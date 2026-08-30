# KeyHollow Argon2id Dependency Review — Draft 0.1

## Current integration candidate

KeyHollow currently integrates `tmthecoder/Argon2Swift` version `1.0.4` through Swift Package Manager.

Why it is being used for the development build:

- exposes Argon2id v1.3;
- wraps the Password Hashing Competition reference Argon2 C implementation rather than inventing a KeyHollow-specific primitive;
- supports iOS through Swift Package Manager;
- permits raw 32-byte key output needed for a wrapping-key design.

## Important release caveat

The Swift wrapper's most recent release is from 2023 and its package manifest references the upstream Argon2 package by branch. That is acceptable for a development candidate but **not sufficient as-is for KeyHollow's production security release gate**.

Before App Store release:

1. Resolve and pin the complete transitive dependency graph to exact reviewed commits.
2. Review upstream Argon2 changes represented by the pinned commit.
3. Run RFC/test-vector verification in KeyHollow CI.
4. Benchmark Argon2id parameters on the oldest supported iPhone.
5. Review memory behavior and denial-of-service implications.
6. Run dependency/vulnerability scanning.
7. Include this KDF path in the independent security review.

## Apple CryptoKit status

CryptoKit supplies KeyHollow's AES-GCM, HKDF, HMAC, and SHA-256 building blocks but does not currently provide a released Argon2id API that KeyHollow can rely on. A proposed Argon2id addition to Apple's open-source Swift Crypto project is not treated as a production dependency until it is actually merged/released and evaluated.

## Parameter starting point

Development parameters are currently:

- Argon2id v1.3
- memory: 64 MiB
- iterations: 3
- parallelism: 2
- output: 32 bytes

These are starting values only. Production values must be benchmarked and reviewed rather than copied blindly.
