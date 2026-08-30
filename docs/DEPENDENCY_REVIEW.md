# KeyHollow Argon2id Dependency Review — Draft 0.3

## Current integration candidate

KeyHollow vendors the source of `MarlonJD/argon2id-swift-native` version `0.1.1` directly in `KeyHollow/ThirdParty/Argon2id/`.

Upstream source identity used for the vendored implementation:

- release/tag: `0.1.1`
- upstream commit: `b8f2bc586f5c032628bb6c2618011e61b3df23cf`
- upstream `Argon2id.swift` blob: `1b786556c1720b9150064cbf1424533db24dce4e`
- license: MIT; the upstream copyright/license text is retained at `KeyHollow/ThirdParty/Argon2id/LICENSE`

Why it is being used for the development build:

- implements Argon2id v1.3 / RFC 9106;
- is a small dependency-free Swift implementation;
- supports the KeyHollow iOS target;
- exposes raw derivation and a CryptoKit `SymmetricKey` API;
- upstream includes RFC 9106/BLAKE2b test vectors.

## Local compatibility patch

The 0.1.1 source triggered an Xcode 16.4 type-checker timeout in `Data.littleEndianUInt64(at:)`, where eight shifted `UInt64` expressions were combined in one large expression.

KeyHollow's vendored copy makes one mechanical compatibility change: the eight byte/shift expressions are assigned to `b0` through `b7` and then ORed together. The byte offsets, shifts, types, and final bitwise operation are unchanged.

KeyHollow CI contains an RFC 9106 known-answer test so this compatibility edit cannot silently change the expected Argon2id result without failing the build.

## Why the previous dependency approaches were removed

`tmthecoder/Argon2Swift` 1.0.4 could not be resolved as a pinned stable Swift Package dependency because its manifest depended on the upstream Argon2 repository by an unstable branch. KeyHollow CI caught that supply-chain issue and the package was removed rather than weakening dependency pinning.

`argon2id-swift-native` was then added as an exact Swift Package version. Xcode 16.4 exposed the compiler timeout described above. Vendoring the exact reviewed source plus a minimal documented patch gives KeyHollow a deterministic build graph and makes the local change directly auditable.

## Important release caveat

Vendoring and known-answer tests do not constitute an independent cryptographic audit. This implementation remains a **production security release gate**.

Before App Store release:

1. Independently review the vendored source against upstream 0.1.1 and the documented patch.
2. Keep RFC 9106 known-answer verification in KeyHollow CI.
3. Add additional cross-implementation Argon2id vectors.
4. Benchmark Argon2id parameters on the oldest supported iPhone.
5. Review memory behavior and denial-of-service implications.
6. Complete dependency/license and vulnerability review.
7. Include the KDF and key-wrapping path in an independent security audit.

## Apple CryptoKit status

CryptoKit supplies KeyHollow's AES-GCM, HKDF, HMAC, and SHA-256 building blocks but does not supply the Argon2id KDF KeyHollow requires for numeric-passcode hardening.

## Parameter starting point

Development parameters are currently:

- Argon2id v1.3
- memory: 64 MiB
- iterations: 3
- parallelism: 2
- output: 32-byte symmetric key

These are development starting values only. Production values must be benchmarked and reviewed rather than copied blindly.
