import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'player.dart';

class SeriesPage extends ConsumerStatefulWidget {
  const SeriesPage({super.key, required this.series});
  final MediaItem series;
  @override
  ConsumerState<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends ConsumerState<SeriesPage> {
  List<MediaItem>? episodes;
  int? selectedSeason;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      error = null;
      episodes = null;
    });
    try {
      final list = await ref.read(appProvider).episodes(widget.series);
      list.sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.episode.compareTo(b.episode);
      });
      if (mounted) {
        setState(() {
          episodes = list;
          selectedSeason = list.firstOrNull?.season;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = (episodes ?? []).map((e) => e.season).toSet().toList()
      ..sort();
    final visible = (episodes ?? [])
        .where((e) => e.season == selectedSeason)
        .toList();
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff344b32), Color(0xff102019)],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width < 600 ? 80 : 120,
                    height: MediaQuery.sizeOf(context).width < 600 ? 120 : 180,
                    child: widget.series.logo.startsWith('http')
                        ? Image.network(
                            widget.series.logo,
                            semanticLabel: '${widget.series.name} artwork',
                            fit: BoxFit.cover,
                            cacheWidth: 360,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0xff243628),
                              child: Icon(Icons.movie_outlined, size: 40),
                            ),
                          )
                        : const ColoredBox(
                            color: Color(0xff243628),
                            child: Icon(Icons.movie_outlined, size: 40),
                          ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('YOUR NEXT EPISODE'),
                      const SizedBox(height: 10),
                      Text(
                        widget.series.name,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (widget.series.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            widget.series.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (seasons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: SizedBox(
                            width: 290,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              key: ValueKey(selectedSeason),
                              initialValue: selectedSeason,
                              decoration: const InputDecoration(
                                labelText: 'Season',
                              ),
                              items: [
                                for (final s in seasons)
                                  DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      '${s == 0 ? 'Specials' : 'Season $s'} · ${episodes!.where((e) => e.season == s).length} episodes',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => selectedSeason = value),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: error != null
                ? EmptyState(
                    icon: Icons.error_outline,
                    title: 'Couldn’t load episodes',
                    body: error!,
                    action: OutlinedButton(
                      onPressed: load,
                      child: const Text('Retry'),
                    ),
                  )
                : episodes == null
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? const Center(child: Text('No episodes available.'))
                : ListView.separated(
                    key: ValueKey(selectedSeason),
                    padding: const EdgeInsets.all(20),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final episode = visible[i];
                      return FutureBuilder<Map<String, dynamic>>(
                        future: app.store.state(app.current!.id, episode.id),
                        builder: (context, snapshot) {
                          final position =
                              (snapshot.data?['position'] as int?) ?? 0;
                          final duration =
                              (snapshot.data?['duration'] as int?) ??
                              episode.durationSeconds;
                          final complete =
                              duration > 0 && position >= duration * .95;
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: limeColor.withValues(
                                  alpha: .12,
                                ),
                                child: Text(
                                  '${episode.episode > 0 ? episode.episode : i + 1}',
                                ),
                              ),
                              title: Text(
                                episode.name.replaceFirst(
                                  RegExp(r'^S\d+\s*·\s*E\d*\s*'),
                                  '',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (episode.description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        episode.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Text(
                                    complete
                                        ? 'Watched'
                                        : position > 0
                                        ? 'Resume at ${position ~/ 60} min'
                                        : duration > 0
                                        ? '${duration ~/ 60} min'
                                        : 'Episode ${episode.episode > 0 ? episode.episode : i + 1}',
                                  ),
                                  if (position > 0 && duration > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: LinearProgressIndicator(
                                        value: (position / duration).clamp(
                                          0,
                                          1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Icon(
                                complete
                                    ? Icons.replay
                                    : Icons.play_circle_outline,
                                color: limeColor,
                              ),
                              onTap: () async {
                                await openMedia(context, episode);
                                if (mounted) setState(() {});
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
