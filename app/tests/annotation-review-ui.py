"""Current articles, live HEX previews and a real ORA run on synthetic input."""
import csv
import io
import json
import time
import zipfile
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'app'
OUT = APP / 'tests/_pathway-review/browser'
OUT.mkdir(parents=True, exist_ok=True)
BASE = 'http://127.0.0.1:7898'
HEADINGS = ['定义解释', '分析原理', '分析操作', '适用范围', '参考与致谢']

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1536, 'height': 1050}, accept_downloads=True)
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))

    def select(id, value):
        page.locator('#' + id).evaluate('(e,v)=>e.selectize.setValue(v)', value)
        page.wait_for_timeout(300)

    def settle():
        page.wait_for_function('document.getElementById("bm-content").getAttribute("aria-busy")==="false"')

    catalog = page.request.get(BASE + '/api/knowledge/catalog').json()
    assert {'pca', 'reactome', 'go-kegg', 'gmt', 'pca-code', 'gmt-code'} <= {x['id'] for x in catalog['articles']}
    inventory = page.request.get(BASE + '/api/knowledge/annotations').json()['items']
    assert {x['id'] for x in inventory} == {'go', 'kegg', 'reactome'}
    for article in catalog['articles']:
        page.goto(BASE + '/biomethod/articles/' + article['id'], wait_until='networkidle')
        settle()
        assert page.locator('.bm-article h2').all_text_contents() == HEADINGS
        assert not page.locator('.bm-toc').count()
        assert not page.locator('.bm-error').count()
        assert page.evaluate('document.documentElement.scrollWidth<=innerWidth+2')
    page.goto(BASE + '/biomethod/articles/pca', wait_until='networkidle')
    settle()
    assert len(page.locator('.bm-prose').inner_text()) > 12000
    assert page.locator('.katex').count() >= 4
    assert not page.locator('.katex-error').count()
    heading_id = page.locator('.bm-article h2').nth(2).get_attribute('id')
    page.goto(BASE + '/biomethod/articles/pca#' + heading_id, wait_until='networkidle')
    settle()
    assert '/biomethod/articles/pca#' in page.url
    page.reload(wait_until='networkidle')
    settle()
    assert page.locator('.bm-article h2').all_text_contents() == HEADINGS
    page.goto(BASE + '/biomethod/articles/reactome', wait_until='networkidle')
    settle()
    assert page.locator('.bm-annotation-library').count() == 1
    page.screenshot(path=str(OUT / 'reactome.png'))
    page.set_viewport_size({'width': 390, 'height': 844})
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth+2')
    page.screenshot(path=str(OUT / 'reactome-mobile.png'))
    page.set_viewport_size({'width': 1536, 'height': 1050})
    print('PASS all five-section articles, no TOC, PCA math/deep refresh and live annotation inventory', flush=True)

    for tool in ['go', 'kegg', 'gsea', 'gsva']:
        page.goto(BASE + '/workstation?tool=' + tool, wait_until='networkidle')
        page.locator('#gsea_sort').wait_for(state='attached')
        options = page.locator('#gsea_sort').evaluate('(e)=>Object.keys(e.selectize.options)')
        assert all(x in options for x in ['pvalue', 'padj', 'FDR'])
        assert not page.locator('.shiny-output-error').count()

    page.goto(BASE + '/workstation?tool=go', wait_until='networkidle')
    page.locator('#path_deg').wait_for()
    page.locator('#pathway_lookup').click()
    page.wait_for_function('(()=>{const s=document.getElementById("pathway_library_selection")?.selectize;return s && !s.isDisabled && Object.keys(s.options).length>0})()')
    page.locator('#pathway_library_selection-selectized').click()
    page.locator('#pathway_library_selection-selectized').fill('GO:0006955')
    page.locator('.selectize-dropdown .option[data-value="GO:0006955"]').click()
    page.locator('#pathway_library_add').click()
    page.wait_for_function('document.getElementById("target_pathways").value.includes("GO:0006955")')
    page.locator('#path_deg').fill(str(APP / 'tests/_pathway-review/probability_only.csv'))
    page.wait_for_function('Boolean(document.getElementById("ora_p_column")?.selectize?.options?.Study_adjP)')
    select('ora_p_column', 'Study_adjP')
    select('ora_filter_mode', 'probability')
    select('pathway_source', 'custom')
    page.locator('#path_gmt').fill(str(APP / 'examples/demo_sets.gmt'))
    page.locator('#database_version').evaluate('(e)=>{for(let n=e;n;n=n.parentElement)if(n.tagName==="DETAILS")n.open=true}')
    select('gmt_id_type', 'gene_id')
    page.locator('#database_version').fill('synthetic UI metric fixture')
    page.locator('#ora_fdr').fill('1')
    select('gsea_sort', 'pvalue')
    page.locator('#target_pathways').fill('Synthetic set 1\nDEMO_2')
    page.locator('input[name=target_pathway_input][value=table]').check()
    table = OUT / 'pathway_names.csv'
    table.write_text('pathway_name\nSynthetic set 3\n', encoding='utf-8')
    page.locator('#upload_pathway_names').set_input_files(table)
    page.wait_for_function('document.getElementById("path_pathway_names").value.length>0')
    with page.expect_download() as pending:
        page.locator('#download_pathway_template').click()
    pending.value.save_as(str(OUT / 'template.csv'))
    page.locator('input[name=target_pathway_input][value=text]').check()
    assert page.locator('#target_pathways').input_value() == 'Synthetic set 1\nDEMO_2'
    page.locator('#style_pathway_target_fill').evaluate('(e)=>{for(let n=e;n;n=n.parentElement)if(n.tagName==="DETAILS")n.open=true}')
    field = page.locator('#style_pathway_target_fill')
    field.fill('#FFF2CC')
    preview = page.locator('[data-color-preview-for=style_pathway_target_fill]')
    assert preview.locator('.hex-color-code').inner_text() == '#FFF2CC'
    assert preview.locator('.hex-color-swatch').evaluate('(e)=>getComputedStyle(e).backgroundColor') == 'rgb(255, 242, 204)'
    field.fill('not-a-color')
    assert field.get_attribute('aria-invalid') == 'true'
    field.fill('transparent')
    assert preview.locator('.hex-color-code').inner_text() == '无填充'
    field.fill('#FFF2CC')
    group = page.locator('fieldset.style-group').filter(has=page.locator('#style_pathway_target_fill'))
    group.screenshot(path=str(OUT / 'hex-controls.png'))
    select('style_enrichment_kind', 'bar')
    page.locator('#style_width').fill('7')
    page.locator('#style_height').fill('6')
    page.locator('#style_dpi').fill('96')
    page.locator('#run_tool').click()
    deadline = time.time() + 100
    while time.time() < deadline:
        if page.locator('.status-failed').count():
            raise AssertionError(page.locator('.status-failed').inner_text())
        if page.locator('.status-completed').count():
            break
        page.wait_for_timeout(300)
    else:
        raise AssertionError(page.locator('.shiny-notification').all_text_contents())
    page.wait_for_function('document.getElementById("download_zip").href.includes("/download/")')
    with page.expect_download() as pending:
        page.locator('#download_zip').click()
    archive = OUT / 'synthetic_go.zip'
    pending.value.save_as(str(archive))
    with zipfile.ZipFile(archive) as bundle:
        name = next(x for x in bundle.namelist() if x.endswith('target_pathway_matches.csv'))
        matches = list(csv.DictReader(io.StringIO(bundle.read(name).decode('utf-8-sig'))))
        assert {x['requested'] for x in matches} == {'Synthetic set 1', 'DEMO_2'}
        assert all(x['in_results'] == 'TRUE' for x in matches)
        name = next(x for x in bundle.namelist() if x.endswith('ora_input_selection.json'))
        metrics = json.loads(bundle.read(name))
        assert metrics['mode'] == 'probability' and metrics['probability_column'] == 'Study_adjP'
    page.screenshot(path=str(OUT / 'go-completed.png'))
    assert not errors, errors
    (OUT / 'ui-report.json').write_text(json.dumps({'passed': True, 'js_errors': errors}), encoding='utf-8')
    browser.close()
print('PASS real metric selection, name/ID recognition, exclusive input methods, template, HEX preview and ORA ZIP')
