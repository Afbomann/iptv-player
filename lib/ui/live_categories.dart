import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'guide.dart';
import 'library.dart';

class LiveCategoriesPage extends ConsumerStatefulWidget {
  const LiveCategoriesPage({super.key});
  @override
  ConsumerState<LiveCategoriesPage> createState() => _LiveCategoriesPageState();
}

class _LiveCategoriesPageState extends ConsumerState<LiveCategoriesPage> {
  String? group, source;
  bool opened = false, favorites = false;
  Future<List<String>>? categories;
  int revision = -1;
  final categoryFilter = TextEditingController();
  bool savingFavorite = false;

  @override
  void dispose() {
    categoryFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final favoriteCategories = List<String>.from(
      app.current!.preferences['favoriteCategories'] ?? [],
    );
    String favoriteKey(String category) => jsonEncode([source ?? '', category]);
    bool isFavorite(String category) =>
        favoriteCategories.contains(favoriteKey(category));
    Future<void> toggleFavorite(String category) async {
      if (savingFavorite) return;
      setState(() => savingFavorite = true);
      final next = [...favoriteCategories];
      final key = favoriteKey(category);
      if (!next.remove(key)) next.add(key);
      await perform(
        context,
        () => app.preferences({'favoriteCategories': next}),
      );
      if (mounted) setState(() => savingFavorite = false);
    }

    if (revision != app.revision) {
      revision = app.revision;
      categories = app.store.groups(
        app.current!,
        kind: MediaKind.live,
        source: source,
      );
    }
    final wide = MediaQuery.sizeOf(context).width > 1100;
    void select(String? value, {bool favorite = false}) => setState(() {
      group = value;
      favorites = favorite;
      opened = true;
    });
    final menu = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('LIVE TELEVISION'),
              const SizedBox(height: 10),
              Text(
                'Categories',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose a category to open its TV guide.',
                style: TextStyle(color: mutedColor),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                icon: const Icon(Icons.grid_view),
                label: const Text('Multiview'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Multiview')),
                      body: const CatalogPage(
                        title: 'Choose live channels',
                        kind: MediaKind.live,
                      ),
                    ),
                  ),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: source ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Playlist'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All playlists'),
                  ),
                  for (final s in app.sources.where(
                    (s) =>
                        app.current!.admin ||
                        app.current!.allowedSources.isEmpty ||
                        app.current!.allowedSources.contains(s.id),
                  ))
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  source = value == '' ? null : value;
                  group = null;
                  opened = false;
                  revision = -1;
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: categoryFilter,
                decoration: InputDecoration(
                  labelText: 'Filter categories',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: categoryFilter.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear category filter',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(categoryFilter.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<String>>(
            future: categories,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final query = categoryFilter.text.trim().toLowerCase();
              final entries =
                  [
                        (title: 'All channels', group: null, favorite: false),
                        (title: 'Favorites', group: null, favorite: true),
                        for (final value in [
                          ...snapshot.data!.where(isFavorite),
                          ...snapshot.data!.where(
                            (value) => !isFavorite(value),
                          ),
                        ])
                          (title: value, group: value, favorite: false),
                      ]
                      .where(
                        (entry) => entry.title.toLowerCase().contains(query),
                      )
                      .toList();
              if (entries.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No matching categories.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                key: ValueKey(query),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final title = entry.title;
                  final chosen =
                      opened &&
                      group == entry.group &&
                      favorites == entry.favorite;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: chosen,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .12),
                      leading: Icon(
                        entry.favorite ? Icons.star_outline : Icons.live_tv,
                        size: 22,
                      ),
                      title: Text(title),
                      trailing: entry.group == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip:
                                  '${isFavorite(title) ? 'Unfavorite' : 'Favorite'} category $title',
                              icon: Icon(
                                isFavorite(title)
                                    ? Icons.star
                                    : Icons.star_border,
                                color: isFavorite(title)
                                    ? Theme.of(context).colorScheme.primary
                                    : mutedColor,
                              ),
                              onPressed: savingFavorite
                                  ? null
                                  : () => toggleFavorite(title),
                            ),
                      onTap: () =>
                          select(entry.group, favorite: entry.favorite),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
    return PopScope(
      canPop: !opened,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && opened) setState(() => opened = false);
      },
      child: Row(
        children: [
          if (!opened || wide) Expanded(flex: opened ? 2 : 1, child: menu),
          if (opened)
            Expanded(
              flex: 7,
              child: GuidePage(
                key: ValueKey('$source:$group:$favorites'),
                group: group,
                source: source,
                favorites: favorites,
                onCategories: () => setState(() => opened = false),
              ),
            ),
        ],
      ),
    );
  }
}
