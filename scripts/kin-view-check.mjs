/* D1(10건 1 · 2) 웹 창의 실제 브라우저 검사 — 승계표 · 세계표 · 가문 창의 막대 · 성씨 창 · 계보 전용 인물 창 · 검색 (js/kin-view.js · js/viewer.js · css/viewer.css)
   ① 승계표: 나라 상세의 '승계표' 단추로 열림 · 기본은 지도자만(카드 34 · 이음매 22 · 선 갈래 · 복위 고리 · '다시') · 펼쳐도 누른 카드는 0px ·
      한 사람은 한 번 · 모두 펼친 줄 ≤ 사람 + 지도자 · 키보드(↑↓ → ← Enter Home End) · 줄을 눌러 연 창의 '◀ 승계표'
   ①+ 건의 8의 5번 A: 복위 고리의 화살촉은 아래 끝(다시 오른 카드) · 그 카드의 알약은 'n대에서'(← 없음) · 범례 '복위' 견본도 내려가는 끝
   ② 세계표: 가문 창의 '세계표'로 열림 · 카드 124×42 · 세대 줄 82 · 선 path 여섯 · 양자 · n대손 딱지 · 카드 · 딱지 · 이름표 · 알약 겹침 0 · 창 밖 돌출 0 ·
      접고 펴도 누른 카드는 0px · 찾기 · 전체도 · 파에서 열면 그 파의 하위 나무 · Esc로 닫힘
   ②+ 건의 8의 4: 틀(그림판 1px 먹 20% · 둥근 6 · 좌우 18 · 세대 칸 세로선) · 보기 단계 [보통 | 점](점 12 · 세대 줄 30 · 글 · 장식 없음 · 선 1.2 · 바꿔도 가운데 사람이 제자리 ·
      풍선 '이름 · 곁글' · 점을 누르면 보통으로 그 사람에게 · V · Ctrl+휠) · 이름 미상은 글자 없는 원(지름 14 · 테 2px · 선이 원 위 · 아래에 닿음 · 풍선 '이름 미상') ·
      세그먼트 · V로 점에 들면 한눈 보기(맨 위부터 · 좁으면 가로 가운데), 제자리는 Ctrl+휠(커서 밑) · 점 누르기 · 보통으로 돌아올 때(가운데 사람) · 창 둘레 1px 먹 20% · 둥근 12
   ③ 가문 창(다스린 기간 막대 · 세계표 단추 · 계보 전용 n명 줄) · 성씨 창(가문 둘 · 막대) · 가문 조명(timeline.setHouse(ids, { spans, dim: true }))
   ④ 계보 전용 인물 창(생몰 비움 · 고르지 않음) · 검색(계보 전용 · ○○파, 해 칸 비움, 연표 강조 없음)
   ⑤ 견본(samples/sample-lantern.json — 등불 연대기, 가문 19 · 파 7 — 2.0.1)의 가문 창 글이 그대로(새 단추 · 막대만 더해짐 — kin-view.js를 빼고 연 창과 견줌) · 금지 낱말 없음
   ⑥ 가상 대가족 2만(이 검사가 결정적으로 지음 — 가상 음절 이름): 모두 펼친 승계표 · 세계표의 창 안 요소 ≤ 400 · 밀고 끄는 동안도
   ⑦ 메이커 미리 보기: 머리 칩 ✏️ · 빈 값의 점선 칩이 HT.maker.kin.editHead({ kind, uid, field })를 부름
   ⑧ 1배 그림(1920×1080 · 배율 1): 승계표 · 세계표 · 성씨 창을 결과 폴더에, 목업 판 그림이 있으면 나란히 붙인 그림도
   node scripts/kin-view-check.mjs <검사할 폴더> <결과 폴더> [목업 판 폴더]
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)에.
   계약 도우미(js/core.js의 HT.kinSkeleton · successionRows …)가 없으면 이 검사는 '도우미 없음'으로 멈춥니다(옛 core.js — 창 단추가 없어야 함만 봄) */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.');
const output = path.resolve(process.argv[3] || '배포/계보-창-검사');
const mockDir = process.argv[4] ? path.resolve(process.argv[4]) : '';
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      const text = bytes.toString('utf8');
      const marker = '/* ---------- 팩 & 모델 ---------- */';
      assert.equal(text.split(marker).length, 2);
      bytes = Buffer.from(text.replace(marker, 'window.__state=state;window.__openDetail=(...a)=>openDetail(...a);\n' + marker));
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = 'http://127.0.0.1:' + server.address().port;

/* ---------- 가상 자료 (실제 역사 이름 없음) ---------- */
const PID = 'kv-check';
const W = '서쪽 나라';
/* 목업 결정 2 A의 사람 20 · 11세대와 같은 짜임(양자 둘 · 양자로 들어간 곁가지 · 그 생가 쪽 6대손 · 두 나라 지도자)을 가상 이름으로 */
const westLeaders = [
  ['가온 임금', 1623, 1649, null, null],
  ['나린 임금', 1649, 1659, ['아들', '세습'], [['가온 임금', 1623, '부']]],
  ['라온 임금', 1659, 1674, ['아들', '세습'], [['나린 임금', 1649, '부']]],
  ['마루 임금', 1674, 1720, ['아들', '세습'], [['라온 임금', 1659, '부']]],
  ['바다 임금', 1720, 1724, ['아들', '세습'], [['마루 임금', 1674, '부']]],
  ['사랑 임금', 1724, 1776, ['동생', '세습'], [['마루 임금', 1674, '부']]],
  ['자람 임금', 1776, 1800, ['손자', '세습'], [['f-areum', null, '부']]],
  ['타래 임금', 1800, 1834, ['아들', '세습'], [['자람 임금', 1776, '부']]],
  ['이슬 임금', 1834, 1849, ['손자', '세습'], [['f-guseul', null, '부']]],
  ['노을 임금', 1849, 1863, ['방계', '추대'], [['f-parang', null, '생부'], ['타래 임금', 1800, '양부']]],
  ['바람 임금', 1863, 1897, ['미상', '추대'], [['f-duru', null, '생부'], ['f-guseul', null, '양부']]],
];
const ref = (name, start, polity = W) => (start == null ? name : `${polity}:${name}@${start}`);
const leader = ([name, s, e, acc, parents]) => Object.assign({ name, start: s, end: e }, acc ? { accession: { kin: acc[0], how: acc[1] } } : null, parents ? { parents: parents.map(([w, st, as]) => ({ who: ref(w, st), as })) } : null);
const lin = (id, name, parents, extra = {}) => Object.assign({ id, track: 'kvw', name, lineageOnly: true }, extra, parents ? { parents } : null);
/* 목업 결정 1 A(지도자 16 — 손자 · 세습, 숙부 · 찬탈, 동생 · 추대, 형 · 복위 = 6대와 같은 사람, 사촌 · 추대 …)와 같은 이음매 짜임 */
const eastNames = ['가람제', '나래제', '다올제', '라임제', '마루제', '바름제', '사랑제', '바름제', '아름제', '자람제', '차오제', '카나제', '타리제', '파랑제', '하랑제', '가온제'];
const eastKin = [null, ['손자', '세습'], ['숙부', '찬탈'], ['아들', '세습'], ['아들', '세습'], ['아들', '세습'], ['동생', '추대'], ['형', '복위'], ['아들', '세습'], ['아들', '세습'], ['아들', '세습'], ['사촌', '추대'], ['아들', '세습'], ['아들', '세습'], ['손자', '세습'], ['아들', '세습']];
const eastYears = [1368, 1398, 1402, 1424, 1425, 1435, 1449, 1457, 1464, 1487, 1505, 1521, 1567, 1572, 1620, 1621, 1627];
const eastLeaders = eastNames.map((n, i) => Object.assign({ name: n, start: eastYears[i], end: eastYears[i + 1] }, eastKin[i] ? { accession: { kin: eastKin[i][0], how: eastKin[i][1] } } : null, i === 7 ? { person: { polity: '동쪽 나라', leader: '바름제', start: 1435 } } : null));
/* 목업 결정 8 A(지도자 일곱 — 선양 셋 · 세습 둘 · 찬탈) */
const northKin = [null, ['아들', '선양'], ['동생', '선양'], ['아들', '선양'], ['아들', '세습'], ['아들', '세습'], ['숙부', '찬탈']];
const northYears = [1392, 1398, 1400, 1418, 1450, 1452, 1455, 1468];
const northLeaders = ['한빛 임금', '두빛 임금', '세빛 임금', '네빛 임금', '닷빛 임금', '엿빛 임금', '일빛 임금'].map((n, i) => Object.assign({ name: n, start: northYears[i], end: northYears[i + 1] }, northKin[i] ? { accession: { kin: northKin[i][0], how: northKin[i][1] } } : null));
const pack = {
  format: 'history-timeline-dlc',
  formatVersion: 3,
  id: PID,
  name: '가상 계보 검사',
  version: '1.0.0',
  tracks: [{ id: 'kvw', name: '가상 서쪽 들', color: '#c8b193', order: 1 }, { id: 'kve', name: '가상 동쪽 강', color: '#a0bcc5', order: 2 }],
  peoples: [{ id: 'kv-nuri', name: '가상 누리족' }],
  houses: [
    { id: 'h-heuin', name: '흰내 한씨', surname: '한', seat: '흰내', founder: ref('가온 임금', 1623), color: '#c8a27c', track: 'kvw', people: '가상 누리족', tags: ['왕실'] },
    { id: 'h-dasom', name: '다솜대군파', parent: 'h-heuin', founder: 'f-dasom', color: '#a0bcc5' },
    { id: 'h-solnae', name: '솔내 한씨', surname: '한', seat: '솔내', founder: '솔내 나라:솔 첫 임금@1500', color: '#b6c398' },
    { id: 'h-solbig', name: '솔 큰군파', parent: 'h-solnae', founder: 'f-sol-big', color: '#bbacc8' },
    { id: 'h-water', name: '물결 가문', surname: '물결', color: '#d1a9b9' },
  ],
  periods: [
    { id: 'west', track: 'kvw', name: W, people: '가상 누리족', house: 'h-heuin', start: 1623, end: 1897, tags: ['가상 왕조'], leaders: westLeaders.map(leader) },
    {
      id: 'dawn', track: 'kvw', name: '새벽 나라', people: '가상 누리족', house: 'h-heuin', start: 1897, end: 1910,
      leaders: [
        { name: '바람 임금', start: 1897, end: 1907, person: { polity: W, leader: '바람 임금', start: 1863 } },
        { name: '새솔 임금', start: 1907, end: 1910, accession: { kin: '아들', how: '선양' }, parents: [{ who: '새벽 나라:바람 임금@1897', as: '부' }] },
      ],
    },
    { id: 'east', track: 'kve', name: '동쪽 나라', start: 1368, end: 1627, leaders: eastLeaders },
    { id: 'north', track: 'kve', name: '북쪽 나라', start: 1392, end: 1468, leaders: northLeaders },
    {
      id: 'solnae', track: 'kvw', name: '솔내 나라', house: 'h-solnae', start: 1500, end: 1622,
      leaders: [
        { name: '솔 첫 임금', start: 1500, end: 1540 },
        { name: '솔 둘째 임금', start: 1540, end: 1580, accession: { kin: '아들', how: '세습' }, parents: [{ who: '솔내 나라:솔 첫 임금@1500', as: '부' }] },
        { name: '솔 셋째 임금', start: 1580, end: 1622, accession: { kin: '미상', how: '찬탈' } },
      ],
    },
  ],
  figures: [
    lin('f-dasom', '다솜대군', [{ who: ref('가온 임금', 1623), as: '부' }], { role: '대군', birth: 1622 }),
    lin('f-areum', '아름 세자', [{ who: ref('사랑 임금', 1724), as: '부' }], { role: '세자', birth: 1735, death: 1762 }),
    lin('f-chaoreum', '차오름군', [{ who: 'f-areum', as: '부' }], { role: '군' }),
    lin('f-kara', '카라군', [{ who: 'f-areum', as: '부' }], { role: '군' }),
    lin('f-parang', '파랑 대원군', [{ who: 'f-chaoreum', as: '부' }]),
    lin('f-haneul', '하늘군', [{ who: 'f-kara', as: '양부' }, { who: 'f-dasom', as: '후손', gen: 6 }]),
    lin('f-guseul', '구슬 세자', [{ who: ref('타래 임금', 1800), as: '부' }], { birth: 1809, death: 1830 }),
    lin('f-duru', '두루 대원군', [{ who: 'f-haneul', as: '부' }]),
    /* 솔내 한씨: 파(솔 큰군파) · 이름 미상의 공유 자리(형제 둘이 한 빈 고리 아래) · 날짜 없는 계보 전용 · 외손(가문 밖 잎) */
    lin('f-sol-big', '솔 큰군', [{ who: '솔내 나라:솔 첫 임금@1500', as: '부' }], { role: '군' }),
    lin('f-sol-unk', '미상', [{ who: 'f-sol-big', as: '부' }]),
    lin('f-sol-a', '한 가을', [{ who: 'f-sol-unk', as: '부' }]),
    lin('f-sol-b', '한 겨울', [{ who: 'f-sol-unk', as: '부' }], { birth: 1560 }),
    lin('f-sol-dau', '한 달님', [{ who: '솔내 나라:솔 첫 임금@1500', as: '부' }], { role: '공주', birth: 1545 }),
    lin('f-water-a', '물결 바위', [{ who: 'f-sol-dau', as: '모' }], { birth: 1566, house: 'h-water' }),
  ],
};
/* 가상 대가족 2만 — 결정적(난수 없음): 셋째 갈래 나무 · 지도자 서른(한 줄의 후손) · 파 열둘 */
function bigPack(N = 20000) {
  const SY = ['가', '나', '다', '라', '마', '바', '사', '아', '자', '차', '카', '타', '파', '하', '온', '솔', '빛', '별', '달', '물'];
  const nm = i => `큰 ${SY[i % 20]}${SY[Math.floor(i / 20) % 20]}${SY[Math.floor(i / 400) % 20]}`;
  const figures = [];
  for (let i = 0; i < N; i++) figures.push(Object.assign({ id: `b${i}`, track: 'bigt', name: nm(i), lineageOnly: true }, i ? { parents: [{ who: `b${Math.floor((i - 1) / 3)}`, as: '부' }] } : null));
  const line = [];
  for (let i = 0; i < N; i = i * 3 + 1) line.push(i);
  const leaders = [];
  let y = 1000;
  for (let k = 0; k < 30; k++) {
    const who = k < line.length ? line[k] : 3 + k * 7;
    leaders.push(Object.assign({ name: `큰 임금 ${k + 1}`, start: y, end: y + 10, person: `b${who}` }, k ? { accession: { kin: k < line.length ? '아들' : '방계', how: '세습' } } : null));
    y += 10;
  }
  const houses = [{ id: 'h-big', name: '큰 가문', surname: '큰', founder: 'b0', color: '#c8a27c' }];
  for (let k = 0; k < 12; k++) houses.push({ id: `h-big-${k}`, name: `큰 ${k + 1}파`, parent: 'h-big', founder: `b${13 + k}`, color: '#a0bcc5' });
  return { format: 'history-timeline-dlc', formatVersion: 3, id: 'kv-big', name: '가상 대가족', version: '1.0.0', tracks: [{ id: 'bigt', name: '가상 큰 들', color: '#b6c398' }], houses, periods: [{ id: 'bign', track: 'bigt', name: '큰 나라', house: 'h-big', start: 1000, end: 1300, leaders }], figures };
}

const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
// 정지 화면은 글꼴과 유한한 등장 효과가 끝난 뒤 찍는다. 무한 반복 효과는 그대로 둔다.
const settleCapture = page => page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all(document.getAnimations()
    .filter(a => Number.isFinite(a.effect?.getComputedTiming().endTime))
    .map(a => a.finished.catch(() => {})));
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
});
const report = { 화면: '1920×1080 · 100%', 도우미: '', 검사: [], 오류: [], 그림: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};
const BAD = /재위|즉위|퇴위|재임|임기|계승/;
let famRect = [0, 0, 1, 1];
let detRect = [0, 0, 1, 1];
const OLD_WORDS = /앞 지도자|자리 이음/;
async function open(packs, { page: url = '/index.html', draft = null, noKin = false } = {}) {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  await context.addInitScript(({ list, draft }) => {
    if (sessionStorage.getItem('kv-seeded')) return;
    sessionStorage.setItem('kv-seeded', '1');
    localStorage.clear();
    localStorage.setItem('ht.packs.installed', JSON.stringify(list));
    if (draft) localStorage.setItem('ht.maker.draft', JSON.stringify(draft));
  }, { list: packs, draft });
  if (noKin) await context.route('**/js/kin-view.js', r => r.fulfill({ status: 200, contentType: 'text/javascript', body: '/* 빠짐 */' }));
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => m.type() === 'error' && !/Service Worker|서비스 워커/.test(m.text()) && report.오류.push(m.text()));
  await page.goto(base + url);
  await page.waitForFunction(() => window.__state && window.__state.model && window.HT && HT.viewer, null, { timeout: 120000 });
  await page.waitForTimeout(200);
  return { context, page };
}
const rect = (page, sel) => page.evaluate(s => {
  const el = typeof s === 'string' ? document.querySelector(s) : null;
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x, y: r.y, w: r.width, h: r.height };
}, sel);
const shot = async (page, name, selector) => {
  const file = path.join(output, name);
  await settleCapture(page);
  const clip = selector ? await rect(page, selector) : null;
  await page.screenshot({ path: file, clip: clip ? { x: Math.max(0, Math.floor(clip.x)), y: Math.max(0, Math.floor(clip.y)), width: Math.ceil(clip.w), height: Math.ceil(clip.h) } : undefined });
  report.그림.push(file);
  return file;
};

try {
  /* ---------- 도우미 확인 ---------- */
  const { context, page } = await open([pack]);
  const helpers = await page.evaluate(() => ['kinSkeleton', 'kinLayout', 'kinDefaultOpen', 'kinOf', 'kinOfPerson', 'successionRows', 'successionOpen', 'accessionLine', 'accessionSeam', 'polityHead', 'houseHead', 'houseUnder', 'houseSpans', 'houseEras'].filter(k => typeof HT[k] !== 'function'));
  report.도우미 = helpers.length ? `없음: ${helpers.join(' · ')}` : '모두 있음';
  if (helpers.includes('kinSkeleton') || helpers.includes('successionRows')) {
    /* 옛 core.js: 창 단추가 없어야(조용히 비켜 감) */
    const t = await page.evaluate(() => {
      window.__openDetail('kv-check/east');
      return document.querySelector('#detail').innerText;
    });
    check(!/승계표/.test(t), '도우미가 없으면 나라 상세에 승계표 단추가 없음(옛 화면 그대로)');
    throw Object.assign(new Error('계약 도우미가 없어 창 검사를 건너뜀'), { skip: true });
  }
  const m0 = await page.evaluate(() => ({ lineage: (__state.model.lineageFigures || []).length, figures: (__state.model.figures || []).filter(f => f.packId === 'kv-check').length }));
  check(m0.lineage === 14 && m0.figures === 0, '견본의 계보 전용 인물 14명이 model.lineageFigures에 · 띠 인물에 없음', m0);
  await page.evaluate(() => {
    const tl = HT.viewer.timeline;
    const orig = tl.setHouse.bind(tl);
    window.__houseCalls = [];
    tl.setHouse = (ids, o) => {
      window.__houseCalls.push([ids, o ? { spans: (o.spans || []).length, dim: !!o.dim } : null]);
      return orig(ids, o);
    };
  });

  /* ---------- ① 승계표 ---------- */
  const succOpen = async uid => {
    await page.evaluate(u => window.__openDetail(u), uid);
    const btn = await page.$('#detail [data-kin-succ=""]');
    check(!!btn, `${uid}: 나라 상세 '지도자' 상자 머리에 승계표 단추`);
    await btn.click();
    await page.waitForSelector('#detail .kv-succ .kv-row');
    await page.waitForTimeout(100);
  };
  const rowsOf = () => page.evaluate(() => {
    const host = document.querySelector('#detail .kv-succ');
    const list = [...host.querySelectorAll('.kv-row')].map(el => {
      const r = el.getBoundingClientRect();
      return { k: el.dataset.k, cls: el.className, line: el.dataset.line || '', y: r.y, h: r.height, text: el.innerText.replace(/\s+/g, ' ').trim() };
    });
    return { list: list.sort((a, b) => a.y - b.y), height: host.getBoundingClientRect().height, dom: host.querySelectorAll('*').length + 1 };
  });
  await succOpen('kv-check/east');
  {
    const r = await rowsOf();
    const cards = r.list.filter(x => /is-L/.test(x.cls));
    const seams = r.list.filter(x => /is-S/.test(x.cls));
    check(cards.length >= 12 && cards.every(c => Math.round(c.h) === 34), '승계표 기본: 지도자 카드만(34px)', { cards: cards.length });
    check(seams.every(s => Math.round(s.h) === 22), '이음매 22px');
    check(Math.round(r.height) === 34 + 56 * 15, '목록 높이 = 34 + 56 × 15 (지도자만 · 펼침 없음)', r.height);
    const st = await page.evaluate(() => {
      const d = document.querySelector('#detail');
      return { text: d.innerText, head: d.querySelector('.detail-head .badges').innerText.replace(/\s+/g, ' '), legend: !!d.querySelector('.kv-legend'), loops: d.querySelectorAll('.kv-loop').length, again: [...d.querySelectorAll('.kv-again')].length };
    });
    check(/지도자 16(?![\d명])/.test(st.text) && !/지도자 16명 · 전임자와의 관계/.test(st.text) && st.legend, '승계표 머리 글(이름 + 수만 — 건의 8) · 범례', st.text.slice(0, 120));
    check(/가상 동쪽 강 › 동쪽 나라/.test(st.head), "머리 칩: 구분 › 국가 이름 (민족을 적지 않은 나라는 칩을 뺌)", st.head);
    const seamBy = n => (r.list.find(x => x.k === `S${n}`) || {});
    check(seamBy(1).line === 'solid' && /손자 · 세습/.test(seamBy(1).text), '이음매 2대: 손자 · 세습 = 실선', seamBy(1));
    check(seamBy(2).line === 'cut' && /숙부 · 찬탈/.test(seamBy(2).text), '이음매 3대: 숙부 · 찬탈 = 끊긴 선 + 빗금', seamBy(2));
    check(seamBy(7).line === 'res' && /형 · 복위/.test(seamBy(7).text) && /6대와 같은 사람/.test(seamBy(7).text), '이음매 8대: 형 · 복위 = 실선 + 고리 · 6대와 같은 사람', seamBy(7));
    check(st.loops === 1 && st.again === 1, "복위 고리 하나 · '다시' 딱지 하나", st);
    /* 건의 8의 5번 A: 화살촉은 아래 끝(다시 오른 8대 카드 쪽 — 시간이 흐르는 쪽) · 알약 '6대에서' · 범례 견본도 내려가는 끝 */
    const res = await page.evaluate(() => {
      const d = document.querySelector('#detail');
      const loop = d.querySelector('.kv-loop');
      const lr = loop.getBoundingClientRect();
      const a = getComputedStyle(loop, '::before');
      const card = k => {
        const r = d.querySelector(`.kv-row[data-k="${k}"]`).getBoundingClientRect();
        return r.top + r.height / 2;
      };
      const lg = getComputedStyle(d.querySelector('.kv-lg.is-res'), '::after');
      return { tipY: lr.top + parseFloat(getComputedStyle(loop).borderTopWidth) + parseFloat(a.top) + parseFloat(a.height) / 2, tipX: lr.left + parseFloat(a.left) + 1.5, loopLeft: lr.left, loopTop: lr.top, loopBottom: lr.bottom, first: card('L5'), again: card('L7'), back: (d.querySelector('.kv-pill.is-back') || {}).textContent, lgTop: parseFloat(lg.top), lgW: lg.width };
    });
    check(Math.abs(res.tipY - (res.loopBottom - 1)) < 1 && Math.abs(res.tipX - res.loopLeft) < 1 && Math.abs(res.again - (res.loopBottom - 1)) < 1.5 && Math.abs(res.first - (res.loopTop + 1)) < 1.5, '복위 고리: 화살촉은 아래 끝 — 다시 오른 카드(8대)를 가리킴 (건의 8의 5번 A)', res);
    check(res.back === '6대에서', "다시 오른 카드의 알약: '6대에서'(← 없음)", res.back);
    check(res.lgW === '8px' && res.lgTop >= 2, "범례 '복위' 견본의 화살촉도 내려가는 끝(아래)", res);
    check(!BAD.test(st.text) && !OLD_WORDS.test(st.text), "승계표 글에 금지 낱말 · 옛 말('앞 지도자' · '자리 이음')이 없음");
    await shot(page, 'kv-succession-1x.png');
    const dr = await rect(page, '#detail');
    detRect = [Math.round(dr.x), Math.round(dr.y), Math.round(dr.w), Math.round(dr.h)];
    await shot(page, 'kv-succession-panel-1x.png', '#detail');
  }
  await succOpen('kv-check/north');
  {
    const r = await rowsOf();
    const lines = r.list.filter(x => /is-S/.test(x.cls)).map(x => x.line);
    check(lines.join() === 'two,two,two,solid,solid,cut', '목업 결정 8 A 꼴: 선양 겹선 셋 · 세습 실선 둘 · 찬탈 끊긴 선', lines);
    await shot(page, 'kv-succession-8a-1x.png', '#detail');
  }
  /* 펼치기 · 접기: 누른 카드는 0px · 한 사람 한 번 · 모두 펼친 줄 ≤ 사람 + 지도자 */
  await succOpen('kv-check/west');
  {
    const before = await rect(page, '#detail .kv-succ [data-k="L0"]');
    await page.click('#detail .kv-succ [data-kv-pill="0"]');
    await page.waitForTimeout(80);
    const after = await rect(page, '#detail .kv-succ [data-k="L0"]');
    const r = await rowsOf();
    check(Math.abs(after.y - before.y) < 0.5 && Math.abs(after.x - before.x) < 0.5, '승계표: 누른 카드(후손 n ▸)는 화면에서 0px', { before, after });
    check(r.list.some(x => /is-P/.test(x.cls)), '펼치면 그 카드와 이음매 사이에 사람 줄');
    const S1 = r.list.find(x => x.k === 'S1');
    const lastP = r.list.filter(x => /is-P|is-K/.test(x.cls)).pop();
    check(S1 && lastP && S1.y >= lastP.y + lastP.h - 0.5 && r.list.filter(x => /is-P|is-K/.test(x.cls)).every(x => x.line === 'solid'), '펼친 줄은 카드와 다음 이음매 사이 · 왼쪽 여백에 다음 이음매의 선', { S1, lastP });
    await page.click('#detail [data-kin-level="A"]');
    await page.waitForTimeout(80);
    const all = await page.evaluate(() => {
      const rows = (HT.viewer.state.kinSucc || {}).rows ? HT.viewer.state.kinSucc.rows() : [];
      return { rows, people: (HT.viewer.state.model.lineageFigures || []).length };
    });
    const people = all.rows.filter(x => x.t === 'P').map(x => `${x.key}|${x.j}`);
    const leaders = all.rows.filter(x => x.t === 'L').length;
    check(new Set(people).size === people.length, '모두 펼침: 한 사람은 한 번만', { people: people.length });
    check(all.rows.filter(x => x.t !== 'S').length <= 21 + leaders, '모두 펼친 줄 수 ≤ 사람 + 지도자', { rows: all.rows.length });
    await shot(page, 'kv-succession-all-1x.png', '#detail');
    /* 키보드: 초점 → End · Home · ↓ · Enter = 그 칸 창 → '◀ 승계표'로 돌아옴 */
    await page.focus('#detail .kv-succ');
    await page.keyboard.press('End');
    await page.keyboard.press('Home');
    await page.keyboard.press('ArrowDown');
    const act = await page.evaluate(() => (document.querySelector('#detail .kv-succ .kv-row.is-act') || {}).dataset);
    check(act && /^P/.test(act.k), '키보드: Home → ↓ 로 첫 사람 줄', act);
    await page.keyboard.press('Home');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(80);
    const back = await page.$('#detail [data-kin-back]');
    check(!!back && /가온 임금/.test(await page.evaluate(() => document.querySelector('#detail h2').innerText)), "Enter: 그 칸 창 · 바닥에 '◀ 승계표'");
    await back.click();
    await page.waitForSelector('#detail .kv-succ');
    check(await page.evaluate(() => document.querySelectorAll('#detail .kv-succ .kv-row.is-P').length > 0), "'◀ 승계표'로 돌아오면 펼침이 기억에서 그대로");
    await page.click('#detail [data-kin-level="L"]');
    /* 지도자 칸 창의 '승계표에서 보기'(그 카드로 데려가 펼친 채) · '세계표에서 보기' */
    await page.evaluate(() => window.__openDetail('kv-check/west', { cell: 'leader:5' }));
    const links = await page.evaluate(() => [...document.querySelectorAll('#detail .kv-links button')].map(b => b.textContent));
    check(links.join() === '승계표에서 보기,세계표에서 보기', "지도자 칸 창: '승계표에서 보기 · 세계표에서 보기'", links);
    await page.click('#detail .kv-links [data-kin-succ]');
    await page.waitForSelector('#detail .kv-succ');
    await page.waitForTimeout(60);
    const st = await page.evaluate(() => ({ act: (document.querySelector('#detail .kv-succ .kv-row.is-act') || {}).dataset, open: document.querySelector('#detail .kv-succ [data-k="L5"]').getAttribute('aria-expanded'), people: document.querySelectorAll('#detail .kv-succ .kv-row.is-P').length }));
    check(st.act && st.act.k === 'L5' && st.open === 'true' && st.people > 0, "'승계표에서 보기': 그 카드로 데려가 펼친 채", st);
    await page.click('#detail [data-kin-level="L"]');
  }

  /* ---------- ③ 가문 창 · 가문 조명 ---------- */
  await page.evaluate(() => {
    window.__houseCalls.length = 0;
    window.__openDetail('house:h-heuin');
  });
  await page.waitForTimeout(80);
  {
    const st = await page.evaluate(() => {
      const d = document.querySelector('#detail');
      return { text: d.innerText, bars: d.querySelectorAll('.kv-eras .kv-era').length, fam: !!d.querySelector('.detail-foot [data-kin-fam-house]'), calls: window.__houseCalls.slice() };
    });
    check(st.bars === 2 && st.fam, "가문 창: 다스린 기간 막대(나라마다 한 줄) · 바닥의 '세계표'", st.bars);
    check(/계보 전용 인물 \d+명 · 세계표에서 보기/.test(st.text), "가문 창: '계보 전용 인물 n명 · 세계표에서 보기' 한 줄");
    const last = st.calls[st.calls.length - 1] || [];
    check(Array.isArray(last[0]) && last[0].includes('h-heuin') && last[0].includes('h-dasom') && last[1] && last[1].spans > 0 && last[1].dim, '가문 조명: setHouse(본가 + 아래 파, { spans, dim: true })', last);
  }
  /* ---------- ② 세계표 ---------- */
  await page.click('#detail .detail-foot [data-kin-fam-house]');
  await page.waitForSelector('.kv-fam .kv-p');
  await page.waitForTimeout(150);
  const famState = () => page.evaluate(() => {
    const win = document.querySelector('.kv-fam');
    const view = win.querySelector('.kv-view').getBoundingClientRect();
    const box = el => {
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height, k: el.className + ':' + (el.dataset.i || el.textContent.slice(0, 12)) };
    };
    const vis = r => r.x + r.w > view.x && r.x < view.x + view.width && r.y + r.h > view.y && r.y < view.y + view.height;
    const items = [...win.querySelectorAll('.kv-p, .kv-blabel, .kv-fpill, .kv-far, .kv-tag')].map(box).filter(vis);
    return { win: box(win), view: { x: view.x, y: view.y, w: view.width, h: view.height }, items, dom: win.querySelectorAll('*').length + 1, paths: win.querySelectorAll('.kv-edges path').length, text: win.innerText.replace(/\s+/g, ' '), stats: HT.kinView.current().stats() };
  });
  const overlaps = items => {
    const out = [];
    for (let a = 0; a < items.length; a++)
      for (let b = a + 1; b < items.length; b++) {
        const p = items[a];
        const q = items[b];
        const ix = Math.min(p.x + p.w, q.x + q.w) - Math.max(p.x, q.x);
        const iy = Math.min(p.y + p.h, q.y + q.h) - Math.max(p.y, q.y);
        if (ix > 0.5 && iy > 0.5) out.push([p.k, q.k]);
      }
    return out;
  };
  {
    const f = await famState();
    const cards = f.items.filter(x => /kv-p/.test(x.k));
    check(cards.length > 0 && cards.every(c => Math.round(c.w) === 124 && Math.round(c.h) === 42), '세계표 카드 124×42', cards.slice(0, 2));
    const ys = [...new Set(cards.map(c => Math.round(c.y)))].sort((a, b) => a - b);
    check(ys.slice(1).every((y, i) => (y - ys[i]) % 82 === 0), '세대 줄 82px', ys);
    check(f.paths === 6, '선은 갈래마다 path 하나(실선 · 양자 · n대손 × 옅게)', f.paths);
    check(f.stats.n === 20 && f.stats.visible === 20, '사람 20(200명 이하) — 처음 열 때 모두 펼침', f.stats);
    check(/양자/.test(f.text) && /6대손/.test(f.text), "딱지: '양자' · '6대손'");
    check(/가상 서쪽 들 › 가상 누리족 › 흰내 한씨/.test(f.text) && /왕실/.test(f.text), '세계표 머리 칩: 구분 › 민족 › 본관 성씨(이름과 같아 이름은 뺌) · 꼬리표', f.text.slice(0, 80));
    check(!overlaps(f.items).length, '카드 · 딱지 · 파 이름표 · 알약 겹침 0', overlaps(f.items).slice(0, 4));
    check(f.win.x >= 0 && f.win.y >= 0 && f.win.x + f.win.w <= 1920 && f.win.y + f.win.h <= 1080, '세계표 창이 화면 안(창 밖 돌출 0)', f.win);
    const det = await rect(page, '#detail');
    check(f.win.x + f.win.w <= det.x, '세계표 창은 가문 창 왼쪽(겹치지 않음)', { win: f.win, det });
    check(f.dom <= 400, '세계표 창 안 요소 ≤ 400', f.dom);
    check(!BAD.test(f.text), '세계표 글에 금지 낱말 없음');
    await shot(page, 'kv-family-1x.png');
    famRect = [Math.round(f.win.x), Math.round(f.win.y), Math.round(f.win.w), Math.round(f.win.h)];
    /* 건의 8의 4-나: 틀 — 그림판 둘레 1px 먹 20% · 둥근 6 · 좌우 여백 18, 세대 번호 칸 오른쪽 1px 먹 8% 세로선 · 아래 줄 보기 단계 [보통 | 점] */
    const fr = await page.evaluate(() => {
      const v = getComputedStyle(document.querySelector('.kv-fam .kv-view'));
      const g = getComputedStyle(document.querySelector('.kv-fam .kv-gens'));
      return { b: `${v.borderTopWidth} ${v.borderTopColor} ${v.borderTopLeftRadius}`, m: `${v.marginLeft} ${v.marginRight}`, g: g.boxShadow, seg: [...document.querySelectorAll('.kv-fam .kv-seg button')].map(b => `${b.textContent}:${b.getAttribute('aria-checked')}`).join() };
    });
    check(fr.b === '1px rgba(0, 0, 0, 0.2) 6px' && fr.m === '18px 18px' && /rgba\(0, 0, 0, 0\.08\) -1px 0px 0px 0px inset/.test(fr.g), '세계표 틀: 그림판 1px 먹 20% · 둥근 6 · 좌우 18 · 세대 칸 세로선 먹 8% (건의 8의 4-나)', fr);
    check(fr.seg === '보통:true,점:false', '아래 줄 보기 단계 [보통 | 점] — 처음은 보통', fr.seg);
    /* 접고 펴기: 누른 카드는 0px · 접힌 카드 아래 '후손 n명' */
    const areum = await page.evaluate(() => {
      const c = HT.kinView.current();
      return c.indexOf('f:kv-check/f-areum');
    });
    const sel = `.kv-fam .kv-p[data-i="${areum}"]`;
    const b0 = await rect(page, sel);
    await page.mouse.click(b0.x + b0.w - 8, b0.y + 8);
    await page.waitForTimeout(100);
    const b1 = await rect(page, sel);
    const f1 = await famState();
    check(Math.abs(b1.x - b0.x) < 0.5 && Math.abs(b1.y - b0.y) < 0.5, '세계표: 접어도 누른 카드는 화면에서 0px', { b0, b1 });
    check(f1.stats.visible < 20 && f1.items.some(x => /kv-fpill/.test(x.k)), "접으면 하위가 사라지고 카드 아래 '후손 n명'", f1.stats);
    check(!overlaps(f1.items).length, '접은 뒤에도 겹침 0', overlaps(f1.items).slice(0, 4));
    await page.click('.kv-fam .kv-fpill');
    await page.waitForTimeout(100);
    const b2 = await rect(page, sel);
    check(Math.abs(b2.x - b0.x) < 0.5 && Math.abs(b2.y - b0.y) < 0.5 && (await famState()).stats.visible === 20, "'후손 n명'을 누르면 다시 펴지고 카드는 그 자리", b2);
    /* 찾기 → 그 카드로 */
    await page.fill('.kv-fam [data-kv="find"]', '새솔');
    await page.press('.kv-fam [data-kv="find"]', 'Enter');
    await page.waitForTimeout(150);
    const ff = await page.evaluate(() => {
      const c = document.querySelector('.kv-fam .kv-p.is-focus');
      const v = document.querySelector('.kv-fam .kv-view').getBoundingClientRect();
      const r = c ? c.getBoundingClientRect() : null;
      return { name: c ? c.textContent : '', inside: !!r && r.x >= v.x && r.x + r.width <= v.x + v.width && r.y >= v.y && r.y + r.height <= v.y + v.height };
    });
    check(ff.name === '새솔 임금' && ff.inside, '찾기: 이름을 치면 그 카드로 데려가 초점', ff);
    /* 전체도: 누르면 그리로 */
    const s0 = await page.evaluate(() => HT.kinView.current().scroll());
    const ov = await rect(page, '.kv-fam .kv-over');
    await page.mouse.click(ov.x + 4, ov.y + 4);
    await page.waitForTimeout(100);
    const s1 = await page.evaluate(() => HT.kinView.current().scroll());
    check(s1[0] < s0[0] || s1[1] < s0[1] || (s0[0] === 0 && s0[1] === 0), '전체도를 누르면 그 자리로', { s0, s1 });
    /* 건의 8의 4-나: 세계표 창 둘레 1px 먹 20% · 둥근 12 테(붙은 상세 칸의 꼴을 받지 않음) */
    const wb = await page.evaluate(() => { const cs = getComputedStyle(document.querySelector('.kv-fam')); return { shadow: cs.boxShadow, r: cs.borderTopLeftRadius }; });
    check(/rgba\(0, 0, 0, 0\.2\) 0px 0px 0px 1px/.test(wb.shadow) && wb.r === '12px', '세계표 창 둘레: 1px 먹 20% · 둥근 12', wb);
    /* 사람 하나의 화면 자리 · 창 안 한 점에 가장 가까운 사람 */
    const spot = i => page.evaluate(k => { const c = HT.kinView.current(); const r = c.cardRect(k); const [sx, sy] = c.scroll(); return { cx: r.x + r.w / 2 - sx, cy: r.y + r.h / 2 - sy }; }, i);
    const nearestAt = (fx, fy) =>
      page.evaluate(([fx, fy]) => {
        const c = HT.kinView.current();
        const v = document.querySelector('.kv-fam .kv-view');
        const [sx, sy] = c.scroll();
        let best = -1;
        let bd = Infinity;
        for (const g of c.layout().rows)
          for (const i of g) {
            const r = c.cardRect(i);
            const d = Math.abs(r.x + r.w / 2 - sx - v.clientWidth * fx) + Math.abs(r.y + r.h / 2 - sy - v.clientHeight * fy);
            if (d < bd) {
              bd = d;
              best = i;
            }
          }
        const r = c.cardRect(best);
        const vb = v.getBoundingClientRect();
        return { i: best, cx: r.x + r.w / 2 - sx, cy: r.y + r.h / 2 - sy, px: vb.x + v.clientLeft + v.clientWidth * fx, py: vb.y + v.clientTop + v.clientHeight * fy };
      }, [fx, fy]);
    /* 건의 8의 4-가: 세그먼트로 점 → 한눈 보기(맨 위부터 · 판이 좁으면 가로 가운데) · 점 12 · 세대 줄 30 · 글 · 장식 없음 · 선 1.2 */
    await page.click('.kv-fam .kv-seg [data-kv-scale="1"]');
    await page.waitForTimeout(150);
    const dt = await page.evaluate(() => {
      const c = HT.kinView.current();
      const win = document.querySelector('.kv-fam');
      const ps = [...win.querySelectorAll('.kv-p')];
      const v = win.querySelector('.kv-view');
      const vr = v.getBoundingClientRect();
      const rs = ps.map(e => e.getBoundingClientRect());
      const g0 = [...c.layout().rows[0]].map(i => win.querySelector(`.kv-p[data-i="${i}"]`)).filter(Boolean).map(e => e.getBoundingClientRect().y);
      return {
        scale: c.scale(),
        firstTop: Math.min(...g0) - vr.y - v.clientTop,
        mid: (Math.min(...rs.map(r => r.left)) + Math.max(...rs.map(r => r.right))) / 2 - vr.x - v.clientLeft,
        center: 24 + (v.clientWidth - 24) / 2,
        sizes: [...new Set(ps.map(e => { const b = e.getBoundingClientRect(); return `${Math.round(b.width)}x${Math.round(b.height)}`; }))],
        ys: [...new Set(ps.map(e => Math.round(e.getBoundingClientRect().y)))].sort((a, b) => a - b),
        text: ps.map(e => e.textContent).join(''),
        deco: win.querySelectorAll('.kv-blabel, .kv-fpill, .kv-far, .kv-tag').length,
        stroke: getComputedStyle(win.querySelector('.kv-e')).strokeWidth,
        dots: win.classList.contains('is-dots'),
        seg: [...win.querySelectorAll('.kv-seg button')].map(b => b.getAttribute('aria-checked')).join(),
        dom: win.querySelectorAll('*').length + 1,
      };
    });
    check(dt.scale === 1 && dt.dots && dt.firstTop >= 0 && dt.firstTop <= 40 && Math.abs(dt.mid - dt.center) < 2, '세그먼트로 점: 한눈 보기 — 첫 세대 점이 그림판 맨 위 근처 · 판이 좁아 가로 가운데', { firstTop: dt.firstTop, mid: dt.mid, center: dt.center });
    check(dt.sizes.join() === '12x12' && dt.ys.slice(1).every((y, k) => (y - dt.ys[k]) % 30 === 0) && dt.text === '' && dt.deco === 0 && dt.stroke === '1.2px' && dt.seg === 'false,true' && dt.dom <= 400, '점 단계: 지름 12 · 세대 줄 30 · 이름 · 알약 · 파 이름표 · 딱지 없음 · 선 1.2 · 창 안 요소 ≤ 400', dt);
    /* 올리면 풍선 '이름 · 곁글'(먹 바탕 · 종이 글 11.5 · 둥근 4) */
    const anyDot = await page.evaluate(() => {
      const v = document.querySelector('.kv-fam .kv-view').getBoundingClientRect();
      const e = [...document.querySelectorAll('.kv-fam .kv-p.is-ruler')].find(x => {
        const r = x.getBoundingClientRect();
        return r.x > v.x + 30 && r.right < v.right - 4 && r.y > v.y + 30 && r.bottom < v.bottom - 4;
      });
      if (!e) return null;
      const r = e.getBoundingClientRect();
      return { i: Number(e.dataset.i), x: r.x + 6, y: r.y + 6, label: e.getAttribute('aria-label') };
    });
    check(!!anyDot, '점 단계: 화면 안에 지도자 점', anyDot);
    await page.mouse.move(anyDot.x, anyDot.y);
    await page.waitForTimeout(80);
    const tip = await page.evaluate(() => {
      const t = document.querySelector('.kv-fam .kv-tip');
      const cs = getComputedStyle(t);
      return { text: t.hidden ? '' : t.textContent, bg: cs.backgroundColor, color: cs.color, size: cs.fontSize, r: cs.borderTopLeftRadius };
    });
    check(tip.text === anyDot.label && / · /.test(tip.text) && tip.bg === 'rgb(0, 0, 0)' && tip.color === 'rgb(255, 255, 255)' && tip.size === '11.5px' && tip.r === '4px', "점에 올리면 풍선 '이름 · 곁글'(먹 바탕 · 종이 글 11.5 · 둥근 4)", { tip, label: anyDot.label });
    await shot(page, 'kv-family-dots-1x.png');
    /* 점을 누르면 보통으로 돌아오며 그 사람에게 */
    await page.mouse.click(anyDot.x, anyDot.y);
    await page.waitForTimeout(150);
    const back = await page.evaluate(i => {
      const c = HT.kinView.current();
      return { scale: c.scale(), focus: c.indexOf(c.focusedKey()) === i, dots: document.querySelector('.kv-fam').classList.contains('is-dots') };
    }, anyDot.i);
    check(back.scale === 0 && back.focus && !back.dots, '점을 누르면 보통으로 돌아오며 그 사람에게', back);
    /* V 키로 돌기 · Ctrl+휠(아래 = 점 · 위 = 보통) */
    await page.focus('.kv-fam .kv-view');
    const sc = () => page.evaluate(() => HT.kinView.current().scale());
    await page.keyboard.press('v');
    const k1 = await sc();
    await page.keyboard.press('v');
    const k2 = await sc();
    const vr = await rect(page, '.kv-fam .kv-view');
    await page.mouse.move(vr.x + vr.w / 2, vr.y + vr.h / 2);
    await page.keyboard.down('Control');
    await page.mouse.wheel(0, 120);
    await page.waitForTimeout(60);
    const w1 = await sc();
    await page.mouse.wheel(0, -120);
    await page.waitForTimeout(60);
    const w2 = await sc();
    await page.keyboard.up('Control');
    check(k1 === 1 && k2 === 0 && w1 === 1 && w2 === 0, 'V 키로 보통 ↔ 점 · Ctrl+휠 아래로 점 · 위로 보통', { k1, k2, w1, w2 });
    /* 제자리 유지: Ctrl+휠은 커서 밑 사람 · 보통으로 돌아올 때(세그먼트)는 가운데 사람 */
    const at0 = await nearestAt(0.3, 0.4);
    await page.mouse.move(at0.px, at0.py);
    await page.keyboard.down('Control');
    await page.mouse.wheel(0, 120);
    await page.waitForTimeout(60);
    await page.keyboard.up('Control');
    const at1 = await spot(at0.i);
    check((await sc()) === 1 && Math.abs(at1.cx - at0.cx) < 0.5 && Math.abs(at1.cy - at0.cy) < 0.5, 'Ctrl+휠로 점: 커서 밑 사람이 화면에서 제자리', { at0, at1 });
    const mid0 = await nearestAt(0.5, 0.5);
    await page.click('.kv-fam .kv-seg [data-kv-scale="0"]');
    await page.waitForTimeout(150);
    const mid1 = await spot(mid0.i);
    check((await sc()) === 0 && Math.abs(mid1.cx - mid0.cx) < 0.5 && Math.abs(mid1.cy - mid0.cy) < 0.5, '보통으로 돌아올 때: 가운데에 가장 가까운 사람이 화면에서 제자리', { mid0, mid1 });
    /* 키보드: ↑ = 나무 부모 */
    await page.focus('.kv-fam .kv-view');
    await page.evaluate(() => HT.kinView.current().focusKey('f:kv-check/f-guseul'));
    await page.waitForTimeout(50);
    await page.keyboard.press('ArrowUp');
    await page.waitForTimeout(50);
    const up = await page.evaluate(() => (document.querySelector('.kv-fam .kv-p.is-focus') || {}).textContent);
    check(up === '타래 임금', '키보드 ↑: 나무 부모', up);
    const cardSel = `.kv-fam .kv-p[data-i="${await page.evaluate(() => HT.kinView.current().indexOf('f:kv-check/f-guseul'))}"]`;
    await page.click(cardSel, { button: 'right' });
    const menu = await page.evaluate(() => [...document.querySelectorAll('#ctxMenu:not([hidden]) .ctx-label')].map(x => x.textContent));
    check(menu.includes('세계표에서 보기') && menu.includes('승계표에서 보기') && menu.includes('창 열기'), "세계표 카드 메뉴: 창 열기 · 세계표에서 보기 · 승계표에서 보기", menu);
    await page.click('.kv-fam .kv-title h2'); // 메뉴 바깥을 누르면 메뉴가 닫힘
    await page.focus('.kv-fam .kv-view');
    await page.keyboard.press('Escape');
    check(!(await page.$('.kv-fam')), 'Esc: 세계표 창이 닫힘(상세 창은 그대로)');
    check(!!(await page.$('#detail:not([hidden])')), 'Esc로 세계표를 닫아도 가문 창은 남음');
  }
  /* 파에서 열면 그 파의 하위 나무 · 본가 쪽 한 줄 */
  await page.evaluate(() => window.__openDetail('house:h-solbig'));
  await page.click('#detail .detail-foot [data-kin-fam-house]');
  await page.waitForSelector('.kv-fam .kv-p');
  {
    const f = await famState();
    check(/솔 큰군파 세계표/.test(f.text) && /본가 쪽: 솔 첫 임금/.test(f.text) && f.stats.n === 4, '파에서 열면 파조의 하위 나무(새로 짓지 않음) · 본가 쪽 조상 한 줄', { n: f.stats.n });
    /* 건의 8의 4-다: 이름 미상은 글자 없이 원 하나(지름 14 · 종이빛 · 테 2px) — 부모 선은 원 아래에서 나가고 자식으로 오는 선은 원 위에 닿음 · 올리면 풍선 '이름 미상' */
    const uk = await page.evaluate(() => {
      const u = document.querySelector('.kv-fam .kv-p.is-unk');
      const r = u.getBoundingClientRect();
      const a = getComputedStyle(u, '::after');
      const cy = r.y + r.height / 2;
      const ends = [];
      for (const p of document.querySelectorAll('.kv-fam .kv-e')) {
        const svg = p.ownerSVGElement.getBoundingClientRect();
        const d = p.getAttribute('d') || '';
        for (const m of d.matchAll(/M([-\d.]+) ([-\d.]+)/g)) ends.push(['M', Number(m[2]) + svg.y]);
        for (const m of d.matchAll(/V([-\d.]+)/g)) ends.push(['V', Number(m[1]) + svg.y]);
      }
      return { text: u.textContent, aria: u.getAttribute('aria-label'), w: a.width, h: a.height, ring: a.boxShadow, x: r.x + r.width / 2, y: cy, ends: ends.filter(e => Math.abs(e[1] - cy) < 10).map(e => e[0] + Math.round((e[1] - cy) * 10) / 10) };
    });
    check(f.items.filter(x => /is-unk/.test(x.k)).length === 1 && uk.text === '' && uk.aria === '이름 미상' && uk.w === '14px' && uk.h === '14px' && /2px/.test(uk.ring), "이름 미상의 공유 자리: 글자 없이 원 하나(지름 14 · 테 2px — 읽는 이름은 aria-label '이름 미상')", uk);
    check(uk.ends.includes('M7') && uk.ends.includes('V-7'), '이름 미상: 부모 선은 원 아래에서 나가고 자식 선은 원 위에 닿음', uk.ends);
    await page.mouse.move(uk.x, uk.y);
    await page.waitForTimeout(80);
    check((await page.evaluate(() => { const t = document.querySelector('.kv-fam .kv-tip'); return t.hidden ? '' : t.textContent; })) === '이름 미상', "이름 미상에 올리면 풍선 '이름 미상'");
    /* 원에는 ▾ 손잡이가 없음(그리지도 · 누르는 자리도) — 접기는 Space · 모두 접기. 키보드 초점은 원 둘레(반지름 7 + 4) */
    const uf = await page.evaluate(() => {
      const u = document.querySelector('.kv-fam .kv-p.is-unk');
      const before = { cls: u.className, handle: getComputedStyle(u, '::before').content };
      HT.kinView.current().reveal(Number(u.dataset.i), { smooth: false });
      return before;
    });
    await page.waitForTimeout(120);
    const uf2 = await page.evaluate(() => {
      const u = document.querySelector('.kv-fam .kv-p.is-unk');
      return { focus: u.classList.contains('is-focus'), outline: getComputedStyle(u).outlineStyle, ring: getComputedStyle(u, '::after').boxShadow };
    });
    check(!/is-open|is-closed/.test(uf.cls) && uf.handle === 'none', '이름 미상의 원에는 ▾ 손잡이가 없음', uf);
    check(uf2.focus && uf2.outline === 'none' && /0px 0px 0px 4px/.test(uf2.ring), '이름 미상의 키보드 초점: 카드 네모가 아니라 원 둘레(7 + 4)', uf2);
    await shot(page, 'kv-family-unknown-1x.png');
    check(!overlaps(f.items).length, '파 세계표 겹침 0');
    await page.keyboard.press('Escape');
  }

  /* ---------- 성씨 창 ---------- */
  await page.evaluate(() => {
    window.__openDetail('house:h-heuin');
    window.__houseCalls.length = 0;
  });
  await page.click('#detail .detail-head [data-uid^="surname:"]');
  await page.waitForTimeout(80);
  {
    const st = await page.evaluate(() => {
      const d = document.querySelector('#detail');
      return { text: d.innerText, bars: d.querySelectorAll('.kv-eras .kv-era').length, chips: d.querySelectorAll('.chips [data-uid^="house:"]').length, calls: window.__houseCalls.slice(), sel: HT.viewer.timeline.selected };
    });
    check(/^성씨/.test(st.text.trim()) && /가문 2 · 다스린 나라 3/.test(st.text) && st.bars === 3 && st.chips === 2, '성씨 창: 가문 2 · 다스린 나라 3 · 막대 · 가문 칩', st.text.slice(0, 80));
    const last = st.calls[st.calls.length - 1] || [];
    check(Array.isArray(last[0]) && ['h-heuin', 'h-dasom', 'h-solnae', 'h-solbig'].every(id => last[0].includes(id)) && last[1].dim && last[1].spans > 0, '성씨 조명: 그 성의 모든 가문과 아래 파를 같은 칠로', last);
    check(st.sel === null, '성씨 창은 고르지 않음(연표가 흐려지지 않음)');
    await shot(page, 'kv-surname-1x.png');
    await page.evaluate(() => document.querySelector('#detail [data-act="close"]').click());
    const off = await page.evaluate(() => window.__houseCalls[window.__houseCalls.length - 1]);
    check(off && off[0] === null, '창을 닫으면 조명을 끔(setHouse(null))', off);
  }

  /* ---------- ④ 계보 전용 인물 창 · 검색 ---------- */
  await page.evaluate(() => window.__openDetail('kv-check/f-sol-a'));
  {
    const st = await page.evaluate(() => {
      const d = document.querySelector('#detail');
      return { text: d.innerText, when: !!d.querySelector('.detail-body > .when'), fam: !!d.querySelector('[data-kin-fam]'), succ: !!d.querySelector('[data-kin-succ-person]'), sel: HT.viewer.timeline.selected };
    });
    check(!st.when && !/미상 ~|~ 미상/.test(st.text), '계보 전용 인물 창: 생몰을 적지 않았으면 생몰 줄 없음(비움 ≠ 미상)', st.text.slice(0, 120));
    check(/계보 전용/.test(st.text) && /솔 큰군파/.test(st.text) && /부모 · 조상: 부 미상/.test(st.text), '계보 전용 인물 창: 계보 전용 · 가문 길 · 부모 줄', st.text.slice(0, 200));
    check(st.fam && st.succ && st.sel === null, "'세계표에서 보기' · '승계표에서 보기' · 고르지 않음", st);
    await page.click('#detail [data-kin-fam]');
    await page.waitForSelector('.kv-fam .kv-p.is-focus');
    const fc = await page.evaluate(() => ({ name: document.querySelector('.kv-fam .kv-p.is-focus').textContent, title: document.querySelector('.kv-fam .kv-title h2').textContent }));
    check(fc.name === '한 가을' && /솔내 한씨 세계표/.test(fc.title), "계보 전용 인물 창의 '세계표에서 보기': 그 가문의 세계표를 열고 그 카드로", fc);
    await page.evaluate(() => HT.kinView.closeFamily());
    await page.click('#detail [data-kin-succ-person]');
    await page.waitForSelector('#detail .kv-succ');
    await page.waitForTimeout(80);
    const act = await page.evaluate(() => {
      const r = document.querySelector('#detail .kv-succ .kv-row.is-act');
      const b = document.querySelector('#detail .detail-body').getBoundingClientRect();
      const q = r ? r.getBoundingClientRect() : null;
      return { text: r ? r.innerText : '', inside: !!q && q.y >= b.y && q.y + q.height <= b.y + b.height };
    });
    check(/한 가을/.test(act.text) && act.inside, "'승계표에서 보기': 그 사람이 펼쳐지는 지도자 카드부터 펼쳐 그 줄로", act);
  }
  {
    const res = await page.evaluate(async () => {
      const input = document.querySelector('#searchInput');
      input.focus();
      input.value = '한 겨울';
      input.dispatchEvent(new Event('input', { bubbles: true }));
      await new Promise(r => setTimeout(r, 60));
      const b = [...document.querySelectorAll('#searchResults button')].find(x => /한 겨울/.test(x.innerText));
      return b ? { text: b.innerText, when: b.querySelector('.sr-when').textContent, hi: HT.viewer.timeline.highlight ? [...HT.viewer.timeline.highlight] : [] } : null;
    });
    check(res && /계보 전용 · 솔 큰군파/.test(res.text) && res.when === '' && !res.hi.includes('kv-check/f-sol-b'), "검색: 계보 전용 인물은 사람 결과 · 곁글 '계보 전용 · ○○파' · 해 칸 비움 · 연표 강조 없음", res);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(80);
    check(/한 겨울/.test(await page.evaluate(() => document.querySelector('#detail h2').innerText)), '검색 결과를 고르면 계보 전용 인물 창');
  }
  await context.close();

  /* ---------- ⑤ 견본(등불 연대기)의 가문 창 글 그대로 — 가문 19 · 파 7. kin-view.js를 빼고 연 창의 글이 차례대로 남는가 ---------- */
  {
    const lantern = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
    const texts = async noKin => {
      const o = await open([lantern], { noKin });
      const out = await o.page.evaluate(() => {
        const map = {};
        for (const h of __state.model.houses || []) {
          window.__openDetail(h.uid);
          map[h.uid] = document.querySelector('#detail').innerText.split('\n').map(l => l.trim()).filter(Boolean);
        }
        return map;
      });
      await o.context.close();
      return out;
    };
    const a = await texts(true);
    const b = await texts(false);
    const lost = [];
    for (const [uid, lines] of Object.entries(a)) {
      const nb = b[uid] || [];
      let j = 0;
      for (const l of lines) {
        while (j < nb.length && nb[j] !== l) j++;
        if (j >= nb.length) lost.push(`${uid}: ${l}`);
        j++;
      }
    }
    /* 견본 2.0.1의 가문 19(2.0.0의 17 + 물새씨 · 백탑 대단장가) — 2.0.0의 목록 밖 id(h-on · h-dan)는 온담씨 · 단목씨로 이어 새 가문이 생기지 않음 */
    check(Object.keys(a).length === 19 && lantern.houses.every(h => a[`house:${h.id}`]) && !lost.length, '견본(sample-lantern)의 가문 창 19(적은 가문 19 — 2.0.1에서 물새씨 · 백탑 대단장가를 더함): 계보 창 없이 연 글이 그대로 차례대로 남음(막대 · 단추만 더해짐)', { houses: Object.keys(a).length, lost: lost.slice(0, 6) });
  }

  /* ---------- ⑥ 가상 대가족 2만: 창 안 요소 ≤ 400 ---------- */
  {
    const big = bigPack(20000);
    const o = await open([big]);
    const p = o.page;
    await p.evaluate(() => {
      window.__long = [];
      try {
        new PerformanceObserver(l => l.getEntries().forEach(e => window.__long.push(Math.round(e.duration)))).observe({ type: 'longtask', buffered: false });
      } catch (e) {
        /* 없음 */
      }
    });
    const t0 = Date.now();
    /* 큰 뼈대는 나눠 지으며(4-6 · HT.kinSkeletonAsync) 그동안 '승계표를 짓고 있습니다' — 여는 같은 장면에 보여야 함(D1 결합) */
    const w0 = await p.evaluate(() => {
      window.__openDetail('kv-big/bign', { cell: 'succession' });
      const el = document.querySelector('#detail .kv-succ-wait');
      return { wait: !!el, text: el ? el.textContent : '', async: typeof HT.kinSkeletonAsync === 'function' };
    });
    await p.waitForSelector('#detail .kv-succ .kv-row');
    const tOpen = Date.now() - t0;
    if (w0.async) check(w0.wait && w0.text === '승계표를 짓고 있습니다' && !(await p.$('#detail .kv-succ-wait')), "대가족 2만 승계표: 큰 뼈대는 나눠 지으며 먼저 '승계표를 짓고 있습니다' → 다 지으면 목록", w0);
    const t1 = Date.now();
    await p.click('#detail [data-kin-level="A"]');
    await p.waitForTimeout(100);
    const tAll = Date.now() - t1;
    const doms = [];
    const st = await p.evaluate(() => {
      const rows = HT.viewer.state.kinSucc.rows();
      return { rows: rows.length, people: rows.filter(r => r.t === 'P').length, uniq: new Set(rows.filter(r => r.t === 'P').map(r => `${r.key}|${r.j}`)).size, leaders: rows.filter(r => r.t === 'L').length };
    });
    check(st.people === st.uniq && st.rows - (st.leaders - 1) <= 20000 + st.leaders, '대가족 2만 승계표 모두 펼침: 한 사람 한 번 · 줄 수 ≤ 사람 + 지도자', st);
    for (let k = 0; k < 12; k++) {
      await p.evaluate(f => {
        const b = document.querySelector('#detail .detail-body');
        b.scrollTop = (b.scrollHeight - b.clientHeight) * f;
      }, k / 11);
      await p.waitForTimeout(40);
      doms.push(await p.evaluate(() => document.querySelectorAll('#detail *').length));
    }
    check(Math.max(...doms) <= 400, '대가족 2만 승계표: 끝까지 밀어도 창 안 요소 ≤ 400', { max: Math.max(...doms) });
    await p.evaluate(() => window.__openDetail('house:h-big'));
    const t2 = Date.now();
    await p.click('#detail .detail-foot [data-kin-fam-house]');
    await p.waitForSelector('.kv-fam .kv-p', { timeout: 60000 });
    const tFam = Date.now() - t2;
    await p.click('.kv-fam [data-kv="all"]');
    await p.waitForTimeout(150);
    const fdoms = [];
    const v = await rect(p, '.kv-fam .kv-view');
    for (let k = 0; k < 8; k++) {
      await p.mouse.move(v.x + v.w / 2, v.y + v.h / 2);
      await p.mouse.down();
      await p.mouse.move(v.x + v.w / 2 - 300 * (k % 2 ? -1 : 1), v.y + v.h / 2 - 150, { steps: 6 });
      await p.mouse.up();
      await p.waitForTimeout(60);
      fdoms.push(await p.evaluate(() => document.querySelectorAll('.kv-fam *').length + 1));
    }
    const fs2 = await p.evaluate(() => HT.kinView.current().stats());
    check(fs2.visible === 20000 && Math.max(...fdoms) <= 400, '대가족 2만 세계표 모두 펼침: 끌어 밀어도 창 안 요소 ≤ 400', { max: Math.max(...fdoms), visible: fs2.visible });
    const items = await p.evaluate(() => {
      const win = document.querySelector('.kv-fam');
      const view = win.querySelector('.kv-view').getBoundingClientRect();
      return [...win.querySelectorAll('.kv-p, .kv-blabel, .kv-fpill, .kv-far, .kv-tag')].map(el => {
        const r = el.getBoundingClientRect();
        return { x: r.x, y: r.y, w: r.width, h: r.height, k: el.className + ':' + (el.dataset.i || '') };
      }).filter(r => r.x + r.w > view.x && r.x < view.x + view.width && r.y + r.h > view.y && r.y < view.y + view.height);
    });
    check(!overlaps(items).length, '대가족 세계표: 화면 안 카드 · 딱지 · 이름표 겹침 0', overlaps(items).slice(0, 4));
    const long = await p.evaluate(() => window.__long.slice());
    report.대가족 = { 승계표_열기_ms: tOpen, 모두_펼치기_ms: tAll, 세계표_열기_ms: tFam, 긴_작업_ms: long };
    await shot(p, 'kv-big-family-1x.png');
    /* 세계표의 나눠 짓기 창(D1 결합): 아직 짓지 않은 열쇠면 같은 장면에 '세계표를 짓고 있습니다' 창 → 다 지으면 진짜 창(뼈대가 없으면 걷힘) */
    if (w0.async) {
      const w1 = await p.evaluate(async () => {
        HT.kinView.closeFamily();
        const det = document.querySelector('#detail');
        const api = HT.kinView.family({ stage: det.parentElement, model: HT.viewer.state.model, key: 'kin:polity:kv-big/없는-나라', title: '없는 세계표', placeNear: det });
        const el = document.querySelector('.kv-fam.is-building');
        const shown = { win: !!el, text: el ? el.querySelector('.kv-building').textContent : '', building: !!(api && api.building), tree: el ? !!el.querySelector('[role="tree"]') : null };
        await new Promise(r => setTimeout(r, 40));
        return Object.assign(shown, { left: document.querySelectorAll('.kv-fam').length, current: !!HT.kinView.current() });
      });
      check(w1.win && w1.building && w1.text === '세계표를 짓고 있습니다' && w1.tree === false && !w1.left && !w1.current, "세계표: 짓는 동안 같은 자리에 '세계표를 짓고 있습니다' 창(트리 없음) → 다 지으면 바꿈 · 뼈대가 없으면 걷힘", w1);
    }
    await o.context.close();
  }

  /* ---------- ⑦ 메이커 미리 보기: 칩 ✏️ · 점선 빈 칩 → HT.maker.kin.editHead ---------- */
  {
    const o = await open([], { page: '/dlc-maker.html', draft: pack });
    const p = o.page;
    await p.waitForFunction(() => HT.maker && HT.maker.kin && HT.maker.kin.ready && HT.maker.kin.ready(), null, { timeout: 30000 }).catch(() => {});
    const ready = await p.evaluate(() => !!(HT.maker && HT.maker.kin && HT.maker.kin.ready && HT.maker.kin.ready()));
    report.메이커 = ready ? 'HT.maker.kin.ready() 참' : 'HT.maker.kin이 준비되지 않음 — 칩 ✏️ 검사 건너뜀';
    if (ready) {
      await p.evaluate(() => {
        window.__edits = [];
        HT.maker.kin.editHead = o => (window.__edits.push({ kind: o.kind, uid: o.uid, field: o.field, remove: o.remove }), Promise.resolve(false));
        window.__openDetail('kv-check/north', { cell: 'succession' });
      });
      const st = await p.evaluate(() => {
        const head = document.querySelector('#detail .detail-head .badges');
        return { pens: head.querySelectorAll('.kv-pen').length, empty: [...head.querySelectorAll('.kv-chip.is-empty')].map(b => b.textContent) };
      });
      check(st.pens >= 2 && st.empty.includes('＋ 민족') && st.empty.includes('＋ 꼬리표'), '메이커: 칩마다 ✏️ · 빈 값은 점선 칩(＋ 민족 · ＋ 꼬리표)', st);
      await p.click('#detail .detail-head .kv-chip.is-empty');
      await p.click('#detail .detail-head .kv-pen');
      const ed = await p.evaluate(() => window.__edits.slice());
      check(ed.length === 2 && ed.every(e => e.kind === 'polity' && e.uid === 'kv-check/north') && ed[0].field === 'people', '칩을 누르면 HT.maker.kin.editHead({ kind, uid, field })', ed);
    }
    await o.context.close();
  }

  /* ---------- ⑧ 목업 판과 나란히 (있을 때만 — 목업 판 그림의 창 자리를 잘라 왼쪽, 이 검사의 1배 그림을 오른쪽) ---------- */
  if (mockDir && fs.existsSync(mockDir)) {
    report.목업 = mockDir;
    const pairs = [
      ['d1-1-a.png', [1527, 72, 382, 992], 'kv-succession-1x.png', null, 'kv-compare-succession.png'],
      ['d1-8-a.png', [0, 0, 404, 590], 'kv-succession-8a-1x.png', [0, 0, 380, 590], 'kv-compare-8a.png'],
      ['d1-2-a.png', [640, 84, 780, 978], 'kv-family-1x.png', null, 'kv-compare-family.png'],
      ['d1-7-sur.png', [1527, 72, 382, 992], 'kv-surname-1x.png', null, 'kv-compare-surname.png'],
    ];
    const ctx2 = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
    const pg = await ctx2.newPage();
    for (const [mock, mclip, ours, oclip, out] of pairs) {
      const mp = path.join(mockDir, mock);
      const op = path.join(output, ours);
      if (!fs.existsSync(mp) || !fs.existsSync(op)) continue;
      const data = f => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
      const ourRect = oclip || (ours === 'kv-family-1x.png' ? famRect : detRect);
      const size = await pg.evaluate(async ([a, ac, b, bc]) => {
        const load = src => new Promise(r => { const im = new Image(); im.onload = () => r(im); im.src = src; });
        const [ia, ib] = await Promise.all([load(a), load(b)]);
        const W = ac[2] + bc[2] + 24;
        const H = Math.max(ac[3], bc[3]) + 28;
        const c = document.createElement('canvas');
        c.width = W;
        c.height = H;
        const g = c.getContext('2d');
        g.fillStyle = '#ffffff';
        g.fillRect(0, 0, W, H);
        g.drawImage(ia, ac[0], ac[1], ac[2], ac[3], 0, 28, ac[2], ac[3]);
        g.drawImage(ib, bc[0], bc[1], bc[2], bc[3], ac[2] + 24, 28, bc[2], bc[3]);
        g.fillStyle = '#333';
        g.font = '14px sans-serif';
        g.fillText('목업 판(왼쪽)', 4, 18);
        g.fillText('구현(오른쪽 · 가상 자료)', ac[2] + 28, 18);
        document.body.style.margin = '0';
        document.body.innerHTML = '';
        document.body.appendChild(c);
        return [W, H];
      }, [data(mp), mclip, data(op), ourRect]);
      const file = path.join(output, out);
      await pg.setViewportSize({ width: size[0], height: size[1] });
      await settleCapture(pg);
      await pg.screenshot({ path: file, clip: { x: 0, y: 0, width: size[0], height: size[1] } });
      report.그림.push(file);
    }
    await ctx2.close();
  }
} catch (err) {
  if (!err.skip) {
    report.오류.push(String(err && err.stack ? err.stack : err));
    throw err;
  }
  report.건너뜀 = err.message;
} finally {
  fs.writeFileSync(path.join(output, 'kin-view-check.json'), JSON.stringify(report, null, 2));
  await browser.close();
  server.close();
}
const errs = report.오류.filter(e => !/Service Worker|서비스 워커/.test(e));
console.log(JSON.stringify({ 검사: report.검사.length, 오류: errs.length, 도우미: report.도우미, 대가족: report.대가족, 메이커: report.메이커, 건너뜀: report.건너뜀 }, null, 1));
if (errs.length) {
  console.log(errs.slice(0, 5).join('\n'));
  process.exitCode = 1;
}
