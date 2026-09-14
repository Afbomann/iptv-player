import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models.dart';
import '../playback/engine.dart';
import '../platform/fullscreen.dart';
import 'common.dart';
import 'track_picker.dart';

class VideoStage extends StatefulWidget {
  const VideoStage({
    super.key,
    required this.item,
    required this.engine,
    required this.opening,
    required this.problem,
    required this.multi,
    required this.onRetry,
    required this.onFavorite,
    required this.onEngine,
    required this.frameRate,
    required this.onFrameRate,
    this.onEpisodes,
  });
  final MediaItem item;
  final PlaybackEngine? engine;
  final bool opening, multi, frameRate;
  final String? problem;
  final VoidCallback onRetry, onFavorite;
  final Future<void> Function(EngineKind) onEngine;
  final Future<void> Function() onFrameRate;
  final Future<void> Function()? onEpisodes;
  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  bool visible = true, menu = false;
  Timer? hide;
  final videoFocus = FocusNode();

  void togglePlayback() {
    reveal();
    final engine = widget.engine;
    if (!menu && !widget.opening && widget.problem == null && engine != null) {
      unawaited(perform(context, engine.toggle));
    }
  }

  void seekTo(Duration target) {
    final engine = widget.engine;
    if (menu ||
        widget.opening ||
        widget.problem != null ||
        engine == null ||
        widget.item.kind == MediaKind.live ||
        engine.duration <= Duration.zero) {
      return;
    }
    reveal();
    unawaited(
      perform(
        context,
        () => engine.seek(
          Duration(
            milliseconds: target.inMilliseconds.clamp(
              0,
              engine.duration.inMilliseconds,
            ),
          ),
        ),
      ),
    );
  }

  void skip(int seconds) => seekTo(
    (widget.engine?.position ?? Duration.zero) + Duration(seconds: seconds),
  );
  @override
  void initState() {
    super.initState();
    reveal();
  }

  void reveal() {
    hide?.cancel();
    if (mounted && !visible) setState(() => visible = true);
    hide = Timer(const Duration(seconds: 4), () {
      if (mounted && !menu && widget.engine?.playing == true) {
        setState(() => visible = false);
      }
    });
  }

  @override
  void dispose() {
    hide?.cancel();
    videoFocus.dispose();
    super.dispose();
  }

  String time(Duration d) =>
      '${d.inHours > 0 ? '${d.inHours}:' : ''}${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  Future<void> tracks() async {
    final engine = widget.engine;
    if (engine == null) return;
    menu = true;
    reveal();
    await showDialog(
      context: context,
      builder: (_) => TrackPicker(engine: engine),
    );
    if (mounted) {
      menu = false;
      reveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final shown = visible || widget.problem != null || engine?.playing != true;
    return IconButtonTheme(
      data: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(40, 40)),
          maximumSize: WidgetStatePropertyAll(Size(40, 40)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): togglePlayback,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => skip(-10),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => skip(10),
          for (final entry in [
            LogicalKeyboardKey.digit0,
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
            LogicalKeyboardKey.digit5,
            LogicalKeyboardKey.digit6,
            LogicalKeyboardKey.digit7,
            LogicalKeyboardKey.digit8,
            LogicalKeyboardKey.digit9,
          ].asMap().entries)
            SingleActivator(entry.value): () => seekTo(
              Duration(
                milliseconds:
                    ((engine?.duration.inMilliseconds ?? 0) * entry.key / 10)
                        .round(),
              ),
            ),
          const SingleActivator(LogicalKeyboardKey.keyF): () =>
              unawaited(toggleFullscreen()),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
        },
        child: Focus(
          focusNode: videoFocus,
          autofocus: !widget.multi,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) reveal();
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            onHover: (_) => reveal(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: reveal,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (engine != null)
                    KeyedSubtree(
                      key: ObjectKey(engine),
                      child: engine.surface(),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        videoFocus.requestFocus();
                        togglePlayback();
                      },
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                  if (widget.opening && widget.problem == null)
                    const Center(child: CircularProgressIndicator()),
                  if (widget.problem != null)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        padding: const EdgeInsets.all(24),
                        color: Colors.black87,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.primary,
                              size: 36,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.problem!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: widget.onRetry,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      ignoring: !shown,
                      child: AnimatedOpacity(
                        opacity: shown ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 16, 30),
                              child: Row(
                                children: [
                                  if (!widget.multi)
                                    IconButton(
                                      tooltip: 'Close player',
                                      onPressed: () =>
                                          Navigator.maybePop(context),
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        color: Colors.white,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      widget.item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (widget.item.kind == MediaKind.live)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        '● LIVE',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (engine != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: !shown,
                        child: AnimatedOpacity(
                          opacity: shown ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 30, 12, 8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (engine.duration > Duration.zero &&
                                      widget.item.kind != MediaKind.live)
                                    Slider(
                                      value: engine.position.inMilliseconds
                                          .clamp(
                                            0,
                                            engine.duration.inMilliseconds,
                                          )
                                          .toDouble(),
                                      max: engine.duration.inMilliseconds
                                          .toDouble(),
                                      onChangeStart: (_) {
                                        menu = true;
                                        reveal();
                                      },
                                      onChangeEnd: (_) {
                                        menu = false;
                                        reveal();
                                      },
                                      onChanged: (value) => engine.seek(
                                        Duration(milliseconds: value.toInt()),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: engine.playing
                                            ? 'Pause'
                                            : 'Play',
                                        onPressed: () {
                                          reveal();
                                          unawaited(
                                            perform(context, engine.toggle),
                                          );
                                        },
                                        icon: Icon(
                                          engine.playing
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (widget.item.kind != MediaKind.live &&
                                          !widget.multi)
                                        IconButton(
                                          tooltip: 'Back 10 seconds',
                                          onPressed: () => skip(-10),
                                          icon: const Icon(
                                            Icons.replay_10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (widget.item.kind != MediaKind.live &&
                                          !widget.multi)
                                        IconButton(
                                          tooltip: 'Forward 10 seconds',
                                          onPressed: () => skip(10),
                                          icon: const Icon(
                                            Icons.forward_10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          widget.item.kind == MediaKind.live
                                              ? engine.kind.label
                                              : '${time(engine.position)} / ${time(engine.duration)}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Audio and subtitles',
                                        onPressed: tracks,
                                        icon: const Icon(
                                          Icons.subtitles_outlined,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (widget.onEpisodes != null)
                                        IconButton(
                                          tooltip: 'Episodes',
                                          icon: const Icon(
                                            Icons.video_library_outlined,
                                            color: Colors.white,
                                          ),
                                          onPressed: () async {
                                            menu = true;
                                            reveal();
                                            try {
                                              await widget.onEpisodes!();
                                            } finally {
                                              if (mounted) {
                                                menu = false;
                                                reveal();
                                              }
                                            }
                                          },
                                        ),
                                      if (!widget.multi)
                                        PopupMenuButton<String>(
                                          tooltip: 'Player settings',
                                          icon: const Icon(
                                            Icons.settings_outlined,
                                            color: Colors.white,
                                          ),
                                          onOpened: () {
                                            menu = true;
                                            reveal();
                                          },
                                          onCanceled: () {
                                            menu = false;
                                            reveal();
                                          },
                                          onSelected: (value) async {
                                            if (value == 'favorite') {
                                              widget.onFavorite();
                                            } else if (value == 'frameRate') {
                                              await widget.onFrameRate();
                                            } else {
                                              await widget.onEngine(
                                                EngineKind.values.byName(value),
                                              );
                                            }
                                            if (mounted) {
                                              menu = false;
                                              reveal();
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'favorite',
                                              child: Text('Toggle favorite'),
                                            ),
                                            for (final kind in [
                                              EngineKind.automatic,
                                              ...PlaybackCapabilities
                                                  .current
                                                  .engines,
                                            ])
                                              PopupMenuItem(
                                                value: kind.name,
                                                child: Text(
                                                  'Engine · ${kind.label}',
                                                ),
                                              ),
                                            if (PlaybackCapabilities
                                                    .current
                                                    .frameRate &&
                                                engine.kind == EngineKind.mpv)
                                              PopupMenuItem(
                                                value: 'frameRate',
                                                child: Text(
                                                  '${widget.frameRate ? 'Disable' : 'Enable'} frame-rate matching',
                                                ),
                                              ),
                                          ],
                                        ),
                                      IconButton(
                                        tooltip: 'Fullscreen',
                                        onPressed: () {
                                          reveal();
                                          unawaited(toggleFullscreen());
                                        },
                                        icon: const Icon(
                                          Icons.fullscreen,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
