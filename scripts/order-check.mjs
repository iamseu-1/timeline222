/* 띠 배치의 기준점(배열 기준) · 시대 접기 · 간지 설정(설계 docs/설계-10건/6-모아-보기와-배치.md 결정 6 · 7 · 8 — 감독 선택 D4 6 C · 7 A · 8 B)을 실제 브라우저 · 실제 포인터로 검사합니다.
   node scripts/order-check.mjs <검사할 폴더> <결과 폴더>
   ㉮ 연표(견본 samples/sample-lantern.json — 등불 연대기만 켬 · 가상 자료): 배열 — 상위 민족(대륙인)이 북 → 남이어도 'start'로 끊은 하연인 묶음 안은 시작 해 차례(민족 칸이 조각나지 않음) ·
      날짜 칸의 간지 설정(줄 제목 '불씨해' · 해마다 칸에 아홉 이름 · 첫 이름 '새벽'의 해 강조 · 칸 밖으로 넘치지 않음) ·
      펼친 시대 구분 줄의 왼쪽 이름 단추가 글 칸과 1px도 다르지 않음(단추를 글 칸으로 바꿔 찍은 1배 그림을 화소로 견줌) · 맨 처음 줄(공통)만 이름 끝에 ▾ · 눌러 접으면 공통 줄까지 '시대 구분 3줄 ▸' 한 줄(22px · 감독 건의 2026-10-14 2번 · 앞의 네 줄(공통 · 설령 · 청림 · 백사만 — 가닥은 넷까지)마다 시대 색 막대 ·
      막대가 줄 밖으로 나가지 않음) · 접힘 기억(ht.ui axisOpen의 'epochFold')이 다시 열어도 남음 · 다시 눌러 펼침 · 필터 '간지'로 줄을 끄고 켬
      (북 → 남 정렬 자체는 이 검사에서 보지 않습니다 — 견본 1.0.0에 그런 묶음이 없어 뺐음. 2.0.0에는 북 → 남인 청림인 묶음이 생겼으나 아직 되살리지 않음)
   ㉯ 연표(동아시아 기본팩 + yearCycle: false인 가상 DLC): 처음 열면 간지 줄이 꺼지고 필터의 체크도 꺼짐 · 보는 사람이 다시 켜면 육십갑자 줄 '간지'가 나오고 다시 열어도 켠 그대로
   ㉰ 메이커(견본을 작업본으로): 바탕 자료 민족 표의 '배열 기준' 고르기 칸 → 작업본 rowOrder · 시대 편집 창의 '남북 위치' 칸(회색 예시 글 없음) · 팩 정보의 '날짜 칸의 간지 설정'(다른 순환 → 끔)
      (검사 창의 '남북 위치 없음'은 견본의 나라가 모두 남북 위치를 적어 보지 않습니다)
   그림(모두 1920×1080 · 배율 1)은 결과 폴더에. 자료는 모두 독립 브라우저의 저장소에만 넣고, 가상 자료에는 실제 역사 이름을 쓰지 않습니다.
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)로 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/띠-배치-기준점');
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
const sample = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const P = `${sample.id}/`; // 견본 항목 uid의 머리 (lantern-chronicle/)
const offDlc = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'order-check-off', name: '가상 간지 끔 묶음', version: '1.0.0', yearCycle: false,
  tracks: [{ id: 'oc-wind', name: '바람 들', color: '#b6c398', order: 930 }],
  periods: [{ id: 'oc-p', track: 'oc-wind', name: '바람 나라', start: 100, end: 300 }],
};
/* 하연 트랙의 줄 (하연인 묶음 — 'start'로 끊어 시작 해 차례 · 승계로 이어진 나라는 한 줄) */
const WANT = ['안개 부족 연맹→등불 왕국→하연 총관부', '아랫물국', '윗물국', '갈대 공국', '빛나루 자유시', '물안개 왕국', '하연 부흥국→하연 연합 왕국→하연 공화국', '검은물 의병', '남강 임시정부'];
/* 간지 설정: 견본의 yearCycle (이름 아홉 · 첫 해 1 · 줄 제목 '불씨해') */
const CYCLE = sample.yearCycle;

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100% · 배율 1', 검사: [], 오류: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};
const newPage = async (seed, file) => {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block', reducedMotion: 'reduce' });
  await context.addInitScript(seed => {
    if (sessionStorage.getItem('order-check-seeded')) return;
    sessionStorage.setItem('order-check-seeded', '1');
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
const settle = page => page.waitForTimeout(1300);
/** 두 1배 그림(PNG)의 화소 차이 — 브라우저의 캔버스로 풀어 견줌: { n: 다른 화소 수, big: 색값이 1보다 크게 다른 화소 수, box } */
async function pixelDiff(page, a, b) {
  return page.evaluate(
    async ([a, b]) => {
      const load = src => new Promise((ok, no) => { const im = new Image(); im.onload = () => ok(im); im.onerror = no; im.src = src; });
      const [ia, ib] = await Promise.all([load(a), load(b)]);
      const px = im => { const c = document.createElement('canvas'); c.width = im.width; c.height = im.height; const g = c.getContext('2d'); g.drawImage(im, 0, 0); return g.getImageData(0, 0, im.width, im.height).data; };
      const da = px(ia), db = px(ib);
      let n = 0, big = 0, x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1;
      for (let i = 0; i < da.length; i += 4) {
        if (da[i] === db[i] && da[i + 1] === db[i + 1] && da[i + 2] === db[i + 2]) continue;
        n++;
        if (Math.max(Math.abs(da[i] - db[i]), Math.abs(da[i + 1] - db[i + 1]), Math.abs(da[i + 2] - db[i + 2])) > 1) big++;
        const p = i / 4, x = p % ia.width, y = Math.floor(p / ia.width);
        x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
      }
      return { n, big, box: n ? [x0, y0, x1, y1] : null, size: [ia.width, ia.height] };
    },
    ['data:image/png;base64,' + a.toString('base64'), 'data:image/png;base64,' + b.toString('base64')],
  );
}
const axisRect = page => page.evaluate(() => { const r = __tl.axisEl.getBoundingClientRect(); return { x: Math.floor(r.x), y: Math.floor(r.y), width: Math.ceil(r.width), height: Math.ceil(r.height) }; });

try {
  /* ================= ㉮ 연표 — 견본만 켬 ================= */
  {
    const page = await newPage({ 'ht.packs.installed': [sample], 'ht.packs.state': { 'east-asia-base': { enabled: false } } }, 'index.html');
    /* 배열 (견본 전체가 보이는 범위 — 보이지 않는 줄은 접혀 민족 칸의 높이가 0) */
    await page.evaluate(() => { __tl.setView(-700, 1800); __tl.bodyEl.scrollTop = 0; });
    await settle(page);
    const rows = await page.evaluate(() => {
      const tr = __tl.tracks.find(t => t.id === 'hayeon');
      return {
        rows: tr.rowPeriods.map(r => r.map(p => p.name).join('→')),
        heads: tr.rowPeriods.map(r => ({ start: r[0].start, ns: HT.northOf(r[0]) })),
        chips: Object.fromEntries(__tl.tracks.map(t => [t.id, [...t.el.querySelectorAll('.tl-people')].filter(el => el.getBoundingClientRect().height > 0).map(el => el.textContent.trim())])), // 트랙 id로 — 트랙 차례는 문화권 차례를 따름(하연이 맨 위)
      };
    });
    const byStart = rows.heads.every((h, i) => !i || rows.heads[i - 1].start <= h.start);
    const byNorth = rows.heads.every((h, i) => !i || rows.heads[i - 1].ns >= h.ns);
    check(JSON.stringify(rows.rows) === JSON.stringify(WANT) && byStart && !byNorth, "배열: 상위 민족(대륙인)이 북 → 남이어도 'start'로 끊은 하연인 묶음 안은 시작 해 차례(남북 값 차례와 다름) · 승계로 이어진 나라는 한 줄", rows);
    check(Object.values(rows.chips).every(c => c.length && new Set(c).size === c.length) && JSON.stringify(rows.chips.hayeon) === JSON.stringify(['대륙인', '하연인']), '민족 칸이 조각나지 않음(트랙마다 같은 이름의 칸이 둘 이상 없음 — 하연은 대륙인 · 하연인)', rows.chips);
    /* 간지 설정 — DLC의 순환 (해마다 칸이 보이게 좁힘) */
    await page.evaluate(() => { __tl.setView(80, 120); __tl.bodyEl.scrollTop = 0; });
    await settle(page);
    const cyc = await page.evaluate(() => {
      const row = document.querySelector('.tl-axis-row.is-ganji');
      const cells = [...row.querySelectorAll('.tl-acell')];
      const over = cells.filter(el => el.scrollWidth > el.clientWidth + 1).map(el => el.textContent);
      const cr = row.querySelector('.tl-axis-cells').getBoundingClientRect();
      const out = cells.filter(el => { const r = el.getBoundingClientRect(); return r.top < cr.top - 0.5 || r.bottom > cr.bottom + 0.5; }).length;
      return { corner: row.querySelector('.tl-corner').textContent, texts: cells.map(el => el.textContent), first: cells.filter(el => el.classList.contains('is-gapja')).map(el => el.title), over, out };
    });
    const [first, second] = CYCLE.names;
    check(cyc.corner === CYCLE.label, `날짜 칸의 줄 제목이 DLC가 준 줄 제목('${CYCLE.label}')`, cyc.corner);
    check(cyc.texts.includes(first) && cyc.texts.includes(second) && cyc.texts.every(t => CYCLE.names.includes(t)) && !cyc.texts.some(t => /^[갑을병정무기경신임계][자축인묘진사오미신유술해]$/.test(t)), '해마다 칸에 DLC의 이름(육십갑자 아님)', cyc.texts.slice(0, 14));
    check(cyc.first.length >= 3 && cyc.first.every(t => t.includes(first) && (parseInt(t, 10) - CYCLE.start) % CYCLE.names.length === 0), `첫 이름의 해(첫 해 ${CYCLE.start}년에서 ${CYCLE.names.length}해마다)가 갑자년처럼 강조`, cyc.first);
    check(!cyc.over.length && !cyc.out, '간지 줄 칸의 글이 칸 밖으로 넘치지 않고 칸이 줄 밖으로 나가지 않음', { over: cyc.over, out: cyc.out });
    await page.mouse.move(2, 2);
    await page.screenshot({ path: path.join(output, '연표-간지-설정-1920-1배.png') });

    /* 시대 접기 — 펼친 모습은 지금 그대로(왼쪽 이름 단추 = 글 칸). 견본의 나라별 시대 구분은 설령 · 청림 · 백사만 · 산호해 · 서해 백탑령 다섯 트랙에 셋씩(겹치지 않아 한 줄씩) —
       세 시대가 모두 보이는 범위에서 봄. 나라 줄은 연표의 트랙 차례(문화권 차례 — 견본 파일의 트랙 차례와 다름)로 놓임 */
    const EPOCH_VIEW = [100, 1500];
    const trackOrder = await page.evaluate(() => __tl.tracks.map(t => t.id));
    const byTrack = trackOrder.map(id => sample.tracks.find(t => t.id === id)).filter(Boolean).map(t => ({ name: t.name, list: sample.epochs.filter(e => e.track === t.id) })).filter(t => t.list.length);
    const common = sample.epochs.filter(e => !e.track);
    const seen = common.concat(byTrack.flatMap(t => t.list)).filter(e => e.start < EPOCH_VIEW[1] && (e.ongoing || e.end > EPOCH_VIEW[0]));
    const lines = (common.length ? 1 : 0) + byTrack.length; // 접으면 한 줄로 묶이는 시대 구분 줄 수(공통 줄 포함)
    /* 접은 줄(22px)의 가닥은 넷까지(js/timeline.js 접은 묶음 줄 — Math.min(줄 수, 4)) — 견본 2.0.0은 여섯 줄이라 앞의 넷(공통 · 설령 · 청림 · 백사만)만 가닥이 됨.
       막대 색은 모델의 시대 색(연표가 고른 색으로 맞춘 것 — 견본의 청림 시대 둘은 같은 색이 됨)으로 견줌 */
    const STRANDS = Math.min(lines, 4);
    const strandSeen = (common.length ? [common] : []).concat(byTrack.map(t => t.list)).slice(0, STRANDS).flat().filter(e => seen.includes(e));
    const epochColor = await page.evaluate(() => Object.fromEntries(__state.model.epochs.map(e => [e.id, e.color])));
    await page.evaluate(v => { __tl.setView(v[0], v[1]); __tl.bodyEl.scrollTop = 0; }, EPOCH_VIEW);
    await settle(page);
    const open0 = await page.evaluate(() => ({ epochRows: document.querySelectorAll('.tl-axis-row.is-epoch').length, btns: [...document.querySelectorAll('.tl-axis-row.is-epoch button.tl-corner')].map(b => b.textContent), epochRowsH: [...document.querySelectorAll('.tl-axis-row.is-epoch')].reduce((s, r) => s + Math.round(r.getBoundingClientRect().height), 0), h: Math.round(__tl.axisEl.getBoundingClientRect().height) }));
    check(open0.epochRows === lines && JSON.stringify(open0.btns) === JSON.stringify(['시대 구분▾', ...byTrack.map(t => `${t.name} 시대`)]), '펼친 날짜 칸: 공통 줄 + 나라 줄 다섯(설령 · 청림 · 백사만 · 산호해 · 서해 백탑령 — 연표의 트랙 차례) — 여섯 다 왼쪽 이름이 접기 단추 · 맨 처음 줄만 ▾', open0);
    await page.screenshot({ path: path.join(output, '연표-시대-펼침-1920-1배.png') });
    const clip = await axisRect(page);
    const withBtn = await page.screenshot({ clip });
    await page.evaluate(() => document.querySelectorAll('.tl-axis-row.is-epoch button.tl-corner').forEach(b => { const d = document.createElement('div'); d.className = 'tl-corner'; d.innerHTML = b.innerHTML; b.replaceWith(d); }));
    await page.waitForTimeout(100);
    const withDiv = await page.screenshot({ clip });
    const same = await pixelDiff(page, withBtn, withDiv);
    check(same.n === 0, '펼친 시대 구분 줄의 왼쪽 이름 단추가 예전 글 칸과 1px도 다르지 않음(같은 자리의 1배 그림 화소 비교)', same);
    await page.evaluate(() => __tl.relayout());
    await settle(page);

    /* 눌러 접기 */
    await page.click('.tl-axis-row.is-epoch button.tl-corner');
    await settle(page);
    const shut = await page.evaluate(() => {
      const g = document.querySelector('.tl-axis-cells[data-group="epochs"]');
      const row = g && g.closest('.tl-axis-row');
      const cr = g && g.getBoundingClientRect();
      const bars = g ? [...g.querySelectorAll('.tl-gbar')].map(b => { const r = b.getBoundingClientRect(); return { c: b.style.getPropertyValue('--c'), top: Math.round(r.top - cr.top), inside: r.top >= cr.top - 0.5 && r.bottom <= cr.bottom + 0.5 && r.left >= cr.left - 0.5 && r.right <= cr.right + 0.5 }; }) : [];
      return { btn: row && row.querySelector('.tl-group-btn').textContent, h: row && Math.round(row.getBoundingClientRect().height), epochRows: document.querySelectorAll('.tl-axis-row.is-epoch').length, bars, strands: [...new Set(bars.map(b => b.top))].length, axisH: Math.round(__tl.axisEl.getBoundingClientRect().height), ui: __state.ui.axisOpen };
    });
    check(shut.btn === `시대 구분${lines}줄 ▸` && shut.h === 22 && shut.epochRows === 0, `누르면 공통 줄까지 시대 구분 줄이 모두 '시대 구분 ${lines}줄 ▸' 한 줄(22px)로(감독 건의 2026-10-14 2번)`, shut);
    const colors = list => [...new Set(list)].sort().join();
    check(shut.bars.length === strandSeen.length && shut.strands === STRANDS && shut.bars.every(b => b.inside) && colors(shut.bars.map(b => b.c)) === colors(strandSeen.map(e => epochColor[e.id])), `접힌 줄: 앞의 ${STRANDS}줄이 한 가닥씩(가닥은 넷까지) · 시대마다 제 색 막대(${strandSeen.length}개) · 줄 밖으로 나가지 않음`, shut.bars);
    check(open0.epochRowsH > 22 && open0.h - shut.axisH === open0.epochRowsH - 22, `날짜 칸이 접은 만큼(시대 구분 줄 ${open0.epochRowsH}px → 22px) 낮아짐`, { before: open0.h, after: shut.axisH, epochRowsH: open0.epochRowsH });
    check(Array.isArray(shut.ui) && shut.ui.includes('epochFold'), "접힘 기억: 보기 설정 axisOpen에 'epochFold'", shut.ui);
    await page.mouse.move(2, 2);
    await page.screenshot({ path: path.join(output, '연표-시대-접기-1920-1배.png') });
    await page.reload();
    await page.waitForFunction(() => window.__tl && window.__state && window.__state.model);
    await settle(page);
    check(await page.evaluate(() => !!document.querySelector('.tl-axis-cells[data-group="epochs"]')), '다시 열어도 접힌 채');
    await page.click('.tl-axis-row.is-group .tl-group-btn[data-axis-group="epochFold"]');
    await settle(page);
    check(await page.evaluate(n => document.querySelectorAll('.tl-axis-row.is-epoch').length === n && !(__state.ui.axisOpen || []).includes('epochFold'), lines), '접힌 줄을 누르면 다시 공통 줄 · 나라별 줄 · 기억에서 빠짐');
    /* 필터 '간지'로 끄고 켬 */
    await page.evaluate(() => document.getElementById('ganjiToggle').click());
    await settle(page);
    const g0 = await page.evaluate(() => ({ row: !!document.querySelector('.tl-axis-row.is-ganji'), ui: __state.ui.show.ganji }));
    await page.evaluate(() => document.getElementById('ganjiToggle').click());
    await settle(page);
    const g1 = await page.evaluate(() => ({ row: !!document.querySelector('.tl-axis-row.is-ganji'), label: (document.querySelector('.tl-axis-row.is-ganji .tl-corner') || {}).textContent }));
    check(!g0.row && g0.ui === false && g1.row && g1.label === CYCLE.label, "필터 '간지'로 간지 줄(DLC의 순환)을 끄고 켬", { g0, g1 });
    await page.context().close();
  }

  /* ================= ㉯ 연표 — DLC가 간지 줄을 끔(yearCycle: false) ================= */
  {
    const page = await newPage({ 'ht.packs.installed': [offDlc] }, 'index.html');
    await page.evaluate(() => { __tl.setView(1900, 2000); __tl.bodyEl.scrollTop = 0; });
    await settle(page);
    const a = await page.evaluate(() => ({ row: !!document.querySelector('.tl-axis-row.is-ganji'), box: document.getElementById('ganjiToggle').checked, seen: __state.ui.cycleSeen, cycle: __state.model.yearCycle }));
    check(!a.row && !a.box && a.cycle && a.cycle.off && JSON.stringify(a.seen) === '["order-check-off"]', '간지 줄을 끈 DLC를 처음 켜면 간지 줄이 꺼지고 필터의 체크도 꺼짐', a);
    await page.evaluate(() => document.getElementById('ganjiToggle').click());
    await settle(page);
    const b = await page.evaluate(() => ({ row: !!document.querySelector('.tl-axis-row.is-ganji'), label: (document.querySelector('.tl-axis-row.is-ganji .tl-corner') || {}).textContent, gapja: [...document.querySelectorAll('.tl-axis-row.is-ganji .is-gapja')].map(e => e.title) }));
    check(b.row && b.label === '간지' && b.gapja.some(t => /갑자/.test(t)), "보는 사람이 필터 '간지'로 다시 켜면 육십갑자 줄", b);
    await page.mouse.move(2, 2);
    await page.screenshot({ path: path.join(output, '연표-간지-다시-켬-1920-1배.png') });
    await page.reload();
    await page.waitForFunction(() => window.__tl && window.__state && window.__state.model);
    await settle(page);
    check(await page.evaluate(() => !!document.querySelector('.tl-axis-row.is-ganji') && document.getElementById('ganjiToggle').checked), '다시 열어도 보는 사람이 켠 간지 줄 그대로(보는 사람이 바꾼 것이 이김)');
    await page.context().close();
  }

  /* ================= ㉰ 메이커 — 견본을 작업본으로 ================= */
  {
    const page = await newPage({ 'ht.maker.draft': sample }, 'dlc-maker.html');
    await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden);
    await settle(page);
    /* 바탕 자료 민족 표(도구 창)의 배열 기준 칸 — 견본의 민족: 대륙인 northSouth · 하연인 start · 나머지는 비움(상위 민족 따름) */
    const peoples = sample.peoples.map(p => p.rowOrder || '');
    const ns = peoples.indexOf('northSouth'), st = peoples.indexOf('start'), blank = peoples.indexOf(''), pick = peoples.lastIndexOf('');
    await page.evaluate(() => __maker.openBase('peoples', -1, true));
    await page.waitForSelector('#mkBaseBody select[name="rowOrder"]');
    const sel = await page.$$eval('#mkBaseBody tr[data-i] select[name="rowOrder"]', els => els.map(e => [e.value, [...e.options].map(o => o.textContent).join('/')]));
    check(sel.length === peoples.length && sel[ns][0] === 'northSouth' && sel[st][0] === 'start' && sel[blank][0] === '' && /상위 민족 따름\/시작 연도\/북 → 남/.test(sel[blank][1]), "민족 표의 '배열 기준' 칸(상위 민족 따름 · 시작 연도 · 북 → 남)", sel);
    await page.selectOption(`#mkBaseBody tr[data-i="${pick}"] select[name="rowOrder"]`, 'start');
    await page.waitForTimeout(500);
    check(await page.evaluate(i => __maker.draft.peoples[i].rowOrder === 'start', pick), '고르면 작업본의 민족 rowOrder로');
    await page.screenshot({ path: path.join(output, '메이커-민족-배열-기준-1920-1배.png') });
    await page.keyboard.press('Escape');
    /* 가운데 표에서도 배열 기준은 직접 고르는 칸이다. */
    await page.evaluate(() => __maker.openBase('peoples'));
    await page.waitForSelector('[data-grid-cell]');
    const orderColumn = await page.evaluate(() => [...document.querySelectorAll('.mk-grid [role="columnheader"]')].findIndex(e => e.textContent.includes('배열 기준')));
    check(orderColumn >= 0, "가운데 '표' 탭에 배열 기준 열이 있음", orderColumn);
    await page.locator(`[data-grid-cell="${ns}:${orderColumn}"]`).dblclick();
    const gridOrder = page.locator('select[data-grid-editor][aria-label="배열 기준"]');
    await gridOrder.waitFor();
    check(await gridOrder.inputValue() === 'northSouth', '가운데 표의 배열 기준 칸은 현재 값을 가진 고르기 칸');
    await page.screenshot({ path: path.join(output, '메이커-표-배열-기준-1920-1배.png') });
    await gridOrder.selectOption('start');
    await gridOrder.press('Enter');
    await page.waitForTimeout(500);
    check(await page.evaluate(i => __maker.draft.peoples[i].rowOrder === 'start', ns), '가운데 표에서 고른 배열 기준을 작업본에 저장');
    await page.evaluate(() => __maker.openBase('peoples'));
    await page.locator(`[data-grid-cell="${ns}:${orderColumn}"]`).dblclick();
    await page.locator('select[data-grid-editor][aria-label="배열 기준"]').selectOption('northSouth');
    await page.locator('select[data-grid-editor][aria-label="배열 기준"]').press('Enter');
    await page.locator('[data-ctab="timeline"]').click();
    /* 시대 편집 창의 남북 위치 (갈대 공국 — 430 ~ 602 · 남북 위치 40.3) */
    const reed = sample.periods.find(p => p.id === 'p-reed');
    await page.evaluate(() => { __tl.setView(80, 620); __tl.bodyEl.scrollTop = 0; });
    await settle(page);
    await page.click(`#timeline .tl-band[data-uid="${P}${reed.id}"]`);
    await page.waitForSelector('#editorForm input[name="northSouth"]', { state: 'attached' });
    // 안 쓴 블록은 칩으로 접힌다(D3). 실제 칩으로 열어 남북 위치 칸까지 닿는지 본다.
    const northBlock = await page.locator('#editorForm input[name="northSouth"]').evaluate(el => el.closest('[data-blk]')?.dataset.blk || '');
    if (northBlock && await page.locator(`#editorForm [data-blk-chip="${northBlock}"]`).isVisible()) {
      await page.locator(`#editorForm [data-blk-chip="${northBlock}"]`).click();
    }
    await page.waitForSelector('#editorForm input[name="northSouth"]');
    const nsBox = await page.evaluate(() => { const i = document.querySelector('#editorForm input[name="northSouth"]'); return { v: i.value, ph: i.hasAttribute('placeholder'), open: i.closest('details').open }; });
    check(nsBox.v === String(reed.northSouth) && !nsBox.ph && nsBox.open, "시대 편집 창의 '남북 위치' 칸(적은 값 · 회색 예시 글 없음 · 그 구역이 열림)", nsBox);
    await page.screenshot({ path: path.join(output, '메이커-남북-위치-블록-1920-1배.png') });
    /* 팩 정보의 간지 설정 */
    await page.evaluate(() => __maker.openInfo());
    await page.waitForSelector('[name="yearCycleMode"]');
    const info = await page.evaluate(() => ({ mode: document.querySelector('[name="yearCycleMode"]').value, names: document.querySelector('[name="yearCycleNames"]').value, start: document.querySelector('[name="yearCycleStart"]').value, label: document.querySelector('[name="yearCycleLabel"]').value, ph: [...document.querySelectorAll('[name^="yearCycle"]')].some(e => e.hasAttribute('placeholder')) }));
    check(info.mode === 'custom' && info.names.startsWith(`${CYCLE.names[0]}, ${CYCLE.names[1]}`) && info.start === String(CYCLE.start) && info.label === CYCLE.label && !info.ph, "팩 정보의 '날짜 칸의 간지 설정'(다른 순환 — 명칭 목록 · 기준 연도 · 줄 제목 · 회색 예시 글 없음)", info);
    await page.screenshot({ path: path.join(output, '메이커-팩-정보-간지-설정-1920-1배.png') });
    await page.selectOption('[name="yearCycleMode"]', 'off');
    await page.waitForTimeout(600);
    const off = await page.evaluate(() => ({ v: __maker.draft.yearCycle, hidden: [...document.querySelectorAll('[data-cycle-custom]')].every(e => e.hidden) }));
    check(off.v === false && off.hidden, "'기본으로 끔'을 고르면 작업본 yearCycle: false · 이름 칸이 숨음", off);
    await page.context().close();
  }
  check(!report.오류.length, '페이지 오류 0', report.오류);
} finally {
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
  await browser.close();
  server.close();
}
console.log(`띠 배치의 기준점 · 시대 접기 · 간지 설정 검사 ${report.검사.length}항목 통과 · 페이지 오류 ${report.오류.length}`);
