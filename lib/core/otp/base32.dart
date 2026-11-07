import 'dart:typed_data';

/// RFC 4648 Base32 (the `A–Z2–7` alphabet), as used for OTP secrets.
abstract final class Base32 {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static final RegExp _ignored = RegExp(r'[\s-]');

  static String encode(List<int> bytes, {bool padding = true}) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | (byte & 0xff);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 0x1f]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
    }
    if (padding) {
      while (out.length % 8 != 0) {
        out.write('=');
      }
    }
    return out.toString();
  }

  /// Decodes user- or URI-supplied Base32. Returns `null` if the input is not
  /// valid Base32.
  ///
  /// Lenient where real-world secrets vary: any letter case, spaces and
  /// hyphens between groups, and missing or partial `=` padding. Strict about
  /// the alphabet and about lengths no encoder can produce (1, 3 or 6
  /// characters beyond a multiple of 8).
  static Uint8List? tryDecode(String input) {
    final cleaned = input.replaceAll(_ignored, '');
    const padding = 0x3D; // '='
    var end = cleaned.length;
    while (end > 0 && cleaned.codeUnitAt(end - 1) == padding) {
      end--;
    }
    if (const {1, 3, 6}.contains(end % 8)) return null;

    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < end; i++) {
      final value = _valueOf(cleaned.codeUnitAt(i));
      if (value < 0) return null;
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    return Uint8List.fromList(out);
  }

  /// Maps one code unit to its 5-bit value, or -1. Case-insensitive by
  /// explicit ASCII ranges rather than `toUpperCase`, so no non-ASCII
  /// character can fold into the alphabet.
  static int _valueOf(int c) {
    if (c >= 0x41 && c <= 0x5A) return c - 0x41; // A-Z
    if (c >= 0x61 && c <= 0x7A) return c - 0x61; // a-z
    if (c >= 0x32 && c <= 0x37) return c - 0x32 + 26; // 2-7
    return -1;
  }
}
