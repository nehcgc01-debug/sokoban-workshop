// Lab: tool-crate map on the Web build. Keyboard only. Usage like web_smoke.js.
const { chromium } = require('playwright');
const fs = require('fs');
const PAGE = process.argv[2] || 'http://127.0.0.1:8765/index.html';
const OUT = process.argv[3] || 'web_lab_out';
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
  await key('Enter', 1200);                         // 开始游戏 -> map
  for (let i = 0; i < 3; i++) await key('ArrowDown');  // intro -> pull -> challenge -> lab row
  await page.screenshot({ path: `${OUT}/l00_map_lab_row.png` });
  await key('Enter', 1500);                         // T1
  await page.screenshot({ path: `${OUT}/l01_T1.png` });
  for (const k of ['ArrowRight', 'ArrowRight']) await key(k);
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}/l02_T1_opened.png` });
  for (const k of ['ArrowRight', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowLeft']) await key(k);
  await shift('ArrowRight');
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${OUT}/l03_T1_win.png` });
  const prog = await page.evaluate(() => localStorage.getItem('kuro_sukobann_lab6:user://progress.cfg') || '');
  rec(/(^|\n)12=8/.test(prog), 'T1 solved in 8 moves on the Web and recorded', prog.replace(/\n/g, ' '));
  // editor: paste a KUROT code, check it, copy it back
  await key('Escape', 1500);
  await key('ArrowDown'); await key('Enter', 1800);
  // the KUROT share code of T1, built the same way as level_store.gd (checksum = first 6 hex of MD5)
  const lv = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../levels/demo_12.json'), 'utf8'));
  const g = [...Array(6)].map(() => [...Array(7)].map(() => 'O'));
  for (const [x, y] of lv.walls) g[y][x] = 'W';
  for (const [x, y] of lv.goals) g[y][x] = 'G';
  for (const [x, y] of lv.boxes) g[y][x] = g[y][x] === 'G' ? 'X' : 'B';
  g[lv.tool[1]][lv.tool[0]] = 'T'; g[lv.bench[1]][lv.bench[0]] = 'K';
  g[lv.player[1]][lv.player[0]] = 'P';
  const body = `KUROT${lv.pull_charges}-` + g.map(r => r.join('')).join('/');
  const code = body + '-' + require('crypto').createHash('md5').update(body).digest('hex').slice(0, 6).toUpperCase();
  await page.evaluate(t => navigator.clipboard.writeText(t), code);
  await key('Control+v', 1500);
  await page.screenshot({ path: `${OUT}/l04_paste_box.png` });
  await key('Enter', 1200);
  await key('v', 2500);
  await page.screenshot({ path: `${OUT}/l05_editor_checked.png` });
  await page.evaluate(() => navigator.clipboard.writeText('EMPTY'));
  await key('c', 1200);
  const clip = await page.evaluate(() => navigator.clipboard.readText());
  rec(clip === code, 'a KUROT code pastes into the editor and copies back unchanged', clip);
  rec(errors.length === 0, 'no page or script errors', errors.slice(0, 3).join(' || '));
  fs.writeFileSync(`${OUT}/lab_results.json`, JSON.stringify(results, null, 1));
  await browser.close(); process.exit(results.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
