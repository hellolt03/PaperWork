#!/usr/bin/env bash
# parse_citation.sh — extract structured fields from a single citation string
#
# Usage: parse_citation.sh "<raw citation text>"
# Output: single-line JSON {authors, year, title, doi, nber_number, arxiv_id}
#
# Scope: v0.1 handles the common academic citation shapes (APA, Chicago,
# naive BibTeX). Full parser fidelity for every citation style is a
# deliberate non-goal — the tool is a fuzzy extractor, not a lexer.
# The downstream matcher (title_match.sh) tolerates minor field errors.
#
# Security: treats input as opaque bytes, never interpolates into shell
# commands. Normalizes control characters and null bytes before pattern
# matching. Length-bounded at 4 KB per citation to prevent pathological
# input from hanging the extractor.

set -euo pipefail

# v0.2 dispatcher: when invoked with --file <path>, detect .bib input and
# route to scripts/parse_bibtex.py via python3 -I. Otherwise the existing
# single-citation path (one raw citation in argv[1]) is preserved byte-
# compatible with v0.1.
if [ "${1:-}" = "--file" ] && [ -n "${2:-}" ]; then
    SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    INPUT_PATH="$2"

    is_bibtex=0
    case "$INPUT_PATH" in
        *.bib|*.bibtex) is_bibtex=1 ;;
    esac
    if [ "$is_bibtex" -eq 0 ]; then
        FIRSTLINE=$(grep -m1 -E '^[[:space:]]*[^[:space:]]' "$INPUT_PATH" || true)
        case "$FIRSTLINE" in
            @article\{*|@book\{*|@inproceedings\{*|@incollection\{*|@misc\{*|@techreport\{*|@unpublished\{*|@phdthesis\{*|@mastersthesis\{*)
                is_bibtex=1 ;;
        esac
    fi

    if [ "$is_bibtex" -eq 1 ]; then
        if ! command -v python3 >/dev/null 2>&1; then
            jq -n --arg err "python3_unavailable" '{error:$err}'
            exit 3
        fi
        # Memory cap 256MB, wall-clock 10s. Isolated mode. Vendor on path.
        export PYTHONPATH="$SKILL_DIR/vendor"
        ulimit -v 262144 2>/dev/null || true
        timeout 10s python3 -I "$SKILL_DIR/scripts/parse_bibtex.py" "$INPUT_PATH"
        exit $?
    fi

    # Non-BibTeX file input: read line-by-line and run the existing
    # single-citation path per non-blank line. (Placeholder for v0.2 line mode;
    # lint.sh already iterates per-line so this path remains a pass-through.)
    exec cat "$INPUT_PATH"
fi

if [ "$#" -ne 1 ]; then
    jq -n --arg err "usage: parse_citation.sh <citation text>" '{error:$err}'
    exit 2
fi

RAW="$1"

# Length bound — no citation should exceed 4 KB in real use.
if [ ${#RAW} -gt 4096 ]; then
    jq -n --arg err "citation exceeds 4096 byte limit" '{error:$err}'
    exit 2
fi

# Strip null bytes and normalize line endings / control characters.
CLEANED=$(printf '%s' "$RAW" | tr -d '\000' | tr '\r' ' ' | tr '\n' ' ' | tr -s '[:space:]' ' ')

# --- Extract DOI ---
# DOI pattern: 10.{registrant}/{suffix} with safe characters only.
DOI=$(printf '%s' "$CLEANED" | grep -oE '10\.[0-9]+/[A-Za-z0-9._:;()/-]+' | head -n 1 || true)
# Strip trailing punctuation that often appears after a DOI in prose.
DOI=$(printf '%s' "$DOI" | sed -E 's/[.,;:)\]]+$//')

# --- Extract NBER working paper number ---
# Matches "NBER Working Paper 33344", "NBER w33344", "NBER Working Paper No. 33344".
NBER=$(printf '%s' "$CLEANED" | grep -oE '([Nn][Bb][Ee][Rr][^0-9]{0,40}|\bw)([0-9]{3,7})\b' | head -n 1 || true)
if [ -n "$NBER" ]; then
    NBER=$(printf '%s' "$NBER" | grep -oE '[0-9]{3,7}$' || true)
fi

# --- Extract arXiv ID ---
# Modern form: YYMM.NNNNN (4-5 digit suffix), optionally with v1/v2 version.
# Old form: subject-class/YYMMNNN.
ARXIV=$(printf '%s' "$CLEANED" | grep -oE '(arXiv:|arxiv\.org/(abs|pdf)/)?[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?' | head -n 1 || true)
if [ -n "$ARXIV" ]; then
    ARXIV=$(printf '%s' "$ARXIV" | grep -oE '[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?' || true)
    # Strip version suffix for canonical form.
    ARXIV=$(printf '%s' "$ARXIV" | sed -E 's/v[0-9]+$//')
fi

# --- Extract year ---
# Look for a 4-digit year between 1800 and 2099, preferably in parentheses.
YEAR=$(printf '%s' "$CLEANED" | grep -oE '\((18|19|20)[0-9]{2}[a-z]?\)' | head -n 1 | grep -oE '(18|19|20)[0-9]{2}' || true)
if [ -z "$YEAR" ]; then
    # Fall back to any 4-digit year-looking token.
    YEAR=$(printf '%s' "$CLEANED" | grep -oE '\b(18|19|20)[0-9]{2}\b' | head -n 1 || true)
fi
# APA suffix normalization: (2022a) -> 2022. Strip a single lowercase letter
# immediately following the 4-digit year if the year is in the valid range.
if [ -n "$YEAR" ]; then
    YEAR=$(printf '%s' "$YEAR" | sed -E 's/^(18|19|20)([0-9]{2})[a-z]?$/\1\2/')
fi

# --- Extract authors ---
# Authors are typically the chunk before the year. Take the substring
# from the start of the citation up to the first year (or first 200 chars
# as a safety cap) and extract surnames.
AUTHOR_CHUNK=""
if [ -n "$YEAR" ]; then
    AUTHOR_CHUNK=$(printf '%s' "$CLEANED" | awk -v yr="$YEAR" '{
        idx = index($0, yr);
        if (idx > 1) {
            print substr($0, 1, idx - 1);
        } else {
            print substr($0, 1, 200);
        }
    }')
else
    AUTHOR_CHUNK=$(printf '%s' "$CLEANED" | cut -c1-200)
fi

# Heuristic: capitalized words with 3+ letters are probably surnames.
# This is imperfect but works for APA/Chicago/Harvard where author lists
# come first. Avoid tokens like "A", "J", "&", "and".
AUTHORS_JSON=$(printf '%s' "$AUTHOR_CHUNK" | \
    tr ',&' ' ' | \
    tr ' ' '\n' | \
    grep -E '^[A-Z][a-zA-Z'\''-]{2,}$' | \
    grep -vE '^(And|The|Of|In|With|For|From|To)$' | \
    head -n 10 | \
    jq -R . | jq -s .)

# --- Extract title ---
# Heuristic: the title is usually the longest meaningful chunk between
# the year and the venue. Look for text between the year and the next
# period that's followed by a space and a capital letter (which usually
# starts the venue).
TITLE=""
if [ -n "$YEAR" ]; then
    # Everything after the year.
    AFTER_YEAR=$(printf '%s' "$CLEANED" | awk -v yr="$YEAR" '{
        idx = index($0, yr);
        if (idx > 0) {
            print substr($0, idx + length(yr));
        } else {
            print $0;
        }
    }')
    # Strip leading punctuation/whitespace after the year.
    AFTER_YEAR=$(printf '%s' "$AFTER_YEAR" | sed -E 's/^[).,:;]+[[:space:]]*//; s/^[[:space:]]+//')
    # Take up to the first sentence-ending period (followed by space
    # and capital letter, typical in APA: "Title. Journal").
    TITLE=$(printf '%s' "$AFTER_YEAR" | awk '{
        match($0, /\. [A-Z]/);
        if (RSTART > 0) {
            print substr($0, 1, RSTART - 1);
        } else {
            print $0;
        }
    }')
    # Strip quotes/braces that are purely delimiters.
    TITLE=$(printf '%s' "$TITLE" | sed -E 's/^["\'\''`{]+//; s/["\'\''`}]+$//')
    # Length bound.
    TITLE=$(printf '%s' "$TITLE" | cut -c1-500)
fi

# Emit the structured record. jq -n --arg for every string so no
# interpolation can inject into the JSON. -c for compact single-line
# output so downstream while-read loops work correctly.
jq -nc \
    --arg doi    "${DOI:-}" \
    --arg nber   "${NBER:-}" \
    --arg arxiv  "${ARXIV:-}" \
    --arg year   "${YEAR:-}" \
    --arg title  "${TITLE:-}" \
    --arg raw    "$CLEANED" \
    --argjson authors "${AUTHORS_JSON:-[]}" \
    '{
        raw: $raw,
        authors: $authors,
        year: (if $year == "" then null else ($year | tonumber) end),
        title: $title,
        doi: (if $doi == "" then null else $doi end),
        nber_number: (if $nber == "" then null else $nber end),
        arxiv_id: (if $arxiv == "" then null else $arxiv end)
    }'
