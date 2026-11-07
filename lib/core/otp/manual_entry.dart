import 'base32.dart';
import 'hotp.dart';
import 'otp_parameters.dart';
import 'otp_secret.dart';
import 'otp_types.dart';

enum ManualEntryField { name, secret, period, counter }

enum ManualEntryError {
  /// Neither an issuer nor an account name was given.
  nameMissing,
  secretMissing,

  /// Not Base32 (letters A–Z and digits 2–7; spaces and dashes are allowed).
  secretInvalid,
  periodInvalid,
  counterInvalid,
}

sealed class ManualEntryResult {
  const ManualEntryResult();
}

final class ManualEntryValid extends ManualEntryResult {
  const ManualEntryValid(this.parameters);

  final OtpParameters parameters;
}

final class ManualEntryInvalid extends ManualEntryResult {
  const ManualEntryInvalid(this.errors);

  /// One error per field that failed. Never contains the input itself.
  final Map<ManualEntryField, ManualEntryError> errors;
}

/// Validates a manually typed account, as on a service's "can't scan the
/// code?" page.
abstract final class ManualEntry {
  static ManualEntryResult validate({
    required String issuer,
    required String accountName,
    required String secret,
    required OtpType type,
    HashAlgorithm algorithm = HashAlgorithm.sha1,
    int digits = 6,
    String period = '30',
    String counter = '0',
  }) {
    RangeError.checkValueInInterval(
      digits,
      Hotp.minDigits,
      Hotp.maxDigits,
      'digits',
    );
    final errors = <ManualEntryField, ManualEntryError>{};
    final trimmedIssuer = issuer.trim();
    final trimmedName = accountName.trim();

    if (trimmedIssuer.isEmpty && trimmedName.isEmpty) {
      errors[ManualEntryField.name] = ManualEntryError.nameMissing;
    }

    final secretMissing = secret.trim().isEmpty;
    final secretBytes = secretMissing ? null : Base32.tryDecode(secret);
    if (secretMissing) {
      errors[ManualEntryField.secret] = ManualEntryError.secretMissing;
    } else if (secretBytes == null || secretBytes.isEmpty) {
      // e.g. only dashes or padding: valid characters, but no key.
      errors[ManualEntryField.secret] = ManualEntryError.secretInvalid;
    }

    var parsedPeriod = 30;
    var parsedCounter = 0;
    if (type == OtpType.totp) {
      final value = int.tryParse(period.trim());
      if (value == null || value <= 0) {
        errors[ManualEntryField.period] = ManualEntryError.periodInvalid;
      } else {
        parsedPeriod = value;
      }
    } else {
      final value = int.tryParse(counter.trim());
      if (value == null || value < 0) {
        errors[ManualEntryField.counter] = ManualEntryError.counterInvalid;
      } else {
        parsedCounter = value;
      }
    }

    // A null secretBytes always comes with a secret error; checking it here
    // too lets the type system see that.
    if (errors.isNotEmpty || secretBytes == null) {
      return ManualEntryInvalid(Map.unmodifiable(errors));
    }
    return ManualEntryValid(
      OtpParameters(
        type: type,
        secret: OtpSecret(secretBytes),
        issuer: trimmedIssuer,
        accountName: trimmedName,
        algorithm: algorithm,
        digits: digits,
        period: parsedPeriod,
        counter: parsedCounter,
      ),
    );
  }
}
