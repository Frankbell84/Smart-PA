# KeyHollow Work Status

Updated: 2026-09-05
Branch: `chore/phase-four-preflight`
Pull request: Not opened

## Current task

Validate the behavior-neutral pre-Phase 4 cleanup against the Mac simulator,
complete regression/security suite, and Swift CodeQL. App Store review and
TestFlight remain untouched.

## Completed work

- Began from verified remote `main` at merged General File Support commit
  `bbd6bfa`; no completed feature or delivery branch was reused.
- Preserved the compiled core modules and the independently compiled File
  Recognition and General File Support add-ons.
- Removed the General File Support actor-initializer warnings by resolving file
  locations and dependencies locally before assigning actor-owned state. No
  storage path, encryption, import, export, or deletion behavior changed.
- Made warnings-as-errors mandatory for every registered first-party add-on and
  extended the architecture gate to enforce that rule for future add-ons.
- Updated all artifact-upload workflow pins from the deprecated Node 20 action
  to the exact reviewed Node 24 action commit.
- Made simulator selection architecture-specific after the first remote run
  exposed Xcode's harmless multiple-destination warning; future runs now select
  the runner's exact architecture instead of accepting Xcode's first match.
- Refreshed the modularization plan and durable project checkpoint to reflect
  the completed modular baseline, merged add-ons, validated Build 29, and the
  exact Phase 4 entry requirements.
- Preserved the deferred presentation requirement: images imported through
  Files receive encrypted thumbnail parity during the folder/presentation phase.

## Test and build status

- Architecture boundary gate: passed locally.
- Release-hygiene gate: passed locally.
- TestFlight build-number guard self-test: passed locally.
- Whitespace and obsolete-status audit: passed locally.
- First remote Mac compilation: passed; both add-ons compiled with
  warnings-as-errors and no add-on diagnostics.
- First remote run exposed one non-code Xcode destination-selection warning;
  its deterministic workflow correction is pending the refreshed remote run.
- Complete regression/security suite and Swift CodeQL: superseded by the
  refreshed remote run after the destination correction.

## Blockers

- No code blocker. A refreshed remote Mac and CodeQL run is required after the
  deterministic simulator-destination correction is published.

## Next action

Commit and push the final workflow cleanup to draft PR #34 and review the
refreshed Mac build/test/security evidence. If all gates are green, request
explicit approval before merging the clean baseline into `main`.

## Frank's decision required

- No decision is required for routine validation or repairs that do not change
  customer behavior.
- Merging the cleanup into `main`, delivering another TestFlight build, or
  changing App Store review requires Frank's explicit approval.
