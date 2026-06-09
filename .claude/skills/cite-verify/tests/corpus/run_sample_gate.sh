#!/usr/bin/env bash
# run_sample_gate.sh - v0.2 ship gate for the sample regression corpus.
# Checks TWO conditions per entry:
#   (1) verdict label matches expected
#   (2) matched record ID (DOI) matches expected_doi from manifest
# Either miss fails the gate. Per CCG A3, aggregate counts alone are insufficient.
#
# Process substitution (done < <(jq ...)) keeps the loop body in the parent
# shell so $FAILS increments survive. A pipe (jq | while read) would run the
# loop in a subshell, silently zeroing $FAILS and making the gate always pass
# (CCG-on-plan A4).
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CORPUS="$SKILL_DIR/tests/corpus/sample-2026-04-24.bib"
MANIFEST="$SKILL_DIR/tests/corpus/sample-2026-04-24.expected.json"

# Run lint.sh and capture verdicts.jsonl via --emit-verdicts.
# lint.sh exits 1 when NOT_FOUND or METADATA_MISMATCH entries exist (expected in
# this corpus). Capture the exit code separately; the gate checks verdicts directly.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
"$SKILL_DIR/scripts/lint.sh" --emit-verdicts "$TMP/actual.jsonl" "$CORPUS" > /dev/null || true

FAILS=0
# Process substitution: loop stays in parent shell; $FAILS increments are live.
while IFS= read -r exp; do
    KEY=$(printf '%s' "$exp" | jq -r '.entry_key')
    WANT_V=$(printf '%s' "$exp" | jq -r '.expected_verdict')
    WANT_DOI=$(printf '%s' "$exp" | jq -r '.expected_doi')
    WANT_ADV=$(printf '%s' "$exp" | jq -r '.expected_advisory // "none"')

    ACTUAL=$(grep "\"entry_key\":\"$KEY\"" "$TMP/actual.jsonl" || true)
    if [ -z "$ACTUAL" ]; then
        echo "FAIL: $KEY - no matching record in actual output" >&2
        FAILS=$((FAILS + 1)); continue
    fi
    GOT_V=$(printf '%s' "$ACTUAL" | jq -r '.status')
    GOT_DOI=$(printf '%s' "$ACTUAL" | jq -r '.matched.doi // ""')
    GOT_ADV=$(printf '%s' "$ACTUAL" | jq -r '.advisory.type // "none"')

    if [ "$GOT_V" != "$WANT_V" ]; then
        echo "FAIL: $KEY - verdict got=$GOT_V want=$WANT_V" >&2
        FAILS=$((FAILS + 1))
    fi
    if [ "$WANT_DOI" != "null" ] && [ "$GOT_DOI" != "$WANT_DOI" ]; then
        echo "FAIL: $KEY - DOI got=$GOT_DOI want=$WANT_DOI" >&2
        FAILS=$((FAILS + 1))
    fi
    if [ "$WANT_ADV" != "none" ] && [ "$GOT_ADV" != "$WANT_ADV" ]; then
        echo "FAIL: $KEY - advisory.type got=$GOT_ADV want=$WANT_ADV" >&2
        FAILS=$((FAILS + 1))
    fi
done < <(jq -c '.[]' "$MANIFEST")

if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: Sample ship gate - $FAILS mismatches" >&2
    exit 1
fi
echo "PASS: Sample ship gate (all entries match label AND record-ID)"
