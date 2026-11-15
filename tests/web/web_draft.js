// V7.12 Web acceptance for editor drafts (real Chromium, keyboard + mouse only).
//   Same setup as web_smoke.js:  node tests/web/web_draft.js http://127.0.0.1:8765/index.html out_dir
// 1. a draft survives closing the tab right after the last edit (no unload prompt exists on the Web)
// 2. Esc -> Enter keeps the draft and returns to the menu; the menu says a draft is waiting
// 3. Esc -> Tab -> Enter discards it; it does not come back after a reload
const { chromium } = require('playwright');
const fs = require('fs');
const PAGE = process.argv[2] || 'http://127.0.0.1:8765/index.html';
const OUT = process.argv[3] || 'web_draft_out';
fs.mkdirSync(OUT, { recursive: true });
const results = [];
const rec = (ok, n, d = '') => { results.push({ ok, name: n, detail: d }); console.log((ok ? 'PASS ' : 'FAIL ') + n + (d ? '  [' + d + ']' : '')); };
const cell = (c, r) => [48 + 68 * c + 34, 142 + 68 * r + 34];
(async () => {
  const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 1152, height: 720 }, deviceScaleFactor: 1 });
  let page = await ctx.newPage();
  const errors = [];
  const watch = p => { p.on('pageerror', e => errors.push(e.message)); p.on('console', m => { if (/SCRIPT ERROR|Parse Error|ERROR:/.test(m.text())) errors.push(m.text()); }); };
  watch(page);
  const key = async (k, w = 300) => { await page.keyboard.press(k); await page.waitForTimeout(w); };
  const boot = async () => { await page.goto(PAGE); await page.waitForTimeout(7000); await page.mouse.click(5, 5); await page.waitForTimeout(300); };
  const draft = () => page.evaluate(() => localStorage.getItem('kuro_sukobann_lab6:user://editor_recovery.json'));
  const paint = async cells => { for (const [c, r] of cells) { const [x, y] = cell(c, r); await page.mouse.click(x, y); await page.waitForTimeout(150); } };
  const openEditor = async () => { await key('ArrowDown'); await key('Enter', 1800); };

  await boot();
  await openEditor();
  await paint([[1, 1], [2, 1], [3, 1]]);
  rec((await draft() || '').includes('[3,1]'), 'draft is stored synchronously after the last edit', await draft());
  await page.close({ runBeforeUnload: false });            // tab closed at once
  page = await ctx.newPage(); watch(page);
  await boot();
  await page.screenshot({ path: `${OUT}/d01_menu_after_tab_close.png` });
  await openEditor();
  await page.screenshot({ path: `${OUT}/d02_editor_restored.png` });
  rec((await draft() || '').includes('[3,1]'), 'draft survives closing the tab', await draft());

  await paint([[4, 1]]);
  await key('Escape', 900);
  await page.screenshot({ path: `${OUT}/d03_leave_dialog.png` });
  await key('Enter', 1800);                                // default button: keep and return
  await page.screenshot({ path: `${OUT}/d04_menu_draft_waiting.png` });
  rec((await draft() || '').includes('[4,1]'), 'Esc then Enter keeps the draft', await draft());

  await openEditor();
  await key('Escape', 900);
  await key('Tab', 300);
  await page.screenshot({ path: `${OUT}/d05_discard_focused.png` });
  await key('Enter', 1800);
  rec(await draft() === '{}', 'Esc, Tab, Enter discards it (empty marker left so an old copy cannot return)', await draft());
  await page.reload(); await page.waitForTimeout(7000); await page.mouse.click(5, 5);
  await page.screenshot({ path: `${OUT}/d06_menu_after_discard.png` });
  await openEditor();
  await page.screenshot({ path: `${OUT}/d07_editor_empty.png` });
  rec(await draft() === '{}', 'discarded draft stays gone after a reload', await draft());
  rec(errors.length === 0, 'no page or script errors', errors.slice(0, 3).join(' || '));
  fs.writeFileSync(`${OUT}/draft_results.json`, JSON.stringify(results, null, 1));
  await browser.close();
  process.exit(results.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
