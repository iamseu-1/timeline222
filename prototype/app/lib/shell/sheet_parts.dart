import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../scene/paint/bands.dart' show TagEnd, TagLook;
import 'line_icon.dart';
import 'look.dart';
import 'motion_widgets.dart';
import 'sheet_look.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  서고 시트 부품 — 틀의 시트와 창 여덟(필터 시트 · 검색 결과 · 범례 · 차림표 · DLC 관리 · 승계표 · 단체 계보 · 문서 창)이 함께 쓴다.
//  감독 고름 G5 #9(다듬기 판 · 계획 4단계 '감독 고름 더')의 서고 문법을 앱 위젯으로 옮겼다. 값은 모두 `sheet_look.dart`의 [SheetLook].
//
//  짜임(목업 `.claude/research/stage4-choose/themes/g-sheet-*.js` — git 밖):
//    창 = 폴더([SheetFolder] — 어깨 탭 안 **맨 글** 12 + 수 · 오른쪽 닫기 탭 · 탭을 오른쪽에 · 나라 색 갈래)
//    묶음 = 상자([SheetBox] — 모따기 6 · 뚜껑 22 안 **흰 라벨**([SheetLidLabel]) + 수 + 오른쪽 안내 글)
//    줄 = 실에 꿴 꼬리표([SheetThreadColumn] — 뚜껑 밑선의 매듭에서 줄마다 구멍으로 · 가로대 갈래도)
//    켜고 끄기 = 칩([SheetTagChip] · [SheetKeyToggle] · [SheetDotChip] · [SheetScopeChip]) — 켬 = 칠, 끔 = 흰 종이 · 먹 25 **실선** · 글 45
//    단추 = 흰 이름 종이([SheetPaperButton]) · 고르는 칸([SheetSelect] ▾) · 하나 고르기 = 종이 사슬([SheetChain]) ·
//    관계 · 방식 = 열쇠표([SheetKeyLabel]) · 고른 것 = 고른 테([SheetPickRing] — 먹 100 · 1.5)
//    늘어놓기 = 상자 두 열([SheetColumns] — 같은 너비 · 같은 줄은 같은 키 · 좁으면 한 열) · 칩 줄([SheetRun]) ·
//    고르는 칸의 목록 = 흰 이름 종이를 편 것([SheetChoice] · [showSheetChoices]) · 뚜껑의 작은 꼬리표([SheetSmallTag]) ·
//    꼬리표 + 글 한 줄([SheetFitRun] — 들지 않는 꼬리표는 그리지 않고 글이 남는 폭을) · 누르는 나라 꼬리표([SheetTagButton] — 단체 계보)
//  점선 테는 대립 · 얹은 트랙(옮겨 얹기)에만 쓴다([SheetShape.dash]) — 꺼 둔 칩 · 줄은 늘 실선이다.
//  풍선([hint])과 읽기 글(Semantics의 label)은 누르는 부품마다 받는다 — 바꿔 끼우는 창이 예전 부품의 풍선 · 읽기 글을 그대로 옮긴다.
//
//  화소: 바깥 상자는 정수 자리 · 정수 크기([SheetPixelBox]가 폭과 키를 올림)로 두고, 1px 테는 반 픽셀 안쪽(x + .5)을 지나 화소 한 줄을 칠한다.
//  움직임: 누름은 [MotionPress](pop · snap), 올림 · 켬끔의 빛깔 바뀜은 [Motion.microMs] 120ms(색 변화 토큰)만 — 새 움직임은 만들지 않는다.
//  상세 칸 · 표 보기도 쓰는 공용 [MotionChip] · [MotionToggle](`motion_controls.dart`)은 건드리지 않는다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 꼬리표의 끝 꼴 — 그림판 꼬리표의 종류 갈래와 같은 셋(오른쪽은 늘 직각).
enum SheetTagKind {
  /// 다스림: 왼쪽 두 귀 모따기 5.
  cham,

  /// 영토 밖(교단 · 단체 · 직위 · 사람): 왼쪽 둥근 끝(반지름 12까지).
  key,

  /// 무리: 직각 · 테 없음.
  plain,
}

/// 정권 종류 번호(계약 6-1 — 그림판 `BandKind`의 차례) → 꼬리표 끝 꼴. 그림판 [TagLook.endOf]를 그대로 불러 같은 갈래를 낸다:
/// 부흥 · 저항 = 둥근 끝 · 복속 세력 = 직각 · 그 밖 = 모따기.
SheetTagKind sheetTagKindOf(int kind) => switch (TagLook.endOf(kind & 0x1f)) {
  TagEnd.key => SheetTagKind.key,
  TagEnd.plain => SheetTagKind.plain,
  TagEnd.cham => SheetTagKind.cham,
};

// ---- 윤곽 셈(순수) ----

/// 꼬리표 윤곽 길. [box]는 바깥 화소 상자(정수 자리 · 정수 크기)이고 테는 반 픽셀 안쪽(왼 · 위 + .5, 오른 · 아래 − .5)을 지난다.
/// 무리는 직각, 둥근 끝의 반지름은 키의 반 · 폭을 넘지 않는다. [open]이면 오른쪽 세로 테 없이 연다(미정 끝 — 목업 t-common `outline`).
Path sheetTagPath(Rect box, SheetTagKind kind, {double chamfer = SheetLook.tagChamfer, double round = SheetLook.tagRound, bool open = false}) {
  final x0 = box.left + .5, y = box.top + .5, x1 = box.right - .5, h = box.height - 1, yb = y + h, w = x1 - x0;
  final (c, r) = _tagCorners(w, h, chamfer, round);
  return _tagOutline(x0, y, x1, yb, kind, c, r, open: open);
}

/// 가운데 줄 윤곽(폭 [w] · 키 [h])의 모따기 · 둥근 끝 크기 — 모따기는 폭 · 키의 반, 둥근 끝은 키의 반 · 폭을 넘지 않는다.
(double, double) _tagCorners(double w, double h, double chamfer, double round) =>
    (math.max(0.0, math.min(chamfer, math.min(w / 2, h / 2))), math.max(0.0, math.min(round, math.min(h / 2, w))));

/// 꼬리표 윤곽 그대로(자리 · 귀 크기를 셈하지 않고) — 오른쪽 위에서 시작해 왼쪽 끝을 돌아 오른쪽 아래까지.
Path _tagOutline(double x0, double y, double x1, double yb, SheetTagKind kind, double c, double r, {bool open = false}) {
  final p = Path()..moveTo(x1, y);
  switch (kind) {
    case SheetTagKind.plain:
      p
        ..lineTo(x0, y)
        ..lineTo(x0, yb)
        ..lineTo(x1, yb);
    case SheetTagKind.key:
      p
        ..lineTo(x0 + r, y)
        ..arcToPoint(Offset(x0, y + r), radius: Radius.circular(r), clockwise: false)
        ..lineTo(x0, yb - r)
        ..arcToPoint(Offset(x0 + r, yb), radius: Radius.circular(r), clockwise: false)
        ..lineTo(x1, yb);
    case SheetTagKind.cham:
      p
        ..lineTo(x0 + c, y)
        ..lineTo(x0, y + c)
        ..lineTo(x0, yb - c)
        ..lineTo(x0 + c, yb)
        ..lineTo(x1, yb);
  }
  if (!open) p.close();
  return p;
}

/// 45° 귀의 모따기 다리가 테를 [d]만큼 밖으로 옮길 때 느는 길이(안으로면 줄어든다) — d × (2 − √2).
double _chamferGrow(double d) => d * (2 - math.sqrt2);

/// 굵기 [width]의 테를 **칠할** 고리(짝홀 채움) — 가운데 줄 윤곽([sheetTagPath]와 같은 자리 · 같은 귀)을 [width]/2만큼 밖 · 안으로 옮긴 두 윤곽.
/// 테를 획(stroke)으로 긋지 않는 까닭: 실제 앱(Windows의 GPU 그리기)에서 꺾인 길의 1px 획이 이음 바로 뒤 한동안(길이의 15% 남짓)
/// 반만 칠해져 옅게 나왔다(걸음 2의 실제 앱 그림 — 상자 · 칩의 아래 테). 고리 칠은 곧은 테가 화소 경계에 앉아 화소 한 줄을 꽉 칠한다.
/// 연표 그림판도 테를 획 길이 아니라 네모 · 조각으로 긋는다(paint/bands.dart).
Path sheetTagRing(Rect box, SheetTagKind kind, {double chamfer = SheetLook.tagChamfer, double round = SheetLook.tagRound, double width = 1}) {
  final x0 = box.left + .5, y = box.top + .5, x1 = box.right - .5, h = box.height - 1, yb = y + h, w = x1 - x0, d = width / 2;
  final (c, r) = _tagCorners(w, h, chamfer, round);
  return Path()
    ..fillType = PathFillType.evenOdd
    ..addPath(_tagOutline(x0 - d, y - d, x1 + d, yb + d, kind, c + _chamferGrow(d), r + d), Offset.zero)
    ..addPath(_tagOutline(x0 + d, y + d, x1 - d, yb - d, kind, math.max(0, c - _chamferGrow(d)), math.max(0, r - d)), Offset.zero);
}

/// 흰 이름 종이 윤곽(왼쪽 모따기 3) — 단추 · 고르는 칸 · 사슬 고리 · 사건 점 칩.
Path sheetPaperPath(Rect box) => sheetTagPath(box, SheetTagKind.cham, chamfer: SheetLook.paperChamfer);

/// 상자 윤곽(네 귀 모따기 6) — 테는 반 픽셀 안쪽.
Path sheetBoxPath(Rect box, {double chamfer = SheetLook.boxChamfer}) =>
    _boxOutline(box.left + .5, box.top + .5, box.right - .5, box.bottom - .5, chamfer);

/// 상자 테를 칠할 고리(짝홀 채움 · 굵기 1) — [sheetTagRing]과 같은 까닭으로 획 대신.
Path sheetBoxRing(Rect box, {double chamfer = SheetLook.boxChamfer}) {
  final x0 = box.left + .5, y = box.top + .5, x1 = box.right - .5, yb = box.bottom - .5, d = .5;
  return Path()
    ..fillType = PathFillType.evenOdd
    ..addPath(_boxOutline(x0 - d, y - d, x1 + d, yb + d, chamfer + _chamferGrow(d)), Offset.zero)
    ..addPath(_boxOutline(x0 + d, y + d, x1 - d, yb - d, math.max(0, chamfer - _chamferGrow(d))), Offset.zero);
}

Path _boxOutline(double x0, double y, double x1, double yb, double c) => Path()
  ..moveTo(x0 + c, y)
  ..lineTo(x1 - c, y)
  ..lineTo(x1, y + c)
  ..lineTo(x1, yb - c)
  ..lineTo(x1 - c, yb)
  ..lineTo(x0 + c, yb)
  ..lineTo(x0, yb - c)
  ..lineTo(x0, y + c)
  ..close();

/// 상자 뚜껑의 칠 자리(위 두 귀 모따기 · 아래는 뚜껑 밑선까지).
Path sheetLidPath(Rect box, {double chamfer = SheetLook.boxChamfer, double lid = SheetLook.boxLid}) {
  final x0 = box.left + .5, y = box.top + .5, x1 = box.right - .5, c = chamfer;
  return Path()
    ..moveTo(x0, y + c)
    ..lineTo(x0 + c, y)
    ..lineTo(x1 - c, y)
    ..lineTo(x1, y + c)
    ..lineTo(x1, y + lid)
    ..lineTo(x0, y + lid)
    ..close();
}

/// 뚜껑 밑선의 y(반 픽셀 — 상자 윗변에서) — 실의 첫 매듭이 이 선 위에 앉는다.
double sheetLidLineY(double boxTop) => boxTop + .5 + SheetLook.boxLid;

/// 어깨 탭(간지 탭) — 종이 윗변이 어깨로 솟은 꼴. [stroke]는 탭의 테(밑변 없음), [fill]은 몸통 윗테를 덮도록 밑변 아래 1.5까지 닫은 칠.
({Path fill, Path stroke}) sheetTabPath(double xL, double xR, double yBase, {double height = SheetLook.folderTab, double shoulder = SheetLook.folderTabShoulder}) {
  final yT = yBase - height, s = shoulder;
  Path line() => Path()
    ..moveTo(xL, yBase)
    ..cubicTo(xL + s * .55, yBase, xL + s * .45, yT, xL + s, yT)
    ..lineTo(xR - s, yT)
    ..cubicTo(xR - s * .45, yT, xR - s * .55, yBase, xR, yBase);
  final fill = line()
    ..lineTo(xR, yBase + 1.5)
    ..lineTo(xL, yBase + 1.5)
    ..close();
  return (fill: fill, stroke: line());
}

/// 꼬리표 구멍의 가운데 — 왼쪽 테에서 7(둥근 끝 9) · 윗테에서 6. 키 20 아래의 작은 꼬리표는 4.5 · 4.5(목업 sheet-menu `tag`).
Offset sheetHoleAt(Rect box, SheetTagKind kind) {
  final big = box.height >= 20;
  final dx = big ? (kind == SheetTagKind.key ? SheetLook.holeLeftRound : SheetLook.holeLeft) : 4.5;
  return Offset(box.left + .5 + dx, box.top + .5 + (big ? SheetLook.holeTop : 4.5));
}

/// 꼬리 마름모의 가운데 — 오른쪽 테에서 7 · 구멍과 같은 높이.
Offset sheetDiamondAt(Rect box) => Offset(box.right - .5 - SheetLook.diamondRight, box.top + .5 + SheetLook.holeTop);

/// 마름모 길(반 대각선 [half]).
Path sheetDiamondPath(Offset c, {double half = SheetLook.diamondHalf}) => Path()
  ..moveTo(c.dx, c.dy - half)
  ..lineTo(c.dx + half, c.dy)
  ..lineTo(c.dx, c.dy + half)
  ..lineTo(c.dx - half, c.dy)
  ..close();

/// 열쇠표의 45° 실 — 꼬리표 윗변의 [from]에서 열쇠표 구멍 [hole]까지(목업 sheet-succ `keyTag`).
Path sheetKeyThreadPath(Offset from, Offset hole) => Path()
  ..moveTo(from.dx, from.dy)
  ..lineTo(hole.dx, hole.dy);

/// 점선으로 자른 길 — [pattern]은 긋고 띄우는 길이의 되풀이(대립 '3 2' · 얹은 트랙 '2 2').
Path sheetDashed(Path source, List<double> pattern) {
  final out = Path();
  if (pattern.isEmpty) return out..addPath(source, Offset.zero);
  for (final metric in source.computeMetrics()) {
    var d = 0.0, i = 0;
    while (d < metric.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) out.addPath(metric.extractPath(d, math.min(d + len, metric.length)), Offset.zero);
      d += len;
      i++;
    }
  }
  return out;
}

// ---- 칠하는 값 ----

/// 서고 부품 하나의 바탕 — 윤곽(꼬리표 · 이름 종이 · 둥근 네모) · 칠 · 테 · 구멍 · 점 · 안쪽 겹선. 글은 위젯이 따로 얹는다.
/// 값이라 검사가 바로 읽는다(끈 칩의 [dash]가 없음 · 테가 먹 25 따위).
@immutable
class SheetShape {
  const SheetShape({
    this.kind = SheetTagKind.cham,
    this.chamfer = SheetLook.tagChamfer,
    this.round = SheetLook.tagRound,
    this.radius,
    this.fill = SheetLook.paper,
    this.stroke,
    this.strokeWidth = 1,
    this.dash,
    this.hole = false,
    this.holeFill = SheetLook.paper,
    this.holeStroke = SheetLook.ink45,
    this.holeRadius = SheetLook.holeRadius,
    this.holeAt,
    this.dot,
    this.dotFill,
    this.dotStroke,
    this.dotRadius = SheetLook.dotRadius,
    this.inner,
  });

  final SheetTagKind kind;
  final double chamfer, round;

  /// 주면 꼬리표가 아니라 둥근 네모(폴더 칩 6).
  final double? radius;
  final Color fill;

  /// 테(없으면 테 없음). 무리 꼬리표는 테를 긋지 않는다.
  final Color? stroke;
  final double strokeWidth;

  /// 점선 테 — 대립 · 얹은 트랙만. 끈 칩 · 꺼 둔 줄은 늘 null(실선).
  final List<double>? dash;

  final bool hole;
  final Color holeFill, holeStroke;
  final double holeRadius;

  /// 구멍 자리를 따로 줄 때(열쇠표 — 왼쪽 6 · 가운데). 없으면 [sheetHoleAt].
  final Offset? holeAt;

  /// 사건 점의 가운데(없으면 점 없음) · 칠 · 테 · 반지름.
  final Offset? dot;
  final Color? dotFill, dotStroke;
  final double dotRadius;

  /// 안쪽 겹선(폴더 칩 — 안으로 2 · 둥근 4 · 먹 12).
  final Color? inner;

  static Rect _boxOf(Size size) => Offset.zero & size;

  /// 가운데 줄 윤곽(칠 · 점선 · 검사의 자리) — 실선 테는 이 줄을 가운데로 한 고리를 칠한다.
  Path outline(Size size) {
    final box = Offset.zero & size;
    final r = radius;
    if (r != null) return Path()..addRRect(RRect.fromRectAndRadius(box.deflate(.5), Radius.circular(r)));
    return sheetTagPath(box, kind, chamfer: chamfer, round: round);
  }

  void paint(Canvas canvas, Size size) {
    final path = outline(size);
    final paint = Paint()..isAntiAlias = true;
    if (fill.a > 0) canvas.drawPath(path, paint..style = PaintingStyle.fill..color = fill);
    final innerColor = inner;
    if (innerColor != null && radius != null) {
      final inset = Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5);
      canvas.drawRRect(RRect.fromRectAndRadius(inset, const Radius.circular(SheetLook.scopeInnerRadius)), paint..style = PaintingStyle.stroke..strokeWidth = 1..color = innerColor);
    }
    final edge = stroke;
    if (edge != null && (kind != SheetTagKind.plain || radius != null)) {
      final pattern = dash, r = radius, d = strokeWidth / 2;
      if (pattern != null) {
        // 점선(대립 · 얹은 트랙)만 가운데 줄을 잘라 획으로 — 조각마다 짧아 이음 탓의 옅어짐이 없다.
        canvas.drawPath(sheetDashed(path, pattern), paint..style = PaintingStyle.stroke..strokeWidth = strokeWidth..color = edge);
      } else if (r != null) {
        // 실선은 고리 칠([sheetTagRing]의 까닭) — 둥근 네모는 두 겹 둥근 네모 사이를 칠한다.
        final mid = _boxOf(size).deflate(.5);
        canvas.drawDRRect(
          RRect.fromRectAndRadius(mid.inflate(d), Radius.circular(r + d)),
          RRect.fromRectAndRadius(mid.deflate(d), Radius.circular(math.max(0, r - d))),
          paint..style = PaintingStyle.fill..color = edge,
        );
      } else {
        canvas.drawPath(sheetTagRing(_boxOf(size), kind, chamfer: chamfer, round: round, width: strokeWidth), paint..style = PaintingStyle.fill..color = edge);
      }
    }
    if (hole) {
      final c = holeAt ?? sheetHoleAt(Offset.zero & size, kind);
      canvas.drawCircle(c, holeRadius, paint..style = PaintingStyle.fill..color = holeFill);
      canvas.drawCircle(c, holeRadius, paint..style = PaintingStyle.stroke..strokeWidth = 1..color = holeStroke);
    }
    final d = dot;
    if (d != null) {
      final f = dotFill, s = dotStroke;
      if (f != null) canvas.drawCircle(d, dotRadius, paint..style = PaintingStyle.fill..color = f);
      if (s != null) canvas.drawCircle(d, dotRadius, paint..style = PaintingStyle.stroke..strokeWidth = 1..color = s);
    }
  }

  /// 빛깔만 사이 값으로(올림 · 켬끔의 120ms) — 꼴 · 자리는 [b]의 것.
  static SheetShape lerp(SheetShape a, SheetShape b, double t) {
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    Color? maybe(Color? x, Color? y) => x == null || y == null ? y : mix(x, y);
    return SheetShape(
      kind: b.kind, chamfer: b.chamfer, round: b.round, radius: b.radius, fill: mix(a.fill, b.fill), stroke: maybe(a.stroke, b.stroke),
      strokeWidth: b.strokeWidth, dash: b.dash, hole: b.hole, holeFill: mix(a.holeFill, b.holeFill), holeStroke: mix(a.holeStroke, b.holeStroke),
      holeRadius: b.holeRadius, holeAt: b.holeAt, dot: b.dot, dotFill: maybe(a.dotFill, b.dotFill), dotStroke: maybe(a.dotStroke, b.dotStroke),
      dotRadius: b.dotRadius, inner: maybe(a.inner, b.inner),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SheetShape && other.kind == kind && other.chamfer == chamfer && other.round == round && other.radius == radius && other.fill == fill &&
      other.stroke == stroke && other.strokeWidth == strokeWidth && _sameList(other.dash, dash) && other.hole == hole && other.holeFill == holeFill &&
      other.holeStroke == holeStroke && other.holeRadius == holeRadius && other.holeAt == holeAt && other.dot == dot && other.dotFill == dotFill &&
      other.dotStroke == dotStroke && other.dotRadius == dotRadius && other.inner == inner;

  @override
  int get hashCode => Object.hash(kind, chamfer, round, radius, fill, stroke, strokeWidth, dash == null ? null : Object.hashAll(dash!), hole, holeFill, holeStroke, holeRadius, holeAt, dot, dotFill, dotStroke, dotRadius, inner);

  static bool _sameList(List<double>? a, List<double>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _ShapeTween extends Tween<SheetShape> {
  _ShapeTween({super.end});
  @override
  SheetShape lerp(double t) => SheetShape.lerp(begin!, end!, t);
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.shape);
  final SheetShape shape;
  @override
  void paint(Canvas canvas, Size size) => shape.paint(canvas, size);
  @override
  bool shouldRepaint(_ShapePainter old) => old.shape != shape;
}

/// [shape]를 바탕에 그리고 [child]를 얹는다. 빛깔이 바뀌면 [Motion.microMs]로 넘어간다(색 변화 토큰).
class SheetShapeBox extends StatelessWidget {
  const SheetShapeBox({super.key, required this.shape, required this.child});
  final SheetShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<SheetShape>(
    tween: _ShapeTween(end: shape),
    duration: const Duration(milliseconds: Motion.microMs),
    curve: Ui.ease,
    builder: (context, value, child) => CustomPaint(painter: _ShapePainter(value), child: child),
    child: SheetPixelBox(child: child),
  );
}

// ---- 화소 맞춤 ----

/// 자식의 폭 · 키를 정수로 올린다 — 반 픽셀 테가 화소 한 줄에 앉게(목업이 폭을 `Math.round`하는 자리).
class SheetPixelBox extends SingleChildRenderObjectWidget {
  const SheetPixelBox({super.key, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPixelBox();
}

class _RenderPixelBox extends RenderProxyBox {
  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(Size(c.size.width.ceilToDouble(), c.size.height.ceilToDouble()));
  }

  @override
  double computeMinIntrinsicWidth(double height) => super.computeMinIntrinsicWidth(height).ceilToDouble();
  @override
  double computeMaxIntrinsicWidth(double height) => super.computeMaxIntrinsicWidth(height).ceilToDouble();
  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final s = child?.getDryLayout(constraints) ?? constraints.smallest;
    return constraints.constrain(Size(s.width.ceilToDouble(), s.height.ceilToDouble()));
  }
}

// ---- 글 ----

/// 시트의 글 꼴 — 크기 · 굵기 · 먹. 줄 높이 1(칸 가운데에 세움).
TextStyle sheetText(double size, {bool bold = false, Color color = SheetLook.ink85}) =>
    TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color, height: 1, leadingDistribution: TextLeadingDistribution.even);

Widget _line(String text, TextStyle style) => Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);

// ---- 누름 ----

/// 누르는 부품의 겉 — 올림(마우스) 또는 키보드 초점의 표시 상태를 [builder]에 주고, 누름은 [MotionPress] 하나,
/// 키보드(스페이스 · 엔터) · 스크린 리더도 같은 길. 읽기 글은 부품마다 제 마디(container)이고, [label]이 있으면 안의 글 대신 그 글 하나를 읽는다(공용 부품 `_ControlAction`과 같게).
/// [hint]는 올리면 뜨는 풍선.
class _Press extends StatefulWidget {
  const _Press({required this.builder, this.onTap, this.label, this.selected, this.toggled, this.hint, this.autofocus = false});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;
  final String? label, hint;
  final bool? selected, toggled;
  final bool autofocus;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _hover = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    Widget body = Semantics(
      container: true,
      button: widget.toggled == null,
      enabled: on,
      label: widget.label,
      excludeSemantics: widget.label != null,
      selected: widget.selected,
      toggled: widget.toggled,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        enabled: on,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (v) {
          if (mounted && v != _focus) setState(() => _focus = v);
        },
        mouseCursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        shortcuts: const {SingleActivator(LogicalKeyboardKey.space): ActivateIntent(), SingleActivator(LogicalKeyboardKey.enter): ActivateIntent()},
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.onTap,
            child: MotionPress(enabled: on, child: widget.builder((_hover || _focus) && on)),
          ),
        ),
      ),
    );
    if (widget.hint != null) body = Tooltip(message: widget.hint!, child: body);
    return body;
  }
}

/// 누르는 겉을 다른 파일의 서고 부품이 쓰게 연 것(문서 창의 목차 줄 · 하위 문서 칩 · 대문 카드 — [_Press]와 같은 길):
/// 올림 · 키보드 초점의 표시 상태를 [builder]에 주고, 누름은 [MotionPress] 하나 · 스페이스 · 엔터 · 스크린 리더도 같은 길 ·
/// 읽기 글은 제 마디([label]이 있으면 그 글 하나) · [hint]는 풍선.
class SheetPress extends StatelessWidget {
  const SheetPress({super.key, required this.builder, this.onTap, this.label, this.hint, this.selected});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;
  final String? label, hint;
  final bool? selected;

  @override
  Widget build(BuildContext context) => _Press(builder: builder, onTap: onTap, label: label, hint: hint, selected: selected);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  그릇 — 폴더 · 상자
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 폴더 시트(창): 어깨 탭 20 안에 **맨 글** 12 굵게 + 수 12 먹 45(흰 라벨 없음 — 흰 라벨은 상자 뚜껑에만) ·
/// 몸통 둥근 10 · 칠 먹 4 · 테 먹 25 · 안쪽 겹선 먹 12 · 흰 둘레 6. [color]를 주면 나라 시트(제 색 9% · 테 55% · 탭 글 25% + 먹).
/// [onClose]면 오른쪽 끝에 닫기 탭(✕), [tabRight]면 이름 탭이 오른쪽(차림표 — 연 단추 밑). 폭 · 키는 정수로 올린다.
class SheetFolder extends StatelessWidget {
  const SheetFolder({
    super.key,
    required this.label,
    required this.child,
    this.count,
    this.color,
    this.onClose,
    this.tabRight = false,
    this.padding = const EdgeInsets.all(14),
    this.closeLabel = '닫기',
  });

  final String label;
  final String? count;
  final Color? color;
  final VoidCallback? onClose;
  final bool tabRight;
  final EdgeInsets padding;
  final String closeLabel;
  final Widget child;

  Color get _fill => color == null ? SheetLook.ink4 : SheetLook.folderFill(color!);
  Color get _edge => color == null ? SheetLook.ink25 : SheetLook.folderEdge(color!);
  Color get _ink => color == null ? SheetLook.ink85 : SheetLook.folderInk(color!);
  Color get _back => color == null ? SheetLook.ink12 : SheetLook.folderBack(color!);

  @override
  Widget build(BuildContext context) {
    final tab = SheetFolderTab(
      fill: _fill,
      edge: _edge,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _line(label, sheetText(SheetLook.folderTabText, bold: true, color: _ink)),
        if (count != null) ...[
          const SizedBox(width: SheetLook.folderTabCountGap),
          _line(count!, sheetText(SheetLook.folderTabText, color: SheetLook.ink45)),
        ],
      ]),
    );
    return SheetPixelBox(
      child: Stack(clipBehavior: Clip.none, children: [
        Padding(
          padding: const EdgeInsets.only(top: SheetLook.folderTab),
          child: CustomPaint(painter: _FolderBodyPainter(_fill, _edge, _back), child: Padding(padding: padding, child: child)),
        ),
        // 오른쪽 탭은 테 자리(반 픽셀)를 왼쪽 탭과 맞추려 1 더 들인다 — 목업 sheet-menu `folder`의 `X0 + Wd − 1 − 12 − 탭 폭`.
        Positioned(left: tabRight ? null : SheetLook.folderTabInset, right: tabRight ? SheetLook.folderTabInset + 1 : null, top: 0, child: tab),
        if (onClose != null)
          Positioned(
            right: SheetLook.folderTabInset + 1,
            top: 0,
            child: _Press(
              onTap: onClose,
              label: closeLabel,
              builder: (hover) => SheetFolderTab(
                fill: hover ? SheetLook.paper : _fill,
                edge: _edge,
                pad: 0,
                child: const SizedBox(
                  width: SheetLook.folderCloseTab,
                  child: Center(child: LineIcon(LineGlyph.x, size: SheetLook.folderCloseIcon, color: SheetLook.ink60)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 폴더의 어깨 탭 하나 — 키 20 · 어깨 8 · 글 앞뒤 [pad]. 칠은 밑변 아래 1.5까지 내려 몸통 윗테를 덮는다(탭과 몸통이 한 장).
/// 바깥 상자의 왼쪽 위가 탭 발(반 픽셀 안쪽 .5)이다.
class SheetFolderTab extends StatelessWidget {
  const SheetFolderTab({super.key, required this.fill, required this.edge, required this.child, this.pad = SheetLook.folderTabPad});
  final Color fill, edge;
  final double pad;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TabPainter(fill, edge),
    child: SizedBox(
      height: SheetLook.folderTab,
      child: SheetPixelBox(
        child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Center(widthFactor: 1, child: child)),
      ),
    ),
  );
}

class _TabPainter extends CustomPainter {
  const _TabPainter(this.fill, this.edge);
  final Color fill, edge;

  @override
  void paint(Canvas canvas, Size size) {
    final tab = sheetTabPath(.5, size.width + .5, SheetLook.folderTab + .5);
    canvas.drawPath(tab.fill, Paint()..color = fill);
    canvas.drawPath(tab.stroke, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = edge);
  }

  @override
  bool shouldRepaint(_TabPainter old) => old.fill != fill || old.edge != edge;
}

class _FolderBodyPainter extends CustomPainter {
  const _FolderBodyPainter(this.fill, this.edge, this.back);
  final Color fill, edge, back;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, rim = SheetLook.folderRim;
    // 흰 둘레 — 탭 줄까지 덮는다(몸통 윗변 위 20이 폴더 윗변).
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-rim, -SheetLook.folderTab - rim, w + 2 * rim, h + SheetLook.folderTab + 2 * rim), const Radius.circular(SheetLook.folderRimRadius)),
      Paint()..color = SheetLook.paper,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(.5 + SheetLook.folderBackInset, .5 - SheetLook.folderBackRise), Offset(w - .5 - SheetLook.folderBackInset, .5 - SheetLook.folderBackRise), line..color = back);
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(.5, .5, w - 1, h - 1), const Radius.circular(SheetLook.folderRadius));
    canvas.drawRRect(body, Paint()..color = fill);
    canvas.drawRRect(body, line..color = edge);
    final i = SheetLook.folderInnerInset;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(.5 + i, .5 + i, w - 1 - 2 * i, h - 1 - 2 * i), const Radius.circular(SheetLook.folderInnerRadius)), line..color = SheetLook.ink12);
  }

  @override
  bool shouldRepaint(_FolderBodyPainter old) => old.fill != fill || old.edge != edge || old.back != back;
}

/// 상자(묶음): 모따기 6 · 테 먹 25 · 몸 흰 종이 · 뚜껑 22(먹 4 + 밑선 먹 12) 안 **흰 라벨**(11 굵게) + 수 + 오른쪽 안내 글([hint]) 또는 [trailing].
/// 몸의 [child]는 뚜껑 밑선 아래 [padding] 안 — 그 안의 [SheetThreadColumn]은 [SheetBox.knotOf]로 뚜껑 밑선(실의 첫 매듭) 자리를 받는다.
/// [fill]이면 상자가 받은 키를 몸이 다 받는다(옆 상자와 키를 맞춘 DLC 관리의 자세히 — 몸 안의 [Expanded]가 남는 키를 갖는다).
class SheetBox extends StatelessWidget {
  const SheetBox({super.key, required this.label, required this.child, this.count, this.hint, this.trailing, this.padding = const EdgeInsets.all(SheetLook.boxInset), this.fill = false});
  final String label;
  final String? count, hint;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool fill;
  final Widget child;

  /// 이 상자 안 몸의 맨 위(패딩 안쪽)에서 본 뚜껑 밑선의 y(음수 · 반 픽셀). 상자 밖이면 null.
  static double? knotOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_LidScope>()?.knot;

  @override
  Widget build(BuildContext context) {
    final right = trailing ?? (hint == null ? null : _line(hint!, sheetText(SheetLook.boxLabelText, color: SheetLook.ink45)));
    final body = Padding(
      padding: padding,
      child: _LidScope(knot: -(padding.top + .5), child: child),
    );
    return SheetPixelBox(
      child: CustomPaint(
        painter: const _BoxPainter(),
        child: Column(mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: SheetLook.boxLid + 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SheetLook.boxInset),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: SheetLook.boxLabelTop), child: SheetLidLabel(label)),
                if (count != null)
                  SizedBox(
                    height: SheetLook.boxLid + 1,
                    child: Padding(
                      padding: const EdgeInsets.only(left: SheetLook.boxCountGap),
                      child: Center(widthFactor: 1, child: _line(count!, sheetText(SheetLook.boxLabelText, color: SheetLook.ink45))),
                    ),
                  ),
                if (right != null) ...[const Spacer(), SizedBox(height: SheetLook.boxLid + 1, child: Center(widthFactor: 1, child: right))],
              ]),
            ),
          ),
          if (fill) Expanded(child: body) else body,
        ]),
      ),
    );
  }
}

class _LidScope extends InheritedWidget {
  const _LidScope({required this.knot, required super.child});
  final double knot;
  @override
  bool updateShouldNotify(_LidScope old) => old.knot != knot;
}

class _BoxPainter extends CustomPainter {
  const _BoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size, outline = sheetBoxPath(box);
    canvas.drawPath(outline, Paint()..color = SheetLook.paper);
    canvas.drawPath(sheetLidPath(box), Paint()..color = SheetLook.ink4);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final lid = sheetLidLineY(0);
    canvas.drawLine(Offset(.5, lid), Offset(size.width - .5, lid), line..color = SheetLook.ink12);
    // 테는 획이 아니라 고리 칠([sheetTagRing]의 까닭).
    canvas.drawPath(sheetBoxRing(box), Paint()..color = SheetLook.ink25);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => false;
}

/// 상자 뚜껑 안의 흰 라벨 — 키 16 · 둥근 2 · 테 먹 45 · 글 11 굵게 먹 85(앞뒤 6). 흰 라벨은 **상자 뚜껑에만** 쓴다(폴더 탭은 맨 글).
class SheetLidLabel extends StatelessWidget {
  const SheetLidLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _LidLabelPainter(),
    child: SizedBox(
      height: SheetLook.boxLabel,
      child: SheetPixelBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SheetLook.boxLabelPad),
          child: Center(widthFactor: 1, child: _line(label, sheetText(SheetLook.boxLabelText, bold: true))),
        ),
      ),
    ),
  );
}

class _LidLabelPainter extends CustomPainter {
  const _LidLabelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(.5, .5, size.width, size.height), const Radius.circular(SheetLook.boxLabelRadius));
    canvas.drawRRect(r, Paint()..color = SheetLook.paper);
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = SheetLook.ink45);
  }

  @override
  bool shouldRepaint(_LidLabelPainter old) => false;
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  실 기둥 — 뚜껑 밑선의 매듭에서 줄마다 구멍으로
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 줄(꼬리표)들을 위에서 아래로 세우고, 그 **뒤**에 실을 긋는다(먹 45 · 1px · 매듭 1.5).
///  · 기둥(기본 — 차림표 · DLC 관리): 첫 매듭(상자 안이면 뚜껑 밑선 — [SheetBox.knotOf])에서 곧게 내려와 줄마다 구멍을 지나 마지막 구멍까지.
///  · 가로대([rails] — 검색 결과): 줄 사이마다 가로대(먹 12 · 기둥 양옆 [railOutset]까지)를 긋고, 줄마다 바로 위 가로대(첫 줄은 뚜껑 밑선)의
///    매듭에서 제 구멍으로 짧은 실. 줄 사이 틈은 [gap]으로 두고 가로대는 그 가운데(반 픽셀)에 선다.
/// 구멍은 줄 꼬리표가 스스로 그린다(실 위에 종이 칠) — 실은 구멍 위 3에서 멎는다. 구멍 자리는 줄의 바깥 상자와 [kinds](줄마다 · 없으면 [kind])로 셈한다.
/// [breakBefore]의 줄 앞에는 [breakGap]을 더 띄운다(차림표의 작은 묶음).
class SheetThreadColumn extends StatelessWidget {
  const SheetThreadColumn({
    super.key,
    required this.children,
    this.gap = 4,
    this.kind = SheetTagKind.cham,
    this.kinds,
    this.rails = false,
    this.railOutset = SheetLook.boxInset - 1.5,
    this.knot,
    this.breakBefore = const {},
    this.breakGap = 6,
  });

  final List<Widget> children;
  final double gap, railOutset, breakGap;
  final SheetTagKind kind;
  final List<SheetTagKind>? kinds;
  final bool rails;

  /// 첫 매듭의 y(이 기둥 맨 위에서 — 음수면 위). 없으면 상자의 뚜껑 밑선, 상자 밖이면 첫 줄 위 [gap]/2.
  final double? knot;
  final Set<int> breakBefore;

  @override
  Widget build(BuildContext context) => _ThreadColumn(
    gap: gap,
    kinds: [for (var i = 0; i < children.length; i++) kinds != null && i < kinds!.length ? kinds![i] : kind],
    rails: rails,
    railOutset: railOutset,
    knot: knot ?? SheetBox.knotOf(context),
    breakBefore: breakBefore,
    breakGap: breakGap,
    children: children,
  );
}

class _ThreadColumn extends MultiChildRenderObjectWidget {
  const _ThreadColumn({required super.children, required this.gap, required this.kinds, required this.rails, required this.railOutset, required this.knot, required this.breakBefore, required this.breakGap});
  final double gap, railOutset, breakGap;
  final List<SheetTagKind> kinds;
  final bool rails;
  final double? knot;
  final Set<int> breakBefore;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderThreadColumn(gap, kinds, rails, railOutset, knot, breakBefore, breakGap);

  @override
  void updateRenderObject(BuildContext context, _RenderThreadColumn r) => r
    ..gap = gap
    ..kinds = kinds
    ..rails = rails
    ..railOutset = railOutset
    ..knot = knot
    ..breakBefore = breakBefore
    ..breakGap = breakGap;
}

class _ThreadData extends ContainerBoxParentData<RenderBox> {}

class _RenderThreadColumn extends RenderBox with ContainerRenderObjectMixin<RenderBox, _ThreadData>, RenderBoxContainerDefaultsMixin<RenderBox, _ThreadData> {
  _RenderThreadColumn(this._gap, this._kinds, this._rails, this._railOutset, this._knot, this._breakBefore, this._breakGap);

  double _gap, _railOutset, _breakGap;
  List<SheetTagKind> _kinds;
  bool _rails;
  double? _knot;
  Set<int> _breakBefore;

  set gap(double v) => _set(_gap != v, () => _gap = v, layout: true);
  set kinds(List<SheetTagKind> v) => _set(!listEquals(_kinds, v), () => _kinds = v);
  set rails(bool v) => _set(_rails != v, () => _rails = v);
  set railOutset(double v) => _set(_railOutset != v, () => _railOutset = v);
  set knot(double? v) => _set(_knot != v, () => _knot = v);
  set breakBefore(Set<int> v) => _set(!setEquals(_breakBefore, v), () => _breakBefore = v, layout: true);
  set breakGap(double v) => _set(_breakGap != v, () => _breakGap = v, layout: true);

  void _set(bool changed, VoidCallback apply, {bool layout = false}) {
    if (!changed) return;
    apply();
    if (layout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ThreadData) child.parentData = _ThreadData();
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
    final inner = width == null ? const BoxConstraints() : BoxConstraints.tightFor(width: width);
    var y = 0.0, widest = 0.0, i = 0;
    for (var child = firstChild; child != null; child = childAfter(child), i++) {
      if (i > 0) y += _gap + (_breakBefore.contains(i) ? _breakGap : 0);
      child.layout(inner, parentUsesSize: true);
      (child.parentData as _ThreadData).offset = Offset(0, y);
      y += child.size.height;
      widest = math.max(widest, child.size.width);
    }
    size = constraints.constrain(Size(width ?? widest, y));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _sumHeight((c) => c.getMinIntrinsicHeight(width));
  @override
  double computeMaxIntrinsicHeight(double width) => _sumHeight((c) => c.getMaxIntrinsicHeight(width));
  @override
  double computeMinIntrinsicWidth(double height) => _maxWidth((c) => c.getMinIntrinsicWidth(height));
  @override
  double computeMaxIntrinsicWidth(double height) => _maxWidth((c) => c.getMaxIntrinsicWidth(height));

  double _sumHeight(double Function(RenderBox) of) {
    var y = 0.0, i = 0;
    for (var child = firstChild; child != null; child = childAfter(child), i++) {
      if (i > 0) y += _gap + (_breakBefore.contains(i) ? _breakGap : 0);
      y += of(child);
    }
    return y;
  }

  double _maxWidth(double Function(RenderBox) of) {
    var w = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      w = math.max(w, of(child));
    }
    return w;
  }

  /// 줄마다의 구멍 가운데(이 기둥 안 자리) — 검사도 읽는다.
  List<Offset> get holes {
    final out = <Offset>[];
    var i = 0;
    for (var child = firstChild; child != null; child = childAfter(child), i++) {
      final at = (child.parentData as _ThreadData).offset;
      out.add(sheetHoleAt(at & child.size, i < _kinds.length ? _kinds[i] : SheetTagKind.cham));
    }
    return out;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final holes = this.holes;
    if (holes.isNotEmpty) {
      final canvas = context.canvas;
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SheetLook.threadWidth
        ..color = SheetLook.threadInk;
      final dot = Paint()..color = SheetLook.threadInk;
      final rail12 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = SheetLook.ink12;
      final first = _knot ?? -(_gap / 2).floorToDouble() - .5;
      if (_rails) {
        var i = 0;
        for (var child = firstChild; child != null; child = childAfter(child), i++) {
          final top = (child.parentData as _ThreadData).offset.dy;
          final rail = i == 0 ? first : top - (_gap / 2).floorToDouble() - .5;
          if (i > 0) canvas.drawLine(offset + Offset(-_railOutset, rail), offset + Offset(size.width + _railOutset, rail), rail12);
          final h = holes[i];
          canvas.drawLine(offset + Offset(h.dx, rail + SheetLook.knotRadius), offset + Offset(h.dx, h.dy - SheetLook.threadStop), line);
          canvas.drawCircle(offset + Offset(h.dx, rail), SheetLook.knotRadius, dot);
        }
      } else {
        final x = holes.first.dx;
        canvas.drawLine(offset + Offset(x, first + SheetLook.knotRadius), offset + Offset(x, holes.last.dy - SheetLook.threadStop), line);
        canvas.drawCircle(offset + Offset(x, first), SheetLook.knotRadius, dot);
      }
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  꼬리표 · 칩
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 꼬리표 하나(줄 · 견본의 바탕) — [shape]의 윤곽 · 칠 · 테 · 구멍 위에 [child]. 키는 [height](없으면 자식 키), 폭은 정수로 올린다.
class SheetTag extends StatelessWidget {
  const SheetTag({super.key, required this.shape, required this.child, this.height});
  final SheetShape shape;
  final double? height;
  final Widget child;

  /// 흰 꼬리표 줄(차림표 · DLC · 문서의 줄): 흰 종이 · 테 먹 25(켬 · 올림이면 45) · 구멍(켬 = 먹 85 칠) · 올리면 칠 먹 4.
  static SheetShape row({SheetTagKind kind = SheetTagKind.cham, bool on = false, bool hover = false, bool off = false}) => SheetShape(
    kind: kind,
    fill: hover ? SheetLook.ink4 : SheetLook.paper,
    stroke: off ? SheetLook.ink25 : (on || hover ? SheetLook.ink45 : SheetLook.ink25),
    hole: kind != SheetTagKind.plain,
    holeFill: on ? SheetLook.ink85 : SheetLook.paper,
    holeStroke: on ? SheetLook.ink85 : (off ? SheetLook.ink25 : SheetLook.ink45),
  );

  /// 나라 색 꼬리표(검색의 객체 줄 · 승계표 · 단체 계보의 이름띠): 칠 24% · 테 84% + 먹 · 구멍. 대립이면 점선 테 '3 2'.
  static SheetShape colored(Color c, {SheetTagKind kind = SheetTagKind.cham, bool rival = false}) => SheetShape(
    kind: kind,
    fill: SheetLook.tagFill(c),
    stroke: kind == SheetTagKind.plain ? null : SheetLook.tagEdge(c),
    dash: rival ? const [3, 2] : null,
    hole: kind != SheetTagKind.plain,
  );

  @override
  Widget build(BuildContext context) {
    Widget body = child;
    if (height != null) body = SizedBox(height: height, child: body);
    return SheetShapeBox(shape: shape, child: body);
  }
}

/// 누르는 나라 색 꼬리표(단체 계보 창 머리의 나라 꼬리표 · '고른 단체' 상자의 이어짐 꼬리표 — 목업 g-sheet-tree `tag`):
/// 칠 제 색 24% · 테 84% + 먹 · 구멍 · 글 [text] 굵게 탭 글(제 색 22% + 먹)이 구멍 뒤 7에서 · 뒤 [tail] · 올리면 칠에 먹 4%.
/// 켜고 끄는 칩([SheetTagChip])과 달리 켬 · 끔이 없는 단추다(읽기 글 = [semantics] 또는 글).
class SheetTagButton extends StatelessWidget {
  const SheetTagButton({super.key, required this.label, required this.color, this.onTap, this.kind = SheetTagKind.cham, this.height = SheetLook.chip, this.text = 11, this.tail = 13.5, this.hint, this.semantics});
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final SheetTagKind kind;
  final double height, text, tail;
  final String? hint, semantics;

  /// 올림 — 칠 위에 먹 4%(검색 결과 · 승계표의 꼬리표 줄과 같은 셈).
  static Color lift(Color fill) => Color.alphaBlend(const Color(0x0a000000), fill);

  static SheetShape shapeOf(Color c, {SheetTagKind kind = SheetTagKind.cham, bool hover = false}) {
    final fill = SheetLook.tagFill(c);
    return SheetShape(kind: kind, fill: hover ? lift(fill) : fill, stroke: kind == SheetTagKind.plain ? null : SheetLook.tagEdge(c), hole: kind != SheetTagKind.plain);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sheetHoleAt(Rect.fromLTWH(0, 0, 40, height), kind).dx + 7;
    return _Press(
      onTap: onTap,
      label: semantics ?? label,
      hint: hint,
      builder: (hover) => SheetTag(
        shape: shapeOf(color, kind: kind, hover: hover),
        height: height,
        child: Padding(
          padding: EdgeInsets.only(left: lead, right: tail),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: sheetText(text, bold: true, color: SheetLook.tagInk(color))),
          ),
        ),
      ),
    );
  }
}

/// 꼬리표 칩(트랙 · 종류 — 필터): 키 24 · 켬 = 그림판 그대로(제 색 칠 24% · 테 84% + 먹 · 탭 글 22% + 먹 — 무리는 테 없이 이름 글 45%) ·
/// 끔 = 흰 종이 · 먹 25 **실선** · 구멍 테 먹 25 · 글 먹 45. 글 앞 15(둥근 끝 17) · 뒤 10.
class SheetTagChip extends StatelessWidget {
  const SheetTagChip({super.key, required this.label, required this.color, required this.on, this.onTap, this.kind = SheetTagKind.cham, this.hint});
  final String label;
  final String? hint;
  final Color color;
  final bool on;
  final SheetTagKind kind;
  final VoidCallback? onTap;

  /// 칩의 바탕 — 검사가 끈 칩의 실선 · 먹 25를 바로 본다.
  static SheetShape shapeOf(Color c, {required bool on, SheetTagKind kind = SheetTagKind.cham}) => SheetShape(
    kind: kind,
    fill: on ? SheetLook.tagFill(c) : SheetLook.paper,
    stroke: on ? (kind == SheetTagKind.plain ? null : SheetLook.tagEdge(c)) : SheetLook.ink25,
    hole: true,
    holeStroke: on ? SheetLook.ink45 : SheetLook.ink25,
  );

  /// 글 빛깔 — 켬: 탭 글(무리는 이름 글) · 끔: 먹 45.
  static Color inkOf(Color c, {required bool on, SheetTagKind kind = SheetTagKind.cham}) =>
      on ? (kind == SheetTagKind.plain ? SheetLook.nameInk(c) : SheetLook.tagInk(c)) : SheetLook.ink45;

  @override
  Widget build(BuildContext context) => _Press(
    onTap: onTap,
    label: label,
    toggled: on,
    hint: hint,
    builder: (_) => SheetTag(
      shape: shapeOf(color, on: on, kind: kind),
      height: SheetLook.chip,
      child: Padding(
        padding: EdgeInsets.only(left: kind == SheetTagKind.key ? SheetLook.chipLeadRound : SheetLook.chipLead, right: SheetLook.chipTail),
        child: Center(widthFactor: 1, child: _line(label, sheetText(SheetLook.chipText, bold: true, color: inkOf(color, on: on, kind: kind)))),
      ),
    ),
  );
}

/// 열쇠표 켜고 끄기(표시 — 필터 · 차림표의 글자): 둥근 끝 칩 · 흰 종이 · 켬 = 테 먹 45 · 매듭(구멍) 먹 60 칠 · 글 85 /
/// 끔 = 테 먹 25 · 빈 구멍(테 25) · 글 45.
class SheetKeyToggle extends StatelessWidget {
  const SheetKeyToggle({super.key, required this.label, required this.on, this.onTap, this.hint});
  final String label;
  final String? hint;
  final bool on;
  final VoidCallback? onTap;

  static SheetShape shapeOf({required bool on}) => SheetShape(
    kind: SheetTagKind.key,
    stroke: on ? SheetLook.ink45 : SheetLook.ink25,
    hole: true,
    holeFill: on ? SheetLook.ink60 : SheetLook.paper,
    holeStroke: on ? SheetLook.ink60 : SheetLook.ink25,
  );

  @override
  Widget build(BuildContext context) => _Press(
    onTap: onTap,
    label: label,
    toggled: on,
    hint: hint,
    builder: (_) => SheetTag(
      shape: shapeOf(on: on),
      height: SheetLook.chip,
      child: Padding(
        padding: const EdgeInsets.only(left: SheetLook.chipLeadRound, right: SheetLook.chipTail),
        child: Center(widthFactor: 1, child: _line(label, sheetText(SheetLook.chipText, bold: true, color: on ? SheetLook.ink85 : SheetLook.ink45))),
      ),
    ),
  );
}

/// 사건 점 칩(분류): 흰 이름 종이(모따기 3) · 켬 = 테 먹 45 · 점(반지름 3 · 분류 빛깔의 테 84% + 먹) · 글 85 /
/// 끔 = 테 먹 25 · 빈 점(2.5 · 테 25) · 글 45. 점 가운데 12 · 글 앞 21.
class SheetDotChip extends StatelessWidget {
  const SheetDotChip({super.key, required this.label, required this.color, required this.on, this.onTap, this.hint});
  final String label;
  final String? hint;
  final Color color;
  final bool on;
  final VoidCallback? onTap;

  static SheetShape shapeOf(Color c, {required bool on}) => SheetShape(
    chamfer: SheetLook.paperChamfer,
    stroke: on ? SheetLook.ink45 : SheetLook.ink25,
    dot: const Offset(SheetLook.dotCenter, SheetLook.dotCenter),
    dotRadius: on ? SheetLook.dotRadius : SheetLook.dotOffRadius,
    dotFill: on ? SheetLook.tagEdge(c) : SheetLook.paper,
    dotStroke: on ? null : SheetLook.ink25,
  );

  @override
  Widget build(BuildContext context) => _Press(
    onTap: onTap,
    label: label,
    toggled: on,
    hint: hint,
    builder: (_) => SheetTag(
      shape: shapeOf(color, on: on),
      height: SheetLook.chip,
      child: Padding(
        padding: const EdgeInsets.only(left: SheetLook.dotLead, right: SheetLook.chipTail),
        child: Center(widthFactor: 1, child: _line(label, sheetText(SheetLook.chipText, bold: true, color: on ? SheetLook.ink85 : SheetLook.ink45))),
      ),
    ),
  );
}

/// 폴더 칩(대범위): 둥근 6 · 켬 = 그릇 칠(제 색 9%) · 테 55% · 안쪽 겹선 먹 12 · 폴더 그림과 글 = 제 색 25% + 먹 /
/// 끔 = 흰 종이 · 먹 25 · 그림과 글 먹 45. 폴더 그림 13(왼쪽 10) · 글 앞 29.
class SheetScopeChip extends StatelessWidget {
  const SheetScopeChip({super.key, required this.label, required this.color, required this.on, this.onTap, this.hint});
  final String label;
  final String? hint;
  final Color color;
  final bool on;
  final VoidCallback? onTap;

  static SheetShape shapeOf(Color c, {required bool on}) => SheetShape(
    radius: SheetLook.scopeRadius,
    fill: on ? SheetLook.folderFill(c) : SheetLook.paper,
    stroke: on ? SheetLook.folderEdge(c) : SheetLook.ink25,
    inner: on ? SheetLook.ink12 : null,
  );

  @override
  Widget build(BuildContext context) {
    final ink = on ? SheetLook.folderInk(color) : SheetLook.ink45;
    return _Press(
      onTap: onTap,
      label: label,
      toggled: on,
      hint: hint,
      builder: (_) => SheetTag(
        shape: shapeOf(color, on: on),
        height: SheetLook.chip,
        child: Padding(
          padding: const EdgeInsets.only(left: SheetLook.scopeIconLeft, right: SheetLook.chipTail),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LineIcon(LineGlyph.folder, size: SheetLook.scopeIcon, color: ink),
            const SizedBox(width: SheetLook.scopeLead - SheetLook.scopeIconLeft - SheetLook.scopeIcon),
            _line(label, sheetText(SheetLook.chipText, bold: true, color: ink)),
          ]),
        ),
      ),
    );
  }
}

/// 흰 이름 종이 단추(도구 · 닫기 · 켜기 · 끄기): 모따기 3 · 테 먹 45 · 글 12 굵게 먹 85(앞뒤 11) · 올리면 칠 먹 4.
/// [selected]면 고른 테(먹 100 · 1.5 — 종이 테 대신), [quiet]면 테 먹 25 · 글 60(삭제처럼 한발 물러선 단추).
/// 누를 수 없으면([onTap]이 없음) 테 먹 25 · 글 먹 45로 물러선다. [semantics]를 주면 읽기 글은 보이는 글 대신 그것(줄마다의 '끄기'를
/// '〈DLC 이름〉 끄기'로 읽게).
class SheetPaperButton extends StatelessWidget {
  const SheetPaperButton({super.key, required this.label, this.onTap, this.selected = false, this.quiet = false, this.height = SheetLook.chip, this.leading, this.hint, this.semantics, this.pad = SheetLook.buttonPad});
  final String label;
  final VoidCallback? onTap;
  final bool selected, quiet;
  final double height;

  /// 글 앞뒤(기본 11). 단추가 많은 줄(승계표 좁은 창 바닥 여섯 · 넓은 창 서랍 — 다듬기 판 `paper`의 7)만 좁힌다.
  final double pad;
  final Widget? leading;
  final String? hint, semantics;

  static SheetShape shapeOf({bool selected = false, bool quiet = false, bool hover = false}) => SheetShape(
    chamfer: SheetLook.paperChamfer,
    fill: hover ? SheetLook.ink4 : SheetLook.paper,
    stroke: selected ? SheetLook.pickInk : (quiet ? SheetLook.ink25 : SheetLook.ink45),
    strokeWidth: selected ? SheetLook.pickWidth : 1,
  );

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    return _Press(
      onTap: onTap,
      label: semantics ?? label,
      selected: selected,
      hint: hint,
      builder: (hover) => SheetTag(
        shape: shapeOf(selected: selected, quiet: quiet || off, hover: hover),
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            _line(label, sheetText(SheetLook.chipText, bold: true, color: selected ? SheetLook.ink100 : (off ? SheetLook.ink45 : (quiet ? SheetLook.ink60 : SheetLook.ink85)))),
          ]),
        ),
      ),
    );
  }
}

/// 고르는 칸(▾): 제목(12 굵게 먹 60) · 사이 8 · 흰 이름 종이(값 12 보통 먹 85 · 앞 10 · ▾ 14 먹 60이 오른쪽 21에).
/// [title]이 비면 제목 없이 종이만(값 글이 제 머리를 단 원어 · 글꼴 칸). [sizes]를 주면 값 칸의 폭을 그 글들 가운데 가장 긴 것에 맞춘다 —
/// 고를 때마다 칸 폭(그래서 시트의 폭)이 바뀌지 않게(웹 `<select>`와 같게). [onOpen]은 종이의 맥락(누름 움직임 밖)을 받아 목록을 그 밑에 편다.
class SheetSelect extends StatelessWidget {
  const SheetSelect({super.key, required this.title, required this.value, this.onTap, this.onOpen, this.hint, this.semantics, this.sizes = const []});
  final String title, value;
  final VoidCallback? onTap;
  final void Function(BuildContext paper)? onOpen;
  final String? hint;

  /// 읽기 글의 이름(없으면 [title]) — 값과 함께 읽는다.
  final String? semantics;
  final List<String> sizes;

  @override
  Widget build(BuildContext context) {
    final name = semantics ?? title;
    final paper = Builder(
      builder: (paper) => _Press(
        onTap: onOpen != null ? () => onOpen!(paper) : onTap,
        label: name.isEmpty ? value : '$name $value',
        hint: hint,
        builder: (hover) => SheetTag(
          shape: SheetPaperButton.shapeOf(hover: hover),
          height: SheetLook.chip,
          child: Padding(
            padding: const EdgeInsets.only(left: SheetLook.selectLead, right: SheetLook.selectIconRight - SheetLook.selectIcon),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _WidestLine(value, sizes, sheetText(SheetLook.chipText)),
              const SizedBox(width: SheetLook.selectTail - SheetLook.selectLead - (SheetLook.selectIconRight - SheetLook.selectIcon) - SheetLook.selectIcon),
              const LineIcon(LineGlyph.chevronDown, size: SheetLook.selectIcon, color: SheetLook.ink60),
            ]),
          ),
        ),
      ),
    );
    if (title.isEmpty) return paper;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _line(title, sheetText(SheetLook.chipText, bold: true, color: SheetLook.ink60)),
      const SizedBox(width: SheetLook.selectTitleGap),
      paper,
    ]);
  }
}

/// 한 줄 글 — 폭은 [sizes] 가운데 가장 긴 글의 폭(정수로 올림)과 제 폭 가운데 큰 것.
class _WidestLine extends StatelessWidget {
  const _WidestLine(this.text, this.sizes, this.style);
  final String text;
  final List<String> sizes;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (sizes.isEmpty) return _line(text, style);
    final base = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    var widest = 0.0;
    for (final s in sizes) {
      final painter = TextPainter(text: TextSpan(text: s, style: base), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return ConstrainedBox(constraints: BoxConstraints(minWidth: widest.ceilToDouble()), child: _line(text, style));
  }
}

/// 고르는 칸의 값 고르기 — [SheetSelect]를 누르면 그 밑에 흰 이름 종이 목록([showSheetChoices])을 펴고, 고른 값이 다르면 [onChanged].
/// [disabled]는 고를 수 없는(흐린) 값, [tips]는 목록 줄마다의 풍선(웹 `<option disabled>` · `<option title>`), [hint]는 닫힌 칸의 풍선.
class SheetChoice<T> extends StatelessWidget {
  const SheetChoice({
    super.key,
    this.title = '',
    required this.value,
    required this.options,
    required this.onChanged,
    this.semantics,
    this.hint,
    this.disabled = const {},
    this.tips = const {},
  });

  final String title;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? semantics, hint;
  final Set<T> disabled;
  final Map<T, String> tips;

  /// 지금 값의 글(목록에 없으면 첫 줄).
  String get label {
    for (final o in options) {
      if (o.$1 == value) return o.$2;
    }
    return options.isEmpty ? '' : options.first.$2;
  }

  @override
  Widget build(BuildContext context) => SheetSelect(
    title: title,
    value: label,
    semantics: semantics,
    hint: hint,
    sizes: [for (final o in options) o.$2],
    onOpen: (paper) async {
      final picked = await showSheetChoices<T>(paper, options: options, value: value, disabled: disabled, tips: tips, label: semantics ?? title);
      if (picked != null && picked != value) onChanged(picked);
    },
  );
}

/// 고르는 칸의 목록을 [anchor](고르는 칸의 종이) 밑 4에 편다 — 흰 이름 종이(모따기 3 · 테 먹 45 · 흰 둘레 4) 안에 값마다 한 줄(키 24 · 글 12).
/// 고른 값은 안쪽 고른 테(먹 100 · 1.5)와 굵은 먹 100 글, 고를 수 없는 값은 먹 25 글. 밑에 들지 않으면 위로 편다.
/// 바깥을 누르거나 Esc면 닫히고 null. 움직임은 차림표와 같은 토큰(나타남 pop · 물러남 out)이다.
Future<T?> showSheetChoices<T>(
  BuildContext anchor, {
  required List<(T, String)> options,
  required T value,
  Set<T> disabled = const {},
  Map<T, String> tips = const {},
  String label = '',
}) {
  final navigator = Navigator.of(anchor, rootNavigator: true);
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final rect = MatrixUtils.transformRect(box.getTransformTo(overlay), Offset.zero & box.size);
  return navigator.push(_ChoiceRoute<T>(anchor: rect, options: options, value: value, disabled: disabled, tips: tips, label: label));
}

class _ChoiceRoute<T> extends PopupRoute<T> {
  _ChoiceRoute({required this.anchor, required this.options, required this.value, required this.disabled, required this.tips, required this.label});
  final Rect anchor;
  final List<(T, String)> options;
  final T value;
  final Set<T> disabled;
  final Map<T, String> tips;
  final String label;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '고르기 닫기';
  @override
  Duration get transitionDuration => const Duration(milliseconds: Motion.popMs);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: Motion.outMs * 2);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondary) => CustomSingleChildLayout(
    delegate: _ChoiceLayout(anchor),
    // 길 위의 글에도 바탕(Material)을 둔다 — 없으면 Flutter가 글마다 '바탕 없음' 겹밑줄을 긋는다.
    child: Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => MotionPresence(open: animation.status == AnimationStatus.forward || animation.status == AnimationStatus.completed, child: child!),
        child: Semantics(
          label: label,
          explicitChildNodes: true,
          child: _ChoiceList<T>(
            minWidth: anchor.width,
            options: options,
            value: value,
            disabled: disabled,
            tips: tips,
            onPick: (v) => Navigator.of(context).pop(v),
          ),
        ),
      ),
    ),
  );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) => child;
}

/// 목록을 고르는 칸 밑 4(들지 않으면 위 4)에, 왼쪽 끝을 칸에 맞춰 놓되 화면 4 안으로 밀어 넣는다.
class _ChoiceLayout extends SingleChildLayoutDelegate {
  const _ChoiceLayout(this.anchor);
  final Rect anchor;
  static const edge = 4.0, gap = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(math.max(0, constraints.maxWidth - 2 * edge), math.max(0, constraints.maxHeight - 2 * edge)));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final below = anchor.bottom + gap, above = anchor.top - gap - child.height;
    final y = below + child.height <= size.height - edge || above < edge ? below : above;
    return Offset(
      math.max(edge, math.min(anchor.left, size.width - child.width - edge)).roundToDouble(),
      math.max(edge, math.min(y, size.height - child.height - edge)).roundToDouble(),
    );
  }

  @override
  bool shouldRelayout(_ChoiceLayout old) => old.anchor != anchor;
}

class _ChoiceList<T> extends StatelessWidget {
  const _ChoiceList({required this.minWidth, required this.options, required this.value, required this.disabled, required this.tips, required this.onPick});
  final double minWidth;
  final List<(T, String)> options;
  final T value;
  final Set<T> disabled;
  final Map<T, String> tips;
  final ValueChanged<T> onPick;

  /// 줄 키 24 · 종이 안 위아래 3 · 글 앞 10(고르는 칸의 값 글과 같은 줄) · 뒤 14 · 흰 둘레 4.
  static const row = SheetLook.chip, pad = 3.0, lead = SheetLook.selectLead, tail = 14.0, rim = 4.0;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (v, name) in options)
        _Press(
          onTap: disabled.contains(v) ? null : () => onPick(v),
          label: name,
          selected: v == value,
          autofocus: v == value,
          builder: (hover) {
            final picked = v == value, off = disabled.contains(v);
            final text = _line(name, sheetText(SheetLook.chipText, bold: picked, color: off ? SheetLook.ink25 : (picked ? SheetLook.ink100 : SheetLook.ink85)));
            return SheetPickRing(
              on: picked,
              inside: true,
              child: ColoredBox(
                color: hover ? SheetLook.ink4 : const Color(0x00ffffff),
                child: SizedBox(
                  height: row,
                  child: Padding(
                    padding: const EdgeInsets.only(left: lead, right: tail),
                    child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: tips[v] == null ? text : Tooltip(message: tips[v]!, child: text)),
                  ),
                ),
              ),
            );
          },
        ),
    ];
    return CustomPaint(
      painter: const _ChoicePaperPainter(rim),
      child: SheetPixelBox(
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth.ceilToDouble()),
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: pad),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록의 바탕: 흰 둘레(그림자 대신 종이) · 흰 이름 종이(모따기 3 · 테 먹 45).
class _ChoicePaperPainter extends CustomPainter {
  const _ChoicePaperPainter(this.rim);
  final double rim;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(box.inflate(rim), Radius.circular(rim + SheetLook.paperChamfer)), Paint()..color = SheetLook.paper);
    SheetPaperButton.shapeOf().paint(canvas, size);
  }

  @override
  bool shouldRepaint(_ChoicePaperPainter old) => old.rim != rim;
}

/// 하나 고르기 = 종이 사슬: 흰 이름 종이를 짧은 실(10 · 먹 45)로 잇는다 · 고른 고리 = 먹 100 · 1.5 테 · 글 먹 100 / 다른 고리 = 테 먹 45 · 글 60.
/// [semantics]는 사슬 전체의 읽기 글(예: '중요도 필터'), [hint]는 사슬에 올리면 뜨는 풍선.
class SheetChain<T> extends StatelessWidget {
  const SheetChain({super.key, required this.items, required this.value, this.onSelect, this.semantics, this.hint});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T>? onSelect;
  final String? semantics, hint;

  @override
  Widget build(BuildContext context) {
    Widget body = CustomPaint(
      painter: const _ChainLinkPainter(),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: SheetLook.chainLink),
          _ChainItem(
            label: items[i].$2,
            selected: items[i].$1 == value,
            onTap: onSelect == null ? null : () => onSelect!(items[i].$1),
          ),
        ],
      ]),
    );
    if (semantics != null) body = Semantics(label: semantics, child: body);
    if (hint != null) body = Tooltip(message: hint!, child: body);
    // 바깥이 폭을 못 박아도(상자 몸) 사슬은 제 고리들만큼 — 잇는 실이 상자 끝까지 뻗지 않게.
    return Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, heightFactor: 1, child: body);
  }
}

class _ChainItem extends StatelessWidget {
  const _ChainItem({required this.label, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _Press(
    onTap: onTap,
    label: label,
    selected: selected,
    builder: (hover) => SheetTag(
      shape: SheetPaperButton.shapeOf(selected: selected, hover: hover),
      height: SheetLook.chip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SheetLook.buttonPad),
        child: Center(widthFactor: 1, child: _line(label, sheetText(SheetLook.chipText, bold: true, color: selected ? SheetLook.ink100 : SheetLook.ink60))),
      ),
    ),
  );
}

/// 사슬 고리 사이의 실 — 칩 키의 가운데(12.5) 한 줄을 사슬 폭 전체에 긋고 고리(흰 종이)가 그 위를 덮는다.
class _ChainLinkPainter extends CustomPainter {
  const _ChainLinkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = (SheetLook.chip / 2).floorToDouble() + .5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = SheetLook.ink45);
  }

  @override
  bool shouldRepaint(_ChainLinkPainter old) => false;
}

/// 열쇠표 한 조각의 글 — 관계는 굵게 먹 85, 방식은 보통 먹 60, 이름은 제 빛깔.
typedef SheetKeyPart = ({String text, bool bold, Color color});

/// 열쇠표(관계 · 방식 — 승계표 · 단체 계보): 키 12 · 왼쪽 둥근 끝 6 · 흰 종이 · 테 먹 45 · 구멍 1.5(왼쪽 6 · 가운데) ·
/// 글 8.5(앞 11 · 뒤 6 · 조각 사이 '·'). 꼬리표 윗변에서 오는 45° 실은 창이 [sheetKeyThreadPath]로 긋는다.
class SheetKeyLabel extends StatelessWidget {
  const SheetKeyLabel({super.key, required this.parts});
  final List<SheetKeyPart> parts;

  static const shape = SheetShape(
    kind: SheetTagKind.key,
    round: SheetLook.keyRound,
    stroke: SheetLook.ink45,
    hole: true,
    holeRadius: SheetLook.keyHole,
    holeAt: Offset(.5 + SheetLook.keyHoleLeft, .5 + SheetLook.keyTag / 2),
  );

  /// 테 가운데끼리 12라 바깥 화소 상자는 13(목업 `outline(kx, ky, kx + w, 12)`) — 오른쪽도 같은 까닭으로 1 넓다.
  @override
  Widget build(BuildContext context) => SheetTag(
    shape: shape,
    height: SheetLook.keyTag + 1,
    child: Padding(
      padding: const EdgeInsets.only(left: SheetLook.keyLead, right: SheetLook.keyTail + 1),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: _line('·', sheetText(SheetLook.keyText, color: SheetLook.ink60))),
          _line(parts[i].text, sheetText(SheetLook.keyText, bold: parts[i].bold, color: parts[i].color)),
        ],
      ]),
    ),
  );
}

/// 고른 테 — 먹 100 · 1.5. 바깥(기본): 그림판 고른 띠처럼 [child] 상자 2 밖에 같은 끝 꼴(모따기 6 · 둥근 끝 14).
/// [inside]면 상자 안 3에 둥근 3(흰 층 안의 칸 줄). [on]이 거짓이면 테를 그리지 않는다(자리는 그대로).
class SheetPickRing extends StatelessWidget {
  const SheetPickRing({super.key, required this.child, this.on = true, this.kind = SheetTagKind.cham, this.inside = false});
  final Widget child;
  final bool on, inside;
  final SheetTagKind kind;

  /// 바깥 고른 테의 길([box]는 고른 것의 바깥 화소 상자).
  static Path outsidePath(Rect box, SheetTagKind kind) =>
      sheetTagPath(box.inflate(SheetLook.pickOutset), kind == SheetTagKind.plain ? SheetTagKind.cham : kind, chamfer: SheetLook.pickChamfer, round: SheetLook.pickRound);

  /// 바깥 고른 테를 칠할 고리(굵기 1.5 — 가운데 줄은 [outsidePath]).
  static Path outsideRing(Rect box, SheetTagKind kind) => sheetTagRing(box.inflate(SheetLook.pickOutset), kind == SheetTagKind.plain ? SheetTagKind.cham : kind,
      chamfer: SheetLook.pickChamfer, round: SheetLook.pickRound, width: SheetLook.pickWidth);

  /// 안쪽 고른 테의 길.
  static Path insidePath(Rect box) =>
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(box.left + SheetLook.pickInset + .5, box.top + 2.5, box.right - SheetLook.pickInset - .5, box.bottom - 2.5), const Radius.circular(SheetLook.pickInnerRadius)));

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: on ? _PickPainter(kind, inside) : null, child: child);
}

class _PickPainter extends CustomPainter {
  const _PickPainter(this.kind, this.inside);
  final SheetTagKind kind;
  final bool inside;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    if (inside) {
      canvas.drawPath(SheetPickRing.insidePath(box), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SheetLook.pickWidth
        ..color = SheetLook.pickInk);
      return;
    }
    // 바깥 고른 테도 고리 칠([sheetTagRing]의 까닭) — 가운데 줄은 [SheetPickRing.outsidePath]와 같다.
    canvas.drawPath(SheetPickRing.outsideRing(box, kind), Paint()..color = SheetLook.pickInk);
  }

  @override
  bool shouldRepaint(_PickPainter old) => old.kind != kind || old.inside != inside;
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  늘어놓기 — 칩 줄 · 뚜껑의 작은 꼬리표 · 상자 두 열
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 칩 줄: 사이 6으로 흘리고 넘치면 다음 줄(사이 6). 펼친 폭(고유 폭)에 칩 사이를 넣어 센다 —
/// Flutter의 [Wrap]은 고유 폭에 사이를 넣지 않아 [SheetColumns]가 '가장 긴 칩 줄'을 짧게 재기 때문이다.
class SheetRun extends Wrap {
  const SheetRun({
    super.key,
    super.spacing = SheetLook.chipGap,
    super.runSpacing = SheetLook.chipGap,
    super.alignment,
    super.crossAxisAlignment = WrapCrossAlignment.center,
    super.children,
  });

  @override
  RenderWrap createRenderObject(BuildContext context) => _RenderRun(
    direction: direction,
    alignment: alignment,
    spacing: spacing,
    runAlignment: runAlignment,
    runSpacing: runSpacing,
    crossAxisAlignment: crossAxisAlignment,
    textDirection: textDirection ?? Directionality.maybeOf(context),
    verticalDirection: verticalDirection,
    clipBehavior: clipBehavior,
  );
}

class _RenderRun extends RenderWrap {
  _RenderRun({super.direction, super.alignment, super.spacing, super.runAlignment, super.runSpacing, super.crossAxisAlignment, super.textDirection, super.verticalDirection, super.clipBehavior});

  @override
  double computeMaxIntrinsicWidth(double height) => super.computeMaxIntrinsicWidth(height) + (childCount > 1 ? spacing * (childCount - 1) : 0);
}

/// 뚜껑의 작은 꼬리표(대범위 상자의 트랙 — 목업 g-sheet-search `smallTag`): 키 16 · 모따기 3 · 칠 제 색 24% · 테 84% + 먹 ·
/// 구멍 1.5(왼쪽 위 5.5) · 이름 9 굵게 탭 글(제 색 22% + 먹) · 글 앞 11 · 뒤 6.
class SheetSmallTag extends StatelessWidget {
  const SheetSmallTag({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  static const height = 16.0, text = 9.0, lead = 11.0, tail = 6.0, hole = 1.5, holeAt = 5.5;

  static SheetShape shapeOf(Color c) => SheetShape(
    chamfer: SheetLook.paperChamfer,
    fill: SheetLook.tagFill(c),
    stroke: SheetLook.tagEdge(c),
    hole: true,
    holeRadius: hole,
    holeAt: const Offset(holeAt, holeAt),
  );

  @override
  Widget build(BuildContext context) => SheetTag(
    shape: shapeOf(color),
    height: height,
    child: Padding(
      padding: const EdgeInsets.only(left: lead, right: tail),
      child: Center(widthFactor: 1, child: _line(label, sheetText(text, bold: true, color: SheetLook.tagInk(color)))),
    ),
  );
}

/// 한 줄 꼬리표 + 글(DLC 관리 줄의 둘째 줄 — 트랙 작은 꼬리표들 · 담긴 것): [children]의 마지막은 글, 그 앞은 꼬리표다. 꼬리표를 사이 [gap]으로
/// 왼쪽부터 놓되 글이 제 폭(줄 폭의 반까지)을 갖도록 들지 않는 꼬리표부터는 그리지 않는다(넘침 없이 — 모두는 자세히에). 글은 마지막 꼬리표 뒤
/// [after](꼬리표가 없으면 [lead])부터 남는 폭 안에(줄임표는 글이 스스로). 위아래는 가운데(온 화소). 그리지 않은 꼬리표는 누름 · 읽기에서도 빠진다.
class SheetFitRun extends MultiChildRenderObjectWidget {
  const SheetFitRun({super.key, required super.children, this.gap = SheetLook.dlcMiniGap, this.after = SheetLook.dlcContentsGap, this.lead = SheetLook.dlcContentsGap});
  final double gap, after, lead;

  @override
  RenderSheetFitRun createRenderObject(BuildContext context) => RenderSheetFitRun(gap, after, lead);

  @override
  void updateRenderObject(BuildContext context, RenderSheetFitRun renderObject) => renderObject.set(gap, after, lead);
}

class _FitData extends ContainerBoxParentData<RenderBox> {}

/// [SheetFitRun]의 배치 — 검사가 [shown](그린 꼬리표 수)을 읽는다.
class RenderSheetFitRun extends RenderBox with ContainerRenderObjectMixin<RenderBox, _FitData>, RenderBoxContainerDefaultsMixin<RenderBox, _FitData> {
  RenderSheetFitRun(this._gap, this._after, this._lead);
  double _gap, _after, _lead;

  /// 마지막 배치에서 그린 꼬리표 수(앞에서부터).
  int shown = 0;

  void set(double gap, double after, double lead) {
    if (gap == _gap && after == _after && lead == _lead) return;
    _gap = gap;
    _after = after;
    _lead = lead;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitData) child.parentData = _FitData();
  }

  /// 그리는 아이들 — 앞의 [shown]개 꼬리표와 마지막 글.
  Iterable<RenderBox> get _visible sync* {
    final kids = getChildrenAsList();
    if (kids.isEmpty) return;
    yield* kids.take(math.min(shown, kids.length - 1));
    yield kids.last;
  }

  @override
  void performLayout() {
    final kids = getChildrenAsList();
    if (kids.isEmpty) {
      shown = 0;
      size = constraints.smallest;
      return;
    }
    final text = kids.last, tags = kids.sublist(0, kids.length - 1);
    final maxW = constraints.maxWidth, bounded = maxW.isFinite;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    final keep = bounded ? math.min(text.getMaxIntrinsicWidth(double.infinity), maxW / 2) : 0.0;
    var x = 0.0, full = false;
    shown = 0;
    for (final t in tags) {
      t.layout(loose, parentUsesSize: true);
      if (!full && (!bounded || x + t.size.width + _after + keep <= maxW)) {
        (t.parentData! as _FitData).offset = Offset(x, 0);
        x += t.size.width + _gap;
        shown++;
      } else {
        full = true;
      }
    }
    final tx = shown == 0 ? _lead : x - _gap + _after;
    text.layout(BoxConstraints(maxWidth: bounded ? math.max(0.0, maxW - tx) : double.infinity, maxHeight: constraints.maxHeight), parentUsesSize: true);
    var h = text.size.height;
    for (var i = 0; i < shown; i++) {
      h = math.max(h, tags[i].size.height);
    }
    h = constraints.constrainHeight(h);
    for (var i = 0; i < shown; i++) {
      final d = tags[i].parentData! as _FitData;
      d.offset = Offset(d.offset.dx, ((h - tags[i].size.height) / 2).roundToDouble());
    }
    (text.parentData! as _FitData).offset = Offset(tx, ((h - text.size.height) / 2).roundToDouble());
    size = constraints.constrain(Size(bounded ? maxW : tx + text.size.width, h));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    final kids = getChildrenAsList();
    if (kids.isEmpty) return 0;
    var w = kids.last.getMaxIntrinsicWidth(height);
    final tags = kids.length - 1;
    for (final t in kids.take(tags)) {
      w += t.getMaxIntrinsicWidth(height) + _gap;
    }
    return w + (tags == 0 ? _lead : _after - _gap);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _tallest((c) => c.getMinIntrinsicHeight(double.infinity));
  @override
  double computeMaxIntrinsicHeight(double width) => _tallest((c) => c.getMaxIntrinsicHeight(double.infinity));

  double _tallest(double Function(RenderBox) of) {
    var h = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      h = math.max(h, of(c));
    }
    return h;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final c in _visible) {
      context.paintChild(c, (c.parentData! as _FitData).offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final c in _visible.toList().reversed) {
      final at = (c.parentData! as _FitData).offset;
      if (result.addWithPaintOffset(offset: at, position: position, hitTest: (r, p) => c.hitTest(r, position: p))) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) => _visible.forEach(visitor);
}

/// 상자 두 열(필터 시트 — 목업 g-sheet-search `drawFilter`): [left] · [right]의 상자를 같은 너비의 두 열에 세우고, 같은 줄(차례가 같은 상자)은
/// 같은 키로 맞춘다. 열 너비 = 상자들의 펼친 폭(가장 긴 칩 줄 + 안쪽 10 · 10) 가운데 가장 넓은 것 — 발([footer])이 한 줄에 들도록
/// (발 폭 − [gap]) / 2보다 좁지 않게 · 들어갈 자리((폭 − [gap]) / 2)보다 넓지 않게, 모두 정수. 들어갈 자리가 [minColumn]과 펼친 폭 가운데
/// 작은 것보다 좁으면(휴대폰 · 좁은 창) 한 열로 [left] 다음 [right]를 차례로 세운다. 발은 상자들 밑에 온 폭으로 둔다.
/// 몸의 폭은 내용에 맞추고(두 열 = 열 × 2 + [gap]), 바깥이 폭을 못 박으면 그 폭.
class SheetColumns extends MultiChildRenderObjectWidget {
  SheetColumns({super.key, required List<Widget> left, required List<Widget> right, Widget? footer, this.gap = 12, this.rowGap = 8, this.minColumn = 300})
    : leftCount = left.length,
      rightCount = right.length,
      hasFooter = footer != null,
      super(children: [...left, ...right, ?footer]);

  final int leftCount, rightCount;
  final bool hasFooter;
  final double gap, rowGap, minColumn;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSheetColumns(leftCount, rightCount, hasFooter, gap, rowGap, minColumn);

  @override
  void updateRenderObject(BuildContext context, RenderSheetColumns renderObject) => renderObject
    ..set(leftCount, rightCount, hasFooter)
    ..gap = gap
    ..rowGap = rowGap
    ..minColumn = minColumn;
}

class _ColumnsData extends ContainerBoxParentData<RenderBox> {}

/// [SheetColumns]의 배치 — 검사가 [twoColumns] · [column]을 읽는다.
class RenderSheetColumns extends RenderBox with ContainerRenderObjectMixin<RenderBox, _ColumnsData>, RenderBoxContainerDefaultsMixin<RenderBox, _ColumnsData> {
  RenderSheetColumns(this._left, this._right, this._footer, this._gap, this._rowGap, this._minColumn);

  int _left, _right;
  bool _footer;
  double _gap, _rowGap, _minColumn;

  void set(int left, int right, bool footer) {
    if (left == _left && right == _right && footer == _footer) return;
    _left = left;
    _right = right;
    _footer = footer;
    markNeedsLayout();
  }

  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  set rowGap(double v) {
    if (v == _rowGap) return;
    _rowGap = v;
    markNeedsLayout();
  }

  set minColumn(double v) {
    if (v == _minColumn) return;
    _minColumn = v;
    markNeedsLayout();
  }

  /// 마지막 배치가 두 열이었는가 · 그 열 너비.
  bool twoColumns = true;
  double column = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ColumnsData) child.parentData = _ColumnsData();
  }

  List<RenderBox> get _boxes => getChildrenAsList().take(_left + _right).toList();
  RenderBox? get _foot => _footer ? lastChild : null;

  double get _natural {
    var w = 0.0;
    for (final b in _boxes) {
      w = math.max(w, b.getMaxIntrinsicWidth(double.infinity).ceilToDouble());
    }
    return w;
  }

  double get _footNatural => _foot?.getMaxIntrinsicWidth(double.infinity).ceilToDouble() ?? 0;

  /// 열을 몇으로 · 너비 얼마로 세울지(폭 [maxWidth] 안).
  ({bool two, double col, double width}) _plan(double maxWidth) {
    final natural = _natural, foot = _footNatural;
    final room = maxWidth.isFinite ? ((maxWidth - _gap) / 2).floorToDouble() : double.infinity;
    final two = _left > 0 && _right > 0 && room >= math.min(natural, _minColumn);
    if (two) {
      final col = math.min(math.max(natural, ((foot - _gap) / 2).ceilToDouble()), room);
      return (two: true, col: col, width: col * 2 + _gap);
    }
    final col = math.min(math.max(natural, foot), maxWidth.isFinite ? maxWidth.floorToDouble() : double.infinity);
    return (two: false, col: col, width: col);
  }

  /// 상자 · 발을 놓는다(놓을 자리만 셈하려면 [place]를 거짓 — 마른 배치).
  Size _run(BoxConstraints constraints, {required bool place}) {
    final plan = _plan(constraints.maxWidth);
    final boxes = _boxes, foot = _foot;
    Size measure(RenderBox b, BoxConstraints c) {
      if (!place) return b.getDryLayout(c);
      b.layout(c, parentUsesSize: true);
      return b.size;
    }

    void at(RenderBox b, double x, double y) {
      if (place) (b.parentData! as _ColumnsData).offset = Offset(x, y);
    }

    final width = BoxConstraints.tightFor(width: plan.col);
    var y = 0.0;
    var first = true;
    if (plan.two) {
      final rows = math.max(_left, _right);
      for (var i = 0; i < rows; i++) {
        final l = i < _left ? boxes[i] : null, r = i < _right ? boxes[_left + i] : null;
        final hl = l == null ? 0.0 : measure(l, width).height, hr = r == null ? 0.0 : measure(r, width).height;
        final h = math.max(hl, hr).ceilToDouble();
        if (!first) y += _rowGap;
        first = false;
        // 같은 줄의 상자는 같은 키 — 낮은 쪽을 그 키로 다시 놓는다.
        if (l != null) {
          if (hl != h) measure(l, BoxConstraints.tight(Size(plan.col, h)));
          at(l, 0, y);
        }
        if (r != null) {
          if (hr != h) measure(r, BoxConstraints.tight(Size(plan.col, h)));
          at(r, plan.col + _gap, y);
        }
        y += h;
      }
    } else {
      for (final b in boxes) {
        if (!first) y += _rowGap;
        first = false;
        final h = measure(b, width).height;
        at(b, 0, y);
        y += h;
      }
    }
    if (foot != null) {
      final h = measure(foot, BoxConstraints.tightFor(width: plan.width)).height;
      at(foot, 0, y);
      y += h;
    }
    if (place) {
      twoColumns = plan.two;
      column = plan.col;
    }
    return constraints.constrain(Size(plan.width, y));
  }

  @override
  void performLayout() => size = _run(constraints, place: true);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _run(constraints, place: false);

  @override
  double computeMinIntrinsicWidth(double height) => _plan(double.infinity).col;
  @override
  double computeMaxIntrinsicWidth(double height) => _plan(double.infinity).width;
  @override
  double computeMinIntrinsicHeight(double width) => _run(BoxConstraints(maxWidth: width), place: false).height;
  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  받침 카드 — 문서 창(목업 g-sheet-tree `drawDoc` · 다듬기 판 sht-doc)
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 받침 카드: 주인 객체의 카드(제 색 칠 24% · 테 84% + 먹 — 주인이 없는 문서는 칠 먹 4 · 테 먹 25)가 흰 종이(테 먹 25) 밑에서
/// 위 · 오른쪽으로 [peek] 6만큼 드러난다(둘 다 왼쪽 두 귀 모따기 12 · 오른쪽은 직각 — 그림판 꼬리표의 다스림 꼴). 카드 오른쪽 끝(10 안)에
/// 이름 탭(키 18 · 왼쪽 위 모따기 5 · 맨 글 12 굵게 탭 글 + 과녁 12 — 누르면 [onTab] · 풍선 [tabHint])이 카드 윗변에 붙어 선다(탭 칠이 카드 윗테를 덮어 한 장).
/// [tab]이 없으면 탭도 없다(카드 윗변의 자리는 그대로 — 18 아래). [child]는 흰 종이의 테 안쪽.
/// 이 위젯의 크기가 정수일 때 테가 화소 한 줄에 앉는다(문서 창은 화면 가장자리에서 정수 자리 · 정수 크기).
class SheetCard extends StatelessWidget {
  const SheetCard({super.key, required this.child, this.color, this.tab, this.onTab, this.tabHint, this.tabSemantics});
  final Widget child;

  /// 주인 객체의 빛깔(없으면 먹 — 트랙 · 민족 · 분류 · 대문 같은 주인 없는 문서).
  final Color? color;
  final String? tab, tabHint, tabSemantics;
  final VoidCallback? onTab;

  /// 탭 키 18 · 카드가 종이 밖으로 드러나는 폭 6 · 모따기 12 · 탭은 카드 오른쪽 테에서 10 안 · 탭 왼쪽 위 모따기 5 ·
  /// 탭 글 앞 9 · 글과 과녁 사이 10 · 과녁 12 · 과녁 뒤 6 · 탭은 가장 넓어도 320(좁은 카드에서는 카드 왼쪽 모따기 안까지).
  static const tabHeight = 18.0, peek = 6.0, chamfer = 12.0, tabInset = 10.0, tabChamfer = 5.0, tabLead = 9.0, tabGap = 10.0, tabIcon = 12.0, tabTail = 6.0, tabMax = 320.0;

  /// 카드 칠 · 테 · 탭 글 — 주인이 없으면 먹.
  static Color fillOf(Color? c) => c == null ? SheetLook.ink4 : SheetLook.tagFill(c);
  static Color edgeOf(Color? c) => c == null ? SheetLook.ink25 : SheetLook.tagEdge(c);
  static Color inkOf(Color? c) => c == null ? SheetLook.ink85 : SheetLook.tagInk(c);

  /// 이 위젯 크기 [s] 안의 카드 · 흰 종이 바깥 화소 상자.
  static Rect cardRect(Size s) => Rect.fromLTRB(peek, tabHeight, s.width, s.height);
  static Rect pageRect(Size s) => Rect.fromLTRB(0, tabHeight + peek, s.width - peek, s.height);

  @override
  Widget build(BuildContext context) {
    final fill = fillOf(color), edge = edgeOf(color), name = tab;
    return Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _CardPainter(fill, edge))),
      Positioned(left: 1, top: tabHeight + peek + 1, right: peek + 1, bottom: 1, child: child),
      if (name != null)
        // 탭은 오른쪽(카드 테에서 10 안)에 붙고, 좁은 카드(휴대폰)에서는 카드 왼쪽 모따기(드러난 6 + 12) 안까지만 — 그보다 길면 이름을 줄인다.
        Positioned(
          top: 0,
          left: peek + chamfer,
          right: tabInset,
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: tabMax),
              child: _Press(
                onTap: onTab,
                label: tabSemantics ?? name,
                hint: tabHint,
                builder: (hover) => CustomPaint(
                  painter: _CardTabPainter(hover ? SheetTagButton.lift(fill) : fill, edge),
                  child: SheetPixelBox(
                    child: SizedBox(
                      height: tabHeight + 2,
                      child: Padding(
                        padding: const EdgeInsets.only(left: tabLead, right: tabTail, bottom: 1),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: sheetText(SheetLook.folderTabText, bold: true, color: inkOf(color)))),
                          const SizedBox(width: tabGap),
                          LineIcon(LineGlyph.locate, size: tabIcon, color: inkOf(color)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// 카드(제 색) 위에 흰 종이 — 칠은 윤곽 길, 테는 고리 칠([sheetTagRing]의 까닭).
class _CardPainter extends CustomPainter {
  const _CardPainter(this.fill, this.edge);
  final Color fill, edge;

  @override
  void paint(Canvas canvas, Size size) {
    final card = SheetCard.cardRect(size), page = SheetCard.pageRect(size);
    if (card.width <= 1 || page.height <= 1) return;
    canvas.drawPath(sheetTagPath(card, SheetTagKind.cham, chamfer: SheetCard.chamfer), Paint()..color = fill);
    canvas.drawPath(sheetTagRing(card, SheetTagKind.cham, chamfer: SheetCard.chamfer), Paint()..color = edge);
    canvas.drawPath(sheetTagPath(page, SheetTagKind.cham, chamfer: SheetCard.chamfer), Paint()..color = SheetLook.paper);
    canvas.drawPath(sheetTagRing(page, SheetTagKind.cham, chamfer: SheetCard.chamfer), Paint()..color = SheetLook.ink25);
  }

  @override
  bool shouldRepaint(_CardPainter old) => old.fill != fill || old.edge != edge;
}

/// 이름 탭(키 18 · 왼쪽 위 모따기 5 · 밑변 없음): 칠은 카드 윗테 아래 1까지 내려 카드와 한 장(목업 `yb + 1`), 테는 곧은 셋을 네모로 · 모따기만 획으로.
class _CardTabPainter extends CustomPainter {
  const _CardTabPainter(this.fill, this.edge);
  final Color fill, edge;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, c = SheetCard.tabChamfer, base = SheetCard.tabHeight + 1;
    canvas.drawPath(
      Path()
        ..moveTo(.5, base + 1)
        ..lineTo(.5, c + .5)
        ..lineTo(c + .5, .5)
        ..lineTo(w - .5, .5)
        ..lineTo(w - .5, base + 1)
        ..close(),
      Paint()..color = fill,
    );
    final line = Paint()..color = edge;
    canvas.drawRect(Rect.fromLTRB(0, c, 1, base), line);
    canvas.drawRect(Rect.fromLTRB(w - 1, 0, w, base), line);
    canvas.drawRect(Rect.fromLTRB(c, 0, w - 1, 1), line);
    canvas.drawLine(Offset(.5, c + .5), Offset(c + .5, .5), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = edge);
  }

  @override
  bool shouldRepaint(_CardTabPainter old) => old.fill != fill || old.edge != edge;
}
