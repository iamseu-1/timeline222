import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../layout.dart';
import '../marks.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import 'bands.dart';
import 'context.dart';
import 'look.dart';
import 'patterns.dart';

// 띠 밖에 덧붙는 것: 속국 이름표(매달린 탭) · 세로 끈 · 구역 탭 · 바탕 문화의 아래 이름 단(구역 16 · 17 · 18 · 44).
// 값의 뜻은 docs/계약-아카이브-3단계.md 6-4절, 그리기 규칙은 docs/명세-3단계/03-띠에-덧붙는-것.md 3 · 4 · 5절.
//
// 이 층은 **띠보다 아래**(뒤 판)에 그려진다 — 매달린 탭은 띠 아랫변 밑으로 2px 끼워 매달리므로 탭의 윗부분이 띠에 가려진다(지금 연표의 z −1).
// 자리는 모두 줄의 몫(slot) 기준이고, 탭 줄의 윗변은 `geo.zoneLaneTop(lane)`(띠 아랫변에 바로 붙는 자리)에서 셈한다.
//
// 타일 경계에 걸린 이름표는 조각으로 나뉘어 오므로(일반 구역도 잘림 표시를 단다), 자리 셈은 [beginFrame]에서 **장면 전체**로 한 번 하고
// [paintTile]은 제 조각의 몫만 그린다 — 그래야 이어 붙은 칸(j-l · j-r)과 "이름은 긴 칸의 첫 칸에만"이 통을 넘어도 같은 답을 낸다(계약 7-3절).
//
// 밝기(고르기 · 흐림 · 기간 조명)는 항목마다 색의 알파에 곱해 같은 묶음에 넣는다(saveLayer 없이 — 설계 4.5절).

/// 이 층의 값. 지금 연표(js/timeline.js의 G · _depHangs · css/common.css의 .tl-hang · .tl-org.is-zone · .tl-under-name)에서 옮겼다.
abstract final class HangLook {
  /// 구역 탭 한 줄(G.zoneTab 20)과 줄 사이(G.zoneGap 3).
  static const tab = G.zoneTab, gap = G.zoneGap;

  /// 매달린 탭은 띠 아랫변 밑으로 2px 끼워 매단다. 높이는 그 줄의 간격(`RowGeo.hangHeight` — 13 · 옛 저장소는 23)만큼이다.
  static const tuck = 2.0;

  /// 둥근 모서리 아래에 매달리지 않게 띠 끝에서 들이는 px(구역 탭도 같다).
  static const inset = 10.0;

  /// 아래 모서리의 반지름(매달린 탭 6 · 구역 탭은 네 모서리 5).
  static const radius = 6.0, zoneRadius = 5.0;

  /// 그리지 않는 좁은 칸의 문턱(layoutStrip의 minW)과 잇는 칸으로 보는 틈.
  static const minWidth = 2.0, joinGap = 1.5;

  /// 품은 칸 한 줄(꼬리표 안 흰 층 16 — 틈 없음) — 세로 끈이 닿는 자리를 셀 때.
  static const depPitch = G.depPitch;

  /// 글자: 구역 탭 · 바탕 문화 이름은 9.5px, 매달린 이름표는 8px(감독 결정 2026-10-14 '크기만 줄이자') · 굵기 650 ·
  /// css의 letter-spacing −0.14px(`.tl`의 −.01em이 14px에서 굳은 값이라 아래 글자에 모두 물려진다).
  static const size = 9.5, hangSize = 8.0, spacing = -0.14;

  /// 탭 안쪽: 테두리 1 + padding 1 + `b`의 padding 5 → 글자는 왼쪽에서 7px. 세로는 글 상자의 가운데 —
  /// 첫 줄은 탭 위에서 3px(띠 밑에 끼운 2 + 1 · css padding-top 3), 둘째 줄부터는 2px(가름선 1 + padding 1)에서 아래 테두리 위까지.
  static const textLeft = 7.0, textTopFirst = 3.0, textTopDeep = 2.0;

  /// 같은 글줄 윗변에서 새 엔진은 8px 글의 먹을 크로뮴보다 1px 아래에 찍는다(1배 그림으로 잼 — 첫 줄 위 2 · 아래 0px ↔ 웹 1 · 1px).
  /// 웹과 같은 화소에 앉아 위아래 틈이 1px씩 남도록 그만큼 올린다.
  static const inkLift = 1.0;

  /// 이름 맞춤의 문턱(_depLabel). 매달린 탭은 품은 칸보다 4px 엄하게 본다.
  static const fitFull = 12.0, fitFirst = 9.0, hangTight = 4.0;

  /// 구역 탭: 이름 맞춤(timeline.js:6731) · 이름을 아예 뺄 만큼 좁은 탭(is-thin) · 안쪽 여백(테두리 1 + padding 6).
  static const zoneFitFull = 14.0, zoneFitFirst = 10.0, zoneThin = 16.0, zoneTextLeft = 7.0, zoneLine = 10.0;

  /// 구역 탭의 빗금(묶음 3 · 2번 — 감독 결정 2026-09-22): 기관 칸과 같은 성긴 ／ 빗금(135° · 굵기 4 · 간격 8 · 제 색 20%) —
  /// 빗금 = 외세의 손길(기관 · 구역), 민무늬 = 나라(속국 이름표). 지금 연표 common.css의 '.tl-lane .tl-org.is-zone'.
  static const zoneHatch = PatternSpec.stripes(135, 4, 8);

  /// 바탕 문화 이름 단: 들어가는지 재는 문턱(폭 ≥ 이름 폭 + 24) · 왼쪽 들임 12 + 테두리 1 · 작은 글('문화')의 앞 틈과 크기.
  static const hemFit = 24.0, hemLeft = 13.0, hemGap = 4.0, hemSize = 9.0;

  /// 바탕 문화의 폭을 재는 글자(지금 연표 textWidth(name, 11) — 기본 굵기 500).
  static const hemProbe = TextLook(11, ui.FontWeight.w500, Look.ink);

  /// 세로 끈: 폭 1.5 · 가운데 맞춤(−0.75) · 탭 쪽 자리는 그 줄 윗변(끼운 2px 위)에서 7px(옛 저장소의 23px 줄은 8px).
  static const linkWidth = 1.5, linkOut = 7.0, linkOutLegacy = 8.0;

  /// 점선 · 파선 테두리(css의 border-style: dotted · dashed를 크로뮴이 1px 테두리에 그리는 꼴 — 기준 그림에서 px로 재었다:
  /// 점선은 1 켜고 1 끔, 파선은 3 켜고 2 끔의 되풀이).
  static const dotOn = 1.0, dotOff = 1.0, dashOn = 3.0, dashOff = 2.0;

  /// 모습 번호(계약 6-4절의 b): 0 빈 탭 · 1 칠한 탭 · 2 점선 탭 · 3 파선 탭 · 4 세로 끈.
  static const loose = 0, firm = 1, nominal = 2, plain = 3, link = 4;

  /// 이름표의 style(계약 6-4절의 c).
  static const unknownStart = 1, unknownEnd = 2, joinLeft = 4, linkToInside = 8, vagueEstimated = 16, vagueLegend = 32, hasRange = 64;

  /// 이어 붙은 쪽의 미정 꼬리는 끝까지 사라지지 않고 .35까지만 옅어진다(css '칸의 미정' — `.unk-s.j-l { --ma: .35 }`).
  static const joinFade = .35;

  /// 모호한 연대의 무늬(js의 ZONE_GRAD): 추정은 세로 줄 1.5/4, 전승은 135° 빗금 1.5/4.5. 색은 edge-soft 42%(css:1865의 `--zc`).
  static const vagueEstimatedPattern = PatternSpec.stripes(90, 1.5, 4), vagueLegendPattern = PatternSpec.stripes(135, 1.5, 4.5);
  static const vagueMix = .42;

  /// 무늬가 이름표 글자를 먹지 않게 두는 틈(altRowPlan의 ALT_GAP 3 + 반 픽셀) · 무늬로 보는 가장 좁은 구간.
  static const vagueGap = 3.5, vagueMin = 1.0;

  /// 유령 구분선(css:1840 `.tl-calt`): 1px 점이 1 켜고 2 끔 · 위아래 2px 들임 · 색은 edge-soft 75%.
  /// 진짜 구분선 · 칸 끝 · 이름표 글자와 3px 떨어져야 긋고(altMarks의 ALT_GAP), 8px보다 좁은 조각에는 달지 않는다(ALT_MIN_W).
  static const ghostGap = 3.0, ghostMinWidth = 8.0, ghostInset = 2.0, ghostMix = .75, ghostOn = 1.0, ghostOff = 2.0;

  /// 검색 · 창의 강조에 든 속국의 이름표 테두리(css의 `--warn` #d49a45 — `.tl-hang.is-match`).
  static const warn = 0xff000000;

  /// 조감(보기 조건 density 2)에서는 띠 아래로 덧붙는 것이 모두 사라진다(명세 05의 7.2 · 명세 03의 6.3).
  static const birdDensity = 2;

  /// 실로 매단 작은 꼬리표(감독 결정 '두 장 ㄴ' · 목업 서고의 접힌 그릇 꼬리표 — Fable 판 f-0-common.js paintHangsSmall):
  /// 높이 [G.hang] 13 · 왼쪽 두 귀 모따기 3 · 구멍(왼쪽 끝 + 6 · 세로 가운데 · 반지름 2.5 · 종이 + 먹 45 테) · 이름 8.5 굵게(왼쪽 끝 + 12) ·
  /// 실 = 상국 몸통 아랫변에서 구멍 위까지 1px 먹 45. 칠: 빈 탭 = 제 색 10% · 칠한 탭 · 점선 탭 = 띠 칠(24%) · 파선 탭 = 종이.
  static const tagCham = 3.0, tagHoleX = 6.0, tagHoleR = 2.5, tagTextX = 12.0, tagSize = 8.5, tagFill = .24, threadInk = .45;
}

/// 속국 · 구역 · 문화의 빛깔에서 끌어낸 색. css의 `--edge`(제 색 84% + 글자색) · `--edge-soft`(92%)와 color-mix 식 그대로다(색마다 한 번만 셈한다).
class _Tone {
  _Tone(int rgb) : this._(0xff000000 | rgb);
  _Tone._(int c)
      : _base0 = c,
        fillLoose = mixSrgb(c, Look.paper, .10),
        fillFirm = mixSrgb(c, Look.paper, .34),
        edge = mixOklab(c, Look.ink, .84),
        edgeSoft = mixOklab(c, Look.ink, .92),
        ink = mixOklab(c, Look.ink, .45);
  final int fillLoose, fillFirm, edge, edgeSoft, ink;
  final int _base0;

  /// 둘째 줄부터의 가는 가름선(edge-soft 45%) · 이어 붙은 쪽의 구분선(55%) · 모호한 연대의 무늬(42%) · 유령 구분선(75%).
  late final int deep = withAlpha(edgeSoft, .45), join = withAlpha(edgeSoft, .55), vague = withAlpha(edgeSoft, HangLook.vagueMix), ghost = withAlpha(edgeSoft, HangLook.ghostMix);
  late final TextLook look = TextLook(HangLook.hangSize, ui.FontWeight.w600, ink, spacing: HangLook.spacing, wght: 650);

  /// 실로 매단 작은 꼬리표(두 장 ㄴ): 칠(띠 칠과 같은 24%) · 이름(띠 이름과 같은 먹 섞임 22%).
  late final int fillTag = mixSrgb(_base0, Look.paper, HangLook.tagFill);
  late final TextLook tagLook = TextLook(HangLook.tagSize, ui.FontWeight.w700, mixSrgb(_base0, Look.ink, .22));
}

/// 구역 탭의 색(css:816 · css:709 — 바탕 6% · 테두리 edge-soft 60% · 글자는 제 색 35% + paper-muted).
class _ZoneTone {
  _ZoneTone(int rgb) : this._(0xff000000 | rgb);
  _ZoneTone._(int c)
      : fill = mixSrgb(c, Look.paper, .06),
        edge = withAlpha(mixOklab(c, Look.ink, .92), .60),
        look = TextLook(HangLook.size, ui.FontWeight.w600, mixSrgb(c, Look.muted, .35), spacing: HangLook.spacing);
  final int fill, edge;
  final TextLook look;
}

/// 바탕 문화 이름 단의 색(css:691 — 제 색 30% + 글자색 · 기울임 · opacity .85, 작은 글은 거기에 .8을 또).
class _HemTone {
  _HemTone(int rgb) : this._(0xff000000 | rgb);
  _HemTone._(int c)
      : name = TextLook(HangLook.size, ui.FontWeight.w400, withAlpha(mixSrgb(c, Look.ink, .30), .85), italic: true, spacing: HangLook.spacing),
        small = TextLook(HangLook.hemSize, ui.FontWeight.w400, withAlpha(mixSrgb(c, Look.ink, .30), .68), spacing: HangLook.spacing);
  final TextLook name, small;
}

/// 검사 · 덤프가 읽는 기록: 이 층이 그린 것 하나.
class HangMark {
  HangMark(this.kind, this.row, this.lane, this.rect,
      {this.name = '', this.look = 0, this.ref = 0, this.joinLeft = false, this.joinRight = false, this.openLeft = false, this.alpha = 1, this.zones = 0, this.dotted = ''});

  /// 'hang' 매달린 탭 · 'link' 세로 끈 · 'zone' 구역 탭 · 'hem' 바탕 문화 이름.
  final String kind;
  final int row, lane, look;

  /// 가리키는 띠의 번호(상국 · 얹히는 띠 · 문화 띠).
  final int ref;
  final ui.Rect rect;
  final String name;
  final bool joinLeft, joinRight, openLeft;

  /// 밝기(고르기 · 흐림) · 모호한 연대의 무늬 조각 수 · 점선이 된 테두리('l' · 'r' · 'lr').
  final double alpha;
  final int zones;
  final String dotted;

  @override
  String toString() {
    String n(double v) => v.toStringAsFixed(2);
    return '$kind 줄$row 단$lane [${n(rect.left)},${n(rect.top)},${n(rect.width)},${n(rect.height)}]'
        '${ref > 0 ? ' 띠$ref' : ''}${look > 0 ? ' 모습$look' : ''}${joinLeft ? ' j-l' : ''}${joinRight ? ' j-r' : ''}${openLeft ? ' clip-l' : ''}'
        '${zones > 0 ? ' 무늬$zones' : ''}${dotted.isEmpty ? '' : ' 점선$dotted'}${alpha < .999 ? ' 밝기${n(alpha)}' : ''}${name.isEmpty ? '' : ' $name'}';
  }
}

/// 맞히기의 답: 눌린 것이 어느 이름표 · 구역 탭 · 바탕 문화 이름인가.
class HangHit {
  const HangHit(this.kind, {this.band = 0, this.host = 0, this.row = -1, this.lane = 0, this.uid = '', this.name = ''});

  /// 'hang' 속국 이름표(세로 끈 포함) · 'zone' 구역 탭 · 'hem' 바탕 문화 이름 단.
  final String kind;

  /// 속국 띠의 번호(모르면 0) · 상국(얹히는 · 문화) 띠의 번호 · 줄 · 탭 줄.
  final int band, host, row, lane;

  /// 가리키는 항목의 uid(속국 · 구역 · 문화)와 이름.
  final String uid, name;
}

class _HitBox {
  const _HitBox(this.rect, this.hit);
  final ui.Rect rect;
  final HangHit hit;
}

/// 이름표 한 조각의 밝기 판: 미정 끝의 옅어짐(css의 mask-image)과 기간 조명의 밝은 구간(`--lm`)과 고르기 · 흐림의 밝기를 한데 모은다.
/// 항목마다 saveLayer를 부르지 않고, 밝기가 꺾이는 자리에서만 잘라 네모의 꼭짓점 색에 곱한다.
class _Shade {
  const _Shade(this.l, this.r, this.fadeL, this.fadeR, this.headAlpha, this.tailAlpha, this.base, this.lit, this.spots);

  final double l, r, fadeL, fadeR, headAlpha, tailAlpha, base, lit;

  /// 기간 조명의 밝은 구간(화면 px)과 그 진행([em.Spot.glow] 0~1) — 흐린 띠 안에서도 이 구간만 [lit] 밝기로 남는다.
  /// 밝기는 `base + (lit − base) × glow`라 진행 0이면 이름표의 밝기 그대로, 1이면 조명 밝기다.
  final List<(double, double, double)> spots;

  bool get flat => fadeL <= 0 && fadeR <= 0 && spots.isEmpty;

  double _ramp(double x) {
    var a = 1.0;
    if (fadeL > 0 && x < l + fadeL) a = headAlpha + (1 - headAlpha) * ((x - l) / fadeL).clamp(0.0, 1.0);
    if (fadeR > 0 && x > r - fadeR) a = math.min(a, tailAlpha + (1 - tailAlpha) * ((r - x) / fadeR).clamp(0.0, 1.0));
    return a;
  }

  double _baseAt(double x) {
    var a = base;
    // 겹친 구간(자리를 물려주는 동안)은 가장 밝은 값을 쓴다.
    for (final s in spots) {
      if (x >= s.$1 && x <= s.$2) {
        final on = base + (lit - base) * s.$3;
        if (on > a) a = on;
      }
    }
    return a;
  }

  double alphaAt(double x) => _baseAt(x) * _ramp(x);

  /// [a0]~[z0]을 밝기가 꺾이는 자리에서 잘라 조각마다 [draw](왼쪽 · 오른쪽 · 두 끝의 밝기)를 부른다.
  void steps(double a0, double z0, void Function(double a, double z, double alphaA, double alphaZ) draw) {
    if (z0 <= a0) return;
    if (flat) {
      if (base > .004) draw(a0, z0, base, base);
      return;
    }
    final marks = <double>[a0, z0];
    void mark(double x) {
      if (x > a0 && x < z0) marks.add(x);
    }

    if (fadeL > 0) mark(l + fadeL);
    if (fadeR > 0) mark(r - fadeR);
    for (final s in spots) {
      mark(s.$1);
      mark(s.$2);
    }
    marks.sort();
    for (int k = 0; k + 1 < marks.length; k++) {
      final a = marks[k], z = marks[k + 1];
      if (z - a < 1e-6) continue;
      final b = _baseAt((a + z) / 2);
      final al = b * _ramp(a), az = b * _ramp(z);
      if (al > .004 || az > .004) draw(a, z, al, az);
    }
  }
}

/// 장면 하나에서 풀어 놓은 이름표 조각 하나(타일의 조각들을 합친 것).
class _Tab {
  _Tab(this.id, this.row, this.lane, this.look, this.style, this.color, this.name, this.client, this.host, this.clientBand);
  final int id, row, lane, look, style, color, host;

  /// 속국의 uid와 그 속국 띠의 번호(없으면 0 — 고르기 · 강조가 속국을 짚을 때 쓴다).
  final String name, client;
  final int clientBand;

  /// 자르지 않은 화면 x(타일 조각을 합친 것).
  double rawLeft = double.infinity, rawRight = double.negativeInfinity;

  /// 매달릴 수 있는 범위(상국 띠 안쪽 10px).
  double lo = 0, hi = 0;

  /// 자료로 본 이음(앞 · 뒤 구간과 맞닿아 있는가 — 0.5px 틈을 두는지가 여기에 달렸다).
  bool prevJoin = false, nextJoin = false;

  /// 자른 뒤의 자리와 모습.
  double left = 0, right = 0;
  bool drawn = false, joinLeft = false, joinRight = false, clipLeft = false, clipRight = false, unknownStart = false, unknownEnd = false;

  /// 앞 조각의 끝이 미정이라 사이 구분선도 점선(u-l) · 모호한 연대라 그쪽 테두리가 점선(z-l · z-r).
  bool dashLeft = false, zoneLeft = false, zoneRight = false;

  /// 이름과 그 폭(장면마다 한 번 — 이름은 긴 칸의 첫 칸에만)과 유령 구분선을 비켜 옮긴 만큼.
  String? label;
  double labelWidth = 0, fade = 0, labelShift = 0;

  /// 모호한 연대의 무늬 조각(왼쪽 · 오른쪽 · 0 추정 · 1 전승).
  List<(double, double, int)> layers = const [];

  /// 밝기와 강조(검색 · 창에 걸린 속국).
  double alpha = 1;
  bool matched = false;

  /// 이 조각에 걸린 기간 조명 구간(왼쪽 · 오른쪽 · 진행).
  List<(double, double, double)> spots = const [];
}

/// 구역 탭 · 바탕 문화 이름처럼 잇지 않는 항목 하나(타일 조각을 합친 자리만 쓴다).
class _Span {
  _Span(this.id, this.row, this.color, this.name, this.text2, this.a, this.b, this.c, this.d, this.host);
  final int id, row, color, a, b, c, d, host;
  final String name, text2;
  double rawLeft = double.infinity, rawRight = double.negativeInfinity;
}

/// 구역 45 — 이설이 말하는 경계 하나(유령 구분선). 그을지는 자리를 정한 뒤에 가린다(altMarks).
class _GhostLine {
  _GhostLine(this.row, this.lane, this.client, this.x);
  final int row, lane;
  final String client;
  final double x;
  int color = 0;
  double alpha = 1;
  bool drawn = false;
}

/// 구역 44 — 이름표의 모호한 연대 구간 하나(연대 폭). 같은 속국의 구간 전체에서 모아 조각마다 잘라 쓴다.
class _Vague {
  _Vague(this.row, this.lane, this.client, this.kind);
  final int row, lane, kind;
  final String client;
  double x0 = double.infinity, x1 = double.negativeInfinity;
}

/// 매달린 탭 · 구역 탭의 둥근 모서리 조각. 항목마다 둥근 네모를 그리면 하나하나가 따로 처리되므로,
/// 반지름 6 · 5의 네 모서리를 채움과 1px 고리로 한 장에 그려 두고 [flush]에서 drawRawAtlas 한 번으로 찍는다.
/// (scene/sprites.dart의 방식을 본떴지만 그 파일은 고치지 않는다 — 이 층의 조각은 이 층이 든다.)
class TabSprites {
  ui.Image? _image;
  double _scale = 1;

  static const _cell = 8.0, _sheet = 40.0;

  /// 실로 매단 꼬리표의 구멍(지름 [hole] 6 칸 · 반지름 2.5 · 가운데 3): 종이 채움과 1px 고리.
  static const hole = 6.0;
  static const holeFill = ui.Rect.fromLTWH(0, _cell * 4, hole, hole), holeRing = ui.Rect.fromLTWH(_cell, _cell * 4, hole, hole);
  static const big = HangLook.radius, small = HangLook.zoneRadius;

  /// 채움 조각(반지름 6): 왼쪽 위 · 오른쪽 위 · 왼쪽 아래 · 오른쪽 아래.
  static const fillTopLeft = ui.Rect.fromLTWH(0, 0, big, big), fillTopRight = ui.Rect.fromLTWH(_cell, 0, big, big);
  static const fillBottomLeft = ui.Rect.fromLTWH(_cell * 2, 0, big, big), fillBottomRight = ui.Rect.fromLTWH(_cell * 3, 0, big, big);

  /// 1px 고리 조각(반지름 6).
  static const ringTopLeft = ui.Rect.fromLTWH(0, _cell, big, big), ringTopRight = ui.Rect.fromLTWH(_cell, _cell, big, big);
  static const ringBottomLeft = ui.Rect.fromLTWH(_cell * 2, _cell, big, big), ringBottomRight = ui.Rect.fromLTWH(_cell * 3, _cell, big, big);

  /// 반지름 5의 채움과 고리(구역 탭).
  static const zoneFillTopLeft = ui.Rect.fromLTWH(0, _cell * 2, small, small), zoneFillTopRight = ui.Rect.fromLTWH(_cell, _cell * 2, small, small);
  static const zoneFillBottomLeft = ui.Rect.fromLTWH(_cell * 2, _cell * 2, small, small), zoneFillBottomRight = ui.Rect.fromLTWH(_cell * 3, _cell * 2, small, small);
  static const zoneRingTopLeft = ui.Rect.fromLTWH(0, _cell * 3, small, small), zoneRingTopRight = ui.Rect.fromLTWH(_cell, _cell * 3, small, small);
  static const zoneRingBottomLeft = ui.Rect.fromLTWH(_cell * 2, _cell * 3, small, small), zoneRingBottomRight = ui.Rect.fromLTWH(_cell * 3, _cell * 3, small, small);

  /// 멎은 돋보기 배율(× 화면의 px 비율)을 알려 준다. 바뀌었으면 그 배율로 다시 뜬다(작아서 싸다).
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  ui.Image _sheetImage() {
    final s = _scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(s);
    final white = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    final line = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    // 네 모서리는 각각 원 하나를 제 칸에만 보이게 잘라 그린다. 열 차례는 왼쪽 위 · 오른쪽 위 · 왼쪽 아래 · 오른쪽 아래이고,
    // 원의 가운데는 그 사분면이 칸에 들도록 놓는다(왼쪽 위 조각이면 칸의 오른쪽 아래가 원의 가운데).
    for (final (row, radius, paint, inset) in [(0, big, white, 0.0), (1, big, line, .5), (2, small, white, 0.0), (3, small, line, .5)]) {
      for (int col = 0; col < 4; col++) {
        final ox = col * _cell, oy = row * _cell;
        final left = col == 0 || col == 2, upper = col < 2;
        // 채움은 테두리 밑까지 깔리므로 반지름 그대로, 고리는 테두리 1px의 한가운데(반지름 − 0.5)에 긋는다.
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(ox, oy, radius, radius));
        canvas.drawCircle(ui.Offset(left ? ox + radius : ox, upper ? oy + radius : oy), radius - inset, paint);
        canvas.restore();
      }
    }
    // 구멍: 반지름 2.5의 채움과 고리(고리는 그 반지름에 1px).
    canvas.drawCircle(const ui.Offset(hole / 2, _cell * 4 + hole / 2), HangLook.tagHoleR, white);
    canvas.drawCircle(const ui.Offset(_cell + hole / 2, _cell * 4 + hole / 2), HangLook.tagHoleR, line);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheet * s).ceil(), (_sheet * s).ceil());
    picture.dispose();
    return image;
  }

  Float32List _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  Int32List _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 조각 하나를 왼쪽 위 자리(배치 px)에 찍는다. [size]는 좁은 칸에서 조각을 줄여 찍을 비율.
  void add(ui.Rect source, double left, double top, int argb, [double size = 1]) {
    if (argb >> 24 == 0) return;
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = size / s;
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
    final image = _image ??= _sheetImage();
    canvas.drawRawAtlas(image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4),
        Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

class HangLayer extends TileLayer {
  /// 일반 구역의 번호(계약 6-4절).
  static const sectionHang = 16, sectionZone = 17, sectionHem = 18, sectionVague = 44, sectionAlt = 45;

  final sprites = TabSprites();

  /// 밝기 상태(총괄이 장면에 넣기 전에는 중립). 층은 장면마다 여기서만 밝기를 묻는다.
  em.Emphasis? emphasis;
  static final em.Emphasis _neutral = em.Emphasis();

  em.Emphasis get _em => emphasis ?? _neutral;

  /// 소속이 펼쳐진 상위 띠의 번호(`▸ n` → `▾`). 그 띠의 속국은 제 줄의 띠로 나오므로 이름표 · 끈을 그리지 않는다(밭은 총괄이 채운다).
  final expanded = <int>{};

  final _tone = <int, _Tone>{}, _zoneTone = <int, _ZoneTone>{}, _hemTone = <int, _HemTone>{};

  /// 띠 id → 화면에서의 왼쪽 · 오른쪽 끝과 미정 끝 표시(장면의 처음에 보이는 타일 모두에서 모은다).
  final _bandLeft = <int, double>{}, _bandRight = <int, double>{};
  final _bandFade = <int, int>{};

  /// 띠 id → look(두 장 꼬리표의 몸통 아랫변 — 매단 꼬리표의 실이 거기서 내려온다).
  final _bandLook = <int, int>{};

  /// 띠의 연대 폭(구역 19)이 넓혀 주는 끝.
  final _rangeLeft = <int, double>{}, _rangeRight = <int, double>{};

  /// 이번 장면의 이름표 · 세로 끈 · 구역 탭 · 바탕 문화 이름(항목 id로 짚는다)과 모호한 연대 구간.
  final _tabs = <int, _Tab>{}, _links = <int, _Span>{}, _zones = <int, _Span>{}, _hems = <int, _Span>{};
  final _vague = <int, _Vague>{};

  /// 구역 45에서 온 이설 경계와, 자리를 가려 실제로 그을 유령 구분선.
  final _altEdges = <int, _GhostLine>{};
  final _ghosts = <_GhostLine>[];

  /// 이설(다른 견해) 표시를 켰는가(표시 상태의 [SceneMarks.showAlt]). 꺼 두면 지금 연표처럼 유령 구분선이 없어지고,
  /// 그 선을 비켜 가던 이름표도 제자리로 돌아온다(js/timeline.js 6181 `alt: this.showAlt && !this._bird` — 끄면
  /// `altRowPlan`의 `lines` · `shift`가 모두 빈다). 구역 44의 모호한 연대 무늬는 이 체크와 상관없이 그대로다(js:6172의 '무늬는 그대로').
  bool _showAlt = true;

  /// 품은 칸(칸 종류 7)의 자리 — 세로 끈이 다른 속국의 칸을 가로지르는지 볼 때(depLinkBlocked). 이름이 곧 그 속국이다.
  final _held = <(int row, int lane, double x0, double x1, String name)>[];

  /// 이번 장면에 그린 것의 누름 상자(뒤에 그린 것이 위).
  final _hits = <_HitBox>[];

  /// 이번 장면에 기간 조명 구간을 갈라 칠할 일이 있는가 — 켜져 있거나([em.Look.lit]), 거둔 구간이 아직 옅어지는 중이다.
  /// 이름표마다 묻지 않고 장면마다 한 번만 [beginFrame]에서 정한다.
  bool _litFrame = false;

  @override
  void setScale(double scale) => sprites.setScale(scale);

  @override
  void flush(PaintContext c) => sprites.flush(c.canvas);

  @override
  void beginFrame(PaintContext c) {
    _showAlt = SceneMarks.of(c.scene).showAlt;
    _litFrame = _em.look.lit || _em.litMoving;
    _bandLeft.clear();
    _bandRight.clear();
    _bandFade.clear();
    _bandLook.clear();
    _rangeLeft.clear();
    _rangeRight.clear();
    _tabs.clear();
    _links.clear();
    _zones.clear();
    _hems.clear();
    _vague.clear();
    _altEdges.clear();
    _ghosts.clear();
    _held.clear();
    _hits.clear();
    // 조감: 줄이 띠 하나뿐이라 매달린 이름표 · 세로 끈 · 구역 탭 · 바탕 문화 이름 단이 모두 빠진다(명세 05의 7.2).
    if (c.layout.conditions.density >= HangLook.birdDensity) return;
    final v = c.v;
    // 1) 상국 · 얹히는 띠의 양 끝: 탭은 그 띠 안쪽 10px에 매달리므로 띠의 좌표가 있어야 자리를 정할 수 있다(계약 7-3절).
    for (final d in c.scene.draw) {
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        final id = t.bandId[i], flags = t.bandFlags[i];
        // 연대 폭이 있는 끝은 그 조각에만 표시가 붙는다 — 조각을 모두 훑어 모은다.
        _bandFade[id] = (_bandFade[id] ?? 0) | (flags & (Tile.fuzzyStart | Tile.fuzzyEnd));
        _bandLook[id] = t.bandLook[i];
        if (flags & Tile.clipLeft == 0) {
          final x = v.xOf(origin + t.bandX0[i]);
          if (x < (_bandLeft[id] ?? double.infinity)) _bandLeft[id] = x;
        }
        if (flags & Tile.clipRight == 0) {
          final x = v.xOf(origin + t.bandX1[i]);
          if (x > (_bandRight[id] ?? double.negativeInfinity)) _bandRight[id] = x;
        }
      }
      // 2) 띠의 연대 폭(구역 19): 지금 연표의 bandStart는 startRange[0]이라 띠의 두 끝이 연대 폭까지 품는다.
      _collectRanges(c, t);
      // 3) 이름표 · 끈 · 구역 탭 · 바탕 문화 이름 · 모호한 연대: 타일 조각을 항목 id로 합친다.
      _collect(c, t, sectionHang);
      _collect(c, t, sectionZone);
      _collect(c, t, sectionHem);
      _collectVague(c, t);
      _collectAlts(c, t);
      _collectHeld(c, t);
    }
    // 연대 폭은 그 띠를 이미 아는 때만 넓힌다 — 띠 조각이 모두 잘려 있으면(화면 밖으로 이어짐) 어차피 끝을 모른다.
    for (final e in _rangeLeft.entries) {
      final at = _bandLeft[e.key];
      if (at != null && e.value < at) _bandLeft[e.key] = e.value;
    }
    for (final e in _rangeRight.entries) {
      final at = _bandRight[e.key];
      if (at != null && e.value > at) _bandRight[e.key] = e.value;
    }
    _resolveTabs(c);
  }

  /// 구역 19(띠의 연대 폭)를 모아 띠의 두 끝을 넓힌다.
  void _collectRanges(PaintContext c, Tile t) {
    final sec = t.section(19);
    if (sec.count == 0) return;
    final v = c.v;
    final origin = t.origin.toDouble();
    final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
    final ref = sec.u(Tile.itemRef), side = sec.u(Tile.itemA), flags = sec.u(Tile.itemFlags);
    for (int i = 0; i < sec.count; i++) {
      if (side[i] == 0 && flags[i] & Tile.clipLeft == 0) {
        final x = v.xOf(origin + x0[i]);
        if (x < (_rangeLeft[ref[i]] ?? double.infinity)) _rangeLeft[ref[i]] = x;
      } else if (side[i] == 1 && flags[i] & Tile.clipRight == 0) {
        final x = v.xOf(origin + x1[i]);
        if (x > (_rangeRight[ref[i]] ?? double.negativeInfinity)) _rangeRight[ref[i]] = x;
      }
    }
  }

  /// 타일 [t]의 구역 [kind]를 훑어 이번 장면의 항목에 조각을 더한다(같은 항목이 여러 타일에 나뉘어 올 수 있다).
  void _collect(PaintContext c, Tile t, int kind) {
    final sec = t.section(kind);
    if (sec.count == 0) return;
    final v = c.v, layout = c.layout;
    final origin = t.origin.toDouble();
    final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
    final id = sec.u(Tile.itemId), row = sec.u(Tile.itemRow);
    final ref = sec.u(Tile.itemRef), color = sec.u(Tile.itemColor), name = sec.u(Tile.itemName), text2 = sec.u(Tile.itemText2);
    final a = sec.u(Tile.itemA), b = sec.u(Tile.itemB), cc = sec.u(Tile.itemC), d = sec.u(Tile.itemD);
    for (int i = 0; i < sec.count; i++) {
      final r = row[i];
      if (r >= layout.rowCount || !layout.hasBody(r)) continue;
      // 소속이 펼쳐진 상위 띠의 속국은 제 줄의 띠로 나온다 — 이름표 · 끈을 그리지 않는다.
      if (kind == sectionHang && expanded.contains(ref[i])) continue;
      final left = v.xOf(origin + x0[i]), right = v.xOf(origin + x1[i]);
      if (kind == sectionHang && b[i] != HangLook.link) {
        final tab = _tabs[id[i]] ??= _Tab(id[i], r, a[i], b[i], cc[i], color[i], t.text(name[i]), t.text(text2[i]), ref[i], d[i]);
        if (left < tab.rawLeft) tab.rawLeft = left;
        if (right > tab.rawRight) tab.rawRight = right;
      } else {
        final into = kind == sectionHang ? _links : (kind == sectionZone ? _zones : _hems);
        final span = into[id[i]] ??= _Span(id[i], r, color[i], t.text(name[i]), t.text(text2[i]), a[i], b[i], cc[i], d[i], ref[i]);
        if (left < span.rawLeft) span.rawLeft = left;
        if (right > span.rawRight) span.rawRight = right;
      }
    }
  }

  /// 구역 44 — 이름표의 모호한 연대 구간(연대 폭). 같은 속국 · 같은 줄의 것을 모아 조각마다 자른다.
  void _collectVague(PaintContext c, Tile t) {
    final sec = t.section(sectionVague);
    if (sec.count == 0) return;
    final v = c.v, layout = c.layout;
    final origin = t.origin.toDouble();
    final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
    final row = sec.u(Tile.itemRow), ref = sec.u(Tile.itemRef), a = sec.u(Tile.itemA), b = sec.u(Tile.itemB), text2 = sec.u(Tile.itemText2);
    final id = sec.u(Tile.itemId);
    for (int i = 0; i < sec.count; i++) {
      final r = row[i];
      if (r >= layout.rowCount || !layout.hasBody(r) || expanded.contains(ref[i])) continue;
      // 타일 경계에 걸린 구간은 조각으로 나뉘어 오므로 항목 번호로 합친다.
      final at = _vague[id[i]] ??= _Vague(r, a[i], t.text(text2[i]), b[i]);
      final left = v.xOf(origin + x0[i]), right = v.xOf(origin + x1[i]);
      if (left < at.x0) at.x0 = left;
      if (right > at.x1) at.x1 = right;
    }
  }

  /// 구역 45 — 이설이 말하는 경계. `start`가 선의 자리이므로 왼쪽 끝을 든 조각만 읽는다.
  void _collectAlts(PaintContext c, Tile t) {
    if (!_showAlt) return; // '이설' 체크를 끄면 유령 구분선도 이름표 비킴도 없다
    final sec = t.section(sectionAlt);
    if (sec.count == 0) return;
    final v = c.v, layout = c.layout;
    final origin = t.origin.toDouble();
    final x0 = sec.f(Tile.itemX0);
    final row = sec.u(Tile.itemRow), ref = sec.u(Tile.itemRef), a = sec.u(Tile.itemA), text2 = sec.u(Tile.itemText2);
    final id = sec.u(Tile.itemId), flags = sec.u(Tile.itemFlags);
    for (int i = 0; i < sec.count; i++) {
      final r = row[i];
      if (r >= layout.rowCount || !layout.hasBody(r) || expanded.contains(ref[i]) || flags[i] & Tile.clipLeft != 0) continue;
      _altEdges[id[i]] ??= _GhostLine(r, a[i], t.text(text2[i]), v.xOf(origin + x0[i]));
    }
  }

  /// 품은 칸(칸 종류 7)의 자리 — 세로 끈이 다른 속국의 칸을 가로지르는지 볼 때 쓴다(지금 연표의 depLinkBlocked).
  void _collectHeld(PaintContext c, Tile t) {
    final v = c.v, layout = c.layout;
    final origin = t.origin.toDouble();
    for (int i = 0; i < t.cellCount; i++) {
      if (t.cellKindOf(i) != 7) continue;
      final r = t.cellRow[i];
      if (r >= layout.rowCount || !layout.hasBody(r)) continue;
      _held.add((r, t.cellLane[i] & 0xff, v.xOf(origin + t.cellX0[i]), v.xOf(origin + t.cellX1[i]), t.text(t.cellName[i])));
    }
  }

  /// 매달린 탭의 자리를 장면 전체로 한 번 정한다 — 지금 연표의 `layoutStrip`(js/timeline.js:235)과 같은 식.
  /// 같은 속국의 이어지는 구간은 하나의 긴 둥근 칸 + 가는 구분선이 되고, 너무 좁아 그리지 않는 칸이 있어도 무리가 끊기지 않게 앞 칸을 늘려 빈틈을 메운다.
  void _resolveTabs(PaintContext c) {
    if (_tabs.isEmpty) return;
    final list = _tabs.values.toList()
      ..sort((p, q) {
        final row = p.row.compareTo(q.row);
        if (row != 0) return row;
        final lane = p.lane.compareTo(q.lane);
        if (lane != 0) return lane;
        final at = p.rawLeft.compareTo(q.rawLeft);
        return at != 0 ? at : p.id.compareTo(q.id);
      });
    final left = c.left, width = c.w;
    // 1) 상국 띠 안쪽 10px에 드는 구간만 고른다(띠가 화면 밖으로 이어지면 화면 가장자리까지).
    final vis = <_Tab>[];
    for (final tab in list) {
      if (!_bandFade.containsKey(tab.host)) continue; // 상국 띠가 이번 장면에 없으면 자리를 정할 수 없다
      final bandLeft = _bandLeft[tab.host] ?? double.negativeInfinity, bandRight = _bandRight[tab.host] ?? double.infinity;
      tab.lo = bandLeft < left - 1 ? left - 1 : bandLeft + HangLook.inset;
      tab.hi = bandRight > width + 1 ? width + 1 : bandRight - HangLook.inset;
      if (tab.rawRight <= tab.lo || tab.rawLeft >= tab.hi) continue;
      tab.clipLeft = tab.rawLeft <= tab.lo && bandLeft < left - 1;
      tab.clipRight = tab.rawRight >= tab.hi && bandRight > width + 1;
      vis.add(tab);
    }
    // 2) 이음(joins): 같은 줄 · 같은 단에서 바로 앞 구간이 같은 속국이고 시간으로도 맞닿아 있을 때만
    //    (자료가 굳혀 실어 보낸 c의 4비트 + 화면에서 1.5px 안 — 지금 연표의 joins와 같은 두 조건).
    for (int i = 1; i < vis.length; i++) {
      final p = vis[i - 1], q = vis[i];
      if (p.row != q.row || p.lane != q.lane) continue;
      final joined = q.style & HangLook.joinLeft != 0 && p.client == q.client && (q.rawLeft - p.rawRight).abs() < HangLook.joinGap;
      p.nextJoin = joined;
      q.prevJoin = joined;
    }
    // 3) 자리 · 그릴지 · 이어 붙은 끝. 너무 좁아 그리지 않는 칸이 사이에 있어도 이음이 끊기지 않으면 앞 칸을 늘려 빈틈을 메운다.
    _Tab? lastDrawn;
    int group = -1;
    bool chain = true;
    for (final tab in vis) {
      final key = tab.row << 8 | tab.lane;
      if (key != group) {
        group = key;
        lastDrawn = null;
        chain = true;
      }
      final atL = tab.rawLeft <= tab.lo, atR = tab.rawRight >= tab.hi;
      tab.left = atL ? tab.lo : tab.rawLeft + (tab.prevJoin ? 0 : .5);
      tab.right = atR ? tab.hi : tab.rawRight - (tab.nextJoin ? 0 : .5);
      tab.unknownStart = tab.style & HangLook.unknownStart != 0 && !tab.clipLeft;
      tab.unknownEnd = tab.style & HangLook.unknownEnd != 0 && !tab.clipRight;
      chain = chain && tab.prevJoin;
      tab.drawn = tab.right - tab.left >= HangLook.minWidth;
      if (!tab.drawn) continue;
      if (lastDrawn != null && chain) {
        tab.joinLeft = true;
        lastDrawn.joinRight = true;
        if (lastDrawn.right < tab.left) lastDrawn.right = tab.left;
        // 앞 조각의 끝이 미정이면 사이 구분선(이 조각의 왼쪽 테두리)도 점선이다(css의 u-l).
        tab.dashLeft = lastDrawn.style & HangLook.unknownEnd != 0;
      }
      lastDrawn = tab;
      chain = true;
    }
    // 4) 이름과 미정 꼬리: 잘리지 않은 칸 전체의 폭으로 잰다(계약 7-3절) — 타일 조각마다 답이 달라지지 않게.
    for (final tab in vis) {
      if (!tab.drawn) continue;
      final tone = _tone[tab.color] ??= _Tone(tab.color);
      final room = tab.right - tab.left;
      // 매단 꼬리표: 구멍 뒤(왼쪽 + 12)부터 오른쪽 끝 2 앞까지 — 이름 → 첫 글자 → 없음(목업 fitHang(room − 14, 4, 2)).
      tab.label = tab.joinLeft || tab.name.isEmpty ? null : _fit(c, tab.name, tone.tagLook, room - HangLook.tagTextX - 2, 4, 2);
      tab.labelWidth = tab.label == null ? 0 : (c.text.widthOf(tab.label!, tone.tagLook) ?? 0);
      // 미정 끝의 꼬리(unkCell): max(3, min(44, 폭 × 0.4, 이름이 있으면 (폭 − 글자 폭) / 2 아니면 폭 × 0.3)).
      tab.fade = math.max(3.0, math.min(Look.fuzzyFade, math.min(room * .4, tab.label == null ? room * .3 : (room - tab.labelWidth) / 2)));
    }
    // 5) 모호한 연대(altRowPlan의 zones): 같은 속국 · 같은 단에서 모은 구간을 조각마다 잘라 담고, 그 구간에 걸친 경계는 점선으로.
    _resolveVague(vis);
    // 5-1) 이설의 유령 구분선과 이름표 비킴(altMarks).
    _resolveGhosts(vis);
    // 6) 밝기: 매달린 이름표는 상국 띠의 **자식이 아니라 줄 직속**이라(js:8149가 `out`에 붙인다) 띠의 흐림을 물려받지 않는다 —
    //    고른 동안 .5(고른 것이 그 속국이면 1) · 강조 밖 .25(강조에 든 속국은 1)로, 탭과 같은 값이다(C:1724 · C:1725).
    final look = _em.look;
    for (final tab in vis) {
      if (!tab.drawn) continue;
      tab.matched = look.filtered && tab.clientBand != 0 && (look.bands?.contains(tab.clientBand) ?? false);
      tab.alpha = _em.tabAlpha(tab.clientBand);
      tab.spots = _spotsOn(c, tab.host, tab.left, tab.right);
    }
  }

  /// 이 띠에 걸린 기간 조명 구간(화면 px)과 그 진행. 흐린 띠 안에서도 조명 구간만 밝게 남는 [em.Look.lit]일 때 갈라 칠한다.
  /// 흐르는 동안에는 켜지는 구간과 꺼지는 구간이 함께 오고 저마다 [em.Spot.glow]를 싣는다 — 다 꺼진 것은 버린다.
  ///
  /// 조명이 꺼진 뒤에도(창을 닫아 구간을 거두면) 아직 옅어지는 구간은 남는다 — 명세 06의 3-3 '물러남'(160ms · css `.lit-out`).
  /// 그것은 [em.Look.spots]에서 빠졌는데도 [em.Emphasis.spotsOf]에 진행이 줄며 남아 있는 구간이다.
  /// 거꾸로 `lit`이 꺼진 채 **새로 온** 구간은 조명이 아니므로 밝히지 않는다.
  List<(double, double, double)> _spotsOn(PaintContext c, int band, double l, double r) {
    if (!_litFrame) return const [];
    final lit = _em.look.lit;
    List<(double, double, double)>? out;
    for (final s in _em.spotsOf(band)) {
      if (s.glow <= .004) continue;
      if (!lit && _wanted(s)) continue;
      final a = c.v.xOf(s.start), z = c.v.xOf(s.end);
      if (z <= l || a >= r) continue;
      (out ??= []).add((a, z, s.glow));
    }
    return out ?? const [];
  }

  /// 이 구간이 지금 [em.Look.spots]가 바라는 것인가(= 거두는 중이 아니다). 구간은 한 줌뿐이라 그냥 훑는다.
  bool _wanted(em.Spot s) {
    for (final w in _em.look.spots) {
      if (w.key == s.key) return true;
    }
    return false;
  }

  /// 조명 구간의 밝기 — 켜져 있는 동안은 1(흐린 띠 안에서도)이고, 거두는 동안에도 같은 1이다
  /// (진행이 1 → 0으로 줄며 `base + (1 − base) × glow`가 이름표의 밝기로 내려간다). 구간이 없으면 [_Shade]가 쓰지 않는다.
  static const double _spotLit = 1;

  /// 모호한 연대의 무늬 조각과 점선 경계. 구간은 **같은 속국의 조각 전체**에서 모으고(연대 폭은 제 조각 밖으로도 뻗는다),
  /// 확실성만 적어 폭이 없는 조각은 그 조각 전체가 무늬다(지금 연표 altRowPlan의 zones와 같은 식).
  void _resolveVague(List<_Tab> vis) {
    final spans = <String, List<(double, double, int)>>{};
    void put(int row, int lane, String client, double a, double b, int kind) {
      if (b - a < HangLook.vagueMin) return;
      (spans['$row|$lane|$client'] ??= []).add((a, b, kind));
    }

    for (final v in _vague.values) {
      put(v.row, v.lane, v.client, v.x0, v.x1, v.kind);
    }
    for (final tab in vis) {
      final bits = tab.style & (HangLook.vagueEstimated | HangLook.vagueLegend);
      if (!tab.drawn || bits == 0) continue;
      put(tab.row, tab.lane, tab.client, tab.left - .5, tab.right + .5, bits & HangLook.vagueLegend != 0 ? 1 : 0);
    }
    if (spans.isEmpty) return;
    for (final tab in vis) {
      if (!tab.drawn) continue;
      final list = spans['${tab.row}|${tab.lane}|${tab.client}'];
      if (list == null) continue;
      final inL = tab.left + 1, inR = tab.right - (tab.joinRight ? 0 : 1);
      // 무늬는 이름표 글자를 피해 간다(글자에서 3px + 반 픽셀 — 자간 · 반올림 여유).
      final inkL = tab.label == null ? null : tab.left + HangLook.textLeft - HangLook.vagueGap;
      final inkR = tab.label == null ? null : tab.left + HangLook.textLeft + tab.labelWidth + HangLook.vagueGap;
      final layers = <(double, double, int)>[];
      for (final s in list) {
        final a = math.max(s.$1, inL), b = math.min(s.$2, inR);
        if (tab.left > s.$1 + .25 && tab.left < s.$2 - .25) tab.zoneLeft = true;
        if (!tab.joinRight && tab.right > s.$1 + .25 && tab.right < s.$2 - .25) tab.zoneRight = true;
        if (b - a < HangLook.vagueMin) continue;
        for (final (p, q) in inkL == null ? [(a, b)] : [(a, math.min(b, inkL)), (math.max(a, inkR!), b)]) {
          if (q - p >= HangLook.vagueMin) layers.add((p, q, s.$3));
        }
      }
      if (layers.isNotEmpty) tab.layers = layers;
    }
  }

  /// 이설이 말하는 경계에 긋는 유령 구분선과, 그 선을 비켜 가는 이름표(지금 연표의 `altMarks`).
  /// 진짜 구분선 · 조각 끝 · 미정 꼬리 안 · 띠 밖의 선은 긋지 않고, 이름표에 닿으면 이름을 적게 움직이는 쪽으로 3px 비킨다.
  void _resolveGhosts(List<_Tab> vis) {
    if (_altEdges.isEmpty) return;
    // 같은 속국(같은 줄 · 같은 단)의 조각끼리 묶어 본다 — 경계는 제 속국의 칸 줄 안에서만 잰다.
    final groups = <String, List<_Tab>>{};
    for (final tab in vis) {
      if (tab.drawn) (groups['${tab.row}|${tab.lane}|${tab.client}'] ??= []).add(tab);
    }
    for (final edge in _altEdges.values) {
      final group = groups['${edge.row}|${edge.lane}|${edge.client}'];
      if (group == null) continue;
      // 선은 제 조각 밖(이웃 조각 · 조각 사이 빈자리)에도 설 수 있다 — 주인은 그 조각을 품은 것, 없으면 가장 가까운 것이다.
      _Tab? owner;
      var far = double.infinity;
      for (final tab in group) {
        if (edge.x >= tab.left && edge.x < tab.right) {
          owner = tab;
          break;
        }
        final d = edge.x < tab.left ? tab.left - edge.x : edge.x - tab.right;
        if (d < far) {
          far = d;
          owner = tab;
        }
      }
      if (owner == null || owner.right - owner.left < HangLook.ghostMinWidth) continue;
      if (edge.x < owner.lo || edge.x > owner.hi - 1) continue;
      var near = double.infinity;
      for (final tab in group) {
        near = math.min(near, math.min((tab.left - edge.x).abs(), (tab.right - edge.x).abs()));
      }
      if (near < HangLook.ghostGap) continue;
      // 미정 꼬리 안(칸이 사라지는 자리)에는 긋지 않는다.
      final fadeL = owner.unknownStart ? owner.fade : 0.0, fadeR = owner.unknownEnd ? owner.fade : 0.0;
      if (fadeL > 0 && edge.x <= owner.left + fadeL + 1) continue;
      if (fadeR > 0 && edge.x >= owner.right - fadeR - 1) continue;
      if (_ghosts.any((q) => q.row == edge.row && q.lane == edge.lane && (q.x - edge.x).abs() < HangLook.ghostGap)) continue;
      edge.color = owner.color;
      _ghosts.add(edge);
    }
    if (_ghosts.isEmpty) return;
    // 이름표 비킴: 선에서 3px 떨어지는 자리 가운데 가장 적게 움직이는 곳으로. 비킬 자리가 없으면 그 선을 뺀다.
    for (final tab in vis) {
      if (!tab.drawn || tab.label == null || tab.labelWidth <= 0) continue;
      final center = tab.left + HangLook.textLeft + tab.labelWidth / 2;
      final inside = [for (final m in _ghosts) if (m.row == tab.row && m.lane == tab.lane && m.x >= tab.left && m.x < tab.right) m];
      if (inside.isEmpty) continue;
      final half = tab.labelWidth / 2;
      final hits = [for (final m in inside) if (m.x + 1 > center - half - HangLook.ghostGap && m.x < center + half + HangLook.ghostGap) m];
      if (hits.isEmpty) continue;
      var segs = <(double, double)>[(tab.left + 1 + HangLook.ghostGap + half, tab.right - 1 - HangLook.ghostGap - half)];
      for (final m in inside) {
        final a = m.x - HangLook.ghostGap - half, b = m.x + 1 + HangLook.ghostGap + half;
        segs = [
          for (final s in segs) ...[(s.$1, math.min(s.$2, a)), (math.max(s.$1, b), s.$2)],
        ].where((s) => s.$2 >= s.$1).toList();
      }
      double? to;
      for (final s in segs) {
        final at = center.clamp(s.$1, s.$2);
        if (to == null || (at - center).abs() < (to - center).abs() - 1e-9) to = at;
      }
      if (to != null) {
        tab.labelShift = to - center;
      } else {
        _ghosts.removeWhere(hits.contains);
      }
    }
    for (final m in _ghosts) {
      for (final tab in vis) {
        if (tab.drawn && tab.row == m.row && tab.lane == m.lane && m.x >= tab.left && m.x < tab.right) m.alpha = tab.alpha;
      }
    }
  }

  /// 아직 긋지 않은 유령 구분선을 긋는다(선은 제 조각 안에 있지만 타일마다 나눠 그리지 않는다 — 장면에서 한 번).
  void _paintGhosts(PaintContext c) {
    if (_ghosts.isEmpty) return;
    final v = c.v, layout = c.layout;
    for (final m in _ghosts) {
      if (m.drawn) continue;
      m.drawn = true;
      final geo = layout.geo(m.row);
      if (m.lane >= geo.zoneLanes) continue;
      final laneTop = geo.zoneLaneTop(m.lane);
      if (laneTop < 0) continue;
      final top = v.yOf(layout.rowTop(m.row) + laneTop - (geo.hangLanes > 0 ? 0 : HangLook.tuck));
      final height = geo.hangHeight;
      if (!c.rowOnScreen(m.row, top, height)) continue;
      final tone = _tone[m.color] ??= _Tone(m.color);
      final alpha = withAlpha(tone.ghost, m.alpha);
      if (alpha >> 24 == 0) continue;
      c.quads.vLine(m.x, top + HangLook.ghostInset, top + height - HangLook.ghostInset, alpha,
          dash: HangLook.ghostOn, gap: HangLook.ghostOff, phase: top + HangLook.ghostInset);
      c.debug?.note('hang', HangMark('alt', m.row, m.lane, ui.Rect.fromLTWH(m.x, top + HangLook.ghostInset, 1, height - 2 * HangLook.ghostInset), alpha: m.alpha));
    }
  }

  /// 세로 끈만 앞 판에서(띠 채움 · 품은 칸 위에) 그렸는가. 지금 연표의 `.tl-hang-link`는 띠보다 **위**에 온다(z 없음 · DOM에서 띠 뒤)
  /// — painter.dart가 앞 판에서 [paintFront]를 부르면 여기가 켜지고, 뒤 판에서는 끈을 건너뛴다.
  bool linksInFront = false;

  @override
  void paintTile(PaintContext c, Tile t) {
    if (c.hide.contains('hangs') || c.layout.conditions.density >= HangLook.birdDensity) return;
    _paintHangs(c, t);
    _paintZones(c, t);
    _paintHems(c, t);
  }

  /// 띠 위에 얹히는 것(세로 끈) — 앞 판에서 부른다. 부르지 않으면 끈은 뒤 판에 그려져 띠에 가린 채로 남는다.
  void paintFront(PaintContext c, Tile t) {
    if (c.hide.contains('hangs') || c.layout.conditions.density >= HangLook.birdDensity) return;
    linksInFront = true;
    _paintLinks(c, t);
  }

  /// 구역 16의 세로 끈(b = 4)만 골라 그린다.
  void _paintLinks(PaintContext c, Tile t) {
    final sec = t.section(sectionHang);
    if (sec.count == 0) return;
    final ids = sec.u(Tile.itemId), flags = sec.u(Tile.itemFlags), look = sec.u(Tile.itemB);
    for (int i = 0; i < sec.count; i++) {
      // 끈은 제 시작(왼쪽 끝)을 든 조각만 긋는다.
      if (look[i] != HangLook.link || flags[i] & Tile.clipLeft != 0) continue;
      _paintLink(c, _links[ids[i]]);
    }
  }

  // ---- 매달린 속국 이름표(구역 16 · b 0~3)와 세로 끈(b = 4) ----

  void _paintHangs(PaintContext c, Tile t) {
    _paintGhosts(c);
    final sec = t.section(sectionHang);
    if (sec.count == 0) return;
    final v = c.v, layout = c.layout;
    final origin = t.origin.toDouble();
    final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
    final ids = sec.u(Tile.itemId), flags = sec.u(Tile.itemFlags), look = sec.u(Tile.itemB);
    // 실(두 장 ㄴ): 상국 몸통 아랫변에서 꼬리표 구멍 위까지 — 모든 꼬리표보다 먼저(아래 단 꼬리표의 실이 위 단 꼬리표 뒤로 지나게).
    for (int i = 0; i < sec.count; i++) {
      if (look[i] == HangLook.link || flags[i] & Tile.clipLeft != 0) continue;
      final tab = _tabs[ids[i]];
      if (tab == null || !tab.drawn || tab.joinLeft) continue;
      final geo = layout.geo(tab.row);
      if (geo.hangLanes <= 0 || tab.lane >= geo.hangLanes) continue;
      final laneTop = geo.zoneLaneTop(tab.lane);
      if (laneTop < 0) continue;
      final base = layout.rowTop(tab.row);
      final from = v.yOf(base + TagLook.bodyBottom(geo, _bandLook[tab.host] ?? 0, oldStore: !(layout.spec(tab.row)?.cellRows ?? false), loose: layout.conditions.density < 0));
      final hy = v.yOf(base + laneTop) + G.hang / 2;
      if (!c.rowOnScreen(tab.row, from, hy - from)) continue;
      final x = (tab.left + HangLook.tagHoleX).floorToDouble();
      c.quads.vLine(x, from, hy - HangLook.tagHoleR, withAlpha(mixSrgb(Look.ink, Look.paper, HangLook.threadInk), tab.alpha));
    }
    for (int i = 0; i < sec.count; i++) {
      final cutL = flags[i] & Tile.clipLeft != 0, cutR = flags[i] & Tile.clipRight != 0;
      if (look[i] == HangLook.link) {
        if (!cutL && !linksInFront) _paintLink(c, _links[ids[i]]);
        continue;
      }
      final tab = _tabs[ids[i]];
      if (tab == null || !tab.drawn) continue;
      final geo = layout.geo(tab.row);
      if (tab.lane >= geo.zoneLanes) continue;
      final laneTop = geo.zoneLaneTop(tab.lane);
      if (laneTop < 0) continue;
      final top = v.yOf(layout.rowTop(tab.row) + laneTop - (geo.hangLanes > 0 ? 0 : HangLook.tuck));
      final height = geo.hangHeight;
      if (!c.rowOnScreen(tab.row, top, height)) continue;
      // 제 조각의 몫만 그린다 — 조각들은 타일 경계에서 딱 나뉘므로 겹쳐 그려지지 않는다.
      final l = cutL ? math.max(tab.left, v.xOf(origin + x0[i])) : tab.left;
      final r = cutR ? math.min(tab.right, v.xOf(origin + x1[i])) : tab.right;
      if (r <= l) continue;
      _drawTab(c, tab, l, r, top, height, ownsLeft: l <= tab.left + .01, ownsRight: r >= tab.right - .01);
    }
  }

  /// 실로 매단 작은 꼬리표 하나(두 장 ㄴ — [HangLook.tagCham] 등): 칠 → 모호한 연대 무늬 → 테(왼쪽 두 귀 모따기 · 오른쪽 곧게) → 구멍 → 이름.
  /// 이어 붙은 쪽(같은 속국의 이은 관계)은 귀 · 구멍 · 이름 없이 옅은 구분선, 화면에 잘린 쪽은 세로 테가 없다.
  void _drawTab(PaintContext c, _Tab tab, double l, double r, double top, double height, {required bool ownsLeft, required bool ownsRight}) {
    final tone = _tone[tab.color] ??= _Tone(tab.color);
    final bottom = top + height;
    final fill = switch (tab.look) {
      HangLook.loose => tone.fillLoose,
      HangLook.plain => Look.paper,
      _ => tone.fillTag,
    };
    final edge = tab.matched ? HangLook.warn : tone.edge;
    final (dash, gap) = switch (tab.look) {
      HangLook.nominal => (HangLook.dotOn, 2.0),
      HangLook.plain => (HangLook.dashOn, HangLook.dashOff),
      _ => (0.0, 0.0),
    };
    // 미정인 쪽 끝의 옅어짐 · 기간 조명 · 고르기의 밝기를 한 판으로 모은다(이어 붙은 쪽은 .35까지만 옅어진다).
    final fadeL = tab.unknownStart && ownsLeft ? tab.fade : 0.0, fadeR = tab.unknownEnd && ownsRight ? tab.fade : 0.0;
    final shade = _Shade(tab.left, tab.right, fadeL, fadeR, tab.joinLeft ? HangLook.joinFade : 0, tab.joinRight ? HangLook.joinFade : 0,
        tab.alpha, _spotLit, tab.spots);
    final head = ownsLeft && !tab.joinLeft && !tab.clipLeft;
    final k = head ? math.min(HangLook.tagCham, (r - l) / 2).floorToDouble() : 0.0;
    // 칠: 귀는 줄마다 한 칸씩 들인다(3px — 길 없이 네모 묶음으로).
    _quad(c, l + k, top, r, bottom, fill, shade);
    if (k > 0) {
      _quad(c, l, top + k, l + k, bottom - k, fill, shade);
      for (int j = 0; j < k; j++) {
        _quad(c, l + k - j, top + j, l + k, top + j + 1, fill, shade);
        _quad(c, l + k - j, bottom - 1 - j, l + k, bottom - j, fill, shade);
      }
    }
    // 모호한 연대의 무늬: 바탕 위 · 테두리 밑.
    if (tab.layers.isNotEmpty) {
      final pt = top + 1, pb = bottom - 1;
      for (final (a, z, kind) in tab.layers) {
        final pl = math.max(a, l + k), pr = math.min(z, r);
        if (pr - pl < HangLook.vagueMin) continue;
        final spec = kind == 1 ? HangLook.vagueLegendPattern : HangLook.vagueEstimatedPattern;
        shade.steps(pl, pr, (p, q, al, az) => c.patterns.add(spec, p, pt, q, pb, withAlpha(tone.vague, (al + az) / 2), phaseX: a, phaseY: pt));
      }
    }
    // 테: 위 · 아래는 귀 뒤에서, 왼쪽은 귀 사이 + 귀의 빗변(1px 계단), 오른쪽은 제 끝일 때만.
    _hEdge(c, l + k, r, top, edge, shade, dash: dash, gap: gap, phase: tab.left);
    _hEdge(c, l + k, r, bottom - 1, edge, shade, dash: dash, gap: gap, phase: tab.left);
    if (ownsLeft && !tab.clipLeft) {
      if (tab.joinLeft) {
        _vEdge(c, l, top + 1, bottom - 1, tab.matched ? edge : tone.join, shade);
      } else {
        final (dl, gl) = _edgeDash(tab.zoneLeft, tab.unknownStart || tab.dashLeft, dash, gap);
        _vEdge(c, l, top + k, bottom - k, edge, shade, dash: dl, gap: gl, phase: top);
        for (int j = 0; j < k; j++) {
          _quad(c, l + k - 1 - j, top + j, l + k - j, top + j + 1, edge, shade);
          _quad(c, l + k - 1 - j, bottom - 1 - j, l + k - j, bottom - j, edge, shade);
        }
      }
    }
    if (ownsRight && !tab.clipRight && !tab.joinRight) {
      final (dr, gr) = _edgeDash(tab.zoneRight, tab.unknownEnd, dash, gap);
      _vEdge(c, r - 1, top, bottom, edge, shade, dash: dr, gap: gr, phase: top);
    }
    // 구멍: 왼쪽 끝 + 6 · 세로 가운데(실이 여기에 닿는다).
    if (ownsLeft && !tab.joinLeft) {
      final hx = (tab.left + HangLook.tagHoleX).floorToDouble() + .5, hy = top + height / 2;
      final a = shade.alphaAt(hx);
      sprites.add(TabSprites.holeFill, hx - TabSprites.hole / 2, hy - TabSprites.hole / 2, withAlpha(Look.paper, a));
      sprites.add(TabSprites.holeRing, hx - TabSprites.hole / 2, hy - TabSprites.hole / 2, withAlpha(mixSrgb(Look.ink, Look.paper, HangLook.threadInk), a));
    }
    c.stats.shapes++;
    _hits.add(_HitBox(ui.Rect.fromLTRB(l, top, r, bottom),
        HangHit('hang', band: tab.clientBand, host: tab.host, row: tab.row, lane: tab.lane, uid: tab.client, name: tab.name)));
    c.debug?.note(
      'hang',
      HangMark('hang', tab.row, tab.lane, ui.Rect.fromLTRB(l, top, r, bottom),
          name: tab.name, look: tab.look, ref: tab.host, joinLeft: tab.joinLeft, joinRight: tab.joinRight, openLeft: tab.clipLeft,
          alpha: tab.alpha, zones: tab.layers.length, dotted: '${tab.zoneLeft ? 'l' : ''}${tab.zoneRight ? 'r' : ''}'),
    );
    if (!ownsLeft || tab.label == null) return;
    // 이름: 구멍 뒤(왼쪽 + 12) · 꼬리표 세로 가운데.
    final at = tab.left + HangLook.tagTextX + tab.labelShift;
    c.later.add('hang', tab.label!, tone.tagLook, at, top + height / 2 - HangLook.tagSize * .6, shade.alphaAt(at + tab.labelWidth / 2));
  }

  /// 세로 테두리의 끊는 꼴: 모호한 연대에 걸치면 점선, 미정이면 대시, 아니면 탭 제 모습(z-l · z-r이 css에서 마지막 승자).
  (double, double) _edgeDash(bool zone, bool unknown, double dash, double gap) => zone
      ? (HangLook.dotOn, HangLook.dotOff)
      : unknown
          ? (HangLook.dashOn, HangLook.dashOff)
          : (dash, gap);

  /// 밖 ↔ 안을 옮긴 속국의 세로 끈: 매달린 탭의 가운데와 품은 칸의 가운데를 잇는다.
  void _paintLink(PaintContext c, _Span? span) {
    if (span == null) return;
    final layout = c.layout, v = c.v;
    final geo = layout.geo(span.row);
    if (geo.depTop < 0 || span.a >= geo.zoneLanes) return;
    final laneTop = geo.zoneLaneTop(span.a);
    if (laneTop < 0) return;
    final x = span.rawLeft;
    // 띠 안쪽 10px 밖이면 긋지 않는다(탭과 같은 테두리).
    final bandLeft = _bandLeft[span.host] ?? double.negativeInfinity, bandRight = _bandRight[span.host] ?? double.infinity;
    final lo = bandLeft < c.left - 1 ? c.left - 1 : bandLeft + HangLook.inset;
    final hi = bandRight > c.w + 1 ? c.w + 1 : bandRight - HangLook.inset;
    if (x < lo || x > hi) return;
    // 품은 칸은 0번 줄이 띠 아랫변에 가장 가깝다 — 그 줄의 예속 칸 자리에서 거꾸로 센다.
    final lanes = math.max(0, (geo.depHeight / HangLook.depPitch).round());
    final inLane = span.d - 1;
    if (inLane < 0) return;
    if (_linkBlocked(span, x, inLane)) return;
    final yRow = geo.depTop + math.max(0, lanes - 1 - inLane) * HangLook.depPitch + G.dep / 2;
    // 두 장 꼬리표: 예속 칸도 그 띠의 몸통 안 맞붙인 자리(bands.dart TagLook.compactOf)
    final yIn = (layout.spec(span.row)?.cellRows ?? false) ? TagLook.compactOf(geo, _bandLook[span.host] ?? 0, yRow) : yRow;
    final yOut = geo.hangLanes > 0 ? laneTop : laneTop + HangLook.linkOutLegacy - HangLook.tuck; // 매단 꼬리표(두 장 ㄴ)는 그 윗변까지
    final top = v.yOf(layout.rowTop(span.row) + math.min(yIn, yOut));
    final height = (yOut - yIn).abs();
    if (!c.rowOnScreen(span.row, top, height)) return;
    final tone = _tone[span.color] ??= _Tone(span.color);
    // 끈(`.tl-hang-link`)은 제 uid가 없어 `is-selected` · `is-dim`이 붙지 않는다(js:8165) —
    // 고른 동안은 제 속국을 골랐어도 .5이고, 강조만 걸렸을 때는 흐려지지 않는다(C:1724에만 든다).
    final twin = _twinOf(span);
    final alpha = _em.hangLinkDim;
    if (alpha <= .004) return;
    c.quads.add(x - HangLook.linkWidth / 2, top, x + HangLook.linkWidth / 2, top + height, withAlpha(tone.edge, alpha));
    c.stats.shapes++;
    _hits.add(_HitBox(ui.Rect.fromLTRB(x - 2, top, x + 2, top + height),
        HangHit('hang', band: twin?.clientBand ?? 0, host: span.host, row: span.row, lane: span.a, uid: span.text2, name: twin?.name ?? '')));
    c.debug?.note('hang',
        HangMark('link', span.row, span.a, ui.Rect.fromLTWH(x - HangLook.linkWidth / 2, top, HangLook.linkWidth, height), ref: span.host, alpha: alpha));
  }

  /// 끈이 [x]에서 다른 속국의 이름표 · 품은 칸을 가로지르는가 — 이 속국보다 띠에 가까운 줄의 것이 있으면 긋지 않는다(depLinkBlocked).
  bool _linkBlocked(_Span span, double x, int inLane) {
    for (final tab in _tabs.values) {
      if (tab.row != span.row || tab.client == span.text2 || tab.lane >= span.a) continue;
      if (tab.rawLeft - 1 < x && x < tab.rawRight + 1) return true;
    }
    // 품은 칸(칸 종류 7)은 이름이 곧 속국이다 — 같은 속국의 칸은 건너뛴다.
    final own = _twinOf(span)?.name ?? '';
    for (final (row, lane, x0, x1, name) in _held) {
      if (row != span.row || lane >= inLane) continue;
      if (own.isNotEmpty && name == own) continue;
      if (x0 - 1 < x && x < x1 + 1) return true;
    }
    return false;
  }

  /// 끈과 같은 속국의 이름표(같은 줄) — 밝기 · 이름 · 띠 번호를 빌린다.
  _Tab? _twinOf(_Span span) {
    for (final tab in _tabs.values) {
      if (tab.row == span.row && tab.client == span.text2) return tab;
    }
    return null;
  }

  // ---- 구역 탭(구역 17): 띠 아래로 내려오는 네 변 테두리의 작은 탭 ----

  void _paintZones(PaintContext c, Tile t) {
    final sec = t.section(sectionZone);
    if (sec.count == 0) return;
    final v = c.v, layout = c.layout;
    final origin = t.origin.toDouble();
    final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
    final ids = sec.u(Tile.itemId), flags = sec.u(Tile.itemFlags);
    for (int i = 0; i < sec.count; i++) {
      final span = _zones[ids[i]];
      if (span == null) continue;
      final geo = layout.geo(span.row);
      if (span.a >= geo.zoneLanes) continue;
      final laneTop = geo.zoneLaneTop(span.a);
      if (laneTop < 0) continue;
      // 구역 탭은 매달린 이름표 줄 아래에, 띠 아랫변에서 2px 띄워서.
      final top = v.yOf(layout.rowTop(span.row) + laneTop + HangLook.gap);
      if (!c.rowOnScreen(span.row, top, HangLook.tab)) continue;
      final fade = _bandFade[span.host];
      if (fade == null) continue; // 얹히는 띠가 이번 장면에 없으면 자리를 정할 수 없다
      // 얹히는 띠의 끝(미정 꼬리 44px 포함) 안쪽 10px에 가둔다.
      final hb0 = (_bandLeft[span.host] ?? double.negativeInfinity) - (fade & Tile.fuzzyStart != 0 ? Look.fuzzyFade : 0);
      final hb1 = (_bandRight[span.host] ?? double.infinity) + (fade & Tile.fuzzyEnd != 0 ? Look.fuzzyFade : 0);
      final la = span.rawLeft > hb0 + HangLook.inset ? span.rawLeft + .5 : hb0 + HangLook.inset;
      final rb = span.rawRight < hb1 - HangLook.inset ? span.rawRight - .5 : hb1 - HangLook.inset;
      final left = math.max(la, c.left), right = math.min(rb, c.w);
      if (right - left < HangLook.minWidth) continue;
      final cutL = flags[i] & Tile.clipLeft != 0, cutR = flags[i] & Tile.clipRight != 0;
      final l = cutL ? math.max(left, v.xOf(origin + x0[i])) : left;
      final r = cutR ? math.min(right, v.xOf(origin + x1[i])) : right;
      if (r <= l) continue;
      _drawZone(c, span, l, r, left, right, top, clipL: la < c.left, clipR: rb > c.w, ownsLeft: l <= left + .01, ownsRight: r >= right - .01);
    }
  }

  void _drawZone(PaintContext c, _Span span, double l, double r, double left, double right, double top,
      {required bool clipL, required bool clipR, required bool ownsLeft, required bool ownsRight}) {
    final tone = _zoneTone[span.color] ??= _ZoneTone(span.color);
    // 구역 탭은 `.tl-lane .tl-org.is-zone`이다(js:6748) — 줄 직속이라 얹히는 띠의 흐림을 받지 않고,
    // 고른 동안 .5(고른 것이 그 구역이면 1) · 강조에는 흐림 규칙이 없다(C:717 · C:935).
    // (고른 것 자신을 1로 되살리는 `is-selected`는 `Look`에 고른 것의 uid가 없어 아직 못 가린다 — 보고의 '총괄이 이어 줄 것'.)
    final alpha = _em.markAlpha(mine: false, matched: _em.look.matchedUid(span.text2), pick: em.Dim.orgPick, dim: em.Dim.orgDim);
    if (alpha <= .004) return;
    final shade = _Shade(left, right, 0, 0, 1, 1, alpha, _spotLit, _spotsOn(c, span.host, left, right));
    final fill = tone.fill, edge = tone.edge;
    final bottom = top + HangLook.tab;
    final roundL = ownsLeft && !clipL, roundR = ownsRight && !clipR;
    final radius = math.min(HangLook.zoneRadius, math.min((r - l) / (roundL && roundR ? 2 : 1), HangLook.tab / 2));
    final size = radius / HangLook.zoneRadius;
    // 네 모서리가 모두 둥근 작은 네모(css:816이 앞의 '아래만 둥근' 규칙을 덮어쓴다).
    if (roundL || roundR) {
      _quad(c, l + (roundL ? radius : 0), top, r - (roundR ? radius : 0), bottom, fill, shade);
      if (roundL) {
        _quad(c, l, top + radius, l + radius, bottom - radius, fill, shade);
        final a = shade.alphaAt(l + radius / 2);
        sprites.add(TabSprites.zoneFillTopLeft, l, top, withAlpha(fill, a), size);
        sprites.add(TabSprites.zoneFillBottomLeft, l, bottom - radius, withAlpha(fill, a), size);
        sprites.add(TabSprites.zoneRingTopLeft, l, top, withAlpha(edge, a), size);
        sprites.add(TabSprites.zoneRingBottomLeft, l, bottom - radius, withAlpha(edge, a), size);
      }
      if (roundR) {
        _quad(c, r - radius, top + radius, r, bottom - radius, fill, shade);
        final a = shade.alphaAt(r - radius / 2);
        sprites.add(TabSprites.zoneFillTopRight, r - radius, top, withAlpha(fill, a), size);
        sprites.add(TabSprites.zoneFillBottomRight, r - radius, bottom - radius, withAlpha(fill, a), size);
        sprites.add(TabSprites.zoneRingTopRight, r - radius, top, withAlpha(edge, a), size);
        sprites.add(TabSprites.zoneRingBottomRight, r - radius, bottom - radius, withAlpha(edge, a), size);
      }
    } else {
      _quad(c, l, top, r, bottom, fill, shade);
    }
    // 빗금: 바탕 위 · 테두리 밑(테두리 안쪽 1px에) — 조명 · 흐림의 밝기를 함께 받는다.
    shade.steps(l + 1, r - 1, (p, q, al, az) => c.patterns.add(HangLook.zoneHatch, p, top + 1, q, bottom - 1, withAlpha(0xff000000 | span.color, .20 * (al + az) / 2), phaseX: l, phaseY: top));
    _hEdge(c, l + (roundL ? radius : 0), r - (roundR ? radius : 0), top, edge, shade);
    _hEdge(c, l + (roundL ? radius : 0), r - (roundR ? radius : 0), bottom - 1, edge, shade);
    if (ownsLeft && !clipL) _vEdge(c, l, top + (roundL ? radius : 0), bottom - (roundL ? radius : 0), edge, shade);
    if (ownsRight && !clipR) _vEdge(c, r - 1, top + (roundR ? radius : 0), bottom - (roundR ? radius : 0), edge, shade);
    c.stats.shapes++;
    _hits.add(_HitBox(ui.Rect.fromLTRB(l, top, r, bottom), HangHit('zone', host: span.host, row: span.row, lane: span.a, uid: span.text2, name: span.name)));
    c.debug?.note('hang',
        HangMark('zone', span.row, span.a, ui.Rect.fromLTRB(l, top, r, bottom), name: span.name, ref: span.host, openLeft: clipL, alpha: alpha));
    if (!ownsLeft || span.name.isEmpty || right - left < HangLook.zoneThin) return;
    final label = _fit(c, span.name, tone.look, right - left, HangLook.zoneFitFull, HangLook.zoneFitFirst);
    if (label == null) return;
    c.later.add('zone', label, tone.look, l + HangLook.zoneTextLeft, top + 1 + (HangLook.zoneLine - HangLook.size * 1.2) / 2, alpha);
  }

  // ---- 바탕 문화의 아래 이름 단(구역 18) ----

  void _paintHems(PaintContext c, Tile t) {
    final sec = t.section(sectionHem);
    if (sec.count == 0) return;
    final v = c.v, layout = c.layout;
    final flags = sec.u(Tile.itemFlags), ids = sec.u(Tile.itemId);
    for (int i = 0; i < sec.count; i++) {
      // 이름 단은 한 번만 적는다 — 왼쪽 끝을 든 조각이 맡는다(바탕 문화 띠는 이름 단보다 훨씬 길 수 있다).
      if (flags[i] & Tile.clipLeft != 0) continue;
      final span = _hems[ids[i]];
      if (span == null) continue;
      final geo = layout.geo(span.row);
      if (geo.hemTop < 0) continue;
      // 이름 단은 바탕 문화 띠의 테두리 안쪽에 놓인다 — 줄 아랫변에서 12px 높이, 왼쪽에서 12px(테두리 1을 더해 13).
      final top = v.yOf(layout.rowTop(span.row) + geo.hemTop - 1);
      if (!c.rowOnScreen(span.row, top, G.hem)) continue;
      // 이름 단은 바탕 문화 띠의 자식이라 그 띠의 좌우를 그대로 따른다(항목의 기간이 아니라 — 연대 폭이 있는 문화는 띠가 더 넓다).
      final known = _bandFade.containsKey(span.host);
      final x1 = known ? (_bandLeft[span.host] ?? double.negativeInfinity) : span.rawLeft;
      final x2 = known ? (_bandRight[span.host] ?? double.infinity) : span.rawRight;
      final left = math.max(x1, c.left - 1);
      final width = math.max(3.0, math.min(x2, c.w + 1) - left);
      if (span.name.isEmpty) continue;
      // 이름이 띠 안에 드는지는 지금 연표와 같은 문턱으로 본다(폭 ≥ 11px로 잰 이름 폭 + 24).
      final probe = c.text.widthOf(span.name, HangLook.hemProbe);
      if (probe == null || width < probe + HangLook.hemFit) continue;
      final tone = _hemTone[span.color] ??= _HemTone(span.color);
      final nameWidth = c.text.widthOf(span.name, tone.name);
      if (nameWidth == null) continue;
      // 이름 단은 바탕 문화 띠의 밝기를 따른다.
      final alpha = _em.bandAlpha(span.host, span.row);
      if (alpha <= .004) continue;
      final at = left + HangLook.hemLeft;
      c.later.add('hem', span.name, tone.name, at, top + (G.hem - HangLook.size * 1.2) / 2, alpha);
      if (span.text2.isNotEmpty) {
        c.later.add('hem', span.text2, tone.small, at + nameWidth + HangLook.hemGap, top + (G.hem - HangLook.hemSize * 1.2) / 2, alpha);
      }
      _hits.add(_HitBox(ui.Rect.fromLTWH(at, top, nameWidth, G.hem), HangHit('hem', host: span.host, row: span.row, uid: span.text2, name: span.name)));
      c.debug?.note('hang', HangMark('hem', span.row, 0, ui.Rect.fromLTWH(at, top, nameWidth, G.hem), name: span.name, ref: span.host, alpha: alpha));
    }
  }

  // ---- 맞히기 ----

  /// [x] · [y](배치 px)에 있는 이름표 · 구역 탭 · 바탕 문화 이름. 없으면 null. 뒤에 그린 것(아래 줄 · 위 층)이 이긴다.
  HangHit? hitHangs(double x, double y) {
    for (int i = _hits.length - 1; i >= 0; i--) {
      if (_hits[i].rect.contains(ui.Offset(x, y))) return _hits[i].hit;
    }
    return null;
  }

  // ---- 함께 쓰는 것 ----

  /// 이름 맞춤: 온 이름 → 첫 글자 → 없음(_depLabel · 구역 탭의 같은 식). 폭을 아직 모르면 null.
  String? _fit(PaintContext c, String name, TextLook look, double room, double full, double first) {
    final width = c.text.widthOf(name, look);
    if (width == null) return null;
    if (room >= width + full) return name;
    final head = String.fromCharCode(name.runes.first);
    final headWidth = c.text.widthOf(head, look);
    if (headWidth == null) return null;
    return room >= headWidth + first ? head : null;
  }

  /// 네모 하나를 밝기 판에 따라 잘라 네모 묶음에 모은다(미정 끝의 옅어짐 · 조명 · 흐림을 한 번에).
  void _quad(PaintContext c, double l, double t, double r, double b, int argb, _Shade shade) {
    if (r <= l || b <= t) return;
    shade.steps(l, r, (a, z, al, az) => c.quads.addFade(a, t, z, b, withAlpha(argb, al), withAlpha(argb, az)));
  }

  /// 가로 테두리(점선 · 파선도) — 끊어 그린 조각마다 밝기를 먹인다.
  void _hEdge(PaintContext c, double x0, double x1, double y, int argb, _Shade shade, {double dash = 0, double gap = 0, double phase = 0}) {
    if (x1 <= x0) return;
    final top = y.floorToDouble();
    if (dash <= 0) {
      _quad(c, x0, top, x1, top + 1, argb, shade);
      return;
    }
    final period = dash + gap;
    var x = x0 - ((x0 - phase) % period + period) % period;
    for (; x < x1; x += period) {
      final a = x < x0 ? x0 : x, z = x + dash > x1 ? x1 : x + dash;
      if (z > a) _quad(c, a, top, z, top + 1, argb, shade);
    }
  }

  /// 세로 테두리 — 그 x의 밝기 하나로(세로선은 밝기가 꺾이지 않는다).
  void _vEdge(PaintContext c, double x, double y0, double y1, int argb, _Shade shade, {double dash = 0, double gap = 0, double phase = 0}) {
    if (y1 <= y0) return;
    final alpha = shade.alphaAt(x + .5);
    if (alpha <= .004) return;
    c.quads.vLine(x, y0, y1, withAlpha(argb, alpha), dash: dash, gap: gap, phase: phase);
  }
}
