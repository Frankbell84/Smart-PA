# KeyHollow Work Status

Updated: 2026-09-05
Branch: `chore/phase-four-preflight`
Pull request: [#34](https://github.com/Frankbell84/KeyHollow/pull/34) (draft)

## Current task

Preserve the completed, warning-free pre-Phase 4 cleanup as the clean baseline
pending explicit merge approval. App Store review and TestFlight remain
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
- Final remote CI run [#215](https://github.com/Frankbell84/KeyHollow/actions/runs/33985539241)
  at `cce693e`: passed.
- Mac simulator build and complete regression/security suite: passed in 6m49s.
- Both first-party add-ons compiled under strict concurrency with
  warnings-as-errors; no add-on diagnostics remained.
- Deterministic architecture-specific simulator selection removed the prior
  multiple-destination warning.
- Artifact uploads through the pinned Node 24 action: passed; simulator and
  security-test artifacts were produced with recorded SHA-256 digests.
- Swift CodeQL: passed in 24m20s with zero unresolved AST nodes and no failed
  security gate.

## Blockers

- None.

## Next action

Commit and push this final evidence record. Keep PR #34 in draft until Frank
explicitly approves merging the clean baseline into `main`. After merge, tag
the clean checkpoint and open Phase 4 on a fresh isolated branch.

## Frank's decision required

- Approve or defer merging draft PR #34 into `main`.
- A new TestFlight build is not required for this behavior-neutral cleanup.
- Any future TestFlight delivery or App Store review change still requires
  Frank's explicit approval.
