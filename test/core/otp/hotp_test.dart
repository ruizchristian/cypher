import 'dart:convert';

import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:flutter_test/flutter_test.dart';

// RFC 4226 Appendix D: secret "12345678901234567890", SHA1, 6 digits.
const _rfc4226 = [
  '755224',
  '287082',
  '359152',
  '969429',
  '338314',
  '254676',
  '287922',
  '162583',
  '399871',
  '520489',
];

void main() {
  final secret = OtpSecret(utf8.encode('12345678901234567890'));

  group('Hotp.generate', () {
    for (var counter = 0; counter < _rfc4226.length; counter++) {
      test('RFC 4226 counter $counter -> ${_rfc4226[counter]}', () {
        expect(Hotp.generate(secret, counter: counter), _rfc4226[counter]);
      });
    }

    test('produces the requested number of digits', () {
      for (final digits in [6, 7, 8]) {
        expect(
          Hotp.generate(secret, counter: 0, digits: digits),
          hasLength(digits),
        );
      }
    });

    test('supports counters beyond 32 bits', () {
      final code = Hotp.generate(secret, counter: 0x1FFFFFFFF);
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(code, isNot(Hotp.generate(secret, counter: 0xFFFFFFFF)));
    });

    test('different algorithms give different codes', () {
      final codes = {
        for (final algorithm in HashAlgorithm.values)
          Hotp.generate(secret, counter: 1, algorithm: algorithm),
      };
      expect(codes, hasLength(3));
    });

    test('rejects a negative counter', () {
      expect(() => Hotp.generate(secret, counter: -1), throwsArgumentError);
    });

    test('rejects digits outside 6-8', () {
      expect(
        () => Hotp.generate(secret, counter: 0, digits: 5),
        throwsRangeError,
      );
      expect(
        () => Hotp.generate(secret, counter: 0, digits: 9),
        throwsRangeError,
      );
    });
  });
}
