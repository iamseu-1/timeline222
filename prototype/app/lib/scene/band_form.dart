// 띠의 form(스키마 4 · 타일 띠 구역의 열 10 — 계약 5절 띠 행(엔진 tile.rs와 같은 규칙) — 진짜 엔진 대조 schema4_real_engine_test가 지킴)을
// 형식 4의 종류 · 관계 · 정통성 · 중요도로 푼다.
// 약속은 docs/계약-아카이브-3단계.md 6-1 가의 비트 표(스키마 4 · 1-1)이고, 값을 짓는 쪽은 prototype/scripts/export/bands.mjs의 formOf다
// (번호표 TYPE_NO · REL_NO · STATUS_NO의 거울). 그림판과 떨어진 순수 풀개다 — 3단계의 앱은 이 값을 모델에 받기만 하고,
// 그림은 지금처럼 띠의 look(그림 갈래 0 ~ 22)을 본다(계획 정한 것 #14 · 그림은 4단계).
//
// 비트: 0 ~ 4 종류 + 1(0 = 모름) · 5 ~ 9 관계(0 = 없음) · 10 ~ 12 정통성 + 1(0 = 비움) · 13 ~ 15 중요도 + 1(0 = 비움).
// 16비트 위는 쓰지 않는다(읽을 때 무시).

/// form 비트의 풀개. 모든 값은 번호이고, id는 아래 표로 바꾼다.
abstract final class BandForm {
  /// 형식 4 종류(19개) — 번호 = 차례. bands.mjs TYPE_NO의 차례(계약 6-1 가 · 설계 3-11의 번호).
  static const types = <String>[
    'state', 'federation', 'principality', 'city', 'government', 'regime', 'dependency', 'warlord', 'organization',
    'faith', 'order', 'company', 'office', 'group', 'era', 'realm', 'union', 'league', 'person',
  ];

  /// 관계(0 ~ 17) — 번호 = 차례, 0은 없음('').
  /// 1 ~ 13은 bands.mjs REL_NO(옛 종속 kind), 14 명목상 · 15 구성국 · 16 동군연합은 js/core.js HT.RELATIONS의 id.
  /// 17 공동 통치는 계약에 자리만 있고 관계 id가 아직 없어 ''로 둔다(번호 17은 [relationOf]로 그대로 읽힌다).
  static const relations = <String>[
    '', 'tributary', 'fief', 'dominion', 'vassal', 'protectorate', 'satellite', 'puppet', 'mandate', 'colony', 'occupied',
    'client', 'frontier', 'prefecture', 'nominal', 'member', 'union', '',
  ];

  /// 정통성(6개) — 번호 = 차례. bands.mjs STATUS_NO(= HT.F4 STATUSES)의 차례.
  static const legits = <String>['legit', 'rival', 'joint', 'regent', 'nominal', 'claim'];

  /// 형식 4 종류 번호(0 ~ 18). −1 = 모름(옛 저장소 · 객체가 아닌 그림 띠 — 바탕 문화 · 기관 · 왕조).
  static int typeOf(int form) => (form & 0x1f) - 1;

  /// 관계 번호(0 ~ 17). 0 = 없음.
  static int relationOf(int form) => (form >> 5) & 0x1f;

  /// 정통성 번호(0 ~ 5). −1 = 비움.
  static int legitOf(int form) => ((form >> 10) & 7) - 1;

  /// 중요도(0 ~ 3). −1 = 비움(기간 길이로 짐작하는 자리).
  static int importanceOf(int form) => ((form >> 13) & 7) - 1;

  /// 한 번에 푼 넷.
  static ({int type, int relation, int legit, int importance}) parts(int form) => (
    type: typeOf(form),
    relation: relationOf(form),
    legit: legitOf(form),
    importance: importanceOf(form),
  );

  /// 종류 번호 → id. 모름(−1)이나 표 밖의 번호는 ''.
  static String typeId(int type) => _at(types, type);

  /// 관계 번호 → id. 없음(0) · 공동 통치(17 — id 없음) · 표 밖의 번호는 ''.
  static String relationId(int relation) => _at(relations, relation);

  /// 정통성 번호 → id. 비움(−1)이나 표 밖의 번호는 ''.
  static String legitId(int legit) => _at(legits, legit);

  static String _at(List<String> table, int i) => i >= 0 && i < table.length ? table[i] : '';
}
