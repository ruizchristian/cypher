import 'dart:convert';
import 'dart:math';

import 'package:cypher/core/otp/base32.dart';
import 'package:flutter_test/flutter_test.dart';

// RFC 4648 §10 test vectors.
const _rfc4648 = {
  '': '',
  'f': 'MY======',
  'fo': 'MZXQ====',
  'foo': 'MZXW6===',
  'foob': 'MZXW6YQ=',
  'fooba': 'MZXW6YTB',
  'foobar': 'MZXW6YTBOI======',
};

void main() {
  group('Base32.encode', () {
    _rfc4648.forEach((plain, encoded) {
      test('RFC 4648 "$plain" -> "$encoded"', () {
        expect(Base32.encode(utf8.encode(plain)), encoded);
      });
    });

    test('omits padding when asked', () {
      expect(
        Base32.encode(utf8.encode('foobar'), padding: false),
        'MZXW6YTBOI',
      );
    });
  });

  group('Base32.tryDecode', () {
    _rfc4648.forEach((plain, encoded) {
      test('RFC 4648 "$encoded" -> "$plain"', () {
        expect(Base32.tryDecode(encoded), utf8.encode(plain));
      });
    });

    test('decodes the RFC 4226 test secret', () {
      expect(
        Base32.tryDecode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
        utf8.encode('12345678901234567890'),
      );
    });

    test('accepts lowercase, missing padding, spaces and hyphens', () {
      final expected = utf8.encode('foobar');
      expect(Base32.tryDecode('mzxw6ytboi'), expected);
      expect(Base32.tryDecode('MZXW 6YTB OI'), expected);
      expect(Base32.tryDecode('mzxw-6ytb-oi=='), expected);
      expect(Base32.tryDecode('  MZXW6YTBOI\n'), expected);
    });

    test('rejects characters outside the alphabet', () {
      for (final bad in ['MZXW0YTB', 'MZXW1YTB', 'MZXW8YTB', 'MZXW9YTB']) {
        expect(Base32.tryDecode(bad), isNull, reason: bad);
      }
      expect(Base32.tryDecode('MZXW6YT!'), isNull);
      expect(Base32.tryDecode('MZXWßYTB'), isNull);
      expect(Base32.tryDecode('MZXＷ6YTB'), isNull); // full-width W
    });

    test('rejects padding in the middle', () {
      expect(Base32.tryDecode('MY==MZXQ'), isNull);
    });

    test('rejects lengths no encoder can produce', () {
      expect(Base32.tryDecode('M'), isNull); // 1 mod 8
      expect(Base32.tryDecode('MZX'), isNull); // 3 mod 8
      expect(Base32.tryDecode('MZXW6Y'), isNull); // 6 mod 8
    });

    test('round-trips arbitrary bytes', () {
      final random = Random(42);
      for (var length = 0; length <= 64; length++) {
        final bytes = List.generate(length, (_) => random.nextInt(256));
        expect(Base32.tryDecode(Base32.encode(bytes)), bytes);
        expect(Base32.tryDecode(Base32.encode(bytes, padding: false)), bytes);
      }
    });
  });
}
