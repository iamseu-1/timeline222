/* 메이커의 함께 만드는 틀(10건 D3 결정 6 A — js/maker-templates.js)과 작업 폴더(결정 7 A — js/maker-shell.js)를 실제 브라우저 · 실제 포인터로 검사합니다.
   node scripts/maker-templates-check.mjs <검사할 폴더> <결과 폴더>
   가상 작업본(나라 셋 — 해온국 · 가온국 · 나래국, 지도자 솔빛 · 가람 · 누리 · 한별 …)과 잠김을 푼 가상 이웃 팩 하나를 독립 브라우저의 저장소에만 넣고 봅니다:
   ① 읽는 곳 · 포장 목록  ② '＋ 더' 메뉴 — 연표의 '항목 추가' 줄 그대로 + '틀로 만들기' 갈래 · 넣기 메뉴 · 명령 찾기
   ③ 빈칸 채우기 창 — 고치는 나라가 기본 · 같은 해 한 번 · 미리 보는 '만들어질 것' · 전임자 잇기 · 만들기 = 되돌리기 한 걸음 · 만든 칸의 꼴 · 형식 버전 그대로
   ④ 비운 칸 — 비워도 되는 칸은 그 줄을 건너뜀 · 적어야 하는 칸은 문제 글 · 불러온 팩(잠김을 푼 것)의 나라는 덮어쓰기로
   ⑤ 편집 창의 '/' 목록 · 블록 메뉴 '틀로 저장…'  ⑥ 틀 관리 창 — 새 틀 · 묻는 칸 · 만드는 것 · 칸 이름 바꾸면 {이름}도 · 검사 · 저장(작업실 설정) · 지우기 · 되살리기
   ⑦ 작업 폴더 — 나무 맨 위 갈래(어느 보기 갈래에서든) · ＋ 새 폴더 · 끌어 넣기(빈 자리 + 미리 글) · 새 폴더로 놓기 · 폴더에서 폴더로(옮김 · Ctrl은 남김) · '폴더에 넣기…' ·
     폴더 메뉴(이름 · 색 · 모두 고르기 · 지우기) · F2 · Alt+↑↓ · 찾기 · 작업본은 그대로(되돌리기 없음)
   ⑧ 집합 보기로 내보내기 — views 항목 하나 · 나라만 · 모델이 구성 나라를 찾음 · 되돌리기 한 걸음  ⑨ DLC 파일에 틀 · 폴더 열쇠가 없음  ⑩ 1배 그림(1920×1080 · 100%).
   Playwright는 HT_PLAYWRIGHT_ROOT(그 package.json) · 브라우저는 HT_BROWSER(기본 msedge)로 — 다른 메이커 검사와 같게 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/메이커-틀-폴더');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  if (!ok) fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};

/* ① 읽는 곳 · 포장 목록: 메이커만 읽고(viewer 앞), 서비스 워커가 담고, 연표 포장에서는 빠짐 */
const text = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const scripts = html => [...html.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<script\b[^>]*\ssrc="([^"]+)"/g)].map(m => m[1]);
{
  const maker = scripts(text('dlc-maker.html'));
  const at = maker.indexOf('js/maker-templates.js');
  check(at >= 0 && maker.indexOf('js/maker.js') < at && maker.indexOf('js/viewer.js') > at, 'dlc-maker.html이 js/maker-templates.js를 maker.js 뒤 · viewer.js 앞에 읽음', { 차례: at });
  check(!scripts(text('index.html')).includes('js/maker-templates.js'), '보기 전용 index.html은 js/maker-templates.js를 읽지 않음');
  check(text('sw.js').includes("'js/maker-templates.js'"), 'sw.js PRECACHE에 js/maker-templates.js');
  check(/const MAKER_ONLY = \[[^\]]*'js\/maker-templates\.js'/.test(text('scripts/build-web.mjs')), 'build-web.mjs의 MAKER_ONLY에 js/maker-templates.js (연표 포장에서 빠짐)');
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
const OWN = 'tpl-check';
const NEAR = 'tpl-neighbor';
const L = (name, start, end, more = {}) => Object.assign({ name, start }, end == null ? {} : { end }, more);
const draft = {
  format: 'history-timeline-dlc', formatVersion: 2, id: OWN, name: '가상 틀 검사', version: '1.0.0', author: '', description: '',
  tracks: [{ id: 'sea', name: '바다 땅', order: 10 }],
  categories: [],
  peoples: [{ id: 'p-wind', name: '바람겨레' }],
  periods: [
    {
      id: 'haeon', track: 'sea', name: '해온국', start: 520, end: 700, people: '바람겨레', description: '확인용 가상 나라 — 고증 아님',
      leaders: [L('솔빛', 520, 548), L('가람', 548, 575), L('누리', 575, 611), L('한별', 611)],
      eras: [['새벽', 548, 560], ['물결', 560]],
      capitals: [{ city: '달내', start: 520 }],
    },
    { id: 'gaon', track: 'sea', name: '가온국', start: 540, end: 700, people: '바람겨레', leaders: [L('마루', 540, 586), L('여울', 586, 630)] },
    { id: 'narae', track: 'sea', name: '나래국', start: 600, end: 690 },
  ],
  events: [{ id: 'e1', track: 'sea', title: '봄맞이 잔치', start: 560, polity: '해온국' }],
  figures: [{ id: 'f1', track: 'sea', name: '가온', birth: 530, death: 590 }],
  documents: {},
  epochs: [], organs: [], cultures: [], dynasties: [], patches: [], rankDefs: [], requires: [], scopes: [],
};
const near = {
  format: 'history-timeline-dlc', formatVersion: 2, id: NEAR, name: '확인용 이웃 팩', version: '1.0.0',
  tracks: [{ id: 'sea', name: '바다 땅' }], peoples: [],
  periods: [{ id: 'baram', track: 'sea', name: '바람국', start: 500, end: 620, leaders: [L('물빛', 500)] }],
  events: [],
};

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
  await context.addInitScript(({ draft, near, OWN, NEAR }) => {
    if (sessionStorage.getItem('tpl-seeded')) return;
    sessionStorage.setItem('tpl-seeded', '1');
    localStorage.clear();
    localStorage.setItem('ht.packs.installed', JSON.stringify([near]));
    localStorage.setItem('ht.maker.draft', JSON.stringify(draft));
    localStorage.setItem('ht.maker.refs', JSON.stringify({ [OWN]: [{ id: NEAR, show: true, locked: false }] }));
    localStorage.setItem('ht.maker.ui', JSON.stringify({ tree: { figures: true } })); // 구조 나무의 인물 묶음을 펼친 채 (폴더에 인물 줄 넣기)
  }, { draft, near, OWN, NEAR });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => m.type() === 'error' && report.오류.push(m.text()));
  page.on('dialog', d => d.dismiss().catch(() => {}));
  page.setDefaultTimeout(20000);
  await page.goto('http://127.0.0.1:' + server.address().port + '/dlc-maker.html');
  await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden && HT.makerTemplates && HT.makerBlocks);
  await page.waitForTimeout(300);
  const raw = () => page.evaluate(() => JSON.parse(JSON.stringify(__maker.draft)));
  const steps = () => page.evaluate(() => __maker.history.index);
  const store = key => page.evaluate(k => JSON.parse(localStorage.getItem(k) || 'null'), key);
  const open = async uid => {
    await page.evaluate(u => HT.viewer.openEditor(u), uid);
    await page.waitForFunction(() => !document.querySelector('#editPane').hidden);
    await page.waitForTimeout(150);
  };
  const ctxMenu = () => page.evaluate(() => { const m = document.querySelector('#ctxMenu'); return m && !m.hidden ? [...m.children].map(c => (c.classList.contains('ctx-title') ? `# ${c.textContent}` : c.classList.contains('ctx-sep') ? '—' : (c.querySelector('.ctx-label') || c).textContent)) : []; });
  const clickCtx = async label => { await page.locator('#ctxMenu .ctx-item', { hasText: label }).first().click(); await page.waitForTimeout(150); };
  const fill = '#mkTplFill';
  const made = () => page.evaluate(() => [...document.querySelectorAll('#mkTplFill [data-made] li')].map(li => li.innerText.replace(/\s+/g, ' ').trim()));
  const undo = async () => {
    await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(250);
  };

  /* ② '＋ 더' 메뉴 — 연표의 '항목 추가' 줄 그대로 + '틀로 만들기' 갈래 (+ 넣기 메뉴 · 명령 찾기) */
  await open(`${OWN}/haeon`);
  await page.locator('#addPeriodBtn').click();
  await page.waitForTimeout(150);
  let menu = await ctxMenu();
  const addLabels = await page.evaluate(() => (HT.viewer ? true : false) && ['event'].concat(Object.keys(HT.FORMS).filter(k => k !== 'event')).filter(k => HT.FORMS[k] && HT.FORMS[k].add !== false).map(k => HT.FORMS[k].addLabel || `＋ ${HT.FORMS[k].word} 추가`));
  const tIdx = menu.indexOf('# 틀로 만들기');
  check(menu[0] === '# 항목 추가' && JSON.stringify(menu.slice(1, 1 + addLabels.length)) === JSON.stringify(addLabels), "'＋ 더' 메뉴의 '항목 추가' 줄은 연표의 메뉴와 같은 글 · 같은 차례", menu);
  check(tIdx > addLabels.length && menu.slice(tIdx + 1).join('|') === '새 지도자 — 지도자 줄 + 연호 줄 + 승계 사건|천도 — 도읍 줄 + 천도 사건|개원 — 연호 줄 + 개원 사건|틀 관리…', "'＋ 더' 메뉴 끝에 '틀로 만들기' 갈래: 기본 틀 셋 · 틀 관리…", menu);
  await page.screenshot({ path: path.join(output, '더-메뉴-틀로-만들기-1920-1배.png') });
  await page.locator('#addPeriodBtn').click(); // 다시 누르면 닫힘 (연표의 단추와 같게)
  await page.waitForTimeout(120);
  check((await ctxMenu()).length === 0, "'＋ 더'를 다시 누르면 메뉴가 닫힘");
  await page.locator('#mkMenus [data-menu="insert"]').click();
  await page.waitForTimeout(150);
  menu = await ctxMenu();
  check(menu.includes('# 틀로 만들기') && menu.includes('새 지도자 — 지도자 줄 + 연호 줄 + 승계 사건') && menu.at(-1) === '틀 관리…', "메뉴 줄 '넣기'에도 같은 틀 목록", menu.slice(-6));
  await page.keyboard.press('Escape');
  await page.keyboard.press('Control+K');
  await page.waitForTimeout(200);
  await page.keyboard.type('틀로');
  await page.waitForTimeout(250);
  const pal = await page.evaluate(() => document.body.innerText.includes('틀로 만들기: 새 지도자 — 지도자 줄 + 연호 줄 + 승계 사건'));
  check(pal, "명령 찾기(Ctrl+K)에 '틀로 만들기: 새 지도자 …'");
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);

  /* ③ 빈칸 채우기 창 — '＋ 더' ▸ 새 지도자 */
  await page.locator('#addPeriodBtn').click();
  await page.waitForTimeout(120);
  await clickCtx('새 지도자 — ');
  await page.waitForSelector(`${fill}[open]`);
  check(await page.locator(`${fill} h2`).innerText() === '틀로 만들기 — 새 지도자', '빈칸 채우기 창 제목');
  check((await page.locator(`${fill} [data-ask="polity"]`).inputValue()) === `${OWN}/haeon`, '나라는 지금 고치는 나라가 기본(해온국)');
  check(await page.evaluate(() => document.activeElement && document.activeElement.dataset.ask === 'year'), '처음 초점은 첫 빈 칸(승계 해)');
  check(await page.evaluate(() => ![...document.querySelectorAll('#mkTplFill input')].some(i => i.placeholder)), '입력 칸에 회색 예시 글(placeholder)이 없음');
  await page.locator(`${fill} [data-ask="year"]`).fill('640');
  await page.locator(`${fill} [data-ask="who"]`).fill('바다솔');
  await page.locator(`${fill} [data-ask="era"]`).fill('밝음');
  await page.waitForTimeout(100);
  let rows = await made();
  check((await page.locator(`${fill} [data-made-n]`).innerText()) === '만들어질 것 3', "'만들어질 것 3'", rows);
  check(/지도자 줄.*해온국 · 바다솔 640–.*전임자 한별의 끝을 640에 맞춰 이음/.test(rows[0]) && /연호 줄.*밝음 640–.*이전 연호 물결의 끝을 640에 맞춰 이음/.test(rows[1]) && /사건 바다솔 승계 640 · 해온국 · 정치/.test(rows[2]), '미리 보는 세 줄 — 같은 해는 한 번 · 전임자 잇기 · 사건 제목은 틀이 지은 글', rows);
  check((await page.locator(`${fill} [data-ev="2"]`).inputValue()) === '바다솔 승계', '사건 제목 칸이 틀이 지은 글을 따라감');
  check((await page.locator(`${fill} [data-open-label]`).innerText()) === '만든 뒤 해온국 편집 창 열기', "'만든 뒤 해온국 편집 창 열기'");
  await page.locator(fill).screenshot({ path: path.join(output, '빈칸-채우기-창.png') });
  await page.screenshot({ path: path.join(output, '빈칸-채우기-창-1920-1배.png') });
  const before = await steps();
  const d0 = await raw();
  await page.locator(`${fill} button[type="submit"]`).click();
  await page.waitForFunction(() => !document.querySelector('#mkTplFill').open);
  await page.waitForTimeout(250);
  let d = await raw();
  const h = d.periods.find(p => p.id === 'haeon');
  check((await steps()) === before + 1, '만들기 = 작업본 고침 한 번(되돌리기 한 걸음)', { before, after: await steps() });
  check(JSON.stringify(h.leaders.at(-1)) === '{"name":"바다솔","start":640}' && h.leaders.at(-2).end === 640, '지도자 줄: 시작 순 자리 · 전임자(한별)의 끝이 640', h.leaders.slice(-2));
  check(JSON.stringify(h.eras) === '[["새벽",548,560],["물결",560,640],{"name":"밝음","start":640}]', '연호 줄: 짧은 꼴 [이름, 시작] 전임 줄은 셋째 칸에 끝 · 새 줄은 편집 창과 같은 꼴', h.eras);
  const ev = d.events.find(e => e.title === '바다솔 승계');
  check(!!ev && ev.start === 640 && ev.track === 'sea' && ev.polity === '해온국' && ev.category === 'politics', '사건: 제목 · 해 · 트랙 · 나라 · 분류(정치)', ev);
  check(await page.evaluate(() => HT.usesFormatV3 ? !HT.usesFormatV3(__maker.draft) : true), '틀이 만든 것은 지금 열쇠뿐 — 형식 버전 3 아님');
  check(!Object.keys(d).some(k => /templ|folder/i.test(k)), 'DLC 작업본에 틀 · 폴더 열쇠가 없음', Object.keys(d));
  check(await page.evaluate(() => __state.editing === 'tpl-check/haeon' && !document.querySelector('#editPane').hidden), '만든 뒤 해온국 편집 창이 열림');
  check(await page.evaluate(() => [...document.querySelectorAll('#editorForm [data-cells="leaders"] > .cell-row > .c-name')].map(i => i.value).includes('바다솔')), '편집 창의 지도자 블록에 새 줄이 보임');
  await undo();
  check(JSON.stringify(await raw()) === JSON.stringify(d0), '되돌리기 한 번에 세 줄 · 전임자 끝까지 모두 돌아옴');
  await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());
  await page.keyboard.press('Control+y');
  await page.waitForTimeout(250);
  check(JSON.stringify(await raw()) === JSON.stringify(d), '다시 하기로 돌아옴');

  /* ④ 비운 칸 · 불러온 팩의 나라 */
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  await page.locator('#addPeriodBtn').click();
  await page.waitForTimeout(120);
  await clickCtx('새 지도자 — ');
  await page.waitForSelector(`${fill}[open]`);
  await page.locator(`${fill} button[type="submit"]`).click();
  await page.waitForTimeout(150);
  let probs = await page.evaluate(() => [...document.querySelectorAll('#mkTplFill [data-fill-problems] li')].map(li => li.textContent));
  check(await page.locator(`${fill}[open]`).count() === 1 && probs.join('|') === '«승계 해»를 적으세요.|«지도자 이름»을 적으세요.', '적어야 하는 칸이 비면 만들지 않고 문제 글(조사도 맞게)', probs);
  check(await page.evaluate(() => document.activeElement.dataset.ask === 'year' && document.activeElement.hasAttribute('aria-invalid')), '첫 문제 칸으로 초점 · 표시');
  await page.locator(`${fill} [data-ask="polity"]`).selectOption(`${NEAR}/baram`);
  await page.locator(`${fill} [data-ask="year"]`).fill('기원전 7');
  await page.locator(`${fill} [data-ask="who"]`).fill('물보라');
  await page.waitForTimeout(100);
  rows = await made();
  check((await page.locator(`${fill} [data-made-n]`).innerText()) === '만들어질 것 2' && /연호 줄 «연호»가 비어 건너뜀/.test(rows[1]), '비워도 되는 칸(연호)이 비면 그 줄은 건너뜀', rows);
  check(/나라 기간\(500–620\) 밖/.test(rows[0]), '나라 기간 밖이면 미리 글에 알림', rows[0]);
  await page.locator(`${fill} [data-ask="year"]`).fill('580');
  await page.locator(`${fill} [data-ev="2"]`).fill('물보라 집권');
  await page.locator(`${fill} [data-ask="who"]`).fill('물보라2');
  await page.waitForTimeout(100);
  check((await page.locator(`${fill} [data-ev="2"]`).inputValue()) === '물보라 집권', '고쳐 적은 사건 제목은 다른 칸을 고쳐도 그대로');
  await page.locator(`${fill} [data-open-after]`).uncheck();
  await page.locator(`${fill} button[type="submit"]`).click();
  await page.waitForFunction(() => !document.querySelector('#mkTplFill').open);
  await page.waitForTimeout(250);
  d = await raw();
  const patch = d.patches.find(p => p.target === `${NEAR}/baram`);
  const pl = patch && patch.set && patch.set.leaders;
  check(!!pl && Object.keys(patch.set).join() === 'leaders' && pl.length === 2 && pl[0].name === '물빛' && pl[0].end === 580 && JSON.stringify(pl[1]) === '{"name":"물보라2","start":580}', '불러온 팩(잠김을 푼 것)의 나라는 바뀐 칸만 덮어쓰기로 (지도자 목록 — 편집 창 · 구조 나무 끌기와 같은 길)', patch);
  const ev2 = d.events.find(e => e.title === '물보라 집권');
  check(!!ev2 && ev2.polity === '바람국' && ev2.track === 'sea', '사건은 그 나라 · 트랙에', ev2);
  check((await store('ht.maker.templates')).openAfter === false, "'만든 뒤 편집 창 열기'를 끈 것은 작업실 설정에 기억");

  /* ⑤ 편집 창의 '/' 목록 · 블록 메뉴 '틀로 저장…' */
  await open(`${OWN}/gaon`);
  await page.locator('#editorForm [data-cells="leaders"] > .cell-row > .mk-grip').first().focus();
  await page.keyboard.press('/');
  await page.waitForTimeout(150);
  const slash = await page.evaluate(() => [...document.querySelectorAll('.mk-bmenu:not([hidden]) .ctx-item .ctx-label')].map(e => e.textContent));
  const slashText = await page.evaluate(() => document.querySelector('.mk-bmenu:not([hidden])').innerText);
  check(['새 지도자', '천도', '개원', '틀 관리…'].every(x => slash.includes(x)) && /\n틀\n새 지도자[\s\S]*천도[\s\S]*개원[\s\S]*틀 관리…/.test(slashText), "편집 창 '/' 목록의 '틀' 무리에 틀 이름 · 틀 관리… (판 d5-a)", slashText);
  await page.keyboard.type('틀');
  await page.waitForTimeout(100);
  const slashTl = await page.evaluate(() => [...document.querySelectorAll('.mk-bmenu:not([hidden]) .ctx-item .ctx-label')].map(e => e.textContent));
  check(JSON.stringify(slashTl) === JSON.stringify(['새 지도자', '천도', '개원', '틀 관리…']), "'/틀'로 거르면 틀 줄만", slashTl);
  await page.keyboard.press('Backspace');
  await page.keyboard.type('천도');
  await page.waitForTimeout(100);
  await page.keyboard.press('Enter');
  await page.waitForSelector(`${fill}[open]`);
  check((await page.locator(`${fill} h2`).innerText()) === '틀로 만들기 — 천도' && (await page.locator(`${fill} [data-ask="polity"]`).inputValue()) === `${OWN}/gaon`, "'/'에서 고른 틀 — 나라는 편집 창의 나라(가온국)", await page.locator(`${fill} h2`).innerText());
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  const grips = page.locator('#editorForm [data-cells="leaders"] > .cell-row > .mk-grip');
  await grips.nth(0).click({ modifiers: ['Shift'] });
  await grips.nth(1).click({ modifiers: ['Shift'] });
  await grips.nth(1).click();
  await page.waitForTimeout(150);
  const bmenu = await page.evaluate(() => [...document.querySelectorAll('.mk-bmenu:not([hidden]) .ctx-item .ctx-label')].map(e => e.textContent));
  check(bmenu.includes('틀로 저장…'), "블록 메뉴(줄 둘 고름)에 '틀로 저장…'", bmenu);
  await page.locator('.mk-bmenu .ctx-item', { hasText: '틀로 저장…' }).click();
  await page.waitForSelector('#mkTplMan[open]');
  const fromRows = await page.evaluate(() => ({ name: document.querySelector('#mkTplMan [data-tm-name]').value, asks: [...document.querySelectorAll('#mkTplMan .mk-tm-ask')].map(e => e.textContent), makes: [...document.querySelectorAll('#mkTplMan [data-mk-text]')].map(i => i.value), msg: document.querySelector('#mkTplMan [data-man-msg]').textContent }));
  check(fromRows.name === '새 틀' && JSON.stringify(fromRows.makes) === '["{지도자 이름}","{지도자 이름 2}"]' && fromRows.asks.join('|') === '나라|해|해 2해|지도자 이름|지도자 이름 2', "'틀로 저장…' — 고른 줄의 꼴로 채운 새 틀(해가 다르면 해 칸 둘)", fromRows);
  await page.locator('#mkTplMan [data-tm-name]').fill('두 지도자');
  await page.locator('#mkTplMan [data-tm-save]').click();
  await page.waitForTimeout(100);
  check((await store('ht.maker.templates')).list.some(t => t.name === '두 지도자' && t.makes.length === 2), "저장하면 작업실 설정(ht.maker.templates)에 — DLC 파일과 무관");

  /* ⑥ 틀 관리 창 */
  await page.locator('#mkTplMan [data-tm-new]').click();
  await page.locator('#mkTplMan [data-tm-name]').fill('새 내각');
  await page.locator('#mkTplMan [data-ask-add]').click();
  await page.locator('#mkTplMan [data-ae-label]').fill('내각 이름');
  await page.locator('#mkTplMan [data-ae-label]').press('Tab');
  await page.waitForTimeout(80);
  await page.locator('#mkTplMan [data-ae-done]').click();
  if (!(await page.locator('#mkTplMan [data-mk-kind]').count())) await page.locator('#mkTplMan [data-mk-add]').click();
  await page.locator('#mkTplMan [data-mk-kind="cabinets"]').click();
  await page.locator('#mkTplMan [data-make-i="0"] [data-ins="내각 이름"]').click();
  await page.locator('#mkTplMan [data-mk-add]').click();
  await page.locator('#mkTplMan [data-mk-kind="event"]').click();
  await page.locator('#mkTplMan [data-make-i="1"] [data-mk-text]').fill('{내각 이름} 출범');
  await page.waitForTimeout(80);
  await page.locator('#mkTplMan .mk-tm-ask', { hasText: '내각 이름' }).click();
  await page.locator('#mkTplMan [data-ae-label]').fill('새 내각 이름');
  await page.locator('#mkTplMan [data-ae-label]').press('Enter');
  await page.waitForTimeout(80);
  const texts = await page.evaluate(() => [...document.querySelectorAll('#mkTplMan [data-mk-text]')].map(i => i.value));
  check(JSON.stringify(texts) === '["{새 내각 이름}","{새 내각 이름} 출범"]', "묻는 칸 이름을 바꾸면 만드는 것의 {이름}도 함께", texts);
  await page.screenshot({ path: path.join(output, '틀-관리-창-1920-1배.png') });
  await page.locator('#mkTplMan [data-tm-name]').fill('');
  await page.locator('#mkTplMan [data-tm-save]').click();
  await page.waitForTimeout(80);
  const manProbs = await page.evaluate(() => [...document.querySelectorAll('#mkTplMan [data-man-problems] li')].map(li => li.textContent));
  check(manProbs.some(t => /이름을 적으세요/.test(t)) && !(await store('ht.maker.templates')).list.some(t => /내각/.test(t.name)), '이름이 빈 틀은 저장하지 않고 문제 글', manProbs);
  await page.locator('#mkTplMan [data-tm-name]').fill('새 내각');
  await page.locator('#mkTplMan [data-tm-save]').click();
  await page.waitForTimeout(80);
  let saved = (await store('ht.maker.templates')).list;
  check(saved.map(t => t.name).join('|') === '새 지도자|천도|개원|두 지도자|새 내각', '저장 — 목록의 차례대로', saved.map(t => t.name));
  /* 차례: Alt+↑ · 기본 틀 지우기 → 되살리기 */
  await page.locator('#mkTplMan [data-tm-i="4"]').focus();
  await page.keyboard.press('Alt+ArrowUp');
  await page.locator('#mkTplMan [data-tm-i="0"]').click();
  await page.locator('#mkTplMan [data-tm-del]').click();
  check((await page.locator('#mkTplMan [data-tm-restore]').count()) === 1, "기본 틀을 빼면 '기본 틀 되살리기'");
  await page.locator('#mkTplMan [data-tm-save]').click();
  await page.waitForTimeout(80);
  saved = (await store('ht.maker.templates')).list;
  check(saved.map(t => t.name).join('|') === '천도|개원|새 내각|두 지도자', 'Alt+↑로 차례 · 지운 틀은 저장 뒤 사라짐', saved.map(t => t.name));
  await page.locator('#mkTplMan [data-tm-restore]').click();
  await page.locator('#mkTplMan [data-tm-save]').click();
  await page.locator('#mkTplMan [data-man-close]').first().click();
  await page.waitForFunction(() => !document.querySelector('#mkTplMan').open);
  saved = (await store('ht.maker.templates')).list;
  check(saved.at(-1).name === '새 지도자', '기본 틀 되살리기 — 목록 끝에', saved.map(t => t.name));
  /* 만든 틀로 만들기 (가온국) */
  await page.locator('#addPeriodBtn').click();
  await page.waitForTimeout(120);
  await clickCtx('새 내각 — 내각 줄 + 출범 사건');
  await page.waitForSelector(`${fill}[open]`);
  await page.locator(`${fill} [data-ask="polity"]`).selectOption(`${OWN}/gaon`);
  await page.locator(`${fill} [data-ask="year"]`).fill('600');
  await page.locator(`${fill} input[data-ask]:not([data-ask="year"])`).fill('푸른 물 내각');
  await page.locator(`${fill} button[type="submit"]`).click();
  await page.waitForFunction(() => !document.querySelector('#mkTplFill').open);
  await page.waitForTimeout(250);
  d = await raw();
  check(JSON.stringify(d.periods.find(p => p.id === 'gaon').cabinets) === '[{"name":"푸른 물 내각","start":600}]' && d.events.some(e => e.title === '푸른 물 내각 출범' && e.polity === '가온국'), '만든 틀로 만들기 — 내각 줄 + 사건', d.periods.find(p => p.id === 'gaon').cabinets);

  /* 편집 창에 저장하지 않은 고침이 있을 때: 묻는 창에서 그만두면 빈칸 채우기 창은 그대로(적은 칸 · 까닭 글) · 버리고 만들면 그때 닫힘 */
  await open(`${OWN}/narae`);
  await page.locator('#editorForm [name="name"]').fill('나래국 고침');
  await page.locator('#addPeriodBtn').click();
  await page.waitForTimeout(120);
  await clickCtx('개원 — ');
  await page.waitForSelector(`${fill}[open]`);
  check((await page.locator(`${fill} [data-ask="polity"]`).inputValue()) === `${OWN}/narae`, '편집 창의 나라(나래국)가 기본');
  await page.locator(`${fill} [data-ask="year"]`).fill('650');
  await page.locator(`${fill} [data-ask="era"]`).fill('물안개');
  const s0 = await steps();
  await page.locator(`${fill} button[type="submit"]`).click();
  await page.waitForSelector('#mkAskDialog[open]');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  const failed = await page.evaluate(() => [...document.querySelectorAll('#mkTplFill [data-fill-problems] li')].map(li => li.textContent).join('|'));
  check((await page.locator(`${fill}[open]`).count()) === 1 && (await page.locator(`${fill} [data-ask="era"]`).inputValue()) === '물안개' && /만들지 못했습니다/.test(failed) && (await steps()) === s0, '묻는 창에서 그만두면 창 · 적은 칸이 그대로, 까닭은 창 안에', failed);
  await page.locator(`${fill} button[type="submit"]`).click();
  await page.waitForSelector('#mkAskDialog[open]');
  await page.locator('#mkAskNo').click();
  await page.waitForFunction(() => !document.querySelector('#mkTplFill').open);
  await page.waitForTimeout(250);
  d = await raw();
  const nr = d.periods.find(x => x.id === 'narae');
  check(nr.name === '나래국' && JSON.stringify(nr.eras) === '[{"name":"물안개","start":650}]' && d.events.some(e => e.title === '물안개 개원') && (await steps()) === s0 + 1, "'버리고 …'를 고르면 편집 창의 고침은 버리고 틀대로 만듦(한 걸음)", nr);

  check(report.오류.length === 0, '페이지 오류 없음 (틀)', report.오류);

  /* ⑦ 작업 폴더 — 나무 맨 위(팩 줄 바로 아래) 갈래 */
  const rowSel = uid => `#mkTree .mk-trow[data-tuid="${uid}"]:not([data-infolder])`;
  const fRowSel = (fid, uid) => `#mkTree [data-infolder="${fid}"][data-tuid="${uid}"]`;
  const box = async sel => {
    const b = await page.locator(sel).first().boundingBox();
    assert.ok(b, `요소가 없음: ${sel}`);
    return b;
  };
  /** 실제 포인터로 끌어 놓기 (구조 나무 끌기 검사와 같은 꼴) — 놓기 직전의 미리 글 · 빈 자리를 돌려줌 */
  async function dragTo(from, to, { ctrl = false, shot = '' } = {}) {
    const a = await box(from);
    await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
    await page.mouse.down();
    await page.mouse.move(a.x + a.width / 2 + 3, a.y + a.height / 2 + 8, { steps: 3 });
    await page.waitForTimeout(450);
    if (ctrl) await page.keyboard.down('Control');
    for (let i = 0; i < 3; i++) {
      const b = await box(to);
      await page.mouse.move(b.x + Math.min(60 + i, b.width / 2), b.y + b.height / 2, { steps: i ? 2 : 8 });
      await page.waitForTimeout(450);
      const on = await page.evaluate(sel => { const el = document.querySelector(sel); return !!el && [...el.classList].some(c => /^is-(no)?drop/.test(c)); }, to);
      if (on) break;
    }
    const seen = await page.evaluate(() => {
      const slot = document.querySelector('#mkTree .mk-slot:not(.is-closing)');
      const ghost = document.querySelector('.mk-dnd-ghost');
      return { tip: slot ? slot.querySelector('.mk-slot-pre span').textContent : ghost && !ghost.hidden ? (ghost.querySelector('.mk-dnd-why') || {}).textContent || '' : '', slot: !!slot, kind: ((slot || ghost || document).querySelector('.mk-dnd-chip .k') || {}).textContent || '' };
    });
    if (shot) {
      await page.waitForTimeout(450);
      await page.screenshot({ path: path.join(output, shot) });
    }
    await page.mouse.up();
    if (ctrl) await page.keyboard.up('Control');
    await page.waitForTimeout(200);
    return seen;
  }
  const folders = async () => ((await store('ht.maker.folders')) || {})[OWN] || [];
  await page.evaluate(() => HT.viewer.closeEditor());
  await page.waitForTimeout(150);
  check(await page.evaluate(() => { const s = document.querySelector('#mkTree .mk-fsec'); return !!s && s.previousElementSibling && s.previousElementSibling.matches('.is-pack') && s.querySelector('[data-tgroup="folders"] small').textContent === '0'; }), "나무 맨 위(팩 줄 바로 아래)에 '작업 폴더 0' 갈래");
  const steps0 = await steps();
  const draft0 = JSON.stringify(await raw());
  await page.locator('#mkTree [data-fnew]').click();
  await page.waitForTimeout(80);
  check(await page.evaluate(() => document.activeElement && document.activeElement.closest('.mk-fsec .mk-tnew') && !document.activeElement.placeholder), "'＋' — 작업 폴더 아래 이름 칸 하나(회색 예시 글 없음)에 초점");
  await page.keyboard.type('초기 지도자 정리');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  let fs1 = await folders();
  check(fs1.length === 1 && fs1[0].name === '초기 지도자 정리' && fs1[0].color === '#d7c18e' && !fs1[0].items.length, '새 폴더 — 이름 · 첫 색(버터) · 빈 항목 · 작업실 설정(ht.maker.folders)에', fs1);
  const F1 = fs1[0].id;
  const head1 = `#mkTree [data-folder="${F1}"]`;
  check(await page.evaluate(sel => document.activeElement === document.querySelector(sel), head1), 'Enter 뒤 초점은 새 폴더 머리');
  let seen = await dragTo(rowSel(`${OWN}/haeon`), head1, { shot: '작업-폴더-끄는-중-1920-1배.png' });
  check(seen.slot && seen.tip === '놓으면: 폴더 «초기 지도자 정리»에 넣음 (1개)', '나라 줄을 폴더 머리에 끌면 빈 자리 + 미리 글', seen);
  fs1 = await folders();
  check(JSON.stringify(fs1[0].items) === JSON.stringify([`${OWN}/haeon`]) && (await page.locator(fRowSel(F1, `${OWN}/haeon`)).count()) === 1, '놓으면 폴더에 바로 가기 줄 — 자동 묶음의 줄은 그대로', fs1[0]);
  seen = await dragTo(rowSel(`${OWN}/f1`), '#mkTree [data-tgroup="periods:sea"]');
  check(!seen.slot && /작업 폴더에만 놓을 수 있음/.test(seen.tip) && seen.kind === '인물', '인물 줄은 트랙 묶음에는 놓을 수 없음(까닭 글) — 사본에 «인물»', seen);
  seen = await dragTo(rowSel(`${OWN}/f1`), head1);
  check(seen.slot && /폴더 «초기 지도자 정리»에 넣음 \(1개\)/.test(seen.tip), '인물 줄도 폴더에는 넣을 수 있음', seen);
  seen = await dragTo(rowSel(`${OWN}/haeon`), head1);
  check(!seen.slot && /이미 이 폴더에 있음/.test(seen.tip), '이미 든 항목은 놓을 수 없음', seen);
  check((await steps()) === steps0 && JSON.stringify(await raw()) === draft0, '폴더에 넣어도 작업본은 그대로(되돌리기 걸음 없음)');
  /* '작업 폴더' 머리에 놓기 = 새 폴더 */
  seen = await dragTo(rowSel(`${OWN}/gaon`), '#mkTree [data-tgroup="folders"]');
  check(seen.slot && seen.tip === '놓으면: 새 폴더를 만들어 넣음 (1개)', "'작업 폴더' 머리에 놓으면 새 폴더", seen);
  await page.waitForTimeout(100);
  check(await page.evaluate(() => document.activeElement && document.activeElement.closest('.mk-tnew') && document.activeElement.value === '새 폴더'), "놓자마자 새 폴더의 이름 칸('새 폴더' — 골라 둠)");
  await page.keyboard.type('도읍 옮긴 일');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  fs1 = await folders();
  const F2 = fs1[1].id;
  check(fs1.length === 2 && fs1[1].name === '도읍 옮긴 일' && fs1[1].color === '#a0bcc5' && fs1[1].items[0] === `${OWN}/gaon`, '새 폴더 — 둘째 색(스카이) · 놓은 항목', fs1[1]);
  /* 폴더에서 폴더로: Ctrl = 남김 · 그냥 = 옮김 */
  seen = await dragTo(fRowSel(F1, `${OWN}/haeon`), `#mkTree [data-folder="${F2}"]`, { ctrl: true });
  fs1 = await folders();
  check(seen.slot && !/Ctrl|에서 뺌/.test(seen.tip) && fs1[0].items.includes(`${OWN}/haeon`) && fs1[1].items.includes(`${OWN}/haeon`), 'Ctrl을 누른 채 놓으면 원래 폴더에도 남음', { seen, fs1 });
  seen = await dragTo(fRowSel(F2, `${OWN}/gaon`), head1);
  fs1 = await folders();
  check(/«도읍 옮긴 일»에서 뺌/.test(seen.tip) && fs1[0].items.includes(`${OWN}/gaon`) && !fs1[1].items.includes(`${OWN}/gaon`), '폴더 안의 줄을 다른 폴더에 놓으면 옮김(미리 글에 알림)', { seen, fs1 });
  await page.screenshot({ path: path.join(output, '작업-폴더-나무.png'), clip: { x: 0, y: 72, width: 560, height: 984 } });
  /* 항목 메뉴 '폴더에 넣기…' · '폴더에서 빼기' */
  await page.locator(rowSel(`${OWN}/narae`)).click({ button: 'right' });
  await page.waitForTimeout(120);
  await clickCtx('폴더에 넣기…');
  menu = await ctxMenu();
  check(menu[0] === '# 폴더에 넣기 — 1개' && menu.includes('초기 지도자 정리') && menu.includes('도읍 옮긴 일') && menu.at(-1) === '＋ 새 폴더에 넣기', "항목 메뉴 '폴더에 넣기…' — 폴더 목록 · 새 폴더", menu);
  await clickCtx('도읍 옮긴 일');
  fs1 = await folders();
  check(fs1[1].items.includes(`${OWN}/narae`), "'폴더에 넣기…'로 넣음", fs1[1]);
  await page.locator(fRowSel(F2, `${OWN}/narae`)).click({ button: 'right' });
  await page.waitForTimeout(120);
  await clickCtx('폴더 «도읍 옮긴 일»에서 빼기');
  check(!(await folders())[1].items.includes(`${OWN}/narae`), "폴더 안 줄의 메뉴 '폴더에서 빼기'");
  /* 폴더 메뉴 — 이름 · 색 · 모두 고르기 · 지우기 */
  await page.locator(head1).click({ button: 'right' });
  await page.waitForTimeout(150);
  const fmenu = await page.evaluate(() => { const m = document.querySelector('.mk-fmenu'); return m && !m.hidden ? { items: [...m.querySelectorAll('.ctx-item .ctx-label')].map(e => e.textContent), sw: m.querySelectorAll('[data-fsw]').length, on: (m.querySelector('[data-fsw].is-on') || {}).dataset?.fsw } : null; });
  check(!!fmenu && fmenu.items.join('|') === '이름 바꾸기|집합 보기로 내보내기…|폴더 안 항목 모두 고르기|폴더 지우기 — 항목은 그대로' && fmenu.sw === 12 && fmenu.on === '#d7c18e', '폴더 메뉴: 이름 바꾸기 · 색(파스텔 열둘) · 집합 보기로 내보내기 · 모두 고르기 · 지우기', fmenu);
  await page.screenshot({ path: path.join(output, '작업-폴더-메뉴.png'), clip: { x: 0, y: 72, width: 560, height: 984 } });
  await page.locator('.mk-fmenu [data-fsw="#bbacc8"]').click();
  await page.waitForTimeout(100);
  check((await folders())[0].color === '#bbacc8' && (await page.locator('.mk-fmenu:not([hidden]) [data-fsw="#bbacc8"].is-on').count()) === 1, '색 견본 — 바로 바뀌고 메뉴는 그대로');
  await page.locator('.mk-fmenu .ctx-item', { hasText: '폴더 안 항목 모두 고르기' }).click();
  await page.waitForTimeout(120);
  const sel = await page.evaluate(() => __maker.selection().slice().sort());
  check(JSON.stringify(sel) === JSON.stringify([`${OWN}/f1`, `${OWN}/gaon`, `${OWN}/haeon`]), '폴더 안 항목 모두 고르기', sel);
  /* ⑧ 집합 보기로 내보내기 */
  await page.locator(head1).click({ button: 'right' });
  await page.waitForTimeout(150);
  await page.locator('.mk-fmenu .ctx-item', { hasText: '집합 보기로 내보내기…' }).click();
  await page.waitForSelector('#mkAskDialog[open]');
  const askText = await page.locator('#mkAskText').innerText();
  check(/나라 2 · 인물 1/.test(askText) && /나라만 들어 1개는 빠집니다/.test(askText) && (await page.locator('#mkAskYes').innerText()) === '집합 보기 더하기', '내보내기 전에 알림 — 폴더의 종류별 수 · 나라만 듦', askText);
  const steps1 = await steps();
  await page.locator('#mkAskYes').click();
  await page.waitForTimeout(300);
  d = await raw();
  check((await steps()) === steps1 + 1 && d.views.length === 1 && d.views[0].name === '초기 지도자 정리' && JSON.stringify(d.views[0].members) === JSON.stringify([{ track: 'sea', polity: '해온국' }, { track: 'sea', polity: '가온국' }]) && d.views[0].color === '#bbacc8', '집합 보기 하나(views — 이름 · 구성 나라 { track, polity } · 폴더 색) · 되돌리기 한 걸음', d.views);
  const vm = await page.evaluate(id => { const v = __state.model.viewMap.get(id); return v ? { n: v.members.length, w: v.warnings.length } : null; }, d.views[0].id);
  check(!!vm && vm.n === 2 && vm.w === 0, '모델이 집합 보기의 구성 나라 둘을 모두 찾음(경고 없음)', vm);
  check(await page.evaluate(() => HT.usesFormatV3(__maker.draft)), '집합 보기(views)는 형식 3 열쇠 — 이 파일만 형식 3');
  await undo();
  check(!(await raw()).views || !(await raw()).views.length, '되돌리기 한 번에 집합 보기가 빠짐');
  /* F2 · Esc · Alt+↓ · Delete */
  await page.locator(head1).focus();
  await page.keyboard.press('F2');
  await page.waitForTimeout(100);
  check(await page.evaluate(() => document.activeElement && document.activeElement.closest('.mk-tnew') && document.activeElement.value === '초기 지도자 정리'), 'F2 — 폴더 이름 칸');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(100);
  check((await folders())[0].name === '초기 지도자 정리', 'Esc — 그만둠');
  await page.locator(head1).focus();
  await page.keyboard.press('Alt+ArrowDown');
  await page.waitForTimeout(150);
  check((await folders()).map(f => f.id).join() === [F2, F1].join() && (await page.evaluate(sel => document.activeElement === document.querySelector(sel), head1)), 'Alt+↓ — 폴더 차례 · 초점은 그 폴더 머리');
  /* 다른 보기 갈래 · 찾기 */
  await page.locator('#mkLeft [data-tview]').selectOption('people');
  await page.waitForTimeout(250);
  check(await page.evaluate(() => { const s = document.querySelector('#mkTree .mk-fsec'); return !!s && s.previousElementSibling.matches('.is-pack') && s.querySelectorAll('[data-folder]').length === 2; }), "보기 갈래 '민족으로'에서도 맨 위에 같은 작업 폴더");
  await page.locator('#mkTreeFind').fill('가온');
  await page.waitForTimeout(250);
  const found = await page.evaluate(() => [...document.querySelectorAll('#mkTree .mk-fsec [data-infolder]')].map(e => e.textContent));
  check(found.length >= 1 && found.every(t => /가온/.test(t)), '찾기 칸 — 작업 폴더도 맞는 줄만', found);
  await page.locator('#mkTreeFind').fill('');
  await page.locator('#mkLeft [data-tview]').selectOption('kind');
  await page.waitForTimeout(250);
  await page.locator(head1).focus();
  await page.keyboard.press('Delete');
  await page.waitForSelector('#mkAskDialog[open]');
  check(/항목 3개는 제자리에 그대로/.test(await page.locator('#mkAskText').innerText()), 'Delete — 든 항목이 있으면 묻고(항목은 그대로)', await page.locator('#mkAskText').innerText());
  await page.locator('#mkAskYes').click();
  await page.waitForTimeout(150);
  fs1 = await folders();
  check(fs1.length === 1 && fs1[0].id === F2 && (await steps()) === steps1 && JSON.stringify(await raw()) === draft0, '폴더 지우기 — 항목 · 작업본은 그대로(집합 보기는 되돌린 뒤)', fs1);
  /* 순수 부품: 읽기 · DLC id가 바뀌면 따라감 */
  const pure = await page.evaluate(() => {
    const S = HT.makerShell;
    const r = S.readFolders({ a: [{ id: 'f-1', name: ' 하나 ', color: '#zzzzzz', items: ['a/x', 'a/x', 3] }, { id: 'bad id' }, { id: 'f-1' }] }, 'a');
    localStorage.setItem('ht.maker.folders', JSON.stringify({ old: [{ id: 'f-1', name: 'x', color: '#d7c18e', items: ['old/p1', 'other/p2'] }] }));
    S.moveFolders('old', 'new');
    const m = JSON.parse(localStorage.getItem('ht.maker.folders'));
    return { r, m };
  });
  check(JSON.stringify(pure.r) === '[{"id":"f-1","name":"하나","color":"#d4a39b","items":["a/x"]}]' && !pure.m.old && JSON.stringify(pure.m.new[0].items) === '["new/p1","other/p2"]', '폴더 읽기(모르는 값 버림 · 색 바로잡음 · 같은 항목 한 번) · DLC id를 바꾸면 폴더와 제 항목 바로 가기가 따라감', pure);
  check(report.오류.length === 0, '페이지 오류 없음 (폴더)', report.오류);
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
  console.log(`maker-templates-check: ${report.검사.length}개 통과`);
} finally {
  await browser.close();
  server.close();
}
