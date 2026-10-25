import 'dart:convert';

import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/view_memory.dart';
import 'package:flutter_test/flutter_test.dart';

// 보기 기억(parts['viewState'] — 리메이크 4단계 과제 7 걸음 5): 쓰기 · 읽기 왕복 · 모르는 uid 버림 · 옛 기억(열쇠 없음) · 되살리기 전에는 쓰지 않음(결함 ㉡).

Map<String, dynamic> row(int id, {int variant = 0}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': variant,
};

/// 그릇 변형(`scope:<uid>` · kind 2) · 선반 변형(`shelf:<uid>` · kind 6) 하나씩 — [rows]를 한 가지로.
Map<String, dynamic> variant(int id, int kind, String uid, List<int> rows) => {
  'id': id, 'key': '${kind == 6 ? 'shelf' : 'scope'}:$uid', 'kind': kind, 'track': 1, 'band': 0, 'uid': uid, 'name': uid,
  'rows': [
    for (final (i, r) in rows.indexed) {'row': r, 'after': r - 1, 'ord': 0, 'new': 0, 'scope_pad': i == 0 ? 16 : 0, 'group_start': i == 0 ? 1 : 0},
  ],
  'groups': [
    {'key': '__scope:$uid', 'depth': 0, 'name': uid, 'color': 0xd4a39b, 'kind': 2, 'rows': rows},
  ],
  if (kind == 6) 'shelf': [{'uid': 'h/a', 'name': '숨은 띠', 'color': 0x8a9a7b, 'start': 0, 'end': 0, 'ord': 5}],
};

/// 트랙 하나 · 문화권 둘(east · west) · 그릇 셋 — s-big(그릇 변형 + 선반 변형) · s-small(그릇 변형만 — 구성원 다섯 이하) · s-shelf-only(선반 변형만 —
/// 저장소가 아는 그릇으로 친다).
SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '검사 자료집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xa0bcc5, 'rows': [for (int r = 0; r < 8; r++) row(r)]},
  ],
  'epochs': [],
  'spheres': [{'id': 'east', 'name': '동녘'}, {'id': 'west', 'name': '서녘'}],
  'variants': [
    variant(1, 2, 's-big', [1, 2]),
    variant(2, 6, 's-big', [1, 2]),
    variant(3, 2, 's-small', [4, 5]),
    variant(4, 6, 's-shelf-only', [6, 7]),
  ],
})..reduceMotion = true;

void main() {
  test('저장소가 아는 그릇 uid는 그릇 변형 · 선반 변형의 uid · 문화권은 그 id', () {
    final l = layout();
    expect(ViewMemory.scopesOf(l), {'s-big', 's-small', 's-shelf-only'});
    expect(ViewMemory.spheresOf(l), {'east', 'west'});
  });

  test('쓰기 · 읽기 왕복: 열쇠마다 정렬한 목록 · shelvedScopes는 그릇 uid의 정렬 목록 · 읽으면 같은 보기 상태(켠 그릇은 바탕 그대로)', () {
    const now = ViewState(
      foldedTracks: {7, 2},
      foldedGroups: {'1|__scope:s-small', '1|3:0:1'},
      expandedHosts: {12, 5},
      expandedGroups: {9},
      foldedSpheres: {'west'},
      shelvedScopes: {'s-small', 's-big'},
      openScopes: {'s-big', 's-small'},
    );
    final json = ViewMemory.toJson(now);
    expect(json, {
      'foldedTracks': [2, 7],
      'foldedGroups': ['1|3:0:1', '1|__scope:s-small'],
      'expandedHosts': [5, 12],
      'expandedGroups': [9],
      'foldedSpheres': ['west'],
      'shelvedScopes': ['s-big', 's-small'],
    });
    expect(json.containsKey('openScopes'), isFalse, reason: '켠 그릇은 필터 기억(parts.filters.scopes)이 맡는다');
    // 파일을 거친 꼴(JSON 글 → 맵)로 읽는다 — 바탕(필터 기억이 켠 그릇)에 얹는다.
    final saved = Map<String, dynamic>.from(jsonDecode(jsonEncode(json)) as Map);
    const base = ViewState(openScopes: {'s-big', 's-small'});
    final read = ViewMemory.read(saved, base, spheres: {'east', 'west'}, scopes: {'s-big', 's-small'})!;
    expect(read, now);
    expect(read.openScopes, base.openScopes);
    expect(ViewMemory.toJson(read), json, reason: '다시 적어도 같은 글');
  });

  test('읽기: 지금 저장소에 없는 그릇 · 문화권은 버린다 · 글이 아닌 값도 버린다', () {
    final l = layout();
    final saved = <String, dynamic>{
      'foldedSpheres': ['east', 'gone-sphere'],
      'shelvedScopes': ['s-big', 'gone/scope', 's-shelf-only', 7, null],
    };
    final read = ViewMemory.read(saved, l.viewState, spheres: ViewMemory.spheresOf(l), scopes: ViewMemory.scopesOf(l))!;
    expect(read.foldedSpheres, {'east'});
    expect(read.shelvedScopes, {'s-big', 's-shelf-only'});
  });

  test('옛 기억(shelvedScopes 열쇠 없음 — 걸음 5 전의 판)은 선반 빈 목록 · 나머지 열쇠는 예전 그대로 · 문화권 열쇠가 없으면 바탕(처음 접힘) 그대로 · 칸이 없으면 null', () {
    final old = <String, dynamic>{
      'foldedTracks': [3],
      'foldedGroups': ['1|__scope:s-big'],
      'expandedHosts': [11],
      'expandedGroups': <int>[],
    };
    const base = ViewState(openScopes: {'s-big'}, foldedSpheres: {'west'}, shelvedScopes: {'s-big'});
    final read = ViewMemory.read(old, base, spheres: {'east', 'west'}, scopes: {'s-big'})!;
    expect(read.shelvedScopes, isEmpty);
    expect([read.foldedTracks, read.foldedGroups, read.expandedHosts, read.expandedGroups], [{3}, {'1|__scope:s-big'}, {11}, <int>{}]);
    expect(read.foldedSpheres, {'west'}, reason: '문화권 열쇠가 없는 기억은 처음 접힘(바탕) 그대로');
    expect(read.openScopes, {'s-big'});
    expect(ViewMemory.read(null, base, spheres: const {}, scopes: const {}), isNull);
  });

  test('되살리기 전에는 쓰지 않는다(결함 ㉡): 기억을 잇는 동안의 보기 상태가 되살릴 기억을 덮지 않고, 되살린 뒤부터 달라진 것만 적는다', () {
    final l = layout();
    // 지난 실행이 남긴 기억: 선반 s-big · 그릇 s-small의 가지를 접음 · 트랙 1 접음.
    final parts = <String, Map<String, dynamic>>{
      ViewMemory.part: ViewMemory.toJson(const ViewState(foldedTracks: {1}, foldedGroups: {'1|__scope:s-small'}, shelvedScopes: {'s-big'})),
    };
    final before = jsonEncode(parts);
    final memory = ViewMemory();
    expect(memory.restored, isFalse);
    // 기억을 이을 때: 필터 기억이 그릇 둘을 켬(이때 장면 듣개가 불려 지금 상태 — 접힘 없음 — 를 적으려 한다).
    expect(l.setViewState(l.viewState.withScopeOpen('s-big', true).withScopeOpen('s-small', true)), isTrue);
    expect(memory.write(parts, l.viewState), isFalse);
    expect(jsonEncode(parts), before, reason: '되살리기 전 — 기억 그대로');
    // 되살리기: 켠 그릇 위에 기억을 얹는다 → 선반 · 접힘 · 트랙 접힘이 남는다.
    final next = ViewMemory.read(parts[ViewMemory.part], l.viewState, spheres: ViewMemory.spheresOf(l), scopes: ViewMemory.scopesOf(l))!;
    expect(l.setViewState(next), isTrue);
    memory.restored = true;
    expect([l.scopeStateOf('s-big'), l.scopeStateOf('s-small'), l.viewState.foldedTracks], [ScopeState.shelf, ScopeState.closed, {1}]);
    expect(l.variantKeys, contains('shelf:s-big'), reason: '켠 그릇이 선반 기억에 있으면 엔진의 선반 변형');
    expect(memory.write(parts, l.viewState), isFalse, reason: '되살린 그대로면 같은 글이라 적지 않는다');
    // 되살린 뒤의 바꿈(차림표 '펼침' — 선반 기억이 빠짐)은 적는다.
    expect(l.setViewState(l.viewForScopeState('s-big', ScopeState.open)), isTrue);
    expect(memory.write(parts, l.viewState), isTrue);
    expect(parts[ViewMemory.part]!['shelvedScopes'], isEmpty);
    expect(parts[ViewMemory.part]!['foldedGroups'], ['1|__scope:s-small']);
  });
}
