// 보기 상태 — 사람이 접고 펴고 끈 것. 줄의 생김새(자료)와 달리 이것은 그때그때의 상태라 불변 값으로 들고 다니며,
// SceneLayout.setViewState(next)에 통째로 넣는다(명세 05의 5절 · 7.6절 · 계약 3-1절).
//
//  · 접힌 트랙   — 그 트랙은 높이 34(조감 22) 머리글 하나로 줄고 줄은 모두 안 보인다(가는 막대만).
//  · 접힌 민족   — 그 묶음의 줄들이 묶음의 첫 줄 자리에 한 줄(높이 30 · 조감 14)로 합쳐진다.
//  · 끈 트랙     — 필터. 줄이 통째로 빠지고 아래가 올라온다(자료집 끔과 같은 길 — 흐르지 않는다).
//  · 펼친 상위 정권 · 켠 대범위 — 저장소의 변형을 켜 줄을 옮겨 쌓는다(계약 3-2절).
//  · 접힌 대범위 가지 — 켠 대범위의 묶음도 민족처럼 한 줄로 접힌다([ViewState.variantGroupKey] · 지금 연표의 `__scope:<uid>` 가지).
//  · 켠 집합 보기 — 판 하나(변형 kind 3 `view:<id>`)를 켜면 구성 나라의 줄이 맨 위 판 트랙으로 모이고 나머지 트랙은 **판의 접힘**으로 접힌다
//    (10건 6 · 감독 선택 D4 결정 1 A — 지금 연표의 setBoard · _foldedNow). 판의 접힘(다시 편 트랙 · 판 트랙 접음)은 접힘 기억과 따로다.
//
// 묶음의 열쇠는 [ViewState.groupKey] · [ViewState.variantGroupKey]의 주석에 적었다.

/// 조감의 모양(명세 05 0절의 BIRD): a 띠 21px · 이름 · 사건 점 · b 21px · 이름만 · c 8px · 글자 없이 띠와 선만.
enum BirdShape {
  a,
  b,
  c;

  /// 그 모양에서 띠(= 줄) 하나의 높이.
  double get bandHeight => this == BirdShape.c ? 8.0 : 21.0;

  /// 띠 안 이름을 그리는가 · 사건 점과 알약을 그리는가.
  bool get name => this != BirdShape.c;
  bool get dots => this == BirdShape.a;

  /// 승계선의 문 높이와 띠 모서리 반지름.
  double get door => this == BirdShape.c ? 3.0 : 4.4;
  double get radius => this == BirdShape.c ? 2.5 : 4.5;

  static BirdShape of(String name) => switch (name) { 'b' => BirdShape.b, 'c' => BirdShape.c, _ => BirdShape.a };
}

/// 지금 쓰는 자리 값 묶음 — 보통은 G, 조감이면 G_BIRD가 덮어쓴 값(명세 05 0절 · 지금 연표의 `_G()`).
class ViewMetrics {
  const ViewMetrics._({
    required this.pad,
    required this.gap,
    required this.memberGap,
    required this.groupGap,
    required this.tab,
    required this.hem,
    required this.folded,
    required this.foldedGroup,
    required this.scopeHead,
    required this.scopeFoot,
    required this.mini,
    required this.miniTop,
    required this.miniPitch,
    this.bird,
  });

  /// 트랙 위아래 여백 · 줄 사이 기본 틈 · 소속 줄의 틈 · 민족 경계에 더하는 틈 · 책갈피 탭 자리 · 바탕 문화의 이름 단.
  final double pad, gap, memberGap, groupGap, tab, hem;

  /// 접힌 트랙의 높이 · 접힌 민족 줄의 높이 · 대범위 테두리의 머리와 발.
  final double folded, foldedGroup, scopeHead, scopeFoot;

  /// 가는 막대의 높이 · 첫 단의 위 · 단 간격.
  final double mini, miniTop, miniPitch;

  /// 조감이면 그 모양, 아니면 null.
  final BirdShape? bird;

  bool get isBird => bird != null;

  /// 꼬리표 갈래 E(설계 4-1 '실제 띠에 입힘' · 2026-10-15): 띠 위 탭 줄(18)이 없어지고 [tab]은 **줄 위 틈 5**(꼬리표 윗변 위의 숨 —
  /// 섬기는 줄의 받침 카드 · 상국 탭 몫은 줄마다 따로 더한다). 줄 사이 3 · 소속 줄 1 · 트랙 위아래 4(트랙 사이 띠끼리 4 + 4 + 5 = 13).
  /// 민족 경계의 14는 그대로 — 조각 ③에서 그릇 폴더가 대신한다.
  static const normal = ViewMetrics._(
    pad: 4, gap: 3, memberGap: 1, groupGap: 14, tab: 5, hem: 21,
    folded: 34, foldedGroup: 30, scopeHead: 16, scopeFoot: 6,
    mini: 6, miniTop: 5, miniPitch: 8,
  );

  static const _birdA = ViewMetrics._(
    pad: 4, gap: 6, memberGap: 6, groupGap: 6, tab: 0, hem: 0,
    folded: 22, foldedGroup: 14, scopeHead: 12, scopeFoot: 4,
    mini: 3, miniTop: 1.5, miniPitch: 4, bird: BirdShape.a,
  );
  static const _birdB = ViewMetrics._(
    pad: 4, gap: 6, memberGap: 6, groupGap: 6, tab: 0, hem: 0,
    folded: 22, foldedGroup: 14, scopeHead: 12, scopeFoot: 4,
    mini: 3, miniTop: 1.5, miniPitch: 4, bird: BirdShape.b,
  );
  static const _birdC = ViewMetrics._(
    pad: 4, gap: 6, memberGap: 6, groupGap: 6, tab: 0, hem: 0,
    folded: 22, foldedGroup: 14, scopeHead: 12, scopeFoot: 4,
    mini: 3, miniTop: 1.5, miniPitch: 4, bird: BirdShape.c,
  );

  /// 조감의 값 묶음(자리 값은 같고 모양만 다르다 — 띠 높이는 `bird.bandHeight`).
  static ViewMetrics birdOf(BirdShape shape) => switch (shape) {
    BirdShape.a => _birdA,
    BirdShape.b => _birdB,
    BirdShape.c => _birdC,
  };
}

/// 보기 상태(불변). 바꿀 때는 [copyWith] 따위로 새 값을 만들어 `layout.setViewState(next)`에 넣는다.
class ViewState {
  const ViewState({
    this.foldedTracks = const <int>{},
    this.foldedGroups = const <String>{},
    this.offTracks = const <int>{},
    this.expandedHosts = const <int>{},
    this.expandedGroups = const <int>{},
    this.openScopes = const <String>{},
    this.board = '',
    this.boardOpen = const <int>{},
    this.boardFolded = false,
    this.openHangs = const <int>{},
    this.foldedSpheres = const <String>{},
  });

  static const none = ViewState();

  /// 접힌 문화권(문화권 id — `east-asia` …, 리메이크 조각 ②). 접힌 문화권은 머리 단 한 줄뿐이고 그 트랙은 모두 안 보인다.
  /// 글자 id라 저장소를 다시 지어도 같다(기억 `parts['viewState'].foldedSpheres`).
  final Set<String> foldedSpheres;

  /// 접힌 트랙(트랙 id) · 접힌 민족 묶음(`"<트랙 id>|<묶음의 첫 줄>"`) · 끈 트랙(필터 · 트랙 id).
  final Set<int> foldedTracks, offTracks;
  final Set<String> foldedGroups;

  /// 펼친 상위 정권(띠 id) · 켠 대범위(uid). 둘 다 **줄을 옮겨 쌓는다** — 저장소의 변형(계약 3-2절)을 켜는 열쇠다.
  final Set<int> expandedHosts;
  final Set<String> openScopes;

  /// 단체를 펼친 나라(띠 id — 리메이크 조각 ④ · 설계 4-6 #7 C): 그 나라에 접혀 든 단체의 띠가 나라 밑 제 줄에 선다(저장소의 변형 `groups:…` · kind 5).
  final Set<int> expandedGroups;

  /// 켠 집합 보기 — 저장소의 변형 kind 3의 열쇠(`view:<id>` · 시대 구분의 임시 판은 `view:epoch:<시대 구분 uid>`). 빈 글이면 판이 없다.
  /// 한 번에 판 하나다(다른 판을 켜면 앞 판이 꺼진다 — 지금 연표의 setBoard).
  final String board;

  /// 판을 켠 동안 보는 사람이 **다시 편** 트랙(트랙 id) — 나머지 트랙은 접혀 있다(결정 1 A · 지금 연표의 `_boardOpen`).
  /// 접힘 기억 [foldedTracks]는 판을 켜도 그대로라, 판을 끄면 켜기 전 모습으로 돌아간다.
  final Set<int> boardOpen;

  /// 판 트랙 자신을 접었는가(지금 연표의 `_boardFolded`).
  final bool boardFolded;

  /// 매달린 속국 이름표를 **펼친** 줄(줄 번호 — 상국 띠의 플래그 창 '속국' · 건의 8 · 2026-10-14). 펼치지 않은 줄은 띠 아래 덧단에서 매달린 줄들의 몫이 빠진다.
  /// 리메이크 2부(목업 서고 — 감독 2026-10-15 "정권 등 숨김 펼침은 플래그에"): 처음에는 모두 접혀 있다(목업에는 상국 띠 아래 이름표가 없다).
  /// 줄 하나에 매달린 이름표를 단 상국은 지금 자료에서 하나뿐이라 줄로 잡는다(웹은 상국 uid로 잡는다 — 같은 답). 저장하지 않는다(창을 다시 열면 접혀 있다).
  final Set<int> openHangs;

  /// 묶음의 열쇠는 `"<트랙 id>|<묶음 이름>"`이다(지금 연표의 `peopleKey` — js/timeline.js 357).
  /// 지금 연표의 묶음 이름은 민족 · 문화면 그 민족 id, 대범위 가지면 `__scope:<대범위 uid>`인데,
  /// `{"op":"layout"}`의 `groups`에는 민족 id가 실리지 않아(계약 2절) 민족 · 문화는 (첫 줄 · 깊이 · 종류)로 대신한다.
  ///
  ///  · 민족 · 문화 묶음 — `"<트랙 id>|<첫 줄>:<깊이>:<종류>"` ([groupKey])
  ///  · 대범위 가지     — `"<트랙 id>|__scope:<대범위 uid>"` ([variantGroupKey] · 변형의 `groups[].key`를 그대로 쓴다)
  ///
  /// 가지는 드는 줄이 이어져 있지 않고(월흔해에서 `[8, 11, 12]`) 켤 때마다 생겼다 사라지므로 첫 줄로 가릴 수 없다 —
  /// 그래서 열쇠 규칙을 넓혔다. 두 꼴은 `|` 뒤의 모양이 달라 서로 부딪치지 않는다.
  static String groupKey(int trackId, int firstRow, int depth, int kind) => '$trackId|$firstRow:$depth:$kind';

  /// 변형이 만드는 묶음(대범위 가지)의 열쇠 — [key]는 변형의 `groups[].key`(`__scope:<uid>`)다.
  static String variantGroupKey(int trackId, String key) => '$trackId|$key';

  bool isTrackFolded(int trackId) => foldedTracks.contains(trackId);
  bool isTrackOff(int trackId) => offTracks.contains(trackId);
  bool isGroupFolded(String key) => foldedGroups.contains(key);
  bool isSphereFolded(String id) => foldedSpheres.contains(id);

  ViewState copyWith({
    Set<int>? foldedTracks,
    Set<String>? foldedGroups,
    Set<int>? offTracks,
    Set<int>? expandedHosts,
    Set<int>? expandedGroups,
    Set<String>? openScopes,
    String? board,
    Set<int>? boardOpen,
    bool? boardFolded,
    Set<int>? openHangs,
    Set<String>? foldedSpheres,
  }) => ViewState(
    foldedTracks: foldedTracks ?? this.foldedTracks,
    foldedGroups: foldedGroups ?? this.foldedGroups,
    offTracks: offTracks ?? this.offTracks,
    expandedHosts: expandedHosts ?? this.expandedHosts,
    expandedGroups: expandedGroups ?? this.expandedGroups,
    openScopes: openScopes ?? this.openScopes,
    board: board ?? this.board,
    boardOpen: boardOpen ?? this.boardOpen,
    boardFolded: boardFolded ?? this.boardFolded,
    openHangs: openHangs ?? this.openHangs,
    foldedSpheres: foldedSpheres ?? this.foldedSpheres,
  );

  /// 집합 보기 하나를 켜거나(열쇠) 끈다(빈 글). 판을 바꾸거나 켜고 끄면 판의 접힘은 새로 — 판 트랙만 펴고 나머지는 접힌다(지금 연표의 setBoard).
  ViewState withBoard(String key) => key == board ? this : copyWith(board: key, boardOpen: const <int>{}, boardFolded: false);

  /// 판을 켠 동안 트랙 하나를 다시 펴거나 접는다(판 트랙이 아닌 트랙).
  ViewState withBoardTrackOpen(int trackId, bool open) => copyWith(boardOpen: _with(boardOpen, trackId, open));

  /// 트랙 하나를 접거나 편다.
  ViewState withTrackFolded(int trackId, bool on) => copyWith(foldedTracks: _with(foldedTracks, trackId, on));

  /// 트랙 하나를 끄거나 켠다(필터).
  ViewState withTrackOff(int trackId, bool off) => copyWith(offTracks: _with(offTracks, trackId, off));

  /// 민족 묶음 하나를 접거나 편다([key]는 [groupKey] · `layout.groupKeyOf`).
  ViewState withGroupFolded(String key, bool on) => copyWith(foldedGroups: _with(foldedGroups, key, on));

  /// 모두 접거나 모두 편다(지금 연표의 `foldAll`).
  ViewState withAllFolded(Iterable<int> trackIds, bool on) => copyWith(foldedTracks: on ? {...trackIds} : const <int>{});

  /// 상위 정권 하나의 소속을 펼치거나 접는다([bandId]는 그 띠의 번호 — 저장소의 변형 `host:…`가 이 번호를 안다).
  ViewState withHostExpanded(int bandId, bool on) => copyWith(expandedHosts: _with(expandedHosts, bandId, on));

  /// 나라 하나의 단체를 펼치거나 접는다([bandId]는 그 나라 띠의 번호 — 저장소의 변형 `groups:…`가 이 번호를 안다).
  ViewState withGroupsExpanded(int bandId, bool on) => copyWith(expandedGroups: _with(expandedGroups, bandId, on));

  /// 줄 하나의 매달린 속국 이름표를 펴거나([on]) 접는다.
  ViewState withHangsOpen(int row, bool on) => copyWith(openHangs: _with(openHangs, row, on));

  /// 문화권 하나를 접거나 편다(리메이크 조각 ②).
  ViewState withSphereFolded(String id, bool on) => copyWith(foldedSpheres: _with(foldedSpheres, id, on));

  /// 대범위 하나를 켜거나 끈다([uid]는 대범위의 이름 — 저장소의 변형 `scope:…`가 이 이름을 안다).
  ViewState withScopeOpen(String uid, bool on) => copyWith(openScopes: _with(openScopes, uid, on));

  /// 줄 쌓기에 쓰이는 것만 견준다 — 펼친 소속과 켠 대범위도 줄을 옮겨 쌓으므로 여기에 든다.
  bool stacksSameAs(ViewState other) =>
      _same(foldedTracks, other.foldedTracks) &&
      _same(foldedGroups, other.foldedGroups) &&
      _same(offTracks, other.offTracks) &&
      _same(expandedHosts, other.expandedHosts) &&
      _same(expandedGroups, other.expandedGroups) &&
      _same(openScopes, other.openScopes) &&
      board == other.board &&
      _same(boardOpen, other.boardOpen) &&
      boardFolded == other.boardFolded &&
      _same(openHangs, other.openHangs) &&
      _same(foldedSpheres, other.foldedSpheres);

  /// 이번에 접거나 편 트랙이 하나뿐이면 그 id(아니면 -1) — 세로 닻이 그 트랙의 위를 붙잡는다(지금 연표의 `_pressHold`).
  /// 판을 켠 채 트랙을 펴고 접으면 판의 접힘([boardOpen] · [boardFolded] — 판 트랙의 id는 [boardTrack])이 바뀐다.
  static int foldToggled(ViewState before, ViewState after, {int boardTrack = -1}) {
    int found = -1;
    for (final id in {...before.foldedTracks, ...after.foldedTracks}) {
      if (before.foldedTracks.contains(id) == after.foldedTracks.contains(id)) continue;
      if (found >= 0) return -1;
      found = id;
    }
    if (before.board.isEmpty || before.board != after.board) return found;
    for (final id in {...before.boardOpen, ...after.boardOpen}) {
      if (before.boardOpen.contains(id) == after.boardOpen.contains(id)) continue;
      if (found >= 0) return -1;
      found = id;
    }
    if (before.boardFolded != after.boardFolded && boardTrack >= 0) {
      if (found >= 0) return -1;
      found = boardTrack;
    }
    return found;
  }

  @override
  bool operator ==(Object other) =>
      other is ViewState &&
      stacksSameAs(other) &&
      _same(expandedHosts, other.expandedHosts) &&
      _same(openScopes, other.openScopes);

  @override
  int get hashCode => Object.hash(foldedTracks.length, foldedGroups.length, offTracks.length, expandedHosts.length, expandedGroups.length, openScopes.length, board, boardOpen.length, boardFolded, openHangs.length, foldedSpheres.length);

  static Set<T> _with<T>(Set<T> set, T value, bool on) {
    if (set.contains(value) == on) return set;
    final out = {...set};
    if (on) {
      out.add(value);
    } else {
      out.remove(value);
    }
    return out;
  }

  /// 두 묶음이 같은가(차례는 보지 않는다).
  static bool sameSet<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
  static bool _same<T>(Set<T> a, Set<T> b) => sameSet(a, b);
}

/// 자동 조감(명세 05 7.6 · 움직임 원칙 ⑨): 보는 폭이 문턱을 넘으면 조감으로, 되돌아오면 직전 밀도로.
/// 켬/끔(`on`)과 돌아갈 밀도(`from`)는 밖에서 받고, 판정은 **정착 때 한 번**만 새로 한다(원칙 ④).
class AutoBird {
  /// 들어가는 문턱(년)과 나가는 문턱 — 문턱은 둘이다(8% 여유).
  static const thresholdYears = 2600.0, gapRatio = 0.08;
  static const enterYears = thresholdYears, leaveYears = thresholdYears * (1 - gapRatio); // 2600 · 2392

  /// 자동 조감을 켰는가 · 되돌아갈 밀도 · 손으로 다른 밀도를 골라 쉬는 중인가.
  bool on = false;
  int from = 0;
  bool hold = false;

  bool _past = false, _known = false;

  /// 지난 판정(문턱을 넘어 있었는가).
  bool get past => _past;

  /// 아직 한 번도 재지 않았는가.
  bool get fresh => !_known;

  /// 문턱 둘(지금 연표의 `_past`): 넘어 있었으면 2,392년까지 버티고, 아니면 2,600년을 넘어야 한다.
  bool measure(double spanYears) {
    _past = spanYears >= (_known && _past ? leaveYears : enterYears);
    _known = true;
    return _past;
  }

  /// 지금 자동 조감이 걸려야 하는가.
  bool get wanted => on && !hold && _past;

  /// 자동 조감을 켜고 끈다 — 켜는 순간에는 지금 보기로 한 번 판정한다(지금 연표의 `setBird({auto})`).
  void enable(bool value, double spanYears) {
    on = value;
    hold = false;
    if (value) measure(spanYears);
  }

  /// 밀도를 손으로 골랐다(지금 연표의 `setDensity`): 조감을 고르면 쉼을 풀고, 다른 것을 고르면 문턱 아래로 내려올 때까지 쉰다.
  void chose(int density) {
    if (density == 2) {
      hold = false;
      return;
    }
    if (wanted) hold = true;
    from = density;
  }

  /// 자동 조감을 손으로 풀었다(지금 연표의 `leaveAutoBird`).
  void leave() {
    if (wanted) hold = true;
  }

  /// 정착 때 한 번. 자동 조감이 달라져야 하면 새 값을, 그대로면 null을 돌려준다.
  /// [active]는 지금 걸려 있는 자동 조감, [density]는 사람이 고른 밀도다.
  bool? settle(double spanYears, {required int density, required bool active}) {
    final past = measure(spanYears);
    if (!past) hold = false; // 문턱 아래로 내려오면 손으로 풀어 둔 것을 되돌린다
    if (!on || density == 2) return null;
    return wanted == active ? null : wanted;
  }
}
