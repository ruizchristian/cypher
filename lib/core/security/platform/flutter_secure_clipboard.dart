import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../secure_clipboard.dart';

/// [SecureClipboard] for Android and iOS.
///
/// Android goes through the `cypher/platform` channel (see `MainActivity.kt`),
/// which marks the clip sensitive so Android 13+ hides it from the clipboard
/// preview. On clearing, the native side leaves the clipboard alone only if
/// it can see that something else was copied since. Android blocks reading
/// the clipboard in the background, so it clears in that case too.
///
/// iOS uses Flutter's clipboard and clears unconditionally: reading the
/// clipboard to compare would trigger iOS's paste-permission prompt.
/// TODO(ios): copy with `UIPasteboard` `.localOnly` (no Universal Clipboard)
/// and `.expirationDate` once Swift code can be built and tested.
final class FlutterSecureClipboard implements SecureClipboard {
  FlutterSecureClipboard({
    this.clearAfter = const Duration(seconds: 30),
    this._channel = const MethodChannel('cypher/platform'),
  });

  final Duration clearAfter;
  final MethodChannel _channel;
  Timer? _clearTimer;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> copyCode(String code) async {
    if (_isAndroid) {
      await _channel.invokeMethod<void>('copySensitive', {'text': code});
    } else {
      await Clipboard.setData(ClipboardData(text: code));
    }
    _clearTimer?.cancel();
    _clearTimer = Timer(clearAfter, () => unawaited(_clear(code)));
  }

  Future<void> _clear(String code) async {
    if (_isAndroid) {
      await _channel.invokeMethod<void>('clearIfUnchanged', {'text': code});
    } else {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
