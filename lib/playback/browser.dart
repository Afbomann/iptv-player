import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/models.dart';
import 'types.dart';

@JS('lumenVideo.create')
external VideoBridge _create(JSFunction notify);

extension type VideoBridge(JSObject _) implements JSObject {
  external web.HTMLVideoElement get video;
  external JSPromise<JSAny?> open(
    JSString url,
    JSString headers,
    JSNumber start,
    JSNumber volume,
  );
  external JSString state();
  external JSString tracks();
  external JSPromise<JSAny?> select(JSString id, JSBoolean subtitle);
  external JSPromise<JSAny?> toggle();
  external void seek(JSNumber seconds);
  external void volume(JSNumber value);
  external void dispose();
}

PlaybackEngine createBrowserEngine() => BrowserEngine();

class BrowserEngine extends PlaybackEngine {
  BrowserEngine() {
    bridge = _create(_update.toJS);
  }
  late final VideoBridge bridge;
  @override
  EngineKind get kind => EngineKind.browser;
  void _update() {
    if (terminated) return;
    final data = jsonDecode(bridge.state().toDart);
    playing = data['playing'];
    buffering = data['buffering'];
    error = data['error'];
    position = Duration(
      milliseconds: ((data['position'] as num) * 1000).round(),
    );
    duration = Duration(
      milliseconds: ((data['duration'] as num) * 1000).round(),
    );
    notifyListeners();
  }

  @override
  Widget surface() => HtmlElementView.fromTagName(
    tagName: 'div',
    onElementCreated: (element) {
      final host = element as web.HTMLElement;
      host.style.width = '100%';
      host.style.height = '100%';
      host.style.pointerEvents = 'none';
      host.appendChild(bridge.video);
    },
  );
  @override
  Future<void> open(
    MediaItem item, {
    String? url,
    Duration start = Duration.zero,
  }) async {
    try {
      await bridge
          .open(
            (url ?? item.url).toJS,
            jsonEncode(item.headers).toJS,
            (start.inMilliseconds / 1000).toJS,
            initialVolume.toJS,
          )
          .toDart;
    } catch (_) {
      if (!terminated) {
        error =
            'Browser playback could not start. Check stream format, CORS, and HTTPS permissions.';
        notifyListeners();
      }
    }
  }

  @override
  Future<void> toggle() async {
    await bridge.toggle().toDart;
  }

  @override
  Future<void> seek(Duration value) async =>
      bridge.seek((value.inMilliseconds / 1000).toJS);
  @override
  Future<void> volume(double value) async => bridge.volume(value.toJS);
  @override
  Future<List<PlaybackTrack>> tracks() async =>
      (jsonDecode(bridge.tracks().toDart) as List)
          .map(
            (t) => PlaybackTrack(
              t['id'],
              t['label'],
              subtitle: t['subtitle'],
              selected: t['selected'],
            ),
          )
          .toList();
  @override
  Future<void> selectTrack(PlaybackTrack track) async {
    await bridge.select(track.id.toJS, track.subtitle.toJS).toDart;
  }

  @override
  Future<void> close() async {
    if (beginClose()) bridge.dispose();
  }
}
