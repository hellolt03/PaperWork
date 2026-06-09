#!/usr/bin/env bash
# Strip "2nd edition" from both sides before F1. Harrell 2015 case.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$("$SKILL_DIR/scripts/title_match.sh" \
  "Regression Modeling Strategies, 2nd edition" \
  "Regression Modeling Strategies")
VERDICT=$(printf '%s' "$OUT" | jq -r '.verdict')
if [ "$VERDICT" != "EXACT" ] && [ "$VERDICT" != "STRONG" ] && [ "$VERDICT" != "STRONG_MATCH" ]; then
    echo "FAIL: got $VERDICT, want EXACT or STRONG after edition strip" >&2
    echo "$OUT" >&2
    exit 1
fi
echo "PASS: 01_edition_normalization"
