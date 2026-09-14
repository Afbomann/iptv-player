import 'package:flutter/services.dart';

Future<void> enterFullscreen() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
Future<void> leaveFullscreen() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
Future<void> toggleFullscreen() => enterFullscreen();
