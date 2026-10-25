import 'dart:math' as math;
import 'dart:ui' as ui;

import '../aux_calendar.dart' show fromAstro, toAstro;
import '../layout.dart' show G;
import '../ruler.dart' show minuteOfYear, yearAt, yearLabel;
import '../sprites.dart';
import '../sphere_rows.dart';
import '../text_paragraph.dart';
import 'context.dart';
import 'gutter.dart' show Gut;
import 'ink.dart';
import 'look.dart';

// 문화권 머리 단 밑 줄(리메이크 4단계 과제 3 걸음 2 · 계획 정한 것 #3): 펼친 문화권의 머리 단 상자 안 위 20 밑에 시대 줄 · 주기 줄을 그린다.
// 기준은 메이커 서고 미리보기 — js/timeline.js `_drawSphereRows`(2151 ~ 2215줄)와 css/common.css `.tl-srow` · `.tl-srow-cy` · `.tl-srow-lab`(2456 ~ 2462줄).
//   시대 줄(14): 그 문화권 시대마다 흰 종이 칩 — 높이 14 · 테 먹 30 · 둥근 3 · 글 8.5 먹 85 · 안 여백 4 · 넘치면 끝을 '…'.
//   주기 줄(13): 칠 먹 2.5 · 위아래 테 먹 15 · 칸마다 왼쪽 금(먹 12 · 바퀴의 첫 이름은 먹 35)과 가운데 글(8 먹 55 · 첫 이름은 굵게 먹 85).
//     이름 돌림 — 해 한 칸이 9px 이상이고 400해 안이면 해마다 칸(글은 16px 이상일 때만), 좁으면 한 바퀴를 한 칸으로('첫 이름 해' → '첫 이름' → 빈 칸).
//     연호 눈금 — step해마다 칸(400칸 안) · 40px 이상이면 '연호 n년'.
//     이름의 순번 · 바퀴의 첫 해 · '연호 n년'의 n은 천문 해(기원전 1년 = 0)로 센다 — 계약의 `HT.cycleIndex`와 날짜 칸 사용자 순환(aux_calendar.dart)과 같은 셈.
//     미리보기(`_drawSphereRows` 2180 · 2187 · 2200줄)는 해 좌표의 차이로 세어 0을 건너면 한 해 어긋난다(검토 지적 — 5단계 잔여 과제 5에 알림).
//   사람 띠(16 — 과제 4 걸음 1 · 미리보기 2205 ~ 2213줄 · css `.tl-person` 2413 · 2419 ~ 2421 · 2479 ~ 2482줄): 주기 줄 밑에 줄마다 16.
//     흰 종이 · 테 먹 50 · 둥근 끝 8 · 구멍(테 안 왼쪽 6 · 위 5 · 지름 5 · 테 먹 50) · 이름 10 굵게 먹 85(테 안 왼쪽 15) 뒤 6에 때 글 10 먹 55 —
//     '시작해 ~ 끝해 · 왕관 n'. 폭은 그림판 안으로 자르고 최소 14(시작 자리에서) · 60 아래면 때 글 없이 · 40 아래면 구멍만(테 안 왼쪽 4) · 글은 드는 만큼 줄임('…').
//   줄 자리는 그림판 왼쪽 ~ 오른쪽 끝 − 20 · 줄 이름표('시대' · 주기 이름 — 9.5 먹 60)는 왼쪽 칸 오른쪽 끝에서 12 앞에 오른쪽 맞춤(사람 띠 줄은 이름표 없음).
// 해 ↔ 분은 앱의 해 셈(ruler.dart의 minuteOfYear · yearAt — 0년 빈 자리는 건너뜀)을 쓴다. 글자는 자리 밖으로 나가지 않는다(넘치는 글은 줄이거나 쓰지 않음).
// 그리기는 왼쪽 칸 층(gutter.dart `_sphereHead`)에서 머리 단 바로 뒤에 — 몸통 뒤 · 날짜 칸 앞. 네모는 c.quads, 둥근 귀는 c.sprites, 구멍은 층의 점, 글자는 c.later.
// 그린 사람 띠의 자리([SpherePersonBand] — 문화권 · 줄 · x 범위 · 인물 uid · 왕관)는 왼쪽 칸 층이 장면마다 남긴다(gutter.dart `personBands` — 과제 4 걸음 2 · 3이 읽음).
// 누름(과제 4 걸음 3): 보이는 띠 자리가 사람 창을 여는 누름 자리다([SpherePersonBand.opens] — 왼쪽 칸 층이 머리 단 누름 자리 뒤에 적어 먼저 잡힘).

/// 머리 단 밑 줄의 값 — css에서 옮긴 값(메이커 서고 미리보기). 먹 값은 옛 값 — 그릴 때 그림판 먹 단계([CanvasInk])로 낸다
/// (칩 테 30 → 25 · 글 85 · 주기 칠 2.5 → 4 · 테 15 → 12 · 칸 금 12 · 첫 이름 금 35 → 45 · 칸 글 55 → 60 · 이름표 60 · 사람 띠 테 50 → 45).
abstract final class SphereLinesLook {
  /// 줄 자리의 오른쪽 끝(그림판 오른쪽 끝에서 20 앞 — `.tl-sphere-rows { right: 20px }`) · 줄 이름표의 오른쪽 끝(왼쪽 칸 오른쪽 끝에서 12 앞).
  static const rightPad = 20.0, labelRight = 12.0;

  /// 시대 칩: 둥근 3 · 테 먹 30 · 안 여백 4 · 글줄 12(테 안) · 글 8.5 먹 85.
  static const chipRadius = 3.0, chipEdge = .30, chipPad = 4.0, chipLine = 12.0, chipInk = .85;
  static final chip = TextLook(8.5, ui.FontWeight.w400, CanvasInk.of(0xff262626));

  /// 주기 줄: 칠 먹 2.5 · 위아래 테 먹 15 · 칸 글줄 11(테 안) · 칸 왼쪽 금 먹 12(첫 이름 먹 35).
  static const cycleFill = .025, cycleEdge = .15, cellLine = 11.0, cellEdge = .12, firstEdge = .35;
  static final cell = TextLook(8, ui.FontWeight.w400, CanvasInk.of(0xff737373)), first = TextLook(8, ui.FontWeight.w700, CanvasInk.of(0xff262626));

  /// 이름 돌림: 해 한 칸이 [yearCell]px 이상이면 해마다 칸, 글은 [yearText]px 이상일 때만. 칸은 [maxCells]까지(미리보기의 400).
  /// 한 바퀴 칸에 '첫 이름 해'가 들려면 글 폭 + 8, '첫 이름'은 + 6. 연호 눈금의 글은 칸이 [eraText]px 이상일 때.
  static const yearCell = 9.0, yearText = 16.0, maxCells = 400, roundFull = 8.0, roundName = 6.0, roundMin = 4.0, eraText = 40.0;

  /// 줄 이름표: 9.5 먹 60 · 글줄 13(줄 위에서).
  static const labelLine = 13.0;
  static final label = TextLook(9.5, ui.FontWeight.w400, CanvasInk.of(0xff666666));

  /// 한 해의 분(365.25일 — 해 한 칸의 폭을 잴 때).
  static const yearMinutes = 525960.0;

  /// 사람 띠(css `.tl-person`): 둥근 끝 8 · 테 먹 50 · 글줄 14(테 안) · 왼쪽 여백 15 · 오른쪽 여백 6 · 이름과 때 글 사이 6 ·
  /// 구멍(테 안 왼쪽 6 · 아주 좁으면 4 · 위 5 · 지름 5 — 속은 종이 3) · 최소 폭 14 · 60 아래면 때 글 없이(`is-narrow`) · 40 아래면 구멍만(`is-tiny`).
  static const personRadius = 8.0, personEdge = .50, personLine = 14.0, personPadLeft = 15.0, personPadRight = 6.0, personGap = 6.0;
  static const holeLeft = 6.0, holeLeftTiny = 4.0, holeTop = 5.0, holeSize = 5.0, holeInner = 3.0;
  static const personMin = 14.0, narrowBelow = 60.0, tinyBelow = 40.0;
  static final personName = TextLook(10, ui.FontWeight.w700, CanvasInk.of(0xff262626)), personWhen = TextLook(10, ui.FontWeight.w400, CanvasInk.of(0xff737373));
}

/// 사람 띠의 꼴 — 넉넉함(이름 · 때 글) · 좁음(이름만 — 60 아래) · 아주 좁음(구멍만 — 40 아래).
enum SpherePersonShape { full, narrow, tiny }

/// 사람 띠 하나의 그린 자리 — 띠의 왼쪽 · 오른쪽(보이는 몫 — 줄 자리 오른쪽 끝에서 잘렸으면 [openRight]) · 위(장면 y) · 꼴 · 구멍 왼쪽 ·
/// 그린 글(빈 글이면 쓰지 않음)과 그 왼쪽. [person]이 이름 · 때 · 인물 uid · 왕관 · 줄 번호를 든다(과제 4 걸음 2 · 3이 읽음).
class SpherePersonBand {
  const SpherePersonBand(this.person, this.x0, this.x1, this.top, this.shape, this.holeX,
      {this.openRight = false, this.name = '', this.nameX = 0, this.when = '', this.whenX = 0});
  final SpherePersonRow person;
  final double x0, x1, top, holeX, nameX, whenX;
  final SpherePersonShape shape;
  final bool openRight;
  final String name, when;

  double get bottom => top + G.spherePerson;

  /// 누르면 여는 것(과제 4 걸음 3 — 사람 창): 인물 uid가 있으면 그 인물([cell]은 빈 글 — 인물 창), 없으면 첫 왕관의 띠 칸 창(띠 uid · `leader:i`).
  /// 왕관도 없으면 빈 uid(누름이 아무것도 열지 않는다). 누름 자리는 보이는 띠 [x0] ~ [x1] · [top] ~ [bottom](왼쪽 칸 층 `gutter.dart`가 적음).
  ({String uid, String cell}) get opens {
    if (person.uid.isNotEmpty) return (uid: person.uid, cell: '');
    for (final crown in person.crowns) {
      if (crown.uid.isNotEmpty && crown.cell >= 0) return (uid: crown.uid, cell: 'leader:${crown.cell}');
    }
    return (uid: '', cell: '');
  }

  /// 구멍을 그리는가 — 구멍이 띠 안(테 안)에 다 들 때만.
  bool get hasHole => holeX + SphereLinesLook.holeSize <= x1 - (openRight ? 0 : 1);

  @override
  String toString() => 'SpherePersonBand(${person.name} · $x0 ~ $x1 · $top · ${shape.name} · "$name" "$when")';
}

/// 시대 칩 하나: 칩의 왼쪽 · 오른쪽(오른쪽 끝에서 잘렸으면 [openRight] — 오른쪽 테 · 둥근 귀 없음) · 위 · 글(빈 글이면 쓰지 않음)과 글 왼쪽.
class SphereChip {
  const SphereChip(this.x0, this.x1, this.top, this.text, this.textX, {this.openRight = false});
  final double x0, x1, top, textX;
  final String text;
  final bool openRight;

  @override
  String toString() => 'SphereChip($x0 ~ $x1 · $top · "$text")';
}

/// 주기 줄의 칸 하나: 왼쪽 금 자리([edge] — 줄 자리 밖이면 금을 긋지 않음) · 오른쪽 · 첫 이름인가 · 글(빈 글이면 쓰지 않음)과 글 왼쪽.
class SphereCell {
  const SphereCell(this.x0, this.x1, this.first, this.text, this.textX, {this.edge = true});
  final double x0, x1, textX;
  final bool first, edge;
  final String text;

  @override
  String toString() => 'SphereCell($x0 ~ $x1${first ? ' · 첫' : ''} · "$text")';
}

/// 문화권 하나의 머리 단 밑 줄을 그릴 것 — 자리 · 글을 먼저 셈하고([SphereLinesPaint.plan]) 그린다. 검사도 이것을 읽는다.
class SphereLinesPlan {
  /// 시대 줄 · 주기 줄 · 사람 띠 첫 줄의 위(배치 y — 그 줄이 없거나 상자에 들지 않으면 null)와 주기 줄의 왼쪽 · 오른쪽.
  double? epochTop, cycleTop, personTop;
  double left = 0, right = 0;
  final chips = <SphereChip>[];
  final cells = <SphereCell>[];

  /// 그릴 사람 띠(답의 차례 — 화면 밖 · 상자에 들지 않는 줄의 띠는 없음).
  final persons = <SpherePersonBand>[];

  /// 줄 이름표: (글, 왼쪽, 줄 위).
  final labels = <(String, double, double)>[];

  /// 글자 폭을 아직 모르는 글이 있었다(다음 장면을 청한다).
  bool waiting = false;
}

abstract final class SphereLinesPaint {
  /// 문화권 하나의 머리 단 밑 줄을 그린다. [top]은 줄 영역의 위(머리 단 위 + 20 · 배치 y), [bottom]은 상자 아랫변 테의 y —
  /// 흐르는 동안(접고 펼 때) 상자에 다 들지 않는 줄은 그리지 않는다. [dot]은 층의 점(사람 띠의 구멍 — 지름 · 왼쪽 · 위 · 빛깔).
  /// 그린 것의 셈을 돌려준다(줄이 없으면 null — 왼쪽 칸 층이 사람 띠의 자리를 남길 때 읽음).
  static SphereLinesPlan? paint(PaintContext c, SphereRows rows, double top, double bottom, {void Function(double size, double left, double top, int argb)? dot}) {
    if (rows.isEmpty) return null;
    final v = c.v;
    final plan = SphereLinesPaint.plan(
      rows, top: top, bottom: bottom, left: c.left, right: c.w - SphereLinesLook.rightPad,
      xOf: v.xOf, loMinute: v.minuteAt(c.left), hiMinute: v.minuteAt(c.w), ppm: v.ppm, widthOf: c.text.widthOf,
    );
    if (plan.waiting) c.scene.requestFrame();
    final q = c.quads;
    if (plan.epochTop != null) {
      final fill = Look.paper, edge = CanvasInk.gray(SphereLinesLook.chipEdge);
      for (final chip in plan.chips) {
        final t = chip.top, b = t + G.sphereEpoch;
        // 테 빛깔로 둥근 네모를 깔고 안쪽 1px을 종이로 덮는다(figures.dart의 둥근 칸과 같은 길 — 귀는 c.sprites 조각).
        _round(c, chip.x0, t, chip.x1, b, SphereLinesLook.chipRadius, edge, !chip.openRight);
        _round(c, chip.x0 + 1, t + 1, chip.x1 - (chip.openRight ? 0 : 1), b - 1, SphereLinesLook.chipRadius - 1, fill, !chip.openRight);
        c.stats.shapes++;
        if (chip.text.isNotEmpty) {
          c.later.add('sphereEpoch', chip.text, SphereLinesLook.chip, chip.textX, Gut.textTopAt(t + 1, SphereLinesLook.chipLine, SphereLinesLook.chip.size));
        }
      }
    }
    final cy = plan.cycleTop;
    if (cy != null) {
      final b = cy + G.sphereCycle;
      final edge = CanvasInk.gray(SphereLinesLook.cycleEdge);
      q.add(plan.left, cy, plan.right, b, CanvasInk.gray(SphereLinesLook.cycleFill));
      q.hLine(plan.left, plan.right, cy, edge);
      q.hLine(plan.left, plan.right, b - 1, edge);
      final normal = CanvasInk.gray(SphereLinesLook.cellEdge), firstEdge = CanvasInk.gray(SphereLinesLook.firstEdge);
      for (final cell in plan.cells) {
        if (cell.edge) q.vLine(cell.x0, cy + 1, b - 1, cell.first ? firstEdge : normal);
        if (cell.text.isNotEmpty) {
          final look = cell.first ? SphereLinesLook.first : SphereLinesLook.cell;
          c.later.add('sphereCycle', cell.text, look, cell.textX, Gut.textTopAt(cy + 1, SphereLinesLook.cellLine, look.size));
        }
      }
      c.stats.shapes++;
    }
    for (final (text, x, lineTop) in plan.labels) {
      c.later.add('sphereLineLabel', text, SphereLinesLook.label, x, Gut.textTopAt(lineTop, SphereLinesLook.labelLine, SphereLinesLook.label.size));
    }
    if (plan.persons.isNotEmpty) {
      final edge = CanvasInk.gray(SphereLinesLook.personEdge);
      const r = SphereLinesLook.personRadius;
      for (final band in plan.persons) {
        final t = band.top, b = band.bottom, open = band.openRight;
        // 테 빛깔로 둥근 띠를 깔고 안쪽 1px을 종이로 덮는다(시대 칩과 같은 길) — 오른쪽 끝에서 잘린 띠는 오른쪽 테 · 둥근 귀 없이.
        _round(c, band.x0, t, band.x1, b, r, edge, !open);
        _round(c, band.x0 + 1, t + 1, band.x1 - (open ? 0 : 1), b - 1, r - 1, Look.paper, !open);
        c.stats.shapes++;
        if (dot != null && band.hasHole) {
          dot(SphereLinesLook.holeSize, band.holeX, t + 1 + SphereLinesLook.holeTop, edge);
          dot(SphereLinesLook.holeInner, band.holeX + 1, t + 2 + SphereLinesLook.holeTop, Look.paper);
        }
        final y = Gut.textTopAt(t + 1, SphereLinesLook.personLine, SphereLinesLook.personName.size);
        if (band.name.isNotEmpty) c.later.add('spherePersonName', band.name, SphereLinesLook.personName, band.nameX, y);
        if (band.when.isNotEmpty) c.later.add('spherePersonWhen', band.when, SphereLinesLook.personWhen, band.whenX, y);
      }
    }
    return plan;
  }

  /// 그릴 것을 셈한다(그리기 없이 — 검사가 바로 부른다). [xOf]는 분 → 배치 x, [loMinute] · [hiMinute]는 그림판 왼쪽 · 오른쪽 끝의 시각,
  /// [ppm]은 1분의 폭, [widthOf]는 글자 폭(아직 모르면 null). [left] · [right]는 줄 자리(그림판 왼쪽 · 오른쪽 끝 − 20).
  static SphereLinesPlan plan(
    SphereRows rows, {
    required double top,
    required double bottom,
    required double left,
    required double right,
    required double Function(num minute) xOf,
    required double loMinute,
    required double hiMinute,
    required double ppm,
    required double? Function(String text, TextLook look) widthOf,
  }) {
    final out = SphereLinesPlan()
      ..left = left
      ..right = right;
    if (rows.isEmpty || right <= left) return out;
    double? width(String text, TextLook look) {
      final w = widthOf(text, look);
      if (w == null) out.waiting = true;
      return w;
    }

    // 줄 이름표: 왼쪽 칸 오른쪽 끝에서 12 앞에 오른쪽 맞춤.
    void label(String text, double lineTop) {
      if (text.isEmpty) return;
      final w = width(text, SphereLinesLook.label);
      if (w != null) out.labels.add((text, left - SphereLinesLook.labelRight - w, lineTop));
    }

    if (rows.epochs.isNotEmpty && top + rows.epochTop + G.sphereEpoch <= bottom) {
      final y = top + rows.epochTop;
      out.epochTop = y;
      label('시대', y);
      for (final e in rows.epochs) {
        // 미리보기: a = max(X(시작), 0) · b = min(X(끝), W) · b − a < 2면 건너뜀 — 줄 자리 오른쪽 끝(W − 20)을 넘는 칩은 그 자리에서 잘린다(오른쪽 열림).
        final a = math.max(xOf(e.start), left).roundToDouble(), b = math.min(xOf(e.end), right + SphereLinesLook.rightPad).roundToDouble();
        if (b - a < 2 || a >= right) continue;
        final open = b > right, x1 = open ? right : b;
        final room = x1 - a - 2 - 2 * SphereLinesLook.chipPad;
        out.chips.add(SphereChip(a, x1, y, _fit(e.name, SphereLinesLook.chip, room, width), a + 1 + SphereLinesLook.chipPad, openRight: open));
      }
    }
    final cycle = rows.cycle;
    if (cycle != null && top + rows.cycleTop + G.sphereCycle <= bottom) {
      final y = top + rows.cycleTop;
      out.cycleTop = y;
      label(cycle.title, y);
      _cells(out, cycle, left, right, xOf, loMinute, hiMinute, ppm, width);
    }
    if (rows.persons.isNotEmpty && top + rows.personTop + G.spherePerson <= bottom) {
      out.personTop = top + rows.personTop;
      for (final p in rows.persons) {
        final t = personTopOf(rows, p, top: top, bottom: bottom);
        if (t == null) continue;
        final band = _person(p, t, left, right, xOf, width);
        if (band != null) out.persons.add(band);
      }
    }
    return out;
  }

  /// 사람 띠 [p]의 위(배치 y) — [top]은 줄 영역의 위(머리 단 위 + 20), [bottom]은 상자 아랫변 테의 y. 상자에 다 들지 않는 줄(접고 펼 때 흐르는 동안)이면 null.
  /// 그리기([plan])와 실(paint/sphere_threads.dart — 과제 4 걸음 2)이 같은 셈을 쓴다.
  static double? personTopOf(SphereRows rows, SpherePersonRow p, {required double top, required double bottom}) {
    if (top + rows.personTop + G.spherePerson > bottom) return null;
    final t = top + rows.personTop + p.lane * G.spherePerson;
    return t + G.spherePerson > bottom ? null : t;
  }

  /// 사람 띠 [p]의 가로 자리(미리보기 `_drawSphereRows`의 사람 띠 — 2205 ~ 2213줄): 시작 x(a0)가 그림판 오른쪽 끝(W) 밖이거나 끝 x(b0)가 왼쪽 끝 앞이면 null ·
  /// a = max(a0, 0) · b = min(max(b0, a0 + 14), W)(정수 px) · 줄 자리 오른쪽 끝(W − 20)을 넘는 몫은 그 자리에서 잘린다(오른쪽 열림 — [x1]은 보이는 오른쪽).
  /// [wide]는 자르기 전의 b − a(꼴을 가르는 폭). 그리기와 실이 같은 셈을 쓴다.
  static ({double x0, double x1, bool open, double wide})? personSpan(SpherePersonRow p, {required double left, required double right, required double Function(num minute) xOf}) {
    final edgeRight = right + SphereLinesLook.rightPad;
    final a0 = xOf(p.start), b0 = xOf(p.end);
    if (b0 < left || a0 > edgeRight) return null;
    final a = math.max(a0, left).roundToDouble(), b = math.min(math.max(b0, a0 + SphereLinesLook.personMin), edgeRight).roundToDouble();
    if (b - a < 1 || a >= right) return null;
    final open = b > right;
    return (x0: a, x1: open ? right : b, open: open, wide: b - a);
  }

  /// 사람 띠 하나(미리보기 `_drawSphereRows`의 사람 띠 — 2205 ~ 2213줄). 화면 밖이거나 보이는 몫이 없으면 null.
  /// 가로 자리는 [personSpan] · 폭 b − a가 40 아래면 `is-tiny` · 60 아래면 `is-narrow`.
  static SpherePersonBand? _person(SpherePersonRow p, double t, double left, double right, double Function(num) xOf, double? Function(String, TextLook) width) {
    final look = SphereLinesLook.personName, whenLook = SphereLinesLook.personWhen;
    final span = personSpan(p, left: left, right: right, xOf: xOf);
    if (span == null) return null;
    final a = span.x0, wide = span.wide, open = span.open, x1 = span.x1;
    final shape = wide < SphereLinesLook.tinyBelow
        ? SpherePersonShape.tiny
        : wide < SphereLinesLook.narrowBelow
        ? SpherePersonShape.narrow
        : SpherePersonShape.full;
    if (shape == SpherePersonShape.tiny) return SpherePersonBand(p, a, x1, t, shape, a + 1 + SphereLinesLook.holeLeftTiny, openRight: open);
    // 글 자리: 테 안 왼쪽 여백 15 뒤 ~ 테 안 오른쪽 여백 6 앞(잘린 띠는 잘린 자리까지). css text-overflow: ellipsis처럼 줄 끝을 '…'로 —
    // 이름 + 6 + 때 글이 다 들면 둘 다, 이름 + 6 + '…'까지 들면 때 글을 줄이고, 그것도 안 들면 이름을 줄이고 때 글은 없이.
    final textX = a + 1 + SphereLinesLook.personPadLeft;
    final room = (open ? x1 : x1 - 1 - SphereLinesLook.personPadRight) - textX;
    var name = '', time = '';
    double nameW = 0;
    if (room > 0) {
      final wn = p.name.isEmpty ? 0.0 : width(p.name, look);
      if (shape == SpherePersonShape.full && wn != null) {
        final wt = width(p.when, whenLook), we = width('…', whenLook);
        if (wt != null && wn + SphereLinesLook.personGap + wt <= room) {
          (name, time, nameW) = (p.name, p.when, wn);
        } else if (we != null && wn + SphereLinesLook.personGap + we <= room) {
          (name, time, nameW) = (p.name, _fit(p.when, whenLook, room - wn - SphereLinesLook.personGap, width), wn);
        }
      }
      if (name.isEmpty && p.name.isNotEmpty) {
        name = _fit(p.name, look, room, width);
        nameW = name.isEmpty ? 0 : (width(name, look) ?? 0);
        time = '';
      }
    }
    return SpherePersonBand(p, a, x1, t, shape, a + 1 + SphereLinesLook.holeLeft,
        openRight: open, name: name, nameX: textX, when: time, whenX: textX + nameW + SphereLinesLook.personGap);
  }

  /// 주기 줄의 칸들(미리보기 `_drawSphereRows`의 셋 갈래).
  static void _cells(SphereLinesPlan out, SphereCycleRow cycle, double left, double right, double Function(num) xOf, double loMinute, double hiMinute, double ppm,
      double? Function(String, TextLook) width) {
    final start = yearAt(loMinute), end = yearAt(hiMinute);
    final y0 = start.floor(), y1 = end.ceil();
    final yw = SphereLinesLook.yearMinutes * ppm;
    double xYear(int y) => xOf(minuteOfYear(y.toDouble()));
    // 해 좌표에는 0년이 빈 자리다 — 기원전 1년(−1)의 끝은 기원후 1년의 시작(ruler.dart의 간지 칸과 같은 셈).
    int nextYear(int y) => y == -1 ? 1 : y + 1;

    /// 칸 하나를 담는다. 글은 칸 안(왼쪽 금 1px 뒤 ~ 오른쪽 끝)에 가운데 · 줄 자리 안에 다 들 때만.
    void put(double a, double b, bool first, String text) {
      final x0 = a.roundToDouble(), x1 = b.roundToDouble();
      final look = first ? SphereLinesLook.first : SphereLinesLook.cell;
      var shown = '';
      var tx = x0;
      if (text.isNotEmpty) {
        final w = width(text, look);
        if (w != null) {
          tx = x0 + 1 + (x1 - x0 - 1 - w) / 2;
          if (w <= x1 - x0 - 1 && tx >= left && tx + w <= right) shown = text;
        }
      }
      out.cells.add(SphereCell(x0, x1, first, shown, tx, edge: x0 >= left && x0 < right));
    }

    if (cycle.isNames) {
      final n = cycle.names.length;
      // 순번은 천문 해(기원전 1년 = 0)로 센다 — 계약의 이름 돌림은 최상위 yearCycle과 같은 뜻 · 같은 읽기(js/core.js `HT.cycleIndex`)이고,
      // 날짜 칸의 사용자 순환(aux_calendar.dart `YearCycle.index`)도 이렇게 센다. 해 좌표의 차이로 세면 0을 건널 때 한 해 어긋난다.
      final base = toAstro(cycle.start);
      int index(int y) => (toAstro(y) - base) % n; // Dart의 %는 나누는 수가 양수면 늘 0 이상
      if (yw >= SphereLinesLook.yearCell && y1 - y0 <= SphereLinesLook.maxCells) {
        // 해마다 칸 — 글은 해 한 칸이 16px 이상일 때만.
        for (int y = y0; y <= y1; y++) {
          if (y == 0) continue;
          final a = xYear(y), b = xYear(nextYear(y));
          if (b < left || a > right) continue;
          final i = index(y);
          put(a, b, i == 0, yw >= SphereLinesLook.yearText ? cycle.names[i] : '');
        }
        return;
      }
      // 해 한 칸이 좁으면 한 바퀴(이름 n개)를 한 칸으로 — 첫 이름(+ 해)만, 바퀴 칸도 좁으면 빈 칸(경계만). 보이는 몫만(가장자리에서 글이 반쯤 잘리지 않게).
      if (yw * n < SphereLinesLook.roundMin || (y1 - y0) / n > SphereLinesLook.maxCells) return;
      // 바퀴의 첫 해는 천문 해로 n씩 가고 해 좌표로 되돌린다(aux_calendar.dart `YearCycle.firstYears`와 같은 셈) — 0을 건너는 바퀴도 n해를 덮는다.
      for (int a0 = toAstro(y0) - index(y0); fromAstro(a0) <= y1; a0 += n) {
        final y = fromAstro(a0);
        final a = math.max(xYear(y), left), b = math.min(xYear(fromAstro(a0 + n)), right);
        if (b - a < 1) continue;
        final x0 = a.roundToDouble(), room = b.roundToDouble() - x0;
        final full = '${cycle.names.first} ${yearLabel(y)}';
        final wFull = width(full, SphereLinesLook.first), wName = width(cycle.names.first, SphereLinesLook.first);
        final text = wFull != null && room >= wFull + SphereLinesLook.roundFull
            ? full
            : wName != null && room >= wName + SphereLinesLook.roundName
            ? cycle.names.first
            : '';
        put(a, b, true, text);
      }
      return;
    }
    // 연호 눈금: step해마다 칸(보이는 처음의 step 배수부터) · 40px 이상이면 '연호 n년'.
    // n은 원년(from)에서 지난 해 수 — 천문 해로 센다(0을 건너도 한 해 크지 않게. 칸 자리는 미리보기처럼 해 좌표의 step 배수).
    final step = math.max(1, cycle.step);
    final from = (start / step).ceil() * step;
    if ((end - from) / step > SphereLinesLook.maxCells) return;
    final origin = toAstro(cycle.from);
    for (int y = from; y <= y1; y += step) {
      final a = xYear(y), b = xYear(y + step);
      if (b < left || a > right) continue;
      put(a, math.max(b, a + 1), true, b - a >= SphereLinesLook.eraText ? '${cycle.era} ${toAstro(y) - origin}년' : '');
    }
  }

  /// [text]를 [room]에 맞춘다 — 넘치면 끝을 '…'로(css text-overflow: ellipsis — 들 때까지 한 자씩 덜고 '…', '…'도 안 들면 빈 글).
  static String _fit(String text, TextLook look, double room, double? Function(String, TextLook) width) {
    if (text.isEmpty || room <= 0) return '';
    final full = width(text, look);
    if (full == null) return '';
    if (full <= room) return text;
    final chars = text.runes.toList();
    int lo = 0, hi = chars.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final w = width('${String.fromCharCodes(chars.take(mid)).trimRight()}…', look);
      if (w == null) return '';
      if (w <= room) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final out = '${String.fromCharCodes(chars.take(lo)).trimRight()}…';
    final w = width(out, look);
    return w != null && w <= room ? out : '';
  }

  /// 둥근 네모 하나(채움만) — 왼쪽 두 귀는 늘 둥글고, [roundRight]가 거짓이면 오른쪽은 직각(줄 자리 끝에서 잘린 칩).
  /// 귀는 c.sprites의 둥근 조각(반지름 9를 줄여 찍음), 몸통은 네모 묶음(figures.dart `_roundRect`와 같은 길).
  static void _round(PaintContext c, double l, double t, double r, double b, double radius, int argb, bool roundRight) {
    if (r <= l || b <= t) return;
    final rad = math.max(0.0, math.min(radius, math.min((r - l) / (roundRight ? 2 : 1), (b - t) / 2)));
    final size = rad / Sprites.cornerRadius;
    var bodyL = l, bodyR = r;
    if (rad > 0) {
      c.sprites.add(Sprites.cornerTopLeft, l, t, argb, size);
      c.sprites.add(Sprites.cornerBottomLeft, l, b - rad, argb, size);
      c.quads.add(l, t + rad, l + rad, b - rad, argb);
      bodyL = l + rad;
      if (roundRight) {
        c.sprites.add(Sprites.cornerTopRight, r - rad, t, argb, size);
        c.sprites.add(Sprites.cornerBottomRight, r - rad, b - rad, argb, size);
        c.quads.add(r - rad, t + rad, r, b - rad, argb);
        bodyR = r - rad;
      }
    }
    if (bodyR > bodyL) c.quads.add(bodyL, t, bodyR, b, argb);
  }
}
