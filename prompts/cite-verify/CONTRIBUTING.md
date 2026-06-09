# Contributing to cite-verify

cite-verify is a small, focused tool maintained by one person. Contributions that improve citation verification accuracy are prioritized above all else.

## How to contribute

### Share a catch

The single most valuable contribution is sharing a hallucinated citation that cite-verify caught (or missed) in your work. Post it in [Discussions > Catches](https://github.com/jonckr/cite-verify/discussions/categories/catches). Anonymize freely.

### Report accuracy issues

Accuracy bugs get fixed first:

- **False positive** (correct citation flagged): [open an issue](https://github.com/jonckr/cite-verify/issues/new?template=false-positive.yml). Include the citation text and a link to the real paper.
- **False negative** (hallucination missed): [open an issue](https://github.com/jonckr/cite-verify/issues/new?template=false-negative.yml). Include the citation text and what the real paper at that identifier actually is.

### Report bugs

Script errors, crashes, unexpected output: [open a bug report](https://github.com/jonckr/cite-verify/issues/new?template=bug.yml).

### Suggest features

Post in [Discussions > Ideas](https://github.com/jonckr/cite-verify/discussions/categories/ideas) first. Ideas that get traction become issues. Check the [README scope section](https://github.com/jonckr/cite-verify#scope-and-limits) before proposing — some things are deliberately out of scope.

### Contribute code

1. **Small fixes** (typos, edge cases, test additions): open a PR directly.
2. **Medium changes** (new flag, parser improvement): open a Discussion first, then PR after alignment.
3. **Large changes** (new lookup source, new input format): must start as a Discussion. These affect the tool's scope and security surface.

## Development setup

```bash
git clone https://github.com/jonckr/cite-verify.git
cd cite-verify
chmod +x scripts/*.sh tests/*.sh
```

### Dependencies

cite-verify uses only standard Unix tools. No package manager needed.

**Required:** `bash` (3.2+), `curl`, `jq`, `awk`, `sed`, `perl` (with `Unicode::Normalize`, core since 5.8), `shasum`

**macOS only:** `textutil` (for `.docx` support, ships with the OS)

### Running tests

```bash
# Unit tests — title matcher adversarial suite (offline, fast)
./tests/test_title_match.sh

# Smoke tests — 5 example citations with cached responses (offline, fast)
./tests/smoke.sh

# Smoke tests — live Crossref API (requires network, ~35s)
./tests/smoke.sh --live
```

All tests must pass before submitting a PR.

### Code style

- **Bash 3.2 compatible.** No associative arrays, no `declare -A`, no `mapfile`. Stock macOS bash must work.
- **No external dependencies.** If it doesn't ship with macOS and common Linux distros, don't use it.
- **Security first.** All user input passes through `jq --arg` for JSON construction. No string interpolation into shell commands. No redirect following in curl. See [SECURITY.md](./SECURITY.md) for the full threat model.
- **One script, one job.** Each script in `scripts/` does one thing. `lint.sh` orchestrates.

### Adding test cases

The best PRs add test cases for edge cases you've encountered:

- **Title matcher tests:** add cases to `tests/test_title_match.sh` using the `expect_verdict` helper.
- **Smoke tests:** add example files to `examples/` with a corresponding cached response in `tests/fixtures/` and a new assertion in `tests/smoke.sh`.

## Architecture

```
scripts/
  parse_citation.sh    — extract fields from raw citation text
  crossref_lookup.sh   — query Crossref API (hardened client)
  title_match.sh       — F1-based title comparison
  lint.sh              — orchestrator: parse → lookup → match → report
  report.sh            — render Markdown report from verdicts

tests/
  test_title_match.sh  — 20-case adversarial matcher test suite
  smoke.sh             — end-to-end tests on example citations
  fixtures/            — cached Crossref API responses for offline testing

examples/
  *.md                 — one citation per file, each demonstrating a verdict
```

Data flow: `input → parse_citation.sh → crossref_lookup.sh → title_match.sh → report.sh → output`

Each script reads from arguments or stdin and writes JSON to stdout. Scripts communicate via JSON — no shared state, no temp files crossing script boundaries (except within `lint.sh`'s temp directory).

## What gets merged

- Accuracy improvements (fewer false positives, fewer false negatives)
- New test cases for real-world edge cases
- Security hardening
- Documentation fixes
- Performance improvements that don't sacrifice readability

## What doesn't get merged

- Features that expand scope beyond citation metadata verification
- Dependencies on tools not available on stock macOS + common Linux
- Changes that break Bash 3.2 compatibility
- Changes without tests

## Response time

This is a side project. Expect a week or two for responses. Bump threads if you're stuck.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE).
