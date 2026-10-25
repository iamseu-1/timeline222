// 리메이크 4단계 틀의 시트와 창 찍기 틀(가지 remake-4-ui · docs/계획-리메이크-4단계.md 과제 9 '걸음 1 — 틀의 시트와 창'):
// 실제 앱을 1920×1080으로 띄워 시트와 창 여덟(필터 시트 · 검색 결과 · 범례 · 차림표 · DLC 관리 · 승계표 · 단체 계보 · 문서 창)을
// 장면 열로 찍는다 — 차림표는 … 단추와 오른쪽 클릭 둘 · 승계표는 좁은 창과 넓은 창(걸음 7의 화면 아래 서랍) 둘. 걸음마다 '바꾼 창만 바뀌고 나머지는 바이트 같음'을 보고,
// 감독이 고른 다듬기 판의 그림(.claude/research/stage4-choose/out/polish-shots/<id>.png — git 밖 · 메인 작업 폴더)과 한 장에 나란히 놓는다.
// 다듬기 판은 가상 자료라 나란히 놓는 것은 꼴을 견주는 것이지 픽셀을 견주는 것이 아니다.
// 결과는 모두 prototype/results/remake4-sheets/(git 밖)에. 저장소는 remake4-shots의 것(prototype/results/remake4-shots/stores/ —
// 없으면 `node prototype/scripts/remake4-shots.mjs --stores`)을 읽기만 하고, 장면마다 사본을 띄운다.
// 사용(작업 폴더에서):
//   node prototype/scripts/remake4-sheet-shots.mjs --list                 장면 표
//   node prototype/scripts/remake4-sheet-shots.mjs --check                장면마다 자료가 맞는지(저장소 SQLite에서 바로) → 장면-자료.json · 표
//   node prototype/scripts/remake4-sheet-shots.mjs --tag=<이름> [--only=<장면>,…] [--app=<이름|실행본 경로>] [--overwrite]
//       장면마다 실제 앱(--capture-only · --capture-script · --memory-dir=<결과 폴더 안>)으로 shots/<이름>/<장면>.png.
//       대본은 d4-app-capture와 같은 걸음(command · search · tap · rightTap · select(cell: succession) · groupTree · slot doc).
//       찍기 전에 --check를 한 번 돌려 자료가 모자란 장면은 찍지 않는다.
//   node prototype/scripts/remake4-sheet-shots.mjs --tag=<이름> --compare=<태그> [--changed=<장면>,…] [--no-capture]
//       장면마다 바이트 같음/다름 표(다르면 다른 픽셀 수 · 범위) — 모든 장면이 같아야 끝 코드 0(결정적인지 · 걸음이 다른 창을 건드리지 않았는지).
//       --changed에 적은 장면은 그 걸음이 다시 그린 창이라 거꾸로 '달라야' 통과다(같으면 바꾼 것이 그림에 닿지 않은 것).
//   node prototype/scripts/remake4-sheet-shots.mjs --tag=<이름> --side [--no-capture] [--before=<태그>] [--crop=x,y,w,h]
//       side-by-side.mjs(HT_PLAYWRIGHT_ROOT)로 앱 그림과 다듬기 판 그림을 한 장에(side/<이름>/<장면>-나란히.png).
//       --before면 그 태그의 앱 그림과 이 태그의 앱 그림도 한 장에(side/<이름>/<장면>-전후.png — 4단계 전과 견줌).
//       --crop이면 1920×1080 전체 대신 그 자리만 1배로(승계표 좁은 창 = 상세 칸 1540,56,380,1024).
// 실행본은 prototype/scripts/dev.ps1 app-build(-Junction <이름>)로 지은 release. --app=<이름>은 remake4-shots --keep-app=<이름>으로 남긴
// prototype/results/remake4-shots/app/<이름>/을 쓴다(4단계 전 틀의 앱 = before-ui). 앱은 늘 --memory-dir=<결과 폴더 안>으로 띄운다(판정 R50).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const root = path.resolve(prototype, '..');
const results = path.join(prototype, 'results', 'remake4-sheets');
const stores = path.join(prototype, 'results', 'remake4-shots', 'stores');
const apps = path.join(prototype, 'results', 'remake4-shots', 'app');
/** 다듬기 판의 1배 그림(감독 고름 — git 밖 · 메인 작업 폴더의 연구 폴더 · 읽기만). 작업 폴더 안에 같은 길이 있으면 그것을 먼저. */
const POLISH = [path.join(root, '.claude', 'research', 'stage4-choose', 'out', 'polish-shots'), path.resolve(root, '..', '..', '..', '.claude', 'research', 'stage4-choose', 'out', 'polish-shots')]
  .find(p => fs.existsSync(p)) || path.join(root, '.claude', 'research', 'stage4-choose', 'out', 'polish-shots');

const args = Object.fromEntries(process.argv.slice(2).map(a => { const m = a.match(/^--([^=]+)(?:=(.*))?$/); return m ? [m[1], m[2] ?? ''] : ['', a]; }));
const known = new Set(['list', 'check', 'tag', 'only', 'app', 'overwrite', 'compare', 'no-capture', 'side', 'changed', 'before', 'crop']);
for (const k of Object.keys(args)) if (!known.has(k)) die(`모르는 인자 --${k} (${[...known].join(' · ')})`);

function die(msg) {
  console.error(`remake4-sheet-shots: ${msg}`);
  process.exit(2);
}

const L = 'lantern-chronicle/';
/** 장면: 저장소 · 보는 해 범위 · 대본 걸음(d4-app-capture의 대본 그대로) · 다듬기 판 그림 id · 자료 확인(need). */
const SCENES = [
  { id: 'filter', store: 'lantern', from: 760, to: 960, steps: [{ do: 'command', name: 'filter' }], polish: 'shs-filter', note: '필터 시트(☰ — 맨 위 줄 아래)' },
  { id: 'search', store: 'lantern', from: 760, to: 960, steps: [{ do: 'search', text: '설원' }], polish: 'shs-search', need: { search: '설원' }, note: '검색 결과(검색 칸 아래 · 객체 · 칸 · 사건 · 인물 묶음)' },
  { id: 'legend', store: 'lantern', from: 760, to: 960, steps: [{ do: 'command', name: 'legend' }], polish: 'shs-legend', note: '범례' },
  // … 단추: 맨 위 줄 오른쪽 끝(오른쪽 여백 16 · 단추 36 — dock.dart)의 가운데를 누른다.
  { id: 'menu', store: 'lantern', from: 760, to: 960, steps: [{ do: 'tap', x: 1886, y: 30 }], polish: 'sm-menu', note: '차림표(… 단추)' },
  // 오른쪽 클릭: 설원 제국 띠(760 ~ 960 · 문화권 모두 펼침 — 설령 빙원권 첫 줄)의 '설 왕조' 단 위.
  { id: 'context', store: 'lantern', from: 760, to: 960, steps: [{ do: 'rightTap', x: 1000, y: 790 }], polish: 'sm-menu', need: { band: `${L}p-empire` }, note: '오른쪽 클릭 차림표(설원 제국 띠 위)' },
  { id: 'dlc', store: 'lantern-sphere', from: 760, to: 960, steps: [{ do: 'command', name: 'dlc' }], polish: 'sm-dlc', need: { packs: 2 }, note: 'DLC 관리(등불 + f4-sphere — DLC 둘)' },
  { id: 'succession', store: 'lantern', from: 760, to: 960, steps: [{ do: 'select', uid: `${L}p-empire`, kind: 'period', cell: 'succession' }], polish: 'sh-succ-narrow', need: { succession: `${L}p-empire` }, note: '승계표 좁은 창(상세 칸 — 설원 제국 · 위에서 아래로)' },
  // 걸음 7: 승계표 넓은 창(화면 아래 서랍 · 가로로 이어짐) — 대본의 slot 걸음으로 슬롯 succWide에 정권 uid(좁은 창 '넓게'와 같은 길의 서랍 쪽).
  { id: 'succ-wide', store: 'lantern', from: 760, to: 960, steps: [{ do: 'slot', name: 'succWide', value: `${L}p-empire` }], polish: 'sh-succ-wide', need: { succession: `${L}p-empire` }, note: '승계표 넓은 창(화면 아래 서랍 — 설원 제국 · 가로로)' },
  { id: 'group-tree', store: 'lantern', from: 1380, to: 1660, steps: [{ do: 'groupTree', uid: `${L}p-union`, group: `${L}g-pearl` }], polish: 'sht-gtree', need: { tree: `${L}p-union`, group: `${L}g-pearl` }, note: '단체 계보(하연 연합 왕국 · 진주파 고름)' },
  // 걸음 9: 문서 창은 다듬기 판 sht-doc과 같은 '넓게'(연표를 덮는 창)로 — 앱의 처음 값은 나란히(연표 옆 760 칸)라 대본 slot 걸음으로 docSide를 끈 뒤 연다.
  // 나란히는 덧 장면 doc-side(걸음 8까지의 doc 장면과 같은 길).
  { id: 'doc', store: 'lantern', from: 760, to: 960, steps: [{ do: 'slot', name: 'docSide', value: false }, { do: 'slot', name: 'doc', value: `${L}p-lantern` }], polish: 'sht-doc', need: { doc: `${L}p-lantern` }, note: '문서 창 넓게(등불 왕국 — 받침 카드 · 목차 · 각주 · 딸린 항목)' },
  // 덧 장면(extra — --only에 이름을 적을 때만): 필터 시트의 '관점' 고르는 칸(발 왼쪽 — 걸음 2의 1920×1080 자리 120,570)을 눌러 편 목록.
  { id: 'filter-choice', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'command', name: 'filter' }, { do: 'wait', ms: 600 }, { do: 'tap', x: 120, y: 570 }], polish: 'shs-filter', note: '필터 시트 — 관점 고르는 칸의 목록을 편 것(덧 장면)' },
  // 걸음 3의 덧 장면: '온'(가문 · 칸 · 인물 · 하위 문서 — 상자 넷이 한 화면에) · '880'(날짜 이동 줄 + 그때에 걸친 정권) ·
  // 차림표 줄에 마우스를 올린 것(먹 4 칠 + 테 먹 45 — '기간 재기' 줄 자리 1700,206은 걸음 3의 1920×1080 차림표).
  { id: 'search-mix', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'search', text: '온' }], polish: 'shs-search', note: "검색 결과 — '온'(객체 · 칸 · 인물 · 문서 상자 · 덧 장면)" },
  { id: 'search-date', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'search', text: '880' }], polish: 'shs-search', note: "검색 결과 — '880'(맨 위 날짜 이동 줄 · 덧 장면)" },
  { id: 'menu-hover', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'tap', x: 1886, y: 30 }, { do: 'wait', ms: 600 }, { do: 'hover', x: 1700, y: 206 }], polish: 'sm-menu', note: '차림표 — 줄에 마우스를 올린 것(덧 장면)' },
  // 걸음 5의 덧 장면: DLC 관리 창을 띄운 채 대본의 'dlc' 걸음으로 f4-sphere를 끄고(엔진 remove_pack — 보관함) 일이 끝나길 기다린 것 ·
  // 끈 뒤 다시 켠 것(엔진 add_pack — 켠 DLC 상자로 돌아옴). 실패한 조회 · 대본 오류가 0이어야 찍힌다.
  { id: 'dlc-off', extra: true, store: 'lantern-sphere', from: 760, to: 960, steps: [{ do: 'command', name: 'dlc' }, { do: 'wait', ms: 600 }, { do: 'dlc', off: 'f4-sphere' }, { do: 'until', what: 'idle', ms: 120000 }, { do: 'wait', ms: 800 }], polish: 'sm-dlc', need: { packs: 2 }, note: 'DLC 관리 — f4-sphere를 끈 뒤(보관함 · 덧 장면)' },
  // 걸음 6의 덧 장면: 칸 창의 '승계표에서 보기'와 같은 길(슬롯 kinFocus → 그 카드를 펼친 채 데려감)로 끝눈 황제(leader:9 — 후손 6)를 편 것 ·
  // 바닥 '모두 펼치기'와 같은 일(대본 kin 걸음 — 단추가 실제 창 키 962 밖이라 누르기 대신)을 한 것(사람 띠 · 건너뛰기 줄 · 파 꼬리표).
  { id: 'succ-open', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'slot', name: 'kinFocus', value: { uid: `${L}p-empire`, cell: 'leader:9' } }, { do: 'select', uid: `${L}p-empire`, kind: 'period', cell: 'succession' }], polish: 'sh-succ-narrow', need: { succession: `${L}p-empire` }, note: '승계표 좁은 창 — 끝눈 황제를 펼친 것(사람 띠 · 덧 장면)' },
  { id: 'succ-all', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'select', uid: `${L}p-empire`, kind: 'period', cell: 'succession' }, { do: 'wait', ms: 600 }, { do: 'kin', all: true }, { do: 'wait', ms: 600 }], polish: 'sh-succ-narrow', need: { succession: `${L}p-empire` }, note: '승계표 좁은 창 — 모두 펼치기(덧 장면)' },
  // 걸음 7의 덧 장면: 나라 상세를 연 채 넓은 창 — 좁은 창 '넓게'를 누른 뒤와 같은 모습(상세 칸 · 배율 알약이 서랍 위로 비킴 — stageBottomInset).
  { id: 'succ-wide-detail', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'select', uid: `${L}p-empire`, kind: 'period' }, { do: 'wait', ms: 600 }, { do: 'slot', name: 'succWide', value: `${L}p-empire` }], polish: 'sh-succ-wide', need: { succession: `${L}p-empire` }, note: '승계표 넓은 창 — 나라 상세를 연 채(상세 칸이 서랍 위로 · 덧 장면)' },
  // 표가 서랍보다 넓은 정권(등불 왕국 — 지도자 21 · 가장 짧은 재위 6년이라 1년 4px · 가로로 끎)과 뒤 나라 넷(한참 뒤의 부흥 셋 — 둘째 줄부터).
  { id: 'succ-wide-long', extra: true, store: 'lantern', from: 600, to: 800, steps: [{ do: 'slot', name: 'succWide', value: `${L}p-lantern` }], polish: 'sh-succ-wide', need: { succession: `${L}p-lantern` }, note: '승계표 넓은 창 — 등불 왕국(가로로 끎 · 뒤 나라 넷 · 덧 장면)' },
  // 걸음 8의 덧 장면: 단체 계보 창을 열었다 닫은 뒤의 연표(대본 groupTree 걸음 — uid 없이 부르면 닫음). 창이 남긴 것(조명 · 고른 단체 표시 · 비킴)이 없어
  // 4단계 전 앱(--app=before-ui)으로 찍은 같은 장면과 바이트 같아야 한다 — 연 때 그 나라 띠를 창 위로 데려온 세로 자리는 두 앱이 같은 셈이라 같음.
  { id: 'group-tree-closed', extra: true, store: 'lantern', from: 1380, to: 1660, steps: [{ do: 'groupTree', uid: `${L}p-union`, group: `${L}g-pearl` }, { do: 'wait', ms: 800 }, { do: 'groupTree' }, { do: 'wait', ms: 800 }], polish: 'sht-gtree', need: { tree: `${L}p-union`, group: `${L}g-pearl` }, note: '단체 계보 — 열었다 닫은 뒤의 연표(덧 장면 · 4단계 전과 바이트 같음)' },
  // 걸음 9의 덧 장면: 문서 창 나란히(앱의 처음 값 — 연표 옆 760 칸 · 딸린 항목이 본문 밑) · 문서 대문(갈래 상자 + 흰 종이 카드) ·
  // 하위 문서(등불 왕국/아홉 불씨 — 경로 줄 · 문서 그림).
  { id: 'doc-side', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'slot', name: 'doc', value: `${L}p-lantern` }], polish: 'sht-doc', need: { doc: `${L}p-lantern` }, note: '문서 창 나란히(연표 옆 760 칸 · 덧 장면)' },
  { id: 'doc-front', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'slot', name: 'docSide', value: false }, { do: 'slot', name: 'doc', value: '@대문' }], polish: 'sht-doc', note: '문서 대문 넓게(갈래 상자 + 흰 종이 카드 · 덧 장면)' },
  { id: 'doc-sub', extra: true, store: 'lantern', from: 760, to: 960, steps: [{ do: 'slot', name: 'docSide', value: false }, { do: 'slot', name: 'doc', value: `${L}p-lantern//아홉 불씨` }], polish: 'sht-doc', need: { doc: `${L}p-lantern` }, note: '하위 문서 넓게(등불 왕국/아홉 불씨 — 경로 · 그림 · 덧 장면)' },
  { id: 'dlc-toggle', extra: true, store: 'lantern-sphere', from: 760, to: 960, steps: [{ do: 'command', name: 'dlc' }, { do: 'wait', ms: 600 }, { do: 'dlc', off: 'f4-sphere' }, { do: 'until', what: 'idle', ms: 120000 }, { do: 'wait', ms: 800 }, { do: 'shot', name: '끈 뒤' }, { do: 'dlc', on: 'f4-sphere' }, { do: 'until', what: 'idle', ms: 120000 }, { do: 'wait', ms: 800 }], polish: 'sm-dlc', need: { packs: 2 }, note: 'DLC 관리 — f4-sphere를 끄고 다시 켠 뒤(덧 장면 · 끈 뒤 그림은 _run/dlc-toggle/out)' },
];

/** 장면의 다른 이름(계획 문서 · 걸음 지시가 쓰는 이름) — 오른쪽 클릭 차림표 = context · 승계표 좁은 창 = succession · 단체 계보 = group-tree. */
const ALIAS = { ctxmenu: 'context', 'succ-narrow': 'succession', gtree: 'group-tree' };
const pick = list => {
  const only = (args.only || '').split(',').map(s => s.trim()).filter(Boolean).map(n => ALIAS[n] || n);
  for (const n of only) if (!list.some(x => x.id === n)) die(`모르는 장면 ${n} (${list.map(x => x.id).join(' · ')})`);
  // 덧 장면(extra)은 --only에 적을 때만 — 기본 장면 열의 견줌 · 나란히에 끼지 않는다.
  return list.filter(x => (only.length ? only.includes(x.id) : !x.extra));
};
const storeDir = name => path.join(stores, name);
const storeDb = name => path.join(storeDir(name), 'archive.db');
const sha12 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 12);

/** 해 → 1970년 기준 분(remake4-shots.mjs · compare-shots.mjs의 minute와 같은 셈). */
function minute(y) {
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}

// ---- 장면 자료 확인 ----

async function sqlite() {
  const realWarn = process.emitWarning; // node:sqlite(실험 기능)의 경고 한 줄을 끈다 — build-check.mjs와 같게
  process.emitWarning = (w, ...rest) => (String(w).includes('SQLite') ? undefined : realWarn.call(process, w, ...rest));
  return (await import('node:sqlite')).DatabaseSync;
}

/** 장면 하나의 자료가 그 창을 채우는지 — 지도자 여럿 + kin 승계 · x_groupTree 나무 · 문서 · DLC 수 · 검색 낱말. [ok, 글] */
function checkScene(DatabaseSync, s) {
  const db = storeDb(s.store);
  if (!fs.existsSync(db)) return [false, `저장소 없음 — node prototype/scripts/remake4-shots.mjs --stores`];
  const d = new DatabaseSync(db, { readOnly: true });
  try {
    const entity = uid => { const r = d.prepare('SELECT json FROM entities WHERE uid=?').get(uid); return r ? JSON.parse(r.json) : null; };
    const need = s.need || {}, notes = [];
    let ok = true;
    const fail = msg => { ok = false; notes.push(`없음: ${msg}`); };
    if (need.band) {
      const e = entity(need.band);
      if (!e) fail(need.band); else notes.push(`띠 ${e.name} ${e.start} ~ ${e.end ?? ''}`);
    }
    if (need.succession) {
      const e = entity(need.succession);
      const leaders = e?.leaders?.length || 0, lineage = e?.x_lineage ? Object.values(e.x_lineage) : [];
      const kins = [...new Set(lineage.map(l => l?.kinAt?.[0]).filter(Boolean))];
      const missing = kins.filter(k => !entity(k));
      if (leaders < 2) fail(`지도자 여럿(${leaders})`);
      if (!kins.length) fail('kin 승계(x_lineage의 kinAt)');
      if (missing.length) fail(`뼈대 기록 ${missing.join(' · ')}`);
      notes.push(`${e?.name ?? need.succession} 지도자 ${leaders} · 승계 줄 ${lineage.length} · 뼈대 ${kins.join(' · ')}`);
    }
    if (need.tree) {
      const tree = entity(need.tree)?.x_groupTree, nodes = tree?.nodes || [];
      if (nodes.length < 2) fail(`x_groupTree 나무(마디 ${nodes.length})`);
      if (need.group && !nodes.some(n => n.uid === need.group)) fail(`고를 단체 ${need.group}`);
      notes.push(`나무 마디 ${nodes.length} · 줄 ${tree?.rows ?? 0} · 이음 ${(tree?.edges || []).length} · 고름 ${nodes.find(n => n.uid === need.group)?.name ?? '-'}`);
    }
    if (need.doc) {
      const e = entity(need.doc), wiki = String(e?.wiki || '');
      const heads = (wiki.match(/^==.*==\s*$/gm) || []).length, notesN = (wiki.match(/\[\*/g) || []).length, subs = (e?.x_docs || []).length;
      if (!wiki) fail('문서 본문(wiki)');
      if (!entity(`doc:${need.doc}`) && !wiki) fail(`doc:${need.doc}`);
      notes.push(`${e?.name ?? need.doc} 본문 ${wiki.length}자 · 제목 ${heads} · 각주 ${notesN} · 딸린 문서 ${subs}`);
    }
    if (need.packs) {
      const packs = d.prepare('SELECT id, name FROM packs ORDER BY id').all().map(r => r.name);
      if (packs.length < need.packs) fail(`DLC ${need.packs}(있음 ${packs.length})`);
      notes.push(`DLC ${packs.length} — ${packs.join(' · ')}`);
    }
    if (need.search) {
      const n = Number(Object.values(d.prepare("SELECT count(*) n FROM entities WHERE json LIKE ?").get(`%"name":"%${need.search}%`))[0]);
      if (!n) fail(`'${need.search}'이 든 이름`);
      notes.push(`'${need.search}'이 든 이름 ${n}`);
    }
    if (!notes.length) notes.push(`저장소 ${s.store}`);
    return [ok, notes.join(' / ')];
  } finally {
    d.close();
  }
}

async function check(scenes, { quiet = false } = {}) {
  const DatabaseSync = await sqlite();
  const out = {};
  for (const s of scenes) {
    const [ok, note] = checkScene(DatabaseSync, s);
    out[s.id] = { ok, note, store: s.store, sha: fs.existsSync(storeDb(s.store)) ? sha12(storeDb(s.store)) : null };
  }
  fs.mkdirSync(results, { recursive: true });
  // --only로 몇 장면만 보았으면 표의 나머지 장면은 그대로 둔다.
  const file = path.join(results, '장면-자료.json');
  const before = (() => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return {}; } })();
  fs.writeFileSync(file, JSON.stringify(Object.fromEntries(SCENES.filter(s => out[s.id] || before[s.id]).map(s => [s.id, out[s.id] || before[s.id]])), null, 1) + '\n');
  if (!quiet) {
    console.log('| 장면 | 저장소 | 자료 | 확인 |');
    console.log('| --- | --- | --- | --- |');
    for (const s of scenes) console.log(`| ${s.id} | ${s.store} | ${out[s.id].note} | ${out[s.id].ok ? '맞음' : '모자람'} |`);
    console.log(`저장: ${path.relative(root, path.join(results, '장면-자료.json'))}`);
  }
  return out;
}

// ---- 찍기 ----

function exePath() {
  const a = args.app || '';
  if (!a) return path.join(prototype, 'app', 'build', 'windows', 'x64', 'runner', 'Release', 'archive_prototype.exe');
  if (a.endsWith('.exe')) return path.resolve(a);
  return path.join(apps, a, 'archive_prototype.exe');
}

async function capture(tag, scenes) {
  const exe = exePath();
  if (!fs.existsSync(exe)) die(`실행본이 없습니다: ${exe} — powershell -File prototype/scripts/dev.ps1 app-build -Junction <이름> -Flutter <flutter.bat>`);
  const facts = await check(scenes, { quiet: true });
  const folder = path.join(results, 'shots', tag);
  fs.mkdirSync(folder, { recursive: true });
  const appSo = path.join(path.dirname(exe), 'data', 'app.so');
  const app = { exe: path.relative(root, exe), code: fs.existsSync(appSo) ? sha12(appSo) : '?', engine: sha12(path.join(path.dirname(exe), 'archive_engine.dll')) };
  const infoFile = path.join(folder, '_실행본.json');
  const info = (() => { try { return JSON.parse(fs.readFileSync(infoFile, 'utf8')); } catch { return {}; } })();
  let bad = 0;
  for (const s of scenes) {
    const png = path.join(folder, `${s.id}.png`);
    if (fs.existsSync(png) && !('overwrite' in args)) { console.error(`${s.id}: 이미 찍음(덮어쓰지 않음 — --overwrite) ${path.relative(root, png)}`); bad++; continue; }
    if (!facts[s.id].ok) { console.error(`${s.id}: 자료가 모자라 찍지 않음 — ${facts[s.id].note}`); bad++; continue; }
    const run = path.join(folder, '_run', s.id);
    fs.rmSync(run, { recursive: true, force: true });
    fs.mkdirSync(run, { recursive: true });
    // 저장소 사본(앱이 열며 쓰는 것이 있어도 지은 저장소는 그대로) — 옆 DLC/도
    const store = path.join(run, 'store');
    fs.cpSync(storeDir(s.store), store, { recursive: true });
    // 기억 사본: 문화권 모두 펼침 · 보던 기간 = 장면의 범위(remake4-shots와 같은 꼴)
    const from = minute(s.from), to = minute(s.to);
    const memory = path.join(run, 'memory');
    fs.mkdirSync(memory, { recursive: true });
    fs.writeFileSync(path.join(memory, 'ui-state.json'), JSON.stringify({ version: 1, view: { start: from, end: to }, parts: { viewState: { foldedSpheres: [] } } }));
    // 대본: 첫 장면이 가라앉은 뒤 창을 여는 걸음 → 가라앉힘 → 한 장('대본') · 그 뒤 측정기가 2초 더 기다려 '화면-1배.png'를 뜬다(둘이 같으면 그사이 멎어 있었다)
    const script = path.join(run, 'script.json');
    fs.writeFileSync(script, JSON.stringify([{ do: 'wait', ms: 800 }, ...s.steps, { do: 'wait', ms: 1200 }, { do: 'shot', name: '대본' }]));
    const out = path.join(run, 'out');
    const pass = [`--db=${path.join(store, 'archive.db')}`, `--measure=${out}`, '--exit=yes', '--offline=yes', '--capture-only=yes', '--capture-size=1920x1080',
      `--capture-script=${script}`, `--memory-dir=${path.join(run, 'memory-dir')}`, `--capture-memory=${memory}`, `--from=${from}`, `--to=${to}`, '--capture-scroll=0'];
    const t0 = Date.now();
    const r = spawnSync(exe, pass, { cwd: path.dirname(exe), encoding: 'utf8', timeout: 180000 });
    fs.writeFileSync(path.join(run, '실행.log'), (r.stdout || '') + (r.stderr || '') + (r.error?.stack || ''));
    const failed = path.join(out, '측정-실패.txt');
    const shot = path.join(out, '화면-1배.png');
    if (r.error || r.status !== 0 || fs.existsSync(failed) || !fs.existsSync(shot)) {
      console.error(`${s.id}: 실제 앱 실행 실패(${r.error?.message || r.status}) — ${path.relative(root, run)}`);
      bad++;
      continue;
    }
    const log = JSON.parse(fs.readFileSync(path.join(out, '검증-기록.json'), 'utf8'));
    const start = JSON.parse(fs.readFileSync(path.join(out, '시작-장면.json'), 'utf8'));
    const errors = log.steps.filter(x => x.error), asks = log.ask_failures.length + (start.ask_failures?.length || 0);
    const state = log.steps.find(x => x.shot) || {};
    const still = fs.existsSync(path.join(out, '대본.png')) && fs.readFileSync(path.join(out, '대본.png')).equals(fs.readFileSync(shot));
    fs.copyFileSync(shot, png);
    fs.rmSync(store, { recursive: true, force: true }); // 사본은 지움 — 기록 · 그림은 남김
    info[s.id] = { ...app, store: s.store, from: s.from, to: s.to, steps: s.steps, data: facts[s.id].note, selection: state.selection ?? null, detailOpen: state.detailOpen ?? null,
      groupTree: state.groupTree ?? null, doc: state.slots?.doc ?? null, askFailures: asks, scriptErrors: errors.map(x => x.error), still };
    const warn = [asks && `실패한 조회 ${asks}`, errors.length && `대본 오류 ${errors.map(x => x.error).join(' · ')}`, !still && '대본 그림과 1배 그림이 다름(그사이 그림이 움직임)'].filter(Boolean).join(' · ');
    console.log(`${s.id}: 찍음 ${path.relative(root, png)} · ${((Date.now() - t0) / 1000).toFixed(1)}초${warn ? ' · ' + warn : ''}`);
    if (asks || errors.length) bad++;
  }
  fs.writeFileSync(infoFile, JSON.stringify(info, null, 1) + '\n');
  return bad;
}

// ---- 견주기(remake4-shots.mjs의 decodePng · pixelDiff와 같은 셈) ----

/** PNG(8비트 · RGB/RGBA · 비월 없음 — Flutter가 뜨는 꼴)를 RGBA로 푼다. 다른 꼴이면 null. */
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) return null;
  let pos = 8, width = 0, height = 0, type = 0, depth = 0, interlace = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), kind = buf.toString('latin1', pos + 4, pos + 8), body = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === 'IHDR') { width = body.readUInt32BE(0); height = body.readUInt32BE(4); depth = body[8]; type = body[9]; interlace = body[12]; }
    else if (kind === 'IDAT') idat.push(body);
    else if (kind === 'IEND') break;
    pos += 12 + len;
  }
  const bpp = type === 6 ? 4 : type === 2 ? 3 : 0;
  if (!bpp || depth !== 8 || interlace) return null;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * bpp, out = Buffer.alloc(width * height * 4), prev = Buffer.alloc(stride), line = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = src[i];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      line[i] = v & 255;
    }
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      out[o] = line[x * bpp]; out[o + 1] = line[x * bpp + 1]; out[o + 2] = line[x * bpp + 2]; out[o + 3] = bpp === 4 ? line[x * bpp + 3] : 255;
    }
    line.copy(prev);
  }
  return { width, height, data: out };
}

/** 두 그림의 다른 픽셀 수와 범위(x0,y0,x1,y1). 크기가 다르면 size. */
function pixelDiff(a, b) {
  const A = decodePng(a), B = decodePng(b);
  if (!A || !B) return { note: '풀 수 없는 PNG 꼴' };
  if (A.width !== B.width || A.height !== B.height) return { size: [[A.width, A.height], [B.width, B.height]] };
  let n = 0, x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let i = 0; i < A.data.length; i += 4) {
    if (A.data.readUInt32BE(i) === B.data.readUInt32BE(i)) continue;
    n++;
    const p = i / 4, x = p % A.width, y = (p - x) / A.width;
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  return { pixels: n, box: n ? [x0, y0, x1, y1] : null };
}

function compare(tag, other, scenes) {
  const rows = [];
  // 그 걸음이 다시 그린 창의 장면 — 거꾸로 달라야 통과.
  const changed = new Set((args.changed || '').split(',').map(x => x.trim()).filter(Boolean).map(n => ALIAS[n] || n));
  for (const id of changed) if (!SCENES.some(s => s.id === id)) die(`--changed의 모르는 장면 ${id}`);
  let bad = 0;
  for (const s of scenes) {
    const a = path.join(results, 'shots', tag, `${s.id}.png`), b = path.join(results, 'shots', other, `${s.id}.png`);
    const want = changed.has(s.id) ? ' (다시 그린 창 — 달라야 함)' : '';
    // 이 걸음이 새로 낸 장면(--changed에 적었고 견줄 태그에는 그림이 없음 — 걸음 7의 succ-wide)은 통과.
    if (want && fs.existsSync(a) && !fs.existsSync(b)) { rows.push({ id: s.id, state: '새 장면(견줄 그림 없음 — 통과)' }); continue; }
    if (!fs.existsSync(a) || !fs.existsSync(b)) { rows.push({ id: s.id, state: '그림 없음' + want }); bad++; continue; }
    const A = fs.readFileSync(a), B = fs.readFileSync(b);
    if (A.equals(B)) { rows.push({ id: s.id, state: '같음' + want }); if (want) bad++; continue; }
    rows.push({ id: s.id, state: '다름' + want, ...pixelDiff(A, B) });
    if (!want) bad++;
  }
  console.log(`\n견줌: ${tag} ↔ ${other} · ${changed.size ? `${[...changed].join(' · ')}만 달라야 하고 나머지는 같아야 함` : '모든 장면이 같아야 함'}`);
  console.log('| 장면 | 바이트 | 다른 픽셀 | 범위(x0,y0,x1,y1) |');
  console.log('| --- | --- | --- | --- |');
  for (const r of rows) console.log(`| ${r.id} | ${r.state} | ${r.pixels ?? (r.size ? '크기 다름' : r.note ?? '')} | ${r.box ? r.box.join(',') : ''} |`);
  const file = path.join(results, 'shots', tag, `견줌-${other}.json`);
  fs.writeFileSync(file, JSON.stringify({ tag, other, changed: [...changed], rows }, null, 1) + '\n');
  console.log(`${bad ? `어긋남 ${bad}` : (changed.size ? '바라던 대로' : '모두 같음')} · 저장: ${path.relative(root, file)}`);
  return bad;
}

// ---- 다듬기 판과 나란히 ----

function side(tag, scenes) {
  if (!process.env.HT_PLAYWRIGHT_ROOT) console.log('알림: HT_PLAYWRIGHT_ROOT가 없습니다 — 저장소의 node_modules에서 playwright를 찾습니다.');
  const out = path.join(results, 'side', tag);
  fs.mkdirSync(out, { recursive: true });
  const crop = args.crop || '0,0,1920,1080';
  if (!/^\d+,\d+,\d+,\d+$/.test(crop)) die('--crop=x,y,w,h');
  const pairUp = (id, a, b, labels, file) => {
    const r = spawnSync(process.execPath, [path.join(here, 'side-by-side.mjs'), '--a', a, '--b', b, '--crop', crop, '--labels', labels, '--out', file], { encoding: 'utf8', timeout: 120000 });
    if (r.status !== 0) { console.error(`${id}: 나란히 뜨기 실패 ${(r.stderr || '').trim().split('\n').slice(-4).join('\n')}`); return 1; }
    console.log(`${id}: 나란히 ${path.relative(root, file)}`);
    return 0;
  };
  let bad = 0;
  for (const s of scenes) {
    const app = path.join(results, 'shots', tag, `${s.id}.png`), polish = path.join(POLISH, `${s.polish}.png`);
    if (!fs.existsSync(app)) { console.error(`${s.id}: 앱 그림이 없습니다 — 먼저 --tag=${tag}`); bad++; continue; }
    if (!fs.existsSync(polish)) { console.error(`${s.id}: 다듬기 판 그림이 없습니다 — ${polish}`); bad++; continue; }
    bad += pairUp(s.id, app, polish, `연표 앱(${tag} · ${s.id}),다듬기 판(${s.polish} — 가상 자료 · 꼴만 견줌)`, path.join(out, `${s.id}-나란히.png`));
    // --before: 그 태그의 앱 그림(4단계 전 따위)과 이 태그의 앱 그림을 한 장에.
    if (args.before) {
      const was = path.join(results, 'shots', args.before, `${s.id}.png`);
      if (!fs.existsSync(was)) { console.error(`${s.id}: 견줄 그림이 없습니다 — ${path.relative(root, was)}`); bad++; continue; }
      bad += pairUp(s.id, was, app, `연표 앱(${args.before} · ${s.id}),연표 앱(${tag} · ${s.id})`, path.join(out, `${s.id}-전후.png`));
    }
  }
  return bad;
}

// ---- 차례 ----

let bad = 0;
const scenes = pick(SCENES);
if ('list' in args) {
  console.log('| 장면 | 저장소 | 해 범위 | 대본 | 다듬기 판 | 무엇 |');
  console.log('| --- | --- | --- | --- | --- | --- |');
  for (const s of SCENES) console.log(`| ${s.id} | ${s.store} | ${s.from} ~ ${s.to} | ${s.steps.map(x => x.do).join(' · ')} | ${s.polish} | ${s.note} |`);
}
if ('check' in args) {
  const facts = await check(scenes);
  if (Object.values(facts).some(f => !f.ok)) bad++;
}
if ('tag' in args && !args.tag) die('--tag=<이름>');
// --tag면 찍는다 — 견주기만(--no-capture) · 나란히(--side — 그 태그의 앱 그림을 씀)는 찍지 않는다.
if (args.tag && !('no-capture' in args) && !('side' in args)) bad += await capture(args.tag, scenes);
if ('compare' in args) {
  if (!args.tag || !args.compare) die('--tag=<이름> --compare=<태그>');
  bad += compare(args.tag, args.compare, scenes);
}
if ('side' in args) {
  if (!args.tag) die('--side는 --tag=<앱 그림의 태그>와 함께');
  bad += side(args.tag, scenes);
}
if (!Object.keys(args).some(k => ['list', 'check', 'tag', 'compare', 'side'].includes(k))) {
  console.log('할 일을 적으세요: --list · --check · --tag=<이름> · --compare=<태그> · --side (머리말 참고)');
  process.exit(2);
}
process.exit(bad ? 1 : 0);
