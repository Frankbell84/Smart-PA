# KeyHollow Work Status

Updated: 2026-09-05
Branch: `delivery/general-file-support`
Source review: Draft PR #33

## Current task

Validate isolated internal TestFlight Build 24 on a physical iPhone: general files must appear in the primary Vault screen and remain fully usable through the dedicated file manager.

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

## Test and build status

- Corrected source architecture boundary check: passed locally.
- Corrected source release-hygiene check: passed locally.
- Corrected source whitespace/diff validation: passed locally.
- Corrected macOS simulator build and full regression/security suite: passed on PR #33 at source commit `84262d0`.
- Corrected Swift CodeQL security analysis: passed on PR #33 at source commit `84262d0`.
- Build 23 physical-device import persistence: passed for a PDF.
- Build 23 primary-vault visibility with a general-file-only vault: failed; corrected source is fully validated and awaiting Build 24 device confirmation.
- Feature-branch architecture gate: passed at `6b39328`.
- Feature-branch iOS simulator build and full regression/security suite: passed at `6b39328`.
- Feature-branch Swift CodeQL analysis: passed at `6b39328`.
- Delivery-branch local release-hygiene, architecture, build-number guard, and diff gates: passed.
- Delivery source parity audit: passed; all app, test, documentation, and security-script files match the fully validated feature candidate.
- A duplicate delivery-branch CodeQL run is not required because the only remaining differences are the build number, upload branch allow-list, and this status record.
- Signed production-identity archive, embedded-extension/module-hygiene verification, IPA export, and Apple upload: passed in workflow #33.
- Signed Build 24 archive, embedded-extension/module-hygiene verification, IPA export, and Apple upload: passed in workflow #34.
- Internal TestFlight Build 23: processed and available in `KeyHollow Internal` with status `Ready to Submit`.
- Internal TestFlight Build 24: upload accepted by Apple; final processing and automatic internal-group availability await confirmation.
- Production branch and App Store review: untouched.

## Blockers

- No implementation or automated-validation blocker. App Store Connect signed out immediately after upload, so final Apple processing visibility requires a fresh sign-in or confirmation that Build 24 arrived in TestFlight.

## Next action

After Build 24 appears in TestFlight, install it and verify that a vault containing only a PDF or other general file no longer says `Empty Vault`, that the file is visible on the primary Vault screen, and that tapping it opens Vault Files. Keep PR #33 unmerged until that device validation passes.

## Frank's decision required

- Frank must confirm that Build 24 appears in TestFlight and that a general-file-only vault no longer appears empty and opens through the primary Vault screen.
- Final merge and any App Store review submission remain separate decisions requiring Frank's explicit approval after device validation.
