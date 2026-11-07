import 'dart:convert';
import 'dart:typed_data';

import '../core/otp/base32.dart';
import '../core/otp/hotp.dart';
import '../core/otp/otp_secret.dart';
import '../core/otp/otp_types.dart';
import 'account.dart';

/// Raised when decrypted vault content is not a valid vault. The message names
/// the problem, never the content.
final class VaultFormatException implements Exception {
  const VaultFormatException(this.message);

  final String message;

  @override
  String toString() => 'VaultFormatException($message)';
}

/// Serialises accounts to the vault's plaintext JSON.
///
/// Schema 1:
/// `{"schema":1,"accounts":[{"id","type","issuer","account","alg","digits",
/// "period","counter","secret","created"}]}`. Array order is display order.
/// Readers must accept every schema up to [currentSchema]; writers emit only
/// [currentSchema].
abstract final class VaultCodec {
  static const int currentSchema = 1;

  static Uint8List encode(List<Account> accounts) {
    final json = {
      'schema': currentSchema,
      'accounts': [for (final a in accounts) _encodeAccount(a)],
    };
    return utf8.encode(jsonEncode(json));
  }

  /// Throws [VaultFormatException] on anything other than a valid vault.
  static List<Account> decode(List<int> bytes) {
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const VaultFormatException('not JSON');
    }
    if (root is! Map<String, Object?>) {
      throw const VaultFormatException('root is not an object');
    }
    final schema = root['schema'];
    if (schema is! int || schema < 1 || schema > currentSchema) {
      throw const VaultFormatException('unsupported schema');
    }
    final list = root['accounts'];
    if (list is! List<Object?>) {
      throw const VaultFormatException('accounts is not a list');
    }
    final accounts = [for (final entry in list) _decodeAccount(entry)];
    final ids = {for (final a in accounts) a.id};
    if (ids.length != accounts.length) {
      throw const VaultFormatException('duplicate account id');
    }
    return accounts;
  }

  static Map<String, Object> _encodeAccount(Account a) => {
    'id': a.id,
    'type': a.type.name,
    'issuer': a.issuer,
    'account': a.accountName,
    'alg': a.algorithm.name,
    'digits': a.digits,
    'period': a.period,
    'counter': a.counter,
    'secret': Base32.encode(a.secret.bytes, padding: false),
    'created': a.createdAt.toUtc().toIso8601String(),
  };

  static Account _decodeAccount(Object? entry) {
    if (entry is! Map<String, Object?>) {
      throw const VaultFormatException('account is not an object');
    }
    T field<T>(String name) {
      final value = entry[name];
      if (value is! T) throw VaultFormatException('bad field "$name"');
      return value;
    }

    final id = field<String>('id');
    final type = _byName(OtpType.values, field<String>('type'), 'type');
    final algorithm = _byName(
      HashAlgorithm.values,
      field<String>('alg'),
      'alg',
    );
    final digits = field<int>('digits');
    final period = field<int>('period');
    final counter = field<int>('counter');
    final secretBytes = Base32.tryDecode(field<String>('secret'));
    final created = DateTime.tryParse(field<String>('created'));

    if (id.isEmpty) throw const VaultFormatException('empty id');
    if (digits < Hotp.minDigits || digits > Hotp.maxDigits) {
      throw const VaultFormatException('bad field "digits"');
    }
    if (period <= 0) throw const VaultFormatException('bad field "period"');
    if (counter < 0) throw const VaultFormatException('bad field "counter"');
    if (secretBytes == null || secretBytes.isEmpty) {
      throw const VaultFormatException('bad field "secret"');
    }
    if (created == null) {
      throw const VaultFormatException('bad field "created"');
    }

    return Account(
      id: id,
      type: type,
      secret: OtpSecret(secretBytes),
      createdAt: created,
      issuer: field<String>('issuer'),
      accountName: field<String>('account'),
      algorithm: algorithm,
      digits: digits,
      period: period,
      counter: counter,
    );
  }

  static T _byName<T extends Enum>(List<T> values, String name, String field) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw VaultFormatException('bad field "$field"');
  }
}
