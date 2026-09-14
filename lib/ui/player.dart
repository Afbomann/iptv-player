import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../playback/engine.dart';
import '../playback/sessions.dart';
import 'common.dart';
import 'video_stage.dart';
import 'episode_picker.dart';
import '../platform/fullscreen.dart';

Future<void> openMedia(
  BuildContext context,
  MediaItem item, {
  String? url,
  Programme? programme,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlayerPage(items: [item], url: url, programme: programme),
    ),
  );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.items, this.url, this.programme});
  final List<MediaItem> items;
  final String? url;
  final Programme? programme;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  int audible = 0;
  @override
  void dispose() {
    unawaited(leaveFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: widget.items.length == 1
        ? null
        : AppBar(
            backgroundColor: Colors.black,
            title: Text(
              widget.items.length == 1
                  ? widget.items.first.name
                  : 'Multiview · ${widget.items.length} streams',
            ),
            actions: [
              if (widget.items.length > 1)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select a tile for audio',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
    body: LayoutBuilder(
      builder: (context, box) => widget.items.length == 1
          ? PlayerPane(
              item: widget.items.first,
              audible: true,
              multi: false,
              url: widget.url,
              programme: widget.programme,
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: box.maxWidth > 700 ? 2 : 1,
                childAspectRatio: 16 / 11,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, i) => Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: audible == i
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white24,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(
                        widget.items[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        audible == i ? Icons.volume_up : Icons.volume_off,
                      ),
                      onTap: () => setState(() => audible = i),
                    ),
                    Expanded(
                      child: PlayerPane(
                        key: ValueKey(widget.items[i].id),
                        item: widget.items[i],
                        audible: audible == i,
                        multi: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

class PlayerPane extends ConsumerStatefulWidget {
  const PlayerPane({
    super.key,
    required this.item,
    required this.audible,
    required this.multi,
    this.url,
    this.programme,
  });
  final MediaItem item;
  final bool audible, multi;
  final String? url;
  final Programme? programme;
  @override
  ConsumerState<PlayerPane> createState() => _PlayerPaneState();
}

class _PlayerPaneState extends ConsumerState<PlayerPane> {
  late MediaItem item = widget.item;
  PlaybackEngine? engine;
  String? error;
  bool opening = true, closed = false, frameRate = false;
  final owner = const Uuid().v4();
  Timer? saveTimer;
  EngineKind preference = EngineKind.automatic;
  final attempted = <EngineKind>{};
  bool switching = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  @override
  void didUpdateWidget(covariant PlayerPane old) {
    super.didUpdateWidget(old);
    if (old.audible != widget.audible) engine?.volume(widget.audible ? 1 : 0);
  }

  Future<void> start({EngineKind? override, bool fallback = false}) async {
    if (switching || closed) return;
    switching = true;
    var playbackAttempted = false;
    final app = ref.read(appProvider);
    final p = app.current;
    try {
      if (p == null ||
          !await app.store.canPlay(p, item, programme: widget.programme)) {
        throw StateError('This content is restricted by your profile.');
      }
      final source = app.sources
          .where((s) => s.id == item.sourceId)
          .firstOrNull;
      if (closed) return;
      if (source == null) {
        throw StateError('The source is no longer available.');
      }
      if (!SessionPool.shared.acquire(
        owner,
        source.id,
        source.connectionLimit,
      )) {
        throw StateError(
          'Provider connection limit reached. Close a stream or recording first.',
        );
      }
      final channel = await app.store.setting('engine:${item.id}');
      final sourceEngine = await app.store.setting(
        'engine-source:${source.id}',
      );
      final saved =
          channel?['engine'] ??
          sourceEngine?['engine'] ??
          p.preferences['engine'] ??
          'automatic';
      if (!fallback) {
        preference =
            override ??
            EngineKind.values.firstWhere(
              (e) => e.name == saved,
              orElse: () => EngineKind.automatic,
            );
      }
      if (preference != EngineKind.automatic &&
          !PlaybackCapabilities.current.engines.contains(preference)) {
        preference = EngineKind.automatic;
      }
      engine?.removeListener(update);
      if (frameRate) {
        await engine?.frameRate(false);
        frameRate = false;
      }
      await engine?.close();
      engine?.dispose();
      if (closed) return;
      engine = createEngine(fallback ? override! : preference);
      engine!.initialVolume = widget.audible ? 1 : 0;
      attempted.add(engine!.kind);
      engine!.addListener(update);
      setState(() {
        error = null;
        opening = true;
      });
      final state = await app.store.state(p.id, item.id);
      if (closed) return;
      final finished =
          (state['duration'] ?? 0) > 0 &&
          (state['position'] ?? 0) >= (state['duration'] ?? 0) * .95;
      final resume = item.kind == MediaKind.live || finished
          ? Duration.zero
          : Duration(seconds: state['position'] ?? 0);
      playbackAttempted = true;
      await engine!.open(item, url: widget.url, start: resume);
      if (closed) return;
      await engine!.volume(widget.audible ? 1 : 0);
      if (!widget.multi &&
          p.preferences['autoFrameRate'] == true &&
          engine!.kind == EngineKind.mpv) {
        try {
          await engine!.frameRate(true);
          frameRate = true;
        } catch (_) {
          /* Some streams do not report fps until decoding begins. */
        }
      }
      await app.store.setState(p.id, item.id, watched: true);
      saveTimer?.cancel();
      saveTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (closed) return;
        final active = app.current;
        if (active == null ||
            active.id != p.id ||
            !await app.store.canPlay(
              active,
              item,
              programme: widget.programme,
            )) {
          await stopRestricted();
          return;
        }
        if (item.kind != MediaKind.live && engine != null) {
          await app.store.setState(
            p.id,
            item.id,
            position: engine!.position.inSeconds,
            duration: engine!.duration.inSeconds,
            watched: true,
          );
        }
      });
      if (mounted) setState(() => opening = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendlyError(e);
          opening = false;
        });
      }
    } finally {
      switching = false;
      if (!closed &&
          playbackAttempted &&
          preference == EngineKind.automatic &&
          (error != null || engine?.error != null) &&
          engine != null) {
        tryFallback();
      }
    }
  }

  bool tryFallback() {
    if (switching || closed || preference != EngineKind.automatic) return false;
    final next = PlaybackCapabilities.current.engines
        .where((kind) => !attempted.contains(kind))
        .firstOrNull;
    if (next == null) return false;
    unawaited(start(override: next, fallback: true));
    return true;
  }

  Future<void> stopRestricted() async {
    saveTimer?.cancel();
    await engine?.close();
    SessionPool.shared.release(owner);
    if (mounted) {
      setState(() => error = 'Playback stopped because access is restricted.');
    }
  }

  void update() {
    if (!mounted || closed) return;
    if (engine?.error != null &&
        preference == EngineKind.automatic &&
        !switching) {
      if (tryFallback()) return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    closed = true;
    saveTimer?.cancel();
    engine?.removeListener(update);
    if (frameRate) unawaited(engine!.frameRate(false));
    final old = engine;
    if (old != null) {
      unawaited(
        old.close().whenComplete(() {
          old.dispose();
          SessionPool.shared.release(owner);
        }),
      );
    } else {
      SessionPool.shared.release(owner);
    }
    super.dispose();
  }

  Future<void> chooseEpisode() async {
    if (switching || closed) return;
    final app = ref.read(appProvider);
    final chosen = await showDialog<MediaItem>(
      context: context,
      builder: (_) => EpisodePicker(
        current: item,
        load: () async {
          final profile = app.current!;
          final series = await app.store.item(profile, item.parentId);
          if (series == null) {
            throw StateError('Series is no longer available.');
          }
          return app.episodes(series);
        },
      ),
    );
    if (!mounted ||
        closed ||
        switching ||
        chosen == null ||
        chosen.id == item.id) {
      return;
    }
    saveTimer?.cancel();
    if (engine != null && app.current != null) {
      await app.store.setState(
        app.current!.id,
        item.id,
        position: engine!.position.inSeconds,
        duration: engine!.duration.inSeconds,
        watched: true,
      );
    }
    if (!mounted || closed) return;
    setState(() => item = chosen);
    attempted.clear();
    await start();
  }

  @override
  Widget build(BuildContext context) => VideoStage(
    item: item,
    onEpisodes:
        !widget.multi &&
            item.kind == MediaKind.episode &&
            item.parentId.isNotEmpty
        ? chooseEpisode
        : null,
    engine: engine,
    opening: opening,
    problem: error ?? engine?.error,
    multi: widget.multi,
    frameRate: frameRate,
    onRetry: () => start(override: engine?.kind),
    onFavorite: () => ref.read(appProvider).favorite(item),
    onEngine: (kind) async {
      await ref.read(appProvider).preferences({'engine': kind.name});
      attempted.clear();
      await start(override: kind);
    },
    onFrameRate: () async {
      await perform(context, () async {
        await engine?.frameRate(!frameRate);
        await ref.read(appProvider).preferences({'autoFrameRate': !frameRate});
        if (mounted) setState(() => frameRate = !frameRate);
      });
    },
  );
}
