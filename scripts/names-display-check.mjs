/* 원어 병기 · 글꼴(10건 3 · 9 — 갈래 D2 · 감독 선택 docs/설계-10건/감독-선택.md D2)의 실제 브라우저 검사 (크로미움 · 1920×1080 · 배율 1).
   ① 상세 창 머리(결정 1 A): 제목 아래 원어 · 로마자 두 줄 · 언어 · 종류 딱지 없음 · 머리에 오르지 않은 이름만 '다른 이름 n' 칸
   ② 왼쪽 칸만(결정 2): '원어: 왼쪽 칸에도'면 연표 맨 왼쪽 줄 이름 칸에만 원어(책갈피 탭 · 지도자 칸 · 사건에는 없음) · 줄 높이 그대로 · 넘침 없음
   ③ 설정 셋(결정 3 A): 원어 없음 · 상세 창만 · 왼쪽 칸에도 + 적용 체크(나라 · 인물 · 지명) · 고른 값만 저장
   ④ 오른쪽에서 왼쪽 문자(결정 4 B): 줄 이름의 연도가 이름 오른쪽에(방향 격리) · 띠 표에 없는 아랍 원어는 왼쪽 칸에서 로마자로 · 창에서는 아랍 원어 그대로
   ⑤ 글꼴 없음 · 글꼴 팩(결정 4 B · 5 A): 가상 문자 · 한자 확장 글자는 '원어 — ○○ · 글꼴 없음' 딱지 · 글꼴 팩을 켜면 그 글꼴로 보임(판정 표에 팩의 범위) ·
      [글꼴 ▾]은 한글을 덮는 글꼴만 고를 수 있고 고르면 화면 글꼴 목록 맨 앞
   ⑥ 메이커 文 단추(결정 6 A): 네 폼(시대 · 왕조 · 인물 · 사건)의 이름 칸 안 文 → 이름 칸 바로 아래에 명칭 목록 · 닫혀 있으면 0px · 표기 수 딱지 · 폼 왕복
   ⑦ 이름 목록 · 글꼴이 없는 자료(가상 팩 PLAIN만 — 기본팩은 끔)는 무리가 숨고 화면 글꼴 목록을 건드리지 않음 — 기준 폴더(HT_BASELINE_ROOT: 고치기 전 사본)를 주면 같은 화면을 찍어 1px까지 견줌.
      처음에는 기본팩을 '이름 목록이 없는 자료'로 썼으나, 기본팩 자료가 이름 목록(다른 이름)을 가지면 이 검사가 기본팩 내용에 묶이므로 가상 팩으로 바꿈
      (기본팩 끄기는 id 'east-asia-base'에 묶임 — 기본팩 id가 바뀌면 함께 고칠 곳)
   node scripts/names-display-check.mjs <검사할 폴더> <결과 폴더>
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge — 클라우드는 chromium)에.
   검사 자료는 모두 가상 이름(고증 아님) — 확인용 가상 문자 글꼴(사설 영역 U+F1A00~F1A0B 열두 자 · 목업 판의 make-font.py로 만든 것)을 아래에 담았습니다 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/원어-글꼴-검사');
const baseRoot = process.env.HT_BASELINE_ROOT ? path.resolve(process.env.HT_BASELINE_ROOT) : '';
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const serve = (dir, inject) =>
  http.createServer((req, res) => {
    try {
      const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
      const file = path.resolve(dir, rel);
      if (!file.startsWith(dir + path.sep)) { res.writeHead(403); res.end(); return; }
      let bytes = fs.readFileSync(file);
      if (inject && rel === 'js/viewer.js') {
        const text = bytes.toString('utf8'), marker = '/* ---------- 팩 & 모델 ---------- */';
        assert.equal(text.split(marker).length, 2);
        bytes = Buffer.from(text.replace(marker, "window.__state=state;window.__timeline=timeline;window.__openDetail=(...a)=>openDetail(...a);window.__openEditor=(...a)=>openEditor(...a);\n" + marker));
      }
      res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(bytes);
    } catch { res.writeHead(404); res.end(); }
  });
const listen = async srv => { await new Promise(r => srv.listen(0, '127.0.0.1', r)); return 'http://127.0.0.1:' + srv.address().port; };

/* ---------- 검사 자료 (가상 이름 · 고증 아님) ---------- */
const PUA = s => [...s].map(c => String.fromCodePoint(0xf1a00 + parseInt(c, 16))).join('');
const BYEOL = PUA('0123');
const EXTB = '\u{2546E}泉國'; // 첫 글자가 한자 확장 B(U+2546E)
const FONT_TTF = 'data:font/ttf;base64,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';
const NAMES = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'd2-names', name: '확인용 가상 세계(원어)', version: '1.0.0', description: '원어 병기 검사용 가상 자료 — 고증 아님',
  tracks: [{ id: 'd2w', name: '가상 세계', color: '#9fb4c7' }],
  places: [{ id: 'pl-sea', name: '바닷골', names: [{ text: '海谷', lang: 'lzh', kind: '원어' }, { text: 'Badatgol', lang: 'ko-Latn', kind: '로마자' }] }],
  surnames: [{ id: 'sn-sea', name: '바다', description: '확인용 가상 성씨.', names: [{ text: '海', lang: 'lzh', kind: '원어' }, { text: 'Bada', kind: '로마자' }, { text: '大海', kind: '옛 이름' }] }],
  houses: [{ id: 'h-sea', name: '바다 가문', surname: 'sn-sea', names: [{ text: '海氏', lang: 'lzh', kind: '원어' }] }],
  periods: [
    {
      id: 'haeon', track: 'd2w', name: '해온국', start: 1420, end: 1500, color: '#a8c7b8', description: '확인용 가상 나라 — 이름이 넷(원어 · 로마자 · 옛 이름 · 약칭).',
      names: [{ text: '海溫國', lang: 'lzh', kind: '원어' }, { text: 'Haeon-guk', lang: 'ko-Latn', kind: '로마자' }, { text: '溫羅', lang: 'lzh', kind: '옛 이름', start: 1420, end: 1449 }, { text: '海溫', lang: 'lzh', kind: '약칭' }],
      leaders: [{ name: '바다 임금', start: 1420, names: [{ text: '海王', lang: 'lzh', kind: '원어' }, { text: 'Bada Imgeum', kind: '로마자' }] }, { name: '물빛 임금', start: 1460 }],
      capitals: [{ city: 'pl-sea', start: 1420 }],
    },
    { id: 'moon', track: 'd2w', name: '달 왕국', start: 520, end: 680, color: '#b9c6dd', names: [{ text: 'قمر', lang: 'ar', kind: '원어' }, { text: 'Qamar', kind: '로마자' }] },
    { id: 'byeol', track: 'd2w', name: '별바다', start: 540, end: 700, color: '#d8c3cf', names: [{ text: BYEOL, lang: 'x-byeol', kind: '원어' }, { text: 'Yelna Oru', kind: '로마자' }] },
    { id: 'rock', track: 'd2w', name: '돌샘국', start: 600, end: 780, color: '#c9d3b2', names: [{ text: EXTB, lang: 'lzh', kind: '원어' }, { text: 'Dolsaem', kind: '로마자' }] },
    { id: 'long', track: 'd2w', name: '달빛 강 연합 왕국', start: 1400, end: 1480, color: '#c8c0dc', names: [{ text: '月光江聯合王國', lang: 'lzh', kind: '원어' }] },
    { id: 'rtl', track: 'd2w', name: 'قمر', start: 520, end: 680, color: '#e0cfb8', description: '이름 자체가 오른쪽에서 왼쪽으로 쓰는 글자인 나라 — 줄 이름 칸의 연도가 이름 오른쪽에 남는지' },
  ],
  figures: [
    { id: 'f-sol', track: 'd2w', name: '솔빛', role: '학자', birth: 1430, death: 1480, service: [{ polity: '해온국', office: '기록관' }], names: [{ text: '松光', lang: 'lzh', kind: '원어' }, { text: 'Solbit', kind: '로마자' }] },
    { id: 'f-wave', track: 'd2w', name: '물결', lineageOnly: true, birth: 1380, death: 1450, aka: ['물결 어른'], description: '확인용 가상 계보 인물.', names: [{ text: '波', lang: 'lzh', kind: '원어' }, { text: 'Mulgyeol', kind: '로마자' }, { text: '小波', kind: '옛 이름' }] },
  ],
  events: [{ id: 'ev-move', track: 'd2w', title: '바닷골 천도', start: 1430, category: 'politics', place: 'pl-sea', names: [{ text: '海谷遷都', lang: 'lzh', kind: '원어' }] }],
};
/** ⑦ 이름 목록 · 글꼴이 없는 자료 — 서로 겹치는 나라 넷(줄 넷) · 이름 목록 없음 */
const PLAIN = {
  format: 'history-timeline-dlc', formatVersion: 1, id: 'd2-plain', name: '확인용 가상 세계(이름 목록 없음)', version: '1.0.0', description: '이름 목록 · 글꼴이 없는 검사용 가상 자료 — 고증 아님',
  tracks: [{ id: 'd2p', name: '가상 들판', color: '#b6c398' }],
  periods: [
    { id: 'p-deul', track: 'd2p', name: '들메 왕국', start: 1380, end: 1460, color: '#a8c7b8' },
    { id: 'p-galdae', track: 'd2p', name: '갈대 나라', start: 1400, end: 1500, color: '#b9c6dd' },
    { id: 'p-baram', track: 'd2p', name: '바람 고을', start: 1420, end: 1520, color: '#d8c3cf' },
    { id: 'p-morae', track: 'd2p', name: '모래 성읍', start: 1440, end: 1510, color: '#c9d3b2' },
  ],
};
const FONTS = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'd2-font', name: '확인용 가상 문자 글꼴', version: '1.0.0', description: '사설 영역 열두 자 — 검사용',
  fonts: [
    { id: 'byeol', family: '별바다 글씨', src: FONT_TTF, license: '확인용 — 검사 전용', scripts: ['Qaaa'], ranges: ['U+F1A00-F1A0B'] },
    { id: 'hangul-mock', family: '확인용 한글 글꼴', src: FONT_TTF, license: '확인용 — 검사 전용', scripts: ['Hang'], note: '한글을 덮는다고 적은 확인용 글꼴(실제 글자는 없음 — 고르기 길만 봄)' },
  ],
};

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
const ctxOpts = { viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' };
const srv = serve(root, true);
const base = await listen(srv);
const shot = async (page, name, sel, pad = 0) => {
  // 글꼴 비교는 등장 도중의 반투명·이동 화소를 섞지 않는다. 무한 반복 효과는 기다리거나 끄지 않는다.
  const captureState = await page.evaluate(async selector => {
    const el = selector ? document.querySelector(selector) : document.documentElement;
    const read = () => {
      const style = getComputedStyle(el), rect = el.getBoundingClientRect();
      return { opacity: style.opacity, transform: style.transform, left: rect.left, top: rect.top,
        animations: el.getAnimations({ subtree: true }).map(a => ({ state: a.playState, currentTime: a.currentTime, endTime: a.effect?.getComputedTiming().endTime ?? null })) };
    };
    const before = read();
    await document.fonts.ready;
    const finite = el.getAnimations({ subtree: true }).filter(a => Number.isFinite(a.effect?.getComputedTiming().endTime));
    await Promise.all(finite.map(a => a.finished.catch(() => {})));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return { before, after: read() };
  }, sel || null);
  (report.캡처상태 ||= []).push({ file: name, selector: sel || null, ...captureState });
  const box = sel ? await page.evaluate(([s, p]) => { const r = document.querySelector(s).getBoundingClientRect(); return { x: Math.max(0, r.left - p), y: Math.max(0, r.top - p), width: Math.min(1920, r.width + 2 * p), height: Math.min(1080, r.height + 2 * p) }; }, [sel, pad]) : null;
  await page.screenshot({ path: path.join(output, name), clip: box || undefined });
  if (box) await page.screenshot({ path: path.join(output, '전체-' + name) });
};
const settle = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(r, 80)))));
/* 구역(①~⑤ · ⑥ · ⑦)은 따로 돈다 — 앞 구역이 실패해도 뒤 구역을 돌리고, 실패는 구역마다 report.실패에 모아 끝에 종료 코드 1
   (리메이크 6단계 검토: ⑥의 실패가 assert로 검사 전체를 멈춰 ⑦이 정식 실행에서 한 번도 돌지 않던 것) */
const section = async (name, run) => {
  try {
    await run();
  } catch (e) {
    (report.실패 ||= []).push(`${name}: ${e && e.stack ? e.stack : e}`);
  }
};
try {
  /* ---------- ①~⑤ 연표 ---------- */
  await section('①~⑤ 연표', async () => {
    const context = await browser.newContext(ctxOpts);
    await context.addInitScript(([list]) => {
      try {
        if (sessionStorage.getItem('d2-seeded')) return;
        localStorage.setItem('ht.packs.installed', JSON.stringify(list));
        localStorage.setItem('ht.packs.state', JSON.stringify({ 'east-asia-base': { enabled: false }, 'd2-font': { enabled: false } }));
        localStorage.setItem('ht.view', JSON.stringify({ start: 1395, end: 1525 }));
        sessionStorage.setItem('d2-seeded', '1');
      } catch (e) { /* 저장 못 함 */ }
    }, [[NAMES, FONTS]]);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + '/index.html');
    await page.waitForFunction(() => window.__state && window.__state.model && window.__state.model.byUid.has('d2-names/haeon'));
    await settle(page);
    const ui = () => page.evaluate(() => JSON.parse(localStorage.getItem('ht.ui') || '{}'));
    /* ⓪ 판정 표 둘 · 글꼴의 덮는 범위(core.js) — 화면 밖 계산 */
    const t0 = await page.evaluate(fontsPack => {
      const T = HT.glyphTables([]);
      const A = HT.glyphTables([{ scripts: ['Arab'] }]);
      const bad = JSON.parse(JSON.stringify(fontsPack));
      bad.fonts[0].ranges = ['U+F1A00-F1A0B', 'nope', 'u+4e00'];
      const r = HT.normalizePack(bad);
      const back = HT.packToJSON(r.pack);
      return {
        hangulBand: HT.drawable('해온국', T.band), hanjaBand: HT.drawable('海溫國', T.band), latinExt: HT.drawable('Sông Bạc', T.band),
        arabBand: HT.drawable('قمر', T.band), arabWin: HT.drawable('قمر', T.window), arabPackBand: HT.drawable('قمر', A.band),
        oldHangul: [HT.drawable('ᄀᆞᆯ', T.window), HT.missingScriptName('ᄀᆞᆯ', T.window)], combining: [HT.drawable('e\u0301', T.band), HT.missingScriptName('e\u0301', T.band)],
        extA: HT.missingScriptName('\u3400', T.window), missing: HT.glyphMissing('海\u{2546E}\u{2546E}泉', T.window),
        hang: [HT.fontHasHangul({ scripts: ['Hang'] }), HT.fontHasHangul({ ranges: ['U+AC00-D7A3'] }), HT.fontHasHangul({ scripts: ['Hani'] }), HT.fontHasHangul({ ranges: ['U+AC00-AC10'] })],
        ranges: r.pack.fonts[0].ranges, warn: r.warnings.map(w => w.msg).filter(m => /글자 범위/.test(m)), back: back.fonts[0].ranges, version: back.formatVersion,
      };
    }, FONTS);
    check(t0.hangulBand && t0.hanjaBand && t0.latinExt && !t0.arabBand && t0.arabWin && !t0.arabPackBand, '판정 표: 띠 표 = 한글 · 기본 한자 · 라틴(베트남어 미리 합친 글자) — 아랍은 창 표에만, 아랍 글꼴 팩이 있어도 띠 표에는 넣지 않음', t0);
    check(!t0.oldHangul[0] && t0.oldHangul[1] === '옛한글' && !t0.combining[0] && t0.combining[1] === '결합 부호' && t0.extA === '한자 확장 글자' && JSON.stringify(t0.missing) === JSON.stringify([0x2546e]), '판정 표: 옛한글 자모 · 결합 부호 · 한자 확장은 없음 — 없는 글자 목록은 겹치지 않게', t0);
    check(JSON.stringify(t0.hang) === JSON.stringify([true, true, false, false]), '화면 글꼴로 고를 수 있는 글꼴 = 한글 음절 전부(AC00–D7A3)를 덮는 글꼴', t0.hang);
    check(JSON.stringify(t0.ranges) === JSON.stringify(['U+F1A00-F1A0B', 'U+4E00']) && t0.warn.length === 1 && JSON.stringify(t0.back) === JSON.stringify(t0.ranges) && t0.version === 3, "글꼴의 덮는 범위(fonts[].ranges): 'U+…' 꼴로 다듬어 읽고 · 꼴이 틀린 범위는 경고하고 뺌 · 왕복 그대로 · 형식 3", t0);
    const detail = (uid, opts) =>
      page.evaluate(([u, o]) => {
        window.__openDetail(u, o || {});
        const el = document.querySelector('#detail');
        const q = s => el.querySelector(s);
        const h2 = q('h2');
        const when = q('.when');
        /* 머리(제목 아래 ~ 기간 줄 위)의 글과 딱지 */
        const head = [];
        for (let n = h2 && h2.nextElementSibling; n && n !== when; n = n.nextElementSibling) head.push({ cls: n.className, text: n.innerText.trim(), badges: n.querySelectorAll('.badge, .chip, .mk-lang').length });
        const rest = q('.names-rest');
        return {
          text: el.innerText,
          html: el.innerHTML,
          head,
          orig: q('.names-orig') ? q('.names-orig').innerText.trim() : null,
          origHTML: q('.names-orig') ? q('.names-orig').innerHTML : '',
          roman: q('.names-roman') ? q('.names-roman').innerText.trim() : null,
          rest: rest ? { title: rest.querySelector('h3').innerText.trim(), rows: [...rest.querySelectorAll('li')].map(li => [...li.children].map(c => c.innerText.trim())) } : null,
          restBeforeDesc: !!(rest && rest.nextElementSibling && rest.nextElementSibling.classList.contains('desc')),
          line: [...el.querySelectorAll('.names-line')].map(p => p.innerText.trim()),
        };
      }, [uid, opts || null]);
    const setOrig = v => page.evaluate(v2 => { const s = document.querySelector('#origSelect'); s.value = v2; s.dispatchEvent(new Event('change', { bubbles: true })); }, v);
    const setKind = (id, on) => page.evaluate(([i, o]) => { const c = document.querySelector('#' + i); c.checked = o; c.dispatchEvent(new Event('change', { bubbles: true })); }, [id, on]);

    /* ③ 무리 · 기본값 */
    const g0 = await page.evaluate(() => {
      const g = document.querySelector('#namesGroup');
      return { shown: !!g && !g.hidden, inShows: !!(g && g.parentElement.classList.contains('filter-shows')), orig: document.querySelector('#origSelect').value, options: [...document.querySelectorAll('#origSelect option')].map(o => o.textContent), kinds: ['namesPolity', 'namesPerson', 'namesPlace'].map(i => document.querySelector('#' + i).checked), labels: [...g.querySelectorAll('.check')].map(l => l.textContent.trim()), sub: g.querySelector('.filter-sub').textContent, font: !document.querySelector('#fontSelect').hidden };
    });
    check(g0.shown && g0.inShows && g0.orig === 'detail' && g0.options.join('|') === '원어: 상세 창만|원어: 없음|원어: 왼쪽 칸에도' && g0.kinds.every(Boolean) && g0.labels.join('|') === '나라|인물|지명' && g0.sub === '적용' && !g0.font, "필터 시트 '표기' 무리: 원어(상세 창만 · 없음 · 왼쪽 칸에도) · 적용 나라 · 인물 · 지명 — 기본은 상세 창만 · 셋 모두 · 글꼴 팩이 없으면 [글꼴 ▾] 숨김", g0);
    check(!('names' in (await ui())), '고르기 전에는 표기 설정을 저장하지 않음(지금 사용자는 그대로)');
    await page.evaluate(() => document.querySelector('#filterToggle').click());
    await settle(page);
    await shot(page, '1-필터-표기-무리.png', '#filterbar', 8);
    await page.evaluate(() => document.querySelector('#filterToggle').click());

    /* ① 상세 창 머리 */
    const h = await detail('d2-names/haeon');
    check(h.orig === '海溫國' && h.roman === 'Haeon-guk', '상세 창 머리: 제목 아래 첫째 줄 원어 · 둘째 줄 로마자', h.head);
    check(h.head.length === 2 && h.head.every(x => !x.badges) && !h.head.some(x => /한문|로마자|중국어|언어/.test(x.text)), "머리 두 줄에 언어 · 종류 딱지('한문' · '로마자' 등)가 없음", h.head);
    check(/lang="lzh"/.test(h.origHTML) && /<bdi/.test(h.origHTML) && /title="원어 · 한문"/.test(h.origHTML), '원어 글은 <bdi lang>(방향을 가둠) · 언어 이름은 올렸을 때의 풍선에만', h.origHTML);
    check(h.rest && h.rest.title === '다른 이름 2' && JSON.stringify(h.rest.rows) === JSON.stringify([['옛 이름', '溫羅', '1420년 ~ 1449년'], ['약칭', '海溫', '']]) && h.restBeforeDesc, "머리에 오르지 않은 이름만 설명 바로 위 '다른 이름 n개' 칸(종류 · 글 · 쓴 기간) — 머리의 이름은 다시 적지 않음", h.rest);
    await settle(page);
    await shot(page, '1-상세-머리-해온국.png', '#detail');
    const hm = await page.evaluate(() => {
      const r = s => document.querySelector('#detail ' + s).getBoundingClientRect();
      return { h2: r('h2').bottom, orig: [r('.names-orig').top, r('.names-orig').bottom, parseFloat(getComputedStyle(document.querySelector('#detail .names-orig')).fontSize)], roman: [r('.names-roman').top, r('.names-roman').bottom, parseFloat(getComputedStyle(document.querySelector('#detail .names-roman')).fontSize)], when: r('.when').top };
    });
    report.치수 = { 상세머리: hm };
    check(hm.orig[2] === 19 && hm.roman[2] === 13 && hm.orig[0] >= hm.h2 - 0.5 && hm.roman[0] >= hm.orig[1] + 2.9 && hm.when >= hm.roman[1] - 0.5, '머리 두 줄의 크기(원어 19px · 로마자 13px)와 차례(제목 → 원어 → 로마자 → 기간) · 두 줄 사이 최소 3px', hm);
    // CSS 목록만으로 실제 글꼴을 단정하지 않는다: 브라우저가 한글·한자에 쓴 글꼴도 기록한다.
    const fontSession = await context.newCDPSession(page);
    await fontSession.send('DOM.enable');
    await fontSession.send('CSS.enable');
    const fontDoc = await fontSession.send('DOM.getDocument');
    report.실제글꼴 = {};
    for (const [name, selector] of [['제목', '#detail h2'], ['한자원어', '#detail .names-orig bdi'], ['로마자', '#detail .names-roman bdi']]) {
      const { nodeId } = await fontSession.send('DOM.querySelector', { nodeId: fontDoc.root.nodeId, selector });
      report.실제글꼴[name] = (await fontSession.send('CSS.getPlatformFontsForNode', { nodeId })).fonts;
    }
    for (const [name, postScript] of [['제목', 'Pretendard-Bold'], ['한자원어', 'ChosunKm'], ['로마자', 'Pretendard-Regular']]) {
      check(report.실제글꼴[name].length > 0 && report.실제글꼴[name].every(f => f.postScriptName === postScript && f.isCustomFont), `${name}는 실제로 내장 ${postScript}로 그린다`, report.실제글꼴[name]);
    }
    await fontSession.detach();
    const cellL = await detail('d2-names/haeon', { cell: 'leader:0' });
    check(cellL.orig === '海王' && cellL.roman === 'Bada Imgeum', '지도자 칸 창도 같은 머리', cellL.head);
    const cap = await detail('d2-names/haeon', { cell: 'capital:0' });
    check(cap.line.some(l => /지명 바닷골 — 海谷 · Badatgol/.test(l)) && !/원어|로마자/.test(cap.line.join(' ')), '도읍 칸 창: 지명의 원어 · 로마자 한 줄(딱지 없음)', cap.line);
    const fig = await detail('d2-names/f-sol');
    check(fig.orig === '松光' && fig.roman === 'Solbit', '인물 창도 같은 머리', fig.head);
    for (const [uid, orig, roman, title] of [['surname:sn-sea', '海', 'Bada', '성씨'], ['d2-names/f-wave', '波', 'Mulgyeol', '계보-인물']]) {
      const d = await detail(uid);
      check(d.orig === orig && d.roman === roman && d.rest?.title === '다른 이름 1' && d.restBeforeDesc, `${title}: 머리 두 줄과 설명 바로 위 다른 이름 칸`, d);
      const adjacent = await page.evaluate(() => document.querySelector('#detail h2').nextElementSibling?.classList.contains('names-orig') && document.querySelector('#detail .names-orig').nextElementSibling?.classList.contains('names-roman'));
      check(adjacent && !/한문|로마자/.test(d.head.map(x => x.text).join(' ')), `${title}: 제목 바로 아래 두 줄 · 언어와 종류 꼬리 없음`);
      await settle(page);
      await shot(page, `1-상세-머리-${title}.png`, '#detail');
    }
    const ev = await detail('d2-names/ev-move');
    check(ev.orig === '海谷遷都' && ev.roman === null && ev.line.some(l => /장소 바닷골 — 海谷 · Badatgol/.test(l)), '사건 창: 제목의 원어 · 장소의 지명 원어', { head: ev.head, line: ev.line });

    /* ③ 설정 셋 + 적용 체크 */
    await setOrig('none');
    const n0 = await detail('d2-names/haeon');
    check(n0.orig === null && n0.roman === null && !n0.rest && (await ui()).names.orig === 'none', "원어: 없음 — 상세 창에 원어 · 로마자 · '다른 이름' 칸이 없음(형식 3 이전 모습) · 고른 값은 저장", n0.head);
    const n0c = await detail('d2-names/haeon', { cell: 'capital:0' });
    check(!n0c.line.some(l => /海谷/.test(l)), '원어: 없음 — 지명 원어 줄도 없음', n0c.line);
    for (const uid of ['surname:sn-sea', 'd2-names/f-wave']) {
      const d = await detail(uid);
      check(d.orig === null && d.roman === null && !d.rest, `원어 없음: ${uid}의 머리와 다른 이름 칸도 숨김`);
    }
    await setOrig('detail');
    check((await page.evaluate(() => document.querySelectorAll('#timeline .nm-o').length)) === 0, '원어: 상세 창만 — 왼쪽 줄 이름 칸에 원어가 없음');
    await setKind('namesPolity', false);
    const k1 = await detail('d2-names/haeon');
    const k1c = await detail('d2-names/haeon', { cell: 'leader:0' });
    check(k1.orig === null && !k1.rest && k1c.orig === '海王', "적용 '나라'를 끄면 나라 창에는 원어가 없고 인물(지도자 칸)에는 그대로", { k1: k1.head, k1c: k1c.head });
    const snOff = await detail('surname:sn-sea'), lineageOn = await detail('d2-names/f-wave');
    check(snOff.orig === null && snOff.roman === null && !snOff.rest && lineageOn.orig === '波' && !!lineageOn.rest, '나라 적용: 성씨의 머리와 나머지만 숨기고 계보 인물은 유지');
    await setKind('namesPolity', true);
    await setKind('namesPerson', false);
    const k2 = await detail('d2-names/haeon', { cell: 'leader:0' });
    const k2f = await detail('d2-names/f-sol');
    const k2p = await detail('d2-names/haeon');
    check(k2.orig === null && k2f.orig === null && k2p.orig === '海溫國', "적용 '인물'을 끄면 지도자 칸 · 인물 창에 원어가 없고 나라 창에는 그대로");
    const lineageOff = await detail('d2-names/f-wave'), snOn = await detail('surname:sn-sea');
    check(lineageOff.orig === null && lineageOff.roman === null && !lineageOff.rest && snOn.orig === '海' && !!snOn.rest, '인물 적용: 계보 인물의 머리와 나머지만 숨기고 성씨는 유지');
    await setKind('namesPerson', true);
    await setKind('namesPlace', false);
    const k3 = await detail('d2-names/haeon', { cell: 'capital:0' });
    check(!k3.line.some(l => /海谷/.test(l)), "적용 '지명'을 끄면 도읍 칸 창의 지명 원어가 없음", k3.line);
    await setKind('namesPlace', true);
    check(JSON.stringify((await ui()).names) === JSON.stringify({ orig: 'detail', kinds: { polity: true, person: true, place: true } }), '표기 설정은 ht.ui.names = { orig, kinds }로 저장', (await ui()).names);

    /* ② 왼쪽 칸만 */
    await page.evaluate(() => window.__openDetail('d2-names/haeon', {}));
    await page.evaluate(() => document.querySelector('#detail [data-act="close"]').click());
    const rowOf = uid => page.evaluate(u => { const r = document.querySelector(`.tl-row[data-uid="${u}"]`); if (!r) return null; const b = r.getBoundingClientRect(); const nm = r.querySelector('.nm'); return { h: b.height, top: b.top, text: nm.innerText, o: r.querySelector('.nm-o') ? r.querySelector('.nm-o').innerText : null, over: nm.scrollWidth - nm.clientWidth, title: r.title }; }, uid);
    const before = await rowOf('d2-names/haeon');
    await setOrig('band');
    await settle(page);
    const after = await rowOf('d2-names/haeon');
    check(after && after.o === '海溫國' && after.h === before.h && after.top === before.top && after.over <= 0, "원어: 왼쪽 칸에도 — 맨 왼쪽 줄 이름 칸(나라 이름 줄)에 원어 · 줄 높이 · 자리 그대로 · 넘침 없음", { before, after });
    const longRow = await rowOf('d2-names/long');
    check(longRow && longRow.o === null && longRow.over <= 0 && /月光江聯合王國/.test(longRow.title), '이름 + 원어가 칸에 들지 않으면 원어를 빼고(넘침 · 말줄임 없음) 풍선(title)에 원어까지', longRow);
    const only = await page.evaluate(() => {
      const hits = [];
      const walk = document.createTreeWalker(document.querySelector('#timeline'), NodeFilter.SHOW_TEXT);
      for (let n = walk.nextNode(); n; n = walk.nextNode()) if (/海溫國|海王|溫羅/.test(n.nodeValue)) hits.push({ text: n.nodeValue, inRow: !!n.parentElement.closest('.tl-row') });
      return hits;
    });
    check(only.length >= 1 && only.every(x => x.inRow), '원어는 왼쪽 줄 이름 칸에만 — 책갈피 탭 · 지도자 칸 · 사건에는 넣지 않음', only);
    await shot(page, '2-왼쪽-칸-원어.png', '.tl-rows', 0).catch(() => shot(page, '2-왼쪽-칸-원어.png'));
    const ownUid = 'd2-names/haeon';
    const nmBox = await page.evaluate(u => { const r = document.querySelector(`.tl-row[data-uid="${u}"]`); const b = r.getBoundingClientRect(); return { x: Math.max(0, b.left - 4), y: Math.max(0, b.top - 4), width: 260, height: b.height + 8 }; }, ownUid);
    await page.screenshot({ path: path.join(output, '2-왼쪽-칸-원어-확대.png'), clip: nmBox });
    await setKind('namesPolity', false);
    await settle(page);
    check((await rowOf('d2-names/haeon')).o === null, "왼쪽 칸에도 + 적용 '나라' 끔 — 줄 이름 칸에도 원어 없음");
    await setKind('namesPolity', true);

    /* ④ 오른쪽에서 왼쪽 문자 */
    await page.evaluate(() => window.__timeline.setView(500, 800));
    await settle(page);
    const rtl = await page.evaluate(() => {
      const r = document.querySelector('.tl-row[data-uid="d2-names/rtl"]');
      const nm = r.querySelector('.nm bdi').getBoundingClientRect();
      const em = r.querySelector('.nm em');
      return { name: nm.right, year: em ? em.getBoundingClientRect().left : null, yearText: em ? em.innerText : '' };
    });
    check(rtl.year != null && rtl.year >= rtl.name - 0.5 && rtl.yearText === '520–680', '오른쪽에서 왼쪽 글자 이름(قمر)의 줄 이름 칸: 연도가 이름 오른쪽(뒤집히지 않음 — 방향 격리)', rtl);
    const moonRow = await rowOf('d2-names/moon');
    check(moonRow.o === 'Qamar', '띠 표에 없는 아랍 원어는 왼쪽 칸에서 로마자로 물러남(결정 4 B — 새 앱 띠와 같은 답)', moonRow);
    const moonD = await detail('d2-names/moon');
    check(moonD.orig === 'قمر' && /lang="ar"/.test(moonD.origHTML), '창 표에는 아랍 문자가 있어 상세 창에는 아랍 원어 그대로', moonD.head);

    /* ⑤ 글꼴 없음 · 글꼴 팩 */
    const by0 = await detail('d2-names/byeol');
    const rk0 = await detail('d2-names/rock');
    check(by0.orig === '원어 — 가상 문자 · 글꼴 없음' && by0.roman === 'Yelna Oru' && /names-nofont/.test(by0.origHTML) && !by0.html.includes(BYEOL), "가상 문자(사설 영역) 원어: 글 대신 '원어 — 가상 문자 · 글꼴 없음' 딱지 · 로마자 줄은 그대로", by0.head);
    check(rk0.orig === '원어 — 한자 확장 글자 · 글꼴 없음', "한자 확장 B 글자가 든 원어: '원어 — 한자 확장 글자 · 글꼴 없음'", rk0.head);
    await settle(page);
    await shot(page, '5-글꼴-없음-돌샘국.png', '#detail');
    await detail('d2-names/byeol');
    await settle(page);
    await shot(page, '5-글꼴-없음-별바다.png', '#detail');
    const lr = { byeol: await rowOf('d2-names/byeol'), rock: await rowOf('d2-names/rock') };
    check(lr.byeol.o === 'Yelna Oru' && lr.rock.o === 'Dolsaem', '왼쪽 칸: 그릴 수 없는 원어는 로마자로(가상 문자 · 한자 확장)', lr);
    const font0 = await page.evaluate(() => document.documentElement.style.getPropertyValue('--font'));
    check(font0 === '', '글꼴 팩이 꺼져 있으면 화면 글꼴 목록(--font)을 건드리지 않음', font0);
    /* 글꼴 팩 켜기 — 다른 탭에서 켠 것처럼(저장소 사건) */
    await page.evaluate(() => {
      const st = JSON.parse(localStorage.getItem('ht.packs.state'));
      st['d2-font'] = { enabled: true };
      localStorage.setItem('ht.packs.state', JSON.stringify(st));
      window.dispatchEvent(new StorageEvent('storage', { key: 'ht.packs.state' }));
    });
    await page.waitForFunction(() => [...document.fonts].some(f => /HT 글꼴 d2-font byeol/.test(f.family) && f.status === 'loaded'));
    await page.evaluate(() => document.fonts.ready);
    await settle(page);
    const f1 = await page.evaluate(() => ({ stack: document.documentElement.style.getPropertyValue('--font'), opts: [...document.querySelectorAll('#fontSelect option')].map(o => ({ v: o.value, t: o.textContent, d: o.disabled })), shown: !document.querySelector('#fontSelect').hidden }));
    const stackParts = f1.stack.split(',').map(s => s.trim());
    const genericAt = stackParts.findIndex(s => /^(?:serif|sans-serif|monospace|cursive|fantasy|system-ui|ui-serif|ui-sans-serif|ui-monospace|ui-rounded|math|emoji|fangsong)$/i.test(s));
    const packAt = stackParts.indexOf('"HT 글꼴 d2-font byeol"');
    check(packAt > 0 && genericAt > packAt && stackParts[0] === '"Pretendard"', '글꼴 팩은 감독이 고른 프리텐다드를 유지하고 첫 일반 글꼴 이름(sans-serif 등) 앞에 끼움', f1.stack);
    check(f1.shown && f1.opts.length === 3 && f1.opts[0].t === '글꼴: 기본' && f1.opts[1].d && /별바다 글씨 \(없는 글자에만\)/.test(f1.opts[1].t) && !f1.opts[2].d, "[글꼴 ▾]: 기본 + 켜진 글꼴 — 한글이 없는 글꼴은 고를 수 없음('없는 글자에만')", f1.opts);
    const by1 = await detail('d2-names/byeol');
    const rk1 = await detail('d2-names/rock');
    const drawn = await page.evaluate(t => document.fonts.check('19px "HT 글꼴 d2-font byeol"', t), BYEOL);
    check(by1.orig === BYEOL && !/names-nofont/.test(by1.origHTML) && drawn, '글꼴 팩이 덮는 가상 문자 원어는 그 글꼴로 보임(창 표에 팩의 범위)', { orig: by1.orig, drawn });
    check(rk1.orig === '원어 — 한자 확장 글자 · 글꼴 없음', '팩이 덮지 않는 한자 확장 글자는 그대로 글꼴 없음', rk1.head);
    await detail('d2-names/byeol');
    await settle(page);
    await shot(page, '5-글꼴-팩-별바다.png', '#detail');
    await page.evaluate(() => document.querySelector('#detail [data-act="close"]').click());
    await settle(page);
    await shot(page, '5-글꼴-팩-왼쪽-칸.png', '.tl-rows');
    check((await rowOf('d2-names/byeol')).o === BYEOL, '글꼴 팩을 켜면 왼쪽 칸에도 가상 문자 원어(띠 표에 팩의 범위 — 그림판이 그릴 수 있는 범위만)');
    /* 화면 글꼴 고르기 */
    await page.evaluate(() => { const s = document.querySelector('#fontSelect'); s.value = 'hangul-mock'; s.dispatchEvent(new Event('change', { bubbles: true })); });
    await settle(page);
    const f2 = await page.evaluate(() => document.documentElement.style.getPropertyValue('--font'));
    check(/^"HT 글꼴 d2-font hangul-mock", /.test(f2) && (await ui()).fonts.screen === 'hangul-mock', '[글꼴 ▾]로 고른 글꼴은 화면 글꼴 목록 맨 앞(화면 글꼴 — 하나만) · ht.ui.fonts.screen에 저장', f2);
    await page.evaluate(() => { const s = document.querySelector('#fontSelect'); s.value = ''; s.dispatchEvent(new Event('change', { bubbles: true })); });
    const f3 = await page.evaluate(() => document.documentElement.style.getPropertyValue('--font'));
    check(!/^"HT/.test(f3) && /"HT 글꼴 d2-font byeol"/.test(f3), "'글꼴: 기본'으로 되돌리면 화면 글꼴은 기본 · 팩은 없는 글자 채우기로만", f3);
    /* 끄면 원래대로 */
    await page.evaluate(() => {
      const st = JSON.parse(localStorage.getItem('ht.packs.state'));
      st['d2-font'] = { enabled: false };
      localStorage.setItem('ht.packs.state', JSON.stringify(st));
      window.dispatchEvent(new StorageEvent('storage', { key: 'ht.packs.state' }));
    });
    await settle(page);
    const f4 = await page.evaluate(() => ({ stack: document.documentElement.style.getPropertyValue('--font'), faces: [...document.fonts].filter(f => /HT 글꼴/.test(f.family)).length, sel: document.querySelector('#fontSelect').hidden }));
    check(f4.stack === '' && f4.faces === 0 && f4.sel, '글꼴 팩을 끄면 브라우저 글꼴 · 화면 글꼴 목록이 원래대로 · [글꼴 ▾] 숨김', f4);
    check((await detail('d2-names/byeol')).orig === '원어 — 가상 문자 · 글꼴 없음', '글꼴 팩을 끄면 다시 글꼴 없음 딱지');
    /* 그림 내보내기(SVG): 왼쪽 칸 원어도 같은 규칙 */
    await page.evaluate(() => window.__timeline.setView(1395, 1525));
    await settle(page);
    const svg = await page.evaluate(() => window.__timeline.toSVG({ width: 1800 }));
    check(/해온국<tspan dx="4" font-weight="400"[^>]*style="unicode-bidi:isolate">海溫國<\/tspan>/.test(svg), '그림 내보내기(SVG)의 줄 이름에도 원어(보통 굵기 · 방향 격리)');
    await context.close();
  });

  /* ---------- ⑥ 메이커 文 단추 ---------- */
  await section('⑥ 메이커 文 단추', async () => {
    const context = await browser.newContext(ctxOpts);
    await context.addInitScript(raw => { try { if (!sessionStorage.getItem('d2-mk')) { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); sessionStorage.setItem('d2-mk', '1'); } } catch (e) { /* 저장 못 함 */ } }, NAMES);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + '/dlc-maker.html');
    await page.waitForFunction(() => window.__state && window.__state.model && window.__state.model.byUid.has('d2-names/haeon'));
    const formState = (uid, kind) =>
      page.evaluate(async ([u, k]) => {
        window.__openEditor(u ? window.__state.model.byUid.get(u) : null, k);
        await new Promise(r => setTimeout(r, 60));
        const form = document.querySelector('#editorForm');
        const btn = form.querySelector('[data-names-toggle]');
        const box = form.querySelector('details.names-adv[data-adv="names"]');
        const label = btn.closest('label');
        const next = box.nextElementSibling;
        const rect = el => el.getBoundingClientRect();
        return {
          inName: !!btn.closest('.name-in') && !!btn.closest('.name-in').querySelector('input[name="name"], input[name="title"]'),
          after: label.nextElementSibling === box,
          open: box.open, h: rect(box).height, btn: btn.textContent, has: btn.classList.contains('has-names'), exp: btn.getAttribute('aria-expanded'),
          gapClosed: Math.round(rect(next).top - rect(label).bottom),
          inside: (() => { const a = rect(btn), b = rect(btn.closest('.name-in').querySelector('input')); return a.left >= b.left && a.right <= b.right && a.top >= b.top && a.bottom <= b.bottom; })(),
        };
      }, [uid, kind]);
    const click = () => page.evaluate(async () => {
      const form = document.querySelector('#editorForm');
      const btn = form.querySelector('[data-names-toggle]');
      btn.click();
      await new Promise(r => setTimeout(r, 30));
      const box = form.querySelector('details.names-adv[data-adv="names"]');
      const label = btn.closest('label');
      return { open: box.open, h: box.getBoundingClientRect().height, gap: Math.round(box.getBoundingClientRect().top - label.getBoundingClientRect().bottom), cls: btn.className, exp: btn.getAttribute('aria-expanded'), rows: box.querySelectorAll('.name-row').length, focusName: document.activeElement === btn };
    });
    const forms = [['d2-names/haeon', 'period', '文4'], [null, 'dynasty', '文'], ['d2-names/f-sol', 'figure', '文2'], ['d2-names/ev-move', 'event', '文1']];
    for (const [uid, kind, label] of forms) {
      const s = await formState(uid, kind);
      check(s.inName && s.inside && s.after && !s.open && s.h === 0 && s.btn === label && s.has === (label !== '文') && s.exp === 'false', `메이커 ${kind} 폼: 이름 칸 안의 文 단추(표기 수 ${label}) · 명칭 목록은 이름 칸 바로 아래 · 이름이 있어도 닫혀 시작(0px)`, s);
      if (kind === 'period') await shot(page, '6-메이커-文-닫힘.png', '#editPane');
      const o = await click();
      check(o.open && o.h > 40 && o.gap >= 0 && o.gap <= 16 && /is-open/.test(o.cls) && o.exp === 'true', `메이커 ${kind} 폼: 文을 누르면 이름 칸 바로 아래에 명칭 목록이 펼쳐짐`, o);
      if (kind === 'period') await shot(page, '6-메이커-文-펼침.png', '#editPane');
    }
    /* 이름 줄을 더하면 딱지 수가 따라감 · 폼 왕복(채우고 읽은 이름 목록이 같음) */
    const rt = await page.evaluate(async () => {
      window.__openEditor(window.__state.model.byUid.get('d2-names/haeon'), 'period');
      await new Promise(r => setTimeout(r, 60));
      const form = document.querySelector('#editorForm');
      const read = HT.FORMS.period.read(form).item.names;
      form.querySelector('[data-names-toggle]').click();
      form.querySelector('details.names-adv [data-name-add]').click();
      const row = form.querySelector('details.names-adv [data-names-rows]').lastElementChild;
      row.querySelector('.x-text').value = 'Haeon';
      row.querySelector('.x-text').dispatchEvent(new Event('input', { bubbles: true }));
      return { read, btn: form.querySelector('[data-names-toggle]').textContent };
    });
    check(JSON.stringify(rt.read.map(n => n.text)) === JSON.stringify(['海溫國', 'Haeon-guk', '溫羅', '海溫']) && rt.btn === '文5', '메이커 폼 왕복: 닫힌 명칭 목록도 그대로 읽힘 · 이름 줄을 더하면 文 딱지 수가 따라감', rt);
    await context.close();
  });

  /* ---------- ⑦ 이름 목록 · 글꼴이 없는 자료(가상 팩 PLAIN만 — 기본팩은 끔) ---------- */
  await section('⑦ 이름 목록 · 글꼴이 없는 자료', async () => {
    const look = async (b, inject) => {
      const context = await browser.newContext(ctxOpts);
      await context.addInitScript(([plain]) => {
        try {
          if (!sessionStorage.getItem('d2-base')) {
            localStorage.setItem('ht.packs.installed', JSON.stringify([plain]));
            localStorage.setItem('ht.packs.state', JSON.stringify({ 'east-asia-base': { enabled: false } }));
            localStorage.setItem('ht.view', JSON.stringify({ start: 1380, end: 1520 }));
            sessionStorage.setItem('d2-base', '1');
          }
        } catch (e) { /* 저장 못 함 */ }
      }, [PLAIN]);
      const page = await context.newPage();
      page.on('pageerror', e => report.오류.push(e.message));
      await page.goto(b + '/index.html');
      await page.waitForFunction(() => document.querySelectorAll('.tl-row').length > 3);
      await settle(page);
      await page.evaluate(() => document.querySelector('#filterToggle').click());
      await new Promise(r => setTimeout(r, 400));
      const png = await page.screenshot();
      /* 상세 창도: 화면의 첫 나라 줄 이름을 눌러 연 창 */
      await page.evaluate(() => document.querySelector('#filterToggle').click());
      await new Promise(r => setTimeout(r, 400));
      await page.click('.tl-row[data-uid]');
      await new Promise(r => setTimeout(r, 600));
      const png2 = await page.screenshot();
      const info = inject ? await page.evaluate(() => ({ group: !!document.querySelector('#namesGroup') && document.querySelector('#namesGroup').hidden, orig: document.querySelectorAll('.nm-o').length, font: document.documentElement.style.getPropertyValue('--font'), stored: 'names' in JSON.parse(localStorage.getItem('ht.ui') || '{}') })) : null;
      await context.close();
      return { png, png2, info };
    };
    const now = await look(base, true);
    fs.writeFileSync(path.join(output, '7-이름-없는-자료-필터.png'), now.png);
    fs.writeFileSync(path.join(output, '7-이름-없는-자료-상세.png'), now.png2);
    check(now.info.group && !now.info.orig && now.info.font === '' && !now.info.stored, "이름 목록 · 글꼴이 없는 자료만(가상 팩 · 기본팩 끔): '표기' 무리 숨김 · 왼쪽 칸 원어 없음 · 화면 글꼴 목록 그대로 · 설정 저장 없음", now.info);
    if (baseRoot) {
      const bsrv = serve(baseRoot, false);
      const bb = await listen(bsrv);
      const was = await look(bb, false);
      bsrv.close();
      fs.writeFileSync(path.join(output, '7-이름-없는-자료-필터-기준.png'), was.png);
      fs.writeFileSync(path.join(output, '7-이름-없는-자료-상세-기준.png'), was.png2);
      check(Buffer.compare(was.png, now.png) === 0, '이름 목록이 없는 자료만: 고치기 전 사본(HT_BASELINE_ROOT)과 화면(필터 시트를 연 1920×1080)이 1px도 다르지 않음', { 기준: baseRoot });
      check(Buffer.compare(was.png2, now.png2) === 0, '이름 목록이 없는 자료만: 고치기 전 사본과 화면(나라 상세 창을 연 1920×1080)이 1px도 다르지 않음', { 기준: baseRoot });
    } else report.검사.push({ 검사: '고치기 전 사본과의 1px 비교', 결과: '건너뜀 — HT_BASELINE_ROOT 없음' });
  });
} catch (e) {
  (report.실패 ||= []).push(String(e && e.stack ? e.stack : e));
} finally {
  await browser.close();
  srv.close();
  fs.writeFileSync(path.join(output, '검사-결과.json'), JSON.stringify(report, null, 2));
}
if (report.실패) {
  for (const f of report.실패) console.log(f);
  console.log(`오류: ${JSON.stringify(report.오류)}`);
  process.exit(1);
}
console.log(`검사 ${report.검사.length} · 오류 ${JSON.stringify(report.오류)}`);
process.exit(report.오류.length ? 1 : 0);
