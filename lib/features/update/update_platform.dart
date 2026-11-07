import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The build that is running now.
final class InstalledVersion {
  const InstalledVersion({required this.version, required this.build});

  final String version;

  /// Android versionCode. A release is an update only when its build is
  /// higher.
  final int build;
}

/// What the updater needs from the OS. Narrow so the controller can be tested
/// with a fake.
abstract interface class UpdatePlatform {
  /// Null where in-app updates are not supported: anything but an Android
  /// release build.
  Future<InstalledVersion?> installed();

  /// App-private cache directory. Only `<cache>/updates` is shared with the
  /// installer.
  Future<Directory> cacheDirectory();

  /// Whether the user has allowed CypherAuth to install apps.
  Future<bool> canInstall();

  /// Opens the system screen where that permission is granted.
  Future<void> openInstallSettings();

  /// Hands the APK to Android's installer. False if it could not be opened.
  Future<bool> install(File apk);
}

final class AndroidUpdatePlatform implements UpdatePlatform {
  const AndroidUpdatePlatform();

  static const _channel = MethodChannel('cypher/updates');

  @override
  Future<InstalledVersion?> installed() async {
    // Debug builds are signed with the debug key, so Android would refuse a
    // release APK over them; offering one would only end in an installer
    // error.
    if (!Platform.isAndroid || !kReleaseMode) return null;
    final info = await _channel.invokeMapMethod<String, Object?>(
      'installedVersion',
    );
    final build = info?['build'];
    if (build is! int) return null;
    return InstalledVersion(version: '${info?['version'] ?? ''}', build: build);
  }

  @override
  Future<Directory> cacheDirectory() async =>
      Directory((await _channel.invokeMethod<String>('cacheDirectory'))!);

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<bool> install(File apk) async =>
      await _channel.invokeMethod<bool>('install', {'path': apk.path}) ?? false;
}
