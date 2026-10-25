import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';

import '../shell/look.dart';
import '../shell/search_results.dart';
import '../shell/sheet_parts.dart' show SheetTagKind;
import 'app_bus.dart';
import 'filter_query.dart';
import 'filter_state.dart';
import 'search_parse.dart';

// 찾기(명세 06의 5절). 입력을 [parseSearch]로 읽고, 자료 처리부에 물어 결과 목록을 만들고,
// 고르면 **창을 먼저 열고 그다음에 이동**한다(명세 ㈐-9 — 도착 자리가 창에 가려지지 않게).
// 이 부품은 [AppBus]만 받아서 혼자 선다: 자료는 bus.ask · 고르기는 bus.select · 가기는 bus.goTo ·
// 그 밖에 알릴 것은 bus.slot('searchHits' · 'yearPanel' · 'marker' · 'wiki')다.
//
// material의 SearchController(SearchAnchor의 것)와 이름이 겹치므로 이 파일은 그쪽을 hide 한다.
// 이 파일을 쓰는 쪽도 `import 'package:flutter/material.dart' hide SearchController;`로 들여야 한다.

/// 명세 5-2의 줄 색(0xRRGGBB) — 간지 줄은 `--warn`(앱 틀의 [Ui.warnRgb]), 날짜 줄은 `--accent`.
const _warnRgb = Ui.warnRgb, _accentRgb = 0xc27a45;

/// 결과 한 줄. 자료 처리부가 주는 꼴 그대로이고, 간지 · 날짜 줄만 화면이 지어 넣는다.
@immutable
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.name,
    this.uid = '',
    this.cell,
    this.sub = '',
    this.when = '',
    this.track = '',
    this.color = 0,
    this.start = 0,
    this.end = 0,
    this.row,
    this.eventId,
    this.prec = Prec.year,
    this.date,
    this.timeless = false,
  });

  /// 'event' · 'period' · 'figure' · 'epoch' · 'scope' · 'cell' · 'house' · 'doc'
  /// 와, 화면이 지어 넣는 'date'(맨 위 이동 줄) · 'ganji'.
  final String kind;

  /// 항목 기록(entities)의 열쇠. 칸 줄이면 그 **정권**의 uid다.
  final String uid;

  /// 칸 참조('leader:3' · 'era:2' · 'capital:0'). 칸 줄에만 있다.
  final String? cell;

  /// 이름과 그 뒤의 작은 글(`인물 · 탐험가 · 유리항 패총국`).
  final String name, sub;

  /// 오른쪽 끝에 서는 기간 글과 트랙 이름.
  final String when, track;

  /// 0xRRGGBB. 0이면 옅은 글자색으로 그린다.
  final int color;

  /// 분(1970-01-01 UTC 기준).
  final num start, end;

  /// 전체 줄 번호(없으면 null — 제 줄이 없는 항목).
  final int? row;

  /// 저장소의 events.id(알면).
  final int? eventId;
  final Prec prec;

  /// 날짜 · 간지 줄이 가리키는 때.
  final DateQuery? date;

  /// 기간이 없는 줄(엔진 답의 start · end가 null — D1의 계보 전용 인물처럼 띠에 그림이 없는 것).
  /// 고르면 창만 열고 연표를 옮기지 않으며, 같은 갈래 묶음 안에서 기간 있는 줄 뒤에 선다(웹 runSearch · 엔진 검색 차례와 같게).
  final bool timeless;

  /// 같은 줄인지 가리는 열쇠(칸은 정권 uid가 같아도 칸마다 다른 줄이다).
  String get key => '$kind|$uid|${cell ?? ''}|$start|$name';
}

// ---- 보이는 차례(검색 결과 시트의 짜임) ----

/// 검색 결과 시트의 갈래 상자 넷(차례대로) — 객체 · 칸 · 사건 · 조약 · 인물 · 문서(감독 고름 G5 #9 다듬기 판 `shs-search`).
const searchBoxLabels = ['객체', '칸', '사건 · 조약', '인물 · 문서'];

/// 줄 갈래 → 상자 차례([searchBoxLabels]). 날짜 · 간지 이동 줄은 −1(상자 밖 맨 위의 흰 종이 줄).
/// 객체 상자는 정권 · 시대 · 대범위 · 왕조 · 기관 · 문화 · 가문(과 그 밖의 띠 갈래)이다.
int searchBoxOf(String kind) => switch (kind) {
  'date' || 'ganji' => -1,
  'cell' => 1,
  'event' || 'treaty' => 2,
  'figure' || 'doc' => 3,
  _ => 0,
};

/// 칸 줄의 곁글(`〈정권 · 트랙 이름〉 〈칸 갈래〉` — 엔진 `cell_sub`, 뒤에 ` · 덧글`이 붙을 수도)에 서는 칸 갈래 이름. 긴 것부터 맞춘다.
const _cellKinds = ['시기 구분', '시대 구분', '지도자', '내각', '지위', '연호', '도읍', '배도', '왕조', '기관', '인물', '예속'];

/// 칸 줄의 주인 이름 · 칸 갈래 · 덧글을 곁글에서 가른다. 갈래를 못 찾으면 곁글 전체가 주인이다.
({String owner, String kind, String note}) searchCellOwner(SearchHit hit) {
  final sub = hit.sub;
  for (final kind in _cellKinds) {
    if (sub == kind) return (owner: '', kind: kind, note: '');
    if (sub.endsWith(' $kind')) return (owner: sub.substring(0, sub.length - kind.length - 1), kind: kind, note: '');
    final at = sub.indexOf(' $kind · ');
    if (at >= 0) return (owner: sub.substring(0, at), kind: kind, note: sub.substring(at + kind.length + 4));
  }
  return (owner: sub, kind: '', note: '');
}

/// 칸 상자 안의 주인 하나 — 같은 정권(uid · 없으면 주인 이름)의 칸 줄들(엔진 차례 그대로). [kind]는 그 칸들의 갈래를 차례대로 모은 것.
@immutable
class SearchCellGroup {
  const SearchCellGroup({required this.owner, required this.kind, required this.rows});
  final String owner, kind;
  final List<int> rows;
}

/// 갈래 상자 하나 — [rows]는 [SearchController.hits]의 번호(엔진 차례 그대로), 칸 상자면 [cells](주인마다 · 처음 나온 차례).
@immutable
class SearchBoxPlan {
  const SearchBoxPlan({required this.label, this.rows = const [], this.cells = const []});
  final String label;
  final List<int> rows;
  final List<SearchCellGroup> cells;

  /// 상자의 줄 수(칸은 칸마다).
  int get count => rows.length + cells.fold(0, (n, g) => n + g.rows.length);
}

/// 결과를 보이는 차례로 가른 것: 맨 위 이동 줄([lead]) → 상자 넷([boxes] — 빈 상자는 없음). [order]는 화면에 보이는 차례 그대로의
/// 번호 표 — 화살표 · Enter가 이것을 따른다(상자를 건너 위에서 아래로).
@immutable
class SearchLayout {
  const SearchLayout({this.lead = const [], this.boxes = const [], this.order = const []});

  factory SearchLayout.of(List<SearchHit> hits) {
    final lead = <int>[];
    final rows = List.generate(searchBoxLabels.length, (_) => <int>[]);
    for (var i = 0; i < hits.length; i++) {
      final box = searchBoxOf(hits[i].kind);
      if (box < 0) {
        lead.add(i);
      } else {
        rows[box].add(i);
      }
    }
    // 칸은 같은 정권끼리 주인 꼬리표 하나로 — 주인은 처음 나온 차례, 그 안은 엔진 차례.
    final groups = <String, ({String owner, List<String> kinds, List<int> rows})>{};
    for (final i in rows[1]) {
      final split = searchCellOwner(hits[i]);
      final key = hits[i].uid.isNotEmpty ? 'u|${hits[i].uid}' : 'o|${split.owner}';
      final g = groups.putIfAbsent(key, () => (owner: split.owner, kinds: <String>[], rows: <int>[]));
      if (split.kind.isNotEmpty && !g.kinds.contains(split.kind)) g.kinds.add(split.kind);
      g.rows.add(i);
    }
    final cells = [for (final g in groups.values) SearchCellGroup(owner: g.owner, kind: g.kinds.join(' · '), rows: List.unmodifiable(g.rows))];
    final boxes = <SearchBoxPlan>[
      for (var b = 0; b < searchBoxLabels.length; b++)
        if (rows[b].isNotEmpty)
          b == 1 ? SearchBoxPlan(label: searchBoxLabels[b], cells: cells) : SearchBoxPlan(label: searchBoxLabels[b], rows: List.unmodifiable(rows[b])),
    ];
    final order = <int>[
      ...lead,
      for (final box in boxes) ...[...box.rows, for (final g in box.cells) ...g.rows],
    ];
    return SearchLayout(lead: List.unmodifiable(lead), boxes: List.unmodifiable(boxes), order: List.unmodifiable(order));
  }

  final List<int> lead;
  final List<SearchBoxPlan> boxes;
  final List<int> order;
}

/// 검색의 머리: 입력을 읽고 · 물어보고 · 결과를 들고 있고 · 고르면 창과 이동을 건다.
/// 화면 없이도 돌아가므로 검사는 이것만 두드려도 된다.
class SearchController extends ChangeNotifier {
  SearchController({required this.bus, TextEditingController? text, this.limit = 60}) : text = text ?? TextEditingController(), _ownText = text == null;

  final AppBus bus;

  /// 검색 칸의 글. 앱 틀의 칸을 그대로 받아 쓸 수 있다.
  final TextEditingController text;
  final bool _ownText;

  /// 한 번에 보이는 결과의 수(명세 ㈐-14 — 60건까지).
  final int limit;

  SearchQuery _query = const SearchQuery.empty();
  List<SearchHit> _hits = const [];
  SearchLayout _layout = const SearchLayout();
  int _active = -1, _found = 0, _seq = 0;
  int? _total;
  bool _more = false, _closed = false;
  String _error = '';

  SearchQuery get query => _query;

  /// 그릴 줄들(엔진 차례). 맨 위 날짜 이동 줄이 있으면 그것까지 든다.
  List<SearchHit> get hits => _hits;

  /// 결과 시트의 짜임(맨 위 이동 줄 · 갈래 상자) — [hits]가 바뀔 때마다 다시 가른다.
  SearchLayout get layout => _layout;

  /// 화면에 보이는 차례대로의 [hits] 번호 — `↑ ↓` · `Enter`가 이 차례를 따른다.
  List<int> get order => _layout.order;

  /// `↑ ↓`로 짚은 줄 — [hits]의 번호(없으면 −1).
  int get activeIndex => _active;

  /// 찾은 수(폴더 탭의 수). 다 세지 못했으면(더 있음) 뒤에 '+'.
  String get countText => '$_found${_total == null && _more ? '+' : ''}';

  /// 안내 글이 '〈수〉건 찾음' 하나뿐인가 — 그 수는 폴더 탭에 서므로 시트는 안내 글을 따로 두지 않는다.
  bool get plainNote => note == '$_found건 찾음';

  /// 목록을 보일 때인가 — 검색어가 있고 아직 닫지 않았을 때.
  bool get showResults => !_closed && _query.raw.isNotEmpty;

  /// 목록 맨 위의 안내 글(명세 5-2).
  String get note {
    if (_error.isNotEmpty) return _error;
    final shown = _hits.where((h) => h.kind != 'date').length;
    final head = _found == 0
        ? '일치하는 항목이 없습니다'
        : _total != null
        ? '$_found건 찾음${_found > shown ? ' (앞의 $shown건만 표시)' : ''}'
        : _more
        ? '$_found건 넘게 찾음 (앞의 $shown건만 표시)'
        : '$_found건 찾음';
    return '$head'
        '${_query.ganji.isNotEmpty ? ' · ${_query.ganji}년은 60년마다 돌아옵니다. 보고 있는 시기에 가까운 해부터 보여 줍니다' : ''}'
        '${_filtered ? ' · 필터로 숨긴 항목은 검색되지 않습니다' : ''}';
  }

  /// 필터가 걸려 있는가 — 필터 담당이 `bus.slot('filters')`에 둔 값을 읽기만 한다.
  bool get _filtered {
    return _filter != null;
  }

  /// 물음에 싣는 거르개는 계약 2-2의 꼴(`{tracks_off: […], …}`)로 — 걸린 것이 없으면 싣지 않는다(앱 틀이 제 것을 싣는다).
  Map<String, dynamic>? get _filter {
    final value = bus.slot('filters').value;
    // 실재성의 '끔'은 지금 칩 줄에 보이는 것만 센다(명세 06 6-4) — 앱 틀이 그 목록을 이 슬롯에 둔다. 없으면 실재성은 거르지 않는다.
    final shown = bus.slot('shownHistoricity').value;
    return value is FilterState ? filterQueryOf(value, shownHistoricity: shown is Iterable<String> ? shown : null) : null;
  }

  /// 검색어가 바뀌었다. 늦게 온 답은 버린다(글을 빨리 치면 답이 뒤섞이지 않게).
  Future<void> setQuery(String input) async {
    final q = parseSearch(input);
    final seq = ++_seq;
    _query = q;
    _active = -1;
    _closed = false;
    _error = '';
    _total = null;
    _more = false;
    if (q.isEmpty) {
      _hits = const [];
      _layout = const SearchLayout();
      _found = 0;
      _publish(const []);
      notifyListeners();
      return;
    }
    notifyListeners(); // 글이 바뀐 것을 먼저 보인다 — 답은 뒤따라온다.

    final ganji = q.ganji.isEmpty ? const <SearchHit>[] : await _ganjiRows(q.ganji);
    if (seq != _seq) return;
    final found = <String, SearchHit>{};
    for (final hit in await _ask({'op': 'search', 'text': q.raw, 'kinds': q.kinds, 'limit': limit + 1, 'after': 0})) {
      found[hit.key] = hit;
    }
    if (seq != _seq) return;
    final date = q.date;
    if (date != null) {
      for (final hit in await _ask({'op': 'search_year', 't': date.t, 'end': date.end, 'kinds': q.kinds, 'limit': limit + 1, 'after': 0})) {
        found.putIfAbsent(hit.key, () => hit);
      }
      if (seq != _seq) return;
    }

    // 차례: 간지 해 → 항목(시작 오름차순) → 칸 → 하위 문서 → 가문(명세 5-1).
    final rest = found.values.toList()
      ..sort((a, b) {
        final byKind = _order(a.kind) - _order(b.kind);
        if (byKind != 0) return byKind;
        if (a.timeless != b.timeless) return a.timeless ? 1 : -1;
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.name.compareTo(b.name);
      });
    final all = [...ganji, ...rest];
    _more = _more || all.length > limit;
    _found = _total ?? all.length;
    final shown = all.length > limit ? all.sublist(0, limit) : all;
    _hits = [if (date != null) _dateRow(date), ...shown];
    _layout = SearchLayout.of(_hits);
    _publish(shown);
    notifyListeners();
  }

  static int _order(String kind) => switch (kind) {
    'cell' => 1,
    'doc' => 2,
    'house' => 3,
    _ => 0,
  };

  /// 검색 강조(명세 5-4): 항목 결과의 uid + 칸 결과의 정권 uid. 없으면 null로 두어 열린 창의 조명 강조가 되살아나게 한다.
  void _publish(List<SearchHit> shown) {
    final uids = <String>[];
    for (final hit in shown) {
      // 기간 없는 줄(계보 전용 인물)은 띠에 그림이 없어 강조에 넣지 않는다(웹과 같음).
      if (hit.uid.isEmpty || hit.timeless || hit.kind == 'doc' || hit.kind == 'house' || hit.kind == 'ganji' || hit.kind == 'date') continue;
      if (!uids.contains(hit.uid)) uids.add(hit.uid);
    }
    bus.slot('searchHits').value = uids.isEmpty ? null : uids;
  }

  Future<List<SearchHit>> _ask(Map<String, dynamic> request) async {
    final filter = _filter;
    final query = <String, dynamic>{...request};
    if (filter != null) query['filter'] = filter; // 필터로 숨긴 항목은 찾지 않는다(명세 ㈐-14).
    try {
      final answer = await bus.ask(query);
      final items = answer['items'];
      if (items is! List) return const [];
      final out = <SearchHit>[];
      for (final row in items) {
        if (row is Map) out.add(_hitOf(row));
      }
      if (answer['has_more'] == true) _more = true;
      // 'total'(통틀어 몇 건)은 있으면 쓰고 없으면 센 만큼만 적는다. 두 번 물었으면 큰 쪽을 쓴다(겹친 줄은 어차피 합쳐진다).
      final total = answer['total'];
      if (total is num && total.toInt() > (_total ?? 0)) _total = total.toInt();
      return out;
    } catch (error) {
      _error = '찾지 못했습니다 — $error';
      return const [];
    }
  }

  /// 간지에 해당하는 해들. 자료 처리부에 물어보고, 그 명령이 아직 없으면 연표의 범위로 여기서 센다.
  Future<List<SearchHit>> _ganjiRows(String ganji) async {
    final lo = yearAt(bus.controller.minMinute), hi = yearAt(bus.controller.maxMinute);
    final center = yearAt((bus.controller.view.lo + bus.controller.view.hi) / 2);
    var years = <int>[];
    try {
      final answer = await bus.ask({'op': 'ganji_years', 'ganji': ganji, 'center': center, 'lo': lo, 'hi': hi, 'limit': limit});
      final list = answer['years'];
      if (list is List) years = [for (final y in list) if (y is num) y.toInt()];
    } catch (_) {
      years = const [];
    }
    if (years.isEmpty) years = ganjiYears(ganji, center: center, lo: lo, hi: hi, limit: limit);
    return [
      for (final year in years)
        SearchHit(
          kind: 'ganji',
          name: '${yearText(year)} · $ganji년',
          when: '그 해로 이동',
          color: _warnRgb,
          start: minuteOf(year),
          end: minuteOf(year + 1) - 1,
          date: DateQuery(t: minuteOf(year), end: minuteOf(year + 1) - 1, prec: Prec.year, label: yearText(year), year: year),
        ),
    ];
  }

  SearchHit _dateRow(DateQuery date) => SearchHit(
    kind: 'date',
    name: '${date.label}(으)로',
    sub: date.note,
    color: _accentRgb,
    start: date.t,
    end: date.end,
    prec: date.prec,
    date: date,
  );

  SearchHit _hitOf(Map<Object?, Object?> row) {
    String str(String key, [String fallback = '']) {
      final value = row[key];
      return value is String ? value : fallback;
    }

    num number(String key, num fallback) {
      final value = row[key];
      return value is num ? value : fallback;
    }

    final start = number('start', 0);
    final rowNo = row['row'];
    final id = row['id'];
    final kind = str('kind', 'event');
    // 기간 없는 줄: 엔진은 start · end를 null로 싣는다(D1-B). 계보 전용 인물(갈래 figure)은 웹처럼 해 칸을 비운다(설계 9-2 D1-W2 6 — '미정'을 쓰지 않음).
    final timeless = row['start'] is! num && row['end'] is! num;
    return SearchHit(
      kind: kind,
      uid: str('uid'),
      cell: row['cell'] is String ? row['cell'] as String : null,
      name: str('name', str('title')),
      sub: str('sub'),
      when: timeless && kind == 'figure' ? '' : str('when'),
      track: str('track'),
      color: number('color', 0).toInt(),
      start: start,
      end: number('end', start),
      row: rowNo is num && rowNo >= 0 ? rowNo.toInt() : null,
      eventId: id is num ? id.toInt() : null,
      prec: precOf(row['prec']),
      timeless: timeless,
    );
  }

  // ---- 고르기 ----

  /// 보이는 차례([order])로 [step]만큼 옮긴다 — 상자를 건너 위에서 아래로, 끝에서는 처음으로 돈다.
  /// 짚은 줄이 없으면 `↓`는 첫 줄, `↑`는 끝 줄로 간다.
  void moveActive(int step) {
    final order = _layout.order;
    if (order.isEmpty) return;
    final at = order.indexOf(_active);
    // Dart의 %는 나누는 수가 양수면 늘 0 이상이다(−1 % n = n − 1).
    _active = order[at < 0 ? (step > 0 ? 0 : order.length - 1) : (at + step) % order.length];
    notifyListeners();
  }

  /// 결과 하나를 고른다(명세 5-3). 창을 먼저 열고 그다음에 이동한다. [index]가 없으면 짚은 줄, 그것도 없으면 보이는 첫 줄.
  void activate([int? index]) {
    final at = index ?? (_active >= 0 ? _active : (_layout.order.isEmpty ? 0 : _layout.order.first));
    if (at < 0 || at >= _hits.length) return;
    final hit = _hits[at];
    final span = bus.controller.view.span;
    switch (hit.kind) {
      case 'date':
      case 'ganji':
        {
          // 같은 해 보기 창은 도구 담당의 몫이라 여기서는 알리기만 한다 — 창이 먼저 열려야 가는 길이 창을 피한다.
          // `t` · `end`는 계약 0절의 **분**이다. 그 창은 해 좌표로 싣는 쪽도 받으므로 단위를 적어 준다(`minutes`).
          final date = hit.date!;
          bus.slot('yearPanel').value = {'t': date.t, 'end': date.end, 'prec': precCode(date.prec), 'label': date.label, 'cal': date.cal, 'minutes': true};
          bus.slot('marker').value = date.t;
          final (lo, hi) = dateRange(date, span);
          bus.goTo(lo, hi);
        }
      case 'cell':
        {
          // 칸은 정권 창이 아니라 **칸 창 + 조명**이다. 폭은 해 120년까지만.
          bus.select(hit.uid, kind: 'period', cell: hit.cell);
          final (lo, hi) = dateRange(
            DateQuery(t: hit.start.round(), end: hit.end.round(), prec: hit.prec, label: hit.name, year: yearAt(hit.start)),
            span,
            yearMax: 120,
          );
          bus.goTo(lo, hi, row: hit.row, ring: hit.uid.isEmpty ? null : hit.uid);
        }
      case 'house':
        bus.select(hit.uid, kind: 'house'); // 가문은 연표를 옮기지 않는다(명세 ㈐-6).
      case 'doc':
        bus.slot('doc').value = hit.uid; // 문서 창은 이번 묶음 밖이라 알리기만 한다.
      default:
        {
          if (hit.uid.isNotEmpty) bus.select(hit.uid, kind: hit.kind, eventId: hit.eventId);
          // 기간 없는 줄(계보 전용 인물)은 창만 연다 — 옮길 때가 없다(0분 = 1970년으로 가지 않게).
          if (hit.timeless) break;
          final (lo, hi) = itemRange(start: hit.start, end: hit.end, prec: hit.prec, span: span);
          bus.goTo(lo, hi, row: hit.row, ring: hit.uid.isEmpty ? null : hit.uid);
        }
    }
    close();
  }

  /// 목록만 닫는다(검색어는 그대로 — 다시 초점을 주면 되살아난다).
  void close() {
    if (_closed) return;
    _closed = true;
    notifyListeners();
  }

  /// 검색어를 비우고 빠져나간다(`Esc`).
  void clear() {
    text.clear();
    setQuery('');
  }

  /// 검색 칸의 키(명세 5-2): `↑ ↓`로 옮기고 `Enter`로 고르고 `Esc`로 비운다. 맡았으면 참.
  bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_query.raw.isEmpty && !showResults) return false;
      clear();
      return true;
    }
    if (!showResults) return false;
    if (key == LogicalKeyboardKey.arrowDown) {
      moveActive(1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      moveActive(-1);
      return true;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      activate();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    if (_ownText) text.dispose();
    super.dispose();
  }
}

/// 검색 결과 카드(앱 틀의 `searchResults` 자리에 든다). [withField]면 제 입력 칸까지 함께 세운다 — 앱 틀 없이도 혼자 선다.
class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key, required this.bus, this.controller, this.withField = false, this.autofocus = false});

  final AppBus bus;

  /// 밖에서 들고 있는 머리(없으면 제가 하나 만들고 제가 버린다).
  final SearchController? controller;

  /// 제 입력 칸을 함께 둔다(앱 틀의 검색 칸을 쓰지 않을 때).
  final bool withField;
  final bool autofocus;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  SearchController? _own;
  late SearchController _search = widget.controller ?? (_own = SearchController(bus: widget.bus));

  @override
  void initState() {
    super.initState();
    _search.addListener(_redraw);
  }

  @override
  void didUpdateWidget(SearchPanel old) {
    super.didUpdateWidget(old);
    if (widget.controller == old.controller) return;
    _search.removeListener(_redraw);
    _search = widget.controller ?? (_own ??= SearchController(bus: widget.bus));
    _search.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_redraw);
    _own?.dispose();
    super.dispose();
  }

  /// 줄의 제 색(0이면 없음 — 흰 종이 · 먹 45로 그린다).
  static Color? _colorOf(SearchHit hit) => hit.color == 0 ? null : Color(0xff000000 | (hit.color & 0xffffff));

  /// 갈래마다의 줄 꼴(감독 고름 G5 #9 — 객체 = 제 색 꼬리표 · 사건 = 점 · 조약 = 마름모 · 인물 = 흰 사람 띠 · 문서 = 흰 종이 + 문서 그림).
  static ResultMark _markOf(String kind) => switch (kind) {
    'date' || 'ganji' => ResultMark.paper,
    'event' => ResultMark.dot,
    'treaty' => ResultMark.diamond,
    'figure' => ResultMark.person,
    'doc' => ResultMark.doc,
    _ => ResultMark.tag,
  };

  /// 객체 꼬리표의 끝 꼴 — 다스리는 띠(정권 · 왕조 · 대범위 · 시대 구분)는 모따기, 영토 밖(기관 · 문화 · 가문 · 단체 · 제도)은 둥근 끝.
  static SheetTagKind _tagKindOf(String kind) => switch (kind) {
    'organ' || 'culture' || 'house' || 'group' || 'institution' => SheetTagKind.key,
    _ => SheetTagKind.cham,
  };

  /// 폴더 탭에 서는 찾는 말(16자에서 줄임).
  static String _cut(String text) => text.length > 16 ? '${text.substring(0, 16)}…' : text;

  @override
  Widget build(BuildContext context) {
    final hits = _search.hits, layout = _search.layout;
    ResultRow rowOf(int i, {String? sub}) {
      final hit = hits[i];
      return ResultRow(
        title: hit.name,
        // 곁글 = 엔진의 곁글 · 트랙(이름 뒤 옅게) · 때는 오른쪽 끝(한 바탕선).
        sub: sub ?? [hit.sub, hit.track].where((s) => s.isNotEmpty).join(' · '),
        when: hit.when,
        mark: _markOf(hit.kind),
        color: _colorOf(hit),
        kind: _tagKindOf(hit.kind),
        selected: i == _search.activeIndex,
        onTap: () => _search.activate(i),
      );
    }

    final results = !_search.showResults
        ? null
        : SearchResultsPanel(
            title: _search.query.raw.isEmpty ? '찾음' : '찾음 · ${_cut(_search.query.raw)}',
            count: _search.countText,
            note: _search.plainNote ? null : _search.note,
            lead: [for (final i in layout.lead) rowOf(i)],
            boxes: [
              for (final box in layout.boxes)
                ResultBox(
                  label: box.label,
                  items: [
                    for (final i in box.rows) rowOf(i),
                    for (final g in box.cells)
                      ResultCells(
                        owner: g.owner,
                        kind: g.kind,
                        track: hits[g.rows.first].track,
                        color: _colorOf(hits[g.rows.first]),
                        rows: [for (final i in g.rows) rowOf(i, sub: searchCellOwner(hits[i]).note)],
                      ),
                  ],
                ),
            ],
          );
    if (!widget.withField) return results ?? const SizedBox.shrink();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _search.handleKey(event) ? KeyEventResult.handled : KeyEventResult.ignored,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchField(controller: _search, autofocus: widget.autofocus),
          if (results != null) Padding(padding: const EdgeInsets.only(top: 10), child: results),
        ],
      ),
    );
  }
}

/// 제 입력 칸(앱 틀의 검색 칸과 같은 233×32 · 둥근 9 · 바탕 surface-2). 회색 예시 글자는 두지 않는다.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, this.autofocus = false});
  final SearchController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: Ui.searchWidth,
    height: Ui.searchHeight,
    child: TextField(
      controller: controller.text,
      autofocus: autofocus,
      maxLines: 1,
      textAlignVertical: TextAlignVertical.center,
      cursorColor: Ui.ink,
      style: const TextStyle(fontSize: 14, height: 20 / 14, color: Ui.text),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Ui.paper,
        contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Ui.searchRadius), borderSide: const BorderSide(color: Ui.ink20)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Ui.searchRadius), borderSide: const BorderSide(color: Ui.ink20)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Ui.searchRadius), borderSide: const BorderSide(color: Ui.ink)),
      ),
      onChanged: controller.setQuery,
    ),
  );
}
