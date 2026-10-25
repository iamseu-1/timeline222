import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shell/look.dart';
import 'app_bus.dart';
import '../scene/aux_calendar.dart' show AuxCalendarStore;
import 'date_text.dart';
import 'detail_item.dart' as item_detail show ItemDetail;
import 'detail_echo.dart';
import 'detail_format3.dart';
import 'detail_item.dart' show certaintyNames, namedOf, rankMix;
import 'detail_shell.dart';
import 'names_display.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  칸 창 · 시기 창 · 지위 창
//  — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-3절의 ㈏(지도자 · 내각 · 연호 · 도읍) ·
//    ㈐(시기 구분(학계) · 체계 견주기) · ㈑(지위).
//
//  묶음이 나오는 차례는 지금 연표의 `cellDetailHTML`(js/viewer.js:1082) · `phaseDetailHTML`(1349) ·
//  `rankDetailHTML`(1472) 그대로이고, **비어 있는 묶음은 아예 그리지 않는다**(다만 '이 시기의 사건'은
//  지금 연표와 같이 비어도 상자를 두고 "없습니다" 한 줄을 적는다 — 그 칸에 사건이 없다는 것도 답이다).
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    registerCellDetail();                 // 앱을 세울 때 한 번 — 갈래 'cell' · 'phase' · 'rank'를 이 파일이 맡는다
//    …  DetailHost(bus: bus)               // 나머지는 뼈대가 한다
//
//    혼자 세울 때(검사 · 다른 창 안에 끼울 때):
//    CellDetail(bus: bus, entity: 항목기록JSON, cell: 'leader:3')
//      · entity = `{"op":"entity","uid":…}`의 json을 푼 Map(계약 6-9절). uid는 그 안의 `uid`를 쓴다.
//      · cell   = 칸 참조 — `leader:3` · `cabinet:0` · `era:2` · `capital:5` · `phase:4`(체계를 가로지른 번호 ci) · `rank:1`
//
//  ── 이 창이 항목 기록에서 읽는 것 ───────────────────────────────────────────────────────────
//    leaders · cabinets · eras · capitals(칸 목록) · phaseSchemes · rankSpans ·
//    x_cellBounds(칸마다의 경계 [lo, hi) — 분) · x_leaderFigures(같은 이름의 인물) · x_served(이 시기의 인물)
//    형식 3(계약 초안 6-9 다): x_cellNames(칸의 원어 줄) · x_lineage(자리 이음) · x_persons(칸의 사람 · 혈연 ·
//    속한 단체) · x_cellPlaces(도읍의 지명 줄) — 모두 `{"leader:3": …}`처럼 칸 참조가 열쇠다. 없으면 그 줄이 없다.
//
//  ── 자료 처리부에 묻는 것(없으면 그 묶음만 빠진다) ──────────────────────────────────────────
//    {"op":"events_in","band":정권uid,"lo":분,"hi":분,"limit":n}
//        → {"events":[{uid,title,when,start,end,color,treaty,member,prec}]}
//    같은 시기 타국(메아리)의 조회 `echo`는 그 자리를 맡은 [EchoSlot](detail_echo.dart)이 스스로 묻는다.
//
//  ── 앱 틀이 채워 주어야 하는 곳 ─────────────────────────────────────────────────────────────
//    bus.slot('tracks')   = {'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5}, …}  (머리의 트랙 배지)
//    bus.slot('docKeys')  = 문서가 있는 열쇠의 목록/집합 — 연표는 보기 전용이라 **문서가 있는 칸에만** 📄를 둔다.
//                           비어 있으면 📄 단추를 두지 않는다(칸의 문서 열쇠는 `cell:<정권uid>:<목록>:<이름>@<시작>`).
//    bus.slot('doc')      ← 📄를 누를 때 그 문서 열쇠를 넣는다(문서 창은 이 묶음 밖).
//    bus.slot('echo')     ← '같은 시기를 타국에도' 스위치의 값(bool).
//    bus.slot('spots')    ← 이 창이 켜는 기간 조명 `[{uid, cell, start, end}]`(분).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 갈래 `cell`(지도자 · 내각 · 연호 · 도읍) · `phase`(시기 구분) · `rank`(지위)를 이 파일이 맡는다.
void registerCellDetail() {
  DetailHost.register('cell', CellDetail.of);
  DetailHost.register('phase', CellDetail.of);
  DetailHost.register('rank', CellDetail.of);
}

// ── 이름 표(지금 연표의 js/core.js) ─────────────────────────────────────────────────────────

/// 칸 종류의 이름(`HT.CELL_KINDS`의 name)과 세는 말.
const cellKindNames = {'leader': '지도자', 'cabinet': '내각', 'era': '연호', 'capital': '도읍'};

/// 칸 종류 → 항목 기록의 목록 열쇠(문서 열쇠의 종류 글자이기도 하다).
const cellKindLists = {'leader': 'leaders', 'cabinet': 'cabinets', 'era': 'eras', 'capital': 'capitals'};

/// 도읍의 역할(`HT.CAPITAL_ROLES`).
const capitalRoleNames = {'main': '정도', 'co': '공동 정도', 'secondary': '배도', 'temporary': '임시', 'exile': '망명'};

/// 문서를 달지 않는 칸 종류 — 지위 칸은 제 문서가 없고 그 정권의 문서로 간다(명세 ㈑).
const cellKindsWithoutDoc = {'rank'};

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 칸의 경계 [lo, hi) — 명세 9절 ㈐-4 · 5 (순수 함수)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 칸이 품는 구간 `[lo, hi)` — 계약의 시간(분).
@immutable
class CellBounds {
  const CellBounds(this.lo, this.hi);
  final double lo, hi;

  @override
  bool operator ==(Object other) => other is CellBounds && other.lo == lo && other.hi == hi;
  @override
  int get hashCode => Object.hash(lo, hi);
  @override
  String toString() => 'CellBounds($lo, $hi)';
}

/// 칸이 연표에 놓인 구간 — 적힌 시작과, 끝을 비운 칸은 풀어 둔 끝(`endY`)이나 정권의 끝.
/// 기간 글 · 칸 그림이 쓰는 값이고, 칸이 **품는** 구간은 [cellBoundsOf]다.
@immutable
class CellSpan {
  const CellSpan({
    required this.start,
    this.startAt,
    required this.end,
    this.endAt,
    this.exact = false,
    this.startUnknown = false,
    this.endUnknown = false,
    this.ongoing = false,
  });

  final double? start, end;
  final String? startAt, endAt;

  /// 끝이 다음 칸의 시작에서 끌어낸 한 순간인가 — 그러면 "그해 끝까지"로 늘이지 않는다.
  final bool exact;
  final bool startUnknown, endUnknown, ongoing;
}

/// 칸 참조(`leader:3`)가 가리키는 칸 하나와 그 이웃들.
@immutable
class CellRef {
  const CellRef({required this.kind, required this.index, required this.cell, required this.list, required this.ref});

  /// `leader` · `cabinet` · `era` · `capital` · `phase` · `rank`.
  final String kind;

  /// [list] 안에서의 자리(앞뒤로 넘길 때 쓴다).
  final int index;
  final Map<String, dynamic> cell;

  /// 앞뒤로 넘길 이웃 — 시기는 **같은 체계**의 것만, 나머지는 그 종류의 목록 전부.
  final List<Map<String, dynamic>> list;
  final String ref;

  /// 칸 종류의 이름(`지도자` · `시기 구분(학계)` · `지위`).
  String get kindName => kind == 'phase' ? '시기 구분(학계)' : (kind == 'rank' ? '지위' : cellKindNames[kind] ?? kind);

  /// [list]의 i번째 칸의 칸 참조 — 없으면 null. 시기는 목록의 자리가 아니라 체계를 가로지른 번호(`ci`)로 가리킨다.
  String? refAt(int i) {
    if (i < 0 || i >= list.length) return null;
    if (kind == 'phase') return 'phase:${(detailNum(list[i], 'ci') ?? i).toInt()}';
    return '$kind:$i';
  }
}

/// 칸 참조로 칸 하나를 찾는다(`HT.cellRefOf`의 거꾸로). 없으면 null.
CellRef? findCell(Map<String, dynamic> entity, String cell) {
  final at = cell.indexOf(':');
  if (at <= 0) return null;
  final kind = cell.substring(0, at);
  final number = int.tryParse(cell.substring(at + 1));
  if (number == null) return null;

  if (kind == 'phase') {
    for (final scheme in detailList(entity, 'phaseSchemes')) {
      final spans = detailList(scheme, 'spans');
      for (int i = 0; i < spans.length; i++) {
        if ((detailNum(spans[i], 'ci') ?? -1).toInt() == number) {
          return CellRef(kind: kind, index: i, cell: spans[i], list: spans, ref: cell);
        }
      }
    }
    return null;
  }
  final list = detailList(entity, kind == 'rank' ? 'rankSpans' : (cellKindLists[kind] ?? ''));
  if (number < 0 || number >= list.length) return null;
  return CellRef(kind: kind, index: number, cell: list[number], list: list, ref: cell);
}

/// 칸의 끝이 진행 중인 정권의 끝(오늘)까지인지(`HT.cellToNow`) — 그런 칸의 기간 글은 끝이 `현재`다.
bool cellToNow(Map<String, dynamic> entity, Map<String, dynamic> cell) =>
    entity['ongoing'] == true &&
    cell['endUnknown'] != true &&
    cell['endYAuto'] != true &&
    (cell['endPolity'] == true || (cell['end'] == null && cell['endYNext'] != true));

/// 칸 하나만 보고 정한 구간(`HT.cellSpan`의 앞쪽 — 이웃 칸은 보지 않는다).
CellSpan placedSpan(Map<String, dynamic> entity, Map<String, dynamic> cell) {
  final start = detailNum(cell, 'start')?.toDouble();
  final startAt = detailString(cell, 'startAt');
  double? end;
  String endAt;
  if (cell['end'] != null) {
    end = detailNum(cell, 'end')?.toDouble();
    endAt = detailString(cell, 'endAt');
  } else if (cell['endY'] != null) {
    end = detailNum(cell, 'endY')?.toDouble();
    endAt = detailString(cell, 'endYAt');
  } else {
    end = detailNum(entity, 'endY')?.toDouble() ?? detailNum(entity, 'end')?.toDouble();
    endAt = detailString(entity, 'endAt');
  }
  return CellSpan(
    start: start,
    startAt: startAt.isEmpty ? null : startAt,
    end: end,
    endAt: endAt.isEmpty ? null : endAt,
    exact: (cell['end'] == null && cell['endYNext'] == true) || (cell['endAuto'] == true && cell['endPolity'] != true),
    startUnknown: cell['startUnknown'] == true,
    // 끝을 비운 도읍의 끝이 시작 미정인 다음 정도에서 짐작한 자리여도 "미정"이다(js/viewer.js:1086).
    endUnknown: cell['endUnknown'] == true || (cell['end'] == null && cell['endYAuto'] == true),
    ongoing: cellToNow(entity, cell),
  );
}

/// 연도만 적은 끝(정수 · 날짜 글 없음)이 실제로 뜻하는 마지막 순간 — 그해 끝(`HT.endBound`).
double? endBoundT(double? end, {String? at, bool exact = false}) {
  if (end == null) return null;
  if (exact) return end;
  if (atFits(at, end)) return unitEnd(end, precOfAt(at)) - 1e-9;
  if (end != end.roundToDouble()) return end;
  return end + 1 - 1e-9;
}

/// **칸이 품는 구간 `[lo, hi)`(분)** — 명세 9절 ㈐-4. 조명 · 그 시기의 사건 · 이 시기의 인물 ·
/// `🎯 이 시기로` · 같은 해 보기가 모두 이 값 하나를 본다.
///
/// 이웃 칸을 봐야 정해지는 값이라 내보내기가 넣을 때 확정해 둔 `x_cellBounds`(계약 6-9 가)가 먼저다
/// — 경계 해는 뒤 칸의 것이라 앞 칸의 `hi`와 뒤 칸의 `lo`가 같은 순간이 된다.
/// 그 값이 없는 기록(옛 판)은 칸 하나만 보고 정한다: `lo` = 시작 · `hi` = 연도만 적은 끝이면 그해 끝까지.
CellBounds? cellBoundsOf(Map<String, dynamic> entity, String cell) {
  final table = entity['x_cellBounds'];
  if (table is Map) {
    final v = table[cell];
    if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
      return CellBounds((v[0] as num).toDouble(), (v[1] as num).toDouble());
    }
  }
  final ref = findCell(entity, cell);
  if (ref == null) return null;
  final sp = placedSpan(entity, ref.cell);
  if (sp.start == null) return null;
  final lo = minutesOfT(sp.start!);
  final hi = endBoundT(sp.end, at: sp.endAt, exact: sp.exact);
  return CellBounds(lo, hi == null ? lo : math.max(lo, minutesOfT(hi)));
}

/// 구간 `[a, b)`가 `[lo, hi)`에 걸치는가(`HT.spanMeets`) — 폭 0인 쪽은 한 점으로 본다.
/// 활동 기록(이 시기의 인물) · 칸끼리 · 같은 해 보기가 쓴다.
bool spanMeets(double a, double b, double lo, double hi) {
  if (!(b > a)) return hi > lo ? (lo <= a && a < hi) : a == lo;
  if (!(hi > lo)) return a <= lo && lo < b;
  return a < hi && lo < b;
}

/// 적힌 값이 덮는 단위 `[처음, 끝)`(분) — 연도만 적은 값은 그해 전체, 달까지면 그달, 날까지면 그날.
/// 시 · 분까지 적은 값은 한 점으로 본다(그 단위의 폭은 경계를 가르는 데 쓸 만큼 넓지 않다).
(double, double) dateUnit(double at, DatePrec prec) {
  if (prec == DatePrec.hour || prec == DatePrec.minute) return (at, at);
  final t = tOfMinutes(at);
  final a = civilAt(t);
  final double from = switch (prec) {
    DatePrec.year => a.year.toDouble(),
    DatePrec.month => tOfJdn(jdnOf(a.year, a.month, 1)),
    _ => tOfJdn(a.jdn),
  };
  return (minutesOfT(from), minutesOfT(unitEnd(from, prec)));
}

/// 항목(사건 …)이 칸이 품는 구간 `[lo, hi)`에 걸치는가(`HT.spanHit`) — 명세 9절 ㈐-5.
///
/// 기간이 있는 항목은 `[시작, 끝이 덮는 단위의 끝)`, **한 단위뿐인 항목(연도만 적은 사건)은 그 단위의
/// 한가운데 한 점**으로 본다 — 경계 해의 사건이 앞뒤 두 칸의 목록에 모두 들지 않게.
bool spanHit({
  required double start,
  double? end,
  DatePrec startPrec = DatePrec.year,
  DatePrec? endPrec,
  bool ongoing = false,
  required double lo,
  required double hi,
}) {
  final s = dateUnit(start, startPrec);
  final (double, double)? e = ongoing ? (end == null ? null : (end, end)) : (end == null ? null : dateUnit(end, endPrec ?? startPrec));
  if (e == null || (e.$1 == s.$1 && e.$2 == s.$2)) {
    final t = (s.$1 + s.$2) / 2;
    return spanMeets(t, t, lo, hi);
  }
  return spanMeets(s.$1, math.max(s.$1, e.$2), lo, hi);
}

/// `🎯 이 시기로`가 잡는 보기 범위 — 칸의 기간에 앞뒤 35% 여유, 8년보다 좁게는 가지 않는다(js/viewer.js:2288).
/// 8년을 1.7로 나눈 것이 지금 연표의 가장 좁은 보기 폭이고, 525,960분이 한 해다.
const _focusMinSpan = 8 / 1.7 * 525960.0;

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 창
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 칸 창(지도자 · 내각 · 연호 · 도읍) · 시기 창 · 지위 창. 셋은 같은 길(조명 · 앞뒤 넘기기 · 이 시기의 사건)을 쓴다.
class CellDetail extends StatefulWidget {
  const CellDetail({super.key, required this.bus, required this.entity, required this.cell, this.uid, this.onClose});

  final AppBus bus;

  /// 항목 기록의 JSON을 푼 것(계약 6-9절).
  final Map<String, dynamic> entity;

  /// 칸 참조 — `leader:3` · `phase:4` · `rank:1` …
  final String cell;

  /// 기록의 `uid`와 다를 때만(보통은 비워 둔다).
  final String? uid;

  /// 닫기 — 없으면 고르기를 푼다.
  final VoidCallback? onClose;

  /// 뼈대에 갈래를 등록할 때 쓰는 길([registerCellDetail]).
  static Widget of(DetailContext ctx) => CellDetail(bus: ctx.bus, entity: ctx.json, cell: ctx.cell ?? '', uid: ctx.uid, onClose: ctx.close);

  @override
  State<CellDetail> createState() => _CellDetailState();
}

class _CellDetailState extends State<CellDetail> {
  /// 이 시기의 사건 — null이면 아직 답을 받지 못했다(그 명령이 없으면 묶음을 그리지 않는다).
  List<Map<String, dynamic>>? _events;
  int _turn = 0;

  /// 같은 사람의 자리(건의 8의 6-가 · 2026-10-13) — 이 칸 자신과 그 사람의 다른 칸들(다른 나라 · 같은 나라 복위), 시작 순.
  /// null이면 아직 받지 못했다(그동안은 [_roughSeats] — 칸 기록의 `others` 글만으로 그린다).
  List<_Seat>? _seats;

  Map<String, dynamic> get x => widget.entity;
  String get uid => widget.uid ?? detailString(x, 'uid');
  Color get color => detailColor(x['color'], Ui.text3);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CellDetail old) {
    super.didUpdateWidget(old);
    if (old.cell != widget.cell || !identical(old.entity, widget.entity)) _load();
  }

  @override
  void dispose() {
    // 내가 켠 조명만 끈다 — 다음 칸 창이 이미 제 조명으로 갈아 끼웠으면 건드리지 않는다(명세 3-3의 `lit-sw`).
    final lit = widget.bus.slot('spots').value;
    if (lit is List && lit.isNotEmpty && lit.first is Map && (lit.first as Map)['cell'] == widget.cell) {
      widget.bus.slot('spots').value = null;
    }
    // 같은 사람의 칸 테(건의 8의 6-나)도 내가 실은 것만 거둔다.
    final twins = widget.bus.slot('twins').value;
    if (twins is List && twins.isNotEmpty && twins.first is Map && (twins.first as Map)['cell'] == widget.cell && (twins.first as Map)['uid'] == uid) {
      widget.bus.slot('twins').value = null;
    }
    super.dispose();
  }

  // ── 자료 ──────────────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _ask(Map<String, dynamic> query) async {
    try {
      return await widget.bus.ask(query);
    } catch (_) {
      // 그 조회 명령이 아직 없으면 그 묶음만 빠진다 — 창은 그대로 선다.
      return null;
    }
  }

  List<Map<String, dynamic>>? _rows(Map<String, dynamic>? answer, String key) {
    if (answer == null) return null;
    for (final k in [key, 'rows', 'list']) {
      final v = answer[k];
      if (v is List) {
        return [
          for (final row in v)
            if (row is Map) row.cast<String, dynamic>(),
        ];
      }
    }
    return null;
  }

  /// 칸이 바뀌면(◀ ▶ · 배지) 묶음을 비우고 다시 묻는다. [initState] · [didUpdateWidget]에서 불리므로
  /// 그리는 중에는 값을 그대로 넣고(다시 그리기는 어차피 예약되어 있다), 알림과 조회는 다음 판으로 미룬다.
  void _load() {
    final turn = ++_turn;
    _events = null;
    _surname = null;
    _seats = null;
    unawaited(_loadSurname(turn));
    unawaited(_loadSeats(turn));
    scheduleMicrotask(() {
      // 같은 사람의 칸(건의 8의 6-나): 연표가 이 칸과 그 사람의 다른 칸에 먹 테를 두른다 — 다른 자리가 없으면 거둔다.
      if (mounted && turn == _turn) widget.bus.slot('twins').value = _twinAsk();
    });
    final bounds = cellBoundsOf(x, widget.cell);
    if (bounds == null) return;
    scheduleMicrotask(() {
      if (!mounted || turn != _turn) return;
      // 창이 연표에 켜는 기간 조명 — 칸이 품는 구간 그대로(명세 3-3).
      widget.bus.slot('spots').value = _spots();
      // 지위 창은 사건 목록을 두지 않으므로 묻지 않는다.
      if (!widget.cell.startsWith('rank:')) _loadEvents(turn, bounds);
    });
  }

  /// 이 창이 연표에 켜는 기간 조명(메아리도 이 구간에서 센다).
  List<Map<String, dynamic>> _spots() {
    final bounds = cellBoundsOf(x, widget.cell);
    if (bounds == null) return const [];
    return [
      {'uid': uid, 'cell': widget.cell, 'start': bounds.lo, 'end': bounds.hi},
    ];
  }

  /// 휴대폰의 성씨 배지(D1 결정 6 A — 확정 설계 5-2 · 나라 · 왕조 창은 detail_item과 같은 값): 가문 배지 옆 `성 ○ · 본관 ○○`.
  /// 올림 풍선이 없는 휴대폰에서만(`ItemDetail.surnameBadge`) — 컴퓨터는 띠 위 성씨 풍선(D1-N3)이 같은 값을 보인다.
  ({String text, String uid})? _surname;

  Future<void> _loadSurname(int turn) async {
    final houseId = detailString(findCell(x, widget.cell)?.cell ?? const {}, 'houseId');
    if (!item_detail.ItemDetail.surnameBadge || houseId.isEmpty) return;
    final h = await detailEntity(widget.bus, 'house:$houseId');
    if (!mounted || turn != _turn || h == null) return;
    final sn = h['x_surname'] is Map ? (h['x_surname'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final name = detailString(sn, 'name').isNotEmpty ? detailString(sn, 'name') : detailString(h, 'surname');
    if (name.isEmpty) return;
    final seat = detailString(h, 'seat');
    setState(() => _surname = (text: '성 $name${seat.isEmpty ? '' : ' · 본관 $seat'}', uid: detailString(sn, 'uid')));
  }

  /// 같은 사람의 다른 칸(`x_persons[칸].others` — `[{name, uid, ref, polity, when}]`). 지도자 · 내각 칸만.
  List<Map<String, dynamic>> _othersOf(CellRef ref) {
    if (ref.kind != 'leader' && ref.kind != 'cabinet') return const [];
    final p = _byCell('x_persons', ref.ref);
    return p == null ? const [] : detailList(p, 'others');
  }

  /// 연표에 실을 같은 사람의 칸 — 이 칸이 맨 앞(창이 닫힐 때 제 것인지 가린다). 다른 자리가 없으면 null.
  List<Map<String, String>>? _twinAsk() {
    final ref = findCell(x, widget.cell);
    if (ref == null) return null;
    final others = _othersOf(ref);
    if (others.isEmpty) return null;
    return [
      {'uid': uid, 'cell': ref.ref},
      for (final q in others)
        if (detailString(q, 'uid').isNotEmpty && detailString(q, 'ref').isNotEmpty) {'uid': detailString(q, 'uid'), 'cell': detailString(q, 'ref')},
    ];
  }

  /// 다른 자리의 기록을 받아 자리 줄(나라 · 대수 · 기간 · 자리 이음)을 짓는다. 같은 나라(복위)는 이 기록 그대로.
  Future<void> _loadSeats(int turn) async {
    await Future<void>.value(); // 그리는 중(initState · didUpdateWidget)에는 setState를 부르지 않는다
    if (!mounted || turn != _turn) return;
    final ref = findCell(x, widget.cell);
    if (ref == null) return;
    final others = _othersOf(ref);
    if (others.isEmpty) return;
    final seats = <_Seat>[_seatOf(x, uid, ref, here: true)];
    for (final q in others) {
      final u = detailString(q, 'uid'), r = detailString(q, 'ref');
      if (u.isEmpty || r.isEmpty) continue;
      final e = u == uid ? x : await detailEntity(widget.bus, u);
      if (!mounted || turn != _turn) return;
      final cell = e == null ? null : findCell(e, r);
      seats.add(cell == null ? _Seat.rough(q) : _seatOf(e!, u, cell));
    }
    seats.sort((a, b) => (a.start ?? double.infinity).compareTo(b.start ?? double.infinity));
    setState(() => _seats = seats);
  }

  /// 기록을 받기 전의 자리들 — 다른 칸은 `others`의 글(나라 이름 · 기간 글)만으로.
  List<_Seat> _roughSeats(CellRef ref) => [_seatOf(x, uid, ref, here: true), for (final q in _othersOf(ref)) _Seat.rough(q)];

  /// 칸 하나의 자리 줄 — 나라 [e]의 칸 [cell].
  _Seat _seatOf(Map<String, dynamic> e, String polity, CellRef cell, {bool here = false}) {
    final sp = placedSpan(e, cell.cell);
    final ordinal = detailNum(cell.cell, 'ordinal');
    final nth = cell.kind != 'leader' ? '' : (ordinal != null ? '${_plainNumber(ordinal)}대' : (cell.cell['ordinalUnknown'] == true ? '대수 미상' : ''));
    final end = sp.ongoing ? DateTime.now().year.toDouble() : (sp.endUnknown ? null : sp.end);
    return _Seat(
      uid: polity,
      ref: cell.ref,
      polity: detailString(e, 'name'),
      color: detailColor(e['color'], Ui.text3),
      tag: nth.isEmpty ? cell.kindName : '${cell.kindName} · $nth',
      years: '${sp.startUnknown || sp.start == null ? '미정' : _yearLabel(sp.start!)} ~ ${sp.ongoing ? '현재' : (end == null ? '미정' : _yearLabel(end))}',
      start: sp.startUnknown ? null : sp.start,
      end: end,
      span: sp,
      lineage: _lineageBits(e, cell, polity, seat: true) ?? const [],
      here: here,
    );
  }

  /// 자리 줄의 연도(달 · 날은 빼고 해만 — 목업의 `1455 ~ 1480`).
  static String _yearLabel(double t) {
    final y = t == t.roundToDouble() ? t.round() : civilAt(t).year;
    return y < 0 ? '기원전 ${-y}' : '$y';
  }

  Future<void> _loadEvents(int turn, CellBounds bounds) async {
    final answer = await _ask({'op': 'events_in', 'band': uid, 'lo': bounds.lo, 'hi': bounds.hi, 'limit': 200});
    if (!mounted || turn != _turn) return;
    setState(() => _events = _rows(answer, 'events'));
  }

  // ── 가기 · 열기 ───────────────────────────────────────────────────────────────────────────

  void _close() => widget.onClose == null ? widget.bus.clearSelection() : widget.onClose!();
  void _open(String target, {String kind = '', String? cell}) => widget.bus.select(target, kind: kind, cell: cell);
  void _goCell(String ref) => _open(uid, cell: ref);

  /// 🎯 이 시기로 — 칸이 품는 구간에 앞뒤 35% 여유(8년보다 좁게는 가지 않는다).
  void _focus() {
    final bounds = cellBoundsOf(x, widget.cell);
    if (bounds == null) return;
    final len = math.max(bounds.hi - bounds.lo, _focusMinSpan);
    final pad = len * .35;
    widget.bus.goTo(bounds.lo - pad, bounds.hi + pad, ring: uid);
  }

  /// 다른 견해의 연대를 누르면 그 해로.
  void _goYear(double t) => widget.bus.goTo(minutesOfT(t), minutesOfT(t + 1), ring: uid);

  /// 문서가 있는 열쇠인가 — 연표는 보기 전용이라 **있는 문서에만** 📄를 둔다.
  bool _hasDoc(String key) {
    if (key.isEmpty) return false;
    final table = widget.bus.slot('docKeys').value;
    if (table is Set) return table.contains(key);
    if (table is List) return table.contains(key);
    if (table is Map) return table.containsKey(key);
    return false;
  }

  /// 칸의 문서 열쇠 — `cell:<정권uid>:<목록>:<이름>@<시작>`(`HT.docKey.cell`).
  /// 이름은 `docName`이 있으면 그것(시기 구분은 체계를 붙인 이름), 시작은 내림한 해다.
  String _docKey(CellRef ref) {
    if (cellKindsWithoutDoc.contains(ref.kind)) return uid; // 지위 칸에는 제 문서를 달지 않는다
    final list = ref.kind == 'phase' ? 'phases' : (cellKindLists[ref.kind] ?? '');
    if (list.isEmpty) return '';
    final doc = detailString(ref.cell, 'docName');
    final name = doc.isNotEmpty ? doc : detailString(ref.cell, 'name');
    final start = detailNum(ref.cell, 'start');
    return 'cell:$uid:$list:$name@${start == null ? '' : (start + 1e-9).floor()}';
  }

  static String _plainNumber(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  // ── 창 ────────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ref = findCell(x, widget.cell);
    if (ref == null) {
      return DetailShell(
        onClose: _close,
        badges: [DetailBadge(detailString(x, 'name'), color: color, onTap: () => _open(uid))],
        body: [
          DetailTitle(detailString(x, 'name')),
          DetailNote('이 항목에 «${widget.cell}» 칸이 없습니다 — 자료가 바뀌었거나 칸 참조가 잘못되었습니다.'),
        ],
        foot: [DetailSmallButton('닫기', onTap: _close)],
      );
    }
    return DetailShell(
      onClose: _close,
      badges: _badges(ref),
      body: switch (ref.kind) {
        'phase' => _phaseBody(ref),
        'rank' => _rankBody(ref),
        _ => _cellBody(ref),
      },
      foot: _foot(ref),
    );
  }

  List<Widget> _foot(CellRef ref) {
    final key = _docKey(ref);
    final doc = _hasDoc(key);
    return [
      DetailSmallButton('이 시기로', icon: LineGlyph.locate, onTap: _focus),
      if (doc)
        DetailSmallButton(
          ref.kind == 'rank' ? '${detailString(x, 'name')} 문서' : '문서',
          icon: LineGlyph.file,
          onTap: () => widget.bus.slot('doc').value = key,
        ),
      DetailSmallButton('닫기', onTap: _close),
    ];
  }

  // ── 머리 배지 ─────────────────────────────────────────────────────────────────────────────

  List<Widget> _badges(CellRef ref) {
    if (_othersOf(ref).isNotEmpty) {
      // 한 사람의 창(건의 8의 6-가): 나라 · 대수는 자리 줄에 — 머리에는 '인물'(인물 기록이 있으면 누르면 인물 창) · 가문 · 확실성.
      final fig = _figureUidOf(ref);
      return [
        DetailBadge('인물', color: Ui.ink40, onTap: fig.isEmpty ? null : () => _open(fig, kind: 'figure')),
        ..._houseBadge(ref.cell),
        ..._certBadge(ref.cell),
      ];
    }
    final out = <Widget>[];
    final track = namedOf(widget.bus, 'tracks', detailString(x, 'track'));
    if (track != null) out.add(DetailBadge(track.name, color: track.color));
    out.add(DetailBadge(detailString(x, 'name'), color: color, onTap: () => _open(uid)));

    if (ref.kind == 'phase') {
      final scheme = detailString(ref.cell, 'scheme');
      out.add(DetailBadge('시기 구분(학계)${scheme.isEmpty ? '' : ' · $scheme'}', color: const Color(0xffb3a896)));
    } else if (ref.kind == 'rank') {
      final tier = detailNum(ref.cell, 'tier');
      out.add(DetailBadge('지위${tier == null ? '' : ' · 서열 ${_plainNumber(tier)}'}', color: color));
    } else {
      final tag = _cellTag(ref);
      out.add(DetailBadge('${ref.kindName}${tag.isEmpty ? '' : ' · $tag'}', color: color));
      out.addAll(_rankBadge(ref));
    }
    out.addAll(_houseBadge(ref.cell));
    out.addAll(_certBadge(ref.cell));
    return out;
  }

  /// 이 칸의 사람의 인물 기록 uid — 칸에 적은 사람(`x_persons[칸].figure`), 없으면 같은 이름의 인물(`x_leaderFigures`). 없으면 빈 글.
  String _figureUidOf(CellRef ref) {
    final f = _byCell('x_persons', ref.ref)?['figure'];
    if (f is Map && '${f['uid'] ?? ''}'.isNotEmpty) return '${f['uid']}';
    final twin = _byCell('x_leaderFigures', ref.ref);
    return twin == null ? '' : detailString(twin, 'uid');
  }

  /// 이름표 뒤에 붙는 말 — 지도자는 `제n대`, 도읍은 역할(정도는 빼고).
  String _cellTag(CellRef ref) {
    if (ref.kind == 'leader') {
      final ordinal = detailNum(ref.cell, 'ordinal');
      if (ordinal == null) return ref.cell['ordinalUnknown'] == true ? '대수 미상' : ''; // 대수 미상(묶음 5 · 4번)
      return '제${_plainNumber(ordinal)}대';
    }
    if (ref.kind == 'capital') {
      final role = detailString(ref.cell, 'role');
      return role.isEmpty || role == 'main' ? '' : (capitalRoleNames[role] ?? role);
    }
    return '';
  }

  /// 지도자의 지위 배지 — 적은 지위, 없으면 그 해의 정권 지위(짐작). 같은 이름의 지위 구간이 있을 때만 누를 수 있다.
  List<Widget> _rankBadge(CellRef ref) {
    if (ref.kind != 'leader') return const [];
    final written = detailString(ref.cell, 'rank');
    final name = written.isNotEmpty ? written : detailString(ref.cell, 'rankAuto');
    if (name.isEmpty) return const [];
    final spans = detailList(x, 'rankSpans');
    final start = detailNum(ref.cell, 'start')?.toDouble();
    final end = (detailNum(ref.cell, 'end') ?? detailNum(x, 'endY'))?.toDouble();
    int hit = -1;
    if (start != null) {
      final same = [
        for (int j = 0; j < spans.length; j++)
          if (detailString(spans[j], 'name') == name) j,
      ];
      double s(int j) => (detailNum(spans[j], 'start') ?? 0).toDouble();
      double e(int j) => (detailNum(spans[j], 'end') ?? detailNum(x, 'endY') ?? 0).toDouble();
      hit = same.firstWhere((j) => s(j) <= start && start < e(j), orElse: () => -1);
      if (hit < 0) hit = same.firstWhere((j) => s(j) <= start && start <= e(j), orElse: () => -1);
      if (hit < 0 && end != null) hit = same.firstWhere((j) => s(j) < end && start < e(j), orElse: () => -1);
    }
    final text = '지위 $name${written.isEmpty ? ' (짐작)' : ''}';
    return [DetailBadge(text, color: color, onTap: hit < 0 ? null : () => _goCell('rank:$hit'))];
  }

  /// 가문 배지 — 누르면 가문 창.
  List<Widget> _houseBadge(Map<String, dynamic> cell) {
    final id = detailString(cell, 'houseId');
    if (id.isEmpty) return const [];
    final name = detailString(cell, 'houseName');
    final sn = _surname;
    return [
      DetailBadge(
        name.endsWith('가문') ? name : '가문 $name',
        color: detailColor(cell['houseColor'], Ui.text3),
        onTap: () => _open('house:$id'),
      ),
      // 휴대폰의 성씨 배지(D1 — 위 _loadSurname). 누르면 성씨 창.
      if (sn != null) DetailBadge(sn.text, color: detailColor(cell['houseColor'], Ui.text3), onTap: sn.uid.isEmpty ? null : () => _open(sn.uid, kind: 'surname')),
    ];
  }

  /// 확실성 배지 — 통설이면 없다.
  List<Widget> _certBadge(Map<String, dynamic> cell) {
    final cert = detailString(cell, 'certainty');
    if (cert.isEmpty || cert == 'accepted') return const [];
    return [DetailBadge('${certaintyNames[cert] ?? cert} 연대', color: DetailUi.warn)];
  }

  // ── ㈏ 칸 창(지도자 · 내각 · 연호 · 도읍) ────────────────────────────────────────────────

  List<Widget> _cellBody(CellRef ref) {
    final c = ref.cell;
    final sp = placedSpan(x, c);
    final facts = _facts(ref);
    final prec = atFits(sp.startAt, sp.start) ? precOfAt(sp.startAt) : DatePrec.year;
    final fine = prec == DatePrec.day || prec == DatePrec.hour || prec == DatePrec.minute;
    final dyn = detailString(c, 'dynasty').isNotEmpty ? detailString(c, 'dynasty') : detailString(c, 'dynastyAuto');
    // 한 사람의 창(건의 8의 6-가): 기간은 모든 자리를 합친 것 — 가장 이른 시작 ~ 가장 늦은 끝.
    final seats = _seats;
    final whole = seats != null && seats.length > 1 ? _wholeOf(seats) : null;

    return [
      DetailTitle(_cellName(ref)),
      // 원어 머리 두 줄(10건 3 · 감독 결정 D2-1 A — 웹 namesHeadHTML(c.names, 지도자 → 인물 · 도읍 → 지명 · 그 밖 → 나라) · 제목 바로 아래).
      NamesHead(bus: widget.bus, head: _byCell('x_cellNameHead', ref.ref), old: _byCell('x_cellNames', ref.ref), kind: _nameKindOf(ref)),
      if (facts.isNotEmpty) DetailAka(facts.join(' · ')),
      if (whole != null)
        DetailWhen(
          rangeText(
            start: whole.start,
            startAt: whole.startAt,
            end: whole.end,
            endAt: whole.endAt,
            startUnknown: whole.startUnknown,
            endUnknown: whole.endUnknown,
            ongoing: whole.ongoing,
          ),
        )
      else
        DetailWhen(
          rangeText(start: sp.start, startAt: sp.startAt, end: sp.end, endAt: sp.endAt, startUnknown: sp.startUnknown, endUnknown: sp.endUnknown, ongoing: sp.ongoing),
          sub: fine && sp.start != null ? dayNote(sp.start!, lunar: AuxCalendarStore.shared?.lunar, withLunar: !isLunarAt(sp.startAt)) : null,
        ),
      ..._unknownNote(sp),
      ..._rangeNotes(c),
      if (dyn.isNotEmpty) DetailAka('왕조 $dyn${detailString(c, 'dynasty').isEmpty ? ' (시작한 해로 짐작)' : ''}'),
      ..._leaderFigure(ref),
      if (ref.kind == 'leader' || ref.kind == 'cabinet') ..._personLines(ref),
      if (ref.kind == 'capital') NamesPlace(bus: widget.bus, place: _byCell('x_cellPlaces', ref.ref), lead: '지명'),
      NamesRest(bus: widget.bus, head: _byCell('x_cellNameHead', ref.ref), kind: _nameKindOf(ref)),
      _memo(detailString(c, 'note')),
      ..._alternatives(c, sp),
      _nav(ref),
      _echoSlot(_ownEvents()),
      if (ref.kind == 'leader' || ref.kind == 'cabinet') ..._cellFigures(),
    ];
  }

  /// 자리들을 합친 기간 — 가장 이른 시작의 자리 · 가장 늦은 끝의 자리에서 그 글(날짜 글 · 미정 · 현재)까지.
  static CellSpan _wholeOf(List<_Seat> seats) {
    CellSpan? first, last;
    double endOf(CellSpan s) => s.ongoing ? double.infinity : (s.end ?? double.negativeInfinity);
    for (final seat in seats) {
      final s = seat.span;
      if (s == null) continue;
      if (s.start != null && !s.startUnknown && (first == null || s.start! < first.start!)) first = s;
      if (last == null || endOf(s) > endOf(last)) last = s;
    }
    return CellSpan(
      start: first?.start,
      startAt: first?.startAt,
      startUnknown: first == null,
      end: last?.end,
      endAt: last?.endAt,
      endUnknown: last?.endUnknown ?? true,
      ongoing: last?.ongoing ?? false,
    );
  }

  /// 칸 이름 목록의 적용 체크 종류(웹 viewer.js 칸 창: 지도자 → 인물 · 도읍 → 지명 · 그 밖 → 나라).
  NameKind _nameKindOf(CellRef ref) => ref.kind == 'leader' ? NameKind.person : ref.kind == 'capital' ? NameKind.place : NameKind.polity;

  /// 칸의 제목 — 지도자는 지금 연표의 기본 표기(`HT.leaderLabel(c, 'auto')`).
  String _cellName(CellRef ref) {
    final c = ref.cell;
    if (ref.kind == 'leader') {
      for (final key in const ['name', 'temple', 'title', 'given']) {
        final v = detailString(c, key);
        if (v.isNotEmpty) return v;
      }
      return '';
    }
    final name = detailString(c, 'name');
    return name.isNotEmpty ? name : detailString(c, 'city');
  }

  /// 제목 아래 한 줄에 적는 것들(`K.facts`) — 지도자는 묘호 · 시호 · 이름, 도읍은 역할 · 도시 · 시기 이름 · 묶음.
  List<String> _facts(CellRef ref) {
    final c = ref.cell;
    if (ref.kind == 'leader') {
      return [
        if (detailString(c, 'temple').isNotEmpty) '묘호 ${detailString(c, 'temple')}',
        if (detailString(c, 'title').isNotEmpty) '시호 ${detailString(c, 'title')}',
        if (detailString(c, 'given').isNotEmpty) '이름 ${detailString(c, 'given')}',
      ];
    }
    if (ref.kind == 'capital') {
      final role = detailString(c, 'role');
      final as = detailString(c, 'as'), city = detailString(c, 'city');
      return [
        '역할 ${capitalRoleNames[role.isEmpty ? 'main' : role] ?? role}',
        if (as.isNotEmpty && as != city) '도시 $city',
        if (detailString(c, 'label').isNotEmpty) '시기 이름 ${detailString(c, 'label')}',
        if (detailString(c, 'group').isNotEmpty) '묶음 ${detailString(c, 'group')}',
      ];
    }
    return const [];
  }

  /// 지도자 칸의 '같은 이름의 인물' 링크(`x_leaderFigures`).
  List<Widget> _leaderFigure(CellRef ref) {
    if (ref.kind != 'leader') return const [];
    final table = x['x_leaderFigures'];
    if (table is! Map) return const [];
    final row = table[ref.ref];
    if (row is! Map) return const [];
    final f = row.cast<String, dynamic>();
    final role = detailString(f, 'role');
    return [
      DetailNote(
        '같은 이름의 인물: ${detailString(f, 'name')}${role.isEmpty ? '' : ' · $role'}',
        onTap: () => _open(detailString(f, 'uid'), kind: 'figure'),
      ),
    ];
  }

  /// 칸 참조를 열쇠로 둔 표(`x_cellNames` · `x_lineage` · `x_persons` · `x_cellPlaces`)에서 그 칸의 값.
  Map<String, dynamic>? _byCell(String key, String ref) {
    final table = x[key];
    if (table is! Map) return null;
    final v = table[ref];
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  /// 지도자 · 내각 칸의 사람 글(형식 3 — 웹 `cellPersonHTML`): 자리 이음 → `사람:` → 같은 사람의 다른 칸 → 혈연 → 속한 단체.
  List<Widget> _personLines(CellRef ref) {
    final p = _byCell('x_persons', ref.ref);
    if (p != null && _othersOf(ref).isNotEmpty) return _seatLines(ref, p);
    final out = <Widget>[...?_lineageLine(ref)];
    if (p == null) return out;
    out.addAll(_figureLine(ref, p));
    // 같은 사람의 다른 칸 — 같은 나라면 기간만, 다른 나라면 `나라 기간`.
    final others = detailList(p, 'others');
    if (others.isNotEmpty) {
      out.add(
        DetailLine([
          const DetailBit('같은 사람의 다른 칸: '),
          ...detailJoin([
            for (final q in others)
              [
                DetailBit.link(
                  '${detailString(q, 'uid') == uid || detailString(q, 'polity').isEmpty ? '' : '${detailString(q, 'polity')} '}'
                  '${detailString(q, 'when').isNotEmpty ? detailString(q, 'when') : detailString(q, 'name')}',
                  detailString(q, 'uid').isEmpty ? null : () => _open(detailString(q, 'uid'), cell: detailString(q, 'ref')),
                ),
              ],
          ]),
        ]),
      );
    }
    out.addAll(detailKinLines(p, open: _open, here: uid));
    out.addAll(detailPersonGroupsLines(p, open: _open));
    return out;
  }

  /// `사람:` — 칸에 적은 사람(인물)이 '같은 이름의 인물'과 다를 때만(웹: n.figure !== figureOfLeader).
  List<Widget> _figureLine(CellRef ref, Map<String, dynamic> p) {
    final f = p['figure'];
    if (f is! Map || '${f['uid'] ?? ''}'.isEmpty) return const [];
    final fig = f.cast<String, dynamic>();
    final twin = _byCell('x_leaderFigures', ref.ref);
    if (ref.kind == 'leader' && twin != null && detailString(twin, 'uid') == detailString(fig, 'uid')) return const [];
    final role = detailString(fig, 'role');
    return [
      DetailLine([
        const DetailBit('사람: '),
        DetailBit.link('${detailString(fig, 'name')}${role.isEmpty ? '' : ' · $role'}', () => _open(detailString(fig, 'uid'), kind: 'figure')),
      ]),
    ];
  }

  /// 한 사람의 창(건의 8의 6-가 — 목업 '후'): `사람:` → 묶음 '자리 N'(자리마다 나라 · 대수 · 기간 · 자리 이음, 누른 자리에 왼쪽 먹 줄 ·
  /// 누르면 그 칸으로) → 겹친 기간 → 묶음 '가족'(혈연 줄) → 속한 단체. 어느 나라의 칸을 눌러도 같은 꼴의 창이 선다.
  List<Widget> _seatLines(CellRef ref, Map<String, dynamic> p) {
    final seats = _seats ?? _roughSeats(ref);
    final kin = detailKinLines(p, open: _open, here: uid);
    return [
      ..._figureLine(ref, p),
      DetailBox(
        title: '자리',
        small: '${seats.length}',
        children: [
          _SeatList(seats, open: (s) => _open(s.uid, cell: s.ref)),
          ?_OverlapLine.of(seats),
        ],
      ),
      if (kin.isNotEmpty) DetailBox(title: '가족', children: kin),
      ...detailPersonGroupsLines(p, open: _open),
    ];
  }

  /// 자리 이음 한 줄 — `앞 지도자 〈이름〉의 **동생** · 찬탈`(앞 지도자와 관계를 알 때), 아니면 조각마다 ` · `.
  /// 칸에 `accession`을 적었을 때만(웹과 같다 — 미리 푼 `x_lineage`는 모든 지도자에게 있을 수 있다).
  List<Widget>? _lineageLine(CellRef ref) {
    final bits = _lineageBits(x, ref, uid);
    return bits == null ? null : [DetailLine(bits)];
  }

  /// 자리 이음의 조각 — 나라 [e]의 칸 [ref]. [here]는 그 나라 uid(같은 나라의 앞 지도자는 나라 이름 없이).
  /// [seat]이면 한 사람의 창의 자리 줄 꼴(목업 '후' — `앞 셋째 임금의 동생 · 찬탈`: '지도자' · 메모 없이).
  List<DetailBit>? _lineageBits(Map<String, dynamic> e, CellRef ref, String here, {bool seat = false}) {
    if (ref.kind != 'leader' || ref.cell['accession'] == null) return null;
    final table = e['x_lineage'];
    final row = table is Map ? table[ref.ref] : null;
    final a = row is Map ? row.cast<String, dynamic>() : null;
    if (a == null) return null;
    bool on(String k) => a[k] == 1 || a[k] == true;
    final fromRing = a['from'] is Map ? (a['from'] as Map).cast<String, dynamic>() : null;
    final from = on('fromUnknown')
        ? const [DetailBit('앞 지도자 미상')]
        : fromRing != null
        ? [DetailBit(seat ? '앞 ' : '앞 지도자 '), ...DetailPersonRing.bitsOf(fromRing, open: _open, here: here)]
        : const <DetailBit>[];
    final kinText = detailString(a, 'kin');
    final kin = kinText.isNotEmpty ? [DetailBit.bold(kinText)] : (on('kinUnknown') ? const [DetailBit('관계 미상')] : const <DetailBit>[]);
    final howText = detailString(a, 'how');
    final how = howText.isNotEmpty ? [DetailBit(howText)] : (on('howUnknown') ? const [DetailBit('오른 방식 미상')] : const <DetailBit>[]);
    final parts = fromRing != null && !on('fromUnknown') && kinText.isNotEmpty ? [[...from, const DetailBit('의 '), ...kin], how] : [from, kin, how];
    final bits = detailJoin(parts);
    if (bits.isEmpty) return null;
    final note = seat ? '' : detailString(a, 'note');
    return [...bits, if (note.isNotEmpty) ...[const DetailBit(' '), DetailBit.small(note)]];
  }

  // ── ㈐ 시기 창 ────────────────────────────────────────────────────────────────────────────

  List<Widget> _phaseBody(CellRef ref) {
    final c = ref.cell;
    final scheme = detailString(c, 'scheme');
    final group = _schemeOf(c);
    final note = group == null ? '' : detailString(group, 'note');
    final whence = _phaseWhence(ref);
    return [
      DetailTitle(detailString(c, 'name')),
      if (scheme.isNotEmpty) DetailAka('체계 $scheme${note.isEmpty ? '' : ' — $note'}') else if (note.isNotEmpty) DetailAka(note),
      DetailWhen(_phaseWhen(c), sub: whence.isEmpty ? null : whence),
      ..._rangeNotes(c),
      _memo(detailString(c, 'note')),
      ..._alternatives(c, placedSpan(x, c)),
      _nav(ref),
      _phaseCompare(ref),
      _echoSlot(_ownEvents()),
    ];
  }

  Map<String, dynamic>? _schemeOf(Map<String, dynamic> span) {
    final si = (detailNum(span, 'si') ?? 0).toInt();
    for (final g in detailList(x, 'phaseSchemes')) {
      if ((detailNum(g, 'si') ?? 0).toInt() == si) return g;
    }
    return null;
  }

  /// 시기 하나의 기간 글(`HT.phaseRangeText`) — 양쪽을 늘 적는다.
  String _phaseWhen(Map<String, dynamic> c) {
    String side(String key) {
      if (c['${key}Unknown'] == true) return '미정';
      if (key == 'end' && cellToNow(x, c)) return '현재';
      final at = detailString(c, '${key}At');
      return whenText(detailNum(c, key)?.toDouble(), at: at.isEmpty ? null : at);
    }

    return '${side('start')} ~ ${side('end')}';
  }

  /// 비운 경계가 어디서 왔는지 · 미정이 연표의 어디에 놓였는지(명세 ㈐).
  String _phaseWhence(CellRef ref) {
    final c = ref.cell;
    final last = ref.index == ref.list.length - 1;
    final start = detailNum(c, 'start')?.toDouble();
    final end = detailNum(c, 'end')?.toDouble();
    final guess = c['guess'] == true;
    return [
      if (c['startAuto'] == true && c['startUnknown'] != true) (ref.index == 0 ? '시작은 정권 시작' : '시작은 앞 시기의 끝'),
      if (c['endAuto'] == true && c['endUnknown'] != true) (last ? '끝은 정권 끝' : '끝은 다음 시기의 시작'),
      if (guess) '앞뒤 경계를 알 수 없어 그 사이를 고르게 나눠 자리만 잡음',
      if (c['startUnknown'] == true && !guess) '시작 미정 — 연표에는 ${whenText(start)} 무렵부터 놓았습니다',
      if (c['endUnknown'] == true && !guess) '끝 미정 — 연표에는 ${endText(end, now: _nowT)} 무렵까지 놓았습니다',
    ].join(' · ');
  }

  /// 체계 견주기 — 체계마다 한 줄, 같은 시간 축(명세 ㈐).
  Widget _phaseCompare(CellRef ref) {
    final schemes = detailList(x, 'phaseSchemes');
    if (schemes.isEmpty) return const SizedBox.shrink();
    return DetailBox(
      title: schemes.length > 1 ? '체계 견주기' : '시기 한눈에',
      small: schemes.length > 1 ? '${schemes.length}' : null,
      children: [
        _PhaseCompare(
          schemes: schemes,
          current: ref.cell,
          polityStart: detailNum(x, 'start')?.toDouble(),
          polityEnd: (detailNum(x, 'endY') ?? detailNum(x, 'end'))?.toDouble(),
          onTap: (span) => _goCell('phase:${(detailNum(span, 'ci') ?? 0).toInt()}'),
        ),
      ],
    );
  }

  // ── ㈑ 지위 창 ────────────────────────────────────────────────────────────────────────────

  List<Widget> _rankBody(CellRef ref) {
    final c = ref.cell;
    final sp = placedSpan(x, c);
    final def = c['def'] is Map ? (c['def'] as Map).cast<String, dynamic>() : null;
    final level = (detailNum(c, 'level') ?? 0).toInt();
    final whence = _rankWhence(ref, sp);
    final description = def == null ? '' : detailString(def, 'description');
    return [
      _RankTitle(name: detailString(c, 'name'), swatch: _rankSwatch(level), edge: color),
      DetailAka('${_tierLine(c, def, level)}${description.isEmpty ? '' : ' — $description'}'),
      DetailWhen(
        rangeText(start: sp.start, startAt: sp.startAt, end: sp.end, endAt: sp.endAt, startUnknown: sp.startUnknown, endUnknown: sp.endUnknown, ongoing: sp.ongoing),
        sub: whence.isEmpty ? null : whence,
      ),
      ..._rangeNotes(c),
      _memo(detailString(c, 'note')),
      ..._alternatives(c, sp),
      _nav(ref),
      // 지위 창에는 '이 시기의 사건' 목록이 없다(지금 연표의 rankDetailHTML 그대로) — 연표 쪽 강조는 칸 창과 같다.
      _echoSlot([_rankList(ref), _rankLeaders(ref)]),
    ];
  }

  /// 서열 설명 한 줄.
  String _tierLine(Map<String, dynamic> c, Map<String, dynamic>? def, int level) {
    if (def == null) return '사전에 없는 지위 — 서열 없이 중립 색으로 그립니다';
    final tier = detailNum(c, 'tier');
    final head = tier == null ? '서열 밖' : '서열 ${_plainNumber(tier)}';
    final mix = level > 0 ? ' · 짙기 $level단계(넷 중)' : ' · 중립 색';
    final alias = detailString(def, 'name') != detailString(c, 'name') ? ' · 사전의 "${detailString(def, 'name')}"과(와) 같은 서열로 봄' : '';
    return '$head$mix$alias';
  }

  String _rankWhence(CellRef ref, CellSpan sp) {
    final c = ref.cell;
    final last = ref.index == ref.list.length - 1;
    return [
      if (c['derived'] == true) '지도자에게 적힌 지위에서 끌어냄',
      if (c['startAuto'] == true && c['startUnknown'] != true) '시작은 정권 시작',
      if (c['endAuto'] == true && c['derived'] != true && c['endUnknown'] != true) (last ? '끝은 정권 끝' : '끝은 다음 지위의 시작'),
      if (c['startUnknown'] == true) '시작 미정 — 연표에는 ${whenText(sp.start)} 무렵부터 놓았습니다',
      if (c['endUnknown'] == true) '끝 미정 — 연표에는 ${endText(sp.end, now: _nowT)} 무렵까지 놓았습니다',
    ].join(' · ');
  }

  Color _rankSwatch(int level) => Color.lerp(Ui.bg, color, rankMix[level.clamp(0, rankMix.length - 1)] / 100)!;

  /// 지위 변천 — 전체 목록, 지금 것은 진하게.
  Widget _rankList(CellRef ref) {
    final list = ref.list;
    return DetailBox(
      title: '지위 변천',
      small: '${list.length}',
      children: [
        DetailCellList(single: true, [
          for (int j = 0; j < list.length; j++)
            DetailCellTile(
              year: _rankWhen(list[j]),
              name: detailString(list[j], 'name'),
              swatch: _rankSwatch((detailNum(list[j], 'level') ?? 0).toInt()),
              mark: _rankMove(list, j),
              markColor: _rankUp(list, j) ? DetailUi.ok : DetailUi.warn,
              current: j == ref.index,
              sub: detailString(list[j], 'note').isEmpty ? null : detailString(list[j], 'note'),
              onTap: () => _goCell('rank:$j'),
            ),
        ]),
      ],
    );
  }

  String _rankWhen(Map<String, dynamic> c) {
    final startAt = detailString(c, 'startAt'), endAt = detailString(c, 'endAt');
    return rangeText(
      start: detailNum(c, 'start')?.toDouble(),
      startAt: startAt.isEmpty ? null : startAt,
      end: detailNum(c, 'end')?.toDouble(),
      endAt: endAt.isEmpty ? null : endAt,
      startUnknown: c['startUnknown'] == true,
      endUnknown: c['endUnknown'] == true,
      ongoing: cellToNow(x, c),
    );
  }

  /// 앞 지위 → 이 지위: 승격 ▲ · 격하 ▼(두 서열을 다 알 때만).
  String? _rankMove(List<Map<String, dynamic>> list, int j) {
    if (j == 0) return null;
    final before = detailNum(list[j - 1], 'tier'), now = detailNum(list[j], 'tier');
    if (before == null || now == null || before == now) return null;
    return now > before ? '▲ 승격' : '▼ 격하';
  }

  bool _rankUp(List<Map<String, dynamic>> list, int j) {
    if (j == 0) return false;
    final before = detailNum(list[j - 1], 'tier'), now = detailNum(list[j], 'tier');
    return before != null && now != null && now > before;
  }

  /// 이 지위의 지도자 — 그 기간에 겹치는 지도자 칸.
  Widget _rankLeaders(CellRef ref) {
    final c = ref.cell;
    final sp = placedSpan(x, c);
    final start = sp.start ?? 0, end = sp.end ?? start;
    final polityEnd = (detailNum(x, 'endY') ?? detailNum(x, 'end'))?.toDouble();
    final leaders = detailList(x, 'leaders');
    final hits = <int>[];
    for (int i = 0; i < leaders.length; i++) {
      final s = detailNum(leaders[i], 'start')?.toDouble();
      if (s == null) continue;
      final e = (detailNum(leaders[i], 'end'))?.toDouble() ?? polityEnd ?? s;
      if ((s < end || (end == start && s == start)) && e > start) hits.add(i);
    }
    return DetailBox(
      title: '이 지위의 지도자',
      small: '${hits.length}',
      children: [
        if (hits.isEmpty)
          const Text('이 기간의 지도자가 적혀 있지 않습니다.', style: TextStyle(fontSize: 13, height: 1.6, color: Ui.text3))
        else
          DetailCellList(leaders: true, [
            for (final i in hits)
              DetailCellTile(
                year: _rankWhen(leaders[i]),
                name: _cellName(CellRef(kind: 'leader', index: i, cell: leaders[i], list: leaders, ref: 'leader:$i')),
                sub: _leaderSub(leaders[i], detailString(c, 'name')),
                leaders: true,
                onTap: () => _goCell('leader:$i'),
              ),
          ]),
      ],
    );
  }

  String? _leaderSub(Map<String, dynamic> c, String rankName) {
    final ordinal = detailNum(c, 'ordinal');
    final rank = detailString(c, 'rank');
    final bits = [
      if (ordinal != null) '${_plainNumber(ordinal)}대' else if (c['ordinalUnknown'] == true) '대수 미상',
      if (rank.isNotEmpty && rank != rankName) '지위 $rank',
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  // ── 셋이 함께 쓰는 묶음 ───────────────────────────────────────────────────────────────────

  /// 메모 — 비어 있으면 "메모가 없습니다."(설명이 아니라 메모다).
  Widget _memo(String note) => note.isEmpty
      ? const Text('메모가 없습니다.', style: TextStyle(fontSize: 14, height: 1.75, color: Ui.text3, fontStyle: FontStyle.italic))
      : DetailDesc(note);

  /// 미정 안내 — 모르는 쪽이 연표의 어디에 놓였는지.
  List<Widget> _unknownNote(CellSpan sp) {
    if (sp.startUnknown && sp.endUnknown) {
      return [DetailRangeNote('시작 · 끝 미정 — 연표에는 ${whenText(sp.start)} ~ ${endText(sp.end, now: _nowT)} 무렵에 놓았습니다')];
    }
    if (sp.startUnknown) return [DetailRangeNote(cellUnknownStartNote(sp.start, at: sp.startAt))];
    if (sp.endUnknown) return [DetailRangeNote(cellUnknownEndNote(sp.end, at: sp.endAt, now: _nowT))];
    return const [];
  }

  /// 연대 폭 안내 — `시작 — 이르면 …, 늦으면 …`.
  List<Widget> _rangeNotes(Map<String, dynamic> cell) {
    final out = <Widget>[];
    for (final pair in const [('시작', 'startRange'), ('끝', 'endRange')]) {
      final v = cell[pair.$2];
      if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
        out.add(DetailRangeNote(rangeNote(pair.$1, (v[0] as num).toDouble(), (v[1] as num).toDouble())));
      }
    }
    return out;
  }

  /// 다른 견해 — 첫 줄은 이 연표가 쓰는 연대, 그 아래는 비운 쪽을 통설로 채운 이설.
  List<Widget> _alternatives(Map<String, dynamic> cell, CellSpan base) {
    final alts = detailList(cell, 'alternatives');
    if (alts.isEmpty) return const [];
    final baseAt = !base.startUnknown && base.start != null
        ? base.start
        : (!base.endUnknown && !base.ongoing && base.end != null ? base.end : null);
    return [
      DetailBox(
        title: '다른 견해',
        children: [
          DetailAltList([
            DetailAltRow(
              when: rangeText(
                start: base.start,
                startAt: base.startAt,
                end: base.end,
                endAt: base.endAt,
                startUnknown: base.startUnknown,
                endUnknown: base.endUnknown,
                ongoing: base.ongoing,
              ),
              why: '이 연표가 쓰는 연대',
              main: true,
              onTap: baseAt == null ? null : () => _goYear(baseAt),
            ),
            for (final a in alts) _altRow(a, base),
          ]),
        ],
      ),
    ];
  }

  Widget _altRow(Map<String, dynamic> a, CellSpan base) {
    final ownStart = a['start'] != null || a['startUnknown'] == true;
    final ownEnd = a['end'] != null || a['endUnknown'] == true || a['ongoing'] == true;
    final start = ownStart ? detailNum(a, 'start')?.toDouble() : base.start;
    final end = ownEnd ? detailNum(a, 'end')?.toDouble() : base.end;
    final startUnknown = ownStart ? a['startUnknown'] == true : base.startUnknown;
    final endUnknown = ownEnd ? a['endUnknown'] == true : base.endUnknown;
    final ongoing = ownEnd ? a['ongoing'] == true : base.ongoing;
    // 한쪽만 적은 이설의 빈 쪽을 통설로 채우니 앞뒤가 뒤집히면 연표에 그리지 않는다.
    final flipped = start != null && end != null && end < start && !endUnknown && !ongoing;
    final dated = start != null || end != null || startUnknown || endUnknown;
    final go = flipped ? null : (ownStart && start != null ? start : (ownEnd && end != null ? end : null));
    final label = detailString(a, 'label');
    final source = detailString(a, 'source');
    final note = detailString(a, 'note');
    return DetailAltRow(
      when: dated ? rangeText(start: start, end: end, startUnknown: startUnknown, endUnknown: endUnknown, ongoing: ongoing) : '',
      why: source.isEmpty ? label : '$label · $source',
      note: flipped ? '비운 쪽을 이 연표의 연대로 채우면 앞뒤가 뒤집혀 연표에는 그리지 않습니다' : (note.isEmpty ? null : note),
      onTap: go == null ? null : () => _goYear(go),
    );
  }

  /// 앞뒤 칸 넘기기 — 각각 창 폭의 48%까지, 넘으면 말줄임.
  Widget _nav(CellRef ref) {
    final prev = ref.refAt(ref.index - 1), next = ref.refAt(ref.index + 1);
    if (prev == null && next == null) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text);
    String name(int i) => ref.kind == 'leader'
        ? _cellName(CellRef(kind: 'leader', index: i, cell: ref.list[i], list: ref.list, ref: ref.refAt(i) ?? ''))
        : detailString(ref.list[i], 'name');
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final cap = (box.maxWidth.isFinite ? box.maxWidth * .48 : 160.0) - 22 - 14;
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (prev != null)
                DetailSmallButton('◀ ${_fit(name(ref.index - 1), cap, style, scaler)}', onTap: () => _goCell(prev))
              else
                const SizedBox.shrink(),
              if (next != null)
                DetailSmallButton('${_fit(name(ref.index + 1), cap, style, scaler)} ▶', onTap: () => _goCell(next))
              else
                const SizedBox.shrink(),
            ],
          ),
        );
      },
    );
  }

  /// 메아리 자리 — '같은 시기를 타국에도' 스위치와 '같은 시기 타국' 묶음. [between]은 그 사이에 드는 것
  /// (칸 · 시기 창은 '이 시기의 사건', 지위 창은 지위 목록 둘 — 지금 연표의 차례 그대로).
  /// 칸 · 시기 · 지위 창은 `always`라 메아리를 끄고도 그 시기의 사건을 강조한다(명세 3-4).
  Widget _echoSlot(List<Widget> between) => EchoSlot(bus: widget.bus, spots: _spots(), always: true, between: between, color: color, onOpen: _open);

  /// 이 시기의 사건 — 칸이 품는 구간 `[lo, hi)`에 걸친 사건(숨은 소속의 것에는 꼬리표).
  List<Widget> _ownEvents() {
    final rows = _events;
    if (rows == null) return const [];
    return [
      DetailBox(
        title: '이 시기의 사건',
        small: '${rows.length}',
        children: [
          if (rows.isEmpty)
            const Text('이 시기의 사건이 없습니다.', style: TextStyle(fontSize: 13, height: 1.6, color: Ui.text3))
          else
            DetailYearEvents([for (final e in rows) _eventRow(e)]),
        ],
      ),
    ];
  }

  DetailYearRow _eventRow(Map<String, dynamic> e) {
    final member = detailString(e, 'member');
    return DetailYearRow(
      color: detailColor(e['color'], color),
      when: _eventWhen(e),
      title: detailString(e, 'title'),
      tail: member.isEmpty ? null : '소속 · $member',
      diamond: e['treaty'] == true,
      onTap: () => _open(detailString(e, 'uid')),
    );
  }

  /// 사건 한 줄의 날짜 글 — 자료 처리부가 `when`을 주면 그대로, 아니면 분에서 셈한다.
  String _eventWhen(Map<String, dynamic> e) {
    final when = detailString(e, 'when');
    if (when.isNotEmpty) return when;
    final start = detailNum(e, 'start')?.toDouble();
    if (start == null) return '';
    final end = detailNum(e, 'end')?.toDouble();
    return rangeText(start: tOfMinutes(start), end: end == null || end == start ? null : tOfMinutes(end));
  }

  /// 이 시기의 인물 — 활동 기록이 칸이 품는 구간과 겹치는 사람(`x_served` · [spanMeets]).
  List<Widget> _cellFigures() {
    final bounds = cellBoundsOf(x, widget.cell);
    if (bounds == null) return const [];
    final hits = <Map<String, dynamic>>[];
    for (final row in detailList(x, 'x_served')) {
      final span = row['span'];
      if (span is! List || span.length < 2 || span[0] is! num || span[1] is! num) continue;
      if (spanMeets((span[0] as num).toDouble(), (span[1] as num).toDouble(), bounds.lo, bounds.hi)) hits.add(row);
    }
    if (hits.isEmpty) return const [];
    return [
      DetailBox(
        title: '이 시기의 인물',
        small: '${hits.length}',
        children: [
          DetailSuccList([
            for (final f in hits)
              DetailSuccRow(
                badge: detailString(f, 'role').isEmpty ? null : detailString(f, 'role'),
                name: detailString(f, 'name'),
                trailing: detailString(f, 'office').isEmpty ? null : detailString(f, 'office'),
                years: detailString(f, 'when'),
                onTap: () => _open(detailString(f, 'uid'), kind: 'figure'),
              ),
          ]),
        ],
      ),
    ];
  }
}

/// 오늘의 해 좌표 — 진행 중인 항목의 끝을 `현재`로 적을 때만 쓴다(`HT.NOW_T`).
double get _nowT => tOfMinutes(DateTime.now().toUtc().millisecondsSinceEpoch / 60000);

/// 들 폭에 맞게 글을 줄인다(css의 `text-overflow: ellipsis`).
String _fit(String text, double max, TextStyle style, TextScaler scaler) {
  if (text.isEmpty || max <= 0) return text;
  if (measureText(text, style, scaler: scaler) <= max) return text;
  int lo = 0, hi = text.length;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (measureText('${text.substring(0, mid)}…', style, scaler: scaler) <= max) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo <= 0 ? '…' : '${text.substring(0, lo)}…';
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 지위 창의 제목 — [짙기 견본]이름
// ────────────────────────────────────────────────────────────────────────────────────────────

class _RankTitle extends StatelessWidget {
  const _RankTitle({required this.name, required this.swatch, required this.edge});
  final String name;
  final Color swatch, edge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 12,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: swatch,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: edge.withValues(alpha: .55)),
          ),
        ),
        Flexible(child: Text(name, style: DetailTitle.style)),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 체계 견주기 — 체계마다 한 줄, 같은 시간 축(명세 ㈐ · css/viewer.css:500~518)
// ────────────────────────────────────────────────────────────────────────────────────────────

class _PhaseCompare extends StatelessWidget {
  const _PhaseCompare({required this.schemes, required this.current, required this.onTap, this.polityStart, this.polityEnd});

  final List<Map<String, dynamic>> schemes;
  final Map<String, dynamic> current;
  final double? polityStart, polityEnd;
  final void Function(Map<String, dynamic> span) onTap;

  static const trackHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final all = [for (final g in schemes) ...detailList(g, 'spans')];
    if (all.isEmpty) return const SizedBox.shrink();
    double t0 = polityStart ?? double.infinity, t1 = polityEnd ?? double.negativeInfinity;
    for (final c in all) {
      final s = detailNum(c, 'start')?.toDouble(), e = detailNum(c, 'end')?.toDouble();
      if (s != null) t0 = math.min(t0, s);
      if (e != null) t1 = math.max(t1, e);
      if (s != null) t1 = math.max(t1, s);
    }
    if (!t0.isFinite || !t1.isFinite) return const SizedBox.shrink();
    final span = t1 - t0;
    double pct(double t) => span > 0 ? ((t - t0) / span).clamp(0.0, 1.0) : 0;
    final curSi = (detailNum(current, 'si') ?? 0).toInt();

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 320.0;
        final scaler = MediaQuery.textScalerOf(context);
        final rows = <Widget>[];
        for (final g in schemes) {
          final spans = detailList(g, 'spans');
          final name = detailString(g, 'scheme');
          final mine = (detailNum(g, 'si') ?? 0).toInt() == curSi;
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (schemes.length > 1 || name.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        name.isEmpty ? '이름 없는 체계' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, height: 1.5, color: mine ? Ui.text2 : Ui.text3, fontWeight: mine ? FontWeight.w600 : FontWeight.w400),
                      ),
                    ),
                  SizedBox(
                    height: trackHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Ui.text3.withValues(alpha: Ui.text3.a * .09), borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                        for (final c in spans) ..._bar(c, pct, width, scaler),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final guides = [
          for (final key in const ['start', 'end'])
            if (detailNum(current, key) != null) pct(detailNum(current, key)!.toDouble()) * width,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
                Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GuidePainter(guides)))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(whenText(t0), style: _axisStyle),
                  Text(whenText(t1), style: _axisStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static const _axisStyle = TextStyle(fontSize: 11, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);

  List<Widget> _bar(Map<String, dynamic> c, double Function(double) pct, double width, TextScaler scaler) {
    final s = detailNum(c, 'start')?.toDouble();
    if (s == null) return const [];
    final e = detailNum(c, 'end')?.toDouble() ?? s;
    final left = pct(s) * width;
    final w = math.max(3.0, pct(e) * width - left);
    final cur = identical(c, current) || ((detailNum(c, 'ci') ?? -1) == (detailNum(current, 'ci') ?? -2));
    final name = detailString(c, 'name');
    // 이름이 다 들어가지 않으면 이름을 감춘다(css의 is-bare — 글자가 잘리거나 겹치지 않게).
    final bare = measureText(name, _PhaseBar.labelStyle, scaler: scaler) + 8 > w;
    return [
      Positioned(
        left: left,
        width: w,
        top: 0,
        bottom: 0,
        child: _PhaseBar(
          label: bare ? '' : name,
          current: cur,
          startUnknown: c['startUnknown'] == true,
          endUnknown: c['endUnknown'] == true,
          tooltip: '${detailString(c, 'scheme').isEmpty ? '' : '${detailString(c, 'scheme')} · '}$name',
          onTap: () => onTap(c),
        ),
      ),
    ];
  }
}

/// 견주기 막대 하나. 미정인 쪽 변은 css에서 파선이라 그쪽 세로 변만 점선으로 그린다
/// (Flutter의 `Border`는 파선을 그리지 못하고, 둥근 모서리에는 변마다 다른 테두리를 둘 수도 없어 손으로 그린다).
class _PhaseBar extends StatefulWidget {
  const _PhaseBar({required this.label, required this.current, required this.startUnknown, required this.endUnknown, required this.tooltip, required this.onTap});
  final String label, tooltip;
  final bool current, startUnknown, endUnknown;
  final VoidCallback onTap;

  static const labelStyle = TextStyle(fontSize: 11, height: 18 / 11, fontWeight: FontWeight.w500, color: Ui.text2);

  @override
  State<_PhaseBar> createState() => _PhaseBarState();
}

class _PhaseBarState extends State<_PhaseBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final edge = widget.current ? Ui.text2 : (_hover ? Ui.text3 : Ui.text3.withValues(alpha: Ui.text3.a * .45));
    final background = widget.current
        ? Color.alphaBlend(Ui.text2.withValues(alpha: Ui.text2.a * .16), Ui.surface)
        : (_hover ? Color.alphaBlend(Ui.accentSoft, Ui.surface) : Ui.surface);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Tooltip(
            message: widget.tooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: CustomPaint(
              painter: _BarPainter(background: background, edge: edge, startUnknown: widget.startUnknown, endUnknown: widget.endUnknown),
              child: Center(
                child: widget.label.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: widget.current
                              ? _PhaseBar.labelStyle.copyWith(fontWeight: FontWeight.w700, color: Ui.text)
                              : _PhaseBar.labelStyle,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 막대의 바탕과 테두리 — 미정인 세로 변은 점선(그 자리에 바탕색 틈을 둔다).
class _BarPainter extends CustomPainter {
  const _BarPainter({required this.background, required this.edge, required this.startUnknown, required this.endUnknown});
  final Color background, edge;
  final bool startUnknown, endUnknown;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(box, Paint()..color = background);
    canvas.drawRRect(
      box.deflate(.5),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final gap = Paint()
      ..color = background
      ..strokeWidth = 1;
    for (final side in [if (startUnknown) .5, if (endUnknown) size.width - .5]) {
      for (double y = 5; y < size.height - 4; y += 4) {
        canvas.drawLine(Offset(side, y), Offset(side, math.min(y + 2, size.height - 4)), gap);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.background != background || old.edge != edge || old.startUnknown != startUnknown || old.endUnknown != endUnknown;
}

/// 지금 시기의 두 경계에 서는 가는 세로 점선.
class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.xs);
  final List<double> xs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Ui.text2.withValues(alpha: Ui.text2.a * .55)
      ..strokeWidth = 1;
    for (final x in xs) {
      for (double y = 0; y < size.height; y += 5) {
        canvas.drawLine(Offset(x + .5, y), Offset(x + .5, math.min(y + 3, size.height)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.xs.length != xs.length || !old.xs.every(xs.contains);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  한 사람의 창의 자리(건의 8의 6-가 · 2026-10-13 감독 선택 '후')
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 같은 사람이 앉은 자리 하나 — 나라의 지도자 · 내각 칸.
class _Seat {
  const _Seat({
    required this.uid,
    required this.ref,
    required this.polity,
    required this.color,
    required this.tag,
    required this.years,
    this.start,
    this.end,
    this.span,
    this.lineage = const [],
    this.here = false,
  });

  /// 기록을 받기 전(또는 못 받은) 자리 — 칸 기록의 `others` 한 줄(나라 이름 · 기간 글)만으로.
  factory _Seat.rough(Map<String, dynamic> q) => _Seat(
    uid: detailString(q, 'uid'),
    ref: detailString(q, 'ref'),
    polity: detailString(q, 'polity'),
    color: Ui.ink20,
    tag: '',
    years: detailString(q, 'when'),
  );

  /// 나라 uid · 칸 참조 · 나라 이름 · 나라 색.
  final String uid, ref, polity;
  final Color color;

  /// `지도자 · 4대` · 오른쪽 끝의 기간 글(`1455 ~ 1480`).
  final String tag, years;

  /// 겹친 기간 · 막대가 쓰는 시작 · 끝(서력 해 수 — 진행 중이면 올해). 모르면 null.
  final double? start, end;

  /// 합친 기간의 글(날짜 글 · 미정 · 현재)을 짓는 칸의 기간. 기록을 못 받았으면 null.
  final CellSpan? span;

  /// 자리 이음 조각(`앞 셋째 임금의 동생 · 찬탈`) — 없으면 빈 목록.
  final List<DetailBit> lineage;

  /// 이 창을 연 칸(왼쪽 먹 줄 · 누를 수 없다).
  final bool here;
}

/// '자리' 묶음의 상자 — 둥근 8 · 1px 선 테, 자리 사이 1px 선.
class _SeatList extends StatelessWidget {
  const _SeatList(this.seats, {required this.open});
  final List<_Seat> seats;
  final void Function(_Seat seat) open;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Ui.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < seats.length; i++) ...[
            if (i > 0) const SizedBox(height: 1, child: ColoredBox(color: Ui.line)),
            _SeatRow(seats[i], onTap: seats[i].here || seats[i].uid.isEmpty ? null : () => open(seats[i])),
          ],
        ],
      ),
    ),
  );
}

/// 자리 한 줄: `● 나라 지도자 · 4대 …… 1455 ~ 1480` + 자리 이음. 이 창의 자리는 왼쪽 3px 먹 줄 · 옅은 바탕(목업의 246).
class _SeatRow extends StatelessWidget {
  const _SeatRow(this.seat, {this.onTap});
  final _Seat seat;
  final VoidCallback? onTap;

  /// 이 창의 자리 바탕 — 목업 그대로(먹 3.5% · 종이 위 246).
  static const _hereFill = Color(0x09000000);

  @override
  Widget build(BuildContext context) {
    final s = seat;
    final head = Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(
          flex: 0,
          child: Text(
            s.polity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, height: 20 / 13.5, fontWeight: FontWeight.w700, color: Ui.text),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(s.tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 20 / 11.5, color: Ui.text3)),
        ),
        const SizedBox(width: 8),
        Text(
          s.years,
          style: const TextStyle(fontSize: 12.5, height: 20 / 12.5, fontWeight: FontWeight.w600, color: Ui.text, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: s.here ? Ui.ink : const Color(0x00000000), width: 3)),
      ),
      child: DetailPressable(
        onTap: onTap,
        radius: 0,
        padding: EdgeInsets.fromLTRB(9, 8, 12, s.lineage.isEmpty ? 8 : 0),
        background: s.here ? _hereFill : null,
        semantics: '${s.polity} ${s.years}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            head,
            // 자리 이음 줄(글 12 · 먹 60% — 아래 여백 8은 줄이 가진다).
            if (s.lineage.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: DetailLine(s.lineage)),
          ],
        ),
      ),
    );
  }
}

/// 자리 상자 아래 한 줄 — `겹친 기간 1470 ~ 1480 · 10년`과 오른쪽의 자리마다 가는 막대(합친 기간 안의 비례 자리).
/// 둘 이상의 자리가 시간이 겹칠 때만 선다(복위처럼 겹치지 않으면 없다).
class _OverlapLine extends StatelessWidget {
  const _OverlapLine._(this.seats, this.lo, this.hi);
  final List<_Seat> seats;
  final double lo, hi;

  static _OverlapLine? of(List<_Seat> seats) {
    double? lo, hi;
    for (var i = 0; i < seats.length; i++) {
      for (var j = i + 1; j < seats.length; j++) {
        final a = seats[i], b = seats[j];
        if (a.start == null || a.end == null || b.start == null || b.end == null) continue;
        final s = math.max(a.start!, b.start!), e = math.min(a.end!, b.end!);
        if (e <= s) continue;
        lo = lo == null ? s : math.min(lo, s);
        hi = hi == null ? e : math.max(hi, e);
      }
    }
    return lo == null ? null : _OverlapLine._(seats, lo, hi!);
  }

  @override
  Widget build(BuildContext context) {
    int year(double t) => t == t.roundToDouble() ? t.round() : civilAt(t).year;
    String label(double t) => year(t) < 0 ? '기원전 ${-year(t)}' : '${year(t)}';
    final n = year(hi) - year(lo);
    final bars = [for (final s in seats) if (s.start != null && s.end != null) s];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '겹친 기간  '),
                TextSpan(
                  text: '${label(lo)} ~ ${label(hi)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Ui.text, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                if (n > 0) TextSpan(text: '  · $n년'),
              ],
            ),
            style: const TextStyle(fontSize: 12, height: 20 / 12, color: Ui.text3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: SizedBox(
                  width: double.infinity,
                  height: bars.length * 4.0 + (bars.length - 1) * 2.0,
                  child: CustomPaint(painter: _SeatBars(bars)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 자리마다 가는 막대(높이 4 · 둥근 2 · 나라 색) — 모든 자리를 합친 기간을 폭으로 삼는다.
class _SeatBars extends CustomPainter {
  const _SeatBars(this.seats);
  final List<_Seat> seats;

  @override
  void paint(Canvas canvas, Size size) {
    if (seats.isEmpty) return;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final s in seats) {
      lo = math.min(lo, s.start!);
      hi = math.max(hi, s.end!);
    }
    final span = math.max(hi - lo, 1e-9);
    for (var i = 0; i < seats.length; i++) {
      final s = seats[i];
      final l = (s.start! - lo) / span * size.width, r = (s.end! - lo) / span * size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(l, i * 6.0, math.max(r, l + 4), i * 6.0 + 4), const Radius.circular(2)),
        Paint()..color = s.color,
      );
    }
  }

  @override
  bool shouldRepaint(_SeatBars old) => old.seats != seats;
}
