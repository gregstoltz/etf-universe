# Runbook

Two ways to keep data fresh:

## A) Apps Script → push to GitHub (recommended for `live/`)
1) In Google Apps Script, store a GitHub token (one time).  
2) Set Settings!A:B keys in the Sheet (owner/repo/branch/base path).  
3) Run `pushScanToGitHub_()` for `live/SCAN.csv`.  
4) Optionally run `pushWholeWorkbookToGitHub_()` to export all tabs as CSV into `live/`.

## B) GitHub Actions → pull from Google Sheet (for mirroring)
- Publish the Sheet (or make it link-visible).
- Update the workflow `mirror-scan-pull.yml` with your Sheet ID.
- Run workflow → `sheets/SCAN.csv` updates inside the repo.

## Common Checks
- Confirm CSVs appear in `live/` or `sheets/` as intended.
- Branch protections on `main` if desired (CI should still push).
