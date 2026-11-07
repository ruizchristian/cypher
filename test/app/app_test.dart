import 'package:cypher/features/accounts/accounts_screen.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

Brightness _screenBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(AccountsScreen))).brightness;

void main() {
  group('CypherApp', () {
    testWidgets('first launch opens an empty vault on the accounts screen', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);

      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(find.text(AccountsStrings.emptyTitle), findsOneWidget);
      expect(app.secrets.values, hasLength(1)); // vault key created
      expect(app.files.data, isNotNull); // encrypted vault written
      await app.unmount(tester);
    });

    testWidgets('uses the light theme when the platform is light', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = AppHarness();
      await app.pump(tester);
      expect(_screenBrightness(tester), Brightness.light);
      await app.unmount(tester);
    });

    testWidgets('follows the platform into dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = AppHarness();
      await app.pump(tester);
      expect(_screenBrightness(tester), Brightness.dark);
      await app.unmount(tester);
    });
  });
}
