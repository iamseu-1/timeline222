import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../band_form.dart';
import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../layout.dart';
import '../lens_titles.dart';
import '../marks.dart';
import '../reserved.dart';
import '../scene.dart' show DrawTile;
import '../schema4_items.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import 'context.dart';
import 'ink.dart';
import 'look.dart';
import 'paint_pick.dart';
import 'patterns.dart';
import 'scopes.dart' show FlagLook, ScopeLook;
import 'strips.dart' show StripLayer;

part 'lid_tags.dart'; // 그릇 노릇 객체의 납작한 뚜껑(과제 8 걸음 1 · 스위치 lid)

/// 최대로 줄였을 때도 띠가 보이는 가장 좁은 폭(px) — 감독 2026-09-22 "최대한 줄여도 아예 사라지는 느낌 없애줘".
const _minBandPx = 6.0;

// 정권 띠와 책갈피 탭. 값은 모두 지금 연표(css/common.css · js/timeline.js)에서 옮겼다 —
// 근거는 docs/명세-3단계/01-띠의-표현.md의 1 · 2 · 4 · 5 · 6절, 값의 뜻은 docs/계약-아카이브-3단계.md 6-1절과 6-4절의 구역 19.
// 고르기 · 흐림 · 기간 조명은 명세 06의 3절, 조감(밀도 넷째 단계)은 명세 05의 7절이다.
//
// 띠 하나에 drawRRect · drawPath · clipRect를 한 번도 부르지 않는다(2단계의 병목 넷 가운데 하나였다):
//   · 채움 · 테두리의 곧은 변 · 옅은 끝 · 겹줄 · 깃대 · 탭의 필름은 c.quads(네모 묶음)에,
//   · 둥근 모서리(채움 사분원 · 1px 호 · 연맹의 고리 · 탭 모서리 밑의 조각)는 이 층의 그림판 [BandSprites]에,
//   · 빗금 · 세로 줄 · 점무늬는 c.patterns에, 글자는 c.later에 모아 한 번씩 내보낸다.
// 타일 경계에 걸친 띠는 조각마다 그리되 이음매에는 모서리도 세로 테두리도 두지 않고, 점선 · 무늬의 자리는
// 띠의 진짜 왼쪽 끝(조각을 가로질러 beginFrame이 모은 값)에서 재 두 조각이 하나로 이어져 보인다.
//
// 밝기(고르기 · 흐림 · 조명)는 saveLayer를 쓰지 않는다 — 항목마다 색의 알파에 곱해 같은 묶음에 넣는다([_Fade]가 그 곱셈을 맡는다).
// 이 층은 장면마다 묶음을 처음부터 다시 모으므로 `emphasis.version`이 올라도 따로 버릴 기억이 없고,
// `emphasis.active`(흐르는 중)에는 장면마다 값이 달라져도 그대로 이어진다.
// 띠 칠은 아래의 연도 세로줄을 가리는 종이다(리메이크 4단계 세로줄 얹기 — paint/grounds.dart): 알파가 1보다 작은 칠(흐린 띠 · 녹아드는 끝 ·
// 바탕 문화 · 꼬리표 몸통)은 그 자리 바탕색과 미리 섞은 불투명 색으로 칠한다([_fill]의 paper). 바탕 문화는 뒤 판의 맨 앞([paintUnder])에 깔고 바탕 칸으로 등록한다.

/// 띠 종류 번호(계약 6-1절 — 지금 연표의 KIND_ORDER + 시대와 별개인 종류).
abstract final class BandKind {
  static const state = 0, tributary = 1, fief = 2, dominion = 3, warlord = 4, vassal = 5, protectorate = 6;
  static const satellite = 7, puppet = 8, mandate = 9, colony = 10, occupied = 11, federation = 12;
  static const org = 13, era = 14, exile = 15, movement = 16, culture = 17, overlay = 18, dynasty = 19;

  /// 시대마다의 특별한 형태(묶음 3 · 3번 — 2026-09-22): 복속 세력 · 부용 · 기미 · 번부 · 토사 · 직할령 · 군현(모두 종속 갈래).
  static const client = 20, frontier = 21, prefecture = 22;
}

/// 띠의 `look` 비트(계약 6-1절).
abstract final class BandLook {
  static const kindMask = 0x1f;
  static const certShift = 5, certMask = 3;
  static const hasRange = 1 << 7;
  static const hsShift = 8, hsMask = 7;
  static const famDep = 1 << 11, flagPole = 1 << 12, exile = 1 << 13;
  static const under = 1 << 14, underHead = 1 << 15, folded = 1 << 16, member = 1 << 17, hollow = 1 << 18;

  /// 연대의 확실성 — 0 확실 · 1 통설 · 2 추정 · 3 전승.
  static const certCertain = 0, certAccepted = 1, certEstimated = 2, certLegend = 3;

  /// 실재성 — 0 실재 · 1 반전설 · 2 전설 · 3 논쟁 · 4 부정.
  static const hsAttested = 0, hsSemi = 1, hsLegendary = 2, hsDisputed = 3, hsRefuted = 4;

  static int kindOf(int look) => look & kindMask;
  static int certOf(int look) => (look >> certShift) & certMask;
  static int hsOf(int look) => (look >> hsShift) & hsMask;
}

/// 테두리를 긋는 법: 1px 실선 · 파선(3 긋고 2 띄움) · 점선(1 긋고 1 띄움) — 기준 그림의 픽셀에서 잰 값이다.
enum EdgeStroke {
  solid(0, 0),
  dashed(3, 2),
  dotted(1, 1);

  const EdgeStroke(this.dash, this.gap);
  final double dash, gap;
}

/// 꼬리표의 왼쪽 끝 꼴(설계 4-1 '실제 띠에 입힘' — 갈래 E · 감독 2026-10-15). 오른쪽 끝은 늘 직각이다.
/// 다스림 = 왼쪽 두 귀 모따기 · 영토 밖 = 둥근 끝 · 무리 = 직각 · 테 없음. 띠의 form(형식 4 종류)이 있으면 그 종류 갈래로,
/// 없으면 옛 종류로 짐작한다([TagLook.endOfBand] — 감독 고름 G6 가 · 2026-10-25).
enum TagEnd { cham, key, plain }

/// 꼬리표의 자리 값(설계 4-1 '구멍과 꼬리 마름모' · '실제 띠에 입힘' — 목업 `.claude/research/stage2/mock/themes/t-e.js`).
abstract final class TagLook {
  /// 다스림의 귀 모따기 · 영토 밖 둥근 끝의 반지름 — 꼬리표 키 52(목업 서고의 꼬리표)까지의 값. 그보다 큰 꼬리표는 키에 맞춰 커진다([cornerOf]).
  static const cham = 5.0, keyRadius = 12.0;

  /// 구멍(가운데): 왼쪽 끝에서 7(영토 밖은 둥근 끝에 테가 닿아 9) · 윗변에서 7(두 장 꼬리표의 이름 색줄 14의 세로 가운데 — 감독 결정 '두 장 ㄴ') ·
  /// 반지름 2.5 + 테 1. 이름은 구멍 가운데에서 7 오른쪽.
  static const holeX = 7.0, holeXKey = 9.0, holeY = 7.0, holeR = 2.5, nameGap = 7.0;

  /// 꼬리 마름모(가운데): 오른쪽 끝에서 7 · 구멍 높이 · 반 대각선 3. 머리의 이름 · 딱지는 오른쪽 끝에서 [nameRight] 앞까지
  /// (마름모가 없는 꼬리표도 같은 자리를 비운다 — 이어짐은 관계선 층이 알기 때문).
  static const diamondX = 7.0, diamondHalf = 3.0, nameRight = 15.0;

  /// 구멍 가운데에서 머리 줄의 글이 비켜 설 거리 — 관계선 층이 단추에 비우는 반너비와 같다(구멍 반지름 2.5 + 테 1 + 1.5 · links.dart `_plan`).
  static const markClear = 5.0;

  /// 탭 글의 안 여백 13(서고 미리보기 `TAG.pad` — 어깨 7 + 안 여백 6): 미리보기는 머리의 탭 자리를 이름 왼쪽 − 13에서 [TabPlan.width]만큼 잡고
  /// 그 끝 + [Look.tabGap]에 뒤 글(빌린 줄의 출처 글)을 잇는다 — 앱도 같은 자리에 둔다([BandLayer.borrowLook]).
  static const namePad = 13.0;

  /// 상국 탭 · 연합의 겹 탭(띠 위 받침 카드 위에 솟는 낮은 탭 — 목업 hostTab): 높이 12 · 왼쪽 위 모따기 4 · 글 8.5.
  static const tabH = 12.0, tabCham = 4.0;

  /// 두 장 꼬리표(감독 결정 '두 장 ㄴ')의 몸통 아랫변 — 줄 몫 안 y. 펼친 꼬리표는 늘 색줄 + (있으면 칸 층) + 사건 칸(감독 2026-10-15 "국가 색 띠와 사건 띠는 항상").
  /// 사건 칸은 그 띠의 마지막 칸 층 바로 밑에(칸이 없으면 색줄 바로 밑에) 붙는다 — 몸통 아랫변은 띠 아랫변에서 그만큼([eventLift]) 올라간다.
  /// 옛 저장소([oldStore] — 줄 값 없음) · 몸통이 없는 줄(조감 · 접힘)은 띠 아랫변. [loose](넉넉하게 — 기간 막대 · 인물 단이 줄 몫)는 올리지 않는다.
  /// [sub]는 그 띠의 sub 비트(셈 다섯이 함께 나름 — [compactOf]).
  static double bodyBottom(RowGeo geo, int look, {required bool oldStore, bool loose = false, required int sub}) {
    final b = geo.bandTop + geo.bandHeight;
    if (geo.bodyTop < 0 || oldStore) return b;
    return b - eventLift(geo, look, oldStore: oldStore, loose: loose, sub: sub);
  }

  /// 그 띠가 가진 칸 층의 아랫변(줄 몫 안 y) — 띠 look 비트 21~29(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관)와 30(직위 줄 더 — [floorBitsOf])이 가리키는 층 가운데
  /// 맨 아래 것(줄의 칸 뭉치는 그 줄의 띠들이 나눠 쓰므로 — 고려는 무신 정권 단까지). 칸이 없는 띠는 몸통 윗변, 비트가 없는 띠(칸 종류를 싣지 않은 내보내기)는 줄의 칸 뭉치 끝.
  /// 꼬리표 밑 사슬로 뺀 왕조 · 지위(비트 21 · 23 — 감독 고름 G5 #9 나)는 칸 층으로 세지 않는다 — 그 둘만 가진 띠는 몸통 윗변([compactOf]).
  /// 띠마다 제 몸통 높이(칸 그림 갈래 걸음 5 · 스위치 `body`): 줄어든 줄([RowGeo.shrunk])은 칸 층을 모두 쌓은 끝([RowGeo.stackEnd])을 맞붙여 셈한다 —
  /// 그 줄 띠들 가운데 가장 긴 몸통이 줄의 칸 뭉치 아랫변([RowGeo.floorEnd])에 닿고 나머지는 그 위다(사건 칸 올림 [eventLift] ≥ 0).
  static double floorEndOf(RowGeo geo, int look, {required int sub}) {
    if (look & (1 << 20) == 0) return geo.bodyTop;
    if (floorBitsOf(look) == 0) return geo.floorEnd;
    return compactOf(geo, look, geo.stackEnd, sub: sub);
  }

  /// 띠 look의 칸 층 비트(21 ~ 29 — 왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관)와 30(직위 줄 더 — G7 가 · 계약 1-1 덧붙임)을
  /// 0부터 센 비트로(비트 k = look 21 + k). 직위 줄 더는 스위치 `office`가 켜진 동안만 본다 — 끄면 0x1ff 가림 그대로라
  /// 직위 줄 더만 가진 띠도 예전처럼 '칸 종류 비트 없음'으로 읽힌다(끈 찍기가 앞 걸음과 바이트 같게).
  static int floorBitsOf(int look) => (look >> 21) & (PaintPick.office ? 0x3ff : 0x1ff);

  /// [floorBitsOf]에서 직위 줄 더 층의 비트(look 30).
  static const officeFloorBit = 9;

  /// 줄의 칸 뭉치(층 차례: 왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관)에서 그 띠가 갖지 않은 층을 빼고 맞붙인 자리 —
  /// 줄 몫 y [y](줄의 층 자리)를 그 띠의 몸통 안 자리로 옮긴다(위에 있는 남의 층 높이만큼 올림). 칸 종류 비트가 없는 띠 · 몸통 없는 줄은 그대로.
  /// 띠마다 제 몸통(고려 = 무신 정권 단 · 조선 = 지도자 · 내각 단)이 되게 칸 층(paint/strips.dart) · 층 사이 금 · 동군연합 이음줄이 함께 쓴다.
  /// 꼬리표 밑 사슬([RowGeo.chainTop] — 왕조 · 지위)은 몸통 밖의 단이라 칸 층으로 세지 않고, 사슬 안의 자리는 그대로 둔다(띠마다의 자리는 [chainYOf]).
  /// 줄어든 줄([RowGeo.shrunk])도 칸 층 자리(쌓은 끝 [RowGeo.stackEnd]까지)는 늘 사슬 단 위라(layout.dart `_bandOf`의 사슬 묶음) 이 가름이 그대로 맞다.
  ///
  /// 셈 다섯([bodyBottom] · [floorEndOf] · [compactOf] · [eventLift] · [chainYOf])의 이름 인자 [sub] — 그 띠의 sub 비트(타일 띠 구역 열 9 · 계약 6-1).
  /// 배치 갈래(4단계 · 계약 1-1 덧붙임)가 17 ~ 21에 그 띠의 직위 줄 더 수 · 22 ~ 23에 지도자 층 단 수 − 1을 실었다(schema4_items.dart
  /// `Schema4.officeMoreOf` · `leaderLanesOf`). 0은 직위 줄 더 없음 · 지도자 한 단이다. **기본값 없이 꼭 넘긴다** — 같은 바탕에서 갈라진 갈래가 sub를 모르고
  /// 새로 쓴 부름(두 장 꼬리표 상자 `_tagBox` · 세로줄 덮개의 몸통 아랫변 따위)이 합칠 때 조용히 0(한 단 · 직위 줄 더 없음)으로 셈하지 않고 컴파일에서 걸리게.
  /// 띠 번호로 sub를 찾는 길은 [BandLayer.floorYOf] · [BandLayer.bodyBottomOf] · [BandLayer.eventLiftOf]다.
  /// 지도자 두 단(칸 그림 갈래 걸음 2 · 정통성 넷 가 다듬은 꼴): 줄의 지도자 층은 줄 단 수([RowGeo.leaderLanes]) × 14이고, 띠는 제 단 수(sub 22 ~ 23 + 1 —
  /// 줄 단 수를 넘지 않음)만 맞붙인다 — 지도자 층 아래 자리는 (줄 단 − 제 단) × 14만큼 올리고, 지도자 칸이 없는 띠는 줄의 지도자 층 전체만큼 올린다.
  /// 줄이 한 단이면(옛 저장소 · 렌즈 · 변형이 새로 만든 줄 · 스위치 `legit` 끔) 예전 셈 그대로다.
  /// 직위 줄 더(칸 그림 갈래 걸음 4 · G7 가 · 스위치 `office`): 줄의 직위 줄 더 층은 줄의 수([RowGeo.officeLanes]) × 14(내각 다음 · 예속 앞)이고, look 30이 선 띠는
  /// 제 수(sub 17 ~ 21 — 줄의 수를 넘지 않음)만 맞붙인다 — 지도자 두 단과 같은 꼴로 층 아래 자리를 (줄 수 − 제 수) × 14만큼 올리고, look 30이 없는 띠는
  /// 층 전체만큼 올린다(서고 미리보기 `_bandGeo`의 officeTop 갈래). 층 안의 제 줄 자리(줄 k = 층 윗변 + 14k)는 위 층을 뺀 만큼만 옮긴다.
  static double compactOf(RowGeo geo, int look, double y, {required int sub}) {
    if (geo.bodyTop < 0 || look & (1 << 20) == 0) return y;
    final bits = floorBitsOf(look);
    if (bits == 0) return y;
    if (geo.chainTop >= 0 && y >= geo.chainTop - .5) return y;
    var out = y;
    void skip(int bit, double top, double h) {
      if (top >= 0 && top < y - .5 && bits & (1 << bit) == 0) out -= h;
    }

    if (!geo.dynastyChained) skip(0, geo.dynastyTop, G.floor);
    skip(1, geo.phaseTop, geo.phaseLanes * G.floor);
    if (!geo.rankChained) skip(2, geo.rankTop, G.floor);
    skip(3, geo.powerTop, G.floor);
    skip(4, geo.realTop, G.floor);
    skip(5, geo.leaderTop, geo.leaderLanes * G.floor);
    // 제 지도자 단이 줄 단보다 적은 띠: 지도자 층 아래 자리는 남는 단만큼 올린다(층 안의 제 단 자리는 그대로).
    final rowLanes = geo.leaderLanes;
    if (rowLanes > 1 && bits & (1 << 5) != 0 && geo.leaderTop >= 0 && y >= geo.leaderTop + rowLanes * G.floor - .5) {
      out -= (rowLanes - math.min(Schema4.leaderLanesOf(sub), rowLanes)) * G.floor;
    }
    skip(6, geo.cabinetTop, G.floor);
    // 직위 줄 더 층(줄마다 14): look 30이 없는 띠는 층 전체 · 있는 띠는 제 수만 맞붙이고 남는 줄만큼 층 아래 자리를 올린다(지도자 두 단과 같은 꼴).
    final rowOffices = geo.officeLanes;
    if (geo.officeTop >= 0 && rowOffices > 0) {
      skip(officeFloorBit, geo.officeTop, rowOffices * G.floor);
      if (bits & (1 << officeFloorBit) != 0 && y >= geo.officeTop + rowOffices * G.floor - .5) {
        out -= (rowOffices - math.min(Schema4.officeMoreOf(sub), rowOffices)) * G.floor;
      }
    }
    skip(7, geo.depTop, geo.depHeight);
    skip(8, geo.organTop, G.floor);
    return out;
  }

  /// 두 장 꼬리표에서 사건이 있는 띠의 사건 칸을 제 마지막 칸 층(없으면 색줄) 바로 밑으로 올리는 몫(줄 몫 px · 0이면 그대로) — 목업 f-u처럼 꼬리표마다 제 몸통.
  /// 줄의 칸 뭉치 가운데 그 띠에 없는 아래 층은 같은 줄 다른 띠의 몫이다. 사건 점 · 이름 · 묶음 · 누름 · 고른 고리가 모두 이 값만큼 올라간다
  /// (paint/events.dart · overlay.dart · hit_test.dart — [BandLayer.eventLiftOf]). 꼬리표 밑 사슬의 왕조 · 지위는 칸 층이 아니라 올림에 들지 않는다([floorEndOf]).
  /// 줄어든 줄([RowGeo.shrunk])은 줄인 칸 뭉치 아랫변에서 잰다 — 가장 긴 몸통의 띠는 0.
  static double eventLift(RowGeo geo, int look, {required bool oldStore, required bool loose, required int sub}) {
    if (geo.bodyTop < 0 || oldStore || loose) return 0;
    return geo.floorEnd - floorEndOf(geo, look, sub: sub);
  }

  /// 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나 · 차례 걸음 14) 안의 줄 자리 [y]([RowGeo.strip] 0 · 5 — 줄의 띠 아랫변 밑 사슬 단)를 그 띠의
  /// **꼬리표 바로 밑**으로 옮긴다(고르기 판 `g-g5-9b.js`의 below — 사슬은 띠마다 제 꼬리표 아랫변에서 틈 3): 사건 칸을 올린 몫([eventLift] — 남의 칸 층만큼
  /// 짧은 꼬리표)만큼 올리고, 그 띠에 없는 위 사슬(지위 사슬 위의 왕조 사슬)만큼 더 올린다. 줄의 사슬 단 자리는 줄 높이의 몫으로 남는다(가장 긴 꼬리표의 밑).
  /// 사슬 밖의 자리 · 칸 종류 비트가 없는 띠의 맞붙이기는 그대로(옛 저장소 [oldStore] · 넉넉하게 [loose]는 올림이 0).
  static double chainYOf(RowGeo geo, int look, double y, {required bool oldStore, required bool loose, required int sub}) {
    if (geo.chainTop < 0 || y < geo.chainTop - .5) return y;
    var out = y - eventLift(geo, look, oldStore: oldStore, loose: loose, sub: sub);
    final bits = floorBitsOf(look);
    if (!oldStore && look & (1 << 20) != 0 && bits != 0 && geo.dynastyChained && geo.dynastyTop < y - .5 && bits & 1 == 0) out -= G.chainPitch;
    return out;
  }

  /// 옛 종류(look)로 짐작한 꼬리표 끝 — 복속 세력(무리) = 직각 · 부흥 · 저항 세력(영토 밖) = 둥근 끝, 나머지(옛 조직체 · 군벌 포함 — G6 가) = 모따기.
  static TagEnd endOf(int look) => switch (BandLook.kindOf(look)) {
    BandKind.client => TagEnd.plain,
    BandKind.movement => TagEnd.key,
    _ => TagEnd.cham,
  };

  /// form 종류 번호([BandForm.types]의 차례 — 내보내기 bands.mjs TYPE_NO)의 갈래 끝: 다스림 0 ~ [formRulingLast](국가 · 연방 · 제후국 · 도시 · 정부 ·
  /// 실권 정권 · 속령 · 군벌) · 영토 밖 ~ [formOfflandLast](단체 · 교단 · 기사단 · 회사 · 직위) · 무리 [formFolk](집단). 그 뒤 14 ~ 17은 그릇(시대 · 영역 ·
  /// 동군연합 · 동맹) · 18은 사람이다(js/core.js `HT.F4` TYPES의 group — ruling · offland · folk · container · person).
  static const formRulingLast = 7, formOfflandLast = 12, formFolk = 13;

  /// 정통성 '대립'의 번호([BandForm.legits]의 차례 — `HT.F4` STATUSES).
  static const formRival = 1;

  /// 띠의 꼬리표 왼쪽 끝 꼴 — 감독 고름 G6 가(2026-10-25 · 계획 정한 것 #2): form이 있으면 **종류 갈래**로(다스림 = 모따기 · 영토 밖 = 둥근 끝 ·
  /// 무리 = 직각). 그릇 · 사람 · 모름(form 0 — 옛 저장소 · 객체가 아닌 그림 띠)은 옛 짐작 [endOf] 그대로(옛 조직체 · 군벌 모두 모따기 —
  /// 칠의 옅기만 옛 look대로). 그릇의 제 꼴(설계 4-6 #6 A '납작한 뚜껑' — 과제 8 걸음 1 · lid_tags.dart)은 이 끝 꼴을 그대로 두고(구멍 · 관계선) 칠 · 테만 바꾼다.
  /// 스위치 `tag`가 꺼지면(`--paint-off=tag` — 찍기 · 증명 전용) form을 보지 않는다.
  static TagEnd endOfBand(int look, int form) {
    if (!PaintPick.tag || form == 0) return endOf(look);
    final type = BandForm.typeOf(form);
    if (type < 0) return endOf(look);
    if (type <= formRulingLast) return TagEnd.cham;
    if (type <= formOfflandLast) return TagEnd.key;
    if (type == formFolk) return TagEnd.plain;
    return endOf(look);
  }

  /// 정통성 '대립'인 띠인가(form 10 ~ 12비트 — 과제 2 걸음 2 · 설계 4-1 `status`): 꼬리표 테를 파선 [rivalStroke]로 · 머리 이름은 먹 [rivalName].
  /// 다른 정통성(공동 · 섭정 · 명목 · 주장)은 여기서 그리지 않는다(칸 무늬 — 정통성 넷 가는 배치 갈래). 스위치 `tag`가 꺼지면 거짓.
  static bool rivalOf(int form) => PaintPick.tag && BandForm.legitOf(form) == formRival;

  /// 대립 띠의 테 — 파선 3 · 2(고르기 판 `stroke-dasharray: 3 2`). 조직체의 점선 1 · 1보다 이긴다. 직각(무리)은 테가 없는 그대로.
  static const rivalStroke = EdgeStroke.dashed;

  /// 대립 띠의 머리 이름 먹 — 그림판 먹 단계 60(고르기 판 s4 object `o.rival ? k(.6)`). 칠 · 테 빛깔은 look 그대로.
  static const rivalName = CanvasInk.k60;

  /// 키에 따른 귀(감독 2026-10-15 "크기에 따라 모서리 수치를 가변적으로" → 실제 앱 1배 견줌에서 갈래 1): 갈래 E의 실제 띠는 키가 30 ~ 140이라
  /// 고정 모따기 5가 큰 꼬리표에서 보이지 않아 상자처럼 읽혔다. 목업 서고의 비율(키 52에 모따기 5 ≒ 0.1)을 지켜 위아래 두 귀가 함께 커진다 —
  /// 모따기 = 키 × 0.1(5 ~ 12) · 둥근 끝 = 키 × 0.22(12 ~ 24) · 1px로 맞춤. 받침 카드 · 고른 테 · 흰 층의 아래 귀 · 구멍 자리([holeAt])가 같은 값을 쓴다.
  static double cornerOf(TagEnd end, double h) {
    if (end == TagEnd.plain) return 0;
    final v = (end == TagEnd.cham ? (h * .1).clamp(cham, 12.0) : (h * .22).clamp(keyRadius, 24.0)).roundToDouble();
    return math.min(v, h / 2);
  }

  /// 키 [h]인 꼬리표의 구멍 가운데 자리(왼쪽 끝에서) — 위 귀가 커지면 함께 안으로(모따기 귀 + 2 · 둥근 끝 반지름 × 0.6).
  static double holeAt(TagEnd end, double h) {
    final k = cornerOf(end, h);
    return end == TagEnd.key ? math.max(holeXKey, (k * .6).roundToDouble()) : math.max(holeX, k + 2);
  }
}

/// 정통성 넷 가 다듬은 꼴(lg2-ga — 감독 고름 더 · 다듬기 판 `.claude/research/stage4-choose/themes/g-legit2.js`)의 무늬 값 — 칸(paint/strips.dart) ·
/// 띠 머리 · 소속 구간 탭(이 파일)이 함께 쓴다(칸 그림 갈래 걸음 3 · 스위치 `legit`). 상태는 색 없이 먹과 굵기로만(설계 4-4):
/// 섭정 = 피후견 칸 아랫변 안쪽 2px 먹 60 · 명목 = 이름 먹 45 · 주장 = 바탕 1px 화소 빗금 먹 25(이름 둘레는 받침) · 대립 = 파선 테(G6 가 그대로) ·
/// 공동 = 두 단(걸음 2)이 곧 꼴. 소속 구간의 명목 = 탭 글 먹 45 · 탭 테와 이어진 뒤 장 테 먹 25(다듬기 판 '열쇠표 옅게').
abstract final class LegitLook {
  /// 주장의 빗금 — 5px 칸의 1px 화소 계단(왼쪽 아래 → 오른쪽 위 · 보간 없이 1배 화소 격자에 — 다듬기 판 hatch의 5 × 5 무늬).
  static const hatch = PatternSpec.stairs(5);

  /// 빗금의 먹(그림판 먹 단계 25 — 먹 알파로 깔아 밑의 칠이 비친다).
  static const hatchInk = .25;

  /// 섭정 밑줄의 먹(종이 위 고른 회색 60)과 두께.
  static const regentInk = CanvasInk.k60, regentH = 2.0;

  /// 명목의 이름 먹 · 소속 명목 탭의 글 먹(45) · 소속 명목 탭 테 · 뒤 장 테의 먹(25).
  static const nominalName = CanvasInk.k45, nominalLine = CanvasInk.k25;

  /// 빗금을 비우는 받침: 칸 이름 앞뒤 4 · 띠 머리 이름 끝 + 6(구멍 · 이름 둘레는 띠 칠) · 소속 주장 탭 글 앞뒤 1(탭이 글 + 14로 좁다).
  static const namePad = 4.0, headPad = 6.0, tabPad = 1.0;

  /// 빗금이 화면에 붙는 가로 자리: 분 0이 선 화소 열([zeroX] — `c.v.xOf(0)`)을 5로 나눈 나머지(1px 단위). 옆으로 옮기면 무늬가 칸 · 띠와 함께 움직이고,
  /// 이웃 칸 · 단 · 띠의 빗금이 한 무늬로 이어진다(다듬기 판의 `patternUnits: userSpaceOnUse` · x 0과 같은 뜻).
  static double phaseX(double zeroX) => zeroX.roundToDouble() % hatch.period;
}

/// 띠 하나의 색과 선 — 자료(look)만으로 정해지는 순수한 값이라 따로 검사한다.
class BandTone {
  const BandTone(this.fill, this.edge, this.stroke, this.radius, {double? radiusBottom, this.hatch = false, this.hatchColor = 0, this.fog = 0, this.dots = false, this.pole = 0})
    : radiusBottom = radiusBottom ?? radius;

  /// 바탕 · 테두리 색(0xAARRGGBB). 안개 띠(전설 · 반전설)에서는 안개가 쓰는 색이다.
  final int fill, edge;
  final EdgeStroke stroke;

  /// 위 두 모서리의 반지름(문화 12 · 그 밖 10). 미정 쪽 22와 잘린 쪽 0은 자리에 달렸으므로 여기서 정하지 않는다.
  final double radius;

  /// 아래 두 모서리의 반지름 — 바탕 문화만 다르다(`12 12 10 10` · C:879).
  final double radiusBottom;

  /// 전승 연대의 빗금(바탕 대신). [hatchColor]가 줄의 색이고 [fill]이 그 사이의 색이다.
  final bool hatch;
  final int hatchColor;

  /// 안개(전설 · 반전설)의 짙기. 0이면 안개가 아니다.
  final double fog;

  /// 문화 띠 · 바탕 문화의 점무늬.
  final bool dots;

  /// 부흥·저항 세력의 깃대 색(0이면 없음 — 불투명도까지 담은 값).
  final int pole;
}

/// 책갈피 탭에 무엇을 얼마나 적는가 — 지금 연표의 `tabParts`(T:648)를 그대로 옮긴 순수한 셈.
class TabPlan {
  const TabPlan(this.mode, this.width, this.boxWidth, this.name, this.tags, this.tagKinds, this.nameWidth);

  /// 'full' 이름 + 딱지 · 'short' 첫 글자만 · '' 그리지 않음(왼쪽 칸에 이름이 있다).
  final String mode;

  /// `tabParts`가 셈한 폭 — 문턱과 `_tabR`(승계선이 비켜 갈 자리)에 쓴다. 글자를 10.5px로 재서 셈한다.
  final double width;

  /// 실제로 그리는 상자의 폭 — 글자는 10px로 그리므로 [width]와 딱지마다 1px씩 어긋난다(명세 2-2의 '의도된 어긋남').
  final double boxWidth;

  final String name;
  final List<String> tags;

  /// 딱지의 종류: 0 종류 · 1 실재성 · 2 지위.
  final List<int> tagKinds;

  /// 그릴 이름의 폭(10px).
  final double nameWidth;

  static const empty = TabPlan('', 0, 0, '', <String>[], <int>[], 0);
}

/// 탭에서 자리와 무관한 몫 — 이름 · 딱지의 글자 폭과 그것으로 셈한 밑값(글꼴 · 색 · 서열도 타일에 적힌 값에서만 나온다).
/// 타일마다 띠 하나에 한 번만 재고, 장면마다는 남은 폭([room])과 견주는 산수만 한다.
class _TabBase {
  const _TabBase(this.name, this.head, this.tags, this.kinds, this.looks, this.widths, this.nameWidth, this.headWidth, this.base, this.box, this.rkNeed, this.hasRank);
  final String name, head;
  final List<String> tags;
  final List<int> kinds;
  final List<TextLook> looks;
  final List<double> widths;
  final double nameWidth, headWidth, base, box, rkNeed;
  final bool hasRank;
}

/// 칸이 그려진 뒤에 내보낼 테두리 하나.
class _EdgeJob {
  _EdgeJob(this.l, this.t, this.r, this.b, this.radiusL, this.radiusR, this.radiusLB, this.radiusRB, this.fade, this.argb, this.stroke, this.openL, this.openR, this.anchor,
      {this.chamL = false, this.chamR = false, this.rows, this.teeL = true, this.hazeL = 0, this.hazeR = 0, this.hazeArgb = 0});
  final double l, t, r, b, radiusL, radiusR, radiusLB, radiusRB, anchor;
  final _Fade fade;
  final int argb;
  final EdgeStroke stroke;
  final bool openL, openR;

  /// 왼쪽 두 귀가 모따기(꼬리표 갈래 E).
  final bool chamL;

  /// 오른쪽 두 귀도 모따기(뚜껑 꼬리표 — lid_tags.dart).
  final bool chamR;

  /// 파선 · 점선 테가 몸통 안 가로 금과 만나는 줄([BandLayer.innerRows] — 맞닿음일 때만 · 없으면 null)과, 왼쪽에서 그 금이 테 바로 옆에서
  /// 멈추는가(미정 시작 · 열린 쪽은 금이 띠 끝까지라 T자가 없다) — [BandLayer._dashTees].
  final List<double>? rows;
  final bool teeL;

  /// 흐림의 끝 구간 폭(왼쪽 · 오른쪽 — 0이면 없음)과 그 구간 테의 흐린 빛깔([BandLayer._hazeEnds]와 같은 구간 · 끔이면 늘 0).
  final double hazeL, hazeR;
  final int hazeArgb;
}

/// 맞힌 것: 띠 번호 · 그 줄 · 책갈피 탭을 맞혔는가.
class BandHit {
  const BandHit(this.band, this.row, {this.tab = false, this.uid = '', this.coal = false});
  final int band, row;
  final bool tab;

  /// 뒤 장의 탭(속국 띠 위의 상국 탭 — 묶음 3 · 1번)을 맞혔으면 그 상국의 uid. [band]는 상국 띠의 번호(그려지지 않으면 0).
  /// 연합의 겹 탭([coal])이면 그 연합 단체의 uid(누르면 단체 창 · 올리면 구성 나라 모두 진하게 — 감독 선택 D5 결정 3 C + 덧판 x2 A).
  final String uid;
  final bool coal;

  @override
  String toString() => '띠 $band(줄 $row)${tab ? ' 탭' : ''}${uid.isEmpty ? '' : (coal ? ' 연합 $uid' : ' 상국 $uid')}';
}

/// 조감의 띠 안 이름 하나의 자리와 글 — 장면을 열 때 재어 두고 그릴 때 그대로 쓴다.
class _BirdName {
  const _BirdName(this.row, this.l, this.top, this.height, this.width, this.text, this.look, this.refuted);
  final int row;
  final double l, top, height, width;
  final String text;
  final TextLook look;

  /// 부정된 나라의 취소선.
  final bool refuted;
}

/// 꼬리표 머리의 이름 하나(갈래 E) — 장면을 열 때 재어 두고 그릴 때 그대로 쓴다. [plan]이 비면 이름 없이 상국 · 연합 탭만.
class _Head {
  const _Head(this.id, this.row, this.look, this.color, this.rank, this.l, this.top, this.realL, this.realR, this.plan, this.base,
      {this.sticky = false, this.borrow, this.powers = const [], this.rival = false, this.lid = false});
  final int id, row, look, color, rank;

  /// 정통성 '대립'인 띠 — 머리 이름을 먹 60으로([TagLook.rivalName] · G6 가 · 과제 2 걸음 2).
  final bool rival;

  /// 납작한 뚜껑으로 그리는 띠 — 머리 이름을 먹 85로([LidLook.name] · 과제 8 걸음 1 · 대립의 먹 60이 이긴다).
  final bool lid;

  /// 빌린 직위 줄의 출처 글(구역 54 — `· 지도자 ← 출처 · 내각 ← 출처`)과 그 왼쪽 x. 없거나 자리가 모자라면 null.
  final (String, double)? borrow;

  /// 이 띠 머리의 실권 밑줄(구역 56 — 빼앗긴 띠 · 제 안의 실권자). 없으면 빈 목록.
  final List<_PowerMark> powers;

  /// 띠 시작이 화면 밖이라 이름이 화면 왼쪽에 붙어 따라오는가 — 그 자리는 사건 이름 셈의 비켜 갈 구간(분)으로 적지 않고,
  /// 사건 층이 그릴 때 겹치는 첫 글줄의 점 · 이름을 숨긴다([BandLayer.headHides] — 조감의 띠 안 이름과 같은 길).
  final bool sticky;

  /// 이름의 왼쪽(구멍 가운데 + 7, 띠 시작이 화면 밖이면 화면 끝 + 6) · 띠 윗변(화면 y) · 띠의 진짜 두 끝.
  final double l, top, realL, realR;
  final TabPlan plan;

  /// 딱지의 글꼴 · 폭(재어 둔 타일의 몫 — 그리는 타일이 달라도 같은 값). 이름이 없으면 null.
  final _TabBase? base;
}

/// 맞히기용 자리 기록 하나(그린 차례대로 쌓고 거꾸로 훑는다 — 나중에 그린 것이 위다).
class _HitBox {
  const _HitBox(this.l, this.t, this.r, this.b, this.band, this.row, this.tab, {this.uid = '', this.coal = false});
  final double l, t, r, b;
  final int band, row;
  final bool tab;

  /// 뒤 장의 탭이면 그 상국의 uid(상국 띠가 그려지지 않은 자료에서도 상세를 열 수 있게) · 연합의 겹 탭이면 연합 단체의 uid([coal]).
  final String uid;
  final bool coal;
}

/// 한 줄에 놓인 띠 하나의 진짜 두 끝(배치 px · 연대 폭까지)과 미정 끝 — 이웃 띠를 찾아 미정 꼬리를 자를 때 쓴다.
class _RowSpan {
  _RowSpan(this.id);
  final int id;
  double l = double.negativeInfinity, r = double.infinity;
  bool fuzzyL = false, fuzzyR = false;
}

/// 받침 카드 한 장의 자리와 꼴(BandLayer._sheets — 칠 · 테 · 틈과 칠 없는 카드의 뒤 판 종이가 함께 쓴다).
typedef _Sheet = ({int band, _HostSeg s, double l, double t, double r, double b, double l0, double r0, double top, double bottom, double h,
    double bandL, double bandR, TagEnd end, double k, bool roundL, bool roundR, bool joinL, double alpha, bool atL});

/// 뒤 장의 탭(구역 47) 하나 — 장면의 처음에 보이는 타일에서 조각을 모아 합친다(속국 띠 id → 항목 id → 이것).
class _HostSeg {
  _HostSeg(this.k, this.look, this.name, this.color, this.hostBand, this.uid, this.row);
  final int k, look, color, hostBand;
  final String name, uid;

  /// 속국 띠의 줄(뒤 장을 그 띠 뒤에 깐다 — 건의 8의 2번 C).
  final int row;
  double left = double.infinity, right = double.negativeInfinity;
}

/// 이번 장면에 선 탭 하나(상국 탭 · 연합 겹 탭 — [BandLayer._hostSpotsOf] · [BandLayer._coalSpotsOf]가 정함): 그 관계 · 왼쪽 · 폭(연합은 앞 장 폭 —
/// 뒤 장 [BandLayer.coalBackDx]는 따로) · 쓸 글(온 이름 · 첫 글자 — 짧은 관계 · 조사 결함 26). [dot]이면 탭 없이 카드 윗단에 상국 색 점 하나([x]가 점 가운데 · 폭 0).
class _TabSpot {
  const _TabSpot(this.s, this.x, this.w, this.text, this.textW, {this.dot = false});
  final _HostSeg s;
  final double x, w, textW;
  final String text;
  final bool dot;

  /// 온 이름을 다 쓰지 못한 탭(첫 글자 · 점) — 올리면 풍선 글로 상국 이름을 말한다([BandLayer.hostTipAt]).
  bool get short => dot || text != s.name;
}

/// 실권 밑줄(구역 56 — 리메이크 4단계 과제 6) 하나 — 장면의 처음에 보이는 타일에서 조각을 항목 번호로 합친다(빼앗긴 띠 id → 이것들).
/// [start] · [end]는 절대 분(타일 시작 + x0 · x1 — 끝은 끝 분 + 1, 띠 · 칸과 같은 셈). 화면에 실린 타일 밖의 몫은 모른다.
class PowerSpan {
  PowerSpan(this.id, this.row, this.holder, this.color, this.own);
  final int id, row;

  /// 쥔 쪽 이름 · 색(0xRRGGBB — 제 안의 실권자는 0) · 제 안의 실권자인가(구역 56의 a = 1).
  final String holder;
  final int color;
  final bool own;
  double start = double.infinity, end = double.negativeInfinity;

  /// 절대 분 [s] ~ [e](끝은 끝 분 + 1)와 겹치는가 — 미리보기 `ousted`(timeline.js 7416: 칸 끝 > 실권 시작이고 칸 시작 < 실권 끝)처럼
  /// 맞닿기만 하면 겹치지 않는다. 타일의 분은 f32라 넓은 타일에서 몇십 분 어긋나므로 [touch] 아래의 겹침은 맞닿음으로 친다.
  bool overlaps(double s, double e) => math.min(end, e) - math.max(start, s) > touch;

  /// 맞닿음으로 치는 겹침(분 — 반나절). 자료의 날은 하루 단위라 참 겹침은 이보다 길다.
  static const touch = 720.0;
}

/// 그릴 실권 밑줄 하나(장면을 열 때 [BandLayer._placePowers]가 자리를 끝낸다): 밑줄의 두 끝 · 빛깔 · 끝 이름(없으면 null)과 그 왼쪽 · 글꼴.
class _PowerMark {
  const _PowerMark(this.id, this.a, this.b, this.line, this.name, this.nameX, this.look, this.lane);
  final int id;

  /// 단(0 = 예전 자리 · 겹친 실권의 둘째부터 1 · 2 … — [BandLayer.powerY]).
  final int lane;
  final double a, b;
  final int line;
  final String? name;
  final double nameX;
  final TextLook look;
}

/// 띠 하나의 출처 글 몫(타일 구역 54 — [BandLayer._borrowsOf]): 지도자 · 내각 몫([base] — 없으면 빈 글 · 예전 글 그대로)과 그 몫의 (낱말, 출처)([heads]),
/// 직위 줄 더의 빌림(줄 차례 · (줄, 낱말, 출처)). 직위 줄 더 몫은 그릴 때 그 줄에 층이 섰을 때만 잇는다([BandLayer._borrowTextOf]).
class _BorrowText {
  const _BorrowText(this.base, this.heads, this.offices);
  final String base;
  final List<(String, String)> heads;
  final List<(int, String, String)> offices;
}

class BandLayer extends TileLayer {
  final sprites = BandSprites();

  /// 밑 조각: 반투명이던 띠 귀(흐린 띠 · 옅어지는 끝 — 그 자리 바탕색과 섞은 불투명 종이). 그 걸음의 네모 · 무늬보다 먼저 내보낸다([flushUnder]) —
  /// 귀 칸 안의 제 빗금 · 점무늬 · 깃대가 몸통처럼 그 위에 오게(예전 반투명 귀는 그것들이 비쳤다 · 불투명 종이를 나중에 찍으면 네모나게 지운다).
  late final _underSprites = BandSprites(sharing: sprites);

  /// 밝기 상태(총괄이 장면에 넣기 전에는 중립). 층은 장면마다 여기서만 밝기를 묻는다.
  em.Emphasis? emphasis;
  static final em.Emphasis _neutral = em.Emphasis();

  em.Emphasis get _em => emphasis ?? _neutral;

  /// 커서가 올라간 띠(총괄이 [hitBands]의 답으로 채운다). 없으면 장면의 값을 쓴다.
  int? hotBand;

  /// 띠 id → 이어지는 조각까지 합친 진짜 왼쪽 · 오른쪽 끝(배치 px). 타일에 걸친 띠가 하나로 보이게 한다.
  final _joinedLeft = <int, double>{}, _joinedRight = <int, double>{};

  /// 띠 id → 꼬리표의 왼쪽 끝 꼴(갈래 E) — 받침 카드 · 종이 틈이 같은 꼴을 따른다.
  final _endOf = <int, TagEnd>{};

  /// 그 띠의 꼬리표 왼쪽 끝 꼴(이번 장면에 실린 띠 — 없으면 [fallback] · 기본은 다스림의 모따기). 관계선 층이 구멍 자리를 정할 때 ·
  /// 칸 층(strips.dart)이 흰 층의 왼쪽 아래 귀를 깎을 때 묻는다 — form의 종류 갈래([TagLook.endOfBand])를 함께 따른다.
  TagEnd endOf(int band, [TagEnd fallback = TagEnd.cham]) => _endOf[band] ?? fallback;

  /// 머리 줄(이름 색줄)의 덧붙는 글(실권 끝 이름 · 칸 층 없는 꼬리표의 집권 · 실권 이름)이 들 수 있는 가로 끝 — 구멍 · 꼬리 마름모 자리를 비운다
  /// (감독 2026-10-26 수정 5 — 구멍 등이 글을 가리지 않게 · 구멍을 옮기지 않고 글이 비킨다). [realL] · [realR]은 띠의 진짜 두 끝(배치 px).
  /// 왼쪽: 띠의 맨 앞이 화면 안([left] − 1 이상)이면 구멍 가운데 + [TagLook.markClear](구멍이 화면 밖이면 걸지 않음). 미정인 시작의 점선 동그라미는
  /// 띠 끝(확정 해)에 서서 이 끝 안쪽이다. 오른쪽: 띠 끝 − [TagLook.nameRight](머리 이름과 같은 끝 — 마름모가 없는 꼬리표도 같은 자리를 비운다).
  (double, double) headTextBounds(int band, double realL, double realR, double left) => (
    realL >= left - 1 ? realL + TagLook.holeAt(endOf(band), G.head) + TagLook.markClear : double.negativeInfinity,
    realR - TagLook.nameRight,
  );

  /// 띠 id → look(이번 장면에 실린 띠) — 사건 칸을 올리는 몫([eventLiftOf])을 셀 때.
  final _lookOf = <int, int>{};

  /// 띠 id → sub(이번 장면에 실린 띠 — [_lookOf]와 함께 채움). [TagLook]의 셈에 함께 넘긴다([TagLook.compactOf]의 `sub`).
  final _subOf = <int, int>{};

  /// 줄 [row]의 띠 [band]에서 줄의 층 자리 [y]가 그 띠의 몸통 안에서 앉는 자리([TagLook.compactOf]) — 모르는 띠는 그대로.
  double floorYOf(SceneLayout layout, int row, int band, double y) {
    final look = _lookOf[band];
    if (look == null || row < 0 || row >= layout.rowCount || !(layout.spec(row)?.cellRows ?? false)) return y;
    return TagLook.compactOf(layout.geo(row), look, y, sub: _subOf[band] ?? 0);
  }

  /// 줄 [row]의 띠 [band]의 몸통 아랫변(줄 몫 y · [TagLook.bodyBottom]) — 모르는 띠는 띠 아랫변.
  double bodyBottomOf(SceneLayout layout, int row, int band) {
    final geo = layout.geo(row);
    final look = _lookOf[band];
    if (look == null) return geo.bandTop + geo.bandHeight;
    return TagLook.bodyBottom(geo, look, oldStore: !(layout.spec(row)?.cellRows ?? false), loose: layout.conditions.density < 0, sub: _subOf[band] ?? 0);
  }

  /// 줄 [row]에 놓인 띠 [band]의 사건을 올리는 몫(배치 px · [TagLook.eventLift]). 모르는 띠는 0.
  double eventLiftOf(SceneLayout layout, int row, int band) {
    final look = _lookOf[band];
    if (look == null || row < 0 || row >= layout.rowCount) return 0;
    return TagLook.eventLift(layout.geo(row), look,
        oldStore: !(layout.spec(row)?.cellRows ?? false), loose: layout.conditions.density < 0, sub: _subOf[band] ?? 0);
  }

  /// 줄 → 그 줄에 놓인 띠들(왼쪽 끝 차례). 미정 끝의 꼬리(44px)는 띠 밖으로 스며드는데, 줄을 나눌 때는 그 꼬리를 셈하지 않아
  /// (웹 `chainRows` — 앞 띠의 끝 ≤ 뒤 띠의 시작이면 같은 줄) 옆 띠 위에 반투명하게 겹쳐 두 테두리가 함께 보였다(감독 건의 2026-10-14 7번 —
  /// 단군조선의 끝이 위만조선의 앞을 덮음). 꼬리는 이웃 띠의 진짜 끝까지만 — 자리가 모자라면 제 띠 안쪽으로 들어와 옅어진다.
  final _rowSpans = <int, List<_RowSpan>>{};

  /// 이미 탭(또는 조감의 띠 안 이름)을 그린 띠(타일마다 조각이 오므로 한 번만).
  final _tabbed = <int>{};

  /// 꼬리표 머리의 이름 자리(갈래 E): 띠 → 자리. [beginFrame]이 재고, [paintTile]이 그릴 띠를 [_headJobs]에 모으면 [paintEdges]가 그린다.
  final _heads = <int, _Head>{};

  /// 이번 판에 머리를 그릴 띠(띠 칠 뒤 — 테두리 걸음에서 그리고 비운다).
  final _headJobs = <int>[];

  /// 머리 이름(과 딱지)의 오른쪽 끝(px) — 소속 단추가 그 뒤에 앉는다(paint/scopes.dart). 이름이 없으면 이름이 섰을 자리 − 4.
  final headNameEnd = <int, double>{};

  /// 줄 → 머리 이름이 차지한 구간(px · 앞뒤 4 여유) — 대범위 · 속국 접기 단추가 비켜 앉는다(paint/scopes.dart).
  final headNameZones = <int, List<(double, double)>>{};

  /// 줄 → 화면 왼쪽에 붙어 따라오는 머리 이름의 구간(px · 앞뒤 4 여유) — [headHides].
  final _headSticky = <int, List<(double, double)>>{};

  /// 이 장면의 실권 밑줄(구역 56): 빼앗긴 띠 id → 기간들(타일 · 항목 차례). [beginFrame]이 채운다 — 칸 층(strips.dart)이
  /// 같은 장면에 그 기간과 겹치는 지도자 칸을 옅게 한다(띠 층의 beginFrame이 먼저다 — painter.dart `_tileLayers`).
  final powerSpans = <int, List<PowerSpan>>{};

  /// 단체의 실권 단(칸 종류 8 · 단 3 · 단 갈래 5 ~ 7)의 칸 기간 — 줄 → (절대 분 시작, 끝). 실권 밑줄이 있는 장면에서만 모은다.
  final _realCells = <int, List<(double, double)>>{};

  /// 타일마다 한 번 읽어 둔 구역 56(타일의 내용은 바뀌지 않는다).
  static final _powerItems = Expando<List<PowerLine>>('실권 밑줄');

  /// [row]의 첫 글줄에서 [lo]~[hi]가 화면 왼쪽에 붙은 머리 이름에 걸치는가 — 걸치면 사건 층이 그 점 · 이름을 **옮기지 않고 숨긴다**
  /// (조감의 [birdHides]와 같은 길 — 붙은 이름의 자리는 장면마다 바뀌어 이름 자리 셈에 넣지 않는다).
  bool headHides(int row, double lo, double hi) {
    final zones = _headSticky[row];
    if (zones == null) return false;
    for (final z in zones) {
      if (z.$1 < hi && z.$2 > lo) return true;
    }
    return false;
  }

  /// 타일의 끝에 몰아 그릴 띠 테두리 — 칸보다 뒤에 나가야 칸의 테두리를 덮지 않는다.
  final _edges = <_EdgeJob>[];

  /// 바탕 문화의 칠([paintUnder] — 뒤 판)이 남긴 뒷일(테 · 맞히기 · 검사 기록): 타일 → 부른 차례대로의 묶음. 그 타일의 앞 판 [paintTile]이
  /// 맨 앞에서 하나씩 꺼내 한다 — 테는 예전처럼 그 판의 테두리 걸음에서(감싼 타일의 자르기 · 흐림 안), 맞히기는 예전 차례 그대로.
  final _underLater = <Tile, List<List<void Function()>>>{};

  /// 이 타일의 연대 폭(구역 19): 띠 id → 그 띠의 항목 번호들. 타일의 내용은 바뀌지 않으므로 타일마다 한 번만 묶는다
  /// (장면마다 다시 묶으면 항목마다 새 목록을 만들게 된다). 타일이 버려지면 함께 버려지게 [Expando]에 건다.
  static final _zoneIndex = Expando<Map<int, List<int>>>('연대 폭 묶음');
  var _zoneOf = const <int, List<int>>{};

  /// 타일마다의 띠 색 — look · 제 색 · 미정은 타일에 적힌 값이라 장면이 바뀌어도 그대로다(올린 띠만 장면마다 따로 셈한다).
  static final _tones = Expando<List<BandTone?>>('띠의 색');

  /// 타일마다의 탭 밑값(이름 · 딱지의 폭).
  static final _tabBases = Expando<List<_TabBase?>>('탭의 밑값');

  /// 띠와 탭의 자리 기록(맞히기 · 커서 비춤).
  final _hits = <_HitBox>[];

  /// 뒤 장의 탭(구역 47): 속국 띠 id → 항목 id → 조각을 합친 것. 장면마다 [beginFrame]이 다시 모은다.
  final _hostSegs = <int, Map<int, _HostSeg>>{};
  static const sectionHostTab = 47;

  /// 소속 구간의 정통성(구역 58 — 칸 그림 갈래 걸음 3 · 스위치 `legit`): (속국 띠 id · 소속 순번 — 구역 47의 b) → 정통성 번호. 장면마다 [beginFrame]이 다시 모은다.
  final _hostLegit = <(int, int), int>{};

  /// 타일마다 한 번 읽어 둔 구역 58(타일의 내용은 바뀌지 않는다).
  static final _hostLegitBy = Expando<List<HostLegit>>('소속 구간의 정통성');

  /// 띠 자체가 정통성 '주장'인 띠(form 10 ~ 12)의 머리 빗금이 시작하는 x(이름 끝 + [LegitLook.headPad] — [_placeHead]가 정함). 장면마다 다시.
  final _claimFrom = <int, double>{};

  /// 구역 47의 모습 7 = 연합의 겹 탭(내보내기 `export/power.mjs` — 구성 나라 띠마다 가담 한 건에 하나 · text2 = 연합 단체의 uid).
  /// 0 ~ 6은 상국 탭(묶음 3 · 1번)이다.
  static const coalLook = 7;

  /// 연합의 겹 탭: 앞 장의 안 여백 9(웹 TAB.coalPad) · 뒤 장은 4px 오른쪽 · 3px 위(TAB.backDx · backDy). 칠은 앞 장 34% · 뒤 장 18%,
  /// 올리면(같은 연합의 탭 모두) 앞 장 +14% · 뒤 장 30% · 글자는 먹(웹 `.tl-htab.k-coal:is(:hover, .is-coal-on)`).
  static const coalPad = 9.0, coalBackDx = 4.0, coalBackDy = 3.0;

  /// 연합 단체 uid → 이 장면의 타일에서 그 연합의 겹 탭 항목이 걸린 줄들(구성 나라 띠의 줄) — 올림의 조명 · 흐림이 읽는다([coalRows]).
  final _coalRows = <String, Set<int>>{};

  /// 띠 → 이번 장면에 선 상국 탭(들) — [_hostSpotsOf]가 처음 물을 때 정하고 장면 끝까지 그대로(그리기 · 관계선 · 열쇠표 · 실이 같은 자리를 본다).
  final _hostSpots = <int, List<_TabSpot>>{};

  /// 띠 → 이번 장면에 선 연합 겹 탭(들) — 플래그가 놓인 뒤([flagsPlaced]) 처음 물을 때 정한다([_coalSpotsOf]).
  final _coalSpots = <int, List<_TabSpot>>{};

  /// 띠 → 이번 장면 플래그의 오른쪽 끝(px) — 단추 층이 플래그를 놓으며 적는다(scopes.dart `ScopeMarks._placeFlags`). 연합 겹 탭이 그 뒤에 선다(조사 결함 27).
  final flagRight = <int, double>{};

  /// 이번 장면에 단추 층이 플래그를 다 놓았는가([flagRight]가 다 찼는가) — 관계선 층의 길 셈은 그 앞이라 연합 겹 탭 자리를 넉넉히 본다([overTop]).
  bool flagsPlaced = false;

  /// 이 장면에 [uid] 연합의 구성 나라 띠가 놓인 줄(보이는 타일에 그 가담 기간이 걸린 것만 — 보기 범위 밖에서 끝난 가담의 띠는 들지 않는다).
  Set<int> coalRows(String uid) => _coalRows[uid] ?? const {};

  /// 올린 연합(장면의 표시 상태 `SceneMarks.hotCoal`)을 이 장면에 한 번 읽어 둔다.
  String? _hotCoal;

  /// 이 장면에 연합의 겹 탭을 그리는가 — 표시 체크 '단체'(`ViewConditions.groups`). 끄면 탭도 올림도 없다.
  bool _coalOn = true;

  /// 이 장면에 그린 타일들(풍선 글을 지을 때만 다시 훑는다 — 장면마다 띠 이름을 따로 모으지 않으려고 목록만 쥐어 둔다).
  List<DrawTile> _frameDraw = const [];

  /// 연합의 겹 탭에 올렸을 때의 풍선 글(웹 `_coalTabTip` — 띠 위에는 '연합' 딱지를 두지 않고 이 글과 단체 창에만):
  /// "연합 이름 — 연합 · 구성 나라 · 나라 — 누르면 단체 창". 구성 나라는 이 장면의 타일에 가담 기간이 걸린 띠만(위에서 아래로).
  /// 가담 기간 · 역할 · 메모는 타일에 없어 적지 않는다(단체 창에 있다). 그 연합의 탭이 이 장면에 없으면 빈 글.
  String coalTip(String uid) {
    String? name;
    final members = <int, String>{};
    for (final d in _frameDraw) {
      if (d.isCover) continue;
      final t = d.tile, host = t.section(sectionHostTab);
      if (host.count == 0) continue;
      final look = host.u(Tile.itemA), ref = host.u(Tile.itemRef), row = host.u(Tile.itemRow), hname = host.u(Tile.itemName), text2 = host.u(Tile.itemText2);
      for (int i = 0; i < host.count; i++) {
        if (look[i] != coalLook || t.text(text2[i]) != uid) continue;
        name ??= t.text(hname[i]);
        if (members.containsKey(row[i])) continue;
        for (int b = 0; b < t.bandCount; b++) {
          if (t.bandId[b] == ref[i]) {
            members[row[i]] = t.text(t.bandName[b]);
            break;
          }
        }
      }
    }
    if (name == null) return '';
    final rows = members.keys.toList()..sort();
    final list = [for (final r in rows) if (members[r]!.isNotEmpty) members[r]!];
    final made = list.isEmpty ? '' : ' · 구성 ${list.join(' · ')}';
    return '$name — 연합$made — 누르면 단체 창';
  }

  /// 탭 줄의 글자 크기 — 감독 2026-10-13 "모든 글자 위 아래로는 적당한 공간이 있어야 해. 겹쳐보이잖아"와 그 안의 선택 **"글자 한 단계 작게"**(줄 높이는 그대로):
  /// 제 이름 10 → 9 · 상국과 연합 9.5 → 8.5. 통합에서 탭의 안(윗선 아래 ~ 띠 윗변)을 17px로 넓혀 글자 틀의 위아래에 틈이 남는다. 웹의 `.tl-lane .tl-tab` · `.tl-htab`과 같은 값.
  static const tabNameSize = 9.0;

  /// 제 이름 탭의 폭은 반 포인트 큰 글로 잰다(웹 tabParts — 9.5px로 재고 9px로 그린다. 명세 2-2 · 5-3 첫째의 어긋남(예전 10.5 / 10)을 그대로 두어야 자리가 같다).
  static const tabNameUp = 9.5 / tabNameSize;

  /// 뒤 장의 탭 · 연합의 겹 탭의 글자(지금 연표 .tl-htab — 8.5px · 600).
  static const hostLook = TextLook(8.5, ui.FontWeight.w600, Look.ink, spacing: -.1);

  /// 탭 줄의 글줄 윗변 — 글줄(크기 × 1.2)을 탭의 안(윗선 1px 아래 ~ 띠 윗변: [tabTop] + 1 ~ [tabTop] + [G.tab])의 가운데에 둔다.
  static double tabTextTop(double tabTop, double size) => tabTop + 1 + (G.tab - 1 - size * 1.2) / 2;

  /// 낮은 탭(갈래 E — 상국 탭 · 연합 탭)의 글줄 윗변: 탭의 안(윗선 1px 아래 ~ 밑변 [tabTop] + 1 + [TagLook.tabH])의 가운데.
  static double smallTabTextTop(double tabTop, double size) => tabTop + 1 + (TagLook.tabH - size * 1.2) / 2;

  /// 조감의 띠 안 이름이 차지한 구간 — 줄 → [왼쪽 − 3, 오른쪽 + 3](BIRD_NAME.clear 3px).
  /// 사건 층이 이 구간의 점 · 알약을 **옮기지 않고 숨긴다**(명세 05의 7-3).
  ///
  /// 지금 연표의 `tr._bnmZ`와 같은 자리다 — 거기에는 띠 안 이름뿐 아니라 **띠 안 단추**(소속 `▸n` · 대범위)의
  /// 자리도 함께 든다(js:3332 `zones.push([bx − clear, bx + memW + clear])`). 단추의 자리는 단추 층이 아는 값이라,
  /// 단추 층이 제 구간을 이 map에 **더해 주면** [birdClear]가 지금 연표와 같은 답을 낸다.
  ///
  /// **이 값은 [beginFrame]이 채운다**(그리는 때가 아니라). 읽는 층 — 단추 층(paint/scopes.dart의 `ScopeMarks.collect`)과
  /// 관계선 층(paint/links.dart) — 도 제 `beginFrame`에서 읽고 더하므로, 그리개의 `_tileLayers`에서 **띠 층이 그 둘보다 앞**에
  /// 있어야 한다(painter.dart). 뒤에 있으면 읽는 쪽은 지난 장면의 자리를 보고, 더한 구간은 이 층이 곧바로 지워 버린다.
  final birdNameZones = <int, List<(double, double)>>{};

  /// 띠마다 몸통 안 가로 금(색줄 아랫금 · 층 사이 금 · 사건 칸 윗줄)을 그은 화면 줄(정수 · 오름차순 · 겹침 없음 — 띠 id → 줄들). [_paintTwoPiece]가
  /// 이번 장면에 적고 할거기 경계 파선(scopes.dart `ScopeLayer.paintOverBands` — 띠 걸음 뒤)이 읽어 그 줄을 건너뛴다 — 가로 금 · 칸 층 가로선과
  /// 엇갈리는 점에 먹이 두 번 얹히지 않게(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off면 적지 않음). 파선 · 점선 띠 테도 읽어
  /// 그 줄의 T자를 닫는다([_dashTees]). 목록은 장면마다 새로 만들지 않고 [beginFrame]이 비워 다시 쓴다(이번 장면에 없는 띠는 빈 목록).
  final innerRows = <int, List<double>>{};

  /// 지금 [_hLine]이 긋는 것이 몸통 안 가로 금이면 그 띠 id(아니면 −1) — [innerRows]에 적는다.
  int _innerOf = -1;

  /// 조감의 띠 안 이름의 오른쪽 끝 — 띠 id → x. 소속 · 할거 단추가 [birdBtnGap]만큼 띄워 여기에 이어 붙는다(명세 05의 7-4).
  /// 지금 연표의 `bnR`(js:6934)과 같다: 이름이 서면 `이름 왼쪽 + 이름 폭`, 이름이 없으면 `이름이 섰을 자리 − 4`다.
  /// 모양 c(이름 없음) · 띠가 아닌 줄에는 값이 없다 — 그때는 단추도 없다(js:3320 `bnR == null`).
  /// [birdNameZones]와 같이 [beginFrame]이 채운다(차례의 약속도 같다).
  final birdNameEnd = <int, double>{};

  /// 이번 장면에 잰 조감의 띠 안 이름 — 띠 id → 자리와 글. [beginFrame]이 재고 [paintTile]이 그대로 그린다.
  final _birdNames = <int, _BirdName>{};

  /// 이번 장면에 이미 자리를 잰 띠(타일마다 조각이 오므로 한 번만 — 글자 폭이 아직이면 들지 않는다).
  final _birdPlaced = <int>{};

  /// 조감의 띠 안 이름 모양(0 없음 · 1 첫 글자 · 2 온 이름). 더 긴 모양으로 바뀔 때만 8px을 더 요구하는
  /// 문턱 둘(명세 05의 7-3 · 원칙 ⑨)을 위해 장면을 건너 기억한다.
  final _birdMode = <int, int>{};

  /// 이번 장면에 기간 조명 구간을 갈라 칠할 일이 있는가 — 켜져 있거나([em.Look.lit]), 거둔 구간이 아직 옅어지는 중이다.
  /// 띠마다 묻지 않고 장면마다 한 번만 [beginFrame]에서 정한다.
  bool _litFrame = false;

  @override
  void setScale(double scale) => sprites.setScale(scale);

  @override
  void flush(PaintContext c) => sprites.flush(c.canvas);

  @override
  void flushUnder(PaintContext c) => _underSprites.flush(c.canvas);

  /// 조감에서 [row]의 [x] 자리가 띠 안 이름 · 단추를 비켰는가 — 지금 연표의 `birdClear`(js:7454)를 그대로 옮긴 것이다:
  /// 구간과 4px 안에서 스치기만 해도 비킨 것이 아니다(`l < x + 4 && r > x − 4`).
  /// 관계선 층이 조감의 내림줄 · 오름줄을 세울 자리를 고를 때 묻는다(명세 04의 7-2).
  bool birdClear(int row, double x) {
    final zones = birdNameZones[row];
    if (zones == null) return true;
    for (final z in zones) {
      if (z.$1 < x + 4 && z.$2 > x - 4) return false;
    }
    return true;
  }

  /// [row]에서 [lo]~[hi] 상자가 띠 안 이름 · 단추의 자리에 **걸치는가** — 걸치면 사건의 점 · 개수 알약을
  /// 옮기지 않고 숨긴다(명세 05의 7-3 · 지금 연표 `_placeRow`의 `overlaps(zonesB, …)` js:3608 · 3714).
  /// [birdClear]와 달리 4px의 여유를 두지 않는다 — 지금 연표도 점 · 알약에는 상자끼리의 겹침만 본다.
  bool birdHides(int row, double lo, double hi) {
    final zones = birdNameZones[row];
    if (zones == null) return false;
    for (final z in zones) {
      if (z.$1 < hi && z.$2 > lo) return true;
    }
    return false;
  }

  // ── 층 배선 없이 읽는 길 ──
  // 사건 층은 그리개의 배선(`painter.dart`)을 거치지 않고도 이 자리를 알아야 한다(조감의 점 · 알약이 이름을 가리지 않게).
  // 밝기 상태(`Emphasis.of`)와 같은 길로 **장면 곁에** 이 층을 매달아 둔다 — [beginFrame]이 매 장면 다시 적는다.
  static final _byScene = Expando<BandLayer>('띠 층');

  /// 이 장면을 그린 띠 층(아직 한 장면도 그리지 않았으면 null).
  static BandLayer? of(Object scene) => _byScene[scene];

  /// (x, y)에 있는 띠 · 탭. 나중에 그린 것(띠 → 탭 → 바탕 문화)이 이긴다.
  BandHit? hitBands(double x, double y) {
    for (int i = _hits.length - 1; i >= 0; i--) {
      final h = _hits[i];
      if (x >= h.l && x <= h.r && y >= h.t && y <= h.b) return BandHit(h.band, h.row, tab: h.tab, uid: h.uid, coal: h.coal);
    }
    return null;
  }

  @override
  void beginFrame(PaintContext c) {
    _sheetsDone = false;
    // 타일에 걸친 띠의 진짜 두 끝: 왼쪽이 잘리지 않은 조각의 시작과, 가장 오른쪽 조각의 끝을 미리 모은다.
    // 이름 자리 · 점선과 무늬의 시작 자리 · 미정 꼬리의 길이가 모두 띠 전체의 자리에서 나온다.
    _byScene[c.scene] = this;
    _joinedLeft.clear();
    _joinedRight.clear();
    _endOf.clear();
    _rowSpans.clear();
    final spanOf = <int, _RowSpan>{};
    _tabbed.clear();
    _hits.clear();
    _underLater.clear();
    _hostSegs.clear();
    _hostLegit.clear();
    _claimFrom.clear();
    _coalRows.clear();
    _hostSpots.clear();
    _coalSpots.clear();
    flagRight.clear();
    flagsPlaced = false;
    // 표시 체크 '단체'를 끄면 연합의 겹 탭도 없다(웹 `_coalTabPlan`의 `show.groups`) — 탭 · 올림의 조명 · 흐림이 모두 이 값을 본다.
    _coalOn = c.layout.conditions.groups;
    _frameDraw = c.scene.draw;
    _hotCoal = _coalOn ? SceneMarks.of(c.scene).hotCoal : null;
    birdNameZones.clear();
    for (final rows in innerRows.values) {
      rows.clear(); // 목록은 다시 씀(장면마다 띠마다 새 목록을 만들지 않게)
    }
    birdNameEnd.clear();
    _heads.clear();
    _headJobs.clear();
    headNameEnd.clear();
    headNameZones.clear();
    _headSticky.clear();
    _birdNames.clear();
    _birdPlaced.clear();
    powerSpans.clear();
    _realCells.clear();
    _litFrame = _em.look.lit || _em.litMoving;
    final v = c.v;
    final powerById = <int, PowerSpan>{};
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        final id = t.bandId[i], flags = t.bandFlags[i];
        if (flags & Tile.clipLeft == 0) {
          final x0 = v.xOf(origin + t.bandX0[i]);
          if (x0 < (_joinedLeft[id] ?? double.infinity)) _joinedLeft[id] = x0;
        }
        final x1 = v.xOf(origin + t.bandX1[i]);
        if (x1 > (_joinedRight[id] ?? double.negativeInfinity)) _joinedRight[id] = x1;
        _endOf[id] = TagLook.endOfBand(t.bandLook[i], t.bandForm[i]);
        _lookOf[id] = t.bandLook[i];
        _subOf[id] = t.bandSub[i];
        // 바탕 문화(다른 띠와 겹쳐 깔리는 띠) · 접힌 줄의 띠는 이웃이 아니다.
        if (t.bandLook[i] & (BandLook.under | BandLook.folded) == 0) {
          var s = spanOf[id];
          if (s == null) {
            s = spanOf[id] = _RowSpan(id);
            (_rowSpans[t.bandRow[i]] ??= <_RowSpan>[]).add(s);
          }
          if (flags & Tile.clipLeft == 0 && flags & Tile.fuzzyStart != 0) s.fuzzyL = true;
          if (flags & Tile.clipRight == 0 && flags & Tile.fuzzyEnd != 0) s.fuzzyR = true;
        }
      }
      // 뒤 장의 탭(구역 47): 조각을 항목 id로 합친다 — 자리는 탭을 그릴 때 정한다(_paintHostTabs).
      final host = t.section(sectionHostTab);
      if (host.count > 0) {
        final hx0 = host.f(Tile.itemX0), hx1 = host.f(Tile.itemX1);
        final hid = host.u(Tile.itemId), href = host.u(Tile.itemRef), hname = host.u(Tile.itemName), hcolor = host.u(Tile.itemColor);
        final ha = host.u(Tile.itemA), hb = host.u(Tile.itemB), hd = host.u(Tile.itemD), htext = host.u(Tile.itemText2), hrow = host.u(Tile.itemRow);
        for (int i = 0; i < host.count; i++) {
          final byItem = _hostSegs[href[i]] ??= <int, _HostSeg>{};
          final s = byItem[hid[i]] ??= _HostSeg(hb[i], ha[i], t.text(hname[i]), hcolor[i], hd[i], t.text(htext[i]), hrow[i]);
          if (_coalOn && ha[i] == coalLook && s.uid.isNotEmpty) (_coalRows[s.uid] ??= <int>{}).add(hrow[i]);
          final a = v.xOf(origin + hx0[i]), b = v.xOf(origin + hx1[i]);
          if (a < s.left) s.left = a;
          if (b > s.right) s.right = b;
        }
      }
      // 소속 구간의 정통성(구역 58): (속국 띠 · 소속 순번)으로 구역 47의 탭과 짝 — 상국 탭 · 뒤 장의 꼴(_paintHostTabs · paintHostSheets).
      // 시대 그릇 소속의 몫(a 1 — 계약은 아직 싣지 않음)은 탭이 없어 뺀다. 구역이 없는 타일은 빈 목록이라 여기서 끝난다.
      if (PaintPick.legit) {
        for (final h in _hostLegitBy[t] ??= Schema4.hostLegits(t)) {
          if (!h.era && h.legit >= 0) _hostLegit[(h.band, h.seq)] = h.legit;
        }
      }
      // 실권 밑줄(구역 56): 조각을 항목 번호로 합친다 — 자리는 머리를 잴 때(_placePowers).
      for (final p in _powerItems[t] ??= Schema4.powerLines(t)) {
        final s = powerById[p.id] ??= () {
          final made = PowerSpan(p.id, p.row, p.holder, p.color, p.own);
          (powerSpans[p.band] ??= []).add(made);
          return made;
        }();
        if (origin + p.x0 < s.start) s.start = origin + p.x0;
        if (origin + p.x1 > s.end) s.end = origin + p.x1;
      }
      // 띠의 두 끝은 **연대 폭(구역 19)까지 품는다**(명세 1-1의 bandStart · bandEnd) — 탭의 자리도
      // 조감의 띠 안 이름의 들 폭도 그 끝에서 재므로, 띠 몸통과 같은 끝을 여기서 함께 모은다.
      final zones = t.section(19);
      if (zones.count == 0) continue;
      final ref = zones.u(Tile.itemRef), side = zones.u(Tile.itemA), zoneFlags = zones.u(Tile.itemFlags);
      final za = zones.f(Tile.itemX0), zb = zones.f(Tile.itemX1);
      for (int i = 0; i < zones.count; i++) {
        final id = ref[i];
        if (id == 0) continue;
        if (side[i] == 0 && zoneFlags[i] & 1 == 0) {
          final x0 = v.xOf(origin + za[i]);
          if (x0 < (_joinedLeft[id] ?? double.infinity)) _joinedLeft[id] = x0;
        }
        if (side[i] == 1) {
          final x1 = v.xOf(origin + zb[i]);
          if (x1 > (_joinedRight[id] ?? double.negativeInfinity)) _joinedRight[id] = x1;
        }
      }
    }
    for (final s in spanOf.values) {
      s.l = _joinedLeft[s.id] ?? double.negativeInfinity; // 진짜 시작이 보이는 타일에 없으면 화면 왼쪽 밖이다
      s.r = _joinedRight[s.id] ?? double.infinity;
    }
    for (final list in _rowSpans.values) {
      list.sort((a, b) => a.l.compareTo(b.l));
    }
    // 단체의 실권 단 칸 — 실권 밑줄과 같은 기간에 그려지면 밑줄 끝 이름을 뺀다(과제 6 걸음 2). 밑줄이 없는 장면은 칸을 훑지 않는다.
    if (powerSpans.isNotEmpty && c.layout.conditions.groups && !c.layout.bird) {
      for (final d in c.scene.draw) {
        if (d.isCover) continue;
        final t = d.tile;
        final origin = t.origin.toDouble();
        for (int i = 0; i < t.cellCount; i++) {
          if (t.cellKindOf(i) != _realKind || t.cellLane[i] & 0xff != _realLane || (t.cellStyle[i] >> 27) & 7 < _realBandFrom) continue;
          (_realCells[t.cellRow[i]] ??= []).add((origin + t.cellX0[i], origin + t.cellX1[i]));
        }
      }
    }
    // 띠의 두 끝이 다 모인 뒤에 조감의 띠 안 이름의 자리를 잰다(그 자리가 두 끝에서 나온다).
    _placeBirdNames(c);
    _placeHeads(c);
  }

  /// 미정 꼬리가 갈 수 있는 끝: 왼쪽은 앞 띠의 진짜 끝, 오른쪽은 뒤 띠의 진짜 시작까지(둘 다 미정이면 사이의 가운데).
  /// 이웃이 없으면 ±무한. [l] · [r]은 이 띠의 진짜 두 끝(연대 폭까지).
  (double, double) _tailRoom(int row, int id, double l, double r) {
    final list = _rowSpans[row];
    if (list == null || list.length < 2) return (double.negativeInfinity, double.infinity);
    _RowSpan? me;
    for (final s in list) {
      if (s.id == id) {
        me = s;
        break;
      }
    }
    var lo = double.negativeInfinity, hi = double.infinity;
    for (final s in list) {
      if (s.id == id) continue;
      if (s.r <= l + .5 && s.r > lo) lo = s.fuzzyR && (me?.fuzzyL ?? false) ? (s.r + l) / 2 : s.r;
      if (s.l >= r - .5 && s.l < hi) hi = s.fuzzyL && (me?.fuzzyR ?? false) ? (r + s.l) / 2 : s.l;
    }
    return (math.min(lo, l), math.max(hi, r));
  }

  /// 줄 [row]의 띠 [band](윗변 [top] px)의 꼬리표가 칠해진 아랫변(px) — [_paintTwoPiece]의 한 장 아랫변 그대로: 몸통이 있으면 몸통 아랫변
  /// ([bodyBottomOf] — 사건 칸을 남의 칸 층만큼 올린 꼬리표는 줄 몫의 띠 아랫변보다 짧다), 없으면 이름 색줄 아랫변. 몸통 없는 줄은 띠 아랫변.
  /// 받침 카드([paintHostSheets])가 꼬리표의 보이는 몸통에 맞춘다 — 그 아래는 바탕이라 띠 뒤 승계선 · 그릇 칠이 그대로 보인다.
  /// 할거기 칠(scopes.dart `paintOverBands`)도 이 셈 하나를 묻는다.
  double tagBottom(PaintContext c, int row, int band, double top) {
    final layout = c.layout, geo = layout.geo(row), base = layout.rowTop(row);
    final b = top + geo.bandHeight;
    if (geo.bodyTop < 0) return b;
    final stripB = math.min(b, c.v.yOf(base + geo.bodyTop)), bodyB = math.min(b, c.v.yOf(base + bodyBottomOf(layout, row, band)));
    return bodyB > stripB + .5 ? bodyB : stripB;
  }

  /// 바탕 문화(under 띠)의 칠 — 뒤 판의 맨 앞(그릇 칠 바로 뒤 · 사람 띠의 실 · 관계선 · 매단 이름표 · 구역 탭 · 바탕 문화 이름 앞)에서 타일마다
  /// (그리개 `_scopeSteps` · SVG `scopeSteps`). 리메이크 4단계 세로줄 얹기: 칠이 그 자리 바탕색과 섞은 불투명 종이라, 예전 자리(앞 판 — 그것들 위)에
  /// 두면 그것들을 가린다. 칠한 몫은 바탕 칸으로 등록한다(그 위에 얹는 매단 이름표 · 흐린 띠가 이 빛과 섞이게). 점무늬는 칠과 함께 여기서,
  /// 테 · 맞히기 · 검사 기록은 예전 걸음(그 타일의 [paintTile] 맨 앞 — [_underLater])에 그대로 둔다.
  /// 조감에서는 바탕 문화를 그리지 않는다(T:6679 `bird ? [] : tr.underlays`).
  void paintUnder(PaintContext c, Tile t) {
    if (c.hide.contains('bands') || c.layout.bird) return;
    final zones = t.section(19);
    _zoneOf = _zoneIndex[t] ??= _zonesOf(zones);
    final later = <void Function()>[];
    for (int i = 0; i < t.bandCount; i++) {
      if (t.bandLook[i] & BandLook.under != 0) _paintBand(c, t, i, zones, later: later);
    }
    (_underLater[t] ??= <List<void Function()>>[]).add(later);
  }

  @override
  void paintTile(PaintContext c, Tile t) {
    if (c.hide.contains('bands')) return;
    final zones = t.section(19);
    _zoneOf = _zoneIndex[t] ??= _zonesOf(zones);
    // 조감에서는 바탕 문화를 그리지 않고(T:6679 `bird ? [] : tr.underlays`), 탭도 없다 —
    // 이름이 띠 안으로 들어간다(명세 05의 7-2 · G_BIRD.tab = 0).
    final bird = c.layout.bird;
    // 쌓는 차례(명세 4-1절): 바탕 문화 → 책갈피 탭(띠보다 아래 층) → 띠. 바탕 문화의 칠은 뒤 판의 맨 앞([paintUnder])에 이미 깔았고,
    // 여기서는 그 테(띠 테두리 걸음) · 맞히기 · 검사 기록만 예전 차례로 — 같은 타일의 [paintUnder]가 부른 차례대로 하나씩 꺼낸다.
    if (!bird) {
      final queue = _underLater[t];
      if (queue != null && queue.isNotEmpty) {
        for (final job in queue.removeAt(0)) {
          job();
        }
      }
    }
    // 꼬리표의 머리(이름 · 딱지 · 상국 탭 · 연합 탭)는 모든 띠 칠 뒤 — 테두리 걸음([paintEdges])에서 그린다(딱지 바탕 · 취소선이 띠 칠에 묻히지 않고,
    // 맞히기 상자가 띠보다 뒤에 쌓여 먼저 잡히게).
    if (!c.hide.contains('tabs')) {
      for (int i = 0; i < t.bandCount; i++) {
        if (t.bandLook[i] & (BandLook.under | BandLook.folded) != 0) continue;
        if (bird) {
          _paintBirdName(c, t, i);
        } else if (_heads.containsKey(t.bandId[i]) && _tabbed.add(t.bandId[i])) {
          _headJobs.add(t.bandId[i]); // 이 판(보통 타일들 · 감싼 타일 하나)의 테두리 걸음에서 — 감싼 타일의 자르기 · 흐림을 함께 받는다
        }
      }
    }
    for (int i = 0; i < t.bandCount; i++) {
      if (t.bandLook[i] & BandLook.under == 0) _paintBand(c, t, i, zones);
    }
  }

  /// 연대 폭(구역 19)을 띠 번호로 묶는다 — 타일마다 한 번(내용이 바뀌지 않는다).
  static Map<int, List<int>> _zonesOf(TileSection zones) {
    if (zones.count == 0) return const {};
    final out = <int, List<int>>{};
    final ref = zones.u(Tile.itemRef);
    for (int i = 0; i < zones.count; i++) {
      (out[ref[i]] ??= <int>[]).add(i);
    }
    return out;
  }

  // ─────────────────────────── 뒤 장(상국 표기 C) ───────────────────────────

  /// 뒤 장의 둥근 정도(건의 8의 2번 C). 상국 탭은 뒤 장의 두 끝에서 이만큼 안쪽(평평한 윗변)에만 선다.
  static const sheetRadius = 10.0;

  /// 뒤 장의 위로 드러남 · 오른쪽 어긋남 · 상국 탭의 올림(px). 감독 결정(2026-10-14 "어긋나는 부분 없이" → 옆은 맞추고 위로만):
  /// 위 5 · 오른쪽 0 · 탭 5. 그림 대본의 `sheet` 걸음으로 바꿔 볼 수 있다.
  static double sheetRise = 5.0, sheetShift = 0.0, tabRise = 5.0;

  /// 띠와 뒤 장 사이의 종이빛 틈(띠가 살짝 떠 보이게 — 그림자 대신). 0이면 틈 없음(감독 확인 그림의 두 꼴).
  static double sheetGap = 1.5;

  /// 깊이(구역 47의 a — 0 빈 · 1 칠한 · 2 점선 · 3 파선 · 4 옅은 · 5 짙은 · 6 빗금)마다 상국 색의 몫(oklab · 나머지는 종이):
  /// 스스로 다스림 46% · 종속 · 보호 · 위성 62% · 괴뢰 · 위임 74% · 식민 · 직할 · 점령 86%. 명목상(2) · 관계 없는 소속(3)은 칠 없이 점선 테.
  static const sheetMix = [.46, .62, 0.0, 0.0, .74, .86, .86];

  /// 이 장면에 깔 받침 카드(상국 탭의 카드 · 연합 겹 탭 빼고) 하나하나의 자리와 꼴 — [paintHostSheets](칠 · 테 · 틈)와 [paintHostPaper](칠 없는 카드의
  /// 바탕색 종이 — 뒤 판)가 같은 거름 · 같은 꼴을 쓴다. 조감 · 탭 끔에는 없다.
  Iterable<_Sheet> _sheets(PaintContext c) sync* {
    if (c.layout.bird || c.hide.contains('tabs') || _hostSegs.isEmpty) return;
    final layout = c.layout, v = c.v;
    for (final entry in _hostSegs.entries) {
      final band = entry.key;
      // 긴 관계의 카드부터 깐다 — 겹친 섬김에서 안쪽(짧은) 카드의 윗 테 · 세로 테가 바깥 카드 칠 위에 보이게(조사 결함 20). 같으면 왼쪽 차례(예전 차례).
      final mine = [for (final s in entry.value.values) if (s.look != coalLook) s]
        ..sort((a, b) {
          final la = a.right - a.left, lb = b.right - b.left;
          return la != lb ? lb.compareTo(la) : a.left.compareTo(b.left);
        });
      for (final s in mine) {
        if (s.row < 0 || s.row >= layout.rowCount || !layout.hasBody(s.row)) continue;
        if (layout.spec(s.row)?.kind == RowKind.foldedGroup) continue;
        final geo = layout.geo(s.row);
        final top = v.yOf(layout.rowTop(s.row) + geo.bandTop), h = geo.bandHeight;
        if (h <= 0 || !c.rowOnScreen(s.row, top - sheetRise, h + sheetRise)) continue;
        final bandL = _joinedLeft[band] ?? (c.left - 40), bandR = _joinedRight[band] ?? (c.w + 40);
        final atL = s.left <= bandL + .5;
        final l0 = s.left + (atL ? sheetShift : 0), r0 = l0 + (s.right - s.left);
        if (r0 < c.left - sheetRadius || l0 > c.w + sheetRadius || r0 - l0 < 1) continue;
        final alpha = _em.bandAlpha(band, s.row);
        if (alpha <= 0) continue;
        // 화면 밖으로 멀리 뻗은 쪽은 잘라 둔다(둥근 끝은 화면 밖에 남는다).
        final l = math.max(l0, c.left - 2 * sheetRadius), r = math.min(r0, c.w + 2 * sheetRadius);
        // 같은 상국 아래 관계만 바뀐 자리(앞 관계의 끝 = 이 관계의 시작)는 이어 그린다 — 그쪽은 둥근 모서리도 세로 테도 없이 짙기만 바뀐다.
        bool joins(_HostSeg o, double x) => !identical(o, s) && o.uid == s.uid && (x - o.right).abs() < 1.5;
        final joinL = mine.any((o) => joins(o, s.left)), joinR = mine.any((o) => !identical(o, s) && o.uid == s.uid && (o.left - s.right).abs() < 1.5);
        final roundL = l == l0 && !joinL, roundR = r == r0 && !joinR;
        // 카드는 꼬리표의 보이는 몸통만큼 — 사건 칸을 남의 칸 층만큼 올린 꼬리표는 줄 몫(띠 아랫변)보다 짧고, 그 밑은 바탕이다
        // (예전에는 줄 몫만큼 길어 몸통 밑으로 카드 · 바탕빛 틈이 나와 그 자리의 띠 뒤 승계선 · 그릇 칠 · 세로 눈금을 지웠다 — 감독 지적 2026-10-25
        // '등불왕국 부분 계승 줄이 끊겨있는데' · 감독 결정 2026-10-25 '세로줄은 늘 바탕').
        final bottom = tagBottom(c, s.row, band, top);
        final t = top - sheetRise, b = t + (bottom - top);
        // 꼬리표 갈래 E: 카드는 띠와 같은 꼬리표 꼴 — 왼쪽은 띠의 끝 꼴(모따기 5 · 둥근 끝 12 · 직각), 오른쪽은 직각(목업 card).
        // 위 귀의 크기는 줄 몫의 키로(고른 테가 카드의 귀를 두른다 — [_ringOf]) · 아래 귀는 띠 뒤라 [_tagPath]가 짧은 카드에 맞춰 줄인다.
        final end = _endOf[band] ?? TagEnd.cham, k = _tagCorner(end, h);
        yield (band: band, s: s, l: l, t: t, r: r, b: b, l0: l0, r0: r0, top: top, bottom: bottom, h: h, bandL: bandL, bandR: bandR,
            end: end, k: k, roundL: roundL, roundR: roundR, joinL: joinL, alpha: alpha, atL: atL);
      }
    }
  }

  /// 칠 없는 받침 카드(명목상 · 관계 없는 소속 — 점선 · 파선 테만)의 테 안 바탕색 종이 — 뒤 판(그릇 · 바탕 문화 뒤 · 실 · 관계선 · 매단 것 앞)에 한 번.
  /// 아래의 연도 세로줄은 가리되(리메이크 4단계 세로줄 얹기), 카드 윗단(5px)에 끝이 닿는 관계선의 꺾쇠 · 점은 그 위에 그대로 오게 —
  /// 앞 판 [paintHostSheets]에서 깔면 칠 없는 카드가 그것들을 지웠다(세로줄 얹기 검토). 테 · 틈 · 맞히기는 [paintHostSheets]에 그대로 둔다.
  void paintHostPaper(PaintContext c) {
    for (final p in _sheets(c)) {
      if (sheetMix[p.s.look.clamp(0, 6)] > 0) continue;
      final groundX = (math.max(p.l, c.left) + math.min(p.r, c.w)) / 2;
      c.canvas.drawPath(_tagPath(p.l, p.t, p.r, p.b, p.end, p.k, p.roundL), _sheetFill..color = ui.Color(c.grounds.at(groundX, p.t + 1)));
    }
  }

  /// 속국 띠 **뒤**에 상국 빛깔의 종이(뒤 장) — 꼬리표의 보이는 몸통과 같은 높이([tagBottom]) · 둥근 10, 위로 5px 드러남, 가로는 관계의 시작 ~ 끝 그대로(띠 끝 밖으로 나오지 않는다).
  /// 테 1px = 상국 색 78% + 먹. 띠 둘레에는 종이빛 틈([sheetGap] — 카드가 비치는 자리에만). 띠 층의 걸음보다 먼저 캔버스에 바로 그린다 — 그 걸음의 네모 · 모서리 묶음이
  /// 뒤에 나가므로 뒤 장은 띠 · 제 이름 탭 · 상국 탭 아래에 깔린다. 조감에는 없다. 한 장면에 몇 장뿐이라 길(Path)로 그린다.
  void paintHostSheets(PaintContext c) {
    // 감싸야 하는 타일(메움 · 떠오르는 중)은 타일마다 걸음을 다 돌아 이 일이 여러 번 불린다 — 장면에 한 번만.
    if (_sheetsDone) return;
    _sheetsDone = true;
    final canvas = c.canvas;
    // 띠 둘레의 바탕빛 틈은 그 띠의 카드를 **다 깐 뒤** 한 번(웹 `.tl-plate-back`과 같은 차례 — 조사 결함 23): 예전에는 첫 카드 바로 뒤에 깔아
    // 둘째 카드부터는 그 칠이 틈을 덮어 띠가 카드에 붙었다(f4-liege 갈대 공국의 백사 공국 조공 카드). 띠 → 틈 꼴 · 모든 카드 길의 합 · 카드마다 (칸, 칠).
    final rings = <int, ({ui.Path clip, double bl, double br, double top, double bottom, TagEnd end, double gapK, bool roundL, double alpha, List<(double, double, double, double, int)> cards})>{};
    for (final p in _sheets(c)) {
      final s = p.s, band = p.band, l = p.l, t = p.t, r = p.r, b = p.b, top = p.top, bottom = p.bottom, end = p.end, k = p.k, alpha = p.alpha;
      final hc = 0xff000000 | s.color, look = s.look.clamp(0, 6);
      final mix = sheetMix[look];
      // 카드는 아래의 연도 세로줄을 가리는 종이다(리메이크 4단계 세로줄 얹기 — paint/grounds.dart): 흐린 카드의 칠은 그 자리 바탕색과 섞은 불투명 색으로.
      // 칠 없는 카드(명목상 · 관계 없는 소속 — 점선 · 파선 테만)의 테 안 바탕색 종이는 뒤 판에 이미 깔았다([paintHostPaper]). 바탕은 화면에 보이는 카드 몫의 가운데에서 읽는다.
      final groundX = (math.max(l, c.left) + math.min(r, c.w)) / 2;
      final cardFill = mix > 0 ? c.grounds.over(withAlpha(mixOklab(hc, Look.paper, mix), alpha), groundX, t + 1) : c.grounds.at(groundX, t + 1);
      if (mix > 0) canvas.drawPath(_tagPath(l, t, r, b, end, k, p.roundL), _sheetFill..color = ui.Color(cardFill));
      // 카드는 그 위에 얹는 것(흐린 속국 띠 · 탭 · 플래그)이 섞일 그 자리의 바탕이다 — 바탕 칸으로 등록한다(왼쪽 귀 몫도 네모로 — 띠의 귀 밖이라 거의 묻지 않는다).
      c.grounds.add(l, t, r, b, cardFill);
      // 소속 구간의 정통성(구역 58 — 칸 그림 갈래 걸음 3): 탭과 뒤 장은 한 장이라 테도 탭을 따른다 — 명목은 먹 25 · 대립은 파선(_paintHostTabs).
      final legit = _hostLegit[(band, s.k)] ?? -1;
      final edge = withAlpha(legit == Schema4.legitNominal ? LegitLook.nominalLine : mixOklab(hc, Look.ink, .78), alpha);
      // 테: 윗변과, 이어지지 않은 쪽의 귀 · 세로 변만(아랫변은 띠 뒤라 보이지 않는다).
      final edgeL = p.roundL && !p.joinL && l == p.l0;
      final stroke = legit == Schema4.legitRival ? EdgeStroke.dashed : (look == 2 ? EdgeStroke.dotted : (look == 3 ? EdgeStroke.dashed : EdgeStroke.solid));
      _sheetEdge(c, l, t, r, b, end, k, edgeL, p.roundR, edge, stroke, p.l0);
      // 카드마다 테를 곧바로 내보낸다 — 뒤 카드의 칠(길 · 곧바로 그림)이 앞 카드의 테를 덮는 예전 차례 그대로.
      c.flushShapes();
      sprites.flush(canvas);
      // 맞히기: 띠 위로 드러난 윗단(5px) — 올리면 상국 띠도 진해지고 누르면 상국 상세(상국 탭과 같은 길).
      _hits.add(_HitBox(math.max(l, c.left), top - sheetRise, math.min(r, c.w), top, s.hostBand, s.row, true, uid: s.uid));
      c.stats.shapes++;
      c.debug?.note('뒤장', '$band ${s.name} ${(p.l0 * 10).round()},${(p.r0 * 10).round()} 깊이=$look${p.atL ? ' 첫머리' : ''}');
      // 띠 둘레의 바탕빛 틈 — 띠가 뒤 장 위에 살짝 떠 보이게(띠는 다음 걸음에 이 위에 그려진다). 바탕이 흰색이 아니게 된 뒤로(건의 2026-10-15 1번) 종이가 아니라 바탕색.
      // 틈은 카드가 비치는 자리에만 깐다(카드 길로 자름 — 카드의 흐린 테두리 픽셀까지 덮게 1px 넓게): 예전에는 띠 길이 × 줄 몫 전체에 깔아
      // 카드 밖(꼬리표 밑 · 띠 양 끝 밖의 바탕)에서 그 밑의 세로 눈금 · 그릇 칠을 바탕빛으로 지웠다(감독 결정 2026-10-25 '세로줄은 늘 바탕').
      if (sheetGap > 0 && (sheetRise > 0 || sheetShift > 0)) {
        final card = _tagPath(l - 1, t - 1, r + 1, b + 1, end, k > 0 ? k + 1 : 0.0, p.roundL);
        final ring = rings[band];
        if (ring == null) {
          final bl = math.max(p.bandL, c.left - 2 * sheetRadius), br = math.min(p.bandR, c.w + 2 * sheetRadius);
          rings[band] = (clip: card, bl: bl, br: br, top: top, bottom: bottom, end: end, gapK: k > 0 ? k + sheetGap : 0.0, roundL: bl == p.bandL, alpha: alpha,
              cards: [(l, t, r, b, cardFill)]);
        } else {
          rings[band] = (clip: ui.Path.combine(ui.PathOperation.union, ring.clip, card), bl: ring.bl, br: ring.br, top: ring.top, bottom: ring.bottom, end: ring.end,
              gapK: ring.gapK, roundL: ring.roundL, alpha: ring.alpha, cards: ring.cards..add((l, t, r, b, cardFill)));
        }
      }
    }
    for (final g in rings.values) {
      canvas
        ..save()
        ..clipPath(g.clip)
        ..drawPath(_tagPath(g.bl - sheetGap, g.top - sheetGap, g.br + sheetGap, g.bottom + sheetGap, g.end, g.gapK, g.roundL), _sheetFill..color = ui.Color(withAlpha(Look.ground, g.alpha)))
        ..restore();
      // 틈은 띠 밑까지 깔린 칠이라(흐리면 바탕빛을 그 알파로 카드에 얹은 빛) 흐린 띠가 섞일 바탕이다 — 카드와 겹친 몫을 바탕 칸으로 등록한다.
      for (final (l, t, r, b, fill) in g.cards) {
        c.grounds.add(math.max(g.bl - sheetGap, l - 1), math.max(g.top - sheetGap, t - 1), math.min(g.br + sheetGap, r + 1), math.min(g.bottom + sheetGap, b + 1),
            over(withAlpha(Look.ground, g.alpha), fill));
      }
    }
  }

  /// 받침 카드의 테(아랫변 없음 — 조사 결함 24): 예전에는 길(Path) 획 1px로 그어 화면 그림판(Impeller)의 긴 가로 획 앞쪽 약 13%가 반 짙기로 그려졌다
  /// (f4-liege 갈대 공국 윗선 x 474 ~ 613 bbac9a · 뒤는 8f7e68). 이제 띠 테([_edge])와 같은 길 — 곧은 변은 픽셀 칸 네모 묶음(점선 · 파선은 dash/gap),
  /// 왼쪽 위 귀는 1px 귀 조각(모따기 · 둥근 끝)이다. 왼쪽 세로 변과 귀([roundL]일 때) → 윗변 → 오른쪽 세로 변([roundR] — 관계의 진짜 끝일 때).
  /// 무늬의 차례는 윗변이 카드의 진짜 왼쪽([anchor]) · 세로 변이 카드 윗변에서 잰다 — 옆으로 옮겨도 · 카드 키가 바뀌어도 드러난 윗단의 점 자리가 그대로.
  void _sheetEdge(PaintContext c, double l, double t, double r, double b, TagEnd end, double k, bool roundL, bool roundR, int argb, EdgeStroke stroke, double anchor) {
    final corner = roundL && end != TagEnd.plain && k > 0 ? k : 0.0;
    c.quads.hLine(l + corner, r, t, argb, dash: stroke.dash, gap: stroke.gap, phase: anchor);
    if (roundL) c.quads.vLine(l, t + corner, b, argb, dash: stroke.dash, gap: stroke.gap, phase: t.floorToDouble());
    if (roundR) c.quads.vLine(r - 1, t, b, argb, dash: stroke.dash, gap: stroke.gap, phase: t.floorToDouble());
    if (corner > 0) sprites.add(end == TagEnd.cham ? BandSprites.chamEdge(corner) : BandSprites.arc(corner), BandCorner.topLeft, l, t, argb, corner);
  }

  /// 꼬리표 꼴의 귀 크기(높이 [h]의 띠): 모따기 5 · 둥근 끝 min(12, h/2) · 직각 0.
  static double _tagCorner(TagEnd end, double h) => TagLook.cornerOf(end, h);

  /// 꼬리표 꼴의 닫힌 길(받침 카드 · 종이 틈 — 한 장면에 몇 장뿐이라 길로 그린다): 왼쪽 두 귀는 [end]의 꼴(크기 [k]), 오른쪽은 직각.
  /// [roundL]이 거짓이면 왼쪽도 직각(화면 밖 · 앞 관계와 이어짐). 왼쪽 아래 귀는 키가 두 귀에 모자라면 남는 만큼으로 준다
  /// (받침 카드는 위 귀를 줄 몫의 키로 재고 키는 꼬리표의 보이는 몸통만큼이라 — [paintHostSheets] · 아래 귀는 띠 뒤라 보이지 않는다).
  static ui.Path _tagPath(double l, double t, double r, double b, TagEnd end, double k, bool roundL) {
    final p = ui.Path();
    if (!roundL || end == TagEnd.plain || k <= 0) return p..addRect(ui.Rect.fromLTRB(l, t, r, b));
    final kb = math.min(k, math.max(0.0, b - t - k));
    if (end == TagEnd.cham) {
      return p
        ..moveTo(r, t)
        ..lineTo(l + k, t)
        ..lineTo(l, t + k)
        ..lineTo(l, b - kb)
        ..lineTo(l + kb, b)
        ..lineTo(r, b)
        ..close();
    }
    return p..addRRect(ui.RRect.fromLTRBAndCorners(l, t, r, b, topLeft: ui.Radius.circular(k), bottomLeft: ui.Radius.circular(kb)));
  }

  /// 이 장면에 뒤 장을 이미 그렸는가([beginFrame]이 내린다).
  bool _sheetsDone = false;

  final _sheetFill = ui.Paint()..isAntiAlias = true;
  /// 칸이 그려진 뒤에 부른다: 모아 둔 띠 테두리를 그린다(층의 차례 — 띠 채움 → 칸 → 구분선 → 띠 테두리).
  /// 모서리 조각은 painter가 이 뒤에 부르는 `_flush(c, bands)`가 내보낸다.
  void paintEdges(PaintContext c) {
    for (final e in _edges) {
      _edge(c, e);
    }
    _edges.clear();
    for (final id in _headJobs) {
      final h = _heads[id];
      if (h != null) _paintHead(c, h);
    }
    _headJobs.clear();
  }

  // ─────────────────────────── 띠 ───────────────────────────

  /// 띠 하나. [later]가 있으면(바탕 문화 — [paintUnder]) 칠만 지금 하고 테 · 맞히기 · 검사 기록은 거기에 넣어 둔다.
  void _paintBand(PaintContext c, Tile t, int i, TileSection zones, {List<void Function()>? later}) {
    final layout = c.layout;
    final row = t.bandRow[i];
    if (row >= layout.rowCount || !layout.hasBody(row)) return;
    // 접힌 민족 줄 · 접힌 트랙에서는 띠도 탭도 그리지 않는다 — 그 줄은 가는 막대 하나뿐이다(paint/minibars.dart의 몫).
    if (t.bandLook[i] & BandLook.folded != 0 || layout.spec(row)?.kind == RowKind.foldedGroup) return;
    final geo = layout.geo(row);
    final look = t.bandLook[i], flags = t.bandFlags[i];
    final under = look & BandLook.under != 0;
    final v = c.v, origin = t.origin.toDouble();
    // 바탕 문화는 줄의 몫 전체(띠 아래 덧붙는 단까지), 보통 띠는 띠의 몫만.
    final top = v.yOf(layout.rowTop(row) + geo.bandTop);
    // 줄이 흐르며 자라거나 줄어드는 동안은 줄의 보이는 몫([SceneLayout.rowClip]) 밖을 자른다 — 다 자라지 않은 줄의 띠가 아래 줄 띠 위로
    // 넘쳐 이름끼리 포개지지 않게(감독 2026-10-26 '신라 쪽 휠 — 신라 이름표가 튀어나감': 다시 펴지는 변한 줄이 신라 띠를 덮던 것).
    final clip = layout.rowClip(row);
    final height = math.min(under ? geo.height - geo.bandTop : geo.bandHeight, clip == null ? double.infinity : clip - geo.bandTop);
    if (height <= 0 || !c.rowOnScreen(row, top, height)) return;

    final cutL = flags & Tile.clipLeft != 0, cutR = flags & Tile.clipRight != 0;
    final fuzzyS = flags & Tile.fuzzyStart != 0, fuzzyE = flags & Tile.fuzzyEnd != 0;
    final id = t.bandId[i];
    // 띠의 두 끝은 연대 폭까지 품는다(명세 5-3 둘째 — bandStart는 startRange[0]이다).
    var startMin = t.bandX0[i], endMin = t.bandX1[i];
    final list = _zoneOf[id];
    if (list != null) {
      final side = zones.u(Tile.itemA), za = zones.f(Tile.itemX0), zb = zones.f(Tile.itemX1);
      for (final z in list) {
        if (side[z] == 0 && za[z] < startMin) startMin = za[z];
        if (side[z] == 1 && zb[z] > endMin) endMin = zb[z];
      }
    }
    var x1 = cutL ? v.xOf(origin + t.bandX0[i]) : v.xOf(origin + startMin);
    var x2 = cutR ? v.xOf(origin + t.bandX1[i]) : v.xOf(origin + endMin);
    // 연대 폭이 앞(뒤) 타일에서 비롯하면 이 타일의 연대 폭 조각은 타일 끝에서 잘려 있고, 띠 조각은 확정 해부터라 그 타일에는 없다 —
    // 띠의 진짜 끝은 장면에서 모은 값([_joinedLeft] · [_joinedRight] — 머리 이름 · 무늬 자리가 재는 그 끝)으로 넓힌다(감독 2026-10-26
    // '고구려 · 신라 이름표가 띠 밖으로 탈출': 확대 · 축소로 타일 경계가 연대 폭 안을 지나면 띠만 그 경계에서 잘려 이름이 빈 바탕에 섰다).
    if (!cutL) x1 = math.min(x1, _joinedLeft[id] ?? x1);
    if (!cutR) x2 = math.max(x2, _joinedRight[id] ?? x2);
    if (fuzzyS) x1 -= Look.fuzzyFade;
    if (fuzzyE) x2 += Look.fuzzyFade;
    // 미정 꼬리는 같은 줄의 이웃 띠 앞에서 멈춘다(위 [_rowSpans]) — 꼬리의 길이(옅어지는 폭)는 그대로라 모자란 만큼 제 띠 안에서 옅어진다.
    if (!under && ((fuzzyS && !cutL) || (fuzzyE && !cutR))) {
      final (roomL, roomR) = _tailRoom(row, id, v.xOf(origin + startMin), v.xOf(origin + endMin));
      if (fuzzyS && !cutL && x1 < roomL) x1 = roomL;
      if (fuzzyE && !cutR && x2 > roomR) x2 = roomR;
    }
    // 최대로 줄여도 짧은 나라(진 · 대한제국)가 사라지지 않게: 6px보다 좁은 띠는 가운데를 지키며 6px 알약으로 그린다(감독 2026-09-22 "아예 사라지는 느낌 없애줘").
    // 타일 경계에서 잘린 조각은 그대로 둔다(양쪽 조각이 같은 px에서 만나야 하므로). 점 · 이름은 실제 범위로 재어 좁으면 숨는다(labels.dart).
    final pill = !cutL && !cutR && x2 - x1 < _minBandPx;
    if (pill) {
      final mid = (x1 + x2) / 2;
      x1 = mid - _minBandPx / 2;
      x2 = mid + _minBandPx / 2;
    }
    final edgeL = c.left - 1, edgeR = c.w + 1;
    if (x2 < c.left - 2 || x1 > c.w + 2) return;
    var l = math.max(x1, edgeL), r = math.min(x2, edgeR);
    if (r - l < 3) r = l + 3;
    // 이음매는 양쪽 조각이 같은 정수 px에서 만나게 한다.
    if (cutL) l = l.roundToDouble();
    if (cutR) r = r.roundToDouble();
    final b = top + height;
    final shape = layout.birdShape;

    final lifted = id == (hotBand ?? c.scene.hoverBand) || id == _em.look.band;
    // 올리지 않은 띠의 색은 타일의 값(제 색 · look · 미정)에서만 나온다 — 타일마다 한 번 섞어 두고 다시 쓴다.
    final BandTone tone;
    if (lifted) {
      tone = toneOf(t.bandColor[i], look, fuzzy: fuzzyS || fuzzyE, lifted: true);
    } else {
      final memo = _tones[t] ??= List<BandTone?>.filled(t.bandCount, null);
      tone = memo[i] ??= toneOf(t.bandColor[i], look, fuzzy: fuzzyS || fuzzyE);
    }
    // 미정 끝의 꼬리: 화면 밖으로 밀린 만큼 줄여 가장자리에서 갑자기 끊기지 않게 한다(T:6787).
    final tailL = fuzzyS ? math.max(0.0, Look.fuzzyFade - math.max(0.0, edgeL - x1)) : 0.0;
    final tailR = fuzzyE ? math.max(0.0, Look.fuzzyFade - math.max(0.0, x2 - edgeR)) : 0.0;
    // 흐림(감독 지적 · 고름 다 2026-10-26 — [PaintPick.haze] 기본 켬): 미정 끝 · 연대 폭은 그 구간만 흐린 칠 · 같은 옅음의 테([hazePeriod] · [_hazeEnds]).
    // 미정 끝의 흐린 구간은 예전처럼 끝으로 갈수록 바탕에 사라진다(꼬리 tailL · tailR). 띠 전체는 흐리지 않는다([toneOf]). 끔(`--paint-off=haze`)이면 두 폭이 0이라 옛 꼴.
    final hazing = PaintPick.haze && !under;
    var hazeL = 0.0, hazeR = 0.0;
    if (hazing) {
      hazeL = cutL ? 0.0 : tailL;
      hazeR = cutR ? 0.0 : tailR;
      if (list != null) {
        final side = zones.u(Tile.itemA), za = zones.f(Tile.itemX0), zb = zones.f(Tile.itemX1);
        for (final z in list) {
          if (side[z] == 0) hazeL = math.max(hazeL, v.xOf(origin + zb[z]) - math.max(x1, edgeL));
          if (side[z] == 1) hazeR = math.max(hazeR, math.min(x2, edgeR) - v.xOf(origin + za[z]));
        }
      }
      // 끝만 짧게 흐림(감독 고름 2026-10-26 04:4x): 연대 폭 없이 띠 전체에 붙은 추정 · 전승 연대는 두 끝에 [shortHaze](짧은 띠는 폭의 1/4)만 흐린다.
      // 어느 끝이 추정인지는 자료가 연대 폭으로만 적는다 — 연대 폭이 있으면 그 구간이 이미 그 끝이라 더하지 않는다. 사라지지 않고(꼬리는 미정 끝만) 몸통 · 글자는 보통.
      final cert = BandLook.certOf(look);
      if ((cert == BandLook.certEstimated || cert == BandLook.certLegend) && look & BandLook.hasRange == 0) {
        final s = shortHazeOf(x2 - x1);
        if (!cutL) hazeL = math.max(hazeL, x1 + s - math.max(x1, edgeL));
        if (!cutR) hazeR = math.max(hazeR, math.min(x2, edgeR) - (x2 - s));
      }
    }
    final openL = cutL || x1 < edgeL + .5, openR = cutR || x2 > edgeR - .5;
    // 문화 띠는 두 끝이 폭의 12%, 바탕 문화는 10%만큼 옅어진다. 잘린 쪽은 옅어지지 않는다(C:550 · C:603).
    final softPct = under ? .10 : (BandLook.kindOf(look) == BandKind.culture ? .12 : 0.0);
    final soft = softPct > 0 ? (x2 - x1) * softPct : 0.0;
    final fade = _Fade(
      l, r, math.max(tailL, openL ? 0 : soft), math.max(tailR, openR ? 0 : soft),
      base: _em.bandAlpha(id, row), spots: _spotsOn(c, id, l, r), spotAlpha: _spotAlpha(id, row),
    );

    // 모서리 반지름: 미정 쪽 22(화면 밖에서 잘린 꼬리는 0) · 문화와 바탕 문화 12(아래 10) · 그 밖 10 · 잘린 쪽 0.
    // 조감은 종류 · 미정을 가리지 않고 네 모서리가 같다(모양 a · b 4.5 · c 2.5 — C:1766~1770).
    final cap = math.min((r - l) / 2, height / 2);
    final birdR = shape?.radius;
    // 꼬리표(갈래 E — 설계 4-1 '실제 띠에 입힘'): 왼쪽은 갈래의 꼴(모따기 · 둥근 끝 — 키에 맞춘 크기 [TagLook.cornerOf] · 직각), 오른쪽은 늘 직각.
    // 미정 쪽은 옅어지며 열리므로 직각이다. 조감 · 바탕 문화 · 문화 띠 · 6px 알약은 예전 꼴 그대로(조감의 꼴은 설계 4-6 #4).
    // 꼴은 form의 종류 갈래로(없으면 옛 종류 짐작 — [TagLook.endOfBand] · G6 가). 정통성 '대립'인 꼬리표는 테를 파선 3 · 2로(조직체의 점선보다 이긴다 —
    // 직각(무리)은 테가 없는 그대로 · 칠 · 테 빛깔은 look 그대로 · 조감은 꼬리표가 아니라 예전 선).
    final form = t.bandForm[i];
    final tagEnd = shape == null && !under && !pill && BandLook.kindOf(look) != BandKind.culture ? TagLook.endOfBand(look, form) : null;
    final stroke = tagEnd != null && TagLook.rivalOf(form) ? TagLook.rivalStroke : tone.stroke;
    final double radiusL, radiusR, radiusLB, radiusRB;
    if (tagEnd != null) {
      final shut = openL || fuzzyS;
      radiusL = radiusLB = shut ? 0.0 : math.min(TagLook.cornerOf(tagEnd, height), cap);
      radiusR = radiusRB = 0;
    } else {
      radiusL = openL ? 0.0 : math.min(birdR ?? (fuzzyS ? 22.0 : tone.radius), cap);
      radiusR = openR ? 0.0 : math.min(birdR ?? (fuzzyE ? 22.0 : tone.radius), cap);
      radiusLB = openL ? 0.0 : math.min(birdR ?? (fuzzyS ? 22.0 : tone.radiusBottom), cap);
      radiusRB = openR ? 0.0 : math.min(birdR ?? (fuzzyE ? 22.0 : tone.radiusBottom), cap);
    }
    final chamL = tagEnd == TagEnd.cham && radiusL > 0;
    // 점선 · 무늬의 자리는 띠의 진짜 왼쪽 끝에서 잰다 — 두 조각이 이음매에서 어긋나지 않게.
    final anchor = _joinedLeft[id] ?? l;
    // 그릇 노릇 객체(동맹 · 구성원 없는 나라 · 동군연합)는 제 줄의 납작한 뚜껑(과제 8 걸음 1 · 스위치 lid — lid_tags.dart). 띠 상자 · 누름 · 기록은 같은 길.
    if (tagEnd != null && _lidOf(c, look, form, id)) {
      _paintLid(c, t, i, row, geo, id, form, fade, tagEnd, l, top, r, b, openL, openR, fuzzyS, fuzzyE, anchor, hazeL, hazeR);
      return;
    }

    // 고른 띠 · 고른 것과 같은 줄의 띠는 그림자 대신 ink 선 하나(css의 `box-shadow: 0 0 0 1px` — HistoryArchive의 디자인 · 2026-10-13). 손을 올린 띠는 표시가 없다.
    // 한 장면에 몇 개뿐이라 묶음 밖에서 바로 그린다.
    // 두 장 꼬리표(감독 결정 '두 장 ㄴ' — 손그림): 이름 색줄(줄 몫의 bodyTop까지) + 몸통 띠(칸 뭉치 칠 → 흰 사건 칸). 몸통은 그 띠에 칸 · 사건이 있을 때만
    // (띠 look 비트 19 사건 · 20 칸 — 내보내기 tracks.mjs의 늦은 차례). 옛 저장소(줄 값 없음)는 몸통을 늘 띠 아랫변까지.
    if (tagEnd != null && geo.bodyTop >= 0) {
      _paintTwoPiece(c, t, i, zones, row, geo, look, id, tone, stroke, fade, tagEnd, l, top, r, b, openL, openR, fuzzyS, anchor, cutL, hazeL: hazeL, hazeR: hazeR);
      return;
    }
    if (shape == null && !under && _em.look.picked && fade.base > .99) {
      if (tagEnd != null) {
        _ringOf(c, id, row, l, top, r, b, radiusL, chamL, openL, openR, tagEnd, height);
      } else {
        _ring(c, l, top, r, b, radiusL, radiusR, radiusLB, radiusRB, openL, openR);
      }
    }

    if (!c.hide.contains('bandFill')) {
      // 안개(전승 · 반전설 · 부정됨)도 고른 옅은 색으로 칠한다 — 예전의 아래로 사라지는 투명도 대신(감독 건의 2026-10-15 2번 · [fogFillOf]).
      _fill(c, l, top, r, b, radiusL, radiusR, radiusLB, radiusRB, fogFillOf(tone, look), fade, chamL: chamL, paper: true, register: under);
      if (hazing) _hazeEnds(c, l, top, r, b, radiusL, radiusR, radiusLB, radiusRB, hazeL, hazeR, hazed(fogFillOf(tone, look), hazePeriod), fade, chamL: chamL);
      if (tone.hatch) _steps(l, r, fade, 4, (a, z, alpha) => c.patterns.add(_hatchBand, a, top, z, b, withAlpha(tone.hatchColor, alpha), phaseX: anchor + 1, phaseY: top + 1));
      if (tone.dots) _dots(c, l, top, r, b, t.bandColor[i], fade, anchor, under);
      // 조감 모양 c의 연맹은 겹줄 자체가 없다(C:1773), a · b의 종이빛은 종이빛도 1px이다.
      if (BandLook.kindOf(look) == BandKind.federation && shape != BirdShape.c) {
        _double(c, l, top, r, b, radiusL, radiusR, tone.edge, fade, openL, openR, shape != null);
      }
      if (tone.pole != 0 && !openL && !fuzzyS) _pole(c, l + 1, top + 1, b - 1, withAlpha(tone.pole, fade.base), radiusL);
      // 바탕 문화에는 연대 폭 무늬를 깔지 않는다 — 지금 연표도 underlays에는 .tl-zone을 두지 않는다(T:6676~6694).
      // 꼬리표 갈래 E: 칸 단의 흰 층은 칸 층(paint/strips.dart)이 칸이 있는 띠에만 깐다 — 무늬 · 조명은 그 아래에 묻힌다.
      if (!under && !hazing) _zones(c, t, zones, id, l, top, r, b, radiusL, radiusR, t.bandColor[i], anchor, fade);
      if (!under && _hotCoal != null) _coalLit(c, id, l, top, r, b, fade.base);
    }
    // 검색 · 창의 강조에 든 띠는 테두리가 --warn(C:339 · C:882). 커서 아래의 띠는 테두리를 한 단 짙게 —
    // 지금 연표는 그늘로 말하지만(C:673) 새 엔진은 띠마다 그늘을 그리지 않는다.
    final matched = _em.look.filtered && (_em.look.bands?.contains(id) ?? false);
    final edge = matched ? _warn : (id == (hotBand ?? c.scene.hoverBand) ? mixOklab(tone.edge, Look.ink, .82) : tone.edge);
    // 무리(복속 세력)의 꼬리표는 테가 없다 — 칠만(설계 4-1 · 고른 띠의 먹 선과 올림의 짙은 테는 그대로 받는다).
    final plain = tagEnd == TagEnd.plain && !matched && edge == tone.edge;
    // 테 · 맞히기 · 검사 기록 — 바탕 문화([later])는 예전 걸음(앞 판 [paintTile]의 맨 앞)에서.
    void rest() {
      if (!c.hide.contains('bandEdge') && !plain) {
        _edges.add(_EdgeJob(l, top, r, b, radiusL, radiusR, radiusLB, radiusRB, fade, edge, stroke, openL, openR, anchor, chamL: chamL,
            hazeL: hazeL, hazeR: hazeR, hazeArgb: hazing ? hazed(edge, hazePeriod) : 0));
      }
      _hits.add(_HitBox(l, top, r, b, id, row, false));
      c.stats.shapes++;
      c.debug?.bands.add(DebugBand(id, ui.Rect.fromLTRB(l, top, r, b), radiusL > 0, radiusR > 0, fuzzyS, fuzzyE));
      c.debug?.note(
        '띠',
        '$id 종류=${BandLook.kindOf(look)} 반지름=${radiusL.round()}/${radiusR.round()} 옅은끝=${fade.left.round()}/${fade.right.round()}'
            ' 바탕=${tone.fill.toRadixString(16)} 테두리=${edge.toRadixString(16)} ${stroke.name}'
            '${tone.hatch ? ' 빗금' : ''}${tone.fog > 0 ? ' 안개' : ''}${tone.dots ? ' 점무늬' : ''}${tone.pole != 0 ? ' 깃대' : ''}'
            '${fade.base < 1 ? ' 밝기=${fade.base.toStringAsFixed(2)}' : ''}${fade.spots.isEmpty ? '' : ' 조명=${fade.spots.length}'}',
      );
    }

    if (later != null) {
      later.add(rest);
    } else {
      rest();
    }
  }

  /// 띠 look의 비트 20(두 장 꼬리표 — 그 띠에 칸이 있는가 · 비트 19 사건은 감독 결정(사건 칸은 늘)으로 그리기에 쓰지 않는다).
  static const _hasCells = 1 << 20;

  /// 가운데 켜(칸 뭉치)의 칠: 이름 색줄 칠의 50%(목업 f-u '뭉치 칠 50%'), 사건 칸 = 종이.
  static const bodyTint = .5;

  /// 켜 사이 · 층 사이 금의 짙기 — 띠 테 빛깔을 종이와 섞은 몫(테보다 옅게 — 한 장 안의 칸막이로 보이게).
  static const innerLine = .45;

  /// 안개(전승 · 반전설 · 부정됨) 색줄의 칠 — 안개 빛깔을 한 번 더 종이와 섞은 몫. 예전 안개는 아래로 옅어지는 투명도였는데(평균 짙기 약 .48),
  /// 감독 건의(2026-10-15 2번 "연한 것도 투명도로 연하게 하는 게 아니라 색 자체를 연하게")대로 고른 색 하나로 칠한다.
  static const fogSolid = .5;

  /// 반전설 색줄의 몫 — 예전에는 아래 1/3만 사라져(평균 짙기 약 .83) 전설보다 짙었으므로 한 단 덜 옅게.
  static const fogSemi = .75;

  /// 띠(한 장 꼬리표에서는 이름 색줄)의 칠 — 안개 띠는 안개 빛깔을 종이와 한 번 더 섞은 고른 색([fogSolid] · 반전설 [fogSemi]), 나머지는 띠 칠 그대로.
  static int fogFillOf(BandTone tone, int look) =>
      tone.fog > 0 ? mixSrgb(tone.fill, Look.paper, BandLook.hsOf(look) == BandLook.hsSemi ? fogSemi : fogSolid) : tone.fill;

  /// 두 장 꼬리표의 띠 상자(화면 y — 띠 아랫변 [b]를 넘지 않음): 이름 색줄 끝 · 칸 층 끝 · 몸통 아랫변 · 칸이 있는가 · 옛 저장소(줄 값 없음)인가.
  /// 두 장 꼬리표([_paintTwoPiece])와 뚜껑(lid_tags.dart `_paintLid`)이 **이 한 셈**을 쓴다 — 뚜껑 상자가 두 장 꼬리표 상자와 어긋나지 않게(과제 8 걸음 4 검토).
  /// 띠의 값은 타일 [t]의 [i]째 띠에서 읽는다. 띠마다 나르는 값(칸 그림 갈래 remake-4-cells의 `sub` — 지도자 단 수 · 직위 줄 더 — 합칠 때 넣음)은
  /// 여기 한 곳에서 읽어 [TagLook.floorEndOf] · [TagLook.bodyBottom]에 넘긴다(뚜껑도 따라온다).
  ({double stripB, double floorB, double bodyB, bool hasCells, bool oldStore}) _tagBox(PaintContext c, Tile t, int i, int row, RowGeo geo, double b) {
    final layout = c.layout, v = c.v, base = layout.rowTop(row), look = t.bandLook[i];
    final stripB = math.min(b, v.yOf(base + geo.bodyTop));
    final oldStore = !(layout.spec(row)?.cellRows ?? false);
    final sub = t.bandSub[i];
    final floorB = math.min(b, v.yOf(base + (oldStore ? geo.floorEnd : TagLook.floorEndOf(geo, look, sub: sub))));
    final hasCells = oldStore ? floorB > stripB + .5 : look & _hasCells != 0;
    final bodyB = math.min(b, v.yOf(base + TagLook.bodyBottom(geo, look, oldStore: oldStore, loose: layout.conditions.density < 0, sub: sub)));
    return (stripB: stripB, floorB: floorB, bodyB: bodyB, hasCells: hasCells, oldStore: oldStore);
  }

  /// 한 장 꼬리표(감독 건의 2026-10-15 3번 — "띠는 다 하나의 띠 안에 있는 걸로 통일 · 가장 위 나라 이름 띠가 가장 진하고 ·
  /// 중간의 시기 · 지도자 등은 좀 더 연하게(통일) · 마지막 사건 부분은 하얀색"). 예전의 두 장(색줄 · 몸통이 저마다 테)을 테 하나로 합쳤다:
  /// ① 이름 색줄 — [top] ~ 줄 몫의 [RowGeo.bodyTop](14) · 띠 칠.
  /// ② 가운데 켜 — 칸이 있을 때만(시기 · 지도자 · 내각 · 집권 · 왕조 …) 색줄 칠의 50% 하나로(칸마다 칠을 따로 두지 않는다 — strips.dart `_skinOf`).
  /// ③ 사건 칸 — 종이(흰색). 펼친 꼬리표는 늘 사건 칸까지(감독 2026-10-15 "국가 색 띠와 사건 띠는 항상").
  /// 테는 바깥 하나(왼쪽 위 귀 = 색줄 키의 꼴 · 왼쪽 아래 귀 = 몸통의 꼴 — 예전 두 장의 값), 켜 사이 · 층 사이는 테보다 옅은 1px 금([innerLine]).
  /// 바깥 테는 [stroke](대립 띠는 파선 3 · 2 — 그 밖은 [BandTone.stroke])로 · 켜 사이 금은 늘 실선.
  void _paintTwoPiece(PaintContext c, Tile t, int i, TileSection zones, int row, RowGeo geo, int look, int id, BandTone tone, EdgeStroke stroke, _Fade fade, TagEnd tagEnd,
      double l, double top, double r, double b, bool openL, bool openR, bool fuzzyS, double anchor, bool cutL, {double hazeL = 0, double hazeR = 0}) {
    final v = c.v, base = c.layout.rowTop(row);
    final (:stripB, :floorB, :bodyB, :hasCells, :oldStore) = _tagBox(c, t, i, row, geo, b);
    final sub = t.bandSub[i];
    final shut = openL || fuzzyS;
    final hazing = PaintPick.haze;
    final w = r - l;
    final cham = tagEnd == TagEnd.cham;
    final k1 = shut ? 0.0 : math.min(TagLook.cornerOf(tagEnd, stripB - top), w / 2);
    final body = bodyB > stripB + .5;
    // 색줄 아랫변의 금은 색줄의 마지막 줄(stripB − 1)에 — 예전 두 장이 테를 나눠 쓰던 자리 그대로.
    final bt = stripB - 1, bh = bodyB - bt;
    final k2 = !body || shut || tagEnd == TagEnd.plain ? 0.0 : math.min(cham ? TagLook.cham : math.min(TagLook.keyRadius, bh / 2), math.min(bh / 2, w / 2));
    final bottom = body ? bodyB : stripB, kB = body ? k2 : k1; // 한 장의 아랫변과 왼쪽 아래 귀
    final chamL = cham && (k1 > 0 || kB > 0);

    if (_em.look.picked && fade.base > .99) _ringOf(c, id, row, l, top, r, bottom, k1, cham && k1 > 0, openL, openR, tagEnd, b - top);

    // 안개도 고른 색으로(건의 2번): 안개 빛깔을 한 번 더 종이와 섞는다. 가운데 켜는 그 색줄 칠의 50%.
    final stripFill = fogFillOf(tone, look);
    final tint = mixSrgb(stripFill, Look.paper, bodyTint);
    final stripEnd = body ? stripB : bottom;
    if (!c.hide.contains('bandFill')) {
      _fill(c, l, top, r, stripEnd, k1, 0, body ? 0 : kB, 0, stripFill, fade, chamL: chamL, paper: true);
      if (hazing) _hazeEnds(c, l, top, r, stripEnd, k1, 0, body ? 0 : kB, 0, hazeL, hazeR, hazed(stripFill, hazePeriod), fade, chamL: chamL);
      // 무늬(빗금 · 점)는 색줄 아랫변의 금 위에서 멈춘다 — 무늬가 나중에 찍혀 그 금을 덮으면 금이 파선처럼 보였다(건의 4번의 헷갈림과 같은 꼴).
      final patternEnd = body ? bt : stripEnd;
      if (tone.hatch) _steps(l, r, fade, 4, (a, z, alpha) => c.patterns.add(_hatchBand, a, top, z, patternEnd, withAlpha(tone.hatchColor, alpha), phaseX: anchor + 1, phaseY: top + 1));
      if (tone.dots) _dots(c, l, top, r, patternEnd, t.bandColor[i], fade, anchor, false);
      if (BandLook.kindOf(look) == BandKind.federation) _double(c, l, top, r, stripEnd, k1, 0, tone.edge, fade, openL, openR, false);
      if (tone.pole != 0 && !openL && !fuzzyS) _pole(c, l + 1, top + 1, stripEnd - 1, withAlpha(tone.pole, fade.base), k1);
      final claimFrom = _claimFrom[id];
      if (claimFrom != null) _claimHead(c, id, claimFrom, l, top, r, body ? bt : stripEnd - 1, fade, openR);
      if (!hazing) _zones(c, t, zones, id, l, top, r, stripEnd, k1, 0, t.bandColor[i], anchor, fade);
      if (_hotCoal != null) _coalLit(c, id, l, top, r, stripEnd, fade.base);
      if (body) {
        final midB = hasCells ? math.min(floorB, bodyB) : stripB;
        final cells = hasCells && midB > stripB + .5;
        final last = cells && midB >= bodyB - .5;
        if (cells) _fill(c, l, stripB, r, midB, 0, 0, last ? kB : 0, 0, tint, fade, chamL: chamL, paper: true);
        if (cells && hazing) _hazeEnds(c, l, stripB, r, midB, 0, 0, last ? kB : 0, 0, hazeL, hazeR, hazed(tint, hazePeriod), fade, chamL: chamL);
        if (!last) _fill(c, l, cells ? midB : stripB, r, bodyB, 0, 0, kB, 0, Look.paper, fade, chamL: chamL, paper: true);
        // 켜 사이 · 층 사이 금 — 테보다 옅게(종이와 섞은 고른 색). 색줄 아랫변 · 제 칸 뭉치 안의 층 사이(남의 층을 빼고 맞붙인 자리 — TagLook.compactOf) · 칸 뭉치 아랫변.
        final line = mixSrgb(over(tone.edge, Look.paper), Look.paper, innerLine);
        final (inL, inR) = _innerSpan(l, r, shut, openR);
        _innerOf = PaintPick.rows == FloorRule.off ? -1 : id; // 아래 가로 금의 줄을 [innerRows]에 적음(할거기 경계 파선이 건너뜀)
        _hLine(c, inL, inR, bt, line, EdgeStroke.solid, fade, anchor);
        if (cells) {
          // 그 띠에 없는 층은 맞붙이면 다음 층 윗선과 같은 y가 된다(직위 줄 더 n줄 · 시기 · 예속 여러 단 — 서고 미리보기 `_bandGeo`는 띠가 가진 층만
          // floorTops에 넣는다) — 같은 금을 두 번 그으면 옅은 끝 · 흐림(알파 < 1)에서 그 금만 짙어지므로 한 번만(층 윗변은 오름차순 · 맞붙여도 오름차순).
          // 직위 줄 더 층이 이 겹침을 늘렸으므로 스위치 `office`에 건다 — 끄면 예전 그대로(끈 찍기 ↔ 바탕 바이트 같음 증명을 지킴).
          final once = PaintPick.office;
          var drawn = double.negativeInfinity;
          for (final y0 in geo.floorTops) {
            final y = v.yOf(base + (oldStore ? y0 : TagLook.compactOf(geo, look, y0, sub: sub)));
            if (y > stripB + .5 && y < midB - .5 && (!once || (y - drawn).abs() > .5)) {
              _hLine(c, inL, inR, y, line, EdgeStroke.solid, fade, anchor);
              c.debug?.note('층금', '$id ${(y * 10).round()}');
              drawn = y;
            }
          }
          if (!last) _hLine(c, inL, inR, midB, line, EdgeStroke.solid, fade, anchor);
        }
        _innerOf = -1;
      }
    }
    final matched = _em.look.filtered && (_em.look.bands?.contains(id) ?? false);
    final edge = matched ? _warn : (id == (hotBand ?? c.scene.hoverBand) ? mixOklab(tone.edge, Look.ink, .82) : tone.edge);
    final plain = tagEnd == TagEnd.plain && !matched && edge == tone.edge;
    if (!c.hide.contains('bandEdge') && !plain) {
      // 파선 · 점선 테는 몸통 안 가로 금의 줄을 함께 넘겨 T자를 닫는다([_dashTees] — 맞닿음일 때만 적힌 줄).
      _edges.add(_EdgeJob(l, top, r, bottom, k1, 0, kB, 0, fade, edge, stroke, openL, openR, anchor,
          chamL: chamL, rows: stroke.dash > 0 ? innerRows[id] : null, teeL: !shut, hazeL: hazeL, hazeR: hazeR, hazeArgb: hazing ? hazed(edge, hazePeriod) : 0));
    }
    _hits.add(_HitBox(l, top, r, bottom, id, row, false));
    c.stats.shapes++;
    c.debug?.bands.add(DebugBand(id, ui.Rect.fromLTRB(l, top, r, bottom), k1 > 0, false, fuzzyS, false));
    c.debug?.note('띠', '$id 한 장 색줄=${(stripB - top).round()} 몸통=${body ? (bodyB - stripB).round() : 0} 칸=$hasCells');
  }

  /// 띠 자체의 주장(정통성 넷 가 다듬은 꼴 lg2-ga — 칸 그림 갈래 걸음 3 · 다듬기 판 object의 `o.lst === 'claim'`): 이름 색줄 바탕(칠 위)에
  /// 1px 화소 빗금(먹 25 — [LegitLook.hatch]) — 가로는 이름 끝 + 6([from] · 구멍과 이름 둘레는 띠 칠 그대로)부터 오른쪽 테 안까지(이 타일 조각 안),
  /// 세로는 윗 테 아래 ~ 색줄 아랫금 위([bottom] — 몸통이 없으면 아래 테 위). 옅은 끝 · 조명 · 흐림은 띠 칠과 같은 계단([_steps]).
  /// 머리의 이름 · 출처 글 · 실권 밑줄은 이 뒤(테두리 걸음)에 그 위로 그린다.
  void _claimHead(PaintContext c, int id, double from, double l, double top, double r, double bottom, _Fade fade, bool openR) {
    final x0 = math.max(from, l).ceilToDouble(), x1 = (openR ? r : r - 1).floorToDouble();
    final y0 = top + 1;
    if (x1 - x0 < 1 || bottom - y0 < 1) return;
    final phase = LegitLook.phaseX(c.v.xOf(0));
    _steps(x0, x1, fade, 4, (a, z, alpha) => c.patterns.add(LegitLook.hatch, a, y0, z, bottom, CanvasInk.alpha(LegitLook.hatchInk, alpha), phaseX: phase, phaseY: top));
    c.stats.shapes++;
    c.debug?.note('주장머리', '$id ${(x0 * 10).round()},${(y0 * 10).round()},${((x1 - x0) * 10).round()},${((bottom - y0) * 10).round()}');
  }

  /// 이 띠에 걸린 기간 조명 구간(화면 px)과 그 진행. 흐린 띠 안에서도 조명 구간만 밝게 남는 [em.Look.lit]일 때 갈라 칠한다.
  /// 흐르는 동안에는 켜지는 구간과 꺼지는 구간이 함께 오고 저마다 [em.Spot.glow]를 싣는다 — 다 꺼진 것은 버린다.
  ///
  /// 조명이 꺼진 뒤에도(창을 닫아 구간을 거두면) 아직 옅어지는 구간은 남는다 — 명세 06의 3-3 '물러남'(160ms · css `.lit-out`).
  /// 그것은 [em.Look.spots]에서 빠졌는데도 [em.Emphasis.spotsOf]에 진행이 줄며 남아 있는 구간이다.
  /// 거꾸로 `lit`이 꺼진 채 **새로 온** 구간은 조명이 아니므로 밝히지 않는다.
  List<(double, double, double)> _spotsOn(PaintContext c, int id, double l, double r) {
    if (!_litFrame) return const [];
    final lit = _em.look.lit;
    List<(double, double, double)>? out;
    for (final s in _em.spotsOf(id)) {
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

  /// 조명 구간의 밝기 — 켜져 있는 동안은 [em.Emphasis.spotAlpha](흐린 띠 안에서도 1)이고,
  /// 거두는 동안에도 같은 1이다(진행이 1 → 0으로 줄며 `base + (1 − base) × glow`가 띠의 밝기로 내려간다).
  double _spotAlpha(int id, int row) => _em.look.lit ? _em.spotAlpha(id, row) : 1;

  /// 고른 띠의 ink 선: 띠의 바깥 1px(css의 `box-shadow: 0 0 0 1px`). 모서리는 띠의 반지름을 따르고,
  /// 타일 · 화면에 잘린 쪽([openL] · [openR])은 선을 멀리 늘린 뒤 조각의 폭으로 잘라 이웃 조각의 선과 이음매 없이 이어지게 한다.
  void _ring(PaintContext c, double l, double t, double r, double b, double radiusL, double radiusR, double radiusLB, double radiusRB, bool openL, bool openR) {
    ui.Radius corner(double radius) => ui.Radius.circular(radius > 0 ? radius + .5 : 0);
    final box = ui.RRect.fromLTRBAndCorners(
      openL ? l - 600 : l - .5, t - .5, openR ? r + 600 : r + .5, b + .5,
      topLeft: corner(radiusL), topRight: corner(radiusR), bottomLeft: corner(radiusLB), bottomRight: corner(radiusRB),
    );
    c.canvas.save();
    c.canvas.clipRect(ui.Rect.fromLTRB(openL ? l : l - 2, t - 2, openR ? r : r + 2, b + 2));
    c.canvas.drawRRect(box, _ringPen);
    c.canvas.restore();
  }

  /// 꼬리표의 고른 띠 먹 선(갈래 E): 띠 바깥 1px — 오른쪽은 직각, 왼쪽 두 귀는 모따기([chamL]) 또는 둥근 끝([radiusL]).
  /// 길(Path) 없이 네모 묶음 · 그림판 조각으로 — 모따기는 한 칸 큰 조각, 둥근 끝은 1px 호. 잘린 쪽([openL] · [openR])은 세로 선이 없다.
  /// [radiusTop]이 있으면 왼쪽 위 귀만 그 크기(받침 카드까지 감싼 테가 카드의 귀를 두를 때 — 흠 ② 고침 · [_ringOf]).
  void _tagRing(PaintContext c, double l, double t, double r, double b, double radiusL, bool chamL, bool openL, bool openR, {double? radiusTop}) {
    const ink = Look.ink;
    final x0 = l - 1, y0 = t - 1, x1 = r + 1, y1 = b + 1;
    final cr = openL || radiusL <= 0 ? 0.0 : radiusL + 1;
    final ct = radiusTop == null ? cr : (openL || radiusTop <= 0 ? 0.0 : radiusTop + 1);
    c.quads.hLine(x0 + ct, x1, y0, ink);
    c.quads.hLine(x0 + cr, x1, y1 - 1, ink);
    if (!openL) c.quads.vLine(x0, y0 + ct, y1 - cr, ink);
    if (!openR) c.quads.vLine(x1 - 1, y0, y1, ink);
    if (ct > 0) sprites.add(chamL ? BandSprites.chamEdge(ct) : BandSprites.arc(ct), BandCorner.topLeft, x0, y0, ink, ct);
    if (cr > 0) sprites.add(chamL ? BandSprites.chamEdge(cr) : BandSprites.arc(cr), BandCorner.bottomLeft, x0, y1 - cr, ink, cr);
  }

  /// 고른 띠의 먹 선을 긋는다 — 흠 ② 고침(4단계 감독 고름 G5 #8 흠 라 · 설계 4-6 #8 · 고르기 판 `g-g5-8.js` pickRing — 스위치 `flaw`): 예전 테는 꼬리표만
  /// 감싸 받침 카드의 드러난 윗단([sheetRise])을 가로질렀다. 이 장면에 받침 카드를 깐 띠([paintHostSheets]와 같은 거름 — 상국 탭의 카드 · 연합 겹 탭 빼고)는
  /// 테가 카드까지 감싼다: 위 = 카드 윗변 − 1 · 오른쪽 = 카드와 띠 가운데 큰 쪽 + 1(이 조각이 오른쪽에서 잘렸으면 조각 끝) · 왼쪽 귀 = 띠의 끝 꼴
  /// (카드가 띠 첫머리에 섰으면 위 귀는 카드의 귀를 두른다). 상국 탭은 띠 테두리 걸음([paintEdges])에서 그려 테 위에 온다. 굵기는 1 그대로
  /// (앱 B안 2026-10-13 — 목업의 1.5는 감독 확인 전 바꾸지 않음). 카드가 없거나 스위치를 끄면 예전 [_tagRing] 그대로.
  void _ringOf(PaintContext c, int band, int row, double l, double t, double r, double b, double radiusL, bool chamL, bool openL, bool openR, TagEnd end, double h) {
    final card = PaintPick.flaw ? _cardOf(c, band, row, t) : null;
    if (card == null) {
      _tagRing(c, l, t, r, b, radiusL, chamL, openL, openR);
      return;
    }
    final right = openR ? r : math.max(r, card.right);
    final top = card.atL && radiusL > 0 ? _tagCorner(end, h) : radiusL;
    _tagRing(c, l, card.top, right, b, radiusL, chamL, openL, openR, radiusTop: top);
    c.debug?.note('고른테', '$band ${(l - 1).toStringAsFixed(1)},${(card.top - 1).toStringAsFixed(1)},${(right + 1).toStringAsFixed(1)},${(b + 1).toStringAsFixed(1)} 카드');
  }

  /// 띠 [band](줄 [row] · 띠 윗변 [top])가 이 장면에 깐 받침 카드의 윗변 · 오른쪽 끝 · 띠 첫머리에 섰는가([paintHostSheets]의 거름 그대로). 없으면 null.
  ({double top, double right, bool atL})? _cardOf(PaintContext c, int band, int row, double top) {
    if (c.layout.bird || c.hide.contains('tabs')) return null;
    final segs = _hostSegs[band];
    if (segs == null || _em.bandAlpha(band, row) <= 0) return null;
    final bandL = _joinedLeft[band] ?? (c.left - 40);
    double? right;
    var atLeft = false;
    for (final s in segs.values) {
      if (s.look == coalLook || s.row != row) continue;
      final atL = s.left <= bandL + .5;
      final l0 = s.left + (atL ? sheetShift : 0), r0 = l0 + (s.right - s.left);
      if (r0 < c.left - sheetRadius || l0 > c.w + sheetRadius || r0 - l0 < 1) continue;
      if (right == null || r0 > right) right = r0;
      if (atL) atLeft = true;
    }
    return right == null ? null : (top: top - sheetRise, right: right, atL: atLeft);
  }

  /// 띠 [band](줄 [row])의 윗변 위가 가로 [x] ± [half]에서 무엇에 덮이는가 — 관계선 층의 위로 드는 획(명세 04 3-7 · 스위치 route · 이어 주는 선 검증 지적):
  /// **0** 비었음 · **1** 받침 카드의 드러난 윗단([sheetRise])만(카드는 띠 뒤 선보다 위 판이라 관문을 카드 윗변까지 잇는다) ·
  /// **2** 상국 탭 · 연합 겹 탭이 설 수 있는 자리(그 획을 고르지 않는다). 거름은 [paintHostSheets] · [_paintHostTabs] · [_paintCoalTabs]와 같고,
  /// 탭의 자리는 앞 탭 · 제 이름 탭에 밀려 빠지는 경우를 보지 않아 넉넉히 본다(탭이 실제로 서지 않아도 2일 수 있다).
  int overTop(PaintContext c, int band, int row, double x, double half) {
    if (c.layout.bird || c.hide.contains('tabs')) return 0;
    final segs = _hostSegs[band];
    if (segs == null || _em.bandAlpha(band, row) <= 0) return 0;
    if (row < 0 || row >= c.layout.rowCount || !c.layout.hasBody(row) || c.layout.spec(row)?.kind == RowKind.foldedGroup) return 0;
    final lo = x - half, hi = x + half;
    final bandL = _joinedLeft[band] ?? (c.left - 40);
    // 이번 장면에 실제로 선 탭(시작 쪽 · 첫 글자 · 점 — [_hostSpotsOf] · 플래그를 놓은 뒤면 연합 겹 탭도)은 늘 막는다.
    if (_heads[band]?.row == row) {
      for (final (a, b) in hostTabSpans(c, band)) {
        if (lo < b && hi > a) return 2;
      }
    }
    // 플래그가 설 수 있는 자리(띠 시작 + 16 · 폭 14) — 연합 겹 탭은 그 뒤로 밀릴 수 있다([_coalSpotsOf] · 길 셈은 플래그를 놓기 전).
    final flagSlot = (math.max(bandL, c.left) + FlagLook.from).roundToDouble() + FlagLook.w + Look.tabGap;
    var out = 0;
    for (final s in segs.values) {
      if (s.row != row) continue;
      final w0 = c.text.widthOf(s.name, hostLook);
      if (s.look == coalLook) {
        // 연합 겹 탭: 가담이 시작한 해(띠 첫머리 · 화면 왼쪽 안 [Look.tabInset]보다 앞이면 그 자리)에서 이름 폭 + 안 여백 + 뒤 장 어긋남 —
        // 플래그 뒤로 밀린 자리까지 넉넉히.
        if (!_coalOn || w0 == null) continue;
        final l = math.max(s.left, math.max(bandL, c.left + Look.tabInset));
        final pushed = math.max(l, flagSlot);
        if (lo < pushed + w0 + 2 * coalPad + coalBackDx && hi > l) return 2;
        continue;
      }
      final atL = s.left <= bandL + .5;
      final l0 = s.left + (atL ? sheetShift : 0), r0 = l0 + (s.right - s.left);
      if (r0 - l0 < 1 || hi <= l0 || lo >= r0) continue;
      // 상국 탭: 뒤 장 끝 − [sheetRadius](화면 오른쪽 밖이면 화면 끝 안)에서 왼쪽으로 이름 폭 + 14.
      if (w0 != null) {
        final right = math.min(r0 - sheetRadius, c.w - Look.tabInset);
        if (lo < right && hi > right - w0 - 14) return 2;
      }
      out = 1;
    }
    return out;
  }

  final _ringPen = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const ui.Color(Look.ink);

  /// 띠의 채움: 둥근 모서리는 조각으로, 나머지는 네모로. 옅은 끝은 네모의 꼭짓점 색으로 번지게 한다.
  /// 위와 아래의 반지름이 다를 수 있다(바탕 문화 `12 12 10 10`).
  /// [chamL]이면 왼쪽 두 귀가 둥근 대신 모따기다(꼬리표 갈래 E — 반지름 자리에 모따기 크기).
  /// [paper]면 아래의 연도 세로줄을 가리는 종이로 칠한다(리메이크 4단계 세로줄 얹기 — paint/grounds.dart): 알파가 1보다 작은 칠(흐린 띠 .58 · .2 ·
  /// 조명 구간 · 미정 꼬리 · 문화 띠 끝 · 바탕 문화 9%)을 그 자리 바탕색과 섞은 불투명 색으로 — 투명으로 사라지던 끝은 그 자리 바탕색으로 녹는다.
  /// 보이는 색은 바탕이 단색이면 예전 합성과 같다(±1). [register]면 칠한 네모를 바탕 칸으로 등록한다(바탕 문화 — 그 위에 얹는 것이 이 빛과 섞이게).
  /// 겹줄([_double]) · 무늬 · 테는 칠 위라 paper가 아니다.
  /// paper면 반투명이던 귀는 밑 조각([_underSprites] — 무늬 · 깃대보다 먼저 나감)으로, 띠 끝이 px 사이에 선 기둥에는 밑 종이([_edgePaper])를 깐다.
  void _fill(PaintContext c, double l, double t, double r, double b, double radiusL, double radiusR, double radiusLB, double radiusRB, int fill, _Fade fade,
      {bool chamL = false, bool paper = false, bool register = false}) {
    // 귀 조각 — paper면 그 귀 칸 가운데의 바탕색과 섞는다(조각은 한 색이라 귀 칸 하나에 바탕 하나). 섞은 귀(반투명이던 귀)는 밑 조각으로:
    // 나중에 나가는 조각 묶음에 두면 불투명 종이가 귀 칸 안의 제 빗금 · 점무늬 · 깃대를 네모나게 지운다(세로줄 얹기 검토 — 예전 반투명 귀는 비쳤다).
    // 처음부터 불투명한 귀는 예전 묶음 그대로(바이트 같음).
    void corner((double, double, double) cell, BandCorner where, double left, double top, double x, double k) {
      final argb = withAlpha(fill, fade.alphaAt(x));
      if (paper && (argb >>> 24) != 0xff) {
        _underSprites.add(cell, where, left, top, c.grounds.over(argb, x, top + k / 2), k);
      } else {
        sprites.add(cell, where, left, top, argb, k);
      }
    }

    if (paper) {
      _edgePaper(c, l, t + radiusL, b - radiusLB, left: true);
      _edgePaper(c, r, t + radiusR, b - radiusRB, left: false);
    }
    if (radiusL > 0) corner(chamL ? BandSprites.chamFill(radiusL) : BandSprites.disc, BandCorner.topLeft, l, t, l + radiusL / 2, radiusL);
    if (radiusLB > 0) corner(chamL ? BandSprites.chamFill(radiusLB) : BandSprites.disc, BandCorner.bottomLeft, l, b - radiusLB, l + radiusLB / 2, radiusLB);
    if (radiusR > 0) corner(BandSprites.disc, BandCorner.topRight, r - radiusR, t, r - radiusR / 2, radiusR);
    if (radiusRB > 0) corner(BandSprites.disc, BandCorner.bottomRight, r - radiusRB, b - radiusRB, r - radiusRB / 2, radiusRB);
    final wideL = math.max(radiusL, radiusLB), wideR = math.max(radiusR, radiusRB);
    if (wideL > 0) {
      _band(c, l, t + radiusL, l + wideL, b - radiusLB, fill, fade, paper: paper, register: register);
      if (radiusL < wideL) _band(c, l + radiusL, t, l + wideL, t + radiusL, fill, fade, paper: paper, register: register);
      if (radiusLB < wideL) _band(c, l + radiusLB, b - radiusLB, l + wideL, b, fill, fade, paper: paper, register: register);
    }
    if (wideR > 0) {
      _band(c, r - wideR, t + radiusR, r, b - radiusRB, fill, fade, paper: paper, register: register);
      if (radiusR < wideR) _band(c, r - wideR, t, r - radiusR, t + radiusR, fill, fade, paper: paper, register: register);
      if (radiusRB < wideR) _band(c, r - wideR, b - radiusRB, r - radiusRB, b, fill, fade, paper: paper, register: register);
    }
    _band(c, l + wideL, t, r - wideR, b, fill, fade, paper: paper, register: register);
  }

  /// 띠 끝 [x]가 px 사이에 서면 그 끝 기둥(⌊x⌋)은 칠이 일부만 덮어(가장자리가 부드러워) 맨 아래 연도 세로줄이 그만큼 비친다 — 흐린 띠의 반투명
  /// 세로 테 · 점선 테의 틈이 그 기둥에 서면 테 한 줄 내내 점선이 비친다(세로줄 얹기 검토). 그 기둥의 [y0] ~ [y1](귀 칸 빼고 · 정수 px 안쪽)에
  /// 그 자리 바탕색 종이를 밑 종이 묶음(c.under — 이 걸음의 네모보다 먼저)에 한 줄 깐다. 같은 기둥을 이웃 띠가 나눠 덮어도 둘 다 이 종이 위에 섞인다.
  /// 왼쪽 끝 기둥은 늘(세로 테가 그 기둥에 선다 — 띠의 테 기둥), 오른쪽 끝 기둥(세로 테는 그 앞 기둥)은 칠이 반 넘게 덮을 때만 — 조금만 덮인
  /// 기둥은 띠 밖이라 그 자리의 연도 세로줄 · 띠에 닿는 관계선 끝이 그대로 남는다.
  static void _edgePaper(PaintContext c, double x, double y0, double y1, {required bool left}) {
    final col = x.floorToDouble(), f = x - col;
    if (f < .01) return; // 정수 px 끝 — 왼쪽 끝은 그 기둥을 다 덮고, 오른쪽 끝은 그 기둥에 닿지 않는다.
    if (!left && f < .5) return;
    final a = y0.ceilToDouble(), z = y1.floorToDouble();
    if (z <= a) return;
    c.grounds.paper(c.under, col, a, col + 1, z);
  }

  /// 옅은 끝 · 조명 구간을 지나는 네모 하나 — 꺾이는 자리에서 잘라 꼭짓점 색으로 번지게 한다.
  /// [paper]면 두 끝 색을 그 자리 바탕색과 섞은 불투명 그러데이션으로(paint/grounds.dart — 바탕 칸 경계에서 나눠 섞는다), [register]면 칠한 몫을 바탕 칸으로 등록한다.
  void _band(PaintContext c, double l, double t, double r, double b, int argb, _Fade fade, {bool paper = false, bool register = false}) {
    if (r <= l || b <= t) return;
    if (fade.flat) {
      final color = withAlpha(argb, fade.base);
      if (paper) {
        c.grounds.fill(c.quads, l, t, r, b, color, register: register);
      } else {
        c.quads.add(l, t, r, b, color);
      }
      return;
    }
    final cuts = <double>[l, r];
    for (final x in fade.cuts) {
      if (x > l && x < r) cuts.add(x);
    }
    cuts.sort();
    for (int k = 0; k + 1 < cuts.length; k++) {
      final a = cuts[k], z = cuts[k + 1];
      if (z - a < .01) continue;
      final (ca, cz) = fade.alphaSpan(a, z);
      if (paper) {
        c.grounds.fade(c.quads, a, t, z, b, withAlpha(argb, ca), withAlpha(argb, cz), register: register);
      } else {
        c.quads.addFade(a, t, z, b, withAlpha(argb, ca), withAlpha(argb, cz));
      }
    }
  }

  /// 무늬 · 선처럼 한 칸에 색이 하나뿐인 것을 위해 [l]~[r]을 밝기가 고른 칸들로 나눈다
  /// (조명 경계에서 끊고, 옅은 두 끝은 [steps]칸의 계단으로).
  static void _steps(double l, double r, _Fade fade, int steps, void Function(double a, double z, double alpha) draw) {
    if (r <= l) return;
    if (fade.flat) {
      if (fade.base > .004) draw(l, r, fade.base);
      return;
    }
    final marks = <double>[l, r];
    void mark(double x) {
      if (x > l && x < r) marks.add(x);
    }

    for (final x in fade.cuts) {
      mark(x);
    }
    for (int k = 1; k < steps; k++) {
      if (fade.left > 0) mark(fade.l + fade.left * k / steps);
      if (fade.right > 0) mark(fade.r - fade.right * k / steps);
    }
    marks.sort();
    for (int k = 0; k + 1 < marks.length; k++) {
      final a = marks[k], z = marks[k + 1];
      if (z - a < .01) continue;
      final alpha = fade.alphaAt((a + z) / 2);
      if (alpha > .004) draw(a, z, alpha);
    }
  }

  /// 연맹의 속 빈 겹줄: 테두리 안쪽으로 종이빛 2px · 테 55% 1px 고리(C:787).
  /// 조감(모양 a · b)에서는 종이빛도 1px이다(C:1772 — 모양 c는 겹줄 자체가 없다).
  /// 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off가 아니면): 고리는 띠 테의 열([_edge] — floor(l) · floor(r − 1))에서 [inset]만큼
  /// 안쪽 정수 열에 두고, 직각 귀(반지름 0)에서는 세로 변이 가로 변 사이에서만 — 귀 픽셀을 두 변이 함께 칠해 55% 고리에 짙은 점이 생기지 않게.
  void _double(PaintContext c, double l, double t, double r, double b, double radiusL, double radiusR, int edge, _Fade fade, bool openL, bool openR, bool bird) {
    final joint = PaintPick.rows != FloorRule.off;
    for (final (inset, width, argb, cell) in [(1.0, bird ? 1.0 : 2.0, Look.paper, BandSprites.fedOuter), (bird ? 2.0 : 3.0, 1.0, withAlpha(edge, .55), BandSprites.fedInner)]) {
      final x0 = openL ? l : (joint ? l.floorToDouble() : l) + inset, x1 = openR ? r : (joint ? (r - 1).floorToDouble() + 1 : r) - inset;
      final y0 = t + inset, y1 = b - inset;
      if (x1 - x0 <= 2 * width || y1 - y0 <= 2 * width) continue;
      final rl = openL ? 0.0 : math.max(0.0, math.min(radiusL - inset, cell.$3 / 2)), rr = openR ? 0.0 : math.max(0.0, math.min(radiusR - inset, cell.$3 / 2));
      final sl = rl > 0 || !joint ? rl : width, sr = rr > 0 || !joint ? rr : width; // 세로 변이 비켜 갈 위아래 몫
      _band(c, x0 + rl, y0, x1 - rr, y0 + width, argb, fade);
      _band(c, x0 + rl, y1 - width, x1 - rr, y1, argb, fade);
      if (!openL) _band(c, x0, y0 + sl, x0 + width, y1 - sl, argb, fade);
      if (!openR) _band(c, x1 - width, y0 + sr, x1, y1 - sr, argb, fade);
      final la = withAlpha(argb, fade.alphaAt(x0 + rl)), ra = withAlpha(argb, fade.alphaAt(x1 - rr));
      if (rl > 0) {
        sprites.add(cell, BandCorner.topLeft, x0, y0, la, rl);
        sprites.add(cell, BandCorner.bottomLeft, x0, y1 - rl, la, rl);
      }
      if (rr > 0) {
        sprites.add(cell, BandCorner.topRight, x1 - rr, y0, ra, rr);
        sprites.add(cell, BandCorner.bottomRight, x1 - rr, y1 - rr, ra, rr);
      }
    }
  }

  /// 부흥·저항 세력의 깃대: 띠 안쪽 왼쪽 3px(C:1274). 둥근 모서리를 따라 1px 기둥 셋으로 깎는다.
  void _pole(PaintContext c, double l, double t, double b, int argb, double radius) {
    final rr = math.min(radius, (b - t) / 2);
    for (int k = 0; k < 3; k++) {
      final cut = _inset(rr, k + .5);
      c.quads.add(l + k, t + cut, l + k + 1, b - cut, argb);
    }
  }

  /// 문화 띠 · 바탕 문화의 점무늬(9px 격자 · 반지름 1.5). css의 원 자리(20%/40% · 30%/40%)만큼 어긋나게 둔다.
  void _dots(PaintContext c, double l, double t, double r, double b, int rgb, _Fade fade, double anchor, bool under) {
    final dot = withAlpha(0xff000000 | rgb, under ? .40 : .22);
    final ox = 9 * (.5 - (under ? .30 : .20)), oy = 9 * (.5 - .40);
    // 옅은 두 끝 · 조명 경계에서는 무늬도 함께 갈린다 — 무늬 한 칸에 색이 하나뿐이라 몇 칸으로 나눈다.
    _steps(l, r, fade, 5, (a, z, alpha) => c.patterns.add(_dotGrid, a, t, z, b, withAlpha(dot, alpha), phaseX: anchor + ox, phaseY: t + oy));
  }

  /// 연대 폭(구역 19): 띠 안쪽에 그 구간만 무늬 — 추정은 세로 줄, 전승은 빗금. 양옆 경계는 1px 파선(명세 1-4 나).
  void _zones(PaintContext c, Tile t, TileSection zones, int id, double l, double top, double r, double b, double radiusL, double radiusR, int rgb, double anchor, _Fade fade) {
    final list = _zoneOf[id];
    if (list == null) return;
    final v = c.v, origin = t.origin.toDouble();
    final ox = l + 1, iw = math.max(0.0, r - l - 2), y0 = top + 1, y1 = b - 1;
    if (iw <= 0 || y1 <= y0) return;
    final color = 0xff000000 | rgb;
    final soft = mixOklab(color, Look.ink, .92);
    final x0s = zones.f(Tile.itemX0), x1s = zones.f(Tile.itemX1), bs = zones.u(Tile.itemB), cut = zones.u(Tile.itemFlags);
    for (final z in list) {
      // 타일 끝에서 잘린 연대 폭 조각은 띠의 그쪽 끝까지 — 띠가 앞(뒤) 타일의 몫으로 넓어졌으면([_paintBand]) 무늬도 따라 깐다.
      final zl = cut[z] & Tile.clipLeft != 0 ? ox : math.max(v.xOf(origin + x0s[z]), ox);
      final zr = cut[z] & Tile.clipRight != 0 ? ox + iw : math.min(v.xOf(origin + x1s[z]), ox + iw);
      if (zr - zl <= .5) continue;
      final atS = zl <= ox + .5, atE = zr >= ox + iw - .5;
      final kind = bs[z];
      // 연대 폭은 띠의 두 끝에 있어 옅은 꼬리와 겹친다 — 구간 가운데의 밝기 하나로 칠한다(무늬 한 칸에 색이 하나뿐이라).
      final alpha = fade.alphaAt((zl + zr) / 2);
      if (alpha <= .004) continue;
      // 무늬 뒤에 깔리는 바탕: 추정은 종이빛, 전승은 c 4%.
      final base = withAlpha(kind == 1 ? mixSrgb(color, Look.paper, .04) : Look.paper, alpha);
      // 띠 끝에 닿는 쪽만 띠 안쪽 모서리(10 − 1 = 9)를 따라 둥글게.
      final rl = atS ? math.max(0.0, radiusL - 1) : 0.0, rr = atE ? math.max(0.0, radiusR - 1) : 0.0;
      _rounded(c, zl, y0, zr, y1, rl, rr, rr, rl, base);
      if (kind == 0) c.patterns.add(_zoneEstimated, zl, y0, zr, y1, withAlpha(mixSrgb(color, Look.paper, .14), alpha), phaseX: anchor + 1, phaseY: y0);
      if (kind == 1) c.patterns.add(_zoneLegend, zl, y0, zr, y1, withAlpha(mixSrgb(color, Look.paper, .18), alpha), phaseX: anchor + 1, phaseY: y0);
      // 연대 폭의 경계 — 예전 파선을 옅은 실선으로(감독 건의 2026-10-15 4번 A: 끊긴 선은 관계선만).
      final rim = withAlpha(mixSrgb(soft, Look.paper, unsureEdge), alpha);
      if (!atS) c.quads.vLine(zl, y0, y1, rim);
      if (!atE) c.quads.vLine(zr - 1, y0, y1, rim);
      c.stats.shapes++;
    }
  }

  /// 몸통 안 가로 금(색줄 아랫금 · 층 사이 금 · 사건 칸 윗줄)의 두 끝 — 띠 테 바로 안쪽. 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' ·
  /// 꼴 off가 아니면 — paint_pick.dart [PaintPick.rows]): 테 세로 변의 열([_edge] — 왼쪽 floor(l) · 오른쪽 floor(r − 1)) 바로 옆 열까지 정수로.
  /// 소수 끝이면 픽셀 가운데 셈에 왼쪽은 테 옆 1열이 비고(l의 소수부 .5 넘음) 오른쪽은 테 열에 겹쳤다. 열린 쪽([openL] · [openR] — 테 없음)은 띠 끝 그대로.
  static (double, double) _innerSpan(double l, double r, bool openL, bool openR) {
    if (PaintPick.rows == FloorRule.off) return (l + (openL ? 0 : 1), r - (openR ? 0 : 1));
    return (openL ? l : l.floorToDouble() + 1, openR ? r : (r - 1).floorToDouble());
  }

  /// 가로 테(윗변 · 아랫변)의 두 끝 — 귀 반지름 [radiusL] · [radiusR]만큼 안쪽. 맞닿음(꼴 off가 아니면): 직각 귀(반지름 0)이고 그쪽 세로 테가 있으면
  /// 가로 테는 세로 테의 열 바로 옆에서 멈춘다 — 귀 픽셀은 세로 테 하나만 칠해 흐린 띠에서 먹이 두 번 얹히지 않고(짙은 점), 소수 끝이 세로 테 바깥 열로
  /// 반쯤 번지지도 않는다.
  static (double, double) _edgeSpan(_EdgeJob e, double radiusL, double radiusR) {
    final x0 = e.l + radiusL, x1 = e.r - radiusR;
    if (PaintPick.rows == FloorRule.off) return (x0, x1);
    return (radiusL <= 0 && !e.openL ? e.l.floorToDouble() + 1 : x0, radiusR <= 0 && !e.openR ? (e.r - 1).floorToDouble() : x1);
  }

  /// 세로 테(왼쪽 · 오른쪽)의 위아래 끝 — 귀 반지름 [radiusT] · [radiusB]만큼 안쪽. 맞닿음(꼴 off가 아니면): 직각 귀(반지름 0)면 가로 테의 줄
  /// ([Quads.hLine]이 내림한 윗변 floor(t) · 아랫변 floor(b − 1))에 맞춰 정수로 — 가로 테가 귀 앞에서 멈추므로([_edgeSpan]) 띠 윗변이 소수 자리
  /// (관성 스크롤 뒤 등 — 소수부 .5 이상)면 귀 픽셀을 칠하는 쪽이 없었고, 아랫변 밑으로는 세로 테가 반 줄 삐져나왔다.
  static (double, double) _sideSpan(_EdgeJob e, double radiusT, double radiusB) {
    if (PaintPick.rows == FloorRule.off) return (e.t + radiusT, e.b - radiusB);
    return (radiusT > 0 ? e.t + radiusT : e.t.floorToDouble(), radiusB > 0 ? e.b - radiusB : (e.b - 1).floorToDouble() + 1);
  }

  /// 세로 테 무늬(파선 · 점선)가 시작하는 자리 — 꼴 off는 띠 윗변 그대로, 맞닿음이면 윗변 줄(정수)에서: 무늬 끝이 픽셀 사이에 서지 않고, 윗변 줄은
  /// 늘 칠한 차례라 위 귀가 비지 않는다([_dashCorners] · [_dashTees]가 같은 자리로 빈 줄을 셈).
  static double _dashPhase(_EdgeJob e) => PaintPick.rows == FloorRule.off ? e.t : e.t.floorToDouble();

  /// 세로 테 무늬가 줄 [y](정수)를 칠하는가 — 무늬는 [_dashPhase]에서 dash 긋고 gap 띄운다.
  static bool _dashOn(_EdgeJob e, double y) {
    final period = e.stroke.dash + e.stroke.gap;
    return ((y - _dashPhase(e)) % period + period) % period < e.stroke.dash;
  }

  /// 파선 · 점선 테의 직각 아래 귀(맞닿음 · 꼴 off가 아니면): 가로 변은 귀 앞에서 멈추므로([_edgeSpan]) 귀 픽셀은 세로 변의 무늬가 맡는데, 무늬는 윗변
  /// 줄에서 시작해([_dashPhase]) 아랫변 줄에서는 빌 수 있다 — 그때 귀 픽셀 하나를 따로 칠해 귀가 열려 보이지 않게(한 번만).
  void _dashCorners(PaintContext c, _EdgeJob e) {
    if (PaintPick.rows == FloorRule.off || e.stroke.dash <= 0) return;
    final y = (e.b - 1).floorToDouble();
    if (_dashOn(e, y)) return;
    if (!e.openL && e.radiusLB <= 0) c.quads.add(e.l.floorToDouble(), y, e.l.floorToDouble() + 1, y + 1, withAlpha(e.argb, e.fade.alphaAt(e.l)));
    if (!e.openR && e.radiusRB <= 0) c.quads.add((e.r - 1).floorToDouble(), y, (e.r - 1).floorToDouble() + 1, y + 1, withAlpha(e.argb, e.fade.alphaAt(e.r)));
  }

  /// 파선 · 점선 테와 몸통 안 가로 금(색줄 아랫금 · 층 사이 금 · 사건 칸 윗줄 — [_EdgeJob.rows])이 만나는 T자(맞닿음 · 꼴 off가 아니면 —
  /// 감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게'): 가로 금은 테 열 바로 옆에서 멈추므로([_innerSpan]) 테 무늬가 그 줄에서 비면 만나는 점이
  /// 빈 채로 남았다(가로 금이 테의 빈 칸에서 끝남) — 그 점 하나를 테 빛깔로 칠한다([_dashCorners]와 같은 길 · 무늬가 빈 줄에만이라 먹은 한 번).
  /// 세로 테가 있는 줄(귀 반지름 밖 · 윗변 줄과 아랫변 줄 사이)만.
  void _dashTees(PaintContext c, _EdgeJob e) {
    final rows = e.rows;
    if (rows == null || rows.isEmpty || PaintPick.rows == FloorRule.off || e.stroke.dash <= 0) return;
    final top = e.t.floorToDouble(), bottom = (e.b - 1).floorToDouble();
    final xl = e.l.floorToDouble(), xr = (e.r - 1).floorToDouble();
    for (final y in rows) {
      if (y <= top || y >= bottom || _dashOn(e, y)) continue;
      final mid = y + .5;
      if (e.teeL && !e.openL && mid >= e.t + e.radiusL && mid <= e.b - e.radiusLB) {
        c.quads.add(xl, y, xl + 1, y + 1, withAlpha(e.argb, e.fade.alphaAt(e.l)));
      }
      if (!e.openR && mid >= e.t + e.radiusR && mid <= e.b - e.radiusRB) {
        c.quads.add(xr, y, xr + 1, y + 1, withAlpha(e.argb, e.fade.alphaAt(e.r)));
      }
    }
  }

  /// 띠의 테두리: 곧은 변은 네모 묶음(점선 · 파선은 dash/gap), 둥근 모서리는 1px 호 조각. 가로 변의 끝은 [_edgeSpan] · 세로 변의 끝은 [_sideSpan].
  void _edge(PaintContext c, _EdgeJob e) {
    final (t0, t1) = _edgeSpan(e, e.radiusL, e.radiusR);
    final (b0, b1) = _edgeSpan(e, e.radiusLB, e.radiusRB);
    _edgeH(c, e, t0, t1, e.t);
    _edgeH(c, e, b0, b1, e.b - 1);
    final phase = _dashPhase(e);
    // 흐림의 끝 구간이 닿은 쪽은 세로 테 · 귀도 흐린 빛깔(끔이면 폭이 0이라 늘 제 빛깔).
    final argbL = e.hazeL > 0 ? e.hazeArgb : e.argb, argbR = e.hazeR > 0 ? e.hazeArgb : e.argb;
    if (!e.openL) {
      final (y0, y1) = _sideSpan(e, e.radiusL, e.radiusLB);
      c.quads.vLine(e.l, y0, y1, withAlpha(argbL, e.fade.alphaAt(e.l)), dash: e.stroke.dash, gap: e.stroke.gap, phase: phase);
    }
    if (!e.openR) {
      final (y0, y1) = _sideSpan(e, e.radiusR, e.radiusRB);
      c.quads.vLine(e.r - 1, y0, y1, withAlpha(argbR, e.fade.alphaAt(e.r)), dash: e.stroke.dash, gap: e.stroke.gap, phase: phase);
    }
    _dashCorners(c, e);
    _dashTees(c, e);
    if (e.radiusL > 0) sprites.add(e.chamL ? BandSprites.chamEdge(e.radiusL) : BandSprites.arc(e.radiusL), BandCorner.topLeft, e.l, e.t, withAlpha(argbL, e.fade.alphaAt(e.l + e.radiusL / 2)), e.radiusL);
    if (e.radiusLB > 0) sprites.add(e.chamL ? BandSprites.chamEdge(e.radiusLB) : BandSprites.arc(e.radiusLB), BandCorner.bottomLeft, e.l, e.b - e.radiusLB, withAlpha(argbL, e.fade.alphaAt(e.l + e.radiusLB / 2)), e.radiusLB);
    if (e.radiusR > 0) sprites.add(e.chamR ? BandSprites.chamEdge(e.radiusR) : BandSprites.arc(e.radiusR), BandCorner.topRight, e.r - e.radiusR, e.t, withAlpha(argbR, e.fade.alphaAt(e.r - e.radiusR / 2)), e.radiusR);
    if (e.radiusRB > 0) sprites.add(e.chamR ? BandSprites.chamEdge(e.radiusRB) : BandSprites.arc(e.radiusRB), BandCorner.bottomRight, e.r - e.radiusRB, e.b - e.radiusRB, withAlpha(argbR, e.fade.alphaAt(e.r - e.radiusRB / 2)), e.radiusRB);
  }

  /// 가로 테 한 줄 — 흐림의 끝 구간([_EdgeJob.hazeL] · [_EdgeJob.hazeR] — 정수 px에서 끊음)은 흐린 빛깔로, 가운데는 제 빛깔로. 구간이 없으면 [_hLine] 하나.
  void _edgeH(PaintContext c, _EdgeJob e, double x0, double x1, double y) {
    if (e.hazeL <= 0 && e.hazeR <= 0) return _hLine(c, x0, x1, y, e.argb, e.stroke, e.fade, e.anchor);
    final a = e.hazeL > 0 ? math.max(x0, math.min(x1, (e.l + e.hazeL).roundToDouble())) : x0;
    final z = e.hazeR > 0 ? math.max(a, math.min(x1, (e.r - e.hazeR).roundToDouble())) : x1;
    if (a > x0) _hLine(c, x0, a, y, e.hazeArgb, e.stroke, e.fade, e.anchor);
    if (z > a) _hLine(c, a, z, y, e.argb, e.stroke, e.fade, e.anchor);
    if (x1 > z) _hLine(c, z, x1, y, e.hazeArgb, e.stroke, e.fade, e.anchor);
  }

  /// 흐림의 끝 구간 칠 — 띠 왼쪽 [hl] · 오른쪽 [hr]만큼(정수 px에서 끊어 밑 종이 기둥이 생기지 않게) 흐린 색 [fill]을 덧칠한다. 귀는 띠의 귀 그대로.
  void _hazeEnds(PaintContext c, double l, double t, double r, double b, double rl, double rr, double rlb, double rrb, double hl, double hr, int fill, _Fade fade,
      {bool chamL = false}) {
    if (hl > 0) {
      final z = math.min((l + hl).roundToDouble(), r);
      if (z - l >= 1) _fill(c, l, t, z, b, math.min(rl, z - l), 0, math.min(rlb, z - l), 0, fill, fade, chamL: chamL, paper: true);
    }
    if (hr > 0) {
      final a = math.max((r - hr).roundToDouble(), l);
      if (r - a >= 1) _fill(c, a, t, r, b, 0, math.min(rr, r - a), 0, math.min(rrb, r - a), fill, fade, paper: true);
    }
  }

  /// 가로 테두리 한 줄 — 옅은 끝 · 조명 경계를 지나면 몇 칸으로 나눠 짙기를 바꾼다.
  void _hLine(PaintContext c, double x0, double x1, double y, int argb, EdgeStroke stroke, _Fade fade, double anchor) {
    if (_innerOf >= 0) {
      // 오름차순으로 끼워 넣는다(읽는 쪽이 고르거나 베끼지 않게 — 줄은 띠마다 몇 개뿐).
      final rows = innerRows[_innerOf] ??= <double>[], row = y.floorToDouble();
      var k = 0;
      while (k < rows.length && rows[k] < row) {
        k++;
      }
      if (k == rows.length || rows[k] != row) rows.insert(k, row);
    }
    _steps(x0, x1, fade, 6, (a, z, alpha) => c.quads.hLine(a, z, y, withAlpha(argb, alpha), dash: stroke.dash, gap: stroke.gap, phase: anchor));
  }

  // ─────────────────────────── 꼬리표 머리의 이름 ───────────────────────────

  /// 꼬리표 갈래 E(설계 4-1 '실제 띠에 입힘'): 띠 위 탭 줄 대신 이름이 띠 안 **머리**(윗변에서 24의 가운데)에 든다 —
  /// 구멍 가운데에서 7 오른쪽(띠 시작이 화면 밖이면 화면 끝 6에 붙어 따라옴), 딱지(종류 · 실재성 · 지위)는 이름 뒤에 이어 붙고,
  /// 오른쪽 끝 [TagLook.nameRight] 앞까지(꼬리 마름모 자리)에 들지 않으면 첫 글자 · 없음([planTab]).
  /// 자리는 장면을 열 때 끝낸다 — 같은 장면의 단추 층이 [headNameEnd] · [headNameZones]를 읽고,
  /// 사건 이름 셈이 비켜 갈 구간을 읽는다(reserved.dart · 출처 'names').
  void _placeHeads(PaintContext c) {
    final layout = c.layout;
    final zones = <int, List<ReservedZone>>{};
    if (!layout.bird) {
      final own = {for (final d in c.scene.draw) if (!d.isCover) d.key};
      for (final d in c.scene.draw) {
        if (d.isCover && own.contains(d.key)) continue;
        final t = d.tile;
        for (int i = 0; i < t.bandCount; i++) {
          if (t.bandLook[i] & (BandLook.under | BandLook.folded) != 0) continue;
          _placeHead(c, t, i, zones);
        }
      }
    }
    ReservedZones.of(c.scene).put('names', zones);
  }

  void _placeHead(PaintContext c, Tile t, int i, Map<int, List<ReservedZone>> zones) {
    final layout = c.layout;
    final row = t.bandRow[i];
    if (row >= layout.rowCount || !layout.hasBody(row)) return;
    if (layout.spec(row)?.kind == RowKind.foldedGroup) return;
    final id = t.bandId[i];
    if (_heads.containsKey(id)) return;
    final geo = layout.geo(row);
    final top = v0(c, layout, row, geo);
    // 띠 위로 솟는 상국 · 연합 탭(줄 위 틈 몫)까지 화면에 걸치면 잰다.
    final above = layout.tabOf(row);
    // 흐르는 줄이면 몸 전체가 아니라 이름 색줄([G.head])이 보이는 몫에 들면 둔다 — 몸은 띠 층이 그 몫에서 자른다(css overflow:hidden처럼 위부터 드러남).
    if (top - above > c.h || top + geo.bandHeight < c.head || !c.fitsRow(row, top + G.head)) return;
    // 관점(lens)이 켜져 있으면 그 나라가 부르는 이름으로 적고 폭도 그 글로 잰다(자료 · 줄 쌓기에는 닿지 않는다 — 11물결 labels4 4번).
    final name = LensTitles.of(c.scene).bandTitleOf(id) ?? t.text(t.bandName[i]);
    final v = c.v, origin = t.origin.toDouble();
    final cutL = t.bandFlags[i] & Tile.clipLeft != 0;
    final realL = _joinedLeft[id] ?? (cutL ? c.left - 2 : v.xOf(origin + t.bandX0[i]));
    final realR = _joinedRight[id] ?? v.xOf(origin + t.bandX1[i]);
    if (realR < c.left - 2 || realL > c.w + 2) return;
    // 붙지 않은 자리(구멍 가운데 + 7) — 띠 시작이 화면 밖이면 이름은 화면 끝 + 6에 붙어 따라온다.
    // 구멍은 이름 색줄의 귀에 맞춘다(두 장 꼬리표) — 귀는 form의 종류 갈래로(영토 밖의 둥근 끝은 구멍 9 · 다스림 7 — [TagLook.endOfBand]).
    final form = t.bandForm[i];
    final free = realL + TagLook.holeAt(TagLook.endOfBand(t.bandLook[i], form), G.head) + TagLook.nameGap;
    final rival = TagLook.rivalOf(form), lid = _lidOf(c, t.bandLook[i], form, id);
    final l = math.max(free, c.left + Look.tabInset);
    final r = math.min(realR - TagLook.nameRight, c.w - Look.tabInset);
    // [planTab]은 탭의 몫(앞뒤 여백 14 · 어깨 [Look.tabExt])을 더해 견주므로 그만큼 얹어 넘긴다 — 머리에서는 글 · 딱지 폭만 든다.
    final plan = name.isEmpty ? TabPlan.empty : planTab(c, t, i, name, r - l + 14 + Look.tabExt);
    if (plan == null) return; // 글자 폭을 아직 잴 수 없다 — 다음 장면에.
    final base = name.isEmpty ? null : _tabBases[t]?[i];
    final sticky = l > free + .01;
    // 띠 자체의 주장(칸 그림 갈래 걸음 3 · lg2-ga): 머리 빗금은 이름 끝 + 6부터(이름이 없으면 이름 자리 + 6) — 구멍과 이름 둘레는 띠 칠 그대로.
    if (PaintPick.legit && BandForm.legitOf(form) == Schema4.legitClaim) {
      _claimFrom[id] = (plan.mode.isEmpty || base == null ? l : l + plan.nameWidth) + LegitLook.headPad;
    }
    if (plan.mode.isEmpty || base == null) {
      headNameEnd[id] = l - 4;
      final powers = _placePowers(c, id, row, realL, realR);
      _heads[id] = _Head(id, row, t.bandLook[i], 0xff000000 | t.bandColor[i], t.bandSub[i] & 7, l, top, realL, realR, plan, base, sticky: sticky, powers: powers, rival: rival, lid: lid);
      return;
    }
    // 리메이크 2부(목업 서고): 머리에는 이름만 — 종류 · 실재성 · 지위 딱지는 그리지 않는다(상세 창에서).
    final end = l + plan.nameWidth;
    headNameEnd[id] = end;
    (headNameZones[row] ??= []).add((l - 4, end + 4));
    final borrow = _placeBorrow(c, t, id, row, l, r, plan);
    final powers = _placePowers(c, id, row, realL, realR);
    _heads[id] = _Head(id, row, t.bandLook[i], 0xff000000 | t.bandColor[i], t.bandSub[i] & 7, l, top, realL, realR, plan, base, sticky: sticky, borrow: borrow, powers: powers, rival: rival, lid: lid);
    // 두 장 꼬리표(감독 결정 '두 장 ㄴ'): 이름은 색줄에, 사건은 몸통의 흰 사건 칸에 — 같은 글줄이 아니라 사건이 이름을 비켜 가지 않는다
    // (예전: 첫 글줄의 비킬 구간 · 화면 왼쪽에 붙은 이름 아래 점 숨김 — [headHides]는 빈 채로 남는다).
  }

  /// 빌린 직위 줄의 출처 글(리메이크 4단계 과제 5 걸음 2 — 서고 미리보기 `.tl-borrow` · timeline.js 8272 ~ 8278 · common.css 2497):
  /// 구역 54 가운데 지도자 · 내각 줄(a = 1 · 2)의 `· 지도자 ← 출처` · `· 내각 ← 출처`를 한 글로 머리 이름 탭 뒤에 —
  /// 자리는 미리보기의 `tabEnd`(이름 왼쪽 − [TagLook.namePad] + [TabPlan.width] + [Look.tabGap] — 탭 폭은 그리지 않는 딱지 몫까지 든 값 그대로).
  /// 꼬리 마름모 앞([r] = 띠 오른쪽 끝 − [TagLook.nameRight] · 화면 오른쪽 − 6)까지 다 들 때만 쓰고(줄여 쓰지 않는다), 같은 줄의 다른 머리 글
  /// ([headNameZones] — 이웃 띠의 이름 · 출처 글)과 겹치면 뺀다. 쓰면 그 구간(앞뒤 4)을 [headNameZones]에 더해 뒤에 놓는 머리 줄의 글
  /// (칸 층 없는 꼬리표의 집권 · 실권 이름 — strips.dart `_inlinePower`)이 비킨다. 상국 · 연합 탭은 띠 윗변 위(받침 카드 위 [sheetRise])라 머리 줄과 겹치지 않는다.
  /// 사건 이름은 두 장 꼬리표의 몸통(흰 사건 칸)에 서서 머리 줄을 지나지 않으므로 사건 이름 셈의 비킬 구간(출처 'names')에는 적지 않는다 —
  /// 머리 이름과 같은 길(미리보기도 비키지 않는다). 구역 54의 a = 9(직위 줄 더의 빌림)는 그 줄에 직위 줄 더 층이 섰을 때(스위치 `office` · 표시 '지도자' ·
  /// 줄 값) 그 줄 이름으로 뒤에 잇는다(`· 재상 ← 출처` — G7 가 · 칸 그림 갈래 걸음 4 · [_borrowTextOf]).
  /// 직위 낱말은 칸 종류로 정한다 — 구역 54에는 `leadersFrom.name`(사용자가 붙인 줄 이름)이 실리지 않아, 미리보기의 `· 등좌 ← …`가 앱에서는 `· 지도자 ← …`.
  (String, double)? _placeBorrow(PaintContext c, Tile t, int id, int row, double l, double r, TabPlan plan) {
    final text = _borrowTextOf(c, t, id, row);
    if (text == null) return null;
    final w = c.text.widthOf(text, borrowLook);
    if (w == null) {
      c.scene.requestFrame(); // 글자 폭을 아직 잴 수 없다 — 다음 장면에
      return null;
    }
    final x = l - TagLook.namePad + plan.width + Look.tabGap;
    if (x + w > r) return null;
    for (final z in headNameZones[row] ?? const <(double, double)>[]) {
      if (z.$1 < x + w && z.$2 > x) return null;
    }
    (headNameZones[row] ??= []).add((x - 4, x + w + 4));
    return (text, x);
  }

  /// 출처 글의 글꼴 — 미리보기 `.tl-borrow`: 8.5 · 보통 굵기 · 먹 55%(종이와 — 그림판 먹 단계 60).
  static final borrowLook = TextLook(8.5, ui.FontWeight.w400, CanvasInk.gray(.55));

  /// 실권 밑줄(리메이크 4단계 과제 6 — 서고 미리보기 `.tl-power-ul` · `.tl-power-name` · timeline.js 8280 ~ 8287 · common.css 2498 ~ 2499):
  /// 구역 56마다 빼앗긴 띠 머리에 2px 밑줄 — 자리는 띠 윗변 + [powerTop] ~ + [powerTop] + [powerHeight](머리 14 아랫변 바로 위),
  /// 가로는 실권 기간을 띠 상자(미정 꼬리까지 — 미리보기 x1 · x2) 안 3px 안쪽으로 자른 것이고 4px 미만이면 긋지 않는다.
  /// 빛깔은 쥔 쪽 색 80% + 먹(srgb). 끝 이름(쥔 쪽 이름)은 밑줄 오른쪽 끝 − 3에 오른쪽 맞춤 · 8 굵게 · 쥔 쪽 색 30% + 먹 · 띠 윗변 + 2의 9px 글줄 —
  /// 미리보기처럼 밑줄 폭이 이름(8.5 굵게로 잰 폭) + 8 이상일 때만, 그리고 같은 줄 머리 글([headNameZones] — 이름 · 출처 글 · 앞 밑줄의 이름)과 겹치지 않을 때만 쓴다.
  /// 쓰면 그 구간(앞뒤 4)을 [headNameZones]에 더한다(칸 층 없는 꼬리표의 집권 이름 · 소속 단추가 비킨다).
  /// 제 안의 실권자(구역 56의 a = 1 — 과제 6 걸음 1-1)는 쥔 쪽 색이 없어 밑줄 · 이름 모두 먹 — 미리보기는 이것을 그리지 않는다(`HT.f4Preview`가 over 없는 줄을 뺀다).
  /// 단체의 실권 단(칸 종류 8 · 단 3)이 그 기간에 그려지면(걸음 2 — 표시 체크 '단체' · 실권 층이 있거나 빽빽하게의 머리 줄) 밑줄은 두고 끝 이름만 뺀다.
  /// 상국 · 연합 탭은 띠 윗변 위라 머리 줄과 겹치지 않는다. 조감에는 없다(머리가 없다).
  ///
  /// 한 띠에 기간이 겹치는 실권이 둘 이상이면 **단을 나눈다**(조사 결함 31 — 예전에는 한 y에 포개져 나중 색만 보였다): 항목 번호 차례로 겹치지 않는 가장 낮은 단에 —
  /// 단 0은 띠 윗변 + [powerTop](예전 자리) · 단 1부터 [powerLane]씩 아래(색줄 아랫금 밑)이고 셋째 단부터는 파선(3 · 2). 겹침은 분 값([PowerSpan.overlaps])으로 보므로
  /// 옆으로 옮겨도 단이 흔들리지 않는다. 끝 이름은 띠 오른쪽 끝뿐 아니라 **화면 오른쪽 안**([Look.tabInset])에 붙고 들 폭도 화면에 보이는 몫으로 잰다(조사 결함 30 —
  /// 예전에는 실권 끝이 화면 밖이면 이름이 화면 밖 끝에 붙어 보이지 않았고, 실린 타일 경계가 끝으로 잡혀 옆으로 옮길 때 이름 자리가 튀었다). 밑줄은 진짜 끝까지 그대로.
  List<_PowerMark> _placePowers(PaintContext c, int id, int row, double realL, double realR) {
    final spans = powerSpans[id];
    if (spans == null) return const [];
    final v = c.v;
    final (boxL, boxR) = _boxOf(row, id, realL, realR);
    // 끝 이름은 구멍 · 꼬리 마름모 자리를 비킨다(감독 2026-10-26 수정 5) — 밑줄은 그대로 실권 끝까지.
    final (textL, textR) = headTextBounds(id, realL, realR, c.left);
    final out = <_PowerMark>[];
    // 단 나눔: 항목 번호 차례(타일과 상관없는 차례)로 겹치는 앞 실권이 없는 가장 낮은 단.
    final lanes = <int, int>{};
    final byLane = <List<PowerSpan>>[];
    for (final s in [...spans]..sort((a, b) => a.id.compareTo(b.id))) {
      var lane = 0;
      while (lane < byLane.length && byLane[lane].any((o) => s.overlaps(o.start, o.end))) {
        lane++;
      }
      if (lane == byLane.length) byLane.add(<PowerSpan>[]);
      byLane[lane].add(s);
      lanes[s.id] = lane;
    }
    for (final s in spans) {
      final a = math.max(v.xOf(s.start), boxL + 3), b = math.min(v.xOf(s.end), boxR - 3);
      if (b - a < 4) continue;
      // 끝 이름의 오른쪽 끝 · 들 폭은 화면에 보이는 몫으로 — 이름 끝(nameR − 3)은 마름모 앞([textR]), 이름 앞(nameL + 5 이상)은 구멍 뒤([textL]).
      final nameR = math.min(math.min(b, c.w - Look.tabInset), textR + 3), nameL = math.max(math.max(a, c.left), textL - 5);
      final inked = s.own || s.color == 0;
      final rgb = 0xff000000 | s.color;
      final line = inked ? CanvasInk.of(Look.ink) : mixSrgb(rgb, Look.ink, powerMix);
      final look = inked ? powerNameLook : _powerLooks[rgb] ??= powerNameLook.withColor(mixSrgb(rgb, Look.ink, powerNameMix));
      String? name;
      var nameX = 0.0;
      if (s.holder.isNotEmpty && !_realOver(c, row, s)) {
        final room = c.text.widthOf(s.holder, powerRoomLook), w = c.text.widthOf(s.holder, look);
        if (room == null || w == null) {
          c.scene.requestFrame(); // 글자 폭을 아직 잴 수 없다 — 다음 장면에
        } else if (nameR - nameL >= room + 8) {
          final x = nameR - 3 - w;
          var free = true;
          for (final z in headNameZones[row] ?? const <(double, double)>[]) {
            if (z.$1 < x + w && z.$2 > x) free = false;
          }
          if (free) {
            (headNameZones[row] ??= []).add((x - 4, x + w + 4));
            name = s.holder;
            nameX = x;
          }
        }
      }
      out.add(_PowerMark(s.id, a, b, line, name, nameX, look, lanes[s.id] ?? 0));
    }
    return out;
  }

  /// 실권 밑줄의 자리(띠 윗변에서) · 두께와 섞임 — 미리보기 `.tl-power-ul { top: 11px; height: 2px }` · `color-mix(--c 80%, 먹)` · 이름 `color-mix(--c 30%, 먹)`.
  /// 겹친 실권의 둘째 단부터는 [powerLane]씩 아래(단 1 = 띠 윗변 + 14 — 머리 색줄 아랫금 바로 밑 · 조사 결함 31).
  static const powerTop = 11.0, powerHeight = 2.0, powerMix = .80, powerNameMix = .30, powerLane = 3.0;

  /// 머리 밑 단의 밑줄이 칸 글자 몸 둘레에 비우는 여백(px — 동군연합 이음줄이 사건 이름 상자 둘레를 비우는 것처럼).
  static const powerTextClear = 2.0;

  /// 단 [lane]의 밑줄 윗변(띠 윗변 [top]에서 — 정수 픽셀).
  static double powerY(double top, int lane) => (top + powerTop + powerLane * lane).floorToDouble();

  /// 끝 이름의 글꼴(먹 — 그림판 먹 단계 85 · 쥔 쪽 색이 있으면 그 색 30% + 먹으로 바꿔 쓴다) · 글줄 가운데(띠 윗변 + 2 + 9/2).
  static final powerNameLook = TextLook(8, ui.FontWeight.w700, CanvasInk.of(Look.ink));
  static const powerNameMid = 6.5;

  /// 쥔 쪽 색 → 끝 이름의 글꼴(장면마다 새로 짓지 않게).
  final _powerLooks = <int, TextLook>{};

  /// 끝 이름이 드는지 잴 때의 글꼴 — 미리보기는 8.5 굵게로 잰다(`textWidth(nm, 8.5, 700) + 8`). 그리는 글은 8.
  static const powerRoomLook = TextLook(8.5, ui.FontWeight.w700, Look.ink);

  /// 단체의 실권 단 = 칸 종류 8(공용 칸 단)의 단 3 · 단 갈래 5 ~ 7(strips.dart `CellStyle.isGroupBand` — 이 파일은 칸 층을 읽지 않아 값으로 적는다).
  static const _realKind = 8, _realLane = 3, _realBandFrom = 5;

  /// 줄 [row]에 단체의 실권 단이 그려지고(표시 체크 '단체' · 실권 층이 있거나 빽빽하게의 머리 줄 — strips.dart `_paintLane`과 같은 갈래)
  /// 그 칸이 실권 밑줄 [s]의 기간과 겹치는가.
  bool _realOver(PaintContext c, int row, PowerSpan s) {
    final cells = _realCells[row];
    if (cells == null) return false;
    if (c.layout.geo(row).realTop < 0 && c.layout.conditions.density <= 0) return false;
    for (final (a, b) in cells) {
      if (s.overlaps(a, b)) return true;
    }
    return false;
  }

  /// 띠 상자의 두 끝(미리보기 `x1` · `x2`): 진짜 두 끝(연대 폭까지)에 미정 꼬리([Look.fuzzyFade] — 이웃 띠 앞에서 멈춤)를 더한 것.
  (double, double) _boxOf(int row, int id, double realL, double realR) {
    _RowSpan? me;
    for (final s in _rowSpans[row] ?? const <_RowSpan>[]) {
      if (s.id == id) me = s;
    }
    if (me == null || (!me.fuzzyL && !me.fuzzyR)) return (realL, realR);
    final (roomL, roomR) = _tailRoom(row, id, realL, realR);
    return (me.fuzzyL ? math.max(realL - Look.fuzzyFade, roomL) : realL, me.fuzzyR ? math.min(realR + Look.fuzzyFade, roomR) : realR);
  }

  /// 칸 종류 → 직위 낱말(구역 54의 a — 1 지도자 · 2 내각, strips.dart `CellKind`). 종류 9(직위 줄 더)는 낱말이 줄마다 달라 구역 55의 줄 이름으로([_borrowsOf]).
  static const _borrowWords = {1: '지도자', 2: '내각'};

  /// 타일마다 한 번 읽어 둔 출처 글(띠 id → 글 몫). 타일의 내용은 바뀌지 않으므로 타일에 걸어 둔다.
  static final _borrowBy = Expando<Map<int, _BorrowText>>('빌린 줄의 출처 글');

  /// 띠 [id]의 출처 글 — 지도자 · 내각 몫 뒤에 직위 줄 더의 빌림을 그 줄(lane)이 줄 [row]의 직위 줄 더 층 안([RowGeo.officeLanes])일 때만 잇는다
  /// (층이 없는 줄 — 옛 꼴 줄 · 표시 '지도자' 끔 · 스위치 `office` 끔 — 에서는 그 줄이 그려지지 않으므로 글도 없다). 띠에 출처 글이 없으면 null.
  /// 직위 줄 더 몫이 하나라도 서면 고르기 판 G7 가(g-g7.js — `· 등좌 · 재상 ← 성좌령`)의 꼴: 출처 글 끝의 '/직위'가 그 몫의 낱말과 같으면 떼고
  /// (내보내기 strips.mjs `fromOf`가 `출처이름/직위`로 실음 — 낱말과 겹쳐 `· 서기 ← 모래 서원/서기`가 되던 것), 출처가 같은 이웃 몫은 `· 낱말 · 낱말 ← 출처`
  /// 한 글로 묶는다(칸 그림 갈래 검토 고침). 직위 줄 더 몫이 없으면 지도자 · 내각 몫은 예전 글 그대로([_BorrowText.base] — 스위치 office 끔도 같음).
  String? _borrowTextOf(PaintContext c, Tile t, int id, int row) {
    final b = _borrowsOf(t)[id];
    if (b == null) return null;
    if (b.offices.isEmpty) return b.base.isEmpty ? null : b.base;
    final lanes = c.layout.geo(row).officeLanes;
    final shown = [for (final (lane, word, source) in b.offices) if (lane < lanes) (word, source)];
    if (shown.isEmpty) return b.base.isEmpty ? null : b.base;
    String bare(String word, String source) {
      final cut = source.lastIndexOf('/');
      return cut > 0 && source.substring(cut + 1).trim() == word ? source.substring(0, cut).trimRight() : source;
    }

    final parts = <String>[];
    String? from;
    final words = <String>[];
    void flush() {
      if (from != null) parts.add('· ${words.join(' · ')} ← $from');
      words.clear();
    }

    for (final (word, source) in [...b.heads, ...shown]) {
      final src = bare(word, source);
      if (src != from) {
        flush();
        from = src;
      }
      words.add(word);
    }
    flush();
    return parts.join(' ');
  }

  /// 타일의 구역 54에서 띠마다 출처 글을 짓는다 — 지도자 → 내각 → 직위 줄 더(줄 차례) · 빈칸 하나로 이음(미리보기의 두 빈칸은 `white-space: nowrap`이 하나로 접는다).
  /// 같은 띠 · 같은 종류(직위 줄 더는 같은 줄)가 둘이면 앞의 것(타일에 실린 차례). 출처가 빈 글이면 그 줄은 없다.
  /// 직위 줄 더의 빌림(구역 54의 a = 9 · b = 줄 — G7 가 · 칸 그림 갈래 걸음 4)은 `· 재상 ← 출처` — 낱말은 같은 띠 구역 55의 그 줄 이름(고르기 판 G7 가의
  /// `· 등좌 · 재상 ← 성좌령`처럼 직위 낱말), 없으면 출처 글의 '/' 뒤 직위 · 그것도 없으면 '직위'. 그 몫은 줄마다 (줄, 낱말, 출처)로 두고 그릴 때 층이 선 줄만 잇는다(출처가 같은 몫은 한 글로 — [_borrowTextOf]).
  static Map<int, _BorrowText> _borrowsOf(Tile t) => _borrowBy[t] ??= () {
    final heads = Schema4.borrowHeads(t);
    if (heads.isEmpty) return const <int, _BorrowText>{};
    final byBand = <int, Map<int, String>>{};
    final lanesBy = <int, Map<int, String>>{};
    for (final h in heads) {
      if (h.source.isEmpty) continue;
      if (_borrowWords.containsKey(h.kind)) {
        (byBand[h.band] ??= {}).putIfAbsent(h.kind, () => h.source);
      } else if (h.kind == Schema4.cellOfficeMore && h.lane >= 0) {
        (lanesBy[h.band] ??= {}).putIfAbsent(h.lane, () => h.source);
      }
    }
    final names = <int, String>{};
    if (lanesBy.isNotEmpty) {
      for (final n in Schema4.officeNames(t)) {
        names.putIfAbsent(n.band * 32 + n.lane, () => n.name);
      }
    }
    String wordOf(int band, int lane, String source) {
      final named = names[band * 32 + lane];
      if (named != null && named.isNotEmpty) return named;
      final cut = source.lastIndexOf('/');
      final tail = cut >= 0 ? source.substring(cut + 1).trim() : '';
      return tail.isNotEmpty ? tail : '직위';
    }

    return {
      for (final band in {...byBand.keys, ...lanesBy.keys})
        band: _BorrowText(
          [for (final k in const [1, 2]) if (byBand[band]?[k] != null) '· ${_borrowWords[k]} ← ${byBand[band]![k]}'].join(' '),
          [for (final k in const [1, 2]) if (byBand[band]?[k] != null) (_borrowWords[k]!, byBand[band]![k]!)],
          [
            for (final lane in (lanesBy[band]?.keys.toList() ?? <int>[])..sort()) (lane, wordOf(band, lane, lanesBy[band]![lane]!), lanesBy[band]![lane]!),
          ],
        ),
    };
  }();

  /// 재어 둔 자리에 머리의 이름 · 딱지와, 띠 위로 솟는 상국 탭 · 연합의 겹 탭을 그린다(장면에 띠마다 한 번 — 테두리 걸음에서).
  void _paintHead(PaintContext c, _Head h) {
    final id = h.id;
    final alpha = _tabAlpha(id);
    _paintHostTabs(c, id, h.row, h.top, alpha);
    // 실권 밑줄 — 이름이 없는 띠에도(미리보기는 이름 탭과 따로 긋는다). 이름 · 출처 글과 같은 흐림 · 누름은 받지 않는다(`pointer-events: none`).
    if (h.powers.isNotEmpty) {
      for (final p in h.powers) {
        final a = p.a.roundToDouble(), b = p.b.roundToDouble(), y = powerY(h.top, p.lane);
        // 머리 밑으로 내려온 단(1부터 — 칸 층의 윗머리)은 칸에 적은 글자 몸과 가로로 겹치는 몫(둘레 [powerTextClear])을 비운다(0.1.1 합침 검토 — 둘째 단 파선이
        // 지도자 칸 '셋째 임금'의 윗부분을 지났다 · 글자 겹침 금지). 단 0은 머리 안이라 칸 글자에 닿지 않는다.
        final cuts = p.lane >= 1 ? StripLayer.of(c.scene)?.textSpansIn(a - powerTextClear, b + powerTextClear, y, y + powerHeight) : null;
        final runs = <(double, double)>[(a, b)];
        if (cuts != null && cuts.isNotEmpty) {
          cuts.sort((m, n) => m.$1.compareTo(n.$1));
          runs.clear();
          var from = a;
          for (final (l, r) in cuts) {
            final to = (l - powerTextClear).floorToDouble();
            if (to > from) runs.add((from, math.min(to, b)));
            from = math.max(from, (r + powerTextClear).ceilToDouble());
          }
          if (from < b) runs.add((from, b));
          c.debug?.note('실권밑줄비움', '$id ${p.lane} ${[for (final (l, r) in cuts) '${(l * 10).round()},${(r * 10).round()}'].join(' ')}');
        }
        for (final (l, r) in runs) {
          if (r <= l) continue;
          if (p.lane >= 2) {
            c.quads.hLine(l, r, y, withAlpha(p.line, alpha), width: powerHeight, dash: EdgeStroke.dashed.dash, gap: EdgeStroke.dashed.gap, phase: a);
          } else {
            c.quads.add(l, y, r, y + powerHeight, withAlpha(p.line, alpha));
          }
        }
        c.stats.shapes++;
        c.debug?.note('실권밑줄', '$id ${(a * 10).round()},${(y * 10).round()},${((b - a) * 10).round()} ${(p.line & 0xffffff).toRadixString(16).padLeft(6, '0')}');
        final name = p.name;
        if (name == null) continue;
        c.later.add('powerName', name, p.look, p.nameX, h.top + powerNameMid - p.look.size * .6, alpha);
        c.debug?.note('실권이름', '$id ${(p.nameX * 10).round()} ${(p.look.color & 0xffffff).toRadixString(16).padLeft(6, '0')} $name');
      }
    }
    final plan = h.plan, base = h.base;
    if (plan.mode.isEmpty || base == null) return;
    final look = h.look, color = h.color;
    final hs = BandLook.hsOf(look);
    final hover = id == (hotBand ?? c.scene.hoverBand), chosen = id == _em.look.band;
    final refuted = hs == BandLook.hsRefuted;
    // 대립 띠의 이름은 먹 60(고르기 판 s4 — 고른 · 올린 띠는 먹 그대로, 부정된 띠는 옅은 먹이 이긴다) · 뚜껑 꼬리표는 먹 85(lid_tags.dart).
    final fg = refuted ? CanvasInk.of(Look.muted) : (hover || chosen ? Look.ink : (h.rival ? TagLook.rivalName : (h.lid ? LidLook.name : mixSrgb(color, Look.ink, .22))));
    final nameLook = TextLook(tabNameSize, ui.FontWeight.w700, fg, spacing: -.1, italic: hs == BandLook.hsLegendary);
    final mid = h.top + G.head / 2;
    var at = h.l;
    c.later.add('tab', plan.name, nameLook, at, mid - nameLook.size * .6, alpha);
    // 부정된 나라는 이름에만 취소선(딱지에는 긋지 않는다) — 머리의 가운데 줄에.
    if (refuted) c.quads.hLine(at, at + plan.nameWidth, mid, withAlpha(CanvasInk.of(Look.muted), alpha));
    at += plan.nameWidth;
    _hits.add(_HitBox(h.l, h.top, at, h.top + G.head, id, h.row, true));
    c.stats.shapes++;
    // 빌린 직위 줄의 출처 글 — 이름과 같은 색줄 가운데 · 같은 흐림(누름은 받지 않는다 — 미리보기 `pointer-events: none`이라 그 자리는 띠).
    final borrow = h.borrow;
    if (borrow != null) {
      c.later.add('borrow', borrow.$1, borrowLook, borrow.$2, mid - borrowLook.size * .6, alpha);
      c.debug?.note('빌린머리', '$id ${(borrow.$2 * 10).round()} ${borrow.$1}');
    }
  }

  /// 간지 탭의 칠 — 띠 바탕과 같은 섞임(지금 연표 common.css '간지 탭'의 --tm · .tl-band · .tl-lane .tl-band의 바탕):
  /// 보통 띠 24% · 미정 6% · 종속 갈래 · 종속국 · 망명 · 부흥 세력 · 문화 9% · 조직체 · 시대 이름 10% · 연맹 6%.
  static double tabMixOf(int look, {required bool fuzzy}) {
    final kind = BandLook.kindOf(look);
    if (kind == BandKind.federation) return .06;
    if (kind == BandKind.org || kind == BandKind.era) return .10;
    if (look & BandLook.famDep != 0 || kind == BandKind.vassal || kind == BandKind.exile || kind == BandKind.movement || kind == BandKind.culture) return .09;
    return fuzzy ? .06 : .24;
  }

  /// 낮은 탭 한 장(밑변 없음 — 꼬리표 갈래 E의 상국 탭 · 연합의 겹 탭): 왼쪽 위 귀만 모따기 [ch], 나머지는 직각.
  /// 칠은 네모 둘 + 귀 조각, 선은 윗변 · 두 옆변(네모 묶음) + 귀의 빗변 조각 — 길(Path) 없이. 선의 모양(실선 · 파선 · 점선)은 받침 카드와 같다.
  /// 칠은 아래의 연도 세로줄을 가리는 종이다(리메이크 4단계 세로줄 얹기): 흐린 탭(알파 < 1)의 칠은 탭 가운데의 바탕색과 섞은 불투명 색으로(이미 섞은 색이면 그대로).
  void _smallTab(PaintContext c, double l, double t, double r, double b, double ch, int fill, int edge, EdgeStroke stroke) {
    if (r - l < 2 * ch + 2) return;
    fill = c.grounds.over(fill, (l + r) / 2, (t + b) / 2);
    sprites.add(BandSprites.cham, BandCorner.topLeft, l, t, fill, ch);
    c.quads.add(l, t + ch, l + ch, b, fill);
    c.quads.add(l + ch, t, r, b, fill);
    c.quads.hLine(l + ch, r, t, edge, dash: stroke.dash, gap: stroke.gap, phase: l);
    c.quads.vLine(l, t + ch, b, edge, dash: stroke.dash, gap: stroke.gap, phase: t);
    c.quads.vLine(r - 1, t, b, edge, dash: stroke.dash, gap: stroke.gap, phase: t);
    sprites.add(BandSprites.chamLine, BandCorner.topLeft, l, t, edge, ch);
  }

  /// 소속 구간의 주장(칸 그림 갈래 걸음 3): 상국 탭([l] ~ [r] · [t] ~ [b] — [_smallTab]의 자리) 칠에 1px 화소 빗금(먹 25 — [LegitLook.hatch]).
  /// 테 안쪽만(윗 테 아래 ~ 탭 밑 줄 · 두 옆 테 안 · 왼쪽 위 모따기 귀 밖은 비움)이고, 글([textL] ~ + [textW])의 앞뒤 [LegitLook.tabPad]는 받침으로 비운다
  /// (칸 · 머리의 '이름 둘레는 받침'과 같은 문법 — 탭이 글 + 14로 좁아 받침은 1).
  void _claimTab(PaintContext c, double l, double t, double r, double b, double textL, double textW, double alpha) {
    final ink = CanvasInk.alpha(LegitLook.hatchInk, alpha), phase = LegitLook.phaseX(c.v.xOf(0));
    const ch = TagLook.tabCham;
    // 테는 화소 열 · 줄로 내려 긋는다(batch.dart vLine · hLine의 floor) — 왼쪽 테 floor(l) · 오른쪽 테 floor(r − 1) · 윗 테 floor(t)의 안쪽만.
    final inL = l.floorToDouble() + 1, inR = (r - 1).floorToDouble(), inT = t.floorToDouble() + 1;
    final gapL = (textL - LegitLook.tabPad).floorToDouble(), gapR = (textL + textW + LegitLook.tabPad).ceilToDouble();
    void put(double x0, double y0, double x1, double y1) {
      if (x1 - x0 >= 1 && y1 - y0 >= 1) c.patterns.add(LegitLook.hatch, x0, y0, x1, y1, ink, phaseX: phase, phaseY: inT - 1);
    }

    put(inL + ch, inT, gapL, inT + ch); // 모따기 귀 옆(위 몫)
    put(inL, inT + ch, gapL, b); // 귀 아래
    put(gapR, inT, inR, b);
    c.debug?.note('주장탭', '${(inL * 10).round()},${(gapL * 10).round()},${(gapR * 10).round()},${(inR * 10).round()},${(inT * 10).round()}');
  }

  /// 띠 [band]의 상국 탭 자리(장면에 한 번 — 처음 물을 때 정해 그리기 · 관계선 층 · 열쇠표 · 실이 같은 자리를 본다). 머리를 잰 띠([_heads])만.
  /// 관계를 **짧은 것부터** 놓는다 — 예전에는 왼쪽 끝 차례라, 겹친 섬김에서 바깥(긴) 관계의 탭이 먼저 끝 쪽을 차지하면 안쪽(짧은) 관계의 탭은 늘 버려졌다
  /// (조사 결함 20 · f4-liege 갈대 공국의 백사 공국 조공). 자리 후보는 차례대로 ① 끝 쪽(예전 자리 — 뒤 장 끝 − [sheetRadius] · 화면 오른쪽 안)
  /// ② 시작 쪽(뒤 장 시작 + [sheetRadius] · 띠 평지 첫머리 · 플래그 자리 뒤) — 온 이름이 어디에도 안 들면 ③ 첫 글자 탭(끝 쪽 → 시작 쪽)
  /// ④ 카드 윗단의 상국 색 점(조사 결함 26 — 짧은 관계의 이름 없는 카드). 앞서 선 탭과는 [Look.tabGap] 띄운다.
  /// 끝 쪽 온 이름 탭은 예전과 같은 자리 · 같은 거름이라 관계가 하나뿐인 띠는 그림이 그대로다(플래그 자리는 시작 쪽 후보만 비킨다 —
  /// 길 셈은 플래그를 놓기 전이라 플래그가 설 수 있는 자리를 늘 비워 둔다).
  List<_TabSpot> _hostSpotsOf(PaintContext c, int band) {
    final done = _hostSpots[band];
    if (done != null) return done;
    final h = _heads[band], segs = _hostSegs[band];
    if (h == null || segs == null || segs.isEmpty || c.layout.bird || c.hide.contains('tabs')) return _hostSpots[band] = const [];
    final x1 = h.realL, flatL = math.max(h.realL, c.left + Look.tabInset);
    // 플래그가 설 수 있는 자리(scopes.dart `_placeFlags` — 띠 시작(화면 왼쪽 밖이면 그림판 왼쪽) + 16 · 폭 14)의 오른쪽 + 틈.
    final flagSlot = (math.max(h.realL, c.left) + FlagLook.from).roundToDouble() + FlagLook.w + Look.tabGap;
    final list = [for (final s in segs.values) if (s.look != coalLook) s]
      ..sort((a, b) {
        final la = a.right - a.left, lb = b.right - b.left;
        return la != lb ? la.compareTo(lb) : (a.left != b.left ? a.left.compareTo(b.left) : a.k.compareTo(b.k));
      });
    final out = <_TabSpot>[];
    bool free(double x, double w) => out.every((o) => o.dot ? (x + w <= o.x - Look.tabGap || x >= o.x + Look.tabGap) : (x + w + Look.tabGap <= o.x || x >= o.x + o.w + Look.tabGap));
    for (final s in list) {
      if (s.right < math.max(x1, c.left) + 10) continue;
      final w0 = c.text.widthOf(s.name, hostLook);
      if (w0 == null) {
        c.scene.requestFrame(); // 글자 폭을 아직 잴 수 없다 — 다음 장면에
        continue;
      }
      // 탭은 뒤 장의 평평한 윗변 안에 선다(제 이름 탭이 띠의 둥근 모서리 뒤에서 서듯) — 뒤 장의 두 끝에서 둥근 정도만큼 안쪽.
      final atL = s.left <= (_joinedLeft[band] ?? double.negativeInfinity) + .5;
      final sheetL = s.left + (atL ? sheetShift : 0), sheetR = sheetL + (s.right - s.left);
      final right = math.min(sheetR - sheetRadius, c.w - Look.tabInset);
      final lo = math.max(sheetL + sheetRadius, flatL), loStart = math.max(lo, flagSlot);
      _TabSpot? spot;
      for (final (text, tw) in [(s.name, w0), if (s.name.isNotEmpty) (_firstGlyph(s.name), c.text.widthOf(_firstGlyph(s.name), hostLook))]) {
        if (tw == null) continue;
        final w = tw + 14;
        if (right - w >= lo && free(right - w, w)) {
          spot = _TabSpot(s, right - w, w, text, tw);
        } else if (loStart + w <= right && free(loStart, w)) {
          spot = _TabSpot(s, loStart, w, text, tw);
        }
        if (spot != null) break;
      }
      if (spot == null) {
        // 점: 카드의 보이는 몫 가운데(화면 안) — 카드 끝 귀([sheetRadius])에 걸치지 않을 만큼 넓을 때만.
        final l = math.max(sheetL + 3, c.left), r = math.min(sheetR - 3, c.w);
        final mid = ((l + r) / 2).roundToDouble();
        if (r - l >= 2 * dotR + 2 && free(mid - dotR, 2 * dotR)) spot = _TabSpot(s, mid, 0, '', 0, dot: true);
      }
      if (spot != null) out.add(spot);
    }
    out.sort((a, b) => a.x.compareTo(b.x));
    return _hostSpots[band] = out;
  }

  /// 짧은 관계의 상국 색 점의 반지름(px — 카드 윗단 5px 안 · 조사 결함 26).
  static const dotR = 1.5;

  /// 띠 [band]의 연합 겹 탭 자리(장면에 한 번 — 플래그를 놓은 뒤 처음 물을 때 · [force]면 플래그를 기다리지 않는다(그리기 — 단추 층이 꺼진 장면)).
  /// 자리는 가담이 시작한 해(띠 첫머리 · 화면 왼쪽 안이면 평지 첫머리)와 **플래그 오른쪽 + [Look.tabGap]** 가운데 늦은 쪽(조사 결함 27 — 플래그가 첫 글자들을 덮었다 ·
  /// 열쇠표가 플래그 뒤로 미는 것과 같은 셈). 앉은 상국 탭과 [Look.tabGap] 안으로 닿거나 평지 끝을 넘으면 없다(밀지 않는다 — 웹 `_coalTabPlan`).
  List<_TabSpot>? _coalSpotsOf(PaintContext c, int band, {bool force = false}) {
    final done = _coalSpots[band];
    if (done != null) return done;
    if (!flagsPlaced && !force) return null;
    final h = _heads[band], segs = _hostSegs[band];
    if (!_coalOn || h == null || segs == null || c.layout.bird || c.hide.contains('tabs')) return _coalSpots[band] = const [];
    // 차례 = 그 띠의 가담 차례(구역 47의 b — HT.coalitionsOf의 시작 · 끝 · 이름 차례).
    final coals = [for (final s in segs.values) if (s.look == coalLook) s]..sort((a, b) => a.k.compareTo(b.k));
    if (coals.isEmpty) return _coalSpots[band] = const [];
    final flatL = math.max(h.realL, c.left + Look.tabInset), flatR = math.min(h.realR, c.w - Look.tabInset);
    final flag = flagRight[band];
    final start = flag == null ? flatL : math.max(flatL, flag + Look.tabGap);
    final taken = [for (final o in _hostSpotsOf(c, band)) if (!o.dot) (o.x, o.x + o.w)];
    final out = <_TabSpot>[];
    for (final s in coals) {
      if (s.right < math.max(h.realL, c.left) + 10) continue;
      final w0 = c.text.widthOf(s.name, hostLook);
      if (w0 == null) {
        c.scene.requestFrame();
        continue;
      }
      final w = w0 + 2 * coalPad;
      final x = math.max(s.left, start);
      final r = x + w + coalBackDx;
      if (r > flatR) continue;
      var free = true;
      for (final (a, b) in taken) {
        if (!(r + Look.tabGap <= a || x >= b + Look.tabGap)) free = false;
      }
      if (!free) continue;
      out.add(_TabSpot(s, x, w, s.name, w0));
      taken.add((x, r));
    }
    return _coalSpots[band] = out;
  }

  /// 띠 [band]의 윗변 위에 이번 장면 선 탭들(상국 탭 · 연합 겹 탭 — 연합은 뒤 장 [coalBackDx]까지 · 점은 [dotR] 둘레)의 가로 구간(px).
  /// 단추 층의 열쇠표(scopes.dart `_collectKeys` — 조사 결함 21 · 48)와 사람 띠의 실(sphere_threads.dart — 결함 37 탭 몫)이 비킨다.
  /// 연합 겹 탭은 플래그를 놓은 뒤에만 든다([flagsPlaced]).
  List<(double, double)> hostTabSpans(PaintContext c, int band) => [
    for (final o in _hostSpotsOf(c, band)) o.dot ? (o.x - dotR, o.x + dotR) : (o.x, o.x + o.w),
    for (final o in _coalSpotsOf(c, band) ?? const <_TabSpot>[]) (o.x, o.x + o.w + coalBackDx),
  ];

  /// 띠 [band](줄 [row])의 띠 상자 오른쪽 끝(px — 미정 꼬리까지 · 미리보기 `x2`). 이번 장면에 실린 띠가 아니면 null.
  /// 열쇠표가 이 앞에서 끝나야 선다(scopes.dart `_collectKeys` — 조사 결함 25 · 웹 `kx + w > min(x2, W) − 4`).
  double? boxRightOf(int row, int band) {
    final r = _joinedRight[band];
    if (r == null) return null;
    return _boxOf(row, band, _joinedLeft[band] ?? double.negativeInfinity, r).$2;
  }

  /// (x, y)가 이름을 다 쓰지 못한 상국 탭(첫 글자 · 점 — 조사 결함 26)이나 그 카드의 드러난 윗단이면 풍선 글('상국 이름 — 상국 · 누르면 상국'), 아니면 빈 글.
  /// 그리개 바깥(timeline_view.dart)의 올림이 묻는다.
  String hostTipAt(double x, double y) {
    for (int i = _hits.length - 1; i >= 0; i--) {
      final h = _hits[i];
      if (!h.tab || h.coal || h.uid.isEmpty || x < h.l || x > h.r || y < h.t || y > h.b) continue;
      for (final spots in _hostSpots.values) {
        for (final o in spots) {
          if (o.short && o.s.uid == h.uid && o.s.hostBand == h.band && x >= o.s.left - 1 && x <= o.s.right + 1) return '${o.s.name} — 상국 · 누르면 상국';
        }
      }
      return '';
    }
    return '';
  }

  /// 뒤 장의 탭(상국 이름 탭 — 건의 8의 2번 C · 2026-10-13 · 이음매 2026-10-14): 어깨 모양은 예전 상국 탭, **뒤 장과 한 장** — 칠 · 테 · 선 모양 · 흐림이
  /// 뒤 장과 같고, 탭과 뒤 장 사이에는 경계선이 없어 한 윤곽으로 이어진다. 자리는 [_hostSpotsOf]가 정한다(끝 쪽 → 시작 쪽 → 첫 글자 → 점 —
  /// 탭은 [tabRise] 올린다). 화면 왼쪽 밖에서 이미 끝난 관계는 없다. 칠의 짙기는 상국 띠의 속국 이름표와 같은 자
  /// (구역 47의 a — 0 빈 · 1 칠한 · 2 점선 · 3 파선 · 4 옅은 · 5 짙은 · 6 빗금).
  ///
  /// 꼬리표 갈래 E(2026-10-15): 띠 위 탭 줄이 없어져 탭은 **받침 카드 윗변 위의 낮은 탭**(높이 [TagLook.tabH] · 왼쪽 위 모따기 [TagLook.tabCham] ·
  /// 글 8.5 — 목업 hostTab)이다. 그런 줄은 위 틈이 15 더 있다(layout.dart `RowSpec.raised`). [top]은 띠 윗변(화면 y).
  void _paintHostTabs(PaintContext c, int band, int row, double top, double alpha) {
    final segs = _hostSegs[band];
    if (segs == null || segs.isEmpty) return;
    for (final spot in _hostSpotsOf(c, band)) {
      final s = spot.s, x = spot.x, w = spot.w;
      final hc = 0xff000000 | s.color, look = s.look.clamp(0, 6);
      if (spot.dot) {
        // 점(조사 결함 26): 카드의 드러난 윗단(윗 테 아래 3줄) 가운데에 상국 글빛 네모 3 × 3 — 맞히기 · 풍선 글은 카드 윗단의 것(paintHostSheets)이 맡는다.
        final y = top - sheetRise + 1;
        c.quads.add(x - 1, y, x + 2, y + 2 * dotR, withAlpha(mixOklab(hc, Look.ink, look >= 4 ? .28 : .45), _em.bandAlpha(band, row)));
        c.debug?.note('상국점', '$band ${s.name} ${(x * 10).round()}');
        c.stats.shapes++;
        continue;
      }
      // 탭과 뒤 장은 한 장 — 칠 · 테 · 선 모양 · 흐림이 뒤 장과 같다(paintHostSheets).
      final sheetAlpha = _em.bandAlpha(band, row);
      final mix = sheetMix[look];
      // 소속 구간의 정통성(구역 58 — 칸 그림 갈래 걸음 3 · 다듬기 판 '소속 구간도 같은 문법'): 명목 = 탭 글 먹 45 · 탭 테와 이어진 뒤 장 테 먹 25(열쇠표 옅게) ·
      // 주장 = 탭 칠에 화소 빗금(글 둘레는 받침 — [_claimTab]) · 대립 = 파선 테(띠의 G6 가와 같은 3 · 2). 공동 · 섭정은 꼴이 없어 그대로.
      // 차례는 불투명 탭 칠(아래 fill) → [_claimTab] 빗금 → 글 — 흐릴 때도 빗금은 불투명 탭 칠 위에 얹혀 세로줄이 비치지 않는다.
      final legit = _hostLegit[(band, s.k)] ?? -1;
      final edge = withAlpha(legit == Schema4.legitNominal ? LegitLook.nominalLine : mixOklab(hc, Look.ink, .78), sheetAlpha);
      final stroke = legit == Schema4.legitRival ? EdgeStroke.dashed : (look == 2 ? EdgeStroke.dotted : (look == 3 ? EdgeStroke.dashed : EdgeStroke.solid));
      // 탭 밑 1px이 받침 카드의 윗변 자리 — 탭은 카드 위로 [TagLook.tabH] 솟는다.
      final hBottom = top - sheetRise + 1, hTop = hBottom - 1 - TagLook.tabH;
      // 칠은 아래의 연도 세로줄을 가리는 종이(흐릴 때는 탭 가운데의 바탕색과 섞은 불투명 색 — 리메이크 4단계 세로줄 얹기). 밑 1px 덮개도 같은 색.
      final fill = c.grounds.over(withAlpha(mix > 0 ? mixOklab(hc, Look.paper, mix) : Look.paper, sheetAlpha), x + w / 2, (hTop + hBottom) / 2);
      _smallTab(c, x, hTop, x + w, hBottom, TagLook.tabCham, fill, edge, stroke);
      // 탭과 뒤 장 사이에는 경계선이 없다(감독 2026-10-14 "상국 태그랑 띠 있는 경계선은 지우자") — 탭 맨 아래 1px 줄(= 뒤 장의 윗변 자리)을
      // 어깨 끝에서 끝까지 탭의 칠로 덮어, 탭과 뒤 장이 한 윤곽으로 이어진다. 탭 바깥으로는 뒤 장의 윗변 선이 그대로 이어진다.
      if (tabRise > 0) c.quads.add(x + .5, hBottom - 1, x + w - .5, hBottom, fill);
      if (legit == Schema4.legitClaim) _claimTab(c, x, hTop, x + w, hBottom, x + 7, spot.textW, sheetAlpha);
      final ink = legit == Schema4.legitNominal ? LegitLook.nominalName : mixOklab(hc, Look.ink, look >= 4 ? .28 : .45);
      if (legit >= 0) c.debug?.note('소속정통', '$band ${s.name} $legit');
      c.later.add('hostTab', spot.text, hostLook.withColor(ink), x + 7, smallTabTextTop(hTop, hostLook.size), sheetAlpha);
      _hits.add(_HitBox(x, hTop, x + w, hBottom, s.hostBand, row, true, uid: s.uid));
      c.debug?.note('상국탭', '$band ${s.name} ${(x * 10).round()},${(w * 10).round()}${spot.short ? ' 첫글자' : ''}');
      c.stats.shapes++;
    }
    final coals = _coalSpotsOf(c, band, force: true) ?? const <_TabSpot>[];
    if (coals.isNotEmpty) _paintCoalTabs(c, coals, row, top, alpha);
  }

  /// 연합의 겹 탭(감독 선택 D5 결정 3 C + 덧판 x2 A — 웹 `_coalTabPlan` · `_hostTabs`): 구성 나라 띠의 탭 줄, 가담이 시작한 해의 자리에 이름 폭 탭 하나
  /// (시작이 띠 첫머리 · 화면 왼쪽 밖이면 평지 첫머리). 상국 탭이 먼저 자리를 잡고, 연합 탭은 그 자리에서 앉은 탭과
  /// [Look.tabGap] 안으로 닿지 않고(뒤 장까지) 오른쪽 평지 끝을 넘지 않을 때만 — 밀지 않는다(시작 해가 어긋나지 않게 · 다른 구성 띠 · 올림 · 단체 창에서).
  /// 화면 왼쪽 밖에서 이미 끝난 가담은 없다. 그림: 같은 어깨 윤곽의 뒤 장(4px 오른쪽 · 3px 위 · 칠 18%)을 먼저, 그 위에 앞 장(34%) — '연합' 딱지 없이 모양으로.
  ///
  /// 꼬리표 갈래 E(2026-10-15): 띠 윗변 위에 바로 서는 낮은 탭(앞 장 [TagLook.tabH] · 왼쪽 위 모따기 [TagLook.tabCham]) — 뒤 장은 4px 오른쪽 · 3px 위(모따기 3).
  /// 자리는 [_coalSpotsOf]가 정한다(플래그 뒤 · 앉은 상국 탭을 비킴).
  void _paintCoalTabs(PaintContext c, List<_TabSpot> spots, int row, double top, double alpha) {
    // 밑 1px은 띠 윗변의 테가 덮는다 — 보이는 안이 [TagLook.tabH]가 되게(글이 가운데에 서게) 그만큼 높인다.
    final tabBottom = top + 1, tabTop = tabBottom - 2 - TagLook.tabH;
    for (final spot in spots) {
      final s = spot.s, x = spot.x, w = spot.w, r = x + w + coalBackDx;
      final on = _hotCoal != null && _hotCoal == s.uid;
      final hc = 0xff000000 | s.color;
      final edge = withAlpha(mixOklab(hc, Look.ink, .84), alpha);
      // 뒤 장 먼저, 그 위에 앞 장 — 묶음을 중간에 내보내지 않는다(같은 종류끼리 몰아서 한 번에). 네모 묶음이 먼저 · 어깨 조각(그림판)이 나중에 나가므로
      // 뒤 장의 왼쪽 어깨를 통째로 찍으면 앞 장의 몸통(네모) 위에 오는데, 그 어깨에서 보이는 몫은 앞 장 윗변 위로 솟은 3px뿐이라 그 몫만 찍는다([_dividerTall]).
      // 뒤 장의 귀 모따기는 3 — 앞 장 윗변 위로 솟은 3px 안에서 끝나, 나중에 나가는 귀 조각이 앞 장 몸통을 덮지 않는다.
      _smallTab(c, x + coalBackDx, tabTop - coalBackDy, x + coalBackDx + w, tabBottom, coalBackDy, withAlpha(mixSrgb(hc, Look.paper, on ? .30 : .18), alpha), edge, EdgeStroke.solid);
      _smallTab(c, x, tabTop, x + w, tabBottom, TagLook.tabCham, withAlpha(mixSrgb(hc, Look.paper, on ? .48 : .34), alpha), edge, EdgeStroke.solid);
      final ink = on ? Look.ink : mixOklab(hc, Look.ink, .30);
      c.later.add('hostTab', s.name, hostLook.withColor(ink), x + coalPad, smallTabTextTop(tabTop, hostLook.size), alpha);
      // 누르기 자리 = 앞 장 + 오른쪽 4px(뒤 장까지 — 웹의 요소 폭 w + backDx).
      _hits.add(_HitBox(x, tabTop, r, tabBottom, 0, row, true, uid: s.uid, coal: true));
      c.stats.shapes++;
      c.debug?.note('연합탭', '$row ${s.name} ${(x * 10).round()},${(w * 10).round()}${on ? ' 올림' : ''}');
    }
  }

  /// 연합의 겹 탭에 올렸을 때 구성 나라 띠 안의 가담 기간 조명(웹 `.tl-coal-lit` — 띠 테두리 안 · 칸 아래):
  /// 연합 색 26% 칠 + 양 끝 1px 선(그 색 70%) — 띠 끝(화면에 잘린 상자 끝)에 닿은 쪽은 선 없음. [l] ~ [r]은 이 타일의 조각.
  void _coalLit(PaintContext c, int id, double l, double top, double r, double b, double alpha) {
    final segs = _hostSegs[id];
    if (segs == null || alpha <= 0) return;
    final boxL = math.max(_joinedLeft[id] ?? l, c.left - 1) + 1, boxR = math.min(_joinedRight[id] ?? r, c.w + 1) - 1;
    for (final s in segs.values) {
      if (s.look != coalLook || s.uid != _hotCoal) continue;
      final a = math.max(s.left, boxL), z = math.min(s.right, boxR);
      if (z - a < .5) continue;
      final kc = 0xff000000 | s.color;
      final pa = math.max(a, l), pz = math.min(z, r);
      if (pz > pa) c.quads.add(pa, top + 1, pz, b - 1, withAlpha(withAlpha(kc, .26), alpha));
      final line = withAlpha(withAlpha(kc, .70), alpha);
      if (a > boxL + .5 && a >= l && a < r) c.quads.add(a, top + 1, a + 1, b - 1, line);
      if (z < boxR - .5 && z <= r && z > l) c.quads.add(z - 1, top + 1, z, b - 1, line);
      c.debug?.note('연합조명', '$id ${(a * 10).round()},${(z * 10).round()}');
    }
  }

  /// 탭 · 조감의 띠 안 이름의 흐림(C:1187~1189 · C:1781~1783) — 둘 다 **줄 직속**이라 띠의 흐림을 물려받지 않고
  /// 고른 동안 .5(제 띠만 1) · 강조 밖 .25(강조에 든 띠는 1)다. 띠와 달리 **같은 줄(`is-onrow`)은 1이 아니다** —
  /// 지금 연표의 `_applyStates`는 `is-onrow`를 띠에만 붙인다(js:5664). 값은 [em.Emphasis.tabAlpha]가 흐름에 태워 준다.
  double _tabAlpha(int band) => _em.tabAlpha(band);

  // ─────────────────────────── 조감의 띠 안 이름 ───────────────────────────

  /// 조감에서는 탭 대신 이름이 띠 안에 든다(`_birdName` T:3341 · 그리기 T:6925 · C:1777).
  /// 자리는 **띠 시작에 고정**이고 들 폭도 화면에 잘린 폭이 아니라 띠 전체다 — 옆으로 옮겨도 모양이 바뀌지 않는다.
  ///
  /// 자리를 재는 몫은 [_placeBirdNames]가 장면을 열 때 끝낸다([birdNameEnd] · [birdNameZones]를 같은 장면의
  /// 단추 층 · 관계선 층이 읽기 때문이다) — 여기서는 재어 둔 자리에 글자만 놓는다.
  void _placeBirdNames(PaintContext c) {
    final layout = c.layout;
    // 모양 c(띠 8px)는 이름이 없다(BIRD.c.name = false) — 올리면 풍선으로 말한다.
    if (!layout.bird || layout.birdShape?.name != true) return;
    // 장면을 여는 몫이라 층 감추기(`hide`)는 가리지 않는다 — 띠를 감춰도 단추 · 관계선은 이름 자리를 알아야 한다
    // (위의 두 끝 모으기도 같다).
    // 떠오르는 제 타일 밑에 깔린 메움 타일은 건너뛴다(그 자리는 제 타일이 잰다).
    final own = {for (final d in c.scene.draw) if (!d.isCover) d.key};
    for (final d in c.scene.draw) {
      if (d.isCover && own.contains(d.key)) continue;
      final t = d.tile;
      for (int i = 0; i < t.bandCount; i++) {
        if (t.bandLook[i] & (BandLook.under | BandLook.folded) != 0) continue;
        _placeBirdName(c, t, i);
      }
    }
  }

  /// 띠 하나의 조감 이름 자리 — 지금 연표의 `_birdName`(T:3341)과 같은 셈이다.
  void _placeBirdName(PaintContext c, Tile t, int i) {
    final layout = c.layout;
    final row = t.bandRow[i];
    if (row >= layout.rowCount || !layout.hasBody(row)) return;
    if (layout.spec(row)?.kind == RowKind.foldedGroup) return;
    final id = t.bandId[i];
    if (_birdPlaced.contains(id)) return;
    final geo = layout.geo(row);
    final top = v0(c, layout, row, geo);
    if (!c.rowOnScreen(row, top, geo.bandHeight)) return;
    // 관점(lens)이 켜져 있으면 그 나라가 부르는 이름으로 적고 폭도 그 글로 잰다(자료 · 줄 쌓기에는 닿지 않는다 — 11물결 labels4 4번).
    final name = LensTitles.of(c.scene).bandTitleOf(id) ?? t.text(t.bandName[i]);
    if (name.isEmpty) return;
    final v = c.v, origin = t.origin.toDouble();
    // 띠의 진짜 두 끝(연대 폭을 품은 bandStart · bandEnd — 미정 꼬리는 세지 않는다).
    final realL = _joinedLeft[id] ?? v.xOf(origin + t.bandX0[i]);
    final realR = _joinedRight[id] ?? v.xOf(origin + t.bandX1[i]);
    final l = realL + _birdInset, room = realR - _birdInset - l;
    // 이름이 없어도 단추가 설 자리(bnR)는 있다 — 지금 연표의 `bnR = nm.text ? nm.l + nm.w : nm.l − 4`(js:6934)라
    // 이름이 없으면 단추가 이름이 섰을 자리(`bnR + 4` = nm.l)에서 시작한다.
    birdNameEnd[id] = l - birdBtnGap;
    if (room <= 0) return;
    final look = t.bandLook[i], hs = BandLook.hsOf(look);
    final refuted = hs == BandLook.hsRefuted;
    final color = 0xff000000 | t.bandColor[i];
    final ink = refuted ? CanvasInk.of(Look.muted) : mixSrgb(color, Look.ink, .30);
    final nameLook = TextLook(_birdSize, ui.FontWeight.w700, ink, spacing: -.1, italic: hs == BandLook.hsLegendary);
    final full = c.text.widthOf(name, nameLook);
    if (full == null) return; // 글자 폭을 아직 잴 수 없다 — 다음 장면에.
    final head = _firstGlyph(name);
    final short = head == name ? full : c.text.widthOf(head, nameLook);
    if (short == null) return;
    _birdPlaced.add(id);
    // 문턱 둘: 더 긴 모양으로 바뀌려면 8px(양옆 4px)이 더 있어야 하고, 지금 모양은 딱 들어가는 동안 그대로.
    // 지난 모양을 모르면(맨 처음 · 그림 내보내기) 문턱은 하나다(명세 05의 7-3).
    final was = _birdMode[id];
    double need(double width, int level) => width + (was != null && was < level ? _birdGrow : 0);
    final mode = room >= need(full, 2) ? 2 : (room >= need(short, 1) ? 1 : 0);
    _birdMode[id] = mode;
    if (mode == 0) return;
    final text = mode == 2 ? name : head, width = mode == 2 ? full : short;
    birdNameEnd[id] = l + width;
    (birdNameZones[row] ??= []).add((l - _birdClear, l + width + _birdClear));
    c.debug?.note('조감이름', '$row ${(l - _birdClear).toStringAsFixed(1)}~${(l + width + _birdClear).toStringAsFixed(1)} $text');
    _birdNames[id] = _BirdName(row, l, top, geo.bandHeight, width, text, nameLook, refuted);
  }

  /// 재어 둔 자리에 조감의 띠 안 이름을 그린다(타일마다 조각이 오므로 띠마다 한 번).
  void _paintBirdName(PaintContext c, Tile t, int i) {
    final id = t.bandId[i];
    if (!_tabbed.add(id)) return;
    final n = _birdNames[id];
    if (n == null) return;
    // 자리는 그대로 두고 **화면 안에 다 드는 이름만** 그린다 — 점 · 알약이 숨거나 드러나지 않게.
    if (n.l < c.left - .5 || n.l + n.width > c.w + .5) return;
    final alpha = _tabAlpha(id);
    c.later.add('bandName', n.text, n.look, n.l, n.top + (n.height - _birdSize * 1.2) / 2, alpha);
    if (n.refuted) c.quads.hLine(n.l, n.l + n.width, n.top + n.height / 2, withAlpha(CanvasInk.of(Look.muted), alpha));
  }

  static double v0(PaintContext c, SceneLayout layout, int row, RowGeo geo) => c.v.yOf(layout.rowTop(row) + geo.bandTop);

  /// 딱지의 글꼴과 글자색. 딱지는 탭의 글자색을 물려받지 않고 제 규칙이 있다(C:1183 · C:1437 · C:1438 · C:1587) —
  /// 종류 `mixSrgb(--c, --paper-ink, 70%)` · 실재성 `mixSrgb(--paper-muted, --paper-ink, 55%)` ·
  /// 지위 `mixSrgb(--c, --paper-ink, 40%)`(서열 0은 `--paper-muted`). [color]은 그 띠의 제 색이다.
  /// 먹과 종이만 섞은 것(실재성 · 서열 0의 지위)은 그림판 먹 단계([CanvasInk] — 실재성 82 → 85 · 지위 60).
  static TextLook _tagLook(int kind, int color, int rank) => switch (kind) {
    1 => TextLook(8.5, ui.FontWeight.w500, CanvasInk.of(mixSrgb(Look.muted, Look.ink, .55))),
    2 => TextLook(8.5, ui.FontWeight.w600, rank <= 1 ? CanvasInk.of(Look.muted) : mixSrgb(color, Look.ink, .40)),
    _ => TextLook(8.5, ui.FontWeight.w500, mixSrgb(color, Look.ink, .70)),
  };

  /// 그 띠의 탭에 무엇이 들어가는가. 글자 폭을 아직 잴 수 없으면 null(이번 장면은 건너뛴다).
  /// 자리와 무관한 몫은 [_tabBaseOf]가 타일마다 한 번만 재고, 여기서는 남은 폭과 견주기만 한다.
  TabPlan? planTab(PaintContext c, Tile t, int i, String name, double room) {
    final memo = _tabBases[t] ??= List<_TabBase?>.filled(t.bandCount, null);
    final b = memo[i] ??= _tabBaseOf(c, t, i, name);
    if (b == null) return null;
    const up = tabNameUp;
    // 간지 탭의 어깨 몫(Look.tabExt — 지금 연표 tabParts의 ext)은 온 이름 탭에만 더한다. 첫 글자 탭은 예전 폭 그대로.
    final rkOn = b.hasRank && room >= b.base + b.rkNeed + Look.tabExt;
    final full = b.base + (rkOn ? b.rkNeed : 0) + Look.tabExt;
    if (room >= full) {
      final box = (rkOn ? b.box + b.rkNeed - 1 : b.box) + Look.tabExt;
      final keep = rkOn ? b.tags.length : b.tags.length - (b.hasRank ? 1 : 0);
      final tags = keep == b.tags.length ? b.tags : b.tags.sublist(0, keep);
      final kinds = keep == b.kinds.length ? b.kinds : b.kinds.sublist(0, keep);
      return TabPlan('full', full, box, b.name, tags, kinds, b.nameWidth);
    }
    final shortW = b.headWidth * up + 14;
    if (room >= shortW) return TabPlan('short', shortW, b.headWidth + 14, b.head, const <String>[], const <int>[], b.headWidth);
    return TabPlan.empty;
  }

  /// 탭의 밑값을 한 번 잰다. 글자 폭이 아직 준비되지 않았으면 null(보관하지 않고 다음 장면에 다시 잰다).
  _TabBase? _tabBaseOf(PaintContext c, Tile t, int i, String name) {
    final look = t.bandLook[i];
    final hs = BandLook.hsOf(look), rank = t.bandSub[i] & 7;
    final tag = t.text(t.bandTag[i]);
    final all = tag.isEmpty ? const <String>[] : tag.split('|');
    // 딱지의 차례는 늘 종류 → 실재성 → 지위. 있고 없음은 look의 실재성과 sub 0~2로 알 수 있다(계약 6-1절).
    final hasRank = rank != 0, hasHs = hs != BandLook.hsAttested;
    final kinds = <int>[];
    if (all.length - (hasRank ? 1 : 0) - (hasHs ? 1 : 0) > 0) kinds.add(0);
    if (hasHs) kinds.add(1);
    if (hasRank) kinds.add(2);
    final tags = all.length <= kinds.length ? all : all.sublist(all.length - kinds.length);
    final legendary = hs == BandLook.hsLegendary;
    final nameLook = TextLook(tabNameSize, ui.FontWeight.w700, Look.ink, spacing: -.1, italic: legendary);
    final w10 = c.text.widthOf(name, nameLook);
    if (w10 == null) return null;
    final head = _firstGlyph(name);
    final first = head == name ? w10 : c.text.widthOf(head, nameLook);
    if (first == null) return null;
    // 폭은 9.5px로 재고 글자는 9px로 그린다([tabNameUp] — 명세 2-2 · 5-3 첫째의 어긋남을 한 단계 작은 글에 그대로).
    const up = tabNameUp;
    var base = w10 * up + 14, box = w10 + 14;
    var rkNeed = 0.0;
    final looks = <TextLook>[], widths = <double>[];
    for (int k = 0; k < tags.length && k < kinds.length; k++) {
      final tagLook = _tagLook(kinds[k], 0xff000000 | t.bandColor[i], rank);
      final w = c.text.widthOf(tags[k], tagLook);
      if (w == null) return null;
      looks.add(tagLook);
      widths.add(w);
      if (kinds[k] == 2) {
        rkNeed = w + 12;
      } else {
        base += w + 12;
        box += w + 11;
      }
    }
    if (legendary) base += 2; // 이름이 기울어 조금 넓어짐
    return _TabBase(name, head, tags, kinds, looks, widths, w10, first, base, box, rkNeed, hasRank);
  }

  // ─────────────────────────── 값과 모양 ───────────────────────────

  /// 불확실한 띠(문화 · 추정 · 전승 · 미정)의 옅은 실선 테 — 제 테 빛깔을 종이와 섞은 몫(감독 건의 2026-10-15 4번 A · 고르기 판 `.claude/research/band-one/`).
  static const unsureEdge = .5;

  /// 띠의 색과 선. 지금 연표의 css 차례(뒤에 오는 규칙이 이긴다)를 그대로 따른다 — 명세 1-2 ~ 1-6절.
  /// [lifted]는 커서가 올라갔거나 고른 띠다 — 안개가 36%로 짙어지고 바탕 문화의 칠이 16%에 실선 테두리가 된다(C:1558 · C:606).
  /// 흐림([PaintPick.haze] — 기본 켬 · 감독 지적 2026-10-26 '흐림 하나로' · 고름 다 "흐린 부분은 해당하는 기간만 흐리게 해줘. 전체 흐리게 하지말고")이면
  /// 확실성 · 실재성 · 미정을 지운 보통 띠의 칠 · 테 — 띠 전체에 붙은 표시(구간 없는 추정 · 전승 연대 · 반전설 · 전설 · 논쟁 · 부정됨)는 띠를 흐리지 않고
  /// 글자(전설 기울임 · 부정 취소선 · 딱지)만 남긴다. 형식의 실재성은 나라 하나에 붙는 칸이라 구간이 없다(DLC-형식.md '나라가 있었는지 갈릴 때').
  /// 흐리는 것은 자료가 구간을 가리키는 연대 폭 · 미정 끝 · 칸의 연대 폭, 그리고 연대 폭 없는 추정 · 전승 연대의 두 끝만 짧게([shortHazeOf] — 고름 2026-10-26 04:4x)([hazePeriod] · [_hazeEnds]). 끔(`--paint-off=haze`)이면 옛 꼴([_toneNow]).
  static BandTone toneOf(int rgb, int look, {required bool fuzzy, bool lifted = false}) {
    if (!PaintPick.haze || look & BandLook.under != 0) return _toneNow(rgb, look, fuzzy: fuzzy, lifted: lifted);
    const sure = ~((BandLook.certMask << BandLook.certShift) | (BandLook.hsMask << BandLook.hsShift));
    return _toneNow(rgb, (look & sure) | (BandLook.certAccepted << BandLook.certShift), fuzzy: false, lifted: lifted);
  }

  /// 흐림 세기(구간의 칠 · 테를 종이 쪽으로 섞는 몫 — 0 = 보통 띠 · 1 = 종이): 연대 폭 · 미정 끝 · 칸의 연대 폭. 앞 걸음의 .35는 1배에서 옅은 나라 색
  /// (동예 · 부여의 연대 폭)에 잘 보이지 않아 .4로. 고른 다의 실재 논란 · 부정됨 세기는 그 표시에 구간이 없어 쓰는 데가 없다.
  static const hazePeriod = .4;

  /// 끝만 짧게 흐림의 길이 — 미정 끝과 같은 [Look.fuzzyFade](44px), 띠가 짧으면 띠 폭 [w]의 1/4.
  static double shortHazeOf(double w) => math.max(0.0, math.min(Look.fuzzyFade, w / 4));

  /// 흐림: 색 [argb]를 종이 위에 놓은 뒤 세기 [s]만큼 종이와 섞은 불투명 색(투명도가 아님 — 세로줄 얹기의 불투명 칠 결정).
  static int hazed(int argb, double s) => mixSrgb(over(argb, Look.paper), Look.paper, 1 - s);

  static BandTone _toneNow(int rgb, int look, {required bool fuzzy, bool lifted = false}) {
    final c = 0xff000000 | rgb;
    final kind = BandLook.kindOf(look), cert = BandLook.certOf(look), hs = BandLook.hsOf(look);
    final dep = look & BandLook.famDep != 0;
    final edge = mixOklab(c, Look.ink, .84), soft = mixOklab(c, Look.ink, .92);
    final radius = kind == BandKind.culture || look & BandLook.under != 0 ? 12.0 : 10.0;
    // 전승 빗금이 붙지 않는 종류: 바탕을 제 규칙으로 덮어쓰는 것들(C:292의 빗금보다 뒤에 오는 규칙 — C:1569의 목록).
    final pale = dep || fuzzy || kind == BandKind.vassal || kind == BandKind.exile || kind == BandKind.movement || kind == BandKind.federation || kind == BandKind.org || kind == BandKind.era;
    final whole = cert != BandLook.certAccepted && look & BandLook.hasRange == 0;
    // 안개 띠와 부정된 띠는 제 규칙이 덮어쓰는 바탕이 아니라 안개 · 회색 바탕에 빗금을 얹으므로 문화도 빗금이 간다(C:1569 · C:1581).
    final fogged = hs == BandLook.hsLegendary || hs == BandLook.hsSemi || hs == BandLook.hsRefuted;
    final hatch = whole && cert == BandLook.certLegend && !pale && (fogged || kind != BandKind.culture);
    // 테두리의 선: 조직체 · 복속 세력은 늘 점선. 문화 · 추정 · 전승 · 미정은 예전에 파선이었는데, 간접 · 부흥 계승선의 파선과 헷갈려(감독 건의 2026-10-15 4번 → 갈래 A)
    // 끊긴 선은 관계선만 쓰고 이 띠들은 **한 단 옅은 실선**(테 빛깔을 종이와 반씩 — 투명도가 아닌 고른 색) — 불확실은 칠(빗금 · 옅은 안개)과 이 옅은 테가 말한다.
    final dotted = kind == BandKind.org || kind == BandKind.client; // 복속 세력(묶음 3 · 3번)은 조직체의 점선 테두리를 빌린 옅은 띠
    final unsure = !dotted && (kind == BandKind.culture || fuzzy || (whole && cert >= BandLook.certEstimated));
    final stroke = dotted ? EdgeStroke.dotted : EdgeStroke.solid;
    int soften(int e) => unsure ? mixSrgb(over(e, Look.paper), Look.paper, unsureEdge) : e;
    if (look & BandLook.under != 0) {
      // 바탕 문화: 종이빛이 비치는 옅은 칠 + 점무늬 · 옅은 실선 테두리(예전 파선 — 건의 4번 A), 모서리는 위 12 · 아래 10(C:599 · C:690 · C:879).
      final rim = withAlpha(soft, .70);
      return BandTone(withAlpha(c, lifted ? .16 : .09), lifted ? rim : mixSrgb(over(rim, Look.paper), Look.paper, unsureEdge), EdgeStroke.solid, radius, radiusBottom: 10, dots: true);
    }
    if (hs == BandLook.hsLegendary || hs == BandLook.hsSemi || hs == BandLook.hsRefuted) {
      // 안개: 띠 자신은 속이 비고 한 겹이 바탕과 테두리를 그린다. 짙기는 종류에 달렸다(C:1555~1558).
      // 부정됨은 전설과 같은 안개를 색 없이 회색으로(묶음 5 · 5번 — 감독 결정 A · C 실재성 블록의 .hs-refuted).
      final refuted = hs == BandLook.hsRefuted;
      final base = refuted ? Look.muted : c;
      final fogEdge = refuted ? withAlpha(Look.muted, .50) : edge;
      final fog = lifted
          ? .36
          : (kind == BandKind.vassal || kind == BandKind.org || kind == BandKind.era || dep || kind == BandKind.exile || kind == BandKind.movement
              ? .10
              : (fuzzy || kind == BandKind.federation ? .07 : .24));
      return BandTone(
        mixSrgb(base, Look.paper, hatch ? .05 : fog), soften(fogEdge), stroke, radius,
        hatch: hatch, hatchColor: mixSrgb(base, Look.paper, .14), fog: fog,
        pole: kind == BandKind.movement ? withAlpha(refuted ? mixOklab(Look.muted, Look.ink, .84) : edge, .85) : 0,
      );
    }
    // 바탕: 종류마다 다르고, 미정의 6%는 제 바탕 규칙이 없는 보통 띠에만 이긴다(명세 5-3 열둘째).
    var pct = switch (kind) {
      BandKind.culture => .09,
      BandKind.federation => .06,
      BandKind.org => .10,
      BandKind.era => .10,
      BandKind.vassal || BandKind.exile || BandKind.movement => .09,
      _ => dep ? .09 : .24,
    };
    if (fuzzy && pct == .24) pct = .06;
    final border = switch (kind) {
      BandKind.era => withAlpha(soft, .60),
      BandKind.culture => withAlpha(soft, .70),
      _ => edge,
    };
    return BandTone(
      mixSrgb(c, Look.paper, hatch ? .05 : pct), soften(border), stroke, radius,
      hatch: hatch, hatchColor: mixSrgb(c, Look.paper, .14), dots: kind == BandKind.culture,
      pole: kind == BandKind.movement ? withAlpha(edge, .85) : 0,
    );
  }

  /// 모서리 넷을 저마다 둥글린 네모(탭의 필름 · 딱지 · 연대 폭의 끝). 반지름이 작아 조각을 굽지 않고 몇 칸으로 깎는다.
  void _rounded(PaintContext c, double l, double t, double r, double b, double tl, double tr, double br, double bl, int argb) {
    if (r <= l || b <= t) return;
    final topR = math.min(math.max(tl, tr), (b - t) / 2), botR = math.min(math.max(br, bl), (b - t) / 2);
    if (topR <= 0 && botR <= 0) {
      c.quads.add(l, t, r, b, argb);
      return;
    }
    final n = math.max(topR, botR) > 5 ? 8 : 3;
    for (int k = 0; k < n && topR > 0; k++) {
      final a = t + topR * k / n, z = t + topR * (k + 1) / n, dy = (a + z) / 2 - t;
      c.quads.add(l + _inset(tl, dy), a, r - _inset(tr, dy), z, argb);
    }
    if (b - botR > t + topR) c.quads.add(l, t + topR, r, b - botR, argb);
    for (int k = 0; k < n && botR > 0; k++) {
      final a = b - botR * (k + 1) / n, z = b - botR * k / n, dy = b - (a + z) / 2;
      c.quads.add(l + _inset(bl, dy), a, r - _inset(br, dy), z, argb);
    }
  }

  /// 반지름 [radius]의 둥근 모서리에서, 끝에서 [dy]만큼 떨어진 줄이 가장자리에서 얼마나 들어가는가.
  static double _inset(double radius, double dy) {
    if (radius <= 0 || dy >= radius) return 0;
    final k = radius - dy;
    return radius - math.sqrt(math.max(0.0, radius * radius - k * k));
  }

  /// 이름의 첫 글자(묶음 문자도 한 글자로).
  static String _firstGlyph(String name) => name.isEmpty ? name : String.fromCharCode(name.runes.first);

  /// 검색 · 창의 강조에 든 띠의 테두리(css `--warn`).
  static const _warn = 0xff000000;

  /// 고른 띠의 깊은 그늘의 색(C:331의 `rgba(45,38,26,.66)`).

  /// 조감의 띠 안 이름(BIRD_NAME = { size 10 · wt 700 · inset 6 · clear 3 })과 모양이 길어질 때의 여유 8px.
  static const _birdSize = 10.0, _birdInset = 6.0, _birdClear = 3.0, _birdGrow = 8.0;

  /// 조감의 띠 안 단추가 이름 뒤에 붙는 틈 — 지금 연표의 `_birdBtns`가 `bx = bnR + 4`로 쓴다(js:3329).
  /// 단추 층(`paint/scopes.dart`)이 [birdNameEnd]에 이 값을 더해 첫 단추의 왼쪽을 잡는다.
  static const birdBtnGap = 4.0;

  /// 무늬(명세 1-4 · 3-4 — 띠와 칸의 무늬는 각도는 같고 줄 간격이 다르다).
  static const _hatchBand = PatternSpec.stripes(135, 6, 12);
  static const _zoneEstimated = PatternSpec.stripes(90, 2, 6);
  static const _zoneLegend = PatternSpec.stripes(135, 5, 10);
  static const _dotGrid = PatternSpec.dots(9, 1.5);
}

/// 띠 하나의 가로 밝기: 옅어지는 두 끝(미정 꼬리 44px · 문화 띠 12% · 바탕 문화 10%)에
/// 고르기 · 흐림의 밝기 [base]와 기간 조명 구간([spots]는 [spotAlpha])을 곱해 둔 것이다.
/// 밝기를 색의 알파로 옮겨 같은 묶음에 넣으려고 한곳에 모았다 — saveLayer도 가림 판도 쓰지 않는다.
class _Fade {
  const _Fade(this.l, this.r, this.left, this.right, {this.base = 1, this.spots = const <(double, double, double)>[], this.spotAlpha = 1});
  final double l, r, left, right, base, spotAlpha;

  /// 흐린 띠 안에서도 밝게 남는 구간(화면 px)과 그 구간의 진행([em.Spot.glow] 0~1).
  /// 밝기는 `base + (spotAlpha − base) × glow`라 진행 0이면 띠와 같고 1이면 조명 밝기다.
  final List<(double, double, double)> spots;

  /// 한 색으로 칠해도 되는가(끊을 자리가 없는가).
  bool get flat => left <= 0 && right <= 0 && spots.isEmpty;

  /// 반드시 끊어야 하는 x 자리 — 옅은 끝이 꺾이는 곳과 조명 구간의 경계(경계는 곧은 세로).
  Iterable<double> get cuts sync* {
    if (left > 0) yield l + left;
    if (right > 0) yield r - right;
    for (final s in spots) {
      yield s.$1;
      yield s.$2;
    }
  }

  double alphaAt(double x) {
    var a = base;
    // 겹친 구간(자리를 물려주는 동안)은 가장 밝은 값을 쓴다 — 두 구간에 다 드는 곳이 잠깐 어두워지지 않게.
    for (final s in spots) {
      if (x >= s.$1 && x <= s.$2) {
        final lit = base + (spotAlpha - base) * s.$3;
        if (lit > a) a = lit;
      }
    }
    var f = 1.0;
    if (left > 0 && x < l + left) f = ((x - l) / left).clamp(0.0, 1.0);
    if (right > 0 && x > r - right) f = math.min(f, ((r - x) / right).clamp(0.0, 1.0));
    return a * f;
  }

  /// 한 칸 [a]~[z]의 두 끝 색 — 조명 경계에서는 칸 안쪽으로 살짝 들어가 재야 경계가 곧게 선다.
  (double, double) alphaSpan(double a, double z) {
    final eps = math.min(.01, (z - a) / 4);
    return (alphaAt(a + eps), alphaAt(z - eps));
  }
}

/// 조각을 찍을 네 모서리.
enum BandCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 띠 층의 작은 그림판: 둥근 모서리의 채움 사분원 · 1px 테두리 호 · 연맹의 겹줄 고리 · 간지 탭의 어깨(칠 · 선 — 실선 · 파선 · 점선).
/// scene/sprites.dart와 같은 방식(흰색으로 한 장에 그려 두고 drawRawAtlas 한 번)이되 띠에만 쓰는 조각이라 이 층에 둔다.
class BandSprites {
  /// 한 칸: (왼쪽, 위, 한 변). 사분원은 이 칸을 넷으로 나눈 것이다.
  static const disc = (0.0, 0.0, 44.0);
  static const arc10 = (44.0, 0.0, 20.0), arc12 = (64.0, 0.0, 24.0), arc22 = (0.0, 44.0, 44.0);
  static const fedOuter = (44.0, 44.0, 18.0), fedInner = (62.0, 44.0, 14.0);
  static const sheetWidth = 88.0, sheetHeight = chamTop + 26;

  /// 꼬리표의 귀 모따기(갈래 E): 10px 칸의 마름모 — 사분면 하나가 귀의 삼각형([cham] · 칠)과 그 빗변의 1px 선([chamLine] —
  /// 마름모 테를 0.5 안쪽에 그어, 띠 윗변 · 옆변의 1px 선 가운데와 꼭 맞물린다). [add]가 반지름 자리에 모따기 크기를 받아 늘이고 줄인다.
  static const chamTop = shoulderTallTop + shoulderTallH + 2;
  static const cham = (0.0, chamTop, 10.0), chamLine = (12.0, chamTop, 10.0);

  /// 큰 귀 모따기(키에 따른 귀 — 6보다 클 때): 24px 칸(사분면 12) — 늘이면 1px 빗변이 굵어지므로 큰 칸을 줄여 쓴다.
  static const chamBig = (24.0, chamTop, 24.0), chamLineBig = (50.0, chamTop, 24.0);
  static (double, double, double) chamFill(double k) => k > 6 ? chamBig : cham;
  static (double, double, double) chamEdge(double k) => k > 6 ? chamLineBig : chamLine;

  /// 간지 탭의 어깨(묶음 3 · 1번): 폭 s × 높이 11(띠 윗변 위의 몫 — 탭 높이 12의 밑 1px는 띠가 덮는다). 윤곽은 지금 연표 tabBump와 같은 S자
  /// (칠: (0,12) → 조절점 (0.6s,12) · (0.4s,0) → (s,0) · 선: 같은 꼴을 0.5 내려 1px). 어깨 7은 y 88, 어깨 4는 y 100의 줄에 8px 칸마다
  /// 칠 왼 · 칠 오 · 선 왼 · 선 오(실선) · 파선 왼 · 오 · 점선 왼 · 오.
  static const shoulderTop7 = 88.0, shoulderH = G.tab;
  static const shoulderTop4 = shoulderTop7 + shoulderH + 1;

  /// 연합의 겹 탭 뒤 장의 어깨(감독 선택 D5 덧판 x2 A): 어깨 7 · 높이 14(띠 윗변 위의 몫 — 뒤 장은 앞 장보다 3px 위에서 띠 윗변까지).
  /// 윤곽은 웹 tabBump(dx, −dy, w, h + dy) 그대로 (0,15) → (s,0)의 S자 · 실선만. y 112의 줄에 칠 왼 · 칠 오 · 선 왼 · 선 오.
  static const shoulderTallTop = shoulderTop4 + shoulderH + 1, shoulderTallH = shoulderH + BandLayer.coalBackDy;
  static ({ui.Rect fillL, ui.Rect fillR, ui.Rect lineL, ui.Rect lineR}) shouldersTall() => (
    fillL: const ui.Rect.fromLTWH(0, shoulderTallTop, 7, shoulderTallH),
    fillR: const ui.Rect.fromLTWH(8, shoulderTallTop, 7, shoulderTallH),
    lineL: const ui.Rect.fromLTWH(16, shoulderTallTop, 7, shoulderTallH),
    lineR: const ui.Rect.fromLTWH(24, shoulderTallTop, 7, shoulderTallH),
  );
  static ({ui.Rect fillL, ui.Rect fillR, ui.Rect lineL, ui.Rect lineR}) shoulders(double s, EdgeStroke stroke) {
    final y = s >= 6 ? shoulderTop7 : shoulderTop4, w = s >= 6 ? 7.0 : 4.0;
    final line = switch (stroke) { EdgeStroke.solid => 16.0, EdgeStroke.dashed => 32.0, EdgeStroke.dotted => 48.0 };
    return (
      fillL: ui.Rect.fromLTWH(0, y, w, shoulderH),
      fillR: ui.Rect.fromLTWH(8, y, w, shoulderH),
      lineL: ui.Rect.fromLTWH(line, y, w, shoulderH),
      lineR: ui.Rect.fromLTWH(line + 8, y, w, shoulderH),
    );
  }

  /// 바깥 반지름 [r]의 1px 호. 없는 반지름은 가장 가까운 칸을 줄여 쓴다(호의 굵기가 1px를 크게 벗어나지 않게).
  static (double, double, double) arc(double r) => r >= 17 ? arc22 : (r >= 11 ? arc12 : arc10);

  /// [sharing]을 주면 그 묶음의 그림판 · 배율을 같이 쓰는 둘째 묶음(내보내는 때만 다르다 — 띠 층의 밑 조각). 그림판을 한 장 더 뜨지 않는다(SVG에도 한 장).
  BandSprites({BandSprites? sharing}) : _owner = sharing;
  final BandSprites? _owner;

  ui.Image? _image;
  double _scale = 1;
  Float32List _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  Int32List _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;
  double get scale => _owner?.scale ?? _scale;

  /// 멎은 돋보기 배율(× 화면의 px 비율)이 바뀌었다 — 그림판을 그 배율로 다시 뜬다(작아서 싸다). 둘째 묶음은 제 주인의 배율을 따른다.
  void setScale(double scale) {
    if (_owner != null) return;
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  /// 칸 [cell]의 [corner] 사분면을 왼쪽 위 자리에 [size]×[size]로 찍는다.
  void add((double, double, double) cell, BandCorner corner, double left, double top, int argb, double size) {
    if (size <= 0 || ((argb >> 24) & 0xff) == 0) return;
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final half = cell.$3 / 2;
    final sx = cell.$1 + (corner == BandCorner.topRight || corner == BandCorner.bottomRight ? half : 0);
    final sy = cell.$2 + (corner == BandCorner.bottomLeft || corner == BandCorner.bottomRight ? half : 0);
    final p = _n * 4, s = scale;
    _transforms[p] = size / half / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = sx * s;
    _rects[p + 1] = sy * s;
    _rects[p + 2] = (sx + half) * s;
    _rects[p + 3] = (sy + half) * s;
    _colors[_n] = argb;
    _n++;
  }

  /// 그림판의 [src](배치 px)를 제 크기 그대로 왼쪽 위 ([left], [top])에 찍는다(간지 탭의 어깨).
  void addRect(ui.Rect src, double left, double top, int argb) {
    if (((argb >> 24) & 0xff) == 0) return;
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = scale;
    _transforms[p] = 1 / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = src.left * s;
    _rects[p + 1] = src.top * s;
    _rects[p + 2] = src.right * s;
    _rects[p + 3] = src.bottom * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    final sheet = _owner ?? this;
    final image = sheet._image ??= render(sheet._scale);
    canvas.drawRawAtlas(image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }

  static ui.Image render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    void ring((double, double, double) cell, double width) {
      final r = cell.$3 / 2;
      canvas.drawCircle(
        ui.Offset(cell.$1 + r, cell.$2 + r),
        r - width / 2,
        ui.Paint()
          ..color = const ui.Color(0xffffffff)
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }

    canvas.drawCircle(const ui.Offset(22, 22), 22, white);
    ring(arc10, 1);
    ring(arc12, 1);
    ring(arc22, 1);
    ring(fedOuter, 2);
    ring(fedInner, 1);
    // 간지 탭의 어깨: 칠(S자 아래) · 선(S자 1px — 실선 · 파선 3/2 · 점선 1/1). 오른쪽은 왼쪽을 거울에 비춘 것. 칸 밖(띠 윗변 밑 1px)은 잘라 낸다.
    for (final (y, s) in [(shoulderTop7, 7.0), (shoulderTop4, 4.0)]) {
      ui.Path curve(double x0, bool mirror, double dy) {
        double fx(double v) => mirror ? x0 + s - v : x0 + v;
        return ui.Path()
          ..moveTo(fx(0), y + shoulderH + 1)
          ..cubicTo(fx(s * .6), y + shoulderH + 1, fx(s * .4), y + dy, fx(s), y + dy);
      }
      for (final (x0, mirror) in [(0.0, false), (8.0, true)]) {
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x0, y, s, shoulderH));
        final fill = curve(x0, mirror, 0)
          ..lineTo(mirror ? x0 : x0 + s, y + shoulderH + 1)
          ..close();
        canvas.drawPath(fill, white);
        canvas.restore();
      }
      for (final (x0, dash, gap) in [(16.0, 0.0, 0.0), (32.0, 3.0, 2.0), (48.0, 1.0, 1.0)]) {
        for (final mirror in [false, true]) {
          final at = mirror ? x0 + 8 : x0;
          canvas.save();
          canvas.clipRect(ui.Rect.fromLTWH(at, y, s, shoulderH));
          final path = curve(at, mirror, .5);
          final pen = ui.Paint()
            ..color = const ui.Color(0xffffffff)
            ..isAntiAlias = true
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1;
          if (dash <= 0) {
            canvas.drawPath(path, pen);
          } else {
            // 끊어 긋기: 윗변의 가로선과 무늬가 이어지게 탭 안쪽(윗변 쪽)에서부터 센다.
            for (final m in path.computeMetrics()) {
              for (double d = m.length; d > 0; d -= dash + gap) {
                canvas.drawPath(m.extractPath(math.max(0, d - dash), d), pen);
              }
            }
          }
          canvas.restore();
        }
      }
    }
    // 겹 탭 뒤 장의 키 큰 어깨(높이 14 · 실선): 칠 (0, y + shoulderTallH + 1) → (s, y), 선은 같은 꼴을 0.5 내려 1px.
    {
      const y = shoulderTallTop, s = 7.0;
      ui.Path curve(double x0, bool mirror, double dy) {
        double fx(double v) => mirror ? x0 + s - v : x0 + v;
        return ui.Path()
          ..moveTo(fx(0), y + shoulderTallH + 1)
          ..cubicTo(fx(s * .6), y + shoulderTallH + 1, fx(s * .4), y + dy, fx(s), y + dy);
      }
      for (final (x0, mirror) in [(0.0, false), (8.0, true)]) {
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x0, y, s, shoulderTallH));
        canvas.drawPath(curve(x0, mirror, 0)..lineTo(mirror ? x0 : x0 + s, y + shoulderTallH + 1)..close(), white);
        canvas.restore();
      }
      for (final (x0, mirror) in [(16.0, false), (24.0, true)]) {
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x0, y, s, shoulderTallH));
        canvas.drawPath(
          curve(x0, mirror, .5),
          ui.Paint()
            ..color = const ui.Color(0xffffffff)
            ..isAntiAlias = true
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        canvas.restore();
      }
    }
    // 꼬리표의 귀 모따기: 칠은 마름모(사분면 = 귀의 삼각형), 선은 같은 마름모를 0.5 안쪽에서 1px로.
    {
      ui.Path diamond((double, double, double) cell, double inset) {
        final x = cell.$1, y = cell.$2, w = cell.$3, h = w / 2;
        return ui.Path()
          ..moveTo(x + h, y + inset)
          ..lineTo(x + w - inset, y + h)
          ..lineTo(x + h, y + w - inset)
          ..lineTo(x + inset, y + h)
          ..close();
      }
      canvas.drawPath(diamond(cham, 0), white);
      canvas.drawPath(diamond(chamBig, 0), white);
      canvas.drawPath(
        diamond(chamLineBig, .5),
        ui.Paint()
          ..color = const ui.Color(0xffffffff)
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawPath(
        diamond(chamLine, .5),
        ui.Paint()
          ..color = const ui.Color(0xffffffff)
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((sheetWidth * scale).ceil(), (sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }
}
