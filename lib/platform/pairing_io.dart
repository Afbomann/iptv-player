import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import '../core/security.dart';
import 'backup_transport_io.dart';

class PairingServer {
  PairingServer({this.loadAsset});
  final Future<String> Function(String)? loadAsset;
  HttpServer? _server;
  Timer? _expiry;
  BackupTransport? _transfer;
  String url = '';
  bool used = false;
  Future<void> start(
    void Function(Map<String, dynamic>) onSubmit, {
    bool transfer = false,
    String? backup,
  }) async {
    final networks = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final addresses = networks
        .expand((n) => n.addresses)
        .where((a) => !a.isLoopback)
        .toList();
    if (addresses.isEmpty) {
      throw const FormatException(
        'Connect this device to Wi-Fi or Ethernet first.',
      );
    }
    final keyBytes = Security.randomBytes(32);
    final key = SecretKey(keyBytes);
    final session = base64UrlEncode(Security.randomBytes(24));
    final html = await (loadAsset ?? rootBundle.loadString)(
      'assets/pairing/index.html',
    );
    final js = await (loadAsset ?? rootBundle.loadString)(
      'assets/pairing/pairing.js',
    );
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final origin = 'http://${addresses.first.address}:${_server!.port}';
    if (transfer) _transfer = BackupTransport(session, key, origin, backup);
    url =
        '$origin/#${Uri(queryParameters: {'session': session, 'key': base64Encode(keyBytes), if (transfer) 'mode': backup == null ? 'upload' : 'download'}).query}';
    _expiry = Timer(Duration(minutes: transfer ? 30 : 5), close);
    _server!.listen((request) async {
      Map<String, dynamic>? pending;
      try {
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('X-Content-Type-Options', 'nosniff');
        request.response.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
        );
        final host = request.headers.value('host');
        if (host != Uri.parse(origin).authority) {
          request.response.statusCode = 403;
          return;
        }
        if (request.method == 'GET' && request.uri.path == '/') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(html);
        } else if (request.method == 'GET' &&
            request.uri.path == '/pairing.js') {
          request.response.headers.contentType = ContentType(
            'application',
            'javascript',
            charset: 'utf-8',
          );
          request.response.write(js);
        } else if (transfer &&
            request.method == 'POST' &&
            request.uri.path.startsWith('/backup/')) {
          pending = await _transfer!.handle(request);
          used = _transfer!.finished;
        } else if (request.method == 'POST' &&
            request.uri.path == '/submit' &&
            !transfer &&
            !used) {
          if (request.headers.value('origin') != origin ||
              request.contentLength < 0 ||
              request.contentLength > 16384) {
            request.response.statusCode = 403;
            return;
          }
          final body = await utf8.decoder
              .bind(request)
              .join()
              .timeout(const Duration(seconds: 10));
          final envelope = jsonDecode(body);
          if (envelope['session'] != session) {
            request.response.statusCode = 403;
            return;
          }
          final payload = jsonDecode(
            await Security.open(jsonEncode(envelope), key),
          );
          if (payload is! Map ||
              payload['url'] is! String ||
              payload['name'] is! String) {
            request.response.statusCode = 400;
            return;
          }
          if (used) {
            request.response.statusCode = 410;
            return;
          }
          used = true;
          pending = Map<String, dynamic>.from(payload);
          request.response.statusCode = 202;
        } else {
          request.response.statusCode = 410;
        }
      } catch (_) {
        request.response.statusCode = 400;
      } finally {
        try {
          await request.response.close();
        } catch (_) {
          /* Peer closed or session cancelled. */
        }
        if (pending != null) {
          try {
            onSubmit(pending);
          } catch (_) {
            /* A dismissed dialog must not crash the HTTP listener. */
          }
        }
      }
    });
  }

  Future<void> close() async {
    _expiry?.cancel();
    await _server?.close(force: true);
    await _transfer?.close();
    _server = null;
  }
}
