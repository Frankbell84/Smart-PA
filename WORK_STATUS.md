# KeyHollow Work Status

Updated: 2026-09-05
Branch: `delivery/general-file-support`
Source review: Draft PR #33

## Current task

Run the signed isolated TestFlight Build 25 delivery after validating the unified mixed-content grid and preserving production.

## Completed work

- Implemented a unified primary Vault presentation that composes authenticated
  photo and general-file records without merging their stores or manifests.
- A general-file-only vault now displays its encrypted files on the primary
  screen instead of showing the photo-only `Empty Vault` state.
- Tapping a primary-screen file opens the dedicated Vault Files manager, and
  dismissing that manager refreshes the primary file list after imports or
  deletions.
- Moved shared general-file presentation and scoped-access composition into one
  UI-layer file, removing duplicate type-icon and cryptographic adapter code.
- Added a regression assertion covering photo-only, file-only, mixed, and truly
  empty primary-vault states.
- PR #33 completed the corrected macOS simulator build, full regression/security suite, architecture enforcement, release-hygiene gate, and Swift CodeQL analysis at source commit `84262d0`.
- Frank confirmed that Build 23 successfully encrypts and persists a selected PDF in the General File Support add-on.
- Physical-device evidence isolated the defect to presentation: the primary Vault screen reads only the photo manifest and therefore reports `Empty Vault` even when the general-file manifest contains encrypted records.
- Confirmed that the file is not stranded in a temporary holding area; it is present in `Vault Files`, selectable, exportable, and deletable.
- Preserved Build 22 as the previously tested delivery baseline.
- Transferred only the validated explicit general-file import review changes from the isolated feature branch.
- Pending selections do not change the vault until the user confirms `Import N Files into Vault`.
- Cancelling or removing pending selections releases file access and leaves the vault and source files unchanged.
- General File Support remains an independently compiled add-on behind narrow interfaces.
- Advanced both the KeyHollow app and thumbnail extension to Build 24 for the corrected internal candidate.
- Build 23 remains the physical-device evidence baseline that exposed the presentation defect.
- Ran signed TestFlight workflow #34 from delivery commit `1d29108`.
- Workflow #34 passed the App Store Connect build-number guard, production-identity check, release hygiene, archive/module hygiene, IPA export, signing, and Apple upload.
- Apple accepted the Build 24 upload for processing; no App Store review submission was changed.
- Ran signed TestFlight workflow #33 from delivery commit `c1e30fd`.
- Apple accepted and processed Build 23, and App Store Connect assigned it to the existing `KeyHollow Internal` group.
- Frank confirmed on a physical iPhone that Build 24 fixes the functional defect: general files persist and are reachable from the primary Vault screen.
- Build 24 exposed a presentation-quality issue only: general files use an oversized list card while photos use compact square tiles.
- The isolated source refinement replaces that split presentation with one three-column grid while keeping photo and general-file stores, manifests, and compiled modules separate.
- PR #33 passed the refined macOS simulator build, full regression/security suite, architecture enforcement, release hygiene, and Swift CodeQL at source commit `7b41ffc`.
- Transferred only the validated unified-grid source and documentation into this isolated delivery branch at `a12c4b7`.
- Confirmed exact parity for the three transferred source/documentation files against validated source commit `7b41ffc`.
- Advanced both the KeyHollow app and thumbnail extension to Build 25.
- Replaced the oversized primary-screen file panel with compact file tiles inside the same three-column grid used by photo thumbnails.
- File tiles retain file-type identity, display name, size, accessibility labels, and navigation into the dedicated file manager.
- Photo-selection mode visibly disables file tiles because its save/delete actions remain intentionally photo-specific.
- Updated the add-on behavior record to document the unified mixed-content grid without weakening the separate manifests or compiled-module boundary.

## Test and build status

- Corrected source architecture boundary check: passed locally.
- Corrected source release-hygiene check: passed locally.
- Corrected source whitespace/diff validation: passed locally.
- Corrected macOS simulator build and full regression/security suite: passed on PR #33 at source commit `84262d0`.
- Corrected Swift CodeQL security analysis: passed on PR #33 at source commit `84262d0`.
- Build 23 physical-device import persistence: passed for a PDF.
- Build 23 primary-vault visibility with a general-file-only vault: failed; corrected source is fully validated and awaiting Build 24 device confirmation.
- Build 24 primary-vault general-file visibility and navigation: passed on a physical iPhone.
- Build 24 mixed-content visual consistency: refinement required before merge.
- Refined source macOS simulator build, full regression/security suite, and Swift CodeQL: passed on PR #33 at `7b41ffc`.
- Delivery architecture boundary check: passed after the unified-grid transfer.
- Delivery release-hygiene check: passed after the unified-grid transfer.
- Delivery TestFlight build-number guard self-test: passed after the unified-grid transfer.
- Delivery source parity for the transferred UI files and behavior record: passed against `7b41ffc`.
- Feature-branch architecture gate: passed at `6b39328`.
- Feature-branch iOS simulator build and full regression/security suite: passed at `6b39328`.
- Feature-branch Swift CodeQL analysis: passed at `6b39328`.
- Delivery-branch local release-hygiene, architecture, build-number guard, and diff gates: passed.
- Delivery source parity audit: passed; all app, test, documentation, and security-script files match the fully validated feature candidate.
- A duplicate delivery-branch CodeQL run is not required because the only remaining differences are the build number, upload branch allow-list, and this status record.
- Signed production-identity archive, embedded-extension/module-hygiene verification, IPA export, and Apple upload: passed in workflow #33.
- Signed Build 24 archive, embedded-extension/module-hygiene verification, IPA export, and Apple upload: passed in workflow #34.
- Internal TestFlight Build 23: processed and available in `KeyHollow Internal` with status `Ready to Submit`.
- Internal TestFlight Build 24: processed, installed, and functionally validated on a physical iPhone.
- Production branch and App Store review: untouched.

## Blockers

- No implementation or automated-validation blocker. Signed Build 25 delivery and physical-device visual confirmation remain.

## Next action

Commit and push the Build 25 delivery checkpoint, start the signed TestFlight workflow, verify Apple accepts the upload, and wait for physical-device visual confirmation. Keep PR #33 draft and production untouched.

## Frank's decision required

- After Build 25 arrives, Frank must confirm that photos and general files share a coherent grid and that file navigation remains clear.
- Final merge and any App Store review submission remain separate decisions requiring Frank's explicit approval after device validation.
