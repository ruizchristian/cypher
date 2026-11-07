import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cypher/app/vault_bootstrap.dart';
import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/platform/flutter_secret_store.dart';
import 'package:cypher/features/add_account/payload_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Proves the native ZXing library loads and decodes on a real device, and
/// that a decoded code flows into the real vault. Uses its own vault.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const directoryName = 'vault_add_account_test';
  const keyName = 'cypher.vault.dek.add-account-test';
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // RFC 4226 test secret

  late Directory temp;

  Future<void> cleanUp() async {
    await StoredKeyWrapper(
      const FlutterSecretStore(),
      storageKey: keyName,
    ).deleteKey();
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}$directoryName',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  setUp(() async {
    await cleanUp();
    temp = await Directory.systemTemp.createTemp('cypher_qr');
  });

  tearDown(() async {
    await cleanUp();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Encodes [text] as a QR code with ZXing and saves it as a PNG, like a
  /// screenshot of a setup page.
  Future<String> qrPng(String text) async {
    final encoded = zx.encodeBarcode(
      contents: text,
      params: EncodeParams(width: 600, height: 600, margin: 40),
    );
    expect(encoded.isValid, isTrue, reason: encoded.error);
    final width = encoded.width!;
    final height = encoded.height!;
    final grey = encoded.data!;
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      rgba
        ..[i * 4] = grey[i]
        ..[i * 4 + 1] = grey[i]
        ..[i * 4 + 2] = grey[i]
        ..[i * 4 + 3] = 255;
    }
    final image = await (() {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      return done.future;
    })();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = '${temp.path}${Platform.pathSeparator}qr.png';
    await File(path).writeAsBytes(png!.buffer.asUint8List());
    return path;
  }

  Future<String?> decode(String path) async {
    final code = await zx.readBarcodeImagePathString(
      path,
      DecodeParams(format: Format.qrCode, tryHarder: true, maxSize: 1600),
    );
    return code.isValid ? code.text : null;
  }

  testWidgets('a QR image decodes on-device and imports into the vault', (
    tester,
  ) async {
    const uri =
        'otpauth://hotp/Example:alice@example.com?secret=$secret'
        '&issuer=Example&counter=0';
    final decoded = await decode(await qrPng(uri));
    expect(decoded, uri);

    final outcome = PayloadImporter().handle(decoded!);
    final accounts = (outcome as ImportReady).accounts;

    final repo = await openAccountRepository(
      directoryName: directoryName,
      keyName: keyName,
    );
    await repo.unlock();
    await repo.addAll(accounts);
    repo.lock();

    final reopened = await openAccountRepository(
      directoryName: directoryName,
      keyName: keyName,
    );
    await reopened.unlock();
    final stored = reopened.accounts.single;
    expect(
      (stored.issuer, stored.accountName, stored.type),
      ('Example', 'alice@example.com', OtpType.hotp),
    );
    expect(Hotp.generate(stored.secret, counter: 0), '755224');
    await reopened.dispose();
    await repo.dispose();
  });

  testWidgets('an image without a QR code decodes to nothing', (tester) async {
    final blank = Uint8List(200 * 200 * 4)..fillRange(0, 200 * 200 * 4, 255);
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      blank,
      200,
      200,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    final png = await (await done.future).toByteData(
      format: ui.ImageByteFormat.png,
    );
    final path = '${temp.path}${Platform.pathSeparator}blank.png';
    await File(path).writeAsBytes(png!.buffer.asUint8List());
    expect(await decode(path), isNull);
  });
}
