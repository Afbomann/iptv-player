import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/security.dart';
import 'package:lumen_iptv/core/backup_limits.dart';
import 'package:lumen_iptv/platform/pairing_io.dart';

void main() {
  for (final download in [false, true]) {
    test(
      'Chunked backup ${download ? "download" : "upload"} rejects replay',
      () async {
        final server = PairingServer(loadAsset: (_) async => 'test asset');
        final received = Completer<Map<String, dynamic>>();
        final client = HttpClient();
        final archive = 'x' * (backupChunkSize + 17);
        try {
          await server.start(
            received.complete,
            transfer: true,
            backup: download ? archive : null,
          );
          final uri = Uri.parse(server.url);
          final fragment = Uri.splitQueryString(uri.fragment);
          final key = SecretKey(base64Decode(fragment['key']!));
          Future<(int, String)> send(int index) async {
            final start = index * backupChunkSize;
            final end = (start + backupChunkSize).clamp(0, archive.length);
            final envelope = jsonDecode(
              await Security.seal(
                jsonEncode({
                  'index': index,
                  if (!download)
                    'bytes': base64Encode(
                      utf8.encode(archive.substring(start, end)),
                    ),
                  if (!download) 'done': end == archive.length,
                }),
                key,
              ),
            );
            final request = await client.postUrl(
              uri.replace(
                path: '/backup/${download ? "download" : "upload"}',
                fragment: '',
              ),
            );
            request.headers.set('Origin', uri.origin);
            request.headers.contentType = ContentType.json;
            final bytes = utf8.encode(
              jsonEncode({...envelope, 'session': fragment['session']}),
            );
            request.contentLength = bytes.length;
            request.add(bytes);
            final response = await request.close();
            return (
              response.statusCode,
              await utf8.decoder.bind(response).join(),
            );
          }

          final first = await send(0);
          expect(first.$1, download ? 200 : 202);
          expect((await send(0)).$1, 409);
          final last = await send(1);
          expect(last.$1, download ? 200 : 202);
          if (download) {
            final a = jsonDecode(await Security.open(first.$2, key));
            final b = jsonDecode(await Security.open(last.$2, key));
            expect(a['done'], false);
            expect(b['done'], true);
            expect(
              utf8.decode([
                ...base64Decode(a['bytes']),
                ...base64Decode(b['bytes']),
              ]),
              archive,
            );
          } else {
            expect((await received.future)['backup'], archive);
          }
          expect((await send(1)).$1, 410);
        } finally {
          client.close(force: true);
          await server.close();
        }
      },
    );
  }
  test(
    'LAN pairing verifies session, decrypts fields, and rejects reuse',
    () async {
      final server = PairingServer(loadAsset: (_) async => 'test asset');
      final received = Completer<Map<String, dynamic>>();
      final client = HttpClient();
      try {
        await server.start(received.complete);
        final uri = Uri.parse(server.url);
        final fragment = Uri.splitQueryString(uri.fragment);
        final origin = uri.origin;
        final envelope = jsonDecode(
          await Security.seal(
            jsonEncode({
              'name': 'My TV',
              'url': 'https://provider.test',
              'username': 'person',
              'password': 'private secret',
            }),
            SecretKey(base64Decode(fragment['key']!)),
          ),
        );
        Future<int> send(String session) async {
          final req = await client.postUrl(
            uri.replace(path: '/submit', fragment: ''),
          );
          req.headers.set('Origin', origin);
          req.headers.contentType = ContentType.json;
          final bytes = utf8.encode(
            jsonEncode({...envelope, 'session': session}),
          );
          req.contentLength = bytes.length;
          req.add(bytes);
          final response = await req.close();
          await response.drain<void>();
          return response.statusCode;
        }

        expect(await send('wrong'), 403);
        final simultaneous = await Future.wait([
          send(fragment['session']!),
          send(fragment['session']!),
        ]);
        expect(simultaneous, unorderedEquals([202, 410]));
        expect((await received.future)['password'], 'private secret');
        expect(await send(fragment['session']!), 410);
      } finally {
        client.close(force: true);
        await server.close();
      }
    },
  );
}
