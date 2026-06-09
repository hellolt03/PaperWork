#!/usr/bin/env bash
# test_title_match.sh — adversarial test suite for title_match.sh
#
# Runs each codex attack vector and verifies the matcher produces the
# correct verdict. Exits non-zero if any attack still passes as VERIFIED
# when it should be flagged.

set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MATCHER="$SKILL_DIR/scripts/title_match.sh"

PASS=0
FAIL=0
FAILED_TESTS=""

# Helper: run the matcher, extract the verdict, compare to expected.
# Usage: expect_verdict "test name" "expected verdict" "expected title" "canonical title"
expect_verdict() {
    local name="$1"
    local want="$2"
    local expected="$3"
    local canonical="$4"

    local result verdict f1
    result=$("$MATCHER" "$expected" "$canonical" 2>&1)
    verdict=$(printf '%s' "$result" | jq -r '.verdict // "ERROR"')
    f1=$(printf '%s' "$result" | jq -r '.f1 // 0')

    # Allow want to be a '|'-separated list of acceptable verdicts.
    local ok=0
    local IFS='|'
    for acceptable in $want; do
        if [ "$verdict" = "$acceptable" ]; then
            ok=1
            break
        fi
    done
    unset IFS

    if [ "$ok" -eq 1 ]; then
        printf '  PASS  %-55s  verdict=%-14s f1=%s\n' "$name" "$verdict" "$f1"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %-55s  verdict=%-14s f1=%s  (wanted: %s)\n' "$name" "$verdict" "$f1" "$want"
        FAIL=$((FAIL + 1))
        FAILED_TESTS="$FAILED_TESTS\n  - $name (got $verdict, wanted $want)"
    fi
}

printf '=== title_match.sh adversarial test suite ===\n\n'

printf '## Group 1: Identity and canonical correctness\n'
expect_verdict "identical titles" \
    "EXACT|STRONG_MATCH" \
    "Attention Is All You Need" \
    "Attention Is All You Need"

expect_verdict "case-insensitive identical" \
    "EXACT|STRONG_MATCH" \
    "ATTENTION IS ALL YOU NEED" \
    "attention is all you need"

expect_verdict "punctuation variation only" \
    "EXACT|STRONG_MATCH" \
    "Attention Is All You Need." \
    "Attention, Is All You Need"

printf '\n## Group 2: The LMR subset attack (codex critical finding)\n'
expect_verdict "LMR truncation hallucination" \
    "WEAK_MATCH|MISMATCH" \
    "Large Language Models" \
    "Large Language Models: An Applied Econometric Framework"

expect_verdict "LMR reverse direction" \
    "WEAK_MATCH|MISMATCH" \
    "Large Language Models: An Applied Econometric Framework" \
    "Large Language Models"

printf '\n## Group 3: Legitimate subtitle variation\n'
# When user cites with subtitle and got has subtitle too: EXACT.
# When user cites without subtitle and got has subtitle: should be MATCH or WEAK_MATCH.
expect_verdict "user cites WITHOUT subtitle, canonical has subtitle" \
    "STRONG_MATCH|MATCH|WEAK_MATCH" \
    "Attention Is All You Need" \
    "Attention Is All You Need The Transformer Architecture Explained"

expect_verdict "canonical both sides has subtitle" \
    "EXACT|STRONG_MATCH|MATCH" \
    "Bartik Instruments What When Why And How" \
    "Bartik Instruments What When Why and How"

printf '\n## Group 4: Short-title attacks (insufficient meaningful tokens)\n'
expect_verdict "Capital Marx vs Piketty (1 token)" \
    "INSUFFICIENT" \
    "Capital" \
    "Capital in the Twenty-First Century"

expect_verdict "Dreams (1 token)" \
    "INSUFFICIENT" \
    "Dreams" \
    "Dreams of a Final Theory: The Search for Fundamental Laws of Nature"

expect_verdict "2-token title" \
    "INSUFFICIENT" \
    "Deep Learning" \
    "Deep Learning for Causal Inference in Tax Fraud Detection"

printf '\n## Group 5: Stopword inflation attack\n'
expect_verdict "On the — stopwords only in expected" \
    "INSUFFICIENT|MISMATCH" \
    "On the" \
    "On the Origin of Species by Means of Natural Selection"

expect_verdict "The Way of the World anagram (below min token count)" \
    "INSUFFICIENT" \
    "The Way of the World" \
    "The World of the Way"

printf '\n## Group 6: Repetition and multiset correctness\n'
expect_verdict "very very deep vs very deep (multiset)" \
    "STRONG_MATCH|MATCH|WEAK_MATCH" \
    "Very Very Deep Learning for Images" \
    "Very Deep Learning for Images"

printf '\n## Group 7: Unicode, transliteration, non-ASCII\n'
expect_verdict "German umlauts (Ü/Ö → U/O via perl NFD)" \
    "EXACT|STRONG_MATCH|MATCH" \
    "Über die Ökonometrie moderner Methoden" \
    "Uber die Okonometrie moderner Methoden"

expect_verdict "French accents (È/é → E/e via perl NFD)" \
    "EXACT|STRONG_MATCH|MATCH|INSUFFICIENT" \
    "L'Être et le Néant de Sartre" \
    "L'Etre et le Neant de Sartre"

printf '\n## Group 8: LaTeX in titles\n'
expect_verdict "LaTeX math mode stripped to same as canonical" \
    "EXACT|STRONG_MATCH|MATCH" \
    "On the Convergence of \$\\ell_1\$ Minimization Algorithms for Sparse Recovery" \
    "On the Convergence of Minimization Algorithms for Sparse Recovery"

expect_verdict "LaTeX \\emph{} command stripped" \
    "EXACT|STRONG_MATCH|MATCH" \
    "Statistical \\emph{Learning} Theory Foundations" \
    "Statistical Learning Theory Foundations"

printf '\n## Group 9: Complete mismatches (real hallucination)\n'
expect_verdict "totally different papers" \
    "MISMATCH" \
    "Causal Inference with Imperfect Instruments" \
    "Large Language Models An Applied Econometric Framework"

expect_verdict "fabricated paper vs completely unrelated" \
    "MISMATCH" \
    "Deep Learning for Banana Detection in Supermarket Aisles" \
    "Attention Is All You Need"

printf '\n## Group 10: Numeric variant titles\n'
expect_verdict "Arabic vs Arabic numerals (identical)" \
    "STRONG_MATCH|MATCH|EXACT" \
    "World War 2 Origins" \
    "World War 2 Origins"

printf '\n=== Results ===\n'
printf 'Passed: %d\n' "$PASS"
printf 'Failed: %d\n' "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    printf '\nFailed tests:\n'
    printf '%b\n' "$FAILED_TESTS"
    exit 1
fi

printf '\nAll adversarial tests pass. The matcher resists codex findings.\n'
exit 0
