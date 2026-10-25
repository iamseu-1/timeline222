// 보조 달력(음력 · 중국 음력 · 이슬람력 · 움 알쿠라 · 페르시아력)의 **달의 시작 표**를 넣을 때 한 번 떠서 항목 기록에 싣는다.
//
// 까닭: 지금 연표(js/calendar.js)는 브라우저의 `Intl.DateTimeFormat('en-u-ca-dangi' …)` — ICU의 달력 표 — 에
// 기대어 환산한다. Dart에는 그 표가 없고 새 꾸러미도 넣지 않기로 했으므로, **노드에도 있는 같은 ICU**로 표를
// 미리 떠서 저장소에 싣는다. 그리는 쪽은 그 표를 이분 탐색해 분 ↔ (해, 달, 날)을 옮긴다.
//
// 싣는 곳: 항목 기록 `entities`의 `{uid:'cal:<달력>', kind:'cal', json:'{…}'}`. 조회는 이미 있는
// `{"op":"entity","uid":"cal:dangi"}`다(Rust를 고치지 않는다 — 엔진은 기록의 뜻을 모른 채 싣고 돌려준다).
//
// ── 표의 모양(계약 6-3절에도 적었다) ────────────────────────────────────────────────────────
//   { cal, calName, lunar, prefix, from, to, year0, count, months, note }
//   · calName     달력 이름. **`name`이 아니다** — 엔진이 이름 표(`names`)를 펼 때 `$.name`이 있는 항목 기록을
//                 모두 검색에 싣기 때문이다(builder.rs의 build_names 2)). 달력은 검색에 나올 것이 아니다.
//   · from · to   그 표가 덮는 날 번호(JDN)의 양 끝(from = 첫 달의 초하루 · to = 마지막 달의 다음 초하루).
//                 이 밖은 '모르는 범위'라 눈금을 그리지 않는다.
//   · year0       첫 달이 든 해(지금 연표가 쓰는 값 그대로 — 음력은 그 달이 든 서력 연표 연도, 그 밖은 ICU의 해).
//   · months      **한 달에 두 글자**인 글. 달마다 [이름 글자][길이 글자]:
//                   이름 = String.fromCharCode(65 + 달*2 + (윤달?1:0))  → 'C'~'Z' (달 1~12)
//                   길이 = String.fromCharCode(48 + 날수 - 29)          → '0'(29일) · '1'(30일) · '2'(31일)
//                 해는 셈으로 얻는다: 달 1이면서 윤달이 아니면 새 해다(음력은 0년 자리를 건너뛴다).
//                 줄마다 `[시작 분, 해, 달, 윤달, 날수]`를 그대로 싣는 것보다 12배 작다(아래 '크기' 주석).
//
// 크기(월흔해에서 잰 값 — 자료가 −1550~2027년이라 앞뒤 100년을 더해 −1650~2127년): 달력 하나에 달이
// 45,326~46,716개다. 줄마다 `[시작, 해, 달, 윤달, 날수]`로 실으면 한 달에 24자쯤이라 다섯 달력이 5.6MB로
// 가져오기 JSON(13.2MB)의 40%가 불어난다. 두 글자 글로 싣자 한 달에 2자라 **다섯을 합쳐 0.47MB**다(12분의 1).
// 이 표는 화면에서 이분 탐색으로만 쓰이므로 줄의 모양이 필요 없다. 뜨는 데 5.9초가 든다.
//
// ── 미리 떠 둔 표(2026-10-15) ────────────────────────────────────────────────────────────────
// DLC를 더하거나 뺄 때마다 이 모듈이 다섯 달력을 ICU로 새로 떠서, 배치 셈 7.3초 가운데 7.1초를 썼다(동아시아 + DLC 하나 —
// 나머지 모듈을 다 합쳐 0.2초 · 저장소 짓기는 0.7초). 표는 **자료의 해 범위와 ICU 판에만** 달려 있고 DLC의 내용과는 무관하므로,
// 넓은 범위로 한 번 떠 둔 표에서 잘라 쓴다 — 잘라 낸 표는 바로 뜬 표와 글자까지 같다([sliceTable] · calendar-cache-check.mjs가 지킨다).
//   · 표 파일: `prototype/results/calendar-cache.json`(노드에서만 — 메이커의 일꾼(브라우저)은 지금처럼 바로 뜬다).
//     환경 변수 HT_CALENDAR_CACHE=off면 쓰지 않고, 경로를 주면 그 파일을 쓴다(검사용).
//   · 시드 · 꾸러미 저장소는 build-showcase.mjs가 warm-calendar.mjs로 −3500~2500년을 떠서 엔진 짓기(`archive-tool build --calendar`)에 넘긴다
//     (꾸러미에는 Node가 없다 — 판정 R49).
//   · 파일이 없거나 · ICU 판이 다르거나 · 범위가 모자라면 모자란 범위를 500년 단위로 넓혀 다시 뜨고 파일을 갈아 둔다(그때만 지금처럼 느리다).
//     **기본 자리(공용 표)는 갈지 않는다**(판정 R64 넘김 · 과제 testinfra — 공용 표는 build-check가 Rust 길에 주는 표이기도 해서, 도구 · 검사가 소리 없이
//     넓히거나 다른 ICU로 갈아 쓰면 안 된다): 그때는 임시 폴더의 사본(<TMP>/ht-calendar-cache-<ICU>.json)에 뜨고 알린다. 공용 표는 warm-calendar.mjs로만 뜬다.
//     HT_CALENDAR_CACHE로 준 파일은 예전처럼 그 자리에서 넓힌다(검사 도구는 제 사본을 준다 — oracle/cal-copy.mjs).
import { assert, node, prototype } from './base.mjs'; // 노드에서는 node:assert/strict 그대로(브라우저 겸용 — base.mjs 머리말)

/// 자료의 앞뒤로 더 떠 두는 햇수(옆으로 끌어 자료 밖을 봐도 눈금이 이어지게).
const PAD_YEARS = 100;

/// 한 달의 날수가 이 사이가 아니면 ICU가 답을 못 준 것으로 본다.
const MIN_LEN = 29, MAX_LEN = 31;

/** 달 하나를 두 글자로. */
const encodeMonth = (m, leap, len) => String.fromCharCode(65 + m * 2 + (leap ? 1 : 0)) + String.fromCharCode(48 + len - 29);

/** 자료가 놓인 해의 범위(연표 연도) — 띠 · 사건 · 시대 구분 · 인물의 양 끝. */
function dataYears(model) {
  let lo = Infinity, hi = -Infinity;
  const see = (a, b) => {
    if (Number.isFinite(a) && a < lo) lo = a;
    if (Number.isFinite(b) && b > hi) hi = b;
  };
  for (const p of model.periods || []) see(p.startRange ? p.startRange[0] : p.start, p.endRange ? p.endRange[1] : p.endY);
  for (const e of model.events || []) see(e.start, e.endY != null ? e.endY : e.start);
  for (const e of model.epochs || []) see(e.start, e.endY != null ? e.endY : e.end);
  for (const f of model.figures || []) see(f.birth != null ? f.birth : f.start, f.death != null ? f.death : f.endY);
  if (!Number.isFinite(lo) || !Number.isFinite(hi)) return [1, 1];
  return [Math.floor(lo) - PAD_YEARS, Math.ceil(hi) + PAD_YEARS];
}

/**
 * 달력 하나의 표를 뜬다. [fromJ, toJ) 안에서 시작하는 달을 모두 담는다.
 * 하루씩 훑지 않고 29 · 30 · 31일을 짚어 경계만 확인한다(한 달에 ICU 물음 두 번쯤).
 */
export function buildTable(HT, c, fromJ, toJ) {
  const id = c.id;
  const first = HT.cal.monthStartIn(id, fromJ); // fromJ가 든 달의 초하루(fromJ보다 앞일 수 있다)
  let J = first;
  let parts = HT.cal.partsIn(id, J);
  assert.ok(parts && Number.isFinite(parts.m), `${c.name}: ICU가 ${fromJ}의 달을 주지 못했습니다`);
  const out = [];
  let year = parts.y;
  let derived = year;
  let bad = '';
  while (J < toJ) {
    let len = 0, next = null;
    for (let k = MIN_LEN; k <= MAX_LEN; k++) {
      const p = HT.cal.partsIn(id, J + k);
      if (p && p.d === 1) {
        len = k;
        next = p;
        break;
      }
    }
    if (!len) {
      bad = `날 번호 ${J}에서 다음 달의 초하루를 찾지 못했습니다`;
      break;
    }
    // 해는 셈으로 되살릴 수 있어야 한다 — 달 1(윤달 아님)마다 한 살. 어긋나면 표의 약속이 깨진 것이다.
    if (out.length) derived = parts.m === 1 && !parts.leap ? (c.lunar && derived === -1 ? 1 : derived + 1) : derived;
    assert.equal(derived, parts.y, `${c.name}: 해를 셈으로 되살릴 수 없습니다(날 번호 ${J} — 셈 ${derived} · ICU ${parts.y})`);
    out.push(encodeMonth(parts.m, parts.leap, len));
    J += len;
    parts = next;
  }
  return { start: first, year0: year, months: out.join(''), count: out.length, end: J, bad };
}

/**
 * 넓게 뜬 표(wide — [buildTable]의 답)에서 [fromJ, toJ)의 표를 잘라 낸다. `buildTable(HT, c, fromJ, toJ)`와 글자까지 같은 답이다 —
 * 첫 달은 fromJ가 든 달, 해는 buildTable과 같은 셈(달 1 · 윤달 아님마다 한 살 · 음력은 0년을 건너뜀)으로 따라간다.
 * 넓은 표가 그 범위를 덮지 못하면 null(그때는 바로 뜬다).
 */
export function sliceTable(wide, c, fromJ, toJ) {
  if (!wide || typeof wide.months !== 'string' || !(wide.start <= fromJ) || !(toJ <= wide.end)) return null;
  const months = wide.months, n = months.length / 2;
  const lenAt = k => months.charCodeAt(k * 2 + 1) - 48 + 29;
  const newYear = k => months.charCodeAt(k * 2) === 67; // 'C' = 달 1 · 윤달 아님(encodeMonth)
  let J = wide.start, year = wide.year0, i = 0;
  while (i < n && J + lenAt(i) <= fromJ) {
    J += lenAt(i++);
    if (i < n && newYear(i)) year = c.lunar && year === -1 ? 1 : year + 1;
  }
  const first = i, start = J, year0 = year;
  while (J < toJ && i < n) J += lenAt(i++);
  if (J < toJ || first >= n) return null;
  return { start, year0, months: months.slice(first * 2, i * 2), count: i - first, end: J, bad: '' };
}

/** 날짜 칸의 고르기 단추에 나오는 달력만(양력 · 그레고리력 · 율리우스력은 순수한 산수라 Dart가 이미 셈한다). */
export const wantedCalendars = HT => HT.cal.CALENDARS.filter(c => c.intl && HT.cal.supports(c.id));

/** 모자랄 때 표를 넓히는 단위(해) — DLC가 해 범위를 조금 넓힐 때마다 다시 뜨지 않게. */
const WIDEN_YEARS = 500;
/** 표 파일의 꼴 번호 — 표의 모양(encodeMonth · buildTable)을 바꾸면 올린다(옛 파일을 쓰지 않게). */
const CACHE_VERSION = 1;

/** 표 파일의 자리(노드에서만 — 브라우저 · HT_CALENDAR_CACHE=off면 빈 글). */
function cacheFile() {
  if (!node) return '';
  const env = (process.env.HT_CALENDAR_CACHE || '').trim();
  if (env === 'off') return '';
  return env ? node.path.resolve(env) : sharedFile();
}

/** 공용 표(기본 자리) — [cachedTables]는 읽기만 한다. */
const sharedFile = () => node.path.join(prototype, 'results', 'calendar-cache.json');

/** 공용 표가 모자랄 때 대신 뜨는 사본의 자리(제 TMP · ICU 판마다 하나). */
function sideFile() {
  const tmp = process.env.TMP || process.env.TEMP || process.env.TMPDIR || (process.platform === 'win32' ? '' : '/tmp');
  return tmp ? node.path.join(tmp, `ht-calendar-cache-${process.versions.icu || 'none'}.json`) : '';
}
let sideNoted = false;

/** 해 범위 [lo, hi]의 날 번호 양 끝 — contribute와 같은 셈(서력에는 0년이 없다). */
const jdnRange = (HT, lo, hi) => [HT.cal.jdnCivil(lo === 0 ? -1 : lo, 1, 1), HT.cal.jdnCivil(hi === -1 || hi === 0 ? 1 : hi + 1, 1, 1)];

/** lo ~ hi년의 표를 모두 떠서 파일에 쓴다(쓰지 못해도 답은 돌려준다 — 읽기 전용 설치). 꾸러미의 warm-calendar.mjs와 [cachedTables]가 쓴다. */
export function warmTables(HT, wanted, lo, hi, file = cacheFile()) {
  const [fromJ, toJ] = jdnRange(HT, lo, hi);
  const tables = {};
  for (const c of wanted) tables[c.id] = Object.assign({ intl: c.intl }, buildTable(HT, c, fromJ, toJ));
  const body = { v: CACHE_VERSION, icu: process.versions.icu || '', years: [lo, hi], tables };
  if (file) {
    // 옆에 쓰고 바꿔 넣는다 — 둘이 함께 돌아도 반쯤 쓴 파일을 읽지 않게.
    const temp = `${file}.${process.pid}.tmp`;
    try {
      node.fs.mkdirSync(node.path.dirname(file), { recursive: true });
      node.fs.writeFileSync(temp, JSON.stringify(body));
      node.fs.renameSync(temp, file);
    } catch {
      try { node.fs.rmSync(temp, { force: true }); } catch { /* 이미 없음 */ }
    }
  }
  return body;
}

/** 미리 떠 둔 표(달력 id → 넓은 표)를 읽는다. 파일이 없거나 · ICU 판이 다르거나 · 자료의 해 범위를 덮지 못하면 그 범위를 500년 단위로
    넓혀(같은 ICU의 옛 범위도 함께 덮어) 다시 뜨고 파일을 갈아 둔다 — 기본 자리(공용 표)면 갈지 않고 제 TMP의 사본([sideFile])에서 같은 일을 한다(머리말).
    노드가 아니거나 · 꺼 두었거나 · 다시 뜨다 실패하면 null. */
function cachedTables(HT, wanted, loYear, hiYear) {
  const file = cacheFile();
  if (!file) return null;
  const read = f => { try { return JSON.parse(node.fs.readFileSync(f, 'utf8')); } catch { return null; } }; // 없음 · 깨짐 — 다시 뜬다
  const usable = t => !!t && t.v === CACHE_VERSION && t.icu === (process.versions.icu || '') && Array.isArray(t.years) && !!t.tables;
  const covers = t => usable(t) && t.years[0] <= loYear && hiYear <= t.years[1] && wanted.every(c => t.tables[c.id] && t.tables[c.id].intl === c.intl);
  const old = read(file);
  if (covers(old)) return old.tables;
  let target = file;
  const known = [old];
  if (file === sharedFile()) {
    target = sideFile();
    if (!target) return null; // 사본 자리를 모름 — 자료의 범위만 바로 뜬다
    const side = read(target);
    if (covers(side)) return side.tables;
    known.push(side);
    if (!sideNoted) {
      sideNoted = true;
      console.warn(`calendar: 공용 달력 표(${file})가 ${old ? `이 자료(${loYear} ~ ${hiYear}년) · ICU ${process.versions.icu || ''}에 맞지 않아` : '없어'} 갈지 않고 사본(${target})에 뜹니다 — 공용 표는 node prototype/scripts/warm-calendar.mjs로`);
    }
  }
  let lo = Math.floor(loYear / WIDEN_YEARS) * WIDEN_YEARS, hi = Math.ceil(hiYear / WIDEN_YEARS) * WIDEN_YEARS;
  for (const t of known.filter(usable)) {
    lo = Math.min(lo, t.years[0]);
    hi = Math.max(hi, t.years[1]);
  }
  try {
    return warmTables(HT, wanted, lo, hi, target).tables;
  } catch {
    return null; // 넓힌 범위에서 ICU가 답을 못 줌 — 자료의 범위만 바로 뜬다(지금처럼)
  }
}

export function contribute(ctx, out) {
  const { HT, model } = ctx;
  const [loYear, hiYear] = dataYears(model);
  const fromJ = HT.cal.jdnCivil(loYear, 1, 1);
  const toJ = HT.cal.jdnCivil(hiYear === -1 ? 1 : hiYear + 1, 1, 1);
  const wanted = wantedCalendars(HT);
  const notes = { 해범위: [loYear, hiYear], 달력: {} };
  let bytes = 0;
  const digests = new Map();
  const wide = cachedTables(HT, wanted, loYear, hiYear);
  for (const c of wanted) {
    const t0 = Date.now();
    const cut = wide && sliceTable(wide[c.id], c, fromJ, toJ);
    const table = cut || buildTable(HT, c, fromJ, toJ);
    const key = `${table.start}|${table.months}`;
    const same = digests.get(key);
    digests.set(key, same || c.id);
    const body = {
      cal: c.id, calName: c.name, lunar: !!c.lunar, prefix: c.prefix,
      from: table.start, to: table.end, year0: table.year0, count: table.count,
      months: table.months,
      // ICU가 달을 더 주지 못한 곳 · 다른 달력과 한 달도 다르지 않은 것(월흔해의 범위에서는 둘 다 없었다 —
      // 음력 ↔ 중국 음력은 211달, 이슬람력 ↔ 움 알쿠라는 1,525달이 다르다).
      note: [table.bad, same && same !== c.id ? `이 범위에서는 ${same}와 같은 답이다` : ''].filter(Boolean).join(' · '),
    };
    const json = JSON.stringify(body);
    bytes += json.length;
    out.entities.push({ uid: `cal:${c.id}`, kind: 'cal', json, pack: 0 }); // 표는 켠 자료 전체의 해 범위로 뜬다 — 기본 DLC(0)에 붙인다
    notes.달력[c.id] = { 달: table.count, 글자: json.length, ms: Date.now() - t0, 표: cut ? '잘라 씀' : '바로 뜸', 메모: body.note || undefined };
  }
  notes.글자합 = bytes;
  // 줄로 실었다면 얼마나 됐을지(견줄 값).
  notes.줄로실었다면 = wanted.reduce((s, c) => s + (notes.달력[c.id] ? notes.달력[c.id].달 * 24 : 0), 0);
  ctx.notes.calendar = notes;
}
