import '../../core/otp/migration_batch.dart';
import '../../core/otp/migration_payload.dart';
import '../../core/otp/otp_parameters.dart';
import '../../core/otp/otpauth_uri.dart';

enum ImportProblem {
  notAnAccountCode,
  invalidAccountCode,
  unsupportedAlgorithm,
  tooManyAccounts,
}

sealed class ImportOutcome {
  const ImportOutcome();
}

/// Every account the payload describes, ready for confirmation.
final class ImportReady extends ImportOutcome {
  const ImportReady(this.accounts);

  final List<OtpParameters> accounts;
}

/// Part of a multi-code export was read; more parts are needed.
final class ImportNeedsMore extends ImportOutcome {
  const ImportNeedsMore({required this.received, required this.total});

  final int received;
  final int total;
}

final class ImportRejected extends ImportOutcome {
  const ImportRejected(this.problem);

  final ImportProblem problem;
}

/// Turns scanned or pasted text into accounts.
///
/// Holds state across calls so a multi-code Google Authenticator export can
/// be assembled from several scans. Use one importer per add-account flow.
final class PayloadImporter {
  final MigrationBatchCollector _batch = MigrationBatchCollector();

  ImportOutcome handle(String text) {
    final trimmed = text.trim();
    final scheme = trimmed.split(':').first.toLowerCase();
    return switch (scheme) {
      'otpauth' => _single(OtpauthUri.parse(trimmed)),
      'otpauth-migration' => _migration(MigrationPayload.parse(trimmed)),
      _ => const ImportRejected(ImportProblem.notAnAccountCode),
    };
  }

  ImportOutcome _single(OtpauthParseResult result) => switch (result) {
    OtpauthParsed(:final parameters) => ImportReady([parameters]),
    OtpauthParseFailure(error: OtpauthError.unsupportedAlgorithm) =>
      const ImportRejected(ImportProblem.unsupportedAlgorithm),
    OtpauthParseFailure(error: OtpauthError.notOtpauth) => const ImportRejected(
      ImportProblem.notAnAccountCode,
    ),
    OtpauthParseFailure() => const ImportRejected(
      ImportProblem.invalidAccountCode,
    ),
  };

  ImportOutcome _migration(MigrationParseResult result) {
    switch (result) {
      case MigrationParseFailure(:final error):
        return ImportRejected(switch (error) {
          MigrationError.unsupportedAlgorithm =>
            ImportProblem.unsupportedAlgorithm,
          MigrationError.tooManyAccounts => ImportProblem.tooManyAccounts,
          MigrationError.notMigrationUri => ImportProblem.notAnAccountCode,
          _ => ImportProblem.invalidAccountCode,
        });
      case MigrationParsed():
        // The per-part cap alone could be sidestepped by splitting an export
        // into many parts, so the running total is capped too.
        if (_batch.wouldExceed(result, MigrationPayload.maxAccounts)) {
          _batch.reset();
          return const ImportRejected(ImportProblem.tooManyAccounts);
        }
        final complete = _batch.add(result);
        if (complete != null) {
          return complete.isEmpty
              ? const ImportRejected(ImportProblem.invalidAccountCode)
              : ImportReady(complete);
        }
        return ImportNeedsMore(received: _batch.received, total: _batch.total);
    }
  }
}
