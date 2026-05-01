import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/reader_progress_store.dart';

class ReaderRestoreTarget {
  const ReaderRestoreTarget({this.position, this.visibleImageIndex});

  final ReaderPosition? position;
  final int? visibleImageIndex;

  int? imageIndexFor(ReaderPageData page) {
    if (page.imageUrls.isEmpty) {
      return null;
    }
    final int? rawIndex =
        visibleImageIndex ??
        (position?.isPaged == true ? position!.pageIndex : null);
    if (rawIndex == null) {
      return null;
    }
    return rawIndex.clamp(0, page.imageUrls.length - 1);
  }
}
