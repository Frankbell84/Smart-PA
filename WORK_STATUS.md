# KeyHollow Work Status

Updated: 2026-09-04
Branch: `feature/general-file-support`
Pull request: Draft PR #33

## Current task

Prepare the isolated production-identity delivery candidate for internal TestFlight Build 23.

## Completed work

- General File Support remains an independently compiled add-on behind narrow interfaces.
- Selecting files now creates pending review candidates and does not change the vault manifest.
- The review screen provides an explicit `Import N Files into Vault` confirmation.
- Removing or cancelling pending candidates leaves the vault and source files unchanged.
- Security-scoped file access is owned and released by the add-on rather than the UI.
- Added regression tests for deferred commit and safe discard.
- Corrected asynchronous test assertions without changing application behavior.
- Completed the remote Mac simulator build, full regression/security suite, and Swift CodeQL analysis for commit `6b39328`.

## Test and build status

- Local release-hygiene gate: passed.
- Local architecture-boundary gate: passed.
- Local diff validation: passed.
- Remote iOS simulator build and regression/security tests: passed for commit `6b39328`.
- Swift CodeQL security analysis: passed for commit `6b39328`.
- Production and App Store review: untouched.

## Blockers

- No active blocker. The validated feature changes are ready to be transferred onto the isolated delivery branch.

## Next action

Transfer only the validated import-review changes onto `delivery/general-file-support`, bump both app and thumbnail-extension build numbers to 23, rerun the delivery gates, and upload only to the existing internal TestFlight group.

## Frank's decision required

- After Build 23 reaches TestFlight, Frank must perform the physical-iPhone import/cancel/confirm regression test.
- Final merge and any App Store review submission remain separate decisions and require Frank's explicit approval after device validation.
