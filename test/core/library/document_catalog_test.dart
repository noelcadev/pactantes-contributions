import 'package:flutter_test/flutter_test.dart';
import 'package:pactantes/core/library/models/reading_document.dart';
import 'package:pactantes/core/library/repository/document_catalog_local_repository.dart';

void main() {
  const DocumentCatalogLocalRepositoryImpl catalog =
      DocumentCatalogLocalRepositoryImpl();
  test('registers historical works and collections with stable IDs', () {
    expect(catalog.all.map((ReadingDocument document) => document.id), <String>[
      'westminster-confession',
      'heidelberg-catechism',
      'canons-of-dort',
      'belgic-confession',
      'scots-confession',
      'augustine-confessions',
      'three-forms-of-unity',
    ]);
    expect(
      catalog.all.map((ReadingDocument document) => document.title),
      <String>[
        'Confesión de Fe de Westminster',
        'Catecismo de Heidelberg',
        'Cánones de Dort',
        'Confesión Belga',
        'Confesión Escocesa de 1560',
        'Confesiones de san Agustín',
        'Las tres formas de unidad',
      ],
    );
    expect(
      catalog.all.map((ReadingDocument document) => document.id).toSet(),
      hasLength(7),
    );
    expect(() => catalog.all.clear(), throwsUnsupportedError);
  });
  test('only books with a bundled reading edition are available', () {
    expect(
      catalog.available.map((ReadingDocument document) => document.id),
      <String>[
        'westminster-confession',
        'heidelberg-catechism',
        'canons-of-dort',
        'belgic-confession',
        'scots-confession',
        'augustine-confessions',
      ],
    );
  });
  test('catalog does not guess edition-specific reading totals', () {
    expect(
      catalog.all.every(
        (ReadingDocument document) => document.totalUnits == null,
      ),
      isTrue,
    );
  });
  test('lookup resolves metadata and safely returns null for unknown IDs', () {
    expect(
      catalog.findById('westminster-confession')?.collectionId,
      'westminster-standards',
    );
    expect(catalog.findById('unknown'), isNull);
  });
  test('filters types independently from collections', () {
    expect(
      catalog.byType(DocumentType.confession).map((item) => item.id),
      <String>[
        'westminster-confession',
        'canons-of-dort',
        'belgic-confession',
        'scots-confession',
      ],
    );
    expect(
      catalog.byType(DocumentType.catechism).single.id,
      'heidelberg-catechism',
    );
    expect(
      catalog.byType(DocumentType.collection).single.id,
      'three-forms-of-unity',
    );
    expect(catalog.byType(DocumentType.creed), isEmpty);
    expect(
      catalog.byType(DocumentType.document).single.id,
      'augustine-confessions',
    );
  });
  test(
    'collection membership references existing entries without duplication',
    () {
      final List<ReadingDocument> members = catalog.inCollection(
        'three-forms-of-unity',
      );
      expect(
        members.map((ReadingDocument document) => document.id).toSet(),
        <String>{'heidelberg-catechism', 'canons-of-dort', 'belgic-confession'},
      );
      expect(members, hasLength(3));
      for (final ReadingDocument member in members) {
        expect(identical(member, catalog.findById(member.id)), isTrue);
        expect(member.type, isNot(DocumentType.collection));
      }
      expect(
        catalog.inCollection('westminster-standards').single.id,
        'westminster-confession',
      );
      expect(catalog.inCollection('unknown'), isEmpty);
    },
  );
}
