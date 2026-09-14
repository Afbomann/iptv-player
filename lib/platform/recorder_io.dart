import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StreamRecorder {
  StreamRecorder({this.directory});
  final Future<Directory> Function()? directory;
  final _clients = <String, HttpClient>{};
  final _stopped = <String>{};
  Future<String> record({
    required String id,
    required String url,
    required DateTime end,
    Map<String, String> headers = const {},
    int maxBytes = 4294967296,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Invalid recording identifier.');
    }
    final folder = directory != null
        ? await directory!()
        : Directory(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              'Lumen',
              'Recordings',
            ),
          );
    await folder.create(recursive: true);
    final path = p.join(folder.path, '$id.ts');
    final sink = File(path).openWrite();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _clients[id] = client;
    _stopped.remove(id);
    var bytes = 0;
    final seen = <String>{};
    final timer = Timer(
      end.difference(DateTime.now()).isNegative
          ? Duration.zero
          : end.difference(DateTime.now()),
      () => stop(id),
    );
    Future<HttpClientResponse> fetch(Uri uri) async {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != 200) {
        throw const FormatException('Recording stream returned an error.');
      }
      return response;
    }

    Future<void> write(HttpClientResponse response) async {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (_stopped.contains(id)) break;
        bytes += chunk.length;
        if (bytes > maxBytes) {
          throw const FormatException('Recording size limit reached.');
        }
        sink.add(chunk);
        if (bytes % (1024 * 1024) < chunk.length) await sink.flush();
      }
    }

    try {
      var uri = Uri.parse(url);
      var response = await fetch(uri);
      uri = effectiveRecordingUri(uri, response);
      final hls =
          uri.path.toLowerCase().endsWith('.m3u8') ||
          response.headers.contentType?.mimeType.toLowerCase().contains(
                'mpegurl',
              ) ==
              true;
      if (!hls) {
        await write(response);
      } else {
        while (!_stopped.contains(id) && DateTime.now().isBefore(end)) {
          final text = await utf8.decoder.bind(response).join();
          if (text.length > 2 * 1024 * 1024) {
            throw const FormatException('HLS manifest is too large.');
          }
          if (RegExp(r'#EXT-X-KEY:([^\r\n]+)')
              .allMatches(text)
              .any(
                (m) => !RegExp(r'^METHOD=NONE(?:,|$)').hasMatch(m.group(1)!),
              )) {
            throw const FormatException(
              'Encrypted HLS recording is not supported.',
            );
          }
          if (text.contains('#EXT-X-MAP:') ||
              text.contains('#EXT-X-BYTERANGE:')) {
            throw const FormatException(
              'This HLS recording format is not supported; use a TS stream.',
            );
          }
          final segments = const LineSplitter()
              .convert(text)
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty && !l.startsWith('#'))
              .toList();
          if (text.contains('#EXT-X-STREAM-INF:')) {
            if (segments.isEmpty) {
              throw const FormatException('Empty HLS master playlist.');
            }
            uri = uri.resolve(segments.first);
            response = await fetch(uri);
            uri = effectiveRecordingUri(uri, response);
            continue;
          }
          for (final segment in segments) {
            final resolved = uri.resolve(segment);
            if (seen.add(resolved.toString())) {
              await write(await fetch(resolved));
            }
            if (_stopped.contains(id)) break;
          }
          if (text.contains('#EXT-X-ENDLIST')) break;
          if (seen.length > 2000) {
            seen.removeAll(seen.take(seen.length - 1000).toList());
          }
          await Future<void>.delayed(const Duration(seconds: 2));
          if (_stopped.contains(id)) break;
          response = await fetch(uri);
          uri = effectiveRecordingUri(uri, response);
        }
      }
      if (bytes == 0) throw const FormatException('No media was received.');
      return path;
    } catch (_) {
      if (_stopped.contains(id) && bytes > 0) return path;
      rethrow;
    } finally {
      timer.cancel();
      client.close(force: true);
      _clients.remove(id);
      _stopped.remove(id);
      await sink.flush();
      await sink.close();
    }
  }

  void stop(String id) {
    _stopped.add(id);
    _clients[id]?.close(force: true);
  }

  Future<void> close() async {
    for (final id in _clients.keys.toList()) {
      stop(id);
    }
  }
}

Uri effectiveRecordingUri(Uri requested, HttpClientResponse response) {
  return response.redirects.fold(
    requested,
    (uri, redirect) => uri.resolveUri(redirect.location),
  );
}
