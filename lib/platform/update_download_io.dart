import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/updates.dart';

String packageExtension(ReleaseInfo release) {
  final uri = Uri.parse(release.url);
  final expected = Platform.isAndroid
      ? '.apk'
      : Platform.isWindows
      ? '.exe'
      : Platform.isLinux
      ? '.deb'
      : '';
  if (expected.isEmpty ||
      p.extension(uri.path).toLowerCase() != expected ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      release.build <= UpdateService.currentBuild ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(release.sha256)) {
    throw const FormatException(
      'Unsupported or invalid update package for this platform.',
    );
  }
  return expected;
}

Future<String> downloadUpdate(ReleaseInfo release) async {
  final extension = packageExtension(release);
  final root = Directory(
    p.join((await getApplicationSupportDirectory()).path, 'updates'),
  );
  await root.create(recursive: true);
  final folder = await root.createTemp('release-${release.build}-');
  final partial = File(p.join(folder.path, 'download.part'));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  var complete = false;
  try {
    var uri = Uri.parse(release.url);
    HttpClientResponse? response;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        throw const FormatException(
          'Update redirect must use HTTPS without embedded credentials.',
        );
      }
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      response = await request.close().timeout(const Duration(seconds: 30));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || redirects == 5) {
        throw const FormatException('Invalid update redirect.');
      }
      await response.drain<void>().timeout(const Duration(seconds: 30));
      uri = uri.resolve(location);
    }
    if (response == null || response.statusCode != 200) {
      throw const FormatException('Release download failed.');
    }
    if (response.contentLength > 1024 * 1024 * 1024) {
      throw const FormatException('Release package is too large.');
    }
    final sink = partial.openWrite();
    try {
      var size = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        size += chunk.length;
        if (size > 1024 * 1024 * 1024) {
          throw const FormatException('Release package is too large.');
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if ((await sha256.bind(partial.openRead()).first).toString() !=
        release.sha256) {
      throw const FormatException(
        'Release checksum failed. The package was discarded.',
      );
    }
    final file = await partial.rename(
      p.join(folder.path, 'lumen-${release.build}$extension'),
    );
    complete = true;
    return file.path;
  } finally {
    client.close(force: true);
    if (!complete && await folder.exists()) {
      await folder.delete(recursive: true);
    }
  }
}

/// Called only after the user chooses Install. Never bypass OS approval.
Future<void> installUpdate(String path, ReleaseInfo release) async {
  final extension = packageExtension(release);
  final root = await Directory(
    p.join((await getApplicationSupportDirectory()).path, 'updates'),
  ).resolveSymbolicLinks();
  final file = File(path);
  final canonical = await file.resolveSymbolicLinks();
  if (!p.isWithin(root, canonical) ||
      p.extension(canonical) != extension ||
      (await sha256.bind(file.openRead()).first).toString() != release.sha256) {
    throw const FormatException(
      'The downloaded package is no longer valid. Download it again.',
    );
  }
  if (Platform.isAndroid) {
    await const MethodChannel(
      'app.lumen/device',
    ).invokeMethod('installUpdate', {'path': canonical});
  } else if (Platform.isWindows) {
    await Process.start(canonical, ['/SP-'], mode: ProcessStartMode.detached);
  } else if (Platform.isLinux) {
    final result = await Process.run('xdg-open', [canonical]);
    if (result.exitCode != 0) {
      throw const FormatException(
        'No package installer could be opened. Install the downloaded .deb with your system package manager.',
      );
    }
  }
}
