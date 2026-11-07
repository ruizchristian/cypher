import 'base32.dart';
import 'hotp.dart';
import 'otp_parameters.dart';
import 'otp_secret.dart';
import 'otp_types.dart';

/// Why an `otpauth://` URI was rejected. Deliberately carries no part of the
/// input, which may contain the secret.
enum OtpauthError {
  tooLong,
  malformed,
  notOtpauth,
  unsupportedType,
  missingSecret,
  invalidSecret,
  unsupportedAlgorithm,
  invalidDigits,
  invalidPeriod,
  missingCounter,
  invalidCounter,
}

sealed class OtpauthParseResult {
  const OtpauthParseResult();
}

final class OtpauthParsed extends OtpauthParseResult {
  const OtpauthParsed(this.parameters);

  final OtpParameters parameters;
}

final class OtpauthParseFailure extends OtpauthParseResult {
  const OtpauthParseFailure(this.error);

  final OtpauthError error;

  @override
  String toString() => 'OtpauthParseFailure(${error.name})';
}

/// Parser for the Key URI format:
/// `otpauth://TYPE/[ISSUER:]ACCOUNT?secret=…&issuer=…&algorithm=…&digits=…&period=…&counter=…`
abstract final class OtpauthUri {
  /// Bound on untrusted input; real URIs are far shorter.
  static const int maxLength = 4096;

  static OtpauthParseResult parse(String input) {
    final text = input.trim();
    if (text.length > maxLength) return _fail(OtpauthError.tooLong);

    final Uri uri;
    final Map<String, String> query;
    final String label;
    try {
      uri = Uri.parse(text);
      query = uri.queryParameters;
      label = Uri.decodeComponent(
        uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
      );
    } on FormatException {
      return _fail(OtpauthError.malformed);
    } on ArgumentError {
      return _fail(OtpauthError.malformed);
    }

    if (uri.scheme.toLowerCase() != 'otpauth') {
      return _fail(OtpauthError.notOtpauth);
    }
    final type = switch (uri.host.toLowerCase()) {
      'totp' => OtpType.totp,
      'hotp' => OtpType.hotp,
      _ => null,
    };
    if (type == null) return _fail(OtpauthError.unsupportedType);

    final rawSecret = query['secret'];
    if (rawSecret == null || rawSecret.trim().isEmpty) {
      return _fail(OtpauthError.missingSecret);
    }
    final secretBytes = Base32.tryDecode(rawSecret);
    if (secretBytes == null || secretBytes.isEmpty) {
      return _fail(OtpauthError.invalidSecret);
    }

    final algorithm = switch (query['algorithm']?.toUpperCase()) {
      null || 'SHA1' => HashAlgorithm.sha1,
      'SHA256' => HashAlgorithm.sha256,
      'SHA512' => HashAlgorithm.sha512,
      _ => null,
    };
    if (algorithm == null) return _fail(OtpauthError.unsupportedAlgorithm);

    final digits = _intParam(query['digits'], 6);
    if (digits == null || digits < Hotp.minDigits || digits > Hotp.maxDigits) {
      return _fail(OtpauthError.invalidDigits);
    }

    var period = 30;
    var counter = 0;
    if (type == OtpType.totp) {
      final parsed = _intParam(query['period'], 30);
      if (parsed == null || parsed <= 0) {
        return _fail(OtpauthError.invalidPeriod);
      }
      period = parsed;
    } else {
      final raw = query['counter'];
      if (raw == null) return _fail(OtpauthError.missingCounter);
      final parsed = int.tryParse(raw.trim());
      if (parsed == null || parsed < 0) {
        return _fail(OtpauthError.invalidCounter);
      }
      counter = parsed;
    }

    // The label is "issuer:account" or just "account". The issuer parameter
    // takes precedence over the label prefix when both are present.
    final colon = label.indexOf(':');
    final labelIssuer = colon < 0 ? '' : label.substring(0, colon).trim();
    final accountName = (colon < 0 ? label : label.substring(colon + 1)).trim();
    final issuerParam = query['issuer']?.trim() ?? '';

    return OtpauthParsed(
      OtpParameters(
        type: type,
        secret: OtpSecret(secretBytes),
        issuer: issuerParam.isNotEmpty ? issuerParam : labelIssuer,
        accountName: accountName,
        algorithm: algorithm,
        digits: digits,
        period: period,
        counter: counter,
      ),
    );
  }

  /// `null` means present but not an integer; absent yields [fallback].
  static int? _intParam(String? raw, int fallback) =>
      raw == null ? fallback : int.tryParse(raw.trim());

  static OtpauthParseFailure _fail(OtpauthError error) =>
      OtpauthParseFailure(error);
}
