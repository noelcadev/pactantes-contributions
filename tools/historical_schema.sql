CREATE TABLE IF NOT EXISTS historical_editions (
    document_key TEXT PRIMARY KEY REFERENCES document_sources(document_key),
    document_id TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS historical_document_id ON historical_editions(document_id);

CREATE TABLE IF NOT EXISTS historical_groups (
    document_key TEXT NOT NULL REFERENCES historical_editions(document_key),
    group_id TEXT NOT NULL,
    title TEXT,
    PRIMARY KEY (document_key, group_id)
);

CREATE TABLE IF NOT EXISTS historical_units (
    id INTEGER PRIMARY KEY,
    document_key TEXT NOT NULL,
    group_id TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    position INTEGER NOT NULL CHECK (position > 0),
    title TEXT NOT NULL,
    body TEXT NOT NULL CHECK (length(trim(body)) > 0),
    reference_text TEXT NOT NULL DEFAULT '',
    edition_notes TEXT NOT NULL DEFAULT '',
    FOREIGN KEY (document_key, group_id) REFERENCES historical_groups(document_key, group_id),
    UNIQUE (document_key, unit_id),
    UNIQUE (document_key, position)
);

CREATE VIRTUAL TABLE IF NOT EXISTS historical_search USING fts4(
    group_title, title, body, reference_text, edition_notes, tokenize=unicode61
);

CREATE TABLE IF NOT EXISTS historical_unit_aliases (
    document_key TEXT NOT NULL,
    alias_id TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    PRIMARY KEY (document_key, alias_id),
    FOREIGN KEY (document_key, unit_id) REFERENCES historical_units(document_key, unit_id)
);

CREATE TABLE IF NOT EXISTS historical_facsimile_ranges (
    document_key TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    first_page INTEGER NOT NULL CHECK (first_page > 0),
    last_page INTEGER NOT NULL CHECK (last_page >= first_page),
    asset_directory TEXT NOT NULL,
    PRIMARY KEY (document_key, unit_id),
    FOREIGN KEY (document_key, unit_id) REFERENCES historical_units(document_key, unit_id)
);
