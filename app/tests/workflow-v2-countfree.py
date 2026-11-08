"""Custom plotting and one-panel composition without Count/group input."""
from pathlib import Path
import time
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))

    def run():
        old = page.locator('.status-card').get_attribute('data-job-id')
        page.locator('#run_tool').click()
        page.wait_for_function(
            '(old)=>document.querySelector(".status-card")?.dataset.jobId && '
            'document.querySelector(".status-card").dataset.jobId!==old', arg=old
        )
        deadline = time.time() + 90
        while time.time() < deadline:
            if page.locator('.status-failed').count():
                raise AssertionError(page.locator('.status-failed').inner_text())
            if page.locator('.status-completed').count():
                return
            page.wait_for_timeout(300)
        raise AssertionError('Synthetic worker timeout')

    page.goto('http://127.0.0.1:7898/workstation', wait_until='networkidle')
    page.locator('.hero-start').click()
    page.locator('#path_counts').wait_for()
    page.locator('#path_counts').fill('')
    page.locator('#path_groups').fill('')
    page.wait_for_timeout(400)
    page.locator('#bulk_start').click()
    page.locator('#flow_plan_start').wait_for()
    page.locator('input[name=flow_plan_mode][value=default]').check()
    page.wait_for_timeout(400)
    for count in range(10, 0, -1):
        page.locator('[data-flow-remove]').first.click()
        page.wait_for_function(
            '(n)=>document.querySelectorAll("[data-flow-remove]").length===n', arg=count - 1
        )
    for tool in ['beeswarm', 'figure_layout']:
        page.locator('#flow_add_tool').evaluate('(e,v)=>e.selectize.setValue(v)', tool)
        page.locator('#flow_add').click()
        page.wait_for_timeout(400)
    page.locator('#flow_plan_start').click()
    page.locator('#path_matrix').wait_for()
    assert not page.locator('#path_counts').count()
    assert not page.locator('#path_groups').count()
    page.locator('#upload_matrix').set_input_files(
        str(Path('app/examples/demo_beeswarm.csv').resolve())
    )
    page.wait_for_function('document.getElementById("path_matrix").value.length>0')
    run()
    page.locator('#bulk_next').click()
    page.locator('.bulk-gallery-item').first.wait_for()
    assert not page.locator('#gallery_step').count()
    assert 'beeswarm' in page.locator('.bulk-gallery-item').first.inner_text()
    page.locator('.bulk-gallery-item').first.click()
    page.locator('#bulk_gallery_continue').click()
    page.locator('#panel_auto_favorites').check()
    page.wait_for_function('document.getElementById("panel_count").value==="1"')
    page.wait_for_function('document.getElementById("path_panel_01").value.length>0')
    run()
    assert page.locator('#download_bulk_all').count() == 1
    assert not errors, errors
    browser.close()
print('PASS Count-free custom tool, its current-step gallery and actual one-panel composition')
