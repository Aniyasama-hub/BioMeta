"""Read-only article, tutorial, diagram and format-download regression."""
import argparse
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://127.0.0.1:7907')
parser.add_argument('--output', default='app/tests/_enhancements/biomethod-editorial')
args = parser.parse_args()
base = args.url.rstrip('/')
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
headings = ['定义解释', '分析原理', '分析操作', '适用范围', '参考与致谢']

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1440, 'height': 1000}, accept_downloads=True)
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    response = page.request.get(base + '/api/knowledge/catalog')
    assert response.ok, response.status
    catalog = response.json()
    concepts = [a for a in catalog['articles'] if a['article_type'] == 'concept']
    tutorials = [a for a in catalog['articles'] if a['article_type'] == 'technical']
    assert len(concepts) == len(tutorials) == 9
    assert {a['id'] for a in concepts} >= {'gmt', 'pca', 'reactome'}

    def visit(path):
        page.goto(base + path, wait_until='domcontentloaded')
        page.wait_for_function('document.getElementById("bm-content")?.getAttribute("aria-busy")==="false"')
        assert not page.locator('.bm-error').count(), page.locator('#bm-content').inner_text()

    def no_overflow():
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 2'), page.url

    for item in catalog['articles']:
        visit('/biomethod/articles/' + item['id'])
        assert page.locator('.bm-article h2').all_text_contents() == headings
        assert page.locator('.bm-process').count() >= 1
        assert not page.locator('.bm-toc,.katex-error').count()
        assert page.locator('.bm-process ol li').first.is_visible()
        if item['article_type'] == 'concept':
            assert page.locator('.bm-prose pre code.language-r').count() == 0
            assert page.get_by_role('heading', name='对应的工作站源码', exact=True).count() == 0
            assert page.get_by_role('heading', name='继续学习：逐行代码教程', exact=True).count() == 1
        else:
            assert page.locator('.bm-prose pre code.language-r').count() >= 1
        no_overflow()
        page.set_viewport_size({'width': 390, 'height': 844})
        no_overflow()
        size = page.locator('.bm-process span').first.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)')
        assert size >= 14, size
        page.set_viewport_size({'width': 1440, 'height': 1000})
    print('PASS 18 articles: headings, examples/diagrams, tutorial separation, math and mobile overflow', flush=True)

    visit('/biomethod/category/scripts')
    assert page.locator('.bm-entry-list .bm-entry').count() == len(tutorials)
    assert not page.locator('.bm-source-index').get_attribute('open')
    page.locator('.bm-source-index summary').click()
    assert page.locator('.bm-source-index .bm-entry').count() == len(catalog['scripts'])
    page.locator('.bm-source-index summary').focus()
    page.keyboard.press('Enter')
    assert page.locator('.bm-source-index').get_attribute('open') is None
    visit('/biomethod/scripts/pca-prepare')
    assert page.get_by_role('heading', name='逐行代码教程', exact=True).count() == 1
    page.locator('a[href="/biomethod/articles/pca-code"]').first.click()
    page.wait_for_url('**/biomethod/articles/pca-code')
    page.wait_for_function('document.getElementById("bm-content").getAttribute("aria-busy")==="false"')
    assert page.locator('.bm-prose pre').count() == 2
    page.reload(wait_until='domcontentloaded')
    page.wait_for_function('document.getElementById("bm-content").getAttribute("aria-busy")==="false"')
    assert page.locator('.bm-prose pre').count() == 2

    visit('/biomethod/articles/gmt')
    for name in ['custom-format-example.gmt', 'gene-set-members-template.csv']:
        with page.expect_download() as pending:
            page.locator(f'a[download][href$="/{name}"]').click()
        pending.value.save_as(out / name)
    gmt = (out / 'custom-format-example.gmt').read_text(encoding='utf-8')
    assert len(gmt.strip().splitlines()) == 2
    assert all(len(line.split('\t')) >= 3 for line in gmt.strip().splitlines())
    print('PASS script category, source-to-tutorial navigation, deep refresh and two real downloads', flush=True)

    for theme in ['night', 'classic']:
        for article in ['gmt', 'pca-code', 'pca']:
            visit('/biomethod/articles/' + article)
            # This page-local change tests theme CSS without writing personal settings.
            page.evaluate('(theme)=>document.documentElement.dataset.theme=theme', theme)
            page.locator('.bm-process').first.scroll_into_view_if_needed()
            page.screenshot(path=str(out / f'{theme}-{article}.png'))
            colors = page.locator('.bm-process').first.evaluate('''e=>({
                background:getComputedStyle(e).backgroundColor,
                color:getComputedStyle(e).color,
                height:e.getBoundingClientRect().height})''')
            assert colors['height'] > 200, colors
            page.set_viewport_size({'width': 390, 'height': 844})
            no_overflow()
            page.screenshot(path=str(out / f'{theme}-{article}-mobile.png'))
            page.set_viewport_size({'width': 1440, 'height': 1000})
    visit('/biomethod/search?q=GMT')
    assert page.locator('a[href="/biomethod/articles/gmt"]').count() >= 1
    assert page.locator('a[href="/biomethod/articles/gmt-code"]').count() >= 1
    assert not errors, errors
    browser.close()
    print('PASS both themes, desktop/mobile captures, GMT search and no browser errors', flush=True)
