/* 개편 목업 — 공용 그리기 도구 (모든 방향이 함께 씀). window.K */
(function () {
  const P = { rose: '#d4a39b', peach: '#dab195', butter: '#d7c18e', sage: '#b6c398', mint: '#9dbea8', sky: '#a0bcc5', peri: '#abb3c9', lav: '#bbacc8', pink: '#d1a9b9', sand: '#c8b193', slate: '#a4b1b7', mocha: '#bba395' };
  const INK = '#1b1a19';
  const hx = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const toHex = a => '#' + a.map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('');
  const mix = (c, p, base = '#ffffff') => { const a = hx(c), b = hx(base); return toHex(a.map((v, i) => v * p + b[i] * (1 - p))); };
  const lin = v => (v /= 255) <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4;
  const delin = v => 255 * (v <= .0031308 ? 12.92 * v : 1.055 * Math.max(v, 0) ** (1 / 2.4) - .055);
  function oklab(c) { const [r, g, b] = hx(c).map(lin); const l = Math.cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b), m = Math.cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b), s = Math.cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b); return [.2104542553 * l + .793617785 * m - .0040720468 * s, 1.9779984951 * l - 2.428592205 * m + .4505937099 * s, .0259040371 * l + .7827717662 * m - .808675766 * s]; }
  function unOklab([L, A, B]) { const l = (L + .3963377774 * A + .2158037573 * B) ** 3, m = (L - .1055613458 * A - .0638541728 * B) ** 3, s = (L - .0894841775 * A - 1.291485548 * B) ** 3; return toHex([4.0767416621 * l - 3.3077115913 * m + .2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - .3413193965 * s, -.0041960863 * l - .7034186147 * m + 1.707614701 * s].map(delin)); }
  const mixOk = (c, p, base) => { const a = oklab(c), b = oklab(base); return unOklab(a.map((v, i) => v * p + b[i] * (1 - p))); };
  /** 먹의 불투명도를 종이 위의 불투명 색으로 */
  const ink = (a, paper = '#ffffff', inkc = '#000000') => mix(inkc, a, paper);

  const NS = 'http://www.w3.org/2000/svg';
  function E(tag, at, parent) { const e = document.createElementNS(NS, tag); for (const k in at) if (at[k] != null && at[k] !== false) e.setAttribute(k, at[k]); if (parent) parent.appendChild(e); return e; }
  const cvx = document.createElement('canvas').getContext('2d');
  const FONT = { sans: '"Pretendard", "Malgun Gothic", sans-serif', serif: '"RIDIBatang", "Batang", serif', heavy: '"ChosunKm", "Batang", serif' };
  function TW(s, size = 9, wt = 700, fam = 'sans') { if (fam === 'heavy' || fam === 'serif') wt = 400; cvx.font = `${wt} ${size}px ${FONT[fam] || fam}`; const ls = 0; return cvx.measureText(String(s)).width + ls; }
  function T(g, x, y, s, o = {}) {
    const wt = (o.fam === 'heavy' || o.fam === 'serif') ? 400 : (o.wt || 700);
    const e = E('text', { x, y, 'font-size': o.size || 9, 'font-weight': wt, fill: o.fill || INK, 'text-anchor': o.anchor || 'start', 'letter-spacing': o.ls, opacity: o.op, 'font-style': o.italic ? 'italic' : null, 'writing-mode': o.vertical ? 'vertical-rl' : null }, g);
    e.style.fontFamily = FONT[o.fam || 'sans'] || o.fam;
    e.textContent = s; return e;
  }
  /** 글줄 가운데 → 바탕선 */
  const base = (center, size) => center + size * .36;
  const px = v => Math.round(v) + .5;
  /** 왼쪽 둥근 rl · 오른쪽 둥근 rr(각 모서리 따로: [tl, tr, br, bl]도) */
  function rr(x, y, w, h, r = 10, r2) {
    let tl, tr, br, bl;
    if (Array.isArray(r)) [tl, tr, br, bl] = r; else { tl = bl = r; tr = br = (r2 ?? r); }
    const c = v => Math.max(0, Math.min(v, h / 2, w / 2));
    tl = c(tl); tr = c(tr); br = c(br); bl = c(bl);
    const a = (q, x2, y2) => q ? `A${q},${q} 0 0 1 ${x2},${y2}` : '';
    return `M${x + tl},${y} H${x + w - tr} ${a(tr, x + w, y + tr)} V${y + h - br} ${a(br, x + w - br, y + h)} H${x + bl} ${a(bl, x, y + h - bl)} V${y + tl} ${a(tl, x + tl, y)} Z`;
  }
  /** 간지 탭 — 종이 윗변이 어깨로 솟은 모양 */
  function tabPath(xL, xR, yBase, th, s = 7) {
    const yT = yBase - th;
    const stroke = `M${xL},${yBase} C${xL + s * .55},${yBase} ${xL + s * .45},${yT} ${xL + s},${yT} L${xR - s},${yT} C${xR - s * .45},${yT} ${xR - s * .55},${yBase} ${xR},${yBase}`;
    return { fill: stroke + ` L${xR},${yBase + 1.5} L${xL},${yBase + 1.5} Z`, open: stroke + ' Z', stroke };
  }
  function roundPoly(pts, r) {
    const n = pts.length; let d = '';
    for (let i = 0; i < n; i++) {
      const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n];
      const l1 = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]), l2 = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
      const q = Math.min(r, l1 / 2, l2 / 2);
      const a = [p1[0] + (p0[0] - p1[0]) / l1 * q, p1[1] + (p0[1] - p1[1]) / l1 * q];
      const b = [p1[0] + (p2[0] - p1[0]) / l2 * q, p1[1] + (p2[1] - p1[1]) / l2 * q];
      d += (i ? ' L' : 'M') + `${a[0]},${a[1]} Q${p1[0]},${p1[1]} ${b[0]},${b[1]}`;
    }
    return d + ' Z';
  }
  let uid = 0; const id = p => (p || 'k') + (++uid);

  /* 선 아이콘 — Lucide 규격(24칸 · 굵기 1.5) */
  const ICON = {
    search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    filter: '<path d="M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4"/>',
    eye: '<path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0"/><circle cx="12" cy="12" r="3"/>',
    layers: '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    plus: '<path d="M5 12h14M12 5v14"/>',
    minus: '<path d="M5 12h14"/>',
    expand: '<path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>',
    down: '<path d="m6 9 6 6 6-6"/>',
    right: '<path d="m9 18 6-6-6-6"/>',
    folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    book: '<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/>',
    doc: '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>',
  };
  function icon(g, name, x, y, size = 16, color = INK, sw = 1.5) {
    const s = size / 24;
    const gg = E('g', { transform: `translate(${x},${y}) scale(${s})`, fill: 'none', stroke: color, 'stroke-width': sw / s, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, g);
    gg.innerHTML = ICON[name] || '';
    return gg;
  }
  /** 글을 폭에 맞춰 줄임(이름 → 첫 글자 → 없음) */
  function fit(s, room, size, wt = 700, fam) {
    if (TW(s, size, wt, fam) <= room) return s;
    if (TW(s[0], size, wt, fam) <= room) return s[0];
    return '';
  }
  window.K = { P, INK, mix, mixOk, ink, edge: c => mixOk(c, .84, INK), edgeSoft: c => mixOk(c, .92, INK), fillC: (c, p = .24, paper = '#ffffff') => mix(c, p, paper), tabInk: c => mix(c, .22, INK), nameInk: c => mix(c, .45, INK), E, T, TW, base, px, rr, tabPath, roundPoly, id, icon, fit, FONT };
})();
