import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  group('biometrics toggle', () {
    testWidgets('can still be turned off after the sensor goes away', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await app.lock.setBiometricsEnabled(true, reason: 'r');
      app.biometrics.available = false; // e.g. fingerprints removed
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AccountsStrings.settings));
      await tester.pumpAndSettle();

      final toggle = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(app.lock.settings.biometricsEnabled, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      await app.unmount(tester);
    });
  });
}
