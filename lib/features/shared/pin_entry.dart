import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/pin_hasher.dart';

// Text owned by the PIN pad itself (shared by lock and settings).
abstract final class PinEntryStrings {
  static const String useBiometrics = 'Use fingerprint or face';
  static const String backspace = 'Delete last digit';
  static String digitsEntered(int count) =>
      count == 1 ? '1 digit entered' : '$count digits entered';
}

/// A full PIN entry: title, explanation or error, digit dots, a number pad
/// and a submit button. Digits live only in this widget's state and are
/// cleared on submit, so the PIN is never kept around.
///
/// Hardware keyboards work too (digits, Backspace, Enter).
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.title,
    required this.onSubmit,
    required this.submitLabel,
    this.message,
    this.isError = false,
    this.enabled = true,
    this.busy = false,
    this.onBiometric,
    this.footer,
    this.autoSubmitLength,
  });

  final String title;

  /// Explanation, or an error when [isError].
  final String? message;
  final bool isError;

  /// Called with the entered PIN (always [PinPolicy]-valid).
  final ValueChanged<String> onSubmit;
  final String submitLabel;

  /// False while a wait is active: the pad ignores input.
  final bool enabled;

  /// True while a PIN is being checked.
  final bool busy;

  /// Shows a biometric button on the pad when set.
  final VoidCallback? onBiometric;
  final Widget? footer;

  /// When set, the PIN is submitted as soon as this many digits are typed
  /// and no submit button is shown (a spinner shows while checking).
  final int? autoSubmitLength;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  final FocusNode _focus = FocusNode();

  bool get _active => widget.enabled && !widget.busy;

  @override
  void dispose() {
    _pin = '';
    _focus.dispose();
    super.dispose();
  }

  void _digit(String d) {
    if (!_active || _pin.length >= PinPolicy.maxLength) return;
    setState(() => _pin += d);
    if (_pin.length == widget.autoSubmitLength) _submit();
  }

  void _backspace() {
    if (!_active || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (!_active || !PinPolicy.isValid(_pin)) return;
    final pin = _pin;
    setState(() => _pin = '');
    widget.onSubmit(pin);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final char = event.character;
    if (char != null && char.length == 1 && '0123456789'.contains(char)) {
      _digit(char);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: message == null
                        ? null
                        : Semantics(
                            liveRegion: true,
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: widget.isError
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ),
                          ),
                  ),
                  _PinDots(count: _pin.length),
                  const SizedBox(height: 24),
                  _NumberPad(
                    enabled: _active,
                    onDigit: _digit,
                    onBackspace: _backspace,
                    onBiometric: widget.onBiometric,
                  ),
                  const SizedBox(height: 16),
                  if (widget.autoSubmitLength == null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _active && PinPolicy.isValid(_pin)
                            ? _submit
                            : null,
                        child: widget.busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(widget.submitLabel),
                      ),
                    )
                  else
                    SizedBox(
                      height: 40,
                      child: widget.busy
                          ? const Center(
                              child: SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ?widget.footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slots = count < PinPolicy.minLength ? PinPolicy.minLength : count;
    return Semantics(
      label: PinEntryStrings.digitsEntered(count),
      excludeSemantics: true,
      child: Wrap(
        spacing: 12,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < slots; i++)
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < count ? scheme.primary : null,
                border: Border.all(color: scheme.outline, width: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    Widget key(String digit) => _PadKey(
      onPressed: enabled ? () => onDigit(digit) : null,
      child: Text(digit, style: Theme.of(context).textTheme.headlineSmall),
    );
    final biometric = onBiometric;
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [for (final d in row) key(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            biometric == null
                ? const SizedBox(width: 72, height: 72)
                : _PadKey(
                    onPressed: enabled ? biometric : null,
                    tooltip: PinEntryStrings.useBiometrics,
                    child: const Icon(Icons.fingerprint, size: 32),
                  ),
            key('0'),
            _PadKey(
              onPressed: enabled ? onBackspace : null,
              tooltip: PinEntryStrings.backspace,
              child: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({required this.onPressed, required this.child, this.tooltip});

  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 72,
      height: 72,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(shape: const CircleBorder()),
        child: child,
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
