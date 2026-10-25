import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../scene/fonts.dart';
import '../scene/paint/context.dart';
import '../scene/paint/patterns.dart';
import '../scene/painter.dart';
import '../scene/ruler.dart';
import '../scene/scene.dart';
import '../scene/sprites.dart';
import '../scene/text_paragraph.dart';
import '../scene/tile.dart';

// SVG로 저장(명세 06의 7-5 · 지금 연표의 `toSVG`). 지금 연표는 모든 것을 벡터로 **다시 그리는** 610줄이지만,
// 새 앱은 그리개 하나가 모든 모양을 정하므로 **그리개를 그대로 돌리고 받는 쪽만 SVG로 바꾼다**:
//
//   · [SvgCanvas]  — `ui.Canvas`인 척하며 받은 그리기를 SVG 조각으로 적는다(자리 바꾸기는 펴서 뿌리 좌표로).
//   · [SvgQuads] · [SvgLines] · [SvgPatterns] — 네모 · 가는 선 · 무늬의 묶음. 이들은 `drawVertices`로 나가는데
//     `ui.Vertices`는 **되읽을 수 없는 native 덩어리**라 화폭에서는 꼭짓점을 볼 수 없다. 그래서 묶음 쪽을 이어받아
//     담을 때의 네모를 그대로 적는다(`Quads.add` · `addCorners` · `Patterns.add`는 공개된 길이다).
//   · [SvgText]    — 글자 뒷단. 폭 재기는 화면과 **같은 뒷단**에 맡겨 이름 자리가 PNG와 한 픽셀도 다르지 않게 하고,
//     그리기만 진짜 `<text>`로 적는다. 그래야 SVG의 글을 고르고 찾을 수 있다(지금 연표의 SVG와 같음).
//
// **그리개의 층 차례를 여기 [paintSceneToSvg]에 옮겨 두었다.** 그리개(`scene/painter.dart`)의 묶음 밭
// (`_quads` · `_dividers` · `_patterns`)이 사사로워 밖에서 갈아 끼울 수 없기 때문이다(보고의 '총괄이 이어 줄 것' —
// 그 셋을 만들 때 받게 고치면 이 함수는 `painter.paint(svgCanvas, size)` 한 줄로 줄어든다).
// 차례가 어긋나면 `test/export_svg_test.dart`의 '그리개와 같은 것을 그린다'가 알려 준다.

/// 소수 둘째 자리까지, 꼬리의 0은 떼고 적는다(지금 연표의 `n()`과 같은 몫).
String svgNum(double v) {
  if (!v.isFinite) return '0';
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s == '-0' ? '0' : s;
}

/// `#rrggbb`.
String svgHex(int argb) => '#${(argb & 0xffffff).toRadixString(16).padLeft(6, '0')}';

/// 0~1의 짙기(255면 빈 글 — 속성을 적지 않는다).
String _opacity(String name, int argb) {
  final a = (argb >>> 24) & 0xff;
  return a == 0xff ? '' : ' $name="${svgNum(a / 255)}"';
}

/// SVG 안의 글 · 속성에 그대로 넣을 수 없는 글자를 바꾼다.
String svgEscape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 한 칸의 자리 바꾸기 · 자르기 · 열어 둔 무리의 수.
class _Level {
  _Level(this.a, this.b, this.c, this.d, this.e, this.f, this.clip, this.open);
  final double a, b, c, d, e, f;
  final ui.Rect? clip;
  final int open;
}

/// 그림판 한 장(`drawRawAtlas`가 쓰는 그림) — SVG의 `<defs>`에 `data:` PNG로 한 번만 품는다.
class _Atlas {
  _Atlas(this.id, this.image);
  final String id;
  final ui.Image image;
}

/// 받은 그리기를 SVG로 적는 화폭. 그리개가 부르는 것만 옮기고 나머지는 [noSuchMethod]로 조용히 넘기되,
/// **무엇이 몇 번 넘어갔는지 [skipped]에 센다**(검사에서 0인지 본다).
class SvgCanvas implements ui.Canvas {
  SvgCanvas({required this.width, required this.height});

  /// 그림 한 장의 크기(px).
  final double width, height;

  final _defs = StringBuffer();
  final _body = StringBuffer();

  /// 옮기지 못하고 넘긴 그리기 호출(이름 → 수).
  final skipped = <String, int>{};

  /// 적은 그림 조각의 수(`<path>` · `<rect>` · `<text>` …).
  int elements = 0;

  /// 적은 글줄(`<text>`)의 수.
  int texts = 0;

  void _skip(String what) => skipped[what] = (skipped[what] ?? 0) + 1;

  // 자리 바꾸기(CTM)를 펴 둔다: 뿌리 좌표로 바로 적으므로 `<g transform>`이 겹겹이 쌓이지 않는다.
  double _a = 1, _b = 0, _c = 0, _d = 1, _e = 0, _f = 0;
  ui.Rect? _clip;
  final _levels = <_Level>[];
  int _open = 0;
  int _ids = 0;
  final _clipIds = <String, String>{};
  final _maskIds = <String, String>{};
  final _fadeIds = <String, String>{};
  final _patternIds = <String, String>{};
  final _atlases = <ui.Image, _Atlas>{};

  String get _nextId => 'h${_ids++}';

  double _mx(double x, double y) => _a * x + _c * y + _e;
  double _my(double x, double y) => _b * x + _d * y + _f;

  /// 돌림 · 비틂이 없는가(있으면 네모를 네모로 적을 수 없다).
  bool get _straight => _b == 0 && _c == 0;

  /// 길이 하나를 뿌리 좌표의 길이로(가로 · 세로의 늘임이 같다고 본다 — 그리개는 늘 같게 쓴다).
  double get _zoom => _straight ? (_a.abs() + _d.abs()) / 2 : 1;

  ui.Rect _rectOf(ui.Rect r) {
    final x0 = _mx(r.left, r.top), y0 = _my(r.left, r.top), x1 = _mx(r.right, r.bottom), y1 = _my(r.right, r.bottom);
    return ui.Rect.fromLTRB(math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1));
  }

  // ─────────────────── 칸 쌓기 ───────────────────

  @override
  void save() {
    _levels.add(_Level(_a, _b, _c, _d, _e, _f, _clip, _open));
    _open = 0;
  }

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    save();
    final alpha = ((paint.color.toARGB32() >>> 24) & 0xff) / 255;
    _body.write('<g opacity="${svgNum(alpha)}">');
    _open++;
  }

  @override
  void restore() {
    for (int i = 0; i < _open; i++) {
      _body.write('</g>');
    }
    _open = 0;
    if (_levels.isEmpty) return;
    final s = _levels.removeLast();
    _a = s.a;
    _b = s.b;
    _c = s.c;
    _d = s.d;
    _e = s.e;
    _f = s.f;
    _clip = s.clip;
    _open = s.open;
  }

  @override
  void restoreToCount(int count) {
    while (_levels.length >= count && _levels.isNotEmpty) {
      restore();
    }
  }

  @override
  int getSaveCount() => _levels.length + 1;

  // ─────────────────── 자리 바꾸기 ───────────────────

  void _concat(double a, double b, double c, double d, double e, double f) {
    final na = _a * a + _c * b, nb = _b * a + _d * b;
    final nc = _a * c + _c * d, nd = _b * c + _d * d;
    final ne = _a * e + _c * f + _e, nf = _b * e + _d * f + _f;
    _a = na;
    _b = nb;
    _c = nc;
    _d = nd;
    _e = ne;
    _f = nf;
  }

  @override
  void translate(double dx, double dy) => _concat(1, 0, 0, 1, dx, dy);

  @override
  void scale(double sx, [double? sy]) => _concat(sx, 0, 0, sy ?? sx, 0, 0);

  @override
  void rotate(double radians) => _concat(math.cos(radians), math.sin(radians), -math.sin(radians), math.cos(radians), 0, 0);

  @override
  void skew(double sx, double sy) => _concat(1, sy, sx, 1, 0, 0);

  @override
  void transform(Float64List matrix4) => _concat(matrix4[0], matrix4[1], matrix4[4], matrix4[5], matrix4[12], matrix4[13]);

  @override
  Float64List getTransform() => Float64List.fromList([_a, _b, 0, 0, _c, _d, 0, 0, 0, 0, 1, 0, _e, _f, 0, 1]);

  @override
  ui.Rect getLocalClipBounds() => _clip ?? ui.Rect.fromLTWH(0, 0, width, height);

  @override
  ui.Rect getDestinationClipBounds() => _clip ?? ui.Rect.fromLTWH(0, 0, width, height);

  // ─────────────────── 자르기 ───────────────────

  @override
  void clipRect(ui.Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp != ui.ClipOp.intersect) {
      // 구멍 내기(부드러운 그늘의 `hole`)는 옮기지 않는다 — 내보내는 그림에는 고른 것 · 손 올린 것이 없어 그늘이 없다.
      _skip('clipRect(difference)');
      return;
    }
    if (!_straight) {
      _skip('clipRect(rotated)');
      return;
    }
    final r = _rectOf(rect);
    final next = _clip == null ? r : _clip!.intersect(r);
    if (_clip != null && next == _clip) return; // 이미 더 좁게 잘려 있다
    _clip = next;
    _body.write('<g clip-path="url(#${_clipId(next)})">');
    _open++;
  }

  String _clipId(ui.Rect r) {
    final key = '${svgNum(r.left)},${svgNum(r.top)},${svgNum(r.width)},${svgNum(r.height)}';
    return _clipIds[key] ??= () {
      final id = _nextId;
      _defs.write('<clipPath id="$id"><rect x="${svgNum(r.left)}" y="${svgNum(r.top)}" width="${svgNum(math.max(0, r.width))}" height="${svgNum(math.max(0, r.height))}"/></clipPath>');
      return id;
    }();
  }

  // ─────────────────── 모양 ───────────────────

  /// 붓 하나를 SVG의 칠 · 선 속성으로.
  String _paintAttrs(ui.Paint paint) {
    final argb = paint.color.toARGB32();
    if (paint.style == ui.PaintingStyle.stroke) {
      return 'fill="none" stroke="${svgHex(argb)}"${_opacity('stroke-opacity', argb)} stroke-width="${svgNum(paint.strokeWidth * _zoom)}"';
    }
    return 'fill="${svgHex(argb)}"${_opacity('fill-opacity', argb)}';
  }

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    if (!_straight) {
      _skip('drawRect(rotated)');
      return;
    }
    final r = _rectOf(rect);
    if (r.width <= 0 || r.height <= 0) return;
    _body.write('<rect x="${svgNum(r.left)}" y="${svgNum(r.top)}" width="${svgNum(r.width)}" height="${svgNum(r.height)}" ${_paintAttrs(paint)}/>');
    elements++;
  }

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    if (!_straight) {
      _skip('drawRRect(rotated)');
      return;
    }
    final r = _rectOf(ui.Rect.fromLTRB(rrect.left, rrect.top, rrect.right, rrect.bottom));
    final rx = rrect.tlRadiusX * _zoom, ry = rrect.tlRadiusY * _zoom;
    _body.write('<rect x="${svgNum(r.left)}" y="${svgNum(r.top)}" width="${svgNum(r.width)}" height="${svgNum(r.height)}" rx="${svgNum(rx)}" ry="${svgNum(ry)}" ${_paintAttrs(paint)}/>');
    elements++;
  }

  @override
  void drawCircle(ui.Offset center, double radius, ui.Paint paint) {
    _body.write('<circle cx="${svgNum(_mx(center.dx, center.dy))}" cy="${svgNum(_my(center.dx, center.dy))}" r="${svgNum(radius * _zoom)}" ${_paintAttrs(paint)}/>');
    elements++;
  }

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {
    final r = _rectOf(rect);
    _body.write('<ellipse cx="${svgNum(r.center.dx)}" cy="${svgNum(r.center.dy)}" rx="${svgNum(r.width / 2)}" ry="${svgNum(r.height / 2)}" ${_paintAttrs(paint)}/>');
    elements++;
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    final argb = paint.color.toARGB32();
    _body.write('<line x1="${svgNum(_mx(p1.dx, p1.dy))}" y1="${svgNum(_my(p1.dx, p1.dy))}" x2="${svgNum(_mx(p2.dx, p2.dy))}" y2="${svgNum(_my(p2.dx, p2.dy))}"'
        ' stroke="${svgHex(argb)}"${_opacity('stroke-opacity', argb)} stroke-width="${svgNum(math.max(paint.strokeWidth, 1) * _zoom)}"/>');
    elements++;
  }

  // ─────────────────── 네모 묶음(SvgQuads · SvgLines가 넘겨 준다) ───────────────────

  /// 같은 색이 이어지면 `<path>` 하나로 모으고, 꼭짓점 색이 다른 것은 그 칸만 `linearGradient`로.
  void writeQuads(SvgQuads quads) {
    final n = quads.count;
    int i = 0;
    while (i < n) {
      if (!quads.flat(i)) {
        _gradientQuad(quads, i);
        i++;
        continue;
      }
      final color = quads.colorAt(i);
      final path = StringBuffer();
      int j = i;
      while (j < n && quads.flat(j) && quads.colorAt(j) == color) {
        _appendQuadPath(path, quads.left(j), quads.top(j), quads.right(j), quads.bottom(j));
        j++;
      }
      if (path.isNotEmpty) {
        _body.write('<path d="$path" fill="${svgHex(color)}"${_opacity('fill-opacity', color)}/>');
        elements++;
      }
      i = j;
    }
  }

  void _appendQuadPath(StringBuffer out, double l, double t, double r, double b) {
    if (r <= l || b <= t) return;
    if (_straight) {
      final x0 = _mx(l, t), y0 = _my(l, t), x1 = _mx(r, b), y1 = _my(r, b);
      out.write('M${svgNum(math.min(x0, x1))} ${svgNum(math.min(y0, y1))}H${svgNum(math.max(x0, x1))}V${svgNum(math.max(y0, y1))}H${svgNum(math.min(x0, x1))}Z');
      return;
    }
    out.write('M${svgNum(_mx(l, t))} ${svgNum(_my(l, t))}L${svgNum(_mx(r, t))} ${svgNum(_my(r, t))}'
        'L${svgNum(_mx(r, b))} ${svgNum(_my(r, b))}L${svgNum(_mx(l, b))} ${svgNum(_my(l, b))}Z');
  }

  void _gradientQuad(SvgQuads q, int i) {
    final l = q.left(i), t = q.top(i), r = q.right(i), b = q.bottom(i);
    if (r <= l || b <= t) return;
    final tl = q.cornerAt(i, 0), tr = q.cornerAt(i, 1), bl = q.cornerAt(i, 3);
    // 옆으로 번지는 것(연대 미정의 옅은 끝 — `addFade`)과 아래로 번지는 것(전설의 안개 — `addFadeDown`) 둘뿐이다.
    final down = tl == tr && bl == q.cornerAt(i, 2);
    final from = tl, to = down ? bl : tr;
    final box = _rectOf(ui.Rect.fromLTRB(l, t, r, b));
    final x1 = box.left, y1 = box.top;
    final x2 = down ? box.left : box.right, y2 = down ? box.bottom : box.top;
    final key = '$from-$to-${svgNum(x1)},${svgNum(y1)},${svgNum(x2)},${svgNum(y2)}';
    final id = _fadeIds[key] ??= () {
      final made = _nextId;
      _defs.write('<linearGradient id="$made" gradientUnits="userSpaceOnUse" x1="${svgNum(x1)}" y1="${svgNum(y1)}" x2="${svgNum(x2)}" y2="${svgNum(y2)}">'
          '<stop offset="0" stop-color="${svgHex(from)}" stop-opacity="${svgNum(((from >>> 24) & 0xff) / 255)}"/>'
          '<stop offset="1" stop-color="${svgHex(to)}" stop-opacity="${svgNum(((to >>> 24) & 0xff) / 255)}"/>'
          '</linearGradient>');
      return made;
    }();
    _body.write('<rect x="${svgNum(box.left)}" y="${svgNum(box.top)}" width="${svgNum(box.width)}" height="${svgNum(box.height)}" fill="url(#$id)"/>');
    elements++;
  }

  // ─────────────────── 무늬 묶음(SvgPatterns가 넘겨 준다) ───────────────────

  void writePatterns(SvgPatterns patterns) {
    for (int i = 0; i < patterns.count; i++) {
      final box = _rectOf(ui.Rect.fromLTRB(patterns.left(i), patterns.top(i), patterns.right(i), patterns.bottom(i)));
      if (box.width <= 0 || box.height <= 0) continue;
      final id = _patternId(patterns.specAt(i), patterns.colorAt(i), patterns.phaseXAt(i), patterns.phaseYAt(i), patterns.tileOf(i));
      _body.write('<rect x="${svgNum(box.left)}" y="${svgNum(box.top)}" width="${svgNum(box.width)}" height="${svgNum(box.height)}" fill="url(#$id)"/>');
      elements++;
    }
  }

  String _patternId(PatternSpec spec, int argb, double phaseX, double phaseY, double tile) {
    final px = _mx(phaseX, phaseY), py = _my(phaseX, phaseY), zoom = _zoom;
    final key = '${spec.dots}-${spec.stairs}-${spec.angle}-${spec.line}-${spec.period}-$argb-${svgNum(px)},${svgNum(py)},${svgNum(zoom)},${svgNum(tile)}';
    return _patternIds[key] ??= () {
      final id = _nextId;
      final fill = 'fill="${svgHex(argb)}"${_opacity('fill-opacity', argb)}';
      final body = StringBuffer();
      final a = spec.angle % 180;
      if (spec.stairs) {
        // 화소 계단(정통성 '주장' — 칸 그림 갈래 걸음 3): 한 장 n칸 × n칸에 (i, n − 1 − i)마다 한 칸 — 왼쪽 아래 → 오른쪽 위로 오른다(`Patterns._makeStairs`와 같은 자리).
        final n = spec.period.round().clamp(2, 64), cell = tile / n;
        for (int i = 0; i < n; i++) {
          body.write('<rect x="${svgNum(i * cell)}" y="${svgNum((n - 1 - i) * cell)}" width="${svgNum(cell)}" height="${svgNum(cell)}" $fill/>');
        }
      } else if (spec.dots) {
        body.write('<circle cx="${svgNum(tile / 2)}" cy="${svgNum(tile / 2)}" r="${svgNum(spec.line)}" $fill/>');
      } else if (a == 90) {
        body.write('<rect x="0" y="0" width="${svgNum(spec.line)}" height="${svgNum(tile)}" $fill/>');
      } else if (a == 0) {
        body.write('<rect x="0" y="0" width="${svgNum(tile)}" height="${svgNum(spec.line)}" $fill/>');
      } else {
        // 기운 줄: 한 장을 넘나드는 줄 셋으로 이음매를 맞춘다(무늬 묶음 `Patterns._make`와 같은 자리).
        final rising = a > 90;
        final stroke = 'stroke="${svgHex(argb)}"${_opacity('stroke-opacity', argb)} stroke-width="${svgNum(spec.line)}"';
        for (int k = -1; k <= 1; k++) {
          final o = k * tile;
          if (rising) {
            body.write('<line x1="${svgNum(o - tile)}" y1="${svgNum(tile * 2)}" x2="${svgNum(o + tile * 2)}" y2="${svgNum(-tile)}" $stroke/>');
          } else {
            body.write('<line x1="${svgNum(o - tile)}" y1="${svgNum(-tile)}" x2="${svgNum(o + tile * 2)}" y2="${svgNum(tile * 2)}" $stroke/>');
          }
        }
      }
      _defs.write('<pattern id="$id" patternUnits="userSpaceOnUse" width="${svgNum(tile)}" height="${svgNum(tile)}"'
          ' patternTransform="translate(${svgNum(px)} ${svgNum(py)}) scale(${svgNum(zoom)})">$body</pattern>');
      return id;
    }();
  }

  // ─────────────────── 조각 그림판 ───────────────────

  @override
  void drawRawAtlas(ui.Image atlas, Float32List rstTransforms, Float32List rects, Int32List? colors, ui.BlendMode? blendMode, ui.Rect? cullRect, ui.Paint paint) {
    final sheet = _atlases[atlas] ??= _Atlas(_nextId, atlas);
    final n = rstTransforms.length ~/ 4;
    for (int i = 0; i < n; i++) {
      final scos = rstTransforms[i * 4], ssin = rstTransforms[i * 4 + 1];
      final tx = rstTransforms[i * 4 + 2], ty = rstTransforms[i * 4 + 3];
      if (ssin != 0) {
        _skip('drawRawAtlas(rotated)');
        continue;
      }
      final sl = rects[i * 4], st = rects[i * 4 + 1], sr = rects[i * 4 + 2], sb = rects[i * 4 + 3];
      final w = (sr - sl) * scos, h = (sb - st) * scos;
      if (w <= 0 || h <= 0) continue;
      final box = _rectOf(ui.Rect.fromLTWH(tx, ty, w, h));
      final argb = colors == null || i >= colors.length ? 0xffffffff : colors[i];
      final mask = _maskId(sheet, sl, st, sr, sb);
      _body.write('<rect x="${svgNum(box.left)}" y="${svgNum(box.top)}" width="${svgNum(box.width)}" height="${svgNum(box.height)}"'
          ' fill="${svgHex(argb)}"${_opacity('fill-opacity', argb)} mask="url(#$mask)"/>');
      elements++;
    }
  }

  @override
  void drawAtlas(ui.Image atlas, List<ui.RSTransform> transforms, List<ui.Rect> rects, List<ui.Color>? colors, ui.BlendMode? blendMode, ui.Rect? cullRect, ui.Paint paint) {
    final raw = Float32List(transforms.length * 4), src = Float32List(rects.length * 4);
    for (int i = 0; i < transforms.length; i++) {
      raw[i * 4] = transforms[i].scos;
      raw[i * 4 + 1] = transforms[i].ssin;
      raw[i * 4 + 2] = transforms[i].tx;
      raw[i * 4 + 3] = transforms[i].ty;
    }
    for (int i = 0; i < rects.length; i++) {
      src[i * 4] = rects[i].left;
      src[i * 4 + 1] = rects[i].top;
      src[i * 4 + 2] = rects[i].right;
      src[i * 4 + 3] = rects[i].bottom;
    }
    drawRawAtlas(atlas, raw, src, colors == null ? null : Int32List.fromList([for (final c in colors) c.toARGB32()]), blendMode, cullRect, paint);
  }

  /// 그림판의 한 조각을 제 상자에 맞춰 오려 내는 가림막(조각 종류마다 하나 — 찍는 자리 · 크기와 상관없다).
  String _maskId(_Atlas sheet, double sl, double st, double sr, double sb) {
    final w = sr - sl, h = sb - st;
    final key = '${sheet.id}:${svgNum(sl)},${svgNum(st)},${svgNum(w)},${svgNum(h)}';
    return _maskIds[key] ??= () {
      final id = _nextId;
      _defs.write('<mask id="$id" maskContentUnits="objectBoundingBox" style="color-interpolation:sRGB">'
          '<use href="#${sheet.id}" transform="scale(${svgNum(1 / w)} ${svgNum(1 / h)}) translate(${svgNum(-sl)} ${svgNum(-st)})"/></mask>');
      return id;
    }();
  }

  // ─────────────────── 글자(SvgText가 넘겨 준다) ───────────────────

  /// 글줄 하나를 진짜 `<text>`로. [baseline]은 글의 밑줄(배치 px).
  void writeText(String text, TextLook look, double x, double baseline, double alpha) {
    if (text.isEmpty) return;
    final argb = look.color;
    final a = ((argb >>> 24) & 0xff) / 255 * alpha;
    final weight = (look.wght ?? look.weight.value.toDouble()).round();
    final buffer = StringBuffer('<text x="${svgNum(_mx(x, baseline))}" y="${svgNum(_my(x, baseline))}"'
        ' font-size="${svgNum(look.size * _zoom)}" font-weight="$weight" fill="${svgHex(argb)}"');
    if (a < 1) buffer.write(' fill-opacity="${svgNum(a)}"');
    if (look.italic) buffer.write(' font-style="italic"');
    if (look.spacing != 0) buffer.write(' letter-spacing="${svgNum(look.spacing * _zoom)}"');
    buffer.write('>${svgEscape(text)}</text>');
    _body.write(buffer);
    elements++;
    texts++;
  }

  // ─────────────────── 옮기지 않는 것 ───────────────────

  @override
  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, ui.Paint paint) => _skip('drawVertices');

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) => _skip('drawParagraph');

  @override
  void drawPath(ui.Path path, ui.Paint paint) => _skip('drawPath');

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) => _skip('drawImage');

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) => _skip('drawImageRect');

  /// 부드러운 그늘(고른 띠 · 손 올린 띠). 내보내는 그림은 아무것도 고르지 않은 새 장면이라 여기 오지 않는다.
  @override
  void drawImageNine(ui.Image image, ui.Rect center, ui.Rect dst, ui.Paint paint) => _skip('drawImageNine');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    final at = name.indexOf('"');
    _skip(at < 0 ? name : name.substring(at + 1, name.lastIndexOf('"')));
    return null;
  }

  // ─────────────────── 다 적기 ───────────────────

  /// 열어 둔 무리를 모두 닫고 SVG 한 장을 글로 만든다. [head]는 `<defs>` 뒤 · 몸통 앞에 넣을 것(바탕 · 제목 · 기간 글).
  Future<String> toSvg({String head = ''}) async {
    while (_open > 0 || _levels.isNotEmpty) {
      restore();
    }
    final sheets = StringBuffer();
    for (final sheet in _atlases.values) {
      final bytes = await sheet.image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) continue;
      sheets.write('<image id="${sheet.id}" x="0" y="0" width="${sheet.image.width}" height="${sheet.image.height}"'
          ' preserveAspectRatio="none" href="data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}"/>');
    }
    final fonts = [sceneFontFamily, ...sceneFontFallback, 'sans-serif'].join(', ');
    return '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
        ' width="${svgNum(width)}" height="${svgNum(height)}" viewBox="0 0 ${svgNum(width)} ${svgNum(height)}"'
        ' font-family="${svgEscape(fonts)}">'
        '<defs>$sheets$_defs</defs>$head$_body</svg>';
  }
}

/// 네모 묶음을 이어받아 담을 때의 네모를 그대로 적는다(`ui.Vertices`는 되읽을 수 없다).
class SvgQuads extends Quads {
  final _at = <double>[];
  final _colors = <int>[];
  int _n = 0;

  @override
  int get count => _n;

  double left(int i) => _at[i * 4];
  double top(int i) => _at[i * 4 + 1];
  double right(int i) => _at[i * 4 + 2];
  double bottom(int i) => _at[i * 4 + 3];

  /// 꼭짓점 넷의 색이 모두 같은가.
  bool flat(int i) {
    final c = _colors[i * 4];
    return _colors[i * 4 + 1] == c && _colors[i * 4 + 2] == c && _colors[i * 4 + 3] == c;
  }

  int colorAt(int i) => _colors[i * 4];

  /// 꼭짓점 하나의 색(0 왼위 · 1 오른위 · 2 오른아래 · 3 왼아래).
  int cornerAt(int i, int corner) => _colors[i * 4 + corner];

  @override
  void add(double l, double t, double r, double b, int argb) => addCorners(l, t, r, b, argb, argb, argb, argb);

  @override
  void addCorners(double l, double t, double r, double b, int topLeft, int topRight, int bottomRight, int bottomLeft) {
    _at
      ..add(l)
      ..add(t)
      ..add(r)
      ..add(b);
    _colors
      ..add(topLeft)
      ..add(topRight)
      ..add(bottomRight)
      ..add(bottomLeft);
    _n++;
  }

  @override
  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    if (canvas is SvgCanvas) canvas.writeQuads(this);
    _at.clear();
    _colors.clear();
    _n = 0;
  }
}

/// 가는 선의 묶음. `Lines`는 안에 제 네모 묶음을 두므로 담는 길만 이어받는다(셈은 `Lines.add`와 같다).
class SvgLines extends Lines {
  SvgLines(super.argb);
  final quads = SvgQuads();

  @override
  void add(double x0, double y0, double x1, double y1) {
    if (x0 == x1) {
      final x = x0.floorToDouble();
      quads.add(x, y0, x + 1, y1, argb);
    } else {
      final y = y0.floorToDouble();
      quads.add(x0, y, x1, y + 1, argb);
    }
  }

  @override
  void flush(ui.Canvas canvas) => quads.flush(canvas);
}

/// 무늬 묶음을 이어받는다. 무늬 한 장의 크기는 raster와 같은 셈(`Patterns._make`의 `size`)으로 맞춘다.
class SvgPatterns extends Patterns {
  final _specs = <PatternSpec>[];
  final _at = <double>[];
  final _colors = <int>[];
  final _phase = <double>[];
  double _scale = 1;
  int _n = 0;

  int get count => _n;
  PatternSpec specAt(int i) => _specs[i];
  double left(int i) => _at[i * 4];
  double top(int i) => _at[i * 4 + 1];
  double right(int i) => _at[i * 4 + 2];
  double bottom(int i) => _at[i * 4 + 3];
  int colorAt(int i) => _colors[i];
  double phaseXAt(int i) => _phase[i * 2];
  double phaseYAt(int i) => _phase[i * 2 + 1];

  /// 되풀이되는 한 장의 크기(배치 px). raster는 화면 px로 반올림해 뜨므로 같은 셈을 따른다.
  double tileOf(int i) {
    final spec = _specs[i];
    double tile;
    if (spec.stairs) {
      tile = spec.period.round().clamp(2, 64).toDouble(); // 화소 계단은 기울지 않은 n칸 한 장(`Patterns._makeStairs`)
    } else if (spec.dots) {
      tile = spec.period;
    } else {
      final a = spec.angle % 180;
      tile = a == 90 || a == 0 ? spec.period : spec.period / math.sin(a * math.pi / 180).abs();
    }
    return (tile * _scale).roundToDouble().clamp(2.0, 512.0) / _scale;
  }

  @override
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next <= 0) return;
    _scale = next;
  }

  @override
  void add(PatternSpec spec, double l, double t, double r, double b, int argb, {double phaseX = 0, double phaseY = 0}) {
    if (r <= l || b <= t) return;
    _specs.add(spec);
    _at
      ..add(l)
      ..add(t)
      ..add(r)
      ..add(b);
    _colors.add(argb);
    _phase
      ..add(phaseX)
      ..add(phaseY);
    _n++;
  }

  @override
  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    if (canvas is SvgCanvas) canvas.writePatterns(this);
    _specs.clear();
    _at.clear();
    _colors.clear();
    _phase.clear();
    _n = 0;
  }
}

/// 글자 뒷단 (다) — 진짜 `<text>`로 적는다.
///
/// 폭 재기 · 예산은 [inner](화면이 쓰는 뒷단)에 그대로 맡긴다. 이름 자리를 정하는 것이 폭이므로,
/// 그래야 SVG의 이름이 PNG와 **같은 자리**에 선다. 그리기만 화폭이 [SvgCanvas]일 때 `<text>`로 갈라 나간다.
class SvgText extends SceneText {
  SvgText({SceneText? inner}) : inner = inner ?? ParagraphText();

  /// 폭을 재고 예산을 지키는 뒷단(화면과 같은 것).
  final SceneText inner;

  /// (크기, 꼴) → 글의 밑줄이 글줄 상자 위에서 얼마나 내려와 있는가.
  final _baselines = <(double, int), double>{};

  @override
  int get newThisFrame => inner.newThisFrame;
  @override
  bool get starved => inner.starved;
  @override
  double get spentMs => inner.spentMs;

  /// 옅어짐은 `fill-opacity` 하나면 되므로 층이 필요 없다(그림판 방식과 같다 — 이름의 드나듦이 화면과 같게).
  @override
  bool get canFade => true;

  @override
  void beginFrame() {
    inner
      ..maxNewPerFrame = maxNewPerFrame
      ..budgetMicros = budgetMicros;
    inner.beginFrame();
  }

  @override
  double? widthOf(String text, TextLook look) => inner.widthOf(text, look);

  @override
  void setScale(double scale) => inner.setScale(scale);

  @override
  bool paint(ui.Canvas canvas, String text, TextLook look, double x, double y, {double alpha = 1}) {
    if (canvas is! SvgCanvas) return inner.paint(canvas, text, look, x, y, alpha: alpha);
    if (inner.widthOf(text, look) == null) return false; // 아직 준비가 안 된 이름은 화면과 같게 다음 장면으로
    canvas.writeText(text, look, x, y + baselineOf(text, look), alpha);
    return true;
  }

  /// 글줄 상자의 위에서 밑줄까지(px). 화면은 글줄 상자의 위를 [y]로 받고 SVG의 `<text>`는 밑줄을 받는다.
  double baselineOf(String text, TextLook look) => _baselines[(look.size, look.shapeKey)] ??= () {
        final builder = ui.ParagraphBuilder(look.paragraphStyle(1))
          ..pushStyle(look.textStyle(look.color, 1))
          ..addText(text.isEmpty ? '가' : text);
        final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
        final baseline = paragraph.alphabeticBaseline;
        paragraph.dispose();
        return baseline;
      }();

  @override
  void flush(ui.Canvas canvas) {
    if (canvas is! SvgCanvas) inner.flush(canvas);
  }

  @override
  void dispose() {
    inner.dispose();
    _baselines.clear();
  }
}

/// 다 적은 SVG 한 장과, 무엇을 얼마나 적었는지.
class ExportSvg {
  const ExportSvg(this.svg, {required this.texts, required this.elements, required this.shapes, required this.labels, required this.skipped});

  /// SVG 글 전체.
  final String svg;

  /// 적은 `<text>`의 수와 그림 조각 전체의 수.
  final int texts, elements;

  /// 그리개가 이번 장면에 모은 도형과 글줄의 수(`SceneStats`) — [texts]와 [labels]는 같아야 한다.
  final int shapes, labels;

  /// 옮기지 못하고 넘긴 그리기 호출(비어 있어야 한다).
  final Map<String, int> skipped;
}

/// 걸음 하나(그리개의 `_Step`과 같다).
class _Step {
  const _Step(this.each, this.layer, {this.once, this.text = false});
  final void Function(PaintContext c, Tile tile)? each;
  final void Function(PaintContext c)? once;
  final TileLayer layer;
  final bool text;
}

/// 한 장면을 [canvas]에 SVG로 그린다 — **`scene/painter.dart`의 `TimelinePainter.paint`와 같은 층 차례**다.
///
/// [painter]의 층을 그대로 쓴다(그림판 · 이름 자리 · 밝기 상태가 화면과 같은 것이라야 한다). 배율(돋보기)과
/// 밝기 상태는 [painter]가 이미 장면을 그려 두었을 때의 것을 쓴다 — 내보내기는 다 가라앉힌 뒤에 한 번만 부른다.
void paintSceneToSvg(
  TimelinePainter painter,
  SvgCanvas canvas,
  ui.Size size, {
  required SvgText text,
  required SvgQuads quads,
  required SvgLines dividers,
  required SvgPatterns patterns,
  required Ruler ruler,
}) {
  final scene = painter.scene;
  final later = TextQueue();
  // 무늬 한 장은 화면 px로 뜬다 — 조각 그림판과 같은 배율을 알려 주어야 SVG의 무늬 주기가 PNG와 같다.
  patterns.setScale(Sprites.shared.scale);
  text.beginFrame();
  scene.measureName ??= (title, importance) => text.widthOf(title, Look.event(importance));
  scene.prepare();

  // 떠오르는 타일(200ms)은 떠오름 없이 다 보이게 적는다(그림 저장은 멈춘 그림 — 층째 투명도로 적으면 맨 아래 연도 세로줄이 띠 안에 비친다 ·
  // 세로줄 얹기 걸음 4). 그 밑에 깐 메움 타일(같은 열쇠 · 사라지는 줄의 타일은 빼고)도 적지 않는다 — 다 도착한 장면과 같은 그림.
  final fading = {for (final d in scene.draw) if (!d.isCover && d.alpha < 1) d.key};
  final plain = <DrawTile>[], wrapped = <DrawTile>[];
  for (final d in scene.draw) {
    if (d.isCover && !d.ghost && fading.contains(d.key)) continue;
    (d.clip == null ? plain : wrapped).add(d);
  }

  final v = scene.controller.view;
  final stats = scene.stats
    ..shapes = 0
    ..labels = 0;
  final w = size.width / v.mag, h = size.height / v.mag;
  // 그 자리의 바탕색(paint/grounds.dart): SVG의 바탕은 종이라 그 위에 섞는다(그리개는 그림판 바탕).
  final grounds = Grounds()..reset(Look.paper);
  final c = PaintContext(
      canvas: canvas, scene: scene, text: text, w: w, h: h, quads: quads, dividers: dividers, later: later, patterns: patterns, grounds: grounds, under: SvgQuads());

  // 준비(beginFrame)의 차례는 그리개(`TimelinePainter._tileLayers`)와 같아야 한다 — 띠 층이 맨 앞(조감의 이름 자리를 대범위 · 관계선 층이 읽는다).
  final tileLayers = <TileLayer>[painter.bands, painter.scopes, painter.links, painter.hangs, painter.minibars, painter.strips, painter.rails, painter.figures, painter.bars, painter.threads];
  // 뒤 판의 맨 앞(그리개 `_scopeSteps`와 같다): 그릇(불투명 종이 · 판 → 바깥 → 안) → 바탕 문화의 칠(불투명 종이 — 테 · 맞히기는 앞 판 띠 걸음).
  final scopeSteps = <_Step>[
    _Step((c, t) => painter.scopes.paintTile(c, t), painter.scopes),
    _Step((c, t) => painter.bands.paintUnder(c, t), painter.bands),
  ];
  final backSteps = <_Step>[
    _Step((c, t) => painter.links.paintTile(c, t), painter.links),
    _Step((c, t) => painter.hangs.paintTile(c, t), painter.hangs, text: true),
  ];
  final frontSteps = <_Step>[
    _Step((c, t) => painter.bands.paintTile(c, t), painter.bands),
    _Step((c, t) => painter.minibars.paintTile(c, t), painter.minibars),
    _Step((c, t) => painter.scopes.paintOverBands(c, t), painter.scopes),
    _Step((c, t) => painter.strips.paintTile(c, t), painter.strips),
    _Step((c, t) => painter.figures.paintTile(c, t), painter.figures),
    _Step((c, t) {
      painter.rails.paintTile(c, t);
      painter.bars.paintTile(c, t);
    }, painter.rails),
    _Step((c, t) => painter.hangs.paintFront(c, t), painter.hangs),
    _Step(null, painter.bands, once: painter.bands.paintEdges, text: true),
  ];
  final markSteps = <_Step>[_Step((c, t) => painter.links.paintFront(c, t), painter.links, text: true)];

  void finish(_Step s) {
    s.once?.call(c);
    s.layer.flushUnder(c); // 층의 밑 조각(반투명이던 귀의 불투명 종이)은 그 걸음의 네모 · 무늬보다 먼저(그리개 `_finish`와 같다)
    c.flushShapes();
    s.layer.flush(c);
    if (s.text) c.flushText();
  }

  void pass(List<_Step> steps) {
    if (plain.isNotEmpty) {
      for (final s in steps) {
        final each = s.each;
        if (each != null) {
          for (final d in plain) {
            each(c, d.tile);
          }
        }
        finish(s);
      }
    }
    // 남는 것은 메움 타일(제 자리만큼 자른다)뿐이다 — 떠오르는 타일은 위에서 보통 타일로 갈랐다(층 감싸기 없음).
    for (final d in wrapped) {
      canvas.save();
      canvas.clipRect(d.clip!);
      c.grounds.clip = d.clip;
      for (final s in steps) {
        s.each?.call(c, d.tile);
        finish(s);
      }
      canvas.restore();
      c.grounds.clip = null;
    }
  }

  canvas.save();
  canvas.scale(v.mag);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), c.fill..color = const ui.Color(Look.paper));
  for (final layer in tileLayers) {
    layer.beginFrame(c);
  }
  // 그리개와 같은 차례(scene/painter.dart 머리 주석): 바탕 눈금을 맨 아래에 한 번 적고, 그 위에 몸통 → 왼쪽 칸 → 날짜 칸을 차례대로 얹는다.
  canvas.save();
  canvas.clipRect(ui.Rect.fromLTRB(v.left, v.head, w, h));
  final marks = ruler.compute(v.lo, v.hi, v.ppm);
  painter.grid.paint(c, marks);
  // 뒤 판: 바탕 종이 · 그릇 · 바탕 문화 → 조감의 현재선 → 사람 띠의 실 · 뿔 매듭(리메이크 4단계 과제 4 걸음 2 — 그리개처럼 타일 바퀴 밖에서 한 번 ·
  // 그릇 종이 위 · 실의 작은 그림판은 조각 + 가림막으로 적힌다) → 관계선 · 매단 것. 그리개의 칠 없는 받침 카드 종이 걸음은 없다(SVG에는 받침 카드
  // 걸음이 예전부터 없다).
  // 바탕 종이(그리개 `_paperStep`과 같다): 접힌 민족 줄의 띠 몸통에 바탕색 종이 — 그릇보다 먼저(펼친 그릇 안이면 그릇 종이 · 테가 그 위에 온다).
  // 감독이 접힌 줄 종이를 뒤집으면 이 한 줄만 뺀다.
  finish(_Step(null, painter.minibars, once: painter.minibars.paintFoldedPaper));
  pass(scopeSteps);
  painter.grid.paintBirdNow(c);
  if (painter.threads.threads.isNotEmpty) finish(_Step(null, painter.threads, once: painter.threads.paint));
  pass(backSteps);
  pass(frontSteps);
  painter.minibars.paintFoldedRows(c);
  finish(_Step(null, painter.minibars));
  painter.grid.paintOver(c, marks);
  c.flushShapes();
  painter.events.paint(c);
  pass(markSteps);
  painter.overlay.paint(c);
  c.flushShapes();
  c.flushText();
  canvas.restore();
  painter.gutter.paint(c);
  painter.axis.paint(c, marks);
  canvas.restore();
  stats.newParagraphs = text.newThisFrame;
}
