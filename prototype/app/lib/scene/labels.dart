import 'dart:typed_data';

// 사건의 이름 자리와 묶음(개수 알약) 계산. 화면과 무관한 순수 함수라 뒤의 작업자(isolate)에서 그대로 돈다.
// 규칙은 지금 연표(js/timeline.js의 _placeRow 3409~3732줄)를 그대로 옮긴 것이다 — 명세 docs/명세-3단계/02-사건의-표현.md 4절:
//  · 줄마다 따로 셈한다. 분류별 글줄이 있는 줄(look 8~15비트)에서는 사건이 제 분류의 글줄에만 놓인다.
//  · 차례는 prio(고른 사건 100 + 중요도) 내림 → 시각 오름. 이름은 오른쪽 먼저, 안 되면 왼쪽(뒤집기).
//  · 첫째 차례에 자리를 못 찾은 이름은 둘째 차례(late)에서 다섯 단계로 덜어 낸다:
//    연도 떼기 → 여백 5px → 둘 다 → 제 하위 수 알약 떼기 → 자리를 막는 이웃의 알약까지 떼기.
//  · 점은 제 띠 안쪽 9px, 이름은 띠 ±3px에 가둔다. 이름은 다른 점을 덮지 않는다(coversDot).
//  · 이름 없는 점은 이름 붙은 점 11px(묶여 있었으면 14px) 안이면 그 점에 포개고(동전 겹침),
//    남은 것끼리는 개수 알약 하나로 묶는다(같은 띠 안에서만 · 알약 폭까지 따져 이어 묶음).
//  · 보기 폭이 2,600년을 넘으면 이름 없음 · 1,300년을 넘으면 중요도 3만 · 500년을 넘으면 2 이상(문턱마다 따로 8% 이력).
// 자리는 모두 '분'에 매여 있어 옆으로 움직여도 다시 계산할 필요가 없다. 배율이 바뀌면 다시 계산한다.

/// 사건의 `look` 비트(계약 6-6). 그리는 쪽과 자리 셈이 함께 쓴다.
abstract final class EventLook {
  /// 분류 번호(255 = 분류 없음).
  static int category(int look) => look & 0xff;

  /// 분류별 글줄 번호(255 = 자유 배치).
  static int lane(int look) => (look >> 8) & 0xff;

  static bool treaty(int look) => look & 0x10000 != 0;
  static bool shared(int look) => look & 0x20000 != 0;

  /// 공동 사건의 다른 자리 — 이름을 붙이지 않는다.
  static bool pair(int look) => look & 0x40000 != 0;
  static bool child(int look) => look & 0x80000 != 0;
  static bool estimated(int look) => look & 0x100000 != 0;
  static bool legend(int look) => look & 0x200000 != 0;
  static bool unknown(int look) => look & 0x400000 != 0;
  static bool fuzzy(int look) => look & 0x800000 != 0;

  /// 하위 사건 수(0~255).
  static int kids(int look) => (look >> 24) & 0xff;

  /// 이름을 기울이는가 — 추정 · 전승 · 미정.
  static bool italic(int look) => look & 0x700000 != 0;

  /// 자리 셈이 쓰는 점의 폭 — 지금 연표 `_placeRow`의 `dotW`(js:3546) 그대로다(명세 3.3).
  /// 조약을 따로 재지 않아 마름모도 7px으로 셈한다 — 화면에 그리는 폭은 [dotBox]다(명세 8.3-6).
  static double dotWidth(int look) => unknown(look) ? 10 : (shared(look) ? 9 : (child(look) ? 5 : 7));

  /// 화면의 점 상자 폭(css `.tl-ev .d`의 width) — **그릴 때의 자리**와 이름 줄의 조각 자리가 이 값을 쓴다.
  /// 배치가 쓰는 [dotWidth]와 일부러 다르다: 조약의 마름모는 css가 5 · 6.4 · 4px이고, 그만큼 이름이 점 쪽으로 붙는다.
  /// [small]은 좁은 띠의 작은 점 · 조감(css 1789~1795).
  static double dotBox(int look, {bool small = false}) {
    if (small) {
      if (treaty(look)) return 4;
      if (shared(look) || unknown(look)) return 7;
      return child(look) ? 4 : 5;
    }
    if (treaty(look)) {
      if (unknown(look)) return 6.4;
      // 제 자리의 조약(공동이면서 다른 자리 · 확실성이 아닌 것)은 채운 5px 마름모로 되돌린다.
      if (shared(look) && !pair(look) && !estimated(look) && !legend(look)) return 5;
      if (shared(look) || estimated(look) || legend(look)) return 6.4;
      return child(look) ? 4 : 5;
    }
    return unknown(look) ? 10 : (shared(look) ? 9 : (child(look) ? 5 : 7));
  }

  /// 점 가운데가 `it.x`에서 얼마나 비껴 있는가(배치 px) — `.tl-ev`의 `translateX`(보통 −3.5 · 뒤집으면 −100%+3.5 ·
  /// 작은 점 · 조감은 −2.5)와 `padding-right: 2px`이 만드는 어긋남이다(명세 8.3-1 · 9.4).
  /// 뒤집힌 작은 점은 지금 연표에도 없다(작은 점은 이름이 없는 점에만 붙는다).
  static double dotDx(int look, {int side = LabelSide.none, bool small = false}) {
    final w = dotBox(look, small: small);
    if (side == LabelSide.left) return 1.5 - w / 2;
    return -(small ? 2.5 : 3.5) + w / 2;
  }

  /// 점의 반지름 + 둘레(좁은 띠에서 작은 점 · 숨김을 가르는 값 — 명세 4.4).
  static double dotRadius(int look, bool small) => small
      ? (shared(look) || unknown(look) || child(look) ? 3.5 : 4.5)
      : (shared(look) ? 7.5 : (unknown(look) ? 5 : (child(look) ? 4.5 : 6.5)));
}

abstract final class LabelSide {
  static const none = 0, right = 1, left = 2;
}

/// 보이는 점의 표시.
abstract final class LabelFlag {
  /// 연도 글을 붙였다 · 하위 수 알약을 붙였다 · 작은 점 · 동전 겹침(뒤에 포갠 점이 있다) · 앞 판에서 연도를 떼었다.
  static const year = 1, count = 2, small = 4, more = 8, shedYear = 16;
}

/// 묶음(개수 알약)의 표시: 작은 알약 · 셀 수 없는 나머지가 섞였다(눈금을 다 찍을 수 없다).
abstract final class ClusterFlag {
  static const small = 1, partial = 2;
}

abstract final class LabelGeo {
  static const lineHeight = 21.0;

  /// 점을 띠 안쪽으로 당기는 여백(반지름 3.5 + 둘레 3 + 테두리 1).
  static const dotInset = 9.0;

  /// 이름이 다른 점을 덮는지 볼 때의 점 반지름(js의 DOT).
  static const dotReach = 6.0;

  /// 둘째 차례의 좁힌 여백(LAB_TIGHT) · 새 이름의 여유 · 묶는 문턱과 푸는 문턱.
  static const tight = 5.0, newMargin = 4.0, tie = 11.0, untie = 14.0;

  /// 이름 줄의 밑값(점 7 + 사이 6 + 뒤 여백 2 + 여유 2, 하위는 점 5 기준) · 하위 수 알약 한 칸(사이 6 + 앞 4 + 안 8).
  static const base = 17.0, childBase = 14.0, countPad = 18.0;

  /// 이름 ↔ 곁들임 사이(flex gap)와 하위 수 알약의 앞 여백.
  static const gap = 6.0, countMargin = 4.0;

  /// 개수 알약: 보통 높이 14 · 작은 알약 높이 10, 띠 안쪽 여백 4 · 2 · 조감 5.
  static const pillHeight = 14.0, smallPillHeight = 10.0, pillInset = 4.0, smallPillInset = 2.0, birdPillInset = 5.0;

  /// 띠 바깥 끝에서 점의 둘레까지 적어도(테두리 1px · 조감은 테두리 1 + 관문 3 + 0.5).
  static const bandEdge = 1.0, birdEdge = 4.5;

  static double pillWidth(int count) => 13 + 6.2 * '$count'.length;
  static double smallPillWidth(int count) => 9 + 5.0 * '$count'.length;

}

/// 이름 줄의 조각 자리(점의 가로 자리에서 잰 배치 px). 뒤집힌 이름(`side == left`)은 왼쪽부터 연도 → 알약 → 이름 → 점이다.
class LabelRun {
  const LabelRun(this.nameLeft, this.nameRight, this.countLeft, this.countRight, this.yearLeft, this.yearRight);
  final double nameLeft, nameRight, countLeft, countRight, yearLeft, yearRight;

  /// 점과 글자를 모두 품은 구간(뒤의 빈 여백은 뺀 것 — js의 sl ~ sr).
  double get left => yearLeft < nameLeft ? yearLeft : (countLeft < nameLeft ? countLeft : nameLeft);
  double get right => yearRight > nameRight ? yearRight : (countRight > nameRight ? countRight : nameRight);
}

/// [LabelRun]과 같은 값을 담되 덮어써 다시 쓰는 그릇 — 장면마다 수백 개의 새 객체를 만들지 않으려고 그리는 쪽이 하나만 두고 돌려 쓴다.
class LabelRunBox {
  double nameLeft = 0, nameRight = 0, countLeft = 0, countRight = 0, yearLeft = 0, yearRight = 0;

  /// 점과 글자를 모두 품은 구간(뒤의 빈 여백은 뺀 것 — js의 sl ~ sr).
  double get left => yearLeft < nameLeft ? yearLeft : (countLeft < nameLeft ? countLeft : nameLeft);
  double get right => yearRight > nameRight ? yearRight : (countRight > nameRight ? countRight : nameRight);
}

/// 이름 · 하위 수 알약 · 연도가 실제로 놓이는 자리. 차례는 점 → 이름 → 알약 → 연도(뒤집으면 거울).
/// 점의 폭은 **화면의 상자 폭**([EventLook.dotBox])이다 — 흐름(flex)이 그 폭만큼 이름을 밀어내기 때문이고,
/// 배치가 셈에 쓰는 [EventLook.dotWidth]와 다른 조약에서는 이름이 4px 점 쪽으로 붙는다(명세 8.3-6 · 기준 덤프 #344).
void labelRunInto(LabelRunBox box, {required double x, required int side, required int look, required double nameWidth, required double countWidth, required double yearWidth}) {
  final dotW = EventLook.dotBox(look);
  final cnt = countWidth > 0 ? countWidth + 8 : 0.0;
  if (side == LabelSide.left) {
    final nameRight = x - 4.5 - dotW, nameLeft = nameRight - nameWidth;
    final countRight = cnt > 0 ? nameLeft - LabelGeo.gap : nameLeft, countLeft = countRight - cnt;
    final head = cnt > 0 ? countLeft - LabelGeo.countMargin : nameLeft;
    final yearRight = yearWidth > 0 ? head - LabelGeo.gap : head;
    box
      ..nameLeft = nameLeft
      ..nameRight = nameRight
      ..countLeft = countLeft
      ..countRight = countRight
      ..yearLeft = yearRight - yearWidth
      ..yearRight = yearRight;
    return;
  }
  final nameLeft = x + dotW + 2.5, nameRight = nameLeft + nameWidth;
  final countLeft = nameRight + (cnt > 0 ? LabelGeo.gap + LabelGeo.countMargin : 0), countRight = countLeft + cnt;
  final yearLeft = (cnt > 0 ? countRight : nameRight) + (yearWidth > 0 ? LabelGeo.gap : 0);
  box
    ..nameLeft = nameLeft
    ..nameRight = nameRight
    ..countLeft = countLeft
    ..countRight = countRight
    ..yearLeft = yearLeft
    ..yearRight = yearLeft + yearWidth;
}

final _runBox = LabelRunBox();

/// 값을 그대로 둔 채 돌려주는 판(한 번 쓰고 마는 곳에서). 되풀이되는 곳은 [labelRunInto]로 그릇을 돌려 쓴다.
LabelRun labelRun({required double x, required int side, required int look, required double nameWidth, required double countWidth, required double yearWidth}) {
  labelRunInto(_runBox, x: x, side: side, look: look, nameWidth: nameWidth, countWidth: countWidth, yearWidth: yearWidth);
  final b = _runBox;
  return LabelRun(b.nameLeft, b.nameRight, b.countLeft, b.countRight, b.yearLeft, b.yearRight);
}

class LabelInput {
  LabelInput({
    required this.version,
    required this.pxPerMinute,
    required this.spanYears,
    required this.at,
    required this.row,
    required this.importance,
    required this.eventId,
    required this.look,
    required this.band,
    required this.nameWidth,
    required this.yearWidth,
    required this.countWidth,
    required this.kids,
    required this.bandLo,
    required this.bandHi,
    required this.precLo,
    required this.precHi,
    required this.pillLo,
    required this.pillHi,
    required this.pillRow,
    required this.pillRest,
    required this.rowBase,
    required this.rowLines,
    required this.expandedKeys,
    this.zoneAt,
    this.zoneLo,
    this.zoneHi,
    this.zoneLine,
    this.zoneNoDot,
    this.zoneSq,
    this.zoneDir,
    this.zoneSig,
    this.pillCatAt,
    this.pillCat,
    this.pillCatCount,
    this.selectedEventId = 0,
    this.highlighted,
    this.bird = false,
    this.previous,
  });

  /// 판 번호. 늦게 온 결과를 버리는 데 쓴다.
  final int version;
  final double pxPerMinute, spanYears;

  /// 후보(대표 사건)마다: 시각(분) · 줄 · 중요도 · 사건 번호 · 모양(계약 6-6) · 든 띠의 번호.
  final Float64List at;
  final Int32List row, importance, eventId, band;
  final Uint32List look;

  /// 이름 · 이름 옆 연도 글 · 하위 수 글의 폭(px, 아직 모르면 이름은 NaN · 나머지는 0).
  final Float32List nameWidth, yearWidth, countWidth;

  /// 그 사건에 접힌 하위 사건이 몇인가(펼쳐졌으면 0) — 이름 뒤의 작은 알약.
  final Int32List kids;

  /// 후보가 든 띠의 분 범위 — 점과 이름은 그 안에 머문다. 띠가 없거나 끝을 모르면 ∓무한대.
  final Float64List bandLo, bandHi;

  /// 시작 날짜의 정밀도가 덮는 구간(분). 없으면 NaN — 점은 제 시각에 선다.
  final Float64List precLo, precHi;

  /// 통마다: 분 범위 · 줄 · 대표를 뺀 나머지 개수.
  final Float64List pillLo, pillHi;
  final Int32List pillRow, pillRest;

  /// 통마다의 분류 비율(자료 처리부가 알약 구역에 실어 주면) — 통 `p`의 것은 `[pillCatAt[p], pillCatAt[p+1])`의
  /// (분류 번호 [pillCat], 개수 [pillCatCount])다. 아직 열이 없으면 셋 다 null이고 색줄은 대표의 분류로만 센다.
  final Int32List? pillCatAt, pillCat, pillCatCount;

  /// 줄의 글줄 수: rowLines[줄 - rowBase].
  final int rowBase;
  final Int32List rowLines;

  /// 이번 판에 펼쳐진 부모 사건의 열쇠(그리는 쪽이 90px 문턱으로 고른다) — 다음 판의 이력으로 그대로 돌려준다.
  final Int32List expandedKeys;

  /// 이름(과 세기 2면 점)이 비켜 갈 구간(reserved.dart) — 줄 `rowBase + i`의 것은 `[zoneAt[i], zoneAt[i+1])`.
  /// 자리는 분이고, `zoneLine`이 −1이면 그 줄의 모든 글줄이다. 아무것도 없으면 null.
  final Int32List? zoneAt, zoneLine, zoneNoDot;
  final Float64List? zoneLo, zoneHi;

  /// 구간의 **세기**(지금 연표 `_placeRow`의 `blocks` 세 갈래): 0 = 이름 줄 전체를 막음(소속 · 대범위 단추 · 내림줄 —
  /// js의 `reserved[row][0].push([l, r])`처럼 셋째 값이 없는 것) · 1 = 글자 상자만(글줄 둘 이상의 건국 · 멸망 네모) ·
  /// 2 = 글자의 먹 구간과 점까지(글줄 하나의 네모). 없으면 [zoneNoDot]으로 1 · 2만 가른다.
  final Int32List? zoneSq;

  /// [zoneNoDot]인 구간이 점을 미는 쪽(지금 연표 `avoid`의 `dir`): +1 오른쪽 · −1 왼쪽. 부풀리는 폭이 그만큼 비대칭이다.
  final Int32List? zoneDir;

  /// 줄마다의 구간 생김새 지문(`zoneSig[줄 − rowBase]`). 앞 판과 다른 줄은 **이름 이력을 한 번 버린다** —
  /// 구간은 그리기보다 한 장면 늦게 오므로, 구간이 없던 장면에 놓인 이름이 이력 때문에 여유 0으로 눌러앉는 것을 막는다.
  final Int32List? zoneSig;

  final int selectedEventId;

  /// 강조(검색 · 창의 조명)에 든 사건 — 이름 자리에서 앞선다(지금 연표 prio의 +10 · 명세 06 3-2의 hiLayout).
  final Set<int>? highlighted;

  /// 조감(밀도 2): 이름을 아예 붙이지 않고 점 · 알약도 작게(명세 05 7.5 · 02 4.1의 `ctx.minImp = 99`).
  final bool bird;
  final LabelOutput? previous;

  /// 같은 입력에 앞 판의 결과(이력)만 바꿔 단 것.
  LabelInput withPrevious(LabelOutput? previous) => LabelInput(
    version: version, pxPerMinute: pxPerMinute, spanYears: spanYears, at: at, row: row, importance: importance, eventId: eventId, look: look, band: band,
    nameWidth: nameWidth, yearWidth: yearWidth, countWidth: countWidth, kids: kids, bandLo: bandLo, bandHi: bandHi, precLo: precLo, precHi: precHi,
    pillLo: pillLo, pillHi: pillHi, pillRow: pillRow, pillRest: pillRest, rowBase: rowBase, rowLines: rowLines, expandedKeys: expandedKeys,
    zoneAt: zoneAt, zoneLo: zoneLo, zoneHi: zoneHi, zoneLine: zoneLine, zoneNoDot: zoneNoDot, zoneSq: zoneSq, zoneDir: zoneDir, zoneSig: zoneSig,
    pillCatAt: pillCatAt, pillCat: pillCat, pillCatCount: pillCatCount,
    selectedEventId: selectedEventId, highlighted: highlighted, bird: bird, previous: previous,
  );
}

class LabelOutput {
  LabelOutput({
    required this.version,
    required this.shownCandidate,
    required this.shownLine,
    required this.shownSide,
    required this.shownExtra,
    required this.shownCoins,
    required this.shownFlags,
    required this.shownAt,
    required this.shownPrec,
    required this.clusterAt,
    required this.clusterRow,
    required this.clusterLine,
    required this.clusterCount,
    required this.clusterFlags,
    required this.clusterWidth,
    required this.clusterLo,
    required this.clusterHi,
    required this.clusterLead,
    required this.clusterBandLo,
    required this.clusterBandHi,
    required this.clusterTickAt,
    required this.clusterTick,
    required this.clusterCatAt,
    required this.clusterCat,
    required this.clusterCatCount,
    required this.minImportance,
    required this.gates,
    required this.deferred,
    required this.shownEventId,
    required this.tiedEventIds,
    required this.expandedKeys,
    this.zoneSig,
    this.zoneSigBase = 0,
    this.clusterIds,
  });
  final int version;

  /// 보이는 점마다: 후보 번호 · 글줄 · 이름 자리(없음/오른쪽/왼쪽) · 이름 뒤 하위 수 알약의 수 · 뒤에 포갠 점의 수 · 표시([LabelFlag]).
  final Int32List shownCandidate, shownLine, shownSide, shownExtra, shownCoins, shownFlags;

  /// 점이 실제로 놓인 시각(분) — 적은 시각에 띠 안쪽 가두기가 반영된 값(날짜를 모르는 점도 옮겨 가지 않는다).
  final Float64List shownAt;

  /// 모르는 구간이 화면에서 넉넉해진 정도 f(0~1) — 점의 풍선 글에 모른다는 말을 붙일지(예전 정밀도 괄호의 짙기와 같은 문턱).
  final Float32List shownPrec;

  /// 묶음(개수 알약)마다: 알약 가운데(분) · 줄 · 글줄 · 숫자 · 표시([ClusterFlag]) · 폭(px) · 자리 선의 양 끝(분) · 든 띠의 분 범위.
  final Float64List clusterAt, clusterLo, clusterHi, clusterBandLo, clusterBandHi;
  final Int32List clusterRow, clusterLine, clusterCount, clusterFlags;

  /// 대표의 후보 번호(대표가 없는 통의 알약이면 −1) — 알약의 색을 그 띠에서 끌어낸다.
  final Int32List clusterLead;
  final Float32List clusterWidth;

  /// 묶음마다의 눈금(묶인 점의 시각) — clusterTickAt[i] ~ clusterTickAt[i+1].
  final Int32List clusterTickAt;
  final Float64List clusterTick;

  /// 눈금과 같은 자리의 사건 번호(묶인 점의 사건) — 렌즈가 '그 주제의 사건이 하나라도 든 묶음'을 가린다(웹의 `.tl-clu.is-lens`).
  /// 옛 꼴로 만든 판(검사의 손 판)에는 없다(null).
  final Int32List? clusterIds;

  /// 묶음마다의 분류 비율 색줄 — clusterCatAt[i] ~ clusterCatAt[i+1]의 (분류 번호, 개수).
  final Int32List clusterCatAt, clusterCat, clusterCatCount;

  /// 이름을 보인 가장 낮은 중요도(이름 없음이면 99)와 문턱 셋의 상태 — 다음 판의 이력.
  final int minImportance, gates;

  /// 이름 폭을 아직 몰라 미룬 후보 수.
  final int deferred;

  /// 다음 판의 이력: 보인 점의 사건 번호(shownCandidate와 같은 순서)와, 한데 묶인 사건 번호들.
  final Int32List shownEventId;
  final List<Int32List> tiedEventIds;

  /// 이번 판에 펼쳐진 부모 사건의 열쇠(문턱 둘의 이력).
  final Int32List expandedKeys;

  /// 이번 판의 줄마다의 구간 생김새 지문(`zoneSig[줄 − zoneSigBase]`) — 다음 판이 달라진 줄을 가려내는 이력.
  final Int32List? zoneSig;
  final int zoneSigBase;

  int get shownCount => shownCandidate.length;

  /// 묶음(개수 알약)의 수.
  int get clusters => clusterAt.length;
}

/// 보기 폭(년)에 따른 이름의 중요도 문턱 셋(2,600 · 1,300 · 500년). 켜져 있던 문턱은 8%까지 버틴다(지금 연표의 `_past`).
int importanceGates(double spanYears, int? previous) {
  final was = previous ?? 0;
  bool on(double limit, int bit) => limit / spanYears >= (was & bit != 0 ? .92 : 1);
  return (on(2600, 1) ? 1 : 0) | (on(1300, 2) ? 2 : 0) | (on(500, 4) ? 4 : 0);
}

int minImportanceOf(int gates) => gates & 1 == 0 ? 99 : (gates & 2 == 0 ? 3 : (gates & 4 == 0 ? 2 : 1));

/// 보기 폭에서 바로 문턱을 얻는 짧은 길([previous]는 앞 판의 [LabelOutput.gates]).
int minImportanceFor(double spanYears, int? previous) => minImportanceOf(importanceGates(spanYears, previous));

/// 글줄 하나에서 차지한 가로 구간. 지금 연표의 `subs[k]`가 담는 여섯 값과 같다.
class _Zone {
  _Zone(this.l, this.r, this.sq, this.sl, this.sr, {this.pillFlip = false, this.pillWidth = 0, this.owner = -1});
  double l, r, sl, sr, pillWidth;

  /// 0 = 놓인 이름이 차지한 구간 · 1 = 건국/멸망 네모(글자 상자만 비킴) · 2 = 같은 네모인데 먹 구간과 점까지 비킴 ·
  /// 3 = 밖에서 온 세기 0(소속 · 대범위 단추 · 내림줄 — 이름 줄 전체를 막는 굳은 자리).
  final int sq;
  bool pillFlip;
  int owner;
}

/// 이름 한 자리의 가장자리들(명세 3.3).
class _Try {
  const _Try(this.flip, this.l, this.r, this.tl, this.tr, this.gl, this.gr, this.sl, this.sr);
  final bool flip;
  final double l, r, tl, tr, gl, gr, sl, sr;
}

class _Placed {
  _Placed(this.index);
  final int index;
  int line = 0, side = LabelSide.none, flags = 0, extra = 0, coins = 0;
  double x = 0, prec = 0;
  bool hidden = false, off = false, small = false, more = false;
}

LabelOutput placeLabels(LabelInput input) {
  final n = input.at.length, scale = input.pxPerMinute;
  final previous = input.previous;
  final gates = importanceGates(input.spanYears, previous?.gates);
  // 조감에서는 이름을 아예 따져 보지 않는다(지금 연표 js:7004의 `ctx.minImp = 99`) — 점과 알약은 그대로 그린다.
  final minImp = input.bird ? 99 : minImportanceOf(gates);

  // 비켜 갈 구간이 달라진 줄: 그 줄의 이름 이력을 **한 번 버린다**. 구간은 그리기보다 한 장면 늦게 도착하므로(reserved.dart),
  // 구간이 없던 장면에 놓인 이름이 이력 때문에 여유 0으로 눌러앉아 지금 연표에는 없는 이름이 붙어 버린다.
  final zoneChanged = <int>{};
  final sig = input.zoneSig, was = previous?.zoneSig;
  if (sig != null && was != null) {
    for (int i = 0; i < sig.length; i++) {
      final row = input.rowBase + i, j = row - previous!.zoneSigBase;
      if (j >= 0 && j < was.length && was[j] != sig[i]) zoneChanged.add(row);
    }
  }

  // 앞 판의 이력: 함께 묶여 있던 사건, 이름을 보였던 글줄 · 쪽 · 연도를 떼었는지.
  final tiedWith = <int, int>{};
  final namedBefore = <int, int>{}; // 사건 번호 → 글줄 << 2 | 쪽
  final shedYearBefore = <int>{};
  if (previous != null) {
    for (int g = 0; g < previous.tiedEventIds.length; g++) {
      for (final id in previous.tiedEventIds[g]) {
        tiedWith[id] = g;
      }
    }
    // 달라진 줄이 없으면 사건 번호 → 줄 맞표는 쓸 데가 없다. 후보가 수천인 돋보기 구간에서 장면마다 짓지 않도록 가른다.
    final rowOf = zoneChanged.isEmpty ? const <int, int>{} : {for (int i = 0; i < n; i++) input.eventId[i]: input.row[i]};
    for (int i = 0; i < previous.shownCount; i++) {
      if (previous.shownSide[i] == LabelSide.none) continue;
      final id = previous.shownEventId[i];
      final row = rowOf[id];
      if (row != null && zoneChanged.contains(row)) continue;
      namedBefore[id] = previous.shownLine[i] << 2 | previous.shownSide[i];
      if (previous.shownFlags[i] & LabelFlag.shedYear != 0) shedYearBefore.add(id);
    }
  }

  // 줄마다 따로 셈한다. 사건이 하나도 없어도 통의 나머지만 있는 줄은 알약을 세워야 하니 함께 돈다.
  final byRow = <int, List<int>>{};
  for (int i = 0; i < n; i++) {
    (byRow[input.row[i]] ??= []).add(i);
  }
  for (int p = 0; p < input.pillRest.length; p++) {
    if (input.pillRest[p] > 0) byRow[input.pillRow[p]] ??= [];
  }

  final placed = <_Placed>[];
  final tied = <Int32List>[];
  final clusters = <_Cluster>[];
  int deferred = 0;
  for (final row in byRow.keys.toList()..sort()) {
    deferred += _placeRow(input, row, byRow[row]!, minImp, tiedWith, namedBefore, shedYearBefore, placed, tied, clusters);
  }

  final shown = [for (final p in placed) if (!p.hidden && !p.off) p];
  final tickAt = Int32List(clusters.length + 1), catAt = Int32List(clusters.length + 1);
  final ticks = <double>[], cats = <int>[], catCounts = <int>[], tickIds = <int>[];
  for (int i = 0; i < clusters.length; i++) {
    tickAt[i] = ticks.length;
    catAt[i] = cats.length;
    for (final m in clusters[i].members) {
      ticks.add(m.x / scale);
      tickIds.add(input.eventId[m.index]);
    }
    clusters[i].categories.forEach((cat, count) {
      cats.add(cat);
      catCounts.add(count);
    });
  }
  tickAt[clusters.length] = ticks.length;
  catAt[clusters.length] = cats.length;

  return LabelOutput(
    version: input.version,
    shownCandidate: Int32List.fromList([for (final p in shown) p.index]),
    shownLine: Int32List.fromList([for (final p in shown) p.line]),
    shownSide: Int32List.fromList([for (final p in shown) p.side]),
    shownExtra: Int32List.fromList([for (final p in shown) p.extra]),
    shownCoins: Int32List.fromList([for (final p in shown) p.coins]),
    shownFlags: Int32List.fromList([for (final p in shown) p.flags | (p.small ? LabelFlag.small : 0) | (p.more ? LabelFlag.more : 0)]),
    shownAt: Float64List.fromList([for (final p in shown) p.x / scale]),
    shownPrec: Float32List.fromList([for (final p in shown) p.prec]),
    clusterAt: Float64List.fromList([for (final c in clusters) c.x / scale]),
    clusterRow: Int32List.fromList([for (final c in clusters) c.row]),
    clusterLine: Int32List.fromList([for (final c in clusters) c.line]),
    clusterCount: Int32List.fromList([for (final c in clusters) c.count]),
    clusterFlags: Int32List.fromList([for (final c in clusters) c.flags]),
    clusterWidth: Float32List.fromList([for (final c in clusters) c.width]),
    clusterLo: Float64List.fromList([for (final c in clusters) c.lo / scale]),
    clusterHi: Float64List.fromList([for (final c in clusters) c.hi / scale]),
    clusterLead: Int32List.fromList([for (final c in clusters) c.lead]),
    clusterBandLo: Float64List.fromList([for (final c in clusters) c.bandLo]),
    clusterBandHi: Float64List.fromList([for (final c in clusters) c.bandHi]),
    clusterTickAt: tickAt,
    clusterTick: Float64List.fromList(ticks),
    clusterCatAt: catAt,
    clusterCat: Int32List.fromList(cats),
    clusterCatCount: Int32List.fromList(catCounts),
    minImportance: minImp,
    gates: gates,
    deferred: deferred,
    shownEventId: Int32List.fromList([for (final p in shown) input.eventId[p.index]]),
    tiedEventIds: tied,
    expandedKeys: input.expandedKeys,
    zoneSig: input.zoneSig,
    zoneSigBase: input.rowBase,
    clusterIds: Int32List.fromList(tickIds),
  );
}

class _Cluster {
  _Cluster(this.row, this.line, this.members, this.lead, this.lo, this.hi, this.x, this.width, this.flags, this.bandLo, this.bandHi, this.count, this.categories);
  final int row, line, lead, flags;
  final List<_Placed> members;
  final double lo, hi, x, width, bandLo, bandHi;
  int count;
  final Map<int, int> categories;
}

/// 줄 하나의 배치. 돌려주는 값은 이름 폭을 몰라 미룬 후보 수.
int _placeRow(
  LabelInput input,
  int row,
  List<int> candidates,
  int minImp,
  Map<int, int> tiedWith,
  Map<int, int> namedBefore,
  Set<int> shedYearBefore,
  List<_Placed> out,
  List<Int32List> tied,
  List<_Cluster> clusters,
) {
  final scale = input.pxPerMinute;
  final at = input.at, look = input.look;
  final lines = _linesOf(input, row);
  int deferred = 0;

  // 비켜 갈 구간(건국 · 멸망 네모 · 소속/대범위 단추 · 내림줄 — reserved.dart가 줄마다 적어 준다).
  // 세기 0은 이름 줄 전체를 막고(단추 · 내림줄), 1은 글자 상자만(네모), 2는 먹 구간과 점까지 비킨다(글줄 하나의 네모).
  final zoneAt = input.zoneAt;
  final zoneIndex = row - input.rowBase;
  int zoneFrom = 0, zoneTo = 0;
  if (zoneAt != null && zoneIndex >= 0 && zoneIndex + 1 < zoneAt.length) {
    zoneFrom = zoneAt[zoneIndex];
    zoneTo = zoneAt[zoneIndex + 1];
  }
  final zoneSq = input.zoneSq;
  int sqOf(int z) => zoneSq != null && z < zoneSq.length ? zoneSq[z] : (input.zoneNoDot![z] != 0 ? 2 : 1);

  final highlighted = input.highlighted;
  int prio(int i) =>
      (input.eventId[i] == input.selectedEventId ? 100 : 0) +
      (highlighted != null && highlighted.contains(input.eventId[i]) ? 10 : 0) +
      input.importance[i];
  final order = candidates.toList()
    ..sort((a, b) {
      final byPrio = prio(b).compareTo(prio(a));
      if (byPrio != 0) return byPrio;
      final byAt = at[a].compareTo(at[b]);
      return byAt != 0 ? byAt : input.eventId[a].compareTo(input.eventId[b]);
    });
  final count = order.length;

  // 점의 가로 자리: 저장소가 실은 시각 그대로 → 제 띠 안쪽 9px로 당기기(inside). 날짜 · 시각을 다 모르는 점(연도만 · 달까지만 · 날까지만 ·
  // 세기로 적은 것)은 내보내기가 이미 그 구간 가운데(또는 사건의 자리 spot)에 놓아 싣고, 확대해도 옮겨 가지 않는다 —
  // 감독 결정 2026-10-14 "일 기준까지 확대해도 범위로 진행하지 말 것 · 중간으로 · 사건에서 위치를 조정할 수 있게".
  double insideBand(int i, double x, double margin) {
    final lo = input.bandLo[i] * scale + margin, hi = input.bandHi[i] * scale - margin;
    if (!lo.isFinite && !hi.isFinite) return x;
    if (hi <= lo) return (input.bandLo[i] * scale + input.bandHi[i] * scale) / 2;
    return x < lo ? lo : (x > hi ? hi : x);
  }

  /// 점을 `noDot` 구간의 가장 가까운 바깥으로 민다(지금 연표의 `avoid`). 세기와는 따로다 — 지금 연표도 목록이 둘이고,
  /// 단추는 세기 0이면서 글줄이 하나인 줄(과 분류별 글줄이 있는 줄의 첫 글줄)에서는 점을 민다.
  /// 부풀리기는 **미는 쪽([ReservedZone.dir])에 따라 비대칭**이다: 오른쪽(건국 네모 · 단추)은 `[a−4.5, b+8]`,
  /// 왼쪽(멸망 네모)은 `[a−10, b+4.5]`.
  double avoidZones(int i, double x, int lane) {
    final dirs = input.zoneDir;
    for (int z = zoneFrom; z < zoneTo; z++) {
      if (input.zoneNoDot![z] == 0) continue;
      final line = input.zoneLine![z];
      if (line >= 0 && line != lane) continue;
      final lo = input.zoneLo![z] * scale, hi = input.zoneHi![z] * scale;
      final back = dirs != null && z < dirs.length && dirs[z] < 0;
      final a = lo - (back ? 10 : 4.5), b = hi + (back ? 4.5 : 8);
      if (x <= a || x >= b) continue;
      x = x - a < b - x ? a : b;
    }
    return x;
  }

  final xs = Float64List(count), precF = Float64List(count);
  for (int k = 0; k < count; k++) {
    final i = order[k];
    final t = at[i];
    // 정밀도 구간이 화면에서 넉넉해진 정도(14 → 50px)는 점의 풍선 글 뒤에 모른다는 말을 붙일지에만 쓴다(점 자리는 그대로).
    if (!input.precLo[i].isNaN) {
      final w = (input.precHi[i] - input.precLo[i]) * scale;
      final u = ((w - 14) / 36).clamp(0.0, 1.0);
      precF[k] = u * u * (3 - 2 * u);
    }
    final lane = EventLook.lane(look[i]);
    xs[k] = avoidZones(i, insideBand(i, t * scale, LabelGeo.dotInset), lane < lines ? lane : -1);
  }
  // 점 덮기(coversDot)를 빨리 보기 위해 가로 순서를 따로 둔다 — 줄에 점이 수천이어도 이웃만 본다.
  final byX = List<int>.generate(count, (k) => k)..sort((a, b) => xs[a].compareTo(xs[b]));
  final sortedX = Float64List.fromList([for (final k in byX) xs[k]]);
  final dotLine = Int32List(count);
  for (int k = 0; k < count; k++) {
    final lane = EventLook.lane(look[order[k]]);
    dotLine[k] = lane < lines ? lane : -1;
  }

  int lowerBound(double v) {
    int lo = 0, hi = count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sortedX[mid] < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  bool coversDot(int line, double a, double b, int self) {
    for (int p = lowerBound(a - LabelGeo.dotReach); p < count; p++) {
      if (sortedX[p] - LabelGeo.dotReach >= b) break;
      final k = byX[p];
      if (k == self) continue;
      if ((sortedX[p] - xs[self]).abs() < 1.5) continue; // 같은 해의 점은 원래 한자리
      if (dotLine[k] == -1 || dotLine[k] == line) return true;
    }
    return false;
  }

  final subs = List.generate(lines, (_) => <_Zone>[], growable: false);
  for (int z = zoneFrom; z < zoneTo; z++) {
    final l = input.zoneLo![z] * scale, r = input.zoneHi![z] * scale;
    // 세기 0은 안에서 쓰는 3(굳은 자리)으로 — 놓인 이름이 만드는 0과 갈라 둔다.
    final s = sqOf(z);
    final zone = _Zone(l, r, s == 0 ? 3 : s, l, r);
    final line = input.zoneLine![z];
    if (line >= 0 && line < lines) {
      subs[line].add(zone);
    } else {
      for (final s in subs) {
        s.add(zone);
      }
    }
  }
  final items = List<_Placed>.generate(count, (k) => _Placed(order[k])..x = xs[k]..prec = precF[k]);

  bool blocks(List<_Zone> zones, _Try t, double margin, double tight, List<_Zone>? shed) {
    for (final z in zones) {
      if (z.sq == 3) {
        // 밖에서 온 세기 0(소속 · 대범위 단추 · 내림줄): 이름 줄 전체를 막는다(지금 연표 `blocks`의 마지막 갈래와 같은 식).
        if (z.l < t.r + margin && t.l - margin < z.r) return true;
        continue;
      }
      if (z.sq == 1) {
        if (z.l < t.gr && t.gl < z.r) return true;
        continue;
      }
      if (z.sq == 2) {
        if (z.l < t.sr + (t.flip ? 0 : margin) && t.sl - (t.flip ? margin : 0) < z.r) return true;
        continue;
      }
      bool hit(double a, double b, double sa, double sb) =>
          tight > 0 ? sa < t.sr + tight + margin && t.sl - tight - margin < sb : a < t.r + margin && t.l - margin < b;
      if (!hit(z.l, z.r, z.sl, z.sr)) continue;
      if (shed == null || z.pillWidth <= 0) return true;
      final d = z.pillWidth;
      if (z.pillFlip ? hit(z.l + d, z.r, z.sl + d, z.sr) : hit(z.l, z.r - d, z.sl, z.sr - d)) return true;
      shed.add(z);
    }
    return false;
  }

  void shedPill(_Zone z) {
    final d = z.pillWidth;
    if (z.pillFlip) {
      z.l += d;
      z.sl += d;
    } else {
      z.r -= d;
      z.sr -= d;
    }
    if (z.owner >= 0) {
      items[z.owner].flags &= ~LabelFlag.count;
      items[z.owner].extra = 0;
    }
    z.pillWidth = 0;
  }

  final late = <bool Function()>[];
  for (int k = 0; k < count; k++) {
    final i = order[k], it = items[k], x = xs[k];
    final child = EventLook.child(look[i]);
    final need = child ? (minImp < 2 ? minImp : 2) : minImp;
    // 공동 사건의 다른 자리에는 이름을 붙이지 않는다(명세 6.2 · 계약 6-6 비트 18).
    final may = !EventLook.pair(look[i]) && input.importance[i] >= need && minImp < 99;
    if (may) {
      final nameW = input.nameWidth[i];
      if (nameW.isNaN) {
        deferred++;
      } else {
        final yearW = input.yearWidth[i];
        final kids = input.kids[i];
        final countW = kids > 0 ? input.countWidth[i] : 0.0;
        final lo = input.bandLo[i] * scale - 3, hi = input.bandHi[i] * scale + 3;
        final before = namedBefore[input.eventId[i]];
        final margin = before == null && input.eventId[i] != input.selectedEventId ? LabelGeo.newMargin : 0.0;
        final first = child && lines > 1 ? 1 : 0;
        final lane = dotLine[k];
        var ks = lane >= 0 ? <int>[lane] : [for (int q = 0; q < lines; q++) (first + q) % lines];
        if (before != null && lane < 0) {
          final want = before >> 2;
          if (want < lines) ks = [want, ...ks.where((q) => q != want)];
        }
        final flipFirst = before != null && (before & 3) == LabelSide.left;
        final dotW = EventLook.dotWidth(look[i]);

        bool place(double yr, double mm, {double tight = 0, bool withCount = true, bool shedNeighbour = false}) {
          final cw = withCount && kids > 0 ? countW + LabelGeo.countPad : 0.0;
          final w = nameW + (yr > 0 ? yr + LabelGeo.gap : 0) + cw + (child ? LabelGeo.childBase : LabelGeo.base);
          final ink = nameW + cw + (yr > 0 ? yr + LabelGeo.gap : 0);
          var tries = <_Try>[
            _Try(false, x - 7, x + w, x + 6, x + w, x + dotW + 2, x + dotW + 3 + ink, x - 7, x + dotW + 3 + ink),
            _Try(true, x - w, x + 9, x - w, x - 6, x - dotW - 5 - ink, x - dotW - 4, x - dotW - 5 - ink, x + 9),
          ];
          if (flipFirst) tries = tries.reversed.toList();
          for (final t in tries) {
            if (t.l - mm < lo || t.r + mm > hi) continue;
            for (final line in ks) {
              final shed = shedNeighbour ? <_Zone>[] : null;
              if (blocks(subs[line], t, mm, tight, shed)) continue;
              if (tight > 0 ? coversDot(line, t.gl - 2, t.gr + 2, k) : coversDot(line, t.tl, t.tr, k)) continue;
              if (shed != null) {
                for (final z in shed) {
                  shedPill(z);
                }
              }
              subs[line].add(_Zone(t.l, t.r, 0, t.sl, t.sr, pillFlip: t.flip, pillWidth: cw, owner: k));
              it
                ..side = t.flip ? LabelSide.left : LabelSide.right
                ..line = line
                ..flags = (yr > 0 ? LabelFlag.year : 0) | (cw > 0 ? LabelFlag.count : 0) | (yearW > 0 && yr <= 0 ? LabelFlag.shedYear : 0)
                ..extra = cw > 0 ? kids : 0;
              dotLine[k] = line;
              return true;
            }
          }
          return false;
        }

        final firstMargin = yearW > 0 && shedYearBefore.contains(input.eventId[i]) ? (margin > 4 ? margin : 4.0) : margin;
        if (!place(yearW, firstMargin)) {
          late.add(() =>
              (yearW > 0 && place(0, margin)) ||
              place(yearW, margin, tight: LabelGeo.tight) ||
              (yearW > 0 && place(0, margin, tight: LabelGeo.tight)) ||
              (kids > 0 && place(0, margin, tight: LabelGeo.tight, withCount: false)) ||
              place(0, margin, tight: LabelGeo.tight, withCount: false, shedNeighbour: true));
        }
      }
    }
    if (it.side == LabelSide.none) {
      // 이름 없는 점: 제 분류의 글줄, 아니면 그 자리에 글자가 없는 첫 글줄.
      var line = dotLine[k];
      if (line < 0) {
        line = -1;
        for (int q = 0; q < lines && line < 0; q++) {
          if (!_overlaps(subs[q], x - LabelGeo.dotReach, x + LabelGeo.dotReach)) line = q;
        }
        if (line < 0) line = 0;
      }
      it.line = line;
      dotLine[k] = line;
    }
  }
  for (final f in late) {
    f();
  }

  // 좁은 띠: 점이 띠 안쪽에 다 들지 않으면 작은 점, 그것도 안 들면 그리지 않는다.
  for (int k = 0; k < count; k++) {
    final it = items[k], i = order[k];
    if (it.side != LabelSide.none) continue;
    final lo = input.bandLo[i], hi = input.bandHi[i];
    if (!lo.isFinite || !hi.isFinite) continue;
    // 조감은 띠 안쪽 여백이 1 + 관문 3 + 0.5 = 4.5px이고, 들지 않으면 작은 점으로 줄이지 않고 곧바로 숨긴다(명세 4.4).
    final room = (hi - lo) * scale - 2 * (input.bird ? LabelGeo.birdEdge : LabelGeo.bandEdge);
    if (room >= 2 * EventLook.dotRadius(look[i], false)) continue;
    if (!input.bird && room >= 2 * EventLook.dotRadius(look[i], true)) {
      it.small = true;
    } else {
      it.hidden = it.off = true;
    }
  }

  // 동전 겹침: 이름 붙은 점 11px(묶여 있었으면 14px) 안의 이름 없는 점은 그 점에 포갠다.
  bool together(int a, int b) {
    final ga = tiedWith[input.eventId[order[a]]], gb = tiedWith[input.eventId[order[b]]];
    return ga != null && ga == gb;
  }

  bool sameBand(int a, int b) => input.band[order[a]] == input.band[order[b]] && input.bandLo[order[a]] == input.bandLo[order[b]];

  final coins = <int, List<int>>{};
  for (int k = 0; k < count; k++) {
    final it = items[k];
    if (it.side != LabelSide.none || it.off || it.hidden) continue;
    for (int h = 0; h < count; h++) {
      final host = items[h];
      if (host.side == LabelSide.none || host.line != it.line || !sameBand(h, k)) continue;
      if ((host.x - it.x).abs() >= (together(h, k) ? LabelGeo.untie : LabelGeo.tie)) continue;
      host.more = true;
      host.coins++;
      it.hidden = true;
      (coins[h] ??= [h]).add(k);
      break;
    }
  }
  for (final group in coins.values) {
    tied.add(Int32List.fromList([for (final k in group) input.eventId[order[k]]]));
  }

  // 개수 알약: 남은 점을 글줄마다 모아 가로 순으로 이어 묶는다.
  final byLine = <int, List<int>>{};
  for (int k = 0; k < count; k++) {
    if (items[k].side != LabelSide.none || items[k].hidden || items[k].off) continue;
    (byLine[items[k].line] ??= []).add(k);
  }
  (double, double) extentOf(List<int> run) {
    if (run.length == 1) return (xs[run.first] - 5, xs[run.first] + 5);
    final l = xs[run.first], r = xs[run.last];
    final w = (r - l + 12) > LabelGeo.pillWidth(run.length) ? r - l + 12 : LabelGeo.pillWidth(run.length);
    return ((l + r) / 2 - w / 2, (l + r) / 2 + w / 2);
  }

  /// 가로 순으로 놓인 점들을 지금 연표의 묶음 규칙으로 이어 묶는다(같은 띠 · 이웃 거리 11/14px · 알약이 차지할 폭까지 — js `_placeRow`의 cluster 절).
  /// 한 글줄 안의 점들에도, 통에서 나온 나머지를 나눌 때에도 같은 규칙을 쓴다.
  List<List<int>> runsOf(List<int> list) {
    final runs = <List<int>>[];
    var run = <int>[list.first];
    for (int q = 1; q < list.length; q++) {
      final k = list[q], last = run.last;
      final tg = together(k, last);
      if (sameBand(k, last) && (xs[k] - xs[last] < (tg ? LabelGeo.untie : LabelGeo.tie) || xs[k] - 5 < extentOf(run).$2 + (tg ? 5 : 2))) {
        run.add(k);
      } else {
        runs.add(run);
        run = [k];
      }
    }
    runs.add(run);
    for (int q = 1; q < runs.length; q++) {
      final a = runs[q - 1];
      if (sameBand(runs[q].first, a.last) && extentOf(runs[q]).$1 < extentOf(a).$2 + (together(runs[q].first, a.last) ? 5 : 2)) {
        runs[q - 1] = [...a, ...runs[q]];
        runs.removeAt(q--);
      }
    }
    return runs;
  }

  final rowClusters = <_Cluster>[];

  /// 묶음마다 [tied]의 몇 번째 줄인가 — 뒤에 점을 더 묶을 때 그 이력에 함께 적는다.
  final tiedAt = <_Cluster, int>{};
  for (final line in byLine.keys) {
    final list = byLine[line]!..sort((a, b) => xs[a].compareTo(xs[b]));
    for (final r in runsOf(list)) {
      if (r.length < 2) continue;
      final cluster = _makeCluster(input, row, line, r, items, order, xs, subs[line], scale);
      if (cluster == null) {
        for (final k in r) {
          items[k]
            ..hidden = true
            ..off = true;
        }
        continue;
      }
      for (final k in r) {
        items[k].hidden = true;
      }
      rowClusters.add(cluster);
      subs[line].add(_Zone(cluster.x - cluster.width / 2, cluster.x + cluster.width / 2, 0, cluster.x - cluster.width / 2, cluster.x + cluster.width / 2));
      tiedAt[cluster] = tied.length;
      tied.add(Int32List.fromList([for (final k in r) input.eventId[order[k]]]));
    }
  }

  // 통의 나머지 개수: 그 통의 으뜸 대표가 든 묶음에 통째로 붙이고, 대표가 없으면 제 알약으로 선다(명세 8.2).
  for (int p = 0; p < input.pillRest.length; p++) {
    if (input.pillRow[p] != row || input.pillRest[p] <= 0) continue;
    int best = -1;
    // 접힌 부모의 자식은 지금 연표에서 아예 보이지 않는다(js:3429). 통의 개수는 그 자식들까지 세어 오므로
    // 그 통에 든 대표의 '접힌 하위 수'만큼 빼 준다 — 그 수는 이미 부모 이름 뒤의 작은 알약이 말한다.
    var rest = input.pillRest[p];
    for (int k = 0; k < count; k++) {
      final i = order[k];
      if (at[i] < input.pillLo[p] || at[i] >= input.pillHi[p]) continue;
      rest -= input.kids[i];
      if (best < 0 || prio(order[k]) > prio(order[best]) || (prio(order[k]) == prio(order[best]) && at[i] < at[order[best]])) best = k;
    }
    if (rest <= 0) continue;
    _Cluster? host;
    if (best >= 0) {
      for (final c in rowClusters) {
        if (c.members.contains(items[best])) {
          host = c;
          break;
        }
      }
    }
    if (host != null) {
      host.count += rest;
      continue;
    }
    /// 알약이 [line] 글줄의 [c] 자리에 들어가는가(놓인 글자와 그 글줄의 점을 모두 비켜서). [skip]은 제 자리를 내줄 점들.
    bool roomAt(int line, double c, double w, {Set<int> skip = const {}}) {
      if (c.isNaN || _overlaps(subs[line], c - w / 2, c + w / 2)) return false;
      for (int k = 0; k < count; k++) {
        if (skip.contains(k) || items[k].hidden || items[k].off || items[k].line != line) continue;
        if ((xs[k] - c).abs() < w / 2 + EventLook.dotRadius(look[order[k]], items[k].small)) return false;
      }
      return true;
    }

    // 으뜸 대표가 이름을 얻었으면 그 점 뒤에 포갠다(동전 겹침) — 지금 연표에 없는 알약을 빈 글줄에 세우지 않는다.
    // 나머지는 눌렀을 때 그 통의 목록으로 열리므로 개수를 잃지도 않는다.
    if (best >= 0 && items[best].side != LabelSide.none && !items[best].hidden && !items[best].off) {
      items[best].more = true;
      items[best].coins += rest;
      continue;
    }
    // 나머지가 남은 통은 대표 넷보다 촘촘한 통이다 — 그 통에 이름 없이 홀로 남은 대표들을 나머지와 함께 묶는다.
    // 묶는 규칙은 지금 연표 그대로([runsOf] — 같은 띠 · 같은 글줄 · 이웃 거리)이고, **묶음마다 한 알약**이다:
    // 지금 연표는 사건을 다 들고 있어 분류별 글줄마다 · 떨어진 자리마다 알약이 서는데(기준 `전체` 장면에서 같은 자리에
    // 글줄만 다른 알약이 여럿), 통에서 온 나머지를 묶음 하나에만 얹으면 다른 묶음의 대표가 홀로 선 점으로 남는다.
    // 나머지는 묶음에 든 대표 수에 맞춰 나눈다(남는 몫은 큰 묶음부터 — 합은 통의 수 그대로).
    final loose = <int>[];
    for (int k = 0; k < count; k++) {
      final i = order[k];
      if (at[i] < input.pillLo[p] || at[i] >= input.pillHi[p]) continue;
      if (items[k].side != LabelSide.none || items[k].hidden || items[k].off) continue;
      loose.add(k);
    }
    if (loose.isNotEmpty) {
      loose.sort((a, b) => xs[a].compareTo(xs[b]));
      final byLine = <int, List<int>>{};
      for (final k in loose) {
        (byLine[items[k].line] ??= []).add(k);
      }
      // 글줄마다 묶음 규칙으로 다시 나눈 뒤, 대표가 많은 묶음부터 — 나머지의 남는 몫도 그 차례로 간다.
      final groups = <(int, List<int>)>[];
      for (final line in byLine.keys) {
        // 묶음 규칙으로 나뉘어도 몫을 받아 알약이 될 만한 묶음만 따로 세운다 — 통 하나는 화면에서 20px 안팎이라
        // 갈라 놓고 몫을 못 받으면 홀로 선 점만 늘어난다(기준보다 점이 많아진다).
        final runs = runsOf(byLine[line]!);
        if (runs.length > 1 && rest < runs.length * 2) {
          groups.add((line, byLine[line]!));
          continue;
        }
        for (final r in runs) {
          groups.add((line, r));
        }
      }
      groups.sort((a, b) => b.$2.length != a.$2.length ? b.$2.length.compareTo(a.$2.length) : xs[a.$2.first].compareTo(xs[b.$2.first]));
      final shares = _shareOut(rest, [for (final g in groups) g.$2.length]);
      // 몫을 못 받아 홀로 남을 묶음이 있으면 가장 많이 받은 묶음에서 하나씩 옮긴다(합은 그대로) —
      // 기준 그림에서는 같은 자리에 글줄만 다른 알약이 여럿 서고 홀로 선 점은 거의 없다.
      for (int q = 0; q < groups.length; q++) {
        if (groups[q].$2.length + shares[q] >= 2) continue;
        int big = -1;
        for (int r = 0; r < groups.length; r++) {
          if (r == q || shares[r] <= 0 || groups[r].$2.length + shares[r] - 1 < 2) continue;
          if (big < 0 || shares[r] > shares[big]) big = r;
        }
        if (big < 0) break;
        shares[big]--;
        shares[q]++;
      }
      final whole = groups.length == 1 ? _pillCats(input, p) : null;
      var left = rest;
      for (int q = 0; q < groups.length; q++) {
        final (line, run) = groups[q];
        final give = shares[q];
        // 알약은 둘부터다 — 몫을 못 받은 홀로 선 대표는 그대로 점으로 둔다(지금 연표도 이름 없는 점 하나는 점이다).
        if (run.length + give < 2) continue;
        final folded = _makeCluster(input, row, line, run, items, order, xs, subs[line], scale, count: run.length + give, cats: whole);
        if (folded == null || !roomAt(line, folded.x, folded.width, skip: run.toSet())) continue;
        for (final k in run) {
          items[k].hidden = true;
        }
        rowClusters.add(folded);
        subs[line].add(_Zone(folded.x - folded.width / 2, folded.x + folded.width / 2, 0, folded.x - folded.width / 2, folded.x + folded.width / 2));
        tiedAt[folded] = tied.length;
        tied.add(Int32List.fromList([for (final k in run) input.eventId[order[k]]]));
        left -= give;
      }
      // 모두 나눴으면 이 통은 끝. 남은 몫이 있으면 아래에서 제 알약 하나로 세운다.
      if (left <= 0) continue;
      rest = left;
    }
    // 대표가 없는 통: 통 가운데에 알약 하나.
    final centre = (input.pillLo[p] + input.pillHi[p]) / 2 * scale;
    final bandLo = best >= 0 ? input.bandLo[order[best]] : double.negativeInfinity;
    final bandHi = best >= 0 ? input.bandHi[order[best]] : double.infinity;
    var width = input.bird ? LabelGeo.smallPillWidth(rest) : LabelGeo.pillWidth(rest);
    var flags = ClusterFlag.partial | (input.bird ? ClusterFlag.small : 0);
    var inset = input.bird ? LabelGeo.birdPillInset : LabelGeo.pillInset;
    if (!input.bird && bandLo.isFinite && bandHi.isFinite) {
      final room = (bandHi - bandLo) * scale;
      if (room - 2 * inset < width && room - 4 >= LabelGeo.smallPillWidth(rest)) {
        width = LabelGeo.smallPillWidth(rest);
        inset = LabelGeo.smallPillInset;
        flags |= ClusterFlag.small;
      }
    }
    double clamp(double v) {
      if (!bandLo.isFinite || !bandHi.isFinite) return v;
      final lo = bandLo * scale + inset + width / 2, hi = bandHi * scale - inset - width / 2;
      return hi < lo ? double.nan : (v < lo ? lo : (v > hi ? hi : v));
    }

    var x = clamp(centre);
    if (x.isNaN) continue;
    // 글자 · 점에 걸리면 통 안에서 비킨다 — 묶음 알약과 같은 규칙. 통을 훑어도 빈 곳이 없으면 그 줄의 가장 가까운 묶음에 개수를 넘긴다.
    final low = input.pillLo[p] * scale + width / 2, high = input.pillHi[p] * scale - width / 2;
    bool free(int line, double c) => roomAt(line, c, width);

    int line = -1;
    for (int q = 0; q < lines && line < 0; q++) {
      for (int step = 0; step <= 16; step++) {
        final c = clamp(step == 0 ? x : low + (high - low) * (step - 1) / 15);
        if (!free(q, c)) continue;
        x = c;
        line = q;
        break;
      }
    }
    if (line < 0) {
      // 줄이 꽉 찼다: 가장 가까운 묶음에 개수를 넘기고, 묶음도 없으면 가장 가까운 점 뒤에 포갠다(개수를 잃지 않는다).
      _Cluster? nearest;
      for (final c in rowClusters) {
        if (nearest == null || (c.x - centre).abs() < (nearest.x - centre).abs()) nearest = c;
      }
      if (nearest != null) {
        nearest.count += rest;
        continue;
      }
      // 으뜸 대표가 보이면 그 뒤에, 아니면 가장 가까운 점 뒤에.
      int host = best >= 0 && !items[best].hidden && !items[best].off ? best : -1;
      if (host < 0) {
        for (int k = 0; k < count; k++) {
          if (items[k].hidden || items[k].off) continue;
          if (host < 0 || (xs[k] - centre).abs() < (xs[host] - centre).abs()) host = k;
        }
      }
      if (host < 0) {
        line = 0;
      } else {
        items[host].more = true;
        items[host].coins += rest;
        continue;
      }
    }
    subs[line].add(_Zone(x - width / 2, x + width / 2, 0, x - width / 2, x + width / 2));
    // 색줄: 자료 처리부가 통의 분류 비율을 실어 주면 그것으로(대표가 없는 통은 셈할 대표가 없다).
    rowClusters.add(_Cluster(row, line, <_Placed>[], best >= 0 ? order[best] : -1, input.pillLo[p] * scale, input.pillHi[p] * scale, x, width, flags, bandLo, bandHi, rest,
        _pillCats(input, p) ?? <int, int>{}));
  }

  // 이웃 통의 알약과 홀로 선 점을 다시 묶는다. 통마다 대표가 넷뿐이라, 이웃 통에서 선 알약과 그 곁에 남은 점이
  // 지금 연표에서는 한 알약인데 따로 서는 일이 있다. 거리 규칙은 [runsOf] 그대로(알약 상자에서 7px 안 · 묶인 자리에서 11px 안).
  for (int k = 0; k < count; k++) {
    final it = items[k], i = order[k];
    if (it.side != LabelSide.none || it.hidden || it.off) continue;
    _Cluster? host;
    var near = double.infinity;
    for (final c in rowClusters) {
      if (c.line != it.line) continue;
      // 같은 띠인가 — 대표가 없는 통의 알약은 띠를 모르니 그 자리가 점의 띠 안에 드는지로 본다.
      if (c.lead >= 0) {
        if (input.band[c.lead] != input.band[i] || input.bandLo[c.lead] != input.bandLo[i]) continue;
      } else if (c.x < input.bandLo[i] * scale || c.x > input.bandHi[i] * scale) {
        continue;
      }
      final box = c.x - c.width / 2 - it.x > it.x - c.x - c.width / 2 ? c.x - c.width / 2 - it.x : it.x - c.x - c.width / 2;
      final span = c.lo - it.x > it.x - c.hi ? c.lo - it.x : it.x - c.hi;
      if (box >= 7 && span >= LabelGeo.tie) continue;
      final d = (c.x - it.x).abs();
      if (d >= near) continue;
      host = c;
      near = d;
    }
    if (host == null) continue;
    host.count++;
    host.members.add(it);
    it.hidden = true;
    final line = tiedAt[host];
    if (line != null) tied[line] = Int32List.fromList([...tied[line], input.eventId[i]]);
  }

  clusters.addAll(rowClusters);
  out.addAll(items);
  return deferred;
}

/// 나머지 [total]을 몫 [weights]에 맞춰 나눈다(가장 큰 나머지 차례로 — 합은 늘 [total]). 무게가 모두 0이면 앞에서부터 하나씩.
List<int> _shareOut(int total, List<int> weights) {
  final out = List<int>.filled(weights.length, 0);
  if (weights.isEmpty || total <= 0) return out;
  var sum = 0;
  for (final w in weights) {
    sum += w;
  }
  if (sum <= 0) {
    for (int i = 0; i < weights.length && i < total; i++) {
      out[i] = 1;
    }
    out[0] += total - (total < weights.length ? total : weights.length);
    return out;
  }
  var given = 0;
  final rest = <(double, int)>[];
  for (int i = 0; i < weights.length; i++) {
    final exact = total * weights[i] / sum;
    out[i] = exact.floor();
    given += out[i];
    rest.add((exact - out[i], i));
  }
  rest.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
  for (int q = 0; given < total; q++, given++) {
    out[rest[q % rest.length].$2]++;
  }
  return out;
}

/// 통 [p]의 분류 비율(자료 처리부가 알약 구역에 실어 준 것). 열이 없으면 null.
Map<int, int>? _pillCats(LabelInput input, int p) {
  final at = input.pillCatAt, cat = input.pillCat, counts = input.pillCatCount;
  if (at == null || cat == null || counts == null || p + 1 >= at.length) return null;
  final from = at[p], to = at[p + 1];
  if (to <= from) return null;
  final out = <int, int>{};
  for (int k = from; k < to; k++) {
    out[cat[k]] = (out[cat[k]] ?? 0) + counts[k];
  }
  return out;
}

/// 묶음 하나의 알약 자리를 잡는다. [count]를 주면 숫자는 그 값이다(통의 나머지를 함께 담을 때).
/// [cats]를 주면 색줄의 분류 비율을 그것으로 한다(통이 실어 준 비율 — 없으면 묶인 대표의 분류로 센다).
_Cluster? _makeCluster(LabelInput input, int row, int line, List<int> run, List<_Placed> items, List<int> order, Float64List xs, List<_Zone> taken, double scale, {int? count, Map<int, int>? cats}) {
  final total = count ?? run.length;
  final lead = run.reduce((best, k) {
    final a = order[k], b = order[best];
    final pa = input.importance[a] + (input.eventId[a] == input.selectedEventId ? 100 : 0);
    final pb = input.importance[b] + (input.eventId[b] == input.selectedEventId ? 100 : 0);
    if (pa != pb) return pa > pb ? k : best;
    return input.at[a] < input.at[b] ? k : best;
  });
  final l = xs[run.first], r = xs[run.last];
  // 조감의 알약은 처음부터 작은 알약이고 띠 안쪽 여백이 5px이다(명세 4.3 · 05 7.5).
  var small = input.bird;
  var width = small ? LabelGeo.smallPillWidth(total) : LabelGeo.pillWidth(total);
  var x = (l + r) / 2;
  for (final c in [x, l + width / 2 - 5, r - width / 2 + 5]) {
    if (_overlaps(taken, c - width / 2, c + width / 2)) continue;
    x = c;
    break;
  }
  final bandLo = input.bandLo[order[lead]] * scale, bandHi = input.bandHi[order[lead]] * scale;
  var inset = small ? LabelGeo.birdPillInset : LabelGeo.pillInset;
  if (bandLo.isFinite && bandHi.isFinite) {
    if (!input.bird && bandHi - bandLo - 2 * inset < width && bandHi - bandLo - 4 >= LabelGeo.smallPillWidth(total)) {
      width = LabelGeo.smallPillWidth(total);
      inset = LabelGeo.smallPillInset;
      small = true;
    }
    final lo = bandLo + inset + width / 2, hi = bandHi - inset - width / 2;
    if (hi < lo) return null;
    x = x < lo ? lo : (x > hi ? hi : x);
  }
  // 글자를 비켜 가운데에서 옮긴 알약이 이웃 점 · 글자에 닿으면 다른 비킴 자리, 없으면 가운데로 되돌린다.
  final mid = (l + r) / 2;
  if ((x - mid).abs() > .5) {
    final ring = small ? 1.0 : 3.0;
    double fit(double c) => bandLo.isFinite && bandHi.isFinite ? c.clamp(bandLo + inset + width / 2, bandHi - inset - width / 2) : c;
    bool near(double c) {
      final half = width / 2 + ring;
      if (_overlaps(taken, c - half, c + half)) return true;
      for (int k = 0; k < items.length; k++) {
        if (run.contains(k) || items[k].hidden || items[k].off || items[k].line != line) continue;
        if ((xs[k] - c).abs() < half + EventLook.dotRadius(input.look[order[k]], items[k].small) - .25) return true;
      }
      return false;
    }

    if (near(x)) {
      double? alt;
      for (final c in [fit(l + width / 2 - 5), fit(r - width / 2 + 5)]) {
        if ((c - x).abs() > .5 && !near(c)) {
          alt = c;
          break;
        }
      }
      x = alt ?? fit(mid);
    }
  }
  final categories = <int, int>{};
  if (cats != null) {
    categories.addAll(cats);
  } else {
    for (final k in run) {
      final cat = EventLook.category(input.look[order[k]]);
      categories[cat] = (categories[cat] ?? 0) + 1;
    }
  }
  return _Cluster(row, line, [for (final k in run) items[k]], order[lead], l, r, x, width, small ? ClusterFlag.small : 0,
      input.bandLo[order[lead]], input.bandHi[order[lead]], total, categories);
}

bool _overlaps(List<_Zone> zones, double a, double b) {
  for (final z in zones) {
    if (a < z.r && z.l < b) return true;
  }
  return false;
}

int _linesOf(LabelInput input, int row) {
  final i = row - input.rowBase;
  return i >= 0 && i < input.rowLines.length && input.rowLines[i] > 0 ? input.rowLines[i] : 1;
}
