import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'otp_secret.dart';
import 'otp_types.dart';

/// HMAC-based one-time passwords (RFC 4226).
abstract final class Hotp {
  static const int minDigits = 6;
  static const int maxDigits = 8;

  static const List<int> _powersOfTen = [
    1,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
    10000000,
    100000000,
  ];

  /// Throws [ArgumentError] for a negative [counter] or [digits] outside
  /// [minDigits]–[maxDigits]. Callers validate user input before this point,
  /// so these are programming errors.
  static String generate(
    OtpSecret secret, {
    required int counter,
    HashAlgorithm algorithm = HashAlgorithm.sha1,
    int digits = 6,
  }) {
    if (counter < 0) {
      throw ArgumentError.value(counter, 'counter', 'must not be negative');
    }
    RangeError.checkValueInInterval(digits, minDigits, maxDigits, 'digits');

    // RFC 4226 §5.2: the counter is an 8-byte big-endian value.
    final message = Uint8List(8);
    ByteData.sublistView(message).setUint64(0, counter);

    final hash = crypto.Hmac(
      _hashFor(algorithm),
      secret.bytes,
    ).convert(message).bytes;

    // RFC 4226 §5.3: dynamic truncation.
    final offset = hash[hash.length - 1] & 0x0f;
    final binary =
        ((hash[offset] & 0x7f) << 24) |
        (hash[offset + 1] << 16) |
        (hash[offset + 2] << 8) |
        hash[offset + 3];

    return (binary % _powersOfTen[digits]).toString().padLeft(digits, '0');
  }

  static crypto.Hash _hashFor(HashAlgorithm algorithm) => switch (algorithm) {
    HashAlgorithm.sha1 => crypto.sha1,
    HashAlgorithm.sha256 => crypto.sha256,
    HashAlgorithm.sha512 => crypto.sha512,
  };
}
