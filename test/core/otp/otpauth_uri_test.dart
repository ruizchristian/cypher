import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/otp/otpauth_uri.dart';
import 'package:flutter_test/flutter_test.dart';

// Base32 of the RFC 4226 test secret "12345678901234567890".
const _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

OtpParameters _ok(String uri) {
  final result = OtpauthUri.parse(uri);
  if (result is! OtpauthParsed) fail('expected success, got $result');
  return result.parameters;
}

OtpauthError _error(String uri) {
  final result = OtpauthUri.parse(uri);
  if (result is! OtpauthParseFailure) fail('expected failure for $uri');
  return result.error;
}

void main() {
  group('OtpauthUri.parse success', () {
    test('reads every parameter', () {
      final p = _ok(
        'otpauth://totp/ACME%20Co:john@example.com?secret=$_secret'
        '&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60',
      );
      expect(p.type, OtpType.totp);
      expect(p.issuer, 'ACME Co');
      expect(p.accountName, 'john@example.com');
      expect(p.algorithm, HashAlgorithm.sha256);
      expect(p.digits, 8);
      expect(p.period, 60);
    });

    test('applies defaults: SHA1, 6 digits, 30 s', () {
      final p = _ok('otpauth://totp/alice?secret=$_secret');
      expect(p.algorithm, HashAlgorithm.sha1);
      expect(p.digits, 6);
      expect(p.period, 30);
      expect(p.issuer, '');
      expect(p.accountName, 'alice');
    });

    test('the decoded secret produces the RFC 4226 code', () {
      final p = _ok('otpauth://hotp/x?secret=$_secret&counter=0');
      expect(Hotp.generate(p.secret, counter: p.counter), '755224');
    });

    test('takes the issuer from the label when no parameter is given', () {
      final p = _ok('otpauth://totp/GitHub:octocat?secret=$_secret');
      expect(p.issuer, 'GitHub');
      expect(p.accountName, 'octocat');
    });

    test('prefers the issuer parameter over the label prefix', () {
      final p = _ok('otpauth://totp/Old:me?secret=$_secret&issuer=New');
      expect(p.issuer, 'New');
      expect(p.accountName, 'me');
    });

    test('handles an encoded colon and a space after the colon', () {
      final p = _ok(
        'otpauth://totp/Example%3A%20alice%40google.com?secret=$_secret',
      );
      expect(p.issuer, 'Example');
      expect(p.accountName, 'alice@google.com');
    });

    test('is case-insensitive for scheme, type, algorithm and secret', () {
      final p = _ok(
        'OTPAUTH://TOTP/x?secret=${_secret.toLowerCase()}&algorithm=sha512',
      );
      expect(p.type, OtpType.totp);
      expect(p.algorithm, HashAlgorithm.sha512);
    });

    test('accepts a padded or grouped secret', () {
      _ok('otpauth://totp/x?secret=MZXW6YTBOI%3D%3D%3D%3D%3D%3D');
      _ok('otpauth://totp/x?secret=MZXW%206YTB%20OI');
    });

    test('ignores unknown parameters and the HOTP-only counter on TOTP', () {
      final p = _ok(
        'otpauth://totp/x?secret=$_secret&image=https://x/y.png&counter=5',
      );
      expect(p.counter, 0);
    });

    test('reads the HOTP counter, including values beyond 32 bits', () {
      final p = _ok('otpauth://hotp/x?secret=$_secret&counter=8589934591');
      expect(p.type, OtpType.hotp);
      expect(p.counter, 8589934591);
    });

    test('accepts an empty label', () {
      final p = _ok('otpauth://totp/?secret=$_secret&issuer=Solo');
      expect(p.accountName, '');
      expect(p.issuer, 'Solo');
    });
  });

  group('OtpauthUri.parse failure', () {
    test('wrong scheme or type', () {
      expect(
        _error('https://example.com/?secret=$_secret'),
        OtpauthError.notOtpauth,
      );
      expect(
        _error('otpauth://steam/x?secret=$_secret'),
        OtpauthError.unsupportedType,
      );
      expect(_error('not a uri at all'), OtpauthError.notOtpauth);
    });

    test('missing or invalid secret', () {
      expect(_error('otpauth://totp/x'), OtpauthError.missingSecret);
      expect(_error('otpauth://totp/x?secret='), OtpauthError.missingSecret);
      expect(
        _error('otpauth://totp/x?secret=ABC1'),
        OtpauthError.invalidSecret,
      );
      expect(
        _error('otpauth://totp/x?secret=%3D%3D'),
        OtpauthError.invalidSecret,
      );
    });

    test('unsupported algorithm', () {
      expect(
        _error('otpauth://totp/x?secret=$_secret&algorithm=MD5'),
        OtpauthError.unsupportedAlgorithm,
      );
    });

    test('digits outside 6-8 or not a number', () {
      for (final digits in ['5', '9', '0', 'six', '']) {
        expect(
          _error('otpauth://totp/x?secret=$_secret&digits=$digits'),
          OtpauthError.invalidDigits,
          reason: digits,
        );
      }
    });

    test('period not positive or not a number', () {
      for (final period in ['0', '-30', 'abc']) {
        expect(
          _error('otpauth://totp/x?secret=$_secret&period=$period'),
          OtpauthError.invalidPeriod,
          reason: period,
        );
      }
    });

    test('HOTP without a valid counter', () {
      expect(
        _error('otpauth://hotp/x?secret=$_secret'),
        OtpauthError.missingCounter,
      );
      expect(
        _error('otpauth://hotp/x?secret=$_secret&counter=-1'),
        OtpauthError.invalidCounter,
      );
      expect(
        _error('otpauth://hotp/x?secret=$_secret&counter=1.5'),
        OtpauthError.invalidCounter,
      );
    });

    test('oversized input', () {
      final huge =
          'otpauth://totp/${'a' * OtpauthUri.maxLength}?secret=$_secret';
      expect(_error(huge), OtpauthError.tooLong);
    });
  });

  group('no secret leakage', () {
    test('failure toString carries only the error name', () {
      final result = OtpauthUri.parse(
        'otpauth://totp/x?secret=$_secret&digits=9',
      );
      expect(result.toString(), 'OtpauthParseFailure(invalidDigits)');
    });

    test('parameters toString redacts the secret', () {
      final text = _ok('otpauth://totp/x?secret=$_secret').toString();
      expect(text, contains('<redacted>'));
      expect(text, isNot(contains(_secret)));
      expect(text, isNot(contains('1234567890')));
    });
  });
}
