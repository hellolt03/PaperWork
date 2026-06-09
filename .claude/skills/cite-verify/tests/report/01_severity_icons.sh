#!/usr/bin/env bash
# report.sh renders an icon for each verdict class.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/verdicts.jsonl" <<'JSONL'
{"index":1,"status":"VERIFIED","claimed":{"raw":"A","title":"A","authors":[],"year":"2020","doi":null},"lookup_mode":"doi","lookup":{"ok":true,"records":[]},"match":{"verdict":"EXACT","f1":1}}
{"index":2,"status":"PARTIAL_MATCH","claimed":{"raw":"B","title":"B","authors":[],"year":"2020","doi":null},"lookup_mode":"doi","lookup":{"ok":true,"records":[]},"match":{"verdict":"WEAK_MATCH","f1":0.7}}
{"index":3,"status":"METADATA_MISMATCH","claimed":{"raw":"C","title":"C","authors":[],"year":"2020","doi":"10.1/x"},"lookup_mode":"doi","lookup":{"ok":true,"records":[{"title":"Different","authors":[],"year":"2020","DOI":"10.1/x","type":"journal-article","publisher":"","container":"","URL":"","subtitle":""}]},"match":{"verdict":"MISMATCH","f1":0.1}}
{"index":4,"status":"NOT_FOUND","claimed":{"raw":"D","title":"D","authors":[],"year":"2020","doi":null},"lookup_mode":"search","lookup":{"ok":false,"error":"not found","records":[]},"match":{"verdict":"MISMATCH","f1":0}}
{"index":5,"status":"NEEDS_MANUAL_VERIFICATION","claimed":{"raw":"E","title":null,"authors":[],"year":null,"doi":null},"lookup_mode":"n/a","lookup":{"ok":false,"error":"python3 unavailable","records":[]},"match":{"verdict":"NEEDS_MANUAL_VERIFICATION","f1":0},"diagnosis":{"reason":"python3_unavailable","context":"install Python 3.9+"}}
JSONL

OUT=$("$SKILL_DIR/scripts/report.sh" "$TMP/verdicts.jsonl")

# Each status must map to a distinctive icon character cluster.
for want in "[OK]" "[?]" "[!]" "[X]" "[TODO]"; do
    if ! printf '%s' "$OUT" | grep -qF "$want"; then
        echo "FAIL: report missing severity icon cluster $want" >&2
        printf '%s\n' "$OUT" >&2
        exit 1
    fi
done
echo "PASS: 01_severity_icons"
