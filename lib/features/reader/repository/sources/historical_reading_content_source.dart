import '../../../../core/database/reading_database.dart';
import '../../models/reading_content.dart';
import 'reading_content_source.dart';

class HistoricalReadingContentSource implements ReadingPreviewSource {
  const HistoricalReadingContentSource(this._database);

  final ReadingDatabase _database;
  static const String _passages = '''
    SELECT u.unit_id, u.position, u.group_id, g.title AS group_title,
           u.title, u.question, u.body, u.reference_text, u.edition_notes
    FROM historical_units u JOIN historical_groups g USING (document_key, group_id)
    WHERE u.document_key = ?
  ''';

  Future<List<Map<String, Object?>>> _editions(
    String documentId,
    String language,
  ) async {
    final List<Map<String, Object?>> editions = await _database.query(
      '''
      SELECT s.document_key, s.title, s.language_code, s.attribution, s.source_url
      FROM historical_editions e JOIN document_sources s USING (document_key)
      WHERE e.document_id = ?
      ORDER BY CASE s.language_code WHEN ? THEN 0 WHEN 'es' THEN 1 ELSE 2 END, s.language_code
    ''',
      <Object?>[documentId, language],
    );
    if (editions.isEmpty) throw const ReadingDatabaseException();
    return editions;
  }

  ReadingUnit _unit(Map<String, Object?> row, {bool linkReferences = false}) {
    final String referenceText = row['reference_text']! as String;
    final List<String> references = referenceText.isEmpty
        ? const <String>[]
        : List<String>.unmodifiable(referenceText.split('\n'));
    final String? question = row['question'] as String?;
    final String body = row['body']! as String;
    return ReadingUnit(
      id: row['unit_id']! as String,
      number: row['position']! as int,
      title: row['title']! as String,
      question: question,
      body: body,
      parentId: row['group_id']! as String,
      parentTitle: row['group_title'] as String?,
      references: references,
      hasNumberedReferences: references.isNotEmpty,
      referenceLinks: linkReferences
          ? ReadingReferenceLinks.fromLetteredNotes(
              question: question,
              body: body,
              references: references,
            )
          : null,
      editionNotes: row['edition_notes']! as String,
    );
  }

  String _attribution(Map<String, Object?> edition) =>
      '${edition['attribution']}\n${edition['source_url']}';

  @override
  Future<ReadingContent> read(
    String documentId, {
    required String languageCode,
  }) async {
    final List<Map<String, Object?>> editions = await _editions(
      documentId,
      languageCode,
    );
    final Map<String, Object?> edition = editions.first;
    final List<Map<String, Object?>> rows = await _database.query(
      '$_passages ORDER BY u.position',
      <Object?>[edition['document_key']],
    );
    if (rows.isEmpty) throw const ReadingDatabaseException();
    final List<ReadingUnit> units = List<ReadingUnit>.unmodifiable(
      rows.map(
        (Map<String, Object?> row) => _unit(
          row,
          linkReferences:
              edition['document_key'] == 'westminster_larger_catechism_es',
        ),
      ),
    );
    final List<Map<String, Object?>> aliases = await _database.query(
      '''SELECT alias_id, unit_id FROM historical_unit_aliases WHERE document_key = ?''',
      <Object?>[edition['document_key']],
    );
    return ReadingContent(
      documentId: documentId,
      title: edition['title']! as String,
      languageCode: edition['language_code']! as String,
      availableLanguageCodes: Set<String>.unmodifiable(
        editions.map((row) => row['language_code']! as String),
      ),
      attribution: _attribution(edition),
      units: units,
      unitAliases: Map<String, String>.unmodifiable(<String, String>{
        for (final Map<String, Object?> alias in aliases)
          alias['alias_id']! as String: alias['unit_id']! as String,
      }),
    );
  }

  @override
  Future<ReadingPreview> readPreview(
    String documentId, {
    required String languageCode,
    String? unitId,
  }) async {
    final Map<String, Object?> edition = (await _editions(
      documentId,
      languageCode,
    )).first;
    final Object? key = edition['document_key'];
    // Home needs just the saved passage (or the first), even for a full-length book.
    final List<Map<String, Object?>> rows = await _database.query(
      '''
      $_passages AND u.position = COALESCE(
        (SELECT position FROM historical_units WHERE document_key = ? AND unit_id = ?),
        (SELECT target.position FROM historical_unit_aliases alias
         JOIN historical_units target USING (document_key, unit_id)
         WHERE alias.document_key = ? AND alias.alias_id = ?),
        1
      )
    ''',
      <Object?>[key, key, unitId, key, unitId],
    );
    if (rows.isEmpty) throw const ReadingDatabaseException();
    return (
      title: edition['title']! as String,
      languageCode: edition['language_code']! as String,
      attribution: _attribution(edition),
      unit: _unit(rows.single),
    );
  }
}
