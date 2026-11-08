from playwright.sync_api import sync_playwright
from pathlib import Path
import time,json,zipfile,csv,io,argparse
parser=argparse.ArgumentParser();parser.add_argument('--url',default='http://127.0.0.1:7898');parser.add_argument('--output',default='app/tests/_browser/settings-bulk');args=parser.parse_args()
out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 b=p.chromium.launch(headless=True);page=b.new_page(viewport={'width':1536,'height':1000});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(args.url,wait_until='networkidle');page.locator('.tool-card').first.wait_for()
 page.locator('#show_environment').click();page.locator('.modal-dialog').wait_for()
 assert not page.locator('#project_path').count();assert not page.locator('#project_child').count();assert page.locator('#project_browse').count()
 page.locator('.modal-dialog a[data-value="界面风格"]').click();assert page.locator('input[name=settings_theme]').count()==2
 page.locator('input[value=classic][name=settings_theme]').check();page.locator('#settings_theme_save').click();page.wait_for_function("document.documentElement.dataset.theme==='classic'")
 page.locator('.modal-footer .btn').click();page.locator('.modal-backdrop').wait_for(state='hidden');page.screenshot(path=str(out/'light-home.png'))
 page.locator('#show_environment').click();page.locator('.modal-dialog a[data-value="运行环境"]').click();page.locator('#settings_rscript').fill(r'D:\R\R-4.5.1\bin\x64\Rscript.exe');page.locator('#settings_probe').click();page.wait_for_function("document.getElementById('settings_versions').textContent.includes('4.5.1')",timeout=45000)
 page.locator('.modal-dialog a[data-value="R 软件包"]').click();assert not page.locator('#settings_packages').count();page.locator('#settings_check_packages').wait_for()
 page.locator('.modal-dialog a[data-value="界面风格"]').click();page.locator('input[value=night][name=settings_theme]').check();page.locator('#settings_theme_save').click();page.wait_for_function("document.documentElement.dataset.theme==='night'")
 page.locator('.modal-footer .btn').click();page.locator('.modal-backdrop').wait_for(state='hidden')
 page.locator('.hero-start').click();page.locator('#bulk_start').wait_for();page.locator('#example_bulk').check();page.wait_for_timeout(1200)
 print('bulk inputs',page.locator('#bulk_start').inner_text(),flush=True)
 page.locator('#bulk_start').click();page.locator('#flow_plan_start').wait_for();page.locator('input[name=flow_plan_mode][value=default]').check();page.locator('#flow_plan_start').click();page.locator('#pca_top').wait_for(timeout=15000);assert not page.locator('#cancel_job').count()
 def run():
  previous=page.locator('.status-card').get_attribute('data-job-id')
  page.locator('#run_tool').click()
  page.wait_for_function('(old)=>document.querySelector(".status-card")?.dataset.jobId && document.querySelector(".status-card").dataset.jobId!==old',arg=previous,timeout=30000)
  end=time.time()+140
  while time.time()<end:
   if page.locator('.status-failed').count():raise AssertionError(page.locator('.status-failed').inner_text())
   if page.locator('.status-completed').count():return
   page.wait_for_timeout(400)
  raise AssertionError('timeout')
 run();page.locator('#bulk_next').click();page.locator('.bulk-gallery-item').first.wait_for();page.locator('.bulk-gallery-item').first.click();page.locator('.gallery-star.favorite').first.wait_for();page.locator('#bulk_gallery_continue').click();page.locator('#padj').wait_for();assert not page.locator('#cancel_job').count()
 run();page.locator('#bulk_next').click();page.locator('.bulk-gallery-item').first.wait_for();page.screenshot(path=str(out/'bulk-gallery.png'))
 page.wait_for_function("document.querySelector('#bulk_gallery_images').textContent.includes('deg_proportions')")
 print('DEG gallery',page.locator('.bulk-gallery-item').all_text_contents(),flush=True)
 page.locator('#bulk_gallery_continue').click();page.locator('.modal-backdrop').wait_for(state='hidden')
 for step in ['volcano','heatmap','go','kegg','gsea','gsva','network']:
  page.wait_for_timeout(500)
  assert not page.locator('#cancel_job').count(),step
  print('RUN',step,flush=True)
  run()
  if step=='network':
   # Real Cytoscape editor -> image -> Shiny cache; no fabricated task result.
   page.locator('a[data-value="交互网络"]').click()
   frame=page.frame_locator('.network-frame')
   with page.expect_popup() as opened: frame.locator('.edit-link').click()
   advanced=opened.value
   advanced.wait_for_load_state()
   advanced.locator('#cache-png').click()
   assert advanced.evaluate('window.opener === null')
   page.wait_for_function("Array.from(document.querySelectorAll('.shiny-notification')).some(e=>e.textContent.includes('精细编辑图片已加入'))")
  page.locator('#bulk_next').click();page.locator('.bulk-gallery-item').first.wait_for()
  page.locator('#bulk_gallery_continue').click();page.locator('.modal-backdrop').wait_for(state='hidden')
 page.locator('[data-bulk-pick-panel]').first.wait_for()
 page.locator('#panel_count').fill('2');page.locator('#panel_count').press('Tab');page.wait_for_timeout(600)
 for i in range(2):
  page.locator('[data-bulk-pick-panel]').nth(i).click();page.locator('.bulk-gallery-item').first.wait_for()
  page.locator('.bulk-gallery-item').nth(i).click();page.locator('.modal-backdrop').wait_for(state='hidden')
 run()
 page.wait_for_function("document.getElementById('download_bulk_all').href.includes('/download/')")
 with page.expect_download(timeout=120000) as d: page.locator('#download_bulk_all').click()
 archive=out/'bulk-all.zip';d.value.save_as(str(archive))
 with zipfile.ZipFile(archive) as z:
  assert all(any(n.startswith(f'{i:02d}_') for n in z.namelist()) for i in range(1,11)),z.namelist()
  summary_file=next(n for n in z.namelist() if n.endswith('deg_summary.csv'))
  summary=next(csv.DictReader(io.StringIO(z.read(summary_file).decode('utf-8-sig'))))
  assert int(summary['up'])+int(summary['down'])+int(summary['not_significant'])==int(summary['tested'])
  assert int(summary['detected_before_filter'])>=int(summary['tested'])
  assert any('deg_proportions.png' in n for n in z.namelist())
  assert any('09_network/edited/' in n for n in z.namelist())
 page.locator('#show_home').click();page.wait_for_timeout(500)
 root=Path.cwd()/'app/results/toolbox/bulk-cache'
 assert not list(root.glob('**/*.png'))
 page.locator('#show_environment').click();page.locator('.modal-dialog a[data-value="运行环境"]').click()
 assert page.locator('select[id^=runtime_method_]').count()==3
 page.locator('.modal-dialog a[data-value="R 软件包"]').click()
 page.locator('#settings_check_packages').click()
 page.wait_for_function("document.getElementById('package_update_log').textContent.includes('检测完成')",timeout=180000)
 assert page.locator('#dependency_table table').first.locator('th').all_text_contents()==['包名','当前版本','最新版本','功能简介','包对应网址','操作']
 assert page.locator('[data-update-package]:disabled').count()>0
 page.locator('.modal-footer .btn').click();page.locator('.modal-backdrop').wait_for(state='hidden')
 print('PASS full 10-step synthetic workflow, manual run per step, real PPI editor cache, cached layout, ZIP and exit cleanup; JS errors',errors,flush=True)
 assert not errors
 b.close()
