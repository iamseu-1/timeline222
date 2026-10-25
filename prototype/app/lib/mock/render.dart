// JS 이름(BASE의 고리 · M · L · S · C · X0 · Y · Hh · W · H · GUT · DET · HEAD · PW · PH)을 그대로 둔다 — 목업을 줄 그대로 옮겨 견주기 쉽게.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'js.dart';
import 'kit.dart';
import 'scene.dart';
import 'svg_lite.dart';

// 장면을 한 화면(1920×1080)으로 그리는 틀 — .claude/research/stage2/mock/render.js(sha256 88ae7d054e8c)를 줄 그대로 옮김.
// 원본의 저장소 사본: test/mock/source/render.js — 연구 폴더의 원본이 바뀌어도 옮긴 판의 기준은 이 사본이다.
// 방향(theme)은 BASE의 고리 · 토큰을 바꿔 끼운다: JS의 merge(theme)는 상속이 대신한다 — 갈래는 BaseTheme을 물려받아 고리(메서드)를 덮어쓰고,
// tok · M은 덮어쓸 열쇠만 tokOverride · mOverride로 돌려준다. 고리 안의 this.k(a)는 Dart에서도 덮어쓴 메서드가 불린다.
// 장면 · 줄 배치 · 자리(g · b)는 JS 객체처럼 Map<String, dynamic>이고 열쇠 이름은 JS 그대로다(갈래가 같은 열쇠를 읽고 더한다).

const W = 1920, H = 1080, GUT = 240, DET = 380, HEAD = 56;

const _P = K.P;

List<String> wrap(String s, num width, num size, [num wt = 400, String? fam]) {
  final out = <String>[];
  var line = '';
  for (final word in s.split(' ')) {
    final t = line.isNotEmpty ? '$line $word' : word;
    if (K.TW(t, size, wt, fam) > width && line.isNotEmpty) {
      out.add(line);
      line = word;
    } else {
      line = t;
    }
  }
  if (line.isNotEmpty) out.add(line);
  return out;
}

/// 그리기 층(JS의 p). 그림판 층(grid ~ over)은 renderScreen이 x GUT ~ W−DET · y clipTop ~ H로 자른다.
class MockLayers {
  /// defs 다음에 층 열둘을 JS layers()의 차례(bg · grid · cont · under · links · band · over · dateh · gut · frame · detail · top)로 svg에 단다
  /// — 초기화 목록은 적힌 차례대로 돌므로 이 차례가 곧 그리는 차례다.
  MockLayers(this.svg, {required this.W, required this.H, required this.CL, required this.CR, required this.L, required this.R})
      : defs = E('defs', {}, svg),
        bg = E('g', {}, svg),
        grid = E('g', {}, svg),
        cont = E('g', {}, svg),
        under = E('g', {}, svg),
        links = E('g', {}, svg),
        band = E('g', {}, svg),
        over = E('g', {}, svg),
        dateh = E('g', {}, svg),
        gut = E('g', {}, svg),
        frame = E('g', {}, svg),
        detail = E('g', {}, svg),
        top = E('g', {}, svg);

  final MockEl svg, defs, bg, grid, cont, under, links, band, over, dateh, gut, frame, detail, top;
  final num W, H, L, R;

  /// 그림판 좌우 끝 — 부품 판(renderParts)이 접힌 문화권을 그리는 동안 잠시 바꾼다.
  num CL, CR;

  /// 해 → x.
  late double Function(num year) X;
}

/* ───────── 기준 방향: 간지(지금 언어를 다듬은 서류철 · B안) ─────────
   토큰 tok: 종이 · 먹 · 글꼴 역할(f) · 칠(fill) · 선의 짙기(edgeK) · 괘선 굵기(rule) */
class BaseTheme {
  String get id => 'base';
  String get name => '간지';
  // 기준 방향에는 없는 값(JS undefined) — 갈래가 덮어쓴다.
  String? get code => null;
  String? get idea => null;
  String? get pro => null;
  String? get con => null;
  bool get rec => false;
  String? get by => null;
  Map<String, dynamic>? get opt => null;

  static const Map<String, dynamic> baseTok = {
    'paper': '#ffffff', 'ink': '#000000',
    'f': {'ui': 'sans', 'name': 'sans', 'title': 'sans', 'body': 'sans', 'num': 'sans', 'gut': 'sans', 'cont': 'sans'},
    'sz': {'name': 9, 'cont': 10, 'title': 15, 'head': 20, 'gut': 11, 'num': 11, 'body': 14, 'cul': 10.5},
    'fill': .24, 'edgeK': .84, 'rule': 1, 'contRule': 1,
  };
  static const Map<String, num> baseM = {
    'top': 134, 'clipTop': 118, 'tabH': 13, 'bandH': 20, 'cellsH': 32, 'gap': 5, 'headH': 24, 'headH2': 22, 'padB': 7, 'afterC': 4, //
    'laneH': 12, 'laneGap': 2, 'closedRoom': 14, 'closedH': 24, 'trackGap': 6, 'cultureGap': 9, 'inset': 5,
  };

  /// 갈래가 바꿀 토큰의 열쇠만(f · sz는 그 안의 열쇠만 — 한 겹 더 합친다).
  Map<String, dynamic> get tokOverride => const {};

  /// 갈래가 바꿀 치수의 열쇠만.
  Map<String, num> get mOverride => const {};

  /// render.js merge의 tok — 갈래의 값을 덮고, f · sz는 한 겹 더 합친다. 처음 읽을 때 합친다(갈래의 생성자가 끝난 뒤라 그 필드를 써도 됨).
  late final Map<String, dynamic> tok = {
    ...baseTok,
    ...tokOverride,
    'f': <String, dynamic>{...baseTok['f'] as Map<String, dynamic>, ...?tokOverride['f'] as Map<String, dynamic>?},
    'sz': <String, dynamic>{...baseTok['sz'] as Map<String, dynamic>, ...?tokOverride['sz'] as Map<String, dynamic>?},
  };

  /// render.js merge의 M — 한 겹만 합친다.
  late final Map<String, num> M = {...baseM, ...mOverride};

  /// 갈래(방향)마다 장면을 바꿔 끼우는 고리 — 고친 장면을 돌려준다(null이면 받은 장면 그대로 — JS에서 th.scene이 없을 때와 같음).
  Map<String, dynamic>? scene(Map<String, dynamic> S) => null;

  String k(num a) => K.ink(a, tok['paper'], tok['ink']);

  /// 역할별 글 — role: ui · name · title · body · num · gut · cont
  MockEl t(MockEl g, num x, num y, Object s, String role, [Map<String, Object?> o = const {}]) => K.T(g, x, y, s, {'fam': jsOr(tok['f'][role], 'sans'), ...o});
  double tw(Object s, num size, String role, [num wt = 700]) => K.TW(s, size, wt, jsOr(tok['f'][role], 'sans'));
  String fillOf(String c, [num? p]) => K.fillC(c, p ?? tok['fill'], tok['paper']);
  String edgeOf(String c) => K.mixOk(c, tok['edgeK'], tok['ink'] == '#000000' ? K.INK : tok['ink']);
  String tabInkOf(String c) => K.tabInk(c);
  String nameInkOf(String c) => K.nameInk(c);

  /// 사건 글의 먹 — 기준 방향은 객체를 보지 않는다(render.js가 객체를 넘기므로 갈래는 그것을 써도 됨).
  String evInk([Map<String, dynamic>? o]) => k(.8);

  // ───────── 틀 ─────────
  void frame(Map<String, dynamic> S, MockLayers p, [Map<String, dynamic>? L]) {
    final tk = tok;
    E('rect', {'x': 0, 'y': 0, 'width': W, 'height': H, 'fill': tk['paper']}, p.bg);
    rule(p.frame, 0, W, HEAD - .5, k(.2));
    t(p.frame, 16, K.base(28, tk['sz']['title']), S['title'], 'title', {'size': tk['sz']['title'], 'fill': k(1)});
    E('path', {'d': K.rr(248.5, 10.5, 720, 35, 6), 'fill': 'none', 'stroke': k(.2)}, p.frame);
    K.icon(p.frame, 'search', 262, 20, 16, k(.6));
    for (final (n, x) in [('filter', W - 168), ('eye', W - 128), ('layers', W - 88), ('more', W - 48)]) {
      K.icon(p.frame, n, x, 19, 18, k(1));
    }
    E('line', {'x1': W - DET + .5, 'x2': W - DET + .5, 'y1': HEAD, 'y2': H, 'stroke': k(.2), 'stroke-width': tk['rule']}, p.frame);
    E('line', {'x1': GUT - .5, 'x2': GUT - .5, 'y1': HEAD, 'y2': H, 'stroke': k(.08)}, p.frame);
  }

  /// 가로 괘선(방향마다 겹선 등으로 바꿈)
  void rule(MockEl g, num x0, num x1, num y, String col, [num? w]) {
    E('line', {'x1': x0, 'x2': x1, 'y1': y, 'y2': y, 'stroke': col, 'stroke-width': w ?? tok['rule']}, g);
  }

  // ───────── 날짜 칸 ─────────
  void dateHeader(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) {
    const y0 = HEAD;
    final tk = tok;
    for (var y = ((S['win']['y0'] as num) / 25).ceil() * 25; y <= S['win']['y1']; y += 25) {
      final x = K.px(p.X(y));
      if (x < p.L || x > p.CR - 4) continue;
      gridLine(p, x, y0 + 24, y % 50 == 0);
      if (y % 50 == 0 && x + 4 + tw(jsStr(y), tk['sz']['num'], 'num') < p.CR - 4) t(p.dateh, x + 4, K.base(y0 + 13, tk['sz']['num']), jsStr(y), 'num', {'size': tk['sz']['num'], 'fill': k(.8)});
    }
    t(p.dateh, GUT - 12, K.base(y0 + 13, 10), '${jsNum(S['win']['y1'] - S['win']['y0'])}년 보기', 'ui', {'size': 10, 'wt': 400, 'fill': k(.6), 'anchor': 'end'});
    E('line', {'x1': GUT, 'x2': W - DET, 'y1': y0 + 24.5, 'y2': y0 + 24.5, 'stroke': k(.08)}, p.dateh);
    t(p.dateh, GUT - 12, K.base(y0 + 38, 10), '시대', 'ui', {'size': 10, 'fill': k(.6), 'anchor': 'end'});
    // 이름표 시대를 겹치지 않는 줄에 앉힌다 — 장면의 이름표에 그 줄(lane)을 적는다(그래서 장면은 그릴 때마다 새것).
    final lanes = <num>[];
    for (final l in S['labels']) {
      var i = lanes.indexWhere((e) => e <= l['a']);
      if (i < 0) {
        i = lanes.length;
        lanes.add(0);
      }
      lanes[i] = l['b'];
      l['lane'] = i;
    }
    for (final l in S['labels']) {
      labelEra(S, p, {'x0': p.X(jsMax(l['a'], S['win']['y0'])), 'x1': jsMin(p.X(l['b']), p.CR + 20), 'y': y0 + 28 + l['lane'] * 16, 'h': 14, 'cl': l['a'] < S['win']['y0'], 'cr': l['b'] > S['win']['y1']}, l['n'], p.dateh);
    }
    rule(p.dateh, 0, W - DET, M['clipTop']! - .5, k(.2));
  }

  void gridLine(MockLayers p, num x, num y, bool major) {
    E('line', {'x1': x, 'x2': x, 'y1': y, 'y2': H, 'stroke': major ? k(.08) : k(.04), 'stroke-dasharray': '2 3'}, p.grid);
  }

  void labelEra(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> g, String name, MockEl layer) {
    E('path', {'d': K.rr(K.px(g['x0']), K.px(g['y']), jsRound(g['x1'] - g['x0']), g['h'] - 1, 2), 'fill': k(.05), 'stroke': k(.2)}, layer);
    final s = K.fit(name, g['x1'] - g['x0'] - 12, 9.5);
    if (s.isNotEmpty) t(layer, g['x0'] + 6, K.base(g['y'] + g['h'] / 2, 9.5), s, 'ui', {'size': 9.5, 'fill': k(.8)});
  }

  // ───────── 거터 ─────────
  void gutter(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) {
    final g = p.gut, tk = tok;
    for (final C in L['cultures']) {
      cultureStrip(g, C);
      for (final Tr in C['tracks'] ?? []) {
        if (Tr['n'] == C['n']) continue;
        final cs = [for (final r in (Tr['n'] as String).runes) String.fromCharCode(r)], ty = (Tr['y0'] + Tr['y1']) / 2 - (cs.length - 1) * 6;
        E('line', {'x1': 21.5, 'x2': 21.5, 'y1': Tr['y0'] + 2, 'y2': Tr['y1'] - 2, 'stroke': k(.2)}, g);
        for (final (i, ch) in cs.indexed) {
          t(g, 30, K.base(ty + i * 12, 10), ch, 'gut', {'size': 10, 'fill': k(.6), 'anchor': 'middle'});
        }
      }
    }
    for (final c in L['containers']) {
      K.icon(g, 'folder', 44 + c['depth'] * 10, c['yTop'] + 5, 12, k(.6), 1.5);
      t(g, 60 + c['depth'] * 10, K.base(c['yTop'] + 11, tk['sz']['gut']), c['n'], 'gut', {'size': tk['sz']['gut'], 'fill': k(.8)});
    }
    for (final r in L['rows']) {
      final x = 50 + r['depth'] * 10;
      E('circle', {'cx': x, 'cy': r['yBand'] + r['h'] / 2, 'r': 2.5, 'fill': edgeOf(r['items'][0]['c'])}, g);
      String s = jsOr(r['label'], (r['items'] as List).map((o) => o['n']).join(' · '));
      while (tw(s, tk['sz']['gut'], 'gut') > GUT - x - 18 && s.length > 2) {
        s = '${s.substring(0, s.length - 2)}…';
      }
      t(g, x + 7, K.base(r['yBand'] + r['h'] / 2, tk['sz']['gut']), s, 'gut', {'size': tk['sz']['gut'], 'fill': k(.8)});
    }
    for (final C in L['closed']) {
      K.icon(g, 'right', 44, C['rowY'] + C['rowH'] / 2 - 7, 14, k(.6));
      t(g, 60, K.base(C['rowY'] + C['rowH'] / 2, tk['sz']['gut']), C['n'], 'gut', {'size': tk['sz']['gut'], 'fill': k(.8)});
      t(g, 60 + tw(C['n'], tk['sz']['gut'], 'gut') + 5, K.base(C['rowY'] + C['rowH'] / 2, 10), jsStr(C['count']), 'ui', {'size': 10, 'fill': k(.4)});
    }
  }

  void cultureStrip(MockEl g, Map<String, dynamic> C) {
    final tk = tok;
    E('path', {'d': K.rr(2.5, K.px(C['y0']), 15, jsRound(C['y1'] - C['y0']), 7.5), 'fill': k(.05), 'stroke': 'none'}, g);
    final chars = [for (final r in (C['n'] as String).replaceAll(' ', '').runes) String.fromCharCode(r)], cy = (C['y0'] + C['y1']) / 2 - (chars.length - 1) * 6.5;
    for (final (i, ch) in chars.indexed) {
      t(g, 10, K.base(cy + i * 13, tk['sz']['cul']), ch, 'gut', {'size': tk['sz']['cul'], 'fill': k(.8), 'anchor': 'middle'});
    }
  }

  // ───────── 그릇 ─────────
  /// 그릇(펼침) — 큰 폴더 + 큰 간지 탭. 나라 · 연방은 제 색 9%, 시대는 먹 4%
  void container(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> c, Map<String, dynamic> g) {
    final tk = tok;
    final top = c['yTop'] + 15, colored = c['t'] != '시대' && jsTruthy(c['c']);
    final fill = colored ? fillOf(c['c'], .09) : k(jsTruthy(c['depth']) ? .05 : .035), stroke = colored ? K.mixOk(c['c'], .55, tk['paper']) : k(.2);
    final x0 = K.px(g['x0']), x1 = jsRound(g['x1']) - .5;
    final cl = jsTruthy(g['cl']), cr = jsTruthy(g['cr']);
    E('path', {'d': 'M${jsNum(x0 + 18)},${jsNum(K.px(top - 3))} H${jsNum(x1 - 18)}', 'stroke': colored ? K.mixOk(c['c'], .35, tk['paper']) : k(.12), 'fill': 'none'}, p.cont);
    E('path', {'d': K.rr(x0, K.px(top), x1 - x0, jsRound(g['yBottom'] - top), [cl ? 0 : 12, cr ? 0 : 12, cr ? 0 : 12, cl ? 0 : 12]), 'fill': fill, 'stroke': stroke, 'stroke-width': tk['contRule']}, p.cont);
    final tx = cl ? p.CL + 10 : x0 + 12;
    tabT(p.cont, tx, K.px(top), c['n'], {'th': 15, 'size': tk['sz']['cont'], 'role': 'cont', 'fill': fill, 'stroke': stroke, 'ink': colored ? K.mix(c['c'], .25, K.INK) : k(.85), 'count': (c['rows'] as List).fold<int>(0, (n, r) => n + (r['items'] as List).length), 'countInk': k(.45), 's': 8});
    for (final l in c['labels'] ?? []) {
      labelEra(S, p, {'x0': p.X(l['a']), 'x1': p.X(l['b']), 'y': top + 3, 'h': 13}, l['n'], p.cont);
    }
  }

  void closedCulture(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> C) {
    final x0 = p.CL - 30, x1 = p.CR + 30, Y = K.px(C['rowY']), Hh = C['rowH'] - 1;
    for (final t in C['tabs']) {
      tabT(p.cont, K.px(p.X(t['y'])), Y, t['n'], {'fill': fillOf(t['c']), 'stroke': edgeOf(t['c']), 'ink': tabInkOf(t['c']), 'behind': true});
    }
    E('path', {'d': K.rr(x0, Y, x1 - x0, Hh, 10), 'fill': k(.035), 'stroke': k(.2)}, p.cont);
    t(p.cont, p.CL + 10, K.base(Y + Hh / 2, 10.5), C['n'], 'cont', {'size': 10.5, 'fill': k(.85)});
    t(p.cont, p.CL + 14 + tw(C['n'], 10.5, 'cont'), K.base(Y + Hh / 2, 10), jsStr(C['count']), 'ui', {'size': 10, 'fill': k(.45)});
    K.icon(p.cont, 'down', p.CR - 26, Y + Hh / 2 - 7, 14, k(.5));
  }

  /// 탭(간지) — 글꼴 역할을 따름
  num tabT(MockEl g, num xL, num yBase, String label, [Map<String, dynamic> o = const {}]) => tab(g, xL, yBase, label, {'fam': tok['f'][jsOr(o['role'], 'name')], 'size': tok['sz']['name'], ...o});

  // ───────── 객체 띠 ─────────
  /// 띠의 모서리 반지름 — rr의 r(수 또는 [tl, tr, br, bl])
  Object shape(Map<String, dynamic> g) => [jsTruthy(g['cl']) ? 0 : 2, jsTruthy(g['cr']) ? 0 : 6, jsTruthy(g['cr']) ? 0 : 6, jsTruthy(g['cl']) ? 0 : 6];

  void object(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g) {
    final tk = tok;
    if (jsTruthy(o['serve'])) serve(S, p, o, g);
    final fill = fillOf(o['c']), stroke = edgeOf(o['c']);
    final X0 = K.px(g['x0']), X1 = jsRound(g['x1']) - .5, Y = K.px(g['y']), Hh = jsRound(g['h']) - 1;
    final b = <String, dynamic>{'X0': X0, 'X1': X1, 'Y': Y, 'Hh': Hh, 'fill': fill, 'stroke': stroke};
    body(S, p, o, g, b);
    final left = jsTruthy(g['cl']) ? p.CL + 6 : X0 + 2, room = X1 - left - 8;
    if (o['g'] == '무리') {
      final s = K.fit(o['n'], room, 9.5, 700, tk['f']['name']);
      if (s.isNotEmpty) t(p.band, left + 6, K.base(Y + Hh / 2, 9.5), s, 'name', {'size': 9.5, 'fill': nameInkOf(o['c'])});
    } else {
      final s = K.fit(o['n'], room - 26, tk['sz']['name'], 700, tk['f']['name']);
      if (s.isNotEmpty) g['tabR'] = (o['g'] == '영토 밖' ? tabSq : tabT)(p.band, left, Y, s, {'fill': fill, 'stroke': stroke, 'ink': tabInkOf(o['c']), 'pad': s.length == 1 ? 7 : 13});
    }
    if (jsTruthy(o['cells']) || jsTruthy(o['offices'])) cells(S, p, o, g, b);
    if (jsTruthy(o['power'])) power(S, p, o, g, b);
    if (jsTruthy(o['ev']) && !jsTruthy(o['cells']) && !jsTruthy(o['offices'])) events(S, p, o, g, b);
    if (jsTruthy(o['tags'])) tags(S, p, o, g, b);
    if (jsTruthy(o['selected'])) select(S, p, o, g, b);
  }

  void body(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b) {
    E('path', {'d': K.rr(b['X0'], b['Y'], b['X1'] - b['X0'], b['Hh'], shape(g)), 'fill': b['fill'], 'stroke': b['stroke'], 'stroke-dasharray': jsTruthy(o['rival']) ? '3 2' : null}, p.band);
  }

  num tabSq(MockEl g, num xL, num yBase, String label, [Map<String, dynamic> o = const {}]) => tabSquare(g, xL, yBase, label, {'fam': tok['f']['name'], 'size': tok['sz']['name'], ...o});

  void cells(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b) {
    final y = b['Y'] + b['Hh'] - 17;
    const h = 15;
    if (jsTruthy(o['cells'])) {
      for (final [n, a, e, ...] in o['cells']) {
        final x0 = jsMax(p.X(a), b['X0'] + 3) + .5, x1 = jsMin(p.X(e), b['X1'] - 3) - .5;
        if (x1 - x0 < 3) continue;
        E('path', {'d': K.rr(K.px(x0), K.px(y), jsRound(x1 - x0) - 1, h, 3), 'fill': K.mix(b['fill'], .5, tok['paper']), 'stroke': K.edgeSoft(o['c'])}, p.band);
        final s = K.fit(n, x1 - x0 - 6, 9, 400, tok['f']['body']);
        if (s.isNotEmpty) t(p.band, x0 + 3, K.base(y + h / 2 + .5, 9), s, 'body', {'size': 9, 'wt': 400, 'fill': nameInkOf(o['c'])});
      }
    }
    if (jsTruthy(o['offices'])) {
      for (final (i, f) in (o['offices'] as List).indexed) {
        final yy = b['Y'] + 3 + i * 14, x0 = jsMax(p.X(f['a']), b['X0'] + 3), x1 = jsMin(p.X(f['b']), b['X1'] - 3);
        E('path', {'d': K.rr(K.px(x0), K.px(yy), jsRound(x1 - x0) - 1, 12, 3), 'fill': K.mix(b['fill'], .5, tok['paper']), 'stroke': K.edgeSoft(o['c']), 'stroke-dasharray': f['status'] == '대립' ? '3 2' : null}, p.band);
        t(p.band, jsMax(x0, p.CL + 4) + 4, K.base(yy + 6.5, 8.5), f['n'], 'name', {'size': 8.5, 'fill': nameInkOf(o['c'])});
      }
    }
  }

  void power(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b) {
    for (final pw in o['power']) {
      final x0 = jsMax(p.X(pw['a']), b['X0'] + 3), x1 = jsMin(p.X(pw['b']), b['X1'] - 3), y = jsTruthy(o['cells']) ? b['Y'] + 3 : b['Y'] + b['Hh'] - 5, h = jsTruthy(o['cells']) ? 12 : 3;
      E('path', {'d': K.rr(K.px(x0), K.px(y), jsRound(x1 - x0) - 1, h, 2), 'fill': K.mixOk(o['c'], .7, K.INK), 'stroke': 'none'}, p.band);
      final s = K.fit(pw['n'], x1 - x0 - 8, 8);
      if (s.isNotEmpty && h >= 11) t(p.band, x0 + 4, K.base(y + h / 2 + .5, 8), s, 'ui', {'size': 8, 'fill': '#ffffff'});
    }
  }

  void events(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b) {
    for (final e in o['ev']) {
      final x = p.X(e['y']);
      if (x < b['X0'] + 30 || x > b['X1'] - 6) continue;
      final cy = jsTruthy(o['power']) ? b['Y'] + (b['Hh'] - 5) / 2 : b['Y'] + b['Hh'] / 2;
      E('circle', {'cx': x, 'cy': cy, 'r': 2.5, 'fill': edgeOf(o['c'])}, p.band);
      final w = tw(e['n'], 9.5, 'body', 400);
      if (x + 6 + w < b['X1'] - 6) t(p.band, x + 6, K.base(cy, 9.5), e['n'], 'body', {'size': 9.5, 'wt': 400, 'fill': evInk(o)});
    }
  }

  void tags(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b) {
    num last = jsOr(g['tabR'], b['X0']) + 4;
    for (final t in o['tags']) {
      final x = jsMax(K.px(p.X(t['a'])), last);
      last = tabT(p.under, x, b['Y'], t['n'], {'fill': k(.06), 'stroke': k(.3), 'ink': k(.65), 'behind': true, 'size': 8.5, 'th': 12}) + 3;
    }
  }

  void serve(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g) {
    final s = o['serve'], x0 = K.px(jsMax(p.X(s['a']), g['x0'])), x1 = jsRound(g['x1']) - .5, Y = K.px(g['y'] - 4);
    final f = fillOf(s['c'], .4), st = edgeOf(s['c']);
    E('path', {'d': K.rr(x0, Y, x1 - x0, jsRound(g['h']) + 3, [6, jsTruthy(g['cr']) ? 0 : 6, jsTruthy(g['cr']) ? 0 : 6, 6]), 'fill': f, 'stroke': st}, p.under);
    final w = tw(s['to'], 8.5, 'name') + 18, tx = jsMin(x1 - w - 10, p.CR - w - 8);
    if (tx > x0 + 40) tabT(p.under, tx, Y, s['to'], {'fill': f, 'stroke': st, 'ink': tabInkOf(s['c']), 'size': 8.5, 'th': 11, 'pad': 9, 's': 6});
  }

  void select(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b) {
    E('path', {'d': K.rr(b['X0'] - 2, b['Y'] - 2, b['X1'] - b['X0'] + 4, b['Hh'] + 4, [4, 8, 8, 8]), 'fill': 'none', 'stroke': K.INK}, p.over);
  }

  // ───────── 이어짐 · 직위 줄 ─────────
  void link(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> a, Map<String, dynamic> b, String how) {
    final y = K.px(a['y'] + a['h'] / 2), x0 = jsRound(a['x1']) - .5, x1 = K.px(b['x0']);
    if (x1 - x0 < 1) return;
    E('line', {'x1': x0, 'x2': x1, 'y1': y, 'y2': y, 'stroke': k(.45), 'stroke-dasharray': how == 'indirect' ? '2 2' : null}, p.links);
  }

  void lanes(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) {
    final segs = <({num x0, num x1, num y})>[];
    for (final r in L['lanes']) {
      final l = r['lane'], x0 = jsMax(p.X(l['a']), p.CL - 30), x1 = jsMin(p.X(l['b']), p.CR + 30), y = K.px(r['laneY']), h = M['laneH']! - 1;
      E('path', {'d': K.rr(K.px(x0), y, jsRound(x1 - x0), h, 2), 'fill': k(.06), 'stroke': k(.35), 'stroke-dasharray': l['status'] == '주장' ? '3 2' : null}, p.band);
      final tx = jsMax(x0, p.CL + 4) + 5;
      t(p.band, tx, K.base(y + h / 2 + .5, 8.5), l['n'], 'name', {'size': 8.5, 'fill': k(.75)});
      segs.add((x0: x0, x1: x1, y: y + h / 2));
    }
    for (var i = 1; i < segs.length; i++) {
      final a = segs[i - 1], b = segs[i];
      E('path', {'d': 'M${jsNum(a.x1)},${jsNum(a.y)} H${jsNum(K.px(jsMax(a.x1 + 4, b.x0 - 4)))} V${jsNum(b.y)} H${jsNum(b.x0)}', 'fill': 'none', 'stroke': k(.5), 'stroke-dasharray': '2 2'}, p.links);
    }
  }

  /// 갈래가 다 그린 뒤 더 그릴 것(JS th.extra — 기준 방향에는 없음).
  void extra(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) {}

  // ───────── 상세 ─────────
  void detail(Map<String, dynamic> S, MockLayers p) {
    const x = W - DET + 24, w = DET - 48;
    final g = p.detail, d = S['detail'], tk = tok;
    var y = HEAD + 30;
    t(g, x, K.base(y, 12), (d['path'] as List).join('  ›  '), 'ui', {'size': 12, 'wt': 400, 'fill': k(.6)});
    K.icon(g, 'x', W - 44, y - 8, 16, k(.8));
    y += 30;
    t(g, x, K.base(y, tk['sz']['head']), d['title'], 'title', {'size': tk['sz']['head'], 'fill': k(1)});
    y += 26;
    t(g, x, K.base(y, 14), d['when'], 'num', {'size': 14, 'wt': 400, 'fill': k(.6)});
    y += 26;
    final bw = tw(d['kind'], 12, 'ui') + 16;
    E('path', {'d': K.rr(K.px(x), K.px(y - 10), jsRound(bw), 20, 4), 'fill': 'none', 'stroke': k(.25)}, g);
    t(g, x + 8, K.base(y, 12), d['kind'], 'ui', {'size': 12, 'fill': k(.85)});
    t(g, x + bw + 8, K.base(y, 12), d['group'], 'ui', {'size': 12, 'wt': 400, 'fill': k(.5)});
    y += 30;
    for (final line in wrap(d['text'], w, tk['sz']['body'], 400, tk['f']['body'])) {
      t(g, x, K.base(y, tk['sz']['body']), line, 'body', {'size': tk['sz']['body'], 'wt': 400, 'fill': k(.85)});
      y += 22;
    }
    y += 8;
    void sec() {
      rule(g, x, x + w, K.px(y), k(.2));
      y += 22;
    }

    sec();
    for (final [a, b, ...] in d['facts']) {
      t(g, x, K.base(y, 13), a, 'ui', {'size': 13, 'wt': 400, 'fill': k(.6)});
      t(g, x + 92, K.base(y, 13), b, 'name', {'size': 13, 'fill': k(.9)});
      y += 24;
    }
    for (final f in d['offices']) {
      y += 6;
      sec();
      t(g, x, K.base(y, 14), f['n'], 'title', {'size': 14, 'fill': k(1)});
      t(g, x + tw(f['n'], 14, 'title') + 8, K.base(y, 12), '${jsStr(f['count'])}${jsTruthy(f['note']) ? ' · ${jsStr(f['note'])}' : ''}', 'ui', {'size': 12, 'wt': 400, 'fill': k(.5)});
      y += 24;
      // 이 줄의 t는 기간 글이다 — 고리 t는 this.t로 부른다.
      for (final [n, t, ...] in f['rows']) {
        this.t(g, x, K.base(y, 13), n, 'body', {'size': 13, 'wt': 400, 'fill': k(.85)});
        this.t(g, x + w, K.base(y, 12), t, 'num', {'size': 12, 'wt': 400, 'fill': k(.5), 'anchor': 'end'});
        y += 24;
      }
    }
    y += 6;
    sec();
    for (final [a, b, c, ...] in d['links']) {
      t(g, x, K.base(y, 13), a, 'ui', {'size': 13, 'wt': 400, 'fill': k(.6)});
      t(g, x + 92, K.base(y, 13), b, 'name', {'size': 13, 'fill': k(.9)});
      t(g, x + w, K.base(y, 12), c, 'ui', {'size': 12, 'wt': 400, 'fill': k(.5), 'anchor': 'end'});
      y += 24;
    }
  }

  /// 확대 단추는 머리 줄에(그림판 위에 떠서 띠 끝을 덮지 않게 — Fable 검토의 공통 흠 1)
  void zoom(Map<String, dynamic> S, MockLayers p) {
    const x = W - 330, y = 10.5;
    E('path', {'d': K.rr(K.px(x), y, 108, 35, 6), 'fill': tok['paper'], 'stroke': k(.2)}, p.top);
    for (final (i, n) in ['minus', 'plus', 'expand'].indexed) {
      K.icon(p.top, n, x + 10 + i * 34, 20, 16, k(.85));
    }
    E('line', {'x1': K.px(x + 36), 'x2': K.px(x + 36), 'y1': 16, 'y2': 40, 'stroke': k(.12)}, p.top);
    E('line', {'x1': K.px(x + 70), 'x2': K.px(x + 70), 'y1': 16, 'y2': 40, 'stroke': k(.12)}, p.top);
  }
}

/// 탭(간지) — behind: 띠 뒤에(밑변을 닫지 않음)
num tab(MockEl g, num xL, num yBase, String label, [Map<String, dynamic> o = const {}]) {
  final num size = jsOr(o['size'], 9), th = jsOr(o['th'], 13), pad = o['pad'] ?? 13, s = o['s'] ?? 7;
  final String fam = jsOr(o['fam'], 'sans');
  final extra = o['count'] != null ? 4 + K.TW(jsStr(o['count']), size, 700) : 0;
  final w = K.TW(label, size, 700, fam) + pad * 2 + extra, xR = xL + w;
  final pp = K.tabPath(xL, xR, yBase, th, s);
  E('path', {'d': jsTruthy(o['behind']) ? pp.open : pp.fill, 'fill': o['fill']}, g);
  E('path', {'d': pp.stroke, 'fill': 'none', 'stroke': o['stroke'], 'stroke-width': jsOr(o['sw'], 1)}, g);
  K.T(g, xL + pad, K.base(yBase - th / 2, size) + .3, label, {'size': size, 'fill': o['ink'], 'fam': fam});
  if (o['count'] != null) K.T(g, xL + pad + K.TW(label, size, 700, fam) + 4, K.base(yBase - th / 2, size) + .3, jsStr(o['count']), {'size': size, 'fill': jsOr(o['countInk'], '#888')});
  return xR;
}

num tabSquare(MockEl g, num xL, num yBase, String label, [Map<String, dynamic> o = const {}]) {
  final num size = jsOr(o['size'], 9), th = jsOr(o['th'], 13), pad = (o['pad'] ?? 13) - 4;
  final String fam = jsOr(o['fam'], 'sans');
  final w = K.TW(label, size, 700, fam) + pad * 2, xR = xL + w, yT = yBase - th;
  const n = jsNum;
  final d = 'M${n(xL)},${n(yBase)} V${n(yT + 1.5)} Q${n(xL)},${n(yT)} ${n(xL + 1.5)},${n(yT)} H${n(xR - 1.5)} Q${n(xR)},${n(yT)} ${n(xR)},${n(yT + 1.5)} V${n(yBase)}';
  E('path', {'d': '$d V${n(yBase + 1.5)} H${n(xL)} Z', 'fill': o['fill']}, g);
  E('path', {'d': d, 'fill': 'none', 'stroke': o['stroke']}, g);
  K.T(g, xL + pad, K.base(yBase - th / 2, size) + .3, label, {'size': size, 'fill': o['ink'], 'fam': fam});
  return xR;
}

Map<String, dynamic> contGeom(MockLayers p, Map<String, dynamic> c, Map<String, dynamic> S, BaseTheme th) {
  num x0 = p.X(c['a']), x1 = p.X(c['b']);
  var cl = false, cr = false;
  if (c['a'] < S['win']['y0']) {
    x0 = p.CL - 30;
    cl = true;
  }
  if (c['b'] > S['win']['y1']) {
    x1 = p.CR + 30;
    cr = true;
  }
  final stack = c['stack'] as List, par = stack.isEmpty ? null : stack.last;
  if (par != null && par['geo'] != null) {
    if (!jsTruthy(par['geo']['cl'])) x0 = jsMax(x0, par['geo']['x0'] + th.M['inset']!);
    if (!jsTruthy(par['geo']['cr'])) x1 = jsMin(x1, par['geo']['x1'] - th.M['inset']!);
  }
  return {'x0': x0, 'x1': x1, 'yTop': c['yTop'], 'yBottom': c['yBottom'], 'cl': cl, 'cr': cr};
}

Map<String, dynamic>? objGeom(MockLayers p, Map<String, dynamic> o, Map<String, dynamic> row, int k, Map<String, dynamic> S, BaseTheme th) {
  num x0 = p.X(o['a']), x1 = p.X(o['b']);
  var cl = false, cr = false;
  if (o['a'] < S['win']['y0']) {
    x0 = p.CL - 30;
    cl = true;
  }
  if (o['b'] > S['win']['y1']) {
    x1 = p.CR + 30;
    cr = true;
  }
  final stack = row['stack'] as List, c = stack.isEmpty ? null : stack.last;
  if (c != null && c['geo'] != null) {
    if (!jsTruthy(o['outL']) && !jsTruthy(c['geo']['cl'])) x0 = jsMax(x0, c['geo']['x0'] + th.M['inset']!);
    if (!jsTruthy(o['outR']) && !jsTruthy(c['geo']['cr'])) x1 = jsMin(x1, c['geo']['x1'] - th.M['inset']!);
    if (jsTruthy(c['geo']['cl']) && o['a'] <= c['a']) {
      x0 = p.CL - 30;
      cl = true;
    }
    if (jsTruthy(c['geo']['cr']) && o['b'] >= c['b']) {
      x1 = p.CR + 30;
      cr = true;
    }
  }
  final items = row['items'] as List;
  final prev = k > 0 ? items[k - 1] : null, next = k + 1 < items.length ? items[k + 1] : null;
  if (prev != null && prev['b'] == o['a']) x0 += 2;
  if (next != null && next['a'] == o['b']) x1 -= 2;
  if (x1 - x0 < 2) return null;
  return {'o': o, 'row': row, 'x0': x0, 'x1': x1, 'y': row['yBand'], 'h': row['h'], 'cl': cl, 'cr': cr};
}

({MockLayers p, Map<String, dynamic> L, BaseTheme th, Map<String, dynamic> S}) renderScreen(BaseTheme th) {
  // 2단계 결정 판: 갈래(방향)마다 장면을 바꿔 끼울 수 있음 — th.scene(S)가 고친 장면을 돌려줌(없으면 같은 장면)
  final S0 = mockScene();
  final S = th.scene(S0) ?? S0;
  final L = layoutScene(S, th.M);
  final svg = E('svg', {'width': W, 'height': H, 'viewBox': '0 0 ${jsNum(W)} ${jsNum(H)}', 'class': 'screen'});
  final p = MockLayers(svg, W: W, H: H, CL: GUT, CR: W - DET, L: GUT + 8, R: W - DET - 12);
  p.X = (y) => (p.L + (y - S['win']['y0']) / (S['win']['y1'] - S['win']['y0']) * (p.R - p.L)).toDouble();
  final cid = K.id('clip'), cp = E('clipPath', {'id': cid}, p.defs);
  E('rect', {'x': GUT, 'y': th.M['clipTop'], 'width': W - DET - GUT, 'height': H - th.M['clipTop']!}, cp);
  for (final layer in [p.grid, p.under, p.cont, p.links, p.band, p.over]) {
    layer.setAttribute('clip-path', 'url(#$cid)');
  }
  th.frame(S, p, L);
  th.dateHeader(S, p, L);
  th.gutter(S, p, L);
  for (final c in jsSorted(L['containers'] as List<Map<String, dynamic>>, (a, b) => a['depth'] - b['depth'])) {
    c['geo'] = contGeom(p, c, S, th);
    th.container(S, p, c, c['geo']);
  }
  for (final C in L['closed']) {
    th.closedCulture(S, p, C);
  }
  final geos = <Map<String, dynamic>>[];
  for (final row in L['rows']) {
    for (final (k, o) in (row['items'] as List).indexed) {
      final g = objGeom(p, o, row, k, S, th);
      if (g != null) {
        o['geo'] = g;
        geos.add(g);
      }
    }
  }
  for (final g in geos) {
    th.object(S, p, g['o'], g);
  }
  for (final row in L['rows']) {
    final items = row['items'] as List;
    for (var k = 1; k < items.length; k++) {
      final a = items[k - 1]['geo'], b = items[k]['geo'];
      if (a != null && b != null && jsTruthy(items[k]['from'])) th.link(S, p, a, b, items[k]['from']);
    }
  }
  th.lanes(S, p, L);
  th.extra(S, p, L);
  th.detail(S, p);
  th.zoom(S, p);
  return (p: p, L: L, th: th, S: S);
}

/// 부품 판 — 같은 고리로 작은 장면(갈래 넷 · 그릇 펼침/접힘 · 섬김 · 끌지 않는 그릇 · 직위 줄 · 이어짐)
MockEl renderParts(BaseTheme th) {
  const PW = 1800, PH = 300;
  final svg = E('svg', {'width': PW, 'height': PH, 'viewBox': '0 0 ${jsNum(PW)} ${jsNum(PH)}', 'class': 'parts'});
  final p = MockLayers(svg, W: PW, H: PH, CL: 0, CR: PW, L: 0, R: PW);
  E('rect', {'x': 0, 'y': 0, 'width': PW, 'height': PH, 'fill': th.tok['paper']}, p.bg);
  final S = <String, dynamic>{
    'win': <String, dynamic>{'y0': 0, 'y1': 1000},
  };
  String k(num a) => th.k(a);
  void cap(num x, num y, String s) => K.T(p.top, x, y, s, {'size': 11, 'wt': 400, 'fill': k(.5)});
  final M = th.M, rowH = M['tabH']! + M['bandH']! + 10;
  final objs = [('국가', '다스림', _P['rose']!, '다스리는 것'), ('실권 정권', '다스림', _P['sage']!, '실권 정권 · 섬김'), ('교단', '영토 밖', _P['mocha']!, '영토가 본업이 아닌 것'), ('집단', '무리', _P['sand']!, '사람의 무리')];
  p.X = (y) => (20 + y * 0.42).toDouble();
  for (final (i, (t, gname, c, label)) in objs.indexed) {
    final y = 30 + i * (rowH + 14);
    final o = <String, dynamic>{'n': t == '집단' ? '반달' : (t == '교단' ? '로마 교단' : (t == '실권 정권' ? '가마쿠라 막부' : '고려')), 'a': 0, 'b': 900, 'c': c, 't': t, 'g': gname};
    if (t == '실권 정권') o['serve'] = <String, dynamic>{'to': '조정', 'c': _P['lav'], 'rel': '명목상', 'a': 300};
    if (t == '국가') {
      o['tags'] = [
        <String, dynamic>{'n': '합스부르크', 'a': 600},
      ];
    }
    th.object(S, p, o, {'o': o, 'x0': p.X(60), 'x1': p.X(900), 'y': y + M['tabH']!, 'h': M['bandH'], 'cl': false, 'cr': false});
    cap(p.X(920), K.base(y + M['tabH']! + M['bandH']! / 2, 11), label);
  }
  const cx = 640;
  p.X = (y) => (cx + y * 0.5).toDouble();
  const cTop = 22;
  final inner = cTop + M['headH']!;
  final rows = [
    <String, dynamic>{'yBand': inner + M['tabH']!},
    <String, dynamic>{'yBand': inner + 2 * M['tabH']! + M['bandH']! + M['gap']!},
  ];
  final cBot = rows[1]['yBand'] + M['bandH']! + M['padB']!;
  final c = <String, dynamic>{
    'n': '전국 시대', 't': '시대', 'depth': 0, 'stack': [], 'labels': [], 'yTop': cTop, 'yBottom': cBot, //
    'rows': [
      {
        'items': [{}, {}],
      },
    ],
  };
  c['geo'] = <String, dynamic>{'x0': p.X(0), 'x1': p.X(600), 'yTop': cTop, 'yBottom': cBot, 'cl': false, 'cr': false};
  th.container(S, p, c, c['geo']);
  for (final (i, (n, a, b2, col)) in [('다케다', 30, 500, _P['rose']!), ('오다', 200, 580, _P['butter']!)].indexed) {
    final o = <String, dynamic>{'n': n, 'a': a, 'b': b2, 'c': col, 't': '군벌', 'g': '다스림'};
    th.object(S, p, o, {'o': o, 'x0': p.X(a), 'x1': p.X(b2), 'y': rows[i]['yBand'], 'h': M['bandH'], 'cl': false, 'cr': false});
  }
  cap(p.X(0), cBot + 18, '그릇 펼침');
  final C = <String, dynamic>{
    'n': '초원', 'count': 9, 'rowY': cBot + 44, 'rowH': M['closedH'], //
    'tabs': [
      <String, dynamic>{'n': '몽골 제국', 'y': 40, 'c': _P['sand']},
      <String, dynamic>{'n': '금장 칸국', 'y': 260, 'c': _P['peach']},
      <String, dynamic>{'n': '티무르', 'y': 470, 'c': _P['mint']},
    ],
  };
  final sv = (p.CL, p.CR);
  p.CL = p.X(0) + 30;
  p.CR = p.X(600) - 30;
  th.closedCulture(S, p, C);
  p.CL = sv.$1;
  p.CR = sv.$2;
  cap(p.X(0), C['rowY'] + C['rowH'] + 18, '그릇 접힘');
  const rx = 1020;
  p.X = (y) => (rx + y * 0.6).toDouble();
  th.lanes(S, p, {
    'lanes': [
      {'laneY': 40, 'lane': {'n': '칼리파위', 'a': 0, 'b': 300}},
      {'laneY': 80, 'lane': {'n': '칼리파위', 'a': 330, 'b': 700, 'status': '명목'}},
      {'laneY': 120, 'lane': {'n': '칼리파위', 'a': 700, 'b': 1000, 'status': '주장'}},
    ],
  });
  cap(rx, 160, '직위 줄 · 옮겨 앉음(이어짐)');
  return svg;
}
