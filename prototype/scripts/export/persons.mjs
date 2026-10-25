// 사람 띠(리메이크 3단계 · 계약 1-1 초안 · 설계 3-11 ① — 세계사 장면 1): 왕관(지도자 칸의 person 이음)이 둘 이상의 객체에 있는 사람마다
// 문화권 단위의 표 sphere_lines에 kind 1 한 줄. 셈은 js/core.js의 HT.personBands — 메이커 서고 미리보기(HT.f4Preview)와 같은 셈이다.
//   sphere = 왕관 트랙들의 문화권 가운데 차례가 가장 앞 · start · end = 왕관 칸의 가장 이른 시작 ~ 가장 늦은 끝(분) · name = 사람 이름 ·
//   uid = 인물 uid · color 0 · data = 왕관 목록 JSON [{"uid": 객체 띠 uid, "cell": 지도자 칸 순번}] · pack = 인물이 든 DLC.
// 사람 띠는 트랙의 줄이 아니라 문화권 머리 단 자리에 서므로 줄 · 타일에 들지 않는다(엔진은 {"op":"layout"}에 통째로 답함).
// out.sphereLines만 쓰고 다른 값은 건드리지 않는다 — 왕관이 둘 이상인 사람이 없으면 아무것도 싣지 않고 열쇠도 만들지 않는다.
import { minute } from './base.mjs';

/** sphere_lines의 kind(계약 1-1 초안) */
export const LINE = { person: 1, epoch: 2, cycle: 3 };

/** out.sphereLines에 한 줄 — 열쇠는 처음 실을 때 만든다(옛 출력에 빈 열쇠가 생기지 않게). persons · axis · tracks 모듈이 함께 쓴다. */
export function pushLine(out, line) {
  if (!out.sphereLines) out.sphereLines = [];
  out.sphereLines.push(line);
}

export function contribute(ctx, out) {
  const { HT, model } = ctx;
  const bands = typeof HT.personBands === 'function' ? HT.personBands(model) : [];
  let n = 0;
  for (const b of bands) {
    const start = minute(b.start), end = minute(b.end);
    if (start == null || end == null || end < start) continue;
    const fig = b.figure && model.figures ? model.figures.find(f => f.uid === b.figure) : null;
    pushLine(out, {
      kind: LINE.person, sphere: b.sphere || '', start, end, name: b.name || '', uid: b.figure || '', color: 0,
      data: JSON.stringify(b.crowns.map(c => ({ uid: c.uid, cell: c.i }))), pack: ctx.packOf(fig),
    });
    n++;
  }
  ctx.notes.사람띠 = n;
}
