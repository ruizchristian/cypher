import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/account.dart';
import '../shared/providers.dart';
import 'account_display.dart';
import 'accounts_strings.dart';

/// Lets the user rename an account. The secret and code settings are fixed at
/// creation and are not shown or editable here.
Future<void> showEditAccountSheet(BuildContext context, Account account) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditAccountSheet(account: account),
  );
}

/// Asks for confirmation, then deletes [account].
Future<void> confirmDeleteAccount(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(AccountsStrings.deleteTitle),
      content: Text(AccountsStrings.deleteBody(accountTitle(account))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text(AccountsStrings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: const Text(AccountsStrings.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(accountRepositoryProvider).delete(account.id);
  } on Exception {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AccountsStrings.saveFailed)));
  }
}

class _EditAccountSheet extends ConsumerStatefulWidget {
  const _EditAccountSheet({required this.account});

  final Account account;

  @override
  ConsumerState<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends ConsumerState<_EditAccountSheet> {
  late final TextEditingController _issuer = TextEditingController(
    text: widget.account.issuer,
  );
  late final TextEditingController _accountName = TextEditingController(
    text: widget.account.accountName,
  );
  bool _saving = false;

  @override
  void dispose() {
    _issuer.dispose();
    _accountName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .rename(
            widget.account.id,
            issuer: _issuer.text.trim(),
            accountName: _accountName.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AccountsStrings.saveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AccountsStrings.editTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _issuer,
            decoration: const InputDecoration(
              labelText: AccountsStrings.issuerLabel,
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            maxLength: 100,
          ),
          TextField(
            controller: _accountName,
            decoration: const InputDecoration(
              labelText: AccountsStrings.accountLabel,
            ),
            textInputAction: TextInputAction.done,
            autocorrect: false,
            maxLength: 200,
            onSubmitted: (_) => _saving ? null : _save(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text(AccountsStrings.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text(AccountsStrings.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
