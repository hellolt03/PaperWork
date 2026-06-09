#!/usr/bin/env bash
# smoke.sh — end-to-end smoke tests for cite-verify
#
# Usage:
#   ./tests/smoke.sh           — run with cached Crossref responses (offline, fast)
#   ./tests/smoke.sh --live    — run against the live Crossref API (requires network, ~35s)
#
# Each example file in examples/ is piped through the full lint.sh pipeline.
# The test asserts the expected verdict for each citation.

set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$SKILL_DIR/scripts/lint.sh"
FIXTURES="$SKILL_DIR/tests/fixtures"
EXAMPLES="$SKILL_DIR/examples"

LIVE=0
if [ "${1:-}" = "--live" ]; then
    LIVE=1
fi

PASS=0
FAIL=0
FAILED_TESTS=""

# In cached mode, we replace crossref_lookup.sh with a shim that serves
# fixture files. The shim is written to a temp directory and the LINT
# script is patched to use it via an env var override.
TMPDIR_SMOKE=$(mktemp -d -t citeverify-smoke)
trap 'rm -rf "$TMPDIR_SMOKE"' EXIT INT TERM

if [ "$LIVE" -eq 0 ]; then
    # Create the lookup shim.
    cat > "$TMPDIR_SMOKE/crossref_lookup.sh" <<'SHIM'
#!/usr/bin/env bash
# Cached lookup shim for smoke tests.
# Reads CITE_VERIFY_FIXTURE_DIR to find pre-recorded API responses.
set -euo pipefail

FIXTURE_DIR="${CITE_VERIFY_FIXTURE_DIR:?}"
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

mode="$1"
shift

case "$mode" in
    doi)
        doi="$1"
        # Map NBER DOIs to the lmr fixture.
        if printf '%s' "$doi" | grep -q '10.3386/w33344'; then
            fixture="$FIXTURE_DIR/lmr-nber-doi.json"
        else
            # Generic DOI — try to find a fixture by DOI hash.
            fixture="$FIXTURE_DIR/doi-$(printf '%s' "$doi" | shasum -a 256 | cut -c1-16).json"
        fi
        if [ ! -f "$fixture" ]; then
            jq -n '{ok:false, error:"no cached fixture for this DOI", code:"no_fixture", records:[]}'
            exit 1
        fi
        record=$(jq --compact-output ".message | ${SHAPE_FILTER}" "$fixture")
        jq -n --arg src "crossref_doi" --argjson rec "$record" '{ok:true, source:$src, records:[$rec]}'
        ;;
    nber)
        raw="$1"
        number="${raw#[wW]}"
        fixture="$FIXTURE_DIR/lmr-nber-doi.json"
        if [ ! -f "$fixture" ]; then
            jq -n '{ok:false, error:"no cached fixture", code:"no_fixture", records:[]}'
            exit 1
        fi
        record=$(jq --compact-output ".message | ${SHAPE_FILTER}" "$fixture")
        jq -n --arg src "crossref_doi" --argjson rec "$record" '{ok:true, source:$src, records:[$rec]}'
        ;;
    search)
        title="$1"
        author="${2:-}"
        # Match fixture by keyword in the title.
        if printf '%s' "$title" | grep -qi 'attention'; then
            fixture="$FIXTURE_DIR/attention-paper-search.json"
        elif printf '%s' "$title" | grep -qi 'colonial'; then
            fixture="$FIXTURE_DIR/acemoglu-search.json"
        elif printf '%s' "$title" | grep -qi 'unobservable\|coefficient'; then
            fixture="$FIXTURE_DIR/oster-search.json"
        elif printf '%s' "$title" | grep -qi 'synthetic.*predictive\|distributed.*networks'; then
            fixture="$FIXTURE_DIR/fabricated-search.json"
        else
            jq -n '{ok:false, error:"no cached fixture for this search", code:"no_fixture", records:[]}'
            exit 1
        fi
        if [ ! -f "$fixture" ]; then
            jq -n '{ok:false, error:"fixture file missing", code:"no_fixture", records:[]}'
            exit 1
        fi
        records=$(jq --compact-output "[.message.items[]? | ${SHAPE_FILTER}]" "$fixture")
        jq -n --arg src "crossref_search" --argjson recs "$records" '{ok:true, source:$src, records:$recs}'
        ;;
    *)
        jq -n --arg m "$mode" '{ok:false, error:("unknown mode: " + $m), code:"unknown_mode", records:[]}'
        exit 1
        ;;
esac
SHIM
    chmod +x "$TMPDIR_SMOKE/crossref_lookup.sh"
fi

# Run lint.sh on an example file and check the verdict.
# Usage: run_example "test name" "example file" "expected status regex"
run_example() {
    local name="$1"
    local example_file="$2"
    local want_pattern="$3"

    local output exit_code
    if [ "$LIVE" -eq 0 ]; then
        # In cached mode, we need to make lint.sh use our shim.
        # We do this by temporarily replacing the lookup script.
        local real_lookup="$SKILL_DIR/scripts/crossref_lookup.sh"
        local backup="$TMPDIR_SMOKE/crossref_lookup_backup.sh"
        cp "$real_lookup" "$backup"
        cp "$TMPDIR_SMOKE/crossref_lookup.sh" "$real_lookup"
        export CITE_VERIFY_FIXTURE_DIR="$FIXTURES"
        output=$("$LINT" "$example_file" 2>&1) && exit_code=0 || exit_code=$?
        cp "$backup" "$real_lookup"
        chmod +x "$real_lookup"
    else
        output=$("$LINT" "$example_file" 2>&1) && exit_code=0 || exit_code=$?
    fi

    # Extract the status from the verdicts in the output.
    # The report contains lines like "### METADATA_MISMATCH: Citation #1"
    # and the summary table has "| 1 | FAIL METADATA_MISMATCH |".
    # We check the "All findings" table for the status.
    local found_status
    found_status=$(printf '%s' "$output" | grep -oE '(VERIFIED|PARTIAL_MATCH|METADATA_MISMATCH|NOT_FOUND|NEEDS_MANUAL_VERIFICATION)' | head -n 1 || echo "UNKNOWN")

    local ok=0
    if printf '%s' "$found_status" | grep -qE "$want_pattern"; then
        ok=1
    fi

    if [ "$ok" -eq 1 ]; then
        printf '  PASS  %-45s  status=%-25s exit=%d\n' "$name" "$found_status" "$exit_code"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %-45s  status=%-25s exit=%d  (wanted: %s)\n' "$name" "$found_status" "$exit_code" "$want_pattern"
        FAIL=$((FAIL + 1))
        FAILED_TESTS="$FAILED_TESTS\n  - $name (got $found_status, wanted $want_pattern)"
    fi
}

MODE_LABEL="cached"
if [ "$LIVE" -eq 1 ]; then
    MODE_LABEL="live"
fi

printf '=== cite-verify smoke tests (%s mode) ===\n\n' "$MODE_LABEL"

run_example "Attention Is All You Need (verified)" \
    "$EXAMPLES/attention-paper-verified.md" \
    "VERIFIED"

run_example "LMR hallucination (metadata mismatch)" \
    "$EXAMPLES/transformer-hallucination.md" \
    "METADATA_MISMATCH"

run_example "Acemoglu Colonial Origins (verified)" \
    "$EXAMPLES/acemoglu-partial-match.md" \
    "VERIFIED|PARTIAL_MATCH"

run_example "Oster coefficient stability (verified)" \
    "$EXAMPLES/oster-verified.md" \
    "VERIFIED|PARTIAL_MATCH"

run_example "Fabricated paper (not found)" \
    "$EXAMPLES/fabricated-not-found.md" \
    "NOT_FOUND"

printf '\n=== Results ===\n'
printf 'Passed: %d\n' "$PASS"
printf 'Failed: %d\n' "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    printf '\nFailed tests:\n'
    printf '%b\n' "$FAILED_TESTS"
    exit 1
fi

printf '\nAll smoke tests pass (%s mode).\n' "$MODE_LABEL"
exit 0
