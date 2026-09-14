import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import '../core/models.dart';
import '../platform/device.dart';
import 'mpv_property_stub.dart' if (dart.library.io) 'mpv_property_io.dart';
import 'types.dart';
import 'failure.dart';
export 'types.dart';
import 'browser_stub.dart' if (dart.library.js_interop) 'browser.dart';

class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.engines,
    required this.recording,
    required this.multiview,
    required this.frameRate,
  });
  final List<EngineKind> engines;
  final bool recording, multiview, frameRate;
  static PlaybackCapabilities get current {
    if (isAppleTV) {
      return const PlaybackCapabilities(
        engines: [EngineKind.native],
        recording: false,
        multiview: true,
        frameRate: false,
      );
    }
    if (kIsWeb) {
      return const PlaybackCapabilities(
        engines: [EngineKind.browser],
        recording: false,
        multiview: true,
        frameRate: false,
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => const PlaybackCapabilities(
        engines: [EngineKind.native, EngineKind.mpv, EngineKind.vlc],
        recording: true,
        multiview: true,
        frameRate: true,
      ),
      TargetPlatform.iOS => const PlaybackCapabilities(
        engines: [EngineKind.native, EngineKind.mpv, EngineKind.vlc],
        recording: false,
        multiview: true,
        frameRate: false,
      ),
      TargetPlatform.windows ||
      TargetPlatform.linux => const PlaybackCapabilities(
        engines: [EngineKind.mpv, EngineKind.mpvSoftware],
        recording: true,
        multiview: true,
        frameRate: false,
      ),
      _ => const PlaybackCapabilities(
        engines: [EngineKind.mpv],
        recording: false,
        multiview: true,
        frameRate: false,
      ),
    };
  }
}

class MpvEngine extends PlaybackEngine {
  @override
  Future<List<PlaybackTrack>> tracks() async => [
    for (final t in player.state.tracks.audio)
      PlaybackTrack(
        t.id,
        t.id == 'auto'
            ? 'Automatic'
            : t.id == 'no'
            ? 'Off'
            : t.title ?? t.language ?? 'Audio ${t.id}',
        selected: player.state.track.audio.id == t.id,
      ),
    for (final t in player.state.tracks.subtitle)
      PlaybackTrack(
        t.id,
        t.id == 'auto'
            ? 'Automatic'
            : t.id == 'no'
            ? 'Off'
            : t.title ?? t.language ?? 'Subtitle ${t.id}',
        subtitle: true,
        selected: player.state.track.subtitle.id == t.id,
      ),
  ];
  @override
  Future<void> selectTrack(PlaybackTrack track) async {
    if (track.subtitle) {
      await player.setSubtitleTrack(
        player.state.tracks.subtitle.firstWhere((t) => t.id == track.id),
      );
    } else {
      await player.setAudioTrack(
        player.state.tracks.audio.firstWhere((t) => t.id == track.id),
      );
    }
  }

  MpvEngine({this.software = false}) {
    _subscriptions.addAll([
      player.stream.log.listen((log) {
        final specific = specificPlaybackFailure(log.text);
        if (specific != null) _lastFailure = specific;
      }),
      player.stream.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      player.stream.position.listen((v) {
        if (v > position) {
          _lastProgress = DateTime.now();
          _failureTimer?.cancel();
          _failureTimer = null;
          error = null;
        }
        position = v;
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
      }),
      player.stream.error.listen((v) {
        _lastFailure =
            specificPlaybackFailure(v) ?? _lastFailure ?? playbackFailure(v);
        // MPV can report recoverable decoder/probe errors before succeeding.
        // Do not cover working video with a permanent error overlay.
        _failureTimer ??= Timer(const Duration(seconds: 3), () {
          _failureTimer = null;
          if (!terminated &&
              DateTime.now().difference(_lastProgress).inSeconds >= 3) {
            error = _lastFailure;
            notifyListeners();
          }
        });
      }),
    ]);
  }
  final bool software;
  Timer? _failureTimer;
  String? _lastFailure;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  final player = mk.Player(
    configuration: const mk.PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );
  late final controller = VideoController(
    player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !software,
      hwdec: software ? 'no' : null,
    ),
  );
  final _subscriptions = <StreamSubscription>[];
  @override
  EngineKind get kind => software ? EngineKind.mpvSoftware : EngineKind.mpv;
  @override
  Widget surface() => Video(controller: controller, controls: NoVideoControls);
  @override
  Future<void> open(
    MediaItem item, {
    String? url,
    Duration start = Duration.zero,
  }) async {
    error = null;
    _lastFailure = null;
    _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
    _failureTimer?.cancel();
    _failureTimer = null;
    // Initialize the video output before opening media, independent of when
    // Flutter mounts the surface (important for desktop texture initialization).
    try {
      await controller.platform.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      throw StateError(
        'Video output could not initialize. Try MPV (software decoding) and update the graphics driver.',
      );
    }
    await player.setVolume(initialVolume * 100);
    final native = player.platform;
    if (native is mk.NativePlayer) {
      // Xtream servers may need time to start a channel or redirect to a CDN.
      // media_kit otherwise uses a five-second network timeout.
      await native.setProperty('network-timeout', '25');
    }
    await player.open(
      mk.Media(url ?? item.url, httpHeaders: item.headers, start: start),
    );
  }

  @override
  Future<void> toggle() => player.playOrPause();
  @override
  Future<void> seek(Duration value) => player.seek(value);
  @override
  Future<void> volume(double value) => player.setVolume(value * 100);
  @override
  Future<void> frameRate(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final native = player.platform;
    if (native is! mk.NativePlayer) {
      throw StateError('Frame-rate matching requires native playback.');
    }
    final fps = enabled
        ? double.tryParse(await mpvProperty(player, 'container-fps'))
        : 0.0;
    if (enabled && (fps == null || fps <= 0)) {
      throw StateError('The stream has not reported a frame rate yet.');
    }
    await const MethodChannel(
      'app.lumen/device',
    ).invokeMethod('frameRate', {'enabled': enabled, 'fps': fps});
  }

  @override
  Future<void> close() async {
    if (!beginClose()) return;
    _failureTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await player.dispose();
  }
}

class NativeEngine extends PlaybackEngine {
  @override
  Future<List<PlaybackTrack>> tracks() async {
    if (controller?.isAudioTrackSupportAvailable() != true) return [];
    return (await controller!.getAudioTracks())
        .map(
          (t) => PlaybackTrack(
            t.id,
            t.label ?? t.language ?? t.id,
            selected: t.isSelected,
          ),
        )
        .toList();
  }

  @override
  Future<void> selectTrack(PlaybackTrack track) async =>
      controller?.selectAudioTrack(track.id);
  VideoPlayerController? controller;
  @override
  EngineKind get kind => EngineKind.native;
  void _update() {
    final v = controller!.value;
    playing = v.isPlaying;
    buffering = v.isBuffering || !v.isInitialized;
    position = v.position;
    duration = v.duration;
    if (v.hasError) {
      error =
          specificPlaybackFailure(v.errorDescription ?? '') ??
          'Native playback failed without a recognized cause. Try mpv or VLC for this stream.';
    }
    notifyListeners();
  }

  @override
  Widget surface() => controller?.value.isInitialized == true
      ? Center(
          child: AspectRatio(
            aspectRatio: controller!.value.aspectRatio,
            child: VideoPlayer(controller!),
          ),
        )
      : const SizedBox.expand();
  @override
  Future<void> open(
    MediaItem item, {
    String? url,
    Duration start = Duration.zero,
  }) async {
    controller = VideoPlayerController.networkUrl(
      Uri.parse(url ?? item.url),
      httpHeaders: item.headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    controller!.addListener(_update);
    try {
      await controller!.initialize();
    } catch (failure) {
      throw StateError(
        specificPlaybackFailure(failure.toString()) ??
            'Native playback initialization failed without a recognized cause. Try mpv or VLC for this stream.',
      );
    }
    if (terminated) return;
    await controller!.setVolume(initialVolume);
    if (start > Duration.zero) await controller!.seekTo(start);
    await controller!.play();
  }

  @override
  Future<void> toggle() async {
    if (playing) {
      await controller?.pause();
    } else {
      await controller?.play();
    }
  }

  @override
  Future<void> seek(Duration value) async => controller?.seekTo(value);
  @override
  Future<void> volume(double value) async => controller?.setVolume(value);
  @override
  Future<void> frameRate(bool enabled) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await const MethodChannel(
        'app.lumen/device',
      ).invokeMethod('frameRate', {'enabled': enabled});
    }
  }

  @override
  Future<void> close() async {
    if (!beginClose()) return;
    controller?.removeListener(_update);
    await controller?.dispose();
  }
}

class VlcEngine extends PlaybackEngine {
  @override
  Future<List<PlaybackTrack>> tracks() async {
    if (controller == null) return [];
    final audio = await controller!.getAudioTrack();
    final subtitle = await controller!.getSpuTrack();
    return [
      for (final t in (await controller!.getAudioTracks()).entries)
        PlaybackTrack('${t.key}', t.value, selected: audio == t.key),
      for (final t in (await controller!.getSpuTracks()).entries)
        PlaybackTrack(
          '${t.key}',
          t.value,
          subtitle: true,
          selected: subtitle == t.key,
        ),
    ];
  }

  @override
  Future<void> selectTrack(PlaybackTrack track) async {
    if (track.subtitle) {
      await controller?.setSpuTrack(int.parse(track.id));
    } else {
      await controller?.setAudioTrack(int.parse(track.id));
    }
  }

  Completer<void>? ready;
  VlcPlayerController? controller;
  @override
  EngineKind get kind => EngineKind.vlc;
  void _update() {
    final v = controller!.value;
    playing = v.isPlaying;
    buffering = v.isBuffering;
    position = v.position;
    duration = v.duration;
    if (v.hasError) error = 'VLC could not play this stream.';
    notifyListeners();
  }

  @override
  Widget surface() => controller == null
      ? const SizedBox.expand()
      : VlcPlayer(
          controller: controller!,
          aspectRatio: 16 / 9,
          placeholder: const Center(child: CircularProgressIndicator()),
        );
  @override
  Future<void> open(
    MediaItem item, {
    String? url,
    Duration start = Duration.zero,
  }) async {
    if (item.headers.isNotEmpty) {
      throw const FormatException(
        'Use mpv or native playback for streams requiring custom headers.',
      );
    }
    controller = VlcPlayerController.network(
      url ?? item.url,
      hwAcc: HwAcc.auto,
      autoPlay: false,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1500)]),
      ),
    );
    controller!.addListener(_update);
    ready = Completer<void>();
    controller!.addOnInitListener(() async {
      try {
        if (terminated) return;
        await controller!.setVolume((initialVolume * 100).round());
        if (start > Duration.zero) await controller!.seekTo(start);
        await controller!.play();
        if (!ready!.isCompleted) ready!.complete();
      } catch (e) {
        if (!ready!.isCompleted) ready!.completeError(e);
      }
    });
    notifyListeners();
    await ready!.future.timeout(const Duration(seconds: 25));
  }

  @override
  Future<void> toggle() async {
    if (playing) {
      await controller?.pause();
    } else {
      await controller?.play();
    }
  }

  @override
  Future<void> seek(Duration value) async => controller?.seekTo(value);
  @override
  Future<void> volume(double value) async =>
      controller?.setVolume((value * 100).round());
  @override
  Future<void> close() async {
    if (!beginClose()) return;
    if (ready != null && !ready!.isCompleted) ready!.complete();
    controller?.removeListener(_update);
    await controller?.dispose();
  }
}

PlaybackEngine createEngine(EngineKind preference) {
  final available = PlaybackCapabilities.current.engines;
  final chosen = preference == EngineKind.automatic
      ? available.first
      : preference;
  if (!available.contains(chosen)) {
    throw const FormatException('That engine is unavailable on this device.');
  }
  return switch (chosen) {
    EngineKind.native => NativeEngine(),
    EngineKind.vlc => VlcEngine(),
    EngineKind.browser => createBrowserEngine(),
    EngineKind.mpvSoftware => MpvEngine(software: true),
    _ => MpvEngine(),
  };
}
