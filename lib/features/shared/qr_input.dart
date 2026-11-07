import 'package:flutter/widgets.dart';

/// Builds the live camera scanner. [onCode] receives the text of every QR
/// code seen, possibly many times for the same code. [onCameraUnavailable]
/// is called if the camera cannot start (no permission, no camera).
///
/// An interface so the scanner library stays swappable and widget tests can
/// run without a camera.
typedef QrScannerBuilder = Widget Function({
  required ValueChanged<String> onCode,
  required VoidCallback onCameraUnavailable,
});

/// Lets the user pick an image and reads the first QR code in it.
abstract interface class QrImageReader {
  /// The QR code's text; `null` if the user cancelled or no code was found
  /// ([lastPickCancelled] tells the two apart).
  Future<String?> pickAndRead();

  /// Whether the last [pickAndRead] ended because the user cancelled.
  bool get lastPickCancelled;
}
