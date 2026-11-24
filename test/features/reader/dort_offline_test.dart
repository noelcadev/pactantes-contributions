import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:pactantes/app/dependency_injection.dart';
import 'package:pactantes/core/database/reading_database.dart';
import 'package:pactantes/core/database/sqflite_reading_database.dart';
import 'package:pactantes/features/home/view_models/home_view_model.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/repository/reader_content_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_preferences_local_repository.dart';
import 'package:pactantes/features/reader/view_models/reader_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled Dort editions open and resume without a download', () async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final DatabaseFactory factory = databaseFactoryFfi;
    final String previous = await factory.getDatabasesPath();
    final Directory directory = await Directory.systemTemp.createTemp(
      'pactantes_dort',
    );
    await factory.setDatabasesPath(directory.path);
    final GetIt container = GetIt.asNewInstance();
    registerDependencies(container);
    await container.unregister<ReadingDatabase>();
    final ReadingDatabase database = SqfliteReadingDatabase(
      factory,
      rootBundle,
    );
    container.registerSingleton<ReadingDatabase>(database);
    addTearDown(() async {
      await container.reset();
      await factory.setDatabasesPath(previous);
      await directory.delete(recursive: true);
    });
    final ReaderContentLocalRepository repository =
        container<ReaderContentLocalRepository>();
    final ReadingContent english = await repository.read(
      'canons-of-dort',
      languageCode: 'en-US',
    );
    final ReadingContent spanish = await repository.read(
      'canons-of-dort',
      languageCode: 'es-PY',
    );
    expect(english.languageCode, 'en');
    expect(spanish.languageCode, 'es');
    expect(english.availableLanguageCodes, <String>{'en', 'es'});
    expect(spanish.canonicalUnitIds, orderedEquals(english.canonicalUnitIds));
    expect(english.units, hasLength(94));
    expect(spanish.groups.map((ReadingGroup g) => g.units.length), <int>[
      18,
      9,
      9,
      7,
      17,
      9,
      15,
      9,
      1,
    ]);
    expect(english.units.first.body, contains('Adam'));
    expect(english.units.first.question, isNull);
    expect(
      spanish.units.first.body,
      startsWith('Puesto que todos los hombres han pecado en Adán'),
    );
    expect(spanish.units.last.id, 'conclusion');
    expect(english.attribution, contains('Thomas Scott'));
    expect(spanish.attribution, contains('CC BY-SA 4.0'));
    // An unavailable global preference falls back for Dort only.
    final ReaderPreferencesLocalRepository preferences =
        container<ReaderPreferencesLocalRepository>();
    await preferences.save(
      const ReaderPreferences(translation: ReaderTranslation.portuguese),
    );
    final ReaderViewModel reader = container<ReaderViewModel>();
    await reader.initialize('canons-of-dort', languageCode: 'pt');
    expect(reader.content!.languageCode, 'es');
    expect(
      (await preferences.read()).translation,
      ReaderTranslation.portuguese,
    );
    reader.select('3-4-rejection-3');
    await reader.pendingWrites;
    await reader.toggleFavorite();
    await reader.changeTranslation(ReaderTranslation.english);
    expect(reader.unit!.id, '3-4-rejection-3');
    expect(reader.content!.languageCode, 'en');
    await reader.pendingWrites;
    reader.dispose();
    final ReaderViewModel reopened = container<ReaderViewModel>();
    await reopened.initialize('canons-of-dort');
    expect(reopened.unit!.id, '3-4-rejection-3');
    expect(reopened.favorite, isTrue);
    await reopened.pendingWrites;
    reopened.dispose();
    final HomeViewModel home = container<HomeViewModel>();
    await home.initialize(languageCode: 'en');
    expect(home.readingItems.single.document.id, 'canons-of-dort');
    expect(
      home.libraryItems.map((item) => item.sourceTitle),
      containsAll([
        english.title,
        (await repository.read(
          'heidelberg-catechism',
          languageCode: 'en',
        )).title,
      ]),
    );
    home.dispose();
    final Database handle = await factory.openDatabase(
      '${directory.path}/reformed_documents_v7.db',
      options: OpenDatabaseOptions(readOnly: true),
    );
    await handle.close();
  });
}
