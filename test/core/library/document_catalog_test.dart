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
      'westminster-larger-catechism',
      'canons-of-dort',
      'belgic-confession',
      'scots-confession',
      'nicene-creed',
      'augustine-confessions',
      'three-forms-of-unity',
    ]);
    expect(
      catalog.all.map((ReadingDocument document) => document.title),
      <String>[
        'Confesión de Fe de Westminster',
        'Catecismo de Heidelberg',
        'Catecismo mayor de Westminster',
        'Cánones de Dort',
        'Confesión Belga',
        'Confesión Escocesa de 1560',
        'Credo Niceno',
        'Confesiones de san Agustín',
        'Las tres formas de unidad',
      ],
    );
    expect(
      catalog.all.map((ReadingDocument document) => document.id).toSet(),
      hasLength(9),
    );
    expect(() => catalog.all.clear(), throwsUnsupportedError);
  });
  test('only books with a bundled reading edition are available', () {
    expect(
      catalog.available.map((ReadingDocument document) => document.id),
      <String>[
        'westminster-confession',
        'heidelberg-catechism',
        'westminster-larger-catechism',
        'canons-of-dort',
        'belgic-confession',
        'scots-confession',
        'nicene-creed',
        'augustine-confessions',
      ],
    );
  });
  test('catalog leaves edition-specific reading totals unresolved', () {
    expect(catalog.findById('heidelberg-catechism')?.totalUnits, isNull);
    expect(catalog.findById('westminster-larger-catechism')?.totalUnits, 196);
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
      catalog.byType(DocumentType.catechism).map((item) => item.id),
      <String>['heidelberg-catechism', 'westminster-larger-catechism'],
    );
    expect(
      catalog.byType(DocumentType.collection).single.id,
      'three-forms-of-unity',
    );
    expect(catalog.byType(DocumentType.creed).single.id, 'nicene-creed');
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
        catalog.inCollection('westminster-standards').map((item) => item.id),
        <String>['westminster-confession', 'westminster-larger-catechism'],
      );
      expect(catalog.inCollection('unknown'), isEmpty);
    },
  );
}
