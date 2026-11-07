import 'package:cypher/core/security/secure_clipboard.dart';
import 'package:flutter/services.dart';

/// Records copied codes instead of touching the system clipboard.
final class FakeSecureClipboard implements SecureClipboard {
  final List<String> copied = [];
  bool disposed = false;

  /// When true, the next copy fails the way a platform channel error would.
  bool failNextCopy = false;

  @override
  Future<void> copyCode(String code) async {
    if (failNextCopy) {
      failNextCopy = false;
      throw PlatformException(code: 'clipboard_unavailable');
    }
    copied.add(code);
  }

  @override
  void dispose() => disposed = true;
}
