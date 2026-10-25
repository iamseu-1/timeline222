import '../motion.dart';

// 장면 위에 얹는 표시 상태 — 기준선 · 기간 재기 · 커서가 올라간 것 · 펼친 상위 정권 · 켠 대범위 · 승계선 보기 · 도착 고리.
// 앱 틀의 다리가 적고, 그리개가 장면마다 읽어 층에 걸어 준다(층은 제 밭만 안다). 밝기 상태(고르기 · 강조 · 조명)는 emphasis.dart.
// 장면의 밭을 늘리지 않으려고 곁에 매단다.

import 'aux_calendar.dart';

/// 도착 고리 하나(명세 06의 4-4 · css `.is-arrived`) — 멀리 가서 닿은 그 항목에 600ms 한 번.
/// 번호는 타일의 번호다: [band] 띠 · [event] 사건 · [row] 그 줄의 띠 모두 · [track] 트랙(트랙의 id) — 하나만 채운다.
/// [at]은 고리가 시작한 시각(장면의 시계 `scene.now`의 ms)이라, 같은 것에 다시 걸어도 새 [SceneRing]이면 처음부터 다시 그린다.
class SceneRing {
  const SceneRing({this.band = 0, this.event = 0, this.row = -1, this.track = 0, required this.at});
  final int band, event, row, track;
  final double at;

  /// 가리키는 것이 하나도 없다(그릴 것이 없다).
  bool get isEmpty => band == 0 && event == 0 && row < 0 && track == 0;

  /// 고리가 다 옅어지는 데 걸리는 시간(css `--t-ring`).
  static const ms = Motion.ring;
}

class SceneMarks {
  static final _byScene = Expando<SceneMarks>('표시 상태');
  static SceneMarks of(Object scene) => _byScene[scene] ??= SceneMarks();

  /// 기준선(같은 해 보기)의 자리(분)와 그 위의 날짜 글.
  double? marker;
  String markerText = '';

  /// 기간 재기의 두 끝(분)과 가운데 글.
  (double, double)? measure;
  String measureText = '';

  /// 고른 인물(uid) · 고른 날짜 칸(axisCellKey) · 도읍 노선도가 비추는 도시.
  String? pickedFigure, pickedAxisCell, hotCity;

  /// 커서가 올라간 것: 띠 번호 · 띠 안의 칸(StripHit.key) · 인물(uid) · 왼쪽 칸의 줄과 트랙.
  int? hotBand, hotRow, hotTrack;
  String? hotCell, hoverFigure;

  /// 커서가 올라간 지도자 칸의 사람이 앉은 모든 자리(건의 8의 6-나 — `'<띠 번호>|<칸 참조>'`, 올린 칸 자신도 든다). 같은 사람의 다른 자리가
  /// 없으면 null. 앱 틀이 칸의 항목 기록(`x_persons[칸].others`)을 늦게 받아 채운다 — 칸 층이 [Look.twins]와 같은 테를 두른다.
  Set<String>? hotTwins;

  /// 커서가 올라간 선의 두 끝(승계선 = 선대 · 후대 띠 번호, 소속선 = 상국 · 소속 띠 번호) — 그 선만 색이 짙어진다(`.tl-link:hover` · `.tl-part:hover`).
  (int, int)? hotLink;

  /// 커서가 올라간 연합의 겹 탭 — 그 연합 단체의 uid(감독 선택 D5 결정 3 C: 구성 나라 띠만 또렷 · 각자의 가담 기간 조명 · 나머지 줄 .3 ·
  /// 왼쪽 칸의 줄 이름 .4 · 같은 연합의 탭 모두 진하게 — 트랙이 달라도). 띠 층(paint/bands.dart)과 맨 위 층(paint/overlay.dart)이 읽는다.
  String? hotCoal;

  /// 단체 계보 창에서 고른 단체(웹 `timeline.setGroupFocus` — 감독 선택 D5 결정 4 A): 집권 단 · 실권 단 · 붕당 렌즈의 단체 칸 가운데
  /// 그 단체의 칸만 안쪽 진한 테두리(조명과 같은 말) · 나머지 단체 칸은 .4. [groupFocusColor]는 그 단체의 색(0xRRGGBB) —
  /// 연정 칸의 타일에는 첫째 단체의 uid만 실려 있어, 둘째부터는 그 나라 띠(조명이 켜진 띠)의 색 점으로 가린다. 칸 층(paint/strips.dart)이 읽는다.
  String? groupFocus;
  int groupFocusColor = 0;

  /// 승계선 보기(0 모두 · 1 직접만 · 2 끔)와 소속선 보기.
  int successionMode = 0;
  bool showPartOf = true;

  /// 필터 시트의 표시 값 가운데 그리기만 바꾸는 것(자료 · 줄 쌓기는 그대로) — 앱 틀이 FilterState에서 옮겨 적고 층이 읽는다(11물결).
  /// [showAlt] 이설(다른 견해)의 표시 · [showHouses] 가문 칠 · [leaderLabel] 지도자 표기('auto' · 'temple' · 'posthumous' · 'given' … 지금 연표의 값 그대로) ·
  /// [leaderOrdinal] 대수 · [lens] 관점('' 기본 · 'local' 나라마다 제 이름 · 그 밖은 트랙 번호를 적은 글).
  bool showAlt = true, showHouses = false, leaderOrdinal = false;
  String leaderLabel = 'auto', lens = '';

  /// 필터 시트의 '날짜 칸' 표시 체크 넷(간지 · 연호 · 도읍 · 시대 구분) — 끄면 그 줄이 날짜 칸에서 빠진다(11물결 axis3).
  /// 그리개가 [AxisLayer.setShown]으로 옮겨 적고, 높이는 묶음 여닫기와 같은 360ms 흐름을 탄다.
  bool showGanji = false, showEras = false, showCapitals = false, showEpochs = true; // 리메이크 2부: 목업 날짜 칸은 연도 · 시대뿐
  YearCycle? yearCycle;

  /// 펼친 상위 정권(띠 번호)과 켠 대범위(uid).
  Set<int> expanded = const {};
  Set<String> scopesOn = const {};

  /// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A): 켠 주제의 색(0xFFRRGGBB — 그 주제 사건의 고리) · 그 주제의 사건 번호(타일의 번호).
  /// 렌즈를 켰는지는 배치의 `SceneLayout.themeLens`가 정한다. [lensEvents]가 null이면 아직 받는 중이라 사건을 옅게 하지 않는다.
  int lensColor = 0;
  Set<int>? lensEvents;

  /// 도착 고리(없으면 null) — 맨 위 층(paint/overlay.dart)이 읽어 한 번 그린다.
  SceneRing? ring;

  /// 도착 고리를 건다(다리가 uid를 타일의 번호로 바꿔 부른다). 빈 것이면 걷는다 — 앞 고리도 함께 걷힌다.
  void showRing(SceneRing? next) {
    ring = next == null || next.isEmpty ? null : next;
    version++;
  }

  /// 바뀔 때마다 오른다 — 적는 쪽이 올리고 장면에 다음 장면을 청한다.
  int version = 0;
}
