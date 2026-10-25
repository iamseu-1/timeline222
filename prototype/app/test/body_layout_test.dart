import 'dart:math' as math;

import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagLook;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 띠마다 제 몸통 높이(칸 그림 갈래 걸음 5 · 과제 8 걸음 3 — docs/계획-리메이크-4단계.md · 계약 1-1 덧붙임 '줄어드는 층'):
// 줄 fig_wide 28 ~ 30(줄어드는 층 수)이 선 줄은 칸 층 자리를 그대로 두고 칸 뭉치 아랫변(= 흰 사건 칸 윗변)과 그 밑을 그 수 × 14 올린다
// (layout.dart `_bandOf` — RowGeo.shrunk · stackEnd). 띠의 제 몸통 끝은 쌓은 끝을 맞붙여 셈하므로(bands.dart TagLook.floorEndOf) 가장 긴 띠가
// 줄의 칸 뭉치 아랫변에 닿는다. 저장된 값은 '모두 켠 보기'의 셈이고 왕조 · 지위는 그 셈에 없다(배치 판 8 검토 고침 — 새 앱의 기본은 꼬리표 밑 흰 사슬).
// 그래서 보기가 그 줄에 자료로 있는 **셈에 든 층**(왕조 · 지위 밖)을 하나라도 빼거나 지도자 단을 줄이면 0, 왕조 · 지위는 사슬 켬 · 끔 · 표시 체크와 상관없이
// 저장된 값 그대로 읽고(사슬이 선 줄은 칸 층이 사슬 단 위에 머물게 묶음), 렌즈 켬 · 줄 값 없는 줄 · 변형 줄 · 스위치 body 끔은 0이다.
// 검토 고침: 두 장 꼬리표 줄의 기관 층은 줄 값(비트 6 — 계약 1-1 덧붙임 '쌓기') · 줄 값 없는 줄과 스위치 body 끔은 트랙 값(예전).
// 합칠 때 고침(remake-4-final): 칸 그림 갈래 바탕(9321957)의 옛 셈(U에 왕조 · 지위를 넣고 앱이 사슬로 옮긴 만큼 덜 읽음)을 새 계약대로 — [Floors]의 셈 ·
// 무작위 줄의 기대 · '보기가 빼면 0'의 왕조 · 지위 줄 · 사슬 시험을 다시 썼다.

/// 칸 층 비트(look 21 + k): 0 왕조 · 1 시기 · 2 지위 · 3 집권 · 4 실권 · 5 지도자 · 6 내각 · 7 예속 · 8 기관 · 9 직위 줄 더(look 30).
const kDyn = 0, kPhase = 1, kRank = 2, kPower = 3, kReal = 4, kLeader = 5, kCab = 6, kDep = 7, kOrgan = 8, kOffice = 9;
const hasCells = 1 << 20;
int bit(int k) => 1 << (21 + k);

/// 손으로 지은 띠 하나 — look(칸 층 비트)와 sub(지도자 단 수 − 1 · 직위 줄 더 수).
class Band {
  const Band(this.kinds, {this.lanes = 1, this.office = 1, this.cells = true});
  final Set<int> kinds;
  final int lanes, office;
  final bool cells;
  int get look => (cells ? hasCells : 0) | kinds.fold<int>(0, (a, k) => a | bit(k));
  int get sub => (kinds.contains(kLeader) ? (lanes - 1) << 22 : 0) | (kinds.contains(kOffice) ? office << 17 : 0);
}

/// 손으로 지은 줄의 층 자료(저장된 줄 값) — 띠들에서 지은다(내보내기처럼 줄 값 = 그 줄 띠들의 합).
class Floors {
  Floors.of(this.bands, {this.phase = 1, this.dep = 1}) {
    bool any(int k) => bands.any((b) => b.cells && b.kinds.contains(k));
    dyn = any(kDyn);
    rank = any(kRank);
    power = any(kPower);
    real = any(kReal);
    cab = any(kCab);
    organ = any(kOrgan);
    phases = any(kPhase) ? phase : 0;
    deps = any(kDep) ? dep : 0;
    lanes = bands.where((b) => b.cells && b.kinds.contains(kLeader)).fold(0, (a, b) => math.max(a, b.lanes));
    office = bands.where((b) => b.cells && b.kinds.contains(kOffice)).fold(0, (a, b) => math.max(a, b.office));
  }
  final List<Band> bands;
  final int phase, dep;
  late final bool dyn, rank, power, real, cab, organ;
  late final int phases, deps, lanes, office;

  /// 그 줄의 층 하나하나(띠 비트 → 줄의 층 수) — 내보내기 tracks.mjs `contributeLate`의 floors와 같은 차례.
  /// 왕조 · 지위는 세지 않는다(계약 1-1 덧붙임 '줄어드는 층의 셈' — 새 앱의 기본은 꼬리표 밑 흰 사슬): 왕조 · 지위만 가진 띠는 제 층 합 0(사슬만).
  List<(int, int)> get counts => [(kPhase, phases), (kPower, power ? 1 : 0), (kReal, real ? 1 : 0),
    (kLeader, lanes), (kCab, cab ? 1 : 0), (kOffice, office), (kDep, deps), (kOrgan, organ ? 1 : 0)];

  /// 줄의 층 합 U(왕조 · 지위 밖).
  int get u => counts.fold<int>(0, (a, c) => a + c.$2);

  /// 띠들 제 층 합의 큰 값 — 칸은 있고 층 비트 21 ~ 29가 없는 띠는 U(내보내기 tracks.mjs와 같은 셈 — 왕조 · 지위 비트만 있는 띠는 0).
  int get top {
    var top = 0;
    for (final b in bands) {
      if (!b.cells) continue;
      if ((b.look >> 21) & 0x1ff == 0) return u;
      var own = 0;
      for (final (k, n) in counts) {
        if (n == 0 || !b.kinds.contains(k)) continue;
        own += k == kLeader ? b.lanes : (k == kOffice ? b.office : n);
      }
      top = math.max(top, own);
    }
    return top;
  }

  /// 줄어드는 층 = min(7, U − 띠들 제 층 합의 큰 값) · U가 0이면 0.
  int get shrink => u == 0 ? 0 : math.min(7, u - top);

  /// 7을 넘어 덜 준 줄인가.
  bool get capped => u - top > 7;

  /// 칸은 있는데 층 비트 21 ~ 29가 없는 띠(직위 줄 더만 가진 띠 포함)가 있어 내보내기가 U로 센 줄인가 — 줄지 않는다(앱은 걸음 4부터 그 띠를
  /// 제 직위 줄 더 층만큼 맞붙이므로 가장 긴 띠가 칸 뭉치 끝에 닿지 않을 수 있다 — 덜 줄어 안전).
  bool get whole => bands.any((b) => b.cells && (b.look >> 21) & 0x1ff == 0);
}

/// 엔진 답 꼴의 줄 하나(`rail` 칸이 있으면 나머지 칸도 읽는다 — chain_layout_test와 같은 꼴). [shrink]는 저장된 줄어드는 층(null이면 [f]로 셈).
Map<String, dynamic> row(int id, Floors f, {int? shrink, bool cellRows = true, int variant = 0, bool carried = true}) {
  final s = shrink ?? f.shrink;
  return {
    'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
    'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
    'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': f.phases, 'rank': f.rank ? 1 : 0, 'cats': <int>[],
    'fig': 0, 'dep': f.deps > 0 ? 13 * f.deps - 1 : 0, 'zones': 0, 'hem': 0, 'variant': variant,
    'fig_wide': (carried ? 1 << 3 : 0) | (f.lanes > 0 ? 1 << 17 | (f.lanes - 1) << 26 : 0) | f.office << 21 | s << 28,
    'rail': 0, 'cell_rows': cellRows ? 1 : 0, 'dynasty': f.dyn ? 1 : 0, 'leader': f.lanes > 0 ? 1 : 0, 'cabinet': f.cab ? 1 : 0,
    'organ': f.organ ? 1 : 0, 'power': f.power ? 1 : 0, 'real': f.real ? 1 : 0, 'hang': 0,
  };
}

/// 줄마다 트랙 하나(트랙 값 기관 층이 그 줄 값과 같게). [rows]는 트랙마다의 줄 목록.
Map<String, dynamic> layoutOf(List<List<Map<String, dynamic>>> rows, {List<dynamic> variants = const []}) => {
  'packs': [
    {'id': 1, 'name': '몸통 견본', 'events': 0},
  ],
  'tracks': [
    for (int i = 0; i < rows.length; i++)
      {
        'id': i + 1, 'pack': 1, 'ord': i, 'name': '갈래 $i', 'color': 0xa0bcc5, 'key': 'body-$i', 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
        'rows': rows[i],
      },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
  'variants': variants,
};

/// 스위치를 두고 짓는다(배치는 쌓을 때 스위치를 읽는다).
SceneLayout build(Map<String, dynamic> json, {bool body = true, bool chain = true, bool legit = true, bool office = true}) {
  PaintPick.body = body;
  PaintPick.chain = chain;
  PaintPick.legit = legit;
  PaintPick.office = office;
  return SceneLayout.fromJson(json)..reduceMotion = true;
}

/// 줄 생김새의 모든 값(legit_layout_test의 fields + 직위 줄 더 · 줄어든 층).
List<Object> fields(RowGeo g) => [
  g.height, g.bandTop, g.bandHeight, g.dynastyTop, g.leaderTop, g.cabinetTop, g.textTop, g.textLines, g.railTop, g.organTop, g.phaseTop, g.phaseLanes,
  g.rankTop, g.powerTop, g.realTop, g.railLevels, g.figTop, g.figLevels, g.depTop, g.depHeight, g.zoneTop, g.zoneLanes, g.hangLanes, g.hangOpen, g.hemTop,
  g.lineH, g.bodyTop, g.floorEnd, g.chainTop, g.chainLanes, g.leaderLanes, g.officeTop, g.officeLanes, g.shrunk, g.floorTops,
];

double bottomOf(RowGeo g) => g.bandTop + g.bandHeight;

void main() {
  tearDown(PaintPick.reset);

  // 줄 0: 시기 2 · 지도자 · 내각 · 기관(U 5) — 띠 가 [시기 지도자 내각] 4층 · 띠 나 [지도자 기관] 2층 → 1층 줄어듦. 줄 1: 지도자만(줄지 않음).
  // 줄 1은 제 트랙(기관 없음) — 같은 트랙이면 스위치 body 끔의 트랙 값 기관 층(예전)이 줄 1에도 서서 '줄지 않는 줄은 그대로'를 견줄 수 없다
  // (두 장 꼬리표 줄의 기관 층은 줄 값 — 아래 '두 장 꼬리표 줄의 기관 층' 시험).
  final bandA = Band({kPhase, kLeader, kCab}), bandB = Band({kLeader, kOrgan});
  final first = Floors.of([bandA, bandB], phase: 2);
  final plain = Floors.of([Band({kLeader})]);
  Map<String, dynamic> one() => layoutOf([
    [row(0, first)],
    [row(1, plain)],
  ]);

  test('줄어든 줄 — 칸 층 자리는 그대로 · 칸 뭉치 아랫변 · 사건 칸 · 띠 아랫변 · 줄 높이는 14 위 · 뒤 줄이 올라선다', () {
    expect(first.shrink, 1, reason: 'U 5 − 큰 띠 4');
    final on = build(one()), off = build(one(), body: false);
    final g = on.geo(0), o = off.geo(0);
    expect(on.spec(0)!.shrink, 1, reason: '줄 fig_wide 28 ~ 30');
    expect([g.shrunk, o.shrunk], [1, 0]);
    expect(g.floorTops, o.floorTops, reason: '칸 층 자리(띠마다 맞붙이는 바탕)는 그대로');
    expect([g.phaseTop, g.leaderTop, g.cabinetTop, g.organTop], [o.phaseTop, o.leaderTop, o.cabinetTop, o.organTop]);
    expect(g.stackEnd, o.floorEnd, reason: '칸 층을 모두 쌓은 끝');
    expect(g.floorEnd, o.floorEnd - G.floor);
    expect(g.textTop, g.floorEnd, reason: '흰 사건 칸은 줄인 칸 뭉치 바로 밑');
    expect(g.bandHeight, o.bandHeight - G.floor);
    expect(g.height, o.height - G.floor);
    expect(on.rowTop(1), off.rowTop(1) - G.floor, reason: '뒤 줄은 줄어든 만큼 올라선다');
    expect(fields(on.geo(1)), fields(off.geo(1)), reason: '줄지 않는 줄은 그대로');
    expect(on.totalHeight, off.totalHeight - G.floor);
    // 흐르는 동안의 생김새(withHeight)도 줄어든 층을 지닌다.
    final flowing = g.withHeight(10);
    expect([flowing.shrunk, flowing.stackEnd, flowing.floorEnd], [1, g.stackEnd, g.floorEnd]);
  });

  test('가장 긴 띠의 몸통이 줄의 칸 뭉치 끝 · 짧은 띠는 그 위(사건 칸 올림 ≥ 0) · 몸통 아랫변 · 칸 자리', () {
    final g = build(one()).geo(0);
    expect(TagLook.floorEndOf(g, bandA.look, sub: bandA.sub), g.floorEnd, reason: '띠 가(4층)가 가장 길다');
    expect(TagLook.floorEndOf(g, bandB.look, sub: bandB.sub), g.bodyTop + 2 * G.floor, reason: '띠 나(2층) — 시기 둘 · 내각을 빼고 맞붙임');
    expect(TagLook.eventLift(g, bandA.look, oldStore: false, loose: false, sub: bandA.sub), 0.0);
    expect(TagLook.eventLift(g, bandB.look, oldStore: false, loose: false, sub: bandB.sub), 2 * G.floor);
    expect(TagLook.bodyBottom(g, bandA.look, oldStore: false, sub: bandA.sub), bottomOf(g));
    expect(TagLook.bodyBottom(g, bandB.look, oldStore: false, sub: bandB.sub), bottomOf(g) - 2 * G.floor);
    // 칸 자리(맞붙이기)는 줄지 않은 줄과 같다 — 띠 나의 지도자는 몸통 첫 층 · 기관 층은 그 바로 밑.
    expect(TagLook.compactOf(g, bandB.look, g.leaderTop, sub: bandB.sub), g.bodyTop);
    expect(TagLook.compactOf(g, bandB.look, g.organTop, sub: bandB.sub), g.bodyTop + G.floor);
    expect(TagLook.compactOf(g, bandA.look, g.cabinetTop, sub: bandA.sub), g.cabinetTop);
    // 칸이 없는 띠는 몸통 윗변 · 넉넉하게 · 옛 저장소는 올림 0(예전 셈).
    expect(TagLook.floorEndOf(g, 0, sub: 0), g.bodyTop);
    expect(TagLook.eventLift(g, bandB.look, oldStore: false, loose: true, sub: bandB.sub), 0.0);
    expect(TagLook.eventLift(g, bandB.look, oldStore: true, loose: false, sub: bandB.sub), 0.0);
  });

  test('띠 비트가 여럿인 손으로 지은 줄 — 어느 보기에서도 넘침 없음 · 모두 켠 보기면 가장 긴 띠가 칸 뭉치 끝', () {
    final rnd = math.Random(20261025);
    final rowsOf = <Floors>[];
    for (int i = 0; i < 240; i++) {
      final bands = [
        for (int b = 0; b < 1 + rnd.nextInt(4); b++)
          Band({for (int k = 0; k < 10; k++) if (rnd.nextDouble() < .35) k}, lanes: 1 + rnd.nextInt(2), office: 1 + rnd.nextInt(2), cells: rnd.nextDouble() < .92),
      ];
      rowsOf.add(Floors.of(bands, phase: 1 + rnd.nextInt(2), dep: 1 + rnd.nextInt(2)));
    }
    final json = layoutOf([for (int i = 0; i < rowsOf.length; i++) [row(i, rowsOf[i])]]);
    expect(rowsOf.where((f) => f.shrink > 0).length, greaterThan(60), reason: '줄어드는 줄이 넉넉히 든다');
    var shrunkRows = 0, cappedByChain = 0;
    for (final chain in [false, true]) {
      for (final density in [0, -1, 1]) {
        final l = build(json, chain: chain);
        l.setConditions(l.conditions.copyWith(density: density));
        l.finishFlow();
        final dense = density > 0;
        for (int r = 0; r < rowsOf.length; r++) {
          final f = rowsOf[r], g = l.geo(r), when = '줄 $r · 사슬 $chain · 밀도 $density';
          // 보기가 뺀 셈에 든 층(빽빽하게 — 시기 · 집권 · 실권)이 있으면 0 · 지위(빽빽하게에서 숨음)와 왕조는 셈에 없어 보지 않는다
          // (사슬 켬 · 끔 모두 저장된 값 그대로 — 사슬이 선 줄은 사슬 단 위로 묶여 덜 줄 수 있음).
          final removed = dense && (f.phases > 0 || f.power || f.real);
          final want = removed ? 0 : f.shrink;
          if (g.chainLanes > 0) {
            expect(g.shrunk, lessThanOrEqualTo(want), reason: when);
            expect(g.stackEnd, lessThan(g.chainTop - .5), reason: '$when: 칸 층은 사슬 단 위');
            if (g.shrunk < want) cappedByChain++;
          } else {
            expect(g.shrunk, want, reason: when);
          }
          if (g.shrunk > 0) shrunkRows++;
          // 넘침 없음: 띠마다 제 몸통 끝 ≤ 줄의 칸 뭉치 끝(사건 칸 올림 ≥ 0) · 몸통 아랫변 ≤ 띠 아랫변.
          var longest = g.bodyTop;
          for (final b in f.bands) {
            if (!b.cells) continue;
            final end = TagLook.floorEndOf(g, b.look, sub: b.sub);
            expect(end, lessThanOrEqualTo(g.floorEnd + 1e-9), reason: '$when: 띠 ${b.kinds} 넘침');
            expect(TagLook.eventLift(g, b.look, oldStore: false, loose: density < 0, sub: b.sub), greaterThanOrEqualTo(0.0), reason: when);
            expect(TagLook.bodyBottom(g, b.look, oldStore: false, loose: density < 0, sub: b.sub), lessThanOrEqualTo(bottomOf(g) + 1e-9), reason: when);
            longest = math.max(longest, end);
          }
          // 모두 켠 기본 보기(사슬 켬 · 빽빽하게 아님): 가장 긴 띠가 줄의 칸 뭉치 끝에 닿는다(7을 넘어 덜 준 줄 · 내보내기가 U로 센 줄 ·
          // 사슬 묶음으로 덜 준 줄은 빼고). 사슬 끔은 왕조 · 지위가 칸 뭉치로 돌아와 덜 줄어든다(넘침만 위에서 봄).
          if (chain && !dense && !f.capped && !f.whole && g.shrunk == f.shrink && f.bands.any((b) => b.cells)) {
            expect(longest, g.floorEnd, reason: '$when: 가장 긴 띠');
          }
        }
      }
    }
    expect(shrunkRows, greaterThan(100));
    // ignore: avoid_print
    print('몸통 견줌: 줄 ${rowsOf.length} × 보기 여섯 · 줄어든 줄 $shrunkRows · 사슬 묶음으로 덜 준 줄 $cappedByChain');
  });

  // 층마다 줄 하나(그 층 + 짝 층 — 두 띠가 하나씩 · 줄어듦 1): 보기가 그 층을 빼면 그 줄만 0. 짝은 보기가 빼지 않는 기관 층(줄마다 트랙 하나라
  // 트랙 값 = 줄 값) — 기관 줄의 짝은 내각.
  // 왕조 · 지위는 셈에 없어 짝만으로는 줄지 않으므로 보기가 빼지 않는 예속 층과 한 띠에 둔다 — 보기가 왕조 · 지위를 빼도 그 줄은 그대로 1.
  Floors pair(int k, {int other = kOrgan}) => Floors.of([Band({k}), Band({other})]);
  final byKind = <String, Floors>{
    '왕조': Floors.of([Band({kDyn, kDep}), Band({kOrgan})]),
    '시기': pair(kPhase),
    '지위': Floors.of([Band({kRank, kDep}), Band({kOrgan})]),
    '집권': pair(kPower),
    '실권': pair(kReal),
    '내각': pair(kCab),
    // 직위 줄 더만 가진 띠는 내보내기가 U로 세어 줄지 않으므로 지도자와 함께 둔다.
    '직위 줄 더': Floors.of([Band({kLeader, kOffice}), Band({kOrgan})]),
    '예속': pair(kDep),
    '기관': pair(kOrgan, other: kCab),
    '두 단': Floors.of([Band({kLeader}, lanes: 2), Band({kLeader, kCab})]),
  };
  final names = byKind.keys.toList();
  Map<String, dynamic> kindsJson() => layoutOf([for (final n in names) [row(names.indexOf(n), byKind[n]!)]]);
  Map<String, int> shrunkOf(SceneLayout l) => {for (int i = 0; i < names.length; i++) names[i]: l.geo(i).shrunk};
  Map<String, int> allBut(Set<String> zero) => {for (final n in names) n: zero.contains(n) ? 0 : 1};

  test('보기가 그 줄의 셈에 든 층을 빼면 0 — 표시 체크 · 빽빽하게 · 스위치 legit · office 끔 · 왕조 · 지위는 빼도 그대로 (사슬 켬 · 끔 모두)', () {
    for (final n in names) {
      expect(byKind[n]!.shrink, 1, reason: n);
    }
    for (final chain in [true, false]) {
      final l = build(kindsJson(), chain: chain);
      expect(shrunkOf(l), allBut({}), reason: '모두 켠 보기 · 사슬 $chain');
      void view(ViewConditions c, Set<String> zero, String why) {
        l.setConditions(c);
        l.finishFlow();
        expect(shrunkOf(l), allBut(zero), reason: '$why · 사슬 $chain');
      }

      const all = ViewConditions();
      view(all.copyWith(dynasties: false), {}, "표시 '왕조' 끔 — 셈에 없어 그대로");
      view(all.copyWith(phases: false), {'시기'}, "표시 '시기' 끔");
      view(all.copyWith(ranks: false), {}, "표시 '지위' 끔 — 셈에 없어 그대로");
      view(all.copyWith(groups: false), {'집권', '실권'}, "표시 '단체' 끔");
      view(all.copyWith(cabinets: false), {'내각', '기관', '두 단'}, "표시 '내각' 끔");
      view(all.copyWith(leaders: false), {'두 단', '직위 줄 더'}, "표시 '지도자' 끔 — 직위 줄 더 층도 빠짐");
      view(all.copyWith(density: 1), {'시기', '집권', '실권'}, '빽빽하게 — 지위가 숨는 것은 셈 밖');
      view(all, {}, '되돌림');
      expect(shrunkOf(build(kindsJson(), chain: chain, legit: false)), allBut({'두 단'}), reason: '스위치 legit 끔 — 지도자 한 단 · 사슬 $chain');
      expect(shrunkOf(build(kindsJson(), chain: chain, office: false)), allBut({'직위 줄 더'}), reason: '스위치 office 끔 — 직위 줄 더 층 없음 · 사슬 $chain');
      expect(shrunkOf(build(kindsJson(), chain: chain, body: false)), allBut(names.toSet()), reason: '스위치 body 끔 · 사슬 $chain');
    }
  });

  test('두 장 꼬리표 줄의 기관 층은 줄 값(비트 6 — 계약 1-1 덧붙임) · 줄 값 없는 줄 · 스위치 body 끔은 트랙 값(예전)', () {
    // 한 트랙 세 줄: 줄 0 기관 있음(트랙 값 켬) · 줄 1 기관 없음(줄어듦 1 — 시기 · 지도자) · 줄 2 기관 없음 · 줄 값 없음(변형이 새로 만든 줄의 꼴).
    final withOrgan = Floors.of([Band({kOrgan})]), noOrgan = pair(kPhase, other: kLeader);
    Map<String, dynamic> json() => layoutOf([
      [row(0, withOrgan), row(1, noOrgan), row(2, noOrgan, cellRows: false)],
    ]);
    final l = build(json(), chain: false), flat = build(json(), chain: false, body: false);
    expect(l.organOf(0), isTrue, reason: '트랙 값(보이는 줄들로 다시 셈)은 그대로 켬');
    expect(l.geo(0).organTop, greaterThanOrEqualTo(0), reason: '기관 칸 주인이 있는 줄');
    final g = l.geo(1);
    expect(g.organTop, -1, reason: '줄 값 — 기관 칸 주인이 없는 줄에는 기관 층이 없다');
    expect(g.shrunk, 1);
    // 가장 긴 띠가 줄의 칸 뭉치 끝(서고 미리보기 geoFor의 `trackOrgan && organRows.has(r)`와 같은 높이 — 남는 기관 층 14가 없다): 시기 · 지도자 2층 − 1.
    expect([for (final b in noOrgan.bands) TagLook.floorEndOf(g, b.look, sub: b.sub)].reduce(math.max), g.floorEnd);
    expect(g.floorEnd, g.bodyTop + G.floor);
    // 줄 값 없는 줄은 트랙 값 — 기관 층이 서고 스위치와 상관없이 같다.
    expect(l.geo(2).organTop, greaterThanOrEqualTo(0));
    expect(fields(l.geo(2)), fields(flat.geo(2)), reason: '줄 값 없는 줄');
    // 스위치 body 끔: 늘 트랙 값(예전 그대로) — 줄 1에도 기관 층 · 줄지 않음.
    final o = flat.geo(1);
    expect([o.organTop >= 0, o.shrunk], [true, 0]);
    expect(g.height, o.height - 2 * G.floor, reason: '기관 층 14 + 줄어든 층 14');
  });

  test('왕조 · 지위는 셈에 없음 — 사슬 켬 · 끔 모두 저장된 값 그대로 읽음 · 사슬 단은 줄어든 띠 아랫변을 따라 올라감 · 칸 층은 사슬 단 위에 묶임', () {
    // 줄 0: 지위 · 시기 · 지도자 · 내각(U 3 — 지위 밖) — 띠 가 [지위 시기] 1층 · 띠 나 [지도자 내각] 2층 → 1층 줄어듦.
    // 줄 1: 왕조 · 지위 · 지도자 · 내각(U 2) — 띠 가 [왕조 지위]는 사슬만(제 층 0) · 띠 나 [지도자 내각] 2층 → 0(줄지 않음).
    // 줄 2: 지위 · 시기 2 · 지도자 · 내각 · 기관(U 5) — 띠 가 [지위 시기] 2층 · 띠 나 [지도자 내각 기관] 3층 → 2층 → 사슬 켬이면 사건 칸 한 줄에서
    // 사슬 단에 묶여 1(넉넉하게는 2).
    final a0 = Band({kRank, kPhase}), b0 = Band({kLeader, kCab});
    final r0 = Floors.of([a0, b0]), r1 = Floors.of([Band({kDyn, kRank}), Band({kLeader, kCab})]);
    final r2 = Floors.of([Band({kRank, kPhase}), Band({kLeader, kCab, kOrgan})], phase: 2);
    expect([r0.shrink, r1.shrink, r2.shrink], [1, 0, 2]);
    Map<String, dynamic> json() => layoutOf([
      [row(0, r0)],
      [row(1, r1)],
      [row(2, r2)],
    ]);
    final off = build(json(), chain: false), on = build(json()), flat = build(json(), body: false);
    expect([off.geo(0).shrunk, off.geo(1).shrunk, off.geo(2).shrunk], [1, 0, 2], reason: '사슬 끔이면 저장된 값 그대로(지위 · 왕조가 칸 뭉치로 돌아와 덜 줄어듦)');
    expect([on.geo(0).shrunk, on.geo(1).shrunk, on.geo(2).shrunk], [1, 0, 1], reason: '사슬 켬도 그대로 — 줄 2만 사슬 묶음으로 1');
    // 사슬 끔: 왕조 · 지위가 칸 뭉치로 돌아와도 넘침 없음(덜 줄어든다) — 띠마다 제 몸통 끝 ≤ 칸 뭉치 끝.
    for (final (r, f) in [(0, r0), (1, r1), (2, r2)]) {
      final go = off.geo(r);
      for (final b in f.bands) {
        expect(TagLook.floorEndOf(go, b.look, sub: b.sub), lessThanOrEqualTo(go.floorEnd), reason: '사슬 끔 줄 $r 띠 ${b.kinds}');
      }
    }
    expect(off.geo(0).floorEnd, off.geo(0).bodyTop + 3 * G.floor, reason: '사슬 끔 줄 0: 지위 · 시기 · 지도자 · 내각 4층 − 1');
    final g = on.geo(0), o = flat.geo(0);
    expect(g.chainTop, bottomOf(g), reason: '사슬 단은 띠 아랫변 밑');
    expect(g.chainTop, o.chainTop - G.floor, reason: '줄어든 만큼 사슬 단도 올라감');
    expect(g.rankTop, o.rankTop - G.floor);
    expect(g.rankChained, isTrue);
    // 사슬 켬의 참 값: 칸 층 셋(시기 · 지도자 · 내각) − 띠 나 2 = 1 — 가장 긴 띠가 칸 뭉치 끝.
    expect(TagLook.floorEndOf(g, b0.look, sub: 0), g.floorEnd);
    expect(TagLook.floorEndOf(g, a0.look, sub: 0), g.bodyTop + G.floor);
    // 띠마다의 사슬 자리 — 제 몸통 아랫변 밑 틈 3.
    expect(TagLook.chainYOf(g, a0.look, g.rankTop, oldStore: false, loose: false, sub: 0), TagLook.bodyBottom(g, a0.look, oldStore: false, sub: 0) + G.chainGap);
    expect(TagLook.compactOf(g, b0.look, g.rankTop, sub: 0), g.rankTop, reason: '맞붙이기는 사슬 자리를 건드리지 않는다');
    // 묶임: 칸 층을 모두 쌓은 끝이 사슬 단 위.
    final g2 = on.geo(2);
    expect(g2.stackEnd, lessThan(g2.chainTop - .5));
    on.setConditions(on.conditions.copyWith(density: -1));
    on.finishFlow();
    expect(on.geo(2).shrunk, 2, reason: '넉넉하게(사건 칸 두 줄)는 사슬 단까지 넉넉해 2');
    expect(on.geo(2).stackEnd, lessThan(on.geo(2).chainTop - .5));
  });

  test('렌즈 켬 · 줄 값 없는 줄 · 변형 줄 · 비트 3 ~ 5 = 0인 옛 저장소 · 스위치 body 끔은 0', () {
    final f = first;
    final variants = [
      {
        'id': 1, 'key': 'host:h1', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '은륜 제국',
        'rows': [
          {'row': 2, 'after': 0, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': <dynamic>[],
      },
    ];
    final json = layoutOf([
      [row(0, f), row(1, f, cellRows: false), row(2, f, variant: 1), row(3, f, carried: false)],
    ], variants: variants);
    final l = build(json);
    expect(l.expandHost(7, true), isTrue);
    l.finishFlow();
    expect([for (int r = 0; r < 4; r++) l.geo(r).shrunk], [1, 0, 0, 0], reason: '줄 값 줄만 · 변형 줄(켠 소속 펼치기) · 비트 3 ~ 5 = 0은 0');
    expect(l.spec(3)!.shrink, 0, reason: '옛 꼴(비트 3 ~ 5 = 0)이면 줄 값을 읽지 않는다');
    expect(l.spec(2)!.shrink, 1, reason: '변형 줄은 값이 서도 읽지 않는다');
    // 옛 셈(엔진 답에 칸이 없는 손 답)도 같다.
    final legacy = RowFlags.legacy(f.lanes > 0 ? 1 << 17 | 1 << 28 : 1 << 28, 0);
    expect(legacy.shrink, 0);
    // 렌즈 켬.
    expect(l.setThemeLens('system', slots: {'body-0'}), isTrue);
    l.finishFlow();
    expect(l.geo(0).shrunk, 0, reason: '렌즈 켬');
    expect(l.setThemeLens(''), isTrue);
    l.finishFlow();
    expect(l.geo(0).shrunk, 1, reason: '렌즈 끔이면 다시');
    // 스위치 body 끔은 줄 값을 지운 배치와 같다.
    final cleared = layoutOf([
      [row(0, f, shrink: 0), row(1, f, cellRows: false, shrink: 0), row(2, f, variant: 1, shrink: 0), row(3, f, carried: false, shrink: 0)],
    ], variants: variants);
    final off = build(json, body: false), bare = build(cleared);
    for (final x in [off, bare]) {
      x.expandHost(7, true);
      x.finishFlow();
    }
    for (int r = 0; r < 4; r++) {
      expect(fields(off.geo(r)), fields(bare.geo(r)), reason: '줄 $r');
      expect(off.rowTop(r), bare.rowTop(r));
    }
  });
}
