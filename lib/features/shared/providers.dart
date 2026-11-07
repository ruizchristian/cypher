import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/security/secure_clipboard.dart';
import '../../data/account_repository.dart';
import '../../data/backup_service.dart';
import '../../data/lock_service.dart';
import 'backup_files.dart';
import 'qr_input.dart';

// Injected dependencies. They have no defaults on purpose: `main.dart` wires
// the real implementations and tests override them with fakes, so nothing
// silently falls back to a platform service.

final clockProvider = Provider<Clock>(
  (ref) => throw UnimplementedError('clockProvider must be overridden'),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) =>
      throw UnimplementedError('accountRepositoryProvider must be overridden'),
);

final secureClipboardProvider = Provider<SecureClipboard>(
  (ref) =>
      throw UnimplementedError('secureClipboardProvider must be overridden'),
);

/// The vault's current state followed by every change.
final vaultStateProvider = StreamProvider<VaultState>((ref) {
  final repository = ref.watch(accountRepositoryProvider);
  final controller = StreamController<VaultState>();
  // Subscribe before reading the current state, so no change published in
  // between can be missed.
  final subscription = repository.states.listen(controller.add);
  controller.add(repository.state);
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The single app-wide tick that drives every code and countdown. It fires
/// on each second boundary and stops when nothing is listening (for example
/// when no codes are on screen).
final tickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  final controller = StreamController<DateTime>();
  Timer? timer;

  void tick() {
    final now = clock.now();
    controller.add(now);
    timer = Timer(Duration(milliseconds: 1000 - now.millisecond), tick);
  }

  tick();
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The live QR scanner (ZXing in the app, a fake in tests).
final qrScannerBuilderProvider = Provider<QrScannerBuilder>(
  (ref) =>
      throw UnimplementedError('qrScannerBuilderProvider must be overridden'),
);

/// Reads a QR code from a picked image (ZXing in the app, a fake in tests).
final qrImageReaderProvider = Provider<QrImageReader>(
  (ref) => throw UnimplementedError('qrImageReaderProvider must be overridden'),
);

/// The app lock (PIN, biometrics, auto-lock). Wired in `main.dart`.
final lockServiceProvider = Provider<LockService>(
  (ref) => throw UnimplementedError('lockServiceProvider must be overridden'),
);

/// The lock's current state followed by every change.
final lockStateProvider = StreamProvider<LockState>((ref) {
  final service = ref.watch(lockServiceProvider);
  final controller = StreamController<LockState>();
  // Subscribe before reading the current state, so no change is missed.
  final subscription = service.states.listen(controller.add);
  controller.add(service.state);
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Encrypted backup export/import. Wired in `main.dart`.
final backupServiceProvider = Provider<BackupService>(
  (ref) => throw UnimplementedError('backupServiceProvider must be overridden'),
);

/// The system's save/open pickers for backup files (a fake in tests).
final backupFilesProvider = Provider<BackupFiles>(
  (ref) => throw UnimplementedError('backupFilesProvider must be overridden'),
);

/// When the last backup was saved (`null` if never), then every change.
final lastBackupProvider = StreamProvider<DateTime?>((ref) {
  final service = ref.watch(backupServiceProvider);
  final controller = StreamController<DateTime?>();
  final subscription = service.lastBackupChanges.listen(controller.add);
  controller.add(service.lastBackupAt);
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});
