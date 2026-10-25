import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagLook;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 꼬리표 밑 흰 사슬 쌓기(감독 고름 G5 #9 나 · 차례 걸음 14 — docs/계획-리메이크-4단계.md): 왕조 · 지위는 칸 층에서 빠지고 띠 아랫변 바로 밑의
// 사슬 단에 선다 — 사슬 하나 = 틈 3 + 14(고르기 판 `themes/g-g5-9b.js`의 CH_GAP · CH_H) · 차례는 왕조 → 지위 · 그 뒤에 매단 속국 줄 · 구역 탭 ·
// 바탕 문화 단. 보이는 조건은 칸 층일 때와 같다(표시 '왕조' · '지위' · 지위는 빽빽하게에서 숨음 · 조감 없음). 스위치 chain을 끄면(`--paint-off=chain`)
// 예전 배치 그대로다. 줄 쌓기는 앱이 가진다(layout.dart `_bandOf` — 엔진 · 내보내기 · 정답지는 그대로).

/// 엔진 답 꼴의 줄 하나(줄 값이 실린 새 저장소 — `rail` 칸이 있으면 나머지 칸도 읽는다).
Map<String, dynamic> row(int id, {bool dynasty = false, bool rank = false, bool leader = true, int zones = 0, int hang = 0, bool hem = false, int phase = 0}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': phase, 'rank': rank ? 1 : 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': zones, 'hem': hem ? 1 : 0, 'variant': 0,
  'rail': 0, 'cell_rows': 1, 'dynasty': dynasty ? 1 : 0, 'leader': leader ? 1 : 0, 'cabinet': 0, 'hang': hang,
};

/// 트랙 둘: 'chain-a'의 줄 0 왕조 + 지위 · 1 왕조 · 2 지위 · 3 둘 다 없음 · 4 왕조 + 지위 + 시기 둘 + 매단 줄 1 · 구역 탭 2 · 바탕 문화 단,
/// 'chain-b'(지도자 칸 없음 — 렌즈 자리 트랙)의 줄 5 지위.
Map<String, dynamic> chainLayout() => {
  'packs': [
    {'id': 1, 'name': '사슬 견본', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'chain-a', 'dynasty': 1, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
      'rows': [
        row(0, dynasty: true, rank: true),
        row(1, dynasty: true),
        row(2, rank: true),
        row(3),
        row(4, dynasty: true, rank: true, phase: 2, zones: 3, hang: 1, hem: true),
      ],
    },
    {
      'id': 2, 'pack': 1, 'ord': 1, 'name': '물결 갈래', 'color': 0xc8b193, 'key': 'chain-b', 'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
      'rows': [row(5, rank: true, leader: false)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
};

/// 스위치 chain을 [chain]으로 두고 짓는다(배치는 쌓을 때 스위치를 읽는다).
SceneLayout build({bool chain = true}) {
  PaintPick.chain = chain;
  return SceneLayout.fromJson(chainLayout())..reduceMotion = true;
}

/// 줄 생김새의 모든 값(줄어든 층 — 칸 그림 갈래 걸음 5 · 이 견본은 줄 값이 없어 늘 0).
List<Object> fields(RowGeo g) => [
  g.height, g.bandTop, g.bandHeight, g.dynastyTop, g.leaderTop, g.cabinetTop, g.textTop, g.textLines, g.railTop, g.organTop, g.phaseTop, g.phaseLanes,
  g.rankTop, g.powerTop, g.realTop, g.railLevels, g.figTop, g.figLevels, g.depTop, g.depHeight, g.zoneTop, g.zoneLanes, g.hangLanes, g.hangOpen, g.hemTop,
  g.lineH, g.bodyTop, g.floorEnd, g.chainTop, g.chainLanes, g.shrunk,
];

double bottomOf(RowGeo g) => g.bandTop + g.bandHeight;

void main() {
  tearDown(PaintPick.reset);

  test('왕조 · 지위가 든 줄의 높이 = 예전 − 14 · n + 17 · n(사슬 n개) — 띠는 칸 층만큼 낮고 사슬 단만큼 줄의 몫이 길다', () {
    final off = build(chain: false), on = build();
    for (final (r, n) in [(0, 2), (1, 1), (2, 1), (3, 0), (4, 2), (5, 1)]) {
      final a = off.geo(r), b = on.geo(r);
      expect(b.height, a.height - G.floor * n + G.chainPitch * n, reason: '줄 $r(사슬 $n)');
      expect(b.height - a.height, 3.0 * n);
      expect(b.bandHeight, a.bandHeight - G.floor * n, reason: '줄 $r의 띠');
      expect(b.chainLanes, n);
      expect(b.chainDepth, G.chainDepthOf(n));
      expect(b.bandTop, a.bandTop, reason: '줄 위 틈은 그대로');
    }
    expect(G.chainGap + G.chain, 17, reason: '고르기 판 CH_GAP 3 + CH_H 14');
    // 뒤 줄은 앞 줄들의 사슬 몫(3 · n)만큼 내려선다.
    expect(on.rowTop(1) - off.rowTop(1), 6);
    expect(on.rowTop(4) - off.rowTop(4), 6 + 3 + 3);
    expect(on.totalHeight - off.totalHeight, 6 + 3 + 3 + 6 + 3);
  });

  test('strip(0) · strip(5)는 사슬 자리 — 띠 아랫변 밑 틈 3에 왕조, 그 밑 17에 지위 · 칸 층(floorTops)에는 들지 않는다', () {
    final l = build();
    final g = l.geo(0), bottom = bottomOf(g);
    expect(g.chainTop, bottom);
    expect(g.strip(0), (bottom + 3, 14.0));
    expect(g.strip(5), (bottom + 3 + 17, 14.0));
    expect(g.chainKinds, [0, 5]);
    expect([g.dynastyChained, g.rankChained], [true, true]);
    expect(g.leaderTop, g.bodyTop, reason: '몸통의 첫 층은 지도자');
    expect(g.floorTops, [g.leaderTop]);
    expect(g.floorEnd, g.bodyTop + G.floor);
    expect(g.textTop, g.floorEnd);
    expect(g.bandHeight, G.head + G.floor + G.evLine);
    expect(g.height, bottom + 34);
    // 왕조만 · 지위만이면 사슬 하나가 띠 아랫변 밑 첫 자리에.
    final d = l.geo(1), k = l.geo(2);
    expect([d.strip(0), d.strip(5).$1, d.chainKinds], [(bottomOf(d) + 3, 14.0), -1, [0]]);
    expect([k.strip(0).$1, k.strip(5), k.chainKinds], [-1, (bottomOf(k) + 3, 14.0), [5]]);
    // 사슬이 없는 줄.
    final none = l.geo(3);
    expect([none.chainTop, none.chainLanes, none.chainKinds], [-1, 0, <int>[]]);
    // 시기 층은 몸통에 남는다(시기 · 인물 막대 · 기간 사건 · 조약은 지금 꼴 — G5 #9 나).
    final p = l.geo(4);
    expect(p.phaseTop, p.bodyTop);
    expect(p.leaderTop, p.bodyTop + 2 * G.floor);
    expect(p.floorTops, [p.bodyTop, p.bodyTop + 14, p.bodyTop + 28]);
    expect(p.strip(4, 1), (p.bodyTop + 14, 14.0));
    expect(p.strip(0), (bottomOf(p) + 3, 14.0));
    expect(p.strip(5), (bottomOf(p) + 20, 14.0));
  });

  test('사건 칸 올림 — 왕조 · 지위는 칸 층이 아니라 올림 · 맞붙이기에 들지 않는다 · 사슬은 띠마다 제 꼬리표 바로 밑', () {
    const dynRank = 1 << 20 | 1 << 21 | 1 << 23, leaderOnly = 1 << 20 | 1 << (21 + 5), all3 = dynRank | 1 << (21 + 5), noBits = 1 << 20;
    final on = build().geo(0);
    expect(TagLook.floorEndOf(on, dynRank, sub: 0), on.bodyTop, reason: '왕조 · 지위만 가진 띠는 몸통에 칸 층이 없다');
    expect(TagLook.eventLift(on, dynRank, oldStore: false, loose: false, sub: 0), G.floor, reason: '남의 지도자 층만큼 올림');
    expect(TagLook.eventLift(on, leaderOnly, oldStore: false, loose: false, sub: 0), 0, reason: '왕조 · 지위가 없어도 올리지 않는다(그 둘은 몸통 밖)');
    expect(TagLook.eventLift(on, all3, oldStore: false, loose: false, sub: 0), 0);
    expect(TagLook.floorEndOf(on, noBits, sub: 0), on.floorEnd, reason: '칸 종류 비트가 없는 띠는 줄의 칸 뭉치 끝');
    expect(TagLook.compactOf(on, leaderOnly, on.leaderTop, sub: 0), on.leaderTop);
    expect(TagLook.compactOf(on, leaderOnly, on.rankTop, sub: 0), on.rankTop, reason: '맞붙이기(몸통 칸 층)는 사슬 자리를 건드리지 않는다 — 띠마다의 자리는 chainYOf');
    expect(TagLook.compactOf(on, leaderOnly, on.dynastyTop, sub: 0), on.dynastyTop);
    expect(TagLook.bodyBottom(on, dynRank, oldStore: false, sub: 0), bottomOf(on) - G.floor);
    expect(TagLook.bodyBottom(on, all3, oldStore: false, sub: 0), bottomOf(on), reason: '몸통 아랫변은 띠 아랫변 — 사슬은 그 밑');
    // 띠마다의 사슬 자리(TagLook.chainYOf — 고르기 판 below): 제 꼬리표(몸통) 아랫변 밑 틈 3부터 제 사슬만 맞붙인다.
    double chainY(int look, double y, {bool loose = false}) => TagLook.chainYOf(on, look, y, oldStore: false, loose: loose, sub: 0);
    const rankLeader = 1 << 20 | 1 << 23 | 1 << (21 + 5), rankOnly = 1 << 20 | 1 << 23;
    expect(chainY(all3, on.dynastyTop), on.dynastyTop, reason: '가장 긴 꼬리표의 띠는 줄의 사슬 자리 그대로');
    expect(chainY(all3, on.rankTop), on.rankTop);
    expect(chainY(dynRank, on.dynastyTop), TagLook.bodyBottom(on, dynRank, oldStore: false, sub: 0) + G.chainGap, reason: '지도자 층이 없는 짧은 꼬리표 — 사건 칸을 올린 만큼 사슬도 올림');
    expect(chainY(dynRank, on.rankTop), on.rankTop - G.floor);
    expect(chainY(rankLeader, on.rankTop), bottomOf(on) + G.chainGap, reason: '왕조가 없는 띠의 지위 사슬은 첫 사슬 자리');
    expect(chainY(rankOnly, on.rankTop), TagLook.bodyBottom(on, rankOnly, oldStore: false, sub: 0) + G.chainGap, reason: '올림 + 없는 위 사슬');
    expect(chainY(dynRank, on.dynastyTop, loose: true), on.dynastyTop, reason: '넉넉하게는 올리지 않는다(꼬리표가 모두 띠 아랫변까지)');
    expect(TagLook.chainYOf(on, rankOnly, on.rankTop, oldStore: true, loose: false, sub: 0), on.rankTop, reason: '옛 저장소는 줄의 자리');
    expect(chainY(noBits, on.rankTop), on.rankTop, reason: '칸 종류 비트가 없는 띠는 줄의 자리');
    expect(chainY(rankOnly, on.leaderTop), on.leaderTop, reason: '사슬 밖 자리는 그대로');
    // 예전(스위치 끔): 왕조 · 지위가 칸 층이라 그 둘이 없는 띠는 그만큼 올렸다.
    final off = build(chain: false).geo(0);
    expect(TagLook.eventLift(off, leaderOnly, oldStore: false, loose: false, sub: 0), 2 * G.floor);
    expect(TagLook.eventLift(off, dynRank, oldStore: false, loose: false, sub: 0), G.floor);
    expect(TagLook.compactOf(off, leaderOnly, off.leaderTop, sub: 0), off.bodyTop);
  });

  test('구역 탭 · 매단 줄 · 바탕 문화 단은 사슬 단 밑 — 매단 줄의 실 시작(몸통 아랫변)은 그대로', () {
    final off = build(chain: false), on = build();
    for (final open in [false, true]) {
      off
        ..foldHangs(4, !open)
        ..finishFlow();
      on
        ..foldHangs(4, !open)
        ..finishFlow();
      final a = off.geo(4), b = on.geo(4);
      expect(b.hangOpen, open);
      expect(a.zoneTop, bottomOf(a));
      expect(b.zoneTop, bottomOf(b) + 2 * G.chainPitch, reason: '사슬 둘 밑에서 덧단이 시작');
      expect(b.zoneTop, b.chainTop + b.chainDepth);
      for (int lane = 0; lane < 3; lane++) {
        final za = a.zoneLaneTop(lane), zb = b.zoneLaneTop(lane);
        expect(zb < 0 ? zb : zb - b.zoneTop, za < 0 ? za : za - a.zoneTop, reason: '${open ? '펼친' : '접은'} 매단 줄 · 덧단 $lane의 자리(덧단 안)');
        if (zb >= 0) expect(zb, greaterThanOrEqualTo(b.chainTop + b.chainDepth), reason: '덧단 $lane은 사슬 밑');
      }
      expect(b.hemTop - b.zoneTop, a.hemTop - a.zoneTop, reason: '바탕 문화 단');
      expect(b.height - b.hemTop, G.hem);
      expect(b.height - a.height, 2 * 3.0);
    }
    // 매단 줄의 실은 상국 몸통 아랫변에서(paint/hangs.dart — 사슬 단을 지나 내려간다).
    final g = on.geo(4);
    const all = 1 << 20 | 1 << 21 | 1 << 22 | 1 << 23 | 1 << (21 + 5);
    expect(TagLook.bodyBottom(g, all, oldStore: false, sub: 0), bottomOf(g));
    expect(g.zoneLaneTop(0), greaterThan(g.chainTop + g.chainDepth));
  });

  test("보이는 조건은 칸 층일 때와 같다 — 표시 '왕조' · '지위' 끔 · 빽빽하게는 지위 없음 · 조감은 사슬 없음", () {
    final l = build();
    l.setConditions(l.conditions.copyWith(dynasties: false));
    l.finishFlow();
    expect([l.geo(0).chainKinds, l.geo(1).chainKinds, l.geo(2).chainKinds], [[5], <int>[], [5]]);
    expect(l.geo(0).dynastyTop, -1);
    l.setConditions(l.conditions.copyWith(dynasties: true, ranks: false));
    l.finishFlow();
    expect([l.geo(0).chainKinds, l.geo(2).chainKinds], [[0], <int>[]]);
    expect(l.geo(0).rankTop, -1);
    l.setConditions(l.conditions.copyWith(ranks: true, density: 1));
    l.finishFlow();
    expect([l.geo(0).chainKinds, l.geo(2).chainKinds], [[0], <int>[]], reason: '빽빽하게는 지위를 숨긴다(예전 칸 층과 같음)');
    l.setConditions(l.conditions.copyWith(density: -1));
    l.finishFlow();
    expect(l.geo(0).chainKinds, [0, 5], reason: '넉넉하게');
    final loose = l.geo(0);
    expect(loose.chainTop, bottomOf(loose), reason: '넉넉하게도 띠(기간 막대 · 인물 단까지) 아랫변 밑');
    l.setConditions(l.conditions.copyWith(density: 2));
    l.finishFlow();
    for (int r = 0; r < 6; r++) {
      expect([l.geo(r).chainTop, l.geo(r).chainLanes, l.geo(r).dynastyTop, l.geo(r).rankTop], [-1, 0, -1, -1], reason: '조감 — 줄 $r');
    }
  });

  test('렌즈 켬 — 자리 트랙의 지도자 자리(+14)는 몸통에, 지위 단 자리(종류 8 단 1)는 사슬 자리 그대로', () {
    final l = build();
    final before = l.geo(5);
    expect(before.leaderTop, -1, reason: "'chain-b'는 지도자 칸이 없다");
    expect(before.strip(5), (bottomOf(before) + 3, 14.0));
    expect(l.setThemeLens('system', slots: {'chain-b'}), isTrue);
    l.finishFlow();
    final g = l.geo(5);
    expect(g.leaderTop, g.bodyTop);
    expect(g.height - before.height, G.leader, reason: '렌즈 켬의 지도자 자리는 예전처럼 칸 층 하나');
    expect(g.strip(5), (bottomOf(g) + 3, 14.0), reason: '렌즈의 지위 단 자리(paint/strips.dart _stripAt 종류 8 단 1 → strip(5))도 사슬 자리');
    expect(g.chainKinds, [5]);
    // 스위치를 끈 예전 배치에서는 지위 층이 몸통의 첫 층이고 렌즈 지도자 자리가 그 밑.
    final off = build(chain: false)..setThemeLens('system', slots: {'chain-b'});
    off.finishFlow();
    expect(off.geo(5).strip(5), (off.geo(5).bodyTop, 14.0));
    expect(off.geo(5).leaderTop, off.geo(5).bodyTop + G.floor);
    expect(g.height - off.geo(5).height, 3.0);
  });

  test('스위치 chain을 끄면 줄 생김새가 예전과 같다 — 왕조 · 지위가 칸 층 · 사슬 없음 · 덧단은 띠 아랫변에서', () {
    final off = build(chain: false);
    final g = off.geo(4), body = g.bodyTop;
    // 예전 배치(차례 걸음 13까지)의 손셈: 색줄 14 → 왕조 14 → 시기 2 × 14 → 지위 14 → 지도자 14 → 사건 칸 18 · 덧단은 띠 아랫변에서.
    expect(body, g.bandTop + G.head);
    expect([g.dynastyTop, g.phaseTop, g.phaseLanes, g.rankTop, g.leaderTop, g.floorEnd, g.textTop], [body, body + 14, 2, body + 42, body + 56, body + 70, body + 70]);
    expect(g.bandHeight, G.head + 5 * G.floor + G.evLine);
    expect(g.floorTops, [body, body + 14, body + 28, body + 42, body + 56]);
    expect([g.chainTop, g.chainLanes, g.chainKinds], [-1, 0, <int>[]]);
    expect([g.dynastyChained, g.rankChained], [false, false]);
    expect(g.zoneTop, bottomOf(g));
    expect(g.hemTop, bottomOf(g) + G.hangDepthOf(0) + 2 * (G.zoneTab + G.zoneGap) + 3, reason: '매단 줄을 접은 처음 보기');
    expect(g.height, g.hemTop + G.hem);
    // 왕조 · 지위가 없는 줄은 스위치와 상관없이 같다.
    final on = build();
    expect(fields(on.geo(3)), fields(off.geo(3)));
    // 흐르는 동안의 생김새(withHeight)도 사슬 자리를 지닌다.
    final flowing = on.geo(0).withHeight(10);
    expect([flowing.chainTop, flowing.chainLanes, flowing.strip(5)], [on.geo(0).chainTop, 2, on.geo(0).strip(5)]);
  });
}
