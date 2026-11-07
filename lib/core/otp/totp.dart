import 'hotp.dart';
import 'otp_secret.dart';
import 'otp_types.dart';

/// Time-based one-time passwords (RFC 6238) with T0 = 0.
///
/// The time is always passed in. This layer never reads the wall clock, so
/// every result is reproducible in tests.
abstract final class Totp {
  static const int defaultPeriod = 30;

  /// The RFC 6238 time-step counter `floor(unixSeconds / period)`.
  static int timeStep(DateTime at, {int period = defaultPeriod}) {
    _check(at, period);
    return at.millisecondsSinceEpoch ~/ (period * 1000);
  }

  static String generate(
    OtpSecret secret, {
    required DateTime at,
    int period = defaultPeriod,
    HashAlgorithm algorithm = HashAlgorithm.sha1,
    int digits = 6,
  }) {
    return Hotp.generate(
      secret,
      counter: timeStep(at, period: period),
      algorithm: algorithm,
      digits: digits,
    );
  }

  /// Time left until the next code. At an exact step boundary this is the
  /// full period.
  static Duration remaining(DateTime at, {int period = defaultPeriod}) {
    _check(at, period);
    final periodMs = period * 1000;
    return Duration(
      milliseconds: periodMs - at.millisecondsSinceEpoch % periodMs,
    );
  }

  static void _check(DateTime at, int period) {
    if (period <= 0) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    if (at.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(at, 'at', 'must not be before the Unix epoch');
    }
  }
}
