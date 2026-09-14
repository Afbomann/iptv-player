import '../core/updates.dart';

Future<String> downloadUpdate(ReleaseInfo release) async =>
    throw UnsupportedError(
      'Reload the web app to activate the deployed version.',
    );

Future<void> installUpdate(String path, ReleaseInfo release) async =>
    throw UnsupportedError('Use the installer supported by this platform.');
