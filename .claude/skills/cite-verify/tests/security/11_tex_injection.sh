#!/usr/bin/env bash
# Verify \write18 and \input TeX escapes do NOT execute.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
rm -f /tmp/citeverify_pwned

"$SKILL_DIR/scripts/parse_citation.sh" --file "$SKILL_DIR/tests/security/fixtures/tex_injection.bib" > /dev/null

if [ -f /tmp/citeverify_pwned ]; then
    echo "FAIL: TeX \\write18 executed" >&2
    rm -f /tmp/citeverify_pwned
    exit 1
fi
echo "PASS: 11_tex_injection"
