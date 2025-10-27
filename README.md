# ETF Universe

Public repository for a CAD-denominated ETF dataset with live snapshots and daily technical analytics.

- **Owner:** `gregstoltz`
- **Repo:** `etf-universe`
- **Default branch:** `main`
- **Source of truth:** Google Sheet (`NEW_SHEET_ID`) with a key tab named `SCAN`
- **Outputs:**
  - `live/` — latest CSV snapshots (overwritten by pushes from Apps Script)
  - `sheets/` — mirrored copies of specific tabs pulled by GitHub Actions (optional)
  - `daily/` — optional append-only artifacts

## Data pipeline (high level)
- **Priority:** GoogleFinance → Yahoo → Barchart → TMX → MarketWatch  
- **Currency:** all prices normalized to CAD  
- **Analytics:** Trend, Momentum, Volatility, Flow (25% each) ⇒ `TA_Score` (0–100), `Macro_Adj` (–10..+10), `Final_Signal` (BUY / HOLD / SELL)

See detailed docs in `docs/`.
