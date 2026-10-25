/* 개편 목업 — 장면을 한 화면(1920×1080)으로 그리는 틀. 방향(theme)은 BASE의 고리 · 토큰을 바꿔 끼움. window.renderScreen · window.renderParts · window.BASE */
(function () {
  const { P, INK, mix, mixOk, ink, edgeSoft, tabInk, nameInk, E, T, TW, base, px, rr, tabPath, id, icon, fit } = K;
  const W = 1920, H = 1080, GUT = 240, DET = 380, HEAD = 56;

  function wrap(s, width, size, wt = 400, fam) {
    const out = []; let line = '';
    for (const word of s.split(' ')) {
      const t = line ? line + ' ' + word : word;
      if (TW(t, size, wt, fam) > width && line) { out.push(line); line = word; } else line = t;
    }
    if (line) out.push(line);
    return out;
  }

  /* ───────── 기준 방향: 간지(지금 언어를 다듬은 서류철 · B안) ─────────
     토큰 tok: 종이 · 먹 · 글꼴 역할(f) · 칠(fill) · 선의 짙기(edgeK) · 괘선 굵기(rule) */
  const BASE = {
    id: 'base', name: '간지',
    tok: {
      paper: '#ffffff', ink: '#000000',
      f: { ui: 'sans', name: 'sans', title: 'sans', body: 'sans', num: 'sans', gut: 'sans', cont: 'sans' },
      sz: { name: 9, cont: 10, title: 15, head: 20, gut: 11, num: 11, body: 14, cul: 10.5 },
      fill: .24, edgeK: .84, rule: 1, contRule: 1,
    },
    M: { top: 134, clipTop: 118, tabH: 13, bandH: 20, cellsH: 32, gap: 5, headH: 24, headH2: 22, padB: 7, afterC: 4, laneH: 12, laneGap: 2, closedRoom: 14, closedH: 24, trackGap: 6, cultureGap: 9, inset: 5 },

    k(a) { return ink(a, this.tok.paper, this.tok.ink); },
    /** 역할별 글 — role: ui · name · title · body · num · gut · cont */
    t(g, x, y, s, role, o = {}) { return T(g, x, y, s, { fam: this.tok.f[role] || 'sans', ...o }); },
    tw(s, size, role, wt = 700) { return TW(s, size, wt, this.tok.f[role] || 'sans'); },
    fillOf(c, p) { return K.fillC(c, p ?? this.tok.fill, this.tok.paper); },
    edgeOf(c) { return mixOk(c, this.tok.edgeK, this.tok.ink === '#000000' ? INK : this.tok.ink); },
    tabInkOf(c) { return tabInk(c); },
    nameInkOf(c) { return nameInk(c); },
    evInk() { return this.k(.8); },

    frame(S, p) {
      const k = a => this.k(a), tk = this.tok;
      E('rect', { x: 0, y: 0, width: W, height: H, fill: tk.paper }, p.bg);
      this.rule(p.frame, 0, W, HEAD - .5, k(.2));
      this.t(p.frame, 16, base(28, tk.sz.title), S.title, 'title', { size: tk.sz.title, fill: k(1) });
      E('path', { d: rr(248.5, 10.5, 720, 35, 6), fill: 'none', stroke: k(.2) }, p.frame);
      icon(p.frame, 'search', 262, 20, 16, k(.6));
      [['filter', W - 168], ['eye', W - 128], ['layers', W - 88], ['more', W - 48]].forEach(([n, x]) => icon(p.frame, n, x, 19, 18, k(1)));
      E('line', { x1: W - DET + .5, x2: W - DET + .5, y1: HEAD, y2: H, stroke: k(.2), 'stroke-width': tk.rule }, p.frame);
      E('line', { x1: GUT - .5, x2: GUT - .5, y1: HEAD, y2: H, stroke: k(.08) }, p.frame);
    },
    /** 가로 괘선(방향마다 겹선 등으로 바꿈) */
    rule(g, x0, x1, y, col, w = this.tok.rule) { E('line', { x1: x0, x2: x1, y1: y, y2: y, stroke: col, 'stroke-width': w }, g); },

    dateHeader(S, p, L) {
      const k = a => this.k(a), y0 = HEAD, M = this.M, tk = this.tok;
      for (let y = Math.ceil(S.win.y0 / 25) * 25; y <= S.win.y1; y += 25) {
        const x = px(p.X(y)); if (x < p.L || x > p.CR - 4) continue;
        this.gridLine(p, x, y0 + 24, y % 50 === 0);
        if (y % 50 === 0 && x + 4 + this.tw(String(y), tk.sz.num, 'num') < p.CR - 4) this.t(p.dateh, x + 4, base(y0 + 13, tk.sz.num), String(y), 'num', { size: tk.sz.num, fill: k(.8) });
      }
      this.t(p.dateh, GUT - 12, base(y0 + 13, 10), `${S.win.y1 - S.win.y0}년 보기`, 'ui', { size: 10, wt: 400, fill: k(.6), anchor: 'end' });
      E('line', { x1: GUT, x2: W - DET, y1: y0 + 24.5, y2: y0 + 24.5, stroke: k(.08) }, p.dateh);
      this.t(p.dateh, GUT - 12, base(y0 + 38, 10), '시대', 'ui', { size: 10, fill: k(.6), anchor: 'end' });
      const lanes = []; for (const l of S.labels) { let i = lanes.findIndex(e => e <= l.a); if (i < 0) { i = lanes.length; lanes.push(0); } lanes[i] = l.b; l.lane = i; }
      for (const l of S.labels) this.labelEra(S, p, { x0: p.X(Math.max(l.a, S.win.y0)), x1: Math.min(p.X(l.b), p.CR + 20), y: y0 + 28 + l.lane * 16, h: 14, cl: l.a < S.win.y0, cr: l.b > S.win.y1 }, l.n, p.dateh);
      this.rule(p.dateh, 0, W - DET, M.clipTop - .5, k(.2));
    },
    gridLine(p, x, y, major) { E('line', { x1: x, x2: x, y1: y, y2: H, stroke: major ? this.k(.08) : this.k(.04), 'stroke-dasharray': '2 3' }, p.grid); },
    labelEra(S, p, g, name, layer) {
      const k = a => this.k(a);
      E('path', { d: rr(px(g.x0), px(g.y), Math.round(g.x1 - g.x0), g.h - 1, 2), fill: k(.05), stroke: k(.2) }, layer);
      const s = fit(name, g.x1 - g.x0 - 12, 9.5); if (s) this.t(layer, g.x0 + 6, base(g.y + g.h / 2, 9.5), s, 'ui', { size: 9.5, fill: k(.8) });
    },

    gutter(S, p, L) {
      const k = a => this.k(a), g = p.gut, tk = this.tok;
      for (const C of L.cultures) {
        this.cultureStrip(g, C);
        for (const Tr of C.tracks || []) if (Tr.n !== C.n) {
          const cs = [...Tr.n], ty = (Tr.y0 + Tr.y1) / 2 - (cs.length - 1) * 6;
          E('line', { x1: 21.5, x2: 21.5, y1: Tr.y0 + 2, y2: Tr.y1 - 2, stroke: k(.2) }, g);
          cs.forEach((ch, i) => this.t(g, 30, base(ty + i * 12, 10), ch, 'gut', { size: 10, fill: k(.6), anchor: 'middle' }));
        }
      }
      for (const c of L.containers) {
        icon(g, 'folder', 44 + c.depth * 10, c.yTop + 5, 12, k(.6), 1.5);
        this.t(g, 60 + c.depth * 10, base(c.yTop + 11, tk.sz.gut), c.n, 'gut', { size: tk.sz.gut, fill: k(.8) });
      }
      for (const r of L.rows) {
        const x = 50 + r.depth * 10;
        E('circle', { cx: x, cy: r.yBand + r.h / 2, r: 2.5, fill: this.edgeOf(r.items[0].c) }, g);
        let s = r.label || r.items.map(o => o.n).join(' · '); while (this.tw(s, tk.sz.gut, 'gut') > GUT - x - 18 && s.length > 2) s = s.slice(0, -2) + '…';
        this.t(g, x + 7, base(r.yBand + r.h / 2, tk.sz.gut), s, 'gut', { size: tk.sz.gut, fill: k(.8) });
      }
      for (const C of L.closed) {
        icon(g, 'right', 44, C.rowY + C.rowH / 2 - 7, 14, k(.6));
        this.t(g, 60, base(C.rowY + C.rowH / 2, tk.sz.gut), C.n, 'gut', { size: tk.sz.gut, fill: k(.8) });
        this.t(g, 60 + this.tw(C.n, tk.sz.gut, 'gut') + 5, base(C.rowY + C.rowH / 2, 10), String(C.count), 'ui', { size: 10, fill: k(.4) });
      }
    },
    cultureStrip(g, C) {
      const k = a => this.k(a), tk = this.tok;
      E('path', { d: rr(2.5, px(C.y0), 15, Math.round(C.y1 - C.y0), 7.5), fill: k(.05), stroke: 'none' }, g);
      const chars = [...C.n.replace(/ /g, '')], cy = (C.y0 + C.y1) / 2 - (chars.length - 1) * 6.5;
      chars.forEach((ch, i) => this.t(g, 10, base(cy + i * 13, tk.sz.cul), ch, 'gut', { size: tk.sz.cul, fill: k(.8), anchor: 'middle' }));
    },

    /* 그릇(펼침) — 큰 폴더 + 큰 간지 탭. 나라 · 연방은 제 색 9%, 시대는 먹 4% */
    container(S, p, c, g) {
      const k = a => this.k(a), tk = this.tok;
      const top = c.yTop + 15, colored = c.t !== '시대' && c.c;
      const fill = colored ? this.fillOf(c.c, .09) : k(c.depth ? .05 : .035), stroke = colored ? mixOk(c.c, .55, tk.paper) : k(.2);
      const x0 = px(g.x0), x1 = Math.round(g.x1) - .5;
      E('path', { d: `M${x0 + 18},${px(top - 3)} H${x1 - 18}`, stroke: colored ? mixOk(c.c, .35, tk.paper) : k(.12), fill: 'none' }, p.cont);
      E('path', { d: rr(x0, px(top), x1 - x0, Math.round(g.yBottom - top), [g.cl ? 0 : 12, g.cr ? 0 : 12, g.cr ? 0 : 12, g.cl ? 0 : 12]), fill, stroke, 'stroke-width': tk.contRule }, p.cont);
      const tx = g.cl ? p.CL + 10 : x0 + 12;
      this.tabT(p.cont, tx, px(top), c.n, { th: 15, size: tk.sz.cont, role: 'cont', fill, stroke, ink: colored ? mix(c.c, .25, INK) : k(.85), count: c.rows.reduce((n, r) => n + r.items.length, 0), countInk: k(.45), s: 8 });
      for (const l of c.labels || []) this.labelEra(S, p, { x0: p.X(l.a), x1: p.X(l.b), y: top + 3, h: 13 }, l.n, p.cont);
    },
    closedCulture(S, p, C) {
      const k = a => this.k(a), tk = this.tok;
      const x0 = p.CL - 30, x1 = p.CR + 30, Y = px(C.rowY), Hh = C.rowH - 1;
      for (const t of C.tabs) this.tabT(p.cont, px(p.X(t.y)), Y, t.n, { fill: this.fillOf(t.c), stroke: this.edgeOf(t.c), ink: this.tabInkOf(t.c), behind: true });
      E('path', { d: rr(x0, Y, x1 - x0, Hh, 10), fill: k(.035), stroke: k(.2) }, p.cont);
      this.t(p.cont, p.CL + 10, base(Y + Hh / 2, 10.5), C.n, 'cont', { size: 10.5, fill: k(.85) });
      this.t(p.cont, p.CL + 14 + this.tw(C.n, 10.5, 'cont'), base(Y + Hh / 2, 10), String(C.count), 'ui', { size: 10, fill: k(.45) });
      icon(p.cont, 'down', p.CR - 26, Y + Hh / 2 - 7, 14, k(.5));
    },

    /** 탭(간지) — 글꼴 역할을 따름 */
    tabT(g, xL, yBase, label, o = {}) { return tab(g, xL, yBase, label, { fam: this.tok.f[o.role || 'name'], size: this.tok.sz.name, ...o }); },

    /* 객체 띠 */
    shape(g) { return [g.cl ? 0 : 2, g.cr ? 0 : 6, g.cr ? 0 : 6, g.cl ? 0 : 6]; },
    object(S, p, o, g) {
      const tk = this.tok;
      if (o.serve) this.serve(S, p, o, g);
      const fill = this.fillOf(o.c), stroke = this.edgeOf(o.c);
      const X0 = px(g.x0), X1 = Math.round(g.x1) - .5, Y = px(g.y), Hh = Math.round(g.h) - 1;
      const b = { X0, X1, Y, Hh, fill, stroke };
      this.body(S, p, o, g, b);
      const left = g.cl ? p.CL + 6 : X0 + 2, room = X1 - left - 8;
      if (o.g === '무리') { const s = fit(o.n, room, 9.5, 700, tk.f.name); if (s) this.t(p.band, left + 6, base(Y + Hh / 2, 9.5), s, 'name', { size: 9.5, fill: this.nameInkOf(o.c) }); }
      else {
        const s = fit(o.n, room - 26, tk.sz.name, 700, tk.f.name);
        if (s) g.tabR = (o.g === '영토 밖' ? this.tabSq : this.tabT).call(this, p.band, left, Y, s, { fill, stroke, ink: this.tabInkOf(o.c), pad: s.length === 1 ? 7 : 13 });
      }
      if (o.cells || o.offices) this.cells(S, p, o, g, b);
      if (o.power) this.power(S, p, o, g, b);
      if (o.ev && !o.cells && !o.offices) this.events(S, p, o, g, b);
      if (o.tags) this.tags(S, p, o, g, b);
      if (o.selected) this.select(S, p, o, g, b);
    },
    body(S, p, o, g, b) { E('path', { d: rr(b.X0, b.Y, b.X1 - b.X0, b.Hh, this.shape(g)), fill: b.fill, stroke: b.stroke, 'stroke-dasharray': o.rival ? '3 2' : null }, p.band); },
    tabSq(g, xL, yBase, label, o = {}) { return tabSquare(g, xL, yBase, label, { fam: this.tok.f.name, size: this.tok.sz.name, ...o }); },
    cells(S, p, o, g, b) {
      const y = b.Y + b.Hh - 17, h = 15;
      if (o.cells) for (const [n, a, e] of o.cells) {
        const x0 = Math.max(p.X(a), b.X0 + 3) + .5, x1 = Math.min(p.X(e), b.X1 - 3) - .5; if (x1 - x0 < 3) continue;
        E('path', { d: rr(px(x0), px(y), Math.round(x1 - x0) - 1, h, 3), fill: mix(b.fill, .5, this.tok.paper), stroke: edgeSoft(o.c) }, p.band);
        const s = fit(n, x1 - x0 - 6, 9, 400, this.tok.f.body); if (s) this.t(p.band, x0 + 3, base(y + h / 2 + .5, 9), s, 'body', { size: 9, wt: 400, fill: this.nameInkOf(o.c) });
      }
      if (o.offices) o.offices.forEach((f, i) => {
        const yy = b.Y + 3 + i * 14, x0 = Math.max(p.X(f.a), b.X0 + 3), x1 = Math.min(p.X(f.b), b.X1 - 3);
        E('path', { d: rr(px(x0), px(yy), Math.round(x1 - x0) - 1, 12, 3), fill: mix(b.fill, .5, this.tok.paper), stroke: edgeSoft(o.c), 'stroke-dasharray': f.status === '대립' ? '3 2' : null }, p.band);
        this.t(p.band, Math.max(x0, p.CL + 4) + 4, base(yy + 6.5, 8.5), f.n, 'name', { size: 8.5, fill: this.nameInkOf(o.c) });
      });
    },
    power(S, p, o, g, b) {
      for (const pw of o.power) {
        const x0 = Math.max(p.X(pw.a), b.X0 + 3), x1 = Math.min(p.X(pw.b), b.X1 - 3), y = o.cells ? b.Y + 3 : b.Y + b.Hh - 5, h = o.cells ? 12 : 3;
        E('path', { d: rr(px(x0), px(y), Math.round(x1 - x0) - 1, h, 2), fill: mixOk(o.c, .7, INK), stroke: 'none' }, p.band);
        const s = fit(pw.n, x1 - x0 - 8, 8); if (s && h >= 11) this.t(p.band, x0 + 4, base(y + h / 2 + .5, 8), s, 'ui', { size: 8, fill: '#ffffff' });
      }
    },
    events(S, p, o, g, b) {
      for (const e of o.ev) {
        const x = p.X(e.y); if (x < b.X0 + 30 || x > b.X1 - 6) continue;
        const cy = o.power ? b.Y + (b.Hh - 5) / 2 : b.Y + b.Hh / 2;
        E('circle', { cx: x, cy, r: 2.5, fill: this.edgeOf(o.c) }, p.band);
        const w = this.tw(e.n, 9.5, 'body', 400); if (x + 6 + w < b.X1 - 6) this.t(p.band, x + 6, base(cy, 9.5), e.n, 'body', { size: 9.5, wt: 400, fill: this.evInk(o) });
      }
    },
    tags(S, p, o, g, b) {
      const k = a => this.k(a);
      let last = (g.tabR || b.X0) + 4;
      for (const t of o.tags) {
        const x = Math.max(px(p.X(t.a)), last);
        last = this.tabT(p.under, x, b.Y, t.n, { fill: k(.06), stroke: k(.3), ink: k(.65), behind: true, size: 8.5, th: 12 }) + 3;
      }
    },
    serve(S, p, o, g) {
      const s = o.serve, x0 = px(Math.max(p.X(s.a), g.x0)), x1 = Math.round(g.x1) - .5, Y = px(g.y - 4);
      const f = this.fillOf(s.c, .4), st = this.edgeOf(s.c);
      E('path', { d: rr(x0, Y, x1 - x0, Math.round(g.h) + 3, [6, g.cr ? 0 : 6, g.cr ? 0 : 6, 6]), fill: f, stroke: st }, p.under);
      const w = this.tw(s.to, 8.5, 'name') + 18, tx = Math.min(x1 - w - 10, p.CR - w - 8);
      if (tx > x0 + 40) this.tabT(p.under, tx, Y, s.to, { fill: f, stroke: st, ink: this.tabInkOf(s.c), size: 8.5, th: 11, pad: 9, s: 6 });
    },
    select(S, p, o, g, b) { E('path', { d: rr(b.X0 - 2, b.Y - 2, b.X1 - b.X0 + 4, b.Hh + 4, [4, 8, 8, 8]), fill: 'none', stroke: INK }, p.over); },
    link(S, p, a, b, how) {
      const y = px(a.y + a.h / 2), x0 = Math.round(a.x1) - .5, x1 = px(b.x0);
      if (x1 - x0 < 1) return;
      E('line', { x1: x0, x2: x1, y1: y, y2: y, stroke: this.k(.45), 'stroke-dasharray': how === 'indirect' ? '2 2' : null }, p.links);
    },
    lanes(S, p, L) {
      const k = a => this.k(a), segs = [];
      for (const r of L.lanes) {
        const l = r.lane, x0 = Math.max(p.X(l.a), p.CL - 30), x1 = Math.min(p.X(l.b), p.CR + 30), y = px(r.laneY), h = this.M.laneH - 1;
        E('path', { d: rr(px(x0), y, Math.round(x1 - x0), h, 2), fill: k(.06), stroke: k(.35), 'stroke-dasharray': l.status === '주장' ? '3 2' : null }, p.band);
        const tx = Math.max(x0, p.CL + 4) + 5;
        this.t(p.band, tx, base(y + h / 2 + .5, 8.5), l.n, 'name', { size: 8.5, fill: k(.75) });
        segs.push({ x0, x1, y: y + h / 2 });
      }
      for (let i = 1; i < segs.length; i++) {
        const a = segs[i - 1], b = segs[i];
        E('path', { d: `M${a.x1},${a.y} H${px(Math.max(a.x1 + 4, b.x0 - 4))} V${b.y} H${b.x0}`, fill: 'none', stroke: k(.5), 'stroke-dasharray': '2 2' }, p.links);
      }
    },

    detail(S, p) {
      const k = a => this.k(a), g = p.detail, d = S.detail, x = W - DET + 24, w = DET - 48, tk = this.tok;
      let y = HEAD + 30;
      this.t(g, x, base(y, 12), d.path.join('  ›  '), 'ui', { size: 12, wt: 400, fill: k(.6) });
      icon(g, 'x', W - 44, y - 8, 16, k(.8));
      y += 30; this.t(g, x, base(y, tk.sz.head), d.title, 'title', { size: tk.sz.head, fill: k(1) });
      y += 26; this.t(g, x, base(y, 14), d.when, 'num', { size: 14, wt: 400, fill: k(.6) });
      y += 26;
      const bw = this.tw(d.kind, 12, 'ui') + 16; E('path', { d: rr(px(x), px(y - 10), Math.round(bw), 20, 4), fill: 'none', stroke: k(.25) }, g);
      this.t(g, x + 8, base(y, 12), d.kind, 'ui', { size: 12, fill: k(.85) });
      this.t(g, x + bw + 8, base(y, 12), d.group, 'ui', { size: 12, wt: 400, fill: k(.5) });
      y += 30;
      for (const line of wrap(d.text, w, tk.sz.body, 400, tk.f.body)) { this.t(g, x, base(y, tk.sz.body), line, 'body', { size: tk.sz.body, wt: 400, fill: k(.85) }); y += 22; }
      y += 8;
      const sec = () => { this.rule(g, x, x + w, px(y), k(.2)); y += 22; };
      sec();
      for (const [a, b] of d.facts) { this.t(g, x, base(y, 13), a, 'ui', { size: 13, wt: 400, fill: k(.6) }); this.t(g, x + 92, base(y, 13), b, 'name', { size: 13, fill: k(.9) }); y += 24; }
      for (const f of d.offices) {
        y += 6; sec();
        this.t(g, x, base(y, 14), f.n, 'title', { size: 14, fill: k(1) });
        this.t(g, x + this.tw(f.n, 14, 'title') + 8, base(y, 12), `${f.count}${f.note ? ' · ' + f.note : ''}`, 'ui', { size: 12, wt: 400, fill: k(.5) });
        y += 24;
        for (const [n, t] of f.rows) { this.t(g, x, base(y, 13), n, 'body', { size: 13, wt: 400, fill: k(.85) }); this.t(g, x + w, base(y, 12), t, 'num', { size: 12, wt: 400, fill: k(.5), anchor: 'end' }); y += 24; }
      }
      y += 6; sec();
      for (const [a, b, c] of d.links) { this.t(g, x, base(y, 13), a, 'ui', { size: 13, wt: 400, fill: k(.6) }); this.t(g, x + 92, base(y, 13), b, 'name', { size: 13, fill: k(.9) }); this.t(g, x + w, base(y, 12), c, 'ui', { size: 12, wt: 400, fill: k(.5), anchor: 'end' }); y += 24; }
    },
    /* 확대 단추는 머리 줄에(그림판 위에 떠서 띠 끝을 덮지 않게 — Fable 검토의 공통 흠 1) */
    zoom(S, p) {
      const k = a => this.k(a), x = W - 330, y = 10.5;
      E('path', { d: rr(px(x), y, 108, 35, 6), fill: this.tok.paper, stroke: k(.2) }, p.top);
      ['minus', 'plus', 'expand'].forEach((n, i) => icon(p.top, n, x + 10 + i * 34, 20, 16, k(.85)));
      E('line', { x1: px(x + 36), x2: px(x + 36), y1: 16, y2: 40, stroke: k(.12) }, p.top); E('line', { x1: px(x + 70), x2: px(x + 70), y1: 16, y2: 40, stroke: k(.12) }, p.top);
    },
  };

  /* 탭(간지) — behind: 띠 뒤에(밑변을 닫지 않음) */
  function tab(g, xL, yBase, label, o = {}) {
    const size = o.size || 9, th = o.th || 13, pad = o.pad ?? 13, s = o.s ?? 7, fam = o.fam || 'sans';
    const extra = o.count != null ? 4 + TW(String(o.count), size, 700) : 0;
    const w = TW(label, size, 700, fam) + pad * 2 + extra, xR = xL + w;
    const pp = tabPath(xL, xR, yBase, th, s);
    E('path', { d: o.behind ? pp.open : pp.fill, fill: o.fill }, g);
    E('path', { d: pp.stroke, fill: 'none', stroke: o.stroke, 'stroke-width': o.sw || 1 }, g);
    T(g, xL + pad, base(yBase - th / 2, size) + .3, label, { size, fill: o.ink, fam });
    if (o.count != null) T(g, xL + pad + TW(label, size, 700, fam) + 4, base(yBase - th / 2, size) + .3, String(o.count), { size, fill: o.countInk || '#888' });
    return xR;
  }
  function tabSquare(g, xL, yBase, label, o = {}) {
    const size = o.size || 9, th = o.th || 13, pad = (o.pad ?? 13) - 4, fam = o.fam || 'sans';
    const w = TW(label, size, 700, fam) + pad * 2, xR = xL + w, yT = yBase - th;
    const d = `M${xL},${yBase} V${yT + 1.5} Q${xL},${yT} ${xL + 1.5},${yT} H${xR - 1.5} Q${xR},${yT} ${xR},${yT + 1.5} V${yBase}`;
    E('path', { d: d + ` V${yBase + 1.5} H${xL} Z`, fill: o.fill }, g);
    E('path', { d, fill: 'none', stroke: o.stroke }, g);
    T(g, xL + pad, base(yBase - th / 2, size) + .3, label, { size, fill: o.ink, fam });
    return xR;
  }

  function contGeom(p, c, S, th) {
    let x0 = p.X(c.a), x1 = p.X(c.b), cl = false, cr = false;
    if (c.a < S.win.y0) { x0 = p.CL - 30; cl = true; } if (c.b > S.win.y1) { x1 = p.CR + 30; cr = true; }
    const par = c.stack[c.stack.length - 1];
    if (par && par.geo) { if (!par.geo.cl) x0 = Math.max(x0, par.geo.x0 + th.M.inset); if (!par.geo.cr) x1 = Math.min(x1, par.geo.x1 - th.M.inset); }
    return { x0, x1, yTop: c.yTop, yBottom: c.yBottom, cl, cr };
  }
  function objGeom(p, o, row, k, S, th) {
    let x0 = p.X(o.a), x1 = p.X(o.b), cl = false, cr = false;
    if (o.a < S.win.y0) { x0 = p.CL - 30; cl = true; } if (o.b > S.win.y1) { x1 = p.CR + 30; cr = true; }
    const c = row.stack[row.stack.length - 1];
    if (c && c.geo) {
      if (!o.outL && !c.geo.cl) x0 = Math.max(x0, c.geo.x0 + th.M.inset);
      if (!o.outR && !c.geo.cr) x1 = Math.min(x1, c.geo.x1 - th.M.inset);
      if (c.geo.cl && o.a <= c.a) { x0 = p.CL - 30; cl = true; }
      if (c.geo.cr && o.b >= c.b) { x1 = p.CR + 30; cr = true; }
    }
    const prev = row.items[k - 1], next = row.items[k + 1];
    if (prev && prev.b === o.a) x0 += 2; if (next && next.a === o.b) x1 -= 2;
    if (x1 - x0 < 2) return null;
    return { o, row, x0, x1, y: row.yBand, h: row.h, cl, cr };
  }
  function merge(theme) {
    const th = Object.assign({}, BASE, theme);
    th.M = Object.assign({}, BASE.M, theme.M || {});
    th.tok = Object.assign({}, BASE.tok, theme.tok || {});
    th.tok.f = Object.assign({}, BASE.tok.f, (theme.tok || {}).f || {});
    th.tok.sz = Object.assign({}, BASE.tok.sz, (theme.tok || {}).sz || {});
    return th;
  }
  function layers(svg) { const p = {}; for (const kk of ['bg', 'grid', 'cont', 'under', 'links', 'band', 'over', 'dateh', 'gut', 'frame', 'detail', 'top']) p[kk] = E('g', {}, svg); return p; }

  function renderScreen(host, theme) {
    const th = merge(theme);
    /* 2단계 결정 판: 갈래(방향)마다 장면을 바꿔 끼울 수 있음 — theme.scene(S) 가 고친 장면을 돌려줌(없으면 같은 장면) */
    const S0 = JSON.parse(JSON.stringify(SCENE));
    const S = th.scene ? th.scene(S0) || S0 : S0;
    const L = layoutScene(S, th.M);
    const svg = E('svg', { width: W, height: H, viewBox: `0 0 ${W} ${H}`, class: 'screen' }, host);
    const p = Object.assign({ svg, defs: E('defs', {}, svg), W, H, CL: GUT, CR: W - DET, L: GUT + 8, R: W - DET - 12 }, layers(svg));
    p.X = y => p.L + (y - S.win.y0) / (S.win.y1 - S.win.y0) * (p.R - p.L);
    const cid = id('clip'), cp = E('clipPath', { id: cid }, p.defs);
    E('rect', { x: GUT, y: th.M.clipTop, width: W - DET - GUT, height: H - th.M.clipTop }, cp);
    for (const kk of ['grid', 'under', 'cont', 'links', 'band', 'over']) p[kk].setAttribute('clip-path', `url(#${cid})`);
    th.frame(S, p, L); th.dateHeader(S, p, L); th.gutter(S, p, L);
    for (const c of [...L.containers].sort((a, b) => a.depth - b.depth)) { c.geo = contGeom(p, c, S, th); th.container(S, p, c, c.geo); }
    for (const C of L.closed) th.closedCulture(S, p, C);
    const geos = [];
    for (const row of L.rows) row.items.forEach((o, k) => { const g = objGeom(p, o, row, k, S, th); if (g) { o.geo = g; geos.push(g); } });
    for (const g of geos) th.object(S, p, g.o, g);
    for (const row of L.rows) for (let k = 1; k < row.items.length; k++) { const a = row.items[k - 1].geo, b = row.items[k].geo; if (a && b && row.items[k].from) th.link(S, p, a, b, row.items[k].from); }
    th.lanes(S, p, L);
    if (th.extra) th.extra(S, p, L);
    th.detail(S, p); th.zoom(S, p);
    return { p, L, th, S };
  }

  /* 부품 판 — 같은 고리로 작은 장면(갈래 넷 · 그릇 펼침/접힘 · 섬김 · 끌지 않는 그릇 · 직위 줄 · 이어짐) */
  function renderParts(host, theme) {
    const th = merge(theme);
    const PW = 1800, PH = 300;
    const svg = E('svg', { width: PW, height: PH, viewBox: `0 0 ${PW} ${PH}`, class: 'parts' }, host);
    const p = Object.assign({ svg, defs: E('defs', {}, svg), W: PW, H: PH, CL: 0, CR: PW, L: 0, R: PW }, layers(svg));
    E('rect', { x: 0, y: 0, width: PW, height: PH, fill: th.tok.paper }, p.bg);
    const S = { win: { y0: 0, y1: 1000 } };
    const k = a => th.k(a);
    const cap = (x, y, s) => T(p.top, x, y, s, { size: 11, wt: 400, fill: k(.5) });
    const M = th.M, rowH = M.tabH + M.bandH + 10;
    const objs = [['국가', '다스림', P.rose, '다스리는 것'], ['실권 정권', '다스림', P.sage, '실권 정권 · 섬김'], ['교단', '영토 밖', P.mocha, '영토가 본업이 아닌 것'], ['집단', '무리', P.sand, '사람의 무리']];
    p.X = y => 20 + y * 0.42;
    objs.forEach(([t, gname, c, label], i) => {
      const y = 30 + i * (rowH + 14);
      const o = { n: t === '집단' ? '반달' : t === '교단' ? '로마 교단' : t === '실권 정권' ? '가마쿠라 막부' : '고려', a: 0, b: 900, c, t, g: gname };
      if (t === '실권 정권') o.serve = { to: '조정', c: P.lav, rel: '명목상', a: 300 };
      if (t === '국가') o.tags = [{ n: '합스부르크', a: 600 }];
      th.object(S, p, o, { o, x0: p.X(60), x1: p.X(900), y: y + M.tabH, h: M.bandH, cl: false, cr: false });
      cap(p.X(920), base(y + M.tabH + M.bandH / 2, 11), label);
    });
    const cx = 640; p.X = y => cx + y * 0.5;
    const cTop = 22, inner = cTop + M.headH;
    const rows = [{ yBand: inner + M.tabH }, { yBand: inner + 2 * M.tabH + M.bandH + M.gap }];
    const cBot = rows[1].yBand + M.bandH + M.padB;
    const c = { n: '전국 시대', t: '시대', depth: 0, stack: [], rows: [{ items: [{}, {}] }], labels: [], yTop: cTop, yBottom: cBot };
    c.geo = { x0: p.X(0), x1: p.X(600), yTop: cTop, yBottom: cBot, cl: false, cr: false }; th.container(S, p, c, c.geo);
    [['다케다', 30, 500, P.rose], ['오다', 200, 580, P.butter]].forEach(([n, a, b2, col], i) => {
      const o = { n, a, b: b2, c: col, t: '군벌', g: '다스림' };
      th.object(S, p, o, { o, x0: p.X(a), x1: p.X(b2), y: rows[i].yBand, h: M.bandH, cl: false, cr: false });
    });
    cap(p.X(0), cBot + 18, '그릇 펼침');
    const C = { n: '초원', count: 9, tabs: [{ n: '몽골 제국', y: 40, c: P.sand }, { n: '금장 칸국', y: 260, c: P.peach }, { n: '티무르', y: 470, c: P.mint }], rowY: cBot + 44, rowH: M.closedH };
    const sv = [p.CL, p.CR]; p.CL = p.X(0) + 30; p.CR = p.X(600) - 30; th.closedCulture(S, p, C); [p.CL, p.CR] = sv;
    cap(p.X(0), C.rowY + C.rowH + 18, '그릇 접힘');
    const rx = 1020; p.X = y => rx + y * 0.6;
    th.lanes(S, p, { lanes: [{ laneY: 40, lane: { n: '칼리파위', a: 0, b: 300 } }, { laneY: 80, lane: { n: '칼리파위', a: 330, b: 700, status: '명목' } }, { laneY: 120, lane: { n: '칼리파위', a: 700, b: 1000, status: '주장' } }] });
    cap(rx, 160, '직위 줄 · 옮겨 앉음(이어짐)');
    return svg;
  }

  window.BASE = BASE; window.renderScreen = renderScreen; window.renderParts = renderParts; window.MOCK = { tab, tabSquare, wrap, merge, W, H, GUT, DET, HEAD };
})();
