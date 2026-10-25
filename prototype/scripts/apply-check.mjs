// 실자료 같음(계획 한 벌 P4 과제 7b): 옛 DLC 묶음(지금 메이커가 저장한 꼴 그대로 — 옛 DLC의 약속 1)으로 '어떤 차례로 넣고 빼도
// 그 조합을 통째로 지은 것과 같다'를 잰다. 조합마다 배치를 한 번 내고(export-layout.mjs) 통째로 지은 뒤(archive-tool import-layout),
// 길 둘을 고쳐 쓰기(archive-tool apply-layout · 한 번은 add-dlc.mjs --apply)로 걸으며 걸음마다
// `archive-tool canon --queries`(번호 없이 적은 layout · 풀어 낸 타일 · 조회 · 수 세기)가 그 조합의 통째 짓기와 같은지,
// `archive-tool verify-tiles 120`이 누락 · 중복 0인지 본다. 견줌은 canon 출력의 SHA-256 — 다를 때만 두 출력을 풀어 첫 다른 경로를 찍는다.
//
// 사용: node prototype/scripts/apply-check.mjs [--only=ea,ktl,move,nest,dep,d7,sphere,f4crowns,f4office3,f4sphere] [--work=<폴더>] [--keep]
//   --only   돌릴 조합(쉼표 · 기본 모두). 조합 열쇠는 아래 COMBOS.
//   --work   임시 저장소 · 배치를 둘 폴더(기본 <TMP>/apply-check — 처음에 비우고 끝나면 지운다. 어긋나면 살펴보게 남긴다).
//   --keep   다 맞아도 그 폴더를 남긴다.
//   (환경 변수) HT_ARCHIVE_TOOL=<archive-tool 경로> · HT_APPLY_KTL=<KoreanTimeLine .htpack 경로>.
// 종료 코드: 0 = 돌린 걸음이 모두 같음 · 누락 · 중복 0 / 1 = 어긋남이 있거나 조합을 하나도 못 돌림 / 2 = 사용법.
//
// 조합 열(옛 DLC의 약속 1의 묶음 — fixtures/oracle/list.json의 east-asia · +ktl · +move · +nest · +dep · +d7 · +sphere와 같은 짝 —
//   그리고 형식 4 가상 팩 셋을 동아시아 위에 얹은 짝(리메이크 3단계 저장소 걸음 9 — 스키마 4의 띠 form · 문화권 단위 줄 · 실권 · 빌림을 넣고 빼기로 지남)):
//   ea   동아시아 기본팩(packs/east-asia — 배치가 results/compat/east-asia.htpack을 함께 낸다)
//   ktl  + KoreanTimeLine v1.0.5(형식 3 · 감독의 실자료 — 자리는 HT_APPLY_KTL 또는 HT_KTL(없으면 감독 PC의 옛 자리) · 읽기만 · 없으면 그 조합을 건너뜀 —
//        HT_REQUIRE_KTL=1이면 실패 · oracle/ktl.mjs)
//   move + move-scene · nest + nest-scene · dep + dep-scene · d7 + d7-test · sphere + sphere-test(모두 형식 3) — 리메이크 시험 DLC 다섯을 베낀
//        fixtures/oracle/*.htpack
//   f4crowns + f4-crowns(왕관 여럿 · 사람 띠) · f4office3 + f4-office3(직위 줄 · 빌림 · 실권) · f4sphere + f4-sphere(문화권 시대 · 주기 줄)
//        — 형식 4 가상 팩(fixtures/oracle/f4/*.htpack)
// 길 둘:
//   넣기만               동아시아를 통째로 지은 저장소 → +그 DLC(apply-layout). 동아시아 조합은 같은 배치를 다시(바뀐 것 없음).
//   넣고 빼고 다시 넣기  그 조합을 통째로 지은 저장소 → −그 DLC(apply-layout --remove) → +그 DLC(add-dlc.mjs --apply — 예전 도구 길 · 지금은 정답지 ·
//                        비교용: 앱은 엔진의 add_pack · remove_pack으로 넣고 뺀다 — 계약 2-7-1).
//                        동아시아 조합은 갈아 끼우기: 동아시아 → +ktl → (−ktl +move) → (−move +nest) → … → (−d7 +sphere) → (−sphere +f4crowns) → …
//                        → (−f4office3 +f4sphere) → −f4sphere(한 번에 빼고 넣기).
//   넣기만의 끝에서는 canon이 기본으로 줄인 단계(0 · 4 · 7 · 8 · 11 · 14 — 판정 R11) 밖의 단계도 한 번 견준다(조회 없이 타일만).
// 지킨 타일(과제 8 고침 2회차): 걸음마다 고쳐 쓰기 전 · 뒤 저장소에서 엔진 답의 `first_pos` 앞 줄 묶음((c+1)·8 ≤ first_pos — 앱이 버리지 않고
//   그대로 쓰는 타일)의 타일이 바이트로 같은지 표본으로 본다(묶음 ≤ 4 · 단계 4 · 8 · 가로 ≤ 6열). 다르면 어긋남(앱이 옛 타일을 보인다).
// 곁 점검(어긋나도 종료 코드를 바꾸지 않고 알리기만): 통째 짓기의 canon에서 고른 검색 낱말 · 변형 보기 답이 0건이 아닌지(과제 5d의 넓힌 조회),
//   배치에서 변형 판 항목의 띠 번호 칸이 제 띠를 가리키는지(과제 1c 메모 — variants.mjs의 replay가 띠 번호를 새로 셈).
// 필요한 것: Node.js · 엔진 도구(archive-tool — prototype/ 또는 prototype/engine/target/release/) · 이 폴더 구조.
// 배치 내보내기는 results/compat/에 쓴다 — 이 도구가 만든 파일은 끝에 치운다(원래 있던 east-asia.htpack은 그대로 둔다). 돌리는 동안 생긴
// add-dlc --apply의 배치(dlc-apply-* — 같은 때 돈 남의 도구의 것일 수 있다)는 지우지 않고 알리기만 한다.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { useCalendarCopy } from './oracle/cal-copy.mjs';
import { ktlFile, requireKtl } from './oracle/ktl.mjs';

useCalendarCopy('apply-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const oracle = path.join(prototype, 'fixtures', 'oracle');
const compat = path.join(prototype, 'results', 'compat');
const args = process.argv.slice(2);
const option = (name) => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : ''; };
const known = ['--keep'];
const unknown = args.filter(a => !known.includes(a) && !/^--(only|work)=/.test(a));
if (unknown.length) {
  console.error(`모르는 인자: ${unknown.join(' ')}\n사용: node prototype/scripts/apply-check.mjs [--only=ea,ktl,move,nest,dep,d7,sphere,f4crowns,f4office3,f4sphere] [--work=<폴더>] [--keep]`);
  process.exit(2);
}
const keep = args.includes('--keep');
const work = path.resolve(option('work') || path.join(process.env.TMP || process.env.TEMP || os.tmpdir(), 'apply-check'));

const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [process.env.HT_ARCHIVE_TOOL || '', ...[prototype, path.join(prototype, 'engine', 'target', 'release')].flatMap(dir => toolNames.map(n => path.join(dir, n)))]
  .find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) { console.error(`엔진 도구(${toolNames[0]})가 없습니다 — 먼저 cargo build --release --locked.`); process.exit(1); }

/** 얹는 DLC — 키 → 파일 · 이름. id · 판은 파일에서 읽는다(check-pack). */
const DLCS = [
  { key: 'ktl', file: process.env.HT_APPLY_KTL || ktlFile(), what: 'KoreanTimeLine v1.0.5(감독의 실자료)' },
  { key: 'move', file: path.join(oracle, 'move-scene.htpack'), what: 'move-scene' },
  { key: 'nest', file: path.join(oracle, 'nest-scene.htpack'), what: 'nest-scene' },
  { key: 'dep', file: path.join(oracle, 'dep-scene.htpack'), what: 'dep-scene' },
  { key: 'd7', file: path.join(oracle, 'd7-test.htpack'), what: 'd7-test' },
  { key: 'sphere', file: path.join(oracle, 'sphere-test.htpack'), what: 'sphere-test' },
  // 형식 4 가상 팩(리메이크 3단계 저장소 걸음 9): 띠 form · 문화권 단위 줄(sphere_lines — 온 판 '*' 지문) · 실권 · 빌림 출처가 넣고 빼기를 지나도 통째 짓기와 같은지.
  { key: 'f4crowns', file: path.join(oracle, 'f4', 'f4-crowns.htpack'), what: 'f4-crowns' },
  { key: 'f4office3', file: path.join(oracle, 'f4', 'f4-office3.htpack'), what: 'f4-office3' },
  { key: 'f4sphere', file: path.join(oracle, 'f4', 'f4-sphere.htpack'), what: 'f4-sphere' },
];
const COMBOS = [{ key: 'ea', name: '동아시아', dlcs: [] }, ...DLCS.map(d => ({ key: d.key, name: `+${d.what}`, dlcs: [d.key] }))];
const only = new Set(option('only').split(',').filter(Boolean));
for (const k of only) if (!COMBOS.some(c => c.key === k)) { console.error(`모르는 조합: ${k} (있는 것: ${COMBOS.map(c => c.key).join(' · ')})`); process.exit(2); }
/** canon이 기본으로 뜨는 단계(main.rs) 밖의 단계 — 넣기만의 끝에서 한 번(얹힌 몫 2 · 판정 R11). */
const DENSE_LEVELS = '1,2,3,5,6,9,10,12,13';

// ---- 도구 부르기 ----

const ms = (t0) => Math.round(performance.now() - t0);
const tail = (r) => String((r.stderr || r.stdout || '')).trim().split('\n').filter(l => !l.startsWith('    at ')).slice(-8).join('\n');
/** 엔진 도구를 부른다. 실패하면 던진다(무엇을 · 끝 몇 줄). 돌려주는 값: 표준 출력(글 또는 바이트) · 걸린 ms. */
function engine(list, what, { bytes = false } = {}) {
  const t0 = performance.now();
  const r = spawnSync(tool, list, { encoding: bytes ? null : 'utf8', maxBuffer: 1 << 30 });
  if (r.status !== 0) throw new Error(`${what} 실패(종료 ${r.status}): ${tail({ stderr: String(r.stderr || ''), stdout: bytes ? '' : r.stdout })}`);
  return { out: r.stdout, ms: ms(t0) };
}
const lastJson = (text) => JSON.parse(String(text).trim().split('\n').pop());
const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

/** DLC 파일의 id · 판 · 이름(엔진의 check-pack — 앱 · add-dlc와 같은 읽기). */
function packInfo(file) {
  const meta = path.join(work, `pack-${path.basename(file)}.json`);
  engine(['check-pack', file, meta], `DLC 읽기(${file})`);
  const raw = JSON.parse(fs.readFileSync(meta, 'utf8'));
  fs.rmSync(meta, { force: true });
  return { id: String(raw.id || ''), version: String(raw.version ?? ''), name: String(raw.name || '') };
}

/** 조합의 배치를 낸다(export-layout.mjs — add-dlc.mjs와 같은 환경 변수) → 작업 폴더로 옮긴다. */
function exportLayout(combo) {
  const name = `apply-check-${process.pid}-${combo.key}.json`;
  const env = { ...process.env, HT_EXPORT_PACK: 'east-asia', HT_EXPORT_NAME: name, HT_EXPORT_EXTRA: combo.dlcs.map(k => dlc(k).file).join(';') };
  const t0 = performance.now();
  const r = spawnSync(process.execPath, [path.join(scripts, 'export-layout.mjs')], { encoding: 'utf8', env, maxBuffer: 64 << 20 });
  if (r.status !== 0) throw new Error(`배치 내보내기 실패(${combo.name}):\n${tail(r)}`);
  const layout = path.join(work, `layout-${combo.key}.json`);
  fs.copyFileSync(path.join(compat, name), layout); // 다른 드라이브일 수 있어 옮기기 대신 베끼고 지운다
  fs.rmSync(path.join(compat, name), { force: true });
  return { layout, ms: ms(t0) };
}

/** 표본 타일 120장(add-dlc · 가져오기와 같은 문턱). 어긋나면 엔진이 처음 어긋난 곳을 내며 실패한다 — 그 글을 돌려준다. */
function verifyTiles(db) {
  const t0 = performance.now();
  const r = spawnSync(tool, ['verify-tiles', db, '120'], { encoding: 'utf8' });
  if (r.status !== 0) return { ok: false, text: tail(r), ms: ms(t0) };
  const v = lastJson(r.stdout);
  return { ok: v.누락_중복 === 0, text: `${v.타일}장 · 사건 ${v.견준_사건} · 누락·중복 ${v.누락_중복}`, ms: ms(t0) };
}

/** canon 출력(바이트) · SHA-256 · ms. `levels`를 주면 조회 없이 그 단계의 타일만. */
function canonOf(db, levels = '') {
  const { out, ms: took } = engine(['canon', db, ...(levels ? [`--levels=${levels}`] : ['--queries'])], `canon(${db})`, { bytes: true });
  return { buf: out, sha: sha(out), ms: took };
}

// ---- 지킨 타일(앱의 keepBefore — 계약 2-7 first_pos) ----

const KEEP_LEVELS = [4, 8], KEEP_CHUNKS = 4, KEEP_COLUMNS = 6, CHUNK_ROWS = 8;
/** 저장소의 모든 DLC 번호(`{"op":"layout"}`의 packs — canon처럼 다 켠 보기). */
function packIds(db) {
  const a = lastJson(engine(['query', db, '{"op":"layout"}'], `뼈대(${db})`).out);
  return ((a.data || a).packs || []).map(p => p.id);
}
/** 타일 하나의 바이트와 머리(origin · span — 분). */
function tileOf(db, req) {
  const file = path.join(work, 'keep-tile.bin');
  const head = lastJson(engine(['tile', db, JSON.stringify(req), file], `타일(${db})`).out);
  return { head, bytes: fs.readFileSync(file) };
}
/** 고쳐 쓰기 전([before]) · 뒤([after]) 저장소에서 [firstPos] 앞의 지킨 줄 묶음 타일을 견준다. */
function keptTiles(before, after, firstPos) {
  const kept = Math.floor(Math.max(0, firstPos) / CHUNK_ROWS);
  if (firstPos < 0) return { ok: true, text: '바뀐 트랙 없음(타일을 버리지 않음 — 견주지 않음)' };
  if (!kept) return { ok: true, text: '지킨 묶음 없음' };
  const n = Math.min(KEEP_CHUNKS, kept);
  const chunks = [...new Set(Array.from({ length: n }, (_, i) => (n === 1 ? 0 : Math.round(i * (kept - 1) / (n - 1)))))];
  const info = lastJson(engine(['query', before, '{"op":"info"}'], `정보(${before})`).out);
  const meta = (info.data || info).meta || {};
  const [min, max] = [Number(meta.min), Number(meta.max)];
  const packsBefore = packIds(before), packsAfter = packIds(after);
  let checked = 0, differ = 0, filled = 0;
  const examples = [];
  for (const level of KEEP_LEVELS) {
    const span = tileOf(before, { level, x: 0, chunk: 0, packs: packsBefore }).head.span;
    const first = Math.floor(min / span), last = Math.floor(max / span), count = last - first + 1;
    const xs = [...new Set(count <= KEEP_COLUMNS ? Array.from({ length: count }, (_, i) => first + i)
      : Array.from({ length: KEEP_COLUMNS }, (_, i) => first + Math.floor(i * (count - 1) / (KEEP_COLUMNS - 1))))];
    for (const x of xs) {
      for (const chunk of chunks) {
        const a = tileOf(before, { level, x, chunk, packs: packsBefore }), b = tileOf(after, { level, x, chunk, packs: packsAfter });
        checked++;
        if (a.head.bands + a.head.cells + a.head.events + a.head.pills > 0) filled++;
        if (!a.bytes.equals(b.bytes)) {
          differ++;
          if (examples.length < 3) examples.push(`단계 ${level} · x ${x} · 묶음 ${chunk}: ${a.bytes.length} ↔ ${b.bytes.length}바이트(띠 ${a.head.bands}↔${b.head.bands} · 사건 ${a.head.events}↔${b.head.events})`);
        }
      }
    }
  }
  fs.rmSync(path.join(work, 'keep-tile.bin'), { force: true });
  return { ok: differ === 0, text: `지킨 묶음 ${kept}(표본 ${chunks.join('·')}) · 타일 ${checked}장(빈 것 아님 ${filled}) · 다름 ${differ}${examples.length ? ` — ${examples.join(' / ')}` : ''}` };
}

// ---- 같음 · 다름 ----

const brief = (v) => { const s = JSON.stringify(v); return s === undefined ? '(없음)' : s.length > 160 ? `${s.slice(0, 157)}…` : s; };
/** 두 값의 다른 곳(경로 · 왼쪽 · 오른쪽)을 앞에서부터 `cap`개까지. */
function diffs(a, b, at = '', out = [], cap = 5000) {
  if (out.length >= cap || a === b) return out;
  const kind = (v) => (Array.isArray(v) ? 'array' : v === null ? 'null' : typeof v);
  if (kind(a) !== kind(b) || (kind(a) !== 'array' && kind(a) !== 'object')) {
    if (JSON.stringify(a) !== JSON.stringify(b)) out.push({ at, a: brief(a), b: brief(b) });
    return out;
  }
  if (Array.isArray(a)) {
    if (a.length !== b.length) out.push({ at: `${at}.length`, a: String(a.length), b: String(b.length) });
    for (let i = 0; i < Math.min(a.length, b.length) && out.length < cap; i++) diffs(a[i], b[i], `${at}[${i}]`, out, cap);
    return out;
  }
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (out.length >= cap) break;
    if (!(k in a) || !(k in b)) out.push({ at: `${at}.${k}`, a: k in a ? brief(a[k]) : '(없음)', b: k in b ? brief(b[k]) : '(없음)' });
    else diffs(a[k], b[k], `${at}.${k}`, out, cap);
  }
  return out;
}
/** 다른 곳을 '답' 단위로 묶는 이름 — 조회는 첫 배열 자리 앞까지(queries.echo.<uid>.groups), 타일은 views[i].tiles[j]까지. */
const answerOf = (at) => (at.startsWith('.views') ? (at.match(/^\.views\[\d+\]\.tiles\[\d+\]/) || [at])[0] : at.split('[')[0]);

/** 걸음의 canon을 통째 짓기의 것과 견준다. 다르면 첫 다른 경로와 답 단위 묶음을 돌려준다(출력은 작업 폴더에 남긴다). */
function compare(step, full, label) {
  if (step.sha === full.sha) return { same: true };
  const file = path.join(work, `canon-${label}.json`);
  fs.writeFileSync(file, step.buf);
  const list = diffs(JSON.parse(full.buf.toString('utf8')), JSON.parse(step.buf.toString('utf8')));
  const answers = new Map();
  for (const d of list) answers.set(answerOf(d.at), (answers.get(answerOf(d.at)) || 0) + 1);
  return { same: false, first: list[0], count: list.length, answers: [...answers.keys()], file };
}

// ---- 곁 점검 ----

/** 얹힌 몫 3: 통째 짓기의 canon에서 고른 검색 낱말 · 변형 보기 답이 0건이 아닌지. */
function queryWidth(full) {
  const q = JSON.parse(full.buf.toString('utf8')).queries || {};
  const words = q.search_words || {};
  const hits = (v) => (v && Array.isArray(v.items) ? v.items.length : 0);
  const views = Object.entries(q.variant_views || {});
  let empty = 0, answered = 0;
  for (const [, part] of views) {
    const parts = [...Object.values(part.events_in_bands || {}).map(hits), ...Object.values(part.search || {}).map(hits),
      ...Object.values(part.echo || {}).map(v => (v && v.groups ? v.groups.length : 0)), ...Object.values(part.same_year || {}).map(v => (v && v.tracks ? v.tracks.length : 0))];
    if (parts.some(n => n > 0)) answered++; else empty++;
  }
  const searchHits = Object.values(q.search || {}).map(hits);
  return {
    text: `검색 낱말 옛 ${words.plain ?? '?'} · 거르개 ${words.filtered ? '있음' : '없음'} · 넓힌 ${words.wide ?? '?'} (기본 보기 검색 답 ${searchHits.join('/') || '없음'}건)`
      + ` · 변형 보기 ${views.length}(답 있는 것 ${answered} · 빈 것 ${empty})`,
    zero: !(words.plain > 0) || !(words.wide > 0) || searchHits.some(n => n === 0) || empty > 0,
  };
}

/** 계약의 띠 번호 칸(engine/src/bandref.rs의 표와 같다). */
const bandFields = (it) => {
  if (it.section === 16 && it.b !== 4) return ['d'];
  if (it.section === 44 || it.section === 45) return ['d'];
  if (it.section === 47 && it.a !== 7) return ['d'];
  if ([21, 22, 49, 52, 60].includes(it.section)) return ['b'];
  return [];
};
/** text2에 그 칸이 가리킬 띠의 uid를 적는 구역(hangs.mjs 16 · 44 · 45 · 47의 d · links.mjs 21 · 60의 b) — 맞대 볼 수 있다. */
const TEXT2_IS_BAND = new Set([16, 44, 45, 47, 21, 60]);

/** 얹힌 몫 1: 배치에서 띠 번호 칸('`periods` 자리 + 1')이 제 띠를 가리키는지 — 기본 항목과 변형마다(변형 열쇠 — `view:`는 집합 보기 판) 따로.
    맞대 볼 수 있는 구역은 text2의 uid로 옳은 번호를 셈해 어긋난 폭(적힌 번호 − 옳은 번호)도 센다. */
function bandNumbers(layoutFile) {
  const out = JSON.parse(fs.readFileSync(layoutFile, 'utf8'));
  const periods = out.periods || [], items = out.items || [];
  const numberOf = new Map();
  periods.forEach((p, i) => { if (!numberOf.has(p.uid)) numberOf.set(p.uid, i + 1); });
  const kinds = new Map(); // '기본' 또는 변형 열쇠 → { checked, wrong, unchecked, outside, shifts, examples, sections }
  for (const it of items) {
    for (const f of bandFields(it)) {
      const n = it[f];
      if (!n) continue;
      const k = it.variant ? String(it.variant) : '기본';
      const slot = kinds.get(k) || { checked: 0, wrong: 0, unchecked: 0, outside: 0, shifts: new Map(), examples: [], sections: new Map() };
      kinds.set(k, slot);
      const band = periods[n - 1];
      if (!band) { slot.outside++; if (slot.examples.length < 2) slot.examples.push(`구역 ${it.section} ${f}=${n}: 띠 목록 밖(띠 ${periods.length}개)`); continue; }
      if (!TEXT2_IS_BAND.has(it.section) || !it.text2) { slot.unchecked++; continue; }
      slot.checked++;
      // 구역별(16 · 44 · 45 · 47 · 21) 맞대 본 수 · 어긋난 수 — 어느 구역이 비었는지(맞대 보지 못했는지)도 드러나게.
      const per = slot.sections.get(it.section) || { checked: 0, wrong: 0 };
      slot.sections.set(it.section, per);
      per.checked++;
      if (band.uid !== it.text2) {
        per.wrong++;
        slot.wrong++;
        const shift = numberOf.has(it.text2) ? n - numberOf.get(it.text2) : '?';
        slot.shifts.set(shift, (slot.shifts.get(shift) || 0) + 1);
        if (slot.examples.length < 2) slot.examples.push(`구역 ${it.section} ${f}=${n} → «${band.uid}» ≠ 적은 «${it.text2}»(옳은 번호 ${numberOf.get(it.text2) ?? '없음'})`);
      }
    }
  }
  return [...kinds.entries()].map(([k, s]) => ({ kind: k, ...s, shifts: [...s.shifts.entries()].map(([d, c]) => `${d > 0 ? '+' : ''}${d}×${c}`).join(' '),
    sections: [...TEXT2_IS_BAND].map(sec => { const p = s.sections.get(sec) || { checked: 0, wrong: 0 }; return `${sec} ${p.checked}${p.wrong ? `(어긋남 ${p.wrong})` : ''}`; }).join(' · ') }));
}

// ---- 걷기 ----

const dlcByKey = new Map(DLCS.map(d => [d.key, d]));
const dlc = (k) => dlcByKey.get(k);
const rows = []; // 요약 표의 줄
let bad = 0;

/** 걸음 하나: 저장소를 `from` 조합에서 `to` 조합으로 고쳐 쓰고(apply-layout 또는 add-dlc --apply) `to`의 통째 짓기와 견준다(`owner` = 표의 조합). */
function step(owner, walk, db, from, to, via, label) {
  const add = to.dlcs.filter(k => !from.dlcs.includes(k)), remove = from.dlcs.filter(k => !to.dlcs.includes(k));
  const what = `${[...remove.map(k => `−${k}`), ...add.map(k => `+${k}`)].join(' ') || '같은 배치 다시'} → ${to.key}`;
  let answer, applyMs;
  // 지킨 타일을 견주려고 고쳐 쓰기 전 저장소를 베껴 둔다(옆 파일 — 걸음 뒤 지움).
  const before = `${db}.before.db`;
  fs.copyFileSync(db, before);
  const t0 = performance.now();
  if (via === 'add-dlc') {
    // 사용자가 쓰는 도구 길: 원본은 저장소에서 꺼내고(pack-out) · 준 파일과 함께 배치를 셈해(export-layout) 고쳐 쓴 뒤 DLC/ 폴더를 맞춘다.
    if (remove.length > 1) throw new Error('add-dlc --apply는 한 번에 하나만 뺀다');
    const r = spawnSync(process.execPath, [path.join(scripts, 'add-dlc.mjs'), db, '--apply', ...add.map(k => dlc(k).file), ...remove.map(k => `--remove=${dlc(k).id}`)],
      { encoding: 'utf8', env: { ...process.env, HT_ARCHIVE_TOOL: tool }, maxBuffer: 64 << 20 });
    if (r.status !== 0) throw new Error(`add-dlc --apply 실패(${walk} · ${what}, 종료 ${r.status}): ${tail(r)}`);
    answer = lastJson(r.stdout);
    const folder = fs.existsSync(path.join(path.dirname(db), 'DLC')) ? fs.readdirSync(path.join(path.dirname(db), 'DLC')).sort().join(', ') : '(없음)';
    answer.folder = folder;
  } else {
    // 원본: 기본팩(배치를 셈한 그 파일 — 같으면 엔진이 그대로 둔다) + 새로 넣는 DLC. 이미 든 DLC의 원본은 저장소의 것(넘기지 않는다).
    const originals = [basePack, ...add.map(k => dlc(k).file)];
    const { out } = engine(['apply-layout', db, layouts.get(to.key), ...originals, ...remove.map(k => `--remove=${dlc(k).id}`)], `apply-layout(${walk} · ${what})`);
    answer = lastJson(out);
  }
  applyMs = ms(t0);
  let keptCheck;
  try {
    keptCheck = keptTiles(before, db, Number(answer.first_pos ?? -1));
  } catch (e) {
    keptCheck = { ok: false, text: `견주지 못함 — ${e.message}` };
  } finally {
    fs.rmSync(before, { force: true });
  }
  return judge({ owner, walk, combo: to, what: `${what}${via === 'add-dlc' ? ' (add-dlc --apply)' : ''}`, db, answer, applyMs, label, keptCheck });
}

/** 저장소 하나를 그 조합의 통째 짓기와 견주고 표에 적는다. */
function judge({ owner, walk, combo, what, db, answer, applyMs, label, keptCheck }) {
  const v = verifyTiles(db);
  const c = canonOf(db);
  const full = fulls.get(combo.key);
  const cmp = compare(c, full.canon, label);
  const row = {
    combo: owner.name, walk, what, same: cmp.same, verify: v.ok ? `0` : `어긋남 — ${v.text}`, ok: cmp.same && v.ok && (!keptCheck || keptCheck.ok),
    kept: keptCheck ? (keptCheck.ok ? '같음' : '**다름**') : '—',
    rewrote: answer ? `${answer.rewrote.length}/${answer.added.length}/${answer.removed.length}` : '—', rowsAfter: answer ? answer.rows_after : '—',
    applyMs: applyMs ?? '—', engineMs: answer ? Math.round(answer.ms) : '—', canonMs: c.ms, verifyMs: v.ms,
  };
  rows.push(row);
  if (!row.ok) bad++;
  console.log(`  [${walk}] ${what}: ${cmp.same ? '같음' : '다름'} · 표본 타일 ${v.text} · 다시 쓴/새/뺀 트랙 ${row.rewrote} · 줄 ${row.rowsAfter}`
    + ` · 고쳐 쓰기 ${row.applyMs}ms(엔진 ${row.engineMs}) · canon ${c.ms}ms${answer && answer.folder ? ` · DLC 폴더 ${answer.folder}` : ''}`);
  if (keptCheck) console.log(`    지킨 타일(first_pos ${answer?.first_pos}): ${keptCheck.text}`);
  if (!cmp.same) {
    console.log(`    첫 다른 곳 ${cmp.first.at}\n      통째 짓기 ${cmp.first.a}\n      고쳐 쓴 것 ${cmp.first.b}`);
    console.log(`    다른 곳 ${cmp.count}${cmp.count >= 5000 ? '+' : ''} · 답 ${cmp.answers.length}: ${cmp.answers.slice(0, 12).join(' · ')}${cmp.answers.length > 12 ? ' …' : ''}`);
    console.log(`    출력: ${cmp.file}`);
  }
  return row;
}

/** 통째 짓기를 저장소 폴더에 베낀다(걷기는 사본에서). */
function copyFull(key, to) {
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(fulls.get(key).db, to);
  return to;
}

// ---- 차리기 ----

const compatHad = fs.existsSync(compat);
const basePackHad = fs.existsSync(path.join(compat, 'east-asia.htpack'));
const compatBefore = new Set(compatHad ? fs.readdirSync(compat) : []);
// 작업 폴더는 처음에 비운다 — 이 도구가 만든 폴더(표지 파일)이거나 빈 폴더일 때만(남의 폴더를 지우지 않게).
const MARK = path.join(work, '.apply-check');
if (fs.existsSync(work) && fs.readdirSync(work).length && !fs.existsSync(MARK)) {
  console.error(`작업 폴더가 비어 있지 않고 이 도구가 만든 것도 아닙니다 — 다른 폴더를 주세요(--work): ${work}`);
  process.exit(2);
}
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
fs.writeFileSync(MARK, 'apply-check.mjs의 작업 폴더 — 다음에 돌릴 때 비운다\n');
fs.mkdirSync(compat, { recursive: true });
const cleanCompat = () => {
  // 이 도구가 만든 것만 지운다(내 배치 — 원래 있던 파일은 그대로). 돌리는 동안 생긴 add-dlc --apply의 배치(dlc-apply-*)는 이 도구가 부른
  // add-dlc가 실패하며 남긴 것일 수도, 같은 때 돈 남의 도구의 것일 수도 있어 지우지 않고 알리기만 한다.
  const strays = [];
  for (const f of fs.existsSync(compat) ? fs.readdirSync(compat) : []) {
    if (compatBefore.has(f)) continue;
    if (f.startsWith(`apply-check-${process.pid}-`)) fs.rmSync(path.join(compat, f), { force: true });
    else if (f.startsWith('dlc-apply-')) strays.push(f);
  }
  if (strays.length) console.log(`알림: 돌리는 동안 ${compat}에 생긴 배치를 지우지 않았습니다(남의 것일 수 있음): ${strays.join(' · ')}`);
  if (!basePackHad) fs.rmSync(path.join(compat, 'east-asia.htpack'), { force: true });
  if (!compatHad && fs.existsSync(compat) && !fs.readdirSync(compat).length) fs.rmSync(compat, { recursive: true, force: true });
};

const started = performance.now();
console.log(`엔진 도구: ${tool}\n작업 폴더: ${work}`);
const layouts = new Map(); // 조합 열쇠 → 배치 경로
let basePack = ''; // 첫 배치가 함께 낸 기본팩(results/compat/east-asia.htpack)을 작업 폴더에 베낀 것
const fulls = new Map(); // 조합 열쇠 → { db, canon }
let combos = [], skipped = [];
let exitCode = 0;
try {
  // DLC 파일 읽기(check-pack)도 try 안에서 — 읽지 못하면 멈추되 results/compat를 치운다(작업 폴더는 살펴보게 남긴다).
  for (const d of DLCS) {
    if (!fs.existsSync(d.file) && d.key === 'ktl' && requireKtl()) throw new Error(`KTL이 없습니다(${d.file}) — HT_REQUIRE_KTL=1이라 건너뛰지 않습니다(자리는 HT_KTL)`);
    if (!fs.existsSync(d.file)) { d.missing = true; console.log(`자료 없음 — ${d.what}(${d.file}): 그 DLC가 든 조합 · 걸음을 건너뜁니다.`); continue; }
    Object.assign(d, packInfo(d.file));
    console.log(`DLC ${d.key}: «${d.id}» v${d.version} ${d.name} — ${d.file}`);
  }
  combos = COMBOS.filter(c => (!only.size || only.has(c.key)) && !c.dlcs.some(k => dlc(k).missing));
  skipped = COMBOS.filter(c => (!only.size || only.has(c.key)) && c.dlcs.some(k => dlc(k).missing));
  for (const c of skipped) console.log(`조합 건너뜀: ${c.name} — 자료가 없습니다.`);
  if (!combos.length) {
    console.error('\n돌릴 조합이 없습니다(자료가 없거나 --only로 고른 조합을 모두 건너뜀).');
    cleanCompat();
    fs.rmSync(work, { recursive: true, force: true });
    process.exit(1);
  }
  // 걷기가 닿는 조합: 고른 조합 + 동아시아(넣기만의 출발) + 갈아 끼우기가 지나는 조합(동아시아 조합을 고르면).
  const needed = new Set(['ea', ...combos.map(c => c.key)]);
  if (combos.some(c => c.key === 'ea')) for (const c of COMBOS) if (c.dlcs.every(k => !dlc(k).missing)) needed.add(c.key);
  console.log(`\n배치 · 통째 짓기(${[...needed].join(' · ')})`);
  for (const key of needed) {
    const combo = COMBOS.find(c => c.key === key);
    const { layout, ms: exportMs } = exportLayout(combo);
    layouts.set(key, layout);
    if (!basePack) {
      basePack = path.join(work, 'east-asia.htpack');
      fs.copyFileSync(path.join(compat, 'east-asia.htpack'), basePack);
    }
    const db = path.join(work, `full-${key}`, 'archive.db');
    fs.mkdirSync(path.dirname(db), { recursive: true });
    const imp = engine(['import-layout', basePack, layout, db, ...combo.dlcs.map(k => dlc(k).file)], `통째 짓기(${combo.name})`);
    const v = verifyTiles(db);
    const canon = canonOf(db);
    fs.writeFileSync(path.join(work, `canon-full-${key}.json`), canon.buf);
    fulls.set(key, { db, canon });
    const width = queryWidth(canon);
    console.log(`  ${combo.name}: 배치 ${exportMs}ms · 짓기 ${imp.ms}ms · 표본 타일 ${v.text} · canon ${(canon.buf.length / 1048576).toFixed(1)}MB ${canon.ms}ms · sha ${canon.sha.slice(0, 12)}`);
    console.log(`    곁 점검(조회 넓이): ${width.text}${width.zero ? ' ← 0건이 있음' : ''}`);
    for (const k of bandNumbers(layout)) {
      console.log(`    곁 점검(띠 번호 · ${k.kind}): 맞대 본 ${k.checked}(구역별 ${k.sections}) · 어긋남 ${k.wrong}${k.shifts ? `(어긋난 폭 ${k.shifts})` : ''} · 맞대 볼 수 없음 ${k.unchecked} · 목록 밖 ${k.outside}`
        + (k.examples.length ? `\n      ${k.examples.join('\n      ')}` : ''));
    }
    rows.push({ combo: combo.name, walk: '통째 짓기', what: `import-layout → ${key}`, same: true, verify: v.ok ? '0' : `어긋남 — ${v.text}`, ok: v.ok, rewrote: '—', rowsAfter: '—',
      applyMs: imp.ms, engineMs: '—', canonMs: canon.ms, verifyMs: v.ms });
    if (!v.ok) bad++;
  }

  for (const combo of combos) {
    console.log(`\n조합 ${combo.name}`);
    const ea = COMBOS[0];
    // 길 1 — 넣기만: 동아시아 통째 → +그 DLC(동아시아 조합은 같은 배치 다시).
    const db1 = copyFull('ea', path.join(work, `${combo.key}-1`, 'archive.db'));
    step(combo, '넣기만', db1, ea, combo, 'apply', `${combo.key}-1`);
    // 넣기만의 끝: 줄인 단계 밖의 타일도 한 번(얹힌 몫 2).
    {
      const a = canonOf(fulls.get(combo.key).db, DENSE_LEVELS), b = canonOf(db1, DENSE_LEVELS);
      const cmp = compare(b, a, `${combo.key}-1-dense`);
      const row = { combo: combo.name, walk: '넣기만', what: `빠진 단계 ${DENSE_LEVELS}(타일만) → ${combo.key}`, same: cmp.same, verify: '—', ok: cmp.same, rewrote: '—', rowsAfter: '—',
        applyMs: '—', engineMs: '—', canonMs: a.ms + b.ms, verifyMs: '—' };
      rows.push(row);
      if (!cmp.same) bad++;
      console.log(`  [넣기만] 빠진 단계 ${DENSE_LEVELS}: ${cmp.same ? '같음' : '다름'} · ${(b.buf.length / 1048576).toFixed(1)}MB · canon ${a.ms}+${b.ms}ms`
        + (cmp.same ? '' : `\n    첫 다른 곳 ${cmp.first.at}\n      통째 짓기 ${cmp.first.a}\n      고쳐 쓴 것 ${cmp.first.b}\n    답 ${cmp.answers.length}: ${cmp.answers.slice(0, 12).join(' · ')}`));
    }
    // 길 2 — 넣고 빼고 다시 넣기.
    if (combo.key !== 'ea') {
      const db2 = copyFull(combo.key, path.join(work, `${combo.key}-2`, 'archive.db'));
      step(combo, '넣고 빼고 다시 넣기', db2, combo, ea, 'apply', `${combo.key}-2a`);
      step(combo, '넣고 빼고 다시 넣기', db2, ea, combo, 'add-dlc', `${combo.key}-2b`);
    } else {
      // 동아시아 조합은 갈아 끼우기: 동아시아 → +첫 DLC → (앞 DLC 빼며 다음 DLC 넣기) … → 마지막 DLC 빼기.
      const db2 = copyFull('ea', path.join(work, 'ea-2', 'archive.db'));
      const tour = [ea, ...COMBOS.slice(1).filter(c => c.dlcs.every(k => !dlc(k).missing)), ea];
      for (let i = 1; i < tour.length; i++) step(combo, '넣고 빼고 다시 넣기', db2, tour[i - 1], tour[i], 'apply', `ea-2-${i}`);
    }
  }
} catch (e) {
  console.error(`\n멈춤: ${e.message}`);
  exitCode = 1;
} finally {
  cleanCompat();
}

// ---- 요약 ----
console.log(`\n| 조합 | 길 | 걸음 | 같음 | 누락·중복 | 지킨 타일 | 다시 쓴/새/뺀 트랙 | 줄 | 고쳐 쓰기 ms(엔진) | canon ms | 타일 검사 ms |`);
console.log('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
for (const r of rows) {
  console.log(`| ${r.combo} | ${r.walk} | ${r.what} | ${r.same ? '같음' : '**다름**'} | ${r.verify} | ${r.kept ?? '—'} | ${r.rewrote} | ${r.rowsAfter} | ${r.applyMs}${r.engineMs !== '—' ? `(${r.engineMs})` : ''} | ${r.canonMs} | ${r.verifyMs} |`);
}
if (bad) exitCode = 1;
const total = ((performance.now() - started) / 1000).toFixed(1);
console.log(`\n걸음 ${rows.length} · 어긋남 ${bad} · 건너뛴 조합 ${skipped.length} · ${total}초 — ${exitCode === 0 ? '모두 같음 · 누락·중복 0' : '어긋남이 있습니다'}`);
if (exitCode === 0 && !keep) fs.rmSync(work, { recursive: true, force: true });
else console.log(`작업 폴더를 남겼습니다: ${work}`);
process.exit(exitCode);
