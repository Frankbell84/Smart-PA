# KeyHollow Work Status

Updated: 2026-09-05
Branch: `feature/general-file-support`
Pull request: PR #33 merged into `main` at `bbd6bfa`

## Current task

Close the completed general-file-support phase and prepare the next add-on on a fresh isolated branch. App Store review remains untouched. Thumbnail parity for images imported through Files is carried into the dedicated folder/presentation phase.

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
- Replaced the oversized primary-screen file panel with compact file tiles inside the same three-column grid used by photo thumbnails.
- File tiles retain file-type identity, display name, size, accessibility labels, and navigation into the dedicated file manager.
- Photo-selection mode visibly disables file tiles because its save/delete actions remain intentionally photo-specific.
- Updated the add-on behavior record to document the unified mixed-content grid without weakening the separate manifests or compiled-module boundary.
- PR #33 completed the refined macOS simulator build, full regression/security suite, architecture enforcement, release-hygiene gate, and Swift CodeQL analysis at `7b41ffc`.
- Build 25 physical-device testing confirmed that the unified mixed-content grid works and files remain encrypted, persisted, and reachable.
- The pending import candidates already clear after confirmation, but the same `Vault Files` sheet immediately switches to its persisted-record manager, making the imported file appear to remain in staging.
- Successful primary-vault imports now clear pending candidates and return to the unified grid after the user acknowledges the result.
- Canceling the primary-vault review or Files picker now returns to the unified grid instead of revealing the stored-file manager as if it were staging.
- Intentionally opening `Vault Files` still presents persisted encrypted records for export and deletion.
- Added a regression decision test that distinguishes successful primary-vault imports from zero-import and intentional manager flows.
- Build 26 physical-device testing confirmed that importing succeeds and the file appears in the unified grid, but the originating sheet still remains visible as the persisted-record manager.
- The underlying defect is now isolated to sheet lifecycle ownership: pending candidates clear correctly, but child-level dismissal is not reliably closing the parent-owned sheet.
- The primary Vault now owns import-flow completion through a narrow callback and closes its own sheet after the result is acknowledged.
- Completed primary-vault imports enter a terminal presentation state, so they cannot fall through into the persisted-record manager while dismissal is being processed.
- Picker cancellation and review cancellation use the same parent-owned close path; intentionally opening `Vault Files` remains a separate manager flow.
- Added regression coverage for completed, unfinished, and intentional-manager lifecycle decisions and documented the ownership boundary.
- Build 27 physical-device testing confirmed that parent-controlled dismissal still does not reliably eliminate the post-selection staging/manager experience.
- Frank directed that the staging/review step be removed: selecting files must encrypt them immediately and refresh the same unified three-column grid used by photos.
- Removed the pending-candidate type, review list, second confirmation button, child-dismissal policy, and every user-facing staging lifecycle symbol.
- Added a narrow module-owned batch-import API that enforces the 50-file limit, processes each file through the existing protected copy/encrypt/verify/commit path, and returns only aggregate counts.
- The primary Vault now presents Apple's Files picker directly and refreshes the unified three-column grid after import without presenting `Vault Files`.
- The intentional `Vault Files` manager uses the same batch-import API for its plus button while retaining export and deletion controls.
- Future metadata editing is explicitly decoupled from import and deferred to a deliberate post-import Vault Security/settings surface.
- Replaced staging lifecycle tests with batch success, partial rejection, source-preservation, and maximum-selection regression coverage.
- PR #33 passed the staging-free macOS simulator build, full regression/security suite, architecture enforcement, release-hygiene gate, and Swift CodeQL at source commit `b964b37`.
- Build 28 reached the production KeyHollow internal TestFlight group and Frank confirmed direct, staging-free general-file import works on a physical iPhone.
- Build 28 physical testing exposed two follow-up gaps: matching confirmation digits do not reveal an immediate Continue action, and a portable-vault export/restore preserves photos but omits general files.
- Source audit confirmed the transfer defect is structural rather than presentational: the portable archive catalog, exporter, validator, and installer currently operate only on `PhotoData` and the photo manifest; `GeneralFileData` is never added to or restored from the archive.
- Added a versioned supplemental-ciphertext seam to the compiled transfer module without allowing the protected core to import the general-file add-on.
- Added an app-composition bridge that asks the independently compiled general-file add-on to authenticate its manifest and every encrypted blob before export and again after archive extraction.
- New mixed-content archives carry the authenticated general-file manifest and blobs in a traversal-safe namespace; catalog version 1 photo-only archives remain accepted for backward compatibility.
- Restore now validates all photo and general-file ciphertext before installation, commits both stores under one authenticated transaction journal, and rolls both back if credential publication or an interrupted install fails.
- Added mixed photo/file export, validation, install, plaintext-equivalence, legacy-catalog compatibility, and dual-store rollback regression coverage.
- The import verification summary now reports both photo and file counts.
- Matching, policy-compliant confirmation digits now reveal an inline Continue action directly beneath the second LowKey field while preserving the keyboard toolbar action.
- PR #33 completed the corrected macOS simulator build, full mixed photo/file regression and security suite, architecture enforcement, release-hygiene gate, and Swift CodeQL analysis at `2ac4d75`.
- The exact validated implementation and tests were transferred to isolated delivery Build 29; signed workflow #39 passed and Apple assigned Build 29 to `KeyHollow Internal` with status `Ready to Submit`.
- Frank confirmed on a physical iPhone that Build 29 works end to end, including mixed photo/file portable-vault export and restore and the smoother matching-LowKey Continue flow.
- Physical testing confirmed that general files and Photo-library images now share the unified vault grid and persist through the protected transfer path.
- One presentation refinement is intentionally deferred: image files imported through Apple's Files picker use a generic encrypted-file tile instead of the live thumbnail used for Photo-library imports. This is a folder/presentation concern, not a storage, encryption, or transfer defect.
- Frank explicitly approved the final merge after Build 29 physical-device validation.
- The exact approved head `57f638e` passed all three protected checks: iPhone simulator build/regression/security tests, Swift CodeQL, and changed-code scanning with no new alerts.
- PR #33 was made merge-ready and merged into `main` as merge commit `bbd6bfa` on 2026-09-05. The feature branch was intentionally retained as a recovery trail.

## Test and build status

- Corrected source architecture boundary check: passed locally.
- Corrected source release-hygiene check: passed locally.
- Corrected source whitespace/diff validation: passed locally.
- Previous remote simulator build, full tests, and Swift CodeQL passed at `6b39328`.
- Build 23 general-file encryption and persistence on a physical iPhone: passed for a PDF.
- Build 23 primary-vault visibility with a general-file-only vault: failed; correction is now published for review.
- Build 24 primary-vault general-file visibility and navigation: passed on a physical iPhone.
- Build 24 mixed-content visual consistency: refinement required before merge.
- Refined source architecture boundary check: passed locally.
- Refined source release-hygiene check: passed locally.
- Refined source whitespace/diff validation: passed locally.
- Refined macOS simulator build and full regression/security suite: passed on PR #33 at `7b41ffc`.
- Refined Swift CodeQL security analysis: passed on PR #33 at `7b41ffc`.
- Build 25 unified mixed-content grid and file persistence: passed on a physical iPhone.
- Build 25 post-import flow clarity: failed; the completed import remains in the file-manager sheet and looks like uncleared staging.
- Corrected post-import source architecture boundary check: passed locally.
- Corrected post-import release-hygiene check: passed locally.
- Corrected post-import TestFlight build-number guard self-test: passed locally.
- Corrected post-import whitespace/diff validation: passed locally.
- Corrected post-import macOS simulator build and full regression/security suite: passed on PR #33 at `ecc02c0`.
- Corrected post-import Swift CodeQL security analysis: passed on PR #33 at `ecc02c0`.
- Parent-owned lifecycle correction architecture boundary check: passed locally.
- Parent-owned lifecycle correction release-hygiene check: passed locally.
- Parent-owned lifecycle correction TestFlight build-number guard self-test: passed locally.
- Parent-owned lifecycle correction whitespace/diff validation: passed locally.
- Parent-owned lifecycle correction macOS simulator build and full regression/security suite: passed on PR #33 at `bf30be0`.
- Parent-owned lifecycle correction Swift CodeQL security analysis: passed on PR #33 at `bf30be0`.
- Direct-import architecture boundary check: passed locally.
- Direct-import release-hygiene check: passed locally.
- Direct-import TestFlight build-number guard self-test: passed locally.
- Direct-import whitespace/diff validation: passed locally.
- Obsolete staging/review implementation-symbol audit: passed locally; no symbols remain.
- Direct-import macOS simulator build and full regression/security suite: passed on PR #33 at `b964b37`.
- Direct-import Swift CodeQL security analysis: passed on PR #33 at `b964b37`.
- Build 28 direct, staging-free general-file import and unified-grid presentation: passed on a physical iPhone.
- Build 28 mixed-content `.khvault` export/restore: failed on a physical iPhone; photos restore but general files are absent.
- Mixed-content repair architecture boundary check: passed locally; TransferCore remains independent from all add-ons.
- Mixed-content repair release-hygiene check: passed locally.
- Mixed-content repair whitespace/diff validation: passed locally.
- Mixed-content macOS simulator compilation and full regression/security suite: passed on PR #33 at `2ac4d75`.
- Mixed-content Swift CodeQL security analysis: passed on PR #33 at `2ac4d75`.
- Signed internal TestFlight Build 29 delivery, Apple processing, and `KeyHollow Internal` assignment: passed.
- Build 29 mixed photo/file export and restore on a physical iPhone: passed.
- Build 29 matching-LowKey inline Continue interaction on a physical iPhone: passed.
- Image-file thumbnail parity with Photo-library imports: deferred to the folder/presentation phase by design.
- Final protected validation at approved head `57f638e`: passed all three checks; Swift CodeQL completed in 20 minutes with no unresolved changed-code alert.
- Production source merge: passed; PR #33 is merged into `main` at `bbd6bfa`.
- Corrected macOS simulator build and full regression/security suite: passed on PR #33 at `84262d0`.
- Corrected Swift CodeQL security analysis: passed on PR #33 at `84262d0`.
- App Store review submission: untouched.

## Blockers

- No blocker remains for the general-file-support phase.
- Current compiler warnings identify Swift 6 actor-isolation hardening debt; they did not fail the current build or security analysis and must be handled in a separate isolated hardening change rather than altering the device-tested candidate.

## Next action

Create the next add-on from the new `main` baseline on a fresh isolated branch. Treat thumbnail generation and unified image-tile presentation as an acceptance requirement of the folder/presentation module, and run the same architecture, simulator, security, TestFlight, and physical-device gates before any future merge.

## Frank's decision required

- No decision is required to close the completed general-file-support phase or begin routine isolated development of the next planned add-on.
- Any App Store review submission remains a separate decision requiring Frank's explicit approval.
