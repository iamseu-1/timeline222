import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../layout.dart';
import '../marks.dart';
import '../tile.dart';
import 'bands.dart' show BandLayer;
import 'context.dart';
import 'events.dart' show EventLayer;
import 'ink.dart';
import 'look.dart';
import 'paint_pick.dart';
import 'strips.dart';

// 동군연합 이음줄(건의 8의 6-다 · 2026-10-14 감독 "이음줄 진행" · 고른 안 A · 늘 옅게):
// 같은 사람이 같은 때 두 나라의 지도자이면 겹친 기간의 가운데 해에서 두 지도자 칸을 세로로 꿰는 줄(먹 60% · 1.5px)과
// 두 끝의 작은 고리(지름 7 · 종이빛 채움 · 먹 1.5px 테). 평소 짙기 .5 · 줄에 올리거나 두 나라 · 두 칸 가운데 하나를 고르거나 올리면 1.
// 두 나라의 줄 사이(다른 줄 · 트랙 사이)는 승계선처럼 띠 뒤로 지나고([paintBack]), 두 나라의 띠 안의 몫과 고리는 띠 위([paintFront]).
// 한쪽 칸이 화면 밖이거나 그려지지 않으면 줄은 긋지 않고 보이는 칸의 이름 앞에 겹고리 표지(판의 B 꼴) — 칸이 좁아 이름과 부딪히면 표지도 없다.
//
// 자료는 내보내기 구역 49(끝마다 하나 · 짝은 text2의 열쇠 — prototype/scripts/export/links.mjs · 계약 6-10절). 끝 하나는 겹친 기간의 가운데에서 시작해
// 겹친 길이만큼 이어지고(길이로 단계가 잡힌다) 줄은 그 **잘리지 않은 왼쪽 끝**(가운데)에 긋는다. 가운데가 타일 밖이면(화면 왼쪽 밖) 그 끝은 받지 않는다.
// a = 이 끝의 지도자 칸 순번 · b = 짝 띠의 번호 · c = 짝의 지도자 칸 순번 · name = 풍선 글. 칸이 실제로 그려졌는지는 타일의 칸(칸 종류 1 · 순번)으로 본다.
// 선 몇 개뿐이라 묶음 대신 캔버스에 바로 긋는다 — 그래서 걸음 하나의 '한 번'(once)에서 그린다(앞서 모은 묶음이 먼저 나간 뒤).
// 사람 띠로 그린 사람(리메이크 4단계 과제 4 걸음 4 · 계획 정한 것 #7 · 미리보기 timeline.js 8902줄)은 실 · 뿔 매듭(sphere_threads.dart)이 칸을 잇는다 —
// 끝 하나라도 왕관 칸(장면 곁 왕관 표의 띠 번호 · 지도자 순번)인 짝은 줄도 겹고리 표지도 없다(두 벌이 엇갈리지 않게). 사람 띠가 없는 저장소는 그대로다.
// 0.1.1(스위치 route — 조사 결함 41): 띠 안 몫이 사건 이름 위를 곧게 지나 글자를 가로질렀다 — 이번 장면에 그린 사건 이름의 상자([EventLayer.nameBoxes])를
// 지나는 몫은 비워 이름이 줄 위에 얹힌 것처럼 둔다(이름 자리는 그대로 — 비켜 갈 구간으로 밀면 글줄이 하나인 판 3 줄에서 이름이 통째로 빠졌다).
// 칸 이름 · 사슬 글은 그대로.

/// 이 층의 값.
abstract final class UnionLook {
  /// 줄: 먹 60% · 1.5px · 평소 짙기 .5(올리거나 고르면 1).
  static const ink = .6, width = 1.5, rest = .5;

  /// 끝의 고리: 지름 7 · 테 1.5px(먹 — 그림판 먹 단계 85 · 줄의 먹 60은 그대로). 겹고리 표지는 같은 고리 둘을 5px 어긋나게(폭 12) · 이름에서 2px 앞 · 칸 왼쪽 안 3px 안쪽에만.
  static const ring = 3.5, ringEdge = 1.5, pairGap = 5.0, markGap = 2.0, markInset = 3.0;

  /// 지도자 칸의 단(칸 종류 1).
  static const leaderKind = 1;

  /// 띠 안 몫이 사건 이름 상자를 지나는 자리에서 비우는 둘레(0.1.1 · 조사 결함 41 — 이름 상자의 위아래 · 좌우 1px).
  static const nameClear = 1.0;
}

/// 구역 49의 끝 하나(장면마다).
class _End {
  _End(this.key, this.row, this.band, this.leader, this.partner, this.partnerLeader, this.tip);
  final String key, tip;
  final int row, band, leader, partner, partnerLeader;
  double x = 0;

  String get ref => 'leader:$leader';
}

/// 이번 장면에 그을 줄 하나.
class _Line {
  _Line(this.top, this.bottom, this.x, this.alpha, this.tip);

  /// 위 끝 · 아래 끝(위 칸의 아랫변 · 아래 칸의 윗변 — 위가 늘 [top]).
  final _End top, bottom;
  final double x, alpha;
  final String tip;

  /// 세로 자리: 위 칸 아랫변 · 위 띠 아랫변 · 아래 띠 윗변 · 아래 칸 윗변.
  double y0 = 0, y1 = 0, y2 = 0, y3 = 0;
}

class UnionLayer extends TileLayer {
  static const section = 49;

  /// 칸 층 — 표지가 이름 앞에 붙으므로 이름 자리를 묻는다(그리개가 이어 준다).
  StripLayer? strips;

  /// 사건 층 — 이번 장면에 그린 사건 이름의 상자([EventLayer.nameBoxes])를 띠 안 몫이 비운다(0.1.1 · 조사 결함 41 · 그리개가 이어 준다).
  /// 사건 층이 먼저 그린다(그리개 — 사건 → 표식 판의 이음줄 띠 안 몫).
  EventLayer? events;

  /// 밝기 상태(고른 것 · 같은 사람의 칸).
  em.Emphasis? emphasis;

  final _ends = <String, List<_End>>{};
  final _lines = <_Line>[];
  final _marks = <(_End, double)>[];
  bool _backDone = false, _frontDone = false;

  /// 맞히기: 줄의 자리(배치 px)와 두 띠 · 풍선 글.
  final _hits = <(ui.Rect, int, int, String)>[];

  /// 검사가 읽는 기록 — 이번 장면에 그은 줄(x · 위 · 아래 · 짙기)과 단 표지(띠 · 칸 · x).
  final debugLines = <(double, double, double, double)>[];
  final debugMarks = <(int, String, double)>[];

  final _linePaint = ui.Paint()
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.butt;
  final _fill = ui.Paint()..isAntiAlias = true;

  @override
  void beginFrame(PaintContext c) {
    _ends.clear();
    _lines.clear();
    _marks.clear();
    _hits.clear();
    debugLines.clear();
    debugMarks.clear();
    _backDone = false;
    _frontDone = false;
    final layout = c.layout;
    // 조감에는 지도자 칸이 없다 · 관계선을 숨긴 화면(검사)에서도 뺀다.
    if (layout.bird || c.hide.contains('links')) return;
    // 왕관 표를 기다리는 동안은 쉰다 — 걷힐 줄이 한 장면 비쳤다 사라지지 않게(사람 띠가 없는 저장소는 기다리지 않는다).
    final crowns = c.scene.crowns;
    if (crowns.pending) return;
    final crown = crowns.cells;
    final v = c.v;
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      final s = t.section(section);
      if (s.count == 0) continue;
      final origin = t.origin.toDouble();
      final x0 = s.f(Tile.itemX0), id = s.u(Tile.itemId), row = s.u(Tile.itemRow), flags = s.u(Tile.itemFlags);
      final ref = s.u(Tile.itemRef), name = s.u(Tile.itemName), text2 = s.u(Tile.itemText2);
      final a = s.u(Tile.itemA), b = s.u(Tile.itemB), cc = s.u(Tile.itemC);
      for (int i = 0; i < s.count; i++) {
        // 왼쪽 끝(= 겹친 기간의 가운데)을 든 조각만 — 타일 경계에서 잘린 조각은 다른 타일의 조각이 맡는다.
        if (flags[i] & Tile.clipLeft != 0 || !seen.add(id[i])) continue;
        final r = row[i];
        if (r >= layout.rowCount || !layout.hasBody(r)) continue;
        // 이 끝(띠 · 지도자 순번)이나 짝(띠 · 지도자 순번)이 왕관 칸이면 이 짝은 사람 띠의 실이 맡는다.
        if (crown.isNotEmpty && (crown.contains((ref[i], a[i])) || crown.contains((b[i], cc[i])))) continue;
        final end = _End(t.text(text2[i]), r, ref[i], a[i], b[i], cc[i], t.text(name[i]))..x = v.xOf(origin + x0[i]);
        (_ends[end.key] ??= []).add(end);
      }
    }
    if (_ends.isEmpty) return;
    final marks = SceneMarks.of(c.scene);
    final look = emphasis?.look;
    for (final pair in _ends.values) {
      // 끝마다 그 칸이 이번 장면에 실렸는가(타일의 지도자 칸 · 그 순번 · 그 x를 품음)와 화면 안의 세로 자리.
      final shown = [for (final e in pair) if (_cellAt(c, e)) e];
      if (shown.isEmpty) continue;
      final both = pair.length == 2 && shown.length == 2;
      final e0 = pair.first;
      final x = e0.x;
      if (both && x >= c.left && x <= c.w) {
        final up = _top(c, pair[0]) <= _top(c, pair[1]) ? pair[0] : pair[1];
        final down = identical(up, pair[0]) ? pair[1] : pair[0];
        final geoUp = layout.geo(up.row), geoDown = layout.geo(down.row);
        // 두 장 꼬리표: 지도자 단 · 몸통 아랫변은 그 띠의 맞붙인 자리(bands.dart BandLayer.floorYOf · bodyBottomOf).
        // 두 단 띠(정통성 넷 가 다듬은 꼴 — 칸 그림 갈래 걸음 2)의 칸은 그 자리의 조각대로(혼자면 층 전체 · 겹쳤으면 제 단 — StripLayer.leaderSlotAt).
        final bands = BandLayer.of(c.scene);
        final slotUp = strips?.leaderSlotAt(c, up.row, up.band, up.leader, x), slotDown = strips?.leaderSlotAt(c, down.row, down.band, down.leader, x);
        final y0 = slotUp?.$2 ?? v.yOf(layout.rowTop(up.row) + (bands?.floorYOf(layout, up.row, up.band, geoUp.leaderTop) ?? geoUp.leaderTop) + G.leader);
        final y3 = slotDown?.$1 ?? v.yOf(layout.rowTop(down.row) + (bands?.floorYOf(layout, down.row, down.band, geoDown.leaderTop) ?? geoDown.leaderTop));
        // 두 칸이 다 화면 안에 있어야 줄을 긋는다(한쪽이 밖이면 표지로).
        if (y0 > c.head && y0 <= c.h && y3 >= c.head && y3 < c.h && y3 > y0) {
          final hot = _hot(marks, look, up, down);
          final line = _Line(up, down, x, hot ? 1 : UnionLook.rest, e0.tip)
            ..y0 = y0
            ..y1 = v.yOf(layout.rowTop(up.row) + (bands?.bodyBottomOf(layout, up.row, up.band) ?? geoUp.bandTop + geoUp.bandHeight))
            ..y2 = v.yOf(layout.rowTop(down.row) + geoDown.bandTop)
            ..y3 = y3;
          _lines.add(line);
          _hits.add((ui.Rect.fromLTRB(x - 3, y0 - UnionLook.ring, x + 3, y3 + UnionLook.ring), up.band, down.band, e0.tip));
          continue;
        }
      }
      for (final e in shown) {
        final hot = _hot(marks, look, e, pair.length == 2 ? (identical(e, pair[0]) ? pair[1] : pair[0]) : e);
        _marks.add((e, hot ? 1 : UnionLook.rest));
      }
    }
  }

  /// 이 끝의 지도자 칸이 이번 장면의 타일에 실려 있고 그 줄이 보이며 지도자 단이 있는가.
  bool _cellAt(PaintContext c, _End e) {
    final layout = c.layout;
    if (!layout.isVisible(e.row)) return false;
    final geo = layout.geo(e.row);
    if (geo.leaderTop < 0) return false;
    final v = c.v;
    for (final d in c.scene.draw) {
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.cellCount; i++) {
        if (t.cellRow[i] != e.row || t.cellKindOf(i) != UnionLook.leaderKind) continue;
        if (CellStyle.seqOf(t.cellStyle[i]) != e.leader) continue;
        final l = v.xOf(origin + t.cellX0[i]), r = v.xOf(origin + t.cellX1[i]);
        if (e.x >= l - .5 && e.x <= r + .5) return true;
      }
    }
    return false;
  }

  double _top(PaintContext c, _End e) => c.layout.rowTop(e.row);

  /// 짙게 할 때: 줄에 올림 · 두 나라 가운데 하나를 고름 · 두 칸 가운데 하나에 올림 · 같은 사람의 칸으로 고름.
  bool _hot(SceneMarks marks, em.Look? look, _End a, _End b) {
    final link = marks.hotLink;
    if (link != null && ((link.$1 == a.band && link.$2 == b.band) || (link.$1 == b.band && link.$2 == a.band))) return true;
    if (look != null && (look.band == a.band || look.band == b.band)) return true;
    if (look != null && (look.isTwin(a.band, a.ref) || look.isTwin(b.band, b.ref))) return true;
    final cell = marks.hotCell;
    if (cell != null && (cell == '${a.band}|${a.ref}' || cell == '${b.band}|${b.ref}')) return true;
    return false;
  }

  @override
  void paintTile(PaintContext c, Tile t) {}

  /// 띠 뒤(관계선 층의 띠 뒤 선과 같은 판): 두 나라 띠 사이의 몫.
  void paintBack(PaintContext c) {
    if (_backDone) return;
    _backDone = true;
    for (final l in _lines) {
      if (l.y2 > l.y1) _stroke(c.canvas, l.x, l.y1, l.y2, l.alpha);
    }
  }

  /// 띠 위(칸 · 띠 테두리 뒤): 두 나라 띠 안의 몫 · 끝의 고리 · 겹고리 표지.
  void paintFront(PaintContext c) {
    if (_frontDone) return;
    _frontDone = true;
    final canvas = c.canvas;
    final boxes = PaintPick.mend ? (events?.nameBoxes ?? const <ui.Rect>[]) : const <ui.Rect>[];
    for (final l in _lines) {
      // 위 칸 아랫변 → 위 띠 아랫변, 아래 띠 윗변 → 아래 칸 윗변(두 띠가 이어 붙으면 한 줄로 다 띠 위).
      // 스위치 mend(0.1.1 · 조사 결함 41 — route에서 뗌): 사건 이름 상자를 지나는 몫은 비운다([_open]).
      if (l.y2 <= l.y1) {
        _open(canvas, l.x, l.y0, l.y3, l.alpha, boxes, c);
      } else {
        _open(canvas, l.x, l.y0, l.y1, l.alpha, boxes, c);
        _open(canvas, l.x, l.y2, l.y3, l.alpha, boxes, c);
      }
      _ring(canvas, l.x, l.y0, l.alpha);
      _ring(canvas, l.x, l.y3, l.alpha);
      debugLines.add((l.x, l.y0, l.y3, l.alpha));
      c.debug?.note('동군연합', '줄 ${l.top.band}|${l.top.ref} ↔ ${l.bottom.band}|${l.bottom.ref} x=${l.x.toStringAsFixed(1)} ${l.y0.toStringAsFixed(1)}~${l.y3.toStringAsFixed(1)} ${l.alpha}');
    }
    final strip = strips;
    if (strip == null) return;
    for (final (e, alpha) in _marks) {
      final cell = strip.drawnCell(e.band, e.ref);
      if (cell == null || cell.textW <= 0) continue;
      // 고리 둘(5px 어긋남 · 폭 12)을 이름 2px 앞에 — 칸 왼쪽 안 3px보다 밖으로 나가면(이름과 부딪힘) 달지 않는다.
      final right = cell.textL - UnionLook.markGap;
      final left = right - (UnionLook.pairGap + 2 * UnionLook.ring);
      if (left < cell.l + UnionLook.markInset) continue;
      final cy = (cell.t + cell.b) / 2;
      _ring(canvas, left + UnionLook.ring, cy, alpha, fill: false);
      _ring(canvas, left + UnionLook.ring + UnionLook.pairGap, cy, alpha, fill: false);
      debugMarks.add((e.band, e.ref, left));
      c.debug?.note('동군연합', '표지 ${e.band}|${e.ref} x=${left.toStringAsFixed(1)} $alpha');
    }
  }

  /// 띠 안 몫 하나를 긋되, 이번 장면에 그린 사건 이름 상자 [boxes](둘레 [UnionLook.nameClear] — 줄 굵기의 반도 더해 x가 상자에 걸치는 것)를
  /// 지나는 몫은 비운다(0.1.1 · 조사 결함 41). 상자가 없으면 [_stroke] 그대로.
  void _open(ui.Canvas canvas, double x, double y0, double y1, double alpha, List<ui.Rect> boxes, PaintContext c) {
    const pad = UnionLook.nameClear, half = UnionLook.width / 2;
    final gaps = <(double, double)>[
      for (final b in boxes)
        if (x + half > b.left - pad && x - half < b.right + pad && b.bottom + pad > y0 && b.top - pad < y1) (b.top - pad, b.bottom + pad),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var from = y0;
    for (final (a, z) in gaps) {
      if (a > from) _stroke(canvas, x, from, math.min(a, y1), alpha);
      from = math.max(from, z);
      c.debug?.note('동군연합 비움', '${x.toStringAsFixed(1)} ${a.toStringAsFixed(1)}~${z.toStringAsFixed(1)}');
    }
    if (from < y1) _stroke(canvas, x, from, y1, alpha);
  }

  void _stroke(ui.Canvas canvas, double x, double y0, double y1, double alpha) {
    if (y1 <= y0) return;
    _linePaint
      ..color = ui.Color(CanvasInk.alpha(UnionLook.ink, alpha))
      ..strokeWidth = UnionLook.width;
    canvas.drawLine(ui.Offset(x, y0), ui.Offset(x, y1), _linePaint);
  }

  /// 고리 하나: 줄 끝은 종이빛으로 채우고(밑의 줄 · 칸 테를 가림), 겹고리 표지는 채우지 않는다(두 고리의 테가 다 보이게 — 웹의 `.tl-umark`).
  void _ring(ui.Canvas canvas, double x, double y, double alpha, {bool fill = true}) {
    if (fill) {
      _fill.color = ui.Color(withAlpha(Look.paper, math.min(1.0, alpha * 2)));
      canvas.drawCircle(ui.Offset(x, y), UnionLook.ring - UnionLook.ringEdge / 2, _fill);
    }
    _linePaint
      ..color = ui.Color(CanvasInk.alpha(1, alpha))
      ..strokeWidth = UnionLook.ringEdge;
    canvas.drawCircle(ui.Offset(x, y), UnionLook.ring - UnionLook.ringEdge / 2, _linePaint);
  }

  /// [x] · [y](배치 px)에 있는 줄 — (두 띠, 풍선 글). 없으면 null.
  (int, int, String)? hitUnion(double x, double y) {
    // 두 띠 사이의 몫은 띠 뒤 판이라 위 나라 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나)의 종이 뒤에서는 보이지 않는다 —
    // 그 자리의 누름은 사슬 칸이 받는다(칸 층 [StripLayer.chainAt] · 검토 2026-10-25).
    if (strips?.chainAt(x, y) ?? false) return null;
    for (final (rect, a, b, tip) in _hits) {
      if (rect.contains(ui.Offset(x, y))) return (a, b, tip);
    }
    return null;
  }
}
