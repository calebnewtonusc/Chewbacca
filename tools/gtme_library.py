#!/usr/bin/env python3
"""Index and search a private GTME source corpus without network access."""

import argparse
from collections import Counter
from contextlib import closing
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile


INDEX_NAME = "gtme-library.sqlite3"


def load_sources(corpus):
    manifests = sorted(corpus.rglob("fetch-inventory.json"))
    if not manifests:
        raise ValueError("No fetch-inventory.json found in the corpus")
    sources = {}
    for manifest in manifests:
        records = json.loads(manifest.read_text(encoding="utf-8"))
        if not isinstance(records, list):
            raise ValueError("Fetch inventory must be a JSON array")
        for record in records:
            if not isinstance(record, dict) or not isinstance(record.get("url"), str):
                raise ValueError("Every source must have a URL")
            source = dict(record)
            source["manifest"] = str(manifest.relative_to(corpus))
            source["content"] = ""
            source["content_status"] = "missing"
            for key in ("article_text_path", "text_path"):
                relative = record.get(key)
                if not relative:
                    continue
                candidate = (manifest.parent / relative).resolve()
                if not candidate.is_relative_to(corpus.resolve()):
                    raise ValueError("Source content path escapes the corpus")
                if candidate.is_file():
                    source["content"] = candidate.read_text(encoding="utf-8")
                    source["content_status"] = "present" if source["content"].strip() else "empty"
                    if source["content_status"] == "present":
                        break
            source["reading_status"] = record.get("reading_status", "not_recorded")
            source["fetch_status"] = record.get("status", "not_recorded")
            source["title"] = record.get("title") or record["url"].rstrip("/").rsplit("/", 1)[-1].replace("-", " ")
            sources[source["url"]] = source
    return list(sources.values())


def coverage(corpus):
    sources = load_sources(corpus)
    discovered = set(source["url"] for source in sources)
    for manifest in corpus.rglob("url-inventory.json"):
        records = json.loads(manifest.read_text(encoding="utf-8"))
        if not isinstance(records, list):
            raise ValueError("URL inventory must be a JSON array")
        discovered.update(record["url"] for record in records)
    return {
        "discovered_urls": len(discovered),
        "fetch_records": len(sources),
        "fetch_status_counts": dict(Counter(source["fetch_status"] for source in sources)),
        "reading_status_counts": dict(Counter(source["reading_status"] for source in sources)),
        "content_status_counts": dict(Counter(source["content_status"] for source in sources)),
        "failures": [{"url": source["url"], "error": source.get("error", "fetch_failed")}
                     for source in sources if source["fetch_status"] == "fetch_failed"],
        "missing_content": [source["url"] for source in sources
                            if source["content_status"] != "present" and source["fetch_status"] != "fetch_failed"],
        "note": "Fetching and indexing do not establish reading, comprehension, or successful execution.",
    }


def build_index(corpus):
    sources = load_sources(corpus)
    handle, temporary = tempfile.mkstemp(prefix=".gtme-library-", suffix=".sqlite3", dir=corpus)
    os.close(handle)
    try:
        with closing(sqlite3.connect(temporary)) as connection:
            with connection:
                connection.execute("CREATE VIRTUAL TABLE documents USING fts5(url UNINDEXED, title, content, fetch_status UNINDEXED, reading_status UNINDEXED, fetched_at UNINDEXED, manifest UNINDEXED)")
                for source in sources:
                    if source["content_status"] != "present" or source["fetch_status"] == "fetch_failed":
                        continue
                    connection.execute("INSERT INTO documents VALUES (?, ?, ?, ?, ?, ?, ?)", (
                        source["url"], source["title"], source["content"], source["fetch_status"],
                        source["reading_status"], source.get("fetched_at", ""), source["manifest"],
                    ))
                count = connection.execute("SELECT count(*) FROM documents").fetchone()[0]
        os.replace(temporary, corpus / INDEX_NAME)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return {"indexed_documents": count, "index": str(corpus / INDEX_NAME),
            "note": "Regenerable private index; source reading status was preserved."}


def search(corpus, query, limit=10):
    if limit < 1 or limit > 100:
        raise ValueError("Limit must be between 1 and 100")
    tokens = re.findall(r"\w+", query, flags=re.UNICODE)
    if not tokens:
        return []
    expression = " AND ".join('"' + token.replace('"', '""') + '"' for token in tokens)
    index = corpus / INDEX_NAME
    if not index.is_file():
        raise ValueError("No local index; run gtme-library --corpus PATH index first")
    connection = sqlite3.connect(index.resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            "SELECT url, title, snippet(documents, 2, '[', ']', ' … ', 32) AS snippet, "
            "fetch_status, reading_status, fetched_at, manifest FROM documents "
            "WHERE documents MATCH ? ORDER BY bm25(documents) LIMIT ?", (expression, limit))
        return [dict(row) for row in rows]
    finally:
        connection.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path(os.environ.get(
        "GTME_CORPUS_DIR", str(Path.home() / ".chewbacca" / "gtme-corpus"))),
        help="Private corpus root (default: GTME_CORPUS_DIR or ~/.chewbacca/gtme-corpus)")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("index", help="Rebuild the private SQLite FTS5 index")
    commands.add_parser("coverage", help="Read source coverage and failures without writing")
    find = commands.add_parser("search", help="Search indexed source text; punctuation is literal")
    find.add_argument("query")
    find.add_argument("--limit", type=int, default=10)
    args = parser.parse_args(argv)
    corpus = args.corpus.expanduser().resolve()
    try:
        if not corpus.is_dir():
            raise ValueError("Corpus directory does not exist")
        if args.command == "index":
            result = build_index(corpus)
        elif args.command == "coverage":
            result = coverage(corpus)
        else:
            result = search(corpus, args.query, args.limit)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (ValueError, OSError, sqlite3.Error, KeyError, TypeError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
