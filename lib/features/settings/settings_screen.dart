import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/biometric_auth.dart';
import '../../data/lock_service.dart';
import '../backup/export_backup_screen.dart';
import '../backup/import_backup_screen.dart';
import '../shared/providers.dart';
import 'change_pin_screen.dart';
import 'settings_strings.dart';

Future<void> openSettings(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late LockSettings _settings = ref.read(lockServiceProvider).settings;
  bool? _biometricsAvailable;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    ref.read(lockServiceProvider).biometricsAvailable().then((available) {
      if (mounted) setState(() => _biometricsAvailable = available);
    });
  }

  Future<void> _setBiometrics(bool enabled) async {
    setState(() => _updating = true);
    final service = ref.read(lockServiceProvider);
    final BiometricResult result;
    try {
      result = await service.setBiometricsEnabled(
        enabled,
        reason: SettingsStrings.biometricEnableReason,
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _updating = false);
      _showSaveFailed();
      return;
    }
    if (!mounted) return;
    setState(() {
      _updating = false;
      _settings = service.settings;
    });
    if (enabled && result != BiometricResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(SettingsStrings.biometricsNotEnabled)),
      );
    }
  }

  Future<void> _chooseAutoLock() async {
    final choice = await showDialog<Duration>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text(SettingsStrings.autoLock),
        children: [
          for (final option in LockSettings.autoLockChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option),
              child: Row(
                children: [
                  Expanded(child: Text(SettingsStrings.autoLockLabel(option))),
                  if (option == _settings.autoLockAfter)
                    const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final service = ref.read(lockServiceProvider);
    try {
      await service.setAutoLockAfter(choice);
    } on Exception {
      if (mounted) _showSaveFailed();
      return;
    }
    if (mounted) setState(() => _settings = service.settings);
  }

  void _showSaveFailed() => ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text(SettingsStrings.saveFailed)));

  @override
  Widget build(BuildContext context) {
    final available = _biometricsAvailable;
    final canSave = ref.watch(backupFilesProvider).canSave;
    final lastBackup = ref.watch(lastBackupProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text(SettingsStrings.title)),
      body: ListView(
        children: [
          const _SectionHeader(SettingsStrings.security),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text(SettingsStrings.biometrics),
            subtitle: available == false
                ? const Text(SettingsStrings.biometricsUnavailable)
                : null,
            value: _settings.biometricsEnabled,
            // Turning off needs no sensor, so it stays possible after the
            // user removes their fingerprints or face.
            onChanged:
                !_updating && (available == true || _settings.biometricsEnabled)
                ? _setBiometrics
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text(SettingsStrings.autoLock),
            subtitle: Text(
              SettingsStrings.autoLockLabel(_settings.autoLockAfter),
            ),
            onTap: _chooseAutoLock,
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text(SettingsStrings.changePin),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChangePinScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text(SettingsStrings.lockNow),
            onTap: () => ref.read(lockServiceProvider).lock(),
          ),
          const _SectionHeader(SettingsStrings.backup),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text(SettingsStrings.exportBackup),
            subtitle: Text(
              canSave
                  ? SettingsStrings.lastBackup(lastBackup?.toLocal())
                  : SettingsStrings.exportUnavailable,
            ),
            enabled: canSave,
            onTap: () => openExportBackup(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text(SettingsStrings.importBackup),
            onTap: () => openImportBackup(context),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
