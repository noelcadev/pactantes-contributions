"""Rebuild the reviewed historical editions in the bundled reading database."""

import argparse
import json
import re
import sqlite3
from contextlib import closing
from pathlib import Path


TOOLS = Path(__file__).resolve().parent
CONTENT = TOOLS / "content" / "historical"


def load_edition(edition, directory):
    book = json.loads((directory / edition["text"]).read_text(encoding="utf-8"))
    groups = book["groups"]
    sizes = [len(group["units"]) for group in groups]
    if not groups or 0 in sizes or sizes != edition["group_sizes"]:
        raise ValueError(f"{edition['text']}: unexpected group or unit count")
    if not re.fullmatch(r"[0-9a-f]{64}", edition["source_sha256"]):
        raise ValueError(f"{edition['text']}: invalid source digest")
    seen_groups = set()
    seen_units = set()
    for group in groups:
        group_id = group["id"]
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", group_id) or group_id in seen_groups:
            raise ValueError(f"Invalid or duplicate group: {group_id}")
        if group["title"] is not None and not group["title"].strip():
            raise ValueError(f"Empty group title: {group_id}")
        seen_groups.add(group_id)
        for unit in group["units"]:
            unit_id = unit["id"]
            if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", unit_id) or unit_id in seen_units:
                raise ValueError(f"Invalid or duplicate unit: {unit_id}")
            seen_units.add(unit_id)
            if not unit["title"].strip() or not unit["body"].strip():
                raise ValueError(f"Empty passage: {unit_id}")
            if any(not line.strip() or "\n" in line for line in unit.get("references", [])):
                raise ValueError(f"Invalid reference lines: {unit_id}")
            if edition.get("facsimile_directory"):
                pages = unit.get("source_pages")
                if (not isinstance(pages, list) or len(pages) != 2
                        or not all(type(page) is int for page in pages)
                        or not 0 < pages[0] <= pages[1]):
                    raise ValueError(f"Invalid source pages: {unit_id}")
    return groups


def insert_edition(db, edition, groups):
    key = edition["document_key"]
    db.execute("""
        INSERT INTO document_sources (document_key, title, language_code, source_filename,
            source_sha256, attribution, source_url, content_version)
        VALUES (:document_key, :title, :language_code, :source_filename,
            :source_sha256, :attribution, :source_url, :content_version)
        """, {"content_version": 1, **edition})
    db.execute("INSERT INTO historical_editions VALUES (?, ?)", (key, edition["document_id"]))
    position = 0
    for group in groups:
        db.execute("INSERT INTO historical_groups VALUES (?, ?, ?)", (key, group["id"], group["title"]))
        for unit in group["units"]:
            position += 1
            db.execute("""
                INSERT INTO historical_units
                    (document_key, group_id, unit_id, position, title, body, reference_text, edition_notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (key, group["id"], unit["id"], position, unit["title"],
                      unit["body"], "\n".join(unit.get("references", [])), "\n\n".join(unit.get("notes", []))))
            if directory := edition.get("facsimile_directory"):
                db.execute("""
                    INSERT INTO historical_facsimile_ranges
                        (document_key, unit_id, first_page, last_page, asset_directory)
                    VALUES (?, ?, ?, ?, ?)
                    """, (key, unit["id"], *unit["source_pages"], directory))


def insert_augustine_aliases(db, edition, groups, directory):
    numbering = edition.get("augustine_numbering")
    if numbering is None:
        return
    other = {"paragraph": "section", "section": "paragraph"}[numbering]
    books = json.loads((directory / "augustine-alignment.json").read_text(encoding="utf-8"))
    if len(books) != len(groups):
        raise ValueError("Incomplete Augustine book alignment")
    for group, book in zip(groups, books):
        prefix = f"book-{book['book']}"
        units = group["units"]
        targets = book[f"{other}_to_{numbering}"]
        if (group["id"] != prefix or len(units) != len(book[f"{numbering}_to_{other}"])
                or not targets or targets != sorted(targets)
                or targets[0] != 1 or targets[-1] > len(units)):
            raise ValueError(f"Invalid Augustine alignment for {prefix}")
        for position, unit in enumerate(units, 1):
            if unit["id"] != f"{prefix}-{numbering}-{position}":
                raise ValueError(f"Unexpected unit in Augustine alignment: {unit['id']}")
        db.executemany("INSERT INTO historical_unit_aliases VALUES (?, ?, ?)", (
            (edition["document_key"], f"{prefix}-{other}-{i}", units[target - 1]["id"])
            for i, target in enumerate(targets, 1)
        ))


def import_database(database, directory=CONTENT):
    editions = json.loads((directory / "editions.json").read_text(encoding="utf-8"))
    if not editions:
        raise ValueError("No historical editions supplied")
    identities = {(edition["document_id"], edition["language_code"]) for edition in editions}
    if len(identities) != len(editions):
        raise ValueError("Duplicate historical edition")
    texts = [(edition, load_edition(edition, directory)) for edition in editions]
    with closing(sqlite3.connect(f"{database.resolve().as_uri()}?mode=rw", uri=True)) as db, db:
        db.execute("PRAGMA foreign_keys = ON")
        db.executescript("BEGIN IMMEDIATE;\n" + (TOOLS / "historical_schema.sql").read_text())
        # Only editions managed by this importer are replaced.
        old_keys = db.execute("SELECT document_key FROM historical_editions").fetchall()
        db.execute("DELETE FROM historical_search")
        db.execute("DELETE FROM historical_unit_aliases")
        db.execute("DELETE FROM historical_facsimile_ranges")
        db.execute("DELETE FROM historical_units")
        db.execute("DELETE FROM historical_groups")
        db.execute("DELETE FROM historical_editions")
        db.executemany("DELETE FROM document_sources WHERE document_key = ?", old_keys)
        for edition, groups in texts:
            insert_edition(db, edition, groups)
            insert_augustine_aliases(db, edition, groups, directory)
        db.execute("""
            INSERT INTO historical_search (docid, group_title, title, body, reference_text, edition_notes)
            SELECT u.id, g.title, u.title, u.body, u.reference_text, u.edition_notes
            FROM historical_units u JOIN historical_groups g USING (document_key, group_id)
            ORDER BY u.id
            """)
        db.execute("INSERT INTO historical_search(historical_search) VALUES ('integrity-check')")
        if db.execute("PRAGMA foreign_key_check").fetchone() or db.execute(
            "PRAGMA integrity_check"
        ).fetchall() != [("ok",)]:
            raise ValueError("Corpus integrity check failed")
        if db.execute("PRAGMA user_version").fetchone()[0] < 5:
            db.execute("PRAGMA user_version = 5")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path)
    import_database(parser.parse_args().database)
