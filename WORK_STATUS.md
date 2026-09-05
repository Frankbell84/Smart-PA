# KeyHollow Work Status

Updated: 2026-09-05
Branch: `chore/phase-four-preflight`
Pull request: [#34](https://github.com/Frankbell84/KeyHollow/pull/34) (merged)

## Current task

The pre-Phase 4 cleanup is complete and merged into `main` at `69154ff` after
Frank's explicit approval. Preserve that commit as the clean rollback baseline.
Phase 4 feature work has not begun. App Store review and TestFlight remain
untouched.

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
- Final branch-tip CI run [#216](https://github.com/Frankbell84/KeyHollow/actions/runs/33986912069)
  at `7fb5487`: passed.
- Mac simulator build and complete regression/security suite: passed in 6m41s.
- Both first-party add-ons compiled under strict concurrency with
  warnings-as-errors; no add-on diagnostics remained.
- Deterministic architecture-specific simulator selection removed the prior
  multiple-destination warning.
- Artifact uploads through the pinned Node 24 action: passed; simulator and
  security-test artifacts were produced with recorded SHA-256 digests.
- Swift CodeQL: passed with no failed security gate.
- PR #34 merged into `main` as `69154ff`; all three required checks were green
  and GitHub reported no conflicts at merge time.

## Blockers

- None.

## Next action

Create and push an annotated rollback tag at `69154ff`, then hold. When Frank
explicitly starts Phase 4, create a fresh isolated branch from that tagged
baseline before making any feature change.

## Frank's decision required

- No decision is currently required; the approved merge is complete.
- Frank must explicitly start Phase 4 before feature implementation begins.
- A new TestFlight build is not required for this behavior-neutral cleanup.
- Any future TestFlight delivery or App Store review change still requires
  Frank's explicit approval.
