import 'dart:io';

import 'package:cypher/features/update/update_platform.dart';
import 'package:cypher/features/update/update_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_updates.dart';
import '../../helpers/app_harness.dart';

void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('cypher-update-ui');
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  /// A release build with update 1.0.1 (build 200) published.
  AppHarness withUpdate() {
    final harness = AppHarness();
    harness.updatePlatform
      ..cache = cache
      ..version = const InstalledVersion(version: '1.0.0', build: 100);
    harness.updateSource.latestRelease = fakeUpdate(200, size: 3 * 1048576);
    return harness;
  }

  testWidgets('the account list shows the update and "Not now" hides it', (
    tester,
  ) async {
    final harness = withUpdate();
    await harness.seed([totpAccount('GitHub')]);
    await harness.pump(tester);

    expect(find.text(UpdateStrings.available), findsOneWidget);
    expect(find.text('CypherAuth 1.0.1 · 3.0 MB'), findsOneWidget);

    await tester.tap(find.text(UpdateStrings.later));
    await tester.pump();
    expect(find.text(UpdateStrings.available), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('the update shows before any account is added', (tester) async {
    final harness = withUpdate();
    await harness.pump(tester);

    expect(find.text(UpdateStrings.available), findsOneWidget);
    expect(find.text('No accounts yet'), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('Install downloads the APK and opens the installer', (
    tester,
  ) async {
    final harness = withUpdate();
    harness.updateSource.latestRelease = fakeUpdate(200);
    await harness.seed([totpAccount('GitHub')]);
    await harness.pump(tester);

    await tester.runAsync(harness.updates.install);
    await tester.pump();
    expect(harness.updatePlatform.installs.single, endsWith('-200.apk'));
    expect(find.text(UpdateStrings.ready), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('nothing shows, and nothing is checked, in debug builds', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.seed([totpAccount('GitHub')]);
    await harness.pump(tester);

    expect(find.text(UpdateStrings.available), findsNothing);
    expect(harness.updateSource.checks, 0);
    await harness.unmount(tester);
  });

  testWidgets('Settings offers the download and explains the network use', (
    tester,
  ) async {
    final harness = withUpdate();
    await harness.pump(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(UpdateStrings.networkNote), 200);
    expect(find.text('Installed: 1.0.0 (100)'), findsOneWidget);
    expect(find.text('Available: 1.0.1 (200)'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Download and install (3.0 MB)'),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });
}
