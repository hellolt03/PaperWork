#!/usr/bin/env bash
# 02_tampered_file.sh - verify_deps.sh exits nonzero after vendor file tamper.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Pick a .py file and tamper it (append a harmless comment).
VICTIM=$(find "$SKILL_DIR/vendor/bibtexparser" -name '*.py' -type f | head -n 1)
[ -z "$VICTIM" ] && { echo "FAIL: no .py files found in vendor/bibtexparser" >&2; exit 1; }
cp "$VICTIM" "$VICTIM.bak"
trap 'mv "$VICTIM.bak" "$VICTIM"' EXIT INT TERM
echo "# tamper marker" >> "$VICTIM"

set +e
"$SKILL_DIR/scripts/verify_deps.sh" >/dev/null 2>&1
code=$?
set -e

if [ "$code" -eq 0 ]; then
    echo "FAIL: verify_deps.sh passed despite vendor tamper" >&2
    exit 1
fi
echo "PASS: 02_tampered_file (verify_deps.sh caught the tamper, exit=$code)"
