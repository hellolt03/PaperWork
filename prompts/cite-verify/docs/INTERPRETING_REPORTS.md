# How to read a cite-verify report

A cite-verify report is a short Markdown document with one section per citation plus a summary header. This guide explains what each signal means and what action, if any, you should take.

## Verdict icons (left of each entry)

| Icon | Verdict | What it means | Action |
|---|---|---|---|
| `[OK]` | `VERIFIED` | A canonical record matched your citation on author, year, title, and (when present) DOI. | None. Your citation is good. |
| `[?]` | `PARTIAL_MATCH` | A record exists and plausibly matches, but something is off (title variance, edition wording, chapter-vs-book). | Read the advisory if present. Confirm the candidate record. |
| `[!]` | `METADATA_MISMATCH` | A canonical record EXISTS at the identifier you gave (DOI, NBER number), but the title does NOT match. **This is the LLM hallucination failure mode cite-verify was built to catch.** | Fix the citation before submission. Do not cite. |
| `[X]` | `NOT_FOUND` | No record anywhere in Crossref. Could be a legitimate obscure source (think-tank blog, gov report), or a fabricated cite. | Verify by hand. v0.3 will add OpenAlex as a second backend to cover more sources. |
| `[TODO]` | `NEEDS_MANUAL_VERIFICATION` | cite-verify could not reach a verdict. The `diagnosis.reason` tells you why. | Read `diagnosis.reason` and `diagnosis.context` for the fix. |

## Advisories (on `[?]` entries)

Advisories are **not** verdict changes. A `[?] PARTIAL_MATCH -- matched a book-chapter` entry is STILL a PARTIAL_MATCH; the advisory gives you a candidate record to eyeball. Auto-upgrading to VERIFIED would turn a fuzzy match into a false-confident one, which would gut the tool's value on the hallucination class of error. Safety dominates cosmetic improvement.

Advisory types in v0.2:

- **`advisory: book_candidate`** - Crossref's top hit was a book chapter, but a sibling book record exists with the same first author and a strong title match (F1 > 0.85). The named book record is likely what you meant. Confirm, then replace the DOI in your bibliography.
- **`advisory: token_containment`** - The citation title tokens are 90%+ contained within a candidate Crossref record, but F1 scoring puts them in the PARTIAL zone (usually due to subtitle length differences). Confirm the candidate record matches the paper you read.

## Diagnosis (on `[TODO]` entries)

Every `NEEDS_MANUAL_VERIFICATION` carries a `diagnosis: {reason, context}` object. The reason is a stable enum; the context is a short human string you can act on.

| diagnosis.reason | What to do |
|---|---|
| `python3_unavailable` | Install Python 3.9+ (Homebrew: `brew install python@3.12`). |
| `deps_integrity_fail` | Run `scripts/install_deps.sh` to reinstall the pinned parser. |
| `bibtex_parse_error` | Open the `.bib` at the line named in `context` and fix the syntax. |
| `bibtex_parse_timeout` | Input is pathological; split the `.bib` into smaller batches. |
| `bibtex_entry_malformed` | Fix the one entry named in `context`; others continue. |
| `insufficient_title_tokens` | The cited title has fewer than 3 meaningful tokens after stopword removal; automated F1 matching is unreliable. Verify manually. |
| `crossref_rate_limited` | Wait a minute and re-run; Crossref's polite pool has quotas. |
| `network_unavailable` | Check your internet connection. |
| `backend_server_error` | Crossref returned an HTTP 4xx or 5xx error; try again later or check the Crossref status page. |
| `input_over_size` | Input exceeds the 60-citation cap; split into batches. |

## Duplicates

A `DUPLICATE_ENTRY` warning at the top of the report means the same DOI (or the same raw citation when DOI is absent) appears more than once in your input. This is usually an accidental paste; clean it up before submitting.

## Exit code

cite-verify exits `0` when every entry is `VERIFIED`, `1` when any entry is `METADATA_MISMATCH` or `NOT_FOUND`, `2` on internal error. `PARTIAL_MATCH` and `NEEDS_MANUAL_VERIFICATION` do NOT fail the exit code; they require human judgment but are not proof of a hallucination.
