# KeyHollow Work Status

Updated: 2026-09-05
Branch: `feature/folder-presentation-addon`
Pull request: [#35](https://github.com/Frankbell84/KeyHollow/pull/35) (draft)

## Current task

Phase 4 is integrating the independently compiled folder/presentation add-on
through the app composition layer. The current milestone gives general image
files the same gallery thumbnail treatment as Photos imports, using only an
authenticated record-level read and encrypted presentation cache. Protected
store formats, existing vaults, and `.khvault` compatibility remain unchanged.
App Store review and TestFlight remain untouched.

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
- Merged the preflight cleanup through PR #34 and published the annotated
  `checkpoint/pre-phase-4-clean-baseline` rollback tag at `69154ff`.
- Created `feature/folder-presentation-addon` directly from that clean tagged
  checkpoint.
- Added the first independently compiled Phase 4 module:
  `KeyHollowFolderPresentationAddOn`.
- Defined neutral photo/general-file references, folder membership records, and
  scoped cryptographic access without importing either protected content store.
- Added an encrypted presentation store whose folder deletion and reconciliation
  operations cannot delete protected photos or general files.
- Added authenticated local thumbnail persistence as opaque bytes so image
  generation and decoding remain outside the module.
- Added folder lifecycle, input validation, encrypted-at-rest thumbnail,
  reconciliation, and vault-access mismatch tests.
- Opened draft PR #35 so all remote Mac and security gates run before UI
  composition begins.

## Test and build status

- Architecture boundary gate: passed locally.
- Release-hygiene gate: passed locally.
- TestFlight build-number guard self-test: passed locally.
- Whitespace and obsolete-status audit: passed locally.
- Final merged-baseline CI run [#216](https://github.com/Frankbell84/KeyHollow/actions/runs/33986912069)
  at `7fb5487`: passed.
- Mac simulator build and complete regression/security suite: passed in 6m49s.
- Both first-party add-ons compiled under strict concurrency with
  warnings-as-errors; no add-on diagnostics remained.
- Deterministic architecture-specific simulator selection removed the prior
  multiple-destination warning.
- Artifact uploads through the pinned Node 24 action: passed; simulator and
  security-test artifacts were produced with recorded SHA-256 digests.
- Swift CodeQL: passed with no failed security gate.
- PR #34 merged into `main` as `69154ff`; all required checks were green.
- Phase 4 inherits that green baseline.
- Phase 4 architecture boundary gate: passed locally.
- Phase 4 release-hygiene gate: passed locally.
- Phase 4 whitespace audit: passed locally.
- Thumbnail-composition architecture and release-hygiene gates: passed locally.
- Thumbnail-composition build-number guard self-test: passed locally.
- Thumbnail-composition diff integrity check: passed locally.
- Remote Phase 4 run [#222](https://github.com/Frankbell84/KeyHollow/actions/runs/33992220446)
  rejected `b55e40a` at compile time because the optional general-file content
  type was not explicitly unwrapped before creating `UTType`. The architecture
  and hygiene steps passed; tests did not run after the compiler stopped.
- The thumbnail path now safely requires a non-nil content type before image
  preview work begins. Files without a declared image type remain accessible
  through their normal generic tile and are never guessed from untrusted bytes.
- Corrected Phase 4 run [#223](https://github.com/Frankbell84/KeyHollow/actions/runs/33993203704)
  at `55366a2`: passed in 23m31s.
- Mac simulator build and complete regression/security suite: passed in 6m34s.
- Swift CodeQL: passed in 22m46s with no failed security gate.
- Security-test and simulator artifacts were produced with recorded SHA-256
  digests.
- Definitive Phase 4 run [#219](https://github.com/Frankbell84/KeyHollow/actions/runs/33989008013)
  at `802252d`: passed in 28m43s.
- Mac simulator build and complete regression/security suite: passed in 7m37s.
- Swift CodeQL: passed in 27m04s with no failed security gate.
- Simulator and test artifacts were produced with recorded SHA-256 digests.
- Authenticated general-file preview read, scoped folder-presentation access,
  presentation-aware vault cleanup, and the gallery thumbnail view seam were
  checkpointed and pushed as `57ed011`.
- Completed root-gallery composition for images imported through Files: the app
  first loads an authenticated encrypted presentation thumbnail, otherwise it
  decrypts only the selected manifest record, creates a bounded 512-pixel JPEG,
  and stores that preview in the independent encrypted presentation add-on.
- Added cancellation checks to authenticated general-file reads and a strict
  2 MiB presentation-thumbnail ceiling with regression coverage.
- Ordered presentation-store initialization before file records appear so a
  fast first render cannot skip thumbnail generation.

## Blockers

- None.

## Next action

Begin the visible folder milestone: create folders, show root/folder contents,
move photo and general-file references through neutral add-on interfaces, and
delete folders without deleting protected content. Preserve current selection,
import, export, and restore behavior, then run the same local and remote gates.

## Frank's decision required

- No routine decision is currently required; Frank explicitly started Phase 4.
- Folder and presentation implementation may proceed autonomously within the
  documented acceptance criteria.
- Any future TestFlight delivery or App Store review change still requires
  Frank's explicit approval.
