---
paths:
  - "lib/features/**/*.dart"
  - "lib/app/**/*.dart"
  - "lib/core/**/*.dart"
---

# Performance rules

- **One ticker for all codes.** Drive countdowns and code refreshes from a single app-level periodic tick (aligned to the second), not a `Timer` per list tile. Pause it when the app is backgrounded or locked.
- **Compute a code once per time step**, not per frame or per rebuild. Cache `(accountId, timeStep) → code` and recompute only when the step changes. Countdown rings animate from the remaining fraction and don't regenerate the HMAC.
- **Keep heavy crypto off the UI isolate.** Argon2id/PBKDF2 for export, import and PIN checks runs in `Isolate.run`. HOTP/TOTP generation itself is cheap and can stay on the main isolate.
- **Read secure storage once.** Load accounts into memory at unlock and write through on change. Never read secure storage from `build()` or per tick. Drop the in-memory copy when the app locks.
- **Lists**: use `ListView.builder` / `ReorderableListView.builder` with stable keys (the account ID), `const` sub-widgets, and narrow state selection so one tick rebuilds only the code and countdown widgets, not the whole list. Search filters in memory on every keystroke; add debouncing only if profiling shows a need.
- **Scanner**: start the camera only while the scanner screen is visible, stop it after a successful scan and in `dispose`, and stop processing frames once a valid `otpauth` payload is accepted.
- Measure before optimizing anything beyond these rules (`flutter run --profile` plus DevTools). Don't add caching layers speculatively.
