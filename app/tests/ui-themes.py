import argparse,json,time,zipfile
from pathlib import Path
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser();parser.add_argument('--url',default='http://127.0.0.1:7898');parser.add_argument('--output',required=True);args=parser.parse_args()
out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True)
 page=browser.new_page(viewport={'width':1536,'height':1000},device_scale_factor=1,accept_downloads=True)
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def idle():page.wait_for_timeout(450)
 def home():page.locator('#show_home').click();idle()
 def settings(tab):
  page.locator('#show_environment').click();page.locator('.modal-dialog').wait_for();idle()
  page.locator('.modal-dialog a[data-value="'+tab+'"]').click();idle()
 def close():page.locator('.modal-footer .btn').click();idle()
 def set_theme(theme):
  page.locator('input[name="settings_theme"][value="'+theme+'"]').check();page.locator('#settings_theme_save').click()
  page.wait_for_function('(v)=>document.documentElement.dataset.theme===v',arg=theme)
 def wait_terminal():
  deadline=time.time()+120
  while time.time()<deadline:
   if page.locator('.status-failed').count():raise AssertionError(page.locator('.status-failed').inner_text())
   if page.locator('.status-completed,.status-cancelled').count():return
   page.wait_for_timeout(250)
  raise AssertionError('worker timeout')
 page.goto(args.url,wait_until='networkidle');page.locator('.tool-card').first.wait_for()
 assert not page.locator('.modal-dialog').is_visible()
 assert page.locator('.sidebar #example_choice').count()==0
 settings('界面风格');set_theme('night');close()
 assert page.locator('html').get_attribute('data-theme')=='night'
 assert page.locator('html').get_attribute('lang')=='zh-CN'
 assert page.locator('head title').count()==1
 # Tooltips must retain help supplied by another component.
 badge=page.locator('.local-badge')
 badge.evaluate("e=>e.setAttribute('aria-describedby','existing-help')")
 badge.focus()
 page.wait_for_function("document.querySelector('.local-badge').getAttribute('aria-describedby').includes('context-tooltip')")
 badge.press('Escape')
 assert badge.get_attribute('aria-describedby')=='existing-help'
 badge.evaluate("e=>e.removeAttribute('aria-describedby')")

 for theme in ['classic','night']:
  settings('界面风格');set_theme(theme);close();page.reload(wait_until='networkidle');page.locator('.tool-card').first.wait_for()
  assert page.locator('html').get_attribute('data-theme')==theme
  page.screenshot(path=str(out/(theme+'-home.png')))
 settings('示例数据');page.locator('#example_catalog .selectize-input').click();page.locator('#example_catalog .selectize-dropdown .option').nth(1).click();idle()
 assert 'GSE148036' in page.locator('.example-document').inner_text()
 close();page.reload(wait_until='networkidle');page.locator('.tool-card').first.wait_for()
 settings('示例数据');assert page.locator('#example_choice').input_value().startswith('01_')
 page.locator('#example_catalog .selectize-input').click();page.locator('#example_catalog .selectize-dropdown .option[data-value="synthetic"]').click();idle();close()
 ids=page.locator('.tool-nav').evaluate_all('(es)=>es.map(e=>e.dataset.tool)')
 for tool in ids:
  page.locator('.tool-nav[data-tool="'+tool+'"]').click();idle()
  assert page.locator('h1').first.is_visible(),tool
  actual_errors=page.locator('.shiny-output-error:not(.shiny-output-error-validation)').all_text_contents()
  assert not actual_errors,(tool,actual_errors)
 print('PASS all',len(ids),'navigation entries')
 home();page.locator('.hero-start').click();idle();assert page.locator('#bulk_start').count()==1;home()
 page.locator('#tool_search').fill('KEGG');idle();assert page.locator('.tool-card').count()==1;page.locator('#tool_search').fill('');idle()
 page.locator('.tool-nav[data-tool="kegg"]').click();idle()
 page.locator('#example_kegg').check()
 page.wait_for_function('!document.documentElement.classList.contains("shiny-busy")')
 page.wait_for_timeout(1000)
 page.locator('#validate_inputs').click()
 try: page.locator('.modal-dialog').wait_for()
 except Exception:
  print('INPUT CHECK NOTIFICATIONS',page.locator('.shiny-notification').all_text_contents(),flush=True);raise
 close()
 page.locator('#run_tool').click();page.locator('#cancel_job').wait_for(timeout=30000)
 assert page.locator('#run_tool').is_disabled()
 # Simulate a control arriving later in Shiny's dynamic workspace while the worker is busy.
 page.evaluate("()=>{const b=document.createElement('button');b.id='redraw';b.textContent='仅重新绘图';document.querySelector('.main-shell').append(b)}")
 page.wait_for_function("document.getElementById('redraw').disabled")
 assert page.locator('#redraw').get_attribute('aria-disabled')=='true'
 page.locator('#redraw').evaluate('(e)=>e.remove()')

 page.evaluate('window.scrollTo(0,0)');page.screenshot(path=str(out/'kegg-running.png'))
 page.locator('#cancel_job').click();page.locator('.status-cancelled').wait_for(timeout=30000)
 assert page.locator('#run_tool').is_enabled()
 page.locator('#run_tool').click();page.locator('#cancel_job').wait_for(timeout=30000);wait_terminal();assert page.locator('.status-completed').count()
 assert page.locator('#run_tool').is_enabled()
 page.locator('a[data-value="图形预览"]').click();idle();page.evaluate('window.scrollTo(0,0)');idle()
 page.screenshot(path=str(out/'kegg-complete.png'))
 with page.expect_download() as d:page.locator('#download_zip').click()
 dl=d.value;archive=out/dl.suggested_filename;dl.save_as(str(archive))
 with zipfile.ZipFile(archive) as z:
  assert any(n.endswith('kegg_enrichment.png') for n in z.namelist())
  assert any(n.endswith('kegg_enrichment_plot_data.csv') for n in z.namelist())
 page.locator('#redraw').click();page.locator('#cancel_job').wait_for(timeout=30000);wait_terminal();assert page.locator('.status-completed').count()
 print('PASS input validation, submit, real progress, repeat-submit lock, cancel, completion, ZIP and redraw')
 home();page.set_viewport_size({'width':390,'height':844});idle()
 assert page.evaluate('document.documentElement.scrollWidth<=innerWidth+2')
 page.screenshot(path=str(out/'mobile-home.png'))
 assert not errors,errors
 (out/'report.json').write_text(json.dumps({'navigation':len(ids),'themes':['night','classic'],'worker':'KEGG synthetic GMT','passed':True,'js_errors':errors},ensure_ascii=False,indent=2),encoding='utf-8')
 browser.close()
print('PASS browser checks')
