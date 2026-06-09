#!/usr/bin/env bash
# Containment advisory: F1 in [0.60, 0.85) AND title is 90%-substring -> advisory fires.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Citation: "Can You Build a Better Cop"; Crossref: "Can You Build a Better Cop?
# Experimental Evidence on Supervision, Training, and Policing in the Community"
OUT=$("$SKILL_DIR/scripts/title_match.sh" \
  "Can You Build a Better Cop" \
  "Can You Build a Better Cop Experimental Evidence on Supervision Training and Policing in the Community")
VERDICT=$(printf '%s' "$OUT" | jq -r '.verdict')
if [ "$VERDICT" = "EXACT" ] || [ "$VERDICT" = "STRONG" ] || [ "$VERDICT" = "STRONG_MATCH" ]; then
    echo "FAIL: long-title containment should NOT auto-promote to VERIFIED/EXACT" >&2
    exit 1
fi
# Extract token_containment_pct from title_match.sh output.
OVERLAP=$(printf '%s' "$OUT" | jq -r '.token_containment_pct // 0')
if [ "$(printf '%s' "$OVERLAP" | awk '{print ($1 >= 0.90)}')" != "1" ]; then
    echo "FAIL: containment_overlap_pct=$OVERLAP, want >= 0.90" >&2
    exit 1
fi
echo "PASS: 03_containment_advisory"
