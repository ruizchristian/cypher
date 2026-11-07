import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/account.dart';
import '../../data/account_repository.dart';
import '../add_account/add_account_sheet.dart';
import '../backup/export_backup_screen.dart';
import '../settings/settings_screen.dart';
import '../shared/app_logo.dart';
import '../shared/providers.dart';
import 'account_tile.dart';
import 'accounts_strings.dart';
import 'vault_unreadable_view.dart';

/// Home screen: the account list. Only reachable while unlocked: the lock gate
/// (`app/lock_gate.dart`) opens the vault after the PIN or biometrics.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  // "Later" on the backup reminder hides it until the app restarts.
  bool _reminderHidden = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setSearching(bool searching) {
    setState(() {
      _searching = searching;
      if (!searching) _search.clear();
    });
  }

  /// Only once the last backup is known to be "never".
  bool get _showBackupReminder {
    if (_reminderHidden) return false;
    final lastBackup = ref.watch(lastBackupProvider);
    return lastBackup.hasValue && lastBackup.value == null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultStateProvider).value;
    final accounts = state is VaultUnlocked ? state.accounts : null;

    return Scaffold(
      floatingActionButton: accounts == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAddAccountSheet(context),
              icon: const Icon(Icons.add),
              label: const Text(AccountsStrings.addAccount),
            ),
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: AccountsStrings.searchHint,
                  border: InputBorder.none,
                ),
              )
            : const Text(AccountsStrings.screenTitle),
        actions: [
          if (accounts != null && accounts.isNotEmpty)
            IconButton(
              tooltip: _searching
                  ? AccountsStrings.closeSearch
                  : AccountsStrings.search,
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => _setSearching(!_searching),
            ),
          if (!_searching) ...[
            IconButton(
              tooltip: AccountsStrings.lockNow,
              icon: const Icon(Icons.lock_outline),
              onPressed: () => ref.read(lockServiceProvider).lock(),
            ),
            IconButton(
              tooltip: AccountsStrings.settings,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => openSettings(context),
            ),
          ],
        ],
      ),
      body: switch (state) {
        VaultUnreadable(:final reason) => VaultUnreadableView(reason: reason),
        VaultUnlocked(:final accounts) when accounts.isEmpty => const _Message(
          logo: true,
          icon: Icons.shield_outlined,
          title: AccountsStrings.emptyTitle,
          body: AccountsStrings.emptyBody,
        ),
        VaultUnlocked(:final accounts) => Column(
          children: [
            if (_showBackupReminder)
              _BackupReminder(
                onLater: () => setState(() => _reminderHidden = true),
              ),
            Expanded(
              child: _AccountList(
                accounts: accounts,
                query: _searching ? _search.text.trim() : '',
              ),
            ),
          ],
        ),
        VaultLocked() ||
        null => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _AccountList extends ConsumerWidget {
  const _AccountList({required this.accounts, required this.query});

  final List<Account> accounts;
  final String query;

  static bool _matches(Account account, String lowerQuery) =>
      account.issuer.toLowerCase().contains(lowerQuery) ||
      account.accountName.toLowerCase().contains(lowerQuery);

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    int from,
    int to,
  ) async {
    try {
      await ref.read(accountRepositoryProvider).reorder(from, to);
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AccountsStrings.saveFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.isNotEmpty) {
      // Reordering is disabled while filtering: indices would not match the
      // stored order.
      final lowerQuery = query.toLowerCase();
      final matches = [
        for (final a in accounts)
          if (_matches(a, lowerQuery)) a,
      ];
      if (matches.isEmpty) {
        return const _Message(
          icon: Icons.search_off,
          title: AccountsStrings.noMatches,
        );
      }
      return ListView.builder(
        itemCount: matches.length,
        itemBuilder: (_, i) =>
            AccountTile(key: ValueKey(matches[i].id), account: matches[i]),
      );
    }
    // On phones the default drag handles are a long-press anywhere on the
    // row, so rows stay free of permanent handles. Screen readers get
    // "move up/down" actions from the list.
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: accounts.length,
      onReorderItem: (from, to) => _reorder(context, ref, from, to),
      proxyDecorator: (child, _, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Material(
          elevation: 6 * animation.value,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
        child: child,
      ),
      itemBuilder: (_, i) =>
          AccountTile(key: ValueKey(accounts[i].id), account: accounts[i]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.logo = false,
  });

  /// Shows the CypherAuth logo instead of [icon].
  final bool logo;

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo)
              const AppLogo(height: 72)
            else
              Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown until the first backup: without one, a forgotten PIN or a lost
/// phone means the accounts are gone.
class _BackupReminder extends ConsumerWidget {
  const _BackupReminder({required this.onLater});

  final VoidCallback onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canSave = ref.watch(backupFilesProvider).canSave;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.backup_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AccountsStrings.backupReminder,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onLater,
                  child: const Text(AccountsStrings.backupLater),
                ),
                if (canSave)
                  TextButton(
                    onPressed: () => openExportBackup(context),
                    child: const Text(AccountsStrings.backupNow),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
