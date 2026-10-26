import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../motion_spring.dart';
import '../scene/layout.dart';
import '../scene/aux_calendar.dart';
import '../scene/paint/bands.dart' show BandKind;
import '../shell/sheet_look.dart';
import '../shell/sheet_parts.dart';
import 'app_bus.dart';
import 'filter_state.dart';
import 'names_display.dart';
import 'shell_keys.dart';

// 필터 시트의 속 — 앱 틀의 FilterSheet(child: …) 안에 들어간다(명세 06-상세-검색-필터-도구.md 6절).
// 꼴은 리메이크 4단계 서고 시트(감독 고름 G5 #9 다듬기 판의 필터 시트 — 목업 g-sheet-search `drawFilter` · 부품 `shell/sheet_parts.dart`):
//   같은 너비의 상자 두 열([SheetColumns]) — 왼쪽 트랙 · 분류 · 종류 · 실재성 · 대범위, 오른쪽 띠 안 · 날짜 칸 · 선·견해 · 표기 · 중요도 —
//   와 가로대(먹 12) 아래의 발(관점 · 밀도 · 조감 고르는 칸 + '축소하면 조감' · 오른쪽 끝 도구 단추).
//   켬 = 그림판 그대로(꼬리표 칠 · 매듭 칠 · 사건 점), 끔 = 흰 종이 · 먹 25 실선 · 글 먹 45.
// 칩의 항목 · 누르는 길(누름 · Alt+누름 = 이것만 보기) · 풍선 · 읽기 글 · 기억은 4단계 전 그대로다 — 바뀐 것은 그리는 꼴뿐.
//
// 이 부품이 바깥과 주고받는 것은 AppBus뿐이다:
//  - 상태: bus.slot('filters')에 [FilterState]를 싣는다(다른 부품도 읽고 쓸 수 있다 — 상세 창의 '같은 시기를 타국에도' 스위치).
//  - 보기 조건: 띠 안의 단 켬/끔과 밀도는 bus.conditions에도 옮긴다(앱 틀이 듣고 줄을 다시 쌓는다).
//  - 모두 접기/펴기: bus.slot('foldAll')에 바라는 상태(참 = 모두 접힘)를 적는다. 지금 접혔는지도 같은 자리에서 읽는다.
//  - 칩의 목록: 트랙 · 분류는 bus.scene.layout에서, 종류 · 실재성 · 쓰인 분류는 {op:'legend_kinds'}, 대범위는 {op:'scopes'}에서.

/// `{"op":"legend_kinds"}` · `{"op":"scopes"}`의 답을 읽어 둔 것. 명령이 아직 없으면 빈 값이고, 그러면 그 칩 줄은 나오지 않는다.
@immutable
class _ChipSource {
  const _ChipSource({this.kinds = const [], this.kindEnds = const {}, this.historicity = const [], this.categories, this.scopes = const []});

  /// 지금 자료에 쓰인 정권 종류 · 실재성(둘 다 `{id, name}`).
  final List<FilterOption<String>> kinds, historicity;

  /// 종류 칩의 끝 꼴(종류 id → 그림판 꼬리표와 같은 갈래).
  final Map<String, SheetTagKind> kindEnds;

  /// 사건에 쓰인 분류 번호. 모르면 null(= 다 보인다).
  final Set<int>? categories;
  final List<_ScopeChip> scopes;
}

@immutable
class _ScopeChip {
  const _ScopeChip(this.uid, this.track, this.name, this.color, this.label, this.members, this.byDefault);
  final String uid, name, label;
  final int track, color, members;
  final bool byDefault;
}

/// 종류 한 줄(`{id, kind?, name}`)의 종류 번호 — 엔진은 번호(`kind` · `id`)를, 옛 답 · 견본은 종류 id('state' · 'movement' …)를 준다.
/// 번호는 계약 6-1의 차례(= 그림판 [BandKind]). 모르면 −1(모따기).
int _kindNumber(Map<dynamic, dynamic> raw) {
  final kind = raw['kind'];
  if (kind is num) return kind.toInt();
  final id = '${raw['id']}';
  return int.tryParse(id) ?? _kindIds[id] ?? -1;
}

/// 종류 id → 번호(그림판 [BandKind]의 거울 — 엔진 query.rs `BAND_KINDS`와 같은 차례).
const _kindIds = <String, int>{
  'state': BandKind.state, 'tributary': BandKind.tributary, 'fief': BandKind.fief, 'dominion': BandKind.dominion, 'warlord': BandKind.warlord,
  'vassal': BandKind.vassal, 'protectorate': BandKind.protectorate, 'satellite': BandKind.satellite, 'puppet': BandKind.puppet,
  'mandate': BandKind.mandate, 'colony': BandKind.colony, 'occupied': BandKind.occupied, 'federation': BandKind.federation, 'org': BandKind.org,
  'era': BandKind.era, 'exile': BandKind.exile, 'movement': BandKind.movement, 'culture': BandKind.culture, 'overlay': BandKind.overlay,
  'dynasty': BandKind.dynasty, 'client': BandKind.client, 'frontier': BandKind.frontier, 'prefecture': BandKind.prefecture,
};

class FilterSheetBody extends StatefulWidget {
  const FilterSheetBody({super.key, required this.bus, this.tools, this.seed});

  final AppBus bus;

  /// 필터 값이 아직 없을 때(시트를 연 적이 없는 기억 · 측정 모드) 시트가 시작할 첫 값을 짓는 길 — 앱 틀은 이어 붙이기의 `AppGlue.filters`
  /// (지금 보기 조건 + 기억의 조감 전 밀도)를 준다. 없으면 지금 보기 조건에서 짓는다([FilterState.orSeed]). 0.1.1: 예전에는 기본값에서 시작해
  /// 첫 그리기 뒤 그 값을 보기 조건으로 돌려 조감 · 끈 단이 풀렸다.
  final FilterState Function()? seed;

  /// 시트 발 오른쪽 끝의 도구 단추 줄(📍 같은 해 보기 · 📏 기간 재기 · 📋 표 보기 · 📷 이미지·인쇄 · ❔ 범례).
  /// 그것은 명세 7절(단위 L)의 몫이라 여기서는 자리만 내어 준다 — 없으면 그 자리도 없다.
  final Widget? tools;

  @override
  State<FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<FilterSheetBody> {
  _ChipSource _source = const _ChipSource();
  int _askedVersion = -1;

  ValueNotifier<Object?> get _slot => widget.bus.slot('filters');
  ValueNotifier<Object?> get _foldSlot => widget.bus.slot('foldAll');

  /// 필터 값 — 슬롯에 실린 값, 아직 없으면 [FilterSheetBody.seed]의 첫 값(없으면 지금 보기 조건에서 — [FilterState.orSeed]).
  FilterState get _state {
    final value = _slot.value;
    if (value is FilterState) return value;
    return widget.seed?.call() ?? FilterState.orSeed(null, widget.bus.conditions.value);
  }

  @override
  void initState() {
    super.initState();
    _slot.addListener(_onChanged);
    _foldSlot.addListener(_onChanged);
    widget.bus.slot('yearCycle').addListener(_onChanged);
    // '표기' 무리(10건 3 · 9 — 갈래 D2): 표기 설정 · 이름 정보(이름 목록 · 글꼴이 있는 자료집)가 바뀌면 다시 그린다.
    widget.bus.slot(slotNames).addListener(_onChanged);
    widget.bus.slot(slotNamesInfo).addListener(_onChanged);
    widget.bus.scene.addListener(_onScene);
    // 기억해 둔 값이 이미 실려 있으면 그것이 첫 값이고, 없으면 지금 보기 조건에서 지은 값([_state])이다 — 어느 쪽이든 연표의 보기 조건을 한 번 맞춰 둔다
    // (첫 값이 보기 조건과 같으므로 시트를 연 것만으로 조감 · 켠 단이 바뀌지 않는다).
    // 알리는 것은 첫 그리기가 끝난 뒤에 — 듣는 쪽(앱 틀)이 그리는 도중에 다시 그리라는 말을 듣지 않게.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_slot.value is! FilterState) _slot.value = _state;
      widget.bus.conditions.value = _state.toConditions();
    });
    _askChips();
  }

  @override
  void dispose() {
    _slot.removeListener(_onChanged);
    _foldSlot.removeListener(_onChanged);
    widget.bus.slot('yearCycle').removeListener(_onChanged);
    widget.bus.slot(slotNames).removeListener(_onChanged);
    widget.bus.slot(slotNamesInfo).removeListener(_onChanged);
    widget.bus.scene.removeListener(_onScene);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 자료집을 켜고 끄면 쓰인 종류 · 실재성 · 대범위가 달라진다 — 조합이 바뀐 때만 다시 묻는다.
  void _onScene() {
    if (widget.bus.scene.layout.version != _askedVersion) _askChips();
  }

  Future<void> _askChips() async {
    final version = widget.bus.scene.layout.version;
    _askedVersion = version;
    final legend = await _ask({'op': 'legend_kinds'});
    final scopes = await _ask({'op': 'scopes'});
    if (!mounted) return;
    setState(() {
      _source = _ChipSource(
        kinds: _options(legend?['kinds']),
        kindEnds: {
          for (final x in (legend?['kinds'] as List? ?? const []))
            if (x is Map) '${x['id']}': sheetTagKindOf(_kindNumber(x)),
        },
        historicity: _options(legend?['historicity']),
        categories: legend?['categories'] is List ? {for (final c in legend!['categories'] as List) (c as num).toInt()} : null,
        scopes: [
          for (final s in (scopes?['scopes'] as List? ?? const []))
            if (s is Map)
              _ScopeChip('${s['uid']}', (s['track'] as num? ?? 0).toInt(), '${s['name']}', (s['color'] as num? ?? 0xa4b1b7).toInt(), '${s['label'] ?? ''}',
                  (s['members'] as num? ?? 0).toInt(), s['default'] == true),
        ],
      );
    });
  }

  /// 아직 없는 조회 명령은 빈 답으로 친다 — 그 칩 줄만 나오지 않고 나머지는 그대로 쓴다.
  Future<Map<String, dynamic>?> _ask(Map<String, dynamic> query) async {
    try {
      return await widget.bus.ask(query);
    } catch (_) {
      return null;
    }
  }

  static List<FilterOption<String>> _options(Object? raw) => [
    for (final x in (raw as List? ?? const []))
      if (x is Map) FilterOption('${x['id']}', '${x['name']}'),
  ];

  void _set(FilterState next) {
    // `같은 시기를 타국에도`는 상세 창의 스위치(slot 'echo')와 한 값이다.
    if (next.showing('spotEcho') != _state.showing('spotEcho')) widget.bus.slot('echo').value = next.showing('spotEcho');
    _slot.value = next;
    widget.bus.conditions.value = next.toConditions();
  }

  /// 칩 누르기. Alt를 누른 채면 '이것만 보기'. 누름마다 그때의 슬롯 값([_state])에서 셈한다 — 그리던 때 잡아 둔 값이 아니라
  /// (그리기 사이에 여러 번 눌러도 앞의 누름을 덮어쓰지 않게). 다른 칸의 누름도 모두 같다.
  void _tapChip(ChipGroup group, String id, List<String> all) {
    final alt = HardwareKeyboard.instance.isAltPressed;
    _set(alt ? _state.onlyChip(group, id, all) : _state.toggleChip(group, id));
  }

  /// 대범위 칩은 거르기가 아니라 모아 보기다: 모여드는 움직임을 시트가 가리지 않게 **시트를 먼저 접고**(--t-out) 켠다(명세 6-3 · 9절 ㈐-17).
  /// 시트가 접히면 이 부품은 사라지므로, 뒤에 할 일은 위젯이 아니라 AppBus에 맡긴다.
  void _tapScope(_ScopeChip scope) {
    final bus = widget.bus;
    _set(_state.copyWith(filterOpen: false));
    MotionStage.instance.schedule(Motion.out, () {
      final slot = bus.slot('filters');
      final now = FilterState.orSeed(slot.value, bus.conditions.value);
      slot.value = now.toggleScope(scope.uid, fallback: scope.byDefault);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final layout = widget.bus.scene.layout;
    // 집합 보기의 판 트랙(판마다 하나 — 판을 켰을 때만 맨 위에 선다)은 거르는 트랙이 아니다.
    final tracks = [for (int i = 0; i < layout.tracks.length; i++) if (!layout.isBoardTrack(i)) layout.tracks[i]];
    final trackIds = [for (final t in tracks) '${t.id}'];
    final categories = [
      for (final c in layout.categories)
        if (_source.categories == null || _source.categories!.contains(c.id)) c,
    ];
    final categoryIds = [for (final c in categories) '${c.id}'];
    final kindIds = [for (final k in _source.kinds) k.value];
    final historicityIds = [for (final h in _source.historicity) h.value];
    final allFolded = _foldSlot.value == true;
    final axis = axisTogglesFor(widget.bus.slot('yearCycle').value as YearCycle?);
    final names = NamesInfo.of(widget.bus).visible(layout.enabledPacks);

    return SheetColumns(
      left: [
        // 트랙: 자료를 거른다(그 트랙의 정권 · 사건 · 인물 · 시대 구분 · 대범위가 함께 빠진다). 뚜껑 밑 줄 오른쪽에 '모두 접기/펴기'.
        _box(
          '트랙',
          count: tracks.length,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: SheetRun(children: [
                for (final t in tracks)
                  _chip(t.name, t.color, state.chipOn(ChipGroup.tracks, '${t.id}'), () => _tapChip(ChipGroup.tracks, '${t.id}', trackIds)),
              ]),
            ),
            const SizedBox(width: _buttonGap),
            SheetPaperButton(
              label: allFolded ? '모두 펴기' : '모두 접기',
              hint: '모든 트랙을 접거나 펼칩니다',
              onTap: tracks.isEmpty ? null : () => runCommand(widget.bus, Cmd.foldAll),
            ),
          ]),
        ),
        // 분류: 사건만 거른다. 쓰인 분류만 보인다 — 사건 점 칩.
        _box(
          '분류',
          count: categories.length,
          SheetRun(children: [
            for (final c in categories)
              SheetDotChip(
                label: c.name,
                color: Color(0xff000000 | c.color),
                on: state.chipOn(ChipGroup.categories, '${c.id}'),
                hint: _chipHint,
                onTap: () => _tapChip(ChipGroup.categories, '${c.id}', categoryIds),
              ),
          ]),
        ),
        // 종류 · 실재성: 정권과 그 정권에 달린 사건을 거른다. 종류는 둘 이상일 때만, 실재성은 자료에 쓰였을 때만 나온다.
        // 종류 칩의 끝 꼴은 그림판 꼬리표와 같은 갈래(부흥 · 저항 = 둥근 끝 · 복속 세력 = 직각 · 그 밖 = 모따기).
        if (_source.kinds.length >= 2)
          _box(
            '종류',
            count: _source.kinds.length,
            SheetRun(children: [
              for (final k in _source.kinds)
                _chip(k.name, _neutralChip, state.chipOn(ChipGroup.kinds, k.value), () => _tapChip(ChipGroup.kinds, k.value, kindIds), kind: _source.kindEnds[k.value] ?? SheetTagKind.cham),
            ]),
          ),
        if (_source.historicity.isNotEmpty)
          _box(
            '실재성',
            count: _source.historicity.length,
            SheetRun(children: [
              for (final h in _source.historicity)
                _chip(h.name, _neutralChip, state.chipOn(ChipGroup.historicity, h.value), () => _tapChip(ChipGroup.historicity, h.value, historicityIds)),
            ]),
          ),
        if (_source.scopes.isNotEmpty) _scopeBox(state, tracks),
      ],
      right: [
        _box('띠 안', count: bandToggles.length + 1, SheetRun(children: _bandChecks(state))),
        _box('날짜 칸', count: axis.length, SheetRun(children: [for (final t in axis) _check(t, state)])),
        _box('선·견해', count: lineToggles.length, SheetRun(children: [for (final t in lineToggles) _check(t, state)])),
        if (names) _box('표기', SheetRun(children: _namesChecks(layout))),
        _box(
          '중요도',
          SheetChain<int>(
            items: [for (final o in importanceOptions) (o.value, o.name)],
            value: state.minImportance,
            semantics: '중요도 필터',
            onSelect: (v) => _set(_state.copyWith(minImportance: v)),
          ),
        ),
      ],
      footer: _foot(state, tracks),
    );
  }

  /// 발: 가로대(먹 12) 아래에 보기 고르기 셋 + '축소하면 조감', 오른쪽 끝에 도구 단추(목업의 `rail + 13`).
  Widget _foot(FilterState state, List<TrackInfo> tracks) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: _railGap),
      const ColoredBox(color: SheetLook.ink12, child: SizedBox(height: 1)),
      const SizedBox(height: _railGap),
      SheetRun(
        alignment: WrapAlignment.spaceBetween,
        spacing: _toolsGap,
        runSpacing: 8,
        children: [
          SheetRun(spacing: _footGap, runSpacing: 8, children: [
            SheetChoice<String>(
              title: '관점',
              value: [for (final o in _lensOptions(tracks)) o.$1].contains(state.lens) ? state.lens : '',
              options: _lensOptions(tracks),
              semantics: '관점',
              hint: '같은 사건을 어느 나라의 이름으로 보여 줄지 고릅니다',
              onChanged: (v) => _set(_state.copyWith(lens: v)),
            ),
            SheetChoice<int>(
              title: '밀도',
              value: state.density,
              options: [for (final o in densityOptions) (o.value, o.name)],
              semantics: '띠 밀도',
              hint: '정권 띠의 높이와 글자 크기 — 조감은 줄을 띠 하나 높이로 줄여 모든 나라를 한눈에 (V)',
              onChanged: (v) => _set(_state.withDensity(v)),
            ),
            SheetChoice<String>(
              title: '조감',
              value: state.birdShape,
              options: [for (final o in birdShapeOptions) (o.value, o.name)],
              semantics: '조감 모양',
              hint: '조감에서 띠 안에 남길 것',
              onChanged: (v) => _set(_state.copyWith(birdShape: v)),
            ),
            SheetKeyToggle(
              label: '축소하면 조감',
              hint: '가로로 많이 축소하면 저절로 조감으로, 다시 확대하면 고른 밀도로 돌아옵니다',
              on: state.birdAuto,
              onTap: () => _set(_state.copyWith(birdAuto: !_state.birdAuto)),
            ),
          ]),
          ?widget.tools,
        ],
      ),
    ],
  );

  /// 띠 안 묶음 — 지도자 다음에 표기 고르기와 '대수'가 끼어든다(지금 연표의 차례 그대로).
  List<Widget> _bandChecks(FilterState state) => [
    for (final t in bandToggles) ...[
      _check(t, state),
      if (t.key == 'leaders') ...[
        SheetChoice<String>(
          title: '지도자',
          value: state.leaderLabel,
          options: [for (final o in leaderLabelOptions) (o.value, o.name)],
          semantics: '지도자 표기',
          hint: '지도자 칸에 묘호·시호·이름 중 무엇을 적을지',
          onChanged: (v) => _set(_state.copyWith(leaderLabel: v)),
        ),
        SheetKeyToggle(
          label: '대수',
          hint: "지도자 이름 앞에 '4대'처럼 대수를 붙입니다",
          on: state.leaderOrdinal,
          onTap: () => _set(_state.copyWith(leaderOrdinal: !_state.leaderOrdinal)),
        ),
      ],
    ],
  ];

  /// '표기' 무리(10건 3 · 9 — 감독 결정 D2-3 A · 5 A, 웹 viewer.js의 #namesGroup과 같은 차례 · 같은 글):
  /// [원어: 상세 창만 ▾] · 적용 나라 · 인물 · 지명 · [글꼴 ▾](켜진 DLC에 글꼴이 있을 때만). 무리는 켜진 자료집에 이름 목록이나
  /// 글꼴이 있을 때만 보인다. 값은 bus.slot('names')(NamesUi — 기억은 고를 때만 parts['names']).
  /// 글꼴: 한글을 덮지 않는 글꼴은 고를 수 없다('(없는 글자에만)' — 화면 글꼴에 없는 글자 채우기로만 쓴다). 화면 글꼴은 앱을 다시 켤 때 바뀐다.
  /// 글꼴 줄마다 올리면 '팩 이름 · 라이선스'(웹 `<option title>`과 같은 글).
  List<Widget> _namesChecks(SceneLayout layout) {
    final bus = widget.bus;
    final ui = NamesUi.of(bus);
    final fonts = NamesInfo.of(bus).fontsOn(layout.enabledPacks);
    String fontTip(FontEntry f) {
      final pack = layout.packs.where((p) => p.id == f.pack).firstOrNull?.name ?? '';
      return '${pack.isEmpty ? '' : '$pack · '}라이선스 ${f.license}${f.hangul ? '' : ' — 한글이 없는 글꼴이라 화면 글꼴로는 쓰지 않고, 화면 글꼴에 없는 글자에만 씁니다'}';
    }

    void set(NamesUi next) => NamesGlue.set(bus, next);
    return [
      SheetChoice<String>(
        value: ui.orig,
        options: [for (final o in NamesUi.origOptions) (o.$1, '원어: ${o.$2}')],
        semantics: '원어 함께 적기',
        hint: '원어(제 말 · 제 글자로 적은 이름)를 어디까지 함께 적을지 — 상세 창의 이름 아래 · 연표 맨 왼쪽 줄 이름 칸',
        onChanged: (v) => set(NamesUi.of(bus).copyWith(orig: v)),
      ),
      Tooltip(
        message: '원어 고르기를 어느 이름에 쓸지',
        child: Text('적용', maxLines: 1, softWrap: false, style: sheetText(SheetLook.chipText, bold: true, color: SheetLook.ink60)),
      ),
      SheetKeyToggle(label: '나라', hint: '나라 · 왕조 · 가문 · 성씨 · 연호 · 내각 · 단체 · 제도의 이름에', on: ui.polity, onTap: () => set(NamesUi.of(bus).copyWith(polity: !NamesUi.of(bus).polity))),
      SheetKeyToggle(label: '인물', hint: '지도자 · 인물의 이름에', on: ui.person, onTap: () => set(NamesUi.of(bus).copyWith(person: !NamesUi.of(bus).person))),
      SheetKeyToggle(label: '지명', hint: '도읍 · 지명에', on: ui.place, onTap: () => set(NamesUi.of(bus).copyWith(place: !NamesUi.of(bus).place))),
      if (fonts.isNotEmpty)
        SheetChoice<String>(
          value: fonts.any((f) => f.uid == ui.screen && f.hangul) ? ui.screen! : '',
          options: [
            ('', '글꼴: 기본'),
            for (final f in fonts) (f.uid, f.hangul ? '글꼴: ${f.family}' : '글꼴: ${f.family} (없는 글자에만)'),
          ],
          disabled: {for (final f in fonts) if (!f.hangul) f.uid},
          tips: {for (final f in fonts) f.uid: fontTip(f)},
          semantics: '화면 글꼴',
          hint: '화면 글꼴 — 한글을 덮는 글꼴 팩을 고르면 앱을 다시 켤 때부터 화면 전체가 그 글꼴로. 화면 글꼴에 없는 글자는 켜진 글꼴 팩이 저절로 채웁니다',
          onChanged: (v) => set(v.isEmpty ? NamesUi.of(bus).copyWith(noScreen: true) : NamesUi.of(bus).copyWith(screen: v)),
        ),
    ];
  }

  Widget _check(ShowToggle toggle, FilterState state) => SheetKeyToggle(
    label: toggle.label,
    hint: toggle.hint,
    on: state.showing(toggle.key),
    onTap: () => _set(_state.withShowing(toggle.key, !_state.showing(toggle.key))),
  );

  List<(String, String)> _lensOptions(List<TrackInfo> tracks) => [
    ('', '기본'),
    ('local', '나라마다 제 이름'),
    for (final t in tracks) ('${t.id}', t.name),
  ];

  /// 대범위 상자: 폴더 칩(모아 보기). 칩이 한 트랙의 것뿐이면 그 트랙의 작은 꼬리표를 뚜껑 오른쪽에(목업 그대로),
  /// 둘 이상의 트랙이면 트랙마다 칩 앞에 작은 꼬리표를 세워 묶는다(어느 트랙의 대범위인지 잃지 않게). 끈 트랙의 대범위는 보이지 않는다.
  Widget _scopeBox(FilterState state, List<TrackInfo> tracks) {
    final byTrack = <int, List<_ScopeChip>>{};
    for (final s in _source.scopes) {
      if (!state.chipOn(ChipGroup.tracks, '${s.track}')) continue;
      byTrack.putIfAbsent(s.track, () => []).add(s);
    }
    TrackInfo? trackOf(int id) {
      for (final t in tracks) {
        if (t.id == id) return t;
      }
      return null;
    }

    Widget tag(int id) => SheetSmallTag(label: trackOf(id)?.name ?? '', color: Color(0xff000000 | (trackOf(id)?.color ?? _neutralChip)));
    Widget chip(_ScopeChip s) {
      final on = state.scopeOn(s.uid, fallback: s.byDefault);
      return SheetScopeChip(
        label: s.name,
        color: Color(0xff000000 | s.color),
        on: on,
        hint: '${s.name}${s.label.isEmpty ? '' : ' · ${s.label}'} — 누르면 모아 보기 ${on ? '끄기' : '켜기'} (구성 정권 ${s.members}곳)',
        onTap: () => _tapScope(s),
      );
    }

    final one = byTrack.length == 1;
    return _box(
      '대범위',
      count: byTrack.values.fold<int>(0, (n, list) => n + list.length),
      trailing: one
          ? SizedBox(
              height: SheetLook.boxLid + 1,
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: SheetLook.boxLabelTop * 2 + SheetSmallTag.height,
                  child: Center(widthFactor: 1, child: Text('트랙', maxLines: 1, softWrap: false, style: sheetText(SheetLook.boxLabelText, color: SheetLook.ink45))),
                ),
                const SizedBox(width: 6),
                Padding(padding: const EdgeInsets.only(top: SheetLook.boxLabelTop), child: tag(byTrack.keys.first)),
              ]),
            )
          : null,
      SheetRun(children: [
        for (final entry in byTrack.entries) ...[
          if (!one) tag(entry.key),
          for (final s in entry.value) chip(s),
        ],
      ]),
    );
  }

  Widget _box(String label, Widget body, {int? count, Widget? trailing}) => SheetBox(
    label: label,
    count: count == null ? null : '$count',
    trailing: trailing,
    padding: const EdgeInsets.fromLTRB(SheetLook.boxInset, SheetLook.boxInset, SheetLook.boxInset, SheetLook.boxInset + 1),
    child: body,
  );

  Widget _chip(String label, int color, bool on, VoidCallback onTap, {SheetTagKind kind = SheetTagKind.cham}) =>
      SheetTagChip(label: label, color: Color(0xff000000 | color), on: on, kind: kind, hint: _chipHint, onTap: onTap);
}

/// 종류 · 실재성 칩의 색(지금 연표도 이 회색 하나를 쓴다).
const _neutralChip = 0xa4b1b7;

/// 칩의 풍선 — 4단계 전과 같은 글.
const _chipHint = '클릭: 켜기/끄기 · Alt+클릭: 이것만 보기';

/// 트랙 칩 줄과 '모두 접기' 단추 사이(목업 18) · 발의 가로대 위아래(12 — 목업 `rail = boxesEnd + 12 · ctl = rail + 13`) ·
/// 발의 고르는 칸 사이(18) · 발의 고르기 묶음과 도구 단추 사이의 가장 좁은 틈(32).
const _buttonGap = 18.0, _railGap = 12.0, _footGap = 18.0, _toolsGap = 32.0;
