# V2 Beta Isolation Boundary

The encrypted-vault-transfer work is developed and tested outside the V1
release line.

## Repository boundary

- Production remains on `main`.
- V2 integration occurs only on
  `integration/v2-encrypted-vault-transfer`.
- The V2 pull request must remain a draft until every release gate below is
  complete.
- No V2 commit may be merged into `main` merely to obtain CI or device builds.

## Device boundary

- V1 bundle identifier: `com.keyhollow.app`
- V2 beta bundle identifier: `com.keyhollow.app.beta`
- V2 display name: `KeyHollow Beta`

The separate bundle identifier gives the beta its own application container,
preferences, Keychain access group, and local vault storage. Installing or
deleting KeyHollow Beta must not upgrade, replace, or delete the production
KeyHollow app or its vaults.

The production TestFlight upload workflow is also restricted to `main`. A
separate signing profile and beta delivery workflow must be created before a
V2 beta can be installed on physical devices through TestFlight.

## Release gates

1. Existing V1 unit, security, launch, Copy, Move, and lifecycle tests remain
   green on the V2 integration branch.
2. All portable-archive tamper, hostile-input, collision, cancellation, and
   rollback tests pass.
3. Export and import receive an isolated user interface with clear recovery
   credential, progress, cancellation, storage, and no-source-deletion rules.
4. Repeated `.khvault` transfers succeed between two physical iPhones.
5. Forced termination is tested at every export and import commit boundary.
6. Large-vault testing demonstrates bounded memory and sufficient-storage
   failure handling.
7. The V2 beta is independently reviewed before any merge into `main`.
