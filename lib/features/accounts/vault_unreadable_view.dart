import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/account_repository.dart';
import '../shared/providers.dart';
import 'accounts_strings.dart';

/// Shown when the vault exists but cannot be opened. Starting over is an
/// explicit, confirmed action, and the old file is kept (see
/// `AccountRepository.resetUnreadableVault`). Restoring from an encrypted
/// backup arrives with M6.
class VaultUnreadableView extends ConsumerWidget {
  const VaultUnreadableView({super.key, required this.reason});

  final VaultUnreadableReason reason;

  String get _explanation => switch (reason) {
    VaultUnreadableReason.keyMissing => AccountsStrings.unreadableKeyMissing,
    VaultUnreadableReason.decryptFailed =>
      AccountsStrings.unreadableDecryptFailed,
    VaultUnreadableReason.corruptContent => AccountsStrings.unreadableCorrupt,
  };

  Future<void> _startOver(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AccountsStrings.startOverConfirmTitle),
        content: const Text(AccountsStrings.startOverConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AccountsStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AccountsStrings.startOver),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(accountRepositoryProvider).resetUnreadableVault();
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AccountsStrings.saveFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              AccountsStrings.unreadableTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(_explanation, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              AccountsStrings.unreadableKept,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => _startOver(context, ref),
              child: const Text(AccountsStrings.startOver),
            ),
          ],
        ),
      ),
    );
  }
}
