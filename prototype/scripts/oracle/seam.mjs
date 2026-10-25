// 정답지의 '덤프 규칙'(seam) — P3의 두 번째 이음매(줄 배정 전 · 후의 연표 상태 `tl`과 모델)를 JSON 글로 적는 규칙.
// 모델 · 연표 상태는 고리가 있어 그대로는 JSON이 아니다. Node(이 파일)와 Rust(과제 3의 `lay::js` 덤프)가 같은 규칙으로 적어 견준다.
//
// 규칙(깊이 우선):
//   · 객체 열쇠는 JS 차례(Object.keys — 정수 모양 열쇠가 먼저, 나머지는 넣은 차례). 함수 · undefined · symbol 값은 빠진다(배열 · Map · Set 안이면 null).
//   · NaN · ±Infinity는 null. 수 글은 JSON.stringify 그대로(5.0 → 5, 1e21 → 1e+21, -0 → 0).
//   · Map은 {"$map":[[열쇠, 값],…]} · Set은 {"$set":[…]}.
//   · 이미 만난 객체 · 배열 · Map · Set은 {"$ref":"<uid가 글이면 uid, 아니면 빈 글>#<처음 만난 경로>"}.
//     경로는 열쇠 · 순번을 '.'로 이은 것(`tracks.0.periods.3` — 맨 위는 빈 글). Map의 칸은 `<경로>.$map.<순번>.0`(열쇠) · `.1`(값),
//     Set의 칸은 `<경로>.$set.<순번>`. 열쇠 글은 이스케이프하지 않는다(경로는 이름표일 뿐 — 같은 객체가 처음 만난 자리만 뜻이 같으면 된다).
//   · 그 밖의 객체(Date · 클래스 개체 …)는 덤프하지 않고 경로와 함께 멈춘다 — 조용히 틀린 정답지가 나오지 않게.
// 쓰임: seam(값) → JSON 글(한 줄). 줄 바꿈 · 들여쓰기 없음.

/** 값을 덤프 규칙으로 JSON 글로 적는다. */
export function seam(root) {
  const seen = new Map(); // 객체 → 처음 만난 경로
  const at = (path, seg) => (path === '' ? String(seg) : `${path}.${seg}`);

  /** 글 한 조각 · 빠지는 값(함수 · undefined · symbol)이면 undefined. */
  function dump(v, path) {
    if (v === undefined || typeof v === 'function' || typeof v === 'symbol') return undefined;
    if (v === null) return 'null';
    switch (typeof v) {
      case 'boolean': return v ? 'true' : 'false';
      case 'number': return Number.isFinite(v) ? JSON.stringify(v) : 'null';
      case 'string': return JSON.stringify(v);
      case 'bigint': throw new Error(`seam: BigInt는 덤프하지 않습니다 (${path || '(루트)'})`);
    }
    if (seen.has(v)) return `{"$ref":${JSON.stringify(`${typeof v.uid === 'string' ? v.uid : ''}#${seen.get(v)}`)}}`;
    seen.set(v, path);
    const parts = [];
    if (Array.isArray(v)) {
      for (let i = 0; i < v.length; i++) parts.push(dump(v[i], at(path, i)) ?? 'null'); // 구멍도 null
      return `[${parts.join(',')}]`;
    }
    if (v instanceof Map) {
      let i = 0;
      for (const [k, x] of v) {
        const p = at(at(path, '$map'), i++);
        parts.push(`[${dump(k, at(p, 0)) ?? 'null'},${dump(x, at(p, 1)) ?? 'null'}]`);
      }
      return `{"$map":[${parts.join(',')}]}`;
    }
    if (v instanceof Set) {
      let i = 0;
      for (const x of v) parts.push(dump(x, at(at(path, '$set'), i++)) ?? 'null');
      return `{"$set":[${parts.join(',')}]}`;
    }
    const proto = Object.getPrototypeOf(v);
    if (proto !== Object.prototype && proto !== null) {
      throw new Error(`seam: 덤프할 수 없는 객체입니다 (${path || '(루트)'} — ${(proto.constructor && proto.constructor.name) || '이름 없는 개체'})`);
    }
    for (const k of Object.keys(v)) {
      const s = dump(v[k], at(path, k));
      if (s !== undefined) parts.push(`${JSON.stringify(k)}:${s}`);
    }
    return `{${parts.join(',')}}`;
  }

  const text = dump(root, '');
  return text === undefined ? 'null' : text;
}
