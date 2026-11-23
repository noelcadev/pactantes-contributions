import shutil
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from import_dort import TOOLS, import_database


class DortImportTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.database = Path(directory.name) / "corpus.db"
        shutil.copyfile(TOOLS.parent / "assets/db/reformed_documents.db", self.database)

    def test_rebuild_preserves_other_books_and_reproduces_the_shipped_text(self):
        with closing(sqlite3.connect(self.database)) as db:
            def snapshot():
                return [
                    db.execute(query).fetchall() for query in (
                        "SELECT * FROM document_sources ORDER BY document_key",
                        "SELECT * FROM heidelberg_catechism ORDER BY id",
                        "SELECT * FROM dort_units ORDER BY id",
                        "SELECT docid, * FROM dort_search ORDER BY docid",
                    )
                ]
            before = snapshot()
            import_database(self.database)
            self.assertEqual(snapshot(), before)
            self.assertEqual(len(before[2]), 188)

    def test_failed_rebuild_rolls_back_content_and_index(self):
        with closing(sqlite3.connect(self.database)) as db:
            before = db.execute("SELECT count(*), sum(length(body)) FROM dort_units").fetchone()
            db.execute("""CREATE TRIGGER interrupt_import BEFORE INSERT ON dort_units
                WHEN NEW.unit_id = '2-article-1'
                BEGIN SELECT RAISE(ABORT, 'interrupted'); END""")
            db.commit()
            with self.assertRaisesRegex(sqlite3.IntegrityError, "interrupted"):
                import_database(self.database)
            self.assertEqual(
                db.execute("SELECT count(*), sum(length(body)) FROM dort_units").fetchone(), before
            )
            self.assertEqual(db.execute("SELECT count(*) FROM dort_search").fetchone()[0], before[0])


if __name__ == "__main__":
    unittest.main()
