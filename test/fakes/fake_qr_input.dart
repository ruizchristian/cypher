import 'package:cypher/features/shared/qr_input.dart';
import 'package:flutter/widgets.dart';

/// Stands in for the camera scanner: tests call [show] to "scan" a code.
final class FakeQrScanner {
  ValueChanged<String>? _onCode;
  VoidCallback? _onCameraUnavailable;

  Widget build({
    required ValueChanged<String> onCode,
    required VoidCallback onCameraUnavailable,
  }) {
    _onCode = onCode;
    _onCameraUnavailable = onCameraUnavailable;
    return const SizedBox.expand(key: Key('fake-scanner'));
  }

  void show(String text) => _onCode!(text);

  void failCamera() => _onCameraUnavailable!();
}

/// Returns queued results: a string is a decoded code, `null` means no code
/// found, and [cancel] simulates the user backing out of the picker.
final class FakeQrImageReader implements QrImageReader {
  final List<Object?> _results = [];
  bool _cancelled = false;

  static const Object cancel = Object();

  void queue(Object? result) => _results.add(result);

  @override
  bool get lastPickCancelled => _cancelled;

  @override
  Future<String?> pickAndRead() async {
    final next = _results.removeAt(0);
    _cancelled = identical(next, cancel);
    return _cancelled ? null : next as String?;
  }
}
