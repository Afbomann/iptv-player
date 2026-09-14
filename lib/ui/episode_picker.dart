import 'package:flutter/material.dart';
import '../core/models.dart';

class EpisodePicker extends StatefulWidget {
  const EpisodePicker({super.key, required this.current, required this.load});
  final MediaItem current;
  final Future<List<MediaItem>> Function() load;
  @override
  State<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<EpisodePicker> {
  late int season = widget.current.season;
  late Future<List<MediaItem>> episodes = widget.load();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Episodes'),
    content: SizedBox(
      width: 580,
      height: 400,
      child: FutureBuilder<List<MediaItem>>(
        future: episodes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() { episodes = widget.load(); }),
                child: const Text('Could not load episodes. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = [...snapshot.data!]
            ..sort((a, b) => a.episode.compareTo(b.episode));
          final seasons = items.map((e) => e.season).toSet().toList()..sort();
          if (seasons.isEmpty) {
            return const Center(child: Text('No episodes available.'));
          }
          final selected = seasons.contains(season) ? season : seasons.first;
          final visible = items.where((e) => e.season == selected).toList();
          return Column(
            children: [
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Season'),
                items: [
                  for (final s in seasons)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s == 0 ? 'Specials' : 'Season $s'),
                    ),
                ],
                onChanged: (value) => setState(() => season = value!),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final episode = visible[i];
                    final current = episode.id == widget.current.id;
                    return ListTile(
                      selected: current,
                      leading: Icon(
                        current ? Icons.equalizer : Icons.play_circle_outline,
                      ),
                      title: Text(
                        episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: current ? const Text('Now playing') : null,
                      onTap: () => Navigator.pop(context, episode),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
