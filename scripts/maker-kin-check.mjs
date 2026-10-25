/* 메이커 계보 입력(D1-M1 — docs/설계-10건/의 D1 확정 설계 7절)을 실제 브라우저로 검사합니다.
   node scripts/maker-kin-check.mjs <검사할 폴더> <결과 폴더>
   가상 작업본(가람 나라 · 지도자 둘 · 계보 전용 인물 · 가문)과 가상 이웃 팩(다른 DLC의 나라 · 가문)을 독립 브라우저의 저장소에만 넣고:
   ① 계층 입력 — 뿌리에서 지은 글 · 줄을 더해 적용(새 계보 전용 인물 · id 명시 · 부모 참조 · 이름 미상 · 양자 · 파조 → 가문 줄) · 다시 열면 같은 글(왕복) · 되돌리기 한 걸음 ·
      줄 지우기 물음 · '/' 넣을 것 목록 · 족보 들여쓰기 붙여넣기(인물 표 → 계층 입력 창)
   ② 인물 표 — 엑셀 머리글(이름 · 부 · 파 · 생 · 몰) 붙여넣기 두 번 읽기(같은 붙여넣기 안의 이름 · 겹친 이름 = 가장 가까운 위 줄 · 못 찾음 → 새 사람) · 계보 전용 · 부 칸 ·
      한꺼번에 고치기(계보 전용 · 부) · 사람 찾기 상자(세 글자)
   ③ 지도자 줄 붙여넣기의 새 열(관계 · 방식 · 전임자 · 인물 · 부)
   ④ 머리 칩 고치기 HT.maker.kin.editHead — 정권 트랙 · 민족 · 이름 · 가문 구분 · 꼬리표(원래 칸 · 되돌리기 한 걸음) · 남의 DLC 정권 → 패치 set · 남의 가문 → 알림
   ⑤ 적는 글(7-4: 겹치면 id) · 구조 나무 거르기 · 상태 줄 수 · 짐작 딱지(회색 예시 글 없음) · 가문 표의 새 열
   D1-W1(core.js의 계보 전용 읽기 · 모델)이 아직 기록되지 않았으면 그 부분은 '대역(W1 대기)'으로 적고 건너뜁니다 — 결합 단계에서 다시 돌립니다.
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)로 고릅니다 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/계보-입력');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'dlc-maker.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      const text = bytes.toString('utf8'), marker = 'if (maker) maker.start();';
      assert.equal(text.split(marker).length, 2, 'viewer.js의 메이커 시작 줄이 하나가 아님');
      bytes = Buffer.from(text.replace(marker, marker + ' window.__maker = maker; window.__state = state; window.__openDetail = (...a) => openDetail(...a);'));
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));

/* 가상 자료 — 실제 역사 이름 없음 */
const OWN = 'kin-maker';
const NEAR = 'kin-neighbor';
const draft = {
  format: 'history-timeline-dlc', formatVersion: 3, id: OWN, name: '가상 계보 입력 검사', version: '1.0.0', author: '', description: '',
  tracks: [{ id: 'garam', name: '가람', order: 10 }, { id: 'dal', name: '달내', order: 20 }],
  categories: [],
  peoples: [{ id: 'nuri', name: '누리족' }, { id: 'nuri-a', name: '누리 갈래', parent: '누리족' }],
  houses: [{ id: 'h-on', name: '물빛 온씨', surname: '온', seat: '물빛', founder: '가람 나라:첫 임금@1400' }],
  periods: [{
    id: 'garam', track: 'garam', name: '가람 나라', people: '누리족', house: 'h-on', start: 1400, end: 1650,
    leaders: [
      { name: '첫 임금', start: 1400, end: 1418 },
      { name: '둘째 임금', start: 1418, end: 1450, accession: { kin: '아들', how: '선양' }, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] },
    ],
  }],
  events: [],
  figures: [
    { id: 'f-baram', track: 'garam', name: '바람대군', lineageOnly: true, birth: 1402, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] },
    { id: 'f-sol', track: 'garam', name: '솔군', lineageOnly: true, birth: 1430, parents: [{ who: 'f-baram', as: '부' }] },
  ],
  epochs: [], organs: [], cultures: [], dynasties: [], scopes: [], patches: [], rankDefs: [], documents: {}, requires: [],
};
const near = {
  format: 'history-timeline-dlc', formatVersion: 2, id: NEAR, name: '가상 이웃 팩', version: '1.0.0',
  tracks: [{ id: 'dal', name: '달내' }], peoples: [{ id: 'mae', name: '메족' }],
  houses: [{ id: 'h-near', name: '이웃 씨', surname: '이웃' }],
  periods: [{ id: 'ipo', track: 'dal', name: '이웃 나라', people: '메족', house: 'h-near', start: 1300, end: 1500, leaders: [{ name: '이웃 임금', start: 1300, end: 1350 }] }],
  events: [],
};

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 대역: [], 오류: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details, null, 1) : ''));
};
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
  await context.addInitScript(({ draft, near, OWN, NEAR }) => {
    if (sessionStorage.getItem('kin-seeded')) return;
    sessionStorage.setItem('kin-seeded', '1');
    localStorage.clear();
    localStorage.setItem('ht.packs.installed', JSON.stringify([near]));
    localStorage.setItem('ht.maker.draft', JSON.stringify(draft));
    localStorage.setItem('ht.maker.refs', JSON.stringify({ [OWN]: [{ id: NEAR, show: true, locked: false }] }));
    localStorage.setItem('ht.maker.tree', JSON.stringify({ view: 'kind', ref: false }));
  }, { draft, near, OWN, NEAR });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => m.type() === 'error' && report.오류.push(m.text()));
  await page.goto('http://127.0.0.1:' + server.address().port + '/dlc-maker.html');
  await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden && window.HT && HT.maker && HT.maker.kin && HT.maker.kin.ready());
  await page.waitForTimeout(300);

  /* 도우미 */
  const raw = () => page.evaluate(() => JSON.parse(JSON.stringify(__maker.draft)));
  const steps = () => page.evaluate(() => __maker.history.index);
  const fig = async id => (await raw()).figures.find(f => f.id === id);
  const undo = async () => {
    await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(150);
  };
  /* D1-W1(core.js)이 계보 전용 인물을 읽고 모델(lineageFigures)에 두는지 — 아니면 그 부분은 대역으로 적고 건너뜀 */
  const w1 = await page.evaluate(() => Array.isArray(__state.model.lineageFigures) && __state.model.byUid.has('kin-maker/f-baram') && !!HT.personOf(__state.model, __state.model.byUid.get('kin-maker/f-baram')));
  const w1Model = w1 && (await page.evaluate(() => {
    const r = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 3, id: 'probe', name: 'p', tracks: [{ id: 't', name: 't' }], figures: [{ id: 'a', track: 't', name: '날짜 없음', lineageOnly: true }] });
    return !!(r.pack && r.pack.figures.length === 1);
  }));
  if (!w1Model) report.대역.push('D1-W1의 계보 전용 읽기(날짜 없는 계보 전용 인물) · 모델이 아직 없어, 날짜 없는 새 사람이 모델에 드는 검사는 건너뜀 — 결합 때 다시');
  const rootKey = `c:${OWN}/garam|leader:0`;
  const openOutline = async (opts = { uid: rootKey }) => {
    await page.evaluate(o => { window.__kinDone = HT.maker.kin.outline(o); }, opts);
    await page.waitForSelector('dialog.mk-kin-dlg[open] [data-kin-text]');
    await page.waitForTimeout(80);
  };
  const frames = () => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(r, 30)))));
  const outlineText = () => page.evaluate(() => document.querySelector('dialog.mk-kin-dlg [data-kin-text]').value);
  const setOutline = async text => {
    await page.evaluate(t => { const ta = document.querySelector('dialog.mk-kin-dlg [data-kin-text]'); ta.value = t; ta.dispatchEvent(new Event('input', { bubbles: true })); }, text);
    await frames();
  };
  const sumText = () => page.evaluate(() => document.querySelector('dialog.mk-kin-dlg [data-kin-sum]').textContent);
  const applyOutline = async () => {
    await page.click('dialog.mk-kin-dlg [data-kin-apply]');
    await page.waitForFunction(() => !document.querySelector('dialog.mk-kin-dlg') || document.querySelector('#mkAskDialog[open]'));
    await page.waitForTimeout(150);
  };

  /* ========== ① 계층 입력 ========== */
  await openOutline();
  const first = await outlineText();
  check(first === '첫 임금\n  바람대군 (1402 ~)\n    솔군 (1430 ~)\n  둘째 임금', '계층 입력: 뿌리(첫 임금) 아래 자손 글 — 생년 있는 바람대군이 생년 없는 둘째 임금보다 앞(2-4 아), 들여쓰기 = 세대', first);
  check(await page.evaluate(() => !document.querySelector('dialog.mk-kin-dlg [placeholder]')), '계층 입력 창에 회색 예시 글(placeholder)이 없음');
  /* '/' 넣을 것 목록 — 솔군 줄 끝에서 / → 파 */
  await page.evaluate(() => { const ta = document.querySelector('dialog.mk-kin-dlg [data-kin-text]'); const at = ta.value.indexOf('솔군 (1430 ~)') + '솔군 (1430 ~)'.length; ta.focus(); ta.setSelectionRange(at, at); });
  await page.keyboard.type('/');
  await page.waitForSelector('dialog.mk-kin-dlg .mk-kin-slash');
  const slashItems = await page.evaluate(() => [...document.querySelectorAll('.mk-kin-slash [data-slash]')].map(o => o.dataset.slash));
  check(JSON.stringify(slashItems) === JSON.stringify(['branch', 'adopted', 'unknown', 'dates']), "'/'를 치면 작은 펼침 목록(파 · 양자 · 미상 · 생몰 — D3 결정 5 A)", slashItems);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  check((await outlineText()).includes('    솔군 (1430 ~) [솔군파]'), "목록에서 '파'를 고르면 줄 끝에 실제 이름으로 [솔군파]", await outlineText());
  await page.screenshot({ path: path.join(output, '계층-입력-1920-1배.png') });
  /* 줄 더하기: 이름 미상(공유) · 그 아래 형제 둘 · 양자 · 파 안의 파 */
  const grown = [
    '첫 임금',
    '  바람대군 (1402 ~) [바람대군파]',
    '    솔군 (1430 ~) [솔군파]',
    '      미상',
    '        온 가람 (1500 ~ 1560)',
    '        온 나래',
    '    달군 (양자)',
    '  둘째 임금',
  ].join('\n');
  await setOutline(grown);
  const sum1 = await sumText();
  check(/새 사람 4/.test(sum1) && /파 2/.test(sum1), '미리 보기 요약: 새 사람 4 · 파 2', sum1);
  const rowsShown = await page.evaluate(() => [...document.querySelectorAll('dialog.mk-kin-dlg .mk-kin-row')].map(r => r.textContent));
  check(rowsShown.length === 8 && rowsShown.some(t => /이름 미상/.test(t)) && rowsShown.some(t => /양자/.test(t)), '나무 미리 보기: 줄 8 · 이름 미상(빈 고리) · 양자 칩', rowsShown);
  let h0 = await steps();
  await applyOutline();
  check((await steps()) === h0 + 1, '계층 입력 [적용] = 되돌리기 한 걸음');
  let d = await raw();
  const added = d.figures.filter(f => !['f-baram', 'f-sol'].includes(f.id));
  const byName = n => added.find(f => f.name === n);
  check(added.length === 4 && added.every(f => f.lineageOnly === true && /^[A-Za-z0-9_.-]+$/.test(f.id) && f.track === 'garam'), '새 줄 → 계보 전용 인물(id 명시 · 트랙은 부모에서)', added);
  const unk = byName('미상');
  check(!!unk && unk.parents[0].who === '솔군' && unk.parents[0].as === 'father', '이름 미상의 사람: 부모 = 솔군(이름이 하나뿐이라 이름으로)', unk);
  check(byName('온 가람').parents[0].who === unk.id && byName('온 나래').parents[0].who === unk.id, '미상 아래 형제 둘은 미상을 id로 가리킴(한 빈 고리 — 2-4 다)', [byName('온 가람'), byName('온 나래')]);
  check(byName('온 가람').birth === 1500 && byName('온 가람').death === 1560, '생몰 (1500 ~ 1560)', byName('온 가람'));
  check(byName('달군').parents[0].as === 'adoptive-father' && byName('달군').parents[0].who === '바람대군', '(양자) = 위 줄이 양부', byName('달군'));
  const hb = d.houses.find(h => h.name === '바람대군파'), hs = d.houses.find(h => h.name === '솔군파');
  check(!!hb && hb.parent === '물빛 온씨' && hb.founder === 'f-baram', '[바람대군파] → 가문 줄 { parent: 본가, founder: 파조 id }', hb);
  check(!!hs && hs.parent === hb.id && hs.founder === 'f-sol', '[솔군파] → 파 안의 파(본가 = 바람대군파)', hs);
  /* 왕복 — 다시 열면 같은 글 */
  if (w1Model) {
    await openOutline();
    const again = await outlineText();
    check(again === grown, '계층 입력 왕복: 글 → 인물 · 가문 줄 → 다시 지은 글이 같음', { again, grown });
    /* 줄 지우기 → 물음 → 지우고 적용 */
    await setOutline(grown.replace('        온 나래\n', ''));
    check(/지운 줄 1/.test(await sumText()), '줄을 지우면 요약에 지운 줄', await sumText());
    await page.click('dialog.mk-kin-dlg [data-kin-apply]');
    await page.waitForSelector('#mkAskDialog[open]');
    const askText = await page.evaluate(() => document.querySelector('#mkAskDialog').textContent);
    check(/계보 전용 인물 1명은 작업본에서 지우고/.test(askText), '지운 줄은 물음(계보 전용 인물은 지움)', askText);
    await page.click('#mkAskDialog button[value="yes"]');
    await page.waitForFunction(() => !document.querySelector('dialog.mk-kin-dlg'));
    await page.waitForTimeout(150);
    check(!(await raw()).figures.some(f => f.name === '온 나래'), '지우고 적용 → 온 나래가 작업본에서 빠짐');
    await undo();
    check((await raw()).figures.some(f => f.name === '온 나래'), '되돌리기 한 번에 돌아옴');
    /* 들여쓰기 바꾸기(부모 바꿈) · 이름 바꿈 */
    await openOutline();
    await setOutline(grown.replace('    달군 (양자)', '  달군').replace('        온 가람 (1500 ~ 1560)', '        온 가람별 (1500 ~ 1560)'));
    await applyOutline();
    d = await raw();
    const dalgun = d.figures.find(f => f.name === '달군');
    check(dalgun.parents[0].who === '첫 임금' || (typeof dalgun.parents[0].who === 'object' && dalgun.parents[0].who.leader === '첫 임금'), '들여쓰기를 바꾼 줄 → 부모 바꿈(첫 임금 아래로 · 양자 표시를 빼면 부)', dalgun);
    check(dalgun.parents[0].as === 'father', '양자 표시를 빼면 as = father', dalgun);
    check(d.figures.some(f => f.name === '온 가람별') && !d.figures.some(f => f.name === '온 가람'), '고친 이름 → 그 사람의 이름 바꿈(id 그대로)', d.figures.filter(f => /온 가람/.test(f.name)));
    await undo();
  } else report.대역.push('계층 입력 왕복 · 줄 지우기 · 부모 바꿈 — 날짜 없는 계보 전용 인물이 모델에 들어야 함(W1)');
  await undo();
  check(JSON.stringify((await raw()).figures) === JSON.stringify(draft.figures), '되돌리기로 처음 인물 목록');

  /* 족보 들여쓰기 붙여넣기 — 인물 표에 붙여넣으면 계층 입력 창 (뿌리 없음: 맨 위 줄은 같은 이름의 사람으로 이음) */
  await page.click('#mkCTabs [data-ctab="table"]');
  await page.waitForTimeout(150);
  await page.selectOption('[data-grid-list]', 'figures');
  await page.waitForTimeout(150);
  const pasteGrid = async text => {
    await page.evaluate(t => {
      const sc = document.querySelector('.mk-grid-scroll');
      sc.focus();
      const dt = new DataTransfer();
      dt.setData('text/plain', t);
      sc.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
    }, text);
    await page.waitForTimeout(200);
  };
  await pasteGrid('바람대군\n\t솔군\n\t\t별군 (1460 ~)\n\t\t새군');
  check(await page.locator('dialog.mk-kin-dlg[open]').count() === 1, '족보 들여쓰기 글을 인물 표에 붙여넣으면 계층 입력 창이 열림');
  const sum2 = await sumText();
  check(/새 사람 2/.test(sum2) && !/빨간/.test(sum2), '맨 위 줄(바람대군) · 그 자식(솔군)은 있는 사람으로 잇고 새 사람 2', sum2);
  await applyOutline();
  d = await raw();
  check(d.figures.filter(f => ['별군', '새군'].includes(f.name)).every(f => f.parents[0].who === '솔군' && f.lineageOnly), '붙여넣은 족보의 새 사람: 부 = 솔군 · 계보 전용', d.figures.slice(2));
  await undo();

  /* ========== ② 인물 표 — 엑셀 머리글 붙여넣기 두 번 읽기 ========== */
  /* 새 줄(+)에서 붙여넣기 — 표의 붙여넣기는 고른 칸부터 덮어쓰므로 */
  await page.focus('.mk-grid-scroll');
  for (let i = 0; i < 3; i++) await page.keyboard.press('ArrowDown');
  await pasteGrid('이름\t부\t파\t생\t몰\n한별\t솔군\t\t1530\t1590\n한별\t바람대군\t\t1540\t\n새벽\t한별\t\t1560\t\n구름\t없는이\t\t\t');
  await page.waitForSelector('dialog.mk-box[open] [data-create-missing]');
  const confirmText = await page.evaluate(() => document.querySelector('dialog.mk-box[open]').textContent);
  check(/찾지 못한 부모 1명/.test(confirmText) && /없는이/.test(confirmText), '못 찾은 부는 확인 창에 빨갛게(없는이)', confirmText);
  check(/계보 전용 인물로 넣습니다/.test(confirmText), '족보 붙여넣기의 새 줄은 계보 전용 인물로(활동 시작을 지어 넣지 않음)', confirmText);
  await page.check('dialog.mk-box[open] [data-create-missing]');
  h0 = await steps();
  await page.click('dialog.mk-box[open] [data-accept]');
  await page.waitForTimeout(300);
  check((await steps()) === h0 + 1, '표 붙여넣기 = 되돌리기 한 걸음');
  d = await raw();
  const hanbyeol = d.figures.filter(f => f.name === '한별');
  const saebyeok = d.figures.find(f => f.name === '새벽');
  check(hanbyeol.length === 2 && hanbyeol[0].parents[0].who === '솔군' && hanbyeol[1].parents[0].who === '바람대군', '첫째 읽기: 줄을 만들고 부를 이름으로(하나뿐인 이름)', hanbyeol);
  check(saebyeok.parents[0].who === hanbyeol[1].id, '같은 붙여넣기 안의 겹친 이름(한별 둘) → 바로 위의 가장 가까운 줄, id로 적음(7-4)', saebyeok);
  const nobody = d.figures.find(f => f.name === '없는이');
  check(!!nobody && nobody.lineageOnly === true && d.figures.find(f => f.name === '구름').parents[0].who === nobody.id, "'새 사람으로 만들기' → 없는이를 계보 전용 인물로 만들고 id로 가리킴", [nobody, d.figures.find(f => f.name === '구름')]);
  check(hanbyeol.every(f => f.lineageOnly === true && !('start' in f)) && hanbyeol[0].birth === 1530 && hanbyeol[0].death === 1590, '생 · 몰 머리글(별칭) → birth · death', hanbyeol);
  /* 부 칸: 한 칸 고치기 — 그 역할의 줄만 바꾸고 확실성 · 메모는 지킴 */
  await page.evaluate(() => {
    const d = __maker.draft;
    return null;
  });
  const parentCellOk = await page.evaluate(() => {
    const x = { parents: [{ who: '갑', as: 'father', certainty: 'estimated', note: '메모' }, { who: '을', as: 'mother' }] };
    HT.makerKin.setParent(x, 'father', '병');
    const a = JSON.stringify(x.parents);
    HT.makerKin.setParent(x, 'mother', '');
    return { a, b: JSON.stringify(x.parents) };
  });
  check(parentCellOk.a === JSON.stringify([{ who: '병', as: 'father', certainty: 'estimated', note: '메모' }, { who: '을', as: 'mother' }]) && parentCellOk.b === JSON.stringify([{ who: '병', as: 'father', certainty: 'estimated', note: '메모' }]), '부 · 모 칸은 그 역할의 부모 줄 하나만 고침(확실성 · 메모 그대로)', parentCellOk);
  const cols = await page.evaluate(() => HT.makerGrid.columns({ list: 'figures' }).map(c => c.label));
  check(['계보 전용', '부', '모', '양부', '생부', '형제 순서'].every(l => cols.includes(l)), '인물 표의 새 열: 계보 전용 · 부 · 모 · 양부 · 생부 · 형제 순서', cols);
  /* 한꺼번에 고치기: 계보 전용 · 부 */
  const bulk = await page.evaluate(() => {
    const d = JSON.parse(JSON.stringify(__maker.draft));
    const ids = d.figures.filter(f => f.name === '한별').map(f => `${d.id}/${f.id}`);
    const env = { model: __state.model, isLocked: () => false, rawOf: x => x, baseModel: () => __state.model };
    const r1 = HT.makerGrid.bulkPlan(d, ids, { key: 'kin:father', text: '바람대군' }, env);
    const r2 = HT.makerGrid.bulkPlan(d, ids, { key: 'lineageOnly', text: '' }, env);
    return { changed: [r1.changed, r2.changed], figs: d.figures.filter(f => f.name === '한별') };
  });
  check(bulk.changed[0] === 1 && bulk.changed[1] === 2 && bulk.figs.every(f => f.parents[0].who === '바람대군' && !f.lineageOnly), '한꺼번에 고치기의 부 · 계보 전용(고른 사람들 한 번에)', bulk);
  check(await page.evaluate(() => HT.makerGrid.BULK_FIELDS.some(c => c.key === 'lineageOnly') && HT.makerGrid.BULK_FIELDS.some(c => c.key === 'kin:father')), '한꺼번에 고치기의 고칠 칸에 계보 전용 · 부');
  /* 사람 찾기 상자 — 부 칸에서 세 글자 */
  const rowIdx = await page.evaluate(() => [...document.querySelectorAll('.mk-grid-head [data-grid-sort]')].findIndex(b => b.dataset.gridSort === 'kin:father'));
  await page.evaluate(i => { document.querySelector('.mk-grid-scroll').scrollLeft = 0; const el = document.querySelector(`[data-grid-cell="3:${i}"]`); el.scrollIntoView({ inline: 'center' }); }, rowIdx);
  await page.dblclick(`[data-grid-cell="3:${rowIdx}"]`);
  await page.keyboard.type('바람대');
  await page.waitForTimeout(150);
  const finder = await page.evaluate(() => { const b = [...document.querySelectorAll('.mk-kin-find')].find(x => !x.hidden); return b ? [...b.querySelectorAll('[data-i] b')].map(x => x.textContent) : null; });
  check(!!finder && finder.includes('바람대군'), '사람 칸에 세 글자 넘게 치면 사람 찾기 상자(계보 전용 인물 포함)', finder);
  await page.screenshot({ path: path.join(output, '인물-표-사람-찾기-1920-1배.png') });
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await undo();
  check(JSON.stringify((await raw()).figures) === JSON.stringify(draft.figures), '되돌리기로 처음 인물 목록(표)');

  /* ========== ③ 지도자 줄 붙여넣기의 새 열 ========== */
  const lp = await page.evaluate(() => {
    const a = HT.makerPaste.analyze('대표 이름\t시작\t끝\t관계\t방식\t전임자\t인물\t부\n셋째 임금\t1450\t1470\t동생\t찬탈\t\t\t가람 나라:첫 임금@1400\n넷째 임금\t1470\t1480\t미상\t\t미상\tf-sol\t', 'leaders');
    return { map: a.map, rows: a.rows.map(r => ({ cell: r.cell, error: r.error })) };
  });
  check(JSON.stringify(lp.map) === JSON.stringify(['name', 'start', 'end', 'kin', 'how', 'from', 'person', 'father']), '지도자 줄 붙여넣기: 관계 · 방식 · 전임자 · 인물 · 부 머리글을 알아봄', lp.map);
  check(JSON.stringify(lp.rows[0].cell.accession) === JSON.stringify({ kin: 'younger-brother', how: 'usurpation' }) && JSON.stringify(lp.rows[0].cell.parents) === JSON.stringify([{ who: { polity: '가람 나라', leader: '첫 임금', start: 1400 }, as: 'father' }]), '관계 · 방식 → accession · 부 → parents(사람 참조 읽기 그대로)', lp.rows[0]);
  check(JSON.stringify(lp.rows[1].cell.accession) === JSON.stringify({ kinUnknown: true, fromUnknown: true }) && lp.rows[1].cell.person === 'f-sol' && !lp.rows[1].error, '미상 → …Unknown · 인물 → person', lp.rows[1]);
  check(!/앞 지도자/.test(await page.evaluate(() => HT.makerPaste.FIELDS.leaders.flatMap(f => f.aliases).join(' '))), '새 열의 낱말은 한자어(전임자) — 옛 말을 새로 쓰지 않음');
  /* 실제 편집 창: 지도자 목록의 '여러 줄 한꺼번에 붙여넣기' → 미리 보기 창 → 넣기 → 저장(Ctrl+S) → 작업본의 칸에 accession · parents · person */
  await page.locator(`#mkTree [data-tuid="${OWN}/garam"]`).click();
  const form = page.locator('form:has([data-paste-text="leaders"])').first();
  await form.waitFor({ state: 'attached' });
  await form.locator('details[data-adv="cells"]').evaluate(el => { el.open = true; for (const x of el.querySelectorAll('details.cell-paste')) x.open = true; });
  await form.locator('[data-paste-text="leaders"]').fill('대표 이름\t시작\t끝\t관계\t방식\t전임자\t인물\t부\n셋째 임금\t1450\t1470\t동생\t찬탈\t\t\t가람 나라:첫 임금@1400');
  await form.locator('[data-cell-paste="leaders"]').click();
  const dlg = page.locator('dialog[data-row-paste="leaders"]');
  await dlg.waitFor();
  check(JSON.stringify(await dlg.locator('thead select').evaluateAll(s => s.map(x => x.value))) === JSON.stringify(['name', 'start', 'end', 'kin', 'how', 'from', 'person', 'father']), '편집 창의 줄 묶음 붙여넣기 미리 보기: 새 열을 머리글로 맞춤');
  await page.screenshot({ path: path.join(output, '지도자-줄-붙여넣기-새-열-1920-1배.png') });
  await dlg.locator('[data-paste-accept]').click();
  await dlg.waitFor({ state: 'detached' });
  h0 = await steps();
  await page.keyboard.press('Control+s');
  await page.waitForFunction(() => (__maker.draft.periods[0].leaders || []).length === 3);
  const third = (await raw()).periods[0].leaders[2];
  check(third.name === '셋째 임금' && JSON.stringify(third.accession) === JSON.stringify({ kin: 'younger-brother', how: 'usurpation' }) && third.parents && third.parents[0].as === 'father' && (third.parents[0].who === '가람 나라:첫 임금@1400' || (third.parents[0].who && third.parents[0].who.leader === '첫 임금')), '저장하면 작업본 지도자 칸에 승계(accession) · 부(parents)', third);
  check((await steps()) === h0 + 1, '편집 창 저장 = 한 걸음');
  await undo();
  check((await raw()).periods[0].leaders.length === 2, '되돌리기 — 지도자 둘');
  await page.keyboard.press('Escape');

  /* ========== ④ 머리 칩 고치기 ========== */
  const editHead = (o, anchorSel) => page.evaluate(([o, sel]) => { window.__headDone = HT.maker.kin.editHead(Object.assign({}, o, sel ? { anchor: document.querySelector(sel) } : {})); return true; }, [o, anchorSel]);
  const headDone = () => page.evaluate(() => window.__headDone);
  const per = async () => (await raw()).periods[0];
  /* 민족: 고르기에서 아래 단계 고르기 */
  await page.evaluate(() => { const b = document.createElement('button'); b.id = 'chipStandIn'; b.textContent = '누리족'; b.style.cssText = 'position:fixed;left:900px;top:300px'; document.body.append(b); });
  h0 = await steps();
  await editHead({ kind: 'polity', uid: `${OWN}/garam`, field: 'people' }, '#chipStandIn');
  await page.waitForSelector('.mk-kin-pop [data-pop-pick]');
  await page.screenshot({ path: path.join(output, '머리-칩-민족-1920-1배.png') });
  check(await page.evaluate(() => !document.querySelector('.mk-kin-pop [placeholder]')), '칩 고르기에 회색 예시 글 없음');
  await page.click('.mk-kin-pop [data-pop-pick="누리 갈래"]');
  check((await headDone()) === true && (await per()).people === '누리 갈래' && (await steps()) === h0 + 1, '민족 칩 → 정권의 people(원래 칸) · 한 걸음', await per());
  await undo();
  check((await per()).people === '누리족', '되돌리기 한 번에 원래 민족');
  /* 트랙(구분) */
  await editHead({ kind: 'polity', uid: `${OWN}/garam`, field: 'track', value: 'dal' });
  await page.waitForTimeout(200);
  const asked = await page.locator('#mkAskDialog[open]').count();
  if (asked) await page.click('#mkAskDialog button[value="yes"]');
  check((await headDone()) === true && (await per()).track === 'dal', '구분 칩 → 정권의 트랙(구조 나무의 트랙 옮기기와 같은 길)', await per());
  await undo();
  check((await per()).track === 'garam', '되돌리기 — 트랙');
  /* 국가 이름: 가리키던 곳이 따라감 */
  await editHead({ kind: 'polity', uid: `${OWN}/garam`, field: 'name' }, '#chipStandIn');
  await page.waitForSelector('.mk-kin-pop [data-pop-val]');
  await page.fill('.mk-kin-pop [data-pop-val]', '가람 왕국');
  await page.press('.mk-kin-pop [data-pop-val]', 'Enter');
  check((await headDone()) === true && (await per()).name === '가람 왕국', '국가 이름 칩 → 정권의 name', (await per()).name);
  check((await fig('f-baram')).parents[0].who === '가람 왕국:첫 임금@1400', '이름을 바꾸면 그 나라를 가리키던 사람 참조도 따라감(renameReferences)', await fig('f-baram'));
  await undo();
  /* 꼬리표: 더하기 · ✕ 지우기 */
  await editHead({ kind: 'polity', uid: `${OWN}/garam`, field: 'tags', value: '통일 왕조' });
  check((await headDone()) === true && JSON.stringify((await per()).tags) === JSON.stringify(['통일 왕조']), '＋ 꼬리표 → periods[].tags', (await per()).tags);
  await editHead({ kind: 'polity', uid: `${OWN}/garam`, field: 'tags', remove: '통일 왕조' });
  check((await headDone()) === true && !('tags' in (await per())), '꼬리표 칩의 ✕ → 그 꼬리표를 뺌');
  await undo();
  await undo();
  /* 가문 구분 · 본관 성씨 · 꼬리표 */
  await editHead({ kind: 'house', uid: 'house:h-on', field: 'track' }, '#chipStandIn');
  await page.waitForSelector('.mk-kin-pop [data-pop-val]');
  const guessBtn = await page.locator('.mk-kin-pop [data-pop-guess]').count();
  if (guessBtn) await page.click('.mk-kin-pop [data-pop-guess]');
  else { await page.selectOption('.mk-kin-pop [data-pop-val]', 'garam'); await page.click('.mk-kin-pop [data-pop-ok]'); }
  check((await headDone()) === true && (await raw()).houses[0].track === 'garam', `가문 구분 칩 → houses[].track${guessBtn ? "('짐작 값을 적기')" : ''}`, (await raw()).houses[0]);
  if (!guessBtn) report.대역.push("가문 구분의 '짐작 값을 적기' 단추 — 모델의 trackAuto(W1)가 없어 고르기로 검사");
  await undo();
  await editHead({ kind: 'house', uid: 'house:h-on', field: 'seat', value: { seat: '새물', surname: '온' } });
  check((await headDone()) === true && (await raw()).houses[0].seat === '새물', '본관 성씨 칩 → 가문의 seat · surname', (await raw()).houses[0]);
  await undo();
  await editHead({ kind: 'house', uid: 'house:h-on', field: 'tags', value: '왕실' });
  check((await headDone()) === true && JSON.stringify((await raw()).houses[0].tags) === JSON.stringify(['왕실']), '가문 꼬리표 → houses[].tags', (await raw()).houses[0]);
  await undo();
  /* 남의 DLC 정권 → 패치 set · 남의 가문 → 알림(고치지 않음) */
  await editHead({ kind: 'polity', uid: `${NEAR}/ipo`, field: 'tags', value: '이웃 꼬리표' });
  d = await raw();
  const patch = d.patches.find(p => p.target === `${NEAR}/ipo`);
  check((await headDone()) === true && !!patch && JSON.stringify(patch.set.tags) === JSON.stringify(['이웃 꼬리표']), '남의 DLC 정권의 칩 → 패치 set', patch);
  await undo();
  await editHead({ kind: 'polity', uid: `${NEAR}/ipo`, field: 'people', value: '누리족' });
  d = await raw();
  check((await headDone()) === true && d.patches.some(p => p.target === `${NEAR}/ipo` && p.set.people === '누리족'), '남의 DLC 정권의 민족 → 패치 set.people', d.patches);
  await undo();
  const before = JSON.stringify(await raw());
  await editHead({ kind: 'house', uid: 'house:h-near', field: 'track', value: 'dal' });
  const toast = await page.evaluate(() => [...document.querySelectorAll('.toast, [role="status"]')].map(t => t.textContent).join(' | '));
  check((await headDone()) === false && JSON.stringify(await raw()) === before, '남의 DLC 가문은 고치지 않음(false)', toast.slice(0, 300));
  check(/다른 DLC의 가문/.test(toast), '남의 가문 — 알림 글', toast.slice(0, 300));

  /* 승계표 머리 칩(D1-W2)이 있으면 실제 칩 ✏️ · ＋ 꼬리표 · ✕로 — 없으면 결합 단계에서 */
  await page.evaluate(() => __openDetail(`kin-maker/garam`, { cell: 'succession' }));
  await page.waitForTimeout(400);
  if (await page.locator('#detail [data-kin-edit="people"]').count()) {
    await page.locator('#detail [data-kin-edit="people"]').first().click();
    await page.waitForSelector('.mk-kin-pop [data-pop-pick]');
    await page.click('.mk-kin-pop [data-pop-pick="누리 갈래"]');
    await page.waitForTimeout(300);
    check((await per()).people === '누리 갈래', '승계표 머리의 민족 칩 ✏️ → 고르기 → 정권의 people (W2 칩 → editHead)', await per());
    await undo();
    await page.evaluate(() => __openDetail(`kin-maker/garam`, { cell: 'succession' }));
    await page.waitForTimeout(300);
    await page.locator('#detail [data-kin-edit="tags"]').last().click();
    await page.waitForSelector('.mk-kin-pop [data-pop-val]');
    await page.fill('.mk-kin-pop [data-pop-val]', '통일 왕조');
    await page.press('.mk-kin-pop [data-pop-val]', 'Enter');
    await page.waitForTimeout(300);
    check(JSON.stringify((await per()).tags) === JSON.stringify(['통일 왕조']), '승계표 머리의 ＋ 꼬리표 → periods[].tags', (await per()).tags);
    await page.evaluate(() => __openDetail(`kin-maker/garam`, { cell: 'succession' }));
    await page.waitForTimeout(300);
    const del = page.locator('#detail [data-kin-tag-del="통일 왕조"]');
    if (await del.count()) {
      await del.first().click();
      await page.waitForTimeout(300);
      check(!('tags' in (await per())), '꼬리표 칩의 ✕ → 그 꼬리표를 뺌(W2 칩 → editHead remove)', await per());
      await undo();
    }
    await undo();
    await page.screenshot({ path: path.join(output, '승계표-머리-칩-1920-1배.png') });
  } else report.대역.push('승계표 머리 칩(✏️ · ＋ 꼬리표 · ✕ — D1-W2)이 아직 없어 editHead를 직접 불러 검사 — 결합 때 실제 칩으로');
  await page.keyboard.press('Escape');

  /* ========== ⑤ 적는 글 · 나무 · 상태 줄 · 짐작 딱지 · 가문 표 ========== */
  const refs = await page.evaluate(() => {
    const m = __state.model, K = HT.makerKin, env = { model: m, draftId: 'kin-maker', track: 'garam' };
    const baram = K.targetOfKey(m, 'f:kin-maker/f-baram');
    const king = K.targetOfKey(m, 'c:kin-maker/garam|leader:0');
    return {
      baram: K.whoRef(baram, env),
      baramDup: K.whoRef(baram, Object.assign({}, env, { extra: [{ id: 'x1', name: '바람대군', track: 'garam' }] })),
      king: K.whoRef(king, env),
      kingStrict: K.whoRef(king, Object.assign({}, env, { strict: true })),
      unknownNew: K.whoRef({ isNew: true, id: 'u1', name: '미상', track: 'garam' }, env),
    };
  });
  check(refs.baram === '바람대군' && refs.baramDup === 'f-baram', '7-4: 같은 트랙에 이름이 하나뿐이면 이름, 겹치면 인물 id', refs);
  check(refs.king === '첫 임금' && refs.kingStrict && refs.kingStrict.polity === '가람 나라' && refs.kingStrict.leader === '첫 임금' && refs.unknownNew === 'u1', '지도자 칸은 이름 · 칸 참조, 이름 미상은 늘 id', refs);
  /* 상태 줄 · 구조 나무 거르기 */
  const status = await page.evaluate(() => document.querySelector('#mkStatus').textContent);
  check(/띠 인물 0 · 계보 전용 2/.test(status), '상태 줄: 띠 인물 n · 계보 전용 n', status);
  await page.selectOption('.mk-tview [data-tfig]', 'hide');
  await page.waitForTimeout(150);
  const hideRows = await page.evaluate(() => document.querySelector('#mkTree [data-tgroup="figures"] small').textContent);
  await page.selectOption('.mk-tview [data-tfig]', 'only');
  await page.waitForTimeout(150);
  const onlyRows = await page.evaluate(() => document.querySelector('#mkTree [data-tgroup="figures"] small').textContent);
  check(hideRows === '0' && onlyRows === '2', '구조 나무의 인물 거르기: 계보 전용 숨기기 0 · 계보 전용만 2', { hideRows, onlyRows });
  await page.selectOption('.mk-tview [data-tfig]', 'all');
  if (w1) {
    await page.selectOption('.mk-tview [data-tview]', 'house');
    await page.waitForTimeout(250);
    const kinGroups = await page.evaluate(() => [...document.querySelectorAll('#mkTree [data-tgroup$=":kin"]')].map(b => b.textContent));
    check(kinGroups.length >= 1, "'가문(국성)으로' 보기: 계보 전용 인물은 가문(파) 가지 아래 '계보 전용' 묶음(처음엔 접힘)", kinGroups);
    await page.selectOption('.mk-tview [data-tview]', 'kind');
  } else report.대역.push("'가문(국성)으로' 보기의 계보 전용 묶음 — 사람 자리의 가문(houseId · W1)이 있어야 함");
  /* 가문 표: 새 열 · 짐작 딱지 · 시조 찾기 상자 */
  await page.selectOption('[data-grid-list]', 'houses');
  await page.waitForTimeout(200);
  const heads = await page.evaluate(() => [...document.querySelectorAll('.mk-grid-head [data-grid-sort]')].map(b => b.textContent.trim()));
  check(['구분(트랙)', '민족', '꼬리표'].every(l => heads.includes(l)), '가문 표의 새 열: 구분(트랙) · 민족 · 꼬리표', heads);
  const guesses = await page.evaluate(() => [...document.querySelectorAll('.mk-grid-rows .mk-guess')].map(g => g.textContent));
  if (w1 && (await page.evaluate(() => !!(__state.model.houseMap.get('h-on') || {}).trackAuto))) check(guesses.some(g => /^짐작: 가람$/.test(g)), "비운 구분은 '짐작: 가람' 딱지(회색 예시 글이 아님)", guesses);
  else report.대역.push("가문 표의 '짐작: …' 딱지 — 모델의 trackAuto · peopleAuto(W1)가 있어야 함");
  check(await page.evaluate(() => !document.querySelector('.mk-grid input[placeholder], .mk-kin-pop input[placeholder], .mk-kin-dlg [placeholder]')), '새 입력 칸에 회색 예시 글 없음');
  const founderIdx = heads.indexOf('시조');
  await page.dblclick(`[data-grid-cell="0:${founderIdx}"]`);
  await page.keyboard.press('Control+a');
  await page.keyboard.type('바람대');
  await page.waitForTimeout(150);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(250);
  check((await raw()).houses[0].founder === 'f-baram', "가문 표의 시조 칸: 찾기 상자로 고르면 id로(파조 · 시조는 늘 id — 2-4 라)", (await raw()).houses[0]);
  await undo();
  await page.screenshot({ path: path.join(output, '가문-표-1920-1배.png') });
  /* 바탕 자료 창(가져오기 · 문서 도구)의 가문 표도 같은 열 — 구분 고르기 · 짐작 딱지 · 시조 칸 찾기 상자 */
  await page.evaluate(() => __maker.openBase && document.querySelector('[data-grid-base-tools]').click());
  await page.waitForSelector('#mkBaseWin:not([hidden]) table[data-list="houses"]');
  const baseWin = await page.evaluate(() => {
    const t = document.querySelector('#mkBaseWin table[data-list="houses"]');
    return { select: !!t.querySelector('select[name="track"]'), guess: [...t.querySelectorAll('.mk-guess')].map(g => g.textContent), founder: !!t.querySelector('input[name="founder"][data-person-col]'), tags: !!t.querySelector('input[name="tags"]'), people: (t.querySelector('input[name="people"]') || {}).getAttribute?.('list') };
  });
  check(baseWin.select && baseWin.founder && baseWin.tags && baseWin.people === 'mkBaseHousePeopleList', '바탕 자료 창의 가문 표: 구분 고르기 · 민족(자동 완성) · 꼬리표 · 시조 찾기 상자', baseWin);
  if (w1) check(baseWin.guess.includes('짐작: 가람'), "바탕 자료 창에도 '짐작: …' 딱지", baseWin.guess);
  h0 = await steps();
  await page.selectOption('#mkBaseWin table[data-list="houses"] select[name="track"]', 'dal');
  await page.waitForTimeout(500);
  check((await raw()).houses[0].track === 'dal', '바탕 자료 창에서 구분을 고르면 houses[].track', (await raw()).houses[0]);
  await undo();
  check(!('track' in (await raw()).houses[0]), '되돌리기 — 구분 비움', (await raw()).houses[0]);
  await page.evaluate(() => document.querySelector('#mkBaseWin [data-win-close]').click());

  /* 가문의 민족 · 구분은 민족 이름 · 트랙 id를 바꾸면 따라감(바탕 자료의 참조 길 — PEOPLE_REFS · 트랙 refs) */
  const follow = await page.evaluate(() => {
    const kit = HT.makerKit, d = JSON.parse(JSON.stringify(__maker.draft));
    d.houses[0].people = '누리족';
    d.houses[0].track = 'garam';
    const a = kit.renameRefs(d, kit.BASE_TABLES.peoples, 'name', '누리족', '누리 겨레');
    const b = kit.renameRefs(d, kit.BASE_TABLES.tracks, 'id', 'garam', 'garam2');
    return { a, b, people: d.houses[0].people, track: d.houses[0].track, users: kit.findUsers(__maker.draft, kit.BASE_TABLES.peoples, { id: 'nuri', name: '누리족' }).length };
  });
  check(follow.people === '누리 겨레' && follow.track === 'garam2', '가문의 민족 · 구분은 민족 이름 · 트랙 id를 바꾸면 따라감', follow);

  /* 큰 입력(수천 줄)에서도 줄 수에 비례하는지 — 계층 글 5천 줄 계획 · 줄 이어 두기, 인물 표 3천 줄 붙여넣기(부를 같은 붙여넣기 안의 이름으로) 계획 */
  const perf = await page.evaluate(() => {
    const K = HT.makerKin, m = __state.model, d = __maker.draft;
    const lines = [];
    for (let i = 0; i < 5000; i++) lines.push('  '.repeat(Math.min(i % 40, 39)) + `가상${i % 97}호 (${1500 + (i % 300)} ~)`);
    let t = performance.now();
    const plan = K.planOutline({ model: m, draft: d, lines, keys: [], root: null, orig: new Map() });
    const tPlan = performance.now() - t;
    t = performance.now();
    const removed = new Map();
    const keys = K.remapKeys(lines, lines.map((l, i) => `k${i}`), lines.map(l => l + ' '), removed);
    const tRemap = performance.now() - t;
    const writes = [];
    for (let i = 0; i < 3000; i++) { writes.push({ row: 2 + i, key: 'name', text: `가상${i}` }); writes.push({ row: 2 + i, key: 'kin:father', text: i ? `가상${Math.floor((i - 1) / 2)}` : '솔군' }); }
    t = performance.now();
    const g = HT.makerGrid.plan(d, { list: 'figures' }, writes, m, __state.packs);
    const tGrid = performance.now() - t;
    return { tPlan: Math.round(tPlan), tRemap: Math.round(tRemap), tGrid: Math.round(tGrid), add: plan.ops.add.length, errors: plan.errors.length, kept: keys.filter(Boolean).length, gridAdded: g.added, gridErrors: g.errors.length, sample: g.draft.figures.slice(-1)[0] };
  });
  report.성능 = perf;
  check(perf.add === 5000 && perf.errors === 0 && perf.kept === 5000 && perf.gridAdded === 3000 && perf.gridErrors === 0, '큰 입력: 계층 글 5천 줄 · 인물 표 3천 줄 계획이 오류 없이', perf);
  check(perf.tPlan < 4000 && perf.tRemap < 1000 && perf.tGrid < 6000, '큰 입력도 줄 수에 비례(계획 5천 줄 · 줄 잇기 · 표 3천 줄 — 이차 시간 없음)', perf);

  /* 검사 창의 알림(덩어리 상한) — 계산만 */
  const notes = await page.evaluate(() => {
    const persons = Array.from({ length: 50001 }, () => ({ houseId: 'h-on' }));
    return HT.makerKin.checks({ persons, houseMap: __state.model.houseMap }, __maker.draft).map(n => n.msg);
  });
  check(notes.length === 1 && /덩어리 상한/.test(notes[0]), '검사 창: 한 뿌리 가문이 5만 명을 넘으면 알림(새 앱에는 파별로)', notes);

  check(JSON.stringify((await raw()).figures) === JSON.stringify(draft.figures) && JSON.stringify((await raw()).houses) === JSON.stringify(draft.houses) && JSON.stringify((await raw()).periods) === JSON.stringify(draft.periods), '모든 되돌리기 뒤 작업본이 처음과 같음');
  await context.close();
  check(report.오류.length === 0, '브라우저 오류 없음', report.오류);
} finally {
  fs.writeFileSync(path.join(output, 'maker-kin-check.json'), JSON.stringify(report, null, 2));
  await browser.close();
  server.close();
}
console.log(JSON.stringify({ 검사: report.검사.length, 대역: report.대역, 오류: report.오류 }));
