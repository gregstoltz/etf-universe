#!/usr/bin/env python3
"""
Merge CSV 'old' + 'new' while only rewriting the last N days.

- Keeps all rows from OLD where Date < cutoff_date
- Replaces rows for Date >= cutoff_date with rows from NEW (so new data & recalcs win)
- Ensures header equality; sorts by Date ascending at the end
- Assumes a 'Date' column (configurable via --date-col)

Usage:
  ./scripts/merge_last_days.py \
      --old sheets/H_XIU.csv \
      --new /tmp/H_XIU.new.csv \
      --out sheets/H_XIU.csv \
      --keep-days 30 \
      --date-col Date
"""
import argparse, csv, sys, datetime, os

def parse_date(s):
    # Accept "YYYY-MM-DD", "YYYY-MM-DD HH:MM", or ISO-like "YYYY-MM-DDTHH:MM:SSZ"
    s = s.strip()
    if not s:
        return None
    # Just take date-part before space or 'T'
    s = s.split('T')[0].split(' ')[0]
    return datetime.date.fromisoformat(s)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", required=False, help="Existing CSV path (optional if none yet)")
    ap.add_argument("--new", required=True, help="Fresh export CSV path")
    ap.add_argument("--out", required=True, help="Output CSV path to write")
    ap.add_argument("--keep-days", type=int, default=30)
    ap.add_argument("--date-col", default="Date")
    args = ap.parse_args()

    # Read NEW
    with open(args.new, newline='', encoding="utf-8") as f:
        r = csv.reader(f)
        new_rows = list(r)
    if not new_rows:
        print("ERROR: new CSV is empty", file=sys.stderr)
        sys.exit(2)

    header = new_rows[0]
    try:
        di = header.index(args.date_col)
    except ValueError:
        print(f"ERROR: date column '{args.date_col}' not found in NEW header", file=sys.stderr)
        sys.exit(2)

    # Read OLD if present
    old_rows = []
    if args.old and os.path.exists(args.old) and os.path.getsize(args.old) > 0:
        with open(args.old, newline='', encoding="utf-8") as f:
            r = csv.reader(f)
            old_rows = list(r)
        if not old_rows:
            old_rows = [header]
        # Header check
        if old_rows[0] != header:
            print("WARNING: headers differ; using NEW header & NEW data for recent window", file=sys.stderr)

    cutoff = datetime.date.today() - datetime.timedelta(days=args.keep_days)

    # Index NEW by date for >= cutoff
    new_recent = {}
    for row in new_rows[1:]:
        if len(row) != len(header):
            # skip malformed rows quietly
            continue
        d = parse_date(row[di])
        if d is None:
            continue
        if d >= cutoff:
            new_recent[d] = row

    # Start with OLD rows strictly before cutoff
    merged = [header]
    old_body = old_rows[1:] if old_rows else []
    for row in old_body:
        if len(row) != len(header):
            continue
        try:
            d = parse_date(row[di])
        except Exception:
            continue
        if d is None:
            continue
        if d < cutoff:
            merged.append(row)

    # Add all rows from NEW for >= cutoff (covers new days + replacement of last 30d)
    # If multiple rows per date exist in NEW, latest wins due to dict overwrite above.
    for d in sorted(new_recent.keys()):
        merged.append(new_recent[d])

    # Sort overall by Date ascending (in case OLD portion wasn’t perfectly sorted)
    body = merged[1:]
    body_sorted = sorted(body, key=lambda r: parse_date(r[di]))
    merged = [header] + body_sorted

    # Write OUT
    with open(args.out, "w", newline='', encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerows(merged)

if __name__ == "__main__":
    main()
