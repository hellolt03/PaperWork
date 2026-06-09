#!/usr/bin/env bash
# Book-vs-chapter advisory: when Crossref top hit is a book-chapter but a book
# record exists for same first-author+year with F1>0.85, the verdict STAYS
# PARTIAL_MATCH but the report/audit-log gains an advisory_book_candidate field.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Three stubs to exercise the full predicate surface per CCG-on-plan B1:
#   (1) happy path - matching author+year+F1>0.85 -> advisory fires
#   (2) wrong author - must NOT fire
#   (3) F1 too low   - must NOT fire

STUB_OK=$(cat <<'JSON'
{
  "top_hit": {"type": "book-chapter", "doi": "10.17226/chap1", "title": "Chapter 1"},
  "siblings": [
    {"type": "monograph", "doi": "10.17226/24928", "title": "Proactive Policing",
     "first_author": "NAS", "year": 2018, "f1_against_citation": 0.92}
  ],
  "citation": {"first_author": "NAS", "year": 2018, "title": "Proactive Policing"}
}
JSON
)
STUB_WRONG_AUTHOR=$(cat <<'JSON'
{
  "top_hit": {"type": "book-chapter", "doi": "10.17226/chap1", "title": "Chapter 1"},
  "siblings": [
    {"type": "monograph", "doi": "10.17226/99999", "title": "Proactive Policing",
     "first_author": "SomebodyElse", "year": 2018, "f1_against_citation": 0.92}
  ],
  "citation": {"first_author": "NAS", "year": 2018, "title": "Proactive Policing"}
}
JSON
)
STUB_LOW_F1=$(cat <<'JSON'
{
  "top_hit": {"type": "book-chapter", "doi": "10.17226/chap1", "title": "Chapter 1"},
  "siblings": [
    {"type": "monograph", "doi": "10.17226/88888", "title": "A Completely Different Book",
     "first_author": "NAS", "year": 2018, "f1_against_citation": 0.40}
  ],
  "citation": {"first_author": "NAS", "year": 2018, "title": "Proactive Policing"}
}
JSON
)

# Case 1: advisory MUST fire with the correct DOI.
ADV=$(printf '%s' "$STUB_OK" | "$SKILL_DIR/scripts/lint.sh" --advisory-probe 2>/dev/null || echo "{}")
TYPE=$(printf '%s' "$ADV" | jq -r '.type // "none"')
if [ "$TYPE" != "book_candidate" ]; then
    echo "FAIL: STUB_OK advisory.type=$TYPE, want book_candidate" >&2
    echo "$ADV" >&2
    exit 1
fi
CAND_DOI=$(printf '%s' "$ADV" | jq -r '.doi // ""')
if [ "$CAND_DOI" != "10.17226/24928" ]; then
    echo "FAIL: STUB_OK advisory.doi=$CAND_DOI, want 10.17226/24928" >&2
    exit 1
fi

# Case 2: wrong author MUST suppress the advisory.
ADV=$(printf '%s' "$STUB_WRONG_AUTHOR" | "$SKILL_DIR/scripts/lint.sh" --advisory-probe 2>/dev/null || echo "{}")
TYPE=$(printf '%s' "$ADV" | jq -r '.type // "none"')
if [ "$TYPE" = "book_candidate" ]; then
    echo "FAIL: STUB_WRONG_AUTHOR fired advisory despite author mismatch" >&2
    exit 1
fi

# Case 3: F1 below 0.85 MUST suppress.
ADV=$(printf '%s' "$STUB_LOW_F1" | "$SKILL_DIR/scripts/lint.sh" --advisory-probe 2>/dev/null || echo "{}")
TYPE=$(printf '%s' "$ADV" | jq -r '.type // "none"')
if [ "$TYPE" = "book_candidate" ]; then
    echo "FAIL: STUB_LOW_F1 fired advisory despite F1<0.85" >&2
    exit 1
fi

echo "PASS: 02_book_chapter_advisory (3 predicates)"
