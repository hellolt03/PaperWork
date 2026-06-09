# Migrating from cite-verify v0.1 to v0.2

## TL;DR

- **Install once:** `scripts/install_deps.sh` populates `./vendor/` with the hash-pinned `bibtexparser`.
- **New capability:** pass a `.bib` file directly - `lint.sh path/to/references.bib`.
- **Expect MORE `NEEDS_MANUAL` on first run** than you saw in v0.1. This is by design (see below).
- **All v0.1 inputs still work the same way.** Plain text, Markdown, stdin - byte-compatible.

## What changed

### New: BibTeX parser (hybrid architecture)

v0.2 adds a Python subprocess (`python3 -I scripts/parse_bibtex.py`) that handles `.bib` input via the pinned `bibtexparser` library. Plain-text / APA / stdin input still takes the existing bash regex path.

Parser routing (in `parse_citation.sh`):
1. File path ends `.bib` - Python path.
2. First non-blank line starts with `@article{`, `@book{`, etc. - Python path.
3. Otherwise - bash regex path (unchanged from v0.1).

### Behavioral change: APA `(2022a)` suffixes normalize cleanly

v0.1 treated `(2022a)` as literal text; the year field emerged as `2022a` and downstream lookups drifted. v0.2 strips the single-letter suffix in both parser paths and emits `year: "2022"`.

### Behavioral change: three matching improvements on PARTIAL_MATCH

1. **Edition normalization (preprocessing):** `"2nd edition"`, `"rev. ed."`, `"updated edition"`, etc. are stripped from both the citation and the Crossref record before F1 scoring.
2. **Book-vs-chapter advisory (non-promoting):** when Crossref's top hit is a `book-chapter` and a sibling `monograph` / `book` record matches, the report surfaces the candidate book record as an advisory. Verdict label stays `PARTIAL_MATCH`.
3. **Token-containment advisory (non-promoting, 90%):** when F1 is in `[0.60, 0.85)` and the shorter title's tokens are 90%-contained in the longer title, the report surfaces the containment candidate.

Neither advisory ever auto-upgrades PARTIAL_MATCH to VERIFIED. A false VERIFIED is a false negative on a hallucination, and safety dominates cosmetic improvement.

### Behavioral change: fails CLOSED instead of silent degradation

v0.1 frequently produced bare `NEEDS_MANUAL` with no reason. v0.2 fails closed and always carries a `diagnosis: {reason, context}` object. The new reason enum includes:

| reason | meaning | action |
|---|---|---|
| `python3_unavailable` | Python 3.9+ not on PATH | Install Python |
| `deps_integrity_fail` | vendor/ hash mismatch | Re-run `install_deps.sh` |
| `bibtex_parse_error` | Python parser returned nonzero | Check `.bib` for the line number in context string |
| `bibtex_parse_timeout` | parser exceeded 10s | Input likely pathological; split it |
| `bibtex_entry_malformed` | one entry bad, others OK | Fix the named line |
| `insufficient_title_tokens` | Cited title has fewer than 3 meaningful tokens after stopword removal; F1 matching unsafe | Verify manually |
| `crossref_rate_limited` | Crossref 429 after 3 retries | Wait and rerun |
| `network_unavailable` | Local network unreachable (DNS / route / timeout) | Check your internet connection |
| `backend_server_error` | Crossref returned HTTP 4xx or 5xx | Try again later; check Crossref status |
| `input_over_size` | > 60 citations | Split into batches |

### New: report rendering

- Per-verdict severity icons (`[OK]`, `[?]`, `[!]`, `[X]`, `[TODO]`).
- `DUPLICATE_ENTRY` warning when a DOI or raw citation repeats.
- `advisory` sub-bullet on PARTIAL_MATCH records that have one.
- `diagnosis.reason` and `diagnosis.context` sub-bullets on NEEDS_MANUAL records.

### New: log directory fallback

If `$SKILL_DIR/logs/` is unwritable (restricted mount, read-only FS), verifications log to `$TMPDIR/cite-verify-verifications-$USER.jsonl` with a single stderr warning. The run never fails because of log-write failure.

## Why you will see MORE `NEEDS_MANUAL` on first run

v0.1 parsed loosely and silently dropped fields it could not understand. v0.2 fails closed with an explicit reason. So if you ran v0.1 on a malformed `.bib`, it may have returned `VERIFIED` on a partially-parsed citation; v0.2 will return `NEEDS_MANUAL` with `bibtex_entry_malformed` and the line number. **This is the tool becoming more honest, not breaking.** Fix the `.bib` and re-run.

## Fixture-tested v0.2 guarantees

- Every fixture in `tests/fixtures/` (v0.1) produces the same verdict label, F1 score, and matched DOI.
- Plain-text stdin mode produces byte-identical normalized output.
- APA file input produces byte-identical normalized output.
- The parity tests (`tests/parse_parity/`) verify BibTeX form of the same citation produces output equivalent to APA form (with documented allowed differences).

## Rollback

Every release is a git tag: `git checkout v0.1.0` restores v0.1. Audit log format is stable across versions; no migration needed.
