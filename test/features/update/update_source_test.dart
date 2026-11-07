import 'package:cypher/features/update/update_source.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _asset(
  String name, {
  int size = 1000,
  String state = 'uploaded',
  String url = 'https://github.com/o/r/releases/download/v1/',
}) => {
  'name': name,
  'size': size,
  'state': state,
  'browser_download_url': '$url$name',
  'digest': 'sha256:ABCDEF',
};

Map<String, Object?> _release(
  List<Object?> assets, {
  bool draft = false,
  bool prerelease = false,
}) => {'draft': draft, 'prerelease': prerelease, 'assets': assets};

void main() {
  group('parseReleases', () {
    test('reads version, build, size and digest from the APK asset', () {
      final update = parseReleases([
        _release([
          _asset('notes.txt'),
          _asset('CypherAuth-1.0.1-26110707.apk', size: 5000),
        ]),
      ])!;
      expect(update.version, '1.0.1');
      expect(update.build, 26110707);
      expect(update.sizeBytes, 5000);
      expect(update.sha256, 'abcdef');
      expect(
        update.downloadUrl.path,
        endsWith('CypherAuth-1.0.1-26110707.apk'),
      );
    });

    test('counts pre-releases, which is how CypherAuth ships for now', () {
      final update = parseReleases([
        _release([_asset('CypherAuth-1.0.1-7.apk')], prerelease: true),
      ]);
      expect(update?.build, 7);
    });

    test('ignores drafts, non-https links and other apps\' APKs', () {
      expect(
        parseReleases([
          _release([_asset('CypherAuth-1.0.0-1.apk')], draft: true),
          _release([_asset('CypherAuth-1.0.0-2.apk', url: 'http://x/')]),
          _release([_asset('Muso-1.0.0-3.apk')]),
        ]),
        isNull,
      );
    });

    test('is null while CI has not finished attaching the APK', () {
      expect(parseReleases([_release([])]), isNull);
      expect(
        parseReleases([
          _release([_asset('CypherAuth-1.0.0-1.apk', state: 'starter')]),
        ]),
        isNull,
      );
    });

    test('picks the highest build across releases', () {
      final update = parseReleases([
        _release([_asset('CypherAuth-1.0.1-5.apk')]),
        _release([_asset('CypherAuth-1.0.2-9.apk')], prerelease: true),
        _release([_asset('CypherAuth-1.0.0-3.apk')]),
      ]);
      expect(update?.build, 9);
      expect(update?.version, '1.0.2');
    });

    test('skips malformed entries instead of failing', () {
      final update = parseReleases([
        'nonsense',
        {'assets': 'not a list'},
        _release([
          {'name': 'CypherAuth-1.0.0-4.apk'},
          _asset('CypherAuth-1.0.0-4.apk', size: 0),
          _asset('CypherAuth-1.0.0-6.apk'),
        ]),
      ]);
      expect(update?.build, 6);
    });
  });
}
