#!/usr/bin/env bash
# Below F1 0.60, containment advisory MUST NOT fire.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$("$SKILL_DIR/scripts/title_match.sh" \
  "A Very Specific Topic" \
  "An Entirely Different Paper About Totally Unrelated Things")
# Report must NOT contain a containment advisory.
HAS_ADV=$(printf '%s' "$OUT" | jq -r '.token_containment_pct // "none"')
if [ "$HAS_ADV" != "none" ] && [ "$HAS_ADV" != "0" ]; then
    echo "FAIL: containment advisory fired on a bad match: $HAS_ADV" >&2
    exit 1
fi
echo "PASS: 04_bad_match_stays_partial"
