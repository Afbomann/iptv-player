import 'dart:ffi';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/data/database.dart';

void main() {
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
  test('Actual encrypted catalog imports and repeated refreshes', () async {
    final store = LibraryStore(
      LumenDatabase(NativeDatabase.memory()),
      SecretKey(List.filled(32, 7)),
    );
    const source = Source(
      id: 'large',
      name: 'Large',
      kind: SourceKind.m3u,
      url: 'https://test/list',
    );
    try {
      for (final size in [5000, 10000, 10000]) {
        final items = List.generate(
          size,
          (i) => MediaItem(
            id: 'large:$i',
            sourceId: 'large',
            name: 'Channel $i',
            url: 'https://test/live/$i.ts',
            group: 'Group ${i % 20}',
          ),
        );
        final watch = Stopwatch()..start();
        await store.replaceItems(source, items);
        watch.stop();
        final rows = await store.db
            .customSelect('SELECT count(*) AS n FROM item_search')
            .getSingle();
        expect(rows.read<int>('n'), size);
        // Includes real encryption + both SQL indexes, unlike the index-only benchmark.
        // ignore: avoid_print
        print(
          'Encrypted import: $size items in ${watch.elapsedMilliseconds}ms',
        );
      }
    } finally {
      await store.db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
