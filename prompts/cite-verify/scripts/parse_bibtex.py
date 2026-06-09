#!/usr/bin/env python3
# parse_bibtex.py - isolated BibTeX parser for cite-verify v0.2.
#
# Reads a single .bib file (path from argv[1]), emits a JSON array of
# normalized citation records to stdout. One record per entry.
#
# Normalized record shape:
#   {"authors": [str], "year": str, "title": str, "doi": str|None,
#    "venue": str|None, "type": str}
#
# Safety: invoked via `python3 -I` (no PYTHONPATH, no user site, no sitecustomize).
# Wrapped by `timeout 10s` and `ulimit -v 262144` (256MB) in the bash dispatcher.
# Only reads the file at argv[1]; no user-controlled paths beyond that.
# Field whitelist: only title/author/year/doi/type/booktitle/journal/volume/
# pages/publisher/editor are read; `file={...}` and other non-whitelisted
# fields are ignored regardless of value (blocks BibTeX path-traversal vectors).
# Output strings encoded UTF-8 (explicit; per Gemini review Tier-C item).
# Year token stripped of APA a/b/c suffix before emission.

import json
import os
import re
import sys

# Ensure vendored bibtexparser is reachable.
VENDOR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "vendor"
)
if os.path.isdir(VENDOR):
    sys.path.insert(0, VENDOR)

import bibtexparser  # noqa: E402
from bibtexparser.bparser import BibTexParser  # noqa: E402

FIELD_WHITELIST = {
    "title", "author", "year", "doi", "booktitle", "journal",
    "volume", "pages", "publisher", "editor",
}

YEAR_SUFFIX_RE = re.compile(r"^(18|19|20)([0-9]{2})[a-z]?$")

MAX_ENTRIES = 60

TEX_ACCENTS = {
    "\\'{i}": "í", "\\'{a}": "á", "\\'{e}": "é",
    "\\'{o}": "ó", "\\'{u}": "ú",
    '\\"{a}': "ä", '\\"{e}': "ë", '\\"{i}': "ï",
    '\\"{o}': "ö", '\\"{u}': "ü",
    "\\'{A}": "Á", "\\'{E}": "É", "\\'{I}": "Í",
    "\\'{O}": "Ó", "\\'{U}": "Ú",
    '\\"{A}': "Ä", '\\"{E}': "Ë", '\\"{I}': "Ï",
    '\\"{O}': "Ö", '\\"{U}': "Ü",
    "\\`{a}": "à", "\\`{e}": "è", "\\`{i}": "ì",
    "\\`{o}": "ò", "\\`{u}": "ù",
    "\\^{a}": "â", "\\^{e}": "ê", "\\^{i}": "î",
    "\\^{o}": "ô", "\\^{u}": "û",
    "\\~{n}": "ñ", "\\~{N}": "Ñ",
    "\\c{c}": "ç", "\\c{C}": "Ç",
}

# Precomposed forms that the fixture expects (NFC).
# We store precomposed chars directly for the common cases.
TEX_ACCENTS_PRECOMPOSED = {
    "\\'{i}": "í", "\\'{a}": "á", "\\'{e}": "é",
    "\\'{o}": "ó", "\\'{u}": "ú",
    '\\"{a}': "ä", '\\"{e}': "ë", '\\"{i}': "ï",
    '\\"{o}': "ö", '\\"{u}': "ü",
    "\\'{A}": "Á", "\\'{E}": "É", "\\'{I}": "Í",
    "\\'{O}": "Ó", "\\'{U}": "Ú",
    '\\"{A}': "Ä", '\\"{E}': "Ë", '\\"{I}': "Ï",
    '\\"{O}': "Ö", '\\"{U}': "Ü",
    "\\`{a}": "à", "\\`{e}": "è", "\\`{i}": "ì",
    "\\`{o}": "ò", "\\`{u}": "ù",
    "\\^{a}": "â", "\\^{e}": "ê", "\\^{i}": "î",
    "\\^{o}": "ô", "\\^{u}": "û",
    "\\~{n}": "ñ", "\\~{N}": "Ñ",
    "\\c{c}": "ç", "\\c{C}": "Ç",
}


def normalize_year(raw):
    if not raw:
        return ""
    m = YEAR_SUFFIX_RE.match(raw.strip())
    if m:
        return m.group(1) + m.group(2)
    return raw.strip()


def decode_tex_accents(s):
    if not s:
        return s
    for tex, ch in TEX_ACCENTS_PRECOMPOSED.items():
        s = s.replace(tex, ch)
    return s


def strip_braces(s):
    if not s:
        return s
    prev = None
    cur = s
    while prev != cur:
        prev = cur
        cur = re.sub(r"\{([^{}]*)\}", r"\1", cur)
    return cur


def normalize_authors(raw):
    if not raw:
        return []
    raw = decode_tex_accents(raw)
    raw = strip_braces(raw)
    # Split on " and " only when NOT preceded by a comma.
    # Corporate names like "X, Y, and Z" use ", and " internally;
    # BibTeX author separators use " and " not preceded by a comma.
    parts = re.split(r"(?<!,) and ", raw)
    parts = [p.strip() for p in parts if p.strip()]
    return parts


def entry_to_record(entry):
    etype = entry.get("ENTRYTYPE", "misc")
    filtered = {k: v for k, v in entry.items() if k in FIELD_WHITELIST}
    title_raw = filtered.get("title", "").strip() or None
    if title_raw:
        title = strip_braces(decode_tex_accents(title_raw))
    else:
        title = None
    return {
        "entry_key": entry.get("ID", ""),
        "authors": normalize_authors(filtered.get("author", "")),
        "year": normalize_year(filtered.get("year", "")),
        "title": title,
        "doi": filtered.get("doi", "").strip() or None,
        "venue": (filtered.get("journal") or filtered.get("booktitle") or "").strip() or None,
        "type": etype,
    }


def make_parser():
    p = BibTexParser(common_strings=True)
    p.ignore_nonstandard_types = False
    return p


def main():
    if len(sys.argv) != 2:
        print(json.dumps({"error": "usage: parse_bibtex.py <path.bib>"}), file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    if not os.path.isfile(path):
        print(json.dumps({"error": f"file not found: {path}"}), file=sys.stderr)
        sys.exit(2)
    # Explicit UTF-8 with BOM-stripping. `utf-8-sig` strips an optional BOM
    # (Zotero/Mendeley exports include one; plain `utf-8` would leave it and
    # corrupt the first entry key). Per CCG-on-plan A1 (Gemini).
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        text = f.read()

    db = None
    try:
        db = bibtexparser.loads(text, parser=make_parser())
    except Exception as e:
        # Emit line number context if available in the exception message.
        line_hint = ""
        m = re.search(r"line (\d+)", str(e))
        if m:
            line_hint = f" (line {m.group(1)})"
        print(json.dumps({"error": f"bibtex_entry_malformed{line_hint}", "detail": str(e)[:200]}),
              file=sys.stderr)
        db = None

    if db is None:
        # Minimal recovery: regex-split entries, parse each individually, skip failures.
        chunks = re.split(r"(?=^@[a-zA-Z]+\s*\{)", text, flags=re.MULTILINE)
        recovered = []
        start_line = 1
        for chunk in chunks:
            if not chunk.strip().startswith("@"):
                start_line += chunk.count("\n")
                continue
            try:
                sub_db = bibtexparser.loads(chunk, parser=make_parser())
                recovered.extend(sub_db.entries)
            except Exception as sub_e:
                print(
                    json.dumps(
                        {
                            "error": "bibtex_entry_malformed",
                            "line": start_line,
                            "detail": str(sub_e)[:200],
                        }
                    ),
                    file=sys.stderr,
                )
            start_line += chunk.count("\n")

        class FakeDB:
            entries = recovered
        db = FakeDB()

    # DoS cap: refuse to process more than MAX_ENTRIES entries.
    total = len(db.entries)
    records = [entry_to_record(e) for e in db.entries[:MAX_ENTRIES]]
    if total > MAX_ENTRIES:
        print(
            json.dumps(
                {"warning": "entry_count_capped", "total": total, "kept": MAX_ENTRIES}
            ),
            file=sys.stderr,
        )

    json.dump(records, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
