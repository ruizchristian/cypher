import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_platform.dart';
import 'update_source.dart';
import 'update_strings.dart';

enum UpdateStatus {
  unsupported,
  idle,
  checking,
  available,
  downloading,
  ready,
  error,
}

/// The app's one update checker, shared by the banner and Settings. Wired in
/// `main.dart`; widgets listen to it with a `ListenableBuilder`.
final updateControllerProvider = Provider<UpdateController>(
  (ref) =>
      throw UnimplementedError('updateControllerProvider must be overridden'),
);

/// How long before a foreground re-check. Switching apps every few seconds
/// should not send a request each time.
const _checkInterval = Duration(minutes: 15);

/// Finds new releases on GitHub, downloads the APK when asked and hands it to
/// Android's installer.
///
/// Nothing is downloaded until the user asks: an APK is tens of megabytes,
/// not a cost to run up on someone's mobile data in the background.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this._source,
    required this._platform,
    required this._now,
  });

  final UpdateSource _source;
  final UpdatePlatform _platform;
  final DateTime Function() _now;

  AppLifecycleListener? _lifecycle;
  bool _disposed = false;
  bool _checking = false;

  UpdateStatus _status = UpdateStatus.checking;
  InstalledVersion? _installed;
  AvailableUpdate? _update;
  File? _downloaded;
  double? _progress;
  String? _error;
  String? _notice;
  DateTime? _lastCheckedAt;

  /// Which build was dismissed, rather than a flag: "not this one, not now",
  /// so a newer release surfaces again on its own.
  int? _dismissedBuild;

  /// Set while the user is away granting "Install unknown apps", so coming
  /// back picks the install up again.
  bool _installOnResume = false;

  UpdateStatus get status => _status;
  InstalledVersion? get installed => _installed;
  AvailableUpdate? get update => _update;

  /// 0–1 while downloading, otherwise null.
  double? get progress => _progress;

  /// Generic, user-safe text; never the raw exception.
  String? get error => _error;

  /// Guidance that is not an error, such as what to do on the permission
  /// screen.
  String? get notice => _notice;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  bool get isBusy =>
      _status == UpdateStatus.checking || _status == UpdateStatus.downloading;

  /// Whether the banner shows. Checking and errors stay in Settings, where
  /// the user asked the question.
  bool get showBanner =>
      _update != null &&
      _update!.build != _dismissedBuild &&
      (_status == UpdateStatus.available ||
          _status == UpdateStatus.downloading ||
          _status == UpdateStatus.ready);

  Future<void> init() async {
    try {
      _installed = await _platform.installed();
    } on Object {
      _installed = null;
    }
    if (_installed == null) {
      _set(UpdateStatus.unsupported);
      return;
    }
    // Re-check on returning to the foreground rather than on a timer: a
    // backgrounded app has no reason to poll.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_onResume()));
    await _removeStaleDownloads();
    await checkNow();
  }

  /// Looks for a newer release. `force: false` is the throttled foreground
  /// re-check.
  Future<void> checkNow({bool force = true}) async {
    if (_status == UpdateStatus.unsupported ||
        _checking ||
        _status == UpdateStatus.downloading) {
      return;
    }
    final last = _lastCheckedAt;
    if (!force && last != null && _now().difference(last) < _checkInterval) {
      return;
    }

    _checking = true;
    _error = null;
    // With an update already on offer the re-check runs quietly, so the
    // banner does not blink away while it is in flight.
    if (_update == null) _set(UpdateStatus.checking);
    try {
      final latest = await _source.latest();
      _lastCheckedAt = _now();
      if (latest != null && latest.build > _installed!.build) {
        // A different build makes the earlier download worthless.
        if (_update?.build != latest.build) _downloaded = null;
        _update = latest;
        _downloaded ??= await _existingDownload(latest);
        _set(_downloaded != null ? UpdateStatus.ready : UpdateStatus.available);
      } else {
        _update = null;
        _downloaded = null;
        _set(UpdateStatus.idle);
      }
    } on Object {
      _error = UpdateStrings.checkFailed;
      // A failed re-check does not hide an update found earlier.
      _set(
        _update == null
            ? UpdateStatus.error
            : (_downloaded != null
                  ? UpdateStatus.ready
                  : UpdateStatus.available),
      );
    } finally {
      _checking = false;
    }
  }

  /// Downloads the update if needed, then opens Android's installer, which
  /// asks the user to confirm. Installing over the app keeps the vault: the
  /// update is signed with the same key.
  Future<void> install() async {
    final update = _update;
    if (update == null || isBusy) return;
    _error = null;
    _notice = null;

    if (_downloaded == null) {
      try {
        _downloaded = await _download(update);
      } on Object {
        _progress = null;
        _error = UpdateStrings.downloadFailed;
        _set(UpdateStatus.available);
        return;
      }
    }
    _progress = null;
    _set(UpdateStatus.ready);
    await _launchInstaller();
  }

  void dismiss() {
    _dismissedBuild = _update?.build;
    notifyListeners();
  }

  Future<void> _onResume() async {
    if (_installOnResume) {
      _installOnResume = false;
      if (_downloaded != null && await _canInstall()) {
        await _launchInstaller();
        return;
      }
    }
    await checkNow(force: false);
  }

  Future<void> _launchInstaller() async {
    final apk = _downloaded;
    if (apk == null) return;
    if (!await _canInstall()) {
      _installOnResume = true;
      _notice = UpdateStrings.allowInstalls;
      notifyListeners();
      await _platform.openInstallSettings();
      return;
    }
    _notice = null;
    bool opened;
    try {
      opened = await _platform.install(apk);
    } on Object {
      opened = false;
    }
    if (!opened) _error = UpdateStrings.installerFailed;
    notifyListeners();
  }

  Future<bool> _canInstall() async {
    try {
      return await _platform.canInstall();
    } on Object {
      return false;
    }
  }

  Future<Directory> _updatesDirectory() async =>
      Directory('${(await _platform.cacheDirectory()).path}/updates');

  File _fileFor(Directory directory, AvailableUpdate update) =>
      File('${directory.path}/CypherAuth-${update.build}.apk');

  Future<File> _download(AvailableUpdate update) async {
    final directory = await _updatesDirectory();
    await directory.create(recursive: true);
    final target = _fileFor(directory, update);
    // A temporary name, so a half-written file is never mistaken for a
    // finished one after the app is killed mid-download.
    final partial = File('${target.path}.part');

    _progress = 0;
    _set(UpdateStatus.downloading);
    var lastNotified = 0.0;
    try {
      await _source.download(update, partial, (received) {
        final value = (received / update.sizeBytes).clamp(0.0, 1.0);
        _progress = value;
        // One rebuild per percent is plenty for a progress bar.
        if (value - lastNotified >= 0.01) {
          lastNotified = value;
          notifyListeners();
        }
      });
      return await partial.rename(target.path);
    } on Object {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  /// A finished download from an earlier session, for example when the user
  /// backed out of the installer.
  Future<File?> _existingDownload(AvailableUpdate update) async {
    try {
      final file = _fileFor(await _updatesDirectory(), update);
      if (await file.exists() && await file.length() == update.sizeBytes) {
        return file;
      }
    } on Object {
      // An unreadable cache just means downloading again.
    }
    return null;
  }

  /// Deletes partial downloads and APKs for builds already installed.
  Future<void> _removeStaleDownloads() async {
    try {
      final directory = await _updatesDirectory();
      if (!await directory.exists()) return;
      final finished = RegExp(r'^CypherAuth-(\d+)\.apk$');
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final build = finished.firstMatch(entity.uri.pathSegments.last);
        if (build == null || int.parse(build.group(1)!) <= _installed!.build) {
          await entity.delete();
        }
      }
    } on Object {
      // Best effort: a leftover file costs space, not correctness.
    }
  }

  void _set(UpdateStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    super.dispose();
  }
}
