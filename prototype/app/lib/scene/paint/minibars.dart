import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../tile.dart';
import 'context.dart';
import 'ink.dart';
import 'look.dart';

// 접힌 트랙 · 접힌 민족 줄의 '가는 막대'(`.tl-mini-bar` — 명세 05의 5.3절 · 실측 9.2 · 9.3).
// 접힌 자리에는 띠도 칸도 사건도 없고, 그 안의 정권마다 가는 막대 하나만 남는다.
//
// 단(위아래 줄)은 **자료로 미리 정해** 실어 온다(원칙 ① — 화면이 정하면 옆으로 옮길 때 막대가 단을 바꾼다).
// 접힘 여부와 단의 자리 · 상자 높이는 줄 쌓기의 `layout`(isTrackFolded · mergedRows · miniTop · foldedHeight)이 준다.
// 접히는 묶음은 민족 · 문화 묶음과 **대범위 가지**(켠 대범위의 점선 칸) 둘이고, 가지는 드는 줄이 이어져 있지 않다.
// 리메이크 2부부터 닫힌 그릇(대범위 가지)에는 막대 · 줄무늬를 그리지 않는다 — 목업 서고처럼 윗변에 매단 작은 꼬리표만(scopes.dart).
// 구역 45가 띠마다 두 단 번호를 나른다: a = 접힌 트랙용(`_laneAll`) · b = 접힌 민족 줄용(`_laneRow`).
//
// 그리기는 모두 묶음으로 한다: 줄 바탕의 줄무늬는 c.quads의 가는 선, 막대의 채움과 둘레는 제 그림판(둥근 네모)에 모아 한 번에.

/// 가는 막대의 값 — css의 마지막에 이기는 값. 높이 · 단 자리 · 상자 높이는 `layout.metrics`(G · G_BIRD)가 준다.
abstract final class Mini {
  /// 막대의 높이 6(조감 3) · 첫 단의 위 5(조감 1.5) · 단 사이 8(조감 4) — 기준값(층은 `layout.metrics`를 읽는다).
  static const height = 6.0, birdHeight = 3.0, top = 5.0, pitch = 8.0, birdPitch = 4.0;
  static const radius = 3.0, minWidth = 3.0, lanes = 3;

  /// 바탕 `color-mix(in srgb, var(--c) 70%, var(--paper))` · 둘레 `inset 0 0 0 1px color-mix(in srgb, var(--edge) 55%, transparent)`.
  static const fillMix = .70, edgeMix = .55;

  /// 몸통 쪽 접힌 줄의 바탕(css 428): 90° 줄무늬 — 6px 비우고 1px 긋기 · 모서리 6 · `--paper-line` 60%.
  static const stripeGap = 6.0, stripeWidth = 1.0, stripeAlpha = .6, stripeRadius = 6.0;

  /// 일반 항목 구역 45(계약 6-11절 — 39~44는 이미 쓰였다).
  static const section = 45;
}

/// 가는 막대의 둥근 네모(바탕 + 안쪽 1px 둘레)를 크기마다 한 번 그려 두고 한 번에 찍는다.
/// 높이는 6과 3 두 가지뿐이고 가로는 늘여 찍는다 — 모서리 3px은 세로로만 늘어나지 않게 조각을 두 쪽(왼 · 오른)으로 쓴다.
class MiniSprites {
  MiniSprites._(this._image, this._scale);
  ui.Image _image;
  double _scale;

  /// 조각 한 칸: (높이, 왼쪽 끝인가). 그림은 폭 [_cell] 안에 왼쪽 끝 · 오른쪽 끝 · 가운데(둘레만 위아래)를 나란히.
  static const _heights = [Mini.height, Mini.birdHeight];
  static const _cell = 8.0, _rows = 3; // 0 왼쪽 끝 · 1 오른쪽 끝 · 2 가운데

  static MiniSprites? _shared;
  static MiniSprites get shared => _shared ??= MiniSprites._(_render(1), 1);

  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image.dispose();
    _image = _render(next);
    _scale = next;
  }

  /// 흰 그림 하나에 조각을 그려 둔다 — 색은 찍을 때 곱한다(modulate).
  /// 안쪽 둘레는 바탕보다 옅은 값이라 색을 따로 곱할 수 없어, 채움 조각과 둘레 조각을 따로 둔다(alpha 채널로만).
  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final paint = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    for (int i = 0; i < _heights.length; i++) {
      final h = _heights[i], r = math.min(Mini.radius, h / 2);
      final x = i * _cell * 2;
      // 왼쪽 끝: 왼쪽 두 모서리만 둥글게. 오른쪽 끝: 오른쪽 두 모서리만.
      for (int side = 0; side < 2; side++) {
        final rect = ui.Rect.fromLTWH(x + side * _cell, 0, _cell, h);
        final rr = side == 0
            ? ui.RRect.fromRectAndCorners(ui.Rect.fromLTWH(rect.left, 0, _cell * 2, h), topLeft: ui.Radius.circular(r), bottomLeft: ui.Radius.circular(r))
            : ui.RRect.fromRectAndCorners(ui.Rect.fromLTWH(rect.left - _cell, 0, _cell * 2, h), topRight: ui.Radius.circular(r), bottomRight: ui.Radius.circular(r));
        canvas.save();
        canvas.clipRect(rect);
        canvas.drawRRect(rr, paint);
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_heights.length * _cell * 2 * scale).ceil(), (_heights.first * _rows * scale).ceil());
    picture.dispose();
    return image;
  }

  Float32List _transforms = Float32List(4 * 128), _rects = Float32List(4 * 128);
  Int32List _colors = Int32List(128);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  void _push(double sx, double sy, double sw, double sh, double dx, double dy, double scaleX, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = scaleX / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = dx;
    _transforms[p + 3] = dy;
    _rects[p] = sx * s;
    _rects[p + 1] = sy * s;
    _rects[p + 2] = (sx + sw) * s;
    _rects[p + 3] = (sy + sh) * s;
    _colors[_n] = argb;
    _n++;
  }

  /// 둥근 막대 하나. 가운데는 네모 묶음이 맡고 여기서는 양 끝의 둥근 조각만 찍는다.
  void addEnds(double height, double left, double right, double top, int argb) {
    int at = 0;
    for (int i = 1; i < _heights.length; i++) {
      if ((_heights[i] - height).abs() < (_heights[at] - height).abs()) at = i;
    }
    final source = _heights[at], x = at * _cell * 2;
    final scaleY = height / source;
    final cap = math.min(_cell * scaleY, (right - left) / 2);
    // 세로로만 늘릴 수 없어 조각을 가로도 같은 비율로 늘린다(모서리가 6→3px에서도 둥글게 보인다).
    _push(x, 0, _cell, source, left, top, scaleY, argb);
    _push(x + _cell, 0, _cell, source, right - cap, top, scaleY, argb);
  }

  /// 조각 하나의 가로 몫(양 끝이 차지하는 폭).
  double capOf(double height) => _cell * height / _heights.first;

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }
}

/// 가는 막대 하나(검사와 누름 판정이 읽는다).
class MiniBar {
  const MiniBar(this.band, this.row, this.lane, this.left, this.right, this.top, this.height, this.color);
  final int band, row, lane, color;
  final double left, right, top, height;

  @override
  String toString() => '막대(띠 $band · 줄 $row · 단 $lane · ${left.toStringAsFixed(1)}~${right.toStringAsFixed(1)} · 위 ${top.toStringAsFixed(1)})';
}

class MiniBarLayer extends TileLayer {
  final sprites = MiniSprites.shared;

  /// 이번 장면에 그린 막대(검사 · 누름 판정).
  final bars = <MiniBar>[];

  /// 타일에 걸쳐 잘린 띠는 번호로 합친다 — 한 막대를 두 번 그리지 않게.
  final _seen = <int>{};

  /// 접힌 묶음 줄에 합쳐진 줄 → 그 묶음의 머리 줄. `layout.mergedRows`를 거꾸로 편 것이다.
  /// 민족 묶음은 줄이 이어져 있지만 **대범위 가지**는 그렇지 않아(월흔해에서 `[8, 11, 12]`) 목록 쪽을 읽는다.
  final _groupOf = <int, int>{};
  int _stack = -1;

  @override
  void setScale(double scale) => sprites.setScale(scale);

  @override
  void beginFrame(PaintContext c) {
    bars.clear();
    _seen.clear();
    _paperDone = false;
    final layout = c.layout;
    if (layout.stackVersion == _stack) return;
    _stack = layout.stackVersion;
    _groupOf.clear();
    // 접힌 묶음: 머리 줄 → 그 줄에 합쳐진 줄들. 그 줄들의 띠가 모두 머리 줄의 막대가 된다.
    for (final entry in layout.mergedRows.entries) {
      for (final r in entry.value) {
        if (r < layout.rowCount) _groupOf[r] = entry.key;
      }
    }
  }

  @override
  void paintTile(PaintContext c, Tile t) {
    final section = t.section(Mini.section);
    if (section.count == 0) return;
    final layout = c.layout, v = c.v;
    final height = layout.miniHeight;
    final origin = t.origin;
    final x0 = section.f(Tile.itemX0), x1 = section.f(Tile.itemX1);
    final rows = section.u(Tile.itemRow), refs = section.u(Tile.itemRef);
    final colors = section.u(Tile.itemColor), laneAll = section.u(Tile.itemA), laneRow = section.u(Tile.itemB);
    for (int i = 0; i < section.count; i++) {
      final row = rows[i];
      if (row >= layout.rowCount) continue;
      final trackIndex = layout.trackIndexOf(row);
      final folded = layout.isTrackFolded(layout.tracks[trackIndex].id);
      final head = folded ? -1 : (_groupOf[row] ?? -1);
      if (!folded && head < 0) continue; // 펴져 있는 자리 — 막대가 아니라 띠로 그린다
      if (!folded && layout.foldedVariantOf(head).startsWith('scope:')) continue; // 닫힌 그릇은 막대 없이 작은 꼬리표만(목업 서고)
      if (!_seen.add(refs[i] != 0 ? refs[i] : -Object.hash(t.x, t.level, i).abs() - 1)) continue;
      // 자리: 접힌 트랙은 트랙 위 + 5(조감은 상자 가운데), 접힌 민족 줄은 그 줄의 띠 윗변 + 5.
      final double box, boxTop;
      if (folded) {
        if (layout.trackTop(trackIndex) < 0) continue;
        box = layout.foldedHeight;
        boxTop = v.yOf(layout.trackTop(trackIndex));
      } else {
        if (!layout.isVisible(head)) continue;
        box = layout.foldedGroupHeight;
        boxTop = v.yOf(layout.rowTop(head) + layout.geo(head).bandTop);
      }
      final lane = (folded ? laneAll[i] : laneRow[i]) & 0xff;
      final top = boxTop + layout.miniTop(lane, box);
      if (top + height < c.head || top > c.h) continue;
      final left = math.max(v.xOf(origin + x0[i]), c.left);
      final right = math.max(left + Mini.minWidth, math.min(v.xOf(origin + x1[i]), c.w));
      if (v.xOf(origin + x1[i]) < c.left || v.xOf(origin + x0[i]) > c.w) continue;
      final color = 0xff000000 | colors[i];
      _bar(c, left, right, top, height, color);
      bars.add(MiniBar(refs[i], row, lane, left, right, top, height, color));
    }
  }

  /// 막대 하나: 바탕(c 70% + 종이) 위에 안쪽 1px 둘레(edge 55%).
  void _bar(PaintContext c, double left, double right, double top, double height, int color) {
    final fill = mixSrgb(color, Look.paper, Mini.fillMix);
    final edge = withAlpha(mixOklab(color, Look.ink, .84), Mini.edgeMix);
    final cap = math.min(sprites.capOf(height), (right - left) / 2);
    sprites.addEnds(height, left, right, top, fill);
    if (right - left > cap * 2) c.quads.add(left + cap, top, right - cap, top + height, fill);
    // 안쪽 1px 둘레: 위 · 아래 가로선과 좌 · 우 세로선(모서리 3px은 조각의 둥근 끝이 이미 덮는다).
    c.quads.hLine(left + 1, right - 1, top + .5, edge);
    c.quads.hLine(left + 1, right - 1, top + height - .5, edge);
    c.quads.vLine(left + .5, top + 1, top + height - 1, edge);
    c.quads.vLine(right - .5, top + 1, top + height - 1, edge);
    c.stats.shapes += 5;
  }

  /// 몸통 쪽 접힌 민족 줄의 바탕(css 428): 90° 줄무늬(6px 비우고 1px 긋기) · 모서리 6.
  /// 줄 이름 칸이 아니라 **몸통**의 줄 바탕이라 이 층이 그린다(접힌 줄에는 띠가 없다).
  void paintFoldedRows(PaintContext c) {
    final stripe = CanvasInk.of(withAlpha(Look.line, Mini.stripeAlpha)); // 종이 위 먹 12(그림판 먹 단계 12 그대로)
    for (final (top, bottom) in _foldedBodies(c)) {
      // 모서리 6px은 양 끝 6px을 줄무늬에서 빼는 것으로 갈음한다(옅은 1px 줄이라 모서리가 보이지 않는다).
      for (double x = c.left + Mini.stripeGap; x < c.w; x += Mini.stripeGap + Mini.stripeWidth) {
        c.quads.add(x, top, x + Mini.stripeWidth, bottom, stripe);
      }
      c.stats.shapes++;
    }
  }

  /// 접힌 민족 줄의 띠 몸통 자리(그림 영역 가로 전체 × 띠 윗변 ~ 띠 높이)에 **그 자리 바탕색 종이**를 깐다 — 줄무늬 사이로 연도 세로줄이 비치지 않게
  /// (감독 2026-10-25 '다 막아줘' · '할거 등 폴더 부분에도 세로선 없게' — 접힌 줄도 종이로 본 것은 조정자 판단).
  /// 그리개 · SVG 뒤 판의 'grounds' 걸음(그릇 칠 뒤 · 사람 띠의 실 · 관계선 · 매단 것 앞 · 타일 바퀴 밖)에서 장면에 한 번 — 줄무늬는 예전 자리(앞 판 뒤)에 그대로다.
  /// **감독이 뒤집으면** 그리개(`painter.dart` `paint`의 `_finish(c, _paperStep)`)와 SVG(`export_svg.dart` `paintSceneToSvg`의 `paintFoldedPaper` 걸음)
  /// 한 줄씩만 빼면 예전 그림이다.
  void paintFoldedPaper(PaintContext c) {
    if (_paperDone) return;
    _paperDone = true;
    for (final (top, bottom) in _foldedBodies(c)) {
      c.grounds.paper(c.quads, c.left, top, c.w, bottom);
      c.stats.shapes++;
    }
  }

  bool _paperDone = false;

  /// 화면에 걸친 접힌 민족 줄의 띠 몸통(위 · 아래 y) — 닫힌 그릇(대범위 가지)은 목업 서고의 닫힌 폴더 · 상자라 빼고(줄무늬 없이 매단 작은 꼬리표만 — scopes.dart · 리메이크 2부).
  Iterable<(double, double)> _foldedBodies(PaintContext c) sync* {
    final layout = c.layout, v = c.v;
    for (final head in layout.mergedRows.keys) {
      if (head >= layout.rowCount || !layout.isVisible(head)) continue;
      if (layout.foldedVariantOf(head).startsWith('scope:')) continue;
      final geo = layout.geo(head);
      final top = v.yOf(layout.rowTop(head) + geo.bandTop);
      final bottom = top + geo.bandHeight;
      if (bottom < c.head || top > c.h) continue;
      yield (top, bottom);
    }
  }

  @override
  void flush(PaintContext c) => sprites.flush(c.canvas);
}
