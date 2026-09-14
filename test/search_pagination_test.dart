import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/controller.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/data/database.dart';
import 'package:lumen_iptv/ui/library.dart';
import 'package:lumen_iptv/ui/search_sections.dart';

class _SearchStore implements LibraryStore {
  final offsets = <int>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #browse) {
      final offset = invocation.namedArguments[#offset] as int;
      offsets.add(offset);
      return Future.value(
        List.generate(
          offset == 0 ? 60 : 10,
          (i) => MediaItem(
            id: '${offset + i}',
            sourceId: 's',
            name: 'Result ${offset + i}',
            url: '',
            logo: i.isEven ? 'https://example.test/logo.png' : '',
          ),
        ),
      );
    }
    if (invocation.memberName == #groups) return Future.value(<String>[]);
    if (invocation.memberName == #searchProgrammes) {
      return Future.value(<(MediaItem, Programme)>[]);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets(
    'Grouped search never inserts another page above the scroll anchor',
    (tester) async {
      final store = _SearchStore();
      final app = AppController(store)
        ..current = const Profile(
          id: 'p',
          name: 'Admin',
          passwordHash: '',
          admin: true,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => app)],
          child: const MaterialApp(
            home: Scaffold(
              body: CatalogPage(title: 'Search', query: 'Result'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var sections = tester.widget<SearchSections>(find.byType(SearchSections));
      sections.controller.jumpTo(sections.controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(store.offsets, [0]);
      expect(sections.items.length, 60);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      sections = tester.widget<SearchSections>(find.byType(SearchSections));
      expect(store.offsets, [0, 60]);
      expect(sections.items.first.id, '60');
      expect(sections.items.length, 10);
      expect(sections.controller.offset, 0);
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      sections = tester.widget<SearchSections>(find.byType(SearchSections));
      expect(store.offsets, [0, 60, 0]);
      expect(sections.items.first.id, '0');
      expect(sections.controller.offset, 0);
    },
  );
}
