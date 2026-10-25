import 'filter_state.dart';

// 필터 시트의 값 → 자료 처리부의 거르개(계약 2-2절). 타일 · 빈 줄 접기 · 줄 이름 · 검색 · 같은 해 보기 · 표 · 묶음 목록이 같은 거르개를 받는다.

/// 거르개를 받는 조회 명령들(범례 `legend_kinds`와 `scopes`는 자료 전체를 본다).
/// 켠 변형(줄이 옮겨 가는 것)을 받는 조회 명령들(계약 2-4절).
const variantOps = {'rows_near', 'row_labels', 'list', 'events_in', 'echo'};

const filteredOps = {'rows_near', 'row_labels', 'search', 'search_year', 'events_in', 'same_year', 'table', 'table_csv', 'list', 'echo', 'lens_names'};

/// 켠 DLC(`packs`)를 받는 조회 명령들 — 끈 DLC가 저장소에 남아 있을 때(다시 짓지 못하는 곳 · 다 껐을 때 · 다시 짓는 동안)
/// 검색 · 같은 해 · 표 · 범례 · 대범위 · 목록에 끈 DLC가 나오지 않게 앱이 싣는다(2026-10-16 감독 건의). 싣지 않으면 엔진은 모든 DLC를 본다.
const packOps = {'search', 'search_year', 'events_in', 'same_year', 'table', 'table_csv', 'list', 'echo', 'lens_names', 'legend_kinds', 'scopes'};

/// [shownHistoricity]는 지금 칩 줄에 보이는 실재성 id들 — 저장된 '끔'은 보이는 것만 센다(실재성을 쓰던 자료집을 끄면 칩 줄이 사라지는데 저장된 끔이 남아 나라가 모두 숨는 일을 막는다 — 명세 06 6-4).
/// 거를 것이 없으면 null(거르개를 싣지 않는다 — 답이 예전과 바이트까지 같다).
Map<String, dynamic>? filterQueryOf(FilterState s, {Iterable<String>? shownHistoricity}) {
  List<int> ints(Iterable<String> ids) => [for (final id in ids) if (int.tryParse(id) != null) int.parse(id)]..sort();
  final hist = shownHistoricity == null ? const <String>{} : s.historicityOffAmong(shownHistoricity);
  final q = <String, dynamic>{
    if (s.tracksOff.isNotEmpty) 'tracks_off': ints(s.tracksOff),
    if (s.categoriesOff.isNotEmpty) 'cats_off': ints(s.categoriesOff),
    if (s.kindsOff.isNotEmpty) 'kinds_off': ints(s.kindsOff),
    if (hist.isNotEmpty) 'hist_off': ints(hist),
    if (s.minImportance > 1) 'min_importance': s.minImportance,
  };
  q.removeWhere((_, v) => v is List && v.isEmpty);
  return q.isEmpty ? null : q;
}
