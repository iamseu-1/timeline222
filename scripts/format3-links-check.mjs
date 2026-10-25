/* 형식 3 세 갈래를 하나로 이은 곳(통합 — F1 이름 · 사람 · F2 단체 · 렌즈 · F3 판 · 지도)을 실제 브라우저에서 검사합니다.
   ① 연표(보기 전용): 가상 팩 하나를 설치한 채로 열어 —
      단체 창 머리의 원어 줄 · 구성원 칩(인물 → 인물 창 · 지도자 칸 "나라:지도자@해" → 그 칸 · 찾지 못한 이름은 누를 수 없는 칩),
      지도자 칸 창 · 인물 창의 '속한 단체', 제도 창의 원어 줄, 검색이 단체 · 제도 · 주제의 이름 목록으로도 찾음.
   ② 메이커: 새 DLC에 나라를 만들고 단체 폼에 이름 줄 · 구성원(지도자 칸 참조)을 넣어 저장 → 작업본의 꼴 · 열어서 그대로 저장해도 같음 ·
      지도자 칸 참조의 트랙이 폼을 지나도 남음, 구조 나무 '종류별'의 단체 · 제도 묶음과 성씨 · 지명 · 주제 바탕 줄.
   node scripts/format3-links-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge)
   자료는 따로 띄운 브라우저의 메모리에만 둡니다(가상 나라 · 가상 사람만). 1920×1080 · 1배 화면 그림을 결과 폴더에 남깁니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/형식3-잇기');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
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
// 정지 화면은 글꼴과 유한한 등장 효과가 끝난 뒤 찍는다. 무한 반복 효과는 그대로 둔다.
const settleCapture = page => page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all(document.getAnimations()
    .filter(a => Number.isFinite(a.effect?.getComputedTiming().endTime))
    .map(a => a.finished.catch(() => {})));
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
});
const report = { 화면: '1920×1080 · 100% · 1배', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };

/* 가상 팩: 나라 하나(지도자 둘) · 인물 하나 · 주제 사전 · 단체(구성원 = 인물 · 지도자 칸 · 글) · 제도 — 이름 목록은 가상 언어의 로마자 */
const F = 'history-timeline-dlc';
const PACK = {
  format: F, formatVersion: 3, id: 'links-check', name: '잇기 검사 팩', version: '1.0.0',
  tracks: [{ id: 'lk-field', name: '잇는 들' }],
  periods: [{ id: 'sol', track: 'lk-field', name: '솔나라', start: 500, end: 700, leaders: [{ name: '첫 왕', start: 500, end: 530 }, { name: '둘째 왕', start: 530, end: 700 }] }],
  figures: [{ id: 'garam', track: 'lk-field', name: '가람', birth: 480, death: 560 }],
  themes: [{ id: 'levy', name: '거둠 제도', names: [{ text: 'Levy Rule', kind: '로마자' }] }],
  groups: [{ id: 'band', name: '들바람 모임', type: '붕당', track: 'lk-field', start: 510, end: 650, within: '솔나라', people: ['가람', '솔나라:첫 왕@500', '그냥 이름'], names: [{ text: 'Wind Band', kind: '로마자' }] }],
  institutions: [{ id: 'share', theme: 'levy', polity: '솔나라', track: 'lk-field', spans: [['밭 나눔', 500]], names: [{ text: 'Field Share', kind: '로마자' }] }],
};
try {
  /* ① 연표 */
  const view = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  await view.addInitScript(packs => { if (!localStorage.getItem('ht.packs.installed')) localStorage.setItem('ht.packs.installed', JSON.stringify(packs)); }, [PACK]);
  const page = await view.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.setDefaultTimeout(20000);
  await page.goto(base + 'index.html');
  await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.byUid.has('links-check/band'));
  const group = await page.evaluate(() => {
    HT.viewer.openDetail('links-check/band');
    const d = document.querySelector('#detail');
    const sec = [...d.querySelectorAll('.sub-box')].find(s => /구성원/.test(s.querySelector('h3').textContent));
    const chips = [...sec.querySelectorAll('.chip')].map(c => ({ text: c.textContent.trim(), uid: c.dataset.uid || '', cellOf: c.dataset.cellOf || '', cell: c.dataset.cell || '', off: c.classList.contains('is-off') }));
    return { title: d.querySelector('h2').textContent, names: [...d.querySelectorAll('.names-orig, .names-roman, .names-line')].map(p => p.textContent), chips };
  });
  /* 머리 꼴은 감독 결정 D2-1 A(갈래 D2): 이름 아래 원어 · 로마자 두 줄 · 언어 · 종류 딱지 없음 */
  check(group.title === '들바람 모임' && group.names.some(t => t.includes('Wind Band')) && !group.names.some(t => t.includes('로마자')), '단체 창 머리 이름 아래에 원어 · 로마자 줄(이름 목록 — 시대 · 인물 창과 같은 꼴 · 딱지 없음)', group.names);
  const [cFig, cCell, cOff] = group.chips;
  check(group.chips.length === 3 && cFig.uid === 'links-check/garam' && !cFig.off, '구성원 칩: 인물로 적힌 사람은 인물 창으로', cFig);
  check(cCell && cCell.cellOf === 'links-check/sol' && cCell.cell === 'leader:0' && cCell.text.includes('첫 왕') && cCell.text.includes('솔나라'), '구성원 칩: 지도자 칸("나라:지도자@해")으로 적은 사람은 그 지도자 칸으로 (사람 잇기의 사람 자리)', cCell);
  check(cOff && cOff.off && cOff.text === '그냥 이름', '구성원 칩: 연표에서 찾지 못한 이름은 누를 수 없는 칩', cOff);
  await settleCapture(page);
  await page.screenshot({ path: path.join(output, '단체-창-구성원-1920-1배.png') });
  await page.locator('#detail .chip[data-cell-of="links-check/sol"]').click();
  await page.waitForTimeout(150);
  const cell = await page.evaluate(() => { const d = document.querySelector('#detail'); return { title: d.querySelector('h2').textContent, text: d.textContent, link: !!d.querySelector('.linky[data-uid="links-check/band"]') }; });
  check(/첫 왕/.test(cell.title + cell.text) && /속한 단체/.test(cell.text) && cell.link, '구성원 칩을 누르면 그 지도자 칸 창 — 칸 창에 \'속한 단체\'(누르면 단체 창)', { title: cell.title, link: cell.link });
  const fig = await page.evaluate(() => { HT.viewer.openDetail('links-check/garam'); const d = document.querySelector('#detail'); return { text: d.textContent, link: !!d.querySelector('.linky[data-uid="links-check/band"]') }; });
  check(/속한 단체/.test(fig.text) && fig.link, "인물 창에도 '속한 단체'", fig.link);
  const inst = await page.evaluate(() => { HT.viewer.openDetail('links-check/share'); const d = document.querySelector('#detail'); return [...d.querySelectorAll('.names-orig, .names-roman, .names-line')].map(p => p.textContent); });
  check(inst.some(t => t.includes('Field Share')), '제도 창에도 원어 줄', inst);
  const search = async q => {
    await page.locator('#searchInput').fill(q);
    await page.waitForTimeout(250);
    return page.evaluate(() => [...document.querySelectorAll('#searchResults button .sr-title')].map(b => b.textContent));
  };
  const s1 = await search('Wind Band');
  check(s1.some(t => t.startsWith('들바람 모임')), '검색: 단체의 이름 목록(원어)으로도 찾음', s1);
  const s2 = await search('Field Share');
  check(s2.some(t => t.includes('솔나라 · 거둠 제도')), '검색: 제도의 이름 목록으로도 찾음', s2);
  const s3 = await search('Levy Rule');
  check(s3.some(t => t.includes('솔나라 · 거둠 제도')), '검색: 제도의 주제(사전)의 이름 목록으로도 그 제도를 찾음', s3);
  await page.locator('#searchInput').fill('');
  await view.close();

  /* ② 메이커 */
  const makerContext = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const maker = await makerContext.newPage();
  maker.on('pageerror', e => report.오류.push(e.message));
  maker.setDefaultTimeout(20000);
  await maker.goto(base + 'dlc-maker.html');
  await maker.locator('[data-start-new]').waitFor();
  await maker.locator('[data-start-new] [name="name"]').fill('가상 잇기 확인');
  await maker.locator('[data-start-new] [name="id"]').fill('links-maker-check');
  await maker.locator('[data-start-new] [name="how"][value="world"]').check();
  await maker.locator('[data-start-new] button[type="submit"]').click();
  await maker.waitForFunction(() => window.HT && HT.viewer && HT.viewer.maker && HT.viewer.maker.draft && document.querySelector('#mkStart').hidden);
  const polityUid = await maker.evaluate(() => {
    HT.viewer.openEditor(null, 'period');
    const form = document.querySelector('#editorForm');
    HT.FORMS.period.fill(form, { name: '솔나라', track: form.elements.track.value, start: 500, end: 700, leaders: [{ name: '첫 왕', start: 500, end: 530 }, { name: '둘째 왕', start: 530, end: 700 }] });
    return HT.viewer.saveEditor();
  });
  check(!!polityUid, '작업본에 가상 나라(지도자 둘)를 만듦', polityUid);
  await maker.evaluate(() => HT.viewer.openEditor(null, 'group'));
  const box = await maker.evaluate(() => { const f = document.querySelector('#editorForm'); const d = f.querySelector('details[data-adv="names"]'); return { names: !!(d && d.querySelector('[data-names-field]')), hint: f.querySelector('[name="people"]').closest('label').textContent }; });
  check(box.names && /나라:지도자@시작 해/.test(box.hint), '단체 폼: 이름(원어 등) 접는 구역 · 구성원 칸의 안내에 지도자 칸 참조', box);
  await maker.locator('#editorForm [name="name"]').fill('들바람 모임');
  await maker.evaluate(() => { const f = document.querySelector('#editorForm'); HT.writeDateField(f, 'start', 510); HT.writeDateField(f, 'end', 650); f.querySelector('details[data-adv="names"]').open = true; });
  await maker.locator('#editorForm [data-names-field] [data-name-add]').click();
  await maker.locator('#editorForm [data-names-field] .name-row .x-text').fill('Wind Band');
  await maker.locator('#editorForm [data-names-field] .name-row .x-kind').fill('로마자');
  await maker.locator('#editorForm [name="people"]').fill('솔나라:첫 왕@500, 가람');
  await settleCapture(maker);
  await maker.screenshot({ path: path.join(output, '메이커-단체-폼-이름-구성원-1920-1배.png') });
  const savedGroup = await maker.evaluate(() => HT.viewer.saveEditor());
  check(!!savedGroup, '단체 폼 저장');
  const g0 = await maker.evaluate(() => JSON.parse(JSON.stringify(HT.viewer.maker.draft.groups[0])));
  check(JSON.stringify(g0.people) === JSON.stringify([{ polity: '솔나라', leader: '첫 왕', start: 500 }, '가람']) && g0.names && g0.names[0].text === 'Wind Band' && g0.names[0].kind === 'roman', '작업본의 단체: 구성원은 사람 참조(지도자 칸은 객체) · 이름 목록(종류 id)', g0);
  const linked = await maker.evaluate(uid => {
    const g = HT.viewer.state.model.byUid.get(uid);
    const r = g.peopleList[0];
    return { cell: r.person && r.person.cells[0] ? `${r.person.cells[0].p.name}|${r.person.cells[0].ref}` : '', warn: g.warnings };
  }, savedGroup);
  check(linked.cell.startsWith('솔나라|leader:0'), '메이커의 모델에서도 지도자 칸 구성원이 그 칸의 사람 자리로', linked);
  const same = await maker.evaluate(uid => {
    const before = JSON.stringify(HT.viewer.maker.draft.groups);
    HT.viewer.openEditor(uid);
    const shown = document.querySelector('#editorForm [name="people"]').value;
    HT.viewer.saveEditor();
    return { shown, same: before === JSON.stringify(HT.viewer.maker.draft.groups) };
  }, savedGroup);
  check(same.shown === '솔나라:첫 왕@500, 가람' && same.same, '열어서 그대로 저장하면 단체가 그대로 (구성원 칸에는 "나라:지도자@해" 글)', same);
  const keepTrack = await maker.evaluate(() => {
    const form = document.querySelector('#editorForm');
    const track = form.elements.track.value;
    HT.FORMS.group.fill(form, { name: '트랙 남김', track, start: 510, people: [{ track, polity: '솔나라', leader: '첫 왕' }, '가람'] });
    const kept = HT.FORMS.group.read(form).item.people;
    form.elements.people.value = '솔나라:둘째 왕, 가람';
    const changed = HT.FORMS.group.read(form).item.people;
    return { track, kept, changed };
  });
  check(keepTrack.kept[0].track === keepTrack.track && keepTrack.kept[0].leader === '첫 왕' && !keepTrack.changed[0].track && keepTrack.changed[0].leader === '둘째 왕', '구성원 칸: 글을 고치지 않은 지도자 칸 참조는 트랙까지 그대로 · 고친 것은 새로 읽음', keepTrack);
  await maker.evaluate(() => { HT.viewer.closeEditor(); }); // 묻는 창이 뜨면 그 답을 기다리는 약속 — 기다리지 않고 아래에서 답함
  await maker.waitForFunction(() => document.querySelector('dialog#mkAskDialog[open]') || document.querySelector('#editPane').hidden);
  if (await maker.evaluate(() => !!document.querySelector('dialog#mkAskDialog[open]'))) await maker.locator('#mkAskNo').click(); // 버리고 닫기
  /* 구조 나무 '종류별' */
  await maker.evaluate(() => {
    HT.viewer.openEditor(null, 'institution');
    const form = document.querySelector('#editorForm');
    HT.FORMS.institution.fill(form, { theme: '조세제도', polity: '솔나라', spans: [{ name: '밭 나눔', start: 500 }] });
    HT.viewer.saveEditor();
  });
  const tree = await maker.evaluate(async () => {
    await new Promise(r => setTimeout(r, 50));
    const t = document.querySelector('#mkTree');
    for (const k of ['base', 'lens']) {
      const b = t.querySelector(`[data-tgroup="${k}"]`);
      if (b && b.getAttribute('aria-expanded') !== 'true') b.click();
    }
    await new Promise(r => setTimeout(r, 50));
    for (const k of ['lens:groups', 'lens:institutions']) {
      const b = t.querySelector(`[data-tgroup="${k}"]`);
      if (b && b.getAttribute('aria-expanded') !== 'true') b.click();
    }
    await new Promise(r => setTimeout(r, 50));
    return {
      lens: !!t.querySelector('[data-tgroup="lens"]'),
      base: [...t.querySelectorAll('[data-tbase]')].map(b => b.dataset.tbase),
      rows: [...t.querySelectorAll('[data-tuid]')].map(b => b.textContent.replace(/\s+/g, ' ').trim()),
    };
  });
  check(tree.lens && tree.rows.some(r => r.includes('들바람 모임')) && tree.rows.some(r => r.includes('솔나라 · 조세제도')), "구조 나무 '종류별'에 단체 · 제도 묶음과 그 줄", tree.rows);
  check(['surnames', 'places', 'themes'].every(k => tree.base.includes(k)), "구조 나무 '종류별'의 바탕에 성씨 · 지명 · 주제 표 줄", tree.base);
  const opened = await maker.evaluate(async uid => {
    document.querySelector(`#mkTree [data-tuid="${CSS.escape(uid)}"]`).click();
    await new Promise(r => setTimeout(r, 100));
    const f = document.querySelector('#editorForm');
    return { open: !document.querySelector('#editPane').hidden, name: f && f.elements.name ? f.elements.name.value : '' };
  }, savedGroup);
  check(opened.open && opened.name === '들바람 모임', '구조 나무의 단체 줄을 누르면 편집 창에 그 단체', opened);
  await settleCapture(maker);
  await maker.screenshot({ path: path.join(output, '메이커-구조나무-단체제도-1920-1배.png') });
  await makerContext.close();
  check(report.오류.length === 0, '브라우저 실행 오류 없음', report.오류);
} catch (e) { report.오류.push(e.stack || String(e)); process.exitCode = 1; }
finally { await browser.close(); server.close(); fs.writeFileSync(path.join(output, '화면검사.json'), JSON.stringify(report, null, 2) + '\n'); }
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류, 결과: output }));
