import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:lumen_iptv/ui/backup_transfer.dart';
import 'package:sqlite3/open.dart';
import 'package:lumen_iptv/data/database.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/core/controller.dart';
import 'package:lumen_iptv/core/security.dart';
import 'package:lumen_iptv/data/providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
  late LibraryStore store;
  const admin = Profile(
    id: 'admin',
    name: 'Admin',
    passwordHash: 'hash',
    admin: true,
  );
  const child = Profile(
    id: 'child',
    name: 'Child',
    passwordHash: 'hash',
    blockedGroups: ['Adults'],
    maxRating: 12,
    allowUnrated: true,
  );
  const source = Source(
    id: 's',
    name: 'Provider',
    kind: SourceKind.m3u,
    url: 'https://test/playlist?secret=123',
  );
  const items = [
    MediaItem(
      id: 's:one',
      sourceId: 's',
      name: 'Nature live',
      url: 'https://test/live?password=123',
      group: 'Nature',
      epgId: 'nature',
    ),
    MediaItem(
      id: 's:two',
      sourceId: 's',
      name: 'Nature adults',
      url: 'https://test/adult',
      group: 'Adults',
      rating: 18,
    ),
  ];
  setUp(() async {
    store = LibraryStore(
      LumenDatabase(NativeDatabase.memory()),
      SecretKey(List.filled(32, 7)),
    );
    await store.saveProfile(admin);
    await store.saveProfile(child);
    await store.replaceItems(source, items);
  });
  test(
    'Controller backup restores portable files and resets busy state after failures',
    () async {
      final app = AppController(store)..current = admin;
      app.profiles = await store.profiles();
      addTearDown(app.dispose);
      await store.setSetting('file:s', {
        'encrypted': await Security.seal('#EXTM3U', store.key),
      });
      final backup = await app.exportBackup('backup passphrase');
      expect(app.backupBusy, false);
      await store.setSetting('new-setting', {'value': true});
      final before = await store.exportData();
      await expectLater(
        app.restoreBackup('invalid', 'backup passphrase'),
        throwsFormatException,
      );
      expect(await store.exportData(), before);
      expect(app.backupBusy, false);
      expect(app.recording.suspended, false);
      await app.restoreBackup(backup, 'backup passphrase');
      expect(app.current, isNull);
      expect(app.backupBusy, false);
      expect(await store.setting('new-setting'), isNull);
      final file = await store.setting('file:s');
      expect(await Security.open(file!['encrypted'], store.key), '#EXTM3U');
      expect(await store.setting('rollback'), isNotNull);
      expect(
        await store.exportData(),
        isNot(contains('lumen-backup-v2-device-key')),
      );
    },
  );
  testWidgets(
    'Closing the backup password dialog does not dispose a live field',
    (tester) async {
      final app = AppController(store)..current = admin;
      app.profiles = [admin];
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => transferBackup(context, app),
                child: const Text('Backup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'backup passphrase');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  test(
    'Releasing SQLite memory preserves the library and user state',
    () async {
      await store.setState(admin.id, items.first.id, favorite: true);
      final before = await store.exportData();
      await store.releaseMemory();
      expect(await store.exportData(), before);
      expect(
        (await store.browse(admin, favorites: true)).single.id,
        items.first.id,
      );
    },
  );
  test(
    'Backup lock rejects conflicting controller mutations without writes',
    () async {
      final app = AppController(store)..current = admin;
      app.profiles = [admin, child];
      app.backupBusy = true;
      addTearDown(app.dispose);
      final before = await store.exportData();
      for (final action in <Future<void> Function()>[
        () => app.addSource(source),
        () => app.updateSource(source),
        () => app.removeSource(source),
        () => app.createAdmin('Admin', 'password'),
        () => app.createUser('User', '1234'),
        () => app.updateUser(child),
        () => app.resetUserPin(child, '1234'),
        () => app.setDiscoverable(child, false),
        () => app.deleteUser(child),
        () => app.login(admin, 'password'),
        () => app.loginByName('Child', '1234'),
        () => app.preferences({'accent': 1}),
        () => app.favorite(items.first),
        () async {
          await app.episodes(items.first);
        },
      ]) {
        await expectLater(action(), throwsStateError);
      }
      expect(app.logout, throwsStateError);
      expect(app.current, admin);
      expect(await store.exportData(), before);
    },
  );
  for (final kind in [SourceKind.m3u, SourceKind.file]) {
    test(
      '$kind migrates legacy items and invalidates orphan-only recovery once',
      () async {
        const playlist = '#EXTM3U\n#EXTINF:-1,Channel\nhttps://test/stream\n';
        final providerSource = Source.fromJson({
          ...source.toJson(),
          'kind': kind.name,
        });
        final incoming = parseM3u({
          'source': source.id,
          'text': playlist,
        }).single;
        final legacyId = stableId(source.id, '|Channel|Ungrouped|/stream');
        await store.replaceItems(providerSource, [
          MediaItem.fromJson({...incoming.toJson(), 'id': legacyId}),
        ]);
        await store.setState(child.id, legacyId, favorite: true, position: 25);
        await store.saveProfile(
          Profile.fromJson({
            ...child.toJson(),
            'blockedChannels': [legacyId],
          }),
        );
        await store.saveRecording({
          'id': 'job',
          'source': source.id,
          'item': legacyId,
          'status': 'scheduled',
        });
        final migrated = await store.replaceItems(providerSource, [incoming]);
        expect(migrated.referencesChanged, isTrue);
        expect((await store.state(child.id, incoming.id))['position'], 25);
        expect((await store.recordings()).single['item'], incoming.id);
        expect(
          (await store.profiles())
              .firstWhere((p) => p.id == child.id)
              .allows(incoming),
          isFalse,
        );

        // Simulate an earlier refresh having replaced the catalog but left references behind.
        await store.setState(child.id, legacyId, favorite: true);
        await store.saveProfile(
          Profile.fromJson({
            ...child.toJson(),
            'blockedChannels': [legacyId],
            'preferences': {
              'customGroups': {
                'Saved': [legacyId],
              },
            },
          }),
        );
        if (kind == SourceKind.file) {
          await store.setSetting('file:${source.id}', {
            'encrypted': await Security.seal(playlist, store.key),
          });
        }
        final app = AppController(
          store,
          providers: ProviderClient(
            client: MockClient((_) async => http.Response(playlist, 200)),
          ),
        )..current = child;
        addTearDown(app.dispose);
        final revision = app.revision;
        await app.refreshDue(force: true);
        expect(app.refreshError, isNull);
        expect(
          app.refreshSummary,
          contains('0 added · 0 changed · 0 removed · 1 unchanged'),
        );
        expect(app.revision, revision + 1);
        expect(app.current!.allows(incoming), isFalse);
        expect(app.current!.preferences['customGroups']['Saved'], [
          incoming.id,
        ]);
        await app.refreshDue(force: true);
        expect(app.revision, revision + 1);
        expect(
          (await store.replaceItems(providerSource, [
            incoming,
          ])).referencesChanged,
          isFalse,
        );
      },
    );
  }
  test(
    'M3U identity migration preserves references and blocks all legacy variants',
    () async {
      final incoming = parseM3u({
        'source': source.id,
        'text':
            '#EXTM3U\n#EXTINF:-1 tvg-id="news" group-title="TV",News\nhttps://a.test/play?id=1\n'
            '#EXTINF:-1 tvg-id="news" group-title="TV",News\nhttps://a.test/play?id=2',
      });
      final legacyId = stableId(source.id, 'news|News|TV|/play');
      final legacy = MediaItem.fromJson({
        ...incoming.last.toJson(),
        'id': legacyId,
      });
      await store.replaceItems(source, [legacy]);
      await store.setState(
        child.id,
        legacyId,
        favorite: true,
        position: 42,
        duration: 100,
      );
      await store.saveProfile(
        Profile.fromJson({
          ...child.toJson(),
          'blockedChannels': [legacyId],
          'preferences': {
            'customGroups': {
              'News': [legacyId],
            },
          },
        }),
      );
      await store.setSetting('engine:$legacyId', {'engine': 'mpv'});
      await store.setSetting('epg-map:$legacyId', {'channel': 'news'});
      await store.saveRecording({
        'id': 'job',
        'source': source.id,
        'item': legacyId,
        'status': 'scheduled',
      });
      await store.replaceItems(source, incoming);
      expect((await store.state(child.id, incoming.last.id))['favorite'], 1);
      expect((await store.state(child.id, incoming.last.id))['position'], 42);
      expect((await store.recordings()).single['item'], incoming.last.id);
      final migrated = (await store.profiles()).firstWhere(
        (p) => p.id == child.id,
      );
      expect(incoming.every((item) => !migrated.allows(item)), isTrue);
      expect(
        migrated.preferences['customGroups']['News'],
        containsAll(incoming.map((i) => i.id)),
      );
      expect(await store.setting('engine:${incoming.last.id}'), {
        'engine': 'mpv',
      });
      expect(await store.setting('epg-map:${incoming.last.id}'), {
        'channel': 'news',
      });
      final before = await store.exportData();
      final delta = await store.replaceItems(source, incoming);
      expect(delta.unchanged, 2);
      expect(await store.exportData(), before);
    },
  );

  test(
    'Orphaned ambiguous references fail safely and migration rolls back with refresh',
    () async {
      final incoming = parseM3u({
        'source': source.id,
        'text':
            '#EXTM3U\n#EXTINF:-1,News\nhttps://a.test/play?id=1\n#EXTINF:-1,News\nhttps://b.test/play?id=2',
      });
      final legacyId = stableId(source.id, '|News|Ungrouped|/play');
      await store.setState(child.id, legacyId, favorite: true);
      await store.saveProfile(
        Profile.fromJson({
          ...child.toJson(),
          'blockedChannels': [legacyId],
        }),
      );
      await store.saveRecording({
        'id': 'ambiguous',
        'source': source.id,
        'item': legacyId,
        'status': 'scheduled',
      });
      await expectLater(
        store.replaceItems(
          source,
          incoming,
          onProgress: (_, _) => throw StateError('rollback'),
        ),
        throwsStateError,
      );
      expect((await store.state(child.id, legacyId))['favorite'], 1);
      expect((await store.recordings()).single['status'], 'scheduled');
      await store.replaceItems(source, incoming);
      final job = (await store.recordings()).single;
      expect(job['status'], 'failed');
      expect(job['error'], contains('ambiguous'));
      for (final item in incoming) {
        expect((await store.state(child.id, item.id))['favorite'], 1);
        expect(
          (await store.profiles())
              .firstWhere((p) => p.id == child.id)
              .allows(item),
          isFalse,
        );
      }
    },
  );
  tearDown(() async => store.db.close());
  test(
    'FTS policy filters before pagination and encrypted URLs stay out of storage',
    () async {
      expect(await store.browse(child, query: 'Nature'), hasLength(1));
      expect(await store.browse(admin, query: 'Nature'), hasLength(2));
      expect(await store.item(child, 's:two'), isNull);
      final raw = await store.db
          .customSelect('SELECT payload FROM items')
          .get();
      expect(
        raw.first.read<String>('payload'),
        isNot(contains('password=123')),
      );
    },
  );
  test(
    'Refreshing preserves favorites and removes obsolete search results',
    () async {
      await store.setState(child.id, items.first.id, favorite: true);
      await store.replaceItems(source, [items.first]);
      expect(await store.browse(child, favorites: true), hasLength(1));
      expect(await store.browse(admin, query: 'adults'), isEmpty);
    },
  );
  test(
    'Delta refresh leaves unchanged ciphertext and writes only additions/changes/deletions',
    () async {
      final before =
          (await store.db
                  .customSelect("SELECT payload FROM items WHERE id='s:one'")
                  .getSingle())
              .read<String>('payload');
      final unchanged = await store.replaceItems(source, items);
      expect(unchanged.unchanged, 2);
      expect(unchanged.updated + unchanged.added + unchanged.deleted, 0);
      expect(
        (await store.db
                .customSelect("SELECT payload FROM items WHERE id='s:one'")
                .getSingle())
            .read<String>('payload'),
        before,
      );
      final changed = MediaItem.fromJson({
        ...items.first.toJson(),
        'name': 'Updated channel',
      });
      const added = MediaItem(
        id: 's:new',
        sourceId: 's',
        name: 'New channel',
        url: 'https://test/new',
      );
      final delta = await store.replaceItems(source, [changed, added]);
      expect([delta.added, delta.updated, delta.deleted], [1, 1, 1]);
      expect(await store.browse(admin, query: 'Updated'), hasLength(1));
      expect(await store.browse(admin, query: 'adults'), isEmpty);
    },
  );
  test(
    'EPG delta updates changed titles and deletes vanished programmes',
    () async {
      final now = DateTime.now();
      final p = Programme(
        id: 'p',
        sourceId: 's',
        channelId: 'nature',
        title: 'Original',
        start: now,
        end: now.add(const Duration(hours: 1)),
      );
      await store.replaceEpg('s', [p]);
      expect((await store.replaceEpg('s', [p])).unchanged, 1);
      final edited = Programme.fromJson({...p.toJson(), 'title': 'Changed'});
      expect((await store.replaceEpg('s', [edited])).updated, 1);
      expect((await store.replaceEpg('s', [])).deleted, 1);
      expect(
        (await store.db
                .customSelect('SELECT count(*) AS n FROM programme_search')
                .getSingle())
            .read<int>('n'),
        0,
      );
    },
  );
  test(
    'Missing fingerprints seed hashes without replacing existing catalog rows',
    () async {
      final before = await store.db
          .customSelect('SELECT payload FROM items ORDER BY id')
          .get();
      await store.db.customStatement('DELETE FROM sync_hashes');
      final delta = await store.replaceItems(source, items);
      expect(
        [delta.added, delta.updated, delta.deleted, delta.unchanged],
        [0, 0, 0, 2],
      );
      final after = await store.db
          .customSelect('SELECT payload FROM items ORDER BY id')
          .get();
      expect(after.map((r) => r.data), before.map((r) => r.data));
      expect((await store.replaceItems(source, items)).unchanged, 2);
    },
  );
  test(
    'Progress and unchanged refresh do not invalidate views; failed catalog does not advance timestamp',
    () async {
      var failed = false;
      final provider = ProviderClient(
        client: MockClient(
          (request) async => failed
              ? http.Response('private response', 503)
              : http.Response(
                  '#EXTM3U\n#EXTINF:-1,Channel\nhttps://test/stream\n',
                  200,
                ),
        ),
      );
      final app = AppController(store, providers: provider)..current = admin;
      final revisions = <int>[];
      app.addListener(() => revisions.add(app.revision));
      await app.refreshDue(force: true);
      expect(app.refreshError, isNull);
      final revision = app.revision;
      revisions.clear();
      await app.refreshDue(force: true);
      expect(revisions, everyElement(revision));
      expect(
        app.refreshSummary,
        contains('0 added · 0 changed · 0 removed · 1 unchanged'),
      );
      final timestamp = (await store.sources()).single.updatedAt;
      failed = true;
      await app.refreshDue(force: true);
      expect(app.refreshError, isNull);
      expect((await store.sources()).single.updatedAt, timestamp);
      expect(await store.browse(admin), hasLength(1));
      await store.replaceItems(source, []);
      await app.refreshDue(force: true);
      expect(app.refreshError, contains('HTTP 503'));
      expect(app.refreshError, isNot(contains('secret=123')));
      app.dispose();
    },
  );
  test(
    'Movie, series, live queries and category lists stay type-scoped',
    () async {
      await store.replaceItems(source, [
        const MediaItem(
          id: 's:live',
          sourceId: 's',
          name: 'Shared',
          url: 'https://test/live',
          group: 'News',
        ),
        const MediaItem(
          id: 's:movie',
          sourceId: 's',
          name: 'Shared',
          url: 'https://test/movie',
          group: 'Cinema',
          kind: MediaKind.movie,
        ),
        const MediaItem(
          id: 's:series',
          sourceId: 's',
          name: 'Shared',
          url: '',
          group: 'Drama',
          kind: MediaKind.series,
        ),
      ]);
      for (final kind in [MediaKind.live, MediaKind.movie, MediaKind.series]) {
        final results = await store.browse(admin, query: 'Shared', kind: kind);
        expect(results.single.kind, kind);
      }
      expect(await store.groups(admin, kind: MediaKind.live), ['News']);
      expect(
        await store.browse(admin, kind: MediaKind.live, group: 'Cinema'),
        isEmpty,
      );
    },
  );
  test(
    'Bulk indexing preserves other sources and upserts episodes without duplicates',
    () async {
      const other = Source(
        id: 'other',
        name: 'Other',
        kind: SourceKind.m3u,
        url: 'https://test/other',
      );
      const foreign = MediaItem(
        id: 'other:1',
        sourceId: 'other',
        name: 'Foreign',
        url: 'https://test/stream',
      );
      await store.replaceItems(other, [foreign]);
      await store.replaceItems(source, [items.first, items.first]);
      await store.replaceItems(source, [
        items.first,
        items.last,
      ], replace: false);
      await store.replaceItems(source, [items.first], replace: false);
      final count = await store.db
          .customSelect('SELECT count(*) AS n FROM item_search')
          .getSingle();
      expect(count.read<int>('n'), 3);
      expect(await store.browse(admin, query: 'Foreign'), hasLength(1));
      expect(await store.browse(admin, query: 'Nature'), hasLength(2));
    },
  );
  test(
    'Restore to a different device key is portable and malformed import rolls back',
    () async {
      final backup = await store.exportData();
      final target = LibraryStore(
        LumenDatabase(NativeDatabase.memory()),
        SecretKey(List.filled(32, 9)),
      );
      await target.importData(backup);
      expect((await target.sources()).single.url, source.url);
      expect(await target.browse(admin), hasLength(2));
      final invalid = jsonDecode(backup);
      invalid['items'][0]['payload'] = 'invalid json';
      await expectLater(
        target.importData(jsonEncode(invalid)),
        throwsA(anything),
      );
      expect(await target.browse(admin), hasLength(2));
      await target.db.close();
    },
  );
  test('Current programme rating is enforced at playback', () async {
    final now = DateTime.now();
    await store.replaceEpg('s', [
      Programme(
        id: 'p',
        sourceId: 's',
        channelId: 'nature',
        title: 'Restricted',
        rating: 18,
        start: now.subtract(const Duration(minutes: 1)),
        end: now.add(const Duration(hours: 1)),
      ),
    ]);
    expect(await store.canPlay(child, items.first), isFalse);
    expect(await store.canPlay(admin, items.first), isTrue);
  });
  test('Failed EPG refresh is silent only when a saved guide exists', () async {
    await store.saveSource(
      Source.fromJson({...source.toJson(), 'epgUrl': 'https://test/guide'}),
    );
    final now = DateTime.now();
    await store.replaceEpg(source.id, [
      Programme(
        id: 'saved-guide',
        sourceId: source.id,
        channelId: 'nature',
        title: 'Saved programme',
        start: now,
        end: now.add(const Duration(hours: 1)),
      ),
    ]);
    final app = AppController(
      store,
      providers: ProviderClient(
        client: MockClient((_) async => http.Response('', 503)),
      ),
    )..current = admin;
    await app.refreshDue(force: true);
    expect(app.refreshError, isNull);
    expect(await store.hasCachedSource(source.id, guide: true), isTrue);
    await store.replaceEpg(source.id, []);
    await app.refreshDue(force: true);
    expect(app.refreshError, contains('EPG refresh failed'));
    expect(app.refreshError, isNot(contains('library refresh failed')));
    app.dispose();
  });
  test(
    'Live browsing keeps provider order, including reordered unchanged rows',
    () async {
      const z = MediaItem(
        id: 's:z',
        sourceId: 's',
        name: 'Zulu channel',
        url: 'https://test/z',
        group: 'News',
      );
      const a = MediaItem(
        id: 's:a',
        sourceId: 's',
        name: 'Alpha channel',
        url: 'https://test/a',
        group: 'News',
      );
      await store.replaceItems(source, [z, a]);
      expect(
        (await store.browse(
          admin,
          kind: MediaKind.live,
          group: 'News',
        )).map((i) => i.id),
        ['s:z', 's:a'],
      );
      final before =
          (await store.db
                  .customSelect("SELECT payload FROM items WHERE id='s:z'")
                  .getSingle())
              .read<String>('payload');
      final delta = await store.replaceItems(source, [a, z]);
      expect(delta.reordered, 2);
      expect(delta.updated, 0);
      expect(
        (await store.db
                .customSelect("SELECT payload FROM items WHERE id='s:z'")
                .getSingle())
            .read<String>('payload'),
        before,
      );
      expect(
        (await store.browse(
          admin,
          kind: MediaKind.live,
          group: 'News',
          query: 'channel',
          limit: 1,
        )).single.id,
        's:a',
      );
      expect(
        (await store.browse(
          admin,
          kind: MediaKind.live,
          group: 'Sport',
          query: 'channel',
        )),
        isEmpty,
      );
      expect((await store.replaceItems(source, [a, z])).reordered, 0);
      final backup = await store.exportData();
      await store.replaceItems(source, [z, a]);
      await store.importData(backup);
      expect(
        (await store.browse(admin, kind: MediaKind.live)).map((i) => i.id),
        ['s:a', 's:z'],
      );
    },
  );
  test('Episode exclusion applies before search pagination', () async {
    await store.replaceItems(source, [
      const MediaItem(
        id: 's:e',
        sourceId: 's',
        name: 'Shared A episode',
        url: 'https://test/e',
        kind: MediaKind.episode,
        parentId: 's:series',
      ),
      const MediaItem(
        id: 's:m',
        sourceId: 's',
        name: 'Shared B movie',
        url: 'https://test/m',
        kind: MediaKind.movie,
      ),
    ]);
    expect(
      (await store.browse(
        admin,
        query: 'Shared',
        includeEpisodes: false,
        limit: 1,
      )).single.id,
      's:m',
    );
    expect(
      await store.browse(admin, query: 'Shared', includeEpisodes: true),
      hasLength(2),
    );
  });
  test(
    'Version 2 upgrade retains existing channels and creates order storage',
    () async {
      final temp = await Directory.systemTemp.createTemp('lumen-order-test-');
      final file = File('${temp.path}/library.sqlite');
      final old = LibraryStore(
        LumenDatabase(NativeDatabase(file)),
        SecretKey(List.filled(32, 7)),
      );
      await old.replaceItems(source, items);
      await old.db.customStatement('DROP TABLE channel_order');
      await old.db.customStatement('PRAGMA user_version=2');
      await old.db.close();
      final upgraded = LibraryStore(
        LumenDatabase(NativeDatabase(file)),
        SecretKey(List.filled(32, 7)),
      );
      try {
        expect(
          await upgraded.browse(admin, kind: MediaKind.live),
          hasLength(2),
        );
        expect(
          (await upgraded.db
                  .customSelect('SELECT count(*) AS n FROM channel_order')
                  .getSingle())
              .read<int>('n'),
          2,
        );
        await upgraded.replaceItems(source, items.reversed.toList());
        expect(
          (await upgraded.browse(admin, kind: MediaKind.live)).first.id,
          items.last.id,
        );
      } finally {
        await upgraded.db.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
