/* 메이커 편집 창의 '입력 칸 길잡이'(js/form-keys.js — ↑↓ · Enter · Alt+↑↓ · Ctrl+D · Ctrl+Shift+Delete)를 실제 브라우저에서 확인합니다.
   node scripts/form-keys-check.mjs <검사할 폴더> <결과 폴더>
   dlc-maker.html을 1920×1080 · 1배로 띄워 작업본에 가상 나라를 만들고 편집 창을 열어 키를 누릅니다. 자료는 따로 띄운 브라우저의 메모리에만 둡니다.
   크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT(그 package.json)로 고릅니다 — 다른 브라우저 검사와 같게. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/입력-칸-길잡이');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details !== undefined ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details === undefined ? true : details }); };

/* ① 읽는 곳 · 포장 목록: 메이커만 읽고(core 뒤 · viewer 앞), 서비스 워커가 담고, 연표 포장에서는 빠짐 */
const text = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const scripts = html => [...html.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<script\b[^>]*\ssrc="([^"]+)"/g)].map(m => m[1]);
{
  const maker = scripts(text('dlc-maker.html'));
  const at = maker.indexOf('js/form-keys.js');
  check(at >= 0 && maker.indexOf('js/core.js') < at && maker.indexOf('js/viewer.js') > at, 'dlc-maker.html이 js/form-keys.js를 core.js 뒤 · viewer.js 앞에 읽음', { 차례: at });
  check(!scripts(text('index.html')).includes('js/form-keys.js'), '보기 전용 index.html은 js/form-keys.js를 읽지 않음');
  check(text('sw.js').includes("'js/form-keys.js'"), 'sw.js PRECACHE에 js/form-keys.js');
  check(/const MAKER_ONLY = \[[^\]]*'js\/form-keys\.js'/.test(text('scripts/build-web.mjs')), 'build-web.mjs의 MAKER_ONLY에 js/form-keys.js (연표 포장에서 빠짐)');
}

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    const bytes = fs.readFileSync(file);
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.setDefaultTimeout(20000);
  await page.goto('http://127.0.0.1:' + server.address().port + '/dlc-maker.html');
  await page.locator('[data-start-new]').waitFor();
  await page.locator('[data-start-new] [name="name"]').fill('가상 길잡이 검사');
  await page.locator('[data-start-new] [name="id"]').fill('form-keys-check');
  await page.locator('[data-start-new] [name="how"][value="world"]').check();
  await page.locator('[data-start-new] button[type="submit"]').click();
  await page.waitForFunction(() => document.querySelector('#mkStart').hidden && window.HT && HT.formKeys && HT.viewer && HT.viewer.maker && HT.viewer.maker.draft);

  /* 가상 나라 하나: 지도자 셋 · 도읍 하나 · 여러 줄 설명 — 편집 창에 채워 저장한 뒤(편집 창은 그 나라를 계속 엶) 키를 누릅니다 */
  const opened = await page.evaluate(() => {
    HT.viewer.openEditor(null, 'period');
    const form = document.querySelector('#editorForm');
    const track = form.elements.track.value;
    HT.FORMS.period.fill(form, {
      name: '솔나라', track, start: 100, end: 200, description: '첫 줄\n둘째 줄\n셋째 줄',
      leaders: [{ name: '첫 임금', start: 100, end: 130 }, { name: '둘째 임금', start: 130, end: 160 }, { name: '셋째 임금', start: 160, end: 200 }],
      capitals: [{ city: '가람 고을', start: 100 }],
    });
    const uid = HT.viewer.saveEditor();
    return { uid, open: !document.querySelector('#editPane').hidden, rows: form.querySelectorAll('[data-cells="leaders"] .cell-row').length };
  });
  check(opened.uid && opened.open && opened.rows === 3, '작업본에 가상 나라를 만들고 편집 창을 엶', opened);
  await page.evaluate(() => {
    /* 지금 초점이 있는 칸의 자리: 목록 이름 · 몇 번째 줄 · 칸 클래스 · 값 */
    window.__where = () => {
      const a = document.activeElement;
      const row = a && HT.formKeys.rowOf(a);
      const list = row && row.parentElement;
      const tag = list ? [...list.attributes].filter(x => x.name.startsWith('data-')).map(x => `${x.name}=${x.value}`).join('&') : '';
      return { tag: a ? a.tagName : '', name: (a && a.name) || '', cls: a ? HT.formKeys.colKey(a) : '', list: tag, row: row ? [...list.children].indexOf(row) : -1, value: a && 'value' in a ? a.value : '' };
    };
    window.__leaders = () => [...document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row')].map(r => r.querySelector('.c-name').value);
    window.__focus = (sel, i = 0, caret = null) => {
      const el = document.querySelectorAll('#editorForm ' + sel)[i];
      el.focus();
      if (caret != null) el.setSelectionRange(caret, caret);
      return !!el;
    };
  });
  const where = () => page.evaluate(() => __where());
  const focus = (sel, i = 0, caret = null) => page.evaluate(([s, n, c]) => __focus(s, n, c), [sel, i, caret]);
  const leaders = () => page.evaluate(() => __leaders());
  const L = '[data-cells="leaders"] .cell-row';

  /* ② ↑↓ — 줄 안에서는 같은 열 */
  await focus(`${L} .c-start`, 0);
  await page.keyboard.press('ArrowDown');
  let w = await where();
  check(w.list === 'data-cells=leaders' && w.row === 1 && w.cls === 'c-start' && w.value === '130', '↓: 지도자 1번째 줄의 시작 → 2번째 줄의 시작', w);
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.row === 1 && w.cls === 'c-start', '↑: 아래 줄에서 위 줄의 같은 열로', w);

  /* ③ 목록 끝에서 ↓ — 목록 밖의 다음 글 칸 (닫힌 '여러 줄 붙여넣기' · 빈 내각 · 연호 목록을 건너 도읍 1번째 줄) */
  await focus(`${L} .c-start`, 2);
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(w.list === 'data-cells=capitals' && w.row === 0 && w.cls === 'c-name', '↓: 마지막 지도자 줄 → 닫힌 접는 구역을 건너 도읍 1번째 줄의 첫 칸', w);
  /* ↑: 도읍 첫 줄에서 위로 — 지도자 마지막 줄의 메모 (그 줄의 접힌 이설 상자 칸은 건너뜀) */
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.list === 'data-cells=leaders' && w.row === 2 && w.cls === 'c-note', '↑: 도읍 첫 줄 → 지도자 마지막 줄의 메모 (접힌 이설 상자의 칸은 건너뜀)', w);

  /* ④ 줄 밖: 이름 칸에서 ↓ — 보이는 다음 글 칸(고르기 · 체크는 멈추지 않음 · 숨은 날짜 칸 건너뜀) */
  await focus('[name="name"]');
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(w.tag === 'INPUT' && w.name === 'start', '↓: 줄 밖에서는 보이는 다음 글 칸 (기원 고르기는 건너뜀)', w);
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.name === 'name', '↑: 줄 밖에서 앞 글 칸', w);

  /* ⑤ Enter · Shift+Enter — 아래 줄 · 위 줄의 같은 칸, 마지막 줄이면 ＋로 새 줄 · 저장하지 않음 */
  const draftBefore = await page.evaluate(() => JSON.stringify(HT.viewer.maker.draft.periods));
  await focus(`${L} .c-name`, 0);
  await page.keyboard.press('Enter');
  w = await where();
  check(w.row === 1 && w.cls === 'c-name' && w.value === '둘째 임금', 'Enter: 아래 줄의 같은 칸', w);
  await page.keyboard.press('Shift+Enter');
  w = await where();
  check(w.row === 0 && w.cls === 'c-name', 'Shift+Enter: 위 줄의 같은 칸', w);
  await focus(`${L} .c-start`, 2);
  await page.keyboard.press('Enter');
  w = await where();
  let names = await leaders();
  check(names.length === 4 && w.row === 3 && w.cls === 'c-start' && w.value === '', 'Enter: 마지막 줄이면 ＋로 새 줄을 만들고 같은 칸으로', { w, names });
  await page.keyboard.press('Enter');
  w = await where();
  names = await leaders();
  check(names.length === 4 && w.list === 'data-cells=capitals', 'Enter: 텅 빈 마지막 줄에서는 새 줄을 또 만들지 않고 목록 뒤로', { w, names });
  const draftAfter = await page.evaluate(() => JSON.stringify(HT.viewer.maker.draft.periods));
  check(draftBefore === draftAfter, '한 줄 칸의 Enter는 저장하지 않음 (작업본 그대로)');
  await focus('[name="name"]');
  await page.keyboard.press('Enter');
  w = await where();
  check(w.name === 'start', 'Enter: 줄 밖 한 줄 칸에서는 다음 글 칸으로', w);

  /* ⑥ Alt+↑↓ — 줄 옮기기 (초점은 그 칸 그대로) */
  await focus(`${L} .c-name`, 0);
  await page.keyboard.press('Alt+ArrowDown');
  w = await where();
  names = await leaders();
  check(names[0] === '둘째 임금' && names[1] === '첫 임금' && w.row === 1 && w.value === '첫 임금', 'Alt+↓: 줄을 아래로 옮기고 초점은 그 칸에', { names, w });
  check(await page.evaluate(() => HT.viewer.state.editSnap !== JSON.stringify(HT.FORMS.period.read(document.querySelector('#editorForm')).item)), '줄을 옮기면 편집 창에 저장하지 않은 고침');
  await page.keyboard.press('Alt+ArrowUp');
  await page.keyboard.press('Alt+ArrowUp'); // 맨 위에서는 그대로
  names = await leaders();
  w = await where();
  check(names[0] === '첫 임금' && names[1] === '둘째 임금' && w.row === 0, 'Alt+↑: 위로 옮기기 · 맨 위에서는 그대로', { names, w });

  /* ⑦ Ctrl+D — 줄 복제(바로 아래) · Ctrl+Shift+Delete — 줄 지우기 */
  await focus(`${L} .c-start`, 1);
  await page.keyboard.press('Control+d');
  w = await where();
  names = await leaders();
  const dup = await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row')].map(r => [r.querySelector('.c-name').value, r.querySelector('.c-start').value]));
  check(names.length === 5 && dup[2][0] === '둘째 임금' && dup[2][1] === '130' && w.row === 2 && w.cls === 'c-start', 'Ctrl+D: 그 줄 바로 아래에 같은 값의 줄 · 초점은 복제한 줄의 같은 칸', { dup, w });
  await page.keyboard.press('Control+Shift+Delete');
  w = await where();
  names = await leaders();
  check(names.length === 4 && names.join('|') === '첫 임금|둘째 임금|셋째 임금|' && w.row === 2 && w.cls === 'c-start' && w.value === '160', 'Ctrl+Shift+Delete: 줄을 지우고 초점은 그 자리의 다음 줄 같은 칸', { names, w });
  await focus(`${L} .c-name`, 3);
  await page.keyboard.press('Control+Shift+Delete');
  w = await where();
  names = await leaders();
  check(names.length === 3 && w.row === 2 && w.cls === 'c-name', 'Ctrl+Shift+Delete: 마지막 줄을 지우면 위 줄의 같은 칸', { names, w });

  /* ⑧ 한글 조합 중에는 아무것도 하지 않음 — 실제 조합(CDP의 입력기 흉내) 중의 ↓ · Enter, 그리고 keyCode 229 */
  const cdp = await context.newCDPSession(page);
  await focus(`${L} .c-note`, 0);
  await cdp.send('Input.imeSetComposition', { text: '가', selectionStart: 1, selectionEnd: 1 });
  const composing = await page.evaluate(() => {
    const a = document.activeElement;
    const seen = [];
    const spy = e => seen.push([e.key, e.isComposing, e.defaultPrevented]);
    a.addEventListener('keydown', spy);
    window.__spyOff = () => a.removeEventListener('keydown', spy);
    window.__seen = seen;
    return a.value;
  });
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  w = await where();
  const seen = await page.evaluate(() => (window.__spyOff(), window.__seen));
  check(w.row === 0 && w.cls === 'c-note' && (await leaders()).length === 3, '한글 조합 중의 ↓ · Enter: 칸을 옮기지도 줄을 만들지도 않음', { composing, seen, w });
  await cdp.send('Input.insertText', { text: '' }).catch(() => {});
  const synthetic = await page.evaluate(() => {
    const a = document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row .c-start')[0];
    a.focus();
    const out = [];
    for (const init of [{ key: 'ArrowDown', isComposing: true }, { key: 'Enter', isComposing: true }, { key: 'ArrowDown', code229: true }]) {
      const ev = new KeyboardEvent('keydown', { key: init.key, isComposing: !!init.isComposing, bubbles: true, cancelable: true });
      if (init.code229) Object.defineProperty(ev, 'keyCode', { get: () => 229 });
      a.dispatchEvent(ev);
      out.push({ key: init.key, prevented: ev.defaultPrevented, same: document.activeElement === a });
    }
    return out;
  });
  /* Enter는 viewer.js의 원래 '한 줄 칸 Enter 삼키기'가 막으므로(조합 중에도 — 예전 그대로) 화살표만 막히지 않았는지 봅니다 */
  check(synthetic.every(x => x.same && (x.key === 'Enter' || !x.prevented)) && (await leaders()).length === 3, 'isComposing · keyCode 229인 키: 칸을 옮기지도 줄을 만들지도 않고, 화살표는 막지도 않음', synthetic);

  /* ⑨ 여러 줄 글 칸 — 커서가 첫 줄에서 ↑ · 끝 줄에서 ↓일 때만 칸 이동 (길어서 접힌 줄도 줄로 셈) */
  await focus('[name="description"]', 0, 4); // '첫 줄\n|둘째 줄'
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.name === 'description', '여러 줄 칸: 가운데 줄에서 ↑는 칸 안의 커서 이동', w);
  await focus('[name="description"]', 0, 1);
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.name !== 'description' && w.tag === 'INPUT', '여러 줄 칸: 첫 줄에서 ↑는 앞 칸으로', w);
  await page.evaluate(() => {
    const ta = document.querySelector('#editorForm [name="description"]');
    ta.value = '바람 들녘 가람 고을 '.repeat(60).trim(); // 줄바꿈 없이 칸 폭에서 여러 줄로 접히는 글
    ta.focus();
    ta.setSelectionRange(ta.value.length, ta.value.length);
  });
  await page.keyboard.press('ArrowUp');
  w = await where();
  const wrapped = await page.evaluate(() => { const ta = document.querySelector('#editorForm [name="description"]'); return { lines: Math.round(ta.scrollHeight / parseFloat(getComputedStyle(ta).lineHeight)), caret: ta.selectionStart, len: ta.value.length }; });
  check(w.name === 'description' && wrapped.caret < wrapped.len, '여러 줄 칸: 접힌 긴 글의 끝 줄에서 ↑는 칸 안에서 위 줄로', { w, wrapped });
  await page.evaluate(() => { const ta = document.querySelector('#editorForm [name="description"]'); ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); });
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(w.name !== 'description', '여러 줄 칸: 끝 줄에서 ↓는 다음 칸으로', w);
  await page.evaluate(() => { const ta = document.querySelector('#editorForm [name="description"]'); ta.value = '첫 줄\n둘째 줄\n셋째 줄'; ta.dispatchEvent(new Event('input', { bubbles: true })); });

  /* ⑩ 고르기는 화살표를 가로채지 않음 */
  await focus('[data-cells="capitals"] .cell-row .c-role');
  const roleBefore = await page.evaluate(() => document.activeElement.value);
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(w.tag === 'SELECT' && w.cls === 'c-role', '고르기(select)의 ↓는 고르기 것 — 칸을 옮기지 않음', { roleBefore, w });
  await page.evaluate(v => { document.activeElement.value = v; }, roleBefore);

  /* ⑪ 펼친 이설 상자 — 이설 줄끼리 같은 열 · 마지막 이설 줄의 Enter는 새 이설 줄 */
  await page.evaluate(() => {
    const row = document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row')[0];
    HT.toggleCellAlts(row, true, { instant: true });
    row.querySelector('[data-calt-add]').click();
    const alt = row.querySelector('[data-calt-rows] .alt-row .alt-year');
    alt.value = '101';
    alt.focus();
  });
  await page.keyboard.press('Enter');
  w = await where();
  const altRows = await page.evaluate(() => document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row')[0].querySelectorAll('[data-calt-rows] .alt-row').length);
  check(w.list === 'data-calt-rows=' && w.row === 1 && w.cls === 'alt-year' && altRows === 2, '이설 상자: 마지막 이설 줄의 Enter → 새 이설 줄의 같은 칸', { w, altRows });
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.list === 'data-calt-rows=' && w.row === 0 && w.cls === 'alt-year' && w.value === '101', '이설 상자: ↑는 위 이설 줄의 같은 열', w);
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.list === 'data-cells=leaders' && w.row === 0 && w.cls === 'c-note', '이설 상자: 첫 이설 줄에서 ↑는 그 지도자 줄의 메모로', w);
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(w.list === 'data-cells=leaders' && w.row === 1 && w.cls === 'c-note', '지도자 줄의 ↓는 펼친 이설 상자를 넘어 아래 지도자 줄의 같은 열', w);
  await page.evaluate(() => {
    const row = document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row')[0];
    for (const b of [...row.querySelectorAll('[data-calt-del]')]) b.click();
    HT.toggleCellAlts(row, false, { instant: true });
  });

  /* ⑫ 문서 칸의 [[ 자동 완성 상자가 열려 있으면 그 상자가 ↑↓를 가짐 */
  await page.evaluate(() => { const d = document.querySelector('#editorForm details[data-adv="wiki"]'); d.open = true; });
  await focus('[name="wiki"]');
  await page.keyboard.type('[[솔');
  const acOpen = await page.evaluate(() => [...document.querySelectorAll('.wk-ac')].some(b => !b.hidden && b.querySelector('.wk-ac-item')));
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(acOpen && w.name === 'wiki', '[[ 자동 완성 상자가 열려 있으면 ↓는 상자 안에서 (칸을 옮기지 않음)', { acOpen, w });
  await page.keyboard.press('Escape');
  await page.evaluate(() => { const ta = document.querySelector('#editorForm [name="wiki"]'); ta.value = ''; ta.dispatchEvent(new Event('input', { bubbles: true })); document.querySelector('#editorForm details[data-adv="wiki"]').open = false; });

  /* ⑬ 큰 입력 창이 열려 있으면 길잡이는 쉼 */
  const popped = await page.evaluate(() => HT.fieldPop.open(document.querySelector('#editorForm [name="description"]')));
  await focus(`${L} .c-start`, 0);
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(popped && w.row === 0 && w.cls === 'c-start', '큰 입력 창이 열려 있으면 ↓로 칸을 옮기지 않음', { popped, w });
  await page.evaluate(() => HT.fieldPop.close());

  /* ⑭ 화면 밖의 칸으로 가면 보이게 스크롤 — 움직임 줄이기에서는 곧장, 보통 움직임에서는 스프링(--t-move)으로 */
  const inView = () => page.evaluate(() => {
    const a = document.activeElement, box = document.querySelector('#editPane .ep-body');
    const r = a.getBoundingClientRect(), b = box.getBoundingClientRect();
    return { top: Math.round(r.top - b.top), bottom: Math.round(b.bottom - r.bottom), scroll: Math.round(box.scrollTop), inside: r.top >= b.top && r.bottom <= b.bottom };
  });
  await page.evaluate(() => { const box = document.querySelector('#editPane .ep-body'); box.scrollTop = 0; });
  await focus(`${L} .c-start`, 2);
  await page.evaluate(() => { const box = document.querySelector('#editPane .ep-body'); box.scrollTop = box.scrollHeight; });
  await page.keyboard.press('ArrowUp');
  let view = await inView();
  check(view.inside, '움직임 줄이기: 화면 밖의 칸으로 가면 곧장 보이게', view);
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.waitForFunction(() => HT.motion.T.move > 0);
  await page.evaluate(() => { const box = document.querySelector('#editPane .ep-body'); box.scrollTop = box.scrollHeight; });
  const glide = await page.evaluate(async () => {
    const box = document.querySelector('#editPane .ep-body');
    const el = document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row .c-start')[0];
    el.focus({ preventScroll: true });
    box.scrollTop = box.scrollHeight;
    const start = box.scrollTop;
    el.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    const marks = [];
    const t0 = performance.now();
    while (performance.now() - t0 < 900) {
      await new Promise(requestAnimationFrame);
      marks.push(Math.round(box.scrollTop));
    }
    return { start, marks: [...new Set(marks)].length, end: Math.round(box.scrollTop), move: HT.motion.T.move };
  });
  view = await inView();
  check(view.inside && glide.marks > 3 && glide.end < glide.start, '보통 움직임: 여러 프레임에 걸쳐 스크롤해 칸이 보이게 (스프링 · --t-move)', { glide, view });
  await page.emulateMedia({ reducedMotion: 'reduce' });

  /* ⑮ Ctrl+S 저장은 그대로 — 줄을 바꾼 폼이 저장되고 작업본에 들어감 */
  await focus(`${L} .c-name`, 1);
  await page.keyboard.press('Control+d');
  await page.keyboard.press('Control+a');
  await page.keyboard.type('넷째 임금');
  await focus(`${L} .c-start`, 2); // 복제한 줄의 시작
  await page.keyboard.press('Control+a');
  await page.keyboard.type('145');
  await focus(`${L} .c-end`, 1); // 둘째 임금의 끝도 145로 — 두 칸이 겹치지 않게
  await page.keyboard.press('Control+a');
  await page.keyboard.type('145');
  await page.keyboard.press('Control+s');
  await page.waitForTimeout(100);
  const saved = await page.evaluate(() => {
    const p = HT.viewer.maker.draft.periods.find(x => x.name === '솔나라');
    return { leaders: (p.leaders || []).map(c => (Array.isArray(c) ? c[0] : c.name)), starts: (p.leaders || []).map(c => (Array.isArray(c) ? c[1] : c.start)), dirty: HT.viewer.state.editSnap !== JSON.stringify(HT.FORMS.period.read(document.querySelector('#editorForm')).item) };
  });
  check(saved.leaders.join('|') === '첫 임금|둘째 임금|넷째 임금|셋째 임금' && saved.starts.join('|') === '100|130|145|160' && !saved.dirty, 'Ctrl+S: 복제 · 고친 줄이 저장됨 (시작 순으로 놓임)', saved);

  /* ⑯ 다른 줄 목록도 같은 꼴로 — 새 조약의 당사국 줄(고르기 · 글 · 숫자 칸) · 조항 줄(여러 줄 본문) */
  const treaty = await page.evaluate(() => {
    HT.viewer.openEditor(null, 'treaty');
    const form = document.querySelector('#editorForm');
    form.querySelector('[data-tr-party-add]').click();
    const row = form.querySelector('[data-tr-parties] .tr-party');
    row.querySelector('.p-polity').value = '갑 왕국';
    row.querySelector('.p-side').value = '1';
    row.querySelector('.p-polity').focus();
    return { open: form.querySelector('details[data-adv="treaty"]').open, rows: form.querySelectorAll('[data-tr-parties] .tr-party').length };
  });
  await page.keyboard.press('Enter');
  w = await where();
  const parties = await page.evaluate(() => document.querySelectorAll('#editorForm [data-tr-parties] .tr-party').length);
  check(treaty.open && parties === 2 && w.list === 'data-tr-parties=' && w.row === 1 && w.cls === 'p-polity', '조약 당사국 줄: 마지막 줄의 Enter → ＋ 당사국으로 새 줄의 같은 칸', { treaty, parties, w });
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.row === 0 && w.cls === 'p-polity' && w.value === '갑 왕국', '조약 당사국 줄: ↑는 위 줄의 같은 열', w);
  await focus('[data-tr-parties] .tr-party .p-side');
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.cls === 'p-side' && w.row === 0, '숫자 칸(편)의 ↑는 그 칸의 값 바꾸기 — 칸을 옮기지 않음', w);
  await page.evaluate(() => document.querySelector('#editorForm [data-tr-article-add]').click());
  await focus('[data-tr-articles] .tr-article .a-text');
  await page.keyboard.type('첫 조각');
  await page.keyboard.press('Enter');
  await page.keyboard.type('둘째 조각');
  w = await where();
  const articles = await page.evaluate(() => document.querySelectorAll('#editorForm [data-tr-articles] .tr-article').length);
  check(w.cls === 'a-text' && w.value === '첫 조각\n둘째 조각' && articles === 1, '조항 본문(여러 줄 칸)의 Enter는 줄바꿈 — 새 줄을 만들지 않음', { w, articles });
  await page.keyboard.press('Control+d');
  w = await where();
  const articles2 = await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-tr-articles] .tr-article .a-text')].map(t => t.value));
  check(articles2.length === 2 && articles2[1] === '첫 조각\n둘째 조각' && w.row === 1 && w.cls === 'a-text', '조항 줄: Ctrl+D 복제 (여러 줄 본문 그대로)', { articles2, w });
  await page.keyboard.press('Control+Shift+Delete');
  await page.keyboard.press('Control+Shift+Delete');
  w = await where();
  const articles3 = await page.evaluate(() => document.querySelectorAll('#editorForm [data-tr-articles] .tr-article').length);
  check(articles3 === 0 && w.tag === 'BUTTON', '조항 줄을 모두 지우면 초점은 그 목록의 ＋ (body로 떨어지지 않음)', { articles3, w });
  await page.evaluate(() => { HT.viewer.closeEditor(); }); // 묻는 창이 뜨면 그 답을 기다리는 약속 — 기다리지 않고 아래에서 답함
  await page.waitForFunction(() => document.querySelector('dialog#mkAskDialog[open]') || document.querySelector('#editPane').hidden);
  if (await page.evaluate(() => !!document.querySelector('dialog#mkAskDialog[open]'))) await page.locator('#mkAskNo').click(); // 버리고 닫기
  await page.evaluate(uid => HT.viewer.openEditor(uid), opened.uid);

  /* ⑱ 형식 3의 새 줄 목록 · 숨은 상자 (통합 — F1 · F2와 잇기, js/form-keys.js 머리 주석의 꼴): 상자 · 목록마다 하나씩 */
  await page.evaluate(() => {
    /* 지도자 i번째 줄의 [사람] 단추와 상자 */
    window.__cx = i => {
      const row = document.querySelectorAll('#editorForm [data-cells="leaders"] .cell-row')[i];
      return { row, btn: row.querySelector('[data-cx-toggle]'), box: [...row.children].find(el => el.classList.contains('cell-xbox')) };
    };
  });
  /* (가) 지도자 줄의 [사람] 상자 — 딸린 상자(HT.formKeys.SUB_BOXES): 사람 · 자리 이음 칸은 앞 / 뒤 칸으로, 상자 안의 이름 · 부모 줄은 제 목록 */
  const xb = await page.evaluate(i => {
    const { box, btn } = __cx(i);
    HT.toggleCellBox(box, btn, true, { instant: true });
    box.querySelector('.x-person').focus();
    return { open: !box.hidden, sub: HT.formKeys.SUB_BOXES.includes('.cell-xbox') };
  }, 0);
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(xb.open && xb.sub && w.list === 'data-cells=leaders' && w.row === 0 && w.cls === 'x-kin', '[사람] 상자: 사람 칸의 ↓는 상자 안의 다음 칸(자리 이음의 관계) — 아래 지도자 줄로 가지 않음', { xb, w });
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.list === 'data-cells=leaders' && w.row === 0 && w.cls === 'c-note', '[사람] 상자: 첫 칸(사람)의 ↑는 그 지도자 줄의 메모로', w);
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(w.list === 'data-cells=leaders' && w.row === 1 && w.cls === 'c-note', '지도자 줄의 ↓는 펼친 [사람] 상자를 넘어 아래 지도자 줄의 같은 열', w);
  const nm = await page.evaluate(i => {
    const { box } = __cx(i);
    box.querySelector('.names-box [data-name-add]').click();
    const t = box.querySelector('.names-box [data-names-rows] .name-row .x-text');
    t.value = '첫 임금 원어';
    t.focus();
    return box.querySelectorAll('.names-box .name-row').length;
  }, 0);
  await page.keyboard.press('Enter');
  w = await where();
  const nm2 = await page.evaluate(i => __cx(i).box.querySelectorAll('.names-box .name-row').length, 0);
  check(nm === 1 && nm2 === 2 && w.list === 'data-names-rows=' && w.row === 1 && w.cls === 'x-text', '[사람] 상자의 이름 줄: 마지막 줄의 Enter → ＋ 이름 추가로 새 줄의 같은 칸', { nm, nm2, w });
  await page.keyboard.press('ArrowUp');
  w = await where();
  check(w.list === 'data-names-rows=' && w.row === 0 && w.cls === 'x-text' && w.value === '첫 임금 원어', '[사람] 상자의 이름 줄: ↑는 위 이름 줄의 같은 열', w);
  const kin = await page.evaluate(i => {
    const { box } = __cx(i);
    box.querySelector('[data-kin-add="parent"]').click();
    const who = box.querySelector('[data-kin-rows="parent"] .parent-row .x-who');
    who.value = '미상';
    who.focus();
    return box.querySelectorAll('[data-kin-rows="parent"] .parent-row').length;
  }, 0);
  await page.keyboard.press('Enter');
  w = await where();
  const kin2 = await page.evaluate(i => __cx(i).box.querySelectorAll('[data-kin-rows="parent"] .parent-row').length, 0);
  check(kin === 1 && kin2 === 2 && w.list === 'data-kin-rows=parent' && w.row === 1 && w.cls === 'x-who', '[사람] 상자의 부모 줄: 마지막 줄의 Enter → ＋ 부모 추가로 새 줄의 같은 칸', { kin, kin2, w });
  await page.evaluate(i => {
    const { box, btn } = __cx(i);
    for (const b of [...box.querySelectorAll('[data-name-del], [data-kin-del]')]) b.click();
    HT.toggleCellBox(box, btn, false, { instant: true });
  }, 0);

  /* (나) 폼의 이름(원어 등) 줄 — 접는 구역 안의 이름 목록(.alt-rows): ↓ 같은 열 · 마지막 줄의 Enter는 새 줄 */
  const nf = await page.evaluate(() => {
    const form = document.querySelector('#editorForm');
    form.querySelector('details[data-adv="names"]').open = true;
    const add = form.querySelector('[data-names-field] > .toolbar [data-name-add]');
    add.click();
    add.click();
    const rows = form.querySelectorAll('[data-names-field] > [data-names-rows] .name-row');
    rows[0].querySelector('.x-text').value = '솔나라 원어';
    rows[1].querySelector('.x-text').value = '솔 옛 이름';
    rows[0].querySelector('.x-lang').focus();
    return rows.length;
  });
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(nf === 2 && w.list === 'data-names-rows=' && w.row === 1 && w.cls === 'x-lang', '이름(원어 등) 줄: ↓는 아래 이름 줄의 같은 열(언어)', { nf, w });
  await focus('[data-names-field] > [data-names-rows] .name-row .x-text', 1);
  await page.keyboard.press('Enter');
  w = await where();
  const nf2 = await page.evaluate(() => document.querySelectorAll('#editorForm [data-names-field] > [data-names-rows] .name-row').length);
  check(nf2 === 3 && w.list === 'data-names-rows=' && w.row === 2 && w.cls === 'x-text', '이름(원어 등) 줄: 마지막 줄의 Enter → ＋ 이름 추가로 새 줄', { nf2, w });
  await page.evaluate(() => {
    const form = document.querySelector('#editorForm');
    for (const b of [...form.querySelectorAll('[data-names-field] > [data-names-rows] [data-name-del]')]) b.click();
    form.querySelector('details[data-adv="names"]').open = false;
  });
  const closeEditor = async () => {
    await page.evaluate(() => { HT.viewer.closeEditor(); });
    await page.waitForFunction(() => document.querySelector('dialog#mkAskDialog[open]') || document.querySelector('#editPane').hidden);
    if (await page.evaluate(() => !!document.querySelector('dialog#mkAskDialog[open]'))) await page.locator('#mkAskNo').click(); // 버리고 닫기
    await page.waitForFunction(() => document.querySelector('#editPane').hidden);
  };
  await closeEditor();

  /* (다) 단체 폼 — 집권 기간 줄(칸 줄 · 이설 상자 있음) · 구성 나라 줄(나라 줄): 같은 열 · Enter로 새 줄 · Alt+↓ · Ctrl+D */
  const gp = await page.evaluate(() => {
    HT.viewer.openEditor(null, 'group');
    const form = document.querySelector('#editorForm');
    HT.FORMS.group.fill(form, {
      name: '들바람 모임', track: form.elements.track.value, start: 110, end: 190, within: '솔나라',
      power: [{ name: '집권', start: 120, end: 150 }, { name: '실권', start: 150, end: 170 }],
      members: [{ polity: '솔나라', role: '맹주' }, { polity: '물나라' }],
    });
    form.querySelectorAll('[data-gp-power] .gp-power-row .c-start')[0].focus();
    return { power: form.querySelectorAll('[data-gp-power] .gp-power-row').length, members: form.querySelectorAll('[data-gp-members] .gp-polity-row').length };
  });
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(gp.power === 2 && w.list === 'data-gp-power=' && w.row === 1 && w.cls === 'c-start' && w.value === '150', '단체 폼 집권 기간 줄: ↓는 아래 줄의 같은 열(시작)', { gp, w });
  await page.keyboard.press('Enter');
  w = await where();
  const power2 = await page.evaluate(() => document.querySelectorAll('#editorForm [data-gp-power] .gp-power-row').length);
  check(power2 === 3 && w.list === 'data-gp-power=' && w.row === 2 && w.cls === 'c-start', '단체 폼 집권 기간 줄: 마지막 줄의 Enter → ＋ 기간 추가로 새 줄의 같은 칸', { power2, w });
  const members = () => page.evaluate(() => [...document.querySelectorAll('#editorForm [data-gp-members] .gp-polity-row .s-from')].map(i => i.value));
  await focus('[data-gp-members] .gp-polity-row .s-from', 0);
  await page.keyboard.press('Alt+ArrowDown');
  w = await where();
  let ms = await members();
  check(gp.members === 2 && ms.join('|') === '물나라|솔나라' && w.list === 'data-gp-members=' && w.row === 1 && w.value === '솔나라', '단체 폼 구성 나라 줄: Alt+↓로 줄 옮기기 (초점은 그 칸)', { ms, w });
  await page.keyboard.press('Control+d');
  w = await where();
  ms = await members();
  check(ms.join('|') === '물나라|솔나라|솔나라' && w.row === 2 && w.cls === 's-from', '단체 폼 구성 나라 줄: Ctrl+D 복제 (바로 아래 · 같은 칸)', { ms, w });
  await page.keyboard.press('Control+Shift+Delete');
  ms = await members();
  check(ms.join('|') === '물나라|솔나라', '단체 폼 구성 나라 줄: Ctrl+Shift+Delete로 지우기', ms);
  await closeEditor();

  /* (라) 제도 폼의 칸 줄 — 같은 열 · 마지막 줄의 Enter는 ＋ 칸 추가 */
  const inst = await page.evaluate(() => {
    HT.viewer.openEditor(null, 'institution');
    const form = document.querySelector('#editorForm');
    HT.FORMS.institution.fill(form, { theme: '조세제도', polity: '솔나라', spans: [{ name: '밭 나눔', start: 100 }, { name: '돈 거둠', start: 150 }] });
    form.querySelectorAll('[data-inst-spans] .inst-span-row .c-name')[0].focus();
    return form.querySelectorAll('[data-inst-spans] .inst-span-row').length;
  });
  await page.keyboard.press('ArrowDown');
  w = await where();
  check(inst === 2 && w.list === 'data-inst-spans=' && w.row === 1 && w.cls === 'c-name' && w.value === '돈 거둠', '제도 폼 칸 줄: ↓는 아래 줄의 같은 열(이름)', { inst, w });
  await page.keyboard.press('Enter');
  w = await where();
  const inst2 = await page.evaluate(() => document.querySelectorAll('#editorForm [data-inst-spans] .inst-span-row').length);
  check(inst2 === 3 && w.list === 'data-inst-spans=' && w.row === 2 && w.cls === 'c-name', '제도 폼 칸 줄: 마지막 줄의 Enter → ＋ 칸 추가로 새 줄의 같은 칸', { inst2, w });
  await closeEditor();
  await page.evaluate(uid => HT.viewer.openEditor(uid), opened.uid);

  /* ⑰ 단축키 목록(상태 줄의 '단축키 ?')에 새 키 */
  await page.locator('#mkStatus [data-cmd="keys"]').click();
  await page.locator('dialog.mk-box[open] .mk-keys').waitFor();
  const listed = await page.evaluate(() => { const t = document.querySelector('dialog.mk-box[open] .mk-keys').textContent; return HT.formKeys.KEYS.filter(([l, k]) => !(t.includes(l) && t.includes(k))).map(x => x[0]); });
  await page.evaluate(() => { const b = document.querySelector('dialog.mk-box[open] .dlg-body'); b.scrollTop = b.scrollHeight; }); // 새 줄은 목록 끝에
  await page.screenshot({ path: path.join(output, '단축키-목록-1920-1배.png') });
  check(listed.length === 0, '메이커 단축키 목록에 편집 창의 새 키가 모두 보임', { 빠진것: listed });
  await page.keyboard.press('Escape');

  /* 결과 그림: 편집 창의 지도자 줄에 초점 (1920×1080 · 1배) */
  await page.waitForTimeout(3500); // 알림이 걷힐 때까지
  await focus(`${L} .c-start`, 1);
  await page.keyboard.press('ArrowDown');
  await page.evaluate(() => { const box = document.querySelector('#editPane .ep-body'); const r = document.activeElement.closest('.field').getBoundingClientRect(); box.scrollTop += r.top - box.getBoundingClientRect().top - 12; });
  await page.screenshot({ path: path.join(output, '입력-칸-길잡이-1920-1배.png') });
  check(report.오류.length === 0, '브라우저 실행 오류 없음', report.오류);
  await context.close();
} catch (e) { report.오류.push(e.stack || String(e)); process.exitCode = 1; }
finally { await browser.close(); server.close(); fs.writeFileSync(path.join(output, '입력-칸-길잡이.json'), JSON.stringify(report, null, 2) + '\n'); }
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류, 결과: output }));
