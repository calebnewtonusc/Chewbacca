#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pypdf>=5", "markitdown[pdf]>=0.1"]
# ///
"""Turn a textbook PDF into a searchable chapter corpus.

    ingest.py scan  book.pdf                    the chapter plan, writes nothing
    ingest.py apply book.pdf --out DIR          writes exactly what scan showed

scan and apply are separate because the chapter split comes from the PDF's own
bookmark outline, and an outline can be wrong or absent. Read the plan before
507 pages get filed under the wrong headings.

Extraction is pdfminer by way of markitdown, not `pdftotext`. On a Pressbooks
PDF with figures in the margin, pdftotext interleaves caption lines into the
body mid-word: "the emerging anthropological prac-" / "Figure 2. An
illustration of..." / "tices of this time". pdfminer keeps reading order and
pushes captions to the end of the page.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tempfile
from collections import Counter
from pathlib import Path

from markitdown import MarkItDown
from pypdf import PdfReader, PdfWriter

# A heading line in a Pressbooks export is set in caps with no terminal period.
# Longer than this and it is a caps-locked sentence in the body, not a heading.
MAX_HEADING = 64

# A running head has to appear beside a page number this many times before the
# cleaner will drop it. Two is too few: a chapter epigraph set in caps can sit
# next to a page number twice by coincidence, and dropping it loses real text.
HEAD_REPEATS = 3

BULLET_ONLY = re.compile(r"[\u2022\u25aa\u25e6\u00b7*\-\u2013\u2014\s]+")

CAPTION = re.compile(r"^(Figure|Table|Map|Plate)\s+\d+[.:]", re.I)


def slugify(text: str) -> str:
    text = re.sub(r"[^\w\s-]", "", text.lower())
    return re.sub(r"[\s_-]+", "-", text).strip("-")[:60]


def outline_entries(reader: PdfReader) -> list[dict]:
    """Flatten the PDF outline, keeping the nesting depth and page spans.

    Depth is what separates a chapter from the rest. In a Pressbooks export the
    top level holds Contents, Preface, the "Part N" dividers and Image Credits,
    and the numbered chapters sit one level under a Part. Flattening the tree
    and numbering what falls out gave Perspectives a "chapter 3. Introduction
    to Anthropology", which is the book's chapter 1: the course assigns work by
    chapter number, so that error points every reading at the wrong text.
    """
    found: list[tuple[str, int, int]] = []

    def walk(items, depth=0):
        for item in items:
            if isinstance(item, list):
                walk(item, depth + 1)
                continue
            try:
                page = reader.get_destination_page_number(item)
            except Exception:
                continue
            found.append((str(item.title).strip(), page + 1, depth))

    walk(reader.outline)
    found.sort(key=lambda entry: entry[1])

    entries = []
    for index, (title, start, depth) in enumerate(found):
        end = found[index + 1][1] - 1 if index + 1 < len(found) else len(reader.pages)
        entries.append({"title": title, "start": start, "end": max(start, end), "depth": depth})
    return entries


SKIP_TITLES = re.compile(r"^(contents|table of contents|part\s+\w+|section\s+\w+)$", re.I)


def classify(entries: list[dict]) -> list[dict]:
    """Number the chapters, keep front and back matter unnumbered, drop dividers."""
    kept = []
    number = 0
    for entry in entries:
        if SKIP_TITLES.fullmatch(entry["title"]):
            continue
        if entry["depth"] > 0:
            number += 1
            entry["number"] = number
            entry["slug"] = f"{number:02d}-{slugify(entry['title'])}"
        else:
            entry["number"] = None
            prefix = "front" if not kept or all(e["number"] is None for e in kept) else "back"
            entry["slug"] = f"{prefix}-{slugify(entry['title'])}"
        kept.append(entry)
    return kept


def plan(pdf: Path) -> tuple[dict, list[dict]]:
    reader = PdfReader(str(pdf))
    meta = reader.metadata or {}
    book = {
        "title": (meta.get("/Title") or pdf.stem).strip(),
        "pages": len(reader.pages),
        "source_pdf": pdf.name,
        "sha256": hashlib.sha256(pdf.read_bytes()).hexdigest(),
    }
    return book, classify(outline_entries(reader))


# Front matter is paginated in roman numerals and the body in arabic, so a page
# label is either. Recognising only digits left "xii PERSPECTIVES: AN OPEN
# INTRODUCTION TO CULTURAL ANTHROPOLOGY" in the preface as a spurious heading.
PAGE_LABEL = re.compile(r"[0-9]{1,4}|[ivxlcdm]{1,7}", re.I)


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.casefold())


def same_title(a: str, b: str) -> bool:
    """True for "Perspectives: ..." against "Perspectives: ..., 2nd Edition"."""
    na, nb = normalize(a), normalize(b)
    return bool(na and nb) and (na.startswith(nb) or nb.startswith(na))


def without_page_label(bare: str) -> list[tuple[str, str]]:
    """The line minus a page label at either end, as (label, rest) pairs."""
    tokens = bare.split()
    if len(tokens) < 2:
        return []
    out = []
    if PAGE_LABEL.fullmatch(tokens[0]):
        out.append((tokens[0], " ".join(tokens[1:])))
    if PAGE_LABEL.fullmatch(tokens[-1]):
        out.append((tokens[-1], " ".join(tokens[:-1])))
    return out


def running_heads(lines: list[str], titles: tuple[str, ...]) -> set[str]:
    """Strings sitting beside a page label on many pages, whatever they say.

    Matching the book title alone was not enough: the running head reads
    "PERSPECTIVES: AN OPEN INTRODUCTION TO CULTURAL ANTHROPOLOGY" while the PDF
    metadata title ends ", 2nd Edition", so every verso head survived into the
    corpus as a spurious `## ` heading. Counting repeats needs no such match.
    """
    counts = Counter()
    for line in lines:
        for _, rest in without_page_label(re.sub(r"\s+", " ", line.strip())):
            if rest:
                counts[rest.casefold()] += 1
    heads = {text for text, seen in counts.items() if seen >= HEAD_REPEATS}
    heads.update(title.casefold() for title in titles)
    return heads


def clean(raw: str, book_title: str, chapter_title: str) -> str:
    """Strip running heads, undouble the text layer, reflow paragraphs.

    Printed page numbers survive as HTML comments. Every claim pulled out of
    this corpus has to be citable to a page, because the course grades on
    chapters and a passage with no page is a passage the user cannot check.
    """
    lines = raw.splitlines()
    titles = (book_title, chapter_title)
    heads = running_heads(lines, titles)

    def head_page(bare: str) -> str | None:
        """The page label printed on this line, if the line is a running head."""
        for label, rest in without_page_label(bare):
            if rest.casefold() in heads or any(same_title(rest, t) for t in titles):
                return label
        return None

    page: str | None = None
    blocks: list[tuple[str, str | None]] = []
    current: list[str] = []

    def flush():
        """Close the current block, healing a word broken across a page edge.

        A page label lands between "harms people by pre-" and "venting them",
        so the block boundary falls inside a word. Joining inside a block was
        not enough; the split has to be healed across blocks too, and the
        passage keeps the earlier page because that is where it starts.
        """
        nonlocal current
        if not current:
            return
        text = join(current)
        current = []
        if not text:
            return
        if blocks and blocks[-1][0].endswith("-") and text[:1].islower():
            previous, at_page = blocks[-1]
            blocks[-1] = (previous[:-1] + text, at_page)
            return
        blocks.append((text, page))

    for line in lines:
        bare = re.sub(r"\s+", " ", line.strip())
        if not bare:
            flush()
            continue
        # Prince draws chapter openers twice, so the chapter number arrives as
        # "1 1". Left alone it reads as page 1 and mis-cites the whole opener.
        if re.fullmatch(r"(\d{1,4}) \1", bare):
            flush()
            continue
        if PAGE_LABEL.fullmatch(bare):
            flush()
            page = bare
            continue
        label = head_page(bare)
        if label is not None:
            flush()
            page = label
            continue
        if BULLET_ONLY.fullmatch(bare):
            flush()
            continue
        # The same text layer doubling, one line lower: a two-line heading comes
        # out as A, A, B, B. Body prose never repeats a line verbatim.
        if current and current[-1] == bare:
            continue
        current.append(bare)
    flush()

    out: list[str] = []
    last_page = None
    for text, at_page in blocks:
        if not text:
            continue
        if at_page is not None and at_page != last_page:
            out.append(f"<!-- p. {at_page} -->")
            last_page = at_page
        if text.isupper() and len(text) <= MAX_HEADING and not text.endswith("."):
            out.append(f"## {text}")
        else:
            out.append(text)
    return "\n\n".join(out) + "\n"


def join(lines: list[str]) -> str:
    """Join wrapped lines, healing words the typesetter broke with a hyphen.

    "prac-" + "tices" is one word and the hyphen goes. "non-" + "European" is a
    real compound and the hyphen stays; the capital on the second half is what
    tells them apart, which is the convention Pressbooks and every other
    typesetter follows.
    """
    out = ""
    for line in lines:
        line = re.sub(r"\s+", " ", line).strip()
        if not line:
            continue
        if not out:
            out = line
        elif out.endswith("-") and not out.endswith("--"):
            out = out + line if line[:1].isupper() else out[:-1] + line
        else:
            out = f"{out} {line}"
    return out


def extract(pdf: Path, start: int, end: int, converter: MarkItDown, scratch: Path) -> str:
    reader = PdfReader(str(pdf))
    writer = PdfWriter()
    for index in range(start - 1, end):
        writer.add_page(reader.pages[index])
    slice_path = scratch / "slice.pdf"
    with slice_path.open("wb") as handle:
        writer.write(handle)
    return converter.convert(str(slice_path)).text_content


# A glossary entry is a capitalised term of a few words, a colon, then a
# sentence. Chapters 2 and 9 of Perspectives set one entry per paragraph and
# chapters 6 and 11 run them all together, so the terms have to be recovered
# from the punctuation rather than from the line breaks.
GLOSS_SPLIT = re.compile(r"(?<=\.)\s+(?=[A-Z][\w\u2019'-]*(?:[ -][\w\u2019'-]+){0,4}:\s)")


def glossary_of(text: str) -> list[str]:
    """Pull the chapter's GLOSSARY section, which runs until the next heading."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "## GLOSSARY")
    except StopIteration:
        return []
    entries = []
    for line in lines[start + 1 :]:
        if line.startswith("## "):
            break
        line = line.strip()
        if line and not line.startswith("<!--"):
            entries.extend(part for part in GLOSS_SPLIT.split(line) if part)
    return entries


def apply(pdf: Path, out: Path, book: dict, chapters: list[dict]) -> None:
    converter = MarkItDown()
    chapters_dir = out / "chapters"
    chapters_dir.mkdir(parents=True, exist_ok=True)
    glossary: list[tuple[int, str, str]] = []

    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp)
        for chapter in chapters:
            raw = extract(pdf, chapter["start"], chapter["end"], converter, scratch)
            body = clean(raw, book["title"], chapter["title"])
            chapter["words"] = len(body.split())
            front = (
                "---\n"
                f"book: {json.dumps(book['title'])}\n"
                + (f"chapter: {chapter['number']}\n" if chapter["number"] else "")
                + f"title: {json.dumps(chapter['title'])}\n"
                f"pdf_pages: {chapter['start']}-{chapter['end']}\n"
                f"words: {chapter['words']}\n"
                "---\n\n"
            )
            path = chapters_dir / f"{chapter['slug']}.md"
            path.write_text(front + f"# {chapter['title']}\n\n" + body, encoding="utf-8")
            if chapter["number"]:
                for entry in glossary_of(body):
                    glossary.append((chapter["number"], chapter["title"], entry))
            label = f"{chapter['number']:>2}." if chapter["number"] else "  -"
            print(f"  {label} {chapter['title'][:52]:<52} {chapter['words']:>6} words")

    book["chapters"] = [
        {k: c[k] for k in ("number", "title", "slug", "start", "end", "words")}
        for c in chapters
    ]
    (out / "book.json").write_text(json.dumps(book, indent=2) + "\n", encoding="utf-8")

    lines = [f"# Glossary: {book['title']}", "", f"{len(glossary)} entries, chapter order.", ""]
    current = None
    for number, title, entry in glossary:
        if number != current:
            lines += [f"## {number}. {title}", ""]
            current = number
        lines += [f"- {entry}", ""]
    (out / "GLOSSARY.md").write_text("\n".join(lines), encoding="utf-8")

    index = [
        f"# {book['title']}",
        "",
        f"{len(chapters)} chapters, {sum(c['words'] for c in chapters):,} words, "
        f"from `{book['source_pdf']}` ({book['pages']} pages).",
        "",
        "| # | Chapter | PDF pages | Words |",
        "| --- | --- | --- | --- |",
    ]
    for chapter in chapters:
        index.append(
            f"| {chapter['number'] or ''} | [{chapter['title']}](chapters/{chapter['slug']}.md) "
            f"| {chapter['start']}-{chapter['end']} | {chapter['words']:,} |"
        )
    (out / "INDEX.md").write_text("\n".join(index) + "\n", encoding="utf-8")


def verify(out: Path, book: dict, chapters: list[dict]) -> int:
    """Check the written corpus against the PDF it came from.

    Every defect checked here was shipped at least once during the first
    ingest: front matter numbered as chapters, running heads left in as
    headings, a doubled text layer, and glossary entries fused into one
    paragraph. A checklist in prose did not catch any of them twice.
    """
    problems: list[str] = []
    written = sorted((out / "chapters").glob("*.md"))
    if len(written) != len(chapters):
        problems.append(f"{len(chapters)} chapters planned, {len(written)} files on disk")

    # Pages before chapter 1 and after the last one are the cover, the table of
    # contents and the part dividers, all deliberately skipped. A gap *between*
    # two chapters is the real failure: it means the outline lost a chapter and
    # the reading assigned for it is not in the corpus at all.
    body = [c for c in chapters if c["number"]]
    for earlier, later in zip(body, body[1:]):
        gap = later["start"] - earlier["end"] - 1
        if gap > 2:
            problems.append(
                f"{gap} PDF pages between chapter {earlier['number']} and "
                f"{later['number']} belong to no chapter"
            )

    title_words = set(normalize(book["title"]).split())
    for path in written:
        text = path.read_text()
        for number, line in enumerate(text.splitlines(), 1):
            if not line.startswith("## "):
                continue
            heading = line[3:]
            if same_title(heading, book["title"]):
                problems.append(f"{path.name}:{number} running head kept as a heading")
            tokens = heading.split()
            half = len(tokens) // 2
            if tokens and len(tokens) % 2 == 0 and tokens[:half] == tokens[half:]:
                problems.append(f"{path.name}:{number} doubled heading: {heading[:40]}")
        if "## GLOSSARY" in text and not glossary_of(text):
            problems.append(f"{path.name} has a GLOSSARY heading and no entries")

    entries = (out / "GLOSSARY.md").read_text().count("\n- ")
    if entries < len(chapters):
        problems.append(f"only {entries} glossary entries across {len(chapters)} chapters")

    for problem in problems:
        print(f"  ! {problem}")
    print(f"\n{len(problems)} problem(s); {len(written)} files, {entries} glossary entries")
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("scan", "apply", "verify"):
        p = sub.add_parser(name)
        p.add_argument("pdf", type=Path)
        if name != "scan":
            p.add_argument("--out", type=Path, required=True)
        if name == "apply":
            p.add_argument("--keep-pdf", action="store_true", help="copy the source PDF into the corpus")
    args = parser.parse_args()

    if not args.pdf.exists():
        print(f"no such file: {args.pdf}", file=sys.stderr)
        return 1

    book, chapters = plan(args.pdf)
    numbered = sum(1 for c in chapters if c["number"])
    print(
        f"{book['title']}\n{book['pages']} pages, {numbered} chapters, "
        f"{len(chapters) - numbered} front/back matter\n"
    )

    if args.command == "scan":
        for chapter in chapters:
            span = f"{chapter['start']}-{chapter['end']}"
            label = f"{chapter['number']:>2}." if chapter["number"] else "  -"
            print(f"  {label} {span:>9}  {chapter['slug']}")
        print("\nNothing written. Re-run with `apply --out DIR` to write this plan.")
        return 0

    if args.command == "verify":
        return verify(args.out, book, chapters)

    print(f"writing {args.out}")
    apply(args.pdf, args.out, book, chapters)
    if args.keep_pdf:
        shutil.copy2(args.pdf, args.out / book["source_pdf"])
    print(f"\ndone: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
