"""Real local Shiny UI, synthetic inputs only; no software-package updates."""
import argparse, csv, hashlib, io, json, time, zipfile
from pathlib import Path
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser()
parser.add_argument('--url',default='http://127.0.0.1:7898')
parser.add_argument('--output',default='app/tests/_browser/workflow-v2')
args=parser.parse_args();out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
settings=Path('app/results/toolbox/settings.json')
original=json.loads(settings.read_text(encoding='utf-8-sig')) if settings.exists() else {}
with sync_playwright() as p:
 b=p.chromium.launch(headless=True)
 page=b.new_page(viewport={'width':1536,'height':1000},accept_downloads=True)
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def idle(): page.wait_for_timeout(450)
 def select(selector,value): page.locator(selector).evaluate('(e,v)=>e.selectize.setValue(v)',value)
 def close():
  page.locator('.modal-footer .btn').click();page.locator('.modal-backdrop').wait_for(state='hidden')
 def run():
  assert not page.locator('#cancel_job').count()
  old=page.locator('.status-card').get_attribute('data-job-id')
  page.locator('#run_tool').click()
  try: page.wait_for_function('(old)=>document.querySelector(".status-card")?.dataset.jobId && document.querySelector(".status-card").dataset.jobId!==old',arg=old,timeout=20000)
  except Exception:
   print(page.locator('.shiny-notification').all_text_contents(),flush=True);raise
  deadline=time.time()+160
  while time.time()<deadline:
   if page.locator('.status-failed').count():raise AssertionError(page.locator('.status-failed').inner_text())
   if page.locator('.status-completed').count():idle();return
   page.wait_for_timeout(300)
  raise AssertionError('worker timeout')
 def next_step(star=True):
  page.locator('#bulk_next').click();page.locator('.bulk-gallery-item').first.wait_for()
  idle()
  assert not page.locator('#gallery_step').count()
  assert not page.locator('#gallery_favorites').count()
  if star:
   image=page.locator('.bulk-gallery-item').first
   if image.get_attribute('aria-pressed')!='true': image.click()
  page.screenshot(path=str(out/'current-step-gallery.png'))
  page.locator('#bulk_gallery_continue').click();page.locator('.modal-backdrop').wait_for(state='hidden');idle()
 try:
  page.goto(args.url,wait_until='networkidle');page.locator('.tool-card').first.wait_for()
  assert page.locator('#show_environment').inner_text()=='设置'
  page.locator('#show_environment').click();page.locator('.modal-dialog').wait_for()
  page.locator('.modal-dialog a[data-value="运行环境"]').click();idle()
  assert page.locator('select[id^=runtime_method_]').count()==3
  assert not page.locator('#detect_rscript').count()
  assert page.locator('.runtime-links a').count()==4
  page.locator('.modal-dialog a[data-value="R 软件包"]').click()
  page.locator('#dependency_table table').first.wait_for()
  assert page.locator('#dependency_table table').first.locator('tbody tr').count()>=30
  page.locator('.modal-dialog a[data-value="界面风格"]').click()
  for theme in ['classic','night']:
   page.locator(f'input[name=settings_theme][value={theme}]').check();page.locator('#settings_theme_save').click()
   page.wait_for_function('(x)=>document.documentElement.dataset.theme===x',arg=theme)
   close();idle();page.screenshot(path=str(out/f'{theme}-home.png'))
   if theme=='classic':
    page.locator('#show_environment').click();page.locator('.modal-dialog a[data-value="界面风格"]').click()
  page.locator('.hero-start').click();page.locator('#example_bulk').check();idle()
  page.locator('#bulk_palette').evaluate('(e)=>e.selectize.setValue(Object.keys(e.selectize.options).find(x=>x))')
  page.locator('#bulk_start').click();page.locator('#flow_plan_start').wait_for()
  page.locator('input[name=flow_plan_mode][value=default]').check();idle()
  # Begin with the default plan, then create a four-step custom plan using real controls.
  for count in range(10,2,-1):
   page.locator('[data-flow-remove]').nth(2).click()
   page.wait_for_function('(n)=>document.querySelectorAll("[data-flow-remove]").length===n',arg=count-1)
  for tool in ['volcano','figure_layout']:
   select('#flow_add_tool',tool);page.locator('#flow_add').click();idle()
  assert page.locator('[data-flow-remove]').count()==4
  # Move volcano before DEG, then back, with the explicit drag grip.
  page.locator('[data-flow-drag="3"]').drag_to(page.locator('[data-flow-index="2"]'),target_position={'x':50,'y':2});idle()
  assert '火山' in page.locator('[data-flow-index="2"]').inner_text()
  page.locator('[data-flow-drag="2"]').drag_to(page.locator('[data-flow-index="3"]'),target_position={'x':50,'y':45});idle()
  assert '差异表达' in page.locator('[data-flow-index="2"]').inner_text()
  print('PASS default list, runtime dropdown, custom plan add/remove/drag',flush=True)
  page.locator('#flow_save_preset').check();page.locator('#flow_plan_start').click()
  page.locator('#pca_top').wait_for();assert not page.locator('#bulk_skip_dialog').count()
  page.locator('#pca_top').fill('80');run();next_step()
  run();idle()
  page.locator('[data-bulk-jump=pca]').click();page.locator('#pca_top').wait_for();idle()
  assert page.locator('#pca_top').input_value()=='80'
  assert page.locator('.status-completed').count()==1
  page.locator('#pca_top').fill('100');run();next_step()
  assert not page.locator('.status-completed').count()  # Previous DEG is invalidated.
  run();next_step();run();next_step(False)
  page.locator('#panel_auto_favorites').check()
  page.wait_for_function("document.getElementById('panel_count').value==='2'")
  page.locator('#panel_thumb_panel_01 img').wait_for()
  page.locator('#panel_thumb_panel_02 img').wait_for()
  first=page.locator('#path_panel_01').input_value();second=page.locator('#path_panel_02').input_value()
  assert first!=second and first and second
  page.locator('[data-panel-move=panel_02][data-position=top]').click()
  page.wait_for_function('(x)=>document.getElementById("path_panel_01").value===x',arg=second)
  page.locator('[data-panel-drag=panel_02]').drag_to(page.locator('[data-panel-field=panel_01]'),target_position={'x':80,'y':2})
  page.wait_for_function('(x)=>document.getElementById("path_panel_01").value===x',arg=first)
  assert not page.locator('#panel_auto_favorites').is_checked()
  print('PASS backward revisit, invalidation, auto favorites, thumbnail, move and grip reorder',flush=True)
  page.locator('[data-bulk-pick-panel]').first.click();page.locator('#gallery_step').wait_for(state='attached')
  for step in ['pca','deg','volcano']:
   select('#gallery_step',step);idle();assert page.locator('.bulk-gallery-item').count()>0,step
  select('#gallery_step','all');idle()
  page.screenshot(path=str(out/'final-gallery.png'));close()
  page.screenshot(path=str(out/'panel-order.png'));run()
  page.wait_for_function("document.getElementById('download_bulk_all').href.includes('/download/')")
  with page.expect_download(timeout=120000) as downloaded:page.locator('#download_bulk_all').click()
  downloaded.value.save_as(str(out/'custom-flow.zip'))
  with zipfile.ZipFile(out/'custom-flow.zip') as z:
   assert all(any(name.startswith(f'{i:02d}_') for name in z.namelist()) for i in range(1,5))
   assert any(name.endswith('/inputs/counts.csv') or '/inputs/' in name for name in z.namelist())
  with page.expect_popup() as opened:page.locator('a[href$="figure-layout.html"]').click()
  editor=opened.value;editor.on('pageerror',lambda e:errors.append(str(e)))
  editor.locator('canvas[data-ready=true]').wait_for()
  def exported(name):
   with editor.expect_download() as d:editor.locator('#export').click()
   file=out/name;d.value.save_as(str(file));return hashlib.sha256(file.read_bytes()).hexdigest()
  before=exported('before.png')
  config=editor.evaluate("JSON.parse(document.getElementById('figure-config').textContent)")
  panel=config['panels'][0];box=editor.locator('#figure').bounding_box()
  editor.mouse.click(box['x']+(panel['x']+panel['width']/2)*box['width'],box['y']+(panel['y']+panel['height']/2)*box['height'])
  editor.locator('#figure').press('Shift+ArrowRight')
  moved=exported('moved.png');assert moved!=before
  editor.keyboard.press('Control+z');assert exported('undo.png')==before
  editor.keyboard.press('Control+y');assert exported('redo.png')==moved
  editor.close()
  page.locator('#show_home').click();idle();page.reload(wait_until='networkidle');page.locator('.hero-start').click()
  page.locator('#example_bulk').check();idle();select('#bulk_palette',next(x for x in page.locator('#bulk_palette').evaluate('(e)=>Object.keys(e.selectize.options)') if x));page.locator('#bulk_start').click();page.locator('#flow_plan_start').wait_for();idle()
  assert page.locator('input[name=flow_plan_mode][value=custom]').is_checked()
  assert page.locator('[data-flow-remove]').count()==4
  assert not errors,errors
  (out/'report.json').write_text(json.dumps({'passed':True,'js_errors':errors,'workflow':'custom persisted; jump/rerun invalidation; gallery filters; auto favorites; drag/order; Ctrl+Z/Y exports verified'},ensure_ascii=False,indent=2),encoding='utf-8')
  print('PASS workflow v2 custom planning/persistence, rerun, current-only review, filters, favorites, order, thumbnail, ZIP and undo/redo',flush=True)
 except Exception:
  print('NOTIFICATIONS',page.locator('.shiny-notification').all_text_contents(),flush=True)
  page.screenshot(path=str(out/'failure.png'));raise
 finally:
  b.close()
  # Restore only the test-owned preset field; preserve other settings.
  cfg=json.loads(settings.read_text(encoding='utf-8-sig'))
  if 'workflow_preset' in original:cfg['workflow_preset']=original['workflow_preset']
  else:cfg.pop('workflow_preset',None)
  settings.write_text(json.dumps(cfg,ensure_ascii=False,indent=2),encoding='utf-8')
