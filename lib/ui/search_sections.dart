import 'package:flutter/material.dart';
import '../core/models.dart';

bool hasSearchArtwork(MediaItem item) {
  final uri = Uri.tryParse(item.logo.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

class SearchSections extends StatelessWidget {
  const SearchSections({
    super.key,
    required this.items,
    required this.controller,
    required this.tile,
    this.compact = false,
  });
  final List<MediaItem> items;
  final ScrollController controller;
  final Widget Function(MediaItem) tile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sections = [('With artwork', true), ('Without artwork', false)];
    final grouped = <bool, List<MediaItem>>{};
    for (final item in items) {
      (grouped[hasSearchArtwork(item)] ??= []).add(item);
    }
    return CustomScrollView(
      controller: controller,
      slivers: [
        for (final section in sections)
          if (grouped.containsKey(section.$2)) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Row(
                  children: [
                    Text(
                      section.$1,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 20),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: compact ? 220 : 300,
                  childAspectRatio: 1.22,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: grouped[section.$2]!.length,
                itemBuilder: (_, index) => tile(grouped[section.$2]![index]),
              ),
            ),
          ],
      ],
    );
  }
}
