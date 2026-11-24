import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactantes/core/library/models/reading_document.dart';
import 'package:pactantes/core/reading_progress/models/reading_progress.dart';
import 'package:pactantes/design_system/theme/app_theme.dart';
import 'package:pactantes/design_system/widgets/edition_credits_sheet.dart';
import 'package:pactantes/features/home/models/home_reading_item.dart';
import 'package:pactantes/features/home/views/components/home_action.dart';
import 'package:pactantes/features/home/views/components/reading_section.dart';
import 'package:pactantes/features/reader/models/reader_preferences.dart';
import 'package:pactantes/features/reader/models/reading_content.dart';
import 'package:pactantes/features/reader/theme/reader_theme.dart';
import 'package:pactantes/l10n/generated/app_localizations.dart';

const ReadingDocument _document = ReadingDocument(
  id: 'study-document',
  title: 'Study document',
  type: DocumentType.confession,
  isAvailable: true,
);
const ReadingUnit _excerpt = ReadingUnit(
  id: 'article-1',
  number: 1,
  body: 'First article from the source edition.',
);
final ReadingProgress _progress = ReadingProgress(
  documentId: _document.id,
  sectionId: _excerpt.id,
  paragraph: 1,
  progress: .21,
  lastReadAt: DateTime.utc(2026),
);
const String _notice =
    'Author and edition. Source https://example.com/edition\n'
    'License https://creativecommons.org/licenses/by/4.0/';

Widget _app(
  Widget child, {
  ThemeData? theme,
  Locale locale = const Locale('en'),
  double textScale = 2,
}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'credits and reading are distinct actions on a narrow excerpt card',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<HomeReadingItem> opened = <HomeReadingItem>[];
      final HomeReadingItem item = HomeReadingItem(
        document: _document,
        progress: _progress,
        unit: _excerpt,
        attribution: _notice,
      );
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: ReadingSection(
              title: 'Study',
              items: <HomeReadingItem>[
                item,
                const HomeReadingItem(document: _document, unit: _excerpt),
              ],
              onOpen: opened.add,
            ),
          ),
        ),
      );

      final Finder credits = find.widgetWithText(TextButton, 'Edition credits');
      final Finder cards = find.byType(HomeAction);
      expect(
        tester.getSize(cards.first).height,
        tester.getSize(cards.last).height,
      );
      final Finder article = find.text('Study document').first;
      final Finder card = find.widgetWithText(InkWell, 'Study document').first;
      expect(credits, findsOneWidget);
      await tester.ensureVisible(credits);
      await tester.pumpAndSettle();
      expect(tester.getSize(credits).height, greaterThanOrEqualTo(48));
      final SemanticsNode creditsNode = tester.getSemantics(credits);
      final SemanticsNode readingNode = tester.getSemantics(card);
      expect(creditsNode.id, isNot(readingNode.id));
      expect(
        creditsNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        readingNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(credits);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, _notice), findsOneWidget);
      expect(opened, isEmpty);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(article);
      await tester.tap(article);
      expect(opened, <HomeReadingItem>[item]);
    },
  );

  testWidgets('resume stays at the trailing edge on long and short cards', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        ReadingSection(
          title: 'Continuar leyendo',
          items: <HomeReadingItem>[
            HomeReadingItem(
              document: _document,
              progress: _progress,
              unit: const ReadingUnit(
                id: 'article-1',
                number: 1,
                parentTitle: 'A long chapter heading that spans several lines',
                title: 'Article 1',
                body: 'An excerpt from the source edition.',
              ),
              attribution: _notice,
            ),
            HomeReadingItem(
              document: _document,
              progress: _progress,
              unit: _excerpt,
              attribution: _notice,
            ),
          ],
        ),
        locale: const Locale('es'),
        textScale: 1,
      ),
    );
    await tester.pumpAndSettle();

    final Finder cards = find.byType(HomeAction);
    const String resume = 'Retomar estudio';
    final Finder labels = find.text(resume);
    final Finder arrows = find.byIcon(Icons.chevron_right);
    final Finder bars = find.byType(LinearProgressIndicator);
    for (int index = 0; index < 2; index++) {
      final RenderParagraph label = tester.renderObject(labels.at(index));
      final List<TextBox> lines = label.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: resume.length),
      );
      final Rect arrow = tester.getRect(arrows.at(index));
      final Rect bar = tester.getRect(bars.at(index));
      expect(lines, hasLength(1));
      final double textEnd = label
          .localToGlobal(Offset(lines.single.right, 0))
          .dx;
      expect(arrow.left - textEnd, closeTo(4, .5));
      expect(arrow.right, closeTo(bar.right, .01));
    }
    expect(
      tester.getSize(cards.first).height,
      tester.getSize(cards.last).height,
    );
    expect(tester.getCenter(arrows.first).dy, tester.getCenter(arrows.last).dy);
    await tester.binding.setSurfaceSize(const Size(700, 800));
    await tester.pump();
    final Rect percentage = tester.getRect(find.text('21% COMPLETADO').first);
    final Rect bar = tester.getRect(bars.first);
    final Rect arrow = tester.getRect(arrows.first);
    expect(percentage.left, closeTo(bar.left, .01));
    expect(percentage.center.dy, closeTo(arrow.center.dy, .5));
    expect(arrow.right, closeTo(bar.right, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card without an excerpt does not show edition credits', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ReadingSection(
          title: 'Study',
          items: <HomeReadingItem>[
            HomeReadingItem(document: _document, attribution: _notice),
          ],
        ),
      ),
    );

    expect(find.byType(EditionCreditsButton), findsNothing);
  });

  testWidgets(
    'the credits sheet keeps reader colors and scrolls long notices',
    (WidgetTester tester) async {
      const ReaderTheme readerTheme = ReaderTheme(ReaderPalette.dark);
      final String attribution = List<String>.filled(20, _notice).join('\n\n');
      await tester.pumpWidget(
        _app(
          Center(child: EditionCreditsButton(attribution: attribution)),
          theme: readerTheme.data(AppTheme.light),
        ),
      );

      await tester.tap(find.byType(EditionCreditsButton));
      await tester.pumpAndSettle();
      final Finder sheet = find.byType(BottomSheet);
      expect(
        tester.widget<BottomSheet>(sheet).backgroundColor,
        readerTheme.background,
      );
      final Finder scrollable = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable.first, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable.first).position.pixels,
        greaterThan(0),
      );
      expect(find.widgetWithText(SelectableText, attribution), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    },
  );
}
