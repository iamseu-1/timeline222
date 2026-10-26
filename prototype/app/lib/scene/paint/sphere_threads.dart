import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../layout.dart' show G;
import '../sphere_crowns.dart';
import '../tile.dart';
import 'bands.dart' show BandLayer;
import 'context.dart';
import 'grid.dart';
import 'ink.dart';
import 'links.dart' show LinkColumn, LinkColumns, LinkTagBoxes;
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
// 0.1.1(스위치 mend — route에서 뗌 · 끄면 위 미리보기 그대로): x는 이음 .5 틈을 빼기 전 칸 시작에서 반올림(조사 결함 36) · 세로로 겹치는 실끼리 2.5px 안이면 띠가 가까운
// 실부터 3px씩 나눔([SphereThreadLayer.spread] · 결함 35) · 실 자리에 받침 카드 윗단만 깔렸으면 뿔을 카드 윗변으로(결함 37 카드 몫) · 조감은 띠 단위로 닿는
// 가는 실([SphereThreadLayer.birdTargetOf] · 결함 47) · 실과 같은 자리의 연도 세로줄은 실 밑에서 걷는다(이어 주는 선 미룸 1). 머리 단 상자에 덮이는 몫은
// 왼쪽 칸 층(gutter.dart `_threadsOver` — 결함 38 · 39)이 상자 위에 다시 찍는다.

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

  /// 실 나눔(0.1.1 · 조사 결함 35 · 스위치 mend): 세로로 겹치는 실끼리 x가 [spreadNear] 안이면(같은 해에 시작하는 왕관 칸 — 같은 사람도)
  /// 닿는 띠가 가까운 실부터 제자리, 다음 실은 [spread]씩 오른쪽으로 — 띠 윗변마다 제 기둥 하나만 뿔에서 끝나게.
  static const spreadNear = 2.5, spread = 3.0;

  /// 조감의 실 굵기(0.1.1 · 조사 결함 47 — 조감에는 지도자 칸이 없어 실이 띠 단위로 닿는다) · 띠 끝에서 뿔을 들이는 몫(반 밑변 2.5 + 테 .5).
  static const birdWidth = .6, birdInset = 3.0;
}

/// 이번 장면에 그을 실 하나(배치 px).
class SphereThread {
  SphereThread(this.x, this.dot, this.knot, {required this.sphere, required this.person, required this.band, required this.cell, this.thin = false});

  /// 실의 x(.5 자리) · 사람 띠 아랫변의 점 y(아랫변 + .5) · 뿔 매듭 밑변 y(띠 윗변 + .5 — 그 자리에 받침 카드가 깔렸으면 카드 윗변 + .5).
  final double x, dot, knot;

  /// 조감의 가는 실(굵기 [SphereThreadLook.birdWidth] — 조사 결함 47).
  final bool thin;

  /// x · 뿔 밑변만 바꾼 사본(실 나눔 · 카드 윗변 — 0.1.1).
  SphereThread moved({double? x, double? knot}) =>
      SphereThread(x ?? this.x, dot, knot ?? this.knot, sphere: sphere, person: person, band: band, cell: cell, thin: thin);

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

  /// 조감의 가는 점선 조각(굵기 [SphereThreadLook.birdWidth] · 0.1.1 조사 결함 47) — 기준은 [dash]와 같은 [dashAt].
  static const thinDash = ui.Rect.fromLTWH(_cell * 4, 0, 3, 3);

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
    if (source == thinDash) {
      return _toSegment(x - thinDash.left, y, dashAt.dx, dashAt.dy, dashAt.dx, dashAt.dy + SphereThreadLook.dash) <= SphereThreadLook.birdWidth / 2;
    }
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
    for (final source in const [dash, dot, hornFill, hornEdge, thinDash]) {
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
    final image = picture.toImageSync((_cell * 5 * scale).ceil(), (_cell * scale).ceil());
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

  /// 띠 층 — 띠 윗변 위 탭의 자리를 묻는다([BandLayer.hostTabSpans] · 그리개가 잇는다). 띠 층의 beginFrame이 먼저다(painter.dart `_tileLayers`).
  BandLayer? bands;

  /// 바탕 눈금 층 — 이번 장면에 그은 연도 세로줄의 열([GridLayer.columns] · 그리개가 잇는다). 실과 겹치는 세로줄을 실 밑에서 걷는다(0.1.1).
  GridLayer? grid;
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
    // 조감에는 지도자 칸이 없다(미리보기 `!this._bird`) — 스위치 mend면 실이 띠 단위로 닿는다([birdTargetOf] · 0.1.1 조사 결함 47).
    // 왕관 표를 기다리는 동안은 긋지 않는다.
    final mend = PaintPick.mend;
    if ((layout.bird && !mend) || c.hide.contains('threads') || c.scene.crowns.pending) return;
    final bird = layout.bird;
    final crowns = c.scene.crowns;
    final v = c.v;
    final columns = PaintPick.route ? LinkColumns.of(c.scene) : const <LinkColumn>[];
    // 실 나눔 · 카드 윗변(0.1.1)이 실마다 읽는 것: 칸 오른쪽 · 띠 윗변 위 탭 · 줄.
    final rights = <double>[], tabsOf = <List<(double, double)>>[], rowsOf = <int>[];
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
          final at = bird ? birdTargetOf(c, band, crown.cell) : targetOf(c, band, crown.cell);
          if (at == null || at.top <= dot + SphereThreadLook.horn + SphereThreadLook.near) continue;
          var x = columns.isEmpty ? at.x : dodge(at.x, dot + SphereThreadLook.start, at.top, at.right, columns);
          if (x != at.x) c.debug?.note('사람 실 비킴', '${at.x} → $x · 띠 ${band.id} 칸 ${crown.cell}');
          // 그 띠 윗변 위의 상국 탭 · 연합 겹 탭(앞 판이라 실 · 뿔을 덮는다)을 비킨다(조사 결함 37 탭 몫).
          final tabs = bands?.hostTabSpans(c, band.id) ?? const <(double, double)>[];
          if (tabs.isNotEmpty) {
            final moved = dodgeTabs(x, at.left, at.right, tabs, dot + SphereThreadLook.start, at.top, columns);
            if (moved != x) c.debug?.note('사람 실 탭 비킴', '$x → $moved · 띠 ${band.id} 칸 ${crown.cell}');
            x = moved;
          }
          threads.add(SphereThread(x, dot, at.top, sphere: k, person: p.uid, band: band.id, cell: crown.cell, thin: bird));
          rights.add(at.right);
          tabsOf.add(tabs);
          rowsOf.add(band.row);
        }
      }
    }
    if (!mend || threads.isEmpty) return;
    // 나눔은 승계선 세로 기둥을 늘 본다(route를 꺼도 — 옛 길의 기둥에 실을 옮겨 얹지 않게 · 켜면 [columns]와 같다).
    spread(threads, rights, tabsOf, LinkColumns.of(c.scene));
    // 뿔이 받침 카드에 덮이지 않게(0.1.1 · 조사 결함 37 카드 몫): 실 자리에 구역 47 관계의 받침 카드 윗단만 깔렸으면(탭 자리 아님 —
    // [BandLayer.overTop] 1) 뿔 밑변을 카드 윗변(띠 윗변 − [BandLayer.sheetRise])으로 올린다 — 실이 카드 윗변(상국 쪽)이 아니라 띠 쪽에 닿게.
    final layer = bands;
    if (layer == null || bird) return;
    for (final i in raiseOnCards(threads, rowsOf, (band, row, x, half) => layer.overTop(c, band, row, x, half))) {
      c.debug?.note('사람 실 카드', '띠 ${threads[i].band} 칸 ${threads[i].cell} · 뿔 ${threads[i].knot}');
    }
  }

  /// 카드 윗변(0.1.1 · 조사 결함 37 카드 몫): 실 자리의 띠 윗변 위가 받침 카드의 드러난 윗단뿐이면([overTop] 1 — [BandLayer.overTop]) 뿔 밑변을
  /// [BandLayer.sheetRise]만큼 올린다(사람 띠에 너무 가까워지면 그대로). 올린 실의 차례 번호를 돌려준다.
  static List<int> raiseOnCards(List<SphereThread> list, List<int> rows, int Function(int band, int row, double x, double half) overTop) {
    const half = SphereThreadLook.hornBase / 2 + SphereThreadLook.hornEdge / 2;
    final out = <int>[];
    for (int i = 0; i < list.length; i++) {
      final t = list[i];
      if (overTop(t.band, rows[i], t.x, half) != 1) continue;
      final knot = t.knot - BandLayer.sheetRise;
      if (knot <= t.dot + SphereThreadLook.horn + SphereThreadLook.near) continue;
      list[i] = t.moved(knot: knot);
      out.add(i);
    }
    return out;
  }

  /// 실 나눔(0.1.1 · 조사 결함 35 · [SphereThreadLook.spreadNear] · [SphereThreadLook.spread]): 세로 범위가 겹치는 실끼리 x가 2.5px 안이면
  /// 닿는 띠가 가까운(뿔이 높은) 실부터 제자리에 두고, 뒤 실은 3px씩 오른쪽으로 — 옮긴 뿔(반 밑변 2.5 + 테 .5)이 제 칸 오른쪽 [rights] 안에 들고
  /// 그 띠의 탭 [tabs] · 승계선 세로 기둥 [columns]에서도 비었을 때만(안 되면 그대로 — 예전처럼 포갠다). 같은 사람의 실도 나눈다.
  static void spread(List<SphereThread> list, List<double> rights, List<List<(double, double)>> tabs, List<LinkColumn> columns) {
    const half = SphereThreadLook.hornBase / 2 + SphereThreadLook.hornEdge / 2;
    final order = List<int>.generate(list.length, (i) => i)..sort((a, b) => list[a].knot != list[b].knot ? list[a].knot.compareTo(list[b].knot) : a - b);
    final placed = <SphereThread>[];
    for (final i in order) {
      final t = list[i];
      bool clash(double x) => placed.any((p) => (p.x - x).abs() <= SphereThreadLook.spreadNear && p.dot < t.knot && p.knot > t.dot);
      if (clash(t.x)) {
        bool free(double x) =>
            !clash(x) &&
            !tabs[i].any((s) => x > s.$1 - SphereThreadLook.clear && x < s.$2 + SphereThreadLook.clear) &&
            !columns.any((k) => (k.x - x).abs() <= SphereThreadLook.clear && k.top < t.knot && k.bottom > t.from);
        for (var x = t.x + SphereThreadLook.spread; x + half <= rights[i]; x += SphereThreadLook.spread) {
          if (!free(x)) continue;
          list[i] = list[i].moved(x: x);
          break;
        }
      }
      placed.add(list[i]);
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

  /// 탭 비킴(조사 결함 37 탭 몫): 실 [x](.5 자리)가 띠 윗변 위의 탭 구간 [tabs]([BandLayer.hostTabSpans]) 하나에서 [SphereThreadLook.clear] 안이면
  /// 그 탭 밖 [SphereThreadLook.dodge]로 — 오른쪽 · 왼쪽 가운데 가까운 쪽이고, 옮긴 뿔(반 밑변 2.5 + 테 .5)이 칸 [left] ~ [right] 안에 들며
  /// 다른 탭 · 승계선 세로 기둥([columns] — 실의 세로 범위 [from] ~ [to]와 겹치는 것)에서도 비었을 때만. 아니면 그대로(탭이 덮는다).
  static double dodgeTabs(double x, double left, double right, List<(double, double)> tabs, double from, double to, List<LinkColumn> columns) {
    const clear = SphereThreadLook.clear, half = SphereThreadLook.hornBase / 2 + SphereThreadLook.hornEdge / 2;
    bool inTab(double at) => tabs.any((s) => at > s.$1 - clear && at < s.$2 + clear);
    bool nearColumn(double at) => columns.any((k) => (k.x - at).abs() <= clear && k.top < to && k.bottom > from);
    (double, double)? hit;
    for (final s in tabs) {
      if (x > s.$1 - clear && x < s.$2 + clear) hit = s;
    }
    if (hit == null) return x;
    final r = (hit.$2 + SphereThreadLook.dodge - .5).ceilToDouble() + .5, l = (hit.$1 - SphereThreadLook.dodge + .5).floorToDouble() - .5;
    bool ok(double at) => at - half >= left && at + half <= right && !inTab(at) && !nearColumn(at);
    final order = (r - x) <= (x - l) ? [r, l] : [l, r];
    for (final at in order) {
      if (ok(at)) return at;
    }
    return x;
  }

  /// 왕관 하나가 닿는 자리 — 실의 x와 띠 윗변(+ .5) · 칸 왼쪽 · 오른쪽 끝(실 비킴이 칸 안에 머무는지 본다).
  /// 그 칸이 그려지지 않으면(줄이 안 보임 · 지도자 단 없음 · 빽빽한 칸 · 화면 밖 · 4px 아래) null.
  static ({double x, double top, double left, double right})? targetOf(PaintContext c, CrownBand band, int seq) {
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
    // 스위치 mend(0.1.1 · 조사 결함 36): x는 칸 시작 a(이음 .5 틈을 빼기 전)에서 반올림 — 띠마다 이음 여부가 달라 같은 해의 두 실이 1px 어긋나
    // 굵은 점선 한 줄로 보였다. 같은 해는 같은 x가 되고, 나눔([spread])이 3px씩 가른다.
    final x = math.max(PaintPick.mend ? (a > lo ? a : lo) : l, boxL).roundToDouble() + SphereThreadLook.inset;
    final top = v.yOf(layout.rowTop(row) + geo.bandTop).roundToDouble() + .5;
    return (x: x, top: top, left: math.max(l, boxL), right: r);
  }

  /// 조감에서 왕관 하나가 닿는 자리(0.1.1 · 조사 결함 47 · 스위치 mend): 조감에는 지도자 칸이 없으므로 띠 단위로 닿는다 —
  /// x = 왕관 칸의 시작 해(띠 상자 안 [SphereThreadLook.birdInset]으로 자름 · .5 자리) · 윗변 = 띠 윗변(+ .5). 칸이 띠 · 화면 밖이거나 띠가 너무 좁으면 null.
  static ({double x, double top, double left, double right})? birdTargetOf(PaintContext c, CrownBand band, int seq) {
    final layout = c.layout, v = c.v;
    final row = band.row;
    if (row < 0 || row >= layout.rowCount || !layout.hasBody(row)) return null;
    final i = band.indexOf(seq);
    if (i < 0) return null;
    final bx0 = band.start == null ? double.negativeInfinity : v.xOf(band.start!), bx1 = band.end == null ? double.infinity : v.xOf(band.end!);
    final boxL = math.max(bx0, c.left - 1), boxR = math.min(bx1, c.w + 1);
    final lo = boxL + SphereThreadLook.birdInset, hi = boxR - SphereThreadLook.birdInset;
    if (hi < lo) return null;
    final cell = band.leaders[i];
    final a = v.xOf(cell.start), b = v.xOf(cell.end);
    if (b <= boxL || a >= boxR) return null;
    final x = a.clamp(lo, hi).floorToDouble() + .5;
    final top = v.yOf(layout.rowTop(row) + layout.geo(row).bandTop).roundToDouble() + .5;
    return (x: x, top: top, left: boxL, right: boxR);
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
    // 연도 세로줄과 같은 자리(0.1.1 · 이어 주는 선 미룸 1 — 스위치 mend): 실 획이 덮거나 맞닿는 세로줄 열은 실이 지나는 몫만 그 자리 바탕색 종이로 걷는다 —
    // 같은 점선 꼴이 포개져 한 줄로 읽히지 않게(세로줄은 맨 아래 한 번 긋고 그 위에 얹는 것이라, 실 밑에 종이를 한 장 더 얹는 셈이다).
    // 짝 꼬리표(띠 밖 글 — 구역 60) 자리는 실이 비운다(스위치 mend · 0.1.1 검토: 조감 가는 실이 '→' 위를 지났다) — 점선 조각도 세로줄 걷기도 그 몫은 없다.
    final tags = PaintPick.mend ? LinkTagBoxes.of(c.scene) : const <ui.Rect>[];
    if (PaintPick.mend) maskGrid(c, threads, grid?.columns ?? const [], tags);
    for (final t in threads) {
      t.labelsBefore = c.debug?.labels.length ?? -1;
      final piece = t.thin ? ThreadSprites.thinDash : ThreadSprites.dash;
      final cut = tagsOn(t, tags);
      for (final (y, end) in t.dashes(lo: lo, hi: hi)) {
        if (cut.any((r) => end + tagPad > r.top && y - tagPad < r.bottom)) continue;
        if (!_seen.add((t.x, y))) continue;
        _sprites.add(piece, t.x - ThreadSprites.dashAt.dx, y - ThreadSprites.dashAt.dy, thread);
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

  /// 실과 같은 자리의 연도 세로줄 걷기(0.1.1 · [paint]): 실 획(굵기 1.2 · 조감 .6)이 덮거나 1px 안에 맞닿는 세로줄 열([GridLayer.columns])마다
  /// 실의 점선 범위(보이는 몸통 안)를 그 자리 바탕색 종이(1px 폭)로 덮는다. 종이는 이 걸음의 네모라 실 조각(층의 그림판)보다 먼저 나간다.
  static void maskGrid(PaintContext c, List<SphereThread> threads, List<double> columns, [List<ui.Rect> tags = const []]) {
    if (columns.isEmpty) return;
    for (final t in threads) {
      final half = (t.thin ? SphereThreadLook.birdWidth : SphereThreadLook.width) / 2;
      final top = math.max(t.from, c.head), bottom = math.min(t.to, c.h);
      if (bottom <= top) continue;
      // 짝 꼬리표 자리는 실이 비우므로 세로줄도 그대로 둔다(걷으면 그 몫에 틈이 난다).
      final spans = <(double, double)>[(top, bottom)];
      for (final r in tagsOn(t, tags)) {
        final a = r.top - tagPad, z = r.bottom + tagPad;
        final next = <(double, double)>[];
        for (final (s, e) in spans) {
          if (z <= s || a >= e) {
            next.add((s, e));
            continue;
          }
          if (a > s) next.add((s, a));
          if (z < e) next.add((z, e));
        }
        spans
          ..clear()
          ..addAll(next);
      }
      for (final l in GridLayer.touching(columns, t.x, half)) {
        for (final (top, bottom) in spans) {
          c.grounds.paper(c.quads, l, top, l + 1, bottom);
          c.debug?.note('세로줄 걷기', '실 ${t.x} · 열 $l · ${top.toStringAsFixed(1)} ~ ${bottom.toStringAsFixed(1)}');
        }
      }
    }
  }

  /// 짝 꼬리표 자리와 실 사이 틈(px).
  static const tagPad = 1.0;

  /// 실 [t]의 획(굵기 반 + [tagPad])이 가로로 닿는 짝 꼬리표 자리.
  static List<ui.Rect> tagsOn(SphereThread t, List<ui.Rect> tags) {
    if (tags.isEmpty) return const [];
    final half = (t.thin ? SphereThreadLook.birdWidth : SphereThreadLook.width) / 2 + tagPad;
    return [for (final r in tags) if (t.x + half > r.left && t.x - half < r.right) r];
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
