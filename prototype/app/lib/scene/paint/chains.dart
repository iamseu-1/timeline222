import 'dart:ui' as ui;

import '../text_paragraph.dart';
import 'ink.dart';

// 꼬리표 밑 흰 사슬의 꼴 — 4단계 감독 고름 G5 #9 '나'(2026-10-25 · 차례 걸음 15 · 고르기 판 `.claude/research/stage4-choose/themes/g-g5-9b.js`의
// chain() · below() · subLabels() · 기준 그림 `out/shots/g9b-na.png`).
//
// 왕조 · 지위(와 렌즈가 지위 자리로 내린 지도자 칸)는 꼬리표 안 칸 층이 아니라 띠 아랫변 밑 사슬 단(쌓기 — 차례 걸음 14 `layout.dart _bandOf`)에
// 선다. 사슬 하나 = 흰 종이(둥근 3 · 테 먹 45) 위에 칸을 꿴 것(칸 사이 세로 금 먹 25 · 글 8.5 굵게 먹 85 — 드는 만큼 줄임):
//   · 왕조 — 칸 앞에 가문 색 막대(3 × 8 · 둥근 1 · 그 칸 색의 띠 테 빛깔)
//   · 지위 — 이름 뒤 서열 눈금(폭 2 · 간격 4 · 먹 45 · 서열 수만큼)
//   · 구멍과 실 — 사슬이 꼬리표 시작에서 비롯하면 첫 칸에 구멍(반지름 1.5 · 테 먹 45 · 띠 왼쪽 + 7). 꼬리표 아랫변의 점(반지름 1.5)에서 내려오는
//     실 하나(x = 띠 왼쪽 + 7 · 먹 45)가 마지막 사슬의 구멍까지 꿰인다 — 실은 종이 뒤라 사슬 사이 틈에서만 보인다.
//   · 왼쪽 칸 — 사슬마다 칸 오른쪽 끝 − 12에 '왕조' · '지위'(10 · 틀 먹) + 6px 금(paint/gutter.dart).
// 그리기는 칸 층(paint/strips.dart `_paintChain`)이 한다 — 잘린 쪽 · 미정 끝 · 고름 · 흐림 · 조명 · 실권 옅기 · 누름(그 칸 창) · 커서 비춤은 칸 층과 같은 길.
// 스위치 `chain`(`--paint-off=chain` — 찍기 · 증명 전용)을 끄면 쌓기가 예전 칸 층이라 이 꼴도 쓰이지 않는다.

/// 흰 사슬의 값(고르기 판 g-g5-9b.js의 chain() — 먹은 옛 짙기로 두고 그림판 먹 단계 [CanvasInk]로 낸다).
abstract final class ChainLook {
  /// 종이의 둥근 귀.
  static const radius = 3.0;

  /// 테 · 실 · 꼬리표 아랫변의 점 · 구멍 테 · 지위 서열 눈금의 먹(45).
  static const edge = .45;

  /// 칸 사이 세로 금의 먹(목업 22 → 그림판 먹 단계 25) — 위아래 테 안 1px 들임.
  static const divider = .22;

  /// 칸 글의 먹(목업 80 → 단계 85) · 크기 8.5 굵게.
  static const text = .80, textSize = 8.5;

  /// 글의 왼쪽 = 칸 왼쪽(화면 왼쪽에 잘렸으면 화면 왼쪽) + 5 · 오른쪽 여유 4.
  static const textPad = 5.0, roomPad = 4.0;

  /// 구멍 — 띠 왼쪽(사슬 종이의 왼쪽 테) + 7의 가운데 · 반지름 1.5(테 1px) · 세로는 사슬 가운데. 구멍 있는 칸의 글은 띠 왼쪽 + 13.
  static const holeX = 7.0, holeR = 1.5, holeText = 13.0;

  /// 꼬리표 아랫변의 점(실이 나오는 자리) — 반지름 1.5 · 가운데는 꼬리표 아랫변 + 1.5(꼬리표와 첫 사슬 사이 틈 3을 메움).
  static const dotR = 1.5;

  /// 왕조의 가문 색 막대 — 글 자리에서 3 × 8(둥근 1) · 사슬 위 + 3 · 그 뒤 7에 이름.
  static const barW = 3.0, barH = 8.0, barTop = 3.0, barAdvance = 7.0;

  /// 둥근 1의 3 × 8 막대에서 네 귀 한 칸씩이 덮는 몫(사분원 넓이 π/4).
  static const barCorner = .785;

  /// 지위의 서열 눈금 — 이름 끝 + 5에서 폭 2 · 4마다 · 사슬 위 + 4에서 높이 6. 사슬 오른쪽 − 3 안에 다 들 때만.
  static const tickGap = 5.0, tickW = 2.0, tickPitch = 4.0, tickTop = 4.0, tickH = 6.0;

  /// 꼬리표 시작에서 비롯하는 사슬로 치는 어긋남 — 반년(고르기 판 `Math.abs(first.a - o.a) < .5`).
  static const startSlackMinutes = 365.2425 * 24 * 60 / 2;

  /// 왼쪽 칸의 사슬 이름(목업 subLabels): 칸 오른쪽 끝 − 12에 오른쪽 맞춤 · 10 · 틀 먹 50 · 그 뒤 칸 오른쪽 끝 − 8 ~ − 2의 금(틀 먹 20).
  static const labelRight = 12.0, labelSize = 10.0, labelInk = .5, lineFrom = 8.0, lineTo = 2.0, lineInk = .2;

  /// 사슬 칸의 글꼴(스위치 `ink`를 끄면 옛 먹 80 — 그래서 const가 아니다).
  static final textLook = TextLook(textSize, ui.FontWeight.w700, CanvasInk.gray(text));

  /// 사슬 차례(0 왕조 · 1 지위 자리)의 왼쪽 칸 이름 — 렌즈가 지위 자리로 내린 지도자 칸이면 '지도자'.
  static String labelOf(int slot, {bool leaders = false}) => slot == 0 ? '왕조' : (leaders ? '지도자' : '지위');

  /// 이름을 들 폭 [room]에 맞춘다(고르기 판 fit — 온 이름 → 첫 글자 → 없음, 왕조는 그 사이에 끝의 '왕조 · 왕가 · …'를 뗀 짧은 이름).
  /// [widthOf]가 null(글자 폭이 아직)이면 null — 다음 장면에 다시. 들 것이 없으면 빈 글.
  static (String, double)? fit(String name, double room, double? Function(String) widthOf, {String short = ''}) {
    if (name.isEmpty || room <= 0) return ('', 0);
    for (final s in [name, if (short.isNotEmpty) short, name.substring(0, 1)]) {
      final w = widthOf(s);
      if (w == null) return null;
      if (w <= room) return (s, w);
    }
    return ('', 0);
  }

  /// 지위 서열 눈금 수 — 서열 단계([CellStyle.rankOf]의 값 · 0 이하면 없음)를 4까지.
  static int ticksOf(int level) => level <= 0 ? 0 : (level > 4 ? 4 : level);
}

/// 이번 장면에 그린 사슬 하나의 왼쪽 칸 이름 자리(줄 · 사슬 차례마다 화면 왼쪽에 가장 가까운 사슬 — 사슬 가운데 y).
/// 칸 층이 그리며 적고 왼쪽 칸(paint/gutter.dart)이 같은 장면에 읽는다(왼쪽 칸은 몸통 뒤에 그린다 — painter.dart).
class ChainMark {
  ChainMark(this.row, this.slot, this.label, this.x, this.y);
  final int row, slot;
  String label;
  double x, y;

  @override
  String toString() => '$row:$slot $label ${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
}
