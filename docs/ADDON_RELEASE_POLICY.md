# KeyHollow Add-on Release Policy

This policy is mandatory for every customer-facing capability added after the
validated modular baseline. A feature is not eligible for production merely
because it works locally.

## Module contract

1. Put implementation in `KeyHollow/AddOns/<Feature>`.
2. Compile it as the static target `KeyHollow<Feature>AddOn`.
3. Expose only the minimum protocols and value types required by callers.
4. Let the add-on depend on approved core interfaces; never let crypto, vault,
   photo-storage, session, or transfer code import the add-on.
5. Wire the concrete add-on only from the application composition layer.
6. Keep UI, Apple frameworks, network clients, cloud SDKs, analytics, ads, and
   purchases outside the protected local vault core.
7. Avoid shared mutable global state. Cancellation, locking, and sensitive-data
   lifetime must remain explicit at interface boundaries.

## Compatibility contract

- Existing vaults must open without conversion or data loss.
- `.khvault` compatibility must be preserved. Format changes require versioned
  decoding, hostile-input tests, rollback tests, and a separately reviewed
  migration plan.
- A failed, canceled, or interrupted add-on operation must not damage the
  source vault, source Photos items, or a previously valid export.
- Removing or disabling an add-on must leave the protected core operational.

## Required release gates

Every feature follows this order:

1. Isolated feature branch and draft pull request.
2. Narrow-interface and dependency-direction review.
3. Architecture boundary gate.
4. Complete simulator build, unit, security, lifecycle, and launch tests.
5. Swift CodeQL analysis with no unresolved security findings.
6. Production-identity TestFlight build from a guarded delivery branch.
7. Physical-iPhone testing of the feature, core regressions, interruptions,
   low-storage behavior, and rollback/data-integrity behavior.
8. Explicit approval to merge only after all evidence is recorded.

No gate may be skipped because a feature is small, urgent, or UI-only.
