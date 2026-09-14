import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/platform/recorder_io.dart';

void main() {
  late HttpServer server;
  late Directory folder;
  late StreamRecorder recorder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('lumen-recording-test-');
    recorder = StreamRecorder(directory: () async => folder);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await recorder.close();
    await server.close(force: true);
    await folder.delete(recursive: true);
  });
  test('Clear HLS resolves relative segments and writes each once', () async {
    server.listen((r) async {
      if (r.uri.path == '/live.m3u8') {
        r.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        r.response.write(
          '#EXTM3U\n#EXTINF:1,\none.ts\n#EXTINF:1,\ntwo.ts\n#EXT-X-ENDLIST',
        );
      } else {
        r.response.add(List.filled(188, r.uri.path == '/one.ts' ? 1 : 2));
      }
      await r.response.close();
    });
    final path = await recorder.record(
      id: 'hls-test',
      url: 'http://127.0.0.1:${server.port}/live.m3u8',
      end: DateTime.now().add(const Duration(minutes: 1)),
    );
    final bytes = await File(path).readAsBytes();
    expect(bytes, hasLength(376));
    expect(bytes.first, 1);
    expect(bytes.last, 2);
  });
  test(
    'HLS resolves master and media paths after multiple redirects',
    () async {
      final requested = <String>[];
      server.listen((r) async {
        final path = r.uri.path;
        requested.add(path);
        final redirect = {
          '/start': '/redirect/entry',
          '/redirect/entry': '../cdn/master.m3u8',
          '/cdn/variant.m3u8': '/media/live.m3u8',
        }[path];
        if (redirect != null) {
          r.response.statusCode = 302;
          r.response.headers.set('location', redirect);
        } else if (path == '/cdn/master.m3u8') {
          r.response.write(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nvariant.m3u8',
          );
        } else if (path == '/media/live.m3u8') {
          r.response.write('#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST');
        } else if (path == '/media/segment.ts') {
          r.response.add(List.filled(188, 7));
        } else {
          r.response.statusCode = 404;
        }
        await r.response.close();
      });
      final path = await recorder.record(
        id: 'redirected',
        url: 'http://127.0.0.1:${server.port}/start',
        end: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(await File(path).readAsBytes(), List.filled(188, 7));
      expect(requested, [
        '/start',
        '/redirect/entry',
        '/cdn/master.m3u8',
        '/cdn/variant.m3u8',
        '/media/live.m3u8',
        '/media/segment.ts',
      ]);
    },
  );
  test(
    'Encrypted HLS is rejected even if a METHOD=NONE tag is also present',
    () async {
      server.listen((r) async {
        r.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        r.response.write(
          '#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:1,\none.ts',
        );
        await r.response.close();
      });
      await expectLater(
        recorder.record(
          id: 'encrypted',
          url: 'http://127.0.0.1:${server.port}/live.m3u8',
          end: DateTime.now().add(const Duration(seconds: 10)),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Output limits abort recording and unsafe identifiers are rejected',
    () async {
      server.listen((r) async {
        r.response.add(List.filled(1000, 1));
        await r.response.close();
      });
      await expectLater(
        recorder.record(
          id: 'limit',
          url: 'http://127.0.0.1:${server.port}/stream.ts',
          end: DateTime.now().add(const Duration(seconds: 10)),
          maxBytes: 100,
        ),
        throwsFormatException,
      );
      await expectLater(
        recorder.record(
          id: '../outside',
          url: 'http://127.0.0.1:${server.port}/stream.ts',
          end: DateTime.now(),
        ),
        throwsFormatException,
      );
    },
  );
}
