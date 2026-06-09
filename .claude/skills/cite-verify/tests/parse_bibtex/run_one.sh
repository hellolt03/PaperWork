#!/usr/bin/env bash
# run_one.sh <fixture_stem>
# Runs parse_bibtex.py on <stem>.bib, diffs against <stem>.expected.json.
set -euo pipefail
STEM="$1"
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$SKILL_DIR/tests/parse_bibtex"
python3 -I "$SKILL_DIR/scripts/parse_bibtex.py" "$DIR/$STEM.bib" > /tmp/parse_bibtex_actual.json
# Canonicalize both sides through jq --sort-keys for stable compare.
jq --sort-keys . "$DIR/$STEM.expected.json" > /tmp/parse_bibtex_expected.json
jq --sort-keys . /tmp/parse_bibtex_actual.json > /tmp/parse_bibtex_actual_canonical.json
if ! diff -u /tmp/parse_bibtex_expected.json /tmp/parse_bibtex_actual_canonical.json; then
    echo "FAIL: $STEM" >&2
    exit 1
fi
echo "PASS: $STEM"
