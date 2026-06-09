#!/usr/bin/env bash
# Force a Crossref network-failure path and verify a diagnosis reason is surfaced.
# The stub curl exits 28 (timeout); crossref_lookup.sh maps this to http_code="000"
# which lint.sh maps to network_unavailable. The test accepts any of the three
# network/backend/rate-limit codes per plan Task 14 note.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cat > "$STUB_DIR/curl" <<'EOF'
#!/usr/bin/env bash
# Stub curl that always exits 28 (timeout), emitting no body.
exit 28
EOF
chmod +x "$STUB_DIR/curl"

# Point lint.sh to the stub curl via PATH override.
OUT=$(PATH="$STUB_DIR:$PATH" "$SKILL_DIR/scripts/lint.sh" <<< "Smith (2020) A Paper. DOI 10.1/abc" 2>/dev/null || true)
if ! printf '%s' "$OUT" | grep -qE "crossref_rate_limited|backend_server_error|network_unavailable"; then
    echo "FAIL: no rate-limit/network reason surfaced" >&2
    echo "$OUT" >&2
    exit 1
fi
echo "PASS: 02_rate_limited"
