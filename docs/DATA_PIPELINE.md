# Data Pipeline

**Priority order:** GoogleFinance → Yahoo → Barchart → TMX → MarketWatch  
**Currency:** Normalize all prices to CAD.  
**Freshness:** Live snapshots (`live/`) overwrite; daily artifacts (`daily/`) are append-only.

Primary files:
- `live/SCAN.csv` — current scan page export
- `daily/` — optional end-of-day artifacts
