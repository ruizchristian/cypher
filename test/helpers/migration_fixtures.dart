import 'dart:convert';

/// Test-side protobuf encoder for `otpauth-migration://` payloads,
/// independent of the parser under test.
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

List<int> _bytes(int field, List<int> value) => [
  ..._varint(field << 3 | 2),
  ..._varint(value.length),
  ...value,
];

List<int> _int(int field, int value) => [
  ..._varint(field << 3),
  ..._varint(value),
];

/// One exported account. Secret defaults to the RFC 4226 test secret.
List<int> migrationAccount({
  required String issuer,
  String name = 'user',
  List<int>? secret,
  int algorithm = 1, // SHA1
  int type = 2, // TOTP
  int? counter,
}) => [
  ..._bytes(1, secret ?? utf8.encode('12345678901234567890')),
  ..._bytes(2, utf8.encode(name)),
  ..._bytes(3, utf8.encode(issuer)),
  ..._int(4, algorithm),
  ..._int(5, 1), // six digits
  ..._int(6, type),
  if (counter != null) ..._int(7, counter),
];

/// A full `otpauth-migration://offline?data=…` URI for one batch part.
String migrationUri(
  List<List<int>> accounts, {
  int batchSize = 1,
  int batchIndex = 0,
  int batchId = 1,
}) {
  final payload = [
    for (final a in accounts) ..._bytes(1, a),
    ..._int(2, 1),
    ..._int(3, batchSize),
    ..._int(4, batchIndex),
    ..._int(5, batchId),
  ];
  return 'otpauth-migration://offline?data='
      '${Uri.encodeQueryComponent(base64.encode(payload))}';
}
