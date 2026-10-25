// 도읍 노선도 카드(명세 06의 4-2 · 7-19 · 지금 연표의 `js/timeline.js`의 `_metroHTML`)가 읽는 값을
// 항목 기록에 `x_metro`로 얹는 **늦은 차례**(contributeLate) — `docs.mjs`의 `x_docs`와 같은 틀이다.
//
// 왜 필요한가: 노선도 카드가 쓰는 것 가운데 셋은 **그 정권의 기록만으로는 알 수 없다.**
//   ① 환승(겹고리 · `⇄` 칩) — 같은 도시를 도읍으로 쓴 **다른 정권**들(지금 연표의 `tl._cityUses`).
//   ② 발의 다른 정권 단추(`← →`) — **같은 트랙**에서 도읍이 있는 정권들(지금 연표의 `tr.periods`).
//   ③ 머리의 기간 글 · 진행 중인가 — 항목 기록에는 `ongoing`이 참일 때만 실리고, 기간 글은 `HT.formatRange`가 만든다.
// 새 엔진은 모델을 올리지 않으므로 이 셋(과 칸의 날짜 글 · 다른 견해 글)을 **넣을 때 한 번** 풀어 둔다.
//
// 카드는 x_metro가 **없어도** 도읍 칸(`capitals`)만으로 본선 · 지선 · 우회를 그린다(조용히 비지 않는다).
// x_metro가 있으면 환승 · 다른 정권 단추 · 지금 연표와 똑같은 날짜 글이 더해진다.
//
// 싣는 곳: `{uid:"<정권 uid>", kind:"period"}` 기록의 json에 `x_metro` 하나(도읍이 없는 정권에는 싣지 않는다).
//   x_metro = {
//     range:  '기원전 960년 ~ 기원전 400년',   // HT.formatRange(p) — 머리의 기간 글
//     ongoing: 1,                              // 진행 중일 때만
//     end:    '960',                           // bcYear(p.endY) — 끝 역 아래의 작은 글
//     when:   ['720년 ~ 825년', …],            // 도읍 칸과 **같은 차례** — 역 설명글의 기간(cellRange(c,'endY',null,p))
//     alts:   {'5': ['824년: 기억고 이전을 …']},// 다른 견해가 있는 칸만(HT.altText — 앞의 '다른 견해 — '는 카드가 붙인다)
//     xfer:   {'파도문': [{uid,name,color,cell,year}, …]},  // 그 도시를 쓴 **다른** 정권들(차례는 지금 연표의 _cityUses 그대로)
//     peers:  [{uid,name,color}, …],           // 같은 트랙에서 도읍이 있는 정권(제 자신 포함 · 트랙의 차례 그대로)
//   }
// 시간 값은 싣지 않는다 — 카드는 도읍 칸의 해 좌표를 `date_text.dart`의 `minutesOfT`로 옮겨 `bus.goTo`에 넘긴다
// (지금 연표의 `setView(a - pad, b + pad)`가 해 좌표를 그대로 쓰는 것과 같은 값).
//
// 혼자 돌려 볼 때(MODULES에 'metro'가 아직 없을 때): 이미 내보낸 JSON에 얹기만 한다.
//   node prototype/scripts/export/metro.mjs prototype/results/compat/<이름>.json
import { loadContext, node } from './base.mjs'; // 노드 내장은 base.mjs의 `node`로만(브라우저에서는 null — 브라우저 겸용)

/** 빈 것(없음 · 빈 글 · 빈 목록 · 빈 표)은 싣지 않는다 — 기록이 부풀지 않게. */
const some = v => (v == null || v === '' || (Array.isArray(v) && !v.length) || (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length) ? null : v);

/** 한 도시를 쓴 다른 정권을 이만큼까지만 싣는다(설명글은 지금 연표도 넷까지만 적고 나머지는 '외 n'이다). */
const XFER_MAX = 12;

/** 지금 연표의 글 만드는 함수들을 그대로 쓴다(`js/timeline.js`의 `bcYear` · `cellRange` · `cellAltTip`). */
function tools(HT) {
  /** `js/timeline.js`의 `bcYear` — 역 이름 아래의 해. */
  const bcYear = y => (y < 0 ? `BC ${-HT.yearOf(y)}` : `${HT.yearOf(y)}`);
  /** `js/timeline.js`의 `cellRange(c, 'endY', null, p)` — 역 설명글의 기간. */
  const cellRange = (c, p) => {
    const s = c.startUnknown ? '미정' : HT.formatWhen(c, 'start');
    if (c.endUnknown || c.endYAuto) return `${s} ~ 미정`;
    if (c.toNow || HT.cellToNow(c, p)) return `${s} ~ 현재`;
    const ev = c.endY ?? null;
    if (ev == null) return `${s} ~`;
    return `${s} ~ ${HT.formatDate(ev, c.endYAt || c.endAt)}`;
  };
  /** `js/timeline.js`의 `cellAltTip` — 앞의 '다른 견해 — '는 카드가 붙이므로 여기서는 글만. */
  const cellAlts = c =>
    ((c && c.alternatives) || []).map(a =>
      HT.altText(a, { start: c.start, startAt: c.startAt, end: c.endY ?? c.end, endAt: c.endYAt || c.endAt, startUnknown: c.startUnknown, endUnknown: c.endUnknown }),
    );
  return { bcYear, cellRange, cellAlts };
}

/**
 * 정권 하나의 x_metro를 만든다. [cityUses]는 지금 연표의 `tl._cityUses`(도시 → [{p, c}]),
 * [peersOf]는 트랙 id → 도읍이 있는 정권 목록. 도읍이 없으면 null.
 */
export function metroOf(HT, p, cityUses, peersOf) {
  const caps = p.capitals || [];
  if (!caps.length) return null;
  const { bcYear, cellRange, cellAlts } = tools(HT);

  const when = caps.map(c => cellRange(c, p));
  const alts = {};
  caps.forEach((c, i) => {
    const list = cellAlts(c);
    if (list.length) alts[i] = list;
  });

  const xfer = {};
  for (const c of caps) {
    if (!c.city || xfer[c.city]) continue;
    const others = (cityUses.get(c.city) || []).filter(u => u.p !== p);
    if (!others.length) continue;
    const list = others.slice(0, XFER_MAX).map(u => ({
      uid: u.p.uid,
      name: u.p.name || '',
      color: u.p.color || '',
      cell: u.c.name || u.c.city || '',
      year: u.c.startUnknown ? '미정' : bcYear(u.c.start),
    }));
    // 잘렸으면 '외 n'이 지금 연표와 같은 수가 되게 전체 수를 함께 싣는다(첫 칸에만 적는다).
    if (others.length > list.length) list[0].all = others.length;
    xfer[c.city] = list;
  }

  const peers = (peersOf.get(p.track) || []).map(q => ({ uid: q.uid, name: q.name || '', color: q.color || '' }));

  const out = { range: HT.formatRange(p), end: bcYear(p.endY), when };
  if (p.ongoing) out.ongoing = 1;
  if (some(alts)) out.alts = alts;
  if (some(xfer)) out.xfer = xfer;
  if (peers.length > 1) out.peers = peers; // 하나뿐이면 발에 단추가 서지 않는다
  return out;
}

/** 지금 연표의 `setData`가 만드는 두 표(도시 → 쓰임 · 트랙 → 도읍이 있는 정권)를 그대로.
    발의 단추는 `_metroHTML`이 `this.tracks.find(t => t.id === p.track).periods`에서 고르므로 **줄을 쌓은 뒤의 차례**를 쓴다. */
function indexes(ctx) {
  const { tl } = ctx;
  const cityUses = tl && tl._cityUses ? tl._cityUses : new Map();
  const peersOf = new Map();
  for (const tr of tl.tracks) {
    const list = tr.periods.filter(q => q.capitals && q.capitals.length);
    if (list.length) peersOf.set(tr.id, list);
  }
  return { cityUses, peersOf };
}

/** 모든 모듈이 제 몫을 실은 뒤 — 남이 실은 항목 기록에 x_metro를 얹는다(`docs.mjs`와 같은 차례). */
export function contributeLate(ctx, out) {
  const { HT, model } = ctx;
  const { cityUses, peersOf } = indexes(ctx);
  const byUid = new Map(model.periods.map(p => [p.uid, p]));
  let hit = 0;
  let 환승 = 0;
  for (const e of out.entities) {
    if (e.kind !== 'period') continue;
    const p = byUid.get(e.uid);
    if (!p) continue;
    const x = metroOf(HT, p, cityUses, peersOf);
    if (!x) continue;
    const json = JSON.parse(e.json);
    json.x_metro = x;
    e.json = JSON.stringify(json);
    hit++;
    환승 += Object.keys(x.xfer || {}).length;
  }
  ctx.notes.노선도 = { 도읍_있는_정권: hit, 환승_도시: 환승 };
}

/** `contribute`는 제 몫이 없다 — 늦은 차례에만 일한다(MODULES에 이름을 더해도 두 번 돌지 않게). */
export function contribute() {}

// ── 혼자 돌려 보기 ─────────────────────────────────────────────────────────────────────────────
// MODULES에 'metro'가 아직 없을 때, 이미 내보낸 JSON에 x_metro만 얹는다(제자리에 다시 쓴다).
if (node && process.argv[1] && import.meta.url === node.url.pathToFileURL(process.argv[1]).href) {
  const { fs, path } = node;
  const file = process.argv[2];
  if (!file) {
    console.error('쓰는 법: node prototype/scripts/export/metro.mjs <내보낸 layout json>');
    process.exit(1);
  }
  const full = path.resolve(file);
  const out = JSON.parse(fs.readFileSync(full, 'utf8'));
  const ctx = await loadContext();
  ctx.notes = {};
  contributeLate(ctx, out);
  fs.writeFileSync(full, JSON.stringify(out) + '\n');
  console.log(JSON.stringify({ 파일: full, 기록: ctx.notes }, null, 1));
}
