import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_controller.dart';
import 'update_strings.dart';

/// Update status in Settings, with a manual check and the install button.
class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final theme = Theme.of(context);
        final status = updates.status;
        if (status == UpdateStatus.unsupported) {
          return const ListTile(
            leading: Icon(Icons.system_update_outlined),
            title: Text(UpdateStrings.section),
            subtitle: Text(UpdateStrings.unsupported),
          );
        }

        final installed = updates.installed;
        final update = updates.update;
        final lastChecked = updates.lastCheckedAt;
        final lines = <String>[
          if (installed != null)
            UpdateStrings.installedVersion(installed.version, installed.build),
          if (update != null)
            UpdateStrings.availableVersion(update.version, update.build)
          else if (status == UpdateStatus.idle) ...[
            UpdateStrings.upToDate,
            if (lastChecked != null)
              UpdateStrings.lastChecked(lastChecked.toLocal()),
          ],
        ];
        final (label, installs) = switch (status) {
          UpdateStatus.checking => (UpdateStrings.checking, false),
          UpdateStatus.downloading => (
            UpdateStrings.downloadingDetail(
              updates.progress,
              update!.sizeBytes,
            ),
            true,
          ),
          UpdateStatus.ready => (UpdateStrings.installUpdate, true),
          UpdateStatus.available => (
            UpdateStrings.downloadAndInstall(update!.sizeBytes),
            true,
          ),
          _ => (UpdateStrings.checkNow, false),
        };
        final message = updates.error ?? updates.notice;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
              if (status == UpdateStatus.downloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: updates.progress),
              ],
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    color: updates.error != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (update != null) ...[
                const SizedBox(height: 4),
                Text(
                  UpdateStrings.keepsAccounts,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: updates.isBusy
                    ? null
                    : (installs ? updates.install : updates.checkNow),
                child: Text(label),
              ),
              const SizedBox(height: 12),
              Text(
                UpdateStrings.networkNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
