/* 메이커 구조 나무의 '놓아서 채우기'(docs/구상-연표-확장-10건.md 3-4 (나))를 실제 브라우저 · 실제 포인터로 검사합니다.
   node scripts/maker-tree-drop-check.mjs <검사할 폴더> <결과 폴더>
   가상 작업본(트랙 셋 · 민족 나무 · 나라 · 가문 · 대범위 · 사건 · 인물)과 가상 이웃 팩 하나를 독립 브라우저의 저장소에만 넣고,
   보기 갈래(민족으로 · 소속으로 · 가문으로 · 대범위로 · 종류별)마다 줄을 끌어 놓아 people · partOf · house · scopes 구성원 · track · order가 바뀌는지,
   되돌리기 한 번에 돌아오는지, 남의 항목은 덮어쓰기(patches)로 적히는지, 놓을 수 없는 곳은 까닭 글과 함께 막히는지, 키보드 '옮기기…'가 같은 결과인지 봅니다.
   끄는 동안의 꼴은 메이커 안 끌기 한 꼴(10건 D3 결정 3 C — js/maker-drag.js HT.makerDrag.slot): 끄는 줄은 접혀 빠지고 놓을 곳에 빈 자리(.mk-slot)가 열려
   그 안에 미리 글, 놓을 수 없는 곳은 빈 자리 없이 손 밑 사본(.mk-dnd-ghost) 아래에 까닭 글 — 예전 커서 곁 풍선(.mk-drop-tip) 대신 여기서 글을 읽습니다.
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)로 고릅니다 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/구조-나무-놓기');
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
      bytes = Buffer.from(text.replace(marker, marker + ' window.__maker = maker; window.__state = state;'));
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));

/* 가상 자료 — 실제 역사 이름 없음 */
const OWN = 'tree-drop';
const NEAR = 'tree-neighbor';
const draft = {
  format: 'history-timeline-dlc', formatVersion: 2, id: OWN, name: '가상 나무 검사', version: '1.0.0', author: '', description: '',
  tracks: [{ id: 'sol', name: '솔나라 땅', order: 10 }, { id: 'dal', name: '달내 땅', order: 20 }, { id: 'gang', name: '강마을', order: 30 }],
  categories: [],
  peoples: [{ id: 'p-east', name: '동쪽 무리' }, { id: 'p-east-a', name: '동쪽 가람', parent: '동쪽 무리' }, { id: 'p-east-b', name: '동쪽 메', parent: '동쪽 무리' }, { id: 'p-west', name: '서쪽 무리' }],
  houses: [{ id: 'h-pine', name: '솔 가문' }, { id: 'h-pine-2', name: '솔 가문 작은집', parent: 'h-pine' }],
  periods: [
    { id: 'gap', track: 'sol', name: '갑 왕국', start: 100, end: 400, people: '동쪽 가람' },
    { id: 'eul', track: 'sol', name: '을 왕국', start: 150, end: 500, people: '동쪽 가람' },
    { id: 'byeong', track: 'sol', name: '병 나라', start: 200, end: 300, people: '서쪽 무리' },
    { id: 'jeong', track: 'sol', name: '정 성읍', start: 220, end: 380 },
    { id: 'mu', track: 'dal', name: '무 왕국', start: 300, end: 600, people: '동쪽 메' },
    { id: 'gi', track: 'gang', name: '기슭 마을', start: 320, end: 520 },
  ],
  events: [{ id: 'e1', track: 'sol', title: '봄맞이 잔치', start: 150, polity: '갑 왕국' }],
  figures: [{ id: 'f1', track: 'sol', name: '가온', birth: 120, death: 180, service: [{ polity: '갑 왕국', start: 140, end: 170 }] }],
  scopes: [{ id: 's-league', track: 'sol', name: '솔 동맹', members: ['갑 왕국', '정 성읍'] }],
  epochs: [], organs: [], cultures: [], dynasties: [], patches: [], rankDefs: [], documents: {}, requires: [],
};
const near = {
  format: 'history-timeline-dlc', formatVersion: 2, id: NEAR, name: '가상 이웃 팩', version: '1.0.0',
  tracks: [{ id: 'sol', name: '솔나라 땅' }], peoples: [],
  periods: [{ id: 'ki', track: 'sol', name: '키 나라', start: 250, end: 450, people: '서쪽 무리' }],
  scopes: [{ id: 's-near', track: 'sol', name: '이웃 연합', members: ['키 나라'] }],
  events: [],
};

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
  await context.addInitScript(({ draft, near, OWN, NEAR }) => {
    if (sessionStorage.getItem('tree-drop-seeded')) return;
    sessionStorage.setItem('tree-drop-seeded', '1');
    localStorage.clear();
    localStorage.setItem('ht.packs.installed', JSON.stringify([near]));
    localStorage.setItem('ht.maker.draft', JSON.stringify(draft));
    localStorage.setItem('ht.maker.refs', JSON.stringify({ [OWN]: [{ id: NEAR, show: true, locked: false }] }));
    localStorage.setItem('ht.maker.tree', JSON.stringify({ view: 'people', ref: true }));
  }, { draft, near, OWN, NEAR });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => m.type() === 'error' && report.오류.push(m.text()));
  await page.goto('http://127.0.0.1:' + server.address().port + '/dlc-maker.html');
  await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden && document.querySelector('#mkTree [data-tuid="tree-drop/gap"]'));
  await page.waitForTimeout(300);

  /* 도우미 */
  const raw = () => page.evaluate(() => JSON.parse(JSON.stringify(__maker.draft)));
  const per = async id => (await raw()).periods.find(p => p.id === id);
  const steps = () => page.evaluate(() => __maker.history.index);
  const rowSel = uid => `#mkTree [data-tuid="${uid}"]`;
  const headSel = key => `#mkTree [data-tgroup="${key}"]`;
  const box = async sel => {
    const el = page.locator(sel).first();
    await el.scrollIntoViewIfNeeded();
    const b = await el.boundingBox();
    assert.ok(b, `${sel}가 화면에 없음`);
    return b;
  };
  /** 실제 포인터로 끌어 놓기: from 줄의 가운데 → to의 (위쪽 · 가운데 · 아래쪽). 놓기 직전의 미리 글과 놓을 곳 표시를 돌려줌.
      끄는 줄이 접히며 아래 줄이 올라오므로(빈 자리 꼴) 접히는 움직임이 끝난 뒤 놓을 곳의 자리를 잽니다 */
  async function dragTo(from, to, { at = 'mid', ctrl = false, shot = '' } = {}) {
    const a = await box(from);
    await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
    await page.mouse.down();
    await page.mouse.move(a.x + a.width / 2 + 3, a.y + a.height / 2 + 8, { steps: 3 });
    await page.waitForTimeout(450);
    if (ctrl) await page.keyboard.down('Control');
    /* 지나가는 가지마다 빈 자리가 열리고 닫히며 줄이 비켜나므로, 움직임이 끝난 뒤 놓을 곳을 다시 재어 그 위로 (사람이 눈으로 맞추듯 — 세 번까지) */
    for (let i = 0; i < 3; i++) {
      const b = await box(to);
      const y = at === 'top' ? b.y + 4 : at === 'bottom' ? b.y + b.height - 4 : b.y + b.height / 2;
      await page.mouse.move(b.x + Math.min(60 + i, b.width / 2), y, { steps: i ? 2 : 8 });
      await page.waitForTimeout(450);
      const on = await page.evaluate(sel => { const el = document.querySelector(sel); return !!el && [...el.classList].some(c => /^is-(no)?drop/.test(c)); }, to);
      if (on) break;
    }
    const seen = await page.evaluate(sel => {
      const slot = document.querySelector('#mkTree .mk-slot:not(.is-closing)');
      const ghost = document.querySelector('.mk-dnd-ghost');
      const why = ghost && !ghost.hidden ? (ghost.querySelector('.mk-dnd-why') || {}).textContent || '' : '';
      return {
        tip: slot ? slot.querySelector('.mk-slot-pre span').textContent : why,
        no: !slot && !!ghost && !ghost.hidden && ghost.classList.contains('is-no'),
        slot: !!slot,
        dragging: document.querySelectorAll('#mkTree .is-dragging').length,
        mark: [...(document.querySelector(sel)?.classList || [])].filter(c => /^is-(no)?drop/.test(c)).join(' '),
      };
    }, to);
    if (shot) {
      await page.waitForTimeout(450); // 빈 자리가 다 열린 뒤
      await page.screenshot({ path: path.join(output, shot) });
    }
    await page.mouse.up();
    if (ctrl) await page.keyboard.up('Control');
    await page.waitForTimeout(120);
    return seen;
  }
  const undo = async () => {
    await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(120);
  };
  const setView = async v => {
    await page.selectOption('.mk-tview [data-tview]', v);
    await page.waitForTimeout(120);
  };

  /* ---------- 민족으로 ---------- */
  check(await page.locator(headSel('v:people:sol:p-east-b')).count() === 1, '민족으로: 나라가 없는 하위 민족(동쪽 메)도 그 트랙의 가지로 보임');
  check(await page.locator(rowSel(`${NEAR}/ki`)).count() === 1, '불러온 팩도: 이웃 팩의 나라가 나무에 보임');
  let h0 = await steps();
  let seen = await dragTo(rowSel(`${OWN}/byeong`), headSel('v:people:sol:p-east-b'), { shot: '민족으로-끄는-중-1920-1배.png' });
  check(seen.tip === '놓으면: 민족 → 동쪽 메 (1개)', '끄는 동안 미리 글: 놓으면: 민족 → 동쪽 메 (1개)', seen);
  check(seen.dragging >= 1 && /is-drop/.test(seen.mark) && seen.slot, '끄는 줄은 is-dragging(접혀 빠짐) · 놓을 곳은 is-drop · 그 가지에 빈 자리(미리 글은 빈 자리 안)', seen);
  check((await per('byeong')).people === '동쪽 메', '나라 줄을 민족 가지에 놓으면 people이 그 민족', await per('byeong'));
  check((await steps()) === h0 + 1, '놓기 한 번 = 되돌리기 한 걸음');
  await undo();
  check((await per('byeong')).people === '서쪽 무리', '되돌리기 한 번에 원래 민족으로', await per('byeong'));

  /* 여러 줄을 고른 채 끌기 */
  await page.locator(rowSel(`${OWN}/gap`)).click();
  await page.locator(rowSel(`${OWN}/jeong`)).click({ modifiers: ['Control'] });
  await page.waitForTimeout(100);
  h0 = await steps();
  seen = await dragTo(rowSel(`${OWN}/gap`), headSel('v:people:sol:p-east'));
  check(seen.tip === '놓으면: 민족 → 동쪽 무리 (2개)', '여러 줄: 미리 글에 개수(2개) · 위 단계 민족', seen);
  check((await per('gap')).people === '동쪽 무리' && (await per('jeong')).people === '동쪽 무리', '여러 줄이 함께 위 단계 민족으로', [await per('gap'), await per('jeong')]);
  check((await steps()) === h0 + 1, '여러 줄도 되돌리기 한 걸음');
  await undo();
  check((await per('gap')).people === '동쪽 가람' && !('people' in (await per('jeong'))), '되돌리기 한 번에 둘 다 돌아옴');

  /* 민족 없음 = 비움 */
  await page.locator(rowSel(`${OWN}/eul`)).click();
  seen = await dragTo(rowSel(`${OWN}/eul`), headSel('v:people:sol:-'));
  check(seen.tip === '놓으면: 민족 비움 (1개)' && !('people' in (await per('eul'))), "'민족 없음'에 놓으면 people을 지움", seen);
  await undo();

  /* 남의 항목 → 덮어쓰기 */
  const nearBefore = await page.evaluate(() => JSON.stringify(__state.packs.find(p => p.id === 'tree-neighbor').periods));
  seen = await dragTo(rowSel(`${NEAR}/ki`), headSel('v:people:sol:p-east-a'));
  let d = await raw();
  const patch = d.patches.find(p => p.target === `${NEAR}/ki`);
  check(!!patch && patch.set && patch.set.people === '동쪽 가람' && Object.keys(patch.set).length === 1, '남의 나라는 바뀐 칸만 덮어쓰기(patches[].set.people)', patch);
  check(!d.periods.some(p => p.name === '키 나라'), '남의 나라를 내 목록에 복사하지 않음');
  check((await page.evaluate(() => JSON.stringify(__state.packs.find(p => p.id === 'tree-neighbor').periods))) === nearBefore, '남의 팩 원본은 그대로');
  await undo();
  check(!(await raw()).patches.some(p => p.target === `${NEAR}/ki`), '되돌리기 한 번에 덮어쓰기가 사라짐');

  /* ＋ 민족: 이름만 치면 그 가지 아래에 */
  await page.hover(headSel('v:people:sol:p-east'));
  await page.locator(`.mk-tgh:has(> ${headSel('v:people:sol:p-east').replace('#mkTree ', '')}) .mk-tadd`).click();
  const ph = await page.locator('.mk-tnew input').getAttribute('placeholder');
  check(ph === null, "'＋ 민족' 이름 칸에 회색 예시 글(placeholder)이 없음");
  await page.keyboard.type('동쪽 들');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  d = await raw();
  const born = d.peoples.find(p => p.name === '동쪽 들');
  check(!!born && born.parent === '동쪽 무리', "'＋ 민족': peoples에 더해지고 상위 민족이 그 가지", born);
  check(born && (await page.locator(headSel(`v:people:sol:${born.id}`)).count()) === 1, '새 민족이 그 가지 아래 나무에 바로 생김', await page.evaluate(() => [...document.querySelectorAll('#mkTree [data-tgroup]')].map(e => e.dataset.tgroup)));
  seen = await dragTo(rowSel(`${OWN}/jeong`), headSel(`v:people:sol:${born.id}`));
  check((await per('jeong')).people === '동쪽 들', '새 민족 가지에 놓기', seen);
  await undo();
  await undo();
  check(!(await raw()).peoples.some(p => p.name === '동쪽 들'), '되돌리기로 새 민족도 사라짐');

  /* 트랙 옮기기 (딸린 것 확인 글) */
  h0 = await steps();
  seen = await dragTo(rowSel(`${OWN}/mu`), headSel('v:people:gang'));
  check(seen.tip === '놓으면: 트랙 → 강마을 (1개)' && (await per('mu')).track === 'gang', '트랙 머리에 놓으면 트랙을 옮김(딸린 것이 없으면 묻지 않음)', seen);
  await undo();
  check((await per('mu')).track === 'dal', '되돌리기로 트랙이 돌아옴');
  h0 = await steps();
  seen = await dragTo(rowSel(`${OWN}/gap`), headSel('v:people:dal'));
  await page.locator('#mkAskDialog[open]').waitFor();
  const askText = await page.locator('#mkAskText').textContent();
  check(/사건 1개/.test(askText) && /섬긴 인물 1명/.test(askText), '트랙 옮기기: 딸린 사건 · 인물을 어떻게 할지 묻는 글', askText);
  check((await page.locator('#mkAskNo').getAttribute('class')) === 'btn', "'나라만 옮기기'는 붉은 단추가 아님");
  await page.locator('#mkAskYes').click();
  await page.waitForTimeout(150);
  d = await raw();
  check(d.periods.find(p => p.id === 'gap').track === 'dal' && d.events.find(e => e.id === 'e1').track === 'dal', '함께 옮기기: 나라와 그 사건이 새 트랙으로', [d.periods.find(p => p.id === 'gap'), d.events[0]]);
  check(d.figures[0].service[0].track === 'dal', '함께 옮기기: 섬긴 인물의 활동 기록이 새 트랙의 그 나라를 가리킴', d.figures[0]);
  check(JSON.stringify(d.scopes[0].members) === JSON.stringify(['정 성읍']), '옛 트랙의 대범위에서는 뺌', d.scopes[0]);
  check((await steps()) === h0 + 1, '트랙 옮기기(딸린 것까지)도 되돌리기 한 걸음');
  await undo();
  d = await raw();
  check(d.periods.find(p => p.id === 'gap').track === 'sol' && d.events[0].track === 'sol' && !('track' in d.figures[0].service[0]) && d.scopes[0].members.length === 2, '되돌리기 한 번에 나라 · 사건 · 인물 · 대범위가 모두 돌아옴', d.scopes[0]);

  /* 차례(order): 트랙 머리끼리 · 다른 팩이 정한 트랙은 막힘 */
  seen = await dragTo(headSel('v:people:gang'), headSel('v:people:dal'), { at: 'top' });
  d = await raw();
  check(/차례 — «달내 땅» 앞으로/.test(seen.tip) && /is-drop-before/.test(seen.mark), '트랙 머리끼리 끌기: 미리 글 · 앞에 놓을 줄 표시', seen);
  check(d.tracks.find(t => t.id === 'gang').order < d.tracks.find(t => t.id === 'dal').order, '트랙 머리끼리 끌면 order가 바뀜', d.tracks);
  const order = await page.evaluate(() => [...document.querySelectorAll('#mkTree [data-tgroup^="v:people:"]')].map(e => e.dataset.tgroup).filter(k => k.split(':').length === 3));
  check(order.indexOf('v:people:gang') < order.indexOf('v:people:dal'), '나무에서도 트랙 차례가 바뀜', order);
  await undo();
  seen = await dragTo(headSel('v:people:sol'), headSel('v:people:dal'), { at: 'top' });
  check(seen.no && /다른 팩이 정한 트랙/.test(seen.tip), '다른 팩이 먼저 정한 트랙은 차례를 바꿀 수 없음(까닭 글)', seen);
  /* 민족 머리끼리 (같은 부모 아래) */
  const before = await page.evaluate(() => [...document.querySelectorAll('#mkTree [data-tgroup^="v:people:sol:p-east-"]')].map(e => e.dataset.tgroup));
  seen = await dragTo(headSel('v:people:sol:p-east-b'), headSel('v:people:sol:p-east-a'), { at: 'top' });
  const after = await page.evaluate(() => [...document.querySelectorAll('#mkTree [data-tgroup^="v:people:sol:p-east-"]')].map(e => e.dataset.tgroup));
  check(after.indexOf('v:people:sol:p-east-b') < after.indexOf('v:people:sol:p-east-a') && before.indexOf('v:people:sol:p-east-b') > before.indexOf('v:people:sol:p-east-a'), '같은 부모 아래 민족끼리 끌면 차례가 바뀜', { before, after, seen });
  check(typeof (await raw()).peoples.find(p => p.id === 'p-east-b').order === 'number', '민족의 order가 적힘');
  await undo();
  seen = await dragTo(headSel('v:people:sol:p-east-b'), headSel('v:people:sol:p-west'), { at: 'top' });
  check(seen.no && /같은 부모/.test(seen.tip), '부모가 다른 민족 사이에는 차례를 바꿀 수 없음(까닭 글)', seen);
  /* 키보드: 머리에서 Alt+↑ */
  h0 = await steps();
  await page.locator(headSel('v:people:gang')).focus();
  await page.keyboard.press('Alt+ArrowUp');
  await page.waitForTimeout(150);
  d = await raw();
  check(d.tracks.find(t => t.id === 'gang').order < d.tracks.find(t => t.id === 'dal').order && (await steps()) === h0 + 1, '트랙 머리에서 Alt+↑ = 한 칸 위로(끌기와 같은 결과)', d.tracks);
  await undo();

  /* 키보드: 오른쪽 클릭 ▸ 옮기기… → 갈 곳 목록 */
  await page.locator(rowSel(`${OWN}/byeong`)).click();
  await page.locator(rowSel(`${OWN}/byeong`)).click({ button: 'right' });
  await page.locator('#ctxMenu .ctx-item', { hasText: '옮기기…' }).click();
  await page.locator('dialog.mk-move[open]').waitFor();
  check((await page.locator('dialog.mk-move [data-move-find]').getAttribute('placeholder')) === null, "'옮기기…'의 찾기 칸에 회색 예시 글이 없음");
  await page.keyboard.type('동쪽 메');
  await page.screenshot({ path: path.join(output, '옮기기-1920-1배.png') });
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  check((await per('byeong')).people === '동쪽 메', "키보드 길(오른쪽 클릭 ▸ 옮기기… ▸ 갈 곳)이 끌어 놓기와 같은 결과", await per('byeong'));
  await undo();

  /* ---------- 소속으로 ---------- */
  await setView('partOf');
  seen = await dragTo(rowSel(`${OWN}/eul`), rowSel(`${OWN}/gap`));
  check(/소속 → 갑 왕국 \(1개\)/.test(seen.tip), '소속으로: 나라 위에 놓을 때 미리 글', seen);
  await page.locator('#ctxMenu:not([hidden])').waitFor();
  await page.locator('#ctxMenu .ctx-item', { hasText: '괴뢰국' }).click();
  await page.waitForTimeout(150);
  check(JSON.stringify((await per('eul')).partOf) === JSON.stringify([{ polity: '갑 왕국', relation: 'puppet' }]), '놓을 때 고른 관계로 partOf(상위 하나 · 기간 없음)', await per('eul'));
  await page.screenshot({ path: path.join(output, '소속으로-1920-1배.png') });
  check((await page.locator(`${rowSel(`${OWN}/gap`)} ~ ${rowSel(`${OWN}/eul`).replace('#mkTree ', '')}`).count()) === 1, '소속으로: 그 나라 줄 아래로 들어감');
  seen = await dragTo(rowSel(`${OWN}/eul`), headSel('v:partOf:sol:-'));
  check(seen.tip === '놓으면: 소속 지움 (1개)' && !('partOf' in (await per('eul'))), "'소속 없음'에 놓으면 소속을 지움", seen);
  await undo();
  await undo();
  seen = await dragTo(rowSel(`${OWN}/mu`), rowSel(`${OWN}/gap`));
  check(seen.no && /같은 트랙이 아님/.test(seen.tip) && !('partOf' in (await per('mu'))), '다른 트랙의 나라 위에는 놓을 수 없음(까닭 글 · 바뀌지 않음)', seen);
  seen = await dragTo(rowSel(`${OWN}/byeong`), rowSel(`${OWN}/gap`));
  await page.locator('#ctxMenu .ctx-item', { hasText: '관계 없음' }).click();
  await page.waitForTimeout(150);
  check((await per('byeong')).partOf === '갑 왕국', "'관계 없음'은 글 하나(접히는 소속)", await per('byeong'));
  seen = await dragTo(rowSel(`${OWN}/gap`), rowSel(`${OWN}/byeong`));
  check(seen.no && /제 아래 나라/.test(seen.tip), '제 아래 나라에 놓는 것(돌고 도는 소속)은 막힘', seen);
  await undo();
  /* 남의 나라의 소속 → 덮어쓰기 */
  seen = await dragTo(rowSel(`${NEAR}/ki`), rowSel(`${OWN}/jeong`));
  await page.locator('#ctxMenu .ctx-item', { hasText: '관계 없음' }).click();
  await page.waitForTimeout(150);
  const kiPatch = (await raw()).patches.find(p => p.target === `${NEAR}/ki`);
  check(kiPatch && kiPatch.set.partOf === '정 성읍', '남의 나라의 소속도 덮어쓰기로', kiPatch);
  await undo();

  /* ---------- 가문(국성)으로 ---------- */
  await setView('house');
  check((await page.locator(headSel('v:house:sol:h-pine-2')).count()) === 1, '가문으로: 아직 쓰이지 않은 제 가문(본가 → 분가)도 놓을 곳으로 보임');
  seen = await dragTo(rowSel(`${OWN}/gap`), headSel('v:house:sol:h-pine-2'));
  check(seen.tip === '놓으면: 국성 → 솔 가문 작은집 (1개)' && (await per('gap')).house === '솔 가문 작은집', '가문 가지에 놓으면 국성(house)', seen);
  await page.screenshot({ path: path.join(output, '가문으로-1920-1배.png') });
  seen = await dragTo(rowSel(`${OWN}/gap`), headSel('v:house:sol:-'));
  check(!('house' in (await per('gap'))), "'가문 없음'에 놓으면 국성을 지움", seen);
  await undo();
  await undo();

  /* ---------- 대범위로 ---------- */
  await setView('scope');
  seen = await dragTo(rowSel(`${OWN}/eul`), headSel(`v:scope:${OWN}/s-league`));
  d = await raw();
  check(seen.tip === '놓으면: 대범위 «솔 동맹»에 넣음 (1개)' && JSON.stringify(d.scopes[0].members) === JSON.stringify(['갑 왕국', '정 성읍', '을 왕국']), '대범위에 놓으면 구성 정권이 됨', d.scopes[0]);
  await page.screenshot({ path: path.join(output, '대범위로-1920-1배.png') });
  seen = await dragTo(`#mkTree [data-from="${OWN}/s-league"][data-tuid="${OWN}/eul"]`, headSel('v:scope:sol:-'));
  check(JSON.stringify((await raw()).scopes[0].members) === JSON.stringify(['갑 왕국', '정 성읍']), "대범위의 줄을 '대범위 없음'에 놓으면 그 대범위에서 뺌", seen);
  await undo();
  await undo();
  seen = await dragTo(rowSel(`${OWN}/eul`), headSel(`v:scope:${NEAR}/s-near`));
  check(seen.no && /남의 대범위/.test(seen.tip), '남의 대범위에는 놓을 수 없음(까닭 글)', seen);
  check(JSON.stringify((await raw()).scopes) === JSON.stringify(draft.scopes), '막힌 곳에 놓으면 아무것도 바뀌지 않음');

  /* ---------- 종류별(지금 나무): 트랙 묶음에 놓기 ---------- */
  await setView('kind');
  seen = await dragTo(rowSel(`${OWN}/mu`), headSel('periods:sol'));
  check(seen.tip === '놓으면: 트랙 → 솔나라 땅 (1개)' && (await per('mu')).track === 'sol', '종류별 나무의 트랙 묶음에 놓으면 트랙을 옮김', seen);
  await undo();
  check((await per('mu')).track === 'dal', '되돌리기');

  /* 마지막: 움직임 줄이기에서도 오류 없음 · 원래 작업본과 같음 */
  check(JSON.stringify((await raw()).periods) === JSON.stringify(draft.periods), '모든 되돌리기 뒤 시대 목록이 처음과 같음');
  await page.screenshot({ path: path.join(output, '종류별-끝-1920-1배.png') });
  await context.close();
  check(report.오류.length === 0, '브라우저 오류 없음', report.오류);
} finally {
  fs.writeFileSync(path.join(output, 'maker-tree-drop-check.json'), JSON.stringify(report, null, 2));
  await browser.close();
  server.close();
}
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류 }));
