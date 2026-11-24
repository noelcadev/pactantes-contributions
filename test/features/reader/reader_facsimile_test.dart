import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactantes/core/preferences/preferences_store.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/repository/reader_content_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_favorites_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_preferences_local_repository.dart';
import 'package:pactantes/features/reader/repository/reader_progress_local_repository.dart';
import 'package:pactantes/features/reader/repository/sources/reading_content_source.dart';
import 'package:pactantes/features/reader/view_models/reader_view_model.dart';
import 'package:pactantes/features/reader/views/reader_view.dart';
import 'package:pactantes/l10n/generated/app_localizations.dart';

const String _documentId = 'augustine-confessions';
const String _selectedId = 'book-1-paragraph-2';
const String _assetDirectory = 'assets/facsimiles/test-augustine';

class _MemoryStore implements PreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

class _EditionSource implements ReadingContentSource {
  @override
  Future<ReadingContent> read(
    String documentId, {
    required String languageCode,
  }) async => ReadingContent(
    documentId: documentId,
    title: 'Confessions',
    languageCode: languageCode,
    units: <ReadingUnit>[
      const ReadingUnit(
        id: 'book-1-paragraph-1',
        number: 1,
        body: 'Other text',
      ),
      ReadingUnit(
        id: _selectedId,
        number: 2,
        body: 'Selected passage',
        facsimile: languageCode == 'es'
            ? const ReadingFacsimileRange(
                assetDirectory: _assetDirectory,
                firstPage: 111,
                lastPage: 112,
              )
            : null,
      ),
    ],
  );
}

class _TestBundle extends CachingAssetBundle {
  final Set<String> unavailable = <String>{};
  final List<String> requested = <String>[];

  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(_assetDirectory)) return rootBundle.load(key);
    requested.add(key);
    if (unavailable.contains(key)) {
      throw FlutterError('Missing test scan: $key');
    }
    return ByteData.sublistView(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAwAAAASCAAAAABKwmDQAAAAEklEQVR4nGP8wIAATEjsYccBAOvOARSeRqt2AAAAAElFTkSuQmCC',
      ),
    );
  }
}

Future<void> _openReader(
  WidgetTester tester,
  _TestBundle bundle,
  Locale locale,
  ReaderViewModel reader,
) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.65)),
          child: child!,
        ),
        home: ReaderView(
          viewModel: reader,
          documentId: _documentId,
          documentTitle: 'Confessions',
          initialUnitId: _selectedId,
          onShare: (_, _) async {},
          onCopy: (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finishImage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() async {
    final Finder finder = find.byType(Image);
    final Image image = tester.widget<Image>(finder);
    await precacheImage(
      image.image,
      tester.element(finder),
      onError: (_, _) {},
    );
  });
  await tester.pumpAndSettle();
}

Finder _pageButton(String tooltip) => find.byWidgetPredicate(
  (Widget widget) => widget is IconButton && widget.tooltip == tooltip,
);

void main() {
  late ReaderPreferencesLocalRepository preferences;
  late ReaderProgressLocalRepository progress;
  late ReaderViewModel reader;
  late _TestBundle bundle;

  void createFixture() {
    final _MemoryStore store = _MemoryStore();
    progress = ReaderProgressLocalRepositoryImpl(store);
    preferences = ReaderPreferencesLocalRepositoryImpl(store);
    reader = ReaderViewModel(
      ReaderContentLocalRepositoryImpl(<String, ReadingContentSource>{
        _documentId: _EditionSource(),
      }),
      preferences,
      ReaderFavoritesLocalRepositoryImpl(store),
      progress,
    );
    bundle = _TestBundle();
    addTearDown(reader.dispose);
  }

  testWidgets(
    'opens only the passage pages, zooms, and returns to the same passage',
    (tester) async {
      createFixture();
      await _openReader(tester, bundle, const Locale('es'), reader);
      await tester.tap(find.text('Ver páginas originales'));
      await _finishImage(tester);
      expect(find.text('Página del PDF 111'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(_pageButton('Página anterior del PDF'))
            .onPressed,
        isNull,
      );
      expect(bundle.requested, <String>['$_assetDirectory/111.png']);

      final Finder viewport = find.byType(InteractiveViewer);
      final Offset center = tester.getCenter(viewport);
      final TestGesture left = await tester.startGesture(
        center.translate(-35, 0),
        pointer: 1,
      );
      final TestGesture right = await tester.startGesture(
        center.translate(35, 0),
        pointer: 2,
      );
      await left.moveTo(center.translate(-80, 0));
      await right.moveTo(center.translate(80, 0));
      await tester.pump();
      expect(
        tester
            .widgetList<Transform>(
              find.descendant(of: viewport, matching: find.byType(Transform)),
            )
            .any((transform) => transform.transform.getMaxScaleOnAxis() > 1),
        isTrue,
      );
      await left.up();
      await right.up();

      final Finder next = _pageButton('Página siguiente del PDF');
      final VoidCallback advance = tester.widget<IconButton>(next).onPressed!;
      await tester.tap(next);
      advance();
      await _finishImage(tester);
      expect(find.text('Página del PDF 112'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(_pageButton('Página siguiente del PDF'))
            .onPressed,
        isNull,
      );
      expect(bundle.requested, <String>[
        '$_assetDirectory/111.png',
        '$_assetDirectory/112.png',
      ]);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Selected passage'), findsOneWidget);
      expect(reader.unit?.id, _selectedId);
      await reader.pendingWrites;
      expect(await progress.readUnit(_documentId), _selectedId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows a localized page error and retries the same bundled asset',
    (tester) async {
      createFixture();
      await preferences.save(
        const ReaderPreferences(translation: ReaderTranslation.spanish),
      );
      await _openReader(tester, bundle, const Locale('pt'), reader);
      final String path = '$_assetDirectory/111.png';
      bundle.unavailable.add(path);
      await tester.tap(find.text('Ver páginas originais'));
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível abrir esta página do PDF.'),
        findsOneWidget,
      );
      expect(find.text('Página do PDF 111'), findsOneWidget);

      bundle.unavailable.remove(path);
      await tester.tap(find.text('Tentar novamente'));
      await _finishImage(tester);
      expect(
        find.text('Não foi possível abrir esta página do PDF.'),
        findsNothing,
      );
      expect(
        bundle.requested.where((key) => key == path).length,
        greaterThan(1),
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeps the reader action hidden for a passage without originals',
    (tester) async {
      createFixture();
      await _openReader(tester, bundle, const Locale('en'), reader);
      expect(find.text('Selected passage'), findsOneWidget);
      expect(find.text('View original pages'), findsNothing);
      expect(bundle.requested, isEmpty);
    },
  );
}
