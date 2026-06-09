#!/usr/bin/env bash
# lint.sh — main entry point for cite-verify
#
# Usage:
#   lint.sh                          — read citations from stdin
#   lint.sh -                        — same, explicit
#   lint.sh <file>                   — read citations from a file
#
# Accepts plain text, Markdown, BibTeX, or any file where citations appear
# one per line or separated by blank lines. For .docx files on macOS, the
# caller should first run `textutil -convert txt -- <file>` and pipe the
# result in.
#
# Output: human-readable Markdown report to stdout. Exit code 0 if all
# citations verified cleanly, 1 if any citation flagged as MISMATCH or
# METADATA_MISMATCH, 2 on internal error.
#
# Security: reads input as opaque bytes, 1 MB max per invocation,
# 60 citations max, allowlisted API endpoints only, log file symlink
# check before append, temp files 0600 with trap cleanup.

set -euo pipefail

# --advisory-probe: read stub JSON on stdin, emit the advisory that would be
# injected, or {} if no advisory fires. Used by unit tests for Task 12.
# Per CCG-on-plan B1, enforces ALL THREE predicates:
#   (1) top_hit.type is "book-chapter"
#   (2) sibling first_author matches citation.first_author
#   (3) sibling f1_against_citation > 0.85
if [ "${1:-}" = "--advisory-probe" ]; then
    STUB=$(cat)
    CITATION=$(printf '%s' "$STUB" | jq -c '.citation')
    CAND=$(printf '%s' "$STUB" | jq -c \
      --argjson citation "$CITATION" '
      if .top_hit.type == "book-chapter" then
        [ .siblings[]
          | select(.type == "monograph" or .type == "book")
          | select(.first_author == $citation.first_author)
          | select((.f1_against_citation // 0) > 0.85)
        ][0] // empty
      else empty end
    ' 2>/dev/null || true)
    if [ -n "$CAND" ]; then
        DOI=$(printf '%s' "$CAND" | jq -r '.doi')
        TITLE=$(printf '%s' "$CAND" | jq -r '.title')
        jq -n --arg doi "$DOI" --arg title "$TITLE" \
          '{type:"book_candidate", doi:$doi, title:$title}'
        exit 0
    fi
    printf '{}\n'
    exit 0
fi

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MATCHER="$SKILL_DIR/scripts/title_match.sh"
LOOKUP="$SKILL_DIR/scripts/crossref_lookup.sh"
PARSER="$SKILL_DIR/scripts/parse_citation.sh"
REPORT="$SKILL_DIR/scripts/report.sh"

# Log file setup with read-only directory fallback (Tier-C, D7).
LOG_FILE="$SKILL_DIR/logs/verifications.jsonl"
LOG_DIR="$(dirname "$LOG_FILE")"

if [ ! -d "$LOG_DIR" ] || ! { : > "$LOG_DIR/.writable_probe" 2>/dev/null; }; then
    FALLBACK="${TMPDIR:-/tmp}/cite-verify-verifications-${USER:-anon}.jsonl"
    echo "warning: log fallback - $LOG_DIR unwritable; using $FALLBACK" >&2
    LOG_FILE="$FALLBACK"
else
    rm -f "$LOG_DIR/.writable_probe"
fi

MAX_INPUT_BYTES=1048576   # 1 MB
MAX_CITATIONS=60

TMPDIR_LOCAL=$(mktemp -d -t citeverify-lint)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT INT TERM

# --emit-verdicts <path>: copy the final verdicts.jsonl to that path after the run.
EMIT_VERDICTS=""
if [ "${1:-}" = "--emit-verdicts" ]; then
    EMIT_VERDICTS="$2"
    # Refuse symlink at the destination to prevent redirect attacks (per /cso Note #4).
    if [ -L "$EMIT_VERDICTS" ]; then
        echo "error: --emit-verdicts target is a symlink: $EMIT_VERDICTS" >&2
        exit 2
    fi
    shift 2
fi

# Read input. Accept file path as first arg, or stdin if arg is "-" or absent.
INPUT_FILE=""
if [ "$#" -ge 1 ] && [ "$1" != "-" ]; then
    INPUT_FILE="$1"
    if [ ! -f "$INPUT_FILE" ]; then
        echo "error: file not found: $INPUT_FILE" >&2
        exit 2
    fi
    # Use -- before the path to prevent option injection if path starts with -.
    cp -- "$INPUT_FILE" "$TMPDIR_LOCAL/input.raw"
else
    cat > "$TMPDIR_LOCAL/input.raw"
fi

# Detect .bib input type for python3 gate.
INPUT_TYPE="text"
if [ -n "$INPUT_FILE" ]; then
    case "$INPUT_FILE" in
        *.bib|*.BIB) INPUT_TYPE="bib" ;;
    esac
fi

# Python availability gate: .bib input requires python3.
# Emit a single NEEDS_MANUAL verdict and skip to report if python3 is absent.
# Use `python3 --version` rather than `command -v` so a stub that exits nonzero
# is treated as unavailable (allows tests to shadow with a broken stub).
if [ "$INPUT_TYPE" = "bib" ] && ! python3 --version >/dev/null 2>&1; then
    mkdir -p "$TMPDIR_LOCAL"
    : > "$TMPDIR_LOCAL/verdicts.jsonl"
    jq -nc \
        --arg status "NEEDS_MANUAL_VERIFICATION" \
        --arg lookup_mode "none" \
        --arg reason "python3_unavailable" \
        --arg context "python3 not found on PATH; install Python 3.9+ or convert .bib to plain text" \
        '{
            index: 1,
            status: $status,
            lookup_mode: $lookup_mode,
            claimed: {raw: "(.bib input)", title: null, authors: [], year: null, doi: null},
            lookup: {ok: false, error: "python3 unavailable", records: []},
            match: {verdict: "NEEDS_MANUAL_VERIFICATION", f1: 0},
            diagnosis: {reason: $reason, context: $context}
        }' >> "$TMPDIR_LOCAL/verdicts.jsonl"
    "$REPORT" "$TMPDIR_LOCAL/verdicts.jsonl"
    exit 0
fi

# Size bound check.
input_size=$(wc -c < "$TMPDIR_LOCAL/input.raw" | tr -d ' ')
if [ "$input_size" -gt "$MAX_INPUT_BYTES" ]; then
    echo "error: input exceeds ${MAX_INPUT_BYTES} byte limit ($input_size bytes)" >&2
    exit 2
fi

# Strip null bytes for safety.
tr -d '\000' < "$TMPDIR_LOCAL/input.raw" > "$TMPDIR_LOCAL/input.clean"

: > "$TMPDIR_LOCAL/records.jsonl"

# Vendor integrity gate: for .bib input, verify vendor checksums before
# dispatching to parse_bibtex.py. Fail closed with NEEDS_MANUAL if tampered.
if [ "$INPUT_TYPE" = "bib" ]; then
    if ! "$SKILL_DIR/scripts/verify_deps.sh" >/dev/null 2>&1; then
        echo "error: vendor integrity check failed; run scripts/install_deps.sh to reinstall" >&2
        diagnosis_reason="deps_integrity_fail"
        diagnosis_context="vendor integrity check failed; re-run scripts/install_deps.sh"
        jq -nc \
            --arg status "NEEDS_MANUAL_VERIFICATION" \
            --arg lookup_mode "none" \
            --arg reason "$diagnosis_reason" \
            --arg context "$diagnosis_context" \
            '{
                index: 1,
                status: $status,
                lookup_mode: $lookup_mode,
                claimed: {raw: "(.bib input)", title: null, authors: [], year: null, doi: null},
                lookup: {ok: false, error: "deps_integrity_fail", records: []},
                match: {verdict: "NEEDS_MANUAL_VERIFICATION", f1: 0},
                diagnosis: {reason: $reason, context: $context}
            }' >> "$TMPDIR_LOCAL/verdicts.jsonl"
        "$REPORT" "$TMPDIR_LOCAL/verdicts.jsonl"
        exit 1
    fi
fi

if [ "$INPUT_TYPE" = "bib" ]; then
    # BibTeX path: call parse_bibtex.py on the whole file, get a JSON array,
    # then write one record per line (jsonl) for the shared lookup loop.
    # entry_key is included by parse_bibtex.py from the bibtexparser ID field.
    # parse_bibtex.py self-roots vendor/ via sys.path; PYTHONPATH= is unnecessary
    # under `python3 -I` (which would ignore it anyway).
    RAW_BIBTEX_JSON=$(python3 -I \
        "$SKILL_DIR/scripts/parse_bibtex.py" "$TMPDIR_LOCAL/input.clean" 2>/dev/null \
        || echo '[]')
    count=$(printf '%s' "$RAW_BIBTEX_JSON" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo "error: no citations found in input" >&2
        exit 2
    fi
    if [ "$count" -gt "$MAX_CITATIONS" ]; then
        echo "warning: input has more than $MAX_CITATIONS citations, using first $MAX_CITATIONS" >&2
    fi
    # Write one record per line, capped at MAX_CITATIONS. Augment each record with
    # a .raw field (synthetic, for logging) since parse_bibtex.py does not emit one.
    printf '%s' "$RAW_BIBTEX_JSON" | jq -c \
        --argjson cap "$MAX_CITATIONS" \
        '.[:$cap][] | . + {raw: ("@" + (.type // "misc") + "{" + (.entry_key // "") + "}")}' \
        >> "$TMPDIR_LOCAL/records.jsonl"
else
    # Plain-text path: awk paragraph mode splits on blank lines; we collapse each
    # paragraph to a single line. Downstream reads one citation per line.
    awk '
BEGIN { RS="" }
{
    gsub(/[[:space:]]+/, " ");
    gsub(/^[[:space:]]+|[[:space:]]+$/, "");
    if (length($0) >= 10) print $0;
}
' "$TMPDIR_LOCAL/input.clean" > "$TMPDIR_LOCAL/citations.lines"

    count=0
    while IFS= read -r content || [ -n "$content" ]; do
        [ -z "$content" ] && continue
        [ ${#content} -lt 10 ] && continue
        count=$((count + 1))
        if [ "$count" -gt "$MAX_CITATIONS" ]; then
            echo "warning: input has more than $MAX_CITATIONS citations, stopping" >&2
            break
        fi
        "$PARSER" "$content" >> "$TMPDIR_LOCAL/records.jsonl"
    done < "$TMPDIR_LOCAL/citations.lines"

    if [ "$count" -eq 0 ]; then
        echo "error: no citations found in input" >&2
        exit 2
    fi
fi

# For each parsed citation, look up Crossref and match title.
: > "$TMPDIR_LOCAL/verdicts.jsonl"
idx=0
while IFS= read -r record; do
    idx=$((idx + 1))
    # Extract fields.
    title=$(printf '%s' "$record" | jq -r '.title // ""')
    doi=$(printf '%s' "$record" | jq -r '.doi // ""')
    nber=$(printf '%s' "$record" | jq -r '.nber_number // ""')
    arxiv=$(printf '%s' "$record" | jq -r '.arxiv_id // ""')
    year=$(printf '%s' "$record" | jq -r '.year // ""')
    first_author=$(printf '%s' "$record" | jq -r '.authors[0] // ""')
    raw=$(printf '%s' "$record" | jq -r '.raw // ""')

    # Diagnosis fields - set when status will be NEEDS_MANUAL_VERIFICATION.
    diagnosis_reason=""
    diagnosis_context=""

    # Determine query path priority: DOI > NBER > arXiv > title search.
    lookup_result='{"ok":false,"error":"no lookup attempted","records":[]}'
    lookup_mode="none"
    if [ -n "$doi" ]; then
        lookup_mode="doi"
        lookup_result=$("$LOOKUP" doi "$doi" 2>/dev/null || echo '{"ok":false,"error":"network_error","records":[]}')
    elif [ -n "$nber" ]; then
        lookup_mode="nber"
        lookup_result=$("$LOOKUP" nber "$nber" 2>/dev/null || echo '{"ok":false,"error":"network_error","records":[]}')
    elif [ -n "$title" ] && [ ${#title} -ge 10 ]; then
        lookup_mode="search"
        lookup_result=$("$LOOKUP" search "$title" "$first_author" 2>/dev/null || echo '{"ok":false,"error":"network_error","records":[]}')
    else
        lookup_mode="insufficient_data"
    fi

    # Inspect lookup failure to set diagnosis codes.
    # crossref_lookup.sh emits {ok:false, error:"<msg>", code:"<code>", records:[]}.
    # When curl itself fails (network_error stub), the fallback JSON has error:"network_error".
    # When crossref_lookup.sh catches an HTTP error, code="http_error" and error="Crossref returned HTTP NNN".
    if [ "$(printf '%s' "$lookup_result" | jq -r '.ok // false')" = "false" ]; then
        lookup_err=$(printf '%s' "$lookup_result" | jq -r '.error // ""')
        lookup_code=$(printf '%s' "$lookup_result" | jq -r '.code // ""')
        if [ "$lookup_err" = "network_error" ]; then
            diagnosis_reason="network_unavailable"
            diagnosis_context="network unreachable; check connectivity"
        elif [ "$lookup_code" = "http_error" ]; then
            # Extract the HTTP status code from the error message.
            http_sc=$(printf '%s' "$lookup_err" | grep -oE '[0-9]{3}' | head -1 || echo "")
            if [ "$http_sc" = "429" ]; then
                diagnosis_reason="crossref_rate_limited"
                diagnosis_context="Crossref returned 429 after 3 retries"
            elif printf '%s' "$http_sc" | grep -qE '^5'; then
                diagnosis_reason="backend_server_error"
                diagnosis_context="Crossref returned HTTP ${http_sc}; try again later"
            elif printf '%s' "$http_sc" | grep -qE '^4'; then
                diagnosis_reason="backend_server_error"
                diagnosis_context="Crossref returned HTTP ${http_sc}"
            else
                diagnosis_reason="network_unavailable"
                diagnosis_context="network unreachable; check connectivity"
            fi
        fi
        # lookup_mode=insufficient_data and ok=false is not an HTTP error; no diagnosis set.
    fi

    # If the lookup succeeded, match the claimed title against the top result.
    match_verdict="NEEDS_MANUAL_VERIFICATION"
    match_result='{"verdict":"NEEDS_MANUAL_VERIFICATION","f1":0}'
    ok=$(printf '%s' "$lookup_result" | jq -r '.ok // false')
    if [ "$ok" = "true" ]; then
        hit_count=$(printf '%s' "$lookup_result" | jq '.records | length')
        if [ "$hit_count" -gt 0 ]; then
            canonical_title=$(printf '%s' "$lookup_result" | jq -r '.records[0].title // ""')
            if [ -n "$canonical_title" ] && [ -n "$title" ]; then
                match_result=$("$MATCHER" "$title" "$canonical_title" 2>/dev/null || echo '{"verdict":"ERROR","f1":0}')
                match_verdict=$(printf '%s' "$match_result" | jq -r '.verdict // "ERROR"')
            fi
        fi
    fi

    # Map internal match verdict to user-facing status.
    case "$match_verdict" in
        EXACT|STRONG_MATCH|MATCH)
            status="VERIFIED" ;;
        WEAK_MATCH)
            status="PARTIAL_MATCH" ;;
        MISMATCH)
            if [ "$lookup_mode" = "doi" ] || [ "$lookup_mode" = "nber" ]; then
                status="METADATA_MISMATCH"
            else
                status="NOT_FOUND"
            fi
            ;;
        INSUFFICIENT)
            status="NEEDS_MANUAL_VERIFICATION"
            diagnosis_reason="insufficient_title_tokens"
            diagnosis_context="title has fewer than 3 meaningful tokens after stopword removal; cannot reliably F1-match"
            ;;
        *)
            if [ "$ok" = "true" ]; then
                # ok=true but hit_count=0 (Crossref returned empty records): genuinely not found.
                status="NOT_FOUND"
            else
                # ok=false: network/backend error prevented lookup; do not declare not-found.
                status="NEEDS_MANUAL_VERIFICATION"
            fi
            ;;
    esac

    # Build the verdict record. -c for compact single-line output so the
    # downstream logging loop can read one verdict per line.
    # entry_key is present when input was a .bib file (threaded from bibtexparser ID).
    # Diagnosis is injected only when status=NEEDS_MANUAL_VERIFICATION and
    # diagnosis_reason is non-empty (plan D1 shape).
    entry_key=$(printf '%s' "$record" | jq -r '.entry_key // ""')
    matched_doi=$(printf '%s' "$lookup_result" | jq -r '.records[0].DOI // ""' 2>/dev/null || true)
    jq -nc \
        --argjson idx "$idx" \
        --arg status "$status" \
        --arg lookup_mode "$lookup_mode" \
        --arg entry_key "$entry_key" \
        --arg matched_doi "$matched_doi" \
        --argjson record "$record" \
        --argjson lookup "$lookup_result" \
        --argjson match "$match_result" \
        --arg diagnosis_reason "${diagnosis_reason:-}" \
        --arg diagnosis_context "${diagnosis_context:-}" \
        '({
            index: $idx,
            status: $status,
            lookup_mode: $lookup_mode,
            claimed: $record,
            lookup: $lookup,
            match: $match,
            matched: {doi: (if $matched_doi != "" then $matched_doi else null end)}
        })
        | if $entry_key != "" then . + {entry_key: $entry_key} else . end
        | if $diagnosis_reason != "" then
            . + {diagnosis: {reason: $diagnosis_reason, context: $diagnosis_context}}
          else . end' >> "$TMPDIR_LOCAL/verdicts.jsonl"

    # Advisory injection for PARTIAL_MATCH records (non-promoting per CCG A2).
    # Book advisory fires when Crossref top hit is a book-chapter and a sibling
    # monograph/book record exists. If no book advisory fires, check containment.
    if [ "$status" = "PARTIAL_MATCH" ]; then
        ADVISORY=""

        # Book-vs-chapter advisory: check Crossref response structure.
        # Enforces the same 3 predicates as --advisory-probe:
        #   (1) top hit type is "book-chapter"
        #   (2) sibling first author family name matches citation first author
        #   (3) sibling title has F1 > 0.85 against the cited title
        TOP_TYPE=$(printf '%s' "$lookup_result" | jq -r '.records[0].type // ""' 2>/dev/null || true)
        if [ "$TOP_TYPE" = "book-chapter" ]; then
            # citation first_author is already extracted above (family name from parse_citation).
            CAND_COUNT=$(printf '%s' "$lookup_result" | jq '[.records[] | select(.type == "monograph" or .type == "book")] | length' 2>/dev/null || echo 0)
            i=0
            while [ "$i" -lt "$CAND_COUNT" ]; do
                CAND_FAMILY=$(printf '%s' "$lookup_result" | jq -r --argjson i "$i" \
                  '[.records[] | select(.type == "monograph" or .type == "book")][$i].authors[0].family // ""' 2>/dev/null || true)
                # Author check: citation first_author must match candidate first author family name.
                # `grep -F` (fixed-string) prevents regex-injection if Crossref returns a family name
                # containing regex metacharacters (`.`, `*`, `[`, etc.), per /security-review.
                if [ -n "$CAND_FAMILY" ] && [ -n "$first_author" ] && \
                   printf '%s' "$CAND_FAMILY" | grep -qiF "$(printf '%s' "$first_author" | cut -d' ' -f1)"; then
                    CAND_TITLE=$(printf '%s' "$lookup_result" | jq -r --argjson i "$i" \
                      '[.records[] | select(.type == "monograph" or .type == "book")][$i].title // ""' 2>/dev/null || true)
                    CAND_DOI_B=$(printf '%s' "$lookup_result" | jq -r --argjson i "$i" \
                      '[.records[] | select(.type == "monograph" or .type == "book")][$i].DOI // ""' 2>/dev/null || true)
                    if [ -n "$CAND_TITLE" ] && [ -n "$title" ]; then
                        BOOK_MATCH=$("$MATCHER" "$title" "$CAND_TITLE" 2>/dev/null || echo '{"verdict":"ERROR","f1":0}')
                        BOOK_F1=$(printf '%s' "$BOOK_MATCH" | jq -r '.f1 // 0')
                        if awk -v f="$BOOK_F1" 'BEGIN{exit !(f > 0.85)}'; then
                            ADVISORY=$(jq -n --arg doi "$CAND_DOI_B" --arg cand_title "$CAND_TITLE" \
                              '{type:"book_candidate", doi:$doi, title:$cand_title}')
                            break
                        fi
                    fi
                fi
                i=$((i + 1))
            done
        fi

        # Containment advisory (only if book advisory did not fire).
        if [ -z "$ADVISORY" ]; then
            CONT_F1=$(printf '%s' "$match_result" | jq -r '.f1 // 0')
            CONT_OVERLAP=$(printf '%s' "$match_result" | jq -r '.token_containment_pct // 0')
            if awk -v f="$CONT_F1" 'BEGIN{exit !(f >= 0.60 && f < 0.85)}' && \
               awk -v o="$CONT_OVERLAP" 'BEGIN{exit !(o >= 0.90)}'; then
                CAND_DOI=$(printf '%s' "$lookup_result" | jq -r '.records[0].DOI // .records[0].doi // ""' 2>/dev/null || true)
                ADVISORY=$(jq -n \
                  --argjson f "$CONT_F1" \
                  --argjson o "$CONT_OVERLAP" \
                  --arg doi "$CAND_DOI" \
                  '{type:"token_containment", f1:$f, overlap_pct:$o, candidate_doi:$doi}')
            fi
        fi

        # Merge advisory into the last verdicts.jsonl record if one fired.
        # Use `sed '$d'` (portable BSD/GNU) not `head -n -1` (GNU-only, per CCG A3).
        if [ -n "$ADVISORY" ]; then
            LAST=$(tail -1 "$TMPDIR_LOCAL/verdicts.jsonl")
            MERGED=$(printf '%s' "$LAST" | jq -c --argjson adv "$ADVISORY" '. + {advisory:$adv}')
            sed '$d' "$TMPDIR_LOCAL/verdicts.jsonl" > "$TMPDIR_LOCAL/verdicts.jsonl.tmp"
            printf '%s\n' "$MERGED" >> "$TMPDIR_LOCAL/verdicts.jsonl.tmp"
            mv "$TMPDIR_LOCAL/verdicts.jsonl.tmp" "$TMPDIR_LOCAL/verdicts.jsonl"
        fi
    fi
done < "$TMPDIR_LOCAL/records.jsonl"

# Append to local log (after symlink check).
if [ -L "$LOG_FILE" ]; then
    echo "warning: log file is a symlink, refusing to write: $LOG_FILE" >&2
elif [ -e "$LOG_FILE" ] || touch "$LOG_FILE" 2>/dev/null; then
    chmod 600 "$LOG_FILE" 2>/dev/null || true
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    while IFS= read -r verdict; do
        claimed_hash=$(printf '%s' "$verdict" | jq -r '.claimed.raw // ""' | shasum -a 256 | awk '{print $1}')
        jq -n \
            --arg ts "$timestamp" \
            --arg hash "$claimed_hash" \
            --arg status "$(printf '%s' "$verdict" | jq -r '.status')" \
            --arg mode "$(printf '%s' "$verdict" | jq -r '.lookup_mode')" \
            '{timestamp:$ts, citation_hash:("sha256:"+$hash), status:$status, lookup_mode:$mode}' >> "$LOG_FILE"
    done < "$TMPDIR_LOCAL/verdicts.jsonl"
fi

# Render the markdown report.
"$REPORT" "$TMPDIR_LOCAL/verdicts.jsonl"

# Copy verdicts to caller-specified path when --emit-verdicts was given.
if [ -n "$EMIT_VERDICTS" ]; then
    cp "$TMPDIR_LOCAL/verdicts.jsonl" "$EMIT_VERDICTS"
fi

# Exit code: 1 if any citation is METADATA_MISMATCH or NOT_FOUND, 0 otherwise.
if grep -q -E '"status":"(METADATA_MISMATCH|NOT_FOUND)"' "$TMPDIR_LOCAL/verdicts.jsonl"; then
    exit 1
fi
exit 0
