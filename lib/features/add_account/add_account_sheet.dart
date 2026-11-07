import 'package:flutter/material.dart';

import 'add_account_strings.dart';
import 'image_import_screen.dart';
import 'manual_entry_screen.dart';
import 'paste_link_screen.dart';
import 'scan_screen.dart';

/// The four ways to add an account.
Future<void> showAddAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void open(Widget screen) {
        Navigator.of(sheetContext).pop();
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text(AddAccountStrings.scanQr),
              subtitle: const Text(AddAccountStrings.scanQrHint),
              onTap: () => open(const ScanScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text(AddAccountStrings.chooseImage),
              subtitle: const Text(AddAccountStrings.chooseImageHint),
              onTap: () => open(const ImageImportScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text(AddAccountStrings.enterManually),
              subtitle: const Text(AddAccountStrings.enterManuallyHint),
              onTap: () => open(const ManualEntryScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text(AddAccountStrings.pasteLink),
              subtitle: const Text(AddAccountStrings.pasteLinkHint),
              onTap: () => open(const PasteLinkScreen()),
            ),
          ],
        ),
      );
    },
  );
}
