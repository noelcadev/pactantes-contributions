import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

class EditionCreditsButton extends StatelessWidget {
  const EditionCreditsButton({required this.attribution, super.key});

  final String attribution;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showEditionCreditsSheet(context, attribution: attribution),
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: Text(
      AppLocalizations.of(context).readerEditionCredits,
      textAlign: TextAlign.center,
    ),
  );
}

Future<void> showEditionCreditsSheet(
  BuildContext context, {
  required String attribution,
}) {
  final ThemeData theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor:
        theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (BuildContext context) {
      final AppLocalizations strings = AppLocalizations.of(context);
      final ThemeData theme = Theme.of(context);
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20, end: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        strings.readerEditionCredits,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.readerClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SelectableText(attribution),
              ),
            ),
          ],
        ),
      );
    },
  );
}
