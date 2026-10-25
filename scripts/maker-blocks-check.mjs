/* 메이커 편집 창의 블록(10건 D3 결정 1~5 — js/maker-blocks.js)과 메이커 안 끌기 한 꼴(결정 3 C — js/maker-drag.js HT.makerDrag.slot)을 실제 브라우저 · 실제 포인터로 검사합니다.
   node scripts/maker-blocks-check.mjs <검사할 폴더> <결과 폴더>
   가상 작업본(나라 셋 — 해온국 · 가온국 · 나래국, 지도자 솔빛 · 가람 · 누리 · 한별 …)과 잠김을 푼 가상 이웃 팩 하나를 독립 브라우저의 저장소에만 넣고 봅니다:
   ① 읽는 곳 · 포장 목록  ② 블록 폼 — 쓴 블록만 · 칩 · 머리의 개수 · 요약 · 폼의 읽기 값이 블록 전과 같음(옛 파일 지문 그대로)  ③ 손잡이 — 늘 보임 · 첫 줄 맨 앞 · 지도자 줄 높이
   ④ 블록 메뉴 — 복제 · 위로 · 아래로 · 종류 바꾸기 · 지우기 · 여러 줄 고르기 · 맞바꾸기  ⑤ 끌기 — 같은 목록(빈 자리 + 미리 글) · 다른 목록(종류 바꾸기) · 놓을 수 없는 곳
   ⑥ 다른 나라로 옮기기 — 제 나라 · 남의 나라(덮어쓰기) · 되돌리기 한 걸음 · 칸 문서 따라감  ⑦ '/' 명령 — 글 칸 밖에서만 · 거름 · 한글 조합 중 무시  ⑧ 칩 · 블록 머리 ＋
   ⑨ 사람 상자(형식 3) 왕복 그대로 · 다른 폼(사건 · 인물)도 블록  ⑩ 1배 그림(1920×1080 · 100%).
   Playwright는 HT_PLAYWRIGHT_ROOT(그 package.json) · 브라우저는 HT_BROWSER(기본 msedge)로 — 다른 메이커 검사와 같게 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/메이커-블록');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};

/* ① 읽는 곳 · 포장 목록: 메이커만 읽고(maker-drag 뒤 · viewer 앞), 서비스 워커가 담고, 연표 포장에서는 빠짐 */
const text = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const scripts = html => [...html.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<script\b[^>]*\ssrc="([^"]+)"/g)].map(m => m[1]);
{
  const maker = scripts(text('dlc-maker.html'));
  const at = maker.indexOf('js/maker-blocks.js');
  check(at >= 0 && maker.indexOf('js/maker-drag.js') < at && maker.indexOf('js/viewer.js') > at, 'dlc-maker.html이 js/maker-blocks.js를 maker-drag.js 뒤 · viewer.js 앞에 읽음', { 차례: at });
  check(!scripts(text('index.html')).includes('js/maker-blocks.js'), '보기 전용 index.html은 js/maker-blocks.js를 읽지 않음');
  check(text('sw.js').includes("'js/maker-blocks.js'"), 'sw.js PRECACHE에 js/maker-blocks.js');
  check(/const MAKER_ONLY = \[[^\]]*'js\/maker-blocks\.js'/.test(text('scripts/build-web.mjs')), 'build-web.mjs의 MAKER_ONLY에 js/maker-blocks.js (연표 포장에서 빠짐)');
}

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'dlc-maker.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      const t = bytes.toString('utf8'), marker = 'if (maker) maker.start();';
      assert.equal(t.split(marker).length, 2, 'viewer.js의 메이커 시작 줄이 하나가 아님');
      bytes = Buffer.from(t.replace(marker, marker + ' window.__maker = maker; window.__state = state;'));
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));

/* 가상 자료 — 확인용 · 고증 아님 (실제 역사 이름 없음) */
const OWN = 'blocks-check';
const NEAR = 'blocks-neighbor';
const L = (name, start, end, more = {}) => Object.assign({ name, start, end }, more);
const draft = {
  format: 'history-timeline-dlc', formatVersion: 2, id: OWN, name: '가상 블록 검사', version: '1.0.0', author: '', description: '',
  tracks: [{ id: 'sea', name: '바다 땅', order: 10 }],
  categories: [],
  peoples: [{ id: 'p-wind', name: '바람겨레' }],
  periods: [
    {
      id: 'haeon', track: 'sea', name: '해온국', start: 520, end: 700, people: '바람겨레', description: '확인용 가상 나라 — 고증 아님',
      leaders: [L('솔빛', 520, 548, { ordinal: 1 }), L('가람', 548, 575, { ordinal: 2, temple: '물마루', person: '가온', accession: { kin: 'son', how: 'hereditary' }, names: [{ text: 'Garam', lang: 'x-test-Latn', kind: 'roman' }] }), L('누리', 575, 611, { ordinal: 3 }), L('한별', 611, 640, { ordinal: 4 })],
      eras: [L('새벽', 548, 560), L('물결', 560, 575)],
      capitals: [{ city: '달내', start: 520, end: 590 }, { city: '솔뫼', start: 590 }],
    },
    { id: 'gaon', track: 'sea', name: '가온국', start: 540, end: 700, people: '바람겨레', leaders: [L('마루', 540, 586), L('여울', 586, 630)] },
    { id: 'narae', track: 'sea', name: '나래국', start: 600, end: 690 },
  ],
  events: [{ id: 'e1', track: 'sea', title: '봄맞이 잔치', start: 560, polity: '해온국' }],
  figures: [{ id: 'f1', track: 'sea', name: '가온', birth: 530, death: 590 }],
  documents: { 'haeon': '== 개요 ==\n확인용 가상 나라.\n== 바닷길 ==\n포구 셋.\n== 도읍 ==\n달내 · 솔뫼', 'cell:haeon:leaders:가람@548': '가람의 칸 문서' },
  epochs: [], organs: [], cultures: [], dynasties: [], patches: [], rankDefs: [], requires: [], scopes: [],
};
const near = {
  format: 'history-timeline-dlc', formatVersion: 2, id: NEAR, name: '확인용 이웃 팩', version: '1.0.0',
  tracks: [{ id: 'sea', name: '바다 땅' }], peoples: [],
  periods: [{ id: 'baram', track: 'sea', name: '바람국', start: 500, end: 620, leaders: [L('물빛', 500, 560)] }],
  events: [],
};

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
  await context.addInitScript(({ draft, near, OWN, NEAR }) => {
    if (sessionStorage.getItem('blocks-seeded')) return;
    sessionStorage.setItem('blocks-seeded', '1');
    localStorage.clear();
    localStorage.setItem('ht.packs.installed', JSON.stringify([near]));
    localStorage.setItem('ht.maker.draft', JSON.stringify(draft));
    localStorage.setItem('ht.maker.refs', JSON.stringify({ [OWN]: [{ id: NEAR, show: true, locked: false }] }));
  }, { draft, near, OWN, NEAR });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => m.type() === 'error' && report.오류.push(m.text()));
  page.setDefaultTimeout(20000);
  await page.goto('http://127.0.0.1:' + server.address().port + '/dlc-maker.html');
  await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden && HT.makerBlocks);
  await page.waitForTimeout(300);
  const open = async uid => {
    await page.evaluate(u => HT.viewer.openEditor(u), uid);
    await page.waitForFunction(() => !document.querySelector('#editPane').hidden);
    await page.waitForTimeout(150);
  };
  await open(`${OWN}/haeon`);
  const F = '#editorForm';
  const LR = `${F} [data-cells="leaders"] > .cell-row`;
  const grip = i => page.locator(`${LR} > .mk-grip`).nth(i);
  const raw = () => page.evaluate(() => JSON.parse(JSON.stringify(__maker.draft)));
  const steps = () => page.evaluate(() => __maker.history.index);
  const names = (kind = 'leaders') => page.evaluate(k => [...document.querySelectorAll(`#editorForm [data-cells="${k}"] > .cell-row`)].map(r => (r.querySelector(':scope > .c-name') || {}).value), kind);
  const read = () => page.evaluate(() => HT.FORMS.period.read(document.querySelector('#editorForm')).item);
  const blocks = () => page.evaluate(() => [...document.querySelectorAll('#editorFields .mk-blocks details.mk-blk')].map(b => ({ id: b.dataset.blk, hidden: b.hidden, open: b.open, n: b.querySelector('summary .n').textContent, sum: b.querySelector('summary .sum').textContent })));
  const chips = () => page.evaluate(() => [...document.querySelectorAll('#editorFields .mk-blk-chip')].map(c => c.textContent.replace('＋', '').trim()));
  const menuText = () => page.evaluate(() => { const m = document.querySelector('.mk-bmenu'); return m && !m.hidden ? m.innerText : ''; });
  const menuItems = () => page.evaluate(() => [...document.querySelectorAll('.mk-bmenu:not([hidden]) .ctx-item')].map(b => b.querySelector('.ctx-label').textContent.replace(/\s*새$/, '')));
  const pick = async label => { await page.locator('.mk-bmenu .ctx-item', { hasText: label }).first().click(); await page.waitForTimeout(120); };
  /** 편집 창의 고침을 버리고 그 나라를 다시 엶 (저장하지 않은 고침이 있으면 '버리고 닫기') */
  const reset = async (uid = `${OWN}/haeon`) => {
    await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());
    const p = page.evaluate(() => HT.viewer.closeEditor());
    const ask = page.locator('#mkAskDialog[open]');
    if (await ask.waitFor({ timeout: 1500 }).then(() => true, () => false)) await page.locator('#mkAskNo').click();
    await p;
    await open(uid);
  };
  const toDesc = () => page.evaluate(() => { const body = document.querySelector('#editorForm .ep-body'); const d = document.querySelector('#editorForm [name="description"]').closest('.field'); body.scrollTop += d.getBoundingClientRect().top - body.getBoundingClientRect().top - 8; });
  const shotPane = async name => page.screenshot({ path: path.join(output, name), clip: { x: 1340, y: 0, width: 580, height: 1080 } });
  const toolbarFind = await page.evaluate(() => { const el = document.querySelector('.mk-tools .mk-find'), cs = getComputedStyle(el); return { height: el.getBoundingClientRect().height, top: cs.marginTop, bottom: cs.marginBottom, padding: cs.paddingLeft }; });
  check(toolbarFind.height === 28 && toolbarFind.top === '0px' && toolbarFind.bottom === '0px' && toolbarFind.padding === '0px', '블록 메뉴의 거름 칸 규칙이 도구 줄 찾기 칸의 높이·여백을 바꾸지 않음', toolbarFind);

  /* ② 블록 폼 (결정 4 C) — 쓴 블록만 · 안 쓴 블록은 칩 · 머리의 개수와 요약 */
  await page.screenshot({ path: path.join(output, '시대-폼-1920-1배.png') });
  await toDesc();
  await page.waitForTimeout(80);
  await page.locator('#editPane').screenshot({ path: path.join(output, '시대-폼-블록-편집-창.png') });
  let bs = await blocks();
  const shown = bs.filter(b => !b.hidden).map(b => b.id);
  check(JSON.stringify(shown) === JSON.stringify(['leaders', 'eras', 'capitals', 'wiki']), '쓴 블록만 보임: 지도자 · 연호 · 도읍 · 문서 (블록 차례는 프로그램이 정함)', bs);
  check(JSON.stringify(await chips()) === JSON.stringify(['소속·예속', '승계', '지위 변천', '내각', '남북 위치', '시기 구분', '연대 · 실재성']), '안 쓴 블록은 칩으로 모두 늘어놓음 (남북 위치도 이름 있는 칩 · 명칭 목록은 이름 칸 아래)', await chips());
  const northBlock = await page.evaluate(() => { const b = document.querySelector('#editorForm details[data-blk="northSouth"]'); return b && { group: b.dataset.group, independent: !b.parentElement.closest('details[data-adv="cells"]'), inputCount: b.querySelectorAll('[name="northSouth"]').length }; });
  check(northBlock && northBlock.group === '규격' && northBlock.independent && northBlock.inputCount === 1, '남북 위치는 빈 칸 묶음과 독립한 규격 블록 하나 (D4 독립 구역과 D3 칩 연결)', northBlock);
  const L4 = bs.find(b => b.id === 'leaders');
  check(L4.n === '4' && L4.open && /^솔빛 520–548 → 한별 611–640$/.test(L4.sum), '블록 머리: 이름 · 개수 4 · 한 줄 요약(넷 넘으면 처음 → 끝) · 처음엔 펼침', L4);
  check(bs.find(b => b.id === 'wiki').sum === '개요 · 바닷길 · 도읍' && bs.find(b => b.id === 'wiki').n === '3', '문서 블록 머리: 제목 셋', bs.find(b => b.id === 'wiki'));
  check(await page.evaluate(() => !!document.querySelector('#editorForm details[data-adv="cells"] [data-cells="leaders"]')), "'승계 · 지위 · 지도자 …' 구역(details[data-adv=cells])은 블록 여섯을 담는 그릇으로 남음 — 구역을 찾던 길 그대로");
  /* 폼의 읽기 = 파일: 열어서 그대로 저장하면 작업본이 한 글자도 바뀌지 않음 (블록은 감싸는 꼴만) */
  {
    const canon = v => (Array.isArray(v) ? v.map(canon) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, canon(v[k])])) : v); // 칸 차례는 따지지 않음
    const before = JSON.stringify(canon((await raw()).periods));
    await page.evaluate(() => HT.viewer.saveEditor());
    await page.waitForTimeout(150);
    const after = JSON.stringify(canon((await raw()).periods));
    check(after === before, '블록 폼을 열어 그대로 저장해도 작업본 그대로 (사람 · 승계 · 이름 칸 — 형식 3 — 포함)', after === before ? undefined : { before, after });
  }

  /* ③ 손잡이 (결정 1 B) — 늘 보임 · 줄 안 첫 줄 맨 앞 · 지도자 줄 높이 그대로 */
  {
    const g = await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-cells="leaders"] > .cell-row')].map(r => {
      const h = r.firstElementChild, a = r.querySelector(':scope > .c-ordinal');
      const cs = getComputedStyle(h);
      return { first: h.classList.contains('mk-grip'), text: h.textContent, op: cs.opacity, vis: cs.visibility, sameLine: Math.abs(h.getBoundingClientRect().top - a.getBoundingClientRect().top) < 2, left: h.getBoundingClientRect().left < a.getBoundingClientRect().left, height: Math.round(r.getBoundingClientRect().height) };
    }));
    check(g.every(x => x.first && x.text === '⋮⋮' && x.op === '1' && x.vis === 'visible' && x.sameLine && x.left), '손잡이 ⋮⋮: 줄마다 첫 자식 · 늘 보임 · 첫 줄 맨 앞(대수 칸 앞, 같은 줄)', g);
    const withoutGrip = await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-cells="leaders"] > .cell-row')].map(r => {
      const copy = r.cloneNode(true);
      copy.querySelector(':scope > .mk-grip').remove();
      r.parentElement.appendChild(copy);
      const height = Math.round(copy.getBoundingClientRect().height);
      copy.remove();
      return height;
    }));
    check(g.every((x, i) => x.height === 154 && x.height === withoutGrip[i]), 'B안 지도자 줄은 손잡이 유무와 관계없이 154px · 네 줄 유지(줄 끝 단추 높이 32px)', { withGrip: g.map(x => x.height), withoutGrip });
    check(await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-cells="capitals"] > .cell-row, #editorForm [data-cells="eras"] > .cell-row')].every(r => r.firstElementChild.classList.contains('mk-grip'))), '연호 · 도읍 줄에도 손잡이');
    const tree = await page.evaluate(() => [...document.querySelectorAll('#mkTree .mk-trow > .mk-handle')].map(h => getComputedStyle(h).opacity));
    check(tree.length > 0 && tree.every(o => o === '1'), '구조 나무 줄의 손잡이도 늘 보임 (메이커 안 끌기 한 꼴)', tree);
  }

  /* ④ 블록 메뉴 (결정 2 A) */
  await toDesc();
  await grip(1).click();
  await page.waitForTimeout(120);
  check((await menuText()).startsWith('지도자 줄 — 2 · 가람') && JSON.stringify(await menuItems()) === JSON.stringify(['복제', '위로 옮기기', '아래로 옮기기', '다른 나라로 옮기기…', '내각 줄로 바꾸기', '연호 줄로 복사', '틀로 저장…', '지우기']), "손잡이를 누르면 세로 메뉴: 제목 · 복제 · 위로 · 아래로 · 다른 나라로 옮기기… · 종류 바꾸기 · 틀로 저장…(결정 6 — js/maker-templates.js가 extras.menu에 더함) · 지우기", await menuText());
  check(/Shift\+손잡이 = 여러 줄 함께 고르기 · 둘을 고르면 맞바꾸기/.test(await menuText()) && (await page.locator('.mk-bmenu .ctx-key').allTextContents()).join('|') === 'Ctrl+D|Alt+↑|Alt+↓|Ctrl+Shift+Del', '메뉴의 단축키(입력 칸 길잡이와 같음) · 바닥 글', await page.locator('.mk-bmenu .ctx-key').allTextContents());
  const menuLook = await page.evaluate(() => {
    const el = document.querySelector('.mk-bmenu');
    const style = node => { const cs = getComputedStyle(node); return { blur: cs.backdropFilter, shadow: cs.boxShadow, border: cs.borderTopWidth, radius: cs.borderTopLeftRadius, background: cs.backgroundColor }; };
    return { menu: style(el), context: style(document.querySelector('#ctxMenu')), sameClass: el.classList.contains('ctx-menu') };
  });
  check(menuLook.sameClass && menuLook.menu.blur === 'none' && JSON.stringify(menuLook.menu) === JSON.stringify(menuLook.context), '메뉴 꼴은 B안 오른쪽 누름 메뉴와 같음(흐림 없음 · 같은 바탕과 선)', menuLook);
  await page.screenshot({ path: path.join(output, '블록-메뉴-1920-1배.png') });
  await page.keyboard.press('Escape');
  check(!(await menuText()) && await page.evaluate(() => !document.querySelector('#editPane').hidden && document.activeElement.classList.contains('mk-grip')), 'Esc: 메뉴만 닫히고 초점은 손잡이로 (편집 창 그대로)');
  await grip(1).click();
  await pick('복제');
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '가람', '가람', '누리', '한별']), '복제: 바로 아래에 같은 값의 줄', await names());
  await grip(2).click();
  await pick('지우기');
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '가람', '누리', '한별']), '지우기: 그 줄의 ✕와 같은 길', await names());
  await grip(2).click();
  await pick('위로 옮기기');
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '누리', '가람', '한별']) && await page.evaluate(() => HT.viewer.state.editSnap !== JSON.stringify(HT.FORMS.period.read(document.querySelector('#editorForm')).item)), '위로 옮기기 → 저장하지 않은 고침', await names());
  await grip(0).click();
  check((await page.locator('.mk-bmenu .ctx-item', { hasText: '위로 옮기기' }).getAttribute('class')).includes('is-disabled'), '맨 위 줄의 위로 옮기기는 흐림');
  await page.keyboard.press('Escape');
  await reset();
  /* 종류 바꾸기 — 가람(대수 · 묘호 · 사람 · 승계 · 이름) → 내각: 표의 칸만 옮기고 나머지는 버림 */
  await grip(1).click();
  await pick('내각 줄로 바꾸기');
  let r = await read();
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '누리', '한별']) && JSON.stringify(await names('cabinets')) === JSON.stringify(['가람']), '내각 줄로 바꾸기: 지도자에서 빠지고 내각 블록이 드러나 그 줄', { L: await names(), C: await names('cabinets') });
  const cab = r.cabinets && r.cabinets[0];
  check(cab && cab.start === 548 && cab.end === 575 && cab.person === '가온' && Array.isArray(cab.names) && !('ordinal' in cab) && !('temple' in cab) && !('accession' in cab), '옮긴 칸: 대표 이름 · 기간 · 사람 · 이름(원어 등) — 대수 · 묘호 · 승계는 버림', cab);
  check(!(await blocks()).find(b => b.id === 'cabinets').hidden && !(await chips()).includes('내각'), '내각 블록이 드러나고 칩에서 빠짐');
  await grip(0).click();
  await pick('연호 줄로 복사');
  r = await read();
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '누리', '한별']) && r.eras.length === 3 && r.eras.some(e => e.name === '솔빛' && e.start === 520 && e.end === 548 && !('ordinal' in e)), '연호 줄로 복사: 지도자 줄은 그대로 · 연호에 이름 · 기간만', r.eras);
  await reset();
  /* 여러 줄 고르기 · 맞바꾸기 */
  await grip(1).click({ modifiers: ['Shift'] });
  await grip(2).click({ modifiers: ['Shift'] });
  check(await page.locator(`${LR}.is-picked`).count() === 2 && !(await menuText()), 'Shift+손잡이: 메뉴 없이 여러 줄 고르기 (고른 줄 칠)');
  await grip(2).click();
  await page.waitForTimeout(100);
  check((await menuText()).startsWith('지도자 줄 2개 고름 — 가람 · 누리') && JSON.stringify(await menuItems()) === JSON.stringify(['두 줄 맞바꾸기 (기간은 그대로)', '기간만 맞바꾸기', '복제', '다른 나라로 옮기기…', '틀로 저장…', '지우기']), '두 줄을 고른 메뉴: 맞바꾸기 둘 · 복제 · 다른 나라로 · 틀로 저장… · 지우기', await menuText());
  await page.screenshot({ path: path.join(output, '두-줄-맞바꾸기-메뉴-1920-1배.png') });
  await pick('기간만 맞바꾸기');
  r = await read();
  const span = n => { const c = r.leaders.find(x => x.name === n); return c && `${c.start}-${c.end}`; };
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '가람', '누리', '한별']) && span('가람') === '575-611' && span('누리') === '548-575' && r.leaders.find(x => x.name === '가람').temple === '물마루', '기간만 맞바꾸기: 줄은 제자리 · 시작 · 끝만 서로', r.leaders);
  await reset();
  await grip(1).click({ modifiers: ['Shift'] });
  await grip(2).click({ modifiers: ['Shift'] });
  await grip(1).click();
  await pick('두 줄 맞바꾸기 (기간은 그대로)');
  r = await read();
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '누리', '가람', '한별']) && span('누리') === '548-575' && span('가람') === '575-611' && (await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-cells="leaders"] > .cell-row > .c-start')].map(x => x.value).join(','))) === '520,548,575,611', '두 줄 맞바꾸기(기간은 그대로): 자리의 기간은 그대로 · 나머지 칸이 서로', r.leaders);
  await page.keyboard.press('Escape');
  check(await page.locator(`${LR}.is-picked`).count() === 0 && await page.evaluate(() => !document.querySelector('#editPane').hidden), 'Esc: 고른 줄을 풂 (편집 창은 그대로)');
  await reset();

  /* ⑤ 끌기 (결정 3 C — 빈 자리 + 빈 자리 안 미리 글) */
  const slotNow = () => page.evaluate(() => {
    const s = document.querySelector('#editorForm .mk-slot:not(.is-closing)');
    const g = document.querySelector('.mk-dnd-ghost');
    return { slot: !!s, text: s ? s.querySelector('.mk-slot-pre span').textContent : '', chip: s ? s.querySelector('.mk-dnd-chip').textContent : '', h: s ? Math.round(s.getBoundingClientRect().height) : 0, why: g && !g.hidden ? (g.querySelector('.mk-dnd-why') || {}).textContent : '', ring: !!document.querySelector('#editorForm .is-drop-into'), lifted: document.querySelectorAll('#editorForm .cell-row.is-dragging').length };
  });
  /** 손잡이 i를 끌어 to(선택자)의 위쪽 · 가운데로 — 지나가며 열리고 닫히는 빈 자리 때문에 움직임이 끝난 뒤 다시 재어 그 위로 */
  async function dragGrip(i, to, { at = 'top', shot = '', drop = true, esc = false } = {}) {
    await toDesc();
    const g = await grip(i).boundingBox();
    await page.mouse.move(g.x + g.width / 2, g.y + g.height / 2);
    await page.mouse.down();
    await page.mouse.move(g.x + 4, g.y + 12, { steps: 3 });
    await page.waitForTimeout(450);
    for (let k = 0; k < 3; k++) {
      const el = page.locator(to).first();
      await el.evaluate(e => e.scrollIntoView({ block: 'center' }));
      const b = await el.boundingBox();
      await page.mouse.move(b.x + Math.min(120, b.width / 2), at === 'top' ? b.y + 6 : b.y + b.height / 2, { steps: k ? 2 : 10 });
      await page.waitForTimeout(450);
    }
    const seen = await slotNow();
    if (shot) await page.screenshot({ path: path.join(output, shot) });
    if (esc) await page.keyboard.press('Escape');
    if (drop || esc) await page.mouse.up();
    await page.waitForTimeout(150);
    return seen;
  }
  const rowOf = name => `${LR}:has(> .c-name[value="${name}"])`; // 처음 채운 값(속성)으로 — 빈 자리가 끼어도 같은 줄
  let seen = await dragGrip(2, rowOf('가람'), { shot: '끌기-같은-목록-1920-1배.png' });
  check(seen.slot && seen.lifted === 1 && seen.text === '저장하면 시작 순(575)으로 돌아갑니다 — 차례는 시작이 같거나 미정인 줄끼리만 남습니다' && /누리\s*575–611\s*지도자/.test(seen.chip) && seen.h >= 152 && !seen.ring, '같은 목록: 끄는 줄은 접혀 빠지고 놓을 자리에 같은 높이의 빈 자리 · 그 안에 손 밑 사본 · 미리 글', seen);
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '누리', '가람', '한별']), '놓으면 그 자리로 (저장하지 않은 고침)', await names());
  await reset();
  seen = await dragGrip(1, `${F} [data-blk-chip="cabinets"]`, { at: 'mid', shot: '끌기-종류-바꾸기-1920-1배.png' });
  check(seen.slot && seen.ring && seen.text === '놓으면 내각 줄로 바뀝니다 — 대표 이름 · 기간 · 사람 · 이름(원어 등)만 옮기고, 대수 · 묘호 · 승계는 버립니다 · Ctrl을 누른 채 놓으면 복사', '다른 목록(안 쓴 내각 블록의 칩): 받는 블록 테두리 · 빈 자리 안 미리 글(버리는 칸은 그 줄에 적힌 것만)', seen);
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '누리', '한별']) && JSON.stringify(await names('cabinets')) === JSON.stringify(['가람']), '놓으면 내각 줄로 바뀜 (내각 블록이 드러남)', { L: await names(), C: await names('cabinets') });
  await reset();
  seen = await dragGrip(0, `${F} [data-cells="capitals"] > .cell-row`, { at: 'mid' });
  check(!seen.slot && seen.why === '놓을 수 없음 — 지도자 줄은 도읍 줄로 바꿀 수 없음', '놓을 수 없는 곳: 빈 자리 없이 손 밑 사본 아래에 까닭 글만', seen);
  check(JSON.stringify(await names()) === JSON.stringify(['솔빛', '가람', '누리', '한별']) && (await names('capitals')).length === 2, '놓을 수 없는 곳에 놓으면 아무것도 바뀌지 않음');
  seen = await dragGrip(3, rowOf('솔빛'), { drop: false, esc: true });
  check(seen.slot && JSON.stringify(await names()) === JSON.stringify(['솔빛', '가람', '누리', '한별']) && await page.evaluate(() => !document.querySelector('.mk-slot') && !document.querySelector('#editorForm .is-dragging')), 'Esc: 끌기를 그만두면 그대로 (빈 자리 · 접힌 줄 모두 되돌림)');

  /* ⑥ 다른 나라로 옮기기… — 작업본 고침 한 번 · 칸 문서도 따라감 · 되돌리기 한 걸음 */
  await reset();
  let h0 = await steps();
  await grip(1).click();
  await pick('다른 나라로 옮기기');
  const pk = await menuText();
  check(/어느 나라로 — 가람 548–575/.test(pk) && /이 DLC/.test(pk) && /가온국/.test(pk) && /나래국[\s\S]*기간 밖/.test(pk) && /불러온 팩 — 잠김을 푼 것 \(덮어쓰기로\)[\s\S]*바람국/.test(pk) && !/해온국/.test(pk), '나라 고르기: 이 DLC의 나라 · 잠김을 푼 불러온 팩의 나라 · 기간 밖은 표시 · 지금 나라는 없음', pk);
  await page.screenshot({ path: path.join(output, '다른-나라로-1920-1배.png') });
  await page.keyboard.type('가온');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(400);
  let d = await raw();
  const haeon = () => d.periods.find(p => p.id === 'haeon');
  const gaon = () => d.periods.find(p => p.id === 'gaon');
  check(JSON.stringify(haeon().leaders.map(x => x.name)) === JSON.stringify(['솔빛', '누리', '한별']) && gaon().leaders.some(x => x.name === '가람' && x.temple === '물마루' && x.person === '가온'), '옮기기: 해온국에서 빠지고 가온국에 그 줄 그대로(저장돼 있던 칸 모두)', [haeon().leaders, gaon().leaders]);
  check(!('cell:haeon:leaders:가람@548' in d.documents) && d.documents['cell:gaon:leaders:가람@548'] === '가람의 칸 문서', '칸 문서(cell:…)도 그 나라로 따라감', Object.keys(d.documents));
  check((await steps()) === h0 + 1, '작업본 고침 한 번 = 되돌리기 한 걸음');
  check(await page.evaluate(() => HT.viewer.state.editing === 'blocks-check/haeon' && !document.querySelector('#editPane').hidden), '편집 창은 원래 나라(해온국) 그대로 — 옮긴 줄이 빠진 새 값으로');
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  await page.keyboard.press('Control+z');
  await page.waitForTimeout(300);
  d = await raw();
  check(haeon().leaders.length === 4 && gaon().leaders.length === 2 && d.documents['cell:haeon:leaders:가람@548'] === '가람의 칸 문서', '되돌리기 한 번에 두 나라 · 칸 문서가 모두 돌아옴');
  /* 남의 나라(잠김을 푼 불러온 팩) — 덮어쓰기로 · Ctrl = 복사 */
  await open(`${OWN}/haeon`);
  await grip(0).click();
  await pick('다른 나라로 옮기기');
  await page.keyboard.type('바람');
  await page.keyboard.down('Control');
  await page.keyboard.press('Enter');
  await page.keyboard.up('Control');
  await page.waitForTimeout(400);
  d = await raw();
  const patch = d.patches.find(p => p.target === `${NEAR}/baram`);
  check(haeon().leaders.length === 4 && patch && patch.set && patch.set.leaders.some(x => x.name === '솔빛') && !d.periods.some(p => p.name === '바람국'), 'Ctrl = 복사 · 남의 나라는 바뀐 칸만 덮어쓰기(patches)로', patch);
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  await page.keyboard.press('Control+z');
  await page.waitForTimeout(300);
  check(!(await raw()).patches.some(p => p.target === `${NEAR}/baram`), '되돌리기 한 번에 덮어쓰기가 사라짐');
  /* 새 항목(아직 저장 전)은 옮길 수 없음 — 까닭 알림 */
  await open(`${OWN}/haeon`);

  /* ⑦ '/' 명령 (결정 5 A) */
  await toDesc();
  await grip(0).focus();
  await page.keyboard.press('/');
  await page.waitForTimeout(120);
  const sl = await menuText();
  check(/칸 묶음[\s\S]*지도자[\s\S]*있음 · 줄 더하기[\s\S]*내각[\s\S]*관계[\s\S]*소속·예속[\s\S]*승계[\s\S]*이름 · 글[\s\S]*이름\(원어 등\)[\s\S]*연대 · 실재성[\s\S]*문서/.test(sl) && /지도자 한 사람의 승계 관계 · 부모 · 배우자는 그 줄 끝 '사람' 단추에/.test(sl), "손잡이에서 '/': 작은 펼침 목록(칸 묶음 · 관계 · 이름 · 글 — 있는 블록은 '있음 · 줄 더하기')", sl);
  check(await page.evaluate(() => document.activeElement.matches('.mk-bmenu .mk-find input') && !document.querySelector('#mkPalette:not([hidden]), .mk-find-dlg[open]')), "'/'는 작업실 명령 찾기 대신 블록 목록 (거름 칸에 초점)");
  await page.screenshot({ path: path.join(output, '슬래시-목록-1920-1배.png') });
  await page.keyboard.type('ㄴ');
  await page.waitForTimeout(80);
  check(JSON.stringify(await menuItems()) === JSON.stringify(['내각', '남북 위치']), "거름(초성도): 'ㄴ' → 내각 · 남북 위치", await menuItems());
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  check((await names('cabinets')).length === 1 && await page.evaluate(() => !!document.activeElement.closest('[data-cells="cabinets"] > .cell-row')) && !(await blocks()).find(b => b.id === 'cabinets').hidden, "Enter: 없던 블록이면 새 블록(줄 하나 · 그 줄에 초점)");
  await page.keyboard.type('/가');
  check((await page.evaluate(() => document.activeElement.value)) === '/가' && !(await menuText()), "글 칸 안의 '/'는 그대로 글자");
  await grip(0).focus();
  const composing = await page.evaluate(() => {
    const ev = new KeyboardEvent('keydown', { key: '/', isComposing: true, bubbles: true, cancelable: true });
    document.activeElement.dispatchEvent(ev);
    return !document.querySelector('.mk-bmenu') || document.querySelector('.mk-bmenu').hidden;
  });
  check(composing, "한글 조합 중의 '/'는 목록을 열지 않음");
  await reset();

  /* ⑧ 칩 · 블록 머리 ＋ · 접어 둔 블록 기억 */
  await page.locator(`${F} [data-blk-chip="succ"]`).click();
  await page.waitForTimeout(120);
  check(await page.evaluate(() => !!document.activeElement.closest('[data-succ] > .succ-row') && document.activeElement.classList.contains('s-from')) && !(await chips()).includes('승계'), "'＋ 승계' 칩: 블록이 생기고 줄 하나 · 그 줄의 첫 칸에 초점");
  check(await page.evaluate(() => document.querySelector('#editorForm [data-succ] > .succ-row > .mk-grip') !== null), '새로 더한 줄에도 손잡이');
  await page.locator(`${F} details[data-blk="leaders"] > summary [data-blk-add]`).click();
  await page.waitForTimeout(100);
  check((await names()).length === 5 && await page.evaluate(() => !!document.activeElement.closest('[data-cells="leaders"] > .cell-row:last-child')), '블록 머리 ＋: 그 목록에 줄 하나', await names());
  await reset();
  await page.locator(`${F} details[data-blk="leaders"] > summary`).click();
  await page.waitForTimeout(80);
  check(await page.evaluate(() => !document.querySelector('#editorForm details[data-blk="leaders"]').open && JSON.parse(localStorage.getItem('ht.maker.blocks')).closed.includes('leaders')), '블록 머리를 눌러 접으면 작업실 설정(ht.maker.blocks)에 기억');
  bs = await blocks();
  check(bs.find(b => b.id === 'leaders').sum === '솔빛 520–548 → 한별 611–640', '접은 블록 머리에 한 줄 요약', bs.find(b => b.id === 'leaders'));
  await page.locator('#editPane').screenshot({ path: path.join(output, '지도자-블록-접음-편집-창.png') });
  await open(`${OWN}/gaon`);
  check(await page.evaluate(() => !document.querySelector('#editorForm details[data-blk="leaders"]').open), '다른 나라를 열어도 접어 둔 블록은 접힌 채');
  await page.locator(`${F} details[data-blk="leaders"] > summary`).click();
  await page.waitForTimeout(80);
  check(await page.evaluate(() => document.querySelector('#editorForm details[data-blk="leaders"]').open && !JSON.parse(localStorage.getItem('ht.maker.blocks')).closed.includes('leaders')), '다시 펼치면 기억에서 빠짐');

  /* ⑨ 다른 폼도 블록 · 새 항목 */
  await page.evaluate(() => HT.viewer.openEditor(null, 'period'));
  await page.waitForTimeout(200);
  bs = await blocks();
  check(bs.every(b => b.hidden) && (await chips()).length === 11, '새 나라: 블록은 모두 칩(남북 위치 포함 · 쓴 것이 없음)', await chips());
  await page.locator(`${F} [data-blk-chip="northSouth"]`).click();
  await page.locator(`${F} [name="northSouth"]`).fill('0');
  check((await read()).northSouth === 0 && await page.locator(`${F} [name="northSouth"]`).isVisible(), '남북 위치 칩을 열어 0을 적으면 폼이 수 0을 읽음(빈칸과 구별)');
  await page.screenshot({ path: path.join(output, '남북-위치-블록-1920-1배.png') });
  await page.locator(`${F} [name="northSouth"]`).fill('');
  const reset2 = page.evaluate(() => HT.viewer.closeEditor());
  await reset2;
  await open(`${OWN}/e1`);
  check(JSON.stringify(await chips()) === JSON.stringify(['묶기', '연대', '나라마다 다른 이름', '조약 규격', '주제 · 법 · 선거', '문서']), '사건 폼: 접는 구역이 블록 · 안 쓴 것은 칩', await chips());
  await page.locator(`${F} [data-blk-chip="treaty"]`).click();
  await page.waitForTimeout(150);
  check(await page.evaluate(() => /체결/.test(document.querySelector('#editorForm').textContent) && document.querySelector('#editorForm details[data-adv="treaty"]').open), "'＋ 조약 규격' 칩 = 예전에 조약 구역을 펼친 것과 같음(시작 · 끝 이름표가 체결 · 실효로)");
  await page.evaluate(() => { const body = document.querySelector('#editorForm .ep-body'); body.scrollTop = body.scrollHeight; });
  await page.locator('#editPane').screenshot({ path: path.join(output, '사건-폼-블록-편집-창.png') });
  await reset(`${OWN}/f1`);
  check(JSON.stringify(await chips()) === JSON.stringify(['가족', '연대', '문서']), '인물 폼: 가족 · 연대 · 문서가 블록', await chips());
  await page.evaluate(() => HT.viewer.closeEditor());
  await context.close();
  check(report.오류.length === 0, '브라우저 오류 없음', report.오류);
} finally {
  fs.writeFileSync(path.join(output, 'maker-blocks-check.json'), JSON.stringify(report, null, 2));
  await browser.close();
  server.close();
}
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류 }));
