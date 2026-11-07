import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker/image_picker.dart';

import '../shared/qr_input.dart';

// The only file that touches flutter_zxing / image_picker. Swapping the
// scanner library means replacing this file (docs/system-plan.md, M4).

/// [QrScannerBuilder] backed by ZXing (zxing-cpp over FFI) and the Flutter
/// team's camera plugin. No Google ML Kit, no network.
Widget zxingScanner({
  required ValueChanged<String> onCode,
  required VoidCallback onCameraUnavailable,
}) {
  return ReaderWidget(
    codeFormat: Format.qrCode,
    tryInverted: true,
    showGallery: false,
    showToggleCamera: false,
    isMultiScan: false,
    // Decode the whole frame (0 = no crop; this also hides the scan box).
    // The default centre crop did not line up with the preview on real
    // phones: the decoder saw the code cut off at the edge of its square
    // while it looked centred on screen.
    cropPercent: 0,
    // The default waits 1 s after every frame without a code, so a
    // half-aimed first frame left the user waiting; retry quickly instead.
    scanDelay: const Duration(milliseconds: 150),
    scanDelaySuccess: const Duration(milliseconds: 300),
    onScan: (code) {
      final text = code.text;
      if (code.isValid && text != null && text.isNotEmpty) onCode(text);
    },
    onControllerCreated: (controller, error) {
      if (error != null || controller == null) onCameraUnavailable();
    },
  );
}

final class ZxingQrImageReader implements QrImageReader {
  ZxingQrImageReader([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  bool _cancelled = false;

  @override
  bool get lastPickCancelled => _cancelled;

  @override
  Future<String?> pickAndRead() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    _cancelled = file == null;
    if (file == null) return null;
    final code = await zx.readBarcodeImagePath(
      file,
      DecodeParams(
        format: Format.qrCode,
        tryHarder: true,
        tryInverted: true,
        maxSize: 1600,
      ),
    );
    final text = code.text;
    return code.isValid && text != null && text.isNotEmpty ? text : null;
  }
}
