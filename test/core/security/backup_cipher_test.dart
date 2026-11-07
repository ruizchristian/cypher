import 'dart:convert';
import 'dart:typed_data';

import 'package:cypher/core/security/backup_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

const _cheap = BackupKdfParams.pbkdf2(iterations: 1);
const _password = 'correct horse battery staple';

Matcher _fails(BackupFailure reason) => throwsA(
  isA<BackupDecryptException>().having((e) => e.reason, 'reason', reason),
);

Future<Uint8List> _seal(List<int> clear, {String password = _password}) =>
    BackupCipher.encrypt(clear, password, params: _cheap, inIsolate: false);

Future<Uint8List> _open(Uint8List file, {String password = _password}) =>
    BackupCipher.decrypt(file, password, inIsolate: false);

void main() {
  final clear = utf8.encode('{"schema":1,"accounts":[]}');

  test('round-trips', () async {
    expect(await _open(await _seal(clear)), clear);
  });

  test('the real Argon2id default works on an isolate', () async {
    final file = await BackupCipher.encrypt(clear, _password);
    expect(file[7], BackupKdf.argon2id.id);
    final view = ByteData.sublistView(file);
    expect(
      (view.getUint32(8), view.getUint32(12), view.getUint32(16)),
      (64 * 1024, 3, 1),
    );
    expect(await BackupCipher.decrypt(file, _password), clear);
  });

  test('writes the documented layout', () async {
    final file = await _seal(clear);
    expect(ascii.decode(file.sublist(0, 6)), 'CYPHER');
    expect(file[6], 1); // format version
    expect(file[7], BackupKdf.pbkdf2Sha256.id);
    expect(ByteData.sublistView(file).getUint32(8), 1);
    expect(file.length, BackupCipher.headerLength + clear.length + 16);
    expect(utf8.decode(file, allowMalformed: true), isNot(contains('schema')));
  });

  test('fresh salt and nonce every time', () async {
    final a = await _seal(clear);
    final b = await _seal(clear);
    expect(a.sublist(20, 48), isNot(b.sublist(20, 48)));
  });

  test('a wrong password and a damaged file give the same error', () async {
    final file = await _seal(clear);
    expect(
      _open(file, password: 'wrong password!'),
      _fails(BackupFailure.wrongPasswordOrDamaged),
    );
    final damaged = Uint8List.fromList(file)..[60] ^= 1;
    expect(_open(damaged), _fails(BackupFailure.wrongPasswordOrDamaged));
  });

  test('every byte after the version is protected', () async {
    final file = await _seal(clear);
    for (var i = 8; i < file.length; i++) {
      if (i >= 8 && i < 12) continue; // PBKDF2 iterations: see the next test
      final tampered = Uint8List.fromList(file)..[i] ^= 0x01;
      await expectLater(
        _open(tampered),
        _fails(BackupFailure.wrongPasswordOrDamaged),
        reason: 'byte $i',
      );
    }
  });

  test('a changed iteration count also fails (it is authenticated)', () async {
    final file = await _seal(clear);
    final view = ByteData.sublistView(file);
    view.setUint32(8, 2);
    expect(_open(file), _fails(BackupFailure.wrongPasswordOrDamaged));
  });

  test('rejects other files, newer versions and oversized input', () async {
    final file = await _seal(clear);
    expect(
      _open(Uint8List.fromList(file)..[0] = 0x58),
      _fails(BackupFailure.notABackup),
    );
    expect(
      _open(Uint8List.fromList(file)..[6] = 2),
      _fails(BackupFailure.unsupportedVersion),
    );
    expect(_open(Uint8List(10)), _fails(BackupFailure.notABackup));
    expect(
      _open(Uint8List(BackupCipher.maxFileBytes + 1)),
      _fails(BackupFailure.tooLarge),
    );
  });

  group('hostile headers are refused before any work', () {
    Uint8List withArgon(int memory, int iterations, int parallelism) {
      final header = Uint8List(BackupCipher.headerLength + 32)
        ..setAll(0, BackupCipher.magic)
        ..[6] = 1
        ..[7] = BackupKdf.argon2id.id;
      ByteData.sublistView(header)
        ..setUint32(8, memory)
        ..setUint32(12, iterations)
        ..setUint32(16, parallelism);
      return header;
    }

    test('Argon2id costs outside the bounds', () async {
      for (final (m, t, p) in [
        (4 * 1024 * 1024, 3, 1), // 4 GiB of memory
        (65536, 1000, 1), // 1000 passes
        (65536, 3, 64), // 64 lanes
        (0, 3, 1),
        (65536, 0, 1),
        (16, 3, 4), // less than 8 KiB per lane
      ]) {
        final sw = Stopwatch()..start();
        await expectLater(
          _open(withArgon(m, t, p)),
          _fails(BackupFailure.unsafeParameters),
          reason: '($m, $t, $p)',
        );
        expect(sw.elapsedMilliseconds, lessThan(500), reason: 'no KDF ran');
      }
    });

    test('PBKDF2 iterations outside the bounds', () async {
      final file = await _seal(clear);
      ByteData.sublistView(file).setUint32(8, 0xFFFFFFFF);
      expect(_open(file), _fails(BackupFailure.unsafeParameters));
    });
  });

  test('password policy: at least 10 characters', () {
    expect(BackupPassword.isAcceptable('123456789'), isFalse);
    expect(BackupPassword.isAcceptable('1234567890'), isTrue);
    expect(BackupPassword.isAcceptable('ẞüßéàçøñ✓€'), isTrue); // 10 runes
  });

  test('the exception carries no data', () {
    expect(
      const BackupDecryptException(BackupFailure.wrongPasswordOrDamaged)
          .toString(),
      'BackupDecryptException(wrongPasswordOrDamaged)',
    );
  });
}
