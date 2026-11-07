import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/pin_entry.dart';
import '../shared/providers.dart';
import 'lock_strings.dart';

/// First run: create the mandatory PIN, confirm it, then optionally turn on
/// biometrics. Completing setup opens the vault.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String? _first;
  String? _error;
  bool _busy = false;
  int _errors = 0; // drives the PIN pad's shake

  Future<void> _onSubmit(String pin) async {
    final first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != first) {
      setState(() {
        _first = null;
        _error = LockStrings.mismatch;
        _errors++;
      });
      return;
    }
    _first = null;
    final service = ref.read(lockServiceProvider);
    if (await service.biometricsAvailable() && mounted) {
      final wanted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text(LockStrings.biometricOfferTitle),
          content: const Text(LockStrings.biometricOfferBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(LockStrings.biometricOfferNo),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(LockStrings.biometricOfferYes),
            ),
          ],
        ),
      );
      if (wanted == true) {
        // Only turns on if the user passes a biometric check now; otherwise
        // biometrics simply stay off and the PIN is used.
        await service.setBiometricsEnabled(
          true,
          reason: LockStrings.biometricEnableReason,
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await service.createPin(pin); // opens the vault; the gate moves on
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = LockStrings.unlockFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return Scaffold(
      body: PinEntry(
        key: ValueKey(confirming),
        title: confirming ? LockStrings.confirmTitle : LockStrings.createTitle,
        message:
            _error ??
            (confirming ? LockStrings.confirmBody : LockStrings.createBody),
        isError: _error != null,
        busy: _busy,
        submitLabel: LockStrings.continueLabel,
        // Confirming: the length is known from the first entry.
        autoSubmitLength: _first?.length,
        onSubmit: _onSubmit,
        errorSignal: _errors,
        footer: confirming
            ? null
            : const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  LockStrings.noRecovery,
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
}
