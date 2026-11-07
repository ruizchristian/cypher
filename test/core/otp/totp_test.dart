import 'dart:convert';

import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/otp/totp.dart';
import 'package:flutter_test/flutter_test.dart';

// RFC 6238 Appendix B: 8 digits, period 30, T0 = 0.
const _rfc6238 = <(int, String, String, String)>[
  // (unix seconds, SHA1, SHA256, SHA512)
  (59, '94287082', '46119246', '90693936'),
  (1111111109, '07081804', '68084774', '25091201'),
  (1111111111, '14050471', '67062674', '99943326'),
  (1234567890, '89005924', '91819424', '93441116'),
  (2000000000, '69279037', '90698825', '38618901'),
  (20000000000, '65353130', '77737706', '47863826'),
];

DateTime _at(int seconds, [int millis = 0]) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + millis, isUtc: true);

void main() {
  // RFC 6238 uses a different seed length per algorithm.
  final seeds = {
    HashAlgorithm.sha1: OtpSecret(utf8.encode('12345678901234567890')),
    HashAlgorithm.sha256: OtpSecret(
      utf8.encode('12345678901234567890123456789012'),
    ),
    HashAlgorithm.sha512: OtpSecret(
      utf8.encode(
        '1234567890123456789012345678901234567890123456789012345678901234',
      ),
    ),
  };

  group('Totp.generate RFC 6238 vectors', () {
    for (final (seconds, sha1, sha256, sha512) in _rfc6238) {
      final expected = {
        HashAlgorithm.sha1: sha1,
        HashAlgorithm.sha256: sha256,
        HashAlgorithm.sha512: sha512,
      };
      for (final MapEntry(key: algorithm, value: code) in expected.entries) {
        test('T=$seconds ${algorithm.name} -> $code', () {
          expect(
            Totp.generate(
              seeds[algorithm]!,
              at: _at(seconds),
              algorithm: algorithm,
              digits: 8,
            ),
            code,
          );
        });
      }
    }
  });

  group('Totp.timeStep', () {
    test('steps change exactly on period boundaries', () {
      expect(Totp.timeStep(_at(0)), 0);
      expect(Totp.timeStep(_at(29, 999)), 0);
      expect(Totp.timeStep(_at(30)), 1);
      expect(Totp.timeStep(_at(59, 999)), 1);
      expect(Totp.timeStep(_at(60)), 2);
    });

    test('matches the RFC 6238 counter for T=20000000000 (beyond 32 bits)', () {
      expect(Totp.timeStep(_at(20000000000)), 0x27BC86AA);
    });

    test('honours a custom period', () {
      expect(Totp.timeStep(_at(59), period: 60), 0);
      expect(Totp.timeStep(_at(60), period: 60), 1);
    });

    test('rejects a non-positive period and pre-epoch times', () {
      expect(() => Totp.timeStep(_at(0), period: 0), throwsArgumentError);
      expect(() => Totp.timeStep(_at(-1)), throwsArgumentError);
    });

    test('the same instant gives the same code in any time zone', () {
      final utc = _at(1234567890);
      final secret = seeds[HashAlgorithm.sha1]!;
      expect(
        Totp.generate(secret, at: utc.toLocal(), digits: 8),
        Totp.generate(secret, at: utc, digits: 8),
      );
    });
  });

  group('Totp.remaining', () {
    test('is the full period exactly on a boundary', () {
      expect(Totp.remaining(_at(30)), const Duration(seconds: 30));
    });

    test('counts down within a step', () {
      expect(Totp.remaining(_at(29, 500)), const Duration(milliseconds: 500));
      expect(Totp.remaining(_at(45)), const Duration(seconds: 15));
      expect(Totp.remaining(_at(45), period: 60), const Duration(seconds: 15));
    });
  });
}
