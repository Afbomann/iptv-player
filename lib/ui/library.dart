import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'player.dart';
import 'settings.dart';
import 'item_actions.dart';
import 'guide.dart';
import 'series.dart';

Future<void> showItem(
  BuildContext context,
  AppController app,
  MediaItem item,
) async {
  if (item.kind != MediaKind.series) {
    await openMedia(context, item);
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => SeriesPage(series: item)),
  );
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final profile = app.current!;
    final padding = MediaQuery.sizeOf(context).width < 700 ? 20.0 : 36.0;
    final rows = List<String>.from(
      profile.preferences['homeRows'] ??
          ['Continue watching', 'Your favorites', 'Live now', 'Movie night'],
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, 12, padding, 36),
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff3e5235), Color(0xff243628), Color(0xff19251e)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -55,
                top: -80,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: limeColor.withValues(alpha: .08),
                      width: 50,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(padding + 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Settle in. Stay curious.'),
                    const SizedBox(height: 20),
                    Text(
                      'Your next good\nevening starts here.',
                      style: TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: MediaQuery.sizeOf(context).width < 700
                            ? 39
                            : 56,
                        height: 1.02,
                        color: const Color(0xffeff3e3),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      app.sources.isEmpty
                          ? 'Bring your own playlist. Make this space yours.'
                          : 'Welcome back, ${profile.name}. There’s always something on.',
                      style: const TextStyle(
                        color: Color(0xffc1cdb9),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => app.sources.isEmpty
                              ? (profile.admin
                                    ? showSourceDialog(context, app)
                                    : onNavigate(1))
                              : onNavigate(1),
                          icon: Icon(
                            app.sources.isEmpty ? Icons.add : Icons.play_arrow,
                          ),
                          label: Text(
                            app.sources.isEmpty
                                ? 'Add a playlist'
                                : 'Explore live TV',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => onNavigate(2),
                          icon: const Icon(Icons.calendar_view_week_outlined),
                          label: const Text('Open the guide'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (app.sources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_outlined, color: limeColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A library that feels like yours',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        profile.admin
                            ? 'Connect an M3U playlist or Xtream account. Your channels, films, and series will appear here, ready to explore.'
                            : 'Your administrator can add playlists in Settings. Your favorites and watch history will stay personal.',
                        style: const TextStyle(color: mutedColor, height: 1.7),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        for (final row in rows)
          HomeRow(
            key: ValueKey('$row:${app.revision}'),
            title: row,
            onSeeAll: () => onNavigate(
              row == 'Your favorites'
                  ? 5
                  : row == 'Movie night'
                  ? 3
                  : 1,
            ),
          ),
      ],
    );
  }
}

class HomeRow extends ConsumerStatefulWidget {
  const HomeRow({super.key, required this.title, required this.onSeeAll});
  final String title;
  final VoidCallback onSeeAll;
  @override
  ConsumerState<HomeRow> createState() => _HomeRowState();
}

class _HomeRowState extends ConsumerState<HomeRow> {
  late final Future<List<MediaItem>> items;
  @override
  void initState() {
    super.initState();
    final app = ref.read(appProvider);
    items = app.store.browse(
      app.current!,
      limit: 12,
      kind: widget.title == 'Live now'
          ? MediaKind.live
          : widget.title == 'Movie night'
          ? MediaKind.movie
          : null,
      favorites: widget.title == 'Your favorites',
      recent: widget.title == 'Continue watching',
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: items,
    builder: (context, snapshot) {
      final list = snapshot.data ?? [];
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onSeeAll,
                  child: const Text('Explore →'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 205,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) => SizedBox(
                  width: 236,
                  child: MediaTile(
                    item: list[i],
                    onTap: () =>
                        showItem(context, ref.read(appProvider), list[i]),
                    onFavorite: () => ref.read(appProvider).favorite(list[i]),
                    onMore: () =>
                        itemActions(context, ref.read(appProvider), list[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({
    super.key,
    required this.title,
    this.kind,
    this.query = '',
    this.favorites = false,
  });
  final String title, query;
  final MediaKind? kind;
  final bool favorites;
  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  List<MediaItem> items = [];
  List<(MediaItem, Programme)> programmeResults = [];
  List<String> groups = [];
  String? group, source, error;
  bool loading = false, more = true, multi = false;
  bool showEpisodes = false;
  bool get globalSearch =>
      widget.query.isNotEmpty && widget.kind == null && !widget.favorites;
  int revision = -1, generation = 0;
  final selected = <String, MediaItem>{};
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 600 && more && !loading) load();
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    generation++;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CatalogPage old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind ||
        old.favorites != widget.favorites ||
        old.query != widget.query) {
      revision = -1;
      group = null;
      source = null;
    }
  }

  Future<void> load({bool reset = false}) async {
    if (loading && !reset) return;
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        items = [];
        more = true;
        selected.clear();
      }
    });
    final app = ref.read(appProvider);
    try {
      final custom = Map<String, dynamic>.from(
        app.current!.preferences['customGroups'] ?? {},
      );
      final isCustom = group?.startsWith('My group · ') == true;
      final values = await app.store.browse(
        app.current!,
        kind: widget.kind,
        query: widget.query,
        includeEpisodes: !globalSearch || showEpisodes,
        favorites: widget.favorites,
        group: isCustom ? null : group,
        ids: isCustom
            ? List<String>.from(custom[group!.substring(11)] ?? [])
            : null,
        source: source,
        offset: items.length,
      );
      final categories = await app.store.groups(
        app.current!,
        kind: widget.kind,
        source: source,
      );
      categories.insertAll(0, custom.keys.map((g) => 'My group · $g'));
      final programmes =
          widget.query.isEmpty ||
              widget.kind != null ||
              widget.favorites ||
              source != null ||
              group != null
          ? <(MediaItem, Programme)>[]
          : await app.store.searchProgrammes(app.current!, widget.query);
      if (mounted && ticket == generation) {
        setState(() {
          items.addAll(values);
          groups = categories;
          programmeResults = programmes;
          more = values.length == 60;
        });
      }
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    if (revision != app.revision) {
      revision = app.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load(reset: true);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (widget.kind == MediaKind.live)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        multi = !multi;
                        selected.clear();
                      }),
                      icon: Icon(multi ? Icons.close : Icons.grid_view),
                      label: Text(multi ? 'Cancel' : 'Multiview'),
                    ),
                  if (multi && selected.length >= 2)
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PlayerPage(items: selected.values.toList()),
                        ),
                      ),
                      child: Text('Watch ${selected.length}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (globalSearch)
                    FilterChip(
                      label: const Text('Show episodes'),
                      selected: showEpisodes,
                      onSelected: (value) {
                        setState(() => showEpisodes = value);
                        load(reset: true);
                      },
                    ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: group ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Group'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All groups'),
                        ),
                        for (final g in groups)
                          DropdownMenuItem(
                            value: g,
                            child: Text(g, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        group = v == '' ? null : v;
                        load(reset: true);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
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
                            child: Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        source = v == '' ? null : v;
                        load(reset: true);
                      },
                    ),
                  ),
                ],
              ),
              if (multi)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Select 2–4 channels. Each uses a provider connection.',
                    style: TextStyle(color: mutedColor),
                  ),
                ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (programmeResults.isNotEmpty)
          SizedBox(
            height: 180,
            child: ListView.builder(
              itemCount: programmeResults.length,
              itemBuilder: (context, i) {
                final result = programmeResults[i];
                return ListTile(
                  leading: const Icon(Icons.calendar_view_week),
                  title: Text(result.$2.title),
                  subtitle: Text(
                    '${result.$1.name} · ${result.$2.start.toLocal()}',
                  ),
                  onTap: () =>
                      programmeDetails(context, app, result.$1, result.$2),
                );
              },
            ),
          ),
        Expanded(
          child: error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Couldn’t load the library',
                  body: error!,
                  action: OutlinedButton(
                    onPressed: () => load(reset: true),
                    child: const Text('Retry'),
                  ),
                )
              : items.isEmpty && !loading
              ? EmptyState(
                  icon: Icons.video_library_outlined,
                  title: widget.favorites
                      ? 'Save something good.'
                      : 'Nothing here yet.',
                  body: widget.query.isNotEmpty
                      ? 'Try another search or change your filters.'
                      : widget.favorites
                      ? 'Use the star on a channel or film to keep it close.'
                      : 'Add a playlist in Settings, or try a different group.',
                )
              : GridView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent:
                        app.current!.preferences['density'] == 'compact'
                        ? 220
                        : 300,
                    childAspectRatio:
                        (widget.kind == MediaKind.movie ||
                            widget.kind == MediaKind.series)
                        ? 0.8
                        : 1.22,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => MediaTile(
                    item: items[i],
                    selected: selected.containsKey(items[i].id),
                    onTap: () {
                      if (multi) {
                        setState(() {
                          if (selected.containsKey(items[i].id)) {
                            selected.remove(items[i].id);
                          } else if (selected.length < 4) {
                            selected[items[i].id] = items[i];
                          }
                        });
                      } else {
                        showItem(context, app, items[i]);
                      }
                    },
                    onFavorite: () => app.favorite(items[i]),
                    onMore: () => itemActions(context, app, items[i]),
                  ),
                ),
        ),
      ],
    );
  }
}
