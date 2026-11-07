import 'package:cypher/core/otp/migration_batch.dart';
import 'package:cypher/core/otp/migration_payload.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:flutter_test/flutter_test.dart';

OtpParameters _account(String issuer) =>
    OtpParameters(type: OtpType.totp, secret: OtpSecret([1]), issuer: issuer);

MigrationParsed _part(
  int index,
  int size, {
  int id = 1,
  List<String> issuers = const ['x'],
}) => MigrationParsed(
  accounts: [for (final i in issuers) _account(i)],
  batchIndex: index,
  batchSize: size,
  batchId: id,
);

void main() {
  late MigrationBatchCollector collector;
  setUp(() => collector = MigrationBatchCollector());

  test('releases every account in batch order once complete', () {
    expect(collector.add(_part(1, 2, issuers: ['B', 'C'])), isNull);
    expect((collector.received, collector.total), (1, 2));
    final all = collector.add(_part(0, 2, issuers: ['A']));
    expect(all!.map((a) => a.issuer), ['A', 'B', 'C']);
    expect((collector.received, collector.total), (0, 0)); // reset
  });

  test('a repeated part is ignored', () {
    collector.add(_part(0, 2, issuers: ['A']));
    collector.add(_part(0, 2, issuers: ['A']));
    expect((collector.received, collector.accountCount), (1, 1));
  });

  test('a part from another export starts over', () {
    collector.add(_part(0, 2, id: 1, issuers: ['Old']));
    expect(collector.add(_part(0, 2, id: 2, issuers: ['New'])), isNull);
    expect(
      collector
          .add(_part(1, 2, id: 2, issuers: ['New2']))!
          .map((a) => a.issuer),
      ['New', 'New2'],
    );
  });

  test('rejects an index outside its batch', () {
    expect(() => collector.add(_part(2, 2)), throwsRangeError);
    expect(() => collector.add(_part(-1, 2)), throwsRangeError);
  });

  group('wouldExceed', () {
    test('counts what is already collected plus the new part', () {
      collector.add(_part(0, 3, issuers: ['a', 'b']));
      expect(collector.wouldExceed(_part(1, 3, issuers: ['c']), 3), isFalse);
      expect(
        collector.wouldExceed(_part(1, 3, issuers: ['c', 'd']), 3),
        isTrue,
      );
    });

    test('a repeated part adds nothing', () {
      collector.add(_part(0, 3, issuers: ['a', 'b', 'c']));
      expect(
        collector.wouldExceed(_part(0, 3, issuers: ['a', 'b', 'c']), 3),
        isFalse,
      );
    });

    test('a part from another export is counted on its own', () {
      collector.add(_part(0, 3, id: 1, issuers: ['a', 'b', 'c']));
      expect(
        collector.wouldExceed(_part(0, 3, id: 2, issuers: ['z']), 3),
        isFalse,
      );
    });
  });

  test('the parser caps the batch size', () {
    expect(MigrationPayload.maxBatchSize, 100);
  });
}
