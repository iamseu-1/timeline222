// 정권 띠. 2단계의 값(자리 · 기간 · 색 · 이름)에서 출발해 그 모습(계약 6절의 look · tag · sub)을 더한다.
// 모습은 지금 연표 _drawTrack이 띠에 붙이는 클래스(kind-* · 확실성 · 연대 폭 · 실재성 · 종속 갈래 · 깃대 · 망명 · 바탕 문화)와
// 책갈피 탭의 딱지(tabParts)를 비트로 옮긴 것이다 — 화면에 달린 값(잘림 · 조명 · 흐림)은 싣지 않는다.
// 띠에 딸린 일반 항목: 구역 19(연대 폭) · 58(소속 구간의 정통성 — 4단계 배치 갈래 · 계약 1-1 덧붙임).
import { assert } from './base.mjs'; // 노드에서는 node:assert/strict 그대로(브라우저 겸용 — base.mjs 머리말)
import { minute, color } from './base.mjs';

/** 띠 종류 번호(계약 6절) — 지금 연표의 KIND_ORDER + 시대와 별개인 종류(문화 · 기관 · 왕조) */
export const KIND_NO = {
  state: 0, tributary: 1, fief: 2, dominion: 3, warlord: 4, vassal: 5, protectorate: 6, satellite: 7,
  puppet: 8, mandate: 9, colony: 10, occupied: 11, federation: 12, org: 13, era: 14, exile: 15, movement: 16,
  culture: 17, overlay: 18, dynasty: 19,
  // 묶음 3 · 3번(2026-09-22): 시대마다의 특별한 형태 — 번호는 뒤에 이어 붙인다(옛 저장소의 번호가 바뀌지 않게). 5비트라 31까지
  client: 20, frontier: 21, prefecture: 22,
};
/** 책갈피 탭의 종류 딱지 — 지금 연표의 KIND_SHORT(js/timeline.js:563) 그대로.
 *  종류 표(HT.POLITY_KINDS)의 short에 없는 문화 · 기관이 여기에서 붙고, 겹치는 것은 이 표가 이긴다(지금 연표와 같은 차례). */
const KIND_SHORT = { vassal: '종속', federation: '연맹', org: '조직', era: '시대', culture: '문화', overlay: '기관' };
/** 연대의 확실성 번호 — HT.CERTAINTY의 차례 */
const CERT_NO = { certain: 0, accepted: 1, estimated: 2, legend: 3 };
/** 실재성 번호 — HT.HISTORICITY의 차례 */
const HS_NO = { attested: 0, semi: 1, legendary: 2, disputed: 3, refuted: 4 };

/** 형식 4 종류 번호(계약 1-1 초안 · 설계 3-11 초안의 차례) — 띠의 form 0 ~ 4비트에 번호 + 1로 */
export const TYPE_NO = {
  state: 0, federation: 1, principality: 2, city: 3, government: 4, regime: 5, dependency: 6, warlord: 7, organization: 8,
  faith: 9, order: 10, company: 11, office: 12, group: 13, era: 14, realm: 15, union: 16, league: 17, person: 18,
};
/** 관계 번호(계약 1-1 초안) — 띠에는 옛 종속 kind의 관계만 싣는다(명목상 · 구성국 · 동군연합은 소속선 구역 22가 말함) */
export const REL_NO = {
  tributary: 1, fief: 2, dominion: 3, vassal: 4, protectorate: 5, satellite: 6, puppet: 7, mandate: 8, colony: 9, occupied: 10,
  client: 11, frontier: 12, prefecture: 13,
};
/** 정통성 번호 + 1(0 = 비움) — HT.F4.STATUSES의 차례. 띠의 form 10 ~ 12 · 구역 57(칸의 정통성 — strips.mjs) · 58(소속 구간의 정통성 — 아래)이 함께 쓴다 */
export const STATUS_NO = { legit: 1, rival: 2, joint: 3, regent: 4, nominal: 5, claim: 6 };
/** 칸 · 소속의 status → 정통성 번호 + 1(4단계 배치 갈래 — 표에 제 이름으로 있는 글만 · 그 밖은 0 = 싣지 않음) */
export const statusNoOf = v => (typeof v === 'string' && Object.prototype.hasOwnProperty.call(STATUS_NO, v) ? STATUS_NO[v] : 0);
/** 소속 구간의 정통성 — 일반 항목 구역 58(4단계 배치 갈래 · 계약 1-1 덧붙임 · 감독 결정 LEGIT 가) */
export const SECTION_HOST_STATUS = 58;
/** 그림 띠(객체가 아님) — form의 종류는 0(모름) */
const DRAWN_ONLY = new Set(['culture', 'overlay', 'dynasty']);
/** form(리메이크 3단계 · 계약 1-1 초안): 0 ~ 4 형식 4 종류 + 1 · 5 ~ 9 관계 · 10 ~ 12 정통성 + 1 · 13 ~ 15 중요도 + 1.
    종류 = 적힌 type(정규화가 지킨 것 — 옛 종류로 되살릴 수 없을 때만 적힘) → 단체의 띠(groupUid — 실권 정권은 옛 군벌로 내려 옴) → 옛 kind에서 되살림(HT.F4.typeOfKind). */
export function formOf(HT, p, kind) {
  let type = '';
  if (!DRAWN_ONLY.has(kind)) {
    if (p.type && p.type in TYPE_NO) type = p.type;
    else if (p.groupUid) type = kind === 'warlord' ? 'regime' : 'organization';
    else type = HT.F4.typeOfKind(kind);
  }
  const imp = [0, 1, 2, 3].includes(p.importance) ? p.importance + 1 : 0;
  return (type in TYPE_NO ? TYPE_NO[type] + 1 : 0) | ((REL_NO[kind] || 0) << 5) | ((STATUS_NO[p.status] || 0) << 10) | (imp << 13);
}

/** look: 아래 5비트 종류 · 5~6 확실성 · 7 연대 폭 · 8~10 실재성 · 11~18 모습 · 19 사건 있음 · 20 칸 있음 · 21~29 가진 칸 층(두 장 꼬리표의 몸통 — tracks.mjs의 늦은 차례가 켬) */
const L = {
  kind: 0x1f, cert: 5, range: 1 << 7, hs: 8,
  dep: 1 << 11, flag: 1 << 12, exile: 1 << 13, under: 1 << 14, underHead: 1 << 15,
  folded: 1 << 16, member: 1 << 17, hollow: 1 << 18,
};

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const skipped = { hidden: 0, overlay: 0, noRow: 0 };
  const bandOf = (ctx.shared.bandOf = new Map()); // 띠의 uid → out.periods의 순번(바탕 문화는 첫 줄의 것)
  const counts = { 보통: 0, 바탕문화: 0, 바탕문화_덧줄: 0, 연대폭: 0, 소속정통성: 0 };

  tl.tracks.forEach((tr, trackIndex) => {
    /* 바탕 문화(승계국 줄 밑에 깔리는 띠)도 같은 줄의 띠와 겹친 채 그대로 싣는다 — 깔리는 줄이 여럿이면 줄마다 하나씩.
       둘째 줄부터는 uid 뒤에 #u<줄>을 붙여 가리키는 곳이 헷갈리지 않게 한다(칸 · 항목 기록은 첫 줄의 uid를 쓴다). */
    const list = tr.periods.filter(p => !p._overlay);
    for (const p of list) {
      if (p._hidden) { skipped.hidden++; continue; }
      const rows = p._under ? (p._underRows || []) : p._row == null || p._row < 0 || p._row >= tr.rows ? [] : [p._row];
      if (!rows.length) { skipped.noRow++; continue; }
      const start = minute(p.start), end = minute(p.endY);
      assert.ok(start != null && end != null && start <= end, `띠의 기간 오류: ${p.name}`);
      const kind = p.polityKind || 'state';
      const cert = p.certainty || 'accepted';
      const ranges = [p.startRange, p.endRange].filter(Boolean);
      const hs = HT.historicityOf(p) || 'attested';
      const dep = p._dep || null;
      const form = formOf(HT, p, kind);
      let look =
        (KIND_NO[kind] ?? 0) |
        ((CERT_NO[cert] ?? 1) << L.cert) |
        (ranges.length ? L.range : 0) |
        ((HS_NO[hs] ?? 0) << L.hs) |
        (HT.kindFamily(kind) === 'dependent' ? L.dep : 0) |
        (kind === 'movement' ? L.flag : 0) |
        (kind === 'exile' ? L.exile : 0) |
        (p._under ? L.under : 0) |
        (p._folded ? L.folded : 0) |
        (p._member ? L.member : 0) |
        (tl._hosted && tl._hosted.has(p.uid) ? L.hollow : 0);

      /* 책갈피 탭의 딱지: 이름 뒤에 차례로 종류 → 실재성 → 지위. 무엇까지 들어가는지는 폭에 달렸으므로(tabParts) 후보를 모두 싣고 그리는 쪽이 고른다 */
      // 단체의 띠(리메이크 조각 ④ — core.js groupBands)는 단체의 갈래(붕당 · 정당 · 세력 …)를 딱지로
      const short = p.groupKind || KIND_SHORT[kind] || (HT.POLITY_KINDS.find(k => k.id === kind) || {}).short || '';
      const tags = [];
      if (HT.kindFamily(kind) !== 'dependent' && short) tags.push(short);
      const hsTag = HT.historicityTag(hs);
      if (hsTag) tags.push(hsTag);
      const geo = tr.geos[rows[0]] || tr.geo;
      const rk = !geo.rankH && p.rankSpans && p.rankSpans.length === 1 ? p.rankSpans[0] : null; // 지위 단이 없는 줄의 지위 딱지(tabRank)
      if (rk) tags.push(rk.name || '');
      const sub =
        (rk ? Math.min(7, (rk.level || 0) + 1) : 0) |
        (ranges.length ? 1 << 6 : 0) |
        (Math.min(31, (dep && dep.outLanes) || 0) << 7) |
        (Math.min(31, (dep && dep.inLanes) || 0) << 12);

      rows.forEach((r, k) => {
        const uid = k === 0 ? p.uid : `${p.uid}#u${r}`;
        if (k === 0) bandOf.set(p.uid, out.periods.length);
        out.periods.push({
          uid, track: trackIndex, row: r, start, end,
          fuzzy: (p.startUnknown ? 1 : 0) | (p.endUnknown ? 2 : 0),
          color: color(p.color), name: p.name || '',
          look: look | (p._under && k === 0 ? L.underHead : 0), tag: tags.join('|'), sub, form,
        });
        if (p._under) counts[k === 0 ? '바탕문화' : '바탕문화_덧줄']++;
        else counts.보통++;
      });

      /* 연대 폭(흐린 끝 — 확실한 경계가 아니라 '이 사이 어딘가'): 구간이 있어야 그릴 수 있으므로 일반 항목 19로 (계약 6절) */
      for (const [side, rg] of [[0, p.startRange], [1, p.endRange]]) {
        if (!rg) continue;
        const s = minute(rg[0]), e = minute(rg[1]);
        if (s == null || e == null || e < s) continue;
        out.items.push({
          section: 19, track: trackIndex, row: rows[0], row2: rows[0], start: s, end: e, lod: -1,
          ref: p.uid, name: '', color: color(p.color),
          // 무늬는 지금 연표의 zoneKind(확실성이 통설이면 추정의 무늬)와 같게
          a: side, b: cert === 'legend' ? 1 : cert === 'certain' ? 2 : 0, c: 0, d: 0, text2: '',
        });
        counts.연대폭++;
      }

      /* 소속 구간의 정통성(구역 58 — 4단계 배치 갈래 · 계약 1-1 덧붙임 · 감독 결정 LEGIT 가): 소속 한 건(hosts 차례 k — 구역 47의 b와 같음)에 status가 있으면 하나.
         구간 = 그 소속의 시작 ~ 끝(적지 않았으면 띠의 시작 · 끝)을 띠의 구간으로 자른 것 · name · color · text2 = 상위 · a 0(1은 시대 그릇 소속의 몫) · d = 정통성 번호 + 1.
         바탕 문화의 덧줄에는 싣지 않는다(첫 줄 하나). 접힌 소속(상위 띠 아래에 접힘)은 기본 배치에 띠가 없어 소속 펼치기 변형 판에만 실린다(variants.mjs가 이 모듈을 다시 돌림) */
      (p.hosts || []).forEach((h, k) => {
        const no = h ? statusNoOf(h.status) : 0;
        if (!no) return;
        const hs = minute(h.start ?? p.start), he = minute(h.end ?? p.endY);
        if (hs == null || he == null) return;
        const a = Math.max(hs, start), b = Math.min(he, end);
        if (b < a) return;
        const q = h.host || {};
        out.items.push({
          section: SECTION_HOST_STATUS, track: trackIndex, row: rows[0], row2: rows[0], start: a, end: b, lod: -1,
          ref: p.uid, name: q.name || '', color: color(q.color), a: 0, b: k, c: 0, d: no, text2: q.uid || '',
        });
        counts.소속정통성++;
      });
    }
    for (const p of tr.periods) if (p._overlay) skipped.overlay++;
  });
  ctx.notes.띠 = counts;
  ctx.notes.띠에서_뺀_것 = skipped;
}
