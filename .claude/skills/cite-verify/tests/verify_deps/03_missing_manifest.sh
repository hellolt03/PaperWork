#!/usr/bin/env bash
# verify_deps.sh MUST exit nonzero when the manifest is missing (fail closed).
# It MUST NOT auto-bake a fresh manifest (Gemini B3 / Codex A2).
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$SKILL_DIR/vendor/.integrity-manifest.sha256"

# Temporarily move the manifest aside.
mv "$MANIFEST" "$MANIFEST.bak"
trap 'mv "$MANIFEST.bak" "$MANIFEST"' EXIT

set +e
OUT=$("$SKILL_DIR/scripts/verify_deps.sh" 2>&1)
code=$?
set -e

if [ "$code" -eq 0 ]; then
    echo "FAIL: verify_deps.sh passed despite missing manifest" >&2
    exit 1
fi
if ! printf '%s' "$OUT" | grep -q "install_deps.sh"; then
    echo "FAIL: error message did not direct user to install_deps.sh" >&2
    exit 1
fi
echo "PASS: 03_missing_manifest"
