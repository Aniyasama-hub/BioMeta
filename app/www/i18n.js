/* UI dictionaries are bundled. Research data, articles and code are never sent to translators. */
(() => {
  const originals = new WeakMap();
  const attrs = new WeakMap();
  let language = window.BiometaLanguage || 'zh-CN';
  let catalogs = {};
  const sourceByTranslation = new Map();
  let scheduled = false;
  let titleSource = document.title;
  let titleRendered = document.title;
  const excluded =
    'script,style,textarea,input,pre,code,.bm-prose,.bm-source,.job-log,.task-error,#data_preview,.example-document,#project_name,#project-folder-display,[data-no-translate]';
  function sourceText(text) {
    const trimmed = text.trim();
    const source = sourceByTranslation.get(trimmed);
    return source ? text.replace(trimmed, source) : text;
  }
  function translate(text) {
    const trimmed = text.trim();
    const value = catalogs[language]?.[trimmed];
    if (value) return text.replace(trimmed, value);
    const count = trimmed.match(/^(\d+) 项 · 示例图形$/);
    const template = catalogs[language]?.['{n} 项 · 示例图形'];
    if (count && template) return text.replace(trimmed, template.replace('{n}', count[1]));
    const metadata = trimmed.match(/^(入门|进阶) · (.+) · 更新 (\d{4}-\d{2}-\d{2})$/);
    const metadataTemplate = catalogs[language]?.['{level} · {topics} · 更新 {date}'];
    if (metadata && metadataTemplate) {
      const topics = metadata[2].split(' / ').map(translate).join(' / ');
      return text.replace(
        trimmed,
        metadataTemplate
          .replace('{level}', translate(metadata[1]))
          .replace('{topics}', topics)
          .replace('{date}', metadata[3]),
      );
    }
    return text;
  }
  function apply() {
    scheduled = false;
    document.documentElement.lang = language;
    document.documentElement.dataset.language = language;
    if (document.title !== titleRendered) titleSource = document.title;
    titleRendered = translate(titleSource);
    if (document.title !== titleRendered) document.title = titleRendered;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (!node.parentElement || node.parentElement.closest(excluded)) continue;
      const prior = originals.get(node);
      if (!prior || (node.nodeValue !== prior.rendered && node.nodeValue !== prior.source))
        originals.set(node, { source: sourceText(node.nodeValue), rendered: node.nodeValue });
      const record = originals.get(node);
      const value = translate(record.source);
      if (node.nodeValue !== value) node.nodeValue = value;
      record.rendered = value;
    }
    document.querySelectorAll('[title],[placeholder],[aria-label],[data-help]').forEach((el) => {
      if (el.closest(excluded.replace('textarea,input,', ''))) return;
      const record = attrs.get(el) || {};
      for (const key of ['title', 'placeholder', 'aria-label', 'data-help']) {
        const current = el.getAttribute(key);
        if (current === null) continue;
        if (!record[key] || (current !== record[key].rendered && current !== record[key].source))
          record[key] = { source: sourceText(current), rendered: current };
        const value = translate(record[key].source);
        if (value !== current) el.setAttribute(key, value);
        record[key].rendered = value;
      }
      attrs.set(el, record);
    });
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(apply);
  }
  window.BiometaI18n = {
    setLanguage(value) {
      if (!['zh-CN', 'zh-TW', 'en', 'fr'].includes(value)) return;
      language = value;
      apply();
    },
    translate,
  };
  function register() {
    if (window.Shiny)
      Shiny.addCustomMessageHandler('workbench-language', window.BiometaI18n.setLanguage);
  }
  document.addEventListener('shiny:connected', register);
  register();
  const ready = window.BiometaLocales
    ? Promise.resolve().then(() => {
        catalogs = window.BiometaLocales;
      })
    : Promise.all(
        ['zh-TW', 'en', 'fr'].map(async (id) => {
          const response = await fetch(`/locales/${id}.json`);
          if (!response.ok) throw new Error(`Cannot load UI language ${id}`);
          catalogs[id] = await response.json();
        }),
      );
  ready
    .then(() => {
      Object.values(catalogs).forEach((catalog) => {
        Object.entries(catalog).forEach(([source, translation]) => {
          // Recreated tooltips may already contain a translated help attribute.
          if (source !== translation) sourceByTranslation.set(translation, source);
        });
      });
      const observer = new MutationObserver(schedule);
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        characterData: true,
        attributes: true,
        attributeFilter: ['title', 'placeholder', 'aria-label', 'data-help'],
      });
      apply();
    })
    .catch((error) => {
      console.error(error);
      document.documentElement.dataset.languageError = 'true';
    });
})();
