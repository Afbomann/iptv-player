import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../platform/device.dart';
import '../core/models.dart';
import '../core/security.dart';
import 'sync.dart';
export 'sync.dart' show SyncDelta;

class LumenDatabase extends GeneratedDatabase {
  LumenDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'lumen',
              native: DriftNativeOptions(
                databaseDirectory: isAppleTV
                    ? getApplicationCacheDirectory
                    : getApplicationDocumentsDirectory,
              ),
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.dart.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final sql in [
        'CREATE TABLE channel_order (id TEXT PRIMARY KEY, position INTEGER NOT NULL)',
        syncSchema,
        'CREATE INDEX sync_source ON sync_hashes(kind,source)',
        'CREATE TABLE profiles (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        'CREATE TABLE sources (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        'CREATE TABLE items (id TEXT PRIMARY KEY, source TEXT NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL, category TEXT NOT NULL, rating INTEGER NOT NULL, epg TEXT NOT NULL, parent TEXT NOT NULL, payload TEXT NOT NULL)',
        'CREATE INDEX items_browse ON items(kind, source, category, name)',
        'CREATE INDEX items_epg ON items(source, epg)',
        'CREATE VIRTUAL TABLE item_search USING fts5(id UNINDEXED, name, category, tokenize="unicode61 remove_diacritics 2")',
        'CREATE TABLE programmes (id TEXT PRIMARY KEY, source TEXT NOT NULL, channel TEXT NOT NULL, title TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER NOT NULL, rating INTEGER NOT NULL, payload TEXT NOT NULL)',
        'CREATE INDEX programme_window ON programmes(source,channel,start,end)',
        'CREATE VIRTUAL TABLE programme_search USING fts5(id UNINDEXED, title, tokenize="unicode61 remove_diacritics 2")',
        'CREATE TABLE user_state (profile TEXT NOT NULL, item TEXT NOT NULL, favorite INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, duration INTEGER NOT NULL DEFAULT 0, watched INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(profile,item))',
        'CREATE TABLE settings (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        'CREATE TABLE recordings (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      ]) {
        await customStatement(sql);
      }
    },
    onUpgrade: (_, from, to) async {
      if (from < 3) {
        await customStatement(
          'CREATE TABLE channel_order (id TEXT PRIMARY KEY, position INTEGER NOT NULL)',
        );
        await customStatement(
          "INSERT INTO channel_order SELECT id,rowid FROM items WHERE kind='live'",
        );
      }
      if (from < 2) {
        await customStatement(syncSchema);
        await customStatement(
          'CREATE INDEX sync_source ON sync_hashes(kind,source)',
        );
      }
    },
  );
}

class LibraryStore {
  LibraryStore(this.db, this.key);
  final LumenDatabase db;
  final SecretKey key;
  static Future<LibraryStore> open() async {
    const vault = FlutterSecureStorage();
    var encoded = await vault.read(key: 'lumen.database.key.v1');
    if (encoded == null) {
      encoded = base64Encode(Security.randomBytes(32));
      await vault.write(key: 'lumen.database.key.v1', value: encoded);
    }
    final store = LibraryStore(
      LumenDatabase(),
      SecretKey(base64Decode(encoded)),
    );
    await store.db.customSelect('SELECT 1').get();
    return store;
  }

  Future<void> _put(
    String table,
    String id,
    Map<String, dynamic> payload, {
    bool encrypted = false,
  }) async {
    final raw = jsonEncode(payload);
    await db.customStatement(
      'INSERT OR REPLACE INTO $table(id,payload) VALUES (?,?)',
      [id, encrypted ? await Security.seal(raw, key) : raw],
    );
  }

  Future<List<Map<String, dynamic>>> _all(
    String table, {
    bool encrypted = false,
  }) async {
    final rows = await db.customSelect('SELECT payload FROM $table').get();
    return Future.wait(
      rows.map(
        (r) async => decodeMap(
          encrypted
              ? await Security.open(r.read<String>('payload'), key)
              : r.read<String>('payload'),
        ),
      ),
    );
  }

  Future<List<Profile>> profiles() async =>
      (await _all('profiles')).map(Profile.fromJson).toList();
  Future<void> saveProfile(Profile p) => _put('profiles', p.id, p.toJson());
  Future<void> deleteProfile(String id) => db.transaction(() async {
    await db.customStatement('DELETE FROM profiles WHERE id=?', [id]);
    await db.customStatement('DELETE FROM user_state WHERE profile=?', [id]);
  });
  Future<List<Source>> sources() async =>
      (await _all('sources', encrypted: true)).map(Source.fromJson).toList();
  Future<void> saveSource(Source s) =>
      _put('sources', s.id, s.toJson(), encrypted: true);
  Future<bool> hasCachedSource(String source, {bool guide = false}) async {
    try {
      final rows = await db
          .customSelect(
            'SELECT 1 FROM ${guide ? 'programmes' : 'items'} WHERE source=? LIMIT 1',
            variables: [Variable.withString(source)],
          )
          .get();
      return rows.isNotEmpty;
    } catch (_) {
      // Do not hide a storage failure when we cannot verify the fallback.
      return false;
    }
  }

  Future<void> deleteSource(String id) => db.transaction(() async {
    await db.customStatement(
      'DELETE FROM channel_order WHERE id IN (SELECT id FROM items WHERE source=?)',
      [id],
    );
    await db.customStatement('DELETE FROM sync_hashes WHERE source=?', [id]);
    await db.customStatement(
      'DELETE FROM item_search WHERE id IN (SELECT id FROM items WHERE source=?)',
      [id],
    );
    await db.customStatement(
      'DELETE FROM programme_search WHERE id IN (SELECT id FROM programmes WHERE source=?)',
      [id],
    );
    await db.customStatement('DELETE FROM items WHERE source=?', [id]);
    await db.customStatement('DELETE FROM programmes WHERE source=?', [id]);
    await db.customStatement('DELETE FROM sources WHERE id=?', [id]);
  });
  Future<SyncDelta> replaceItems(
    Source source,
    List<MediaItem> items, {
    bool replace = true,
    String? parent,
    void Function(int, int)? onProgress,
  }) => db.transaction(() async {
    if (items.any(
      (i) =>
          i.sourceId != source.id || (parent != null && i.parentId != parent),
    )) {
      throw const FormatException('Catalog source mismatch.');
    }
    final result = await synchronize(
      db: db,
      key: key,
      source: source.id,
      catalog: true,
      replace: replace,
      parent: parent,
      encrypt: (raw) => Security.seal(raw, key),
      readLegacy: (raw) async => jsonEncode(
        MediaItem.fromJson(decodeMap(await Security.open(raw, key))).toJson(),
      ),
      onProgress: onProgress,
      rows: [
        for (final i in items)
          SyncRow(i.id, jsonEncode(i.toJson()), [
            i.id,
            i.sourceId,
            i.name,
            i.kind.name,
            i.group,
            i.rating,
            i.epgId,
            i.parentId,
          ]),
      ],
    );
    var reordered = 0;
    if (replace && parent == null) {
      final oldOrder = await db
          .customSelect(
            'SELECT o.id,o.position FROM channel_order o JOIN items i ON i.id=o.id WHERE i.source=?',
            variables: [Variable.withString(source.id)],
          )
          .get();
      final positions = {
        for (final row in oldOrder)
          row.read<String>('id'): row.read<int>('position'),
      };
      final live = {
        for (final i in items.where((i) => i.kind == MediaKind.live)) i.id: i,
      }.keys.toList();
      await db.batch((batch) {
        for (var index = 0; index < live.length; index++) {
          if (positions[live[index]] == index) continue;
          if (positions.containsKey(live[index])) reordered++;
          batch.customStatement(
            'INSERT OR REPLACE INTO channel_order VALUES (?,?)',
            [live[index], index],
          );
        }
      });
      await db.customStatement(
        'DELETE FROM channel_order WHERE id NOT IN (SELECT id FROM items)',
      );
    }
    await saveSource(source);
    return SyncDelta(
      result.added,
      result.updated,
      result.deleted,
      result.unchanged,
      reordered: reordered,
    );
  });

  (String, List<Variable>) _policy(Profile p, {String alias = 'i'}) {
    if (p.admin) return ('1=1', []);
    final clauses = <String>[
      '($alias.rating > 0 AND $alias.rating <= ? ${p.allowUnrated ? 'OR $alias.rating=0' : ''})',
    ];
    final args = <Variable>[Variable.withInt(p.maxRating)];
    for (final entry in [
      (p.allowedSources, 'source', false),
      (p.blockedGroups, 'category', true),
      (p.blockedChannels, 'id', true),
    ]) {
      if (entry.$1.isNotEmpty) {
        clauses.add(
          '$alias.${entry.$2} ${entry.$3 ? 'NOT IN' : 'IN'} (${List.filled(entry.$1.length, '?').join(',')})',
        );
        args.addAll(entry.$1.map(Variable.withString));
      }
    }
    return (clauses.join(' AND '), args);
  }

  static String ftsQuery(String text) => RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text).take(12).map((m) => '"${m.group(0)}"*').join(' AND ');
  Future<List<MediaItem>> browse(
    Profile p, {
    MediaKind? kind,
    String query = '',
    String? group,
    String? source,
    bool favorites = false,
    bool recent = false,
    bool includeEpisodes = true,
    String? parent,
    List<String>? ids,
    int offset = 0,
    int limit = 60,
  }) async {
    final policy = _policy(p);
    final where = <String>[policy.$1];
    if (!includeEpisodes) where.add("i.kind != 'episode'");
    final args = <Variable>[...policy.$2];
    var join = '';
    if (kind == MediaKind.live && !recent) {
      join += ' LEFT JOIN channel_order o ON o.id=i.id';
    }
    if (favorites || recent) {
      join += ' JOIN user_state u ON u.item=i.id AND u.profile=?';
      args.insert(0, Variable.withString(p.id));
      where.add(favorites ? 'u.favorite=1' : 'u.watched>0');
    }
    final search = ftsQuery(query);
    if (ids != null) {
      if (ids.isEmpty) return [];
      where.add('i.id IN (SELECT value FROM json_each(?))');
      args.add(Variable.withString(jsonEncode(ids)));
    }
    if (query.trim().isNotEmpty && search.isEmpty) return [];
    if (search.isNotEmpty) {
      where.add(
        'i.id IN (SELECT id FROM item_search WHERE item_search MATCH ?)',
      );
      args.add(Variable.withString(search));
    }
    for (final v in [
      ('kind', kind?.name),
      ('category', group),
      ('source', source),
      ('parent', parent),
    ]) {
      if (v.$2 != null) {
        where.add('i.${v.$1}=?');
        args.add(Variable.withString(v.$2!));
      }
    }
    final rows = await db
        .customSelect(
          'SELECT i.payload FROM items i $join WHERE ${where.join(' AND ')} ORDER BY ${recent
              ? 'u.watched DESC'
              : kind == MediaKind.live
              ? 'i.source,COALESCE(o.position,i.rowid),i.id'
              : 'i.name COLLATE NOCASE'} LIMIT ? OFFSET ?',
          variables: [
            ...args,
            Variable.withInt(limit.clamp(1, 200)),
            Variable.withInt(offset),
          ],
        )
        .get();
    return Future.wait(
      rows.map(
        (r) async => MediaItem.fromJson(
          decodeMap(await Security.open(r.read<String>('payload'), key)),
        ),
      ),
    );
  }

  Future<MediaItem?> item(Profile p, String id) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM items WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    final item = MediaItem.fromJson(
      decodeMap(await Security.open(rows.first.read<String>('payload'), key)),
    );
    return p.allows(item) ? item : null;
  }

  Future<List<String>> groups(
    Profile p, {
    MediaKind? kind,
    String? source,
  }) async {
    final policy = _policy(p);
    final rows = await db
        .customSelect(
          'SELECT DISTINCT i.category FROM items i WHERE ${policy.$1}${kind == null ? '' : ' AND i.kind=?'}${source == null ? '' : ' AND i.source=?'} ORDER BY i.category',
          variables: [
            ...policy.$2,
            if (kind != null) Variable.withString(kind.name),
            if (source != null) Variable.withString(source),
          ],
        )
        .get();
    return rows.map((r) => r.read<String>('category')).toList();
  }

  Future<List<(MediaItem, Programme)>> searchProgrammes(
    Profile p,
    String query,
  ) async {
    final search = ftsQuery(query);
    if (search.isEmpty) return [];
    final policy = _policy(p);
    final rating = p.admin
        ? '1=1'
        : '(g.rating>0 AND g.rating<=? ${p.allowUnrated ? 'OR g.rating=0' : ''})';
    final rows = await db
        .customSelect(
          '''SELECT i.payload AS item_payload,g.payload AS programme_payload FROM programmes g
      JOIN items i ON i.source=g.source AND i.kind='live' AND g.channel=COALESCE(
        (SELECT json_extract(payload,'\$.channel') FROM settings WHERE id='epg-map:'||i.id),NULLIF(i.epg,''),i.name)
      WHERE ${policy.$1} AND $rating AND g.id IN (SELECT id FROM programme_search WHERE programme_search MATCH ?)
      ORDER BY g.start LIMIT 20''',
          variables: [
            ...policy.$2,
            if (!p.admin) Variable.withInt(p.maxRating),
            Variable.withString(search),
          ],
        )
        .get();
    return Future.wait(
      rows.map(
        (r) async => (
          MediaItem.fromJson(
            decodeMap(await Security.open(r.read<String>('item_payload'), key)),
          ),
          Programme.fromJson(decodeMap(r.read<String>('programme_payload'))),
        ),
      ),
    );
  }

  Future<int> count(Profile p) async {
    final policy = _policy(p);
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM items i WHERE ${policy.$1}',
          variables: policy.$2,
        )
        .get();
    return rows.first.read<int>('n');
  }

  Future<SyncDelta> replaceEpg(
    String source,
    List<Programme> programs, {
    void Function(int, int)? onProgress,
  }) {
    if (programs.any((p) => p.sourceId != source)) {
      throw const FormatException('Guide source mismatch.');
    }
    return synchronize(
      db: db,
      key: key,
      source: source,
      catalog: false,
      encrypt: (raw) async => raw,
      onProgress: onProgress,
      rows: [
        for (final p in programs)
          SyncRow(p.id, jsonEncode(p.toJson()), [
            p.id,
            p.sourceId,
            p.channelId,
            p.title,
            p.start.millisecondsSinceEpoch,
            p.end.millisecondsSinceEpoch,
            p.rating,
          ]),
      ],
    );
  }

  Future<List<Programme>> guide(
    Profile p,
    MediaItem channel,
    DateTime from,
    DateTime to, {
    String? mapping,
  }) async {
    if (!p.allows(channel)) return [];
    final rows = await db
        .customSelect(
          'SELECT payload FROM programmes WHERE source=? AND channel=? AND end>? AND start<? ORDER BY start LIMIT 100',
          variables: [
            Variable.withString(channel.sourceId),
            Variable.withString(
              mapping ?? (channel.epgId.isEmpty ? channel.name : channel.epgId),
            ),
            Variable.withInt(from.millisecondsSinceEpoch),
            Variable.withInt(to.millisecondsSinceEpoch),
          ],
        )
        .get();
    return rows
        .map((r) => Programme.fromJson(decodeMap(r.read<String>('payload'))))
        .where((v) => allowsProgramme(p, v))
        .toList();
  }

  bool allowsProgramme(Profile p, Programme v) =>
      p.admin || (v.rating == 0 ? p.allowUnrated : v.rating <= p.maxRating);
  Future<bool> canPlay(
    Profile p,
    MediaItem item, {
    Programme? programme,
  }) async {
    if (!p.allows(item)) return false;
    if (programme != null) return allowsProgramme(p, programme);
    if (item.kind != MediaKind.live || p.admin) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final mapping = await setting('epg-map:${item.id}');
    final rows = await db
        .customSelect(
          'SELECT payload FROM programmes WHERE source=? AND channel=? AND start<=? AND end>?',
          variables: [
            Variable.withString(item.sourceId),
            Variable.withString(
              mapping?['channel'] ??
                  (item.epgId.isEmpty ? item.name : item.epgId),
            ),
            Variable.withInt(now),
            Variable.withInt(now),
          ],
        )
        .get();
    return rows.isEmpty
        ? p.allowUnrated
        : rows.every(
            (r) => allowsProgramme(
              p,
              Programme.fromJson(decodeMap(r.read<String>('payload'))),
            ),
          );
  }

  Future<Map<String, dynamic>> state(String profile, String item) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM user_state WHERE profile=? AND item=?',
          variables: [Variable.withString(profile), Variable.withString(item)],
        )
        .get();
    return rows.isEmpty
        ? {'favorite': 0, 'position': 0, 'duration': 0, 'watched': 0}
        : rows.first.data;
  }

  Future<void> setState(
    String profile,
    String item, {
    bool? favorite,
    int? position,
    int? duration,
    bool watched = false,
  }) async {
    final previous = await state(profile, item);
    await db.customStatement(
      'INSERT OR REPLACE INTO user_state VALUES (?,?,?,?,?,?)',
      [
        profile,
        item,
        favorite == null ? previous['favorite'] : (favorite ? 1 : 0),
        position ?? previous['position'],
        duration ?? previous['duration'],
        watched ? DateTime.now().millisecondsSinceEpoch : previous['watched'],
      ],
    );
  }

  Future<Map<String, dynamic>?> setting(String id) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM settings WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : decodeMap(rows.first.read<String>('payload'));
  }

  Future<void> setSetting(String id, Map<String, dynamic> value) =>
      _put('settings', id, value);
  Future<List<Map<String, dynamic>>> recordings() => _all('recordings');
  Future<void> saveRecording(Map<String, dynamic> job) =>
      _put('recordings', job['id'], job);
  Future<String> exportData() async {
    final result = <String, dynamic>{'version': 1};
    for (final table in [
      'profiles',
      'sources',
      'items',
      'programmes',
      'user_state',
      'settings',
      'recordings',
      'channel_order',
    ]) {
      final rows = await db
          .customSelect(
            'SELECT * FROM $table ${table == 'settings' ? "WHERE id != 'rollback'" : ''}',
          )
          .get();
      result[table] = await Future.wait(
        rows.map((r) async {
          final data = Map<String, dynamic>.from(r.data);
          if (table == 'items' || table == 'sources') {
            data['payload'] = await Security.open(data['payload'], key);
          }
          return data;
        }),
      );
    }
    return jsonEncode(result);
  }

  Future<void> importData(String raw) async {
    final data = decodeMap(raw);
    if (data['version'] != 1) {
      throw const FormatException('Unsupported database version.');
    }
    final profiles = (data['profiles'] as List)
        .map((r) => Profile.fromJson(decodeMap(r['payload'])))
        .toList();
    if (profiles.where((p) => p.admin).length != 1) {
      throw const FormatException(
        'Backup must contain exactly one administrator.',
      );
    }
    const columns = {
      'profiles': ['id', 'payload'],
      'sources': ['id', 'payload'],
      'items': [
        'id',
        'source',
        'name',
        'kind',
        'category',
        'rating',
        'epg',
        'parent',
        'payload',
      ],
      'programmes': [
        'id',
        'source',
        'channel',
        'title',
        'start',
        'end',
        'rating',
        'payload',
      ],
      'user_state': [
        'profile',
        'item',
        'favorite',
        'position',
        'duration',
        'watched',
      ],
      'settings': ['id', 'payload'],
      'recordings': ['id', 'payload'],
      'channel_order': ['id', 'position'],
    };
    // Every statement is inside one transaction: invalid rows roll the entire import back.
    await db.transaction(() async {
      await db.customStatement('DELETE FROM sync_hashes');
      for (final table in columns.keys) {
        await db.customStatement('DELETE FROM $table');
        for (final value
            in (table == 'channel_order' ? data[table] ?? [] : data[table])
                as List) {
          final row = Map<String, dynamic>.from(value);
          if (table == 'sources') Source.fromJson(decodeMap(row['payload']));
          if (table == 'items') MediaItem.fromJson(decodeMap(row['payload']));
          if (table == 'programmes') {
            Programme.fromJson(decodeMap(row['payload']));
          }
          if (table == 'items' || table == 'sources') {
            row['payload'] = await Security.seal(row['payload'], key);
          }
          if (table == 'recordings') {
            final job = decodeMap(row['payload']);
            job['status'] = 'paused';
            job['path'] = '';
            row['payload'] = jsonEncode(job);
          }
          await db.customStatement(
            'INSERT INTO $table (${columns[table]!.join(',')}) VALUES (${List.filled(columns[table]!.length, '?').join(',')})',
            columns[table]!.map((c) => row[c]).toList(),
          );
        }
      }
      await db.customStatement('DELETE FROM item_search');
      await db.customStatement(
        'INSERT INTO item_search(id,name,category) SELECT id,name,category FROM items',
      );
      await db.customStatement('DELETE FROM programme_search');
      await db.customStatement(
        'INSERT INTO programme_search(id,title) SELECT id,title FROM programmes',
      );
    });
  }
}
