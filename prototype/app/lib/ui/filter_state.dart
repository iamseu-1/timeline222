import 'package:flutter/foundation.dart';

import '../scene/layout.dart';
import '../scene/aux_calendar.dart';

// 필터 시트가 들고 있는 값. 불변이라 바뀔 때마다 새 값을 만들어 AppBus의 slot('filters')에 싣는다.
// 무엇을 기억하고 무엇이 예외인지는 명세(docs/명세-3단계/06-상세-검색-필터-도구.md 6-3 · 6-4 · 9절 ㈐-16 · 18)를 그대로 따랐고,
// 값의 이름과 기본값은 지금 연표의 ht.ui(js/viewer.js:24 · js/core.js의 HT.SHOW_DEFAULTS)와 같다.

/// 칩 묶음 넷. 트랙 · 분류는 저장소의 번호지만, 저장된 설정의 열쇠와 같게 모두 글자로 적어 둔다.
enum ChipGroup { tracks, categories, kinds, historicity }

/// 목록 상자 한 줄: 기억되는 값과 사람이 읽는 이름.
@immutable
class FilterOption<T> {
  const FilterOption(this.value, this.name);
  final T value;
  final String name;
}

/// 중요도 — 사건과 인물에 함께 걸린다.
const importanceOptions = <FilterOption<int>>[
  FilterOption(1, '모든 사건'),
  FilterOption(2, '보통 이상'),
  FilterOption(3, '중요 사건만'),
];

/// 띠 밀도. 조감(2)은 줄을 띠 하나 높이로 줄여 한눈에 본다.
const densityOptions = <FilterOption<int>>[
  FilterOption(-1, '넉넉하게'),
  FilterOption(0, '자동'),
  FilterOption(1, '빽빽하게'),
  FilterOption(2, '조감'),
];

/// 조감에서 띠 안에 남길 것.
const birdShapeOptions = <FilterOption<String>>[
  FilterOption('a', '이름 + 점'),
  FilterOption('b', '이름만'),
  FilterOption('c', '띠 · 선만'),
];

/// 지도자 칸에 무엇을 적을지 — 지금 연표의 HT.LEADER_LABELS 그대로.
const leaderLabelOptions = <FilterOption<String>>[
  FilterOption('auto', '기본 이름'),
  FilterOption('temple', '묘호'),
  FilterOption('title', '시호'),
  FilterOption('given', '이름'),
  FilterOption('temple-title', '묘호·시호'),
  FilterOption('all', '모두'),
];

/// 표시 체크 한 칸: 열쇠 · 글 · 설명(올리면 뜨는 말).
@immutable
class ShowToggle {
  const ShowToggle(this.key, this.label, this.hint);
  final String key, label, hint;
}

/// 띠 안 묶음 — 끄면 그 단이 사라져 줄을 다시 쌓는다(가문만 칠이라 다시 쌓지 않는다).
const bandToggles = <ShowToggle>[
  ShowToggle('dynasties', '왕조', '띠 맨 위에 왕조 칸을 보여 줍니다 (왕조를 적은 나라만)'),
  ShowToggle('leaders', '지도자', '띠 위쪽에 지도자 칸을 보여 줍니다'),
  ShowToggle('cabinets', '내각', '지도자 칸 아래에 내각 칸을 보여 줍니다'),
  ShowToggle('phases', '시기', "띠 안 지도자 칸 위에 후대 학계의 시기 구분을 보여 줍니다 — 날짜 칸의 '시대 구분'과는 다른 것입니다. '빽빽하게' · '조감'에서는 숨습니다"),
  ShowToggle('ranks', '지위', "지위가 바뀐 나라는 띠 안에 지위 단을, 지위가 하나뿐인 나라는 책갈피 탭에 작은 딱지를 보여 줍니다. '빽빽하게' · '조감'에서는 숨습니다"),
  // 단체(10건 7 — 감독 선택 D5 결정 1 A · 2 · 3 C): 집권 단 · 실권 단 · 명목 지도자 · 연합의 겹 탭. 웹 필터의 '단체' 체크(HT.SHOW_DEFAULTS.groups)와 같은 열쇠.
  ShowToggle('groups', '단체', "띠 안 지도자 칸 위에 그때 집권한 단체와 실권을 쥔 집단의 칸을, 띠 위 탭 줄에 연합의 겹 탭을 보여 줍니다 (단체를 적은 나라만). '빽빽하게' · '조감'에서는 칸이 숨습니다"),
  ShowToggle('figures', '인물', '띠 안, 기간 막대 아래에 그 나라에서 활동한 인물의 활동 막대를 보여 줍니다 (중요도 필터를 따름)'),
  ShowToggle('houses', '가문', '지도자 칸 아래쪽에 그 지도자의 가문 색 줄을 긋습니다 (같은 가문이 이어지는 동안 한 줄)'),
];

/// 날짜 칸 묶음 — 맨 위 날짜 칸의 줄을 끈다.
const axisToggles = <ShowToggle>[
  ShowToggle('ganji', '간지', '맨 위 날짜 칸에 간지(육십갑자) 줄을 보여 줍니다'),
  ShowToggle('eras', '연호', '맨 위 날짜 칸에 연호 묶음 줄을 보여 줍니다'),
  ShowToggle('capitals', '도읍', '맨 위 날짜 칸에 도읍 묶음 줄을 보여 줍니다'),
  ShowToggle('epochs', '시대 구분', '맨 위 날짜 칸에 나라별 시대 구분 띠를 보여 줍니다'),
];

/// 이름을 바꾼 DLC의 날짜 줄 제목을 필터에도 쓴다. 끔을 다시 켜면 내장 육십갑자다.
List<ShowToggle> axisTogglesFor(YearCycle? cycle) => cycle?.custom == true ? [
  ShowToggle('ganji', cycle!.title, '맨 위 날짜 칸에 ${cycle.title} 줄을 보여 줍니다'),
  ...axisToggles.skip(1),
] : axisToggles;

/// 선·견해 묶음. '이설'만 show가 아니라 [FilterState.showAlt]에 든다(지금 연표의 ui.showAlt와 같은 자리).
const lineToggles = <ShowToggle>[
  ShowToggle('succession', '승계선', '건국·멸망 네모를 잇는 승계선(직접 실선 · 간접 점선)을 보여 줍니다'),
  ShowToggle('partOf', '소속선', '연맹의 구성국·종속국·조직체를 상위 정권과 잇는 세로 점선을 보여 줍니다'),
  ShowToggle('showAlt', '이설', '학자·사료마다 다른 연대를 함께 표시합니다 — 사건 · 시대의 점선 표식, 칸의 유령 구분선'),
  ShowToggle('spotEcho', '같은 시기를 타국에도', '칸이나 인물을 골라 그 기간이 조명될 때, 그때 있던 타국의 띠도 그 기간만큼은 조명과 같은 짙기로 칠하고 그 시기 타국의 사건도 밝게 남깁니다'),
];

@immutable
class FilterState {
  const FilterState({
    this.tracksOff = const <String>{},
    this.categoriesOff = const <String>{},
    this.kindsOff = const <String>{},
    this.historicityOff = const <String>{},
    this.scopes = const <String, bool>{},
    this.minImportance = 1,
    this.lens = '',
    this.density = 0,
    this.birdShape = 'a',
    this.birdAuto = false,
    this.birdFrom = 0,
    this.showAlt = true,
    this.show = showDefaults,
    this.leaderLabel = 'auto',
    this.leaderOrdinal = false,
    this.filterOpen = false,
  });

  /// 표시 체크의 기본값 — 지금 연표의 HT.SHOW_DEFAULTS에서 날짜 칸의 간지 · 연호 · 도읍만 끔(리메이크 2부 — 목업 날짜 칸은 연도 · 시대뿐).
  /// 저장된 값에 없는 열쇠는 여기 값으로 채운다(뒤에 생긴 표시가 옛 설정을 쓰는 사람에게 꺼진 채로 나오지 않게).
  static const showDefaults = <String, Object>{
    'dynasties': true, 'leaders': true, 'cabinets': true, 'eras': false, 'capitals': false, 'ganji': false, 'epochs': true,
    'succession': true, 'partOf': true, 'spotEcho': false, 'figures': true, 'phases': true, 'ranks': true, 'houses': false,
    'groups': true,
  };

  /// **끈 것만** 담는다 — 적히지 않은 것은 켜진 것이다(지금 연표의 `ui.tracks[id] !== false`와 같은 규칙).
  final Set<String> tracksOff, categoriesOff, kindsOff, historicityOff;

  /// 대범위 모아 보기. 거르기가 아니라 모아 보기라서, 적힌 것만 사람이 정한 값이고 없으면 그 대범위의 기본값을 따른다.
  final Map<String, bool> scopes;

  /// 1 모든 사건 · 2 보통 이상 · 3 중요 사건만.
  final int minImportance;

  /// 관점: '' 기본 · 'local' 나라마다 제 이름 · 그 밖은 트랙 번호를 적은 글.
  final String lens;

  /// −1 넉넉하게 · 0 자동 · 1 빽빽하게 · 2 조감.
  final int density;

  /// 조감 모양 a · b · c와 '축소하면 조감', 그리고 조감으로 들어가기 직전의 밀도(↕ · V가 되돌아갈 자리).
  final String birdShape;
  final bool birdAuto;
  final int birdFrom;

  /// 이설(다른 견해)을 함께 보이는가.
  final bool showAlt;

  /// 표시 체크 묶음. 값은 참/거짓이고 **승계선만 세 값**이다(true · 'direct' · false — 'direct'는 메뉴에서만 고른다).
  final Map<String, Object> show;

  final String leaderLabel;
  final bool leaderOrdinal;

  /// 필터 시트가 열려 있는가 — 이것도 기억한다(명세 6-4).
  final bool filterOpen;

  // ---- 칩 ----

  Set<String> offOf(ChipGroup group) => switch (group) {
    ChipGroup.tracks => tracksOff,
    ChipGroup.categories => categoriesOff,
    ChipGroup.kinds => kindsOff,
    ChipGroup.historicity => historicityOff,
  };

  bool chipOn(ChipGroup group, String id) => !offOf(group).contains(id);

  /// 눌러 켜고 끄기.
  FilterState toggleChip(ChipGroup group, String id) {
    final off = {...offOf(group)};
    if (!off.remove(id)) off.add(id);
    return _withOff(group, off);
  }

  /// Alt+클릭 — 그 묶음에서 지금 보이는 칩([all]) 가운데 누른 것만 켜고 나머지는 끈다.
  /// 보이지 않는 칩의 저장값은 건드리지 않는다(실재성 칩의 예외와 같은 까닭).
  FilterState onlyChip(ChipGroup group, String id, Iterable<String> all) {
    final off = {...offOf(group)}..removeAll(all);
    off.addAll(all.where((x) => x != id));
    return _withOff(group, off);
  }

  /// 실재성의 예외(명세 6-4 · 9절 ㈐-16): 저장된 "끔"은 **지금 칩 줄에 보이는 것만** 센다.
  /// 실재성을 쓰던 자료집을 꺼서 칩 줄이 사라졌는데 끔이 남아 나라가 모두 숨는 일을 막는다(저장값은 지우지 않는다).
  Set<String> historicityOffAmong(Iterable<String> shown) => {for (final id in shown) if (historicityOff.contains(id)) id};

  /// 대범위 모아 보기의 지금 값. 사람이 정한 적이 없으면 [fallback](그 대범위의 기본값).
  bool scopeOn(String uid, {bool fallback = false}) => scopes[uid] ?? fallback;

  FilterState toggleScope(String uid, {bool fallback = false}) => copyWith(scopes: {...scopes, uid: !scopeOn(uid, fallback: fallback)});

  // ---- 표시 체크 ----

  /// 켜졌는가. 승계선의 'direct'(직접 승계만)도 켜진 것으로 센다 — 체크 상자는 켬/끔 둘뿐이다.
  bool showing(String key) => key == 'showAlt' ? showAlt : (show[key] ?? showDefaults[key]) != false;

  /// 적힌 값 그대로(승계선은 true · 'direct' · false).
  Object showValue(String key) => show[key] ?? showDefaults[key] ?? false;

  /// 체크를 눌렀을 때. 'direct'였던 승계선을 끄면 false, 다시 켜면 true가 된다(지금 연표와 같다).
  FilterState withShowing(String key, bool on) => key == 'showAlt' ? copyWith(showAlt: on) : copyWith(show: {...show, key: on});

  FilterState withShowValue(String key, Object value) => copyWith(show: {...show, key: value});

  /// 밀도 고르기 — 조감으로 들어갈 때 직전 밀도를 기억한다(명세 9절 ㈐-18).
  FilterState withDensity(int value) {
    final v = const [-1, 0, 1, 2].contains(value) ? value : 0;
    return copyWith(density: v, birdFrom: v == 2 && density != 2 ? density : birdFrom);
  }

  /// 띠 안의 단 켬/끔과 밀도를 연표의 보기 조건으로. 가문은 칠만 바꾸므로 여기 없다.
  ViewConditions toConditions() => ViewConditions(
    dynasties: showing('dynasties'),
    leaders: showing('leaders'),
    cabinets: showing('cabinets'),
    phases: showing('phases'),
    ranks: showing('ranks'),
    figures: showing('figures'),
    groups: showing('groups'),
    density: density,
    // 조감의 모양(a 이름+점 · b 이름만 · c 띠·선만). '축소하면 조감'(birdAuto)은 여기 싣지 않는다 — 보기 조건의 autoBird는
    // '지금 자동 조감이 걸려 있는가'(장면이 정착 때 판정)이고, 켬/끔은 이어 붙이기가 장면의 자동 조감 스위치로 잇는다.
    birdShape: switch (birdShape) {
      'b' => BirdShape.b,
      'c' => BirdShape.c,
      _ => BirdShape.a,
    },
  );

  /// 필터 값이 아직 없을 때(필터 시트를 연 적이 없는 기억) 앱이 필터 값을 처음 지어야 하면 — 켠 그릇을 필터 기억에 적을 때(과제 7 걸음 5 결함 ㉢) —
  /// 기본값이 아니라 **지금 보기 조건**에서 시작한다: 켠 단 · 밀도 · 조감 모양은 [conditions](기억의 `ui.show` · `ui.density`가 이미 넣은 값)에서,
  /// 조감에 들기 직전 밀도는 [birdFrom](기억의 `ui.birdFrom`)에서. [toConditions]로 되돌리면 [conditions]와 같다(`autoBird`는 장면의 판정이라 빼고).
  /// 기본값(밀도 0)에서 시작하면 다음 실행에 기억을 이을 때(`AppGlue.attachMemory`) 그 값이 보기 조건을 덮어 조감 · 켠 단을 한 번 잃었다(검토 고침).
  /// 나머지(칩 · 중요도 · 조건에 없는 표시)는 기본값 그대로 — 시트를 연 적이 없으면 그 값이 쓰이고 있다.
  factory FilterState.fromConditions(ViewConditions conditions, {int birdFrom = 0}) => FilterState(
    density: conditions.density,
    birdFrom: birdFrom,
    birdShape: switch (conditions.birdShape) {
      BirdShape.b => 'b',
      BirdShape.c => 'c',
      BirdShape.a => 'a',
    },
    show: {
      ...showDefaults,
      'dynasties': conditions.dynasties,
      'leaders': conditions.leaders,
      'cabinets': conditions.cabinets,
      'phases': conditions.phases,
      'ranks': conditions.ranks,
      'figures': conditions.figures,
      'groups': conditions.groups,
    },
  );

  // ---- 기억 ----

  Map<String, dynamic> toJson() => {
    'tracks': _offJson(tracksOff),
    'categories': _offJson(categoriesOff),
    'kinds': _offJson(kindsOff),
    'historicity': _offJson(historicityOff),
    'scopes': {for (final key in scopes.keys.toList()..sort()) key: scopes[key]},
    'minImportance': minImportance,
    'lens': lens,
    'density': density,
    'birdShape': birdShape,
    'birdAuto': birdAuto,
    'birdFrom': birdFrom,
    'showAlt': showAlt,
    'show': {for (final key in show.keys.toList()..sort()) key: show[key]},
    'leaderLabel': leaderLabel,
    'leaderOrdinal': leaderOrdinal,
    'filterOpen': filterOpen,
  };

  /// 모르는 열쇠는 무시하고, 없는 것과 값이 어긋난 것은 기본값으로 읽는다.
  factory FilterState.fromJson(Map<String, dynamic> json) {
    final show = <String, Object>{...showDefaults};
    final rawShow = json['show'];
    if (rawShow is Map) {
      for (final e in rawShow.entries) {
        final key = '${e.key}';
        if (!showDefaults.containsKey(key)) continue;
        final v = e.value;
        if (v is bool) {
          show[key] = v;
        } else if (key == 'succession' && v == 'direct') {
          show[key] = 'direct';
        }
      }
    }
    final density = _oneOf(json['density'], const [-1, 0, 1, 2], 0);
    return FilterState(
      tracksOff: _off(json['tracks']),
      categoriesOff: _off(json['categories']),
      kindsOff: _off(json['kinds']),
      historicityOff: _off(json['historicity']),
      scopes: json['scopes'] is Map ? {for (final e in (json['scopes'] as Map).entries) if (e.value is bool) '${e.key}': e.value as bool} : const {},
      minImportance: _oneOf(json['minImportance'], const [1, 2, 3], 1),
      lens: json['lens'] is String ? json['lens'] as String : '',
      density: density,
      birdShape: birdShapeOptions.any((o) => o.value == json['birdShape']) ? json['birdShape'] as String : 'a',
      birdAuto: json['birdAuto'] == true,
      birdFrom: _oneOf(json['birdFrom'], const [-1, 0, 1], 0),
      showAlt: json['showAlt'] != false,
      show: show,
      leaderLabel: leaderLabelOptions.any((o) => o.value == json['leaderLabel']) ? json['leaderLabel'] as String : 'auto',
      leaderOrdinal: json['leaderOrdinal'] == true,
      filterOpen: json['filterOpen'] == true,
    );
  }

  FilterState copyWith({
    Set<String>? tracksOff,
    Set<String>? categoriesOff,
    Set<String>? kindsOff,
    Set<String>? historicityOff,
    Map<String, bool>? scopes,
    int? minImportance,
    String? lens,
    int? density,
    String? birdShape,
    bool? birdAuto,
    int? birdFrom,
    bool? showAlt,
    Map<String, Object>? show,
    String? leaderLabel,
    bool? leaderOrdinal,
    bool? filterOpen,
  }) => FilterState(
    tracksOff: tracksOff ?? this.tracksOff,
    categoriesOff: categoriesOff ?? this.categoriesOff,
    kindsOff: kindsOff ?? this.kindsOff,
    historicityOff: historicityOff ?? this.historicityOff,
    scopes: scopes ?? this.scopes,
    minImportance: minImportance ?? this.minImportance,
    lens: lens ?? this.lens,
    density: density ?? this.density,
    birdShape: birdShape ?? this.birdShape,
    birdAuto: birdAuto ?? this.birdAuto,
    birdFrom: birdFrom ?? this.birdFrom,
    showAlt: showAlt ?? this.showAlt,
    show: show ?? this.show,
    leaderLabel: leaderLabel ?? this.leaderLabel,
    leaderOrdinal: leaderOrdinal ?? this.leaderOrdinal,
    filterOpen: filterOpen ?? this.filterOpen,
  );

  FilterState _withOff(ChipGroup group, Set<String> off) => switch (group) {
    ChipGroup.tracks => copyWith(tracksOff: off),
    ChipGroup.categories => copyWith(categoriesOff: off),
    ChipGroup.kinds => copyWith(kindsOff: off),
    ChipGroup.historicity => copyWith(historicityOff: off),
  };

  /// 끈 것만 `{"열쇠": false}`로 적는다 — 지금 연표가 남긴 설정과 같은 모양이다.
  static Map<String, bool> _offJson(Set<String> off) => {for (final id in off.toList()..sort()) id: false};

  /// 끈 것 읽기: `{"3": false}` 꼴도, 끈 것만 적은 목록도 읽는다.
  static Set<String> _off(Object? raw) {
    if (raw is Map) return {for (final e in raw.entries) if (e.value == false) '${e.key}'};
    if (raw is List) return {for (final v in raw) '$v'};
    return const {};
  }

  static int _oneOf(Object? raw, List<int> allowed, int fallback) {
    final v = raw is num ? raw.toInt() : null;
    return v != null && allowed.contains(v) ? v : fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is FilterState &&
      setEquals(other.tracksOff, tracksOff) &&
      setEquals(other.categoriesOff, categoriesOff) &&
      setEquals(other.kindsOff, kindsOff) &&
      setEquals(other.historicityOff, historicityOff) &&
      mapEquals(other.scopes, scopes) &&
      other.minImportance == minImportance &&
      other.lens == lens &&
      other.density == density &&
      other.birdShape == birdShape &&
      other.birdAuto == birdAuto &&
      other.birdFrom == birdFrom &&
      other.showAlt == showAlt &&
      mapEquals(other.show, show) &&
      other.leaderLabel == leaderLabel &&
      other.leaderOrdinal == leaderOrdinal &&
      other.filterOpen == filterOpen;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(tracksOff),
    Object.hashAllUnordered(categoriesOff),
    Object.hashAllUnordered(kindsOff),
    Object.hashAllUnordered(historicityOff),
    Object.hashAllUnordered(scopes.entries.map((e) => Object.hash(e.key, e.value))),
    minImportance,
    lens,
    density,
    birdShape,
    birdAuto,
    birdFrom,
    showAlt,
    Object.hashAllUnordered(show.entries.map((e) => Object.hash(e.key, e.value))),
    leaderLabel,
    leaderOrdinal,
    filterOpen,
  );
}
