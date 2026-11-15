// Lab 2 on the Web build (single-threaded): the warm loop survives a reload, and a heavy custom map
// does not freeze the page when a test play starts. Keyboard only. Usage like web_smoke.js.
// Optional 4th argument: localStorage prefix (default kuro_sukobann_lab6:), so the same script can
// measure the previous build for comparison.
const { chromium } = require('playwright');
const fs = require('fs');
const PAGE = process.argv[2] || 'http://127.0.0.1:8765/index.html';
const OUT = process.argv[3] || 'web_lab2_out';
const PREFIX = process.argv[4] || 'kuro_sukobann_lab6:';
const HEAVY = 'KUROT2-OOOWOOO/OOWGWOO/OOOWOOO/OBOBOBO/OGOOOGO/POOOOOO-1DA7F9';
fs.mkdirSync(OUT, { recursive: true });
const results = [];
const rec = (ok, n, d = '') => { results.push({ ok, name: n, detail: d }); console.log((ok ? 'PASS ' : 'FAIL ') + n + (d ? '  [' + d + ']' : '')); };
(async () => {
  const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 1152, height: 720 }, deviceScaleFactor: 1 });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new (require('url').URL)(PAGE).origin });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (/SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(m.text()); });
  const key = async (k, w = 300) => { await page.keyboard.press(k); await page.waitForTimeout(w); };
  const shift = async k => { await page.keyboard.down('Shift'); await key(k); await page.keyboard.up('Shift'); };
  await page.goto(PAGE); await page.waitForTimeout(7000); await page.mouse.click(5, 5);
  await page.screenshot({ path: `${OUT}/w00_menu_empty_corner.png` });
  await key('Enter', 1200);
  for (let i = 0; i < 3; i++) await key('ArrowDown');
  await key('Enter', 1500);                         // T1
  await page.screenshot({ path: `${OUT}/w01_T1_lamp_dark.png` });
  for (const k of ['ArrowRight', 'ArrowRight', 'ArrowRight', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowLeft']) await key(k);
  await shift('ArrowRight');
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${OUT}/w02_T1_lamp_lit.png` });
  const prog = await page.evaluate(p => localStorage.getItem(p + 'user://progress.cfg') || '', PREFIX);
  rec(/12=8/.test(prog), 'T1 solved on the Web build; the record that lights the rest corner is stored', prog.replace(/\n/g, ' '));
  await key('Escape', 2500);
  await page.screenshot({ path: `${OUT}/w03_menu_corner_1.png` });
  await page.reload(); await page.waitForTimeout(7000); await page.mouse.click(5, 5);
  await page.screenshot({ path: `${OUT}/w04_menu_after_reload.png` });
  const prog2 = await page.evaluate(p => localStorage.getItem(p + 'user://progress.cfg') || '', PREFIX);
  rec(/12=8/.test(prog2), 'after a page reload the record (and with it the lamp in the corner) is still there');
  // heavy custom map: paste in the editor, start a test play, watch the frame gaps
  await key('ArrowDown'); await key('Enter', 1800);
  await key('p', 800);
  await page.keyboard.press('Control+a'); await page.keyboard.type(HEAVY, { delay: 5 }); await key('Enter', 1000);
  await page.evaluate(() => { window.__gaps = []; let last = performance.now(); const tick = () => { const now = performance.now(); window.__gaps.push(now - last); last = now; window.__raf = requestAnimationFrame(tick); }; tick(); });
  await page.waitForTimeout(1500);
  const idle = await page.evaluate(() => { const g = window.__gaps.slice(5); window.__gaps = []; return Math.max(...g); });
  const t0 = Date.now();
  await page.keyboard.press('t');
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${OUT}/w05_heavy_400ms.png` });
  await page.keyboard.press('ArrowRight'); await page.waitForTimeout(200);
  await page.keyboard.press('ArrowRight'); await page.waitForTimeout(200);
  await page.screenshot({ path: `${OUT}/w06_heavy_moved.png` });
  await page.waitForTimeout(6000);
  const worst = await page.evaluate(() => { cancelAnimationFrame(window.__raf); return Math.max(...window.__gaps); });
  await page.screenshot({ path: `${OUT}/w07_heavy_settled.png` });
  rec(worst < 700, 'heavy map test play: the longest gap between two browser frames stays short', `worst ${Math.round(worst)} ms after pressing T; ${Math.round(idle)} ms while idle in the editor`);
  rec(errors.length === 0, 'no script errors', errors.join(' | ').slice(0, 300));
  fs.writeFileSync(`${OUT}/lab2_results.json`, JSON.stringify({ results, worst_gap_ms: worst, idle_gap_ms: idle }, null, 2));
  await browser.close();
  const bad = results.filter(r => !r.ok).length;
  console.log(bad === 0 ? `WEB LAB2: ${results.length}/${results.length}` : `WEB LAB2 FAILED: ${bad}`);
  process.exit(bad === 0 ? 0 : 1);
})();
