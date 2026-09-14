import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../data/providers.dart';
import 'models.dart';
import 'security.dart';
import 'backup_limits.dart';
import 'recording_service.dart';
import 'updates.dart';
import 'refresh_failure.dart';
import '../platform/device.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw UnimplementedError('Provide a LibraryStore at startup.'),
);
Future<String> _hash(String value) => Security.hashPassword(value);
Future<String> _backup(List<String> values) =>
    Security.backup(values[0], values[1]);
Future<String> _restore(List<String> values) =>
    Security.restore(values[0], values[1]);
Future<String> _hashPin(String value) => Security.hashPin(value);
Future<bool> _verify(List<String> values) =>
    Security.verify(values[0], values[1]);

class AppController extends ChangeNotifier {
  AppController(this.store, {ProviderClient? providers})
    : providers = providers ?? ProviderClient();
  final LibraryStore store;
  final ProviderClient providers;
  late final RecordingService recording = RecordingService(store);
  List<Profile> profiles = [];
  List<Source> sources = [];
  Profile? current;
  bool refreshing = false;
  bool backupBusy = false;
  String? activity;
  String? refreshError;
  String? refreshSummary;
  int revision = 0;
  bool isTV = false;
  ReleaseInfo? availableUpdate;
  Timer? _refreshTimer;
  Timer? _appUpdateTimer;
  bool _disposed = false;
  bool _signingIn = false;
  bool _checkingUpdates = false;
  Future<void> initialize() async {
    isTV = isAppleTV;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        isTV =
            await const MethodChannel(
              'app.lumen/device',
            ).invokeMethod<bool>('isTV') ??
            false;
      } catch (_) {}
    }
    profiles = await store.profiles();
    sources = await store.sources();
    await recording.initialize();
    final updateSettings = await store.setting('app-updates');
    if (updateSettings?['startup'] != false && UpdateService.configured) {
      unawaited(checkUpdates());
    }
    if (UpdateService.configured) {
      _appUpdateTimer = Timer.periodic(const Duration(hours: 6), (_) async {
        try {
          final settings = await store.setting('app-updates');
          if (!_disposed && settings?['startup'] != false) await checkUpdates();
        } catch (_) {
          /* An optional check must not interrupt playback. */
        }
      });
    }
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => refreshDue(),
    );
  }

  void changed() {
    revision++;
    progressChanged();
  }

  void progressChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> checkUpdates() async {
    if (_disposed || _checkingUpdates) return;
    _checkingUpdates = true;
    try {
      availableUpdate = await UpdateService.check();
      progressChanged();
    } catch (_) {
      /* Optional startup checks must not block local playback. */
    } finally {
      _checkingUpdates = false;
    }
  }

  void requireAdmin() {
    requireBackupIdle();
    if (current?.admin != true) {
      throw StateError('Administrator access is required.');
    }
  }

  void requireBackupIdle() {
    if (backupBusy) {
      throw StateError('Wait for the current backup or restore to finish.');
    }
  }

  Future<void> createAdmin(String name, String password) async {
    requireBackupIdle();
    if ((await store.profiles()).isNotEmpty) {
      throw StateError('An administrator already exists.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('Enter an account name.');
    }
    final p = Profile(
      id: const Uuid().v4(),
      name: name.trim(),
      passwordHash: await compute(_hash, password),
      admin: true,
    );
    requireBackupIdle();
    await store.saveProfile(p);
    profiles = [p];
    current = p;
    changed();
  }

  Future<void> login(Profile profile, String password) async {
    requireBackupIdle();
    if (_signingIn) {
      throw StateError('A sign-in attempt is already in progress.');
    }
    _signingIn = true;
    try {
      await _login(profile, password);
    } finally {
      _signingIn = false;
    }
  }

  Future<void> _login(Profile profile, String password) async {
    final latest = (await store.profiles())
        .where((p) => p.id == profile.id)
        .firstOrNull;
    if (latest == null) throw StateError('Account no longer exists.');
    final throttle = await store.setting('login:${profile.id}') ?? {};
    if ((throttle['until'] ?? 0) > DateTime.now().millisecondsSinceEpoch) {
      throw const FormatException(
        'Too many attempts. Try again in a few minutes.',
      );
    }
    if (!await compute(_verify, [password, latest.passwordHash])) {
      requireBackupIdle();
      final failures = (throttle['failures'] ?? 0) + 1;
      await store.setSetting('login:${profile.id}', {
        'failures': failures,
        'until': failures >= 5
            ? DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch
            : 0,
      });
      throw FormatException(
        latest.usesPin ? 'Incorrect PIN.' : 'Incorrect password.',
      );
    }
    requireBackupIdle();
    await store.setSetting('login:${profile.id}', {'failures': 0, 'until': 0});
    current = latest;
    changed();
    unawaited(refreshDue(startup: true));
  }

  void logout() {
    requireBackupIdle();
    current = null;
    changed();
  }

  Future<void> createUser(
    String name,
    String pin, {
    bool discoverable = true,
  }) async {
    requireAdmin();
    if (name.trim().isEmpty) {
      throw const FormatException('Enter an account name.');
    }
    if (profiles.any(
      (p) => p.name.toLowerCase() == name.trim().toLowerCase(),
    )) {
      throw const FormatException('That account name is already used.');
    }
    final hash = await compute(_hashPin, pin);
    requireAdmin();
    await store.saveProfile(
      Profile(
        id: const Uuid().v4(),
        name: name.trim(),
        passwordHash: hash,
        pin: true,
        discoverable: discoverable,
      ),
    );
    profiles = await store.profiles();
    changed();
  }

  Future<void> updateUser(Profile p) async {
    requireAdmin();
    final original = profiles.firstWhere((v) => v.id == p.id);
    if (original.admin != p.admin ||
        original.passwordHash != p.passwordHash ||
        original.usesPin != p.usesPin) {
      throw StateError('Account role and credentials cannot be changed here.');
    }
    await store.saveProfile(p);
    profiles = await store.profiles();
    changed();
  }

  Future<void> resetUserPin(Profile profile, String pin) async {
    requireAdmin();
    final hash = await compute(_hashPin, pin);
    requireAdmin();
    final latest = (await store.profiles()).firstWhere(
      (p) => p.id == profile.id,
    );
    if (latest.admin) {
      throw StateError('The administrator must use a password.');
    }
    final updated = Profile.fromJson({
      ...latest.toJson(),
      'passwordHash': hash,
      'pin': true,
    });
    await store.db.transaction(() async {
      requireBackupIdle();
      await store.saveProfile(updated);
      await store.setSetting('login:${latest.id}', {'failures': 0, 'until': 0});
    });
    profiles = await store.profiles();
    changed();
  }

  Future<void> setDiscoverable(Profile profile, bool value) async {
    requireAdmin();
    final latest = (await store.profiles()).firstWhere(
      (p) => p.id == profile.id,
    );
    if (latest.admin) {
      throw StateError('The administrator cannot be discoverable.');
    }
    requireBackupIdle();
    await store.saveProfile(
      Profile.fromJson({...latest.toJson(), 'discoverable': value}),
    );
    profiles = await store.profiles();
    changed();
  }

  Future<void> loginByName(String name, String secret) async {
    requireBackupIdle();
    final profile = (await store.profiles())
        .where(
          (p) => !p.admin && p.name.toLowerCase() == name.trim().toLowerCase(),
        )
        .firstOrNull;
    if (profile == null) {
      throw const FormatException('Incorrect account name or sign-in code.');
    }
    await login(profile, secret);
  }

  Future<void> deleteUser(Profile p) async {
    requireAdmin();
    if (p.admin) throw StateError('The administrator cannot be deleted.');
    await store.deleteProfile(p.id);
    profiles = await store.profiles();
    changed();
  }

  Future<void> preferences(Map<String, dynamic> values) async {
    requireBackupIdle();
    final p = current;
    if (p == null) return;
    final updated = Profile.fromJson({
      ...p.toJson(),
      'preferences': {...p.preferences, ...values},
    });
    await store.saveProfile(updated);
    current = updated;
    profiles = await store.profiles();
    changed();
  }

  Future<void> addSource(Source source, {String? fileText}) async {
    requireAdmin();
    if (refreshing) throw StateError('Wait for the current refresh to finish.');
    if (source.refreshHours < 1 || source.epgHours < 1) {
      throw const FormatException('Refresh intervals must be positive hours.');
    }
    providerUri(
      source.url.isEmpty && source.kind == SourceKind.file
          ? 'https://local.invalid'
          : source.url,
    );
    refreshing = true;
    activity = 'Importing ${source.name}';
    changed();
    try {
      final items = await providers.load(
        source,
        fileText: fileText,
        onProgress: (stage) {
          activity = '$stage · ${source.name}';
          changed();
        },
      );
      final effective =
          source.epgUrl.isEmpty &&
              providers.discoveredEpg.containsKey(source.id)
          ? Source.fromJson({
              ...source.toJson(),
              'epgUrl': providers.discoveredEpg[source.id],
            })
          : source;
      requireAdmin();
      await store.replaceItems(
        providers.withAccount(effective).withUpdate(library: DateTime.now()),
        items,
        onProgress: (done, total) {
          activity = done == total
              ? 'Building search index · ${source.name}'
              : 'Saving catalog · $done / $total';
          changed();
        },
      );
      if (fileText != null) {
        // Retain the original local playlist encrypted so backups and refreshes are portable.
        await store.setSetting('file:${source.id}', {
          'encrypted': await Security.seal(fileText, store.key),
        });
      }
      sources = await store.sources();
    } finally {
      await store.releaseMemory();
      refreshing = false;
      activity = null;
      changed();
    }
    unawaited(refreshDue());
  }

  Future<void> updateSource(Source s) async {
    requireAdmin();
    if (refreshing) throw StateError('Wait for the current refresh to finish.');
    if (s.kind != SourceKind.file) providerUri(s.url);
    for (final epg in s.epgUrl.split('\n').where((e) => e.trim().isNotEmpty)) {
      providerUri(epg);
    }
    if (s.refreshHours < 1 || s.epgHours < 1) {
      throw const FormatException('Refresh intervals must be positive hours.');
    }
    refreshing = true;
    activity = 'Checking provider settings';
    changed();
    try {
      providers.accounts.remove(s.id);
      final accountSource = providers.accountSource(s);
      if (accountSource != null) {
        if (s.kind == SourceKind.xtream) {
          await providers.account(accountSource);
        } else {
          try {
            await providers.account(accountSource);
          } catch (_) {
            /* Optional M3U account metadata. */
          }
        }
      }
      s = providers.withAccount(s);
      requireAdmin();
      await store.saveSource(s);
      sources = await store.sources();
    } finally {
      refreshing = false;
      activity = null;
      changed();
    }
  }

  Future<void> removeSource(Source s) async {
    requireAdmin();
    if (refreshing) throw StateError('Wait for the current refresh to finish.');
    await store.deleteSource(s.id);
    sources = await store.sources();
    changed();
  }

  Future<void> refreshDue({bool startup = false, bool force = false}) async {
    if (refreshing || backupBusy || current == null) return;
    refreshing = true;
    refreshError = null;
    refreshSummary = null;
    progressChanged();
    final errors = <String>[];
    final summaries = <String>[];
    var libraryChanged = false;
    try {
      for (final original in await store.sources()) {
        if (current == null) break;
        var source = original;
        final now = DateTime.now();
        final due =
            source.updatedAt == null ||
            now.difference(source.updatedAt!).inHours >= source.refreshHours;
        if (force || due || (startup && source.startup)) {
          activity = 'Refreshing ${source.name}';
          progressChanged();
          try {
            String? fileText;
            if (source.kind == SourceKind.file) {
              final saved = await store.setting('file:${source.id}');
              if (saved != null) {
                fileText = await Security.open(saved['encrypted'], store.key);
              }
            }
            final items = await providers.load(
              source,
              fileText: fileText,
              onProgress: (stage) {
                activity = '$stage · ${source.name}';
                progressChanged();
              },
            );
            source = providers
                .withAccount(source)
                .withUpdate(library: DateTime.now());
            final delta = await store.replaceItems(
              source,
              items,
              onProgress: (done, total) {
                activity = done == total
                    ? 'Catalog compared · ${source.name}'
                    : 'Saving catalog · $done / $total';
                progressChanged();
              },
            );
            libraryChanged |=
                delta.referencesChanged ||
                delta.added + delta.updated + delta.deleted + delta.reordered >
                    0;
            profiles = await store.profiles();
            final currentId = current?.id;
            if (currentId != null) {
              current = profiles.where((p) => p.id == currentId).firstOrNull;
            }
            summaries.add('${source.name} library: $delta');
          } catch (error) {
            source = original;
            if (!await store.hasCachedSource(source.id)) {
              errors.add(
                '${source.name}: library refresh failed. ${refreshFailure(error)}',
              );
            }
          }
        }
        final epgDue =
            source.epgUpdatedAt == null ||
            now.difference(source.epgUpdatedAt!).inHours >= source.epgHours;
        if ((source.epgUrl.isNotEmpty || source.kind == SourceKind.xtream) &&
            (force || epgDue || (startup && source.epgStartup))) {
          activity = 'Updating guide · ${source.name}';
          progressChanged();
          try {
            final retention = await store.setting('epg-retention') ?? {};
            final programs = await providers.epg(
              source,
              pastDays: retention['past'] ?? 2,
              futureDays: retention['future'] ?? 7,
            );
            final updatedSource = source.withUpdate(epg: DateTime.now());
            final delta = await store.db.transaction(() async {
              final result = await store.replaceEpg(
                source.id,
                programs,
                onProgress: (done, total) {
                  activity = done == total
                      ? 'Guide compared · ${source.name}'
                      : 'Saving guide · $done / $total';
                  progressChanged();
                },
              );
              await store.saveSource(updatedSource);
              return result;
            });
            source = updatedSource;
            libraryChanged |= delta.added + delta.updated + delta.deleted > 0;
            summaries.add('${source.name} guide: $delta');
          } catch (error) {
            if (!await store.hasCachedSource(source.id, guide: true)) {
              errors.add(
                '${source.name}: EPG refresh failed. ${refreshFailure(error)}',
              );
            }
          }
        }
      }
      sources = await store.sources();
    } finally {
      refreshing = false;
      activity = null;
      refreshError = errors.isEmpty ? null : errors.join('\n');
      refreshSummary = summaries.isEmpty ? null : summaries.join('\n');
      if (libraryChanged) revision++;
      progressChanged();
    }
  }

  Future<void> favorite(MediaItem item) async {
    requireBackupIdle();
    final p = current;
    if (p == null || !p.allows(item)) return;
    final state = await store.state(p.id, item.id);
    requireBackupIdle();
    await store.setState(p.id, item.id, favorite: state['favorite'] != 1);
    changed();
  }

  Future<List<MediaItem>> episodes(MediaItem series) async {
    requireBackupIdle();
    final p = current;
    if (p == null || !p.allows(series)) {
      throw StateError('Content is restricted.');
    }
    final source = sources.firstWhere((s) => s.id == series.sourceId);
    final episodes = await providers.episodes(source, series);
    requireBackupIdle();
    await store.replaceItems(source, episodes, parent: series.id);
    return episodes.where(p.allows).toList();
  }

  Future<String> exportBackup(String password) async {
    requireAdmin();
    if (password.length < 10) {
      throw const FormatException(
        'Backup password must be at least 10 characters.',
      );
    }
    if (backupBusy || refreshing) {
      throw StateError('Wait for the current backup or refresh to finish.');
    }
    backupBusy = true;
    progressChanged();
    try {
      final raw = await store.exportData(portableFiles: true);
      final archive = await compute(_backup, [raw, password]);
      if (archive.length > backupTransferLimit) {
        throw const FormatException('Backup exceeds the 256 MB limit.');
      }
      return archive;
    } finally {
      backupBusy = false;
      progressChanged();
    }
  }

  Future<void> restoreBackup(String archive, String password) async {
    if (profiles.isNotEmpty) requireAdmin();
    if (backupBusy || refreshing) {
      throw StateError('Wait for the current backup or refresh to finish.');
    }
    if (recording.active.isNotEmpty || recording.checking) {
      throw StateError('Stop active recordings before restoring a backup.');
    }
    backupBusy = true;
    recording.suspended = true;
    progressChanged();
    try {
      // Compress the rollback before decoding the incoming library, avoiding two
      // expanded libraries alive at once. Never include a prior rollback.
      final rollback = await compute(_backup, [
        await store.exportData(),
        base64Encode(await store.key.extractBytes()),
      ]);
      final raw = await compute(_restore, [archive, password]);
      await store.db.transaction(() async {
        await store.importData(raw, portableFiles: true);
        await store.setSetting('rollback', {
          'format': 'lumen-backup-v2-device-key',
          'encrypted': rollback,
        });
      });
      profiles = await store.profiles();
      sources = await store.sources();
      current = null;
      changed();
    } finally {
      recording.suspended = false;
      backupBusy = false;
      progressChanged();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _appUpdateTimer?.cancel();
    unawaited(recording.dispose());
    providers.close();
    super.dispose();
  }
}
