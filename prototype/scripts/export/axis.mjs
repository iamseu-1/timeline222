// 맨 위 날짜 칸(계약 1절 axis_cells · 4절 axis): 시대 구분 · 연호 · 도읍 · 배도.
// 지금 연표의 _buildAxis()를 그대로 불러(화면 없이 — base가 axisEl · axisOpen을 채워 둔다) 그것이 정한 줄 · 단 · 갈래를 그대로 싣는다.
import { minute, color } from './base.mjs';
import { LINE, pushLine } from './persons.mjs';

const KIND = { epoch: 1, era: 2, capital: 3, secondary: 4 };
/** 칸의 모습(계약 6-3절): 1 시작 미정 · 2 끝 미정 · 4 임시 도읍 · 8 망명 · 16 공동 정도 · 32 이설 있음 */
const ST = { unkS: 1, unkE: 2, temporary: 4, exile: 8, co: 16, variant: 32 };

/** 그 칸에 연대를 말하는 다른 견해(이설)가 있는가 — 지금 연표의 `HT.altDated`(js/core.js 1366줄) 그대로 */
const altDated = a => !!a && (a.start != null || a.end != null || a.ongoing === true || a.birth != null || a.death != null);
const hasVariant = c => !!(c && (c.alternatives || []).some(altDated));

export function contribute(ctx, out) {
  const { tl, trackIndex } = ctx;
  tl._buildAxis(); // epochRows · eraRows · capRows를 채운다(연호 · 도읍 묶음은 base의 axisOpen으로 펼쳐 둔 상태)

  let strip = 0; // 같은 값끼리 이어진 긴 둥근 칸의 번호(0 = 이음 없음)
  const seen = { epoch: 0, era: 0, capital: 0, secondary: 0 };
  const push = (kind, track, lane, s, e, name, col, style, stripNo, seq, pack = 0) => {
    const start = minute(s), end = minute(e);
    if (start == null || end == null || end < start) return;
    out.axis.push({ kind, track, lane: lane || 0, start, end, name: name || '', color: col, style, strip: stripNo, seq, pack });
  };

  /* 시대 구분: 공통 줄(track −1)과 나라별 줄. 이어 붙지 않으므로 strip 0 */
  for (const row of tl.epochRows || []) {
    const track = row.track ? (trackIndex.get(row.track.id) ?? -1) : -1;
    row.epochs.forEach((e, i) => {
      if (e.scope) return; // 그릇 안 이름표 시대(리메이크 2부 · 설계 3-3)는 날짜 칸이 아니라 그 그릇 윗변의 둘째 탭(scopes.mjs 구역 53)
      push(KIND.epoch, track, e._lane || 0, e.start, e.endY, e.name, color(e.color, 0xc8b193), hasVariant(e) ? ST.variant : 0, 0, i, ctx.packOf(e));
      seen.epoch++;
    });
  }

  /* 연호: 한 정권의 연호는 틈 없이 이어진 하나의 긴 둥근 칸 — strip은 정권마다 */
  for (const row of tl.eraRows || []) {
    const track = trackIndex.get(row.track.id) ?? -1;
    const stripOf = new Map();
    for (const c of row.eras) {
      if (!stripOf.has(c.uid)) stripOf.set(c.uid, ++strip);
      const style = (c.startUnknown ? ST.unkS : 0) | (c.endUnknown ? ST.unkE : 0) | (hasVariant(c) ? ST.variant : 0);
      push(KIND.era, track, c.lane || 0, c.start, c.end, c.name, color(c.color), style, stripOf.get(c.uid), c.ci, ctx.packOf(c.p || c));
      seen.era++;
    }
  }

  /* 도읍: 정권의 갈래(en.key)마다 하나의 긴 둥근 칸 — 임시 도읍에 갈린 조각은 같은 strip 안의 칸들.
     칸의 미정은 조각의 끝이 그 도읍의 진짜 시작 · 끝일 때만(지금 연표의 segUnk와 같은 규칙) */
  for (const row of tl.capRows || []) {
    const track = trackIndex.get(row.track.id) ?? -1;
    for (const en of row.entries) {
      const no = ++strip;
      for (const g of en.segs) {
        const c = g.c;
        const seq = en.p.capitals.indexOf(c);
        const style =
          (c.startUnknown && Math.abs(g.s - c.start) < 1e-9 ? ST.unkS : 0) |
          ((c.endUnknown || c.endYAuto) && Math.abs(g.e - c.endY) < 1e-9 ? ST.unkE : 0) |
          (c.role === 'temporary' ? ST.temporary : 0) | (c.role === 'exile' ? ST.exile : 0) | (c.role === 'co' ? ST.co : 0) |
          // 이설 표식은 그 도읍의 진짜 시작 · 끝이 든 조각에만(지금 연표의 `own` — 한 경계에 선 하나)
          (hasVariant(c) && (Math.abs(g.s - c.start) < 1e-9 || Math.abs(g.e - c.endY) < 1e-9) ? ST.variant : 0);
        push(KIND.capital, track, en.lane || 0, g.s, g.e, c.label || c.name, color(en.p.color), style, no, seq, ctx.packOf(en.p));
        seen.capital++;
      }
    }
    /* 배도(별도 · 5경 · 소경): 묶음 하나가 칸 하나 — 도읍 줄 아래의 제 갈래(lane) */
    for (const gr of row.sec || []) {
      const seq = gr.p.capitals.indexOf(gr.members[0]);
      const style =
        (gr.members.some(c => c.startUnknown && c.start === gr.start) ? ST.unkS : 0) |
        (gr.members.some(c => c.endUnknown && c.endY === gr.endY) ? ST.unkE : 0) |
        (gr.members.some(hasVariant) ? ST.variant : 0);
      push(KIND.secondary, track, gr.lane || 0, gr.start, gr.endY, gr.name, color(gr.p.color), style, ++strip, seq, ctx.packOf(gr.p));
      seen.secondary++;
    }
  }

  out.axis.sort((a, b) => a.start - b.start || a.kind - b.kind || a.track - b.track || a.lane - b.lane || a.seq - b.seq);
  ctx.notes.날짜_칸 = { 시대구분: seen.epoch, 연호: seen.era, 도읍: seen.capital, 배도: seen.secondary };

  /* 리메이크 3단계(계약 1-1 초안 · 설계 3-11 ⑤ — 세계사 장면 5): 문화권 단위의 줄을 sphere_lines에.
     kind 2 = 문화권 시대 구분 — 트랙 없이 sphere를 적은 시대 구분(트랙을 함께 적은 것은 트랙 우선이라 싣지 않음). 위의 날짜 칸(공통 줄)에도
       지금처럼 그대로 있다 — 있는 값은 바꾸지 않고, 공통 줄에서 뺄지는 4단계가 그릴 때 정한다.
     kind 3 = 문화권 주기 줄 — 켠 DLC 차례로 yearCycles의 문화권 줄, 문화권마다 첫 것 하나(HT.f4Preview와 같음) · start · end = 0 ·
       data = {names, start, label} 또는 {era, from, step, label}. 모델이 모르는 문화권(sphereWarnings)의 것은 싣지 않는다. */
  const known = id => !!id && typeof ctx.HT.isSphere === 'function' && ctx.HT.isSphere(id);
  let epochs = 0, cycles = 0;
  for (const e of ctx.model.epochs || []) {
    if (!e || !e.sphere || e.track || !known(e.sphere)) continue;
    const start = minute(e.start), end = minute(e.end ?? e.endY);
    if (start == null || end == null || end < start) continue;
    pushLine(out, { kind: LINE.epoch, sphere: e.sphere, start, end, name: e.name || '', uid: e.uid || '', color: color(e.color, 0), data: '', pack: ctx.packOf(e) });
    epochs++;
  }
  const took = new Set();
  ctx.packs.forEach((p, i) => {
    for (const c of Array.isArray(p.yearCycles) ? p.yearCycles : []) {
      if (!c || !c.sphere || took.has(c.sphere) || !known(c.sphere)) continue;
      let data = null;
      if (Array.isArray(c.names) && c.names.length) data = { names: c.names.map(String), start: Number(c.start) || 0, label: c.label || '' };
      else if (c.era) data = { era: String(c.era), from: Number(c.from) || 0, step: Math.max(1, Number(c.step) || 1), label: c.label || String(c.era) };
      if (!data) continue;
      took.add(c.sphere);
      pushLine(out, { kind: LINE.cycle, sphere: c.sphere, start: 0, end: 0, name: data.label, uid: '', color: 0, data: JSON.stringify(data), pack: i });
      cycles++;
    }
  });
  if (epochs || cycles) ctx.notes.문화권_줄 = { 시대구분: epochs, 주기: cycles };
}
