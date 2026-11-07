import 'migration_payload.dart';
import 'otp_parameters.dart';

/// Collects the parts of a multi-QR Google Authenticator export.
///
/// Large exports are split across several `otpauth-migration://` codes that
/// share a batch id. A scanner reports the same code many times, so repeated
/// parts are ignored. A part from a different export starts over. Accounts
/// are released only once every part has arrived, keeping the import
/// all-or-nothing.
final class MigrationBatchCollector {
  int? _batchId;
  int _batchSize = 0;
  final Map<int, List<OtpParameters>> _parts = {};

  int get received => _parts.length;

  /// Accounts collected so far across all received parts.
  int get accountCount =>
      _parts.values.fold(0, (sum, accounts) => sum + accounts.length);

  /// Whether adding [part] would take this export above [limit] accounts.
  /// A repeated part adds nothing; a part from another export starts over.
  bool wouldExceed(MigrationParsed part, int limit) {
    final sameBatch = part.batchId == _batchId && part.batchSize == _batchSize;
    final existing = sameBatch ? accountCount : 0;
    final added = sameBatch && _parts.containsKey(part.batchIndex)
        ? 0
        : part.accounts.length;
    return existing + added > limit;
  }

  /// Total parts expected, or 0 before the first part.
  int get total => _batchSize;

  /// Adds [part]. Returns every account in batch order once the batch is
  /// complete, otherwise `null`.
  /// Throws [RangeError] if the part's index is outside its batch (the
  /// parser already guarantees this for parsed payloads).
  List<OtpParameters>? add(MigrationParsed part) {
    RangeError.checkValueInInterval(
      part.batchIndex,
      0,
      part.batchSize - 1,
      'batchIndex',
    );
    if (part.batchId != _batchId || part.batchSize != _batchSize) {
      reset();
      _batchId = part.batchId;
      _batchSize = part.batchSize;
    }
    _parts.putIfAbsent(part.batchIndex, () => part.accounts);
    if (_parts.length < _batchSize) return null;

    final accounts = [for (var i = 0; i < _batchSize; i++) ..._parts[i]!];
    reset();
    return accounts;
  }

  void reset() {
    _batchId = null;
    _batchSize = 0;
    _parts.clear();
  }
}
