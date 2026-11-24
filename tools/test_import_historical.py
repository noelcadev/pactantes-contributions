import hashlib
import json
import shutil
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from import_historical import CONTENT, TOOLS, import_database, validate_lettered_references


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
                    "SELECT docid, * FROM historical_search ORDER BY docid",
                )]
            before = snapshot()
            import_database(self.database)
            self.assertEqual(snapshot(), before)
            for edition in json.loads((CONTENT / "editions.json").read_text()):
                groups = json.loads((CONTENT / edition["text"]).read_text())["groups"]
                expected = [(g["id"], g["title"], u["id"], u["title"], u.get("question"), u["body"],
                             "\n".join(u.get("references", [])), "\n\n".join(u.get("notes", []))) for g in groups for u in g["units"]]
                rows = db.execute("""
                    SELECT u.group_id, g.title, u.unit_id, u.title, u.question, u.body, u.reference_text, u.edition_notes
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
                ("westminster_larger_catechism_es", "447e82eefaf569e0a017c05a72ad69df02a60a1f081445ca2d926c87d27eff8e", "Asamblea de Westminster"),
                ("westminster_larger_catechism_en", "35ee21073cdc6eac9831a69b32ba48a7dd2bf8c02185317df421c69966603b33", "Ian Buchanan"),
                ("westminster_larger_catechism_pt", "99097e8fe0884ecdd3c869bd1c23954d43df0b40f49a9918bb2111e3e071dcbf", "João Ferreira de Medeiros"),
                ("nicene_creed_es", "78df0f13cd80c9f7c0bdc7cb8ccfc47c2b9d06472f167cedb4d010e5965d7247", "La Biblia de Estudio de La Reforma"),
                ("nicene_creed_en", "7e48e836b4b9f052d523b42bfa51b5f25b2978175dc9423ab3ccdec2710c9145", "General Convention"),
                ("nicene_creed_pt", "4489d8753c974c496ef0b04f0b55f7370c9b4937ea96472677c91885aa042397", "Fraga Lamares"),
            ):
                found = db.execute("SELECT source_sha256, attribution FROM document_sources WHERE document_key = ?", (key,)).fetchone()
                self.assertEqual(found[0], digest)
                self.assertIn(credit, found[1])

    def test_augustine_alignment_and_source_pagination(self):
        with closing(sqlite3.connect(self.database)) as db:
            for language, count in (("es", 461), ("en", 453), ("pt", 453)):
                key = f"augustine_confessions_{language}"
                self.assertEqual(db.execute("SELECT COUNT(*) FROM historical_unit_aliases WHERE document_key = ?",
                                            (key,)).fetchone()[0], count)
        source = json.loads((CONTENT / "augustine-es.json").read_text())
        pages = [unit["source_pages"] for group in source["groups"] for unit in group["units"]]
        self.assertEqual(len(pages), 453)
        self.assertEqual(pages[0][0], 111)
        self.assertEqual(pages[-1][-1], 670)

    def test_import_removes_obsolete_page_index_and_updates_title(self):
        with closing(sqlite3.connect(self.database)) as db:
            def legacy_page_index():
                return db.execute("""
                    SELECT name FROM sqlite_master WHERE name = 'historical_facsimile_ranges'
                    """).fetchone()

            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], 7)
            self.assertIsNone(legacy_page_index())
            db.execute("""
                CREATE TABLE historical_facsimile_ranges (
                    document_key TEXT NOT NULL,
                    unit_id TEXT NOT NULL,
                    first_page INTEGER NOT NULL,
                    last_page INTEGER NOT NULL,
                    asset_directory TEXT NOT NULL,
                    PRIMARY KEY(document_key, unit_id),
                    FOREIGN KEY(document_key, unit_id) REFERENCES historical_units(document_key, unit_id)
                )
                """)
            db.execute("""
                INSERT INTO historical_facsimile_ranges VALUES
                    ('augustine_confessions_es', 'book-1-paragraph-1', 111, 113, 'legacy-pages')
                """)
            db.execute("""
                UPDATE document_sources SET title = 'Confesiones'
                WHERE document_key = 'augustine_confessions_es'
                """)
            db.execute("PRAGMA user_version = 5")
            db.commit()
            import_database(self.database)
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], 7)
            self.assertIsNone(legacy_page_index())
            self.assertEqual(db.execute("""
                SELECT title FROM document_sources WHERE document_key = 'augustine_confessions_es'
                """).fetchone()[0], "Confesiones de san Agustín")

    def test_previous_schema_gains_searchable_questions_and_the_creed_note(self):
        with closing(sqlite3.connect(self.database)) as db:
            db.execute("ALTER TABLE historical_units DROP COLUMN question")
            db.execute("DROP TABLE historical_search")
            db.execute("""CREATE VIRTUAL TABLE historical_search USING fts4(
                group_title, title, body, reference_text, edition_notes, tokenize=unicode61)""")
            db.execute("PRAGMA user_version = 6")
            db.commit()
            import_database(self.database)

            key = "westminster_larger_catechism_es"
            rows = db.execute("""SELECT unit_id, question, body, reference_text FROM historical_units
                WHERE document_key = ? ORDER BY position""", (key,)).fetchall()
            self.assertEqual([row[0] for row in rows], [f"question-{i}" for i in range(1, 197)])
            self.assertTrue(all(question and answer for _, question, answer, _ in rows))
            self.assertEqual(rows[0][1], "¿Cuál es el fin principal y más noble del hombre?")
            self.assertIn("Rom. 11:36", rows[0][3])
            self.assertIn(("question-1",), db.execute("""
                SELECT u.unit_id FROM historical_search f JOIN historical_units u ON u.id = f.docid
                WHERE historical_search MATCH 'question:noble' AND u.document_key = ?
                """, (key,)).fetchall())
            question, body, notes = db.execute("""
                SELECT question, body, edition_notes FROM historical_units
                WHERE document_key = 'nicene_creed_es' AND unit_id = 'creed'
                """).fetchone()
            self.assertIsNone(question)
            self.assertEqual(len(body.split("\n\n")), 3)
            self.assertIn("universal*", body)
            self.assertIn("católica", notes)

    def test_larger_catechism_preserves_each_editions_scripture_apparatus(self):
        with closing(sqlite3.connect(self.database)) as db:
            def apparatus(language):
                return {position: text.splitlines() for position, text in db.execute("""
                    SELECT position, reference_text FROM historical_units
                    WHERE document_key = ? ORDER BY position
                    """, (f"westminster_larger_catechism_{language}",))}

            spanish = apparatus("es")
            self.assertEqual(sum(map(len, spanish.values())), 1305)
            self.assertEqual([n for n, refs in spanish.items() if not refs], [100, 188])
            self.assertEqual(len(spanish[113]), 38)
            self.assertEqual(spanish[2], ["c) Rom. 1:19, 20. Véase Sal. 19:1‐3;",
                                          "d) II Tim. 3:15‐17, I Cor. 2:10."])
            self.assertIn("c) Rom. 8:34.", spanish[52])
            self.assertIn("d) Heb. 2:14.", spanish[52])
            self.assertIn("Juan 16:7, 8", spanish[58][-1])
            self.assertIn("r) Sal. 127:3‐5; Prov. 31:23.", spanish[127])
            printed_transitions = db.execute("""
                SELECT position, edition_notes FROM historical_units WHERE
                document_key = 'westminster_larger_catechism_es' AND edition_notes <> ''
                ORDER BY position
                """).fetchall()
            self.assertEqual([n for n, _ in printed_transitions], [90])
            self.assertTrue(printed_transitions[0][1].startswith("Habiendo ya visto"))
            self.assertNotIn("\n\n", printed_transitions[0][1])
            english = apparatus("en")
            self.assertEqual(len(english), 196)
            self.assertFalse(any(english.values()))
            portuguese = apparatus("pt")
            self.assertEqual([n for n, refs in portuguese.items() if not refs], [100, 149, 188])
            self.assertEqual(len(portuguese[99]), 8)
            self.assertEqual(len(portuguese[151]), 4)

    def test_lettered_references_accept_declared_gaps_and_repeated_labels_in_order(self):
        unit = {"id": "question-1", "question": "¿Qué significa «(a)»? ñ)",
                "body": "1) Una respuesta. a) Otra frase. a)",
                "references": ["ñ) Sal. 1:1.", "a) Sal. 2:1.", "ll) Sal. 3:1.", "a) Sal. 4:1."],
                "unanchored_references": ["ll"]}
        validate_lettered_references(unit)
        for invalid in ({"unanchored_references": []}, {"unanchored_references": ["x"]},
                        {"body": "a) ñ) a)"}, {"body": "a)"},
                        {"references": ["ñ) Sal. 1:1.", "Sal. 2:1.", "a) Sal. 4:1."]}):
            with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, "question-1"):
                validate_lettered_references({**unit, **invalid})

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
