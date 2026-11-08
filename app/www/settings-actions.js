document.addEventListener('DOMContentLoaded', () => {
  Shiny.addCustomMessageHandler('local-folder-selected', (path) => {
    const label = document.getElementById('project-folder-display');
    if (label) label.textContent = path;
  });
  Shiny.addCustomMessageHandler('runtime-focus', (id) => document.getElementById(id)?.focus());
  document.addEventListener('click', (event) => {
    const manual = event.target.closest('[data-runtime-manual]');
    if (manual) document.getElementById(manual.dataset.runtimeManual)?.focus();
    const jump = event.target.closest('[data-bulk-jump]');
    if (jump && !jump.disabled)
      Shiny.setInputValue('bulk_jump', jump.dataset.bulkJump, { priority: 'event' });
    const remove = event.target.closest('[data-flow-remove]');
    if (remove)
      Shiny.setInputValue('flow_remove', Number(remove.dataset.flowRemove), { priority: 'event' });
    const move = event.target.closest('[data-panel-move]');
    if (move) {
      const keys = Array.from(document.querySelectorAll('.figure-input-panel')).map(
        (node) => node.dataset.panelField,
      );
      const reordered = keys.filter((key) => key !== move.dataset.panelMove);
      if (move.dataset.position === 'top') reordered.unshift(move.dataset.panelMove);
      else reordered.push(move.dataset.panelMove);
      Shiny.setInputValue('figure_order', reordered, { priority: 'event' });
    }
    const picture = event.target.closest('[data-gallery-image]');
    if (picture)
      Shiny.setInputValue('gallery_image', picture.dataset.galleryImage, { priority: 'event' });
    const panel = event.target.closest('[data-bulk-pick-panel]');
    if (panel)
      Shiny.setInputValue('bulk_pick_panel', panel.dataset.bulkPickPanel, { priority: 'event' });
    const button = event.target.closest('[data-update-package]');
    if (button && !button.disabled)
      Shiny.setInputValue('update_one_package', button.dataset.updatePackage, {
        priority: 'event',
      });
  });
});

window.addEventListener('message', (event) => {
  if (event.origin === location.origin && event.data?.type === 'ppi-cache-image') {
    Shiny.setInputValue('ppi_cache_image', event.data.png, { priority: 'event' });
  }
});

// Native drag starts exclusively on the explicit grip, never on previews/uploads.
(() => {
  let dragging = null;
  document.addEventListener('dragstart', (event) => {
    const panel = event.target.closest('[data-panel-drag]');
    const flow = event.target.closest('[data-flow-drag]');
    if (panel) dragging = { kind: 'panel', key: panel.dataset.panelDrag };
    else if (flow) dragging = { kind: 'flow', key: Number(flow.dataset.flowDrag) };
    else {
      if (event.target.closest('.figure-input-panel')) event.preventDefault();
      return;
    }
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', String(dragging.key));
  });
  const targetFor = (event) =>
    dragging?.kind === 'panel'
      ? event.target.closest('.figure-input-panel')
      : event.target.closest('[data-flow-index]');
  document.addEventListener('dragover', (event) => {
    if (!dragging) return;
    const target = targetFor(event);
    if (!target) return;
    event.preventDefault();
    document
      .querySelectorAll('.drop-before,.drop-after')
      .forEach((node) => node.classList.remove('drop-before', 'drop-after'));
    const after =
      event.clientY >
      target.getBoundingClientRect().top + target.getBoundingClientRect().height / 2;
    target.classList.add(after ? 'drop-after' : 'drop-before');
  });
  document.addEventListener(
    'drop',
    (event) => {
      if (!dragging) return;
      const target = targetFor(event);
      if (!target) return;
      event.preventDefault();
      event.stopPropagation();
      const panel = dragging.kind === 'panel';
      const nodes = Array.from(
        document.querySelectorAll(panel ? '.figure-input-panel' : '[data-flow-index]'),
      );
      const keyOf = (node) => (panel ? node.dataset.panelField : Number(node.dataset.flowIndex));
      const keys = nodes.map(keyOf).filter((key) => key !== dragging.key);
      const targetKey = keyOf(target);
      if (targetKey !== dragging.key) {
        const after =
          event.clientY >
          target.getBoundingClientRect().top + target.getBoundingClientRect().height / 2;
        keys.splice(keys.indexOf(targetKey) + Number(after), 0, dragging.key);
        Shiny.setInputValue(panel ? 'figure_order' : 'flow_reorder', keys, { priority: 'event' });
      }
      dragging = null;
      document
        .querySelectorAll('.drop-before,.drop-after')
        .forEach((node) => node.classList.remove('drop-before', 'drop-after'));
    },
    true,
  );
  document.addEventListener('dragend', () => {
    dragging = null;
    document
      .querySelectorAll('.drop-before,.drop-after')
      .forEach((node) => node.classList.remove('drop-before', 'drop-after'));
  });
})();

// Dynamic Shiny controls: keep the typed HEX value and its preview in sync.
(() => {
  const update = (preview) => {
    const input = document.getElementById(preview.dataset.colorPreviewFor);
    if (!input) return;
    const value = input.value.trim();
    const transparent = preview.dataset.allowTransparent === 'true' && value === 'transparent';
    const valid = transparent || /^#[0-9a-f]{6}$/i.test(value);
    preview.querySelector('.hex-color-swatch').style.backgroundColor = valid
      ? value
      : 'transparent';
    preview.querySelector('.hex-color-code').textContent = valid
      ? transparent
        ? '无填充'
        : value.toUpperCase()
      : '格式不正确';
    preview.setAttribute(
      'aria-label',
      valid ? `颜色预览 ${value}` : '请输入 # 加 6 位十六进制颜色',
    );
    input.setAttribute('aria-invalid', String(!valid));
  };
  const refresh = () => document.querySelectorAll('[data-color-preview-for]').forEach(update);
  document.addEventListener('input', (event) => {
    if (event.target.id?.startsWith('style_pathway_target_')) refresh();
  });
  document.addEventListener('change', refresh);
  document.addEventListener('DOMContentLoaded', () => {
    refresh();
    new MutationObserver((records) => {
      if (records.some((record) => [...record.addedNodes].some((node) => node.nodeType === 1)))
        refresh();
    }).observe(document.body, { childList: true, subtree: true });
  });
})();
