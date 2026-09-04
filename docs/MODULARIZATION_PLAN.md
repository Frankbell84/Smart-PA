# KeyHollow Modularization Plan

## Objective

Strengthen KeyHollow's existing source boundaries with independently compiled
modules while preserving the validated Build 12 behavior and encrypted-data
compatibility.

This phase is structural only. It does not add user-facing features.

## Dependency direction

The dependency graph must remain one-way:

1. App composition and UI depend on feature services.
2. Feature services depend on vault-domain interfaces.
3. Vault-domain code depends on the cryptographic core.
4. The cryptographic core depends only on Apple foundation and cryptography
   frameworks plus the reviewed Argon2id implementation.

No core module may import SwiftUI, UIKit, Photos, PhotosUI, networking, cloud,
analytics, advertising, authentication, or purchase SDKs.

## Incremental extraction sequence

### Milestone 1: Cryptographic core

- Compile `CryptoBox` and the vendored Argon2id implementation as
  `KeyHollowCryptoCore`.
- Link the app and security tests against the new module.
- Preserve all existing algorithms, parameters, inputs, outputs, and errors.
- Require the architecture check to prove the compiled boundary remains in the
  project configuration.
- Status: validated by the Mac simulator build, complete regression suite, and
  Swift security analysis.

### Milestone 2: Vault domain

- Extract key derivation, passcode policy, locator, envelope, and vault
  credential persistence behind narrow public interfaces.
- Remove accidental error coupling between random-key generation and the
  device-secret adapter.
- Keep Apple Keychain access in a platform adapter rather than the pure domain.
- Status: implemented on the isolated branch and awaiting Mac validation.

### Milestone 3: Encrypted photo storage

- Extract encrypted photo models, key scheduling, manifests, and blob storage.
- Keep Photos and PhotosUI imports outside this module.
- Preserve encrypted on-device formats byte-for-byte.

### Milestone 4: Portable vault transfer

- Extract `.khvault` container, payload, security, streaming, journal, and
  rollback behavior.
- Preserve archive compatibility byte-for-byte.
- Depend only on vault-domain interfaces and the cryptographic core.

### Milestone 5: Platform adapters and app composition

- Isolate Photos permission/import/export/delete behavior as an adapter.
- Keep SwiftUI views and navigation in the app target.
- Construct concrete dependencies only at the app composition boundary.

## Gate after every milestone

- Project generation succeeds.
- All modules compile under strict concurrency.
- Architecture-boundary enforcement passes.
- Existing unit, lifecycle, transfer, security, and launch tests pass.
- No encrypted format, key derivation parameter, or customer-visible behavior
  changes.
- The milestone remains isolated until its Mac validation is green.

## Final gate

- Complete simulator regression and Swift security analysis.
- Upload the modular candidate to internal TestFlight.
- Repeat the physical-iPhone test matrix.
- Merge only after the owner confirms the modular build behaves like the
  validated Build 12 baseline.

