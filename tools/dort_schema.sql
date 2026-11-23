CREATE TABLE IF NOT EXISTS dort_units (
    id INTEGER PRIMARY KEY,
    document_key TEXT NOT NULL REFERENCES document_sources(document_key),
    unit_id TEXT NOT NULL,
    position INTEGER NOT NULL CHECK (position > 0),
    group_id TEXT NOT NULL,
    group_title TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL CHECK (length(trim(body)) > 0),
    source_page_start INTEGER NOT NULL CHECK (source_page_start > 0),
    source_page_end INTEGER NOT NULL CHECK (source_page_end >= source_page_start),
    UNIQUE (document_key, unit_id),
    UNIQUE (document_key, position)
);

CREATE VIRTUAL TABLE IF NOT EXISTS dort_search USING fts4(
    group_title, title, body, tokenize=unicode61
);
