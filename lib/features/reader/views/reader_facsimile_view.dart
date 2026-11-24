import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/reading_content.dart';

class ReaderFacsimileView extends StatefulWidget {
  const ReaderFacsimileView({required this.range, super.key});

  final ReadingFacsimileRange range;

  @override
  State<ReaderFacsimileView> createState() => _ReaderFacsimileViewState();
}

class _ReaderFacsimileViewState extends State<ReaderFacsimileView> {
  late int _page = widget.range.firstPage;
  int _imageAttempt = 0;

  void _step(int direction) {
    final int next = _page + direction;
    if (next < widget.range.firstPage || next > widget.range.lastPage) return;
    setState(() => _page = next);
  }

  Future<void> _retry(ExactAssetImage image) async {
    final int page = _page;
    await image.evict(configuration: createLocalImageConfiguration(context));
    if (!mounted || _page != page) return;
    setState(() => _imageAttempt++);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final String pageLabel = strings.readerPdfPage(_page);
    final ExactAssetImage image = ExactAssetImage(
      widget.range.assetPath(_page),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: strings.readerClose,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: Semantics(
          liveRegion: true,
          child: Text(pageLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
      body: SafeArea(
        top: false,
        child: InteractiveViewer(
          key: ValueKey<int>(_page),
          maxScale: 6,
          child: SizedBox.expand(
            child: Image(
              key: ValueKey<(int, int)>((_page, _imageAttempt)),
              image: image,
              fit: BoxFit.contain,
              semanticLabel: pageLabel,
              frameBuilder: (context, child, frame, loadedSynchronously) =>
                  loadedSynchronously || frame != null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (context, error, stack) => Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        strings.readerPdfPageError,
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => _retry(image),
                        child: Text(strings.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                tooltip: strings.readerPdfPreviousPage,
                onPressed: _page > widget.range.firstPage
                    ? () => _step(-1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: strings.readerPdfNextPage,
                onPressed: _page < widget.range.lastPage
                    ? () => _step(1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
