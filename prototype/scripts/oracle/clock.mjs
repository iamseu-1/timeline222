// 시각 고정 — 인자 없는 new Date() · Date.now() · Date()만 정한 시각으로 만든다(인자 있는 생성 · Date.UTC · Date.parse는 원래 것).
// 웹 코드(core.js)가 싣는 순간 new Date().getFullYear()를 세므로, base.mjs(→ core.js)를 가져오기 **전에** 부른다.
// one.mjs(정답지 · 시간대도 Asia/Seoul로 못 박음)와 to-f4.mjs(HT_ORACLE_NOW가 있을 때만 — 바꾼 결과가 시각과 무관한지 보려고)가 함께 쓴다.

/** 정한 시각(`2026-10-15T12:00:00+09:00` 꼴 글)으로 Date를 갈아 끼운다. 돌려주는 값: 그 시각(밀리초). 시각이 아니면 던진다. */
export function installClock(nowText) {
  const now = Date.parse(nowText);
  if (!Number.isFinite(now)) throw new Error(`HT_ORACLE_NOW가 시각이 아닙니다: "${nowText}" (예: 2026-10-15T12:00:00+09:00)`);
  const RealDate = globalThis.Date;
  globalThis.Date = new Proxy(RealDate, {
    construct: (target, argv, newTarget) => Reflect.construct(target, argv.length ? argv : [now], newTarget),
    apply: target => new target(now).toString(),
    get: (target, key) => (key === 'now' ? () => now : Reflect.get(target, key, target)),
  });
  return now;
}
