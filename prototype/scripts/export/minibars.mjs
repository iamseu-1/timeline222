// 접힌 트랙 · 접힌 민족 줄의 '가는 막대'(`.tl-mini-bar`)가 쓸 단(위아래 줄)을 띠마다 미리 정해 싣는다.
// 단은 화면이 아니라 **자료**로 정한다(원칙 ① — 옆으로 옮겨도 막대가 단을 바꾸지 않게). 규칙은 지금 연표의
// `_layoutTrack`의 `assignLanes`(js/timeline.js 2754~2764) 그대로다: 시작 오름차순 → 끝 내림차순으로 늘어놓고
// 앞이 끝난 첫 단에, 세 단이 다 차면 가장 먼저 끝나는 단에 겹쳐 얹는다.
//
// 싣는 곳은 일반 항목 구역 **45**(계약 6-11절 — 39~44는 인물 · 칸 · 이름표 작업자가 이미 썼다): `{ref: 띠의 uid, row, start, end, a: laneAll, b: laneRow, color}`.
//   a = 접힌 **트랙**용(`_laneAll` — 그 트랙의 모든 정권으로 한 번)
//   b = 접힌 **민족 줄**용(`_laneRow` — 그 줄의 정권으로만. 민족을 접으면 묶음의 줄이 하나로 합쳐지므로
//       묶음마다 그 묶음의 모든 정권을 시작 순으로 모아 셈한다 — 접었을 때와 같은 목록이다)
import { minute, color as rgb } from './base.mjs';

export const SECTION = { mini: 45 };

// 띠의 바깥 끝(연대 폭을 품은 해) — 지금 연표의 bandStart · bandEnd(js/timeline.js 304)와 같다.
const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);

/** 지금 연표의 assignLanes(2755) 그대로: 목록에 단 번호를 매겨 Map으로 돌려준다. */
export function assignLanes(list, lanes = 3) {
  const ends = [];
  const out = new Map();
  for (const p of list.slice().sort((a, b) => bandStart(a) - bandStart(b) || bandEnd(b) - bandEnd(a))) {
    let lane = ends.findIndex(end => end <= bandStart(p));
    if (lane < 0) lane = ends.length >= lanes ? ends.indexOf(Math.min(...ends)) : ends.push(-Infinity) - 1;
    ends[lane] = Math.max(ends[lane], bandEnd(p));
    out.set(p.uid, lane);
  }
  return out;
}

export function contribute(ctx, out) {
  const { tl } = ctx;
  const count = { 막대: 0, 트랙단: [0, 0, 0], 줄단: [0, 0, 0] };
  tl.tracks.forEach((tr, track) => {
    const shown = (tr.periods || []).filter(p => !p._hidden && !p._overlay && !p._under);
    const all = assignLanes(shown);
    // 접힌 민족 줄: 묶음을 접으면 그 묶음의 줄들이 하나로 합쳐진다 — 묶음마다 제 정권을 모아 한 번 셈한다.
    // 묶음에 들지 않는 줄은 제 줄만으로(그 줄 하나가 접힐 일은 없지만 값이 비지 않게).
    const row = new Map();
    const done = new Set();
    for (const gp of tr.groups || []) {
      const list = [];
      for (let r = gp.first; r < gp.first + gp.count; r++) {
        for (const p of tr.rowPeriods[r] || []) if (!p._hidden) list.push(p);
        done.add(r);
      }
      for (const [uid, lane] of assignLanes(list)) row.set(uid, lane);
    }
    for (let r = 0; r < (tr.rowPeriods || []).length; r++) {
      if (done.has(r)) continue;
      const list = (tr.rowPeriods[r] || []).filter(p => !p._hidden);
      for (const [uid, lane] of assignLanes(list)) row.set(uid, lane);
    }
    for (const p of shown) {
      if (p._row == null) continue;
      const a = all.get(p.uid) || 0;
      const b = row.has(p.uid) ? row.get(p.uid) : 0;
      const s = minute(bandStart(p)), e = Math.max(s, minute(bandEnd(p)));
      out.items.push({
        section: SECTION.mini, track, row: p._row, row2: p._row, start: s, end: e, lod: -1,
        ref: p.uid, name: p.name || '', color: rgb(p.color), a, b, c: 0, d: 0, text2: '',
      });
      count.막대++;
      count.트랙단[a]++;
      count.줄단[b]++;
    }
  });
  ctx.notes.가는막대 = count;
}
