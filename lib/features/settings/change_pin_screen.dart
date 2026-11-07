import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lock_service.dart';
import '../shared/pin_entry.dart';
import '../shared/providers.dart';
import 'settings_strings.dart';

enum _Step { current, next, confirm }

/// Current PIN → new PIN → confirm. Nothing changes until the last step.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  _Step _step = _Step.current;
  String? _current;
  String? _next;
  String? _error;
  bool _busy = false;
  int _errors = 0; // drives the PIN pad's shake

  @override
  void dispose() {
    _current = null;
    _next = null;
    super.dispose();
  }

  Future<void> _onSubmit(String pin) async {
    switch (_step) {
      case _Step.current:
        setState(() {
          _current = pin;
          _step = _Step.next;
          _error = null;
        });
      case _Step.next:
        setState(() {
          _next = pin;
          _step = _Step.confirm;
          _error = null;
        });
      case _Step.confirm:
        final current = _current;
        if (current == null) return;
        if (pin != _next) {
          setState(() {
            _next = null;
            _step = _Step.next;
            _error = SettingsStrings.mismatch;
            _errors++;
          });
          return;
        }
        setState(() => _busy = true);
        final ChangePinResult result;
        try {
          result = await ref.read(lockServiceProvider).changePin(current, pin);
        } on Exception {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(SettingsStrings.saveFailed)),
          );
          return;
        }
        if (!mounted) return;
        switch (result) {
          case ChangePinResult.changed:
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            messenger.showSnackBar(
              const SnackBar(content: Text(SettingsStrings.pinChanged)),
            );
          case ChangePinResult.wrongPin:
            setState(() {
              _busy = false;
              _current = null;
              _next = null;
              _step = _Step.current;
              _error = SettingsStrings.wrongCurrentPin;
              _errors++;
            });
          case ChangePinResult.lockedOut:
            break; // the app has locked; the lock gate replaces this screen
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (_step) {
      _Step.current => (SettingsStrings.currentPinTitle, null),
      _Step.next => (SettingsStrings.newPinTitle, SettingsStrings.newPinBody),
      _Step.confirm => (SettingsStrings.confirmNewPinTitle, null),
    };
    return Scaffold(
      appBar: AppBar(title: const Text(SettingsStrings.changePin)),
      body: PinEntry(
        key: ValueKey(_step),
        title: title,
        message: _error ?? body,
        isError: _error != null,
        busy: _busy,
        submitLabel: SettingsStrings.continueLabel,
        onSubmit: _onSubmit,
        errorSignal: _errors,
        // The current PIN's length is known; so is the new one when confirming.
        autoSubmitLength: switch (_step) {
          _Step.current => ref.read(lockServiceProvider).settings.pinLength,
          _Step.next => null,
          _Step.confirm => _next?.length,
        },
      ),
    );
  }
}
