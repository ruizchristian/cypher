---
paths:
  - "lib/**/*.dart"
  - "test/**/*.dart"
---

# Dart / Flutter coding standards

- `dart format` output is canonical. `flutter analyze` must report zero issues (the lints are `flutter_lints` via `analysis_options.yaml`). Fix the cause instead of adding `// ignore:`. If an ignore is truly needed, it gets a comment explaining why.
- Files are `snake_case.dart`. A file holds one public widget or class plus its private helpers. Test files mirror the lib path with a `_test.dart` suffix.
- Prefer `final` locals and `const` constructors and widgets. Avoid `dynamic`, `late` without a guaranteed initializer, and `!` without a preceding check.
- Expected failures (invalid Base32, malformed URI, wrong export password) return a typed result, typically a `sealed class` matched with an exhaustive `switch`. Exceptions are for programmer errors and truly unexpected I/O failures.
- Error and result types describe *what* was wrong ("invalid character in secret") and never echo the offending input, because the input may contain the secret.
- Never use `print`. `debugPrint` and `dart:developer` `log` are allowed only with non-sensitive static messages, and must not run in release builds for anything account-related.
- Widgets: break up a build method once it stops fitting on a screen. Check `context.mounted` after every `await` before using `context`. Dispose every controller, `Timer`, `StreamSubscription` and `AnimationController`.
- User-facing strings sit in one place per feature, ready for later localization. Interactive elements get `Semantics`/`tooltip` labels, and countdown indicators expose their remaining time to screen readers.
- Comments explain *why* (RFC section references are welcome in `core/otp/`). Do not comment what the code plainly does.
- Remove `flutter create` template code (the counter demo) when replacing it. Don't leave it beside real code.
