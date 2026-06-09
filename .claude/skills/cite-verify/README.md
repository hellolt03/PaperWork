# cite-verify

> Catch LLM-hallucinated citations in academic bibliographies before they reach your reviewers.

cite-verify is an open source [Claude Code](https://claude.com/claude-code) skill that verifies bibliography citations against canonical metadata from [Crossref](https://www.crossref.org). It specifically targets the failure mode where a large language model pairs a **real identifier** (DOI, NBER working paper number, arXiv ID) with a **fabricated title** - the hardest hallucination to catch by eye because the citation looks superficially correct.

## New in v0.2

- BibTeX support - pass `.bib` files directly, no APA reformatting
- Richer diagnosis - every NEEDS_MANUAL carries a reason code and actionable context
- Advisories on PARTIAL_MATCH - candidate books and containment hints (never auto-upgrades)
- Severity icons and DUPLICATE_ENTRY warnings in the report

See [docs/MIGRATION_v0.1_v0.2.md](docs/MIGRATION_v0.1_v0.2.md) for the upgrade path.

**Install the BibTeX parser once:**

```bash
cd ~/.claude/skills/cite-verify
scripts/install_deps.sh
```

## The problem

You ask an LLM to help format the references section of a paper you're working on. The LLM returns a citation that looks like this:

```
Ludwig, J., Mullainathan, S., & Rambachan, A. (2025).
Causal inference with imperfect instruments
(NBER Working Paper No. 33344).
```

Every part of that citation is plausible. The authors are real economists at the top of their field. The year is current. The working paper number is real. But the title is fabricated - the actual paper at NBER w33344 is **"Large Language Models: An Applied Econometric Framework."**

This hallucination slips past a careful human reader because the identifier looks legitimate and the authors are the right people. It only gets caught when someone clicks through to the actual source paper and notices the mismatch. By the time that happens, the citation may already be in a draft that's been shared, reviewed, or submitted.

cite-verify catches this class of hallucination deterministically by querying Crossref for the canonical metadata at the stated identifier and comparing it to the claimed metadata using a blended F1 similarity score designed to resist both truncation attacks and fabricated additions.

## Quick demo

```bash
$ echo "Ludwig, J., Mullainathan, S., & Rambachan, A. (2025). Causal inference with imperfect instruments (NBER Working Paper No. 33344)." | ~/.claude/skills/cite-verify/scripts/lint.sh

# cite-verify report

**Total citations checked:** 1
**Verified:** 0
**Metadata mismatch (likely hallucination):** 1

## Critical issues

### METADATA_MISMATCH: Citation #1

**You cited:** Ludwig, Mullainathan, Rambachan (2025). Causal inference with imperfect instruments.

**Canonical record at 10.3386/w33344:** Ludwig, Mullainathan, Rambachan (2025). Large Language Models: An Applied Econometric Framework.

**Diagnosis:** The identifier is real but the claimed title does not match. This is the LLM-hallucination pattern.
```

## How it works

cite-verify is a bash skill that composes several small, focused scripts:

1. **`parse_citation.sh`** extracts structured fields (authors, year, title, DOI, NBER number, arXiv ID) from a raw citation string using heuristic regex.
2. **`crossref_lookup.sh`** queries the [Crossref REST API](https://www.crossref.org/documentation/retrieve-metadata/rest-api/) with hardening: HTTPS-only, no redirect following, polite-pool mailto, URL-encoded path components, size-capped responses, and a hardcoded allowlist of endpoints.
3. **`title_match.sh`** compares the claimed title against the canonical title using a **blended F1 score** (precision + recall) that resists the subset attack where a truncated real title would otherwise score as a perfect recall match.
4. **`lint.sh`** orchestrates the pipeline: reads input, extracts citations, verifies each one, and produces a Markdown report.
5. **`report.sh`** formats the report with sanitization so that terminal control sequences or malicious markdown in API responses cannot inject into the output.

Under the hood, the matching logic handles the major edge cases that an adversarial review identified:

- **Subset attack resistance** - truncated titles like "Large Language Models" vs the full canonical title do NOT verify cleanly; they flag as PARTIAL_MATCH with F1 ≈ 0.67.
- **Stopword inflation** - "on the" + any title won't falsely match (stopwords are filtered before comparison).
- **Short-title guard** - titles with fewer than 3 meaningful tokens flag as INSUFFICIENT rather than risk a false positive.
- **Unicode normalization** - "Über" and "Ueber" are treated as equivalent via Perl's `Unicode::Normalize::NFD`.
- **LaTeX stripping** - `\emph{Learning}`, `$\ell_1$`, and similar LaTeX commands are normalized out before comparison.
- **Multiset semantics** - repeated words are preserved in the comparison (not collapsed to sets), so "very very deep learning" and "very deep learning" don't match perfectly.

See [SECURITY.md](./SECURITY.md) for the full threat model and mitigations, `tests/test_title_match.sh` for the 20-case adversarial test suite, and `tests/smoke.sh` for the end-to-end smoke tests.

## Installation

cite-verify runs as a Claude Code skill. Clone this repository into your Claude Code skills directory:

```bash
cd ~/.claude/skills
git clone https://github.com/jonckr/cite-verify.git
chmod +x cite-verify/scripts/*.sh cite-verify/tests/*.sh
```

That's it. No pip install, no brew, no npm. cite-verify uses only tools that are already on any modern macOS or Linux system: `bash`, `curl`, `jq`, `awk`, `sed`, `perl`, `shasum`. On macOS you also need `textutil` for `.docx` support (ships with the OS).

## Usage

### Pasted citations in chat

In a Claude Code session, ask:

> Can you check this citation for me? Ludwig, J., Mullainathan, S., & Rambachan, A. (2025). Causal inference with imperfect instruments. NBER Working Paper 33344.

Claude invokes the skill, runs the verifier on the pasted text, and returns the Markdown report inline.

### File input

```bash
~/.claude/skills/cite-verify/scripts/lint.sh path/to/paper.md
```

Works on `.md`, `.tex`, `.bib`, plain text. For `.docx` on macOS, pipe through `textutil` first:

```bash
textutil -convert txt -stdout -- paper.docx | ~/.claude/skills/cite-verify/scripts/lint.sh
```

### Exit codes

- `0` - all citations verified or partial-match; no critical issues found
- `1` - at least one citation flagged as METADATA_MISMATCH or NOT_FOUND
- `2` - internal error (bad input, API failure, script bug)

## Scope and limits

This is v0.2. Deliberately narrow scope.

**In scope:**
- DOI-based lookup (Crossref `/works/{doi}`)
- NBER working paper lookup (via DOI pattern `10.3386/wXXXXX`)
- Title + author search (Crossref `/works` with `query.bibliographic` and `query.author`)
- Plain text, Markdown, `.bib` (BibTeX), and `.docx` input (the last macOS only)
- Hash-pinned isolated `python3 -I` BibTeX parser (handles nested braces, TeX accents, `@string` macros, BOM-prefixed files, and APA `2022a/b/c` year suffixes)
- Edition-marker normalization in title matching
- Two non-promoting advisories on `PARTIAL_MATCH` (book-vs-chapter candidate, substring-containment candidate)
- Structured `diagnosis: {reason, context}` object on every `NEEDS_MANUAL_VERIFICATION` verdict
- Severity icons and `DUPLICATE_ENTRY` warnings in the report
- Maximum 60 citations per invocation
- Maximum 1 MB input per invocation

**Out of scope for v0.2:**
- arXiv API lookups (deferred - arXiv has a 3-second rate limit and returns Atom XML, adding complexity)
- OpenAlex (deferred to v0.3 - will be opt-out fallback after Crossref `NOT_FOUND`)
- Claim grounding (checking whether the cited source actually supports a claim - different problem, different tool)
- Retraction detection (a cached canonical record might still show a paper that's since been retracted)
- Non-Latin scripts in titles (depends on Unicode normalization quality)
- Auto-fix mode (rewriting the source document with corrected citations)

## Privacy

cite-verify does NOT phone home. It does query Crossref's public API with bibliographic metadata from your citations. A local audit log of SHA-256 hashed citations is maintained at `~/.claude/skills/cite-verify/logs/verifications.jsonl` and never leaves your machine.

**Do not use this skill on documents where even the list of cited papers is sensitive** (confidential grant proposals, embargoed research, anonymous reviewer reports). Crossref will see every citation you check.

See [SECURITY.md](./SECURITY.md) for the full threat model.

## Theoretical foundation

cite-verify applies the validation principle from the NBER paper that inspired this whole project:

> Ludwig, J., Mullainathan, S., & Rambachan, A. (2025). **Large Language Models: An Applied Econometric Framework.** NBER Working Paper 33344. https://www.nber.org/papers/w33344

The Ludwig-Mullainathan-Rambachan paper proves that LLM-generated outputs contain systematic measurement error that propagates into downstream research artifacts unless a validation sample is collected. cite-verify applies the same principle to bibliographies: each citation is treated as an LLM-generated label with potential measurement error, and the canonical Crossref record is treated as the ground truth that validates it.

If you are building anything that uses LLM outputs as inputs to empirical research, you should read the LMR paper. If you are writing academic papers with LLM assistance, you should run cite-verify (or something like it) on every bibliography before submission.

## Related tools

cite-verify occupies a specific niche in the citation-tooling space. Other tools touch adjacent problems:

- **[willoscar/research-units-pipeline-skills](https://github.com/willoscar/research-units-pipeline-skills)** - a 100-skill research pipeline framework including `citation-verifier`, which generates BibTeX from structured paper notes and verifies URLs via HTML title scraping. Best if you're building a research paper from scratch inside a structured pipeline. Different workflow position (build-stage, not post-write audit) and different verification mechanism (HTML scraping vs canonical API lookup).

- **[liangdabiao/claude-code-stock-deep-research-agent](https://github.com/liangdabiao/claude-code-stock-deep-research-agent)** - a financial research agent including `citation-validator`, which does LLM-based claim-to-source grounding with A-E source quality ratings. Best for checking whether factual claims in financial reports are actually supported by their sources. Different granularity (claim-level, not metadata-level) and different domain (finance, not academic).

cite-verify is narrower: **post-write, metadata-only, Crossref-first, academic-focused.**

## Contributing and feedback

cite-verify gets better when users share catches and report bugs. The most valuable contributions:

- **Share a catch.** If cite-verify caught a hallucination in your work, post it in [Discussions → Catches](https://github.com/jonckr/cite-verify/discussions). Anonymize freely.
- **Report a false positive.** If cite-verify flagged a correct citation, [open an issue](https://github.com/jonckr/cite-verify/issues/new?template=false-positive.yml). False positives get fixed first.
- **Report a false negative.** If a hallucinated citation slipped past cite-verify, [open an issue](https://github.com/jonckr/cite-verify/issues/new?template=false-negative.yml). Missed hallucinations are the failure mode the tool exists to prevent.
- **Suggest improvements.** Feature ideas belong in [Discussions → Ideas](https://github.com/jonckr/cite-verify/discussions) before they become issues.
- **Contribute code.** Small patches via PR. Large changes start with a Discussion. See [CONTRIBUTING.md](./CONTRIBUTING.md) for details.

Response time: this is a side project maintained by one person. Expect a week or two for responses. Bump threads if you're stuck.

## License

[MIT](./LICENSE). Use it, fork it, modify it. If you build something useful on top, a link back is appreciated but not required.

## Acknowledgments

Built by [@jonckr](https://github.com/jonckr). Targets the specific class of LLM citation hallucinations where real paper identifiers get paired with fabricated titles. Adversarially reviewed by OpenAI's Codex before v0.1 shipped. Theoretical grounding from Ludwig, Mullainathan & Rambachan (2025).
