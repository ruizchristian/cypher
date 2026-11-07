import 'dart:convert';

import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/data/account.dart';
import 'package:cypher/data/vault_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account(String id, {OtpType type = OtpType.totp}) => Account(
  id: id,
  type: type,
  secret: OtpSecret(utf8.encode('12345678901234567890')),
  createdAt: DateTime.utc(2026, 11, 7, 8, 30, 15, 123),
  issuer: 'Ex: "quoted" ✓',
  accountName: 'alice@example.com',
  algorithm: HashAlgorithm.sha512,
  digits: 8,
  period: 60,
  counter: type == OtpType.hotp ? 1 << 40 : 0,
);

/// A fresh, mutable, valid account entry as it appears in vault JSON.
Map<String, Object?> _validEntry() {
  final root = jsonDecode(
    utf8.decode(VaultCodec.encode([_account('a')])),
  ) as Map<String, Object?>;
  return (root['accounts']! as List<Object?>).first! as Map<String, Object?>;
}

List<int> _vaultWith(Map<String, Object?> entry) => utf8.encode(
  jsonEncode({
    'schema': 1,
    'accounts': [entry],
  }),
);

Matcher get _formatError => throwsA(isA<VaultFormatException>());

void main() {
  test('round-trips every field and preserves order', () {
    final accounts = [_account('b'), _account('a', type: OtpType.hotp)];
    final decoded = VaultCodec.decode(VaultCodec.encode(accounts));
    expect(decoded.map((a) => a.id), ['b', 'a']);
    for (var i = 0; i < accounts.length; i++) {
      final (x, y) = (accounts[i], decoded[i]);
      expect(
        (
          y.type,
          y.issuer,
          y.accountName,
          y.algorithm,
          y.digits,
          y.period,
          y.counter,
        ),
        (
          x.type,
          x.issuer,
          x.accountName,
          x.algorithm,
          x.digits,
          x.period,
          x.counter,
        ),
      );
      expect(y.secret, x.secret);
      expect(y.createdAt, x.createdAt);
    }
  });

  test('round-trips an empty vault', () {
    expect(VaultCodec.decode(VaultCodec.encode(const [])), isEmpty);
  });

  test('writes the current schema', () {
    final json = jsonDecode(utf8.decode(VaultCodec.encode(const [])));
    expect(json, {'schema': 1, 'accounts': <Object?>[]});
  });

  test('rejects non-JSON, a wrong root and unknown schemas', () {
    expect(() => VaultCodec.decode(utf8.encode('nope')), _formatError);
    expect(() => VaultCodec.decode(utf8.encode('[]')), _formatError);
    for (final schema in [0, 2, '1', null]) {
      expect(
        () => VaultCodec.decode(
          utf8.encode(jsonEncode({'schema': schema, 'accounts': []})),
        ),
        _formatError,
        reason: '$schema',
      );
    }
  });

  test('rejects each invalid or missing field', () {
    final cases = <String, Object?>{
      'id': '',
      'type': 'steam',
      'alg': 'MD5',
      'digits': 9,
      'period': 0,
      'counter': -1,
      'secret': 'not-base32-1',
      'created': 'yesterday',
      'issuer': 42,
    };
    cases.forEach((field, bad) {
      expect(
        () => VaultCodec.decode(_vaultWith(_validEntry()..[field] = bad)),
        _formatError,
        reason: field,
      );
      expect(
        () => VaultCodec.decode(_vaultWith(_validEntry()..remove(field))),
        _formatError,
        reason: 'missing $field',
      );
    });
  });

  test('rejects duplicate ids', () {
    expect(
      () =>
          VaultCodec.decode(VaultCodec.encode([_account('x'), _account('x')])),
      _formatError,
    );
  });

  test('error messages never contain the secret', () {
    try {
      VaultCodec.decode(_vaultWith(_validEntry()..['digits'] = 99));
      fail('expected failure');
    } on VaultFormatException catch (e) {
      expect(e.toString(), isNot(contains('GEZDGNBV')));
    }
  });
}
