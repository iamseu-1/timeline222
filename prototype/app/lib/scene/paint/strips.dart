import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../layout.dart';
import '../marks.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import 'bands.dart' show BandKind, BandLayer, BandLook, TagEnd, TagLook;
import 'context.dart'; // 묶음 연장(Quads · DashedQuads · TextQueue)은 context.dart가 batch.dart를 다시 내보낸다
import 'look.dart';
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

  static _StripLook of(int kind) => switch (kind) {
    CellKind.dynasty => dynasty,
    CellKind.leader => leader,
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

  /// 타일 경계에서 잘린 조각(보이지 않는 이음매 — 끝 조각도 테두리도 두지 않는다).
  bool cutL = false, cutR = false;

  /// 타일에 걸친 칸 전체의 폭(이름 · 미정 꼬리 · is-thin은 조각이 아니라 칸 전체로 정한다).
  double wholeL = 0, wholeR = 0;

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

  /// 이름표 글자의 가운데(비키기 전) — [_measure]가 한 번 셈해 둔다.
  double center = 0;

  /// 모호한 구간의 무늬 조각 [a, b, 무늬 종류]와 좌우 점선 테두리.
  final layers = <(double, double, int)>[];
  bool zl = false, zr = false;

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
    wholeL = 0;
    wholeR = 0;
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
    center = 0;
    layers.clear();
    zl = false;
    zr = false;
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

  /// 시기 단의 체계 이름표를 이미 단 (줄, 단) — 한 체계에 딱 하나.
  final _tagged = <int>{};

  /// (줄, 종류, 단) → 그 단에 마지막으로 그린 이름의 오른쪽 끝. 자료가 겹쳐 와도 이름은 겹쳐 그리지 않는다.
  final _labelRight = <int, double>{};

  /// 이번 장면에 흰 층을 깐 띠 — 타일마다 조각이 와도 한 번만.
  final _floored = <int>{};

  /// 흰 층의 세로 금(갈래 E): 이번 단에서 마지막으로 그은 x와 단의 안쪽 두 끝 — 이웃 칸의 끝과 시작이 겹금이 되지 않게(목업 chain의 lastX).
  double _divLast = double.negativeInfinity, _divLo = 0, _divHi = 0;

  /// 흰 층의 칸 사이 세로 금: 먹 20 · 위아래 1px 들임. 칸의 시작 · 끝마다 하나(타일에 잘린 쪽 · 층의 두 끝 · 2.5px 안의 이웃 금은 건너뜀).
  /// 시작을 모르거나 이어진 쪽([dashL])은 2/2 파선.
  void _floorDividers(PaintContext c, double l, double top, double r, double b, _Dim dim, _Placed p, {bool dashL = false}) {
    for (final (x, skip, dash) in [(l, p.cutL, dashL), (r - 1, p.cutR, false)]) {
      if (skip) continue;
      final q = x.roundToDouble();
      if ((q - _divLast).abs() < 2.5 || q < _divLo + 2 || q > _divHi - 3) continue;
      c.quads.vLine(q, top + 1, b - 1, withAlpha(Look.ink, .20 * dim.at(q)), dash: dash ? 2 : 0, gap: dash ? 2 : 0, phase: top);
      _divLast = q;
    }
  }

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
    final marks = SceneMarks.of(c.scene);
    showAlt = marks.showAlt;
    showHouses = marks.showHouses;
    leaderLabel = marks.leaderLabel;
    leaderOrdinal = marks.leaderOrdinal;
    _hostsOf.clear();
    _joined.clear();
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
    if (c.layout.conditions.density == 2) return; // 조감: 줄은 띠 하나뿐이라 단이 모두 사라진다(명세 05의 7.2)
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
        if (had == null) {
          byId[id] = _Host(id, t.bandRow[i], x0, x1, t.bandColor[i])
            ..look = t.bandLook[i]
            ..fuzzyS = flags & Tile.fuzzyStart != 0 && flags & Tile.clipLeft == 0
            ..fuzzyE = flags & Tile.fuzzyEnd != 0 && flags & Tile.clipRight == 0;
        } else {
          if (x0 < had.x0) had.x0 = x0;
          if (x1 > had.x1) had.x1 = x1;
          // 띠의 진짜 끝을 실은 조각에서만 미정 끝을 안다(잘린 조각은 모른다).
          if (flags & Tile.fuzzyStart != 0 && flags & Tile.clipLeft == 0) had.fuzzyS = true;
          if (flags & Tile.fuzzyEnd != 0 && flags & Tile.clipRight == 0) had.fuzzyE = true;
        }
      }
      // 잘리지 않은 칸은 한 타일 안에 온전히 있다 — 잘린 칸만 타일이 미리 짚어 둔 목록에서 본다.
      final clipped = _cellsOf(t).clipped;
      for (int k = 0; k < clipped.length; k++) {
        final i = clipped[k];
        final id = t.cellId[i];
        final x0 = v.xOf(origin + t.cellX0[i]), x1 = v.xOf(origin + t.cellX1[i]);
        final had = spans[id];
        spans[id] = had == null ? (x0, x1) : (math.min(had.$1, x0), math.max(had.$2, x1));
      }
      _readItems(c, t, origin, zoneById, ghostById, wantHouse);
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
        if (kind != CellKind.leader && kind != CellKind.cabinet) continue;
        final hosts = _hostsOf[t.cellRow[i]];
        if (hosts == null || !seen.add(t.cellId[i])) continue;
        final a = v.xOf(origin + t.cellX0[i]), b = v.xOf(origin + t.cellX1[i]);
        final host = _hostAt(hosts, (a + b) / 2);
        if (host == null) continue;
        final boxL = math.max(host.x0, c.left - 1), boxR = math.max(boxL + 3, math.min(host.x1, c.w + 1));
        if (b <= boxL + 1 + _pad2 || a >= boxR - 1 - _pad2) continue;
        if (kind == CellKind.leader) {
          host.leaders++;
        } else {
          host.cabinets++;
        }
      }
    }
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
  void setScale(double scale) => _sprites.setScale(scale);

  @override
  void paintTile(PaintContext c, Tile t) {
    // 조명 칠은 칸보다 먼저(띠 채움 · 연대 폭 빗금 · 할거기 칠 위 · 칸 아래). 조감은 칸이 없고 띠 모양이 달라 아직 칠하지 않는다.
    if (_litOn && c.layout.conditions.density != 2 && !c.hide.contains('spotFill')) _spotFill(c, t);
    if (c.hide.contains('cells')) return;
    if (c.layout.conditions.density == 2) return; // 조감: 왕조 · 시기 · 지위 · 지도자 · 내각 · 예속 · 기관이 모두 빠진다(명세 05의 7.2)
    // 무리(한 줄의 한 단)로 끊는 일은 타일마다 한 번이면 된다 — 타일이 셈해 둔 경계를 쓴다.
    final cache = _cellsOf(t);
    _hideNames = c.hide.contains('cellNames'); // 장면마다 칸마다 묻지 않고 타일마다 한 번
    // 무리는 줄 순으로 온다 — 세로로 안 보이는 줄은 그 줄의 무리를 통째로 건너뛴다(한 줄에 단이 예닐곱이다).
    final layout = c.layout;
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
      _paintLane(c, t, cache, run);
      run++;
    }
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
      if (host == null) continue;
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
    final cellRows = layout.spec(row)?.cellRows ?? false;
    double topOf(_Host host) => cellRows ? c.v.yOf(layout.rowTop(row) + TagLook.compactOf(geo, host.look, stripTop)) : top;
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

    // (1) 보이는 칸 고르기 — 지금 연표 layoutStrip의 vis.
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
        final end = TagLook.endOf(host.look);
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
        if (_denseDone.add(host.id * 16 + kind)) _dense(c, host, lo, hi, cellTop, cellH, alpha);
        return;
      }
    }

    // (3) 잇기와 0.5px 틈 — layoutStrip 그대로. 이음은 `앞 칸과 같은 무리`(style 비트 2)에 픽셀로도 맞닿을 때만.
    final n = _placedCount;
    if (_jn.length < n) _jn = Uint8List(n + 64);
    final jnR = _jn;
    jnR[n - 1] = 0;
    for (int k = 0; k < n - 1; k++) {
      final next = _placed[k + 1];
      final style = t.cellStyle[next.index];
      var join = style & CellStyle.joinLeft != 0;
      if (join && (_placed[k].b - next.a).abs() >= 1.5) {
        // 성긴 단계에서는 엔진이 짧은 칸(통의 1/8 미만)을 싣지 않는다(levels.rs `lod_of`). 그 자리가 몇 px 비면 픽셀로는 맞닿지 않아
        // 무리가 끊기고 양쪽이 따로 둥근 칸이 되어, 축소한 띠의 지도자 칸 줄이 토막 나 보였다(감독 건의 2026-10-14 8번).
        // 목록의 순번(비트 15~26)이 건너뛰었으면 그 사이가 빠진 칸이다 — 이어 붙이고 앞 칸을 늘여 메운다(아래 '잇기'). 웹은 모든 칸을 받아 이미 그렇다.
        final s0 = CellStyle.seqOf(t.cellStyle[_placed[k].index]), s1 = CellStyle.seqOf(style);
        join = next.a > _placed[k].b && s0 >= 0 && s1 > s0 + 1;
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
    _drawAlts(c, row, kind, lane, cellTop, cellH, alpha);
    // (7) 가문 줄(표시 체크 '가문') — 칸보다 위에 그리므로 맨 뒤에.
    if (showHouses && kind == CellKind.leader) _drawHouseLines(c, minW, cellTop, cellH, alpha);
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

  void _dense(PaintContext c, _Host host, double lo, double hi, double top, double height, double alpha) {
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
    final wholeW = math.max(p.w, math.min(p.wholeR, hi) - math.max(p.wholeL, lo));
    p.thin = kind == CellKind.organ ? wholeW < 16 : wholeW < 8;
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
    if (name.isNotEmpty && !_hideNames) {
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
      final ref = cache.refOf(i, kind);
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
      for (final p in drawn) {
        if (p.seq == m.seq) return p;
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
    final ref = p.seq < 0 ? '' : (groupRow ? '${lane == 3 ? 'real' : 'power'}:${p.seq}' : cache.refOf(p.index, kind));
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
      ..textW = 0;
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
      c.quads.add(l, b - 2, r, b, withAlpha(mixOklab(color, Look.ink, powerLine), dim.outside));
      c.stats.shapes++;
    }
    _patternOf(c, kind, p, color, soft, top, b, dim);
    final unkS = p.fade != null && p.fade!.fl > 0;
    // 꼬리표 갈래 E: 칸은 흰 층 안의 각진 칸 — 상자 테 없이 칸 사이의 세로 금(먹 20)만. 고른 칸 · 가문 · 단체 고름(굵은 테)만 테를 둘러 드러낸다.
    final boxed = p.spot || p.house || focused;
    if (!boxed) {
      _floorDividers(c, l, top, r, b, dim, p, dashL: p.openL || p.zl || unkS || p.uLeft);
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
    if (p.cutL && !p.atL) return;
    final nameLook = _lookOf(kind, color, p.style, look.size);
    final y = top + (height - look.size * 1.2) / 2;
    final at = p.center + p.dx - p.textW / 2;
    if (p.tagW > 0) {
      final bl = p.thin ? 0.0 : 1.0;
      _tagBox(c, l + bl + 3, top + (height - (8 * 1.2 + 6)) / 2, p.tagW + 6, dim.at(l + bl + 5));
      c.later.add('sch', p.tag, _schLook, l + bl + 6, top + (height - 8 * 1.2) / 2, dim.at(l + bl + 5));
    }
    // 렌즈의 무리(지위 · 지도자 꼴로 그리는 것도)는 제 열쇠로 — 같은 줄의 옛 지도자 · 지위 칸 이름과 비킴을 섞지 않는다.
    final laneKey = _lensBand != 0 ? row << 11 | CellKind.common << 8 | _lensBand : row << 11 | kind << 8 | lane;
    if (at < (_labelRight[laneKey] ?? double.negativeInfinity)) return;
    _labelRight[laneKey] = at + p.textW;
    _drawn[drawnAt]
      ..textL = at
      ..textW = p.textW;
    final hard = p.spot || p.house || focused || (hot && !groupRow) ? Look.ink : nameLook.color;
    // 명목 지도자 칸은 이름 글만 옅게(칸 · 가문 줄 · 조명은 그대로 — 웹 `.k-leader.is-nominal b { opacity: .5 }`).
    // 투명도 .5 대신 종이와 반씩 섞은 고른 색(감독 건의 2026-10-15 2번 — 연한 것은 색 자체를 연하게).
    final ink = p.nominal ? mixSrgb(over(hard, Look.paper), Look.paper, .5) : hard;
    c.later.add('cell', p.text, ink == nameLook.color ? nameLook : nameLook.withColor(ink), at, y, dim.at(at + p.textW / 2));
    if (p.nominal) c.debug?.note('명목', '$row ${p.text}');
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

  /// 체계 이름표(`.sch`)의 알약 바탕 — 반지름 3 · 높이 9 · 바탕 mixSrgb(paper-muted, 투명, 16%).
  void _tagBox(PaintContext c, double l, double t, double w, double alpha) {
    const bg = 0x29666666;
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
        // 시기 칸은 제 색을 중립색으로 다시 정한다(명세 3-6 나).
        final phaseSoft = withAlpha(Look.muted, .42);
        if (thin && !joined) return (mixSrgb(Look.muted, Look.paper, .30), 0);
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
  void _pattern(PaintContext c, PatternSpec spec, double a, double t, double z, double b, int argb, _Placed p, _Dim dim) {
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
      c.patterns.add(spec, at, t, next, b, withAlpha(argb, k), phaseX: a, phaseY: t);
      at = next;
    }
  }

  /// 둥근 네모의 채움을 네모 묶음(몸통 · 옅은 끝)과 끝 조각에 모은다.
  void _fill(PaintContext c, double l, double t, double r, double b, int argb, double radiusL, double radiusR, _Fade? fade, _Dim? dim) {
    final h = b - t;
    final rl = math.min(radiusL, math.min((r - l) / 2, h / 2)), rr = math.min(radiusR, math.min((r - l) / 2, h / 2));
    var bodyL = l, bodyR = r;
    // 옅어지는 쪽에는 끝 조각을 두지 않는다 — 그쪽은 거의 비치지 않는다.
    if (rl >= 1 && (fade == null || fade.fl <= 0)) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(l + rl / 2));
      _sprites.corner(rl, _CellSprites.topLeft, l, t, a);
      _sprites.corner(rl, _CellSprites.bottomLeft, l, b - rl, a);
      c.quads.add(l, t + rl, l + rl, b - rl, a);
      bodyL = l + rl;
    }
    if (rr >= 1 && (fade == null || fade.fr <= 0)) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(r - rr / 2));
      _sprites.corner(rr, _CellSprites.topRight, r - rr, t, a);
      _sprites.corner(rr, _CellSprites.bottomRight, r - rr, b - rr, a);
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
  }) {
    final h = b - t;
    final rl = math.min(radiusL, math.min((r - l) / 2, h / 2)), rr = math.min(radiusR, math.min((r - l) / 2, h / 2));
    final hasL = left != null, hasR = right != null;
    final capL = rl >= 1 && hasL && (fade == null || fade.fl <= 0);
    final capR = rr >= 1 && hasR && (fade == null || fade.fr <= 0);
    if (capL) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(l + rl / 2));
      _sprites.arc(rl, _CellSprites.topLeft, l, t, a);
      _sprites.arc(rl, _CellSprites.bottomLeft, l, b - rl, a);
    }
    if (capR) {
      final a = dim == null ? argb : withAlpha(argb, dim.at(r - rr / 2));
      _sprites.arc(rr, _CellSprites.topRight, r - rr, t, a);
      _sprites.arc(rr, _CellSprites.bottomRight, r - rr, b - rr, a);
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
  static final int _phaseSoft = withAlpha(Look.muted, .42);

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
      CellKind.cabinet => Look.muted,
      CellKind.phase => mixSrgb(Look.muted, Look.ink, .80),
      CellKind.organ => mixSrgb(color, Look.ink, .35),
      CellKind.dep => mixOklab(color, Look.ink, CellStyle.depLookOf(style) == 1 ? .28 : .45),
      CellKind.rank => CellStyle.rankOf(style) <= 0 ? Look.muted : mixSrgb(color, Look.ink, .30),
      _ => mixSrgb(color, Look.ink, .30),
    };
    final look = _lookFor(kind); // 렌즈의 단체 칸은 자간 0(갈래가 열쇠에 들어 있어 렌즈 칸과 섞이지 않는다)
    return _looks[key] = TextLook(size, look.weight, tone, spacing: look.spacing, wght: look.wght);
  }

  static const _schLook = TextLook(8, ui.FontWeight.w600, Look.muted, spacing: 0.095);
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

  /// 띠의 `look` 비트(계약 6-1) · 미정인 끝 · 연대 폭까지 품은 두 끝(px) — 조명 칠을 띠 모양(둥근 끝)으로 자를 때 쓴다.
  int look = 0;
  bool fuzzyS = false, fuzzyE = false;
  double shapeL = 0, shapeR = 0;
}

/// 타일마다 한 번만 셈해 두는 것 — 타일의 내용은 바뀌지 않으므로 장면마다 다시 하지 않는다.
/// px와 무관한 것만 담는다: 단 무리의 경계 · 끝의 누적 최댓값(화면 밖 일찍 버리기) · style에서 푼 순번 ·
/// 칸 참조 글자 · 이름을 나눈 것과 그 폭(글꼴과 글의 크기만으로 정해진다 — 배율이 달라져도 같다).
/// 타일이 버려지면 함께 버려진다([StripLayer._cellsBy]가 약한 열쇠인 `Expando`).
class _TileCells {
  _TileCells(Tile t) : count = t.cellCount, reach = Float32List(t.cellCount), seq = Int32List(t.cellCount) {
    final n = count;
    final x1 = t.cellX1;
    final starts = <int>[], rows = <int>[], clips = <int>[];
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
        if (t.cellFlagsOf(j) != 0) clips.add(j);
        j++;
      }
      i = j;
    }
    starts.add(n);
    runAt = Int32List.fromList(starts);
    runRow = Int32List.fromList(rows);
    clipped = Int32List.fromList(clips);
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

  /// 칸 참조 글자('leader:3'). 순번이 없으면 빈 글.
  String refOf(int i, int kind) {
    final list = _ref ??= List<String?>.filled(count, null);
    return list[i] ??= seq[i] < 0 ? '' : '${CellKind.prefix(kind)}:${seq[i]}';
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
