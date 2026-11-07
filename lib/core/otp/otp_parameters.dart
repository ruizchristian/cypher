import 'otp_secret.dart';
import 'otp_types.dart';

/// Everything needed to generate codes for one account, as produced by the
/// `otpauth://` and `otpauth-migration://` parsers.
final class OtpParameters {
  const OtpParameters({
    required this.type,
    required this.secret,
    this.issuer = '',
    this.accountName = '',
    this.algorithm = HashAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
  });

  final OtpType type;
  final OtpSecret secret;
  final String issuer;
  final String accountName;
  final HashAlgorithm algorithm;
  final int digits;

  /// TOTP time step in seconds. Ignored for HOTP.
  final int period;

  /// HOTP moving factor. Ignored for TOTP.
  final int counter;

  @override
  String toString() =>
      'OtpParameters(type: ${type.name}, issuer: $issuer, '
      'accountName: $accountName, algorithm: ${algorithm.name}, '
      'digits: $digits, period: $period, counter: $counter, secret: <redacted>)';
}
