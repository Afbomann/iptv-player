import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:archive/archive.dart';
import 'backup_limits.dart';
import '../platform/backup_gzip.dart'
    if (dart.library.io) '../platform/backup_gzip_io.dart';

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
    if (payload.length > backupExpandedLimit) {
      throw const FormatException(
        'Library exceeds the 512 MB backup safety limit.',
      );
    }
    if (password.length < 10) {
      throw const FormatException(
        'Backup password must be at least 10 characters.',
      );
    }
    final salt = randomBytes(16);
    final encoded = utf8.encode(payload);
    if (encoded.length > backupExpandedLimit) {
      throw const FormatException(
        'Library exceeds the 512 MB backup safety limit.',
      );
    }
    return jsonEncode({
      'format': 'lumen-backup',
      'version': 2,
      'kdf': 'pbkdf2-sha256',
      'iterations': 600000,
      'salt': base64Encode(salt),
      'data': await _sealBytes(
        GZipEncoder().encode(encoded),
        await derive(password, salt),
      ),
    });
  }

  static Future<String> restore(String archive, String password) async {
    if (archive.length > backupTransferLimit) {
      throw const FormatException('Backup exceeds the 256 MB limit.');
    }
    final j = jsonDecode(archive);
    if (j['format'] != 'lumen-backup' ||
        ![1, 2].contains(j['version']) ||
        j['iterations'] != 600000 ||
        j['kdf'] != 'pbkdf2-sha256') {
      throw const FormatException('Unsupported backup format.');
    }
    final key = await derive(password, base64Decode(j['salt']));
    if (j['version'] == 1) return open(j['data'], key);
    final box = jsonDecode(j['data']);
    final compressed = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(box['cipher']),
        nonce: base64Decode(box['nonce']),
        mac: Mac(base64Decode(box['mac'])),
      ),
      secretKey: key,
    );
    final output = _BackupOutput(backupExpandedLimit);
    decodeBackupGzip(compressed, output);
    return utf8.decode(output.getBytes());
  }

  static Future<String> _sealBytes(List<int> bytes, SecretKey key) async {
    final box = await AesGcm.with256bits().encrypt(bytes, secretKey: key);
    return jsonEncode({
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }
}

class _BackupOutput extends OutputMemoryStream {
  _BackupOutput(this.maximum);
  final int maximum;
  void check(int count) {
    if (length + count > maximum) {
      throw const FormatException(
        'Expanded backup exceeds the 512 MB memory safety limit.',
      );
    }
  }

  @override
  void writeByte(int value) {
    check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    check(count);
    super.writeBackReference(distance, count);
  }
}
