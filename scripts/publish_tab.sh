#!/usr/bin/env bash
set -euo pipefail

# publish_tab.sh — Export one Google Sheets tab and publish ChatGPT-friendly artifacts.
#
# What it does:
#   1) Export <TabName> via gid → sheets/<TabName>.csv
#   2) (Optional) Incremental merge for H_* / TA_*: rewrite only last N days
#   3) Build artifacts in live/<TabName>/:
#       - head.csv (first 200 rows)
#       - schema.json (headers + counts)
#       - part-00001.csv, part-00002.csv, ... (chunked, header repeated)
#       - compact.jsonl (row-wise JSON for easy parsing)
#       - manifest.json (absolute raw URLs to everything)
#
# Usage:
#   scripts/publish_tab.sh \
#     --sheet-id "$SHEET_ID" \
#     --tab-name "SCAN" \
#     --gid "1375435285" \
#     --branch "main" \
#     [--incremental-days 30] \
#     [--date-col Date] \
#     [--chunk-size 500]
#
# Env needed in GitHub Actions:
#   - GITHUB_REPOSITORY (auto-provided) → e.g., gregstoltz/etf-universe
#
# Requires: curl, jq, python3, coreutils (head, split), awk, sed

# ------------------------- arg parsing -------------------------
SHEET_ID=""
TAB_NAME=""
GID=""
BRANCH="main"
INCREMENTAL_DAYS=""
DATE_COL="Date"
CHUNK_SIZE="500"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sheet-id)         SHEET_ID="$2"; shift 2 ;;
    --tab-name)         TAB_NAME="$2"; shift 2 ;;
    --gid)              GID="$2"; shift 2 ;;
    --branch)           BRANCH="$2"; shift 2 ;;
    --incremental-days) INCREMENTAL_DAYS="$2"; shift 2 ;;
    --date-col)         DATE_COL="$2"; shift 2 ;;
    --chunk-size)       CHUNK_SIZE="$2"; shift 2 ;;
    *)
      echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SHEET_ID" || -z "$TAB_NAME" || -z "$GID" ]]; then
  echo "Usage: $0 --sheet-id <ID> --tab-name <Name> --gid <gid> [--branch main] [--incremental-days 30] [--date-col Date] [--chunk-size 500]" >&2
  exit 2
fi

# ------------------------- deps check -------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 3; }; }
need curl
need jq
need python3
need awk
need sed
need head
need split

# ------------------------- setup -------------------------
REPO="${GITHUB_REPOSITORY:-gregstoltz/etf-universe}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

TAB_SAFE="$(echo "$TAB_NAME" | tr ' ' '_' )"
SHEETS_DIR="sheets"
LIVE_DIR="live/${TAB_SAFE}"
mkdir -p "$SHEETS_DIR" "$LIVE_DIR" /tmp

CSV_PATH="${SHEETS_DIR}/${TAB_SAFE}.csv"
TMP_NEW="/tmp/${TAB_SAFE}.new.csv"

echo "::group::Export ${TAB_NAME} (gid=${GID})"
curl -sSL \
  "https://docs.google.com/spreadsheets/d/${SHEET_ID}/export?format=csv&gid=${GID}" \
  -o "${TMP_NEW}"
if [[ ! -s "${TMP_NEW}" ]]; then
  echo "ERROR: Exported CSV is empty for tab ${TAB_NAME} (gid=${GID})." >&2
  exit 4
fi
echo "::endgroup::"

# ------------------------- incremental merge (optional) -------------------------
# Only apply to H_* and TA_* tabs if INCREMENTAL_DAYS is set.
if [[ -n "${INCREMENTAL_DAYS}" && ( "${TAB_SAFE}" == H_* || "${TAB_SAFE}" == TA_* ) ]]; then
  echo "::group::Incremental merge (last ${INCREMENTAL_DAYS} days) for ${TAB_NAME}"
  # If there's no existing CSV, this is effectively a first publish.
  if [[ -f "${CSV_PATH}" && -s "${CSV_PATH}" ]]; then
    python3 - "$CSV_PATH" "$TMP_NEW" "$CSV_PATH" "$INCREMENTAL_DAYS" "$DATE_COL" <<'PY'
import sys, csv, datetime, os

old_path, new_path, out_path, keep_days_s, date_col = sys.argv[1:]
keep_days = int(keep_days_s)

def parse_date(s):
    s = (s or "").strip()
    if not s: return None
    s = s.split('T')[0].split(' ')[0]
    return datetime.date.fromisoformat(s)

# read new
with open(new_path, newline='', encoding='utf-8') as f:
    r = csv.reader(f)
    new_rows = list(r)
if not new_rows:
    print("ERROR: new CSV empty", file=sys.stderr); sys.exit(5)
header = new_rows[0]
try:
    di = header.index(date_col)
except ValueError:
    print(f"ERROR: date column '{date_col}' missing in NEW header", file=sys.stderr); sys.exit(6)

# read old
old_rows = []
if os.path.exists(old_path) and os.path.getsize(old_path) > 0:
    with open(old_path, newline='', encoding='utf-8') as f:
        r = csv.reader(f)
        old_rows = list(r)
    if not old_rows: old_rows = [header]

cutoff = datetime.date.today() - datetime.timedelta(days=keep_days)

# Build new_recent keyed by date for >= cutoff
new_recent = {}
for row in new_rows[1:]:
    if len(row) != len(header): continue
    d = parse_date(row[di])
    if d is None: continue
    if d >= cutoff: new_recent[d] = row

merged = [header]
# Keep old rows strictly before cutoff
for row in (old_rows[1:] if old_rows else []):
    if len(row) != len(header): continue
    try:
        d = parse_date(row[di])
    except Exception:
        continue
    if d is None: continue
    if d < cutoff: merged.append(row)

# Add/replace with NEW for >= cutoff
for d in sorted(new_recent.keys()):
    merged.append(new_recent[d])

# Sort by date ascending
body = merged[1:]
body_sorted = sorted(body, key=lambda r: parse_date(r[di]) or datetime.date.min)
merged = [header] + body_sorted

with open(out_path, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerows(merged)
PY
  else
    # first publish
    mv "${TMP_NEW}" "${CSV_PATH}"
  fi
  echo "::endgroup::"
else
  # no incremental: replace fully
  mv "${TMP_NEW}" "${CSV_PATH}"
fi

# ------------------------- artifacts -------------------------
echo "::group::Build artifacts for ${TAB_NAME}"
head -n 200 "${CSV_PATH}" > "${LIVE_DIR}/head.csv"

HEADER="$(head -n 1 "${CSV_PATH}")"
if [[ -z "${HEADER}" ]]; then
  echo "ERROR: Header missing in ${CSV_PATH}" >&2; exit 7
fi
COLS=$(echo "$HEADER" | awk -F',' '{print NF}')
ROWS=$(( $(wc -l < "${CSV_PATH}") - 1 ))

jq -n \
  --arg tab "$TAB_NAME" \
  --arg header "$HEADER" \
  --argjson cols "$COLS" \
  --argjson rows "$ROWS" \
  '{
     tab: $tab,
     header: ($header | split(",")),
     column_count: $cols,
     row_count: $rows,
     source_csv: "sheets/\($tab|gsub(" ";"_")).csv"
   }' > "${LIVE_DIR}/schema.json"

# Chunk (header repeated)
tail -n +2 "${CSV_PATH}" > "/tmp/${TAB_SAFE}.nohdr.csv" || true
# If there are no data rows, still publish a single part with just header
rm -f "${LIVE_DIR}/part-"*.csv 2>/dev/null || true
if [[ ! -s "/tmp/${TAB_SAFE}.nohdr.csv" ]]; then
  printf "part-%05d.csv" 1 > "/tmp/${TAB_SAFE}.partname"
  { echo "$HEADER"; } > "${LIVE_DIR}/$(cat /tmp/${TAB_SAFE}.partname)"
else
  split -l "${CHUNK_SIZE}" -d --additional-suffix=.csv "/tmp/${TAB_SAFE}.nohdr.csv" "/tmp/${TAB_SAFE}.part-"
  i=0
  for f in /tmp/${TAB_SAFE}.part-*.csv; do
    [[ -f "$f" ]] || continue
    i=$((i+1))
    printf -v part "part-%05d.csv" "$i"
    { echo "$HEADER"; cat "$f"; } > "${LIVE_DIR}/${part}"
  done
fi

# JSONL
python3 - "$CSV_PATH" "${LIVE_DIR}/compact.jsonl" <<'PY'
import sys, csv, json, pathlib
src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
with src.open(newline='', encoding='utf-8') as f, dst.open('w', encoding='utf-8') as out:
    r = csv.DictReader(f)
    for row in r:
        for k,v in list(row.items()):
            if v is None or v == "":
                continue
            try:
                if v.isdigit():
                    row[k] = int(v)
                else:
                    row[k] = float(v)
            except Exception:
                pass
        out.write(json.dumps(row, ensure_ascii=False) + "\n")
PY

# Manifest (absolute URLs)
mapfile -t PARTS < <(ls "${LIVE_DIR}"/part-*.csv 2>/dev/null | sort)
PARTS_JSON=$(printf '%s\n' "${PARTS[@]}" | sed 's|^|/|' | jq -R . | jq -s .)

jq -n \
  --arg tab "$TAB_NAME" \
  --arg created "$(date -u +%FT%TZ)" \
  --arg base "$RAW_BASE" \
  --arg live "/${LIVE_DIR}" \
  --arg header "$HEADER" \
  --argjson cols "$COLS" \
  --argjson rows "$ROWS" \
  --argfile parts <(echo "${PARTS_JSON:-[]}") \
  '{
     tab: $tab,
     version: "v1",
     created_utc: $created,
     header: ($header | split(",")),
     column_count: $cols,
     row_count: $rows,
     artifacts: {
       head:   { path: ($live + "/head.csv"),    url: ($base + $live + "/head.csv") },
       schema: { path: ($live + "/schema.json"), url: ($base + $live + "/schema.json") },
       jsonl:  { path: ($live + "/compact.jsonl"), url: ($base + $live + "/compact.jsonl") }
     },
     chunks: ($parts | map({ path: ., url: ($base + .) }))
   }' > "${LIVE_DIR}/manifest.json"
echo "::endgroup::"

echo "::notice title=Published::live/${TAB_SAFE}/manifest.json ready (plus chunks, head, schema, jsonl)"
