import 'dart:async';

import 'package:flutter/material.dart';

import '../motion.dart';
import '../motion_spring.dart';
import '../scene/layout.dart';
import '../shell/look.dart';
import 'app_bus.dart';
import 'date_text.dart';
import 'detail_shell.dart';
import 'filter_state.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  같은 시기 타국(메아리) — 창의 스위치와 나라별 묶음
//  — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 3-4절 · 지금 연표의 `spotHighlight` ·
//    `echoBoxHTML` · `fillEchoSlot`(js/viewer.js:2114~2204).
//
//  창과 연표가 **같은 답 하나**를 쓴다: 이 부품이 조회 명령 `echo`를 한 번 불러 목록을 그리고,
//  그 답에서 연표가 쓸 것(제 조명에 든 사건 `ownUids` · 메아리 사건 번호 `echoIds`)만 골라
//  `bus.slot('echoHits')`에 싣는다. 앱 틀(`app_glue.dart`)이 그것을 밝기(`Look`)로 옮겨 담는다.
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    EchoSlot(
//      bus: bus,
//      spots: [{'uid': 정권uid, 'start': 분, 'end': 분}],   // 이 창이 연표에 켠 기간 조명
//      always: true,            // 칸 · 시기 · 지위 창은 참(강조를 늘 검) · 왕조 · 인물 창은 거짓
//      between: [ …이 시기의 사건… ],   // 스위치와 묶음 사이에 드는 것(지금 연표의 차례 그대로)
//      color: 그 항목의 색,
//      onOpen: (uid) => …,      // 줄을 누르면 — 주지 않으면 `bus.select(uid)`
//    )
//
//  ── 스위치 ────────────────────────────────────────────────────────────────────────────────
//    필터 시트의 '선·견해' 묶음에 있는 같은 체크(`show.spotEcho`)와 **한 설정**이다 — 어느 쪽을 눌러도
//    둘이 함께 바뀌고, 기억도 필터의 것 하나뿐이다(기본 끔). 값은 `bus.slot('echo')`에도 실어
//    앱 틀이 곧바로 읽게 한다.
//
//  ── 자료 처리부에 묻는 것(없으면 이 자리만 빈다) ───────────────────────────────────────────
//    {"op":"echo","spots":[{"uid":…,"start":분,"end":분}],"limit":400}
//      → {"spans","own":[…],"ownUids":[…],"echo":[…],"echoIds":[사건 번호…],
//         "groups":[{"track","track_name","band","uid","name","color","folded","count","row"?,
//                    "events":[{"id","uid","title","when","start","end","color","treaty","shared","importance","kids","with"?,"member"}]}],
//         "count","total"}
//    답의 `folded`는 **늘 거짓이다** — 접힌 트랙 · 접힌 줄은 보기 상태라 엔진이 모른다(계약 2-5의 ②).
//    `접힘` 딱지는 이 부품이 `bus.scene.layout`을 보고 붙인다([EchoGroup.foldedIn]) — 묶음의 `row`가 오면 그 줄로,
//    아직 오지 않으면 트랙만 본다.
//    스위치를 켜고 끌 때는 다시 묻지 않는다 — 한 답에 제 것(`ownUids`)과 메아리가 함께 들어 있다.
//    거르개(`filter`)와 변형(`variants`)은 앱 틀이 실어 보낸다(`archive_app.dart`의 `_filtered`).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 창 안의 체크 글(필터 시트의 같은 체크와 한 설정).
const echoSwitchLabel = '같은 시기를 타국에도';

/// 스위치의 값(bool)이 실리는 자리.
const echoSlot = 'echo';

/// 셈해 둔 메아리에서 연표가 쓸 것이 실리는 자리([EchoHits] · 없으면 null).
const echoHitsSlot = 'echoHits';

/// 필터 시트의 값이 실리는 자리(`app_glue.dart`의 `slotFilters`와 같은 이름 — 이 파일은 그 파일을 들이지 않는다).
const _filterSlot = 'filters';

/// 모두 이만큼이 넘으면 나라마다 중요한 [echoEach]건만 · 묶음이 [echoGroupMax]곳을 넘으면 나머지는 접어 둔다.
const echoMax = 40, echoEach = 5, echoGroupMax = 8;

/// 한 번에 받아 오는 줄 수.
const echoLimit = 400;

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 답 읽기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 메아리에서 **연표가 쓰는 것**만: 제 조명에 든 사건(항목 기록의 열쇠)과 메아리 사건의 번호.
@immutable
class EchoHits {
  const EchoHits({this.ownUids = const [], this.echoIds = const []});
  final List<String> ownUids;
  final List<int> echoIds;

  bool get isEmpty => ownUids.isEmpty && echoIds.isEmpty;
}

/// 묶음 한 줄의 사건.
@immutable
class EchoEvent {
  const EchoEvent({
    required this.uid,
    required this.title,
    this.when = '',
    this.color,
    this.treaty = false,
    this.shared = false,
    this.importance = 2,
    this.kids = 0,
    this.alsoIn = const [],
    this.member = '',
  });

  final String uid, title, when;
  final Color? color;

  /// 조약이면 마름모, 여러 자리에 놓인 공동 사건이면 속 빈 점.
  final bool treaty, shared;

  /// 중요도(모두 [echoMax]건이 넘을 때 나라마다 몇 건만 남기는 잣대).
  final int importance;

  /// 부모 줄로 모인 하위 사건의 수(`포함 n`).
  final int kids;

  /// 함께 겪은 다른 자리의 이름(`함께 · 〈다른 나라〉`) — 자료 처리부가 실어 줄 때만.
  final List<String> alsoIn;

  /// 상국 띠 아래에 접혀 숨은 소속의 이름 — 계약 2-5의 `member`.
  /// **메아리 목록은 이 값을 그리지 않는다**: 지금 연표도 메아리 목록에는 `소속 · 〈나라〉`를 적지 않고,
  /// 그 글은 칸 상세의 '이 시기의 사건'(`events_in` · `ui/detail_cell.dart`)에만 있다.
  /// 엔진도 마찬가지로 묶음의 줄에는 이 자리를 늘 빈 글로 둔다(`query.rs`의 `echo_groups`) —
  /// 열쇠가 오는지만 확인하려고 읽어 둔다.
  final String member;

  factory EchoEvent.read(Map<String, dynamic> row) => EchoEvent(
    uid: detailString(row, 'uid'),
    title: detailString(row, 'title'),
    when: echoWhen(row),
    color: row['color'] == null || row['color'] == 0 ? null : detailColor(row['color']),
    treaty: row['treaty'] == true || row['treaty'] == 1,
    shared: row['shared'] == true || row['shared'] == 1,
    importance: (detailNum(row, 'importance') ?? 2).toInt(),
    kids: (detailNum(row, 'kids') ?? 0).toInt(),
    alsoIn: detailStrings(row, 'with'),
    member: detailString(row, 'member'),
  );
}

/// 나라별 묶음 하나.
@immutable
class EchoGroup {
  const EchoGroup({
    required this.uid,
    required this.name,
    this.track = '',
    this.trackId = -1,
    this.row = -1,
    this.color,
    this.folded = false,
    required this.count,
    this.events = const [],
  });

  /// 그 나라(정권)의 열쇠 — 정권이 없는 사건의 묶음(트랙)이면 빈 글.
  final String uid;
  final String name, track;
  final Color? color;

  /// 그 띠가 놓인 트랙의 번호와 줄 번호(답에 없으면 −1).
  final int trackId, row;

  /// 답이 스스로 접혔다고 적었는가. **엔진은 보기 상태를 몰라 늘 거짓이다**(계약 2-5의 ②) —
  /// 딱지는 [foldedIn]으로 창이 붙인다.
  final bool folded;

  /// 그 나라의 줄 수(추려 그리기 전의 수).
  final int count;
  final List<EchoEvent> events;

  /// 머리의 옅은 글 — 정권이면 트랙 이름, 정권이 없는 사건의 묶음이면 그렇다고 적는다.
  String get sub => uid.isEmpty ? '정권 없는 사건' : track;

  /// 연표에서 그 줄이 접혀 있는가 — 접힌 트랙 · 접힌 민족 묶음(합쳐진 줄과 그 안에 든 줄) · 빈 줄 접기.
  /// 지금 연표의 `timeline.echoBands`가 띠마다 매기는 `folded`와 같은 잣대다(js/timeline.js:2196).
  /// **흐르는 중인 값이 아니라 보기 상태를 본다** — 줄 높이가 흐르는 동안에도 딱지는 이미 맞다.
  /// 줄 번호(`row`)가 답에 없으면 트랙만이라도 본다(접힌 트랙).
  bool foldedIn(SceneLayout? layout) {
    if (folded) return true;
    if (layout == null) return false;
    // 정권이 없는 사건의 묶음(트랙)은 띠가 없어 접힘을 매기지 않는다 — 지금 연표도 `folded: !!b && !!b.folded`다.
    if (uid.isEmpty) return false;
    if (row >= 0 && row < layout.rowCount) {
      return layout.isTrackFolded(layout.trackOf(row).id) || layout.isMergedAway(row) || layout.isFoldedGroupRow(row) || layout.foldedRows.contains(row);
    }
    return trackId >= 0 && layout.isTrackFolded(trackId);
  }

  factory EchoGroup.read(Map<String, dynamic> row) {
    final events = [for (final e in detailList(row, 'events')) EchoEvent.read(e)];
    final track = detailString(row, 'track_name').isNotEmpty ? detailString(row, 'track_name') : (row['track'] is String ? row['track'] as String : '');
    final name = detailString(row, 'name');
    return EchoGroup(
      uid: detailString(row, 'uid'),
      name: name.isNotEmpty ? name : track,
      track: track,
      trackId: row['track'] is num ? (row['track'] as num).toInt() : -1,
      row: (detailNum(row, 'row') ?? -1).toInt(),
      color: row['color'] == null ? null : detailColor(row['color']),
      folded: row['folded'] == true,
      count: (detailNum(row, 'count') ?? events.length).toInt(),
      events: events,
    );
  }
}

/// 조회 명령 `echo`의 답.
@immutable
class EchoAnswer {
  const EchoAnswer({required this.count, this.ownUids = const [], this.echoIds = const [], this.groups = const []});

  /// 메아리 줄의 수(묶음에 든 것 모두).
  final int count;
  final List<String> ownUids;
  final List<int> echoIds;
  final List<EchoGroup> groups;

  /// 모두 [echoMax]건이 넘는가 — 그러면 나라마다 중요한 몇 건만 편다.
  bool get big => count > echoMax;

  EchoHits get hits => EchoHits(ownUids: ownUids, echoIds: echoIds);

  factory EchoAnswer.read(Map<String, dynamic> answer) {
    final groups = [for (final g in detailList(answer, 'groups')) EchoGroup.read(g)];
    return EchoAnswer(
      count: (detailNum(answer, 'count') ?? groups.fold<int>(0, (n, g) => n + g.events.length)).toInt(),
      ownUids: _texts(answer, 'ownUids', 'own_uids'),
      echoIds: _numbers(answer, 'echoIds', 'echo_ids'),
      groups: groups,
    );
  }

  static List<String> _texts(Map<String, dynamic> answer, String key, String other) {
    final v = answer[key] ?? answer[other];
    if (v is! List) return const [];
    return [
      for (final one in v)
        if (one is String && one.isNotEmpty) one,
    ];
  }

  static List<int> _numbers(Map<String, dynamic> answer, String key, String other) {
    final v = answer[key] ?? answer[other];
    if (v is! List) return const [];
    return [
      for (final one in v)
        if (one is num) one.toInt(),
    ];
  }
}

/// 사건 한 줄의 날짜 글 — 자료 처리부가 `when`을 주면 그대로, 아니면 분에서 셈한다.
String echoWhen(Map<String, dynamic> row) {
  final when = detailString(row, 'when');
  if (when.isNotEmpty) return when;
  final start = detailNum(row, 'start')?.toDouble();
  if (start == null) return '';
  final end = detailNum(row, 'end')?.toDouble();
  return rangeText(start: tOfMinutes(start), end: end == null || end == start ? null : tOfMinutes(end));
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 창 안의 자리 — 스위치와 묶음
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 칸 · 시기 · 지위 · 왕조 · 인물 창의 '같은 시기를 타국에도' 자리.
class EchoSlot extends StatefulWidget {
  const EchoSlot({super.key, required this.bus, required this.spots, required this.always, this.between = const [], this.color, this.onOpen});

  final AppBus bus;

  /// 이 창이 연표에 켠 기간 조명 `[{uid, cell?, start, end}]`(분) — 메아리는 이 구간에서 셈한다.
  final List<Map<String, dynamic>> spots;

  /// 칸 · 시기 · 지위 창은 참(강조를 늘 걸고 사건 배치에도 쓴다), 왕조 · 인물 창은 거짓.
  final bool always;

  /// 스위치와 묶음 사이에 드는 것 — 지금 연표의 차례가 그렇다(칸 창의 '이 시기의 사건' · 지위 창의 목록 둘).
  final List<Widget> between;

  /// 색이 없는 줄에 쓸 바탕색(그 항목의 색).
  final Color? color;

  /// 줄을 눌렀을 때 — 주지 않으면 그 사건을 고른다.
  final void Function(String uid)? onOpen;

  @override
  State<EchoSlot> createState() => _EchoSlotState();
}

class _EchoSlotState extends State<EchoSlot> {
  bool _on = false;

  /// 받아 둔 답(null이면 아직 못 받았거나 그 조회 명령이 없다 — 자리를 비운다).
  EchoAnswer? _answer;

  /// 내가 슬롯에 실어 둔 것(닫을 때 내 것만 치운다).
  EchoHits? _published;
  int _turn = 0;

  /// 줄을 다시 쌓은 번호 — 트랙 · 민족을 접거나 펴면 올라간다. `접힘` 딱지가 이것을 보고 다시 붙는다.
  int _stack = -1;

  ValueNotifier<Object?> get _switch => widget.bus.slot(echoSlot);
  ValueNotifier<Object?> get _filters => widget.bus.slot(_filterSlot);

  /// 지금 켜져 있는가 — 필터 시트의 값이 있으면 그것이 한 설정이다(`show.spotEcho` · 기본 끔).
  bool get _wanted {
    final state = _filters.value;
    if (state is FilterState) return state.showing('spotEcho');
    return _switch.value == true;
  }

  @override
  void initState() {
    super.initState();
    _on = _wanted;
    _switch.addListener(_sync);
    _filters.addListener(_sync);
    _stack = widget.bus.scene.layout.stackVersion;
    widget.bus.scene.addListener(_onRestack);
    // 그리는 중에는 슬롯을 건드리지 않는다(다른 부품이 그 자리에서 다시 그려지지 않게).
    scheduleMicrotask(() {
      if (!mounted) return;
      if (_switch.value != _on) _switch.value = _on;
      _ask();
    });
  }

  @override
  void didUpdateWidget(EchoSlot old) {
    super.didUpdateWidget(old);
    if (!_sameSpots(old.spots, widget.spots)) _ask();
  }

  @override
  void dispose() {
    _switch.removeListener(_sync);
    _filters.removeListener(_sync);
    widget.bus.scene.removeListener(_onRestack);
    final slot = widget.bus.slot(echoHitsSlot);
    if (_published != null && identical(slot.value, _published)) slot.value = null;
    super.dispose();
  }

  /// 필터 시트에서 켜고 꺼도 창의 체크와 목록이 함께 바뀐다.
  /// 앱 틀은 `slot('echo')`를 듣고 밝기를 고치므로 필터에서 바뀐 값도 그 자리에 옮겨 적는다.
  void _sync() {
    final next = _wanted;
    if (_switch.value != next) _switch.value = next;
    if (next != _on && mounted) setState(() => _on = next);
  }

  /// 장면이 알릴 때마다 오지만, **줄을 다시 쌓았을 때만** 다시 그린다(딱지 말고는 바뀔 것이 없다).
  void _onRestack() {
    final next = widget.bus.scene.layout.stackVersion;
    if (next == _stack) return;
    _stack = next;
    if (mounted) setState(() {});
  }

  void _toggle(bool on) {
    setState(() => _on = on);
    final state = _filters.value;
    if (state is FilterState) _filters.value = state.withShowing('spotEcho', on);
    _switch.value = on;
  }

  // ── 자료 ──────────────────────────────────────────────────────────────────────────────────

  /// 조명이 바뀌면 다시 묻는다. 스위치를 켜고 끌 때는 **다시 묻지 않는다** — 답은 제 것과 메아리를 함께 담고 있다.
  Future<void> _ask() async {
    final turn = ++_turn;
    final spots = widget.spots;
    if (spots.isEmpty) {
      _keep(null);
      return;
    }
    Map<String, dynamic>? answer;
    try {
      answer = await widget.bus.ask({
        'op': 'echo',
        'spots': [
          for (final s in spots)
            {
              if (s['band'] is num) 'band': s['band'],
              if (s['uid'] is String) 'uid': s['uid'],
              'start': s['start'],
              'end': s['end'],
            },
        ],
        'limit': echoLimit,
      });
    } catch (_) {
      // 그 조회 명령이 아직 없으면 이 자리만 빈다 — 창은 그대로 선다.
      answer = null;
    }
    if (!mounted || turn != _turn) return;
    _keep(answer == null || answer.isEmpty ? null : EchoAnswer.read(answer));
  }

  /// 답을 들고, 연표가 쓸 것만 슬롯에 싣는다.
  void _keep(EchoAnswer? answer) {
    if (!mounted) return;
    setState(() => _answer = answer);
    final hits = answer?.hits;
    _published = hits;
    widget.bus.slot(echoHitsSlot).value = hits;
  }

  static bool _sameSpots(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      for (final key in const ['uid', 'band', 'start', 'end']) {
        if (a[i][key] != b[i][key]) return false;
      }
    }
    return true;
  }

  void _open(String uid) {
    if (uid.isEmpty) return;
    final open = widget.onOpen;
    if (open != null) {
      open(uid);
    } else {
      widget.bus.select(uid);
    }
  }

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DetailSwitch(echoSwitchLabel, value: _on, onChanged: _toggle),
        ...widget.between,
        _EchoFill(child: _on && answer != null ? _EchoBox(answer: answer, layout: widget.bus.scene.layout, fallback: widget.color ?? Ui.text3, onOpen: _open) : null),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 켜고 끌 때의 움직임 — 높이는 move / snap, 내용은 in / out — 같은 장면에서 함께 접고 편다
// ────────────────────────────────────────────────────────────────────────────────────────────

class _EchoFill extends StatefulWidget {
  const _EchoFill({this.child});

  /// null이면 자리를 비운다(옅어진 뒤에 치운다).
  final Widget? child;

  @override
  State<_EchoFill> createState() => _EchoFillState();
}

class _EchoFillState extends State<_EchoFill> {
  late final _size = MotionAnimation(value: widget.child == null ? 0 : 1, enter: MotionToken.move, exit: MotionToken.snap, maxOvershoot: 0);
  late final MotionAnimation _fade = MotionAnimation(enter: MotionToken.enter, exit: MotionToken.exit, maxOvershoot: 0, value: widget.child == null ? 0 : 1);
  Widget? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.child;
    _fade.addStatusListener(_onStatus);
    _size.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _size.value = _fade.value = widget.child == null ? 0 : 1;
    }
  }

  void _onStatus(AnimationStatus status) {
    // 다 옅어졌으면 그제야 치운다.
    if (_fade.isDismissed && _size.isDismissed && widget.child == null && _shown != null && mounted) setState(() => _shown = null);
  }

  @override
  void didUpdateWidget(_EchoFill old) {
    super.didUpdateWidget(old);
    final next = widget.child;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _shown = next;
      _size.value = _fade.value = next == null ? 0 : 1;
      return;
    }
    if (next != null) {
      _shown = next;
      _size.forward();
      _fade.forward();
    } else if (_shown != null) {
      _size.reverse();
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return IgnorePointer(
      ignoring: widget.child == null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_fade, _size]),
        child: shown ?? const SizedBox(width: double.infinity),
        builder: (context, child) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _size.value.clamp(0.0, 1.0),
            child: Opacity(opacity: _fade.value.clamp(0.0, 1.0), child: child),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 묶음 — 나라마다 색 점 · 이름 · 트랙 · 건수(명세 3-4의 창 쪽 모양)
// ────────────────────────────────────────────────────────────────────────────────────────────

class _EchoBox extends StatefulWidget {
  const _EchoBox({required this.answer, required this.layout, required this.fallback, required this.onOpen});

  final EchoAnswer answer;

  /// `접힘` 딱지를 매길 줄 쌓기(엔진은 보기 상태를 모른다 — 계약 2-5의 ②).
  final SceneLayout layout;
  final Color fallback;
  final void Function(String uid) onOpen;

  @override
  State<_EchoBox> createState() => _EchoBoxState();
}

class _EchoBoxState extends State<_EchoBox> {
  /// 더 보기를 누른 묶음(그 나라만 모두 편다)과 '타국 n곳 더 펼치기'.
  final _opened = <String>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final answer = widget.answer;
    final groups = answer.groups;
    final shown = _all ? groups : groups.take(echoGroupMax).toList();
    final rest = groups.length - shown.length;
    if (answer.count == 0 || groups.isEmpty) {
      return const DetailBox(
        title: '같은 시기 타국',
        small: '없음',
        children: [Text('그 시기 타국의 사건이 없습니다.', style: TextStyle(fontSize: 13, height: 1.6, color: Ui.text3))],
      );
    }
    return DetailBox(
      title: '같은 시기 타국',
      small: '${groups.length}곳 · ${answer.count}건${answer.big ? ' · 나라마다 중요한 $echoEach건' : ''}',
      children: [
        for (final g in shown) ..._group(g),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DetailSmallButton('타국 $rest곳 더 펼치기', onTap: () => setState(() => _all = true)),
          ),
      ],
    );
  }

  List<Widget> _group(EchoGroup g) {
    final key = g.uid.isEmpty ? 't:${g.track}' : 'b:${g.uid}';
    final events = _rowsOf(g, _opened.contains(key));
    final rest = g.events.length - events.length;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: g.color ?? widget.fallback, shape: BoxShape.circle),
            ),
            Flexible(
              child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('${g.sub.isEmpty ? '' : '${g.sub} · '}${g.count}건', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3)),
            ),
            if (g.foldedIn(widget.layout))
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: '접힌 트랙 · 접힌 줄이라 연표에는 보이지 않습니다',
                  child: Text('접힘', style: TextStyle(fontSize: 10.5, height: 1.5, color: Ui.text3)),
                ),
              ),
          ],
        ),
      ),
      DetailYearEvents([
        for (final e in events)
          DetailYearRow(
            color: e.color ?? g.color ?? widget.fallback,
            when: e.when,
            title: e.title,
            tail: _tailOf(e),
            diamond: e.treaty,
            hollow: e.shared,
            onTap: () => widget.onOpen(e.uid),
          ),
      ]),
      if (rest > 0)
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2),
          child: DetailSmallButton('$rest건 더 보기', onTap: () => setState(() => _opened.add(key))),
        ),
    ];
  }

  /// 모두 [echoMax]건이 넘으면 나라마다 **중요한 [echoEach]건**만 — 고르는 잣대는 중요도(같으면 이른 것),
  /// 보이는 차례는 받은 그대로(연대순)다.
  List<EchoEvent> _rowsOf(EchoGroup g, bool opened) {
    if (!widget.answer.big || opened || g.events.length <= echoEach) return g.events;
    final order = [for (var i = 0; i < g.events.length; i++) i]
      ..sort((a, b) => g.events[b].importance - g.events[a].importance != 0 ? g.events[b].importance - g.events[a].importance : a - b);
    final keep = order.take(echoEach).toSet();
    return [
      for (var i = 0; i < g.events.length; i++)
        if (keep.contains(i)) g.events[i],
    ];
  }

  /// 제목 뒤의 꼬리표 — 하위 사건을 모은 `포함 n`과 함께 겪은 다른 자리의 `함께 · …` 둘뿐이다.
  /// 지금 연표의 메아리 목록(`js/viewer.js:2140`의 `echoRowsHTML`)도 그 둘만 적는다 —
  /// `소속 · 〈나라〉`는 **칸 상세의 '이 시기의 사건'**(`ownEventsHTML` · js/viewer.js:1154)에만 있는 글이라
  /// 여기에는 붙이지 않는다([EchoEvent.member] 참고).
  static String? _tailOf(EchoEvent e) {
    final tail = [
      if (e.kids > 0) '포함 ${e.kids}',
      if (e.alsoIn.isNotEmpty) '함께 · ${e.alsoIn.join(' · ')}',
    ];
    return tail.isEmpty ? null : tail.join(' ');
  }
}
