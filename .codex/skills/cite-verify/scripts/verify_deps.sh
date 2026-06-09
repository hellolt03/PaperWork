#!/usr/bin/env bash
# verify_deps.sh - startup integrity check for the pinned BibTeX parser.
#
# Strictly READ-ONLY: compares the current vendor tree against the baked
# manifest from install_deps.sh. Never bakes, never imports. If the manifest
# is missing, fails closed with instruction to run install_deps.sh.
#
# File enumeration uses `find` on the filesystem - we MUST NOT import
# bibtexparser to discover files, because the import would execute
# attacker-controlled code before any hash is checked.
#
# Usage: scripts/verify_deps.sh
# Output: silent on success, detailed error on mismatch.
# Exit codes: 0 ok; 1 mismatch; 2 missing vendor or missing manifest.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$SKILL_DIR/vendor"
MANIFEST="$VENDOR_DIR/.integrity-manifest.sha256"

if [ ! -d "$VENDOR_DIR/bibtexparser" ]; then
    echo "error: vendor/ not populated; run scripts/install_deps.sh" >&2
    exit 2
fi

if [ ! -f "$MANIFEST" ]; then
    echo "error: integrity manifest missing at $MANIFEST; run scripts/install_deps.sh to establish trust anchor" >&2
    exit 2
fi

TMP_SHA=$(mktemp)
trap 'rm -f "$TMP_SHA"' EXIT INT TERM

# Enumerate by filesystem walk, NOT by Python import. Sort for determinism
# (matches the sort in install_deps.sh manifest baking).
# awk strips the absolute vendor prefix so paths align with the baked manifest.
find "$VENDOR_DIR/bibtexparser" -name '*.py' -type f -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 \
    | awk -v prefix="$VENDOR_DIR/" '{ gsub(prefix, ""); print }' \
    > "$TMP_SHA"

if ! diff -q "$MANIFEST" "$TMP_SHA" >/dev/null 2>&1; then
    echo "FATAL: vendor integrity mismatch; vendor/ may be tampered." >&2
    echo "Diff (first 20 lines):" >&2
    diff "$MANIFEST" "$TMP_SHA" 2>&1 | head -20 >&2
    exit 1
fi

exit 0
