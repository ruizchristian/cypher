import 'package:cypher/core/security/pin_hasher.dart';
import 'package:cypher/core/security/pin_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

const _cheap = PinHashParams.pbkdf2(iterations: 1);

void main() {
  group('PinPolicy', () {
    test('accepts 6 to 12 digits only', () {
      for (final ok in ['123456', '000000', '123456789012']) {
        expect(PinPolicy.isValid(ok), isTrue, reason: ok);
      }
      for (final bad in ['', '12345', '1234567890123', '12345a', '١٢٣٤٥٦']) {
        expect(PinPolicy.isValid(bad), isFalse, reason: bad);
      }
    });
  });

  group('PinHasher', () {
    test('the real Argon2id default verifies on an isolate', () async {
      final encoded = await PinHasher.hash('482913');
      expect(encoded, startsWith(r'v1$argon2id$19456$2$1$'));
      expect(await PinHasher.verify('482913', encoded), isTrue);
      expect(await PinHasher.verify('482914', encoded), isFalse);
    });

    test('hash never contains the PIN, and salts differ per hash', () async {
      final a = await PinHasher.hash(
        '482913',
        params: _cheap,
        inIsolate: false,
      );
      final b = await PinHasher.hash(
        '482913',
        params: _cheap,
        inIsolate: false,
      );
      expect(a, isNot(contains('482913')));
      expect(a, isNot(b));
      expect(await PinHasher.verify('482913', a, inIsolate: false), isTrue);
      expect(await PinHasher.verify('482913', b, inIsolate: false), isTrue);
    });

    test('rejects PINs outside the policy', () async {
      expect(() => PinHasher.hash('123', params: _cheap), throwsArgumentError);
      final encoded = await PinHasher.hash(
        '123456',
        params: _cheap,
        inIsolate: false,
      );
      expect(
        await PinHasher.verify('12345', encoded, inIsolate: false),
        isFalse,
      );
    });

    test('a malformed or tampered hash never verifies', () async {
      final encoded = await PinHasher.hash(
        '123456',
        params: _cheap,
        inIsolate: false,
      );
      final parts = encoded.split(r'$');
      final cases = [
        '',
        'garbage',
        encoded.replaceFirst('v1', 'v2'),
        encoded.replaceFirst('pbkdf2Sha256', 'md5'),
        ([...parts]..[3] = '0').join(r'$'),
        ([...parts]..[5] = 'AAAA').join(r'$'),
        ([...parts]
              ..[6] = '${parts[6].substring(0, 4)}AAAA${parts[6].substring(8)}')
            .join(r'$'),
      ];
      for (final bad in cases) {
        expect(
          await PinHasher.verify('123456', bad, inIsolate: false),
          isFalse,
          reason: bad,
        );
      }
    });

    test('out-of-range Argon2id parameters never verify', () async {
      // Below the Argon2 minimum (8 KiB per lane) the KDF itself throws; a
      // damaged record must still just "not match".
      final encoded = await PinHasher.hash(
        '123456',
        params: const PinHashParams.argon2id(memoryKiB: 64, iterations: 1),
        inIsolate: false,
      );
      final parts = encoded.split(r'$');
      final cases = [
        ([...parts]..[2] = '0').join(r'$'),
        ([...parts]..[2] = '-5').join(r'$'),
        ([...parts]..[4] = '9').join(r'$'),
      ];
      for (final bad in cases) {
        expect(
          await PinHasher.verify('123456', bad, inIsolate: false),
          isFalse,
          reason: bad,
        );
      }
    });

    test('needsRehash detects other parameters', () async {
      final cheap = await PinHasher.hash(
        '123456',
        params: _cheap,
        inIsolate: false,
      );
      expect(PinHasher.needsRehash(cheap), isTrue);
      expect(PinHasher.needsRehash(cheap, current: _cheap), isFalse);
      expect(PinHasher.needsRehash('garbage'), isTrue);
    });
  });

  group('PinThrottle', () {
    test('five free attempts, then escalating waits capped at an hour', () {
      for (var f = 0; f < 5; f++) {
        expect(PinThrottle.waitAfter(f), isNull, reason: '$f');
      }
      expect(PinThrottle.waitAfter(5), const Duration(seconds: 30));
      expect(PinThrottle.waitAfter(6), const Duration(minutes: 1));
      expect(PinThrottle.waitAfter(7), const Duration(minutes: 5));
      expect(PinThrottle.waitAfter(8), const Duration(minutes: 15));
      expect(PinThrottle.waitAfter(9), const Duration(hours: 1));
      expect(PinThrottle.waitAfter(50), const Duration(hours: 1));
    });
  });
}
