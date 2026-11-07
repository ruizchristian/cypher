import 'dart:io';

import 'package:cypher/features/update/update_platform.dart';
import 'package:cypher/features/update/update_source.dart';

/// Release lookups and downloads without a network.
final class FakeUpdateSource implements UpdateSource {
  AvailableUpdate? latestRelease;
  Object? checkError;
  Object? downloadError;
  int checks = 0;
  int downloads = 0;

  @override
  Future<AvailableUpdate?> latest() async {
    checks++;
    if (checkError case final error?) throw error;
    return latestRelease;
  }

  @override
  Future<void> download(
    AvailableUpdate update,
    File destination,
    void Function(int received) onProgress,
  ) async {
    downloads++;
    if (downloadError case final error?) throw error;
    await destination.writeAsBytes(List.filled(update.sizeBytes, 7));
    onProgress(update.sizeBytes);
  }
}

/// The installed build and Android's installer, recorded instead of run.
final class FakeUpdatePlatform implements UpdatePlatform {
  FakeUpdatePlatform(this.cache);

  Directory? cache;

  /// Null means unsupported, like a debug build.
  InstalledVersion? version = const InstalledVersion(
    version: '1.0.0',
    build: 100,
  );
  bool allowed = true;
  int settingsOpened = 0;
  final List<String> installs = [];

  @override
  Future<InstalledVersion?> installed() async => version;

  @override
  Future<Directory> cacheDirectory() async => cache!;

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<bool> install(File apk) async {
    installs.add(apk.path);
    return true;
  }
}

AvailableUpdate fakeUpdate(int build, {int size = 64}) => AvailableUpdate(
  version: '1.0.1',
  build: build,
  downloadUrl: Uri.parse('https://example.com/CypherAuth-1.0.1-$build.apk'),
  sizeBytes: size,
);
