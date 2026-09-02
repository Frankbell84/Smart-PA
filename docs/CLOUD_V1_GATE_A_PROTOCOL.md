# KeyHollow Cloud v1 Gate A Protocol

Status: implementation draft. No production use, credentials, provider account,
or deployment is authorized until deterministic vectors, negative tests, and
independent review close Gate A.

This protocol backs up the existing True Core photo-vault model while keeping
the server content-agnostic. Future folders and file types require a new
encrypted manifest version, not a new storage service or replacement of
existing backups.

## Security properties

Cloud v1 must provide all of the following:

- The server can authenticate accounts, enforce subscription and quota, and
  authorize opaque objects, but cannot decrypt vault content or manifests.
- Each account and vault has independent random key material.
- Every encrypted value uses AES-256-GCM with a fresh CryptoKit-generated
  96-bit nonce.
- Every key derivation and AEAD operation is purpose- and context-bound.
- A backup generation is immutable after commit.
- Corruption, truncation, reordering, substitution, stale-parent commits, and
  unsupported versions fail closed.
- Restore publishes no local plaintext or vault state until all objects and the
  complete manifest authenticate.

## Canonical primitives

Protocol encoders must not use ordinary JSON encoding as a canonical byte
representation. The Gate A implementation uses a strict length-delimited
binary encoding:

| Type | Encoding |
|---|---|
| Integer | Unsigned little-endian fixed width |
| Boolean | UInt8; only `0` and `1` are accepted |
| UUID | The 16 RFC 4122 bytes in displayed byte order, never a platform-memory dump |
| Timestamp | UInt64 milliseconds since Unix epoch UTC |
| Digest | Exactly 32 SHA-256 bytes |
| Byte string | UInt32 byte length followed by exact bytes |
| UTF-8 string | UInt32 byte length followed by valid NFC UTF-8; no NUL |
| Optional | UInt8 presence flag followed by the value when present |
| Array | UInt32 count followed by exactly that many values |

Readers reject non-canonical values, overflow, duplicate identifiers, lengths
above the active profile, invalid UTF-8, unknown required fields, and trailing
bytes. Writers always emit the newest supported version.

### Bounds profile 1

| Value | Hard protocol ceiling |
|---|---:|
| Recovery or vault-key sealed envelope | 4,096 bytes |
| Encrypted manifest plaintext | 32 MiB |
| Manifest entry count | 200,001 |
| One inner encrypted content object | 1 TiB |
| One generation's declared inner ciphertext | 4 TiB |
| Plaintext cloud-object chunk | 1 MiB |
| UTF-8 local storage name | 255 bytes |

Subscription quota is normally much lower than these parser ceilings. Both are
enforced independently before significant allocation, KDF work, upload grants,
or staging writes.

## Algorithm suite 1

- Randomness: `SecRandomCopyBytes` or CryptoKit secure generation.
- KDF: Argon2id v1.3, profile `1` (65,536 KiB, 3 iterations, parallelism 2,
  16-byte salt, 32-byte output), subject to supported-device benchmarking.
- Key derivation: HKDF-SHA256 with the domain label in `salt` and canonical
  context bytes in `info`.
- Encryption: AES-256-GCM; CryptoKit combined representation
  `nonce || ciphertext || tag`.
- Digest: SHA-256 over the exact stored encrypted object bytes.

Algorithm suite identifiers and KDF profile identifiers are authenticated.
Unknown suites and profiles fail closed.

## Key hierarchy

| Key | Generation | Purpose |
|---|---|---|
| Cloud Recovery Key (CRK) | 20 secure-random bytes, human-encoded with version and checksum | Derive the recovery wrapping key |
| Recovery Wrapping Key (RWK) | Argon2id from canonical CRK | Encrypt the AMK recovery envelope |
| Account Master Key (AMK) | 32 secure-random bytes | Root for wrapping account vault keys |
| Cloud Vault Key (CVK) | 32 secure-random bytes per vault | Root for one vault's manifest and object keys |
| Manifest key | HKDF-SHA256 from CVK | Encrypt one manifest generation |
| Chunk key | HKDF-SHA256 from CVK | Encrypt one object version and chunk |

The Apple subject identifier, subscription receipt, local LowKey, device ID,
vault locator, and server credential are never encryption keys or KDF inputs.

### Human CRK encoding

Encode the 20 random CRK bytes as 32 Crockford Base32 data characters. Display
`KH1-` followed by eight groups of four data characters and a final two-
character checksum group. The checksum is the first ten bits of
SHA-256(`keyhollow.cloud.crk-checksum.v1` || NUL || raw CRK bytes), Crockford
Base32 encoded. The checksum adds typo detection and no entropy.

Canonicalization removes ASCII spaces and hyphens, uppercases, maps `O` to `0`
and `I`/`L` to `1`, requires the `KH1` version prefix, decodes exactly 32 data
characters, and verifies the checksum before running Argon2id. Argon2id password
bytes are ASCII `keyhollow.cloud-recovery-key.v1:`, followed by the canonical
32 data characters. Argon2id associated data is ASCII
`keyhollow.cloud.recovery-rwk.v1`.

### Rotation rules

- CRK rotation derives a new RWK and re-encrypts only the AMK recovery
  envelope.
- AMK rotation rewraps every CVK envelope; it does not re-encrypt content.
- CVK compromise creates a new CVK generation and re-encrypts every retained
  object and manifest for that vault before the prior CVK is retired.
- Provider or signing credentials rotate independently and grant no decryption
  capability.
- Old envelopes remain accepted only for a bounded, explicit migration state;
  there is no silent cryptographic downgrade.

## Recovery envelope version 1

Public authenticated fields, in order:

1. Magic: eight bytes `KHCREC1` plus NUL.
2. Envelope version: UInt32 `1`.
3. Algorithm suite: UInt32 `1`.
4. KDF profile: UInt32 `1`.
5. Account key ID: UUID.
6. Recovery-envelope generation: UInt64.
7. Argon2id salt: 16 bytes.

AAD is the ASCII domain `keyhollow.cloud.recovery-envelope.v1`, NUL, followed
by the exact public fields above. The encrypted plaintext is exactly:

1. Magic: eight bytes `KHCAMK1` plus NUL.
2. Secret version: UInt32 `1`.
3. AMK: 32 bytes.
4. AMK creation timestamp: UInt64 milliseconds.
5. AMK generation: UInt64.

The stored envelope appends a UInt32 sealed length and the AES-GCM combined
value. The sealed length is bounded before KDF execution.

## Cloud vault-key envelope version 1

Public authenticated fields, in order:

1. Magic: eight bytes `KHCVKEY` plus NUL.
2. Envelope version: UInt32 `1`.
3. Algorithm suite: UInt32 `1`.
4. Opaque account ID: UUID.
5. Opaque vault ID: UUID.
6. Vault key ID: UUID.
7. AMK generation: UInt64.

Derive the wrapping key with HKDF-SHA256 from the AMK, salt
`keyhollow.cloud.vault-key-wrapper.v1`, and info equal to the canonical public
fields. AAD is the ASCII domain `keyhollow.cloud.vault-key-envelope.v1`, NUL,
followed by those fields. The encrypted plaintext contains the 32-byte CVK,
CVK creation timestamp, and CVK generation, encoded exactly as:

1. Magic: eight bytes `KHCCVK1` plus NUL.
2. Secret version: UInt32 `1`.
3. CVK: 32 bytes.
4. CVK creation timestamp: UInt64 milliseconds.
5. CVK generation: UInt64.

The stored envelope appends a UInt32 sealed length and the AES-GCM combined
value. Both secret payloads reject unsupported versions and trailing bytes.

## Cloud object container version 1

The provider object is opaque ciphertext with a bounded public framing header.
The public header may contain only opaque identifiers, versions, sizes, and
chunk state.

| Field | Encoding |
|---|---|
| Magic | Eight bytes `KHCOBJ1` plus NUL |
| Container version | UInt32 `1` |
| Algorithm suite | UInt32 `1` |
| Purpose | UInt8: `1` manifest, `2` content |
| Account ID | UUID |
| Vault ID | UUID |
| Object ID | UUID |
| Object version | UInt64 |
| Plaintext byte count | UInt64 |
| Plaintext chunk size | UInt32 |
| Chunk count | UInt32 |

Each following frame is `sequence: UInt32`, `final: UInt8`,
`plaintextLength: UInt32`, `sealedLength: UInt32`, and AES-GCM combined bytes.
Only one final frame is allowed, it must be last, and no bytes may follow it.

Derive each frame key using HKDF-SHA256 from the CVK, salt
`keyhollow.cloud.object-chunk-key.v1`, and info equal to purpose, object ID,
object version, and sequence in canonical encoding. Frame AAD is the ASCII
domain `keyhollow.cloud.object-chunk.v1`, NUL, followed by the complete public
object header, sequence, final flag, and declared plaintext length.

Manifest and content purposes derive different keys even if all opaque
identifiers collide. Production callers cannot provide a nonce.

## Encrypted CloudManifestV1 plaintext

The manifest is encrypted as a purpose-`manifest` cloud object. Its plaintext
contains, in order:

| Field | Encoding and rule |
|---|---|
| Magic | Eight bytes `KHCMAN1` plus NUL |
| Manifest version | UInt32 `1` |
| Account ID | UUID; must match object AAD |
| Vault ID | UUID; must match object AAD |
| Snapshot ID | UUID |
| Generation | UInt64; starts at `1` |
| Parent present | UInt8 |
| Parent | When present: generation UInt64, manifest object ID UUID, stored-object SHA-256 |
| Created at | UInt64 milliseconds |
| Local model version | UInt32; `1` for `VaultPhotoManifest` v1 |
| Entries | Bounded array described below |

Each entry contains:

1. Entry ID: UUID unique within the manifest.
2. Role: UInt8 (`1` local encrypted manifest, `2` encrypted original,
   `3` encrypted thumbnail).
3. Local storage name: bounded NFC UTF-8, encrypted inside the manifest.
4. Cloud object ID: UUID.
5. Cloud object version: UInt64.
6. Inner encrypted byte count: UInt64.
7. Inner encrypted SHA-256: 32 bytes.
8. Stored cloud-object byte count: UInt64.
9. Stored cloud-object SHA-256: 32 bytes.
10. Chunk count: UInt32.

Version 1 requires exactly one role-`1` entry and accepts only the three roles
above. A future generic file/folder model uses a new encrypted manifest
version. It does not add photo-specific fields to the server database.

## Immutable snapshot and commit protocol

1. Authenticate the selected local vault.
2. Capture the exact referenced encrypted files into a protected immutable
   staging snapshot while vault mutations are serialized.
3. Create random opaque cloud object IDs and encrypt staged bytes under the CVK.
4. Reserve quota with a random 128-bit idempotency key and bounded declared
   sizes.
5. Upload each object with a single-object, single-operation grant that binds
   object key, maximum content length, checksum, and an expiration no longer
   than five minutes.
6. Create objects with overwrite prevention. Retry only with the same object ID
   and idempotency key.
7. Commit provider-observed size and checksum; never trust client-only usage.
8. Encrypt and upload `CloudManifestV1` only after every referenced object is
   committed.
9. Atomically advance the current generation only when its authenticated parent
   equals the server's current generation. A stale parent receives a conflict;
   no last-writer-wins fallback is allowed.
10. Download and authenticate the committed manifest before displaying backup
    success.

Abandoned reservations, multipart uploads, and unreferenced objects are
garbage-collected after a bounded rollback window. Cleanup must not delete an
object referenced by any retained committed generation.

## Rollback and freshness boundary

The authenticated generation and parent digest detect rollback only when the
device has a trusted prior checkpoint.

- Every device stores the highest accepted generation and manifest digest in
  device-only protected storage.
- A response below or inconsistent with that checkpoint fails closed.
- The server enforces monotonic compare-and-swap commits to prevent accidental
  rollback and concurrent lost updates.
- A completely new device has no independent freshness checkpoint. Cloud v1
  therefore does not claim cryptographic detection of a malicious server
  presenting an internally consistent older history on first recovery.
- New-device recovery shows the backup timestamp and generation before local
  publication. Trusted-device witnessing or an independent transparency log is
  a later hardening option.

## Locked-device and background behavior

AMK/CVK material remains `WhenUnlockedThisDeviceOnly`, and local encrypted
vault files retain complete file protection.

- Backup and restore run only while protected data and required keys are
  available.
- A background launch while locked records no secret-bearing error and defers.
- Resume state contains only opaque operation IDs, completed chunk numbers,
  bounded sizes, and expiration data.
- UI states the last verified backup time; it never promises immediate
  background completion.
- No accessibility-class downgrade is permitted without a new threat review
  and explicit architecture decision.

## Network, session, and grant rules

- Use App Transport Security with no broad exception domains or custom trust
  bypasses.
- Validate Sign in with Apple issuer, audience, expiration, signature, nonce,
  and stable subject on the server.
- Store refresh/session material in Keychain; rotate short-lived sessions and
  revoke them on device removal, account deletion, or suspected compromise.
- Bind mutation requests to account, device/session, operation, idempotency
  key, and freshness value; reject replay outside the operation state machine.
- Treat presigned URLs as bearer secrets: never log them, place them in
  analytics, or persist them beyond resumable operation state.
- App Attest is defense in depth for abuse reduction. It cannot replace account
  authorization, entitlement checks, or end-to-end encryption.

## Server-visible allowlist

The control plane may store only:

- pseudonymous account ID and required Sign in with Apple mapping;
- entitlement state, plan, quota, grace state, and billing reconciliation IDs;
- opaque device/session identifiers and revocation state;
- opaque vault, backup generation, reservation, operation, and object IDs;
- provider object keys derived from opaque IDs;
- object and aggregate ciphertext sizes and stored-object checksums;
- manifest generation, authenticated-parent reference, lifecycle state, and
  operational timestamps;
- deletion jobs, bounded error categories, provider request IDs, and security
  audit events.

The server must reject schema or log fields for filenames, folder paths, photo
IDs, media roles, MIME types, captions, thumbnails, LowKeys, CRKs, AMKs, CVKs,
KDF inputs, decrypted manifests, object ciphertext, presigned URLs, Apple
tokens, receipts, or authorization headers.

## Control-plane recovery objectives

Initial operational targets are an encrypted database-backup RPO of 15 minutes
and RTO of four hours. These targets are provisional until provider and cost
review, but a production launch requires:

- automated encrypted backups in a separate failure domain;
- quarterly database restore drills;
- reconciliation that treats committed provider facts and immutable objects as
  inputs but never exposes or attempts to interpret ciphertext;
- tested handling for database-ahead, object-ahead, missing-object, deletion-
  pending, and subscription-notification replay states;
- an upload kill switch that preserves download, restore, deletion, and
  cryptographic verification paths.

## Gate A exit criteria

Gate A closes only when:

- canonical encoders/decoders exist with strict bounds and no trailing input;
- deterministic non-secret vectors cover every envelope, manifest, object
  header, key derivation, AAD value, ciphertext, and tag;
- one-byte mutation, wrong-key, unsupported-version, hostile-size, duplicate,
  reorder, truncation, trailing-data, and cross-account/vault/generation tests
  fail closed;
- snapshot mutation and cancellation tests leave no partial state;
- stale-parent, duplicate-commit, idempotent-retry, quota-race, and orphan
  cleanup tests pass;
- a local provider-free round trip restores a build 11 vault only after full
  verification;
- independent review has no unresolved critical or high finding.
