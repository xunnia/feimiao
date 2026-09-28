# Soft-delete repair verification

Status: CANDIDATE_ONLY. Do not merge or distribute until the gates below pass.

## Observed failure

Run 34683924098, job 103527438586, revision 84ae9f1:
`testTransferRejectsDeletedTargetAccount` failed because the soft-delete flag
was false after `ModelContext.save()`. Transfer creation then succeeded and
left one transaction instead of zero. These assertions were read from the
authenticated GitHub job page, not inferred from the CoreData diagnostic tail.

## Candidate

Revision 820e6d3 changes persisted domain flags on Account, PhysicalAsset and
ReceivableAsset to `isSoftDeleted`, avoiding SwiftData's `isDeleted` state.
`@Attribute(originalName: "isDeleted")` supplies the old-name migration hint.
Consumers and predicates use the domain flag. Backup DTOs and Android import
keys remain unchanged. No store URL, Bundle ID or account UUID is changed.

The migration hint is not proof of a successful legacy-store upgrade.

## Tests and boundaries

- Existing transfer rejection test still checks both the thrown error and zero
  inserted transactions; no assertion was removed.
- Added on-disk store reopen test for the flag and rejected transfer.
- Added export/import test retaining the legacy JSON key and account UUID.
- Windows diff checks passed. Windows cannot execute SwiftData/XCTest.
- macOS verification: https://github.com/xunnia/feimiao/actions/runs/34700751822
- Verified job results: core tests, Simulator compilation, App XCTest and
  unsigned device packaging all passed for revision 820e6d3. Screenshot capture
  was still running at the last check. Test counts were not extracted from the
  full log; a green job is not evidence of a legacy-store upgrade.

## Required before promotion

1. App XCTest and all existing tests pass on the candidate revision.
2. Verify Account, PhysicalAsset and ReceivableAsset persistence and restoration.
3. Freeze the legacy model graph with an explicit versioned migration contract,
   per p0_product_contract.json, and open an actual pre-change store using the
   candidate. Assert UUIDs, relationships, flags, balances and media survive.
   A new-store reopen or JSON round trip cannot replace this test.
4. Exercise upgrade failure and rollback without clearing the old store.
5. Capture account selection/list states with the same fixture on both platforms
   before marking the user-visible behavior complete.

If an old build already discarded a flag on save, a rename cannot reconstruct
that lost intent. Do not infer deletion from missing activity or invent values;
use a verified backup or report the unrecoverable field explicitly.

This candidate does not close P0 or authorize P1 UI expansion. Signing and the
remaining parity gates stay open. The parent revision is 84ae9f1; no production
release or main-branch merge was performed.
