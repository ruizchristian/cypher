import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/otp/otp_parameters.dart';
import '../../core/otp/otp_types.dart';
import '../../data/account.dart';
import '../../data/account_repository.dart';
import '../shared/providers.dart';
import 'add_account_strings.dart';
import 'payload_importer.dart';

/// User-facing message for an [ImportProblem].
String importProblemMessage(ImportProblem problem) => switch (problem) {
  ImportProblem.notAnAccountCode => AddAccountStrings.notAnAccountCode,
  ImportProblem.invalidAccountCode => AddAccountStrings.invalidAccountCode,
  ImportProblem.unsupportedAlgorithm => AddAccountStrings.unsupportedAlgorithm,
  ImportProblem.tooManyAccounts => AddAccountStrings.tooManyAccounts,
};

/// Opens the confirmation step for [accounts], replacing the current route.
///
/// The accounts travel in the widget constructor, not in route arguments, so
/// secrets never enter RouteSettings, navigation logs or restoration data.
void replaceWithConfirm(BuildContext context, List<OtpParameters> accounts) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => ConfirmImportScreen(accounts: accounts),
    ),
  );
}

/// Pops back to the account list and reports [message] there.
void finishAddFlow(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).popUntil((route) => route.isFirst);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Shows what will be added (names and types only, never secrets), skips
/// accounts already in the vault, and saves the rest in one write.
class ConfirmImportScreen extends ConsumerStatefulWidget {
  const ConfirmImportScreen({super.key, required this.accounts});

  final List<OtpParameters> accounts;

  @override
  ConsumerState<ConfirmImportScreen> createState() =>
      _ConfirmImportScreenState();
}

/// The accounts to add after skipping those already in the vault or repeated
/// earlier in the same import.
final class _ImportPlan {
  factory _ImportPlan(List<OtpParameters> candidates, List<Account> existing) {
    final toAdd = <OtpParameters>[];
    for (final candidate in candidates) {
      final known =
          existing.any((a) => a.isSameAs(candidate)) ||
          toAdd.any((p) => p.isSameAs(candidate));
      if (!known) toAdd.add(candidate);
    }
    return _ImportPlan._(toAdd, candidates.length - toAdd.length);
  }

  const _ImportPlan._(this.toAdd, this.duplicates);

  final List<OtpParameters> toAdd;
  final int duplicates;
}

class _ConfirmImportScreenState extends ConsumerState<ConfirmImportScreen> {
  /// The plan being saved, or `null` when idle. Held so the screen keeps
  /// showing it while it closes, instead of re-planning against a vault
  /// that now contains these accounts.
  _ImportPlan? _saving;

  Future<void> _save(_ImportPlan plan) async {
    setState(() => _saving = plan);
    try {
      await ref.read(accountRepositoryProvider).addAll(plan.toAdd);
      if (!mounted) return;
      finishAddFlow(context, AddAccountStrings.added(plan.toAdd.length));
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AddAccountStrings.saveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultStateProvider).value;
    final plan =
        _saving ??
        _ImportPlan(
          widget.accounts,
          state is VaultUnlocked ? state.accounts : const [],
        );
    final _ImportPlan(:toAdd, :duplicates) = plan;

    return Scaffold(
      appBar: AppBar(title: const Text(AddAccountStrings.confirmTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (duplicates > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                toAdd.isEmpty
                    ? AddAccountStrings.allDuplicates
                    : AddAccountStrings.duplicatesSkipped(duplicates),
              ),
            ),
          for (final p in toAdd)
            ListTile(
              leading: Icon(
                p.type == OtpType.totp ? Icons.schedule : Icons.pin_outlined,
              ),
              title: Text(
                p.issuer.isNotEmpty ? p.issuer : p.accountName,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (p.issuer.isNotEmpty && p.accountName.isNotEmpty)
                    p.accountName,
                  p.type == OtpType.totp
                      ? AddAccountStrings.timeBasedShort
                      : AddAccountStrings.counterBasedShort,
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: toAdd.isEmpty
              ? OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(AddAccountStrings.done),
                )
              : FilledButton(
                  onPressed: _saving != null ? null : () => _save(plan),
                  child: Text(AddAccountStrings.confirmAdd(toAdd.length)),
                ),
        ),
      ),
    );
  }
}
