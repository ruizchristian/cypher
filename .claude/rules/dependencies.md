---
paths:
  - "pubspec.yaml"
  - "pubspec.lock"
---

# Dependency rules

Before adding or upgrading a package:

1. **Need**: could ~100 lines of in-house Dart do it? OTP, Base32 and `otpauth` parsing are in-house by policy.
2. **Network**: the package and its transitive dependencies must not make network calls at runtime, collect telemetry, or need the `INTERNET` permission. After adding it, run `flutter pub deps --style=compact` and inspect every new transitive package.
3. **Denylist** (the guard script fails on these): Firebase (`firebase_*`, `cloud_firestore`), Sentry, Crashlytics, Bugsnag, Datadog, Amplitude, Mixpanel, PostHog, Segment, AppCenter, ad SDKs (`google_mobile_ads`, etc.). The guard only warns on general HTTP clients (`http`, `dio`): those are acceptable as unused transitive dependencies, but are never used directly.
4. **Trust**: prefer verified publishers, active maintenance, a permissive licence and a small API surface. For crypto, use `cryptography` or `pointycastle` (with `crypto` for HMAC/SHA). Never use unmaintained or home-made crypto.
5. **Platform footprint**: check which Android permissions and iOS entitlements the plugin merges into the build. Inspect the merged manifest at `build/app/intermediates/merged_manifests/` after `flutter build apk`.
6. **Record**: justify the package in the change report (purpose, alternatives, network status), and commit `pubspec.lock` with it.

Use caret constraints (`^x.y.z`). Upgrades are their own change, not bundled with features.
