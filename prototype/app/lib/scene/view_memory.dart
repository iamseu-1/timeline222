// 보기 기억 — 보기 상태(ViewState) ↔ 앱 기억 칸 parts['viewState'] 쓰기 · 읽기(명세 8-28 · 리메이크 4단계 과제 7 걸음 5).
// archive_app.dart의 _restoreViewState · _onViewState 몸통을 옮겨 왔다 — 앱 틀은 부르기만 한다(틀을 함께 고치는 다른 갈래와 겹칠 줄을 줄이려고).
//
// 적는 열쇠: 접은 트랙(foldedTracks) · 접은 민족 · 그릇 가지(foldedGroups) · 펼친 상국(expandedHosts) · 단체를 편 나라(expandedGroups) ·
// 접은 문화권(foldedSpheres) · 선반에 둔 그릇(shelvedScopes — 과제 7 · 그릇 uid의 정렬 목록 · 메이커 서고 미리보기의 shelvedScopes와 같은 뜻).
// 켠 그릇(openScopes)은 필터 기억(parts['filters'].scopes)이, 끈 트랙은 칩이 맡는다 — 여기에 적지 않는다.
//
// 결함 ㉡(과제 7 걸음 5에서 고침): 앱이 기억을 이을 때(glue.attachMemory) 필터 기억의 그릇 켬이 보기 상태를 바꾸면, 먼저 붙은 장면 듣개(_onViewState)가
// **되살리기(_restoreViewState) 전에** 지금 보기 상태(접힘 없음)를 기억 칸에 덮어써 되살릴 것이 사라졌다. 그래서 [ViewMemory.restored]가 서기 전에는
// [ViewMemory.write]가 쓰지 않는다. 고친 덕에 그릇을 켠 채 접은 트랙 · 문화권 · 그릇 가지의 접힘(`<트랙 id>|__scope:<uid>`)도 다시 켜면 남는다
// (예전에는 필터 기억에 켠 그릇이 있으면 이 접힘들이 다음 실행에 풀렸다 — 켠 그릇이 없으면 잇는 동안 보기 상태가 바뀌지 않아 듣개가 쓰지 않았다).

import 'dart:convert';

import 'layout.dart'; // ViewState도 함께(layout.dart가 view_state.dart를 내보낸다)

/// 보기 기억 한 벌 — 되살리기가 끝났는지([restored])를 들고, 기억 칸을 읽고 쓰는 순수 함수를 둔다.
class ViewMemory {
  /// 앱 기억(`AppMemory.parts`)의 칸 이름.
  static const part = 'viewState';

  /// 되살리기가 끝났는가 — 끝나기 전에는 [write]가 기억에 쓰지 않는다(결함 ㉡). 앱 틀이 되살린 뒤(되살릴 것이 없었어도) 세운다.
  bool restored = false;

  /// 기억 칸에 적는 꼴(열쇠마다 정렬한 목록 — 같은 상태면 같은 글).
  static Map<String, dynamic> toJson(ViewState now) => <String, dynamic>{
    'foldedTracks': now.foldedTracks.toList()..sort(),
    'foldedGroups': now.foldedGroups.toList()..sort(),
    'expandedHosts': now.expandedHosts.toList()..sort(),
    'expandedGroups': now.expandedGroups.toList()..sort(),
    'foldedSpheres': now.foldedSpheres.toList()..sort(),
    'shelvedScopes': now.shelvedScopes.toList()..sort(),
  };

  /// 기억 칸 [saved]를 [base](여는 참의 보기 상태 — 필터 기억이 켠 그릇이 이미 들었다)에 얹은 보기 상태. 칸이 없으면 null(그대로 둔다).
  ///  · 문화권: 칸이 있으면 마지막으로 본 모습 그대로 — 지금 자료에 없는 문화권([spheres]에 없는 id)은 버린다. 칸이 없으면 [base] 그대로(처음 접힘).
  ///  · 선반: 지금 저장소에 그 그릇의 변형(그릇 변형 · 선반 변형 — [scopes])이 없는 uid는 버린다. 칸이 없는 옛 기억은 빈 목록.
  static ViewState? read(Map<String, dynamic>? saved, ViewState base, {required Set<String> spheres, required Set<String> scopes}) {
    if (saved == null) return null;
    Set<int> numbers(Object? raw) => {if (raw is List) for (final x in raw) if (x is num) x.toInt()};
    final groups = saved['foldedGroups'], folded = saved['foldedSpheres'], shelved = saved['shelvedScopes'];
    return base.copyWith(
      foldedTracks: numbers(saved['foldedTracks']),
      foldedGroups: {if (groups is List) for (final x in groups) '$x'},
      expandedHosts: numbers(saved['expandedHosts']),
      expandedGroups: numbers(saved['expandedGroups']),
      foldedSpheres: folded is List ? {for (final x in folded) if (spheres.contains('$x')) '$x'} : null,
      shelvedScopes: {if (shelved is List) for (final x in shelved) if (x is String && scopes.contains(x)) x},
    );
  }

  /// 그 배치의 저장소가 아는 그릇 uid — 그릇 변형(`scope:` · kind 2)과 선반 변형(`shelf:` · kind 6)의 uid([read]의 `scopes`).
  static Set<String> scopesOf(SceneLayout layout) => {
    for (final v in layout.variants)
      if ((v.kind == VariantInfo.kindScope || v.kind == VariantInfo.kindShelf) && v.uid.isNotEmpty) v.uid,
  };

  /// 그 배치의 문화권 id([read]의 `spheres`).
  static Set<String> spheresOf(SceneLayout layout) => {for (final x in layout.spheres) x.id};

  /// 지금 보기 상태를 기억 칸 [parts]`[`[part]`]`에 적는다 — 되살리기 전([restored] 거짓)이거나 이미 같은 값이면 적지 않고 거짓.
  /// 적었으면 참(부르는 쪽이 `AppMemory.save`를 부른다).
  bool write(Map<String, Map<String, dynamic>> parts, ViewState now) {
    if (!restored) return false;
    final next = toJson(now);
    if (jsonEncode(next) == jsonEncode(parts[part])) return false;
    parts[part] = next;
    return true;
  }
}
