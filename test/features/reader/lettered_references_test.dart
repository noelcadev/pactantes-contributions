import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactantes/core/database/reading_database.dart';
import 'package:pactantes/core/preferences/preferences_store.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/repository/reader_content_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_favorites_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_preferences_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_progress_local_repository.dart';
import 'package:pactantes/features/reader/repository/sources/historical_reading_content_source.dart';
import 'package:pactantes/features/reader/repository/sources/reading_content_source.dart';
import 'package:pactantes/features/reader/view_models/reader_view_model.dart';
import 'package:pactantes/features/reader/views/reader_view.dart';
import 'package:pactantes/l10n/generated/app_localizations.dart';

const String _westminster = 'westminster-larger-catechism';
const String _otherDocument = 'other';
const String _question = '¿Cuál es la primera nota? a)';
const String _firstReference = 'a) Juan 1:1.';
const String _unlinkedReference = 'x) Romanos 3:3.';
const String _secondReference = 'a) Lucas 2:2.';
const String _thirdReference = 'ñ) Marcos 3:3.';
const String _fourthReference = 'll) Mateo 4:4.';
const String _firstLink = 'Abrir referencia bíblica a, nota 1';
const String _secondLink = 'Abrir referencia bíblica a, nota 3';
const String _thirdLink = 'Abrir referencia bíblica ñ, nota 4';
const String _fourthLink = 'Abrir referencia bíblica ll, nota 5';
final String _body =
    'Respuesta con nota repetida. a)\n\n'
    'Segundo párrafo con cita (Juan 3:4). ñ) 1) Con otra nota. ll)\n\n'
    'Párrafo que separa las referencias para comprobar el desplazamiento. '
    '${List<String>.filled(10, 'El pasaje continúa con más texto. ').join()}';

class _HistoricalDatabase implements ReadingDatabase {
  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> arguments = const <Object?>[],
  ]) async {
    if (sql.contains('FROM historical_editions')) {
      final bool westminster = arguments.first == _westminster;
      final String language = arguments[1]! as String;
      return <Map<String, Object?>>[
        for (final String code in <String>[
          language,
          if (language == 'es') 'en',
        ])
          <String, Object?>{
            'document_key': westminster
                ? 'westminster_larger_catechism_$code'
                : 'other_$code',
            'title': 'Catecismo',
            'language_code': code,
            'attribution': 'Edición de prueba',
            'source_url': 'https://example.org',
          },
      ];
    }
    if (sql.contains('FROM historical_unit_aliases')) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      <String, Object?>{
        'unit_id': 'question-1',
        'position': 1,
        'title': 'Pregunta 1',
        'group_id': 'part',
        'group_title': 'Parte',
        'question': _question,
        'body': _body,
        'reference_text': const <String>[
          _firstReference,
          _unlinkedReference,
          _secondReference,
          _thirdReference,
          _fourthReference,
        ].join('\n'),
        'edition_notes': '',
      },
      <String, Object?>{
        'unit_id': 'question-2',
        'position': 2,
        'title': 'Pregunta 2',
        'group_id': 'part',
        'group_title': 'Parte',
        'question': '¿Otra pregunta?',
        'body': 'La llamada b) queda en el texto.',
        'reference_text': 'a) Romanos 5:5.',
        'edition_notes': '',
      },
    ];
  }
}

class _MemoryStore implements PreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

Future<ReaderViewModel> _renderReader(
  WidgetTester tester, {
  String documentId = _westminster,
  ValueChanged<String>? onCopy,
  double scale = 1,
}) async {
  final HistoricalReadingContentSource source = HistoricalReadingContentSource(
    _HistoricalDatabase(),
  );
  final _MemoryStore store = _MemoryStore();
  final ReaderViewModel model = ReaderViewModel(
    ReaderContentLocalRepositoryImpl(<String, ReadingContentSource>{
      documentId: source,
    }),
    ReaderPreferencesLocalRepositoryImpl(store),
    ReaderFavoritesLocalRepositoryImpl(store),
    ReaderProgressLocalRepositoryImpl(store),
  );
  addTearDown(model.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ReaderView(
        viewModel: model,
        documentId: documentId,
        documentTitle: 'Catecismo',
        onShare: (String text, Rect origin) async {},
        onCopy: (String text) async => onCopy?.call(text),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

bool _selected(WidgetTester tester, String text) =>
    tester
        .getSemantics(find.text(text))
        .getSemanticsData()
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

void main() {
  test('lettered calls preserve offsets and reject misaligned sequences', () {
    const String question = 'ñ) ¿Qué quiere decir “(a)” (Juan 1:1)?';
    const String body = 'Palabras. a)\n\n1) Otra parte. ll)';
    final ReadingReferenceLinks links = ReadingReferenceLinks.fromLetteredNotes(
      question: question,
      body: body,
      references: const <String>[
        'ñ) Marcos 1:1.',
        'a) Juan 1:1.',
        'll) Mateo 1:1.',
      ],
    )!;
    expect(links.question.single.start, 0);
    expect(
      links.body.map((ReadingReferenceCall call) => call.referenceIndex),
      <int>[1, 2],
    );
    expect(
      links.body.map(
        (ReadingReferenceCall call) => body.substring(call.start, call.end),
      ),
      <String>['a)', 'll)'],
    );
    expect(
      ReadingReferenceLinks.fromLetteredNotes(
        question: question,
        body: body,
        references: const <String>[
          'ñ) Marcos 1:1.',
          'll) Mateo 1:1.',
          'a) Juan 1:1.',
        ],
      ),
      isNull,
    );
  });

  testWidgets('touch and screen-reader links select each repeated note', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ReaderViewModel model = await _renderReader(tester, scale: 1.8);

    final Finder first = find.bySemanticsLabel(_firstLink);
    final Finder second = find.bySemanticsLabel(_secondLink);
    expect(
      tester.getSemantics(first).getSemanticsData().flagsCollection.isLink,
      isTrue,
    );
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text(_firstReference).hitTestable(), findsOneWidget);
    expect(_selected(tester, _firstReference), isTrue);

    await tester.ensureVisible(second);
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel(_secondLink));
    await tester.pumpAndSettle();
    expect(find.text(_secondReference).hitTestable(), findsOneWidget);
    expect(_selected(tester, _firstReference), isFalse);
    expect(_selected(tester, _secondReference), isTrue);
    expect(_selected(tester, _unlinkedReference), isFalse);
    expect(model.unit?.id, 'question-1');

    final Finder fourth = find.bySemanticsLabel(_fourthLink);
    await tester.ensureVisible(fourth);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(_thirdLink), findsOneWidget);
    await tester.tap(fourth);
    await tester.pumpAndSettle();
    expect(find.text(_fourthReference).hitTestable(), findsOneWidget);
    expect(_selected(tester, _fourthReference), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard links work and selection clears on unit or edition change',
    (WidgetTester tester) async {
      String? copied;
      final ReaderViewModel model = await _renderReader(
        tester,
        onCopy: (String text) => copied = text,
      );

      final Finder first = find.bySemanticsLabel(_firstLink);
      bool focused() =>
          tester
              .getSemantics(first)
              .getSemanticsData()
              .flagsCollection
              .isFocused ==
          Tristate.isTrue;
      for (int tab = 0; tab < 12 && !focused(); tab++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(focused(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_selected(tester, _firstReference), isTrue);

      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar texto'));
      await tester.pumpAndSettle();
      expect(copied, contains(_question));
      expect(copied, contains(_body));
      expect(
        copied,
        contains('$_firstReference\n$_unlinkedReference\n$_secondReference'),
      );

      model.next();
      await tester.pumpAndSettle();
      expect(find.text('La llamada b) queda en el texto.'), findsOneWidget);
      expect(find.text('a) Romanos 5:5.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Abrir referencia bíblica')),
        findsNothing,
      );

      model.previous();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(_firstReference));
      await tester.pumpAndSettle();
      expect(_selected(tester, _firstReference), isFalse);

      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(_selected(tester, _firstReference), isTrue);

      await model.changeTranslation(ReaderTranslation.english);
      await tester.pumpAndSettle();
      expect(find.text(_question), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Abrir referencia bíblica')),
        findsNothing,
      );

      await model.changeTranslation(ReaderTranslation.spanish);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(_firstReference));
      await tester.pumpAndSettle();
      expect(_selected(tester, _firstReference), isFalse);
      expect(find.textContaining('Notas de la edición'), findsNothing);
    },
  );

  testWidgets('historical documents outside this Spanish edition stay plain', (
    WidgetTester tester,
  ) async {
    await _renderReader(tester, documentId: _otherDocument);
    expect(find.text(_question), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
  });
}
