#!/usr/bin/env bash
# Negative: "The Complete Edition of Shakespeares Works" must NOT have
# "edition" stripped (no preceding ordinal or modifier).
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$("$SKILL_DIR/scripts/title_match.sh" \
  "The Complete Edition of Shakespeares Works" \
  "The Complete Edition of Shakespeares Works")
VERDICT=$(printf '%s' "$OUT" | jq -r '.verdict')
if [ "$VERDICT" != "EXACT" ]; then
    echo "FAIL: edition regex over-stripped a legitimate title; got $VERDICT" >&2
    echo "$OUT" >&2
    exit 1
fi
echo "PASS: 05_edition_in_title"
