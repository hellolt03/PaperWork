#!/usr/bin/env bash
# report.sh emits a DUPLICATE_ENTRY warning when a DOI repeats.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/verdicts.jsonl" <<'JSONL'
{"index":1,"status":"VERIFIED","claimed":{"raw":"Smith 2020 A Paper","title":"A Paper","authors":["Smith"],"year":"2020","doi":"10.1/abc"},"lookup_mode":"doi","lookup":{"ok":true,"records":[]},"match":{"verdict":"EXACT","f1":1}}
{"index":2,"status":"VERIFIED","claimed":{"raw":"Smith 2020 A Paper","title":"A Paper","authors":["Smith"],"year":"2020","doi":"10.1/abc"},"lookup_mode":"doi","lookup":{"ok":true,"records":[]},"match":{"verdict":"EXACT","f1":1}}
{"index":3,"status":"VERIFIED","claimed":{"raw":"Jones 2021 Another","title":"Another","authors":["Jones"],"year":"2021","doi":"10.2/xyz"},"lookup_mode":"doi","lookup":{"ok":true,"records":[]},"match":{"verdict":"EXACT","f1":1}}
JSONL

OUT=$("$SKILL_DIR/scripts/report.sh" "$TMP/verdicts.jsonl")

if ! printf '%s' "$OUT" | grep -qi "DUPLICATE_ENTRY"; then
    echo "FAIL: no duplicate warning emitted" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
if ! printf '%s' "$OUT" | grep -q "10.1/abc"; then
    echo "FAIL: duplicate warning does not name the offending DOI" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
echo "PASS: 03_duplicate_entry"
