import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/data/database.dart';

void main() {
  test('50k catalog / 1m programme indexed query benchmark', () async {
    final folder = await Directory.systemTemp.createTemp('lumen-benchmark-');
    final db = LumenDatabase(
      NativeDatabase(File('${folder.path}/library.sqlite')),
    );
    final baseline = ProcessInfo.currentRss;
    try {
      await db.customSelect('SELECT 1').get();
      await db.customStatement('PRAGMA cache_size=-4096');
      final importTimer = Stopwatch()..start();
      await db.customStatement(
        "WITH RECURSIVE c(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM c WHERE n<50000) INSERT INTO items SELECT 'ch'||n,'source','Channel '||n,'live','Group '||(n%30),0,'epg'||n,'','{}' FROM c",
      );
      await db.customStatement(
        'INSERT INTO item_search(id,name,category) SELECT id,name,category FROM items',
      );
      await db.customStatement(
        "WITH RECURSIVE c(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM c WHERE n<1000000) INSERT INTO programmes SELECT 'p'||n,'source','epg'||(1+n%50000),'Programme '||n,(n/50000)*3600000,(1+n/50000)*3600000,0,'{}' FROM c",
      );
      await db.customStatement(
        'INSERT INTO programme_search(id,title) SELECT id,title FROM programmes',
      );
      importTimer.stop();
      final search = <double>[], guide = <double>[];
      for (var n = 0; n < 100; n++) {
        final timer = Stopwatch()..start();
        await db
            .customSelect(
              'SELECT i.id FROM items i WHERE i.id IN (SELECT id FROM item_search WHERE item_search MATCH ?) ORDER BY i.name LIMIT 60',
              variables: [
                Variable.withString('"Channel" AND "${1000 + n * 137}"'),
              ],
            )
            .get();
        search.add(timer.elapsedMicroseconds / 1000);
        timer.reset();
        await db
            .customSelect(
              'SELECT id FROM programmes WHERE source=? AND channel=? AND end>? AND start<? ORDER BY start LIMIT 100',
              variables: [
                Variable.withString('source'),
                Variable.withString('epg${1000 + n * 137}'),
                Variable.withInt(0),
                Variable.withInt(10800000),
              ],
            )
            .get();
        guide.add(timer.elapsedMicroseconds / 1000);
      }
      search.sort();
      guide.sort();
      final result = {
        'catalogItems': 50000,
        'programmes': 1000000,
        'seedSeconds': importTimer.elapsedMilliseconds / 1000,
        'searchP95Ms': search[94],
        'guideP95Ms': guide[94],
        'rssDeltaMB': (ProcessInfo.currentRss - baseline) / 1048576,
        'scope':
            'SQLite index query latency only; synthetic payloads; Flutter test process; not end-to-end device playback performance',
      };
      await Directory('build').create(recursive: true);
      await File(
        'build/benchmark.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      // ignore: avoid_print
      print(jsonEncode(result));
      expect(search[94], lessThan(200));
      expect(guide[94], lessThan(200));
    } finally {
      await db.close();
      await folder.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
