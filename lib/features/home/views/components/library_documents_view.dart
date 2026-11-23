import 'package:flutter/material.dart';

import '../../../../core/library/models/reading_document.dart';
import '../../../../design_system/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../models/home_reading_item.dart';
import '../../view_models/home_view_model.dart';

class LibraryDocumentsView extends StatelessWidget {
  const LibraryDocumentsView({
    required this.title,
    required this.category,
    required this.viewModel,
    required this.onOpenReading,
    super.key,
  });

  final String title;
  final DocumentType? category;
  final HomeViewModel viewModel;
  final ValueChanged<HomeReadingItem>? onOpenReading;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (BuildContext context, Widget? child) {
            final Iterable<HomeReadingItem> books = viewModel.libraryItems
                .where(
                  (HomeReadingItem item) =>
                      category == null || item.document.type == category,
                );
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final HomeReadingItem item in books.where(
                      (item) => item.document.isAvailable,
                    ))
                      ListTile(
                        title: Text(item.sourceTitle ?? item.document.title),
                        enabled: onOpenReading != null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: onOpenReading == null
                            ? null
                            : () => onOpenReading!(item),
                      ),
                    for (final HomeReadingItem item in books.where(
                      (item) => !item.document.isAvailable,
                    ))
                      ListTile(
                        enabled: false,
                        title: Text(
                          item.document.title,
                          style: const TextStyle(color: AppColors.mutedInk),
                        ),
                        subtitle: Text(
                          strings.libraryTextUnavailable,
                          style: const TextStyle(color: AppColors.mutedInk),
                        ),
                      ),
                    if (books.isEmpty) Text(strings.libraryEmptyCategory),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
