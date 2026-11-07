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

## Decisions not yet made

State management is not chosen yet (`flutter_riverpod` is the suggested candidate). The first change that introduces it must record the choice and its conventions here, replacing this section.
