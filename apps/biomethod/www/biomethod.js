/* global hljs, renderMathInElement, ResearchPlatform */
(() => {
  let catalogPromise;
  let renderNumber = 0;
  const $ = (tag, text, className) => {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
  };
  const array = (value) => (Array.isArray(value) ? value : value == null ? [] : [value]);
  async function api(route) {
    const response = await fetch(`/api/knowledge/${route}`, {
      headers: { Accept: 'application/json' },
    });
    const value = await response.json();
    if (!response.ok) throw new Error(value.error || `读取失败 (${response.status})`);
    return value;
  }
  function loadCatalog(force = false) {
    if (!catalogPromise || force)
      catalogPromise = api('catalog').catch((error) => {
        catalogPromise = null;
        throw error;
      });
    return catalogPromise;
  }
  function link(text, href, className) {
    const node = $('a', text, className);
    node.href = href;
    return node;
  }
  function articleLink(item) {
    return link(item.title, `/biomethod/articles/${item.id}`);
  }
  function searchForm(query = '') {
    const form = $('form', undefined, 'bm-search');
    form.setAttribute('role', 'search');
    const label = $('label', '搜索知识、脚本与文献');
    label.htmlFor = 'bm-search-input';
    const input = $('input');
    input.type = 'search';
    input.id = 'bm-search-input';
    input.name = 'q';
    input.value = query;
    input.placeholder = '例如：PCA、批次、VST、DESeq2、DOI…';
    const button = $('button', '搜索');
    button.type = 'submit';
    form.append(label, input, button);
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      ResearchPlatform.navigate(`/biomethod/search?q=${encodeURIComponent(input.value.trim())}`);
    });
    return form;
  }
  function section(title, heading = 'h2') {
    const node = $('section', undefined, 'bm-section');
    node.append($(heading, title));
    return node;
  }
  function articleList(items, title) {
    const node = section(title);
    const list = $('div', undefined, 'bm-entry-list');
    array(items).forEach((item) => {
      const row = $('article', undefined, 'bm-entry');
      row.append(
        articleLink(item),
        $('p', item.summary),
        $('small', `${item.difficulty} · ${array(item.tags).join(' / ')} · 更新 ${item.updated}`),
      );
      list.append(row);
    });
    if (!array(items).length) list.append($('p', '没有匹配条目。请缩短关键词或换用方法名称。'));
    node.append(list);
    return node;
  }
  function referenceCard(item) {
    const card = $('article', undefined, 'bm-reference');
    const href = new URL(item.url);
    if (href.protocol !== 'https:') throw new Error('文献链接须为 HTTPS。');
    const anchor = link(item.title, href.href);
    anchor.target = '_blank';
    anchor.rel = 'noopener';
    card.append(anchor, $('p', `${item.authors} · ${item.year || '持续更新'} · ${item.journal}`));
    if (item.doi) card.append($('code', `DOI: ${item.doi}`));
    card.append($('p', item.summary), $('small', `链接与书目信息核对：${item.verified_on}`));
    return card;
  }
  function scriptCard(item) {
    const node = $('article', undefined, 'bm-entry');
    node.append(
      link(item.title, `/biomethod/scripts/${item.id}`),
      $('p', item.path),
      $('small', `依赖：${array(item.dependencies).join(' / ')}`),
    );
    return node;
  }
  function relatedFeatures(items, heading = 'h2') {
    const node = section('关联分析功能', heading);
    array(items).forEach((id) =>
      node.append(
        link(
          `打开 ${ResearchPlatform.config.feature_labels[id] || id}`,
          `/workstation?tool=${encodeURIComponent(id)}`,
          'bm-action',
        ),
      ),
    );
    return node;
  }
  function detailLayout(article, side) {
    const layout = $('div', undefined, 'bm-detail');
    layout.append(article);
    if (side) layout.append(side);
    return layout;
  }
  function decorate(article) {
    article.querySelectorAll('pre code').forEach((block) => hljs.highlightElement(block));
    renderMathInElement(article, {
      delimiters: [{ left: '$$', right: '$$', display: true }],
      throwOnError: false,
      trust: false,
    });
    article.querySelectorAll('img').forEach((img) => {
      img.loading = 'lazy';
    });
    article.querySelectorAll('h2, h3').forEach((heading, index) => {
      if (!heading.id) heading.id = `bm-section-${index}`;
    });
    return null;
  }
  function annotationInventory(items) {
    const section = $('section', undefined, 'bm-annotation-inventory');
    section.append(
      $('h3', '当前工作站的注释库信息'),
      $(
        'p',
        '以下内容读取当前工作站配置与本机缓存。检查通过表示本地结构有效，不表示与官网最新发行完全一致。',
      ),
    );
    array(items).forEach((item) => {
      const block = $('div', undefined, 'bm-annotation-library');
      block.append(
        $('h4', item.name),
        $('p', item.source),
        $('p', item.identifier),
        $('p', item.coverage),
      );
      const packages = array(item.runtime_packages)
        .map((p) => `${p.name} ${p.version}`)
        .join('；');
      block.append($('p', packages));
      Object.values(item.local || {}).forEach((cache) => {
        const counts =
          cache.terms === undefined
            ? ''
            : `；${cache.terms} 个通路，${cache.genes} 个基因，${cache.links} 条关系`;
        block.append(
          $(
            'p',
            `${cache.organism}：${cache.status}${counts}${cache.retrieved ? '；获取于 ' + cache.retrieved : ''}${cache.release ? '；' + cache.release : ''}`,
          ),
        );
      });
      block.append(
        $('p', item.version_policy),
        $('p', item.limitation),
        link('官方资料', item.homepage),
      );
      section.append(block);
    });
    return section;
  }
  async function render(url, appLabel) {
    const root = document.getElementById('bm-content');
    const number = ++renderNumber;
    root.setAttribute('aria-busy', 'true');
    root.replaceChildren($('p', '正在读取知识内容…', 'bm-loading'));
    try {
      const catalog = await loadCatalog();
      const parts = url.pathname
        .replace(/^\/biomethod\/?/, '')
        .split('/')
        .filter(Boolean);
      const query = url.searchParams.get('q') || '';
      const page = $('div', undefined, 'bm-page');
      if (!parts.length) {
        page.append(
          $('h1', appLabel),
          $('p', '生信方法与知识库', 'bm-subtitle'),
          $('p', '把分析流程、算法假设和真实脚本连在一起。先理解方法，再审阅结果。', 'bm-intro'),
          searchForm(),
        );
        const categories = $('nav', undefined, 'bm-category-grid');
        categories.setAttribute('aria-label', '知识板块');
        catalog.categories.forEach((category) => {
          const a = link('', `/biomethod/category/${category.id}`);
          a.append($('h2', category.title), $('p', category.summary));
          categories.append(a);
        });
        page.append(categories);
        const learning = section('推荐学习路线');
        const list = $('ol', undefined, 'bm-learning');
        array(catalog.learning_path).forEach((id) => {
          const item = catalog.articles.find((a) => a.id === id);
          if (!item) return;
          const li = $('li');
          li.append(articleLink(item));
          list.append(li);
        });
        learning.append(list);
        page.append(learning);
        page.append(
          articleList(
            array(catalog.featured)
              .map((id) => catalog.articles.find((a) => a.id === id))
              .filter(Boolean),
            '推荐教程',
          ),
        );
        page.append(
          articleList(
            [...catalog.articles].sort((a, b) => b.updated.localeCompare(a.updated)).slice(0, 3),
            '最近更新',
          ),
        );
        document.title = appLabel;
      } else if (parts[0] === 'category' || parts[0] === 'search') {
        const category = catalog.categories.find((c) => c.id === parts[1]);
        if (parts[0] === 'category' && !category) throw new Error('此知识分类不存在。');
        page.append($('h1', category ? category.title : '搜索知识库'), searchForm(query));
        if (category?.id === 'references') {
          catalog.references.forEach((item) => page.append(referenceCard(item)));
        } else if (category?.id === 'scripts') {
          page.append(
            articleList(
              catalog.articles.filter((item) => item.category === 'scripts'),
              '逐行代码教程',
            ),
          );
          const sources = $('details', undefined, 'bm-source-index');
          sources.append($('summary', '查看工作站源码索引'));
          catalog.scripts.forEach((item) => sources.append(scriptCard(item)));
          page.append(sources);
        } else if (category) {
          page.append(
            articleList(
              catalog.articles.filter((a) => a.category === category.id),
              '条目',
            ),
          );
        } else {
          const needle = query.toLocaleLowerCase();
          const articles = catalog.articles.filter((a) =>
            a.search_text.toLocaleLowerCase().includes(needle),
          );
          const scripts = catalog.scripts.filter((s) =>
            JSON.stringify(s).toLocaleLowerCase().includes(needle),
          );
          const references = catalog.references.filter((r) =>
            JSON.stringify(r).toLocaleLowerCase().includes(needle),
          );
          page.append(
            $(
              'p',
              `找到 ${articles.length + scripts.length + references.length} 项相关内容`,
              'bm-search-count',
            ),
          );
          page.append(articleList(articles, '知识条目'));
          if (scripts.length) {
            const group = section('脚本');
            scripts.forEach((s) => group.append(scriptCard(s)));
            page.append(group);
          }
          if (references.length) {
            const group = section('参考文献');
            references.forEach((r) => group.append(referenceCard(r)));
            page.append(group);
          }
        }
        document.title = `${category?.title || '搜索'} · ${appLabel}`;
      } else if (parts[0] === 'articles' && parts.length === 2) {
        const item = await api(`articles/${encodeURIComponent(parts[1])}`);
        const article = $('article', undefined, 'bm-article');
        article.append(
          link(appLabel, '/biomethod', 'bm-breadcrumb'),
          $('h1', item.title),
          $(
            'p',
            `${item.difficulty} · ${array(item.tags).join(' / ')} · 更新 ${item.updated}`,
            'bm-meta',
          ),
        );
        const body = $('div', undefined, 'bm-prose');
        // HTML is produced by the read-only server from trusted repository Markdown, never search input.
        body.innerHTML = item.html;
        const required = ['定义解释', '分析原理', '分析操作', '适用范围', '参考与致谢'];
        const headings = [...body.querySelectorAll('h2')].map((heading) =>
          heading.textContent.trim(),
        );
        if (
          body.querySelector('h1') ||
          headings.length !== required.length ||
          headings.some((heading, index) => heading !== required[index])
        ) {
          throw new Error(
            '正文须按顺序使用五个主章节：定义解释、分析原理、分析操作、适用范围、参考与致谢。',
          );
        }
        article.append(body);
        const appendToSection = (title, content) => {
          const headings = [...body.querySelectorAll('h2')];
          const index = headings.findIndex((heading) => heading.textContent.trim() === title);
          if (index < 0) throw new Error(`文章缺少必需章节：${title}`);
          body.insertBefore(content, headings[index + 1] || null);
        };
        if (item.article_type === 'technical' && array(item.scripts).length) {
          const scripts = section('对应的工作站源码', 'h3');
          array(item.scripts).forEach((id) => {
            const s = catalog.scripts.find((v) => v.id === id);
            if (s) scripts.append(scriptCard(s));
          });
          appendToSection('分析操作', scripts);
        }
        const tutorials = array(item.technical_articles)
          .map((id) => catalog.articles.find((entry) => entry.id === id))
          .filter(Boolean);
        if (tutorials.length) {
          const guide = section('继续学习：逐行代码教程', 'h3');
          tutorials.forEach((entry) => guide.append(articleLink(entry)));
          appendToSection('分析操作', guide);
        }
        if (item.annotation_inventory)
          appendToSection('分析操作', annotationInventory(item.annotation_inventory));
        if (array(item.features).length)
          appendToSection('分析操作', relatedFeatures(item.features, 'h3'));
        const references = section('文献与官方资料', 'h3');
        array(item.references).forEach((id) => {
          const r = catalog.references.find((v) => v.id === id);
          if (r) references.append(referenceCard(r));
        });
        appendToSection('参考与致谢', references);
        const aside = decorate(article);
        page.append(detailLayout(article, aside));
        document.title = `${item.title} · ${appLabel}`;
      } else if (parts[0] === 'scripts' && parts.length === 2) {
        const item = await api(`scripts/${encodeURIComponent(parts[1])}`);
        const article = $('article', undefined, 'bm-article');
        article.append(
          link('脚本解析库', '/biomethod/category/scripts'),
          $('h1', item.title),
          $('p', `${item.path} · 当前文件片段 ${item.start_line}–${item.end_line} 行`),
          $('p', '此页展示当前源文件片段。逐步操作与逐行中文注释见下方技术教程。'),
        );
        const tutorials = array(item.articles)
          .map((id) => catalog.articles.find((entry) => entry.id === id))
          .filter((entry) => entry?.article_type === 'technical');
        if (tutorials.length) article.append(articleList(tutorials, '逐行代码教程'));
        [
          ['输入', item.inputs],
          ['输出', item.outputs],
          ['依赖包', item.dependencies],
          ['参数说明', item.parameters],
          ['常见报错', item.errors],
        ].forEach(([title, values]) => {
          const group = section(title);
          const list = $('ul');
          array(values).forEach((v) => list.append($('li', v)));
          group.append(list);
          article.append(group);
        });
        const source = section('重要代码与原有注释');
        const code = $('code', item.code, 'language-r');
        const pre = $('pre');
        pre.append(code);
        source.append(pre);
        article.append(source, $('p', `SHA-256: ${item.sha256}`, 'bm-source-hash'));
        const related = section('关联知识');
        array(item.articles).forEach((id) => {
          const a = catalog.articles.find((v) => v.id === id);
          if (a) related.append(articleLink(a));
        });
        article.append(related);
        page.append(detailLayout(article, decorate(article)));
        document.title = `${item.title} · ${appLabel}`;
      } else if (parts[0] === 'references' && parts.length === 2) {
        const item = await api(`references/${encodeURIComponent(parts[1])}`);
        page.append($('h1', '参考文献'), referenceCard(item));
        array(item.articles).forEach((id) => {
          const a = catalog.articles.find((v) => v.id === id);
          if (a) page.append(articleLink(a));
        });
      } else throw new Error('此知识页面不存在。');
      if (number !== renderNumber) return;
      root.replaceChildren(page);
      if (url.hash) {
        let id;
        try {
          id = decodeURIComponent(url.hash.slice(1));
        } catch {
          id = '';
        }
        document.getElementById(id)?.scrollIntoView({ block: 'start' });
      }
      const articleCategory = catalog.articles.find((a) => a.id === parts[1])?.category;
      const activePath =
        parts[0] === 'articles' && articleCategory
          ? `/biomethod/category/${articleCategory}`
          : parts[0] === 'scripts'
            ? '/biomethod/category/scripts'
            : parts[0] === 'references'
              ? '/biomethod/category/references'
              : url.pathname;
      document.querySelectorAll('.bm-sidebar > nav a').forEach((a) => {
        if (new URL(a.href).pathname === activePath) a.setAttribute('aria-current', 'page');
        else a.removeAttribute('aria-current');
      });
    } catch (error) {
      if (number !== renderNumber) return;
      const panel = $('section', undefined, 'bm-error');
      panel.append(
        $('h1', '无法打开知识内容'),
        $('p', error.message),
        link('返回知识首页', '/biomethod'),
      );
      const retry = $('button', '重新读取');
      retry.type = 'button';
      retry.addEventListener('click', () => {
        catalogPromise = null;
        render(url, appLabel);
      });
      panel.append(retry);
      root.replaceChildren(panel);
    } finally {
      if (number === renderNumber) root.setAttribute('aria-busy', 'false');
    }
  }
  window.BioMethod = { render };
})();
