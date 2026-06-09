#!/usr/bin/env bash
# Verify the bash path strips APA a/b/c suffixes from the year field.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$("$SKILL_DIR/scripts/parse_citation.sh" \
  "National Academies of Sciences, Engineering, and Medicine (2022a). Proactive Policing. DOI 10.17226/24928")
YEAR=$(printf '%s' "$OUT" | jq -r '.year')
if [ "$YEAR" != "2022" ]; then
    echo "FAIL: got year=$YEAR, want 2022" >&2
    exit 1
fi
echo "PASS: 10_apa_suffix_stdin"
