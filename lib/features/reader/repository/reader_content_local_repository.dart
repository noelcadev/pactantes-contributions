import '../models/reading_content.dart';
import 'sources/reading_content_source.dart';

abstract interface class ReaderContentLocalRepository {
  Future<ReadingContent> read(String documentId, {String languageCode = 'es'});
  Future<ReadingPreview> readPreview(
    String documentId, {
    String languageCode = 'es',
    String? unitId,
  });
}

class ReaderContentLocalRepositoryImpl implements ReaderContentLocalRepository {
  ReaderContentLocalRepositoryImpl(Map<String, ReadingContentSource> sources)
    : _sources = Map<String, ReadingContentSource>.unmodifiable(sources);

  final Map<String, ReadingContentSource> _sources;

  ReadingContentSource _source(String documentId) {
    final ReadingContentSource? source = _sources[documentId];
    if (source == null) throw const UnsupportedReadingDocumentException();
    return source;
  }

  String _language(String languageCode) {
    final String requested = languageCode
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first;
    return <String>{'en', 'es', 'pt'}.contains(requested) ? requested : 'pt';
  }

  @override
  Future<ReadingContent> read(
    String documentId, {
    String languageCode = 'es',
  }) async {
    return _source(documentId)
        .read(documentId, languageCode: _language(languageCode));
  }

  @override
  Future<ReadingPreview> readPreview(
    String documentId, {
    String languageCode = 'es',
    String? unitId,
  }) async {
    final ReadingContentSource source = _source(documentId);
    final String language = _language(languageCode);
    if (source is ReadingPreviewSource) {
      return source.readPreview(
        documentId,
        languageCode: language,
        unitId: unitId,
      );
    }
    final ReadingContent content = await source.read(
      documentId,
      languageCode: language,
    );
    return content.preview(unitId);
  }
}

class UnsupportedReadingDocumentException implements Exception {
  const UnsupportedReadingDocumentException();
}
