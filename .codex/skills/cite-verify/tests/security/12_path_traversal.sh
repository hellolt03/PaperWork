#!/usr/bin/env bash
# Verify file={../../etc/passwd} is ignored (not a whitelisted field).
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

OUT=$("$SKILL_DIR/scripts/parse_citation.sh" --file "$SKILL_DIR/tests/security/fixtures/tex_injection.bib")

# If any record contains the string "passwd" we leaked.
if printf '%s' "$OUT" | grep -q "passwd"; then
    echo "FAIL: path traversal value leaked into output" >&2
    exit 1
fi
echo "PASS: 12_path_traversal"
