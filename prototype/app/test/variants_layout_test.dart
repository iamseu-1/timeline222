import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:flutter_test/flutter_test.dart';

// 변형(계약 3-2절) — 소속 펼치기 `host:<상위 띠 번호>`와 대범위 모아 보기 `scope:<대범위 uid>`가
// 줄을 옮겨 쌓는 길. 켜지 않은 변형의 줄은 높이 0 · `isVisible` 거짓이고, 켜면 `after`가 가리키는 줄 바로 아래에 끼워 쌓인다.
//
// 앞쪽 묶음은 손으로 지은 뼈대로 쌓는 규칙만 보고(자료 처리부가 없어도 돈다), 뒤쪽 묶음은 월흔해 저장소로
// 실측(명세 05의 9.6절 `소속-펼침-전체` · 9.5절 `대범위-딱지`)과 견준다.

/// 줄 하나의 뼈대 — 굳은 자리 값은 다시 쌓기가 쓰지 않으므로 최소만 채운다.
/// [rail] · [organ]은 **줄 단위 트랙 값**(계약 3절 끝 · 6-5절)이다: `fig_wide`의 비트 3~5에 막대 단 수 + 1, 비트 6에 기관 칸.
/// [rail]이 −1이면 그 값이 실리지 않은 옛 저장소의 줄이다(트랙에 적힌 값을 그대로 쓴다).
Map<String, dynamic> row(int id, {int kind = 0, int variant = 0, int lines = 1, bool groupStart = false, int scopePad = 0, int rail = -1, bool organ = false}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': lines, 'rail_top': 0, 'organ_top': -1,
  'kind': kind, 'group_start': groupStart ? 1 : 0, 'scope_pad': scopePad, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': ((rail + 1) << 3) | (organ ? 64 : 0), 'dep': 0, 'zones': 0, 'hem': 0, 'variant': variant,
};

Map<String, dynamic> skeleton() => {
  'packs': [
    {'id': 1, 'name': '검사 자료집', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울', 'color': 0xa0bcc5,
      'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
      'rows': [row(0), row(1), row(2), row(3), row(4, variant: 1, kind: 1), row(5, variant: 1, kind: 1), row(6, variant: 9)],
      'groups': [
        {'depth': 0, 'first': 0, 'count': 4, 'name': '윗물 겨레', 'color': 0xbcd8c1, 'kind': 0},
      ],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
  'variants': [
    {
      'id': 1, 'key': 'host:h1', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '은륜 제국',
      'rows': [
        {'row': 4, 'after': 1, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
        {'row': 5, 'after': 4, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
        {'row': 2, 'after': 5, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      ],
      'groups': <dynamic>[],
    },
    {
      'id': 2, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '빈 왕좌의 할거',
      'rows': [
        {'row': 3, 'after': 0, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
        {'row': 1, 'after': 3, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
      ],
      'groups': [
        {'key': '__scope:s1', 'depth': 0, 'name': '빈 왕좌의 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [3]},
      ],
    },
  ],
};

SceneLayout fresh() => SceneLayout.fromJson(skeleton())..reduceMotion = true;

List<int> visibleOrder(SceneLayout layout) {
  final rows = [for (int r = 0; r < layout.rowCount; r++) if (layout.isVisible(r)) r];
  rows.sort((a, b) => layout.rowTop(a).compareTo(layout.rowTop(b)));
  return rows;
}

void main() {
  test('켜지 않은 변형의 줄은 높이 0 · 보이지 않는다', () {
    final layout = fresh();
    expect(layout.rowCount, 7);
    expect(visibleOrder(layout), [0, 1, 2, 3], reason: '변형 줄 넷 · 다섯 · 여섯은 빠진다');
    for (final r in [4, 5, 6]) {
      expect(layout.isVisible(r), isFalse);
      expect(layout.rowTop(r), -1);
      expect(layout.variantOf(r), r == 6 ? 9 : 1, reason: '줄 여섯은 저장소에 없는 변형의 줄이라 영영 숨는다');
    }
    expect(layout.variantKeys, isEmpty);
  });

  test('소속을 펼치면 그 줄이 상위 줄 바로 아래에 끼워 쌓인다', () {
    final layout = fresh();
    expect(layout.expandHost(7, true), isTrue, reason: '상위 띠의 번호로 켠다');
    expect(layout.variantKeys, ['host:h1']);
    expect(visibleOrder(layout), [0, 1, 4, 5, 2, 3]);
    expect(layout.isHostExpanded(7), isTrue);
    // 줄 위의 틈은 그 줄의 몫 맨 위에 든다(geo.bandTop이 곧 틈이다).
    // 펼친 소속 줄의 틈은 memberGap 1 + 줄 위 틈 5 = 6이다(꼬리표 갈래 E — 명세 05의 9.6절 실측 17은 웹의 탭 11 시절 값).
    expect(layout.geo(4).bandTop, 1 + 5);
    expect(layout.geo(5).bandTop, 1 + 5);
    // 그 뒤로 밀린 기본 줄의 틈은 그대로 3 + 5다.
    expect(layout.geo(2).bandTop, 3 + 5);
    expect(layout.expandHost(7, false), isTrue);
    expect(visibleOrder(layout), [0, 1, 2, 3]);
  });

  test('대범위를 켜면 줄이 옮겨 쌓이고 테두리의 머리 · 발이 틈에 더해진다', () {
    final layout = fresh();
    expect(layout.openScope('s1', true), isTrue);
    expect(visibleOrder(layout), [0, 3, 1, 2], reason: '줄 셋이 줄 영 바로 아래로 옮겨 쌓인다');
    // 가지의 첫 줄(그릇의 줄 — 위 틈 15 · 리메이크 조각 ③): 3(기본 틈) + 14(민족 경계) + 15(그릇 안 줄 위 틈) + 21(폴더 머리 — 내보낸 16을 다시 이음) = 53
    expect(layout.geo(3).bandTop, 3 + 14 + 15 + 21);
    // 가지가 끝난 뒤 처음 펴진 줄: 3 + 5 + 7(폴더 발 — 내보낸 6을 다시 이음) = 15
    expect(layout.geo(1).bandTop, 3 + 5 + 7);
    expect(layout.variantGroups(0).single.rows, [3]);
    expect(layout.openScope('s1', false), isTrue);
    expect(visibleOrder(layout), [0, 1, 2, 3]);
  });

  test('둘을 함께 켜면 차이가 겹쳐 쌓인다', () {
    final layout = fresh();
    layout.expandHost(7, true);
    layout.openScope('s1', true);
    expect(layout.variantKeys, ['host:h1', 'scope:s1']);
    // 소속 줄은 줄 1 아래에, 대범위 가지는 줄 0 아래에 — 사슬이 0 → 3 → 1 → 4 → 5 → 2로 이어진다.
    expect(visibleOrder(layout), [0, 3, 1, 4, 5, 2]);
  });

  test('보기 상태가 같으면 다시 쌓지 않는다', () {
    final layout = fresh();
    final before = layout.stackVersion;
    expect(layout.setViewState(layout.viewState), isFalse);
    expect(layout.stackVersion, before);
    expect(layout.expandHost(7, true), isTrue);
    expect(layout.stackVersion, greaterThan(before));
    expect(layout.expandHost(7, true), isFalse, reason: '이미 켠 것을 또 켜지 않는다');
    // 켠 변형이 바뀌면 타일의 내용도 바뀐다 — 판 번호가 갈려 옛 타일이 가려진다.
    final tiles = layout.version;
    expect(layout.openScope('s1', true), isTrue);
    expect(layout.version, isNot(tiles));
    layout.openScope('s1', false);
    expect(layout.version, tiles, reason: '같은 조합으로 돌아오면 옛 판 번호를 다시 쓴다');
  });

  // ── 변형을 켠 뒤의 트랙 값(계약 3절 끝) ──────────────────────────────────────
  //
  // 기간 막대 단 수 · 기관 칸은 띠 안에서는 트랙 하나의 값이지만 지금 연표는 **보이는 줄들**로 다시 셈한다.
  // 소속을 펼치면 새 줄이 들어오고 상위 줄의 사건이 그리로 옮겨 가므로, 그 값이 켜고 끌 때마다 달라질 수 있다.

  /// 트랙 하나에 기본 줄 넷 · 변형 줄 하나. 기본 줄에는 막대 2단 · 기관 없음, 변형 줄에만 막대 3단 · 기관이 있다.
  Map<String, dynamic> valueSkeleton() => {
    'packs': [
      {'id': 1, 'name': '검사 자료집', 'events': 0},
    ],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울', 'color': 0xa0bcc5,
        'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 1, 'rail_levels': 3,
        'rows': [
          row(0, rail: 2),
          row(1, rail: 0),
          row(2, rail: 2),
          row(3, rail: 1),
          row(4, variant: 1, kind: 1, rail: 3, organ: true),
        ],
        'groups': [
          {'depth': 0, 'first': 1, 'count': 2, 'name': '윗물 겨레', 'color': 0xbcd8c1, 'kind': 0},
        ],
      },
    ],
    'epochs': <dynamic>[],
    'variants': [
      {
        'id': 1, 'key': 'host:h1', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '은륜 제국',
        'rows': [
          {'row': 4, 'after': 0, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
          {'row': 1, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': <dynamic>[],
      },
    ],
  };

  test('트랙 값은 보이는 줄들의 최댓값 — 켜지 않은 변형의 줄은 세지 않는다', () {
    final layout = SceneLayout.fromJson(valueSkeleton())..reduceMotion = true;
    // 기본 보기: 변형 줄 넷은 없는 것과 같다 — 막대는 max(2, 2·0·2·1) = 2이고 기관 칸도 없다.
    expect([layout.railLevelsOf(0), layout.organOf(0)], [2, false]);
    // 리메이크 2부(목업 서고): 기간 막대는 '넉넉하게'에서만 — 자동 밀도의 띠에는 막대 자리가 없다.
    expect([layout.geo(0).railLevels, layout.geo(0).railTop], [0, -1]);
    layout.setConditions(layout.conditions.copyWith(density: -1));
    final base = layout.geo(0).height;
    // 넉넉하게: 막대는 그 줄의 값(줄 단위 값이 실린 저장소)이다 — 줄 0은 2단.
    expect(layout.geo(0).railLevels, 2);

    // 소속을 펼치면 그 줄이 들어와 트랙의 막대 셈이 3단이 되고 기관 칸이 생긴다 — 기관 층은 모든 줄의 띠에 함께 붙는다.
    expect(layout.expandHost(7, true), isTrue);
    expect([layout.railLevelsOf(0), layout.organOf(0)], [3, true]);
    expect(layout.geo(0).railLevels, 2, reason: '막대 단은 줄 값 — 줄 0은 그대로 2단');
    expect(layout.geo(4).railLevels, 3, reason: '들어온 변형 줄은 제 값 3단');
    // 기관 칸 층 14(G.floor — 두 장 꼬리표의 몸통 층 · 층 사이 틈 없음)만큼 높아진다.
    expect(layout.geo(0).height - base, G.organ);
    expect(layout.geo(0).height - base, 14);

    expect(layout.expandHost(7, false), isTrue);
    expect([layout.railLevelsOf(0), layout.organOf(0)], [2, false], reason: '끄면 되돌아온다');
    expect(layout.geo(0).height, base);
  });

  test('민족을 접으면 그 줄들이 트랙 값의 셈에서 빠진다', () {
    final layout = SceneLayout.fromJson(valueSkeleton())..reduceMotion = true;
    layout.expandHost(7, true);
    expect(layout.railLevelsOf(0), 3);
    // 줄 1~2를 접으면 합쳐진 줄(1)도 셈에서 빠진다 — 남는 것은 줄 0 · 3 · 4다.
    final track = layout.tracks[0];
    expect(layout.foldGroup(track, track.groups.single, true), isTrue);
    expect(layout.railLevelsOf(0), 3, reason: '변형 줄 4가 아직 보인다');
    layout.expandHost(7, false);
    expect([layout.railLevelsOf(0), layout.organOf(0)], [2, false], reason: '남은 줄 0 · 3은 2단 · 1단뿐이다');
  });

  test('켜지 않은 변형의 줄은 트랙에 남은 줄 수(자동 밀도)에도 들지 않는다', () {
    final layout = SceneLayout.fromJson(valueSkeleton())..reduceMotion = true;
    expect(layout.visibleRowCount(0), 4, reason: '기본 줄 넷 — 변형 줄은 빠진다');
    // 리메이크 2부: 자동 밀도의 글줄은 줄 수와 상관없이 머리 한 줄(예전: 여섯 이하면 둘).
    expect(layout.baseLines(0), 1);
    layout.expandHost(7, true);
    expect(layout.visibleRowCount(0), 5);
    expect(layout.baseLines(0), 1);
  });

  test('줄 단위 트랙 값이 실리지 않은 옛 저장소는 트랙에 적힌 값을 그대로 쓴다', () {
    final layout = SceneLayout.fromJson(skeleton())..reduceMotion = true; // 모든 줄의 fig_wide가 0
    expect(layout.spec(0)!.rail, -1);
    expect([layout.railLevelsOf(0), layout.organOf(0)], [2, false], reason: '뼈대의 트랙 값(rail_levels 2 · organ 0)');
    // 막대는 '넉넉하게'에서만 그린다(리메이크 2부) — 그때 줄 값이 없으면 트랙 값을 쓴다.
    expect(layout.geo(0).railLevels, 0);
    layout.setConditions(layout.conditions.copyWith(density: -1));
    expect(layout.geo(0).railLevels, 2);
  });

  // ── 대범위 가지 접기(계약 3-1 · 3-2절 · 지금 연표의 `foldedPeoples`의 `__scope:<uid>` 가지) ──
  //
  // 가지는 흩어져 있던 줄을 모아 오므로 드는 줄의 번호가 이어지지 않는다 — 민족처럼 '첫 줄 … 첫 줄 + 줄 수'로
  // 가릴 수 없어 열쇠 규칙을 넓혔고([ViewState.variantGroupKey]), 합쳐지는 줄은 **쌓는 차례에서 가장 앞선 줄**이다.

  /// 줄 일곱에 가지 하나(줄 2 · 4 · 6을 모은다). 사슬은 −1 → 0 → 1 → 2 → 4 → 6 → 3 → 5다.
  Map<String, dynamic> branchSkeleton() => {
    'packs': [
      {'id': 1, 'name': '검사 자료집', 'events': 0},
    ],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울', 'color': 0xa0bcc5,
        'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
        'rows': [for (int i = 0; i < 7; i++) row(i)],
        'groups': [
          {'depth': 0, 'first': 0, 'count': 7, 'name': '윗물 겨레', 'color': 0xbcd8c1, 'kind': 0},
        ],
      },
    ],
    'epochs': <dynamic>[],
    'variants': [
      {
        'id': 1, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '빈 왕좌의 할거',
        'rows': [
          {'row': 2, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
          {'row': 4, 'after': 2, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 6, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 3, 'after': 6, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
          {'row': 5, 'after': 3, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s1', 'depth': 0, 'name': '빈 왕좌의 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [2, 4, 6]},
        ],
      },
    ],
  };

  SceneLayout branch() => SceneLayout.fromJson(branchSkeleton())..reduceMotion = true;

  test('가지의 열쇠는 `<트랙 id>|__scope:<uid>` — 민족 묶음의 열쇠와 부딪치지 않는다', () {
    final layout = branch();
    layout.openScope('s1', true);
    final group = layout.variantGroups(0).single;
    expect(layout.variantGroupKeyOf(0, group.key), '1|__scope:s1');
    expect(layout.variantGroupKeyOf(0, group.key), isNot(layout.groupKeyOf(layout.tracks[0], layout.tracks[0].groups.single)));
    expect(layout.isVariantGroupFolded(0, group), isFalse);
  });

  test('가지를 접으면 드는 줄이 쌓는 차례의 첫 줄로 합쳐진다 — 사이에 낀 줄은 그대로다', () {
    final layout = branch();
    layout.openScope('s1', true);
    expect(visibleOrder(layout), [0, 1, 2, 4, 6, 3, 5]);
    final group = layout.variantGroups(0).single;

    expect(layout.foldVariantGroup(0, group.key, true), isTrue);
    expect(layout.isVariantGroupFolded(0, group), isTrue);
    // 줄 2가 합쳐진 줄이고 4 · 6은 그 안에 숨는다. 가지에 들지 않은 3 · 5는 그대로 보인다.
    expect(visibleOrder(layout), [0, 1, 2, 3, 5]);
    expect(layout.isFoldedGroupRow(2), isTrue);
    expect(layout.hasBody(2), isFalse, reason: '합쳐진 줄에는 가는 막대만 남는다');
    expect([layout.isMergedAway(4), layout.isMergedAway(6)], [true, true]);
    expect([layout.isMergedAway(3), layout.isMergedAway(5)], [false, false]);
    // 합쳐진 줄의 높이는 접힌 민족 줄과 같은 30(조감 14)이다.
    expect(layout.geo(2).height - layout.geo(2).bandTop, G.foldedGroup);
    // 가는 막대가 읽는 목록은 **가지의 줄만** 든다(사이에 낀 3 · 5는 들지 않는다).
    expect(layout.mergedRows[2], [2, 4, 6]);
    // 범위(`mergedGroups`)는 합쳐 놓은 줄 ~ 마지막 줄 + 1이라 사이에 낀 줄까지 품는다 —
    // 여기서는 합쳐 놓은 줄이 가장 앞 번호라 가지의 줄이 모두 든다(그렇지 않은 경우는 아래의 `backwardSkeleton` 검사).
    expect(layout.mergedGroups[2], 7);
    expect(layout.foldedVariantOf(2), 'scope:s1');

    expect(layout.foldVariantGroup(0, group.key, false), isTrue);
    expect(visibleOrder(layout), [0, 1, 2, 4, 6, 3, 5]);
    expect(layout.mergedRows, isEmpty);
  });

  test('가지를 끄면 접힘도 함께 쓸모가 없어진다 — 다시 켜면 늘 펼친 채로 모인다(지금 연표 js 7786)', () {
    final layout = branch();
    layout.openScope('s1', true);
    layout.foldVariantGroup(0, '__scope:s1', true);
    expect(layout.openScope('s1', false), isTrue);
    expect(visibleOrder(layout), [0, 1, 2, 3, 4, 5, 6], reason: '가지가 없으면 합쳐진 줄도 없다');
    expect(layout.mergedRows, isEmpty);
    expect(layout.openScope('s1', true), isTrue);
    // 지금 연표의 `toggleScope`는 켜는 순간 `foldedPeoples`에서 `<트랙 id>|__scope:<uid>`를 지운다 — 접힘 기억이 남지 않는다.
    expect(visibleOrder(layout), [0, 1, 2, 4, 6, 3, 5], reason: '켤 때는 늘 펼친 채 모인다');
    expect(layout.isVariantGroupFolded(0, layout.variantGroups(0).single), isFalse);
    expect(layout.viewState.foldedGroups, isEmpty, reason: '접힘 기억 자체가 지워진다');
  });

  test('켜면서 다른 것도 함께 바꿀 때 — revealForScope에 밑바탕 상태를 넘기면 앞서 엮은 것이 살아남는다', () {
    final layout = branch();
    layout.openScope('s1', true);
    layout.foldVariantGroup(0, '__scope:s1', true);
    layout.openScope('s1', false);
    // 한 손짓이 상위 정권 펼치기와 대범위 켜기를 함께 엮는 길(`archive_app._toggleVariant`)의 꼴.
    var next = layout.viewState.withHostExpanded(7, true);
    next = layout.revealForScope('s1', next);
    expect(next.expandedHosts, {7}, reason: '밑바탕을 넘기지 않으면 이 줄이 조용히 사라진다');
    expect(next.openScopes, {'s1'});
    expect(next.foldedGroups, isEmpty, reason: '켜는 김에 그 가지의 접힘도 지운다');
  });

  /// 합쳐 놓은 줄보다 **번호가 작은** 줄이 든 가지. 사슬은 −1 → 0 → 1 → 4 → 2 → 3 → 5라
  /// 쌓는 차례의 첫 줄(= 합쳐 놓은 줄)은 4이고, 같은 가지의 줄 2는 그보다 번호가 작다.
  Map<String, dynamic> backwardSkeleton() => {
    'packs': [
      {'id': 1, 'name': '검사 자료집', 'events': 0},
    ],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울', 'color': 0xa0bcc5,
        'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
        'rows': [for (int i = 0; i < 6; i++) row(i)],
        'groups': [
          {'depth': 0, 'first': 0, 'count': 6, 'name': '윗물 겨레', 'color': 0xbcd8c1, 'kind': 0},
        ],
      },
    ],
    'epochs': <dynamic>[],
    'variants': [
      {
        'id': 1, 'key': 'scope:s2', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's2', 'name': '세 자유 항구',
        'rows': [
          {'row': 4, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 2, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s2', 'depth': 0, 'name': '세 자유 항구', 'color': 0xd4a39b, 'kind': 2, 'rows': [4, 2]},
        ],
      },
    ],
  };

  test('합쳐 놓은 줄보다 번호가 작은 줄 — 가지를 훑는 곳은 mergedGroups의 범위가 아니라 mergedRows를 읽어야 한다', () {
    final layout = SceneLayout.fromJson(backwardSkeleton())..reduceMotion = true;
    layout.openScope('s2', true);
    expect(visibleOrder(layout), [0, 1, 4, 2, 3, 5], reason: '줄 4가 줄 1 아래로, 줄 2가 그 아래로 옮겨 쌓인다');

    expect(layout.foldVariantGroup(0, '__scope:s2', true), isTrue);
    expect(visibleOrder(layout), [0, 1, 4, 3, 5], reason: '줄 2가 줄 4에 합쳐진다');
    expect(layout.mergedRows[4], [4, 2], reason: '정확한 목록은 합쳐 놓은 줄보다 번호가 작은 줄도 든다');
    expect(layout.isMergedAway(2), isTrue);

    // 범위는 열쇠(= 합쳐 놓은 줄)에서 시작할 수밖에 없어 줄 2를 담지 못한다 — `for (r = head; r < end; r++)`로 훑으면 빠진다.
    final span = [for (int r = 4; r < layout.mergedGroups[4]!; r++) r];
    expect(span, [4], reason: '줄 2가 빠진다 — 타일 받기 · 빈 줄 접기가 mergedRows를 읽어야 하는 까닭');
  });

  test('가려는 곳 펴기: 접힌 가지 안의 줄로 가면 가지를 편다 — 합쳐진 줄 자신은 접힌 채로', () {
    final layout = branch();
    layout.openScope('s1', true);
    layout.foldVariantGroup(0, '__scope:s1', true);
    // 가지 안에 숨은 줄 6으로 가려면 가지를 펴야 한다.
    final next = layout.revealFor(6);
    expect(identical(next, layout.viewState), isFalse);
    layout.setViewState(next);
    expect(layout.isVisible(6), isTrue);
    // 합쳐진 줄(2) 자신으로 갈 때는 그대로 둔다.
    layout.foldVariantGroup(0, '__scope:s1', true);
    expect(identical(layout.revealFor(2), layout.viewState), isTrue);
  });

  test('대범위로 갈 때는 그 대범위를 켜고 접어 둔 가지도 편다(지금 연표 js 2517 · 2529)', () {
    final layout = branch();
    layout.openScope('s1', true);
    layout.foldVariantGroup(0, '__scope:s1', true);
    layout.openScope('s1', false);
    expect(layout.isVisible(4), isTrue, reason: '가지를 끄면 줄 4는 제 민족 묶음에 있다');
    // 날것의 `withScopeOpen`만으로 켜면 접어 둔 가지에 그대로 숨는다 — 부르는 쪽이 `openScope` · `revealForScope`를 지나야 하는 까닭이다.
    layout.setViewState(layout.viewState.withScopeOpen('s1', true));
    expect(layout.isVisible(4), isFalse);
    // `revealForScope`는 켜기와 펴기를 한 번에 한다 — 다시 쌓기도 한 번이다.
    layout.setViewState(layout.viewState.withScopeOpen('s1', false));
    final before = layout.stackVersion;
    layout.setViewState(layout.revealForScope('s1'));
    expect(layout.stackVersion, before + 1);
    expect(layout.isVisible(4), isTrue);
    expect(layout.isVariantGroupFolded(0, layout.variantGroups(0).single), isFalse);
  });

  test('조감에서는 대범위 테두리의 머리 16 → 12 · 발 6 → 4로 줄어든다(계약 3-1절 끝)', () {
    final layout = branch();
    layout.openScope('s1', true);
    // 보통(폴더 — 리메이크 조각 ③): 가지의 첫 줄 3 + 14(민족 경계) + 15(그릇 안 줄 위 틈) + 21(폴더 머리) = 53 · 가지 다음 줄 3 + 5 + 7(폴더 발) = 15
    expect(layout.geo(2).bandTop, 3 + 14 + 15 + 21);
    expect(layout.geo(3).bandTop, 3 + 5 + 7);

    expect(layout.setConditions(layout.conditions.copyWith(density: 2)), isTrue);
    final g = layout.metrics;
    expect([g.scopeHead, g.scopeFoot], [12.0, 4.0]);
    // 조감: 틈 6 · 민족 경계 6 · 탭 0 · 머리 12 = 24 · 발은 6 + 0 + 4 = 10
    expect(layout.geo(2).bandTop, g.gap + g.groupGap + g.tab + g.scopeHead);
    expect(layout.geo(3).bandTop, g.gap + g.tab + g.scopeFoot);
  });

  test('그릇의 세 상태(리메이크 조각 ③): 끈 것은 풀림 · 켠 것은 펼침 · 가지를 접으면 접힘 — 바꾸는 보기 상태는 한 값', () {
    final layout = branch();
    expect(layout.scopeStateOf('s1'), ScopeState.loose);
    expect(layout.scopeUidOfRow(2), '', reason: '끈 대범위의 줄은 어느 폴더에도 들지 않는다');
    // 풀림 → 접힘: 켜고 가지를 접은 값 하나(다시 쌓기 한 번).
    final closed = layout.viewForScopeState('s1', ScopeState.closed);
    expect(closed.openScopes, {'s1'});
    expect(closed.foldedGroups, {layout.variantGroupKeyOf(0, '__scope:s1')});
    expect(layout.setViewState(closed), isTrue);
    expect(layout.scopeStateOf('s1'), ScopeState.closed);
    expect(layout.scopeUidOfRow(2), 's1');
    // 접힘 → 펼침: 가지의 접힘 기억을 지운다.
    expect(layout.setViewState(layout.viewForScopeState('s1', ScopeState.open)), isTrue);
    expect(layout.scopeStateOf('s1'), ScopeState.open);
    expect(layout.viewState.foldedGroups, isEmpty);
    // 펼침 → 풀림: 끈다.
    expect(layout.setViewState(layout.viewForScopeState('s1', ScopeState.loose)), isTrue);
    expect(layout.scopeStateOf('s1'), ScopeState.loose);
    expect(layout.viewState.openScopes, isEmpty);
    expect(layout.viewForScopeState('s1', ScopeState.loose), layout.viewState, reason: '이미 풀린 그릇을 풀어도 바뀌는 것이 없다');
  });

  test('그릇의 줄(fig_wide 비트 15 · 켠 가지의 줄)은 줄 위 틈이 15다 — 솟는 줄(비트 14)은 20이 이긴다 · 조감은 0', () {
    final json = branchSkeleton();
    final rows = ((json['tracks'] as List)[0] as Map)['rows'] as List;
    // 줄 1: 그릇의 줄(비트 15) · 줄 3: 그릇의 줄이면서 솟는 줄(비트 14 · 15). 기간 막대 단 비트(3 ~ 5)가 있어야 새 저장소로 읽힌다.
    (rows[1] as Map)['fig_wide'] = (1 << 3) | (1 << 15);
    (rows[3] as Map)['fig_wide'] = (1 << 3) | (1 << 14) | (1 << 15);
    final layout = SceneLayout.fromJson(json)..reduceMotion = true;
    expect([layout.spec(1)!.contained, layout.spec(3)!.contained, layout.spec(3)!.raised], [true, true, true]);
    expect([layout.tabOf(0), layout.tabOf(1), layout.tabOf(3)], [5, 15, 20]);
    // 켠 대범위 가지의 줄(줄 2)은 비트가 없어도 그릇의 줄이다.
    expect(layout.tabOf(2), 5);
    layout.openScope('s1', true);
    expect(layout.tabOf(2), 15);
    layout.setConditions(layout.conditions.copyWith(density: 2));
    expect([layout.tabOf(1), layout.tabOf(2), layout.tabOf(3)], [0, 0, 0]);
  });

  test('본국 줄에 매달린 가지의 머리(−4): 켠 그릇이 덮어쓴 줄은 쓰지 않고(보통 21 · 조감 12) · 덮어쓰지 않은 옛 저장값만 조감에서 2가 된다', () {
    final json = branchSkeleton();
    // 지금 연표의 `_scopePad`: 본국 줄 바로 아래에 매달리면 `머리 + 2 − 줄 틈 − 민족 경계`(보통 16+2−8−14 = −4)다.
    (json['variants'] as List)[0]['rows'][0]['scope_pad'] = -4;
    final layout = SceneLayout.fromJson(json)..reduceMotion = true;
    layout.openScope('s1', true);
    // 보통에서는 폴더(리메이크 조각 ③)라 매달리지 않는다 — 온 머리 21: 3 + 14(민족 경계) + 15(그릇 안 줄 위 틈) + 21 = 53.
    expect(layout.geo(2).bandTop, 3 + 14 + 15 + 21);
    layout.setConditions(layout.conditions.copyWith(density: 2));
    final g = layout.metrics;
    // 리메이크 2부 포개짐(remake/nest/지도.md 3-1 ③): 켠 그릇 변형이 덮어쓴 줄의 머리 · 발은 저장값이 아니라 켠 그릇의 머리 · 발 —
    // 조감도 같은 식으로 머리 12(매달림 없음): 6 + 6 + 0 + 12 = 24.
    expect(layout.geo(2).bandTop, g.gap + g.groupGap + g.tab + g.scopeHead);

    // 켠 그릇이 덮어쓰지 않은 줄의 옛 저장값(`_scopePadOf` — 옛 저장소의 길)은 예전대로 갈라 다시 잇는다: 보통 폴더 머리 21 · 조감 12 + 2 − 6 − 6 = 2.
    final old = branchSkeleton();
    (((old['tracks'] as List)[0] as Map)['rows'] as List)[2]['scope_pad'] = -4;
    final plain = SceneLayout.fromJson(old)..reduceMotion = true;
    expect(plain.geo(2).bandTop, 3 + 5 + 21);
    plain.setConditions(plain.conditions.copyWith(density: 2));
    expect(plain.geo(2).bandTop, g.gap + g.tab + 2);
  });

  // ── 월흔해 저장소로 실측과 견주기 ─────────────────────────────────────────────
  final dll = File('../engine/target/release/archive_engine.dll');
  // 새 저장소를 먼저 찾는다(12물결에서 다시 내보내 넣은 것). 없으면 그 물결의 작업자가 만든 것을 쓴다.
  final db = [File('../data/moonwake3i/archive.db'), File('../data/moonwake3-variants/archive.db')].where((f) => f.existsSync()).firstOrNull ?? File('../data/moonwake3-variants/archive.db');
  final ready = dll.existsSync() && db.existsSync();

  test('월흔해: 소속을 펼치면 줄이 22개가 되고 소속 줄의 틈이 17이다 (명세 05의 9.6절)', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
    final host = layout.variants.firstWhere((v) => v.kind == VariantInfo.kindHost);
    expect(host.key, startsWith('host:'));

    final coast = layout.tracks.first;
    int shown() => [for (int r = coast.firstRow; r < coast.firstRow + coast.rowCount; r++) if (layout.isVisible(r)) r].length;
    expect(shown(), 20, reason: '펼치기 전에는 스무 줄');

    expect(layout.expandHost(host.band, true), isTrue);
    expect(shown(), 22, reason: '9.6절 실측: 유리해안 rows 22');
    final order = visibleOrder(layout).where((r) => r < coast.firstRow + coast.rowCount).toList();
    final member = [for (final r in order) if (layout.spec(r)!.kind == RowKind.member) order.indexOf(r)];
    expect(member, [2, 3], reason: '9.6절 실측: memberRows [2, 3]');
    for (final at in member) {
      expect(layout.geo(order[at]).bandTop, 1 + 5, reason: '소속 줄의 틈 = memberGap 1 + 줄 위 틈 5(꼬리표 갈래 E — 9.6절 실측 rowGap 17은 웹의 탭 11 시절 값)');
    }
    // 켠 변형은 타일 · 조회 요청에 그대로 실어 보낸다.
    expect(layout.variantKeys, [host.key]);
  }, skip: ready ? false : '자료 처리부(archive_engine.dll)나 data/moonwake3-variants가 없습니다');

  test('월흔해: 대범위를 켜면 가지의 줄이 본국 줄 아래로 모이고 머리 16 · 발 6이 붙는다 (명세 05의 9.5절)', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
    final scope = layout.variants.firstWhere((v) => v.kind == VariantInfo.kindScope && v.groups.isNotEmpty && v.rows.any((r) => r.scopePad == 16));
    expect(layout.openScope(scope.uid, true), isTrue);

    final branch = scope.groups.single.rows;
    final order = visibleOrder(layout);
    final at = order.indexOf(branch.first);
    expect(at, greaterThan(0));
    // 가지의 첫 줄: 기본 틈 3 + 민족 경계 14 + 줄 위 틈 5 + 대범위 머리 16 = 38(꼬리표 갈래 E)
    expect(layout.geo(branch.first).bandTop, 3 + 14 + 5 + 16);
    // 가지의 줄들은 이어 붙어 있다.
    for (int i = 1; i < branch.length; i++) {
      expect(order.indexOf(branch[i]), at + i, reason: '가지의 줄은 이어 쌓인다');
    }
    // 가지가 끝난 뒤 처음 펴진 줄에는 발 6이 붙는다.
    expect(layout.geo(order[at + branch.length]).bandTop, 3 + 5 + 6);
    expect(layout.variantGroups(0).single.kind, 2);
  }, skip: ready ? false : '자료 처리부(archive_engine.dll)나 data/moonwake3-variants가 없습니다');

  // ── 왼쪽 칸의 대범위 점선 칸(명세 05의 9.5절 `대범위-딱지`) ─────────────────
  final stack2 = File('../data/moonwake3-stack2/archive.db');
  test('월흔해: 대범위 셋을 켜면 가지의 칸이 드는 줄 목록대로 늘어난다 (실측 9.5)', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(stack2.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
    // 기준 장면과 같게 셋을 켠다(할거 · 자유 항구 · 부흥 운동).
    for (final key in ['warlords', 'scattered', 'revival']) {
      final v = layout.variants.firstWhere((x) => x.key.endsWith('scope-$key'));
      expect(layout.openScope(v.uid, true), isTrue);
    }
    layout.finishFlow();
    final groups = {for (final g in layout.variantGroups(0)) g.name: g};
    expect(groups.keys, containsAll(['빈 왕좌의 할거', '세 자유 항구', '은륜 부흥 운동']));
    // 가지의 줄은 번호가 이어지지 않는다 — 왼쪽 칸은 목록으로 받아 첫 줄의 띠 윗변부터 마지막 줄의 아랫변까지 한 덩이로 그린다.
    expect(groups['빈 왕좌의 할거']!.rows, [8, 11, 12]);
    double boxHeight(VariantGroup g) {
      final rows = [for (final r in g.rows) if (layout.isVisible(r)) r]..sort((a, b) => layout.rowTop(a).compareTo(layout.rowTop(b)));
      final first = rows.first, last = rows.last;
      return layout.rowTop(last) + layout.geo(last).height - (layout.rowTop(first) + layout.geo(first).bandTop);
    }

    // 실측 9.5: `.tl-people.is-scope` 높이 419(빈 왕좌의 할거) · 273(은륜 부흥 운동).
    expect(boxHeight(groups['빈 왕좌의 할거']!), 419);
    expect(boxHeight(groups['은륜 부흥 운동']!), 273);
  }, skip: dll.existsSync() && stack2.existsSync() ? false : '자료 처리부(archive_engine.dll)나 data/moonwake3-stack2가 없습니다');

  test('월흔해: 켠 가지를 모두 접어도 합쳐 놓은 줄이 그 가지에서 번호가 가장 작다 (실제 저장소 — 범위로 훑는 곳의 안전 확인)', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(stack2.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
    for (final v in layout.variants) {
      if (v.kind == VariantInfo.kindScope) layout.openScope(v.uid, true);
    }
    // 켠 가지를 모두 걷어 두고(돌면서 접으면 목록이 다시 지어진다) 하나씩 접는다.
    final keys = <(int, String)>[];
    for (int i = 0; i < layout.tracks.length; i++) {
      for (final g in layout.variantGroups(i)) {
        keys.add((i, g.key));
      }
    }
    expect(keys, isNotEmpty, reason: '실제 저장소에 켤 가지가 있어야 뜻이 있는 검사다');
    for (final (at, key) in keys) {
      layout.foldVariantGroup(at, key, true);
    }
    layout.finishFlow();
    expect(layout.mergedRows, isNotEmpty);

    // `mergedGroups`의 범위는 합쳐 놓은 줄에서 시작한다 — 가지에 그보다 번호가 작은 줄이 들면 그 줄은 범위 밖이다.
    for (final e in layout.mergedRows.entries) {
      final end = layout.mergedGroups[e.key];
      expect(end, isNotNull);
      for (final r in e.value) {
        expect(r, inInclusiveRange(e.key, end! - 1),
            reason: '합쳐 놓은 줄 ${e.key}의 가지에 번호가 더 작은 줄 $r이 들었다 — 범위로 훑는 곳'
                '(scene.dart의 타일 받기 · fold.dart의 빈 줄 접기)이 그 줄을 빠뜨려 가는 막대가 통째로 빈다. '
                '그 두 곳을 layout.mergedRows로 고쳐야 한다');
      }
    }
  }, skip: dll.existsSync() && stack2.existsSync() ? false : '자료 처리부(archive_engine.dll)나 data/moonwake3-stack2가 없습니다');

  // ── 조감의 대범위 여백을 기준 덤프와 견주기(실측 `대범위-딱지-조감`) ───────────────
  //
  // 저장소의 `scope_pad`는 '조감이 아닌' 값 하나뿐이다 — 화면이 머리 16 → 12 · 발 6 → 4로 줄여야
  // 지금 연표의 조감과 줄 자리가 맞는다(계약 3-1절 끝). 기준 덤프의 줄 자리로 확인한다.
  // 조감 여백 검사는 `rows.scope_pad`만 보므로 어느 저장소로도 돈다 — 새 저장소를 먼저 찾는다(11물결 stack3 검토의 [low]).
  final stack3 = [File('../data/moonwake3i/archive.db'), File('../data/moonwake3-stack3/archive.db'), File('../data/moonwake3h/archive.db')].where((f) => f.existsSync()).firstOrNull ?? File('../data/moonwake3i/archive.db');
  final birdDump = File('../results/dom-r5/대범위-딱지-조감.json');

  /// 기준 덤프에서 첫 트랙의 줄 위의 틈 — `.tl-lane`의 자리와 높이로 잰다.
  List<double> dumpGaps(File file) {
    final dump = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final lanes = [
      for (final raw in (dump['items'] as List))
        if ('${(raw as Map)['c']}' == 'tl-lane' || '${raw['c']}'.startsWith('tl-lane ')) raw,
    ];
    final first = lanes.first['p'];
    final rows = [for (final l in lanes) if (l['p'] == first) (l['r'] as List)];
    final out = <double>[];
    double? end;
    for (final r in rows) {
      final top = (r[1] as num).toDouble();
      out.add(end == null ? 0 : top - end);
      end = top + (r[3] as num).toDouble();
    }
    return out;
  }

  /// 우리 쪽 첫 트랙의 줄 위의 틈(첫 줄은 0 — 트랙 여백은 견주지 않는다).
  List<double> layoutGaps(SceneLayout layout) {
    final coast = layout.tracks.first;
    final rows = [for (final r in visibleOrder(layout)) if (r >= coast.firstRow && r < coast.firstRow + coast.rowCount) r];
    final out = <double>[];
    for (int i = 0; i < rows.length; i++) {
      out.add(i == 0 ? 0 : layout.geo(rows[i]).bandTop);
    }
    return out;
  }

  Future<SceneLayout> scopesOn(ArchiveEngine engine, {int density = 0}) async {
    await engine.start(stack3.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
    for (final v in layout.variants) {
      if (v.kind == VariantInfo.kindScope) layout.openScope(v.uid, true);
    }
    if (density != 0) layout.setConditions(layout.conditions.copyWith(density: density));
    layout.finishFlow();
    return layout;
  }

  test('월흔해 · 조감: 대범위 여백이 머리 12 · 발 4로 줄어 기준 덤프의 줄 틈과 0px이다 (실측 대범위-딱지-조감)', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final bird = layoutGaps(await scopesOn(engine, density: 2));
    final want = dumpGaps(birdDump);
    expect(bird.length, want.length, reason: '보이는 줄 수');

    // 대범위 여백이 실제로 든 줄이 있어야 뜻이 있는 검사다:
    //   매달린 머리 14(= 틈 6 + 민족 경계 6 + (12 + 2 − 6 − 6)) · 머리 24(= 6 + 6 + 12) · 발 10(= 6 + 4) · 발+머리 28.
    expect(want, containsAll(<double>[14, 24, 10, 28]));

    // 대범위 넷을 한꺼번에 켠 자리는 변형끼리 겹친다(견본의 `무왕 협약 시대`가 `세 자유 항구`와 같은 정권을 집어 가고,
    // 두 가지가 같은 줄을 제 뒤에 두려 한다) — 저장소의 변형은 하나씩만 켠 채 잰 차이라 그 자리 한 줄은 맞출 수 없다.
    // 나머지는 모두 0px이어야 한다.
    final off = [for (int i = 0; i < want.length; i++) if ((bird[i] - want[i]).abs() > 0.01) i];
    for (final i in off) {
      // 어긋나더라도 그것이 **조감 전환** 때문이 아님을 못 박는다 — 차이는 대범위 발(4) 하나뿐이다.
      expect(want[i] - bird[i], closeTo(ViewMetrics.birdOf(BirdShape.a).scopeFoot, 0.01), reason: '$i번째 줄 위의 틈');
    }
    expect(off.length, lessThanOrEqualTo(1), reason: '겹친 대범위 때문에 어긋나는 줄은 하나뿐이다 · 실제 $off');
  }, skip: dll.existsSync() && stack3.existsSync() && birdDump.existsSync() ? false : '자료 처리부나 저장소(moonwake3i · moonwake3-stack3 · moonwake3h) · 기준 덤프가 없습니다');
}
