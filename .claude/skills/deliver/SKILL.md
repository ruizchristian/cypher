---
name: deliver
description: Structured delivery of a Cypher change — analyze, plan, implement, review, test, refine — ending with a verified report. Use when the user runs /deliver for a feature, fix or refactor that needs more than a one-file edit.
argument-hint: <what to build or fix>
disable-model-invocation: true
---

# /deliver — structured change delivery

Task: **$ARGUMENTS**

## 1. Analyze

- Restate the task in one sentence. If it is genuinely ambiguous in a way that changes the design, ask the user one focused question. Otherwise make reasonable calls and state them.
- Read the relevant code and its tests before deciding anything. The repo started as a `flutter create` scaffold, so confirm what actually exists rather than assuming the suggested structure.
- Classify the risk:
  - **trivial**: one or two files, obvious change, no secret or platform impact
  - **standard**: a multi-file feature or fix with no security surface
  - **sensitive**: touches secrets, crypto, secure storage, export/import, app lock, clipboard or screenshot protection, manifests/entitlements, or `pubspec.yaml`

## 2. Plan (standard and sensitive)

Write a short plan: the files to create or modify, new cross-layer interfaces (Dart signatures), data-format or migration impact, new packages (checked against `.claude/rules/dependencies.md`), and the test plan. For **sensitive** changes, also trace the secret's flow (where it enters, rests and leaves) and **get the user's go-ahead on the plan before implementing**.

## 3. Implement

Follow `.claude/rules/` (architecture layering, coding standards, security, performance). Keep the change focused, reuse existing code, and ship tests with every behaviour change. Any OTP, Base32 or URI work is tested against the `otp-reference` vectors.

## 4. Review your own diff

Re-read every changed file as a reviewer would, not as its author:

- **Correctness**: boundary values (time-step edges, 64-bit counters), `context.mounted` after `await`, disposed controllers and timers.
- **Edge cases**: empty, malformed or huge input; first run; locked versus unlocked; backgrounding mid-flow.
- **Architecture and performance**: the rules files.
- **Security** (sensitive changes): no secret in logs, `toString`, exception text, route arguments or plaintext storage; crypto parameters match `.claude/rules/security.md`.

## 5. Test and refine

Run `/verify`. For larger changes, delegate a cleanup pass over the changed files to the `refine` agent (give it the file list), then re-run `/verify` yourself. Fix what fails, at the root cause: never weaken a test or add `// ignore:`. Re-run it. If a problem can't be resolved after two attempts, stop and report it to the user rather than looping.

## 6. Report

```
## Done: <task>
**Changes** — <file: one-line summary, per file>
**Decisions** — <important choices and why>
**Verification** — format / analyze / test / guard: <actual results>
**Follow-ups** — <remaining risks or next steps, or "none">
```

Never claim tests passed or a feature works without having run the check in this session. If a check could not be run (no device, missing SDK), say so explicitly.
