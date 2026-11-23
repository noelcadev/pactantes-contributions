"""Rebuild the Canons of Dort from the two reviewed transcriptions."""

import argparse
import json
import sqlite3
from contextlib import closing
from pathlib import Path


TOOLS = Path(__file__).resolve().parent
EDITIONS = {
    "en": {
        "text": "scott-en.json",
        "title": "The Canons of Dort",
        "filename": "articlesofsynodo00dort.pdf",
        "sha256": "2225599ff8ea051c6848183c3b61236e77e8d34821670da20986ab9580da60c7",
        "url": "https://archive.org/details/articlesofsynodo00dort",
        "credit": (
            "Synod of Dort. Translated by Thomas Scott (1818). The Articles of the "
            "Synod of Dort, Presbyterian Board of Publication, Philadelphia, 1856. "
            "Public domain. Transcribed from the Princeton Theological Seminary copy."
        ),
    },
    "es": {
        "text": "rc-es.json",
        "title": "Los Cánones de Dort",
        "filename": "20220462 - Les Canons de Dordrecht en espagnol - Los Cánones de Dort.pdf",
        "sha256": "3544b4af7e5c4360ddfc4ec1b4c5c9a0e3b652d92453779a9afe8d59c020101a",
        "url": "https://www.ressourceschretiennes.com/download/file/fid/8491",
        "credit": (
            "Sínodo de Dort. Ressources chrétiennes (2022) reprodujo esta edición "
            "con permiso de Covenant Protestant Reformed Church, Ballymena. "
            "CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). "
            "Formato y numeración de navegación adaptados para Pactantes bajo la misma licencia."
        ),
    },
}


def canonical_ids():
    ids = []
    for head, articles, rejections in (("1", 18, 9), ("2", 9, 7), ("3-4", 17, 9), ("5", 15, 9)):
        for kind, count in (("article", articles), ("rejection", rejections)):
            ids.extend(f"{head}-{kind}-{n}" for n in range(1, count + 1))
    return [*ids, "conclusion"]


def read_units(path):
    units = json.loads(path.read_text(encoding="utf-8"))
    if [unit["id"] for unit in units] != canonical_ids():
        raise ValueError(f"{path.name}: incomplete or out-of-order edition")
    previous_page = 1
    for unit in units:
        if not all(unit[field].strip() for field in ("group_title", "title", "body")):
            raise ValueError(f"{path.name}: missing text for {unit['id']}")
        if not previous_page <= unit["page_start"] <= unit["page_end"]:
            raise ValueError(f"{path.name}: invalid source pages for {unit['id']}")
        previous_page = unit["page_start"]
    return units


def import_database(database):
    texts = {
        language: read_units(TOOLS / "content" / "dort" / edition["text"])
        for language, edition in EDITIONS.items()
    }
    with closing(sqlite3.connect(f"{database.resolve().as_uri()}?mode=rw", uri=True)) as db, db:
        db.execute("PRAGMA foreign_keys = ON")
        db.executescript("BEGIN IMMEDIATE;\n" + (TOOLS / "dort_schema.sql").read_text())
        db.execute("DELETE FROM dort_search")
        db.execute("DELETE FROM dort_units")
        for language, edition in EDITIONS.items():
            key = f"canons_of_dort_{language}"
            db.execute("""
                INSERT INTO document_sources (document_key, title, language_code,
                    source_filename, source_sha256, attribution, source_url, content_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1)
                ON CONFLICT(document_key) DO UPDATE SET title = excluded.title,
                    language_code = excluded.language_code, source_filename = excluded.source_filename,
                    source_sha256 = excluded.source_sha256, attribution = excluded.attribution,
                    source_url = excluded.source_url, content_version = excluded.content_version
                """, (key, edition["title"], language, edition["filename"],
                      edition["sha256"], edition["credit"], edition["url"]))
            for position, unit in enumerate(texts[language], start=1):
                group_id = unit["id"].rpartition("-")[0] or "conclusion"
                db.execute("""
                    INSERT INTO dort_units (document_key, unit_id, position, group_id,
                        group_title, title, body, source_page_start, source_page_end)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (key, unit["id"], position, group_id, unit["group_title"],
                          unit["title"], unit["body"], unit["page_start"], unit["page_end"]))
        db.execute("""
            INSERT INTO dort_search (docid, group_title, title, body)
            SELECT id, group_title, title, body FROM dort_units ORDER BY id
            """)
        db.execute("INSERT INTO dort_search(dort_search) VALUES ('integrity-check')")
        for language, term in (("en", "Adam"), ("es", "Adán")):
            if not db.execute("""
                SELECT 1 FROM dort_search JOIN dort_units ON dort_units.id = dort_search.docid
                WHERE dort_search MATCH ? AND document_key = ? AND unit_id = '1-article-1'
                """, (term, f"canons_of_dort_{language}")).fetchone():
                raise ValueError(f"{language}: first article missing from offline search")
        if db.execute("PRAGMA foreign_key_check").fetchone() or db.execute(
            "PRAGMA integrity_check"
        ).fetchall() != [("ok",)]:
            raise ValueError("Corpus integrity check failed")
        if db.execute("PRAGMA user_version").fetchone()[0] < 3:
            db.execute("PRAGMA user_version = 3")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path)
    import_database(parser.parse_args().database)
