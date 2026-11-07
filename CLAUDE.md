# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Cypher

Cypher is a cross-platform **two-factor authenticator app** built with Flutter. It generates time-based (TOTP, RFC 6238) and counter-based (HOTP, RFC 4226) one-time passcodes, compatible with standard `otpauth://` QR codes issued by services like Google, GitHub, Microsoft, AWS, etc.

## Core principle: offline-first, zero network

- The app must work **fully offline**. Code generation, account storage, import/export and all UI flows require no network.
- Do **not** add analytics, crash reporting, telemetry, ads, remote config, or any package that phones home.
- Do not add the `INTERNET` permission to the Android manifest for release builds, and do not enable network entitlements on iOS/macOS unless explicitly requested.
  - The Flutter template already puts `INTERNET` in `android/app/src/debug/` and `src/profile/` manifests, and `com.apple.security.network.server` in `macos/Runner/DebugProfile.entitlements`. That's expected, because the Flutter tool needs them for hot reload and debugging. Leave them there, but keep `android/app/src/main/AndroidManifest.xml` and `macos/Runner/Release.entitlements` free of network permissions.
- Any future sync/backup feature must be opt-in and end-to-end encrypted; local encrypted export files are the default backup path.

## Security requirements

- Secrets (Base32 shared keys) are stored only in platform secure storage (Android Keystore / iOS Keychain) or an encrypted local database whose key lives in secure storage. Never store secrets in plain `SharedPreferences`, logs, or files.
- Never log, print, or include secrets in error messages or debug output.
- Support app lock (PIN and/or biometrics) before codes are shown.
- Block screenshots / hide content in the app switcher where the platform allows (e.g. `FLAG_SECURE` on Android).
- Clear clipboard after copying a code (e.g. after ~30 seconds).
- Exports must be encrypted with a user-supplied password (e.g. Argon2id/PBKDF2 + AES-GCM).

## Features (planned)

- Add accounts via QR scan (camera), image import, or manual entry (issuer, account, secret, algorithm SHA1/SHA256/SHA512, digits 6/8, period).
- Account list with live codes, countdown indicator, tap-to-copy, search, reorder, edit, delete.
- HOTP support with manual "next code" counter increment.
- Encrypted backup export/import; import from `otpauth://` and `otpauth-migration://` URIs.
- App lock with PIN/biometrics; light/dark theme.

## Tech stack

- Flutter (stable) / Dart 3.x. It targets **Android and iOS only**: no desktop or web, and Android `minSdk` is 30. The desktop/web platform folders are scaffold leftovers due for removal in M0.
- Suggested packages (all offline): `flutter_secure_storage`, `local_auth`, `mobile_scanner`, `crypto` / `cryptography`, a state management solution (e.g. `flutter_riverpod`).
- Implement OTP generation in-house in pure Dart (HMAC per RFC 4226/6238) so it is fully testable and dependency-light.

## Current state

The repo is still the stock `flutter create` scaffold. `lib/main.dart` is the counter demo and `test/widget_test.dart` is its smoke test, and no dependencies have been added beyond `cupertino_icons`. Replace both files when real features land. Android package / application ID: `com.cypher.cypher`. The Dart SDK constraint is `^3.13.5`. Lints come from `flutter_lints` (`analysis_options.yaml`), which excludes the platform folders.

## Suggested structure

The full design (storage and key handling, backup format, milestones M0–M7, open questions) is in `docs/system-plan.md`. Work through its milestones in order.

```
lib/
  main.dart
  app/            # app widget, routing, theme
  core/otp/       # TOTP/HOTP generation, Base32, otpauth URI parsing
  core/security/  # secure storage, encryption, app lock
  data/           # account model + repository
  features/       # accounts list, add account, scanner, settings, backup
test/             # unit tests (OTP must be verified against RFC test vectors)
```

## Commands

```
flutter pub get        # install deps
flutter run            # run on a connected device/emulator
flutter test           # run tests
flutter test test/path/to_test.dart                 # run one test file
flutter test --plain-name "substring of test name"  # run matching tests
flutter analyze        # static analysis
dart format .          # format
flutter build apk      # Android release build
```

Pure-Dart tests (under `core/`, no Flutter imports) can also run with `dart test`, but only once `package:test` is added as a dev dependency.

## Conventions

- Keep OTP/crypto logic in pure Dart with no Flutter imports, and cover it with RFC test vectors.
- Before considering a change done, run `/verify`: format check, `flutter analyze`, `flutter test`, then `dart .claude/skills/verify/scripts/guard.dart`.
- Prefer small, auditable dependencies; justify any new package with respect to the offline and security rules above.

## Claude Code configuration (`.claude/`)

- `rules/` are path-scoped (`paths:` frontmatter) and load only when matching files are in play: `architecture`, `coding-standards`, `security`, `performance` and `testing` for `lib/`/`test/`, and `dependencies` for `pubspec.*`. They hold the *how*; this file holds the *what*. Don't duplicate between them. When a pending decision is made (e.g. state management), update the relevant rule.
- Project skills: `/deliver <task>` (the analyze → plan → implement → review → verify workflow, user-invoked only), `/verify` (the verification gate), and `otp-reference` (RFC vectors and the otpauth URI spec, auto-loaded when OTP code is involved).
- Agent: `@refine` (`agents/refine.md`) does cleanup that keeps behaviour unchanged on a named file, folder or recent change. It writes tests that pin down current behaviour if none exist, and finishes with the full verification gate.
- The guard script (`.claude/skills/verify/scripts/guard.dart`) uses only `dart:io`. Add a check there whenever a new rule can be checked mechanically. `ERROR` fails the gate; `TODO` tracks required protections not yet built (currently `FLAG_SECURE` and disabling Android Auto Backup).
- Third-party skills from `emilkowalski/skill` were installed with `npx skills add` and are tracked in `skills-lock.json`. Most target web, React or Swift: apply their design principles to Flutter and ignore their CSS/JS specifics. Update them with `npx skills update -p`.
