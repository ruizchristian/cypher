import 'package:cypher/features/add_account/zxing_qr_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

void main() {
  // Regression (1.0.0): on a real phone the default centre crop did not line
  // up with the preview, so the decoder only ever saw part of the code, and a
  // 1 s wait after each miss made the scanner feel dead.
  test('the live scanner decodes the whole frame and retries quickly', () {
    final scanner = zxingScanner(
      onCode: (_) {},
      onCameraUnavailable: () {},
    ) as ReaderWidget;
    expect(scanner.cropPercent, 0);
    expect(
      scanner.scanDelay,
      lessThanOrEqualTo(const Duration(milliseconds: 200)),
    );
  });
}
