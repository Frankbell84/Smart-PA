# KeyHollow Development Checkpoint

**Updated:** September 5, 2026
**Purpose:** Durable restart point immediately before Phase 4.

## Executive status

- The compiled modular foundation is complete and merged.
- The exact modular baseline is preserved by tag
  `checkpoint/modular-baseline-build-13` at `1913d43`.
- `KeyHollowCryptoCore`, `KeyHollowVaultCore`, `KeyHollowPhotoCore`,
  `KeyHollowTransferCore`, and `KeyHollowPhotosAdapter` are independently
  compiled behind one-way dependency boundaries.
- `.khvault` File Recognition and the isolated Quick Look thumbnail extension
  are merged through PR #32 at `24cfc57` and validated on a physical iPhone.
- General File Support is merged through PR #33 at `bbd6bfa` after Build 29
  passed physical-iPhone validation.
- Build 29 proved direct general-file import, unified photo/file presentation,
  and mixed photo/file `.khvault` export and restore.
- App Store review was not changed by these development merges.

## Current architecture

The protected modules own cryptography, credential persistence, encrypted photo
storage, portable transfer, and Apple Photos integration. Customer-facing
features are separate static add-ons under `KeyHollow/AddOns`. Add-ons may use
narrow core interfaces, but the protected core never imports an add-on.
Concrete wiring belongs only to the app composition and presentation layer.

The architecture gate enforces compiled targets, dependency direction,
framework allowlists, add-on isolation, and warning-as-error settings for every
first-party add-on. The release-hygiene gate rejects temporary files, editor
debris, and abandoned document-icon implementations.

## Validated evidence

- Architecture boundary gate: passed.
- Release-hygiene gate: passed.
- Complete simulator build and regression/security suite: passed.
- Swift CodeQL analysis: passed with no unresolved changed-code alerts.
- Production-identity TestFlight Build 29: processed and assigned internally.
- Physical-device validation: passed by the owner.
- General-file-support merge: `bbd6bfa` on `main`.

## Phase 4 scope

Phase 4 is the folder and presentation add-on. It must begin from current
`main` on a new isolated feature branch and draft pull request. Its initial
acceptance requirements are:

1. Add folder organization without merging or replacing protected stores.
2. Preserve all existing vaults and `.khvault` compatibility.
3. Give images imported through Files safe local encrypted thumbnails and the
   same polished grid treatment as Photo-library imports.
4. Keep metadata editing separate from import; expose it only through a
   deliberate post-import settings or item-details surface.
5. Leave the protected core functional if the add-on is removed or disabled.

## Required Phase 4 gates

1. Isolated branch and draft review.
2. Narrow-interface and dependency-direction review.
3. Architecture and release-hygiene enforcement.
4. Warning-free simulator build plus full unit, lifecycle, transfer, security,
   and launch tests.
5. Swift CodeQL with no unresolved findings.
6. Guarded production-identity TestFlight delivery branch.
7. Physical-iPhone feature, interruption, low-storage, rollback, and
   data-integrity testing.
8. Explicit owner approval only after all evidence is recorded.

## Known non-blocking boundaries

- UI and navigation intentionally remain in the application target; they are
  composition and presentation, not protected-core responsibilities.
- Build numbers advance only on guarded delivery branches. Source `main` is the
  feature baseline and must not be confused with a specific TestFlight build.
- App Store submission remains a separate owner decision.

## Resume instruction

Read this file and `WORK_STATUS.md`, fetch remote `main`, and verify that the
expected head has not changed. Complete the preflight cleanup review before
creating the Phase 4 folder/presentation branch. Do not reuse the completed
General File Support or delivery branches.
