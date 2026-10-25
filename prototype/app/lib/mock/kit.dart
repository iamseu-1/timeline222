// JS 이름(P · INK · FONT · ICON · TW · T, 셈 안의 L · A · B)을 그대로 둔다 — 목업을 줄 그대로 옮겨 견주기 쉽게.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'js.dart';
import 'svg_lite.dart';

// 목업 · 제품이 함께 쓰는 그리기 부품 — .claude/research/stage2/mock/kit.js(sha256 dd83a24917a8)를 같은 이름 · 같은 인자 · 같은 반올림으로 옮김.
// 원본의 저장소 사본: test/mock/source/kit.js — 연구 폴더의 원본이 바뀌어도 옮긴 판의 기준은 이 사본이다.
// 대조(test/mock/kit_test.dart)는 같은 지문의 사본에서 노드로 뽑은 정답지(test/mock/fixtures/kit.json)와 한다.
// 색은 '#rrggbb' 글, 경로는 SVG 경로 글(제품은 parsePath로 ui.Path를 얻는다). 글자 폭은 크롬의 measureText 대신 앱이 글자를 그리는 글꼴 파일로 잰다.
// window.K의 E는 svg_lite.dart의 E를 그대로 쓴다.

/// 간지 탭의 세 경로: 칠할 것(바탕선 아래 1.5까지 내려 닫음) · 어깨선을 바로 닫은 것 · 어깨선만(열림).
class TabPaths {
  const TabPaths(this.fill, this.open, this.stroke);
  final String fill, open, stroke;
}

class K {
  K._();

  static const P = {
    'rose': '#d4a39b', 'peach': '#dab195', 'butter': '#d7c18e', 'sage': '#b6c398', 'mint': '#9dbea8', 'sky': '#a0bcc5',
    'peri': '#abb3c9', 'lav': '#bbacc8', 'pink': '#d1a9b9', 'sand': '#c8b193', 'slate': '#a4b1b7', 'mocha': '#bba395',
  };
  static const INK = '#1b1a19';

  /// CSS 글꼴 줄 그대로 — 그릴 때(svg_lite)는 첫 이름을 쓴다.
  static const FONT = {
    'sans': '"Pretendard", "Malgun Gothic", sans-serif',
    'serif': '"RIDIBatang", "Batang", serif',
    'heavy': '"ChosunKm", "Batang", serif',
  };

  static List<int> hx(String h) => [1, 3, 5].map((i) => int.parse(h.substring(i, i + 2), radix: 16)).toList();
  static String toHex(List<num> a) => '#${a.map((v) => jsRound(math.max(0, math.min(255, v))).toInt().toRadixString(16).padLeft(2, '0')).join()}';

  static String mix(String c, num p, [String base = '#ffffff']) {
    final a = hx(c), b = hx(base);
    return toHex([for (var i = 0; i < 3; i++) a[i] * p + b[i] * (1 - p)]);
  }

  // pow(**)는 V8과 비트까지 같지 않으나(Dart는 x³을 x·x·x로, 나머지는 C 라이브러리 pow로 셈) #rrggbb로 반올림한 뒤에는 같다(무작위 2만 색 대조).
  static double _lin(num v) {
    final x = v / 255;
    return x <= .04045 ? x / 12.92 : math.pow((x + .055) / 1.055, 2.4).toDouble();
  }

  static double _delin(double v) => 255 * (v <= .0031308 ? 12.92 * v : 1.055 * math.pow(math.max(v, 0), 1 / 2.4) - .055);

  static List<double> oklab(String c) {
    final rgb = hx(c).map(_lin).toList();
    final r = rgb[0], g = rgb[1], b = rgb[2];
    final l = jsCbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b),
        m = jsCbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b),
        s = jsCbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    return [.2104542553 * l + .793617785 * m - .0040720468 * s, 1.9779984951 * l - 2.428592205 * m + .4505937099 * s, .0259040371 * l + .7827717662 * m - .808675766 * s];
  }

  static String unOklab(List<num> lab) {
    final L = lab[0], A = lab[1], B = lab[2];
    final l = math.pow(L + .3963377774 * A + .2158037573 * B, 3).toDouble(),
        m = math.pow(L - .1055613458 * A - .0638541728 * B, 3).toDouble(),
        s = math.pow(L - .0894841775 * A - 1.291485548 * B, 3).toDouble();
    return toHex([4.0767416621 * l - 3.3077115913 * m + .2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - .3413193965 * s, -.0041960863 * l - .7034186147 * m + 1.707614701 * s].map(_delin).toList());
  }

  static String mixOk(String c, num p, String base) {
    final a = oklab(c), b = oklab(base);
    return unOklab([for (var i = 0; i < 3; i++) a[i] * p + b[i] * (1 - p)]);
  }

  /// 먹의 불투명도를 종이 위의 불투명 색으로.
  static String ink(num a, [String paper = '#ffffff', String inkc = '#000000']) => mix(inkc, a, paper);
  static String edge(String c) => mixOk(c, .84, INK);
  static String edgeSoft(String c) => mixOk(c, .92, INK);
  static String fillC(String c, [num p = .24, String paper = '#ffffff']) => mix(c, p, paper);
  static String tabInk(String c) => mix(c, .22, INK);
  static String nameInk(String c) => mix(c, .45, INK);

  /// 글줄 가운데 → 바탕선.
  static double base(num center, num size) => center + size * .36;
  static double px(num v) => jsRound(v) + .5;

  /// 둥근 네모 — 왼쪽 둥근 [r] · 오른쪽 둥근 [r2](없으면 r), 또는 [r]에 모서리 따로 [tl, tr, br, bl].
  static String rr(num x, num y, num w, num h, [Object r = 10, num? r2]) {
    num tl, tr, br, bl;
    if (r is List) {
      tl = r[0] as num;
      tr = r[1] as num;
      br = r[2] as num;
      bl = r[3] as num;
    } else {
      tl = bl = r as num;
      tr = br = r2 ?? r;
    }
    num c(num v) => math.max(0, math.min(v, math.min(h / 2, w / 2)));
    tl = c(tl);
    tr = c(tr);
    br = c(br);
    bl = c(bl);
    const n = jsNum;
    String a(num q, num x2, num y2) => jsTruthy(q) ? 'A${n(q)},${n(q)} 0 0 1 ${n(x2)},${n(y2)}' : '';
    return 'M${n(x + tl)},${n(y)} H${n(x + w - tr)} ${a(tr, x + w, y + tr)} V${n(y + h - br)} ${a(br, x + w - br, y + h)} H${n(x + bl)} ${a(bl, x, y + h - bl)} V${n(y + tl)} ${a(tl, x + tl, y)} Z';
  }

  /// 간지 탭 — 종이 윗변이 어깨로 솟은 모양.
  static TabPaths tabPath(num xL, num xR, num yBase, num th, [num s = 7]) {
    const n = jsNum;
    final yT = yBase - th;
    final stroke = 'M${n(xL)},${n(yBase)} C${n(xL + s * .55)},${n(yBase)} ${n(xL + s * .45)},${n(yT)} ${n(xL + s)},${n(yT)} L${n(xR - s)},${n(yT)} C${n(xR - s * .45)},${n(yT)} ${n(xR - s * .55)},${n(yBase)} ${n(xR)},${n(yBase)}';
    return TabPaths('$stroke L${n(xR)},${n(yBase + 1.5)} L${n(xL)},${n(yBase + 1.5)} Z', '$stroke Z', stroke);
  }

  /// 꼭짓점마다 둥글린 닫힌 다각형(모서리는 이차 곡선, 반지름은 양옆 변의 반을 넘지 않음).
  static String roundPoly(List<List<num>> pts, num r) {
    final n = pts.length;
    var d = '';
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n];
      final l1 = jsHypot(p1[0] - p0[0], p1[1] - p0[1]), l2 = jsHypot(p2[0] - p1[0], p2[1] - p1[1]);
      final q = math.min(r, math.min(l1 / 2, l2 / 2));
      final a = [p1[0] + (p0[0] - p1[0]) / l1 * q, p1[1] + (p0[1] - p1[1]) / l1 * q];
      final b = [p1[0] + (p2[0] - p1[0]) / l2 * q, p1[1] + (p2[1] - p1[1]) / l2 * q];
      d += '${i != 0 ? ' L' : 'M'}${jsNum(a[0])},${jsNum(a[1])} Q${jsNum(p1[0])},${jsNum(p1[1])} ${jsNum(b[0])},${jsNum(b[1])}';
    }
    return '$d Z';
  }

  static int _uid = 0;
  static String id([String? p]) => '${jsOr(p, 'k')}${++_uid}';

  /// 선 아이콘 — Lucide 규격(24칸 · 굵기 1.5). 글은 kit.js의 ICON을 글자 하나 바꾸지 않고 옮겼다.
  static const ICON = <String, String>{
    'search': '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    'filter': '<path d="M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4"/>',
    'eye': '<path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0"/><circle cx="12" cy="12" r="3"/>',
    'layers': '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    'more': '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    'x': '<path d="M18 6 6 18M6 6l12 12"/>',
    'plus': '<path d="M5 12h14M12 5v14"/>',
    'minus': '<path d="M5 12h14"/>',
    'expand': '<path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>',
    'down': '<path d="m6 9 6 6 6-6"/>',
    'right': '<path d="m9 18 6-6-6-6"/>',
    'folder': '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    'book': '<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/>',
    'doc': '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>',
  };

  static MockEl icon(MockEl g, String name, num x, num y, [num size = 16, String color = INK, num sw = 1.5]) {
    final s = size / 24;
    final gg = E('g', {'transform': 'translate(${jsNum(x)},${jsNum(y)}) scale(${jsNum(s)})', 'fill': 'none', 'stroke': color, 'stroke-width': sw / s, 'stroke-linecap': 'round', 'stroke-linejoin': 'round'}, g);
    setInnerSvg(gg, ICON[name] ?? '');
    return gg;
  }

  /// 글 폭 — 굵은 명조 · 명조는 400. 크롬의 measureText 대신 앱의 글자 체계로 잰다(mockTextWidth).
  /// [fam]이 null이면 sans — JS에서 undefined를 넘기면 기본값이 서는 것과 같게(render.js의 wrap · fit이 fam 없이 부른다).
  static double TW(Object s, [num size = 9, num wt = 700, String? fam]) {
    final f = fam ?? 'sans';
    if (f == 'heavy' || f == 'serif') wt = 400;
    return mockTextWidth(jsStr(s), size.toDouble(), wt.round(), FONT[f] ?? f);
  }

  /// 글 요소. [o]: fam · wt · size · fill · anchor · ls · op · italic · vertical.
  static MockEl T(MockEl g, num x, num y, Object s, [Map<String, Object?> o = const {}]) {
    final fam = o['fam'];
    final wt = (fam == 'heavy' || fam == 'serif') ? 400 : jsOr(o['wt'], 700);
    return E('text', {
      'x': x,
      'y': y,
      'font-size': jsOr(o['size'], 9),
      'font-weight': wt,
      'fill': jsOr(o['fill'], INK),
      'text-anchor': jsOr(o['anchor'], 'start'),
      'letter-spacing': o['ls'],
      'opacity': o['op'],
      'font-style': jsTruthy(o['italic']) ? 'italic' : null,
      'writing-mode': jsTruthy(o['vertical']) ? 'vertical-rl' : null,
      // kit.js는 style.fontFamily로 단다 — 여기서는 같은 뜻의 모양 속성으로.
      'font-family': FONT[jsOr(fam, 'sans')] ?? fam,
    }, g)
      ..text = jsStr(s);
  }

  /// 글을 폭에 맞춰 줄임(이름 → 첫 글자 → 없음). kit.js처럼 다섯째 인자에 기본값이 없다(없으면 TW가 sans로).
  static String fit(String s, num room, num size, [num wt = 700, String? fam]) {
    if (TW(s, size, wt, fam) <= room) return s;
    if (s.isNotEmpty && TW(s[0], size, wt, fam) <= room) return s[0];
    return '';
  }
}
