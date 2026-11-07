import '../core/clock.dart';

/// Wall-clock time. Lives in `app/` because `lib/core/` may not read the
/// wall clock directly.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
