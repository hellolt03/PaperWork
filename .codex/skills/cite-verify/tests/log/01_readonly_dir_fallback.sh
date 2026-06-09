#!/usr/bin/env bash
# If $SKILL_DIR/logs is unwritable, lint.sh must fall back to
# $TMPDIR/cite-verify-verifications-$USER.jsonl and emit one stderr warning.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$SKILL_DIR/logs"
mkdir -p "$LOG_DIR"
chmod 0500 "$LOG_DIR"
trap 'chmod 0755 "$LOG_DIR"' EXIT

FALLBACK="${TMPDIR:-/tmp}/cite-verify-verifications-${USER:-anon}.jsonl"
rm -f "$FALLBACK"

# Run a trivial invocation (combine stdout+stderr to capture the warning).
OUT=$("$SKILL_DIR/scripts/lint.sh" <<< "Smith (2020) Paper. DOI 10.1/abc" 2>&1 || true)

if ! printf '%s' "$OUT" | grep -q "log fallback"; then
    echo "FAIL: lint.sh did not emit fallback warning" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
if [ ! -f "$FALLBACK" ]; then
    echo "FAIL: fallback log file not created at $FALLBACK" >&2
    exit 1
fi
echo "PASS: 01_readonly_dir_fallback"
