---
paths:
  - "lib/**/*.dart"
  - "android/app/src/main/**"
  - "ios/Runner/**"
---

# Security implementation guide

`CLAUDE.md` states *what* is required. This file covers *how* to do it in this codebase.

## Secrets at rest

- Store secrets with `flutter_secure_storage` (Android Keystore, iOS Keychain), or in an encrypted database whose key is the only thing in secure storage.
- iOS: use a `*_this_device` Keychain accessibility class (e.g. `first_unlock_this_device`) so secrets are not synced to iCloud or restored onto another device.
- Android: exclude app data from Auto Backup and device transfer (`android:allowBackup="false"`, or `dataExtractionRules` / `fullBackupContent` that exclude everything). The user's backup path is the encrypted export.
- Non-secret metadata (issuer, label, order, icon) may live outside secure storage, but must never contain the secret or the full `otpauth://` URI.

## Secrets in memory and in output

- The secret type's `toString()` returns a redacted placeholder. Code generators (`freezed`, `equatable`, `json_serializable`) include every field, so exclude the secret or wrap it.
- Parse errors for URIs, QR payloads and import files never include the input text.
- Don't pass secrets through route arguments or deep-link strings that end up in navigation logs. Pass an account ID instead.

## Screen and clipboard

- Android: set `WindowManager.LayoutParams.FLAG_SECURE` in `MainActivity` (`android/app/src/main/kotlin/com/cypher/cypher/MainActivity.kt`) for the whole app. This also blanks the recents thumbnail.
- iOS: cover the UI with a privacy overlay when `AppLifecycleState` becomes `inactive`, so the app-switcher snapshot shows no codes.
- Clipboard: copy only the current code, never the secret. After about 30 s, clear the clipboard only if it still holds the code Cypher put there. On Android 13+ mark the clip as sensitive (`ClipDescription.EXTRA_IS_SENSITIVE`, via a small platform channel) so it is hidden from the clipboard preview.

## App lock

- Lock on cold start and when resuming after a configurable background timeout. No code or account metadata renders before unlock.
- Biometrics use `local_auth`. Keep a PIN as the fallback, so the lock still works when the device has no biometrics.
- Store the PIN only as a KDF hash with a random salt (Argon2id or PBKDF2). Compare in constant time. Throttle failed attempts with escalating delays that survive an app restart.

## Export / import format

- KDF: Argon2id preferred (for example 64 MiB memory, 3 iterations, parallelism 1, adjustable). PBKDF2-HMAC-SHA256 with ≥ 600 000 iterations is the fallback. Store the parameters in the file header.
- Encryption: AES-256-GCM with a fresh random 16-byte salt per export and a fresh 12-byte nonce per encryption. The header (magic, format version, KDF params, salt, nonce) is passed as AAD.
- Run the KDF off the UI isolate (`Isolate.run`).
- A wrong password and a corrupted file both surface as the same generic "could not decrypt" error.
- Imports are untrusted input. Bound the file size and account count, validate every field (Base32 alphabet, digits 6–8, period > 0, a known algorithm), and reject the whole import on structural errors instead of partially importing.

## Network

- No network permission or entitlement outside the debug and profile variants. The guard script checks the release Android manifest.
- Camera permission (scanner) is the only runtime permission the app should need. Give it a clear iOS `NSCameraUsageDescription`.
