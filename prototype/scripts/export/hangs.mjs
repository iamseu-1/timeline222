// 띠 밖에 덧붙는 것 → 일반 항목(items): 16 속국 이름표(매달린 탭 · 세로 끈) · 17 구역 탭 · 18 바탕 문화의 아래 이름 단 · 44 이름표의 모호한 연대 ·
// 47 뒤 장의 탭(속국 띠 위, 그 나라가 섬긴 상국의 간지 탭 — 묶음 3 · 1번) · 48 상국 띠의 속국 접기 단추(건의 8의 나).
// 구역 번호와 a~d · text2의 뜻은 계약 6절. 탭의 줄(a)은 0이 띠 아랫변에 가장 가깝고, 구역 탭은 매달린 이름표 줄 뒤에 이어 센다.
import { minute, color } from './base.mjs';

const SEC = { hang: 16, zone: 17, hem: 18, vague: 44, alt: 45, hostTab: 47, hangBtn: 48 };
/** 뒤 장의 탭의 모습(a) — 지금 연표의 depLook 그대로(상국 띠의 이름표와 같은 자) */
const HOST_LOOK = { loose: 0, firm: 1, nominal: 2, plain: 3, held: 4, owned: 5, occupied: 6 };
/** 매달린 이름표의 모습(b) — 지금 연표의 depLook */
const HANG_LOOK = { loose: 0, firm: 1, nominal: 2, plain: 3 };
const HANG_LINK = 4; // b = 4 — 밖 ↔ 안을 옮긴 속국의 세로 끈
/** 매달린 이름표의 style(c) */
const C = { unkS: 1, unkE: 2, joinL: 4, inSide: 8, vagueEst: 16, vagueLeg: 32, hasRange: 64 };

/** 띠가 그려지는 해 범위 — 연대 폭이 있으면 그 바깥 끝까지(timeline.js의 bandStart · bandEnd) */
const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);

/** 이설이 말하는 경계 해 [{ y, side }] — js/timeline.js의 altEdges 그대로(통설과 같은 해 · 뒤집힌 이설은 뺀다) */
const altEdges = (HT, c, base, now) => {
  const out = [];
  const push = (y, side) => {
    if (y == null || !isFinite(y) || out.some(q => Math.abs(q.y - y) < 1e-9)) return;
    out.push({ y, side });
  };
  for (const a of (c && c.alternatives) || []) {
    if (!HT.altDated(a) || HT.altFlipped(a, base)) continue;
    const f = HT.altSpan(a, base);
    if (f.own.start && f.start != null && base.start != null && Math.abs(f.start - base.start) > 1e-9) push(f.start, 's');
    const e = f.ongoing ? now : f.end;
    if (f.own.end && e != null && base.end != null && Math.abs(e - base.end) > 1e-9) push(e, 'e');
  }
  return out;
};

/** 단계 · 통 산수(engine/src/levels.rs의 lod_of와 같은 식) — 이름표에 딸린 항목은 그 조각과 같은 단계까지 실린다. */
const lodOf = duration => {
  const wide = Math.max(0, duration) * 8;
  for (let level = 14; level >= 0; level--) if (wide >= 4 ** level) return level;
  return 0;
};

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const bandOf = ctx.shared.bandOf || new Map(); // 띠의 uid → out.periods의 순번(bands.mjs) — 띠 번호는 순번 + 1
  const idOf = uid => (bandOf.has(uid) ? bandOf.get(uid) + 1 : 0);
  const counts = { 속국이름표: 0, 세로끈: 0, 구역탭: 0, 바탕문화이름: 0, 모호한연대: 0, 이설경계: 0, 뒤장탭: 0, 속국접기단추: 0 };
  const item = o => out.items.push(Object.assign({ section: 0, track: 0, row: 0, row2: 0, start: 0, end: 0, lod: -1, ref: '', name: '', color: 0, a: 0, b: 0, c: 0, d: 0, text2: '' }, o));

  tl.tracks.forEach((tr, track) => {
    const drawn = p => !p._folded && !p._hidden && !p._under && !p._overlay && p._row != null && p._row >= 0 && p._row < tr.rows && !tr.foldedRows.has(p._row);

    /* 속국 이름표: 상국 띠 아래에 매달린 탭(스스로 다스린 관계 — 빈 · 칠한 · 점선 · 파선) */
    for (const p of tr.periods) {
      if (!drawn(p) || !p._dep || !p._dep.outLanes) continue;
      const row = p._row;
      for (const it of p._dep.items) {
        if (!it.out) continue;
        const lane = it.outLane || 0;
        let prev = null;
        for (const s of it.segs) {
          if (s.side !== 'out') { prev = s; continue; }
          const start = minute(s.a), end = minute(s.b);
          if (start == null || end == null || end < start) { prev = s; continue; }
          /* 모호한 연대(디테일 건의 4 · altRowPlan의 zones): 연대 폭을 적었으면 그 구간만(구역 44),
             폭 없이 확실성만 적었으면 그 조각 전체가 무늬다. 무늬는 전승이면 빗금, 그 밖(추정 · 통설)이면 세로 줄(zoneKindOf). */
          const ranges = [s.h.startRange, s.h.endRange].filter(Boolean);
          const legend = s.h.certainty === 'legend';
          const vague = !ranges.length && (legend || s.h.certainty === 'estimated') ? (legend ? C.vagueLeg : C.vagueEst) : 0;
          item({
            section: SEC.hang, track, row, row2: row, start, end, ref: p.uid, name: it.p.name || '', color: color(it.p.color),
            a: lane, b: HANG_LOOK[s.look] ?? 3,
            c: (s.h.startUnknown ? C.unkS : 0) | (s.h.endUnknown ? C.unkE : 0) | (prev && prev.side === 'out' ? C.joinL : 0) | vague | (ranges.length ? C.hasRange : 0),
            d: idOf(it.p.uid), text2: it.p.uid,
          });
          counts.속국이름표++;
          for (const [side, rg] of [[0, s.h.startRange], [1, s.h.endRange]]) {
            if (!rg) continue;
            const a = minute(rg[0]), b = Math.max(a, minute(rg[1]));
            if (a == null) continue;
            item({
              section: SEC.vague, track, row, row2: row, start: a, end: b, lod: lodOf(end - start), ref: p.uid, color: color(it.p.color),
              a: lane, b: legend ? 1 : 0, c: side, d: idOf(it.p.uid), text2: it.p.uid,
            });
            counts.모호한연대++;
          }
          /* 구역 45 — 이설이 말하는 경계(유령 구분선). start가 선의 자리이고 end는 그 조각의 끝이다(단계 셈과 타일 고르기에만). */
          const base = { start: s.a, end: s.b, startUnknown: s.h.startUnknown, endUnknown: s.h.endUnknown };
          for (const m of altEdges(HT, s.h, base, it.p.endY)) {
            const at = minute(m.y);
            if (at == null) continue;
            item({
              section: SEC.alt, track, row, row2: row, start: at, end: Math.max(at, end), lod: lodOf(end - start), ref: p.uid, color: color(it.p.color),
              a: lane, b: m.side === 'e' ? 1 : 0, c: 0, d: idOf(it.p.uid), text2: it.p.uid,
            });
            counts.이설경계++;
          }
          prev = s;
        }
        /* 밖 ↔ 안으로 옮긴 때: 이어진 두 구간의 경계에 세로 끈 하나(매달린 탭의 가운데 ↔ 품은 칸의 가운데).
           끈은 뒤 조각의 시작에 그린다 — 기간은 뒤 조각의 것(단계 셈이 그 조각과 같게) */
        if (it.out && it.inn) {
          for (let k = 1; k < it.segs.length; k++) {
            const a = it.segs[k - 1], b = it.segs[k];
            if (a.side === b.side || Math.abs(a.b - b.a) > 1e-9) continue;
            const start = minute(b.a), end = minute(b.b);
            if (start == null || end == null || end < start) continue;
            item({
              section: SEC.hang, track, row, row2: row, start, end, ref: p.uid, name: '', color: color(it.p.color),
              a: lane, b: HANG_LINK, c: b.side === 'in' ? C.inSide : 0, d: (it.inLane || 0) + 1, text2: it.p.uid,
            });
            counts.세로끈++;
          }
        }
      }
    }

    /* 상국 띠의 속국 접기 단추(구역 48 — 건의 8의 나 · 감독 2026-10-14 "종주국 띠에 접기 하나"): 매달린 이름표가 있는 상국 띠마다 하나 — 지금 연표의 .tl-hangbtn '▾ 속국 n'.
       구간 = 상국 띠(연대 폭의 바깥 끝까지) · a = 매달린 속국 수(그 상국 아래 밖에 매달린 속국 — 조각 수가 아니라 나라 수). 자리(첫 글줄 · 소속 단추 · 네모 뒤)와
       접힘 상태(그 상국의 매달린 줄을 덧붙는 높이에서 뺌)는 그리는 쪽의 몫이다. 내보내기는 아무것도 접지 않은 상태라 모두 펼침 */
    for (const p of tr.periods) {
      if (!drawn(p) || !p._dep || !p._dep.outLanes) continue;
      const start = minute(bandStart(p)), end = minute(bandEnd(p));
      if (start == null || end == null || end < start) continue;
      item({
        section: SEC.hangBtn, track, row: p._row, row2: p._row, start, end, lod: -1, ref: p.uid, name: '', color: color(p.color),
        a: p._dep.items.filter(it => it.out).length, b: 0, c: 0, d: 0, text2: '',
      });
      counts.속국접기단추++;
    }

    /* 뒤 장 · 상국 탭(구역 47 — 묶음 3 · 1번 L, 2026-09-22 → 건의 8의 2번 C, 2026-10-14): 제 줄에 선 속국의 띠 뒤에 그 나라가 섬긴 상국 빛깔의 뒤 장(관계 구간 · 위로 5px),
       그 평평한 윗변의 관계가 끝나는 쪽에 상국 탭. 자리(탭 오른쪽 끝 = min(뒤 장 끝 − 10, 화면 오른쪽 − 6) · 뒤 장 왼쪽 + 10과 제 이름 탭 · 앞 탭 뒤에만 · 안 되면 뒤 장만)는
       그리는 쪽이 장면마다 정한다(timeline.js의 _hostTabPlan · _hostPlates — 새 앱 bands.dart의 paintHostSheets · _paintHostTabs) —
       여기에는 소속 한 건마다 그 구간과 상국 · 모습만 싣는다. 상국은 띠로 그려지는 정권일 때만(왕조 · 기관 · 문화는 뺌), 상위 띠 아래에 접힌 소속(singleHost)은 없다 */
    for (const p of tr.periods) {
      if (!drawn(p) || !p.hosts || !p.hosts.length || p.singleHost) continue;
      p.hosts.forEach((h, k) => {
        const q = h.host;
        if (!q || q.polityKind === 'overlay' || q.polityKind === 'dynasty' || q.polityKind === 'culture') return;
        // 구간 = 섬긴 관계의 시작 ~ 끝(적지 않았으면 속국 띠의 시작 · 끝). 상국이 서기 전 · 없어진 뒤로는 나가지 않는다
        // (감독 2026-10-15 "시작점은 포함 시작 시기, 끝나는 점은 포함 제외 시기" — 끝을 적지 않은 관계가 상국보다 오래 이어지던 것)
        const s = Math.max(h.start ?? p.start, q.start ?? -Infinity), e = Math.min(h.end ?? p.endY, q.endY ?? Infinity);
        if (!(e > s)) return;
        const start = minute(s), end = minute(e);
        if (start == null || end == null || end < start) return;
        const look = HT.Timeline.depLook(p, h).look;
        item({
          section: SEC.hostTab, track, row: p._row, row2: p._row, start, end, ref: p.uid, name: q.name || '', color: color(q.color),
          a: HOST_LOOK[look] ?? 3, b: k, c: 0, d: idOf(q.uid), text2: q.uid,
        });
        counts.뒤장탭++;
      });
    }

    /* 구역 탭(조계지 · 조차지): 얹히는 시대 띠 아래로 살짝 내려오는 작은 탭 — 매달린 이름표 줄 뒤에 이어 센다 */
    for (const p of tr.overlays || []) {
      if (p.scale !== 'zone') continue;
      for (const h of p.hosts || []) {
        let host = tr.periods.find(q => q.uid === h.host.uid) || null;
        while (host && host._hidden) host = host._host;
        if (!host || host._row == null || tr.foldedRows.has(host._row)) continue;
        // 지금 연표(timeline.js:6701~6706)와 같은 구간 — 연대 폭이 있으면 그 바깥 끝까지
        const s = Math.max(bandStart(p), h.start ?? -Infinity, bandStart(host));
        const e = Math.min(bandEnd(p), h.end ?? Infinity, bandEnd(host));
        if (e <= s) continue;
        const start = minute(s), end = minute(e);
        if (start == null || end == null || end < start) continue;
        const row = host._row;
        item({
          section: SEC.zone, track, row, row2: row, start, end, ref: host.uid, name: p.name || '', color: color(p.color),
          a: (tr.hangRowLanes.get(row) || 0) + (p._zoneLane[h.host.uid] ?? 0), text2: p.uid,
        });
        counts.구역탭++;
      }
    }

    /* 바탕 문화의 아래 이름 단(hem): 깔린 첫 줄의 띠 밑에 '이름 + 문화' — 띠 자체는 bands.mjs가 싣는다 */
    for (const p of tr.underlays || []) {
      const rows = p._underRows || [];
      if (!rows.length) continue;
      // 바탕 문화의 좌우는 띠와 같다 — 연대 폭이 있으면 그 바깥 끝까지(지금 연표의 .tl-under도 bandStart · bandEnd)
      const start = minute(bandStart(p)), end = minute(bandEnd(p));
      if (start == null || end == null || end < start) continue;
      item({
        section: SEC.hem, track, row: rows[0], row2: rows[0], start, end, ref: p.uid, name: p.name || '', color: color(p.color),
        a: 0, b: 0, c: rows.length, d: 0, text2: '문화',
      });
      counts.바탕문화이름++;
    }
  });
  ctx.notes.덧붙는_것 = counts;
}
