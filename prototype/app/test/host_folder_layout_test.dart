import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 소속 폴더의 쌓기(리메이크 4단계 과제 8 걸음 2 · 스위치 folder — layout.dart `_hostFolders`): 켠 소속 펼치기 변형(kind 1)마다 '소속 폴더'가
// 켠 그릇(uid = 변형 열쇠 `host:…` · 늘 펼침)으로 서서 머리 21 · 발 7 · 줄 위 틈 + 10이 그릇과 같은 길로 붙고, 소속 줄의 틈이 그릇 안 줄과 같아진다.
// 그릇 안의 상국 · 포갠 소속은 깊이 1(상자) — 바깥 그릇이 소속 줄까지 품는다. 조감 · 집합 보기 판 · 스위치 끔이면 쌓기가 예전과 같다.
//
// 뼈대: 트랙 하나(줄 0 ~ 3 기본) · 상국 띠 7(줄 1)의 소속 펼치기 h1(새 줄 4 · 5 — 줄 2는 그 뒤로) ·
// 소속 줄 5에 선 상국 띠 8의 소속 펼치기 h2(새 줄 6 — 포갠 소속 · 엔진 답에는 아직 없는 꼴을 손으로) · 그릇 s1(줄 1 · 3 — 상국 줄을 품음) ·
// 그릇 s2(줄 3 — 상국 줄을 품지 않음). 집합 보기 판은 트랙 2(줄 7).

Map<String, dynamic> row(int id, {int kind = 0, int variant = 0}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': kind, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': variant,
};

Map<String, dynamic> vrow(int row, int after, {bool fresh = false, int pad = 0, bool start = false}) =>
    {'row': row, 'after': after, 'ord': 0, 'new': fresh ? 1 : 0, 'scope_pad': pad, 'group_start': start ? 1 : 0};

Map<String, dynamic> skeleton() => {
  'packs': [
    {'id': 1, 'name': '검사 자료집', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '솔뫼', 'color': 0xa0bcc5,
      'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
      'rows': [row(0), row(1), row(2), row(3), row(4, kind: 1, variant: 1), row(5, kind: 1, variant: 1), row(6, kind: 1, variant: 3)],
    },
    {
      'id': 2, 'pack': 1, 'ord': 1, 'name': '판', 'color': 0xbcd8c1,
      'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
      'rows': [row(7, variant: 5)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
  'variants': [
    {
      'id': 1, 'key': 'host:p/h1', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '철령 제후 연방',
      'rows': [vrow(4, 1, fresh: true), vrow(5, 4, fresh: true), vrow(2, 5)],
      'groups': <dynamic>[],
    },
    {
      'id': 2, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '바위골 할거',
      'rows': [vrow(1, 0, pad: 16, start: true), vrow(3, 1), vrow(2, 3, pad: 6)],
      'groups': [
        {'key': '__scope:s1', 'depth': 0, 'name': '바위골 할거', 'color': 0xc0b4a3, 'kind': 2, 'rows': [1, 3]},
      ],
      'within': <int>[],
    },
    {
      'id': 3, 'key': 'host:p/h2', 'kind': 1, 'track': 1, 'band': 8, 'uid': '', 'name': '검은솔 대공국',
      'rows': [vrow(6, 5, fresh: true), vrow(2, 6)],
      'groups': <dynamic>[],
    },
    {
      'id': 4, 'key': 'scope:s2', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's2', 'name': '해성 할거',
      'rows': [vrow(3, 0, pad: 16, start: true), vrow(1, 3, pad: 6)],
      'groups': [
        {'key': '__scope:s2', 'depth': 0, 'name': '해성 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [3]},
      ],
      'within': <int>[],
    },
    {
      'id': 5, 'key': 'view:b1', 'kind': 3, 'track': 2, 'band': 0, 'uid': 'b1', 'name': '세 나라 판',
      'rows': [vrow(7, -1, fresh: true, pad: 16, start: true)],
      'groups': <dynamic>[],
    },
  ],
};

/// [folder]는 스위치 — 배치를 지을 때 한 번 읽는다.
SceneLayout build({bool folder = true}) {
  PaintPick.folder = folder;
  final out = SceneLayout.fromJson(skeleton())..reduceMotion = true;
  PaintPick.reset();
  return out;
}

List<int> visibleOrder(SceneLayout layout) {
  final rows = [for (int r = 0; r < layout.rowCount; r++) if (layout.isVisible(r)) r];
  rows.sort((a, b) => layout.rowTop(a).compareTo(layout.rowTop(b)));
  return rows;
}

/// 보이는 줄의 차례 · 줄마다 (위 자리 · 높이 · 띠 위 틈) · 트랙 자리 · 전체 높이 — 쌓기가 같은지 견준다.
List<Object> stackOf(SceneLayout layout) => [
  visibleOrder(layout),
  for (int r = 0; r < layout.rowCount; r++) [layout.rowTop(r), if (layout.isVisible(r)) ...[layout.geo(r).height, layout.geo(r).bandTop, layout.tabOf(r)]],
  for (int t = 0; t < layout.tracks.length; t++) [layout.trackTop(t), layout.trackHeight(t)],
  layout.totalHeight,
];

void main() {
  tearDown(PaintPick.reset);
  const h1 = 'host:p/h1', h2 = 'host:p/h2';

  test('소속을 펼치면 소속 폴더가 선다 — 줄 높이 = 예전 + 머리 21 · 발 7 · 줄 위 틈 10(셋) · 소속 줄 틈 3 − 1(둘)', () {
    final on = build(), off = build(folder: false);
    for (final l in [on, off]) {
      expect(l.expandHost(7, true), isTrue);
    }
    expect(visibleOrder(on), [0, 1, 4, 5, 2, 3], reason: '줄 차례는 그대로');
    expect(visibleOrder(off), [0, 1, 4, 5, 2, 3]);
    final f = on.scopeOnOf(h1)!;
    expect([f.rows, f.depth, f.keys], [{1, 4, 5}, 0, isEmpty], reason: '상국 줄(첫 줄) + 새 줄 · 바깥 폴더 · 접기 열쇠 없음');
    expect(on.hostFolderRowOf(h1), 1);
    expect(on.scopeStateOf(h1), ScopeState.open, reason: '소속 폴더는 늘 펼침');
    expect(on.scopesOn.map((s) => s.uid), [h1]);
    expect(off.scopeOnOf(h1), isNull, reason: '스위치를 끄면 소속 폴더가 없다');
    expect(off.scopesOn, isEmpty);
    // 상국 줄: 틈 3 + 줄 위 틈 5 + 그릇의 줄 10 + 폴더 머리 21.
    expect([off.geo(1).bandTop, on.geo(1).bandTop], [3 + 5, 3 + 5 + 10 + 21]);
    // 소속 줄: 소속 틈 1 → 그릇 안 줄과 같은 줄 사이 틈 3 · 그릇의 줄 10.
    for (final r in [4, 5]) {
      expect([off.geo(r).bandTop, on.geo(r).bandTop], [1 + 5, 3 + 5 + 10], reason: '줄 $r');
    }
    // 폴더 뒤 첫 줄: 폴더 발 7.
    expect([off.geo(2).bandTop, on.geo(2).bandTop], [3 + 5, 3 + 5 + 7]);
    expect(on.geo(3).bandTop, off.geo(3).bandTop, reason: '그 뒤 줄은 그대로');
    expect(on.totalHeight - off.totalHeight, 21 + 7 + 3 * 10 + 2 * 2);
    // 폴더의 세로 자리 = 상국 띠 윗변 − 위 틈 − 머리 ~ 마지막 소속 줄 끝 + 발.
    final span = on.scopeSpanOf(h1)!;
    expect([span.first, span.last], [1, 5]);
    expect(span.top, on.rowTop(1) + on.geo(1).bandTop - on.tabOf(1) - G.folderHead);
    expect(span.bottom, on.rowTop(5) + on.geo(5).height + G.folderFoot);
    expect(span.bottom, on.rowTop(2) + G.folderFoot, reason: '폴더 발은 다음 줄 몫의 맨 위(그 뒤에 줄 사이 틈 3 · 위 틈 5)');
    // 접으면 예전과 같다.
    for (final l in [on, off]) {
      expect(l.expandHost(7, false), isTrue);
    }
    expect(stackOf(on), stackOf(off));
    expect(on.scopeOnOf(h1), isNull);
    expect(on.scopeStateOf(h1), ScopeState.open, reason: '소속 폴더 uid는 늘 펼침으로 읽는다(그리는 쪽은 켠 것만 묻는다)');
  });

  test('소속 폴더는 그릇 상태로 바꾸지 않는다 — 왼쪽 칸 폴더 줄 누름이 와도 보기 상태 그대로', () {
    final on = build()..expandHost(7, true);
    for (final s in ScopeState.values) {
      expect(identical(on.viewForScopeState(h1, s), on.viewState), isTrue, reason: s.name);
    }
    expect(on.viewState.openScopes, isEmpty);
  });

  test('조감 · 스위치 끔이면 쌓기가 예전과 같다 — 조감을 드나들면 소속 폴더가 없어졌다 돌아온다', () {
    final on = build(), off = build(folder: false);
    for (final l in [on, off]) {
      l.expandHost(7, true);
      expect(l.setConditions(l.conditions.copyWith(density: 2)), isTrue);
    }
    expect(on.scopeOnOf(h1), isNull, reason: '조감에는 소속 폴더가 없다');
    expect(stackOf(on), stackOf(off));
    final normal = build()..expandHost(7, true);
    expect(on.setConditions(on.conditions.copyWith(density: 0)), isTrue);
    expect(on.scopeOnOf(h1)?.rows, {1, 4, 5}, reason: '조감에서 나오면 다시 선다');
    expect(stackOf(on), stackOf(normal));
    // 자동 조감도 같은 길(조감 값 bird).
    on.setConditions(on.conditions.copyWith(autoBird: true));
    off.setConditions(off.conditions.copyWith(density: 0, autoBird: true));
    expect(on.scopeOnOf(h1), isNull);
    expect(stackOf(on), stackOf(off));
  });

  test('집합 보기 판을 켠 동안은 소속 폴더가 없다 — 판 밖 트랙을 펴도 쌓기가 예전과 같다', () {
    final on = build(), off = build(folder: false);
    for (final l in [on, off]) {
      l.expandHost(7, true);
      expect(l.setBoard('view:b1'), isTrue);
      expect(l.setViewState(l.withTrackFoldedState(1, false)), isTrue);
    }
    expect(on.board?.key, 'view:b1');
    expect(on.isVisible(4), isTrue, reason: '판 밖 트랙을 폈다');
    expect(on.scopeOnOf(h1), isNull);
    expect(stackOf(on), stackOf(off));
    for (final l in [on, off]) {
      l.setBoard('');
    }
    expect(on.scopeOnOf(h1)?.depth, 0, reason: '판을 끄면 다시 선다');
  });

  test('그릇 안의 상국은 상자(깊이 1) — 그릇이 소속 줄까지 품어 소속 줄이 그릇 밖으로 나가지 않고 그릇의 발이 그 뒤에 선다', () {
    final on = build(), off = build(folder: false);
    for (final l in [on, off]) {
      l.expandHost(7, true);
      l.openScope('s1', true);
    }
    // 예전: 그릇(줄 1 · 3)이 한 덩이로 모이며 소속 줄 4 · 5가 그릇 밖(줄 2 뒤)으로 밀려났다.
    expect(visibleOrder(off), [0, 1, 3, 2, 4, 5]);
    expect(visibleOrder(on), [0, 1, 4, 5, 3, 2], reason: '상국 줄 바로 밑에 소속 줄 — 그 뒤에 그릇의 나머지 줄');
    expect(on.scopeOnOf(h1)!.depth, 1);
    expect(on.scopeDepthOf(h1), 1);
    expect(on.scopeOnOf('s1')!.rows, {1, 3, 4, 5}, reason: '그릇이 소속 폴더의 줄을 품는다');
    expect(on.scopeOnOf('s1')!.depth, 0);
    // 상국 줄: 틈 3 + 민족 경계 14 + 위 틈 5 + 10 + 폴더 머리 21 + 상자 머리 24([G.boxHead] — 과제 7 걸음 2 · 예전 20).
    expect(on.geo(1).bandTop, 3 + 14 + 5 + 10 + G.folderHead + G.boxHead);
    // 상자 뒤 그릇 줄 3: 상자 발 7 · 그릇 줄 2: 폴더 발 7(그릇의 줄이 아니라 위 틈 10 없음).
    expect(on.geo(3).bandTop, 3 + 5 + 10 + G.boxFoot);
    expect(on.geo(2).bandTop, 3 + 5 + G.folderFoot);
    final box = on.scopeSpanOf(h1)!, folder = on.scopeSpanOf('s1')!;
    expect([box.first, box.last, folder.first, folder.last], [1, 5, 1, 3]);
    expect(box.top - folder.top, G.folderHead, reason: '상자 뚜껑은 폴더 머리 밑');
    expect(folder.bottom - (on.rowTop(3) + on.geo(3).height), G.folderFoot);
    expect(box.bottom, lessThan(folder.bottom));
    // 그릇을 접으면 소속 폴더를 두지 않는다 — 예전과 같다(접힌 그릇 안의 꼴은 걸음 3).
    for (final l in [on, off]) {
      expect(l.foldVariantGroup(0, '__scope:s1', true), isTrue);
    }
    expect(on.scopeOnOf(h1), isNull);
    expect(on.scopeOnOf('s1')!.rows, {1, 3}, reason: '접힌 그릇은 넓히지 않는다');
    expect(stackOf(on), stackOf(off));
    // 다시 펴면 상자가 돌아온다.
    on.foldVariantGroup(0, '__scope:s1', false);
    expect(on.scopeOnOf(h1)!.depth, 1);
    expect(visibleOrder(on), [0, 1, 4, 5, 3, 2]);
  });

  test('포갠 소속: 상국 줄이 다른 소속 폴더의 줄이면 그 폴더가 품는다 — 안쪽은 상자(깊이 1)', () {
    final on = build(), off = build(folder: false);
    for (final l in [on, off]) {
      l.expandHost(7, true);
      l.expandHost(8, true);
    }
    expect(visibleOrder(on), [0, 1, 4, 5, 6, 2, 3]);
    expect(visibleOrder(off), [0, 1, 4, 5, 6, 2, 3]);
    final outer = on.scopeOnOf(h1)!, inner = on.scopeOnOf(h2)!;
    expect([outer.rows, outer.depth], [{1, 4, 5, 6}, 0]);
    expect([inner.rows, inner.depth], [{5, 6}, 1]);
    expect(on.hostFolderRowOf(h2), 5);
    // 안쪽 상국 줄 5: 틈 3 + 5 + 10 + 상자 머리 [G.boxHead] 24(그릇 그림 갈래 과제 7 걸음 2 — 뚜껑 22 · 예전 20) · 6: 3 + 5 + 10 ·
    // 두 폴더가 6에서 함께 끝나 줄 2 위에 발 둘(7 + 7).
    expect(on.geo(5).bandTop, 3 + 5 + 10 + G.boxHead);
    expect(on.geo(6).bandTop, 3 + 5 + 10);
    expect(on.geo(2).bandTop, 3 + 5 + G.folderFoot + G.boxFoot);
    expect(on.totalHeight - off.totalHeight, (G.folderHead + G.folderFoot) + (G.boxHead + G.boxFoot) + 4 * 10 + 3 * 2);
    // 바깥만 접으면(상국 띠 7의 소속을 접음) 안쪽 변형도 줄을 잃어 폴더가 없다 — 줄 6은 쌓이되 줄 5가 없다.
    for (final l in [on, off]) {
      l.expandHost(7, false);
    }
    expect(on.scopeOnOf(h1), isNull);
    expect(on.scopeOnOf(h2), isNull, reason: '상국 줄 5가 없으면 안쪽 폴더도 없다');
    expect(on.isVisible(5), isFalse);
    expect(stackOf(on), stackOf(off));
  });

  test('다른 변형과 함께 켜도 깨지지 않는다 — 상국 줄을 품지 않는 그릇은 그대로 · 폴더는 바깥(깊이 0)', () {
    final on = build(), off = build(folder: false);
    for (final l in [on, off]) {
      l.expandHost(7, true);
      l.openScope('s2', true);
    }
    expect(visibleOrder(on), [0, 3, 1, 4, 5, 2]);
    expect(visibleOrder(off), [0, 3, 1, 4, 5, 2]);
    expect(on.scopeOnOf(h1)!.depth, 0);
    expect(on.scopeOnOf('s2')!.rows, {3}, reason: '상국 줄을 품지 않는 그릇은 넓히지 않는다');
    expect(on.scopesOn.map((s) => s.uid), ['s2', h1]);
    // 그릇 s2의 발(줄 1 위)과 소속 폴더의 머리가 한 틈에 쌓인다: 3 + 5 + 10 + 폴더 발 7 + 폴더 머리 21.
    expect(on.geo(1).bandTop, 3 + 5 + 10 + G.folderFoot + G.folderHead);
    expect(off.geo(1).bandTop, 3 + 5 + G.folderFoot);
    // 끄고 켜도 같은 값으로 돌아온다.
    on.openScope('s2', false);
    on.openScope('s2', true);
    expect(on.geo(1).bandTop, 3 + 5 + 10 + G.folderFoot + G.folderHead);
    expect(on.variantKeys, [h1, 'scope:s2']);
  });
}
