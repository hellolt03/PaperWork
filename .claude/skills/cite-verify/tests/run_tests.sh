#!/usr/bin/env bash
# run_tests.sh - v0.2 aggregate test runner.
# Per CCG-on-plan A5: run() takes positional args, not a command-string,
# so invocations with arguments (run_one.sh <stem>) execute correctly in bash.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SKILL_DIR"

PASS=0; FAIL=0
run() {
    # $@ is the full argv - script path plus any args. Exec'd, not shell-parsed.
    if "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
}

# v0.1 suites (must keep passing)
run tests/test_title_match.sh
run tests/smoke.sh

# v0.2 parser unit tests
for stem in 01_apa_suffix 02_nested_braces 03_tex_accents 04_protected_caps 05_string_macros 06_malformed 07_empty 08_oversize_dos; do
    run tests/parse_bibtex/run_one.sh "$stem"
done
run tests/parse_bibtex/09_dispatcher.sh
run tests/parse_bibtex/10_apa_suffix_stdin.sh

# v0.2 parity tests
for stem in 01_english_ascii 02_utf8_authors 03_multi_author 04_doi_present 05_year_suffix 06_long_title; do
    run tests/parse_parity/run_parity.sh "$stem"
done

# v0.2 matcher tests
for f in tests/title_match/*.sh; do run "$f"; done

# v0.2 diagnosis tests (renamed from triage per CCG-on-plan B1)
for f in tests/diagnosis/*.sh; do run "$f"; done

# v0.2 report tests
for f in tests/report/*.sh; do run "$f"; done

# v0.2 log tests
for f in tests/log/*.sh; do run "$f"; done

# v0.2 verify_deps tests
for f in tests/verify_deps/*.sh; do run "$f"; done

# v0.2 security tests
for f in tests/security/*.sh; do run "$f"; done

# Known-hallucination canary (automated per CCG-on-plan B3). Runs live; skip only
# when explicitly told to via HALLUCINATION_OFFLINE=1 (for hermetic CI).
if [ "${HALLUCINATION_OFFLINE:-0}" != "1" ]; then
    run tests/corpus/run_known_hallucination_gate.sh
fi

# Sample ship gate (live API; opt-in via SAMPLE_LIVE=1)
if [ "${SAMPLE_LIVE:-0}" = "1" ]; then
    run tests/corpus/run_sample_gate.sh
fi

echo "=============================="
echo "Total: PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
