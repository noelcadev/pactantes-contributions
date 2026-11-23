import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../models/reader_preferences.dart';
import 'reader_sheet_header.dart';

class ReaderTranslationSheet extends StatelessWidget {
  const ReaderTranslationSheet({
    required this.selected,
    this.title,
    this.availableLanguageCodes,
    this.resolvedLanguageCode,
    super.key,
  });
  final ReaderTranslation selected;
  final String? title;
  final Set<String>? availableLanguageCodes;
  final String? resolvedLanguageCode;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final Map<ReaderTranslation, String> labels = <ReaderTranslation, String>{
      ReaderTranslation.device: strings.readerDeviceLanguage,
      ReaderTranslation.english: strings.readerEnglish,
      ReaderTranslation.portuguese: strings.readerPortuguese,
      ReaderTranslation.spanish: strings.readerSpanish,
    };
    final List<ReaderTranslation> options = ReaderTranslation.values.where((
      ReaderTranslation translation,
    ) {
      final String? code = translation.languageCode;
      return code == null || availableLanguageCodes?.contains(code) != false;
    }).toList();
    final ReaderTranslation resolved = options.firstWhere(
      (ReaderTranslation translation) =>
          translation.languageCode == resolvedLanguageCode,
      orElse: () => ReaderTranslation.device,
    );
    final ReaderTranslation displayedSelection = options.contains(selected)
        ? selected
        : resolved;
    final bool deviceUsesFallback =
        selected == ReaderTranslation.device &&
        resolved != ReaderTranslation.device &&
        availableLanguageCodes?.contains(
              Localizations.localeOf(context).languageCode,
            ) ==
            false;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ReaderSheetHeader(title: title ?? strings.readerTranslation),
            for (final ReaderTranslation translation in options)
              ListTile(
                title: Text(labels[translation]!),
                subtitle:
                    deviceUsesFallback &&
                        translation == ReaderTranslation.device
                    ? Text(strings.readerCurrentEdition(labels[resolved]!))
                    : null,
                selected: displayedSelection == translation,
                trailing: displayedSelection == translation
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(translation),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
