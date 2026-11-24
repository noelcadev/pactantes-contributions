# Canons of Dort

The bundled SQLite corpus includes two editions of the Canons. Each has 59 articles, 34 rejections of errors, and the synod's conclusion. Heads III and IV form a single section in both editions. The catalog ID is `canons-of-dort`.

## English

Thomas Scott translated the articles from Latin in 1818. The transcription follows *The Articles of the Synod of Dort*, Philadelphia, Presbyterian Board of Publication, 1856, from the Princeton Theological Seminary copy. The translation and this edition are in the public domain. The source PDF has SHA-256 `2225599ff8ea051c6848183c3b61236e77e8d34821670da20986ab9580da60c7`. [Scanned edition](https://archive.org/details/articlesofsynodo00dort)

The text runs from printed pages 182–235, physical PDF pages 188–241. It includes the articles, the introductions to the rejections, the rejections with their replies, and the conclusion through its final Amen. Scott's editorial notes, the attestation of the signatories and the separate decision about the Remonstrants fall outside the reading text. The reader uses successive unit numbers where the printer repeated a numeral, including the sixth rejection of Heads III and IV on printed page 218. The transcription was checked against three OCR readings of the scan, with visual checks of disputed passages and section boundaries.

## Spanish

The text follows *Los Cánones de Dort*, Ressources chrétiennes, 2022. The publisher credits Covenant Protestant Reformed Church, Ballymena, for permission to reproduce its edition and identifies the license as CC BY-SA 4.0 on PDF page 22. The Spanish transcription and its formatting adaptations in Pactantes are distributed under the same license. Credits, the source URL and the license URL are available in the reader and accompany copied or shared passages. [Licensed edition](https://www.ressourceschretiennes.com/download/file/fid/8491) · [License](https://creativecommons.org/licenses/by-sa/4.0/)

The licensed PDF has SHA-256 `3544b4af7e5c4360ddfc4ec1b4c5c9a0e3b652d92453779a9afe8d59c020101a`. The supplied `Canones de Dort.pdf` has SHA-256 `18fc8a0cd9343e958d1719b391835a083f2356f79c7a56d7ad0b7148e75e90cd`. The two PDFs and the structured edition have identical body text across all 94 units after removing headers, footers, headings and unit markers, joining words divided by line breaks, and normalizing whitespace. The comparison preserves letters, accents, case and punctuation. The shared 67,959-character text has SHA-256 `f7f0942066c9b1c9e79ae8c412cad8a403f86b50efefe0f2945331442643502f`. Navigation labels use sequential numbers. Source-page references refer to the licensed edition.

## Portuguese edition research

Ressources chrétiennes publishes a complete Portuguese edition under CC BY-SA 4.0. Its notice credits Monergismo and records that permission was obtained. Rev. Wolney Garcia credits himself as translator of a closely matching text. The available notices do not identify who granted the publisher permission to license the underlying translation. Portuguese is not included in this corpus revision. [Publisher's edition and terms](https://www.ressourceschretiennes.com/article/canons-dordrecht-portugais) · [Translator's edition](https://pastorwolney.wordpress.com/2023/05/25/os-canones-de-dort-1618-1619/)

## Storage and reproduction

`tools/content/dort/` holds the reviewed UTF-8 transcriptions. Each record names the unit, its heading, its body and its inclusive one-based physical PDF pages. The importer records each edition in `document_sources` and its ordered units in `dort_units`. Unit IDs such as `3-4-rejection-6` are shared across editions for navigation, favorites and reading progress. The FTS4 index `dort_search` uses the corresponding `dort_units.id` as its `docid`.

From the repository root, rebuild the Dort tables in the existing corpus and run the regression checks with Python's standard library.

```sh
python3 tools/import_dort.py --database assets/db/reformed_documents.db
python3 -m unittest discover -s tools -p test_import_dort.py
```

The importer replaces both editions and their index in a single transaction. It checks unit coverage and order, source pages, full-text matches, foreign keys and database integrity. Flutter installs the resulting asset locally as corpus revision 11.
