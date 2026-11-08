/* global Shiny */
(() => {
  const themes = new Set(['night', 'classic']);
  let executionBusy = false;
  let refreshPending = false;

  function applyTheme(value) {
    document.documentElement.dataset.theme = themes.has(value) ? value : 'night';
  }

  function syncExecutionButtons() {
    refreshPending = false;
    ['run_tool', 'redraw', 'bulk_start'].forEach((id) => {
      const button = document.getElementById(id);
      if (!button) {
        return;
      }
      if (!button.dataset.restLabel) {
        button.dataset.restLabel = button.textContent;
      }
      button.disabled = executionBusy;
      button.setAttribute('aria-disabled', String(executionBusy));
      const label = executionBusy ? '后台正在执行…' : button.dataset.restLabel;
      if (button.textContent !== label) {
        button.textContent = label;
      }
    });
  }

  // Shiny replaces control nodes when tools change; retain the latest worker state.
  function scheduleButtonSync() {
    if (!refreshPending) {
      refreshPending = true;
      window.requestAnimationFrame(syncExecutionButtons);
    }
  }

  applyTheme(document.documentElement.dataset.theme);
  document.addEventListener('DOMContentLoaded', () => {
    Shiny.addCustomMessageHandler('workbench-theme', (state) => applyTheme(state.theme));
    Shiny.addCustomMessageHandler('analysis-state', (state) => {
      executionBusy = Boolean(state.busy);
      syncExecutionButtons();
    });
    const workspace = document.querySelector('.main-shell');
    if (workspace) {
      new MutationObserver(scheduleButtonSync).observe(workspace, {
        childList: true,
        subtree: true,
      });
    }
  });

  document.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (
      !button ||
      button.disabled ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches
    ) {
      return;
    }
    // Web Animations avoids a synchronous layout read on every click.
    button.animate(
      [{ filter: 'brightness(1)' }, { filter: 'brightness(1.22)' }, { filter: 'brightness(1)' }],
      { duration: 250, easing: 'ease-out' },
    );
  });
})();
