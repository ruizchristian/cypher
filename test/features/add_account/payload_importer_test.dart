import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/features/add_account/payload_importer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/migration_fixtures.dart';

const _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

void main() {
  late PayloadImporter importer;
  setUp(() => importer = PayloadImporter());

  List<String> issuers(ImportOutcome outcome) => [
    for (final a in (outcome as ImportReady).accounts) a.issuer,
  ];

  group('otpauth://', () {
    test('a valid URI is ready immediately', () {
      final outcome = importer.handle(
        '  otpauth://totp/GitHub:octocat?secret=$_secret&issuer=GitHub\n',
      );
      expect(issuers(outcome), ['GitHub']);
    });

    test('maps parser failures to user-facing problems', () {
      expect(
        (importer.handle(
          'otpauth://totp/x?secret=$_secret&algorithm=MD5',
        ) as ImportRejected).problem,
        ImportProblem.unsupportedAlgorithm,
      );
      expect(
        (importer.handle(
          'otpauth://totp/x?digits=6',
        ) as ImportRejected).problem,
        ImportProblem.invalidAccountCode,
      );
    });
  });

  test('text that is not an account code is rejected', () {
    for (final text in ['https://example.com', 'hello', '', 'WIFI:S:x;;']) {
      expect(
        (importer.handle(text) as ImportRejected).problem,
        ImportProblem.notAnAccountCode,
        reason: text,
      );
    }
  });

  group('otpauth-migration://', () {
    test('a single-part export is ready immediately, in order', () {
      final outcome = importer.handle(
        migrationUri([
          migrationAccount(issuer: 'A'),
          migrationAccount(issuer: 'B', type: 1, counter: 3),
        ]),
      );
      expect(issuers(outcome), ['A', 'B']);
      expect((outcome as ImportReady).accounts[1].type, OtpType.hotp);
    });

    test('parts are collected in any order; repeats are ignored', () {
      final part0 = migrationUri(
        [migrationAccount(issuer: 'A')],
        batchSize: 3,
        batchIndex: 0,
      );
      final part1 = migrationUri(
        [migrationAccount(issuer: 'B')],
        batchSize: 3,
        batchIndex: 1,
      );
      final part2 = migrationUri(
        [migrationAccount(issuer: 'C')],
        batchSize: 3,
        batchIndex: 2,
      );

      final first = importer.handle(part2) as ImportNeedsMore;
      expect((first.received, first.total), (1, 3));
      final repeat = importer.handle(part2) as ImportNeedsMore;
      expect(repeat.received, 1);
      expect((importer.handle(part0) as ImportNeedsMore).received, 2);

      expect(issuers(importer.handle(part1)), ['A', 'B', 'C']);
    });

    test('a part from a different export starts over', () {
      importer.handle(
        migrationUri(
          [migrationAccount(issuer: 'Old')],
          batchSize: 2,
          batchId: 1,
        ),
      );
      final other = importer.handle(
        migrationUri(
          [migrationAccount(issuer: 'New')],
          batchSize: 2,
          batchId: 2,
        ),
      ) as ImportNeedsMore;
      expect(other.received, 1);
      expect(
        issuers(
          importer.handle(
            migrationUri(
              [migrationAccount(issuer: 'New2')],
              batchSize: 2,
              batchIndex: 1,
              batchId: 2,
            ),
          ),
        ),
        ['New', 'New2'],
      );
    });

    test('an MD5 account rejects the part', () {
      expect(
        (importer.handle(
          migrationUri([migrationAccount(issuer: 'X', algorithm: 4)]),
        ) as ImportRejected).problem,
        ImportProblem.unsupportedAlgorithm,
      );
    });

    test('the account cap applies across parts, not just per part', () {
      final small = migrationAccount(issuer: '', name: '', secret: [1]);
      final part0 = migrationUri(
        List.filled(600, small),
        batchSize: 2,
        batchIndex: 0,
      );
      final part1 = migrationUri(
        List.filled(600, small),
        batchSize: 2,
        batchIndex: 1,
      );
      expect(importer.handle(part0), isA<ImportNeedsMore>());
      expect(
        (importer.handle(part1) as ImportRejected).problem,
        ImportProblem.tooManyAccounts,
      );
      // The rejected export is dropped; a new scan starts from scratch.
      expect((importer.handle(part0) as ImportNeedsMore).received, 1);
    });

    test('an empty export is rejected rather than "ready" with nothing', () {
      expect(importer.handle(migrationUri([])), isA<ImportRejected>());
    });
  });
}
