// 줄 자리. 줄의 생김새는 넣을 때 정해져 저장소에 있고({op:layout}), 여기서는 보기 조건(켠 자료집 · 켠 단 · 밀도 · 접힌 줄)에 따라 위에서부터 쌓는다.
// 쌓는 일은 줄 수에 비례할 뿐이라 자료가 아무리 커도 한 장면 안에 끝난다. 식은 지금 연표의 _layoutTrack 4) · 5)와 _foldRows 그대로다(docs/계약-아카이브-3단계.md 3절).
//
// 두 가지 입력을 읽는다:
//  · 2판(2단계): 줄마다 굳은 자리 값(height · band_top …)만 있다 → 그 값을 그대로 쌓는다(트랙 여백 · 접기 없음).
//  · 3판: 줄마다 kind · phase · rank · cats · fig · dep · zones · hem이 있다 → 단을 다시 쌓는다. 줄의 자리는 '틈 + 띠 + 띠 아래 덧붙는 단'의 몫(slot)이고,
//    트랙마다 위아래 여백 9px · 트랙 사이 1px · 트랙 높이는 적어도 34px.
//
// 다시 쌓은 자리로 곧바로 뛰지 않는다: 접기 · 펼치기 · 밀도가 바뀌면 줄마다 (위 자리 · 높이)가 360ms 흐른다(row_flow.dart).
// 그리는 쪽은 rowTop(row) · geo(row) · isVisible(row)만 읽으므로, 흐르는 동안의 값도 이 접근자들이 돌려준다.

import 'dart:convert';

import 'row_flow.dart';
import 'view_state.dart';
import 'viewport.dart' show SceneView;

export 'view_state.dart';

/// 단의 높이와 틈 — 지금 연표의 G(js/timeline.js).
/// 통합 2026-10-13: 글줄(크기 × 1.2)과 1px 테두리 사이 최소 3px, 단 사이 최소 3px.
abstract final class G {
  static const pad = 9.0, inset = 4.0, slotGap = 3.0, line = 21.0, railPitch = 7.0;

  /// 꼬리표 = 두 장(리메이크 2부 · 감독 결정 '두 장 ㄴ' 2026-10-15 — 손그림 "맨 위 나라 색띠를 얇게 · 아래 지도자 부분이랑 흰부분이랑 또 하나의 색 띠"):
  /// **이름 색줄 [head] 14**(구멍 · 이름 · 꼬리 마름모 — 세로 가운데 7) 밑에 **몸통 띠** — 칸 뭉치(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관이
  /// [floor] 14씩 맞붙음 · 나라 색 옅은 칠) → **흰 사건 칸**([evLine] 18 · 펼친 꼬리표에 늘 · 넉넉하게는 글줄 수만큼) → 기간 막대 · 인물(넉넉하게).
  static const head = 14.0, floor = 14.0, evLine = 18.0;

  /// 위로 솟는 것(받침 카드 6 + 상국 · 연합 탭 12 — [RowSpec.raised])이 있는 줄만 위 틈에 더하는 몫: 줄 위 틈 5 + 15 = 20(목업 tabHS).
  static const raise = 15.0;

  /// 그릇의 줄(리메이크 조각 ③ · 설계 4-1 '줄 위 틈 — 그릇 안 15')이 위 틈에 더하는 몫: 5 + 10 = 15. 그릇의 줄 = 풀린 그릇의 열쇠표가 달린 줄
  /// ([RowSpec.contained]) · 켠 대범위 가지의 줄 — 풀렸으면 띠 위에 열쇠표(12 + 2)가, 펼쳤으면 매다는 실이 든다. 솟는 줄([raise])은 그 값이 이긴다.
  static const contain = 10.0;

  /// 그릇 폴더(리메이크 조각 ③ · 설계 4-1 '가장 바깥 그릇' · 목업 blend.js folder): 어깨 탭 [folderTab] 아래가 몸통이다.
  /// 머리 21 = 탭 20 + 1 — 첫 줄의 위 틈 15를 지나 띠 윗변이 몸통 윗변 아래 16에 선다(목업 headH 22 + tabH 15 − 탭 20 − 1).
  /// 발 7 = 마지막 띠 아래의 몸통 여백(목업 padB). 내보낸 `scope_pad`(지금 연표의 머리 16 · 발 6 · 매달린 머리 −4)를 이 값으로 다시 잇는다([SceneLayout._scopePadOf]).
  static const folderTab = 20.0, folderHead = 21.0, folderFoot = 7.0;

  /// 안쪽 그릇 = 상자(리메이크 2부 포개짐 · 목업 서고 box): 머리 20(뚜껑 18 + 2) · 발 7.
  static const boxHead = 20.0, boxLid = 18.0, boxFoot = 7.0;

  /// 문화권 머리 단(리메이크 조각 ② · 설계 4-6 #5 B · 목업 d5-b): 머리 단 20 · 펼친 문화권은 그 아래 4 뒤에 첫 트랙 · 문화권 사이 6.
  /// 접힌 문화권은 머리 단 한 줄(20)뿐이다.
  static const sphereHead = 20.0, sphereGap = 4.0, sphereBetween = 6.0;
  static const dynasty = floor, leader = floor, cabinet = floor, organ = floor, dep = floor;

  /// 예속 칸 한 단의 간격 — 흰 층이라 틈 없이 [floor]씩.
  static const depPitch = floor;
  static const zoneTab = 20.0, zoneGap = 3.0, gap = 8.0, memberGap = 6.0, groupGap = 14.0;

  /// 매달린 속국 이름표 한 줄(감독 결정 2026-10-14 '원래대로 두고 크기만 줄이자' — 23의 절반 남짓 · js/timeline.js의 HANG.pitch).
  /// 12로는 8px 글의 위아래 틈(감독 원칙 — 1배에서 1px 이상)이 첫 줄에서 나오지 않아 13이다. 구역 탭은 그대로 [zoneTab] + [zoneGap]이다.
  static const hang = 13.0;

  /// 실로 매단 작은 꼬리표(감독 결정 '두 장 ㄴ'의 속국 — 목업 서고의 접힌 그릇 꼬리표): 몸통 아랫변에서 [hangGap] 아래에 첫 꼬리표(높이 [hang]),
  /// 꼬리표 사이 [hangBetween] · 마지막 아래 [hangAfter]. 실은 아랫변에서 꼬리표 구멍까지.
  static const hangGap = 5.0, hangBetween = 4.0, hangAfter = 2.0;

  /// 매단 꼬리표 [n]줄이 몸통 아래에서 차지하는 높이(0줄이면 0).
  static double hangDepthOf(int n) => n <= 0 ? 0 : hangGap + n * hang + (n - 1) * hangBetween + hangAfter;
  static const folded = 34.0, foldedGroup = 30.0, hem = 21.0, tab = 18.0;
  static const figure = 20.0, figGap = 3.0, phase = floor, phaseGap = 0.0, rank = floor, rankGap = 0.0;

  /// 단체 단(집권 · 실권 — 감독 선택 D5 결정 1 A · 2 A): 지위 단 아래 · 지도자 칸 위의 줄 단위 덧단 한 줄씩(js/timeline.js의 G.power · G.powerGap).
  static const power = floor, powerGap = 0.0;

  /// 왼쪽 칸: 줄 이름 칸을 품은 기본 폭 196 = 트랙 칸 24 + 민족 칸 22 + 줄 이름 150. 민족 단계가 하나 늘 때마다 22.
  static const gutter = 240.0, trackColumn = 24.0, peopleColumn = 22.0;
}

/// 줄의 종류.
abstract final class RowKind {
  static const normal = 0, member = 1, common = 2, foldedGroup = 3;
}

/// 이번 다시 쌓기를 일으킨 것 — 그리는 쪽이 연출을 가른다(`layout.stackCause`).
/// 지금 연표에서 이 갈래마다 다른 움직임이 붙는다(움직임 원칙 ③ · ④ · 명세 05의 5 · 7.6절).
enum StackCause {
  /// 첫 쌓기(흐르지 않는다).
  none,

  /// 켠 자료집(DLC)이 바뀜 · 저장소를 다시 지어 뼈대가 바뀜 — 켠 트랙은 0에서 자라나고 끈 트랙은 0으로 접힌다
  /// (2단계의 '바로 뛰기'는 4단계 1걸음에서 걷어냈다 — 움직임 원칙의 '필터·DLC로 바뀐 것').
  packs,

  /// 보기 조건(밀도 · 조감 · 켠 단) — 줄 안의 것이 옛 줄에 **잔상**으로 남아 옅어진다(지금 연표의 `_squash` · `.was-bird`).
  conditions,

  /// 빈 줄 접기(`RowFolder`).
  rows,

  /// 접힌 트랙 · 접힌 민족 · 접힌 대범위 가지 · 끈 트랙.
  view,

  /// 소속 펼치기 · 대범위 모아 보기 — 띠가 옛 줄에서 새 줄로 **모여든다**(지금 연표의 `_gatherDraw`).
  variants,
}

/// 보기 조건: 어느 단을 켰는가와 밀도. 바뀌면 줄을 다시 쌓는다.
class ViewConditions {
  const ViewConditions({
    this.dynasties = true,
    this.leaders = true,
    this.cabinets = true,
    this.phases = true,
    this.ranks = true,
    this.figures = true,
    this.groups = true,
    this.density = 0,
    this.autoBird = false,
    this.birdShape = BirdShape.a,
  });
  final bool dynasties, leaders, cabinets, phases, ranks, figures;

  /// 표시 체크 '단체'(웹 `show.groups` — `HT.SHOW_DEFAULTS`처럼 기본 켬): 집권 단 · 실권 단과 명목 지도자 · 연합의 겹 탭.
  /// 필터 시트에는 아직 체크 상자가 없다(웹도 같음 — 설계 7-8 11-5). 끄면 덧단이 빠지고 줄이 예전 높이로 돌아간다.
  final bool groups;

  /// −1 넉넉하게 · 0 자동 · 1 빽빽하게 · 2 조감. 사람이 고른 값이라 자동 조감이 걸려도 그대로다.
  final int density;

  /// 자동 조감이 지금 걸려 있는가(명세 05 7.6 — 판정은 정착 때 한 번, [AutoBird]가 한다).
  final bool autoBird;

  /// 조감의 모양(a · b · c).
  final BirdShape birdShape;

  /// 지금 조감으로 그리는가 — 밀도 조감이거나 자동 조감이 걸렸을 때(지금 연표의 `isBird()`).
  bool get bird => density == 2 || autoBird;

  ViewConditions copyWith({bool? dynasties, bool? leaders, bool? cabinets, bool? phases, bool? ranks, bool? figures, bool? groups, int? density, bool? autoBird, BirdShape? birdShape}) => ViewConditions(
    dynasties: dynasties ?? this.dynasties, leaders: leaders ?? this.leaders, cabinets: cabinets ?? this.cabinets, phases: phases ?? this.phases,
    ranks: ranks ?? this.ranks, figures: figures ?? this.figures, groups: groups ?? this.groups, density: density ?? this.density,
    autoBird: autoBird ?? this.autoBird, birdShape: birdShape ?? this.birdShape,
  );

  @override
  bool operator ==(Object other) =>
      other is ViewConditions && other.dynasties == dynasties && other.leaders == leaders && other.cabinets == cabinets && other.phases == phases && other.ranks == ranks && other.figures == figures && other.groups == groups && other.density == density && other.autoBird == autoBird && other.birdShape == birdShape;
  @override
  int get hashCode => Object.hash(dynasties, leaders, cabinets, phases, ranks, figures, groups, density, autoBird, birdShape);
}

/// 줄 하나의 생김새(100% 배율 px). 자리는 줄의 몫(slot) 안 상대값이고 없는 단은 -1.
/// 줄의 몫 = 줄 위의 틈(책갈피 탭 자리) + 띠 + 띠 아래 덧붙는 단(구역 탭 · 속국 이름표 · 바탕 문화 이름).
class RowGeo {
  const RowGeo({
    required this.height,
    required this.bandTop,
    required this.bandHeight,
    required this.dynastyTop,
    required this.leaderTop,
    required this.cabinetTop,
    required this.textTop,
    required this.textLines,
    required this.railTop,
    required this.organTop,
    this.phaseTop = -1,
    this.phaseLanes = 0,
    this.rankTop = -1,
    this.powerTop = -1,
    this.realTop = -1,
    this.railLevels = 2,
    this.figTop = -1,
    this.figLevels = 0,
    this.depTop = -1,
    this.depHeight = 0,
    this.zoneTop = -1,
    this.zoneLanes = 0,
    this.hangLanes = 0,
    this.hangOpen = true,
    this.hemTop = -1,
    this.lineH = G.line,
    this.bodyTop = -1,
    this.floorEnd = -1,
  });

  /// 두 장 꼬리표(감독 결정 '두 장 ㄴ'): 몸통 띠의 윗변(= 이름 색줄의 아랫변)과 칸 뭉치의 아랫변(= 흰 사건 칸의 윗변) — 줄의 몫 안 y.
  /// 칸 단이 없으면 둘이 같다. 조감 · 접힌 줄은 −1(몸통 없음).
  final double bodyTop, floorEnd;
  final double height, bandTop, bandHeight, dynastyTop, leaderTop, cabinetTop, textTop, railTop, organTop;
  final int textLines;

  /// 글줄 하나의 높이 — 두 장 꼬리표의 흰 사건 칸 18(`G.evLine`) · 옛 2판 저장소는 21(`G.line`) · 조감에서는 띠 전체(14 · 8)다(글줄이 하나뿐이라 띠의 세로 가운데).
  final double lineH;

  /// 시기 구분 단(체계마다 13 + 2) · 지위 단(13) · 인물 단(단마다 15 · 사이 2) · 예속 칸 · 띠 아래의 탭 줄(줄마다 12 + 2) · 바탕 문화의 이름 단(12).
  final double phaseTop, rankTop, figTop, depTop, depHeight, zoneTop, hemTop;
  final int phaseLanes, railLevels, figLevels, zoneLanes;

  /// 단체 단의 두 줄(각 13 — 위 = 집권 · 아래 = 실권, 실권이 지도자 칸과 맞닿는다). 그 줄에 없으면 −1.
  /// 칸 종류 8(공용 칸 단)의 단 2 · 3이 여기에 놓인다(내보내기 `export/power.mjs`).
  final double powerTop, realTop;

  /// 띠 안의 단 높이와 글줄 높이 — 지금 연표의 값(왕조 15 · 지도자 20 · 내각 17 · 기관 15 · 글줄 21).
  static const dynastyHeight = G.dynasty, leaderHeight = G.leader, cabinetHeight = G.cabinet, organHeight = G.organ, lineHeight = G.line;

  /// 꼬리표 안 흰 층의 윗변들(줄의 몫 안 y — 위에서부터, 갈래 E): 왕조 · 시기(단마다) · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속(단마다) · 기관.
  /// [_bandOf]가 [G.floor]씩 맞붙여 쌓은 자리 그대로다. 칸 단이 없는 줄은 빈 목록(첫 값이 흰 층의 위 — 그 아래 띠 아랫변까지가 흰 층).
  List<double> get floorTops {
    final out = <double>[];
    if (dynastyTop >= 0) out.add(dynastyTop);
    if (phaseTop >= 0) {
      for (int k = 0; k < phaseLanes; k++) {
        out.add(phaseTop + k * G.floor);
      }
    }
    for (final y in [rankTop, powerTop, realTop, leaderTop, cabinetTop]) {
      if (y >= 0) out.add(y);
    }
    if (depTop >= 0) {
      for (int k = 0; k < (depHeight / G.depPitch).round(); k++) {
        out.add(depTop + k * G.depPitch);
      }
    }
    if (organTop >= 0) out.add(organTop);
    return out;
  }

  /// 단의 종류(계약의 번호: 0 왕조 · 1 지도자 · 2 내각 · 3 기관 · 4 시기 · 5 지위 · 6 인물 · 7 예속 안) · 단 번호 → 그 단의 위 자리와 높이. 없으면 (-1, 0).
  (double, double) strip(int kind, [int lane = 0]) => switch (kind) {
    0 => (dynastyTop, G.dynasty),
    1 => (leaderTop, G.leader),
    2 => (cabinetTop, G.cabinet),
    3 => (organTop, G.organ),
    4 => phaseTop < 0 || lane >= phaseLanes ? (-1.0, 0.0) : (phaseTop + lane * (G.phase + G.phaseGap), G.phase),
    5 => (rankTop, G.rank),
    6 => figTop < 0 || lane >= figLevels ? (-1.0, 0.0) : (figTop + lane * (G.figure + G.figGap), G.figure),
    7 => depTop < 0 ? (-1.0, 0.0) : (depTop + lane * G.depPitch, G.dep),
    // 공용 칸 단(종류 8): 단 2 = 집권 단 · 3 = 실권 단. 단 0 · 1(렌즈 — 지도자 · 지위 자리)은 그리는 쪽(paint/strips.dart)이 고른다.
    8 => lane == 2 ? (powerTop < 0 ? (-1.0, 0.0) : (powerTop, G.power)) : (lane == 3 ? (realTop < 0 ? (-1.0, 0.0) : (realTop, G.power)) : (-1.0, 0.0)),
    _ => (-1.0, 0.0),
  };

  /// [zoneLanes] 가운데 앞의 [hangLanes]줄이 매달린 속국 이름표(한 줄 [G.hang])이고 나머지가 구역 탭(한 줄 23)이다.
  /// 0이면 저장소가 그 수를 싣지 않은 옛 저장소 — 모든 줄을 23으로 쌓던 예전 그대로다.
  /// [hangOpen]이 거짓이면 상국 띠의 '속국' 단추로 접은 줄이라 매달린 줄의 자리가 없다(구역 탭이 띠 밑으로 올라온다).
  final int hangLanes;
  final bool hangOpen;

  /// 매달린 이름표 한 줄의 높이(옛 저장소는 23).
  double get hangHeight => hangLanes > 0 ? G.hang : G.zoneTab + G.zoneGap;

  /// 띠 아래 덧붙는 줄(실로 매단 속국 꼬리표 → 구역 탭)의 위 자리. 매단 꼬리표는 몸통 아랫변 [G.hangGap] 아래부터 [G.hang] + [G.hangBetween]씩,
  /// 구역 탭은 그 뒤에 바로. 접은 매달린 줄은 −1.
  double zoneLaneTop(int lane) {
    if (zoneTop < 0) return -1;
    if (lane < hangLanes) return hangOpen ? zoneTop + G.hangGap + lane * (G.hang + G.hangBetween) : -1;
    return zoneTop + hangDepth + (lane - hangLanes) * (G.zoneTab + G.zoneGap);
  }

  /// 매단 꼬리표 줄이 띠 아래에서 차지하는 높이(접었으면 0) — 소속선이 그 아래에서 내려온다.
  double get hangDepth => !hangOpen ? 0 : G.hangDepthOf(hangLanes);

  /// 줄의 몫만 [height]로 바꾼 같은 생김새 — 접히고 펴지는 동안 쓴다(안의 단은 제자리에 있고 밖은 잘린다).
  RowGeo withHeight(double height) => RowGeo(
    height: height, bandTop: bandTop, bandHeight: bandHeight, dynastyTop: dynastyTop, leaderTop: leaderTop, cabinetTop: cabinetTop,
    textTop: textTop, textLines: textLines, railTop: railTop, organTop: organTop, phaseTop: phaseTop, phaseLanes: phaseLanes,
    rankTop: rankTop, powerTop: powerTop, realTop: realTop, railLevels: railLevels, figTop: figTop, figLevels: figLevels, depTop: depTop, depHeight: depHeight,
    zoneTop: zoneTop, zoneLanes: zoneLanes, hangLanes: hangLanes, hangOpen: hangOpen, hemTop: hemTop, lineH: lineH, bodyTop: bodyTop, floorEnd: floorEnd,
  );
}

/// 줄 깃발(한 벌 P3-18): `fig_wide` 한 정수에 든 줄 단위 트랙 값(계약 3-3 · 6-5)을 **엔진의 layout 답이 이름 붙은 칸으로 풀어** 준다 —
/// 앱은 [fromAnswer]로 읽기만 한다. [legacy]는 그 칸이 없는 답(손으로 쓴 검사 답 · 옛 엔진)을 위해 남긴 옛 셈 한 곳이다 — 엔진의
/// `layout.rs` `add_row_flags`와 같은 규칙(옛 저장소 — 비트 3 ~ 5가 0 — 의 예외까지)이고, `layout_static_test`가 둘이 같음을 굳힌다.
class RowFlags {
  const RowFlags({required this.figWide, required this.rail, required this.organ, required this.power, required this.real, required this.hang, required this.raised, required this.contained, required this.cellRows, required this.dynasty, required this.leader, required this.cabinet, required this.events});
  final int figWide, rail, hang;
  final bool organ, power, real, raised, contained, cellRows, dynasty, leader, cabinet, events;

  /// 답에 칸이 있는가(`rail`이 있으면 모두 있다).
  static bool carried(Map<String, dynamic> r) => r.containsKey('rail');

  /// 엔진 답의 칸 그대로.
  factory RowFlags.fromAnswer(Map<String, dynamic> r) {
    bool on(String key) => (r[key] ?? 0) != 0;
    return RowFlags(
      figWide: (r['fig_wide_levels'] ?? 0) as int, rail: (r['rail'] ?? -1) as int, organ: on('organ'), power: on('power'), real: on('real'),
      hang: (r['hang'] ?? 0) as int, raised: on('raised'), contained: on('contained'), cellRows: on('cell_rows'),
      dynasty: on('dynasty'), leader: on('leader'), cabinet: on('cabinet'), events: (r['events'] ?? 1) != 0,
    );
  }

  /// 옛 셈 — `fig_wide` 한 정수가 '넉넉하게의 인물 단 수'와 **줄 단위 트랙 값**을 함께 나른다(계약 6-5절):
  /// 비트 0~2 인물 단 수 · 비트 3~5 그 줄의 기간 막대 단 수 + 1(0이면 실리지 않은 옛 저장소) · 비트 6 그 줄의 기관 칸 ·
  /// 비트 7 · 8 그 줄의 집권 단 · 실권 단(감독 선택 D5 — 비트 3~5가 0인 옛 저장소에서는 읽지 않는다) ·
  /// 비트 9~13 그 줄의 매달린 속국 이름표 줄 수(건의 8 · 2026-10-14 — 없거나 옛 저장소면 0) ·
  /// 비트 14 그 줄에 위로 솟는 것(받침 카드 · 상국 탭 · 연합 탭 — 꼬리표 갈래 E · 2026-10-15)이 있는가 · 비트 15 그릇의 줄 ·
  /// 비트 16 ~ 18 왕조 · 지도자 · 내각 칸 · 비트 19 그 셋을 실었다는 표시 · 비트 20 사건이 있는가.
  factory RowFlags.legacy(int packed, int zones) {
    final railBits = (packed >> 3) & 7;
    final carried = railBits != 0;
    final cellRows = carried && (packed & (1 << 19)) != 0;
    return RowFlags(
      figWide: carried ? packed & 7 : packed, rail: carried ? railBits - 1 : -1,
      organ: carried && (packed & 64) != 0, power: carried && (packed & 128) != 0, real: carried && (packed & 256) != 0,
      hang: carried ? ((packed >> 9) & 31).clamp(0, zones) : 0,
      raised: carried && (packed & 16384) != 0, contained: carried && (packed & 32768) != 0, cellRows: cellRows,
      dynasty: (packed & (1 << 16)) != 0, leader: (packed & (1 << 17)) != 0, cabinet: (packed & (1 << 18)) != 0,
      events: !cellRows || (packed & (1 << 20)) != 0,
    );
  }
}

/// 그릇(대범위) 여백의 가름(한 벌 P3-18): 저장소의 `scope_pad`는 '조감이 아닌' px 하나(머리 16 · 발 6 · 본국 줄에 매달린 머리 −4의 합)라,
/// 엔진의 layout 답이 **머리 수 · 발(0/1) · 매달린 머리 수**로 갈라 준다(`scope_head` · `scope_foot` · `scope_hung` — 갈라지지 않는 값은 −1 셋).
/// px로 되돌리는 쪽(폴더 · 조감 · 상자의 자)은 보기 상태에 달려 앱([SceneLayout._scopePadOf])에 남는다. [legacy]는 칸이 없는 답을 위한 옛 셈 한 곳.
class ScopeSplit {
  const ScopeSplit(this.head, this.foot, this.hung);
  final int head, foot, hung;

  /// 답에 칸이 있는가.
  static bool carried(Map<String, dynamic> r) => r.containsKey('scope_head');

  /// 엔진 답의 칸 — 갈라지지 않는 값(−1 셋)이면 null.
  static ScopeSplit? fromAnswer(Map<String, dynamic> r) {
    final head = (r['scope_head'] ?? -1) as int, foot = (r['scope_foot'] ?? -1) as int, hung = (r['scope_hung'] ?? -1) as int;
    return head < 0 ? null : ScopeSplit(head, foot, hung);
  }

  /// 옛 셈 — 발 6을 먼저 떼어 보고(한 줄에 발은 많아야 하나) 머리 16의 배수 · 매달린 머리 −4(`16 + 2 − 8 − 14`)로 가른다. 안 갈라지면 null.
  static ScopeSplit? legacy(double stored) {
    if (stored == 0) return const ScopeSplit(0, 0, 0);
    final head = ViewMetrics.normal.scopeHead, foot = ViewMetrics.normal.scopeFoot;
    final hung = head + 2 - G.gap - G.groupGap; // −4
    for (int f = 1; f >= 0; f--) {
      final rest = stored - f * foot;
      if (rest == hung) return ScopeSplit(0, f, 1);
      if (rest >= 0 && rest % head == 0) return ScopeSplit(rest ~/ head, f, 0);
    }
    return null;
  }
}

/// 줄의 자료(넣을 때 정해진 것).
class RowSpec {
  const RowSpec({this.kind = 0, this.groupStart = false, this.scopePad = 0, this.scopeSplit, this.phase = 0, this.rank = false, this.cats = const [], this.fig = 0, this.figWide = 0, this.dep = 0, this.zones = 0, this.hang = 0, this.hem = false, this.variant = 0, this.rail = -1, this.organ = false, this.power = false, this.real = false, this.raised = false, this.contained = false, this.cellRows = false, this.dynasty = false, this.leader = false, this.cabinet = false, this.events = true});

  /// 줄 깃발을 [RowFlags]에서 — 엔진 답의 칸([RowFlags.fromAnswer]) 또는 옛 셈([RowFlags.legacy]).
  RowSpec.withFlags(RowFlags f, {this.kind = 0, this.groupStart = false, this.scopePad = 0, this.scopeSplit, this.phase = 0, this.rank = false, this.cats = const [], this.fig = 0, this.dep = 0, this.zones = 0, this.hem = false, this.variant = 0})
      : figWide = f.figWide, rail = f.rail, hang = f.hang, organ = f.organ, power = f.power, real = f.real, raised = f.raised, contained = f.contained,
        cellRows = f.cellRows, dynasty = f.dynasty, leader = f.leader, cabinet = f.cabinet, events = f.events;
  final int kind, phase, fig, figWide, zones;

  /// 그릇 여백 [scopePad]의 가름(머리 수 · 발 · 매달린 머리 — 한 벌 P3-18). null이면 갈라지지 않는 값이라 px를 그대로 쓴다.
  final ScopeSplit? scopeSplit;

  /// 그 줄에 사건이 있는가(`fig_wide` 비트 20). 비트 19가 없는 옛 저장소 · 변형이 새로 만든 줄은 참. 감독 결정(사건 칸은 늘 둠)으로 줄 쌓기는 쓰지 않는다.
  final bool events;

  /// [zones] 가운데 매달린 속국 이름표 줄의 수(`fig_wide`의 비트 9~13 — 내보내기 `export/tracks.mjs`의 packRowValues).
  /// 옛 저장소는 0이라 모든 줄을 구역 탭 높이(23)로 쌓는다.
  final int hang;
  final bool groupStart, rank, hem;
  final double scopePad, dep;

  /// dep의 저장 단위는 옛 높이(n*13-1)로 유지한다. 새 기하와 옛 저장소 모두 같은 줄 수를 쓴다.
  double get depHeight => dep <= 0 ? 0 : ((dep + 1) / 13).round() * G.depPitch;
  final List<int> cats;

  /// 그 줄을 만드는 변형의 번호(0이면 늘 있는 줄). 켜지 않은 변형의 줄은 높이 0 · `isVisible` 거짓이다.
  final int variant;

  /// **줄 단위 트랙 값**(계약 3절 끝): 그 줄만의 기간 막대 단 수(0~3 · −1이면 저장소에 실리지 않음)와 그 줄에 기관 칸이 있는가.
  /// 기간 막대 단 수 · 기관 칸은 띠 안에서는 트랙 하나의 값이지만, 지금 연표는 **보이는 줄들**로 다시 셈한다 —
  /// 민족을 접으면 그 줄들의 정권 · 사건이 빠져 띠가 낮아지고, 소속을 펼치면 사건이 새 줄로 옮겨 간다.
  final int rail;
  final bool organ;

  /// 그 줄에 집권 단 · 실권 단이 있는가(`fig_wide`의 비트 7 · 8 — 내보내기 `export/tracks.mjs`의 packRowValues).
  /// 단체 자료가 없는 줄 · 옛 저장소는 거짓이라 줄 높이가 예전과 1px도 같다.
  final bool power, real;

  /// 그 줄에 **위로 솟는 것**(섬기는 띠의 받침 카드 + 상국 탭 · 연합의 겹 탭 — 구역 47)이 있는가(`fig_wide`의 비트 14 —
  /// 내보내기 `export/tracks.mjs`의 contributeLate). 꼬리표 갈래 E는 띠 위 탭 줄이 없어, 이런 줄만 위 틈을 [G.raise]만큼 더 둔다.
  final bool raised;

  /// 그 줄이 **그릇의 줄**인가(`fig_wide`의 비트 15 — 풀린 그릇의 열쇠표(구역 50)를 실은 줄 · 내보내기 `export/tracks.mjs`의 contributeLate).
  /// 위 틈을 [G.contain]만큼 더 둔다(리메이크 조각 ③). 옛 저장소 · 그릇 없는 자료는 거짓이라 예전과 1px도 같다.
  final bool contained;

  /// 줄 값으로 흰 층을 두는가(`fig_wide`의 비트 19 — 리메이크 2부 · 목업 서고 "칸은 그 줄에 있을 때만")와 그 줄에 왕조 · 지도자 · 내각 칸이 있는가(비트 16 · 17 · 18).
  /// 거짓이면(옛 저장소 · 변형이 새로 만든 줄) 트랙 값([TrackInfo.dynasty] · [TrackInfo.leader] · [TrackInfo.cabinet])을 쓴다.
  final bool cellRows, dynasty, leader, cabinet;
}

/// 켠 그릇 하나(리메이크 2부 포개짐): uid · 트랙(목록 자리) · 묶음 줄 집합 · 묶음 열쇠(접힘) · 깊이.
class ScopeOn {
  ScopeOn(this.uid, this.track, this.rows, this.keys, {this.within});
  final String uid;
  final int track;
  final Set<int> rows;
  final List<String> keys;

  /// 같은 트랙에서 이 그릇의 줄을 모두 품고 더 큰 그릇 변형의 번호(엔진 답 `within` — 한 벌 P3-18 · 정적). null이면 답에 없어 옛 셈으로 깊이를 센다.
  final List<int>? within;
  int depth = 0;
}

/// 변형 하나에서 줄을 쌓는 차례(계약 3-2절). [after]가 −1이면 트랙의 맨 위다.
/// [after]가 **−2**면 그 변형에서 **빠지는 줄**이다 — 집합 보기(kind 3)가 판 트랙으로 통째로 옮긴 원래 트랙의 줄이라 쌓지 않는다.
/// 그때 [ord]는 그 줄이 옮겨 간 판 줄의 번호(없으면 −1 — 내보내기 `export/boards.mjs` · 가져오기 `legacy.rs`).
class VariantRow {
  const VariantRow(this.row, this.after, this.ord, this.isNew, this.scopePad, this.groupStart, {this.scopeSplit});
  final int row, after, ord;
  final bool isNew, groupStart;
  final double scopePad;

  /// 덮어쓰는 그릇 여백 [scopePad]의 가름(한 벌 P3-18 — 줄 답과 같은 칸). null이면 px 그대로.
  final ScopeSplit? scopeSplit;

  /// 그 변형에서 빠지는 줄인가(after −2).
  bool get gone => after == -2;
}

/// 그 변형에서 생기는 왼쪽 칸의 묶음(대범위 칸) — 드는 줄을 그대로 들고 있다.
class VariantGroup {
  const VariantGroup(this.key, this.depth, this.name, this.color, this.kind, this.rows);
  final int depth, color, kind;
  final String key, name;
  final List<int> rows;
}

/// 켤 수 있는 것 하나 — 소속 펼치기(`host:…` · [band]가 그 상위 띠) 또는 대범위 모아 보기(`scope:…` · [uid]가 그 대범위).
class VariantInfo {
  const VariantInfo(this.id, this.key, this.kind, this.track, this.band, this.uid, this.name, this.rows, this.groups, {this.within});
  final int id, kind, track, band;
  final String key, uid, name;
  final List<VariantRow> rows;
  final List<VariantGroup> groups;

  /// 그릇 변형만: 같은 트랙에서 이 그릇의 묶음 줄을 모두 품고 더 큰 그릇 변형의 번호(엔진 답 `within` — 한 벌 P3-18). 답에 없으면 null.
  final List<int>? within;

  /// 1 소속 펼치기 · 2 대범위 모아 보기 · 3 집합 보기(`view:<id>` — [track]은 판 트랙 · 판마다 하나 · 맨 위에 쌓인다).
  static const kindHost = 1, kindScope = 2, kindView = 3;

  /// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A): `theme:<주제 id>` · [uid]가 그 주제. 줄을 옮겨 쌓지 않고 칸(종류 8)과 가림만 싣는다
  /// (내보내기 `prototype/scripts/export/lens.mjs`). 켜고 끄는 것은 보기 상태가 아니라 [SceneLayout.setThemeLens]다.
  static const kindTheme = 4;

  /// 단체 펼치기(리메이크 조각 ④ · `groups:<나라 uid>` · [band]가 그 나라 띠): 그 나라에 접혀 든 단체의 띠를 나라 밑 제 줄에 — 소속 펼치기와 같은 길.
  static const kindGroups = 5;
}

/// 그릇(대범위)의 세 상태(리메이크 조각 ③ · 설계 4-6 #2 B — 감독 2026-10-15 "추천대로"):
/// 펼침 = 켜서 가지에 모으고 폴더로 · 접힘 = 켠 채 가지를 한 줄로 접어 닫힌 폴더로 · 풀림 = 꺼서 구성원이 제 줄로(그릇 이름은 열쇠표로 남는다).
/// 보기 상태에 따로 적지 않는다 — 켠 대범위(`openScopes`)와 가지의 접힘(`foldedGroups`의 `<트랙 id>|__scope:<uid>`)에서 읽는다.
enum ScopeState { open, closed, loose }

class GroupInfo {
  const GroupInfo(this.depth, this.firstRow, this.rowCount, this.name, this.color, this.kind);
  final int depth, firstRow, rowCount, color, kind;
  final String name;
}

class TrackInfo {
  const TrackInfo(this.id, this.pack, this.name, this.firstRow, this.rowCount, {this.color = 0xc27a45, this.dynasty = false, this.leader = false, this.cabinet = false, this.organ = false, this.railLevels = 2, this.groups = const [], this.key = '', this.sphere = '', this.sphereAt});
  final int id, pack, firstRow, rowCount, color, railLevels;

  /// 문화권 목록([SceneLayout.spheres])에서의 자리(엔진 답 `sphere_at` — 한 벌 P3-18 · 문화권 밖이면 −1). 답에 없으면 null(옛 셈으로 찾는다).
  final int? sphereAt;
  final String name;
  final bool dynasty, leader, cabinet, organ;
  final List<GroupInfo> groups;

  /// 트랙의 글자 id(`korea` — `tracks.key`). 저장소를 다시 지어도 같아, 옛 뼈대와 새 뼈대의 트랙을 짝짓는 열쇠다. 옛 저장소는 빈 글.
  final String key;

  /// 트랙이 드는 문화권 id(리메이크 조각 ② — `east-asia` …). 판 트랙 · 옛 저장소는 빈 글(문화권 밖).
  final String sphere;
}

/// 문화권 하나(리메이크 조각 ② — 저장소 meta `spheres` → layout 답 맨 위 `spheres`). 차례는 목록의 차례.
class SphereInfo {
  const SphereInfo(this.id, this.name, {this.count = 0, this.isDefault = false});
  final String id, name;

  /// 그 문화권 트랙에 실린 띠의 수(머리 단의 수) · 처음 펼칠 문화권인가(자료의 default — 설계 4-6 #1 A).
  final int count;
  final bool isDefault;
}

/// 문화권 단위 줄 하나(스키마 4 — 계약 1-1의 표 `sphere_lines` → layout 답 맨 위 `sphereLines`). 차례는 답의 차례(= 표의 id 차례).
/// 3단계는 **받기만** 한다 — 줄 쌓기 · 그리기 어디에서도 읽지 않는다(그림은 4단계 · 계획 정한 것 #14).
class SphereLine {
  SphereLine(this.kind, this.sphere, this.start, this.end, this.name, {this.uid = '', this.color = 0, this.data = '', this.pack = 0});

  /// 답의 원소 하나를 너그럽게 읽는다: 빠진 열쇠는 0 · 빈 글, 수는 정수로, data가 글이 아니면(객체 · 목록) JSON 글로 바꿔 담는다.
  /// 모르는 kind도 버리지 않고 그대로 담는다(무엇을 그릴지는 4단계가 정함).
  factory SphereLine.fromJson(Map json) {
    int number(String key) => switch (json[key]) { final num v => v.toInt(), _ => 0 };
    String text(String key) => switch (json[key]) { null => '', final String v => v, final v => '$v' };
    return SphereLine(
      number('kind'), text('sphere'), number('start'), number('end'), text('name'),
      uid: text('uid'), color: number('color'), pack: number('pack'),
      data: switch (json['data']) { null => '', final String v => v, final v => jsonEncode(v) },
    );
  }

  /// 줄의 갈래 — 1 사람 띠 · 2 문화권 시대 구분 · 3 문화권 주기 줄(계약 1-1).
  static const person = 1, epoch = 2, cycle = 3;

  /// 갈래([person] · [epoch] · [cycle] · 그 밖은 모르는 갈래) · 시작 · 끝(분 — 주기 줄은 둘 다 0) · 색(문화권 시대) · 자료집 순번.
  final int kind, start, end, color, pack;

  /// 문화권의 글자 id(`tracks.sphere`와 같은 글) · 이름 · 대상의 uid(사람 띠 = 인물 · 문화권 시대 = 시대 구분).
  final String sphere, name, uid;

  /// 갈래마다 다른 덧붙은 값의 JSON 글 — 사람 띠는 왕관 목록 `[{"uid", "cell"}]`, 주기 줄은 `{"names", "start", "label"}` 같은 것. 없으면 빈 글.
  final String data;

  /// [data]를 푼 값(처음 읽을 때 한 번) — 빈 글이나 깨진 글이면 null.
  late final Object? decoded = _decode(data);

  /// 사람 띠([person])의 왕관 — data의 `[{uid: 띠 uid, cell: 칸 순번}]`을 (uid, cell)로. 다른 갈래거나 data의 꼴이 다르면 빈 목록.
  late final List<({String uid, int cell})> crowns = _crowns();

  static Object? _decode(String text) {
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  List<({String uid, int cell})> _crowns() {
    final list = decoded;
    if (kind != person || list is! List) return const [];
    return List.unmodifiable([
      for (final c in list)
        if (c is Map) (uid: switch (c['uid']) { final String v => v, _ => '' }, cell: switch (c['cell']) { final num v => v.toInt(), _ => 0 }),
    ]);
  }
}

class PackInfo {
  const PackInfo(this.id, this.name, this.events, {this.key = '', this.periods = 0, this.touches = const []});
  final int id, events;
  final String name;

  /// DLC의 글자 id(`east-asia-base` · 메이커가 준 id — `layout.packs[].key`). 다시 지은 저장소에서 같은 DLC를 알아보는 열쇠다. 옛 저장소는 빈 글.
  final String key;

  /// 이 DLC의 띠(나라 · 시대) 수와, 그 띠 · 사건이 놓인 트랙 번호들(제 트랙이 아닌 남의 트랙에 얹은 것까지 — `layout.packs[].periods` · `touches`).
  /// 옛 저장소에는 없어 0 · 빈 목록이다.
  final int periods;
  final List<int> touches;
}

class EpochInfo {
  const EpochInfo(this.start, this.end, this.color, this.name);
  final int start, end, color;
  final String name;
}

class CategoryInfo {
  const CategoryInfo(this.id, this.key, this.name, this.color);
  final int id, color;
  final String key, name;
}

/// 날짜 칸의 칸 하나(시대 구분 · 연호 · 도읍 · 배도). track = 트랙의 id(공통 줄이면 0).
class AxisCell {
  const AxisCell(this.kind, this.track, this.lane, this.start, this.end, this.name, this.color, this.style, this.strip, this.seq);
  final int kind, track, lane, start, end, color, style, strip, seq;
  final String name;
}

/// 뼈대를 바꾸기 직전의 **지금 보이는** 자리 — [SceneLayout.snapshot]이 적고 [SceneLayout.replaceWith]의 다리가 읽는다.
class LayoutSnapshot {
  const LayoutSnapshot._(this.identity, this.trackTop, this.trackHeight, this.firstRow, this.rowCount, this.rowTop, this.rowHeight, this.live, this.geos, this.total);

  /// 트랙마다 짝짓기 열쇠([SceneLayout.trackIdentity]) · 위 자리(끈 트랙은 −1) · 높이 · 첫 줄 · 줄 수.
  final List<String> identity;
  final List<double> trackTop, trackHeight;
  final List<int> firstRow, rowCount;

  /// 줄마다 위 자리(안 보이면 −1) · 높이(안 보이면 0) · 보이는가 · 생김새.
  final List<double> rowTop, rowHeight;
  final List<bool> live;
  final List<RowGeo> geos;
  final double total;
}

class SceneLayout {
  SceneLayout._(this.packs, this.tracks, this.epochs, this.categories, this.axis, this._fixed, this._specs, this._rowTrack, this.variants,
      [List<SphereInfo>? spheres, List<SphereLine>? sphereLines])
      : spheres = spheres ?? <SphereInfo>[],
        sphereLines = sphereLines ?? <SphereLine>[] {
    _recountSpheres();
    // 처음 접힘(설계 4-6 #1 A): 자료의 default 문화권 하나만 펴고 나머지는 접는다 — 기억이 있으면 앱이 그 값으로 바꾼다(archive_app `_restoreViewState`).
    _view = withDefaultSpheres(ViewState.none);
    _enabled = {for (final p in packs) p.id};
    _syncView();
    _stack();
  }

  factory SceneLayout.fromJson(Map<String, dynamic> json) {
    final packs = [
      for (final p in json['packs'] as List)
        PackInfo(
          p['id'] as int, p['name'] as String, (p['events'] as num).toInt(),
          key: '${p['key'] ?? ''}', periods: ((p['periods'] ?? 0) as num).toInt(), touches: [for (final t in (p['touches'] as List? ?? const [])) (t as num).toInt()],
        ),
    ];
    final tracks = <TrackInfo>[];
    final fixed = <RowGeo>[];
    final specs = <RowSpec?>[];
    final rowTrack = <int>[];
    final ordered = (json['tracks'] as List).toList()
      ..sort((a, b) => (a['ord'] as int).compareTo(b['ord'] as int));
    for (final t in ordered) {
      final rows = t['rows'] as List;
      final first = fixed.length;
      for (final r in rows) {
        if (r['id'] != fixed.length) {
          throw const FormatException('줄 번호는 트랙 순서대로 0부터 빈틈없이 이어져야 합니다');
        }
        double at(String key) => (r[key] as num).toDouble();
        fixed.add(
          RowGeo(
            height: at('height'), bandTop: at('band_top'), bandHeight: at('band_h'), dynastyTop: at('dyn_top'), leaderTop: at('lead_top'),
            cabinetTop: at('cab_top'), textTop: at('text_top'), textLines: r['text_lines'] as int, railTop: at('rail_top'), organTop: at('organ_top'),
          ),
        );
        // 줄 깃발(`fig_wide`의 비트)과 그릇 여백의 가름은 엔진 답의 칸을 읽는다(한 벌 P3-18) — 칸이 없는 답(손으로 쓴 검사 답 · 옛 엔진)만 옛 셈.
        final zones = (r['zones'] ?? 0) as int, scopePad = ((r['scope_pad'] ?? 0) as num).toDouble();
        final flags = RowFlags.carried(r) ? RowFlags.fromAnswer(r) : RowFlags.legacy((r['fig_wide'] ?? r['fig'] ?? 0) as int, zones);
        final split = ScopeSplit.carried(r) ? ScopeSplit.fromAnswer(r) : ScopeSplit.legacy(scopePad);
        specs.add(
          r['kind'] == null
              ? null
              : RowSpec.withFlags(
                  flags,
                  kind: r['kind'] as int, groupStart: (r['group_start'] ?? 0) != 0, scopePad: scopePad, scopeSplit: split, phase: (r['phase'] ?? 0) as int,
                  rank: (r['rank'] ?? 0) != 0, cats: [for (final c in (r['cats'] as List? ?? const [])) c as int], fig: (r['fig'] ?? 0) as int,
                  dep: ((r['dep'] ?? 0) as num).toDouble(), zones: zones, hem: (r['hem'] ?? 0) != 0, variant: (r['variant'] ?? 0) as int,
                ),
        );
        rowTrack.add(tracks.length);
      }
      tracks.add(
        TrackInfo(
          t['id'] as int, t['pack'] as int, t['name'] as String, first, rows.length,
          color: (t['color'] ?? 0xc27a45) as int, dynasty: (t['dynasty'] ?? 0) != 0, leader: (t['leader'] ?? 0) != 0, cabinet: (t['cabinet'] ?? 0) != 0,
          organ: (t['organ'] ?? 0) != 0, railLevels: (t['rail_levels'] ?? 2) as int, key: '${t['key'] ?? ''}', sphere: '${t['sphere'] ?? ''}',
          sphereAt: t['sphere_at'] as int?,
          groups: [
            for (final g in (t['groups'] as List? ?? const []))
              GroupInfo(g['depth'] as int, g['first'] as int, g['count'] as int, g['name'] as String, g['color'] as int, (g['kind'] ?? 0) as int),
          ],
        ),
      );
    }
    final epochs = [
      for (final e in (json['epochs'] as List? ?? const []))
        EpochInfo(e['start'] as int, e['end'] as int, e['color'] as int, e['name'] as String),
    ];
    // 분류 번호는 **목록에서의 자리**(0부터)다 — 사건의 look · rows.cats · legend_kinds · 거르개의 cats_off가 모두 그 눈금이다(계약 4절).
    // 답의 `id`는 저장소의 표 번호(1부터)라 쓰지 않는다: 그것을 칩의 값으로 쓰면 '정치'를 껐는데 '전쟁'이 사라진다.
    final categoryJson = json['categories'] as List? ?? const [];
    final categories = [
      for (int i = 0; i < categoryJson.length; i++)
        CategoryInfo(i, categoryJson[i]['key'] as String, categoryJson[i]['name'] as String, categoryJson[i]['color'] as int),
    ];
    final axis = [
      for (final a in (json['axis'] as List? ?? const []))
        AxisCell(a[0] as int, a[1] as int, a[2] as int, a[3] as int, a[4] as int, a[5] as String, a[6] as int, a[7] as int, a[8] as int, a[9] as int),
    ];
    final variants = [
      for (final v in (json['variants'] as List? ?? const []))
        VariantInfo(
          (v['id'] ?? 0) as int, v['key'] as String, (v['kind'] ?? 0) as int, (v['track'] ?? 0) as int, (v['band'] ?? 0) as int,
          (v['uid'] ?? '') as String, (v['name'] ?? '') as String,
          [
            for (final r in (v['rows'] as List? ?? const []))
              VariantRow((r['row'] ?? 0) as int, (r['after'] ?? -1) as int, (r['ord'] ?? 0) as int, (r['new'] ?? 0) != 0,
                  ((r['scope_pad'] ?? 0) as num).toDouble(), (r['group_start'] ?? 0) != 0,
                  scopeSplit: ScopeSplit.carried(r) ? ScopeSplit.fromAnswer(r) : ScopeSplit.legacy(((r['scope_pad'] ?? 0) as num).toDouble())),
          ],
          [
            for (final g in (v['groups'] as List? ?? const []))
              VariantGroup(g['key'] as String, (g['depth'] ?? 0) as int, (g['name'] ?? '') as String, (g['color'] ?? 0) as int,
                  (g['kind'] ?? 2) as int, [for (final row in (g['rows'] as List? ?? const [])) row as int]),
          ],
          within: v['within'] == null ? null : [for (final id in v['within'] as List) id as int],
        ),
    ];
    // 문화권 목록(리메이크 조각 ②): 쓰인 문화권만 차례대로. 옛 저장소 · 옛 배치는 빈 목록 — 그때는 머리 단 없이 예전 그대로 쌓는다.
    final spheres = [
      for (final x in (json['spheres'] as List? ?? const []))
        SphereInfo('${x['id'] ?? ''}', '${x['name'] ?? ''}', count: ((x['count'] ?? 0) as num).toInt(), isDefault: x['default'] == true),
    ];
    // 문화권 단위 줄(스키마 4 · 계약 1-1): 받기만 한다. 열쇠가 없는 답(손으로 쓴 검사 답 · 옛 엔진)은 빈 목록 — P3-18의 '칸 없는 답' 규칙.
    // 원소가 객체가 아니어도 자리를 지키려 빈 줄로 담는다(차례가 곧 줄의 번호).
    final sphereLines = [
      for (final x in (json['sphereLines'] as List? ?? const [])) SphereLine.fromJson(x is Map ? x : const {}),
    ];
    return SceneLayout._(packs, tracks, epochs, categories, axis, fixed, specs, rowTrack, variants, spheres, sphereLines);
  }

  final List<PackInfo> packs;
  final List<TrackInfo> tracks;

  /// 문화권(리메이크 조각 ②) — 쓰인 것만 차례대로. 비면 머리 단 없이 예전 그대로.
  final List<SphereInfo> spheres;

  /// 문화권 단위 줄(스키마 4 — 사람 띠 · 문화권 시대 · 주기 줄 · 답의 차례). 3단계는 받기만 — 쌓기 · 그리기 어디에서도 읽지 않는다. 옛 답은 빈 목록.
  final List<SphereLine> sphereLines;

  /// 트랙 번호(목록 자리) → 그 문화권의 [spheres] 자리(문화권 밖 · 모르는 id면 −1).
  final _sphereOfTrack = <int>[];

  void _recountSpheres() {
    _sphereOfTrack.clear();
    for (final t in tracks) {
      // 엔진 답의 `sphere_at`(한 벌 P3-18) — 없는 답(손으로 쓴 검사 답)만 옛 셈으로 찾는다.
      _sphereOfTrack.add(t.sphereAt ?? (t.sphere.isEmpty ? -1 : spheres.indexWhere((x) => x.id == t.sphere)));
    }
  }

  /// 이번 쌓기에서 문화권마다 머리 단에 선 첫 트랙(목록 자리 — 그 문화권을 쌓지 않았으면 −1). 머리 단 자리는 그 트랙의 위에서 센다([sphereHeadTop]).
  List<int> _sphereFirst = const [];
  final List<EpochInfo> epochs;
  final List<CategoryInfo> categories;
  final List<AxisCell> axis;

  /// 켤 수 있는 것(소속 펼치기 · 대범위 모아 보기) — 계약 3-2절.
  final List<VariantInfo> variants;
  final List<RowGeo> _fixed;
  final List<RowSpec?> _specs;
  final List<int> _rowTrack;
  late Set<int> _enabled;
  late RowFlow _flow;
  ViewConditions _conditions = const ViewConditions();
  Set<int> _folded = const {};
  ViewState _view = ViewState.none;

  /// 켠 변형(번호 오름차순)과 거기서 이끌어 낸 값: 줄 → 쌓는 차례 · 덮어쓰는 값.
  List<VariantInfo> _on = const [];
  final Map<int, VariantRow> _stackOverride = {};
  final Set<int> _variantRowsOff = {};

  /// 집합 보기: 판 트랙의 순번(모든 판) · 켠 판과 그 판 트랙의 순번 · 판으로 옮겨 가 원래 트랙에서 빠진 줄 → 옮겨 간 판 줄.
  /// 빠진 줄은 켜지 않은 변형의 줄과 같이 [_variantRowsOff]에 들어 쌓이지 않는다.
  final Set<int> _boardTracks = {};
  VariantInfo? _boardOn;
  int _boardIndex = -1;
  final Map<int, int> _goneTo = {};

  /// 접힌 묶음(민족 · 대범위 가지)에서 이끌어 낸 값: 합쳐진 줄 → 그 묶음의 끝 줄(미포함) · 합쳐진 줄 → 그 줄들 ·
  /// 대범위 가지면 그 가지를 만든 변형의 열쇠 · 합쳐져 안 보이는 줄 · 트랙마다 남은 줄 수.
  final Map<int, int> _merged = {};
  final Map<int, List<int>> _mergedRows = {};
  final Map<int, String> _mergedVariant = {};
  final Set<int> _hiddenByGroup = {};
  late List<int> _trackRows;

  /// 보이는 줄들로 다시 셈한 트랙 값(계약 3절 끝): 기간 막대 단 수 · 기관 칸.
  late List<int> _trackRail;
  late List<bool> _trackOrgan;

  /// 움직임 줄이기: 줄 높이가 흐르지 않고 바로 새 자리로 간다.
  bool reduceMotion = false;

  /// 켠 자료집의 조합이 바뀔 때마다 오른다. 타일 보관이 이 번호로 옛 조합의 타일을 가린다.
  int version = 0;

  /// 줄 자리가 달라질 때마다 오른다(자료집 · 보기 조건 · 접힘). 그리는 쪽의 기억(이름 자리 …)을 새로 고칠 때 본다.
  int stackVersion = 0;

  // ---- 렌즈(주제 보기 — 감독 선택 D5 결정 5 A · 설계 docs/설계-10건/7-8-단체와-렌즈.md 10-2 · 10-3) ----
  // 렌즈를 켜면 지도자 칸 자리에 그 주제의 칸(타일의 칸 종류 8 — 변형 `theme:<주제 id>`)이 들어가고, 줄 배치는 렌즈 종류와 상관없이 하나다:
  // 지도자 자리 = (트랙의 지도자 칸 && 표시 '지도자') || (렌즈 켬 && 그 트랙이 [lensSlots]에 듦). 렌즈를 끄면 예전과 1px도 같다.

  String _themeLens = '';
  Set<String> _lensSlots = const {};

  /// 켠 렌즈의 주제 id(끄면 빈 글).
  String get themeLens => _themeLens;

  /// 렌즈 켬 배치에서 지도자 자리가 생기는 트랙(트랙의 글자 id — 항목 기록 themes의 `x_lens.slot`).
  Set<String> get lensSlots => _lensSlots;

  /// 그 주제의 렌즈 변형(`theme:<id>`)이 이 저장소에 있는가 — 없으면 칸은 그대로이고 지도자 칸만 옅어진다(그 주제 자료가 없는 렌즈).
  bool hasThemeVariant(String id) => variants.any((v) => v.kind == VariantInfo.kindTheme && v.uid == id);

  /// 렌즈를 켜고 끈다([id]가 빈 글이면 끔). [slots]를 주면 지도자 자리가 생기는 트랙도 바꾼다(저장소를 다시 지었을 때).
  /// 줄 배치 · 켠 변형이 달라지므로 다시 쌓고(흐름 360ms — 보기 조건과 같은 길) 판 번호를 갈아 타일을 다시 받는다. 달라졌으면 참.
  bool setThemeLens(String id, {Set<String>? slots}) {
    final next = slots ?? _lensSlots;
    if (id == _themeLens && ViewState.sameSet(next, _lensSlots)) return false;
    // 끈 채로 자리 트랙만 바뀌면 줄 배치는 그대로다(렌즈를 끈 배치는 그 목록을 보지 않는다) — 다시 쌓지 않는다.
    if (id.isEmpty && _themeLens.isEmpty) {
      _lensSlots = {...next};
      return false;
    }
    _themeLens = id;
    _lensSlots = {...next};
    _syncView();
    _stack(cause: StackCause.conditions, from: _conditions);
    return true;
  }

  /// 그 트랙이 렌즈 켬 배치에서 지도자 자리를 갖는가(트랙에 지도자 칸이 없어도).
  bool _lensSlotOf(TrackInfo t) => _themeLens.isNotEmpty && t.key.isNotEmpty && _lensSlots.contains(t.key);

  /// 3판의 값(줄의 kind …)을 읽었는가. 아니면 2단계의 굳은 자리 그대로다.
  bool get detailed => _specs.isNotEmpty && _specs.first != null;

  int get rowCount => _fixed.length;
  double get totalHeight => _flow.total;
  List<int> get enabledPacks => _enabled.toList()..sort();

  /// 줄의 생김새. 흐르는 동안에는 줄의 몫(height)만 흐르는 값이고 안의 단은 제자리다.
  RowGeo geo(int row) => _flow.geoOf(row);
  RowSpec? spec(int row) => _specs[row];
  int trackIndexOf(int row) => _rowTrack[row];
  TrackInfo trackOf(int row) => tracks[_rowTrack[row]];
  bool isVisible(int row) => _flow.liveOf(row);

  /// 줄의 몫의 위 자리(몸통 좌표). 끈 줄 · 다 접힌 줄은 -1.
  double rowTop(int row) => _flow.liveOf(row) ? _flow.topOf(row) : -1;

  /// 흐르는 동안 줄의 내용을 자를 높이(보이는 몫). 자를 것이 없으면 null — 그리는 쪽이 이 값으로 넘치는 내용을 가린다.
  double? rowClip(int row) => _flow.liveOf(row) ? _flow.clipOf(row) : null;

  bool isPackEnabled(int pack) => _enabled.contains(pack);
  ViewConditions get conditions => _conditions;
  Set<int> get foldedRows => _folded;

  // ---- 보기 상태(접힌 트랙 · 접힌 민족 · 끈 트랙) ----

  ViewState get viewState => _view;

  /// 지금 쓰는 자리 값 묶음(조감이면 G_BIRD가 덮은 값 — 명세 05 0절).
  ViewMetrics get metrics => _conditions.bird ? ViewMetrics.birdOf(_conditions.birdShape) : ViewMetrics.normal;

  /// 지금 조감으로 그리는가 — 밀도 조감이거나 자동 조감이 걸렸을 때.
  bool get bird => _conditions.bird;
  BirdShape? get birdShape => _conditions.bird ? _conditions.birdShape : null;

  /// 접힌 트랙의 높이(34 · 조감 22) · 접힌 민족 줄의 높이(30 · 조감 14) · 가는 막대의 높이(6 · 조감 3).
  double get foldedHeight => metrics.folded;
  double get foldedGroupHeight => metrics.foldedGroup;
  double get miniHeight => metrics.mini;

  /// 그 트랙을 접었는가(트랙 id) — 접힌 트랙의 줄은 모두 `isVisible` 거짓 · `rowTop` −1이고, 층은 가는 막대만 그린다.
  /// 집합 보기를 켠 동안은 **판의 접힘**이다: 판 트랙은 [ViewState.boardFolded], 나머지는 보는 사람이 다시 편 것만 펴진다
  /// (결정 1 A · 지금 연표의 `_foldedNow` — 접힘 기억 [ViewState.foldedTracks]는 그대로).
  bool isTrackFolded(int trackId) {
    if (_boardIndex < 0) return _view.isTrackFolded(trackId);
    return trackId == tracks[_boardIndex].id ? _view.boardFolded : !_view.boardOpen.contains(trackId);
  }

  // ---- 집합 보기(10건 6 · 감독 선택 D4 — 변형 kind 3) ----

  /// 판 트랙인가(트랙 순번) — 판마다 하나 있고 그 판을 켰을 때만 맨 위에 쌓인다. 켜지 않은 판 트랙은 끈 트랙처럼 자리가 없다.
  bool isBoardTrack(int trackIndex) => _boardTracks.contains(trackIndex);

  /// 지금 켠 판(없으면 null) · 그 판 트랙의 순번(없으면 −1) · 판 트랙 id(없으면 −1).
  VariantInfo? get board => _boardIndex < 0 ? null : _boardOn;
  int get boardTrackIndex => _boardIndex;
  int get boardTrackId => _boardIndex < 0 ? -1 : tracks[_boardIndex].id;

  /// 저장소에 실린 판(변형 kind 3) — DLC가 준 판 `view:<id>`와 시대 구분의 임시 판 `view:epoch:<uid>`.
  List<VariantInfo> get boards => [for (final v in variants) if (v.kind == VariantInfo.kindView) v];

  /// 판 하나를 켜고(열쇠) 끈다(빈 글). 저장소에 없는 열쇠는 끈다. 달라졌으면 참.
  bool setBoard(String key) => setViewState(withBoardState(key));

  /// 판을 켜고 끈 보기 상태 — [from]을 주면 그 값에서(한 번에 다시 쌓으려고).
  ViewState withBoardState(String key, [ViewState? from]) {
    final known = key.isNotEmpty && variants.any((v) => v.kind == VariantInfo.kindView && v.key == key);
    return (from ?? _view).withBoard(known ? key : '');
  }

  /// 트랙 하나를 접거나 편 보기 상태 — 판을 켠 동안은 판의 접힘으로(접힘 기억은 그대로), 아니면 접힘 기억으로.
  ViewState withTrackFoldedState(int trackId, bool on, [ViewState? from]) {
    final state = from ?? _view;
    final b = _boardIndexOf(state);
    if (b < 0) return state.withTrackFolded(trackId, on);
    if (trackId == tracks[b].id) return state.copyWith(boardFolded: on);
    return state.withBoardTrackOpen(trackId, !on);
  }

  /// 모든 트랙을 접거나 편 보기 상태(판 트랙은 빼고 센다 — 켜지 않은 판 트랙은 자리가 없다).
  ViewState withAllFoldedState(bool on) {
    final ids = [for (int i = 0; i < tracks.length; i++) if (!_boardTracks.contains(i)) tracks[i].id];
    if (_boardIndex < 0) return _view.withAllFolded(ids, on);
    return _view.copyWith(boardFolded: on, boardOpen: on ? const <int>{} : {...ids});
  }

  /// 그 보기 상태에서 켠 판 트랙의 순번(없으면 −1).
  int _boardIndexOf(ViewState state) {
    if (state.board.isEmpty) return -1;
    for (final v in variants) {
      if (v.kind != VariantInfo.kindView || v.key != state.board) continue;
      return tracks.indexWhere((t) => t.id == v.track);
    }
    return -1;
  }

  /// 판에 든 줄이면 그 줄, 판을 켜서 원래 트랙에서 빠진 줄이면 그 줄이 옮겨 간 판 줄(없으면 그대로).
  int boardRowOf(int row) => _goneTo[row] ?? row;

  /// 그 트랙을 껐는가(필터) — 줄이 통째로 빠지고 아래가 올라온다.
  bool isTrackOff(int trackId) => _view.isTrackOff(trackId);

  /// 그 민족 묶음의 열쇠(보기 상태에 넣고 뺄 때 쓴다).
  String groupKeyOf(TrackInfo track, GroupInfo group) => ViewState.groupKey(track.id, group.firstRow, group.depth, group.kind);

  /// 그 민족 묶음을 접었는가.
  bool isGroupFolded(GroupInfo group) => _view.isGroupFolded(groupKeyOf(trackOf(group.firstRow), group));

  /// 민족 묶음 하나를 접거나 편다. 달라졌으면 참.
  bool foldGroup(TrackInfo track, GroupInfo group, bool on) => setViewState(_view.withGroupFolded(groupKeyOf(track, group), on));

  // ---- 대범위 가지 접기(변형이 만드는 묶음) ----

  /// 변형이 만드는 묶음(대범위 가지)의 열쇠 — 왼쪽 칸의 누름이 알려 주는 `GutterHit.uid`(= 그 묶음의 `key`)로도 짓는다.
  String variantGroupKeyOf(int trackIndex, String key) =>
      ViewState.variantGroupKey(trackIndex >= 0 && trackIndex < tracks.length ? tracks[trackIndex].id : -1, key);

  /// 그 대범위 가지를 접었는가.
  bool isVariantGroupFolded(int trackIndex, VariantGroup group) => _view.isGroupFolded(variantGroupKeyOf(trackIndex, group.key));

  /// 대범위 가지 하나를 접거나 편다([key]는 그 묶음의 `key` — `__scope:<uid>`). 달라졌으면 참.
  bool foldVariantGroup(int trackIndex, String key, bool on) => setViewState(_view.withGroupFolded(variantGroupKeyOf(trackIndex, key), on));

  /// 대범위 가지 하나를 접었다 폈다 한다(왼쪽 칸의 점선 칸을 누를 때 — 지금 연표의 `toggleFoldPeople`). 달라졌으면 참.
  bool toggleVariantGroup(int trackIndex, String key) =>
      foldVariantGroup(trackIndex, key, !_view.isGroupFolded(variantGroupKeyOf(trackIndex, key)));

  /// 그 트랙의 켠 변형이 만든 묶음 가운데 [key]인 것(없으면 null).
  VariantGroup? variantGroupOf(int trackIndex, String key) {
    for (final g in variantGroups(trackIndex)) {
      if (g.key == key) return g;
    }
    return null;
  }

  /// 그 줄이 접힌 **대범위 가지**의 합쳐진 줄이면 그 가지를 만든 변형의 열쇠(`scope:<uid>`), 아니면 빈 글.
  /// 줄 이름이 그 가지의 접힘용 후보를 고를 때 쓴다(접힌 민족 줄은 단계로 고른다 — [RowLabels.pick]).
  String foldedVariantOf(int row) => _mergedVariant[row] ?? '';

  /// 트랙 하나를 접거나 편다 · 끄거나 켠다. 달라졌으면 참. 판을 켠 동안은 판의 접힘으로.
  bool foldTrack(int trackId, bool on) => setViewState(withTrackFoldedState(trackId, on));
  bool offTrack(int trackId, bool off) => setViewState(_view.withTrackOff(trackId, off));

  /// 그 줄이 '접힌 민족 줄'인가(그 묶음의 줄들이 합쳐진 한 줄).
  bool isFoldedGroupRow(int row) => _merged.containsKey(row) || _specs[row]?.kind == RowKind.foldedGroup;

  /// 그 줄에 몸통(띠 · 칸 · 사건 · 인물 · 승계선)을 그리는가 — 보이는 줄이되 접힌 민족 줄은 아니다
  /// (접힌 민족 줄에는 가는 막대만 남는다 — 지금 연표와 같이. 타일 층들이 [isVisible] 대신 이것을 본다).
  bool hasBody(int row) => isVisible(row) && !isFoldedGroupRow(row);

  /// 접힌 민족 줄에 합쳐져 안 보이는 줄인가.
  bool isMergedAway(int row) => _hiddenByGroup.contains(row);

  /// 합쳐진 줄 → 그 묶음의 줄 범위(합쳐 놓은 줄 포함 · 끝 줄 미포함). 민족 묶음은 줄 번호가 이어지므로 이 범위가 곧 그 묶음이다.
  ///
  /// **대범위 가지에서는 이 범위를 믿지 마세요.** 가지는 드는 줄이 이어져 있지 않고(월흔해에서 `[8, 11, 12]`),
  /// 합쳐 놓은 줄은 번호가 아니라 **쌓는 차례**로 고른다 — 그래서 이 범위는 `합쳐 놓은 줄 … 마지막 줄 + 1`이라
  /// ① 가지에 들지 않는 사이 줄까지 품고(넉넉한 쪽이라 해롭지 않다) ② **합쳐 놓은 줄보다 번호가 작은 줄은 아예 빠진다**.
  /// ②는 조용히 비는 화면을 만든다: 타일 받기(`scene.dart`)가 그 줄의 줄 묶음을 받지 않으면 합쳐진 줄의 가는 막대가 통째로 빈다.
  ///
  /// 그러므로 **가지의 줄을 훑는 곳은 모두 [mergedRows]를 읽어야 한다**(`for (final r in e.value)`).
  /// 월흔해 견본은 가지의 줄이 모두 오름차순이라 ②가 아직 드러나지 않을 뿐이다.
  Map<int, int> get mergedGroups => _merged;

  /// 합쳐진 줄 → 그 줄에 합쳐진 줄들(합쳐 놓은 머리 줄까지 · 쌓는 차례). 민족 묶음과 대범위 가지가 함께 든다.
  /// 가는 막대처럼 **정확히 그 줄들만** 보아야 하는 곳이 읽는다.
  Map<int, List<int>> get mergedRows => _mergedRows;

  /// 트랙에 남은 줄 수(민족을 접어 합쳐진 줄은 하나로 센다) — 자동 밀도의 글줄 수가 이 값을 본다.
  int visibleRowCount(int trackIndex) => _trackRows[trackIndex];

  /// 지금 켠 변형(줄이 옮겨 쌓인다). 타일 · 조회 요청에 `"variants"`로 실어 보낸다.
  List<VariantInfo> get variantsOn => _on;
  List<String> get variantKeys => [for (final v in _on) v.key];

  /// 그 상위 띠의 소속을 펼쳤는가 · 그 대범위를 켰는가.
  bool isHostExpanded(int bandId) => _view.expandedHosts.contains(bandId);

  /// 그 나라 띠의 단체를 펼쳤는가(리메이크 조각 ④).
  bool isGroupsExpanded(int bandId) => _view.expandedGroups.contains(bandId);
  bool isScopeOpen(String uid) => _view.openScopes.contains(uid);

  /// 상위 띠 하나의 소속을 펼치거나 접는다. 달라졌으면 참(줄이 360ms 흐른다).
  bool expandHost(int bandId, bool on) => setViewState(_view.withHostExpanded(bandId, on));

  /// 줄 하나의 매달린 속국 이름표를 접었는가 · 접거나 편다(상국 띠의 '속국' 단추). 달라졌으면 참 — 그 줄이 360ms 동안 낮아지거나 높아진다.
  /// 그 줄의 매달린 속국 이름표가 접혀 있는가 — 처음에는 모두 접힘(리메이크 2부 · [ViewState.openHangs]).
  bool isHangFolded(int row) => !_view.openHangs.contains(row);
  bool foldHangs(int row, bool on) => setViewState(_view.withHangsOpen(row, !on));

  /// 대범위 하나를 켜거나 끈다. 달라졌으면 참.
  ///
  /// **켜는 순간 그 가지의 접힘 기억은 지운다** — 지금 연표의 `toggleScope`(js/timeline.js 7786)가
  /// `foldedPeoples`에서 `<트랙 id>|__scope:<uid>`를 지워 "늘 펼친 채 모이게" 하는 것과 같다.
  /// 그래서 켤 때는 [revealForScope]를 지나간다. 끌 때는 그대로 둔다 — 가지가 사라지면 그 접힘은 어차피 쓰이지 않는다.
  bool openScope(String uid, bool on) => setViewState(on ? revealForScope(uid) : _view.withScopeOpen(uid, false));

  // ---- 그릇의 세 상태(리메이크 조각 ③) ----

  /// 대범위 하나의 지금 상태([ScopeState]): 끈 것은 풀림, 켠 것은 그 가지가 접혔으면 접힘 · 아니면 펼침.
  ScopeState scopeStateOf(String uid) {
    if (!_view.openScopes.contains(uid)) return ScopeState.loose;
    for (final v in variants) {
      if (v.kind != VariantInfo.kindScope || v.uid != uid) continue;
      final at = tracks.indexWhere((t) => t.id == v.track);
      if (at < 0) continue;
      for (final g in v.groups) {
        if (_view.isGroupFolded(variantGroupKeyOf(at, g.key))) return ScopeState.closed;
      }
    }
    return ScopeState.open;
  }

  /// 그 대범위를 [state]로 둘 보기 상태 — [setViewState]에 한 번 넣으면 다시 쌓기도 한 번이다([from]은 [revealForScope]와 같은 뜻).
  /// 펼침 = 켜고 가지를 편다 · 접힘 = 켜고 가지를 접는다 · 풀림 = 끈다(가지의 접힘 기억은 켤 때 지워지므로 그대로 둔다).
  ViewState viewForScopeState(String uid, ScopeState state, [ViewState? from]) {
    final base = from ?? _view;
    if (state == ScopeState.loose) return base.withScopeOpen(uid, false);
    var next = revealForScope(uid, base);
    if (state == ScopeState.closed) {
      for (final v in variants) {
        if (v.kind != VariantInfo.kindScope || v.uid != uid) continue;
        final at = tracks.indexWhere((t) => t.id == v.track);
        if (at < 0) continue;
        for (final g in v.groups) {
          next = next.withGroupFolded(variantGroupKeyOf(at, g.key), true);
        }
      }
    }
    return next;
  }

  /// 그 줄을 가지로 둔 **켠** 대범위의 uid(없으면 빈 글) — 테두리 항목(구역 23)에 uid가 실리지 않아 그리는 쪽이 첫 줄로 찾는다.
  String scopeUidOfRow(int row) {
    for (final v in _on) {
      if (v.kind != VariantInfo.kindScope) continue;
      for (final g in v.groups) {
        if (g.rows.contains(row)) return v.uid;
      }
    }
    return '';
  }

  /// 그 줄이 어느 변형의 줄인가(0이면 늘 있는 줄) · 지금 보이는 변형의 줄인가.
  int variantOf(int row) => _specs[row]?.variant ?? 0;

  /// 그 변형에서 생기는 왼쪽 칸의 묶음(켠 것만).
  Iterable<VariantGroup> variantGroups(int trackIndex) sync* {
    for (final v in _on) {
      if (v.track == tracks[trackIndex].id) yield* v.groups;
    }
  }

  /// 트랙이 하나라도 있고 모두 접혔는가(판 트랙은 켰을 때만 센다).
  bool get allFolded {
    var any = false;
    for (int i = 0; i < tracks.length; i++) {
      if (_boardTracks.contains(i) && i != _boardIndex) continue;
      any = true;
      if (!isTrackFolded(tracks[i].id)) return false;
    }
    return any;
  }

  /// 보기 상태를 바꾼다. 달라졌으면 참이고, 줄 쌓기에 쓰이는 것이 달라졌을 때만 다시 쌓는다.
  /// 끈 트랙(필터)이 달라진 다시 쌓기는 흐르지 않는다(자료집 끔과 같은 길).
  bool setViewState(ViewState next) {
    if (next == _view) return false;
    final restack = !next.stacksSameAs(_view);
    final instant = !ViewState.sameSet(next.offTracks, _view.offTracks);
    // 소속 펼치기 · 대범위 모아 보기는 띠가 옛 줄에서 새 줄로 모여드는 연출(`_gatherDraw`)을 부른다 — 접기와 갈라 알린다.
    final gather = !ViewState.sameSet(next.expandedHosts, _view.expandedHosts) || !ViewState.sameSet(next.expandedGroups, _view.expandedGroups) || !ViewState.sameSet(next.openScopes, _view.openScopes);
    _view = next;
    if (restack) {
      _syncView();
      _stack(instant: instant, cause: gather ? StackCause.variants : StackCause.view);
    }
    return true;
  }

  /// 모든 트랙을 접거나 편다(지금 연표의 `foldAll` — 판을 켠 동안은 판의 접힘으로).
  bool foldAll(bool on) => setViewState(withAllFoldedState(on));

  /// **가려는 곳 펴기**(지금 연표의 `focusOn` ③ — js/timeline.js 2472): 그 줄이 보이려면 바뀌어야 할 보기 상태.
  /// 바꿀 것이 없으면 지금 값을 그대로 돌려준다(`identical(revealFor(row), viewState)`).
  /// 부르는 쪽은 이 값을 [setViewState]에 한 번 넣는다 — 그래야 **다시 쌓기가 한 번**이다.
  ///
  /// 펴는 것: ① 접힌 트랙 ② 그 줄을 **안에** 감춘 접힌 민족 묶음(그 줄이 곧 합쳐진 줄이면 접힌 채로 둔다)
  /// ③ 켜지 않은 변형(펼치지 않은 소속 · 켜지 않은 대범위) — 그 줄이 얹히는 줄(`after`)을 따라 올라가며 겹겹이 켠다.
  ///
  /// 끈 트랙(필터)은 건드리지 않는다(지금 연표의 `focusOn`도 필터는 그대로 둔다). 빈 줄 접기로 접힌 줄도 그대로다 —
  /// 그 줄은 보는 범위를 옮기면 저절로 펴진다(`RowFolder`).
  ViewState revealFor(int row) {
    if (row < 0 || row >= rowCount) return _view;
    // 집합 보기를 켠 동안 판으로 옮겨 간 줄이면 그 판 줄로(원래 트랙의 그 줄은 빠져 있다).
    row = boardRowOf(row);
    if (row < 0 || row >= rowCount) return _view;
    final track = trackOf(row);
    var next = _view;
    // 그 줄이 접힌 문화권 안이면 문화권부터 편다(리메이크 조각 ②).
    final sphere = sphereIndexOfTrack(tracks.indexOf(track));
    if (sphere >= 0 && next.isSphereFolded(spheres[sphere].id)) next = next.withSphereFolded(spheres[sphere].id, false);
    if (isTrackFolded(track.id)) next = withTrackFoldedState(track.id, false, next);
    next = _unfoldGroupsAround(track, row, next);
    // 이미 켜 둔 대범위의 가지가 접혀 그 줄을 감추고 있으면 그 가지도 편다(지금 연표의 `focusOn` — js 2508 · 2517).
    for (final v in _on) {
      if (v.track == track.id) next = _unfoldBranchesAround(v, row, next);
    }
    int at = row;
    for (int step = 0; step < 50; step++) {
      final id = _specs[at]?.variant ?? 0;
      if (id == 0) break;
      VariantInfo? v;
      for (final x in variants) {
        if (x.id == id) v = x;
      }
      if (v == null) break;
      // 집합 보기의 줄은 그 판을 켰을 때만 있다 — 다른 판으로 저절로 바꾸지 않는다(판 트랙의 접힘은 위에서 폈다).
      if (v.kind == VariantInfo.kindView) break;
      if (v.kind == VariantInfo.kindHost) {
        next = next.withHostExpanded(v.band, true);
      } else if (v.kind == VariantInfo.kindGroups) {
        next = next.withGroupsExpanded(v.band, true);
      } else {
        // 대범위를 **새로 켜는** 길은 지금 연표에 `toggleScope` 하나뿐이고, 그 길은 늘 그 가지의 접힘 기억을 지운다
        // (js 7786). 이미 켜 둔 대범위는 건드리지 않는다 — 그때는 아래의 `_unfoldBranchesAround`가 그 줄만 편다.
        next = next.openScopes.contains(v.uid) ? next : revealForScope(v.uid, next);
      }
      next = _unfoldBranchesAround(v, row, next);
      // 그 줄이 얹히는 줄도 보여야 한다 — 그 줄이 또 다른 변형의 줄이면 그것도 켠다(소속 안의 소속).
      int after = -1;
      for (final r in v.rows) {
        if (r.row == at) after = r.after;
      }
      if (after < 0 || after == at) break;
      at = after;
      next = _unfoldGroupsAround(track, at, next);
    }
    return next;
  }

  /// **대범위 하나를 켤 때의 보기 상태**(지금 연표의 `toggleScope` — js 7786 · `focusOn` — js 2517 · 2529):
  /// 그 대범위를 켜고, 접어 둔 그 가지도 편다. 둘을 한 값으로 돌려주므로 [setViewState]에 한 번만 넣으면 다시 쌓기도 한 번이다.
  ///
  /// [from]을 주면 지금 보기 상태 대신 그 값에서 시작한다 — 한 손짓이 **다른 것까지 함께 바꿀 때**(상위 정권을 펼치면서
  /// 대범위도 켜는 `archive_app._toggleVariant`) 앞서 엮어 둔 것이 조용히 사라지지 않게 하려는 것이다.
  ViewState revealForScope(String uid, [ViewState? from]) {
    var next = (from ?? _view).withScopeOpen(uid, true);
    for (final v in variants) {
      if (v.kind != VariantInfo.kindScope || v.uid != uid) continue;
      final at = tracks.indexWhere((t) => t.id == v.track);
      if (at < 0) continue;
      for (final g in v.groups) {
        final key = variantGroupKeyOf(at, g.key);
        if (next.isGroupFolded(key)) next = next.withGroupFolded(key, false);
      }
    }
    return next;
  }

  /// 그 줄을 **안에** 감춘 접힌 대범위 가지를 편 보기 상태(그 줄이 곧 합쳐진 줄이면 접힌 채로 둔다 — 민족과 같은 규칙).
  /// 가지의 줄 번호는 이어지지 않으므로 드는 줄 목록으로 가린다.
  ViewState _unfoldBranchesAround(VariantInfo v, int row, ViewState state) {
    var next = state;
    final at = tracks.indexWhere((t) => t.id == v.track);
    if (at < 0) return next;
    for (final g in v.groups) {
      if (g.rows.length <= 1 || !g.rows.contains(row) || g.rows.first == row) continue;
      final key = variantGroupKeyOf(at, g.key);
      if (next.isGroupFolded(key)) next = next.withGroupFolded(key, false);
    }
    return next;
  }

  /// 그 줄을 안에 감춘 접힌 민족 묶음을 편 보기 상태.
  ViewState _unfoldGroupsAround(TrackInfo track, int row, ViewState state) {
    var next = state;
    for (final g in track.groups) {
      if (g.rowCount <= 0 || row <= g.firstRow || row >= g.firstRow + g.rowCount) continue;
      final key = groupKeyOf(track, g);
      if (next.isGroupFolded(key)) next = next.withGroupFolded(key, false);
    }
    return next;
  }

  /// 가는 막대(접힌 트랙 · 접힌 민족 줄)의 단 [lane]의 위 자리 — 명세 05 5.3.
  /// 보통은 `5 + 단 × 8`이고, 조감은 상자 안에서 가운데 맞춤이다. [boxHeight]를 주지 않으면 접힌 트랙의 상자다.
  double miniTop(int lane, [double? boxHeight]) {
    final g = metrics;
    final box = boxHeight ?? g.folded;
    final top = g.isBird ? (box - (2 * g.miniPitch + g.mini)) / 2 : g.miniTop;
    return top + lane * g.miniPitch;
  }

  /// 그 줄이 쓰는 기본 글줄 수(분류별 글줄은 뺀 트랙의 기준) — 명세 05 7.1.
  int baseLines(int row) {
    if (_conditions.bird) return 1;
    if (_conditions.density < 0) return 2;
    // 리메이크 2부(목업 서고): 자동 밀도도 머리 한 줄(예전: 트랙 줄 여섯 이하면 둘).
    return 1;
  }

  /// 줄 이름의 글자 크기(`--nameSize`) · 사건 글자의 크기 — 명세 05 7.1.
  double nameSize(int row) => _conditions.bird ? 10.5 : (baseLines(row) > 1 ? 13.5 : 12.5);
  /// 꼬리표 갈래 E(설계 4-1 '실제 띠에 입힘' — 목업 t-e): 사건 글은 머리의 이름(9 굵게)과 한 계통으로 9.5(예전 11.5 · 넉넉하게 12).
  double eventSize(int row) => _conditions.bird ? 10 : 9.5;

  /// 그 줄 위의 틈 가운데 띠 몫(꼬리표 갈래 E — 줄 위 틈 5, 위로 솟는 것이 있는 줄은 + 15 · 접힌 민족 줄 · 그 밖 줄 · 조감은 0).
  double tabOf(int row) {
    if (_conditions.bird || isFoldedGroupRow(row)) return 0;
    final spec = _specs[row];
    return spec?.kind == RowKind.common ? 0 : metrics.tab + _lift(row, spec);
  }

  /// 줄 위 틈에 더하는 몫(조감이 아닐 때): 솟는 줄 [G.raise] · 그릇의 줄 [G.contain] · 그 밖 0.
  double _lift(int row, RowSpec? spec) {
    if (spec == null || metrics.isBird) return 0;
    if (spec.raised) return G.raise;
    return spec.contained || _scopeRows.contains(row) ? G.contain : 0;
  }

  // ---- 흐르는 중의 값(연출이 읽는다 — 계약 3-1절 · 움직임 원칙 ③ · ④) ----
  //
  // 지금 연표의 두 연출이 이 값을 쓴다:
  //   · `_gatherDraw`(대범위를 켜고 끌 때 모여드는 것) — 줄마다 [rowShift]만큼 옛 자리에서 출발해 [flowProgress]로 흐른다.
  //   · `_squash`(밀도 · 조감이 바뀔 때의 잔상)        — 옛 줄의 생김새 [rowFromGeo] · 옛 높이 [rowFromHeight] ·
  //     옛 자리 값 묶음 [fromMetrics](조감에서 나왔으면 [wasBird])로 잔상을 그려 옅어지게 한다.
  //
  // 줄 **안**의 것(띠 하나하나 · 사건 · 이름표)을 따로 옮기는 일은 띠가 옛 줄 어디에 있었는지 아는 쪽(타일 · 층)의 몫이다.
  // 줄 쌓기는 줄 단위만 맡는다.

  /// 줄 자리가 흐르는 중인가 — 그동안 화면의 시계가 돌아야 한다.
  bool get flowing => _flow.flowing;

  /// 움직임 곡선을 먹인 진행(0~1 · 흐르지 않으면 1) · 흐른 시간 · 남은 시간(ms).
  double get flowProgress => _flow.progress;
  double get flowElapsed => _flow.elapsed;
  double get flowRemain => _flow.remain;

  /// 흐름이 새로 시작될 때마다 오른다 — 그리는 쪽이 잔상을 한 번만 붙이려고 본다.
  int get flowVersion => _flow.version;

  /// 이번 다시 쌓기를 일으킨 것([StackCause]) — 연출을 가른다(대범위를 켜면 모여들고, 밀도가 바뀌면 잔상이 남는다).
  StackCause get stackCause => _cause;

  /// 그 줄의 옛 자리 · 옛 높이 · 옛 생김새와, 옛 자리에서 새 자리까지의 거리(지금 연표 `_gather`의 줄별 `dy`).
  double rowFromTop(int row) => _flow.fromTopOf(row);
  double rowFromHeight(int row) => _flow.fromHeightOf(row);
  RowGeo rowFromGeo(int row) => _flow.fromGeoOf(row);
  double rowShift(int row) => _flow.shiftOf(row);

  /// 그 줄이 흐르기 전에 보였는가 · 이번에 새로 났는가 · 사라지는 중인가.
  /// 새로 난 줄은 옮길 옛 자리가 없다 — 옮기지 않고 떠오르기만 한다(지금 연표 `_gather`의 `{dy: 0, all: true}`).
  bool wasVisible(int row) => _flow.wasLiveOf(row);
  bool isBornRow(int row) => _flow.bornOf(row);
  bool isGoneRow(int row) => _flow.goneOf(row);

  /// 트랙의 옛 위 자리(흐르는 내내 화면 밖인 트랙을 가릴 때 — 지금 연표의 `_squashAway`).
  double trackFromTop(int index) => _flow.fromTrackTopOf(index);

  /// 흐르기 전의 보기 조건과 자리 값 묶음 — 밀도 · 조감이 바뀌는 흐름에서 잔상이 **옛 모습 그대로** 옅어지게.
  ViewConditions get fromConditions => _fromConditions;
  ViewMetrics get fromMetrics => _fromConditions.bird ? ViewMetrics.birdOf(_fromConditions.birdShape) : ViewMetrics.normal;

  /// 흐르기 전이 조감이었으면 그 모양(지금 연표의 `.was-bird` · `was-bird-<모양>`), 아니면 null.
  BirdShape? get wasBird => _fromConditions.bird ? _fromConditions.birdShape : null;

  /// 지금 흐르는 것이 밀도 · 조감 전환인가 — 참이면 줄 안의 것이 옛 줄에 잔상으로 남는다(`_squash`).
  bool get metricsChanged => _flow.flowing && _cause == StackCause.conditions && !identical(fromMetrics, metrics);

  /// 화면의 시계가 장면마다 부른다(지난 시간 ms).
  void tickFlow(double dtMs) => _flow.tick(dtMs);

  /// 흐름을 끝까지 보낸다(검사 · 움직임 줄이기).
  void finishFlow() => _flow.finish();

  /// 트랙의 세로 자리와 높이(위아래 여백 포함). 끈 트랙은 (-1, 0).
  double trackTop(int index) => _flow.trackTopOf(index);
  double trackHeight(int index) => _flow.trackHeightOf(index);

  /// 민족 단계의 수(왼쪽 민족 칸의 개수)와 왼쪽 칸의 폭: 196 + (단계 − 1) × 22.
  int get peopleDepth {
    int depth = 1;
    for (final t in tracks) {
      for (final g in t.groups) {
        if (g.kind != 2 && g.depth + 1 > depth) depth = g.depth + 1;
      }
    }
    // 켠 집합 보기의 왼쪽 칸(원래 트랙 칩 · 제 민족 칩 — 두 단)도 센다(지금 연표의 판 트랙 tr.depth — 판을 켜면 폭이 늘 수 있다).
    if (_boardIndex >= 0) {
      for (final g in variantGroups(_boardIndex)) {
        if (g.kind != 2 && g.depth + 1 > depth) depth = g.depth + 1;
      }
    }
    return depth;
  }

  /// 왼쪽 칸 폭 — 목업 GUT 240 하나(리메이크 2부: 민족 칸이 없어져 단 수에 따라 넓어지지 않는다). 휴대폰은 좁힌 폭([SceneView.phoneGutter]).
  double get gutterWidth => SceneView.phone ? SceneView.phoneGutter : G.gutter;

  /// 트랙이 없는 자료집(남의 줄에 사건만 덧붙인 것)을 꺼도 줄은 그대로지만 판 번호는 바뀐다 — 타일은 다시 받아야 한다.
  /// 같은 조합으로 돌아오면 그 조합의 옛 판 번호를 다시 쓴다 → 받아 둔 타일을 그대로 쓴다.
  void enable(Set<int> packs) {
    if (packs.length == _enabled.length && packs.containsAll(_enabled)) return;
    _versionOf[_combinationKey] = version;
    _enabled = {...packs};
    version = _versionOf[_combinationKey] ?? ++_lastVersion;
    // 켜고 끄기도 흐른다(4단계 1걸음): 켠 트랙은 0에서 자라나고 끈 트랙은 0으로 접히며 아래가 따라 움직인다. 보던 줄은 제자리(장면의 닻).
    _stack(cause: StackCause.packs);
  }

  /// 보기 조건(켠 단 · 밀도)을 바꾼다. 바뀌었으면 참.
  bool setConditions(ViewConditions next) {
    if (next == _conditions) return false;
    final before = _conditions;
    _conditions = next;
    // 흐르는 동안 잔상은 **옛 조건**의 모습이어야 한다(조감에서 나오면 `.was-bird` — 지금 연표의 `_squashFirst`).
    _stack(cause: StackCause.conditions, from: before);
    return true;
  }

  /// 접힌 줄(보이는 기간에 내용이 없는 줄)을 바꾼다. 바뀌었으면 참. 2판 입력에서는 접지 않는다.
  bool setFolded(Set<int> rows) {
    if (!detailed || (rows.length == _folded.length && rows.containsAll(_folded))) return false;
    _folded = {...rows};
    _stack(cause: StackCause.rows);
    return true;
  }

  /// 타일을 거르는 조건(필터의 거르개)의 서명. 바뀌면 판 번호가 바뀌어 타일을 다시 받고, 같은 조건으로 돌아오면 옛 판 번호를 다시 쓴다(자료집 조합과 같은 길). 바뀌었으면 참.
  bool setFilterKey(String key) {
    if (key == _filterKey) return false;
    _versionOf[_combinationKey] = version;
    _filterKey = key;
    version = _versionOf[_combinationKey] ?? ++_lastVersion;
    return true;
  }

  String _filterKey = '';
  String _variantKey = '';
  String get _combinationKey => '${_combination(_enabled)}#$_filterKey#$_variantKey';

  final _versionOf = <String, int>{};
  int _lastVersion = 0;
  static String _combination(Set<int> packs) => (packs.toList()..sort()).join(',');

  /// 접힌 민족에서 이끌어 내는 값을 다시 셈한다: 어느 줄이 합쳐진 줄이고 어느 줄이 그 안에 숨는가, 트랙마다 줄이 몇인가.
  /// 접힌 묶음 속의 묶음은 이미 숨었으므로 세지 않는다(지금 연표의 `groupsOf`가 접힌 묶음 아래로 내려가지 않는 것과 같다).
  /// 켠 대범위 가지의 줄([_syncView]가 채운다 — [_lift]가 본다).
  final _scopeRows = <int>{};

  /// 켠 그릇들(리메이크 2부 포개짐 — remake/nest/지도.md 3-1): 변형 하나의 묶음 줄 집합 · 깊이(이 그릇을 품은 켠 그릇 수 — 묶음 줄 집합의 품음으로 셈).
  final List<ScopeOn> _scopesOn = [];
  final Map<String, ScopeOn> _scopeOnByUid = {};

  /// 켠 그릇 변형이 덮어쓴 줄(그 줄의 머리 · 발은 저장값이 아니라 묶음 집합으로 셈한다).
  final _scopeOverride = <int>{};

  List<ScopeOn> get scopesOn => _scopesOn;
  ScopeOn? scopeOnOf(String uid) => _scopeOnByUid[uid];

  /// 켠 그릇의 깊이(바깥 0 · 그 안 1 …). 켜지 않았으면 0.
  int scopeDepthOf(String uid) => _scopeOnByUid[uid]?.depth ?? 0;

  /// 그 켠 그릇이 켠 바깥 그릇의 접힘 속에 숨었는가(바깥이 접히면 안쪽 그릇은 그리지 않는다 — 닫힌 폴더의 작은 꼬리표로).
  bool _scopeHidden(ScopeOn s) {
    for (final o in _scopesOn) {
      if (identical(o, s) || o.track != s.track || o.rows.length <= s.rows.length || !o.rows.containsAll(s.rows)) continue;
      for (final k in o.keys) {
        if (_view.isGroupFolded(variantGroupKeyOf(o.track, k))) return true;
      }
    }
    return false;
  }

  double _scopeHeadOf(ScopeOn s) => metrics.isBird ? metrics.scopeHead : (s.depth == 0 ? G.folderHead : G.boxHead);
  double _scopeFootOf(ScopeOn s) => metrics.isBird ? metrics.scopeFoot : (s.depth == 0 ? G.folderFoot : G.boxFoot);

  bool _stackedRow(int r) => !_folded.contains(r) && !_hiddenByGroup.contains(r) && !_variantRowsOff.contains(r);

  /// 켠 그릇의 세로 자리(배치 px): 위 = 첫 보이는 줄의 띠 윗변 − 탭 − (그 줄에서 시작하는 켠 그릇 가운데 깊이가 이 그릇 이상인 것들의 머리),
  /// 아래 = 마지막 보이는 줄의 끝 + (그 줄에서 끝나는 같은 것들의 발). 바깥이 접혀 숨었거나 보이는 줄이 없으면 null.
  ({double top, double bottom, int first, int last})? scopeSpanOf(String uid) {
    final s = _scopeOnByUid[uid];
    if (s == null || _scopeHidden(s)) return null;
    final order = _orderOf(tracks[s.track]);
    int firstOfS(ScopeOn x) => order.firstWhere((r) => x.rows.contains(r) && _stackedRow(r), orElse: () => -1);
    int lastOfS(ScopeOn x) => order.lastWhere((r) => x.rows.contains(r) && _stackedRow(r), orElse: () => -1);
    final first = firstOfS(s), last = lastOfS(s);
    if (first < 0 || !isVisible(first)) return null;
    double heads = 0, feet = 0;
    for (final x in _scopesOn) {
      if (x.track != s.track || x.depth < s.depth || _scopeHidden(x)) continue;
      if (firstOfS(x) == first) heads += _scopeHeadOf(x);
      if (lastOfS(x) == last) feet += _scopeFootOf(x);
    }
    final top = rowTop(first) + geo(first).bandTop - tabOf(first) - heads;
    final bottom = rowTop(last) + geo(last).height + feet;
    return (top: top, bottom: bottom, first: first, last: last);
  }

  void _syncView() {
    // 켠 변형: 펼친 상위 띠(host)와 켠 대범위(scope)를 저장소의 변형에 맞춘다. 차례는 번호 순이다(겹치면 뒤엣것이 이긴다 —
    // 대범위가 소속을 이기도록 내보내기가 대범위에 큰 번호를 준다).
    // 집합 보기(kind 3)는 열쇠로 켠다 — 한 번에 판 하나(ViewState.board).
    // 렌즈의 변형(`theme:<주제 id>`)은 보기 상태가 아니라 켠 렌즈([setThemeLens])로 고른다.
    _on = [
      for (final v in variants)
        if (switch (v.kind) {
          VariantInfo.kindHost => _view.expandedHosts.contains(v.band),
          VariantInfo.kindGroups => _view.expandedGroups.contains(v.band),
          VariantInfo.kindView => v.key == _view.board,
          VariantInfo.kindTheme => _themeLens.isNotEmpty && v.uid == _themeLens,
          _ => _view.openScopes.contains(v.uid),
        })
          v,
    ]..sort((a, b) => a.id.compareTo(b.id));
    _boardTracks.clear();
    _boardOn = null;
    _boardIndex = -1;
    _goneTo.clear();
    for (final v in variants) {
      if (v.kind != VariantInfo.kindView) continue;
      final at = tracks.indexWhere((t) => t.id == v.track);
      if (at < 0) continue;
      _boardTracks.add(at);
      if (v.key == _view.board) {
        _boardOn = v;
        _boardIndex = at;
      }
    }
    _stackOverride.clear();
    _scopeOverride.clear();
    _variantRowsOff.clear();
    _scopesOn.clear();
    _scopeOnByUid.clear();
    for (final v in _on) {
      if (v.kind != VariantInfo.kindScope) continue;
      final at = tracks.indexWhere((t) => t.id == v.track);
      if (at < 0) continue;
      final one = ScopeOn(v.uid, at, {for (final g in v.groups) ...g.rows}, [for (final g in v.groups) g.key], within: v.within);
      _scopesOn.add(one);
      _scopeOnByUid[v.uid] = one;
    }
    // 깊이 = 같은 트랙에서 제 줄을 모두 품는 **켠** 그릇의 수. 품는 관계는 엔진 답 `within`(한 벌 P3-18 · 정적)에서 읽고 켠 것만 센다 —
    // 답에 없으면(손으로 쓴 검사 답) 옛 셈(켠 그릇끼리 `containsAll`).
    final onScopes = {for (final v in _on) if (v.kind == VariantInfo.kindScope) v.id};
    for (final a in _scopesOn) {
      final within = a.within;
      a.depth = within != null
          ? within.where(onScopes.contains).length
          : _scopesOn.where((b) => !identical(a, b) && b.track == a.track && b.rows.length > a.rows.length && b.rows.containsAll(a.rows)).length;
    }
    // 켠 대범위 가지의 줄은 그릇의 줄이다(위 틈 15 — 매다는 실 자리 · 리메이크 조각 ③). 접혀 합쳐진 줄은 탭이 0이라 상관없다.
    _scopeRows.clear();
    for (final v in _on) {
      if (v.kind != VariantInfo.kindScope) continue;
      for (final g in v.groups) {
        _scopeRows.addAll(g.rows);
      }
    }
    final on = {for (final v in _on) v.id};
    for (int r = 0; r < _specs.length; r++) {
      final variant = _specs[r]?.variant ?? 0;
      if (variant != 0 && !on.contains(variant)) _variantRowsOff.add(r);
    }
    for (final v in _on) {
      // 포개진 안쪽 그릇(켠 바깥 그릇 안)의 줄 기록은 넣지 않는다 — 바깥 변형이 이미 안쪽 구성원을 제 안에 두었고, 줄 울타리 덕에 줄이 같다(remake/nest/지도.md 3-1).
      if (v.kind == VariantInfo.kindScope && (_scopeOnByUid[v.uid]?.depth ?? 0) > 0) continue;
      for (final r in v.rows) {
        if (r.gone) {
          // 판으로 옮겨 간 원래 트랙의 줄 — 쌓지 않는다(빈 줄이 남지 않음 · 지금 연표는 그 줄 없이 다시 배치한다).
          _variantRowsOff.add(r.row);
          if (r.ord >= 0) _goneTo[r.row] = r.ord;
          continue;
        }
        _stackOverride[r.row] = r;
        if (v.kind == VariantInfo.kindScope) {
          _scopeOverride.add(r.row);
        } else {
          _scopeOverride.remove(r.row);
        }
      }
    }
    // 켠 변형이 바뀌면 타일의 내용도 바뀐다 — 자료집 조합 · 거르개와 같은 길로 판 번호를 갈아 옛 타일을 가린다.
    final key = variantKeys.join(',');
    if (key != _variantKey) {
      _versionOf[_combinationKey] = version;
      _variantKey = key;
      version = _versionOf[_combinationKey] ?? ++_lastVersion;
    }
    _merged.clear();
    _mergedRows.clear();
    _mergedVariant.clear();
    _hiddenByGroup.clear();
    for (final t in tracks) {
      final groups = [...t.groups]..sort((a, b) => a.firstRow != b.firstRow ? a.firstRow.compareTo(b.firstRow) : b.rowCount.compareTo(a.rowCount));
      for (final g in groups) {
        if (g.rowCount <= 0 || _hiddenByGroup.contains(g.firstRow)) continue;
        if (!_view.isGroupFolded(groupKeyOf(t, g))) continue;
        _merged[g.firstRow] = g.firstRow + g.rowCount;
        _mergedRows[g.firstRow] = [for (int r = g.firstRow; r < g.firstRow + g.rowCount; r++) r];
        for (int r = g.firstRow + 1; r < g.firstRow + g.rowCount; r++) {
          _hiddenByGroup.add(r);
        }
      }
    }
    _syncScopeBranches();
    // 트랙에 남은 줄 수(자동 밀도의 글줄 수가 본다): 접힌 민족에 합쳐진 줄과 **켜지 않은 변형의 줄**은 세지 않는다.
    _trackRows = [
      for (final t in tracks)
        [for (int r = t.firstRow; r < t.firstRow + t.rowCount; r++) if (!_hiddenByGroup.contains(r) && !_variantRowsOff.contains(r)) r].length,
    ];
    _syncTrackValues();
  }

  /// 접힌 대범위 가지를 한 줄로 합친다: 가지의 줄들이 **쌓는 차례에서 가장 앞선 줄** 하나로 모이고 나머지는 숨는다
  /// (민족 접기와 같은 길). 가지의 줄 번호는 이어져 있지 않아 민족처럼 `첫 줄 … 첫 줄 + 줄 수`로 가릴 수 없다 — 차례를 보고 정한다.
  void _syncScopeBranches() {
    if (_on.isEmpty) return;
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      List<int>? order;
      for (final g in variantGroups(i)) {
        if (g.rows.isEmpty) continue;
        if (!_view.isGroupFolded(variantGroupKeyOf(i, g.key))) continue;
        order ??= _orderOf(t);
        final inBranch = g.rows.toSet();
        int first = -1, last = -1;
        for (int k = 0; k < order.length; k++) {
          if (!inBranch.contains(order[k])) continue;
          if (first < 0) first = k;
          last = k;
        }
        if (first < 0) continue;
        final head = order[first];
        if (_hiddenByGroup.contains(head) || _merged.containsKey(head)) continue; // 이미 다른 묶음에 합쳐졌다
        final rows = [for (int k = first; k <= last; k++) if (inBranch.contains(order[k])) order[k]];
        _mergedRows[head] = rows;
        _mergedVariant[head] = _variantKeyOfGroup(i, g.key);
        // [mergedGroups]의 범위는 합쳐 놓은 줄에서 시작할 수밖에 없다(열쇠가 그 줄이다) —
        // 그보다 번호가 작은 줄은 여기에 담기지 않는다. 가지의 줄을 훑는 곳은 [mergedRows]를 읽는다.
        var end = head + 1;
        for (final r in rows) {
          if (r == head) continue;
          _hiddenByGroup.add(r);
          if (r + 1 > end) end = r + 1;
        }
        _merged[head] = end;
      }
    }
  }

  /// 그 묶음을 만든 변형의 열쇠(`scope:<uid>`) — 묶음의 `key`(`__scope:<uid>`)로 찾는다.
  String _variantKeyOfGroup(int trackIndex, String key) {
    for (final v in _on) {
      if (v.track != tracks[trackIndex].id) continue;
      for (final g in v.groups) {
        if (g.key == key) return v.key;
      }
    }
    return '';
  }

  /// 조감의 대범위 여백(계약 3-1절 끝 · 지금 연표의 `_scopePad`가 `_G()`를 쓰는 것과 같게).
  ///
  /// 저장소의 `scope_pad`는 '조감이 아닌' 값 하나뿐이다. 그 값은 **발 6과 머리 16(본국 줄에 매달린 머리는
  /// `16 + 2 − 8 − 14` = −4)의 합**으로만 나오므로, 그렇게 갈라 조감의 값(발 4 · 머리 12 · 매달린 머리
  /// `12 + 2 − 6 − 6` = 2)으로 다시 잇는다. 한 줄에 발은 많아야 하나이고(앞 가지가 끝난 자리) 머리는 여럿일 수 있다.
  /// 갈라지지 않는 값은 건드리지 않는다.
  ///
  /// 조감이 아닐 때는 **그릇 폴더**(리메이크 조각 ③)의 머리 [G.folderHead] · 발 [G.folderFoot]으로 다시 잇는다. 폴더는 늘 제 어깨 탭이 있어
  /// 본국 줄에 매달리지 않으므로 매달린 머리(−4)도 온 머리로 센다.
  ///
  /// 가르는 쪽(머리 수 · 발 · 매달린 머리)은 엔진 답 [split]이 준다(한 벌 P3-18) — 여기서는 보기의 자를 곱해 px로만 되돌린다. [split]이 null이면
  /// 갈라지지 않는 값이라 [stored]를 그대로 쓴다.
  double _scopePadOf(double stored, ScopeSplit? split) {
    final g = metrics;
    if (split == null) return stored;
    if (!g.isBird) return split.foot * G.folderFoot + (split.head + split.hung) * G.folderHead;
    return split.foot * g.scopeFoot + split.head * g.scopeHead + split.hung * (g.scopeHead + 2 - g.gap - g.groupGap);
  }

  /// 그 줄이 트랙 값(기간 막대 단 수 · 기관 칸)의 셈에 드는가 — 접힌 민족에 합쳐진 줄(합쳐 놓은 한 줄까지)과
  /// 켜지 않은 변형의 줄은 빠진다. **빈 줄 접기로 접힌 줄은 그대로 든다**(지금 연표도 `_foldRows` 전에 셈한다).
  bool _countsForTrack(int row) => !_hiddenByGroup.contains(row) && !_merged.containsKey(row) && !_variantRowsOff.contains(row);

  /// 트랙 값을 보이는 줄들의 최댓값으로 다시 셈한다(계약 3절 끝 · 명세 05의 5.2절).
  /// 줄마다의 값이 실리지 않은 옛 저장소에서는 트랙에 적힌 값 하나를 그대로 쓴다 — 그때의 답은 예전과 바이트까지 같다.
  void _syncTrackValues() {
    _trackRail = [];
    _trackOrgan = [];
    for (final t in tracks) {
      int rail = 2;
      bool organ = false, known = false;
      for (int r = t.firstRow; r < t.firstRow + t.rowCount && r < _specs.length; r++) {
        final spec = _specs[r];
        if (spec == null || spec.rail < 0 || !_countsForTrack(r)) continue;
        known = true;
        if (spec.rail > rail) rail = spec.rail;
        if (spec.organ) organ = true;
      }
      _trackRail.add(known ? rail : t.railLevels);
      _trackOrgan.add(known ? organ : t.organ);
    }
  }

  /// 지금 보이는 줄들로 셈한 그 트랙의 기간 막대 단 수(2~3)와 기관 칸의 있고 없음.
  int railLevelsOf(int trackIndex) => _trackRail[trackIndex];
  bool organOf(int trackIndex) => _trackOrgan[trackIndex];

  /// 줄을 위에서부터 다시 쌓는다. [instant]면 흐르지 않고 바로 새 자리로 간다.
  /// [cause]는 무엇이 다시 쌓게 했는가 — 그리는 쪽의 연출이 읽는다([StackCause]).
  void _stack({bool instant = false, StackCause cause = StackCause.none, ViewConditions? from, LayoutSnapshot? bridge}) {
    stackVersion++;
    _cause = cause;
    _fromConditions = from ?? _conditions;
    final next = _build();
    if (_stacked) {
      if (bridge != null) {
        _flow.retargetFrom(_bridge(bridge, next), next, instant: instant || reduceMotion);
      } else {
        _flow.retarget(next, instant: instant || reduceMotion);
      }
      return;
    }
    _stacked = true;
    _flow = RowFlow(next);
  }

  // ---- 저장소를 다시 지었을 때(DLC 더하기 · 빼기 · 판 올리기): 뼈대를 제자리에서 바꾸고 옛 자리에서 흐른다 ----

  /// 트랙을 옛 뼈대와 짝짓는 열쇠 — 글자 id가 있으면 그것, 없으면(옛 저장소) DLC 열쇠 + 이름.
  String trackIdentity(int index) {
    final t = tracks[index];
    if (t.key.isNotEmpty) return 'k:${t.key}';
    String pack = '#${t.pack}';
    for (final p in packs) {
      if (p.id == t.pack) pack = p.key.isNotEmpty ? p.key : '#${p.name}';
    }
    return 'n:$pack|${t.name}';
  }

  /// 바꾸기 직전의 **지금 보이는** 자리(흐르는 도중이면 그 순간의 값)를 적어 둔다 — [replaceWith]의 다리가 읽는다.
  LayoutSnapshot snapshot() => LayoutSnapshot._(
    [for (int i = 0; i < tracks.length; i++) trackIdentity(i)],
    [for (int i = 0; i < tracks.length; i++) trackTop(i)],
    [for (int i = 0; i < tracks.length; i++) trackHeight(i)],
    [for (final t in tracks) t.firstRow],
    [for (final t in tracks) t.rowCount],
    [for (int r = 0; r < rowCount; r++) rowTop(r)],
    [for (int r = 0; r < rowCount; r++) isVisible(r) ? geo(r).height : 0.0],
    [for (int r = 0; r < rowCount; r++) isVisible(r)],
    [for (int r = 0; r < rowCount; r++) geo(r)],
    totalHeight,
  );

  /// 옛 자리([old])를 **이 뼈대의 줄 번호 공간**으로 옮겨 적은 출발 자리. 트랙은 [trackIdentity]로, 트랙 안 줄은 차례(ord)로 짝을 짓는다.
  /// 짝이 없는 줄 — 새 트랙 · 옛 뼈대에서 꺼져 있던 트랙 · 늘어난 줄 · 옛 뼈대에서 안 보이던 줄 — 은 새 자리에서 높이 0으로 출발한다(자라난다).
  /// 옛 뼈대에만 있던 줄(줄어든 줄 · 사라진 트랙)은 여기 자리가 없어 트랙 높이의 흐름에 흡수된다 — 사라지는 트랙은 부르는 쪽이 먼저 끄는 흐름으로 접는다.
  RowStack _bridge(LayoutSnapshot old, RowStack next) {
    final rows = _fixed.length;
    final tops = List<double>.of(next.tops), heights = List<double>.filled(rows, 0);
    final live = List<bool>.filled(rows, false);
    final geos = List<RowGeo>.of(next.geos);
    final trackTop = List<double>.of(next.trackTop), trackHeight = List<double>.filled(tracks.length, 0);
    final at = <String, int>{for (int j = 0; j < old.identity.length; j++) old.identity[j]: j};
    for (int i = 0; i < tracks.length; i++) {
      final j = at[trackIdentity(i)];
      if (j == null || old.trackTop[j] < 0) continue;
      trackTop[i] = old.trackTop[j];
      trackHeight[i] = old.trackHeight[j];
      final t = tracks[i];
      final shared = t.rowCount < old.rowCount[j] ? t.rowCount : old.rowCount[j];
      for (int o = 0; o < shared; o++) {
        final r = t.firstRow + o, or = old.firstRow[j] + o;
        if (or >= old.live.length || !old.live[or]) continue;
        tops[r] = old.rowTop[or];
        heights[r] = old.rowHeight[or];
        geos[r] = old.geos[or];
        live[r] = true;
      }
    }
    return RowStack(
      tops: tops, heights: heights, geos: geos, live: live, visible: [for (int r = 0; r < rows; r++) if (live[r]) r],
      trackTop: trackTop, trackHeight: trackHeight, total: old.total,
    );
  }

  /// 저장소를 다시 지어 뼈대가 통째로 바뀌었다. **제자리에서** 바꾼다 — 부품 · 층 · 다리가 쥔 이 객체가 그대로이게(목록을 비우고 채운다).
  /// [enabled]는 새 번호로 옮겨 적은 켠 DLC(없으면 모두 켠다), [view]는 새 번호로 옮겨 적은 보기 상태, [from]은 바꾸기 직전의 자리([snapshot]) —
  /// 있으면 옛 자리에서 새 자리로 360ms 흐른다. 판 번호는 새로 매긴다(옛 판 번호의 타일은 어떤 조합과도 섞이지 않는다).
  void replaceWith(SceneLayout fresh, {Set<int>? enabled, ViewState view = ViewState.none, LayoutSnapshot? from}) {
    packs
      ..clear()
      ..addAll(fresh.packs);
    tracks
      ..clear()
      ..addAll(fresh.tracks);
    epochs
      ..clear()
      ..addAll(fresh.epochs);
    categories
      ..clear()
      ..addAll(fresh.categories);
    axis
      ..clear()
      ..addAll(fresh.axis);
    variants
      ..clear()
      ..addAll(fresh.variants);
    spheres
      ..clear()
      ..addAll(fresh.spheres);
    sphereLines
      ..clear()
      ..addAll(fresh.sphereLines);
    _recountSpheres();
    _fixed
      ..clear()
      ..addAll(fresh._fixed);
    _specs
      ..clear()
      ..addAll(fresh._specs);
    _rowTrack
      ..clear()
      ..addAll(fresh._rowTrack);
    _enabled = enabled ?? {for (final p in packs) p.id};
    _view = view;
    _folded = const {};
    _versionOf.clear();
    version = ++_lastVersion;
    _visibleSplitOf = null;
    _visibleSplit = const [];
    _syncView();
    _stack(cause: StackCause.packs, bridge: from);
  }

  bool _stacked = false;

  /// 이번 다시 쌓기를 일으킨 것과, 흐르기 **전**의 보기 조건(잔상이 옛 모습으로 남게 — `_squash`).
  StackCause _cause = StackCause.none;
  ViewConditions _fromConditions = const ViewConditions();

  RowStack _build() {
    final rows = _fixed.length;
    // 접힌 줄도 자리를 갖는다(높이 0) — 그 자리에서 접히고 펴지게. 보이는가는 live로 따로 적는다.
    final tops = List<double>.filled(rows, 0), heights = List<double>.filled(rows, 0);
    final live = List<bool>.filled(rows, false);
    final visible = <int>[];
    final trackTop = List<double>.filled(tracks.length, -1), trackHeight = List<double>.filled(tracks.length, 0);
    if (!detailed) {
      final geos = List<RowGeo>.of(_fixed);
      double y = 0;
      for (int i = 0; i < tracks.length; i++) {
        final t = tracks[i];
        if (!_enabled.contains(t.pack)) continue;
        trackTop[i] = y;
        for (int r = t.firstRow; r < t.firstRow + t.rowCount; r++) {
          tops[r] = y;
          heights[r] = _fixed[r].height;
          live[r] = true;
          visible.add(r);
          y += _fixed[r].height;
        }
        trackHeight[i] = y - trackTop[i];
      }
      return RowStack(tops: tops, heights: heights, geos: geos, live: live, visible: visible, trackTop: trackTop, trackHeight: trackHeight, total: y);
    }
    final geos = List<RowGeo>.of(_fixed);
    final g = metrics;
    double y = 0;
    // 쌓는 트랙의 차례: 켠 판의 판 트랙이 맨 위(지금 연표의 _boardPlan — tracks.unshift), 그다음 트랙 차례 그대로.
    // 켜지 않은 판 트랙은 끈 트랙처럼 자리가 없다(판을 켜지 않으면 차례 · 자리가 예전과 같다).
    final order = _boardTracks.isEmpty
        ? null
        : <int>[if (_boardIndex >= 0) _boardIndex, for (int i = 0; i < tracks.length; i++) if (!_boardTracks.contains(i)) i];
    // 문화권(리메이크 조각 ②): 문화권이 바뀌는 트랙 앞에 머리 단(20)을 두고, 펼친 문화권은 4 아래부터 트랙을 쌓는다. 문화권 사이 6.
    // 접힌 문화권의 트랙은 높이 0으로 머리 단 + 24 자리에 숨는다(첫 트랙의 위 − 24 = 머리 단의 위 — 흐르는 동안에도 같은 셈).
    // 모델이 트랙을 문화권 차례로 세워 두었으므로 한 문화권의 트랙은 이어 온다. 문화권 밖 트랙(판 트랙 · 옛 저장소)은 머리 단 없이 그대로.
    final firsts = List<int>.filled(spheres.length, -1);
    int sphereNow = -1;
    double hiddenAt = 0;
    for (int k = 0; k < (order?.length ?? tracks.length); k++) {
      final i = order == null ? k : order[k];
      final t = tracks[i];
      if (!_enabled.contains(t.pack) || _view.isTrackOff(t.id)) continue;
      final s = i < _sphereOfTrack.length ? _sphereOfTrack[i] : -1;
      if (s != sphereNow) {
        if (sphereNow >= 0) y += G.sphereBetween;
        sphereNow = s;
        if (s >= 0 && firsts[s] < 0) {
          firsts[s] = i;
          hiddenAt = y + G.sphereHead + G.sphereGap;
          y += G.sphereHead + (_view.isSphereFolded(spheres[s].id) ? 0 : G.sphereGap);
        }
      }
      if (s >= 0 && _view.isSphereFolded(spheres[s].id)) {
        // 접힌 문화권의 트랙: 높이 0 · 줄은 모두 안 보인다(머리 단 안의 꼬리표가 대신한다 — paint/minibars.dart).
        trackTop[i] = hiddenAt;
        for (int r = t.firstRow; r < t.firstRow + t.rowCount; r++) {
          tops[r] = hiddenAt;
        }
        continue;
      }
      // 트랙끼리는 틈 없이 이어 쌓인다 — 트랙 높이가 아래 1px 테를 품은 값이다(지금 연표의 `_modelTops`: total += tr.height).
      trackTop[i] = y;
      if (isTrackFolded(t.id)) {
        // 접힌 트랙: 머리글 하나 높이로 굳고 줄은 모두 안 보인다(가는 막대만 그린다).
        trackHeight[i] = g.folded;
        for (int r = t.firstRow; r < t.firstRow + t.rowCount; r++) {
          tops[r] = y;
        }
        y += g.folded;
        continue;
      }
      double at = y + g.pad;
      int last = -1;
      final rows = _trackRows[i];
      final rowOrder = _orderOf(t);
      // 켠 그릇의 머리 · 발(리메이크 2부 포개짐): 그 그릇의 첫 보이는 줄 위에 머리, 마지막 보이는 줄 다음에 발 — 바깥 · 안쪽이 같은 줄이면 쌓인다.
      final headAt = <int, double>{}, footAfter = <int, double>{};
      for (final sc in _scopesOn) {
        if (sc.track != i || _scopeHidden(sc)) continue;
        int f = -1, l = -1;
        for (final r in rowOrder) {
          if (!sc.rows.contains(r) || !_stackedRow(r)) continue;
          if (f < 0) f = r;
          l = r;
        }
        if (f < 0) continue;
        headAt[f] = (headAt[f] ?? 0) + _scopeHeadOf(sc);
        footAfter[l] = (footAfter[l] ?? 0) + _scopeFootOf(sc);
      }
      for (final r in rowOrder) {
        if (_folded.contains(r) || _hiddenByGroup.contains(r) || _variantRowsOff.contains(r)) {
          // 접힌 줄 · 접힌 민족에 합쳐진 줄: 틈 0 · 높이 0. 자리는 지금 y — 그 자리에서 접히고 펴진다.
          tops[r] = at;
          continue;
        }
        final spec = _specs[r]!;
        final over = _stackOverride[r];
        final merged = _merged.containsKey(r);
        // 숨은 줄을 건너서도 민족이 바뀌는 곳은 띄운다. 접힌 묶음 안에 숨은 민족 경계는 세지 않는다.
        bool crosses = over?.groupStart ?? false;
        for (int k = last < 0 ? t.firstRow : last + 1; k <= r; k++) {
          if (k >= _specs.length || _specs[k] == null) continue;
          if (_specs[k]!.groupStart && !_hiddenByGroup.contains(k) && !_variantRowsOff.contains(k)) crosses = true;
        }
        final tab = merged || spec.kind == RowKind.foldedGroup || spec.kind == RowKind.common ? 0.0 : g.tab + _lift(r, spec);
        final pad = (_scopeOverride.contains(r) ? 0.0 : (over != null ? _scopePadOf(over.scopePad, over.scopeSplit) : _scopePadOf(spec.scopePad, spec.scopeSplit))) + (headAt[r] ?? 0) + (last >= 0 ? (footAfter[last] ?? 0) : 0);
        final gap = (last < 0 ? 0.0 : (spec.kind == RowKind.member && !crosses ? g.memberGap : g.gap + (crosses ? g.groupGap : 0))) + tab + pad;
        final geo = merged ? _foldedGroupRow(gap) : _bandOf(i, t, spec, gap, rows, hangOpen: _view.openHangs.contains(r));
        geos[r] = geo;
        tops[r] = at;
        heights[r] = geo.height;
        live[r] = true;
        visible.add(r);
        at += geo.height;
        last = r;
      }
      if (last >= 0) at += footAfter[last] ?? 0; // 트랙 끝에서 끝난 그릇의 발
      final height = at + g.pad - y;
      trackHeight[i] = height < g.folded ? g.folded : height;
      y += trackHeight[i];
    }
    _sphereFirst = firsts;
    return RowStack(tops: tops, heights: heights, geos: geos, live: live, visible: visible, trackTop: trackTop, trackHeight: trackHeight, total: y);
  }

  // ---- 문화권(리메이크 조각 ② · 설계 4-6 #1 A · #5 B) ----

  /// 트랙(목록 자리)의 문화권 자리(문화권 밖이면 −1).
  int sphereIndexOfTrack(int trackIndex) => trackIndex >= 0 && trackIndex < _sphereOfTrack.length ? _sphereOfTrack[trackIndex] : -1;

  bool isSphereFolded(String id) => _view.isSphereFolded(id);

  /// 그 트랙이 접힌 문화권 안에 있어 보이지 않는가(왼쪽 칸 · 가는 막대가 건너뛴다).
  bool isTrackHidden(int trackIndex) {
    final s = sphereIndexOfTrack(trackIndex);
    return s >= 0 && _view.isSphereFolded(spheres[s].id);
  }

  /// 문화권 머리 단의 위(몸통 y — 흐르는 값). 이번 보기에 그 문화권의 트랙이 하나도 없으면(꺼짐 · 자료집 끔) −1.
  double sphereHeadTop(int sphere) {
    final first = sphere >= 0 && sphere < _sphereFirst.length ? _sphereFirst[sphere] : -1;
    if (first < 0) return -1;
    final top = trackTop(first);
    return top < 0 ? -1 : top - G.sphereHead - G.sphereGap;
  }

  /// 문화권 하나를 접거나 편다. 바뀌면 참.
  bool foldSphere(String id, bool on) => setViewState(_view.withSphereFolded(id, on));

  /// 처음 접힘(설계 4-6 #1 A — 기억이 없을 때): 자료의 default(없으면 첫 문화권) 하나만 펴고 나머지 문화권은 접는다.
  /// 문화권이 하나뿐이면 아무것도 접지 않는다.
  ViewState withDefaultSpheres(ViewState from) {
    if (spheres.length < 2) return from;
    final open = spheres.firstWhere((x) => x.isDefault, orElse: () => spheres.first).id;
    return from.copyWith(foldedSpheres: {for (final x in spheres) if (x.id != open) x.id});
  }

  /// 그 트랙의 줄을 쌓을 차례 — 켠 변형이 `after`로 옮겨 둔 것을 따라 이어 붙인 사슬이다(계약 3-2절).
  /// 변형이 없으면 트랙 안 차례 그대로이고, 닿지 못한 줄(고리)은 뒤에 붙여 한 줄도 잃지 않는다.
  List<int> _orderOf(TrackInfo t) => _gathered(t, _chainOf(t));

  /// 켠 그릇의 줄은 한 덩이(리메이크 2부 포개짐 · 바깥부터): 떨어져 있으면 첫 줄 자리에 모은다(서로의 차례 그대로).
  List<int> _gathered(TrackInfo t, List<int> order) {
    if (_scopesOn.isEmpty) return order;
    final ti = tracks.indexOf(t);
    final mine = [for (final s in _scopesOn) if (s.track == ti) s]..sort((a, b) => a.depth.compareTo(b.depth));
    for (final s in mine) {
      final at = order.indexWhere(s.rows.contains);
      if (at < 0) continue;
      final before = [for (int k = 0; k < at; k++) order[k]];
      final inside = [for (final r in order) if (s.rows.contains(r)) r];
      final after = [for (int k = at; k < order.length; k++) if (!s.rows.contains(order[k])) order[k]];
      order = [...before, ...inside, ...after];
    }
    return order;
  }

  List<int> _chainOf(TrackInfo t) {
    final last = t.firstRow + t.rowCount;
    if (_stackOverride.isEmpty) return [for (int r = t.firstRow; r < last; r++) r];
    final next = <int, List<int>>{};
    for (int r = t.firstRow; r < last; r++) {
      if (_variantRowsOff.contains(r)) continue;
      final over = _stackOverride[r];
      final anchor = over?.after ?? (r == t.firstRow ? -1 : r - 1);
      (next[anchor] ??= <int>[]).add(r);
    }
    for (final kids in next.values) {
      if (kids.length > 1) {
        kids.sort((a, b) {
          final oa = _stackOverride[a]?.ord ?? 0, ob = _stackOverride[b]?.ord ?? 0;
          return oa != ob ? oa.compareTo(ob) : a.compareTo(b);
        });
      }
    }
    final order = <int>[];
    final seen = <int>{};
    final stack = <int>[...?next[-1]];
    while (stack.isNotEmpty) {
      final r = stack.removeLast();
      if (!seen.add(r)) continue;
      order.add(r);
      final kids = next[r];
      if (kids != null) {
        for (int i = kids.length - 1; i >= 0; i--) {
          stack.add(kids[i]);
        }
      }
    }
    if (order.length < next.values.fold<int>(0, (n, kids) => n + kids.length)) {
      for (int r = t.firstRow; r < last; r++) {
        if (!_variantRowsOff.contains(r) && !seen.contains(r)) order.add(r);
      }
    }
    return order;
  }

  /// 접힌 민족 줄: 높이 30(조감 14)뿐이고 안에는 가는 막대만 든다. 책갈피 탭도 띠 아래 덧단도 없다.
  RowGeo _foldedGroupRow(double gap) {
    final h = metrics.foldedGroup;
    return RowGeo(height: gap + h, bandTop: gap, bandHeight: h, dynastyTop: -1, leaderTop: -1, cabinetTop: -1, textTop: gap, textLines: 0, railTop: -1, organTop: -1, railLevels: 0, lineH: h);
  }

  /// 조감: 줄은 띠 하나뿐이다 — 모든 칸 · 글줄 · 막대 · 인물 · 덧단의 높이가 0이고, 글줄 하나가 띠 전체다
  /// (네모 · 승계선이 닿는 높이 = 띠의 세로 가운데 — 명세 05 7.2).
  RowGeo _birdRow(double gap) {
    final h = metrics.bird!.bandHeight;
    return RowGeo(
      height: gap + h, bandTop: gap, bandHeight: h, dynastyTop: -1, leaderTop: -1, cabinetTop: -1,
      textTop: gap, textLines: 1, lineH: h, railTop: -1, organTop: -1, railLevels: 0,
    );
  }

  /// 띠 안의 단을 위에서부터 쌓는다 — 두 장 꼬리표(감독 결정 '두 장 ㄴ' · 계약 3절 머리 상자): **이름 색줄** 14 → 몸통 띠 =
  /// **칸 층**(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관이 14씩 맞붙음) → **흰 사건 칸** 18 × 글줄(늘) → 기간 막대 → 인물 단(넉넉하게).
  /// 지금 연표의 geoFor(칸 단이 글줄 위)와는 다른 식이다 — 웹 계산은 그대로 두고 쌓는 식은 이 앱이 가진다.
  /// [gap]은 줄 위의 틈(줄의 몫의 맨 위), [rows]는 그 트랙에 남은 줄 수(자동 밀도의 글줄 수가 본다 — 민족을 접으면 줄어든다).
  /// 기간 막대 단 수 · 기관 칸도 트랙에 적힌 값이 아니라 **보이는 줄들로 다시 셈한 값**을 쓴다([_syncTrackValues]).
  /// [hangOpen]이 거짓이면 그 줄의 매달린 속국 이름표를 접어 두었다(띠 아래 덧단에서 그 줄들의 몫이 빠진다).
  RowGeo _bandOf(int trackIndex, TrackInfo t, RowSpec spec, double gap, int rows, {bool hangOpen = true}) {
    final c = _conditions;
    // 리메이크 2부(목업 서고 — 꼬리표는 머리 24에 이름 · 사건 점과 이름뿐): 기간 막대는 '넉넉하게'에서만, 그 줄에 막대가 있을 때만(줄 값 — 옛 저장소는 트랙 값).
    final rails = c.density < 0;
    final railLevels = !rails ? 0 : (spec.rail >= 0 ? spec.rail : _trackRail[trackIndex]), organ = _trackOrgan[trackIndex];
    if (c.bird) return _birdRow(gap);
    if (spec.kind == RowKind.foldedGroup) return _foldedGroupRow(gap);
    final dense = c.density > 0;
    // 두 장 꼬리표(감독 결정 '두 장 ㄴ'): 이름 색줄 14 → 몸통 띠(칸 뭉치 14씩 → 흰 사건 칸 18 → 기간 막대 · 인물).
    // 감독 2026-10-15 "맨 위 국가 색 띠는 얇게 고정 · 지도자 등 가운데는 있으면 추가 · 아래 사건 부분은 항상 남겨둠" — 사건 칸은 늘 둔다
    // (글줄 하나 · 넉넉하게만 둘 · 분류별 글줄이면 그 수). 글줄이 하나면 사건의 해 글도 없다(label_batch). RowSpec.events는 참고로만 남는다.
    final lines = c.density < 0 ? (spec.cats.length >= 2 ? spec.cats.length : 2) : 1;
    double y = gap + G.head;
    final bodyTop = y;
    // 칸 뭉치: 차례대로 14씩 맞붙는다(층마다 윗선 1px — 몸통 띠는 paint/bands.dart · 칸은 paint/strips.dart).
    double dynastyTop = -1, phaseTop = -1, rankTop = -1, powerTop = -1, realTop = -1, leaderTop = -1, cabinetTop = -1, depTop = -1, organTop = -1;
    // 왕조 · 지도자 · 내각 층은 그 줄에 칸이 있을 때만(줄 값이 실린 저장소 — 리메이크 2부 · 목업 서고), 아니면 트랙 값.
    final hasDynasty = spec.cellRows ? spec.dynasty : t.dynasty, hasLeader = spec.cellRows ? spec.leader : t.leader, hasCabinet = spec.cellRows ? spec.cabinet : t.cabinet;
    if (hasDynasty && c.dynasties) {
      dynastyTop = y;
      y += G.floor;
    }
    final phases = c.phases && !dense ? spec.phase : 0;
    if (phases > 0) {
      phaseTop = y;
      y += phases * G.floor;
    }
    if (spec.rank && c.ranks && !dense) {
      rankTop = y;
      y += G.floor;
    }
    // 단체 단(집권 · 실권): 지위 층 아래 · 지도자 층 위, 그 줄에 있을 때만(웹 geoFor의 pw · rl — 빽빽하게 · 표시 끔이면 없음).
    // 두 장 꼬리표에서는 칸 층이 없는 꼬리표도 몸통의 첫 단으로 둔다(고려 = 색줄 + 무신 정권 단 — 빽빽하게만 색줄에 밑줄 + 이름, paint/strips.dart `_inlinePower`).
    if (spec.power && c.groups && !dense) {
      powerTop = y;
      y += G.floor;
    }
    if (spec.real && c.groups && !dense) {
      realTop = y;
      y += G.floor;
    }
    if ((hasLeader && c.leaders) || _lensSlotOf(t)) {
      leaderTop = y;
      y += G.floor;
    }
    if (hasCabinet && c.cabinets) {
      cabinetTop = y;
      y += G.floor;
    }
    if (spec.depHeight > 0) {
      depTop = y;
      y += spec.depHeight;
    }
    if (organ) {
      organTop = y;
      y += G.floor;
    }
    final floorEnd = y;
    // 흰 사건 칸: 글줄마다 18 — 사건 점 · 이름이 그 가운데(paint/events.dart가 textTop · lineH로 놓는다).
    final textTop = y;
    y += lines * G.evLine;
    final railTop = rails ? y : -1.0; // 막대를 그리지 않는 보기에서는 자리도 없다(paint/rails.dart가 −1이면 건너뜀)
    y += railLevels * G.railPitch;
    // 인물 단: '넉넉하게'에서만 3단(목업에 인물 막대가 없다).
    final figMax = !c.figures || c.density >= 0 ? 0 : 3;
    final figWanted = c.density < 0 ? spec.figWide : spec.fig;
    final figs = figWanted < figMax ? figWanted : figMax;
    double figTop = -1;
    if (figs > 0) {
      figTop = y + G.slotGap;
      y = figTop + figs * G.figure + (figs - 1) * G.figGap + G.slotGap;
    } else if (railLevels > 0) {
      y += G.slotGap; // 막대가 몸통 아랫변에 닿지 않게
    }
    final bandHeight = y - gap;
    // 띠 아래 덧단: 매달린 속국 이름표 줄(한 줄 13 — 접었으면 0) → 구역 탭 줄(한 줄 23) → 3px → 바탕 문화 이름 단(웹의 rowCut과 같은 식).
    // 매단 속국 꼬리표는 몸통 아래 실로(G.hangDepthOf — 감독 결정 '두 장 ㄴ'), 구역 탭은 그 뒤에 23씩 + 3.
    final hl = hangOpen ? spec.hang : 0, zl = spec.zones - spec.hang;
    final lanes = G.hangDepthOf(hl) + (zl > 0 ? zl * (G.zoneTab + G.zoneGap) + 3 : 0.0);
    final cut = lanes + (spec.hem ? G.hem : 0.0);
    final bandBottom = gap + bandHeight;
    return RowGeo(
      height: bandBottom + cut, bandTop: gap, bandHeight: bandHeight, dynastyTop: dynastyTop, leaderTop: leaderTop, cabinetTop: cabinetTop, textTop: textTop, textLines: lines,
      railTop: railTop, organTop: organTop, phaseTop: phaseTop, phaseLanes: phases, rankTop: rankTop, powerTop: powerTop, realTop: realTop, railLevels: railLevels, figTop: figTop, figLevels: figs,
      depTop: depTop, depHeight: spec.depHeight, zoneTop: spec.zones > 0 ? bandBottom : -1, zoneLanes: spec.zones, hangLanes: spec.hang, hangOpen: hangOpen,
      hemTop: spec.hem ? bandBottom + lanes : -1, lineH: G.evLine, bodyTop: bodyTop, floorEnd: floorEnd,
    );
  }

  /// 몸통의 세로 자리 y에 있는 줄. 위아래로 벗어나면 첫 줄 · 마지막 줄, 보이는 줄이 없으면 -1.
  int rowAt(double y) {
    final rows = _flow.visible;
    if (rows.isEmpty) return -1;
    int lo = 0, hi = rows.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_flow.topOf(rows[mid]) <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return rows[lo];
  }

  /// 화면 세로 [top] ~ [bottom]에 걸친 보이는 줄의 **번호 범위**(가장 작은 번호 · 가장 큰 번호 — 없으면 (−1, −1)).
  /// 타일의 줄 묶음 · 이름 자리 셈이 이 범위의 번호로 고른다. 쌓인 차례가 번호 차례이면 지금처럼 (위 끝 줄, 아래 끝 줄)이다 —
  /// 집합 보기(판 줄이 번호가 가장 큰데 맨 위)나 그릇 변형(켠 그릇의 줄을 트랙 맨 위로 모음 — 리메이크 2부)이 차례를 바꾸면 그 사이를 모두 본다.
  (int, int) rowRange(double top, double bottom) {
    final first = rowAt(top), last = rowAt(bottom);
    if (first < 0 || _inOrder) return (first, last);
    final rows = _flow.visible;
    int lo = first, hi = first;
    var on = false;
    for (final r in rows) {
      if (r == first) on = true;
      if (!on) continue;
      if (r < lo) lo = r;
      if (r > hi) hi = r;
      if (r == last) break;
    }
    return (lo, hi);
  }

  /// [first]부터 쌓인 차례대로 보이는 줄 — 차례가 번호 차례이면 [visibleRows]`(first, rowCount − 1)`과 같다.
  /// 집합 보기 · 그릇 변형이 차례를 바꾸면 번호로 자를 수 없어(판 줄 · 모은 그릇 줄이 위인데 번호는 크다) 쌓인 차례에서 [first]부터 끝까지.
  Iterable<int> visibleRowsFrom(int first) sync* {
    if (_inOrder) {
      yield* visibleRows(first, rowCount - 1);
      return;
    }
    var on = false;
    for (final r in _flow.visible) {
      if (r == first) on = true;
      if (on) yield r;
    }
  }

  /// [first]부터 [last]까지(포함) 보이는 줄 번호 — 쌓인 차례대로. 변형(소속 펼치기 · 대범위)이 줄을 옮겨 쌓으면 번호가 차례대로가 아니므로 끝까지 본다.
  Iterable<int> visibleRows(int first, int last) sync* {
    for (final r in _flow.visible) {
      if (r >= first && r <= last) yield r;
    }
  }

  /// 그 트랙의 보이는 줄(쌓인 차례대로). 장면마다 트랙마다 묻는 층(왼쪽 칸)이 보이는 줄 전부를 되풀이해 훑지 않게, 쌓을 때마다 한 번만 나눠 둔다.
  List<int> visibleRowsOfTrack(int trackIndex) {
    final all = _flow.visible;
    if (!identical(all, _visibleSplitOf)) {
      _visibleSplitOf = all;
      _visibleSplit = [for (int i = 0; i < tracks.length; i++) <int>[]];
      for (final r in all) {
        _visibleSplit[_rowTrack[r]].add(r);
      }
    }
    return _visibleSplit[trackIndex];
  }

  List<int>? _visibleSplitOf;
  List<List<int>> _visibleSplit = const [];

  /// 보이는 줄의 쌓인 차례가 번호 차례인가(쌓을 때마다 한 번 셈).
  bool get _inOrder {
    final all = _flow.visible;
    if (!identical(all, _inOrderOf)) {
      _inOrderOf = all;
      _inOrderIs = true;
      for (int k = 1; k < all.length; k++) {
        if (all[k] < all[k - 1]) {
          _inOrderIs = false;
          break;
        }
      }
    }
    return _inOrderIs;
  }

  List<int>? _inOrderOf;
  bool _inOrderIs = true;
}
