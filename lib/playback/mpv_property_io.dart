import 'package:media_kit/media_kit.dart';

Future<void> setMpvProperty(Player player, String name, String value) async {
  final native = player.platform;
  if (native is! NativePlayer) {
    throw StateError('Native mpv is unavailable.');
  }
  await native.setProperty(name, value);
}

Future<String> mpvProperty(Player player, String name) async {
  final native = player.platform;
  if (native is! NativePlayer) {
    throw StateError('Native mpv is unavailable.');
  }
  return native.getProperty(name);
}
