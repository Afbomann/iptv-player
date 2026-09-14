import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../playback/engine.dart';
import 'common.dart';
import 'channel_logo.dart';
import 'player.dart';

class GuidePage extends ConsumerStatefulWidget {
  const GuidePage({
    super.key,
    this.group,
    this.source,
    this.favorites = false,
    this.onCategories,
  });
  final String? group, source;
  final bool favorites;
  final VoidCallback? onCategories;
  @override
  ConsumerState<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends ConsumerState<GuidePage> {
  DateTime from = DateTime.now().subtract(
    Duration(minutes: DateTime.now().minute % 30),
  );
  int page = 0;
  final channelFilter = TextEditingController();
  String channelQuery = '';
  Timer? filterTimer;
  @override
  void dispose() {
    filterTimer?.cancel();
    channelFilter.dispose();
    super.dispose();
  }

  void filterChannels(String value) {
    filterTimer?.cancel();
    filterTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          channelQuery = value.trim();
          page = 0;
        });
      }
    });
  }

  Object? channelKey;
  Future<List<MediaItem>>? channelFuture;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final nextKey = (
      app.revision,
      channelQuery,
      page,
      widget.group,
      widget.source,
      widget.favorites,
      app.current!.id,
    );
    if (channelKey != nextKey) {
      channelKey = nextKey;
      channelFuture = app.store.browse(
        app.current!,
        kind: MediaKind.live,
        query: channelQuery,
        group: widget.group,
        source: widget.source,
        favorites: widget.favorites,
        offset: page * 50,
        limit: 50,
      );
    }
    final until = from.add(const Duration(hours: 3));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 250,
                child: TextField(
                  controller: channelFilter,
                  decoration: InputDecoration(
                    labelText: 'Filter channels',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: channelQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear channel filter',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              channelFilter.clear();
                              filterChannels('');
                            },
                          ),
                  ),
                  onChanged: filterChannels,
                ),
              ),
              if (widget.onCategories != null)
                TextButton.icon(
                  onPressed: widget.onCategories,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Categories'),
                ),
              Text(
                widget.group ??
                    (widget.favorites
                        ? 'Favorites'
                        : 'A window into what’s on.'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous three hours',
                    onPressed: () => setState(
                      () => from = from.subtract(const Duration(hours: 3)),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => from = DateTime.now().subtract(
                        Duration(minutes: DateTime.now().minute % 30),
                      ),
                    ),
                    child: const Text('Now'),
                  ),
                  Text(
                    DateFormat('EEE d MMM · HH:mm').format(from),
                    style: const TextStyle(fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Next three hours',
                    onPressed: () => setState(
                      () => from = from.add(const Duration(hours: 3)),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: channelFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final channels = snapshot.data!;
              if (channels.isEmpty) {
                return EmptyState(
                  icon: Icons.calendar_view_week,
                  title: channelQuery.isNotEmpty
                      ? 'No matching channels.'
                      : 'Your guide is waiting.',
                  body: channelQuery.isNotEmpty
                      ? 'Try another channel name or clear the filter.'
                      : 'Add a live TV playlist and an XMLTV guide in Settings.',
                );
              }
              return LayoutBuilder(
                builder: (context, box) {
                  final channelWidth = box.maxWidth < 700 ? 170.0 : 230.0;
                  final timeWidth = (box.maxWidth - channelWidth).clamp(
                    720.0,
                    1800.0,
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: channelWidth + timeWidth,
                      child: Column(
                        children: [
                          Container(
                            height: 42,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: channelWidth,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 18),
                                    child: Text(
                                      'CHANNEL',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1.6,
                                        color: mutedColor,
                                      ),
                                    ),
                                  ),
                                ),
                                for (var i = 0; i < 6; i++)
                                  SizedBox(
                                    width: timeWidth / 6,
                                    child: Text(
                                      DateFormat('HH:mm').format(
                                        from.add(Duration(minutes: i * 30)),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: mutedColor,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemExtent: 82,
                              itemCount: channels.length,
                              itemBuilder: (context, i) => GuideRow(
                                key: ValueKey(
                                  '${channels[i].id}:$from:${app.revision}',
                                ),
                                item: channels[i],
                                from: from,
                                until: until,
                                channelWidth: channelWidth,
                                timeWidth: timeWidth,
                                index: page * 50 + i + 1,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: page > 0
                                    ? () => setState(() => page--)
                                    : null,
                                child: const Text('← Previous channels'),
                              ),
                              Text(
                                'Page ${page + 1}',
                                style: const TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                              TextButton(
                                onPressed: channels.length == 50
                                    ? () => setState(() => page++)
                                    : null,
                                child: const Text('More channels →'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class GuideRow extends ConsumerStatefulWidget {
  const GuideRow({
    super.key,
    required this.item,
    required this.from,
    required this.until,
    required this.channelWidth,
    required this.timeWidth,
    required this.index,
  });
  final MediaItem item;
  final DateTime from, until;
  final double channelWidth, timeWidth;
  final int index;
  @override
  ConsumerState<GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends ConsumerState<GuideRow> {
  late Future<List<Programme>> future;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<Programme>> load() async {
    final app = ref.read(appProvider);
    final mapping = await app.store.setting('epg-map:${widget.item.id}');
    return app.store.guide(
      app.current!,
      widget.item,
      widget.from,
      widget.until,
      mapping: mapping?['channel'],
    );
  }

  Future<void> mapping() async {
    final app = ref.read(appProvider);
    if (app.current?.admin != true) return;
    final controller = TextEditingController(text: widget.item.epgId);
    final answer = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Map this channel to EPG'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'XMLTV channel ID'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (answer == true) {
      await app.store.setSetting('epg-map:${widget.item.id}', {
        'channel': controller.text.trim(),
      });
      if (mounted) setState(() => future = load());
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: widget.channelWidth,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: ChannelLogo(url: widget.item.logo),
          minLeadingWidth: 36,
          horizontalTitleGap: 8,
          title: Text(
            widget.item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${widget.index.toString().padLeft(3, '0')}  ·  ${widget.item.group}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: mutedColor),
          ),
          onTap: () => openMedia(context, widget.item),
          onLongPress: mapping,
        ),
      ),
      SizedBox(
        width: widget.timeWidth,
        child: FutureBuilder(
          future: future,
          builder: (context, snapshot) {
            final programs = snapshot.data ?? [];
            if (programs.isEmpty) {
              return Container(
                margin: const EdgeInsets.all(3),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainer.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No guide information · hold channel to map EPG',
                  style: TextStyle(fontSize: 11, color: mutedColor),
                ),
              );
            }
            return Stack(
              children: [
                for (final p in programs)
                  Positioned(
                    left:
                        (p.start.difference(widget.from).inSeconds /
                                10800 *
                                widget.timeWidth)
                            .clamp(0, widget.timeWidth),
                    top: 3,
                    bottom: 3,
                    width:
                        ((p.end.isAfter(widget.until) ? widget.until : p.end)
                                    .difference(
                                      p.start.isBefore(widget.from)
                                          ? widget.from
                                          : p.start,
                                    )
                                    .inSeconds /
                                10800 *
                                widget.timeWidth)
                            .clamp(1, widget.timeWidth),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Material(
                        color: p.isNow
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .14)
                            : Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => programmeDetails(
                            context,
                            ref.read(appProvider),
                            widget.item,
                            p,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: p.isNow
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${DateFormat.Hm().format(p.start.toLocal())} – ${DateFormat.Hm().format(p.end.toLocal())}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: mutedColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

Future<void> programmeDetails(
  BuildContext context,
  AppController app,
  MediaItem channel,
  Programme p,
) async {
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(p.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${channel.name} · ${DateFormat('EEE d MMM, HH:mm').format(p.start.toLocal())}',
                style: const TextStyle(color: mutedColor),
              ),
              const SizedBox(height: 18),
              Text(
                p.description.isEmpty
                    ? 'No programme description is available.'
                    : p.description,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
        if (PlaybackCapabilities.current.recording &&
            p.end.isAfter(DateTime.now()))
          TextButton.icon(
            icon: const Icon(
              Icons.fiber_manual_record,
              color: Colors.redAccent,
              size: 15,
            ),
            label: const Text('Record'),
            onPressed: () async {
              if (await perform(
                c,
                () => app.recording.schedule(
                  app.current!,
                  channel,
                  p.start,
                  p.end,
                  title: p.title,
                  programme: p,
                ),
                success: 'Recording scheduled. Keep this device available.',
              )) {
                if (c.mounted) Navigator.pop(c);
              }
            },
          ),
        if (p.isNow)
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              openMedia(context, channel, programme: p);
            },
            child: const Text('Watch live'),
          )
        else if (p.start.isBefore(DateTime.now()) && channel.catchupDays > 0)
          FilledButton(
            onPressed: () async {
              await perform(c, () async {
                final source = app.sources.firstWhere(
                  (s) => s.id == channel.sourceId,
                );
                final url = app.providers.catchupUrl(source, channel, p);
                Navigator.pop(c);
                await openMedia(context, channel, url: url, programme: p);
              });
            },
            child: const Text('Watch catch-up'),
          ),
      ],
    ),
  );
}
