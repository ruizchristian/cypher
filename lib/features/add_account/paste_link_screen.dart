import 'package:flutter/material.dart';

import 'add_account_strings.dart';
import 'confirm_import_screen.dart';
import 'payload_importer.dart';

/// Accepts a pasted `otpauth://` or `otpauth-migration://` link. The text
/// field is the only clipboard access: Cypher never reads the clipboard on
/// its own.
class PasteLinkScreen extends StatefulWidget {
  const PasteLinkScreen({super.key});

  @override
  State<PasteLinkScreen> createState() => _PasteLinkScreenState();
}

class _PasteLinkScreenState extends State<PasteLinkScreen> {
  final TextEditingController _link = TextEditingController();
  final PayloadImporter _importer = PayloadImporter();
  String? _error;

  @override
  void dispose() {
    _link.clear();
    _link.dispose();
    super.dispose();
  }

  void _continue() {
    switch (_importer.handle(_link.text)) {
      case ImportReady(:final accounts):
        _link.clear();
        replaceWithConfirm(context, accounts);
      case ImportNeedsMore(:final received, :final total):
        _link.clear();
        setState(
          () => _error = AddAccountStrings.pasteNeedsMore(received, total),
        );
      case ImportRejected(:final problem):
        setState(() => _error = importProblemMessage(problem));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AddAccountStrings.pasteTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _link,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: AddAccountStrings.pasteLabel,
              hintText: AddAccountStrings.pasteHint,
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _continue,
            child: const Text(AddAccountStrings.continueLabel),
          ),
        ],
      ),
    );
  }
}
