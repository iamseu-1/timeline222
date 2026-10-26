import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'batch.dart' show QuadIndices;

// 무늬(빗금 · 세로 줄 · 점무늬)를 묶어 그린다. 무늬마다 작은 그림 한 장을 되풀이 무늬로 깔고, 그 무늬를 쓰는 네모를 모두 모아
// drawVertices 한 번으로 끝낸다(꼭짓점 색으로 제 색을 입힌다). 네모마다 무늬를 따로 그리면 하나하나가 따로 처리되어 칠하기가 한도를 넘는다.
// 무늬의 값은 지금 연표의 css(repeating-linear-gradient · radial-gradient)에서 옮긴다 — docs/명세-3단계/01-띠의-표현.md의 무늬 표.

/// 무늬 하나의 생김새. 줄무늬는 [angle]도로 기운 [line]px 굵기의 줄이 [period]px마다, 점무늬는 [period]px 격자에 반지름 [line]px의 점.
/// 화소 계단([PatternSpec.stairs])은 [period]px 칸마다 1px 화소가 왼쪽 아래 → 오른쪽 위로 한 칸씩 오르는 빗금(보간 없이 1배 화소 격자에 —
/// 정통성 '주장'의 칸 · 머리 · 탭 바탕 · 칸 그림 갈래 걸음 3 · 다듬기 판 `themes/g-legit2.js` hatch의 5 × 5 무늬).
class PatternSpec {
  const PatternSpec.stripes(this.angle, this.line, this.period) : dots = false, stairs = false;
  const PatternSpec.dots(this.period, double radius) : dots = true, stairs = false, angle = 0, line = radius;
  const PatternSpec.stairs(this.period) : dots = false, stairs = true, angle = 45, line = 1;
  final bool dots, stairs;
  final double angle, line, period;

  @override
  bool operator ==(Object other) =>
      other is PatternSpec && other.dots == dots && other.stairs == stairs && other.angle == angle && other.line == line && other.period == period;
  @override
  int get hashCode => Object.hash(dots, stairs, angle, line, period);
}

class _Sheet {
  _Sheet(this.image, this.size, this.crisp) {
    // 무늬 붓은 장마다 한 번만 짓는다 — 내보낼 때마다 새로 지으면 장면마다 (층 × 무늬)만큼 native 그림 붓이 생겼다 버려진다.
    paint = ui.Paint()
      ..shader = ui.ImageShader(image, ui.TileMode.repeated, ui.TileMode.repeated, Patterns._identity, filterQuality: crisp ? ui.FilterQuality.none : ui.FilterQuality.low);
  }
  final ui.Image image;
  final double size;

  /// 가로 · 세로 줄무늬(점선을 대신하는 것)는 가장 가까운 점으로 깐다 — 겹선 보간이면 점선의 가장자리가 1px 번진다. 기운 줄과 점무늬는 보간해야 매끈하다.
  final bool crisp;

  /// 이 무늬 그림을 되풀이로 까는 붓(장마다 하나).
  late final ui.Paint paint;

  /// 네모 하나에 꼭짓점 넷(자리 · 무늬 자리 · 색) — 세모 둘은 [QuadIndices]의 색인이 만든다.
  Float32List at = Float32List(8 * 64), uv = Float32List(8 * 64);
  Int32List color = Int32List(4 * 64);
  int n = 0;

  void dispose() {
    paint.shader?.dispose();
    image.dispose();
  }
}

class Patterns {
  final _sheets = <PatternSpec, _Sheet>{};
  double _scale = 1;

  /// 멎은 돋보기 배율(× 화면의 px 비율)이 바뀌면 무늬 그림을 그 배율로 다시 뜬다(작아서 싸다).
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _scale = next;
    for (final sheet in _sheets.values) {
      sheet.dispose();
    }
    _sheets.clear();
  }

  /// 무늬로 칠할 네모를 모은다. [argb]는 줄(점)의 색 — 바탕은 투명이라 밑의 채움이 비친다. [phaseX] · [phaseY]는 무늬가 시작하는 자리(세계 좌표 px) — 옆으로 움직여도 무늬가 제자리에 붙어 있게.
  void add(PatternSpec spec, double l, double t, double r, double b, int argb, {double phaseX = 0, double phaseY = 0}) {
    if (r <= l || b <= t) return;
    final sheet = _sheets[spec] ??= _make(spec);
    if (sheet.n * 8 == sheet.at.length) {
      sheet.at = Float32List(sheet.at.length * 2)..setRange(0, sheet.at.length, sheet.at);
      sheet.uv = Float32List(sheet.uv.length * 2)..setRange(0, sheet.uv.length, sheet.uv);
      sheet.color = Int32List(sheet.color.length * 2)..setRange(0, sheet.color.length, sheet.color);
    }
    final p = sheet.n * 8, c = sheet.n * 4, s = _scale;
    final at = sheet.at, uv = sheet.uv;
    at[p] = l; at[p + 1] = t; at[p + 2] = r; at[p + 3] = t;
    at[p + 4] = r; at[p + 5] = b; at[p + 6] = l; at[p + 7] = b;
    final u0 = (l - phaseX) * s, v0 = (t - phaseY) * s, u1 = (r - phaseX) * s, v1 = (b - phaseY) * s;
    uv[p] = u0; uv[p + 1] = v0; uv[p + 2] = u1; uv[p + 3] = v0;
    uv[p + 4] = u1; uv[p + 5] = v1; uv[p + 6] = u0; uv[p + 7] = v1;
    final color = sheet.color;
    color[c] = argb; color[c + 1] = argb; color[c + 2] = argb; color[c + 3] = argb;
    sheet.n++;
  }

  void flush(ui.Canvas canvas) {
    for (final sheet in _sheets.values) {
      if (sheet.n == 0) continue;
      for (int from = 0; from < sheet.n; from += QuadIndices.perDraw) {
        final left = sheet.n - from, count = left < QuadIndices.perDraw ? left : QuadIndices.perDraw;
        final vertices = ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.sublistView(sheet.at, from * 8, (from + count) * 8),
          textureCoordinates: Float32List.sublistView(sheet.uv, from * 8, (from + count) * 8),
          colors: Int32List.sublistView(sheet.color, from * 4, (from + count) * 4),
          indices: QuadIndices.of(count),
        );
        // 무늬 그림은 흰색 + 투명도다 → 꼭짓점 색을 곱해 제 색의 줄이 된다.
        canvas.drawVertices(vertices, ui.BlendMode.modulate, sheet.paint);
        vertices.dispose();
      }
      sheet.n = 0;
    }
  }

  static final _identity = Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  _Sheet _make(PatternSpec spec) {
    final s = _scale;
    if (spec.stairs) return _makeStairs(spec.period, s);
    // 되풀이되는 한 장의 크기: 줄무늬는 기운 각에서도 이음매가 맞게 가로 · 세로의 주기를 따로 셈한다.
    double tile;
    if (spec.dots) {
      tile = spec.period;
    } else {
      final a = spec.angle % 180;
      tile = a == 90 || a == 0 ? spec.period : spec.period / math.sin(a * math.pi / 180).abs();
      // 45° · 135°의 줄은 가로 · 세로 주기가 같다(주기 ÷ sin 45°).
    }
    final size = (tile * s).roundToDouble().clamp(2.0, 512.0);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final white = ui.Paint()..color = const ui.Color(0xffffffff);
    if (spec.dots) {
      canvas.drawCircle(ui.Offset(size / 2, size / 2), spec.line * s, white..isAntiAlias = true);
    } else {
      final a = spec.angle % 180;
      if (a == 90) {
        canvas.drawRect(ui.Rect.fromLTWH(0, 0, spec.line * s, size), white);
      } else if (a == 0) {
        canvas.drawRect(ui.Rect.fromLTWH(0, 0, size, spec.line * s), white);
      } else {
        // 기운 줄: 한 장을 넘나드는 줄 셋을 그려 이음매를 맞춘다. css의 135°는 왼쪽 위 → 오른쪽 아래로 흐르는 무늬(줄은 오른쪽 위로 기운다), 45°는 그 반대.
        final stroke = ui.Paint()
          ..color = const ui.Color(0xffffffff)
          ..strokeWidth = spec.line * s
          ..isAntiAlias = true;
        final rising = a > 90;
        for (int k = -1; k <= 1; k++) {
          final o = k * size;
          if (rising) {
            canvas.drawLine(ui.Offset(o - size, size * 2), ui.Offset(o + size * 2, -size), stroke);
          } else {
            canvas.drawLine(ui.Offset(o - size, -size), ui.Offset(o + size * 2, size * 2), stroke);
          }
        }
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.toInt(), size.toInt());
    picture.dispose();
    final a = spec.angle % 180;
    return _Sheet(image, size, !spec.dots && (a == 0 || a == 90));
  }

  /// 화소 계단 한 장: [period]칸 × [period]칸에 (i, period − 1 − i)마다 한 칸(배율 [s]만큼 키운 네모 — 보간 없이 깐다).
  _Sheet _makeStairs(double period, double s) {
    final n = period.round().clamp(2, 64);
    final size = (n * s).roundToDouble().clamp(2.0, 512.0);
    final cell = size / n;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final white = ui.Paint()..color = const ui.Color(0xffffffff);
    for (int i = 0; i < n; i++) {
      canvas.drawRect(ui.Rect.fromLTWH(i * cell, (n - 1 - i) * cell, cell, cell), white);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.toInt(), size.toInt());
    picture.dispose();
    return _Sheet(image, size, true);
  }

  void dispose() {
    for (final sheet in _sheets.values) {
      sheet.dispose();
    }
    _sheets.clear();
  }
}
