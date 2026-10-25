import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../layout.dart' show G;
import '../sphere_crowns.dart';
import '../tile.dart';
import 'context.dart';
import 'ink.dart';
import 'links.dart' show LinkColumn, LinkColumns;
import 'look.dart';
import 'paint_pick.dart';
import 'sphere_lines.dart';

// 사람 띠의 실 · 뿔 매듭(리메이크 4단계 과제 4 걸음 2 · 목업 w-1-crowns personBar · 감독 10-23 "글자가 가려지면 안 됨").
// 기준은 메이커 서고 미리보기 — js/timeline.js `_drawF4Threads`(2217 ~ 2274줄)와 css/common.css `.tl-f4-threads`(2491 ~ 2494줄):
//   그려진 사람 띠마다, 왕관(띠 uid · 지도자 칸 순번)의 띠가 보이고(트랙 · 문화권 펼침 · 지도자 단) 그 칸이 4px 이상 그려졌으면
//   x = round(max(칸 왼쪽, 띠 왼쪽)) + 8.5에서 사람 띠 아랫변(+ .5) + 1.5부터 띠 윗변(+ .5) − 4.5까지 점선(1.2px · 1/3 · 둥근 끝 · 먹 50),
//   띠 윗변에 뿔 매듭(밑변 5 · 높이 4.5 · 종이 칠 · 테 1 먹 45), 사람 띠 아랫변에 점(반지름 1.5 · 먹 50).
//   띠 윗변이 사람 띠 아래 4.5 + 2 안이면 긋지 않는다.
// 그리는 자리는 뒤 판의 맨 앞(painter.dart — 띠 · 탭 · 칸 · 글자보다 먼저 = '띠 뒤 통로')이라 띠 · 줄 안의 것이 실을 덮고 빈 자리에서만 보인다.
// 그림판 몸통으로 잘리고, 다른 문화권의 머리 단 상자(왼쪽 칸 층 — 몸통 뒤에 그림)가 덮는 것도 미리보기와 같다.
// 머리 단 고정(과제 3 걸음 4 — 앱 먼저 · 미리보기에는 아직 없음): 붙은 머리 단의 사람 띠에서 떠나고, 붙은 상자 밑을 지나는 몫은 그 상자가 덮는다.
// 왕관의 띠 번호 · 줄 · 칸의 때는 장면 곁의 왕관 표(scene/sphere_crowns.dart)에서 — 화면 아래로 벗어난 띠로 가는 실도 미리보기처럼 긋는다.
// 칸이 그려졌는가 · 칸 왼쪽은 칸 층(strips.dart `_paintGroup`)과 같은 셈: 칸 상자 = 띠 상자(화면 ±1로 자름) 테 안 · 이어지지 않는 끝 .5 틈 · 빽빽한 칸(6px 아래)은 낱칸 없음.
// 점선 · 뿔 · 점은 이 층의 작은 그림판(drawRawAtlas)으로 찍는다 — SVG 저장의 화폭(ui/export_svg.dart)이 받는 꼴(조각 + 가림막).

/// 이 층의 값 — css에서 옮긴 값(메이커 서고 미리보기).
abstract final class SphereThreadLook {
  /// 실: 굵기 1.2 · 점선 1 / 틈 3(둥근 끝) · 먹 50. 칸 왼쪽에서 8.5.
  static const width = 1.2, dash = 1.0, gap = 3.0, ink = .50, inset = 8.5;

  /// 뿔 매듭: 밑변 5 · 높이 4.5(서고 `G_SEOGO.f4Horn`) · 종이 칠 · 테 1 먹 45. 사람 띠 아랫변의 점: 반지름 1.5 · 먹 50.
  static const hornBase = 5.0, horn = 4.5, hornEdge = 1.0, hornInk = .45, dot = 1.5;

  /// 실의 처음(사람 띠 아랫변 + .5에서 1.5 아래) · 긋지 않는 가까움(뿔 높이 + 2 안).
  static const start = 1.5, near = 2.0;

  /// 그려진 칸 폭이 이 아래면 긋지 않는다(미리보기 `cb.width < 4`).
  static const minCell = 4.0;

  /// 칸 층의 빽빽한 칸 셈(strips.dart `_pad2` · is-dense): 칸 상자 여백 3 · 칸 하나가 6px도 못 되면 단 전체가 한 칸(낱칸 없음 — 실이 닿을 칸이 없다).
  static const pad2 = 3.0, dense = 6.0;

  /// 실 비킴(명세 04 3-6 · 조사 결함 14 · 40 · 이어 주는 선 걸음 6 · 스위치 route): 세로로 겹치는 승계선 세로 기둥([LinkColumns])과
  /// 이만큼 안이면 실을 [dodge]만큼 오른쪽으로 옮긴다 — 옮긴 자리의 뿔(반 밑변 2.5 + 테 .5)이 칸 오른쪽 안에 들고 그 자리도 비었을 때만.
  /// 문턱 3(2026-10-25 저녁 2.5에서 — 백탑 등대 기사단국 → 서해 삼부 왕국의 오름줄과 양리 1세 실이 2.6px 나란해 한 줄처럼 보였다 · 검증 지적).
  static const clear = 3.0, dodge = 4.0;
}

/// 이번 장면에 그을 실 하나(배치 px).
class SphereThread {
  SphereThread(this.x, this.dot, this.knot, {required this.sphere, required this.person, required this.band, required this.cell});

  /// 실의 x(.5 자리) · 사람 띠 아랫변의 점 y(아랫변 + .5) · 뿔 매듭 밑변 y(띠 윗변 + .5).
  final double x, dot, knot;

  /// 사람 띠의 문화권 자리 · 인물 uid(없으면 빈 글) · 왕관 띠 번호 · 지도자 칸 순번.
  final int sphere, band, cell;
  final String person;

  /// 점선의 처음 · 끝 y(끝 = 뿔 꼭짓점).
  double get from => dot + SphereThreadLook.start;
  double get to => knot - SphereThreadLook.horn;

  /// 그릴 때 이미 그린 글줄 수(검사 기록이 켜졌을 때만 — 실이 모든 글자보다 먼저인가). 그리기 전이면 −1.
  int labelsBefore = -1;

  /// [lo] ~ [hi](배치 y) 안의 점선 조각들 — 조각마다 (위, 아래)(둥근 끝 빼고 · 길이 1). 미리보기 `stroke-dasharray: 1 3`처럼 처음부터 4마다.
  /// 끝이 정수 px라(사람 띠 아랫변 · 띠 윗변 모두 .5 자리) 마지막 조각이 잘리지 않는다 — 처음이 끝 이상이면 그 조각은 없다.
  Iterable<(double, double)> dashes({double lo = double.negativeInfinity, double hi = double.infinity}) sync* {
    const period = SphereThreadLook.dash + SphereThreadLook.gap, cap = SphereThreadLook.width / 2;
    var y = from;
    // 보이는 위끝보다 한참 위에서 떠나는 실(머리 단이 화면 위로 지나간 뒤)은 그 앞 조각들을 건너뛴다 — 차례(4마다)는 처음에서 센 그대로.
    final skip = lo - SphereThreadLook.dash - cap - y;
    if (skip > 0) y += (skip / period).floorToDouble() * period;
    for (; y < to && y - cap <= hi; y += period) {
      final end = math.min(y + SphereThreadLook.dash, to);
      if (end + cap < lo) continue;
      yield (y, end);
    }
  }

  @override
  String toString() => 'SphereThread(x $x · ${from.toStringAsFixed(1)} ~ ${to.toStringAsFixed(1)} · 띠 $band 칸 $cell · $person)';
}

/// 실 층의 작은 그림판: 점선 한 조각(굵기 1.2 · 길이 1 · 둥근 끝) · 점(반지름 1.5) · 뿔 칠 · 뿔 테를 흰색으로 한 번 그려 두고 찍을 때 색을 입힌다
/// (gutter.dart `GutterDots`와 같은 길). 조각마다 정수 자리에 찍으면 미리보기의 .5 자리 그림과 같은 픽셀에 앉는다.
class ThreadSprites {
  ThreadSprites._(this._image, this._scale);
  ui.Image _image;
  double _scale;

  static const _cell = 12.0;

  /// 조각(그림판 안 자리 · 크기)과 찍을 때 왼쪽 위에서 그림의 기준점까지(점선 = 조각 위끝 · 점 = 가운데 · 뿔 = 꼭짓점 아래 밑변 가운데).
  static const dash = ui.Rect.fromLTWH(0, 0, 3, 3), dot = ui.Rect.fromLTWH(_cell, 0, 3, 3);
  static const hornFill = ui.Rect.fromLTWH(_cell * 2, 0, 7, 7), hornEdge = ui.Rect.fromLTWH(_cell * 3, 0, 7, 7);

  /// 점선 조각의 기준(조각 위끝 · x 가운데) · 점의 가운데 · 뿔 밑변 가운데가 조각 왼쪽 위에서 얼마나.
  static const dashAt = ui.Offset(1.5, 1), dotAt = ui.Offset(1.5, 1.5), hornAt = ui.Offset(3.5, 5.5);

  static ThreadSprites? _shared;
  static ThreadSprites get shared => _shared ??= ThreadSprites._(_render(1), 1);

  double get scale => _scale;

  /// 멎은 돋보기 배율(× 화면의 px 비율)이 바뀌면 그 배율로 다시 뜬다(작아서 싸다).
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image.dispose();
    _image = _render(next);
    _scale = next;
  }

  /// 그림판 한 칸의 모양(그림판 단위 좌표의 점 하나가 안에 드는가) — 점선 조각(굵기 1.2 · 길이 1 · 둥근 끝 = 선분에서 .6 안) · 점(반지름 1.5) ·
  /// 뿔 칠(세 꼭짓점의 세모) · 뿔 테(세모의 세 변에서 .5 안 — 굵기 1 · 둥근 이음).
  static bool _inside(ui.Rect source, double x, double y) {
    if (source == dash) return _toSegment(x, y, dashAt.dx, dashAt.dy, dashAt.dx, dashAt.dy + SphereThreadLook.dash) <= SphereThreadLook.width / 2;
    if (source == dot) return math.sqrt(math.pow(x - dot.left - dotAt.dx, 2) + math.pow(y - dot.top - dotAt.dy, 2)) <= SphereThreadLook.dot;
    const b = SphereThreadLook.hornBase / 2, h = SphereThreadLook.horn;
    final cx = source.left + hornAt.dx, base = hornAt.dy;
    final (ax, ay, px, py, bx, by) = (cx - b, base, cx, base - h, cx + b, base);
    if (source == hornEdge) {
      final d = math.min(_toSegment(x, y, ax, ay, px, py), math.min(_toSegment(x, y, px, py, bx, by), _toSegment(x, y, bx, by, ax, ay)));
      return d <= SphereThreadLook.hornEdge / 2;
    }
    // 뿔 칠: 밑변 위 · 두 빗변 안.
    if (y > base) return false;
    final t = (base - y) / h; // 0 밑변 ~ 1 꼭짓점
    return t <= 1 && (x - cx).abs() <= b * (1 - t);
  }

  static double _toSegment(double x, double y, double x0, double y0, double x1, double y1) {
    final dx = x1 - x0, dy = y1 - y0, len = dx * dx + dy * dy;
    final t = len == 0 ? 0.0 : (((x - x0) * dx + (y - y0) * dy) / len).clamp(0.0, 1.0);
    final qx = x0 + t * dx - x, qy = y0 + t * dy - y;
    return math.sqrt(qx * qx + qy * qy);
  }

  /// 그림판을 뜬다. 모양을 길(Path)로 그리면 화면 그림판(GPU — Impeller)의 화면 밖 그림에서 가장자리 부드럽게(AA)가 빠져 점선 조각이 세 줄 꽉 찬 점이 된다
  /// (2026-10-25 실제 앱 그림에서 봄 — 검사의 소프트웨어 그림은 부드러웠다). 그래서 기기 px마다 덮는 몫을 8 × 8 표본으로 셈해 그 짙기의 1px 네모로 찍는다 —
  /// 그리는 쪽과 상관없이 같은 그림(정수 자리 네모라 가장자리 부드럽게가 필요 없다).
  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..isAntiAlias = false;
    const samples = 8;
    for (final source in const [dash, dot, hornFill, hornEdge]) {
      final x0 = (source.left * scale).floor(), x1 = (source.right * scale).ceil(), y0 = (source.top * scale).floor(), y1 = (source.bottom * scale).ceil();
      for (int py = y0; py < y1; py++) {
        for (int px = x0; px < x1; px++) {
          int hit = 0;
          for (int j = 0; j < samples; j++) {
            for (int i = 0; i < samples; i++) {
              if (_inside(source, (px + (i + .5) / samples) / scale, (py + (j + .5) / samples) / scale)) hit++;
            }
          }
          if (hit == 0) continue;
          paint.color = ui.Color.fromARGB((255 * hit / (samples * samples)).round(), 255, 255, 255);
          canvas.drawRect(ui.Rect.fromLTWH(px.toDouble(), py.toDouble(), 1, 1), paint);
        }
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_cell * 4 * scale).ceil(), (_cell * scale).ceil());
    picture.dispose();
    return image;
  }

  Float32List _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  Int32List _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 조각 [source]를 왼쪽 위 자리에 찍는다.
  void add(ui.Rect source, double left, double top, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = 1 / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = source.left * s;
    _rects[p + 1] = source.top * s;
    _rects[p + 2] = source.right * s;
    _rects[p + 3] = source.bottom * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }
}

/// 사람 띠의 실 · 뿔 매듭 층. 타일과 상관없이 장면마다 한 번 — 셈은 [beginFrame], 그리기는 [paint](뒤 판의 맨 앞).
class SphereThreadLayer extends TileLayer {
  /// 이번 장면에 그을 실(셈한 차례 = 문화권 → 사람 띠 → 왕관 차례 — 미리보기와 같은 차례).
  final threads = <SphereThread>[];

  final _sprites = ThreadSprites.shared;
  bool _done = false;
  final _seen = <(double, double)>{};

  /// 이번 장면에 찍은 점선 조각 수(겹친 자리는 하나 — 검사가 읽는다).
  int drawnDashes = 0;

  @override
  void setScale(double scale) => _sprites.setScale(scale);

  @override
  void beginFrame(PaintContext c) {
    threads.clear();
    _done = false;
    final layout = c.layout;
    // 조감에는 지도자 칸이 없다(미리보기 `!this._bird`) · 왕관 표를 기다리는 동안은 긋지 않는다.
    if (layout.bird || c.hide.contains('threads') || c.scene.crowns.pending) return;
    final crowns = c.scene.crowns;
    final v = c.v;
    final columns = PaintPick.route ? LinkColumns.of(c.scene) : const <LinkColumn>[];
    for (int k = 0; k < layout.spheres.length; k++) {
      final rows = layout.sphereRowsOf(k);
      if (rows.persons.isEmpty || layout.isSphereFolded(layout.spheres[k].id)) continue;
      // 사람 띠의 자리는 왼쪽 칸 층(gutter.dart `_sphereHead` → sphere_lines.dart)과 같은 셈 — 머리 단이 화면 밖이어도 실은 셈한다(미리보기도 긋는다).
      // 머리 단의 그린 자리([SceneLayout.sphereHeadBox]) — 붙은 머리 단(과제 3 걸음 4)이면 그림판 위에 붙은 사람 띠에서 떠난다.
      final box = layout.sphereHeadBox(k, v);
      if (box == null) continue;
      final y0 = box.top, y1 = y0 + box.height - 1;
      final top = y0 + G.sphereHead, bottom = y1 - 1;
      for (final p in rows.persons) {
        if (p.crowns.isEmpty) continue;
        final t = SphereLinesPaint.personTopOf(rows, p, top: top, bottom: bottom);
        if (t == null || SphereLinesPaint.personSpan(p, left: c.left, right: c.w - SphereLinesLook.rightPad, xOf: v.xOf) == null) continue;
        final dot = (t + G.spherePerson).roundToDouble() + .5;
        for (final crown in p.crowns) {
          final band = crowns.bandOf(crown.uid);
          if (band == null) continue;
          final at = targetOf(c, band, crown.cell);
          if (at == null || at.top <= dot + SphereThreadLook.horn + SphereThreadLook.near) continue;
          final x = columns.isEmpty ? at.x : dodge(at.x, dot + SphereThreadLook.start, at.top, at.right, columns);
          if (x != at.x) c.debug?.note('사람 실 비킴', '${at.x} → $x · 띠 ${band.id} 칸 ${crown.cell}');
          threads.add(SphereThread(x, dot, at.top, sphere: k, person: p.uid, band: band.id, cell: crown.cell));
        }
      }
    }
  }

  /// 실 비킴([SphereThreadLook.clear] · [SphereThreadLook.dodge]): 실의 세로 범위 [from] ~ [to](뿔 밑변)와 겹치는 세로 기둥이 [x]에서 3px 안이면
  /// 4px 오른쪽으로 — 옮긴 뿔이 칸 오른쪽 [right] 안에 들고 옮긴 자리도 기둥에서 3px 밖일 때만. 아니면 그대로.
  static double dodge(double x, double from, double to, double right, List<LinkColumn> columns) {
    bool near(double at) {
      for (final k in columns) {
        if ((k.x - at).abs() <= SphereThreadLook.clear && k.top < to && k.bottom > from) return true;
      }
      return false;
    }

    if (!near(x)) return x;
    final moved = x + SphereThreadLook.dodge;
    if (moved + SphereThreadLook.hornBase / 2 + SphereThreadLook.hornEdge / 2 > right || near(moved)) return x;
    return moved;
  }

  /// 왕관 하나가 닿는 자리 — 실의 x와 띠 윗변(+ .5) · 칸 오른쪽 끝(실 비킴이 칸 안에 머무는지 본다).
  /// 그 칸이 그려지지 않으면(줄이 안 보임 · 지도자 단 없음 · 빽빽한 칸 · 화면 밖 · 4px 아래) null.
  static ({double x, double top, double right})? targetOf(PaintContext c, CrownBand band, int seq) {
    final layout = c.layout, v = c.v;
    final row = band.row;
    // 접힌 트랙 · 접힌 문화권 · 꺼진 자료집 · 접힌 민족 줄은 띠가 없다(미리보기 `tr._sphereHidden || tr.folded`).
    if (row < 0 || row >= layout.rowCount || !layout.hasBody(row)) return null;
    final geo = layout.geo(row);
    if (geo.leaderTop < 0) return null; // 지도자 단이 없는 줄(표시 '지도자' 끔 · 지도자 칸 없는 트랙) — 칸이 그려지지 않는다
    final i = band.indexOf(seq);
    if (i < 0) return null;
    // 칸을 가두는 띠 상자(칸 층 `_paintGroup`): 띠 끝을 화면 ±1로 자르고 테 안 — 끝을 모르는 띠는 화면 끝까지.
    final bx0 = band.start == null ? double.negativeInfinity : v.xOf(band.start!), bx1 = band.end == null ? double.infinity : v.xOf(band.end!);
    final boxL = math.max(bx0, c.left - 1), boxR = math.max(boxL + 3, math.min(bx1, c.w + 1));
    final lo = boxL + 1, hi = boxR - 1;
    // 빽빽한 칸(칸 층 `_countLeaders` · is-dense): 화면 안 지도자 칸이 둘 넘고 칸 하나가 6px도 못 되면 낱칸이 없다.
    int count = 0;
    for (final cell in band.leaders) {
      if (v.xOf(cell.end) <= lo + SphereThreadLook.pad2 || v.xOf(cell.start) >= hi - SphereThreadLook.pad2) continue;
      count++;
    }
    if (count > 1 && (boxR - boxL - 2 - 2 * SphereThreadLook.pad2) / count < SphereThreadLook.dense) return null;
    final cell = band.leaders[i];
    final a = v.xOf(cell.start), b = v.xOf(cell.end);
    if (b <= lo || a >= hi) return null;
    // 이음과 .5 틈(layoutStrip): 앞 칸과 같은 무리(비트 2)에 픽셀로도 맞닿으면 틈 없음.
    final prev = i > 0 ? band.leaders[i - 1] : null, next = i + 1 < band.leaders.length ? band.leaders[i + 1] : null;
    final joinL = cell.joinLeft && prev != null && (v.xOf(prev.end) - a).abs() < 1.5;
    final joinR = next != null && next.joinLeft && (b - v.xOf(next.start)).abs() < 1.5;
    final l = a > lo ? a + (joinL ? 0 : .5) : lo, r = b < hi ? b - (joinR ? 0 : .5) : hi;
    if (r - l < SphereThreadLook.minCell) return null;
    final x = math.max(l, boxL).roundToDouble() + SphereThreadLook.inset;
    final top = v.yOf(layout.rowTop(row) + geo.bandTop).roundToDouble() + .5;
    return (x: x, top: top, right: r);
  }

  @override
  void paintTile(PaintContext c, Tile t) {}

  /// 뒤 판의 맨 앞에서 한 번(painter.dart): 점선 → (뿔 칠 · 뿔 테 · 점)을 실마다 — 미리보기 svg의 차례(실 길 하나 뒤에 매듭들).
  void paint(PaintContext c) {
    if (_done) return;
    _done = true;
    if (threads.isEmpty) return;
    // 실 50 · 뿔 테 45는 옛 값 — 그림판 먹 단계([CanvasInk] — 둘 다 45).
    final thread = CanvasInk.gray(SphereThreadLook.ink), edge = CanvasInk.gray(SphereThreadLook.hornInk);
    final lo = c.head - 2, hi = c.h + 2;
    // 점선 조각은 자리마다 한 번: 한 사람 띠에서 같은 칸 x로 떠나는 실 여럿(같은 사람이 같은 해에 여러 나라의 왕관 — f4-crowns의 1420년 셋)은
    // 갈 데까지 같은 조각을 지난다. 미리보기는 실 모두가 svg 길(path) 하나라 겹친 몫이 한 번만 칠해진다 — 조각을 겹쳐 찍으면 겹친 만큼 짙어진다.
    _seen.clear();
    drawnDashes = 0;
    for (final t in threads) {
      t.labelsBefore = c.debug?.labels.length ?? -1;
      for (final (y, _) in t.dashes(lo: lo, hi: hi)) {
        if (!_seen.add((t.x, y))) continue;
        _sprites.add(ThreadSprites.dash, t.x - ThreadSprites.dashAt.dx, y - ThreadSprites.dashAt.dy, thread);
        drawnDashes++;
      }
    }
    for (final t in threads) {
      if (t.knot >= lo - SphereThreadLook.horn && t.knot - SphereThreadLook.horn <= hi) {
        _sprites.add(ThreadSprites.hornFill, t.x - ThreadSprites.hornAt.dx, t.knot - ThreadSprites.hornAt.dy, Look.paper);
        _sprites.add(ThreadSprites.hornEdge, t.x - ThreadSprites.hornAt.dx, t.knot - ThreadSprites.hornAt.dy, edge);
      }
      if (t.dot >= lo && t.dot <= hi) _sprites.add(ThreadSprites.dot, t.x - ThreadSprites.dotAt.dx, t.dot - ThreadSprites.dotAt.dy, thread);
      c.stats.shapes++;
      c.debug?.note('사람 실', t);
    }
  }

  @override
  void flush(PaintContext c) => _sprites.flush(c.canvas);

  /// 실(점선 조각 · 뿔 · 점)과 글자 상자의 겹침 수 — 검사 · 진단이 센다(설계 4-6 #11 '글자가 가려지면 안 된다' · 서고 전수 점검 seogo-survey의 ④ 줄 걸림).
  /// [rects]는 글자 상자(배치 px), [lo] ~ [hi]는 보이는 세로 범위(그림판 몸통). 닿기만 한 것(겹친 폭 · 높이 0)은 세지 않는다.
  static int textHits(Iterable<SphereThread> threads, Iterable<ui.Rect> rects, {double lo = double.negativeInfinity, double hi = double.infinity}) {
    const cap = SphereThreadLook.width / 2, half = SphereThreadLook.hornBase / 2 + SphereThreadLook.hornEdge / 2;
    final boxes = rects.toList();
    int hits = 0;
    bool overlaps(ui.Rect a) => boxes.any((b) => math.min(a.right, b.right) > math.max(a.left, b.left) && math.min(a.bottom, b.bottom) > math.max(a.top, b.top));
    for (final t in threads) {
      for (final (y0, y1) in t.dashes(lo: lo, hi: hi)) {
        if (overlaps(ui.Rect.fromLTRB(t.x - cap, y0 - cap, t.x + cap, y1 + cap))) hits++;
      }
      if (overlaps(ui.Rect.fromLTRB(t.x - half, t.knot - SphereThreadLook.horn - .5, t.x + half, t.knot + .5))) hits++;
      if (overlaps(ui.Rect.fromLTRB(t.x - SphereThreadLook.dot, t.dot - SphereThreadLook.dot, t.x + SphereThreadLook.dot, t.dot + SphereThreadLook.dot))) hits++;
    }
    return hits;
  }
}
