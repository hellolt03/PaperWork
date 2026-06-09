#!/usr/bin/env bash
# Adversarial: 99% containment AND F1=0.62 -> verdict stays PARTIAL_MATCH (NOT auto-upgraded).
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$("$SKILL_DIR/scripts/title_match.sh" \
  "A Short Title of the Paper" \
  "A Short Title of the Paper Volume 1 With Additional Subtitle That Extends Meaningful Tokens")
VERDICT=$(printf '%s' "$OUT" | jq -r '.verdict')
# PARTIAL_MATCH equivalents: WEAK_MATCH (the matcher's internal label for f1 in [0.40, 0.70)).
case "$VERDICT" in
    EXACT|STRONG_MATCH) echo "FAIL: auto-promoted to $VERDICT, must stay PARTIAL" >&2; exit 1 ;;
esac
echo "PASS: 06_advisory_no_verdict_change (verdict=$VERDICT)"
