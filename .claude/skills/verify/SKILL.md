---
name: verify
description: Run Cypher's full verification gate — format check, flutter analyze, flutter test, and the offline/security guard (no release network permissions, no telemetry packages, pure-Dart OTP core, no print calls). Use before reporting any code change as done, or when asked to check, validate or lint the project.
allowed-tools: Bash(dart format:*), Bash(flutter analyze:*), Bash(flutter test:*), Bash(dart .claude/skills/verify/scripts/guard.dart:*)
---

# /verify — verification gate

Run from the repo root, in this order. Report every step's actual result.

1. `dart format --output=none --set-exit-if-changed lib test`. If it fails, run `dart format lib test`, then re-check.
2. `flutter analyze`. It must print `No issues found!`.
3. `flutter test`. Pass a path or `--plain-name "<name>"` only when the user asked for a subset; the gate itself is the full suite.
4. `dart .claude/skills/verify/scripts/guard.dart`. It exits 1 on any `ERROR` line. `WARN` lines are reported but don't fail the gate. `TODO` lines are required protections not yet implemented.

## What the guard checks

- No `INTERNET` / `ACCESS_NETWORK_STATE` permission in `android/app/src/main/AndroidManifest.xml` (debug and profile manifests are exempt).
- No `com.apple.security.network.*` in `macos/Runner/Release.entitlements`.
- No denylisted telemetry, crash-reporting or ad packages in `pubspec.lock`. It warns on direct HTTP clients.
- No `package:flutter` imports under `lib/core/otp/`.
- No `print(` in `lib/`. It warns on `debugPrint(` and `dart:developer` `log(`.
- TODO lines for `FLAG_SECURE` in `MainActivity`, and for Android Auto Backup not yet disabled.

## Reporting

```
format:  pass | fail (<files>)
analyze: No issues found | <N issues, listed>
test:    <N passed, M failed> | <failing test names>
guard:   pass | <ERROR lines>   (+ WARN/TODO lines)
```

Stop at the first failing step only if later steps can't run meaningfully (for example, a compile error). Otherwise run every step and report them all. Never fix a failure by weakening a test, deleting a check or adding `// ignore:`.
