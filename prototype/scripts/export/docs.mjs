// 문서(위키) 창과 하위 문서 칩이 읽는 기록 — 계약 6-9절 나. 월흔해의 문서 본문(항목의 `wiki` 칸과 DLC의 `documents`는
// 모델이 이미 `model.docs` 하나로 합쳐 둔다) · 하위 문서 · 트랙 · 민족 · 분류 · 가문 · 칸 문서를
// `{uid:"doc:<열쇠>", kind:"doc", json}`으로 항목 기록(out.entities)에 싣는다. 조회는 이미 있는 `{"op":"entity","uid":"doc:<열쇠>"}` 하나면 된다.
//
// 지금 연표의 문서 창(js/viewer.js 2691~3009의 `docInfo` · `baseInfo` · `subdocsOf` · `nameToBase` · `linkToKey` ·
// `backlinks` · `renderWikiSubs`)은 창을 열 때마다 모델 전체를 넘나들며 제목 · 곁글 · 하위 문서 · 고리의 목적지를 찾는다.
// 새 엔진은 모델을 올리지 않으므로 그 답을 **넣을 때 한 번** 풀어 둔다:
//   · 제목 · 곁글 · 빵 부스러기 · 하위 문서 목록 · 역고리 · 본문 안 `[[고리]]`의 목적지까지 기록 안에.
//   · 시간은 계약 4절의 약속대로 정수 분(`span` · `at`)이다. `json` 본문의 옛 값(해 좌표)과 섞지 않는다.
//   · 빈 것은 싣지 않는다 — 열쇠가 없으면 '없음'이다.
//
// 본문이 없는 문서도 기록을 만든다(`empty: 1`): 중간 단계 하위 문서('역사//전기'만 있을 때의 '역사')와
// 고리가 가리키는 곳이다. 지금 연표는 그런 열쇠도 창을 열어 "아직 문서가 없습니다."를 보이므로 갈 곳이 있어야 한다.
//
// 항목 기록 쪽에 실을 것(`x_docs` · `x_cellDocs`)은 [contributeLate]가 맡는다 — MODULES의 차례가 `docs` → `entities`라
// `contribute`가 도는 때에는 항목 기록이 아직 없기 때문이다. `ctx.shared.docsOf` · `ctx.shared.cellDocsOf`로도 넘긴다.
import { minute, runScript } from './base.mjs'; // 스크립트 싣기는 base.mjs가(노드 vm · 브라우저 일꾼 importScripts — 브라우저 겸용)

/** 지금 연표의 위키 렌더러(js/wiki.js)를 한 번만 올린다 — 본문의 `[[고리]]` 이름을 똑같은 규칙으로 뽑으려고(읽기만 한다). */
function loadNamu(HT) {
  if (!HT.namu) runScript('js/wiki.js');
  return HT.namu;
}

/** 해 좌표 → 정수 분(빈 값은 null). */
const M = t => (t == null || !Number.isFinite(t) ? null : minute(t));

/** 구간 [a, b] → [분, 분]. 시작이 없으면 null이고, 뒤집히면 앞쪽으로 맞춘다. */
function spanOf(a, b) {
  const lo = M(a);
  if (lo == null) return null;
  const hi = M(b);
  return [lo, hi == null || hi < lo ? lo : hi];
}

/* ---------- 문서 그림 (형식 3 — 10건 D3 · DLC-형식.md 'images (문서 그림)') ----------
 * 문서 기록에 `images` = { "<본문에 적힌 이름>": { key, mime, w, h, caption?, alt?, credit?, bytes } } — 본문의 `[[파일:이름]]`을 지금 연표와 같은 규칙
 * (HT.docImageOf — 그 문서 글을 적은 팩의 그림 사전에서 id → 이름)으로 미리 푼다. 사전에 없는 이름은 싣지 않는다(새 앱이 '그림 없음' 자리로 그림).
 * 그림 바이트는 기록에 싣지 않고 배치의 겉 열쇠 `blobs[]`({ key, pack, mime, data(base64) })에 한 번만 — 엔진이 저장소의 `blobs` 표에 담고
 * 새 앱이 문서 창을 열 때 열쇠(`img:<DLC id>/<그림 id>`)로 읽는다(설계 A-아카이브-이음.md 6절 바닥 6 · 스키마 판 '3'은 그대로).
 * 문서가 쓰는 그림만 싣는다. 그림을 쓰는 문서가 없으면 `blobs` 열쇠도 없다 — 옛 배치는 1바이트도 다르지 않다. */
const IMAGE_RE = /^data:(image\/(png|jpeg|webp));base64,/;
/** base64 앞부분만 풀어 그림의 픽셀 크기를 읽는다(png · webp · jpeg 머리) — 그림 사전에 width · height가 없을 때. 모르면 [0, 0] */
function sizeOf(b64) {
  let bin;
  try {
    bin = globalThis.atob(b64.slice(0, 87384)); // 앞 64KB만(4의 배수 길이 — 그림 사전의 src는 빈칸 없는 base64)
  } catch {
    return [0, 0];
  }
  const u = i => bin.charCodeAt(i) & 255;
  const be16 = i => (u(i) << 8) | u(i + 1);
  const be32 = i => ((u(i) << 24) >>> 0) + (u(i + 1) << 16) + (u(i + 2) << 8) + u(i + 3);
  if (bin.startsWith('\x89PNG')) return [be32(16), be32(20)];
  if (bin.startsWith('RIFF') && bin.slice(8, 12) === 'WEBP') {
    const chunk = bin.slice(12, 16);
    if (chunk === 'VP8 ') return [(u(26) | (u(27) << 8)) & 0x3fff, (u(28) | (u(29) << 8)) & 0x3fff];
    if (chunk === 'VP8L') return [1 + (((u(22) & 0x3f) << 8) | u(21)), 1 + (((u(24) & 0x0f) << 10) | (u(23) << 2) | ((u(22) & 0xc0) >> 6))];
    if (chunk === 'VP8X') return [1 + (u(24) | (u(25) << 8) | (u(26) << 16)), 1 + (u(27) | (u(28) << 8) | (u(29) << 16))];
    return [0, 0];
  }
  if (u(0) === 0xff && u(1) === 0xd8) {
    for (let i = 2; i + 9 < bin.length; ) {
      if (u(i) !== 0xff) return [0, 0];
      const m = u(i + 1);
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return [be16(i + 7), be16(i + 5)];
      i += 2 + be16(i + 2);
    }
  }
  return [0, 0];
}

/** 빈 것(없음 · 빈 글 · 빈 목록 · 빈 표)은 싣지 않는다. */
const some = v => (v == null || v === '' || (Array.isArray(v) && !v.length) || (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length) ? null : v);

/**
 * 문서 하나하나를 풀어 주는 도구 묶음. 지금 연표의 함수 이름을 그대로 쓴다.
 * 돌려주는 것: `{ keysWithText, docInfo, subdocsOf, linkToKey, textOf }`.
 */
function tools(ctx) {
  const { HT, model } = ctx;
  const namu = loadNamu(HT);

  const textOf = key => {
    const d = model.docs.get(key);
    return d ? d.text || '' : '';
  };
  /** 내용이 있는 문서 열쇠(지금 연표의 `allDocKeys`). */
  const keysWithText = [...model.docs.keys()].filter(k => textOf(k).trim());
  const withText = new Set(keysWithText);

  const trackOf = id => model.trackMap.get(id) || { id, name: id, color: '#8b8f98' };
  /** 칸의 기간 글(viewer.js 73의 `cellWhen(c, undefined, x)`) — 끝을 비운 칸은 풀어 둔 끝으로. */
  const cellWhen = (c, p) => {
    const useEndY = c.end == null;
    return HT.formatRange({
      start: c.start, startAt: c.startAt, end: useEndY ? c.endY : c.end, endAt: useEndY ? c.endYAt : c.endAt,
      startUnknown: c.startUnknown, endUnknown: c.endUnknown || (useEndY && c.endYAuto), ongoing: HT.cellToNow(c, p),
    });
  };

  /** 바탕 키의 대상(viewer.js 2715의 `baseInfo`) — 없으면 null. */
  function baseInfo(base) {
    const p = HT.docKey.parse(base);
    if (p.type === 'people') {
      const pe = model.peopleMap.get(p.id);
      return pe && { title: pe.name, meta: '민족', desc: pe.description || '' };
    }
    if (p.type === 'track') {
      const t = model.trackMap.get(p.id);
      return t && { title: t.name, meta: '트랙(나라·지역)', desc: t.description || '', pack: ctx.trackPack.get(p.id) || 0 };
    }
    if (p.type === 'category') {
      const c = model.categoryMap.get(p.id);
      return c && { title: c.name, meta: '사건 분류', desc: c.description || '' };
    }
    if (p.type === 'house') {
      const h = model.houseMap && model.houseMap.get(p.id);
      // 가문은 제 줄이 없다 — '연표에서'는 가문 창을 열 뿐 연표를 옮기지 않는다(span 없음).
      return h && { title: h.name, meta: `가문${h.surname ? ` · 성 ${h.surname}` : ''}${h.seat ? ` · 본관 ${h.seat}` : ''}`, uid: h.uid, desc: h.description || '', pack: ctx.packOf(h) };
    }
    if (p.type === 'surname') {
      // 성씨 (형식 3) — 제 창이 없어 문서만. 연표로 데려갈 uid는 없다(지금 연표 baseInfo와 같은 글).
      const s = model.surnameMap && model.surnameMap.get(p.id);
      return s && { title: s.name, meta: `성씨${s.houses.length ? ` · 가문 ${s.houses.length}` : ''}`, desc: s.description || '', pack: ctx.packOf(s) };
    }
    if (p.type === 'place') {
      // 지명 (형식 3) — 제 창이 없어 문서만.
      const pl = model.placeMap && model.placeMap.get(p.id);
      return pl && { title: pl.name, meta: `지명${pl.uses.length ? ` · 쓰인 곳 ${pl.uses.length}` : ''}`, desc: pl.description || '', pack: ctx.packOf(pl) };
    }
    if (p.type === 'cell') {
      const x = model.byUid.get(p.uid);
      const K = HT.cellKind(p.cellKind);
      if (!x || !K) return null;
      const cells = HT.cellsOf(x, K);
      // 칸 열쇠는 "이름@시작 해"다 — 열쇠를 만드는 규칙 그대로 맞춰 본다(날짜를 자세히 고쳐도 문서가 떨어지지 않게).
      const i = cells.findIndex(c => HT.docKey.cell(x.uid, p.cellKind, c) === p.base);
      if (i < 0) return null;
      const c = cells[i];
      const ref = `${K.id}:${i}`;
      const sp = HT.cellSpan(c, x, ref);
      return {
        title: K.title(c, { leaderMode: 'auto' }), meta: `${x.name} ${K.name} · ${cellWhen(c, x)}`,
        uid: x.uid, ref, at: M(c.start), span: spanOf(sp.lo, sp.hi), parent: x.uid, desc: c.description || '', pack: ctx.packOf(x),
      };
    }
    const x = model.byUid.get(p.uid);
    if (!x) return null;
    const where = x.track ? ` · ${trackOf(x.track).name}` : '';
    const word = x.kind === 'epoch' ? '시대 구분' : x.kind === 'event' ? '사건' : HT.itemKindOf(x) === 'period' ? HT.kindName(x.polityKind) : HT.itemWord(x);
    return {
      title: x.title || x.name, meta: `${word} · ${HT.formatRange(x)}${where}`, uid: x.uid,
      span: spanOf(x.spanMin != null ? x.spanMin : x.start, x.spanMax != null ? x.spanMax : x.endY != null ? x.endY : x.end),
      desc: x.description || '', pack: ctx.packOf(x),
    };
  }

  const baseCache = new Map();
  const baseOf = base => {
    if (!baseCache.has(base)) baseCache.set(base, baseInfo(base));
    return baseCache.get(base);
  };

  /** 문서 하나의 제목 · 곁글 · 길(viewer.js 2749의 `docInfo`) — 바탕이 없으면 null. */
  function docInfo(key) {
    const { base, sub } = HT.docKey.split(key);
    const b = baseOf(base);
    if (!b) return null;
    if (!sub) return Object.assign({}, b, { key, base, sub: '', path: [] });
    const parts = sub.split('//');
    return Object.assign({}, b, { key, base, sub, path: parts, title: `${b.title}/${parts.join('/')}`, meta: `${b.title}의 하위 문서`, baseTitle: b.title });
  }

  /** 그 문서의 바로 아래 하위 문서(viewer.js 2708) — 중간 단계가 비어 있어도 이름을 보인다. */
  function subdocsOf(key) {
    const pre = `${key}//`;
    const subs = new Set(keysWithText.filter(k => k.startsWith(pre)).map(k => k.slice(pre.length).split('//')[0]));
    return [...subs].sort((a, b) => HT.cmp16(a, b)).map(sub => ({ key: pre + sub, sub }));
  }

  /* ---------- 이름 → 바탕 키(viewer.js 2758의 `nameToBase`) ----------
   * 지금 연표는 이름 하나를 찾을 때마다 모델을 통째로 훑는다. 여기서는 같은 차례로 표를 한 번 지어 두고 찾는다:
   * 항목(시대 → 사건 → 시대 구분) → 대범위 → 민족 → 트랙(이름 · id) → 분류 → 칸 → 인물(이름 → 다른 이름) → 가문 → 단체(형식 3).
   * '먼저 넣은 것이 이긴다' — 같은 이름의 인물 · 가문이 생겨도 이미 있던 고리의 목적지가 바뀌지 않게. */
  const byName = new Map();
  const figureByName = new Map();
  const put = (map, name, key) => {
    const n = String(name || '').trim().toLowerCase();
    if (n && !map.has(n)) map.set(n, key);
  };
  for (const p of model.periods) put(byName, p.name, p.uid);
  for (const e of model.events) put(byName, e.title, e.uid);
  for (const e of model.epochs) put(byName, e.name, e.uid);
  for (const s of model.scopes || []) put(byName, s.name, s.uid);
  for (const pe of model.peoples) put(byName, pe.name, `people:${pe.id}`);
  for (const t of model.tracks) {
    put(byName, t.name, `track:${t.id}`);
    put(byName, t.id, `track:${t.id}`);
  }
  for (const c of model.categories) put(byName, c.name, `category:${c.id}`);
  const docKinds = HT.CELL_KINDS.filter(k => k.doc !== false); // 문서를 다는 칸 종류 모두
  for (const p of model.periods) {
    for (const K of docKinds) {
      for (const c of HT.cellsOf(p, K)) {
        const key = HT.docKey.cell(p.uid, K.list, c);
        for (const v of [c.name, c.temple, c.title, c.given]) put(byName, v, key);
      }
    }
  }
  for (const f of model.figures || []) put(figureByName, f.name, f.uid);
  for (const f of model.figures || []) for (const a of f.aka || []) put(figureByName, a, f.uid);
  for (const [n, uid] of figureByName) put(byName, n, uid);
  for (const h of model.houses || []) put(byName, h.name, h.uid);
  // 단체(형식 3)는 가문 다음 — 새 기능이 이미 있던 고리의 목적지를 바꾸지 않게(지금 연표 nameToBase의 차례). "단체:이름"은 곧바로 단체로.
  const groupByName = new Map();
  for (const g of model.groups || []) put(groupByName, g.name, g.uid);
  for (const [n, uid] of groupByName) put(byName, n, uid);

  function nameToBase(name) {
    const n = String(name).trim().toLowerCase();
    if (!n) return null;
    const fm = n.match(/^인물\s*:\s*(.+)$/); // "인물:이름"은 곧바로 인물로
    if (fm) return figureByName.get(fm[1].trim()) || null;
    const gm = n.match(/^단체\s*:\s*(.+)$/); // "단체:이름"은 곧바로 단체로
    if (gm) return groupByName.get(gm[1].trim()) || null;
    return byName.get(n) || null;
  }

  /** `[[이름]]` · `[[이름/하위]]` · `[[/하위]]` → 문서 키(viewer.js 2789). */
  function linkToKey(name, ctxKey) {
    const raw = String(name).trim();
    if (raw.startsWith('/') && ctxKey) return `${ctxKey}//${raw.slice(1).split('/').filter(Boolean).join('//')}`;
    const whole = nameToBase(raw);
    if (whole) return whole;
    const parts = raw.split('/');
    for (let i = parts.length - 1; i >= 1; i--) {
      const base = nameToBase(parts.slice(0, i).join('/'));
      if (base) return `${base}//${parts.slice(i).filter(Boolean).join('//')}`;
    }
    return null;
  }

  return { namu, textOf, keysWithText, withText, docInfo, subdocsOf, linkToKey, docKinds };
}

export function contribute(ctx, out) {
  const { HT, model } = ctx;
  const T = tools(ctx);

  /* 1) 기록을 만들 열쇠를 모은다: 내용이 있는 문서 + 중간 단계 하위 문서 + 고리가 가리키는 곳. */
  const wanted = new Set(T.keysWithText);
  for (const key of T.keysWithText) {
    const { base, sub } = HT.docKey.split(key);
    const parts = sub ? sub.split('//') : [];
    for (let i = 1; i < parts.length; i++) wanted.add(`${base}//${parts.slice(0, i).join('//')}`);
    if (sub) wanted.add(base);
  }
  /* 2) 본문의 `[[고리]]`를 풀어 둔다 — 목적지도 기록이 있어야 창이 열린다. */
  const links = new Map(); // 문서 열쇠 → { 이름: {key, title, empty} }
  const back = new Map(); // 문서 열쇠 → [가리키는 문서 열쇠…]
  for (const key of T.keysWithText) {
    const found = {};
    for (const name of T.namu.links(T.textOf(key))) {
      const to = T.linkToKey(name, key);
      if (!to || !T.docInfo(to)) continue; // 연표에 없는 이름은 붉은 고리 — 싣지 않는다
      found[name] = to;
      wanted.add(to);
      if (to !== key) {
        if (!back.has(to)) back.set(to, []);
        if (!back.get(to).includes(key)) back.get(to).push(key);
      }
    }
    links.set(key, found);
  }

  /* 3) 기록을 싣는다. */
  const kinds = {};
  let bytes = 0;
  let empties = 0;
  const made = [];
  const blobs = new Map(); // 그림 열쇠 → { key, pack, mime, data } (문서가 쓰는 그림만 한 번씩)
  let figures = 0;
  for (const key of [...wanted].sort()) {
    const info = T.docInfo(key);
    if (!info) continue;
    const body = T.textOf(key);
    const rec = model.docs.get(key);
    const subs = T.subdocsOf(key);
    /* 빵 부스러기(viewer.js 2859의 `renderWikiSubs`): 칸 문서는 제 정권, 하위 문서는 바탕과 중간 단계. */
    const crumbs = [];
    if (info.parent && !info.sub) {
      const up = T.docInfo(info.parent);
      if (up) crumbs.push({ key: info.parent, label: up.title });
    }
    if (info.sub) {
      crumbs.push({ key: info.base, label: info.baseTitle });
      info.path.slice(0, -1).forEach((seg, i) => crumbs.push({ key: `${info.base}//${info.path.slice(0, i + 1).join('//')}`, label: seg }));
    }
    const link = {};
    for (const [name, to] of Object.entries(links.get(key) || {})) {
      const li = T.docInfo(to);
      if (!li) continue;
      link[name] = Object.assign({ key: to, title: li.title }, T.withText.has(to) ? null : { empty: 1 });
    }
    const json = {
      key,
      title: info.title,
      meta: info.meta,
      base: info.base,
    };
    if (info.baseTitle) json.baseTitle = info.baseTitle;
    if (info.sub) {
      json.sub = info.sub;
      json.path = info.path;
    }
    if (body) json.body = body;
    else {
      json.empty = 1;
      empties++;
    }
    if (rec && rec.packName) json.pack = rec.packName;
    if (info.uid) json.uid = info.uid;
    if (info.ref) json.ref = info.ref;
    if (info.at != null) json.at = info.at;
    if (info.span) json.span = info.span;
    if (!body && some(info.desc)) json.desc = info.desc; // 본문이 없는 창이 대신 보이는 설명(지금 연표의 `.wk-desc`)
    if (subs.length) json.subs = subs;
    if (crumbs.length) json.crumbs = crumbs;
    // 굵게 적는 지금 문서의 이름(빵 부스러기의 끝).
    if (crumbs.length) json.last = info.path.length ? info.path[info.path.length - 1] : info.title;
    if (some(link)) json.links = link;
    /* 문서 그림: 본문의 [[파일:이름]] → 그림 사전(그 문서 글을 적은 팩) — 지금 연표 문서 창의 imageResolver와 같은 찾기 */
    if (body && HT.docImageOf && T.namu.files) {
      const pics = {};
      for (const f of T.namu.files(body)) {
        if (!f.name || pics[f.name]) continue;
        const g = HT.docImageOf(model, rec && rec.packId, f.name);
        const m = g && typeof g.src === 'string' ? g.src.match(IMAGE_RE) : null;
        if (!m) continue;
        const data = g.src.slice(m[0].length);
        const [w, h] = g.width && g.height ? [g.width, g.height] : sizeOf(data);
        const one = { key: g.uid, mime: m[1], bytes: Math.floor((data.length * 3) / 4) - (data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0) };
        if (w && h) Object.assign(one, { w, h });
        for (const k of ['caption', 'alt', 'credit']) if (some(g[k])) one[k] = g[k];
        pics[f.name] = one;
        figures++;
        if (!blobs.has(g.uid)) blobs.set(g.uid, { key: g.uid, pack: ctx.packOf({ packId: g.packId }), mime: m[1], data });
      }
      if (some(pics)) json.images = pics;
    }
    const from = (back.get(key) || []).map(k => ({ key: k, title: (T.docInfo(k) || {}).title || k })).filter(b => b.title);
    if (from.length) json.back = from;

    const text = JSON.stringify(json);
    bytes += text.length;
    kinds[info.sub ? '하위' : HT.docKey.parse(info.base).type] = (kinds[info.sub ? '하위' : HT.docKey.parse(info.base).type] || 0) + 1;
    // 자료집 귀속(pack — 배치의 packs[] 순번): 본문을 실은 DLC. 본문이 없는 문서(중간 단계 · 고리의 목적지)는 그 바탕(항목 · 트랙 · 가문 …)의 DLC.
    const pack = rec && rec.packId ? ctx.packOf({ packId: rec.packId }) : info.pack || 0;
    made.push({ uid: `doc:${key}`, kind: 'doc', json: text, pack });
  }
  out.entities.push(...made);
  if (blobs.size) out.blobs = [...blobs.values()].sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)); // 그림이 없으면 열쇠도 없음(옛 배치 그대로)

  /* 4) 항목 기록에 실을 것을 모아 둔다(`contributeLate`와 `ctx.shared`). */
  const docsOf = {}; // 항목 uid → [{key, sub}]
  const cellDocsOf = {}; // 정권 uid → [칸 문서 열쇠…] (상세 창의 📄 — `bus.slot('docKeys')`)
  for (const key of T.keysWithText) {
    const { base, sub } = HT.docKey.split(key);
    if (!sub) continue;
    const info = T.docInfo(base);
    if (!info || !info.uid || info.ref) continue; // 칸 문서의 하위 문서는 그 칸의 몫이다
    const top = sub.split('//')[0];
    const list = (docsOf[info.uid] ||= []);
    if (!list.some(d => d.sub === top)) list.push({ key: `${base}//${top}`, sub: top });
  }
  for (const list of Object.values(docsOf)) list.sort((a, b) => HT.cmp16(a.sub, b.sub));
  for (const key of T.keysWithText) {
    const p = HT.docKey.parse(HT.docKey.split(key).base);
    if (p.type !== 'cell') continue;
    const list = (cellDocsOf[p.uid] ||= []);
    if (!list.includes(p.base)) list.push(p.base);
  }
  ctx.shared.docsOf = docsOf;
  ctx.shared.cellDocsOf = cellDocsOf;

  ctx.notes.문서 = Object.assign(
    { 기록: made.length, 본문없음: empties, 크기MB: Math.round((bytes / 1048576) * 100) / 100, 하위문서를_단_항목: Object.keys(docsOf).length, 칸문서를_단_항목: Object.keys(cellDocsOf).length },
    kinds,
  );
  if (blobs.size) Object.assign(ctx.notes.문서, { 그림_자리: figures, 그림: blobs.size, 그림MB: Math.round(([...blobs.values()].reduce((a, b) => a + b.data.length, 0) * 0.75 / 1048576) * 100) / 100 });
}

/**
 * `entities` 모듈이 돈 **뒤에** 한 번 더 부른다 — 항목 기록에 `x_docs`(하위 문서 칩)와
 * `x_cellDocs`(칸 목록의 📄가 있는 칸 열쇠)를 덧붙인다. 없으면 총괄이 `ctx.shared.docsOf` · `ctx.shared.cellDocsOf`를
 * `entities.mjs` 쪽에서 실어도 된다(둘은 같은 값이다).
 */
export function contributeLate(ctx, out) {
  const docsOf = ctx.shared.docsOf || {};
  const cellDocsOf = ctx.shared.cellDocsOf || {};
  let hit = 0;
  for (const e of out.entities) {
    if (e.kind === 'doc') continue;
    const subs = docsOf[e.uid];
    const cells = cellDocsOf[e.uid];
    if (!subs && !cells) continue;
    const json = JSON.parse(e.json);
    if (subs) json.x_docs = subs;
    if (cells) json.x_cellDocs = cells;
    e.json = JSON.stringify(json);
    hit++;
  }
  if (ctx.notes.문서) ctx.notes.문서.항목에_실음 = hit;
}
