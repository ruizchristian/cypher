import 'dart:math';

import '../core/otp/otp_parameters.dart';
import '../core/otp/otp_secret.dart';
import '../core/otp/otp_types.dart';

/// One stored OTP account. Immutable; the secret is never printed.
final class Account {
  const Account({
    required this.id,
    required this.type,
    required this.secret,
    required this.createdAt,
    this.issuer = '',
    this.accountName = '',
    this.algorithm = HashAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
  });

  factory Account.fromParameters(
    OtpParameters parameters, {
    required String id,
    required DateTime createdAt,
  }) {
    return Account(
      id: id,
      type: parameters.type,
      secret: parameters.secret,
      createdAt: createdAt,
      issuer: parameters.issuer,
      accountName: parameters.accountName,
      algorithm: parameters.algorithm,
      digits: parameters.digits,
      period: parameters.period,
      counter: parameters.counter,
    );
  }

  final String id;
  final OtpType type;
  final OtpSecret secret;
  final DateTime createdAt;
  final String issuer;
  final String accountName;
  final HashAlgorithm algorithm;
  final int digits;

  /// TOTP time step in seconds. Ignored for HOTP.
  final int period;

  /// HOTP moving factor. Ignored for TOTP.
  final int counter;

  /// The secret and the code parameters are fixed at creation; only the
  /// display names and the HOTP counter change afterwards.
  Account copyWith({String? issuer, String? accountName, int? counter}) {
    return Account(
      id: id,
      type: type,
      secret: secret,
      createdAt: createdAt,
      issuer: issuer ?? this.issuer,
      accountName: accountName ?? this.accountName,
      algorithm: algorithm,
      digits: digits,
      period: period,
      counter: counter ?? this.counter,
    );
  }

  static final Random _random = Random.secure();

  /// A random 128-bit identifier as 32 lowercase hex characters.
  static String newId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Whether [parameters] describe this same account: same secret (compared
  /// in constant time), issuer and account name. Used to skip duplicates on
  /// import.
  bool isSameAs(OtpParameters parameters) =>
      _isSameAccount(secret, issuer, accountName, parameters);

  @override
  String toString() =>
      'Account(id: $id, type: ${type.name}, issuer: $issuer, '
      'accountName: $accountName, secret: <redacted>)';
}

/// Duplicate detection for accounts that are not stored yet, such as two
/// entries in one import. Same rule as [Account.isSameAs].
extension OtpParametersDuplicates on OtpParameters {
  bool isSameAs(OtpParameters other) =>
      _isSameAccount(secret, issuer, accountName, other);
}

bool _isSameAccount(
  OtpSecret secret,
  String issuer,
  String accountName,
  OtpParameters other,
) =>
    secret == other.secret &&
    issuer == other.issuer &&
    accountName == other.accountName;
