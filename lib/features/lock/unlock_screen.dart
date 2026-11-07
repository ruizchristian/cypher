import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/biometric_auth.dart';
import '../../data/lock_service.dart';
import '../shared/pin_entry.dart';
import '../shared/providers.dart';
import 'lock_strings.dart';

/// The lock screen. Offers biometrics automatically once when shown (if
/// enabled), and counts down any wrong-PIN wait.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  String? _message;
  bool _isError = false;
  bool _busy = false;
  Timer? _countdown;

  LockService get _service => ref.read(lockServiceProvider);

  @override
  void initState() {
    super.initState();
    _syncWait();
    if (_service.settings.biometricsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _biometric();
      });
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  DateTime? get _waitUntil {
    final state = _service.state;
    final until = state is LockLocked ? state.lockedUntil : null;
    final now = ref.read(clockProvider).now();
    return until != null && now.isBefore(until) ? until : null;
  }

  /// Shows the remaining wait and ticks it down; clears it when over.
  void _syncWait() {
    _countdown?.cancel();
    final until = _waitUntil;
    if (until == null) return;
    void update() {
      final remaining = until.difference(ref.read(clockProvider).now());
      if (!mounted) return;
      if (remaining <= Duration.zero) {
        _countdown?.cancel();
        setState(() {
          _message = null;
          _isError = false;
        });
        return;
      }
      setState(() {
        _message = LockStrings.waitFor(remaining);
        _isError = true;
      });
    }

    update();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _submit(String pin) async {
    setState(() => _busy = true);
    try {
      final attempt = await _service.unlockWithPin(pin);
      if (!mounted) return;
      setState(() => _busy = false);
      switch (attempt) {
        case PinAccepted():
          break; // the gate replaces this screen
        case PinRejected(:final attemptsBeforeWait):
          setState(() {
            _message = LockStrings.wrongPin(attemptsBeforeWait);
            _isError = true;
          });
        case PinLockedOut():
          _syncWait();
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = LockStrings.unlockFailed;
        _isError = true;
      });
    }
  }

  Future<void> _biometric() async {
    if (_busy || _waitUntil != null) return;
    final result = await _service.unlockWithBiometrics(
      LockStrings.biometricReason,
    );
    if (!mounted) return;
    if (result == BiometricResult.lockedOut && _waitUntil == null) {
      setState(() {
        _message = LockStrings.biometricLockedOut;
        _isError = true;
      });
    }
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(LockStrings.forgotPin),
        content: const Text(LockStrings.forgotPinBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(LockStrings.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waitUntil != null;
    return Scaffold(
      body: PinEntry(
        title: LockStrings.unlockTitle,
        message: _message,
        isError: _isError,
        enabled: !waiting,
        busy: _busy,
        submitLabel: LockStrings.unlock,
        // Checks as soon as the last digit is typed (once the length is known).
        autoSubmitLength: _service.settings.pinLength,
        onSubmit: _submit,
        onBiometric: _service.settings.biometricsEnabled ? _biometric : null,
        footer: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton(
            onPressed: _forgot,
            child: const Text(LockStrings.forgotPin),
          ),
        ),
      ),
    );
  }
}
