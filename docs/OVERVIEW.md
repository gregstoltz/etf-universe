# Overview

This repository stores ETF data and analytics exported from a Google Sheet (Apps Script push) and/or mirrored via GitHub Actions (pull).

- Use **Apps Script push** for authoritative CSVs into `live/`.
- Optionally enable **GitHub Actions pull** to mirror a visible `SCAN` tab into `sheets/SCAN.csv`.
