import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

enum BackupKdf {
  argon2id(1),
  pbkdf2Sha256(2);

  const BackupKdf(this.id);

  /// The byte stored in the file header.
  final int id;
}

/// Password-stretching parameters, stored in every backup's header so they
/// can change without breaking old files.
final class BackupKdfParams {
  const BackupKdfParams.argon2id({
    required this.memoryKiB,
    required this.iterations,
    this.parallelism = 1,
  }) : kdf = BackupKdf.argon2id;

  const BackupKdfParams.pbkdf2({required this.iterations})
    : kdf = BackupKdf.pbkdf2Sha256,
      memoryKiB = 0,
      parallelism = 0;

  final BackupKdf kdf;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
}

enum BackupFailure {
  /// Not a CypherAuth backup (wrong magic or too short).
  notABackup,

  /// Made by a newer CypherAuth.
  unsupportedVersion,

  /// Larger than [BackupCipher.maxFileBytes].
  tooLarge,

  /// The header asks for a KDF cost outside safe bounds, which could freeze
  /// or exhaust the phone. Checked before any work is done.
  unsafeParameters,

  /// Wrong password, or the file was damaged or altered. Deliberately one
  /// reason: telling them apart would help an attacker.
  wrongPasswordOrDamaged,
}

final class BackupDecryptException implements Exception {
  const BackupDecryptException(this.reason);

  final BackupFailure reason;

  @override
  String toString() => 'BackupDecryptException(${reason.name})';
}

/// What counts as an acceptable backup password.
abstract final class BackupPassword {
  static const int minLength = 10;

  static bool isAcceptable(String password) =>
      password.runes.length >= minLength;
}

/// The `.cypher` backup file (docs/system-plan.md §7):
///
/// ```
/// 0   6  magic "CYPHER"
/// 6   1  format version (1)
/// 7   1  kdf id (1 = Argon2id, 2 = PBKDF2-SHA256)
/// 8   12 kdf params: Argon2id m KiB, t, p (u32 BE each); PBKDF2 i + 8 zero
/// 20  16 salt
/// 36  12 nonce
/// 48  …  AES-256-GCM ciphertext ‖ 16-byte tag   (AAD = bytes 0–47)
/// ```
///
/// The password is UTF-8 encoded as typed. (Dart has no Unicode
/// normalization, so the same accented password typed with a different
/// composition on another device would not match.)
abstract final class BackupCipher {
  static const List<int> magic = [0x43, 0x59, 0x50, 0x48, 0x45, 0x52];
  static const int formatVersion = 1;
  static const int headerLength = 48;
  static const int macLength = 16;
  static const int maxFileBytes = 1024 * 1024;

  /// Heavy on purpose: a backup may sit in cloud storage, where an attacker
  /// can guess passwords offline at full speed. ~0.6 s on the emulator.
  static const BackupKdfParams defaultParams = BackupKdfParams.argon2id(
    memoryKiB: 64 * 1024,
    iterations: 3,
  );

  // Upper bounds for untrusted files: generous for any real CypherAuth
  // backup, small enough that a crafted header cannot hang the phone.
  static const int maxArgonMemoryKiB = 256 * 1024;
  static const int maxArgonIterations = 10;
  static const int maxArgonParallelism = 4;
  static const int maxPbkdf2Iterations = 10000000;

  static final Random _random = Random.secure();

  static Future<Uint8List> encrypt(
    List<int> plaintext,
    String password, {
    BackupKdfParams params = defaultParams,
    bool inIsolate = true,
  }) async {
    final header = Uint8List(headerLength)
      ..setAll(0, magic)
      ..[6] = formatVersion
      ..[7] = params.kdf.id;
    final view = ByteData.sublistView(header);
    if (params.kdf == BackupKdf.argon2id) {
      view
        ..setUint32(8, params.memoryKiB)
        ..setUint32(12, params.iterations)
        ..setUint32(16, params.parallelism);
    } else {
      view.setUint32(8, params.iterations);
    }
    header
      ..setAll(20, _randomBytes(16))
      ..setAll(36, _randomBytes(12));

    final key = await _deriveKey(
      password,
      Uint8List.sublistView(header, 20, 36),
      params,
      inIsolate: inIsolate,
    );
    try {
      final box = await AesGcm.with256bits().encrypt(
        plaintext,
        secretKey: SecretKeyData(key),
        nonce: Uint8List.sublistView(header, 36, headerLength),
        aad: header,
      );
      return Uint8List.fromList([
        ...header,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// Throws [BackupDecryptException]. Size, magic, version and KDF bounds
  /// are checked before the (deliberately slow) KDF runs.
  static Future<Uint8List> decrypt(
    Uint8List file,
    String password, {
    bool inIsolate = true,
  }) async {
    if (file.length > maxFileBytes) {
      throw const BackupDecryptException(BackupFailure.tooLarge);
    }
    if (file.length < headerLength + macLength) {
      throw const BackupDecryptException(BackupFailure.notABackup);
    }
    for (var i = 0; i < magic.length; i++) {
      if (file[i] != magic[i]) {
        throw const BackupDecryptException(BackupFailure.notABackup);
      }
    }
    if (file[6] != formatVersion) {
      throw const BackupDecryptException(BackupFailure.unsupportedVersion);
    }
    final params = _readParams(file);

    final key = await _deriveKey(
      password,
      Uint8List.sublistView(file, 20, 36),
      params,
      inIsolate: inIsolate,
    );
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          Uint8List.sublistView(file, headerLength, file.length - macLength),
          nonce: Uint8List.sublistView(file, 36, headerLength),
          mac: Mac(Uint8List.sublistView(file, file.length - macLength)),
        ),
        secretKey: SecretKeyData(key),
        aad: Uint8List.sublistView(file, 0, headerLength),
      );
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupDecryptException(BackupFailure.wrongPasswordOrDamaged);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  static BackupKdfParams _readParams(Uint8List file) {
    final view = ByteData.sublistView(file);
    switch (file[7]) {
      case 1: // Argon2id
        final memory = view.getUint32(8);
        final iterations = view.getUint32(12);
        final parallelism = view.getUint32(16);
        final safe =
            parallelism >= 1 &&
            parallelism <= maxArgonParallelism &&
            iterations >= 1 &&
            iterations <= maxArgonIterations &&
            memory >= 8 * parallelism &&
            memory <= maxArgonMemoryKiB;
        if (!safe) {
          throw const BackupDecryptException(BackupFailure.unsafeParameters);
        }
        return BackupKdfParams.argon2id(
          memoryKiB: memory,
          iterations: iterations,
          parallelism: parallelism,
        );
      case 2: // PBKDF2-SHA256
        final iterations = view.getUint32(8);
        if (iterations < 1 || iterations > maxPbkdf2Iterations) {
          throw const BackupDecryptException(BackupFailure.unsafeParameters);
        }
        return BackupKdfParams.pbkdf2(iterations: iterations);
      default:
        // An unknown KDF id is either damage or a newer format; the header
        // is authenticated, so treat it as not decryptable.
        throw const BackupDecryptException(
          BackupFailure.wrongPasswordOrDamaged,
        );
    }
  }

  static Future<Uint8List> _deriveKey(
    String password,
    Uint8List salt,
    BackupKdfParams params, {
    required bool inIsolate,
  }) {
    Future<Uint8List> derive() async {
      final KdfAlgorithm kdf = switch (params.kdf) {
        BackupKdf.argon2id => Argon2id(
          parallelism: params.parallelism,
          memory: params.memoryKiB,
          iterations: params.iterations,
          hashLength: 32,
        ),
        BackupKdf.pbkdf2Sha256 => Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: params.iterations,
          bits: 256,
        ),
      };
      final key = await kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    }

    return inIsolate ? Isolate.run(derive) : derive();
  }

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
