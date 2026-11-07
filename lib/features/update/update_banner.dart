import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_controller.dart';
import 'update_strings.dart';

/// A card above the account list when a newer build is out.
///
/// A card rather than a dialog: the user opened the app for a code, and an
/// update is never urgent enough to stand between them and it.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final update = updates.update;
        if (!updates.showBanner || update == null) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final (title, detail) = switch (updates.status) {
          UpdateStatus.downloading => (
            UpdateStrings.downloading,
            UpdateStrings.downloadingDetail(updates.progress, update.sizeBytes),
          ),
          UpdateStatus.ready => (
            UpdateStrings.ready,
            UpdateStrings.readyDetail(update.version),
          ),
          _ => (
            UpdateStrings.available,
            UpdateStrings.availableDetail(update.version, update.sizeBytes),
          ),
        };
        final message = updates.error ?? updates.notice;
        final onColor = TextStyle(color: scheme.onSecondaryContainer);

        // Announced in passing rather than by moving focus.
        return Semantics(
          liveRegion: true,
          child: Card(
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
                      Icon(
                        Icons.system_update_outlined,
                        color: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(detail, style: onColor),
                            if (message != null) ...[
                              const SizedBox(height: 4),
                              Text(message, style: onColor),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (updates.status == UpdateStatus.downloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: LinearProgressIndicator(value: updates.progress),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: updates.dismiss,
                        child: const Text(UpdateStrings.later),
                      ),
                      TextButton(
                        onPressed: updates.isBusy ? null : updates.install,
                        child: const Text(UpdateStrings.install),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
