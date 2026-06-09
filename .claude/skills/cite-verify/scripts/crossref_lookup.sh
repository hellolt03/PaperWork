#!/usr/bin/env bash
# crossref_lookup.sh — secure Crossref API client for cite-verify
#
# Usage:
#   crossref_lookup.sh doi <doi>                      — direct DOI lookup
#   crossref_lookup.sh nber <number>                  — NBER WP, e.g. "33344" or "w33344"
#   crossref_lookup.sh search "<title>" "<author>"    — bibliographic search
#
# Output: single-line JSON. On success: {ok:true, source, records:[...]}.
# On failure: {ok:false, error:"...", code:"..."}.
#
# Security posture (responds to codex's findings):
# - Hardcoded allowlist: only api.crossref.org.
# - HTTPS enforced via --proto =https.
# - DOI format validated with regex BEFORE URL construction.
# - DOI suffix URL-encoded via jq -Rr @uri (not shell interpolation).
# - No --noproxy (respect enterprise proxy settings).
# - No -L (no redirect following).
# - --max-filesize caps response at 2 MB (prevents JSON bomb DoS).
# - 10-second timeout per request.
# - User-Agent includes mailto for Crossref polite pool.
# - All JSON output built via jq -n --arg; nothing is string-interpolated
#   into shell commands or JSON blobs.

set -euo pipefail

CROSSREF_BASE="https://api.crossref.org"
USER_AGENT="cite-verify/0.2 (+https://github.com/jonckr/cite-verify; mailto:cite-verify@jonckr.dev)"
TIMEOUT_SECONDS=10
MAX_RESPONSE_BYTES=2000000

# Error emitter — always returns valid JSON via jq.
emit_error() {
    local code="$1"
    local message="$2"
    jq -n \
        --arg code "$code" \
        --arg msg  "$message" \
        '{ok:false, error:$msg, code:$code, records:[]}'
    exit 1
}

# Validate a DOI string against the Crossref-acceptable pattern.
# Rejects anything containing shell metacharacters, path traversal, or
# query-string injection fragments before the string is ever used.
# Valid DOIs start with "10." followed by a numeric registrant, a slash,
# and a suffix using letters, digits, and limited punctuation.
validate_doi() {
    local doi="$1"
    # Length bound to prevent pathological input.
    if [ ${#doi} -gt 500 ]; then
        return 1
    fi
    # Regex: 10.<digits>/<safe-chars>
    # Allowed suffix chars: letters, digits, hyphens, dots, underscores,
    # parentheses, colons, semicolons, forward slashes. NO spaces, NO ?,
    # NO #, NO &, NO <, NO >, NO quotes, NO dollar signs, NO backticks.
    if printf '%s' "$doi" | grep -Eq '^10\.[0-9]+/[A-Za-z0-9._:;()/-]+$'; then
        # Reject any occurrence of ".." to prevent path traversal.
        if printf '%s' "$doi" | grep -qF '..'; then
            return 1
        fi
        return 0
    fi
    return 1
}

# URL-encode a string using jq's @uri filter (which does RFC 3986
# percent-encoding). We pass the input via --arg so it's treated as
# literal data, not as a jq expression.
url_encode() {
    local input="$1"
    printf '%s' "$input" | jq -Rr @uri
}

# Run curl with the full hardened flag set. Never string-interpolate user
# input into the command. Pass URL via --url and query params via
# --data-urlencode. Extract the body and HTTP status code.
safe_get() {
    local url="$1"
    local tmp_body
    tmp_body=$(mktemp -t crossref-body)
    local http_code
    http_code=$(curl \
        --silent \
        --proto '=https' \
        --tlsv1.2 \
        --max-filesize "$MAX_RESPONSE_BYTES" \
        --max-time "$TIMEOUT_SECONDS" \
        --user-agent "$USER_AGENT" \
        --output "$tmp_body" \
        --write-out '%{http_code}' \
        --url "$url" \
        2>/dev/null) || http_code="000"

    if [ "$http_code" != "200" ]; then
        rm -f "$tmp_body"
        emit_error "http_error" "Crossref returned HTTP $http_code"
    fi

    cat "$tmp_body"
    rm -f "$tmp_body"
}

# Same as safe_get but with additional query parameters passed via
# --data-urlencode (which correctly URL-encodes the values).
safe_get_with_params() {
    local base_url="$1"
    shift
    local tmp_body
    tmp_body=$(mktemp -t crossref-body)
    local curl_args
    curl_args=(
        --silent
        --get
        --proto '=https'
        --tlsv1.2
        --max-filesize "$MAX_RESPONSE_BYTES"
        --max-time "$TIMEOUT_SECONDS"
        --user-agent "$USER_AGENT"
        --output "$tmp_body"
        --write-out '%{http_code}'
        --url "$base_url"
    )
    # Remaining arguments are key=value pairs, each passed via
    # --data-urlencode so curl does the percent-encoding safely.
    while [ $# -gt 0 ]; do
        curl_args+=(--data-urlencode "$1")
        shift
    done
    local http_code
    http_code=$(curl "${curl_args[@]}" 2>/dev/null) || http_code="000"
    if [ "$http_code" != "200" ]; then
        rm -f "$tmp_body"
        emit_error "http_error" "Crossref returned HTTP $http_code"
    fi
    cat "$tmp_body"
    rm -f "$tmp_body"
}

# The canonical shape of a single Crossref "work" record that cite-verify
# consumes. Kept as a variable so the filter lives in one place and can
# be spliced into jq pipelines.
SHAPE_FILTER='{
    title: (.title // [""] | .[0] // ""),
    subtitle: (.subtitle // [] | .[0] // ""),
    authors: [(.author // [])[] | {
        family: (.family // ""),
        given:  (.given // "")
    }],
    year: (
        (.issued // .created // .published // {}) |
        ."date-parts" // [[]] |
        .[0] // [] |
        .[0]
    ),
    DOI: (.DOI // ""),
    type: (.type // ""),
    publisher: (.publisher // ""),
    container: (."container-title" // [""] | .[0] // ""),
    URL: (.URL // "")
}'

# MODE: doi <doi>
cmd_doi() {
    local doi="$1"
    if ! validate_doi "$doi"; then
        emit_error "invalid_doi" "DOI does not match expected format: $doi"
    fi
    # URL-encode the DOI suffix to be safe inside the path.
    local encoded
    encoded=$(url_encode "$doi")
    local url="${CROSSREF_BASE}/works/${encoded}"

    local body
    body=$(safe_get "$url")

    # Crossref returns {status:"ok", message:{...work...}}
    local record
    record=$(printf '%s' "$body" | jq --compact-output ".message | ${SHAPE_FILTER}")
    jq -n \
        --arg src "crossref_doi" \
        --argjson rec "$record" \
        '{ok:true, source:$src, records:[$rec]}'
}

# MODE: nber <number>
# Accepts "33344" or "w33344" or "W33344" and resolves to DOI 10.3386/wNNNNN.
cmd_nber() {
    local raw="$1"
    # Strip leading "w" or "W" if present.
    local number="${raw#[wW]}"
    # Must be all digits.
    if ! printf '%s' "$number" | grep -Eq '^[0-9]{1,7}$'; then
        emit_error "invalid_nber" "NBER working paper number must be 1-7 digits, got: $raw"
    fi
    local doi="10.3386/w${number}"
    cmd_doi "$doi"
}

# MODE: search <title> <author>
cmd_search() {
    local title="$1"
    local author="${2:-}"
    if [ -z "$title" ]; then
        emit_error "missing_title" "search requires a non-empty title"
    fi
    local url="${CROSSREF_BASE}/works"
    local body
    if [ -n "$author" ]; then
        body=$(safe_get_with_params "$url" \
            "query.bibliographic=$title" \
            "query.author=$author" \
            "rows=5")
    else
        body=$(safe_get_with_params "$url" \
            "query.bibliographic=$title" \
            "rows=5")
    fi
    # Crossref returns {status:"ok", message:{items:[{...work...}, ...]}}
    local records
    records=$(printf '%s' "$body" | jq --compact-output "[.message.items[]? | ${SHAPE_FILTER}]")
    jq -n \
        --arg src "crossref_search" \
        --argjson recs "$records" \
        '{ok:true, source:$src, records:$recs}'
}

# Main dispatch
if [ "$#" -lt 1 ]; then
    emit_error "usage" "usage: crossref_lookup.sh {doi|nber|search} [args]"
fi

mode="$1"
shift

case "$mode" in
    doi)
        [ "$#" -lt 1 ] && emit_error "usage" "crossref_lookup.sh doi <doi>"
        cmd_doi "$1"
        ;;
    nber)
        [ "$#" -lt 1 ] && emit_error "usage" "crossref_lookup.sh nber <number>"
        cmd_nber "$1"
        ;;
    search)
        [ "$#" -lt 1 ] && emit_error "usage" "crossref_lookup.sh search <title> [author]"
        cmd_search "$1" "${2:-}"
        ;;
    *)
        emit_error "unknown_mode" "unknown mode: $mode (expected doi, nber, or search)"
        ;;
esac
