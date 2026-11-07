import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/account.dart';
import '../../data/account_repository.dart';
import '../shared/providers.dart';
import 'account_tile.dart';
import 'accounts_strings.dart';
import 'vault_unreadable_view.dart';

/// Home screen: the account list.
///
/// Until the lock screen exists (M5), this screen opens the vault itself when
/// it is locked. M5 moves unlocking behind the PIN/biometric gate.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  bool _unlockFailed = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _unlock();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    try {
      await ref.read(accountRepositoryProvider).unlock();
    } on Exception {
      if (mounted) setState(() => _unlockFailed = true);
    }
  }

  void _setSearching(bool searching) {
    setState(() {
      _searching = searching;
      if (!searching) _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultStateProvider).value;
    final accounts = state is VaultUnlocked ? state.accounts : null;

    return Scaffold(
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
        ],
      ),
      body: switch (state) {
        _ when _unlockFailed => const _Message(
          icon: Icons.error_outline,
          title: AccountsStrings.loadFailed,
        ),
        VaultUnreadable(:final reason) => VaultUnreadableView(reason: reason),
        VaultUnlocked(:final accounts) when accounts.isEmpty => const _Message(
          icon: Icons.shield_outlined,
          title: AccountsStrings.emptyTitle,
          body: AccountsStrings.emptyBody,
        ),
        VaultUnlocked(:final accounts) => _AccountList(
          accounts: accounts,
          query: _searching ? _search.text.trim() : '',
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
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: accounts.length,
      onReorderItem: (from, to) => _reorder(context, ref, from, to),
      itemBuilder: (_, i) => AccountTile(
        key: ValueKey(accounts[i].id),
        account: accounts[i],
        dragIndex: i,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.body});

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
            Icon(icon, size: 64, color: theme.colorScheme.primary),
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
