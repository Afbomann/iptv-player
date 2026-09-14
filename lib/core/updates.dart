import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../platform/device.dart';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
    required this.notes,
  });
  final String version, url, sha256, notes;
  final int build;
}

class UpdateService {
  static const currentBuild = int.fromEnvironment(
    'LUMEN_BUILD_NUMBER',
    defaultValue: 1,
  );
  static const currentVersion = String.fromEnvironment(
    'LUMEN_VERSION',
    defaultValue: '0.1.0',
  );
  static const manifestUrl = String.fromEnvironment('LUMEN_UPDATE_URL');
  static const publicKey = String.fromEnvironment('LUMEN_UPDATE_PUBLIC_KEY');
  static bool get configured => manifestUrl.isNotEmpty && publicKey.isNotEmpty;
  static String get platform => kIsWeb
      ? 'web'
      : isAppleTV
      ? 'tvos'
      : defaultTargetPlatform.name.toLowerCase();
  static Future<ReleaseInfo?> check({http.Client? client}) async {
    if (!configured) return null;
    final uri = Uri.parse(manifestUrl);
    if (uri.scheme != 'https') {
      throw const FormatException('Update metadata must use HTTPS.');
    }
    final own = client ?? http.Client();
    try {
      final response = await own.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 1024 * 1024) {
        throw const FormatException('Update metadata is unavailable.');
      }
      return await verify(response.body, publicKey, platform);
    } finally {
      if (client == null) own.close();
    }
  }

  static Future<ReleaseInfo?> verify(
    String envelope,
    String key,
    String target,
  ) async {
    final json = jsonDecode(envelope);
    final payload = base64Decode(json['payload']);
    final signature = Signature(
      base64Decode(json['signature']),
      publicKey: SimplePublicKey(base64Decode(key), type: KeyPairType.ed25519),
    );
    if (!await Ed25519().verify(payload, signature: signature)) {
      throw const FormatException('Update signature is invalid.');
    }
    final manifest = jsonDecode(utf8.decode(payload));
    if (manifest['schema'] != 1 ||
        manifest['build'] is! int ||
        manifest['build'] <= 0 ||
        manifest['version'] is! String ||
        manifest['assets'] is! Map) {
      throw const FormatException('Unsupported update manifest.');
    }
    if (manifest['build'] <= currentBuild) return null;
    final asset = manifest['assets'][target];
    if (asset == null) return null;
    final uri = Uri.parse(asset['url']);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset['sha256'])) {
      throw const FormatException('Invalid release asset.');
    }
    return ReleaseInfo(
      version: manifest['version'],
      build: manifest['build'],
      url: asset['url'],
      sha256: asset['sha256'],
      notes: manifest['notes'] ?? '',
    );
  }
}
