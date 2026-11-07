import 'dart:convert';

import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/migration_payload.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:flutter_test/flutter_test.dart';

// Test-side protobuf encoder, independent of the parser under test.
List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (true) {
    final byte = v & 0x7f;
    v = v >>> 7;
    if (v == 0) {
      out.add(byte);
      return out;
    }
    out.add(byte | 0x80);
  }
}

List<int> _tag(int field, int wireType) => _varint(field << 3 | wireType);

List<int> _bytesField(int field, List<int> value) => [
  ..._tag(field, 2),
  ..._varint(value.length),
  ...value,
];

List<int> _intField(int field, int value) => [
  ..._tag(field, 0),
  ..._varint(value),
];

List<int> _account({
  List<int>? secret,
  String name = 'alice@example.com',
  String issuer = 'Example',
  int algorithm = 1,
  int digits = 1,
  int type = 2,
  int? counter,
  List<int> extra = const [],
}) => [
  ..._bytesField(1, secret ?? utf8.encode('12345678901234567890')),
  ..._bytesField(2, utf8.encode(name)),
  ..._bytesField(3, utf8.encode(issuer)),
  ..._intField(4, algorithm),
  ..._intField(5, digits),
  ..._intField(6, type),
  if (counter != null) ..._intField(7, counter),
  ...extra,
];

List<int> _payload(
  List<List<int>> accounts, {
  int batchSize = 1,
  int batchIndex = 0,
  int batchId = 0,
}) => [
  for (final a in accounts) ..._bytesField(1, a),
  ..._intField(2, 1),
  ..._intField(3, batchSize),
  ..._intField(4, batchIndex),
  ..._intField(5, batchId),
];

String _uri(List<int> payload) =>
    'otpauth-migration://offline?data=${Uri.encodeQueryComponent(base64.encode(payload))}';

MigrationParsed _ok(String uri) {
  final result = MigrationPayload.parse(uri);
  if (result is! MigrationParsed) fail('expected success, got $result');
  return result;
}

MigrationError _error(String uri) {
  final result = MigrationPayload.parse(uri);
  if (result is! MigrationParseFailure) fail('expected failure');
  return result.error;
}

void main() {
  group('MigrationPayload.parse success', () {
    test('decodes a TOTP account whose secret yields the RFC code', () {
      final parsed = _ok(_uri(_payload([_account()])));
      expect(parsed.accounts, hasLength(1));
      final a = parsed.accounts.single;
      expect(a.type, OtpType.totp);
      expect(a.issuer, 'Example');
      expect(a.accountName, 'alice@example.com');
      expect(a.algorithm, HashAlgorithm.sha1);
      expect(a.digits, 6);
      expect(a.period, 30);
      expect(Hotp.generate(a.secret, counter: 0), '755224');
    });

    test('maps algorithm, digit and type enums', () {
      final parsed = _ok(
        _uri(
          _payload([
            _account(algorithm: 2, digits: 2),
            _account(algorithm: 3),
            _account(type: 1, counter: 42),
            _account(algorithm: 0, digits: 0, type: 0), // unspecified
          ]),
        ),
      );
      final [a, b, c, d] = parsed.accounts;
      expect((a.algorithm, a.digits), (HashAlgorithm.sha256, 8));
      expect(b.algorithm, HashAlgorithm.sha512);
      expect((c.type, c.counter), (OtpType.hotp, 42));
      expect(
        (d.algorithm, d.digits, d.type),
        (HashAlgorithm.sha1, 6, OtpType.totp),
      );
    });

    test('strips an "Issuer:" prefix from the name', () {
      final parsed = _ok(
        _uri(
          _payload([
            _account(name: 'Example:bob', issuer: 'Example'),
            _account(name: 'GitHub: carol', issuer: ''),
            _account(name: 'Work:dave', issuer: 'Google'),
          ]),
        ),
      );
      final [a, b, c] = parsed.accounts;
      expect((a.issuer, a.accountName), ('Example', 'bob'));
      expect((b.issuer, b.accountName), ('GitHub', 'carol'));
      expect((c.issuer, c.accountName), ('Google', 'Work:dave'));
    });

    test('reports batch information', () {
      final parsed = _ok(
        _uri(_payload([_account()], batchSize: 3, batchIndex: 2, batchId: 77)),
      );
      expect((parsed.batchIndex, parsed.batchSize, parsed.batchId), (2, 3, 77));
    });

    test('skips unknown fields of every wire type', () {
      final unknown = [
        ..._intField(15, 9),
        ..._tag(16, 1),
        ...List.filled(8, 0),
        ..._bytesField(17, [1, 2, 3]),
        ..._tag(18, 5),
        ...List.filled(4, 0),
      ];
      final parsed = _ok(_uri(_payload([_account(extra: unknown)])));
      expect(parsed.accounts, hasLength(1));
    });

    test('keeps a literal "+" in unencoded Base64', () {
      // Find a payload whose Base64 contains '+', then pass it unescaped.
      final payload = [
        for (var i = 0; i < 256; i++)
          _payload([
            _account(secret: [i, i, i, 0xfb]),
          ]),
      ].firstWhere((p) => base64.encode(p).contains('+'));
      final raw = 'otpauth-migration://offline?data=${base64.encode(payload)}';
      expect(_ok(raw).accounts, hasLength(1));
    });

    test('accepts URL-safe Base64 without padding', () {
      final payload = _payload([_account()]);
      final urlSafe = base64Url.encode(payload).replaceAll('=', '');
      expect(
        _ok('otpauth-migration://offline?data=$urlSafe').accounts,
        hasLength(1),
      );
    });

    test('an empty payload yields no accounts', () {
      expect(_ok(_uri(_payload([]))).accounts, isEmpty);
    });
  });

  group('MigrationPayload.parse failure', () {
    test('wrong scheme or host, or no data', () {
      expect(
        _error('otpauth://totp/x?secret=AAAA'),
        MigrationError.notMigrationUri,
      );
      expect(
        _error('otpauth-migration://online?data=AA'),
        MigrationError.notMigrationUri,
      );
      expect(_error('otpauth-migration://offline'), MigrationError.missingData);
      expect(
        _error('otpauth-migration://offline?data='),
        MigrationError.missingData,
      );
    });

    test('invalid Base64 or truncated protobuf', () {
      expect(
        _error('otpauth-migration://offline?data=!!!!'),
        MigrationError.malformed,
      );
      final truncated = _payload([_account()])..removeLast();
      final cut = truncated.sublist(0, truncated.length ~/ 2);
      expect(_error(_uri(cut)), MigrationError.malformed);
    });

    test('rejects MD5 and unknown algorithms', () {
      expect(
        _error(_uri(_payload([_account(algorithm: 4)]))),
        MigrationError.unsupportedAlgorithm,
      );
      expect(
        _error(_uri(_payload([_account(algorithm: 9)]))),
        MigrationError.unsupportedAlgorithm,
      );
    });

    test('rejects invalid accounts, and the whole payload with them', () {
      for (final bad in [
        _account(digits: 3),
        _account(type: 7),
        _account(secret: []),
        _account(type: 1, counter: -1),
      ]) {
        expect(
          _error(_uri(_payload([_account(), bad]))),
          MigrationError.invalidAccount,
        );
      }
    });

    test('rejects a batch size above the cap', () {
      expect(
        _error(
          _uri(
            _payload([
              _account(),
            ], batchSize: MigrationPayload.maxBatchSize + 1),
          ),
        ),
        MigrationError.malformed,
      );
      expect(
        _ok(
          _uri(
            _payload([_account()], batchSize: MigrationPayload.maxBatchSize),
          ),
        ).batchSize,
        MigrationPayload.maxBatchSize,
      );
    });

    test('rejects inconsistent batch fields', () {
      expect(
        _error(_uri(_payload([_account()], batchSize: 2, batchIndex: 2))),
        MigrationError.malformed,
      );
    });

    test('rejects more than maxAccounts accounts', () {
      final small = _account(secret: [1], name: '', issuer: '');
      final payload = _payload(
        List.filled(MigrationPayload.maxAccounts + 1, small),
      );
      expect(_error(_uri(payload)), MigrationError.tooManyAccounts);
    });

    test('rejects oversized input before decoding', () {
      final huge =
          'otpauth-migration://offline?data=${'A' * MigrationPayload.maxInputLength}';
      expect(_error(huge), MigrationError.tooLarge);
    });

    test('failure toString carries only the error name', () {
      expect(
        MigrationPayload.parse(_uri(_payload([_account(algorithm: 4)])))
            .toString(),
        'MigrationParseFailure(unsupportedAlgorithm)',
      );
    });
  });
}
