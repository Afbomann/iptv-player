import 'package:media_kit/media_kit.dart';

Future<String> mpvProperty(Player player, String name) async {
  final native = player.platform;
  if (native is! NativePlayer) {
    throw StateError('Native mpv is unavailable.');
  }
  return native.getProperty(name);
}
