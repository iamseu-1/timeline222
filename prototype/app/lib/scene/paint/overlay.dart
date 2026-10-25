import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../motion.dart';
import '../../motion_spring.dart';

import '../color_mix.dart';
import '../labels.dart';
import '../marks.dart';
import '../tile.dart' show Tile;
import 'bands.dart' show BandKind, BandLayer, BandLook;
import 'context.dart';
import 'gutter.dart' show GutLook;
import 'look.dart';

// 몸통의 맨 위에 얹는 것 — 도착 고리(멀리 가기가 닿은 항목에 한 번) · 조명이 옮겨 갈 때의 잔상처럼 어느 층에도 속하지 않는 표시.
// 그리개가 표식 판 뒤 · 몸통 자르기 안에서 한 번 부른다. 모으기는 다른 층과 같은 묶음 연장(c.quads · 제 그림판 · c.later)으로만 한다.
//
// 도착 고리(명세 06의 4-4 · css/common.css 1166~1174): 멀리 가서 **도착한 뒤에** 600ms 동안 고리가 한 번 옅어진다.
//  · 띠 · 트랙: 상자 **안쪽**에 2px 고리(`inset 0 0 0 2px`) — 띠 밖으로 넘치지 않는다. 트랙은 옅은 바탕(accent 7%)도 함께.
//  · 사건 점: 점에서 5px 밖에 2px 고리(`inset: -5px`).
// 무엇에 걸지는 `SceneMarks.ring`(띠 · 사건의 타일 번호 · 줄 · 트랙)에 다리가 적어 두고, 자리는 그 장면의 타일에서 찾는다.
class OverlayLayer extends SceneLayer {
  /// 고리의 둥근 모서리와 점의 동그라미를 찍는 제 그림판(공용 `scene/sprites.dart`에는 2px 고리가 없다).
  final sprites = RingSprites();

  /// 고리 색(css `color-mix(in srgb, var(--accent) 75%, transparent)`)과 트랙의 옅은 바탕(accent 7%).
  static const ringMix = .75, trackFill = .07;

  /// 고리의 굵기와 사건 점에서 밖으로 나가는 거리.
  static const stroke = 2.0, dotOut = 5.0;


  @override
  void setScale(double scale) => sprites.setScale(scale);

  /// 연합의 겹 탭에 올렸을 때 구성 나라가 아닌 줄의 흐림(웹 `.tl.coal-hot .tl-lane:not(.is-coal-on) { opacity: .3 }` ·
  /// `.tl-row:not(.is-coal-on) { opacity: .4 }`) — 바탕(몸통도 왼쪽 칸도 종이 — HistoryArchive 통일 뒤로 줄 이름 칸의 바탕이 몸통과 같은 면)을
  /// 그만큼 덮어 같은 모습을 낸다.
  static const coalLaneCover = .7, coalRowCover = .6;

  /// 올린 연합의 구성 나라 줄(띠 층이 장면을 열 때 모은 것). 올린 것이 없거나 이 장면에 그 연합의 띠가 하나도 없으면 null
  /// (표시 체크 '단체'를 껐거나 탭이 화면을 떠난 뒤의 낡은 올림으로 모든 줄을 옅게 하지 않게).
  Set<int>? _coalMembers(PaintContext c) {
    final hot = SceneMarks.of(c.scene).hotCoal;
    if (hot == null || hot.isEmpty) return null;
    final rows = BandLayer.of(c.scene)?.coalRows(hot);
    return rows == null || rows.isEmpty ? null : rows;
  }

  /// 구성 나라가 아닌 줄마다 [x0] ~ [x1]을 [argb]로 덮는다(위 · 아래로 이웃한 줄은 한 네모로).
  void _coverRows(PaintContext c, Set<int> members, double x0, double x1, int argb, {required bool bandOnly}) {
    final layout = c.layout, v = c.v;
    double? from;
    double to = 0;
    void close() {
      final a = from;
      if (a != null && to > a) c.quads.add(x0, a, x1, to, argb);
      from = null;
    }

    for (int row = 0; row < layout.rowCount; row++) {
      if (!layout.isVisible(row)) continue;
      final geo = layout.geo(row);
      // 몸통은 줄의 몫 전체(탭 줄 · 띠 · 띠 아래 덧붙는 단 — 웹의 .tl-lane), 왼쪽 칸은 줄 이름 칸(띠의 위부터 — 웹의 .tl-row).
      final top = v.yOf(layout.rowTop(row) + (bandOnly ? geo.bandTop : 0));
      final bottom = v.yOf(layout.rowTop(row) + geo.height);
      if (bottom < c.head || top > c.h) continue;
      if (members.contains(row)) {
        close();
        continue;
      }
      if (from != null && (top - to).abs() < .01) {
        to = bottom;
      } else {
        close();
        from = top;
        to = bottom;
      }
    }
    close();
  }

  /// 왼쪽 칸(줄 이름)의 흐림 — 그리개가 왼쪽 칸을 그린 뒤에 부른다(몸통 자르기 밖).
  void paintGutter(PaintContext c) {
    final members = _coalMembers(c);
    if (members == null || c.layout.bird) return;
    const rowsLeft = GutLook.rowX - 3; // 줄 이름(작은 꼬리표 그림)부터
    _coverRows(c, members, rowsLeft, c.left - 1, withAlpha(Look.paper, coalRowCover), bandOnly: true);
    c.flushShapes();
  }

  @override
  void paint(PaintContext c) {
    // 연합의 겹 탭에 올렸을 때: 구성 나라가 아닌 줄을 .3으로(탭 · 띠 · 칸 · 사건 모두 — 그 위에 덮는다).
    final members = _coalMembers(c);
    if (members != null && !c.layout.bird) {
      // 덮개는 그림판 바탕색(건의 2026-10-15 1번 — 바탕이 흰색이 아니게 됨). 왼쪽 칸은 흰 종이 그대로라 위 paintGutter는 종이.
      _coverRows(c, members, c.left, c.w, withAlpha(Look.ground, coalLaneCover), bandOnly: false);
      c.debug?.note('연합흐림', '구성 줄 ${members.length}');
    }
    final ring = SceneMarks.of(c.scene).ring;
    if (ring == null || ring.isEmpty) return;
    // 움직임 줄이기에서는 그리지 않는다(도착은 화면이 이미 그 자리에 서 있는 것으로 알린다).
    if (c.scene.controller.reduceMotion) return;
    final alpha = MotionStep(MotionToken.ring, c.scene.now - ring.at).xx.clamp(0.0, 1.0);
    if (alpha <= .004) return;
    // 흐르는 동안은 다음 장면을 청한다(장면의 시계가 돌아야 고리가 옅어진다).
    c.scene.requestFrame();

    final argb = withAlpha(withAlpha(Look.accent, ringMix), alpha);
    c.debug?.note('고리', '밝기=${alpha.toStringAsFixed(2)}');
    if (ring.track != 0) _track(c, ring.track, argb, alpha);
    if (ring.band != 0 || ring.row >= 0) _bands(c, ring, argb);
    if (ring.event != 0) _dot(c, ring.event, argb);
    // 제 그림판은 제가 내보낸다 — 공통 묶음(네모)을 먼저 내보내야 고리가 옅은 바탕 위에 온다.
    c.flushShapes();
    sprites.flush(c.canvas);
  }

  /// 트랙 하나: 옅은 바탕 + 모서리 없는 고리(css `.tl-track.is-arrived::after`).
  void _track(PaintContext c, int trackId, int argb, double alpha) {
    final layout = c.layout;
    final index = layout.tracks.indexWhere((t) => t.id == trackId);
    if (index < 0) return;
    final top = layout.trackTop(index), height = layout.trackHeight(index);
    if (top < 0 || height <= 0) return;
    final y = c.v.yOf(top), b = y + height;
    if (b < c.head || y > c.h) return;
    c.quads.add(c.left, y, c.w, b, withAlpha(withAlpha(Look.accent, trackFill), alpha));
    _box(c, c.left, y, c.w, b, 0, 0, argb);
    c.debug?.note('고리', '트랙 $trackId ${_rect(c.left, y, c.w, b)} 바탕');
  }

  /// 띠(또는 그 줄의 띠 모두): 타일에 걸쳐 잘린 조각을 이어 붙인 진짜 두 끝에 상자 안쪽 고리를 두른다.
  void _bands(PaintContext c, SceneRing ring, int argb) {
    final v = c.v, layout = c.layout;
    // 띠 번호 → (왼쪽, 오른쪽, 줄, look). 타일에 걸친 띠는 조각마다 오므로 두 끝을 모은다.
    final left = <int, double>{}, right = <int, double>{};
    final rowOf = <int, int>{}, lookOf = <int, int>{};
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile, origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        final id = t.bandId[i];
        if (ring.band != 0 ? id != ring.band : t.bandRow[i] != ring.row) continue;
        final x0 = v.xOf(origin + t.bandX0[i]), x1 = v.xOf(origin + t.bandX1[i]);
        if (x0 < (left[id] ?? double.infinity)) left[id] = x0;
        if (x1 > (right[id] ?? double.negativeInfinity)) right[id] = x1;
        rowOf[id] = t.bandRow[i];
        lookOf[id] = t.bandLook[i];
      }
    }
    for (final id in rowOf.keys) {
      final row = rowOf[id]!;
      if (row >= layout.rowCount || !layout.isVisible(row)) continue;
      final geo = layout.geo(row), look = lookOf[id]!;
      final under = look & BandLook.under != 0;
      final top = v.yOf(layout.rowTop(row) + geo.bandTop);
      final height = under ? geo.height - geo.bandTop : geo.bandHeight;
      if (height <= 0 || !c.rowOnScreen(row, top, height)) continue;
      // 화면 밖으로 나간 쪽은 모서리를 두지 않는다(잘린 쪽에는 둥근 모서리가 없다 — 띠 층과 같은 규칙).
      final cutL = left[id]! < c.left, cutR = right[id]! > c.w;
      final l = math.max(left[id]!, c.left), r = math.min(right[id]!, c.w);
      if (r - l < 2) continue;
      final radius = _radius(c, look);
      final cap = math.min((r - l) / 2, height / 2);
      final radiusL = cutL ? 0.0 : math.min(radius, cap), radiusR = cutR ? 0.0 : math.min(radius, cap);
      _box(c, l, top, r, top + height, radiusL, radiusR, argb);
      c.debug?.note('고리', '띠 $id 줄 $row ${_rect(l, top, r, top + height)} 반지름=${radiusL.round()}/${radiusR.round()}');
    }
  }

  /// 띠의 모서리 반지름 — 띠 층의 값 그대로(문화 · 바탕 문화 12 · 그 밖 10 · 조감은 모양이 정한다).
  double _radius(PaintContext c, int look) {
    final bird = c.layout.birdShape;
    if (bird != null) return bird.radius;
    return BandLook.kindOf(look) == BandKind.culture || look & BandLook.under != 0 ? 12 : 10;
  }

  /// 사건 점 하나: 점의 한가운데에서 `점 폭 / 2 + 5`만큼 밖에 고리를 두른다.
  void _dot(PaintContext c, int eventId, int argb) {
    final v = c.v, layout = c.layout;
    final batch = c.scene.labelBatch, out = c.scene.labelOutput;
    // (가) 이번 판에 그려진 점이면 그린 자리를 그대로 쓴다(글줄 · 이름 쪽에 따라 점이 비껴 있다).
    if (batch != null && out != null) {
      final input = batch.input;
      for (int i = 0; i < out.shownCount; i++) {
        if (out.shownEventId[i] != eventId) continue;
        final cand = out.shownCandidate[i], row = input.row[cand];
        if (row >= layout.rowCount || !layout.isVisible(row)) return;
        final look = input.look[cand];
        final small = layout.bird || out.shownFlags[i] & LabelFlag.small != 0;
        final geo = layout.geo(row);
        final x = v.xOf(out.shownAt[i]) + EventLook.dotDx(look, side: out.shownSide[i], small: small);
        final lift = BandLayer.of(c.scene)?.eventLiftOf(layout, row, input.band[cand]) ?? 0; // 두 장 꼬리표: 칸 없는 띠의 사건 칸
        final y = v.yOf(layout.rowTop(row) + geo.textTop + (out.shownLine[i] + .5) * geo.lineH - lift);
        _circle(c, eventId, x, y, EventLook.dotBox(look, small: small) + 2 * dotOut, argb);
        return;
      }
    }
    // (나) 아직 이름 자리를 못 받았거나 묶음에 든 점이면 타일의 사건 구역에서 자리를 찾는다(글줄은 첫 줄로 본다).
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile, origin = t.origin.toDouble();
      for (int i = 0; i < t.eventCount; i++) {
        // 앞 타일에서 이어 온 막대 조각(왼쪽 잘림)의 x0은 타일 시작이지 사건 자리가 아니다 — 점은 시작 조각에서(label_batch.dart와 같은 규칙).
        if (t.eventId[i] != eventId || t.eventBits[i] & Tile.eventClipLeft != 0) continue;
        final row = t.eventRow[i];
        if (row >= layout.rowCount || !layout.isVisible(row)) return;
        final geo = layout.geo(row);
        final look = t.eventLook[i];
        final lift = BandLayer.of(c.scene)?.eventLiftOf(layout, row, t.eventBand[i]) ?? 0;
        _circle(c, eventId, v.xOf(origin + t.eventX0[i]), v.yOf(layout.rowTop(row) + geo.textTop + .5 * geo.lineH - lift),
            EventLook.dotBox(look, small: layout.bird) + 2 * dotOut, argb);
        return;
      }
    }
  }

  /// 상자 안쪽 2px 고리: 곧은 네 변은 네모 묶음에, 둥근 모서리는 제 그림판의 호에.
  void _box(PaintContext c, double l, double t, double r, double b, double radiusL, double radiusR, int argb) {
    if (r - l < 2 * stroke || b - t < 2 * stroke) return;
    c.quads.add(l + radiusL, t, r - radiusR, t + stroke, argb);
    c.quads.add(l + radiusL, b - stroke, r - radiusR, b, argb);
    c.quads.add(l, t + radiusL, l + stroke, b - radiusL, argb);
    c.quads.add(r - stroke, t + radiusR, r, b - radiusR, argb);
    if (radiusL > 0) {
      sprites.addCorner(RingCorner.topLeft, l, t, argb, radiusL);
      sprites.addCorner(RingCorner.bottomLeft, l, b - radiusL, argb, radiusL);
    }
    if (radiusR > 0) {
      sprites.addCorner(RingCorner.topRight, r - radiusR, t, argb, radiusR);
      sprites.addCorner(RingCorner.bottomRight, r - radiusR, b - radiusR, argb, radiusR);
    }
    c.stats.shapes++;
  }

  /// 점 밖의 동그란 고리.
  void _circle(PaintContext c, int eventId, double x, double y, double diameter, int argb) {
    if (diameter <= 0) return;
    if (x < c.left - diameter || x > c.w + diameter || y < c.head - diameter || y > c.h + diameter) return;
    sprites.addCircle(x, y, diameter, argb);
    c.stats.shapes++;
    c.debug?.note('고리', '사건 $eventId 가운데=${x.round()},${y.round()} 지름=${diameter.round()}');
  }

  static String _rect(double l, double t, double r, double b) => '${l.round()},${t.round()}~${r.round()},${b.round()}';
}

/// 고리 조각을 찍을 네 모서리.
enum RingCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 맨 위 층의 작은 그림판: 굵기 2px의 고리 하나를 흰색으로 그려 두고, 모서리는 넷으로 나눠 · 점은 통째로 찍는다.
/// `scene/sprites.dart`와 같은 방식(drawRawAtlas 한 번)이되 고리에만 쓰는 조각이라 이 층에 둔다.
class RingSprites {
  /// 칸 하나: 바깥 지름 20의 2px 고리. 모서리는 이 칸의 사분면(반지름 10)이고, 다른 반지름은 줄여 찍는다.
  static const cell = 20.0, cellStroke = 2.0;

  ui.Image? _image;
  double _scale = 1;
  Float32List _transforms = Float32List(4 * 16), _rects = Float32List(4 * 16);
  Int32List _colors = Int32List(16);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;
  double get scale => _scale;

  /// 멎은 돋보기 배율(× 화면의 px 비율)이 바뀌었다 — 그림판을 그 배율로 다시 뜬다.
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  void _put(double sx, double sy, double sw, double left, double top, int argb, double size) {
    if (size <= 0 || ((argb >> 24) & 0xff) == 0) return;
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = size / sw / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = sx * s;
    _rects[p + 1] = sy * s;
    _rects[p + 2] = (sx + sw) * s;
    _rects[p + 3] = (sy + sw) * s;
    _colors[_n] = argb;
    _n++;
  }

  /// 반지름 [radius]의 둥근 모서리 한 조각을 왼쪽 위 자리에 찍는다.
  void addCorner(RingCorner corner, double left, double top, int argb, double radius) {
    final half = cell / 2;
    final sx = corner == RingCorner.topRight || corner == RingCorner.bottomRight ? half : 0.0;
    final sy = corner == RingCorner.bottomLeft || corner == RingCorner.bottomRight ? half : 0.0;
    _put(sx, sy, half, left, top, argb, radius);
  }

  /// 바깥 지름 [diameter]의 고리를 ([x], [y])를 가운데로 찍는다.
  void addCircle(double x, double y, double diameter, int argb) =>
      _put(0, 0, cell, x - diameter / 2, y - diameter / 2, argb, diameter);

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    final image = _image ??= render(_scale);
    canvas.drawRawAtlas(image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4),
        Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }

  static ui.Image render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    canvas.drawCircle(
      const ui.Offset(cell / 2, cell / 2),
      cell / 2 - cellStroke / 2,
      ui.Paint()
        ..color = const ui.Color(0xffffffff)
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = cellStroke,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync((cell * scale).ceil(), (cell * scale).ceil());
    picture.dispose();
    return image;
  }
}
