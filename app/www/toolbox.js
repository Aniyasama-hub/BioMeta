document.addEventListener('click', function (event) {
  const tool = event.target.closest('[data-tool]');
  if (tool && window.Shiny) {
    Shiny.setInputValue('tool_id', tool.dataset.tool, { priority: 'event' });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
  const page = event.target.closest('[data-history-page]');
  if (page && window.Shiny) Shiny.setInputValue('history_page', Number(page.dataset.historyPage), {priority: 'event'});
  const remove = event.target.closest('[data-run-delete]');
  if (remove && window.Shiny) Shiny.setInputValue('history_delete', remove.dataset.runDelete, {priority: 'event'});
  const run = event.target.closest('[data-run]');
  if (run && window.Shiny) {
    Shiny.setInputValue('history_run', run.dataset.run, { priority: 'event' });
  }
});

// One shared, local tooltip. Text is always inserted as textContent, never HTML.
(() => {
  const tip = document.createElement('div');
  tip.id = 'context-tooltip';
  tip.className = 'context-tooltip';
  tip.setAttribute('role', 'tooltip');
  tip.hidden = true;
  let active = null;
  let timer = null;

  function hide() {
    clearTimeout(timer);
    if (active) active.removeAttribute('aria-describedby');
    active = null;
    tip.hidden = true;
  }

  function show(host, point) {
    hide();
    if (!host || !host.dataset.help) return;
    active = host;
    timer = setTimeout(() => {
      if (!host.isConnected) return hide();
      tip.textContent = host.dataset.help;
      tip.hidden = false;
      host.setAttribute('aria-describedby', tip.id);
      const rect = host.getBoundingClientRect();
      const x = point ? point.x + 14 : rect.left;
      const y = point ? point.y + 20 : rect.bottom + 8;
      tip.style.left = Math.max(12, Math.min(x, innerWidth - tip.offsetWidth - 12)) + 'px';
      tip.style.top = Math.max(12, Math.min(y, innerHeight - tip.offsetHeight - 12)) + 'px';
    }, 160);
  }

  function hydrate() {
    if (active && !active.isConnected) hide();
    document.querySelectorAll('.context-note:not([data-ready])').forEach(note => {
      note.dataset.ready = 'true';
      let host = note.previousElementSibling;
      if (!host || host.classList.contains('context-note')) host = note.parentElement;
      if (host.classList.contains('shiny-html-output')) host = host.closest('.panel') || host;
      // Put explanations on the relevant control, not in the document's reading flow.
      const text = note.dataset.note;
      host.dataset.help = [host.dataset.help, text].filter(Boolean).join('\n\n');
    });
    document.querySelectorAll('[data-help]:not([data-help-ready])').forEach(host => {
      host.dataset.helpReady = 'true';
      if (!host.matches('button,a,input,summary,[tabindex]')) host.tabIndex = 0;
      const heading = host.matches('h1,h3,summary,label') ? host :
        host.querySelector('label.control-label,h3,summary');
      if (heading && !heading.querySelector('.help-mark')) {
        const mark = document.createElement('span');
        mark.className = 'help-mark';
        mark.textContent = '?';
        mark.setAttribute('aria-hidden', 'true');
        heading.append(mark);
      }
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    document.body.append(tip);
    hydrate();
    new MutationObserver(hydrate).observe(document.querySelector('.app-shell'), {childList:true, subtree:true});
  });
  document.addEventListener('mouseover', event => {
    const host = event.target.closest('[data-help]');
    if (host !== active) show(host, {x:event.clientX, y:event.clientY});
  });
  document.addEventListener('mouseout', event => {
    if (active && (!event.relatedTarget || !active.contains(event.relatedTarget))) hide();
  });
  document.addEventListener('focusin', event => show(event.target.closest('[data-help]')));
  document.addEventListener('focusout', hide);
  document.addEventListener('keydown', event => { if (event.key === 'Escape') hide(); });
  document.addEventListener('scroll', hide, true);
  window.addEventListener('resize', hide);
  // Touch devices have no hover: tap a help mark; tap outside to dismiss.
  document.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'touch') return;
    const host = event.target.closest('.help-mark')?.closest('[data-help]');
    if (host && host !== active) show(host); else hide();
  });
})();
(() => {
  const normalize = token => {
    token = token.trim();
    if (/^#[\da-f]{3}$/i.test(token)) return '#' + [...token.slice(1)].map(c => c + c).join('');
    if (/^#[\da-f]{6}$/i.test(token)) return token;
    const rgb = /^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/i.exec(token);
    if (rgb && rgb.slice(1).every(value => Number(value) <= 255))
      return '#' + rgb.slice(1).map(value => Number(value).toString(16).padStart(2, '0')).join('');
    return null;
  };
  const input = panel => panel.querySelector('#style_gradient');
  const stops = panel => (input(panel).value || panel.dataset.defaultColors).split(';').map(normalize);
  const render = panel => {
    const colors = stops(panel);
    const ramp = panel.querySelector('.palette-current');
    if (!colors.length || colors.length > 8 || colors.some(color => !color)) {
      ramp.style.background = '';
      ramp.textContent = '请检查颜色格式';
      return;
    }
    ramp.textContent = '';
    ramp.style.background = colors.length === 1 ? colors[0] : 'linear-gradient(90deg,' + colors.join(',') + ')';
    ramp.title = colors.join(' · ');
    panel.querySelector('.palette-mode').value = String(Math.min(colors.length, 4));
    const controls = colors.map((color, index) => {
      const picker = document.createElement('input');
      picker.type = 'color';
      picker.value = color;
      picker.dataset.stop = index;
      picker.setAttribute('aria-label', '颜色 ' + (index + 1));
      return picker;
    });
    panel.querySelector('.palette-pickers').replaceChildren(...controls);
  };
  const setColors = (panel, colors) => {
    const target = input(panel);
    target.value = colors.join('; ');
    target.dispatchEvent(new Event('change', {bubbles: true}));
    render(panel);
  };
  document.addEventListener('click', event => {
    const button = event.target.closest('.palette-option');
    if (!button) return;
    const panel = button.closest('.palette-tool');
    setColors(panel, button.dataset.colors.split(';'));
    panel.querySelector('summary').textContent = button.querySelector('span').textContent;
    panel.querySelector('details').open = false;
  });
  document.addEventListener('input', event => {
    const panel = event.target.closest('.palette-tool');
    if (panel && event.target === input(panel)) render(panel);
  });
  document.addEventListener('change', event => {
    const panel = event.target.closest('.palette-tool');
    if (!panel) return;
    if (event.target.matches('.palette-mode')) {
      const colors = stops(panel).filter(Boolean);
      const fallback = ['#245F67', '#EFEBD9', '#A95A46', '#704B80'];
      const n = Number(event.target.value);
      setColors(panel, Array.from({length:n}, (_, i) => colors[i] || fallback[i]));
    } else if (event.target.matches('input[data-stop]')) {
      const colors = stops(panel);
      colors[Number(event.target.dataset.stop)] = event.target.value;
      setColors(panel, colors);
    }
  });
  const initialize = () => document.querySelectorAll('.palette-tool:not([data-ready])').forEach(panel => {
    panel.dataset.ready = 'true';
    render(panel);
  });
  document.addEventListener('DOMContentLoaded', () => {
    initialize();
    new MutationObserver(initialize).observe(document.body, {childList:true, subtree:true});
  });
})();
