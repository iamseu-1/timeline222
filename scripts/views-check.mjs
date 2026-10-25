/* 집합 보기(10건 6 — 설계 docs/설계-10건/6-모아-보기와-배치.md · 감독 선택 D4 결정 1~5)를 실제 브라우저 · 실제 포인터로 검사합니다.
   node scripts/views-check.mjs <검사할 폴더> <결과 폴더>
   ㉮ 연표(동아시아 기본팩 + 판만 담은 가상 DLC): 판이 없으면 독 단추가 숨음 · 목록의 스위치로 켜면 구성 나라의 줄이 통째로(같은 줄의 앞뒤 나라까지) 맨 위 판 트랙으로 ·
      나머지 트랙은 접힘 · 원래 트랙에는 빈 줄이 남지 않음 · 트랙 칩(같은 트랙이 이어지면 하나) · 테두리 가로 전체 · 이름표 · 기간 구간 · 날짜 칸 그대로 ·
      접힘 기억(ht.ui folded) 그대로 · 다시 열면 켠 판이 되살아남 · 끄면 켜기 전과 1px도 다르지 않음(같은 범위 · 같은 스크롤에서 찍은 1배 그림을 화소로 견줌)
   ㉯ 연표의 시대 구분 상세 '이 시대의 나라' 카드: 칩 빼기 · 다른 트랙 나라 · 스위치 = 저장하지 않은 임시 판(보기 설정에 남지 않음) · 연표에는 저장 · 고치기 길이 없음
   ㉰ 메이커: Ctrl+클릭 두 번 → 아래 가운데 '고른 나라' 막대(확대 단추와 겹치지 않음 · 입력 칸에 회색 예시 글 없음) → 이름 없이 저장은 막힘 → 이름을 적고 저장하면
      작업본 views에 "트랙:이름" 참조로 · 목록의 고치기(이름 · 차례) · 지우기 · 시대 구분 카드의 '집합 보기로 저장'(기간 함께)
   그림(모두 1920×1080 · 배율 1)은 결과 폴더에. 자료는 모두 독립 브라우저의 저장소에만 넣고, 가상 자료에는 실제 역사 이름을 쓰지 않습니다
   (동아시아 기본팩의 나라는 이름이 아니라 uid로만 가리킴). Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)로 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/집합-보기');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      let text = bytes.toString('utf8');
      const models = '/* ---------- 팩 & 모델 ---------- */';
      const started = 'if (maker) maker.start();';
      for (const marker of [models, started]) assert.equal(text.split(marker).length, 2, `viewer.js의 표시 줄 «${marker}»이 하나가 아님`);
      text = text.replace(models, 'window.__tl=timeline;window.__state=state;\n' + models).replace(started, started + ' window.__maker = maker;');
      bytes = Buffer.from(text);
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = 'http://127.0.0.1:' + server.address().port;

/* ---------- 가상 자료 (실제 역사 이름 없음) ---------- */
/* ㉮ 동아시아 기본팩의 네 나라를 uid로만 가리키는 판 (설계 판의 결정 1 · 2 그림과 같은 네 나라 · 같은 576 ~ 696년) */
const EA = ['east-asia-base/korea-px5wuj0', 'east-asia-base/china-pyjg4nx', 'east-asia-base/china-p3be0sd', 'east-asia-base/japan-p3tijct'];
const viewsDlc = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'views-check-a', name: '가상 집합 보기 묶음', version: '1.0.0',
  views: [
    { id: 'v-seven', name: '7세기 견주기', members: EA, start: 600, end: 650, color: '#d7c18e' },
    { id: 'v-two', name: '두 나라만', members: [EA[3], EA[0]] },
  ],
};
/* ㉯ · ㉰ 가상의 세 트랙 · 시대 구분 */
const fixture = (id, name) => ({
  format: 'history-timeline-dlc', formatVersion: 2, id, name, version: '1.0.0', author: '', description: '',
  tracks: [{ id: 'vc-sol', name: '솔내 땅', color: '#b6c398', order: 10 }, { id: 'vc-dal', name: '달메 바다', color: '#a0bcc5', order: 20 }, { id: 'vc-gang', name: '강마루 산', color: '#c8b193', order: 30 }],
  peoples: [{ id: 'pe-sol', name: '솔내 사람' }, { id: 'pe-dal', name: '달메 사람' }],
  periods: [
    { id: 'gap', track: 'vc-sol', name: '갑 왕국', start: 100, end: 400, people: '솔내 사람' },
    { id: 'eul', track: 'vc-sol', name: '을 왕국', start: 400, end: 700, people: '솔내 사람', succeeds: [{ from: '갑 왕국', type: 'direct' }] },
    { id: 'byeong', track: 'vc-sol', name: '병 나라', start: 250, end: 520, people: '솔내 사람' },
    { id: 'jeong', track: 'vc-dal', name: '정 연맹', start: 180, end: 560, people: '달메 사람' },
    { id: 'mu', track: 'vc-gang', name: '무 성읍', start: 300, end: 640 },
  ],
  events: [{ id: 'e1', track: 'vc-sol', polity: '갑 왕국', title: '봄맞이 잔치', start: 210, category: 'society' }],
  epochs: [{ id: 'ep-mid', track: 'vc-sol', name: '가운데 시대', start: 260, end: 480, color: '#d7c18e' }],
  organs: [], cultures: [], dynasties: [], patches: [], documents: {}, requires: [],
});

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100% · 배율 1', 검사: [], 오류: [], 마지막에확인할실패: [] };
const check = (ok, text, details, { defer = false } = {}) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  // PC의 화소 대조가 실패해도 나머지 기능 검사는 끝까지 남긴다. 기준은 그대로이며 마지막에 실패로 종료한다.
  if (!ok && defer) { report.마지막에확인할실패.push(text); return; }
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};
const newPage = async (seed, file, { reduce = true } = {}) => {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block', reducedMotion: reduce ? 'reduce' : 'no-preference' });
  await context.addInitScript(seed => {
    if (sessionStorage.getItem('views-check-seeded')) return;
    sessionStorage.setItem('views-check-seeded', '1');
    localStorage.clear();
    for (const [k, v] of Object.entries(seed)) localStorage.setItem(k, JSON.stringify(v));
  }, seed);
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(`${file}: ${e.message}`));
  page.on('console', m => m.type() === 'error' && report.오류.push(`${file}: ${m.text()}`));
  await page.goto(`${base}/${file}`);
  await page.waitForFunction(() => window.__tl && window.__state && window.__state.model);
  return page;
};
/** 정착까지 기다림 — 빈 줄 접힘(정착 300ms) · 높이 흐름(--t-move)이 모두 끝나게 */
const settle = page => page.waitForTimeout(1300);
const sig = page =>
  page.evaluate(() => ({
    tracks: __tl.tracks.map(tr => ({ id: tr.id, folded: !!tr.folded, rows: tr.rows, h: tr.height, rowsOf: (tr.rowPeriods || []).map(r => r.map(p => p.uid).join(',')), hidden: [...(tr.hiddenRows || [])].join(',') })),
    axis: [...document.querySelectorAll('.tl-group-btn')].map(b => b.textContent),
    gutter: __tl.gutter,
    scroll: __tl.bodyEl.scrollTop,
  }));
/** 두 1배 그림(PNG)의 화소 차이 — 브라우저의 캔버스로 풀어 견줌: { n: 다른 화소 수, box: [x0, y0, x1, y1] } */
async function pixelDiff(page, a, b) {
  return page.evaluate(
    async ([a, b]) => {
      const load = src => new Promise((ok, no) => { const im = new Image(); im.onload = () => ok(im); im.onerror = no; im.src = src; });
      const [ia, ib] = await Promise.all([load(a), load(b)]);
      const px = im => { const c = document.createElement('canvas'); c.width = im.width; c.height = im.height; const g = c.getContext('2d'); g.drawImage(im, 0, 0); return g.getImageData(0, 0, im.width, im.height).data; };
      const da = px(ia), db = px(ib);
      let n = 0, big = 0, x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1;
      const samples = [];
      for (let i = 0; i < da.length; i += 4) {
        if (da[i] === db[i] && da[i + 1] === db[i + 1] && da[i + 2] === db[i + 2]) continue;
        n++;
        if (Math.max(Math.abs(da[i] - db[i]), Math.abs(da[i + 1] - db[i + 1]), Math.abs(da[i + 2] - db[i + 2])) > 1) big++;
        const p = i / 4, x = p % ia.width, y = Math.floor(p / ia.width);
        if (samples.length < 12) samples.push({ x, y, before: [...da.slice(i, i + 4)], after: [...db.slice(i, i + 4)] });
        x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
      }
      return { n, big, box: n ? [x0, y0, x1, y1] : null, size: [ia.width, ia.height], ...(samples.length ? { samples } : {}) };
    },
    ['data:image/png;base64,' + a.toString('base64'), 'data:image/png;base64,' + b.toString('base64')],
  );
}
const rect = (page, sel) => page.evaluate(sel => { const el = document.querySelector(sel); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, r: r.right, b: r.bottom }; }, sel);
/** 판 트랙의 칩(원래 트랙 · 제 민족) 가운데 세로 글이 칩 밖으로 넘친 것 — 반쯤 잘린 글자 없게(앞 글자만 · 말줄임표 없음) */
const chipOverflow = page =>
  page.evaluate(() =>
    [...document.querySelectorAll('.tl-track.is-board .tl-people')]
      .filter(el => el.getBoundingClientRect().height > 0)
      .map(el => {
        const sp = el.querySelector('span');
        const r = document.createRange();
        r.selectNodeContents(sp);
        const t = r.getBoundingClientRect();
        const c = el.getBoundingClientRect();
        return { text: sp.textContent, ok: !sp.textContent.trim() || (t.top >= c.top - 0.5 && t.bottom <= c.bottom + 0.5 && t.height > 0) };
      })
      .filter(x => !x.ok),
  );
const overlap = (a, b) => !!a && !!b && a.x < b.r - 0.5 && b.x < a.r - 0.5 && a.y < b.b - 0.5 && b.y < a.b - 0.5;

try {
  /* ================= ㉮ 연표 — 동아시아 기본팩 + 판 DLC ================= */
  {
    /* 판이 없는 연표: 독 단추가 숨음 */
    const bare = await newPage({}, 'index.html');
    check(await bare.evaluate(() => document.getElementById('viewsBtn').hidden), '판이 하나도 없는 연표: 독의 집합 보기 단추가 숨음');
    await bare.context().close();

    const page = await newPage({ 'ht.packs.installed': [viewsDlc] }, 'index.html');
    const view = async () => {
      await page.evaluate(() => { __tl.setView(576, 696); __tl.bodyEl.scrollTop = 0; });
      await settle(page);
    };
    await view();
    const sig0 = await sig(page);
    const folded0 = await page.evaluate(() => JSON.stringify(__state.ui.folded || []));
    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    await page.mouse.move(2, 2); // 마우스가 올라간 칸의 밝힘이 그림에 들지 않게
    const shot0 = await page.screenshot();
    check(await page.evaluate(() => !document.getElementById('viewsBtn').hidden), '판을 담은 DLC를 켜면 독에 집합 보기 단추');
    const dock = await rect(page, '#dock');
    const btn = await rect(page, '#viewsBtn');
    check(btn.x >= dock.x && btn.r <= dock.r && btn.y >= dock.y && btn.b <= dock.b, '집합 보기 단추는 독 안 (넘치지 않음)', { dock, btn });

    /* 목록 → 스위치로 켜기 */
    await page.click('#viewsBtn');
    await page.waitForTimeout(200);
    const rows = await page.$$eval('.views-pop .vw-row', els => els.map(e => e.textContent.replace(/\s+/g, ' ').trim()));
    check(rows.length === 2 && /7세기 견주기/.test(rows[0]) && /나라 4 · 트랙 3/.test(rows[0]) && /가상 집합 보기 묶음/.test(rows[0]), '독 아래 목록: 판마다 스위치 · 이름 · 나라 수 · 트랙 수 · DLC 표시', rows);
    check((await page.$$('.views-pop [data-vw-edit], .views-pop [data-vw-del], .views-pop [data-vw-keep]')).length === 0, '연표(보기 전용)의 목록에는 고치기 · 지우기 · 저장이 없음');
    const pop = await rect(page, '.views-pop');
    check(pop.y >= dock.b && pop.r <= 1920 && pop.b <= 1080, '목록은 독 아래 · 화면 안', { dock, pop });
    await page.screenshot({ path: path.join(output, '연표-목록-1920-1배.png') });
    await page.click('.views-pop .vw-row:first-child [data-vw-toggle]');
    await page.waitForTimeout(150);
    await page.keyboard.press('Escape');
    await view();
    const on = await sig(page);
    const board = on.tracks[0];
    check(board.id === '__board' && board.rows === 4 && !board.folded, '켜면 맨 위에 판 트랙 하나(줄 4 — 구성 나라 넷이 각각 다른 줄)', board);
    /* 줄 통째: 판의 줄 = 켜기 전 그 나라가 놓였던 줄 그대로(같은 줄의 앞뒤 나라까지) */
    const rowOf = (s, uid) => { for (const t of s.tracks) for (const r of t.rowsOf) if (r.split(',').includes(uid)) return { track: t.id, row: r }; return null; };
    const whole = EA.map(uid => [rowOf(sig0, uid).row, rowOf(on, uid).row]);
    check(whole.every(([a, b]) => a === b) && board.rowsOf.join('|') === EA.map(uid => rowOf(sig0, uid).row).join('|'), '줄은 통째로: 판의 줄마다 켜기 전 그 줄의 모든 나라가 같은 차례로 (구성 나라를 적은 차례)', whole);
    check(board.rowsOf.some(r => r.split(',').length >= 2) && board.rowsOf.some(r => r.split(',').length >= 3), '같은 줄의 앞뒤 나라(승계로 이어진 나라)가 함께 옴', board.rowsOf.map(r => r.split(',').length));
    check(on.tracks.slice(1).every(t => t.folded && t.h === 34), '나머지 트랙은 모두 접힘(34px)', on.tracks.slice(1).map(t => [t.id, t.folded, t.h]));
    check(JSON.stringify(on.axis) === JSON.stringify(sig0.axis), '날짜 칸(연호 · 도읍 묶음)은 켜기 전 그대로 — 자료를 빼는 것이 아님', { before: sig0.axis, after: on.axis });
    check(on.gutter === sig0.gutter, '왼쪽 칸 폭 그대로', [sig0.gutter, on.gutter]);
    const ui1 = await page.evaluate(() => ({ board: __state.ui.board, folded: JSON.stringify(__state.ui.folded || []) }));
    check(ui1.board === 'view:v-seven' && ui1.folded === folded0, '켠 DLC 판은 보기 설정(board)에 기억 · 접힘 기억(folded)은 그대로', ui1);
    /* 왼쪽 칸 · 테두리 · 이름표 */
    const chips = await page.evaluate(() => {
      const tr = __tl.tracks[0];
      return { from: tr.groups.filter(g => g.from).map(g => [g.track, g.first, g.count]), people: tr.groups.filter(g => !g.from).length, els: tr.el.querySelectorAll('.tl-people.is-from').length, fold: tr.el.querySelectorAll('.tl-people[data-fold-people]').length };
    });
    check(chips.from.length === 3 && chips.from[1][2] === 2 && chips.els === 3 && chips.fold === 0, '원래 트랙 칩: 같은 트랙이 이어진 줄은 칩 하나(중국 2줄) · 칩은 접기 단추가 아님', chips);
    const over1 = await chipOverflow(page);
    check(!over1.length, '칩의 세로 글이 칩 밖으로 넘치지 않음', over1);
    const frame = await page.evaluate(() => {
      const tr = __tl.tracks[0];
      const el = tr.lanesEl.querySelector(':scope > .tl-scope.is-board');
      const span = el && el.querySelector('.tl-scope-span');
      const name = el && el.querySelector('.tl-scope-name');
      const X = y => ((y - __tl.view.start) / (__tl.view.end - __tl.view.start)) * __tl.W;
      return el && { left: parseFloat(el.style.left), width: parseFloat(el.style.width), W: __tl.W, clip: el.classList.contains('clip-l') && el.classList.contains('clip-r'), name: name.textContent, nameOff: name.classList.contains('is-off'),
        span: !span.hidden && [parseFloat(span.style.left), parseFloat(span.style.width)], want: [X(600), X(650) - X(600)], top: parseFloat(el.style.top), firstRow: tr.rowTop[0], tab: 18, head: 16 };
    });
    check(frame && frame.left === -1 && Math.abs(frame.width - (frame.W + 2)) < 1 && frame.clip, '테두리는 가로 전체(양쪽 모서리를 폄 — 기간이 아니라 보는 방법)', frame);
    check(frame.name.includes('7세기 견주기') && frame.name.includes('집합 보기 · 트랙 3 · 나라 4') && !frame.nameOff, '이름표: 판 이름 · 집합 보기 · 트랙 3 · 나라 4 (물러나지 않음)', frame.name);
    check(frame.span && Math.abs(frame.span[0] + frame.left - frame.want[0]) < 1.5 && Math.abs(frame.span[1] - frame.want[1]) < 2, '판의 기간(600 ~ 650)은 짙은 세로 구간', frame);
    check(frame.firstRow - frame.top === frame.tab + frame.head, '첫 줄 위 = 책갈피 탭 18 + 머리 16 (대범위 테두리와 같은 자리)', frame);
    const lab = await rect(page, '.tl-scope.is-board .tl-scope-name');
    const brd = await rect(page, '.tl-scope.is-board');
    const firstTab = await rect(page, '.tl-track.is-board .tl-lane[data-row="0"] .tl-tab, .tl-track.is-board .tl-lane[data-row="0"] [data-k^="tab:"]');
    check(lab.x >= brd.x && lab.r <= brd.r && lab.y >= brd.y && lab.b <= brd.b && !overlap(lab, firstTab), '이름표는 테두리 안 · 첫 줄의 책갈피 탭과 겹치지 않음', { lab, brd, firstTab });
    const btnText = await page.evaluate(() => { const b = document.getElementById('viewsBtn'); return [b.title, b.classList.contains('is-on'), b.textContent.trim(), !!b.querySelector('svg.ic')]; });
    check(btnText[0] === '집합 보기 · 7세기 견주기' && btnText[1] && btnText[2] === '' && btnText[3], '독 단추는 기호만(반전 채움) · 켠 판의 이름은 풍선 (건의 8)', btnText);
    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    await page.mouse.move(2, 2); // 마우스가 올라간 칸의 밝힘이 그림에 들지 않게
    await page.screenshot({ path: path.join(output, '연표-판-켬-576-696-1920-1배.png') });
    /* 끄기 → 켜기 전과 1px도 다르지 않음 */
    await page.click('#viewsBtn');
    await page.click('.views-pop .vw-row.is-on [data-vw-toggle]');
    await page.keyboard.press('Escape');
    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    await page.mouse.move(2, 2); // 마우스가 올라간 칸의 밝힘이 그림에 들지 않게
    await view();
    const off = await sig(page);
    check(await page.evaluate(() => __tl.boardOn() === null && __state.ui.board == null), '끄면 판이 꺼지고 보기 설정의 board도 지움');
    check(JSON.stringify(off.tracks) === JSON.stringify(sig0.tracks) && JSON.stringify(off.axis) === JSON.stringify(sig0.axis), '끄면 트랙 · 줄 · 높이 · 날짜 칸이 켜기 전과 같음', { before: sig0.tracks.map(t => [t.id, t.rows, t.h]), after: off.tracks.map(t => [t.id, t.rows, t.h]) });
    const shot1 = await page.screenshot();
    const d = await pixelDiff(page, shot0, shot1);
    if (d.n) {
      fs.writeFileSync(path.join(output, '견줌-켜기-전.png'), shot0);
      fs.writeFileSync(path.join(output, '견줌-끈-뒤.png'), shot1);
    }
    /* 대조: 판과 무관한 다시 짓기(트랙 하나를 접었다 폄)도 같은 자리의 글자 · 탭 가장자리에서 색값 1의 반올림 차이를 냄 — 그래서 "색값이 1보다 크게 다른 화소 0"을 1px 기준으로 */
    await page.evaluate(() => { __tl.toggleFold(__tl.tracks[__tl.tracks.length - 1].id); });
    await settle(page);
    await page.evaluate(() => { __tl.toggleFold(__tl.tracks[__tl.tracks.length - 1].id); });
    await view();
    const ctl = await pixelDiff(page, shot1, await page.screenshot());
    report.검사.push({ 검사: '대조 — 판과 무관한 다시 짓기(마지막 트랙 접었다 펴기)의 같은 견줌', 결과: ctl });
    check(d.big === 0, '끄면 켜기 전과 1px도 다르지 않음 (같은 범위 · 같은 스크롤의 1배 그림을 화소로 견줌 — 색값이 1보다 크게 다른 화소 0)', { 판: d, 대조: ctl }, { defer: true });
    /* 다시 켜고 — 원래 트랙 펴기 · 판 접기 · 이름표 (가장자리 안내가 뜰 수 있어 1px 견줌 뒤에) */
    await page.click('#viewsBtn');
    await page.click('.views-pop .vw-row:first-child [data-vw-toggle]');
    await page.keyboard.press('Escape');
    await view();
    /* 원래 트랙: 판을 켠 채 한 트랙만 펴기(트랙 이름 누르기) — 그 트랙에는 옮겨 간 줄이 없어진 채로(빈 줄 없음) · 접힘 기억은 그대로 */
    const k = sig0.tracks.find(t => t.rowsOf.some(r => r.split(',').includes(EA[0])));
    await page.click(`.tl-track[data-track="${k.id}"] .tl-fold`);
    await settle(page);
    const opened = (await sig(page)).tracks.find(t => t.id === k.id);
    const moved = new Set(board.rowsOf.flatMap(r => r.split(',')));
    check(!opened.folded && opened.rows === k.rows - 1 && !opened.rowsOf.some(r => r.split(',').some(u => moved.has(u))) && opened.rowsOf.every(r => r.length > 0), '판을 켠 채 트랙 하나를 펴면: 옮겨 간 줄 없이 다시 배치(줄 수 −1 · 빈 줄 없음)', { before: k.rows, after: opened.rows });
    check((await page.evaluate(() => JSON.stringify(__state.ui.folded || []))) === folded0, '판을 켠 동안 트랙을 펴고 접어도 접힘 기억(folded)은 그대로');
    await page.click(`.tl-track[data-track="${k.id}"] .tl-tname`);
    await settle(page);
    /* 판 트랙을 접어도 그 나라로 가면(상세의 이 시기로 · 검색) 판이 펴짐 */
    await page.click('.tl-track.is-board .tl-tname');
    await settle(page);
    check((await sig(page)).tracks[0].folded, '판 트랙도 이름을 누르면 접힘');
    await page.evaluate(uid => __tl.focusOn(__state.model.byUid.get(uid)), EA[2]);
    await settle(page);
    check(!(await sig(page)).tracks[0].folded && (await page.evaluate(() => __tl.tracks.filter(t => t.id !== '__board').every(t => t.folded))), '판의 나라로 가면 판 트랙이 펴짐(원래 트랙을 펴지 않음)');
    /* 이름표를 누르면 판 목록 */
    await page.click('.tl-scope.is-board .tl-scope-name');
    await page.waitForTimeout(150);
    check(await page.evaluate(() => !document.getElementById('viewsPop').hidden), '테두리 이름표를 누르면 판 목록');
    await page.keyboard.press('Escape');
    /* 다시 열면 켠 판이 되살아남 (보던 범위 그대로 — 판의 기간으로 날아가지 않음) */
    await page.evaluate(() => { __tl.setView(560, 720); });
    await page.waitForTimeout(700);
    await page.reload();
    await page.waitForFunction(() => window.__tl && window.__state && window.__state.model);
    await page.waitForTimeout(400);
    const back = await page.evaluate(() => ({ b: __tl.boardOn() && __tl.boardOn().id, v: [Math.round(__tl.view.start), Math.round(__tl.view.end)], first: __tl.tracks[0].id }));
    check(back.b === 'view:v-seven' && back.first === '__board' && back.v[0] === 560 && back.v[1] === 720, '다시 열면 켠 판이 되살아남 (보던 범위 그대로)', back);
    await page.click('#viewsBtn');
    await page.click('.views-pop .vw-row.is-on [data-vw-toggle]');
    await page.keyboard.press('Escape');
    check(await page.evaluate(() => __tl.boardOn() === null && __state.ui.board == null), '다시 연 뒤에도 목록의 스위치로 끔');
    await page.context().close();
  }

  /* ================= ㉯ 연표 — 시대 구분 상세의 '이 시대의 나라' 카드 ================= */
  {
    const page = await newPage({ 'ht.packs.installed': [fixture('views-check-b', '가상 시대 구분 묶음')], 'ht.packs.state': { 'east-asia-base': { enabled: false } } }, 'index.html');
    await page.evaluate(() => { __tl.setView(0, 800); __tl.bodyEl.scrollTop = 0; });
    await settle(page);
    await page.click('.tl-epoch[data-uid]');
    await page.waitForSelector('[data-vw-card]');
    const card = async () => page.$$eval('[data-vw-card] [data-vw-pick]', els => els.map(e => [e.textContent, e.getAttribute('aria-pressed')]));
    const c0 = await card();
    check(c0.map(c => c[0]).join(',') === '갑 왕국,을 왕국,병 나라', "시대 구분 상세에 '이 시대의 나라' 카드 — 같은 트랙 · 같은 기간의 나라(연표 차례)", c0);
    check((await page.$$('[data-vw-epoch-save]')).length === 0 && (await page.$$('.vw-bar')).length === 0, '연표에는 판을 저장하는 길이 없음(카드의 저장 · 고른 나라 막대 없음)');
    await page.click('[data-vw-card] [data-vw-pick]:nth-child(2)');
    check((await card())[1][1] === 'false', '칩을 누르면 빠짐(다시 누르면 들어감)');
    await page.click('[data-vw-card] [data-vw-epoch]');
    await settle(page);
    const t1 = await page.evaluate(() => ({ b: __tl.boardOn(), ui: __state.ui.board, first: __tl.tracks[0].id, rows: __tl.tracks[0].rowPeriods.map(r => r.map(p => p.name).join(',')), view: [__tl.view.start, __tl.view.end], btn: document.getElementById('viewsBtn').hidden }));
    check(t1.b && t1.b.temp && t1.b.members.length === 2 && t1.ui == null && t1.first === '__board' && !t1.btn, '스위치를 켜면 저장하지 않은 임시 판(보기 설정에 남지 않음 · 독 단추가 보임)', t1);
    check(t1.view[0] < 260 && t1.view[1] > 480, '켜면 그 시대 구분의 기간으로', t1.view);
    await page.screenshot({ path: path.join(output, '연표-시대-구분-카드-1920-1배.png') });
    await page.click('[data-vw-card] [data-vw-wide]');
    await settle(page);
    const wide = await card();
    const t2 = await page.evaluate(() => __tl.boardOn().members.length);
    check(wide.length === 5 && t2 === 4, '같은 기간의 다른 트랙 나라를 더하면 켠 판이 그 자리에서 다시 모임', { wide, members: t2 });
    await page.click('#viewsBtn');
    check(await page.evaluate(() => /저장하지 않은 판/.test(document.getElementById('viewsPop').textContent)), '목록에 임시 판이 "저장하지 않은 판"으로');
    await page.keyboard.press('Escape');
    await page.click('[data-vw-card] [data-vw-epoch]');
    await settle(page);
    check(await page.evaluate(() => __tl.boardOn() === null && document.getElementById('viewsBtn').hidden), '스위치를 끄면 임시 판이 사라짐(판 DLC가 없으면 독 단추도 다시 숨음)');
    await page.context().close();
  }

  /* ================= ㉰ 메이커 — 고른 나라 막대 · 저장 · 고치기 · 지우기 ================= */
  {
    const OWN = 'views-check-c';
    const page = await newPage({ 'ht.maker.draft': fixture(OWN, '가상 메이커 묶음') }, 'dlc-maker.html');
    await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden);
    await page.evaluate(() => { __tl.setView(0, 800); __tl.bodyEl.scrollTop = 0; });
    await settle(page);
    check(await page.evaluate(() => !!document.querySelector('#mkCTabs #viewsBtn')), '메이커: 가운데 탭 줄에 집합 보기 단추');
    const band = uid => `#timeline .tl-band[data-uid="${OWN}/${uid}"]`;
    await page.click(band('mu'), { modifiers: ['Control'] });
    await page.waitForTimeout(150);
    check(await page.evaluate(() => !document.querySelector('.vw-bar').hidden), 'Ctrl+클릭 한 번이면 고른 나라 막대가 뜸');
    await page.click(band('jeong'), { modifiers: ['Control'] });
    await page.waitForTimeout(150);
    const bar = await page.evaluate(() => ({ text: document.querySelector('.vw-bar-title').textContent, ph: document.querySelector('.vw-bar input').hasAttribute('placeholder'), chips: [...document.querySelectorAll('.vw-bar [data-vw-unpick]')].map(e => e.textContent) }));
    check(/고른 나라 2/.test(bar.text) && !bar.ph && bar.chips.join(',') === '무 성읍,정 연맹', '막대: 고른 나라 2 · 칩(고른 차례) · 이름 칸에 회색 예시 글 없음', bar);
    const barR = await rect(page, '.vw-bar');
    const zoom = await rect(page, '#stage .zoom-controls');
    const stage = await rect(page, '#stage');
    check(!overlap(barR, zoom) && barR.x >= stage.x && barR.r <= stage.r && barR.b <= stage.b && Math.abs(barR.x + barR.w / 2 - (stage.x + stage.w / 2)) < 2, '막대는 화면 아래 가운데 · 확대 단추와 겹치지 않음 · 연표 안', { barR, zoom, stage });
    await page.screenshot({ path: path.join(output, '메이커-고른-나라-막대-1920-1배.png') });
    await page.click('.vw-bar [data-vw-bar="save"]');
    await page.waitForTimeout(200);
    check(await page.evaluate(() => !(__maker.draft.views || []).length), '이름 없이 저장하면 막힘');
    await page.fill('.vw-bar input', '바다와 산');
    await page.click('.vw-bar [data-vw-bar="save"]');
    await page.waitForTimeout(600);
    const saved = await page.evaluate(() => ({ views: JSON.parse(JSON.stringify(__maker.draft.views || [])), board: __tl.boardOn() && __tl.boardOn().name, bar: document.querySelector('.vw-bar').hidden, sel: __maker.selection().length }));
    saved.toasts = await page.evaluate(() => [...document.querySelectorAll('.toast')].map(t => t.textContent));
    check(saved.views.length === 1 && saved.views[0].name === '바다와 산' && JSON.stringify(saved.views[0].members) === JSON.stringify(['vc-gang:무 성읍', 'vc-dal:정 연맹']), "저장하면 작업본 views에 '트랙:이름' 참조로(고른 차례)", saved);
    check(saved.board === '바다와 산' && saved.bar && saved.sel === 0, '저장한 판이 켜지고 고르기가 풀려 막대가 내려감', saved);
    await settle(page);
    const over2 = await chipOverflow(page);
    const chipText = await page.$$eval('.tl-track.is-board .tl-people span', els => els.map(e => e.textContent));
    check(!over2.length && chipText.includes('강마루') && chipText.includes('달메'), '줄이 짧은 판의 칩은 뜻이 남는 앞 낱말만(강마루 산 → 강마루) — 넘치지 않음', { over2, chipText });
    /* 목록의 고치기: 이름 · 차례 */
    await page.click('#viewsBtn');
    await page.waitForSelector('.views-pop [data-vw-edit]');
    await page.screenshot({ path: path.join(output, '메이커-목록-1920-1배.png') });
    await page.click('.views-pop [data-vw-edit]');
    check(!(await page.evaluate(() => [...document.querySelectorAll('.vw-edit input')].some(i => i.hasAttribute('placeholder')))), '고치기 칸에 회색 예시 글 없음');
    await page.fill('.vw-edit input[name="name"]', '산과 바다');
    await page.click('.vw-edit [data-vw-move="0:1"]');
    await page.fill('.vw-edit input[name="start"]', '300');
    await page.fill('.vw-edit input[name="end"]', '500');
    await page.click('.vw-edit button[type="submit"]');
    await page.waitForTimeout(600);
    const edited = await page.evaluate(() => JSON.parse(JSON.stringify(__maker.draft.views)));
    check(edited.length === 1 && edited[0].name === '산과 바다' && JSON.stringify(edited[0].members) === JSON.stringify(['vc-dal:정 연맹', 'vc-gang:무 성읍']) && edited[0].start === 300 && edited[0].end === 500 && edited[0].id === saved.views[0].id, '고치기: 이름 · 차례 · 기간이 같은 id의 판에', edited);
    check(await page.evaluate(() => __tl.boardOn() && __tl.boardOn().name === '산과 바다' && __tl.tracks[0].rowPeriods.map(r => r[0].name).join(',') === '정 연맹,무 성읍'), '켜 둔 판은 고친 구성으로 그 자리에서 다시 모임');
    await page.click('.views-pop [data-vw-del]');
    await page.waitForSelector('#mkAskYes');
    await page.click('#mkAskYes');
    await page.waitForTimeout(600);
    check(await page.evaluate(() => !(__maker.draft.views || []).length && __tl.boardOn() === null), '지우기: 판이 작업본에서 빠지고 켜 둔 판도 꺼짐');
    await page.keyboard.press('Escape');
    /* 시대 구분 카드의 '집합 보기로 저장' (메이커에서만 — 메이커는 시대 구분을 누르면 편집 창이 열리므로 카드는 편집 창 맨 위에) — 기간 함께 */
    await page.click('.tl-epoch[data-uid]');
    await page.waitForSelector('#editorScopeBar [data-vw-card] [data-vw-epoch-save]');
    const ec = await page.$$eval('#editorScopeBar [data-vw-pick]', els => els.map(e => e.textContent));
    check(ec.join(',') === '갑 왕국,을 왕국,병 나라', "메이커: 시대 구분 편집 창 맨 위에 '이 시대의 나라' 카드", ec);
    await page.screenshot({ path: path.join(output, '메이커-시대-구분-카드-1920-1배.png') });
    await page.click('#editorScopeBar [data-vw-epoch-save]');
    await page.waitForTimeout(700);
    const ev = await page.evaluate(() => JSON.parse(JSON.stringify(__maker.draft.views || [])));
    check(ev.length === 1 && ev[0].name === '가운데 시대' && ev[0].start === 260 && ev[0].end === 480 && ev[0].members.length === 3, "시대 구분 카드의 '집합 보기로 저장': 이름 · 기간 · 나라가 판으로", ev);
    check(await page.evaluate(() => __tl.boardOn() && __tl.boardOn().name === '가운데 시대' && !__tl.boardOn().temp), '저장한 판이 켜짐(임시 판이 아니라 DLC의 판)');
    await page.context().close();
  }
  check(report.오류.length === 0, '페이지 오류 0', report.오류);
} finally {
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2) + '\n');
  await browser.close();
  server.close();
}
console.log(`집합 보기 검사 ${report.검사.length} · 오류 ${report.오류.length} · 미해결 ${report.마지막에확인할실패.length} — ${output}`);
assert.equal(report.마지막에확인할실패.length, 0, report.마지막에확인할실패.join('\n'));
