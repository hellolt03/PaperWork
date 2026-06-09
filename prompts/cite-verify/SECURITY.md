# Security

cite-verify processes user-provided citation text and sends bibliographic metadata to external APIs. This document describes the threat model, attack surface, and mitigations.

## Threat model

**Attacker goal:** exploit cite-verify to exfiltrate data, execute arbitrary commands, or produce misleading verification results.

**Trust boundaries:**

1. **User input** (citation text, file paths) - untrusted
2. **Crossref API responses** - untrusted (could be modified in transit despite HTTPS, or the API could return unexpected data)
3. **Local filesystem** (log files, temp files) - trusted but defended against symlink attacks

## Attack surface and mitigations

| Vector | Risk | Mitigation |
|--------|------|------------|
| **Shell injection via citation text** | Attacker embeds `$(cmd)` or backticks in a citation | All user strings pass through `jq --arg` for JSON construction. Never interpolated into shell commands. `parse_citation.sh` strips null bytes and control characters before processing. |
| **Path traversal via file input** | Attacker passes `../../etc/passwd` as input | `lint.sh` copies input to a temp directory via `cp --` (double-dash prevents option injection). File is read as opaque bytes. |
| **DOI injection** | Malicious DOI like `10.1234/../../../admin` | `crossref_lookup.sh` validates DOI format with strict regex before URL construction. Rejects `..`, query strings (`?`), fragments (`#`), and shell metacharacters. DOI suffix is URL-encoded via `jq -Rr @uri`. |
| **SSRF via redirect** | Crossref response triggers redirect to internal network | curl runs with no `-L` flag - redirects are not followed. Only `api.crossref.org` is contacted. |
| **Response bomb (JSON DoS)** | Crossref returns a multi-GB response | `curl --max-filesize 2000000` caps responses at 2 MB. |
| **Slow response (timeout DoS)** | API hangs indefinitely | `curl --max-time 10` enforces a 10-second timeout per request. |
| **Citation flood (resource exhaustion)** | User pipes millions of citations | `lint.sh` enforces a 1 MB input size limit and a 60-citation cap. |
| **Symlink attack on log file** | Attacker replaces `logs/verifications.jsonl` with a symlink to a sensitive file | `lint.sh` checks `[ -L "$LOG_FILE" ]` and refuses to write if the log is a symlink. |
| **Report injection** | Crossref title contains Markdown or terminal escape sequences | `report.sh` sanitizes all external strings: strips control characters, escapes Markdown metacharacters (`#`, `` ` ``, `*`, `_`, `[`, `]`). |
| **Temp file race condition** | Another process writes to cite-verify's temp dir | `mktemp -d` creates a directory with mode 0700. `trap` ensures cleanup on exit, interrupt, and termination. |
| **TLS downgrade** | Man-in-the-middle downgrades HTTPS | `curl --proto =https --tlsv1.2` enforces HTTPS with TLS 1.2 minimum. |

## Network exposure

cite-verify contacts exactly one external service:

- **Crossref REST API** (`https://api.crossref.org`)
  - Endpoint `/works/{doi}` - DOI lookup
  - Endpoint `/works?query.bibliographic=...&query.author=...` - search
  - User-Agent includes a mailto for Crossref's polite pool

**No other network requests are made.** There is no telemetry, no analytics, no phone-home behavior.

### What Crossref sees

For each citation checked, Crossref receives:

- The DOI (if present in the citation)
- The title and first author name (if searching by bibliographic metadata)
- Your IP address
- The cite-verify User-Agent string

Crossref does **not** receive the full document, surrounding text, or any other citation metadata beyond what is needed for the specific lookup.

## Local data

- **Audit log** (`logs/verifications.jsonl`): stores SHA-256 hashes of citation strings (not raw text), verification status, lookup mode, and timestamps. Never leaves your machine. File permissions set to 0600.
- **Cache directory** (`cache/`): reserved for future offline caching. Currently empty. Listed in `.gitignore`.
- **Temp files**: created in a per-invocation `mktemp -d` directory, cleaned up on exit via `trap`.

## Scope limits

cite-verify does **not** defend against:

- A compromised Crossref API returning fabricated metadata (mitigated by HTTPS, but a compromised server could return wrong data)
- Retracted papers appearing as VERIFIED (Crossref records may not reflect retractions immediately)
- Citation text in non-Latin scripts (Unicode normalization quality varies)
- Adversarial citations specifically crafted to exploit the F1 matching thresholds (the thresholds are published in `title_match.sh`)

## v0.2 attack vectors (new in 2026-04)

| # | Vector | Mitigation | Tested by |
|---|---|---|---|
| 11 | BibTeX TeX injection (`\write18`, `\input`) | Field whitelist; `bibtexparser` does not invoke any TeX engine | tests/security/11_tex_injection.sh |
| 12 | BibTeX path traversal via `file={...}` | Field whitelist (`file` is not read) | tests/security/12_path_traversal.sh |
| 13 | Python subprocess blast radius | `python3 -I`; `ulimit -v 262144`; `timeout 10s`; list-args `subprocess` call | tests/security/13_python_bounding.sh |
| 16 | Vendor tampering (TOCTOU) | verify_deps.sh per-`.py`-file SHA-256 manifest; fail-closed on mismatch | tests/security/16_vendor_tampering.sh |

### Bounded, not sandboxed (honesty fix per CCG review)

Vector 13's mitigations are **bounding**, not **sandboxing**. We defend against the specific failure modes listed below and explicitly document the residuals.

**What IS mitigated:**
- Shell injection via subprocess invocation (list args, never `shell=True`)
- User Python config hijack (`python3 -I` ignores PYTHONPATH, user site, sitecustomize)
- Wall-clock runaway (`timeout 10s`)
- Virtual-memory exhaustion (`ulimit -v 262144`)
- Arbitrary filesystem reads via our parser code (only opens argv[1])

**What is NOT mitigated (residual risks):**
- Filesystem reads from stdlib-triggered imports (`/proc`, `/etc/mime.types`, CA bundles, timezone data)
- Writes to `/tmp` via Python `tempfile` or transitive deps
- Network calls via transitive stdlib imports (we rely on bibtexparser being pure-Python text processing; re-audited each release)
- CPU bombs from adversarial brace nesting within the 10s wall-clock window (no `ulimit -t`)
- Fork bombs within the 10s window (no `ulimit -u`)
- Temp-file / cwd side effects in the user's own permission context

**Consequence:** cite-verify is protected enough for **untrusted BibTeX content from a trusted author** (a researcher's own .bib files). It should NOT be used as a service endpoint accepting BibTeX from unauthenticated strangers without additional OS-level sandboxing (firejail, seccomp, containers).

### Supply-chain pinning

`bibtexparser==1.4.2` is pinned by SHA-256 hash in `requirements.txt` and installed via `pip --require-hashes --target=./vendor` by `scripts/install_deps.sh`. Startup `scripts/verify_deps.sh` hashes every `.py` file actually imported by the parser (not just top-level package dir) and fails closed on mismatch. Residual risk: TOCTOU between verify and use is short but not eliminated.

## Reporting vulnerabilities

If you find a security issue, **do not open a public issue.** Instead, [open a private security advisory](https://github.com/jonckr/cite-verify/security/advisories/new) on the repository. Include:

1. Description of the vulnerability
2. Steps to reproduce
3. Impact assessment

Response time: within one week for security issues.
