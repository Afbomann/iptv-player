import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/security.dart';
import 'package:lumen_iptv/platform/pairing_io.dart';

void main() {
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
