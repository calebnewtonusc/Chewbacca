import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("gtme_library", Path(__file__).resolve().parents[1] / "tools" / "gtme_library.py")
library = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(library)


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.corpus = self.root / "corpus"
        self.official = self.corpus / "official"
        self.official.mkdir(parents=True)
        (self.official / "sample.txt").write_text("CSV imports need auto-run disabled. Validate company identity before email enrichment.")
        self.records = [
            {"url": "https://example.test/csv-import", "title": "CSV import", "text_path": "sample.txt", "status": "fetched_not_read", "reading_status": "fetched_not_read"},
            {"url": "https://example.test/broken", "status": "fetch_failed", "error": "HTTP 404"},
            {"url": "https://example.test/missing", "status": "fetched_not_read", "text_path": "missing.txt"},
        ]
        self.save()

    def save(self):
        (self.official / "fetch-inventory.json").write_text(json.dumps(self.records))

    def test_search_preserves_provenance_and_does_not_claim_read(self):
        result = library.build_index(self.corpus)
        self.assertEqual(result["indexed_documents"], 1)
        matches = library.search(self.corpus, '"auto-run"?')
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0]["url"], self.records[0]["url"])
        self.assertEqual(matches[0]["title"], "CSV import")
        self.assertEqual(matches[0]["reading_status"], "fetched_not_read")
        self.assertIn("disabled", matches[0]["snippet"])
        self.assertEqual(json.loads((self.official / "fetch-inventory.json").read_text()), self.records)

    def test_coverage_distinguishes_failure_missing_and_undownloaded(self):
        (self.official / "url-inventory.json").write_text(json.dumps(self.records + [{"url": "https://example.test/unfetched"}]))
        report = library.coverage(self.corpus)
        self.assertEqual(report["discovered_urls"], 4)
        self.assertEqual(report["fetch_records"], 3)
        self.assertEqual(report["fetch_status_counts"]["fetch_failed"], 1)
        self.assertEqual(report["missing_content"], ["https://example.test/missing"])
        self.assertEqual(report["reading_status_counts"]["not_recorded"], 2)
        self.assertFalse((self.corpus / library.INDEX_NAME).exists())

    def test_query_syntax_cannot_inject_fts_operators(self):
        library.build_index(self.corpus)
        for query in ['*', '" OR *', 'title:csv NOT "', "'); DROP TABLE documents; --"]:
            self.assertIsInstance(library.search(self.corpus, query), list)
        self.assertEqual(len(library.search(self.corpus, "CSV")), 1)

    def test_rebuild_removes_stale_content(self):
        library.build_index(self.corpus)
        (self.official / "sample.txt").write_text("Different subject")
        library.build_index(self.corpus)
        self.assertEqual(library.search(self.corpus, "CSV imports"), [])

    def test_manifest_cannot_read_outside_corpus(self):
        (self.root / "outside.txt").write_text("not source material")
        self.records[0]["text_path"] = "../../outside.txt"
        self.save()
        with self.assertRaisesRegex(ValueError, "escapes"):
            library.build_index(self.corpus)

    def test_search_does_not_create_missing_index(self):
        with self.assertRaisesRegex(ValueError, "No local index"):
            library.search(self.corpus, "CSV")
        self.assertFalse((self.corpus / library.INDEX_NAME).exists())

    def test_explicit_read_status_is_retained(self):
        self.records[0]["reading_status"] = "core_text_read"
        self.save()
        library.build_index(self.corpus)
        self.assertEqual(library.search(self.corpus, "CSV")[0]["reading_status"], "core_text_read")


if __name__ == "__main__":
    unittest.main()
