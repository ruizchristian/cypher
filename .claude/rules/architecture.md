---
paths:
  - "lib/**/*.dart"
---

# Architecture rules

## Layers and dependency direction

`app → features → data → core`. A layer may import only from the layers to its right. Nothing imports from `app/` except `main.dart`.

| Layer | Contains | May import Flutter? |
|---|---|---|
| `core/otp/` | HOTP/TOTP, Base32, `otpauth://` and `otpauth-migration://` parsing | **No.** Pure Dart only; enforced by the guard script |
| `core/security/` | KDF, AES-GCM export format, PIN hashing (pure Dart); interfaces for platform services | Pure parts no. Plugin adapters (secure storage, `local_auth`, clipboard, `FLAG_SECURE` channel) live in `core/security/platform/` and implement interfaces defined in `core/security/` |
| `data/` | `Account` model, repository, persistence mapping, schema versioning | Only through `core/security/` interfaces |
| `features/<name>/` | Screens, widgets, and that feature's state | Yes |
| `app/` | `MaterialApp`, routing, theme, lock gate, top-level providers | Yes |

## Rules

- Features read and write accounts only through the repository in `data/`, never through secure storage or a plugin directly.
- Platform services are always behind an interface with an in-memory fake in `test/` so the core and data layers are unit-testable.
- Time is injected (a clock interface or `DateTime Function()`). `core/` never calls `DateTime.now()` directly.
- Models are immutable (`final` fields, `copyWith`). The secret is a `Uint8List` or a dedicated value type whose `toString()` is redacted, never a plain `String` field that ends up in generated `toString`/`==` output.
- Every persisted or exported structure carries a schema/format version, and readers handle older versions.
- One feature must not import another feature's internals. Shared widgets go in `features/shared/` (or `app/` for app-wide chrome).

## Recorded decisions (details in `docs/system-plan.md` §3)

- **State: `flutter_riverpod` 3.x, without code generation** (no `riverpod_generator`/`build_runner`). The app root is wrapped in `ProviderScope` in `main.dart`. Tests override providers through `ProviderScope(overrides: [...])` instead of reaching into globals. Providers that hold secrets or the unlocked vault are torn down when the app locks.
- **Routing: plain `Navigator`** with `onGenerateRoute` in `lib/app/routes.dart`. Route names live in `AppRoutes`. Arguments carry IDs, never secrets or URIs. No `go_router`, and no deep links.
- **The PIN is mandatory**; biometrics are an optional shortcut on top.
- **Platforms: Android and iOS only**, with Android `minSdk = 30`. Don't add desktop or web code paths.
