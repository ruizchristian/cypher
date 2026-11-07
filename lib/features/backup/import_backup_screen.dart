import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup_service.dart';
import '../add_account/confirm_import_screen.dart';
import '../shared/backup_files.dart';
import '../shared/providers.dart';
import 'backup_password_field.dart';
import 'backup_strings.dart';

/// Opens the import flow: choose file, enter its password, then the same
/// confirmation step as adding accounts (duplicates skipped, all-or-nothing).
Future<void> openImportBackup(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const ImportBackupScreen()));

class ImportBackupScreen extends ConsumerStatefulWidget {
  const ImportBackupScreen({super.key});

  @override
  ConsumerState<ImportBackupScreen> createState() => _ImportBackupScreenState();
}

class _ImportBackupScreenState extends ConsumerState<ImportBackupScreen> {
  Uint8List? _file;
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    // Detach first: clearing notifies listeners, and this state is gone.
    _password
      ..removeListener(_rebuild)
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() => _error = null);
    try {
      final bytes = await ref.read(backupFilesProvider).open();
      if (!mounted || bytes == null) return;
      setState(() => _file = bytes);
    } on BackupFileTooLarge {
      if (mounted) setState(() => _error = BackupStrings.fileTooLarge);
    } on Exception {
      if (mounted) setState(() => _error = BackupStrings.openFailed);
    }
  }

  // The keyboard's submit goes through this too, so an empty password never
  // runs the slow KDF only to report a wrong password.
  bool get _canDecrypt => !_busy && _password.text.isNotEmpty;

  Future<void> _decrypt() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accounts = await ref
          .read(backupServiceProvider)
          .readBackup(file, _password.text);
      if (!mounted) return;
      _password.clear();
      replaceWithConfirm(context, accounts);
    } on BackupReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = BackupStrings.problem(e.problem);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _file != null;
    return Scaffold(
      appBar: AppBar(title: const Text(BackupStrings.importTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(BackupStrings.importIntro),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text(BackupStrings.chooseFile),
          ),
          if (hasFile) ...[
            const SizedBox(height: 8),
            const Text(BackupStrings.fileChosen),
            const SizedBox(height: 16),
            BackupPasswordField(
              controller: _password,
              label: BackupStrings.passwordLabel,
              enabled: !_busy,
              obscured: !_showPassword,
              onToggleObscured: () =>
                  setState(() => _showPassword = !_showPassword),
              onSubmitted: (_) {
                if (_canDecrypt) _decrypt();
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canDecrypt ? _decrypt : null,
              child: const Text(BackupStrings.decrypt),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text(BackupStrings.decrypting)),
              ],
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
