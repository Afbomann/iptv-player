import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

class SyncDelta {
  const SyncDelta(
    this.added,
    this.updated,
    this.deleted,
    this.unchanged, {
    this.reordered = 0,
  });
  final int reordered;
  final int added, updated, deleted, unchanged;
  @override
  String toString() =>
      '$added added · $updated changed · $deleted removed · $unchanged unchanged${reordered > 0 ? ' · $reordered reordered' : ''}';
}

class SyncRow {
  const SyncRow(this.id, this.payload, this.columns);
  final String id, payload;
  final List<Object?> columns;
}

const syncSchema =
    'CREATE TABLE IF NOT EXISTS sync_hashes (kind TEXT NOT NULL, id TEXT NOT NULL, source TEXT NOT NULL, digest TEXT NOT NULL, PRIMARY KEY(kind,id))';

/// Fingerprints are keyed: they do not expose a dictionary-testable hash of credentials.
Future<SyncDelta> synchronize({
  required GeneratedDatabase db,
  required SecretKey key,
  required String source,
  required List<SyncRow> rows,
  required bool catalog,
  required Future<String> Function(String) encrypt,
  Future<String> Function(String)? readLegacy,
  bool replace = true,
  String? parent,
  void Function(int, int)? onProgress,
}) => db.transaction(() async {
  final table = catalog ? 'items' : 'programmes';
  final search = catalog ? 'item_search' : 'programme_search';
  final incoming = {for (final row in rows) row.id: row};
  final old = await db
      .customSelect(
        'SELECT t.id,h.digest,CASE WHEN h.digest IS NULL THEN t.payload END AS legacy${catalog ? ',t.parent,t.kind' : ''} FROM $table t LEFT JOIN sync_hashes h ON h.id=t.id AND h.kind=? WHERE t.source=?${parent == null ? '' : ' AND t.parent=?'}',
        variables: [
          Variable.withString(table),
          Variable.withString(source),
          if (parent != null) Variable.withString(parent),
        ],
      )
      .get();
  final previous = {for (final row in old) row.read<String>('id'): row};
  final mac = crypto.Hmac(crypto.sha256, await key.extractBytes());
  final hashes = <String, String>{};
  final changed = <SyncRow>[];
  final seeds = <String, String>{};
  var added = 0;
  var compared = 0;
  for (final row in incoming.values) {
    if (++compared % 500 == 0) await Future<void>.delayed(Duration.zero);
    final hash = mac.convert(utf8.encode(row.payload)).toString();
    var prior = previous[row.id]?.readNullable<String>('digest');
    final legacy = previous[row.id]?.readNullable<String>('legacy');
    if (prior == null && legacy != null) {
      final raw = readLegacy == null ? legacy : await readLegacy(legacy);
      prior = mac.convert(utf8.encode(raw)).toString();
      if (prior == hash) seeds[row.id] = hash;
    }
    if (prior != hash) {
      hashes[row.id] = hash;
      changed.add(row);
      if (!previous.containsKey(row.id)) added++;
    }
  }
  final removed = <String>[];
  if (seeds.isNotEmpty) {
    await db.batch((b) {
      for (final entry in seeds.entries) {
        b.customStatement(
          'INSERT OR REPLACE INTO sync_hashes VALUES (?,?,?,?)',
          [table, entry.key, source, entry.value],
        );
      }
    });
  }
  if (replace) {
    for (final entry in previous.entries) {
      if (incoming.containsKey(entry.key)) continue;
      // Cached episodes survive unchanged series catalogs; invalidate them when
      // their series changes (including inherited parental metadata) or disappears.
      if (catalog && entry.value.read<String>('kind') == 'episode') {
        final parent = entry.value.read<String>('parent');
        if (incoming.containsKey(parent) && !hashes.containsKey(parent)) {
          continue;
        }
      }
      removed.add(entry.key);
    }
  }
  final touched = [...removed, ...changed.map((r) => r.id)];
  if (touched.isNotEmpty) {
    await db.customStatement(
      'DELETE FROM $search WHERE id IN (SELECT value FROM json_each(?))',
      [jsonEncode(touched)],
    );
  }
  if (removed.isNotEmpty) {
    final ids = jsonEncode(removed);
    await db.customStatement(
      'DELETE FROM $table WHERE id IN (SELECT value FROM json_each(?)) AND source=?',
      [ids, source],
    );
    await db.customStatement(
      'DELETE FROM sync_hashes WHERE kind=? AND id IN (SELECT value FROM json_each(?))',
      [table, ids],
    );
  }
  for (var start = 0; start < changed.length; start += 200) {
    final chunk = changed.skip(start).take(200).toList();
    final payloads = await Future.wait(
      chunk.map((r) => catalog ? encrypt(r.payload) : Future.value(r.payload)),
    );
    await db.batch((b) {
      for (var i = 0; i < chunk.length; i++) {
        final row = chunk[i];
        b.customStatement(
          'INSERT OR REPLACE INTO $table VALUES (${List.filled(row.columns.length + 1, '?').join(',')})',
          [...row.columns, payloads[i]],
        );
        b.customStatement(
          'INSERT OR REPLACE INTO sync_hashes VALUES (?,?,?,?)',
          [table, row.id, source, hashes[row.id]],
        );
      }
    });
    onProgress?.call(start + chunk.length, changed.length);
  }
  if (changed.isNotEmpty) {
    final fields = catalog ? 'id,name,category' : 'id,title';
    await db.customStatement(
      'INSERT INTO $search($fields) SELECT $fields FROM $table WHERE id IN (SELECT value FROM json_each(?)) AND source=?',
      [jsonEncode(changed.map((r) => r.id).toList()), source],
    );
  }
  onProgress?.call(changed.length, changed.length);
  return SyncDelta(
    added,
    changed.length - added,
    removed.length,
    incoming.length - changed.length,
  );
});
