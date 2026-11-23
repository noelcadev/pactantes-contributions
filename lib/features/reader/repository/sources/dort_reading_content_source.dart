import '../../../../core/database/reading_database.dart';
import '../../models/reading_content.dart';
import 'reading_content_source.dart';

class DortReadingContentSource implements ReadingContentSource {
  const DortReadingContentSource(this._database);
  final ReadingDatabase _database;

  @override
  Future<ReadingContent> read(
    String documentId, {
    required String languageCode,
  }) async {
    final List<Map<String, Object?>> editions = await _database.query(
      '''
      SELECT document_key, title, language_code, attribution, source_url
      FROM document_sources
      WHERE document_key IN (SELECT DISTINCT document_key FROM dort_units)
      ORDER BY CASE language_code WHEN ? THEN 0 WHEN 'es' THEN 1 ELSE 2 END,
               language_code
      ''',
      <Object?>[languageCode],
    );
    if (editions.isEmpty) throw const ReadingDatabaseException();
    final Map<String, Object?> edition = editions.first;
    final List<Map<String, Object?>> rows = await _database.query(
      '''
      SELECT unit_id, position, group_id, group_title, title, body
      FROM dort_units WHERE document_key = ? ORDER BY position
      ''',
      <Object?>[edition['document_key']],
    );
    final List<ReadingUnit> units = <ReadingUnit>[
      for (final Map<String, Object?> row in rows)
        ReadingUnit(
          id: row['unit_id']! as String,
          number: row['position']! as int,
          title: row['title']! as String,
          body: row['body']! as String,
          parentId: row['group_id']! as String,
          parentTitle: row['group_id'] == 'conclusion'
              ? null
              : row['group_title']! as String,
        ),
    ];
    return ReadingContent(
      documentId: documentId,
      title: edition['title']! as String,
      languageCode: edition['language_code']! as String,
      availableLanguageCodes: Set<String>.unmodifiable(
        editions.map(
          (Map<String, Object?> row) => row['language_code']! as String,
        ),
      ),
      attribution: '${edition['attribution']}\n${edition['source_url']}',
      units: List<ReadingUnit>.unmodifiable(units),
      canonicalUnitIds: List<String>.unmodifiable(
        units.map((ReadingUnit unit) => unit.id),
      ),
    );
  }
}
