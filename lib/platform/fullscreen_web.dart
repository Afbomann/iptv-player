import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> enterFullscreen() async {
  if (web.document.fullscreenElement == null) {
    try {
      await web.document.documentElement!.requestFullscreen().toDart;
    } catch (_) {
      /* Browser may require the explicit fullscreen button. */
    }
  }
}

Future<void> leaveFullscreen() async {
  if (web.document.fullscreenElement != null) {
    await web.document.exitFullscreen().toDart;
  }
}

Future<void> toggleFullscreen() => web.document.fullscreenElement == null
    ? enterFullscreen()
    : leaveFullscreen();
