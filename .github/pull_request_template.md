## Scope

- [ ] This review has one purpose and does not mix architecture work with feature expansion.
- [ ] This change contains no customer-facing feature, or the feature is an independently compiled `KeyHollow<Feature>AddOn` under `KeyHollow/AddOns/<Feature>`.

## Mandatory architecture contract

- [ ] The add-on exposes narrow interfaces and minimum value types.
- [ ] The protected core does not import or depend on the add-on.
- [ ] Concrete wiring is confined to the application composition layer.
- [ ] Platform, network, cloud, analytics, advertising, and purchase SDKs remain outside the local vault core.
- [ ] Existing vault data and `.khvault` compatibility are preserved, or a versioned migration is separately reviewed.
- [ ] Failure, cancellation, interruption, and removal leave the protected core and source data intact.

## Required evidence before merge

- [ ] Architecture boundary enforcement passed.
- [ ] Complete simulator build and regression/security test suite passed.
- [ ] Swift CodeQL completed with no unresolved security findings.
- [ ] Production-identity TestFlight build completed.
- [ ] Physical-iPhone validation passed, including core regression and data-integrity checks.
- [ ] Final merge was explicitly approved after all evidence was recorded.
