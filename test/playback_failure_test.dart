import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/playback/engine.dart';
import 'package:lumen_iptv/playback/failure.dart';

void main() {
  test('Windows has automatic hardware and software MPV choices', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(PlaybackCapabilities.current.engines, [
      EngineKind.mpv,
      EngineKind.mpvSoftware,
    ]);
    expect(EngineKind.mpvSoftware.label, contains('software'));
  });
  test('Playback failures give actionable messages without secrets', () {
    for (final entry in {
      'HTTP 403': 'denied',
      '404': 'not found',
      'TLS certificate': 'secure',
      'D3D hardware decoder': 'software',
      'tcp: connection refused': 'network',
    }.entries) {
      final message = playbackFailure(
        '${entry.key} https://provider.example/live/private-user/private-password/1.ts?token=secret',
      );
      expect(message, contains(entry.value));
      expect(message, isNot(contains('private')));
      expect(message, isNot(contains('provider.example')));
      expect(message, isNot(contains('secret')));
    }
  });
}
