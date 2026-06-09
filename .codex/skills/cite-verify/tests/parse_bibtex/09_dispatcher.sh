#!/usr/bin/env bash
# Verify parse_citation.sh routes a .bib file to parse_bibtex.py.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Use fixture 01 as the input file.
OUT=$("$SKILL_DIR/scripts/parse_citation.sh" --file "$SKILL_DIR/tests/parse_bibtex/01_apa_suffix.bib")

# Expect a JSON array with 3 entries (NAS 2022a/b/c).
COUNT=$(printf '%s' "$OUT" | jq 'length')
if [ "$COUNT" != "3" ]; then
    echo "FAIL: dispatcher returned $COUNT records, want 3" >&2
    exit 1
fi
echo "PASS: 09_dispatcher"
