#!/usr/bin/env bash
# Verify the parser subprocess is killed by timeout within 10s + 2s grace on a CPU bomb.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
START=$(date +%s)
set +e
"$SKILL_DIR/scripts/parse_citation.sh" --file "$SKILL_DIR/tests/security/fixtures/cpu_bomb.bib" > /dev/null 2>&1
CODE=$?
set -e
END=$(date +%s)
ELAPSED=$((END - START))

if [ "$ELAPSED" -gt 15 ]; then
    echo "FAIL: parser ran $ELAPSED seconds, timeout did not fire" >&2
    exit 1
fi
# Either succeeded (parser tolerated the input) OR timed out gracefully. Both acceptable.
echo "PASS: 13_python_bounding (elapsed=${ELAPSED}s, code=$CODE)"
