// Offline/security guard for Cypher.
//
// Usage (from anywhere): dart .claude/skills/verify/scripts/guard.dart
// Exit code 1 if any ERROR is reported. Uses only dart:io so it runs
// without `pub get`.
import 'dart:io';

final _errors = <String>[];
final _warnings = <String>[];
final _todos = <String>[];

late final Directory _root;

void main() {
  // scripts/ -> verify/ -> skills/ -> .claude/ -> repo root
  _root = Directory.fromUri(Platform.script.resolve('../../../../'));
  if (!File(_path('pubspec.yaml')).existsSync()) {
    stderr.writeln('guard: could not locate repo root from ${Platform.script}');
    exit(2);
  }

  _checkAndroidManifest();
  _checkMacosEntitlements();
  _checkDependencies();
  _checkPureDartCore();
  _checkLogging();
  _checkPlatformHardening();

  for (final e in _errors) {
    stdout.writeln('ERROR $e');
  }
  for (final w in _warnings) {
    stdout.writeln('WARN  $w');
  }
  for (final t in _todos) {
    stdout.writeln('TODO  $t');
  }
  stdout.writeln(
    _errors.isEmpty
        ? 'guard: pass (${_warnings.length} warnings, ${_todos.length} todos)'
        : 'guard: FAIL (${_errors.length} errors)',
  );
  exit(_errors.isEmpty ? 0 : 1);
}

String _path(String relative) => _root.uri.resolve(relative).toFilePath();

String? _read(String relative) {
  final file = File(_path(relative));
  return file.existsSync() ? file.readAsStringSync() : null;
}

void _checkAndroidManifest() {
  const manifest = 'android/app/src/main/AndroidManifest.xml';
  final text = _read(manifest);
  if (text == null) {
    _warnings.add('$manifest not found');
    return;
  }
  for (final permission in const [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
  ]) {
    if (text.contains(permission)) {
      _errors.add('$manifest declares $permission (release must be offline)');
    }
  }
}

void _checkMacosEntitlements() {
  const entitlements = 'macos/Runner/Release.entitlements';
  final text = _read(entitlements);
  if (text != null && text.contains('com.apple.security.network.')) {
    _errors.add('$entitlements enables a network entitlement');
  }
}

void _checkDependencies() {
  final lock = _read('pubspec.lock');
  if (lock == null) {
    _warnings.add('pubspec.lock not found; run flutter pub get');
    return;
  }
  // Top-level package names in pubspec.lock are indented by exactly 2 spaces.
  final names = RegExp(
    r'^  ([a-z0-9_]+):\s*$',
    multiLine: true,
  ).allMatches(lock).map((m) => m.group(1)!).toSet();
  final denied = RegExp(
    r'^(firebase_.*|cloud_firestore|.*crashlytics.*|sentry.*|bugsnag.*|'
    r'datadog.*|amplitude.*|mixpanel.*|posthog.*|segment.*|appcenter.*|'
    r'google_mobile_ads|.*_ads|.*analytics.*|.*telemetry.*)$',
  );
  for (final name in names.where(denied.hasMatch)) {
    _errors.add('pubspec.lock contains denylisted package "$name"');
  }

  final pubspec = _read('pubspec.yaml') ?? '';
  for (final client in const ['http', 'dio', 'web_socket_channel']) {
    if (RegExp('^  $client:', multiLine: true).hasMatch(pubspec)) {
      _warnings.add(
        'pubspec.yaml depends directly on network client "$client"',
      );
    }
  }
}

Iterable<File> _dartFiles(String relativeDir) {
  final dir = Directory(_path(relativeDir));
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
}

String _rel(File f) => f.uri
    .toFilePath()
    .substring(_root.uri.toFilePath().length)
    .replaceAll(r'\', '/');

void _checkPureDartCore() {
  final flutterImport = RegExp(
    r'''^\s*(import|export)\s+['"]package:flutter''',
    multiLine: true,
  );
  for (final file in _dartFiles('lib/core/otp')) {
    if (flutterImport.hasMatch(file.readAsStringSync())) {
      _errors.add(
        '${_rel(file)} imports Flutter; lib/core/otp must be pure Dart',
      );
    }
  }
}

void _checkLogging() {
  final printCall = RegExp(r'(^|[^\w.])print\(');
  final debugPrintCall = RegExp(r'\bdebugPrint\(');
  final devLog = RegExp(r'''import\s+['"]dart:developer['"]''');
  for (final file in _dartFiles('lib')) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      final where = '${_rel(file)}:${i + 1}';
      if (printCall.hasMatch(line)) {
        _errors.add('$where uses print(); never log in lib/');
      } else if (debugPrintCall.hasMatch(line)) {
        _warnings.add(
          '$where uses debugPrint(); confirm no secret or account data',
        );
      }
    }
    if (devLog.hasMatch(lines.join('\n'))) {
      _warnings.add(
        '${_rel(file)} imports dart:developer; confirm log() output is non-sensitive',
      );
    }
  }
}

void _checkPlatformHardening() {
  final activityDir = Directory(_path('android/app/src/main/kotlin'));
  if (activityDir.existsSync()) {
    final activities = activityDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('MainActivity.kt'));
    if (!activities.any((f) => f.readAsStringSync().contains('FLAG_SECURE'))) {
      _todos.add(
        'FLAG_SECURE not set in MainActivity (screenshots/recents not blocked)',
      );
    }
  }
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  if (manifest != null &&
      !manifest.contains('android:allowBackup="false"') &&
      !manifest.contains('android:dataExtractionRules')) {
    _todos.add(
      'Android Auto Backup not disabled (allowBackup / dataExtractionRules)',
    );
  }
}
