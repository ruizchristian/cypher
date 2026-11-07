import 'package:cypher/core/otp/base32.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw = [0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef];

  test('toString never reveals the secret', () {
    final text = OtpSecret(raw).toString();
    expect(text, 'OtpSecret(<redacted>)');
    expect(text, isNot(contains(Base32.encode(raw, padding: false))));
    expect(text, isNot(contains('Hello')));
    expect(text, isNot(contains('72'))); // first byte in decimal
  });

  test('rejects an empty secret', () {
    expect(() => OtpSecret(const []), throwsArgumentError);
  });

  test('bytes is a defensive copy', () {
    final secret = OtpSecret(raw);
    secret.bytes[0] = 0;
    expect(secret.bytes, raw);

    final source = List.of(raw);
    final fromSource = OtpSecret(source);
    source[0] = 0;
    expect(fromSource.bytes, raw);
  });

  test('equality compares content', () {
    expect(OtpSecret(raw), OtpSecret(List.of(raw)));
    expect(OtpSecret(raw).hashCode, OtpSecret(List.of(raw)).hashCode);
    expect(OtpSecret(raw), isNot(OtpSecret([...raw, 0])));
    expect(OtpSecret(raw), isNot(OtpSecret([...raw.take(9), 0xee])));
  });
}
