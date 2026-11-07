import 'dart:convert';
import 'dart:typed_data';

import 'otp_parameters.dart';
import 'otp_secret.dart';
import 'otp_types.dart';

/// Why an `otpauth-migration://` URI was rejected. Carries no input data.
enum MigrationError {
  tooLarge,
  malformed,
  notMigrationUri,
  missingData,
  tooManyAccounts,
  unsupportedAlgorithm,
  invalidAccount,
}

sealed class MigrationParseResult {
  const MigrationParseResult();
}

final class MigrationParsed extends MigrationParseResult {
  const MigrationParsed({
    required this.accounts,
    required this.batchIndex,
    required this.batchSize,
    required this.batchId,
  });

  final List<OtpParameters> accounts;

  /// Large exports span several QR codes. All parts share [batchId], and
  /// [batchIndex] runs from 0 to [batchSize] - 1.
  final int batchIndex;
  final int batchSize;
  final int batchId;
}

final class MigrationParseFailure extends MigrationParseResult {
  const MigrationParseFailure(this.error);

  final MigrationError error;

  @override
  String toString() => 'MigrationParseFailure(${error.name})';
}

/// Parser for Google Authenticator's export format:
/// `otpauth-migration://offline?data=<base64 protobuf MigrationPayload>`.
///
/// The protobuf is decoded by hand (see `_ProtoReader`), which avoids taking
/// a dependency for two small messages. Any invalid account rejects the whole
/// payload; nothing is imported partially.
abstract final class MigrationPayload {
  static const int maxInputLength = 64 * 1024;
  static const int maxAccounts = 1000;

  /// Bound on the number of QR codes in one export. The batch size comes
  /// from untrusted input; real exports need a handful of codes.
  static const int maxBatchSize = 100;

  static MigrationParseResult parse(String input) {
    final text = input.trim();
    if (text.length > maxInputLength) return _fail(MigrationError.tooLarge);

    try {
      final uri = Uri.parse(text);
      if (uri.scheme.toLowerCase() != 'otpauth-migration' ||
          uri.host.toLowerCase() != 'offline') {
        return _fail(MigrationError.notMigrationUri);
      }
      final data = _rawDataParam(uri.query);
      if (data == null || data.isEmpty) {
        return _fail(MigrationError.missingData);
      }

      final bytes = base64.decode(base64.normalize(data));
      return _decodePayload(bytes);
    } on _Rejected catch (rejection) {
      return _fail(rejection.error);
    } on FormatException {
      return _fail(MigrationError.malformed);
    } on ArgumentError {
      return _fail(MigrationError.malformed);
    }
  }

  /// Reads `data` from the raw query. `Uri.queryParameters` decodes `+` as a
  /// space, which corrupts Base64 that was not percent-encoded, so `+` is
  /// kept literal here.
  static String? _rawDataParam(String query) {
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      if (Uri.decodeComponent(pair.substring(0, eq)) == 'data') {
        return Uri.decodeComponent(pair.substring(eq + 1))
            .replaceAll(RegExp(r'\s'), '');
      }
    }
    return null;
  }

  static MigrationParsed _decodePayload(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    final accounts = <OtpParameters>[];
    var batchSize = 1;
    var batchIndex = 0;
    var batchId = 0;

    while (!reader.atEnd) {
      final (field, wireType) = reader.readTag();
      switch ((field, wireType)) {
        case (1, _ProtoReader.lengthDelimited):
          if (accounts.length >= maxAccounts) {
            throw const _Rejected(MigrationError.tooManyAccounts);
          }
          accounts.add(_decodeAccount(reader.readBytes()));
        case (3, _ProtoReader.varint):
          batchSize = reader.readVarint();
        case (4, _ProtoReader.varint):
          batchIndex = reader.readVarint();
        case (5, _ProtoReader.varint):
          batchId = reader.readVarint();
        default: // version (2) and unknown fields
          reader.skip(wireType);
      }
    }

    if (batchSize < 1 ||
        batchSize > maxBatchSize ||
        batchIndex < 0 ||
        batchIndex >= batchSize) {
      throw const FormatException('invalid batch fields');
    }
    return MigrationParsed(
      accounts: List.unmodifiable(accounts),
      batchIndex: batchIndex,
      batchSize: batchSize,
      batchId: batchId,
    );
  }

  static OtpParameters _decodeAccount(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    Uint8List? secret;
    var name = '';
    var issuer = '';
    var algorithmCode = 0;
    var digitsCode = 0;
    var typeCode = 0;
    var counter = 0;

    while (!reader.atEnd) {
      final (field, wireType) = reader.readTag();
      switch ((field, wireType)) {
        case (1, _ProtoReader.lengthDelimited):
          secret = reader.readBytes();
        case (2, _ProtoReader.lengthDelimited):
          name = utf8.decode(reader.readBytes());
        case (3, _ProtoReader.lengthDelimited):
          issuer = utf8.decode(reader.readBytes());
        case (4, _ProtoReader.varint):
          algorithmCode = reader.readVarint();
        case (5, _ProtoReader.varint):
          digitsCode = reader.readVarint();
        case (6, _ProtoReader.varint):
          typeCode = reader.readVarint();
        case (7, _ProtoReader.varint):
          counter = reader.readVarint();
        default:
          reader.skip(wireType);
      }
    }

    // Enum value 0 means "unspecified" and maps to the Key URI defaults.
    final algorithm = switch (algorithmCode) {
      0 || 1 => HashAlgorithm.sha1,
      2 => HashAlgorithm.sha256,
      3 => HashAlgorithm.sha512,
      _ => null, // 4 = MD5, and unknown values
    };
    if (algorithm == null) {
      throw const _Rejected(MigrationError.unsupportedAlgorithm);
    }

    final digits = switch (digitsCode) {
      0 || 1 => 6,
      2 => 8,
      _ => null,
    };
    final type = switch (typeCode) {
      0 || 2 => OtpType.totp,
      1 => OtpType.hotp,
      _ => null,
    };
    if (digits == null ||
        type == null ||
        counter < 0 ||
        secret == null ||
        secret.isEmpty) {
      throw const _Rejected(MigrationError.invalidAccount);
    }

    // Exports often store the name as "Issuer:account"; drop the prefix.
    var accountName = name.trim();
    final colon = accountName.indexOf(':');
    if (colon >= 0) {
      final prefix = accountName.substring(0, colon).trim();
      if (issuer.isEmpty || prefix == issuer.trim()) {
        if (issuer.isEmpty) issuer = prefix;
        accountName = accountName.substring(colon + 1).trim();
      }
    }

    return OtpParameters(
      type: type,
      secret: OtpSecret(secret),
      issuer: issuer.trim(),
      accountName: accountName,
      algorithm: algorithm,
      digits: digits,
      counter: type == OtpType.hotp ? counter : 0,
    );
  }

  static MigrationParseFailure _fail(MigrationError error) =>
      MigrationParseFailure(error);
}

/// Internal signal for a structurally valid payload that Cypher rejects.
/// Never escapes [MigrationPayload.parse].
final class _Rejected implements Exception {
  const _Rejected(this.error);

  final MigrationError error;
}

/// Minimal protobuf wire-format reader. Throws [FormatException] on
/// truncated or malformed input.
final class _ProtoReader {
  _ProtoReader(this._bytes);

  static const int varint = 0;
  static const int fixed64 = 1;
  static const int lengthDelimited = 2;
  static const int fixed32 = 5;

  final Uint8List _bytes;
  int _pos = 0;

  bool get atEnd => _pos >= _bytes.length;

  (int field, int wireType) readTag() {
    final tag = readVarint();
    final field = tag >> 3;
    if (field == 0) throw const FormatException('protobuf field 0');
    return (field, tag & 0x7);
  }

  int readVarint() {
    var result = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      final byte = _next();
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
    }
    throw const FormatException('protobuf varint too long');
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (length < 0 || length > _bytes.length - _pos) {
      throw const FormatException('protobuf length out of range');
    }
    final value = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return value;
  }

  void skip(int wireType) {
    switch (wireType) {
      case varint:
        readVarint();
      case fixed64:
        _advance(8);
      case lengthDelimited:
        readBytes();
      case fixed32:
        _advance(4);
      default:
        throw const FormatException('unsupported protobuf wire type');
    }
  }

  int _next() {
    if (atEnd) throw const FormatException('protobuf truncated');
    return _bytes[_pos++];
  }

  void _advance(int count) {
    if (count > _bytes.length - _pos) {
      throw const FormatException('protobuf truncated');
    }
    _pos += count;
  }
}
