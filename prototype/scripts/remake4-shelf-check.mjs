// 리메이크 4단계 선반 갈래 걸음 3 · 4 — 선반 변형(shelf:<그릇 uid> · 변형 갈래 6) 검사. 감독 결정 2026-10-25 '선반 = 엔진 변형 길'.
//   (remake-4 가지의 remake4-shelf-calc.mjs는 길을 고르던 셈이고, 이것은 내보내기가 실제로 낸 선반 변형을 정답지에서 읽어 기대와 견주는 검사다.)
// 하는 일:
//   ① 정답지(prototype/results/oracle/<자료>/upto-lens.json)를 읽어 선반 변형이 있는 자료마다 숨은 띠 · 선반 줄(그릇 묶음의 줄 차례대로 그 줄의 띠) ·
//      빠지는 줄(after −2) · 가림 수를 찍고 기대와 견준다 —
//        lantern+shelf-chain  선반 줄 [등불 왕국 · 하연 부흥국 · 하연 공화국] [아랫물국] [윗물국] · 숨음 = 하연 총관부 · 하연 연합 왕국 · 검은물 의병 · 남강 임시정부
//        lantern+shelf-flat   그릇 줄 7 → 5 · 숨음 = 검은물 의병 · 남강 임시정부
//        f4-federation-scope  그릇 줄 12 → 5 · 남는 것 = 쇠여울 · 흰여울 · 붉은바위 · 범바위 · 잿골
//        nest 넷(east-asia+nest · east-asia+nest@f4 · nest-f4 · nest-f4@f4)  shelf:nest-scene/jp-era(혼자 켜면 구성 9)
//      선반 변형은 이 일곱 자료에만 생겨야 한다.
//      (걸음 4) 숨긴 구성원 꼬리표(구역 59)도 선반 변형마다 본다 — 숨은 띠마다 하나(수 · 띠가 같음) · 그 변형에만(variant = 선반 열쇠) · a = 5부터 이어진 차례 ·
//      b = 숨은 수 · ref = text2 = 띠 uid · 이름 · 색 · 바깥 끝(start · end)이 그 띠와 같음 · row = row2 = 그 그릇 묶음의 끝 줄(폴더 발) · lod = 같은 변형 테(23)의 단계.
//        lantern+shelf-chain의 차례(a)  하연 연합 왕국 · 하연 총관부 · 남강 임시정부 · 검은물 의병(중요도가 없어 기간 길이 차례)
//      (검토 고침) 숨은 구성원(바탕 문화 조각은 빼고 셈)의 사건은 모두 이사 −1 · 선반 변형의 새 줄은 모두 그릇 묶음 안(트랙 끝 '그 밖' 같은 새 줄 없음) ·
//      그 변형의 '그 밖' 줄 이름 없음 · 바탕 문화 조각은 승계국을 따라감(lantern+shelf-chain — 숨는 구성원 밑 −1 · 다시 지은 줄로 간 구성원 밑은 그 줄).
//      자체 점검 알림(variants.notes)은 실패 — 다만 웹 연표의 자동 글줄 문턱(트랙 줄 6 이하면 글줄 2 · 앱은 쓰지 않음)을 선반이 넘으면 그 알림은 알리기만 한다.
//   ② 걸음 1에서 떠 둔 기준(prototype/results/oracle-before-shelf — git 밖 · 고치기 전 정답지 사본)과 자료마다 파일을 견준다(머리 `$oracle`은 뺌 — 규칙 지문이 바뀜).
//      - 모든 자료: variants 모듈 앞자리의 파일(norm · prep · rows · pre-/upto-<tracks ~ power>)은 바이트 같아야 한다.
//      - 선반 변형이 없는 자료: 모든 파일이 바이트 같아야 한다.
//      - 미리 있던 자료 가운데 선반 변형이 생기는 nest 넷: **끝에 덧붙은 것만** 달라야 한다(배열은 앞자리가 같고 뒤에만 붙음 · 객체는 열쇠가 같음 —
//        기존 칸 · 항목 · 변형이 한 바이트도 바뀌지 않음. 줄 이름의 chipOn(변형 열쇠 → 딱지)만 뒤에 열쇠가 붙어도 덧붙음으로 본다).
//      - 걸음 1의 새 시험 자료 셋(선반을 보려고 만든 자료): 달라진 파일 수만 찍는다(렌즈 항목이 변형 항목 뒤에 붙어 자리가 밀리는 등 — 견주지 않음).
//      - 입력이 바뀐 자료(머리 `$oracle.sources`가 다름 — 검토 고침에서 lantern+shelf-chain에 바탕 문화를 더함): 견주지 않고 알린다.
//      합칠 때(remake-4-lay 등 배치를 바꾸는 갈래와 함께) 이 기준은 낡는다 — 합친 판의 선반 없는 정답지를 다시 떠서 --before로 준다.
// 사용(작업 폴더에서 — 먼저 node prototype/scripts/layout-oracle.mjs):
//   node prototype/scripts/remake4-shelf-check.mjs [--only=<자료>,…] [--before=<폴더>]   (기준 폴더가 없으면 ②를 건너뛰고 알림 · 어긋나면 끝 코드 1)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MODULES } from './export/base.mjs';
import { lodOf } from './export/rails.mjs';

/** 선반이 제 줄에 남기는 구성원 수(지금 연표 G_SEOGO.shelfKeep) — 꼬리표(구역 59)의 a는 숨은 첫째가 이 값. */
const SHELF_KEEP = 5;

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const oracleDir = path.join(prototype, 'results', 'oracle');
const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));
const beforeDir = args.before ? path.resolve(args.before) : path.join(prototype, 'results', 'oracle-before-shelf');
const list = JSON.parse(fs.readFileSync(path.join(prototype, 'fixtures', 'oracle', 'list.json'), 'utf8'));
const only = (args.only || '').split(',').map(s => s.trim()).filter(Boolean);

const L = uid => `lantern-chronicle/${uid}`;
/** 기대(선반 변형 열쇠 → 기대). rows: 선반 줄마다의 띠 uid(줄 안 차례 그대로) · hidden: 숨는 띠 uid · scopeRows: 그 그릇의 scope 변형 줄 수 → 선반 줄 수 · keepPrefix: 남는 띠 이름의 앞머리 */
const NEST = { key: 'shelf:nest-scene/jp-era', strict: true }; // strict: 미리 있던 자료 — 끝에 덧붙은 것만 달라야 함(②)
const EXPECT = {
  'lantern+shelf-chain': { key: 'shelf:shelf-chain/shelf-chain', rows: [[L('p-lantern'), L('p-revival'), L('p-republic')], [L('p-lower')], [L('p-upper')]], hidden: [L('p-prefecture'), L('p-union'), L('p-blackwater'), L('p-namgang')],
    tags: [L('p-union'), L('p-prefecture'), L('p-namgang'), L('p-blackwater')], // tags: 숨긴 구성원 꼬리표(구역 59)의 a 차례
    hiddenEvents: 13, // 숨은 넷의 사건(연합 왕국 8 · 의병 2 · 임시정부 2 · 총관부 1) — 모두 이사 −1
    // 바탕 문화 조각 → 따라갈 승계국(그 변형에서의 줄 · null이면 −1). 갈래물 갈대 문화는 아랫물국 · 윗물국 밑 두 조각 — 기본의 둘째 조각(#u3)은 −1, 변형의 둘째 조각은 새 띠로 윗물국 줄에
    under: [['shelf-chain/c-blackwater-kiln', null], ['shelf-chain/c-upper-mound', L('p-upper')], ['shelf-chain/c-fork-reed', L('p-lower')], ['shelf-chain/c-fork-reed#u3', null]],
    underFresh: [['shelf-chain/c-fork-reed', L('p-upper')]] },
  'lantern+shelf-flat': { key: 'shelf:shelf-flat/shelf-flat', scopeRows: [7, 5], hidden: [L('p-blackwater'), L('p-namgang')], hiddenEvents: 4 },
  'f4-federation-scope': { key: 'shelf:f4-federation-scope/s-fed', scopeRows: [12, 5], keepPrefix: ['쇠여울', '흰여울', '붉은바위', '범바위', '잿골'] },
  'east-asia+nest': NEST,
  'east-asia+nest@f4': NEST,
  'nest-f4': NEST,
  'nest-f4@f4': NEST,
};

let failed = 0;
const fail = msg => { failed++; console.log(`  ✗ ${msg}`); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sortU = l => l.slice().sort();

/** 정답지 파일 글에서 머리 `{"$oracle":{…},`를 떼어 낸 몸(글) — 머리 객체의 끝을 따옴표 안을 건너며 괄호 짝으로 찾는다. 머리가 없으면 글 그대로. */
function bodyText(text) {
  const head = '{"$oracle":';
  if (!text.startsWith(head)) return text;
  let i = head.length, depth = 0, str = false;
  for (; i < text.length; i++) {
    const c = text[i];
    if (str) { if (c === '\\') i++; else if (c === '"') str = false; continue; }
    if (c === '"') str = true;
    else if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') { depth--; if (depth === 0) { i++; break; } }
  }
  return text[i] === ',' ? '{' + text.slice(i + 1) : '{' + text.slice(i);
}

/** after가 before에 '끝에 덧붙인 것'뿐인가 — 배열은 before가 앞자리(칸마다 같은 셈을 거듭) · 객체는 열쇠가 같고 칸마다 같은 셈 · 그 밖은 같은 값.
    돌려주는 값: 어긋난 첫 자리(글) · 없으면 null. */
function extensionOf(before, after, at = '') {
  if (Array.isArray(before)) {
    if (!Array.isArray(after)) return `${at || '(뿌리)'}: 배열이 아님`;
    if (after.length < before.length) return `${at}: 길이 ${before.length} → ${after.length}(줄어듦)`;
    for (let i = 0; i < before.length; i++) { const d = extensionOf(before[i], after[i], `${at}[${i}]`); if (d) return d; }
    return null;
  }
  if (before && typeof before === 'object') {
    if (!after || typeof after !== 'object' || Array.isArray(after)) return `${at || '(뿌리)'}: 객체가 아님`;
    const kb = Object.keys(before), ka = Object.keys(after);
    const tail = at.endsWith('.chipOn') && same(kb, ka.slice(0, kb.length)); // chipOn(변형 열쇠 → 딱지)은 새 변형의 열쇠가 뒤에 붙어도 덧붙음
    if (!same(kb, ka) && !tail) return `${at || '(뿌리)'}: 열쇠 ${kb.length} → ${ka.length}(${ka.filter(k => !kb.includes(k)).concat(kb.filter(k => !ka.includes(k)).map(k => '−' + k)).slice(0, 4).join(' · ')})`;
    for (const k of kb) { const d = extensionOf(before[k], after[k], `${at}.${k}`); if (d) return d; }
    return null;
  }
  return before === after ? null : `${at}: ${JSON.stringify(before)} → ${JSON.stringify(after)}`;
}

/** 덧붙은 것의 수(배열마다 늘어난 칸 수의 합 — 뿌리 아래 이름별). */
function grownOf(before, after, at = '', out = new Map()) {
  if (Array.isArray(before)) {
    if (after.length > before.length) out.set(at, (out.get(at) || 0) + after.length - before.length);
    for (let i = 0; i < before.length; i++) grownOf(before[i], after[i], at, out);
  } else if (before && typeof before === 'object') {
    for (const k of Object.keys(before)) grownOf(before[k], after[k], at ? `${at}.${k}` : k, out);
  }
  return out;
}

/** 띠 look의 바탕 문화 비트(export/bands.mjs의 L.under) — 바탕 문화 조각은 구성원이 아니라 승계국 줄 밑에 깔리는 것이라 숨은 구성원 · 선반 줄에서 뺀다. */
const UNDER = 1 << 14;

/** 선반 변형 하나를 읽는다 — 숨은 띠 · 선반 줄 · 빠지는 줄 · 그 그릇 scope 변형의 줄 수. */
function readShelf(o, v) {
  const nameOf = uid => (o.periods.find(p => p.uid === uid) || {}).name || uid;
  const under = new Set(o.periods.filter(p => (p.look & UNDER) !== 0).map(p => p.uid));
  const hidden = v.moves.filter(m => m.kind === 1 && m.row === -1 && !under.has(m.ref)).map(m => m.ref);
  const gone = v.rows.filter(r => r.after === -2);
  const group = v.groups.find(g => g.kind === 2);
  const moved = new Map(v.moves.filter(m => m.kind === 1).map(m => [m.ref, m.row]));
  const rowNow = p => (moved.has(p.uid) ? moved.get(p.uid) : p.row);
  const bandsAt = r => o.periods.filter(p => p.track === v.track && (!p.variant || p.variant === v.key) && !under.has(p.uid) && rowNow(p) === r).map(p => p.uid);
  const rows = (group ? group.rows : []).map(bandsAt);
  const sc = o.variants.find(x => x.key === `scope:${v.uid}`);
  const scGroup = sc && sc.groups.find(g => g.kind === 2);
  /* 빠지는 줄에 남은 기본 것(엔진은 빠지는 줄을 쌓지 않으므로 거기 남으면 그려질 곳이 없다): 띠는 이사(kind 1) · 사건은 이사(kind 2) ·
     일반 항목은 가림(kind 4)이 있어야 한다 — 칸은 제 띠를 따라간다. */
  const goneRows = new Set(gone.map(r => r.row));
  const movedEv = new Set(v.moves.filter(m => m.kind === 2).map(m => m.ref));
  const hiddenItems = new Set(v.hides.filter(h => h.kind === 4).map(h => h.at));
  const left = {
    띠: o.periods.filter(p => !p.variant && p.track === v.track && goneRows.has(p.row) && !moved.has(p.uid)).length,
    사건: o.events.filter(e => !e.variant && e.track === v.track && goneRows.has(e.row) && !movedEv.has(e.uid)).length,
    항목: o.items.filter((it, i) => !it.variant && it.track === v.track && (goneRows.has(it.row) || goneRows.has(it.row2)) && !hiddenItems.has(i)).length,
  };
  /* 숨은 구성원의 사건(기본 판 · 사건이 든 띠가 숨은 것)은 모두 이사 −1이고, 이사 −1인 사건은 그것뿐이어야 한다(공통 줄로 옮겨 가지 않음 — 검토 고침) */
  const hiddenSet = new Set(hidden);
  const evOfHidden = o.events.filter(e => !e.variant && e.track === v.track && hiddenSet.has(e.band)).map(e => e.uid);
  const evHidden = v.moves.filter(m => m.kind === 2 && m.row === -1).map(m => m.ref);
  /* 선반 변형의 새 줄은 모두 그릇 묶음 안(트랙 끝에 '그 밖' 같은 새 줄이 생기지 않음) · 그 변형의 공통 줄 이름(kind 1)도 없음 */
  const groupRows = new Set(v.groups.flatMap(g => g.rows));
  const fresh = o.tracks.flatMap((t, at) => t.rows.map((r, i) => [at, i, r]).filter(([, , r]) => r.variant === v.key)).map(([at, i]) => ({ at, i }));
  const outside = fresh.filter(f => f.at !== v.track || !groupRows.has(f.i)).map(f => `${f.at}#${f.i}`);
  const commonLabels = (o.rowLabels || []).filter(l => l.variant === v.key && l.kind === 1).length;
  /* 웹 연표의 자동 글줄 문턱(트랙 줄 6 이하면 글줄 2 — 앱은 쓰지 않음)을 넘는가: 기본 줄 수와 그 변형에서 쌓는 줄 수(기본 − 빠지는 줄 + 새 줄)가 문턱 양쪽이면
     다시 셈의 글줄 · 인물 단 · 줄 자리가 기본 줄과 달라 자체 점검 알림이 난다(f4-federation · synth-lay의 소속 펼치기와 같은 갈래 — 알리기만) */
  const baseN = o.tracks[v.track].rows.filter(r => !r.variant).length;
  const liveN = baseN - gone.length + fresh.filter(f => f.at === v.track).length;
  const crosses = (baseN <= 6) !== (liveN <= 6);
  /* 기본 띠(바탕 문화 조각 포함)의 그 변형에서의 줄(이사가 없으면 제자리) · 변형에만 있는 바탕 문화 조각(새 띠) */
  const bandNow = uid => { const p = o.periods.find(q => q.uid === uid && !q.variant); return p ? rowNow(p) : undefined; };
  const underFresh = o.periods.filter(p => p.variant === v.key && (p.look & UNDER) !== 0);
  return { hidden, gone, rows, scopeRows: scGroup ? scGroup.rows.length : -1, nameOf, hides: v.hides.length, sc, left, foot: group && group.rows.length ? group.rows[group.rows.length - 1] : null,
    evOfHidden, evHidden, outside, commonLabels, baseN, liveN, crosses, bandNow, underFresh };
}

/** 숨긴 구성원 꼬리표(구역 59 — 걸음 4)를 읽고 어긋난 곳을 모은다 — { tags(a 차례), faults(글 목록) }. */
function readTags(o, v, s) {
  const tags = o.items.filter(it => it.section === 59 && it.variant === v.key).sort((a, b) => a.a - b.a);
  const border = o.items.find(it => it.section === 23 && it.variant === v.key && it.text2.split('\u001f')[0] === v.uid);
  const faults = [];
  if (tags.length !== s.hidden.length) faults.push(`꼬리표 ${tags.length} ≠ 숨은 띠 ${s.hidden.length}`);
  if (!same(sortU(tags.map(t => t.ref)), sortU(s.hidden))) faults.push('꼬리표가 가리키는 띠가 숨은 띠와 다름');
  if (!border) faults.push('같은 변형의 그릇 테(구역 23)가 없음');
  tags.forEach((t, i) => {
    const at = s.nameOf(t.ref);
    const bands = o.periods.filter(p => p.uid === t.ref && !p.variant);
    if (t.a !== SHELF_KEEP + i) faults.push(`${at}: a ${t.a} ≠ ${SHELF_KEEP + i}`);
    if (t.b !== tags.length) faults.push(`${at}: b ${t.b} ≠ 숨은 수 ${tags.length}`);
    if (t.text2 !== t.ref) faults.push(`${at}: text2 ${t.text2} ≠ ref`);
    if (t.track !== v.track) faults.push(`${at}: 트랙 ${t.track} ≠ ${v.track}`);
    if (t.row !== s.foot || t.row2 !== s.foot) faults.push(`${at}: 줄 ${t.row} ~ ${t.row2} ≠ 그릇 끝 줄 ${s.foot}`);
    if (!bands.length) faults.push(`${at}: 기본 띠가 없음`);
    else {
      const lo = Math.min(...bands.map(p => p.start)), hi = Math.max(...bands.map(p => p.end));
      if (t.start !== lo || t.end !== hi) faults.push(`${at}: 구간 ${t.start} ~ ${t.end} ≠ 띠 ${lo} ~ ${hi}`);
      if (t.name !== bands[0].name || t.color !== bands[0].color) faults.push(`${at}: 이름 · 색이 띠와 다름`);
    }
    if (border && t.lod !== lodOf(border.end - border.start)) faults.push(`${at}: lod ${t.lod} ≠ 테의 단계 ${lodOf(border.end - border.start)}`);
  });
  return { tags, faults };
}

console.log('① 선반 변형 — 정답지 upto-lens');
const shelfData = new Set();
const names = list.map(f => f.name).filter(n => !only.length || only.includes(n));
for (const name of names) {
  const file = path.join(oracleDir, name, 'upto-lens.json');
  if (!fs.existsSync(file)) { console.log(`  · ${name}: 정답지 없음(건너뜀 — 선택 자료이거나 뽑지 않음)`); continue; }
  const o = JSON.parse(bodyText(fs.readFileSync(file, 'utf8')));
  const shelves = (o.variants || []).filter(v => v.kind === 6);
  const want = EXPECT[name];
  const shelfKeys = new Set(shelves.map(v => v.key));
  const stray = o.items.filter(it => it.section === 59 && !shelfKeys.has(it.variant)).length;
  if (stray) fail(`${name}: 선반 변형 밖의 숨긴 구성원 꼬리표(구역 59) ${stray}`);
  if (!shelves.length) {
    if (want) fail(`${name}: 선반 변형이 없음(기대 ${want.key})`);
    continue;
  }
  shelfData.add(name);
  console.log(`  ${name}: 변형 ${o.variants.length} · 선반 ${shelves.length}`);
  if (!want) fail(`${name}: 기대하지 않은 선반 변형 ${shelves.map(v => v.key).join(' · ')}`);
  for (const v of shelves) {
    const s = readShelf(o, v);
    const short = uid => s.nameOf(uid);
    console.log(`    ${v.key}: 그릇 줄 ${s.scopeRows} → ${s.rows.length} · 숨음 ${s.hidden.length}(${s.hidden.map(short).join(' · ')}) · 빠지는 줄 ${s.gone.map(r => r.row).join(',') || '없음'} · 가림 ${s.hides} · 이사 ${v.moves.length} · 새 줄 ${v.rows.filter(r => r.new).length}${v.notes ? ` · 알림: ${v.notes}` : ''}`);
    console.log(`      선반 줄: ${s.rows.map(r => `[${r.map(short).join(' · ')}]`).join(' ')}`);
    const leftN = Object.values(s.left).reduce((a, b) => a + b, 0);
    if (leftN) fail(`${name}: 빠지는 줄에 이사 · 가림 없이 남은 기본 것 — ${Object.entries(s.left).map(([k, n]) => `${k} ${n}`).join(' · ')}`);
    console.log(`      숨은 구성원의 사건: ${s.evOfHidden.length}(이사 −1 ${s.evHidden.length}) · 그릇 밖 새 줄 ${s.outside.join(',') || '없음'} · 쌓는 줄 ${s.baseN} → ${s.liveN}${s.crosses ? '(자동 글줄 문턱을 넘음)' : ''}` +
      `${s.underFresh.length ? ` · 변형에만 있는 바탕 문화 조각 ${s.underFresh.map(p => `${p.uid}@${p.row}`).join(' ')}` : ''}`);
    if (!same(sortU(s.evOfHidden), sortU(s.evHidden))) fail(`${name}: 숨은 구성원의 사건 ${s.evOfHidden.length}과 이사 −1인 사건 ${s.evHidden.length}이 다름`);
    if (s.outside.length) fail(`${name}: 그릇 묶음 밖의 새 줄 ${s.outside.join(',')}(숨은 구성원의 사건이 공통 줄로 옮겨 간 것)`);
    if (s.commonLabels) fail(`${name}: 그 변형의 공통 줄('그 밖') 이름 ${s.commonLabels}`);
    const tg = readTags(o, v, s);
    console.log(`      꼬리표(구역 59): ${tg.tags.map(t => `${t.a} ${short(t.ref)}`).join(' · ') || '없음'} — 줄 ${s.foot} · lod ${[...new Set(tg.tags.map(t => t.lod))].join(',') || '-'}`);
    for (const f of tg.faults) fail(`${name}: 꼬리표 — ${f}`);
    if (!want) continue;
    if (want.tags && !same(tg.tags.map(t => t.ref), want.tags)) fail(`${name}: 꼬리표 차례 ${tg.tags.map(t => short(t.ref)).join(' · ')} ≠ 기대 ${want.tags.map(short).join(' · ')}`);
    if (v.key !== want.key) fail(`${name}: 열쇠 ${v.key} ≠ 기대 ${want.key}`);
    if (v.uid !== v.key.slice('shelf:'.length)) fail(`${name}: uid ${v.uid}가 열쇠와 다름`);
    if (!s.sc) fail(`${name}: 같은 그릇의 scope 변형이 없음`);
    if (v.notes && !s.crosses) fail(`${name}: 자체 점검 알림 — ${v.notes}`);
    if (v.notes && s.crosses) console.log(`      (알림만 — 쌓는 줄 ${s.baseN} → ${s.liveN}이 웹 연표의 자동 글줄 문턱 6을 넘어 다시 셈의 글줄 · 인물 단이 기본 줄과 다름 · 앱은 이 문턱을 쓰지 않음)`);
    if (want.hiddenEvents !== undefined && s.evOfHidden.length !== want.hiddenEvents) fail(`${name}: 숨은 구성원의 사건 ${s.evOfHidden.length} ≠ 기대 ${want.hiddenEvents}`);
    for (const [uid, succ] of want.under || []) {
      const got = s.bandNow(uid), exp = succ ? s.bandNow(succ) : -1;
      if (got !== exp) fail(`${name}: 바탕 문화 조각 ${uid}의 줄 ${got} ≠ 기대 ${exp}(${succ ? `${short(succ)}의 줄` : '숨음'})`);
    }
    for (const [uid, succ] of want.underFresh || []) {
      const exp = s.bandNow(succ);
      if (!s.underFresh.some(p => p.uid.startsWith(`${uid}#u`) && p.row === exp)) fail(`${name}: 변형에만 있는 바탕 문화 조각 ${uid}#u…가 ${short(succ)}의 줄 ${exp}에 없음`);
    }
    if (s.gone.some(r => r.ord !== -1 || r.new !== 0)) fail(`${name}: 빠지는 줄의 ord · new가 −1 · 0이 아님`);
    if (s.rows.flat().some(uid => s.hidden.includes(uid))) fail(`${name}: 숨은 띠가 선반 줄에 있음`);
    if (want.rows && !same(s.rows, want.rows)) fail(`${name}: 선반 줄 ${JSON.stringify(s.rows)} ≠ 기대 ${JSON.stringify(want.rows)}`);
    if (want.hidden && !same(sortU(s.hidden), sortU(want.hidden))) fail(`${name}: 숨음 ${s.hidden.join(',')} ≠ 기대 ${want.hidden.join(',')}`);
    if (want.scopeRows && (s.scopeRows !== want.scopeRows[0] || s.rows.length !== want.scopeRows[1])) fail(`${name}: 그릇 줄 ${s.scopeRows} → ${s.rows.length} ≠ 기대 ${want.scopeRows.join(' → ')}`);
    if (want.keepPrefix) {
      const kept = s.rows.flat().map(short);
      const miss = want.keepPrefix.filter(px => !kept.some(n => n.startsWith(px)));
      if (miss.length || kept.length !== want.keepPrefix.length) fail(`${name}: 남는 것 ${kept.join(' · ')} ≠ 기대 ${want.keepPrefix.join(' · ')}`);
    }
  }
}

console.log(`\n② 고치기 전 정답지(${path.relative(path.resolve(prototype, '..'), beforeDir).replace(/\\/g, '/')})와 견줌 — 머리 $oracle은 뺌`);
if (!fs.existsSync(beforeDir)) {
  console.log('  · 기준 폴더가 없어 건너뜀(걸음 1에서 고치기 전 정답지를 그 폴더로 떠 둠)');
} else {
  /** variants 모듈 앞자리의 파일인가(모든 자료에서 바이트 같아야 함). */
  const early = new Set(MODULES.slice(0, MODULES.indexOf('variants')));
  const isEarly = f => /^(norm-\d+|prep|rows)\.json$/.test(f) || [...early].some(m => f === `pre-${m}.json` || f === `pre-${m}.shared.json` || f === `upto-${m}.json`);
  let sameFiles = 0, grownFiles = 0, freshFiles = 0;
  for (const name of names) {
    const a = path.join(beforeDir, name), b = path.join(oracleDir, name);
    if (!fs.existsSync(a) || !fs.existsSync(b)) continue;
    const want = EXPECT[name];
    // 입력(머리 sources — 자료 이름 · SHA-256 앞 12자)이 바뀐 자료는 견주지 않는다(자료를 고친 것 — 출력이 다른 것이 당연)
    const sourcesOf = dir => { const m = fs.readFileSync(path.join(dir, 'upto-lens.json'), 'utf8').slice(0, 4096).match(/"sources":(\[[^\]]*\])/); return m ? m[1] : ''; };
    if (fs.existsSync(path.join(a, 'upto-lens.json')) && fs.existsSync(path.join(b, 'upto-lens.json')) && sourcesOf(a) !== sourcesOf(b)) {
      console.log(`  ${name}: 입력이 바뀜(자료를 고침) — 견주지 않음`);
      continue;
    }
    const files = fs.readdirSync(a).filter(f => f.endsWith('.json')).sort();
    const extra = fs.readdirSync(b).filter(f => f.endsWith('.json') && !files.includes(f));
    if (extra.length) fail(`${name}: 기준에 없던 파일 ${extra.join(' · ')}`);
    const diff = [];
    let grown = null;
    for (const f of files) {
      const fb = path.join(b, f);
      if (!fs.existsSync(fb)) { fail(`${name}/${f}: 지금 정답지에 없음`); continue; }
      const ta = bodyText(fs.readFileSync(path.join(a, f), 'utf8')), tb = bodyText(fs.readFileSync(fb, 'utf8'));
      if (ta === tb) { sameFiles++; continue; }
      diff.push(f);
      if (isEarly(f)) { fail(`${name}/${f}: variants 앞자리의 파일이 다름`); continue; }
      if (!shelfData.has(name) || !want) continue; // 아래에서 자료째 실패로
      if (!want.strict) { freshFiles++; continue; }
      const [ja, jb] = [JSON.parse(ta), JSON.parse(tb)];
      const d = extensionOf(ja, jb);
      if (d) { fail(`${name}/${f}: 덧붙임이 아닌 바뀜 — ${d}`); continue; }
      grownFiles++;
      if (f === 'upto-lens.json') grown = grownOf(ja, jb);
    }
    if (!diff.length) continue;
    if (!shelfData.has(name) || !want) { fail(`${name}: 선반 변형이 없는데 다름 — ${diff.slice(0, 6).join(' · ')}${diff.length > 6 ? ` 외 ${diff.length - 6}` : ''}`); continue; }
    if (!want.strict) { console.log(`  ${name}: 새 시험 자료 — 다른 파일 ${diff.length}/${files.length}(variants 뒤만 · 견주지 않음)`); continue; }
    console.log(`  ${name}: 다른 파일 ${diff.length}/${files.length}(끝에 덧붙음만) — upto-lens에 붙은 것: ${grown ? [...grown].map(([k, n]) => `${k} +${n}`).join(' · ') : '(upto-lens 같음)'}`);
  }
  console.log(`  바이트 같은 파일 ${sameFiles} · 덧붙기만 한 파일 ${grownFiles} · 새 시험 자료의 다른 파일 ${freshFiles}`);
}

console.log(failed ? `\n어긋남 ${failed}곳` : '\n모두 기대대로');
process.exit(failed ? 1 : 0);
