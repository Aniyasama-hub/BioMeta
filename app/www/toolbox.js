document.addEventListener('click', function (event) {
  const tool = event.target.closest('[data-tool]');
  if (tool && window.Shiny) {
    Shiny.setInputValue('tool_id', tool.dataset.tool, { priority: 'event' });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
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
