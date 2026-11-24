import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/widgets/edition_credits_sheet.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/reading_content.dart';
import '../models/reader_preferences.dart';
import '../theme/reader_theme.dart';
import '../view_models/reader_view_model.dart';
import 'components/reader_header.dart';
import 'components/reader_bottom_navigation.dart';
import 'components/reader_navigation_sheet.dart';
import 'components/reader_settings_sheet.dart';
import 'components/reader_translation_sheet.dart';

class ReaderView extends StatefulWidget {
  const ReaderView({
    required this.viewModel,
    required this.documentId,
    required this.documentTitle,
    required this.onShare,
    required this.onCopy,
    this.initialUnitId,
    super.key,
  });
  final ReaderViewModel viewModel;
  final String documentId;
  final String documentTitle;
  final String? initialUnitId;
  final Future<void> Function(String text, Rect origin) onShare;
  final Future<void> Function(String text) onCopy;
  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onState);
  }

  String? _languageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String language = Localizations.localeOf(context).languageCode;
    if (_languageCode == language) return;
    final bool firstLoad = _languageCode == null;
    _languageCode = language;
    unawaited(
      firstLoad
          ? widget.viewModel.initialize(
              widget.documentId,
              unitId: widget.initialUnitId,
              languageCode: language,
            )
          : widget.viewModel.reload(languageCode: language),
    );
  }

  void _onState() {
    if (!widget.viewModel.saveError || !mounted) return;
    widget.viewModel.clearSaveError();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _feedback(AppLocalizations.of(context).readerSaveError);
    });
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onState);
    super.dispose();
  }

  void _feedback(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _formatted() {
    final AppLocalizations strings = lookupAppLocalizations(
      Locale(widget.viewModel.content!.languageCode),
    );
    return widget.viewModel.formattedText(
      unitLabel:
          widget.viewModel.unit!.title ??
          strings.question(widget.viewModel.unit!.number),
      questionPrefix: strings.readerQuestionPrefix,
      answerPrefix: strings.readerAnswerPrefix,
      referencesLabel: strings.readerReferences,
      notesLabel: strings.readerEditionNotes,
      attribution: strings.readerAttribution,
    );
  }

  Future<void> _share(AppLocalizations strings, Rect origin) async {
    try {
      await widget.onShare(_formatted(), origin);
    } on Exception {
      if (mounted) _feedback(strings.readerActionError);
    }
  }

  Future<void> _copy(AppLocalizations strings) async {
    try {
      await widget.onCopy(_formatted());
      if (mounted) _feedback(strings.readerCopied);
    } on Exception {
      if (mounted) _feedback(strings.readerActionError);
    }
  }

  Future<void> _navigation(BuildContext context) async {
    final ReaderViewModel vm = widget.viewModel;
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => _sheetSurface(
        context,
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: ReaderNavigationSheet(
            content: vm.content!,
            selectedId: vm.unit!.id,
          ),
        ),
      ),
    );
    if (mounted && selected != null) vm.select(selected);
  }

  Future<void> _translations(BuildContext context) async {
    final ReaderViewModel vm = widget.viewModel;
    final ReadingContent content = vm.content!;
    final ReaderTranslation? selected =
        await showModalBottomSheet<ReaderTranslation>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (BuildContext context) => _sheetSurface(
            context,
            ReaderTranslationSheet(
              selected: vm.preferences.translation,
              availableLanguageCodes: content.availableLanguageCodes,
              resolvedLanguageCode: content.languageCode,
            ),
          ),
        );
    if (mounted && selected != null) {
      await vm.changeTranslation(selected);
    }
  }

  Widget _sheetSurface(BuildContext context, Widget child) => Theme(
    data: ReaderTheme(widget.viewModel.preferences.palette)
        .data(Theme.of(context)),
    child: Builder(
      builder: (BuildContext context) => Material(
        color: ReaderTheme.of(context).background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    ),
  );

  void _settings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => ListenableBuilder(
        listenable: widget.viewModel,
        builder: (BuildContext context, Widget? child) => _sheetSurface(
          context,
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .9,
            ),
            child: ReaderSettingsSheet(
              preferences: widget.viewModel.preferences,
              onChanged: widget.viewModel.updatePreferences,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (BuildContext context, Widget? child) {
      final ReaderViewModel vm = widget.viewModel;
      final ThemeData theme = ReaderTheme(vm.preferences.palette)
          .data(Theme.of(context));
      final Widget reader = Theme(
        data: theme,
        child: Builder(
          builder: (BuildContext context) {
            final AppLocalizations strings = AppLocalizations.of(context);
            final bool ready = vm.state == ReaderState.ready;
            final String? attribution = vm.content?.attribution?.trim();
            return Scaffold(
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: <Widget>[
                    ReaderHeader(
                      enabled: ready,
                      onShare: ready
                          ? (Rect origin) => unawaited(_share(strings, origin))
                          : null,
                      favorite: vm.favorite,
                      favoriteEnabled: vm.favoriteAvailable && !vm.favoriteBusy,
                      onFavorite: () => unawaited(vm.toggleFavorite()),
                      onSettings: () => _settings(context),
                      onTranslation: () => unawaited(_translations(context)),
                      onCopy: () => unawaited(_copy(strings)),
                      onEditionCredits:
                          ready && attribution != null && attribution.isNotEmpty
                          ? () => unawaited(
                              showEditionCreditsSheet(
                                context,
                                attribution: attribution,
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: switch (vm.state) {
                        ReaderState.loading => Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: strings.loadingReadingProgress,
                          ),
                        ),
                        ReaderState.error => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(strings.readerLoadError),
                                TextButton(
                                  onPressed: () => unawaited(vm.reload()),
                                  child: Text(strings.retry),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ReaderState.ready => _ReaderPages(
                          key: ValueKey<String>(
                            '${vm.content!.documentId}:${vm.content!.languageCode}',
                          ),
                          viewModel: vm,
                          onNavigation: () => unawaited(_navigation(context)),
                        ),
                      },
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: ready
                  ? ReaderBottomNavigation(
                      position: vm.index + 1,
                      total: vm.content!.units.length,
                      onPrevious: vm.hasPrevious ? vm.previous : null,
                      onNext: vm.hasNext ? vm.next : null,
                    )
                  : null,
            );
          },
        ),
      );
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarBrightness: theme.brightness,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: reader,
      );
    },
  );
}

class _ReaderPages extends StatefulWidget {
  const _ReaderPages({
    required this.viewModel,
    required this.onNavigation,
    super.key,
  });
  final ReaderViewModel viewModel;
  final VoidCallback onNavigation;

  @override
  State<_ReaderPages> createState() => _ReaderPagesState();
}

class _ReaderPagesState extends State<_ReaderPages> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.viewModel.index;
    _controller = PageController(initialPage: _page);
  }

  bool _programmatic = false;
  int _transition = 0;

  @override
  void didUpdateWidget(_ReaderPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int target = widget.viewModel.index;
    if (_page == target) return;
    _page = target;
    _programmatic = true;
    final int transition = ++_transition;
    final bool reducedMotion = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || transition != _transition || !_controller.hasClients) {
        return;
      }
      if (reducedMotion) {
        _controller.jumpToPage(target);
      } else {
        await _controller.animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      if (mounted && transition == _transition) _programmatic = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<ReadingUnit> units = widget.viewModel.content!.units;
    return PageView.builder(
      controller: _controller,
      physics: const ClampingScrollPhysics(),
      itemCount: units.length,
      onPageChanged: (int index) {
        if (_programmatic) return;
        _page = index;
        widget.viewModel.select(units[index].id);
      },
      itemBuilder: (BuildContext context, int index) => _ReadingPage(
        key: ValueKey<String>(units[index].id),
        viewModel: widget.viewModel,
        unit: units[index],
        isCurrent: index == widget.viewModel.index,
        onNavigation: widget.onNavigation,
      ),
    );
  }
}

class _ReadingPage extends StatefulWidget {
  const _ReadingPage({
    required this.viewModel,
    required this.unit,
    required this.isCurrent,
    required this.onNavigation,
    super.key,
  });
  final ReaderViewModel viewModel;
  final ReadingUnit unit;
  final bool isCurrent;
  final VoidCallback onNavigation;

  @override
  State<_ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<_ReadingPage> {
  late List<GlobalKey> _referenceTargets;
  int? _selectedReference;

  @override
  void initState() {
    super.initState();
    _resetReferences();
  }

  @override
  void didUpdateWidget(_ReadingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unit != oldWidget.unit) {
      _resetReferences();
    } else if (!widget.isCurrent) {
      _selectedReference = null;
    }
  }

  void _resetReferences() {
    final ReadingUnit unit = widget.unit;
    _selectedReference = null;
    _referenceTargets = List<GlobalKey>.generate(
      unit.referenceLinks == null ? 0 : unit.references.length,
      (_) => GlobalKey(),
    );
  }

  void _showReference(int index) {
    if (!widget.isCurrent) return;
    final BuildContext? targetContext = _referenceTargets[index].currentContext;
    final RenderObject? target = targetContext?.findRenderObject();
    if (targetContext == null || target == null) return;

    setState(() => _selectedReference = index);
    // Reveal the note within this page without moving the horizontal reader.
    final ScrollPosition position = Scrollable.of(
      targetContext,
      axis: Axis.vertical,
    ).position;
    unawaited(
      position.ensureVisible(
        target,
        alignment: .2,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReadingUnit unit = widget.unit;
    final ReaderViewModel viewModel = widget.viewModel;
    final ReaderTheme colors = ReaderTheme.of(context);
    final AppLocalizations strings = lookupAppLocalizations(
      Locale(viewModel.content!.languageCode),
    );
    final AppLocalizations interfaceStrings = AppLocalizations.of(context);
    final TextStyle readingStyle = TextStyle(
      fontFamily: 'SourceSerif4',
      fontSize: viewModel.preferences.textSize,
      height: viewModel.preferences.spacing.lineHeight,
      color: colors.primaryText,
    );
    final TextStyle referenceStyle = TextStyle(
      color: colors.reference,
      fontSize: viewModel.preferences.textSize * .8,
      height: viewModel.preferences.spacing.lineHeight,
    );
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    viewModel.content!.title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: .5,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
                _ReadingUnitHeading(
                  unit: unit,
                  strings: strings,
                  onNavigation: widget.onNavigation,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Divider(),
                ),
                if (unit.question != null) ...<Widget>[
                  _ReadingParagraph(
                    prefix: strings.readerQuestionPrefix,
                    text: unit.question!,
                    style: readingStyle.copyWith(fontStyle: FontStyle.italic),
                    calls: unit.referenceLinks?.question ?? const [],
                    strings: interfaceStrings,
                    onReference: _showReference,
                  ),
                  const SizedBox(height: 20),
                ],
                _ReadingParagraph(
                  prefix: unit.question == null
                      ? null
                      : strings.readerAnswerPrefix,
                  text: unit.body,
                  style: readingStyle,
                  calls: unit.referenceLinks?.body ?? const [],
                  strings: interfaceStrings,
                  onReference: _showReference,
                ),
                for (final (String label, Widget text) in <(String, Widget)>[
                  if (unit.references.isNotEmpty)
                    (
                      strings.readerReferences,
                      unit.referenceLinks == null
                          ? Text(unit.referenceText, style: referenceStyle)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                for (final (int index, String reference)
                                    in unit.references.indexed)
                                  _ReadingReferenceRow(
                                    key: _referenceTargets[index],
                                    text: reference,
                                    style: referenceStyle,
                                    selected: index == _selectedReference,
                                  ),
                              ],
                            ),
                    ),
                  if (unit.editionNotes.isNotEmpty)
                    (
                      strings.readerEditionNotes,
                      Text(unit.editionNotes, style: referenceStyle),
                    ),
                ]) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Divider(),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.menu_book_outlined,
                        size: 18,
                        color: colors.reference,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              label,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: colors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            text,
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingUnitHeading extends StatelessWidget {
  const _ReadingUnitHeading({
    required this.unit,
    required this.strings,
    required this.onNavigation,
  });

  final ReadingUnit unit;
  final AppLocalizations strings;
  final VoidCallback onNavigation;

  @override
  Widget build(BuildContext context) {
    final ReaderTheme colors = ReaderTheme.of(context);
    final TextStyle primaryStyle = TextStyle(
      fontFamily: 'SourceSerif4',
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: colors.heading,
    );
    final TextStyle secondaryStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: colors.secondaryText,
    );
    final String? parentTitle = unit.parentTitle;
    final String unitTitle = unit.title ?? strings.question(unit.number);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.center,
          child: Tooltip(
            message: AppLocalizations.of(context).readerNavigation,
            child: TextButton(
              onPressed: onNavigation,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: colors.heading,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      parentTitle ?? unitTitle,
                      textAlign: TextAlign.center,
                      style: primaryStyle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down, size: 18),
                ],
              ),
            ),
          ),
        ),
        if (parentTitle != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(unitTitle, textAlign: TextAlign.center, style: secondaryStyle),
        ],
      ],
    );
  }
}

class _ReadingParagraph extends StatelessWidget {
  static final RegExp _spaceBeforeCall = RegExp(r' $');

  const _ReadingParagraph({
    required this.prefix,
    required this.text,
    required this.style,
    required this.calls,
    required this.strings,
    required this.onReference,
  });
  final String? prefix;
  final String text;
  final TextStyle style;
  final List<ReadingReferenceCall> calls;
  final AppLocalizations strings;
  final ValueChanged<int> onReference;

  Widget _readingText(BuildContext context) {
    if (calls.isEmpty) return Text(text, style: style);

    final ReaderTheme colors = ReaderTheme.of(context);
    final List<InlineSpan> spans = <InlineSpan>[];
    int offset = 0;
    for (final ReadingReferenceCall call in calls) {
      final String marker = text.substring(call.start, call.end);
      // Keep a call with the clause it follows when a narrow line wraps.
      final String preceding = text.substring(offset, call.start);
      spans.add(
        TextSpan(text: preceding.replaceFirst(_spaceBeforeCall, '\u00a0')),
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.aboveBaseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            container: true,
            link: true,
            label: strings.readerReferenceLink(
              marker.substring(0, marker.length - 1),
              call.referenceIndex + 1,
            ),
            onTap: () => onReference(call.referenceIndex),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                excludeFromSemantics: true,
                borderRadius: BorderRadius.circular(4),
                focusColor: colors.selectedBackground,
                onTap: () => onReference(call.referenceIndex),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 3,
                    right: 3,
                    bottom: style.fontSize! * .14,
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      marker,
                      style: style.copyWith(
                        color: colors.heading,
                        fontSize: style.fontSize! * .72,
                        fontStyle: FontStyle.normal,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      offset = call.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return Text.rich(TextSpan(children: spans), style: style);
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (prefix != null)
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            prefix!,
            style: TextStyle(
              fontSize: style.fontSize,
              height: style.height,
              color: ReaderTheme.of(context).accent,
            ),
          ),
        ),
      Expanded(child: _readingText(context)),
    ],
  );
}

class _ReadingReferenceRow extends StatelessWidget {
  const _ReadingReferenceRow({
    required super.key,
    required this.text,
    required this.style,
    required this.selected,
  });

  final String text;
  final TextStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ReaderTheme colors = ReaderTheme.of(context);
    return Semantics(
      container: true,
      selected: selected ? true : null,
      liveRegion: selected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: selected ? colors.selectedBackground : null,
          border: Border.all(
            color: selected ? colors.accent : Colors.transparent,
          ),
        ),
        child: Text(
          text,
          style: selected
              ? style.copyWith(
                  color: colors.selectedForeground,
                  fontWeight: FontWeight.w600,
                )
              : style,
        ),
      ),
    );
  }
}
