import 'dart:convert';
import 'dart:typed_data';

import 'package:cypher/core/security/vault_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _failsWith(VaultDecryptFailure reason) => throwsA(
  isA<VaultDecryptException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  final key = VaultCipher.newKey();
  final plaintext = utf8.encode('{"schema":1,"accounts":[]}');

  test('round-trips', () async {
    final sealed = await VaultCipher.encrypt(plaintext, key);
    expect(await VaultCipher.decrypt(sealed, key), plaintext);
  });

  test('writes the documented layout', () async {
    final sealed = await VaultCipher.encrypt(plaintext, key);
    expect(sealed.sublist(0, 4), ascii.encode('CYVT'));
    expect(sealed[4], 1);
    expect(
      sealed.length,
      VaultCipher.headerLength + plaintext.length + VaultCipher.macLength,
    );
    expect(
      utf8.decode(sealed, allowMalformed: true),
      isNot(contains('schema')),
    );
  });

  test('uses a fresh nonce for every encryption', () async {
    final nonces = <String>{};
    for (var i = 0; i < 50; i++) {
      final sealed = await VaultCipher.encrypt(plaintext, key);
      nonces.add(base64.encode(sealed.sublist(5, VaultCipher.headerLength)));
    }
    expect(nonces, hasLength(50));
  });

  test('new keys are 32 random bytes', () {
    final keys = {
      for (var i = 0; i < 20; i++) base64.encode(VaultCipher.newKey()),
    };
    expect(keys, hasLength(20));
    expect(VaultCipher.newKey(), hasLength(32));
  });

  test('rejects the wrong key', () async {
    final sealed = await VaultCipher.encrypt(plaintext, key);
    expect(
      VaultCipher.decrypt(sealed, VaultCipher.newKey()),
      _failsWith(VaultDecryptFailure.authenticationFailed),
    );
  });

  test('detects a flipped bit anywhere after the version byte', () async {
    final sealed = await VaultCipher.encrypt(plaintext, key);
    for (var i = 5; i < sealed.length; i++) {
      final tampered = Uint8List.fromList(sealed)..[i] ^= 0x01;
      await expectLater(
        VaultCipher.decrypt(tampered, key),
        _failsWith(VaultDecryptFailure.authenticationFailed),
        reason: 'byte $i',
      );
    }
  });

  test('rejects a wrong magic, an unknown version and short input', () async {
    final sealed = await VaultCipher.encrypt(plaintext, key);
    expect(
      VaultCipher.decrypt(Uint8List.fromList(sealed)..[0] = 0, key),
      _failsWith(VaultDecryptFailure.notAVault),
    );
    expect(
      VaultCipher.decrypt(Uint8List.fromList(sealed)..[4] = 2, key),
      _failsWith(VaultDecryptFailure.unsupportedVersion),
    );
    expect(
      VaultCipher.decrypt(sealed.sublist(0, 20), key),
      _failsWith(VaultDecryptFailure.notAVault),
    );
  });

  test('rejects keys of the wrong length', () {
    expect(
      () => VaultCipher.encrypt(plaintext, Uint8List(16)),
      throwsArgumentError,
    );
  });

  test('the exception message carries no data', () {
    expect(
      const VaultDecryptException(VaultDecryptFailure.authenticationFailed)
          .toString(),
      'VaultDecryptException(authenticationFailed)',
    );
  });
}
