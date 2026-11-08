"""Real local Shiny checks with synthetic inputs; restore user settings afterward."""
import json
import time
import zipfile
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/_enhancements/browser"
OUT.mkdir(parents=True, exist_ok=True)
settings = ROOT / "results/toolbox/settings.json"
original = settings.read_bytes() if settings.exists() else None
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1536, "height": 1100}, accept_downloads=True)
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))

    def select(id, value):
        page.locator("#" + id).evaluate("(e,v)=>e.selectize.setValue(v)", value)
        page.wait_for_timeout(400)

    def close():
        page.locator(".modal-footer .btn").click()
        page.locator(".modal-backdrop").wait_for(state="hidden")

    def go(tool):
        page.goto("http://127.0.0.1:7898/workstation?tool=" + tool, wait_until="networkidle")
        page.locator(".tool-workspace").wait_for()

    def run():
        before = page.locator(".status-card").get_attribute("data-job-id")
        page.locator("#run_tool").click()
        try:
            page.wait_for_function("old=>document.querySelector('.status-card')?.dataset.jobId && document.querySelector('.status-card').dataset.jobId!==old", arg=before, timeout=30000)
        except Exception:
            raise AssertionError(page.locator(".shiny-notification").all_text_contents())
        deadline = time.time() + 160
        while time.time() < deadline:
            if page.locator(".status-failed").count():
                raise AssertionError(page.locator(".status-failed").inner_text())
            if page.locator(".status-completed").count():
                page.wait_for_timeout(400)
                return
            page.wait_for_timeout(300)
        raise AssertionError("Synthetic worker timed out")

    try:
        go("volcano")
        page.locator("#show_environment").click()
        page.locator('.modal-dialog a[data-value="界面风格"]').click()
        page.locator('input[name="settings_theme"][value="night"]').check()
        page.locator("#settings_theme_save").click()
        page.locator('.modal-dialog a[data-value="示例数据"]').click()
        select("example_choice", "synthetic")
        with page.expect_download() as downloaded:
            page.locator("#download_example_data").click()
        archive = OUT / "synthetic.zip"
        downloaded.value.save_as(archive)
        with zipfile.ZipFile(archive) as z:
            assert "demo_counts.csv" in z.namelist() and "demo_sets.gmt" in z.namelist()
        page.locator('.modal-dialog a[data-value="保存设置"]').click()
        page.locator("#settings_export_folder").fill(str(OUT / "saved-results"))
        page.locator("#settings_workflow_autosave").check()
        page.locator("#settings_storage_save").click()
        close()
        page.locator("#example_volcano").check()
        page.locator("#target_text").fill("g001\ng002")
        page.locator('.style-panel > summary, .style-panel summary').first.click() if page.locator('.style-panel > summary').count() else None
        # Inspect rendered controls directly even when the enclosing details is collapsed.
        background = page.locator(".palette-tool").evaluate("e=>getComputedStyle(e).backgroundColor")
        assert background == "rgb(34, 42, 53)", background
        run()
        page.locator(".palette-tool").evaluate("e=>{for(let n=e;n;n=n.parentElement)if(n.tagName==='DETAILS')n.open=true}")
        page.locator(".palette-tool").scroll_into_view_if_needed()
        page.screenshot(path=str(OUT / "night-palette.png"))
        job_id = page.locator(".status-card").get_attribute("data-job-id")
        assert (OUT / "saved-results" / ("BioWorkbench-" + job_id) / "reproduce.R").exists()
        print("PASS settings example download, storage destination, dark palette and volcano targets", flush=True)

        go("bulk")
        page.locator("#example_bulk").check()
        select("bulk_palette", "静谧 · Quietude")
        page.locator("#bulk_start").click()
        page.locator("#flow_plan_start").wait_for()
        page.locator('input[name="flow_plan_mode"][value="custom"]').check()
        while page.locator("[data-flow-remove]").count():
            page.locator("[data-flow-remove]").last.click()
            page.wait_for_timeout(150)
        for tool in ("pca", "volcano", "heatmap"):
            select("flow_add_tool", tool)
            page.locator("#flow_add").click()
            page.wait_for_timeout(200)
        page.locator("#flow_plan_start").click()
        page.locator(".modal-backdrop").wait_for(state="hidden")
        page.locator("#pca_top").wait_for()
        run()
        page.locator("#bulk_next").click()
        page.locator(".bulk-gallery-item").first.wait_for()
        page.locator(".bulk-gallery-item").first.click()
        page.locator("#bulk_gallery_continue").click()
        page.locator(".modal-backdrop").wait_for(state="hidden")
        page.locator("#target_text").fill("g001\ng002")
        run()
        checkpoint = ROOT / "results/toolbox/workflow/current.rds"
        assert checkpoint.exists()
        page.reload(wait_until="networkidle")
        go("bulk")
        page.locator("#bulk_resume").click()
        page.locator("#target_text").wait_for()
        assert page.locator("#target_text").input_value() == "g001\ng002"
        page.locator(".status-completed").wait_for()
        page.screenshot(path=str(OUT / "restored-volcano.png"))
        print("PASS shared palette, real synthetic PCA/volcano, favorites and browser-refresh restore", flush=True)
        page.locator("#bulk_next").click()
        page.locator("#bulk_gallery_continue").wait_for()
        page.locator("#bulk_gallery_continue").click()
        page.locator(".modal-backdrop").wait_for(state="hidden")
        select("heatmap_kind", "annotated")
        select("annotation_mode", "auto")
        select("annotation_source", "custom")
        page.locator("#annotation_terms").fill("Synthetic set 1\nDEMO_2")
        page.locator("#heatmap_top").fill("25")
        run()
        page.screenshot(path=str(OUT / "annotated-heatmap.png"))
        print("PASS bulk annotated heatmap with inherited style", flush=True)
        assert not errors, errors
        (OUT / "report.json").write_text(json.dumps({"passed": True, "js_errors": errors}, ensure_ascii=False))
    finally:
        if not (OUT / "report.json").exists():
            page.screenshot(path=str(OUT / "failure.png"))
        browser.close()
        if original is None:
            settings.unlink(missing_ok=True)
        else:
            settings.write_bytes(original)
