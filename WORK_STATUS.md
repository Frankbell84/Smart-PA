# KeyHollow Work Status

Updated: 2026-09-05
Branch: `feature/general-file-support`
Pull request: Draft PR #33

## Current task

Refine the mixed-content Vault presentation so encrypted photos and general files use one coherent visual system while remaining separate compiled modules underneath.

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
- Frank confirmed on a physical iPhone that Build 24 fixes the functional defect: general files persist and are reachable from the primary Vault screen.
- Build 24 exposed a presentation-quality issue only: general files use an oversized list card while photos use compact square tiles.

## Test and build status

- Corrected source architecture boundary check: passed locally.
- Corrected source release-hygiene check: passed locally.
- Corrected source whitespace/diff validation: passed locally.
- Previous remote simulator build, full tests, and Swift CodeQL passed at `6b39328`.
- Build 23 general-file encryption and persistence on a physical iPhone: passed for a PDF.
- Build 23 primary-vault visibility with a general-file-only vault: failed; correction is now published for review.
- Build 24 primary-vault general-file visibility and navigation: passed on a physical iPhone.
- Build 24 mixed-content visual consistency: refinement required before merge.
- Corrected macOS simulator build and full regression/security suite: passed on PR #33 at `84262d0`.
- Corrected Swift CodeQL security analysis: passed on PR #33 at `84262d0`.
- Production and App Store review: untouched.

## Blockers

- No security, storage, or functional blocker. The remaining issue is mixed-content UI consistency.

## Next action

Replace the separate oversized file panel with file tiles that share the photo grid's square geometry, preserve file-type identity and accessibility, then rerun all architecture, simulator, regression, and security gates before another isolated TestFlight build.

## Frank's decision required

- After the refined build reaches TestFlight, Frank must confirm that mixed photo/file vaults look coherent and that file navigation remains clear.
- Final merge and any App Store review submission remain separate decisions requiring Frank's explicit approval after device validation.
