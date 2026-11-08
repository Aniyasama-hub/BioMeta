"""Explicit identifier/name selections reach a real GO worker, using synthetic data."""
import csv
import io
import tempfile
import time
import zipfile
from pathlib import Path

from playwright.sync_api import sync_playwright


with tempfile.TemporaryDirectory(prefix='bioworkbench-mapping-') as temp:
    fixture = Path(temp) / 'synthetic_aliases.csv'
    with Path('app/examples/demo_deg.csv').open(encoding='utf-8-sig') as source:
        rows = list(csv.DictReader(source))
    fields = list(rows[0])
    with fixture.open('w', encoding='utf-8', newline='') as target:
        writer = csv.writer(target)
        writer.writerow([
            'input_identifier' if x == 'gene_id' else
            'input_symbol' if x == 'gene_name' else x for x in fields
        ])
        writer.writerows([[row[x] for x in fields] for row in rows])

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page(accept_downloads=True)
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))

        def select(selector, value):
            page.locator(selector).evaluate('(e,v)=>e.selectize.setValue(v)', value)

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
                '(n)=>document.querySelectorAll("[data-flow-remove]").length===n',
                arg=count - 1,
            )
        select('#flow_add_tool', 'go')
        page.locator('#flow_add').click()
        page.wait_for_timeout(400)
        page.locator('#flow_plan_start').click()
        page.locator('#upload_deg').set_input_files(str(fixture))
        page.wait_for_function(
            'Boolean(document.getElementById("gene_id_column")?.selectize?.options?.input_identifier)'
        )
        select('#gene_id_column', 'input_identifier')
        select('#gene_name_column', 'input_symbol')
        select('#pathway_source', 'custom')
        page.locator('#upload_gmt').set_input_files(
            str(Path('app/examples/demo_sets.gmt').resolve())
        )
        page.locator('#parameter_controls details').last.locator('summary').click()
        select('#gmt_id_type', 'gene_id')
        page.locator('#database_version').fill('synthetic UI mapping validation')
        page.wait_for_timeout(500)
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
        page.locator('#download_bulk_all').wait_for()
        page.wait_for_function(
            'document.getElementById("download_bulk_all").getAttribute("href")!==""'
        )
        with page.expect_download() as pending:
            page.locator('#download_bulk_all').click()
        archive = Path(temp) / 'mapping.zip'
        pending.value.save_as(str(archive))
        with zipfile.ZipFile(archive) as bundle:
            name = next(x for x in bundle.namelist() if x.endswith('input_gene_mapping.csv'))
            mapped = list(csv.DictReader(io.StringIO(bundle.read(name).decode('utf-8-sig'))))
        assert [x['gene_id'] for x in mapped] == [x['gene_id'] for x in rows]
        assert [x['gene_name'] for x in mapped] == [x['gene_name'] for x in rows]
        assert not errors, errors
        browser.close()
print('PASS workflow upload header discovery, selected mapping/source and real GO audit export')
