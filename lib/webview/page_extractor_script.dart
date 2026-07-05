// 与 Dart 解析器共享站点 DOM 约定，选择器变更需同步。
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
    '.exemptComic-box a[href*="/comic/"], .exemptComicItem a[href*="/comic/"], .correlationList a[href*="/comic/"]';
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
      anchor.closest('.exemptComicItem') ||
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
    const secondaryText = queryText(container, '.update span');

    return {
      title,
      subtitle,
      secondaryText,
      coverUrl: imageUrl(container.querySelector('img')),
      href: linkUrl(anchor),
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
  const sortedQueryString = (params) => {
    const sortedEntries = Array.from(params.entries()).sort((left, right) =>
      left[0].localeCompare(right[0]),
    );
    return new URLSearchParams(sortedEntries).toString();
  };
  const replaceSortedComicsQuery = (params) => {
    const query = sortedQueryString(params);
    return `${location.origin}/comics${query ? `?${query}` : ''}`;
  };
  const isHotSite = () => location.hostname.toLowerCase().includes('manga2026');
  const isHotComicsPage = () =>
    location.pathname.toLowerCase().startsWith('/comics') && isHotSite();
  const hotComicBaseQuery = (groups) => {
    const params = new URLSearchParams(location.search);
    groups.forEach((group) => {
      group.options.forEach((option) => {
        if (!option.active || !option.href) {
          return;
        }
        try {
          const optionUrl = new URL(option.href, location.href);
          if (!optionUrl.pathname.toLowerCase().startsWith('/comics')) {
            return;
          }
          optionUrl.searchParams.forEach((value, key) => {
            params.set(key, value);
          });
        } catch (_) {
          return;
        }
      });
    });
    params.delete('offset');
    params.delete('page');
    params.delete('limit');
    if (!params.has('ordering')) {
      params.set('ordering', '-datetime_updated');
    }
    return params;
  };
  const hotComicTypeHref = (groups, type) => {
    const params = hotComicBaseQuery(groups);
    params.set('type', type);
    return replaceSortedComicsQuery(params);
  };
  const ensureHotSortFilter = (groups) => {
    if (groups.some((group) => group.label === '排序')) {
      return groups;
    }
    const baseParams = hotComicBaseQuery(groups);
    const activeOrdering = baseParams.get('ordering') || '-datetime_updated';
    const buildOption = (label, ordering) => {
      const params = new URLSearchParams(baseParams.toString());
      params.set('ordering', ordering);
      return {
        label,
        href: replaceSortedComicsQuery(params),
        active: activeOrdering === ordering,
      };
    };
    return [
      ...groups,
      {
        label: '排序',
        options: [
          buildOption('最新更新', '-datetime_updated'),
          buildOption('最新上架', '-datetime_created'),
          buildOption('人气最高', '-popular'),
        ],
      },
    ];
  };
  const withHotComicTypeFilter = (groups) => {
    if (!isHotComicsPage()) {
      return groups;
    }
    const normalizedGroups = groups.filter((group) => group.label !== '类型');
    return [
      {
        label: '类型',
        options: [
          {
            label: '免费漫画',
            href: hotComicTypeHref(normalizedGroups, '1'),
            active: new URLSearchParams(location.search).get('type') !== '2',
          },
          {
            label: '付费漫画',
            href: hotComicTypeHref(normalizedGroups, '2'),
            active: new URLSearchParams(location.search).get('type') === '2',
          },
        ],
      },
      ...ensureHotSortFilter(normalizedGroups),
    ];
  };
  const isHotPaidHomeSection = (title, href) => {
    if (!isHotSite()) {
      return false;
    }
    const normalizedTitle = title.replace(/\s+/g, '');
    if (
      !normalizedTitle.includes('付費漫畫') &&
      !normalizedTitle.includes('付费漫画')
    ) {
      return false;
    }
    try {
      const url = new URL(href, location.href);
      return (
        url.pathname.toLowerCase() === '/comics' &&
        (url.searchParams.get('type') === '2' ||
          href.toLowerCase().includes('type=2'))
      );
    } catch (_) {
      return href.toLowerCase().includes('/comics') && href.includes('type=2');
    }
  };
  const homeSectionItemsRoot = (header) => {
    const container = header.parentElement;
    if (!container) {
      return null;
    }

    const siblings = Array.from(container.children);
    const headerIndex = siblings.indexOf(header);
    return siblings.slice(headerIndex + 1).reduce((result, element) => {
      if (result) {
        return result;
      }
      if (element.classList && element.classList.contains('row')) {
        return element;
      }
      return element.querySelector ? element.querySelector('.row') : null;
    }, null);
  };
  const isHotComicRankBlock = (block) => {
    const normalizedTitle = queryText(block, '.theBoxModel').replace(/\s+/g, '');
    if (
      normalizedTitle.includes('動畫') ||
      normalizedTitle.includes('动画') ||
      block.classList.contains('cartoon')
    ) {
      return false;
    }
    if (
      normalizedTitle.includes('漫畫榜') ||
      normalizedTitle.includes('漫画榜') ||
      normalizedTitle.includes('免費漫畫') ||
      normalizedTitle.includes('免费漫画') ||
      normalizedTitle.includes('付費漫畫') ||
      normalizedTitle.includes('付费漫画') ||
      block.classList.contains('free') ||
      block.classList.contains('pay')
    ) {
      return true;
    }
    return (
      !!block.querySelector('a[href*="/comic/"]') &&
      !block.querySelector('a[href*="/cartoon/"]')
    );
  };
  const rankEntryScopes = () => {
    if (!isHotSite()) {
      return [document];
    }
    const blocks = Array.from(document.querySelectorAll('.ranking-item')).filter(
      isHotComicRankBlock,
    );
    return blocks.length > 0 ? blocks : [document];
  };
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
    if (
      document.querySelector('.ranking-box') ||
      document.querySelector('.ranking') ||
      path.startsWith('/rank')
    ) {
      return 'rank';
    }
    if (
      document.querySelector('.exemptComicList') ||
      document.querySelector('.correlationList .exemptComic_Item') ||
      path.startsWith('/comics') ||
      path.startsWith('/search') ||
      path.startsWith('/recommend') ||
      path.startsWith('/newest') ||
      path.startsWith('/author')
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
      cleanText(document.title.replace(/- (拷|熱辣|热辣)[^-]+$/, '')) || 'EasyCopy';
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
        const isHotPaidReplacement = isHotPaidHomeSection(title, sectionHref);
        if (!title || title.includes('排行榜')) {
          return null;
        }
        if (!isHotPaidReplacement && (
          normalizedTitle.includes('熱門更新') ||
          normalizedTitle.includes('热门更新') ||
          normalizedSectionPath === '/comics' ||
          normalizedSectionPath === '/comics/'
        )) {
          return null;
        }

        const row = homeSectionItemsRoot(header);
        if (!row) {
          return null;
        }

        const items = collectComicCards(row, 'a[href*="/comic/"]');
        if (items.length === 0) {
          return null;
        }

        return {
          title: isHotPaidReplacement ? '付費漫畫' : title,
          subtitle: '',
          href: sectionHref,
          items,
        };
      })
      .filter((value) => value);

    return {
      type: 'home',
      title: '首页',
      uri: location.href,
      heroBanners: [],
      sections,
    };
  };
  const buildDiscoverPayload = () => {
    const items = collectComicCards(document, discoverComicSelector);
    const pager = document.querySelector('.page-all');

    return {
      type: 'discover',
      title: pageTitle(),
      uri: location.href,
      filters: withHotComicTypeFilter(collectFilterGroups()),
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
        prevHref: linkUrl(
          pager ? pager.querySelector('.prev a') || pager.querySelector('.prev-all a') : null,
        ),
        nextHref: linkUrl(
          pager ? pager.querySelector('.next a') || pager.querySelector('.next-all a') : null,
        ),
      },
    };
  };
  const buildRankPayload = () => {
    const rankPageTitle = pageTitle();
    const scopes = rankEntryScopes();
    const items = uniqueBy(
      scopes
        .flatMap((scope) =>
          Array.from(scope.querySelectorAll('.ranking-all-box, .ranking-allItem')),
        )
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
      title:
        queryText(document, '.ranking-box-title span') ||
        (rankPageTitle !== 'EasyCopy' ? rankPageTitle : '') ||
        queryText(document, '.ranking .theBoxModel') ||
        rankPageTitle,
      uri: location.href,
      categories: collectFilterGroups().flatMap((group) => group.options),
      periods: scopes
        .flatMap((scope) =>
          Array.from(
            scope.querySelectorAll(
              '.rankingTime a, .ranking .nav-tabs a, .nav-tabs a',
            ),
          ),
        )
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
    const authorLinks = Array.from(
      (rowByPrefix('作者') || document).querySelectorAll('a'),
    )
      .map((anchor) => ({
        label: text(anchor),
        href: linkUrl(anchor),
        active: false,
      }))
      .filter((item) => item.label && item.href);
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
      authorLinks,
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
      noticeMessage: document.querySelector('.upMember')
        ? '当前账号只能读5页漫画，服务端限制'
        : '',
    };
  };
  const buildProfilePayload = () => ({
    type: 'profile',
    title: '我的',
    uri: location.href,
  });
  const buildUnknownPayload = () => ({
    type: 'unknown',
    title: pageTitle(),
    uri: location.href,
    message: '这个页面还没有完成原生重建。',
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
        document.querySelectorAll(discoverComicSelector).length > 0;
      return !hasDiscoverItems && state.attempts < 6;
    }

    if (type === 'rank') {
      return (
        document.querySelectorAll('.ranking-all-box, .ranking-allItem')
          .length === 0 && state.attempts < 6
      );
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
