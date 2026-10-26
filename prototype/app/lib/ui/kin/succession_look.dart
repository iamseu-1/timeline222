import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../shell/motion_widgets.dart' show MotionPress;
import '../../shell/sheet_look.dart';
import '../../shell/sheet_parts.dart';
import '../detail_shell.dart' show detailString;
import 'kin_head.dart' show SeamLine;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  승계표의 서고 꼴 — 이름띠(지도자 꼬리표) · 실 · 열쇠표 · 제목 꼬리표 · 범례 그리개.
//  감독 고름 G5 #9 '서고로 다시 그림'의 다듬기 판(`.claude/research/stage4-choose/themes/g-sheet-succ.js` — git 밖)을 앱으로 옮겼다.
//  좁은 창(상세 칸 — `succession_view.dart`)은 위에서 아래로 계승하고(감독 "원래처럼 위아래로"), 넓은 창(화면 아래 서랍 — 리메이크 4단계
//  틀의 시트와 창 걸음 7)은 같은 그리개로 가로로 잇는다. 그래서 실 · 마름모 · 열쇠표는 세로 · 가로 둘 다 그린다.
//
//  · 지도자 꼬리표 = 그림판 꼬리표를 줄인 꼴: 머리 24(구멍 · 대수 8.5 · 이름 9 굵게 · 작은 흰 종이) + 흰 층 16(해 8.5) · 칠 정권 색 24% ·
//    테 84% + 먹 · 왼쪽 두 귀 모따기 5([SuccTagPainter]).
//  · 승계 = 앞 꼬리표의 꼬리 마름모 → 다음 꼬리표의 구멍 실(굵기 1.5 · 먹 45). 세로 꼴에서 마름모는 꼬리표 아랫변 왼쪽(구멍과 같은 x ·
//    아랫테에서 6 위 — 구멍이 윗테에서 6 아래인 것과 짝)에 앉는다 — 다듬기 판(가로)에는 없는 자리라 감독 1배 확인 거리.
//  · 이음매 갈래 여섯([SeamLine])은 실의 꼴로 지킨다([SuccThread]): 세습 · 추대 = 이은 실 · 선양 = 겹실 · 찬탈 · 정변 = 끊긴 실 + 빗금 ·
//    관계 · 방식 미상 = 점 실 · 비움 = 옅은 실(먹 25) · 복위 = 이은 실 + 오른쪽 통로의 굽은 실 고리와 매듭([SuccLoop]).
//  · 이음매 글 = 실 옆 열쇠표([SuccKeyLabel] — 키 12 · 흰 종이 · 구멍 · 글 8.5 · 관계 굵게 먹 85 · 방식 먹 60 · 다음 꼬리표 윗변에서 45° 실).
//  · 곧은 실은 네모 칠(화소 맞춤 — 실제 앱(Windows GPU 그리기)에서 꺾인 길의 획이 옅게 나오던 일을 피함 · `sheet_parts.dart` [sheetTagRing]의 까닭),
//    빗금 · 굽은 실 · 45° 실만 선으로 긋는다.
//  먹은 시트 토큰([SheetLook])의 여섯(85 · 60 · 45 · 25 · 12 · 4)만 쓴다. 칸 정통성 무늬(공동 · 섭정 · 명목 · 주장)는 자료가 없어 그리지 않는다.
//  넓은 창(걸음 7 — `succession_wide.dart`)이 더 쓰는 것: 나라 사이 승계의 실 갈래([SuccLine] — 간접 · 부흥 점선 · 부분 가는 실) ·
//  이음매 글([succSeamSpan] — 좁은 창과 같은 글) · 제목 꼬리표의 실 길이 · 매듭([SuccTitleTag.thread] · [SuccTitleTag.knot]) ·
//  범례 견본(합쳐짐 · 다시 · 정통성 넷 — [SuccLegendKind]).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 승계표 치수(1배 px).
abstract final class SuccLook {
  // ---- 지도자 꼬리표 ----

  /// 머리 24(밑선은 바깥 상자 위에서 23.5) · 흰 층 16 → 바깥 화소 상자 키 40(목업 `bandH` = 머리 24 − 1 + 층 16의 가운데 줄 + 1).
  static const head = 24.0, floor = 16.0, tag = head + floor;

  /// 머리 · 층 글의 왼쪽(구멍 뒤 — 목업 `nx = hx + 7`) 14 · 대수 8.5(최소 폭 16 — 줄마다 이름이 한 줄에 서게 · 뒤 3) ·
  /// 이름 9 굵게(꼬리표 폭의 45%까지) · 해 8.5 · 머리 오른쪽 끝 6 안 · 작은 종이 사이 5.
  static const lead = 14.0, ordText = 8.5, ordMin = 16.0, ordGap = 3.0, nameText = 9.0, nameShare = .45, yearText = 8.5, headRight = 6.0, chipGap = 5.0;

  /// 머리의 작은 흰 종이('다시' · 다른 나라 · '후손 n ▸' · 'n대에서'): 키 14 · 모따기 3 · 글 8.5 굵게 · 앞뒤 5.
  static const paper = 14.0, paperText = 8.5, paperPad = 5.0;

  // ---- 실 ----

  /// 실 굵기 1.5 · 매듭 반지름 2 · 선양 겹실은 가운데에서 ±2 · 찬탈 끊김 = 길이의 26%(5 이상) + 빗금(±4 · ±3) · 점 실 = 반지름 1 · 4마다.
  static const thread = 1.5, knot = 2.0, doubleGap = 2.0, breakShare = .26, breakMin = 5.0, slashAcross = 4.0, slashAlong = 3.0, dotRadius = 1.0, dotStep = 4.0;

  /// 점선 실(간접 · 부흥 — 넓은 창): 3 긋고 2 띄움.
  static const dash = 3.0, dashGap = 2.0;

  /// 세로 꼴의 실이 내려가는 x — 지도자 꼬리표의 구멍 · 마름모와 같은 자리(꼬리표 왼쪽에서 7.5).
  static const threadX = .5 + SheetLook.holeLeft;

  // ---- 이음매 줄 · 열쇠표 ----

  /// 이음매 줄 22 — 열쇠표(바깥 상자 13)가 다음 꼬리표 윗변 1 위에 들고 위로 8이 남는 키.
  static const seam = 22.0;

  /// 열쇠표: 꼬리표 왼쪽에서 19(목업 `X0 + 19`) · 바깥 상자 13 · 다음 꼬리표 윗변과 1 띄움 · 45° 실은 그 윗변 16.5(열쇠표 왼쪽 − 3 + .5)에서
  /// 열쇠표 구멍(왼쪽 6.5 · 가운데)까지 — 9 옆 · 8 위.
  static const keyLeft = 19.0, keyBox = SheetLook.keyTag + 1, keyBelow = 1.0, keyFromBack = 2.5;

  // ---- 사람 줄 · 건너뛰기 줄 ----

  /// 줄 28 · 들여쓰기 한 칸 14(8대에서 자름 — `kin_rows.dart`) · 첫 칸 왼쪽 4(▸ · ▾ 14가 실 통로 7.5 밖에 서게).
  static const row = 28.0, indentBase = 4.0, toggle = 14.0;

  /// 흰 사람 띠: 키 20 · 왼쪽 둥근 끝 8 · 테 먹 45 · 구멍(왼쪽 9.5 · 가운데) · 이름 10 굵게 + 곁글 10 먹 60(사이 6) · 글 앞 18 · 뒤 8.
  static const band = 20.0, bandRound = 8.0, bandHole = 9.5, bandLead = 18.0, bandTail = 8.0, personText = 10.0, subGap = 6.0;

  /// 파조 꼬리표(파 이름 · 사람 수): 키 16 · 왼쪽 둥근 끝 · 제 색 칠 24% · 테 84% + 먹 · 구멍 1.5(왼쪽 5.5) · 글 8.5 굵게 · 앞 11 · 뒤 6 · 사람 띠 뒤 6.
  static const branch = 16.0, branchHole = 1.5, branchHoleLeft = 5.5, branchLead = 11.0, branchTail = 6.0, branchGap = 6.0;

  // ---- 오른쪽 통로(복위 고리) ----

  /// 꼬리표 오른쪽의 통로 30 · 고리의 세로 실은 줄 오른쪽 끝에서 12 · 굽음 6 · 가로 실은 머리 가운데(12.5).
  static const lane = 30.0, loopRight = 12.0, loopBend = 6.0, loopY = 12.5;

  // ---- 제목 꼬리표 · 범례 ----

  /// 제목 꼬리표: 키 56 · 모따기 8 · 구멍(왼쪽 10 · 위 8)에서 위로 10 실 + 매듭 · 제목 20 굵게(가운데 20) · 아래 글 12(가운데 42) · 글 앞 18.
  static const title = 56.0, titleChamfer = 8.0, titleHoleX = 10.5, titleHoleY = 8.5, titleThread = 10.0, titleSize = 20.0, titleSub = 12.0, titleLead = 18.0;

  /// 범례 한 칸: 견본 30 × 13 · 견본 뒤 8 · 글 11 먹 60 · 칸 사이 14 · 줄 사이 6.
  static const legendSample = 30.0, legendHeight = 13.0, legendGap = 8.0, legendText = 11.0, legendSpacing = 14.0, legendRun = 6.0;

  /// 올림 — 칠 위에 먹 4%(검색 결과의 꼬리표 줄과 같은 셈).
  static Color lift(Color fill) => Color.alphaBlend(const Color(0x0a000000), fill);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  자리 셈(순수)
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 지도자 꼬리표의 구멍 가운데 — 바깥 화소 상자 [box]의 왼쪽 위에서 (7.5, 6.5)(그림판 꼬리표 · [sheetHoleAt]과 같음).
Offset succHoleAt(Rect box) => sheetHoleAt(box, SheetTagKind.cham);

/// 세로 꼴의 꼬리 마름모 가운데 — 구멍과 같은 x · 아랫테(반 픽셀 안)에서 6 위.
Offset succDiamondBelow(Rect box) => Offset(succHoleAt(box).dx, box.bottom - .5 - SheetLook.holeTop);

/// 가로 꼴의 꼬리 마름모 가운데 — 오른쪽 테에서 7 · 구멍과 같은 높이(그림판 · 다듬기 판 그대로).
Offset succDiamondRight(Rect box) => sheetDiamondAt(box);

/// 승계표의 실 갈래 — 이음매 갈래 여섯([SeamLine] 0 ~ 5) 뒤에 넓은 창(앞뒤 나라와의 승계)이 쓰는 둘을 더한다.
/// 나라 사이 승계(`x_succ`의 type): 직접 = [SeamLine.solid] · 간접 · 부흥 = [dashed](점선 3 2) · 부분 = [thin](가는 실 1px).
abstract final class SuccLine {
  static const dashed = 6, thin = 7;

  /// 나라 사이 승계의 갈래(`direct` · `indirect` · `revival` · `partial`) → 실 갈래. 모르는 갈래는 내보내기의 기본(간접)처럼 점선.
  static int ofNation(String type) => switch (type) {
    'direct' => SeamLine.solid,
    'partial' => thin,
    _ => dashed,
  };
}

/// 열쇠표 바깥 상자(이음매 줄 안 자리 — 줄 키 [height] · 열쇠표 폭 [labelWidth]): 왼쪽 19 · 다음 꼬리표 윗변(줄 밑) 1 위.
Rect succKeyBox(double height, double labelWidth) => Rect.fromLTWH(SuccLook.keyLeft, height - SuccLook.keyBelow - SuccLook.keyBox, labelWidth, SuccLook.keyBox);

/// 열쇠표의 45° 실 — 다음 꼬리표 윗변(이음매 줄 밑 + .5)의 [SuccLook.keyLeft] − 2.5에서 열쇠표 구멍까지(이음매 줄 안 자리).
(Offset, Offset) succKeyThread(double height) {
  final hole = succKeyBox(height, 0).topLeft + SheetKeyLabel.shape.holeAt!;
  return (Offset(SuccLook.keyLeft - SuccLook.keyFromBack, height + .5), hole);
}

final _unknownWords = RegExp('관계 미상|방식 미상|전임자 미상');

/// 이음매 글(열쇠표 한 덩이 — 좁은 창 · 넓은 창이 함께 씀) — 관계는 굵게 먹 85, 방식 · 나머지는 먹 60(열쇠표 글의 바탕),
/// '관계 미상' · '방식 미상' · '전임자 미상'과 다시 오른 지도자의 '— [sameAs]와 같은 사람'은 먹 45. 비움이거나 글이 없으면 null(열쇠표 없음).
/// [a]는 정권 기록 `x_lineage['leader:i']`(이음매 글 `seam` — 없으면 옛 기록의 관계 · 방식을 잇는다).
InlineSpan? succSeamSpan(Map<String, dynamic>? a, {String? sameAs}) {
  final line = SeamLine.of(a);
  if (line == SeamLine.blank || a == null) return null;
  final spans = <InlineSpan>[];
  var text = detailString(a, 'seam');
  if (text.isEmpty) {
    // 옛 기록(이음매 글이 없음) — 실린 관계 · 방식 글만 잇는다(글은 웹이 지은 낱말 그대로).
    bool on(String k) => a[k] == 1 || a[k] == true;
    final kin = detailString(a, 'kin').isNotEmpty ? detailString(a, 'kin') : (on('kinUnknown') ? '관계 미상' : '');
    final how = detailString(a, 'how').isNotEmpty ? detailString(a, 'how') : (on('howUnknown') ? '방식 미상' : '');
    text = [kin, how].where((s) => s.isNotEmpty).join(' · ');
  }
  const faint = TextStyle(color: SheetLook.ink45);
  void plain(String s) {
    var i = 0;
    for (final w in _unknownWords.allMatches(s)) {
      if (w.start > i) spans.add(TextSpan(text: s.substring(i, w.start)));
      spans.add(TextSpan(text: w[0], style: faint));
      i = w.end;
    }
    if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
  }

  final kin = detailString(a, 'kin');
  final at = kin.isEmpty ? -1 : text.indexOf(kin);
  if (at >= 0) {
    plain(text.substring(0, at));
    spans.add(TextSpan(text: kin, style: const TextStyle(fontWeight: FontWeight.w700, color: SheetLook.ink85)));
    plain(text.substring(at + kin.length));
  } else {
    plain(text);
  }
  // 다시 오른 지도자 — 이음매 글이 이미 '같은 사람'을 말하면 겹쳐 쓰지 않는다(웹 seamHTML과 같다).
  if (sameAs != null && !text.contains('같은 사람')) spans.add(TextSpan(text: ' — $sameAs와 같은 사람', style: faint));
  return spans.isEmpty ? null : TextSpan(children: spans);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  실 — 이음매 갈래 여섯의 꼴
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 실 한 토막의 꼴(값 — 검사가 바로 읽는다). 곧은 토막은 [bars](네모 칠), 찬탈 빗금은 [slashes](굵기 1.5 선), 점 실은 [dots].
@immutable
class SuccThread {
  const SuccThread({this.bars = const [], this.slashes = const [], this.dots = const [], required this.color});

  final List<Rect> bars;
  final List<(Offset, Offset)> slashes;
  final List<Offset> dots;
  final Color color;

  /// 이음매 갈래 [line]([SeamLine])의 실 — 세로면 x = [at] 가운데로 y [a] ~ [b], 가로면 y = [at] 가운데로 x [a] ~ [b].
  factory SuccThread.of(int line, {required double at, required double a, required double b, bool vertical = true}) {
    Rect bar(double s, double e, [double shift = 0]) {
      const h = SuccLook.thread / 2;
      final c = at + shift;
      return vertical ? Rect.fromLTRB(c - h, s, c + h, e) : Rect.fromLTRB(s, c - h, e, c + h);
    }

    Offset p(double along, double across) => vertical ? Offset(across, along) : Offset(along, across);
    switch (line) {
      case SeamLine.blank:
        return SuccThread(bars: [bar(a, b)], color: SheetLook.ink25);
      case SeamLine.usurp:
        final len = b - a, g = math.max(SuccLook.breakMin, (len * SuccLook.breakShare).roundToDouble()), m = a + len / 2;
        // 빗금: 아래 왼쪽 → 위 오른쪽(가로면 왼쪽 아래 → 오른쪽 위) — 앞 판(paintSeamLine)과 같은 쪽.
        final slash = vertical
            ? (Offset(at - SuccLook.slashAcross, m + SuccLook.slashAlong), Offset(at + SuccLook.slashAcross, m - SuccLook.slashAlong))
            : (Offset(m - SuccLook.slashAlong, at + SuccLook.slashAcross), Offset(m + SuccLook.slashAlong, at - SuccLook.slashAcross));
        return SuccThread(bars: [bar(a, m - g / 2), bar(m + g / 2, b)], slashes: [slash], color: SheetLook.ink45);
      case SeamLine.unknown:
        return SuccThread(dots: [for (var t = a + 1.5; t <= b - 1 + .01; t += SuccLook.dotStep) p(t, at)], color: SheetLook.ink45);
      case SeamLine.abdicate:
        return SuccThread(bars: [bar(a, b, -SuccLook.doubleGap), bar(a, b, SuccLook.doubleGap)], color: SheetLook.ink45);
      case SuccLine.dashed:
        // 간접 · 부흥(넓은 창의 나라 사이 승계) — 3 긋고 2 띄움(다듬기 판 `TH(ind)`의 '3 2').
        return SuccThread(bars: [for (var t = a; t < b - .01; t += SuccLook.dash + SuccLook.dashGap) bar(t, math.min(b, t + SuccLook.dash))], color: SheetLook.ink45);
      case SuccLine.thin:
        // 부분 승계 — 가는 실 하나(1px · 그림판 부분 승계선과 같은 결).
        final c = at;
        return SuccThread(bars: [vertical ? Rect.fromLTRB(c - .5, a, c + .5, b) : Rect.fromLTRB(a, c - .5, b, c + .5)], color: SheetLook.ink45);
      default:
        // 세습 · 추대(5)와 복위(4 — 고리는 오른쪽 통로에 따로)는 이은 실.
        return SuccThread(bars: [bar(a, b)], color: SheetLook.ink45);
    }
  }

  void paint(Canvas canvas) {
    final fill = Paint()..color = color;
    for (final r in bars) {
      if (r.height > 0 && r.width > 0) canvas.drawRect(r, fill);
    }
    if (slashes.isNotEmpty) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SuccLook.thread
        ..color = color;
      for (final (a, b) in slashes) {
        canvas.drawLine(a, b, line);
      }
    }
    for (final d in dots) {
      canvas.drawCircle(d, SuccLook.dotRadius, fill);
    }
  }
}

/// 복위 고리의 한 토막 — 처음 오른 카드(시작) · 그 사이 줄(가운데) · 다시 오른 카드(끝).
enum SuccLoop { start, mid, end }

/// 복위 고리 토막을 그린다 — 줄 폭 [size]의 오른쪽 통로([SuccLook.lane])에서. 꼬리표 오른쪽 끝([tagRight] — 줄 폭 − 통로)에서 머리 가운데로
/// 나와 오른쪽 12의 세로 실로 굽어 내려가고, 다시 오른 카드에서 굽어 들어와 그 꼬리표 오른쪽 테에 매듭(반지름 2)으로 묶인다.
/// 곧은 토막은 네모 칠, 굽음만 선(굵기 1.5).
void paintSuccLoop(Canvas canvas, Size size, SuccLoop part) {
  final x = (size.width - SuccLook.loopRight).floorToDouble() + .5, y = SuccLook.loopY, r = SuccLook.loopBend, tagRight = size.width - SuccLook.lane;
  const h = SuccLook.thread / 2;
  final fill = Paint()..color = SheetLook.ink45;
  final bend = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = SuccLook.thread
    ..color = SheetLook.ink45;
  switch (part) {
    case SuccLoop.start:
      canvas.drawRect(Rect.fromLTRB(tagRight, y - h, x - r, y + h), fill);
      canvas.drawPath(
        Path()
          ..moveTo(x - r, y)
          ..quadraticBezierTo(x, y, x, y + r),
        bend,
      );
      canvas.drawRect(Rect.fromLTRB(x - h, y + r, x + h, size.height), fill);
    case SuccLoop.mid:
      canvas.drawRect(Rect.fromLTRB(x - h, 0, x + h, size.height), fill);
    case SuccLoop.end:
      canvas.drawRect(Rect.fromLTRB(x - h, 0, x + h, y - r), fill);
      canvas.drawPath(
        Path()
          ..moveTo(x, y - r)
          ..quadraticBezierTo(x, y, x - r, y),
        bend,
      );
      canvas.drawRect(Rect.fromLTRB(tagRight, y - h, x - r, y + h), fill);
      canvas.drawCircle(Offset(tagRight + 1.5, y), SuccLook.knot, fill);
  }
}

/// 마름모(반 대각선 3 · 제 색 60% + 먹).
void paintSuccDiamond(Canvas canvas, Offset c, Color color) => canvas.drawPath(sheetDiamondPath(c), Paint()..color = SheetLook.diamondInk(color));

/// 구멍(반지름 [r] · 종이 칠 · 테 먹 45 1px).
void paintSuccHole(Canvas canvas, Offset c, {double r = SheetLook.holeRadius}) {
  canvas.drawCircle(c, r, Paint()..color = SheetLook.paper);
  canvas.drawCircle(c, r, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = SheetLook.ink45);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  그리개 — 지도자 꼬리표 · 줄의 실
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 지도자 꼬리표(그림판 꼬리표를 줄인 꼴): 칠 제 색 24% · 머리 24 밑 흰 층 16(왼쪽 아래 귀는 모따기를 따름) · 머리 밑선과 테 = 제 색 84% + 먹 ·
/// 구멍 · 세로 꼴의 실 토막 — [threadIn](윗변 → 구멍 위 끝 · 이 카드 이음매의 갈래)과 [threadOut](마름모 → 아랫변 · 다음 이음매의 갈래 —
/// 있으면 마름모도). 비움(0)이면 옅은 실(먹 25). [hover]면 머리 칠에 먹 4% · 층은 먹 4.
class SuccTagPainter extends CustomPainter {
  const SuccTagPainter({required this.color, this.hover = false, this.threadIn, this.threadOut});

  final Color color;
  final bool hover;
  final int? threadIn, threadOut;

  /// 실 토막(이 꼬리표 안 자리) — 들어오는 실은 윗변(0)에서 구멍 위 끝까지, 나가는 실은 마름모 가운데에서 아랫변까지.
  List<SuccThread> stubs(Size size) {
    final box = Offset.zero & size, hole = succHoleAt(box), out = succDiamondBelow(box);
    Color ink(int line) => line == SeamLine.blank ? SheetLook.ink25 : SheetLook.ink45;
    const h = SuccLook.thread / 2;
    return [
      if (threadIn case final line?) SuccThread(bars: [Rect.fromLTRB(hole.dx - h, 0, hole.dx + h, hole.dy - SheetLook.holeRadius)], color: ink(line)),
      if (threadOut case final line?) SuccThread(bars: [Rect.fromLTRB(out.dx - h, out.dy, out.dx + h, size.height)], color: ink(line)),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final fill = SheetLook.tagFill(color), edge = SheetLook.tagEdge(color);
    canvas.drawPath(sheetTagPath(box, SheetTagKind.cham), Paint()..color = hover ? SuccLook.lift(fill) : fill);
    // 흰 층 — 머리 밑선(반 픽셀)부터 아래 끝까지 · 왼쪽 아래 귀는 꼬리표와 같은 모따기.
    final x0 = .5, x1 = size.width - .5, ys = SuccLook.head - .5, yb = size.height - .5, ch = SheetLook.tagChamfer;
    canvas.drawPath(
      Path()
        ..moveTo(x1, ys)
        ..lineTo(x0, ys)
        ..lineTo(x0, yb - ch)
        ..lineTo(x0 + ch, yb)
        ..lineTo(x1, yb)
        ..close(),
      Paint()..color = hover ? SheetLook.ink4 : SheetLook.paper,
    );
    canvas.drawLine(Offset(x0 + .5, ys), Offset(x1, ys), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = edge);
    // 테는 획이 아니라 고리 칠([sheetTagRing]의 까닭).
    canvas.drawPath(sheetTagRing(box, SheetTagKind.cham), Paint()..color = edge);
    for (final s in stubs(size)) {
      s.paint(canvas);
    }
    paintSuccHole(canvas, succHoleAt(box));
    if (threadOut != null) paintSuccDiamond(canvas, succDiamondBelow(box), color);
  }

  @override
  bool shouldRepaint(SuccTagPainter old) => old.color != color || old.hover != hover || old.threadIn != threadIn || old.threadOut != threadOut;
}

/// 꼬리표가 아닌 줄(이음매 · 사람 · 건너뛰기)의 실과, 모든 줄의 오른쪽 통로 복위 고리 토막.
/// [line]이 있으면 x = [SuccLook.threadX]에 그 갈래의 실을 줄 키 전체로(이음매 줄은 갈래 그대로, 펼친 줄을 지나는 실은 이은 실 · 비움).
/// [keyThread]면 다음 꼬리표 윗변에서 열쇠표 구멍까지 45° 실(먹 45 · 1px — 열쇠표 밑에 깔림).
class SuccRowPainter extends CustomPainter {
  const SuccRowPainter({this.line, this.keyThread = false, this.loops = const []});

  final int? line;
  final bool keyThread;
  final List<SuccLoop> loops;

  /// 이 줄의 실(줄 키 [size]) — 없으면 null.
  SuccThread? threadOf(Size size) => line == null ? null : SuccThread.of(line!, at: SuccLook.threadX, a: 0, b: size.height);

  @override
  void paint(Canvas canvas, Size size) {
    threadOf(size)?.paint(canvas);
    if (keyThread) {
      final (a, b) = succKeyThread(size.height);
      canvas.drawLine(a, b, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = SheetLook.ink45);
    }
    for (final part in loops) {
      paintSuccLoop(canvas, size, part);
    }
  }

  @override
  bool shouldRepaint(SuccRowPainter old) => old.line != line || old.keyThread != keyThread || !listEquals(old.loops, loops);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  부품 — 누름 · 작은 종이 · 열쇠표 · 제목 꼬리표 · 범례
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 승계표 줄의 누름 — 올림 상태를 [builder]에 주고, 누름은 [MotionPress] 하나 · 읽기 글은 [semantics](단추).
/// [onMenu]면 오른쪽 클릭 · 길게 누름에 그 자리(전역)를 준다(차림표). [onTap]이 없으면 올림 · 누름 없이 그대로.
class SuccPress extends StatefulWidget {
  const SuccPress({super.key, required this.builder, this.onTap, this.semantics, this.onMenu});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;
  final String? semantics;
  final void Function(Offset global)? onMenu;

  @override
  State<SuccPress> createState() => _SuccPressState();
}

class _SuccPressState extends State<SuccPress> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    Widget body = widget.builder(on && _hover);
    if (on) {
      body = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          label: widget.semantics,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: MotionPress(child: body)),
        ),
      );
    }
    final menu = widget.onMenu;
    if (menu == null) return body;
    return GestureDetector(
      onSecondaryTapDown: (d) => menu(d.globalPosition),
      onLongPressStart: (d) => menu(d.globalPosition),
      child: body,
    );
  }
}

/// 한 줄 글(줄 높이 1 · 넘치면 자름).
Widget succLine(String text, TextStyle style, {TextOverflow overflow = TextOverflow.clip}) => Text(text, maxLines: 1, softWrap: false, overflow: overflow, style: style);

/// 머리의 작은 흰 종이('다시' · 다른 나라 · '후손 n ▸' · 'n대에서'): 키 14 · 모따기 3 · 흰 종이 · 테 먹 45 · 글 8.5 굵게(누르면 먹 85 · 아니면 먹 60) ·
/// 올리면 칠 먹 4. [onTap]이 있으면 누르는 단추(읽기 글 = 글).
class SuccPaper extends StatelessWidget {
  const SuccPaper(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SuccPress(
    onTap: onTap,
    semantics: label,
    builder: (hover) => SheetTag(
      shape: SheetPaperButton.shapeOf(hover: hover),
      height: SuccLook.paper,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SuccLook.paperPad),
        child: Center(widthFactor: 1, child: succLine(label, sheetText(SuccLook.paperText, bold: true, color: onTap == null ? SheetLook.ink60 : SheetLook.ink85))),
      ),
    ),
  );
}

/// 파조 꼬리표(파 이름 · 사람 수 — 누르면 그 아래를 모두 펴거나 접음): 키 16 · 왼쪽 둥근 끝 · 제 색 칠 24% · 테 84% + 먹 · 구멍 1.5 · 글 8.5 굵게 탭 글.
class SuccBranchTag extends StatelessWidget {
  const SuccBranchTag({super.key, required this.label, required this.color, this.onTap});
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SuccPress(
    onTap: onTap,
    semantics: label,
    builder: (hover) => SheetTag(
      shape: SheetShape(
        kind: SheetTagKind.key,
        round: SuccLook.branch / 2,
        fill: hover ? SuccLook.lift(SheetLook.tagFill(color)) : SheetLook.tagFill(color),
        stroke: SheetLook.tagEdge(color),
        hole: true,
        holeRadius: SuccLook.branchHole,
        holeAt: const Offset(SuccLook.branchHoleLeft + .5, SuccLook.branch / 2),
      ),
      height: SuccLook.branch,
      child: Padding(
        padding: const EdgeInsets.only(left: SuccLook.branchLead, right: SuccLook.branchTail),
        child: Center(widthFactor: 1, child: succLine(label, sheetText(SuccLook.paperText, bold: true, color: SheetLook.tagInk(color)))),
      ),
    ),
  );
}

/// 열쇠표(이음매 글): 키 12(바깥 상자 13) · 왼쪽 둥근 끝 6 · 흰 종이 · 테 먹 45 · 구멍 1.5 · 글 8.5([text]의 조각 빛깔 그대로 — 관계 굵게 먹 85 ·
/// 방식 먹 60 · 미상 먹 45). 글은 한 덩이 글이라 읽기 도구 · 검사가 이음매 글 한 줄로 읽는다. 폭이 모자라면 줄임표.
class SuccKeyLabel extends StatelessWidget {
  const SuccKeyLabel(this.text, {super.key});
  final InlineSpan text;

  @override
  Widget build(BuildContext context) => SheetTag(
    shape: SheetKeyLabel.shape,
    height: SuccLook.keyBox,
    child: Padding(
      padding: const EdgeInsets.only(left: SheetLook.keyLead, right: SheetLook.keyTail + 1),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: Text.rich(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: sheetText(SheetLook.keyText, color: SheetLook.ink60)),
      ),
    ),
  );
}

/// 제목 꼬리표(정권 색 · 모따기 8 · 키 56): 구멍(왼쪽 10 · 위 8)에서 위로 10 실 + 매듭 · 제목 20 굵게 탭 글(제 색 22% + 먹) ·
/// 아래 글 12(제 색 45% + 먹 — '지도자 n'). 폭은 받은 폭 전체.
/// [thread]는 꼬리표 윗변에서 위로 매단 실의 길이(넓은 창 서랍은 폴더 몸통 윗변까지), [knot]이 거짓이면 실 끝의 매듭이 없다
/// (다듬기 판 넓은 창 `headTag` — 실이 폴더 테에 닿음).
class SuccTitleTag extends StatelessWidget {
  const SuccTitleTag({super.key, required this.color, required this.title, required this.sub, this.thread = SuccLook.titleThread, this.knot = true});
  final Color color;
  final String title, sub;
  final double thread;
  final bool knot;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TitlePainter(color, thread, knot),
    child: SizedBox(
      height: SuccLook.title,
      child: Padding(
        padding: const EdgeInsets.only(left: SuccLook.titleLead, right: 10),
        child: Stack(children: [
          Positioned(left: 0, right: 0, top: 20 - SuccLook.titleSize / 2, height: SuccLook.titleSize, child: succLine(title, sheetText(SuccLook.titleSize, bold: true, color: SheetLook.tagInk(color)), overflow: TextOverflow.ellipsis)),
          Positioned(left: 0, right: 0, top: 42 - SuccLook.titleSub / 2, height: SuccLook.titleSub, child: succLine(sub, sheetText(SuccLook.titleSub, color: SheetLook.nameInk(color)), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ),
  );
}

class _TitlePainter extends CustomPainter {
  const _TitlePainter(this.color, this.thread, this.knot);
  final Color color;
  final double thread;
  final bool knot;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & Size(size.width.floorToDouble(), size.height);
    canvas.drawPath(sheetTagPath(box, SheetTagKind.cham, chamfer: SuccLook.titleChamfer), Paint()..color = SheetLook.tagFill(color));
    canvas.drawPath(sheetTagRing(box, SheetTagKind.cham, chamfer: SuccLook.titleChamfer), Paint()..color = SheetLook.tagEdge(color));
    const hole = Offset(SuccLook.titleHoleX, SuccLook.titleHoleY);
    final top = -thread;
    canvas.drawRect(Rect.fromLTRB(hole.dx - .5, top, hole.dx + .5, hole.dy - SheetLook.holeRadius), Paint()..color = SheetLook.threadInk);
    if (knot) canvas.drawCircle(Offset(hole.dx, top), SheetLook.knotRadius, Paint()..color = SheetLook.threadInk);
    paintSuccHole(canvas, hole);
  }

  @override
  bool shouldRepaint(_TitlePainter old) => old.color != color || old.thread != thread || old.knot != knot;
}

/// 범례 견본 갈래 — 실 갈래 다섯(이음매 [SeamLine] 번호) · 복위 고리 · 열쇠표.
abstract final class SuccLegendKind {
  static const restore = 'restore', key = 'key';
  static String seam(int line) => 'seam:$line';

  /// 넓은 창이 더 쓰는 견본: 합쳐짐(마름모 둘 → 매듭 → 구멍) · 다시(열쇠표 '다시' — 복위) · 정통성 넷(흰 층 조각 — 그림판 범례의 정통성 상자와 같은 문법).
  static const merge = 'merge', again = 'again';
  static const joint = 'legit:joint', regent = 'legit:regent', nominal = 'legit:nominal', claim = 'legit:claim';
  static const legit = [joint, regent, nominal, claim];
}

/// 승계표 전용 범례 — 견본(30 × 13) + 글 11 먹 60을 칸 사이 14로 흘린다. 세계표가 함께 쓰는 `KinLegend`(kin_head.dart)와 따로다.
class SuccLegend extends StatelessWidget {
  const SuccLegend(this.items, {super.key, required this.color});

  /// (견본 갈래 — [SuccLegendKind], 글).
  final List<(String, String)> items;
  final Color color;

  @override
  Widget build(BuildContext context) => SheetRun(
    spacing: SuccLook.legendSpacing,
    runSpacing: SuccLook.legendRun,
    children: [
      for (final (kind, text) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          SuccLegendSample(kind, color: color),
          const SizedBox(width: SuccLook.legendGap),
          succLine(text, sheetText(SuccLook.legendText, color: SheetLook.ink60)),
        ]),
    ],
  );
}

/// 범례 견본 하나(30 × 13): 실 갈래 = 마름모(왼쪽 4.5) → 그 갈래의 실(가로) → 구멍(오른쪽 26.5) · 복위 = '⊃' 굽은 실 + 매듭 ·
/// 열쇠표 = 흰 종이 열쇠표(구멍 1.5).
/// 넓은 창이 더 쓰는 견본: 합쳐짐(30 × 16 — 마름모 둘의 실이 매듭에서 모여 구멍으로) · 다시(열쇠표 '다시' — 제 폭) ·
/// 정통성 넷(다듬기 판 sh-succ-wide `legendOne` — 제 색 테의 흰 층 조각 30 × 16 · 12: 공동 = 반 칸 둘 · 섭정 = 아랫변 안 2px 먹 60 ·
/// 명목 = 이름 먹 45 · 주장 = 1px 화소 빗금 먹 25 — 그림판 범례의 정통성 상자(`legend_marks.dart`)와 같은 문법을 작게).
class SuccLegendSample extends StatelessWidget {
  const SuccLegendSample(this.kind, {super.key, required this.color});
  final String kind;
  final Color color;

  /// 견본의 키(폭은 [SuccLook.legendSample] — '다시'만 제 폭).
  static double heightOf(String kind) => kind == SuccLegendKind.merge || kind == SuccLegendKind.joint ? 16 : (kind.startsWith('legit:') ? 12 : SuccLook.legendHeight);

  @override
  Widget build(BuildContext context) {
    if (kind == SuccLegendKind.key) {
      return const SizedBox(
        width: SuccLook.legendSample,
        height: SuccLook.legendHeight,
        child: CustomPaint(painter: _ShapeSample(SheetKeyLabel.shape)),
      );
    }
    if (kind == SuccLegendKind.again) {
      return const SuccKeyLabel(TextSpan(text: '다시', style: TextStyle(fontWeight: FontWeight.w700, color: SheetLook.ink85)));
    }
    final size = Size(SuccLook.legendSample, heightOf(kind));
    if (kind.startsWith('legit:')) {
      final paint = CustomPaint(size: size, painter: _LegitPainter(kind, color));
      if (kind != SuccLegendKind.nominal) return paint;
      // 명목 — 이름만 옅은 먹(글은 그림판 범례의 정통성 견본과 같은 이름).
      return SizedBox.fromSize(
        size: size,
        child: Stack(children: [
          paint,
          Positioned(left: 4, top: 0, bottom: 0, child: Center(widthFactor: 1, child: succLine('온하', sheetText(SuccLook.yearText, color: SheetLook.ink45)))),
        ]),
      );
    }
    return CustomPaint(size: size, painter: _LegendPainter(kind, color));
  }
}

/// 정통성 견본 — 흰 층 조각(바깥 30 × 키 · 테 제 색 84% + 먹 · 화소 칠).
class _LegitPainter extends CustomPainter {
  const _LegitPainter(this.kind, this.color);
  final String kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void rect(double l, double t, double r, double b, Color c) => canvas.drawRect(Rect.fromLTRB(l, t, r, b), Paint()..color = c);
    rect(0, 0, w, h, SheetLook.paper);
    if (kind == SuccLegendKind.claim) {
      // 5px 칸의 1px 화소 계단 빗금(45° · 먹 25 — 그림판 범례의 주장 견본과 같은 무늬).
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(1, 1, w - 1, h - 1));
      for (var y = 0.0; y < h; y += 5) {
        for (var x = 0.0; x < w; x += 5) {
          for (var i = 0; i < 5; i++) {
            rect(x + i, y + 4 - i, x + i + 1, y + 5 - i, SheetLook.ink25);
          }
        }
      }
      canvas.restore();
    } else if (kind == SuccLegendKind.joint) {
      // 반 칸 둘 — 13부터 오른쪽은 위아래 두 단(단 금 · 칸 금 먹 25).
      rect(13, 8, w - 1, 9, SheetLook.ink25);
      rect(13, 8, 14, h - 1, SheetLook.ink25);
    } else if (kind == SuccLegendKind.regent) {
      // 섭정 — 그 기간 아랫변 안쪽 2px 먹 60.
      rect(2, h - 3, 19, h - 1, SheetLook.ink60);
    }
    final edge = SheetLook.tagEdge(color);
    rect(0, 0, w, 1, edge);
    rect(0, h - 1, w, h, edge);
    rect(0, 1, 1, h - 1, edge);
    rect(w - 1, 1, w, h - 1, edge);
  }

  @override
  bool shouldRepaint(_LegitPainter old) => old.kind != kind || old.color != color;
}

class _ShapeSample extends CustomPainter {
  const _ShapeSample(this.shape);
  final SheetShape shape;
  @override
  void paint(Canvas canvas, Size size) => shape.paint(canvas, size);
  @override
  bool shouldRepaint(_ShapeSample old) => old.shape != shape;
}

class _LegendPainter extends CustomPainter {
  const _LegendPainter(this.kind, this.color);
  final String kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 6.5, x0 = 4.5, x1 = 26.5;
    if (kind == SuccLegendKind.restore) {
      // '⊃' — 위 실이 오른쪽으로 나가 굽어 내려와 아래 실로 돌아와 매듭(다시 오른 카드).
      const top = 2.5, bottom = 10.5, x = 24.5, r = 4.0, h = SuccLook.thread / 2;
      final fill = Paint()..color = SheetLook.ink45;
      final bend = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SuccLook.thread
        ..color = SheetLook.ink45;
      canvas.drawRect(const Rect.fromLTRB(2, top - h, x - r, top + h), fill);
      canvas.drawRect(const Rect.fromLTRB(x0, bottom - h, x - r, bottom + h), fill);
      canvas.drawPath(
        Path()
          ..moveTo(x - r, top)
          ..quadraticBezierTo(x, top, x, top + r)
          ..lineTo(x, bottom - r)
          ..quadraticBezierTo(x, bottom, x - r, bottom),
        bend,
      );
      canvas.drawCircle(const Offset(x0, bottom), SuccLook.knot, fill);
      return;
    }
    if (kind == SuccLegendKind.merge) {
      // 합쳐짐 — 마름모 둘(위 4 · 아래 12)의 실이 14.5의 매듭에서 모여 구멍(26.5, 8)으로.
      const top = 4.0, bottom = 12.0, mid = 8.0, xm = 14.5, h = SuccLook.thread / 2;
      final fill = Paint()..color = SheetLook.ink45;
      canvas.drawRect(const Rect.fromLTRB(x0, top - h, xm + h, top + h), fill);
      canvas.drawRect(const Rect.fromLTRB(x0, bottom - h, xm + h, bottom + h), fill);
      canvas.drawRect(const Rect.fromLTRB(xm - h, top, xm + h, bottom), fill);
      canvas.drawRect(const Rect.fromLTRB(xm, mid - h, x1 - SheetLook.holeRadius, mid + h), fill);
      paintSuccDiamond(canvas, const Offset(x0, top), color);
      paintSuccDiamond(canvas, const Offset(x0, bottom), color);
      canvas.drawCircle(const Offset(xm, mid), SuccLook.knot, fill);
      paintSuccHole(canvas, const Offset(x1, mid));
      return;
    }
    final line = kind.startsWith('seam:') ? int.tryParse(kind.substring(5)) ?? SeamLine.solid : SeamLine.solid;
    SuccThread.of(line, at: y, a: x0, b: x1 - SheetLook.holeRadius, vertical: false).paint(canvas);
    paintSuccDiamond(canvas, const Offset(x0, y), color);
    paintSuccHole(canvas, const Offset(x1, y));
  }

  @override
  bool shouldRepaint(_LegendPainter old) => old.kind != kind || old.color != color;
}
