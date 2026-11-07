/// The source of "now". Core code takes time as a parameter; the UI reads it
/// through this interface so tests can control it.
abstract interface class Clock {
  DateTime now();
}
