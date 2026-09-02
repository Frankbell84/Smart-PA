# KeyHollow Encrypted Vault Archive

Status: the isolated archive, validation, rollback engine, and guarded export
interface are implemented. Import UI and physical-device release gates remain
incomplete. This document does not change the V1 vault format or release
behavior.

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

## Planned container

The `.khvault` file will be an opaque, versioned binary container:

1. fixed KeyHollow magic bytes;
2. container version;
3. bounded public-header length;
4. public header containing only KDF material and the sealed secrets payload;
5. an encrypted catalog;
6. sequential authenticated content chunks.

The content stream will package the already-encrypted vault manifest, photo
blobs, and thumbnails. Outer content encryption hides catalog metadata while
preserving the existing inner authenticated encryption. Export must stream
bounded chunks rather than load an entire vault into memory.

Each content chunk will authenticate its archive identifier, sequence number,
and final-chunk marker. Import must reject missing, duplicated, reordered,
truncated, or modified chunks.

The authenticated content stream begins with an encrypted payload header and
catalog. The catalog contains only the random storage names, roles, ciphertext
sizes, and SHA-256 digests of the existing encrypted manifest, originals, and
thumbnails. It is never present in the public archive header. Import validates
every storage name before creating files, rejects path separators and duplicate
names, and writes only to a protected staging directory. Each ciphertext digest
must match before the staged payload can be handed to vault-level validation.

Payload extraction is fail-closed: traversal attempts, changed source files,
digest mismatches, extra bytes, missing bytes, or cancellation remove the entire
staging directory. No partially extracted directory can become a vault.

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
