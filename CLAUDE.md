# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Cypher

Cypher is a cross-platform **two-factor authenticator app** built with Flutter. It generates time-based (TOTP, RFC 6238) and counter-based (HOTP, RFC 4226) one-time passcodes, compatible with standard `otpauth://` QR codes issued by services like Google, GitHub, Microsoft, AWS, etc.

## Core principle: offline-first, zero network

- The app must work **fully offline**. Code generation, account storage, import/export and all UI flows require no network.
- Do **not** add analytics, crash reporting, telemetry, ads, remote config, or any package that phones home.
- Do not add the `INTERNET` permission to the Android manifest for release builds, and do not add network-related entitlements on iOS unless explicitly requested.
  - The Flutter template already puts `INTERNET` in `android/app/src/debug/` and `src/profile/` manifests. That's expected, because the Flutter tool needs them for hot reload and debugging. Leave them there, but keep `android/app/src/main/AndroidManifest.xml` free of network permissions.
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

- Flutter (stable) / Dart 3.x. It targets **Android and iOS only**: no desktop or web, and Android `minSdk` is 30.
- Suggested packages (all offline): `flutter_secure_storage`, `local_auth`, `flutter_zxing` (QR; not `mobile_scanner`, whose ML Kit bundles Google telemetry), `crypto` / `cryptography`, a state management solution (e.g. `flutter_riverpod`).
- Implement OTP generation in-house in pure Dart (HMAC per RFC 4226/6238) so it is fully testable and dependency-light.

## Current state

M0–M4 are done (foundations, OTP core, vault, accounts UI, adding accounts). `main.dart` opens the vault, then runs `ProviderScope` → `CypherApp`, with the injected dependencies (clock, repository, clipboard) overridden; their providers live in `lib/features/shared/providers.dart` and have no defaults. **Until M5 there is no lock screen: `AccountsScreen` unlocks the vault itself, so the app must not be released before M5.** `lib/core/otp/` holds Base32, HOTP/TOTP and the `otpauth://` / `otpauth-migration://` parsers (RFC-verified). `lib/data/account_repository.dart` owns accounts in an AES-GCM vault whose key is in Keystore/Keychain (`lib/app/vault_bootstrap.dart` wires the real adapters). On-device tests live in `integration_test/`; run them with `flutter test integration_test -d <device>`. Next is M5 (lock screen and hardening). Android package / application ID: `com.cypher.cypher`. The Dart SDK constraint is `^3.13.5`. Lints come from `flutter_lints` (`analysis_options.yaml`), which excludes `android/` and `ios/`.

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
flutter build apk      # Android release build (then run the guard: it audits the release permissions)
```

App icon: artwork in `assets/icon/`; regenerate all Android/iOS sizes with the standalone generator in `tool/app_icon/` (see its README).

Pure-Dart tests (under `core/`, no Flutter imports) can also run with `dart test`, but only once `package:test` is added as a dev dependency.

## Conventions

- Keep OTP/crypto logic in pure Dart with no Flutter imports, and cover it with RFC test vectors.
- Before considering a change done, run `/verify`: format check, `flutter analyze`, `flutter test`, then `dart .claude/skills/verify/scripts/guard.dart`.
- Prefer small, auditable dependencies; justify any new package with respect to the offline and security rules above.

## Claude Code configuration (`.claude/`)

- `rules/` are path-scoped (`paths:` frontmatter) and load only when matching files are in play: `architecture`, `coding-standards`, `security`, `performance` and `testing` for `lib/`/`test/`, and `dependencies` for `pubspec.*`. They hold the *how*; this file holds the *what*. Don't duplicate between them. When a pending decision is made (e.g. state management), update the relevant rule.
- Project skills: `/deliver <task>` (the analyze → plan → implement → review → verify workflow, user-invoked only), `/verify` (the verification gate), and `otp-reference` (RFC vectors and the otpauth URI spec, auto-loaded when OTP code is involved).
- Agent: `@refine` (`agents/refine.md`) does cleanup that keeps behaviour unchanged on a named file, folder or recent change. It writes tests that pin down current behaviour if none exist, and finishes with the full verification gate.
- The guard script (`.claude/skills/verify/scripts/guard.dart`) uses only `dart:io`. Add a check there whenever a new rule can be checked mechanically. `ERROR` fails the gate; `TODO` tracks required protections not yet built (currently `FLAG_SECURE`). It also audits the merged manifest of the last `flutter build apk --release` against a permission allowlist (CAMERA only), so rebuild release after changing dependencies.
- Third-party skills from `emilkowalski/skill` were installed with `npx skills add` and are tracked in `skills-lock.json`. Most target web, React or Swift: apply their design principles to Flutter and ignore their CSS/JS specifics. Update them with `npx skills update -p`.
