/* 집권 단 · 실권 단 표시(감독 선택 D5 결정 1 A · 2 · 3 C + 덧판 x1 A 짙은 칠 · x3 C 두 색 + 색 점, 원칙 "단어로 구분하지 말 것" —
   설계 docs/설계-10건/7-8-단체와-렌즈.md 11절)를 실제 브라우저(1920×1080 · 배율 1)에서 검사합니다.
   견본 samples/sample-lantern.json(등불 연대기 — 따로 세계라 기본팩은 끈 채로)을 설치한 연표: 산호 해상 동맹(진주파 · 닻파 — 집권 · 연정 · 실권)과 하연 연합 왕국(항로당 · 등불당 — 집권 · 연정):
   ① 덧단 — 지위 단 아래 · 지도자 칸 위, 위 = 집권 · 아래 = 실권 · 지도자 칸 바로 위(20px + 틈 3), 줄 단위(실권이 없는 줄은 한 줄만 · 자료 없는 줄 · 다른 트랙은 1px도 그대로) · 표시를 끄면 처음과 같은 높이
   ② 연정 칸 = 위아래 두 색 + 단체 수만큼 색 점(다 들어갈 때만) · 실권 칸 = 단체 색 78%(집권 40%) · 짙은 테두리 · 먹빛 글
   ③ 명목 지도자(제 기간의 절반 이상이 실권과 겹침 — 어린 도선장 물새 아라)는 이름만 50% · 띠 위에 딱지 글(집권 · 실권 · 연정 · 연합) 없음 · 띠 밖 · 겹침 · 잘린 글 없음
   ④ 붕당 렌즈 = 집권 단 ↔ 지도자 칸 맞바꿈(줄 높이 그대로) · 계보 창의 setGroupFocus · 그림 내보내기(두 색 · 점 · 명목 옅게)
   ⑤ 필터 시트의 '단체' 체크 · 범례(자료에 있는 모양만 — 견본 2.0.0에는 연합(자유 등불 대륙 동맹 · 겹친 탭)이 있음 · 단체 자료가 없는 기본팩 연표에는 그 줄들이 없음) · 글자 크기(제 이름 탭 · 상국/관계 탭 · 단체 칸)
   (연합의 겹 탭 모양 · 짝을 모르는 연정은 여기서 보지 않음 — 견본 1.0.0에 그 자료가 없어 뺐던 것. 2.0.0에는 연합이 생겼으나 겹 탭 모양 검사는 아직 되살리지 않음)
   node scripts/power-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge) */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/집권-실권-연합');
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
const settle = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
const TRACK = 'sanho'; // 산호해 — 산호 해상 동맹의 트랙. 견본 2.0.0은 트랙 차례가 문화권 차례(하연 → 설령 → 청림 → 적석 → 백사만 → 산호해 → 서해 백탑령)라 하연 · 적석의 띠는 facts가 그 줄로 옮겨 잼
const LEAGUE = 'lantern-chronicle/p-league';
/* 견본은 따로 세계 — 기본팩을 끈 채로(packs 빈 배열이면 기본팩만 켠 연표) */
const newView = async (packs, baseOff = true) => {
  const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  await ctx.addInitScript(([p, off]) => {
    if (localStorage.getItem('ht.packs.installed')) return;
    localStorage.setItem('ht.packs.installed', JSON.stringify(p));
    if (off) localStorage.setItem('ht.packs.state', JSON.stringify({ 'east-asia-base': { enabled: false } }));
  }, [packs, baseOff]);
  const page = await ctx.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => { if (m.type() === 'error') report.오류.push(m.text()); });
  await page.goto(base + 'index.html');
  await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.timeline);
  return { ctx, page };
};
/* 보기를 옮기고 그 트랙으로 — 그리기가 먼저 끝나야 함(연표의 세로 닻이 옮긴 스크롤을 되돌리지 않게) */
const go = async (page, a, b, track = TRACK) => {
  await page.evaluate(([x, y]) => HT.viewer.timeline.setView(x, y), [a, b]);
  await toTrack(page, track);
};
const toTrack = async (page, track = TRACK) => {
  await settle(page);
  await page.waitForTimeout(150);
  await page.evaluate(id => { const el = document.querySelector(`.tl-track[data-track="${id}"]`); if (el) el.scrollIntoView({ block: 'start' }); }, track);
  await settle(page);
  await page.waitForTimeout(150);
  await page.mouse.move(5, 1070);
  await settle(page);
  /* 느린 때(검사 · 빌드 여럿이 함께 도는 PC)에는 굴린 뒤 그 트랙의 띠가 두 장면 안에 다 그려지지 않거나, 늦게 끝난 그리기가 세로 닻으로 굴린 자리를 되돌린다 —
     띠가 설 때까지 다시 굴리며 기다림(이미 서 있으면 곧바로 지나감) */
  const drawn = () => page.evaluate(id => { const el = document.querySelector(`.tl-track[data-track="${id}"]`); return !el || !!el.querySelector('.tl-band'); }, track);
  for (let i = 0; i < 40 && !(await drawn()); i++) {
    await page.evaluate(id => { const el = document.querySelector(`.tl-track[data-track="${id}"]`); if (el) el.scrollIntoView({ block: 'start' }); }, track);
    await settle(page);
    await page.waitForTimeout(250);
  }
  await settle(page);
};
/* 이름으로 그 띠의 줄(lane)을 화면 가운데로 — 견본 2.0.0에서는 산호해로 옮겨도 하연의 아래쪽 줄(하연 연합 왕국 · 검은물 의병 · 남강 임시정부) · 적석 왕국(재건)이
   한 화면에 들지 않음(트랙 차례가 문화권 차례이고 하연 트랙이 맨 위). 띠가 화면에 그려질 때까지 다시 굴리며 기다림(go와 같은 까닭) */
const showBand = async (page, name) => {
  const scroll = () => page.evaluate(n => {
    for (const tr of HT.viewer.timeline.tracks) {
      const row = tr.rowPeriods.findIndex(r => r.some(p => p.name === n));
      if (row < 0) continue;
      const lane = tr.el.querySelector(`.tl-lane[data-row="${row}"]`);
      if (lane) lane.scrollIntoView({ block: 'center' });
      return;
    }
  }, name);
  const drawn = () => page.evaluate(n => [...document.querySelectorAll('.tl-band')].some(b => { const r = b.getBoundingClientRect(); return (HT.viewer.state.model.byUid.get(b.dataset.uid) || {}).name === n && r.bottom > 0 && r.top < innerHeight; }), name);
  await settle(page);
  await scroll();
  await settle(page);
  await page.waitForTimeout(150);
  for (let i = 0; i < 40 && !(await drawn()); i++) {
    await scroll();
    await settle(page);
    await page.waitForTimeout(250);
  }
};
/* 잴 나라 띠 — 하나씩 그 줄로 옮겨 잰 뒤 산호해 트랙으로 돌아옴(뒤따르는 띠 밖 검사 · 그림은 산호 해상 동맹이 든 화면에서) */
const BANDS = { league: '산호 해상 동맹', union: '하연 연합 왕국', blackwater: '검은물 의병', namgang: '남강 임시정부', jeok2: '적석 왕국(재건)' };
const facts = async page => {
  const out = {};
  for (const [key, name] of Object.entries(BANDS)) {
    await showBand(page, name);
    out[key] = await bandFacts(page, name);
  }
  await toTrack(page);
  return Object.assign(out, await page.evaluate(() => ({ heights: Object.fromEntries(HT.viewer.timeline.tracks.map(t => [t.id, t.height])), root: document.querySelector('#timeline').className })));
};
/* 페이지 안: 나라 띠의 칸 · 높이 */
const bandFacts = (page, bandName) =>
  page.evaluate(bandName => {
    const M = HT.viewer.state.model;
    const inView = b => { const r = b.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; }; // 화면 밖에 남은 옛 그림의 띠보다 화면에 든 띠를
    const band = name => { const all = [...document.querySelectorAll('.tl-band')].filter(b => b.dataset.uid && (M.byUid.get(b.dataset.uid) || {}).name === name); return all.find(inView) || all[0] || null; };
    const cell = el => {
      const cs = getComputedStyle(el);
      const b = el.querySelector('b');
      return { cls: el.className, top: parseFloat(el.style.top), h: parseFloat(el.style.height), text: b ? b.textContent : '', dots: el.querySelectorAll('.gd').length, groups: (el.dataset.groups || '').split(' ').filter(Boolean), bg: cs.backgroundColor, img: cs.backgroundImage, border: cs.borderTopColor, color: cs.color, op: cs.opacity, bop: b ? getComputedStyle(b).opacity : '', bcol: b ? getComputedStyle(b).color : '', bwant: b ? (() => { const d = document.createElement('i'); d.style.color = `color-mix(in srgb, ${cs.color} 50%, var(--paper))`; el.appendChild(d); const v = getComputedStyle(d).color; d.remove(); return v; })() : '', small: el.querySelectorAll('small').length };
    };
    const of = name => {
      const b = band(name);
      if (!b) return null;
      const r = b.getBoundingClientRect();
      return {
        h: r.height,
        groups: [...b.querySelectorAll(':scope > .tl-cell.k-group')].map(cell),
        leaders: [...b.querySelectorAll(':scope > .tl-cell.k-leader')].map(el => Object.assign(cell(el), { name: el.textContent })),
      };
    };
    return of(bandName);
  }, bandName);
/* 띠 밖 · 같은 줄 겹침 · 잘린 글 (단체 칸 · 렌즈 칸 · 작은 지도자 칸) */
const audit = page =>
  page.evaluate(() => {
    const bad = [];
    for (const b of document.querySelectorAll('.tl-band')) {
      const br = b.getBoundingClientRect();
      const cs = [...b.querySelectorAll(':scope > .tl-cell.k-group, :scope > .tl-cell.k-leader.is-mini')];
      for (const el of cs) {
        const r = el.getBoundingClientRect();
        if (r.width < 0.5) continue;
        if (r.left < br.left - 0.5 || r.right > br.right + 0.5 || r.top < br.top - 0.5 || r.bottom > br.bottom + 0.5) bad.push(`띠 밖: ${el.textContent} (${el.className})`);
        const t = el.querySelector('b');
        if (t && !el.classList.contains('is-clip') && t.scrollWidth > t.clientWidth + 0.5) bad.push(`잘린 글: ${t.textContent}`);
        const dots = [...el.querySelectorAll('.gd')].map(d => d.getBoundingClientRect());
        if (dots.some(d => d.left < r.left - 0.5 || d.right > r.right + 0.5)) bad.push(`칸 밖 점: ${el.dataset.groups}`);
      }
      const rows = new Map();
      for (const el of cs) {
        const k = el.style.top;
        if (!rows.has(k)) rows.set(k, []);
        rows.get(k).push(el.getBoundingClientRect());
      }
      for (const list of rows.values()) {
        list.sort((a, c) => a.left - c.left);
        list.forEach((r, i) => { if (i && r.left < list[i - 1].right - 1.01) bad.push(`겹침: ${b.dataset.uid}`); });
      }
    }
    /* 탭 줄: 같은 줄의 탭(제 이름 · 상국 · 관계 탭)이 서로 닿지 않음 */
    for (const lane of document.querySelectorAll('.tl-lane')) {
      const tabs = [...lane.querySelectorAll('.tl-tab, .tl-htab')].filter(el => el.style.visibility !== 'hidden').map(el => ({ r: el.getBoundingClientRect(), t: el.textContent, top: el.style.top }));
      for (let i = 0; i < tabs.length; i++) for (let j = i + 1; j < tabs.length; j++) {
        const a = tabs[i].r, c = tabs[j].r;
        if (Math.abs(a.top - c.top) < 2 && a.left < c.right - 0.5 && c.left < a.right - 0.5) bad.push(`탭 겹침: ${tabs[i].t} × ${tabs[j].t}`);
      }
    }
    return bad;
  });
const shotBand = async (page, file, pad = 30) => {
  const r = await page.evaluate(uid => { const q = document.querySelector(`.tl-band[data-uid="${CSS.escape(uid)}"]`).getBoundingClientRect(); return { y: q.top, h: q.height }; }, LEAGUE);
  await page.screenshot({ path: path.join(output, file), clip: { x: 0, y: Math.max(0, Math.floor(r.y - pad)), width: 1920, height: Math.min(1080 - Math.max(0, Math.floor(r.y - pad)), Math.ceil(r.h + pad * 2)) } });
};
try {
  const { ctx, page } = await newView([sample('sample-lantern')]);
  /* ① 덧단 — 산호 해상 동맹(1031~1402)이 다 드는 보기 */
  await go(page, 1000, 1450);
  const on = await facts(page);
  const pw = on.league.groups.filter(c => !/is-real/.test(c.cls));
  const rl = on.league.groups.filter(c => /is-real/.test(c.cls));
  const ld = on.league.leaders;
  const t0 = pw.length ? pw[0].top : NaN;
  check(pw.length === 6 && rl.length === 1 && pw.every(c => c.top === t0 && c.h === 20) && rl.every(c => c.top === t0 + 23 && c.h === 20) && ld.length === 18 && ld.every(c => c.top === t0 + 46 && c.h === 22), '덧단: 위 = 집권 · 아래 = 실권(20px + 틈 3) · 지도자 칸 바로 위 (산호 해상 동맹)', { power: pw.map(c => c.top), real: rl.map(c => c.top), leader: ld.map(c => c.top).slice(0, 3) });
  await page.evaluate(() => HT.viewer.timeline.setShow({ groups: false }));
  await go(page, 1000, 1450);
  const off = await facts(page);
  /* 견본 2.0.0은 산호해 · 하연 밖에도 단체 자료가 있는 트랙이 셋 — 청림(청림 생태 자치연방: 청림-백사 생태연대 · 자유 등불 대륙 동맹) · 백사만(광학혁신당 · 도가니보수당) ·
     서해 백탑령(은항 삼부회 시민동맹). 셋 다 보기 안 줄에 실권 칸이 없어 한 줄(+23)씩. 단체 자료가 없는 트랙(설령 · 적석)만 1px도 그대로 */
  const GROUPED = ['cheongnim', 'baeksa', 'seohae'];
  const others = Object.keys(on.heights).filter(k => k !== TRACK && k !== 'hayeon' && !GROUPED.includes(k) && on.heights[k] !== off.heights[k]);
  const grouped = GROUPED.filter(k => on.heights[k] - off.heights[k] !== 23);
  check(Math.abs(on.league.h - off.league.h - 46) < 0.01 && Math.abs(on.union.h - off.union.h - 23) < 0.01 && on.heights[TRACK] - off.heights[TRACK] === 46 && on.heights.hayeon - off.heights.hayeon === 23 && Math.abs(on.blackwater.h - off.blackwater.h) < 0.01 && Math.abs(on.namgang.h - off.namgang.h) < 0.01 && Math.abs(on.jeok2.h - off.jeok2.h) < 0.01 && !others.length && !grouped.length,
    "줄 단위: 산호 해상 동맹 줄만 +46(집권 + 실권 두 줄) · 하연 연합 왕국 줄은 +23(정당 — 실권 없음, 한 줄) · 단체 없는 줄(검은물 의병 · 남강 임시정부 · 적석 왕국(재건)) 그대로 · 단체 자료가 있는 다른 트랙(청림 · 백사만 · 서해 백탑령)은 한 줄씩 +23 · 단체 자료가 없는 트랙(설령 · 적석)은 그대로",
    { league: [on.league.h, off.league.h], union: [on.union.h, off.union.h], blackwater: [on.blackwater.h, off.blackwater.h], namgang: [on.namgang.h, off.namgang.h], jeok2: [on.jeok2.h, off.jeok2.h], heights: [on.heights, off.heights], others, grouped });
  check(!off.league.groups.length && !off.union.groups.length && !off.league.leaders.some(c => /is-nominal/.test(c.cls)), "표시 체크 '단체'를 끄면 단 · 명목 옅게가 모두 빠짐");
  await page.evaluate(() => HT.viewer.timeline.setShow({ groups: true }));
  await go(page, 1000, 1450);
  /* ② 연정 · 실권 */
  const f2 = await facts(page);
  const two = f2.league.groups.filter(c => /is-two/.test(c.cls));
  check(two.length === 1 && two.every(c => /linear-gradient/.test(c.img) && (c.dots === 0 || c.dots === c.groups.length)) && two.some(c => c.dots === 2 && c.groups.length === 2 && c.text), '연정 칸 = 위아래 두 색 + 함께 집권한 단체 수만큼 점(다 들어갈 때만 — 진주파 · 닻파 1160~1200)', two.map(c => [c.groups.length, c.dots, c.text]));
  const probe = await page.evaluate(uid => {
    const b = document.querySelector(`.tl-band[data-uid="${CSS.escape(uid)}"]`);
    const real = b.querySelector('.tl-cell.k-group.is-real');
    const pw = b.querySelector('.tl-cell.k-group:not(.is-real):not(.is-two):not(.is-solo)');
    const mk = (c, k) => { const d = document.createElement('i'); d.style.cssText = `position:absolute;left:-99px;width:4px;height:4px;background:color-mix(in srgb, ${c} ${k}%, var(--paper));color:color-mix(in srgb, ${c} 10%, var(--paper-ink));border-top:1px solid color-mix(in oklab, ${c} 64%, var(--paper-ink))`; b.appendChild(d); const s = getComputedStyle(d); const o = { bg: s.backgroundColor, color: s.color, border: s.borderTopColor }; d.remove(); return o; };
    const rc = real.style.getPropertyValue('--c').trim();
    const pc = pw.style.getPropertyValue('--c').trim();
    return { real: { bg: getComputedStyle(real).backgroundColor, color: getComputedStyle(real).color, border: getComputedStyle(real).borderTopColor }, want: mk(rc, 78), power: getComputedStyle(pw).backgroundColor, want40: mk(pc, 40).bg };
  }, LEAGUE);
  check(probe.real.bg === probe.want.bg && probe.real.color === probe.want.color && probe.real.border === probe.want.border && probe.power === probe.want40, '실권 칸 = 단체 색 78% · 그 색 64%의 짙은 테두리 · 먹빛 글 / 집권 칸 = 40%', probe);
  /* ③ 명목 · 딱지 글 없음 · 띠 밖 */
  const sameColor = (x, y) => { const n = t => (t.match(/-?[\d.]+/g) || []).map(Number); const [p, q] = [n(x), n(y)]; return p.length > 0 && p.length === q.length && p.every((v, i) => Math.abs(v - q[i]) < 1e-4); }; // color-mix의 끝자리 반올림
  const nom = f2.league.leaders.filter(c => /is-nominal/.test(c.cls));
  check(nom.map(c => c.name).join() === '물새 아라' && nom.every(c => Number(c.bop) === 1 && sameColor(c.bcol, c.bwant) && Number(c.op) === 1) && !f2.union.leaders.some(c => /is-nominal/.test(c.cls)), '명목 지도자(제 기간의 절반 이상이 실권과 겹침 — 물새 아라 1340~1352)는 이름 글만 칸 글색과 종이를 반씩 섞은 고른 색(예전 투명도 .5 — 서고 모양 1단) · 실권이 없는 하연 연합 왕국에는 없음', nom.map(c => [c.name, c.bop, c.bcol, c.bwant]));
  check(f2.league.groups.concat(f2.union.groups).every(c => !c.small && !/^(집권|실권|연정|연합)/.test(c.text)), '단체 칸에 딱지 글(집권 · 실권 · 연정)이 없음 — 모양 · 색으로만', f2.league.groups.map(c => c.text));
  check((await audit(page)).length === 0, '단체 칸 · 점 · 탭이 띠 밖으로 나가지 않고 겹치지 않고 글자가 잘리지 않음(1000~1450)', await audit(page));
  await shotBand(page, '집권-실권-연정-1000-1450-1배.png');
  for (const [a, b] of [[600, 1700], [0, 2000]]) {
    await go(page, a, b);
    check((await audit(page)).length === 0, `넓은 보기(${a}~${b})에서도 띠 밖 · 겹침 · 잘린 글 없음 — 좁은 칸은 이름 → 첫 글자 → 점만 → 칠만`, await audit(page));
  }
  await shotBand(page, '집권-실권-연정-0-2000-1배.png');
  /* ④ 붕당 렌즈 맞바꿈 · 계보 창의 setGroupFocus · 그림 내보내기 */
  await go(page, 1000, 1450);
  const before = await facts(page);
  await page.evaluate(() => HT.lensUI.setLens('faction'));
  await go(page, 1000, 1450);
  const lens = await facts(page);
  const big = lens.league.groups.filter(c => /k-lens/.test(c.cls));
  const mini = lens.league.leaders.filter(c => /is-mini/.test(c.cls));
  check(Math.abs(lens.league.h - before.league.h) < 0.01 && big.length && big.every(c => c.h === 22 && c.top === t0 + 46) && mini.length && mini.every(c => c.h === 20 && c.top === t0) && lens.league.groups.filter(c => /is-real/.test(c.cls)).every(c => c.top === t0 + 23), '붕당 렌즈 = 집권 단 ↔ 지도자 칸 맞바꿈(집권 칸이 지도자 자리 22px · 지도자 칸이 집권 줄 20px · 실권 줄 그대로 · 줄 높이 그대로)', { big: big.map(c => c.top), mini: mini.map(c => c.top).slice(0, 3), h: [before.league.h, lens.league.h] });
  check((await audit(page)).length === 0, '띠 밖 · 겹침 · 잘린 글 없음(붕당 렌즈)', await audit(page));
  await shotBand(page, '붕당-렌즈-맞바꿈-1000-1450-1배.png');
  await page.evaluate(() => HT.lensUI.setLens(null));
  await go(page, 1000, 1450);
  const gf = await page.evaluate(() => {
    const tl = HT.viewer.timeline;
    tl.setGroupFocus('lantern-chronicle/g-pearl');
    const cells = [...document.querySelectorAll('.tl-cell.k-group')];
    const r = { on: cells.filter(c => c.classList.contains('is-gf')).map(c => c.dataset.groups), dim: cells.filter(c => !c.classList.contains('is-gf')).map(c => getComputedStyle(c).opacity) };
    tl.setGroupFocus(null);
    r.after = document.querySelectorAll('.tl-cell.k-group.is-gf').length + (document.querySelector('#timeline').classList.contains('group-focus') ? 1 : 0);
    return r;
  });
  check(gf.on.length && gf.on.every(g => g.split(' ').includes('lantern-chronicle/g-pearl')) && gf.dim.length && gf.dim.every(o => Math.abs(Number(o) - 0.4) < 0.01) && gf.after === 0, '계보 창의 setGroupFocus: 그 단체(진주파)의 칸만 진하게 · 나머지 단체 칸 .4 · 풀면 그대로', gf);
  /* 그림 내보내기 — 물새 아라(12년)의 이름이 칸에 드는 보기(1100~1420: 진주파 · 닻파 연정 1160~1200도 듦) */
  await go(page, 1100, 1420);
  const svg = await page.evaluate(() => HT.viewer.timeline.toSVG({ width: 1800 }));
  check(/clipPath id="tlgrp/.test(svg) && /<circle cx="[\d.]+" cy="[\d.]+" r="2\.5"/.test(svg) && /<text fill-opacity="0\.5" /.test(svg) && !/>(집권|실권|연정|연합)</.test(svg), '그림 내보내기: 연정 칸 두 색 · 색 점 · 명목 지도자 이름 옅게 · 딱지 글 없음');
  fs.writeFileSync(path.join(output, '그림-내보내기-1100-1420.svg'), svg);
  /* ⑤ 필터 시트의 '단체' 체크 · 범례 — 띠 위에 딱지 글이 없으므로 모양의 뜻은 범례에(자료에 있을 때만) */
  await go(page, 1000, 1450);
  const flip = v => page.evaluate(x => { const el = document.querySelector('#groupToggle'); el.checked = x; el.dispatchEvent(new Event('change', { bubbles: true })); }, v);
  const tog = await page.evaluate(() => { const el = document.querySelector('#groupToggle'); return el ? { checked: el.checked, label: el.closest('label').textContent.trim() } : null; });
  await flip(false);
  await go(page, 1000, 1450);
  const togOff = await facts(page);
  const savedOff = await page.evaluate(() => (HT.viewer.state.ui.show || {}).groups);
  await flip(true);
  await go(page, 1000, 1450);
  const togOn = await facts(page);
  check(tog && tog.checked && tog.label === '단체' && !togOff.league.groups.length && savedOff === false && togOn.league.groups.length === on.league.groups.length && togOn.league.h === on.league.h, "필터 시트의 '단체' 체크: 기본 켬 · 끄면 단체 단이 숨고 설정에 적힘 · 다시 켜면 처음 그대로", { tog, savedOff, off: togOff.league.groups.length, on: togOn.league.groups.length });
  const legendLines = async p => {
    await p.evaluate(() => { if (document.querySelector('#legend').hidden) document.querySelector('#legendBtn').click(); });
    await settle(p);
    return p.evaluate(() => [...document.querySelectorAll('#legend li')].filter(li => li.querySelector('svg.lg-seam')).map(li => li.textContent.trim().slice(0, 10)));
  };
  const WORDS = ['집권한 단체', '함께 집권', '실권을 쥔 집단'];
  const lg = await legendLines(page);
  check(WORDS.every(w => lg.some(t => t.startsWith(w))) && lg.some(t => t.startsWith('겹친 탭')), '범례: 집권한 단체 · 함께 집권(색 점) · 실권을 쥔 집단 — 견본은 연표와 같은 모양 · 견본 2.0.0에는 연합(자유 등불 대륙 동맹)이 있어 겹친 탭도(자료가 없으면 빠지는 것은 아래 기본팩 연표에서)', lg);
  await page.locator('#legend').screenshot({ path: path.join(output, '범례-단체-1배.png') });
  await page.evaluate(() => document.querySelector('#legendBtn').click());
  /* 글자 위아래 틈 — 감독 선택 2026-10-13 "글자 한 단계 작게"(줄 높이는 그대로): 제 이름 탭 9px · 상국/관계 탭 8.5px · 단체 칸 8.5px, 탭의 폭도 작아진 글에 맞춤
     (글꼴에 물린 먹의 자리는 여기서 재지 않음 — 글꼴이 바뀌면 달라짐. 크기와 폭만) — 상국 탭은 화면에 든 첫 상국 · 관계 탭 */
  await go(page, 1000, 1450);
  const type = await page.evaluate(uid => {
    const band = document.querySelector(`.tl-band[data-uid="${CSS.escape(uid)}"]`);
    const lane = band.parentElement;
    /* 탭 안 글 전체의 상자(첫 글 왼쪽 ~ 마지막 글 오른쪽) — 견본의 제 이름 탭은 이름 뒤에 종류 · 지위(연맹 · 도선장)가 붙음 */
    const textBox = el => { const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let n, box = null; while ((n = w.nextNode())) if (n.nodeValue.trim()) { const r = document.createRange(); r.selectNodeContents(n); const q = r.getBoundingClientRect(); box = box ? { left: Math.min(box.left, q.left), right: Math.max(box.right, q.right) } : { left: q.left, right: q.right }; } return box && { left: box.left, right: box.right, width: box.right - box.left }; };
    const one = el => { if (!el) return null; const r = el.getBoundingClientRect(), t = textBox(el); return { text: el.textContent.trim(), band: (HT.viewer.state.model.byUid.get(el.dataset.band || el.dataset.uid) || {}).name || "", size: getComputedStyle(el.querySelector('b') || el).fontSize, padL: +(t.left - r.left).toFixed(2), padR: +(r.right - t.right).toFixed(2), tw: +t.width.toFixed(2) }; };
    const cell = [...band.querySelectorAll(':scope > .tl-cell.k-group:not(.k-lens)')].find(el => el.querySelector('b'));
    return { name: one(lane.querySelector(`.tl-tab[data-uid="${CSS.escape(uid)}"]`)), host: one(document.querySelector('.tl-htab:not(.k-coal)')), cell: one(cell) };
  }, LEAGUE);
  check(type.name && type.host && type.cell && type.name.size === '9px' && type.host.size === '8.5px' && type.cell.size === '8.5px', '글자 한 단계 작게: 제 이름 탭 9px · 상국/관계 탭 8.5px · 단체 칸 8.5px', type);
  check(type.name.padR - type.name.padL < type.name.tw * 0.08 + 1 && Math.abs(type.host.padR - type.host.padL) < 1.5, '탭의 폭도 작아진 글에 맞춤 — 글 뒤의 여백이 앞 여백보다 넓게 남지 않음', type);
  const plain = await newView([], false);
  const lg0 = await legendLines(plain.page);
  check(!lg0.some(t => WORDS.concat('겹친 탭').some(w => t.startsWith(w))), '단체 자료가 없는 연표(기본팩)의 범례에는 그 줄이 없음', lg0);
  await plain.ctx.close();
  check(report.오류.length === 0, '페이지 오류 0', report.오류);
  await ctx.close();
} finally {
  fs.writeFileSync(path.join(output, 'power-check.json'), JSON.stringify(report, null, 2) + '\n');
  await browser.close();
  server.close();
}
console.log(`집권 · 실권 검사 ${report.검사.length}개 통과 · 오류 ${report.오류.length} — ${output}`);
