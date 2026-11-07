import 'package:cypher/app/app.dart';
import 'package:cypher/features/accounts/accounts_screen.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: CypherApp()));
  await tester.pumpAndSettle();
}

Brightness _screenBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(AccountsScreen))).brightness;

void main() {
  group('CypherApp', () {
    testWidgets('launches on the accounts screen showing the empty state', (
      tester,
    ) async {
      await _pumpApp(tester);

      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(find.text(AccountsStrings.emptyTitle), findsOneWidget);
      expect(find.text(AccountsStrings.emptyBody), findsOneWidget);
    });

    testWidgets('uses the light theme when the platform is light', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpApp(tester);

      expect(_screenBrightness(tester), Brightness.light);
    });

    testWidgets('follows the platform into dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpApp(tester);

      expect(_screenBrightness(tester), Brightness.dark);
    });
  });
}
