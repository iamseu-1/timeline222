import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagLook;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 지도자 두 단의 쌓기(칸 그림 갈래 걸음 2 · 정통성 넷 가 다듬은 꼴 lg2-ga — docs/계획-리메이크-4단계.md 과제 2 걸음 4 · 계약 1-1 덧붙임):
// 줄 fig_wide 26 ~ 27 + 1(그 줄의 지도자 층 단 수)이 2 이상인 줄은 지도자 층이 단 수 × 14(layout.dart `_bandOf` — RowGeo.leaderLanes) ·
// 칸 종류 1의 lane k는 그 층의 k번째 단(RowGeo.strip(1, k)). 띠는 제 단 수(sub 22 ~ 23 + 1)만 맞붙이고 남는 단은 뺀다(bands.dart TagLook.compactOf).
// 표시 '지도자'가 꺼졌거나 · 렌즈를 켰거나(계약 '렌즈 보기는 한 단') · 줄 값이 없는 줄(변형이 새로 만든 줄)이거나 · 스위치 legit을 끄면 한 단(예전 그대로).

/// 줄 fig_wide의 배치 값: 비트 3 ~ 5 = 기간 막대 단 수 + 1(이 값이 서야 줄 값 셋을 읽음) · 비트 17 = 지도자 칸 · 26 ~ 27 = 지도자 층 단 수 − 1.
int figWide({int lanes = 1, bool leader = true}) => 1 << 3 | (leader ? 1 << 17 : 0) | (lanes - 1) << 26;

/// 엔진 답 꼴의 줄 하나(chain_layout_test와 같은 꼴 — `rail` 칸이 있으면 나머지 칸도 읽는다).
Map<String, dynamic> row(int id, {int lanes = 1, bool cabinet = false, bool cellRows = true, bool leader = true}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': figWide(lanes: lanes, leader: leader), 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0,
  'rail': 0, 'cell_rows': cellRows ? 1 : 0, 'dynasty': 0, 'leader': leader ? 1 : 0, 'cabinet': cabinet ? 1 : 0, 'hang': 0,
};

/// 트랙 하나('legit-a'): 줄 0 두 단 + 내각 · 1 한 단 + 내각 · 2 두 단(내각 없음) · 3 줄 값 없음(cell_rows 0 — 변형이 새로 만든 줄의 꼴)이지만 두 단 비트.
Map<String, dynamic> legitLayout({int firstLanes = 2}) => {
  'packs': [
    {'id': 1, 'name': '두 단 견본', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'legit-a', 'dynasty': 0, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
      'rows': [row(0, lanes: firstLanes, cabinet: true), row(1, cabinet: true), row(2, lanes: 2), row(3, lanes: 2, cabinet: true, cellRows: false)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
};

/// 스위치 legit을 [legit]으로 두고 짓는다(배치는 쌓을 때 스위치를 읽는다). [firstLanes]는 줄 0의 단 수(견줌용 한 단 줄 0).
SceneLayout build({bool legit = true, int firstLanes = 2}) {
  PaintPick.legit = legit;
  return SceneLayout.fromJson(legitLayout(firstLanes: firstLanes))..reduceMotion = true;
}

/// 줄 생김새의 모든 값(chain_layout_test의 fields + 지도자 단 수).
List<Object> fields(RowGeo g) => [
  g.height, g.bandTop, g.bandHeight, g.dynastyTop, g.leaderTop, g.cabinetTop, g.textTop, g.textLines, g.railTop, g.organTop, g.phaseTop, g.phaseLanes,
  g.rankTop, g.powerTop, g.realTop, g.railLevels, g.figTop, g.figLevels, g.depTop, g.depHeight, g.zoneTop, g.zoneLanes, g.hangLanes, g.hangOpen, g.hemTop,
  g.lineH, g.bodyTop, g.floorEnd, g.chainTop, g.chainLanes, g.leaderLanes,
];

/// 띠 look: 비트 20 = 칸이 있다 · 21 + 5 지도자 · 21 + 6 내각. sub 22 ~ 23 = 띠의 지도자 단 수 − 1.
const hasCells = 1 << 20, leaderBit = 1 << 26, cabinetBit = 1 << 27;
const twoLanes = 1 << 22;

void main() {
  tearDown(PaintPick.reset);

  test('두 단 줄은 지도자 층이 14 × 2 — 줄 높이 +14 · 그 밑 층(내각 · 사건 칸)은 14 아래로', () {
    final l = build();
    final two = l.geo(0), one = l.geo(1), first = build(firstLanes: 1).geo(0);
    expect(l.spec(0)!.leaderLanes, 2, reason: '줄 fig_wide 26 ~ 27 + 1');
    expect([two.leaderLanes, one.leaderLanes, first.leaderLanes], [2, 1, 1]);
    expect(two.height - first.height, G.floor, reason: '같은 자리(트랙 첫 줄)의 한 단 줄보다 14 높다');
    expect(two.bandHeight - one.bandHeight, G.floor);
    expect(two.bandTop, first.bandTop);
    expect(two.leaderTop, two.bodyTop, reason: '몸통의 첫 층은 지도자');
    expect(two.leaderDepth, 2 * G.floor);
    expect(two.cabinetTop, two.leaderTop + 2 * G.floor);
    expect(two.floorEnd, two.bodyTop + 3 * G.floor);
    expect(two.textTop, two.floorEnd);
    expect(two.floorTops, [two.leaderTop, two.cabinetTop], reason: '지도자 층은 단 수와 상관없이 칸 층 하나(띠 전체를 가로지르는 단 사이 금 없음)');
    expect(one.floorTops, [one.leaderTop, one.leaderTop + G.floor]);
    // 뒤 줄은 앞 두 단 줄의 +14만큼 내려선다.
    final off = build(legit: false);
    expect(l.rowTop(1) - off.rowTop(1), G.floor);
    expect(l.rowTop(3) - off.rowTop(3), 2 * G.floor, reason: '줄 0 · 2가 두 단(줄 3은 줄 값이 없어 한 단)');
  });

  test('strip(1, 단) — 단 k는 지도자 층 윗변 + 14k · 줄의 단 밖 단은 단 0 자리 · 한 단 줄은 모두 단 0', () {
    final l = build();
    final two = l.geo(0), one = l.geo(1);
    expect(two.strip(1), (two.leaderTop, 14.0));
    expect(two.strip(1, 0), (two.leaderTop, 14.0));
    expect(two.strip(1, 1), (two.leaderTop + 14, 14.0));
    expect(two.strip(1, 2), (two.leaderTop, 14.0), reason: '줄의 단 밖');
    expect(two.strip(1, 3), (two.leaderTop, 14.0));
    expect(one.strip(1, 1), (one.leaderTop, 14.0), reason: '한 단 줄은 예전처럼 단을 보지 않는다');
    expect(two.strip(2), (two.cabinetTop, 14.0));
    // 흐르는 동안의 생김새(withHeight)도 단 수를 지닌다.
    final flowing = two.withHeight(10);
    expect([flowing.leaderLanes, flowing.strip(1, 1), flowing.floorTops], [2, two.strip(1, 1), two.floorTops]);
  });

  test('띠마다 제 단 — 한 단 띠는 지도자 층 아래 자리를 14 올리고 · 지도자 칸이 없는 띠는 28 올림 · 층 안 자리는 그대로', () {
    final g = build().geo(0);
    const lead = hasCells | leaderBit | cabinetBit, cabOnly = hasCells | cabinetBit;
    double compact(int look, double y, {int sub = 0}) => TagLook.compactOf(g, look, y, sub: sub);
    // 두 단 띠(sub 22 ~ 23 = 1): 줄의 자리 그대로.
    expect(compact(lead, g.cabinetTop, sub: twoLanes), g.cabinetTop);
    expect(compact(lead, g.floorEnd, sub: twoLanes), g.floorEnd);
    expect(compact(lead, g.leaderTop + 14, sub: twoLanes), g.leaderTop + 14, reason: '제 단 1의 자리');
    // 한 단 띠(sub 0): 지도자 층 아래는 남는 단(14)만큼 올림 · 층 안은 그대로.
    expect(compact(lead, g.cabinetTop), g.cabinetTop - 14);
    expect(compact(lead, g.floorEnd), g.floorEnd - 14);
    expect(compact(lead, g.leaderTop), g.leaderTop);
    // 지도자 칸이 없는 띠: 줄의 지도자 층 전체(28)만큼.
    expect(compact(cabOnly, g.cabinetTop), g.leaderTop);
    expect(compact(cabOnly, g.floorEnd, sub: twoLanes), g.floorEnd - 28, reason: 'sub는 지도자 칸이 있는 띠에만');
    // 몸통 아랫변 · 사건 칸 올림(floorEndOf · eventLift · bodyBottom)이 같은 셈을 따른다.
    expect(TagLook.floorEndOf(g, lead, sub: twoLanes), g.floorEnd);
    expect(TagLook.floorEndOf(g, lead, sub: 0), g.floorEnd - 14);
    expect(TagLook.eventLift(g, lead, oldStore: false, loose: false, sub: 0), 14.0);
    expect(TagLook.eventLift(g, lead, oldStore: false, loose: false, sub: twoLanes), 0.0);
    expect(TagLook.eventLift(g, hasCells | leaderBit, oldStore: false, loose: false, sub: 0), 28.0, reason: '지도자만 한 단 — 남는 단 14 + 남의 내각 14');
    expect(TagLook.bodyBottom(g, lead, oldStore: false, sub: 0), g.bandTop + g.bandHeight - 14);
    expect(TagLook.eventLift(g, lead, oldStore: true, loose: false, sub: 0), 0.0, reason: '옛 저장소는 줄의 자리');
    expect(TagLook.eventLift(g, lead, oldStore: false, loose: true, sub: 0), 0.0, reason: '넉넉하게는 올리지 않는다');
    // 한 단 줄에서는 sub가 두 단이라도 예전 셈 그대로(줄의 단 수를 넘지 않음).
    final one = build().geo(1);
    expect(TagLook.compactOf(one, lead, one.cabinetTop, sub: twoLanes), one.cabinetTop);
    expect(TagLook.compactOf(one, cabOnly, one.cabinetTop, sub: 0), one.leaderTop);
  });

  test("렌즈 켬 · 표시 '지도자' 끔 · 줄 값 없는 줄은 한 단", () {
    final l = build();
    final before = l.geo(0);
    expect(l.setThemeLens('system', slots: {'legit-a'}), isTrue);
    l.finishFlow();
    final lens = l.geo(0);
    expect(lens.leaderLanes, 1, reason: "계약 '렌즈 보기는 한 단'");
    expect(before.height - lens.height, G.floor);
    expect(lens.strip(1, 1), (lens.leaderTop, 14.0));
    expect(l.setThemeLens(''), isTrue);
    l.finishFlow();
    expect(fields(l.geo(0)), fields(before), reason: '렌즈를 끄면 다시 두 단');
    l.setConditions(l.conditions.copyWith(leaders: false));
    l.finishFlow();
    final hidden = l.geo(0);
    expect([hidden.leaderTop, hidden.leaderLanes, hidden.leaderDepth], [-1, 1, 0]);
    expect(hidden.cabinetTop, hidden.bodyTop);
    expect(before.height - hidden.height, 2 * G.floor, reason: '두 단 층이 통째로 빠진다');
    // 줄 값 없는 줄(cell_rows 0 — 변형이 새로 만든 줄과 같은 꼴): fig_wide의 단 수가 2여도 한 단(트랙 값으로 쌓음).
    final bare = build().geo(3);
    expect(build().spec(3)!.leaderLanes, 2);
    expect([bare.leaderLanes, bare.leaderDepth], [1, G.floor]);
    expect(bare.cabinetTop, bare.leaderTop + G.floor);
  });

  test('스위치 legit을 끄면 예전 손셈 그대로 — 두 단 비트가 있어도 지도자 층 14 · 한 단 줄과 같은 생김새', () {
    final off = build(legit: false);
    final g = off.geo(0), body = g.bodyTop;
    // 색줄 14 → 지도자 14 → 내각 14 → 사건 칸 18(예전 손셈).
    expect(body, g.bandTop + G.head);
    expect([g.leaderTop, g.cabinetTop, g.floorEnd, g.textTop, g.leaderLanes], [body, body + 14, body + 28, body + 28, 1]);
    expect(g.bandHeight, G.head + 2 * G.floor + G.evLine);
    expect(g.floorTops, [body, body + 14]);
    expect(g.strip(1, 1), (body, 14.0));
    expect(fields(g), fields(build(firstLanes: 1).geo(0)), reason: '같은 자리의 두 단 비트가 없는 줄과 같다');
    // 스위치를 끈 배치에서는 sub가 두 단인 띠도 예전 맞붙이기.
    const lead = hasCells | leaderBit | cabinetBit;
    expect(TagLook.compactOf(g, lead, g.cabinetTop, sub: twoLanes), g.cabinetTop);
    expect(TagLook.eventLift(g, hasCells | leaderBit, oldStore: false, loose: false, sub: twoLanes), G.floor);
    // 두 단 비트가 없는 줄은 스위치와 상관없이 같다.
    expect(fields(build().geo(1)), fields(off.geo(1)));
  });

  test('줄 값 셈(RowFlags) — 옛 셈(legacy)과 엔진 답 칸(fromAnswer)이 같은 단 수 · 비트 17이 없으면 한 단', () {
    for (final lanes in [1, 2, 3, 4]) {
      final packed = figWide(lanes: lanes);
      expect(RowFlags.layOf(packed).leaderLanes, lanes);
      expect(RowFlags.legacy(packed | 1 << 19, 0).leaderLanes, lanes);
    }
    expect(RowFlags.layOf(figWide(lanes: 2, leader: false)).leaderLanes, 1, reason: '지도자 칸 없는 줄');
    expect(RowFlags.layOf(1 << 17 | 1 << 26).leaderLanes, 1, reason: '비트 3 ~ 5가 0인 옛 저장소');
  });
}
