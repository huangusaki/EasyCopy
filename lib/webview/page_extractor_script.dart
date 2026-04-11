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
  const discoverComicSelector =
    '.exemptComic-box a[href*="/comic/"], .correlationList a[href*="/comic/"]';
  const topicListSelector = '.specialContent';
  const topicDetailSelector = '.specialDetailItem';
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
  const textList = (nodes) =>
    Array.from(nodes)
      .map((node) => text(node))
      .filter((value) => value.length > 0);
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
  const escapeRegExp = (value) =>
    value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const parseJavaScriptStringLiteral = (source, start) => {
    let index = start;
    while (index < source.length && /\s/.test(source[index])) {
      index += 1;
    }

    const quote = source[index];
    if (quote !== "'" && quote !== '"' && quote !== '`') {
      return null;
    }
    index += 1;

    let result = '';
    while (index < source.length) {
      const char = source[index];
      index += 1;
      if (char === quote) {
        return {
          value: result,
          end: index,
        };
      }
      if (char !== '\\') {
        result += char;
        continue;
      }

      if (index >= source.length) {
        return null;
      }
      const escape = source[index];
      index += 1;
      switch (escape) {
        case '"':
        case "'":
        case '`':
        case '\\':
        case '/':
          result += escape;
          break;
        case 'b':
          result += '\b';
          break;
        case 'f':
          result += '\f';
          break;
        case 'n':
          result += '\n';
          break;
        case 'r':
          result += '\r';
          break;
        case 't':
          result += '\t';
          break;
        case 'u': {
          const hex = source.slice(index, index + 4);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
            return null;
          }
          result += String.fromCharCode(parseInt(hex, 16));
          index += 4;
          break;
        }
        default:
          result += escape;
          break;
      }
    }

    return null;
  };
  const extractAssignedString = (source, variableName) => {
    const escapedName = escapeRegExp(variableName);
    const patterns = [
      new RegExp(
        `(?:^|[;\\s])(?:var|let|const)\\s+${escapedName}\\s*=\\s*`,
        'im',
      ),
      new RegExp(`(?:^|[;\\s])window\\.${escapedName}\\s*=\\s*`, 'im'),
    ];
    for (const pattern of patterns) {
      const match = pattern.exec(source);
      if (!match) {
        continue;
      }
      const parsed = parseJavaScriptStringLiteral(
        source,
        match.index + match[0].length,
      );
      if (parsed && cleanText(parsed.value)) {
        return cleanText(parsed.value);
      }
    }
    return '';
  };
  const extractCallStringArgument = (source, functionName) => {
    const pattern = new RegExp(
      `(?:^|[^\\w$.])${escapeRegExp(functionName)}\\s*\\(\\s*`,
      'im',
    );
    const match = pattern.exec(source);
    if (!match) {
      return '';
    }
    const parsed = parseJavaScriptStringLiteral(
      source,
      match.index + match[0].length,
    );
    return parsed ? cleanText(parsed.value) : '';
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
  const buildTopicListCard = (card) => {
    const anchor =
      card.querySelector('.specialContentImage a[href]') ||
      card.querySelector('.specialContentButton a[href]');
    return {
      title:
        queryText(card, '.specialContentImageSpan') ||
        queryText(card, '.specialContentTextTitle') ||
        text(anchor),
      subtitle: queryText(card, '.specialContentTextContent'),
      secondaryText: queryText(card, '.specialContentButtonTime'),
      coverUrl: imageUrl(card.querySelector('.specialContentImage img')),
      href: linkUrl(anchor),
      badge: '專題',
    };
  };
  const collectTopicListCards = (root) =>
    uniqueBy(
      Array.from(root.querySelectorAll(topicListSelector))
        .map((card) => buildTopicListCard(card))
        .filter((item) => item.title && item.href),
      (item) => item.href,
    );
  const buildTopicDetailComicCard = (card) => {
    const titleAnchor =
      card.querySelector('.specialDetailItemHeaderContentName a[href]') ||
      card.querySelector('.specialDetailItemHeaderImage a[href]');
    const authorLabels = uniqueStrings(
      textList(
        card.querySelectorAll(
          '.specialDetailItemHeaderContentText a[href*="/author/"]',
        ),
      ),
    );
    const infoLines = textList(
      card.querySelectorAll('.specialDetailItemHeaderContentText'),
    );
    const heatLine =
      infoLines.find(
        (value) => value.includes('熱度') || value.includes('热度'),
      ) || '';
    const tagLabels = uniqueStrings(
      Array.from(
        card.querySelectorAll('.specialDetailItemHeaderContentLabel a'),
      ).map((anchor) => text(anchor).replace(/^#/, '')),
    );

    return {
      title: text(titleAnchor),
      subtitle:
        authorLabels.length > 0 ? `作者：${authorLabels.join(' / ')}` : '',
      secondaryText: heatLine,
      coverUrl: imageUrl(card.querySelector('.specialDetailItemHeaderImage img')),
      href: linkUrl(titleAnchor),
      badge: tagLabels.length > 0 ? tagLabels[0] : '',
    };
  };
  const collectTopicDetailComicCards = (root) =>
    uniqueBy(
      Array.from(root.querySelectorAll(topicDetailSelector))
        .map((card) => buildTopicDetailComicCard(card))
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
  const uniqueStrings = (items) =>
    Array.from(
      new Set(items.map((value) => cleanText(value)).filter((value) => value)),
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
    const isLikelyChapterGroupLabel = (label) => {
      const normalized = cleanText(label).replace(/\s+/g, '');
      return (
        !!normalized &&
        (normalized === '全部' ||
          normalized.includes('全部') ||
          normalized.includes('番外') ||
          normalized.includes('單話') ||
          normalized.includes('单话') ||
          normalized === '話' ||
          normalized.endsWith('話') ||
          normalized.includes('卷') ||
          normalized.includes('單行本') ||
          normalized.includes('单行本'))
      );
    };
    const normalizeTarget = (value) => {
      const normalized = cleanText(value);
      if (!normalized) {
        return '';
      }
      if (normalized.startsWith('#')) {
        return normalized;
      }
      if (
        normalized.includes('/') ||
        normalized.includes(':') ||
        normalized.includes('?')
      ) {
        return '';
      }
      return `#${normalized.replace(/^#/, '')}`;
    };
    const controlTargets = (node) =>
      uniqueStrings([
        normalizeTarget(attr(node, 'href')),
        normalizeTarget(attr(node, 'data-target')),
        normalizeTarget(attr(node, 'data-bs-target')),
        normalizeTarget(attr(node, 'aria-controls')),
      ]).filter((target) => target.startsWith('#'));
    const controls = uniqueBy(
      Array.from(
        document.querySelectorAll(
          '.nav-tabs a, .nav-tabs button, a[data-toggle="tab"], button[data-toggle="tab"], a[data-bs-toggle="tab"], button[data-bs-toggle="tab"], [role="tab"]',
        ),
      )
        .map((control, index) => ({
          label: text(control) || `列表 ${index + 1}`,
          targets: controlTargets(control),
          index,
        }))
        .filter(
          (control) =>
            control.targets.length > 0 || isLikelyChapterGroupLabel(control.label),
        ),
      (control) => `${control.label}::${control.targets.join('|')}`,
    );
    const panes = Array.from(
      document.querySelectorAll('.tab-pane, .tab-content [role="tabpanel"]'),
    )
      .map((pane, index) => ({
        target: normalizeTarget(attr(pane, 'id')),
        labelledBy: normalizeTarget(attr(pane, 'aria-labelledby')),
        chapters: collectChapterLinks(pane),
        index,
      }))
      .filter(
        (pane) =>
          pane.chapters.length > 0 || pane.target || pane.labelledBy,
      );
    const consumedPaneIndices = new Set();
    const groups = [];
    let sequentialPaneIndex = 0;

    controls.forEach((control) => {
      let pane = panes.find((candidate) =>
        control.targets.some(
          (target) =>
            target &&
            (candidate.target === target || candidate.labelledBy === target),
        ),
      );
      if (!pane && control.targets.length === 0) {
        pane = panes.find(
          (candidate) =>
            candidate.index >= sequentialPaneIndex &&
            !consumedPaneIndices.has(candidate.index),
        );
      }
      if (!pane && !isLikelyChapterGroupLabel(control.label)) {
        return;
      }
      if (pane) {
        consumedPaneIndices.add(pane.index);
        sequentialPaneIndex = Math.max(sequentialPaneIndex, pane.index + 1);
      }
      groups.push({
        label: control.label,
        chapters: pane ? pane.chapters : [],
      });
    });

    panes.forEach((pane) => {
      if (consumedPaneIndices.has(pane.index)) {
        return;
      }
      if (pane.chapters.length === 0) {
        return;
      }
      groups.push({
        label: `列表 ${pane.index + 1}`,
        chapters: pane.chapters,
      });
    });

    return uniqueBy(
      groups.filter((group) => group.label || group.chapters.length > 0),
      (group) => {
        const firstChapterHref =
          group.chapters.length > 0 ? group.chapters[0].href : '';
        return `${cleanText(group.label)}::${firstChapterHref}`;
      },
    );
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
    if (
      document.querySelector('.exemptComicList') ||
      document.querySelector('.correlationList .exemptComic_Item') ||
      document.querySelector('.specialDetail') ||
      document.querySelector('.specialContent') ||
      path.startsWith('/comics') ||
      path.startsWith('/search') ||
      path.startsWith('/topic') ||
      path.startsWith('/recommend') ||
      path.startsWith('/newest')
    ) {
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
    const sections = Array.from(document.querySelectorAll('.index-all-icon'))
      .map((header) => {
        const title = text(header.querySelector('.index-all-icon-left-txt'));
        const sectionHref = linkUrl(
          header.querySelector('.index-all-icon-right a'),
        );
        const normalizedTitle = title.replace(/\s+/g, '');
        const normalizedSectionPath = (() => {
          try {
            return new URL(sectionHref, location.href).pathname.toLowerCase();
          } catch (_) {
            return sectionHref.trim().toLowerCase();
          }
        })();
        if (!title || title.includes('排行榜')) {
          return null;
        }
        if (
          normalizedTitle.includes('熱門更新') ||
          normalizedTitle.includes('热门更新') ||
          normalizedSectionPath === '/comics' ||
          normalizedSectionPath === '/comics/'
        ) {
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
          href: sectionHref,
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
      heroBanners: [],
      sections,
      feature: featureCard,
    };
  };
  const buildDiscoverPayload = () => {
    const path = location.pathname.toLowerCase();
    const isTopicDetail =
      path.startsWith('/topic/') || !!document.querySelector('.specialDetail');
    const isTopicRoute = path.startsWith('/topic');
    const items = isTopicDetail
      ? collectTopicDetailComicCards(document)
      : isTopicRoute
      ? collectTopicListCards(document)
      : collectComicCards(document, discoverComicSelector);
    const pager = document.querySelector('.page-all');

    return {
      type: 'discover',
      title: pageTitle(),
      uri: location.href,
      filters: isTopicRoute ? [] : collectFilterGroups(),
      items,
      spotlight: isTopicRoute
        ? []
        : collectComicCards(
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
        prevHref: linkUrl(
          pager ? pager.querySelector('.prev a, .prev-all a') : null,
        ),
        nextHref: linkUrl(
          pager ? pager.querySelector('.next a, .next-all a') : null,
        ),
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
    const collectButton = document.querySelector(
      '.comicParticulars-botton.collect',
    );
    const collectText = text(collectButton);
    const collectId = extractCallStringArgument(
      attr(collectButton, 'onclick'),
      'collect',
    );
    const rowByPrefix = (prefix) =>
      infoRows.find((row) => text(row.querySelector('span')).startsWith(prefix));
    const authors = mapText(
      Array.from(
        (rowByPrefix('作者') || document).querySelectorAll('a'),
      ).map((author) => text(author)),
    ).join(' / ');
    const chapterGroups = parseDetailChapterGroups();
    const groupedChapters = uniqueBy(
      chapterGroups.flatMap((group) => group.chapters),
      (chapter) => chapter.href,
    );
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
      comicId: collectId,
      isCollected:
        !!collectText &&
        !collectText.includes('加入書架') &&
        !collectText.includes('加入书架'),
      startReadingHref: linkUrl(
        document.querySelector('.comicParticulars-botton[href*="/chapter/"]'),
      ),
      chapterGroups,
      chapters: groupedChapters.length > 0 ? groupedChapters : fallbackChapters,
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
      return extractAssignedString(allScriptText, 'contentKey');
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
      const hasContentKey =
        typeof window.contentKey === 'string' && cleanText(window.contentKey);
      const currentCount = document.querySelectorAll('.comicContent-list img').length;
      return !hasContentKey && currentCount === 0 && state.attempts < 6;
    }

    if (type === 'detail') {
      return collectChapterLinks(document).length === 0 && state.attempts < 8;
    }

    if (type === 'discover') {
      const hasDiscoverItems =
        document.querySelectorAll(discoverComicSelector).length > 0 ||
        document.querySelectorAll(topicListSelector).length > 0 ||
        document.querySelectorAll(topicDetailSelector).length > 0;
      return !hasDiscoverItems && state.attempts < 6;
    }

    if (type === 'rank') {
      return document.querySelectorAll('.ranking-all-box').length === 0 && state.attempts < 6;
    }

    if (type === 'home') {
      return document.querySelectorAll('.index-all-icon').length === 0 && state.attempts < 6;
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
      state.timerId = setTimeout(tick, 160);
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
