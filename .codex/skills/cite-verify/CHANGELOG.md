# Changelog

## v0.2.0 - 2026-04-24

### Added
- BibTeX parser via isolated `python3 -I` subprocess with hash-pinned `bibtexparser==1.4.2`
- `scripts/install_deps.sh` and `scripts/verify_deps.sh` for supply-chain integrity
- Frozen sample regression corpus at `tests/corpus/sample-2026-04-24.bib` with per-entry DOI manifest
- Parser parity tests (`tests/parse_parity/`) catching drift between bash and Python paths
- Severity icons in the Markdown report (`[OK]`, `[?]`, `[!]`, `[X]`, `[TODO]`)
- `DUPLICATE_ENTRY` detection warning
- Edition-normalization preprocessing (`"2nd edition"` stripped before F1)
- Book-vs-chapter and token-containment advisories on PARTIAL_MATCH (non-promoting)
- `diagnosis: {reason, context}` object on every NEEDS_MANUAL verdict; reason enum includes `python3_unavailable`, `deps_integrity_fail`, `bibtex_parse_error`, `bibtex_parse_timeout`, `bibtex_entry_malformed`, `insufficient_title_tokens`, `crossref_rate_limited`, `network_unavailable`, `backend_server_error`, `input_over_size`
- Read-only log directory fallback to `$TMPDIR`
- Migration guide `docs/MIGRATION_v0.1_v0.2.md`
- Security vectors 11, 12, 13, 16 documented in `SECURITY.md`

### Fixed
- APA `(2022a)` year suffix no longer breaks lookup (NAS 2022a/b/c class of bug)

### Changed
- NEEDS_MANUAL verdicts now always carry a machine-readable reason and a human-readable context (breaking change for anyone parsing the JSONL audit log - new optional field)

### Security
- Python subprocess explicitly documented as bounded, not sandboxed
