import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/providers.dart';
import 'add_account_strings.dart';
import 'confirm_import_screen.dart';
import 'payload_importer.dart';

/// Reads a QR code from a picked image. Stays open across picks so a
/// multi-part export can be assembled from several screenshots.
class ImageImportScreen extends ConsumerStatefulWidget {
  const ImageImportScreen({super.key});

  @override
  ConsumerState<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends ConsumerState<ImageImportScreen> {
  final PayloadImporter _importer = PayloadImporter();
  String? _status;
  bool _busy = false;

  Future<void> _pick() async {
    final reader = ref.read(qrImageReaderProvider);
    setState(() => _busy = true);
    String? text;
    try {
      text = await reader.pickAndRead();
    } on Exception {
      text = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (text == null) {
      if (!reader.lastPickCancelled) {
        setState(() => _status = AddAccountStrings.noCodeInImage);
      }
      return;
    }
    switch (_importer.handle(text)) {
      case ImportReady(:final accounts):
        replaceWithConfirm(context, accounts);
      case ImportNeedsMore(:final received, :final total):
        setState(
          () => _status = AddAccountStrings.imagePartProgress(received, total),
        );
      case ImportRejected(:final problem):
        setState(() => _status = importProblemMessage(problem));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AddAccountStrings.imageTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  _status ?? AddAccountStrings.imageInstructions,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text(AddAccountStrings.chooseImageButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
