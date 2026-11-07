---
name: otp-reference
description: Authoritative reference for Cypher's OTP core — RFC 4226 HOTP and RFC 6238 TOTP test vectors (SHA1/SHA256/SHA512), RFC 4648 Base32 vectors, the HOTP algorithm steps, and the otpauth:// Key URI format with defaults and edge cases. Use when implementing, testing or debugging code generation, Base32 decoding, or otpauth URI parsing.
user-invocable: false
---

# OTP reference

Copy vectors verbatim into tests. Never derive expected values from the implementation under test.

## HOTP algorithm (RFC 4226 §5)

1. `C` = the counter as an **8-byte big-endian** unsigned integer.
2. `HS = HMAC-H(K, C)`, where `K` is the raw secret bytes (Base32-decoded) and H is SHA1, SHA256 or SHA512.
3. Dynamic truncation: `offset = HS[HS.length - 1] & 0x0f`; `bin = (HS[offset] & 0x7f) << 24 | HS[offset+1] << 16 | HS[offset+2] << 8 | HS[offset+3]`.
4. `code = bin % 10^digits`, left-padded with zeros to `digits` characters.

TOTP (RFC 6238 §4): `C = floor((unixSeconds - T0) / period)`, with `T0 = 0` and `period = 30` by default.

## RFC 4226 Appendix D — HOTP, SHA1, 6 digits

Secret (ASCII) `12345678901234567890` = Base32 `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`

| Counter | Code |
|---|---|
| 0 | 755224 |
| 1 | 287082 |
| 2 | 359152 |
| 3 | 969429 |
| 4 | 338314 |
| 5 | 254676 |
| 6 | 287922 |
| 7 | 162583 |
| 8 | 399871 |
| 9 | 520489 |

## RFC 6238 Appendix B — TOTP, 8 digits, period 30, T0 = 0

Each algorithm uses a seed of a different length (ASCII):

- SHA1: `12345678901234567890` (20 bytes)
- SHA256: `12345678901234567890123456789012` (32 bytes)
- SHA512: `1234567890123456789012345678901234567890123456789012345678901234` (64 bytes)

| Unix time (s) | Counter (hex) | SHA1 | SHA256 | SHA512 |
|---|---|---|---|---|
| 59 | 0000000000000001 | 94287082 | 46119246 | 90693936 |
| 1111111109 | 00000000023523EC | 07081804 | 68084774 | 25091201 |
| 1111111111 | 00000000023523ED | 14050471 | 67062674 | 99943326 |
| 1234567890 | 000000000273EF07 | 89005924 | 91819424 | 93441116 |
| 2000000000 | 0000000003F940AA | 69279037 | 90698825 | 38618901 |
| 20000000000 | 0000000027BC86AA | 65353130 | 77737706 | 47863826 |

`07081804` exercises leading-zero padding. `20000000000` exceeds 32 bits, so the counter math must use 64-bit integers.

## RFC 4648 §10 — Base32 vectors

| Input | Base32 |
|---|---|
| `""` | `""` |
| `f` | `MY======` |
| `fo` | `MZXQ====` |
| `foo` | `MZXW6===` |
| `foob` | `MZXW6YQ=` |
| `fooba` | `MZXW6YTB` |
| `foobar` | `MZXW6YTBOI======` |

The alphabet is `A–Z2–7`. When decoding user input, accept lowercase and missing padding, strip spaces and hyphens, and reject any other character (`0`, `1`, `8`, `9` are invalid). Reject an empty secret.

## Key URI format (`otpauth://`)

```
otpauth://TYPE/LABEL?secret=SECRET&issuer=ISSUER&algorithm=SHA1&digits=6&period=30
otpauth://hotp/LABEL?secret=SECRET&counter=0
```

- `TYPE` is `totp` or `hotp` (case-insensitive). `counter` is **required** for `hotp` and ignored for `totp`.
- `LABEL` is percent-encoded `issuer:account` or just `account`. Split on the first `:` (or its encoded form `%3A`), and trim spaces after the colon. If both the label prefix and the `issuer` parameter are present, prefer `issuer` (they normally match).
- Defaults: `algorithm=SHA1`, `digits=6`, `period=30`. Accept digits 6–8, period > 0, and algorithm `SHA1|SHA256|SHA512` (case-insensitive). Reject anything else with a typed error that does not echo the URI.
- `secret` is Base32, usually unpadded. Unknown parameters (`image`, `color`) are ignored.

## `otpauth-migration://offline?data=...`

This is Google Authenticator's export format: `data` is URL-encoded standard Base64 of a protobuf `MigrationPayload`, containing repeated `OtpParameters { bytes secret = 1; string name = 2; string issuer = 3; Algorithm algorithm = 4; DigitCount digits = 5; OtpType type = 6; int64 counter = 7; }` plus `version`, `batch_size`, `batch_index` and `batch_id`. The enums use 0 for unspecified: Algorithm 1 = SHA1, 2 = SHA256, 3 = SHA512, 4 = MD5 (reject); DigitCount 1 = six, 2 = eight; OtpType 1 = HOTP, 2 = TOTP. The `secret` field holds raw bytes, not Base32. A large export is split across several QR codes (`batch_size` > 1).
