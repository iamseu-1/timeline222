import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../scene/color_mix.dart';
import '../scene/fonts.dart';
import '../scene/paint/bands.dart' show BandKind, BandLayer, BandLook, EdgeStroke, TagEnd, TagLook;
import '../scene/paint/figures.dart' show FigureLook;
import '../scene/paint/hangs.dart' show HangLook;
import '../scene/paint/links.dart' show LinkLook;
import '../scene/paint/look.dart' show Look;
import '../scene/paint/rails.dart' show RailLook;
import '../scene/paint/scopes.dart' show FolderLook, ScopeLook;
import '../scene/paint/sphere_lines.dart' show SphereLinesLook;
import '../scene/paint/sphere_threads.dart' show SphereThreadLook;
import '../scene/paint/unions.dart' show UnionLook;
import '../shell/sheet_look.dart';
import '../shell/sheet_parts.dart' show SheetTagKind, sheetBoxPath, sheetBoxRing, sheetDashed, sheetDiamondPath, sheetLidPath, sheetTabPath, sheetTagPath, sheetTagRing;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  범례의 견본 — 그림판 제 크기(폭 148 · 머리 24 · 층 16 · 이름 9 · 사건 9.5)의 꼬리표 · 칸 · 실 · 받침 · 그릇 · 정통성.
//  감독 고름 G5 #9(다듬기 판 범례 — 목업 `.claude/research/stage4-choose/themes/g-sheet-search.js`의 `drawLegend` · git 밖).
//
//  빛깔 · 테 · 귀 · 구멍 · 무늬는 연표 그림판이 **지금 그리는 값**을 그대로 부른다 — 견본과 실제가 갈라지지 않게:
//    띠 칠 · 테 · 빗금 · 점무늬 · 깃대 · 연맹 겹줄 = [BandLayer.toneOf] · [BandLayer.fogFillOf](안개) · 가운데 켜 [BandLayer.bodyTint] · 층 사이 금 [BandLayer.innerLine]
//    꼬리표 귀 · 구멍 = [TagLook] · 관계선 = [LinkLook] · 기간 사건 = [RailLook] · 그릇 = [FolderLook] · [ScopeLook] · 사람 띠 = [SphereLinesLook] · [SphereThreadLook]
//  정통성 넷(공동 · 섭정 · 명목 · 주장)은 그림판이 아직 그리지 않는 무늬라 '정통성 가 다듬음'(목업 g-legit2 `lg2-ga`)의 그림 그대로다 — 층은 흰 종이.
//  옛 34×12 띠 견본(앞 범례의 `_GlyphPainter`)은 걷었다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 범례 견본 · 줄의 값(다듬기 판 범례).
abstract final class LegendLook {
  /// 견본: 폭 148 · 꼬리표 머리 24 · 층 16 · 이름 9 굵게 · 사건 이름 9.5 굵게 · 칸 이름 8.5.
  static const sample = 148.0, head = 24.0, floor = 16.0, name = 9.0, event = 9.5, cellName = 8.5;

  /// 줄: 견본 뒤 16에 글 칸(기본 172) · 줄 키 36 이상 · 줄 사이 10 · 이름 13 굵게 먹 85 · 설명 12 먹 60(이름 아래 1).
  static const textGap = 16.0, text = 172.0, rowMin = 36.0, rowGap = 10.0, nameSize = 13.0, descSize = 12.0, nameDescGap = 1.0;

  /// 상자 안 묶음 이름(앞 범례의 묶음 제목): 11 굵게 먹 45 · 위 묶음과는 14(가운데 먹 12 금) · 아래 줄과는 6.
  static const sectionSize = 11.0, sectionBefore = 14.0, sectionAfter = 6.0;

  /// 상자 몸: 뚜껑 밑선 아래 11 · 끝 줄 아래 12 · 상자 사이 8 · 열 사이 12 · 폴더 안쪽 14.
  static const boxTop = 11.0, boxBottom = 12.0, boxGap = 8.0, columnGap = 12.0, pad = 14.0;
}

/// 견본 나라 색(목업 kit.js의 `P` — 앱 자료 색과 같은 결의 옅은 빛깔 · 0xRRGGBB).
abstract final class LegendTint {
  static const rose = 0xd4a39b, peach = 0xdab195, butter = 0xd7c18e, sage = 0xb6c398, mint = 0x9dbea8, sky = 0xa0bcc5;
  static const peri = 0xabb3c9, lav = 0xbbacc8, pink = 0xd1a9b9, sand = 0xc8b193, slate = 0xa4b1b7, mocha = 0xbba395;
}

/// 견본의 갈래. 한 줄에 하나, 왼쪽 148 자리에 그림판 제 크기로 그린다.
enum LegendMark {
  // ---- 꼬리표(머리 24) — [LegendRow.look]의 띠 look 비트(종류 · 확실성 · 실재성 · 종속)로 그림판 칠 · 테 ----
  tag,
  tagRange, // 연대 폭이 있는 구간만 무늬
  tagUnknown, // 미정 — 그쪽 끝이 옅어지며 열림
  // ---- 꼬리표 안 ----
  floor, // 지도자 · 직위 층(머리 24 + 층 16)
  power, // 실권 밑줄
  borrow, // 빌린 직위
  event, // 사건 칸의 점 · 빈 점 · 미정 · 기간 · 구슬 · 이설 · 조약 · 기간 조약
  eventHollow,
  eventUnknown,
  rail,
  beads,
  railAlt,
  treaty,
  railTreaty,
  cell, // 칸(왕조 층 + 지도자 층)
  axis, // 날짜 칸의 연호 · 도읍 묶음
  catLines, // 사건 분류별 글줄
  bird, // 조감
  cellSpot, // 칸 기간 조명
  cellAlt, // 칸의 이설(유령 구분선)
  cellFuzzy, // 연대가 모호한 칸
  phase, // 시기 구분
  ranks, // 지위 단
  house, // 가문 색 줄
  cellUnknown, // 칸의 미정
  figure, // 인물 단
  // ---- 실 · 받침 ----
  found, // 건국 = 구멍
  end, // 멸망 = 꼬리 마름모
  foundUnknown, // 연도 미정 = 점선 동그라미
  succession, // 승계 실(직접)
  indirect, // 간접 승계(파선)
  revival, // 부흥(파선 + 작은 고리)
  partial, // 부분 승계(가는 실선)
  join, // 합류
  partOf, // 소속선
  union, // 동군연합
  hangOut, // 상국 띠 아래에 매달린 이름표
  hangIn, // 상국 띠 안 맨 아래의 이름표
  host, // 섬김 받침(뒤 장 · 상국 탭)
  person, // 사람 띠
  // ---- 그릇 ----
  folder,
  box,
  closedBox,
  hollow, // 할거기
  // ---- 정통성(그림판이 아직 그리지 않는 무늬 — lg2-ga 그대로) ----
  joint,
  regent,
  nominal,
  claim,
}

/// 범례 한 줄: 왼쪽 견본 + 이름(13 굵게) + 설명(12 먹 60 · 길면 줄바꿈).
@immutable
class LegendRow {
  const LegendRow(this.mark, this.name, this.desc, {this.look = 0, this.rgb = LegendTint.peri, this.label});
  final LegendMark mark;
  final String name, desc;

  /// 꼬리표 견본의 띠 look 비트(계약 6-1 — 종류 · 확실성 · 실재성 · 종속 갈래). 꼬리표가 아닌 견본은 0.
  final int look;

  /// 견본의 나라 색(0xRRGGBB).
  final int rgb;

  /// 견본 꼬리표에 적는 이름(없으면 갈래마다 정한 이름).
  final String? label;

  /// 한 줄 글(이름 — 설명) — 검사 · 읽기 글이 쓴다.
  String get text => desc.isEmpty ? name : '$name — $desc';

  @override
  bool operator ==(Object other) => other is LegendRow && other.mark == mark && other.name == name && other.desc == desc && other.look == look && other.rgb == rgb && other.label == label;

  @override
  int get hashCode => Object.hash(mark, name, desc, look, rgb, label);
}

/// 견본의 키(폭은 늘 [LegendLook.sample]).
double legendSampleHeight(LegendMark m) => switch (m) {
  LegendMark.tag || LegendMark.tagRange || LegendMark.tagUnknown || LegendMark.power => 24,
  LegendMark.event || LegendMark.eventHollow || LegendMark.eventUnknown || LegendMark.rail || LegendMark.beads || LegendMark.railAlt || LegendMark.treaty || LegendMark.railTreaty => 24,
  LegendMark.axis || LegendMark.bird || LegendMark.closedBox || LegendMark.hollow => 24,
  LegendMark.found || LegendMark.end || LegendMark.foundUnknown || LegendMark.succession || LegendMark.indirect || LegendMark.revival || LegendMark.partial => 24,
  LegendMark.floor || LegendMark.borrow || LegendMark.catLines || LegendMark.cellSpot || LegendMark.cellAlt || LegendMark.cellFuzzy => 40,
  LegendMark.phase || LegendMark.ranks || LegendMark.house || LegendMark.cellUnknown || LegendMark.hangIn || LegendMark.union => 40,
  LegendMark.regent || LegendMark.nominal || LegendMark.claim => 40,
  LegendMark.figure || LegendMark.hangOut || LegendMark.host => 42,
  LegendMark.cell || LegendMark.joint => 56,
  LegendMark.join || LegendMark.partOf => 54,
  LegendMark.person || LegendMark.folder => 52,
  LegendMark.box => 50,
};

/// 견본 하나 — 글자가 아니라 그림이라 글꼴에 흔들리지 않는다(이름 글은 그림판 글꼴).
class LegendSample extends StatelessWidget {
  const LegendSample({super.key, required this.row});
  final LegendRow row;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: LegendLook.sample,
    height: legendSampleHeight(row.mark),
    child: CustomPaint(painter: _SamplePainter(row, MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling)),
  );
}

class _SamplePainter extends CustomPainter {
  _SamplePainter(this.row, this.scaler);
  final LegendRow row;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) => _Pen(canvas, scaler).sample(row, size);

  @override
  bool shouldRepaint(_SamplePainter old) => old.row != row || old.scaler != scaler;
}

// ---- 그리는 손 ----

/// 견본을 그리는 손 — 곧은 테 · 금은 화소 한 줄을 칠하는 네모로(그림판도 테를 네모 · 조각으로 긋는다), 꺾인 테는 고리 칠([sheetTagRing]).
class _Pen {
  _Pen(this.canvas, this.scaler);
  final Canvas canvas;
  final TextScaler scaler;

  static const _w = LegendLook.sample;
  static const paper = Look.paper, ink = Look.ink, muted = Look.muted;
  static final ink45 = SheetLook.ink45.toARGB32(), ink25 = SheetLook.ink25.toARGB32(), ink12 = SheetLook.ink12.toARGB32(), ink4 = SheetLook.ink4.toARGB32();
  static final ink60 = SheetLook.ink60.toARGB32(), ink85 = SheetLook.ink85.toARGB32();

  Paint _fill(int argb) => Paint()
    ..isAntiAlias = true
    ..color = Color(argb);
  Paint _line(int argb, [double width = 1]) => Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = Color(argb);

  void rect(double l, double t, double r, double b, int argb) {
    if (r > l && b > t) canvas.drawRect(Rect.fromLTRB(l, t, r, b), _fill(argb));
  }

  /// 가로 금(화소 줄 [y]) — 점선이면 [dash] · [gap].
  void hLine(double l, double r, double y, int argb, {double dash = 0, double gap = 0}) {
    if (dash <= 0) return rect(l, y, r, y + 1, argb);
    for (var x = l; x < r; x += dash + gap) {
      rect(x, y, math.min(r, x + dash), y + 1, argb);
    }
  }

  /// 세로 금(화소 열 [x]).
  void vLine(double x, double t, double b, int argb, {double dash = 0, double gap = 0}) {
    if (dash <= 0) return rect(x, t, x + 1, b, argb);
    for (var y = t; y < b; y += dash + gap) {
      rect(x, y, x + 1, math.min(b, y + dash), argb);
    }
  }

  void circle(double cx, double cy, double r, {int? fill, int? stroke, double width = 1}) {
    if (fill != null) canvas.drawCircle(Offset(cx, cy), r, _fill(fill));
    if (stroke != null) canvas.drawCircle(Offset(cx, cy), r, _line(stroke, width));
  }

  /// 점선 동그라미(미정) — 짧은 호 [count]개(호마다 제 몫의 [ratio]).
  void dashCircle(double cx, double cy, double r, int argb, {double width = 1, int count = 12, double ratio = .5}) {
    for (var i = 0; i < count; i++) {
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), i * math.pi * 2 / count, math.pi * 2 / count * ratio, false, _line(argb, width));
    }
  }

  /// 마름모(한 변 [side]를 45° 돌린 것).
  void diamond(double cx, double cy, double side, int argb) => canvas.drawPath(sheetDiamondPath(Offset(cx, cy), half: side * math.sqrt2 / 2), _fill(argb));

  /// 글 한 줄 — [cy]는 글줄 가운데 · 바탕선은 정수 픽셀(목업 `tx`). 돌려줌: 글 폭.
  double text(String s, double x, double cy, double size, int argb, {bool bold = false, bool italic = false, bool end = false, double spacing = -.1, FontWeight? weight}) {
    if (s.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: sceneFontFamily,
          fontFamilyFallback: sceneFontFallback,
          fontSize: size,
          fontWeight: weight ?? (bold ? FontWeight.w700 : FontWeight.w400),
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: spacing,
          color: Color(argb),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final top = (cy + size * .36).roundToDouble() - base;
    tp.paint(canvas, Offset(end ? x - tp.width : x, top));
    final w = tp.width;
    tp.dispose();
    return w;
  }

  /// 기운 줄무늬(css `repeating-linear-gradient(135deg, 색 0 [line], 투명 [line] [period])` — '/' 결) · 세로 줄무늬(90°)를 [area]에.
  void stripes(Rect area, double angle, double line, double period, int argb, {Path? clip}) {
    canvas.save();
    canvas.clipRect(area);
    if (clip != null) canvas.clipPath(clip);
    final p = _fill(argb);
    if (angle == 90) {
      for (var x = area.left; x < area.right; x += period) {
        canvas.drawRect(Rect.fromLTRB(x, area.top, math.min(area.right, x + line), area.bottom), p);
      }
    } else {
      final k = math.sqrt2, h = area.height;
      for (var s = 0.0; s < (area.width + h) / k + period; s += period) {
        final a = s * k, b = (s + line) * k;
        canvas.drawPath(
          Path()
            ..moveTo(area.left + a, area.top)
            ..lineTo(area.left + b, area.top)
            ..lineTo(area.left + b - h, area.bottom)
            ..lineTo(area.left + a - h, area.bottom)
            ..close(),
          p,
        );
      }
    }
    canvas.restore();
  }

  // ---- 꼬리표 ----

  static SheetTagKind _kindOf(TagEnd end) => switch (end) {
    TagEnd.cham => SheetTagKind.cham,
    TagEnd.key => SheetTagKind.key,
    TagEnd.plain => SheetTagKind.plain,
  };

  /// 구멍 가운데(바깥 화소 상자 [box]의 왼쪽 위에서 — 반 픽셀 자리 · 그림판 [TagLook.holeAt]의 7 · 9).
  static Offset holeOf(Rect box, TagEnd end) => Offset(box.left + .5 + (end == TagEnd.key ? TagLook.holeXKey : TagLook.holeX), box.top + 6.5);

  void hole(Offset c, {int? ring, double r = TagLook.holeR}) => circle(c.dx, c.dy, r, fill: paper, stroke: ring ?? ink45);

  /// 그림판 꼬리표 하나(바깥 화소 상자 [box] · 머리 24 + 층) — 칠 · 테 · 무늬는 그 look의 [BandLayer.toneOf].
  /// [cells]는 층마다의 칸(이름 · 왼쪽 끝 몫 0 ~ 1) · [fuzzy]면 오른쪽 끝이 44에 걸쳐 옅어지며 열린다.
  ({Offset hole, double nameEnd, int edge, int line}) tag(
    Rect box,
    int rgb,
    int look, {
    String name = '',
    TagEnd? end,
    bool fuzzy = false,
    List<List<(String, double)>> floors = const [],
    bool range = false,
    String badge = '',
    String trail = '',
    bool withHole = true,
    bool dashedFloor = false,
    bool quietCells = false,
  }) {
    final kind = BandLook.kindOf(look), hs = BandLook.hsOf(look);
    final culture = kind == BandKind.culture;
    final e = end ?? TagLook.endOf(look);
    final sk = _kindOf(e);
    final k = TagLook.cornerOf(e, LegendLook.head);
    final tone = BandLayer.toneOf(rgb, look, fuzzy: fuzzy);
    final strip = BandLayer.fogFillOf(tone, look), tint = mixSrgb(strip, paper, BandLayer.bodyTint);
    final c = 0xff000000 | rgb;
    final edge = over(tone.edge, paper);
    final line = mixSrgb(edge, paper, BandLayer.innerLine);
    final headB = box.top + LegendLook.head;
    final outline = culture ? (Path()..addRRect(RRect.fromRectAndRadius(box.deflate(.5), Radius.circular(math.min(tone.radius, box.height / 2))))) : sheetTagPath(box, sk, chamfer: k, round: k);
    // 미정 끝: 오른쪽 44에 걸쳐 옅어진다(그림판 Look.fuzzyFade) — 칠 · 테 모두 같은 붓.
    Paint brush(int argb) {
      final p = _fill(argb);
      if (fuzzy) {
        p.shader = ui.Gradient.linear(Offset(box.right - Look.fuzzyFade, 0), Offset(box.right, 0), [Color(argb), Color(argb & 0x00ffffff)]);
      }
      return p;
    }

    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(Rect.fromLTRB(box.left, box.top, box.right, headB), brush(strip));
    if (box.bottom > headB) canvas.drawRect(Rect.fromLTRB(box.left, headB, box.right, box.bottom), brush(tint));
    canvas.restore();
    final headArea = Rect.fromLTRB(box.left, box.top, box.right, floors.isEmpty ? box.bottom : headB - 1);
    if (tone.hatch) stripes(headArea, 135, 6, 12, tone.hatchColor, clip: outline);
    if (tone.dots) {
      canvas.save();
      canvas.clipPath(outline);
      canvas.clipRect(headArea);
      for (var y = box.top + 9 * .1; y < headArea.bottom + 9; y += 9) {
        for (var x = box.left + 9 * .3; x < box.right + 9; x += 9) {
          canvas.drawCircle(Offset(x, y), 1.5, _fill(withAlpha(c, .22)));
        }
      }
      canvas.restore();
    }
    if (range) {
      // 연대 폭(그림판 _zones): 종이 바탕 + 세로 줄(2 · 6 · 제 색 14%) + 경계는 옅은 실선.
      final zl = box.left + 1, zr = box.left + 1 + 44, y0 = box.top + 1, y1 = headB - 1;
      canvas.save();
      canvas.clipPath(outline);
      rect(zl, y0, zr, y1, paper);
      canvas.restore();
      stripes(Rect.fromLTRB(zl, y0, zr, y1), 90, 2, 6, mixSrgb(c, paper, .14), clip: outline);
      vLine(zr - 1, y0, y1, mixSrgb(over(mixOklab(c, ink, .92), paper), paper, BandLayer.unsureEdge));
    }
    if (kind == BandKind.federation) {
      // 연맹 겹줄(그림판 _double): 안쪽 1 ~ 3 종이 · 3 ~ 4 테 55%.
      canvas.drawPath(sheetTagRing(Rect.fromLTRB(box.left + 1.5, box.top + 1.5, box.right - 1.5, headB - 1.5), sk, chamfer: math.max(0, k - 1.5), round: math.max(0, k - 1.5), width: 2), _fill(paper));
      canvas.drawPath(sheetTagRing(Rect.fromLTRB(box.left + 3, box.top + 3, box.right - 3, headB - 3), sk, chamfer: math.max(0, k - 3), round: math.max(0, k - 3)), _fill(withAlpha(edge, .55)));
    }
    if (tone.pole != 0) {
      canvas.save();
      canvas.clipPath(outline);
      rect(box.left + 1, box.top + 1, box.left + 4, headB - 1, tone.pole);
      canvas.restore();
    }
    // 층 사이 금 · 칸 사이 금(그림판 innerLine — 테를 종이와 섞은 옅은 금).
    for (var i = 0; i < floors.length; i++) {
      final ft = headB + i * LegendLook.floor;
      final top = ft - 1;
      if (dashedFloor && i == 0) {
        hLine(box.left + 1, box.right - 1, top, edge, dash: EdgeStroke.dashed.dash, gap: EdgeStroke.dashed.gap);
      } else {
        hLine(box.left + 1, box.right - 1, top, line);
      }
      final cells = floors[i];
      final lo = box.left + 6, hi = box.right - 2;
      for (var j = 0; j < cells.length; j++) {
        final (s, f) = cells[j];
        final cx = (lo + f * (hi - lo)).roundToDouble();
        if (j > 0) vLine(cx, ft, ft + LegendLook.floor - (i == floors.length - 1 ? 1 : 1), line);
        text(s, (j > 0 ? cx : box.left + 6) + 3, ft + LegendLook.floor / 2 - .5, LegendLook.cellName, quietCells ? ink45 : mixSrgb(c, ink, .45));
      }
    }
    // 테 — 무리는 테 없음 · 조직체 · 복속 세력은 점선 · 미정 끝은 열림.
    if (e != TagEnd.plain || culture) {
      if (fuzzy) {
        final open = sheetTagPath(box, sk, chamfer: k, round: k, open: true);
        final p = _line(edge)..shader = ui.Gradient.linear(Offset(box.right - Look.fuzzyFade, 0), Offset(box.right, 0), [Color(edge), Color(edge & 0x00ffffff)]);
        canvas.drawPath(open, p);
      } else if (tone.stroke != EdgeStroke.solid) {
        canvas.drawPath(sheetDashed(outline, [tone.stroke.dash, tone.stroke.gap]), _line(edge));
      } else if (culture) {
        final mid = box.deflate(.5), r = math.min(tone.radius, box.height / 2);
        canvas.drawDRRect(RRect.fromRectAndRadius(mid.inflate(.5), Radius.circular(r + .5)), RRect.fromRectAndRadius(mid.deflate(.5), Radius.circular(r - .5)), _fill(edge));
      } else {
        canvas.drawPath(sheetTagRing(box, sk, chamfer: k, round: k), _fill(edge));
      }
    }
    final h = holeOf(box, e);
    if (withHole) hole(h);
    final refuted = hs == BandLook.hsRefuted;
    final fg = refuted ? muted : mixSrgb(c, ink, .22);
    final nx = h.dx + TagLook.nameGap;
    final cy = box.top + LegendLook.head / 2;
    var w = text(name, nx, cy, LegendLook.name, fg, bold: true, italic: hs == BandLook.hsLegendary);
    if (refuted && w > 0) hLine(nx, nx + w, cy.floorToDouble(), muted);
    var at = nx + w;
    if (badge.isNotEmpty) at += 4 + text(badge, at + 4, cy, 8.5, mixSrgb(muted, ink, .55), weight: FontWeight.w500);
    if (trail.isNotEmpty) at += 6 + text(trail, at + 6, cy, 8.5, mixSrgb(ink, paper, .55));
    return (hole: h, nameEnd: at, edge: edge, line: line);
  }

  /// 사건 칸(흰 종이 · 꼬리표 테 — 그림판 한 장 꼬리표의 맨 아래 칸).
  void eventCell(Rect box, int rgb) {
    final c = 0xff000000 | rgb;
    canvas.drawPath(sheetTagPath(box, SheetTagKind.cham), _fill(paper));
    canvas.drawPath(sheetTagRing(box, SheetTagKind.cham), _fill(mixOklab(c, ink, .84)));
  }

  /// 사건 점의 빛깔(그림판 events.dart `_Tone`): 채움 = 제 색 80% + 먹 · 둘레 = 제 색 15% + 종이 · 미정 = 종이와 85%.
  static int eventFill(int c) => mixSrgb(c, ink, .80);
  static int eventHalo(int c) => mixSrgb(c, paper, .15);
  static int eventUnknown(int c) => mixSrgb(over(c, paper), paper, .85);

  // ---- 견본 ----

  void sample(LegendRow row, Size size) {
    final rgb = row.rgb, c = 0xff000000 | rgb;
    final full = Rect.fromLTWH(0, 0, _w, size.height);
    final top = Rect.fromLTWH(0, 0, _w, LegendLook.head);
    String nm(String fallback) => row.label ?? fallback;
    switch (row.mark) {
      case LegendMark.tag:
        final hs = BandLook.hsOf(row.look);
        tag(top, rgb, row.look, name: nm('설원 제국'), badge: const ['', '반전설', '전설', '논쟁', '부정'][hs.clamp(0, 4)]);
      case LegendMark.tagRange:
        tag(top, rgb, row.look | BandLook.hasRange, name: nm('설원 제국'), range: true);
      case LegendMark.tagUnknown:
        tag(top, rgb, row.look, name: nm('설원 제국'), fuzzy: true);
      case LegendMark.floor:
        tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('온유', 0), ('온결', .36), ('온서', .68)],
        ]);
      case LegendMark.power:
        // 실권 밑줄(그림판 BandLayer.powerTop · powerHeight · powerMix · powerNameMix): 머리 아랫변 위 2px · 쥔 쪽 색 80% + 먹 · 끝 이름 8 굵게.
        tag(top, rgb, row.look, name: nm('설원 제국'));
        const holder = 0xff000000 | LegendTint.slate;
        final ux0 = (_w * .5).roundToDouble(), ux1 = _w - 3;
        rect(ux0, 19, ux1, 19 + BandLayer.powerHeight, mixSrgb(holder, ink, BandLayer.powerMix));
        text('북설 칸국', ux1 - 3, 13, 8, mixSrgb(holder, ink, BandLayer.powerNameMix), bold: true, end: true);
      case LegendMark.borrow:
        tag(full, LegendTint.mocha, row.look, name: nm('등불 교단'), trail: '· 지도자 ← 성좌령', dashedFloor: true, quietCells: true, floors: const [
          [('서하', 0), ('온결', .36), ('다빈', .68)],
        ]);
      case LegendMark.event || LegendMark.eventHollow || LegendMark.eventUnknown || LegendMark.treaty:
        eventCell(top, rgb);
        const cx = 14.5, cy = 12.0;
        switch (row.mark) {
          case LegendMark.event:
            circle(cx, cy, 6.5, fill: eventHalo(c));
            circle(cx, cy, 3.5, fill: eventFill(c));
          case LegendMark.eventHollow:
            circle(cx, cy, 6.5, fill: eventHalo(c));
            circle(cx, cy, 3.5, fill: c);
            circle(cx, cy, 1.5, fill: paper);
          case LegendMark.eventUnknown:
            circle(cx, cy, 5, fill: paper);
            dashCircle(cx, cy, 4.5, eventUnknown(c));
          default:
            diamond(cx, cy, 8, eventHalo(c));
            diamond(cx, cy, 5, eventFill(c));
            diamond(cx + 16, cy, 6.4, c);
            diamond(cx + 16, cy, 3.4, paper);
        }
        text(nm(row.mark == LegendMark.treaty ? '설원 맹약' : '설원 건국'), row.mark == LegendMark.treaty ? 40 : 26, cy, LegendLook.event, ink85, bold: true);
      case LegendMark.rail || LegendMark.railAlt || LegendMark.railTreaty:
        eventCell(top, rgb);
        final l = row.mark == LegendMark.railAlt ? 22.0 : 10.0, r = row.mark == LegendMark.railAlt ? 82.0 : 86.0;
        _rail(l, r, 12, c, treaty: row.mark == LegendMark.railTreaty);
        if (row.mark == LegendMark.railAlt) {
          // 이설의 시작 · 끝 = 점선 세로바(1.5 × 9 · 2 / 2).
          for (final x in [10.0, 96.0]) {
            for (var y = 12 - RailLook.altHeight / 2; y < 12 + RailLook.altHeight / 2; y += RailLook.altDash + RailLook.altGap) {
              rect(x, y, x + RailLook.altWidth, math.min(12 + RailLook.altHeight / 2, y + RailLook.altDash), RailLook.edge(rgb));
            }
          }
        }
        if (row.mark == LegendMark.railTreaty) {
          final mx = (l + r) / 2;
          diamond(mx, 12, RailLook.effectRing / math.sqrt2, paper);
          diamond(mx, 12, RailLook.effect / math.sqrt2, RailLook.edge(rgb));
        }
        text(nm(row.mark == LegendMark.railTreaty ? '설원 조약' : '대기근'), (row.mark == LegendMark.railAlt ? 104.0 : r) + 6, 12, LegendLook.event, ink85, bold: true);
      case LegendMark.beads:
        eventCell(top, rgb);
        hLine(10, 98, 12, RailLook.edgeSoft(rgb), dash: RailLook.dotDash, gap: RailLook.dotGap);
        circle(10.5, 12.5, RailLook.bead / 2, fill: RailLook.edge(rgb));
        for (final x in [54.5, 98.5]) {
          circle(x, 12.5, RailLook.bead / 2 - .5, fill: paper, stroke: RailLook.edge(rgb));
        }
        text(nm('천도'), 108, 12, LegendLook.event, ink85, bold: true);
      case LegendMark.cell:
        tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('설원 왕조', 0)],
          [('온유', 0), ('온결', .36), ('온서', .68)],
        ]);
      case LegendMark.axis:
        _axis(LegendTint.sky);
      case LegendMark.catLines:
        eventCell(full, rgb);
        hLine(1, _w - 1, 20, mixSrgb(over(mixOklab(c, ink, .92), paper), paper, .45), dash: 1, gap: 2);
        for (final (y, tint, s) in [(10.5, LegendTint.rose, '호반 맹약'), (29.5, LegendTint.mint, '등불 공의회')]) {
          circle(12.5, y, 3, fill: eventFill(0xff000000 | tint));
          text(s, 22, y, LegendLook.event, ink85, bold: true);
        }
      case LegendMark.bird:
        // 조감(띠 하나 14 · 이름은 띠 안 왼쪽 6 · 10 굵게 · 사건은 작은 점).
        final b = Rect.fromLTWH(0, 5, _w, 14);
        final tone = BandLayer.toneOf(rgb, row.look, fuzzy: false);
        final rr = RRect.fromRectAndRadius(b.deflate(.5), const Radius.circular(4.5));
        canvas.drawRRect(rr, _fill(tone.fill));
        canvas.drawDRRect(rr.inflate(.5), rr.deflate(.5), _fill(tone.edge));
        final w = text(nm('설원 제국'), 6, 12, 10, mixSrgb(c, ink, .30), bold: true);
        for (final x in [w + 20, w + 44, w + 58]) {
          circle(x.roundToDouble() + .5, 12, 2, fill: eventFill(c));
        }
      case LegendMark.cellSpot:
        final t = tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('온유', 0), ('온결', .36), ('온서', .68)],
        ]);
        final lo = 6.0, hi = _w - 2, a = (lo + .36 * (hi - lo)).roundToDouble() + 1, z = (lo + .68 * (hi - lo)).roundToDouble();
        rect(a, LegendLook.head, z, 39, mixSrgb(c, paper, .45));
        rect(a, 1, z, LegendLook.head - 1, withAlpha(paper, .5));
        text('온결', a + 2, 31.5, LegendLook.cellName, mixSrgb(c, ink, .45));
        vLine(a - 1, LegendLook.head, 39, t.line);
      case LegendMark.cellAlt:
        tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('온유', 0), ('온결', .45)],
        ]);
        vLine(52, LegendLook.head + FigureLook.ghostInset, 39 - FigureLook.ghostInset, withAlpha(mixOklab(c, ink, .92), FigureLook.ghostMix), dash: FigureLook.ghostDash, gap: FigureLook.ghostGap);
      case LegendMark.cellFuzzy:
        final t = tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('온유', 0), ('온결', .55)],
        ]);
        stripes(const Rect.fromLTRB(64, LegendLook.head, 92, 39), 90, 2, 6, mixSrgb(c, paper, .14));
        vLine(64, LegendLook.head, 39, t.line, dash: 2, gap: 2);
        vLine(91, LegendLook.head, 39, t.line, dash: 2, gap: 2);
      case LegendMark.phase:
        tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('전기', 0), ('후기', .5)],
        ]);
        rect(1, LegendLook.head, 75, 39, withAlpha(c, .12));
      case LegendMark.ranks:
        tag(full, rgb, row.look, name: nm('설원 제국'));
        for (var i = 0; i < 5; i++) {
          final l = 1.0 + i * 29.2, r = i == 4 ? _w - 1 : 1.0 + (i + 1) * 29.2 - 1;
          rect(l.roundToDouble(), LegendLook.head, r.roundToDouble(), 39, i == 0 ? paper : mixSrgb(c, paper, const [0.0, .08, .22, .38, .56][i]));
        }
        hLine(1, _w - 1, LegendLook.head - 1, mixSrgb(over(mixOklab(c, ink, .84), paper), paper, BandLayer.innerLine));
      case LegendMark.house:
        tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('온유', 0), ('온결', .36), ('온서', .68)],
        ]);
        final lo = 6.0, hi = _w - 2;
        rect((lo + .36 * (hi - lo)).roundToDouble() + 3, 35, (lo + .68 * (hi - lo)).roundToDouble() - 3, 37, mixSrgb(0xff000000 | LegendTint.lav, ink, .72));
      case LegendMark.cellUnknown:
        final t = tag(full, rgb, row.look, name: nm('설원 제국'), floors: const [
          [('온유', 0), ('온결', .5)],
        ]);
        // 끝을 모르는 칸: 그쪽 끝이 칸 안에서 옅어진다 · 칸 사이 금이 점선.
        final p = Paint()..shader = ui.Gradient.linear(const Offset(_w - 40, 0), const Offset(_w - 1, 0), [Color(withAlpha(paper, 0)), Color(paper)]);
        canvas.drawRect(const Rect.fromLTRB(_w - 40, LegendLook.head, _w - 1, 39), p);
        final x = (6 + .5 * (_w - 8)).roundToDouble();
        rect(x, LegendLook.head, x + 1, 39, mixSrgb(mixSrgb(0xff000000 | rgb, paper, .24), paper, BandLayer.bodyTint));
        vLine(x, LegendLook.head, 39, t.line, dash: 2, gap: 2);
      case LegendMark.figure:
        tag(full, rgb, row.look, name: nm('설원 제국'));
        const bar = 0xff000000 | LegendTint.sky;
        final b = RRect.fromRectAndRadius(const Rect.fromLTRB(18, 25, 118, 25 + FigureLook.height), const Radius.circular(FigureLook.radius));
        canvas.drawRRect(b, _fill(mixSrgb(bar, paper, .35)));
        hLine(4, 18, 32, withAlpha(mixSrgb(bar, ink, .5), FigureLook.lifeAlpha));
        hLine(118, 140, 32, withAlpha(mixSrgb(bar, ink, .5), FigureLook.lifeAlpha));
        text('은 하림', 26, 32.5, 10, ink85, weight: FontWeight.w500);
      case LegendMark.found:
        // 건국 = 꼬리표 왼쪽 위의 구멍(그림판 links.dart `_paintSquare` — 흰 동그라미 + 1px 테 먹 45).
        tag(top, rgb, row.look, name: nm('설원 제국'));
      case LegendMark.end:
        tag(top, rgb, row.look, name: nm('설원 제국'));
        diamond(_w - .5 - TagLook.diamondX, 6.5, TagLook.diamondHalf * math.sqrt2, mixOklab(c, ink, .6));
      case LegendMark.foundUnknown:
        // 시작을 모르는 끝: 구멍 대신 점선 동그라미(그림판 LinkSprites.dashRing — 반지름 4 · 굵기 1.4 · 호 여섯 · 띠 테 빛깔).
        final t = tag(top, rgb, row.look, name: nm('설원 제국'), withHole: false);
        dashCircle(t.hole.dx, t.hole.dy, 4, t.edge, width: 1.4, count: 6, ratio: .55);
      case LegendMark.succession || LegendMark.indirect || LegendMark.revival || LegendMark.partial:
        _succession(row.mark);
      case LegendMark.join:
        // 합류: 선대(위)의 꼬리 마름모 밑에서 곧게 내려가 후대 띠 윗테에 닿고, 닿는 자리에 선대 색의 짧은 조각.
        tag(const Rect.fromLTWH(0, 0, 92, 24), LegendTint.rose, 0, name: nm('하연'));
        final dx = 92 - .5 - TagLook.diamondX;
        final ink0 = LinkLook.inkOf(LegendTint.rose);
        rect(dx - .8, 9, dx + .8, 30, ink0);
        tag(const Rect.fromLTWH(20, 30, _w - 20, 24), LegendTint.pink, 0, name: '새하연');
        rect(dx - 5, 30, dx + 5, 30 + LinkLook.joinH, 0xff000000 | LegendTint.rose);
        diamond(dx, 6.5, TagLook.diamondHalf * math.sqrt2, mixOklab(0xff000000 | LegendTint.rose, ink, .6));
      case LegendMark.partOf:
        // 소속선: 상위 띠 아래에 접혀 든 정권 ↔ 상위 정권(점선 — 부분 승계의 박자 2 · 3).
        tag(const Rect.fromLTWH(0, 0, _w, 24), LegendTint.peri, 0, name: '설원 제국');
        tag(const Rect.fromLTWH(26, 30, _w - 26, 24), LegendTint.slate, BandKind.vassal | BandLook.famDep, name: nm('북설 칸국'));
        final ink0 = LinkLook.inkOf(LegendTint.peri);
        vLine(12, 24, 42, ink0, dash: LinkLook.partDash, gap: LinkLook.partGap);
        hLine(13, 26, 42, ink0, dash: LinkLook.partDash, gap: LinkLook.partGap);
      case LegendMark.union:
        // 동군연합: 위아래 두 지도자 칸(층)을 꿰는 줄(먹 60 · 1.5)과 끝의 고리(지름 7 · 테 1.5 먹).
        for (final (y, tint, s) in [(0.0, LegendTint.peri, '온하'), (24.0, LegendTint.slate, '온하')]) {
          final b = Rect.fromLTWH(0, y, _w, LegendLook.floor);
          final cc = 0xff000000 | tint;
          canvas.drawPath(sheetTagPath(b, SheetTagKind.cham, chamfer: 4), _fill(mixSrgb(mixSrgb(cc, paper, .24), paper, BandLayer.bodyTint)));
          canvas.drawPath(sheetTagRing(b, SheetTagKind.cham, chamfer: 4), _fill(mixOklab(cc, ink, .84)));
          text(s, 10, y + 8, LegendLook.cellName, mixSrgb(cc, ink, .45));
        }
        const ux = 74.5;
        canvas.drawLine(const Offset(ux, 8 + UnionLook.ring), const Offset(ux, 32 - UnionLook.ring), _line(mixSrgb(ink, paper, UnionLook.ink), UnionLook.width));
        for (final y in [8.0, 32.0]) {
          circle(ux, y, UnionLook.ring - .75, fill: paper, stroke: ink, width: UnionLook.ringEdge);
        }
      case LegendMark.hangOut:
        tag(top, LegendTint.peri, 0, name: '설원 제국');
        // 매달린 이름표(띠 아랫변 밑 2px 끼움 · 아래 귀 6 · 글 8 · 왼쪽 7): 빈 탭 = 스스로 다스림, 칠한 탭 = 종속.
        for (final (l, r, filled, s) in [(10.0, 70.0, false, '조공국'), (76.0, 136.0, true, '종속국')]) {
          final b = Rect.fromLTRB(l, 22, r, 22 + HangLook.tuck + 13 + 4);
          const tint = 0xff000000 | LegendTint.slate;
          final rr = RRect.fromRectAndCorners(b.deflate(.5), bottomLeft: const Radius.circular(HangLook.radius), bottomRight: const Radius.circular(HangLook.radius));
          canvas.drawRRect(rr, _fill(filled ? mixSrgb(tint, paper, .45) : paper));
          canvas.drawRRect(rr, _line(mixOklab(tint, ink, .84)));
          text(s, l + HangLook.textLeft, 33, HangLook.hangSize, mixSrgb(tint, ink, .25), weight: FontWeight.w600);
        }
        // 띠의 아랫테는 매단 탭 위에 다시(탭이 띠 밑에 끼워진 꼴).
        hLine(1, _w - 1, 23, mixOklab(0xff000000 | LegendTint.peri, ink, .84));
      case LegendMark.hangIn:
        tag(full, LegendTint.peri, 0, name: '설원 제국', floors: const [[]]);
        for (final (l, r, a, s) in [(6.0, 70.0, .18, '괴뢰국'), (74.0, 142.0, .45, '군현')]) {
          const tint = 0xff000000 | LegendTint.slate;
          rect(l, 26, r, 37, mixSrgb(tint, paper, a));
          text(s, l + 4, 31.5, HangLook.hangSize, mixSrgb(tint, ink, .3), weight: FontWeight.w600);
        }
      case LegendMark.host:
        _host();
      case LegendMark.person:
        _person();
      case LegendMark.folder:
        _folder(nm('아홉 불씨 연방'));
      case LegendMark.box:
        _box();
      case LegendMark.closedBox:
        _closedBox();
      case LegendMark.hollow:
        // 할거기: 상징적 본국 띠의 그 기간이 속 빈 모양 — 종이 92% · 위아래 2px 남김 · 좌우 1px 점선(제 색 70% + 먹 · 짙기 .6).
        tag(top, rgb, row.look, name: nm('설원 제국'));
        const l = 74.0, r = 128.0;
        rect(l, 1 + ScopeLook.hollowClear, r, LegendLook.head - 1 - ScopeLook.hollowClear, withAlpha(paper, ScopeLook.hollowPaper));
        final e = withAlpha(mixSrgb(c, ink, .7), ScopeLook.hollowEdgeAlpha);
        vLine(l, 1, LegendLook.head - 1, e, dash: 3, gap: 3);
        vLine(r - 1, 1, LegendLook.head - 1, e, dash: 3, gap: 3);
      case LegendMark.joint || LegendMark.regent || LegendMark.nominal || LegendMark.claim:
        _legit(row.mark);
    }
  }

  /// 기간 사건의 가는 선(그림판 RailLook): 몸 2 · 제 색 92% + 먹(옅은 테) · 양 끝 세로바 1.5 × 6(테) — 조약은 위아래 1px 두 줄.
  void _rail(double l, double r, double cy, int c, {bool treaty = false}) {
    final rgb = c & 0xffffff;
    final soft = RailLook.edgeSoft(rgb), edge = RailLook.edge(rgb);
    if (treaty) {
      hLine(l, r, cy - 2, soft);
      hLine(l, r, cy + 1, soft);
    } else {
      rect(l, cy - 1, r, cy + 1, soft);
    }
    for (final x in [l, r - RailLook.cap]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, cy - RailLook.capHeight / 2, RailLook.cap, RailLook.capHeight), const Radius.circular(.75)), _fill(edge));
    }
  }

  /// 날짜 칸의 묶음 줄: 한 왕조의 연호 · 한 정권의 도읍은 하나의 긴 둥근 칸(가는 구분선) · 임시 도읍 = 점선 칸.
  void _axis(int rgb) {
    final c = 0xff000000 | rgb;
    final fill = mixSrgb(c, paper, .24), edge = mixOklab(c, ink, .84), ink0 = mixSrgb(c, ink, .30);
    final long = RRect.fromRectAndRadius(const Rect.fromLTRB(.5, 5.5, 104.5, 18.5), const Radius.circular(4));
    canvas.drawRRect(long, _fill(fill));
    canvas.drawDRRect(long.inflate(.5), long.deflate(.5), _fill(edge));
    vLine(52, 6, 18, mixSrgb(edge, paper, .45));
    text('건원', 6, 12, LegendLook.cellName, ink0, bold: true);
    text('태평', 58, 12, LegendLook.cellName, ink0, bold: true);
    final temp = RRect.fromRectAndRadius(const Rect.fromLTRB(108.5, 5.5, 147.5, 18.5), const Radius.circular(4));
    canvas.drawRRect(temp, _fill(paper));
    canvas.drawPath(sheetDashed(Path()..addRRect(temp), const [2, 2]), _line(edge));
    text('임시', 114, 12, LegendLook.cellName, ink0, bold: true);
  }

  /// 승계 실 넷(직접 · 간접 · 부흥 · 부분): 선대의 꼬리 마름모에서 후대의 구멍으로 — 빛깔은 선대 띠의 테([LinkLook.inkOf]).
  void _succession(LegendMark m) {
    final a = tag(const Rect.fromLTWH(0, 0, 62, 24), LegendTint.rose, 0, name: '하연');
    final b = tag(const Rect.fromLTWH(78, 0, 70, 24), LegendTint.pink, m == LegendMark.revival ? BandKind.movement : 0, name: '새하연');
    final ink0 = LinkLook.inkOf(LegendTint.rose);
    final x0 = 62 - .5 - TagLook.diamondX, x1 = b.hole.dx - TagLook.holeR - .5, y = a.hole.dy;
    switch (m) {
      case LegendMark.partial:
        rect(x0, y.floorToDouble(), x1, y.floorToDouble() + LinkLook.thinW, ink0);
      case LegendMark.indirect || LegendMark.revival:
        for (var x = x0; x < x1; x += LinkLook.dash + LinkLook.gap) {
          rect(x, y - LinkLook.width / 2, math.min(x1, x + LinkLook.dash), y + LinkLook.width / 2, ink0);
        }
      default:
        rect(x0, y - LinkLook.width / 2, x1, y + LinkLook.width / 2, ink0);
    }
    if (m == LegendMark.revival) circle(78 - 4.5, y, LinkLook.ringR - .5, fill: paper, stroke: ink0, width: 1.2);
    hole(b.hole); // 구멍은 실 위에 다시(실이 구멍 테 안으로 들지 않게).
    diamond(x0, y, TagLook.diamondHalf * math.sqrt2, mixOklab(0xff000000 | LegendTint.rose, ink, .6));
  }

  /// 섬김 받침(뒤 장 · 상국 탭 — 목업 `host`): 속국 띠 뒤에 상국 빛깔의 받침 카드, 관계가 끝나는 쪽 윗변에 상국 이름 탭(12 · 모따기 4 · 글 8.5).
  void _host() {
    const hc = 0xff000000 | LegendTint.peri;
    final fill = mixOklab(hc, paper, BandLayer.sheetMix[1]), edge = mixOklab(hc, ink, .78);
    const s = '설원 제국';
    final tw = text(s, -1000, -1000, 8.5, 0, weight: FontWeight.w600);
    const card = Rect.fromLTRB(6, 13, _w, 37);
    canvas.drawPath(sheetTagPath(card, SheetTagKind.cham), _fill(fill));
    canvas.drawPath(sheetTagRing(card, SheetTagKind.cham), _fill(edge));
    final tr = _w - 8.0, tl = (tr - tw - 14).roundToDouble();
    final tab = Path()
      ..moveTo(tl, 14)
      ..lineTo(tl, 1 + TagLook.tabCham)
      ..lineTo(tl + TagLook.tabCham, 1)
      ..lineTo(tr, 1)
      ..lineTo(tr, 14)
      ..close();
    canvas.drawPath(tab, _fill(fill));
    rect(tl, 1, tr, 2, edge);
    vLine(tl, 1 + TagLook.tabCham, 13, edge);
    vLine(tr - 1, 1, 13, edge);
    canvas.drawLine(Offset(tl + .5, 1 + TagLook.tabCham), Offset(tl + TagLook.tabCham, 1.5), _line(edge));
    text(s, tl + 7, 7.5, 8.5, mixOklab(hc, ink, .45), weight: FontWeight.w600);
    // 띠 둘레의 바탕빛 틈 1.5(그림판 sheetGap) 뒤에 속국 띠.
    canvas.drawPath(sheetTagPath(const Rect.fromLTRB(-1.5, 16.5, _w - 4.5, 43.5), SheetTagKind.cham, chamfer: 6.5), _fill(paper));
    tag(const Rect.fromLTRB(0, 18, _w - 6, 42), LegendTint.peach, BandKind.fief | BandLook.famDep, name: '백사 공국');
  }

  /// 사람 띠(목업 `person` · 그림판 SphereLinesLook): 흰 종이 둥근 끝 8 · 테 먹 50 · 구멍 · 이름 10 굵게 + 때 10 ·
  /// 왕관마다 점선 실(1.2 · 1/3 · 먹 50)이 내려가 그 칸 꼬리표 윗변의 뿔(밑 5 · 높이 4.5)에 닿는다.
  void _person() {
    const s1 = '은 하림', s2 = '780 ~ 836 · 왕관 2';
    final edge = mixSrgb(ink, paper, SphereLinesLook.personEdge);
    final w1 = text(s1, -1000, -1000, 10, 0, bold: true), w2 = text(s2, -1000, -1000, 10, 0);
    final pw = (SphereLinesLook.personPadLeft + w1 + SphereLinesLook.personGap + w2 + SphereLinesLook.personPadRight).ceilToDouble();
    for (final (x, w, s, tint) in [(10.0, 60.0, '설원', LegendTint.peri), (76.0, _w - 76, '북설', LegendTint.slate)]) {
      tag(Rect.fromLTWH(x, 28, w, 24), tint, 0, name: s);
      final kx = x + 18.5, top = 28.5;
      final thread = Path()
        ..moveTo(kx, 16)
        ..lineTo(kx, top - SphereThreadLook.horn);
      canvas.drawPath(sheetDashed(thread, const [SphereThreadLook.dash, SphereThreadLook.gap]), _line(mixSrgb(ink, paper, SphereThreadLook.ink), SphereThreadLook.width)..strokeCap = StrokeCap.round);
      final horn = Path()
        ..moveTo(kx - SphereThreadLook.hornBase / 2, top)
        ..lineTo(kx, top - SphereThreadLook.horn)
        ..lineTo(kx + SphereThreadLook.hornBase / 2, top)
        ..close();
      canvas.drawPath(horn, _fill(paper));
      canvas.drawPath(horn, _line(mixSrgb(ink, paper, SphereThreadLook.hornInk))..strokeJoin = StrokeJoin.round);
    }
    final band = Rect.fromLTWH(0, 0, math.min(pw, _w), 16);
    canvas.drawPath(sheetTagPath(band, SheetTagKind.key, round: SphereLinesLook.personRadius), _fill(paper));
    canvas.drawPath(sheetTagRing(band, SheetTagKind.key, round: SphereLinesLook.personRadius), _fill(edge));
    circle(8.5, 8, SphereLinesLook.holeSize / 2, fill: paper, stroke: ink45);
    final x = SphereLinesLook.personPadLeft;
    text(s1, x, 8, 10, SphereLinesLook.personName.color, bold: true);
    text(s2, x + w1 + SphereLinesLook.personGap, 8, 10, SphereLinesLook.personWhen.color);
  }

  /// 폴더(가장 바깥 그릇 — 그림판 FolderLook): 둥근 10 · 칠 제 색 9% · 테 55% · 안쪽 겹선 먹 12 · 어깨 탭 15(이름 10 굵게 + 수) · 안의 꼬리표는 몸통 윗변에 실로.
  void _folder(String s) {
    const c = 0xff000000 | LegendTint.butter;
    final fill = mixSrgb(c, paper, FolderLook.fillPct), edge = mixOklab(c, paper, FolderLook.edgePct), ink0 = mixSrgb(c, ink, .25);
    const x0 = .5, x1 = _w - .5, y = 15.5, bh = 36.0;
    hLine(x0 + 18, x1 - 18, y - 3.5, mixOklab(c, paper, .35));
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(x0, y, _w - 1, bh), const Radius.circular(FolderLook.radius));
    canvas.drawRRect(body, _fill(fill));
    canvas.drawDRRect(body.inflate(.5), body.deflate(.5), _fill(edge));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(x0 + 3, y + 3, _w - 7, bh - 6), const Radius.circular(7)), _line(ink12));
    final nw = text(s, -1000, -1000, 10, 0, bold: true), cw = text('3', -1000, -1000, 10, 0);
    final tl = x0 + 10, tr = (tl + 8 + nw + 4 + cw + 10).roundToDouble() + .5;
    final tab = sheetTabPath(tl, tr, y, height: 15);
    canvas.drawPath(tab.fill, _fill(fill));
    canvas.drawPath(tab.stroke, _line(edge));
    text(s, tl + 9, y - 7.5, 10, ink0, bold: true);
    text('3', tl + 9 + nw + 4, y - 7.5, 10, ink45);
    final t = tag(const Rect.fromLTWH(18, 22, _w - 30, 24), LegendTint.butter, 0, name: '등불 성좌령');
    _thread(t.hole, y);
  }

  /// 매다는 실 — 매듭(지름 3)에서 구멍 위까지 곧게(먹 45).
  void _thread(Offset hole, double knot) {
    rect(hole.dx - .5, knot + 1.5, hole.dx + .5, hole.dy - TagLook.holeR - 1, ink45);
    circle(hole.dx, knot, 1.5, fill: ink45);
  }

  /// 상자(안쪽 그릇): 모따기 6 · 테 먹 25 · 칠 먹 4 · 뚜껑 밑선 먹 12 · 흰 라벨(9.5 굵게) + 수.
  void _box() {
    const b = Rect.fromLTWH(0, 0, _w, 50);
    canvas.drawPath(sheetBoxPath(b), _fill(ink4));
    canvas.drawPath(sheetLidPath(b, lid: 14), _fill(ink4));
    hLine(1, _w - 1, 14, ink12);
    canvas.drawPath(sheetBoxRing(b), _fill(ink25));
    const s = '도시';
    final lw = (text(s, -1000, -1000, 9.5, 0, bold: true) + 12).roundToDouble();
    final label = RRect.fromRectAndRadius(Rect.fromLTWH(6.5, 2.5, lw, 10), const Radius.circular(2));
    canvas.drawRRect(label, _fill(paper));
    canvas.drawRRect(label, _line(ink45));
    text(s, 12.5, 7.5, 9.5, ink85, bold: true);
    text('3', 6.5 + lw + 4, 7.5, 9, ink45);
    final t = tag(const Rect.fromLTWH(44, 21, _w - 54, 24), LegendTint.peach, 0, name: '도가니 자유시');
    _thread(t.hole, 14.5);
  }

  /// 접힌 상자: 안의 꼬리표를 작게(키 13 · 이름 8.5) · 넘치면 +n · 오른쪽 끝 ›.
  void _closedBox() {
    const b = Rect.fromLTWH(0, 0, _w, 24);
    canvas.drawPath(sheetBoxPath(b), _fill(ink4));
    canvas.drawPath(sheetBoxRing(b), _fill(ink25));
    hLine(1, _w - 1, 6, ink12);
    const s = '청림';
    var x = 7.5 + text(s, 7.5, 14, 10, ink85, bold: true) + 4;
    x = (x + text('6', x, 14, 10, ink45) + 8).roundToDouble();
    const tint = 0xff000000 | LegendTint.sage;
    const ts = '청림 후국';
    final w1 = (text(ts, -1000, -1000, 8.5, 0, bold: true) + 12).roundToDouble();
    final small = Rect.fromLTWH(x, 7, w1, 13);
    canvas.drawPath(sheetTagPath(small, SheetTagKind.cham, chamfer: 3), _fill(mixSrgb(tint, paper, .24)));
    canvas.drawPath(sheetTagRing(small, SheetTagKind.cham, chamfer: 3), _fill(mixOklab(tint, ink, .84)));
    circle(x + 5, 12, 1.5, fill: paper, stroke: ink45);
    text(ts, x + 9, 14, 8.5, mixSrgb(tint, ink, .22), bold: true);
    x += w1 + 3;
    const ms = '+5';
    final mw = (text(ms, -1000, -1000, 9, 0) + 10).roundToDouble();
    final more = RRect.fromRectAndRadius(Rect.fromLTWH(x + .5, 7.5, mw, 12), const Radius.circular(2));
    canvas.drawRRect(more, _fill(paper));
    canvas.drawRRect(more, _line(ink25));
    text(ms, x + 5.5, 14, 9, ink60);
    // ›(오른쪽 끝 18 안).
    final p = Path()
      ..moveTo(_w - 14, 9.5)
      ..lineTo(_w - 10.5, 13)
      ..lineTo(_w - 14, 16.5);
    canvas.drawPath(p, _line(ink45, 1.2)..strokeCap = StrokeCap.round);
  }

  // ---- 정통성(lg2-ga 그대로) ----

  /// 정통성 견본 — 그림판 꼬리표(머리 24 · 이름 9) + 지도자 층(흰 종이 · 겹친 기간이 있으면 두 단 16 + 16):
  /// 공동 = 겹친 기간은 반 칸 둘 · 섭정 = 그 기간 칸 아랫변 안 2px 먹 60 · 명목 = 이름 먹 45 · 주장 = 칸 바탕 1px 화소 빗금(먹 25 · 5px — 이름 둘레는 종이 받침).
  void _legit(LegendMark m) {
    final (rgb, name, cells, regent) = switch (m) {
      LegendMark.joint => (LegendTint.rose, '하연 왕국', const [('온결', 0.0, .62, ''), ('다빈', .34, 1.0, 'joint')], null),
      LegendMark.regent => (LegendTint.rose, '하연 왕국', const [('무령', 0.0, 1.0, '')], (0.0, .46)),
      LegendMark.nominal => (LegendTint.peri, '설원 제국', const [('온서', 0.0, .42, ''), ('온하', .42, 1.0, 'nominal')], null),
      _ => (LegendTint.peri, '설원 제국', const [('온담', 0.0, .38, ''), ('온새', .38, 1.0, 'claim')], null),
    };
    final c = 0xff000000 | rgb;
    final lanes = cells.any((q) => q.$4 == 'joint') ? 2 : 1;
    final hf = lanes * LegendLook.floor, h = LegendLook.head + hf;
    final box = Rect.fromLTWH(0, 0, _w, h);
    final edge = mixOklab(c, ink, .84);
    final outline = sheetTagPath(box, SheetTagKind.cham);
    final ft = LegendLook.head - .5; // 머리 밑선(반 픽셀)
    canvas.save();
    canvas.clipPath(outline);
    rect(0, 0, _w, LegendLook.head, mixSrgb(c, paper, .24));
    rect(0, LegendLook.head, _w, h, paper);
    canvas.restore();
    hLine(1, _w - 1, LegendLook.head - 1, edge);
    // 칸 — 경계는 화소 열 · 조각마다 함께 있는 칸 · 겹치면 제 단.
    const lo = 6.0, hi = _w - 2;
    double col(double f) => (lo + f * (hi - lo)).roundToDouble();
    final cs = [for (var i = 0; i < cells.length; i++) (n: cells[i].$1, a: cells[i].$2, e: cells[i].$3, st: cells[i].$4, j: i > 0 && lanes > 1 ? 1 : 0)];
    final ts = {for (final q in cs) ...[q.a, q.e]}.toList()..sort();
    final pieces = <({double a, double e, double c0, double c1, List<int> act})>[];
    for (var i = 0; i + 1 < ts.length; i++) {
      final act = [for (var q = 0; q < cs.length; q++) if (cs[q].a <= ts[i] && cs[q].e >= ts[i + 1]) q];
      if (act.isNotEmpty) pieces.add((a: ts[i], e: ts[i + 1], c0: col(ts[i]), c1: col(ts[i + 1]), act: act));
    }
    (double, double) slot(({double a, double e, double c0, double c1, List<int> act}) pc, int q) =>
        pc.act.length == 1 ? (ft, ft + hf) : (ft + cs[q].j * LegendLook.floor, ft + (cs[q].j + 1) * LegendLook.floor);
    final at = <int, ({int pc, double y0, double y1, double nw})>{};
    for (var q = 0; q < cs.length; q++) {
      for (var p = 0; p < pieces.length; p++) {
        if (!pieces[p].act.contains(q)) continue;
        final nw = text(cs[q].n, -1000, -1000, 8.5, 0);
        if (nw > pieces[p].c1 - pieces[p].c0 - 8) continue;
        final s = slot(pieces[p], q);
        at[q] = (pc: p, y0: s.$1, y1: s.$2, nw: nw);
        break;
      }
    }
    for (var p = 0; p < pieces.length; p++) {
      final pc = pieces[p];
      for (final q in pc.act) {
        if (cs[q].st != 'claim') continue;
        final s = slot(pc, q), mine = at[q];
        final x0 = mine != null && mine.pc == p ? (pc.c0 + 4 + mine.nw + 4).ceilToDouble() : pc.c0;
        if (pc.c1 - x0 < 1) continue;
        // 1px 화소 계단 빗금(5px 칸 · 먹 25).
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(x0, s.$1 + .5, pc.c1, s.$2 - .5));
        for (var y = (s.$1 + .5).floorToDouble(); y < s.$2; y += 5) {
          for (var x = 0.0; x < _w; x += 5) {
            for (var i = 0; i < 5; i++) {
              rect(x + i, y + 4 - i, x + i + 1, y + 5 - i, ink25);
            }
          }
        }
        canvas.restore();
      }
    }
    for (final pc in pieces) {
      if (pc.act.length > 1) hLine(pc.c0, pc.c1 + 1, ft + LegendLook.floor - .5, ink25);
    }
    for (var q = 0; q < cs.length; q++) {
      for (final (t, right) in [(cs[q].a, true), (cs[q].e, false)]) {
        if (t <= 0 || t >= 1) continue;
        final p = pieces.indexWhere((r) => (right ? r.a == t : r.e == t) && r.act.contains(q));
        if (p < 0) continue;
        final s = slot(pieces[p], q);
        vLine(right ? pieces[p].c0 : pieces[p].c1, s.$1 + .5, s.$2 - .5, ink25);
      }
    }
    if (regent != null) {
      final l = col(regent.$1) + 1, r = col(regent.$2);
      rect(l, h - 3, r, h - 1, ink60);
    }
    for (final MapEntry(key: q, value: v) in at.entries) {
      text(cs[q].n, pieces[v.pc].c0 + 4, (v.y0 + v.y1) / 2, 8.5, cs[q].st == 'nominal' ? ink45 : mixSrgb(c, ink, .45));
    }
    canvas.drawPath(sheetTagRing(box, SheetTagKind.cham), _fill(edge));
    final hc = holeOf(box, TagEnd.cham);
    hole(hc);
    text(name, hc.dx + 7, 12, LegendLook.name, mixSrgb(c, ink, .22), bold: true);
  }
}
