/// Escalating waits after wrong PINs. There is deliberately no wipe: a bad
/// day must not destroy the user's accounts.
abstract final class PinThrottle {
  /// Wrong PINs allowed before the first wait.
  static const int freeAttempts = 5;

  static const List<Duration> _waits = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  /// How long to wait after [failures] consecutive wrong PINs; `null` while
  /// free attempts remain. 5 → 30 s, 6 → 1 min, 7 → 5 min, 8 → 15 min, then
  /// 1 h for every further failure.
  static Duration? waitAfter(int failures) {
    if (failures < freeAttempts) return null;
    final step = failures - freeAttempts;
    return _waits[step < _waits.length ? step : _waits.length - 1];
  }
}
