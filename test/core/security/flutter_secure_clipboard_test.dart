import 'package:cypher/core/security/platform/flutter_secure_clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('cypher/platform');

  group('Android', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('copies as sensitive, then clears after 30 s', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final clipboard = FlutterSecureClipboard();
      try {
        await clipboard.copyCode('287082');
        expect(calls.single.method, 'copySensitive');
        expect(calls.single.arguments, {'text': '287082'});

        await tester.pump(const Duration(seconds: 29));
        expect(calls, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(calls.last.method, 'clearIfUnchanged');
        expect(calls.last.arguments, {'text': '287082'});
      } finally {
        clipboard.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a new copy replaces the pending clear of the previous one', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final clipboard = FlutterSecureClipboard();
      try {
        await clipboard.copyCode('111111');
        await tester.pump(const Duration(seconds: 20));
        await clipboard.copyCode('222222');
        await tester.pump(const Duration(seconds: 30));

        final clears = calls.where((c) => c.method == 'clearIfUnchanged');
        expect(clears.map((c) => c.arguments), [
          {'text': '222222'},
        ]);
      } finally {
        clipboard.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('dispose cancels the pending clear', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final clipboard = FlutterSecureClipboard();
      try {
        await clipboard.copyCode('287082');
        clipboard.dispose();
        await tester.pump(const Duration(seconds: 31));
        expect(calls.map((c) => c.method), ['copySensitive']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('iOS', () {
    testWidgets('uses the Flutter clipboard and clears it after 30 s', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final writes = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            writes.add((call.arguments as Map)['text']);
          }
          return null;
        },
      );
      final clipboard = FlutterSecureClipboard();
      try {
        await clipboard.copyCode('287082');
        expect(writes, ['287082']);
        await tester.pump(const Duration(seconds: 30));
        expect(writes, ['287082', '']);
      } finally {
        clipboard.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
