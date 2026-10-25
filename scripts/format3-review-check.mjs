/* 형식 3 통합 검토에서 확인된 지적의 고침을 실제 브라우저에서 검사합니다 (노드에서 볼 수 있는 것은 dev-smoke [68]).
   ① 연표(보기 전용): 검사 안에서 지은 가상 팩 하나(RV)를 설치한 채로 열어 —
      소속이 돌고 도는 나라 셋(가 → 다 → 나 → 가)이 있어도 연표가 멈추지 않고 그려짐,
      지도자 칸 창의 자리 이음 글(무관 → '혈연 없음' · 본인 → '같은 사람' · 첫 지도자 → '관계 아들'), 같은 사람의 다른 칸에 칸 종류(지도자 · 내각) —
      다른 자리가 있는 사람은 한 사람의 창(건의 8의 6-가)이라 자리 이음은 '자리' 상자의 지금 자리 줄(앞 ○○ …), 다른 칸은 자리 줄(칸 종류와 함께).
      (단체 창 '구성 나라' 줄의 꼴 검사는 그 줄을 가진 단체(members)가 견본에 없어 뺐습니다 — 견본 등불 연대기의 단체는 붕당 · 파벌뿐)
   ② 메이커: 소속이 돌고 도는 작업본도 열림, 집권 칸에 이름 목록을 적은 단체(제 것 · 남의 것)를 열어서 그대로 저장해도 그대로 · 덮어쓰기 0,
      바탕 자료 › 지명의 文 상자에서 읽지 못한 이름 줄이 알림 없이 사라지지 않음 — 견본 samples/sample-lantern.json(등불 연대기)을 작업본으로 열어 첫 지명(큰 강 유역)에서
      (줄에 붉은 테 · 까닭 글 · 다른 탭에 갔다 와도 친 글이 남음 · 고치면 그때 작업본에 들어감).
   node scripts/format3-review-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge)
   자료는 가상 나라 · 가상 사람만(가상 팩과 견본), 따로 띄운 브라우저의 메모리에만 둡니다. 1920×1080 · 1배 화면 그림을 결과 폴더에 남깁니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/형식3-검토-검사');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(fs.readFileSync(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100% · 1배', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
const lantern = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
/* 가상 팩: 자리 이음 글 · 같은 사람의 다른 칸(하늘 나라) · 돌고 도는 소속(가 · 나 · 다 나라 — 같은 트랙, 상위 띠 아래에 접히는 소속 하나씩) */
const RV = {
  format: 'history-timeline-dlc', formatVersion: 3, version: '1.0.0', id: 'rv-check', name: '검토 검사',
  tracks: [{ id: 'rv-sky', name: '하늘 들' }, { id: 'rv-ring', name: '고리 들' }],
  periods: [
    {
      id: 'rv-sky-k', track: 'rv-sky', name: '하늘 나라', start: 500, end: 600,
      leaders: [
        { name: '구름', start: 500, end: 510, accession: { kin: '아들', how: '세습' } },
        { name: '비', start: 510, end: 520, accession: { kin: '무관', how: '추대' } },
        { name: '바람', start: 520, end: 530, person: '하늘 나라:비@510', accession: { kin: '본인', how: '복위', from: '하늘 나라:비@510' } },
        { name: '눈', start: 530, end: 600 },
      ],
      cabinets: [{ name: '비의 회의', start: 512, end: 518, person: '하늘 나라:비@510' }],
    },
    { id: 'rv-ga', track: 'rv-ring', name: '가 나라', start: 100, end: 300, partOf: '다 나라' },
    { id: 'rv-na', track: 'rv-ring', name: '나 나라', start: 100, end: 300, partOf: '가 나라' },
    { id: 'rv-da', track: 'rv-ring', name: '다 나라', start: 100, end: 300, partOf: '나 나라' },
  ],
};
try {
  /* ① 연표 */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(packs => { try { localStorage.setItem('ht.packs.installed', JSON.stringify(packs)); } catch (e) { /* 저장 못 함 */ } }, [RV]);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    const t0 = Date.now();
    await page.goto(base + 'index.html', { timeout: 30000 });
    await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.byUid.has('rv-check/rv-ga'), null, { timeout: 30000 });
    /* 돌고 도는 소속: 고리 들 트랙으로 가서 한 번 더 그려도 응답함 (예전에는 _host를 따라가는 while이 끝없이 돌았음) */
    const ring = await Promise.race([
      page.evaluate(async () => {
        const m = HT.viewer.state.model;
        HT.viewer.timeline.focusOn(m.byUid.get('rv-check/rv-ga'));
        await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
        return { ok: true, bands: document.querySelectorAll('#timeline .tl-band').length };
      }),
      new Promise(r => setTimeout(() => r({ ok: false }), 15000)),
    ]);
    check(ring.ok && ring.bands > 0, '연표: 소속이 돌고 도는 나라 셋이 있어도 멈추지 않고 그림', Object.assign({ ms: Date.now() - t0 }, ring));
    /* 자리 이음 글 · 같은 사람의 다른 칸 */
    const kin = await page.evaluate(() => {
      const line = i => {
        HT.viewer.openDetail('rv-check/rv-sky-k', { cell: `leader:${i}` });
        /* 다른 자리가 없는 칸은 예전 줄(.lineage-line), 있는 칸은 한 사람의 창의 지금 자리 줄(.seat-list .is-here .seat-acc — 건의 8의 6-가) */
        const el = document.querySelector('#detail .lineage-line') || document.querySelector('#detail .seat-list > li.is-here .seat-acc');
        const seats = [...document.querySelectorAll('#detail .seat-list > li')].map(li => li.innerText.replace(/\s+/g, ' ').trim());
        return { line: el ? el.textContent.trim() : '', seats, old: /같은 사람의 다른 칸/.test(document.querySelector('#detail').innerText) };
      };
      return [0, 1, 2].map(line);
    });
    check(kin[0].line === '관계 아들 · 세습' && !kin[0].seats.length, "첫 지도자(앞 칸 없음 · 다른 자리 없음): '관계 아들 · 세습' — 예전 창 그대로", kin[0]);
    check(kin[1].line === '앞 구름 · 혈연 없음 · 추대' && !/의 무관/.test(kin[1].line), "무관: '앞 ○○의 무관'이 아니라 '앞 ○○ · 혈연 없음' (한 사람 창의 자리 줄 — 첫 줄에 '지도자')", kin[1]);
    check(kin[2].line === '앞 비 · 같은 사람 · 복위' && !/의 본인/.test(kin[2].line), "본인: '앞 ○○ · 같은 사람'", kin[2]);
    check(kin[2].seats.length === 3 && kin[2].seats.some(s => /^하늘 나라 지도자 · 2대 510 ~ 520/.test(s)) && kin[2].seats.some(s => /^하늘 나라 내각 · 비의 회의 512 ~ 518/.test(s)) && !kin[2].old, "같은 사람의 다른 칸: '자리' 상자에 같은 나라의 지도자 칸 · 내각 칸이 칸 종류와 함께(옛 '같은 사람의 다른 칸' 줄 없음)", kin[2]);
    await context.close();
  }
  /* ② 메이커 — 돌고 도는 소속의 작업본 · 지명 文 상자의 읽지 못한 줄 */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(raw => { try { if (!sessionStorage.getItem('rv-seeded')) { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); sessionStorage.setItem('rv-seeded', '1'); } } catch (e) { /* 저장 못 함 */ } }, RV);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + 'dlc-maker.html', { timeout: 30000 });
    await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.byUid.has('rv-check/rv-ga'), null, { timeout: 30000 });
    const alive = await Promise.race([page.evaluate(() => 1 + 1), new Promise(r => setTimeout(() => r(0), 15000))]);
    check(alive === 2, '메이커: 소속이 돌고 도는 작업본도 열려 응답함');
    await context.close();
  }
  /* 집권 칸에 이름 목록을 적은 단체(손으로 쓴 파일): 제 단체 · 남의 단체 모두 열어서 그대로 저장하면 내보낼 것이 그대로 · 덮어쓰기(패치) 0 */
  {
    const group = (id, track) => ({ id, name: `${id} 무리`, track, start: 420, end: 470, within: '집 나라', power: [{ name: '집권', start: 430, end: 460, names: [{ text: 'Jipgwon', kind: '로마자' }] }] });
    const near = { format: 'history-timeline-dlc', formatVersion: 3, version: '1.0.0', id: 'rv-near', name: '가상 이웃', tracks: [{ id: 'rv-n', name: '이웃 들' }], periods: [{ id: 'jip', track: 'rv-n', name: '집 나라', start: 400, end: 500 }], groups: [group('ng', 'rv-n')] };
    const own = { format: 'history-timeline-dlc', formatVersion: 3, version: '1.0.0', id: 'rv-own', name: '가상 내 팩', tracks: [{ id: 'rv-n', name: '이웃 들' }], groups: [group('og', 'rv-n')] };
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(({ near, own }) => {
      try {
        if (sessionStorage.getItem('rv-seeded')) return;
        localStorage.setItem('ht.packs.installed', JSON.stringify([near]));
        localStorage.setItem('ht.maker.draft', JSON.stringify(own));
        localStorage.setItem('ht.maker.refs', JSON.stringify({ [own.id]: [{ id: near.id, show: true, locked: false }] }));
        sessionStorage.setItem('rv-seeded', '1');
      } catch (e) {
        /* 저장 못 함 */
      }
    }, { near, own });
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + 'dlc-maker.html');
    await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.byUid.has('rv-near/ng') && HT.viewer.state.model.byUid.has('rv-own/og'));
    const kept = await page.evaluate(() => {
      const sortKeys = v => (Array.isArray(v) ? v.map(sortKeys) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sortKeys(v[k])])) : v);
      const out = () => JSON.stringify(sortKeys(HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(HT.viewer.maker.draft))).pack).groups));
      const before = out();
      for (const uid of ['rv-own/og', 'rv-near/ng']) {
        HT.viewer.openEditor(uid);
        HT.viewer.saveEditor();
      }
      return { same: out() === before, patches: (HT.viewer.maker.draft.patches || []).length, before };
    });
    check(kept.same && kept.patches === 0, '집권 칸에 이름 목록을 적은 단체: 제 단체 · 남의 단체 모두 열어서 그대로 저장하면 내보낼 것이 그대로 · 덮어쓰기 0', kept);
    await context.close();
  }
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(raw => { try { if (!sessionStorage.getItem('rv-seeded')) { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); sessionStorage.setItem('rv-seeded', '1'); } } catch (e) { /* 저장 못 함 */ } }, lantern);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + 'dlc-maker.html');
    await page.waitForFunction(uid => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.byUid.has(uid), `${lantern.id}/p-lantern`);
    await page.evaluate(() => HT.viewer.maker.openBase('places'));
    const row0 = '#mkBaseBody tr[data-i="0"]';
    await page.click(`${row0} [data-act="names"]`);
    const box = '#mkBaseBody [data-base-names="0"]';
    const before = await page.evaluate(b => document.querySelectorAll(`${b} .name-row`).length, box);
    await page.click(`${box} [data-name-add]`);
    const last = `${box} .name-row:last-child`;
    await page.fill(`${last} .x-text`, 'Hayeon Old');
    await page.fill(`${last} .x-start`, '삼백');
    await page.fill(`${last} .x-note`, '옛 이름');
    await page.keyboard.press('Tab');
    await page.waitForTimeout(450);
    const bad = await page.evaluate(([b, n]) => {
      const draft = JSON.parse(localStorage.getItem('ht.maker.draft'));
      const rows = [...document.querySelectorAll(`${b} .name-row`)];
      const note = document.querySelector(`${b} .mk-names-problem`);
      return { saved: (draft.places[0].names || []).length, rows: rows.length, invalid: rows.map(r => r.querySelector('.x-text').getAttribute('aria-invalid')), note: note ? note.textContent : '', before: n };
    }, [box, before]);
    check(bad.saved === before && bad.rows === before + 1 && bad.invalid[before] === 'true' && bad.note.includes(`이름 ${before + 1}번째 줄: 쓴 기간이 올바르지 않습니다`) && /저장되지 않았습니다/.test(bad.note), '文 상자: 읽지 못한 줄은 작업본에 들어가지 않고, 그 줄에 붉은 테와 까닭 글', bad);
    await page.screenshot({ path: path.join(output, '메이커-이름-상자-읽지-못한-줄.png') });
    /* 다른 탭(성씨)에 갔다 와도 친 글이 남음 */
    await page.click('#mkBaseTabs [data-base-tab="surnames"]');
    await page.click('#mkBaseTabs [data-base-tab="places"]');
    const back = await page.evaluate(b => {
      const rows = [...document.querySelectorAll(`${b} .name-row`)];
      const lastRow = rows[rows.length - 1];
      return { rows: rows.length, text: lastRow && lastRow.querySelector('.x-text').value, start: lastRow && lastRow.querySelector('.x-start').value, note: lastRow && lastRow.querySelector('.x-note').value, invalid: lastRow && lastRow.querySelector('.x-text').getAttribute('aria-invalid'), msg: !!document.querySelector(`${b} .mk-names-problem`) };
    }, box);
    check(back.rows === before + 1 && back.text === 'Hayeon Old' && back.start === '삼백' && back.note === '옛 이름' && back.invalid === 'true' && back.msg, '文 상자: 다른 탭에 갔다 와도 친 글 · 붉은 테 · 까닭 글이 남음', back);
    /* 고치면 그때 작업본에 들어가고 표시가 사라짐 */
    await page.fill(`${last} .x-start`, '300');
    await page.keyboard.press('Tab');
    await page.waitForTimeout(450);
    const fixed = await page.evaluate(b => {
      const draft = JSON.parse(localStorage.getItem('ht.maker.draft'));
      return { names: draft.places[0].names, msg: !!document.querySelector(`${b} .mk-names-problem`), invalid: [...document.querySelectorAll(`${b} .name-row .x-text[aria-invalid]`)].length };
    }, box);
    const added = (fixed.names || [])[before] || {};
    check(fixed.names.length === before + 1 && added.text === 'Hayeon Old' && added.start === 300 && added.note === '옛 이름' && !fixed.msg && !fixed.invalid, '文 상자: 고친 줄은 작업본에 들어가고 붉은 테 · 까닭 글이 사라짐', fixed);
    await context.close();
  }
} catch (e) {
  report.실패 = String(e && e.stack ? e.stack : e);
} finally {
  await browser.close();
  server.close();
  fs.writeFileSync(path.join(output, '검사-결과.json'), JSON.stringify(report, null, 2));
}
if (report.실패) {
  console.log(report.실패);
  console.log(`오류: ${JSON.stringify(report.오류)}`);
  process.exit(1);
}
console.log(`검사 ${report.검사.length} · 오류 ${JSON.stringify(report.오류)}`);
process.exit(report.오류.length ? 1 : 0);
