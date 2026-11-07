import 'package:cypher/core/clock.dart';

/// A [Clock] that only moves when the test moves it.
final class FakeClock implements Clock {
  FakeClock(this.current);

  /// Starts at [seconds] after the Unix epoch (UTC), matching RFC test times.
  FakeClock.atUnixSeconds(int seconds)
    : current = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      );

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration by) => current = current.add(by);
}
