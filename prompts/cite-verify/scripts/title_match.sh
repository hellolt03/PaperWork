#!/usr/bin/env bash
# title_match.sh — hardened title matcher for cite-verify
#
# Compares two title strings and emits a structured JSON verdict.
# Usage: title_match.sh "EXPECTED TITLE" "CANONICAL TITLE"
#
# Design notes (responding to adversarial review findings):
# - Uses F1 (precision + recall) to resist the subset attack where a truncated
#   hallucination scores 1.0 on recall alone. "Large Language Models" vs
#   "Large Language Models: An Applied Econometric Framework" now scores as
#   PARTIAL_MATCH (F1 ~0.6), not VERIFIED.
# - Preserves whitespace when stripping punctuation (the original spec had a
#   bug where stripping all non-alphanumeric characters also deleted spaces).
# - Stopword filtering prevents "On the" from dominating short-title scores.
# - Minimum 3 meaningful tokens required before fuzzy matching is trusted.
# - Unicode normalization via iconv ASCII//TRANSLIT handles accented characters
#   and common transliterations (Mueller/Müller).
# - LaTeX commands and math mode stripped before tokenization.
# - Multiset semantics via sort + comm -12 (preserves repetition count).
# - No bash 4+ features: works on stock macOS Bash 3.2.
#
# Output: single-line JSON with verdict, f1, precision, recall, tokens.

set -euo pipefail

TMPDIR_LOCAL=$(mktemp -d -t citeverify-match)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT INT TERM

if [ "$#" -ne 2 ]; then
    printf '%s\n' '{"error":"usage: title_match.sh EXPECTED CANONICAL","verdict":"ERROR"}'
    exit 2
fi

EXPECTED_RAW="$1"
CANONICAL_RAW="$2"

# Stopwords — common English function words that inflate scores if retained.
STOPWORDS=" a an the of in on at to for with and or but is are was were be been being as by from into about over under above below its this that these those it "

# strip_edition: remove edition markers from already-lowercased titles.
# Called AFTER Stage 5 (lowercase). Uses portable sed without \b or /i flags.
# Fires ONLY when "edition" or "ed." is preceded by an ordinal or known modifier;
# bare "edition" (e.g. "the complete edition of shakespeare") is kept intact.
# Pattern structure: (space-or-start)(modifier)(space)(edition-token)(space-or-end).
# We replace the whole match with a single space to preserve surrounding tokens.
strip_edition() {
    local text="$1"
    # Numeric ordinals: 1st, 2nd, 3rd, 4th ... 99th edition/ed.
    text=$(printf '%s' "$text" | sed -E 's/(^|[[:space:]])(1st|2nd|3rd|[0-9]+th)[[:space:]]+(edition|ed\.)([[:space:]]|$)/ /g')
    # Written ordinals: first, second ... tenth edition/ed.
    text=$(printf '%s' "$text" | sed -E 's/(^|[[:space:]])(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)[[:space:]]+(edition|ed\.)([[:space:]]|$)/ /g')
    # Modifier words: revised, updated, expanded, student, international, anniversary edition/ed.
    text=$(printf '%s' "$text" | sed -E 's/(^|[[:space:]])(revised|updated|expanded|student|international|anniversary)[[:space:]]+(edition|ed\.)([[:space:]]|$)/ /g')
    # rev. ed. shorthand
    text=$(printf '%s' "$text" | sed -E 's/(^|[[:space:]])rev\.?[[:space:]]+ed\.?([[:space:]]|$)/ /g')
    # Collapse any runs of spaces left behind.
    text=$(printf '%s' "$text" | tr -s ' ')
    printf '%s' "$text"
}

# normalize: apply the full normalization pipeline to a single string.
# Input: $1 (raw text)
# Output: normalized text on stdout (never fails, falls back to identity)
normalize() {
    local text="$1"
    local out
    # Stage 1: Unicode → ASCII decomposition and combining mark removal.
    # We use Perl because macOS BSD iconv's ASCII//TRANSLIT produces quote-
    # prefix artifacts (e.g. "Ö" → `"O` instead of `O`) that corrupt tokens.
    # Perl's Unicode::Normalize has been core since 5.8 (2002) and works
    # identically on macOS and Linux. NFD splits accented chars into base +
    # combining mark, then `\p{Mn}+` strips the marks, leaving ASCII.
    if command -v perl >/dev/null 2>&1; then
        out=$(printf '%s' "$text" | perl -CSDA -MUnicode::Normalize -0777 -pe '$_ = NFD($_); s/\p{Mn}+//g' 2>/dev/null) || out="$text"
    else
        out=$(printf '%s' "$text" | iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null) || out="$text"
    fi
    # Stage 2: strip LaTeX math mode ($...$) — do this before command stripping
    # so that $\ell_1$ is removed entirely rather than being partially preserved.
    out=$(printf '%s\n' "$out" | sed -E 's/\$[^$]*\$//g')
    # Stage 3: strip LaTeX commands of the form \cmd{arg} — keep the arg.
    out=$(printf '%s\n' "$out" | sed -E 's/\\[a-zA-Z]+\{([^{}]*)\}/\1/g')
    # Stage 4: strip bare LaTeX commands \cmd.
    out=$(printf '%s\n' "$out" | sed -E 's/\\[a-zA-Z]+//g')
    # Stage 5: lowercase.
    out=$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')
    # Stage 5.5: strip edition markers after lowercasing so patterns are case-stable.
    # Fires only when "edition" or "ed." is preceded by an ordinal/modifier; bare
    # "edition" (e.g. "the complete edition of shakespeare") is kept intact.
    out=$(strip_edition "$out")
    # Stage 6: strip null bytes explicitly — bash can't carry them.
    out=$(printf '%s' "$out" | tr -d '\000')
    # Stage 7: replace any character that isn't alphanumeric OR whitespace
    # with a single space. This fixes the original spec bug where whitespace
    # was deleted along with punctuation.
    out=$(printf '%s' "$out" | LC_ALL=C tr -c 'a-zA-Z0-9[:space:]' ' ')
    # Stage 8: collapse all whitespace runs (spaces, tabs, newlines) to one space.
    out=$(printf '%s' "$out" | tr -s '[:space:]' ' ')
    # Stage 9: trim leading and trailing spaces.
    out=$(printf '%s' "$out" | sed -E 's/^ +//; s/ +$//')
    printf '%s' "$out"
}

EXPECTED_NORM=$(normalize "$EXPECTED_RAW")
CANONICAL_NORM=$(normalize "$CANONICAL_RAW")

# Shortcut: exact match after normalization.
if [ -n "$EXPECTED_NORM" ] && [ "$EXPECTED_NORM" = "$CANONICAL_NORM" ]; then
    jq -n \
        --arg en "$EXPECTED_NORM" \
        --arg cn "$CANONICAL_NORM" \
        '{verdict:"EXACT", f1:1.0, precision:1.0, recall:1.0, expected_normalized:$en, canonical_normalized:$cn, reason:"normalized strings are identical"}'
    exit 0
fi

# Write tokens one-per-line to temp files so we can use sort/comm for multiset ops.
# This also neatly handles the bash 3.2 "no associative arrays" constraint.
printf '%s\n' $EXPECTED_NORM | tr ' ' '\n' | sed '/^$/d' > "$TMPDIR_LOCAL/expected_all.txt"
printf '%s\n' $CANONICAL_NORM | tr ' ' '\n' | sed '/^$/d' > "$TMPDIR_LOCAL/canonical_all.txt"

# Filter stopwords. A word is a stopword iff " word " appears in $STOPWORDS.
filter_stopwords_file() {
    local src="$1"
    local dst="$2"
    : > "$dst"
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        if ! printf '%s' "$STOPWORDS" | grep -qF " $tok "; then
            printf '%s\n' "$tok" >> "$dst"
        fi
    done < "$src"
}

filter_stopwords_file "$TMPDIR_LOCAL/expected_all.txt"   "$TMPDIR_LOCAL/expected_mf.txt"
filter_stopwords_file "$TMPDIR_LOCAL/canonical_all.txt" "$TMPDIR_LOCAL/canonical_mf.txt"

EXPECTED_COUNT=$(wc -l < "$TMPDIR_LOCAL/expected_mf.txt" | tr -d ' ')
CANONICAL_COUNT=$(wc -l < "$TMPDIR_LOCAL/canonical_mf.txt" | tr -d ' ')

# Minimum meaningful token guard. Short expected titles cannot be fuzzy-matched
# safely because a 1-2 token expected can collide with many unrelated papers.
if [ "$EXPECTED_COUNT" -lt 3 ]; then
    jq -n \
        --arg en "$EXPECTED_NORM" \
        --arg cn "$CANONICAL_NORM" \
        --argjson ec "$EXPECTED_COUNT" \
        --argjson cc "$CANONICAL_COUNT" \
        '{verdict:"INSUFFICIENT", f1:0.0, precision:0.0, recall:0.0, expected_normalized:$en, canonical_normalized:$cn, expected_meaningful_count:$ec, canonical_meaningful_count:$cc, reason:"expected title has fewer than 3 meaningful tokens after stopword filtering; fuzzy matching would be unsafe, manual verification required"}'
    exit 0
fi

# Multiset intersection via sort + comm -12.
# comm -12 on two sorted files produces lines present in BOTH, with
# count equal to min(count_in_A, count_in_B) per unique line. That is
# exactly the multiset intersection cardinality we want.
sort "$TMPDIR_LOCAL/expected_mf.txt"  > "$TMPDIR_LOCAL/expected_sorted.txt"
sort "$TMPDIR_LOCAL/canonical_mf.txt" > "$TMPDIR_LOCAL/canonical_sorted.txt"
INTERSECTION_COUNT=$(comm -12 "$TMPDIR_LOCAL/expected_sorted.txt" "$TMPDIR_LOCAL/canonical_sorted.txt" | wc -l | tr -d ' ')

# Guard against canonical being empty (can happen if canonical is all stopwords).
if [ "$CANONICAL_COUNT" -eq 0 ]; then
    jq -n \
        --arg en "$EXPECTED_NORM" \
        --arg cn "$CANONICAL_NORM" \
        '{verdict:"INSUFFICIENT", f1:0.0, precision:0.0, recall:0.0, expected_normalized:$en, canonical_normalized:$cn, reason:"canonical title has no meaningful tokens after stopword filtering"}'
    exit 0
fi

# Compute precision, recall, f1 in awk (bash has no float arithmetic).
read -r PRECISION RECALL F1 <<AWK_END
$(awk -v i="$INTERSECTION_COUNT" -v e="$EXPECTED_COUNT" -v c="$CANONICAL_COUNT" 'BEGIN {
    p = (c > 0) ? i / c : 0
    r = (e > 0) ? i / e : 0
    f = (p + r > 0) ? (2 * p * r) / (p + r) : 0
    printf "%.6f %.6f %.6f\n", p, r, f
}')
AWK_END

# Verdict thresholds (chosen to reflect codex's findings):
# - f1 >= 0.85 → STRONG_MATCH: very high confidence, essentially verified
# - f1 >= 0.70 → MATCH: verified with normal confidence (e.g., subtitle added)
# - f1 >= 0.40 → WEAK_MATCH: probably related but needs manual confirmation
# - f1 <  0.40 → MISMATCH: clearly different papers
VERDICT=$(awk -v f="$F1" 'BEGIN {
    if      (f >= 0.85) print "STRONG_MATCH"
    else if (f >= 0.70) print "MATCH"
    else if (f >= 0.40) print "WEAK_MATCH"
    else                print "MISMATCH"
}')

# Token-containment computation (non-promoting advisory data).
# Measures token-recall on the shorter side: intersection / min(expected, canonical)
# meaningful token count. When the shorter title's tokens are fully contained in
# the longer, this equals 1.0 (perfect containment). Advisory fires in lint.sh
# only if F1 in [0.60, 0.85) AND this value >= 0.90.
MIN_COUNT=$EXPECTED_COUNT
if [ "$CANONICAL_COUNT" -lt "$MIN_COUNT" ]; then
    MIN_COUNT=$CANONICAL_COUNT
fi
OVERLAP_PCT=0
if [ "$MIN_COUNT" -gt 0 ] && [ "$INTERSECTION_COUNT" -gt 0 ]; then
    OVERLAP_PCT=$(awk -v i="$INTERSECTION_COUNT" -v m="$MIN_COUNT" 'BEGIN{printf "%.2f", i/m}')
fi

jq -n \
    --arg v "$VERDICT" \
    --arg en "$EXPECTED_NORM" \
    --arg cn "$CANONICAL_NORM" \
    --argjson f1 "$F1" \
    --argjson p  "$PRECISION" \
    --argjson r  "$RECALL" \
    --argjson ic "$INTERSECTION_COUNT" \
    --argjson ec "$EXPECTED_COUNT" \
    --argjson cc "$CANONICAL_COUNT" \
    --argjson overlap "$OVERLAP_PCT" \
    '{
        verdict: $v,
        f1: $f1,
        precision: $p,
        recall: $r,
        intersection_count: $ic,
        expected_meaningful_count: $ec,
        canonical_meaningful_count: $cc,
        expected_normalized: $en,
        canonical_normalized: $cn,
        token_containment_pct: $overlap
    }'
