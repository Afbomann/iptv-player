import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/ui/search_sections.dart';

void main() {
  testWidgets('Search separates artwork availability, not media type', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchSections(
            controller: scroll,
            items: const [
              MediaItem(
                id: 'movie',
                sourceId: 's',
                name: 'No poster',
                url: '',
                kind: MediaKind.movie,
              ),
              MediaItem(
                id: 'live',
                sourceId: 's',
                name: 'Channel logo',
                url: '',
                logo: 'https://example.test/logo.png',
              ),
              MediaItem(
                id: 'series',
                sourceId: 's',
                name: 'Series poster',
                url: '',
                kind: MediaKind.series,
                logo: 'https://example.test/cover.png',
              ),
            ],
            tile: (item) => Text(item.name),
          ),
        ),
      ),
    );
    expect(find.text('With artwork'), findsOneWidget);
    expect(find.text('Without artwork'), findsOneWidget);
    expect(find.text('TV channels'), findsNothing);
    final divider = tester.getTopLeft(find.text('Without artwork')).dy;
    expect(tester.getTopLeft(find.text('Channel logo')).dy, lessThan(divider));
    expect(tester.getTopLeft(find.text('Series poster')).dy, lessThan(divider));
    expect(tester.getTopLeft(find.text('No poster')).dy, greaterThan(divider));
  });

  test('Missing, placeholder and invalid artwork URLs are not artwork', () {
    for (final logo in ['', ' ', 'null', 'https://', 'file:///logo.png']) {
      expect(
        hasSearchArtwork(
          MediaItem(id: 'i', sourceId: 's', name: 'Item', url: '', logo: logo),
        ),
        false,
      );
    }
  });
}
