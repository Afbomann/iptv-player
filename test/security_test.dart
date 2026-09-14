import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/security.dart';
import 'package:lumen_iptv/core/updates.dart';

void main() {
  test(
    'PINs preserve leading zeroes, use salted hashes, and validate length',
    () async {
      final hash = await Security.hashPin('0042');
      expect(await Security.verify('0042', hash), isTrue);
      expect(await Security.verify('42', hash), isFalse);
      expect(hash, isNot(await Security.hashPin('0042')));
      for (final invalid in ['123', '123456789', 'abcd', '12 34']) {
        expect(() => Security.hashPin(invalid), throwsFormatException);
      }
      await expectLater(Security.hashPassword('0042'), throwsFormatException);
    },
  );
  test('Passwords are salted and incorrect passwords fail', () async {
    final hash = await Security.hashPassword('correct horse battery');
    expect(hash, startsWith('pbkdf2-sha256:600000:'));
    expect(hash, isNot(contains('correct horse')));
    expect(await Security.verify('correct horse battery', hash), isTrue);
    expect(await Security.verify('wrong', hash), isFalse);
    expect(await Security.verify('password', 'malformed'), isFalse);
  });
  test(
    'Encrypted backup round trip rejects tampering and wrong passwords',
    () async {
      final archive = await Security.backup(
        '{"version":1,"secret":"provider password"}',
        'backup passphrase',
      );
      expect(archive, isNot(contains('provider password')));
      expect(
        await Security.restore(archive, 'backup passphrase'),
        contains('provider password'),
      );
      await expectLater(
        Security.restore(archive, 'incorrect password'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final j = jsonDecode(archive);
      final box = jsonDecode(j['data']);
      final bytes = base64Decode(box['cipher']);
      bytes[0] ^= 1;
      box['cipher'] = base64Encode(bytes);
      j['data'] = jsonEncode(box);
      await expectLater(
        Security.restore(jsonEncode(j), 'backup passphrase'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );
  test('Signed updates require a trusted key and a newer build', () async {
    final algorithm = Ed25519();
    final pair = await algorithm.newKeyPair();
    final key = base64Encode((await pair.extractPublicKey()).bytes);
    final payload = utf8.encode(
      jsonEncode({
        'schema': 1,
        'build': 2,
        'version': '0.2.0',
        'assets': {
          'windows': {
            'url': 'https://release.test/lumen.exe',
            'sha256': 'a' * 64,
          },
        },
      }),
    );
    final signature = await algorithm.sign(payload, keyPair: pair);
    final envelope = jsonEncode({
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes),
    });
    expect(
      (await UpdateService.verify(envelope, key, 'windows'))!.version,
      '0.2.0',
    );
    final wrong = await algorithm.newKeyPair();
    await expectLater(
      UpdateService.verify(
        envelope,
        base64Encode((await wrong.extractPublicKey()).bytes),
        'windows',
      ),
      throwsFormatException,
    );
  });
}
