# Phase Three — Physical-Device Validation

Phase Three is a validation and release-hardening phase. It does not add cloud
storage, subscriptions, analytics, or unrelated product features. It remains
stacked on the isolated Phase Two security branch until every required gate is
complete.

## Automated pre-device gate

- Round-trip a 50-photo encrypted vault in CI.
- Verify all 101 encrypted vault entries: one manifest, 50 originals, and 50
  thumbnails.
- Reopen every restored original and thumbnail and authenticate its contents.
- Confirm export does not alter any encrypted source-vault file.
- Keep the existing cancellation, tamper, rollback, lock-revocation, and
  bounded-memory tests green.

Passing this test proves functional correctness under a larger deterministic
fixture. Simulator CI cannot measure an iPhone's true peak memory or reproduce
Photos and iCloud provider behavior, so it is not a substitute for the device
gate below.

## Required physical-device matrix

Run on the oldest supported iPhone available and, when possible, one current
iPhone. Keep production KeyHollow installed separately from the beta.

### Large local-photo import

1. Create a fresh beta vault.
2. Copy 50 large HEIC or JPEG photos into it in one selection.
3. Confirm progress completes, the app remains responsive, and all 50
   thumbnails open their matching originals.
4. Lock and reopen the vault, then verify a sample from the beginning, middle,
   and end of the selection.
5. Record any memory warning, termination, missing thumbnail, or wrong image.

### iCloud-only photo import

1. Select at least 10 Photos items that are not already downloaded locally.
2. Repeat once on reliable Wi-Fi and once while briefly interrupting the
   connection.
3. Confirm successful items are present and failures are clearly counted.
4. Confirm a failed item never creates a broken vault entry.

### Background and cancellation

Repeat during Copy, Move, export, validation, import, and Save to Photos:

1. Start the operation with enough data that it remains active.
2. Background the app, lock the phone, and return.
3. Repeat using the operation's Cancel control where available.
4. Confirm KeyHollow returns locked, requires the LowKey, and exposes no vault
   contents in the app switcher.
5. Confirm no incomplete `.khvault`, staging directory, orphaned photo record,
   or unintended Photos deletion remains.

### Encrypted transfer between two iPhones

1. Export the same 50-photo vault to a `.khvault` file.
2. Import it on a second iPhone with the recovery code.
3. Assign a new, unused local LowKey.
4. Verify the photo count and open a sample from the beginning, middle, and end.
5. Repeat with one wrong recovery-code attempt and confirm no partial vault is
   created.

### Low-storage behavior

1. Reduce free device storage until the preflight check rejects the selected
   archive or photo batch.
2. Confirm the operation stops before committing a partial vault.
3. Restore adequate space and confirm the same input then succeeds.

## Evidence to retain

- iPhone model and iOS version.
- Operation, item count, approximate source size, and result.
- Screen recording or screenshot for any failure.
- Crash or diagnostic log if iOS terminates the app.
- Confirmation that source Photos remained intact except after an explicitly
  approved and successfully completed Move deletion.

## Exit criteria

Phase Three is ready for independent security review only when the automated
gate is green and every physical-device scenario above passes without data
loss, plaintext persistence, unauthorized access, or an unexplained crash.
