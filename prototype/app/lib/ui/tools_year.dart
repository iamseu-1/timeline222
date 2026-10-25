import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scene/color_mix.dart';
import '../scene/ruler.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import 'app_bus.dart';
import '../scene/aux_calendar.dart' show AuxCalendarStore;
import 'date_text.dart';
import 'shell_keys.dart';
import 'tools_measure.dart';

// 같은 해 보기(명세 06의 7-1). 기준선을 놓은 때에 나라마다 어느 시대였고 무슨 일이 있었는지를 상세 창 자리에 보인다.
// 달 · 날까지 확대했으면 같은 달 · 같은 날이 된다(기준 단위는 확대 정도로 정한다 — [yearUnitFor]).
//
// 혼자 서는 부품이라 [AppBus]만 받는다:
//   `bus.slot('command')`   — 단축키 · 메뉴의 명령([Cmd.year]: `at`이 있으면 그때, 없으면 화면 가운데에서 여닫는다 · [Cmd.close]: 닫는다).
//   `bus.slot('yearPanel')` = [YearRequest] 또는 검색이 싣는 `{t, end, prec, label}`(해 좌표) — 열어 달라는 부탁. null이면 닫힌다.
//   `bus.slot('marker')`    = double(분) — 기준선. 이 창이 열리고 닫힐 때 놓고 거둔다(연표가 그린다).
//   `bus.ask({'op':'same_year', …})`    — 그때의 나라 · 시기 · 인물 · 앞뒤 사건.
//   `bus.select(uid)` · `bus.goTo(lo, hi)` — 목록을 누르면 그 항목의 상세로, `🎯`면 그 해로.

/// `bus.slot(…)`의 이름: 열어 달라는 부탁과 기준선. 이름 `yearPanel`은 검색(`search.dart`)이 이미 쓰는 것에 맞췄다.
const yearSlot = 'yearPanel', markerSlot = 'marker';

/// 기준 단위. 확대 정도로 정하지만, 부탁하는 쪽이 못박을 수도 있다(날짜 검색은 적은 만큼 자세히 연다).
enum YearUnit { year, month, day }

/// 단위마다의 글과 앞뒤 범위 목록(분). 지금 연표의 `PANEL`(js/viewer.js:2014) 그대로다.
extension YearUnitLook on YearUnit {
  String get word => switch (this) {
    YearUnit.year => '해',
    YearUnit.month => '달',
    YearUnit.day => '날',
  };
  String get badge => switch (this) {
    YearUnit.year => '기준 연도',
    YearUnit.month => '기준 달',
    YearUnit.day => '기준 날짜',
  };
  String get unitWord => switch (this) {
    YearUnit.year => '년',
    YearUnit.month => '개월',
    YearUnit.day => '일',
  };

  /// 고를 수 있는 앞뒤 범위(분).
  List<double> get windows => switch (this) {
    YearUnit.year => [0, 5 * minutesPerYear, 10 * minutesPerYear, 25 * minutesPerYear, 50 * minutesPerYear, 100 * minutesPerYear],
    YearUnit.month => [0, minutesPerMonth, 3 * minutesPerMonth, 6 * minutesPerMonth, minutesPerYear, 5 * minutesPerYear],
    YearUnit.day => [0, 3 * minutesPerDay, 7 * minutesPerDay, minutesPerMonth, 3 * minutesPerMonth, minutesPerYear],
  };

  /// 처음 값: ±10년 · ±1개월 · ±7일.
  double get defaultWindow => switch (this) {
    YearUnit.year => 10 * minutesPerYear,
    YearUnit.month => minutesPerMonth,
    YearUnit.day => 7 * minutesPerDay,
  };

  /// 그 단위로 적은 한 시점의 글.
  DatePrec get prec => switch (this) {
    YearUnit.year => DatePrec.year,
    YearUnit.month => DatePrec.month,
    YearUnit.day => DatePrec.day,
  };
}

/// 확대 정도에 맞는 기준 단위: 보기 폭이 두 달보다 좁으면 날, 2년보다 좁으면 달, 아니면 해(js/viewer.js:255 `panelPrec`).
YearUnit yearUnitFor(double viewSpan) {
  if (viewSpan < 2 * minutesPerMonth) return YearUnit.day;
  if (viewSpan < 2 * minutesPerYear) return YearUnit.month;
  return YearUnit.year;
}

/// [minute]이 든 해 · 달 · 날의 첫 순간(분). 달력은 `date_text.dart`의 것(1582년 앞은 율리우스력)을 쓴다.
double snapTo(double minute, YearUnit unit) {
  final at = civilAt(tOfMinutes(minute));
  return minutesOfT(switch (unit) {
    YearUnit.year => at.year.toDouble(), // 해 좌표의 정수 N = N년 1월 1일
    YearUnit.month => tOfJdn(jdnOf(at.year, at.month, 1)),
    YearUnit.day => tOfJdn(at.jdn),
  });
}

/// [atMinute]이 든 해 · 달 · 날의 다음 첫 순간(분) — 창이 보는 구간은 `[at, end)`다.
double unitEndMinute(double atMinute, YearUnit unit) => minutesOfT(unitEnd(tOfMinutes(atMinute), unit.prec));

/// 앞뒤 범위의 글: `±0년` · `±3개월` · `±7일`(js/viewer.js:2019 `windowText`).
String windowText(double window, YearUnit unit) {
  if (window <= 0) return '±0${unit.unitWord}';
  if (window >= minutesPerYear - 1) return '±${(window / minutesPerYear).round()}년';
  if (window >= minutesPerMonth - 1) return '±${(window / minutesPerMonth).round()}개월';
  return '±${(window / minutesPerDay).round()}일';
}

/// 열어 달라는 부탁. [unit]을 비우면 확대 정도로 정하고, [end]를 주면 `[at, end)`를 그대로 쓴다(검색한 음력 달처럼 서력과 어긋나는 구간).
@immutable
class YearRequest {
  const YearRequest(this.at, {this.unit, this.end, this.label});

  /// 기준이 되는 때(분). [end]가 없으면 그 해 · 달 · 날의 첫 순간으로 맞춘다.
  final double at;
  final YearUnit? unit;
  final double? end;

  /// 제목으로 쓸 글(검색에서 왔을 때). 없으면 [at]을 단위만큼 적는다.
  final String? label;

  /// 슬롯에 실린 값을 부탁으로 읽는다. `{t, end, prec, label}` 꼴로 싣는 쪽이 `minutes: true`를 함께 적었으면
  /// 그 둘을 계약 0절의 **분**으로, 적지 않았으면 **해 좌표**로 읽어 분으로 옮긴다.
  static YearRequest? of(Object? value) {
    if (value is YearRequest) return value;
    if (value is! Map) return null;
    final t = value['t'], end = value['end'], label = value['label'];
    if (t is! num) return null;
    final inMinutes = value['minutes'] == true;
    double minutes(num one) => inMinutes ? one.toDouble() : minutesOfT(one.toDouble());
    return YearRequest(
      minutes(t),
      unit: switch ('${value['prec'] ?? ''}') {
        'm' => YearUnit.month,
        'd' => YearUnit.day,
        'y' => YearUnit.year,
        _ => null,
      },
      end: end is num ? minutes(end) : null,
      label: label is String && label.isNotEmpty ? label : null,
    );
  }
}

/// 같은 해 보기가 받는 자료(`{"op":"same_year","at":분,"end":분,"window":분}`의 답).
@immutable
class SameYear {
  const SameYear({this.eras = const [], this.phases = const [], this.figures = const [], this.figureCount = 0, this.events = const [], this.count = 0});

  /// 그때 각 나라는 — 트랙마다 걸친 정권.
  final List<YearGroup> eras;

  /// 그때의 시기 구분(학계) — 정권마다 걸친 시기 칸.
  final List<YearGroup> phases;

  /// 그때 활동한 인물 — 트랙마다.
  final List<YearGroup> figures;
  final int figureCount;

  /// 앞뒤 범위 안의 사건(시작 순).
  final List<YearEvent> events;

  /// 그 범위에 든 사건이 모두 몇 건인가(목록이 잘렸을 수 있다).
  final int count;

  static SameYear fromJson(Map<String, dynamic> j) {
    List<YearGroup> groups(String key) => [for (final g in _list(j[key])) YearGroup.fromJson(_map(g))];
    final events = [for (final e in _list(j['events'])) YearEvent.fromJson(_map(e))];
    return SameYear(
      eras: groups('eras'),
      phases: groups('phases'),
      figures: groups('figures'),
      figureCount: _int(j['figureCount'], groups('figures').fold(0, (n, g) => n + g.items.length)),
      events: events,
      count: _int(j['count'], events.length),
    );
  }
}

/// 트랙(또는 트랙 + 정권) 하나에 딸린 줄. `그때 각 나라는` · `시기 구분` · `인물`이 같은 모양을 쓴다.
@immutable
class YearGroup {
  const YearGroup({required this.name, required this.color, this.period = '', this.items = const []});

  /// 트랙 이름과 색(배지).
  final String name;
  final Color color;

  /// 시기 구분 줄에만: 그 시기가 딸린 정권의 이름.
  final String period;
  final List<YearItem> items;

  static YearGroup fromJson(Map<String, dynamic> j) => YearGroup(
    name: _str(j['name']),
    color: _color(j['color']),
    period: _str(j['period']),
    items: [
      for (final key in const ['periods', 'cells', 'figures', 'items'])
        for (final it in _list(j[key])) YearItem.fromJson(_map(it)),
    ],
  );
}

/// 줄 안의 한 항목(정권 · 시기 칸 · 인물).
@immutable
class YearItem {
  const YearItem({required this.uid, required this.name, this.cell, this.sub = '', this.historicity = 0, this.rank});
  final String uid, name;

  /// 칸 참조(`phase:2` · `rank:1`) — 있으면 그 칸의 창을 연다.
  final String? cell;

  /// 이름 뒤의 작은 글(체계 이름 · 인물의 역할).
  final String sub;

  /// 실재성 0 실재 · 1 반전설 · 2 전설 · 3 실재 논쟁 · 4 부정됨 — 전설과 부정됨은 옅은 글씨다.
  final int historicity;

  /// 그때의 지위(정권 줄에만).
  final YearRank? rank;

  static YearItem fromJson(Map<String, dynamic> j) {
    final rank = j['rank'];
    return YearItem(
      uid: _str(j['uid']),
      name: _str(j['name']),
      cell: j['cell'] == null ? null : _str(j['cell']),
      sub: _str(j['scheme']).isNotEmpty ? _str(j['scheme']) : _str(j['role']),
      historicity: _int(j['hs'], 0),
      rank: rank is Map ? YearRank.fromJson(_map(rank)) : null,
    );
  }
}

/// 그때의 지위 알약.
@immutable
class YearRank {
  const YearRank({required this.name, required this.cell, required this.level});
  final String name, cell;

  /// 서열 단계 0~4 — 짙기는 [rankMix]를 나라 색에 섞는다.
  final int level;

  static YearRank fromJson(Map<String, dynamic> j) => YearRank(name: _str(j['name']), cell: _str(j['cell']), level: _int(j['level'], 0).clamp(0, 4));
}

/// 지위 서열 단계마다 나라 색을 섞는 짙기(%). 지금 연표의 `HT.RANK_MIX`.
const rankMix = [0, 8, 22, 38, 56];

/// 사건 목록의 한 줄.
@immutable
class YearEvent {
  const YearEvent({required this.uid, required this.title, this.label = '', this.track = '', this.color = Ui.accent, this.treaty = false});
  final String uid, title, label, track;
  final Color color;

  /// 조약이면 점 대신 마름모.
  final bool treaty;

  static YearEvent fromJson(Map<String, dynamic> j) =>
      YearEvent(uid: _str(j['uid']), title: _str(j['title']), label: _str(j['label']), track: _str(j['track']), color: _color(j['color']), treaty: j['treaty'] == true);
}

List<dynamic> _list(Object? v) => v is List ? v : const [];
Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
String _str(Object? v) => v == null ? '' : '$v';
int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;
Color _color(Object? v) => v is num ? Color(0xff000000 | (v.toInt() & 0xffffff)) : Ui.text2;

/// 같은 해 보기 창. 상세 창과 같은 자리 · 같은 뼈대(폭 380 · 둥근 20 · 유리 바탕)를 쓴다 —
/// 앱 틀이 `Positioned(top: 12, right: 12, bottom: 16)` 자리에 놓고, 닫히면 스스로 아무 자리도 차지하지 않는다.
class YearPanel extends StatefulWidget {
  const YearPanel({super.key, required this.bus});
  final AppBus bus;

  @override
  State<YearPanel> createState() => _YearPanelState();
}

class _YearPanelState extends State<YearPanel> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();
  Animation<double> get _curve => _enter;

  YearUnit _unit = YearUnit.year;
  double _at = 0, _end = 0, _window = 0;
  String? _label;
  SameYear? _data;
  bool _loading = false, _failed = false, _reduceMotion = false;
  int _token = 0;

  AppBus get _bus => widget.bus;
  bool get _open => YearRequest.of(_bus.slot(yearSlot).value) != null;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    _bus.slot(yearSlot).addListener(_onRequest);
    _bus.slot(slotCommand).addListener(_onCommand);
    _bus.selection.addListener(_onSelect);
    if (_open) _onRequest();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 움직임 줄이기면 미끄러지지 않고 바로 자리에.
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && (_enter.isAnimating || _enter.value > 0)) _enter.value = 1;
  }

  @override
  void dispose() {
    _bus.slot(yearSlot).removeListener(_onRequest);
    _bus.slot(slotCommand).removeListener(_onCommand);
    _bus.selection.removeListener(_onSelect);
    _enter.dispose();
    super.dispose();
  }

  /// 항목을 고르면(상세 창이 열리면) 같은 해 보기는 물러난다 — 두 창이 같은 자리를 쓴다(js/viewer.js:1731의 4번).
  void _onSelect() {
    if (_open && _bus.selection.value != null) _close();
  }

  /// 단축키 · 메뉴의 명령. `📍`(`Y`)는 여닫고, 메뉴의 `📍 〈때〉에 무슨 일이`는 그 자리의 때로 연다.
  void _onCommand() {
    final command = _bus.slot(slotCommand).value;
    if (command is! AppCommand) return;
    if (command.name == Cmd.close) {
      if (_open) _close();
      return;
    }
    if (command.name != Cmd.year) return;
    if (command.at == null && _open) return _close();
    final view = _bus.controller.view;
    _bus.slot(yearSlot).value = YearRequest(command.at ?? view.lo + view.span / 2);
    if (command.at == null) _bus.slot(slotNotice).value = '연표의 빈 곳을 클릭하면 그 자리로 기준선이 옮겨집니다.';
  }

  void _onRequest() {
    final req = YearRequest.of(_bus.slot(yearSlot).value);
    if (req == null) {
      _bus.slot(markerSlot).value = null;
      _enter.reverse();
      if (mounted) setState(() {});
      return;
    }
    final unit = req.unit ?? yearUnitFor(_bus.controller.view.span);
    final at = req.end != null ? req.at : snapTo(req.at, unit);
    // 같은 단위로 다시 열면 고른 앞뒤 범위를 그대로 쓴다(지금 연표와 같이).
    final window = _data != null && unit == _unit ? _window : unit.defaultWindow;
    setState(() {
      _unit = unit;
      _at = at;
      _end = req.end ?? unitEndMinute(at, unit);
      _window = window;
      _label = req.label;
      _data = null;
      _failed = false;
    });
    _bus.clearSelection(); // 고르기와 세로 닻을 풀고
    _bus.slot(markerSlot).value = at; // 기준선을 놓는다
    if (_reduceMotion) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
    _load();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() => _loading = true);
    try {
      final answer = await _bus.ask({'op': 'same_year', 'at': _at, 'end': _end, 'window': _window});
      if (!mounted || token != _token) return;
      setState(() {
        _data = SameYear.fromJson(answer);
        _loading = false;
      });
      // 부탁한 쪽이 제 기준선을 함께 실었을 수 있어(검색은 해 좌표로 싣는다) 여기서 분으로 다시 못박는다.
      _bus.slot(markerSlot).value = _at;
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _close() => _bus.slot(yearSlot).value = null;

  void _openItem(String uid, {String? cell}) {
    if (uid.isEmpty) return;
    _bus.select(uid, cell: cell); // 창이 바뀌는 일은 고르기를 듣는 상세 창의 몫이다
  }

  /// `🎯 이 〈해〉로 이동` — 폭은 지금 그대로, 가운데만 이 구간으로(js/viewer.js:250).
  void _goHere() {
    final span = _bus.controller.view.span;
    final center = (_at + _end) / 2;
    _bus.goTo(center - span / 2, center + span / 2);
    _bus.slot(markerSlot).value = _at;
  }

  void _setWindow(double w) {
    setState(() => _window = w);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_open && _enter.isDismissed) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _enter.opacity,
        child: Transform.translate(offset: Offset(Ui.detailSlide * (1 - _curve.value), 0), child: child),
      ),
      child: SizedBox(
        width: Ui.detailWidth,
        // 상세 칸과 같은 자리 · 같은 꼴: paper 바탕 · 왼쪽 1px 선 하나.
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Ui.detailGlass,
            border: Border(left: BorderSide(color: Ui.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _head(),
              Flexible(child: _body()),
              _foot(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head() => SizedBox(
    height: 46,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _Badge(text: _unit.badge, color: _warn),
          ),
          const Spacer(),
          _IconButton(label: '닫기', onTap: _close),
        ],
      ),
    ),
  );

  Widget _foot() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Ui.line)),
    ),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SmallButton(text: '이 ${_unit.word}로', onTap: _goHere),
        _SmallButton(text: '닫기', onTap: _close),
      ],
    ),
  );

  Widget _body() {
    final data = _data;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
            child: Text(
              _label ?? pointText(_at, _unit.prec),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -.575, height: 1.35, color: Ui.text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
            child: Text(_subLine(), style: const TextStyle(fontSize: 12, color: Ui.text3)),
          ),
          if (_failed)
            const Text('자료를 읽지 못했습니다.', style: TextStyle(fontSize: 13, color: Ui.text3))
          else if (data == null)
            Text(_loading ? '읽는 중…' : '', style: const TextStyle(fontSize: 13, color: Ui.text3))
          else ...[
            _when('그때 각 나라는'),
            _groups(data.eras, empty: '이 ${_unit.word}에 걸친 시대 정보가 없습니다.'),
            if (data.phases.isNotEmpty) ...[_when('그때의 시기 구분(학계)'), _groups(data.phases)],
            if (data.figures.isNotEmpty) ...[_when('그때 활동한 인물', sub: '${data.figureCount}명'), _groups(data.figures)],
            _windowRow(data.count),
            _events(data.events),
          ],
        ],
      ),
    );
  }

  /// 제목 아래 곁들임 줄: 해 · 달은 그해의 간지, 날은 음력 · 일진 · 요일이다(음력은 받아 둔 달의 시작 표가 있을 때만).
  String _subLine() {
    if (_unit == YearUnit.day) return dayNote(tOfMinutes(_at), lunar: AuxCalendarStore.shared?.lunar);
    final year = civilAt(tOfMinutes(_at)).year;
    return '${ganjiOf(year < 0 ? year + 1 : year)}년';
  }

  Widget _when(String text, {String? sub}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Ui.text3),
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(sub, style: const TextStyle(fontSize: 12, color: Ui.text3)),
          ),
      ],
    ),
  );

  Widget _groups(List<YearGroup> groups, {String? empty}) {
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(empty ?? '', style: const TextStyle(fontSize: 13, color: Ui.text3)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Badge(text: g.name, color: g.color),
                  if (g.period.isNotEmpty) Text(g.period, style: const TextStyle(fontSize: 13, color: Ui.text2)),
                  for (int i = 0; i < g.items.length; i++) ...[
                    if (i > 0) const Text('·', style: TextStyle(fontSize: 13, color: Ui.text3)),
                    _link(g.items[i], g.color),
                    if (g.items[i].sub.isNotEmpty) Text(g.items[i].sub, style: const TextStyle(fontSize: 11, color: Ui.text3)),
                    if (g.items[i].rank != null)
                      _RankPill(
                        rank: g.items[i].rank!,
                        color: g.color,
                        onTap: () => _openItem(g.items[i].uid, cell: g.items[i].rank!.cell),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _link(YearItem item, Color color) {
    // 전설 · 부정된 나라는 옅은 글씨(기울임 · 취소선) — 명세 7-1.
    final faded = item.historicity == 2 || item.historicity == 4;
    return Linky(
      text: item.name,
      size: 13,
      color: faded ? Ui.ink60 : Ui.accent,
      italic: item.historicity == 2,
      strike: item.historicity == 4,
      onTap: () => _openItem(item.uid, cell: item.cell),
    );
  }

  Widget _windowRow(int count) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Ui.line)),
    ),
    child: Row(
      children: [
        const Text('앞뒤 ', style: TextStyle(fontSize: 13, color: Ui.text2)),
        _WindowPicker(unit: _unit, window: _window, onPick: _setWindow),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: ' 안의 사건 '),
                TextSpan(
                  text: '$count',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Ui.text),
                ),
                const TextSpan(text: '건'),
              ],
            ),
            style: const TextStyle(fontSize: 13, color: Ui.text2),
          ),
        ),
      ],
    ),
  );

  Widget _events(List<YearEvent> events) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('가까운 사건이 없습니다.', style: TextStyle(fontSize: 13, color: Ui.text3)),
      );
    }
    // `--yw` 맞춤: 창 안 모든 날짜 칸의 최대 폭을 한 번 재어 공통 폭으로(단추 폭의 45%까지).
    final widest = _widestLabel(events);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final e in events) _EventRow(event: e, dateWidth: widest, onTap: () => _openItem(e.uid))],
    );
  }

  double _widestLabel(List<YearEvent> events) {
    double widest = 0;
    for (final e in events) {
      if (e.label.isEmpty) continue;
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(text: e.label, style: const TextStyle(fontSize: 12)),
      )..layout();
      widest = math.max(widest, painter.width);
    }
    // 창 속 폭(380 − 좌우 18 − 줄 좌우 8)의 45%를 넘지 않게.
    return math.min(widest, (Ui.detailWidth - 36 - 16) * .45);
  }
}

/// 상세 창 배지(css의 `.badge`): 제 색 26% 바탕 · 앞에 7px 색 점.
class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: .26), borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Ui.text, height: 1.4),
        ),
      ],
    ),
  );
}

/// 그때의 지위 알약(css의 `.yr-rank`): 나라 색을 서열만큼 섞은 바탕 · 1px 테두리.
class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank, required this.color, required this.onTap});
  final YearRank rank;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Color(mixSrgb(color.toARGB32(), Ui.surface.toARGB32(), rankMix[rank.level] / 100)),
          border: Border.all(color: color.withValues(alpha: .45)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(rank.name, style: const TextStyle(fontSize: 11, color: Ui.text2, height: 1.5)),
      ),
    ),
  );
}

/// 사건 목록의 한 줄(css의 `.year-events button`): `[색 점][날짜][제목][트랙]`.
class _EventRow extends StatefulWidget {
  const _EventRow({required this.event, required this.dateWidth, required this.onTap});
  final YearEvent event;
  final double dateWidth;
  final VoidCallback onTap;

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: _hover ? Ui.accentSoft : null, borderRadius: BorderRadius.circular(7)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _EventDot(color: e.color, treaty: e.treaty),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: widget.dateWidth,
                child: Text(
                  e.label,
                  style: const TextStyle(fontSize: 12, color: Ui.text3, height: 1.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.title, style: const TextStyle(fontSize: 14, color: Ui.text, height: 1.4)),
              ),
              if (e.track.isNotEmpty) ...[const SizedBox(width: 8), Text(e.track, style: const TextStyle(fontSize: 12, color: Ui.text3, height: 1.5))],
            ],
          ),
        ),
      ),
    );
  }
}

/// 사건의 색 점(9px). 조약은 45° 돌린 마름모다.
class _EventDot extends StatelessWidget {
  const _EventDot({required this.color, required this.treaty});
  final Color color;
  final bool treaty;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: treaty ? 7 : 9,
      height: treaty ? 7 : 9,
      decoration: BoxDecoration(color: color, shape: treaty ? BoxShape.rectangle : BoxShape.circle),
    );
    return SizedBox(
      width: 9,
      height: 9,
      child: Center(
        child: treaty ? Transform.rotate(angle: math.pi / 4, child: dot) : dot,
      ),
    );
  }
}

/// 앞뒤 범위 고르기(css의 `.year-window select`).
class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.unit, required this.window, required this.onPick});
  final YearUnit unit;
  final double window;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    final windows = unit.windows;
    int index = windows.indexWhere((w) => (w - window).abs() < 1);
    if (index < 0) index = windows.indexOf(unit.defaultWindow);
    return SizedBox(
      height: 28,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: index < 0 ? 0 : index,
          isDense: true,
          focusColor: const Color(0x00000000),
          style: const TextStyle(fontSize: 13, color: Ui.text2),
          dropdownColor: Ui.surface,
          items: [
            for (int i = 0; i < windows.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(windowText(windows[i], unit), style: const TextStyle(fontSize: 13, color: Ui.text2)),
              ),
          ],
          onChanged: (i) => onPick(windows[i ?? 0]),
        ),
      ),
    );
  }
}

/// 상세 창 바닥의 작은 단추(css의 `.btn.btn-sm`): 높이 28 · 둥근 8 · `surface-2` 바탕.
class _SmallButton extends StatefulWidget {
  const _SmallButton({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Semantics(
        button: true,
        label: widget.text,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _hover ? Ui.surface : Ui.surface2, borderRadius: BorderRadius.circular(8)),
          child: Text(
            widget.text,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Ui.text2, height: 1.4),
          ),
        ),
      ),
    ),
  );
}

/// 창 머리의 아이콘 단추(32×32의 `✕`).
class _IconButton extends StatelessWidget {
  const _IconButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Text('✕', style: TextStyle(fontSize: 14, color: Ui.text2)),
          ),
        ),
      ),
    ),
  );
}

/// 기준 단위 배지의 색(css의 `--warn` — 앱 틀의 [Ui.warn]).
const _warn = Ui.warn;
