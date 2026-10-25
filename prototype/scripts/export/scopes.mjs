// 대범위 테두리(구역 23)와 기간 칠(24). 값의 뜻은 계약 docs/계약-아카이브-3단계.md 6-10절, 규칙은 docs/명세-3단계/04-관계선.md 6절.
//
// 둘은 **켠 대범위에만** 생긴다 — 켜면 구성 정권이 제 민족 묶음을 떠나 합성 가지로 모이므로(명세 6-1) 꺼진 상태에서는 가지의 줄 범위 자체가 없다.
// 지금 연표의 `_scopeNodes` · `_scopeBranches`가 그 가지(`tr.scopeBranches`)를 만들고, 내보내기는 그것을 그대로 읽는다.
// 견본(월흔해)의 대범위 넷은 모두 꺼진 채 시작해서(`tl.scopesOn = {}`) 2026-09-21 현재 이 모듈은 아무것도 싣지 않는다 — 켜 두고 내보내면 그대로 실린다.
// 할거기 칠(25) · 소속 단추(26) · 할거 모아 보기 단추(27)는 대범위를 꺼 두어도 보이므로 links.mjs가 싣는다.
// 숨긴 구성원 꼬리표(59 — 리메이크 4단계 선반 갈래)는 선반 상태로 다시 배치한 가지(`b.shelf`)에만 생겨 선반 변형(variants.mjs의 shelf:<그릇 uid>)으로만 실린다.
import { minute, color } from './base.mjs';
import { lodOf } from './rails.mjs';

/** 내가 쓰는 구역 번호(계약 6-10절) — 50은 풀린 그릇의 열쇠표(리메이크 조각 ③ · 아래 [contribute] 끝) · 59는 숨긴 구성원 꼬리표(선반). */
export const SECTION = { scope: 23, scopeSpan: 24, key: 50, label: 53, shelf: 59 };

/** 선반이 제 줄에 남기는 구성원 수 — 지금 연표의 G_SEOGO.shelfKeep(서고 과제 9 · _shelfSplit)과 같은 값. 구역 59의 a(그릇 안 차례)는 숨은 첫째가 이 값이다. */
const SHELF_KEEP = 5;

/** 대범위의 구성으로 세지 않는 띠의 종류(지금 연표의 `_scopeClaims`와 같다). */
const SKIP_KINDS = new Set(['overlay', 'culture', 'dynasty']);

/** 구역 23 · 테두리의 a 비트. board(8) = **집합 보기 판의 둘레**(10건 6 · 감독 선택 D4 결정 2 A — boards.mjs가 판을 켠 배치를 다시 돌릴 때만 생긴다):
    가로는 화면 전체(기간이 아니라 보는 방법 — 이름표가 물러나지 않음)라 시각 범위를 자료 전체로 싣고, 그리는 쪽이 양쪽 모서리를 편다. */
const SC = { hung: 1, afterHost: 2, guessed: 4, board: 8 };

const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);

/** 자료 전체의 시각 범위(해) — 집합 보기 판의 둘레가 어느 타일에나 실리게. 모든 정권 띠의 바깥 끝까지(판을 켜면 띠 밖의 해에는 그릴 것이 없다). */
function extentOf(ctx) {
  let lo = Infinity, hi = -Infinity;
  for (const p of ctx.model.periods || []) {
    const a = bandStart(p), b = bandEnd(p);
    if (Number.isFinite(a) && a < lo) lo = a;
    if (Number.isFinite(b) && b > hi) hi = b;
  }
  return [lo, hi];
}

export function contribute(ctx, out) {
  const { tl } = ctx;
  const counts = { 대범위테두리: 0, 대범위기간칠: 0 };
  const skipped = { 가지없음: 0, 구성정권없음: 0 };
  let shelfTags = 0;
  const item = o => out.items.push(Object.assign({ section: 0, track: 0, row: 0, row2: 0, start: 0, end: 0, lod: -1, ref: '', name: '', color: 0, a: 0, b: 0, c: 0, d: 0, text2: '' }, o));

  tl.tracks.forEach((tr, track) => {
    const branches = tr.scopeBranches || [];
    if (!branches.length) {
      skipped.가지없음++;
      return;
    }
    for (const b of branches) {
      const s = b.s;
      const list = (b.list || []).filter(p => p && p._row != null);
      if (!list.length) {
        skipped.구성정권없음++;
        continue;
      }
      // 가로: 구성 띠 전체의 시각 범위(가로 여백 8px과 미정 꼬리 44px은 그릴 때 더한다 — 명세 6-3).
      let lo = Infinity, hi = -Infinity;
      for (const p of list) {
        lo = Math.min(lo, bandStart(p));
        hi = Math.max(hi, bandEnd(p));
      }
      // 집합 보기의 판 둘레: 어느 시기를 보든 타일에 실리도록 자료 전체의 시각 범위로(지금 연표의 _scopeX가 판이면 화면 전체 — 기본 상태에는 없다).
      if (b.board) [lo, hi] = extentOf(ctx);
      const start = minute(lo), end = minute(hi);
      if (start == null || end == null || end < start) continue;
      const row = b.first, row2 = b.first + b.count - 1;
      const a = (b.hung ? SC.hung : 0) | (s.afterHost ? SC.afterHost : 0) | (s.rangeFrom === 'members' ? SC.guessed : 0) | (b.board ? SC.board : 0);
      // b = 구성 띠 수(리메이크 조각 ③ — 폴더 탭의 라벨 '이름 수'). 0이면 수를 쓰지 않는다(옛 저장소).
      item({
        section: SECTION.scope, track, row, row2, start, end, lod: -1,
        // text2 = 그릇 uid␟성격(리메이크 2부 포개짐 — 그리는 쪽이 첫 줄로 uid를 찾지 않게 · ␟이 없으면 옛 저장소: 성격만)
        ref: b.host ? b.host.uid : '', name: s.name || '', color: color(s.color), a, b: list.length, text2: `${s.uid}\u001f${s.label || ''}`,
      });
      counts.대범위테두리++;
      /* 구역 53 · 그릇 안 이름표 시대(리메이크 2부 · 설계 3-3): 켠 그릇의 가지마다 그 그릇에 든 시대 구분(구성원 없는 시대 — epochs[].within)마다 하나.
         row · row2 = 23과 같게 · start · end = 시대 구분의 해 · name = 이름 · color = 그릇 색 · text2 = 시대 구분 uid(누르면 상세). 새 앱은 폴더 윗변의 둘째 탭(상자면 뚜껑 안 종이)으로 */
      for (const e of s.labels || []) {
        const es = minute(e.start), ee = minute(e.endY);
        if (es == null || ee == null || ee < es) continue;
        item({ section: SECTION.label, track, row, row2, start: es, end: ee, lod: -1, ref: '', name: e.name || '', color: color(s.color), text2: e.uid });
        counts.그릇안이름표 = (counts.그릇안이름표 || 0) + 1;
      }
      /* 구역 59 · 숨긴 구성원 꼬리표(선반 — 리메이크 4단계 · 감독 결정 2026-10-25 '선반 = 엔진 변형 길'): 선반 상태로 다시 배치한 가지(b.shelf — 지금 연표 _layoutTrack이
         상위 shelfKeep 밖으로 숨긴 구성원 · _shelfSplit 차례)의 숨은 띠마다 하나. 선반 변형을 셀 때만 생겨 그 변형의 새 항목으로 실린다(기본 배치 · 다른 변형에는 없음).
         row = row2 = 가지 끝 줄(폴더 발) · start · end = 그 띠의 바깥 끝 · lod = 테(23)와 같은 단계(테의 범위에서 셈 — 테가 실리는 넓은 보기에서도 실림) ·
         ref · text2 = 그 띠의 uid(자료집 · 거르개가 띠를 따름 — 엔진은 숨은 띠를 가리킨 변형 항목을 제자리에 둔다) · a = 그릇 안 차례(0부터 — 숨은 첫째가 SHELF_KEEP) · b = 숨은 수 */
      const shelf = b.shelf || [];
      shelf.forEach((p, i) => {
        const ps = minute(bandStart(p)), pe = minute(bandEnd(p));
        if (ps == null || pe == null || pe < ps) return;
        item({ section: SECTION.shelf, track, row: row2, row2, start: ps, end: pe, lod: lodOf(end - start), ref: p.uid, name: p.name || '', color: color(p.color), a: SHELF_KEEP + i, b: shelf.length, text2: p.uid });
        shelfTags++;
      });
      // 기간의 짙은 세로 구간: 시각을 a~d(u32)에 담을 수 없어 따로 낸다. 줄 범위가 23과 같아 그리는 쪽이 그 줄로 짝을 찾는다.
      // 기간을 적지 않은 집합 보기는 구간이 없다(지금 연표의 _drawScopes — rangeFrom 'members'면 그리지 않음).
      if (b.board && s.rangeFrom === 'members') continue;
      const ss = minute(s.start), se = minute(s.endY);
      if (ss == null || se == null || se < ss) continue;
      item({
        section: SECTION.scopeSpan, track, row, row2, start: ss, end: se, lod: -1,
        ref: b.host ? b.host.uid : '', name: '', color: color(s.color),
      });
      counts.대범위기간칠++;
    }
  });

  // 풀린 그릇의 열쇠표(구역 50 — 리메이크 조각 ③ · 설계 4-6 #2 B '풀림'): 이 판에서 **꺼 둔** 대범위의 구성 띠마다 하나 —
  // 테가 없어지고 구성원이 제 줄에 있을 때 그릇 이름이 그 띠 위의 열쇠표로 남는다(목업 d2-b의 loosen). 구성은 지금 연표의
  // `_scopeClaims`와 같은 셈(덧그림 · 바탕 문화 · 왕조 띠와 본국은 빼고 · 그 트랙에 그려진 띠만).
  // 켜 둔 판에서는 실리지 않으므로 기본 판의 것이 남는다 — 그리는 쪽이 켠 대범위(text2 = uid)의 것은 건너뛴다.
  // 줄 비트 15(그 줄의 위 틈 15 — 열쇠표 자리)는 tracks.mjs의 늦은 차례가 이 구역을 보고 켠다.
  let keys = 0;
  tl.tracks.forEach((tr, track) => {
    const off = (tl.scopes || []).filter(s => s.track === tr.id && !tl.scopeOn(s));
    if (!off.length) return;
    const inTrack = new Map(tr.periods.map(p => [p.uid, p]));
    for (const s of off) {
      const ss = minute(s.start);
      for (const m of s.members || []) {
        const p = inTrack.get(m.uid);
        if (!p || SKIP_KINDS.has(p.polityKind) || (s.host && s.host.uid === p.uid)) continue;
        if (p._hidden || p._overlay || p._under || p._row == null) continue;
        const a = minute(bandStart(p)), e = minute(bandEnd(p));
        if (a == null || e == null) continue;
        // 열쇠표의 해: 띠가 그릇보다 먼저 섰으면 그릇이 선 해(목업 loosen의 max(띠 시작, 그릇 시작)).
        const start = ss == null ? a : Math.min(Math.max(a, ss), e);
        item({ section: SECTION.key, track, row: p._row, row2: p._row, start, end: e, lod: -1, ref: p.uid, name: s.name || '', color: color(s.color), text2: s.uid });
        keys++;
      }
    }
  });
  if (shelfTags) counts.선반꼬리표 = shelfTags; // 선반 변형의 다시 셈에만 — 기본 배치의 알림은 그대로
  counts.풀린그릇열쇠표 = keys;

  ctx.notes.대범위 = counts;
  ctx.notes.대범위에서_뺀_것 = skipped;
}
