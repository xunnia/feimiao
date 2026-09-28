# P0 capture acceptance, 2026-09-20

Status: P0_PARTIAL. Capture infrastructure passed; product acceptance remains open.

## Verified run

- Repository: xunnia/feimiao, branch codex/screenshot-stability.
- Source: 76e093fe86f109b332edfff096e90ea038578605.
- Run: https://github.com/xunnia/feimiao/actions/runs/35508046549
- All five Android capture jobs, aggregate validation, iOS capture and comparison report succeeded.
- Android: 41 declared scenes. Comparison index: 40 pairs and one explicitly missing
  iOS target, assets-funds (P4). productComplete remains false.
- Business diff status is different, with exactly one reported path: platform
  (android versus ios). No other differences were reported for the exported projection.
  Do not equate this projection with coverage of all stores or user journeys.
- Statistics custom screenshot was visually inspected and correctly selects custom,
  rather than reusing the year page. The screenshot still has product differences:
  card order, chart forms, semantic colors and category labels need phase-owner review.

## Evidence locations

Downloaded report artifact 10605385240 and visual artifact 10605395277:

- Local: C:/src/xunni-codex/.tmp/parity-35508046549/report/
- Local: C:/src/xunni-codex/.tmp/parity-35508046549/visual/
- Android original artifact: 10604794427.
- iOS original artifact: 10603909014.

The report and visual files were downloaded and inspected. Full original image archives
from this run have not yet been archived locally; do so before Actions retention expiry.
Earlier-run originals must not replace this run's images or provenance.

## Remaining work

1. Independently archive original PNGs and metadata, verify hashes and establish
   durable storage outside disposable scratch directories.
2. Separate platform identity metadata from business equality in reporting, with
   tests that still reject real amount/date/entity differences. Do not silently
   ignore arbitrary fields or mark the existing raw report as matched.
3. Verify old QingJi store upgrade, Android v40/v48/current backup restore,
   attachment integrity and failure rollback on macOS. New-store reopen and JSON
   round-trip tests alone are insufficient.
4. Update the distribution contract to the user's Windows + iPhone Air iOS 27
   preview environment, ordinary Apple Account and no paid developer membership.
   macOS CI builds do not prove Windows resigning or device installation. Preserve
   full-extension versus no-extension limitations and require user-assisted testing.
5. Keep assets-funds assigned to P4 and visible UI differences assigned to their
   existing P1-P5 owners. These are not evidence-tool failures and not completed UI.

The successful source is the screenshot branch, not the separate iOS P1 candidate.
Do not claim candidate features were validated by this run. No main merge, production
release, device install or schema-upgrade acceptance was performed in this review.
