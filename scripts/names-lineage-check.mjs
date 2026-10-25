/* 형식 버전 3(F1 — 이름 목록 · 지명 · 사람 잇기 · 자리 이음 · 혈연)의 실제 브라우저 검사. 자료는 견본 하나(samples/sample-lantern.json — 등불 연대기).
   ① 연표(index.html): 견본을 설치해 상세 창의 글 — 머리 이름 아래 원어 · 로마자 줄과 '다른 이름' 칸(등불 왕국),
      지도자 칸 창의 '앞 지도자 ○○의 ○○ · ○○'과 부모(적관왕), 다시 오른 지도자(설원 제국 두갈래 황제 — 한 사람의 창 '자리 N' · 건의 8의 6-가),
      두 나라를 다스린 같은 사람(쌍등왕 — 하연 부흥국 · 적석 왕국(재건)), 자리 이음 '미상'(휘내 돌지기),
      인물 창의 부모 · 조상(미상 · 몇 대 조상 · 전승) · 배우자 · 사람으로 이어진 지도자 칸, 도읍 · 사건 상세의 지명 원어 — 와 검색(원어 · 로마자로 찾기)
   ② 메이커(dlc-maker.html): 견본을 작업본으로 열어 편집 창의 폼 왕복(채우기 → 읽기 → 정규화가 원래 항목과 같음 — 형식에 있는 칸 = 폼에 있는 칸),
      지도자 줄의 [사람] 상자 펼치기 · 이름 줄 더하기가 폼 값에 들어가는지, 바탕 자료 창의 성씨 · 지명 표와 文 상자 · 지명 id와 이름을 바꾸면 따라가는 곳
   node scripts/names-lineage-check.mjs <검사할 폴더> <결과 폴더>
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)에 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/이름-계보-검사');
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
      const text = bytes.toString('utf8'), marker = '/* ---------- 팩 & 모델 ---------- */';
      assert.equal(text.split(marker).length, 2);
      bytes = Buffer.from(text.replace(marker, 'window.__state=state;window.__openDetail=(...a)=>openDetail(...a);window.__openEditor=(...a)=>openEditor(...a);Object.defineProperty(window,\'__maker\',{get:()=>maker});\n' + marker));
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = 'http://127.0.0.1:' + server.address().port;
const lantern = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const P = `${lantern.id}/`; // 견본 항목 uid의 머리 (lantern-chronicle/)
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
try {
  /* ① 연표 */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(list => { try { localStorage.setItem('ht.packs.installed', JSON.stringify(list)); } catch (e) { /* 저장 못 함 */ } }, [lantern]);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + '/index.html');
    await page.waitForFunction(uid => window.__state && window.__state.model && window.__state.model.byUid.has(uid), P + 'p-lantern');
    const text = async (uid, opts) => page.evaluate(([u, o]) => { window.__openDetail(u, o || {}); const el = document.querySelector('#detail'); return { text: el.innerText, html: el.innerHTML }; }, [uid, opts || null]);
    const head = await text(P + 'p-lantern');
    /* 머리 꼴은 감독 결정 D2-1 A(2026-10-12 — 갈래 D2): 이름 아래 원어 · 로마자 두 줄 · 언어 · 종류 딱지 없음 · 나머지는 '다른 이름 n개' 칸 (자세한 검사는 scripts/names-display-check.mjs) */
    check(/燈火王國\n+Kingdom of Lanterns/.test(head.text) && !/\(로마자|\(원어/.test(head.text), '나라 상세: 머리 이름 아래 원어 · 로마자 두 줄(언어 · 종류 딱지 없음)', head.text.split('\n').slice(0, 12));
    /* '다른 이름' 칸의 한 줄: 이름 · 메모 · 기간 (메모와 기간의 차례 · 줄바꿈은 꼴에 따라 다를 수 있어 둘 다 받음) */
    check(/다른 이름 2(?!\d|개)/.test(head.text) && /옛 이름\s*휘국\s*(?:건국 초 금석문의 국호\s*1년 ~ 120년|1년 ~ 120년\s*·?\s*건국 초 금석문의 국호)/.test(head.text), "나라 상세: 옛 이름(국호 변천 — 휘국)이 '다른 이름' 칸에 기간과 함께", head.text.split('\n').slice(0, 20));
    const cap = await text(P + 'p-lantern', { cell: 'capital:1' });
    check(/지명 호반성[^\n]*큰 강 유역에 속함[^\n]*湖畔城/.test(cap.text), '도읍 칸 창: 지명 사전에 있는 도읍(호반성)이 지명 이름 · 위 구역 · 원어로', cap.text.split('\n').slice(0, 10));
    const ev = await text(P + 'e-first-light');
    check(/장소 휘성[^\n]*輝城/.test(ev.text) && /初燈/.test(ev.text), '사건 상세: 장소의 원어와 제목의 다른 이름', ev.text.split('\n').slice(0, 10));
    const c2 = await text(P + 'p-lantern', { cell: 'leader:7' });
    check(/앞 지도자 세등왕의 동생 · 세습/.test(c2.text), "지도자 칸 창: '앞 지도자 ○○의 ○○ · ○○'", c2.text.split('\n').slice(0, 14));
    check(/부모 · 조상: 부 호반왕/.test(c2.text), '지도자 칸 창: 부모');
    const c3 = await text(P + 'p-empire', { cell: 'leader:8' });
    check(/자리 2/.test(c3.text) && !/같은 사람의 다른 칸/.test(c3.text) && /앞 겨울매 황제의 사촌 · 복위/.test(c3.text), "다시 오른 지도자: 한 사람의 창 '자리 2' · 지금 자리 줄의 '앞 ○○의 사촌 · 복위' (건의 8의 6-가)", c3.text.split('\n').slice(0, 22));
    const c5 = await text(P + 'p-mist-league', { cell: 'leader:2' });
    check(/앞 지도자 흰내 돌지기 · 관계 미상 · 오른 방식 미상/.test(c5.text), '자리 이음 "미상": 관계 · 방식 미상(비움과 다르게)', c5.text.split('\n').slice(0, 12));
    const two = await text(P + 'p-jeokseok2', { cell: 'leader:7' });
    check(/자리 2/.test(two.text) && /하연 부흥국/.test(two.text) && /적석 왕국\(재건\)/.test(two.text) && /석양왕의 외손 · 세습/.test(two.text), "두 나라를 다스린 같은 사람: 한 사람의 창 '자리' 상자에 두 나라 · 외손 · 세습", two.text.split('\n').slice(0, 22));
    const lines = t => t.split('\n').filter(l => /부모|배우자|자식|다스린|같은 이름의 지도자/.test(l));
    const fig = await text(P + 'f-on-saebyeok');
    check(/부모 · 조상: 24대 조상 온 시헌 전승/.test(fig.text), '인물 창: 부모 · 조상(몇 대 조상 · 전승)', lines(fig.text));
    const nam = await text(P + 'f-namgang');
    check(/부모 · 조상: 모 휘 은하 · 부 미상/.test(nam.text), '인물 창: 부모 · 조상(어머니 · 아버지 미상)', lines(nam.text));
    const sup = await text(P + 'f-supgyeol');
    check(/부모 · 조상: 부 등불 왕국 적관왕/.test(sup.text) && /배우자: 설족 칸국 흰갈기 칸/.test(sup.text), '인물 창: 다른 나라 지도자 칸인 부모 · 배우자', lines(sup.text));
    check(/다스린 칸|같은 이름의 지도자/.test(fig.text), '인물 창: 사람으로 이어진 지도자 칸', lines(fig.text));
    /* 검색: 원어 · 로마자로 */
    const found = async q => page.evaluate(async q2 => {
      const input = document.querySelector('#searchInput');
      input.focus();
      input.value = q2;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      await new Promise(r => setTimeout(r, 50));
      return document.querySelector('#searchResults') ? document.querySelector('#searchResults').innerText : '';
    }, q);
    check(/등불 왕국/.test(await found('Lanterns')), '검색: 나라의 로마자로 찾음');
    check(/서린/.test(await found('Seorin')), '검색: 인물의 로마자로 인물을 찾음');
    check(/하윤 여왕/.test(await found('Hayun')), '검색: 지도자 칸의 로마자로 찾음');
    check(/호반성/.test(await found('湖畔城')), '검색: 도읍 지명의 원어로 찾음');
    await page.screenshot({ path: path.join(output, '연표-상세.png') });
    await context.close();
  }
  /* ② 메이커 */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(raw => { try { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); } catch (e) { /* 저장 못 함 */ } }, lantern);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + '/dlc-maker.html');
    await page.waitForFunction(uid => window.__state && window.__state.model && window.__state.model.byUid.has(uid), P + 'p-lantern');
    /* 폼 왕복: 편집 창에 채우고 읽은 항목을 정규화한 것이 원래 항목(정규화한 작업본의 그 항목)과 같아야 함 —
       나라는 혈연 칸이 많은 셋(등불 왕국: 부모 · 배우자 미상 · 다른 나라에서 온 자리 이음 · 이설 / 설원 제국: 복위 · 칭제 / 적석 왕국(재건): 두 나라의 같은 사람 · 외손),
       인물은 셋(온새벽: 24대 조상 · 전승 / 휘 남강군: 아버지 미상 · 군호 / 휘 숲결: 다른 나라 지도자 칸인 부모 · 배우자) */
    const round = await page.evaluate(async P => {
      const sortKeys = v => (Array.isArray(v) ? v.map(sortKeys) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sortKeys(v[k])])) : v);
      const canon = v => JSON.stringify(sortKeys(v));
      const raw = JSON.parse(localStorage.getItem('ht.maker.draft'));
      const head = { format: raw.format, formatVersion: 3, id: raw.id, name: raw.name, tracks: raw.tracks, houses: raw.houses };
      const norm = (list, x) => HT.normalizePack(Object.assign({}, head, { [list]: [x] })).pack[list][0];
      const out = [];
      const items = [['p-lantern', 'period', 'periods'], ['p-empire', 'period', 'periods'], ['p-jeokseok2', 'period', 'periods'], ['f-on-saebyeok', 'figure', 'figures'], ['f-namgang', 'figure', 'figures'], ['f-supgyeol', 'figure', 'figures']].map(([id, kind, list]) => [P + id, kind, list]);
      for (const [uid, kind, list] of items) {
        const item = window.__state.model.byUid.get(uid);
        window.__openEditor(item, kind);
        await new Promise(r => setTimeout(r, 30));
        const r = HT.FORMS[kind].read(document.querySelector('#editorForm'));
        const before = norm(list, raw[list].find(x => `${raw.id}/${x.id}` === uid));
        const d = HT.draft.clean(raw); // 메이커가 저장하는 길 그대로(제 항목 고치기 — 비운 칸 · 통설 확실성은 지움)
        HT.draft.updateOwn(d, item.id, JSON.parse(JSON.stringify(r.item)), item);
        const after = norm(list, d[list].find(x => x.id === item.id));
        out.push({ uid, problems: r.problems, same: canon(before) === canon(after), before: canon(before).slice(0, 4000), after: canon(after).slice(0, 4000) });
      }
      return out;
    }, P);
    for (const r of round) check(!r.problems.length && r.same, `메이커 폼 왕복(${r.uid}): 채우고 읽어도 자료가 같음`, r.same && !r.problems.length ? undefined : r);
    /* 지도자 줄의 [사람] 상자: 펼치기 · 이름 줄 더하기가 폼 값에 들어감 (등불 왕국 둘째 지도자 휘명왕 — 자리 이음 아들 · 세습 · 부모 하나) */
    const box = await page.evaluate(async uid => {
      window.__openEditor(window.__state.model.byUid.get(uid), 'period');
      await new Promise(r => setTimeout(r, 30));
      const form = document.querySelector('#editorForm');
      const row = form.querySelectorAll('[data-cells="leaders"] .cell-row')[1];
      const btn = row.querySelector('[data-cx-toggle]');
      const label = btn.textContent;
      btn.click();
      const xbox = [...row.children].find(el => el.classList.contains('cell-xbox'));
      const opened = !xbox.hidden;
      const kin = xbox.querySelector('.x-kin').value;
      xbox.querySelector('.names-box [data-name-add]').click();
      const added = xbox.querySelector('.names-box [data-names-rows]').lastElementChild;
      added.querySelector('.x-text').value = '輝明王';
      added.querySelector('.x-lang').value = 'x-hayeon-Hani';
      added.querySelector('.x-kind').value = '원어';
      added.querySelector('.x-text').dispatchEvent(new Event('input', { bubbles: true }));
      const read = HT.FORMS.period.read(form).item.leaders[1];
      return { label, opened, kin, after: btn.textContent, name: read.name, names: read.names, accession: read.accession, parents: read.parents };
    }, P + 'p-lantern');
    check(box.label === '사람 2' && box.opened && box.kin === '아들', '지도자 줄 [사람] 단추: 적힌 수(자리 이음 · 부모 하나) · 펼치면 관계 칸에 한국어 낱말', box);
    check(box.name === '휘명왕' && box.after === '사람 3' && box.names && box.names[0].text === '輝明王' && box.names[0].kind === 'native' && box.accession.kin === 'son' && box.parents.length === 1, '사람 상자에 더한 이름 줄이 폼 값(이름 목록)에 들어가고 단추 글이 따라감', box);
    await page.screenshot({ path: path.join(output, '메이커-사람-상자.png') });
    await context.close();
  }
  /* ③ 메이커 바탕 자료 창: 성씨 · 지명 표 — 文 상자의 이름 줄 고치기가 작업본에 들어가고, 지명 id를 바꾸면 그 id로 적은 곳(위 구역 · 문서)이,
     이름을 바꾸면 그 이름으로 적은 도읍 · 사건 장소가 따라감 (견본의 도읍 · 사건 장소는 지명 이름으로 적혀 있음) */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(raw => { try { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); } catch (e) { /* 저장 못 함 */ } }, lantern);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + '/dlc-maker.html');
    await page.waitForFunction(uid => window.__state && window.__state.model && window.__state.model.byUid.has(uid), P + 'p-lantern');
    const want = { places: lantern.places.length, hoban: lantern.places.findIndex(x => x.id === 'pl-hoban'), hayeon: lantern.places.findIndex(x => x.id === 'pl-hayeon'), kids: lantern.places.filter(x => x.parent === 'pl-hayeon').length };
    const tabs = await page.evaluate(async want => {
      const wait = ms => new Promise(r => setTimeout(r, ms));
      const draft = () => JSON.parse(localStorage.getItem('ht.maker.draft'));
      window.__maker.openBase('places');
      await wait(50);
      const body = document.querySelector('#mkBaseBody');
      const row = i => body.querySelector(`tr[data-i="${i}"]`);
      const tabs = [...document.querySelectorAll('#mkBaseTabs [data-base-tab]')].map(b => b.dataset.baseTab);
      const rows = body.querySelectorAll('tbody tr[data-i]').length;
      const btn = row(want.hoban).querySelector('[data-act="names"]');
      const label = btn.textContent;
      btn.click();
      await wait(30);
      const sub = body.querySelector(`[data-base-names="${want.hoban}"]`);
      const nrows = sub.querySelectorAll('.name-row').length;
      const first = sub.querySelector('.name-row .x-text');
      first.value = '湖畔大城';
      first.dispatchEvent(new Event('input', { bubbles: true }));
      await wait(400);
      const text = draft().places.find(x => x.id === 'pl-hoban').names[0].text;
      /* id 바꾸기 → 그 id로 적은 문서(place:pl-hoban)가 따라감 */
      const setCell = async (i, name, value) => {
        const input = row(i).querySelector(`input[name="${name}"]`);
        input.value = value;
        input.dispatchEvent(new Event('change', { bubbles: true }));
        await wait(400);
      };
      await setCell(want.hoban, 'id', 'pl-lakeside');
      const d1 = draft();
      /* 큰 강 유역(pl-hayeon)의 id 바꾸기 → 그 id로 적은 아래 지명들의 위 구역이 따라감 */
      await setCell(want.hayeon, 'id', 'pl-bigriver');
      const d2 = draft();
      /* 이름 바꾸기 → 그 이름(호반성)으로 적은 도읍 · 사건 장소가 따라감 */
      await setCell(want.hoban, 'name', '호숫가 성');
      const d3 = draft();
      const caps = d => d.periods.flatMap(p => (p.capitals || []).map(c => c.city));
      const places = d => d.events.map(e => e.place).filter(Boolean);
      return {
        tabs, rows, label, nrows, text,
        doc: { old: 'place:pl-hoban' in d1.documents, now: 'place:pl-lakeside' in d1.documents },
        kids: { old: d2.places.filter(x => x.parent === 'pl-hayeon').length, now: d2.places.filter(x => x.parent === 'pl-bigriver').length },
        caps: { before: caps(d2).filter(c => c === '호반성').length, old: caps(d3).filter(c => c === '호반성').length, now: caps(d3).filter(c => c === '호숫가 성').length },
        evs: { before: places(d2).filter(c => c === '호반성').length, old: places(d3).filter(c => c === '호반성').length, now: places(d3).filter(c => c === '호숫가 성').length },
      };
    }, want);
    check(tabs.tabs.includes('surnames') && tabs.tabs.includes('places') && tabs.rows === want.places && tabs.label === '文3' && tabs.nrows === 3, '바탕 자료 창: 성씨 · 지명 표와 줄 끝 文 상자(호반성 — 이름 줄 3)', tabs);
    check(tabs.text === '湖畔大城', '文 상자의 이름 줄을 고치면 작업본의 이름 목록에 들어감', tabs);
    check(!tabs.doc.old && tabs.doc.now, '지명 id를 바꾸면 그 id로 적은 문서가 따라감', tabs.doc);
    check(tabs.kids.old === 0 && tabs.kids.now === want.kids && want.kids > 0, '지명 id를 바꾸면 그 id로 적은 아래 지명의 위 구역이 따라감', tabs.kids);
    check(tabs.caps.before > 0 && tabs.caps.old === 0 && tabs.caps.now === tabs.caps.before && tabs.evs.before > 0 && tabs.evs.old === 0 && tabs.evs.now === tabs.evs.before, '지명 이름을 바꾸면 그 이름으로 적은 도읍 · 사건 장소가 따라감', { caps: tabs.caps, evs: tabs.evs });
    await page.screenshot({ path: path.join(output, '메이커-지명-표.png') });
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
