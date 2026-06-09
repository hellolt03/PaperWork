#!/usr/bin/env bash
# When a .bib input is given but python3 is not available, lint.sh must emit
# NEEDS_MANUAL with diagnosis.reason=python3_unavailable and an actionable context.
# Strategy: prepend a stub python3 that exits 1 (simulating broken/absent python3).
# lint.sh checks `python3 --version` rather than `command -v`, so an executable
# stub that exits nonzero is treated as unavailable.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT

# Stub python3: executable, but exits 1 on --version so lint.sh treats it as absent.
cat > "$STUB_DIR/python3" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$STUB_DIR/python3"

OUT=$(PATH="$STUB_DIR:$PATH" "$SKILL_DIR/scripts/lint.sh" "$SKILL_DIR/tests/parse_bibtex/01_apa_suffix.bib" 2>/dev/null || true)

# The Markdown report should contain the reason and context strings.
if ! printf '%s' "$OUT" | grep -q "python3_unavailable"; then
    echo "FAIL: report missing python3_unavailable reason" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
if ! printf '%s' "$OUT" | grep -qi "install Python 3.9"; then
    echo "FAIL: report missing actionable context string" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
fi
echo "PASS: 01_python_unavailable"
