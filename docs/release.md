# Releasing CypherAuth (Android)

App ID: **`com.ruizchristian.cypherauth`**. It is permanent: Android only installs an update with
the same ID, signed by the same key. Changing either later makes it a different app, and the
vault on existing installs is not carried over.

## One-time: create the signing key

CypherAuth has its own key (not shared with other apps), so a leak of one key never affects
another app. Run this yourself (`!` in Claude Code, or any terminal) and choose a strong password:

```
keytool -genkeypair -v -keystore android/app/upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10000 -alias upload
```

Then create `android/key.properties` (gitignored, like the `.jks`):

```
storePassword=<your password>
keyPassword=<your password>
keyAlias=upload
storeFile=upload-keystore.jks
```

**Back up the `.jks` file and its password somewhere safe and offline** (for example a password
manager). If it is lost, no update can ever be published for existing installs.

## One-time: GitHub secrets (for CI-built APKs)

In the repository: Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the keystore as Base64, e.g. PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks")) \| Set-Clipboard` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |

Or with the GitHub CLI: `gh secret set ANDROID_KEYSTORE_PASSWORD` and
`gh secret set ANDROID_KEYSTORE_BASE64 < keystore.b64`.

## Building

- **Locally:** `.\scripts\build-apk.ps1` runs the format check, analyze, tests and the guard,
  builds, audits the release permissions, and writes `dist\CypherAuth-<version>-<build>.apk`.
  Without `android/key.properties` it warns and produces a debug-signed APK (fine for testing,
  but it cannot update a properly signed install).
- **CI** (`.github/workflows/android.yml`): pull requests run the checks. Pushes to `main`,
  published releases and manual runs also build a signed APK and upload it as an artifact;
  for releases it is attached to the GitHub release. CI fails if the signing secrets are
  missing, rather than publishing a debug-signed APK.
- On-device tests (`integration_test/`) need an emulator and are run locally:
  `flutter test integration_test -d <device>`.

The build number is the UTC time (`yyMMddHH`) in both places, so every build installs as an
update. Bump `version:` in `pubspec.yaml` for user-visible releases.

## Before publishing

- iOS is not built yet (needs a Mac): iOS export of backups, the Universal-Clipboard opt-out
  and the app-switcher cover are untested there (see docs/system-plan.md).
