# Phase Two security and memory boundaries

This document records the security properties Phase Two is intended to enforce.
It is an engineering boundary, not a claim that Swift can guarantee physical
erasure of every transient copy made by the compiler, runtime, or operating
system.

## Vault-key lifetime

- An unlocked session owns one `VaultAccessCapability`.
- Gallery storage retains that revocable capability, not a `SymmetricKey`.
- A capability performs synchronous key use while holding its private lock. It
  never intentionally returns key material to the caller.
- Locking first removes the unlocked UI state, synchronously revokes the
  capability, and cancels every task registered as sensitive work.
- Revocation waits for an atomic key operation already in its critical section
  to end. Every later operation fails with `VaultAccessError.revoked`.
- Store methods check task cancellation before and after I/O and cryptographic
  work. An interrupted import removes any partially written encrypted blobs.
- Production export re-authenticates the LowKey but does not retain the second
  decrypted vault key returned by the credential envelope. It uses the active
  session capability and is registered for cancellation.
- Portable archive loops check cancellation between one-megabyte chunks and
  files. A canceled writer removes its incomplete destination.

### Honest zeroization limits

`CryptoKit.SymmetricKey` is a value type. Swift, CryptoKit, and Foundation do
not expose a reliable way to prove that compiler/runtime-created copies have
been overwritten. KeyHollow therefore does not claim guaranteed zeroization.
It minimizes long-lived references, revokes the only session capability,
clears explicit mutable `Data` buffers where practical, cancels work, and
relies on iOS process isolation and complete file protection for the remaining
platform boundary.

The portable archive format necessarily wraps the vault key into its encrypted
header. During export, short-lived framework values can contain that key or
derived content keys. They are scoped to the export task and released when the
task completes or is canceled; the application cannot certify physical memory
erasure of those framework-owned values.

## Bounded photo memory

- The Photos picker still allows 50 selections, but loads, normalizes,
  thumbnails, encrypts, and releases one full-resolution item before loading
  the next.
- Back-pressure is explicit: the picker awaits encrypted-store consumption of
  one item before requesting the next item.
- Copy and Move retain only counters and lightweight Photos asset identifiers
  across the batch. Move requests deletion only for successfully encrypted and
  verified originals.
- Save-to-Photos decrypts and submits one selected original at a time. It never
  builds an array of all decrypted originals.
- The gallery caches at most 48 decoded thumbnails and loads them lazily.
- Portable archive input/output remains streamed in one-megabyte chunks rather
  than loading a complete vault file into memory.

## Failure and cancellation behavior

- One unreadable picker item does not prevent other selected items from being
  imported, and the final message reports failures.
- A save failure does not discard encrypted vault copies. Successful earlier
  saves remain successful and are reported.
- A lock or background transition revokes future key operations immediately.
  Registered work receives cancellation and cannot publish a successful result
  after cancellation.
- Incomplete vault-photo imports and incomplete portable exports are deleted.
- Move is fail-safe: if every successfully imported photo cannot be matched to
  a Photos asset identifier, originals are kept and the batch is reported as a
  copy.

## Validation boundary

Automated tests prove capability revocation, task cancellation/cleanup, and a
maximum of one full-size batch item in the import processor. Simulator CI also
runs the complete Stage One lifecycle/security suite and CodeQL.

Simulator tests cannot establish peak memory on every physical iPhone, Photos
provider behavior under iCloud downloads, or iOS termination behavior under
real memory pressure. Before release, exercise 50 large HEIC/JPEG photos on the
oldest supported physical iPhone, test Copy and Move with iCloud-only items,
background during import/export/save, cancel system pickers, and confirm that
no incomplete `.khvault` file or vault record remains.
