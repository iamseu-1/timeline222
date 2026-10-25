/* 렌즈(주제 보기 — 감독 선택 D5 결정 5 A · 6 B, 설계 docs/설계-10건/7-8-단체와-렌즈.md)를 실제 브라우저(1920×1080 · 배율 1)에서 검사합니다.
   ① 연표: 견본 sample-lantern(등불 연대기 — 따로 세계라 기본팩은 끈 채로)을 설치한 채로 — 렌즈 단추(눈 기호만 · 이름은 풍선 — 건의 8) · 차림표(견본이 내장 넷을 숨기고 다섯을 더함),
      지도자 칸 자리에 바꿔 끼움(줄 높이 그대로 · 렌즈 켬 줄 배치는 하나) · 의회 렌즈(산호 해상 동맹 · 하연 연합 왕국의 '바다 회의' 갈래) ·
      붕당의 연정 칸(두 색 — 진주파 · 닻파) · 체제를 지위로 대신(등불 왕국의 지위 단 ↔ 지도자 칸 맞바꿈) · 자료 없는 나라의 지도자 칸 옅게 · 사건 옅게 + 주제 색 고리 · 같은 갈래 메아리 ·
      칸을 누르면 제도 창 · S · Shift+S · Esc 차례(차림표 → 상세 창 → 렌즈 → 집중 모드) · ⋯ 차림표의 한 줄 · 다시 열어도 기억(DLC가 더한 주제도) · 그림 내보내기 · 끄면 처음과 같은 띠(DOM 그대로) ·
      칸이 띠 밖으로 나가거나 서로 겹치거나 글자가 잘리지 않음
   ② 렌즈 종류를 DLC가 고르기(감독 덧붙임): 확인용 DLC가 견본의 의회 주제를 숨기고 · 선거제도의 이름을 바꾸고 · 새 주제를 더함 — 숨긴 주제로 기억된 렌즈는 꺼지고 설정도 지움 ·
      DLC가 더한 주제로 켠 채 그 DLC를 끄면 다시 열 때 꺼지고 설정도 지움
   ③ 메이커: 주제 사전 표의 '렌즈에서 숨김' 칸 — 내장 주제를 가져와 켜면 작업본에 hidden: true · 끄면 칸이 빠짐 · 형식 3
   node scripts/lens-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge) */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/렌즈');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
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
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100% · 1배', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
const sample = name => JSON.parse(fs.readFileSync(path.join(root, 'samples', name + '.json'), 'utf8'));
const SAMPLES = [sample('sample-lantern')];
/* 견본의 트랙 일곱(설령 · 하연 · 적석 · 산호해 · 청림 · 백사만 · 서해 백탑령 — 연표에는 문화권 차례로 하연이 맨 위) */
const TRACKS = SAMPLES[0].tracks.map(t => t.id);
const sameKeys = (o, keys) => Object.keys(o).sort().join() === keys.slice().sort().join(); // 트랙 차례와 상관없이 견본 트랙이 모두 있는지
/* 견본 트랙의 띠 DOM — 렌즈를 켰다 끈 뒤 처음과 글자까지 같은지 (화면에 든 줄 수는 스크롤에 따라 다르므로 띠만 견줌).
   화면 밖으로 밀려난 줄의 띠는 DOM에 옛 그림으로 남아 있다가 다시 화면에 들 때 새로 그려지므로(설령 트랙 — 산호해로 내려간 동안) 화면에 든 띠만 견줌 */
const bandsHTML = page => page.evaluate(ids => {
  const vr = HT.viewer.timeline.bodyEl.getBoundingClientRect();
  const shown = b => { const r = b.getBoundingClientRect(); return r.bottom > vr.top && r.top < vr.bottom; };
  return ids.map(id => [...document.querySelectorAll(`.tl-track[data-track="${id}"] .tl-band`)].filter(shown).map(b => b.outerHTML).join('')).join('\n');
}, TRACKS);
const settle = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
const newView = async (packs, ui = null) => {
  const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  await ctx.addInitScript(([p, u]) => {
    if (!localStorage.getItem('ht.packs.installed')) {
      localStorage.setItem('ht.packs.installed', JSON.stringify(p));
      localStorage.setItem('ht.packs.state', JSON.stringify({ 'east-asia-base': { enabled: false } })); // 견본은 따로 세계 — 기본팩을 끄고 견본 트랙만(두 나라의 같은 갈래가 한 화면에 들게)
    }
    if (u && !sessionStorage.getItem('lens-check-ui')) {
      sessionStorage.setItem('lens-check-ui', '1');
      localStorage.setItem('ht.ui', JSON.stringify(u));
    }
  }, [packs, ui]);
  const page = await ctx.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => { if (m.type() === 'error') report.오류.push(m.text()); });
  await page.goto(base + 'index.html');
  await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && HT.lensUI);
  return { ctx, page };
};
const scrollTo = (page, trackId) => page.evaluate(id => { const el = document.querySelector(`.tl-track[data-track="${id}"]`); if (el) el.scrollIntoView({ block: 'start' }); }, trackId);
/* 페이지 안 도우미: 띠 · 칸 · 높이 — 화면에 든 줄만 그려지므로 그 띠의 줄로 옮긴 뒤 잼.
   견본 2.0.0은 트랙 차례가 문화권 차례(하연 → 설령 → 청림 → 적석 → 백사만 → 산호해 → 서해 백탑령)라 산호해로 옮겨도 하연의 아래쪽 줄(하연 연합 왕국) · 적석이
   한 화면에 들지 않음 — 띠마다 제 줄(lane)을 화면 가운데로 옮겨 재고, 끝에 track으로 돌아옴(뒤따르는 그림 · 띠 DOM 견줌은 그 화면에서) */
/* 그 트랙으로 옮김 — 보기 · 렌즈를 바꾼 그리기가 먼저 끝나야 함(연표의 세로 닻이 옮긴 스크롤을 되돌리지 않게) */
const goTrack = async (page, track) => {
  await settle(page);
  await page.waitForTimeout(150);
  await scrollTo(page, track);
  await settle(page);
  await page.waitForTimeout(150);
};
/* 이름으로 그 띠의 줄을 화면 가운데로 — 지금 보기(가로)에 그 나라가 없으면 옮기지 않고 false. 띠가 화면에 그려질 때까지 다시 굴리며 기다림
   (느린 때에는 두 장면 안에 다 그려지지 않거나 늦게 끝난 그리기가 세로 닻으로 굴린 자리를 되돌림) */
const showBand = async (page, name) => {
  const scroll = () => page.evaluate(n => {
    const tl = HT.viewer.timeline;
    for (const tr of tl.tracks) {
      const row = tr.rowPeriods.findIndex(r => r.some(p => p.name === n));
      if (row < 0) continue;
      const p = tr.rowPeriods[row].find(q => q.name === n);
      if (p.start > tl.view.end || p.endY < tl.view.start) return false;
      const lane = tr.el.querySelector(`.tl-lane[data-row="${row}"]`);
      if (lane) lane.scrollIntoView({ block: 'center' });
      return !!lane;
    }
    return false;
  }, name);
  const drawn = () => page.evaluate(n => [...document.querySelectorAll('.tl-band')].some(b => { const r = b.getBoundingClientRect(); return (HT.viewer.state.model.byUid.get(b.dataset.uid) || {}).name === n && r.bottom > 0 && r.top < innerHeight; }), name);
  await settle(page);
  if (!(await scroll())) return false;
  await settle(page);
  await page.waitForTimeout(150);
  for (let i = 0; i < 40 && !(await drawn()); i++) {
    await scroll();
    await settle(page);
    await page.waitForTimeout(250);
  }
  return true;
};
const BANDS = { league: '산호 해상 동맹', union: '하연 연합 왕국', jeok2: '적석 왕국(재건)', lamp: '등불 왕국', upper: '윗물국' };
const bandFacts = (page, name) =>
  page.evaluate(name => {
    const inView = b => { const r = b.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; }; // 화면 밖에 남은 옛 그림의 띠보다 화면에 든 띠를
    const all = [...document.querySelectorAll('.tl-band')].filter(b => b.dataset.uid && (HT.viewer.state.model.byUid.get(b.dataset.uid) || {}).name === name);
    const b = all.find(inView) || all[0];
    if (!b) return null;
    const cells = sel => [...b.querySelectorAll(sel)].map(el => ({ text: el.textContent, cls: el.className, fam: el.dataset.fam || '', uid: el.dataset.uid || '', top: parseFloat(el.style.top), h: parseFloat(el.style.height), op: getComputedStyle(el).opacity }));
    return { lens: cells('.tl-cell.k-lens'), leader: cells('.tl-cell.k-leader'), power: cells('.tl-cell.k-group:not(.is-real):not(.k-lens)'), real: cells('.tl-cell.k-group.is-real'), rank: cells('.tl-cell.k-rank') };
  }, name);
const facts = async (page, track = 'sanho') => {
  const out = {};
  for (const [key, name] of Object.entries(BANDS)) out[key] = (await showBand(page, name)) ? await bandFacts(page, name) : null;
  await goTrack(page, track);
  return Object.assign(out, await page.evaluate(() => {
    const tl = HT.viewer.timeline;
    return {
      lens: tl.themeLens ? tl.themeLens.id : '',
      heights: Object.fromEntries(tl.tracks.map(t => [t.id, t.height])),
      btn: (b => ({ text: b.textContent.trim(), title: b.title, icon: !!b.querySelector('svg.ic'), on: b.classList.contains('is-on'), dot: b.classList.contains('is-on') ? getComputedStyle(b, '::after').width : '' }))(document.querySelector('#themeLensBtn')),
      root: document.querySelector('#timeline').className,
    };
  }));
};
/* 칸이 띠 밖으로 나가지 않고(띠 안쪽 테두리 안) · 서로 겹치지 않고 · 글자가 잘리지 않는지 (앞글자만 보이게 자른 칸 is-clip은 빼고) */
const audit = page =>
  page.evaluate(() => {
    const bad = [];
    for (const b of document.querySelectorAll('.tl-band')) {
      const br = b.getBoundingClientRect();
      const cs = [...b.querySelectorAll(':scope > .tl-cell.k-lens, :scope > .tl-cell.k-rank.in-lens, :scope > .tl-cell.k-leader.is-mini')];
      for (const el of cs) {
        const r = el.getBoundingClientRect();
        if (r.width < 0.5) continue;
        if (r.left < br.left - 0.5 || r.right > br.right + 0.5 || r.top < br.top - 0.5 || r.bottom > br.bottom + 0.5) bad.push(`띠 밖: ${el.textContent} (${el.className})`);
        const t = el.querySelector('b');
        if (t && !el.classList.contains('is-clip') && t.scrollWidth > t.clientWidth + 0.5) bad.push(`잘린 글: ${t.textContent}`);
      }
      const rows = new Map();
      for (const el of cs) {
        const k = el.style.top;
        if (!rows.has(k)) rows.set(k, []);
        rows.get(k).push(el.getBoundingClientRect());
      }
      for (const list of rows.values()) {
        list.sort((a, c) => a.left - c.left);
        list.forEach((r, i) => { if (i && r.left < list[i - 1].right - 1.01) bad.push(`겹침: ${b.dataset.uid} ${list[i - 1].right.toFixed(1)} > ${r.left.toFixed(1)}`); });
      }
    }
    return bad;
  });
try {
  /* ① 연표 */
  {
    const { ctx, page } = await newView(SAMPLES);
    await page.evaluate(() => HT.viewer.timeline.setView(1000, 1700));
    await settle(page);
    await page.mouse.move(5, 1070);
    const off0 = await facts(page);
    const dom0 = await bandsHTML(page);
    const btnBox = await page.evaluate(() => {
      const d = document.querySelector('#dock').getBoundingClientRect();
      const b = document.querySelector('#themeLensBtn').getBoundingClientRect();
      return { inside: b.left >= d.left && b.right <= d.right && b.top >= d.top && b.bottom <= d.bottom, w: b.width };
    });
    check(off0.lens === '' && off0.btn.text === '' && off0.btn.icon && off0.btn.title === '렌즈 (S)' && !off0.btn.on && btnBox.inside, "처음: 렌즈 꺼짐 · 독 안의 렌즈 단추(눈 기호만 · 풍선 '렌즈 (S)')", { btn: off0.btn, btnBox });
    check(off0.league.lens.length === 0 && off0.league.leader.length === 18 && off0.jeok2.leader.length === 11 && off0.jeok2.leader.every(c => !/is-nolens/.test(c.cls)), '렌즈를 끈 띠에는 렌즈 칸 · 옅은 지도자 칸이 없음', { league: off0.league.leader.length, jeok2: off0.jeok2.leader.length });
    /* 차림표 */
    await page.locator('#themeLensBtn').click();
    await page.waitForSelector('#themeLensMenu:not([hidden])');
    const menu = await page.evaluate(() => {
      const m = document.querySelector('#themeLensMenu');
      const r = m.getBoundingClientRect();
      return { items: [...m.querySelectorAll('.lens-item')].map(el => el.querySelector('.ctx-label').childNodes[0].textContent), title: m.querySelector('.ctx-title').textContent, none: m.querySelectorAll('.lens-none').length, inView: r.left >= 0 && r.right <= innerWidth && r.bottom <= innerHeight, expanded: document.querySelector('#themeLensBtn').getAttribute('aria-expanded') };
    });
    check(menu.items.join() === '없음,체제,붕당,법률,선거제도,빛돌,불씨,바다 무역,의회,광학·연금' && menu.title === '렌즈' && menu.inView && menu.expanded === 'true', '차림표: 없음 + 내장 넷(견본이 이념 · 군사 · 조세 · 선발 제도를 숨김) + 견본이 더한 주제 다섯 (머리는 이름만)', menu);
    await page.screenshot({ path: path.join(output, '렌즈-차림표-1920-1배.png'), clip: { x: 0, y: 0, width: 1120, height: 600 } });
    await page.locator('#themeLensMenu .lens-item', { hasText: '의회' }).click();
    await settle(page);
    const par = await facts(page);
    const grew = Object.keys(off0.heights).filter(k => par.heights[k] !== off0.heights[k]);
    check(par.lens === 'parliament' && par.btn.on && par.btn.text === '' && par.btn.title === '렌즈 · 의회 (S)' && par.btn.dot === '7px' && (await page.evaluate(() => document.querySelector('#themeLensMenu').hidden)), "의회를 고르면 렌즈가 켜지고 단추는 반전 채움 + 주제 색 점 · 풍선 '렌즈 · 의회 (S)'(차림표는 닫힘)", par.btn);
    check(grew.length === 0 && sameKeys(par.heights, TRACKS), '줄 높이 그대로 — 견본 나라는 모두 지도자 칸이 있어 렌즈 칸이 그 자리에 들고 어느 트랙도 자라지 않음', { before: off0.heights, after: par.heights });
    check(par.league.lens.map(c => c.text).join() === '선주 회의,선주 · 선원 회의' && par.league.lens.every(c => c.h === 22 && c.fam === 'parliament|바다 회의' && c.uid) && par.league.leader.length === 0, '산호 해상 동맹: 지도자 칸 자리(22px)에 의회의 칸 둘(갈래 · 제도 uid)', par.league.lens);
    check(par.jeok2.lens.length === 0 && par.jeok2.leader.length === 11 && par.jeok2.leader.every(c => /is-nolens/.test(c.cls) && Math.abs(Number(c.op) - 0.4) < 0.01), '적석 왕국(재건)(의회 자료 없음): 지도자 칸을 옅게(.4) 남김', par.jeok2.leader.map(c => c.op));
    const ev = await page.evaluate(() => {
      const one = uid => { const el = document.querySelector(`.tl-ev[data-uid="${CSS.escape(uid)}"]`); return el ? { cls: el.className, op: getComputedStyle(el).opacity, ring: getComputedStyle(el.querySelector('.d')).boxShadow } : null; };
      return { vote: one('lantern-chronicle/e-elect-1031'), strike: one('lantern-chronicle/e-anchor-strike'), sub: [...document.querySelectorAll('.tl-row .sub')].map(s => s.textContent) };
    });
    check(ev.vote && /is-lens/.test(ev.vote.cls) && Number(ev.vote.op) === 1 && /rgb/.test(ev.vote.ring) && ev.strike && /no-lens/.test(ev.strike.cls) && Math.abs(Number(ev.strike.op) - 0.26) < 0.01, '사건: 그 주제만 또렷 + 주제 색 고리(첫 도선장 선거) · 나머지 .26(닻파의 선원 파업 — 거르지 않음)', ev);
    check(ev.sub.some(s => /^선주 · 선원 회의/.test(s)), "이름 칸의 부제가 '지금 제도'(산호 해상 동맹 — 선주 · 선원 회의)", ev.sub);
    check((await audit(page)).length === 0, '렌즈 칸이 띠 밖으로 나가지 않고 · 겹치지 않고 · 글자가 잘리지 않음(의회)', await audit(page));
    await goTrack(page, 'sanho');
    await page.screenshot({ path: path.join(output, '렌즈-의회-1920-1배.png') });
    /* 같은 갈래 메아리 — 산호 해상 동맹의 '선주 · 선원 회의'와 하연 연합 왕국의 양원 의회는 같은 갈래(바다 회의).
       견본 2.0.0에서는 두 띠가 한 화면에 들지 않음(하연이 맨 위 트랙) — 앞의 facts가 하연 연합 왕국 줄을 의회 렌즈로 그려 둔 띠가 DOM에 남아 있으므로
       산호해 화면에서 올려 두 나라의 칸을 DOM에서 셈(메아리는 화면 밖 칸에도 붙음 — timeline.js _lensEcho) */
    await page.locator('.tl-band .tl-cell.k-lens', { hasText: '선주 · 선원 회의' }).first().hover();
    await settle(page);
    const echo = await page.evaluate(() => ({ root: document.querySelector('#timeline').classList.contains('lens-echo'), fam: document.querySelectorAll('.tl-cell.k-lens.is-fam').length, all: document.querySelectorAll('.tl-cell.k-lens[data-fam="parliament|바다 회의"]').length, uids: new Set([...document.querySelectorAll('.tl-cell.k-lens.is-fam')].map(e => e.closest('.tl-band').dataset.uid)).size }));
    check(echo.root && echo.fam === echo.all && echo.fam === 4 && echo.uids === 2, '같은 갈래에 올리면 두 나라(두 트랙)의 같은 갈래 칸이 모두 진해짐(메아리)', echo);
    await page.mouse.move(5, 1070);
    await settle(page);
    check(!(await page.evaluate(() => document.querySelector('#timeline').classList.contains('lens-echo') || document.querySelectorAll('.is-fam').length)), '칸에서 벗어나면 메아리가 풀림');
    /* S · Shift+S */
    await page.locator('.tl-body').focus();
    await page.keyboard.press('Shift+S');
    await settle(page);
    const s1 = await facts(page);
    await page.keyboard.press('s');
    await settle(page);
    const s2 = await facts(page);
    check(s1.lens === 'sea-trade' && s2.lens === 'parliament' && JSON.stringify(s1.heights) === JSON.stringify(par.heights), 'Shift+S 앞 렌즈 · S 다음 렌즈 — 렌즈를 바꿔도 줄 높이 그대로', { s1: s1.lens, s2: s2.lens });
    /* 붕당 */
    await page.evaluate(() => HT.lensUI.setLens('faction'));
    await settle(page);
    const fac = await facts(page);
    check(JSON.stringify(fac.heights) === JSON.stringify(par.heights), '붕당 렌즈도 같은 줄 높이');
    check(fac.league.lens.length === 6 && fac.league.lens.filter(c => /is-two/.test(c.cls)).length === 1 && fac.league.real.length === 1 && fac.league.real.every(c => !/k-lens/.test(c.cls)), '산호 해상 동맹: 붕당 렌즈 = 단체의 집권 칸(진주파 · 닻파의 연정 칸 하나는 위아래 두 색 · 실권 칸은 빼고 제 줄에)', fac.league.lens.map(c => [c.text, /is-two/.test(c.cls)]));
    /* 집권 단(설계 11-2 '붕당 렌즈(맞바꿈)')이 있는 줄: 집권 칸이 지도자 칸 자리(22px)로 · 지도자 칸은 집권 단 자리(20px · 작은 글)로 — 지위 맞바꿈과 같은 꼴 */
    const leagueLeaderTop = off0.league.leader[0].top, leaguePowerTop = off0.league.power[0].top;
    check(off0.league.power.length === 6 && off0.league.power.every(c => c.top === leaguePowerTop && c.h === 20) && fac.league.lens.every(c => c.top === leagueLeaderTop && c.h === 22) && fac.league.leader.length === 18 && fac.league.leader.every(c => /is-mini/.test(c.cls) && c.top === leaguePowerTop && c.h === 20) && fac.league.power.length === 0, '산호 해상 동맹: 집권 칸이 지도자 칸 자리 · 지도자 칸이 집권 단 자리(작은 글)로 맞바꿈', { lens: fac.league.lens.map(c => [c.text, c.top, c.h]), leader: fac.league.leader.slice(0, 2).map(c => [c.text, c.top, c.h, c.cls]), leagueLeaderTop, leaguePowerTop });
    check((await audit(page)).length === 0, '띠 밖 · 겹침 · 잘린 글 없음(붕당)', await audit(page));
    await goTrack(page, 'sanho');
    await page.screenshot({ path: path.join(output, '렌즈-붕당-1920-1배.png') });
    /* 체제 — 지위로 대신(맞바꿈): 등불 왕국(등왕 → 빈 등좌 — 지위 단이 있는 줄) · 윗물국(지위 하나 — 지위 단이 없는 줄) */
    await page.evaluate(() => { HT.viewer.timeline.setView(0, 1100); HT.lensUI.setLens('system'); });
    await settle(page);
    const sys = await facts(page, 'hayeon');
    await page.evaluate(() => HT.lensUI.setLens(''));
    await settle(page);
    const sysOff = await facts(page, 'hayeon');
    const lampLeaderTop = sysOff.lamp.leader[0].top, lampRankTop = sysOff.lamp.rank[0].top;
    check(TRACKS.every(k => sys.heights[k] === sysOff.heights[k]), '체제 렌즈를 지위로 대신해도 견본 트랙의 줄 높이 그대로', { on: sys.heights, off: sysOff.heights });
    check(sysOff.lamp.rank.length === 2 && sys.lamp.rank.length === 2 && sys.lamp.rank.every(c => /in-lens/.test(c.cls) && c.top === lampLeaderTop && c.h === 22) && sys.lamp.leader.length === 21 && sys.lamp.leader.every(c => /is-mini/.test(c.cls) && c.top === lampRankTop && c.h === 20), '등불 왕국: 지위 칸(등왕 · 빈 등좌)이 지도자 칸 자리 · 지도자 칸이 지위 단 자리(작은 글)로 맞바꿈', { rank: sys.lamp.rank.map(c => [c.text, c.top]), leader: sys.lamp.leader.slice(0, 2).map(c => [c.text, c.top]), lampLeaderTop, lampRankTop });
    check(sysOff.upper.rank.length === 0 && sys.upper.rank.length === 1 && /in-lens/.test(sys.upper.rank[0].cls) && sys.upper.leader.length === 0, '윗물국(지위 단이 없는 줄): 지위 칸만 지도자 자리에', sys.upper);
    await page.evaluate(() => HT.lensUI.setLens('system'));
    await settle(page);
    check((await audit(page)).length === 0, '띠 밖 · 겹침 · 잘린 글 없음(체제 — 지위 맞바꿈)', await audit(page));
    await goTrack(page, 'hayeon');
    await page.screenshot({ path: path.join(output, '렌즈-체제-지위-1920-1배.png') });
    /* 칸을 누르면 제도 창 · Esc 차례 */
    await page.evaluate(() => { HT.viewer.timeline.setView(1000, 1700); HT.lensUI.setLens('parliament'); });
    await settle(page);
    await goTrack(page, 'sanho');
    await page.locator('.tl-band .tl-cell.k-lens', { hasText: '선주 · 선원 회의' }).first().click();
    await page.waitForFunction(() => !document.querySelector('#detail').hidden && /의회/.test(document.querySelector('#detail h2') ? document.querySelector('#detail h2').textContent : ''));
    const det = await page.evaluate(() => document.querySelector('#detail h2').textContent);
    check(/산호 해상 동맹/.test(det) && /의회/.test(det), '렌즈 칸을 누르면 그 제도 창', det);
    await page.keyboard.press('Escape');
    await settle(page);
    const e1 = await page.evaluate(() => ({ detail: !document.querySelector('#detail').hidden, lens: HT.viewer.timeline.themeLens && HT.viewer.timeline.themeLens.id }));
    await page.keyboard.press('Escape');
    await settle(page);
    const e2 = await page.evaluate(() => ({ lens: HT.viewer.timeline.themeLens, ui: HT.viewer.state.ui.themeLens }));
    check(!e1.detail && e1.lens === 'parliament' && !e2.lens && e2.ui === '', 'Esc: 상세 창이 먼저 닫히고, 다시 Esc로 렌즈가 꺼짐', { e1, e2 });
    await page.keyboard.press('z');
    await page.keyboard.press('s');
    await settle(page);
    await page.keyboard.press('Escape');
    await settle(page);
    const z1 = await page.evaluate(() => ({ zen: document.body.classList.contains('is-zen'), lens: !!HT.viewer.timeline.themeLens }));
    await page.keyboard.press('Escape');
    await settle(page);
    const z2 = await page.evaluate(() => ({ zen: document.body.classList.contains('is-zen') }));
    check(z1.zen && !z1.lens && !z2.zen, 'Esc: 집중 모드에서는 렌즈가 먼저 꺼지고, 다시 Esc로 집중 모드가 꺼짐', { z1, z2 });
    await page.evaluate(() => HT.lensUI.setLens('parliament'));
    await page.locator('#themeLensBtn').click();
    await page.waitForSelector('#themeLensMenu:not([hidden])');
    await page.keyboard.press('Escape');
    const m1 = await page.evaluate(() => ({ menu: !document.querySelector('#themeLensMenu').hidden, lens: HT.viewer.timeline.themeLens && HT.viewer.timeline.themeLens.id, focus: document.activeElement && document.activeElement.id }));
    check(!m1.menu && m1.lens === 'parliament' && m1.focus === 'themeLensBtn', 'Esc: 차림표가 열려 있으면 차림표만 닫힘(렌즈는 그대로 · 초점은 단추로)', m1);
    /* ⋯ 차림표의 한 줄 */
    await page.locator('#menuBtn').click();
    await page.waitForSelector('#ctxMenu:not([hidden])');
    const ctxLine = await page.evaluate(() => { const b = document.querySelector('#ctxMenu [data-lens-open]'); return b ? `${b.textContent}|${b.classList.contains('is-checked')}|${b.title}` : ''; });
    await page.locator('#ctxMenu [data-lens-open]').click();
    const opened = await page.evaluate(() => !document.querySelector('#themeLensMenu').hidden && document.querySelector('#ctxMenu').hidden);
    check(ctxLine === '렌즈S|true|렌즈 · 의회' && opened, "⋯ 차림표에 '렌즈' 한 줄(켠 동안 체크 · 풍선에 주제) — 누르면 렌즈 차림표", ctxLine);
    await page.keyboard.press('Escape');
    /* 그림 내보내기 */
    const svg = await page.evaluate(() => HT.viewer.timeline.toSVG({ width: 1800 }));
    await page.evaluate(() => HT.lensUI.setLens('faction'));
    const svgF = await page.evaluate(() => HT.viewer.timeline.toSVG({ width: 1800 }));
    check(/<g opacity="0\.26">/.test(svg) && /<g opacity="0\.4">/.test(svg) && /stroke-width="1\.5"\/>/.test(svg) && /clipPath id="tllens/.test(svgF), '그림 내보내기: 렌즈 칸 · 옅은 지도자 칸(.4) · 옅은 사건(.26) · 주제 색 고리 · 연정 칸 두 색');
    /* 끄면 처음과 같은 띠 — 다시 열기 앞에서 견줌: 다시 열면 하연 트랙은 기억된 보기(1000~1700)에서 빈 줄 넷이 처음부터 접혀 높이가 바뀜(렌즈와 상관없음) */
    await page.evaluate(() => { HT.lensUI.setLens(''); HT.viewer.timeline.setView(1000, 1700); });
    await page.mouse.move(5, 1070);
    await settle(page);
    await page.waitForTimeout(400);
    const off1 = await facts(page);
    const dom1 = await bandsHTML(page);
    /* 견본 트랙(기본팩은 끈 채) — 보기 0~1100(체제 렌즈)을 거쳐도 렌즈를 끄면 그대로 */
    const hs = f => TRACKS.map(k => f.heights[k]).join();
    check(hs(off1) === hs(off0) && dom1 === dom0 && dom0.length > 1000, '렌즈를 끄면 견본 트랙의 줄 높이 · 띠 DOM이 처음과 글자까지 같음', { same: dom1 === dom0, len: [dom0.length, dom1.length], heights: [hs(off0), hs(off1)] });
    /* 다시 열어도 기억 */
    await page.evaluate(() => HT.lensUI.setLens('law'));
    await page.reload();
    await page.waitForFunction(() => window.HT && HT.lensUI && HT.viewer.timeline.themeLens);
    const back = await facts(page);
    check(back.lens === 'law' && back.btn.on && /법률/.test(back.btn.title), '다시 열어도 켠 렌즈를 기억(보는 사람 설정 ui.themeLens — 내장 주제 법률)', back.btn);
    /* DLC가 더한 주제(견본이 더한 '의회' parliament)도 — 렌즈 부품이 붙을 때는 모델이 아직 없어(뷰어는 글꼴이 열린 뒤에 모델을 지음) 내장 여덟만 보고 지우던 것 */
    await page.evaluate(() => HT.lensUI.setLens('parliament'));
    await page.reload();
    await page.waitForFunction(() => window.HT && HT.lensUI && HT.viewer.state.model);
    await settle(page);
    const dlcBack = await page.evaluate(() => ({ lens: HT.viewer.timeline.themeLens && HT.viewer.timeline.themeLens.id, ui: HT.viewer.state.ui.themeLens, saved: JSON.parse(localStorage.getItem('ht.ui') || '{}').themeLens, title: document.querySelector('#themeLensBtn').title }));
    check(dlcBack.lens === 'parliament' && dlcBack.ui === 'parliament' && dlcBack.saved === 'parliament' && dlcBack.title === '렌즈 · 의회 (S)', 'DLC가 더한 주제(견본의 의회)로 켠 렌즈도 다시 열면 그대로 · 설정도 남음', dlcBack);
    await ctx.close();
  }
  /* ② 렌즈 종류를 DLC가 고르기 — 확인용 DLC가 견본(등불 연대기)이 더한 의회 주제를 숨김(견본에는 의회 제도가 셋 — 숨겨도 제도는 그 주제를 찾아야 함) */
  {
    const dlc = {
      format: 'history-timeline-dlc', formatVersion: 3, id: 'lens-dlc-check', name: '렌즈 조정 확인', version: '1.0.0',
      themes: [{ id: 'parliament', hidden: true }, { id: 'election', name: '뽑는 제도', color: '#a0bcc5', kind: '투표' }, { id: 'ritual', name: '제례 제도', color: '#bbacc8', kind: '예법' }],
    };
    const { ctx, page } = await newView([dlc].concat(SAMPLES), { themeLens: 'parliament' });
    await settle(page);
    const st = await page.evaluate(() => ({ lens: HT.viewer.timeline.themeLens, ui: HT.viewer.state.ui.themeLens, saved: JSON.parse(localStorage.getItem('ht.ui') || '{}').themeLens }));
    check(!st.lens && st.ui === '' && st.saved === '', '숨긴 주제(의회)로 기억된 렌즈는 켜지지 않고 설정도 지움', st);
    await page.locator('#themeLensBtn').click();
    await page.waitForSelector('#themeLensMenu:not([hidden])');
    const items = await page.evaluate(() => [...document.querySelectorAll('#themeLensMenu .lens-item')].map(el => ({ name: el.querySelector('.ctx-label').childNodes[0].textContent, hint: (el.querySelector('.ctx-label small:not(.lens-none)') || {}).textContent || '', none: !!el.querySelector('.lens-none') })));
    const names = items.map(x => x.name);
    check(!names.includes('의회') && !names.includes('군사제도') && names.includes('뽑는 제도') && !names.includes('선거제도') && names.indexOf('제례 제도') > names.indexOf('뽑는 제도') && names.includes('빛돌') && items.find(x => x.name === '제례 제도').none && items.find(x => x.name === '뽑는 제도').hint === '투표', 'DLC가 렌즈를 숨기고(견본의 의회) · 이름을 바꾸고(뽑는 제도 · 한마디) · 더함(제례 제도 — 자료 없음)', items);
    await page.screenshot({ path: path.join(output, '렌즈-DLC-조정-차림표-1920-1배.png'), clip: { x: 0, y: 0, width: 1120, height: 600 } });
    await page.keyboard.press('Escape');
    const det = await page.evaluate(() => HT.viewer.state.model.institutions.filter(x => x.themeId === 'parliament').map(o => ({ name: o.name, theme: o.themeName, warn: o.warnings.length })));
    check(det.length === 3 && det.every(o => o.theme === '의회' && o.warn === 0), '숨긴 주제의 제도(견본의 의회 제도 셋)는 그대로 그 주제를 찾음(상세 창 · 검색은 그대로)', det);
    /* DLC가 더한 주제(제례 제도)로 켠 채 그 DLC를 끄고 다시 열면 — 모델을 지은 뒤에 견주어 끄고 설정도 지움 */
    await page.evaluate(() => HT.lensUI.setLens('ritual'));
    const ritualOn = await page.evaluate(() => HT.viewer.timeline.themeLens && HT.viewer.timeline.themeLens.id);
    await page.evaluate(() => HT.store.set(HT.KEYS.packState, Object.assign(HT.store.get(HT.KEYS.packState, {}), { 'lens-dlc-check': { enabled: false } })));
    await page.reload();
    await page.waitForFunction(() => window.HT && HT.lensUI && HT.viewer.state.model);
    await settle(page);
    const gone = await page.evaluate(() => ({ lens: HT.viewer.timeline.themeLens, ui: HT.viewer.state.ui.themeLens, saved: JSON.parse(localStorage.getItem('ht.ui') || '{}').themeLens }));
    check(ritualOn === 'ritual' && !gone.lens && gone.ui === '' && gone.saved === '', 'DLC가 더한 주제로 켠 렌즈는 그 DLC를 끄고 다시 열면 꺼지고 설정도 지움', { ritualOn, gone });
    await ctx.close();
  }
  /* ③ 메이커 — 주제 사전 표의 '렌즈에서 숨김' */
  {
    const makerContext = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    const maker = await makerContext.newPage();
    maker.on('pageerror', e => report.오류.push(e.message));
    await maker.goto(base + 'dlc-maker.html');
    await maker.locator('[data-start-new]').waitFor();
    await maker.locator('[data-start-new] [name="name"]').fill('가상 렌즈 숨김');
    await maker.locator('[data-start-new] [name="id"]').fill('lens-hide-check');
    await maker.locator('[data-start-new] [name="how"][value="world"]').check();
    await maker.locator('[data-start-new] button[type="submit"]').click();
    await maker.waitForFunction(() => window.HT && HT.viewer && HT.viewer.maker && HT.viewer.maker.draft && document.querySelector('#mkStart').hidden);
    await maker.evaluate(() => HT.viewer.maker.openBase('themes'));
    await maker.locator('#mkBaseBody .mk-import summary').click();
    await maker.locator('#mkBaseBody .mk-import li', { hasText: '군사제도' }).locator('[data-import]').click();
    const box = maker.locator('#mkBaseBody tr[data-i]').filter({ has: maker.locator('input[name="name"][value="군사제도"]') }).locator('input[name="hidden"]');
    await box.waitFor();
    const head = await maker.evaluate(() => [...document.querySelectorAll('#mkBaseBody .mk-base-table th')].map(th => th.textContent));
    await box.check();
    await maker.waitForFunction(() => (HT.viewer.maker.draft.themes || []).some(t => t.id === 'military' && t.hidden === true));
    await maker.waitForTimeout(450);
    const on = await maker.evaluate(() => {
      const d = HT.viewer.maker.draft;
      const r = HT.normalizePack(d);
      const j = r.pack ? HT.packToJSON(r.pack) : null;
      return { row: d.themes.find(t => t.id === 'military'), ver: j && j.formatVersion, json: j && j.themes, lens: HT.lensThemes(HT.viewer.state.model).map(t => t.id) };
    });
    check(head.includes('렌즈에서 숨김') && on.row.hidden === true && on.ver === 3 && on.json.find(t => t.id === 'military').hidden === true && !on.lens.includes('military'), "메이커 주제 표의 '렌즈에서 숨김'을 켜면 작업본 · 파일에 hidden: true(형식 3) · 미리보기의 렌즈 주제에서 빠짐", on);
    await maker.screenshot({ path: path.join(output, '메이커-주제-숨김-1920-1배.png') });
    /* 메이커 미리보기의 렌즈 고르기(가운데 탭 줄의 렌즈 단추(눈 기호) — 감독 덧붙임 "렌즈 종류도 dlc 조정 가능하게"를 만드는 사람이 바로 보게): 숨긴 주제는 차림표에 없음 */
    const mkBtn = await maker.evaluate(() => {
      const b = document.querySelector('#themeLensBtn');
      const bar = document.querySelector('#mkCTabs');
      const r = b && b.getBoundingClientRect(), q = bar && bar.getBoundingClientRect();
      return { has: !!b, inBar: !!b && b.parentNode === bar, api: !!(window.HT && HT.lensUI), inside: !!r && !!q && r.width > 0 && r.left >= q.left && r.right <= q.right && r.top >= q.top && r.bottom <= q.bottom, text: b ? b.textContent.trim() : '', icon: !!(b && b.querySelector('svg.ic')) };
    });
    check(mkBtn.has && mkBtn.inBar && mkBtn.api && mkBtn.inside && mkBtn.text === '' && mkBtn.icon, "메이커: 가운데 탭 줄 안에 렌즈 단추(눈 기호만 · 탭 줄 밖으로 나가지 않음)", mkBtn);
    await maker.evaluate(() => HT.lensUI.open());
    const mkMenuHidden = await maker.evaluate(() => [...document.querySelectorAll('#themeLensMenu [data-lens]')].map(b => b.dataset.lens));
    await maker.screenshot({ path: path.join(output, '메이커-렌즈-차림표-1920-1배.png') });
    await maker.evaluate(() => HT.lensUI.close());
    await box.uncheck();
    await maker.waitForFunction(() => !('hidden' in HT.viewer.maker.draft.themes.find(t => t.id === 'military')));
    check(true, "'렌즈에서 숨김'을 끄면 칸이 빠짐(hidden 없음)");
    await maker.waitForTimeout(450);
    await maker.evaluate(() => HT.lensUI.open());
    const mkMenuShown = await maker.evaluate(() => [...document.querySelectorAll('#themeLensMenu [data-lens]')].map(b => b.dataset.lens));
    await maker.evaluate(() => HT.lensUI.close());
    check(!mkMenuHidden.includes('military') && mkMenuShown.includes('military') && mkMenuShown[0] === '', "메이커의 렌즈 차림표: 숨긴 주제는 없고 숨김을 끄면 다시 나옴(맨 위는 '없음')", { hidden: mkMenuHidden, shown: mkMenuShown });
    await makerContext.close();
  }
  check(report.오류.length === 0, '페이지 오류 0', report.오류);
} finally {
  fs.writeFileSync(path.join(output, 'lens-check.json'), JSON.stringify(report, null, 2) + '\n');
  await browser.close();
  server.close();
}
console.log(`렌즈 검사 ${report.검사.length}개 통과 · 오류 ${report.오류.length} — ${output}`);
