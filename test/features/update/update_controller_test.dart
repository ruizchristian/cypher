import 'dart:io';

import 'package:cypher/features/update/update_controller.dart';
import 'package:cypher/features/update/update_strings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cache;
  late FakeUpdateSource source;
  late FakeUpdatePlatform platform;
  late FakeClock clock;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('cypher-update-test');
    source = FakeUpdateSource();
    platform = FakeUpdatePlatform(cache);
    clock = FakeClock.atUnixSeconds(1000);
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  Future<UpdateController> started() async {
    final updates = UpdateController(
      source: source,
      platform: platform,
      now: clock.now,
    );
    addTearDown(updates.dispose);
    await updates.init();
    return updates;
  }

  test('is unsupported, and never checks, where it cannot update', () async {
    platform.version = null;
    final updates = await started();
    expect(updates.status, UpdateStatus.unsupported);
    expect(source.checks, 0);
  });

  test('reports up to date when the release is not newer', () async {
    source.latestRelease = fakeUpdate(100);
    final updates = await started();
    expect(updates.status, UpdateStatus.idle);
    expect(updates.showBanner, isFalse);
  });

  test('offers a newer build, downloads it and opens the installer', () async {
    source.latestRelease = fakeUpdate(200);
    final updates = await started();
    expect(updates.status, UpdateStatus.available);
    expect(updates.showBanner, isTrue);

    await updates.install();
    expect(updates.status, UpdateStatus.ready);
    expect(platform.installs.single, endsWith('CypherAuth-200.apk'));
    expect(File(platform.installs.single).lengthSync(), 64);
  });

  test('reuses a finished download from an earlier session', () async {
    source.latestRelease = fakeUpdate(200);
    await Directory('${cache.path}/updates').create();
    await File('${cache.path}/updates/CypherAuth-200.apk')
        .writeAsBytes(List.filled(64, 1));

    final updates = await started();
    expect(updates.status, UpdateStatus.ready);
    await updates.install();
    expect(source.downloads, 0);
    expect(platform.installs, hasLength(1));
  });

  test('sends the user to allow installs when not yet allowed', () async {
    source.latestRelease = fakeUpdate(200);
    platform.allowed = false;
    final updates = await started();
    await updates.install();
    expect(platform.settingsOpened, 1);
    expect(platform.installs, isEmpty);
    expect(updates.notice, UpdateStrings.allowInstalls);
  });

  test('a failed download keeps the update on offer, generically', () async {
    source.latestRelease = fakeUpdate(200);
    source.downloadError = const SocketException('offline at 10.0.0.1');
    final updates = await started();
    await updates.install();
    expect(updates.status, UpdateStatus.available);
    expect(updates.error, UpdateStrings.downloadFailed);
    expect(Directory('${cache.path}/updates').listSync(), isEmpty);
  });

  test('a failed check does not hide an update found earlier', () async {
    source.checkError = const SocketException('offline');
    final updates = await started();
    expect(updates.status, UpdateStatus.error);
    expect(updates.error, UpdateStrings.checkFailed);

    source
      ..checkError = null
      ..latestRelease = fakeUpdate(200);
    await updates.checkNow();
    source.checkError = const SocketException('offline');
    await updates.checkNow();
    expect(updates.status, UpdateStatus.available);
  });

  test('foreground re-checks are throttled; manual ones are not', () async {
    source.latestRelease = fakeUpdate(100);
    final updates = await started();
    expect(source.checks, 1);

    await updates.checkNow(force: false);
    expect(source.checks, 1);
    clock.advance(const Duration(minutes: 16));
    await updates.checkNow(force: false);
    expect(source.checks, 2);
    await updates.checkNow();
    expect(source.checks, 3);
  });

  test('dismissing hides this build only', () async {
    source.latestRelease = fakeUpdate(200);
    final updates = await started();
    updates.dismiss();
    expect(updates.showBanner, isFalse);

    source.latestRelease = fakeUpdate(300);
    await updates.checkNow();
    expect(updates.showBanner, isTrue);
  });

  test('cleans out partial downloads and installed builds', () async {
    final dir = await Directory('${cache.path}/updates').create();
    await File('${dir.path}/CypherAuth-100.apk').writeAsString('old');
    await File('${dir.path}/CypherAuth-300.apk.part').writeAsString('partial');
    await File('${dir.path}/CypherAuth-300.apk').writeAsString('newer');

    await started();
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, ['CypherAuth-300.apk']);
  });
}
