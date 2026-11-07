import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

enum VaultDecryptFailure { notAVault, unsupportedVersion, authenticationFailed }

/// Raised when vault bytes cannot be decrypted. Carries only a reason code.
final class VaultDecryptException implements Exception {
  const VaultDecryptException(this.reason);

  final VaultDecryptFailure reason;

  @override
  String toString() => 'VaultDecryptException(${reason.name})';
}

/// AES-256-GCM encryption of the vault file.
///
/// Layout: `magic "CYVT" (4) ‖ version (1) ‖ nonce (12) ‖ ciphertext ‖ tag (16)`.
/// The 17-byte header is authenticated as AAD, so tampering with any byte,
/// including the version, fails decryption.
abstract final class VaultCipher {
  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int formatVersion = 1;
  static const List<int> magic = [0x43, 0x59, 0x56, 0x54]; // "CYVT"
  static const int _versionOffset = 4;
  static const int _nonceOffset = _versionOffset + 1;
  static const int headerLength = _nonceOffset + nonceLength;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _random = Random.secure();

  static Uint8List newKey() => _randomBytes(keyLength);

  static Future<Uint8List> encrypt(List<int> plaintext, Uint8List key) async {
    _checkKey(key);
    final header = Uint8List(headerLength)
      ..setAll(0, magic)
      ..[_versionOffset] = formatVersion
      ..setAll(_nonceOffset, _randomBytes(nonceLength));
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKeyData(key),
      nonce: Uint8List.sublistView(header, _nonceOffset),
      aad: header,
    );
    return Uint8List.fromList([...header, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws [VaultDecryptException] if [data] is not a vault, has an unknown
  /// version, or fails authentication (wrong key or tampered bytes).
  static Future<Uint8List> decrypt(Uint8List data, Uint8List key) async {
    _checkKey(key);
    if (data.length < headerLength + macLength) {
      throw const VaultDecryptException(VaultDecryptFailure.notAVault);
    }
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) {
        throw const VaultDecryptException(VaultDecryptFailure.notAVault);
      }
    }
    if (data[_versionOffset] != formatVersion) {
      throw const VaultDecryptException(VaultDecryptFailure.unsupportedVersion);
    }
    final box = SecretBox(
      Uint8List.sublistView(data, headerLength, data.length - macLength),
      nonce: Uint8List.sublistView(data, _nonceOffset, headerLength),
      mac: Mac(Uint8List.sublistView(data, data.length - macLength)),
    );
    try {
      final clear = await _aes.decrypt(
        box,
        secretKey: SecretKeyData(key),
        aad: Uint8List.sublistView(data, 0, headerLength),
      );
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const VaultDecryptException(
        VaultDecryptFailure.authenticationFailed,
      );
    }
  }

  static void _checkKey(Uint8List key) {
    if (key.length != keyLength) {
      throw ArgumentError('Vault keys are $keyLength bytes');
    }
  }

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
