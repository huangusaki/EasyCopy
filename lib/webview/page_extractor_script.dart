const String _pageExtractionScriptTemplate = r"""
(() => {
  const loadId = __LOAD_ID__;
  const bridge = window.easyCopyBridge;
  if (!bridge || typeof bridge.postMessage !== 'function') {
    return;
  }

  const stateKey = '__easyCopyExtractionState';
  const previousState = window[stateKey];
  if (previousState && previousState.timerId) {
    clearTimeout(previousState.timerId);
  }

  const state = {
    loadId,
    attempts: 0,
    timerId: null,
  };
  window[stateKey] = state;

  const cleanText = (value) => (value || '').replace(/\s+/g, ' ').trim();
  const mapText = (list) =>
    list
      .map((value) => cleanText(value))
      .filter((value) => value.length > 0);
  const absoluteUrl = (value) => {
    const next = cleanText(value);
    if (!next || next === '#') {
      return '';
    }
    try {
      return new URL(next, location.href).toString();
    } catch (_) {
      return '';
    }
  };
  const attr = (node, name) => {
    if (!node) {
      return '';
    }
    return cleanText(node.getAttribute(name));
  };
  const text = (node) => cleanText(node ? node.textContent : '');
  const queryText = (root, selector) => {
    if (!root) {
      return '';
    }
    return text(root.querySelector(selector));
  };
  const imageUrl = (node) => {
    if (!node) {
      return '';
    }

    const source =
      attr(node, 'data-src') ||
      attr(node, 'data-original') ||
      attr(node, 'data') ||
      cleanText(node.dataset ? node.dataset.src : '');
    return absoluteUrl(source || attr(node, 'src'));
  };
  const linkUrl = (node) => absoluteUrl(attr(node, 'href'));
  const uniqueBy = (items, keyFactory) => {
    const seen = new Set();
    return items.filter((item) => {
      const key = keyFactory(item);
      if (!key || seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  };
  const buildComicCard = (anchor) => {
    const container =
      anchor.closest('.exemptComic_Item') ||
      anchor.closest('.dailyRecommendation-box') ||
      anchor.closest('.col-auto') ||
      anchor.closest('.topThree') ||
      anchor.closest('.carousel-item') ||
      anchor.parentElement ||
      anchor;
    const title =
      attr(container.querySelector('[title]'), 'title') ||
      queryText(container, '.edit-txt') ||
      queryText(container, '.twoLines') ||
      queryText(container, '.dailyRecommendation-txt') ||
      queryText(container, '.threeLines') ||
      text(anchor);
    const subtitle =
      queryText(container, '.exemptComicItem-txt-span') ||
      queryText(container, '.dailyRecommendation-span') ||
      queryText(container, '.oneLines');
    const secondaryText =
      queryText(container, '.update span') ||
      queryText(container, '.special-time');
    const badge = queryText(container, '.special-text span');

    return {
      title,
      subtitle,
      secondaryText,
      coverUrl: imageUrl(container.querySelector('img')),
      href: linkUrl(anchor),
      badge,
    };
  };
  const collectComicCards = (root, selector) =>
    uniqueBy(
      Array.from(root.querySelectorAll(selector))
        .map((node) => buildComicCard(node))
        .filter((item) => item.title && item.href),
      (item) => item.href,
    );
  const collectFilterGroups = () =>
    Array.from(document.querySelectorAll('.classify-txt-all'))
      .map((group) => {
        const label = text(group.querySelector('dt')).replace('：', '');
        const options = Array.from(group.querySelectorAll('.classify-right a'))
          .map((anchor) => ({
            label: text(anchor.querySelector('dd')) || text(anchor),
            href: linkUrl(anchor),
            active: !!anchor.querySelector('.active'),
          }))
          .filter((option) => option.label && option.href);

        if (!label || options.length === 0) {
          return null;
        }

        return {
          label,
          options,
        };
      })
      .filter((value) => value);
  const collectChapterLinks = (root) =>
    uniqueBy(
      Array.from(root.querySelectorAll('a[href*="/chapter/"]'))
        .map((anchor) => ({
          label: text(anchor),
          href: linkUrl(anchor),
          subtitle: '',
        }))
        .filter((chapter) => chapter.label && chapter.href)
        .filter((chapter) => !chapter.label.includes('開始閱讀')),
      (chapter) => chapter.href,
    );
  const infoValue = (prefix, rowFactory) => {
    const row = rowFactory(prefix);
    if (!row) {
      return '';
    }

    const valueNode =
      row.querySelector('.comicParticulars-right-txt') ||
      row.querySelector('p') ||
      row.querySelectorAll('span')[1] ||
      row;
    const fullText = text(valueNode) || text(row);
    return cleanText(
      fullText.replace(`${prefix}：`, '').replace(`${prefix}:`, ''),
    );
  };
  const parseDetailChapterGroups = () => {
    const tabAnchors = Array.from(document.querySelectorAll('.nav-tabs a'));
    const groups = tabAnchors
      .map((tabAnchor, index) => {
        const target = attr(tabAnchor, 'href');
        const pane =
          target && target.startsWith('#')
            ? document.querySelector(target)
            : null;
        const chapters = pane ? collectChapterLinks(pane) : [];
        if (chapters.length === 0) {
          return null;
        }
        return {
          label: text(tabAnchor) || `列表 ${index + 1}`,
          chapters,
        };
      })
      .filter((value) => value);

    return groups;
  };
  const materializeReaderImages = () => {
    Array.from(document.querySelectorAll('.comicContent-list img')).forEach(
      (img) => {
        const nextSource =
          attr(img, 'data-src') ||
          attr(img, 'data-original') ||
          attr(img, 'data') ||
          cleanText(img.dataset ? img.dataset.src : '') ||
          attr(img, 'src');
        if (!nextSource) {
          return;
        }
        if (!attr(img, 'src') || attr(img, 'src').includes('loading')) {
          img.setAttribute('src', nextSource);
        }
      },
    );

    // The site lazily appends one page per scroll callback. Trigger enough
    // synthetic scrolls to fully materialize medium-sized chapters.
    for (let index = 0; index < 96; index += 1) {
      window.dispatchEvent(new Event('scroll'));
    }
    window.dispatchEvent(new Event('resize'));
  };
  const expectedReaderImageCount = () => {
    const rawValue =
      queryText(document, '.comicCount') ||
      queryText(document, '.comicContent-footer-txt span');
    const match = rawValue.match(/(\d+)/g);
    if (!match || match.length === 0) {
      return 0;
    }
    const numbers = match.map((value) => Number.parseInt(value, 10));
    if (numbers.some((value) => Number.isNaN(value))) {
      return 0;
    }
    return numbers[numbers.length - 1];
  };
  const detectPageType = () => {
    const path = location.pathname.toLowerCase();
    if (path.includes('/chapter/')) {
      return 'reader';
    }
    if (document.querySelector('.comicParticulars-title')) {
      return 'detail';
    }
    if (document.querySelector('.ranking-box')) {
      return 'rank';
    }
    if (document.querySelector('.exemptComicList')) {
      return 'discover';
    }
    if (document.querySelector('.content-box .swiperList') || document.querySelector('.comicRank')) {
      return 'home';
    }
    if (path.startsWith('/web/login') || path.startsWith('/person')) {
      return 'profile';
    }
    return 'unknown';
  };
  const pageTitle = () =>
    cleanText(document.title.replace(/- 拷[^-]+$/, '')) || 'EasyCopy';
  const buildHomePayload = () => {
    const heroBanners = uniqueBy(
      Array.from(document.querySelectorAll('.carousel-item'))
        .map((item) => {
          const anchor = item.querySelector('a[href]');
          return {
            title: queryText(item, '.carousel-caption p'),
            subtitle: '',
            imageUrl: imageUrl(item.querySelector('img')),
            href: linkUrl(anchor),
          };
        })
        .filter((item) => item.title && item.href),
      (item) => item.href,
    );

    const sections = Array.from(document.querySelectorAll('.index-all-icon'))
      .map((header) => {
        const title = text(header.querySelector('.index-all-icon-left-txt'));
        if (!title || title.includes('排行榜')) {
          return null;
        }

        const container = header.parentElement;
        if (!container) {
          return null;
        }

        const siblings = Array.from(container.children);
        const headerIndex = siblings.indexOf(header);
        const row = siblings
          .slice(headerIndex + 1)
          .find(
            (element) =>
              element.classList && element.classList.contains('row'),
          );
        if (!row) {
          return null;
        }

        const items = collectComicCards(row, 'a[href*="/comic/"]');
        if (items.length === 0) {
          return null;
        }

        return {
          title,
          subtitle: '',
          href: linkUrl(header.querySelector('.index-all-icon-right a')),
          items,
        };
      })
      .filter((value) => value);

    const featureCard = (() => {
      const block = document.querySelector('.special');
      const anchor = block ? block.parentElement : null;
      if (!block || !anchor) {
        return null;
      }
      return {
        title: queryText(block, '.special-text-h4 p'),
        subtitle: queryText(block, '.special-time'),
        imageUrl: imageUrl(block.querySelector('img')),
        href: linkUrl(anchor),
      };
    })();

    return {
      type: 'home',
      title: '首頁',
      uri: location.href,
      heroBanners,
      sections,
      feature: featureCard,
    };
  };
  const buildDiscoverPayload = () => {
    const items = collectComicCards(
      document,
      '.exemptComic-box a[href*="/comic/"]',
    );
    const pager = document.querySelector('.page-all');

    return {
      type: 'discover',
      title: pageTitle(),
      uri: location.href,
      filters: collectFilterGroups(),
      items,
      spotlight: collectComicCards(
        document,
        '.dailyRecommendation-box a[href*="/comic/"]',
      ),
      pager: {
        currentLabel:
          queryText(pager, '.page-all-item.active a') || '',
        totalLabel:
          pager && pager.querySelectorAll('.page-total').length > 0
            ? text(pager.querySelectorAll('.page-total')[pager.querySelectorAll('.page-total').length - 1])
            : '',
        prevHref: linkUrl(pager ? pager.querySelector('.prev a') : null),
        nextHref: linkUrl(pager ? pager.querySelector('.next a') : null),
      },
    };
  };
  const buildRankPayload = () => {
    const items = uniqueBy(
      Array.from(document.querySelectorAll('.ranking-all-box'))
        .map((card) => {
          const coverAnchor = card.querySelector('a[href*="/comic/"]');
          const trendElement = card.querySelector('.update-icon');
          let trend = 'stable';
          if (trendElement) {
            if (trendElement.classList.contains('up')) {
              trend = 'up';
            } else if (trendElement.classList.contains('end')) {
              trend = 'down';
            }
          }

          return {
            rankLabel: queryText(card, '.ranking-all-icon'),
            title:
              attr(card.querySelector('.threeLines'), 'title') ||
              queryText(card, '.threeLines'),
            authors: queryText(card, '.oneLines'),
            heat: queryText(card, '.update span'),
            trend,
            coverUrl: imageUrl(card.querySelector('img')),
            href: linkUrl(coverAnchor),
          };
        })
        .filter((item) => item.title && item.href),
      (item) => item.href,
    );

    return {
      type: 'rank',
      title: queryText(document, '.ranking-box-title span') || pageTitle(),
      uri: location.href,
      categories: collectFilterGroups().flatMap((group) => group.options),
      periods: Array.from(document.querySelectorAll('.rankingTime a'))
        .map((anchor) => ({
          label: text(anchor),
          href: linkUrl(anchor),
          active: anchor.classList.contains('active'),
        }))
        .filter((item) => item.label && item.href),
      items,
    };
  };
  const buildDetailPayload = () => {
    const infoRows = Array.from(
      document.querySelectorAll('.comicParticulars-title-right li'),
    );
    const rowByPrefix = (prefix) =>
      infoRows.find((row) => text(row.querySelector('span')).startsWith(prefix));
    const authors = mapText(
      Array.from(
        (rowByPrefix('作者') || document).querySelectorAll('a'),
      ).map((author) => text(author)),
    ).join(' / ');
    const chapterGroups = parseDetailChapterGroups();
    const fallbackChapters = collectChapterLinks(document);

    return {
      type: 'detail',
      title: attr(document.querySelector('h6[title]'), 'title') || pageTitle(),
      uri: location.href,
      coverUrl: imageUrl(document.querySelector('.comicParticulars-left-img img')),
      aliases: infoValue('別名', rowByPrefix),
      authors,
      heat: infoValue('熱度', rowByPrefix),
      updatedAt: infoValue('最後更新', rowByPrefix),
      status: infoValue('狀態', rowByPrefix),
      summary: queryText(document, '.intro'),
      tags: Array.from(document.querySelectorAll('.comicParticulars-tag a'))
        .map((anchor) => ({
          label: text(anchor).replace(/^#/, ''),
          href: linkUrl(anchor),
          active: false,
        }))
        .filter((tag) => tag.label && tag.href),
      startReadingHref: linkUrl(
        document.querySelector('.comicParticulars-botton[href*="/chapter/"]'),
      ),
      chapterGroups,
      chapters:
        chapterGroups.length > 0
          ? uniqueBy(
              chapterGroups.flatMap((group) => group.chapters),
              (chapter) => chapter.href,
            )
          : fallbackChapters,
    };
  };
  const buildReaderPayload = () => {
    const headerText = queryText(document, 'h4.header');
    const titleParts = headerText.split('/');
    const images = uniqueBy(
      Array.from(document.querySelectorAll('.comicContent-list img'))
        .map((img) => imageUrl(img))
        .filter((url) => url.length > 0),
      (url) => url,
    );
    const contentKey = (() => {
      if (typeof window.contentKey === 'string') {
        return cleanText(window.contentKey);
      }
      const allScriptText = Array.from(document.scripts)
        .map((script) => script.textContent || '')
        .join('\n');
      const match = allScriptText.match(/var\s+contentKey\s*=\s*'([^']+)'/i);
      return match ? cleanText(match[1]) : '';
    })();

    return {
      type: 'reader',
      title: headerText || pageTitle(),
      uri: location.href,
      comicTitle: cleanText(titleParts[0]) || pageTitle(),
      chapterTitle: cleanText(titleParts.slice(1).join('/')),
      progressLabel: queryText(document, '.comicContent-footer-txt span'),
      imageUrls: images,
      prevHref: linkUrl(
        document.querySelector('.comicContent-prev:not(.index):not(.list) a[href]'),
      ),
      nextHref: linkUrl(document.querySelector('.comicContent-next a[href]')),
      catalogHref: linkUrl(
        document.querySelector('.comicContent-prev.list a[href]'),
      ),
      contentKey,
    };
  };
  const buildProfilePayload = () => ({
    type: 'profile',
    title: '我的',
    uri: location.href,
    message: '個人中心還在重構中，這個版本先把首頁、發現、排行和閱讀體驗做好。',
  });
  const buildUnknownPayload = () => ({
    type: 'unknown',
    title: pageTitle(),
    uri: location.href,
    message: '這個頁面還沒有完成原生重建。',
  });
  const needsMoreTime = (type) => {
    if (type === 'reader') {
      materializeReaderImages();
      const expectedCount = expectedReaderImageCount();
      const currentCount = document.querySelectorAll('.comicContent-list img').length;
      return (
        (
          currentCount === 0 ||
          (expectedCount > 0 && currentCount < expectedCount)
        ) &&
        state.attempts < 48
      );
    }

    if (type === 'detail') {
      return (
        collectChapterLinks(document).length === 0 &&
        state.attempts < 28
      );
    }

    if (type === 'discover') {
      return (
        document.querySelectorAll('.exemptComic-box a[href*="/comic/"]').length === 0 &&
        state.attempts < 18
      );
    }

    if (type === 'rank') {
      return (
        document.querySelectorAll('.ranking-all-box').length === 0 &&
        state.attempts < 14
      );
    }

    if (type === 'home') {
      return (
        document.querySelectorAll('.index-all-icon').length === 0 &&
        state.attempts < 14
      );
    }

    return false;
  };
  const postPayload = (payload) => {
    bridge.postMessage(
      JSON.stringify({
        loadId,
        ...payload,
      }),
    );
  };
  const buildPayload = (type) => {
    switch (type) {
      case 'home':
        return buildHomePayload();
      case 'discover':
        return buildDiscoverPayload();
      case 'rank':
        return buildRankPayload();
      case 'detail':
        return buildDetailPayload();
      case 'reader':
        return buildReaderPayload();
      case 'profile':
        return buildProfilePayload();
      default:
        return buildUnknownPayload();
    }
  };
  const tick = () => {
    state.attempts += 1;
    const type = detectPageType();
    if (needsMoreTime(type)) {
      state.timerId = setTimeout(tick, 250);
      return;
    }

    try {
      postPayload(buildPayload(type));
    } catch (error) {
      postPayload({
        type: 'unknown',
        title: pageTitle(),
        uri: location.href,
        message: String(error),
      });
    }
  };

  tick();
})();
""";

String buildPageExtractionScript(int loadId) {
  return _pageExtractionScriptTemplate.replaceAll('__LOAD_ID__', '$loadId');
}
