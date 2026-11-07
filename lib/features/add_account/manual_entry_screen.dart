import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/otp/manual_entry.dart';
import '../../core/otp/otp_types.dart';
import '../../data/account_repository.dart';
import '../shared/providers.dart';
import 'add_account_strings.dart';
import 'confirm_import_screen.dart';

String _errorText(ManualEntryError error) => switch (error) {
  ManualEntryError.nameMissing => AddAccountStrings.nameMissing,
  ManualEntryError.secretMissing => AddAccountStrings.secretMissing,
  ManualEntryError.secretInvalid => AddAccountStrings.secretInvalid,
  ManualEntryError.periodInvalid => AddAccountStrings.periodInvalid,
  ManualEntryError.counterInvalid => AddAccountStrings.counterInvalid,
};

/// Manual entry of a setup key, for when a QR code can't be scanned.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _issuer = TextEditingController();
  final _account = TextEditingController();
  final _secret = TextEditingController();
  final _period = TextEditingController(text: '30');
  final _counter = TextEditingController(text: '0');

  OtpType _type = OtpType.totp;
  HashAlgorithm _algorithm = HashAlgorithm.sha1;
  int _digits = 6;
  bool _showSecret = false;
  bool _saving = false;
  Map<ManualEntryField, ManualEntryError> _errors = const {};

  @override
  void dispose() {
    _secret.clear();
    for (final c in [_issuer, _account, _secret, _period, _counter]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final result = ManualEntry.validate(
      issuer: _issuer.text,
      accountName: _account.text,
      secret: _secret.text,
      type: _type,
      algorithm: _algorithm,
      digits: _digits,
      period: _period.text,
      counter: _counter.text,
    );
    switch (result) {
      case ManualEntryInvalid(:final errors):
        setState(() => _errors = errors);
      case ManualEntryValid(:final parameters):
        setState(() {
          _errors = const {};
          _saving = true;
        });
        final state = ref.read(vaultStateProvider).value;
        final duplicate =
            state is VaultUnlocked &&
            state.accounts.any((a) => a.isSameAs(parameters));
        if (duplicate) {
          // Route through the confirm screen, which explains the skip.
          replaceWithConfirm(context, [parameters]);
          return;
        }
        try {
          await ref.read(accountRepositoryProvider).add(parameters);
          if (!mounted) return;
          _secret.clear();
          finishAddFlow(context, AddAccountStrings.added(1));
        } on Exception {
          if (!mounted) return;
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AddAccountStrings.saveFailed)),
          );
        }
    }
  }

  String? _error(ManualEntryField field) {
    final error = _errors[field];
    return error == null ? null : _errorText(error);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(title: const Text(AddAccountStrings.manualTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _issuer,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: AddAccountStrings.issuerLabel,
              hintText: AddAccountStrings.issuerHint,
              errorText: _error(ManualEntryField.name),
            ),
          ),
          TextField(
            controller: _account,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: AddAccountStrings.accountLabel,
              hintText: AddAccountStrings.accountHint,
            ),
          ),
          // The secret: hidden by default and kept out of the keyboard's
          // suggestions and learning.
          TextField(
            controller: _secret,
            obscureText: !_showSecret,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: AddAccountStrings.secretLabel,
              errorText: _error(ManualEntryField.secret),
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: _showSecret
                    ? AddAccountStrings.hideSecret
                    : AddAccountStrings.showSecret,
                icon: Icon(
                  _showSecret ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _showSecret = !_showSecret),
              ),
            ),
          ),
          gap,
          Text(
            AddAccountStrings.typeLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<OtpType>(
            segments: const [
              ButtonSegment(
                value: OtpType.totp,
                label: Text(AddAccountStrings.timeBased),
              ),
              ButtonSegment(
                value: OtpType.hotp,
                label: Text(AddAccountStrings.counterBased),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.single),
          ),
          gap,
          ExpansionTile(
            title: const Text(AddAccountStrings.advanced),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              DropdownButtonFormField<HashAlgorithm>(
                initialValue: _algorithm,
                decoration: const InputDecoration(
                  labelText: AddAccountStrings.algorithmLabel,
                ),
                items: const [
                  DropdownMenuItem(
                    value: HashAlgorithm.sha1,
                    child: Text('SHA-1'),
                  ),
                  DropdownMenuItem(
                    value: HashAlgorithm.sha256,
                    child: Text('SHA-256'),
                  ),
                  DropdownMenuItem(
                    value: HashAlgorithm.sha512,
                    child: Text('SHA-512'),
                  ),
                ],
                onChanged: (v) => setState(() => _algorithm = v ?? _algorithm),
              ),
              gap,
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AddAccountStrings.digitsLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 6, label: Text('6')),
                    ButtonSegment(value: 8, label: Text('8')),
                  ],
                  selected: {_digits},
                  onSelectionChanged: (s) => setState(() => _digits = s.single),
                ),
              ),
              gap,
              if (_type == OtpType.totp)
                TextField(
                  controller: _period,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AddAccountStrings.periodLabel,
                    errorText: _error(ManualEntryField.period),
                  ),
                )
              else
                TextField(
                  controller: _counter,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AddAccountStrings.counterLabel,
                    errorText: _error(ManualEntryField.counter),
                  ),
                ),
            ],
          ),
          gap,
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text(AddAccountStrings.save),
          ),
        ],
      ),
    );
  }
}
