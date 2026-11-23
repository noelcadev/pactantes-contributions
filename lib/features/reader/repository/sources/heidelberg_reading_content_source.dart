import '../../../../core/bible/bible_book_names.dart';
import '../../../../core/database/reading_database.dart';
import '../../models/reading_content.dart';
import 'reading_content_source.dart';

class HeidelbergReadingContentSource implements ReadingContentSource {
  const HeidelbergReadingContentSource(this._database, this._bookNames);
  final ReadingDatabase _database;
  final BibleBookNames _bookNames;

  @override
  Future<ReadingContent> read(
    String documentId, {
    required String languageCode,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      '''
      SELECT c.canonical_question_number, c.question_number, c.question, c.answer,
        q.lords_day_number, d.label, s.title, c.language_code,
        s.attribution, s.source_url
      FROM heidelberg_catechism c
      JOIN heidelberg_questions q USING (canonical_question_number)
      JOIN heidelberg_lords_day_labels d USING (language_code)
      JOIN document_sources s USING (document_key)
      WHERE c.language_code = ? ORDER BY c.question_number
    ''',
      <Object?>[languageCode],
    );
    if (rows.isEmpty) throw const ReadingDatabaseException();
    final List<Map<String, Object?>> references = await _database.query('''
      SELECT r.*, g.reference_kind
      FROM heidelberg_scripture_references r
      JOIN heidelberg_reference_groups g
        USING (canonical_question_number, reference_number)
      ORDER BY canonical_question_number, reference_number, passage_number
    ''');
    final Map<int, Map<int?, List<String>>> referencesByQuestion = {};
    for (final Map<String, Object?> reference in references) {
      final int canonical = reference['canonical_question_number']! as int;
      final int? note = reference['reference_kind'] == 'footnote'
          ? reference['reference_number']! as int
          : null;
      referencesByQuestion
          .putIfAbsent(canonical, () => <int?, List<String>>{})
          .putIfAbsent(note, () => <String>[])
          .add(_reference(reference, languageCode));
    }
    final List<Map<String, Object?>> canonical = await _database.query(
      'SELECT canonical_question_number FROM heidelberg_questions '
      'ORDER BY canonical_question_number',
    );
    return ReadingContent(
      documentId: documentId,
      title: rows.first['title']! as String,
      languageCode: rows.first['language_code']! as String,
      attribution: '${rows.first['attribution']}\n${rows.first['source_url']}',
      canonicalUnitIds: List<String>.unmodifiable(
        canonical.map(
          (Map<String, Object?> row) =>
              'question-${row['canonical_question_number']}',
        ),
      ),
      units: List<ReadingUnit>.unmodifiable(
        rows.map((Map<String, Object?> row) {
          final int canonical = row['canonical_question_number']! as int;
          final int day = row['lords_day_number']! as int;
          final Map<int?, List<String>> groups =
              referencesByQuestion[canonical] ?? {};
          final bool markNotes =
              (languageCode == 'en' || languageCode == 'pt') &&
              groups.isNotEmpty &&
              !groups.containsKey(null);
          final Set<int> markers = <int>{};
          String formatText(String text) => markNotes
              ? text.replaceAllMapped(_noteMarker, (Match match) {
                  final String digits = match[2]!;
                  markers.add(int.parse(digits));
                  return '${match[1]}${_superscript(digits)}';
                })
              : text;

          final String question = formatText(row['question']! as String);
          final String answer = formatText(row['answer']! as String);
          // Some Portuguese notes differ from the groups in the English index.
          final bool numbered =
              markers.isNotEmpty && markers.every(groups.containsKey);
          return ReadingUnit(
            id: 'question-$canonical',
            number: row['question_number']! as int,
            question: question,
            body: answer,
            parentId: 'lords-day-$day',
            parentTitle: '${row['label']} $day',
            hasNumberedReferences: numbered,
            references: List<String>.unmodifiable(<String>[
              for (final MapEntry<int?, List<String>> group in groups.entries)
                if (numbered)
                  '${_superscript(group.key!.toString())} ${group.value.join(' · ')}'
                else
                  ...group.value,
            ]),
          );
        }),
      ),
    );
  }

  // The PDFs attach notes to words or punctuation, sometimes with a space.
  // Keep list numbers ("1.") and Scripture chapter/verse numbers as printed.
  static final RegExp _noteMarker = RegExp(
    r'(\p{L}[.,;:!?”]*) ?([1-9][0-9]*)(?=$|\s|”|\p{Lu})',
    unicode: true,
  );

  static String _superscript(String digits) => digits
      .split('')
      .map((String digit) => '⁰¹²³⁴⁵⁶⁷⁸⁹'[int.parse(digit)])
      .join();

  String _reference(Map<String, Object?> row, String language) {
    final String code = row['book_code']! as String;
    final String book = _bookNames.name(code, languageCode: language);
    final int start = row['chapter_start']! as int;
    final int end = row['chapter_end']! as int;
    final int? verse = row['verse_start'] as int?;
    final int? lastVerse = row['verse_end'] as int?;
    if (verse == null) return '$book $start${end == start ? '' : '–$end'}';
    if (end != start) return '$book $start:$verse–$end:$lastVerse';
    if (lastVerse != verse) return '$book $start:$verse–$lastVerse';
    return '$book $start:$verse';
  }
}
