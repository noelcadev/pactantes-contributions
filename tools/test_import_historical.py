import hashlib
import json
import shutil
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from import_historical import CONTENT, TOOLS, import_database


class HistoricalImportTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.database = Path(directory.name) / "readings.db"
        shutil.copyfile(TOOLS.parent / "assets/db/reformed_documents.db", self.database)

    def test_bundled_editions_match_transcriptions_and_rebuild_without_changing_other_texts(self):
        with closing(sqlite3.connect(self.database)) as db:
            def snapshot():
                return [db.execute(query).fetchall() for query in (
                    "SELECT * FROM document_sources ORDER BY document_key",
                    "SELECT * FROM heidelberg_catechism ORDER BY id",
                    "SELECT * FROM dort_units ORDER BY id",
                    "SELECT * FROM historical_units ORDER BY id",
                    "SELECT * FROM historical_unit_aliases ORDER BY document_key, alias_id",
                    "SELECT * FROM historical_facsimile_ranges ORDER BY document_key, unit_id",
                    "SELECT docid, * FROM historical_search ORDER BY docid",
                )]
            before = snapshot()
            import_database(self.database)
            self.assertEqual(snapshot(), before)
            for edition in json.loads((CONTENT / "editions.json").read_text()):
                groups = json.loads((CONTENT / edition["text"]).read_text())["groups"]
                expected = [(g["id"], g["title"], u["id"], u["title"], u["body"],
                             "\n".join(u.get("references", [])), "\n\n".join(u.get("notes", []))) for g in groups for u in g["units"]]
                rows = db.execute("""
                    SELECT u.group_id, g.title, u.unit_id, u.title, u.body, u.reference_text, u.edition_notes
                    FROM historical_units u JOIN historical_groups g USING (document_key, group_id)
                    WHERE u.document_key = ? ORDER BY u.position
                    """, (edition["document_key"],)).fetchall()
                self.assertEqual(rows, expected)
                hit = db.execute("""
                    SELECT u.unit_id FROM historical_search f JOIN historical_units u ON u.id=f.docid
                    WHERE historical_search MATCH ? AND u.document_key = ? LIMIT 1
                    """, ({'en': 'God', 'es': 'Dios', 'pt': 'Deus'}[edition['language_code']], edition['document_key'])).fetchone()
                self.assertIsNotNone(hit, edition["document_key"])

    def test_local_source_manifests_match_offline_credits(self):
        with closing(sqlite3.connect(self.database)) as db:
            filename, digest, credit, url = db.execute("""
                SELECT source_filename, source_sha256, attribution, source_url
                FROM document_sources WHERE document_key = 'augustine_confessions_pt'
                """).fetchone()
            manifest = (CONTENT / filename).read_bytes()
            self.assertEqual(hashlib.sha256(manifest).hexdigest(), digest)
            books = json.loads(manifest)
            self.assertEqual([record["id"] for record in books],
                             [f"book-{i}" for i in range(1, 14)])
            for book in books:
                self.assertTrue(book["url"].startswith(url))
                self.assertRegex(book["sha256"], r"^[0-9a-f]{64}$")
            self.assertIn("Une Sacra (unesacra.com)", credit)
            self.assertIn("https://creativecommons.org/licenses/by-nc-sa/4.0/", credit)
            for key, digest, credit in (
                ("westminster_confession_es", "0435c8bda4149fdafeba59f228024eb6412868d3cc85a82a83777c2c7a93c01b", "Confraternidad Latinoamericana"),
                ("belgic_confession_es", "ac60c059f2c43f6ba3e9ba7de79106ce7282f9584fe5bb06d13a34b0314c52df", "Reformed Church in America"),
                ("scots_confession_es", "daeac69347b2374db056e9a2d133fdfca56c58554e5985fc0994281e16e28c8c", "HombreReformado.org"),
                ("scots_confession_pt", "b5c869743add94d85b7879da49a520d87c55c234441c6119a511d26be74d8b0c", "Franklin Ferreira"),
                ("augustine_confessions_es", "e9099bdecc37a6bb19f3db1eb8cb956f01d1e98aa8fa1a4822f0b4456986e01b", "Alfredo Encuentra Ortega"),
            ):
                found = db.execute("SELECT source_sha256, attribution FROM document_sources WHERE document_key = ?", (key,)).fetchone()
                self.assertEqual(found[0], digest)
                self.assertIn(credit, found[1])

    def test_augustine_alignment_and_original_pages(self):
        with closing(sqlite3.connect(self.database)) as db:
            for language, count in (("es", 461), ("en", 453), ("pt", 453)):
                key = f"augustine_confessions_{language}"
                self.assertEqual(db.execute("SELECT COUNT(*) FROM historical_unit_aliases WHERE document_key = ?",
                                            (key,)).fetchone()[0], count)
            ranges = db.execute("SELECT asset_directory, first_page, last_page FROM historical_facsimile_ranges").fetchall()
            self.assertEqual(len(ranges), 453)
            assets = {TOOLS.parent / directory / f"{page}.png"
                      for directory, first, last in ranges for page in range(first, last + 1)}
            self.assertEqual(len(assets), 542)
            self.assertEqual(assets, set((TOOLS.parent / ranges[0][0]).glob("*.png")))
            for asset in assets:
                with asset.open("rb") as image:
                    self.assertEqual(image.read(8), b"\x89PNG\r\n\x1a\n")

    def test_interrupted_import_keeps_previous_corpus_and_index(self):
        with closing(sqlite3.connect(self.database)) as db:
            before = db.execute("SELECT docid, * FROM historical_search ORDER BY docid").fetchall()
            db.execute("""CREATE TRIGGER stop_import BEFORE INSERT ON historical_units
                WHEN NEW.position = 2 BEGIN SELECT RAISE(ABORT, 'interrupted'); END""")
            db.commit()
            with self.assertRaisesRegex(sqlite3.IntegrityError, "interrupted"):
                import_database(self.database)
            self.assertEqual(db.execute("SELECT docid, * FROM historical_search ORDER BY docid").fetchall(), before)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM historical_units").fetchone()[0], len(before))
