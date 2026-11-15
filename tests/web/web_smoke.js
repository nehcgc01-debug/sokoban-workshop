// Web build acceptance in real Chromium (single-threaded Godot export). Keyboard + mouse only.
//
//   1. Export:  godot --headless --path . --export-release "Web QA" build/web/index.html
//   2. Serve:   python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
//   3. Run:     node tests/web/web_smoke.js http://127.0.0.1:8765/index.html out_dir
//
// Needs Node + Playwright with Chromium. Exit code 0 only if every check passes.
// Screenshots of every step are written to out_dir for a human to look at.
const { chromium } = require('playwright');
const fs = require('fs');
const PAGE = process.argv[2] || 'http://127.0.0.1:8765/index.html';
const OUT = process.argv[3] || 'web_smoke_out';
fs.mkdirSync(OUT, { recursive: true });
const ROUTES = {
  1: 'RRR', 2: 'RRRLLLDRRR', 3: 'LLURDRURLU', 4: 'r', 5: 'rDLLURURRRDDLLLULD', 8: 'RUULLRRDDLLLUd',
  6: 'LRRRUULLLDLDUd', 7: 'URDRDRDLLUULUlDRRUL', 9: 'UDLLUURlDDRRUULLDLU', 10: 'DURRDDLrUULLDDRRURD',
  11: 'RURRDLDDLLRRRUULULLDRURDUlDRRUL'
};
const ORDER = [1, 2, 3, 4, 5, 8, 6, 7, 9, 10, 11];
const KEY = { R: 'ArrowRight', L: 'ArrowLeft', U: 'ArrowUp', D: 'ArrowDown' };
const CODE9 = 'KURO1-WWWWWWW/WGWWOWW/WOOOOOW/WOOWBWW/WGOBPOW/WWWWWWW-D795C1';
const OPEN3 = 'KURO1-OOOOOOO/OOBOGOO/OOOPOOO/OOBOGOO/OOOBOGO/OOOOOOO-BDFDAB';
const results = [];
function record(ok, name, detail = '') { results.push({ ok, name, detail }); console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail ? '  [' + detail + ']' : '')); }

async function boot(page) { await page.goto(PAGE); await page.waitForTimeout(7000); await page.mouse.click(5, 5); }
async function press(page, key, wait = 260) { await page.keyboard.press(key); await page.waitForTimeout(wait); }
async function play(page, route) {
  for (const c of route) {
    const k = KEY[c.toUpperCase()];
    if (c === c.toLowerCase()) { await page.keyboard.down('Shift'); await press(page, k); await page.keyboard.up('Shift'); }
    else await press(page, k);
  }
}
async function shot(page, name) { await page.screenshot({ path: `${OUT}/${name}.png` }); }
async function idbProgress(page) {
  return page.evaluate(() => new Promise(res => {
    const req = indexedDB.open('/userfs');
    req.onsuccess = () => {
      const st = req.result.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA');
      const out = {}; const c = st.openCursor();
      c.onsuccess = e => { const cur = e.target.result; if (cur) { if (/progress\.cfg$/.test(cur.key) && cur.value.contents) out.text = new TextDecoder().decode(cur.value.contents); cur.continue(); } else res(out.text || ''); };
    };
    req.onerror = () => res('');
  }));
}

(async () => {
  const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 1152, height: 720 }, deviceScaleFactor: 1 });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new (require('url').URL)(PAGE).origin });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (/SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(m.text()); });

  const t0 = Date.now();
  await boot(page);
  record(true, 'boots', `${Date.now() - t0} ms incl. 7 s settle`);
  await shot(page, 'w00_menu');

  // 1. keyboard 1 -> 11
  await press(page, 'Enter', 900);
  await press(page, 'Enter', 1300);
  for (const id of ORDER) {
    await play(page, ROUTES[id]);
    await page.waitForTimeout(400);
    if (id === 11) break;
    await press(page, 'Enter', 1300);
  }
  await shot(page, 'w01_finale_after_11');

  // 2. reload IMMEDIATELY after the last win: the localStorage mirror must keep the record
  const idbBefore = await idbProgress(page);
  record(true, 'IndexedDB at the moment of reload', idbBefore.includes('11=') ? 'already synced' : 'level 11 NOT yet synced');
  await page.reload(); await page.waitForTimeout(7000); await page.mouse.click(5, 5);
  // V7.12: the menu restores the record from the mirror at once, but the browser writes it back to
  // IndexedDB a little later (slower under load), so poll for up to 8 s instead of one fixed wait.
  let idbAfter = '', waited = 0;
  for (; waited <= 8000; waited += 500) { idbAfter = await idbProgress(page); if (/(^|\n)11=31/.test(idbAfter)) break; await page.waitForTimeout(500); }
  record(/(^|\n)11=31/.test(idbAfter), 'level 11 record survives an immediate reload', `after ${waited} ms: ` + idbAfter.replace(/\n/g, ' '));
  await shot(page, 'w02_menu_after_reload');
  await press(page, 'Enter', 1300);
  await shot(page, 'w03_map_after_reload');
  await press(page, 'Escape', 1000);

  // 3. web menu has no quit button: 开始游戏, 关卡编辑器 only (editor is the 2nd button)
  await press(page, 'ArrowDown', 300);   // 开始游戏 -> 关卡编辑器 (no 离开工坊 on Web)
  await press(page, 'Enter', 1800);
  await shot(page, 'w04_editor_via_keys');

  // 4. paste: Ctrl+V opens the box, browser clipboard pre-fills it, Enter imports
  await page.evaluate(t => navigator.clipboard.writeText(t), CODE9);
  await press(page, 'Control+v', 1500);
  await shot(page, 'w05_paste_box');
  await press(page, 'Enter', 1200);
  await shot(page, 'w06_pasted');

  // 5. check: one map with a quick answer
  await press(page, 'v', 2500);
  await shot(page, 'w07_check_done');

  // 6. copy writes the browser clipboard
  await page.evaluate(() => navigator.clipboard.writeText('EMPTY'));
  await press(page, 'c', 1200);
  const clip = await page.evaluate(() => navigator.clipboard.readText());
  record(clip === CODE9, 'C writes the share code to the browser clipboard', clip);
  await shot(page, 'w08_copied');

  // 7. manual paste into the box (clipboard API denied path): type with Ctrl+V into LineEdit
  await page.evaluate(t => navigator.clipboard.writeText(t), OPEN3);
  await press(page, 'p', 1500);
  await press(page, 'Control+a', 200);
  await press(page, 'Backspace', 200);
  await press(page, 'Control+v', 800);
  await shot(page, 'w09_manual_paste');
  await press(page, 'Enter', 1000);
  await press(page, 'Enter', 1200); // discard-changes dialog
  await shot(page, 'w10_open3_loaded');

  // The board above must now be the open 3-box map (no walls): verify w10 by looking at it.
  // 8. long check stays responsive and can be cancelled
  const fps = () => page.evaluate(() => new Promise(res => { let n = 0; const s = performance.now(); (function f() { n++; if (performance.now() - s < 1000) requestAnimationFrame(f); else res(n); })(); }));
  const idle = await fps();
  await page.keyboard.press('v');
  const busy = await fps();
  record(busy >= Math.min(10, idle * 0.5), 'page keeps rendering during a long check', `${idle} fps idle, ${busy} fps checking`);
  await shot(page, 'w11_checking');
  await press(page, 'v', 800);
  await shot(page, 'w12_cancelled');

  // 9. playtest log: facilitator turns it on, one attempt, export downloads a file
  await press(page, 'Escape', 1500);           // editor -> menu (discard dialog if any)
  await press(page, 'Enter', 1500);
  await shot(page, 'w13_menu_again');
  await page.keyboard.press('Control+Shift+P'); await page.waitForTimeout(800);
  await press(page, 'Enter', 800);              // close the info dialog
  await press(page, 'Enter', 1300);             // 开始游戏
  await press(page, 'Enter', 1300);             // level 1
  await play(page, 'RRR');
  await page.waitForTimeout(400);
  await press(page, 'Escape', 1500);            // back to the menu: attempt is written
  const dl = page.waitForEvent('download', { timeout: 8000 }).catch(() => null);
  await page.keyboard.press('Control+Shift+E');
  const download = await dl;
  let lines = [];
  if (download) { const path = `${OUT}/${download.suggestedFilename()}`; await download.saveAs(path); lines = fs.readFileSync(path, 'utf8').trim().split('\n').map(l => JSON.parse(l)); }
  record(download && lines.length === 1 && lines[0].level === 1 && lines[0].solved === true, 'playtest export downloads a JSONL file with the attempt', download ? download.suggestedFilename() + ' · ' + JSON.stringify(lines[0] || {}).slice(0, 120) : 'no download');
  await press(page, 'Enter', 600);
  await shot(page, 'w14_playtest_exported');

  // 10. volume setting survives a reload (slider is not keyboard-reachable in this test: use the mouse)
  await page.mouse.click(312 + 140 * 0.25, 626); await page.waitForTimeout(600);
  await page.reload(); await page.waitForTimeout(7000);
  const settings = await page.evaluate(() => localStorage.getItem('kuro_sukobann_lab6:user://settings.cfg') || '');
  record(/volume=0\.[23]/.test(settings), 'volume setting is saved on Web', settings.replace(/\n/g, ' '));
  await shot(page, 'w15_menu_after_volume_reload');

  record(errors.length === 0, 'no page or script errors', errors.slice(0, 5).join(' || '));
  fs.writeFileSync(`${OUT}/web_results.json`, JSON.stringify(results, null, 1));
  await browser.close();
  process.exit(results.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
