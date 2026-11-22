// Site selectors and labels interpreted by both package:html and the live DOM.
class SiteHtmlRules {
  static const detail = '.comicParticulars-title';
  static const rank = '.ranking-box';
  static const discover =
      '.exemptComicList, .correlationList .exemptComic_Item';
  static const home = '.content-box .swiperList, .comicRank';
  static const discoverCards =
      '.exemptComic-box a[href*="/comic/"], .correlationList a[href*="/comic/"]';
  static const discoverPaths = [
    '/comics',
    '/filter',
    '/search',
    '/recommend',
    '/newest',
    '/author',
  ];
  static const startReading = ['開始閱讀', '开始阅读'];
}
