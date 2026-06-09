#!/usr/bin/env bash
# report.sh — render a Markdown verification report from a verdicts.jsonl file
#
# Usage: report.sh <path-to-verdicts.jsonl>
#
# Output: Markdown report to stdout.
#
# Security: sanitizes all strings from external sources (Crossref) before
# embedding in the Markdown. Strips terminal control sequences, escapes
# Markdown metacharacters that could be used for report injection.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: report.sh <verdicts.jsonl>" >&2
    exit 2
fi

VERDICTS_FILE="$1"

if [ ! -f "$VERDICTS_FILE" ]; then
    echo "error: verdicts file not found: $VERDICTS_FILE" >&2
    exit 2
fi

# Sanitize a string for safe inclusion in Markdown.
# - Strip terminal control sequences (ESC-anything).
# - Strip non-printable characters except whitespace.
# - Escape Markdown metacharacters that could inject headings or code.
sanitize() {
    printf '%s' "$1" \
        | tr -d '\000-\010\013\014\016-\037\177' \
        | sed -E '
            s/\\/\\\\/g
            s/`/\\`/g
            s/\*/\\*/g
            s/_/\\_/g
            s/\[/\\[/g
            s/\]/\\]/g
            s/^#/\\#/g
            s/</\&lt;/g
            s/>/\&gt;/g
        '
}

# Map status to plaintext severity icon (no emoji per user constraint).
severity_icon() {
    case "$1" in
        VERIFIED)                  printf '[OK]' ;;
        PARTIAL_MATCH)             printf '[?]' ;;
        METADATA_MISMATCH)         printf '[!]' ;;
        NOT_FOUND)                 printf '[X]' ;;
        NEEDS_MANUAL_VERIFICATION) printf '[TODO]' ;;
        *)                         printf '[?]' ;;
    esac
}

# Count by status.
total=$(wc -l < "$VERDICTS_FILE" | tr -d ' ')
verified=$(grep -c '"status":"VERIFIED"' "$VERDICTS_FILE" || echo 0)
partial=$(grep -c '"status":"PARTIAL_MATCH"' "$VERDICTS_FILE" || echo 0)
metadata_mismatch=$(grep -c '"status":"METADATA_MISMATCH"' "$VERDICTS_FILE" || echo 0)
not_found=$(grep -c '"status":"NOT_FOUND"' "$VERDICTS_FILE" || echo 0)
needs_manual=$(grep -c '"status":"NEEDS_MANUAL_VERIFICATION"' "$VERDICTS_FILE" || echo 0)

# Strip newlines from counts (some shells leave whitespace).
verified=$(printf '%s' "$verified" | tr -d '[:space:]')
partial=$(printf '%s' "$partial" | tr -d '[:space:]')
metadata_mismatch=$(printf '%s' "$metadata_mismatch" | tr -d '[:space:]')
not_found=$(printf '%s' "$not_found" | tr -d '[:space:]')
needs_manual=$(printf '%s' "$needs_manual" | tr -d '[:space:]')

# Header.
cat <<HEADER
# cite-verify report

**Total citations checked:** $total
**Verified:** $verified
**Partial match:** $partial
**Metadata mismatch (likely hallucination):** $metadata_mismatch
**Not found:** $not_found
**Needs manual verification:** $needs_manual

HEADER

# DUPLICATE_ENTRY detection (Task 16, Tier-C per CCG).
# Group by DOI when present; else by raw citation string. Warn per duplicate key.
DUPES=$(jq -r '.claimed.doi // .claimed.raw' "$VERDICTS_FILE" | sort | uniq -d)
if [ -n "$DUPES" ]; then
    printf '### [WARN] DUPLICATE_ENTRY detected\n\n'
    printf '%s\n' "$DUPES" | while IFS= read -r key; do
        if [ -n "$key" ]; then
            printf '  - `%s` appears more than once in the input.\n' "$(sanitize "$key")"
        fi
    done
    printf '\n'
fi

# Critical issues section (metadata mismatches come first).
if [ "$metadata_mismatch" -gt 0 ] || [ "$not_found" -gt 0 ]; then
    printf '## Critical issues\n\n'
    while IFS= read -r verdict; do
        status=$(printf '%s' "$verdict" | jq -r '.status')
        case "$status" in
            METADATA_MISMATCH|NOT_FOUND) ;;
            *) continue ;;
        esac
        idx=$(printf '%s' "$verdict" | jq -r '.index')
        claimed_title=$(printf '%s' "$verdict" | jq -r '.claimed.title // ""')
        claimed_authors=$(printf '%s' "$verdict" | jq -r '.claimed.authors | join(", ")')
        claimed_year=$(printf '%s' "$verdict" | jq -r '.claimed.year // ""')
        canonical_title=$(printf '%s' "$verdict" | jq -r '.lookup.records[0].title // ""')
        canonical_authors=$(printf '%s' "$verdict" | jq -r '[.lookup.records[0].authors[]? | .family] | join(", ")')
        canonical_year=$(printf '%s' "$verdict" | jq -r '.lookup.records[0].year // ""')
        canonical_doi=$(printf '%s' "$verdict" | jq -r '.lookup.records[0].DOI // ""')
        lookup_mode=$(printf '%s' "$verdict" | jq -r '.lookup_mode')
        f1=$(printf '%s' "$verdict" | jq -r '.match.f1 // 0')

        printf '### %s: Citation #%s — %s\n\n' "$status" "$idx" "$(sanitize "$claimed_title")"
        printf '**You cited:** %s (%s). %s.\n\n' \
            "$(sanitize "$claimed_authors")" \
            "$(sanitize "$claimed_year")" \
            "$(sanitize "$claimed_title")"
        if [ "$status" = "METADATA_MISMATCH" ] && [ -n "$canonical_title" ]; then
            printf '**Canonical record at %s:** %s (%s). %s.\n\n' \
                "$(sanitize "$canonical_doi")" \
                "$(sanitize "$canonical_authors")" \
                "$(sanitize "$canonical_year")" \
                "$(sanitize "$canonical_title")"
            printf '**Diagnosis:** The identifier is real but the claimed title does not match. This is the LLM-hallucination pattern. Verify whether you intended to cite the canonical paper above, or whether you meant a different paper entirely. Title similarity F1: %s.\n\n' "$f1"
        else
            printf '**Diagnosis:** No matching record was found in Crossref via %s lookup. Manually verify the citation is real.\n\n' "$lookup_mode"
        fi
    done < "$VERDICTS_FILE"
fi

# Detailed findings.
printf '## All findings\n\n'
while IFS= read -r verdict; do
    idx=$(printf '%s' "$verdict" | jq -r '.index')
    status=$(printf '%s' "$verdict" | jq -r '.status')
    claimed_title=$(printf '%s' "$verdict" | jq -r '.claimed.title // ""')
    claimed_authors=$(printf '%s' "$verdict" | jq -r '.claimed.authors[0] // ""')
    claimed_year=$(printf '%s' "$verdict" | jq -r '.claimed.year // ""')

    icon=$(severity_icon "$status")
    short=$(sanitize "$claimed_authors $claimed_year $claimed_title" | cut -c1-100)
    printf '%s **[%s]** %s -- %s\n' "$icon" "$status" "$idx" "$short"

    # Render diagnosis sub-bullets when present (Task 15).
    diag_reason=$(printf '%s' "$verdict" | jq -r '.diagnosis.reason // ""')
    diag_context=$(printf '%s' "$verdict" | jq -r '.diagnosis.context // ""')
    if [ -n "$diag_reason" ]; then
        # diag_reason is a trusted enum code; diag_context is external and must be sanitized.
        printf '  - **diagnosis.reason:** `%s`\n' "$diag_reason"
        printf '  - **diagnosis.context:** %s\n' "$(sanitize "$diag_context")"
    fi

    # Render advisory sub-bullets when present (Task 15).
    adv_type=$(printf '%s' "$verdict" | jq -r '.advisory.type // ""')
    if [ -n "$adv_type" ]; then
        case "$adv_type" in
            book_candidate)
                adv_doi=$(printf '%s' "$verdict" | jq -r '.advisory.doi')
                adv_title=$(printf '%s' "$verdict" | jq -r '.advisory.title')
                printf '  - **advisory:** matched a book-chapter. Candidate book record: `%s` - %s\n' \
                    "$(sanitize "$adv_doi")" "$(sanitize "$adv_title")"
                ;;
            token_containment)
                adv_f1=$(printf '%s' "$verdict" | jq -r '.advisory.f1')
                adv_overlap=$(printf '%s' "$verdict" | jq -r '.advisory.overlap_pct')
                adv_doi=$(printf '%s' "$verdict" | jq -r '.advisory.candidate_doi')
                printf '  - **advisory:** high token-containment overlap with candidate `%s` (F1=%s, overlap=%s)\n' \
                    "$(sanitize "$adv_doi")" "$adv_f1" "$adv_overlap"
                ;;
        esac
    fi
done < "$VERDICTS_FILE"

# Footer with feedback link.
cat <<'FOOTER'

---

**Caught a hallucination? False positive? Missed something?**
Share it at https://github.com/jonckr/cite-verify/issues to help others catch the same pattern.
FOOTER
