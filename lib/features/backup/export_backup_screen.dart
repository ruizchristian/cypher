import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/backup_cipher.dart';
import '../../data/lock_service.dart';
import '../shared/pin_entry.dart';
import '../shared/providers.dart';
import 'backup_password_field.dart';
import 'backup_strings.dart';

/// Opens the export flow: PIN check, backup password, then "Save as".
Future<void> openExportBackup(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const ExportBackupScreen()));

class ExportBackupScreen extends ConsumerStatefulWidget {
  const ExportBackupScreen({super.key});

  @override
  ConsumerState<ExportBackupScreen> createState() => _ExportBackupScreenState();
}

class _ExportBackupScreenState extends ConsumerState<ExportBackupScreen> {
  bool _pinConfirmed = false;
  String? _pinError;
  bool _busy = false;

  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _password.addListener(_rebuild);
    _confirm.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    // Detach first: clearing notifies listeners, and this state is gone.
    for (final c in [_password, _confirm]) {
      c
        ..removeListener(_rebuild)
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _checkPin(String pin) async {
    setState(() => _busy = true);
    final result = await ref.read(lockServiceProvider).confirmPin(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case PinCheck.correct:
          _pinConfirmed = true;
          _pinError = null;
        case PinCheck.wrong:
          _pinError = BackupStrings.wrongPin;
        case PinCheck.lockedOut:
          break; // the app has locked; the lock gate replaces this screen
      }
    });
  }

  bool get _canExport =>
      !_busy &&
      BackupPassword.isAcceptable(_password.text) &&
      _password.text == _confirm.text;

  Future<void> _export() async {
    // Read before any await: `ref` throws once the app locks and removes
    // this screen.
    final files = ref.read(backupFilesProvider);
    final backup = ref.read(backupServiceProvider);
    final name = BackupStrings.fileName(ref.read(clockProvider).now());
    setState(() {
      _busy = true;
      _status = BackupStrings.encrypting;
    });
    try {
      final bytes = await backup.export(_password.text);
      if (!mounted) return; // locked meanwhile: no "Save as" over the lock
      final saved = await files.save(name, bytes);
      // Recorded even if this screen is gone: the "Save as" dialog
      // backgrounds the app, which may lock it before the save returns.
      if (saved) {
        try {
          await backup.recordBackupSaved();
        } on Exception {
          // The file is saved; only the reminder's date could not be stored.
          // Reporting the save as failed would be wrong.
        }
      }
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _busy = false;
          _status = BackupStrings.notSaved;
        });
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(BackupStrings.saved),
          duration: Duration(seconds: 8),
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = BackupStrings.saveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(backupFilesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(BackupStrings.exportTitle)),
      body: !files.canSave
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  BackupStrings.exportUnavailable,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : !_pinConfirmed
          ? PinEntry(
              title: BackupStrings.exportPinTitle,
              message: _pinError ?? BackupStrings.exportPinBody,
              isError: _pinError != null,
              busy: _busy,
              submitLabel: BackupStrings.continueLabel,
              autoSubmitLength: ref
                  .read(lockServiceProvider)
                  .settings
                  .pinLength,
              onSubmit: _checkPin,
            )
          : _passwordStep(context),
    );
  }

  Widget _passwordStep(BuildContext context) {
    final mismatch =
        _confirm.text.isNotEmpty && _confirm.text != _password.text;
    void toggleObscured() => setState(() => _showPassword = !_showPassword);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(BackupStrings.passwordIntro),
        const SizedBox(height: 16),
        BackupPasswordField(
          controller: _password,
          label: BackupStrings.passwordLabel,
          enabled: !_busy,
          obscured: !_showPassword,
          onToggleObscured: toggleObscured,
          helperText: BackupStrings.passwordHint(_password.text),
        ),
        const SizedBox(height: 8),
        BackupPasswordField(
          controller: _confirm,
          label: BackupStrings.confirmLabel,
          enabled: !_busy,
          obscured: !_showPassword,
          onToggleObscured: toggleObscured,
          errorText: mismatch ? BackupStrings.mismatch : null,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _canExport ? _export : null,
          child: const Text(BackupStrings.export),
        ),
        if (_status case final status?) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              if (_busy) ...[
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Semantics(liveRegion: true, child: Text(status))),
            ],
          ),
        ],
      ],
    );
  }
}
