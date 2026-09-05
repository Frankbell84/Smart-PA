# KeyHollow Work Status

Updated: 2026-09-04
Branch: `feature/general-file-support`
Pull request: Draft PR #33

## Current task

Validate the explicit general-file import review flow before preparing internal TestFlight Build 23.

## Completed work

- General File Support remains an independently compiled add-on behind narrow interfaces.
- Selecting files now creates pending review candidates and does not change the vault manifest.
- The review screen provides an explicit `Import N Files into Vault` confirmation.
- Removing or cancelling pending candidates leaves the vault and source files unchanged.
- Security-scoped file access is owned and released by the add-on rather than the UI.
- Added regression tests for deferred commit and safe discard.
- Corrected asynchronous test assertions without changing application behavior.

## Test and build status

- Local release-hygiene gate: passed.
- Local architecture-boundary gate: passed.
- Local diff validation: passed.
- Remote iOS simulator build and regression/security tests: running for commit `590b6f4`.
- Swift CodeQL security analysis: running for commit `590b6f4`.
- Production and App Store review: untouched.

## Blockers

- No active blocker. Build 23 delivery is gated on both remote checks passing.

## Next action

After all remote checks pass, create the isolated production-identity delivery candidate, bump both app and thumbnail-extension build numbers to 23, rerun the delivery gates, and upload only to the existing internal TestFlight group.

## Frank's decision required

- After Build 23 reaches TestFlight, Frank must perform the physical-iPhone import/cancel/confirm regression test.
- Final merge and any App Store review submission remain separate decisions and require Frank's explicit approval after device validation.
