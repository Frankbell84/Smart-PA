# KeyHollow Development Checkpoint

**Updated:** September 3, 2026  
**Purpose:** Durable restart point for the validated Phase Three baseline and the modularization effort.

## Executive status

- The validated Phase Three candidate has been merged into production.
- Production TestFlight Build 12 was uploaded, processed, and assigned to the existing internal testing group.
- Build 12 passed the complete automated gate and the physical-iPhone validation performed by the owner.
- The owner reported that all tested behavior works.
- A dedicated rollback checkpoint branch preserves the exact validated merge.
- A separate modular-architecture branch has been created from that checkpoint.
- Three independently compiled boundaries are fully validated:
  `KeyHollowCryptoCore`, `KeyHollowVaultCore`, and `KeyHollowPhotoCore`.
- The fourth boundary, `KeyHollowTransferCore`, is fully validated by its Mac
  build, regression, stress, launch, and Swift security gates.
- The fifth boundary, `KeyHollowPhotosAdapter`, and the final composition-root
  injection are implemented on the isolated branch and awaiting validation.

## What Phase Three accomplished

- Enforced source-level boundaries around the local vault and cryptographic core.
- Added a permanent architecture check intended to prevent UI, Photos, networking, cloud, analytics, or payment code from leaking into the vault core.
- Added a deterministic encrypted-transfer stress test using 50 photos.
- Covered vault export and restoration, including valid and invalid recovery-code behavior.
- Covered existing vault lifecycle and security regressions.
- Completed simulator compilation and testing.
- Completed Swift security analysis.
- Completed physical-iPhone validation of Build 12.

## Verified quality gates

- Architecture boundary check: passed.
- Simulator build: passed.
- Full automated regression and security suite: passed.
- Fifty-photo encrypted-transfer test: passed.
- Swift security analysis: passed.
- Production signing and archive validation: passed.
- Apple upload and processing: passed.
- Physical-device test: passed; owner reported everything works.

## Isolation and branch state

- Validated production merge: `3deb92d` (`Merge validated Phase Three production candidate`).
- Rollback checkpoint: `checkpoint/phase-three-build-12-validated`.
- Active modularization branch: `refactor/modular-architecture`.
- Tested Phase Three production candidate: `delivery/phase-three-production` at `6fef0bf` (`Prepare phase three production TestFlight build 12`).
- Phase Three validation branch: `validation/phase-three-device-hardening` at `a25b910`.
- Phase Two branch: `security/phase-two-revocation-memory` at `3b30c3b`.
- Stage One branch: `test/stage-one-core-baseline` at `601b3cd`.
- The production candidate pull request has been merged.
- The separate KeyHollow Beta listing was removed from App Store Connect.
- Removal of the obsolete beta delivery workflow is isolated in its own draft cleanup change and is not merged.
- The older remote beta delivery branch still exists; it should not be deleted without a separate deliberate cleanup decision.

## Current architectural reality

The important responsibilities are logically separated and protected by
source-boundary checks. Cryptography, vault-domain persistence, and encrypted
photo storage, and portable vault transfer are now independently compiled and
fully validated. The app session retains revocation and task
lifetime. Apple Photos integration is now isolated in its own platform adapter,
while UI and navigation remain in the app target.

## Next goal

Complete and validate modularization without mixing the structural refactor with feature development.

### Approved order when work resumes

1. Run the Mac build, complete regression, architecture, and Swift security
   gates for `KeyHollowPhotosAdapter` and the final app composition.
2. Fix only extraction-related failures; do not change behavior or archive
   compatibility.
3. Upload the completed modular candidate to TestFlight.
4. Repeat the physical-iPhone validation before merging the modular refactor.

## Proposed module sequence

1. Vault and cryptographic core.
2. Encrypted archive transfer.
3. Photos-system adapter.
4. User interface and app composition.

The exact module names may change, but the dependency direction must remain one-way: the app and UI can depend on the core interfaces; the core must not depend on the UI, Photos, network, cloud, analytics, or payment frameworks.

## Guardrails for the next phase

- Do not add product features during modularization.
- Do not merge the modularization branch merely because it compiles.
- Preserve the Build 12 behavior as the reference behavior.
- Keep the dedicated rollback checkpoint branch unchanged while moving code.
- Move one boundary at a time and keep each change reviewable.
- Require all existing tests, architecture checks, security analysis, and device tests to pass again.
- Keep beta-workflow cleanup separate from the functional production merge.

## Estimated next-phase duration

- Merge, tag, and establish rollback point: about half a day.
- Separate vault and cryptographic core: one to two focused days.
- Separate transfer and Photos handling: about two focused days.
- Reconnect UI and repair affected tests: about one focused day.
- Automated and physical-device validation: one to two days.

Expected total: approximately one working week, with additional time only if the structural move exposes a defect.

## Resume instruction

When development resumes, start by reading this file and inspecting the current remote pull-request and branch states. Do not assume they are unchanged. Continue only on the modular-architecture branch, beginning with the pending Mac validation of `KeyHollowCryptoCore`.
