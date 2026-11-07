import 'dart:convert';

import 'package:cypher/app/app.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:cypher/features/shared/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_qr_input.dart';
import '../fakes/fake_secure_clipboard.dart';
import '../fakes/in_memory_secret_store.dart';
import '../fakes/in_memory_vault_file_store.dart';

/// The RFC 4226 / RFC 6238 SHA1 test secret.
final rfcSecret = OtpSecret(utf8.encode('12345678901234567890'));

OtpParameters totpAccount(String issuer, [String account = 'user']) =>
    OtpParameters(
      type: OtpType.totp,
      secret: rfcSecret,
      issuer: issuer,
      accountName: account,
    );

OtpParameters hotpAccount(String issuer, [String account = 'user']) =>
    OtpParameters(
      type: OtpType.hotp,
      secret: rfcSecret,
      issuer: issuer,
      accountName: account,
    );

/// The real app on in-memory storage, a fake clock and a fake clipboard.
final class AppHarness {
  AppHarness({int unixSeconds = 59})
    : clock = FakeClock.atUnixSeconds(unixSeconds);

  final FakeClock clock;
  final FakeSecureClipboard clipboard = FakeSecureClipboard();
  final FakeQrScanner scanner = FakeQrScanner();
  final FakeQrImageReader imageReader = FakeQrImageReader();
  final InMemorySecretStore secrets = InMemorySecretStore();
  final InMemoryVaultFileStore files = InMemoryVaultFileStore();

  AccountRepository newRepository() =>
      AccountRepository(keys: StoredKeyWrapper(secrets), files: files);

  /// Writes [accounts] to the vault before the app starts.
  Future<void> seed(List<OtpParameters> accounts) async {
    final repository = newRepository();
    await repository.unlock();
    for (final a in accounts) {
      await repository.add(a);
    }
    await repository.dispose();
  }

  late AccountRepository repository;

  Future<void> pump(WidgetTester tester) async {
    repository = newRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(clock),
          accountRepositoryProvider.overrideWithValue(repository),
          secureClipboardProvider.overrideWithValue(clipboard),
          qrScannerBuilderProvider.overrideWithValue(scanner.build),
          qrImageReaderProvider.overrideWithValue(imageReader),
        ],
        child: const CypherApp(),
      ),
    );
    // Let the unlock and the first tick land.
    await tester.pump();
    await tester.pump();
  }

  /// Unmounts the app so the ticker and providers are disposed and no timer
  /// is left pending when the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Moves the fake clock and lets the ticker fire.
  Future<void> advance(WidgetTester tester, Duration by) async {
    clock.advance(by);
    await tester.pump(by);
  }
}
