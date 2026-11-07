---
paths:
  - "test/**/*.dart"
  - "lib/core/**/*.dart"
---

# Testing rules

- Any change under `lib/core/otp/` runs the full RFC 4226 and RFC 6238 vector sets (SHA1, SHA256, SHA512; 6 and 8 digits) and the RFC 4648 Base32 vectors. The vectors live in the `otp-reference` skill. Copy them into tests verbatim; never recompute "expected" values with the code under test.
- Use only the RFC test secrets or obviously fake keys in fixtures. Never use a real account's secret.
- Time: inject a clock and test explicit instants, including window boundaries (`T = 29`, `30`, `59`, `60` for a 30 s period). Tests must never depend on the wall clock or sleep.
- Platform services (secure storage, `local_auth`, clipboard, camera) are tested through their interfaces with in-memory fakes in `test/fakes/`. Unit tests must not invoke real platform channels.
- Widget tests: drive time with `tester.pump(duration)` and a fake clock, and leave no pending timers when a test ends (the clipboard-clear timer included). Assert on semantics labels as well as text where accessibility matters.
- Every bug fix comes with a regression test that fails without the fix.
- Security-relevant assertions belong in tests too: `toString()` and error messages of secret-bearing types must not contain the secret.
- Layout: `lib/core/otp/totp.dart` → `test/core/otp/totp_test.dart`. Group with `group()` per public method or behaviour, and use descriptive test names (they're how `--plain-name` finds them).
- Run one file with `flutter test test/core/otp/totp_test.dart`, one test with `flutter test --plain-name "<name>"`, and everything with `flutter test`.
