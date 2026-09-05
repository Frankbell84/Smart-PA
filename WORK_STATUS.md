# KeyHollow Work Status

Updated: 2026-09-05
Branch: `feature/general-file-support`
Pull request: Draft PR #33

## Current task

Deliver the fully validated unified-vault correction to an isolated production-identity TestFlight build for physical-iPhone confirmation.

## Completed work

- General File Support remains an independently compiled add-on behind narrow interfaces.
- Selecting files creates pending review candidates and does not change the vault manifest.
- The review screen provides an explicit `Import N Files into Vault` confirmation.
- Removing or cancelling pending candidates leaves the vault and source files unchanged.
- Security-scoped file access is owned and released by the add-on rather than the UI.
- Build 23 physical-device testing confirmed that a selected PDF is encrypted and persisted in the add-on store.
- Physical-device evidence isolated the remaining defect to presentation: the primary Vault screen read only the photo manifest and incorrectly reported `Empty Vault` when encrypted general files existed.
- Implemented a unified primary Vault presentation that composes authenticated photo and general-file records without merging their stores or manifests.
- A general-file-only vault now displays its encrypted files on the primary screen.
- Tapping a primary-screen file opens the dedicated Vault Files manager, and dismissing that manager refreshes the primary file list after imports or deletions.
- Moved shared general-file presentation and scoped-access composition into one UI-layer file, removing duplicate type-icon and cryptographic adapter code.
- Added a regression assertion covering photo-only, file-only, mixed, and truly empty primary-vault states.
- PR #33 completed the corrected macOS simulator build, full regression/security suite, architecture enforcement, release-hygiene gate, and Swift CodeQL analysis at `84262d0`.

## Test and build status

- Corrected source architecture boundary check: passed locally.
- Corrected source release-hygiene check: passed locally.
- Corrected source whitespace/diff validation: passed locally.
- Previous remote simulator build, full tests, and Swift CodeQL passed at `6b39328`.
- Build 23 general-file encryption and persistence on a physical iPhone: passed for a PDF.
- Build 23 primary-vault visibility with a general-file-only vault: failed; correction is now published for review.
- Corrected macOS simulator build and full regression/security suite: passed on PR #33 at `84262d0`.
- Corrected Swift CodeQL security analysis: passed on PR #33 at `84262d0`.
- Production and App Store review: untouched.

## Blockers

- No implementation or automated-validation blocker. A fresh isolated internal TestFlight build and physical-device confirmation remain.

## Next action

Advance the already synchronized delivery branch to Build 24, run the signed TestFlight pipeline, verify Apple processing, and keep PR #33 unmerged until physical-device validation passes.

## Frank's decision required

- After the corrected build reaches TestFlight, Frank must confirm that a general-file-only vault no longer appears empty and that the file is reachable through the primary Vault screen.
- Final merge and any App Store review submission remain separate decisions requiring Frank's explicit approval after device validation.
