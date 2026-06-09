#!/usr/bin/env bash
# Wrap verify_deps.sh tamper detection from the lint.sh caller perspective.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Ensure manifest baked.
"$SKILL_DIR/scripts/verify_deps.sh" >/dev/null

# Tamper a vendor file.
VICTIM=$(find "$SKILL_DIR/vendor/bibtexparser" -name '*.py' | head -1)
cp "$VICTIM" "$VICTIM.bak"
echo "# tamper" >> "$VICTIM"

# Attempt to run lint.sh on a .bib input - should fail closed.
set +e
OUT=$("$SKILL_DIR/scripts/lint.sh" "$SKILL_DIR/tests/parse_bibtex/01_apa_suffix.bib" 2>&1)
CODE=$?
set -e

# Restore.
mv "$VICTIM.bak" "$VICTIM"

if [ "$CODE" -eq 0 ]; then
    echo "FAIL: lint.sh ran to completion despite vendor tamper" >&2
    exit 1
fi
if ! printf '%s' "$OUT" | grep -qi "integrity"; then
    echo "FAIL: error message did not name the integrity failure" >&2
    exit 1
fi
echo "PASS: 16_vendor_tampering"
