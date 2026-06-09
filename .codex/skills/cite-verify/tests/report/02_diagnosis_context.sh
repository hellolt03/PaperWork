#!/usr/bin/env bash
# report.sh renders diagnosis.reason and diagnosis.context as sub-bullets.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/verdicts.jsonl" <<'JSONL'
{"index":1,"status":"NEEDS_MANUAL_VERIFICATION","claimed":{"raw":"X","title":null,"authors":[],"year":null,"doi":null},"lookup_mode":"n/a","lookup":{"ok":false,"error":"parse error","records":[]},"match":{"verdict":"NEEDS_MANUAL_VERIFICATION","f1":0},"diagnosis":{"reason":"bibtex_parse_error","context":"parse failed at line 42: unexpected token"}}
JSONL

OUT=$("$SKILL_DIR/scripts/report.sh" "$TMP/verdicts.jsonl")

if ! printf '%s' "$OUT" | grep -q "bibtex_parse_error"; then
    echo "FAIL: missing reason" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
if ! printf '%s' "$OUT" | grep -q "line 42"; then
    echo "FAIL: missing context line hint" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
echo "PASS: 02_diagnosis_context"
