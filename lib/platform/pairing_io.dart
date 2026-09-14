import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import '../core/security.dart';

class PairingServer {
  PairingServer({this.loadAsset});
  final Future<String> Function(String)? loadAsset;
  HttpServer? _server;
  Timer? _expiry;
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
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final origin = 'http://${addresses.first.address}:${_server!.port}';
    url =
        '$origin/#${Uri(queryParameters: {'session': session, 'key': base64Encode(keyBytes), if (transfer) 'mode': backup == null ? 'upload' : 'download'}).query}';
    _expiry = Timer(const Duration(minutes: 5), close);
    final html = await (loadAsset ?? rootBundle.loadString)(
      'assets/pairing/index.html',
    );
    final js = await (loadAsset ?? rootBundle.loadString)(
      'assets/pairing/pairing.js',
    );
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
        } else if (request.method == 'POST' &&
            request.uri.path == '/download' &&
            backup != null &&
            !used) {
          if (request.headers.value('origin') != origin ||
              request.contentLength < 0 ||
              request.contentLength > 1024) {
            request.response.statusCode = 403;
            return;
          }
          final body = jsonDecode(
            await utf8.decoder
                .bind(request)
                .join()
                .timeout(const Duration(seconds: 10)),
          );
          if (body['session'] != session) {
            request.response.statusCode = 403;
            return;
          }
          if (used) {
            request.response.statusCode = 410;
            return;
          }
          used = true;
          request.response.headers.contentType = ContentType.json;
          request.response.write(await Security.seal(backup, key));
        } else if (request.method == 'POST' &&
            request.uri.path == '/submit' &&
            !used) {
          if (request.headers.value('origin') != origin ||
              request.contentLength < 0 ||
              request.contentLength > (transfer ? 96 * 1024 * 1024 : 16384)) {
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
              (transfer
                  ? payload['backup'] is! String
                  : (payload['url'] is! String ||
                        payload['name'] is! String))) {
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
        await request.response.close();
        if (pending != null) onSubmit(pending);
      }
    });
  }

  Future<void> close() async {
    _expiry?.cancel();
    await _server?.close(force: true);
    _server = null;
  }
}
