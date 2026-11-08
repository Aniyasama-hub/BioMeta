"""BioMethod/Workstation integration against a real local Shiny server.
Uses built-in synthetic inputs only. Requires Python Playwright.
"""
import argparse
import hashlib
import json
import re
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://127.0.0.1:7898')
parser.add_argument('--output', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1536, 'height': 1000})
    errors = []
    sockets = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('websocket', lambda socket: sockets.append(socket.url))

    def settle():
        page.wait_for_function("document.getElementById('bm-content').getAttribute('aria-busy') === 'false'")

    def go(path):
        page.goto(args.url + path, wait_until='networkidle')
        if path.startswith('/biomethod'):
            settle()
        else:
            page.locator('.tool-card, .tool-workspace').first.wait_for()

    def menu(project):
        host = '#biomethod-root' if page.locator('#biomethod-root').is_visible() else '#workstation-host'
        page.locator(host + ' .platform-switcher summary').click()
        assert page.locator(host + ' .platform-projects [aria-current="page"]').count() == 1
        page.locator(host + f' [data-project-option="{project}"]').click()

    manifest = page.request.get(args.url + '/api/knowledge/catalog').json()
    assert len(manifest['articles']) == 18
    for article in manifest['articles']:
        result = page.request.get(args.url + '/api/knowledge/articles/' + article['id'])
        assert result.status == 200
        headings = re.findall(r'<h2\b[^>]*>(.*?)</h2>', result.json()['html'], re.S)
        assert [re.sub(r'<[^>]+>', '', h).strip() for h in headings] == ['定义解释', '分析原理', '分析操作', '适用范围', '参考与致谢']
        for ref_id in article['references']:
            assert any(ref['id'] == ref_id for ref in manifest['references'])
    for script in manifest['scripts']:
        result = page.request.get(args.url + '/api/knowledge/scripts/' + script['id'])
        assert result.status == 200
        value = result.json()
        assert value['sha256'] == hashlib.sha256((root / value['path']).read_bytes()).hexdigest()
        assert value['parameters']
    assert page.request.get(args.url + '/api/knowledge/catalog?q=PCA').json()['articles']
    assert page.request.get(args.url + '/api/knowledge/catalog?category=workflows').json()['articles'][0]['id'] == 'bulk-rnaseq'
    assert page.request.get(args.url + '/api/knowledge/videos').json()['items'] == []
    assert page.request.get(args.url + '/api/knowledge/videos/schema').json()['properties']['chapters']
    # httpuv's static-path guard may reject non-GET before Shiny dispatch.
    assert page.request.post(args.url + '/api/knowledge/articles/pca', data='{}').status in (400, 405)
    assert page.request.get(args.url + '/api/knowledge/scripts/unregistered').status == 404
    assert page.request.get(args.url + '/api/knowledge/articles/unregistered').status == 404
    assert page.request.get(args.url + '/platform-assets/platform.R').status == 404
    print('PASS content API, registered script hashes, query filters, readonly endpoints and backend-only video schema')

    go('/workstation')
    menu('biomethod')
    settle()
    assert page.url.endswith('/biomethod')
    assert page.locator('#bm-content h1').inner_text() == 'BioMethod (Beta)'
    assert page.locator('.bm-category-grid a').count() == 4
    assert not page.locator('#workstation-host').is_visible()
    assert '视频' not in page.locator('#biomethod-root').inner_text()
    page.screenshot(path=str(out / 'biomethod-home.png'))
    for category in ['workflows', 'methods', 'scripts', 'references']:
        page.locator(f'.bm-sidebar > nav a[href="/biomethod/category/{category}"]').click()
        settle()
        assert not page.locator('.bm-error').count()
    go('/biomethod/articles/pca')
    assert page.locator('.katex').count() >= 4
    assert page.locator('.katex-error').count() == 0
    assert page.locator('.bm-prose a[href="/biomethod/articles/pca-code"]').count() >= 1
    assert page.locator('.bm-toc').count() == 0
    assert page.locator('.bm-prose img').count() == 1
    page.locator('.bm-prose img').scroll_into_view_if_needed()
    page.wait_for_function("document.querySelector('.bm-prose img').complete && document.querySelector('.bm-prose img').naturalWidth > 0")
    page.evaluate('window.scrollTo(0,0)')
    page.screenshot(path=str(out / 'biomethod-pca.png'))
    page.reload(wait_until='networkidle')
    settle()
    assert page.locator('.katex').count() >= 4
    go('/biomethod/articles/pca-code')
    assert page.locator('pre code.hljs').count() >= 1
    page.locator('a[href="/biomethod/scripts/pca-prepare"]').first.click()
    settle()
    assert 'prepare_bundle' in page.locator('pre code').inner_text()
    assert page.locator('.bm-source-hash').inner_text().startswith('SHA-256:')
    page.go_back()
    settle()
    assert page.url.endswith('/biomethod/articles/pca-code')
    page.go_forward()
    settle()
    assert page.url.endswith('/biomethod/scripts/pca-prepare')
    go('/biomethod')
    page.locator('#bm-search-input').fill('VST')
    page.locator('.bm-search button').click()
    settle()
    assert page.locator('.bm-entry').count() >= 2
    page.locator('#bm-search-input').fill('<img src=x onerror=window.injected=true>')
    page.locator('.bm-search button').click()
    settle()
    assert not page.evaluate('Boolean(window.injected)')
    assert '找到 0 项' in page.locator('.bm-search-count').inner_text()
    go('/biomethod/articles/not-registered')
    assert page.locator('.bm-error').count() == 1
    go('/workstation?tool=pca')
    page.locator('#pca_top').wait_for()
    page.locator('.analysis-guide').click()
    settle()
    assert page.url.endswith('/biomethod/articles/pca')
    page.locator('.bm-prose a[href="/workstation?tool=pca"]').first.click()
    page.locator('#pca_top').wait_for()
    assert page.url.endswith('/workstation?tool=pca')
    print('PASS logo selection, independent deep refresh, four libraries, PCA math/code/image and no side TOC, search, error state, back/forward and bidirectional links')

    go('/workstation?tool=kegg')
    page.locator('#show_environment').click()
    page.locator('.modal-dialog').wait_for()
    page.locator('.modal-dialog a[data-value="示例数据"]').click()
    page.locator('#example_catalog .selectize-input').click()
    page.locator('#example_catalog .selectize-dropdown .option[data-value="synthetic"]').click()
    page.locator('.modal-footer .btn').click()
    page.locator('.modal-dialog').wait_for(state='hidden')
    page.locator('.modal-backdrop').wait_for(state='hidden')
    page.locator('#example_kegg').check()
    page.wait_for_timeout(800)
    before_sockets = len(sockets)
    before_jobs = set((root / 'app/results/toolbox/jobs').iterdir())
    page.locator('#run_tool').click()
    page.locator('#cancel_job').wait_for(timeout=30000)
    menu('biomethod')
    settle()
    assert page.locator('#biomethod-root').is_visible()
    assert len(sockets) == before_sockets
    page.go_back()
    page.locator('#workstation-host').wait_for(state='visible')
    deadline = time.time() + 120
    while time.time() < deadline:
        if page.locator('.status-failed').count():
            raise AssertionError(page.locator('.status-failed').inner_text())
        if page.locator('.status-completed').count():
            break
        page.wait_for_timeout(300)
    else:
        raise AssertionError('Analysis did not complete after project switch')
    assert len(sockets) == before_sockets
    new_jobs = set((root / 'app/results/toolbox/jobs').iterdir()) - before_jobs
    assert len(new_jobs) == 1
    state = json.loads((next(iter(new_jobs)) / 'status.json').read_text(encoding='utf-8'))
    assert state['status'] == 'completed'
    page.locator('a[data-value="图形预览"]').click()
    page.wait_for_timeout(500)
    page.evaluate('window.scrollTo(0,0)')
    page.screenshot(path=str(out / 'workstation-after-switch.png'))
    print('PASS actual synthetic KEGG continued in the same Shiny WebSocket/session while visiting BioMethod')

    go('/biomethod')
    for theme in ['classic', 'night']:
        page.locator('[data-platform-settings]').click()
        page.locator('.modal-dialog').wait_for()
        page.locator('.modal-dialog a[data-value="界面风格"]').click()
        page.locator(f'input[name="settings_theme"][value="{theme}"]').check()
        page.locator('#settings_theme_save').click()
        page.wait_for_function('(theme)=>document.documentElement.dataset.theme === theme', arg=theme)
        page.locator('.modal-footer .btn').click()
        page.locator('.modal-dialog').wait_for(state='hidden')
        page.locator('.modal-backdrop').wait_for(state='hidden')
        for notification in page.locator('.shiny-notification-close').all():
            notification.click()
        page.screenshot(path=str(out / f'biomethod-{theme}.png'))
    summary = page.locator('#biomethod-root .platform-switcher summary')
    summary.focus()
    summary.press('Enter')
    assert page.locator('#biomethod-root .platform-switcher').get_attribute('open') is not None
    summary.press('Enter')
    page.set_viewport_size({'width': 390, 'height': 844})
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 2')
    page.screenshot(path=str(out / 'biomethod-mobile.png'))
    go('/biomethod/articles/pca')
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 2')
    page.screenshot(path=str(out / 'biomethod-pca-mobile.png'))
    go('/biomethod/scripts/pca-prepare')
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 2')
    print('PASS BioMethod settings, two themes, keyboard project menu and mobile article/script layouts')
    assert not errors, errors
    (out / 'report.json').write_text(json.dumps({'passed': True, 'articles': len(manifest['articles']), 'script_mappings': len(manifest['scripts']), 'references': len(manifest['references']), 'js_errors': errors, 'task_switch': 'real synthetic KEGG; same WebSocket'}, ensure_ascii=False, indent=2), encoding='utf-8')
    browser.close()
print('PASS BioMethod integration')
