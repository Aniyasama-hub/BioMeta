/* global Shiny, BioMethod */
(() => {
  const config = JSON.parse(document.getElementById('platform-config').textContent);
  let connected = false;
  let initialized = false;
  let routeTarget = null;
  let nonce = 0;

  // All projects share one local Shiny application, including on a deep-link refresh.
  Shiny.createSocket = () => {
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const socket = new WebSocket(`${protocol}//${location.host}/websocket/`);
    socket.binaryType = 'arraybuffer';
    return socket;
  };

  function label(project) {
    return project.name_en + (project.stage ? ` (${project.stage})` : '');
  }

  function applyRoute(url, dispatch = true) {
    const project =
      config.projects.find(
        (entry) => url.pathname === entry.route || url.pathname.startsWith(`${entry.route}/`),
      ) || config.projects[0];
    const knowledge = project.id === 'biomethod';
    document.getElementById('workstation-host').hidden = knowledge;
    document.getElementById('biomethod-root').hidden = !knowledge;
    document.body.dataset.project = project.id;
    if (connected) Shiny.setInputValue('platform_project', project.id, { priority: 'event' });
    document.querySelectorAll('[data-project-option]').forEach((item) => {
      if (item.dataset.projectOption === project.id) item.setAttribute('aria-current', 'page');
      else item.removeAttribute('aria-current');
    });
    if (knowledge) {
      BioMethod.render(url, label(project));
    } else {
      document.title = label(project) + ' · 生信分析工作站';
      if (dispatch && connected) {
        const tool = url.searchParams.get('tool') || 'home';
        routeTarget = config.tools.includes(tool) ? tool : 'home';
        if (routeTarget === 'home')
          Shiny.setInputValue('platform_home', ++nonce, { priority: 'event' });
        else Shiny.setInputValue('tool_id', routeTarget, { priority: 'event' });
      }
    }
    document.dispatchEvent(new Event('shiny:visualchange'));
  }

  function navigate(href, { replace = false, dispatch = true } = {}) {
    const url = new URL(href, location.origin);
    if (replace) history.replaceState({}, '', url.pathname + url.search + url.hash);
    else history.pushState({}, '', url.pathname + url.search + url.hash);
    applyRoute(url, dispatch);
    window.scrollTo(0, 0);
  }

  window.ResearchPlatform = { config, navigate, label };
  document.addEventListener('DOMContentLoaded', () => {
    Shiny.addCustomMessageHandler('platform-feature', ({ feature }) => {
      if (document.body.dataset.project !== 'workstation') return;
      if (routeTarget && feature !== routeTarget) return;
      routeTarget = null;
      const route =
        feature === 'home' ? '/workstation' : `/workstation?tool=${encodeURIComponent(feature)}`;
      if (location.pathname + location.search !== route) history.replaceState({}, '', route);
    });
    window.jQuery(document).on('shiny:connected.platform', () => {
      connected = true;
      if (!initialized) {
        initialized = true;
        applyRoute(new URL(location.href));
      }
    });
    window.jQuery(document).on('shiny:disconnected.platform', () => {
      connected = false;
    });
    applyRoute(new URL(location.href), false);
  });
  window.addEventListener('popstate', () => applyRoute(new URL(location.href)));
  document.addEventListener('click', (event) => {
    if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey)
      return;
    const settings = event.target.closest('[data-platform-settings]');
    if (settings) {
      document.getElementById('show_environment').click();
      return;
    }
    const tool = event.target.closest('[data-tool]');
    if (tool && config.tools.includes(tool.dataset.tool)) {
      navigate(`/workstation?tool=${encodeURIComponent(tool.dataset.tool)}`, { dispatch: false });
      return;
    }
    const anchor = event.target.closest('a[href]');
    if (!anchor || anchor.target === '_blank' || anchor.hasAttribute('download')) return;
    const url = new URL(anchor.href);
    const rawHref = anchor.getAttribute('href');
    if (
      rawHref.startsWith('#') ||
      (url.origin === location.origin &&
        url.pathname === location.pathname &&
        url.search === location.search &&
        url.hash)
    ) {
      const hash = rawHref.startsWith('#') ? rawHref : url.hash;
      let id;
      try {
        id = decodeURIComponent(hash.slice(1));
      } catch {
        return;
      }
      const target = document.getElementById(id);
      if (!target) return;
      event.preventDefault();
      history.pushState({}, '', location.pathname + location.search + hash);
      target.scrollIntoView({ block: 'start' });
      target.setAttribute('tabindex', '-1');
      target.focus({ preventScroll: true });
      return;
    }
    if (url.origin !== location.origin) return;
    const project = config.projects.find(
      (p) => url.pathname === p.route || url.pathname.startsWith(`${p.route}/`),
    );
    if (!project || !['workstation', 'biomethod'].includes(project.id)) return;
    event.preventDefault();
    document.querySelectorAll('.platform-switcher[open]').forEach((menu) => {
      menu.open = false;
    });
    navigate(url.href);
  });
})();
