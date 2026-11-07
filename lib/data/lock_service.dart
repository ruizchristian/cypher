import 'dart:async';
import 'dart:convert';

import '../core/security/biometric_auth.dart';
import '../core/security/pin_hasher.dart';
import '../core/security/pin_throttle.dart';
import '../core/security/secret_store.dart';
import 'account_repository.dart';

sealed class LockState {
  const LockState();
}

final class LockLoading extends LockState {
  const LockLoading();
}

/// First run: no PIN yet. The PIN is mandatory (docs/system-plan.md D8).
final class LockNeedsSetup extends LockState {
  const LockNeedsSetup();
}

final class LockLocked extends LockState {
  const LockLocked({this.lockedUntil, this.failures = 0});

  /// While set and in the future, PIN entry is refused.
  final DateTime? lockedUntil;
  final int failures;
}

final class LockUnlocked extends LockState {
  const LockUnlocked();
}

sealed class PinAttempt {
  const PinAttempt();
}

final class PinAccepted extends PinAttempt {
  const PinAccepted();
}

final class PinRejected extends PinAttempt {
  const PinRejected({required this.attemptsBeforeWait});

  /// Wrong PINs still allowed before a wait starts (0 = the next one waits).
  final int attemptsBeforeWait;
}

/// Outcome of re-checking the PIN while unlocked ([LockService.confirmPin]).
enum PinCheck {
  correct,
  wrong,

  /// Too many wrong PINs: the app has locked, with a wait.
  lockedOut,
}

enum ChangePinResult {
  changed,

  /// The current PIN was wrong; the attempt counts towards the throttle.
  wrongPin,

  /// Too many wrong current PINs: the app has locked, with a wait.
  lockedOut,
}

final class PinLockedOut extends PinAttempt {
  const PinLockedOut(this.until);

  final DateTime until;
}

final class LockSettings {
  const LockSettings({
    this.biometricsEnabled = false,
    this.autoLockAfter = defaultAutoLock,
    this.pinLength,
  });

  static const Duration defaultAutoLock = Duration(seconds: 30);

  /// Choices offered in Settings; [Duration.zero] locks immediately.
  static const List<Duration> autoLockChoices = [
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  final bool biometricsEnabled;
  final Duration autoLockAfter;

  /// Digits in the PIN, so the pad can check it as soon as the last digit is
  /// typed. `null` for PINs set before this was recorded; it is learned at
  /// the next successful unlock. Stored with the other settings in secure
  /// storage; revealing it narrows guessing only slightly, and every guess
  /// is still throttled.
  final int? pinLength;

  LockSettings copyWith({
    bool? biometricsEnabled,
    Duration? autoLockAfter,
    int? pinLength,
  }) => LockSettings(
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    autoLockAfter: autoLockAfter ?? this.autoLockAfter,
    pinLength: pinLength ?? this.pinLength,
  );
}

/// The app lock: PIN setup and checks, biometric unlock, wrong-PIN
/// throttling, and auto-lock after time in the background.
///
/// In v1 the lock gates the vault rather than encrypting it (the vault key is
/// protected by the Keystore/Keychain; see docs/system-plan.md D6 and §6.1).
/// Unlocking opens the vault; locking drops it from memory.
///
/// Persisted in [SecretStore]: the PIN hash, the settings and the throttle
/// counters, so waits survive restarts.
final class LockService {
  LockService({
    required this._store,
    required this._repository,
    required this._biometrics,
    this._now = DateTime.now,
    this._params = PinHasher.defaultParams,
    this._hashInIsolate = true,
    this.keyNamespace = defaultKeyNamespace,
  });

  static const String defaultKeyNamespace = 'cypher.lock';

  /// Prefix of every key this service stores. On-device tests use their own
  /// namespace so they never touch a real PIN.
  final String keyNamespace;

  String get pinKey => '$keyNamespace.pin.v1';
  String get settingsKey => '$keyNamespace.settings.v1';
  String get throttleKey => '$keyNamespace.throttle.v1';

  final SecretStore _store;
  final AccountRepository _repository;
  final BiometricAuth _biometrics;
  final DateTime Function() _now;
  final PinHashParams _params;

  // False only in widget tests (see [PinHasher.hash]).
  final bool _hashInIsolate;

  final StreamController<LockState> _states =
      StreamController<LockState>.broadcast();
  LockState _state = const LockLoading();
  LockSettings _settings = const LockSettings();
  int _failures = 0;
  DateTime? _lockedUntil;
  DateTime? _backgroundedAt;

  LockState get state => _state;
  Stream<LockState> get states => _states.stream;
  LockSettings get settings => _settings;

  Future<void> initialize() async {
    _settings = await _readSettings();
    await _readThrottle();
    final pin = await _store.read(pinKey);
    _publish(pin == null ? const LockNeedsSetup() : _lockedState());
  }

  /// First-run PIN creation. Opens the vault on success.
  Future<void> createPin(String pin) async {
    if (_state is! LockNeedsSetup) {
      throw StateError('A PIN already exists');
    }
    await _store.write(
      pinKey,
      await PinHasher.hash(pin, params: _params, inIsolate: _hashInIsolate),
    );
    await _rememberPinLength(pin);
    await _unlockVault();
  }

  Future<PinAttempt> unlockWithPin(String pin) async {
    if (_state is! LockLocked) throw StateError('Not locked');
    final wait = _activeWait();
    if (wait != null) return PinLockedOut(wait);

    // Count the attempt before checking it, so killing the app mid-check
    // cannot be used to get unlimited tries.
    _failures++;
    await _writeThrottle();

    final encoded = await _store.read(pinKey);
    final ok =
        encoded != null &&
        await PinHasher.verify(pin, encoded, inIsolate: _hashInIsolate);
    if (ok) {
      await _clearThrottle();
      if (PinHasher.needsRehash(encoded, current: _params)) {
        await _store.write(
          pinKey,
          await PinHasher.hash(pin, params: _params, inIsolate: _hashInIsolate),
        );
      }
      await _rememberPinLength(pin);
      await _unlockVault();
      return const PinAccepted();
    }

    final waitFor = PinThrottle.waitAfter(_failures);
    if (waitFor != null) {
      final until = _now().add(waitFor);
      _lockedUntil = until;
      await _writeThrottle();
      _publish(_lockedState());
      return PinLockedOut(until);
    }
    _publish(_lockedState());
    return PinRejected(
      attemptsBeforeWait: PinThrottle.freeAttempts - _failures - 1,
    );
  }

  /// Unlocks with biometrics when enabled and available. Never bypasses an
  /// active wrong-PIN wait.
  Future<BiometricResult> unlockWithBiometrics(String reason) async {
    if (_state is! LockLocked || !_settings.biometricsEnabled) {
      return BiometricResult.unavailable;
    }
    if (_activeWait() != null) return BiometricResult.lockedOut;
    if (!await _biometrics.isAvailable()) return BiometricResult.unavailable;
    final result = await _biometrics.authenticate(reason);
    if (result == BiometricResult.success && _state is LockLocked) {
      await _clearThrottle();
      await _unlockVault();
    }
    return result;
  }

  Future<bool> biometricsAvailable() => _biometrics.isAvailable();

  /// Locks now: the vault and its key leave memory.
  void lock() {
    if (_state is! LockUnlocked) return;
    _repository.lock();
    _backgroundedAt = null;
    _publish(_lockedState());
  }

  void appBackgrounded() {
    if (_state is! LockUnlocked) return;
    if (_settings.autoLockAfter == Duration.zero) {
      lock();
    } else {
      _backgroundedAt ??= _now();
    }
  }

  void appResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (_state is LockUnlocked &&
        since != null &&
        _now().difference(since) >= _settings.autoLockAfter) {
      lock();
    }
  }

  /// Changes the PIN after checking the current one with [confirmPin], so
  /// wrong current PINs are throttled like the lock screen's.
  Future<ChangePinResult> changePin(String current, String next) async {
    switch (await confirmPin(current)) {
      case PinCheck.wrong:
        return ChangePinResult.wrongPin;
      case PinCheck.lockedOut:
        return ChangePinResult.lockedOut;
      case PinCheck.correct:
        break;
    }
    await _store.write(
      pinKey,
      await PinHasher.hash(next, params: _params, inIsolate: _hashInIsolate),
    );
    await _rememberPinLength(next);
    return ChangePinResult.changed;
  }

  /// Re-checks the PIN while unlocked, before a sensitive action (changing
  /// the PIN, exporting every secret).
  ///
  /// Wrong PINs count towards the same throttle as the lock screen, counted
  /// before the check; otherwise this would be an unthrottled way to guess
  /// the PIN on an unlocked phone. Reaching a wait locks the app.
  Future<PinCheck> confirmPin(String pin) async {
    if (_state is! LockUnlocked) throw StateError('Unlock first');
    _failures++;
    await _writeThrottle();
    final encoded = await _store.read(pinKey);
    final ok =
        encoded != null &&
        await PinHasher.verify(pin, encoded, inIsolate: _hashInIsolate);
    if (!ok) {
      final waitFor = PinThrottle.waitAfter(_failures);
      if (waitFor == null) return PinCheck.wrong;
      _lockedUntil = _now().add(waitFor);
      await _writeThrottle();
      lock();
      return PinCheck.lockedOut;
    }
    await _clearThrottle();
    return PinCheck.correct;
  }

  /// Turning biometrics on requires a successful biometric check first, so
  /// it is never enabled on a device whose sensor the user cannot pass.
  Future<BiometricResult> setBiometricsEnabled(
    bool enabled, {
    required String reason,
  }) async {
    if (enabled) {
      if (!await _biometrics.isAvailable()) return BiometricResult.unavailable;
      final result = await _biometrics.authenticate(reason);
      if (result != BiometricResult.success) return result;
    }
    _settings = _settings.copyWith(biometricsEnabled: enabled);
    await _writeSettings();
    return BiometricResult.success;
  }

  Future<void> setAutoLockAfter(Duration after) async {
    _settings = _settings.copyWith(autoLockAfter: after);
    await _writeSettings();
  }

  Future<void> dispose() => _states.close();

  Future<void> _rememberPinLength(String pin) async {
    if (_settings.pinLength == pin.length) return;
    _settings = _settings.copyWith(pinLength: pin.length);
    await _writeSettings();
  }

  Future<void> _unlockVault() async {
    await _repository.unlock();
    _publish(const LockUnlocked());
  }

  DateTime? _activeWait() {
    final until = _lockedUntil;
    return until != null && _now().isBefore(until) ? until : null;
  }

  LockState _lockedState() =>
      LockLocked(lockedUntil: _activeWait(), failures: _failures);

  void _publish(LockState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<LockSettings> _readSettings() async {
    final raw = await _store.read(settingsKey);
    if (raw == null) return const LockSettings();
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final seconds = json['autoLockSeconds'];
      final after = seconds is int
          ? Duration(seconds: seconds)
          : LockSettings.defaultAutoLock;
      final length = json['pinLength'];
      return LockSettings(
        biometricsEnabled: json['biometrics'] == true,
        pinLength:
            length is int &&
                length >= PinPolicy.minLength &&
                length <= PinPolicy.maxLength
            ? length
            : null,
        autoLockAfter: LockSettings.autoLockChoices.contains(after)
            ? after
            : LockSettings.defaultAutoLock,
      );
    } on Object {
      return const LockSettings();
    }
  }

  Future<void> _writeSettings() => _store.write(
    settingsKey,
    jsonEncode({
      'biometrics': _settings.biometricsEnabled,
      'autoLockSeconds': _settings.autoLockAfter.inSeconds,
      'pinLength': _settings.pinLength,
    }),
  );

  Future<void> _readThrottle() async {
    final raw = await _store.read(throttleKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final failures = (json['failures'] as int?) ?? 0;
      if (failures < 0) throw const FormatException('negative failures');
      _failures = failures;
      final until = json['lockedUntilMs'] as int?;
      _lockedUntil = until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until, isUtc: true);
    } on Object {
      // A damaged record must not unlock anything: assume the worst case.
      _failures = PinThrottle.freeAttempts;
      _lockedUntil = _now().add(PinThrottle.waitAfter(_failures)!);
    }
  }

  Future<void> _clearThrottle() {
    _failures = 0;
    _lockedUntil = null;
    return _writeThrottle();
  }

  Future<void> _writeThrottle() => _store.write(
    throttleKey,
    jsonEncode({
      'failures': _failures,
      'lockedUntilMs': _lockedUntil?.toUtc().millisecondsSinceEpoch,
    }),
  );
}
