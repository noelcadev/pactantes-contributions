class ReadingUnit {
  const ReadingUnit({
    required this.id,
    required this.number,
    required this.body,
    this.title,
    this.question,
    this.parentId,
    this.parentTitle,
    this.references = const <String>[],
    this.hasNumberedReferences = false,
    this.referenceLinks,
    this.editionNotes = '',
  });
  final String id;
  final int number;
  final String? title;
  final String? question;
  final String body;
  final String? parentId;
  final String? parentTitle;
  final List<String> references;
  final bool hasNumberedReferences;
  final ReadingReferenceLinks? referenceLinks;
  final String editionNotes;

  String get referenceText =>
      references.join(hasNumberedReferences ? '\n' : ' · ');
}

typedef ReadingReferenceCall = ({int start, int end, int referenceIndex});

class ReadingReferenceLinks {
  const ReadingReferenceLinks._({required this.question, required this.body});

  final List<ReadingReferenceCall> question;
  final List<ReadingReferenceCall> body;

  static final RegExp _call = RegExp(
    r'(?<![\p{L}\p{N}_(])(ll|[a-zñ])\)',
    unicode: true,
  );
  static final RegExp _reference = RegExp(r'^(ll|[a-zñ])\)\s+\S');

  /// Pair full sequences to keep repeated letters attached to their own note.
  static ReadingReferenceLinks? fromLetteredNotes({
    required String? question,
    required String body,
    required List<String> references,
  }) {
    if (references.isEmpty) return null;
    final List<RegExpMatch> questionCalls = _call
        .allMatches(question ?? '')
        .toList();
    final List<RegExpMatch> bodyCalls = _call.allMatches(body).toList();
    final List<RegExpMatch> calls = <RegExpMatch>[
      ...questionCalls,
      ...bodyCalls,
    ];
    if (calls.isEmpty) return null;

    final Set<String> calledLabels = <String>{
      for (final RegExpMatch call in calls) call[1]!,
    };
    final List<(int, String)> linkedReferences = <(int, String)>[];
    for (final (int index, String reference) in references.indexed) {
      final String? label = _reference.firstMatch(reference)?[1];
      if (label == null) return null;
      if (calledLabels.contains(label)) linkedReferences.add((index, label));
    }
    if (calls.length != linkedReferences.length) return null;

    final List<ReadingReferenceCall> ordered = <ReadingReferenceCall>[];
    for (final (int position, RegExpMatch call) in calls.indexed) {
      final (int index, String label) = linkedReferences[position];
      if (call[1] != label) return null;
      ordered.add((start: call.start, end: call.end, referenceIndex: index));
    }
    return ReadingReferenceLinks._(
      question: List<ReadingReferenceCall>.unmodifiable(
        ordered.take(questionCalls.length),
      ),
      body: List<ReadingReferenceCall>.unmodifiable(
        ordered.skip(questionCalls.length),
      ),
    );
  }
}

typedef ReadingPreview = ({
  String title,
  String languageCode,
  String? attribution,
  ReadingUnit unit,
});

class ReadingContent {
  const ReadingContent({
    required this.documentId,
    required this.title,
    required this.languageCode,
    required this.units,
    this.canonicalUnitIds = const <String>[],
    this.unitAliases = const <String, String>{},
    this.availableLanguageCodes = const <String>{'en', 'pt', 'es'},
    this.attribution,
  });
  final String documentId;
  final String title;
  final String languageCode;
  final List<ReadingUnit> units;
  final List<String> canonicalUnitIds;

  /// Maps alternate passage IDs to units in this edition.
  final Map<String, String> unitAliases;

  final Set<String> availableLanguageCodes;
  final String? attribution;

  ReadingPreview preview(String? unitId) {
    if (units.isEmpty) throw const FormatException('Empty document');
    return (
      title: title,
      languageCode: languageCode,
      attribution: attribution,
      unit: units[resolveUnitIndex(unitId)],
    );
  }

  int resolveUnitIndex(String? unitId) {
    final Map<String, int> positions = <String, int>{
      for (final (int index, ReadingUnit unit) in units.indexed) unit.id: index,
    };
    if (positions[unitId] case final int index) return index;
    if (positions[unitAliases[unitId]] case final int index) return index;
    final int canonicalIndex = unitId == null
        ? -1
        : canonicalUnitIds.indexOf(unitId);
    if (canonicalIndex < 0) return 0;
    for (final String id in canonicalUnitIds.skip(canonicalIndex + 1)) {
      if (positions[id] case final int index) return index;
    }
    for (final String id
        in canonicalUnitIds.take(canonicalIndex).toList().reversed) {
      if (positions[id] case final int index) return index;
    }
    return 0;
  }

  List<String> aliasesFor(String unitId) => <String>[
    for (final MapEntry<String, String> alias in unitAliases.entries)
      if (alias.value == unitId && !units.any((unit) => unit.id == alias.key))
        alias.key,
  ];

  List<ReadingGroup> get groups {
    final Map<String, List<ReadingUnit>> grouped =
        <String, List<ReadingUnit>>{};
    for (final ReadingUnit unit in units) {
      grouped.putIfAbsent(unit.parentId ?? '', () => <ReadingUnit>[]).add(unit);
    }
    return <ReadingGroup>[
      for (final List<ReadingUnit> group in grouped.values)
        ReadingGroup(
          title: group.first.parentTitle,
          units: List<ReadingUnit>.unmodifiable(group),
        ),
    ];
  }
}

class ReadingGroup {
  const ReadingGroup({required this.title, required this.units});
  final String? title;
  final List<ReadingUnit> units;
}
