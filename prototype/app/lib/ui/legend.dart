import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scene/layout.dart' show SceneLayout, SphereLine, VariantInfo;
import '../scene/paint/bands.dart' show BandKind, BandLook, TagEnd, TagLook;
import '../scene/viewport.dart' show SceneView;
import '../shell/motion_widgets.dart';
import '../shell/sheet_look.dart';
import '../shell/sheet_parts.dart';
import 'app_bus.dart';
import 'legend_marks.dart';
import 'shell_keys.dart';

export 'legend_marks.dart' show LegendLook, LegendMark, LegendRow, LegendSample, LegendTint, legendSampleHeight;

// 범례(명세 06의 7-3). `❔` · `L`로 왼쪽 아래에 연다. **지금 자료에 쓰인 것만** 그린다 —
// 자료(켠 자료집 · 필터)가 바뀌면 열려 있는 동안 다시 묻는다.
//
// 혼자 서는 부품이라 [AppBus]만 받는다:
//   `bus.slot('command')` — 단축키 · 메뉴의 [Cmd.legend]가 오면 여닫는다(`❔` · `L`).
//   `bus.slot('legend')` = bool — 열고 닫기. 앱 틀이 기억해 둔 값을 여기에 넣어 두면 그대로 열린 채 시작한다.
//   `bus.ask({'op':'legend_kinds'})` — 지금 자료에 쓰인 종류 · 확실성 · 실재성 · 있고 없음.
//   `bus.scene.layout` — 문화권의 사람 띠 줄 · 그릇(대범위) 목록(앱이 아는 것 — 쓰였을 때만 그 줄).
//   `bus.slot('legendSpot')` = [LegendSpot]? — 열린 폴더의 자리(움직임 계측기가 비키고, 오른쪽 클릭 차림표가 그 위에서는 열리지 않는다).
// 상세 창(또는 같은 해 보기)이 열려 있으면 폭이 줄다가 한 열로, 창 폭이 860보다 좁으면 숨는다 — `bus.selection`과 `bus.slot('yearPanel')`로 안다.
//
// 꼴(리메이크 4단계 — 감독 고름 G5 #9 다듬기 판의 범례 · 목업 g-sheet-search `drawLegend`): 왼쪽 아래의 서고 폴더 '범례 {줄 수}'(오른쪽 끝 닫기 탭) 안에
// 두 열의 상자(꼬리표 · 꼬리표 안 · 실 · 받침 · 그릇)와 두 열에 걸친 상자 '정통성'. 줄 = 왼쪽 견본(그림판 제 크기 — [LegendSample]) + 이름 13 굵게 + 설명 12 먹 60.
// 짧은 열은 줄 사이를 고루 늘려 두 열 바닥을 맞춘다. 휴대폰은 한 열이다. 앞 범례의 묶음(정권 띠 · 정권 종류 · 실재성 · 대범위 · 건국·멸망·승계·소속 · 사건 · 칸)은
// 상자 안의 작은 묶음 이름으로 남기고, 줄 글은 '이름 — 설명'으로 나눠 하나도 빼지 않는다.

/// `bus.slot(…)`의 이름: 범례 열기.
const legendSlot = 'legend';

/// `bus.slot(…)`의 이름: 열린 범례 폴더의 자리([LegendSpot] — 닫히면 null).
const legendSpotSlot = 'legendSpot';

/// 열린 범례 폴더의 자리 — [local]은 범례가 선 자리(연표를 덮는 `Positioned.fill`) 안, [global]은 화면 전체.
@immutable
class LegendSpot {
  const LegendSpot(this.local, this.global);
  final Rect local, global;

  @override
  bool operator ==(Object other) => other is LegendSpot && other.local == local && other.global == global;

  @override
  int get hashCode => Object.hash(local, global);
}

/// 범례 상자 안의 작은 묶음(앞 범례의 묶음 — 제목이 비면 상자 맨 위의 새 줄들).
@immutable
class LegendGroup {
  const LegendGroup(this.title, this.rows);
  final String title;
  final List<LegendRow> rows;
}

/// 범례 상자 하나(뚜껑의 흰 라벨 + 줄 수). [wide]면 두 열에 걸친다(정통성).
@immutable
class LegendBox {
  const LegendBox(this.title, this.groups, {this.wide = false});
  final String title;
  final List<LegendGroup> groups;
  final bool wide;

  List<LegendRow> get rows => [for (final g in groups) ...g.rows];
}

/// `{"op":"legend_kinds"}`의 답 — 지금 자료에 무엇이 쓰였는가. 앱이 배치에서 아는 것([persons] · [containers] · [nested])은 [withLayout]이 채운다.
@immutable
class LegendFacts {
  const LegendFacts({
    this.kinds = const [],
    this.certainty = const [],
    this.historicity = const [],
    this.has = const {},
    this.persons = false,
    this.containers = false,
    this.nested = false,
  });

  /// 쓰인 정권 종류(계약 6-1의 종류 번호 차례 · 0 국가는 늘 있다).
  final List<LegendKind> kinds;

  /// 쓰인 연대의 확실성 0 확실 · 1 통설 · 2 추정 · 3 전승.
  final List<int> certainty;

  /// 쓰인 실재성 1 반전설 · 2 전설 · 3 실재 논쟁 · 4 부정됨(0 실재는 빼고).
  final List<int> historicity;

  /// 조건부 줄의 있고 없음(`range` · `unknown` · `scope` · `hollow` · `revival` · `partial` · `join` ·
  /// `depOut` · `depIn` · `figure` · `cellAlt` · `cellFuzzy` · `phase` · `rank` · `treaty` · `cats` · `culture` · `zone`).
  final Map<String, bool> has;

  /// 문화권 단위 줄에 사람 띠가 있는가 · 그릇(대범위 변형)이 있는가 · 그릇 안의 그릇(상자)이 있는가 — 배치(layout)에서.
  final bool persons, containers, nested;

  bool got(String key) => has[key] == true;

  /// 배치가 아는 것(사람 띠 줄 · 그릇 목록)을 더한 값.
  LegendFacts withLayout(SceneLayout? layout) {
    if (layout == null) return this;
    final scopes = [for (final v in layout.variants) if (v.kind == VariantInfo.kindScope) v];
    return LegendFacts(
      kinds: kinds,
      certainty: certainty,
      historicity: historicity,
      has: has,
      persons: layout.sphereLines.any((l) => l.kind == SphereLine.person),
      containers: scopes.isNotEmpty,
      nested: scopes.any((v) => v.within?.isNotEmpty ?? false),
    );
  }

  static LegendFacts fromJson(Map<String, dynamic> j) => LegendFacts(
    kinds: [
      for (final k in _list(j['kinds']))
        if (k is Map) LegendKind.fromJson(k.map((a, b) => MapEntry('$a', b))),
    ],
    certainty: [
      for (final c in _list(j['certainty']))
        if (c is num) c.toInt(),
    ],
    // 자료 처리부는 필터 시트가 읽는 꼴([{id, name}])로 주고 옛 정수 목록은 historicity_ids에 함께 싣는다 — 어느 쪽이 와도 읽는다.
    historicity: [
      for (final h in _list(j['historicity_ids'] ?? j['historicity']))
        if (h is num) h.toInt() else if (h is Map && h['id'] is num) (h['id'] as num).toInt() else if (h is Map && int.tryParse('${h['id']}') != null) int.parse('${h['id']}'),
    ],
    has: {for (final e in (j['has'] is Map ? (j['has'] as Map).entries : const <MapEntry<Object?, Object?>>[])) '${e.key}': e.value == true},
  );
}

/// 쓰인 정권 종류 한 가지.
@immutable
class LegendKind {
  const LegendKind({required this.kind, required this.name, this.hint = '', this.dep = false});

  /// 계약 6-1의 종류 번호.
  final int kind;
  final String name, hint;

  /// 종속 갈래인가(제 띠는 옅은 띠 하나 — 둘 이상 쓰였으면 한 줄로 묶는다).
  final bool dep;

  /// 견본 꼬리표의 띠 look(종류 + 종속 갈래 비트).
  int get look => kind | (dep ? BandLook.famDep : 0);

  static LegendKind fromJson(Map<String, dynamic> j) => LegendKind(
    kind: j['kind'] is num ? (j['kind'] as num).toInt() : 0,
    name: '${j['name'] ?? kindNames[j['kind'] is num ? (j['kind'] as num).toInt().clamp(0, kindNames.length - 1) : 0]}',
    hint: '${j['hint'] ?? ''}',
    dep: j['dep'] == true,
  );
}

/// 종류 번호 → 이름(계약 6-1). 자료가 이름을 주지 않을 때의 대비책이다.
const kindNames = [
  '국가', '조공·책봉국', '봉국·제후국', '자치령', '군벌·할거 세력', '종속국', '보호국', '위성국', '괴뢰국', '위임·신탁 통치령',
  '식민지·속령', '점령지·군정', '연맹', '조직체', '시대 이름', '망명 정부', '부흥·저항 세력', '문화', '기관', '왕조',
  '복속 세력·부용', '기미·번부·토사', '직할령·군현', // 묶음 3 · 3번(2026-09-22) — 종류 번호 20~22
];

List<dynamic> _list(Object? v) => v is List ? v : const [];

const _accepted = BandLook.certAccepted << BandLook.certShift;
int _cert(int c) => c << BandLook.certShift;
int _hs(int h) => _accepted | h << BandLook.hsShift;

/// 쓰인 것만 남긴 범례의 상자를 짓는다 — 꼬리표 · 꼬리표 안 · 실 · 받침 · 그릇(쓰였을 때만) · 정통성(늘).
/// 상자마다 맨 위에 그림판의 서고 장치 줄(꼬리표 끝 · 칸 층 · 실권 밑줄 · 빌린 직위 · 승계 실 · 섬김 받침 · 사람 띠 · 폴더 · 상자 · 접힌 상자)을 두고,
/// 그 아래에 앞 범례의 묶음을 명세 7-3의 차례 그대로 옮겨 담는다(정권 띠 → 정권 종류 → 실재성 · 사건 → 칸 · 건국·멸망·승계·소속 · 대범위).
List<LegendBox> buildLegend(LegendFacts f) {
  final keyNames = [for (final k in f.kinds) if (TagLook.endOf(k.kind) == TagEnd.key) k.name];
  final plainKinds = [for (final k in f.kinds) if (TagLook.endOf(k.kind) == TagEnd.plain) k];
  final deps = f.kinds.where((k) => k.dep).toList();

  final tags = LegendBox('꼬리표', [
    LegendGroup('', [
      const LegendRow(LegendMark.tag, '다스림', '왼쪽 두 귀 모따기 · 구멍', look: _accepted),
      if (keyNames.isNotEmpty) LegendRow(LegendMark.tag, '영토 밖', '둥근 끝 · ${keyNames.join(' · ')}', look: BandKind.movement | _accepted, rgb: LegendTint.mocha, label: keyNames.first),
      if (plainKinds.isNotEmpty)
        LegendRow(LegendMark.tag, '무리', '직각 · 테 없음 · ${plainKinds.map((k) => k.name).join(' · ')}', look: plainKinds.first.look | _accepted, rgb: LegendTint.sand, label: plainKinds.first.name),
    ]),
    LegendGroup('정권 띠', [
      const LegendRow(LegendMark.tag, '통설 연대', '기본', look: _accepted),
      if (f.certainty.contains(2)) LegendRow(LegendMark.tag, '추정 연대', '옅은 실선 테두리', look: _cert(2)),
      if (f.certainty.contains(3)) LegendRow(LegendMark.tag, '전승 연대', '빗금', look: _cert(3)),
      if (f.got('range')) const LegendRow(LegendMark.tagRange, '연대 폭', '연대 폭이 있는 구간만 무늬', look: _accepted),
      if (f.got('unknown')) const LegendRow(LegendMark.tagUnknown, '연도 미정', '그쪽 끝이 둥글게 사라짐', look: _accepted),
    ]),
    // 정권 종류: 종속 갈래가 둘 이상이면 옅은 띠 한 줄로 묶는다(제 띠의 모양이 모두 같기 때문).
    LegendGroup('정권 종류', [
      for (final k in f.kinds)
        if (!k.dep || deps.length == 1)
          LegendRow(LegendMark.tag, k.name, k.hint.isEmpty ? '' : k.hint.split(' — ').last, look: k.look | _accepted, label: k.name)
        else if (k == deps.first)
          LegendRow(
            LegendMark.tag,
            '종속 갈래',
            '옅은 띠 (${deps.map((d) => d.name).join(' · ')}). 누구를 어떻게 섬겼는지는 상국 띠의 이름표로',
            look: k.look | _accepted,
            label: k.name,
          ),
    ]),
    if (f.historicity.isNotEmpty)
      LegendGroup('실재성 — 나라가 있었는가 (연대의 확실성과는 따로)', [
        if (f.historicity.contains(1)) LegendRow(LegendMark.tag, '반전설', '이름 띠를 한 단 옅은 색으로 · 옅은 실선 테 · 탭에 “반전설”', look: _hs(1)),
        if (f.historicity.contains(2)) LegendRow(LegendMark.tag, '전설', '이름 띠를 두 단 옅은 색으로 · 옅은 실선 테 · 탭 이름이 기울어짐 · 탭에 “전설”', look: _hs(2)),
        if (f.historicity.contains(3)) LegendRow(LegendMark.tag, '실재 논쟁', '보통 띠 · 탭에 “논쟁”', look: _hs(3)),
        if (f.historicity.contains(4)) LegendRow(LegendMark.tag, '부정됨', '전설과 같은 옅은 칠을 색 없이 회색으로 · 탭 이름에 취소선 · 이어진 승계선이 옅어짐 · 탭에 “부정”', look: _hs(4)),
      ]),
  ]);

  final inside = LegendBox('꼬리표 안', [
    const LegendGroup('', [
      LegendRow(LegendMark.floor, '지도자 · 직위 층', '머리 아래 층 · 칸 사이 금', look: _accepted),
      LegendRow(LegendMark.power, '실권', '쥔 쪽 색 밑줄 + 쥔 쪽 이름', look: _accepted),
      LegendRow(LegendMark.borrow, '빌린 직위', '칸 윗변 파선 · 출처는 이름 뒤', look: _accepted),
    ]),
    LegendGroup('사건', [
      const LegendRow(LegendMark.event, '점', '확실·통설 연대의 사건'),
      const LegendRow(LegendMark.eventHollow, '빈 점', '추정·전승 연대, 또는 여러 나라가 함께 겪은 사건(속 빈 점)'),
      if (f.got('unknown')) const LegendRow(LegendMark.eventUnknown, '점선 빈 점', '연도 미정 (배치용 연도에 놓임)'),
      const LegendRow(LegendMark.rail, '기간이 있는 사건', '양 끝이 실선 세로바인 가는 선'),
      const LegendRow(LegendMark.beads, '연대가 갈리는 사건', '점선 실에 꿴 구슬: 채운 구슬 = 통설, 빈 고리 = 다른 견해. 날짜를 정확히 모르는 사건은 범위 없이 점 하나로'),
      const LegendRow(LegendMark.railAlt, '기간이 있는 사건의 다른 견해', '이설의 시작 · 끝에 점선 세로바'),
      if (f.got('treaty')) const LegendRow(LegendMark.treaty, '조약', '마름모 인장: 제 줄은 채운 마름모, 다른 당사국의 줄은 속 빈 마름모'),
      if (f.got('treaty')) const LegendRow(LegendMark.railTreaty, '기간이 있는 조약(체결 ~ 실효)', '겹줄 가는 선. 발효가 체결과 다르면 선 위에 작은 마름모 눈금'),
    ]),
    LegendGroup('칸', [
      const LegendRow(
        LegendMark.cell,
        '칸',
        '띠 맨 위: 왕조 칸 · 그 아래 지도자 칸 · 내각 칸. 이어지는 지도자 칸은 같은 왕조끼리 하나의 긴 둥근 칸에 가는 구분선으로. 띠 안 맨 아래는 기관 칸, 띠 아래로 내려오는 작은 탭은 구역 — 둘 다 옅은 빗금(외세의 손길 · 속국 이름표는 민무늬)',
        look: _accepted,
      ),
      const LegendRow(LegendMark.axis, '맨 위 날짜 칸', '간지 줄 아래 연호 · 도읍 묶음 줄. 한 왕조의 연호, 한 정권의 도읍은 하나의 긴 둥근 칸으로 이어짐(천도 = 가는 구분선, 임시 도읍 = 점선 칸)', rgb: LegendTint.sky),
      if (f.got('cats')) const LegendRow(LegendMark.catLines, '띠 안 사건 분류별 글줄', '한 띠에 분류가 둘 이상이면 분류마다 글줄 하나, 글줄 사이는 옅은 점선. 왼쪽 줄 이름 칸의 색 점이 그 글줄의 분류', rgb: LegendTint.rose),
      const LegendRow(LegendMark.bird, '조감(띠 밀도 넷째 · V · ↕)', '줄이 띠 하나 높이로 — 이름은 띠 안 왼쪽, 사건은 작은 점 · 개수 알약', look: _accepted),
      const LegendRow(LegendMark.cellSpot, '칸 기간 조명', '띠 안의 지도자·내각·시기·지위 칸, 날짜 칸의 연호·도읍 칸을 누르면 그 칸은 진하게, 띠 안의 그 기간은 옅게 칠해지고 그 칸의 창이 열림', look: _accepted, rgb: LegendTint.mint),
      if (f.got('cellAlt')) const LegendRow(LegendMark.cellAlt, '칸의 다른 견해(이설)', '이설이 말하는 경계 해에 칸 높이만 한 옅은 점선(유령 구분선) — 진짜 구분선은 그대로', look: _accepted),
      if (f.got('cellFuzzy')) const LegendRow(LegendMark.cellFuzzy, '연대가 모호한 칸(추정 · 전승 · 이르면 ~ 늦으면)', '그 구간의 칸 바탕에 띠의 연대 폭과 같은 무늬, 그 구간 안의 경계는 점선', look: _accepted),
      if (f.got('phase')) const LegendRow(LegendMark.phase, '시기 구분(학계)', '띠 안 왕조 칸 아래 · 지도자 칸 위에 체계마다 얇은 줄 하나. 누르면 그 기간이 조명되고 시기 창이 열림', look: _accepted),
      if (f.got('rank')) const LegendRow(LegendMark.ranks, '지위', '지도자 칸 위(시기 구분이 있으면 그 아래)의 얇은 지위 단 — 서열이 높을수록 나라 색이 짙음(맨 왼쪽 견본은 서열 밖)', look: _accepted),
      const LegendRow(LegendMark.house, '가문', '필터의 가문을 켜면 지도자 칸 아래쪽에 그 지도자의 가문 색 줄. 가문 창이 열린 동안 그 가문의 칸이 진해짐', look: _accepted),
      if (f.got('unknown')) const LegendRow(LegendMark.cellUnknown, '칸의 미정', '시작이나 끝을 모르면 그쪽 끝이 칸 안에서 옅어지며 사라지고 칸 사이 구분선이 점선이 됨', look: _accepted),
      if (f.got('figure')) const LegendRow(LegendMark.figure, '인물 단(띠 안, 기간 막대 아래)', '그 나라에서 활동한 사람의 활동 막대 — 이름은 들어갈 때만. 고르면 생몰을 잇는 수명선. 막대가 너무 좁으면 “인물 n명” 한 칸', look: _accepted),
    ]),
  ]);

  final threads = LegendBox('실 · 받침', [
    LegendGroup('', [
      const LegendRow(LegendMark.succession, '승계', '꼬리 마름모에서 다음 구멍으로'),
      const LegendRow(LegendMark.host, '섬김', '상국 빛깔 받침 카드 + 이름 탭'),
      if (f.persons) const LegendRow(LegendMark.person, '사람 띠', '왕관마다 실 · 띠 윗변의 뿔'),
    ]),
    LegendGroup('건국 · 멸망 · 승계 · 소속', [
      const LegendRow(LegendMark.found, '건국', '채운 둥근 네모, 띠 안쪽', look: _accepted),
      const LegendRow(LegendMark.end, '멸망·종료', '빈 둥근 네모', look: _accepted),
      if (f.got('unknown')) const LegendRow(LegendMark.foundUnknown, '연도 미정', '점선 동그라미', look: _accepted),
      const LegendRow(LegendMark.succession, '직접 승계', '승계를 선언'),
      const LegendRow(LegendMark.indirect, '간접 승계', '지역·거시적 승계'),
      if (f.got('revival')) const LegendRow(LegendMark.revival, '부흥', '멸망한 나라를 되살리려는 세력 (점선 + 후대 띠 앞의 작은 고리)'),
      if (f.got('partial'))
        const LegendRow(LegendMark.partial, '부분 승계', '나라는 끊겼으나 지배층·백성·영역·제도·문화의 일부가 넘어감. 가는 실선(직접 승계는 굵은 실선) — 정도(약 · 중 · 강)와 이어진 것은 선에 올리거나 상세 창에서'),
      if (f.got('join')) const LegendRow(LegendMark.join, '합류', '이미 있던 나라로 들어간 승계(흡수): 선이 멸망 네모 밑에서 곧게 내려가 그해의 띠 테두리에 닿고, 닿는 자리에 선대 색의 짧은 합류 조각'),
      const LegendRow(LegendMark.partOf, '소속선', '상위 띠 아래에 접혀 들어간 정권 ↔ 상위 정권 (펼쳤을 때)'),
      const LegendRow(LegendMark.union, '동군연합', '같은 사람이 같은 때 두 나라의 지도자: 겹친 기간의 가운데에서 두 지도자 칸을 꿰는 옅은 줄과 끝의 고리(한쪽이 화면 밖이면 칸 이름 앞의 겹고리)'),
      if (f.got('depOut'))
        const LegendRow(LegendMark.hangOut, '상국 띠 아래에 매달린 이름표', '스스로 다스린 속국: 빈 탭은 조공·책봉 · 봉국 · 자치령 · 복속 세력 · 기미, 칠한 탭은 종속 · 보호 · 위성 (점선 탭은 명목상 소속, 파선 탭은 예속이 아닌 소속). 상국 띠의 ▾ 속국 단추로 접고 편다'),
      if (f.got('depIn'))
        const LegendRow(LegendMark.hangIn, '상국 띠 안 맨 아래의 이름표', '상국이 다스린 속국: 옅은 칸은 괴뢰 · 위임 통치, 짙은 칸은 식민지 · 속령 · 직할령 · 군현, 빗금 칸은 점령지 · 군정. 매달려 있다가 안으로 들어오면 세로 끈으로 이어짐'),
      if (f.got('hostTab'))
        const LegendRow(
          LegendMark.host,
          '뒤 장',
          '속국 띠 뒤에 깔린 상국 빛깔의 종이(관계가 있던 기간만큼 · 띠 위로 살짝 드러남), 관계가 끝나는 쪽의 탭이 상국 이름. 짙기는 예속의 깊이: 옅게 조공·책봉 · 봉국 · 자치령 · 복속 · 기미, 가운데 종속 · 보호 · 위성, 짙게 괴뢰 · 위임 · 식민 · 군현 · 점령 (칠 없는 점선 테는 명목상 · 예속이 아닌 소속)',
        ),
    ]),
  ]);

  final scope = f.got('scope') || f.got('hollow');
  final vessels = LegendBox('그릇', [
    LegendGroup('', [
      if (f.containers) const LegendRow(LegendMark.folder, '폴더', '가장 바깥 그릇 · 나라 · 연방 · 시대'),
      if (f.nested) const LegendRow(LegendMark.box, '상자', '안쪽 그릇 · 뚜껑에 흰 라벨'),
      if (f.containers) const LegendRow(LegendMark.closedBox, '접힌 상자', '안의 꼬리표를 작게 · 넘치면 +n'),
    ]),
    if (scope)
      LegendGroup('대범위 — 흩어진 나라를 한 집합으로', [
        if (f.got('scope'))
          const LegendRow(LegendMark.folder, '대범위', '대범위를 켜면 구성 정권이 한 가지로 모이고 둘레에 옅은 테두리 — 왼쪽 위 이름표를 누르면 상세, 짙은 세로 구간은 대범위의 기간', rgb: LegendTint.butter),
        if (f.got('hollow')) const LegendRow(LegendMark.hollow, '할거기', '상징적 본국 띠의 그 기간이 속 빈 모양(이름만 남음) · 띠의 작은 단추로 모아 보기', look: _accepted, rgb: LegendTint.rose),
      ]),
  ]);

  return [
    tags,
    inside,
    threads,
    if (vessels.rows.isNotEmpty) vessels,
    legitBox,
  ];
}

/// 정통성 넷(감독 고름 — 다듬기 판 범례의 두 열에 걸친 상자 · 그림은 '정통성 가 다듬음' lg2-ga 그대로).
/// 그림판이 아직 그리지 않는 무늬라 쓰였는지 알 길이 없어 **늘 보이는 줄**로 둔다(앞 범례의 '통설 연대' · '직접 승계'처럼).
const legitBox = LegendBox('정통성', [
  LegendGroup('', [
    LegendRow(LegendMark.joint, '공동', '겹친 기간은 반 칸 둘'),
    LegendRow(LegendMark.regent, '섭정', '그 기간 칸 아랫변에 먹 밑줄'),
    LegendRow(LegendMark.nominal, '명목', '이름만 옅은 먹'),
    LegendRow(LegendMark.claim, '주장', '칸 바탕 빗금 · 띠 자체면 머리에'),
  ]),
], wide: true);

/// 맺음말(css의 `.lg-note`).
const legendNote =
    '세로 눈금은 옅은 점선과 한 칸 걸러 깔린 바탕색으로만 표시해 승계선 · 소속선과 섞이지 않습니다. '
    '트랙 이름 · 민족 칸 · 연호 · 도읍 묶음 이름을 누르면 접거나 펼칩니다. '
    '같은 줄은 승계로 이어진 정권만 함께 씁니다. 띠에 마우스를 올리거나 고르면 그 정권의 승계선이 짙어집니다. 필터 바의 체크로 칸 · 선을 켜고 끕니다.';

/// 범례 폴더가 연표 자리 가장자리에서 떨어진 몫(왼쪽 · 아래 — 목업 x0 16 · 바닥 1064).
const legendMargin = 16.0;

/// 줄 하나의 견본 앞 · 뒤 고정 몫(상자 안쪽 10 · 견본 148 · 사이 16 · 상자 안쪽 10) — 열 너비 = 이 값 + 글 칸.
const _rowFixed = 2 * SheetLook.boxInset + LegendLook.sample + LegendLook.textGap;

/// 두 열로 세우는 가장 좁은 글 칸 · 한 열에서 숨기는 글 칸.
const _twoMinText = 120.0, _oneMinText = 60.0;

/// 범례 폴더의 폭과 열 — [maxWidth]는 연표 자리의 폭. 상세 창(또는 같은 해 보기)이 열려 있으면([covered]) 그 400을 비우고, 860보다 좁으면 숨는다(null).
/// 자리가 넉넉하면 두 열(폭 752 — 글 칸 172), 모자라면 글 칸을 120까지 줄이다가 한 열(폭 384), 휴대폰([phone])은 늘 한 열.
({double width, bool two, double text})? legendFrame(double maxWidth, {required bool covered, bool phone = false}) {
  if (covered && maxWidth <= 860) return null;
  final avail = (covered ? maxWidth - 400 - legendMargin : maxWidth - 2 * legendMargin).floorToDouble();
  const pad = 2 * LegendLook.pad, gap = LegendLook.columnGap;
  if (!phone && avail >= pad + 2 * (_rowFixed + _twoMinText) + gap) {
    final width = math.min(pad + 2 * (_rowFixed + LegendLook.text) + gap, avail);
    final col = ((width - pad - gap) / 2).floorToDouble();
    return (width: pad + 2 * col + gap, two: true, text: col - _rowFixed);
  }
  final width = math.min(pad + _rowFixed + LegendLook.text, avail);
  if (width - pad - _rowFixed < _oneMinText) return null;
  return (width: width, two: false, text: width - pad - _rowFixed);
}

/// 범례 카드. 앱 틀이 연표 영역을 덮는 자리(`Positioned.fill`)에 놓으면 스스로 왼쪽 아래 16에 선다.
class LegendCard extends StatefulWidget {
  const LegendCard({super.key, required this.bus});
  final AppBus bus;

  @override
  State<LegendCard> createState() => _LegendCardState();
}

class _LegendCardState extends State<LegendCard> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();
  Animation<double> get _curve => _enter;

  final _folderKey = GlobalKey();

  LegendFacts? _facts;
  bool _failed = false;
  int _token = 0;

  AppBus get _bus => widget.bus;
  bool get _open => _bus.slot(legendSlot).value == true;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    _bus.slot(legendSlot).addListener(_onSwitch);
    _bus.slot(slotCommand).addListener(_onCommand);
    _bus.conditions.addListener(_onData);
    _bus.selection.addListener(_onCover);
    _bus.slot('yearPanel').addListener(_onCover);
    if (_open) _onSwitch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && (_enter.isAnimating || _enter.value > 0)) _enter.value = 1;
  }

  @override
  void dispose() {
    _bus.slot(legendSlot).removeListener(_onSwitch);
    _bus.slot(slotCommand).removeListener(_onCommand);
    _bus.conditions.removeListener(_onData);
    _bus.selection.removeListener(_onCover);
    _bus.slot('yearPanel').removeListener(_onCover);
    _enter.dispose();
    super.dispose();
  }

  void _onSwitch() {
    if (!mounted) return;
    if (_open) {
      _enter.forward();
      _load();
    } else {
      _enter.reverse();
    }
    setState(() {});
  }

  /// 단축키 · 메뉴의 `❔ 범례`가 오면 여닫는다.
  void _onCommand() {
    final command = _bus.slot(slotCommand).value;
    if (command is AppCommand && command.name == Cmd.legend) _bus.slot(legendSlot).value = !_open;
  }

  /// 자료가 바뀌면(자료집 · 보기 조건) 열려 있는 동안 다시 묻는다 — 쓰이지 않게 된 줄이 남지 않게.
  void _onData() {
    if (_open) _load();
  }

  void _onCover() {
    if (_open && mounted) setState(() {});
  }

  Future<void> _load() async {
    final token = ++_token;
    try {
      final answer = await _bus.ask({'op': 'legend_kinds'});
      if (!mounted || token != _token) return;
      setState(() {
        _facts = LegendFacts.fromJson(answer);
        _failed = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() => _failed = true);
    }
  }

  /// 폴더의 자리를 슬롯에 적는다(그린 뒤에 — 닫혔거나 숨었으면 null). 나타나는 움직임 동안은 적지 않는다(자리가 8px 흐른다).
  void _publishLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LegendSpot? spot;
      final folder = _folderKey.currentContext?.findRenderObject();
      final area = context.findRenderObject();
      if (_open && folder is RenderBox && folder.attached && folder.hasSize && area is RenderBox && area.attached) {
        if (_enter.isAnimating) return;
        spot = LegendSpot(folder.localToGlobal(Offset.zero, ancestor: area) & folder.size, folder.localToGlobal(Offset.zero) & folder.size);
      }
      final slot = _bus.slot(legendSpotSlot);
      if (slot.value != spot) slot.value = spot;
    });
  }

  @override
  Widget build(BuildContext context) {
    _publishLater();
    if (!_open && _enter.isDismissed) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        // 상세 창(또는 같은 해 보기)이 열려 있으면 폭이 줄다가 한 열로, 860보다 좁은 창에서는 숨는다.
        final covered = _bus.selection.value != null || _bus.slot('yearPanel').value != null;
        final frame = legendFrame(box.maxWidth, covered: covered, phone: SceneView.phone);
        if (frame == null) return const SizedBox.shrink();
        final facts = _facts?.withLayout(_bus.scene.layout);
        final boxes = facts == null ? null : buildLegend(facts);
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(legendMargin),
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, child) => Opacity(
                opacity: _enter.opacity,
                child: Transform.translate(offset: Offset(0, 8 * (1 - _curve.value)), child: child),
              ),
              child: SizedBox(
                key: _folderKey,
                width: frame.width,
                child: SheetFolder(
                  label: '범례',
                  count: boxes == null ? null : '${boxes.fold<int>(0, (n, b) => n + b.rows.length)}',
                  onClose: () => _bus.slot(legendSlot).value = false,
                  padding: const EdgeInsets.all(LegendLook.pad),
                  child: boxes == null
                      ? Text(_failed ? '범례에 쓸 자료를 읽지 못했습니다.' : '읽는 중…', style: sheetText(12, color: SheetLook.ink60))
                      : SingleChildScrollView(child: LegendBody(boxes: boxes, two: frame.two, text: frame.text)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  몸 — 상자 두 열(바닥 맞춤) + 두 열에 걸친 정통성 + 맺음말
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 줄 글의 꼴 — 이름 13 굵게 먹 85 · 설명 12 먹 60(줄바꿈) · 상자 안 묶음 이름 11 굵게 먹 45.
const legendNameStyle = TextStyle(fontSize: LegendLook.nameSize, fontWeight: FontWeight.w700, color: SheetLook.ink85, height: 1.3);
const legendDescStyle = TextStyle(fontSize: LegendLook.descSize, fontWeight: FontWeight.w400, color: SheetLook.ink60, height: 1.4);
const legendSectionStyle = TextStyle(fontSize: LegendLook.sectionSize, fontWeight: FontWeight.w700, color: SheetLook.ink45, height: 1.3);
const legendNoteStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: SheetLook.ink45, height: 1.45);

/// 상자 안의 한 칸(묶음 이름 또는 줄) · 그 키.
class _Item {
  _Item.section(this.title, this.height) : row = null, rowText = 0, sampleTop = 0, textTop = 0;
  _Item.row(LegendRow this.row, this.height, this.rowText, this.sampleTop, this.textTop) : title = '';
  final String title;
  final LegendRow? row;
  final double height, rowText, sampleTop, textTop;
}

/// 상자 하나의 배치 — 칸들과 칸 사이(늘릴 수 있는 사이는 [stretch]), 아래 덧 여백.
class _BoxPlan {
  _BoxPlan(this.box, this.items, this.gaps, this.stretch);
  final LegendBox box;
  final List<_Item> items;
  final List<double> gaps;
  final List<bool> stretch;
  double extraBottom = 0;

  double get height =>
      SheetLook.boxLid + 1 + LegendLook.boxTop + items.fold<double>(0, (a, i) => a + i.height) + gaps.fold<double>(0, (a, g) => a + g) + LegendLook.boxBottom + extraBottom;
}

/// 범례의 몸 — [boxes]를 [two]면 두 열(마지막 [LegendBox.wide] 상자는 두 열에 걸쳐), 아니면 한 열로. [text]는 줄의 글 칸 폭.
class LegendBody extends StatelessWidget {
  const LegendBody({super.key, required this.boxes, required this.two, required this.text});
  final List<LegendBox> boxes;
  final bool two;
  final double text;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    double measure(String s, TextStyle style, double width) {
      if (s.isEmpty) return 0;
      final tp = TextPainter(text: TextSpan(text: s, style: base.merge(style)), textDirection: TextDirection.ltr, textScaler: scaler)..layout(maxWidth: width);
      final h = tp.height.ceilToDouble();
      tp.dispose();
      return h;
    }

    final col = _rowFixed + text, inner = col - 2 * SheetLook.boxInset;
    _Item rowItem(LegendRow r) {
      final nameH = measure(r.name, legendNameStyle, text);
      final textH = nameH + (r.desc.isEmpty ? 0 : LegendLook.nameDescGap + measure(r.desc, legendDescStyle, text));
      final sample = legendSampleHeight(r.mark);
      final h = math.max(LegendLook.rowMin, math.max(sample, textH)).ceilToDouble();
      return _Item.row(r, h, textH, ((h - sample) / 2).roundToDouble(), ((h - textH) / 2).roundToDouble());
    }

    _BoxPlan plan(LegendBox b) {
      final items = <_Item>[], gaps = <double>[], stretch = <bool>[];
      for (final g in b.groups) {
        if (g.rows.isEmpty) continue;
        if (g.title.isNotEmpty) {
          if (items.isNotEmpty) {
            gaps.add(LegendLook.sectionBefore);
            stretch.add(true);
          }
          items.add(_Item.section(g.title, math.max(16, measure(g.title, legendSectionStyle, inner))));
        }
        for (final r in g.rows) {
          if (items.isNotEmpty) {
            final afterSection = items.last.row == null;
            gaps.add(afterSection ? LegendLook.sectionAfter : LegendLook.rowGap);
            stretch.add(!afterSection);
          }
          items.add(rowItem(r));
        }
      }
      return _BoxPlan(b, items, gaps, stretch);
    }

    final plans = [for (final b in boxes) if (b.rows.isNotEmpty) plan(b)];
    final wide = two ? [for (final p in plans) if (p.box.wide) p] : const <_BoxPlan>[];
    final narrow = [for (final p in plans) if (!two || !p.box.wide) p];

    if (!two) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(key: const ValueKey('legend-column-0'), child: _column(narrow, col)),
          _note(),
        ],
      );
    }
    final (left, right) = balanceLegendColumns([for (final p in narrow) p.height]);
    final cols = [for (final side in [left, right]) [for (final i in side) narrow[i]]];
    double heightOf(List<_BoxPlan> c) => c.fold<double>(0, (a, p) => a + p.height) + math.max(0, c.length - 1) * LegendLook.boxGap;
    // 짧은 열은 남는 키를 줄 사이에 고루 나눈다(상자 아래가 비지 않게 — 목업 drawLegend).
    final tall = math.max(heightOf(cols[0]), heightOf(cols[1]));
    for (final c in cols) {
      var extra = tall - heightOf(c);
      if (extra <= 0 || c.isEmpty) continue;
      final slots = [for (final p in c) for (var k = 0; k < p.gaps.length; k++) if (p.stretch[k]) (p, k)];
      if (slots.isEmpty) {
        c.last.extraBottom += extra;
        continue;
      }
      for (var j = 0; j < slots.length; j++) {
        final add = (extra / (slots.length - j)).floorToDouble();
        final (p, k) = slots[j];
        p.gaps[k] += add;
        extra -= add;
      }
      if (extra > 0) c.last.extraBottom += extra;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: col, child: KeyedSubtree(key: const ValueKey('legend-column-0'), child: _column(cols[0], col))),
            const SizedBox(width: LegendLook.columnGap),
            SizedBox(width: col, child: KeyedSubtree(key: const ValueKey('legend-column-1'), child: _column(cols[1], col))),
          ],
        ),
        for (final p in wide) ...[const SizedBox(height: LegendLook.boxGap), _wideBox(p, col)],
        _note(),
      ],
    );
  }

  Widget _note() => const Padding(
    padding: EdgeInsets.only(top: 10, left: 2, right: 2),
    child: Text(legendNote, style: legendNoteStyle),
  );

  Widget _column(List<_BoxPlan> plans, double col) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < plans.length; i++) ...[if (i > 0) const SizedBox(height: LegendLook.boxGap), _box(plans[i])],
    ],
  );

  Widget _box(_BoxPlan p) => SheetBox(
    label: p.box.title,
    count: '${p.box.rows.length}',
    padding: EdgeInsets.fromLTRB(SheetLook.boxInset, LegendLook.boxTop, SheetLook.boxInset, LegendLook.boxBottom + p.extraBottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < p.items.length; i++) ...[
          if (i > 0) _gap(p.gaps[i - 1], rule: p.items[i].row == null),
          _item(p.items[i]),
        ],
      ],
    ),
  );

  /// 칸 사이 — 묶음 이름 앞이면 가운데에 먹 12 금(상자 테 안쪽 끝까지).
  Widget _gap(double h, {required bool rule}) => SizedBox(height: h, child: rule ? const CustomPaint(painter: _RulePainter()) : null);

  Widget _item(_Item it) {
    final r = it.row;
    if (r == null) {
      return SizedBox(
        height: it.height,
        child: Align(alignment: Alignment.centerLeft, child: Text(it.title, style: legendSectionStyle)),
      );
    }
    return LegendRowView(row: r, height: it.height, text: text, sampleTop: it.sampleTop, textTop: it.textTop);
  }

  /// 두 열에 걸친 상자(정통성): 줄마다 둘 — 둘째 견본의 왼쪽 끝은 오른쪽 열의 견본과 한 줄.
  Widget _wideBox(_BoxPlan p, double col) {
    final rows = p.box.rows;
    final lines = <List<_Item>>[];
    for (var i = 0; i < p.items.length; i += 2) {
      lines.add(p.items.sublist(i, math.min(p.items.length, i + 2)));
    }
    final cell = col - 2 * SheetLook.boxInset;
    return SheetBox(
      label: p.box.title,
      count: '${rows.length}',
      padding: const EdgeInsets.fromLTRB(SheetLook.boxInset, LegendLook.boxTop, SheetLook.boxInset, LegendLook.boxBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var l = 0; l < lines.length; l++) ...[
            if (l > 0) const SizedBox(height: LegendLook.rowGap),
            Builder(
              builder: (context) {
                final h = lines[l].fold<double>(0, (a, it) => math.max(a, it.height));
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var k = 0; k < lines[l].length; k++) ...[
                      if (k > 0) const SizedBox(width: LegendLook.columnGap + 2 * SheetLook.boxInset),
                      SizedBox(
                        width: cell,
                        child: LegendRowView(
                          row: lines[l][k].row!,
                          height: h,
                          text: text,
                          sampleTop: ((h - legendSampleHeight(lines[l][k].row!.mark)) / 2).roundToDouble(),
                          textTop: ((h - lines[l][k].rowText) / 2).roundToDouble(),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 상자를 두 열에 나눈다(차례는 지킨다) — 앞에서 끊는 갈래와 짧은 열에 차례로 얹는 갈래 가운데 두 열 키 차가 작은 것(같으면 앞에서 끊음).
/// 돌려줌: 왼쪽 · 오른쪽 열의 상자 번호.
(List<int>, List<int>) balanceLegendColumns(List<double> heights) {
  double sum(Iterable<int> ids) => ids.isEmpty ? 0 : ids.fold<double>(0, (a, i) => a + heights[i]) + (ids.length - 1) * LegendLook.boxGap;
  final n = heights.length;
  if (n < 2) return ([for (var i = 0; i < n; i++) i], <int>[]);
  var best = (List<int>.generate(1, (i) => i), List<int>.generate(n - 1, (i) => i + 1));
  var bestDiff = double.infinity;
  for (var k = 1; k < n; k++) {
    final l = List<int>.generate(k, (i) => i), r = List<int>.generate(n - k, (i) => i + k);
    final d = (sum(l) - sum(r)).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = (l, r);
    }
  }
  final gl = <int>[], gr = <int>[];
  for (var i = 0; i < n; i++) {
    (sum(gl) <= sum(gr) ? gl : gr).add(i);
  }
  if ((sum(gl) - sum(gr)).abs() < bestDiff) best = (gl, gr);
  return best;
}

/// 범례 줄 하나 — 왼쪽 견본(148) + 사이 16 + 글 칸(이름 13 굵게 · 설명 12 먹 60). 키는 정한 값([height]).
class LegendRowView extends StatelessWidget {
  const LegendRowView({super.key, required this.row, required this.height, required this.text, this.sampleTop = 0, this.textTop = 0});
  final LegendRow row;
  final double height, text, sampleTop, textTop;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: EdgeInsets.only(top: sampleTop), child: LegendSample(row: row)),
        const SizedBox(width: LegendLook.textGap),
        SizedBox(
          width: text,
          child: Padding(
            padding: EdgeInsets.only(top: textTop),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: legendNameStyle),
                if (row.desc.isNotEmpty) ...[const SizedBox(height: LegendLook.nameDescGap), Text(row.desc, style: legendDescStyle)],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// 묶음 이름 앞의 금 — 먹 12 · 상자 테 안쪽 끝까지(몸의 안쪽 10보다 9 밖).
class _RulePainter extends CustomPainter {
  const _RulePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = (size.height / 2).floorToDouble();
    canvas.drawRect(Rect.fromLTRB(-(SheetLook.boxInset - 1), y, size.width + SheetLook.boxInset - 1, y + 1), Paint()..color = SheetLook.ink12);
  }

  @override
  bool shouldRepaint(_RulePainter old) => false;
}
