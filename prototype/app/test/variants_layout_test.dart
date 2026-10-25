import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
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
    // 소속 폴더(4단계 과제 8 걸음 2 — 스위치 folder)를 끈 예전 쌓기. 폴더의 머리 · 발 · 틈은 host_folder_layout_test.dart.
    PaintPick.folder = false;
    final layout = fresh();
    PaintPick.reset();
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
    // 줄 위 틈을 뺀 몫 — 소속을 펼치면 상국 줄(0)이 소속 폴더의 첫 줄이라 위 틈에 폴더 머리 · 그릇의 줄 틈이 붙는다(4단계 과제 8 걸음 2).
    final baseBody = base - layout.geo(0).bandTop;
    // 넉넉하게: 막대는 그 줄의 값(줄 단위 값이 실린 저장소)이다 — 줄 0은 2단.
    expect(layout.geo(0).railLevels, 2);

    // 소속을 펼치면 그 줄이 들어와 트랙의 막대 셈이 3단이 되고 기관 칸이 생긴다 — 기관 층은 모든 줄의 띠에 함께 붙는다.
    expect(layout.expandHost(7, true), isTrue);
    expect([layout.railLevelsOf(0), layout.organOf(0)], [3, true]);
    expect(layout.geo(0).railLevels, 2, reason: '막대 단은 줄 값 — 줄 0은 그대로 2단');
    expect(layout.geo(4).railLevels, 3, reason: '들어온 변형 줄은 제 값 3단');
    // 기관 칸 층 14(G.floor — 두 장 꼬리표의 몸통 층 · 층 사이 틈 없음)만큼 높아진다.
    expect(layout.geo(0).height - layout.geo(0).bandTop - baseBody, G.organ);
    expect(layout.geo(0).height - layout.geo(0).bandTop - baseBody, 14);

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

  // ── 포개진 그릇의 상자(과제 7 걸음 2) — 펼친 상자 머리 24(뚜껑 22 + 2) · 발 7, 접힌 상자 머리 6 · 발 0 · 합쳐진 줄 24 ──────────
  //
  // 줄 일곱의 트랙에 바깥 그릇 s2(줄 1 ~ 4 · 변형 1)와 그 안의 상자 s3(줄 3 · 4 · 변형 2 · within [1]). 바깥 변형이 안쪽 구성원의 줄 기록까지 들고,
  // 안쪽 변형의 줄 기록은 쓰지 않는다(remake/nest/지도.md 3-1). 줄 위 틈 = 틈 3(+ 민족 경계 14) + 탭(그릇의 줄 15 · 합쳐진 줄 0) + 그릇 머리 · 발.

  Map<String, dynamic> nestSkeleton() {
    Map<String, dynamic> scope(int id, String uid, List<int> rows, {List<int> within = const []}) => {
      'id': id, 'key': 'scope:$uid', 'kind': 2, 'track': 1, 'band': 0, 'uid': uid, 'name': uid,
      'rows': [
        for (final (i, r) in rows.indexed) {'row': r, 'after': r - 1, 'ord': 0, 'new': 0, 'scope_pad': i == 0 ? 16 : 0, 'group_start': i == 0 ? 1 : 0},
        {'row': rows.last + 1, 'after': rows.last, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
      ],
      'groups': [
        {'key': '__scope:$uid', 'depth': within.length, 'name': uid, 'color': 0xd4a39b, 'kind': 2, 'rows': rows},
      ],
      'within': within,
    };
    return {
      'packs': [
        {'id': 1, 'name': '검사 자료집', 'events': 0},
      ],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울', 'color': 0xa0bcc5,
          'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
          'rows': [for (int i = 0; i < 7; i++) row(i)],
        },
      ],
      'epochs': <dynamic>[],
      'variants': [scope(1, 's2', [1, 2, 3, 4]), scope(2, 's3', [3, 4], within: [1])],
    };
  }

  /// 줄 [r]의 (위 자리 · 높이 · 띠 위 틈 · 띠 높이).
  List<double> rowOf(SceneLayout layout, int r) => [layout.rowTop(r), layout.geo(r).height, layout.geo(r).bandTop, layout.geo(r).bandHeight];

  test('펼친 상자: 첫 줄 위에 머리 24(뚜껑 22 + 2) · 끝 줄 다음에 발 7 — 바깥 폴더의 머리 21 · 발 7은 그대로', () {
    final layout = SceneLayout.fromJson(nestSkeleton())..reduceMotion = true;
    layout.openScope('s2', true);
    layout.openScope('s3', true);
    expect((layout.scopeDepthOf('s2'), layout.scopeDepthOf('s3')), (0, 1));
    expect([G.boxHead, G.boxLid, G.boxFoot], [24, 22, 7]);
    expect(visibleOrder(layout), [0, 1, 2, 3, 4, 5, 6]);
    // 바깥 첫 줄 1: 3 + 14(민족 경계 — 변형 첫 줄) + 15 + 21(폴더 머리) · 줄 2: 3 + 15.
    expect(layout.geo(1).bandTop, 3 + 14 + 15 + G.folderHead);
    expect(layout.geo(2).bandTop, 3 + 15);
    // 상자 첫 줄 3: 3 + 15 + 24(상자 머리) · 줄 4: 3 + 15.
    expect(layout.geo(3).bandTop, 3 + 15 + G.boxHead);
    expect(layout.geo(4).bandTop, 3 + 15);
    // 두 그릇이 함께 끝난 다음 줄 5: 3 + 5 + 7(폴더 발) + 7(상자 발).
    expect(layout.geo(5).bandTop, 3 + 5 + G.folderFoot + G.boxFoot);
    expect(layout.closedBoxRowOf('s3'), -1, reason: '펼친 상자');
    // 상자의 세로 자리: 위 = 첫 줄 띠 윗변 − 탭 15 − 머리 24 · 아래 = 끝 줄 끝 + 발 7.
    final span = layout.scopeSpanOf('s3')!;
    expect(span.top, layout.rowTop(3) + layout.geo(3).bandTop - 15 - G.boxHead);
    expect(span.bottom, layout.rowTop(4) + layout.geo(4).height + G.boxFoot);
  });

  test('접힌 상자: 머리 6 · 발 0 · 합쳐진 줄 24(접힌 폴더 · 민족 줄의 30이 아님) — 바깥 폴더와 앞 줄은 그대로 · 뒤 줄은 줄어든 만큼 올라온다', () {
    final open = SceneLayout.fromJson(nestSkeleton())..reduceMotion = true;
    open.openScope('s2', true);
    open.openScope('s3', true);
    final layout = SceneLayout.fromJson(nestSkeleton())..reduceMotion = true;
    layout.openScope('s2', true);
    layout.openScope('s3', true);
    expect(layout.foldVariantGroup(0, '__scope:s3', true), isTrue);
    expect(layout.scopeStateOf('s3'), ScopeState.closed);
    expect(visibleOrder(layout), [0, 1, 2, 3, 5, 6], reason: '줄 4가 줄 3에 합쳐진다');
    expect(layout.closedBoxRowOf('s3'), 3);
    expect(layout.closedBoxRowOf('s2'), -1, reason: '바깥 폴더는 상자가 아니다');
    expect([G.boxClosedRoom, G.boxClosedFoot, G.boxClosed], [6, 0, 24]);
    // 합쳐진 줄 3: 3 + 탭 0 + 머리 6 · 띠(= 접힌 상자) 24.
    expect(rowOf(layout, 3).sublist(1), [3 + G.boxClosedRoom + G.boxClosed, 3 + G.boxClosedRoom, G.boxClosed]);
    // 줄 5: 3 + 5 + 7(폴더 발) + 0(접힌 상자 발).
    expect(layout.geo(5).bandTop, 3 + 5 + G.folderFoot + G.boxClosedFoot);
    // 바깥 폴더와 그 앞 줄(0 ~ 2)은 그대로.
    for (final r in [0, 1, 2]) {
      expect(rowOf(layout, r), rowOf(open, r), reason: '줄 $r');
    }
    expect(layout.scopeSpanOf('s2')!.top, open.scopeSpanOf('s2')!.top);
    // 상자의 세로 자리 = 위 틈 6 + 합쳐진 줄의 띠(24).
    final span = layout.scopeSpanOf('s3')!;
    expect([span.top, span.bottom], [layout.rowTop(3) + 3, layout.rowTop(3) + layout.geo(3).height]);
    // 뒤 줄(5 · 6)의 띠는 줄어든 높이만큼 함께 올라온다(펼친 상자 머리 24 + 줄 3 · 4 + 발 7 → 접힌 상자 위 틈 6 + 24 + 발 0) · 띠 몫은 그대로.
    double bandY(SceneLayout l, int r) => l.rowTop(r) + l.geo(r).bandTop;
    expect(bandY(layout, 5), layout.rowTop(3) + 3 + G.boxClosedRoom + G.boxClosed + 3 + 5 + G.folderFoot + G.boxClosedFoot);
    final shift = bandY(open, 5) - bandY(layout, 5);
    expect(shift, greaterThan(G.boxHead + G.boxFoot));
    for (final r in [5, 6]) {
      expect(bandY(layout, r), bandY(open, r) - shift, reason: '줄 $r');
      expect(layout.geo(r).height - layout.geo(r).bandTop, open.geo(r).height - open.geo(r).bandTop, reason: '줄 $r의 띠 몫은 그대로');
    }
    expect(layout.geo(6).bandTop, open.geo(6).bandTop);
    // 다시 펴면 예전 그대로.
    expect(layout.foldVariantGroup(0, '__scope:s3', false), isTrue);
    expect(layout.closedBoxRowOf('s3'), -1);
    for (int r = 0; r < 7; r++) {
      expect(rowOf(layout, r), rowOf(open, r), reason: '편 뒤 줄 $r');
    }
  });

  test('접힌 상자가 아닌 접힘은 그대로 — 바깥 폴더를 접으면 상자는 숨고 합쳐진 줄 30 · 조감의 접힌 상자는 14', () {
    final layout = SceneLayout.fromJson(nestSkeleton())..reduceMotion = true;
    layout.openScope('s2', true);
    layout.openScope('s3', true);
    layout.foldVariantGroup(0, '__scope:s2', true);
    expect(visibleOrder(layout), [0, 1, 5, 6]);
    expect(layout.closedBoxRowOf('s2'), -1);
    expect(layout.closedBoxRowOf('s3'), -1, reason: '바깥 접힘에 숨은 상자');
    expect(layout.geo(1).bandHeight, G.foldedGroup);
    expect(layout.geo(1).bandTop, 3 + 14 + G.folderHead);
    expect(layout.geo(5).bandTop, 3 + 5 + G.folderFoot);
    // 조감: 안쪽 상자만 접어도 옛 테두리(머리 12 · 발 4 · 합쳐진 줄 14).
    layout.foldVariantGroup(0, '__scope:s2', false);
    layout.foldVariantGroup(0, '__scope:s3', true);
    expect(layout.closedBoxRowOf('s3'), 3);
    layout.setConditions(layout.conditions.copyWith(density: 2));
    final g = layout.metrics;
    expect(layout.closedBoxRowOf('s3'), -1, reason: '조감은 상자가 아니다');
    expect(layout.geo(3).bandHeight, g.foldedGroup);
    expect(layout.geo(3).bandTop, g.gap + g.scopeHead);
  });

  // ── 선반 변형(kind 6 · `shelf:<그릇 uid>` — 리메이크 4단계 선반 갈래 걸음 5 · 계약 2-4절) ──────────
  //
  // 엔진 답의 모양을 손으로 옮겼다(lantern+shelf-chain 정답지의 변형 모양): 같은 그릇 s1에 그릇 변형(id 1)과 선반 변형(id 2)이 함께 있고,
  // 선반 변형은 그릇이 모으던 줄 2 · 4를 빠지는 줄(after −2 · ord −1 — 엔진 답은 ord 차례라 맨 앞)로 두고 다시 지은 새 줄 5 · 6을 쌓는다.
  // 숨긴 구성원 둘은 `shelf`(그릇 안 차례 5 · 6)로 온다. 선반 기억(`shelvedScopes`)에 둔 켠 그릇만 그릇 변형 대신 선반 변형을 켠다(과제 7 걸음 3).

  /// [shelf]가 거짓이면 선반 변형과 그 새 줄(5 · 6)이 없는 답 — 견줄 기준.
  /// [scopeNew]면 그릇 변형에만 있는 새 줄 7(변형 1 · 줄 4 다음)을 더한다 — 선반이 그릇 변형을 대신하는 동안 그 줄로 가는 길(가려는 곳 펴기)을 본다.
  Map<String, dynamic> shelfSkeleton({bool shelf = true, bool scopeNew = false}) => {
    'packs': [
      {'id': 1, 'name': '검사 자료집', 'events': 0},
    ],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xd7bf8e,
        'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
        'rows': [for (int i = 0; i < 5; i++) row(i), if (shelf) ...[row(5, variant: 2), row(6, variant: 2)], if (scopeNew) row(7, variant: 1)],
      },
    ],
    'epochs': <dynamic>[],
    'variants': [
      {
        'id': 1, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '선반 시험 그릇',
        'rows': [
          {'row': 2, 'after': 0, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
          {'row': 4, 'after': 2, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          if (scopeNew) {'row': 7, 'after': 4, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
          {'row': 1, 'after': scopeNew ? 7 : 4, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
          {'row': 3, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s1', 'depth': 0, 'name': '선반 시험 그릇', 'color': 0xd1a8b9, 'kind': 2, 'rows': [2, 4, if (scopeNew) 7]},
        ],
        'within': <int>[],
      },
      if (shelf)
        {
          'id': 2, 'key': 'shelf:s1', 'kind': 6, 'track': 1, 'band': 0, 'uid': 's1', 'name': '선반 시험 그릇',
          'rows': [
            {'row': 2, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
            {'row': 4, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
            {'row': 5, 'after': 0, 'ord': 0, 'new': 1, 'scope_pad': 16, 'group_start': 1},
            {'row': 6, 'after': 5, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
            {'row': 1, 'after': 6, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
            {'row': 3, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          ],
          'groups': [
            {'key': '__scope:s1', 'depth': 0, 'name': '선반 시험 그릇', 'color': 0xd1a8b9, 'kind': 2, 'rows': [5, 6]},
          ],
          'shelf': [
            {'uid': 'shelf/p-blackwater', 'name': '검은물 의병', 'color': 0x8a9a7b, 'start': -1051200, 'end': -525600, 'ord': 5},
            {'uid': 'shelf/p-namgang', 'name': '남강 임시정부', 'color': 0x9b8bb4, 'start': 5256000, 'end': 5781600, 'ord': 6},
          ],
        },
    ],
  };

  /// 보이는 줄의 차례와 줄마다 (위 자리 · 높이 · 띠 위 틈) — 기본 줄(0 ~ 4)만 견준다.
  List<Object> stackOf(SceneLayout layout) => [
    visibleOrder(layout),
    for (int r = 0; r < 5; r++) [layout.rowTop(r), if (layout.isVisible(r)) ...[layout.geo(r).height, layout.geo(r).bandTop]],
    layout.totalHeight,
  ];

  test('선반 기억이 없으면 선반 변형은 그릇을 켜도 켜지지 않는다 — variantKeys에 shelf가 없고 줄 쌓기가 선반 변형이 없는 답과 같다', () {
    final layout = SceneLayout.fromJson(shelfSkeleton())..reduceMotion = true;
    final plain = SceneLayout.fromJson(shelfSkeleton(shelf: false))..reduceMotion = true;
    // 끈 상태: 선반의 새 줄은 높이 0 · 보이지 않고, 빠지는 줄(2 · 4)도 제자리에 있다.
    expect(layout.variantKeys, isEmpty);
    expect(stackOf(layout), stackOf(plain));
    for (final r in [5, 6]) {
      expect([layout.isVisible(r), layout.rowTop(r), layout.variantOf(r)], [false, -1, 2]);
    }

    // 그릇을 켠다 — 예전의 기본 갈래(`_ => openScopes.contains(uid)`)는 uid가 같은 선반 변형까지 켜 버렸다.
    expect(layout.openScope('s1', true), isTrue);
    plain.openScope('s1', true);
    layout.finishFlow();
    plain.finishFlow();
    expect(layout.variantKeys, ['scope:s1'], reason: '선반 변형은 켠 그릇으로 켜지 않는다');
    expect(layout.variantsOn.where((v) => v.kind == VariantInfo.kindShelf), isEmpty);
    expect(visibleOrder(layout), [0, 2, 4, 1, 3], reason: '그릇 변형만 — 줄 2 · 4가 줄 0 아래로 모인다');
    expect(stackOf(layout), stackOf(plain), reason: '선반 변형이 없는 답과 줄 쌓기가 같다');
    expect([layout.isVisible(5), layout.isVisible(6)], [false, false]);
    expect(layout.variantGroups(0).single.rows, [2, 4], reason: '왼쪽 칸의 가지도 그릇 변형의 것 하나뿐');
    expect(layout.scopeStateOf('s1'), ScopeState.open);
    expect(layout.scopeUidOfRow(2), 's1');

    // 끄면 다시 같다.
    layout.openScope('s1', false);
    plain.openScope('s1', false);
    layout.finishFlow();
    plain.finishFlow();
    expect(stackOf(layout), stackOf(plain));
  });

  test('선반 변형을 읽는다 — kind · uid · 빠지는 줄 · 새 줄 · 숨긴 구성원(shelf)의 차례', () {
    final layout = SceneLayout.fromJson(shelfSkeleton())..reduceMotion = true;
    final shelf = layout.variants.singleWhere((v) => v.kind == VariantInfo.kindShelf);
    expect([shelf.id, shelf.key, shelf.kind, shelf.uid, shelf.track], [2, 'shelf:s1', 6, 's1', 1]);
    // 빠지는 줄: after −2 · ord −1(옮겨 간 판 줄 없음).
    final gone = [for (final r in shelf.rows) if (r.gone) r];
    expect([for (final r in gone) r.row], [2, 4]);
    expect([for (final r in gone) r.ord], [-1, -1]);
    // 다시 지은 줄: 새 줄 5 · 6과 가지 뒤로 밀린 줄 1 · 3.
    expect([for (final r in shelf.rows) if (!r.gone) (r.row, r.after, r.isNew)], [(5, 0, true), (6, 5, true), (1, 6, false), (3, 1, false)]);
    expect(shelf.groups.single.key, '__scope:s1');
    expect(shelf.groups.single.rows, [5, 6]);
    // 숨긴 구성원: 답의 차례(= 그릇 안 차례) 그대로.
    expect([for (final m in shelf.shelf) m.uid], ['shelf/p-blackwater', 'shelf/p-namgang']);
    expect([for (final m in shelf.shelf) m.ord], [5, 6]);
    final first = shelf.shelf.first;
    expect([first.name, first.color, first.start, first.end], ['검은물 의병', 0x8a9a7b, -1051200, -525600]);
    // 다른 갈래 · 열쇠가 없는 답은 빈 목록.
    final scope = layout.variants.singleWhere((v) => v.kind == VariantInfo.kindScope);
    expect(scope.shelf, isEmpty);
    expect(SceneLayout.fromJson(skeleton()).variants.every((v) => v.shelf.isEmpty), isTrue);
  });

  test('선반 변형의 줄로 가려 해도 아무것도 켜지 않는다 — 같은 uid의 그릇을 대신 켜지 않는다', () {
    final layout = SceneLayout.fromJson(shelfSkeleton())..reduceMotion = true;
    expect(identical(layout.revealFor(5), layout.viewState), isTrue, reason: '선반을 켜지 않는 동안 그 줄은 없다');
    expect(layout.revealFor(5).openScopes, isEmpty);
    // 그릇 변형이 옮기는 기본 줄로 가는 길은 그대로다(그 줄은 늘 보이므로 바꿀 것이 없다).
    expect(identical(layout.revealFor(2), layout.viewState), isTrue);
  });

  // ── 선반 상태(과제 7 걸음 3 — 보기 기억 `shelvedScopes` · 엔진 선반 변형 켜기 · 발 19) ──────────

  /// 선반 시험 그릇을 [state]로 둔 배치(흐름은 끝까지).
  SceneLayout shelfAt(ScopeState state, {bool shelf = true, bool scopeNew = false}) {
    final layout = SceneLayout.fromJson(shelfSkeleton(shelf: shelf, scopeNew: scopeNew))..reduceMotion = true;
    layout.setViewState(layout.viewForScopeState('s1', state));
    layout.finishFlow();
    return layout;
  }

  test('선반: variantKeys에 shelf:s1이 있고 scope:s1은 없다 — 빠지는 줄 2 · 4는 쌓지 않고 새 줄 5 · 6을 가지로 쌓는다 · 폴더 발에 19가 더해진다', () {
    final open = shelfAt(ScopeState.open);
    final layout = shelfAt(ScopeState.shelf);
    expect(layout.viewState.openScopes, {'s1'});
    expect(layout.viewState.shelvedScopes, {'s1'});
    expect(layout.scopeStateOf('s1'), ScopeState.shelf);
    expect(layout.variantKeys, ['shelf:s1'], reason: '둘을 함께 켜지 않는다(계약 2-4절)');
    expect(layout.isShelfOn('s1'), isTrue);
    expect(open.isShelfOn('s1'), isFalse);
    // 빠지는 줄(after −2)은 쌓지 않는다 · 다시 지은 줄 5 · 6이 줄 0 아래 가지로 · 뒤로 밀린 줄 1 · 3은 그 뒤.
    expect(visibleOrder(open), [0, 2, 4, 1, 3]);
    expect(visibleOrder(layout), [0, 5, 6, 1, 3]);
    for (final r in [2, 4]) {
      expect([layout.isVisible(r), layout.rowTop(r)], [false, -1], reason: '줄 $r');
    }
    // 켠 그릇 = 선반 변형의 가지(묶음 줄 5 · 6 · 열쇠 `__scope:s1` · 깊이 0 · 숨은 구성원 둘).
    final on = layout.scopeOnOf('s1')!;
    expect([on.rows, on.keys, on.depth, on.shelf.length], [{5, 6}, ['__scope:s1'], 0, 2]);
    expect(open.scopeOnOf('s1')!.shelf, isEmpty);
    expect(layout.variantGroups(0).single.rows, [5, 6]);
    expect([layout.scopeUidOfRow(5), layout.scopeUidOfRow(6), layout.scopeUidOfRow(2)], ['s1', 's1', '']);
    expect([layout.shelfVariantOf('s1')!.key, layout.shelfOf('s1').length, layout.shelfOf('nope').length], ['shelf:s1', 2, 0]);
    // 가지의 첫 줄 5는 그릇 변형의 첫 줄 2와 같은 자리: 3 + 14(민족 경계) + 15(그릇의 줄) + 21(폴더 머리).
    expect(layout.geo(5).bandTop, 3 + 14 + 15 + G.folderHead);
    expect(layout.rowTop(5), open.rowTop(2));
    expect(layout.geo(6).bandTop, 3 + 15);
    // 가지 다음 줄 1: 3 + 5 + 폴더 발 7 + 선반 꼬리표 줄 19 — 그 아래는 19만큼 내려간다.
    expect(G.shelfH, 19);
    expect(layout.geo(1).bandTop, 3 + 5 + G.folderFoot + G.shelfH);
    expect(layout.rowTop(1), open.rowTop(1), reason: '발은 다음 줄의 위 틈에 든다');
    expect(layout.rowTop(1) + layout.geo(1).bandTop, open.rowTop(1) + open.geo(1).bandTop + G.shelfH);
    expect(layout.rowTop(3), open.rowTop(3) + G.shelfH);
    expect(layout.totalHeight, open.totalHeight + G.shelfH);
    // 그릇의 세로 자리도 함께: 아래 = 끝 줄 6의 끝 + 7 + 19 · 위는 그릇 변형과 같다.
    final span = layout.scopeSpanOf('s1')!;
    expect([span.first, span.last], [5, 6]);
    expect(span.top, open.scopeSpanOf('s1')!.top);
    expect(span.bottom, layout.rowTop(6) + layout.geo(6).height + G.folderFoot + G.shelfH);
    expect(span.bottom, open.scopeSpanOf('s1')!.bottom + G.shelfH);
    // 조감은 옛 테두리 — 19를 더하지 않는다(선반 변형은 그대로 켜 있다).
    layout.setConditions(layout.conditions.copyWith(density: 2));
    open.setConditions(open.conditions.copyWith(density: 2));
    layout.finishFlow();
    open.finishFlow();
    expect(layout.variantKeys, ['shelf:s1']);
    expect(layout.geo(1).bandTop, open.geo(1).bandTop);
    expect(layout.totalHeight, open.totalHeight);
  });

  test('선반 ↔ 펼침은 켠 변형이 바뀌어 모임(StackCause.variants)으로 다시 쌓는다 · 선반 기억만 바뀌어도 다시 쌓는다', () {
    final layout = shelfAt(ScopeState.open);
    final before = layout.stackVersion;
    expect(layout.setViewState(layout.viewForScopeState('s1', ScopeState.shelf)), isTrue);
    expect(layout.stackVersion, greaterThan(before));
    expect(layout.stackCause, StackCause.variants);
    expect(layout.setViewState(layout.viewForScopeState('s1', ScopeState.open)), isTrue);
    expect(layout.stackCause, StackCause.variants);
    expect(layout.variantKeys, ['scope:s1']);
  });

  test('선반: 가지의 접힘이 선반 기억을 이긴다 — 접은 동안은 그릇 변형을 접고, 펴면 선반으로 돌아온다', () {
    final layout = shelfAt(ScopeState.shelf);
    expect(layout.foldVariantGroup(0, '__scope:s1', true), isTrue);
    layout.finishFlow();
    expect(layout.scopeStateOf('s1'), ScopeState.closed);
    expect(layout.viewState.shelvedScopes, {'s1'}, reason: '가지 접기는 선반 기억을 건드리지 않는다');
    expect(layout.variantKeys, ['scope:s1'], reason: '접힌 동안은 선반 변형을 켜지 않는다');
    expect(layout.isShelfOn('s1'), isFalse);
    expect(visibleOrder(layout), [0, 2, 1, 3], reason: '그릇 변형의 가지(2 · 4)가 줄 2로 합쳐진다');
    expect(layout.scopeOnOf('s1')!.shelf, isEmpty);
    expect(layout.foldVariantGroup(0, '__scope:s1', false), isTrue);
    layout.finishFlow();
    expect(layout.scopeStateOf('s1'), ScopeState.shelf);
    expect(layout.variantKeys, ['shelf:s1']);
    // 차림표의 '접음'(viewForScopeState)은 선반 기억을 뺀다(미리보기 setScopeState와 같은 뜻) — 다시 펴면 펼침.
    final closed = layout.viewForScopeState('s1', ScopeState.closed);
    expect(closed.shelvedScopes, isEmpty);
    layout.setViewState(closed);
    expect(layout.scopeStateOf('s1'), ScopeState.closed);
    layout.foldVariantGroup(0, '__scope:s1', false);
    expect(layout.scopeStateOf('s1'), ScopeState.open);
  });

  test('선반 변형이 없는 그릇(구성원 다섯 이하)도 선반에 둘 수 있다 — 그림은 펼침과 같고 ✓만 선반', () {
    final open = shelfAt(ScopeState.open, shelf: false);
    final layout = shelfAt(ScopeState.shelf, shelf: false);
    expect(layout.scopeStateOf('s1'), ScopeState.shelf);
    expect(layout.viewState.shelvedScopes, {'s1'});
    expect(layout.variantKeys, ['scope:s1']);
    expect(layout.isShelfOn('s1'), isFalse);
    expect(layout.shelfVariantOf('s1'), isNull);
    expect(layout.scopeOnOf('s1')!.shelf, isEmpty);
    expect(stackOf(layout), stackOf(open), reason: '발 19도 없다');
  });

  test('네 상태 오감(viewForScopeState): 풀림 → 선반 → 펼침 → 선반 → 접힘 → 선반 → 풀림 · 필터 칩으로 끄고 켜도 선반 기억은 남는다', () {
    // 선반은 끝에 더했다 — 누름 자리 · 차림표의 번호(차례 + 1)는 1 펼침 · 2 접힘 · 3 풀림이 그대로이고 선반은 4.
    expect([for (final s in ScopeState.values) s.name], ['open', 'closed', 'loose', 'shelf']);
    expect([for (final s in ScopeState.values) s.spread], [true, false, false, true]);
    final layout = SceneLayout.fromJson(shelfSkeleton())..reduceMotion = true;
    final fold = layout.variantGroupKeyOf(0, '__scope:s1');
    void go(ScopeState s) {
      layout.setViewState(layout.viewForScopeState('s1', s));
      layout.finishFlow();
      expect(layout.scopeStateOf('s1'), s);
    }

    // 풀림 → 선반: 켜고 선반에 둔 값 하나(다시 쌓기 한 번).
    final shelved = layout.viewForScopeState('s1', ScopeState.shelf);
    expect([shelved.openScopes, shelved.shelvedScopes, shelved.foldedGroups], [{'s1'}, {'s1'}, <String>{}]);
    go(ScopeState.shelf);
    expect(layout.variantKeys, ['shelf:s1']);
    go(ScopeState.open);
    expect([layout.viewState.shelvedScopes, layout.variantKeys], [<String>{}, ['scope:s1']]);
    go(ScopeState.shelf);
    go(ScopeState.closed);
    expect([layout.viewState.shelvedScopes, layout.viewState.foldedGroups, layout.variantKeys], [<String>{}, {fold}, ['scope:s1']]);
    // 접힘 → 선반: 가지를 펴고 선반에 둔다.
    go(ScopeState.shelf);
    expect([layout.viewState.foldedGroups, layout.variantKeys], [<String>{}, ['shelf:s1']]);
    expect(layout.viewForScopeState('s1', ScopeState.shelf), layout.viewState, reason: '이미 선반이면 바뀌는 것이 없다');
    // 필터 칩(openScope)으로 끄고 켜면 선반 기억은 그대로 — 다시 켜면 선반(미리보기 toggleScope와 같음).
    expect(layout.openScope('s1', false), isTrue);
    expect([layout.scopeStateOf('s1'), layout.viewState.shelvedScopes, layout.variantKeys], [ScopeState.loose, {'s1'}, <String>[]]);
    expect(layout.openScope('s1', true), isTrue);
    expect([layout.scopeStateOf('s1'), layout.variantKeys], [ScopeState.shelf, ['shelf:s1']]);
    // 선반 → 풀림: 끄고 선반 기억도 뺀다.
    go(ScopeState.loose);
    expect([layout.viewState.openScopes, layout.viewState.shelvedScopes, layout.variantKeys], [<String>{}, <String>{}, <String>[]]);
  });

  test('가려는 곳 펴기: 켠 선반이 빼 둔 기본 줄로 가면 선반 → 펼침 · 선반이 대신하는 그릇 변형의 줄도 · 보이는 줄은 그대로', () {
    final layout = shelfAt(ScopeState.shelf);
    // 보이는 줄(다시 지은 줄 5 · 기본 줄 1)은 바꿀 것이 없다.
    expect(identical(layout.revealFor(5), layout.viewState), isTrue);
    expect(identical(layout.revealFor(1), layout.viewState), isTrue);
    // 빠지는 줄 2(숨은 구성원 · 다시 지은 줄로 떠난 구성원의 기본 줄 — 검색 · 상세 창이 주는 줄)로 가면 선반 기억만 뺀다.
    final next = layout.revealFor(2);
    expect([next.openScopes, next.shelvedScopes, next.foldedGroups], [{'s1'}, <String>{}, <String>{}]);
    expect(layout.setViewState(next), isTrue);
    layout.finishFlow();
    expect([layout.scopeStateOf('s1'), layout.variantKeys, layout.isVisible(2)], [ScopeState.open, ['scope:s1'], true]);
    // 그릇 변형에만 있는 새 줄 7 — 선반이 그 변형을 대신하는 동안은 없다. 그 줄로 가면 선반을 뺀다.
    final scoped = shelfAt(ScopeState.shelf, scopeNew: true);
    expect([scoped.variantKeys, scoped.isVisible(7)], [['shelf:s1'], false]);
    final back = scoped.revealFor(7);
    expect([back.openScopes, back.shelvedScopes], [{'s1'}, <String>{}]);
    scoped.setViewState(back);
    scoped.finishFlow();
    expect([scoped.variantKeys, scoped.isVisible(7)], [['scope:s1'], true]);
    expect(visibleOrder(scoped), [0, 2, 4, 7, 1, 3]);
  });

  // 포개짐(과제 7 걸음 3 ④ — 이번에 정함 · 감독 확인거리): 바깥 그릇 s2(줄 1 ~ 4 · 변형 1)와 그 안의 상자 s3(줄 3 · 4 · 변형 2 · within [1])에
  // 바깥 선반 변형(변형 3 · 줄 1 ~ 4를 빼고 새 줄 7 · 8 · 9 · 숨은 구성원 하나)과 안쪽 선반 변형(변형 4 · 줄 3 · 4를 빼고 새 줄 10 · 숨은 구성원 하나)을 더했다.
  Map<String, dynamic> nestShelfSkeleton() {
    final json = nestSkeleton();
    final track = (json['tracks'] as List)[0] as Map;
    track['rows'] = [...track['rows'] as List, row(7, variant: 3), row(8, variant: 3), row(9, variant: 3), row(10, variant: 4)];
    Map<String, dynamic> member(String uid) => {'uid': uid, 'name': uid, 'color': 0x8a9a7b, 'start': 0, 'end': 525600, 'ord': 5};
    json['variants'] = [
      ...json['variants'] as List,
      {
        'id': 3, 'key': 'shelf:s2', 'kind': 6, 'track': 1, 'band': 0, 'uid': 's2', 'name': 's2',
        'rows': [
          for (final r in [1, 2, 3, 4]) {'row': r, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 7, 'after': 0, 'ord': 0, 'new': 1, 'scope_pad': 16, 'group_start': 1},
          {'row': 8, 'after': 7, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
          {'row': 9, 'after': 8, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
          {'row': 5, 'after': 9, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s2', 'depth': 0, 'name': 's2', 'color': 0xd4a39b, 'kind': 2, 'rows': [7, 8, 9]},
        ],
        'shelf': [member('m-outer')],
      },
      {
        'id': 4, 'key': 'shelf:s3', 'kind': 6, 'track': 1, 'band': 0, 'uid': 's3', 'name': 's3',
        'rows': [
          for (final r in [3, 4]) {'row': r, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 10, 'after': 2, 'ord': 0, 'new': 1, 'scope_pad': 16, 'group_start': 1},
          {'row': 5, 'after': 10, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s3', 'depth': 0, 'name': 's3', 'color': 0xd4a39b, 'kind': 2, 'rows': [10]},
        ],
        'shelf': [member('m-inner')],
      },
    ];
    return json;
  }

  test('포개짐: 바깥 그릇이 선반이면 그 안의 켠 그릇은 켜지 않는다 — 안쪽 켬 기억은 남아 선반을 풀면 돌아온다', () {
    final layout = SceneLayout.fromJson(nestShelfSkeleton())..reduceMotion = true;
    layout.openScope('s2', true);
    layout.openScope('s3', true);
    expect(layout.variantKeys, ['scope:s2', 'scope:s3']);
    layout.setViewState(layout.viewForScopeState('s2', ScopeState.shelf));
    layout.finishFlow();
    expect(layout.variantKeys, ['shelf:s2'], reason: '바깥 선반 변형이 안쪽 구성원까지 숨기고 줄을 다시 지었다');
    expect(visibleOrder(layout), [0, 7, 8, 9, 5, 6]);
    expect(layout.scopeOnOf('s3'), isNull);
    expect([layout.viewState.openScopes, layout.scopeStateOf('s3'), layout.scopeStateOf('s2')], [{'s2', 's3'}, ScopeState.open, ScopeState.shelf]);
    expect(layout.scopeDepthOf('s2'), 0);
    expect(layout.geo(5).bandTop, 3 + 5 + G.folderFoot + G.shelfH);
    // 빠지는 줄(안쪽 구성원의 기본 줄 3)로 가면 바깥 선반을 펼침으로 — 안쪽 그릇이 돌아온다.
    layout.setViewState(layout.revealFor(3));
    layout.finishFlow();
    expect(layout.variantKeys, ['scope:s2', 'scope:s3']);
    expect([layout.scopeDepthOf('s2'), layout.scopeDepthOf('s3')], [0, 1]);
    expect(visibleOrder(layout), [0, 1, 2, 3, 4, 5, 6]);
  });

  test('포개짐: 켠 바깥 그릇 안의 그릇은 선반이어도 선반 변형을 켜지 않는다(✓만 선반) — 바깥이 풀리면 제 선반 변형을 깊이 0으로 켠다', () {
    final layout = SceneLayout.fromJson(nestShelfSkeleton())..reduceMotion = true;
    layout.openScope('s2', true);
    layout.setViewState(layout.viewForScopeState('s3', ScopeState.shelf));
    layout.finishFlow();
    expect(layout.scopeStateOf('s3'), ScopeState.shelf);
    expect(layout.variantKeys, ['scope:s2', 'scope:s3'], reason: '선반 변형은 그 그릇만 켠 배치라 바깥 변형과 섞지 않는다');
    expect(layout.isShelfOn('s3'), isFalse);
    expect(layout.scopeDepthOf('s3'), 1);
    expect(layout.scopeOnOf('s3')!.shelf, isEmpty);
    // 바깥을 풀면 안쪽 선반 변형이 켜진다 — 깊이는 같은 uid의 그릇 변형의 within(바깥 변형 1 — 꺼짐)으로 세어 0.
    layout.setViewState(layout.viewForScopeState('s2', ScopeState.loose));
    layout.finishFlow();
    expect(layout.variantKeys, ['shelf:s3']);
    expect(layout.scopeOnOf('s3')!.within, [1]);
    expect(layout.scopeDepthOf('s3'), 0);
    expect(visibleOrder(layout), [0, 1, 2, 10, 5, 6]);
    expect(layout.geo(5).bandTop, 3 + 5 + G.folderFoot + G.shelfH, reason: '폴더(깊이 0)의 발 7 + 19');
    // 둘 다 선반이면 바깥만 선반 변형 — 안쪽은 ②(켠 바깥 안)로 선반 변형을 켜지 않고 ③(선반인 바깥 안)으로 그릇 변형도 켜지 않는다.
    layout.setViewState(layout.viewForScopeState('s2', ScopeState.shelf));
    layout.finishFlow();
    expect(layout.variantKeys, ['shelf:s2']);
    expect([layout.scopeStateOf('s2'), layout.scopeStateOf('s3')], [ScopeState.shelf, ScopeState.shelf]);
  });

  // ── 선반 × 펼친 상국(remake-4-int 검토 고침 — 선반이 이긴다 · 펼치려 하면 선반을 뺀다) ──────────
  // 선반 시험 그릇 s1의 줄 2를 상국 띠 7의 줄로 두고 소속 펼치기 `host:p/h`(변형 3 · 새 줄 7이 줄 2 아래 · 줄 4는 그 뒤로)를,
  // 줄 4를 나라 띠 9의 줄로 두고 단체 펼치기 `groups:p/k`(변형 4 · 새 줄 8이 줄 4 아래)를 더했다. 선반 변형은 줄 2 · 4를 빼므로(숨은 구성원 ·
  // 다시 지은 줄로 옮겨 간 구성원) 두 펼치기 모두 매달릴 줄이 없다 — 예전에는 소속 줄 7이 트랙 끝에 붙고 그 위에 깊이 0 소속 폴더가 그릇 밖에 섰다.
  Map<String, dynamic> heldSkeleton() {
    final json = shelfSkeleton();
    final track = (json['tracks'] as List)[0] as Map;
    track['rows'] = [...track['rows'] as List, row(7, kind: 1, variant: 3), row(8, kind: 1, variant: 4)];
    json['variants'] = [
      ...json['variants'] as List,
      {
        'id': 3, 'key': 'host:p/h', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '시험 상국',
        'rows': [
          {'row': 7, 'after': 2, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
          {'row': 4, 'after': 7, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': <dynamic>[],
      },
      {
        'id': 4, 'key': 'groups:p/k', 'kind': 5, 'track': 1, 'band': 9, 'uid': '', 'name': '시험 나라',
        'rows': [
          {'row': 8, 'after': 4, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': <dynamic>[],
      },
    ];
    return json;
  }

  test('선반 × 펼친 상국: 선반이 상국 줄을 빼 두면 소속 펼치기를 켜지 않는다 — 소속 줄 · 소속 폴더가 트랙 끝에 따로 서지 않고, 펼친 기억은 남아 선반을 풀면 돌아온다', () {
    final layout = SceneLayout.fromJson(heldSkeleton())..reduceMotion = true;
    // 펼침 + 소속 펼침: 소속 폴더(줄 2 · 7 — 그릇 안의 상국이라 깊이 1 상자)를 그릇 s1이 품는다.
    layout.setViewState(layout.viewForScopeState('s1', ScopeState.open, layout.viewForHostExpanded(7, true)));
    layout.finishFlow();
    expect(layout.variantKeys, ['scope:s1', 'host:p/h']);
    expect(visibleOrder(layout), [0, 2, 7, 4, 1, 3]);
    final folder = layout.scopeOnOf('host:p/h')!;
    expect([folder.rows, folder.depth, layout.hostFolderRowOf('host:p/h'), layout.scopeOnOf('s1')!.rows], [{2, 7}, 1, 2, {2, 4, 7}]);
    expect([layout.isHostExpanded(7), layout.expandedHostsShown], [true, {7}]);

    // 선반에 둔다: 선반 변형이 상국 줄 2를 빼므로 소속 펼치기는 켜지 않는다(선반이 이김) — 소속 줄 7은 쌓지 않고 소속 폴더도 없다.
    layout.setViewState(layout.viewForScopeState('s1', ScopeState.shelf));
    layout.finishFlow();
    expect(layout.variantKeys, ['shelf:s1']);
    expect(visibleOrder(layout), [0, 5, 6, 1, 3], reason: '예전에는 [0, 5, 6, 1, 3, 7] — 소속 줄이 트랙 끝에');
    expect(stackOf(layout), stackOf(shelfAt(ScopeState.shelf)), reason: '소속을 펼치지 않은 선반과 줄 쌓기가 같다');
    expect([layout.isVisible(7), layout.scopeOnOf('host:p/h'), layout.hostFolderRowOf('host:p/h')], [false, null, -1]);
    expect([for (final s in layout.scopesOn) s.uid], ['s1'], reason: '그릇 밖의 깊이 0 소속 폴더가 없다');
    expect(layout.scopeOnOf('s1')!.rows, {5, 6});
    // 펼친 기억은 그대로 — 단추 · 매달린 이름표의 밭(expandedHostsShown)과 isHostExpanded는 접힌 꼴(선반 안 상국 띠의 소속 단추는 ▸).
    expect(layout.viewState.expandedHosts, {7});
    expect([layout.isHostExpanded(7), layout.expandedHostsShown], [false, <int>{}]);

    // 선반을 풀면(펼침) 소속 펼치기가 돌아온다.
    layout.setViewState(layout.viewForScopeState('s1', ScopeState.open));
    layout.finishFlow();
    expect(layout.variantKeys, ['scope:s1', 'host:p/h']);
    expect(visibleOrder(layout), [0, 2, 7, 4, 1, 3]);
    expect([layout.hostFolderRowOf('host:p/h'), layout.scopeOnOf('host:p/h')!.depth], [2, 1]);
  });

  test('선반 × 펼친 상국: 선반 그릇 안에서 소속 · 단체를 펼치면(단추 · 가려는 곳 펴기) 그 선반을 뺀다 · 기억에서 함께 켜도 선반이 이긴다', () {
    final layout = SceneLayout.fromJson(heldSkeleton())..reduceMotion = true;
    layout.setViewState(layout.viewForScopeState('s1', ScopeState.shelf));
    layout.finishFlow();
    // 소속 단추(앱 틀 `_toggleVariant`와 같은 꼴): 선반 → 펼침과 소속 펼침을 한 값으로(다시 쌓기 한 번).
    final next = layout.viewForHostExpanded(7, !layout.isHostExpanded(7));
    expect([next.expandedHosts, next.openScopes, next.shelvedScopes], [{7}, {'s1'}, <String>{}]);
    // 접을 때와 선반이 줄을 빼지 않는 띠는 선반을 건드리지 않는다.
    expect(layout.viewForHostExpanded(7, false).shelvedScopes, {'s1'});
    expect(layout.viewForHostExpanded(99, true).shelvedScopes, {'s1'});

    // 기억에서 둘을 함께 켜면(보기 기억 · DLC 다시 읽기) 선반이 이긴다 — 단추는 ▸라 누르면 위처럼 선반을 뺀다.
    layout.setViewState(layout.viewState.withHostExpanded(7, true).withGroupsExpanded(9, true));
    layout.finishFlow();
    expect(layout.variantKeys, ['shelf:s1']);
    expect(visibleOrder(layout), [0, 5, 6, 1, 3]);
    expect([layout.isHostExpanded(7), layout.isGroupsExpanded(9), layout.expandedHostsShown], [false, false, <int>{}]);
    final press = layout.viewForHostExpanded(7, !layout.isHostExpanded(7));
    expect([press.expandedHosts, press.shelvedScopes], [{7}, <String>{}]);
    final groups = layout.viewForGroupsExpanded(9, !layout.isGroupsExpanded(9));
    expect([groups.expandedGroups, groups.shelvedScopes], [{9}, <String>{}]);

    // 가려는 곳 펴기: 소속 줄 7로 가면 선반을 뺀다(펼친 기억은 그대로).
    final reveal = layout.revealFor(7);
    expect([reveal.expandedHosts, reveal.openScopes, reveal.shelvedScopes], [{7}, {'s1'}, <String>{}]);
    layout.setViewState(reveal);
    layout.finishFlow();
    expect(layout.variantKeys, ['scope:s1', 'host:p/h', 'groups:p/k']);
    expect([layout.isVisible(7), layout.isVisible(8), layout.isHostExpanded(7), layout.isGroupsExpanded(9), layout.expandedHostsShown], [true, true, true, true, {7}]);
  });

  // 선반이 상국 줄을 빼지 않을 때(상국이 제 기본 줄에 남는 구성원 · 그릇 밖의 상국): 실제 선반 변형은 남는 구성원의 기본 줄을 그대로 두고
  // 그 뒤 줄을 다시 매단다(f4-federation-scope 줄 9 after 5 · lantern+shelf-flat 줄 1 after 0 — 정답지). 그 기록이 소속 펼치기의 기록과 같은 줄을
  // 다투면 소속 줄은 사슬 끝으로 밀리지만, 소속 폴더도 켠 그릇이라 그 줄을 상국 줄 밑에 한 덩이로 모은다(`_gathered`).
  // 줄 0 ~ 5 기본 · 6 소속 줄(변형 1). 그릇 s1(변형 2 · 줄 1 ~ 3) · 선반 변형(3)은 줄 2를 빼고(숨은 구성원) 줄 3을 줄 1 뒤에 다시 매단다.
  // [inside]면 상국 띠 7이 줄 1(그릇 안 · 선반에도 남음 — 소속 줄 6이 줄 1 밑 · 줄 2가 그 뒤), 아니면 줄 0(그릇 밖 — 소속 줄 6이 줄 0 밑 · 줄 1이 그 뒤).
  // 번호는 실제 내보내기처럼 소속 < 그릇 < 선반(대범위가 소속을 이기고 선반은 변형 목록의 끝).
  Map<String, dynamic> keptSkeleton({required bool inside}) => {
    'packs': [
      {'id': 1, 'name': '검사 자료집', 'events': 0},
    ],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xd7bf8e,
        'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
        'rows': [for (int i = 0; i < 6; i++) row(i), row(6, kind: 1, variant: 1)],
      },
    ],
    'epochs': <dynamic>[],
    'variants': [
      {
        'id': 1, 'key': 'host:p/h', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '시험 상국',
        'rows': [
          {'row': 6, 'after': inside ? 1 : 0, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
          {'row': inside ? 2 : 1, 'after': 6, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
        ],
        'groups': <dynamic>[],
      },
      {
        'id': 2, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '선반 시험 그릇',
        'rows': [
          {'row': 1, 'after': 0, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
          {'row': 4, 'after': 3, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s1', 'depth': 0, 'name': '선반 시험 그릇', 'color': 0xd1a8b9, 'kind': 2, 'rows': [1, 2, 3]},
        ],
        'within': <int>[],
      },
      {
        'id': 3, 'key': 'shelf:s1', 'kind': 6, 'track': 1, 'band': 0, 'uid': 's1', 'name': '선반 시험 그릇',
        'rows': [
          {'row': 2, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 1, 'after': 0, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
          {'row': 3, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          {'row': 4, 'after': 3, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s1', 'depth': 0, 'name': '선반 시험 그릇', 'color': 0xd1a8b9, 'kind': 2, 'rows': [1, 3]},
        ],
        'shelf': [
          {'uid': 'shelf/p-blackwater', 'name': '검은물 의병', 'color': 0x8a9a7b, 'start': -1051200, 'end': -525600, 'ord': 5},
        ],
      },
    ],
  };

  test('선반 × 펼친 상국: 상국이 선반 그릇 안 제 줄에 남으면 소속 폴더는 그 안의 상자(깊이 1) — 선반이 상국 줄 뒤에 다시 매단 줄보다 소속 줄이 먼저(한 덩이)', () {
    final layout = SceneLayout.fromJson(keptSkeleton(inside: true))..reduceMotion = true;
    // 펼침: 그릇이 소속 폴더(줄 1 · 6)까지 품는다.
    layout.setViewState(layout.viewForScopeState('s1', ScopeState.open, layout.viewForHostExpanded(7, true)));
    layout.finishFlow();
    expect(layout.variantKeys, ['host:p/h', 'scope:s1']);
    expect(visibleOrder(layout), [0, 1, 6, 2, 3, 4, 5]);
    expect([layout.scopeOnOf('host:p/h')!.rows, layout.scopeOnOf('host:p/h')!.depth, layout.scopeOnOf('s1')!.rows], [{1, 6}, 1, {1, 2, 3, 6}]);

    // 선반: 상국 줄 1은 빠지지 않으므로 선반이 잡지 않는다(소속 펼치기 · 소속 폴더가 선반과 함께 켜진다).
    // 사슬만으로는 [0, 1, 3, 4, 5, 6](줄 3이 줄 1 뒤를 차지해 소속 줄이 끝으로) — 선반 그릇과 소속 폴더가 한 덩이로 모아 줄 1 밑에 둔다.
    layout.setViewState(layout.viewForScopeState('s1', ScopeState.shelf));
    layout.finishFlow();
    expect(layout.variantKeys, ['host:p/h', 'shelf:s1']);
    expect([layout.isHostExpanded(7), layout.expandedHostsShown], [true, {7}]);
    expect(visibleOrder(layout), [0, 1, 6, 3, 4, 5]);
    final folder = layout.scopeOnOf('host:p/h')!;
    expect([folder.rows, folder.depth, layout.hostFolderRowOf('host:p/h')], [{1, 6}, 1, 1], reason: '선반 그릇 안의 상자');
    expect(layout.scopeOnOf('s1')!.rows, {1, 3, 6}, reason: '선반 그릇이 소속 줄까지 품는다(그릇 밖으로 나가지 않음)');
    expect([for (final s in layout.scopesOn) s.uid], ['s1', 'host:p/h']);
    expect(layout.isShelfOn('s1'), isTrue);
    final span = layout.scopeSpanOf('s1')!, box = layout.scopeSpanOf('host:p/h')!;
    expect([span.first, span.last, box.first, box.last], [1, 3, 1, 6], reason: '소속 상자는 선반 그릇 안 · 그릇의 끝 줄은 줄 3');
    expect(box.bottom, lessThanOrEqualTo(layout.rowTop(3) + layout.geo(3).bandTop - layout.tabOf(3)), reason: '줄 3의 띠는 소속 상자 밖(아래 — 상자 발은 줄 3의 위 틈에 든다)');
  });

  test('선반 × 펼친 상국: 그릇 밖의 상국은 깊이 0 폴더 — 선반이 그 뒤 줄을 다시 매달아도 소속 줄은 상국 줄 바로 밑 · 선반 그릇은 넓히지 않는다', () {
    final layout = SceneLayout.fromJson(keptSkeleton(inside: false))..reduceMotion = true;
    for (final state in [ScopeState.open, ScopeState.shelf]) {
      layout.setViewState(layout.viewForScopeState('s1', state, layout.viewForHostExpanded(7, true)));
      layout.finishFlow();
      expect(layout.variantKeys, ['host:p/h', state == ScopeState.shelf ? 'shelf:s1' : 'scope:s1'], reason: state.name);
      // 그릇 기록(줄 1 after 0)이 소속 기록(줄 1 after 6)을 이겨 사슬만으로는 소속 줄 6이 끝 — 소속 폴더 덩이가 줄 0 밑으로 모은다.
      expect(visibleOrder(layout), state == ScopeState.shelf ? [0, 6, 1, 3, 4, 5] : [0, 6, 1, 2, 3, 4, 5], reason: state.name);
      final folder = layout.scopeOnOf('host:p/h')!;
      expect([folder.rows, folder.depth, layout.hostFolderRowOf('host:p/h')], [{0, 6}, 0, 0], reason: state.name);
      expect(layout.scopeOnOf('s1')!.rows, state == ScopeState.shelf ? {1, 3} : {1, 2, 3}, reason: '${state.name}: 상국 줄을 품지 않는 그릇은 그대로');
    }
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
    // 실측(9.6절)은 소속 폴더(4단계 과제 8 걸음 2) 전의 꼴 — 스위치 folder를 끄고 견준다.
    PaintPick.folder = false;
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
    PaintPick.reset();
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
