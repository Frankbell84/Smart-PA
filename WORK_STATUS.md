# KeyHollow Work Status

Updated: 2026-09-05
Branch: `delivery/general-file-support`
Source review: Draft PR #33

## Current task

Correct the Build 23 vault presentation defect found during physical-iPhone validation: encrypted general files must be visible from the primary Vault screen without weakening the independently compiled photo and general-file storage boundaries.

## Completed work

- Frank confirmed that Build 23 successfully encrypts and persists a selected PDF in the General File Support add-on.
- Physical-device evidence isolated the defect to presentation: the primary Vault screen reads only the photo manifest and therefore reports `Empty Vault` even when the general-file manifest contains encrypted records.
- Confirmed that the file is not stranded in a temporary holding area; it is present in `Vault Files`, selectable, exportable, and deletable.
- Preserved Build 22 as the previously tested delivery baseline.
- Transferred only the validated explicit general-file import review changes from the isolated feature branch.
- Pending selections do not change the vault until the user confirms `Import N Files into Vault`.
- Cancelling or removing pending selections releases file access and leaves the vault and source files unchanged.
- General File Support remains an independently compiled add-on behind narrow interfaces.
- Advanced both the KeyHollow app and thumbnail extension to Build 23.
- Ran signed TestFlight workflow #33 from delivery commit `c1e30fd`.
- Apple accepted and processed Build 23, and App Store Connect assigned it to the existing `KeyHollow Internal` group.

## Test and build status

- Build 23 physical-device import persistence: passed for a PDF.
- Build 23 primary-vault visibility with a general-file-only vault: failed; correction in progress on the isolated delivery branch.
- Feature-branch architecture gate: passed at `6b39328`.
- Feature-branch iOS simulator build and full regression/security suite: passed at `6b39328`.
- Feature-branch Swift CodeQL analysis: passed at `6b39328`.
- Delivery-branch local release-hygiene, architecture, build-number guard, and diff gates: passed.
- Delivery source parity audit: passed; all app, test, documentation, and security-script files match the fully validated feature candidate.
- A duplicate delivery-branch CodeQL run is not required because the only remaining differences are the build number, upload branch allow-list, and this status record.
- Signed production-identity archive, embedded-extension/module-hygiene verification, IPA export, and Apple upload: passed in workflow #33.
- Internal TestFlight Build 23: processed and available in `KeyHollow Internal` with status `Ready to Submit`.
- Production branch and App Store review: untouched.

## Blockers

- No implementation blocker. A fresh internal TestFlight build and physical-device confirmation will be required after the UI correction passes automated gates.

## Next action

Compose the photo and general-file manifests through the presentation layer so the main Vault screen reflects both stores, while keeping encryption and storage independent. Add regression coverage, run architecture/build/security gates, and deliver a higher internal TestFlight build. Keep PR #33 unmerged until physical-device validation passes.

## Frank's decision required

- After the corrected build reaches TestFlight, Frank must confirm that a general-file-only vault no longer appears empty and that the file opens through the primary Vault screen.
- Final merge and any App Store review submission remain separate decisions requiring Frank's explicit approval after device validation.
