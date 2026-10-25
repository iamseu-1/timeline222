import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../motion_spring.dart';
import '../scene/layout.dart';
import '../scene/aux_calendar.dart';
import '../shell/look.dart';
import '../shell/motion_controls.dart';
import 'app_bus.dart';
import 'filter_state.dart';
import 'names_display.dart';
import 'shell_keys.dart';

// 필터 시트의 속 — 앱 틀의 FilterSheet(child: …) 안에 들어간다(명세 06-상세-검색-필터-도구.md 6절).
// 치수 · 색 · 글꼴은 지금 연표의 css(.filterbar · .filter-group · .chip · .check · .btn-sm)와 실측 덤프(results/dom-r6/ui-dump.json)에서 옮겼다.
//
// 이 부품이 바깥과 주고받는 것은 AppBus뿐이다:
//  - 상태: bus.slot('filters')에 [FilterState]를 싣는다(다른 부품도 읽고 쓸 수 있다 — 상세 창의 '같은 시기를 타국에도' 스위치).
//  - 보기 조건: 띠 안의 단 켬/끔과 밀도는 bus.conditions에도 옮긴다(앱 틀이 듣고 줄을 다시 쌓는다).
//  - 모두 접기/펴기: bus.slot('foldAll')에 바라는 상태(참 = 모두 접힘)를 적는다. 지금 접혔는지도 같은 자리에서 읽는다.
//  - 칩의 목록: 트랙 · 분류는 bus.scene.layout에서, 종류 · 실재성 · 쓰인 분류는 {op:'legend_kinds'}, 대범위는 {op:'scopes'}에서.

/// `{"op":"legend_kinds"}` · `{"op":"scopes"}`의 답을 읽어 둔 것. 명령이 아직 없으면 빈 값이고, 그러면 그 칩 줄은 나오지 않는다.
@immutable
class _ChipSource {
  const _ChipSource({this.kinds = const [], this.historicity = const [], this.categories, this.scopes = const []});

  /// 지금 자료에 쓰인 정권 종류 · 실재성(둘 다 `{id, name}`).
  final List<FilterOption<String>> kinds, historicity;

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

class FilterSheetBody extends StatefulWidget {
  const FilterSheetBody({super.key, required this.bus, this.tools});

  final AppBus bus;

  /// 시트 맨 아래 도구 단추 줄(📍 같은 해 보기 · 📏 기간 재기 · 📋 표 보기 · 📷 이미지·인쇄 · ❔ 범례).
  /// 그것은 명세 7절(단위 L)의 몫이라 여기서는 자리만 내어 준다 — 없으면 줄도 없다.
  final Widget? tools;

  @override
  State<FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<FilterSheetBody> {
  _ChipSource _source = const _ChipSource();
  int _askedVersion = -1;

  ValueNotifier<Object?> get _slot => widget.bus.slot('filters');
  ValueNotifier<Object?> get _foldSlot => widget.bus.slot('foldAll');

  FilterState get _state => _slot.value is FilterState ? _slot.value! as FilterState : const FilterState();

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
    // 기억해 둔 값이 이미 실려 있으면 그것이 첫 값이다. 어느 쪽이든 연표의 보기 조건을 한 번 맞춰 둔다.
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

  /// 칩 누르기. Alt를 누른 채면 '이것만 보기'.
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
      final now = slot.value is FilterState ? slot.value! as FilterState : const FilterState();
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

    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 14, height: 1.5, color: Ui.text),
      child: Wrap(
        spacing: 22,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 트랙: 자료를 거른다(그 트랙의 정권 · 사건 · 인물 · 시대 구분 · 대범위가 함께 빠진다).
          _group('트랙', [
            _chips([
              for (final t in tracks)
                _chip(t.name, t.color, state.chipOn(ChipGroup.tracks, '${t.id}'), () => _tapChip(ChipGroup.tracks, '${t.id}', trackIds)),
            ]),
            _SmallButton(
              label: allFolded ? '▸ 모두 펴기' : '▾ 모두 접기',
              hint: '모든 트랙을 접거나 펼칩니다',
              onPressed: tracks.isEmpty ? null : () => runCommand(widget.bus, Cmd.foldAll),
            ),
          ]),
          // 분류: 사건만 거른다. 쓰인 분류만 보인다.
          _group('분류', [
            _chips([
              for (final c in categories)
                _chip(c.name, c.color, state.chipOn(ChipGroup.categories, '${c.id}'), () => _tapChip(ChipGroup.categories, '${c.id}', categoryIds)),
            ]),
          ]),
          // 종류 · 실재성: 정권과 그 정권에 달린 사건을 거른다. 종류는 둘 이상일 때만, 실재성은 자료에 쓰였을 때만 나온다.
          if (_source.kinds.length >= 2)
            _group('종류', [
              _chips([
                for (final k in _source.kinds) _chip(k.name, _neutralChip, state.chipOn(ChipGroup.kinds, k.value), () => _tapChip(ChipGroup.kinds, k.value, kindIds)),
              ]),
            ]),
          if (_source.historicity.isNotEmpty)
            _group('실재성', [
              _chips([
                for (final h in _source.historicity)
                  _chip(h.name, _neutralChip, state.chipOn(ChipGroup.historicity, h.value), () => _tapChip(ChipGroup.historicity, h.value, historicityIds)),
              ]),
            ]),
          if (_source.scopes.isNotEmpty) _group('대범위', [_scopeChips(state, tracks)]),
          // 표시 체크 세 묶음: 시트의 한 줄을 통째로 쓴다.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _showGroup('띠 안', _bandChecks(state)),
                _showGroup('날짜 칸', [for (final t in axisTogglesFor(widget.bus.slot('yearCycle').value as YearCycle?)) _check(t, state)]),
                _showGroup('선·견해', [for (final t in lineToggles) _check(t, state)]),
                if (NamesInfo.of(widget.bus).visible(layout.enabledPacks)) _showGroup('표기', _namesChecks(layout)),
              ],
            ),
          ),
          // 목록 상자와 도구 줄.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MotionSteps(
                  value: state.minImportance,
                  labels: [for (final option in importanceOptions) option.name],
                  onChanged: (v) => _set(state.copyWith(minImportance: v)),
                ),
                _Select<String>(
                  value: [for (final o in _lensOptions(tracks)) o.value].contains(state.lens) ? state.lens : '',
                  options: _lensOptions(tracks),
                  title: '관점',
                  semantics: '관점',
                  hint: '같은 사건을 어느 나라의 이름으로 보여 줄지 고릅니다',
                  onChanged: (v) => _set(state.copyWith(lens: v)),
                ),
                _Select<int>(
                  value: state.density,
                  options: densityOptions,
                  semantics: '띠 밀도',
                  hint: '정권 띠의 높이와 글자 크기 — 조감은 줄을 띠 하나 높이로 줄여 모든 나라를 한눈에 (V)',
                  onChanged: (v) => _set(state.withDensity(v)),
                ),
                _Select<String>(
                  value: state.birdShape,
                  options: birdShapeOptions,
                  title: '조감',
                  semantics: '조감 모양',
                  hint: '조감에서 띠 안에 남길 것',
                  onChanged: (v) => _set(state.copyWith(birdShape: v)),
                ),
                _Check(
                  label: '축소하면 조감',
                  hint: '가로로 많이 축소하면 저절로 조감으로, 다시 확대하면 고른 밀도로 돌아옵니다',
                  value: state.birdAuto,
                  onChanged: (on) => _set(state.copyWith(birdAuto: on)),
                ),
                if (widget.tools != null) ...[const _ToolSeparator(), widget.tools!],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 띠 안 묶음 — 지도자 다음에 표기 목록과 '대수'가 끼어든다(지금 연표의 차례 그대로).
  List<Widget> _bandChecks(FilterState state) => [
    for (final t in bandToggles) ...[
      _check(t, state),
      if (t.key == 'leaders') ...[
        _Select<String>(
          value: state.leaderLabel,
          options: leaderLabelOptions,
          title: '지도자',
          semantics: '지도자 표기',
          hint: '지도자 칸에 묘호·시호·이름 중 무엇을 적을지',
          onChanged: (v) => _set(state.copyWith(leaderLabel: v)),
        ),
        _Check(
          label: '대수',
          hint: "지도자 이름 앞에 '4대'처럼 대수를 붙입니다",
          value: state.leaderOrdinal,
          onChanged: (on) => _set(state.copyWith(leaderOrdinal: on)),
        ),
      ],
    ],
  ];

  /// '표기' 무리(10건 3 · 9 — 감독 결정 D2-3 A · 5 A, 웹 viewer.js의 #namesGroup과 같은 차례 · 같은 글):
  /// [원어: 상세 창만 ▾] · 적용 ☑나라 ☑인물 ☑지명 · [글꼴 ▾](켜진 DLC에 글꼴이 있을 때만). 무리는 켜진 자료집에 이름 목록이나
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
      _Select<String>(
        value: ui.orig,
        options: [for (final o in NamesUi.origOptions) FilterOption(o.$1, '원어: ${o.$2}')],
        semantics: '원어 함께 적기',
        segmented: false,
        hint: '원어(제 말 · 제 글자로 적은 이름)를 어디까지 함께 적을지 — 상세 창의 이름 아래 · 연표 맨 왼쪽 줄 이름 칸',
        onChanged: (v) => set(ui.copyWith(orig: v)),
      ),
      const Tooltip(
        message: '원어 고르기를 어느 이름에 쓸지',
        child: Padding(padding: EdgeInsets.only(left: 2), child: Text('적용', style: TextStyle(fontSize: 12, height: 1.5, color: Ui.text3))),
      ),
      _Check(label: '나라', hint: '나라 · 왕조 · 가문 · 성씨 · 연호 · 내각 · 단체 · 제도의 이름에', value: ui.polity, onChanged: (on) => set(ui.copyWith(polity: on))),
      _Check(label: '인물', hint: '지도자 · 인물의 이름에', value: ui.person, onChanged: (on) => set(ui.copyWith(person: on))),
      _Check(label: '지명', hint: '도읍 · 지명에', value: ui.place, onChanged: (on) => set(ui.copyWith(place: on))),
      if (fonts.isNotEmpty)
        _Select<String>(
          value: fonts.any((f) => f.uid == ui.screen && f.hangul) ? ui.screen! : '',
          options: [
            const FilterOption('', '글꼴: 기본'),
            for (final f in fonts) FilterOption(f.uid, f.hangul ? '글꼴: ${f.family}' : '글꼴: ${f.family} (없는 글자에만)'),
          ],
          disabled: {for (final f in fonts) if (!f.hangul) f.uid},
          tips: {for (final f in fonts) f.uid: fontTip(f)},
          semantics: '화면 글꼴',
          segmented: false,
          hint: '화면 글꼴 — 한글을 덮는 글꼴 팩을 고르면 앱을 다시 켤 때부터 화면 전체가 그 글꼴로. 화면 글꼴에 없는 글자는 켜진 글꼴 팩이 저절로 채웁니다',
          onChanged: (v) => set(v.isEmpty ? ui.copyWith(noScreen: true) : ui.copyWith(screen: v)),
        ),
    ];
  }

  Widget _check(ShowToggle toggle, FilterState state) =>
      _Check(label: toggle.label, hint: toggle.hint, value: state.showing(toggle.key), onChanged: (on) => _set(state.withShowing(toggle.key, on)));

  List<FilterOption<String>> _lensOptions(List<TrackInfo> tracks) => [
    const FilterOption('', '기본'),
    const FilterOption('local', '나라마다 제 이름'),
    for (final t in tracks) FilterOption('${t.id}', t.name),
  ];

  /// 대범위 칩은 트랙마다 작은 이름표를 앞세워 묶는다.
  Widget _scopeChips(FilterState state, List<TrackInfo> tracks) {
    final byTrack = <int, List<_ScopeChip>>{};
    for (final s in _source.scopes) {
      if (!state.chipOn(ChipGroup.tracks, '${s.track}')) continue; // 끈 트랙의 대범위는 보이지 않는다
      byTrack.putIfAbsent(s.track, () => []).add(s);
    }
    TrackInfo? trackOf(int id) {
      for (final t in tracks) {
        if (t.id == id) return t;
      }
      return null;
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in byTrack.entries) ...[
          _TrackTag(name: trackOf(entry.key)?.name ?? '', color: trackOf(entry.key)?.color ?? _neutralChip),
          for (final s in entry.value)
            _FilterChip(
              label: s.name,
              color: s.color,
              on: state.scopeOn(s.uid, fallback: s.byDefault),
              hint: '${s.name}${s.label.isEmpty ? '' : ' · ${s.label}'} — 누르면 모아 보기 ${state.scopeOn(s.uid, fallback: s.byDefault) ? '끄기' : '켜기'} (구성 정권 ${s.members}곳)',
              onTap: () => _tapScope(s),
            ),
        ],
      ],
    );
  }

  Widget _group(String title, List<Widget> children) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [_GroupTitle(title), ...children],
  );

  Widget _chips(List<Widget> chips) => Wrap(spacing: 6, runSpacing: 6, children: chips);

  Widget _chip(String label, int color, bool on, VoidCallback onTap) =>
      _FilterChip(label: label, color: color, on: on, hint: '클릭: 켜기/끄기 · Alt+클릭: 이것만 보기', onTap: onTap);

  /// 묶음 하나: 가는 테두리의 둥근 칸 안에 작은 제목과 체크들.
  Widget _showGroup(String title, List<Widget> checks) => Container(
    constraints: const BoxConstraints(minHeight: 34),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    // 테두리는 칠 위에 얹어 그린다 — 안쪽 여백이 1px 밀리지 않게(css의 inset box-shadow와 같게).
    foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.line)),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [_GroupTitle(title), ...checks],
    ),
  );
}

/// 종류 · 실재성 칩의 점 색(지금 연표도 이 회색 하나를 쓴다).
const _neutralChip = 0xa4b1b7;

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: Ui.text3, letterSpacing: -.12));
}

/// 칩 하나: 자료의 색 점을 보존하고 반전 채움은 안에서 자란다.
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.color, required this.on, required this.onTap, this.hint});
  final String label;
  final int color;
  final bool on;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) => MotionChip(label: label, color: Color(0xff000000 | color), value: on, onTap: onTap, hint: hint);
}

/// 대범위 칩 줄 앞의 트랙 이름표: 3×12 세로 막대 + 작은 이름.
class _TrackTag extends StatelessWidget {
  const _TrackTag({required this.name, required this.color});
  final String name;
  final int color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 4),
        Container(width: 3, height: 12, decoration: BoxDecoration(color: Color(0xff000000 | color), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(name, style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3)),
        const SizedBox(width: 2),
      ],
    ),
  );
}

/// 켬끔 한 칸: 화면 전체의 공통 토글과 같은 모양/값을 쓴다.
class _Check extends StatelessWidget {
  const _Check({required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => MotionToggle(label: label, value: value, onChanged: onChanged, hint: hint);
}

/// 하나 고르기: 반전 표시가 미끄러지는 세그먼트.
class _Select<T> extends StatelessWidget {
  const _Select({required this.value, required this.options, required this.onChanged, required this.semantics, this.hint, this.title, this.disabled = const {}, this.tips = const {}, this.segmented = true});
  final T value;
  final List<FilterOption<T>> options;
  final ValueChanged<T> onChanged;
  final String semantics;
  final String? hint;

  /// 고르는 칸 앞에 한 번 적는 이름(관점 · 지도자 · 조감) — 칸마다 `관점: …`처럼 되풀이하지 않는다(건의 8의 3번).
  final String? title;

  /// 원어·글꼴 메뉴는 드롭다운의 선택 불가 항목과 항목별 라이선스 풍선을 유지한다.
  final bool segmented;

  /// 고를 수 없는(흐린) 줄의 값 — 웹 `<option disabled>`.
  final Set<T> disabled;

  /// 펼친 목록의 줄마다 올렸을 때의 풍선(값 → 글) — 웹 `<option title>`. 닫힌 상자에는 [hint]만(풍선이 겹치지 않게 고른 줄은 글만 그린다).
  final Map<T, String> tips;

  @override
  Widget build(BuildContext context) {
    if (segmented) {
      final control = MotionSegmented<T>(
        value: value,
        options: [for (final option in options) MotionChoice(option.value, option.name)],
        onChanged: onChanged,
        label: semantics,
        hint: hint,
      );
      if (title == null) return control;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title!, style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text2)),
          const SizedBox(width: 8),
          Flexible(child: control),
        ],
      );
    }
    Widget body = Container(
      height: 30,
      padding: const EdgeInsets.only(left: 11, right: 6),
      decoration: BoxDecoration(
        color: Ui.paper,
        borderRadius: BorderRadius.circular(Ui.controlRadius),
        border: Border.all(color: Ui.ink20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(Ui.controlRadius),
          focusColor: const Color(0x00000000),
          style: const TextStyle(fontFamily: Ui.serif, fontFamilyFallback: Ui.serifFallback, fontSize: 14, height: 1.5, color: Ui.text),
          icon: const Icon(Icons.expand_more, size: 16, color: Ui.text3),
          dropdownColor: Ui.surface,
          items: [
            for (final o in options)
              DropdownMenuItem<T>(
                value: o.value,
                enabled: !disabled.contains(o.value),
                child: tips[o.value] == null
                    ? Text(o.name, style: disabled.contains(o.value) ? const TextStyle(color: Ui.text3) : null)
                    : Tooltip(message: tips[o.value]!, child: Text(o.name, style: disabled.contains(o.value) ? const TextStyle(color: Ui.text3) : null)),
              ),
          ],
          selectedItemBuilder: tips.isEmpty ? null : (context) => [for (final o in options) Text(o.name)],
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
        ),
      ),
    );
    if (hint != null) body = Tooltip(message: hint!, child: body);
    return Semantics(label: semantics, child: body);
  }
}

/// 작은 단추(css의 .btn.btn-sm). 앱 틀의 ShellButton은 독의 단추(높이 32 · 바탕 없음)라 여기서는 쓰지 않는다.
class _SmallButton extends StatefulWidget {
  const _SmallButton({required this.label, required this.onPressed, this.hint});
  final String label;
  final VoidCallback? onPressed;
  final String? hint;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final off = widget.onPressed == null;
    Widget body = Opacity(
      opacity: off ? .45 : 1,
      child: AnimatedContainer(
        duration: Duration(milliseconds: Motion.micro.round()),
        curve: Ui.ease,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _hover && !off ? Ui.ink8 : null,
          borderRadius: BorderRadius.circular(Ui.controlRadius),
        ),
        foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.ink20)),
        // 폭은 제 글만큼만 — 테두리형이라 한 줄을 다 차지하면 긴 막대로 보인다.
        child: Center(widthFactor: 1, child: Text(widget.label, style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text))),
      ),
    );
    if (widget.hint != null) body = Tooltip(message: widget.hint!, child: body);
    return MouseRegion(
      cursor: off ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        enabled: !off,
        label: widget.label,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPressed, child: body),
      ),
    );
  }
}

/// 목록 상자와 도구 단추 사이의 가는 세로 선.
class _ToolSeparator extends StatelessWidget {
  const _ToolSeparator();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 20, child: ColoredBox(color: Ui.line));
}
