# KeyHollow Encrypted Vault Archive

Status: archive creation, validation, rollback, export, and import are
implemented. This document records the version 1 format that the code writes
and reads. Physical-device release gates remain incomplete.

## Product boundary

- Export only the vault that is currently unlocked.
- Never enumerate, count, or identify other vaults.
- Require the current LowKey before an export can begin.
- Use a separate portable credential for the exported archive.
- Offer a generated recovery code as the safe default. Do not expose the
  passphrase option until it has its own strength and confirmation UI.
- Never protect a portable archive with the normal numeric LowKey alone.
- Never delete the source vault automatically after export.
- Do not require a KeyHollow account, server, or cloud service.

## Security boundary

V1 derives its unlock key with a random installation salt and a Keychain
pepper marked `ThisDeviceOnly`. Copying the V1 credential envelope therefore
must not be treated as a portable backup. The archive creates a separate
portable envelope without copying or disclosing the device pepper.

The portable credential derives a wrapping key with Argon2id. That wrapping
key seals an authenticated secrets payload containing:

- a random archive identifier;
- the source vault identifier;
- the existing random 256-bit vault key;
- a new random 256-bit archive-content key;
- archive and source-vault timestamps.

The credential type is domain-separated so that an identical recovery-code
string and passphrase do not derive the same key. Public KDF parameters are
authenticated with the sealed payload and strictly bounded before Argon2id is
run. This prevents a hostile archive from requesting unreasonable memory or
iteration values during import.

## Cryptographic profile

- Recovery code: 20 bytes from `SecRandomCopyBytes`, encoded as 32 Crockford
  Base32 characters and displayed in eight groups of four. The separators add
  no entropy; the underlying code has 160 bits of randomness.
- Password KDF: Argon2id v1.3, 65,536 KiB memory, three iterations, parallelism
  two, 16-byte random salt, and 32-byte output.
- Secrets and content encryption: AES-256-GCM.
- AES-GCM combined representation: 12-byte nonce, ciphertext, then 16-byte tag,
  as produced and consumed by CryptoKit.
- Nonces: generated independently by CryptoKit for every sealed secrets value
  and every content chunk. Nonces are not counters and must never be supplied
  by callers in production.
- Content key: a fresh 32-byte value from `SecRandomCopyBytes` for each export.
- Byte order: all fixed-width container integers and authenticated integer
  fields are unsigned little-endian.

The public KDF fields are authenticated as AES-GCM associated data. The format
identifier and container magic are checked against exact constants before any
plaintext is released. Version 1 readers require the exact KDF profile above;
an imported file cannot request weaker or more expensive parameters.

## Container layout

The `.khvault` file is an opaque, versioned binary container:

| Offset | Length | Encoding | Meaning |
|---:|---:|---|---|
| 0 | 8 | bytes | `4b485641554c5400` (`KHVAULT` plus NUL) |
| 8 | 4 | UInt32 LE | container version, currently `1` |
| 12 | 4 | UInt32 LE | JSON public-header byte count, `1...65,536` |
| 16 | variable | UTF-8 JSON | `EncryptedVaultArchiveHeader` |
| next | repeated | binary frames | authenticated content chunks |

Each frame is `sequence: UInt64 LE`, `final: UInt8`, `sealedLength: UInt32
LE`, and `sealedContent`. Only flag values zero and one are accepted. Sealed
content is at least 28 bytes and at most 1,048,640 bytes. Plaintext chunks are
at most 1,048,576 bytes, and exactly one final chunk is required. No byte may
follow it.

The public header has exactly four logical fields: format identifier, archive
version, KDF parameters, and AES-GCM combined sealed secrets. Its JSON key
ordering is not a protocol guarantee. Readers decode by field name and reject
an invalid format, version, KDF profile, salt length, or sealed box.

The sealed secrets contain the archive UUID, source-vault UUID, source-vault
creation date, export date, 32-byte vault key, and 32-byte content key. This
plaintext is never written outside authenticated encryption.

### Header associated data

The byte string is the UTF-8 domain `keyhollow.encrypted-vault.header`, NUL,
the UTF-8 KDF identifier `argon2id-v1.3`, NUL, then archive version, memory,
iterations, parallelism, and output length as UInt32 LE values, followed by the
16-byte salt. Any change to a KDF field or salt causes authentication failure
or strict validation failure.

### Content-chunk associated data

The byte string is the UTF-8 domain
`keyhollow.encrypted-vault.content-chunk.v1`, NUL, the lowercase archive UUID,
NUL, sequence as UInt64 LE, and the final flag byte. This binds every chunk to
one archive and one exact position and prevents reordering, relabeling, or
cross-archive transplantation.

The content stream will package the already-encrypted vault manifest, photo
blobs, and thumbnails. Outer content encryption hides catalog metadata while
preserving the existing inner authenticated encryption. Export must stream
bounded chunks rather than load an entire vault into memory.

Each content chunk will authenticate its archive identifier, sequence number,
and final-chunk marker. Import must reject missing, duplicated, reordered,
truncated, or modified chunks.

The authenticated content stream begins with a 16-byte payload prefix: magic
`4b485041594c4400` (`KHPAYLD` plus NUL), UInt32 LE version `1`, and UInt32 LE
catalog length. The encrypted catalog contains only the random storage names,
roles, ciphertext sizes, and SHA-256 digests of the existing encrypted
manifest, originals, and thumbnails. It is never present in the public archive
header. Import validates
every storage name before creating files, rejects path separators and duplicate
names, and writes only to a protected staging directory. Each ciphertext digest
must match before the staged payload can be handed to vault-level validation.

Payload extraction is fail-closed: traversal attempts, changed source files,
digest mismatches, extra bytes, missing bytes, or cancellation remove the entire
staging directory. No partially extracted directory can become a vault.

Current parser limits are 32 MiB for the catalog, 200,001 entries, 1 TiB for an
individual encrypted entry, and 4 TiB total declared ciphertext. Before import,
the coordinator also requires free space equal to twice the selected archive
size plus 64 MiB. These are safety ceilings, not recommended vault sizes.

Published deterministic compatibility vectors are in
`docs/ENCRYPTED_VAULT_TEST_VECTORS.md` and are enforced by the unit suite.

## Atomic export

1. Create a protected temporary file inside the app container.
2. Write a placeholder header and sequential encrypted chunks.
3. Flush, reopen, and verify the complete archive.
4. Only after verification, expose the archive through the system document
   exporter or share sheet.
5. Remove temporary material after completion, cancellation, or failure.

The source vault remains untouched throughout this process.

## Atomic import

1. Copy the selected archive into protected temporary storage.
2. Validate magic, version, header sizes, and bounded KDF parameters.
3. Authenticate the sealed secrets with the portable credential.
4. Stream and authenticate every content chunk into a staging directory.
5. Validate the encrypted manifest and every referenced ciphertext blob.
6. Ask the user to establish a new LowKey for the destination device.
7. Derive a new device-bound V1 credential envelope and reject any LowKey that
   already resolves to a local vault.
8. Persist a file-protected, device-authenticated rollback journal containing
   only the fresh vault identifier, opaque credential locator, and fingerprint
   of the exact new encrypted credential envelope.
9. Move the fully verified staging directory into a fresh destination-vault
   identifier without replacing any existing directory.
10. Publish the new LowKey wrapper only after the ciphertext move succeeds.
11. Remove the rollback journal only after both commits succeed.
12. If credential publication reports an error, remove both the wrapper and
    the moved ciphertext before reporting failure.

Authentication or validation failures remove staging data. A rejected new
LowKey leaves the validated staging directory available for another LowKey;
commit failures roll it back. Existing vaults remain unchanged in every case.
On launch, any remaining authenticated journal is rolled back rather than
completed: KeyHollow removes the new wrapper and destination directory, clears
the journal only after both are absent, and requires the user to retry import.
A modified, forged, malformed, or unrecognized journal fails closed without
deleting the paths it names. Recovery deletes a credential only when its
fingerprint matches the transaction, so an unrelated wrapper at the same
locator is preserved. New credential publication uses an exclusive complete-
file link and cleans abandoned hidden write files on startup. Repeated
physical-device termination testing at
each commit boundary remains a release gate before this module may leave its
isolated feature branch.

## Required failure tests

- wrong recovery code or passphrase;
- altered public KDF parameters;
- tampered sealed secrets;
- modified, missing, duplicated, or reordered content chunk;
- truncated header or content stream;
- unsupported archive version;
- insufficient storage before and during transfer;
- app termination during export or import;
- tampered, malformed, or unauthenticated rollback journal;
- incomplete rollback retained for retry on the next launch;
- unrelated credential at the same locator is never deleted or overwritten;
- existing vault-identifier collision;
- large vault with bounded memory usage;
- restoration on a different physical iPhone;
- confirmation that no plaintext media, filenames, or catalog appears in
  temporary files, logs, previews, or system backups.

## Release gate

This module remains separate from the V1 release line. It must not be merged
until the existing V1 tests remain green, the archive security tests pass, and
repeated transfer between two physical iPhones succeeds without modifying the
source vault.
