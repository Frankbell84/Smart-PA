# KeyHollow Encrypted Vault Compatibility Vectors

Status: normative for `.khvault` format version 1. These values contain no
production secrets. They exist so refactoring, dependency changes, and future
readers cannot silently alter the authenticated byte representation.

Hex values may be wrapped for readability; whitespace is not part of a value.

## Header associated-data vector

- Archive version: `1`
- KDF: `argon2id-v1.3`
- Memory: `65536` KiB
- Iterations: `3`
- Parallelism: `2`
- Output: `32` bytes
- Salt: `000102030405060708090a0b0c0d0e0f`

Expected AAD:

```text
6b6579686f6c6c6f772e656e637279707465642d7661756c742e68656164657200
6172676f6e3269642d76312e33000100000000000100030000000200000020000000
000102030405060708090a0b0c0d0e0f
```

The compatibility test uses recovery code
`0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ`. Its test-only wrapping key is
SHA-256 of the production domain-separated credential bytes followed by the
salt:

```text
59424afc815b49e262eb83facdf13423dd8d4e5674d9b75b079c26291fdf1842
```

This SHA-256 derivation is only a fast unit-test fixture. Production archives
must use Argon2id with the profile above.

The fixed AES-GCM nonce is `000102030405060708090a0b`. Production code must
never provide a fixed nonce. With the exact plaintext fixture in
`PortableArchiveSecurityTests`, the expected CryptoKit combined value is:

```text
000102030405060708090a0b9df97ec5522e85a15d3a5213bdec2ea97ef96ca3
9ea1d21fefe583323cd169598daf68c1db3a3d572d41a4d387e2bd59f7b17cb3
4d1786fc926e1fc44b778c590dde22b86e69918fbc9d395dd7482b846ed8f885
9090ff1b3113ef64738434b03770db40b2a027b6dc16707f3613d849f9ce8305
ebb8b91168d0ff6e146b9acca68e251ec0ad3ae8f4daf8ea9f91b1934cd746c7
32879d4d4070280589a6353a0203a8d0413e3c7b860d1a58c048f55a814ccdc
aa13aa04f3b2ef9a8412c4c33cdf6f8457d02ca87ab3851cbe92fed68649a953
55d4d6cad5bfc1e4b44a9500e2d13b13f1d67e192ea8495c8e398b8086225ba
4127297c0030ff4c24180faebf26b8e04534d4205dcfed5eaa0424c7e6eba377
bf01fea325f3b2150b
```

## Content-chunk vector

- Archive ID: `00112233-4455-6677-8899-aabbccddeeff`
- Sequence: `7`
- Final flag: `1`
- Content key: bytes `20` through `3f`
- Nonce: bytes `a0` through `ab`
- Plaintext UTF-8: `KeyHollow chunk vector` followed by line feed

Expected AAD:

```text
6b6579686f6c6c6f772e656e637279707465642d7661756c742e636f6e74656e
742d6368756e6b2e76310030303131323233332d343435352d363637372d383839
392d61616262636364646565666600070000000000000001
```

Expected CryptoKit combined value:

```text
a0a1a2a3a4a5a6a7a8a9aaab3559dd7cabbbecc5d608ced253331d86e71aa273
53c62cb860d30739de0ee6010cdbe5c75d4698
```

## Change policy

- A version 1 compatibility vector must never be edited to make a failing test
  pass.
- A deliberate format change requires a new version, new vectors, a migration
  plan, and explicit backwards-compatibility tests.
- Random nonces and keys remain mandatory in production. Fixed values appear
  only in deterministic tests.
- The RFC 9106 Argon2id vector in `SecurityCryptoTests` independently verifies
  the vendored Argon2id implementation, including secret and associated-data
  handling.
