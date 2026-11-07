import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

enum PinKdf { argon2id, pbkdf2Sha256 }

/// Cost parameters for hashing a PIN. Stored inside every hash, so they can
/// be raised later without breaking existing PINs (see [PinHasher.needsRehash]).
final class PinHashParams {
  const PinHashParams.argon2id({
    required this.memoryKiB,
    required this.iterations,
    this.parallelism = 1,
  }) : kdf = PinKdf.argon2id;

  const PinHashParams.pbkdf2({required this.iterations})
    : kdf = PinKdf.pbkdf2Sha256,
      memoryKiB = 0,
      parallelism = 1;

  final PinKdf kdf;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  @override
  bool operator ==(Object other) =>
      other is PinHashParams &&
      other.kdf == kdf &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(kdf, memoryKiB, iterations, parallelism);

  @override
  String toString() => switch (kdf) {
    PinKdf.argon2id =>
      'argon2id(m=$memoryKiB KiB, t=$iterations, p=$parallelism)',
    PinKdf.pbkdf2Sha256 => 'pbkdf2-sha256(i=$iterations)',
  };
}

/// What counts as a valid PIN: 6 to 12 digits.
abstract final class PinPolicy {
  static const int minLength = 6;
  static const int maxLength = 12;

  static bool isValid(String pin) =>
      pin.length >= minLength &&
      pin.length <= maxLength &&
      pin.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
}

/// Slow, salted PIN hashing with constant-time verification.
///
/// Encoded form: `v1$<kdf>$<m>$<t>$<p>$<salt b64>$<hash b64>`. The KDF runs on
/// a background isolate so the UI never stalls.
abstract final class PinHasher {
  /// Tuned on device (docs/system-plan.md, M5): about half a second per
  /// check on a mid-range phone.
  static const PinHashParams defaultParams = PinHashParams.argon2id(
    memoryKiB: 19 * 1024,
    iterations: 2,
  );

  static const int _saltLength = 16;
  static const int _hashLength = 32;
  static final Random _random = Random.secure();

  /// [inIsolate] is false only in widget tests, whose fake async zone
  /// cannot receive results from another isolate.
  static Future<String> hash(
    String pin, {
    PinHashParams params = defaultParams,
    bool inIsolate = true,
  }) async {
    if (!PinPolicy.isValid(pin)) {
      throw ArgumentError('PIN does not meet the PIN policy');
    }
    final salt = Uint8List(_saltLength);
    for (var i = 0; i < salt.length; i++) {
      salt[i] = _random.nextInt(256);
    }
    final digest = await _derive(pin, salt, params, inIsolate: inIsolate);
    return [
      'v1',
      params.kdf.name,
      params.memoryKiB,
      params.iterations,
      params.parallelism,
      base64.encode(salt),
      base64.encode(digest),
    ].join(r'$');
  }

  /// Whether [pin] matches [encoded]. A malformed [encoded] never matches.
  static Future<bool> verify(
    String pin,
    String encoded, {
    bool inIsolate = true,
  }) async {
    final parsed = _parse(encoded);
    if (parsed == null || !PinPolicy.isValid(pin)) return false;
    final (params, salt, expected) = parsed;
    final actual = await _derive(pin, salt, params, inIsolate: inIsolate);
    return _constantTimeEquals(actual, expected);
  }

  /// Whether [encoded] was made with weaker or different parameters than
  /// [current] and should be re-hashed after the next successful unlock.
  static bool needsRehash(
    String encoded, {
    PinHashParams current = defaultParams,
  }) {
    final parsed = _parse(encoded);
    return parsed == null || parsed.$1 != current;
  }

  static (PinHashParams, Uint8List, Uint8List)? _parse(String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 7 || parts[0] != 'v1') return null;
    try {
      final memory = int.parse(parts[2]);
      final iterations = int.parse(parts[3]);
      final parallelism = int.parse(parts[4]);
      final params = switch (parts[1]) {
        'argon2id' => PinHashParams.argon2id(
          memoryKiB: memory,
          iterations: iterations,
          parallelism: parallelism,
        ),
        'pbkdf2Sha256' => PinHashParams.pbkdf2(iterations: iterations),
        _ => null,
      };
      if (params == null || iterations < 1 || parallelism < 1) return null;
      // Argon2 needs at least 8 KiB per lane; below that the KDF throws
      // instead of producing a hash, so treat it as a malformed record.
      if (params.kdf == PinKdf.argon2id && memory < 8 * parallelism) {
        return null;
      }
      final salt = base64.decode(parts[5]);
      final hash = base64.decode(parts[6]);
      if (salt.length != _saltLength || hash.length != _hashLength) return null;
      return (params, salt, hash);
    } on FormatException {
      return null;
    }
  }

  static Future<Uint8List> _derive(
    String pin,
    Uint8List salt,
    PinHashParams params, {
    required bool inIsolate,
  }) {
    Future<Uint8List> derive() async {
      final KdfAlgorithm kdf = switch (params.kdf) {
        PinKdf.argon2id => Argon2id(
          parallelism: params.parallelism,
          memory: params.memoryKiB,
          iterations: params.iterations,
          hashLength: _hashLength,
        ),
        PinKdf.pbkdf2Sha256 => Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: params.iterations,
          bits: _hashLength * 8,
        ),
      };
      final key = await kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    }

    return inIsolate ? Isolate.run(derive) : derive();
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
