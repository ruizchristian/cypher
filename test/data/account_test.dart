import 'dart:convert';

import 'package:cypher/core/otp/base32.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/data/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final secretBytes = utf8.encode('12345678901234567890');
  final account = Account(
    id: 'a1',
    type: OtpType.hotp,
    secret: OtpSecret(secretBytes),
    createdAt: DateTime.utc(2026),
    issuer: 'Example',
    accountName: 'alice',
    counter: 3,
  );

  test('toString redacts the secret', () {
    final text = account.toString();
    expect(text, contains('<redacted>'));
    expect(text, isNot(contains(Base32.encode(secretBytes, padding: false))));
    expect(text, isNot(contains('1234567890')));
  });

  test('copyWith changes only names and counter', () {
    final renamed = account.copyWith(issuer: 'New', counter: 4);
    expect(renamed.issuer, 'New');
    expect(renamed.accountName, 'alice');
    expect(renamed.counter, 4);
    expect(renamed.id, account.id);
    expect(renamed.secret, account.secret);
  });

  test('newId is 32 hex characters and unique', () {
    final ids = {for (var i = 0; i < 200; i++) Account.newId()};
    expect(ids, hasLength(200));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    }
  });

  group('isSameAs', () {
    // Type and code parameters do not take part in duplicate detection.
    OtpParameters params({
      List<int>? secret,
      String issuer = 'Example',
      String accountName = 'alice',
    }) => OtpParameters(
      type: OtpType.totp,
      secret: OtpSecret(secret ?? secretBytes),
      issuer: issuer,
      accountName: accountName,
      digits: 8,
    );

    test('an account matches on secret, issuer and account name', () {
      expect(account.isSameAs(params()), isTrue);
      expect(account.isSameAs(params(secret: [1, 2, 3])), isFalse);
      expect(account.isSameAs(params(issuer: 'Other')), isFalse);
      expect(account.isSameAs(params(accountName: 'bob')), isFalse);
    });

    test('parameters compare by the same rule', () {
      expect(params().isSameAs(params()), isTrue);
      expect(params().isSameAs(params(secret: [1, 2, 3])), isFalse);
      expect(params().isSameAs(params(issuer: 'Other')), isFalse);
      expect(params().isSameAs(params(accountName: 'bob')), isFalse);
    });
  });
}
