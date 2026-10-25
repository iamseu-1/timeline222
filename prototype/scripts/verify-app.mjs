// 실제 앱 전역 점검: 실행본(scripts/dev.ps1 app-build)을 장면마다 띄워 **눌러 보며 찍고**, 걸음마다의 상태와 실패한 조회를 모은다.
// 부품은 조회가 실패하면 그 묶음만 조용히 비우므로 단위 검사 · 계약 검사가 통과해도 실제 앱에서는 빌 수 있다(2026-09-22) —
// 그래서 기능을 '됐다'고 적기 전에 이 도구의 그림을 눈으로 보고 `실패한 조회 0건 · 기대 어긋남 0건`을 확인한다.
// 사용: node prototype/scripts/verify-app.mjs [--pack lantern|east-asia] [--out prototype/results/verify-app/<이름>] [--db <저장소>] [--only 장면,장면]
//       lantern(기본) = 견본 등불 연대기(samples/sample-lantern.json — 따로 세계)만으로 지은 저장소. 기본 자리 data/lantern/archive.db — 짓는 법:
//         node prototype/scripts/warm-calendar.mjs --file=<표>  →  engine/target/release/archive-tool.exe build data/lantern/archive.db ../samples/sample-lantern.json --calendar=<표>(시드와 같은 Rust 짓기 — 옛 export-layout → import-layout 길은 달력 표 없는 저장소를 지어 DLC를 넣고 빼지 못한다)
//       east-asia는 동아시아 기본팩으로 새로 지은 --db를 반드시 준다. 그 팩에 없는 자료 종류는 요약의 untested에 까닭을 남긴다.
//       재는 동안 새 앱의 창이 장면마다 잠깐 뜬다(가리지 말 것). 걸음의 뜻은 app/lib/measure/verify_script.dart 머리말.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const pack = option('--pack', 'lantern');
if (!['lantern', 'east-asia'].includes(pack)) { console.error('알 수 없는 팩: ' + pack); process.exit(2); }
if (pack === 'east-asia' && !option('--db')) { console.error('동아시아 검사는 --db로 동아시아 저장소를 지정하세요.'); process.exit(2); }
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 13);
const out = path.resolve(option('--out', path.join(prototype, 'results', 'verify-app', stamp)));
const db = path.resolve(option('--db', path.join(prototype, 'data', 'lantern', 'archive.db')));
const only = (option('--only', '') || '').split(',').filter(Boolean);
if (!fs.existsSync(db)) { console.error('저장소가 없습니다: ' + db); process.exit(1); }
if (fs.existsSync(path.join(out, '요약.json'))) { console.error('기존 결과를 덮어쓰지 않습니다: ' + out); process.exit(1); }
fs.mkdirSync(out, { recursive: true });

/** 지금 연표의 해 좌표 → 1970년 기준 분(내보내기와 같은 투영). */
function minute(y) {
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}

// 등불 연대기(samples/sample-lantern.json)의 실제 정규화 UID. 화면 좌표로 누르는 걸음은 두지 않는다(옛 월흔해 그림에서 읽은 좌표를 쓰지 않음 — untested).
const LANTERN = 'lantern-chronicle/p-lantern'; // 등불 왕국 — 지도자 칸 21 · 도읍 3 · 문서 · 대범위 둘의 상위 정권
const EMPIRE = 'lantern-chronicle/p-empire'; // 설원 제국 — 지도자 칸 10 · 도읍 2 · 내각
const shot = (name, expect) => ({ do: 'shot', name, ...(expect ? { expect } : {}) });
const wait = ms => ({ do: 'wait', ms });

// 장면: 보는 기간(해)과 걸음. 788 ~ 1031 = 설원 제국 시대(네 트랙 모두 정권이 있는 구간).
const LANTERN_SCENES = [
  { name: '조명과-메아리', years: [788, 1031], steps: [
    { do: 'filters', json: { show: { spotEcho: true } } },
    { do: 'select', uid: EMPIRE, cell: 'leader:2' }, wait(1500), shot('1-지도자-칸-이-시기의-사건', { detailOpen: true, askFailures: 0 }),
    { do: 'select', uid: 'lantern-chronicle/f-galmuri', kind: 'figure' }, wait(1500), shot('2-인물-같은-시기-타국', { detailOpen: true }),
    { do: 'select', uid: 'lantern-chronicle/d-seol', kind: 'dynasty' }, wait(1500), shot('3-왕조-조명', { detailOpen: true }),
  ] },
  { name: '같은-해-보기', years: [788, 1031], steps: [
    { do: 'command', name: 'year' }, wait(1500), shot('1-같은-해-보기', { yearOpen: true, askFailures: 0 }),
    { do: 'tap', x: 600, y: 1040 }, wait(1200), shot('2-다른-자리를-누름', { yearOpen: true }),
    { do: 'command', name: 'close' }, wait(600), shot('3-닫음', { yearOpen: false }),
  ] },
  { name: '검색', years: [788, 1031], steps: [
    { do: 'search', text: '갈무리' }, wait(1200), shot('1-이름-검색'),
    { do: 'activate' }, wait(2500), shot('2-고르면-창과-이동', { detailOpen: true }),
    { do: 'clear' }, { do: 'search', text: '설 왕조' }, wait(1200), shot('3-왕조-이름-검색'),
    { do: 'search', text: '1031' }, wait(1200), shot('4-연도-검색'),
  ] },
  { name: '필터와-밀도', years: [788, 1031], steps: [
    { do: 'command', name: 'filter' }, wait(900), shot('1-필터-시트'),
    { do: 'command', name: 'filter' },
    { do: 'filters', json: { categories: { '0': false } } }, wait(1500), shot('2-첫-분류를-끔'),
    { do: 'filters', json: { categories: {}, density: 2, birdShape: 'c' } }, wait(1500), shot('3-조감-띠와-선만'),
    { do: 'filters', json: { density: 0, birdShape: 'a', show: { leaders: false, cabinets: false } } }, wait(1500), shot('4-지도자와-내각을-끔'),
  ] },
  { name: '대범위와-소속', years: [412, 788], steps: [ // 아홉 불씨 할거(등불 왕국이 품은 대범위)
    { do: 'select', uid: 'lantern-chronicle/s-nine', kind: 'scope' }, wait(1500), shot('1-대범위-창', { detailOpen: true }),
    { do: 'slot', name: 'scopes', value: { 'lantern-chronicle/s-nine': true } }, wait(1800), shot('2-모아-보기를-켬', { 'openScopes.0': 'lantern-chronicle/s-nine' }),
    { do: 'command', name: 'scope', uid: 'lantern-chronicle/s-nine' }, wait(1800), shot('3-메뉴로-끔', { 'openScopes.length': 0 }),
  ] },
  { name: '문서와-도구', years: [300, 788], steps: [
    { do: 'select', uid: LANTERN }, wait(1000), { do: 'command', name: 'wiki', uid: LANTERN }, wait(1500), shot('1-문서-창', { askFailures: 0 }),
    { do: 'command', name: 'close' }, { do: 'clear' },
    { do: 'command', name: 'legend' }, wait(900), shot('2-범례'),
    { do: 'command', name: 'legend' }, { do: 'command', name: 'table' }, wait(1800), shot('3-표-보기'),
  ] },
  { name: '접기와-돋보기', years: [-1500, 1750], steps: [
    shot('1-전체'),
    { do: 'command', name: 'foldAll' }, wait(1500), shot('2-모두-접음', { 'slots.foldAll': true }),
    { do: 'command', name: 'foldAll' }, wait(1500),
    { do: 'mag', value: 0.5 }, wait(2500), shot('3-돋보기-50'),
  ] },
  // ── 12물결(통합)에서 이은 것들 ─────────────────────────────────────────────
  { name: '도읍-노선도', years: [300, 788], steps: [
    // 상세 창의 `🚇`와 왼쪽 칸의 노선 표시가 같은 슬롯을 쓴다 — 슬롯에 실어 카드가 실제로 서는지 본다(등불 왕국 — 도읍 셋).
    { do: 'slot', name: 'metro', value: LANTERN }, wait(1200), shot('1-노선도-카드', { askFailures: 0 }),
    { do: 'command', name: 'close' }, wait(600), shot('2-Esc로-닫음', { 'slots.metro': null }),
  ] },
  { name: '움직임-계측', years: [788, 1031], steps: [
    { do: 'command', name: 'motion' }, wait(1200), shot('1-계측-창', { 'slots.motion': true }),
    { do: 'command', name: 'motion' }, wait(800), shot('2-닫음', { 'slots.motion': false }),
  ] },
  { name: '날짜-칸-표시', years: [788, 1031], steps: [
    shot('1-날짜-칸-그대로', { 'marks.axis.0': true }),
    // 간지 · 연호 · 도읍 · 시대 구분을 차례로 끈다 — 날짜 칸의 높이가 그만큼 줄어든다(360ms).
    { do: 'filters', json: { show: { ganji: false } } }, wait(1200), shot('2-간지-끔', { 'marks.axis.0': false }),
    { do: 'filters', json: { show: { eras: false, capitals: false, epochs: false } } }, wait(1500), shot('3-넷-다-끔', { 'marks.axis.3': false }),
    { do: 'filters', json: { show: { ganji: true, eras: true, capitals: true, epochs: true } } }, wait(1500), shot('4-도로-켬', { 'marks.axis.3': true }),
  ] },
  { name: '표기와-관점', years: [788, 1031], steps: [
    { do: 'filters', json: { show: { houses: true } } }, wait(1500), shot('1-가문-줄', { 'marks.houses': true }),
    { do: 'filters', json: { leaderLabel: 'temple', leaderOrdinal: true } }, wait(1500), shot('2-묘호와-대수', { 'marks.leaderLabel': 'temple' }),
    { do: 'filters', json: { showAlt: false } }, wait(1500), shot('3-이설-끔', { 'marks.alt': false }),
    // 관점: 엔진의 `lens_names`를 실제로 묻는다 — 실패하면 askFailures에 남는다.
    { do: 'filters', json: { lens: 'local', showAlt: true, leaderLabel: 'auto', leaderOrdinal: false, show: { houses: false } } }, wait(1800),
    shot('4-관점-나라마다-제-이름', { 'marks.lens': 'local', askFailures: 0 }),
    { do: 'filters', json: { lens: '' } }, wait(1200), shot('5-관점-끔', { 'marks.lens': '' }),
  ] },
  { name: 'SVG-저장', years: [788, 1031], steps: [
    // 대화 상자를 여는 데까지만 본다(실제로 적으면 내려받기 폴더를 더럽힌다).
    { do: 'command', name: 'image' }, wait(1500), shot('1-이미지-인쇄-대화상자', { askFailures: 0 }),
    { do: 'command', name: 'close' }, wait(600), shot('2-닫음'),
  ] },
];

// 동아시아의 실제 정규화 UID(packs/east-asia/korea-1.js·korea-2.js).
// 지도자는 독립 인물이 아니라 기간의 칸이다. 등불 연대기의 UID · 없는 왕조/대범위 UID를 재사용하지 않는다.
const JOSEON = 'east-asia-base/korea-pyymqsk';
const HUNMIN = 'east-asia-base/korea-1ti0d7u';
const EAST_ASIA_SCENES = [
  { name: '상세-선택', years: [1392, 1500], steps: [
    { do: 'select', uid: JOSEON, kind: 'period' }, wait(1200),
    shot('1-조선-상세', { detailOpen: true, 'selection.uid': JOSEON, askFailures: 0 }),
    { do: 'select', uid: JOSEON, cell: 'leader:3', kind: 'period' }, wait(1200),
    shot('2-세종-지도자-칸', { detailOpen: true, 'selection.cell': 'leader:3', askFailures: 0 }),
    { do: 'select', uid: HUNMIN, kind: 'event' }, wait(1200),
    shot('3-훈민정음-기간-사건', { detailOpen: true, 'selection.uid': HUNMIN, askFailures: 0 }),
    { do: 'command', name: 'close' }, wait(600), shot('4-상세-닫음', { detailOpen: false }),
  ] },
  { name: '조명과-메아리', years: [1392, 1500], steps: [
    { do: 'filters', json: { show: { spotEcho: true } } },
    { do: 'select', uid: JOSEON, cell: 'leader:3', kind: 'period' }, wait(1500),
    shot('1-지도자-시기의-사건', { detailOpen: true, 'selection.cell': 'leader:3', askFailures: 0 }),
    { do: 'select', uid: HUNMIN, kind: 'event' }, wait(1500),
    shot('2-사건-같은-시기-타국', { detailOpen: true, 'selection.uid': HUNMIN, askFailures: 0 }),
  ] },
  { name: '같은-해-보기', years: [1392, 1500], steps: [
    { do: 'command', name: 'year', at: minute(1443) }, wait(1500), shot('1-1443년', { yearOpen: true, askFailures: 0 }),
    { do: 'command', name: 'year', at: minute(1592) }, wait(1200), shot('2-1592년', { yearOpen: true, askFailures: 0 }),
    { do: 'command', name: 'close' }, wait(600), shot('3-닫음', { yearOpen: false }),
  ] },
  { name: '검색', years: [1392, 1500], steps: [
    { do: 'search', text: '훈민정음 창제' }, wait(1200), shot('1-사건-검색', { askFailures: 0 }),
    { do: 'activate' }, wait(2500), shot('2-고르면-창과-이동', { detailOpen: true, 'selection.uid': HUNMIN, askFailures: 0 }),
    { do: 'clear' }, { do: 'search', text: '조선' }, wait(1200), shot('3-나라-검색', { askFailures: 0 }),
    { do: 'search', text: '1443' }, wait(1200), shot('4-연도-검색', { askFailures: 0 }),
  ] },
  { name: '도구', years: [1392, 1500], steps: [
    { do: 'command', name: 'legend' }, wait(900), shot('1-범례', { 'slots.legend': true, askFailures: 0 }),
    { do: 'command', name: 'legend' }, wait(600), shot('2-범례-닫음', { 'slots.legend': false }),
    { do: 'command', name: 'table' }, wait(1800), shot('3-표-보기', { askFailures: 0 }),
  ] },
  { name: '자료집', years: [1392, 1500], steps: [
    { do: 'command', name: 'dlc' }, wait(1200), shot('1-동아시아-자료집', { askFailures: 0 }),
    { do: 'command', name: 'close' }, wait(600), shot('2-자료집-닫음', { askFailures: 0 }),
  ] },
  // 자료 UID에 기대지 않는 공통 조작은 같은 걸음과 같은 기대를 쓴다.
  ...LANTERN_SCENES.filter(scene => ['필터와-밀도', '접기와-돋보기', '움직임-계측', '날짜-칸-표시', '표기와-관점', 'SVG-저장'].includes(scene.name))
    .map(scene => ({ ...scene, years: scene.name === '접기와-돋보기' ? [-2333, 2027] : [1392, 1500] })),
];
const SCENES = pack === 'east-asia' ? EAST_ASIA_SCENES : LANTERN_SCENES;
const unknown = only.filter(name => !SCENES.some(scene => scene.name === name));
if (unknown.length) { console.error('이 팩에 없는 장면: ' + unknown.join(', ')); process.exit(2); }
const untested = pack === 'east-asia' ? [
  { feature: '독립 인물·왕조·대범위·대범위 가지 접기', reason: '동아시아 기본팩에 해당 항목이 없다. 지도자 칸과 나라 상세는 별도로 검증한다.' },
  { feature: '문서 본문·문서 그림·도읍 노선도', reason: '동아시아 기본팩에 문서 본문·그림·도읍 칸이 없다. 해당 견본의 실제 앱 검사로 확인해야 한다.' },
  { feature: 'D2 원어·글꼴 팩, D4 집합 보기, D5 단체·집권 단·실권 단·주제 렌즈', reason: '동아시아 기본팩에 해당 확장 자료가 없다. 동아시아 결과를 네 갈래 견본 검사로 세지 않는다.' },
  { feature: '화면 좌표로 항목 누르기', reason: '고정 화면 좌표를 두지 않는다. 동아시아 선택은 실제 앱의 선택·검색 명령으로 검증하며 포인터 맞춤은 별도 검사한다.' },
] : [
  { feature: '화면 좌표로 항목 누르기(지도자 칸 · 사건 이름 · 왕조 칸 · 오른쪽 클릭 메뉴) · 대범위 가지 칸 누르기', reason: '옛 견본(월흔해) 그림에서 읽은 좌표는 등불 연대기 배치와 맞지 않는다. 선택은 실제 앱의 선택 · 검색 명령으로 검증하며 포인터 맞춤은 등불 연대기 그림에서 좌표를 다시 읽어 더할 때까지 별도 검사한다.' },
];

const pick = (state, key) => key.split('.').reduce((v, k) => (v == null ? v : (k === 'length' ? v.length : v[k])), state);
const summary = { pack, db, untested, scenes: [] };
for (const scene of SCENES) {
  if (only.length && !only.includes(scene.name)) continue;
  const folder = path.join(out, scene.name);
  fs.rmSync(folder, { recursive: true, force: true });
  const scriptFile = path.join(out, `_${scene.name}.json`);
  fs.writeFileSync(scriptFile, JSON.stringify(scene.steps));
  const run = spawnSync(process.execPath, [path.join(prototype, 'scripts', 'measure.mjs'), '--db', db, '--out', folder, '--from', String(minute(scene.years[0])), '--to', String(minute(scene.years[1])),
    '--capture-only', '--capture-size', '1920x1080', '--capture-script', scriptFile], { encoding: 'utf8' });
  const record = path.join(folder, '검증-기록.json');
  if (run.status !== 0 || !fs.existsSync(record)) { summary.scenes.push({ name: scene.name, error: (run.error?.message || run.stderr || run.stdout || '검증 기록이 없습니다.').slice(-400) }); console.log(`✗ ${scene.name} — 실행 실패`); continue; }
  let log;
  try {
    log = JSON.parse(fs.readFileSync(record, 'utf8'));
    if (!Array.isArray(log.steps) || !Array.isArray(log.ask_failures)) throw new Error('steps 또는 ask_failures 기록이 없습니다.');
  } catch (error) {
    summary.scenes.push({ name: scene.name, error: '검증 기록을 읽을 수 없습니다: ' + error.message });
    console.log('✗ ' + scene.name + ' — 검증 기록 오류');
    continue;
  }
  const expects = Object.fromEntries(scene.steps.filter(s => s.do === 'shot' && s.expect).map(s => [s.name, s.expect]));
  const misses = [];
  for (const expected of scene.steps.filter(step => step.do === 'shot')) {
    if (!log.steps.some(step => step.shot === expected.name)) misses.push('기대 그림의 상태 기록이 없습니다: ' + expected.name);
    if (!fs.existsSync(path.join(folder, expected.name + '.png'))) misses.push('기대 그림 파일이 없습니다: ' + expected.name);
  }
  for (const step of log.steps) {
    if (step.error) misses.push(`${step.step}: ${step.error}`);
    for (const [key, want] of Object.entries(expects[step.shot] || {})) {
      const got = pick(step, key);
      const ok = typeof want === 'string' && want.startsWith('^') ? new RegExp(want).test(String(got ?? '')) : got === want;
      if (!ok) misses.push(`${step.shot}: ${key} = ${JSON.stringify(got)} (기대 ${JSON.stringify(want)})`);
    }
  }
  summary.scenes.push({ name: scene.name, shots: log.steps.filter(s => s.shot).map(s => s.shot), ask_failures: log.ask_failures, misses });
  console.log(`${misses.length || log.ask_failures.length ? '✗' : '✓'} ${scene.name} — 그림 ${log.steps.filter(s => s.shot).length} · 실패한 조회 ${log.ask_failures.length} · 기대 어긋남 ${misses.length}`);
  for (const m of misses) console.log('    · ' + m);
  for (const f of log.ask_failures.slice(0, 5)) console.log('    ! ' + String(f).slice(0, 240));
}
const bad = summary.scenes.filter(scene => scene.error || scene.misses?.length || scene.ask_failures?.length).length;
summary.result = bad || !summary.scenes.length ? '실패' : '통과';
summary.failed_scenes = bad;
summary.ask_failures = summary.scenes.reduce((n, scene) => n + (scene.ask_failures?.length || 0), 0);
summary.misses = summary.scenes.reduce((n, scene) => n + (scene.misses?.length || 0), 0);
fs.writeFileSync(path.join(out, '요약.json'), JSON.stringify(summary, null, 1));
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
fs.writeFileSync(path.join(out, 'index.html'), `<!doctype html><html lang="ko"><meta charset="utf-8"><title>실제 앱 점검</title>
<style>body{font:14px/1.5 system-ui;margin:24px;background:#f6f1e8;color:#2d261a}h2{margin-top:32px}img{max-width:100%;border:1px solid #d8cdb8;display:block;margin:6px 0 18px}.bad{color:#a33}</style>
<h1>실제 앱 점검 — ${esc(pack)} · ${esc(path.basename(out))}</h1>
${untested.length ? `<h2>이 자료로 검증하지 못한 것</h2><ul>${untested.map(item => `<li>${esc(item.feature)}: ${esc(item.reason)}</li>`).join('')}</ul>` : ''}
${summary.scenes.map(s => `<h2>${esc(s.name)} ${s.error ? '<span class="bad">실행 실패</span>' : `— 실패한 조회 ${s.ask_failures.length} · 기대 어긋남 ${s.misses.length}`}</h2>
${(s.misses || []).map(m => `<div class="bad">· ${esc(m)}</div>`).join('')}${(s.ask_failures || []).map(f => `<div class="bad">! ${esc(f)}</div>`).join('')}
${(s.shots || []).map(n => `<div>${esc(n)}</div><img src="${encodeURI(s.name + '/' + n + '.png')}">`).join('')}`).join('\n')}</html>`);
console.log(`저장: ${path.join(out, 'index.html')} · 장면 ${summary.scenes.length} · 문제 있는 장면 ${bad}`);

process.exitCode = bad || !summary.scenes.length ? 1 : 0;
