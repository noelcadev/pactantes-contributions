import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:pactantes/app/dependency_injection.dart';
import 'package:pactantes/core/database/reading_database.dart';
import 'package:pactantes/core/database/sqflite_reading_database.dart';
import 'package:pactantes/core/library/models/reading_document.dart';
import 'package:pactantes/core/library/repository/document_catalog_local_repository.dart';
import 'package:pactantes/features/home/view_models/home_view_model.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/repository/reader_content_local_repository.dart';
import 'package:pactantes/features/reader/services/reading_share_formatter.dart';
import 'package:pactantes/features/reader/view_models/reader_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'catalogued editions open offline with their own text, notes and bookmarks',
    () async {
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final DatabaseFactory factory = databaseFactoryFfi;
      final String previous = await factory.getDatabasesPath();
      final Directory directory = await Directory.systemTemp.createTemp(
        'historical_readings',
      );
      await factory.setDatabasesPath(directory.path);
      final GetIt container = GetIt.asNewInstance();
      registerDependencies(container);
      await container.unregister<ReadingDatabase>();
      container.registerSingleton<ReadingDatabase>(
        SqfliteReadingDatabase(factory, rootBundle),
      );
      addTearDown(() async {
        await container.reset();
        final Database handle = await factory.openDatabase(
          '${directory.path}/reformed_documents_v11.db',
          options: OpenDatabaseOptions(readOnly: true),
        );
        await handle.close();
        await factory.setDatabasesPath(previous);
        await directory.delete(recursive: true);
      });
      final ReaderContentLocalRepository books =
          container<ReaderContentLocalRepository>();
      for (final ReadingDocument book
          in container<DocumentCatalogLocalRepository>().available) {
        final ReadingContent content = await books.read(
          book.id,
          languageCode: 'pt-BR',
        );
        final ReadingPreview first = await books.readPreview(
          book.id,
          languageCode: 'pt-BR',
        );
        final ReadingPreview last = await books.readPreview(
          book.id,
          unitId: content.units.last.id,
          languageCode: 'pt-BR',
        );
        expect(content.documentId, book.id);
        expect(first.unit.body, content.units.first.body, reason: book.id);
        expect(last.unit.body, content.units.last.body, reason: book.id);
        expect(last.attribution, content.attribution, reason: book.id);
        expect(last.languageCode, content.languageCode, reason: book.id);
      }
      final ReadingContent larger = await books.read(
        'westminster-larger-catechism',
        languageCode: 'es',
      );
      expect(larger.title, 'Catecismo mayor de Westminster');
      expect(larger.availableLanguageCodes, <String>{'es', 'en', 'pt'});
      expect(larger.units.map((unit) => unit.id), <String>[
        for (int n = 1; n <= 196; n++) 'question-$n',
      ]);
      final ReadingUnit firstQuestion = larger.units.first;
      expect(firstQuestion.title, 'Pregunta 1');
      expect(
        firstQuestion.question,
        '¿Cuál es el fin principal y más noble del hombre?',
      );
      expect(firstQuestion.body, contains('gozar de él para siempre'));
      expect(firstQuestion.references.first, startsWith('a) Rom. 11:36'));
      final Map<String, List<String>> unanchored = <String, List<String>>{};
      int linkedCount = 0;
      for (final ReadingUnit unit in larger.units) {
        final ReadingReferenceLinks? links = unit.referenceLinks;
        if (unit.references.isEmpty) {
          expect(links, isNull);
          continue;
        }
        expect(links, isNotNull, reason: unit.id);
        final List<int> indices = <int>[
          for (final call in [...links!.question, ...links.body])
            call.referenceIndex,
        ];
        linkedCount += indices.length;
        final List<String> missing = <String>[
          for (final (int index, String line) in unit.references.indexed)
            if (!indices.contains(index)) line.split(' ').first,
        ];
        if (missing.isNotEmpty) unanchored[unit.id] = missing;
      }
      expect(linkedCount, 1303);
      expect(unanchored, <String, List<String>>{
        'question-52': ['d)'],
        'question-127': ['r)'],
      });
      final ReadingPreview questionPreview = await books.readPreview(
        larger.documentId,
        languageCode: 'es',
        unitId: firstQuestion.id,
      );
      expect(questionPreview.unit.question, firstQuestion.question);
      expect(
        larger.attribution,
        endsWith(
          'https://ibe.org.mx/wp-content/uploads/2025/09/'
          'catecismo-mayor-de-westminster.pdf',
        ),
      );
      final String sharedQuestion = const ReadingShareFormatter().format(
        document: larger,
        unit: firstQuestion,
        unitLabel: firstQuestion.title!,
        questionPrefix: 'P.',
        answerPrefix: 'R.',
        referencesLabel: 'Referencias',
        attribution: '',
      );
      expect(sharedQuestion, contains('P. ${firstQuestion.question}'));
      expect(sharedQuestion, contains('R. ${firstQuestion.body}'));
      expect(sharedQuestion, contains(firstQuestion.references.first));
      expect(sharedQuestion, contains(larger.attribution));

      final ReadingContent creed = await books.read(
        'nicene-creed',
        languageCode: 'es',
      );
      expect(creed.title, 'Credo Niceno');
      expect(creed.availableLanguageCodes, <String>{'es', 'en', 'pt'});
      final ReadingUnit affirmation = creed.units.single;
      expect(affirmation.id, 'creed');
      expect(affirmation.question, isNull);
      expect(affirmation.body, startsWith('Creemos en un solo Dios'));
      expect(affirmation.body, contains('universal*'));
      expect(affirmation.editionNotes, contains('católica'));
      expect(
        creed.attribution,
        endsWith(
          'https://graciasobregracia.org/storage/documents/'
          'MDLF21_Recursos_Credo_Niceno.pdf',
        ),
      );
      final ReadingPreview creedPreview = await books.readPreview(
        creed.documentId,
        languageCode: 'es',
      );
      expect(creedPreview.unit.body, affirmation.body);
      expect(creedPreview.unit.editionNotes, affirmation.editionNotes);
      for (final (String locale, String opening, String imprint) in [
        ('en', 'I believe in one God', '1892'),
        ('pt-BR', 'Creio em um só Deus', '1884'),
      ]) {
        final ReadingContent edition = await books.read(
          creed.documentId,
          languageCode: locale,
        );
        expect(edition.languageCode, locale.split('-').first);
        expect(edition.units.single.id, affirmation.id);
        expect(edition.units.single.body, startsWith(opening));
        expect(edition.units.single.body.split('\n\n'), hasLength(3));
        expect(edition.attribution, contains(imprint));
      }

      final ReaderViewModel catechismReader = container<ReaderViewModel>();
      await catechismReader.initialize(larger.documentId);
      catechismReader.select('question-196');
      await catechismReader.pendingWrites;
      expect(catechismReader.unit?.title, 'Pregunta 196');
      expect(catechismReader.hasNext, isFalse);
      for (final translation in [
        ReaderTranslation.english,
        ReaderTranslation.portuguese,
      ]) {
        await catechismReader.changeTranslation(translation);
        expect(catechismReader.content?.languageCode, translation.languageCode);
        expect(
          catechismReader.content?.units.map((unit) => unit.id),
          larger.units.map((unit) => unit.id),
        );
        expect(catechismReader.unit?.id, 'question-196');
        expect(catechismReader.unit?.question, isNotEmpty);
        expect(catechismReader.unit?.body, isNot(larger.units.last.body));
      }
      await catechismReader.changeTranslation(ReaderTranslation.spanish);
      catechismReader.dispose();
      final ReaderViewModel resumed = container<ReaderViewModel>();
      await resumed.initialize(larger.documentId);
      expect(resumed.unit?.id, 'question-196');
      await resumed.pendingWrites;
      resumed.dispose();

      final ReadingContent belgic = await books.read(
        'belgic-confession',
        languageCode: 'es',
      );
      expect(belgic.availableLanguageCodes, <String>{'es', 'en', 'pt'});
      expect(belgic.units.map((unit) => unit.id), [
        for (int n = 1; n <= 37; n++) 'article-$n',
      ]);
      final ReadingUnit article = belgic.units.first;
      expect(article.body, startsWith('Todos nosotros creemos con el corazón'));
      expect(article.body, contains('con la boca, que hay un ser espiritual'));
      expect(article.references, isEmpty);
      final String share = const ReadingShareFormatter().format(
        document: belgic,
        unit: article,
        unitLabel: article.title!,
        questionPrefix: '',
        answerPrefix: '',
        referencesLabel: 'Referencias',
        attribution: 'Pactantes',
      );
      expect(share, contains(article.body));
      expect(
        share,
        contains('Used by Permission of the Reformed Church in America'),
      );
      final ReadingPreview fallback = await books.readPreview(
        'belgic-confession',
        unitId: 'unknown',
      );
      expect(fallback.unit.id, 'article-1');
      final ReadingContent portuguese = await books.read(
        'belgic-confession',
        languageCode: 'pt-BR',
      );
      expect(portuguese.languageCode, 'pt');
      expect(
        portuguese.units.map((unit) => unit.id),
        belgic.units.map((unit) => unit.id),
      );
      expect(
        portuguese.units.expand((unit) => unit.references),
        hasLength(262),
      );
      final ReadingUnit article36 = portuguese.units[35];
      expect(article36.editionNotes, contains('idolatria'));
      expect(article36.body, isNot(contains('toda idolatria')));
      final String portugueseShare = const ReadingShareFormatter().format(
        document: portuguese,
        unit: article36,
        unitLabel: article36.title!,
        questionPrefix: '',
        answerPrefix: '',
        referencesLabel: 'Referências',
        notesLabel: 'Notas da edição',
        attribution: 'Pactantes',
      );
      expect(portugueseShare, contains('Notas da edição'));
      expect(portugueseShare, contains(article36.editionNotes));
      expect(portugueseShare, contains('Sociedade Bíblica do Brasil'));

      final ReadingContent westminster = await books.read(
        'westminster-confession',
        languageCode: 'en',
      );
      expect(westminster.groups, hasLength(33));
      expect(westminster.units, hasLength(172));
      expect(westminster.units.first.id, 'chapter-1-section-1');
      expect(westminster.groups[30].units, hasLength(5));
      final ReadingUnit synods = westminster.groups[30].units[1];
      expect(synods.body, contains('magistrates may lawfully call a synod'));
      expect(synods.references, isNotEmpty);
      final ReadingContent clir = await books.read(
        'westminster-confession',
        languageCode: 'es',
      );
      expect(clir.availableLanguageCodes, <String>{'es', 'en'});
      expect(clir.units.map((u) => u.id), westminster.units.map((u) => u.id));
      expect(
        clir.units.first.body,
        startsWith('Aunque la luz de la naturaleza'),
      );
      expect(
        clir.groups[30].units[1].body,
        contains('legítimamente convocar a un Sínodo'),
      );
      expect(clir.groups[30].units[1].editionNotes, startsWith('†.'));
      expect(clir.units.expand((u) => u.references), hasLength(579));
      expect(clir.units.last.references.last, startsWith('584.'));
      expect(
        clir.attribution,
        allOf(
          contains('Alonzo Ramírez Alvarado'),
          contains('Sociedades Bíblicas Unidas'),
        ),
      );
      final ReadingContent scots = await books.read(
        'scots-confession',
        languageCode: 'es',
      );
      expect(scots.availableLanguageCodes, <String>{'es', 'en', 'pt'});
      expect(scots.languageCode, 'es');
      expect(scots.units.map((unit) => unit.id), [
        for (int n = 1; n <= 25; n++) 'chapter-$n',
      ]);
      expect(scots.units.first.title, 'Capítulo 1 · Dios');
      expect(scots.units.last.body, contains('Levántate, oh Dios'));
      expect(scots.units.expand((u) => u.references), hasLength(176));
      expect(scots.attribution, contains('HombreReformado.org'));
      final ReadingContent scotsPt = await books.read(
        'scots-confession',
        languageCode: 'pt-BR',
      );
      expect(scotsPt.units.map((u) => u.id), scots.units.map((u) => u.id));
      expect(scotsPt.units.first.title, 'Capítulo 1 · De Deus');
      expect(scotsPt.units.last.body, contains('Dá aos teus servos forças'));
      expect(scotsPt.units.expand((u) => u.references), hasLength(176));
      expect(scotsPt.attribution, contains('Franklin Ferreira'));
      final ReadingContent augustine = await books.read(
        'augustine-confessions',
        languageCode: 'es',
      );
      expect(augustine.groups.map((group) => group.units.length), <int>[
        31,
        18,
        21,
        31,
        25,
        26,
        27,
        30,
        37,
        70,
        41,
        43,
        53,
      ]);
      expect(augustine.units.first.id, 'book-1-paragraph-1');
      expect(augustine.units.last.id, 'book-13-paragraph-53');
      expect(augustine.units.first.body, startsWith('Grande eres, Señor'));
      expect(augustine.units.last.body, endsWith('Amén.'));
      expect(
        augustine.attribution,
        allOf(
          contains(
            'Confesiones. Traducción y notas de Alfredo Encuentra Ortega',
          ),
          contains('Editorial Gredos'),
        ),
      );
      const Map<String, String> augustineTitles = <String, String>{
        'es': 'Confesiones de san Agustín',
        'en': 'The Confessions of Saint Augustine',
        'pt': 'Confissões de Santo Agostinho',
      };
      for (final String language in augustineTitles.keys) {
        final ReadingContent translation = await books.read(
          'augustine-confessions',
          languageCode: language,
        );
        expect(translation.languageCode, language);
        expect(translation.title, augustineTitles[language]);
        expect(translation.groups, hasLength(13));
        expect(translation.units, hasLength(language == 'es' ? 453 : 461));
        if (language != 'es') {
          expect(translation.attribution, contains('Pusey'));
        }
        if (language == 'pt') {
          expect(translation.attribution, contains('Une Sacra (unesacra.com)'));
          expect(
            translation.attribution,
            contains('creativecommons.org/licenses/by-nc-sa/4.0/'),
          );
        }
        final ReadingPreview paragraph = await books.readPreview(
          'augustine-confessions',
          languageCode: language,
          unitId: 'book-10-section-70',
        );
        expect(paragraph.title, augustineTitles[language]);
        expect(paragraph.unit.body, translation.groups[9].units.last.body);
      }
      final ReadingPreview late = await books.readPreview(
        'augustine-confessions',
        languageCode: 'es',
        unitId: 'book-10-section-38',
      );
      expect(late.unit.id, 'book-10-paragraph-38');
      expect(late.unit.title, contains('27'));
      expect(late.unit.body, contains('¡Tarde te he amado'));
      final ReadingPreview merged = await books.readPreview(
        'augustine-confessions',
        languageCode: 'es',
        unitId: 'book-1-section-30',
      );
      expect(merged.unit.id, 'book-1-paragraph-26');
      final ReadingPreview split = await books.readPreview(
        'augustine-confessions',
        languageCode: 'pt',
        unitId: 'book-12-paragraph-19',
      );
      expect(split.unit.id, 'book-12-section-18');
      final HomeViewModel home = container<HomeViewModel>();
      await home.initialize(languageCode: 'es');
      expect(
        home.libraryItems
            .singleWhere((item) => item.document.id == 'scots-confession')
            .languageCode,
        'es',
      );
      expect(
        home.libraryItems
            .singleWhere((item) => item.document.id == 'augustine-confessions')
            .sourceTitle,
        augustineTitles['es'],
      );
      home.dispose();

      final ReaderViewModel reader = container<ReaderViewModel>();
      await reader.initialize('belgic-confession');
      reader.select('article-37');
      await reader.pendingWrites;
      expect(reader.favoriteAvailable, isTrue);
      await reader.toggleFavorite();
      await reader.changeTranslation(ReaderTranslation.portuguese);
      expect(reader.unit!.id, 'article-37');
      expect(reader.unit!.title, startsWith('Artigo 37'));
      expect(reader.favorite, isTrue);
      await reader.pendingWrites;
      reader.dispose();
      final ReaderViewModel reopened = container<ReaderViewModel>();
      await reopened.initialize('belgic-confession');
      expect(reopened.unit!.id, 'article-37');
      expect(reopened.favorite, isTrue);
      await reopened.pendingWrites;
      reopened.dispose();

      final ReaderViewModel legacy = container<ReaderViewModel>();
      await legacy.initialize(
        'augustine-confessions',
        unitId: 'book-1-section-30',
      );
      expect(legacy.unit!.id, 'book-1-section-30');
      await legacy.toggleFavorite();
      await legacy.changeTranslation(ReaderTranslation.spanish);
      expect(legacy.unit!.id, 'book-1-paragraph-26');
      expect(legacy.favorite, isTrue);
      await legacy.pendingWrites;
      legacy.dispose();

      final ReaderViewModel restored = container<ReaderViewModel>();
      await restored.initialize('augustine-confessions');
      expect(restored.unit!.id, 'book-1-paragraph-26');
      await restored.changeTranslation(ReaderTranslation.english);
      expect(restored.unit!.id, 'book-1-section-30');
      expect(restored.favorite, isTrue);
      await restored.pendingWrites;
      restored.dispose();
    },
  );
}
