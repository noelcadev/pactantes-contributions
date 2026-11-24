import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pactantes/app/dependency_injection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pactantes/core/database/sqflite_reading_database.dart';
import 'package:pactantes/core/preferences/preferences_store.dart';
import 'package:pactantes/core/library/repository/document_catalog_local_repository.dart';
import 'package:pactantes/features/home/view_models/home_view_model.dart';
import 'package:pactantes/features/home/repository/reading_progress_local_repository.dart';
import 'package:pactantes/core/preferences/shared_preferences_reader.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/repository/reader_content_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_preferences_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_favorites_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_progress_local_repository.dart';
import 'package:pactantes/features/reader/services/reading_share_formatter.dart';
import 'package:pactantes/features/reader/view_models/reader_view_model.dart';
import 'package:pactantes/features/reader/views/reader_view.dart';
import 'package:pactantes/features/reader/views/components/reader_navigation_sheet.dart';
import 'package:pactantes/features/reader/views/components/reader_header.dart';
import 'package:pactantes/features/reader/views/components/reader_settings_sheet.dart';
import 'package:pactantes/features/reader/theme/reader_theme.dart';
import 'package:pactantes/l10n/generated/app_localizations.dart';

class MemoryStore implements PreferencesStore {
  final Map<String, String> values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> readString(String key) async => values[key];
  @override
  Future<void> writeString(String key, String value) async {
    if (fail) throw const PreferencesWriteException();
    values[key] = value;
  }
}

const ReadingContent sample = ReadingContent(
  documentId: 'sample',
  canonicalUnitIds: <String>['a', 'b', 'c'],
  title: 'Document',
  languageCode: 'es',
  units: <ReadingUnit>[
    ReadingUnit(
      id: 'a',
      number: 1,
      question: 'Complete question?',
      body: 'First paragraph.\n\nSecond paragraph.',
      parentId: 'day-a',
      parentTitle: 'Day A',
      references: <String>['Romans 1:1', 'John 1:1'],
    ),
    ReadingUnit(
      id: 'c',
      number: 3,
      question: 'Another question?',
      body: 'Answer.',
      parentId: 'day-b',
      parentTitle: 'Day B',
    ),
  ],
);

class ContentRepository implements ReaderContentLocalRepository {
  @override
  Future<ReadingPreview> readPreview(
    String documentId, {
    String languageCode = 'es',
    String? unitId,
  }) async =>
      (await read(documentId, languageCode: languageCode)).preview(unitId);

  bool fail = false;
  ReadingContent document = sample;
  String? requestedLanguage;
  final Map<String, ReadingContent> translations = <String, ReadingContent>{};
  @override
  Future<ReadingContent> read(String id, {String languageCode = 'es'}) async {
    requestedLanguage = languageCode;
    if (fail) throw const FormatException();
    return translations[languageCode] ?? document;
  }
}

class Fixture {
  final MemoryStore store = MemoryStore();
  final ContentRepository content = ContentRepository();
  ReaderViewModel model() => ReaderViewModel(
    content,
    ReaderPreferencesLocalRepositoryImpl(store),
    ReaderFavoritesLocalRepositoryImpl(store),
    ReaderProgressLocalRepositoryImpl(store),
  );
}

String format(ReadingContent document, ReadingUnit unit) =>
    const ReadingShareFormatter().format(
      document: document,
      unit: unit,
      unitLabel: unit.title ?? 'Pregunta ${unit.number}',
      questionPrefix: 'P.',
      answerPrefix: 'R.',
      referencesLabel: 'Referencias bíblicas:',
      attribution: 'Shared from Pactantes.',
    );

Future<void> render(
  WidgetTester tester,
  ReaderViewModel model, {
  Locale locale = const Locale('es'),
  ValueChanged<String>? copied,
  String? initialUnitId,
  void Function(String text, Rect origin)? shared,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReaderView(
        viewModel: model,
        documentId: 'sample',
        documentTitle: sample.title,
        initialUnitId: initialUnitId,
        onShare: (String text, Rect origin) async {
          shared?.call(text, origin);
        },
        onCopy: (String text) async {
          copied?.call(text);
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Home and reader validate and normalize the same progress records',
    () async {
      final MemoryStore store = MemoryStore();
      store.values['reading_progress'] = jsonEncode(<Object>[
        <String, Object>{'documentId': 'sample', 'sectionId': 'b'},
        <String, Object>{
          'documentId': ' sample ',
          'sectionId': ' c ',
          'paragraph': 1,
          'progress': .5,
          'lastReadAt': '2026-11-14T00:00:00Z',
        },
        <String, Object>{
          'documentId': 'unrelated',
          'sectionId': 'article-2',
          'paragraph': 2,
          'progress': .2,
          'lastReadAt': '2026-11-13T00:00:00Z',
        },
      ]);
      final ReadingProgressLocalRepository home =
          ReadingProgressLocalRepositoryImpl(store);
      final ReaderProgressLocalRepository reader =
          ReaderProgressLocalRepositoryImpl(store);
      expect(await reader.readUnit('sample'), 'c');
      expect((await home.read()).first.sectionId, 'c');
      await reader.save(
        documentId: 'sample',
        unitId: 'a',
        title: 'A',
        progress: .1,
      );
      expect((await home.read()).map((record) => record.documentId), <String>[
        'sample',
        'unrelated',
      ]);
      expect(await reader.readUnit('unrelated'), 'article-2');
    },
  );

  test(
    'a fresh reader restores an omitted canonical unit to its successor',
    () async {
      final Fixture fixture = Fixture();
      await ReaderProgressLocalRepositoryImpl(fixture.store)
          .save(documentId: 'sample', unitId: 'b', title: 'B', progress: .5);
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      await model.initialize('sample');
      expect(model.unit!.id, 'c');
      await model.pendingWrites;
      expect(
        await ReaderProgressLocalRepositoryImpl(fixture.store)
            .readUnit('sample'),
        'c',
      );
    },
  );

  test('reader settings survive a new repository and plugin adapter', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ReaderPreferencesLocalRepository repository =
        ReaderPreferencesLocalRepositoryImpl(
          SharedPreferencesReader(SharedPreferences.getInstance),
        );
    expect((await repository.read()).textSize, 20);
    await repository.save(
      const ReaderPreferences(
        palette: ReaderPalette.paper,
        textSize: 27,
        spacing: ReadingSpacing.wide,
      ),
    );
    final ReaderPreferences restored =
        await ReaderPreferencesLocalRepositoryImpl(
          SharedPreferencesReader(SharedPreferences.getInstance),
        ).read();
    expect(restored.palette, ReaderPalette.paper);
    expect(restored.textSize, 27);
    expect(restored.spacing.lineHeight, 1.9);
  });

  test(
    'malformed preferences fall back and numeric sizes are bounded',
    () async {
      final MemoryStore store = MemoryStore();
      final ReaderPreferencesLocalRepository repository =
          ReaderPreferencesLocalRepositoryImpl(store);
      store.values[ReaderPreferencesLocalRepositoryImpl.key] = '{';
      expect((await repository.read()).textSize, 20);
      store.values[ReaderPreferencesLocalRepositoryImpl.key] =
          '{"textSize":100,"theme":"invalid","spacing":"invalid"}';
      final ReaderPreferences value = await repository.read();
      expect(value.textSize, 36);
      expect(value.palette, ReaderPalette.light);
      expect(value.spacing, ReadingSpacing.normal);
      expect(value.copyWith(textSize: 1).textSize, 14);
    },
  );

  test('share includes exact complete text, all references and paragraphs', () {
    expect(
      format(sample, sample.units.first),
      '*Document*\n\n_Day A · Pregunta 1_\n\n*P. Complete question?*\n\nR. First paragraph.\n\nSecond paragraph.\n\n*Referencias bíblicas:*\nRomans 1:1\nJohn 1:1\n\n_Shared from Pactantes._',
    );
    final String longText = List<String>.filled(
      500,
      'Exact original words.',
    ).join('\n');
    final ReadingUnit unit = ReadingUnit(id: 'long', number: 9, body: longText);
    expect(format(sample, unit), contains(longText));
    expect(format(sample, unit), isNot(contains('Referencias')));
    expect(format(sample, unit), isNot(contains('null')));
    expect(format(sample, unit), isNot(contains(' · ')));
  });

  test(
    'grouping uses real parent identities and retains edition numbering',
    () {
      expect(sample.groups.map((ReadingGroup group) => group.title), <String>[
        'Day A',
        'Day B',
      ]);
      expect(sample.groups.last.units.single.number, 3);
      const ReadingContent ungrouped = ReadingContent(
        documentId: 'x',
        title: 'Creed',
        languageCode: 'es',
        units: <ReadingUnit>[
          ReadingUnit(id: 'x', number: 1, body: 'Text', title: 'Article I'),
        ],
      );
      expect(ungrouped.groups.single.title, isNull);
      expect(
        format(ungrouped, ungrouped.units.single),
        contains('_Article I_'),
      );
    },
  );

  test(
    'favorites store identifiers only, preserve other units, serialize writes',
    () async {
      final MemoryStore store = MemoryStore();
      final ReaderFavoritesLocalRepository repository =
          ReaderFavoritesLocalRepositoryImpl(store);
      await Future.wait(<Future<void>>[
        repository.setFavorite('sample', 'a', true),
        repository.setFavorite('sample', 'c', true),
      ]);
      expect(
        await ReaderFavoritesLocalRepositoryImpl(store).contains('sample', 'a'),
        isTrue,
      );
      expect(await repository.contains('other', 'a'), isFalse);
      await repository.setFavorite('sample', 'a', false);
      expect(await repository.contains('sample', 'a'), isFalse);
      expect(await repository.contains('sample', 'c'), isTrue);
      expect(
        jsonDecode(store.values[ReaderFavoritesLocalRepositoryImpl.key]!),
        <String>[
          jsonEncode(<String>['sample', 'c']),
        ],
      );
    },
  );

  test(
    'boundaries, favorites and restored position follow actual unit IDs',
    () async {
      final Fixture fixture = Fixture();
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      await model.initialize('sample');
      expect(model.hasPrevious, isFalse);
      model.previous();
      expect(model.unit!.id, 'a');
      await model.toggleFavorite();
      expect(model.favorite, isTrue);
      model.next();
      await model.pendingWrites;
      expect(model.unit!.id, 'c');
      expect(model.hasNext, isFalse);
      model.next();
      model.select('missing');
      expect(model.unit!.id, 'c');
      final ReaderViewModel restored = fixture.model();
      addTearDown(restored.dispose);
      await restored.initialize('sample');
      expect(restored.unit!.id, 'c');
      expect(restored.favorite, isFalse);
      restored.previous();
      await Future<void>.delayed(Duration.zero);
      expect(restored.favorite, isTrue);
      await restored.pendingWrites;
    },
  );

  test(
    'rapid preferences persist in order and favorites report write failure',
    () async {
      final Fixture fixture = Fixture();
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      await model.initialize('sample');
      model.updatePreferences(model.preferences.copyWith(textSize: 21));
      model.updatePreferences(
        model.preferences.copyWith(textSize: 22, palette: ReaderPalette.dark),
      );
      await model.pendingWrites;
      expect(
        (await ReaderPreferencesLocalRepositoryImpl(
          fixture.store,
        ).read()).textSize,
        22,
      );
      fixture.store.fail = true;
      await model.toggleFavorite();
      expect(model.favorite, isFalse);
      expect(model.saveError, isTrue);
      expect(model.favoriteBusy, isFalse);
    },
  );

  testWidgets(
    'reader isolates controls, settings apply live, copy uses full formatter',
    (WidgetTester tester) async {
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);
      final ReaderViewModel model = Fixture().model();
      addTearDown(model.dispose);
      String? copied;
      await render(tester, model, copied: (String text) => copied = text);
      expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
      final IconButton previous = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is IconButton && widget.tooltip == 'Unidad anterior',
        ),
      );
      expect(previous.onPressed, isNull);
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar texto'));
      await tester.pumpAndSettle();
      expect(copied, contains(sample.units.first.body));
      expect(find.text('Texto copiado'), findsOneWidget);
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustes de lectura'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsSheet), findsOneWidget);
      await tester.tap(find.text('A+'));
      await tester.pumpAndSettle();
      expect(model.preferences.textSize, 21);
      final Text question = tester.widget<Text>(
        find.text('Complete question?'),
      );
      expect(question.style!.fontSize, 21);
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();
      expect(model.preferences.palette, ReaderPalette.dark);
      expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.light,
      );
      expect(
        ReaderTheme.of(tester.element(find.byType(ReaderSettingsSheet)))
            .background,
        const Color(0xFF1B222A),
      );
      await tester.tap(find.text('Papel'));
      await tester.pumpAndSettle();
      expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsSheet), findsNothing);
      expect(model.unit!.id, 'a');
      await model.pendingWrites;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'navigation dismisses without moving and selection immediately navigates',
    (WidgetTester tester) async {
      final ReaderViewModel model = Fixture().model();
      addTearDown(model.dispose);
      await render(tester, model);
      await tester.tap(find.byTooltip('Navegación del documento'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderNavigationSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(model.unit!.id, 'a');
      await tester.tap(find.byTooltip('Navegación del documento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(model.unit!.id, 'c');
      expect(find.byType(ReaderNavigationSheet), findsNothing);
      expect(find.text('Another question?').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (Widget widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Unidad siguiente',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await model.pendingWrites;
    },
  );

  testWidgets('late navigation units open visible at phone width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Fixture fixture = Fixture();
    fixture.content.document = ReadingContent(
      documentId: 'sample',
      title: 'Document',
      languageCode: 'es',
      units: <ReadingUnit>[
        for (int i = 1; i <= 100; i++)
          ReadingUnit(
            id: 'unit-$i',
            number: i,
            body: 'Text',
            parentId: 'day-$i',
            parentTitle: 'Day $i',
          ),
      ],
    );
    final ReaderViewModel model = fixture.model();
    addTearDown(model.dispose);
    await render(tester, model);
    model.select('unit-100');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Navegación del documento'));
    await tester.pumpAndSettle();
    expect(find.text('100').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await model.pendingWrites;
  });

  test(
    'content failures and empty editions expose a recoverable state',
    () async {
      final Fixture fixture = Fixture();
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      fixture.content.fail = true;
      await model.initialize('sample');
      expect(model.state, ReaderState.error);
      expect(model.hasNext, isFalse);
      fixture.content.fail = false;
      fixture.content.document = const ReadingContent(
        documentId: 'sample',
        title: 'Empty',
        languageCode: 'es',
        units: <ReadingUnit>[],
      );
      await model.initialize('sample');
      expect(model.state, ReaderState.error);
      fixture.content.document = sample;
      await model.initialize('sample');
      expect(model.state, ReaderState.ready);
      await model.pendingWrites;
    },
  );

  testWidgets(
    'reader follows the resolved device language and updates when it changes',
    (WidgetTester tester) async {
      final Fixture fixture = Fixture();
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      Future<void> renderLocale(Locale locale) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReaderView(
              viewModel: model,
              documentId: 'sample',
              documentTitle: sample.title,
              onShare: (String text, Rect origin) async {},
              onCopy: (String text) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await renderLocale(const Locale('en', 'US'));
      expect(fixture.content.requestedLanguage, 'en');
      model.next();
      await tester.pumpAndSettle();
      await renderLocale(const Locale('pt', 'BR'));
      expect(fixture.content.requestedLanguage, 'pt');
      expect(model.unit!.id, 'c');
      await model.pendingWrites;
    },
  );

  testWidgets(
    'minimal header opens the index and document title is editorial',
    (WidgetTester tester) async {
      final ReaderViewModel model = Fixture().model();
      addTearDown(model.dispose);
      await render(tester, model);
      final Finder header = find.byType(ReaderHeader);
      expect(
        find.descendant(of: header, matching: find.byType(TextButton)),
        findsNothing,
      );
      expect(find.text('DOCUMENT'), findsOneWidget);
      expect(
        tester.getCenter(find.text('DOCUMENT')).dx,
        closeTo(tester.getCenter(header).dx, .5),
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byIcon(Icons.format_list_bulleted),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Day A'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderNavigationSheet), findsOneWidget);
      await model.pendingWrites;
    },
  );

  testWidgets(
    'retry after an edition change reopens the last displayed passage',
    (WidgetTester tester) async {
      final Fixture fixture = Fixture();
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      await render(tester, model, initialUnitId: 'a');
      model.select('c');
      fixture.content.fail = true;
      await model.changeTranslation(ReaderTranslation.english);
      await tester.pumpAndSettle();
      expect(model.state, ReaderState.error);
      fixture.content.fail = false;
      await tester.tap(
        find.text(lookupAppLocalizations(const Locale('es')).retry),
      );
      await tester.pumpAndSettle();
      expect(model.state, ReaderState.ready);
      expect(model.unit?.id, 'c');
      await model.pendingWrites;
    },
  );

  test('translation selection persists and device mode follows the next device locale', () async {
    final Fixture fixture = Fixture();
    final ReaderViewModel model = fixture.model();
    addTearDown(model.dispose);
    await model.initialize('sample', languageCode: 'es');
    model.next();
    await model.changeTranslation(ReaderTranslation.english);
    expect(fixture.content.requestedLanguage, 'en');
    expect(model.unit!.id, 'c');
    expect(
      (await ReaderPreferencesLocalRepositoryImpl(
        fixture.store,
      ).read()).translation,
      ReaderTranslation.english,
    );
    final ReaderViewModel restored = fixture.model();
    addTearDown(restored.dispose);
    await restored.initialize('sample', languageCode: 'pt');
    expect(fixture.content.requestedLanguage, 'en');
    await restored.changeTranslation(ReaderTranslation.device);
    expect(fixture.content.requestedLanguage, 'pt');
    await restored.pendingWrites;
  });

  test('translation changes choose the next available canonical unit when one is absent', () async {
    final Fixture fixture = Fixture();
    fixture.content.translations['en'] = const ReadingContent(
      documentId: 'sample',
      title: 'English',
      languageCode: 'en',
      units: <ReadingUnit>[
        ReadingUnit(id: 'a', number: 1, body: 'A'),
        ReadingUnit(id: 'b', number: 2, body: 'B'),
        ReadingUnit(id: 'c', number: 3, body: 'C'),
      ],
    );
    final ReaderViewModel model = fixture.model();
    addTearDown(model.dispose);
    await model.initialize('sample', languageCode: 'en');
    model.select('b');
    await model.changeTranslation(ReaderTranslation.spanish);
    expect(model.unit!.id, 'c');
    await model.pendingWrites;
  });

  testWidgets(
    'translation menu switches source text and preserves the interface language',
    (WidgetTester tester) async {
      final Fixture fixture = Fixture();
      fixture.content.translations['en'] = const ReadingContent(
        documentId: 'sample',
        title: 'English edition',
        languageCode: 'en',
        units: <ReadingUnit>[
          ReadingUnit(
            id: 'a',
            number: 1,
            question: 'English question?',
            body: 'English answer.',
            parentId: 'day-a',
            parentTitle: 'English grouping',
          ),
        ],
      );
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      String? shared;
      Rect? origin;
      await render(
        tester,
        model,
        shared: (String text, Rect rect) {
          shared = text;
          origin = rect;
        },
      );
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Traducción'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inglés'));
      await tester.pumpAndSettle();
      expect(find.text('English question?'), findsOneWidget);
      expect(find.text('ENGLISH EDITION'), findsOneWidget);
      expect(find.text('Question 1'), findsOneWidget);
      expect(find.byTooltip('Más opciones'), findsOneWidget);
      expect(model.unit!.id, 'a');
      await tester.tap(find.byTooltip('Compartir'));
      await tester.pumpAndSettle();
      expect(shared, contains('*English edition*'));
      expect(shared, contains('English question?'));
      expect(shared, contains('Question 1'));
      expect(origin!.isEmpty, isFalse);
      await model.pendingWrites;
    },
  );

  testWidgets(
    'left swipes advance, right swipes return and boundaries stop navigation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ReaderViewModel model = Fixture().model();
      addTearDown(model.dispose);
      await render(tester, model);
      await tester.drag(find.text('Complete question?'), const Offset(250, 0));
      await tester.pumpAndSettle();
      expect(model.index, 0);
      await tester.drag(find.text('Complete question?'), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(model.index, 1);
      await tester.drag(find.text('Another question?'), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(model.index, 1);
      await tester.drag(find.text('Another question?'), const Offset(250, 0));
      await tester.pumpAndSettle();
      expect(model.index, 0);
      await tester.drag(find.text('Complete question?'), const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(model.index, 0);
      expect(tester.takeException(), isNull);
      await model.pendingWrites;
    },
  );

  testWidgets('pages follow the finger and animate bottom navigation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ReaderViewModel model = Fixture().model();
    addTearDown(model.dispose);
    await render(tester, model);
    final Finder question = find.text('Complete question?');
    final double initialX = tester.getTopLeft(question).dx;
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(question),
    );
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(tester.getTopLeft(question).dx, lessThan(initialX - 50));
    await gesture.moveBy(const Offset(-160, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(model.index, 1);
    final PageController controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    await tester.tap(find.byTooltip('Unidad anterior'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.page!, greaterThan(0));
    expect(controller.page!, lessThan(1));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(model.index, 0);
    await model.pendingWrites;
  });

  testWidgets(
    'Spanish excerpts include the edition credits on an English device',
    (WidgetTester tester) async {
      final Fixture fixture = Fixture();
      const String editionCredits =
          'Spanish edition. Source: https://example.com/edition\n'
          'CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/';
      fixture.content.document = const ReadingContent(
        documentId: 'sample',
        title: 'Edición española',
        languageCode: 'es',
        attribution: editionCredits,
        units: <ReadingUnit>[
          ReadingUnit(
            id: 'a',
            number: 1,
            question: 'Pregunta de prueba?',
            body: 'Respuesta de prueba.',
            parentTitle: 'Día del Señor 1',
            references: <String>['Romanos 3:9'],
          ),
        ],
      );
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      String? shared;
      String? copied;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderView(
            viewModel: model,
            documentId: 'sample',
            documentTitle: 'Sample',
            onShare: (String text, Rect origin) async {
              shared = text;
            },
            onCopy: (String text) async {
              copied = text;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(shared, contains('Día del Señor 1 · Pregunta 1'));
      expect(shared, contains('*P. Pregunta de prueba?*'));
      expect(shared, contains('R. Respuesta de prueba.'));
      expect(shared, contains('*Referencias bíblicas:*'));
      expect(shared, contains(editionCredits));
      expect(shared, contains('Compartido desde Pactantes'));
      expect(shared, isNot(contains('Question')));
      expect(shared, isNot(contains('Biblical references')));
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edition credits'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, editionCredits),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy text'));
      await tester.pumpAndSettle();
      expect(copied, shared);
      await model.pendingWrites;
    },
  );

  testWidgets(
    'translation options reflect the available editions and preserve saved preferences',
    (WidgetTester tester) async {
      final Fixture fixture = Fixture();
      final ReaderPreferencesLocalRepository preferences =
          ReaderPreferencesLocalRepositoryImpl(fixture.store);
      await preferences.save(
        const ReaderPreferences(translation: ReaderTranslation.portuguese),
      );
      fixture.content.document = const ReadingContent(
        documentId: 'sample',
        title: 'Spanish edition',
        languageCode: 'es',
        availableLanguageCodes: <String>{'en', 'es'},
        units: <ReadingUnit>[
          ReadingUnit(id: 'a', number: 1, title: 'Artículo 1', body: 'Texto.'),
        ],
      );
      final ReaderViewModel model = fixture.model();
      addTearDown(model.dispose);
      const Locale locale = Locale('pt', 'BR');
      final AppLocalizations strings = lookupAppLocalizations(
        const Locale('pt'),
      );
      await render(tester, model, locale: locale);

      Future<void> openTranslations() async {
        await tester.tap(find.byTooltip(strings.moreOptions));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.readerTranslation));
        await tester.pumpAndSettle();
      }

      await openTranslations();
      expect(find.text(strings.readerPortuguese), findsNothing);
      expect(find.text(strings.readerEnglish), findsOneWidget);
      final ListTile spanish = tester.widget<ListTile>(
        find.widgetWithText(ListTile, strings.readerSpanish),
      );
      expect(spanish.selected, isTrue);
      expect(
        (await preferences.read()).translation,
        ReaderTranslation.portuguese,
      );

      await tester.tap(find.text(strings.readerDeviceLanguage));
      await tester.pumpAndSettle();
      await openTranslations();
      final ListTile device = tester.widget<ListTile>(
        find.widgetWithText(ListTile, strings.readerDeviceLanguage),
      );
      expect(device.selected, isTrue);
      expect(
        find.text(strings.readerCurrentEdition(strings.readerSpanish)),
        findsOneWidget,
      );
      expect((await preferences.read()).translation, ReaderTranslation.device);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a corpus upgrade removes the editorial notes from the active catechism',
    () async {
      sqfliteFfiInit();
      final Directory directory = await Directory.systemTemp.createTemp(
        'pactantes_reader_test',
      );
      final DatabaseFactory factory = databaseFactoryFfi;
      final String previous = await factory.getDatabasesPath();
      await factory.setDatabasesPath(directory.path);
      try {
        final String oldPath = '${directory.path}/reformed_documents_v10.db';
        // Representative old rows let the test verify both the new corpus and
        // the old file after opening the reader.
        final Database oldCorpus = await factory.openDatabase(oldPath);
        await oldCorpus.execute('PRAGMA user_version = 7');
        await oldCorpus.execute(
          'CREATE TABLE historical_units (document_key TEXT, unit_id TEXT, '
          'reference_text TEXT, edition_notes TEXT)',
        );
        await oldCorpus.insert('historical_units', <String, Object?>{
          'document_key': 'westminster_larger_catechism_es',
          'unit_id': 'question-58',
          'reference_text': 'o) Tit. 3:5, 6; Juan 16:7, 8.',
          'edition_notes': 'Previous editorial note',
        });
        await oldCorpus.execute(
          'CREATE TABLE heidelberg_catechism '
          '(language_code TEXT, question_number INTEGER, answer TEXT)',
        );
        await oldCorpus.insert('heidelberg_catechism', <String, Object?>{
          'language_code': 'en',
          'question_number': 1,
          'answer': 'Old truncated answer',
        });
        await oldCorpus.execute(
          'CREATE TABLE document_sources '
          '(document_key TEXT PRIMARY KEY, title TEXT, attribution TEXT)',
        );
        await oldCorpus.insert('document_sources', <String, Object?>{
          'document_key': 'augustine_confessions_es',
          'title': 'Confesiones',
          'attribution': 'Old edition credits',
        });
        await oldCorpus.close();
        final SqfliteReadingDatabase database = SqfliteReadingDatabase(
          factory,
          rootBundle,
        );
        final ReaderContentLocalRepository repository =
            createReaderContentRepository(database);
        final ReadingContent larger = await repository.read(
          'westminster-larger-catechism',
        );
        final ReadingContent creed = await repository.read('nicene-creed');
        expect(larger.units, hasLength(196));
        expect(larger.units.last.id, 'question-196');
        expect(larger.units[57].referenceText, contains('Juan 16:7'));
        expect(larger.units[57].editionNotes, isEmpty);
        expect(creed.units.single.id, 'creed');
        final ReadingContent document = await repository.read(
          'heidelberg-catechism',
        );
        expect(document.units, hasLength(128));
        final ReadingContent augustine = await repository.read(
          'augustine-confessions',
          languageCode: 'es',
        );
        expect(augustine.title, 'Confesiones de san Agustín');
        expect(augustine.units, hasLength(453));
        expect(
          document.attribution,
          allOf(
            contains('Aviso de esa edición: “Used by permission'),
            contains('Reformed Church in America'),
            contains('Book of Praise'),
            endsWith(
              'https://www.crcna.org/sites/default/files/'
              'Catecismo%20de%20Heidelberg.pdf',
            ),
          ),
        );
        expect(
          format(document, document.units.first),
          contains(document.attribution),
        );
        expect(await File(oldPath).exists(), isTrue);
        final Database preservedCorpus = await factory.openDatabase(
          oldPath,
          options: OpenDatabaseOptions(readOnly: true),
        );
        expect(
          (await preservedCorpus.query('historical_units'))
              .single['edition_notes'],
          'Previous editorial note',
        );
        expect(
          (await preservedCorpus.rawQuery(
            "SELECT answer FROM heidelberg_catechism WHERE language_code = 'en' AND question_number = 1",
          )).single['answer'],
          'Old truncated answer',
        );
        expect(
          (await preservedCorpus.query(
            'document_sources',
            columns: <String>['title'],
            where: 'document_key = ?',
            whereArgs: <Object?>['augustine_confessions_es'],
          )).single['title'],
          'Confesiones',
        );
        await preservedCorpus.close();

        for (final String language in <String>['en', 'pt']) {
          final ReadingContent localized = await repository.read(
            'heidelberg-catechism',
            languageCode: language,
          );
          expect(localized.languageCode, language);
          expect(localized.units, hasLength(129));
          expect(
            localized.attribution,
            allOf(
              contains('Book of Praise'),
              contains(
                language == 'en'
                    ? '© 1973, 1978, 1984 Biblica'
                    : 'Marcos Vasconcelos',
              ),
              contains('https://www.heidelberg-catechism.com/pdf/'),
            ),
          );
          expect(
            format(localized, localized.units.first),
            contains(localized.attribution),
          );
          final ReadingUnit twelve = localized.units[11];
          final String exodus = language == 'en' ? 'Exodus' : 'Êxodo';
          final String romans = language == 'en' ? 'Romans' : 'Romanos';
          final String isaiah = language == 'en' ? 'Isaiah' : 'Isaías';
          expect(twelve.body, contains('.¹ '));
          expect(twelve.body, endsWith('.²'));
          final String notes =
              '¹ $exodus 20:5 · $exodus 23:7 · $romans 2:1–11\n'
              '² $isaiah 53:11 · $romans 8:3 · $romans 8:4';
          expect(twelve.referenceText, notes);
          expect(format(localized, twelve), contains(notes));
          expect(localized.units[46].question, endsWith('¹'));
          expect(localized.units[22].body, contains('1.'));
          expect(
            localized.units[70].body,
            contains(language == 'en' ? '28:19' : '28.19'),
          );
          if (language == 'en') {
            expect(localized.units[91].body, contains('1. You shall'));
            expect(localized.units[91].body, endsWith('.¹'));
            expect(
              localized.units.first.question,
              'What is your only comfort in life and death?',
            );
            expect(
              localized.units.first.body,
              contains('my faithful Saviour Jesus Christ.³'),
            );
            expect(
              localized.units.first.body,
              endsWith('from now on to live for him.¹⁰'),
            );
            expect(
              format(localized, localized.units.first),
              contains(localized.units.first.body),
            );
          }
          if (language == 'pt') {
            expect(localized.units[41].body, endsWith('.²'));
            expect(localized.units[41].referenceText, startsWith('João'));
            expect(localized.units[31].body, contains('unção,²'));
            expect(localized.units[91].hasNumberedReferences, isFalse);
          }

          expect(localized.groups, hasLength(52));
          expect(localized.units.last.id, document.units.last.id);
          expect(localized.units[79].id, 'question-80');
          expect(
            localized.units.first.question,
            contains(language == 'en' ? 'What' : 'Qual'),
          );
          expect(
            localized.units.first.parentTitle,
            startsWith(language == 'en' ? 'Lord' : 'Dia do Senhor'),
          );
          expect(
            localized.units.first.references.any(
              (String reference) => reference.contains(
                language == 'en' ? 'Corinthians' : 'Coríntios',
              ),
            ),
            isTrue,
          );
        }

        expect(document.groups, hasLength(52));
        expect(document.units[11].body, endsWith('por algún otro.'));
        expect(document.units[11].body, isNot(contains('¹')));
        expect(document.units.first.references, isNotEmpty);
        expect(document.units.last.number, 128);
        expect(document.units[79].id, 'question-81');
        expect(document.units[79].number, 80);
        final MemoryStore progressStore = MemoryStore();
        final ReaderPreferencesLocalRepository preferences =
            ReaderPreferencesLocalRepositoryImpl(progressStore);
        final ReaderProgressLocalRepository progress =
            ReaderProgressLocalRepositoryImpl(progressStore);
        final ReaderContentLocalRepository content = createReaderContentRepository(
          database,
        );
        await preferences.save(
          const ReaderPreferences(translation: ReaderTranslation.english),
        );
        final ReaderViewModel english = ReaderViewModel(
          content,
          preferences,
          ReaderFavoritesLocalRepositoryImpl(progressStore),
          progress,
        );
        await english.initialize('heidelberg-catechism', unitId: 'question-80');
        await english.pendingWrites;
        english.dispose();
        final HomeViewModel home = HomeViewModel(
          ReadingProgressLocalRepositoryImpl(progressStore),
          const DocumentCatalogLocalRepositoryImpl(),
          readerPreferencesRepository: preferences,
          readerContentRepository: content,
        );
        await home.initialize(languageCode: 'en');
        expect(await home.changeTranslation(ReaderTranslation.spanish), isTrue);
        expect(home.readingItems.single.unit!.id, 'question-81');
        expect(await progress.readUnit('heidelberg-catechism'), 'question-80');
        final ReaderViewModel spanish = ReaderViewModel(
          content,
          preferences,
          ReaderFavoritesLocalRepositoryImpl(progressStore),
          progress,
        );
        await spanish.initialize('heidelberg-catechism');
        expect(spanish.unit!.id, 'question-81');
        await spanish.pendingWrites;
        expect(await progress.readUnit('heidelberg-catechism'), 'question-81');
        spanish.dispose();
        home.dispose();

        final ReadingContent reopened = await createReaderContentRepository(
          SqfliteReadingDatabase(factory, rootBundle),
        ).read('heidelberg-catechism');
        expect(reopened.units.last.body, document.units.last.body);
        final Database handle = await factory.openDatabase(
          '${directory.path}/reformed_documents_v11.db',
          options: OpenDatabaseOptions(readOnly: true),
        );
        await handle.close();
      } finally {
        await factory.setDatabasesPath(previous);
        await directory.delete(recursive: true);
      }
    },
  );
}
