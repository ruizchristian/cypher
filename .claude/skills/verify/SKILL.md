---
name: verify
description: Run Cypher's full verification gate — format check, flutter analyze, flutter test, and the offline/security guard (network code only in the updater, release permissions allowlisted, no telemetry packages, pure-Dart OTP core, no print calls). Use before reporting any code change as done, or when asked to check, validate or lint the project.
allowed-tools: Bash(dart format:*), Bash(flutter analyze:*), Bash(flutter test:*), Bash(dart .claude/skills/verify/scripts/guard.dart:*)
---

# /verify — verification gate

Run from the repo root, in this order. Report every step's actual result.

1. `dart format --output=none --set-exit-if-changed lib test`. If it fails, run `dart format lib test`, then re-check.
2. `flutter analyze`. It must print `No issues found!`.
3. `flutter test`. Pass a path or `--plain-name "<name>"` only when the user asked for a subset; the gate itself is the full suite.
4. `dart .claude/skills/verify/scripts/guard.dart`. It exits 1 on any `ERROR` line. `WARN` lines are reported but don't fail the gate. `TODO` lines are required protections not yet implemented.

## What the guard checks

- No `ACCESS_NETWORK_STATE` / `ACCESS_WIFI_STATE` permission in `android/app/src/main/AndroidManifest.xml`. `INTERNET` is allowed for the in-app updater only.
- No network code (`HttpClient`, sockets, `package:http`/`dio`/`web_socket_channel`) anywhere in `lib/` except `lib/features/update/update_source.dart`.
- No denylisted telemetry, crash-reporting or ad packages in `pubspec.lock`. It warns on direct HTTP clients.
- No `package:flutter` imports under `lib/core/otp/`, and no `DateTime.now()` anywhere under `lib/core/`.
- No `print(` in `lib/`. It warns on `debugPrint(` and `dart:developer` `log(`.
- Android backup is off: `allowBackup="false"`, plus `data_extraction_rules.xml` excluding every domain from cloud backup and device transfer.
- The merged manifest of the last release build requests only allowlisted permissions (`CAMERA`, `USE_BIOMETRIC`, `INTERNET`, `REQUEST_INSTALL_PACKAGES`). It warns if there is no release build, or if it is older than `pubspec.lock` or the main manifest.
- `MainActivity` sets `FLAG_SECURE` and extends `FlutterFragmentActivity` (ERROR otherwise).

## Reporting

```
format:  pass | fail (<files>)
analyze: No issues found | <N issues, listed>
test:    <N passed, M failed> | <failing test names>
guard:   pass | <ERROR lines>   (+ WARN/TODO lines)
```

Stop at the first failing step only if later steps can't run meaningfully (for example, a compile error). Otherwise run every step and report them all. Never fix a failure by weakening a test, deleting a check or adding `// ignore:`.
