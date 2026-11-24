import '../../models/reading_content.dart';

abstract interface class ReadingContentSource {
  Future<ReadingContent> read(
    String documentId, {
    required String languageCode,
  });
}

abstract interface class ReadingPreviewSource implements ReadingContentSource {
  Future<ReadingPreview> readPreview(
    String documentId, {
    required String languageCode,
    String? unitId,
  });
}
