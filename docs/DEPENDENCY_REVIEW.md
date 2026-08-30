# KeyHollow Argon2id Dependency Review — Draft 0.2

## Current integration candidate

KeyHollow currently integrates `MarlonJD/argon2id-swift-native` version `0.1.1` through Swift Package Manager using an exact version.

Why it is being used for the development build:

- implements Argon2id v1.3 / RFC 9106;
- is a small dependency-free Swift package rather than a wrapper that pulls an unpinned transitive branch;
- supports iOS 13+ and therefore the KeyHollow iOS 17 target;
- exposes a CryptoKit `SymmetricKey` derivation API;
- includes RFC 9106/BLAKE2b test vectors in its own test suite.

## Why the previous candidate was removed

The previous `tmthecoder/Argon2Swift` 1.0.4 package could not be resolved as a pinned stable Swift Package dependency because its manifest depended on the upstream Argon2 repository by an unstable branch. KeyHollow CI caught that supply-chain issue before release work proceeded. The package was removed rather than weakening dependency pinning.

## Important release caveat

A pinned dependency is not automatically a reviewed dependency. `argon2id-swift-native` is still a relatively new implementation and remains a **production security release gate** until independently reviewed.

Before App Store release:

1. Pin and record the exact reviewed package source/version.
2. Run independent Argon2id RFC/test-vector verification in KeyHollow CI.
3. Benchmark Argon2id parameters on the oldest supported iPhone.
4. Review memory behavior and denial-of-service implications.
5. Run dependency/vulnerability and license review.
6. Review the package's BLAKE2b and Argon2id implementation rather than relying only on its included tests.
7. Include this KDF path in the independent security audit.

## Apple CryptoKit status

CryptoKit supplies KeyHollow's AES-GCM, HKDF, HMAC, and SHA-256 building blocks but does not provide the Argon2id API KeyHollow requires for numeric-passcode hardening.

## Parameter starting point

Development parameters are currently:

- Argon2id v1.3
- memory: 64 MiB
- iterations: 3
- parallelism: 2
- output: package default CryptoKit symmetric-key size

These are development starting values only. Production values must be benchmarked and reviewed rather than copied blindly.
