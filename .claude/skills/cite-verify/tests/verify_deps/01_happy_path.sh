#!/usr/bin/env bash
# 01_happy_path.sh - verify_deps.sh exits 0 on a clean vendor install.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

set +e
"$SKILL_DIR/scripts/verify_deps.sh"
code=$?
set -e

if [ "$code" -ne 0 ]; then
    echo "FAIL: verify_deps.sh exited $code on clean install" >&2
    exit 1
fi
echo "PASS: 01_happy_path"
