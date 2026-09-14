import 'package:media_kit/media_kit.dart';

Future<void> setMpvProperty(Player player, String name, String value) async {
  throw UnsupportedError('Native mpv is unavailable on this platform.');
}

Future<String> mpvProperty(Player player, String name) async => '';
