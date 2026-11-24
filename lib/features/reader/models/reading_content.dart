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
    this.editionNotes = '',
    this.facsimile,
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
  final String editionNotes;
  final ReadingFacsimileRange? facsimile;

  String get referenceText =>
      references.join(hasNumberedReferences ? '\n' : ' · ');
}

class ReadingFacsimileRange {
  const ReadingFacsimileRange({
    required this.assetDirectory,
    required this.firstPage,
    required this.lastPage,
  });

  final String assetDirectory;
  final int firstPage;
  final int lastPage;

  String assetPath(int page) => '$assetDirectory/$page.png';
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
