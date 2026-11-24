import 'dart:convert';

import '../../../core/preferences/preferences_store.dart';

abstract interface class ReaderFavoritesLocalRepository {
  Future<bool> contains(
    String documentId,
    String unitId, {
    Iterable<String> alternateUnitIds = const <String>[],
  });
  Future<void> setFavorite(
    String documentId,
    String unitId,
    bool favorite, {
    Iterable<String> alternateUnitIds = const <String>[],
  });
}

class ReaderFavoritesLocalRepositoryImpl
    implements ReaderFavoritesLocalRepository {
  ReaderFavoritesLocalRepositoryImpl(this._store);
  final PreferencesStore _store;
  Future<void> _pending = Future<void>.value();
  static const String key = 'reader_favorites';
  Future<Set<String>> _read() async {
    final String? raw = await _store.readString(key);
    if (raw == null) return <String>{};
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?> ||
        decoded.any((Object? value) => value is! String)) {
      throw const FormatException('Invalid favorites');
    }
    return decoded.cast<String>().toSet();
  }

  String _id(String documentId, String unitId) =>
      jsonEncode(<String>[documentId, unitId]);
  @override
  Future<bool> contains(
    String documentId,
    String unitId, {
    Iterable<String> alternateUnitIds = const <String>[],
  }) async {
    await _pending;
    final Set<String> values = await _read();
    return values.contains(_id(documentId, unitId)) ||
        alternateUnitIds.any(
          (String id) => values.contains(_id(documentId, id)),
        );
  }

  @override
  Future<void> setFavorite(
    String documentId,
    String unitId,
    bool favorite, {
    Iterable<String> alternateUnitIds = const <String>[],
  }) {
    final Future<void> operation = _pending.then((_) async {
      final Set<String> values = await _read();
      if (favorite) {
        values.add(_id(documentId, unitId));
      } else {
        values.remove(_id(documentId, unitId));
        values.removeAll(
          alternateUnitIds.map((String id) => _id(documentId, id)),
        );
      }
      await _store.writeString(key, jsonEncode(values.toList()));
    });
    _pending = operation.then(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }
}
