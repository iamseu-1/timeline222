import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scene/color_mix.dart' show mixOklab;
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'shell_keys.dart';

// 범례(명세 06의 7-3). `❔` · `L`로 왼쪽 아래에 연다. **지금 자료에 쓰인 것만** 그린다 —
// 자료(켠 자료집 · 필터)가 바뀌면 열려 있는 동안 다시 묻는다.
//
// 혼자 서는 부품이라 [AppBus]만 받는다:
//   `bus.slot('command')` — 단축키 · 메뉴의 [Cmd.legend]가 오면 여닫는다(`❔` · `L`).
//   `bus.slot('legend')` = bool — 열고 닫기. 앱 틀이 기억해 둔 값을 여기에 넣어 두면 그대로 열린 채 시작한다.
//   `bus.ask({'op':'legend_kinds'})` — 지금 자료에 쓰인 종류 · 확실성 · 실재성 · 있고 없음.
// 상세 창(또는 같은 해 보기)이 열려 있으면 폭이 줄고, 창 폭이 860보다 좁으면 숨는다 — `bus.selection`과 `bus.slot('yearPanel')`로 안다.
//
// 작은 견본 그림은 글자(이모지)가 아니라 [LegendMark]를 그리는 위젯이다. 지금 연표는 승계 다리 · 부분 승계 · 합류의 견본을
// **연표를 그리는 코드로** 그려 견본과 실제가 갈라지지 않게 하는데, 새 앱의 그 견본 도우미는 아직 없어 이 파일이 대신 그린다(보고 참고).

/// `bus.slot(…)`의 이름: 범례 열기.
const legendSlot = 'legend';

/// 견본 그림의 종류. 한 줄에 하나씩, 왼쪽 34px 자리에 그린다.
enum LegendMark {
  /// 띠 34×12.
  band,
  bandEstimated,
  bandLegend,
  bandRange,
  bandUnknown,
  bandFaint, // 옅은 띠(종속 갈래)
  bandDouble, // 겹줄 띠(연맹)
  bandDotted, // 점선 테두리(조직체)
  bandPlain, // 테두리 없는 옅은 띠(시대 이름)
  bandFogBottom, // 반전설
  bandFog, // 전설
  bandGray, // 부정됨
  bandScope, // 대범위 테두리
  bandHollow, // 할거기(속 빈 띠)
  /// 점 · 네모 34px 자리 가운데.
  dot,
  dotHollow,
  dotDashed,
  square,
  squareHollow,
  diamond,
  diamondHollow,

  /// 선 34px. lineThin은 부분 승계 — 연표처럼 가는(1px) 실선. 관계선은 모두 띠 테 빛깔 하나.
  line,
  lineThin,
  lineDashed,
  lineDotted,

  /// 동군연합 이음줄(건의 8의 6-다): 위아래 두 칸을 꿰는 옅은 줄과 끝의 고리.
  union,
  rail,
  railTreaty,
  railAlt,
  beads, // 점선 실에 꿴 구슬
  /// 칸 · 탭 · 그 밖.
  cell,
  cellAxis,
  cellSpot,
  cellFuzzy,
  cellAlt,
  cellUnknown,
  hangLoose,
  hangFirm,
  hangIn,
  hostTab, // 뒤 장의 탭(속국 띠 위의 상국 탭 — 묶음 3 · 1번)
  phase,
  ranks,
  house,
  figure,
  catDot,
  bird,
}

/// 범례 한 줄: 왼쪽 견본과 오른쪽 글.
@immutable
class LegendRow {
  const LegendRow(this.mark, this.text, {this.color});
  final LegendMark mark;
  final String text;

  /// 견본의 색(없으면 종이빛 기본).
  final Color? color;
}

/// 범례 한 묶음(제목 + 줄).
@immutable
class LegendGroup {
  const LegendGroup(this.title, this.rows);
  final String title;
  final List<LegendRow> rows;
}

/// `{"op":"legend_kinds"}`의 답 — 지금 자료에 무엇이 쓰였는가.
@immutable
class LegendFacts {
  const LegendFacts({this.kinds = const [], this.certainty = const [], this.historicity = const [], this.has = const {}});

  /// 쓰인 정권 종류(계약 6-1의 종류 번호 차례 · 0 국가는 늘 있다).
  final List<LegendKind> kinds;

  /// 쓰인 연대의 확실성 0 확실 · 1 통설 · 2 추정 · 3 전승.
  final List<int> certainty;

  /// 쓰인 실재성 1 반전설 · 2 전설 · 3 실재 논쟁 · 4 부정됨(0 실재는 빼고).
  final List<int> historicity;

  /// 조건부 줄의 있고 없음(`range` · `unknown` · `scope` · `hollow` · `revival` · `partial` · `join` ·
  /// `depOut` · `depIn` · `figure` · `cellAlt` · `cellFuzzy` · `phase` · `rank` · `treaty` · `cats` · `culture` · `zone`).
  final Map<String, bool> has;

  bool got(String key) => has[key] == true;

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

/// 쓰인 것만 남긴 범례의 차례를 짓는다. 묶음 차례는 명세 7-3 그대로다:
/// 정권 띠 → 정권 종류 → 실재성 → 대범위 → 건국·멸망·승계·소속 → 사건(조약 포함) → 칸 → 맺음말.
List<LegendGroup> buildLegend(LegendFacts f) {
  final groups = <LegendGroup>[];

  groups.add(
    LegendGroup('정권 띠', [
      const LegendRow(LegendMark.band, '통설 연대 (기본)'),
      if (f.certainty.contains(2)) const LegendRow(LegendMark.bandEstimated, '추정 연대 — 옅은 실선 테두리'),
      if (f.certainty.contains(3)) const LegendRow(LegendMark.bandLegend, '전승 연대 — 빗금'),
      if (f.got('range')) const LegendRow(LegendMark.bandRange, '연대 폭이 있는 구간만 무늬'),
      if (f.got('unknown')) const LegendRow(LegendMark.bandUnknown, '연도 미정 — 그쪽 끝이 둥글게 사라짐'),
    ]),
  );

  // 정권 종류: 종속 갈래가 둘 이상이면 옅은 띠 한 줄로 묶는다(제 띠의 모양이 모두 같기 때문).
  final deps = f.kinds.where((k) => k.dep).toList();
  groups.add(
    LegendGroup('정권 종류', [
      for (final k in f.kinds)
        if (!k.dep || deps.length == 1)
          LegendRow(_markOfKind(k.kind), k.hint.isEmpty ? k.name : '${k.name} — ${k.hint.split(' — ').last}')
        else if (k == deps.first)
          LegendRow(LegendMark.bandFaint, '종속 갈래 — 옅은 띠 (${deps.map((d) => d.name).join(' · ')}). 누구를 어떻게 섬겼는지는 상국 띠의 이름표로'),
    ]),
  );

  if (f.historicity.isNotEmpty) {
    groups.add(
      LegendGroup('실재성 — 나라가 있었는가 (연대의 확실성과는 따로)', [
        if (f.historicity.contains(1)) const LegendRow(LegendMark.bandFogBottom, '반전설 — 이름 띠를 한 단 옅은 색으로 · 옅은 실선 테 · 탭에 “반전설”'),
        if (f.historicity.contains(2)) const LegendRow(LegendMark.bandFog, '전설 — 이름 띠를 두 단 옅은 색으로 · 옅은 실선 테 · 탭 이름이 기울어짐 · 탭에 “전설”'),
        if (f.historicity.contains(3)) const LegendRow(LegendMark.band, '실재 논쟁 — 보통 띠 · 탭에 “논쟁”'),
        if (f.historicity.contains(4)) const LegendRow(LegendMark.bandGray, '부정됨 — 전설과 같은 옅은 칠을 색 없이 회색으로 · 탭 이름에 취소선 · 이어진 승계선이 옅어짐 · 탭에 “부정”'),
      ]),
    );
  }

  if (f.got('scope') || f.got('hollow')) {
    groups.add(
      LegendGroup('대범위 — 흩어진 나라를 한 집합으로', [
        if (f.got('scope')) const LegendRow(LegendMark.bandScope, '대범위를 켜면 구성 정권이 한 가지로 모이고 둘레에 옅은 테두리 — 왼쪽 위 이름표를 누르면 상세, 짙은 세로 구간은 대범위의 기간', color: Color(0xffd7c18e)),
        if (f.got('hollow')) const LegendRow(LegendMark.bandHollow, '할거기 — 상징적 본국 띠의 그 기간이 속 빈 모양(이름만 남음) · 띠의 작은 단추로 모아 보기', color: Color(0xffd4a39b)),
      ]),
    );
  }

  groups.add(
    LegendGroup('건국 · 멸망 · 승계 · 소속', [
      const LegendRow(LegendMark.square, '건국 (채운 둥근 네모, 띠 안쪽)'),
      const LegendRow(LegendMark.squareHollow, '멸망·종료 (빈 둥근 네모)'),
      if (f.got('unknown')) const LegendRow(LegendMark.dotDashed, '연도 미정 (점선 동그라미)'),
      const LegendRow(LegendMark.line, '직접 승계 — 승계를 선언'),
      const LegendRow(LegendMark.lineDashed, '간접 승계 — 지역·거시적 승계'),
      if (f.got('revival')) const LegendRow(LegendMark.lineDashed, '부흥 — 멸망한 나라를 되살리려는 세력 (점선 + 후대 띠 앞의 작은 고리)'),
      if (f.got('partial')) const LegendRow(LegendMark.lineThin, '부분 승계 — 나라는 끊겼으나 지배층·백성·영역·제도·문화의 일부가 넘어감. 가는 실선(직접 승계는 굵은 실선) — 정도(약 · 중 · 강)와 이어진 것은 선에 올리거나 상세 창에서'),
      if (f.got('join')) const LegendRow(LegendMark.line, '합류 — 이미 있던 나라로 들어간 승계(흡수): 선이 멸망 네모 밑에서 곧게 내려가 그해의 띠 테두리에 닿고, 닿는 자리에 선대 색의 짧은 합류 조각'),
      const LegendRow(LegendMark.lineDotted, '소속선 — 상위 띠 아래에 접혀 들어간 정권 ↔ 상위 정권 (펼쳤을 때)'),
      const LegendRow(LegendMark.union, '동군연합 — 같은 사람이 같은 때 두 나라의 지도자: 겹친 기간의 가운데에서 두 지도자 칸을 꿰는 옅은 줄과 끝의 고리(한쪽이 화면 밖이면 칸 이름 앞의 겹고리)'),
      if (f.got('depOut'))
        const LegendRow(LegendMark.hangLoose, '상국 띠 아래에 매달린 이름표 — 스스로 다스린 속국: 빈 탭은 조공·책봉 · 봉국 · 자치령 · 복속 세력 · 기미, 칠한 탭은 종속 · 보호 · 위성 (점선 탭은 명목상 소속, 파선 탭은 예속이 아닌 소속). 상국 띠의 ▾ 속국 단추로 접고 편다'),
      if (f.got('depIn'))
        const LegendRow(LegendMark.hangIn, '상국 띠 안 맨 아래의 이름표 — 상국이 다스린 속국: 옅은 칸은 괴뢰 · 위임 통치, 짙은 칸은 식민지 · 속령 · 직할령 · 군현, 빗금 칸은 점령지 · 군정. 매달려 있다가 안으로 들어오면 세로 끈으로 이어짐'),
      if (f.got('hostTab'))
        const LegendRow(
          LegendMark.hostTab,
          '뒤 장 — 속국 띠 뒤에 깔린 상국 빛깔의 종이(관계가 있던 기간만큼 · 띠 위로 살짝 드러남), 관계가 끝나는 쪽의 탭이 상국 이름. 짙기는 예속의 깊이: 옅게 조공·책봉 · 봉국 · 자치령 · 복속 · 기미, 가운데 종속 · 보호 · 위성, 짙게 괴뢰 · 위임 · 식민 · 군현 · 점령 (칠 없는 점선 테는 명목상 · 예속이 아닌 소속)',
        ),
    ]),
  );

  groups.add(
    LegendGroup('사건', [
      const LegendRow(LegendMark.dot, '확실·통설 연대의 사건', color: _eventColor),
      const LegendRow(LegendMark.dotHollow, '추정·전승 연대, 또는 여러 나라가 함께 겪은 사건(속 빈 점)', color: _eventColor),
      if (f.got('unknown')) const LegendRow(LegendMark.dotDashed, '연도 미정 (배치용 연도에 놓임)', color: _eventColor),
      const LegendRow(LegendMark.rail, '기간이 있는 사건 — 양 끝이 실선 세로바인 가는 선', color: _eventColor),
      const LegendRow(LegendMark.beads, '연대가 갈리는 사건 — 점선 실에 꿴 구슬: 채운 구슬 = 통설, 빈 고리 = 다른 견해. 날짜를 정확히 모르는 사건은 범위 없이 점 하나로', color: _eventColor),
      const LegendRow(LegendMark.railAlt, '기간이 있는 사건의 다른 견해 — 이설의 시작 · 끝에 점선 세로바', color: _eventColor),
      if (f.got('treaty')) const LegendRow(LegendMark.diamond, '조약 — 마름모 인장: 제 줄은 채운 마름모, 다른 당사국의 줄은 속 빈 마름모', color: _eventColor),
      if (f.got('treaty')) const LegendRow(LegendMark.railTreaty, '기간이 있는 조약(체결 ~ 실효) — 겹줄 가는 선. 발효가 체결과 다르면 선 위에 작은 마름모 눈금', color: _eventColor),
    ]),
  );

  groups.add(
    LegendGroup('칸', [
      const LegendRow(
        LegendMark.cell,
        '띠 맨 위: 왕조 칸 · 그 아래 지도자 칸 · 내각 칸. 이어지는 지도자 칸은 같은 왕조끼리 하나의 긴 둥근 칸에 가는 구분선으로. 띠 안 맨 아래는 기관 칸, 띠 아래로 내려오는 작은 탭은 구역 — 둘 다 옅은 빗금(외세의 손길 · 속국 이름표는 민무늬)',
      ),
      const LegendRow(LegendMark.cellAxis, '맨 위 날짜 칸: 간지 줄 아래 연호 · 도읍 묶음 줄. 한 왕조의 연호, 한 정권의 도읍은 하나의 긴 둥근 칸으로 이어짐(천도 = 가는 구분선, 임시 도읍 = 점선 칸)', color: _axisColor),
      if (f.got('cats')) const LegendRow(LegendMark.catDot, '띠 안 사건 분류별 글줄: 한 띠에 분류가 둘 이상이면 분류마다 글줄 하나, 글줄 사이는 옅은 점선. 왼쪽 줄 이름 칸의 색 점이 그 글줄의 분류', color: Color(0xffd4a39b)),
      const LegendRow(LegendMark.bird, '조감(띠 밀도 넷째 · V · ↕): 줄이 띠 하나 높이로 — 이름은 띠 안 왼쪽, 사건은 작은 점 · 개수 알약'),
      const LegendRow(LegendMark.cellSpot, '칸 기간 조명: 띠 안의 지도자·내각·시기·지위 칸, 날짜 칸의 연호·도읍 칸을 누르면 그 칸은 진하게, 띠 안의 그 기간은 옅게 칠해지고 그 칸의 창이 열림', color: Color(0xff9dbea8)),
      if (f.got('cellAlt')) const LegendRow(LegendMark.cellAlt, '칸의 다른 견해(이설): 이설이 말하는 경계 해에 칸 높이만 한 옅은 점선(유령 구분선) — 진짜 구분선은 그대로'),
      if (f.got('cellFuzzy')) const LegendRow(LegendMark.cellFuzzy, '연대가 모호한 칸(추정 · 전승 · 이르면 ~ 늦으면): 그 구간의 칸 바탕에 띠의 연대 폭과 같은 무늬, 그 구간 안의 경계는 점선'),
      if (f.got('phase')) const LegendRow(LegendMark.phase, '시기 구분(학계): 띠 안 왕조 칸 아래 · 지도자 칸 위에 체계마다 얇은 줄 하나. 누르면 그 기간이 조명되고 시기 창이 열림'),
      if (f.got('rank')) const LegendRow(LegendMark.ranks, '지위: 지도자 칸 위(시기 구분이 있으면 그 아래)의 얇은 지위 단 — 서열이 높을수록 나라 색이 짙음(맨 왼쪽 견본은 서열 밖)', color: _eventColor),
      const LegendRow(LegendMark.house, '가문: 필터의 가문을 켜면 지도자 칸 아래쪽에 그 지도자의 가문 색 줄. 가문 창이 열린 동안 그 가문의 칸이 진해짐', color: _axisColor),
      if (f.got('unknown')) const LegendRow(LegendMark.cellUnknown, '칸의 미정: 시작이나 끝을 모르면 그쪽 끝이 칸 안에서 옅어지며 사라지고 칸 사이 구분선이 점선이 됨'),
      if (f.got('figure')) const LegendRow(LegendMark.figure, '인물 단(띠 안, 기간 막대 아래): 그 나라에서 활동한 사람의 활동 막대 — 이름은 들어갈 때만. 고르면 생몰을 잇는 수명선. 막대가 너무 좁으면 “인물 n명” 한 칸', color: _axisColor),
    ]),
  );

  return groups;
}

LegendMark _markOfKind(int kind) => switch (kind) {
  12 => LegendMark.bandDouble,
  13 => LegendMark.bandDotted,
  14 => LegendMark.bandPlain,
  15 => LegendMark.bandFaint,
  17 => LegendMark.bandPlain,
  _ => LegendMark.band,
};

const _paper = Ui.surface, _sample = Color(0xffbba395), _eventColor = Color(0xffabb3c9), _axisColor = Color(0xffa0bcc5);

/// 맺음말(css의 `.lg-note`).
const legendNote =
    '세로 눈금은 옅은 점선과 한 칸 걸러 깔린 바탕색으로만 표시해 승계선 · 소속선과 섞이지 않습니다. '
    '트랙 이름 · 민족 칸 · 연호 · 도읍 묶음 이름을 누르면 접거나 펼칩니다. '
    '같은 줄은 승계로 이어진 정권만 함께 씁니다. 띠에 마우스를 올리거나 고르면 그 정권의 승계선이 짙어집니다. 필터 바의 체크로 칸 · 선을 켜고 끕니다.';

/// 범례 카드. 앱 틀이 연표 영역을 덮는 자리(`Positioned.fill`)에 놓으면 스스로 왼쪽 아래 12px에 선다.
class LegendCard extends StatefulWidget {
  const LegendCard({super.key, required this.bus});
  final AppBus bus;

  @override
  State<LegendCard> createState() => _LegendCardState();
}

class _LegendCardState extends State<LegendCard> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();
  Animation<double> get _curve => _enter;

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

  @override
  Widget build(BuildContext context) {
    if (!_open && _enter.isDismissed) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        // 상세 창(또는 같은 해 보기)이 열려 있으면 폭이 줄고, 860보다 좁은 창에서는 숨는다.
        final covered = _bus.selection.value != null || _bus.slot('yearPanel').value != null;
        if (covered && box.maxWidth <= 860) return const SizedBox.shrink();
        final width = math.min(covered ? box.maxWidth - 400 : 300.0, math.min(300.0, box.maxWidth - 24));
        if (width <= 0) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, child) => Opacity(
                opacity: _enter.opacity,
                child: Transform.translate(offset: Offset(0, 8 * (1 - _curve.value)), child: child),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width, maxHeight: math.max(60, box.maxHeight - 24)),
                child: GlassCard(
                  radius: 12,
                  blur: Ui.blurSoft,
                  color: Ui.detailGlass,
                  shadow: Ui.shadow,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: _card(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card() {
    final facts = _facts;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Text(
                '범례',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.text),
              ),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _bus.slot(legendSlot).value = false,
                  child: Semantics(
                    button: true,
                    label: '닫기',
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Text('✕', style: TextStyle(fontSize: 13, color: Ui.text2)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (facts == null)
          Text(_failed ? '범례에 쓸 자료를 읽지 못했습니다.' : '읽는 중…', style: const TextStyle(fontSize: 12, color: Ui.text3))
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in buildLegend(facts)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                      child: Text(
                        g.title,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .46, color: Ui.text3),
                      ),
                    ),
                    for (final row in g.rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            LegendGlyph(mark: row.mark, color: row.color ?? _sample),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(row.text, style: const TextStyle(fontSize: 12, color: Ui.text2, height: 1.45)),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(legendNote, style: TextStyle(fontSize: 11.5, color: Ui.text3, height: 1.45)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 범례의 작은 견본 그림(34px 자리). 글자가 아니라 그림이라 글꼴에 흔들리지 않는다.
class LegendGlyph extends StatelessWidget {
  const LegendGlyph({super.key, required this.mark, this.color = _sample});
  final LegendMark mark;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(width: 34, height: 22, child: CustomPaint(painter: _GlyphPainter(mark, color)));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.mark, this.color);
  final LegendMark mark;
  final Color color;

  Color _mix(double t, [Color other = _paper]) => Color.lerp(other, color, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final band = Rect.fromLTWH(0, cy - 6, 34, 12);
    final edge = Paint()
      ..color = _mix(.55, const Color(0x00ffffff))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dot = Paint()..color = color;
    // 관계선(승계 · 부흥 · 합류 · 소속선)은 그 나라 띠의 테 빛깔 하나 — 투명도 없이(감독 2026-10-16 관계선 색 '가' · 그림판 links.dart LinkLook.inkOf).
    final linkInk = Color(mixOklab(color.toARGB32(), 0xff000000, .84));

    // 불확실한 띠(추정 · 전승 · 미정)의 테 — 파선이 아니라 한 단 옅은 실선(감독 건의 2026-10-15 4번 A — 끊긴 선은 관계선만).
    final softEdge = Paint()
      ..color = _mix(.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    void roundBand({Color? background, bool dashed = false, bool soft = false, double radius = 4, Rect? box, bool border = true}) {
      final r = RRect.fromRectAndRadius((box ?? band).deflate(.5), Radius.circular(radius));
      if (background != null) canvas.drawRRect(r, Paint()..color = background);
      if (!border) return;
      if (dashed) {
        _dashRRect(canvas, r, edge);
      } else {
        canvas.drawRRect(r, soft ? softEdge : edge);
      }
    }

    void hatch(Rect box, {double step = 8, double angle = 135}) {
      canvas.save();
      canvas.clipRect(box);
      final p = Paint()
        ..color = _mix(.35)
        ..strokeWidth = 4;
      final dx = math.cos(angle * math.pi / 180), dy = math.sin(angle * math.pi / 180);
      for (double t = -box.height * 2; t < box.width + box.height * 2; t += step) {
        canvas.drawLine(Offset(box.left + t, box.top), Offset(box.left + t + dx * 40, box.top + dy * -40), p);
      }
      canvas.restore();
    }

    void dashLine(double y, double dash, double gap, Paint p) {
      for (double x = 0; x < 34; x += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset(math.min(34, x + dash), y), p);
      }
    }

    switch (mark) {
      case LegendMark.band:
        roundBand(background: _mix(.24));
      case LegendMark.bandEstimated:
        roundBand(background: _mix(.24), soft: true);
      case LegendMark.bandLegend:
        roundBand(background: _mix(.1));
        hatch(band);
        roundBand(soft: true);
      case LegendMark.bandRange:
        roundBand(background: _mix(.06));
        canvas.save();
        canvas.clipRect(band);
        final p = Paint()
          ..color = _mix(.3)
          ..strokeWidth = 2;
        for (double x = 1; x < 34; x += 5) {
          canvas.drawLine(Offset(x, band.top), Offset(x, band.bottom), p);
        }
        canvas.restore();
        roundBand();
      case LegendMark.bandUnknown:
        // 왼쪽이 둥글게 사라지는 띠: 왼쪽으로 갈수록 옅게.
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            band,
            topLeft: const Radius.circular(8),
            bottomLeft: const Radius.circular(8),
            topRight: const Radius.circular(4),
            bottomRight: const Radius.circular(4),
          ),
          Paint()..shader = LinearGradient(colors: [_mix(.06).withValues(alpha: 0), _mix(.24)]).createShader(band),
        );
        roundBand(soft: true);
      case LegendMark.bandFaint:
        roundBand(background: _mix(.07));
      case LegendMark.bandDouble:
        roundBand(border: false);
        canvas.drawRRect(RRect.fromRectAndRadius(band.deflate(.5), const Radius.circular(4)), edge);
        canvas.drawRRect(RRect.fromRectAndRadius(band.deflate(2.5), const Radius.circular(3)), edge);
      case LegendMark.bandDotted:
        roundBand(background: _mix(.16), dashed: true, radius: 2);
      case LegendMark.bandPlain:
        roundBand(background: _mix(.14), border: false);
      // 안개(반전설 · 전설 · 부정됨): 예전에는 아래로 사라지는 투명도였는데, 감독 건의(2026-10-15 2번 — 연한 것은 색 자체를 연하게)대로
      // 고르게 옅은 칠 + 옅은 실선 테(그림판 bands.dart의 fogSolid · unsureEdge와 같은 결).
      case LegendMark.bandFogBottom:
        roundBand(background: _mix(.18), soft: true);
      case LegendMark.bandFog:
        roundBand(background: _mix(.12), soft: true);
      case LegendMark.bandGray:
        // 부정됨: 전설의 안개를 색 없이 회색으로(묶음 5 · 5번).
        roundBand(background: Color.lerp(_paper, const Color(0xff666666), .12), soft: true);
      case LegendMark.bandScope:
        roundBand(background: _mix(.18), box: Rect.fromLTWH(4, cy - 4, 26, 8), radius: 3);
        _dashRRect(canvas, RRect.fromRectAndRadius(Rect.fromLTWH(.5, cy - 8.5, 33, 17), const Radius.circular(5)), edge);
      case LegendMark.bandHollow:
        roundBand(dashed: false, background: const Color(0x00000000));
        canvas.drawRRect(RRect.fromRectAndRadius(band.deflate(.5), const Radius.circular(4)), edge);
      case LegendMark.dot:
        canvas.drawCircle(Offset(17, cy), 3.5, dot);
      case LegendMark.dotHollow:
        canvas.drawCircle(Offset(17, cy), 3.5, Paint()..color = _paper);
        canvas.drawCircle(
          Offset(17, cy),
          3.5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      case LegendMark.dotDashed:
        _dashCircle(
          canvas,
          Offset(17, cy),
          5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case LegendMark.square:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(17, cy), width: 7, height: 7), const Radius.circular(2)), dot);
      case LegendMark.squareHollow:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(17, cy), width: 7, height: 7), const Radius.circular(2)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      case LegendMark.diamond:
      case LegendMark.diamondHollow:
        canvas.save();
        canvas.translate(17, cy);
        canvas.rotate(math.pi / 4);
        final box = Rect.fromCenter(center: Offset.zero, width: 6, height: 6);
        canvas.drawRect(
          box,
          mark == LegendMark.diamond
              ? dot
              : (Paint()
                  ..color = color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5),
        );
        canvas.restore();
      case LegendMark.line:
        canvas.drawLine(
          Offset(0, cy),
          Offset(34, cy),
          Paint()
            ..color = linkInk
            ..strokeWidth = 1.6,
        );
      case LegendMark.lineThin:
        canvas.drawRect(Rect.fromLTWH(0, cy.floorToDouble(), 34, 1), Paint()..color = linkInk);
      case LegendMark.lineDashed:
        dashLine(
          cy,
          4,
          3,
          Paint()
            ..color = linkInk
            ..strokeWidth = 1.6,
        );
      case LegendMark.union:
        final cellPaint = Paint()..color = _mix(.18);
        final cellEdge = Paint()
          ..color = _mix(.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        for (final top in [cy - 8, cy + 4]) {
          final cell = RRect.fromRectAndRadius(Rect.fromLTWH(3.5, top + .5, 27, 4), const Radius.circular(2));
          canvas.drawRRect(cell, cellPaint);
          canvas.drawRRect(cell, cellEdge);
        }
        final ink = Paint()
          ..color = const Color(0x99000000)
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(17, cy - 3.5), Offset(17, cy + 4.5), ink);
        for (final y in [cy - 3.5, cy + 4.5]) {
          canvas.drawCircle(Offset(17, y), 2, Paint()..color = _paper);
          canvas.drawCircle(
            Offset(17, y),
            2,
            Paint()
              ..color = const Color(0xff000000)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
      case LegendMark.lineDotted:
        dashLine(
          cy,
          1.5,
          2.5,
          Paint()
            ..color = linkInk
            ..strokeWidth = 1.5,
        );
      case LegendMark.rail:
      case LegendMark.railTreaty:
      case LegendMark.railAlt:
        final thin = Paint()..color = color.withValues(alpha: .7);
        if (mark == LegendMark.railTreaty) {
          canvas.drawRect(Rect.fromLTWH(0, cy - 2, 34, 1), thin);
          canvas.drawRect(Rect.fromLTWH(0, cy + 1, 34, 1), thin);
        } else {
          canvas.drawRect(Rect.fromLTWH(0, cy - 1, 34, 2), thin);
        }
        final bar = Paint()..color = color;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - 3.5, 1.5, 7), const Radius.circular(1)), bar);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(32.5, cy - 3.5, 1.5, 7), const Radius.circular(1)), bar);
        if (mark == LegendMark.railAlt) {
          for (double y = cy - 5.5; y < cy + 5.5; y += 4) {
            canvas.drawRect(Rect.fromLTWH(10, y, 1.5, 2), bar);
          }
        }
      case LegendMark.beads:
        dashLine(
          cy,
          1.5,
          2,
          Paint()
            ..color = color
            ..strokeWidth = 1,
        );
        canvas.drawCircle(Offset(4, cy), 2.6, dot);
        for (final x in const [15.0, 26.0]) {
          canvas.drawCircle(Offset(x, cy), 2.4, Paint()..color = _paper);
          canvas.drawCircle(
            Offset(x, cy),
            2.4,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
      case LegendMark.cell:
      case LegendMark.cellAxis:
      case LegendMark.house:
      case LegendMark.cellUnknown:
      case LegendMark.cellAlt:
      case LegendMark.cellFuzzy:
      case LegendMark.cellSpot:
        final box = Rect.fromLTWH(6, cy - 5.5, 22, 11);
        final r = RRect.fromRectAndRadius(box.deflate(.5), const Radius.circular(3));
        canvas.drawRRect(r, Paint()..color = _mix(mark == LegendMark.cellAxis ? .12 : .15));
        if (mark == LegendMark.cellSpot) {
          canvas.drawRect(Rect.fromLTWH(box.left + box.width * .3, box.top, box.width * .4, box.height), Paint()..color = _mix(.45));
        }
        if (mark == LegendMark.cellFuzzy) {
          final p = Paint()
            ..color = _mix(.4)
            ..strokeWidth = 1.5;
          for (double x = box.left + 2; x < box.right; x += 4) {
            canvas.drawLine(Offset(x, box.top + 1), Offset(x, box.bottom - 1), p);
          }
        }
        if (mark == LegendMark.house) {
          canvas.drawRect(Rect.fromLTWH(box.left + 3, box.bottom - 3, 16, 2), Paint()..color = _mix(.72, const Color(0xff000000)));
        }
        if (mark == LegendMark.cellUnknown) {
          canvas.drawRRect(
            r,
            Paint()
              ..color = _mix(.45, const Color(0x00ffffff))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
          _dashLineV(canvas, box.right - .5, box.top, box.bottom, edge);
        } else if (mark == LegendMark.cellAlt) {
          canvas.drawRRect(r, edge);
          _dashLineV(
            canvas,
            box.left + box.width * .55,
            box.top,
            box.bottom,
            Paint()
              ..color = _mix(.6, const Color(0x00ffffff))
              ..strokeWidth = 1,
          );
        } else {
          canvas.drawRRect(r, edge);
        }
      case LegendMark.hostTab:
        // 상국 표기 C(건의 8의 2번 · 지금 연표 Timeline.hostTabSample): 속국 띠 뒤에 상국 빛깔의 뒤 장(양 끝은 띠에 맞추고 위로만 조금), 상국 탭은 뒤 장과
        // 한 장(같은 칠 · 테)으로 관계가 끝나는 오른쪽 평평한 윗변에, 제 이름 탭은 왼쪽 띠 윗변 위로 — 연표와 같은 S자 어깨 · 띠 둘레에 종이빛 틈.
        Path bump(double x, double y, double w, double s) => Path()
          ..moveTo(x, y + 1)
          ..cubicTo(x + s * .6, y + 1, x + s * .4, y - 6, x + s, y - 6)
          ..lineTo(x + w - s, y - 6)
          ..cubicTo(x + w - s * .4, y - 6, x + w - s * .6, y + 1, x + w, y + 1);
        final pen = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        const hostC = Color(0xffa0bcc5);
        final hostEdge = Color.lerp(hostC, const Color(0xff000000), .22)!;
        final host = bump(16, cy - 2.5, 11, 4), own = bump(2, cy, 11, 4);
        canvas.drawPath(Path.from(host)..close(), Paint()..color = Color.lerp(_paper, hostC, .46)!);
        canvas.drawPath(host, pen..color = hostEdge);
        final sheet = RRect.fromRectAndRadius(Rect.fromLTWH(.5, cy - 1.5, 30, 6), const Radius.circular(3));
        canvas.drawRRect(sheet, Paint()..color = Color.lerp(_paper, hostC, .46)!);
        canvas.drawRRect(sheet, pen..color = hostEdge);
        final bandR = RRect.fromRectAndRadius(Rect.fromLTWH(.5, cy + 1, 30, 6), const Radius.circular(3));
        canvas.drawRRect(bandR.inflate(1), Paint()..color = _paper);
        canvas.drawPath(Path.from(own)..close(), Paint()..color = _mix(.2));
        canvas.drawPath(own, pen..color = edge.color);
        canvas.drawRRect(bandR, Paint()..color = _mix(.2));
        canvas.drawRRect(bandR, edge);
      case LegendMark.hangLoose:
      case LegendMark.hangFirm:
      case LegendMark.hangIn:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(1, cy - 7, 32, 7), const Radius.circular(2)), Paint()..color = _mix(.2));
        final tab = Rect.fromLTWH(6, cy + 1, 13, 6);
        final tabRect = RRect.fromRectAndRadius(tab, const Radius.circular(2));
        if (mark == LegendMark.hangIn) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, cy - 6, 13, 5), const Radius.circular(1.5)), Paint()..color = _mix(.45));
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20, cy - 6, 12, 5), const Radius.circular(1.5)), Paint()..color = _mix(.18));
        } else {
          canvas.drawRRect(tabRect, mark == LegendMark.hangFirm ? (Paint()..color = _mix(.45)) : (Paint()..color = _paper));
          canvas.drawRRect(tabRect, edge);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(21, cy + 1, 11, 6), const Radius.circular(2)), Paint()..color = _mix(.45));
        }
      case LegendMark.phase:
        canvas.drawRect(Rect.fromLTWH(4, cy - 5, 26, 5), Paint()..color = _mix(.22));
        canvas.drawRect(Rect.fromLTWH(4, cy + 1, 26, 5), Paint()..color = _mix(.12));
      case LegendMark.ranks:
        for (int i = 0; i < 5; i++) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * 6.8, cy - 4.5, 6, 9), const Radius.circular(2)), Paint()..color = _mix(const [0.0, .08, .22, .38, .56][i]));
        }
      case LegendMark.figure:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(3, cy - 4, 28, 8), const Radius.circular(2)), Paint()..color = _mix(.35));
        canvas.drawLine(
          Offset(0, cy),
          Offset(3, cy),
          Paint()
            ..color = _mix(.5)
            ..strokeWidth = 1,
        );
        canvas.drawLine(
          Offset(31, cy),
          Offset(34, cy),
          Paint()
            ..color = _mix(.5)
            ..strokeWidth = 1,
        );
      case LegendMark.catDot:
        canvas.drawCircle(Offset(17, cy), 3.5, dot);
        canvas.drawCircle(
          Offset(17, cy),
          4.2,
          Paint()
            ..color = _mix(.8, const Color(0xff000000))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case LegendMark.bird:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, cy - 3.5, 22, 7), const Radius.circular(2.5)), Paint()..color = _mix(.2));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6.5, cy - 3, 21, 6), const Radius.circular(2.5)), edge);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.mark != mark || old.color != color;
}

void _dashRRect(Canvas canvas, RRect r, Paint paint) {
  final path = Path()..addRRect(r);
  for (final metric in path.computeMetrics()) {
    for (double d = 0; d < metric.length; d += 6) {
      canvas.drawPath(metric.extractPath(d, math.min(d + 3, metric.length)), paint);
    }
  }
}

void _dashCircle(Canvas canvas, Offset center, double radius, Paint paint) {
  for (double a = 0; a < math.pi * 2; a += math.pi / 6) {
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a, math.pi / 12, false, paint);
  }
}

void _dashLineV(Canvas canvas, double x, double top, double bottom, Paint paint) {
  for (double y = top; y < bottom; y += 4) {
    canvas.drawLine(Offset(x, y), Offset(x, math.min(bottom, y + 2)), paint);
  }
}
