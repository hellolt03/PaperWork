#!/usr/bin/env bash
# Automated canary: LMR w33344 fabricated-title must return METADATA_MISMATCH.
# If this ever passes as VERIFIED or PARTIAL_MATCH, the whole tool value prop is gone.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CORPUS="$SKILL_DIR/tests/corpus/known-hallucination.bib"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
"$SKILL_DIR/scripts/lint.sh" --emit-verdicts "$TMP/actual.jsonl" "$CORPUS" > /dev/null || true

STATUS=$(jq -r '.status' "$TMP/actual.jsonl")
if [ "$STATUS" != "METADATA_MISMATCH" ]; then
    echo "FAIL: known-hallucination returned $STATUS, want METADATA_MISMATCH" >&2
    cat "$TMP/actual.jsonl" >&2
    exit 1
fi
echo "PASS: known_hallucination_gate"
