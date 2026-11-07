# Cypher — System Plan

**Status:** proposed (2026-11-07). The decisions marked **Proposed** become binding once implemented and recorded in `.claude/rules/`.
**Scope:** Android and iOS only (D10). There are no desktop or web versions.

This plan says *what* to build and in *what order*. `CLAUDE.md` holds the product requirements, and `.claude/rules/` holds *how* code is written. This document does not restate them.

---

## 1. Goals and non-goals

**Goals**
- Generate correct TOTP/HOTP codes for any standard `otpauth://` account, fully offline.
- Keep secrets safe at rest, on screen, on the clipboard and in backups (threat model: lost device, other apps, OS backups, malicious QR/import input, supply chain).
- Give users a reliable way out: an encrypted export that any future Cypher version can import.

**Non-goals (v1)**
- Cloud sync, accounts or any server component.
- Push-based 2FA, U2F/WebAuthn, Steam Guard and other non-RFC schemes.
- Fetching issuer icons from the network. Icons are bundled or generated from initials.
- Network time correction (no NTP). A clock-skew hint is shown instead (§9).

---

## 2. System overview

```
┌──────────────────────────── app/ ─────────────────────────────┐
│ CypherApp · theme · routes · LockGate (lifecycle) · providers │
└───────────────┬───────────────────────────────────────────────┘
                │
┌──────────── features/ ───────────────────────────────────────┐
│ lock   accounts   add_account   account_edit   backup   settings │
└───────────────┬───────────────────────────────────────────────┘
                │  (only through repositories/services)
┌────────────── data/ ─────────────────────────────────────────┐
│ Account model · VaultCodec (schema v1) · AccountRepository    │
│ SettingsRepository                                            │
└───────────────┬───────────────────────────────────────────────┘
                │
┌────────────── core/ ─────────────────────────────────────────┐
│ otp/       Base32 · Hotp · Totp · OtpauthUri · MigrationPayload · Clock │  pure Dart
│ security/  VaultCipher · Kdf · ExportFormat · PinHasher        │  pure Dart
│            SecretStore · BiometricAuth · ScreenGuard ·         │  interfaces
│            SecureClipboard                                     │
│ security/platform/  adapters for flutter_secure_storage,       │  Flutter plugins
│            local_auth, MethodChannel (FLAG_SECURE, clipboard)  │
└───────────────────────────────────────────────────────────────┘
```

Dependency direction and layer rules: `.claude/rules/architecture.md`.

---

## 3. Key decisions

| # | Decision | Status | Rationale |
|---|---|---|---|
| D1 | **State management: `flutter_riverpod`**, without code generation | Proposed | Testable through provider overrides, no `build_runner` dependency, and scoped rebuilds (performance rule). Record it in `architecture.md` in M0. |
| D2 | **Routing: plain `Navigator`** with a small route table; no `go_router` | Proposed | Under 10 screens and no deep links. Leaving out deep links also keeps secrets out of URLs. |
| D3 | **Storage: one encrypted vault file + a data-encryption key (DEK) in secure storage** | Proposed | Atomic writes (temp file + rename), one read at unlock (performance rule), a versioned schema, and serialization shared with export. It avoids storing one secure-storage entry per account, which has no atomic multi-entry update. |
| D4 | **OTP, Base32, otpauth and the migration-protobuf decoder are written in-house** | Decided (CLAUDE.md) | A small hand-written protobuf varint decoder replaces the `protobuf` package. |
| D5 | **Crypto library: `cryptography`** (Argon2id, AES-GCM); **`crypto`** for HMAC/SHA | Proposed | Pure Dart, maintained, no network. `cryptography_flutter` (native acceleration) is an optional later addition if Argon2id benchmarks are too slow. |
| D6 | **App lock is a UI gate over keystore-protected data in v1. v2 moves to auth-bound keys** (§6.1) | Decided (Q2) | v1 ships sooner on a simple design. v2 makes secrets cryptographically unreadable without biometrics or the PIN. v1 must keep the DEK behind a `KeyWrapper` interface so v2 needs no vault migration. |
| D7 | **IDs: a random 128-bit hex string from `Random.secure()`**; no `uuid` package | Proposed | Too small a need to justify a dependency. |
| D8 | **The PIN is mandatory.** There is no "no lock" mode; biometrics are an optional convenience on top | Decided (Q1) | CLAUDE.md requires a lock before codes are shown, and v2's PIN-wrapped DEK (§6.1) needs a PIN to exist. |
| D10 | **Phones only: Android and iOS.** No desktop (Windows/macOS/Linux) or web | Decided (Q4) | One mobile security model to build and test. Web can't meet the secure-storage rule anyway. The unused platform folders are removed in M0. |
| D9 | **Android `minSdk = 30`** (Android 11) | Decided (Q3) | It gives `setUserAuthenticationParameters` (biometric *or* device-credential auth on a Keystore key, needed for v2) and a stable `BiometricPrompt`. This drops Android 10 and older. iOS keeps Flutter's default minimum. |

---

## 4. Data model (`data/`)

```dart
enum OtpType { totp, hotp }
enum HashAlgorithm { sha1, sha256, sha512 }

/// Raw secret bytes. toString() is redacted; never serialised except by VaultCodec/ExportFormat.
final class OtpSecret {
  const OtpSecret(this.bytes);
  final Uint8List bytes;
  @override
  String toString() => 'OtpSecret(<redacted>)';
}

final class Account {
  final String id;
  final String issuer;          // may be empty
  final String label;           // account name, e.g. user@example.com
  final OtpType type;
  final HashAlgorithm algorithm; // default sha1
  final int digits;             // 6–8
  final int period;             // seconds, TOTP only, default 30
  final int counter;            // HOTP only
  final OtpSecret secret;
  final int sortIndex;
  final DateTime createdAt;
  // copyWith(...), redacted toString()
}
```

**Vault plaintext (schema v1)**, as JSON before encryption:
`{ "schema": 1, "accounts": [ { "id", "issuer", "label", "type", "alg", "digits", "period", "counter", "secret": "<base32>", "sort", "created" } ] }`

`VaultCodec` reads every schema version up to the current one and writes only the current one. Each schema bump ships with a migration test.

---

## 5. Core components (`core/`)

### 5.1 OTP (`core/otp/`): pure Dart
| Component | Responsibility |
|---|---|
| `Base32` | RFC 4648 decode/encode. Lenient input (case, spaces, hyphens, padding); strict alphabet. |
| `Hotp.generate(secret, counter, algorithm, digits)` | RFC 4226 with a 64-bit counter. |
| `Totp.generate(..., at: DateTime, period)` and `Totp.remaining(at, period)` | RFC 6238. Time is always passed in. |
| `Clock` | `DateTime now()` interface (added in M3): `SystemClock` lives in `app/` because `lib/core/` may not call `DateTime.now()`; `FakeClock` in tests. |
| `OtpauthUri.parse(String) → ParseResult` | A `sealed` result: `ParsedAccount` or `ParseFailure(reason)`. The failure never echoes its input. |
| `MigrationPayload.parse(String) → ...` | `otpauth-migration://` decoding: Base64, then a hand-written protobuf reader, with batch support. |

Reference vectors and the URI spec are in the `otp-reference` skill.

### 5.2 Security (`core/security/`)
| Component | Responsibility |
|---|---|
| `VaultCipher` | AES-256-GCM encrypt/decrypt of the vault with the DEK. Random 12-byte nonce per write, header as AAD. |
| `Kdf` | Argon2id (default) and PBKDF2-SHA256 (fallback), with explicit params. Runs in `Isolate.run`. |
| `ExportFormat` | Encodes and decodes the backup file (§7). |
| `PinHasher` | PIN → salted KDF hash, constant-time verify. |
| `SecretStore` *(interface)* | `read/write/delete(String key)`, implemented over `flutter_secure_storage` with `*_this_device` Keychain accessibility. |
| `BiometricAuth` *(interface)* | `isAvailable()` and `authenticate(reason)`, implemented over `local_auth`. |
| `ScreenGuard` *(interface)* | Enables secure-window mode. Android: `FLAG_SECURE`. iOS: no-op (the privacy overlay is handled in `app/`). |
| `SecureClipboard` *(interface)* | `copy(code)` marks the clip sensitive on Android 13+ and schedules a conditional clear after 30 s. |

### 5.3 Repositories (`data/`)
- `AccountRepository`: `unlock()` loads and decrypts the vault into memory; `lock()` drops it. It exposes `Stream<List<Account>>` and `add/update/delete/reorder/incrementCounter`. Each mutation writes through atomically. HOTP `incrementCounter` **persists before** the new code is shown, so the counter never repeats.
- `SettingsRepository`: non-secret settings (theme, auto-lock timeout, biometrics enabled, the PIN hash reference), with the PIN hash itself in `SecretStore`.

---

## 6. Storage and key handling

```
secure storage (Keystore/Keychain)          app support dir
├── cypher.vault.dek   (32 random bytes)    └── vault.bin  = header ‖ AES-GCM(DEK, vault JSON)
├── cypher.pin.hash    (salt ‖ params ‖ hash)    vault.bin.tmp (write → fsync → rename)
└── cypher.install.id  (detects reinstalls)
```

- **First run**: generate the DEK, write an empty vault, and require setting a PIN before the first account can be added.
- **iOS reinstall**: Keychain items survive app deletion. If `vault.bin` is missing but a DEK exists, the app was reinstalled, so wipe the stale Keychain items and start fresh.
- **Android key loss** (Keystore invalidated, data restored onto another device): the vault fails to decrypt. Show a dedicated "vault unreadable, restore from backup" screen. Never silently create an empty vault over the old file; move the unreadable file aside instead.
- **`KeyWrapper` (v1)**: `Future<Uint8List> unwrapDek()` / `wrapDek(Uint8List)`. The v1 implementation reads the raw DEK from `SecretStore`. All vault code depends only on this interface.

### 6.1 Auth-bound keys (v2, decided)

The DEK is stored **twice, wrapped**, never in raw form:

```
secure storage
├── cypher.dek.bio   = AES-GCM(K_bio, DEK)   K_bio: hardware key that requires biometric auth per use
└── cypher.dek.pin   = AES-GCM(K_pin, DEK)   K_pin = Argon2id(PIN, salt)
```

- **Android**: `K_bio` is an AES key in the Android Keystore with `setUserAuthenticationRequired(true)` and `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)`. It is unlocked through `BiometricPrompt` with a `CryptoObject`, and `setInvalidatedByBiometricEnrollment(true)` invalidates it when a new fingerprint or face is enrolled.
- **iOS**: `K_bio` is a Keychain item with `SecAccessControl` `.biometryCurrentSet`, `ThisDeviceOnly`.
- Either path recovers the DEK. If `K_bio` is invalidated (new fingerprint enrolled), the user unlocks with the PIN and the app re-wraps the DEK under a fresh `K_bio`.
- The PIN hash for throttling is replaced by the AES-GCM authentication check on `cypher.dek.pin`: a wrong PIN fails to decrypt. Throttling state still persists.
- This needs a native platform channel (Kotlin and Swift) beyond `flutter_secure_storage` and `local_auth`. That platform code gets its own security review.
- Migration from v1: at the first v2 unlock, read the raw DEK, write both wrapped forms, then delete the raw DEK. The vault file is untouched.

- **Settings** that are not secret may use `shared_preferences`, but only if a second package is justified. Otherwise store them inside the vault (preferred: one fewer dependency).

---

## 7. Backup format (`.cypher` file)

```
offset  size  field
0       6     magic "CYPHER"
6       1     format version (1)
7       1     kdf id (1 = Argon2id, 2 = PBKDF2-SHA256)
8       12    kdf params (Argon2id: memKiB u32, iterations u32, parallelism u32; PBKDF2: iterations u32 + 8 reserved)
20      16    salt
36      12    nonce
48      …     AES-256-GCM ciphertext ‖ 16-byte tag      (AAD = bytes 0–47)
```

- The payload is the vault JSON (same schema and codec as §4), so export and storage share one tested serializer.
- Argon2id defaults: 64 MiB, 3 iterations, parallelism 1. Benchmark on a low-end device in M6. If it takes more than about 3 s, lower the memory and store the values actually used (the params live in the header, so changing them never breaks old files).
- Import: bound the file size (1 MiB) and account count (1000). Validate everything before writing anything. On duplicates (same issuer + label + secret), skip them and report the count.
- Also import `otpauth://` (paste or scan), `otpauth-migration://` (scan, multi-QR batches) and plain-text lists of `otpauth://` lines.

---

## 8. App flow and features

```
launch ─▶ LockGate ──(no PIN yet)──▶ Onboarding: set PIN (+ biometrics?) ─▶ Accounts
                  └─(locked)──▶ Unlock (biometric → PIN fallback) ─▶ Accounts
background > timeout ─▶ repository.lock() + privacy overlay ─▶ Unlock on resume
```

| Feature | Screens and behaviour | Notes |
|---|---|---|
| `lock` | Onboarding PIN setup, unlock screen, failed-attempt throttling | Throttling state persists across restarts. |
| `accounts` | List of live codes, a single shared ticker, countdown ring, tap-to-copy, search, drag-reorder, HOTP "next code" | Performance rules: one ticker, per-step code cache. |
| `add_account` | Scanner, image import, manual form, paste URI | The scanner runs only while visible. |
| `account_edit` | Edit issuer/label; delete with confirmation (typing the issuer for HOTP accounts) | The secret is not shown again after creation. |
| `backup` | Export (password + confirm, strength hint), import (file / URI / migration QR) | KDF runs in an isolate, with a progress indicator. |
| `settings` | Theme, auto-lock timeout, biometrics toggle, change PIN, about/licences | `showLicensePage` is offline. |

---

## 9. Platform integration

**Android**
- `MainActivity` extends **`FlutterFragmentActivity`** (required by `local_auth`) and sets `FLAG_SECURE` in `onCreate`. This clears the guard TODO.
- Manifest: `android:allowBackup="false"` plus `dataExtractionRules` that exclude everything (this clears the guard TODO), `CAMERA`, `USE_BIOMETRIC`.
- Sensitive clipboard (API 33+) and `FLAG_SECURE` go through a small `MethodChannel` (`cypher/platform`).
- **Merged-manifest risk:** plugins can inject permissions. `mobile_scanner` relies on Google ML Kit, whose transitive data-transport/logging libraries may merge `INTERNET`. In M4: build a release APK, inspect the merged manifest, and if `INTERNET` or `ACCESS_NETWORK_STATE` appears, remove it with `tools:node="remove"` in the main manifest and confirm scanning still works. If ML Kit misbehaves offline, evaluate a ZXing-based scanner instead.

**iOS**
- `NSCameraUsageDescription` and `NSFaceIDUsageDescription` in `Info.plist`.
- Keychain accessibility `first_unlock_this_device`.
- Privacy overlay when `AppLifecycleState.inactive`, and the repository locks on `paused` after the timeout.

**Clock skew:** TOTP depends on device time. If the user reports wrong codes, the settings "about" section shows the device time and time zone, with a hint to enable automatic time. Nothing is fetched.

---

## 10. Dependencies (planned)

| Package | Purpose | Milestone | Network check |
|---|---|---|---|
| `flutter_riverpod` | State | M0 | Pure Dart |
| `crypto` | HMAC-SHA1/256/512 | M1 | Pure Dart (dart-lang) |
| `cryptography` | Argon2id, AES-GCM | M2 | Pure Dart |
| `flutter_secure_storage` | DEK, PIN hash | M2 | Platform keystore only |
| `path_provider` | Vault file location | M2 | Flutter team |
| `mobile_scanner` | QR scanning, image analysis | M4 | **Audit the merged manifest** (§9) |
| `image_picker` | Image import | M4 | Flutter team. Check permissions merged |
| `file_selector` | Export/import file picking | M6 | Flutter team |
| `local_auth` | Biometrics | M5 | Platform only |

Each package is added in its own milestone, following `.claude/rules/dependencies.md`. Anything not on this list needs a justification in the change report.

---

## 11. Milestones

Every item goes through `/deliver`. The 🔒 items are **sensitive**: their plan needs your approval before implementation. Each milestone ends with `@refine` over that milestone's files, then `/verify`.

| M | Deliverables | Acceptance criteria |
|---|---|---|
| **M0 Foundations** ✅ | `git init`; remove the counter template; `CypherApp`, theme (light/dark), route table, Riverpod; set `minSdk = 30` in `android/app/build.gradle.kts`; delete the `linux/`, `macos/`, `windows/` and `web/` folders and drop the guard's macOS entitlement check; replace the widget smoke test; record D1/D2/D8/D9 in `architecture.md` | The app launches to a placeholder screen; `/verify` is green; the template code is gone |
| **M1 OTP core** ✅ | `Base32`, `Hotp`, `Totp`, `OtpSecret`, `OtpauthUri`, `MigrationPayload` (`Clock` moved to M3, where the ticker first needs it) | All `otp-reference` vectors pass; malformed-URI tests pass; the guard confirms no Flutter imports |
| **M2 Vault** 🔒 | `Account`, `VaultCodec`, `VaultCipher`, `SecretStore` adapter, `AccountRepository`, atomic writes, reinstall and unreadable-vault handling | Round-trip, tamper (flipped byte → failure) and migration tests; the repository is tested with a fake `SecretStore`; `toString` redaction tests |
| **M3 Accounts UI** | `Clock` interface (+ `SystemClock` in `app/`, `FakeClock` in `test/fakes/`), list, ticker, countdown, tap-to-copy with `SecureClipboard` 🔒, search, reorder, edit/delete, HOTP next | Widget tests with `FakeClock` cover boundary rollover; no pending timers; one ticker verified |
| **M4 Add account** 🔒 | Manual form, paste URI, scanner, image import, migration-QR batches | Camera stops off-screen; the merged-manifest audit is clean (§9); invalid input shows a typed error with no echo |
| **M5 Lock and hardening** 🔒 | `FlutterFragmentActivity` + `FLAG_SECURE`, backup exclusion, iOS overlay, PIN onboarding/unlock, biometrics, auto-lock, throttling | Both guard TODOs are gone **and converted to ERROR checks**; no code renders before unlock (widget test); throttling survives a restart |
| **M6 Backup** 🔒 | Export/import (§7), Argon2id benchmark and calibration, duplicate handling | Export → import round-trip; wrong password and a corrupted file give the same error; import is all-or-nothing; KDF runs off the UI isolate |
| **M7 Release readiness** | Accessibility pass (semantics, text scaling), string centralization, app icon, release builds for both platforms, a final full-app security review | `flutter build apk` + iOS archive succeed; release-manifest audit clean; `@refine` over the whole `lib/` |

**After v1:**
- **v2 (decided): auth-bound keys** (§6.1). This is a 🔒 milestone: native Kotlin/Swift key code, a v1→v2 DEK migration, and invalidation and re-enrolment flows.
- Optional opt-in E2EE sync (CLAUDE.md rules apply).

---

## 12. Tooling evolution

The guard (`.claude/skills/verify/scripts/guard.dart`) grows with the milestones:
- **M1**: fail on `DateTime.now(` anywhere under `lib/core/`.
- **M5**: turn the `FLAG_SECURE` and backup TODOs into ERRORs.
- **M4/M7**: an optional `--release` mode that inspects `build/app/intermediates/merged_manifests/` (or `aapt dump permissions` on the built APK) for network permissions.
- When a rule here becomes binding, move it into the matching `.claude/rules/` file and delete it from this plan.

---

## 13. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A plugin merges `INTERNET` (ML Kit) | Breaks the offline guarantee | Merged-manifest audit, `tools:node="remove"`, alternative scanner (§9) |
| Keystore key invalidated or lost | Vault unreadable, accounts lost | Unreadable-vault screen, keep the old file, prominent export reminder after adding accounts |
| Argon2id too slow on low-end Android | Export/import feels stuck | Isolate + progress UI, calibrated params stored in the header, optional `cryptography_flutter` |
| HOTP counter desync | Codes rejected by the service | Persist before display, a manual counter edit in `account_edit` |
| Device clock wrong | TOTP codes rejected | Clock-skew hint (§9); there is no network fix by design |
| Stale iOS Keychain after reinstall | Confusing state | Install-ID check on first launch (§6) |

---

## 14. Open questions

All resolved: **Q1** the PIN is mandatory (D8) · **Q2** auth-bound keys in v2 (D6, §6.1) · **Q3** `minSdk = 30` (D9) · **Q4** phones only (D10).
