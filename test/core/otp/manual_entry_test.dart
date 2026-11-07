import 'dart:convert';

import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/manual_entry.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:flutter_test/flutter_test.dart';

// Base32 of the RFC 4226 test secret "12345678901234567890".
const _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

void main() {
  ManualEntryResult validate({
    String issuer = 'Example',
    String accountName = 'alice',
    String secret = _secret,
    OtpType type = OtpType.totp,
    String period = '30',
    String counter = '0',
  }) => ManualEntry.validate(
    issuer: issuer,
    accountName: accountName,
    secret: secret,
    type: type,
    period: period,
    counter: counter,
  );

  Map<ManualEntryField, ManualEntryError> errorsOf(ManualEntryResult r) =>
      (r as ManualEntryInvalid).errors;

  test('accepts a typical key and trims names', () {
    final result = validate(issuer: '  GitHub ', accountName: ' octocat ');
    final p = (result as ManualEntryValid).parameters;
    expect((p.issuer, p.accountName, p.period), ('GitHub', 'octocat', 30));
    expect(p.secret.bytes, utf8.encode('12345678901234567890'));
  });

  test('accepts keys as websites show them: lowercase, grouped, dashed', () {
    for (final shown in [
      _secret.toLowerCase(),
      'GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ',
      'gezd-gnbv-gy3t-qojq-gezd-gnbv-gy3t-qojq',
    ]) {
      final p = (validate(secret: shown) as ManualEntryValid).parameters;
      expect(Hotp.generate(p.secret, counter: 0), '755224', reason: shown);
    }
  });

  test('needs an issuer or an account name, not both', () {
    expect(validate(accountName: ''), isA<ManualEntryValid>());
    expect(validate(issuer: ''), isA<ManualEntryValid>());
    expect(errorsOf(validate(issuer: ' ', accountName: '')), {
      ManualEntryField.name: ManualEntryError.nameMissing,
    });
  });

  test('reports a missing or invalid secret', () {
    expect(
      errorsOf(validate(secret: '  '))[ManualEntryField.secret],
      ManualEntryError.secretMissing,
    );
    for (final bad in ['GEZDG0BV', 'GEZDG1BV', 'not a key!', '===']) {
      expect(
        errorsOf(validate(secret: bad))[ManualEntryField.secret],
        ManualEntryError.secretInvalid,
        reason: bad,
      );
    }
  });

  test('validates the period for TOTP only', () {
    for (final bad in ['0', '-30', 'abc', '']) {
      expect(
        errorsOf(validate(period: bad))[ManualEntryField.period],
        ManualEntryError.periodInvalid,
        reason: bad,
      );
    }
    expect(
      validate(type: OtpType.hotp, period: 'abc'),
      isA<ManualEntryValid>(),
    );
  });

  test('validates the counter for HOTP only', () {
    expect(
      errorsOf(
        validate(type: OtpType.hotp, counter: '-1'),
      )[ManualEntryField.counter],
      ManualEntryError.counterInvalid,
    );
    final p = (validate(
      type: OtpType.hotp,
      counter: '7',
    ) as ManualEntryValid).parameters;
    expect((p.type, p.counter), (OtpType.hotp, 7));
    expect(validate(counter: 'abc'), isA<ManualEntryValid>()); // TOTP
  });

  test('reports every failing field at once', () {
    expect(
      errorsOf(validate(issuer: '', accountName: '', secret: '', period: '0'))
          .keys,
      unorderedEquals([
        ManualEntryField.name,
        ManualEntryField.secret,
        ManualEntryField.period,
      ]),
    );
  });
}
