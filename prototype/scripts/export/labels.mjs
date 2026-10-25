// 왼쪽 줄 이름 — 지금 화면 가운데 시기의 정권. 새 엔진의 자료 처리부가 {"op":"row_labels","rows":[…],"at":분}으로 답할 때 쓸 자료를
// 띠마다 out.rowLabels에 싣는다(out.periods는 X1의 몫이라 건드리지 않는다). 고르는 규칙 · 줄이는 차례 · 부제의 구성은 계약 6절에 글로.
// 읽은 곳: js/timeline.js의 _drawTrackLabels(7241줄) · _laneKey(7340줄) · shortYears(120줄) · HT.leaderLabel · HT.cellSpan.
import { minute, color as rgb } from './base.mjs';

/** 줄 이름 칸의 짧은 연도 글 — shortYears 그대로. */
function shortYears(HT, p) {
  const s = HT.yearOf(p.start);
  const e = p.ongoing ? null : HT.yearOf(p.endY);
  if (e == null) return s < 0 ? `BC ${-s}–` : `${s}–`;
  if (s < 0 && e < 0) return `BC ${-s}–${-e}`;
  if (s < 0) return `BC ${-s}–${e}`;
  return `${s}–${e}`;
}

/**
 * 왼쪽 줄 이름 칸에 함께 적을 원어의 후보(10건 3 · 감독 결정 D2-2 "맨 왼쪽 구분표에서만 원어" · 4 B — 갈래 D2 · 웹 HT.bandOrig):
 * [첫 원어, 첫 로마자] 차례의 `{text, mb?}` — mb = 내장 띠 표(HT.GLYPH_BAND)에 없는 글자의 코드 포인트(비면 싣지 않음).
 * 앱은 '원어: 왼쪽 칸에도' · 적용 '나라'일 때만 이 차례로 켜진 글꼴 팩의 범위(띠에 그릴 수 있는 것만)까지 보고 처음 그릴 수 있는 것을 고른다.
 * 첫 원어를 내장 띠 표로 그릴 수 있으면 로마자는 쓸 일이 없어 싣지 않는다. 이름 목록이 없는 띠는 열쇠째 없다(옛 자료는 바이트까지 그대로).
 */
function origOf(HT, p) {
  if (!HT.glyphMissing || !Array.isArray(p.names)) return null;
  const all = p.names.filter(n => n && n.text);
  const native = all.find(n => n.kind === 'native');
  const roman = all.find(n => n.kind === 'roman');
  const out = [];
  for (const n of [native, roman]) {
    if (!n) continue;
    const o = { text: n.text };
    const mb = HT.glyphMissing(n.text, HT.GLYPH_BAND);
    if (mb.length) o.mb = mb;
    out.push(o);
    if (!mb.length) break; // 내장 표로 그릴 수 있는 후보 뒤는 쓸 일이 없다
  }
  return out.length ? out : null;
}

/** 줄의 종류: 0 정권 줄 · 1 그 밖 줄(공통) · 2 접힌 민족 줄. */
const KIND = { band: 0, common: 1, folded: 2 };

// 띠의 바깥 끝(연대 폭을 품은 해) — 지금 연표의 bandStart · bandEnd(js/timeline.js 304).
const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);

/**
 * 민족 딱지(`.tl-pchip` — 지금 연표의 `_rowPeopleChip` 3159): 줄 r의 정권 민족이 그 줄을 덮은 민족 묶음과 다르면
 * `{id, name, color, scope, all}`, 같거나 민족이 없으면 null. 접힌 줄 · 트랙 공통 줄은 묻지 않는다.
 * 딱지는 줄마다 하나라 그 줄의 후보 띠마다 같은 값을 싣는다(계약 6-8절).
 */
function rowChip(tl, tr, r) {
  if (!tr.rowPeriods || tr.foldedRows.has(r) || r === tr.commonRow) return null;
  const list = (tr.rowPeriods[r] || []).filter(p => p.peopleId && !p._hidden);
  if (!list.length) return null;
  let cover = null;
  for (const gp of tr.groups || []) {
    if (gp.name && !gp.culture && gp.first <= r && r < gp.first + gp.count && (!cover || gp.scope || (!cover.scope && gp.depth > cover.depth))) cover = gp;
  }
  const own = new Map(); // 묶음과 다른 민족 → 그 민족 정권들의 기간 합
  for (const p of list) if (!cover || p.peopleId !== cover.key) own.set(p.peopleId, (own.get(p.peopleId) || 0) + bandEnd(p) - bandStart(p));
  if (!own.size) return null;
  const id = [...own.entries()].sort((a, b) => b[1] - a[1])[0][0];
  const p = list.find(q => q.peopleId === id);
  return {
    id, name: p.peopleName || id, color: rgb(p.peopleColor || tr.color),
    scope: cover && cover.scope ? 1 : 0,
    all: [...own.keys()].map(k => (list.find(q => q.peopleId === k) || {}).peopleName || k),
  };
}

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const cats = ctx.shared.catNo || new Map();
  const rows = (out.rowLabels = []);
  const count = { 띠: 0, 그밖줄: 0, 접힌줄: 0, 접힐줄: 0, 노선도: 0, 소속줄: 0, 민족딱지: 0, 원어: 0 };
  tl.tracks.forEach((tr, track) => {
    for (let row = 0; row < tr.rows; row++) {
      if (row === tr.commonRow) {
        rows.push({ period: '', track, row, kind: KIND.common, name: '그 밖', years: '', color: rgb('#9c978d'), cap: 0, member: 0, lanes: [] });
        count.그밖줄++;
        continue;
      }
      if (tr.foldedRows.has(row)) {
        const gp = (tr.groups || []).find(x => x.first === row && x.folded);
        rows.push({
          period: '', track, row, kind: KIND.folded, name: gp ? gp.name : '', years: '', depth: gp ? gp.depth : 0,
          group: gp ? gp.key : '', color: rgb(gp ? gp.color : tr.color), cap: 0, member: 0, lanes: [], count: (tr.rowPeriods[row] || []).length,
        });
        count.접힌줄++;
        continue;
      }
      const lanes = ((tr.rowCats && tr.rowCats[row]) || []).map(id => (cats.has(id) ? cats.get(id) : 255));
      // 민족 딱지는 줄마다 하나다 — 그 줄의 후보마다 같은 값을 실어, 어느 띠의 이름을 보이든 딱지가 그려지게 한다.
      const chip = rowChip(tl, tr, row);
      if (chip) count.민족딱지++;
      // 그 줄의 후보 정권마다 하나 — 어느 것을 쓸지는 보는 시기(at)를 아는 그리는 쪽이 고른다(계약 6절의 고르는 규칙).
      for (const p of tr.rowPeriods[row] || []) {
        if (p._overlay || p._under || p._hidden) continue;
        const orig = origOf(HT, p);
        if (orig) count.원어++;
        rows.push({
          period: p.uid, track, row, kind: KIND.band,
          name: p.name || '', years: shortYears(HT, p), color: rgb(p.color),
          start: minute(p.start), end: Math.max(minute(p.start), minute(p.endY)),
          cap: p.capitals && p.capitals.length ? 1 : 0,
          member: tr.memberRows.has(row) ? 1 : 0,
          lanes,
          ...(chip ? { chip } : {}),
          ...(orig ? { orig } : {}),
        });
        count.띠++;
        if (p.capitals && p.capitals.length) count.노선도++;
        if (tr.memberRows.has(row)) count.소속줄++;
      }
    }
    // 민족을 접으면 그 묶음의 줄들이 한 줄로 합쳐진다 — 그때 보일 이름을 **미리** 싣는다(명세 05의 8.1절 4번:
    // "넣을 때 두 상태를 모두 만들어 두고 보기 조건으로 고른다"). 묶음의 첫 줄에 `kind 2` 후보 하나를 얹고,
    // 한 줄에 여러 단계의 묶음이 겹칠 수 있으므로 `depth`로 가른다(그리는 쪽이 접힌 묶음의 단계로 고른다).
    // **대범위 가지**(`gp.key`가 `__scope:<uid>`)는 깊이가 늘 0이라 같은 줄의 민족 묶음과 부딪친다 — 묶음 이름(`group`)으로 가른다.
    for (const gp of tr.groups || []) {
      if (!gp.name || gp.folded) continue; // 이미 접힌 묶음은 위에서 실었다
      let n = 0;
      for (let r = gp.first; r < gp.first + gp.count; r++) {
        for (const p of tr.rowPeriods[r] || []) if (!p._hidden) n++;
      }
      rows.push({
        period: '', track, row: gp.first, kind: KIND.folded, name: gp.name, years: '', depth: gp.depth, group: gp.key,
        color: rgb(gp.color), cap: 0, member: 0, lanes: [], count: n,
      });
      count.접힐줄++;
    }
  });
  ctx.notes.줄이름 = count;
}
