import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../platform/recorder.dart';
import '../playback/engine.dart';
import '../playback/sessions.dart';
import 'models.dart';
import 'recording_conflicts.dart';

class RecordingService {
  RecordingService(this.store);
  final LibraryStore store;
  final recorder = StreamRecorder();
  Timer? timer;
  bool checking = false;
  bool suspended = false;
  final active = <String>{};
  Future<void> initialize() async {
    for (final job in await store.recordings()) {
      if (job['status'] == 'recording') {
        job['status'] = 'interrupted';
        await store.saveRecording(job);
      }
    }
    timer = Timer.periodic(const Duration(seconds: 15), (_) => tick());
    unawaited(tick());
  }

  Future<void> schedule(
    Profile profile,
    MediaItem item,
    DateTime start,
    DateTime end, {
    String? title,
    int padding = 2,
    Programme? programme,
  }) async {
    if (!PlaybackCapabilities.current.recording) {
      throw StateError('Recording is not available on this device.');
    }
    if (item.kind != MediaKind.live ||
        !await store.canPlay(profile, item, programme: programme)) {
      throw StateError('This channel cannot be recorded by your profile.');
    }
    if (!end.isAfter(DateTime.now()) || !end.isAfter(start)) {
      throw const FormatException('Recording end time must be in the future.');
    }
    final source = (await store.sources()).firstWhere(
      (s) => s.id == item.sourceId,
    );
    final from = start.subtract(Duration(minutes: padding));
    final until = end.add(Duration(minutes: padding));
    final jobs = await store.recordings();
    final conflicts = peakRecordingConcurrency(
      jobs,
      source.id,
      from.millisecondsSinceEpoch,
      until.millisecondsSinceEpoch,
    );
    if (conflicts >= source.connectionLimit) {
      throw StateError(
        'This recording conflicts with the provider connection limit.',
      );
    }
    await store.saveRecording({
      'id': const Uuid().v4(),
      'profile': profile.id,
      'item': item.id,
      'source': item.sourceId,
      'title': title ?? item.name,
      'start': from.millisecondsSinceEpoch,
      'end': until.millisecondsSinceEpoch,
      'status': 'scheduled',
      'path': '',
      'error': '',
      'rating': programme?.rating ?? item.rating,
    });
    await tick();
  }

  Future<void> tick() async {
    if (checking || suspended || !PlaybackCapabilities.current.recording) return;
    checking = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final job in await store.recordings()) {
        if (job['status'] != 'scheduled' || job['start'] > now) continue;
        if (job['end'] <= now) {
          job['status'] = 'missed';
          await store.saveRecording(job);
          continue;
        }
        job['status'] = 'recording';
        await store.saveRecording(job);
        unawaited(_run(job));
      }
    } finally {
      checking = false;
    }
  }

  Future<void> _run(Map<String, dynamic> job) async {
    final id = job['id'] as String;
    Timer? policyTimer;
    var denied = false;
    active.add(id);
    try {
      final profile = (await store.profiles())
          .where((p) => p.id == job['profile'])
          .firstOrNull;
      if (profile == null) throw StateError('Recording account was removed.');
      final item = await store.item(profile, job['item']);
      if (item == null || !await store.canPlay(profile, item)) {
        throw StateError('Recording access is restricted.');
      }
      final source = (await store.sources()).firstWhere(
        (s) => s.id == item.sourceId,
      );
      if (!SessionPool.shared.acquire(id, source.id, source.connectionLimit)) {
        throw StateError('Provider connection limit reached.');
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await const MethodChannel(
          'app.lumen/device',
        ).invokeMethod('recording', {'active': true});
      }
      final settings = await store.setting('recording') ?? {};
      policyTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        final latest = (await store.profiles())
            .where((p) => p.id == job['profile'])
            .firstOrNull;
        if (latest == null || !await store.canPlay(latest, item)) {
          denied = true;
          recorder.stop(id);
        }
      });
      job['path'] = await recorder.record(
        id: id,
        url: item.url,
        end: DateTime.fromMillisecondsSinceEpoch(job['end']),
        headers: item.headers,
        maxBytes: settings['maxBytes'] ?? 4294967296,
      );
      job['status'] = denied ? 'restricted' : 'completed';
      if (denied) {
        job['error'] =
            'Recording stopped because parental restrictions changed or a restricted programme began.';
      }
    } catch (e) {
      job['status'] = 'failed';
      job['error'] = e is StateError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Recording interrupted by a network or storage error.';
    } finally {
      policyTimer?.cancel();
      active.remove(id);
      SessionPool.shared.release(id);
      await store.saveRecording(job);
      if (active.isEmpty &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        try {
          await const MethodChannel(
            'app.lumen/device',
          ).invokeMethod('recording', {'active': false});
        } catch (_) {}
      }
    }
  }

  Future<void> cancel(Profile profile, Map<String, dynamic> job) async {
    if (!profile.admin && job['profile'] != profile.id) {
      throw StateError('This recording belongs to another profile.');
    }
    recorder.stop(job['id']);
    if (!active.contains(job['id'])) {
      job['status'] = 'cancelled';
      await store.saveRecording(job);
    }
  }

  Future<void> dispose() async {
    timer?.cancel();
    await recorder.close();
  }

  Future<List<Map<String, dynamic>>> visible(Profile p) async {
    final result = <Map<String, dynamic>>[];
    for (final job in await store.recordings()) {
      if (p.admin) {
        result.add(job);
        continue;
      }
      if (job['profile'] != p.id || job['status'] == 'restricted') continue;
      final rating = job['rating'] ?? 0;
      if ((rating == 0 && !p.allowUnrated) || rating > p.maxRating) continue;
      if (await store.item(p, job['item']) != null) result.add(job);
    }
    return result;
  }
}
