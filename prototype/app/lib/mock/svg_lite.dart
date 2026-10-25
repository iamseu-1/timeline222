import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../scene/fonts.dart';
import '../scene/glyph_atlas.dart';
import '../scene/text_paragraph.dart';

// 목업 요소 나무와 그리기. 목업 틀(render · 갈래)은 SVG 요소를 쌓듯 MockEl을 쌓고, renderMock이 그것을 dart:ui로 그린다.
// 글자는 앱의 글자 그리기(SceneText — 기본 AtlasText)로 그린다 — 목업의 글자가 곧 앱의 글자가 되게.
// 받는 것: svg · g · rect · circle · line · path · text · defs/clipPath(자르기) — 모양 속성(fill · stroke · stroke-width · *-opacity · stroke-dasharray ·
// stroke-dashoffset · stroke-linecap · stroke-linejoin · font-* · text-anchor · letter-spacing · writing-mode) · 물려받기 · opacity(그룹은 층으로) ·
// transform(translate · scale · rotate · matrix).
// 무늬 · 그라데이션 · 가림(mask) · 거르개(filter) · 모르는 요소 · 모르는 색 · 모르는 글꼴은 아직 없다 — 쓰면 UnsupportedError
// (목업이 새 장치를 쓰기 시작했는데 말없이 빼먹고 그리지 않게). 속성도 허락 목록(_Painter._own · _shared)에 있는 것만 받는다.

/// 목업의 요소 하나. 값이 null · false인 속성은 두지 않는다(kit.js의 E처럼 — '없음'과 같다).
class MockEl {
  MockEl(this.tag, [Map<String, Object?>? attrs]) : attrs = {...?attrs};
  final String tag;
  final Map<String, Object?> attrs;
  final children = <MockEl>[];

  /// 글 요소의 글(textContent).
  String text = '';
  MockEl? parent;

  void setAttribute(String k, Object? v) {
    if (v == null || v == false) {
      attrs.remove(k);
    } else {
      attrs[k] = v;
    }
  }
}

/// 요소를 만들어 [parent]의 끝에 단다. 값이 null · false인 속성은 빠진다.
// ignore: non_constant_identifier_names
MockEl E(String tag, Map<String, Object?> at, [MockEl? parent]) {
  final e = MockEl(tag, {
    for (final x in at.entries)
      if (x.value != null && x.value != false) x.key: x.value,
  });
  if (parent != null) {
    parent.children.add(e);
    e.parent = parent;
  }
  return e;
}

/// innerHTML처럼 [g]의 자식을 [fragment]의 요소로 바꾼다. 아이콘 글만 받는다 — `<path …/>` · `<circle …/>` · `<rect …/>` · `<line …/>`.
void setInnerSvg(MockEl g, String fragment) {
  for (final old in g.children) {
    old.parent = null;
  }
  g.children.clear();
  for (final tag in RegExp(r'<[^>]*>').allMatches(fragment)) {
    final m = RegExp(r'^<(path|circle|rect|line)\s([^>]*?)/>$').firstMatch(tag.group(0)!);
    if (m == null) throw UnsupportedError('아이콘 조각은 path · circle · rect · line만 됩니다: ${tag.group(0)}');
    final at = <String, Object?>{};
    final attrs = RegExp(r'([\w-]+)="([^"]*)"');
    for (final a in attrs.allMatches(m.group(2)!)) {
      at[a.group(1)!] = a.group(2)!;
    }
    // 큰따옴표가 아닌 속성 같은 읽지 못한 것이 남으면 실패한다 — 빼먹으면 아이콘이 말없이 비어 그려진다.
    if (m.group(2)!.replaceAll(attrs, '').trim().isNotEmpty) throw UnsupportedError('아이콘 조각의 속성을 읽지 못했습니다: ${tag.group(0)}');
    E(m.group(1)!, at, g);
  }
}

// ── SVG 경로 읽기(M L H V C S Q T A Z, 작은 글자 = 상대) ────────────────────
ui.Path parsePath(String d) {
  final path = ui.Path();
  final tok = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  double cx = 0, cy = 0, sx = 0, sy = 0, lcx = 0, lcy = 0;
  var cmd = 'M', prev = '';
  bool isCmd(String t) => t.length == 1 && 'MmLlHhVvCcSsQqTtAaZz'.contains(t);
  double n() => double.parse(tok[i++]);
  // 호의 깃발은 한 글자(0 · 1)라 뒤의 수와 붙여 쓸 수 있다('a1 1 0 011 1') — 붙은 수에서 첫 글자만 떼어 읽는다.
  bool flag() {
    final t = tok[i];
    if (t.length > 1 && (t[0] == '0' || t[0] == '1')) {
      tok[i] = t.substring(1);
      return t[0] == '1';
    }
    i++;
    return double.parse(t) != 0;
  }

  while (i < tok.length) {
    if (isCmd(tok[i])) {
      cmd = tok[i++];
    } else if (cmd == 'Z' || cmd == 'z') {
      // Z는 수를 받지 않는다 — 그대로 두면 같은 자리를 끝없이 돈다.
      throw FormatException('경로의 Z 뒤에 명령 없이 수가 있습니다', d);
    }
    final rel = cmd == cmd.toLowerCase();
    final c = cmd.toUpperCase();
    final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
    switch (c) {
      case 'M':
        cx = ox + n();
        cy = oy + n();
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
        cmd = rel ? 'l' : 'L'; // M 뒤에 이어진 좌표는 L
      case 'L':
        cx = ox + n();
        cy = oy + n();
        path.lineTo(cx, cy);
      case 'H':
        cx = ox + n();
        path.lineTo(cx, cy);
      case 'V':
        cy = oy + n();
        path.lineTo(cx, cy);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n(), x = ox + n(), y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lcx = x2;
        lcy = y2;
        cx = x;
        cy = y;
      case 'S':
        final smooth = prev == 'C' || prev == 'S';
        final x1 = smooth ? 2 * cx - lcx : cx, y1 = smooth ? 2 * cy - lcy : cy;
        final x2 = ox + n(), y2 = oy + n(), x = ox + n(), y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lcx = x2;
        lcy = y2;
        cx = x;
        cy = y;
      case 'Q':
        final x1 = ox + n(), y1 = oy + n(), x = ox + n(), y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
        lcx = x1;
        lcy = y1;
        cx = x;
        cy = y;
      case 'T':
        final smooth = prev == 'Q' || prev == 'T';
        final x1 = smooth ? 2 * cx - lcx : cx, y1 = smooth ? 2 * cy - lcy : cy;
        final x = ox + n(), y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
        lcx = x1;
        lcy = y1;
        cx = x;
        cy = y;
      case 'A':
        final rx = n().abs(), ry = n().abs(), rot = n(), large = flag(), sweep = flag(), x = ox + n(), y = oy + n();
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y);
        } else {
          path.arcToPoint(ui.Offset(x, y), radius: ui.Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
        }
        cx = x;
        cy = y;
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
    }
    prev = c;
  }
  return path;
}

/// [src]를 점선으로 자른 경로. [dash]가 홀수 개면 두 번 이어 쓴다(SVG처럼). 조각마다(윤곽마다) 처음부터 센다.
ui.Path dashed(ui.Path src, List<double> dash, double offset) {
  final pattern = dash.length.isOdd ? [...dash, ...dash] : dash;
  final total = pattern.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return src;
  final out = ui.Path();
  for (final metric in src.computeMetrics()) {
    var dist = -(offset % total);
    var k = 0;
    while (dist < metric.length) {
      final len = pattern[k % pattern.length];
      if (k.isEven) {
        final a = math.max(0.0, dist), b = math.min(metric.length, dist + len);
        if (b > a) out.addPath(metric.extractPath(a, b), ui.Offset.zero);
      }
      dist += len;
      k++;
    }
  }
  return out;
}

// ── 행렬(2차원 아핀을 열 우선 4×4에) ─────────────────────────────────────────
Float64List _affine(double a, double b, double c, double d, double e, double f) => Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);

final _identity = _affine(1, 0, 0, 1, 0, 0);

/// a × b — b를 먼저 적용한다(부모 × 제 것 · 옮기기 목록의 앞 × 뒤).
Float64List _mul(Float64List a, Float64List b) {
  final r = Float64List(16);
  r[0] = a[0] * b[0] + a[4] * b[1];
  r[1] = a[1] * b[0] + a[5] * b[1];
  r[4] = a[0] * b[4] + a[4] * b[5];
  r[5] = a[1] * b[4] + a[5] * b[5];
  r[12] = a[0] * b[12] + a[4] * b[13] + a[12];
  r[13] = a[1] * b[12] + a[5] * b[13] + a[13];
  r[10] = 1;
  r[15] = 1;
  return r;
}

/// transform 속성: translate · scale · rotate · matrix를 차례로 곱한 행렬. 없으면 null.
Float64List? _transform(Object? v) {
  if (v == null) return null;
  final s = '$v';
  Float64List? m;
  var end = 0;
  for (final f in RegExp(r'([A-Za-z]+)\s*\(([^)]*)\)').allMatches(s)) {
    if (s.substring(end, f.start).replaceAll(',', '').trim().isNotEmpty) throw FormatException('옮기기를 읽지 못했습니다', s);
    end = f.end;
    final a = f.group(2)!.trim().split(RegExp(r'[\s,]+')).where((x) => x.isNotEmpty).map(double.parse).toList();
    final Float64List t;
    switch ((f.group(1), a.length)) {
      case ('translate', 1 || 2):
        t = _affine(1, 0, 0, 1, a[0], a.length > 1 ? a[1] : 0);
      case ('scale', 1 || 2):
        t = _affine(a[0], 0, 0, a.length > 1 ? a[1] : a[0], 0, 0);
      case ('rotate', 1 || 3):
        // rotate(d, px, py) = translate(px, py) rotate(d) translate(-px, -py)
        final r = a[0] * math.pi / 180, cs = math.cos(r), sn = math.sin(r);
        final px = a.length > 1 ? a[1] : 0.0, py = a.length > 1 ? a[2] : 0.0;
        t = _affine(cs, sn, -sn, cs, px - cs * px + sn * py, py - sn * px - cs * py);
      case ('matrix', 6):
        t = _affine(a[0], a[1], a[2], a[3], a[4], a[5]);
      default:
        throw UnsupportedError('모르는 옮기기입니다: ${f.group(0)}');
    }
    m = m == null ? t : _mul(m, t);
  }
  if (s.substring(end).trim().isNotEmpty) throw FormatException('옮기기를 읽지 못했습니다', s);
  return m;
}

// ── 속성 값 ──────────────────────────────────────────────────────────────
double _num(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = '$v'.trim();
  return double.tryParse(s.endsWith('px') ? s.substring(0, s.length - 2) : s) ?? (throw FormatException('수가 아닙니다', s));
}

double _opacity(Object? v) => v == null ? 1 : _num(v).clamp(0.0, 1.0);

/// 색과 불투명도(0~1) → 색. none · transparent는 null(칠하지 않음).
ui.Color? _color(String? v, double alpha) {
  if (v == null) return null;
  final s = v.trim().toLowerCase();
  if (s == 'none' || s == 'transparent') return null;
  if (s.startsWith('url(')) throw UnsupportedError('무늬 · 그라데이션은 아직 없습니다: $v');
  int r, g, b;
  var a = 1.0;
  final rgb = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(s);
  if (s == 'white' || s == 'black') {
    r = g = b = s == 'white' ? 255 : 0;
  } else if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(s)) {
    r = int.parse(s[1] * 2, radix: 16);
    g = int.parse(s[2] * 2, radix: 16);
    b = int.parse(s[3] * 2, radix: 16);
  } else if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(s)) {
    r = int.parse(s.substring(1, 3), radix: 16);
    g = int.parse(s.substring(3, 5), radix: 16);
    b = int.parse(s.substring(5, 7), radix: 16);
  } else if (rgb != null) {
    final p = rgb.group(1)!.trim().split(RegExp(r'[\s,/]+')).map(double.parse).toList();
    if (p.length < 3 || p.length > 4) throw UnsupportedError('모르는 색입니다: $v');
    r = p[0].round().clamp(0, 255);
    g = p[1].round().clamp(0, 255);
    b = p[2].round().clamp(0, 255);
    if (p.length == 4) a = p[3].clamp(0.0, 1.0);
  } else {
    throw UnsupportedError('모르는 색입니다: $v');
  }
  return ui.Color.fromARGB((a * alpha * 255).round().clamp(0, 255), r, g, b);
}

/// 목업이 쓰는 글꼴(loadMockFonts가 싣는 것).
const _sans = 'Pretendard';
const _families = {_sans, 'RIDIBatang', 'ChosunKm'};

/// font-family 목록('"RIDIBatang", "Batang", serif')의 첫 이름. 목업 글꼴이 아니면 실패한다.
String _family(String v) {
  final first = v.split(',').first.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  if (!_families.contains(first)) throw UnsupportedError('목업 글꼴은 ${_families.join(' · ')}만 됩니다: $v');
  return first;
}

/// 굵기는 앱 글꼴 파일이 있는 400 · 600 · 700으로(CSS의 글꼴 고르기처럼: 500까지는 400, 600까지는 600, 그 위는 700).
ui.FontWeight _w(int wt) => wt <= 500 ? ui.FontWeight.w400 : (wt <= 600 ? ui.FontWeight.w600 : ui.FontWeight.w700);

int _weight(Object v) => switch ('$v'.trim()) {
  'normal' => 400,
  'bold' => 700,
  final s => _num(s).round(),
};

/// SVG처럼 음수가 있거나 모두 0이면 실선(null).
List<double>? _dash(Object v) {
  final s = '$v'.trim();
  if (s.isEmpty || s == 'none') return null;
  final d = s.split(RegExp(r'[\s,]+')).map(_num).toList();
  return d.any((x) => x < 0) || d.every((x) => x == 0) ? null : d;
}

// ── 물려받는 모양 ──────────────────────────────────────────────────────────
/// 요소가 부모에게서 물려받는 모양. opacity · clip-path · transform은 물려받지 않는다(요소마다 따로).
class _Style {
  String fill = '#000000', stroke = 'none', cap = 'butt', join = 'miter', family = _sans, anchor = 'start', writing = 'horizontal-tb';
  double strokeWidth = 1, fillOpacity = 1, strokeOpacity = 1, dashOffset = 0, fontSize = 16, letterSpacing = 0;
  List<double>? dash;
  int weight = 400;
  bool italic = false;

  static final root = _Style();

  static const _keys = {
    'fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-opacity', 'stroke-dasharray', 'stroke-dashoffset', 'stroke-linecap', //
    'stroke-linejoin', 'font-size', 'font-weight', 'font-family', 'text-anchor', 'letter-spacing', 'font-style', 'writing-mode',
  };

  /// 부모의 모양을 베끼고 제 속성으로 덮는다. 덮을 것이 없으면 부모의 것을 그대로 쓴다(요소마다 베끼지 않게).
  _Style inherit(Map<String, Object?> at) {
    if (!at.keys.any(_keys.contains)) return this;
    final s = _Style()
      ..fill = fill
      ..stroke = stroke
      ..cap = cap
      ..join = join
      ..family = family
      ..anchor = anchor
      ..writing = writing
      ..strokeWidth = strokeWidth
      ..fillOpacity = fillOpacity
      ..strokeOpacity = strokeOpacity
      ..dashOffset = dashOffset
      ..fontSize = fontSize
      ..letterSpacing = letterSpacing
      ..dash = dash
      ..weight = weight
      ..italic = italic;
    for (final MapEntry(:key, :value) in at.entries) {
      if (value == null) continue;
      switch (key) {
        case 'fill':
          s.fill = '$value';
        case 'stroke':
          s.stroke = '$value';
        case 'stroke-width':
          s.strokeWidth = _num(value);
        case 'fill-opacity':
          s.fillOpacity = _opacity(value);
        case 'stroke-opacity':
          s.strokeOpacity = _opacity(value);
        case 'stroke-dasharray':
          s.dash = _dash(value);
        case 'stroke-dashoffset':
          s.dashOffset = _num(value);
        case 'stroke-linecap':
          s.cap = '$value';
        case 'stroke-linejoin':
          s.join = '$value';
        case 'font-size':
          s.fontSize = _num(value);
        case 'font-weight':
          s.weight = _weight(value);
        case 'font-family':
          s.family = _family('$value');
        case 'text-anchor':
          s.anchor = '$value';
        case 'letter-spacing':
          s.letterSpacing = '$value' == 'normal' ? 0 : _num(value);
        case 'font-style':
          s.italic = '$value' == 'italic' || '$value' == 'oblique';
        case 'writing-mode':
          s.writing = '$value';
      }
    }
    return s;
  }
}

// ── 글꼴 · 글 폭 ───────────────────────────────────────────────────────────
/// 목업의 대체 글꼴 줄 — 크롬(Windows)이 목업의 글꼴 줄 '"Pretendard", "Malgun Gothic", sans-serif'에서 프리텐다드에 없는 글자를 채우는 차례:
/// 맑은 고딕, 그다음 시스템 대체(▸ ▾는 Cambria Math — 크롬 개발 도구로 확인). 앱의 대체 줄(sceneFallbackNow)과 달라 목업을 그리고 재는 동안만 쓴다
/// (다르면 글 폭이 달라 맞춤(fit)과 단추 폭이 크롬과 갈린다).
const mockFallback = ['Malgun Gothic', 'Cambria Math'];

/// [mockFallback]의 글꼴 파일. cambria.ttc는 loadFontFromList가 묶음의 첫 글꼴(Cambria)을 싣는데, Cambria Math와 ▸ ▾의 글자 · 폭(1711/2048)이 같다.
const mockFallbackFiles = [
  ('C:/Windows/Fonts/malgun.ttf', 'Malgun Gothic'),
  ('C:/Windows/Fonts/malgunbd.ttf', 'Malgun Gothic'),
  ('C:/Windows/Fonts/cambria.ttc', 'Cambria Math'),
];

/// 대체 글꼴 파일이 모두 있는가 — 없으면(Windows가 아니면) 대체 글자는 줄무늬 네모로 찍히므로, 크롬과 견주는 검사는 건너뛴다.
bool mockFallbackAvailable() => mockFallbackFiles.every((f) => File(f.$1).existsSync());

final _fontLoads = <String, Future<void>>{};

/// 목업 글꼴을 싣는다: 프리텐다드 400 · 600 · 700 · RIDIBatang · ChosunKm + 있으면 대체 글꼴([mockFallbackFiles]). [fontsDir]는 지금 폴더 기준(검사는 app 폴더).
/// 같은 폴더를 거듭 부르면 첫 부름의 싣기를 함께 기다린다 — 실패하면 잊어 다음 부름이 다시 싣는다(실패 뒤 조용히 통과하지 않게).
Future<void> loadMockFonts(String fontsDir) {
  final known = _fontLoads[fontsDir];
  if (known != null) return known;
  final load = _loadFonts(fontsDir);
  _fontLoads[fontsDir] = load;
  load.catchError((Object _) {
    _fontLoads.remove(fontsDir);
  });
  return load;
}

Future<void> _loadFonts(String fontsDir) async {
  for (final (file, family) in const [
    ('Pretendard-Regular.otf', _sans),
    ('Pretendard-SemiBold.otf', _sans),
    ('Pretendard-Bold.otf', _sans),
    ('RIDIBatang.otf', 'RIDIBatang'),
    ('ChosunKm.ttf', 'ChosunKm'),
  ]) {
    await ui.loadFontFromList(await File('$fontsDir/$file').readAsBytes(), fontFamily: family);
  }
  for (final (path, family) in mockFallbackFiles) {
    final f = File(path);
    if (f.existsSync()) await ui.loadFontFromList(await f.readAsBytes(), fontFamily: family);
  }
}

final _widths = <(String, double, int, String), double>{};

/// 글줄 하나의 폭(px) — 목업이 맞춤(fit)을 고를 때 쓰는 셈(크롬의 measureText처럼 글자 사이 다듬기까지 한 글줄의 폭).
/// [family]는 글꼴 이름 또는 font-family 목록.
double mockTextWidth(String s, double size, int wt, String family) {
  final fam = _family(family);
  return _widths.putIfAbsent((s, size, wt, fam), () {
    final weight = _w(wt);
    final p = (ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: fam, fontSize: size, fontWeight: weight))
          ..pushStyle(ui.TextStyle(fontFamily: fam, fontFamilyFallback: mockFallback, fontSize: size, fontWeight: weight))
          ..addText(s))
        .build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final w = p.maxIntrinsicWidth;
    p.dispose();
    return w;
  });
}

/// 그린 글줄의 자리(대조용): 글 · 시작 x · 바탕선 y · 폭 · 높이(화면 px). 세로쓰기는 글자 기둥 전체(바탕선은 첫 글자의 것).
class MockTextBox {
  const MockTextBox(this.text, this.left, this.baseline, this.width, this.height);
  final String text;
  final double left, baseline, width, height;
}

final _boxes = Expando<List<MockTextBox>>();

/// 마지막으로 그린 [svg]의 글줄 자리들(그린 차례).
List<MockTextBox> mockTextBoxes(MockEl svg) => _boxes[svg] ?? [];

/// (글꼴, 크기, 생김새, 첫 글자) → (글 상자 위에서 바탕선까지, 글 상자 높이). 그림판이 글줄의 첫 글자로 바탕선을 잡으므로 같은 글자로 잰다.
final _lines = <(String, double, int, int), (double, double)>{};

SceneText _freshText() => AtlasText()
  ..maxNewPerFrame = 1 << 20
  ..budgetMicros = 1 << 30;

// ── 그리기 ───────────────────────────────────────────────────────────────
/// 그리기 한 번의 됨됨이: 몇 판 그렸는가 · 글자가 모두 준비된 채 끝났는가.
class MockRenderInfo {
  const MockRenderInfo(this.rounds, this.settled);
  final int rounds;

  /// 거짓이면 기다림([renderMock]의 patience)이 다해 덜 된 글자를 그대로 그렸다 — ClearType 글자는 회색, 아직 못 만든 글자는 빠짐.
  final bool settled;
}

final _infos = Expando<MockRenderInfo>();

/// 마지막으로 그린 [svg]의 됨됨이.
MockRenderInfo? mockRenderInfo(MockEl svg) => _infos[svg];

/// [svg]를 width × height 그림으로 그린다(흰 바탕). 글자는 [text](없으면 새 AtlasText — 회색)로 — 프리텐다드가 아닌 글꼴은
/// 그 글꼴의 AtlasText를 따로 둔다(그림판의 글자 열쇠에 글꼴이 없어 섞이면 다른 글꼴의 글자가 찍힌다).
/// 글자가 다 준비될 때까지 [patience] 안에서 다시 그린다. 그래도 덜 됐으면 그대로 돌려주되 [mockRenderInfo]와 stderr로 알린다.
Future<ui.Image> renderMock(MockEl svg, {int width = 1920, int height = 1080, SceneText? text, Duration patience = const Duration(seconds: 10)}) async {
  final texts = <String, SceneText>{_sans: text ?? _freshText()};
  final clips = <String, MockEl>{};
  void collect(MockEl e) {
    if (e.tag == 'clipPath' && e.attrs['id'] != null) clips['${e.attrs['id']}'] = e;
    e.children.forEach(collect);
  }

  collect(svg);
  final boxes = _boxes[svg] = [];
  final clock = Stopwatch()..start();
  try {
    // 글자 그림판은 처음 본 글자를 장면 끝(flush)에 그림판에 넣는다 — 모든 글이 준비될 때까지(starved가 아닐 때까지) 다시 그린다.
    for (var round = 0;; round++) {
      boxes.clear();
      for (final t in texts.values) {
        t.beginFrame();
      }
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      // 먼저 글을 모두 재어 새 글자를 한데 모은다 — 글자는 그리는 차례를 지키려고 모양 앞 · 자르기와 층의 끝마다 내보내는데,
      // 그때마다 처음 보는 글자가 있으면 그림판을 다시 뜬다.
      final dry = _Painter(c, clips, texts, boxes, dry: true)..paint(svg, _Style.root, _identity);
      c.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xffffffff));
      final p = _Painter(c, clips, texts, boxes, dry: false)
        ..paint(svg, _Style.root, _identity)
        ..flushText();
      final pic = rec.endRecording();
      final ready = !dry.missed && !p.missed && !texts.values.any((t) => t.starved);
      if (ready || clock.elapsed >= patience) {
        _infos[svg] = MockRenderInfo(round + 1, ready);
        if (!ready) stderr.writeln('renderMock: 글자를 다 준비하지 못한 채 그림(${round + 1}판 · ${clock.elapsedMilliseconds}ms) — 덜 된 글자는 회색이거나 빠짐');
        final img = await pic.toImage(width, height);
        pic.dispose();
        return img;
      }
      pic.dispose();
      // 판 사이에 이벤트 루프에 양보한다 — ClearType 굽기(따로 띄운 isolate)의 답과 장 그림 뜨기는 이때만 들어온다.
      // 이 판에 모은 굽기는 지금 청하고(그림판은 장면의 앞 beginFrame에서 청한다) 답이 올 때까지는 다시 그리지 않고 기다린다.
      final baking = [for (final t in texts.values) if (t is AtlasText && t.lcdPending > 0) t..beginFrame()];
      await Future<void>.delayed(const Duration(milliseconds: 1));
      while (baking.any((t) => t.lcdPending > 0) && clock.elapsed < patience) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
  } finally {
    for (final t in texts.values) {
      if (!identical(t, text)) t.dispose();
    }
  }
}

class _Painter {
  _Painter(this.c, this.clips, this.texts, this.boxes, {required this.dry});
  final ui.Canvas c;
  final Map<String, MockEl> clips;
  final Map<String, SceneText> texts;
  final List<MockTextBox> boxes;

  /// 재기만 한다: 글의 폭을 재어 새 글자를 모으고, 그리지는 않는다.
  final bool dry;

  /// 준비가 덜 돼 이번 판에 건너뛴 글이 있다.
  bool missed = false;

  /// 그림판에 모아 두고 아직 내보내지 않은 글자가 있다.
  bool _inked = false;

  /// 모아 둔 글자를 내보낸다. 글자는 그림판에 모였다가 한꺼번에 찍히므로, 뒤에 그리는 모양 앞 · 자르기와 층을 닫기 전에 내보내야
  /// SVG의 그리는 차례(뒤의 모양이 글자를 덮음)와 자르기 · 옅어짐이 글자에도 먹는다. 판은 늘 옮기기 없는 좌표라 언제 내보내도 자리가 같다.
  void flushText() {
    if (!_inked) return;
    for (final t in texts.values) {
      t.flush(c);
    }
    _inked = false;
  }

  /// 장면 글자(TextLook)는 앱의 글꼴 이름 · 대체 줄(sceneFamilyNow · sceneFallbackNow)로 글자를 만든다 — 부르는 동안만 그 글꼴과
  /// 목업의 대체 줄([mockFallback] — 크롬과 같은 차례)로 바꾼다.
  R _inFamily<R>(String family, R Function(SceneText t) f) {
    final t = texts.putIfAbsent(family, () => _freshText()..beginFrame());
    final was = sceneFamilyNow, wasFallback = sceneFallbackNow;
    sceneFamilyNow = family;
    sceneFallbackNow = mockFallback;
    try {
      return f(t);
    } finally {
      sceneFamilyNow = was;
      sceneFallbackNow = wasFallback;
    }
  }

  /// 받는 속성(허락 목록) — 목업 틀(kit · render · 갈래)이 쓰는 것과 이 파일이 그리는 것(ry · fill-opacity · stroke-dashoffset)뿐.
  /// 그 밖(dx · dy · xml:space · fill-rule · mask · filter · style …)은 실패한다 — 말없이 빼먹고 그리지 않게. 새 속성은 그리게 만든 뒤 더한다.
  /// [_shared]는 그리는 요소 모두가(모양 · 글꼴 · 옮기기 · 자르기), [_own]은 요소마다 제 자리 속성.
  static const _shared = {
    'transform', 'opacity', 'clip-path', 'fill', 'fill-opacity', 'stroke', 'stroke-width', 'stroke-opacity', 'stroke-dasharray', 'stroke-dashoffset', //
    'stroke-linecap', 'stroke-linejoin', 'font-size', 'font-weight', 'font-family', 'font-style', 'text-anchor', 'letter-spacing', 'writing-mode',
  };
  static const _own = <String, Set<String>>{
    'svg': {'width', 'height', 'viewBox'},
    'g': {},
    'rect': {'x', 'y', 'width', 'height', 'rx', 'ry'},
    'circle': {'cx', 'cy', 'r'},
    'line': {'x1', 'y1', 'x2', 'y2'},
    'path': {'d'},
    'text': {'x', 'y'},
  };

  /// 자르기 자식이 받는 것 — 모양 · 옮기기만 자르기에 닿고 칠 · 선 · 글꼴은 닿지 않는다(받아도 무해). 자식의 clip-path는 그리지 못한다.
  static final _clipShared = _shared.difference(const {'clip-path'});

  /// 그림에 닿지 않는 이름표 — id · class · xmlns · data-*.
  static bool _label(String k) => k == 'id' || k == 'class' || k == 'xmlns' || k.startsWith('data-');

  /// [e]의 속성이 모두 이름표이거나 [shared] · [own]에 있는가 — 아니면 실패.
  static void _check(MockEl e, Set<String> shared, Set<String> own) {
    for (final k in e.attrs.keys) {
      if (!_label(k) && !shared.contains(k) && !own.contains(k)) throw UnsupportedError('<${e.tag}>의 $k는 그리지 못합니다(허락 목록 밖): $k="${e.attrs[k]}"');
    }
  }

  /// 반투명 층 안에서는 ClearType을 끈다 — ClearType 섞기(곱하기 · 더하기)는 바탕이 불투명해야 맞다(층 안에 흰 네모가 남음 · 설계 3-2).
  /// 바깥 층을 열 때 끄고 닫을 때 되돌린다.
  Map<AtlasText, bool>? _lcdWas;
  int _layers = 0;

  void _openLayer(double op) {
    flushText();
    c.saveLayer(null, _alphaPaint(op));
    if (_layers++ == 0) {
      _lcdWas = {for (final t in texts.values) if (t is AtlasText) t: t.lcdAllowed};
      for (final t in _lcdWas!.keys) {
        t.lcdAllowed = false;
      }
    }
  }

  void _closeLayer() {
    flushText();
    c.restore();
    if (--_layers == 0) {
      _lcdWas!.forEach((t, was) => t.lcdAllowed = was);
      _lcdWas = null;
    }
  }

  void paint(MockEl e, _Style parent, Float64List pm) {
    if (const {'defs', 'clipPath', 'title', 'desc'}.contains(e.tag)) return;
    _check(e, _shared, _own[e.tag] ?? (throw UnsupportedError('모르는 요소입니다: <${e.tag}>')));
    final st = parent.inherit(e.attrs);
    final own = _transform(e.attrs['transform']);
    final m = own == null ? pm : _mul(pm, own);
    final op = _opacity(e.attrs['opacity']);
    if (op <= 0) return;
    final clipAt = e.attrs['clip-path'];
    final clip = !dry && clipAt != null && '$clipAt'.trim() != 'none';
    if (clip) {
      final path = _clipOf(clipAt, m);
      flushText();
      c.save();
      c.clipPath(path);
    }
    switch (e.tag) {
      case 'svg' || 'g':
        if (e.tag == 'svg') _checkViewBox(e);
        final layer = !dry && op < 1;
        if (layer) _openLayer(op);
        try {
          for (final k in e.children) {
            paint(k, st, m);
          }
        } finally {
          if (layer) _closeLayer();
        }
      case 'rect' || 'circle' || 'line' || 'path':
        _shape(e, st, m, op);
      case 'text':
        _text(e, st, m, op);
      default:
        throw UnsupportedError('모르는 요소입니다: <${e.tag}>');
    }
    if (clip) {
      flushText();
      c.restore();
    }
  }

  /// 자르기: clipPath의 자식들을 합친 경로를, 자르기를 단 요소의 좌표계(그 요소의 옮기기까지)로 옮긴다.
  ui.Path _clipOf(Object v, Float64List m) {
    final id = RegExp(r'^url\(\s*#([^)\s]+)\s*\)$').firstMatch('$v'.trim())?.group(1);
    if (id == null) throw UnsupportedError('자르기는 url(#…)만 됩니다: $v');
    final cp = clips[id] ?? (throw StateError('자르기 #$id가 없습니다'));
    // 자르기 단위는 userSpaceOnUse만(objectBoundingBox면 0~1을 모양의 상자에 늘여야 한다) · 자식은 모양만 — 그 clip-path · clip-rule은 그리지 못한다.
    _check(cp, const {'transform'}, const {'clipPathUnits'});
    final units = cp.attrs['clipPathUnits'];
    if (units != null && '$units'.trim() != 'userSpaceOnUse') throw UnsupportedError('자르기 단위는 userSpaceOnUse만 됩니다: #$id clipPathUnits="$units"');
    final own = _transform(cp.attrs['transform']);
    final cm = own == null ? m : _mul(m, own);
    ui.Path? out;
    for (final k in cp.children) {
      if (!const {'rect', 'circle', 'line', 'path'}.contains(k.tag)) throw UnsupportedError('자르기 안의 <${k.tag}>는 아직 없습니다');
      _check(k, _clipShared, _own[k.tag]!);
      final p = _pathOf(k);
      if (p == null) continue;
      final kt = _transform(k.attrs['transform']);
      final placed = p.transform(kt == null ? cm : _mul(cm, kt));
      out = out == null ? placed : ui.Path.combine(ui.PathOperation.union, out, placed);
    }
    return out ?? ui.Path();
  }

  void _shape(MockEl e, _Style st, Float64List m, double op) {
    if (dry) return;
    final path = _pathOf(e);
    if (path == null) return;
    final hasFill = e.tag != 'line' && _color(st.fill, 1) != null;
    final hasStroke = st.strokeWidth > 0 && _color(st.stroke, 1) != null;
    if (!hasFill && !hasStroke) return;
    // 칠과 선이 함께 있으면 둘을 한 장에 겹친 뒤 옅게 한다(SVG의 opacity — 칠 위의 선이 두 번 옅어지지 않게). 하나뿐이면 색에 곱한다.
    final layer = op < 1 && hasFill && hasStroke;
    final k = layer ? 1.0 : op;
    flushText();
    c.save();
    c.transform(m);
    if (layer) c.saveLayer(null, _alphaPaint(op));
    if (hasFill) c.drawPath(path, ui.Paint()..color = _color(st.fill, st.fillOpacity * k)!);
    if (hasStroke) {
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..color = _color(st.stroke, st.strokeOpacity * k)!
        ..strokeWidth = st.strokeWidth
        ..strokeCap = switch (st.cap) {
          'round' => ui.StrokeCap.round,
          'square' => ui.StrokeCap.square,
          _ => ui.StrokeCap.butt,
        }
        ..strokeJoin = switch (st.join) {
          'round' => ui.StrokeJoin.round,
          'bevel' => ui.StrokeJoin.bevel,
          _ => ui.StrokeJoin.miter,
        }
        ..strokeMiterLimit = 4;
      final dash = st.dash;
      c.drawPath(dash == null ? path : dashed(path, dash, st.dashOffset), paint);
    }
    if (layer) c.restore();
    c.restore();
  }

  void _text(MockEl e, _Style st, Float64List m, double op) {
    if (e.children.isNotEmpty) throw UnsupportedError('글 안의 요소는 아직 없습니다: <${e.children.first.tag}>');
    // SVG처럼 이어진 빈칸(줄바꿈 · 탭 포함)은 하나로, 앞뒤는 다듬는다.
    final s = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return;
    if (st.strokeWidth > 0 && _color(st.stroke, 1) != null) throw UnsupportedError('글자 테두리(stroke)는 아직 없습니다: $s');
    final color = _color(st.fill, st.fillOpacity);
    if (color == null) return;
    // 그림판은 글자를 화면 화소에 맞춰 찍으므로 늘리거나 돌릴 수 없다.
    if (m[0] != 1 || m[1] != 0 || m[4] != 0 || m[5] != 1) throw UnsupportedError('글자는 평행 이동만 됩니다: $s');
    final x = _num(e.attrs['x']) + m[12], y = _num(e.attrs['y']) + m[13];
    final look = TextLook(st.fontSize, _w(st.weight), color.toARGB32(), italic: st.italic, spacing: st.letterSpacing);
    final vertical = st.writing.startsWith('vertical') || st.writing.startsWith('tb');
    _inFamily(st.family, (t) => vertical ? _column(t, s, look, st, x, y, op) : _line(t, s, look, st, x, y, op));
  }

  /// 가로 글줄: 시작 x는 맞춤(start · middle · end)으로, 바탕선 y에서 바탕선 깊이를 빼 글 상자 윗변을 넘긴다
  /// (그림판이 바탕선을 다시 화면 화소 줄에 맞춘다).
  void _line(SceneText t, String s, TextLook look, _Style st, double x, double y, double op) {
    final w = t.widthOf(s, look);
    if (w == null) {
      missed = true;
      return;
    }
    if (dry) return;
    final left = switch (st.anchor) {
      'middle' => x - w / 2,
      'end' => x - w,
      _ => x,
    };
    final (base, height) = _lineOf(s, look, st.family);
    if (!t.paint(c, s, look, left, y - base, alpha: op)) {
      missed = true;
      return;
    }
    _inked = true;
    boxes.add(MockTextBox(s, left, y, w, height));
  }

  /// 세로쓰기(vertical-rl): 한 자씩 위에서 아래로, 글자마다 x에 가운데 맞춤. 한 자의 칸 = 크기 × 1.2(+ 글자 사이).
  void _column(SceneText t, String s, TextLook look, _Style st, double x, double y, double op) {
    final chars = [for (final r in s.runes) String.fromCharCode(r)];
    final widths = [for (final ch in chars) t.widthOf(ch, look)];
    if (widths.contains(null)) {
      missed = true;
      return;
    }
    if (dry) return;
    final step = st.fontSize * 1.2 + st.letterSpacing, total = chars.length * step;
    final top0 = switch (st.anchor) {
      'middle' => y - total / 2,
      'end' => y - total,
      _ => y,
    };
    var widest = 0.0;
    for (var i = 0; i < chars.length; i++) {
      final w = widths[i]!;
      widest = math.max(widest, w);
      if (t.paint(c, chars[i], look, x - w / 2, top0 + i * step, alpha: op)) {
        _inked = true;
      } else {
        missed = true;
      }
    }
    boxes.add(MockTextBox(s, x - widest / 2, top0 + _lineOf(s, look, st.family).$1, widest, total));
  }

  /// 글 상자 위에서 바탕선까지와 글 상자 높이 — 그림판의 글자와 같은 짜임(TextLook의 글줄 · 첫 글자)으로 한 번 잰다.
  /// 부르는 쪽이 이미 그 글꼴로 바꿔 둔 때만 부른다.
  (double, double) _lineOf(String s, TextLook look, String family) {
    final ink = s.runes.firstWhere((r) => r != 0x20, orElse: () => 0x20);
    return _lines.putIfAbsent((family, look.size, look.shapeKey, ink), () {
      final p = (ui.ParagraphBuilder(look.paragraphStyle(1))
            ..pushStyle(TextLook(look.size, look.weight, 0xffffffff, italic: look.italic, wght: look.wght).textStyle(0xffffffff, 1))
            ..addText(String.fromCharCode(ink)))
          .build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      final r = (p.alphabeticBaseline, p.height);
      p.dispose();
      return r;
    });
  }
}

ui.Paint _alphaPaint(double op) => ui.Paint()..color = ui.Color.fromARGB((op * 255).round(), 0, 0, 0);

/// 모양 요소의 경로(제 좌표계). 넓이 · 반지름이 0 이하면 SVG처럼 그리지 않는다(null).
ui.Path? _pathOf(MockEl e) {
  final a = e.attrs;
  switch (e.tag) {
    case 'rect':
      final r = ui.Rect.fromLTWH(_num(a['x']), _num(a['y']), _num(a['width']), _num(a['height']));
      if (r.width <= 0 || r.height <= 0) return null;
      // rx · ry는 하나만 있으면 둘 다 그 값, 반을 넘지 않는다. 0이면 모난 네모(둥근 네모로 만들면 점선의 시작점이 달라진다).
      final rx = math.min(_num(a['rx'] ?? a['ry']), r.width / 2), ry = math.min(_num(a['ry'] ?? a['rx']), r.height / 2);
      return rx <= 0 || ry <= 0 ? (ui.Path()..addRect(r)) : (ui.Path()..addRRect(ui.RRect.fromRectXY(r, rx, ry)));
    case 'circle':
      final r = _num(a['r']);
      return r <= 0 ? null : (ui.Path()..addOval(ui.Rect.fromCircle(center: ui.Offset(_num(a['cx']), _num(a['cy'])), radius: r)));
    case 'line':
      return ui.Path()
        ..moveTo(_num(a['x1']), _num(a['y1']))
        ..lineTo(_num(a['x2']), _num(a['y2']));
    case 'path':
      final d = a['d'];
      return d == null ? null : parsePath('$d');
  }
  return null;
}

/// 보는 칸(viewBox)은 그림의 크기와 같은 것만 받는다(목업 틀은 늘 '0 0 너비 높이') — 다르면 늘이기를 빼먹고 그리게 된다.
void _checkViewBox(MockEl e) {
  final vb = e.attrs['viewBox'];
  if (vb == null) return;
  final v = '$vb'.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList();
  final w = e.attrs['width'], h = e.attrs['height'];
  if (v.length != 4 || v[0] != 0 || v[1] != 0 || w == null || h == null || v[2] != _num(w) || v[3] != _num(h)) {
    throw UnsupportedError('보는 칸(viewBox)은 0 0 너비 높이만 됩니다: $vb');
  }
}
