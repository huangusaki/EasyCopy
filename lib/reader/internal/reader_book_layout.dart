class BookSpread {
  const BookSpread(this.start, this.end, {this.wide = false});

  final int start;
  final int end;
  final bool wide;
}

bool isBookWide(double? ratio) => ratio != null && ratio >= 1.2;

List<BookSpread> bookSpreads(
  List<String> urls,
  Map<String, double> ratios, {
  required bool comments,
}) {
  final List<BookSpread> pages = <BookSpread>[];
  for (int i = 0; i < urls.length;) {
    final bool wide = isBookWide(ratios[urls[i]]);
    final bool pair =
        !wide && i + 1 < urls.length && !isBookWide(ratios[urls[i + 1]]);
    final int end = i + (pair ? 2 : 1);
    pages.add(BookSpread(i, end, wide: wide));
    i = end;
  }
  if (comments) pages.add(BookSpread(urls.length, urls.length + 1));
  if (pages.isEmpty) pages.add(const BookSpread(0, 0));
  return pages;
}
