import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../layout.dart';
import '../marks.dart';
import '../schema4_items.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import 'bands.dart' show BandKind, BandLayer, BandLook, EdgeStroke, LegitLook, PowerSpan, TagEnd, TagLook;
import 'chains.dart';
import 'context.dart'; // 묶음 연장(Quads · DashedQuads · TextQueue)은 context.dart가 batch.dart를 다시 내보낸다
import 'floor_rules.dart';
import 'ink.dart';
import 'look.dart';
import 'paint_pick.dart';
import 'patterns.dart';

// 띠 안의 단(칸): 왕조 · 지도자 · 내각 · 기관 · 시기 구분 · 지위 · 예속(안).
// 값의 뜻은 docs/계약-아카이브-3단계.md 6-2절, 숫자와 색은 docs/명세-3단계/01-띠의-표현.md 3절(단마다의 규칙)과 6절(실측 표)에서 그대로 옮겼다.
// 밝기(고르기 · 흐림 · 기간 조명 · 가문)는 docs/명세-3단계/06-상세-검색-필터-도구.md 3절.
//
// 그리기는 모두 묶음으로 간다 — 칸 하나에 drawRRect/drawPath를 부르지 않는다:
//   바탕 · 테두리 · 구분선 · 옅은 끝 · 유령 구분선 → c.quads(네모 묶음)  ·  무늬 → c.patterns  ·  둥근 끝 → 제 그림판 [_CellSprites]  ·  이름 → c.later.
// 한 화면에 칸이 수백 개여도 그리기 호출은 (네모 1 + 무늬 종류 수 + 조각 1 + 글자 묶음)뿐이다.

/// 단의 종류(계약 6-2).
abstract final class CellKind {
  static const dynasty = 0, leader = 1, cabinet = 2, organ = 3, phase = 4, rank = 5, figure = 6, dep = 7;

  /// 공용 칸 단(계약 부록 가-9의 예약 — 감독 선택 D5). 지금은 렌즈 칸만 온다(변형 `theme:<주제>` · 내보내기 `export/lens.mjs`):
  /// 단 0 = 지도자 칸 자리 · 1 = 지위 단 자리, 단 갈래는 [CellStyle.bandOf]. 렌즈를 끈 동안에는 그리지 않는다.
  /// 단체 단(감독 선택 D5 결정 1 A · 2 A + 덧판 — 내보내기 `export/power.mjs`)의 칸도 이 종류다: 단 2 = 집권 단 · 3 = 실권 단(단 갈래 5 ~ 7) — 늘 그린다.
  static const common = 8;

  /// 상세 창 · 조명이 쓰는 칸 참조의 앞말('leader:3'). 참조가 없는 단은 빈 글.
  static String prefix(int kind) => switch (kind) {
    dynasty => 'dynasty',
    leader => 'leader',
    cabinet => 'cabinet',
    organ => 'organ',
    phase => 'phase',
    rank => 'rank',
    dep => 'dep',
    common => 'lens',
    _ => '',
  };

  /// 칸 참조 글자 — `'<앞말>:<순번>'`. 직위 줄 더(칸 종류 9)는 내보내기가 줄마다 순번을 0부터 세므로(strips.mjs `seq: i`) 줄을 담아
  /// `'office:<줄>:<순번>'`(서고 미리보기와 같은 꼴) — 앞말만으로는 같은 띠의 다른 줄에서 순번이 같은 칸과 참조가 같아져 커서 비춤 · 고른 칸이 함께 켜진다.
  /// 상세 창은 이 앞말을 모르므로(`detailCellPrefixes`) 누르면 띠 창이고 그 칸만 짙다(기관 · 예속 칸과 같은 길).
  static String ref(int kind, int lane, int seq) => kind == Schema4.cellOfficeMore ? 'office:$lane:$seq' : '${prefix(kind)}:$seq';
}

/// 칸의 `style` 비트(계약 6-2).
abstract final class CellStyle {
  static const unkStart = 1, unkEnd = 2, joinLeft = 4, estimated = 8, legend = 16, tagged = 32, range = 64, alt = 128;

  /// 지위의 서열 단계(kind 5). 딱지가 없으면 −1.
  static int rankOf(int style) => ((style >> 8) & 7) - 1;

  /// 예속 이름표의 모습(kind 7): 0 옅은 칸(괴뢰 · 위임) · 1 짙은 칸(식민) · 2 빗금 칸(점령). 없으면 −1.
  static int depLookOf(int style) => ((style >> 11) & 7) - 1;

  /// 번갈아 짙기(비트 14) — 원래 목록의 번호가 홀수(명세 5-3의 6번: 보이는 차례로 셈하면 옆으로 옮길 때 짙기가 깜빡인다).
  static bool altOf(int style) => style & (1 << 14) != 0;

  /// 공용 칸 단(kind 8)의 단 갈래(비트 27~29): 1 렌즈 칸(제도) · 2 단체 칸(붕당 렌즈 = 집권 단의 칸 — 연정은 위아래 두 색 + 색 점) ·
  /// 3 지위로 대신한 체제(지위 칸 꼴) · 4 지위 단 자리로 내린 지도자 칸(지도자 칸 꼴 · 작은 글). 없으면 0.
  static int bandOf(int style) => (style >> 27) & 7;
  static const lensCell = 1, lensGroup = 2, lensRank = 3, lensLeader = 4;

  /// 단체 단의 단 갈래(단 2 · 3 — 내보내기 `export/power.mjs`): 5 한 단체의 집권 칸 · 6 연정 칸(짝을 모르는 연정 포함 — 위아래 두 색 + 색 점) ·
  /// 7 실권 칸(짙은 칠 78% · 테두리 그 색 64% + 먹 · 먹빛 글 — 덧판 x1 A). 칸에 딸린 것(둘째 색 · 색 점 · 누를 단체)은 렌즈 단체 칸과 같은 구역 43.
  static const groupOne = 5, groupTwo = 6, groupReal = 7;
  static bool isGroupBand(int band) => band >= groupOne && band <= groupReal;

  /// 명목 지도자(이름 글만 .5 — 결정 2 A의 고정 기준): 지도자 칸(종류 1)의 비트 29 · 붕당 렌즈가 단 2로 내린 지도자 칸(종류 8 · 갈래 4)의 비트 30
  /// (종류 8은 비트 27~29가 단 갈래라 한 칸 위에). 표시 체크 '단체'가 켜져 있고 빽빽하게 · 조감이 아닐 때만 옅게 그린다.
  static const nominalLeader = 1 << 29, nominalLowered = 1 << 30;

  /// 그 목록에서의 순번(비트 15~26). 싣지 않았거나 넘치면 −1.
  static int seqOf(int style) {
    final v = (style >> 15) & 0xfff;
    return v == 0 || v == 0xfff ? -1 : v - 1;
  }
}

/// 칸에 딸린 일반 항목의 구역 번호(계약 6-2 끝).
abstract final class CellItem {
  static const zone = 40, alt = 41, house = 42, item = 43;

  /// 지도자 칸의 다른 표기(묘호 · 시호 · 이름 · 대수) — 필터 시트의 '지도자 표기'와 '대수'가 쓴다.
  /// **아직 내보내기가 싣지 않는 구역이다**(계약 6-2는 기본 표기 `HT.leaderLabel(c, 'auto')` 하나만 싣는다).
  /// 실을 자리(보고에 적은 제안): `row` · `ref` · `a`(칸의 종류) · `b`(칸의 단)은 구역 40~43과 같고,
  /// `c` = 그 칸의 순번 + 1 · `d` = 대수 + 1(0 = 대수 없음) · `name` = 묘호 · `text2` = `"시호\t이름"`
  /// (시기 칸의 체계 앞말과 같은 탭 약속 — 항목에 글 밭이 `name` · `text2` 둘뿐이라 둘을 탭으로 잇는다).
  /// 구역이 없으면 이 층은 기본 표기 그대로 그린다(표기를 바꿔도 글이 달라지지 않는다).
  static const leaderName = 46;
}

/// 누른 자리에서 찾은 띠 안의 칸 — 앱 틀이 칸 상세 창을 열 때 쓴다.
class StripHit {
  const StripHit(this.band, this.row, this.kind, this.ref, this.uid, this.name, this.rect, {this.houseId = '', this.houseName = '', this.houseColor = 0});

  /// 주인 띠의 번호(타일의 periods.id)와 줄.
  final int band, row;

  /// 단의 종류(계약 6-2의 0~7)와 칸 참조 글자 — `'leader:3'` · `'cabinet:0'` · `'phase:4'` · `'rank:1'` · `'dynasty:2'` · `'organ:0'` · `'dep:1'`.
  /// 번호는 항목 기록(entities)의 그 정권 안에서의 차례다(`x_cellBounds`의 열쇠와 같다 — 시기는 체계를 가로지른 통번호 `ci`).
  final int kind;
  final String ref;

  /// 그 칸이 가리키는 항목의 uid(왕조 · 기관 · 예속 안 칸만 — 없으면 빈 글)와 칸에 적힌 이름.
  final String uid, name;
  final ui.Rect rect;

  /// 그 칸의 가문(구역 42 — 가문 id · 이름 · 색 0xAARRGGBB). 가문을 읽지 않은 장면이거나 가문이 없으면 빈 글 · 0.
  /// 성씨 풍선(확정 설계 1-2 5-2 · `ui/cards.dart`)이 이 값으로 가문 기록을 찾는다.
  final String houseId, houseName;
  final int houseColor;

  /// 커서 비춤(`StripLayer.hotCell`)이 견주는 열쇠.
  String get key => '$band|$ref';

  @override
  String toString() => '$key($kind · $name)';
}

/// 이 장면에서 그린 칸 하나의 자리 기록(맞히기 · 커서 비춤).
/// 장면마다 새로 만들지 않고 밭의 값만 갈아 다시 쓴다([StripLayer._drawn]의 밭 · [StripLayer._drawnCount]까지가 이번 장면의 것).
class _Drawn {
  int band = 0, row = 0, kind = 0;
  String ref = '', uid = '', name = '';
  double l = 0, t = 0, r = 0, b = 0;

  /// 이름을 적은 자리(왼쪽 · 폭 — 적지 않았으면 폭 0). 동군연합의 겹고리 표지가 이름 앞에 붙는다(건의 8의 6-다).
  double textL = 0, textW = 0;

  /// 그 칸의 가문(구역 42) — 커서가 올라간 칸의 성씨 풍선이 쓴다.
  String houseId = '', houseName = '';
  int houseColor = 0;

  /// 꼬리표 밑 흰 사슬의 칸(종이 — [StripLayer.chainAt])인가.
  bool chain = false;
}

/// 단마다의 값 — 명세 01의 3-6절. [radius]는 모서리, [labelPad]는 온 이름 · 첫 글자가 들어갈 여유(px).
class _StripLook {
  const _StripLook(this.radius, this.fullPad, this.shortPad, this.size, this.weight, {this.wght, this.spacing = 0, this.measure, this.centered = true});
  final double radius, fullPad, shortPad, size, spacing;
  final ui.FontWeight weight;
  final double? wght;

  /// 폭을 재는 크기가 그리는 크기와 다른 단(기관 — 10.5로 재고 10으로 그린다. 명세 3-6 사).
  final double? measure;
  final bool centered;

  /// 글줄 높이(css의 line-height) — 이름 밑 '이설 있음' 점선의 자리를 이 값으로 잡는다.
  double get lineHeight => size * 1.2;
}

abstract final class _Strip {
  // 꼬리표 갈래 E(설계 4-1 '실제 띠에 입힘' · 감독 2026-10-15 "지도자 층은 지금처럼 각진 느낌으로 안에"): 칸 단은 꼬리표 안 아래의
  // 흰 층(16)이라 모든 칸이 각지고(반지름 0) 글은 8.5다(목업 t-e). 굵기 · 자간 · 맞춤 여유는 예전 값 그대로.
  // (예전: 반지름 지도자 6 · 내각 5 · 시기 4 · 지위 4 · 왕조 7 · 예속 6 · 기관 6 — 명세 5-3의 13번 · 글 10 ~ 11.5)
  static const _size = 8.5;
  static const dynasty = _StripLook(0, 14, 12, _size, ui.FontWeight.w600, wght: 650, spacing: -0.1);
  static const leader = _StripLook(0, 12, 8, _size, ui.FontWeight.w600, spacing: -0.14);
  static const cabinet = _StripLook(0, 12, 8, _size, ui.FontWeight.w500, spacing: -0.14);
  static const organ = _StripLook(0, 14, 10, _size, ui.FontWeight.w600, spacing: -0.14, measure: 9);
  static const phase = _StripLook(0, 10, 8, _size, ui.FontWeight.w500, spacing: 0.095);
  static const rank = _StripLook(0, 10, 8, _size, ui.FontWeight.w600);
  static const dep = _StripLook(0, 12, 9, _size, ui.FontWeight.w600, wght: 650, spacing: -0.14, centered: false);

  /// 렌즈 칸(웹의 `.tl-cell.k-lens` — 지도자 칸과 같은 자리 · 온 이름은 +12 · 앞글자는 +8).
  static const lens = _StripLook(0, 12, 8, _size, ui.FontWeight.w600, spacing: -0.14);

  /// 렌즈가 지위로 대신한 체제의 지위 칸(지도자 칸 자리 · 지위 칸의 +10 · +8)과, 지위 단 자리로 내린 지도자 칸.
  static const lensRank = _StripLook(0, 10, 8, _size, ui.FontWeight.w600);
  static const lensLeader = _StripLook(0, 12, 8, _size, ui.FontWeight.w600, spacing: -0.14);

  /// 붕당 렌즈의 단체 칸(웹의 `.k-group.k-lens` — 자간 0 · 온 이름 +12 · 첫 글자 +8, 자르지 않는다).
  static const lensGroup = _StripLook(0, 12, 8, _size, ui.FontWeight.w600);

  /// 집권 단 · 실권 단의 단체 칸(웹의 `.tl-band .tl-cell.k-group` — 8.5px · 600 · 자간 0 · 온 이름 +10 · 첫 글자 +8, 자르지 않는다).
  /// 글자는 감독 선택 2026-10-13 "글자 한 단계 작게"(9.5 → 8.5).
  static const group = _StripLook(0, 10, 8, _size, ui.FontWeight.w600);

  /// 직위 줄 더(칸 종류 9 — G7 가 · 칸 그림 갈래 걸음 4)는 지도자 칸과 같은 꼴(흰 각진 층 · 글 크기 · 굵기 — 서고 미리보기 `_cells`의 'office'가 `lead`).
  static _StripLook of(int kind) => switch (kind) {
    CellKind.dynasty => dynasty,
    CellKind.leader || Schema4.cellOfficeMore => leader,
    CellKind.cabinet => cabinet,
    CellKind.organ => organ,
    CellKind.phase => phase,
    CellKind.rank => rank,
    CellKind.common => lens,
    _ => dep,
  };
}

/// 무늬(명세 5-2의 여덟 장 가운데 넷). 띠의 연대 폭 무늬(2/6 · 5/10)와 줄 간격이 다르다 — 뭉뚱그리면 안 된다.
/// 古 pad2 = 3 (명세 0-2의 G.pad2) — layout.dart의 G에는 없는 값이라 제 상수로 둔다.
const double _pad2 = 3;

/// 유령 구분선이 진짜 경계 · 이웃 선 · 이름표와 떨어질 거리, 표식을 다는 가장 좁은 칸(js/timeline.js의 ALT_GAP · ALT_MIN_W).
const double _altGap = 3, _altMinW = 8;

abstract final class _Pattern {
  static const cellEstimated = PatternSpec.stripes(90, 1.5, 4);
  static const cellLegend = PatternSpec.stripes(135, 1.5, 4.5);
  static const agency = PatternSpec.stripes(135, 4, 8);
  static const occupied = PatternSpec.stripes(45, 1, 4);
  static const dense = PatternSpec.stripes(90, 1, 4);
}

/// 한 칸이 놓인 자리(지금 연표 `layoutStrip`이 내놓는 값 + 타일에 걸친 조각의 표시) + 그리기 앞에 한 번 재어 둔 이름 · 꼬리 · 무늬.
class _Placed {
  int index = -1;
  double a = 0, b = 0, l = 0, r = 0;
  bool jl = false, jr = false, atL = false, atR = false;

  /// 타일 경계에서 잘린 조각(보이지 않는 이음매 — 끝 조각도 테두리도 두지 않는다). 두 단 띠의 조각([StripLayer._paintPieces])은 다른 단 · 층 전체로
  /// 이어지는 쪽(이음매)도 잘린 쪽이다.
  bool cutL = false, cutR = false;

  /// 왼쪽이 **타일 경계**에서 잘렸는가 — 이름은 왼쪽이 타일에 잘리지 않은 조각(또는 화면 왼쪽 끝에 닿은 조각)만 쓴다. 보통 칸은 [cutL]과 같고,
  /// 두 단 띠의 조각은 이음매에서 시작한 조각이 거짓이다(그 조각이 이름 자리일 수 있다).
  bool tileL = false;

  /// 타일에 걸친 칸 전체의 폭(이름 · 미정 꼬리 · is-thin은 조각이 아니라 칸 전체로 정한다). 두 단 띠의 조각은 그 조각 전체(타일을 합친 것)의 폭.
  double wholeL = 0, wholeR = 0;

  /// 두 단 띠의 조각이면 그 칸(타일을 합친 칸과 그 조각들 — [StripLayer._scanPieces])과 화면에 든 칸 전체의 폭(is-thin은 칸 전체로). 보통 칸은 null · 0.
  _PieceCell? cell;
  double cellW = 0;

  // ---- 한 번 재어 두는 것 ----
  int style = 0, color = 0, seq = -1;
  bool thin = false, alt = false, openL = false, openR = false, spot = false, house = false;

  /// 같은 사람의 칸(건의 8의 6-나 — 고른 칸의 짝 [em.Look.twins] 또는 올린 칸의 짝 [StripLayer.hotTwins]): 먹 1.5px 테 · 고름의 흐림에서 빠진다.
  bool twin = false;
  String text = '', tag = '';
  double textW = 0, tagW = 0;

  /// 이 칸의 가문(구역 42)과 그 색 · 이름. 가문이 없으면 빈 글.
  String houseId = '', houseName = '';
  int houseColor = 0;

  /// 이 칸 아래에 가문 줄이 깔리는가(표시 체크 '가문' + 지도자 칸 + 가문이 있음) — 이름 밑 '이설 있음' 점선이 그만큼 위로 올라간다.
  bool houseLine = false;

  /// 앞글자만(온 이름을 왼쪽 맞춤해 잘라 보임) — 이름표를 옮길 수 없다.
  bool fixed = false;
  _Fade? fade;

  /// 테두리 두께(좁은 칸 · 이어 붙은 오른쪽은 0).
  double bl = 1, br = 1;

  /// 앞 칸의 끝이 미정이라 사이 구분선도 점선(u-l).
  bool uLeft = false;

  /// 유령 구분선을 비켜 이름을 옮긴 만큼 · 선을 하나도 긋지 못해 이름 밑에 점선을 다는 칸.
  double dx = 0;
  bool hasAlt = false;

  /// 붕당 렌즈의 단체 칸에 찍을 색 점 수(칸에 다 들 때만 — 아니면 0)와 첫 점의 왼쪽(웹의 `.gd` 6px · 8px 간격).
  int dots = 0;
  double dotsLeft = 0;

  /// 명목 지도자 칸 — 이름 글만 .5(웹의 `.k-leader.is-nominal b`).
  bool nominal = false;

  /// 빌린 직위 줄의 칸(타일 칸 종류 1 · 2 · 9이고 style 27비트 — [Schema4.isBorrowed]): 칸 전체 .72 · 윗변 1px 파선([StripLayer.borrowedAlpha]).
  bool borrowed = false;

  /// 실권 밑줄(구역 56)의 기간과 겹친 지도자 칸: 칸 전체 .55([StripLayer.oustedAlpha] — 빌린 칸의 .72를 대신한다).
  bool ousted = false;

  /// 칸의 정통성(구역 57 — 칸 그림 갈래 걸음 3 · 스위치 `legit`): 명목(이름 먹 45 — [LegitLook.nominalName]) · 주장(칸 바탕 화소 빗금 — [StripLayer._claimCell]).
  bool legitNominal = false, claim = false;

  /// 이 칸(조각)이 피후견 칸인 섭정 기간 — (섭정 칸 · 이 칸 안의 시작 · 끝(화면 px)). 아랫변 안쪽 2px 먹 60([StripLayer._regentLines]).
  final regents = <(_Regent, double, double)>[];

  /// 이름표 글자의 가운데(비키기 전) — [_measure]가 한 번 셈해 둔다.
  double center = 0;

  /// 꼬리표 밑 흰 사슬의 칸(G5 #9 나 — [StripLayer._paintChain]): 글 자리의 왼쪽(왕조는 가문 색 막대 자리) · 첫 칸의 구멍 · 왕조 막대 · 지위 서열 눈금 수.
  double chainX = 0, holeX = 0;
  bool chainHole = false, chainBar = false;
  int ticks = 0;

  /// 모호한 구간의 무늬 조각 [a, b, 무늬 종류]와 좌우 점선 테두리.
  final layers = <(double, double, int)>[];
  bool zl = false, zr = false;

  /// 이 칸이 그은 세로 칸 구분선의 열(왼쪽 · 오른쪽 — 긋지 않았으면 NaN). 칸 층 가로선의 끝이 이 열에 맞춘다
  /// (감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' — [StripLayer._ruleEnds]).
  double divL = double.nan, divR = double.nan;

  /// 잘리지 않은 끝이 타일 이음매에 딱 놓였고 이웃 타일에 그 이음매에서 맞닿는 같은 단의 칸이 있다(왼쪽 · 오른쪽 — [StripLayer._seamAt]).
  /// 두 타일이 저마다 구분선을 그어 그 사이 1px을 가로선이 메워야 한다([StripLayer._ruleEnds]).
  bool seamL = false, seamR = false;

  double get w => r - l;

  /// 장면마다 새로 만들지 않고 처음 상태로 되돌려 다시 쓴다.
  void reset(int index, double a, double b) {
    this.index = index;
    this.a = a;
    this.b = b;
    l = 0;
    r = 0;
    jl = false;
    jr = false;
    atL = false;
    atR = false;
    cutL = false;
    cutR = false;
    tileL = false;
    wholeL = 0;
    wholeR = 0;
    cell = null;
    cellW = 0;
    style = 0;
    color = 0;
    seq = -1;
    thin = false;
    alt = false;
    openL = false;
    openR = false;
    spot = false;
    house = false;
    twin = false;
    houseId = '';
    houseName = '';
    houseColor = 0;
    houseLine = false;
    text = '';
    tag = '';
    textW = 0;
    tagW = 0;
    fixed = false;
    fade = null;
    bl = 1;
    br = 1;
    uLeft = false;
    dx = 0;
    hasAlt = false;
    dots = 0;
    dotsLeft = 0;
    nominal = false;
    borrowed = false;
    ousted = false;
    legitNominal = false;
    claim = false;
    regents.clear();
    center = 0;
    chainX = 0;
    holeX = 0;
    chainHole = false;
    chainBar = false;
    ticks = 0;
    layers.clear();
    zl = false;
    zr = false;
    divL = double.nan;
    divR = double.nan;
    seamL = false;
    seamR = false;
  }
}

/// 옅어지는 끝(지금 연표 `unkCell`): 왼쪽은 [ma]에서 1로 [fl]px에 걸쳐, 오른쪽은 [mb]에서 1로 [fr]px에 걸쳐.
class _Fade {
  const _Fade(this.fl, this.fr, this.ma, this.mb);
  final double fl, fr, ma, mb;
  bool get any => fl > 0 || fr > 0;
}

/// 기간 조명이 가르는 밝기(명세 06 3-3): 구간마다 제 밝기 · 구간 밖 [outside]. [flat]이면 칸 전체를 흐린 쪽으로 고르게.
/// 구간의 밝기는 조명의 진행([em.Spot.glow])을 따라 띠의 밝기와 조명 밝기 사이를 오가므로 구간마다 다를 수 있다.
/// 겹친 곳은 **가장 밝은 값**을 쓴다 — 자리를 물려주는 동안 두 구간에 다 드는 곳이 잠깐 어두워지지 않게(띠 층 `_Fade.alphaAt`과 같은 규칙).
/// 칸 하나를 그리는 동안만 쓰이므로 층이 하나만 두고 값을 갈아 다시 쓴다(장면마다 칸 수만큼 만들지 않는다).
class _Dim {
  final _a = <double>[], _b = <double>[], _v = <double>[];
  double outside = 1;
  bool flat = false;

  /// 조명이 가르지 않는 칸 — 전체가 한 밝기.
  void plain(double alpha) {
    _a.clear();
    _b.clear();
    _v.clear();
    flat = false;
    outside = alpha;
  }

  void begin(double outside) {
    _a.clear();
    _b.clear();
    _v.clear();
    flat = false;
    this.outside = outside;
  }

  void add(double a, double b, double alpha) {
    _a.add(a);
    _b.add(b);
    _v.add(alpha);
  }

  bool get isEmpty => _a.isEmpty;

  /// 칸 [l]~[r]을 한 밝기로 칠해도 되면 그 밝기(통째로 덮는 구간이 있고, 그보다 밝은 조각이 따로 없을 때). 아니면 null.
  double? evenAlpha(double l, double r) {
    double? best;
    for (int i = 0; i < _a.length; i++) {
      if (_a[i] <= l && _b[i] >= r && (best == null || _v[i] > best)) best = _v[i];
    }
    if (best == null) return null;
    for (final v in _v) {
      if (v > best + 1e-6) return null;
    }
    return best;
  }

  double at(double x) {
    if (flat) return outside;
    var best = outside;
    for (int i = 0; i < _a.length; i++) {
      if (x >= _a[i] - .01 && x < _b[i] - .01 && _v[i] > best) best = _v[i];
    }
    return best;
  }

  /// 칸 전체의 밝기를 [k]배로 — 구간 밖 · 구간마다 모두(css `opacity`가 요소 전체에 곱해지듯. 빌린 칸 .72).
  void scale(double k) {
    outside *= k;
    for (int i = 0; i < _v.length; i++) {
      _v[i] *= k;
    }
  }

  /// 자를 곳이 없다 — 칸 전체가 한 밝기라 한 조각으로 그리면 된다.
  bool get even => flat || _a.isEmpty;

  /// [l]~[r] 안의 경계 x를 [out]에 담는다 — 여기서 색을 끊는다.
  void cutsInto(List<double> out, double l, double r) {
    if (flat) return;
    for (int i = 0; i < _a.length; i++) {
      if (_a[i] > l && _a[i] < r) out.add(_a[i]);
      if (_b[i] > l && _b[i] < r) out.add(_b[i]);
    }
  }

  /// [l]과 [r] 사이의 첫 경계(없으면 [r] 그대로).
  double cutBetween(double l, double r) {
    if (flat) return r;
    var best = r;
    for (int i = 0; i < _a.length; i++) {
      if (_a[i] > l && _a[i] < best) best = _a[i];
      if (_b[i] > l && _b[i] < best) best = _b[i];
    }
    return best;
  }
}

/// 칸에 딸린 모호한 구간(구역 40) — 화면 px.
class _Zone {
  _Zone(this.a, this.b, this.look);
  double a, b;
  final int look;
}

/// 이설이 말하는 경계 하나(구역 41) — 화면 px와 주인 칸의 순번.
class _Ghost {
  _Ghost(this.x, this.seq);
  double x;
  final int seq;
}

class StripLayer extends TileLayer {
  final _sprites = _CellSprites();

  /// 흰 사슬 종이의 둥근 귀(반지름 3 — [_ChainSprites]).
  final _chainSprites = _ChainSprites();

  // ── 층 배선 없이 읽는 길 ── 왼쪽 칸(paint/gutter.dart)이 같은 장면에 사슬 이름 자리([chainMarks])를 읽는다 — 띠 층의 `BandLayer.of`와 같은 길.
  static final _byScene = Expando<StripLayer>('칸 층');

  /// 이 장면을 그린 칸 층(아직 한 장면도 그리지 않았으면 null).
  static StripLayer? of(Object scene) => _byScene[scene];

  /// 이번 장면에 그린 꼬리표 밑 흰 사슬의 왼쪽 칸 이름 자리 — (줄 × 2 + 사슬 차례) → 화면 왼쪽에 가장 가까운 사슬([ChainMark]). [beginFrame]이 비운다.
  final chainMarks = <int, ChainMark>{};

  /// 이번 장면에 그린 직위 줄 더 층(칸 종류 9 — G7 가 · 칸 그림 갈래 걸음 4)의 왼쪽 칸 줄 이름 자리 — (줄 × 32 + 직위 줄 더의 줄) → 화면 왼쪽에 가장 가까운
  /// 띠의 그 층([ChainMark] — `slot`은 직위 줄 더의 줄 · `label`은 그 띠 구역 55의 줄 이름 · y는 층 가운데). [beginFrame]이 비운다(왼쪽 칸 gutter.dart `_officeLabels`가 읽음).
  final officeMarks = <int, ChainMark>{};

  /// 이번 장면에 사슬의 실을 그은 띠(타일마다 조각이 와도 한 번 — 그 띠의 첫 사슬 종이보다 먼저).
  final _threaded = <int>{};

  /// 사슬의 구멍 · 꼬리표 아랫변의 점 — 층의 끝(종이 · 귀 조각 뒤)에 매끈한 동그라미로 그린다.
  final _rings = <_Ring>[];
  final _ringFill = ui.Paint()..isAntiAlias = true;
  final _ringLine = ui.Paint()
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1;

  /// 지금 그리는 무리가 꼬리표 밑 사슬 자리이면 그 사슬 차례(0 왕조 · 1 지위 자리), 아니면 −1 — [_paintLane]이 정하고 [_paintGroup]이 본다.
  int _chainSlot = -1;

  /// 밝기 상태(총괄이 장면에 넣기 전에는 중립). 층은 장면마다 여기서만 밝기를 묻는다.
  /// 이 층은 장면마다 묶음을 처음부터 다시 모으므로(보관하는 묶음이 없다) `emphasis.version`이 달라져도 버릴 것이 없다 —
  /// 밝기는 항목마다 색의 알파에 곱해 같은 묶음에 넣는다(`saveLayer`를 쓰지 않는다). `emphasis.active`(흐르는 중)에도 그대로 장면마다 값을 묻는다.
  em.Emphasis? emphasis;
  static final em.Emphasis _neutral = em.Emphasis();

  em.Emphasis get _em => emphasis ?? _neutral;

  // ──────────── 필터 시트의 표시 값(11물결). 그리기만 바꾼다(줄 쌓기 · 자료는 그대로) ────────────
  // 앱 틀이 `SceneMarks`에 적어 두고 층이 장면마다 제 손으로 읽는다([beginFrame]) — 인물 · 이름표 · 막대 층과 같은 길이다.

  /// '이설' 체크. 끄면 유령 구분선도 이름 밑 '이설 있음' 점선도 그리지 않는다(모호한 칸의 무늬는 그대로 — 지금 연표 `_altPlan`의 `alt`).
  bool showAlt = true;

  /// 표시 체크 '가문'. 켜면 지도자 칸 아래에 가문 색의 가는 줄(`.tl-houseline`)을 깐다 — 칸을 다시 배치하지는 않는다.
  bool showHouses = false;

  /// 지도자 칸의 표기(`HT.LEADER_LABELS` — `auto` · `temple` · `title` · `given` · `temple-title` · `all`)와 대수.
  /// 값이 바뀌면 칸의 글이 달라지므로 타일에 걸어 둔 글 · 폭 보관을 [_labelGen]으로 비운다.
  String get leaderLabel => _leaderLabel;
  String _leaderLabel = 'auto';

  set leaderLabel(String value) {
    if (value == _leaderLabel) return;
    _leaderLabel = value;
    _labelGen++;
  }

  bool get leaderOrdinal => _leaderOrdinal;
  bool _leaderOrdinal = false;

  set leaderOrdinal(bool value) {
    if (value == _leaderOrdinal) return;
    _leaderOrdinal = value;
    _labelGen++;
  }

  /// 표기 · 대수가 바뀐 횟수 — 타일에 걸어 둔 글 · 폭은 이 번호가 다르면 비운다.
  int _labelGen = 0;

  /// 기본 표기가 아니어서 칸의 글을 다시 지어야 하는가(구역 46을 읽는 것도 이때뿐이다).
  bool get _labelOn => _leaderLabel != 'auto' || _leaderOrdinal;

  /// 줄 → 그 줄의 띠들(화면 px, 타일에 걸친 조각을 합친 것). 칸은 제 띠 안쪽에 갇힌다.
  final _hostsOf = <int, List<_Host>>{};

  /// 타일에 걸친 칸(id → 조각을 합친 좌우) — 이름을 가운데 놓고 꼬리 길이를 재려면 칸 전체가 필요하다.
  final _joined = <int, (double, double)>{};

  /// 타일에 걸친 칸(id → 조각을 합친 절대 분 시작 · 끝) — 칸 전체가 실권 기간과 겹치는지 잴 때([_measure]).
  final _joinedMin = <int, (double, double)>{};

  /// 잘리지 않은 끝이 타일 이음매에 딱 놓인 칸 — (줄, 종류, 단, 이음매의 분). 시작이 이음매인 칸([_seamStarts])과 끝이 이음매인 칸([_seamEnds]).
  /// [beginFrame]이 그릴 타일마다 모으고 [_seamAt]이 이웃 타일의 맞닿은 칸을 찾는다(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' — 타일 이음매).
  final _seamStarts = <(int, int, int, int)>{}, _seamEnds = <(int, int, int, int)>{};

  /// 이 장면의 실권 밑줄(띠 층 [BandLayer.powerSpans] — 빼앗긴 띠 id → 기간들). 띠 층이 없는 그리개면 빈 것.
  Map<int, List<PowerSpan>> _powers = const {};

  /// 이 장면에 빽빽한 칸을 이미 그린 (띠 · 종류) — 한 띠를 여러 타일이 나눠 가져도 한 번만 그린다.
  final _denseDone = <int>{};

  /// (줄 · 종류 · 단) → 모호한 구간 · 이설 경계. 한 항목이 여러 타일에 실리므로 항목 번호로 합친다.
  final _zonesOf = <int, List<_Zone>>{};
  final _ghostsOf = <int, List<_Ghost>>{};

  /// (띠 · 종류 · 단 · 순번) → 그 칸의 가문 id · 색 · 이름(구역 42 — 가문 강조 · 가문 조명 · 표시 체크 '가문' · 커서가 칸 위에 있을 때만) ·
  /// 그 칸이 가리키는 항목의 uid(구역 43).
  final _houseOf = <(int, int, int, int), (String, int, String)>{};
  final _refOf = <(int, int, int, int), (String, String)>{};

  /// (띠 · 종류 · 단 · 순번) → 지도자 칸의 다른 표기(묘호 · 시호 · 이름 · 대수 — 구역 46). 기본 표기가 아닐 때만 읽는다.
  final _leaderOf = <(int, int, int, int), (String, String, String, int)>{};

  // ──────────── 렌즈(주제 보기 — 감독 선택 D5 결정 5 A · 설계 7-8 10-2) ────────────
  // 켠 렌즈의 칸은 타일의 칸 종류 8로 오고(변형 `theme:<주제>`), 그 주제 자료가 있는 나라의 지도자 칸은 엔진이 이미 가렸다.
  // 그래서 렌즈를 켠 동안 남은 지도자 칸은 모두 '자료 없는 나라'의 것이라 .4로 옅게 그린다(웹의 `is-nolens`).

  /// 렌즈를 켰는가 · 표시 체크 '지도자'(렌즈 켬 배치는 지도자 칸이 없는 트랙에도 그 자리를 두므로 따로 본다) — [beginFrame]이 배치에서 읽는다.
  bool _lensOn = false, _leadersOn = true;

  /// 명목 지도자를 옅게 그리는가 — 표시 체크 '단체'가 켜져 있고 빽빽하게 · 조감이 아닐 때(웹 `_groupsOn()`).
  bool _nominalOn = false;

  /// 단체 계보 창에서 고른 단체와 그 색(`SceneMarks.groupFocus` — 웹 `setGroupFocus`). 없으면 null.
  String? _groupFocus;
  int _groupFocusColor = 0;

  /// (띠 · 단 · 순번) → 렌즈 칸이 가리키는 것([_LensRef]). 구역 43의 `a`가 8인 항목에서 온다.
  final _lensOf = <(int, int, int), _LensRef>{};

  /// 커서가 올라간 렌즈 칸의 갈래 — 모든 나라의 같은 갈래 칸이 진해지고 나머지 렌즈 칸은 .4(웹의 `.lens-echo` · `.is-fam`). 없으면 ''.
  String _echoFam = '';

  /// 지금 그리는 무리가 칸 종류 8에서 왔으면 그 단 갈래(아니면 0)와, 단의 것과 다른 글 생김새(지위로 대신한 체제 11.5 · 내린 지도자 칸 9.5).
  int _lensBand = 0;
  _StripLook? _lookOverride;

  _StripLook _lookFor(int kind) => _lookOverride ?? _Strip.of(kind);

  /// 이 장면에서 그린 칸들(맞히기 · 커서 비춤) — 뒤에 그린 것이 위에 있다. [_drawnCount]까지가 이번 장면의 것(밭은 다시 쓴다).
  final _drawn = <_Drawn>[];
  int _drawnCount = 0;

  /// 커서가 비추는 칸의 열쇠([StripHit.key]) — 앱 틀이 넣는다.
  String? hotCell;

  /// 커서가 올라간 칸의 사람이 앉은 모든 자리의 열쇠([SceneMarks.hotTwins]) — 앱 틀이 넣는다.
  Set<String>? hotTwins;

  /// 이번 장면에 그린 칸 하나의 자리와 이름 자리(띠 번호 · 칸 참조 'leader:3'). 그리지 않았으면 null.
  /// 타일에 걸쳐 조각으로 그린 칸은 이름을 적은 조각을 먼저 돌려준다.
  ({double l, double t, double r, double b, double textL, double textW})? drawnCell(int band, String ref) {
    ({double l, double t, double r, double b, double textL, double textW})? any;
    for (int i = 0; i < _drawnCount; i++) {
      final d = _drawn[i];
      if (d.band != band || d.ref != ref) continue;
      final hit = (l: d.l, t: d.t, r: d.r, b: d.b, textL: d.textL, textW: d.textW);
      if (d.textW > 0) return hit;
      any ??= hit;
    }
    return any;
  }

  /// [x] · [y](배치 px)에 있는 칸. 마지막으로 그린 장면의 자리 기록에서 찾는다(위에 그린 것 먼저).
  StripHit? hitStrips(double x, double y) {
    for (int i = _drawnCount - 1; i >= 0; i--) {
      final d = _drawn[i];
      if (x >= d.l && x <= d.r && y >= d.t && y <= d.b) {
        return StripHit(d.band, d.row, d.kind, d.ref, d.uid, d.name, ui.Rect.fromLTRB(d.l, d.t, d.r, d.b), houseId: d.houseId, houseName: d.houseName, houseColor: d.houseColor);
      }
    }
    return null;
  }

  /// [x] · [y](배치 px)가 이번 장면에 그린 꼬리표 밑 흰 사슬의 종이 위인가. 관계선 · 동군연합 이음줄은 그 종이 뒤(띠 뒤 판)로 지나 거기서는
  /// 보이지 않으므로 그 자리의 누름은 선이 아니라 사슬 칸이 받는다(links.dart [LinkLayer.hitLinks] · unions.dart `hitUnion` — 검토 2026-10-25).
  bool chainAt(double x, double y) {
    for (int i = _drawnCount - 1; i >= 0; i--) {
      final d = _drawn[i];
      if (d.chain && x >= d.l && x <= d.r && y >= d.t && y <= d.b) return true;
    }
    return false;
  }

  /// 시기 단의 체계 이름표를 이미 단 (줄, 단) — 한 체계에 딱 하나.
  final _tagged = <int>{};

  /// (줄, 종류, 단) → 그 단에 마지막으로 그린 이름의 오른쪽 끝. 자료가 겹쳐 와도 이름은 겹쳐 그리지 않는다.
  final _labelRight = <int, double>{};

  /// 이번 장면에 흰 층을 깐 띠 — 타일마다 조각이 와도 한 번만.
  final _floored = <int>{};

  /// 흰 층의 세로 금(갈래 E): 이번 단에서 마지막으로 그은 x와 단의 안쪽 두 끝 — 이웃 칸의 끝과 시작이 겹금이 되지 않게(목업 chain의 lastX).
  double _divLast = double.negativeInfinity, _divLo = 0, _divHi = 0;

  /// 흰 층의 칸 사이 세로 금: 먹 20(그림판 먹 단계 25). 칸의 시작 · 끝마다 하나(타일에 잘린 쪽 · 층의 두 끝 · 2.5px 안의 이웃 금은 건너뜀).
  /// 시작을 모르거나 이어진 쪽([dashL])은 2/2 파선. 칸 층 가로선의 꼴 b(감독 결정 2026-10-25 · [FloorRuleLook.dividerOf])는 가로선과 같은 먹 12로 낮춘다.
  /// 위아래 끝은 [_dividerSpan] — 위아래 가로 금에 맞닿음(꼴 off면 옛 1px 들임). [under]는 칸 아랫변의 밑줄 두께(집권 · 실권 칸 2 — 그 위에서 멈춤).
  /// 그은 열은 칸에 적어 두고([_Placed.divL] · [_Placed.divR] — 가로선 끝이 맞춘다) 그은 범위는 [_divCols]에(섭정 밑줄 · 주장 빗금이 비킴 — 맞닿음으로
  /// 늘어난 위아래 1px까지). 두 단 띠의 조각을 그리는 동안은 [_pieceDividers](칸 그림 갈래 — 조각 안 제 자리).
  void _floorDividers(PaintContext c, double l, double top, double r, double b, _Dim dim, _Placed p, {bool dashL = false, double under = 0}) {
    if (_pieceDivs != null) {
      _pieceDividers(c, top, b, dim, p, dashL);
      return;
    }
    final low = FloorRuleLook.dividerOf(PaintPick.rows);
    final (y0, y1) = _dividerSpan(top, b, p, under);
    for (final (x, skip, dash, left) in [(l, p.cutL, dashL, true), (r - 1, p.cutR, false, false)]) {
      if (skip) continue;
      final q = x.roundToDouble();
      if ((q - _divLast).abs() < 2.5 || q < _divLo + 2 || q > _divHi - 3) continue;
      final ink = CanvasInk.alpha(low ?? .20, dim.at(q));
      c.quads.vLine(q, y0, y1, ink, dash: dash ? 2 : 0, gap: dash ? 2 : 0, phase: _divTop.isNaN ? top : y0);
      _divLast = q;
      _divCols.add((q, y0, y1));
      if (left) {
        p.divL = q;
      } else {
        p.divR = q;
      }
    }
  }

  /// 칸 구분선이 맞닿는 위 · 아래 끝(화면 px — 감독 결정 2026-10-25 "왕 세로선부분이랑 가로선 부분이랑 딱 맞닿게 해줘 틈 없게" · "모든 가로세로
  /// 구분선은 맞닿게"): 지금 층의 [_divTop](위 가로 금 바로 아랫줄)부터 [_divBottom](아래 가로 금 줄 — 칠하지 않는 끝)까지. 가로 금 줄은 칠하지 않아
  /// 만나는 점에 먹이 두 번 얹히지 않는다. 빌린 칸은 제 윗변 파선([_borrowedTop] — 칸 [top]의 한 줄 위) 아래부터, 밑줄이 있는 칸은 밑줄 위까지.
  /// 맞닿음이 없는 층(꼴 off · 몸통이 없는 줄)은 옛 들임 — 칸 상자([top] ~ [b]) 안 위아래 1px.
  (double, double) _dividerSpan(double top, double b, _Placed p, double under) {
    if (_divTop.isNaN) return (top + 1, b - 1);
    final y0 = p.borrowed ? math.max(_divTop, top.floorToDouble()) : _divTop;
    return (y0, _divBottom - under);
  }

  /// 집권 · 실권 칸의 2px 밑줄 자리(왼쪽 · 위 · 오른쪽 · 아래). 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off가 아니면)에서는
  /// 정수 px: 두 끝은 칸 구분선의 열([_floorDividers]와 같은 셈 — 왼쪽 round(l)부터 · 오른쪽 round(r − 1)까지)이라 밑줄 위에서 멈춘 구분선([_dividerSpan]의
  /// under)의 끝을 밑줄이 받고, 띠 테에 닿거나 테 가까이라 구분선을 띠 테가 맡는 끝([_floorDividers]의 건너뜀 · [_ruleEnds]와 같은 셈)은 테 바로 옆 열
  /// (칸 층 가로선의 [_ruleLo] · [_ruleHi]와 같은 셈), 위아래는 아래 가로 금 바로 위 두 줄([_divBottom] — 있을 때). 소수 끝이면 반 픽셀이 구분선 열 너머
  /// 이웃 칸으로 새고 테 옆 첫 열은 옅었다. 꼴 off는 칸 상자 그대로(옛 그림).
  (double, double, double, double) _underSpan(_Placed p, double l, double r, double b) {
    if (PaintPick.rows == FloorRule.off) return (l, b - 2, r, b);
    final x0 = p.atL || (!p.cutL && l.roundToDouble() < _divLo + 2) ? (_divLo - 1).floorToDouble() + 1 : l.roundToDouble();
    final x1 = p.atR || (!p.cutR && (r - 1).roundToDouble() > _divHi - 3) ? _divHi.floorToDouble() : (r - 1).roundToDouble() + 1;
    final y1 = _divBottom.isNaN ? b : _divBottom;
    return (x0, y1 - 2, math.max(x1, x0 + 1), y1);
  }

  // ──────────── 칸 층 사이 흐린 가로선(감독 지적 2026-10-25 — paint/floor_rules.dart · 스위치 `--paint-rows=a|b|c|off`) ────────────

  /// 이 타일에서 모은 가로선 조각 — 타일의 끝([paintTile])에 (띠 · 줄)마다 합쳐 한 번씩 긋는다(위 층의 아랫선과 아래 층의 윗선이 같은 줄).
  final _rules = FloorRules();

  /// 지금 그리는 무리(한 띠의 한 층)의 가로선 자리 — 층 윗줄 · 윗선 줄 · 아랫선 줄(없으면 NaN)과 띠 테 안쪽의 두 끝(정수 px).
  /// [_paintGroup]이 칸을 그리기 전에 정하고([_ruleAt]) 칸을 다 그린 뒤 칸마다 읽는다([_ruleCells]).
  double _ruleFloor = double.nan, _ruleTop = double.nan, _ruleBottom = double.nan, _ruleLo = 0, _ruleHi = 0;

  /// 지금 층의 칸 구분선이 맞닿는 위 · 아래 끝(화면 px 정수 — [_dividerSpan]): 위 가로 금(첫 층은 색줄 아랫금) 바로 아랫줄 · 아래 가로 금 줄
  /// (다음 층 윗선 · 흰 사건 칸 윗줄 · 띠 아랫변이면 그 테 줄). 맞닿음이 없으면(꼴 off · 몸통이 없는 줄) NaN — 옛 들임. [_ruleAt]이 정한다.
  double _divTop = double.nan, _divBottom = double.nan;

  /// 지금 무리의 가로선 밝기 — 칸마다의 밝기가 아니라 **띠의 밝기**(띠 층의 층 사이 금과 같은 길: 띠의 흐림 · 기간 조명 구간 — bands.dart `_Fade`).
  /// 가로선은 띠 몸통의 짜임이라 고른 칸 · 빌린 칸(.72) · 실권 칸(.55)의 제 밝기를 타지 않는다.
  final _ruleDim = _Dim();

  /// 한 층(위 [top] · 높이 [height] — 화면 px)의 가로선 줄: 윗선은 층의 윗선 줄(첫 층이면 이름 색줄 아랫변의 금 줄 — 띠 층 `_paintTwoPiece`의 bt) ·
  /// 아랫선은 층 바로 밑 줄(다음 층의 윗선 줄이거나 흰 사건 칸의 윗줄 — 띠 아랫변에 닿으면 없음). 띠 층의 층 사이 금과 같은 줄이다.
  /// 가로선을 끈 꼴([FloorRule.off]) · 몸통이 없는 줄(조감 · 접힌 줄)은 모두 NaN. [lo] · [hi]는 칸을 가두는 띠 테 안쪽 · [spots]는 그 띠의 조명 구간.
  void _ruleAt(PaintContext c, int row, double top, double height, double lo, double hi, _Host host, List<em.Spot> spots) {
    _ruleFloor = _ruleTop = _ruleBottom = double.nan;
    _divTop = _divBottom = double.nan;
    if (PaintPick.rows == FloorRule.off) return;
    final layout = c.layout, geo = layout.geo(row), v = c.v;
    if (geo.bodyTop < 0) return;
    final base = layout.rowTop(row);
    // 띠 아랫변은 그 띠의 몸통 아랫변(띠 층 `_tagBox`의 bodyB와 한 셈 — TagLook.bodyBottom): 칸 그림 갈래의 '띠마다 제 몸통 높이'(스위치 body) · 직위 줄 더
    // (스위치 office) · 남의 아래 층을 뺀 두 장 꼬리표는 줄의 띠 아랫변보다 짧다 — 줄 값으로 재면 마지막 층의 아랫선([_ruleBottom])이 띠 테 밖에 서고
    // 칸 금([_divBottom])이 테 줄을 덮었다(구분선 갈래와 합칠 때 고침).
    final oldStore = !(layout.spec(row)?.cellRows ?? false);
    final stripB = v.yOf(base + geo.bodyTop);
    final bandB = v.yOf(base + TagLook.bodyBottom(geo, host.look, oldStore: oldStore, loose: layout.conditions.density < 0, sub: host.sub));
    _ruleFloor = top;
    _ruleTop = (top - stripB).abs() < .5 ? top - 1 : top;
    if (top + height < bandB - .5) _ruleBottom = top + height;
    // 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게'): 세로 칸 구분선은 위 가로 금 바로 아랫줄부터 아래 가로 금 줄 앞까지 —
    // 가로 금 줄(띠 층의 층 사이 금 · 이 가로선이 얹히는 줄)과 같은 줄 셈(가로 금은 [Quads.hLine]이 줄을 내림해 긋는다). 띠 아랫변이면 그 테 줄 앞까지.
    _divTop = _ruleTop.floorToDouble() + 1;
    _divBottom = (_ruleBottom.isNaN ? bandB - 1 : _ruleBottom).floorToDouble();
    // 띠 왼쪽 테는 floor(띠 왼쪽) 열(bands.dart `_edge`)이라 가로선은 그 바로 다음 열부터(예전 ceil(lo)은 lo가 소수면 테 옆 1열이 비었다).
    // 오른쪽 floor(hi)는 이미 테 열(floor(띠 오른쪽 − 1)) 바로 앞이다.
    _ruleLo = (lo - 1).floorToDouble() + 1;
    _ruleHi = hi.floorToDouble();
    // 띠의 밝기: 띠의 흐림, 조명 구간 안은 조명 밝기 쪽으로 진행만큼(띠 층 `_Fade.alphaAt` — base + (조명 − base) × 진행).
    final alpha = _em.bandAlpha(host.id, row), d = _ruleDim;
    if (spots.isEmpty) {
      d.plain(alpha);
      return;
    }
    final lit = _em.look.lit ? _em.spotAlpha(host.id, row) : 1.0;
    d.begin(alpha);
    for (final s in spots) {
      d.add(v.xOf(s.start), v.xOf(s.end), alpha + (lit - alpha) * s.glow.clamp(0.0, 1.0));
    }
  }

  /// 이 층에 그린 칸들([_placed]의 앞 [n]개 가운데 [minW] 이상)의 가로선 조각 — 칸을 다 그린 뒤(세로 칸 구분선의 열이 정해진 뒤 — [_ruleEnds]).
  /// 옛 자리(0.5px 틈을 메운 칸 상자)로 맞닿던 이웃 칸(사이 구분선 하나를 함께 쓰는 칸)은 끊지 않고 잇는다 — 앞 조각을 뒤 조각의 시작까지 늘임.
  void _ruleCells(int band, int n, double minW) {
    _Placed? prev;
    double prevX0 = 0, prevX1 = 0;
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      if (p.r - p.l < minW) continue;
      final (x0, x1) = _ruleEnds(p);
      if (prev != null) {
        if (_ruleOld(prev).$2 >= _ruleOld(p).$1 && prevX1 < x0) prevX1 = x0;
        _ruleCell(band, prev, prevX0, prevX1);
      }
      prev = p;
      prevX0 = x0;
      prevX1 = x1;
    }
    if (prev != null) _ruleCell(band, prev, prevX0, prevX1);
  }

  /// 칸 하나의 옛 가로선 자리 — 칸 상자(잇지 않는 쪽의 0.5px 틈은 메움 — 타일에 잘린 쪽은 정수 이음매 그대로)를 띠 테 안쪽으로 잘라 정수 px로.
  (double, double) _ruleOld(_Placed p) =>
      (math.max((p.cutL ? p.l : p.l - .5).roundToDouble(), _ruleLo), math.min((p.cutR ? p.r : p.r + .5).roundToDouble(), _ruleHi));

  /// 칸 하나의 가로선 두 끝(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게'): 그 칸이 그은 세로 칸 구분선의 열까지 — 왼쪽은 그 열부터 · 오른쪽은
  /// 그 열 다음까지(구분선 밖으로 1px 꼬리가 나가지 않게). 구분선이 없는 끝은: 띠 테에 닿거나 테 가까이(구분선을 띠 테가 맡는 자리 — [_floorDividers]의
  /// 건너뜀과 같은 셈)면 띠 테 바로 안쪽([_ruleLo] · [_ruleHi])까지, 그 밖(타일에 잘린 쪽 · 이웃 칸의 구분선이 맡은 자리 · 테를 두른 칸)은 옛 자리([_ruleOld]).
  /// 타일 이음매에 딱 놓인 끝(이웃 타일에 맞닿은 칸이 있음 — [_Placed.seamL] · [_Placed.seamR])은 구분선 열과 옛 자리 가운데 이음매 쪽까지: 한 타일
  /// 안이면 이웃 칸의 구분선이 [_divLast]로 건너뛰어 [_ruleCells]가 잇지만, 두 타일은 저마다 구분선을 그어(예: 1079 · 1081) 그 사이 1px이 비었다.
  (double, double) _ruleEnds(_Placed p) {
    final (oldL, oldR) = _ruleOld(p);
    final x0 = p.atL || (!p.cutL && p.l.roundToDouble() < _divLo + 2)
        ? _ruleLo
        : (!p.cutL && !p.divL.isNaN ? (p.seamL ? math.min(p.divL, oldL) : p.divL) : oldL);
    final x1 = p.atR || (!p.cutR && (p.r - 1).roundToDouble() > _divHi - 3)
        ? _ruleHi
        : (!p.cutR && !p.divR.isNaN ? (p.seamR ? math.max(p.divR + 1, oldR) : p.divR + 1) : oldR);
    return (math.max(x0, _ruleLo), math.min(x1, _ruleHi));
  }

  /// 타일 [t]의 이음매에 딱 놓인 칸([_TileCells.seamed])을 [_seamStarts] · [_seamEnds]에 적는다([beginFrame] — 그릴 타일마다).
  void _noteSeams(Tile t, Int32List seamed) {
    for (int k = 0; k < seamed.length; k++) {
      final i = seamed[k], flags = t.cellFlagsOf(i), row = t.cellRow[i], kind = t.cellKindOf(i), lane = t.cellLane[i] & 0xff;
      if (flags & Tile.clipLeft == 0 && t.cellX0[i] <= 0) _seamStarts.add((row, kind, lane, t.origin));
      if (flags & Tile.clipRight == 0 && t.cellX1[i] >= t.span) _seamEnds.add((row, kind, lane, t.origin + t.span));
    }
  }

  /// 칸 [i]의 잘리지 않은 [right]쪽 끝이 타일 이음매에 딱 놓였고, 이웃 타일에 그 이음매에서 맞닿는 같은 줄 · 종류 · 단의 칸이 있는가
  /// ([_seamStarts] · [_seamEnds]). 대개 첫 비교에서 거짓 — 이음매에 놓인 칸만 찾아본다.
  bool _seamAt(Tile t, int i, bool right) {
    final flags = t.cellFlagsOf(i);
    if (right) {
      if (flags & Tile.clipRight != 0 || t.cellX1[i] < t.span) return false;
      return _seamStarts.contains((t.cellRow[i], t.cellKindOf(i), t.cellLane[i] & 0xff, t.origin + t.span));
    }
    if (flags & Tile.clipLeft != 0 || t.cellX0[i] > 0) return false;
    return _seamEnds.contains((t.cellRow[i], t.cellKindOf(i), t.cellLane[i] & 0xff, t.origin));
  }

  /// 칸 하나가 놓인 자리의 가로선 조각(윗선 · 아랫선 — [x0, x1)), 밝기는 띠의 밝기([_ruleDim] — 조명 경계에서 끊음). 빌린 칸은 층 윗줄에 제 윗변
  /// 파선([_borrowedTop])이 있어 그 줄을 '긋지 않는 자리'로 둔다(옛 자리와 이 조각을 모두 덮게) — 첫 층 아래의 층에서는 그 줄이 곧 윗선 줄이라 파선만
  /// 남는다(첫 층의 윗선은 색줄 아랫변의 금 줄이라 파선과 겹치지 않아 그대로).
  void _ruleCell(int band, _Placed p, double x0, double x1) {
    if (x1 - x0 < .5) return;
    _rulePiece(band, _ruleTop, x0, x1, _ruleDim);
    if (!_ruleBottom.isNaN) _rulePiece(band, _ruleBottom, x0, x1, _ruleDim);
    if (p.borrowed) {
      final (oldL, oldR) = _ruleOld(p);
      _rules.exclude(band, _ruleFloor, math.min(x0, oldL), math.max(x1, oldR));
    }
  }

  void _rulePiece(int band, double y, double x0, double x1, _Dim dim) {
    if (dim.even) {
      _rules.add(band, y, x0, x1, dim.at((x0 + x1) / 2));
      return;
    }
    final cuts = _cuts..clear();
    dim.cutsInto(cuts, x0, x1);
    cuts.sort();
    var at = x0;
    for (int i = 0; i <= cuts.length; i++) {
      final next = i == cuts.length ? x1 : math.min(math.max(cuts[i].roundToDouble(), at), x1);
      if (next - at < .5) continue;
      _rules.add(band, y, at, next, dim.at((at + next) / 2));
      at = next;
    }
  }

  /// 두 단 띠의 조각을 그리는 동안([_paintPieces]) 그은 칸 금(열 · 위 · 아래 — 화면 px). 조각을 그리지 않는 동안은 null.
  List<(double, double, double)>? _pieceDivs;
  final _pieceDivsBuf = <(double, double, double)>[];

  /// 두 단 띠 하나의 칸 금이 설 자리 전부(그리기 전에 모음 — [_paintPieces]). 섭정 밑줄 · 주장 빗금이 비킨다(걸음 3).
  final _pieceCols = <(double, double, double)>[];

  /// 두 단 띠의 칸 금(다듬기 판 `themes/g-legit2.js` paintCells ③): 칸의 진짜 시작 · 끝에서 그 조각 안 제 자리(층 전체 · 제 단)에만, 위아래 가로 금
  /// (층 윗선 · 단 금 · 다음 층 윗선)에 딱 닿게 — 들임 없이 [top](= 층 · 단 윗선 + 1)부터 [b](다음 가로 금)까지. 열은 칸 경계의 화소 열(round(x)) —
  /// 같은 경계의 금(앞 칸 끝 · 뒤 칸 시작 · 다른 단)은 한 열에서 만나고, 이미 그은 금이 덮는 자리는 다시 긋지 않는다(층 전체 조각을 먼저 그림).
  /// 이음매(다른 조각으로 이어지는 쪽) · 타일에 잘린 쪽 · 층의 두 끝 가까이(띠 테가 곧 경계)는 긋지 않는다. 미정 시작 · 이어진 쪽은 2/2 파선(보통 칸과 같음).
  /// 구분선 갈래와 합칠 때(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off면 예전 그대로): 먹은 한 단 띠의 칸 금과 같은 셈(꼴 b면 먹 12 —
  /// [FloorRuleLook.dividerOf]) · 그은 열은 칸에 적어 칸 층 가로선의 끝이 맞춘다([_Placed.divL] · [_Placed.divR] — 안 적으면 옛 자리로 돌아가 1px 꼬리) ·
  /// 위아래 끝은 [_pieceSpan](범위는 이미 맞닿음 — 맞닿음이면 정수 줄 · 띠 아랫변의 테 줄 앞에서 멈춤).
  void _pieceDividers(PaintContext c, double top, double b, _Dim dim, _Placed p, bool dashL) {
    final drawn = _pieceDivs!;
    final low = FloorRuleLook.dividerOf(PaintPick.rows);
    final (from, to) = _pieceSpan(top, b);
    for (final (x, skip, dash, left) in [(p.a, p.cutL, dashL, true), (p.b, p.cutR, false, false)]) {
      if (skip) continue;
      final q = x.roundToDouble();
      if (q < _divLo + 2 || q > _divHi - 3) continue;
      if (drawn.any((d) => (d.$1 - q).abs() < 1.5 && d.$2 <= from + .5 && d.$3 >= to - .5)) continue;
      c.quads.vLine(q, from, to, CanvasInk.alpha(low ?? .20, dim.at(q)), dash: dash ? 2 : 0, gap: dash ? 2 : 0, phase: from);
      drawn.add((q, from, to));
      if (left) {
        p.divL = q;
      } else {
        p.divR = q;
      }
    }
  }

  /// 두 단 띠의 칸 금이 서는 위 · 아래 끝(칸 자리 윗변 [top] = 층 · 단 윗선 + 1 · [b] = 다음 가로 금): 층 윗변에서 시작하는 자리(층 전체 · 단 0)의 위 가로
  /// 금은 층 윗선 — 몸통의 첫 층이면 머리 색줄의 아랫금(한 줄 위)이라 그만큼 올린다([_pieceLift]). 맞닿음(구분선 갈래 — 꼴 off가 아니면 [_ruleAt]이 층 전체로
  /// 정한 [_divTop] · [_divBottom]이 있음)이면 가로 금이 서는 정수 줄에 맞추고([Quads.hLine]이 줄을 내림해 긋는다 — 층 윗변이 소수 자리일 때 반 줄이 가로 금에
  /// 겹치거나 비지 않게) 띠 아랫변에 닿는 조각은 그 테 줄 앞에서 멈춘다(테 줄에 먹이 두 번 얹히지 않게). 꼴 off면 예전 그대로.
  /// [_pieceDividers](긋기)와 [_paintPieces]의 [_pieceCols](섭정 밑줄 · 주장 빗금이 비킬 자리 — 실제로 그은 범위)가 함께 쓴다.
  (double, double) _pieceSpan(double top, double b) {
    final from = (top - 1 - _pieceBase).abs() < .5 ? top - _pieceLift : top;
    if (_divTop.isNaN) return (from, b);
    return (from.floorToDouble(), math.min(b.floorToDouble(), _divBottom));
  }

  /// 조각을 그리는 띠의 지도자 층 윗변(화면 y)과, 그 층이 몸통의 첫 층이라 칸 금을 한 줄 올려 머리 색줄의 아랫금에 닿게 하는가(1 · 아니면 0).
  double _pieceBase = 0;
  double _pieceLift = 0;

  // 색 보관(장면마다 다시 셈하지 않게). 열쇠는 띠 · 칸의 제 색.
  final _edge = <int, int>{}, _edgeSoft = <int, int>{}, _divider = <int, int>{}, _zone = <int, int>{};
  final _realSoft = <int, int>{}, _realEdge = <int, int>{};
  final _looks = <int, TextLook>{};

  /// 바탕 · 테두리 색 보관 — 열쇠는 (종류 · 딱지 갈래 · 제 색 · 옅은 색 · 좁음 · 이음 · 번갈아 · 고름 · 가문).
  final _skins = <int, (int, int)>{};

  /// 타일마다 한 번 셈해 두는 것(약한 열쇠 — 타일이 버려지면 함께 버려진다).
  static final _cellsBy = Expando<_TileCells>('띠 안의 칸');

  /// 타일에 걸어 둔 셈. 지도자 표기 · 대수가 바뀌었으면 글과 폭만 비우고 나머지(무리의 경계 · 순번 · 칸 참조)는 그대로 쓴다.
  _TileCells _cellsOf(Tile t) {
    final cache = _cellsBy[t] ??= _TileCells(t);
    if (cache.labelGen != _labelGen) {
      cache.labelGen = _labelGen;
      cache.resetLabels();
    }
    return cache;
  }

  // 한 무리를 놓는 동안 다시 쓰는 목록(장면마다 새로 만들지 않는다).
  final _placed = <_Placed>[];
  int _placedCount = 0;
  final _lines = <_Ghost>[];

  /// 앞 칸과 이어 붙는가(무리 안의 차례대로) — 장면마다 새 목록을 만들지 않게 밭에 둔다.
  Uint8List _jn = Uint8List(64);

  _Placed _take(int index, double a, double b) {
    if (_placedCount == _placed.length) _placed.add(_Placed());
    final p = _placed[_placedCount++];
    p.reset(index, a, b);
    return p;
  }

  /// 한 단의 칸을 주인 띠마다 모으는 자리(띠는 한 줄에 몇 개뿐이라 곧이곧대로 찾는다).
  final _groupHost = <_Host>[];
  final _groupCells = <List<int>>[];
  int _groupCount = 0;

  /// 칸 하나를 그리는 동안만 쓰는 밝기 · 색을 끊을 자리.
  final _dim = _Dim();
  final _cuts = <double>[];

  /// 이 장면에 읽을 기간 조명이 있는가(켜져 있거나 흐르는 중) — 장면마다 한 번 가린다.
  bool _litOn = false;

  /// 한 무리를 놓는 동안 쓰는 그 띠의 조명 구간(장면마다 새 목록을 만들지 않는다).
  final _spots = <em.Spot>[];

  List<em.Spot> _spotsOn(int band) {
    final out = _spots..clear();
    for (final s in _em.spotsOf(band)) {
      if (s.glow > .004) out.add(s);
    }
    return out;
  }

  /// 한 단의 모호한 구간(구역 40 + 칸 스스로의 확실성) — 다시 쓰는 목록.
  final _spanA = <double>[], _spanB = <double>[];
  final _spanLook = <int>[];

  static int _key(int row, int kind, int lane) => row << 16 | (kind & 0xff) << 8 | (lane & 0xff);

  /// [from]~[to) 가운데 끝의 누적 최댓값이 [x]를 넘는 첫 칸(오름차순이라 이분 탐색). 그 앞은 모두 화면 왼쪽 밖이다.
  static int _firstReaching(Float32List reach, int from, int to, double x) {
    int lo = from, hi = to;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (reach[mid] > x) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// [from]~[to) 가운데 시작이 [x] 이상인 첫 칸. 그 뒤는 모두 화면 오른쪽 밖이다.
  static int _firstAfter(Float32List x0, int from, int to, double x) {
    int lo = from, hi = to;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (x0[mid] >= x) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  @override
  void beginFrame(PaintContext c) {
    // 필터 시트의 표시 값 넷을 장면마다 읽는다. 표기 · 대수는 칸의 글을 바꾸므로 달라진 때에만 보관을 비운다(setter가 [_labelGen]을 올린다).
    _byScene[c.scene] = this;
    chainMarks.clear();
    officeMarks.clear();
    _threaded.clear();
    _rings.clear();
    final marks = SceneMarks.of(c.scene);
    showAlt = marks.showAlt;
    showHouses = marks.showHouses;
    leaderLabel = marks.leaderLabel;
    leaderOrdinal = marks.leaderOrdinal;
    _hostsOf.clear();
    _joined.clear();
    _joinedMin.clear();
    _seamStarts.clear();
    _seamEnds.clear();
    // 띠 층의 beginFrame이 이 층보다 먼저다(painter.dart `_tileLayers`) — 같은 장면의 실권 밑줄을 읽는다.
    _powers = BandLayer.of(c.scene)?.powerSpans ?? const {};
    _denseDone.clear();
    _zonesOf.clear();
    _ghostsOf.clear();
    _houseOf.clear();
    _refOf.clear();
    _leaderOf.clear();
    _drawnCount = 0;
    _tagged.clear();
    _labelRight.clear();
    _floored.clear();
    // 기간 조명은 **흐르는 동안 내내** 읽는다(`_em.spotsOf`) — 끝 값(`look.spots`)만 보면 꺼지는 조명이 한 번에 사라진다.
    // 흐리지 않는 구간으로 갈라 칠하는 것만 `look.lit`에 달렸고(`_dimOf`), 눌린 칸(is-spot)은 지금 연표의 `_isSpot`처럼 메아리 체크와 무관하다.
    _litOn = _em.look.spots.isNotEmpty || _em.litMoving;
    _lensOn = c.layout.themeLens.isNotEmpty;
    _leadersOn = c.layout.conditions.leaders;
    _nominalOn = c.layout.conditions.groups && c.layout.conditions.density <= 0 && !c.layout.conditions.bird;
    final focusMarks = SceneMarks.of(c.scene);
    _groupFocus = focusMarks.groupFocus;
    _groupFocusColor = focusMarks.groupFocusColor & 0xffffff;
    _lensOf.clear();
    _echoFam = '';
    _piecesOn = false;
    _legits.clear();
    _hatchX = LegitLook.phaseX(c.v.xOf(0));
    if (c.layout.bird) return; // 조감(밀도 조감 · 자동 조감): 줄은 띠 하나뿐이라 단이 모두 사라진다(명세 05의 7.2)
    final v = c.v;
    final byId = <int, _Host>{};
    final spans = <int, (double, double)>{};
    final zoneById = <int, _Zone>{}, ghostById = <int, _Ghost>{};
    final rangeL = <int, double>{}, rangeR = <int, double>{};
    // 구역 42는 가문 강조 · 가문 조명(꺼지며 흐르는 동안 포함) · 표시 체크 '가문' · 커서가 칸 위에 있을 때(성씨 풍선)만 읽는다.
    final wantHouse = _em.look.house != null || showHouses || _em.housing || hotCell != null;
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        // 바탕 문화(look 비트 14)는 다른 띠와 겹친 채 깔리는 띠라 칸의 주인이 될 수 없다.
        if (t.bandLook[i] & (1 << 14) != 0) continue;
        final id = t.bandId[i];
        final flags = t.bandFlags[i];
        // 미정인 끝은 띠 상자가 그쪽으로 44px 스며든다(명세 5-3의 3번) — 칸을 가두는 상자도 그만큼 넓다.
        var x0 = v.xOf(origin + t.bandX0[i]), x1 = v.xOf(origin + t.bandX1[i]);
        if (flags & Tile.fuzzyStart != 0 && flags & Tile.clipLeft == 0) x0 -= Look.fuzzyFade;
        if (flags & Tile.fuzzyEnd != 0 && flags & Tile.clipRight == 0) x1 += Look.fuzzyFade;
        final had = byId[id];
        // 띠의 진짜 시작(미정 꼬리 없이) — 꼬리표 밑 사슬이 꼬리표 시작에서 비롯하는가(구멍 · 실)를 가린다.
        final start = flags & Tile.clipLeft == 0 ? v.xOf(origin + t.bandX0[i]) : double.infinity;
        if (had == null) {
          byId[id] = _Host(id, t.bandRow[i], x0, x1, t.bandColor[i])
            ..look = t.bandLook[i]
            ..sub = t.bandSub[i]
            ..startX = start
            ..fuzzyS = flags & Tile.fuzzyStart != 0 && flags & Tile.clipLeft == 0
            ..fuzzyE = flags & Tile.fuzzyEnd != 0 && flags & Tile.clipRight == 0;
        } else {
          if (start < had.startX) had.startX = start;
          if (x0 < had.x0) had.x0 = x0;
          if (x1 > had.x1) had.x1 = x1;
          // 띠의 진짜 끝을 실은 조각에서만 미정 끝을 안다(잘린 조각은 모른다).
          if (flags & Tile.fuzzyStart != 0 && flags & Tile.clipLeft == 0) had.fuzzyS = true;
          if (flags & Tile.fuzzyEnd != 0 && flags & Tile.clipRight == 0) had.fuzzyE = true;
        }
      }
      // 잘리지 않은 칸은 한 타일 안에 온전히 있다 — 잘린 칸만 타일이 미리 짚어 둔 목록에서 본다.
      final tileCells = _cellsOf(t), clipped = tileCells.clipped;
      for (int k = 0; k < clipped.length; k++) {
        final i = clipped[k];
        final id = t.cellId[i];
        final x0 = v.xOf(origin + t.cellX0[i]), x1 = v.xOf(origin + t.cellX1[i]);
        final had = spans[id];
        spans[id] = had == null ? (x0, x1) : (math.min(had.$1, x0), math.max(had.$2, x1));
        if (_powers.isNotEmpty) {
          final m0 = origin + t.cellX0[i], m1 = origin + t.cellX1[i], hadMin = _joinedMin[id];
          _joinedMin[id] = hadMin == null ? (m0, m1) : (math.min(hadMin.$1, m0), math.max(hadMin.$2, m1));
        }
      }
      _noteSeams(t, tileCells.seamed);
      _readItems(c, t, origin, zoneById, ghostById, wantHouse);
      // 칸의 정통성(구역 57 — 칸 그림 갈래 걸음 3): 스위치 legit일 때만 · 구역이 없는 타일은 빈 표.
      if (PaintPick.legit) _legits.addAll(_legitsOf(t));
      // 띠의 두 끝은 연대 폭(구역 19)까지 품는다(띠 층과 같은 끝) — 조명 칠을 띠 모양으로 자를 때만 쓴다(칸을 가두는 상자는 그대로).
      if (_litOn) {
        final zones = t.section(19);
        if (zones.count > 0) {
          final ref = zones.u(Tile.itemRef), side = zones.u(Tile.itemA), zoneFlags = zones.u(Tile.itemFlags);
          final za = zones.f(Tile.itemX0), zb = zones.f(Tile.itemX1);
          for (int i = 0; i < zones.count; i++) {
            final id = ref[i];
            if (id == 0) continue;
            if (side[i] == 0 && zoneFlags[i] & 1 == 0) {
              final x = v.xOf(origin + za[i]);
              if (x < (rangeL[id] ?? double.infinity)) rangeL[id] = x;
            }
            if (side[i] == 1) {
              final x = v.xOf(origin + zb[i]);
              if (x > (rangeR[id] ?? double.negativeInfinity)) rangeR[id] = x;
            }
          }
        }
      }
    }
    _joined.addAll(spans);
    _echoFam = _echoFamOf(hotCell);
    for (final h in byId.values) {
      (_hostsOf[h.row] ??= []).add(h);
      final l = rangeL[h.id], r = rangeR[h.id];
      h.shapeL = math.min(h.x0, l == null ? double.infinity : l - (h.fuzzyS ? Look.fuzzyFade : 0));
      h.shapeR = math.max(h.x1, r == null ? double.negativeInfinity : r + (h.fuzzyE ? Look.fuzzyFade : 0));
    }
    for (final list in _hostsOf.values) {
      list.sort((a, b) => a.x0.compareTo(b.x0));
    }
    _countLeaders(c);
    _scanChains(c);
    _scanPieces(c);
    _scanRegents(c);
    for (final list in _zonesOf.values) {
      list.sort((a, b) => a.a.compareTo(b.a));
    }
    for (final list in _ghostsOf.values) {
      list.sort((a, b) => a.x.compareTo(b.x));
    }
  }

  /// 띠마다 화면 안에 드는 지도자 · 내각 칸을 센다 — 타일을 모두 돌며 칸 번호로 한 번씩(타일에 걸친 칸은 두 타일에 실린다).
  /// 칸 상자 [lo, hi]는 [_paintGroup]과 같은 셈(웹 `_cells`의 `seen`: 끝이 왼쪽 여백 안 · 시작이 오른쪽 여백 안).
  void _countLeaders(PaintContext c) {
    final v = c.v;
    final seen = <int>{};
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.cellCount; i++) {
        final kind = t.cellKindOf(i);
        if (kind != CellKind.leader && kind != CellKind.cabinet && kind != Schema4.cellOfficeMore) continue;
        final hosts = _hostsOf[t.cellRow[i]];
        if (hosts == null || !seen.add(t.cellId[i])) continue;
        final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
        final host = _hostAt(hosts, (a + b) / 2);
        if (host == null) continue;
        final boxL = math.max(host.x0, c.left - 1), boxR = math.max(boxL + 3, math.min(host.x1, c.w + 1));
        if (b <= boxL + 1 + _pad2 || a >= boxR - 1 - _pad2) continue;
        // 섭정 칸은 층을 세우지 않는다(칸 그림 갈래 걸음 3 — 그 기간 피후견 칸의 밑줄) — 빽빽한 칸의 수에도 들지 않는다.
        if (_isRegent(host.id, kind, t.cellLane[i] & 0xff, CellStyle.seqOf(t.cellStyle[i]))) continue;
        if (kind == CellKind.leader) {
          host.leaders++;
          final lane = t.cellLane[i] & 0xff;
          if (lane > 0) (host.leaderUpper ??= Int32List(4))[math.min(lane, 3)]++;
        } else if (kind == CellKind.cabinet) {
          host.cabinets++;
        } else {
          // 직위 줄 더(종류 9 — 서고 미리보기 `_cells`의 'office'도 같은 is-dense): 줄(lane)마다 센다.
          final lane = t.cellLane[i] & 0xff, by = host.offices ??= <int, int>{};
          by[lane] = (by[lane] ?? 0) + 1;
        }
      }
    }
  }

  /// 단(종류 · 단 번호)이 그 줄의 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나)이면 사슬 차례 — 0 왕조 · 1 지위 자리(렌즈가 지위 자리로 내린 지도자 칸 포함). 아니면 −1.
  int _chainSlotOf(RowGeo geo, int kind, int lane) => chainSlotOf(geo, kind, lane, lensRank: _lensOn && _leadersOn);

  /// [_chainSlotOf]의 몸 — [lensRank]는 렌즈를 켰고 표시 '지도자'가 켜졌는가(렌즈가 지도자 칸을 지위 단 자리로 내림). 관계선 층이 띠 밑 단의
  /// 가로 구간을 모을 때(links.dart `_collectLower` — 내림줄이 사슬 종이 뒤로 끊기지 않게)도 같은 셈을 쓴다. 단 1의 렌즈 칸은 갈래가
  /// [CellStyle.lensLeader](내린 지도자 칸)인 것만 사슬에 선다([_scanChains]).
  static int chainSlotOf(RowGeo geo, int kind, int lane, {required bool lensRank}) {
    if (geo.chainTop < 0) return -1;
    if (kind == CellKind.dynasty) return geo.dynastyChained ? 0 : -1;
    if (kind == CellKind.rank) return geo.rankChained ? 1 : -1;
    if (kind == CellKind.common && lane == 1) return geo.rankChained && lensRank ? 1 : -1;
    return -1;
  }

  /// 꼬리표 밑 흰 사슬의 칸을 띠마다 미리 훑는다(차례 걸음 15): 사슬마다 첫 칸의 시작(꼬리표 시작에서 비롯하면 구멍 · 실)과 칸들의 두 끝
  /// (타일을 건너 맞닿은 칸을 한 종이로 잇게 — 칸은 타일마다 따로 그려진다). 타일에 잘린 쪽의 끝은 적지 않는다(진짜 끝이 아니다).
  void _scanChains(PaintContext c) {
    final layout = c.layout, v = c.v;
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      final cache = _cellsOf(t);
      for (int run = 0; run < cache.runCount; run++) {
        final row = cache.runRow[run];
        if (row >= layout.rowCount || !layout.hasBody(row)) continue;
        final first = cache.runAt[run], last = cache.runAt[run + 1];
        final slot = _chainSlotOf(layout.geo(row), t.cellKindOf(first), t.cellLane[first] & 0xff);
        if (slot < 0) continue;
        final hosts = _hostsOf[row];
        if (hosts == null || hosts.isEmpty) continue;
        for (int i = first; i < last; i++) {
          if (t.cellKindOf(i) == CellKind.common && CellStyle.bandOf(t.cellStyle[i]) != CellStyle.lensLeader) continue;
          final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
          final host = _hostAt(hosts, (a + b) / 2);
          if (host == null) continue;
          final flags = t.cellFlagsOf(i), span = host.chainOf(slot);
          if (flags & Tile.clipLeft == 0) {
            span.starts.add(a);
            if (a < span.first) span.first = a;
          }
          if (flags & Tile.clipRight == 0) span.ends.add(b);
        }
      }
    }
  }

  /// [xs] 가운데 [x]에서 1.5px 안의 것이 있는가(사슬의 맞닿은 칸).
  static bool _touches(List<double> xs, double x) {
    for (final e in xs) {
      if ((e - x).abs() < 1.5) return true;
    }
    return false;
  }

  // ──────────── 두 단 지도자 층(정통성 넷 가 다듬은 꼴 lg2-ga · 칸 그림 갈래 걸음 2 — 다듬기 판 `themes/g-legit2.js` paintCells) ────────────
  // 지도자 층이 두 단 이상인 줄(layout.dart `RowGeo.leaderLanes` — 줄 fig_wide 26 ~ 27 · 스위치 legit)에서 제 단 수(띠 sub 22 ~ 23 + 1)도 둘 이상인 띠는
  // 그 띠의 지도자 칸(모든 단)을 칸 경계로 끊은 **조각**으로 그린다: 혼자인 조각은 층 전체(단 수 × 14), 겹친 조각만 제 단 14(칸 종류 1의 lane).
  // 겹친 조각에는 단 사이 금(먹 25 · 양 끝 세로 금 화소까지). 칸 금은 칸의 시작 · 끝에서 그 조각 안 제 자리에만 · 위아래 가로 금에 닿게([_pieceDividers]).
  // 이름은 칸이 시작하는 조각부터 이름과 여백이 드는 첫 조각의 제 자리 가운데([_measure]). 칸 층의 다른 꼴(고름 · 강조 · 조명 · 실권 · 빌림 · 가문 ·
  // 이설 · 미정 끝 · 누름 자리 · 이름 비키기)은 조각을 '이음매 세로 테 없는 잘린 칸'으로 지금 길([_paintPlaced])에 넘겨 그대로 따른다.
  // 섭정 칸(구역 57 — 후보가 아님)은 조각의 경계를 만들지 않고 겹침 수에도 들지 않으며, 칸으로 그리지 않는다 — 그 기간 피후견 조각의 제 자리 아랫변 안쪽
  // 2px 밑줄(걸음 3 — [_pieceRegents] · [_regentLines]). 한 단 띠 · 한 단 줄(옛 저장소 · 렌즈 · 스위치 끔)은 지금 길 그대로다.

  /// 이번 장면에 조각으로 그리는 두 단 띠가 있는가([_scanPieces]).
  bool _piecesOn = false;

  /// 장면마다 두 단 띠의 지도자 칸을 미리 훑는다(메움 타일은 빼고 — [_scanChains]와 같음): 칸마다 타일을 건너 합친 좌우 · 진짜 시작 · 끝(타일에 잘린 쪽은
  /// 진짜 끝이 아니다) · 섭정인가(구역 57의 정통성 — 장면의 표 [_legits])를 모으고, 후보 칸(섭정이 아닌 칸)의 진짜 시작 · 끝을 띠의 조각 경계로 둔다([_BandPieces]).
  void _scanPieces(PaintContext c) {
    final layout = c.layout, v = c.v;
    final found = <_Host>{};
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      final cache = _cellsOf(t);
      for (int run = 0; run < cache.runCount; run++) {
        final first = cache.runAt[run];
        if (t.cellKindOf(first) != CellKind.leader) continue;
        final row = cache.runRow[run];
        if (row >= layout.rowCount || !layout.hasBody(row)) continue;
        final geo = layout.geo(row);
        if (geo.leaderLanes < 2 || geo.leaderTop < 0) continue;
        final hosts = _hostsOf[row];
        if (hosts == null || hosts.isEmpty) continue;
        final last = cache.runAt[run + 1];
        for (int i = first; i < last; i++) {
          final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
          final host = _hostAt(hosts, (a + b) / 2);
          if (host == null) continue;
          final own = math.min(Schema4.leaderLanesOf(host.sub), geo.leaderLanes);
          if (own < 2) continue;
          final cell = (host.pieces ??= _BandPieces(own)).cells[t.cellId[i]] ??= _PieceCell(cache.seq[i], t.cellLane[i] & 0xff);
          if (a < cell.l) cell.l = a;
          if (b > cell.r) cell.r = b;
          final flags = t.cellFlagsOf(i);
          if (flags & Tile.clipLeft == 0) cell.start = a;
          if (flags & Tile.clipRight == 0) cell.end = b;
          found.add(host);
        }
      }
    }
    for (final host in found) {
      final bp = host.pieces!;
      final xs = <double>[];
      for (final cell in bp.cells.values) {
        cell.regent = _isRegent(host.id, CellKind.leader, cell.lane, cell.seq);
        if (cell.regent) continue;
        if (cell.start != null) xs.add(cell.start!);
        if (cell.end != null) xs.add(cell.end!);
      }
      xs.sort();
      for (final x in xs) {
        if (bp.bounds.isEmpty || x - bp.bounds.last >= .5) bp.bounds.add(x);
      }
    }
    _piecesOn = found.isNotEmpty;
  }

  /// 두 단 띠(조각으로 그리는 띠 — [_scanPieces])의 지도자 칸(순번 [seq])이 [x](화면 px)에서 차지한 세로 자리(화면 y — 위 가로 금 · 아래 가로 금):
  /// 그 자리의 조각이 혼자면 층 전체(층 윗선 ~ 층 윗선 + 제 단 수 × 14), 겹쳤으면 제 단(층 윗선 + 단 × 14 ~ 그 + 14) — [_paintPieces]가 그 조각을 그리는 자리.
  /// 두 단 띠가 아니거나(한 단 띠 · 한 단 줄 · 스위치 `legit` 끔) 그 칸 · 조각을 모르면 null(부르는 쪽이 한 단 자리를 쓴다).
  /// 동군연합 이음줄(paint/unions.dart)이 칸의 아랫변 · 윗변으로 쓴다 — 이 층의 [beginFrame] 뒤에만 뜻이 있다(painter.dart `_tileLayers`에서 이 층이 앞).
  (double, double)? leaderSlotAt(PaintContext c, int row, int band, int seq, double x) {
    if (!_piecesOn || seq < 0) return null;
    final hosts = _hostsOf[row];
    if (hosts == null) return null;
    for (final host in hosts) {
      final bp = host.pieces;
      if (host.id != band || bp == null) continue;
      for (final cell in bp.cells.values) {
        if (cell.seq != seq || x < cell.l - .5 || x > cell.r + .5) continue;
        final layout = c.layout, geo = layout.geo(row);
        final base = c.v.yOf(layout.rowTop(row) + TagLook.compactOf(geo, host.look, geo.leaderTop, sub: host.sub));
        for (final (l, r, alone) in bp.piecesOf(cell)) {
          if (x < l - .5 || x > r + .5) continue;
          if (alone) return (base, base + bp.lanes * G.floor);
          final lane = math.min(cell.lane, bp.lanes - 1);
          return (base + lane * G.floor, base + (lane + 1) * G.floor);
        }
      }
    }
    return null;
  }

  /// 조각을 그리는 동안 다시 쓰는 것: 무리마다의 띠 · 칸 · 조각 초안 · 겹친 조각의 단 사이 금 자리.
  final _pieceHost = <_Host>[];
  final _pieceCells = <List<int>>[];
  final _pieceDrafts = <_PieceDraft>[];
  final _laneSpans = <List<double>>[];

  /// 빽빽한 칸 셈에 쓰는 단마다의 보이는 칸 수(단 0 ~ 3 — [_paintPieces]).
  final _seenLanes = Int32List(4);

  /// 이름 비키기([_labelRight])의 열쇠에 더하는 값 — 두 단 띠의 층 전체 조각(0x80)과 제 단 조각(0x40)은 서로 · 한 단 띠(0)와 따로 센다.
  /// 조각은 줄의 지도자 무리를 한 번에 그리고 같은 줄의 한 단 띠는 그 뒤에 그리므로(그리는 차례가 x 차례가 아니다), 열쇠가 섞이면 오른쪽 두 단 띠의
  /// 이름 끝이 왼쪽 한 단 띠의 이름을 막는다. 띠끼리는 x가 겹치지 않아 따로 세어도 이름이 겹치지 않는다.
  int _slotBits = 0;

  /// 두 단 줄(지도자 층이 두 단 이상 — [RowGeo.leaderLanes])의 지도자 무리들: 그 줄의 지도자 단 무리(단 0 · 1 …)를 모두 모아 두 단 띠([_Host.pieces])의
  /// 칸을 조각으로 그린다([_paintPieces]). 돌려주는 값은 그 줄 지도자 무리들의 끝(다음 무리 번호) — 두 단 줄의 지도자 무리가 아니면 [run] 그대로.
  /// 같은 무리들의 한 단 띠 칸은 부르는 쪽([paintTile])이 무리마다 지금 길([_paintLane] — 두 단 띠의 칸은 건너뜀)로 그린다.
  int _paintPieceRuns(PaintContext c, Tile t, _TileCells cache, int run) {
    if (!_piecesOn) return run;
    final firstCell = cache.runAt[run];
    if (t.cellKindOf(firstCell) != CellKind.leader) return run;
    final row = cache.runRow[run], layout = c.layout;
    if (row >= layout.rowCount || !layout.hasBody(row)) return run;
    final geo = layout.geo(row);
    if (geo.leaderLanes < 2 || geo.leaderTop < 0) return run;
    var end = run + 1;
    while (end < cache.runCount && cache.runRow[end] == row && t.cellKindOf(cache.runAt[end]) == CellKind.leader) {
      end++;
    }
    final hosts = _hostsOf[row];
    if (hosts == null || hosts.isEmpty) return end;
    final v = c.v, origin = t.origin.toDouble();
    var groups = 0;
    for (int k = run; k < end; k++) {
      final first = cache.runAt[k], last = cache.runAt[k + 1];
      final from = _firstReaching(cache.reach, first, last, (c.left - 2 - v.left) / v.ppm + v.lo - origin);
      final to = _firstAfter(t.cellX0, from, last, (c.w + 2 - v.left) / v.ppm + v.lo - origin);
      for (int i = from; i < to; i++) {
        final host = _hostAt(hosts, (v.xOf(origin + t.cellX0[i]) + v.xOf(origin + t.cellX1[i])) / 2);
        if (host == null || host.pieces == null) continue;
        int g = 0;
        while (g < groups && !identical(_pieceHost[g], host)) {
          g++;
        }
        if (g == groups) {
          if (g == _pieceCells.length) {
            _pieceHost.add(host);
            _pieceCells.add(<int>[]);
          } else {
            _pieceHost[g] = host;
            _pieceCells[g].clear();
          }
          groups++;
        }
        _pieceCells[g].add(i);
      }
    }
    for (int g = 0; g < groups; g++) {
      _paintPieces(c, t, cache, _pieceHost[g], row, geo, _pieceCells[g]);
    }
    return end;
  }

  /// 두 단 띠 하나의 지도자 칸([cells] — 이 타일의 모든 단)을 조각으로 그린다. 조각은 (층 전체 · 제 단) × 칸의 단마다 한 무리로 모아 지금 칸 길([_paintPlaced])에
  /// 넘기고(층 전체 무리를 먼저 — 칸 금이 겹치지 않게), 끝에 겹친 조각마다 단 사이 금을 긋는다.
  void _paintPieces(PaintContext c, Tile t, _TileCells cache, _Host host, int row, RowGeo geo, List<int> cells) {
    final bp = host.pieces!, own = bp.lanes, layout = c.layout, v = c.v, origin = t.origin.toDouble();
    // 지도자 층의 윗선(제 몸통에 맞붙인 자리 — bands.dart TagLook.compactOf) · 층 전체 높이(제 단 수 × 14).
    final base = v.yOf(layout.rowTop(row) + TagLook.compactOf(geo, host.look, geo.leaderTop, sub: host.sub));
    final depth = own * G.floor;
    if (!c.rowOnScreen(row, base, depth)) return;
    final boxL = math.max(host.x0, c.left - 1), boxR = math.max(math.max(host.x0, c.left - 1) + 3, math.min(host.x1, c.w + 1));
    final clipL = host.x0 < c.left - 1, clipR = host.x1 > c.w + 1;
    final lo = boxL + 1, hi = boxR - 1;
    if (hi - lo < 1) return;
    final alpha = _em.bandAlpha(host.id, row);
    final hostSpots = _litOn ? _spotsOn(host.id) : const <em.Spot>[];
    // 빽빽한 칸(지도자가 한 칸에 6px도 못 되면 층 전체를 한 칸으로 — [_paintGroup]의 (1) · (2)와 같은 셈 · 띠 하나에 한 번): 이 타일의 보이는 칸
    // (칸 상자 lo ~ hi에 걸친 것)을 단마다 세어 — [_paintGroup]은 단마다 한 무리라 그 무리의 칸 수 — 가장 많은 단과 화면 안 그 띠의 단마다 센 지도자 칸
    // ([_countLeaders] · [_Host.leaderLaneMax] — 서고 미리보기 `_cells`가 단마다 `seen`) 가운데 큰 값. 섭정 칸은 세지 않는다.
    // 보이는 칸이 없으면 그리지 않는다(다른 타일이 그린다 — [_paintGroup]의 `_placedCount == 0`).
    final perLane = _seenLanes..fillRange(0, 4, 0);
    for (final i in cells) {
      final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
      if (b <= lo || a >= hi) continue;
      if (_isRegent(host.id, CellKind.leader, 0, cache.seq[i])) continue; // 섭정 칸은 층을 세우지 않는다(걸음 3 — 밑줄)
      perLane[math.min(t.cellLane[i] & 0xff, 3)]++;
    }
    final seen = perLane.reduce(math.max);
    if (seen == 0) return;
    final count = math.max(seen, host.leaderLaneMax);
    if (count > 1 && (boxR - boxL - 2 - 2 * _pad2) / count < 6) {
      if (_denseDone.add(host.id * 16 + CellKind.leader)) _dense(c, host, lo, hi, base + 1, depth - 1, alpha, CellKind.leader, -1);
      return;
    }

    // (1) 조각 초안 — 칸마다 그 칸의 조각([_BandPieces.piecesOf])을 이 타일의 칸 조각으로 자른다.
    final drafts = _pieceDrafts..clear();
    for (final i in cells) {
      var a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
      if (b <= lo || a >= hi) continue;
      if (_isRegent(host.id, CellKind.leader, 0, cache.seq[i])) continue; // 섭정 칸 — 피후견 조각의 밑줄로만([_pieceRegents])
      final flags = t.cellFlagsOf(i), cutL = flags & Tile.clipLeft != 0, cutR = flags & Tile.clipRight != 0;
      if (cutL) a = a.roundToDouble(); // 이음매는 양쪽 조각이 같은 정수 px에서 만나게
      if (cutR) b = b.roundToDouble();
      // 메움 타일(훑지 않음)의 칸은 이 조각 하나를 칸으로 본다.
      final cell = bp.cells[t.cellId[i]] ??
          (_PieceCell(cache.seq[i], t.cellLane[i] & 0xff)
            ..l = a
            ..r = b
            ..start = cutL ? null : a
            ..end = cutR ? null : b);
      final cellW = math.min(cell.r, hi) - math.max(cell.l, lo);
      for (final (pl, pr, alone) in bp.piecesOf(cell)) {
        if (pr <= a + .25 || pl >= b - .25) continue;
        // 조각이 이 타일 조각 안에서 시작 · 끝나는가 — 아니면 그쪽은 타일 경계(잘린 쪽). 칸 안의 경계에서 시작 · 끝나면 이음매(세로 테 없음 · 정수 px).
        final inL = pl >= a - .25, inR = pr <= b + .25;
        final seamL = pl > cell.l + .25, seamR = pr < cell.r - .25;
        drafts.add(_PieceDraft(
          index: i,
          a: inL && seamL ? pl.roundToDouble() : a,
          b: inR && seamR ? pr.roundToDouble() : b,
          cutL: !inL || seamL || cutL,
          cutR: !inR || seamR || cutR,
          tileL: !inL || (!seamL && cutL),
          wholeL: pl,
          wholeR: pr,
          cellW: cellW,
          cell: cell,
          full: alone,
        ));
      }
    }
    if (drafts.isEmpty) return;

    // (2) 무리마다 지금 칸 길로 — 층 전체 조각(칸의 단마다)을 먼저, 그다음 제 단 조각. 한 무리 안은 칸의 단이 하나라 타일 차례(시작 순)대로다.
    final spots = hostSpots;
    _pieceDivs = _pieceDivsBuf..clear();
    _divLast = double.negativeInfinity;
    _divLo = lo;
    _divHi = hi;
    // 칸 금이 위 가로 금에 닿게: 지도자 층이 이 띠 몸통의 첫 층이면 그 위 가로 금은 머리 색줄의 아랫금(층 윗변 − 1 — bands.dart `_paintTwoPiece`의 bt).
    _pieceBase = base;
    _pieceLift = base <= v.yOf(layout.rowTop(row) + geo.bodyTop) + .5 ? 1 : 0;
    // 칸 층 사이 흐린 가로선(구분선 갈래 — 감독 지적 · 결정 2026-10-25)의 층 자리: 층 전체(층 윗선 [base] · 제 단 수 × 14) 기준으로 한 번 — 조각 무리마다
    // 층 윗선 · 아랫선을 칸 자리만큼 모으고([_paintPlaced]의 [_ruleCells] — 같은 줄의 겹친 조각은 [FloorRules]가 합쳐 한 번), 단 사이 금은 [_laneLines]가 긋는다.
    // 칸 금의 맞닿는 위 · 아래 끝([_divTop] · [_divBottom] — [_pieceSpan])도 여기서 정해진다. 꼴 off면 모두 NaN(예전 그대로).
    _ruleAt(c, row, base, depth, lo, hi, host, hostSpots);
    // 칸 금이 설 열 전부(조각마다 칸의 진짜 시작 · 끝 — [_pieceDividers]와 같은 셈)를 미리 모은다: 무늬(섭정 밑줄 · 주장 빗금 — 걸음 3)가 그리는 차례
    // (층 전체 조각 먼저)와 상관없이 뒤에 그을 금의 화소까지 비킨다.
    final cols = _pieceCols..clear();
    for (final d in drafts) {
      final slot = d.full ? base : base + math.min(d.cell.lane, own - 1) * G.floor;
      final (from, to) = _pieceSpan(slot + 1, slot + (d.full ? depth : G.floor));
      for (final (x, cut) in [(d.a, d.cutL), (d.b, d.cutR)]) {
        final q = x.roundToDouble();
        if (!cut && q >= lo + 2 && q <= hi - 3) cols.add((q, from, to));
      }
    }
    try {
      for (final full in const [true, false]) {
        for (int lane = 0; lane < 4; lane++) {
          _placedCount = 0;
          for (final d in drafts) {
            if (d.full != full || d.cell.lane != lane) continue;
            final p = _take(d.index, d.a, d.b)
              ..cutL = d.cutL
              ..cutR = d.cutR
              ..tileL = d.tileL
              ..wholeL = d.wholeL
              ..wholeR = d.wholeR
              ..cell = d.cell
              ..cellW = d.cellW;
            // 잘리지 않은 끝(칸의 진짜 시작 · 끝)이 타일 이음매에 딱 놓여 이웃 타일의 칸과 맞닿음(칸 층 가로선 — [_ruleEnds] · 한 단 띠의 [_paintGroup]과 같은 셈).
            // 조각의 이음매 · 잘린 쪽은 칸의 끝이 아니라 묻지 않는다.
            p.seamL = !d.cutL && _seamAt(t, d.index, false);
            p.seamR = !d.cutR && _seamAt(t, d.index, true);
            _pieceRegents(host, bp, d, p);
          }
          if (_placedCount == 0) continue;
          final top = full ? base : base + math.min(lane, own - 1) * G.floor, height = full ? depth : G.floor;
          _slotBits = full ? 0x80 : 0x40;
          _paintPlaced(c, t, cache, host, row, CellKind.leader, lane, lo, hi, clipL, clipR, top + 1, height - 1, alpha, hostSpots, spots, 1);
        }
      }
      // (3) 단 사이 금 — 겹친 조각마다(그 조각을 나눠 쓰는 칸들의 칸 조각을 합친 이 타일의 몫) · 먹 25 · 양 끝 세로 금 화소까지(다듬기 판 paintCells ②).
      _laneLines(c, t, drafts, base, own, lo, hi, alpha * _em.trimDim);
    } finally {
      _pieceDivs = null;
      _slotBits = 0;
      _ruleTop = _ruleBottom = _divTop = _divBottom = double.nan;
    }
  }

  /// 겹친 조각의 단 사이 금: 단 j(1 ~)의 윗선(지도자 층 윗선 + j × 14)에 조각의 왼쪽 경계 열부터 오른쪽 경계 열까지(둘 다 넣음 — 세로 금과 모서리가 맞물림).
  /// 조각이 타일 경계를 넘으면 그쪽은 타일 경계의 정수 px에서 끊는다(이웃 타일이 이어 긋는다). 끝 열에 이 줄을 지나는 세로 금(층 전체 칸 금)이 이미 있으면
  /// 그 화소는 비운다(겹쳐 짙어지지 않게).
  void _laneLines(PaintContext c, Tile t, List<_PieceDraft> drafts, double base, int own, double lo, double hi, double alpha) {
    final spans = _laneSpans..clear();
    for (final d in drafts) {
      if (d.full) continue;
      List<double>? hit;
      for (final s in spans) {
        if ((s[0] - d.wholeL).abs() < .25) hit = s;
      }
      if (hit == null) {
        spans.add([d.wholeL, d.wholeR]);
      } else if (d.wholeR > hit[1]) {
        hit[1] = d.wholeR;
      }
    }
    if (spans.isEmpty) return;
    // 맞닿은 겹친 조각(셋 이상 겹친 띠 — 경계마다 끊김)은 한 줄로 이어 긋는다(경계 열을 두 번 칠해 짙어지지 않게).
    spans.sort((a, b) => a[0].compareTo(b[0]));
    var k = 0;
    for (int i = 1; i < spans.length; i++) {
      if ((spans[i][0] - spans[k][1]).abs() < .25) {
        if (spans[i][1] > spans[k][1]) spans[k][1] = spans[i][1];
      } else {
        spans[++k] = spans[i];
      }
    }
    spans.length = k + 1;
    final v = c.v, tl = v.xOf(t.origin.toDouble()), tr = v.xOf(t.origin.toDouble() + t.span);
    // 구분선 갈래와 합칠 때(감독 결정 2026-10-25 '가로 · 세로 모두 먹 12' · '모든 가로세로 구분선은 맞닿게' — 꼴 off면 예전 그대로): 먹은 칸 금과 같은 셈
    // (꼴 b면 먹 12 — [FloorRuleLook.dividerOf]) · 왼쪽 끝은 칸 층 가로선의 [_ruleLo]와 같은 셈(띠 왼쪽 테는 floor 열이라 그 바로 다음 열부터 — ceil이면 소수
    // 자리에서 테 옆 1열이 비었다). 오른쪽 floor(hi)는 이미 테 열 바로 앞이다.
    final joint = PaintPick.rows != FloorRule.off;
    final ink = CanvasInk.alpha(FloorRuleLook.dividerOf(PaintPick.rows) ?? .20, alpha);
    final drawn = _pieceDivs ?? const <(double, double, double)>[];
    bool crossed(double col, double y) => drawn.any((d) => (d.$1 - col).abs() < .5 && d.$2 < y - .5 && d.$3 > y + 1.5);
    for (final s in spans) {
      var a = s[0] >= tl - .25 ? s[0].roundToDouble() : tl.roundToDouble();
      var z = s[1] <= tr + .25 ? s[1].roundToDouble() + 1 : tr.roundToDouble();
      a = math.max(a, joint ? (lo - 1).floorToDouble() + 1 : lo.ceilToDouble());
      z = math.min(z, hi.floorToDouble());
      for (int j = 1; j < own; j++) {
        final y = (base + j * G.floor).floorToDouble();
        var from = a, to = z;
        if (crossed(from, y)) from += 1;
        if (crossed(to - 1, y)) to -= 1;
        if (to - from < .5) continue;
        c.quads.hLine(from, to, y, ink);
        c.stats.shapes++;
        c.debug?.note('단금', '$j ${_r1(from)},${_r1(y)},${_r1(to - from)}');
      }
    }
  }

  // ──────────── 칸의 정통성 무늬(정통성 넷 가 다듬은 꼴 lg2-ga · 칸 그림 갈래 걸음 3 — 다듬기 판 `themes/g-legit2.js` paintCells ① ④ ⑤) ────────────
  // 구역 57(칸의 정통성 — 띠 · 칸 종류 · 순번(칸 style 15 ~ 26)으로 칸과 짝)을 장면마다 한 표([_legits])로 모아 두 길(한 단 띠 [_paintGroup] · 두 단 띠의 조각
  // [_paintPieces])이 함께 읽는다. 지도자 · 내각 · 직위 줄 더(종류 9 — 걸음 4가 층을 그리면 따라옴)의 칸이 같은 문법이다:
  //   · 섭정 — 층을 세우지 않는다: 칸 칠 · 금 · 이름을 그리지 않고 그 기간 피후견 칸(그 기간을 품은 칸 · 없으면 처음 겹친 칸 — 두 단 띠는 조각마다)의
  //     제 자리 아랫변 안쪽에 2px 먹 60(칸 금 오른쪽 화소부터 · [_regentLines]). 누름은 밑줄 자리 둘레에서 섭정 칸 창(누름 기록 — 그 칸의 참조).
  //   · 명목 — 이름 먹 45(옛 명목 지도자 29비트의 .5와 함께면 옅은 쪽 — [_drawCell]).
  //   · 주장 — 칸 바탕에만 1px 화소 빗금(먹 25 · 5px 계단 — [LegitLook.hatch]) · 이름 앞 4 ~ 이름 끝 + 4는 받침(두 단 조각은 이름이 든 조각에만 — [_claimCell]).
  //   · 공동 — 무늬 없음(두 단이 곧 꼴 — 걸음 2). 대립 · 정통 칸은 다듬기 판에 꼴이 없어 그리지 않는다.
  // 스위치 legit을 끄면 표가 비어 이 길을 지나지 않는다(구역 57이 없는 타일도 같다 — 지금 그림 그대로).

  /// 이 장면의 칸 정통성(스위치 `legit`일 때만): (띠 id · 칸 종류 · 직위 줄 더의 단(그 밖은 0) · 순번) → 정통성 번호(`Schema4.legitRival` …).
  final _legits = <(int, int, int, int), int>{};

  /// 타일마다 한 번 읽어 둔 구역 57(타일의 내용은 바뀌지 않는다).
  static final _legitBy = Expando<Map<(int, int, int, int), int>>('칸의 정통성');

  /// 주장 빗금이 화면에 붙는 가로 자리(장면마다 — [LegitLook.phaseX]).
  double _hatchX = 0;

  /// 한 무리를 그리는 동안 그은 칸 금(열 · 위 · 아래 — 한 단 띠의 [_floorDividers]). 두 단 띠의 조각은 [_pieceDivs]. 밑줄 · 빗금이 그 화소를 비킨다.
  final _divCols = <(double, double, double)>[];

  static Map<(int, int, int, int), int> _legitsOf(Tile t) => _legitBy[t] ??= () {
    final s = t.section(Schema4.secCellLegit);
    if (s.count == 0) return const <(int, int, int, int), int>{};
    final ref = s.u(Tile.itemRef), a = s.u(Tile.itemA), b = s.u(Tile.itemB), cc = s.u(Tile.itemC), dd = s.u(Tile.itemD);
    return {
      for (int i = 0; i < s.count; i++)
        if (cc[i] > 0 && dd[i] > 0) (ref[i], a[i], a[i] == Schema4.cellOfficeMore ? b[i] : 0, cc[i] - 1): dd[i] - 1,
    };
  }();

  /// 띠 [band]의 칸(타일의 칸 종류 [kind] · 단 [lane] · 순번 [seq])의 정통성 번호 — 모르면(구역 57에 없음 · 스위치 끔) −1.
  int _legitAt(int band, int kind, int lane, int seq) {
    if (_legits.isEmpty || seq < 0) return -1;
    return _legits[(band, kind, kind == Schema4.cellOfficeMore ? lane : 0, seq)] ?? -1;
  }

  bool _isRegent(int band, int kind, int lane, int seq) => _legitAt(band, kind, lane, seq) == Schema4.legitRegent;

  /// 섭정 칸을 띠마다 훑는다(메움 타일은 빼고): 칸 id로 타일을 건너 합친 좌우(화면 px) · 종류 · 단 · 순번 · 이름([_Host.regents]).
  void _scanRegents(PaintContext c) {
    if (!_legits.containsValue(Schema4.legitRegent)) return;
    final layout = c.layout, v = c.v;
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      final cache = _cellsOf(t);
      for (int run = 0; run < cache.runCount; run++) {
        final first = cache.runAt[run], kind = t.cellKindOf(first);
        if (kind != CellKind.leader && kind != CellKind.cabinet && kind != Schema4.cellOfficeMore) continue;
        final row = cache.runRow[run];
        if (row >= layout.rowCount || !layout.hasBody(row)) continue;
        final hosts = _hostsOf[row];
        if (hosts == null || hosts.isEmpty) continue;
        for (int i = first; i < cache.runAt[run + 1]; i++) {
          final seq = cache.seq[i];
          if (seq < 0) continue;
          final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
          final host = _hostAt(hosts, (a + b) / 2);
          if (host == null || !_isRegent(host.id, kind, t.cellLane[i] & 0xff, seq)) continue;
          final r = (host.regents ??= <int, _Regent>{})[t.cellId[i]] ??= _Regent(kind, t.cellLane[i] & 0xff, seq, t.text(t.cellName[i]));
          if (a < r.l) r.l = a;
          if (b > r.r) r.r = b;
        }
      }
    }
  }

  /// 한 단 띠의 무리(지금 길 — [_paintPlaced])에서 섭정 기간마다 피후견 칸을 정한다: 그 기간을 품은 칸(타일을 합친 칸 전체로 잼)이 있으면 그 칸에 기간 전체를,
  /// 없으면 겹친 칸마다 시작 차례로 앞 칸이 덮지 않은 몫을(다듬기 판의 조각마다 피후견 — 한 단 띠는 조각이 곧 칸). 결과는 칸의 [_Placed.regents].
  void _groupRegents(_Host host, int kind, int lane, double minW) {
    final regs = host.regents;
    if (regs == null || _lensBand != 0) return;
    for (final reg in regs.values) {
      if (reg.kind != kind || reg.lane != lane) continue;
      _Placed? holder;
      for (int k = 0; k < _placedCount && holder == null; k++) {
        final p = _placed[k];
        if (p.r - p.l >= minW && p.wholeL <= reg.l + .5 && p.wholeR >= reg.r - .5) holder = p;
      }
      if (holder != null) {
        final s = math.max(reg.l, holder.a), e = math.min(reg.r, holder.b);
        if (e - s >= .5) holder.regents.add((reg, s, e));
        continue;
      }
      var covered = reg.l;
      for (int k = 0; k < _placedCount; k++) {
        final p = _placed[k];
        if (p.r - p.l < minW) continue;
        final s = math.max(covered, p.a), e = math.min(reg.r, p.b);
        if (e - s < .5) continue;
        p.regents.add((reg, s, e));
        covered = e;
      }
    }
  }

  /// 두 단 띠의 조각([d] — 칸 [_PieceDraft.cell]의 조각 [_PieceDraft.wholeL] ~ [_PieceDraft.wholeR]의 이 타일 몫)이 피후견 칸이면 그 섭정 기간을 [p]에 단다:
  /// 그 조각에 든 후보 칸(섭정이 아닌 칸) 가운데 섭정 기간을 품은 칸 · 없으면 단이 가장 위인 칸(다듬기 판 `pc.act.find(…) || pc.act[0]`).
  void _pieceRegents(_Host host, _BandPieces bp, _PieceDraft d, _Placed p) {
    final regs = host.regents;
    if (regs == null) return;
    final mid = (d.wholeL + d.wholeR) / 2;
    for (final reg in regs.values) {
      if (reg.kind != CellKind.leader) continue;
      final s = math.max(math.max(d.a, d.wholeL), reg.l), e = math.min(math.min(d.b, d.wholeR), reg.r);
      if (e - s < .5) continue;
      _PieceCell? top, holder;
      for (final cell in bp.cells.values) {
        if (cell.regent || cell.l >= mid || cell.r <= mid) continue;
        if (top == null || cell.lane < top.lane) top = cell;
        if (cell.l <= reg.l + .5 && cell.r >= reg.r - .5 && (holder == null || cell.lane < holder.lane)) holder = cell;
      }
      if (identical(holder ?? top, d.cell)) p.regents.add((reg, s, e));
    }
  }

  /// 섭정 밑줄(다듬기 판 paintCells ④): 피후견 칸 [p]의 제 자리 아랫변 안쪽 2px([b] − 2 ~ [b]) 먹 60 — 칸 금 오른쪽 화소부터 다음 칸 금 앞까지
  /// (칸 금 — 한 단 띠는 이 무리가 그은 [_divCols] · 두 단 띠는 미리 모은 [_pieceCols] — 이 그 줄을 지나면 비킴) · 칸 [l] ~ [r] 안(테를 두른 칸은 [inset] 안쪽). 밝기 · 옅은 끝은 칸과 같다.
  /// 누름 기록(섭정 칸의 참조 — 밑줄 위 3px까지)을 피후견 칸 뒤에 더해 그 자리를 누르면 섭정 칸 창이 열린다.
  void _regentLines(PaintContext c, _Host host, int row, _Placed p, double l, double r, double b, _Dim dim, double inset) {
    final cols = _pieceDivs != null ? _pieceCols : _divCols;
    final y = b - LegitLook.regentH;
    for (final (reg, s, e) in p.regents) {
      var x0 = s.roundToDouble(), x1 = e.roundToDouble();
      for (final (q, from, to) in cols) {
        if (to <= y + .5 || from >= b - .5) continue;
        if ((q - s).abs() <= 1.5) x0 = math.max(x0, q + 1);
        if (q >= e - 2.5 && q <= e + .5) x1 = math.min(x1, q);
      }
      x0 = math.max(x0, (l + inset).ceilToDouble());
      x1 = math.min(x1, (r - inset).floorToDouble());
      if (x1 - x0 < 1) continue;
      _span(c, x0, y, x1, b, LegitLook.regentInk, p.fade, l, r, dim);
      c.stats.shapes++;
      c.debug?.note('섭정밑줄', '$row ${reg.seq} ${_r1(x0)},${_r1(y)},${_r1(x1 - x0)}');
      final item = _refOf.isEmpty ? null : _refOf[(host.id, reg.kind, reg.lane, reg.seq)];
      if (_drawnCount == _drawn.length) _drawn.add(_Drawn());
      _drawn[_drawnCount++]
        ..band = host.id
        ..row = row
        ..kind = reg.kind
        ..ref = CellKind.ref(reg.kind, reg.lane, reg.seq)
        ..uid = item?.$1 ?? ''
        ..name = item?.$2 ?? reg.name
        ..l = x0
        ..t = y - 3
        ..r = x1
        ..b = b
        ..houseId = ''
        ..houseName = ''
        ..houseColor = 0
        ..textL = 0
        ..textW = 0;
    }
  }

  /// 주장 칸의 빗금(다듬기 판 paintCells ①): 칸 바탕(칸 금 · 테 안 — [top] ~ [b] · [l] ~ [r])에만 1px 화소 빗금 먹 25. 이름 앞 4 ~ 이름 끝 + 4는 받침(빗금 없음) —
  /// 이름 자리는 칸 전체로 정한 것이라 타일에 걸친 칸의 두 조각이 같은 자리를 비운다. 두 단 띠의 조각은 이름이 든 조각만 이름이 있어 그 조각에만 받침이 선다.
  /// 무늬의 세로 자리는 지도자 층 윗선(두 단 띠는 층 전체 — 단이 달라도 한 무늬)에 붙는다.
  void _claimCell(PaintContext c, _Placed p, double l, double top, double r, double b, _Dim dim, double inset) {
    final cols = _pieceDivs != null ? _pieceCols : _divCols;
    var x0 = (l + inset).ceilToDouble(), x1 = (r - inset).floorToDouble();
    final y0 = top + inset, y1 = b - inset;
    for (final (q, from, to) in cols) {
      if (to <= y0 + .5 || from >= y1 - .5) continue;
      if (q >= x0 - .5 && q < x0 + 1.5) x0 = q + 1;
      if (q >= x1 - 1.5 && q < x1 + .5) x1 = q;
    }
    if (x1 - x0 < 1 || y1 - y0 < 1) return;
    final phaseY = _pieceDivs != null ? _pieceBase : top - 1;
    final ink = CanvasInk.alpha(LegitLook.hatchInk);
    void put(double a, double z) {
      if (z - a >= 1) _pattern(c, LegitLook.hatch, a, y0, z, y1, ink, p, dim, phaseX: _hatchX, phaseY: phaseY);
    }

    if (p.text.isEmpty || _hideNames) {
      put(x0, x1);
    } else {
      final at = p.center + p.dx - p.textW / 2;
      put(x0, math.min(x1, (at - LegitLook.namePad).floorToDouble()));
      put(math.max(x0, (at + p.textW + LegitLook.namePad).ceilToDouble()), x1);
    }
    c.debug?.note('주장칸', '${_r1(x0)},${_r1(y0)},${_r1(x1 - x0)},${_r1(y1 - y0)}${p.text.isEmpty ? '' : ' ${p.text}'}');
  }

  /// 칸에 딸린 일반 항목(구역 40~43 · 46)을 모은다. 구간 · 경계는 (줄 · 종류 · 단)마다, 가문 · 가리키는 항목 · 지도자 표기는 (띠 · 종류 · 단 · 순번)마다.
  /// 한 항목이 여러 타일에 실리므로 항목 번호로 좌우를 합친다(잘린 조각의 끝이 아니라 온 구간을 쓴다).
  void _readItems(PaintContext c, Tile t, double origin, Map<int, _Zone> zoneById, Map<int, _Ghost> ghostById, bool wantHouse) {
    final v = c.v;
    for (final kind in const [CellItem.zone, CellItem.alt, CellItem.house, CellItem.item, CellItem.leaderName]) {
      if (kind == CellItem.house && !wantHouse) continue; // 가문 강조 · 표시 체크 '가문'이 꺼져 있으면 읽지 않는다(견본에 1,190개)
      if (kind == CellItem.leaderName && !_labelOn) continue; // 기본 표기면 칸의 이름 그대로다
      final s = t.section(kind);
      if (s.count == 0) continue;
      final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
      final id = s.u(Tile.itemId), row = s.u(Tile.itemRow), a = s.u(Tile.itemA), b = s.u(Tile.itemB), cc = s.u(Tile.itemC), dd = s.u(Tile.itemD);
      final ref = kind == CellItem.house || kind == CellItem.item || kind == CellItem.leaderName ? s.u(Tile.itemRef) : null;
      for (int i = 0; i < s.count; i++) {
        final key = _key(row[i], a[i], b[i]);
        if (kind == CellItem.leaderName) {
          if (cc[i] == 0) continue;
          // `name` = 묘호 · `text2` = "시호\t이름" · `d` = 대수 + 1.
          final rest = t.text(s.u(Tile.itemText2)[i]);
          final cut = rest.indexOf('\t');
          _leaderOf[(ref![i], a[i], b[i], cc[i] - 1)] =
              (t.text(s.u(Tile.itemName)[i]), cut < 0 ? rest : rest.substring(0, cut), cut < 0 ? '' : rest.substring(cut + 1), dd[i] - 1);
        } else if (kind == CellItem.item) {
          if (cc[i] == 0) continue;
          if (a[i] == CellKind.common) {
            // 렌즈 칸: `name` = 갈래 · `color` = 연정 칸의 둘째 색 · `d` = 짝을 모르는 연정 · `text2` = 누를 항목 uid(+ 색 점 — 내보내기 export/lens.mjs).
            _lensOf[(ref![i], b[i], cc[i] - 1)] = _LensRef.read(t.text(s.u(Tile.itemText2)[i]), t.text(s.u(Tile.itemName)[i]), s.u(Tile.itemColor)[i], dd[i]);
            continue;
          }
          _refOf[(ref![i], a[i], b[i], cc[i] - 1)] = (t.text(s.u(Tile.itemText2)[i]), t.text(s.u(Tile.itemName)[i]));
        } else if (kind == CellItem.zone) {
          final had = zoneById[id[i]];
          final l = v.xOf(origin + x0[i]), r = v.xOf(origin + x1[i]);
          if (had == null) {
            final z = _Zone(l, r, cc[i]);
            zoneById[id[i]] = z;
            (_zonesOf[key] ??= []).add(z);
          } else {
            if (l < had.a) had.a = l;
            if (r > had.b) had.b = r;
          }
        } else if (kind == CellItem.alt) {
          final had = ghostById[id[i]];
          final l = v.xOf(origin + x0[i]);
          if (had == null) {
            final g = _Ghost(l, dd[i] == 0 ? -1 : dd[i] - 1);
            ghostById[id[i]] = g;
            (_ghostsOf[key] ??= []).add(g);
          } else if (l < had.x) {
            had.x = l;
          }
        } else {
          if (cc[i] == 0) continue;
          _houseOf[(ref![i], a[i], b[i], cc[i] - 1)] = (t.text(s.u(Tile.itemText2)[i]), s.u(Tile.itemColor)[i], t.text(s.u(Tile.itemName)[i]));
        }
      }
    }
  }

  @override
  void flush(PaintContext c) {
    _sprites.flush(c.canvas);
    // 꼬리표 밑 흰 사슬(G5 #9 나): 종이의 둥근 귀 → 구멍 · 꼬리표 아랫변의 점(종이 · 금 · 막대 위 — 글자는 띠 테두리 걸음의 끝에).
    _chainSprites.flush(c.canvas);
    if (_rings.isNotEmpty) {
      for (final ring in _rings) {
        final at = ui.Offset(ring.x, ring.y);
        if (ring.fill != 0) c.canvas.drawCircle(at, ring.r, _ringFill..color = ui.Color(ring.fill));
        if (ring.line != 0) c.canvas.drawCircle(at, ring.r, _ringLine..color = ui.Color(ring.line));
      }
      _rings.clear();
    }
    _sendHover(c.scene);
  }

  // ──────────────────────────────── 커서가 올라간 칸(성씨 풍선) ────────────────────────────────

  static final _hoverBy = Expando<ValueNotifier<StripHit?>>('커서가 올라간 칸');

  /// 그 장면에서 커서가 올라간 칸([hotCell])의 자리 · 가문 — 장면을 그린 뒤에 바뀐 때만 싣는다(그리는 도중에 듣는 쪽을 깨우지 않게 미룬다).
  /// 성씨 풍선(확정 설계 1-2 5-2 · `ui/cards.dart`의 올림 카드 층)이 듣는다. 칸이 화면에 그려지지 않았으면 null이다.
  /// 자리 [StripHit.rect]는 배치 px(돋보기 배율을 곱하기 전)이다.
  static ValueNotifier<StripHit?> hoverOf(Object scene) => _hoverBy[scene] ??= ValueNotifier<StripHit?>(null);

  StripHit? _hoverSent;

  void _sendHover(Object scene) {
    final key = hotCell;
    StripHit? hit;
    if (key != null) {
      final cut = key.indexOf('|');
      final band = cut < 0 ? null : int.tryParse(key.substring(0, cut));
      final ref = cut < 0 ? '' : key.substring(cut + 1);
      if (band != null && ref.isNotEmpty) {
        _Drawn? first;
        double l = 0, t = 0, r = 0, b = 0;
        for (int i = 0; i < _drawnCount; i++) {
          final d = _drawn[i];
          if (d.band != band || d.ref != ref) continue;
          // 타일에 걸친 칸은 조각마다 기록이 있다 — 하나로 합친다.
          if (first == null) {
            first = d;
            l = d.l;
            t = d.t;
            r = d.r;
            b = d.b;
          } else {
            l = math.min(l, d.l);
            t = math.min(t, d.t);
            r = math.max(r, d.r);
            b = math.max(b, d.b);
          }
        }
        if (first != null) {
          hit = StripHit(first.band, first.row, first.kind, first.ref, first.uid, first.name, ui.Rect.fromLTRB(l, t, r, b),
              houseId: first.houseId, houseName: first.houseName, houseColor: first.houseColor);
        }
      }
    }
    final was = _hoverSent;
    if (hit == null && was == null) return;
    if (hit != null && was != null && hit.key == was.key && hit.rect == was.rect && hit.houseId == was.houseId && hit.name == was.name) return;
    _hoverSent = hit;
    final notifier = hoverOf(scene);
    scheduleMicrotask(() => notifier.value = hit);
  }

  // ──────────────────────────────── 조명 칠(.tl-spot) ────────────────────────────────

  final _fillPaint = ui.Paint();
  final _fillSpans = <(double, double, double)>[];

  /// 띠 안 조명 칠(지금 연표 `.tl-spots` · `.tl-spot` — css 1227~1234): 그 띠에 걸린 **가문 · 성씨 조명** 구간마다 띠 색 22%를 띠의 몫 높이로,
  /// 띠 안쪽(테두리 1px 안 · 띠의 둥근 끝)으로 잘라 칠하고, 띠 끝에 닿지 않은 칠의 끝에는 띠 테두리 색 60%의 1px 세로선을 긋는다.
  /// **칠 차례**(확정 설계 1-2 5-3 · 10절 14번 추천 '함께'): 띠 채움 · 연대 폭 빗금 · 할거기 칠 **위**, 칸 · 사건 **아래** —
  /// 이 층은 그 셋이 다 나간 뒤에 시작하고, 칸의 묶음은 이 층이 끝날 때 나가므로 여기서 곧바로 그리면 그 차례가 된다.
  /// 웹은 칸 · 인물 · 왕조 조명도 같은 칠이지만 앱은 그 칠을 아직 옮기지 않았다(띠 층 검사가 그 구간의 밝기를 픽셀로 잰다 — 결합 때 함께).
  /// 그래서 [em.Emphasis.isHouseSpot]인 구간만 칠한다. 칠의 짙기는 조명의 진행(`Spot.glow`)을 따른다(나타남 200 · 물러남 160).
  /// 타일마다 그 타일의 띠 조각 안만 칠한다(이음매에서 겹쳐 짙어지지 않게 · 바뀌는 동안 덮개 타일의 잘림 · 옅기를 그대로 받게).
  /// 메아리 칠(`.tl-spot.is-echo` — 다른 띠에 같은 시기)은 아직 옮기지 않았다.
  void _spotFill(PaintContext c, Tile t) {
    final v = c.v, origin = t.origin.toDouble(), layout = c.layout;
    for (int i = 0; i < t.bandCount; i++) {
      final look = t.bandLook[i];
      if (look & BandLook.under != 0) continue; // 바탕 문화는 칸의 주인이 아니다(조명도 그 위의 띠에)
      final id = t.bandId[i], row = t.bandRow[i];
      final spots = _spotsOn(id);
      if (spots.isEmpty) continue;
      // 가문 · 성씨 조명의 구간만 칠한다. 칸 · 인물 · 왕조 조명의 칠은 앱에 아직 없다(띠 층이 그 구간의 밝기만 가른다 — 지금 그대로).
      if (!spots.any(_em.isHouseSpot)) continue;
      if (row >= layout.rowCount || !layout.hasBody(row)) continue;
      final geo = layout.geo(row);
      final top = v.yOf(layout.rowTop(row) + geo.bandTop), height = geo.bandHeight;
      if (height <= 2 || !c.rowOnScreen(row, top, height)) continue;
      _Host? host;
      for (final h in _hostsOf[row] ?? const <_Host>[]) {
        if (h.id == id) host = h;
      }
      if (host == null) continue;
      // 띠의 모양(지금 띠 층과 같은 값): 화면 밖으로 1px 넘게 나간 끝은 곧고, 미정 끝 22 · 문화 12 · 그 밖 10.
      final bl = math.max(host.shapeL, c.left - 1), br = math.min(host.shapeR, c.w + 1);
      if (br - bl < 3) continue;
      final openL = host.shapeL < c.left - .5, openR = host.shapeR > c.w + .5;
      final cap = math.min((br - bl) / 2, height / 2);
      final base = BandLook.kindOf(look) == BandKind.culture ? 12.0 : 10.0;
      final rl = openL ? 0.0 : math.min(host.fuzzyS ? 22.0 : base, cap), rr = openR ? 0.0 : math.min(host.fuzzyE ? 22.0 : base, cap);
      final il = bl + 1, ir = br - 1, it = top + 1, ib = top + height - 1;
      // 이 타일의 띠 조각(잘린 쪽은 정수 px에서 이웃 조각과 만난다).
      final flags = t.bandFlags[i];
      final pl = flags & Tile.clipLeft != 0 ? v.xOf(origin + t.bandX0[i]).roundToDouble() : il;
      final pr = flags & Tile.clipRight != 0 ? v.xOf(origin + t.bandX1[i]).roundToDouble() : ir;
      final from = math.max(pl, il), to = math.min(pr, ir);
      if (to - from <= .5) continue;
      // 겹친 구간은 하나로(가장 짙은 진행) — 같은 해를 두 번 칠해 짙어지지 않게(웹: 이미 칠한 해는 다시 칠하지 않음).
      final merged = _fillSpans..clear();
      for (final s in spots) {
        if (_em.isHouseSpot(s)) merged.add((v.xOf(s.start), v.xOf(s.end), s.glow.clamp(0.0, 1.0)));
      }
      merged.sort((a, b) => a.$1.compareTo(b.$1));
      var k = 0;
      for (int j = 1; j < merged.length; j++) {
        final last = merged[k], s = merged[j];
        if (s.$1 <= last.$2) {
          merged[k] = (last.$1, math.max(last.$2, s.$2), math.max(last.$3, s.$3));
        } else {
          merged[++k] = s;
        }
      }
      merged.length = merged.isEmpty ? 0 : k + 1;
      // 띠의 흐림을 따른다 — 다만 '같은 시기를 타국에도'가 켜지면 조명 구간은 흐린 띠 안에서도 밝다(가림 판 --la).
      final alpha = _em.look.lit ? 1.0 : _em.bandAlpha(id, row);
      final color = 0xff000000 | host.color;
      final edge = _edgeOf(color);
      final canvas = c.canvas;
      var clipped = false;
      for (final (a0, b0, glow) in merged) {
        final a = math.max(a0, from), b = math.min(b0, to);
        if (b - a <= .5 || glow <= 0) continue;
        if (!clipped) {
          canvas.save();
          canvas.clipRRect(ui.RRect.fromLTRBAndCorners(il, it, ir, ib,
              topLeft: ui.Radius.circular(math.max(0, rl - 1)), bottomLeft: ui.Radius.circular(math.max(0, rl - 1)),
              topRight: ui.Radius.circular(math.max(0, rr - 1)), bottomRight: ui.Radius.circular(math.max(0, rr - 1))));
          clipped = true;
        }
        canvas.drawRect(ui.Rect.fromLTRB(a, it, b, ib), _fillPaint..color = ui.Color(withAlpha(color, em.Dim.spotFill * glow * alpha)));
        // 칠의 끝선: 띠 끝에 닿은 쪽(at-s · at-e)은 없고, 이 조각 안에 든 끝만(이음매에 선이 생기지 않게).
        final line = ui.Color(withAlpha(edge, .6 * glow * alpha));
        if (a0 > il + .5 && a0 >= pl && a0 < pr) canvas.drawRect(ui.Rect.fromLTRB(a, it, a + 1, ib), _fillPaint..color = line);
        if (b0 < ir - .5 && b0 > pl && b0 <= pr) canvas.drawRect(ui.Rect.fromLTRB(b - 1, it, b, ib), _fillPaint..color = line);
        c.stats.shapes++;
        c.debug?.note('조명칠', '$id ${_r1(a)},${_r1(it)},${_r1(b - a)},${_r1(ib - it)} ${(withAlpha(color, em.Dim.spotFill * glow * alpha) & 0xffffffff).toRadixString(16)}');
      }
      if (clipped) canvas.restore();
    }
  }

  @override
  void setScale(double scale) {
    _sprites.setScale(scale);
    _chainSprites.setScale(scale);
  }

  @override
  void paintTile(PaintContext c, Tile t) {
    // 조명 칠은 칸보다 먼저(띠 채움 · 연대 폭 빗금 · 할거기 칠 위 · 칸 아래). 조감은 칸이 없고 띠 모양이 달라 아직 칠하지 않는다.
    // 조감은 밀도 조감(V)과 자동 조감(보기 폭 2,600년 넘음)을 함께 본다(`layout.bird` — 지금 연표의 `isBird()`).
    if (_litOn && !c.layout.bird && !c.hide.contains('spotFill')) _spotFill(c, t);
    if (c.hide.contains('cells')) return;
    if (c.layout.bird) return; // 조감: 왕조 · 시기 · 지위 · 지도자 · 내각 · 예속 · 기관이 모두 빠진다(명세 05의 7.2)
    // 무리(한 줄의 한 단)로 끊는 일은 타일마다 한 번이면 된다 — 타일이 셈해 둔 경계를 쓴다.
    final cache = _cellsOf(t);
    _hideNames = c.hide.contains('cellNames'); // 장면마다 칸마다 묻지 않고 타일마다 한 번
    // 무리는 줄 순으로 온다 — 세로로 안 보이는 줄은 그 줄의 무리를 통째로 건너뛴다(한 줄에 단이 예닐곱이다).
    final layout = c.layout;
    _rules.clear();
    int run = 0, gateRow = -1;
    var gateOpen = false;
    while (run < cache.runCount) {
      final row = cache.runRow[run];
      if (row != gateRow) {
        gateRow = row;
        gateOpen = false;
        if (row < layout.rowCount && layout.hasBody(row) && (_hostsOf[row]?.isNotEmpty ?? false)) {
          // 줄의 몫에 단이 모두 들어 있으므로 줄이 화면에 안 걸치면 단도 안 걸친다(64px은 넉넉한 여유).
          final rowTop = c.v.yOf(layout.rowTop(row));
          gateOpen = rowTop - 64 <= c.h && rowTop + layout.geo(row).height + 64 >= c.head;
        }
      }
      if (!gateOpen) {
        run++;
        continue;
      }
      // 두 단 줄의 지도자 무리들: 두 단 띠의 칸은 조각으로 한 번에(모든 단), 한 단 띠의 칸은 무리마다 지금 길로.
      final end = _paintPieceRuns(c, t, cache, run);
      if (end > run) {
        for (int k = run; k < end; k++) {
          _paintLane(c, t, cache, k);
        }
        run = end;
        continue;
      }
      _paintLane(c, t, cache, run);
      run++;
    }
    // 칸 층 사이 흐린 가로선(감독 지적 2026-10-25): 이 타일의 칸을 다 그린 뒤 겹친 조각을 합쳐 한 번씩 — 칸 칠 · 세로 금 위 · 글자 아래(글자는 띠 테두리 걸음의 끝).
    // 점선(꼴 c)의 무늬는 세계에 붙인다(1970년 첫 분의 x — 정수로 맞춰 점이 픽셀에 선다).
    _rules.emit(c, PaintPick.rows, c.v.xOf(0).roundToDouble());
  }

  /// 이 타일을 그리는 동안 이름을 끄는가(`c.hide`의 'cellNames').
  bool _hideNames = false;

  /// 한 줄의 한 단(무리). 그 안에서 다시 주인 띠마다 모아 놓는다 — 칸의 좌우는 제 띠 안쪽에 갇히기 때문.
  /// 한 줄에 띠가 여럿이면 같은 단의 칸이 **시작 순으로 섞여** 오므로 이어 붙은 자리만 보지 않고 띠마다 모은다(그러지 않으면 이음이 끊긴다).
  void _paintLane(PaintContext c, Tile t, _TileCells cache, int run) {
    final first = cache.runAt[run], last = cache.runAt[run + 1];
    final row = t.cellRow[first], kind = t.cellKindOf(first), lane = t.cellLane[first] & 0xff;
    // 렌즈 칸(종류 8의 단 갈래 1 ~ 4)은 렌즈를 켠 동안만(끈 뒤 옛 판 타일이 메움으로 깔려도 그리지 않는다 — 아래 무리마다). 렌즈 켬 배치는
    // 지도자 칸이 없는 트랙에도 지도자 자리를 두므로, 표시 체크 '지도자'를 끈 동안의 지도자 칸(내린 지도자 칸 포함)은 뺀다(웹: 그때는 빈 채).
    if (_lensOn && !_leadersOn && kind == CellKind.leader) return;
    final layout = c.layout;
    if (row >= layout.rowCount || !layout.hasBody(row)) return;
    final geo = layout.geo(row);
    final (stripTop, stripHeight) = _stripAt(geo, kind, lane);
    if ((stripTop < 0 || stripHeight <= 0) && kind == CellKind.common && (lane == 2 || lane == 3) && !layout.bird && c.layout.conditions.density > 0 && c.layout.conditions.groups) {
      _inlinePower(c, t, row, first, last, geo);
      return;
    }
    if (stripTop < 0 || stripHeight <= 0) return;
    final top = c.v.yOf(layout.rowTop(row) + stripTop);
    if (!c.rowOnScreen(row, top, stripHeight)) return;
    final hosts = _hostsOf[row];
    if (hosts == null || hosts.isEmpty) return;
    final v = c.v, origin = t.origin.toDouble();
    // 화면 밖은 일찍 버린다. 칸을 가두는 상자는 어느 띠에서도 [c.left − 1, c.w + 1] 안이므로(아래 [_paintGroup]의 lo · hi)
    // 그 바깥의 칸은 어차피 버려진다 — 자리를 셈하기 전에 이분 탐색으로 앞뒤를 잘라 낸다(2px은 셈의 오차를 위한 여유).
    final from = _firstReaching(cache.reach, first, last, (c.left - 2 - v.left) / v.ppm + v.lo - origin);
    final to = _firstAfter(t.cellX0, from, last, (c.w + 2 - v.left) / v.ppm + v.lo - origin);
    if (from >= to) return;
    _groupCount = 0;
    for (int i = from; i < to; i++) {
      final mid = (v.xOf(origin + t.cellX0[i]) + v.xOf(origin + t.cellX1[i])) / 2;
      final host = _hostAt(hosts, mid);
      // 두 단 띠의 지도자 칸은 조각으로 이미 그렸다([_paintPieceRuns]).
      if (host == null || (host.pieces != null && kind == CellKind.leader)) continue;
      int g = 0;
      while (g < _groupCount && !identical(_groupHost[g], host)) {
        g++;
      }
      if (g == _groupCount) {
        if (g == _groupCells.length) {
          _groupHost.add(host);
          _groupCells.add(<int>[]);
        } else {
          _groupHost[g] = host;
          _groupCells[g].clear();
        }
        _groupCount++;
      }
      _groupCells[g].add(i);
    }
    // 두 장 꼬리표(감독 결정 '두 장 ㄴ'): 칸 층은 띠마다 제 층만 몸통 윗변부터 맞붙인 자리(bands.dart TagLook.compactOf — 옛 저장소는 줄의 자리).
    // 꼬리표 밑 흰 사슬(왕조 · 지위 — G5 #9 나)은 띠마다 제 꼬리표 바로 밑(TagLook.chainYOf — 사건 칸을 올린 몫 · 없는 위 사슬만큼 올림).
    final cellRows = layout.spec(row)?.cellRows ?? false, loose = layout.conditions.density < 0;
    double topOf(_Host host) => cellRows
        ? c.v.yOf(layout.rowTop(row) +
            TagLook.chainYOf(geo, host.look, TagLook.compactOf(geo, host.look, stripTop, sub: host.sub), oldStore: false, loose: loose, sub: host.sub))
        : top;
    // 사슬 자리의 무리는 흰 사슬 꼴로(차례 걸음 15 — [_paintGroup]이 [_paintChain]으로 넘긴다). 무리를 다 그리면 되돌린다.
    _chainSlot = stripTop >= geo.chainTop - .5 ? _chainSlotOf(geo, kind, lane) : -1;
    for (int g = 0; g < _groupCount; g++) {
      // 렌즈 칸: 한 띠 · 한 단의 칸은 한 갈래 꼴이다(제도는 렌즈 칸 꼴, 붕당은 단체 칸 꼴, 지위로 대신한 체제는 지위 칸 꼴, 내린 지도자는 지도자 칸 꼴).
      // 지위 · 지도자 꼴은 그 단(종류 5 · 1, 단 0)으로 그려 이설 · 모호한 구간 · 가문 · 표기 · 칸 참조를 옛 칸과 같이 쓴다 — 자리만 바꾼다.
      // 종류 8의 다른 갈래(단체 단 — 설계 11-3의 제안 5 ~ 7)는 렌즈와 상관없이 제 단으로.
      final band = kind == CellKind.common ? CellStyle.bandOf(t.cellStyle[_groupCells[g].first]) : 0;
      if (CellStyle.isGroupBand(band)) {
        // 단체 단(단 2 집권 · 3 실권): 렌즈와 상관없이 제 단에 단체 칸 꼴로. 붕당 렌즈를 켜면 단 2의 칸은 변형이 가리고(엔진),
        // 그 자리에 내린 지도자 칸(갈래 4)이 온다 — 아래 렌즈 갈래.
        _lookOverride = _Strip.group;
        try {
          _paintGroup(c, t, cache, _groupHost[g], row, kind, lane, _groupCells[g], topOf(_groupHost[g]), stripHeight);
        } finally {
          _lookOverride = null;
        }
        continue;
      }
      if (band < CellStyle.lensCell || band > CellStyle.lensLeader) {
        _paintGroup(c, t, cache, _groupHost[g], row, kind, lane, _groupCells[g], topOf(_groupHost[g]), stripHeight);
        continue;
      }
      if (!_lensOn || (band == CellStyle.lensLeader && !_leadersOn)) continue;
      _lensBand = band;
      final (asKind, asLane) = switch (band) {
        CellStyle.lensRank => (CellKind.rank, 0),
        CellStyle.lensLeader => (CellKind.leader, 0),
        _ => (CellKind.common, lane),
      };
      _lookOverride = switch (band) {
        CellStyle.lensRank => _Strip.lensRank,
        CellStyle.lensLeader => _Strip.lensLeader,
        CellStyle.lensGroup => _Strip.lensGroup,
        _ => null,
      };
      try {
        _paintGroup(c, t, cache, _groupHost[g], row, asKind, asLane, _groupCells[g], topOf(_groupHost[g]), stripHeight);
      } finally {
        _lensBand = 0;
        _lookOverride = null;
      }
    }
    _chainSlot = -1;
  }

  /// 커서가 올라간 칸(`'<띠>|lens:<순번>'`)이 갈래가 있는 렌즈 칸이면 그 갈래, 아니면 ''.
  String _echoFamOf(String? hot) {
    if (!_lensOn || hot == null || _lensOf.isEmpty) return '';
    final bar = hot.indexOf('|lens:');
    if (bar <= 0) return '';
    final band = int.tryParse(hot.substring(0, bar)), seq = int.tryParse(hot.substring(bar + 6));
    if (band == null || seq == null) return '';
    return _lensOf[(band, 0, seq)]?.fam ?? '';
  }

  /// 렌즈 칸이 가리키는 것(누를 항목 · 갈래 · 둘째 색 · 색 점).
  _LensRef? _lensItem(int band, int lane, int seq) => seq < 0 ? null : _lensOf[(band, lane, seq)];

  /// 단의 위 자리와 높이. 예속 안 칸은 **0번 단이 띠 아랫변에 가장 가깝다**(계약 6-2) — 줄 전체의 단 수에서 거꾸로 센다.
  /// 단체 단(집권 · 실권)을 층 없이 꼬리표 머리에(리메이크 2부 · 목업 서고 `power`): 그 기간 꼬리표 아랫변이 2px 밑줄([powerLine] — 단체 색 80% + 먹) +
  /// 이름 8.5 굵게 같은 색을 그 기간 왼쪽 + 4에 — 기간에 다 들고 머리 이름과 겹치지 않을 때만. 칸 층이 없는 꼬리표라 [layout]이 층을 두지 않았다.
  void _inlinePower(PaintContext c, Tile t, int row, int first, int last, RowGeo geo) {
    final hosts = _hostsOf[row];
    if (hosts == null || hosts.isEmpty) return;
    final v = c.v, origin = t.origin.toDouble();
    final top = v.yOf(c.layout.rowTop(row) + geo.bandTop).roundToDouble();
    if (!c.rowOnScreen(row, top, G.head)) return;
    final heads = BandLayer.of(c.scene)?.headNameZones[row];
    for (int i = first; i < last; i++) {
      if (!CellStyle.isGroupBand(CellStyle.bandOf(t.cellStyle[i]))) continue;
      final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
      final host = _hostAt(hosts, (a + b) / 2);
      if (host == null) continue;
      final x0 = math.max(math.max(a, host.x0 + 3), c.left).roundToDouble(), x1 = math.min(math.min(b, host.x1 - 3), c.w).roundToDouble();
      if (x1 - x0 < 2) continue;
      final ink = _powerInk[t.cellColor[i]] ??= mixOklab(0xff000000 | t.cellColor[i], Look.ink, powerLine);
      c.quads.add(x0, top + G.head - 2, x1, top + G.head, ink);
      c.stats.shapes++;
      final raw = t.text(t.cellName[i]), cut = raw.indexOf('\t');
      final label = cut >= 0 ? raw.substring(cut + 1) : raw;
      if (label.isEmpty) continue;
      final look = _powerLook[ink] ??= TextLook(8.5, ui.FontWeight.w700, mixSrgb(0xff000000 | t.cellColor[i], Look.ink, .30));
      final w = c.text.widthOf(label, look);
      if (w == null) {
        c.scene.requestFrame();
        continue;
      }
      final sx = x0 + 4;
      if (sx + w > x1 - 4) continue;
      var busy = false;
      for (final z in heads ?? const <(double, double)>[]) {
        if (sx < z.$2 + 4 && sx + w > z.$1 - 4) busy = true;
      }
      if (busy) continue;
      c.later.add('power', label, look, sx, top + G.head / 2 - 1 - look.size * .6);
    }
  }

  final _powerInk = <int, int>{};

  /// 집권 · 실권 단의 밑줄 색 = 단체 색 80% + 먹 20%(감독 2026-10-15 — 예전 58%는 검은 띠처럼 보였다 · 나라 색 계열도 견준 뒤 "그냥 단체 색으로").
  /// 칸 글은 지도자 칸과 같은 섞임(단체 색 30% + 먹).
  static const powerLine = .80;
  final _powerLook = <int, TextLook>{};

  /// 왕조 · 지위(와 지위 단 자리의 렌즈 칸)는 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나)이면 [RowGeo.strip]이 줄의 사슬 자리를 준다 —
  /// 띠마다 제 꼬리표 바로 밑으로 옮기는 것은 [_paintLane]의 `topOf`([TagLook.chainYOf]).
  (double, double) _stripAt(RowGeo geo, int kind, int lane) {
    if (kind == CellKind.dep) {
      if (geo.depTop < 0) return (-1, 0);
      final rowLanes = math.max(0, (geo.depHeight / G.depPitch).round());
      final back = math.max(0, rowLanes - 1 - lane);
      return (geo.depTop + back * G.depPitch, G.dep);
    }
    // 렌즈 칸: 단 0은 지도자 칸 자리, 단 1(지위 단 자리로 내린 지도자 칸)은 지위 단 자리. 그 밖의 단(단체 단 — 설계 11-3)은 아직 자리가 없다.
    if (kind == CellKind.common) return lane <= 1 ? geo.strip(lane == 1 ? CellKind.rank : CellKind.leader) : geo.strip(kind, lane);
    // 기관은 지금 연표가 단을 쌓지 않고 모두 기관 단에 겹쳐 그린다(줄 높이에 자리가 없다) — 그대로 따른다.
    // 칸 종류 9(직위 줄 더 — G7 가 · 칸 그림 갈래 걸음 4 · [Schema4.officeLinesDrawn] 참)는 그 줄(lane)의 직위 줄 더 층 자리(`RowGeo.strip(9, lane)` —
    // 내각 다음 · 예속 앞). 층이 없는 줄(옛 저장소 · 표시 '지도자' 끔 · 줄 값 없는 줄 · 스위치 `office` 끔)은 (−1, 0)이라 그리지 않는다.
    // 띠마다 제 몸통 자리로 옮기는 것은 [_paintLane]의 `topOf`(bands.dart TagLook.compactOf — 직위 줄 더도 제 수만 맞붙임).
    return geo.strip(kind, kind == CellKind.organ ? 0 : lane);
  }

  _Host? _hostAt(List<_Host> hosts, double x) {
    int lo = 0, hi = hosts.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (hosts[mid].x0 <= x) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return null;
    // 같은 자리에서 시작한 띠가 여럿일 수 있으니 뒤에서 앞으로 몇 개만 더 본다.
    for (int k = found; k >= 0 && k > found - 4; k--) {
      if (hosts[k].x1 >= x) return hosts[k];
    }
    return null;
  }

  /// 한 띠 안의 한 단 — 지금 연표의 `_cells` · `_dynCells` · `_phaseCells` · `_rankCells` · `_depCells` · 기관 칸.
  void _paintGroup(PaintContext c, Tile t, _TileCells cache, _Host host, int row, int kind, int lane, List<int> cells, double top, double height) {
    _ruleTop = _ruleBottom = _divTop = _divBottom = double.nan;
    if (_chainSlot >= 0) {
      _paintChain(c, t, cache, host, row, kind, lane, cells, top, height);
      return;
    }
    final v = c.v, origin = t.origin.toDouble();
    // 띠 상자는 화면에 맞춰 자른다(지금 연표: left = max(x1, -1) · width = min(x2, W+1) - left) — 이름이 보이는 부분의 가운데에 오게.
    final boxL = math.max(host.x0, c.left - 1), boxR = math.max(math.max(host.x0, c.left - 1) + 3, math.min(host.x1, c.w + 1));
    final clipL = host.x0 < c.left - 1, clipR = host.x1 > c.w + 1;
    double lo, hi;
    if (kind == CellKind.organ) {
      // 기관 칸은 띠의 자식이 아니라 줄 직속이다(명세 5-3의 11번): 띠의 진짜 끝에서 1px(테) 안쪽, 그다음 화면으로 자른다.
      lo = math.max(host.x0 + 1, c.left);
      hi = math.min(host.x1 - 1, c.w);
    } else {
      // 꼬리표 갈래 E: 칸은 흰 층의 너비 전체 — 띠 테두리 바로 안쪽까지(예전엔 테두리 안 + 3).
      lo = boxL + 1;
      hi = boxR - 1;
    }
    if (hi - lo < 1) return;
    _divLast = double.negativeInfinity;
    _divLo = lo;
    _divHi = hi;
    final minW = kind == CellKind.dep ? 2.0 : 1.0;

    // (1) 보이는 칸 고르기 — 지금 연표 layoutStrip의 vis. 섭정 칸(구역 57 — 칸 그림 갈래 걸음 3)은 층을 세우지 않는다(피후견 칸의 밑줄 — [_regentLines]).
    final legits = _legits.isNotEmpty && _lensBand == 0 && (kind == CellKind.leader || kind == CellKind.cabinet || kind == Schema4.cellOfficeMore);
    _placedCount = 0;
    for (final i in cells) {
      final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
      if (b <= lo || a >= hi) continue;
      if (legits && _isRegent(host.id, t.cellKindOf(i), t.cellLane[i] & 0xff, cache.seq[i])) continue;
      final p = _take(i, a, b);
      final flags = t.cellFlagsOf(i);
      p.cutL = flags & Tile.clipLeft != 0;
      p.cutR = flags & Tile.clipRight != 0;
      p.tileL = p.cutL;
      if (p.cutL) p.a = p.a.roundToDouble(); // 이음매는 양쪽 조각이 같은 정수 px에서 만나게
      if (p.cutR) p.b = p.b.roundToDouble();
      p.seamL = _seamAt(t, i, false); // 잘리지 않은 끝이 이음매에 딱 놓여 이웃 타일의 칸과 맞닿음(칸 층 가로선 — [_ruleEnds])
      p.seamR = _seamAt(t, i, true);
      final whole = (p.cutL || p.cutR) ? _joined[t.cellId[i]] : null;
      p.wholeL = whole?.$1 ?? p.a;
      p.wholeR = whole?.$2 ?? p.b;
    }
    if (_placedCount == 0) return;

    // 칸이 띠에게서 물려받는 밝기. 기관 칸만은 띠의 자식이 아니라 **줄 직속**이라 띠의 흐림을 받지 않는다
    // (명세 5-3의 11번 · css의 `.tl-lane .tl-org` — 아래 (1)의 자리 셈과 같은 까닭).
    var alpha = kind == CellKind.organ ? 1.0 : _em.bandAlpha(host.id, row);
    // 렌즈를 켠 동안 남은 지도자 칸은 그 주제 자료가 없는 나라의 것 — 칸 전체를 .4로(웹의 `.is-nolens`). 내린 지도자 칸(종류 8)은 빼고.
    if (_lensOn && kind == CellKind.leader && _lensBand == 0) alpha *= .4;
    // 이 띠의 조명 구간 — 켜진 것이 없으면 묻지도 않는다(묻기만 해도 걸러 내는 목록이 하나 생긴다).
    // 흐르는 값이라 다 꺼진 것(진행 0)은 버린다 — 띠 층 `_spotsOn`과 같다.
    final hostSpots = _litOn ? _spotsOn(host.id) : const <em.Spot>[];
    final spots = kind == CellKind.organ ? const <em.Spot>[] : hostSpots;

    // 꼬리표 갈래 E(설계 4-1 '실제 띠에 입힘'): 칸이 하나라도 있는 띠는 **첫 칸 단부터 띠 아랫변까지가 흰 층** — 띠 테두리 바로 안쪽 폭(미정 꼬리는 빼고),
    // 층마다 윗선 1px(띠 테두리 빛깔). 칸(칠 · 세로 금 · 글)은 그 윗선 아래에 든다. 칸이 없는 단도 흰 층이라 층이 가운데 끼어 보이지 않는다.
    // 한 장면에 띠마다 한 번(타일마다 조각이 오므로). 왼쪽 아래 귀(모따기 · 둥근 끝) 밖으로 나간 몫은 종이 위의 종이빛이고, 띠 테두리가 나중에 그 귀를 긋는다.
    // 두 장 꼬리표(감독 결정 '두 장 ㄴ')에서는 몸통 띠(칸 뭉치 칠 · 층 사이 금)를 띠 층(bands.dart `_paintTwoPiece`)이 그린다 — 여기서는 칸만.
    if (kind != CellKind.organ && c.layout.geo(row).bodyTop < 0 && _floored.add(host.id)) {
      final layout = c.layout, geo = layout.geo(row), tops = geo.floorTops;
      final fl = math.max(host.shapeL, c.left - 1) + 1, fr = math.min(host.shapeR, c.w + 1) - 1;
      if (tops.isNotEmpty && fr > fl) {
        final base = layout.rowTop(row), bottom = v.yOf(base + geo.bandTop + geo.bandHeight), floorTop = v.yOf(base + tops.first);
        final paper = withAlpha(Look.paper, alpha);
        // 왼쪽 아래 귀(꼬리표 꼴 · 키에 맞춘 크기 — bands.dart TagLook.cornerOf): 귀 밖으로 흰 층이 나가지 않게 귀의 줄마다 안쪽부터 칠한다
        // (폴더 안에서는 귀 밖이 폴더 칠이라 종이빛 삼각형이 보였다). 띠 테두리가 나중에 그 귀의 빗변 · 호를 긋는다.
        // 귀의 꼴은 띠 층이 이 장면에 정한 것(form의 종류 갈래 — TagLook.endOfBand · G6 가)을 따른다. 띠 층이 없는 그리개면 옛 종류 짐작.
        final guess = TagLook.endOf(host.look);
        final end = BandLayer.of(c.scene)?.endOf(host.id, guess) ?? guess;
        final shut = host.fuzzyS || host.shapeL < c.left - .5 || BandLook.kindOf(host.look) == BandKind.culture;
        final k = shut ? 0.0 : math.min(TagLook.cornerOf(end, geo.bandHeight), (host.shapeR - host.shapeL) / 2);
        final cut = math.max(floorTop, bottom - k);
        c.quads.add(fl, floorTop, fr, cut, paper);
        for (double y = cut; y < bottom - .01; y++) {
          final d = y + .5 - (bottom - k); // 귀 위끝에서 이 줄 가운데까지
          final inset = end == TagEnd.key ? k - math.sqrt(math.max(0, k * k - (k - d) * (k - d))) : d;
          c.quads.add(math.max(fl, host.shapeL + inset + .5).roundToDouble(), y, fr, math.min(y + 1, bottom), paper);
        }
        final line = withAlpha(_edgeOf(host.color), alpha);
        for (final y in tops) {
          c.quads.hLine(fl, fr, v.yOf(base + y), line);
        }
      }
    }
    final cellTop = kind == CellKind.organ ? top : top + 1, cellH = kind == CellKind.organ ? height : height - 1;

    // (2) 빽빽한 칸: 지도자 · 내각이 한 칸에 6px도 못 되면 단 전체를 한 칸으로(지금 연표 _cells의 is-dense).
    // 칸 수는 이 타일의 것이 아니라 그 띠의 화면 안 칸 전체로 센다(beginFrame — 웹 `seen`과 같은 뜻). 타일마다 세면 한 띠가 타일 경계에서
    // 반은 빽빽한 칸 · 반은 낱칸으로 갈려 끊겨 보였다. 빽빽한 칸은 띠 하나에 한 번만 그린다(여러 타일이 같은 띠를 나눠 갖는다).
    final iw = boxR - boxL - 2;
    if (kind == CellKind.leader || kind == CellKind.cabinet) {
      final count = math.max(_placedCount, kind == CellKind.leader ? host.leaders : host.cabinets);
      if (count > 1 && (iw - 2 * _pad2) / count < 6) {
        if (_denseDone.add(host.id * 16 + kind)) _dense(c, host, lo, hi, cellTop, cellH, alpha, kind, lane);
        return;
      }
    } else if (kind == Schema4.cellOfficeMore) {
      // 직위 줄 더(칸 그림 갈래 걸음 4): 줄마다 같은 셈 — 열쇠는 줄을 담아(나머지 16이 9라 지도자 · 내각 열쇠와 겹치지 않음).
      final count = math.max(_placedCount, host.offices?[lane] ?? 0);
      if (count > 1 && (iw - 2 * _pad2) / count < 6) {
        if (_denseDone.add((host.id * 32 + lane) * 16 + kind)) _dense(c, host, lo, hi, cellTop, cellH, alpha, kind, lane);
        _markOffice(t, host, row, lane, lo, top + height / 2);
        return;
      }
    }
    // 칸 층 사이 흐린 가로선(감독 지적 2026-10-25)의 이 층 자리 — 빽빽한 칸(위)은 제 파선 테가 있어 긋지 않는다. 층 윗선 [top] · 높이 [height]로
    // (칸 자리 cellTop은 그 한 줄 아래 — 구분선 갈래와 합칠 때 칸 그림 갈래의 [_paintPlaced] 앞으로 옮김).
    _ruleAt(c, row, top, height, lo, hi, host, hostSpots);
    _paintPlaced(c, t, cache, host, row, kind, lane, lo, hi, clipL, clipR, cellTop, cellH, alpha, hostSpots, spots, minW);
    _ruleTop = _ruleBottom = _divTop = _divBottom = double.nan;
    if (kind == Schema4.cellOfficeMore) {
      // 왼쪽 칸 줄 이름 자리: 이 무리에서 그린 칸 가운데 가장 왼쪽(사슬 이름 [chainMarks]와 같은 셈).
      var x = double.infinity;
      for (int k = 0; k < _placedCount; k++) {
        final p = _placed[k];
        if (p.r - p.l >= minW && p.l < x) x = p.l;
      }
      if (x.isFinite) _markOffice(t, host, row, lane, x, top + height / 2);
    }
  }

  /// 직위 줄 더 층(칸 종류 9 — 칸 그림 갈래 걸음 4)의 왼쪽 칸 줄 이름 자리를 적는다 — 줄 · 줄(lane)마다 화면 왼쪽에 가장 가까운 띠의 층([x] — 그 띠가 그린
  /// 가장 왼쪽 칸 · 빽빽한 칸이면 칸 상자 왼쪽) 가운데 [y]. 이름은 그 띠 구역 55의 그 줄 이름(타일 [t]에 실린 것 — 없으면 적지 않음).
  void _markOffice(Tile t, _Host host, int row, int lane, double x, double y) {
    final name = _officeNamesOf(t)[host.id * 32 + lane];
    if (name == null || name.isEmpty) return;
    final key = row * 32 + lane, had = officeMarks[key];
    if (had == null) {
      officeMarks[key] = ChainMark(row, lane, name, x, y);
    } else if (x < had.x) {
      had
        ..x = x
        ..y = y
        ..label = name;
    }
  }

  /// 타일마다 한 번 읽어 둔 구역 55(직위 줄 더의 줄 이름): (띠 id × 32 + 줄) → 이름. 같은 띠 · 같은 줄이 둘이면 앞의 것.
  static final _officeNameBy = Expando<Map<int, String>>('직위 줄 더의 줄 이름');

  static Map<int, String> _officeNamesOf(Tile t) => _officeNameBy[t] ??= () {
    final out = <int, String>{};
    for (final n in Schema4.officeNames(t)) {
      if (n.lane >= 0 && n.lane < 32) out.putIfAbsent(n.band * 32 + n.lane, () => n.name);
    }
    return out;
  }();

  /// 한 무리의 놓인 칸([_placed]의 앞 [_placedCount]개 — 시작 차례)을 잇고 · 재고 · 그린다 — [_paintGroup]의 (3) ~ (7). 칸의 자리는 [cellTop] · [cellH]
  /// (층 윗선 아래), 칸 상자는 [lo] ~ [hi]. 두 단 띠의 조각([_paintPieces] — 층 전체 · 제 단 무리마다)도 이 길로 그린다.
  /// 칸 층 사이 흐린 가로선(구분선 갈래 — [_ruleAt] · [_ruleCells])의 층 자리는 부르는 쪽이 이 길 앞에 정하고 뒤에 비운다(한 단 띠는 그 무리의 층 ·
  /// 두 단 띠는 층 전체 한 번 — 조각 무리가 여럿이라 이 길 안에서 정하거나 비우면 둘째 무리부터 가로선이 빠진다). 이 길은 칸을 다 그린 뒤 칸마다 읽기만.
  void _paintPlaced(PaintContext c, Tile t, _TileCells cache, _Host host, int row, int kind, int lane, double lo, double hi, bool clipL, bool clipR,
      double cellTop, double cellH, double alpha, List<em.Spot> hostSpots, List<em.Spot> spots, double minW) {
    // (3) 잇기와 0.5px 틈 — layoutStrip 그대로. 이음은 `앞 칸과 같은 무리`(style 비트 2)에 픽셀로도 맞닿을 때만.
    final n = _placedCount;
    if (_jn.length < n) _jn = Uint8List(n + 64);
    final jnR = _jn;
    jnR[n - 1] = 0;
    final pieces = _pieceDivs != null;
    _divCols.clear();
    for (int k = 0; k < n - 1; k++) {
      final next = _placed[k + 1];
      final style = t.cellStyle[next.index];
      var join = style & CellStyle.joinLeft != 0;
      if (pieces) {
        // 두 단 띠의 조각: 맞닿은 진짜 끝 · 진짜 시작만 잇는다 — 이음매(다른 단 · 층 전체로 이어지는 쪽)를 건너 잇지 않고, 순번이 건너뛴 칸은
        // 다른 단의 칸이라(순번은 단을 가로질러 센다) 빈틈을 메우지 않는다.
        join = join && !_placed[k].cutR && !next.cutL && (_placed[k].b - next.a).abs() < 1.5;
      } else if (join && (_placed[k].b - next.a).abs() >= 1.5) {
        // 성긴 단계에서는 엔진이 짧은 칸(통의 1/8 미만)을 싣지 않는다(levels.rs `lod_of`). 그 자리가 몇 px 비면 픽셀로는 맞닿지 않아
        // 무리가 끊기고 양쪽이 따로 둥근 칸이 되어, 축소한 띠의 지도자 칸 줄이 토막 나 보였다(감독 건의 2026-10-14 8번).
        // 목록의 순번(비트 15~26)이 건너뛰었으면 그 사이가 빠진 칸이다 — 이어 붙이고 앞 칸을 늘여 메운다(아래 '잇기'). 웹은 모든 칸을 받아 이미 그렇다.
        final s0 = CellStyle.seqOf(t.cellStyle[_placed[k].index]), s1 = CellStyle.seqOf(style);
        join = next.a > _placed[k].b && s0 >= 0 && s1 > s0 + 1;
        // 건너뛴 순번이 모두 섭정 칸(층을 세우지 않아 무리에서 뺀 칸 — 걸음 3)이면 빠진 칸이 아니다 — 메우지 않는다.
        if (join && host.regents != null) {
          var gap = false;
          for (int s = s0 + 1; s < s1 && !gap; s++) {
            if (!_isRegent(host.id, t.cellKindOf(next.index), lane, s)) gap = true;
          }
          join = gap;
        }
      }
      jnR[k] = join ? 1 : 0;
    }
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      final jl = k > 0 && jnR[k - 1] != 0, jr = jnR[k] != 0;
      p.atL = p.a <= lo;
      p.atR = p.b >= hi;
      p.l = p.a > lo ? p.a + (jl || p.cutL ? 0 : 0.5) : lo;
      p.r = p.b < hi ? p.b - (jr || p.cutR ? 0 : 0.5) : hi;
    }
    // 그리는 칸끼리만 잇고, 건너뛴 빈틈은 앞 칸을 늘여 메운다(명세 5-3의 8번).
    int? prev;
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      if (p.r - p.l < minW) continue;
      if (prev != null) {
        bool linked = true;
        for (int i = prev; i < k; i++) {
          if (jnR[i] == 0) linked = false;
        }
        if (linked) {
          p.jl = true;
          _placed[prev].jr = true;
          if (_placed[prev].r < p.l) _placed[prev].r = p.l;
        }
      }
      prev = k;
    }

    // (4) 칸마다 이름 · 꼬리 · 테두리 두께를 먼저 재어 둔다 — 유령 구분선 비킴과 무늬의 글자 자리가 이 값을 본다.
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      if (p.r - p.l < minW) continue;
      _measure(c, t, cache, host, row, kind, lane, p, k > 0 ? _placed[k - 1] : null, hostSpots, lo, hi, clipL, clipR);
    }

    // (4-1) 섭정 기간의 피후견 칸(칸 그림 갈래 걸음 3) — 두 단 띠의 조각은 [_paintPieces]가 이미 달았다.
    if (!pieces) _groupRegents(host, kind, lane, minW);

    // (5) 이설의 유령 구분선과 이름표 비킴, 그리고 모호한 구간의 무늬 조각.
    _planAlts(c, row, kind, lane, minW, lo, hi);
    _planZones(row, kind, lane, minW, cellTop, cellH);

    // (6) 칸마다 그리기.
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      if (p.r - p.l < minW) continue;
      // 메아리: 갈래가 있는 렌즈 칸에 올리면 그 갈래가 아닌 렌즈 칸은 .4(갈래 없는 칸도 — 웹의 `.lens-echo .k-lens:not(.is-fam)`).
      // 단체 단(단 2 · 3)의 칸은 렌즈 칸이 아니라 메아리를 타지 않는다.
      final echo = kind == CellKind.common && lane <= 1 && _echoFam.isNotEmpty && (_lensItem(host.id, lane, p.seq)?.fam ?? '') != _echoFam ? .4 : 1.0;
      _drawCell(c, cache, host, row, kind, lane, p, cellTop, cellH, alpha * echo, spots);
    }
    // 칸 층 사이 흐린 가로선(감독 지적 2026-10-25): 칸 자리의 층 윗선 · 아랫선 조각(타일 끝에 합쳐 긋는다 — [paintTile]). 끝을 칸이 그은 구분선 열에
    // 맞추므로(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게') 칸을 다 그린 뒤에.
    if (!_ruleTop.isNaN) _ruleCells(host.id, n, minW);
    _drawAlts(c, row, kind, lane, cellTop, cellH, alpha);
    // (7) 가문 줄(표시 체크 '가문') — 칸보다 위에 그리므로 맨 뒤에.
    if (showHouses && kind == CellKind.leader) _drawHouseLines(c, minW, cellTop, cellH, alpha);
  }

  // ──────────────────────────── 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나 · 차례 걸음 15 — paint/chains.dart) ────────────────────────────

  /// 한 띠의 한 사슬(왕조 · 지위 · 렌즈가 지위 자리로 내린 지도자 — [ChainLook]). 칸 층의 무리 셈(보이는 칸 · 재기 · 이설 · 모호한 구간 · 밝기 ·
  /// 누름 기록)을 그대로 쓰고 꼴만 다르다: 띠 테 그 자리까지 흰 종이(둥근 3 · 테 먹 45) — 맞닿은 칸(1.5px 안 · 다른 타일에 실린 칸도)은 한 종이로
  /// 잇고 칸 사이에 세로 금 먹 25 · 글은 왼쪽 맞춤 8.5 굵게 먹 85(왕조는 가문 색 막대 뒤 · 지위는 뒤에 서열 눈금) · 꼬리표 시작에서 비롯하는
  /// 사슬의 첫 칸에 구멍. [top]은 이 띠의 사슬 윗변(제 꼬리표 밑 틈 3 — [TagLook.chainYOf]) · [height]는 [G.chain] 14.
  void _paintChain(PaintContext c, Tile t, _TileCells cache, _Host host, int row, int kind, int lane, List<int> cells, double top, double height) {
    final v = c.v, origin = t.origin.toDouble(), slot = _chainSlot;
    // 사슬 종이는 띠 테 그 자리까지(칸 층의 테 안 1px 들임이 없다 — 종이의 왼쪽 테가 꼬리표 왼쪽 테와 한 줄).
    final lo = math.max(host.x0, c.left - 1), hi = math.max(lo + 3, math.min(host.x1, c.w + 1));
    final clipL = host.x0 < c.left - 1, clipR = host.x1 > c.w + 1;
    final span = host.chainOf(slot);

    // (1) 보이는 칸 — 칸 층과 같은 셈.
    _placedCount = 0;
    for (final i in cells) {
      final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
      if (b <= lo || a >= hi) continue;
      final p = _take(i, a, b);
      final flags = t.cellFlagsOf(i);
      p.cutL = flags & Tile.clipLeft != 0;
      p.cutR = flags & Tile.clipRight != 0;
      if (p.cutL) p.a = p.a.roundToDouble(); // 이음매는 양쪽 조각이 같은 정수 px에서 만나게
      if (p.cutR) p.b = p.b.roundToDouble();
      final whole = (p.cutL || p.cutR) ? _joined[t.cellId[i]] : null;
      p.wholeL = whole?.$1 ?? p.a;
      p.wholeR = whole?.$2 ?? p.b;
    }
    if (_placedCount == 0) return;
    // 실은 이 띠의 첫 사슬 종이보다 먼저 묶음에 넣는다 — 종이가 실을 덮어 사슬 사이 틈에서만 보인다.
    if (_threaded.add(host.id)) _chainThread(c, host, row);
    final alpha = _em.bandAlpha(host.id, row);
    final spots = _litOn ? _spotsOn(host.id) : const <em.Spot>[];

    // (2) 자리와 잇기: 칸은 제 자리 그대로(칸 층의 0.5px 틈 없음), 맞닿은 칸은 이음 — 이 타일의 앞뒤 칸이든 다른 타일의 칸이든([_scanChains]가 모은 두 끝).
    final n = _placedCount;
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      p.atL = p.a <= lo;
      p.atR = p.b >= hi;
      p.l = math.max(p.a, lo);
      p.r = math.min(p.b, hi);
      p.jl = !p.cutL && p.a > lo && _touches(span.ends, p.a);
      p.jr = !p.cutR && p.b < hi && _touches(span.starts, p.b);
    }
    for (int k = 1; k < n; k++) {
      final prev = _placed[k - 1], p = _placed[k];
      if (prev.jr && p.jl && (prev.b - p.a).abs() < 1.5) prev.r = p.l; // 1.5px 안의 빈틈 · 겹침은 앞 칸의 끝을 맞춘다
    }

    // (3) 재기 — 칸 층의 셈(색 · 가문 · 명목 · 실권 · 미정 끝 · 고름)에 사슬의 글 자리를 덧쓴다.
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      if (p.r - p.l < 1) continue;
      _measure(c, t, cache, host, row, kind, lane, p, k > 0 ? _placed[k - 1] : null, spots, lo, hi, clipL, clipR);
      _chainText(c, t, cache, host, kind, lane, p, span, lo, hi);
    }

    // (4) 이설의 유령 구분선 · 모호한 구간 — 종이 테 안(위아래 1px 안).
    _planAlts(c, row, kind, lane, 1, lo, hi);
    _planZones(row, kind, lane, 1, top + 1, height - 2);

    // (5) 칸마다 그리기 · 왼쪽 칸의 사슬 이름 자리(줄 · 사슬 차례마다 화면 왼쪽에 가장 가까운 사슬).
    final label = ChainLook.labelOf(slot, leaders: kind == CellKind.leader);
    for (int k = 0; k < n; k++) {
      final p = _placed[k];
      if (p.r - p.l < 1) continue;
      _drawChainCell(c, cache, host, row, kind, lane, p, top, height, alpha, spots);
      final key = row * 2 + slot, had = chainMarks[key];
      if (had == null) {
        chainMarks[key] = ChainMark(row, slot, label, p.l, top + height / 2);
      } else if (p.l < had.x) {
        had
          ..x = p.l
          ..y = top + height / 2
          ..label = label;
      }
    }
    _drawAlts(c, row, kind, lane, top + 1, height - 2, alpha);
  }

  /// 사슬을 꿴 실: 꼬리표 아랫변의 점(반지름 1.5)에서 마지막 구멍까지 한 줄 — x = 띠 왼쪽(사슬 종이의 왼쪽 테) + 7 · 먹 45.
  /// 구멍은 꼬리표 시작에서 비롯하는 사슬(첫 칸의 시작이 띠의 진짜 시작에서 반년 안 — 고르기 판 `Math.abs(first.a - o.a) < .5`)의 첫 칸에만이고,
  /// 그 시작이 화면 왼쪽 밖이면 없다(고르기 판 `!b.cl`). 구멍이 하나도 없으면 실도 점도 없다. 이 띠의 사슬 둘(왕조 · 지위)의 구멍을 함께 정한다.
  /// 밝기는 그 띠의 흐림 × 고른 동안의 .45(구슬 · 실 · 가장자리와 같은 값 — [em.Emphasis.trimDim]).
  void _chainThread(PaintContext c, _Host host, int row) {
    final layout = c.layout, v = c.v, geo = layout.geo(row), base = layout.rowTop(row);
    final cellRows = layout.spec(row)?.cellRows ?? false, loose = layout.conditions.density < 0;
    final slack = math.max(1.0, ChainLook.startSlackMinutes * v.ppm);
    double col = double.nan, last = double.nan;
    for (int slot = 0; slot < 2; slot++) {
      final span = host.chainSpan(slot);
      if (span == null) continue;
      span.hole = host.startX.isFinite && span.first.isFinite && (span.first - host.startX).abs() <= slack && span.first >= c.left - .5;
      if (!span.hole) continue;
      span.holeCol = (span.first - .5).ceilToDouble() + ChainLook.holeX;
      final stripTop = slot == 0 ? geo.dynastyTop : geo.rankTop;
      final laneY = cellRows
          ? TagLook.chainYOf(geo, host.look, TagLook.compactOf(geo, host.look, stripTop, sub: host.sub), oldStore: false, loose: loose, sub: host.sub)
          : stripTop;
      if (col.isNaN) col = span.holeCol;
      last = v.yOf(base + laneY) + G.chain / 2;
    }
    if (col.isNaN) return;
    final from = v.yOf(base + geo.chainTop - (cellRows ? TagLook.eventLift(geo, host.look, oldStore: false, loose: loose, sub: host.sub) : 0));
    final alpha = _em.bandAlpha(host.id, row) * _em.trimDim;
    if (alpha <= .004 || last <= from) return;
    final ink = withAlpha(CanvasInk.gray(ChainLook.edge), alpha);
    c.quads.vLine(col, from, last, ink);
    _rings.add(_Ring(col + .5, from + ChainLook.dotR, ChainLook.dotR, ink, 0));
    c.stats.shapes++;
    c.debug?.note('사슬실', '${host.id} ${_r1(col)},${_r1(from)},${_r1(last)}');
  }

  /// 사슬 칸 하나의 글 자리(고르기 판 chain()): 글은 칸 왼쪽(화면 왼쪽에 잘렸으면 화면 왼쪽) + 5 — 꼬리표 시작에서 비롯하는 사슬의 첫 칸이면
  /// 구멍 뒤(띠 왼쪽 + 13). 왕조는 그 자리에 가문 색 막대(3 × 8)를 두고 7 뒤에 이름. 이름은 칸 오른쪽 − 4까지 드는 만큼(온 이름 → 왕조의 짧은 이름 →
  /// 첫 글자 → 없음). 지위는 이름 끝 + 5에 서열 눈금(칸 오른쪽 − 3 안에 다 들 때만). 칸 층의 글 셈([_measure])이 정한 이름 · 딱지는 덮어쓴다.
  void _chainText(PaintContext c, Tile t, _TileCells cache, _Host host, int kind, int lane, _Placed p, _ChainSpan span, double lo, double hi) {
    final i = p.index;
    p
      ..tag = ''
      ..tagW = 0
      ..fixed = false
      ..text = ''
      ..textW = 0;
    p.chainHole = span.hole && !p.cutL && (p.a - span.first).abs() < .01 && p.r - p.l >= ChainLook.holeText;
    p.holeX = span.holeCol + .5;
    final edgeCol = (math.max(p.wholeL, lo) - .5).ceilToDouble();
    var x = p.chainHole ? span.holeCol - ChainLook.holeX + ChainLook.holeText : math.max(edgeCol, c.left) + ChainLook.textPad;
    final right = math.min(p.wholeR, hi);
    p.chainBar = kind == CellKind.dynasty && x + ChainLook.barW <= right - 2;
    p.chainX = x;
    if (p.chainBar) x += ChainLook.barAdvance;
    p.center = x;
    if (_hideNames) return;
    final raw = _labelOn && kind == CellKind.leader ? _leaderNameOf(cache, i, host.id, lane, p.seq, t.text(t.cellName[i])) : t.text(t.cellName[i]);
    final short = kind == CellKind.dynasty ? (cache.alt[i] ??= _shortDynasty(raw)) : '';
    final fit = ChainLook.fit(raw, right - x - ChainLook.roomPad, (s) => c.text.widthOf(s, ChainLook.textLook), short: short);
    if (fit == null || fit.$1.isEmpty) return;
    p.text = fit.$1;
    p.textW = fit.$2;
    p.center = x + p.textW / 2;
    final ticks = kind == CellKind.rank ? ChainLook.ticksOf(CellStyle.rankOf(p.style)) : 0;
    if (ticks > 0 && x + p.textW + ChainLook.tickGap + (ticks - 1) * ChainLook.tickPitch + ChainLook.tickW <= right - 3) p.ticks = ticks;
  }

  /// 사슬 종이를 그리는 두 끝 — 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off가 아니면): 칸 자리(소수 px) 그대로면 종이의
  /// 세로 테가 두 열에 반씩 번져 위 꼬리표 테의 열과 어긋났다. 띠 테에 닿은 쪽은 꼬리표 테의 열(왼쪽 floor(l) · 오른쪽 floor(r − 1) — bands.dart `_edge`)에,
  /// 그 밖(이어 붙은 쪽 · 타일 이음매 · 띠 안의 칸 끝)은 칸 사이 세로 금과 같은 반올림 열에 둔다(이어 붙은 두 칸은 같은 값이라 한 종이 그대로).
  (double, double) _chainPaper(_Placed p) {
    if (PaintPick.rows == FloorRule.off) return (p.l, p.r);
    final l = p.atL ? p.l.floorToDouble() : p.l.roundToDouble();
    final r = p.atR ? (p.r - 1).floorToDouble() + 1 : p.r.roundToDouble();
    return (l, math.max(r, l + 1));
  }

  /// 사슬 칸 하나 — 종이(칠 · 테 · 둥근 귀) · 칸 사이 세로 금 · 구멍 · 막대 · 글 · 눈금. 맞히기 · 커서 비춤의 자리 기록은 칸 층과 같다(누르면 그 칸 창).
  /// 고른 칸(조명에 눌린 칸) · 가문 칸 · 올린 칸은 칸 층과 같은 칠(제 색을 종이와 섞음)과 짙은 테(그 색의 테 빛깔 — 고른 · 가문 칸은 1.5 · 왕조는 1).
  void _drawChainCell(PaintContext c, _TileCells cache, _Host host, int row, int kind, int lane, _Placed p, double top, double height, double alpha, List<em.Spot> spots) {
    final l = p.l, r = p.r, b = top + height, color = p.color;
    final (pl, pr) = _chainPaper(p); // 종이를 그리는 두 끝(정수 열 — 누름 · 기록은 칸 자리 그대로)
    final ref = p.seq < 0 ? '' : cache.refOf(p.index, kind, lane);
    final item = p.seq < 0 || _refOf.isEmpty ? null : _refOf[(host.id, kind, lane, p.seq)];
    p.twin = ref.isNotEmpty && (_em.look.isTwin(host.id, ref) || (hotTwins?.contains('${host.id}|$ref') ?? false));
    final dim = _dimOf(c, p, host.id, kind, alpha, spots, item?.$1 ?? '');
    if (p.ousted) {
      dim.scale(oustedAlpha);
    } else if (p.borrowed) {
      dim.scale(borrowedAlpha);
    }
    if (_drawnCount == _drawn.length) _drawn.add(_Drawn());
    _drawn[_drawnCount++]
      ..band = host.id
      ..row = row
      ..kind = kind
      ..ref = ref
      ..uid = item?.$1 ?? ''
      ..name = item?.$2 ?? p.text
      ..l = l
      ..t = top
      ..r = r
      ..b = b
      ..houseId = p.houseId
      ..houseName = p.houseName
      ..houseColor = p.houseColor
      ..textL = 0
      ..textW = 0
      ..chain = true;
    final drawnAt = _drawnCount - 1;
    final hot = hotCell != null && ref.isNotEmpty && hotCell == '${host.id}|$ref';
    final marked = p.spot || p.house;
    final paper = p.spot
        ? mixSrgb(color, Look.paper, .48)
        : (p.house ? mixSrgb(color, Look.paper, kind == CellKind.dynasty ? .50 : .42) : (hot ? mixSrgb(color, Look.paper, kind == CellKind.dynasty ? .50 : .30) : Look.paper));
    final edge = marked || hot ? _edgeOf(color) : CanvasInk.gray(ChainLook.edge);
    final bw = marked && kind != CellKind.dynasty ? 1.5 : 1.0;
    final radiusL = p.jl || p.openL || p.cutL ? 0.0 : ChainLook.radius, radiusR = p.jr || p.openR || p.cutR ? 0.0 : ChainLook.radius;
    // 사슬은 띠 아랫변 밑 바탕에 서는 땅 위 칸이다 — 흐림 · 미정 끝으로 종이가 비쳐도 맨 아래 연도 세로줄이 칸 안에 비치지 않게, 칠 · 무늬 · 테 전에
    // 그 자리 바탕색 종이를 깐다(리메이크 4단계 세로줄 얹기 걸음 4 — `_drawCell`의 땅 위 칸과 같은 길 · paint/grounds.dart). 끝은 사슬 종이의
    // 정수 열([_chainPaper] — 맞닿음)이라 이웃 구분선 · 테 열을 반쯤 덮지 않는다.
    c.grounds.paper(c.quads, pl, top, pr, b);
    _fill(c, pl, top, pr, b, paper, radiusL, radiusR, p.fade, dim, chain: true);
    _patternOf(c, kind, p, color, _softOf(color), top + 1, b - 1, dim);
    final unkS = p.fade != null && p.fade!.fl > 0, unkE = p.fade != null && p.fade!.fr > 0;
    _border(
      c, pl, top, pr, b, edge, radiusL, radiusR, fade: p.fade, dim: dim, width: bw, chain: true,
      // 이어 붙은 쪽 · 화면이나 타일에 잘린 쪽은 세로 테가 없다(이어 붙은 왼쪽은 아래 세로 금).
      left: p.cutL || p.openL || p.jl ? null : edge, right: p.cutR || p.openR || p.jr ? null : edge,
      dashLeft: p.zl ? 1.0 : (unkS ? 2.0 : 0), dashRight: p.zr ? 1.0 : (unkE ? 2.0 : 0),
    );
    // 칸 사이 세로 금(먹 25 — 위아래 테 안 1px): 앞 칸과 이어 붙은 칸의 왼쪽. 앞 칸 끝이 미정 · 모호하면 파선.
    if (p.jl) {
      final q = l.roundToDouble(), dash = p.zl || unkS || p.uLeft;
      c.quads.vLine(q, top + 1, b - 1, CanvasInk.alpha(ChainLook.divider, dim.at(q)), dash: dash ? 2 : 0, gap: dash ? 2 : 0, phase: top);
    }
    // 같은 사람의 칸(건의 8의 6-나 — 렌즈가 내린 지도자 칸): 먹 1.5px 테.
    if (p.twin) {
      _border(c, pl, top, pr, b, Look.ink, p.cutL ? 0 : ChainLook.radius, p.cutR ? 0 : ChainLook.radius, dim: dim, width: 1.5, chain: true,
          left: p.cutL ? null : Look.ink, right: p.cutR ? null : Look.ink);
    }
    c.stats.shapes++;
    c.debug?.note('칸', '$kind:$row:$lane ${_r1(l)},${_r1(top)},${_r1(p.w)},${_r1(height)}');
    c.debug?.note('칸이음', '$kind:$row:$lane jl=${p.jl} jr=${p.jr} zl=${p.zl} zr=${p.zr} st=${p.style} seq=${p.seq} a=${_r1(p.a)} b=${_r1(p.b)} i=${p.index}');
    c.debug?.note('사슬', '$_chainSlot:$row:${host.id} ${_r1(l)},${_r1(top)},${_r1(r - l)},${_r1(height)} jl=${p.jl} jr=${p.jr} 귀=${radiusL.round()}/${radiusR.round()}');
    // 밝기는 묶음의 색 알파에 곱해진다 — 칸 층과 같은 기록(칸의 왼쪽 끝과 오른쪽 끝에서 잰 값).
    c.debug?.note('칸밝기', '$kind:$row:$lane ${(dim.at(l + 1) * 1000).round()},${(dim.at(r - 2) * 1000).round()}');
    // 구멍(꼬리표 시작에서 비롯하는 사슬의 첫 칸 — 종이 위 · 반지름 1.5 · 테 먹 45).
    if (p.chainHole) {
      final hy = top + height / 2, fade = p.fade;
      final a = dim.at(p.holeX) * (fade != null && fade.any ? _fadeAt(fade, p.holeX, l, r) : 1);
      _rings.add(_Ring(p.holeX, hy, ChainLook.holeR, withAlpha(Look.paper, a), withAlpha(CanvasInk.gray(ChainLook.edge), a)));
      c.debug?.note('사슬구멍', '${host.id} ${_r1(p.holeX)},${_r1(hy)}');
    }
    // 글 · 막대 · 눈금: 타일에 걸친 칸은 왼쪽 조각만(칸 층과 같다 — 시작이 화면 왼쪽 밖이면 화면 왼쪽 끝에 닿은 조각).
    if (p.cutL && !p.atL) return;
    if (p.chainBar) {
      // 왕조의 가문 색 막대(3 × 8 · 둥근 1 — 네 귀 한 칸씩은 사분원 몫만): 그 칸 색의 띠 테 빛깔.
      final x = p.chainX, y = top + ChainLook.barTop, w = ChainLook.barW, h = ChainLook.barH;
      final a = dim.at(x + w / 2), argb = _edgeOf(color);
      final full = withAlpha(argb, a), corner = withAlpha(argb, a * ChainLook.barCorner);
      c.quads
        ..add(x, y + 1, x + w, y + h - 1, full)
        ..add(x + 1, y, x + w - 1, y + 1, full)
        ..add(x + 1, y + h - 1, x + w - 1, y + h, full)
        ..add(x, y, x + 1, y + 1, corner)
        ..add(x + w - 1, y, x + w, y + 1, corner)
        ..add(x, y + h - 1, x + 1, y + h, corner)
        ..add(x + w - 1, y + h - 1, x + w, y + h, corner);
      c.debug?.note('사슬막대', '${host.id} ${_r1(x)},${_r1(y)} ${(argb & 0xffffffff).toRadixString(16)}');
    }
    if (p.text.isEmpty) return;
    final at = p.center + p.dx - p.textW / 2;
    final laneKey = _lensBand != 0 ? row << 11 | CellKind.common << 8 | _lensBand : row << 11 | kind << 8 | lane;
    if (at < (_labelRight[laneKey] ?? double.negativeInfinity)) return;
    _labelRight[laneKey] = at + p.textW;
    _drawn[drawnAt]
      ..textL = at
      ..textW = p.textW;
    final look = ChainLook.textLook, hard = marked || hot ? Look.ink : look.color;
    final ink = p.nominal ? mixSrgb(over(hard, Look.paper), Look.paper, .5) : hard;
    c.later.add('cell', p.text, ink == look.color ? look : look.withColor(ink), at, top + (height - look.size * 1.2) / 2, dim.at(at + p.textW / 2));
    // 지위의 서열 눈금(이름 끝 + 5 · 폭 2 · 4마다 · 먹 45).
    if (p.ticks > 0) {
      final rx = at + p.textW + ChainLook.tickGap;
      for (int j = 0; j < p.ticks; j++) {
        final x = (rx + j * ChainLook.tickPitch).roundToDouble();
        c.quads.add(x, top + ChainLook.tickTop, x + ChainLook.tickW, top + ChainLook.tickTop + ChainLook.tickH, withAlpha(CanvasInk.gray(ChainLook.edge), dim.at(x + 1)));
      }
      c.debug?.note('사슬눈금', '${host.id} ${_r1(rx)} ${p.ticks}');
    }
    // 선을 하나도 긋지 못한 이설 — 이름 밑 가로 점선(칸 층과 같은 규칙 · 아래 테와 1px 띄움).
    if (p.hasAlt) {
      final gy = math.min(b - 3, (top + (height + look.size) / 2 + 1).roundToDouble());
      c.quads.hLine(at, at + p.textW, gy, withAlpha(_ghostOf(_softOf(color)), alpha * (p.spot ? 1 : _em.trimDim)), dash: 1, gap: 2, phase: at);
    }
  }

  /// 가문 줄(지금 연표 `houseRuns` + `.tl-houseline` · 명세 01의 3-6 가): 이어 붙은 지도자 칸에서 같은 가문이 이어지는 동안 하나.
  /// 칸 아래 테두리 바로 안쪽(칸 top + 높이 − 3)에 높이 2px — 칸과 별개라 칸의 올림 · 고름 모습을 덮지 않고 누름도 받지 않는다.
  void _drawHouseLines(PaintContext c, double minW, double top, double height, double alpha) {
    // 고른 것이 있으면 .45(css 1445 — 구슬 · 실 · 가장자리와 같은 값).
    final base = alpha * _em.trimDim;
    if (base <= 0) return;
    final y = top + height - 3;
    _Placed? first, last;
    void close() {
      if (first != null) _houseLine(c, first!, last!, y, base);
      first = null;
      last = null;
    }

    for (int k = 0; k < _placedCount; k++) {
      final p = _placed[k];
      if (p.r - p.l < minW) continue; // 그리지 않은 칸은 무리에도 들지 않는다(layoutStrip이 내놓은 칸만)
      if (first != null && p.jl && p.houseId.isNotEmpty && p.houseId == first!.houseId) {
        last = p;
        continue;
      }
      close();
      if (p.houseId.isNotEmpty) {
        first = p;
        last = p;
      }
    }
    close();
  }

  /// 가문 줄 한 가닥. 끝 들임: 이어 붙었으면 1px · 화면이나 타일에서 잘린 열린 끝이면 0 · 아니면 3px(칸의 둥근 끝 밖으로 나가지 않게).
  /// 바깥 끝 칸이 미정이면 그 칸과 함께 옅어진다(줄이 3px 안쪽에서 시작하므로 꼬리도 3px 짧다).
  void _houseLine(PaintContext c, _Placed first, _Placed last, double y, double alpha) {
    final l = first.l + (first.jl ? 1 : (first.openL || first.cutL ? 0 : 3));
    final r = last.r - (last.jr ? 1 : (last.openR || last.cutR ? 0 : 3));
    if (r - l < 4) return; // 4px보다 짧은 가닥은 긋지 않는다
    // 가문 창이 열린 그 가문(가문 조명이면 그 묶음)의 줄은 글자색으로(css 1450), 그 밖은 가문 색을 글자색과 72% 섞어.
    final tone = _em.look.isHouse(first.houseId) ? Look.ink : mixSrgb(first.houseColor, Look.ink, .72);
    final argb = withAlpha(tone, alpha);
    final fl = !first.jl && (first.fade?.fl ?? 0) > 0 ? first.fade!.fl - 3 : 0.0;
    final fr = !last.jr && (last.fade?.fr ?? 0) > 0 ? last.fade!.fr - 3 : 0.0;
    final clear = withAlpha(tone, 0);
    var x = l;
    if (fl > 0 && l + fl < r) {
      c.quads.addFade(l, y, l + fl, y + 2, clear, argb);
      x = l + fl;
    }
    final endAt = fr > 0 && r - fr > x ? r - fr : r;
    if (endAt > x) c.quads.add(x, y, endAt, y + 2, argb);
    if (endAt < r) c.quads.addFade(endAt, y, r, y + 2, argb, clear);
    c.stats.shapes++;
    c.debug?.note('가문줄', '${first.houseId} ${_r1(l)},${_r1(y)},${_r1(r - l)} ${tone.toRadixString(16)}${fl > 0 ? ' fl=${_r1(fl)}' : ''}${fr > 0 ? ' fr=${_r1(fr)}' : ''}');
  }

  /// 빽빽한 칸 하나(층 전체 — [kind] · [lane]은 검사 기록에만: 두 단 띠 조각의 층 전체는 lane −1).
  void _dense(PaintContext c, _Host host, double lo, double hi, double top, double height, double alpha, int kind, int lane) {
    c.debug?.note('빽빽', '${host.id}:$kind:$lane ${_r1(lo)},${_r1(top)},${_r1(hi - lo)},${_r1(height)}');
    final soft = _softOf(host.color);
    // 빽빽한 칸도 `.tl-cell`이라 고른 것이 있으면 .45가 함께 곱해진다(C:370).
    final a = alpha * _em.trimDim;
    // 불투명도 .7(명세 5-3의 17번) — 바탕은 없고 무늬와 파선 테두리만.
    c.patterns.add(_Pattern.dense, lo, top, hi, top + height, withAlpha(0xff000000 | host.color, 0.16 * 0.7 * a), phaseX: lo, phaseY: top);
    _border(c, lo, top, hi, top + height, withAlpha(soft, 0.7 * a), 6, 6, dashTop: 3, dashGap: 3);
    c.stats.shapes++;
  }

  /// 칸 하나의 이름 · 딱지 · 미정 꼬리 · 테두리 두께를 잰다(그리기 전에 한 번).
  void _measure(PaintContext c, Tile t, _TileCells cache, _Host host, int row, int kind, int lane, _Placed p, _Placed? before, List<em.Spot> hostSpots, double lo, double hi, bool clipL, bool clipR) {
    final i = p.index;
    p.style = t.cellStyle[i];
    p.seq = cache.seq[i];
    p.alt = CellStyle.altOf(p.style);
    final own = t.cellColor[i];
    p.color = 0xff000000 | (own != 0 ? own : host.color);
    final look = _lookFor(kind);
    // is-thin · 이름 · 꼬리는 조각이 아니라 칸 전체의 폭으로 — 타일 경계에서 모습이 바뀌지 않게.
    // 두 단 띠의 조각은 이름 · 꼬리를 그 조각 전체의 폭으로 재고, is-thin만 칸 전체(화면에 든 몫 — [_Placed.cellW])로 정한다.
    final wholeW = math.max(p.w, math.min(p.wholeR, hi) - math.max(p.wholeL, lo));
    p.thin = kind == CellKind.organ ? wholeW < 16 : (p.cell == null ? wholeW : math.max(wholeW, p.cellW)) < 8;
    p.openL = p.atL && clipL;
    p.openR = p.atR && clipR;
    // 좌우 테두리 두께(모호한 구간의 무늬가 드는 안쪽 상자) — 예속 칸만 좁아도 테두리를 둔다(명세 3-6 바).
    p.bl = kind == CellKind.dep ? 1 : (p.thin ? 0 : 1);
    p.br = kind == CellKind.dep ? (p.jr ? 0 : 1) : (p.thin || (p.jr && kind != CellKind.dynasty) ? 0 : 1);

    // ---- 가문(구역 42) ----
    // 가문 강조의 짙은 칸(is-house)과 표시 체크 '가문'의 가는 줄이 함께 쓴다.
    if (p.seq >= 0 && _houseOf.isNotEmpty) {
      final had = _houseOf[(host.id, kind, lane, p.seq)];
      if (had != null) {
        p.houseId = had.$1;
        p.houseColor = 0xff000000 | had.$2;
        p.houseName = had.$3;
      }
    }
    p.houseLine = showHouses && kind == CellKind.leader && p.houseId.isNotEmpty;

    // ---- 명목 지도자(이름 글만 .5) ----
    // 타일의 종류로 가린다 — 렌즈가 내린 지도자 칸은 지도자 칸 꼴로 그려도 종류 8이라 비트 30을 본다(비트 27~29는 단 갈래).
    if (_nominalOn) {
      final own = t.cellKindOf(i);
      p.nominal = own == CellKind.leader
          ? p.style & CellStyle.nominalLeader != 0
          : own == CellKind.common && CellStyle.bandOf(p.style) == CellStyle.lensLeader && p.style & CellStyle.nominalLowered != 0;
    }

    // ---- 빌린 직위 줄의 칸(리메이크 4단계 과제 5 걸음 2 · 걸음 4) ----
    // 타일의 종류로 가린다: 종류 1 · 2 · 9의 27비트만 빌림이다 — 종류 8(렌즈 · 단체 단)의 27 ~ 29비트는 단 갈래라 그 꼴로 그려도 빌림이 아니다.
    // 종류 9(직위 줄 더 — G7 가 · 칸 그림 갈래 걸음 4)는 그 줄의 층(`RowGeo.strip(9, lane)`)에 오고, 빌린 줄이면 같은 빌림 꼴(.72 · 윗변 1px 파선)이다.
    p.borrowed = Schema4.isBorrowed(t.cellKindOf(i), p.style);

    // ---- 칸의 정통성(구역 57 — 칸 그림 갈래 걸음 3 · 스위치 legit) ----
    // 명목 = 이름 먹 45 · 주장 = 칸 바탕 화소 빗금. 섭정은 무리에 들지 않고(밑줄), 공동은 두 단이 곧 꼴 · 대립 · 정통은 꼴이 없다.
    // 타일의 종류로 짝짓는다 — 렌즈 · 사슬의 무리(종류 8 · 왕조 · 지위)는 구역 57에 없다.
    if (_legits.isNotEmpty && _lensBand == 0 && _chainSlot < 0) {
      final legit = _legitAt(host.id, t.cellKindOf(i), lane, p.seq);
      p.legitNominal = legit == Schema4.legitNominal;
      p.claim = legit == Schema4.legitClaim;
    }

    // ---- 실권 기간의 지도자 칸(리메이크 4단계 과제 6) ----
    // 그 띠의 실권 밑줄(구역 56 — 남의 실권 · 제 안의 실권자 모두) 기간과 겹치는 지도자 칸은 칸 전체 .55(미리보기 `.k-leader.is-ousted` — common.css 2496).
    // 그리는 꼴로 가린다 — 렌즈가 지위 단 자리로 내린 지도자 칸(종류 8 · 갈래 4)도 지도자 칸 꼴이라 같다(미리보기 `_cells(…, 'leader', …)`).
    // 겹침은 칸 전체(타일에 걸친 칸은 조각을 합친 것)로 잰다 — 타일 경계에서 반쪽만 옅어지지 않게.
    if (kind == CellKind.leader && _powers.isNotEmpty) {
      final spans = _powers[host.id];
      if (spans != null) {
        final origin = t.origin.toDouble();
        final whole = (p.cutL || p.cutR) ? _joinedMin[t.cellId[i]] : null;
        final s = whole?.$1 ?? origin + t.cellX0[i], e = whole?.$2 ?? origin + t.cellX1[i];
        p.ousted = spans.any((w) => w.overlaps(s, e));
      }
    }

    // ---- 이름 ----
    // 이름 나누기와 폭 재기는 px와 무관하다(글꼴과 글의 크기만으로 정해진다) — 타일마다 한 번만 하고 보관한 값을 다시 쓴다.
    // 지도자 칸은 표기(묘호 · 시호 · 이름)와 대수가 기본이 아니면 그 자리에서 이름을 다시 짓는다(구역 46 — 보관은 표기가 바뀔 때 비운다).
    final rawName = _labelOn && kind == CellKind.leader ? _leaderNameOf(cache, i, host.id, lane, p.seq, t.text(t.cellName[i])) : t.text(t.cellName[i]);
    String tag = '', name = rawName;
    if (kind == CellKind.phase && p.style & CellStyle.tagged != 0) {
      final tags = cache.tag;
      var had = tags[i];
      if (had == null) {
        final cut = rawName.indexOf('\t');
        had = cut >= 0 ? rawName.substring(0, cut) : '';
        tags[i] = had;
        cache.body[i] = cut >= 0 ? rawName.substring(cut + 1) : rawName;
      }
      tag = had;
      name = cache.body[i]!;
    }
    // 붕당 렌즈의 단체 칸(단 갈래 2 — 이름 "줄임\t이름"): 웹 `_groupCells(lens)`의 글 규칙. 색 점(연정 · 짝 모름)이 있으면 점 자리(점 수 × 8 + 2)를
    // 빼고 온 이름 → 줄임('새·노' · 짝 모름은 첫 글자) → 없음, 점이 없으면 온 이름 → 첫 글자(+8) → 없음 — 어느 쪽도 글자를 자르지 않는다.
    // 집권 단 · 실권 단의 단체 칸(단 갈래 5 ~ 7 — 웹 `_groupCells`)도 같은 규칙 · 같은 구역 43이다(8.5px · 온 이름 +10).
    final gband = kind == CellKind.common ? CellStyle.bandOf(p.style) : 0;
    final group = kind == CellKind.common && (gband == CellStyle.lensGroup || CellStyle.isGroupBand(gband));
    final dotN = group ? (_lensItem(host.id, lane, p.seq)?.dots.length ?? 0) : 0;
    final dotsW = dotN > 0 ? dotN * 9.0 + 3 : 0.0;
    String lensShort = '';
    if (group) {
      var had = cache.tag[i];
      if (had == null) {
        final cut = rawName.indexOf('\t');
        had = cut >= 0 ? rawName.substring(0, cut) : '';
        cache.tag[i] = had;
        cache.body[i] = cut >= 0 ? rawName.substring(cut + 1) : rawName;
      }
      lensShort = had;
      name = cache.body[i]!;
    }
    // 기관 칸은 폭을 10.5로 재고 글자는 10으로 그린다(명세 3-6 사) — 두 생김새를 따로 둔다.
    final sizeLook = _lookOf(kind, p.color, p.style, look.measure ?? look.size);
    double? nameW;
    // 꼬리표 밑 흰 사슬의 칸은 글을 제 셈([_chainText] — 왼쪽 맞춤 · 사슬 글꼴)으로 한다 — 칸 층 글꼴로 재지 않는다(글줄 준비를 헛되이 쓰지 않게).
    if (name.isNotEmpty && !_hideNames && _chainSlot < 0) {
      final slot = cache.nameW;
      final had = slot[i];
      if (!had.isNaN) {
        nameW = had;
      } else {
        nameW = c.text.widthOf(name, sizeLook);
        if (nameW != null) slot[i] = nameW;
      }
    }
    if (nameW != null) {
      if (wholeW >= nameW + look.fullPad + dotsW) {
        p.text = name;
        p.textW = nameW;
      } else if (kind == CellKind.dynasty) {
        // 왕조 칸은 온 이름이 안 들면 끝의 (왕조 | 왕가 | 가문 | 家 | 朝)를 뗀 짧은 이름으로 한 번 더 잰다.
        final shorts = cache.alt;
        final short = shorts[i] ??= _shortDynasty(name);
        double? shortW;
        if (short.isNotEmpty) {
          final slot = cache.altW;
          final had = slot[i];
          if (!had.isNaN) {
            shortW = had;
          } else {
            shortW = c.text.widthOf(short, sizeLook);
            if (shortW != null) slot[i] = shortW;
          }
        }
        if (shortW != null && wholeW >= shortW + 12) {
          p.text = short;
          p.textW = shortW;
        }
      } else if (group) {
        double? shortW;
        if (lensShort.isNotEmpty) {
          final slot = cache.altW;
          final had = slot[i];
          if (!had.isNaN) {
            shortW = had;
          } else {
            shortW = c.text.widthOf(lensShort, sizeLook);
            if (shortW != null) slot[i] = shortW;
          }
        }
        if (shortW != null && wholeW >= shortW + dotsW + (dotN > 0 ? look.fullPad : look.shortPad)) {
          p.text = lensShort;
          p.textW = shortW;
          p.fixed = true; // 웹의 `fixed: text !== c.name` — 유령선 · 조명 경계를 비켜 옮기지 않는다(자리는 아래에서 가운데로)
        }
      }
      if (p.text.isEmpty && kind != CellKind.dynasty && !group) {
        final firsts = cache.alt;
        final first = firsts[i] ??= name.substring(0, 1);
        double? firstW;
        final slot = cache.altW;
        final had = slot[i];
        if (!had.isNaN) {
          firstW = had;
        } else {
          firstW = c.text.widthOf(first, sizeLook);
          if (firstW != null) slot[i] = firstW;
        }
        if (firstW != null && wholeW >= firstW + look.shortPad) {
          // 지금 연표는 온 이름을 왼쪽 맞춤해 잘라 보인다(is-clip · text-overflow: clip) — 들 만큼의 앞글자를 그린다.
          // 자르는 자리는 칸의 안쪽 상자(테두리 안)이고 글은 테두리 1 + 칸 여백 1 + 글 여백 1에서 시작한다 → 들 폭은 w − 4(좁은 칸은 w − 2).
          final room = wholeW - (p.thin ? 2 : 4);
          // 자를 폭이 지난 장면과 같으면(옆으로 끌기만 할 때) 그때의 답을 그대로 쓴다.
          String cut;
          double? cutW;
          if (cache.clipRoom[i] == room) {
            cut = cache.clipText[i]!;
            cutW = cut.isEmpty ? null : cache.clipW[i];
          } else {
            cut = _clipName(c, name, sizeLook, room);
            cutW = cut.isEmpty ? null : c.text.widthOf(cut, sizeLook);
            if (cut.isEmpty || cutW != null) {
              cache.clipRoom[i] = room;
              cache.clipText[i] = cut;
              cache.clipW[i] = cutW ?? 0;
            }
          }
          p.text = cut.isEmpty ? first : cut;
          p.textW = (cut.isEmpty ? firstW : cutW) ?? firstW;
          p.fixed = true;
        }
      }
    }
    // 두 단 띠의 조각(다듬기 판 paintCells의 이름 자리): 이름은 칸이 시작하는 조각부터(화면에 든 것만) 이름과 여백이 드는 첫 조각에만 —
    // 드는 조각이 없으면 화면에 든 첫 조각(그 조각의 폭으로 앞글자 · 자른 이름 — 칸 층의 다른 꼴 그대로). 다른 조각은 이름을 비운다.
    final pieces = p.cell?.pieces;
    if (pieces != null && p.text.isNotEmpty && nameW != null) {
      (double, double)? pick, seenFirst;
      for (final (l, r, _) in pieces) {
        final seen = math.min(r, hi) - math.max(l, lo);
        if (seen <= 0) continue;
        seenFirst ??= (l, r);
        if (seen >= nameW + look.fullPad + dotsW) {
          pick = (l, r);
          break;
        }
      }
      pick ??= seenFirst;
      if (pick == null || (pick.$1 - p.wholeL).abs() > .25) {
        p.text = '';
        p.textW = 0;
        p.fixed = false;
      }
    }
    // 예속 칸은 이어 붙은 조각에 이름을 다시 쓰지 않는다(맨 앞 조각에만).
    if (kind == CellKind.dep && p.jl) {
      p.text = '';
      p.textW = 0;
      p.fixed = false;
    }
    // 체계 이름표: 그 체계의 첫 칸(이어 붙지 않은 칸) 또는 화면 왼쪽에 걸린 첫 칸에만, 이름과 함께 들 때만.
    if (tag.isNotEmpty && p.text.isNotEmpty && !p.fixed) {
      final key = row << 8 | lane;
      final firstOfScheme = p.style & CellStyle.joinLeft == 0 || p.atL;
      if (firstOfScheme && !_tagged.contains(key)) {
        final slot = cache.tagW;
        var measured = slot[i].isNaN ? null : slot[i];
        if (measured == null) {
          measured = c.text.widthOf(tag, _schLook);
          if (measured != null) slot[i] = measured;
        }
        if (measured != null && wholeW >= measured + 12 + p.textW + look.fullPad) {
          p.tag = tag;
          p.tagW = measured;
          p.fixed = true; // 딱지가 붙으면 이름은 딱지 뒤의 남은 자리에 못 박힌다(지금 연표의 fixed)
          _tagged.add(key);
        }
      }
    }

    // ---- 이름표 글자의 가운데(비키기 전) ----
    if (p.tagW > 0) {
      final nameLeft = p.l + p.bl + p.tagW + 12;
      p.center = nameLeft + (p.r - p.br - nameLeft) / 2;
    } else if (p.fixed || !look.centered) {
      p.center = p.l + (kind == CellKind.dep ? 6 : (p.thin ? 3 : 4)) + p.textW / 2;
    } else {
      final nl = p.cutL || p.cutR ? math.max(p.wholeL, lo) : p.l, nr = p.cutL || p.cutR ? math.min(p.wholeR, hi) : p.r;
      p.center = (nl + nr) / 2;
    }
    // 단체 칸: 점(첫 점 왼쪽 여백 2 · 6px · 8px 간격)과 이름(좌우 4)을 한 덩어리로 칸 가운데에(웹의 flex 가운데 맞춤 그대로).
    // 점은 칸에 다 들 때만(일부만 보이면 단체 수를 잘못 읽는다) — 아니면 칠만.
    // 집권 · 실권 단의 칸은 이름의 좌우 여백이 3(점 뒤면 왼쪽 2 — css `.k-group b { padding: 0 3px }` · `.gd + b { padding-left: 2px }`).
    if (group) {
      final nl = p.cutL || p.cutR ? math.max(p.wholeL, lo) : p.l, nr = p.cutL || p.cutR ? math.min(p.wholeR, hi) : p.r;
      p.dots = dotN > 0 && (p.text.isNotEmpty || wholeW >= dotsW + 6) ? dotN : 0;
      final dotsSpan = p.dots > 0 ? p.dots * 9.0 : 0.0;
      final lensPad = gband == CellStyle.lensGroup;
      final padL = lensPad ? 4.0 : 3.0, padR = lensPad ? 4.0 : 3.0;
      final start = nl + (nr - nl - dotsSpan - (p.text.isEmpty ? 0 : p.textW + padL + padR)) / 2;
      p.dotsLeft = start + 3;
      if (p.text.isNotEmpty) p.center = start + dotsSpan + padL + p.textW / 2;
    }

    // ---- 미정 끝(unkCell) ----
    final unkS = p.style & CellStyle.unkStart != 0 && !p.openL && !p.cutL;
    final unkE = p.style & CellStyle.unkEnd != 0 && !p.openR && !p.cutR;
    if (unkS || unkE) {
      final tw = group
          ? (p.text.isEmpty ? (p.dots > 0 ? dotsW : null) : p.textW + (p.dots > 0 ? dotsW : 0))
          : (p.text.isEmpty ? null : (p.fixed && p.tagW == 0 ? wholeW : p.textW));
      final f = math.max(3.0, math.min(math.min(Look.fuzzyFade, wholeW * 0.4), tw != null ? (wholeW - tw) / 2 : wholeW * 0.3));
      p.fade = _Fade(unkS ? f : 0, unkE ? f : 0, p.jl ? 0.35 : 0, p.jr ? 0.35 : 0);
    }
    // 앞 칸의 끝이 미정이면 사이 구분선도 점선(u-l).
    p.uLeft = p.jl && before != null && t.cellStyle[before.index] & CellStyle.unkEnd != 0;

    // ---- 고른 칸 · 가문 칸 ----
    // 눌린 칸의 짙은 모습은 켜짐/꺼짐뿐이라(바탕 · 테두리가 한 번에 바뀐다) 반쯤 켜진 조명은 아직 눌린 칸으로 치지 않는다.
    final look2 = _em.look;
    if (p.seq >= 0 && (hostSpots.isNotEmpty || look2.cell != null)) {
      final ref = cache.refOf(i, kind, lane);
      for (int s = 0; s < hostSpots.length; s++) {
        if (hostSpots[s].cell == ref && hostSpots[s].glow > .5) p.spot = true;
      }
      if (look2.cell == ref && look2.band == host.id) p.spot = true;
    }
    // 가문 강조(가문 창의 그 가문)와 가문 조명(파 포함 묶음 — 결정 7 A)이 같은 진한 모습(is-house)을 쓴다.
    p.house = look2.isHouse(p.houseId);
  }

  /// 지도자 칸의 표기(`HT.leaderLabel`)를 그대로 옮긴 것. [base]는 타일에 실린 기본 표기(`auto`)다.
  /// 고른 표기의 글이 비어 있으면 기본 표기로 물러난다(지금 연표의 `s || c.name || c.temple || …`).
  String leaderTextOf(String base, String temple, String title, String given, int ordinal) {
    var s = switch (_leaderLabel) {
      'temple' => temple,
      'title' => title,
      'given' => given,
      'temple-title' => [temple, title].where((v) => v.isNotEmpty).join(' '),
      'all' => [temple, title, given].where((v) => v.isNotEmpty).join(' '),
      _ => '',
    };
    if (s.isEmpty) s = base;
    if (_leaderOrdinal && ordinal >= 0) s = '$ordinal대 $s';
    return s;
  }

  /// 타일의 칸 하나에 지어 둔 이름(표기 · 대수가 바뀌면 [_cellsOf]가 비운다).
  ///
  /// **못 찾은 답은 보관하지 않는다**: [beginFrame]은 메움(cover)으로 깔리는 타일의 구역 46을 읽지 않는데(`d.isCover`),
  /// 그리개는 메움 타일도 [paintTile]로 그린다. 그때 굳혀 두면 그 타일이 나중에 제 단계의 주 타일이 되어 구역 46이
  /// 실려 와도 그 칸만 기본 이름으로 남는다 — 이번 장면만 기본 표기로 그리고 다음 장면에 다시 묻는다.
  /// 구역 46을 그제야 찾은 칸은 기본 표기로 재어 둔 폭 · 잘라 둔 글도 함께 버린다(글이 달라지면 폭도 달라진다).
  String _leaderNameOf(_TileCells cache, int i, int band, int lane, int seq, String base) {
    final slot = cache.leader;
    final had = slot[i];
    if (had != null) return had;
    final extra = seq < 0 || _leaderOf.isEmpty ? null : _leaderOf[(band, CellKind.leader, lane, seq)];
    if (extra == null) return leaderTextOf(base, '', '', '', -1);
    cache.forgetWidth(i);
    return slot[i] = leaderTextOf(base, extra.$1, extra.$2, extra.$3, extra.$4);
  }

  /// 온 이름을 왼쪽 맞춤해 잘라 보이는 칸: [room]px 안에 드는 앞글자만.
  String _clipName(PaintContext c, String name, TextLook look, double room) {
    if (room <= 0) return '';
    int lo = 1, hi = name.length, best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final w = c.text.widthOf(name.substring(0, mid), look);
      if (w == null) break;
      if (w <= room) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best == 0 ? '' : name.substring(0, best);
  }

  /// 이설의 유령 구분선 고르기와 이름표 비킴(지금 연표 `altMarks`). 결과는 [_lines]와 칸의 `dx` · `hasAlt`.
  void _planAlts(PaintContext c, int row, int kind, int lane, double minW, double lo, double hi) {
    _lines.clear();
    if (!showAlt) return; // '이설' 체크가 꺼지면 유령 구분선도 이름 밑 점선도 없다(지금 연표 `_altPlan`의 alt). 모호한 칸의 무늬는 그대로
    // 자리는 [_Placed.reset]이 이미 처음 상태로 되돌려 두었다 — 이설이 없으면 곧바로 물러난다(가장 흔한 길).
    final ghosts = _ghostsOf[_key(row, kind, lane)];
    if (ghosts == null || ghosts.isEmpty) return;
    final drawn = [for (int k = 0; k < _placedCount; k++) if (_placed[k].w >= minW) _placed[k]];
    if (drawn.isEmpty) return;
    final edges = <double>[for (final p in drawn) ...[p.l, p.r]];
    final miss = <_Placed>{};
    for (final m in ghosts) {
      final owner = _ownerOf(drawn, m);
      if (owner == null) continue;
      if (owner.w < _altMinW) continue; // 좁은 칸에는 표식을 달지 않는다(문턱 둘은 아직 없다)
      double near = double.infinity;
      for (final e in edges) {
        final d = (e - m.x).abs();
        if (d < near) near = d;
      }
      final f = owner.fade;
      final inFade = f != null && ((f.fl > 0 && m.x >= owner.l - 1 && m.x <= owner.l + f.fl + 1) || (f.fr > 0 && m.x >= owner.r - f.fr - 1 && m.x <= owner.r + 1));
      if (m.x < lo || m.x > hi - 1 || near < _altGap || inFade) {
        miss.add(owner);
        continue;
      }
      if (_lines.any((q) => (q.x - m.x).abs() < _altGap)) continue; // 같은 자리의 이설 — 선 하나
      _lines.add(m);
    }
    // 이름표 비킴: 선에서 3px 떨어지는 자리 가운데 가장 적게 움직이는 곳으로.
    for (final p in drawn) {
      if (p.text.isEmpty || p.textW <= 0) continue;
      final center = p.center;
      final inside = [for (final m in _lines) if (m.x >= p.l && m.x < p.r) m];
      if (inside.isEmpty) continue;
      final hits = [for (final m in inside) if (m.x + 1 > center - p.textW / 2 - _altGap && m.x < center + p.textW / 2 + _altGap) m];
      if (hits.isEmpty) continue;
      double? to;
      if (!p.fixed) {
        var segs = <(double, double)>[(p.l + 1 + _altGap + p.textW / 2, p.r - 1 - _altGap - p.textW / 2)];
        for (final m in inside) {
          final a = m.x - _altGap - p.textW / 2, b = m.x + 1 + _altGap + p.textW / 2;
          segs = [
            for (final s in segs) ...[(s.$1, math.min(s.$2, a)), (math.max(s.$1, b), s.$2)],
          ].where((s) => s.$2 >= s.$1).toList();
        }
        for (final s in segs) {
          final v = center.clamp(s.$1, s.$2);
          if (to == null || (v - center).abs() < (to - center).abs() - 1e-9) to = v;
        }
      }
      if (to != null) {
        p.dx = to - center;
      } else {
        _lines.removeWhere(hits.contains);
        miss.add(p);
      }
    }
    for (final p in miss) {
      // 선을 하나라도 그은 칸은 이름 밑 점선을 달지 않는다.
      if (_lines.any((m) => m.x >= p.l && m.x < p.r)) continue;
      if (p.text.isEmpty || p.fixed || p.textW < 4) continue;
      p.hasAlt = true;
    }
  }

  _Placed? _ownerOf(List<_Placed> drawn, _Ghost m) {
    if (m.seq >= 0) {
      // 두 단 띠의 조각은 한 칸이 여러 무리(층 전체 · 제 단)에 나뉘므로 그 경계를 품은 조각만 주인이다(다른 무리가 그린다).
      final pieces = _pieceDivs != null;
      for (final p in drawn) {
        if (p.seq == m.seq && (!pieces || (m.x >= p.l - .5 && m.x < p.r + .5))) return p;
      }
      return null;
    }
    for (final p in drawn) {
      if (m.x >= p.l && m.x < p.r) return p;
    }
    return null;
  }

  /// 모호한 칸의 무늬 구간(지금 연표 `altRowPlan`의 zones): 그 단의 모든 칸에서 구간을 모아 칸마다 이름표를 비켜 자른다.
  void _planZones(int row, int kind, int lane, double minW, double top, double height) {
    // 조각과 좌우 점선은 [_Placed.reset]이 이미 비워 두었다.
    if (kind == CellKind.organ) return; // 기관 칸은 제 빗금만 — 모호한 구간을 그리지 않는다
    // 구간은 (시작 · 끝 · 무늬 갈래)를 나란한 세 목록에 담는다 — 장면마다 구간마다 상자를 만들지 않는다.
    _spanA.clear();
    _spanB.clear();
    _spanLook.clear();
    final carried = _zonesOf[_key(row, kind, lane)];
    if (carried != null) {
      for (int z = 0; z < carried.length; z++) {
        _spanA.add(carried[z].a);
        _spanB.add(carried[z].b);
        _spanLook.add(carried[z].look);
      }
    }
    for (int k = 0; k < _placedCount; k++) {
      final p = _placed[k];
      if (p.w < minW) continue;
      // 연대 폭이 없고 확실성만 적힌 칸은 칸 전체가 구간이다(zoneCls의 둘째 갈래).
      if (p.style & CellStyle.range != 0) continue;
      final look = p.style & CellStyle.legend != 0 ? 1 : (p.style & CellStyle.estimated != 0 ? 0 : -1);
      if (look < 0) continue;
      _spanA.add(p.l - 0.5);
      _spanB.add(p.r + 0.5);
      _spanLook.add(look);
    }
    if (_spanA.isEmpty) return;
    for (int k = 0; k < _placedCount; k++) {
      final p = _placed[k];
      if (p.w < minW) continue;
      final inL = p.l + p.bl, inR = p.r - p.br;
      final center = p.center + p.dx;
      final hasInk = p.text.isNotEmpty;
      final inkL = !hasInk ? 0.0 : (p.fixed ? inL : center - p.textW / 2 - _altGap - 0.5);
      final inkR = !hasInk ? 0.0 : (p.fixed ? inR : center + p.textW / 2 + _altGap + 0.5);
      for (int z = 0; z < _spanA.length; z++) {
        final za = _spanA[z], zb = _spanB[z];
        if (p.l > za + 0.25 && p.l < zb - 0.25) p.zl = true;
        if (!p.jr && p.r > za + 0.25 && p.r < zb - 0.25) p.zr = true;
        final a = math.max(za, inL), b = math.min(zb, inR);
        if (b - a < 1) continue;
        if (!hasInk) {
          if (b - a >= 1) p.layers.add((a, b, _spanLook[z]));
          continue;
        }
        final a1 = a, b1 = math.min(b, inkL);
        if (b1 - a1 >= 1) p.layers.add((a1, b1, _spanLook[z]));
        final a2 = math.max(a, inkR), b2 = b;
        if (b2 - a2 >= 1) p.layers.add((a2, b2, _spanLook[z]));
      }
    }
  }

  /// 띠 몸통 밖 바탕에 서는 칸의 종류인가(세로줄 얹기 걸음 4): 줄 직속 기관 칸 · 꼬리표 밑 흰 사슬로 뺀 왕조 · 지위 칸(렌즈의 지위 칸도 지위로 온다).
  /// 띠 몸통 안의 칠 없는 칸(지도자 · 내각 · 시기 · 집권 단)은 몸통 칠이 불투명이라 들지 않는다.
  static bool _onGround(PaintContext c, int kind, int row) {
    if (kind == CellKind.organ) return true;
    if (kind != CellKind.dynasty && kind != CellKind.rank) return false;
    final geo = c.layout.geo(row);
    return kind == CellKind.dynasty ? geo.dynastyChained : geo.rankChained;
  }

  /// 띠 [host]의 꼬리표 몸통 아랫변(화면 y — [TagLook.bodyBottom] · 띠 층의 `bodyBottomOf`와 같은 셈). 그 밑은 띠 아래 바탕이다.
  static double _bodyBottomPx(PaintContext c, _Host host, int row) {
    final layout = c.layout;
    final y = TagLook.bodyBottom(layout.geo(row), host.look,
        oldStore: !(layout.spec(row)?.cellRows ?? false), loose: layout.conditions.density < 0, sub: host.sub);
    return c.v.yOf(layout.rowTop(row) + y);
  }

  void _drawCell(PaintContext c, _TileCells cache, _Host host, int row, int kind, int lane, _Placed p, double top, double height, double alpha, List<em.Spot> spots) {
    final look = _lookFor(kind);
    final l = p.l, r = p.r, b = top + height;
    final color = p.color;

    // 집권 · 실권 단의 단체 칸(단 갈래 5 ~ 7): 실권 칸은 옅은 테두리 자리에 그 색 64% + 먹의 짙은 선(웹 `.is-real`의 --edge-soft).
    final gband = kind == CellKind.common ? CellStyle.bandOf(p.style) : 0;
    final groupRow = CellStyle.isGroupBand(gband), real = gband == CellStyle.groupReal;

    // ---- 맞히기 · 커서 비춤의 자리 기록(계약 밖 — 앱 틀이 [hitStrips]로 읽는다) ----
    // 순번을 싣지 않은 칸은 참조가 빈 글이다(맞히기는 되고 상세 창은 열 수 없다).
    // 단체 단의 칸은 두 단(집권 · 실권)의 순번이 따로라 단마다 다른 앞말 — 커서 비춤이 다른 단의 같은 순번 칸을 함께 비추지 않게.
    final ref = p.seq < 0 ? '' : (groupRow ? '${lane == 3 ? 'real' : 'power'}:${p.seq}' : cache.refOf(p.index, kind, lane));
    // 렌즈 칸은 누르면 그 제도 · 단체의 창(구역 43의 uid) — 이름은 줄인 글이 아니라 온 이름.
    final lensItem = kind == CellKind.common ? _lensItem(host.id, lane, p.seq) : null;
    final item = kind == CellKind.common
        ? (lensItem == null ? null : (lensItem.uid, cache.body[p.index] ?? p.text))
        : (p.seq < 0 || _refOf.isEmpty ? null : _refOf[(host.id, kind, lane, p.seq)]);

    // 단체 계보 창에서 고른 단체(웹 `.tl.group-focus` — setGroupFocus): 그 단체가 든 칸만 안쪽 1.5px 진한 테두리 · 먹빛 글, 나머지 단체 칸은 .4.
    // 연정 칸은 첫째 단체의 uid만 실려 있으므로, 둘째부터는 조명이 켜진 띠(고른 단체의 나라)에서 색 점의 색으로 가린다(같은 나라의 단체 색은 겹치지 않게 내보낸다).
    final focusOn = _groupFocus != null && lensItem != null && (groupRow || gband == CellStyle.lensGroup);
    final focused = focusOn && (lensItem.uid == _groupFocus || (spots.isNotEmpty && lensItem.dots.any((d) => d & 0xffffff == _groupFocusColor)));

    // 같은 사람의 칸(건의 8의 6-나): 고른 칸의 짝이거나 올린 칸의 짝이면 테를 두르고 고름의 흐림에서 뺀다.
    p.twin = ref.isNotEmpty && (_em.look.isTwin(host.id, ref) || (hotTwins?.contains('${host.id}|$ref') ?? false));

    // ---- 밝기: 띠의 흐림 × 단의 몫, 기간 조명이 있으면 구간 안팎으로 갈린다(명세 06의 3-1 · 3-3) ----
    final dim = _dimOf(c, p, host.id, kind, focusOn && !focused ? alpha * .4 : alpha, spots, item?.$1 ?? '');
    // 빌린 칸: 칸 전체(칠 · 세로 금 · 테 · 무늬 · 이름)가 .72 — 서고 미리보기 `.tl-cell.is-borrowed { opacity: .72 }`(common.css 2495).
    // 실권 기간의 지도자 칸은 .55(`.k-leader.is-ousted` — 2496). 둘 다면 css의 셈(더 구체한 규칙이 이김)대로 .55 하나다(곱하지 않는다).
    if (p.ousted) {
      dim.scale(oustedAlpha);
      c.debug?.note('실권칸', '$kind:$row:$lane ${_r1(l)},${_r1(top)},${_r1(p.w)},${_r1(height)}');
    } else if (p.borrowed) {
      dim.scale(borrowedAlpha);
    }

    if (_drawnCount == _drawn.length) _drawn.add(_Drawn());
    _drawn[_drawnCount++]
      ..band = host.id
      ..row = row
      ..kind = kind
      ..ref = ref
      ..uid = item?.$1 ?? ''
      ..name = item?.$2 ?? p.text
      ..l = l
      ..t = top
      ..r = r
      ..b = b
      ..houseId = p.houseId
      ..houseName = p.houseName
      ..houseColor = p.houseColor
      ..textL = 0
      ..textW = 0
      ..chain = false;
    final drawnAt = _drawnCount - 1;
    // 렌즈 칸의 메아리: 올린 칸과 같은 갈래의 칸은 모든 나라에서 올린 모습(웹의 `.is-fam`).
    final fam = kind == CellKind.common && _echoFam.isNotEmpty && lensItem != null && lensItem.fam == _echoFam;
    final hot = fam || (hotCell != null && ref.isNotEmpty && hotCell == '${host.id}|$ref');

    final soft = kind == CellKind.phase ? _phaseSoft : (real ? _realSoftOf(color) : _softOf(color));
    final radiusL = p.thin ? (p.jl ? 0.0 : (p.jr ? 4.0 : 2.0)) : (p.jl || p.openL || p.cutL ? 0.0 : look.radius);
    final radiusR = p.thin ? (p.jr ? 0.0 : (p.jl ? 4.0 : 2.0)) : (p.jr || p.openR || p.cutR ? 0.0 : look.radius);
    var (fill, edgeBase) = _skin(kind, p.style, color, soft, p.thin, p.jl || p.jr, p.alt, p.spot, p.house);
    // 올림: 테두리 --edge · 바탕은 왕조 50% · 렌즈 칸 56% · 그 밖 30%(명세 3-6의 올림 · 고름 · 웹의 `.k-lens:hover`).
    // 좁은 렌즈 칸(is-thin)은 css 차례상 올려도 테 없는 55% 그대로다.
    // 집권 · 실권 단의 칸은 테두리만 --edge로(웹 `.k-group:hover` — 칠은 그대로 · 실권 칸의 --edge는 그 색 52% + 먹).
    if (hot && groupRow) {
      if (!p.thin) edgeBase = real ? _realEdgeOf(color) : _edgeOf(color);
    } else if (hot && !p.spot && !p.house && !(kind == CellKind.common && p.thin)) {
      fill = mixSrgb(color, Look.paper, kind == CellKind.dynasty ? .50 : (kind == CellKind.common ? .56 : .30));
      edgeBase = _edgeOf(color);
    }
    final edge = p.spot || p.house ? _edgeOf(color) : (focused && !p.thin ? (real ? _realEdgeOf(color) : _edgeOf(color)) : edgeBase);
    final bw = p.spot || p.house ? (kind == CellKind.dynasty ? 1.0 : 1.5) : (focused && !p.thin ? 1.5 : 1.0);
    if (focused) c.debug?.note('단체고름', '$row:$lane ${lensItem.uid}');
    // 붕당 렌즈의 단체 칸(단 갈래 2): 연정은 위 반 첫째 · 아래 반 둘째 단체 색, 짝을 모르는 연정은 위 반 제 색 · 아래 반 종이빛
    // (42% · 올리면 56% — 웹의 `.k-group.is-two` · `.is-solo` · `.k-lens.is-two:hover`. css 차례상 좁은 칸도 두 칠 그대로).
    // 집권 단의 연정 칸(갈래 6)은 위아래 두 색 42%(올려도 그대로) · 실권 칸끼리 겹친 칸(갈래 7 + 둘째 색)은 78%(웹 `.is-real.is-two`).
    final group = kind == CellKind.common && lensItem != null && (gband == CellStyle.lensGroup || groupRow);
    // 땅 위 칸(기관 칸 · 꼬리표 밑 흰 사슬의 왕조 · 지위 칸 — 칠 없이 테 · 빗금만이거나 옅은 칠): 띠 몸통 밖 바탕에 선 몫에는 칠 · 무늬 · 테 전에
    // 그 자리 바탕색 종이를 깐다(리메이크 4단계 세로줄 얹기 걸음 4 — 맨 아래 연도 세로줄이 칸 안에 비치지 않게 · paint/grounds.dart).
    // 띠 몸통 안의 몫(그 층을 가진 띠의 기관 칸)은 몸통 칠이 이미 불투명이라 깔지 않는다(깔면 몸통 빛이 바탕색으로 바뀐다).
    if (_onGround(c, kind, row)) {
      final from = math.max(top, _bodyBottomPx(c, host, row));
      if (b > from) c.grounds.paper(c.quads, l, from, r, b);
    }
    if (group && !groupRow && (lensItem.color2 != 0 || lensItem.solo)) {
      final t = gband == CellStyle.lensGroup ? (hot ? .56 : .42) : (real && !lensItem.solo ? .78 : .42);
      final under = lensItem.solo ? Look.paper : mixSrgb(0xff000000 | lensItem.color2, Look.paper, t);
      _fill2(c, l, top, r, b, mixSrgb(color, Look.paper, t), under, radiusL, radiusR, p.fade, dim);
    } else if (fill != 0) {
      _fill(c, l, top, r, b, fill, radiusL, radiusR, p.fade, dim);
    }
    // 집권 · 실권 단의 칸: 그 기간 층 아랫변에 2px 밑줄(리메이크 2부 · 목업 서고 power 사슬 — 단체 색 80% + 먹 20% · 감독 "먹을 20퍼센트 · 조금 연하게 · 약간의 통일성"
    // → 나라 색 계열을 견준 뒤 감독 "그냥 단체 색으로").
    if (groupRow) {
      final (ux0, uy0, ux1, uy1) = _underSpan(p, l, r, b);
      c.quads.add(ux0, uy0, ux1, uy1, withAlpha(mixOklab(color, Look.ink, powerLine), dim.outside));
      c.stats.shapes++;
      c.debug?.note('단체밑줄', '${host.id} ${_r1(ux0)},${_r1(uy0)},${_r1(ux1 - ux0)},${_r1(uy1 - uy0)}');
    }
    _patternOf(c, kind, p, color, soft, top, b, dim);
    final unkS = p.fade != null && p.fade!.fl > 0;
    // 꼬리표 갈래 E: 칸은 흰 층 안의 각진 칸 — 상자 테 없이 칸 사이의 세로 금(먹 20)만. 고른 칸 · 가문 · 단체 고름(굵은 테)만 테를 둘러 드러낸다.
    final boxed = p.spot || p.house || focused;
    if (!boxed) {
      _floorDividers(c, l, top, r, b, dim, p, dashL: p.openL || p.zl || unkS || p.uLeft, under: groupRow ? 2 : 0);
    } else if (edge != 0) {
      final unkE = p.fade != null && p.fade!.fr > 0;
      _border(
        c, l, top, r, b, edge, radiusL, radiusR, fade: p.fade, dim: dim, width: bw,
        // 이어 붙은 쪽: 왼쪽은 가는 구분선, 오른쪽은 테두리를 지운다. 좁은 칸(is-thin)은 이어 붙은 쪽에 아예 세로 변이 없다.
        left: p.cutL || (p.thin && p.jl) ? null : (p.jl ? (kind == CellKind.common ? withAlpha(soft, .70) : _dividerOf(soft)) : edge),
        right: (p.cutR || (p.jr && kind != CellKind.dynasty)) ? null : edge,
        // 점선(c-l · z-l)이 파선(unk-s)을 이긴다 — css의 차례(C:980 · C:1866이 뒤).
        dashLeft: p.openL || p.zl ? 1.0 : (unkS || p.uLeft ? 2.0 : 0),
        dashRight: p.openR || p.zr ? 1.0 : (unkE ? 2.0 : 0),
      );
    }
    if (p.borrowed) _borrowedTop(c, host, row, kind, lane, l, top, r, p.wholeL, dim);
    // 칸의 정통성(칸 그림 갈래 걸음 3): 이 칸이 피후견 칸인 섭정 기간의 밑줄 · 주장 칸의 바탕 빗금(칸 금 · 테를 비켜).
    if (p.regents.isNotEmpty) _regentLines(c, host, row, p, l, r, b, dim, boxed ? bw : 0);
    if (p.claim) _claimCell(c, p, l, top, r, b, dim, boxed ? bw : 0);
    // 같은 사람의 칸(건의 8의 6-나 · 2026-10-13): 먹 1.5px 테 · 둥근 6 — 바탕은 그대로, 이어 붙은 칸이어도 네 모서리를 둥글게.
    // 타일에 걸쳐 잘린 쪽은 세로 변 없이(다른 조각이 이어 그린다).
    if (p.twin) {
      _border(
        c, l, top, r, b, Look.ink, p.cutL ? 0 : 6, p.cutR ? 0 : 6, dim: dim, width: 1.5,
        left: p.cutL ? null : Look.ink, right: p.cutR ? null : Look.ink,
      );
      c.debug?.note('같은사람', '${host.id}|$ref ${_r1(l)},${_r1(top)},${_r1(r - l)}');
    }
    // 단체 칸의 색 점(웹의 `.gd` — 6px 동그라미 · 제 색 칠 + 1px 테두리(그 색 64% + 먹)). 타일에 걸친 칸은 이름처럼 왼쪽 조각만.
    if (group && p.dots > 0 && !(p.cutL && !p.atL)) {
      final dy = top + (height - 6) / 2;
      for (int k = 0; k < p.dots && k < lensItem.dots.length; k++) {
        _dot(p.dotsLeft + k * 9, dy, lensItem.dots[k], dim.at(p.dotsLeft + k * 9 + 3));
        c.debug?.note('색점', '$row ${_r1(p.dotsLeft + k * 9)},${_r1(dy)} ${(lensItem.dots[k] & 0xffffff).toRadixString(16).padLeft(6, '0')}');
      }
    }
    c.stats.shapes++;
    c.debug?.note('칸', '$kind:$row:$lane ${_r1(l)},${_r1(top)},${_r1(p.w)},${_r1(height)}');
    c.debug?.note('칸이음', '$kind:$row:$lane jl=${p.jl} jr=${p.jr} zl=${p.zl} zr=${p.zr} st=${p.style} seq=${p.seq} a=${_r1(p.a)} b=${_r1(p.b)} i=${p.index}');
    // 밝기는 묶음의 색 알파에 곱해진다 — 칸의 왼쪽 끝과 오른쪽 끝에서 잰 값(조명 경계에 걸치면 둘이 다르다).
    c.debug?.note('칸밝기', '$kind:$row:$lane ${(dim.at(l + 1) * 1000).round()},${(dim.at(r - 2) * 1000).round()}');

    // ---- 글자 ----
    if (p.text.isEmpty) return;
    // 타일에 걸친 칸은 왼쪽 조각만 이름을 쓴다(오른쪽 조각은 같은 이름을 겹쳐 쓰게 된다) — 칸의 시작이 화면 왼쪽 밖이면 화면 왼쪽 끝에 닿은 조각이 쓴다.
    // 예전에는 그 조각을 `p.l > c.left`로 가렸는데, 칸 상자는 화면 왼쪽에서 3px 안쪽(lo)부터라 p.l이 c.left 이하가 되는 일이 없어
    // 시작이 화면 밖인 긴 칸(크게 확대한 지도자 · 시기 칸)은 어느 조각도 이름을 쓰지 않았다(감독 건의 2026-10-14 10번 — 3년 남짓 확대하면 글자가 사라짐).
    // 두 단 띠의 조각은 이음매에서 시작해도 이름 자리일 수 있어 타일 경계만 본다([_Placed.tileL] — 보통 칸은 cutL과 같음).
    if (p.tileL && !p.atL) return;
    final nameLook = _lookOf(kind, color, p.style, look.size);
    final y = top + (height - look.size * 1.2) / 2;
    final at = p.center + p.dx - p.textW / 2;
    if (p.tagW > 0) {
      final bl = p.thin ? 0.0 : 1.0;
      _tagBox(c, l + bl + 3, top + (height - (8 * 1.2 + 6)) / 2, p.tagW + 6, dim.at(l + bl + 5));
      c.later.add('sch', p.tag, _schLook, l + bl + 6, top + (height - 8 * 1.2) / 2, dim.at(l + bl + 5));
    }
    // 렌즈의 무리(지위 · 지도자 꼴로 그리는 것도)는 제 열쇠로 — 같은 줄의 옛 지도자 · 지위 칸 이름과 비킴을 섞지 않는다.
    // 두 단 띠의 조각은 제 열쇠로 센다([_slotBits] — 층 전체 0x80 · 제 단 0x40: 세로 자리가 다르고, 같은 줄의 한 단 띠보다 먼저 그린다).
    // 직위 줄 더(종류 9 — 칸 그림 갈래 걸음 4)는 `kind << 8`(0b1001)이 줄 비트(11 ~)와 겹쳐 줄 r의 열쇠가 줄 r + 1의 지도자 열쇠와 같아지므로
    // 음수 칸에 제 열쇠(줄 · 직위 줄 더의 줄)를 둔다 — 다른 종류의 열쇠는 예전 그대로(종류 9를 그리지 않던 동안의 그림과 같게).
    final laneKey = _lensBand != 0
        ? row << 11 | CellKind.common << 8 | _lensBand
        : (kind == Schema4.cellOfficeMore ? -(row << 8 | lane) - 1 : row << 11 | kind << 8 | (lane | _slotBits));
    if (at < (_labelRight[laneKey] ?? double.negativeInfinity)) return;
    _labelRight[laneKey] = at + p.textW;
    _drawn[drawnAt]
      ..textL = at
      ..textW = p.textW;
    final hard = p.spot || p.house || focused || (hot && !groupRow) ? Look.ink : nameLook.color;
    // 명목 지도자 칸은 이름 글만 옅게(칸 · 가문 줄 · 조명은 그대로 — 웹 `.k-leader.is-nominal b { opacity: .5 }`).
    // 투명도 .5 대신 종이와 반씩 섞은 고른 색(감독 건의 2026-10-15 2번 — 연한 것은 색 자체를 연하게).
    // 정통성 명목(구역 57 — 칸 그림 갈래 걸음 3 · lg2-ga)은 이름 먹 45 — 옛 명목 지도자와 함께면 옅은 쪽.
    final faded = p.nominal ? mixSrgb(over(hard, Look.paper), Look.paper, .5) : hard;
    final ink = p.legitNominal ? (p.nominal ? _paler(faded, LegitLook.nominalName) : LegitLook.nominalName) : faded;
    c.later.add('cell', p.text, ink == nameLook.color ? nameLook : nameLook.withColor(ink), at, y, dim.at(at + p.textW / 2));
    if (p.nominal) c.debug?.note('명목', '$row ${p.text}');
    if (p.legitNominal) c.debug?.note('명목정통', '$row ${p.text} ${(ink & 0xffffff).toRadixString(16).padLeft(6, '0')}');
    // 선을 하나도 긋지 못한 칸은 이름 밑에 가로 점선 하나('이설 있음').
    // 글자 1px 밑에 두되 아래 테두리와 1px은 띄운다 — 가문 줄이 깔린 칸은 그 줄(아래 3px)보다 한 픽셀 더 위까지가 한계다.
    if (p.hasAlt) {
      final inkBottom = top + (height + look.size) / 2;
      final gy = math.min(top + height - (p.houseLine ? 5 : 3), (inkBottom + 1).roundToDouble());
      // 가문 줄이 자리를 좁혀 점선이 글자에 붙으면 아예 달지 않는다(상세 창의 '다른 견해'에만 — 지금 연표의 `y < ib + 0.25`).
      // 밝기는 칸이 아니라 유령선의 규칙(`.tl-calt.is-has` C:1850)을 탄다 — 칸의 .55 · 조명의 가름을 받지 않는다.
      if (!p.houseLine || gy >= inkBottom + .25) {
        c.quads.hLine(at, at + p.textW, gy, withAlpha(_ghostOf(soft), alpha * (p.spot ? 1 : _em.trimDim)), dash: 1, gap: 2, phase: at);
      }
    }
  }

  /// 두 불투명 색 가운데 옅은(밝은) 쪽 — 세 채널의 합으로 견준다(먹 · 종이 섞임과 나라 색 + 먹의 이름 글).
  static int _paler(int a, int b) {
    int sum(int c) => ((c >> 16) & 0xff) + ((c >> 8) & 0xff) + (c & 0xff);
    return sum(b) > sum(a) ? b : a;
  }

  /// 빌린 직위 줄의 칸 짙기 — 서고 미리보기 `.tl.is-seogo .tl-lane .tl-band .tl-cell.is-borrowed { opacity: .72 }`(common.css 2495 · timeline.js 7414 `_f4Borrow`).
  static const borrowedAlpha = .72;

  /// 실권 기간의 지도자 칸 짙기 — 서고 미리보기 `.tl.is-seogo .tl-lane .tl-band .tl-cell.k-leader.is-ousted { opacity: .55 }`(common.css 2496 · timeline.js 7415 ~ 7416).
  static const oustedAlpha = .55;

  /// 빌린 칸의 윗변 1px 파선 — 미리보기 `border-top: 1px dashed var(--edge)`. 무늬는 크롬이 그린 픽셀에서 잰 3 긋고 2 띄움([EdgeStroke.dashed])을
  /// 칸의 진짜 왼쪽([phase] — 화면 · 타일에 잘려도 칸 전체의 왼쪽이라 옆으로 옮길 때 무늬가 칸에 붙어 있다)부터 세고,
  /// 빛깔은 띠 테(`--edge` = 띠 색 oklab 84% + 먹 — 칸은 띠의 값을 물려받는다), 밝기는 칸과 같다(.72 · 조명 경계에서 끊음).
  /// 자리는 층의 맨 윗줄(칸 [top]의 한 줄 위 — 층 자리 `stripTop`): 미리보기의 칸 상자는 층 맨 윗줄부터라 그 윗 테두리가 이 줄이다
  /// (첫 층은 머리 색줄 아랫금 바로 밑 · 다음 층부터는 층 사이 금 위에 겹친다 — 미리보기 `.tl-fl`과 같은 줄). 앱의 칸 칠 · 금 · 글은 그 아래 줄부터다.
  void _borrowedTop(PaintContext c, _Host host, int row, int kind, int lane, double l, double top, double r, double phase, _Dim dim) {
    final y = top - 1;
    final edge = _edgeOf(0xff000000 | host.color);
    final cuts = _cuts..clear();
    dim.cutsInto(cuts, l, r);
    cuts.sort();
    var at = l;
    for (int i = 0; i <= cuts.length; i++) {
      final next = i == cuts.length ? r : cuts[i];
      if (next <= at) continue;
      c.quads.hLine(at, next, y, withAlpha(edge, dim.at((at + next) / 2)), dash: EdgeStroke.dashed.dash, gap: EdgeStroke.dashed.gap, phase: phase);
      at = next;
    }
    c.debug?.note('빌린칸', '$kind:$row:$lane ${_r1(l)},${_r1(y)},${_r1(r - l)} ${(dim.at(l + 1) * 1000).round()}');
  }

  /// 유령 구분선(칸 높이만 한 옅은 1px 세로 점선 — 위 2px · 아래 2px 들임, 가문 줄이 깔리는 지도자 단은 아래 4px). 칸보다 위에 그리므로 칸을 다 그린 뒤에.
  /// 밝기는 칸이 아니라 제 규칙을 탄다(`.tl-calt` C:1850): 고른 것이 있으면 띠 × .45이고, 고른 칸(`is-spot`)의 선만 띠 그대로다.
  /// 강조(`is-filtered`)에는 제 규칙이 없어 띠의 밝기를 그대로 물려받는다 — 칸의 .55 · .25와 다르다.
  void _drawAlts(PaintContext c, int row, int kind, int lane, double top, double height, double alpha) {
    if (_lines.isEmpty) return;
    final bottom = showHouses && kind == CellKind.leader ? 4.0 : 2.0; // 명세 01의 3-5
    final trim = _em.trimDim;
    for (final m in _lines) {
      var owner = _placed[0];
      for (int k = 0; k < _placedCount; k++) {
        if (m.x >= _placed[k].l && m.x < _placed[k].r) {
          owner = _placed[k];
          break;
        }
      }
      final soft = kind == CellKind.phase ? _phaseSoft : _softOf(owner.color);
      final ghost = alpha * (owner.spot ? 1 : trim);
      c.quads.vLine(m.x, top + 2, top + height - bottom, withAlpha(_ghostOf(soft), ghost), dash: 1, gap: 2, phase: top + 2);
      c.debug?.note('유령선', '$kind:$row:$lane ${_r1(m.x)} ${_r1(top + 2)},${_r1(top + height - bottom)}');
    }
    _lines.clear();
  }

  /// 조명 구간 안 · 밖의 밝기(css 1321~1322의 `.lit-in` 불투명도 .55와 `--lp-o = .45 / .55`).
  /// 구간 안은 조명이 다 켜졌을 때의 값이고, 켜지는 · 꺼지는 동안에는 두 값 사이를 [em.Spot.glow]로 섞는다.
  static const _litIn = .55, _litOut = .45;

  /// 이 칸이 **띠 밖에서** 받는 흐림 — 단마다 css의 요소가 달라 규칙도 다르다(명세 06의 3-1 · 3-2 표).
  ///
  /// | 단 | 요소 | 고른 동안 | 강조 |
  /// | --- | --- | --- | --- |
  /// | 지도자 · 내각 · 시기 · 지위 | `.tl-cell` | .45(C:370 — 고른 칸 · 가문 칸도) | 강조에 든 띠 안은 .55(C:1206 · 고른 칸은 뺌) · 가문 칸은 1(C:1449) |
  /// | 왕조 | `.tl-dyn` | .5 · 고른 칸 1(C:969) | .25 · 강조에 든 것 1(C:970) |
  /// | 기관 | `.tl-org` | .5 · 고른 칸 1(C:717) | 규칙 없음(1) |
  /// | 품은 칸 | `.tl-dep` | 규칙 없음(1 — 띠를 그대로) | .3 · 강조에 든 것 1(C:1730) |
  ///
  /// [uid]는 그 칸의 항목 uid(없으면 빈 글) — `is-match`를 가리는 데만 쓴다.
  double _stripDim(_Placed p, int band, int kind, String uid) {
    final look = _em.look;
    switch (kind) {
      case CellKind.dynasty:
        return _em.markAlpha(mine: p.spot, matched: look.matchedUid(uid), pick: em.Dim.dynPick, dim: em.Dim.dynDim);
      case CellKind.organ:
        return _em.markAlpha(mine: p.spot, matched: look.matchedUid(uid), pick: em.Dim.orgPick, dim: em.Dim.orgDim);
      case CellKind.dep:
        return _em.markAlpha(mine: false, matched: look.matchedUid(uid), pick: em.Dim.depPick, dim: em.Dim.depDim);
      default:
        if (p.twin) return 1; // 같은 사람의 칸(건의 8의 6-나)은 고른 동안에도 띠의 밝기 그대로 — 고른 칸과 같이 비친다
        // 같은 사람이 앉은 나라의 띠는 강조에 든 띠와 같은 흐림(.55 — 웹과 같게).
        if (look.filtered && ((look.bands?.contains(band) ?? false) || (look.twinBands?.contains(band) ?? false))) {
          if (p.house) return 1; // 가문 칸은 강조에 든 띠 안에서 흐려지지 않는다
          if (!p.spot) return em.Dim.cellMatch;
        }
        // 가문 조명(결정 7 A): 조명된 띠 안에서 그 묶음에 들지 않은 지도자 칸은 .55 — 웹 `is-other-house`와 같다(내각 · 빽빽한 칸 · 다른 띠는 그대로).
        // css에서는 한 요소의 불투명도 규칙끼리 곱해지지 않으므로 고름의 .45와는 더 옅은 쪽 하나를 쓴다.
        if (kind == CellKind.leader && !p.house && _em.housing) return math.min(_em.trimDim, _em.houseCellAlpha(band, p.houseId));
        return _em.trimDim;
    }
  }

  /// 이 칸의 밝기. 고른 것이 있으면 띠의 흐림에 단의 몫([_stripDim])을 곱하고, 기간 조명이 있으면 구간 안 .55 · 밖 `띠 × .45`로 갈린다.
  /// 조명은 켜지고(200ms) 꺼지는(160ms) 동안 구간마다 진행을 싣고 오므로, 구간 안의 밝기는 `밖 + (.55 − 밖) × glow`로 흐른다
  /// (지금 연표는 띠의 가림 판 `--bo`(= 띠의 흐림)가 구간 밖을 덮고 구간 안은 `--la`(1)라, 구간 밖만 띠의 흐림을 탄다 — css 1288~1292 · 1321).
  _Dim _dimOf(PaintContext c, _Placed p, int band, int kind, double alpha, List<em.Spot> spots, String uid) {
    final d = _dim; // 칸 하나를 그리는 동안만 쓰이므로 하나를 두고 값만 간다
    final base = alpha; // 띠에게서 물려받은 밝기(기관 칸은 `_strip`에서 이미 1로 온다)
    if (spots.isEmpty || !_em.look.lit) return d..plain(base * _stripDim(p, band, kind, uid));
    // 고른 칸 · 가문 칸은 조명의 가름에서 빠진다(css 1321~1331의 `:not(.is-spot, .is-house)`).
    // 고른 칸은 늘 제 조명 구간 안이라 띠의 가림 판이 1이다 — 띠의 흐림을 곱하지 않는다.
    if (p.spot || p.house) return d..plain(_stripDim(p, band, kind, uid));
    final out = base * _litOut;
    d.begin(out);
    for (final s in spots) {
      final a = c.v.xOf(s.start), b = c.v.xOf(s.end);
      if (b > p.l && a < p.r) d.add(a, b, out + (_litIn - out) * s.glow.clamp(0.0, 1.0));
    }
    if (d.isEmpty) return d..plain(out);
    final even = d.evenAlpha(p.l + .5, p.r - .5);
    if (even != null) return d..plain(even);
    // 이름을 비킬 자리가 없는 좁은 칸은 칸 전체를 흐린 쪽 밝기로 고르게(지금 연표의 lit-flat) — 글자가 반만 밝게 갈리지 않게.
    d.flat = p.text.isNotEmpty && (p.fixed || p.w - p.textW < 2 * _altGap + 2);
    return d;
  }

  /// 체계 이름표(`.sch`)의 알약 바탕 — 반지름 3 · 높이 9 · 바탕 mixSrgb(paper-muted, 투명, 16%)(종이 위 먹 약 10 — 그림판 먹 단계 12).
  void _tagBox(PaintContext c, double l, double t, double w, double alpha) {
    final bg = CanvasInk.of(0x29666666);
    _fill(c, l, t, l + w, t + 8 * 1.2 + 6, withAlpha(bg, alpha), 3, 3, null, null);
  }

  /// 단마다의 바탕과 테두리 색(명세 3-6). 바탕이 0이면 칠하지 않는다(기관 칸 — 무늬만).
  /// 색 섞기는 같은 모습마다 한 번만 한다 — 같은 답이 나오는 칸이 한 화면에 수백 개다.
  (int, int) _skin(int kind, int style, int color, int soft, bool thin, bool joined, bool alt, bool spot, bool house) {
    // style에서 바탕을 가르는 것은 지위의 서열과 예속의 이름표 갈래뿐이고, soft는 (종류 · 색)에서 나온다 — 열쇠는 이만큼이면 된다.
    // 32비트 색 위에 나머지를 얹어 정수 하나로 만든다(상자를 만들어 섞는 것보다 싸다).
    final sub = kind == CellKind.dep
        ? CellStyle.depLookOf(style)
        : (kind == CellKind.rank ? CellStyle.rankOf(style) : (kind == CellKind.common && CellStyle.bandOf(style) == CellStyle.groupReal ? 1 : 0));
    final key = (color & 0xffffffff) |
        kind << 32 |
        (sub + 1) << 36 |
        (thin ? 1 << 40 : 0) |
        (joined ? 1 << 41 : 0) |
        (alt ? 1 << 42 : 0) |
        (spot ? 1 << 43 : 0) |
        (house ? 1 << 44 : 0);
    return _skins[key] ??= _skinOf(kind, style, color, soft, thin, joined, alt, spot, house);
  }

  (int, int) _skinOf(int kind, int style, int color, int soft, bool thin, bool joined, bool alt, bool spot, bool house) {
    if (spot && kind != CellKind.dynasty) return (mixSrgb(color, Look.paper, .48), soft);
    if (house) return (mixSrgb(color, Look.paper, kind == CellKind.dynasty ? .50 : .42), soft);
    // 한 장 꼬리표(감독 건의 2026-10-15 3번 — 가운데 켜는 시기 · 지도자 등이 한 색으로 통일): 왕조 · 시기 · 서열 없는 지위 칸도 칠 없이
    // 가운데 켜의 칠(bands.dart `_paintTwoPiece`)이 비친다. 좁은 칸의 옅은 칠은 투명도가 아니라 종이와 섞은 고른 색(건의 2번).
    switch (kind) {
      case CellKind.dynasty:
        if (thin) return (mixSrgb(color, Look.paper, .55), 0);
        return (0, soft);
      case CellKind.phase:
        // 시기 칸은 제 색을 중립색으로 다시 정한다(명세 3-6 나) — 먹과 종이만 섞은 것이라 그림판 먹 단계(테 25 · 좁은 칸 칠 18 → 25).
        final phaseSoft = CanvasInk.of(withAlpha(Look.muted, .42));
        if (thin && !joined) return (CanvasInk.of(mixSrgb(Look.muted, Look.paper, .30)), 0);
        return (0, phaseSoft);
      case CellKind.rank:
        final level = CellStyle.rankOf(style);
        if (thin && !joined) return (mixSrgb(soft, Look.paper, .45), 0);
        if (level <= 0) return (0, soft);
        return (mixSrgb(color, Look.paper, _rankMix[level.clamp(0, 4)] / 100), soft);
      case CellKind.organ:
        return (0, withAlpha(soft, .80));
      case CellKind.common:
        // 리메이크 2부(목업 서고 power 사슬): 집권 · 실권 단의 칸은 칠 없이 흰 층 그대로 — 그 기간 층 아랫변에 2px 밑줄(_drawCell · 단체 색 80% + 먹)과 지도자 칸과 같은 색 이름.
        if (CellStyle.isGroupBand(CellStyle.bandOf(style))) return (0, soft);
        // 실권 칸(단 갈래 7 — 덧판 x1 A): 단체 색 78%(좁아도 78%) · 테두리는 그 색 64% + 먹([soft]로 온다) — 좁으면 테 없이.
        if (CellStyle.bandOf(style) == CellStyle.groupReal) return (mixSrgb(color, Look.paper, .78), thin ? 0 : soft);
        // 렌즈 칸(웹의 `.tl-cell.k-lens`) · 집권 단의 칸(`.k-group`): 갈래 · 단체 색 40% 칠 + 그 색의 옅은 테두리. 좁으면(is-thin) 테 없이 55%.
        if (thin) return (mixSrgb(color, Look.paper, .55), 0);
        return (mixSrgb(color, Look.paper, .40), soft);
      case CellKind.dep:
        return switch (CellStyle.depLookOf(style)) {
          1 => (mixSrgb(color, Look.paper, .52), _edgeOf(color)),
          2 => (mixSrgb(color, Look.paper, .22), soft),
          _ => (mixSrgb(color, Look.paper, .24), soft),
        };
      default:
        // 지도자 · 내각(꼬리표 갈래 E): 칠 없이 가운데 켜가 비친다 — 칸은 세로 금으로만 갈린다(예전: 종이 62% · 번갈아 제 색 12%).
        if (thin && !joined) return (mixSrgb(soft, Look.paper, .45), 0);
        return (0, soft);
    }
  }

  void _patternOf(PaintContext c, int kind, _Placed p, int color, int soft, double t, double b, _Dim dim) {
    final bl = p.thin ? 0.0 : 1.0;
    final l = p.l, r = p.r;
    if (kind == CellKind.organ) {
      _pattern(c, _Pattern.agency, l + bl, t + bl, r - bl, b - bl, withAlpha(color, .20), p, dim);
      return;
    }
    if (kind == CellKind.dep && CellStyle.depLookOf(p.style) == 2) {
      _pattern(c, _Pattern.occupied, l + bl, t + bl, r - bl, b - bl, withAlpha(_edgeOf(color), .55), p, dim);
    }
    if (p.layers.isEmpty) return;
    final zc = _zoneOf(soft);
    for (final layer in p.layers) {
      final spec = layer.$3 == 1 ? _Pattern.cellLegend : _Pattern.cellEstimated;
      _pattern(c, spec, layer.$1, t + bl, layer.$2, b - bl, zc, p, dim);
      // 기준 덤프의 background-size(조각의 폭)와 바로 견줄 수 있게 적어 둔다.
      c.debug?.note('무늬', '$kind ${layer.$3} ${_r1(layer.$1)},${_r1(layer.$2 - layer.$1)}');
    }
  }

  /// 무늬 한 조각. 미정 꼬리 · 조명 경계가 있으면 그 자리에서 잘라 밝기를 달리한다(무늬는 조각마다 한 색뿐이라 꼬리 안은 6px씩 나눈다).
  /// 무늬가 붙는 자리는 조각의 왼쪽 위([a] · [t]) — [phaseX] · [phaseY]를 주면 그 자리(주장 빗금 — 이웃 칸 · 단과 한 무늬).
  void _pattern(PaintContext c, PatternSpec spec, double a, double t, double z, double b, int argb, _Placed p, _Dim dim, {double? phaseX, double? phaseY}) {
    if (z - a < 0.5) return;
    final f = p.fade;
    final lEnd = p.l + (f?.fl ?? 0), rStart = p.r - (f?.fr ?? 0);
    double at = a;
    while (at < z - 1e-6) {
      double next = z;
      if (f != null && f.fl > 0 && at < lEnd) {
        next = math.min(z, math.min(lEnd, at + 6));
      } else if (f != null && f.fr > 0 && at >= rStart - 1e-6) {
        next = math.min(z, at + 6);
      } else {
        if (f != null && f.fl > 0 && lEnd > at && lEnd < next) next = lEnd;
        if (f != null && f.fr > 0 && rStart > at && rStart < next) next = rStart;
        next = dim.cutBetween(at, next);
      }
      if (next <= at) next = z;
      final mid = (at + next) / 2;
      final k = (f == null || !f.any ? 1.0 : _fadeAt(f, mid, p.l, p.r)) * dim.at(mid);
      c.patterns.add(spec, at, t, next, b, withAlpha(argb, k), phaseX: phaseX ?? a, phaseY: phaseY ?? t);
      at = next;
    }
  }

  /// 둥근 네모의 채움을 네모 묶음(몸통 · 옅은 끝)과 끝 조각에 모은다. [chain]이면 끝 조각은 흰 사슬의 반지름 3 조각([_ChainSprites]).
  void _fill(PaintContext c, double l, double t, double r, double b, int argb, double radiusL, double radiusR, _Fade? fade, _Dim? dim, {bool chain = false}) {
    final h = b - t;
    final rl = math.min(radiusL, math.min((r - l) / 2, h / 2)), rr = math.min(radiusR, math.min((r - l) / 2, h / 2));
    var bodyL = l, bodyR = r;
    // 옅어지는 쪽에는 끝 조각을 두지 않는다 — 그쪽은 거의 비치지 않는다.
    if (rl >= 1 && (fade == null || fade.fl <= 0)) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(l + rl / 2));
      if (chain) {
        _chainSprites.corner(rl, _CellSprites.topLeft, l, t, a);
        _chainSprites.corner(rl, _CellSprites.bottomLeft, l, b - rl, a);
      } else {
        _sprites.corner(rl, _CellSprites.topLeft, l, t, a);
        _sprites.corner(rl, _CellSprites.bottomLeft, l, b - rl, a);
      }
      c.quads.add(l, t + rl, l + rl, b - rl, a);
      bodyL = l + rl;
    }
    if (rr >= 1 && (fade == null || fade.fr <= 0)) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(r - rr / 2));
      if (chain) {
        _chainSprites.corner(rr, _CellSprites.topRight, r - rr, t, a);
        _chainSprites.corner(rr, _CellSprites.bottomRight, r - rr, b - rr, a);
      } else {
        _sprites.corner(rr, _CellSprites.topRight, r - rr, t, a);
        _sprites.corner(rr, _CellSprites.bottomRight, r - rr, b - rr, a);
      }
      c.quads.add(r - rr, t + rr, r, b - rr, a);
      bodyR = r - rr;
    }
    if (bodyR > bodyL) _span(c, bodyL, t, bodyR, b, argb, fade, l, r, dim);
  }

  /// 위아래 두 색으로 칠한 칸(렌즈의 연정 칸) — [_fill]과 같은 모서리 · 옅은 끝, 가운데 높이에서 색이 갈린다.
  void _fill2(PaintContext c, double l, double t, double r, double b, int top, int bottom, double radiusL, double radiusR, _Fade? fade, _Dim? dim) {
    final h = b - t, mid = t + h / 2;
    final rl = math.min(radiusL, math.min((r - l) / 2, h / 2)), rr = math.min(radiusR, math.min((r - l) / 2, h / 2));
    var bodyL = l, bodyR = r;
    if (rl >= 1 && (fade == null || fade.fl <= 0)) {
      final a = dim == null ? 1.0 : dim.at(l + rl / 2);
      _sprites.corner(rl, _CellSprites.topLeft, l, t, withAlpha(top, a));
      _sprites.corner(rl, _CellSprites.bottomLeft, l, b - rl, withAlpha(bottom, a));
      if (mid > t + rl) c.quads.add(l, t + rl, l + rl, mid, withAlpha(top, a));
      if (b - rl > mid) c.quads.add(l, mid, l + rl, b - rl, withAlpha(bottom, a));
      bodyL = l + rl;
    }
    if (rr >= 1 && (fade == null || fade.fr <= 0)) {
      final a = dim == null ? 1.0 : dim.at(r - rr / 2);
      _sprites.corner(rr, _CellSprites.topRight, r - rr, t, withAlpha(top, a));
      _sprites.corner(rr, _CellSprites.bottomRight, r - rr, b - rr, withAlpha(bottom, a));
      if (mid > t + rr) c.quads.add(r - rr, t + rr, r, mid, withAlpha(top, a));
      if (b - rr > mid) c.quads.add(r - rr, mid, r, b - rr, withAlpha(bottom, a));
      bodyR = r - rr;
    }
    if (bodyR > bodyL) {
      _span(c, bodyL, t, bodyR, mid, top, fade, l, r, dim);
      _span(c, bodyL, mid, bodyR, b, bottom, fade, l, r, dim);
    }
  }

  /// 6px 색 점 하나(왼쪽 위 [x] · [y]): 테두리 색의 반지름 3 끝 조각 넷 위에 칠 색의 반지름 2 끝 조각 넷(1px 들여).
  void _dot(double x, double y, int argb, double alpha) {
    final rim = withAlpha(mixOklab(argb, Look.ink, .64), alpha), fill = withAlpha(argb, alpha);
    // 화소에 맞춰 찍는다(13px 칸에서는 세로 자리가 반 화소라 그대로 찍으면 뭉개진다 — 내림: 점의 가운데가 글자 먹의 가운데와 같은 줄).
    // 바깥 동그라미는 반지름 3으로 따로 구운 조각([_CellSprites.dot]) — 반지름 2 조각을 1.5배로 늘려 찍으면 네모처럼 뭉개진다(웹의 `.gd`는 또렷한 동그라미).
    x = x.roundToDouble();
    y = y.floorToDouble();
    _sprites.dot(_CellSprites.topLeft, x, y, rim);
    _sprites.dot(_CellSprites.topRight, x + 3, y, rim);
    _sprites.dot(_CellSprites.bottomLeft, x, y + 3, rim);
    _sprites.dot(_CellSprites.bottomRight, x + 3, y + 3, rim);
    _sprites.corner(2, _CellSprites.topLeft, x + 1, y + 1, fill);
    _sprites.corner(2, _CellSprites.topRight, x + 3, y + 1, fill);
    _sprites.corner(2, _CellSprites.bottomLeft, x + 1, y + 3, fill);
    _sprites.corner(2, _CellSprites.bottomRight, x + 3, y + 3, fill);
  }

  /// 1px(고른 칸 · 가문 칸은 1.5px) 테두리. 곧은 변은 네모, 둥근 모서리는 제 그림판의 고리 조각.
  void _border(
    PaintContext c,
    double l,
    double t,
    double r,
    double b,
    int argb,
    double radiusL,
    double radiusR, {
    _Fade? fade,
    _Dim? dim,
    int? left,
    int? right,
    double width = 1,
    double dashLeft = 0,
    double dashRight = 0,
    double dashTop = 0,
    double dashGap = 0,
    bool chain = false,
  }) {
    final h = b - t;
    final rl = math.min(radiusL, math.min((r - l) / 2, h / 2)), rr = math.min(radiusR, math.min((r - l) / 2, h / 2));
    final hasL = left != null, hasR = right != null;
    final capL = rl >= 1 && hasL && (fade == null || fade.fl <= 0);
    final capR = rr >= 1 && hasR && (fade == null || fade.fr <= 0);
    if (capL) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(l + rl / 2));
      if (chain) {
        _chainSprites.arc(rl, _CellSprites.topLeft, l, t, a);
        _chainSprites.arc(rl, _CellSprites.bottomLeft, l, b - rl, a);
      } else {
        _sprites.arc(rl, _CellSprites.topLeft, l, t, a);
        _sprites.arc(rl, _CellSprites.bottomLeft, l, b - rl, a);
      }
    }
    if (capR) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(r - rr / 2));
      if (chain) {
        _chainSprites.arc(rr, _CellSprites.topRight, r - rr, t, a);
        _chainSprites.arc(rr, _CellSprites.bottomRight, r - rr, b - rr, a);
      } else {
        _sprites.arc(rr, _CellSprites.topRight, r - rr, t, a);
        _sprites.arc(rr, _CellSprites.bottomRight, r - rr, b - rr, a);
      }
    }
    final x0 = capL ? l + rl : l, x1 = capR ? r - rr : r;
    if (x1 > x0) {
      if (dashTop > 0) {
        c.quads.hLine(x0, x1, t, argb, dash: dashTop, gap: dashGap, phase: x0);
        c.quads.hLine(x0, x1, b - 1, argb, dash: dashTop, gap: dashGap, phase: x0);
      } else {
        _span(c, x0, t, x1, t + width, argb, fade, l, r, dim);
        _span(c, x0, b - width, x1, b, argb, fade, l, r, dim);
      }
    }
    final y0 = t + (capL ? rl : 0), y1 = b - (capL ? rl : 0);
    if (hasL && y1 > y0) {
      final a = dim == null ? left : withAlpha(left, dim.at(l));
      if (dashLeft > 0) {
        c.quads.vLine(l, y0, y1, a, dash: dashLeft, gap: dashLeft, phase: y0);
      } else {
        c.quads.add(l, y0, l + width, y1, a);
      }
    }
    final z0 = t + (capR ? rr : 0), z1 = b - (capR ? rr : 0);
    if (hasR && z1 > z0) {
      final a = dim == null ? right : withAlpha(right, dim.at(r - 1));
      if (dashRight > 0) {
        c.quads.vLine(r - 1, z0, z1, a, dash: dashRight, gap: dashRight, phase: z0);
      } else {
        c.quads.add(r - width, z0, r, z1, a);
      }
    }
  }

  /// 가로로 한 줄기를 그린다. 옅어지는 끝 · 조명 경계가 있으면 그 자리에서 잘라 번짐 네모로.
  void _span(PaintContext c, double x0, double t, double x1, double b, int argb, _Fade? fade, double cellL, double cellR, _Dim? dim) {
    final fading = fade != null && fade.any;
    // 가장 흔한 길: 옅어지지도 조명에 갈리지도 않는 줄기 — 네모 하나로 끝낸다(자를 자리 목록을 만들지 않는다).
    if (!fading && (dim == null || dim.even)) {
      if (x1 > x0) c.quads.add(x0, t, x1, b, dim == null ? argb : withAlpha(argb, dim.at((x0 + x1) / 2)));
      return;
    }
    final cuts = _cuts..clear();
    if (fading) {
      final lEnd = cellL + fade.fl, rStart = cellR - fade.fr;
      if (fade.fl > 0 && lEnd > x0 && lEnd < x1) cuts.add(lEnd);
      if (fade.fr > 0 && rStart > x0 && rStart < x1) cuts.add(rStart);
    }
    if (dim != null) dim.cutsInto(cuts, x0, x1);
    cuts.sort();
    double at = x0;
    for (int i = 0; i <= cuts.length; i++) {
      final next = i == cuts.length ? x1 : cuts[i];
      if (next <= at) continue;
      final k = dim == null ? 1.0 : dim.at((at + next) / 2);
      if (fade == null || !fade.any) {
        c.quads.add(at, t, next, b, withAlpha(argb, k));
      } else {
        c.quads.addFade(at, t, next, b, withAlpha(argb, _fadeAt(fade, at, cellL, cellR) * k), withAlpha(argb, _fadeAt(fade, next, cellL, cellR) * k));
      }
      at = next;
    }
  }

  double _fadeAt(_Fade f, double x, double l, double r) {
    if (f.fl > 0 && x < l + f.fl) return f.ma + (1 - f.ma) * ((x - l) / f.fl).clamp(0.0, 1.0);
    if (f.fr > 0 && x > r - f.fr) return f.mb + (1 - f.mb) * ((r - x) / f.fr).clamp(0.0, 1.0);
    return 1;
  }

  // ---- 색과 글꼴의 보관 ----
  int _edgeOf(int color) => _edge[color] ??= mixOklab(color, Look.ink, .84);

  /// 한 띠 안의 칸은 거의 다 같은 색이다 — 바로 앞의 답 하나만 따로 두어 보관 표를 뒤지지 않는다.
  int _lastSoftColor = -1, _lastSoft = 0; // −1은 색으로 오지 않는 값(색은 32비트 부호 없는 수)

  int _softOf(int color) {
    if (color == _lastSoftColor) return _lastSoft;
    _lastSoftColor = color;
    return _lastSoft = _edgeSoft[color] ??= mixOklab(color, Look.ink, .92);
  }
  int _dividerOf(int soft) => _divider[soft] ??= withAlpha(soft, .55);

  /// 실권 칸(덧판 x1 A)의 테두리 — 쉴 때 그 색 64% + 먹 · 올리면 52% + 먹(웹 `.is-real`의 --edge-soft · --edge).
  int _realSoftOf(int color) => _realSoft[color] ??= mixOklab(color, Look.ink, .64);
  int _realEdgeOf(int color) => _realEdge[color] ??= mixOklab(color, Look.ink, .52);
  int _zoneOf(int soft) => _zone[soft] ??= withAlpha(soft, .42);

  /// 유령 구분선의 색 `--gc = mixSrgb(--edge-soft, 투명, 75%)`.
  int _ghostOf(int soft) => withAlpha(soft, .75);

  /// 시기 칸은 테두리 · 무늬 색을 중립색으로 다시 정한다(명세 3-6 나의 `--edge-soft`).
  static final int _phaseSoft = CanvasInk.of(withAlpha(Look.muted, .42));

  /// 칸 글의 생김새. 열쇠를 색 섞기 **앞**에서 잡아, 같은 (종류 · 제 색 · 딱지 갈래 · 크기)면 섞기조차 하지 않는다.
  TextLook _lookOf(int kind, int color, int style, double size) {
    final sub = kind == CellKind.dep
        ? CellStyle.depLookOf(style)
        : (kind == CellKind.rank ? CellStyle.rankOf(style) : (kind == CellKind.common ? CellStyle.bandOf(style) : 0));
    // 크기는 단마다 두 가지(그리는 크기 · 재는 크기)뿐이라 0.5px 단위 정수로 얹는다.
    final key = (color & 0xffffffff) | kind << 32 | (sub + 1) << 36 | (size * 2).round() << 40;
    final had = _looks[key];
    if (had != null) return had;
    final tone = switch (kind) {
      CellKind.dynasty => mixSrgb(color, Look.ink, .32),
      CellKind.cabinet => CanvasInk.of(Look.muted),
      CellKind.phase => CanvasInk.of(mixSrgb(Look.muted, Look.ink, .80)),
      CellKind.organ => mixSrgb(color, Look.ink, .35),
      CellKind.dep => mixOklab(color, Look.ink, CellStyle.depLookOf(style) == 1 ? .28 : .45),
      CellKind.rank => CellStyle.rankOf(style) <= 0 ? CanvasInk.of(Look.muted) : mixSrgb(color, Look.ink, .30),
      _ => mixSrgb(color, Look.ink, .30),
    };
    final look = _lookFor(kind); // 렌즈의 단체 칸은 자간 0(갈래가 열쇠에 들어 있어 렌즈 칸과 섞이지 않는다)
    return _looks[key] = TextLook(size, look.weight, tone, spacing: look.spacing, wght: look.wght);
  }

  static final _schLook = TextLook(8, ui.FontWeight.w600, CanvasInk.of(Look.muted), spacing: 0.095);
  static const _rankMix = [0.0, 8.0, 22.0, 38.0, 56.0];

  static String _shortDynasty(String name) {
    for (final tail in const ['왕조', '왕가', '가문', '家', '朝']) {
      if (name.length > tail.length && name.endsWith(tail)) return name.substring(0, name.length - tail.length).trimRight();
    }
    return '';
  }

  static String _r1(double v) => (v * 10).round().toString();
}

/// 줄 안의 띠 하나(타일에 걸친 조각을 합친 것).
class _Host {
  _Host(this.id, this.row, this.x0, this.x1, this.color);
  final int id, row, color;
  double x0, x1;

  /// 이 장면에 화면 안(칸 상자 안)에 드는 지도자 · 내각 칸 수 — 타일을 모두 합친 것(빽빽한 칸을 띠 하나로 정할 때).
  int leaders = 0, cabinets = 0;

  /// [leaders] 가운데 단 1 ~ 3(칸 종류 1의 lane — 두 단 띠의 둘째 단부터 · 3 넘는 단은 3에)의 칸 수. 단 1 이상 칸이 없는 띠는 null.
  Int32List? leaderUpper;

  /// 단마다 센 지도자 칸 수의 가장 큰 값(단 0 = [leaders] − 위 단들) — 두 단 띠 조각의 빽빽한 칸 문턱(칸 그림 갈래 고침: 서고 미리보기 `_cells`는
  /// 단마다 제 칸만 `seen`으로 센다 — 두 단을 합쳐 세면 단마다 6px가 넉넉한데도 빽빽한 칸이 된다). 한 단 띠는 [leaders] 그대로.
  int get leaderLaneMax {
    final up = leaderUpper;
    if (up == null) return leaders;
    var most = leaders - up[1] - up[2] - up[3];
    for (int k = 1; k < 4; k++) {
      if (up[k] > most) most = up[k];
    }
    return most;
  }

  /// 같은 셈의 직위 줄 더(칸 종류 9 — 칸 그림 갈래 걸음 4) 칸 수 — 줄(lane)마다. 종류 9 칸이 없는 띠는 null.
  Map<int, int>? offices;

  /// 띠의 `sub` 비트(계약 6-1 · 배치 갈래가 17 ~ 23에 직위 줄 더 수 · 지도자 층 단 수 − 1을 더함) — [look]과 함께 꼬리표 셈(bands.dart `TagLook`)에 넘긴다.
  int sub = 0;

  /// 띠의 `look` 비트(계약 6-1) · 미정인 끝 · 연대 폭까지 품은 두 끝(px) — 조명 칠을 띠 모양(둥근 끝)으로 자를 때 쓴다.
  int look = 0;
  bool fuzzyS = false, fuzzyE = false;
  double shapeL = 0, shapeR = 0;

  /// 띠의 진짜 시작(px — 미정 꼬리 · 연대 폭 없이 · 왼쪽이 잘리지 않은 조각의 시작). 그 조각이 실린 타일이 없으면 무한(시작이 화면 왼쪽 밖).
  double startX = double.infinity;

  /// 꼬리표 밑 흰 사슬(G5 #9 나) 둘 — 0 왕조 · 1 지위 자리. 사슬이 없는 띠는 null.
  _ChainSpan? _dynasty, _rank;
  _ChainSpan? chainSpan(int slot) => slot == 0 ? _dynasty : _rank;
  _ChainSpan chainOf(int slot) => slot == 0 ? (_dynasty ??= _ChainSpan()) : (_rank ??= _ChainSpan());

  /// 두 단 띠(정통성 넷 가 다듬은 꼴 — 칸 그림 갈래 걸음 2)의 지도자 칸 조각 표([StripLayer._scanPieces]). 두 단 띠가 아니면 null(지금 칸 길).
  _BandPieces? pieces;

  /// 이 띠의 섭정 칸(구역 57 — 칸 그림 갈래 걸음 3 · [StripLayer._scanRegents]): 칸 id → 타일을 건너 합친 그 칸. 섭정이 없으면 null.
  Map<int, _Regent>? regents;
}

/// 섭정 칸 하나(타일을 건너 합친 것 — 화면 px). 층을 세우지 않고 그 기간 피후견 칸 아랫변 안쪽에 2px 먹 60으로만 그린다(다듬기 판 paintCells ④).
class _Regent {
  _Regent(this.kind, this.lane, this.seq, this.name);

  /// 칸 종류(1 지도자 · 2 내각 · 9 직위 줄 더) · 단(타일 칸의 lane — 두 단 띠에서는 피후견 칸의 단) · 순번(칸 style 15 ~ 26) · 이름(누름 기록).
  final int kind, lane, seq;
  final String name;
  double l = double.infinity, r = double.negativeInfinity;
}

/// 두 단 띠 하나의 지도자 칸 조각 표 — 장면마다 [StripLayer._scanPieces]가 짓는다(다듬기 판 `themes/g-legit2.js` paintCells의 pieces).
class _BandPieces {
  _BandPieces(this.lanes);

  /// 그 띠의 지도자 층 단 수(띠 sub 22 ~ 23 + 1 — 줄의 단 수를 넘지 않음 · 2 이상).
  final int lanes;

  /// 칸 id → 타일을 건너 합친 그 칸.
  final cells = <int, _PieceCell>{};

  /// 조각의 경계 — 후보 칸(섭정이 아닌 칸)의 진짜 시작 · 끝(화면 px · 오름차순 · 0.5px 안은 하나).
  final bounds = <double>[];

  /// 칸 [cell]의 조각들(화면 px — 칸을 경계로 끊은 것 · 왼쪽부터)과 저마다 혼자인가(그 조각에 든 후보 칸이 하나 이하 → 층 전체). 칸마다 한 번 셈해 둔다.
  List<(double, double, bool)> piecesOf(_PieceCell cell) {
    final had = cell.pieces;
    if (had != null) return had;
    final out = <(double, double, bool)>[];
    var at = cell.l;
    for (final x in bounds) {
      if (x <= at + .5) continue;
      if (x >= cell.r - .5) break;
      out.add((at, x, _alone(at, x)));
      at = x;
    }
    out.add((at, cell.r, _alone(at, cell.r)));
    return cell.pieces = out;
  }

  /// [a] ~ [b] 조각의 가운데를 품은 후보 칸이 하나 이하인가.
  bool _alone(double a, double b) {
    final m = (a + b) / 2;
    var n = 0;
    for (final c in cells.values) {
      if (!c.regent && c.l < m && m < c.r && ++n > 1) return false;
    }
    return true;
  }
}

/// 두 단 띠의 지도자 칸 하나(타일을 건너 합친 것 — 화면 px): 좌우 · 진짜 시작 · 끝(타일에 잘린 쪽만 있으면 null) · 순번 · 단 · 섭정인가 · 조각들.
class _PieceCell {
  _PieceCell(this.seq, this.lane);
  final int seq, lane;
  double l = double.infinity, r = double.negativeInfinity;
  double? start, end;
  bool regent = false;
  List<(double, double, bool)>? pieces;
}

/// 두 단 띠의 칸 조각 하나의 초안 — 이 타일의 칸 조각 [a] ~ [b] · 잘린 쪽(타일 경계 · 이음매) · 왼쪽이 타일 경계인가 · 조각 전체 · 화면에 든 칸 폭 · 층 전체인가.
class _PieceDraft {
  const _PieceDraft({
    required this.index,
    required this.a,
    required this.b,
    required this.cutL,
    required this.cutR,
    required this.tileL,
    required this.wholeL,
    required this.wholeR,
    required this.cellW,
    required this.cell,
    required this.full,
  });
  final int index;
  final double a, b, wholeL, wholeR, cellW;
  final bool cutL, cutR, tileL, full;
  final _PieceCell cell;
}

/// 한 띠의 사슬 하나를 장면마다 미리 훑은 것([StripLayer._scanChains]) — 칸들의 진짜 시작 · 끝(px)과 첫 칸의 시작, 구멍([StripLayer._chainThread]가 정함).
class _ChainSpan {
  final starts = <double>[], ends = <double>[];
  double first = double.infinity;

  /// 꼬리표 시작에서 비롯하는 사슬인가(첫 칸에 구멍)와 그 구멍 · 실의 픽셀 열(종이 왼쪽 테의 열 + 7).
  bool hole = false;
  double holeCol = 0;
}

/// 사슬의 구멍 · 꼬리표 아랫변의 점 — 가운데 · 반지름 · 칠(0이면 없음) · 1px 테(0이면 없음).
class _Ring {
  const _Ring(this.x, this.y, this.r, this.fill, this.line);
  final double x, y, r;
  final int fill, line;
}

/// 흰 사슬 종이의 둥근 귀(반지름 [ChainLook.radius] 3) — 채운 조각 넷과 1px 고리 조각 넷을 한 번 구워 drawRawAtlas 한 번으로 찍는다([_CellSprites]와 같은 길).
/// 칸 조각 그림판([_CellSprites])에 3을 넣지 않고 따로 둔다: 그 판의 반지름 찾기는 3을 2로 골라 체계 이름표(`_tagBox` — 반지름 3)가 그 조각을 쓰고,
/// 판의 크기를 바꾸면 다른 칸의 조각이 달라질 수 있다 — 사슬을 끈 그림(`--paint-off=chain`)은 예전과 바이트 같아야 한다.
class _ChainSprites {
  static const _cell = 8.0;

  ui.Image? _image;
  double _scale = 1;

  Float32List _transforms = Float32List(4 * 64), _rects = Float32List(4 * 64);
  Int32List _colors = Int32List(64);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  /// 채운 귀 조각([corner]는 [_CellSprites.topLeft] 따위) — [left] · [top]은 조각의 왼쪽 위. [radius]가 3과 다르면 줄여 찍는다.
  void corner(double radius, int corner, double left, double top, int argb) => _add(corner, radius, left, top, argb);

  /// 1px 고리 귀 조각.
  void arc(double radius, int corner, double left, double top, int argb) => _add(corner + 4, radius, left, top, argb);

  void _add(int cell, double radius, double left, double top, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    const baked = ChainLook.radius;
    final p = _n * 4, s = _scale;
    _transforms[p] = radius / baked / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    final sx = cell * _cell;
    _rects[p] = sx * s;
    _rects[p + 1] = 0;
    _rects[p + 2] = (sx + baked) * s;
    _rects[p + 3] = baked * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    final image = _image ??= _render(_scale);
    canvas.drawRawAtlas(image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    final ring = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    const r = ChainLook.radius;
    for (int k = 0; k < 4; k++) {
      // 네 귀를 따로 굽는다(찍을 때 돌리지 않는다): 칸 0 ~ 3은 채운 조각, 4 ~ 7은 고리 조각.
      final left = k == _CellSprites.topLeft || k == _CellSprites.bottomLeft, upper = k == _CellSprites.topLeft || k == _CellSprites.topRight;
      for (final (cell, paint, radius) in [(k, white, r), (k + 4, ring, r - .5)]) {
        final x = cell * _cell;
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x, 0, r, r));
        canvas.drawCircle(ui.Offset(left ? x + r : x, upper ? r : 0), radius, paint);
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((8 * _cell * scale).ceil(), (_cell * scale).ceil());
    picture.dispose();
    return image;
  }
}

/// 타일마다 한 번만 셈해 두는 것 — 타일의 내용은 바뀌지 않으므로 장면마다 다시 하지 않는다.
/// px와 무관한 것만 담는다: 단 무리의 경계 · 끝의 누적 최댓값(화면 밖 일찍 버리기) · style에서 푼 순번 ·
/// 칸 참조 글자 · 이름을 나눈 것과 그 폭(글꼴과 글의 크기만으로 정해진다 — 배율이 달라져도 같다).
/// 타일이 버려지면 함께 버려진다([StripLayer._cellsBy]가 약한 열쇠인 `Expando`).
class _TileCells {
  _TileCells(Tile t) : count = t.cellCount, reach = Float32List(t.cellCount), seq = Int32List(t.cellCount) {
    final n = count;
    final x0 = t.cellX0, x1 = t.cellX1, span = t.span.toDouble();
    final starts = <int>[], rows = <int>[], clips = <int>[], seams = <int>[];
    int i = 0;
    // 타일의 칸은 (줄, 종류, 단, 시작) 순이다 — 같은 단의 칸은 이어 붙어 있으므로 한 번 훑으며 무리로 끊는다.
    while (i < n) {
      starts.add(i);
      final row = t.cellRow[i], kind = t.cellKindOf(i), lane = t.cellLane[i] & 0xff;
      rows.add(row);
      var far = double.negativeInfinity;
      int j = i;
      while (j < n && t.cellRow[j] == row && t.cellKindOf(j) == kind && (t.cellLane[j] & 0xff) == lane) {
        if (x1[j] > far) far = x1[j];
        reach[j] = far; // 무리 안에서 앞에서부터의 끝 최댓값 — 오름차순이라 이분 탐색이 된다
        seq[j] = CellStyle.seqOf(t.cellStyle[j]);
        final flags = t.cellFlagsOf(j);
        if (flags != 0) clips.add(j);
        if ((flags & Tile.clipLeft == 0 && x0[j] <= 0) || (flags & Tile.clipRight == 0 && x1[j] >= span)) seams.add(j);
        j++;
      }
      i = j;
    }
    starts.add(n);
    runAt = Int32List.fromList(starts);
    runRow = Int32List.fromList(rows);
    clipped = Int32List.fromList(clips);
    seamed = Int32List.fromList(seams);
  }

  final int count;

  /// 제 무리 안에서 앞에서부터 잰 `cellX1`의 최댓값(타일 안의 분).
  final Float32List reach;

  /// `CellStyle.seqOf(style)`.
  final Int32List seq;

  /// 무리 k는 칸 [runAt[k], runAt[k + 1]).
  late final Int32List runAt;

  /// 무리 k가 놓인 줄(무리는 줄 순으로 온다 — 같은 줄의 무리는 이어 붙어 있다).
  late final Int32List runRow;

  /// 타일 경계에서 잘린 칸의 번호만(장면의 처음에 조각을 합칠 때 쓴다).
  late final Int32List clipped;

  /// 잘리지 않은 끝이 타일 경계에 딱 놓인 칸의 번호만(장면의 처음에 이음매 이웃을 적을 때 — [StripLayer._seamAt]).
  late final Int32List seamed;

  int get runCount => runAt.length - 1;

  // ---- 처음 물을 때 한 번 만들어 두는 것 ----
  List<String?>? _ref, _alt, _tag, _body, _clipText, _leader;
  Float64List? _nameW, _altW, _tagW, _clipRoom, _clipW;

  /// 이 보관을 지을 때의 지도자 표기 · 대수(`StripLayer._labelGen`). 다르면 글과 폭만 다시 짓는다.
  int labelGen = 0;

  /// 지도자 칸에 지어 둔 이름(표기 · 대수가 기본이 아닐 때만).
  List<String?> get leader => _leader ??= List<String?>.filled(count, null);

  /// 표기 · 대수가 바뀌었다 — 글과 그 폭만 버린다(무리의 경계 · 순번 · 칸 참조 · 체계 딱지는 글과 무관해 그대로 쓴다).
  void resetLabels() {
    _leader = null;
    _alt = null;
    _clipText = null;
    _nameW = null;
    _altW = null;
    _clipRoom = null;
    _clipW = null;
  }

  /// 칸 참조 글자('leader:3' — [CellKind.ref]). 순번이 없으면 빈 글. [lane]은 칸 종류 9만 본다(칸 [i]마다 하나라 칸 번호로 담아 둔다).
  String refOf(int i, int kind, int lane) {
    final list = _ref ??= List<String?>.filled(count, null);
    return list[i] ??= seq[i] < 0 ? '' : CellKind.ref(kind, lane, seq[i]);
  }

  /// 온 이름의 폭 · 앞글자(또는 짧은 왕조 이름)와 그 폭 · 체계 딱지의 폭. NaN이면 아직 재지 않았다.
  Float64List get nameW => _nameW ??= _room();
  Float64List get altW => _altW ??= _room();
  Float64List get tagW => _tagW ??= _room();

  /// 짧은 왕조 이름(왕조 칸) 또는 앞 한 글자(그 밖) — 둘은 한 칸에 함께 쓰이지 않는다.
  List<String?> get alt => _alt ??= List<String?>.filled(count, null);

  /// 시기 칸의 체계 딱지와 딱지를 뗀 이름.
  List<String?> get tag => _tag ??= List<String?>.filled(count, null);
  List<String?> get body => _body ??= List<String?>.filled(count, null);

  /// 앞글자만 잘라 보이는 칸: 지난 장면에 쓴 자를 폭과 그 답(옆으로 끌기만 할 때는 폭이 그대로다).
  Float64List get clipRoom => _clipRoom ??= _room();
  Float64List get clipW => _clipW ??= _room();
  List<String?> get clipText => _clipText ??= List<String?>.filled(count, null);

  /// 칸 하나의 글에 매인 셈(폭 · 짧은 이름 · 잘라 둔 글)만 버린다 — 그 칸의 이름이 달라졌을 때.
  /// 아직 만들지 않은 목록은 건드리지 않는다(없으면 이미 '재지 않음'이다).
  void forgetWidth(int i) {
    final name = _nameW, short = _altW, room = _clipRoom, cut = _clipW;
    if (name != null) name[i] = double.nan;
    if (short != null) short[i] = double.nan;
    if (room != null) room[i] = double.nan;
    if (cut != null) cut[i] = double.nan;
    final alt = _alt, text = _clipText;
    if (alt != null) alt[i] = null;
    if (text != null) text[i] = null;
  }

  Float64List _room() => Float64List(count)..fillRange(0, count, double.nan);
}

/// 렌즈 칸이 가리키는 것(구역 43의 `a` 8 — 내보내기 export/lens.mjs): 누를 항목 uid · 갈래(메아리의 열쇠 — 없으면 '') ·
/// 연정 칸의 둘째 단체 색(0xRRGGBB · 없으면 0) · 짝을 모르는 연정(`d` 1) · 색 점(`text2`의 탭 뒤 '6자리 16진,…' — 0xffRRGGBB).
final class _LensRef {
  const _LensRef(this.uid, this.fam, this.color2, this.solo, this.dots);
  final String uid, fam;
  final int color2;
  final bool solo;
  final List<int> dots;

  factory _LensRef.read(String text2, String fam, int color2, int d) {
    final cut = text2.indexOf('\t');
    if (cut < 0) return _LensRef(text2, fam, color2, d == 1, const []);
    final dots = <int>[];
    for (final hex in text2.substring(cut + 1).split(',')) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) dots.add(0xff000000 | v);
    }
    return _LensRef(text2.substring(0, cut), fam, color2, d == 1, dots);
  }
}

/// 제 그림판: 칸의 둥근 끝(채운 조각 · 1px 고리 조각)을 반지름마다 한 번 구워 두고 drawRawAtlas 한 번으로 찍는다.
/// scene/sprites.dart는 공용이라 고치지 않고 같은 방식만 본떴다(계약 7절).
class _CellSprites {
  static const topLeft = 0, topRight = 1, bottomLeft = 2, bottomRight = 3;
  static const radii = [2.0, 4.0, 5.0, 6.0, 7.0];
  static const _cell = 16.0, _cols = 8.0, _rows = 6.0;

  /// 단체 칸의 색 점(지름 6 — 감독 선택 D5 덧판 x3 C)의 사분원: 반지름 3을 따로 구워 둔 맨 아랫줄. 칸 모서리의 반지름 찾기([_slot] · [radii])에는
  /// 넣지 않는다 — 좁은 칸의 모서리가 이 줄을 골라 다른 칸의 그림이 달라지지 않게.
  static const dotRadius = 3.0, _dotSlot = 5;

  ui.Image? _image;
  double _scale = 1;

  Float32List _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  Int32List _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  static int _slot(double radius) {
    // 칸의 모서리는 거의 늘 구워 둔 값 그대로다(칸마다 여덟 번 부르므로 곧바로 답한다).
    if (radius == 6) return 3;
    if (radius == 4) return 1;
    if (radius == 5) return 2;
    if (radius == 7) return 4;
    if (radius == 2) return 0;
    int best = 0;
    for (int i = 1; i < radii.length; i++) {
      if ((radii[i] - radius).abs() < (radii[best] - radius).abs()) best = i;
    }
    return best;
  }

  /// 채운 끝 조각. [left] · [top]은 조각의 왼쪽 위(칸의 모서리 자리).
  void corner(double radius, int corner, double left, double top, int argb) => _add(_slot(radius), corner, radius, left, top, argb);

  /// 색 점의 사분원(반지름 3 · 채움) — [left] · [top]은 조각의 왼쪽 위.
  void dot(int corner, double left, double top, int argb) => _add(_dotSlot, corner, dotRadius, left, top, argb);

  /// 1px 고리 조각(테두리의 둥근 모서리).
  void arc(double radius, int corner, double left, double top, int argb) => _add(_slot(radius), corner + 4, radius, left, top, argb);

  void _add(int slot, int cell, double radius, double left, double top, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final baked = slot == _dotSlot ? dotRadius : radii[slot];
    final size = radius / baked; // 구워 둔 반지름과 조금 다르면 줄여 · 늘여 찍는다
    final p = _n * 4, s = _scale;
    _transforms[p] = size / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    final sx = cell * _cell, sy = slot * _cell;
    _rects[p] = sx * s;
    _rects[p + 1] = sy * s;
    _rects[p + 2] = (sx + baked) * s;
    _rects[p + 3] = (sy + baked) * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    final image = _image ??= _render(_scale);
    canvas.drawRawAtlas(image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    final ring = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (int slot = 0; slot <= radii.length; slot++) {
      final r = slot == _dotSlot ? dotRadius : radii[slot], y = slot * _cell;
      for (int k = 0; k < 4; k++) {
        // 네 모서리를 따로 구워 둔다(찍을 때는 돌리지 않는다).
        final x = k * _cell;
        final cx = (k == topLeft || k == bottomLeft) ? x + r : x;
        final cy = (k == topLeft || k == topRight) ? y + r : y;
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x, y, r, r));
        canvas.drawCircle(ui.Offset(cx, cy), r, white);
        canvas.restore();
        final ax = x + 4 * _cell;
        final acx = (k == topLeft || k == bottomLeft) ? ax + r : ax;
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(ax, y, r, r));
        canvas.drawCircle(ui.Offset(acx, cy), r - .5, ring);
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_cols * _cell * scale).ceil(), (_rows * _cell * scale).ceil());
    picture.dispose();
    return image;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}
