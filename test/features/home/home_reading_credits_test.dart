import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactantes/core/library/models/reading_document.dart';
import 'package:pactantes/design_system/theme/app_theme.dart';
import 'package:pactantes/design_system/widgets/edition_credits_sheet.dart';
import 'package:pactantes/features/home/models/home_reading_item.dart';
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
const String _notice =
    'Author and edition. Source https://example.com/edition\n'
    'License https://creativecommons.org/licenses/by/4.0/';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: const TextScaler.linear(2)),
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
      const HomeReadingItem item = HomeReadingItem(
        document: _document,
        unit: _excerpt,
        attribution: _notice,
      );
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: ReadingSection(
              title: 'Study',
              items: const <HomeReadingItem>[
                item,
                HomeReadingItem(document: _document, unit: _excerpt),
              ],
              onOpen: opened.add,
            ),
          ),
        ),
      );

      final Finder credits = find.widgetWithText(TextButton, 'Edition credits');
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
