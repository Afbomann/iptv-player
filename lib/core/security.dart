import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class Security {
  static final _random = Random.secure();
  static List<int> randomBytes(int n) =>
      List.generate(n, (_) => _random.nextInt(256));
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );
  static Future<SecretKey> derive(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<String> hashPassword(String password) async {
    if (password.length < 10) {
      throw const FormatException(
        'Use at least 10 characters for your password.',
      );
    }
    return _hashSecret(password);
  }

  static Future<String> hashPin(String pin) {
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      throw const FormatException('Use a PIN of 4–8 digits.');
    }
    return _hashSecret(pin);
  }

  static Future<String> _hashSecret(String password) async {
    final salt = randomBytes(16);
    final hash = await (await derive(password, salt)).extractBytes();
    return 'pbkdf2-sha256:600000:${base64Encode(salt)}:${base64Encode(hash)}';
  }

  static Future<bool> verify(String password, String stored) async {
    try {
      final parts = stored.split(':');
      if (parts.length != 4 ||
          parts[0] != 'pbkdf2-sha256' ||
          parts[1] != '600000') {
        return false;
      }
      final actual = await (await derive(
        password,
        base64Decode(parts[2]),
      )).extractBytes();
      final expected = base64Decode(parts[3]);
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var i = 0; i < actual.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String> seal(String plaintext, SecretKey key) async {
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return jsonEncode({
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<String> open(String envelope, SecretKey key) async {
    final j = jsonDecode(envelope);
    final bytes = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(j['cipher']),
        nonce: base64Decode(j['nonce']),
        mac: Mac(base64Decode(j['mac'])),
      ),
      secretKey: key,
    );
    return utf8.decode(bytes);
  }

  static Future<String> backup(String payload, String password) async {
    if (password.length < 10) {
      throw const FormatException(
        'Backup password must be at least 10 characters.',
      );
    }
    final salt = randomBytes(16);
    return jsonEncode({
      'format': 'lumen-backup',
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': 600000,
      'salt': base64Encode(salt),
      'data': await seal(payload, await derive(password, salt)),
    });
  }

  static Future<String> restore(String archive, String password) async {
    final j = jsonDecode(archive);
    if (j['format'] != 'lumen-backup' ||
        j['version'] != 1 ||
        j['iterations'] != 600000 ||
        j['kdf'] != 'pbkdf2-sha256') {
      throw const FormatException('Unsupported backup format.');
    }
    return open(j['data'], await derive(password, base64Decode(j['salt'])));
  }
}
