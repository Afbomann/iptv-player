import 'package:flutter/material.dart';
import '../core/models.dart';

enum EngineKind { automatic, native, mpv, vlc, browser, mpvSoftware }

extension EngineLabel on EngineKind {
  String get label => this == EngineKind.mpvSoftware
      ? 'MPV (software decoding)'
      : name.toUpperCase();
}

class PlaybackTrack {
  const PlaybackTrack(
    this.id,
    this.label, {
    this.subtitle = false,
    this.selected = false,
  });
  final String id, label;
  final bool subtitle, selected;
}

abstract class PlaybackEngine extends ChangeNotifier {
  bool terminated = false;
  double initialVolume = 1;
  bool beginClose() {
    if (terminated) return false;
    terminated = true;
    return true;
  }

  bool playing = false, buffering = true;
  Duration position = Duration.zero, duration = Duration.zero;
  String? error;
  EngineKind get kind;
  Widget surface();
  Future<void> open(
    MediaItem item, {
    String? url,
    Duration start = Duration.zero,
  });
  Future<void> toggle();
  Future<void> seek(Duration value);
  Future<void> volume(double value);
  Future<void> close();
  Future<void> frameRate(bool enabled) async {}
  Future<List<PlaybackTrack>> tracks() async => [];
  Future<void> selectTrack(PlaybackTrack track) async {}
}
