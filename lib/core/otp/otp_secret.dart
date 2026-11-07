import 'dart:typed_data';

/// The raw shared secret of an OTP account.
///
/// It is never printed: [toString] is redacted, and the bytes are reachable
/// only through [bytes], which returns a copy so callers cannot mutate the
/// stored key.
final class OtpSecret {
  /// Throws [ArgumentError] if [bytes] is empty.
  OtpSecret(List<int> bytes) : _bytes = Uint8List.fromList(bytes) {
    if (_bytes.isEmpty) {
      throw ArgumentError('An OTP secret must not be empty');
    }
  }

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  int get length => _bytes.length;

  /// Constant-time comparison, so equality checks (e.g. duplicate detection on
  /// import) do not leak how many leading bytes match.
  @override
  bool operator ==(Object other) {
    if (other is! OtpSecret || other._bytes.length != _bytes.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < _bytes.length; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'OtpSecret(<redacted>)';
}
