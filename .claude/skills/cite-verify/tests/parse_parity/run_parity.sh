#!/usr/bin/env bash
# run_parity.sh - verify APA and BibTeX forms produce equivalent normalized JSON.
# Allowed differences per fixture: only the `type` field and venue-vs-null where
# documented. All core fields (authors, year, title, doi) MUST match after normalization.
#
# Normalization applied to both sides before diff:
#   - year: coerced to string (APA path emits number, BibTeX path emits string)
#   - authors: reduced to sorted surnames (first token before comma, lowercase)
#     This handles APA "Smith" vs BibTeX "Smith, John" discrepancy.
#   - title: lowercased for case-insensitive comparison
#   - doi: lowercased
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STEM="$1"
DIR="$SKILL_DIR/tests/parse_parity"

APA_OUT=$("$SKILL_DIR/scripts/parse_citation.sh" "$(cat "$DIR/$STEM.apa.txt")")
BIB_OUT=$("$SKILL_DIR/scripts/parse_citation.sh" --file "$DIR/$STEM.bib")

# BibTeX returns a JSON array; APA returns a single object. Extract first record.
BIB_FIRST=$(printf '%s' "$BIB_OUT" | jq '.[0]')

# Per CCG-on-plan B2 (Codex) and spec section B1 (Gemini): parity projection
# covers all normalized output fields except the documented allowed-diffs.
# Allowed diffs: `type` (APA path has no type field),
# `venue` when absent in APA but extractable from BibTeX booktitle/journal.
# Everything else (authors, year, title, doi) MUST match after normalization.
#
# Normalization jq expression applied to BOTH sides:
#   - year: tostring so number/string difference is irrelevant
#   - authors: each author reduced to surname (text before first comma, or whole
#     value if no comma), then sorted for order-independence
#   - title: ascii_downcase for case-insensitive match
#   - doi: ascii_downcase (DOI registry is case-insensitive)
NORMALIZE='
  def surname: split(",")[0] | ascii_downcase | ltrimstr(" ") | rtrimstr(" ");
  {
    authors: ([(.authors // []) | .[] | surname] | sort),
    year: ((.year // null) | if . == null then null else tostring end),
    title: ((.title // null) | if . == null then null else ascii_downcase end),
    doi: ((.doi // null) | if . == null then null else ascii_downcase end)
  }
'

CORE_APA=$(printf '%s' "$APA_OUT" | jq --sort-keys "$NORMALIZE")
CORE_BIB=$(printf '%s' "$BIB_FIRST" | jq --sort-keys "$NORMALIZE")

# Venue parity check: applied only when the APA output has a non-null venue.
# Skipped when APA path returns no venue (which is common - APA path focuses
# on author/year/title/DOI and does not extract journal names).
APA_VENUE=$(printf '%s' "$APA_OUT" | jq -r '.venue // empty')
if [ -n "$APA_VENUE" ]; then
    BIB_VENUE=$(printf '%s' "$BIB_FIRST" | jq -r '.venue // empty')
    if [ "$APA_VENUE" != "$BIB_VENUE" ]; then
        echo "FAIL: venue parity drift on $STEM - apa=$APA_VENUE bib=$BIB_VENUE" >&2
        exit 1
    fi
fi

if ! diff <(echo "$CORE_APA") <(echo "$CORE_BIB"); then
    echo "FAIL: parity drift on $STEM" >&2
    echo "APA: $CORE_APA" >&2
    echo "BIB: $CORE_BIB" >&2
    exit 1
fi
echo "PASS: parity/$STEM"
