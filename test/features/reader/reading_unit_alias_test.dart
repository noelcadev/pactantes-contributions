import 'package:flutter_test/flutter_test.dart';
import 'package:pactantes/core/database/reading_database.dart';
import 'package:pactantes/core/library/models/reading_document.dart';
import 'package:pactantes/core/library/repository/document_catalog_local_repository.dart';
import 'package:pactantes/core/preferences/preferences_store.dart';
import 'package:pactantes/features/home/repository/reading_progress_local_repository.dart';
import 'package:pactantes/features/home/view_models/home_view_model.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/repository/reader_content_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_favorites_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_preferences_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_progress_local_repository.dart';
import 'package:pactantes/features/reader/repository/sources/historical_reading_content_source.dart';
import 'package:pactantes/features/reader/repository/sources/reading_content_source.dart';
import 'package:pactantes/features/reader/view_models/reader_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _documentId = 'augustine-confessions';
const String _section1 = 'book-1-section-1';
const String _section2 = 'book-1-section-2';
const String _section3 = 'book-1-section-3';
const String _section4 = 'book-1-section-4';
const String _paragraph1 = 'book-1-paragraph-1';
const String _paragraph2 = 'book-1-paragraph-2';
const String _paragraph3 = 'book-1-paragraph-3';

class _MemoryStore implements PreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

class _AugustineCatalog extends DocumentCatalogLocalRepositoryImpl {
  const _AugustineCatalog();

  @override
  List<ReadingDocument> get available => <ReadingDocument>[
    findById(_documentId)!,
  ];
}

class _TrackingDatabase implements ReadingDatabase {
  _TrackingDatabase(this.sqlite);

  final Database sqlite;
  bool fail = false;
  final List<int> bodyRows = <int>[];

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> arguments = const <Object?>[],
  ]) async {
    if (fail) throw const ReadingDatabaseException();
    final List<Map<String, Object?>> rows = await sqlite.rawQuery(
      sql,
      arguments,
    );
    if (sql.contains('u.body')) bodyRows.add(rows.length);
    return rows;
  }
}

Future<void> _seedFixture(Database database) async {
  await database.execute('''
    CREATE TABLE document_sources (
      document_key TEXT, title TEXT, language_code TEXT, attribution TEXT, source_url TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE historical_editions (document_key TEXT, document_id TEXT)
  ''');
  await database.execute('''
    CREATE TABLE historical_groups (document_key TEXT, group_id TEXT, title TEXT)
  ''');
  await database.execute('''
    CREATE TABLE historical_units (
      document_key TEXT, unit_id TEXT, position INTEGER, group_id TEXT, title TEXT,
      body TEXT, reference_text TEXT, edition_notes TEXT, question TEXT,
      PRIMARY KEY (document_key, unit_id)
    )
  ''');
  await database.execute('''
    CREATE TABLE historical_unit_aliases (
      document_key TEXT, alias_id TEXT, unit_id TEXT,
      PRIMARY KEY (document_key, alias_id)
    )
  ''');
  final Batch seed = database.batch();
  const Map<String, List<String>> editions = <String, List<String>>{
    'en': <String>[_section1, _section2, _section3, _section4],
    'es': <String>[_paragraph1, _paragraph2, _paragraph3],
  };
  for (final MapEntry<String, List<String>> edition in editions.entries) {
    final String language = edition.key;
    seed.rawInsert(
      'INSERT INTO document_sources VALUES (?, ?, ?, ?, ?)',
      <Object?>[language, 'Confessions', language, 'Edition', 'Source'],
    );
    seed.rawInsert('INSERT INTO historical_editions VALUES (?, ?)', <Object?>[
      language,
      _documentId,
    ]);
    seed.rawInsert('INSERT INTO historical_groups VALUES (?, ?, ?)', <Object?>[
      language,
      'book-1',
      'Book 1',
    ]);
    for (final (int position, String unitId) in edition.value.indexed) {
      seed.rawInsert(
        'INSERT INTO historical_units VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          language,
          unitId,
          position + 1,
          'book-1',
          unitId,
          unitId,
          '',
          '',
          null,
        ],
      );
    }
  }
  const List<(String, String, String)> aliases = <(String, String, String)>[
    ('es', _section1, _paragraph1),
    ('es', _section2, _paragraph2),
    ('es', _section3, _paragraph2),
    ('es', _section4, _paragraph3),
    ('en', _paragraph1, _section1),
    ('en', _paragraph2, _section2),
    ('en', _paragraph3, _section4),
    // An exact ID takes priority even if an edition also lists it as an alias.
    ('es', _paragraph3, _paragraph2),
  ];
  for (final (String language, String alias, String target) in aliases) {
    seed.rawInsert(
      'INSERT INTO historical_unit_aliases VALUES (?, ?, ?)',
      <Object?>[language, alias, target],
    );
  }
  await seed.commit(noResult: true);
}

void main() {
  sqfliteFfiInit();
  late _TrackingDatabase database;
  late ReaderContentLocalRepository content;
  late _MemoryStore store;
  late ReaderPreferencesLocalRepository preferences;
  late ReaderProgressLocalRepository progress;
  late ReaderFavoritesLocalRepository favorites;
  late ReaderViewModel reader;

  setUp(() async {
    final Database sqlite = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(sqlite.close);
    await _seedFixture(sqlite);
    database = _TrackingDatabase(sqlite);
    content = ReaderContentLocalRepositoryImpl(<String, ReadingContentSource>{
      _documentId: HistoricalReadingContentSource(database),
    });
    store = _MemoryStore();
    preferences = ReaderPreferencesLocalRepositoryImpl(store);
    progress = ReaderProgressLocalRepositoryImpl(store);
    favorites = ReaderFavoritesLocalRepositoryImpl(store);
    reader = ReaderViewModel(content, preferences, favorites, progress);
    addTearDown(reader.dispose);
  });

  test(
    'preview resolves exact, alternate, and unknown anchors with one body',
    () async {
      expect(
        (await content.readPreview(_documentId, unitId: _paragraph3)).unit.id,
        _paragraph3,
      );
      final ReadingPreview aliased = await content.readPreview(
        _documentId,
        unitId: _section3,
      );
      expect(aliased.unit.id, _paragraph2);
      expect(
        (await content.readPreview(_documentId, unitId: 'unknown')).unit.id,
        _paragraph1,
      );
      expect(database.bodyRows, <int>[1, 1, 1]);
      final ReadingContent edition = await content.read(_documentId);
      expect(
        edition.units[edition.resolveUnitIndex(_paragraph3)].id,
        _paragraph3,
      );
      expect(
        edition.aliasesFor(_paragraph2),
        unorderedEquals(<String>[_section2, _section3]),
      );
    },
  );

  test(
    'Home preview and fresh reader keep the original progress anchor',
    () async {
      await progress.save(
        documentId: _documentId,
        unitId: _section3,
        title: 'Old edition',
        progress: .75,
      );
      final HomeViewModel home = HomeViewModel(
        ReadingProgressLocalRepositoryImpl(store),
        const _AugustineCatalog(),
        readerPreferencesRepository: preferences,
        readerContentRepository: content,
      );
      addTearDown(home.dispose);
      await home.initialize(languageCode: 'es');
      expect(home.readingItems.first.unit?.id, _paragraph2);
      expect(home.readingItems.first.progress?.sectionId, _section3);
      await reader.initialize(
        _documentId,
        unitId: home.readingItems.first.progress?.sectionId,
      );
      expect(reader.unit?.id, _paragraph2);
      await reader.pendingWrites;
      expect(await progress.readUnit(_documentId), _section3);

      final ReaderViewModel reopened = ReaderViewModel(
        content,
        preferences,
        favorites,
        progress,
      );
      addTearDown(reopened.dispose);
      await reopened.initialize(_documentId, languageCode: 'en');
      expect(reopened.unit?.id, _section3);
      await reopened.pendingWrites;
    },
  );

  test('translation, device language and retry keep the precise anchor until navigation', () async {
    await reader.initialize(_documentId, unitId: _section3, languageCode: 'en');
    await reader.changeTranslation(ReaderTranslation.spanish);
    expect(reader.unit?.id, _paragraph2);
    await reader.pendingWrites;
    expect(await progress.readUnit(_documentId), _section3);

    database.fail = true;
    await reader.changeTranslation(ReaderTranslation.device);
    expect(reader.state, ReaderState.error);
    database.fail = false;
    await reader.reload();
    expect(reader.unit?.id, _section3);

    await reader.reload(languageCode: 'es');
    expect(reader.unit?.id, _paragraph2);
    await reader.reload(languageCode: 'en');
    expect(reader.unit?.id, _section3);

    await reader.reload(languageCode: 'es');
    reader.previous();
    reader.next();
    await reader.pendingWrites;
    expect(await progress.readUnit(_documentId), _paragraph2);
    await reader.reload(languageCode: 'en');
    expect(reader.unit?.id, _section2);
    await reader.pendingWrites;
  });

  test('favorites resolve across merged passages and switch off as one visible favorite', () async {
    await favorites.setFavorite(_documentId, _section3, true);
    await favorites.setFavorite(_documentId, _paragraph3, true);
    await reader.initialize(_documentId, unitId: _section3);
    expect(reader.unit?.id, _paragraph2);
    expect(reader.favorite, isTrue);

    await favorites.setFavorite(_documentId, _section2, true);
    await favorites.setFavorite(_documentId, _paragraph2, true);
    await reader.toggleFavorite();
    expect(reader.favorite, isFalse);
    expect(await favorites.contains(_documentId, _section2), isFalse);
    expect(await favorites.contains(_documentId, _section3), isFalse);
    expect(await favorites.contains(_documentId, _paragraph2), isFalse);
    expect(await favorites.contains(_documentId, _paragraph3), isTrue);

    await reader.toggleFavorite();
    expect(await favorites.contains(_documentId, _section3), isTrue);
    await reader.reload(languageCode: 'en');
    expect(reader.unit?.id, _section3);
    expect(reader.favorite, isTrue);

    await favorites.setFavorite(_documentId, _paragraph2, true);
    await reader.initialize(_documentId, unitId: _section2, languageCode: 'en');
    expect(reader.favorite, isTrue);
    await reader.toggleFavorite();
    expect(await favorites.contains(_documentId, _paragraph2), isFalse);
    expect(await favorites.contains(_documentId, _section3), isTrue);
    await reader.pendingWrites;
  });
}
