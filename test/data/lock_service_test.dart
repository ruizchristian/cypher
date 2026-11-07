import 'dart:convert';

import 'package:cypher/core/security/biometric_auth.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/pin_hasher.dart';
import 'package:cypher/core/security/secret_store.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:cypher/data/lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_biometrics.dart';
import '../fakes/fake_clock.dart';
import '../fakes/in_memory_secret_store.dart';
import '../fakes/in_memory_vault_file_store.dart';

const _pin = '482913';
const _cheap = PinHashParams.pbkdf2(iterations: 1);

/// A store whose reads of the PIN hash can be made to throw, like a crash
/// in the middle of a PIN check.
final class _CrashingStore implements SecretStore {
  final InMemorySecretStore _inner = InMemorySecretStore();
  bool crashOnPinRead = false;

  Map<String, String> get values => _inner.values;

  @override
  Future<String?> read(String key) async {
    if (crashOnPinRead && key == 'cypher.lock.pin.v1') {
      throw StateError('simulated crash');
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

void main() {
  late _CrashingStore store;
  late InMemoryVaultFileStore files;
  late FakeBiometrics biometrics;
  late FakeClock clock;

  setUp(() {
    store = _CrashingStore();
    files = InMemoryVaultFileStore();
    biometrics = FakeBiometrics();
    clock = FakeClock.atUnixSeconds(1_700_000_000);
  });

  AccountRepository repository() =>
      AccountRepository(keys: StoredKeyWrapper(store), files: files);

  /// A fresh service over the same storage, like an app restart.
  Future<(LockService, AccountRepository)> start({
    PinHashParams params = _cheap,
  }) async {
    final repo = repository();
    final service = LockService(
      store: store,
      repository: repo,
      biometrics: biometrics,
      now: clock.now,
      params: params,
      hashInIsolate: false,
    );
    await service.initialize();
    return (service, repo);
  }

  Future<LockService> withPin() async {
    final (service, _) = await start();
    await service.createPin(_pin);
    service.lock();
    return (await start()).$1;
  }

  test('first run needs setup; creating the PIN opens the vault', () async {
    final (service, repo) = await start();
    expect(service.state, isA<LockNeedsSetup>());
    await service.createPin(_pin);
    expect(service.state, isA<LockUnlocked>());
    expect(repo.state, isA<VaultUnlocked>());
    expect(store.values['cypher.lock.pin.v1'], isNot(contains(_pin)));
  });

  test(
    'a restart with a PIN starts locked, and the right PIN unlocks',
    () async {
      final service = await withPin();
      expect(service.state, isA<LockLocked>());
      expect(await service.unlockWithPin(_pin), isA<PinAccepted>());
      expect(service.state, isA<LockUnlocked>());
    },
  );

  test('lock drops the vault from memory', () async {
    final (service, repo) = await start();
    await service.createPin(_pin);
    service.lock();
    expect(service.state, isA<LockLocked>());
    expect(repo.state, isA<VaultLocked>());
    expect(() => repo.accounts, throwsStateError);
  });

  group('wrong PINs', () {
    test('count down, then wait 30 s; even the right PIN waits', () async {
      final service = await withPin();
      for (var left = 3; left >= 0; left--) {
        final r = await service.unlockWithPin('000000');
        expect((r as PinRejected).attemptsBeforeWait, left);
      }
      final fifth = await service.unlockWithPin('000000');
      expect(
        (fifth as PinLockedOut).until,
        clock.now().add(const Duration(seconds: 30)),
      );
      expect(await service.unlockWithPin(_pin), isA<PinLockedOut>());

      clock.advance(const Duration(seconds: 30));
      expect(await service.unlockWithPin(_pin), isA<PinAccepted>());
    });

    test('waits escalate and survive a restart', () async {
      var service = await withPin();
      for (var i = 0; i < 5; i++) {
        await service.unlockWithPin('000000');
      }
      clock.advance(const Duration(seconds: 30));
      final sixth = await service.unlockWithPin('000000') as PinLockedOut;
      expect(sixth.until, clock.now().add(const Duration(minutes: 1)));

      service = (await start()).$1; // restart
      final state = service.state as LockLocked;
      expect(state.lockedUntil, sixth.until);
      expect(await service.unlockWithPin(_pin), isA<PinLockedOut>());
    });

    test('a success resets the count', () async {
      final service = await withPin();
      for (var i = 0; i < 4; i++) {
        await service.unlockWithPin('000000');
      }
      await service.unlockWithPin(_pin);
      service.lock();
      final r = await service.unlockWithPin('000000') as PinRejected;
      expect(r.attemptsBeforeWait, 3);
    });

    test('an attempt is counted before it is checked', () async {
      final service = await withPin();
      store.crashOnPinRead = true;
      await expectLater(service.unlockWithPin('000000'), throwsStateError);
      store.crashOnPinRead = false;
      final throttle =
          jsonDecode(store.values['cypher.lock.throttle.v1']!) as Map;
      expect(throttle['failures'], 1);
    });

    test('a damaged throttle record fails closed', () async {
      await withPin();
      store.values['cypher.lock.throttle.v1'] = 'not json';
      final (service, _) = await start();
      expect((service.state as LockLocked).lockedUntil, isNotNull);
      expect(await service.unlockWithPin(_pin), isA<PinLockedOut>());
    });
  });

  group('biometrics', () {
    test('unlock only when enabled', () async {
      final service = await withPin();
      expect(
        await service.unlockWithBiometrics('r'),
        BiometricResult.unavailable,
      );
      expect(biometrics.prompts, 0);
    });

    test('enabling requires a successful check first', () async {
      final (service, _) = await start();
      await service.createPin(_pin);
      biometrics.nextResult = BiometricResult.cancelled;
      expect(
        await service.setBiometricsEnabled(true, reason: 'r'),
        BiometricResult.cancelled,
      );
      expect(service.settings.biometricsEnabled, isFalse);

      biometrics.nextResult = BiometricResult.success;
      await service.setBiometricsEnabled(true, reason: 'r');
      expect(service.settings.biometricsEnabled, isTrue);
      expect(
        (await start()).$1.settings.biometricsEnabled,
        isTrue,
      ); // persisted
    });

    test('unlocks when enabled and resets wrong-PIN count', () async {
      final (service, _) = await start();
      await service.createPin(_pin);
      await service.setBiometricsEnabled(true, reason: 'r');
      service.lock();
      await service.unlockWithPin('000000');
      expect(await service.unlockWithBiometrics('r'), BiometricResult.success);
      expect(service.state, isA<LockUnlocked>());
      service.lock();
      expect(
        ((await service.unlockWithPin(
          '000000',
        )) as PinRejected).attemptsBeforeWait,
        3,
      );
    });

    test('cannot bypass a wrong-PIN wait', () async {
      final (service, _) = await start();
      await service.createPin(_pin);
      await service.setBiometricsEnabled(true, reason: 'r');
      service.lock();
      for (var i = 0; i < 5; i++) {
        await service.unlockWithPin('000000');
      }
      final prompts = biometrics.prompts;
      expect(
        await service.unlockWithBiometrics('r'),
        BiometricResult.lockedOut,
      );
      expect(biometrics.prompts, prompts);
      expect(service.state, isA<LockLocked>());
    });

    test('a removed fingerprint falls back to the PIN', () async {
      final (service, _) = await start();
      await service.createPin(_pin);
      await service.setBiometricsEnabled(true, reason: 'r');
      service.lock();
      biometrics.available = false;
      expect(
        await service.unlockWithBiometrics('r'),
        BiometricResult.unavailable,
      );
      expect(await service.unlockWithPin(_pin), isA<PinAccepted>());
    });
  });

  group('auto-lock', () {
    Future<LockService> unlocked(Duration after) async {
      final (service, _) = await start();
      await service.createPin(_pin);
      await service.setAutoLockAfter(after);
      return service;
    }

    test('a short trip to the background keeps it unlocked', () async {
      final service = await unlocked(const Duration(seconds: 30));
      service.appBackgrounded();
      clock.advance(const Duration(seconds: 29));
      service.appResumed();
      expect(service.state, isA<LockUnlocked>());
    });

    test('reaching the timeout locks on return', () async {
      final service = await unlocked(const Duration(seconds: 30));
      service.appBackgrounded();
      clock.advance(const Duration(seconds: 30));
      service.appResumed();
      expect(service.state, isA<LockLocked>());
    });

    test('"immediately" locks as soon as the app is backgrounded', () async {
      final service = await unlocked(Duration.zero);
      service.appBackgrounded();
      expect(service.state, isA<LockLocked>());
    });

    test('the setting persists and defaults to 30 s', () async {
      final (fresh, _) = await start();
      expect(fresh.settings.autoLockAfter, const Duration(seconds: 30));
      await fresh.setAutoLockAfter(const Duration(minutes: 5));
      expect(
        (await start()).$1.settings.autoLockAfter,
        const Duration(minutes: 5),
      );
    });
  });

  group('change PIN', () {
    test('needs the current PIN', () async {
      final (service, _) = await start();
      await service.createPin(_pin);
      expect(
        await service.changePin('000000', '135790'),
        ChangePinResult.wrongPin,
      );
      expect(await service.changePin(_pin, '135790'), ChangePinResult.changed);
      service.lock();
      expect(await service.unlockWithPin(_pin), isA<PinRejected>());
      expect(await service.unlockWithPin('135790'), isA<PinAccepted>());
    });
  });

  test(
    'a successful unlock upgrades a hash made with old parameters',
    () async {
      final service = await withPin(); // stored with _cheap
      final old = store.values['cypher.lock.pin.v1']!;
      final stronger = await start(
        params: const PinHashParams.pbkdf2(iterations: 2),
      );
      expect(await stronger.$1.unlockWithPin(_pin), isA<PinAccepted>());
      final upgraded = store.values['cypher.lock.pin.v1']!;
      expect(upgraded, isNot(old));
      expect(upgraded, contains(r'$2$'));
      expect(service.state, isA<LockLocked>()); // the old instance is untouched
    },
  );

  group('PIN length (for checking on the last digit)', () {
    test('is remembered on create and change', () async {
      final (service, _) = await start();
      expect(service.settings.pinLength, isNull);
      await service.createPin(_pin);
      expect(service.settings.pinLength, 6);
      await service.changePin(_pin, '13579024');
      expect(service.settings.pinLength, 8);
      expect((await start()).$1.settings.pinLength, 8); // persisted
    });

    test('is learned at the first unlock of an older PIN', () async {
      final service = await withPin();
      store.values.remove('cypher.lock.settings.v1'); // as before M5 tweak
      final legacy = (await start()).$1;
      expect(legacy.settings.pinLength, isNull);
      await legacy.unlockWithPin(_pin);
      expect(legacy.settings.pinLength, 6);
      expect(service.state, isA<LockLocked>());
    });

    test('an out-of-range stored length is ignored', () async {
      store.values['cypher.lock.settings.v1'] = jsonEncode({'pinLength': 3});
      expect((await start()).$1.settings.pinLength, isNull);
    });
  });

  test(
    'wrong current PINs on Change PIN are throttled and lock the app',
    () async {
      final (service, repo) = await start();
      await service.createPin(_pin);
      for (var i = 0; i < 4; i++) {
        expect(
          await service.changePin('000000', '135790'),
          ChangePinResult.wrongPin,
        );
      }
      expect(
        await service.changePin('000000', '135790'),
        ChangePinResult.lockedOut,
      );
      expect(service.state, isA<LockLocked>());
      expect(repo.state, isA<VaultLocked>());
      expect(await service.unlockWithPin(_pin), isA<PinLockedOut>());
    },
  );

  test('a negative stored attempt count fails closed', () async {
    await withPin();
    store.values['cypher.lock.throttle.v1'] = jsonEncode({'failures': -100});
    final (service, _) = await start();
    expect((service.state as LockLocked).lockedUntil, isNotNull);
    expect(await service.unlockWithPin(_pin), isA<PinLockedOut>());
  });
}
