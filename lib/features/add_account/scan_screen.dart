import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/providers.dart';
import 'add_account_strings.dart';
import 'confirm_import_screen.dart';
import 'payload_importer.dart';

/// Live camera scanning. The camera exists only while this screen does, and
/// scanning stops at the first complete result.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final PayloadImporter _importer = PayloadImporter();
  String? _lastText;
  String? _status;
  bool _done = false;
  bool _cameraUnavailable = false;

  void _onCode(String text) {
    // The scanner reports the same code repeatedly; only react to changes.
    // Frames are decoded asynchronously, so a result can arrive after the
    // screen is gone.
    if (!mounted || _done || text == _lastText) return;
    _lastText = text;
    switch (_importer.handle(text)) {
      case ImportReady(:final accounts):
        _done = true;
        replaceWithConfirm(context, accounts);
      case ImportNeedsMore(:final received, :final total):
        setState(
          () => _status = AddAccountStrings.partProgress(received, total),
        );
      case ImportRejected(:final problem):
        setState(() => _status = importProblemMessage(problem));
    }
  }

  void _onCameraUnavailable() {
    if (mounted) setState(() => _cameraUnavailable = true);
  }

  @override
  Widget build(BuildContext context) {
    final buildScanner = ref.watch(qrScannerBuilderProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AddAccountStrings.scanTitle)),
      body: _cameraUnavailable
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  AddAccountStrings.cameraUnavailable,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: buildScanner(
                    onCode: _onCode,
                    onCameraUnavailable: _onCameraUnavailable,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _status ?? AddAccountStrings.scanInstructions,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
