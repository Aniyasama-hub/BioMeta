"""Live local UI; no persistent setting writes, package updates or new research analyses."""
import json
import zipfile
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE = 'http://127.0.0.1:7898'
OUT = Path('app/tests/_pathway-review/mapping-debug/browser')
OUT.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1536, 'height': 1050}, accept_downloads=True)
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto(BASE + '/workstation', wait_until='networkidle')
    page.locator('.tool-card-preview').first.wait_for()
    assert 'biometa' in page.title()
    assert page.locator('#workstation-host .brand strong').inner_text() == 'biometa (Beta)'
    for theme in ['night', 'classic']:
        page.evaluate('(theme)=>document.documentElement.dataset.theme=theme', theme)
        preview = page.locator('.tool-card-preview').first
        assert float(preview.evaluate('(e)=>getComputedStyle(e).opacity')) < .5
        assert preview.evaluate('(e)=>getComputedStyle(e).position') == 'absolute'
        assert preview.evaluate('(e)=>e.complete && e.naturalWidth>0')
        page.screenshot(path=str(OUT / (theme + '-home.png')))
    page.evaluate('document.documentElement.dataset.theme="night"')
    page.locator('#show_environment').click()
    page.locator('.modal-dialog a[data-value="运行环境"]').click()
    before = page.locator('#settings_rscript').input_value()
    page.locator('#runtime_method_rscript').evaluate('(e)=>e.selectize.setValue("detect")')
    choices = page.locator('#runtime_candidates_rscript input[type=radio]')
    choices.first.wait_for(timeout=60000)
    assert choices.count() >= 2
    assert page.locator('#runtime_candidates_rscript input:checked').count() == 0
    assert page.locator('#settings_rscript').input_value() == before
    values = choices.evaluate_all('(es)=>es.map(e=>e.value)')
    chosen = next(x for x in values if '/R-4.5.1/' in x)
    page.locator('#runtime_candidates_rscript input').filter().evaluate_all('(es,v)=>es.find(e=>e.value===v).click()', chosen)
    page.locator('#runtime_confirm_rscript').click()
    page.wait_for_function('(x)=>document.getElementById("settings_rscript").value===x', arg=chosen)
    page.locator('#runtime_candidates_rscript input').first.wait_for(state='detached')
    page.locator('#runtime_method_python').evaluate('(e)=>e.selectize.setValue("detect")')
    page.locator('#runtime_candidates_python input[type=radio]').first.wait_for(timeout=60000)
    assert page.locator('#runtime_candidates_python input:checked').count() == 0
    page.screenshot(path=str(OUT / 'multiple-runtimes.png'))
    page.locator('#runtime_cancel_python').click()
    page.locator('#runtime_method_rstudio').evaluate('(e)=>e.selectize.setValue("detect")')
    page.locator('#runtime_candidates_rstudio input[type=radio]').first.wait_for(timeout=60000)
    assert '2026.' in page.locator('#runtime_candidates_rstudio').inner_text()
    assert page.locator('#runtime_candidates_rstudio input:checked').count() == 0
    page.locator('#runtime_cancel_rstudio').click()
    page.locator('.modal-footer button').click()
    page.locator('.modal-backdrop').wait_for(state='hidden')
    page.locator('#refresh_history').click()
    page.locator('#history_modal .history-item').first.wait_for(timeout=60000)
    failed = page.locator('#history_modal .history-item').filter(has=page.locator('.history-failed')).first
    exported = failed.locator('.diagnostic-export')
    assert exported.evaluate('(e)=>getComputedStyle(e).backgroundColor') == 'rgb(167, 44, 58)'
    assert exported.evaluate('(e)=>getComputedStyle(e).animationName') == 'none'
    completed = page.locator('#history_modal .history-item').filter(has=page.locator('.history-completed')).first
    assert completed.locator('.diagnostic-disabled').is_disabled()
    with page.expect_download(timeout=60000) as pending:
        exported.click()
    archive = OUT / 'downloaded-failed-diagnostics.zip'
    pending.value.save_as(str(archive))
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        assert 'task/inputs/deg.csv' in names
        assert 'task/parameters.json' in names
        assert 'task/job.log' in names
        assert 'diagnostic_manifest.csv' in names
        assert any(x.endswith('/R/gene_mapping.R') for x in names)
    page.screenshot(path=str(OUT / 'history-diagnostics.png'))
    failed.locator('[data-run]').click()
    page.locator('.mapping-quality').wait_for(timeout=60000)
    page.locator('.mapping-quality summary').click()
    assert '确认冲突' in page.locator('.mapping-quality').inner_text()
    assert 'BW-M02' in page.locator('.task-error').inner_text()
    page.screenshot(path=str(OUT / 'mapping-failure.png'))
    page.set_viewport_size({'width': 390, 'height': 844})
    page.goto(BASE + '/workstation', wait_until='networkidle')
    page.locator('.tool-card').first.wait_for()
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth+2')
    page.screenshot(path=str(OUT / 'night-mobile.png'))
    assert not errors, errors
    (OUT / 'report.json').write_text(json.dumps({'passed': True, 'js_errors': errors}), encoding='utf-8')
    browser.close()
print('PASS biometa brand, translucent cards, real multiple-runtime choice, disabled success/red failed exports, actual diagnostic ZIP, mapping summary and mobile')
