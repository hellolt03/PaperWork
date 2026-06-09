#!/usr/bin/env bash
# install_deps.sh - one-time install of pinned Python deps for v0.2 BibTeX parser.
# Idempotent: safe to re-run - wipes vendor/ first so removed deps do not persist.
# Owns the integrity manifest: bakes vendor/.integrity-manifest.sha256 as the
# last step. verify_deps.sh is strictly read-only and fails closed if absent.
#
# Usage: scripts/install_deps.sh
# Effect: wipes and repopulates ./vendor/ with bibtexparser and transitive deps,
#         then bakes vendor/.integrity-manifest.sha256.
# Exit codes: 0 success; 2 if python3 missing; 3 if pip install fails.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$SKILL_DIR/vendor"
REQ_FILE="$SKILL_DIR/requirements.txt"
MANIFEST="$VENDOR_DIR/.integrity-manifest.sha256"

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found; install Python 3.9+ before running install_deps.sh" >&2
    exit 2
fi

if [ ! -f "$REQ_FILE" ]; then
    echo "error: requirements.txt not found at $REQ_FILE" >&2
    exit 3
fi

# Wipe for idempotency. pip --target is additive; stale files otherwise persist
# when a dep is removed from requirements.txt.
if [ -d "$VENDOR_DIR" ]; then
    rm -rf "$VENDOR_DIR"
fi
mkdir -p "$VENDOR_DIR"

python3 -m pip install \
    --require-hashes \
    --target="$VENDOR_DIR" \
    --no-compile \
    --disable-pip-version-check \
    -r "$REQ_FILE"

# Bake the integrity manifest. Enumerate .py files by FILESYSTEM WALK, never
# by `import` - the import path would run attacker-controlled top-level code
# before we have any hash to check (Codex A1). Also explicitly sort to make
# the manifest deterministic across macOS/Linux and across runs.
# awk strips the absolute vendor prefix so paths are portable across machines.
find "$VENDOR_DIR/bibtexparser" -name '*.py' -type f -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 \
    | awk -v prefix="$VENDOR_DIR/" '{ gsub(prefix, ""); print }' \
    > "$MANIFEST"

if [ ! -s "$MANIFEST" ]; then
    echo "error: manifest is empty; vendor install likely failed" >&2
    exit 3
fi

echo "ok: installed pinned deps into $VENDOR_DIR; manifest baked ($(wc -l < "$MANIFEST") files)"
