import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../scene/fonts.dart';
import '../scene/layout.dart';
import '../shell/look.dart';
import '../shell/motion_controls.dart';
import '../shell/motion_widgets.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'date_text.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  표 보기 · CSV 저장 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 7-4절
//
//  대화 상자 하나로 지금 연표에 담긴 것을 줄줄이 늘어놓고, 같은 조건으로 CSV 파일을 뽑는다.
//  혼자 서는 부품이라 [AppBus]만 받는다:
//    bus.ask({'op':'table', …})      — 표의 줄(200줄씩 이어 받는다)
//    bus.ask({'op':'entities', …})   — 보이는 줄에만 채우는 칸(분류 · 확실성 · 설명 · 다른 견해 · 실재성)
//    bus.ask({'op':'table_csv', …})  — 엔진이 파일로 바로 쓴다(앱은 경로만 정한다)
//    bus.controller.view.lo/hi       — '지금 보이는 시기만'의 범위(분)
//    bus.select · bus.goTo           — 줄을 누르면 창을 먼저 열고 그다음에 옮긴다
//    bus.scene.layout                — 트랙 이름 · 분류 이름을 찾는 표
//
//  쓰는 법: `await showTableDialog(context, bus);`
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 한 번에 받아 오는 줄의 수. 수백만 줄일 수 있어 한꺼번에 다 받지 않는다.
const tablePage = 200;

/// 한 번에 묶어 물을 수 있는 항목 기록의 수(명세 9절 ㈎ — 최대 100).
const tableEntityBatch = 100;

/// 표 한 줄의 높이(제목 줄 + 그 아래 '다른 견해' 줄의 자리를 미리 잡아 둔다 — 자리가 출렁이지 않게).
const tableRowHeight = 46.0, tableHeadHeight = 30.0;

/// 설명 칸에 적는 글자의 수.
const tableDescLimit = 100;

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 값 — 표의 한 줄과, 줄에 없어 따로 채우는 칸
// ────────────────────────────────────────────────────────────────────────────────────────────

/// `{"op":"table"}`이 돌려주는 줄 하나(계약 2-1절).
@immutable
class TableItem {
  const TableItem({required this.kind, required this.uid, required this.name, required this.when, this.start, this.end, this.track, this.name2 = '', this.importance = 2});

  /// 항목 기록의 종류(`period` · `event` · `treaty` · `figure` · `epoch` · `scope` · `organ` · `culture` · `dynasty`).
  final String kind;
  final String uid, name;

  /// 시기 글 — 자료 처리부가 지금 연표의 `HT.formatRange`로 만들어 준 글 그대로 쓴다.
  final String when;

  /// 분. 날짜를 모르는 사건은 둘 다 없다(그런 줄은 눌러도 옮겨 가지 않는다).
  final double? start, end;

  /// 트랙 — 번호(`tracks`의 id)거나 이름이다. 둘 다 받아 준다.
  final Object? track;

  /// 자료 처리부가 실어 준 트랙 이름(`track_name`). 있으면 이것을 쓴다.
  final String name2;
  final int importance;

  static TableItem fromJson(Map<String, dynamic> j) => TableItem(
    kind: _str(j['kind']),
    uid: _str(j['uid']),
    name: _str(j['name']).isNotEmpty ? _str(j['name']) : _str(j['title']),
    when: _str(j['when']),
    start: _numOrNull(j['start']),
    end: _numOrNull(j['end']),
    track: j['track'],
    name2: _str(j['track_name']),
    importance: _int(j['importance'], 2),
  );

  /// 트랙 이름 — 실어 온 이름이 먼저고, 없으면 번호로 [layout]에서 찾는다(id로 먼저, 없으면 차례로).
  String trackName(SceneLayout? layout) {
    if (name2.isNotEmpty) return name2;
    final t = track;
    if (t is String) return t;
    if (t is num && layout != null) {
      final id = t.toInt();
      for (final track in layout.tracks) {
        if (track.id == id) return track.name;
      }
      if (id >= 0 && id < layout.tracks.length) return layout.tracks[id].name;
    }
    return '';
  }
}

/// 줄에 없는 칸 — 보이는 줄에 한해 `{"op":"entities"}`로 묶어 받아 채운다. 못 받으면 빈 칸이다.
@immutable
class TableExtra {
  const TableExtra({this.category = '', this.certainty = '', this.description = '', this.alt = '', this.historicity = ''});

  /// 분류 이름(사건만). 확실성은 통설이면 빈 글.
  final String category, certainty;

  /// 설명 — 100자까지.
  final String description;

  /// `다른 견해: …` 한 줄의 뒷글(없으면 빈 글).
  final String alt;

  /// 실재성 딱지의 글 — 실재면 빈 글.
  final String historicity;

  /// 아직 받지 못한 줄.
  static const none = TableExtra();

  /// 항목 기록 `{uid, kind, json}` 하나를 표의 칸으로 푼다.
  static TableExtra fromRecord(Map<String, dynamic> record, {List<CategoryInfo> categories = const []}) {
    final raw = record['json'];
    Map<String, dynamic> item;
    if (raw is Map) {
      item = raw.cast<String, dynamic>();
    } else {
      try {
        item = (jsonDecode(_str(raw)) as Map).cast<String, dynamic>();
      } on FormatException {
        return none;
      }
    }
    final kind = _str(record['kind']).isNotEmpty ? _str(record['kind']) : _str(item['itemKind']);
    final key = _str(item['category']);
    return TableExtra(
      category: kind == 'event' || kind == 'treaty' ? categoryName(key, categories) : '',
      certainty: certaintyName(_str(item['certainty'])),
      description: cutDescription(_str(item['description'])),
      alt: altsText(item, figure: kind == 'figure'),
      historicity: historicityName(_str(item['historicity'])),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 글 — 지금 연표의 HT.ITEM_WORDS · HT.CERTAINTY · HT.HISTORICITY · HT.altText 그대로
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 구분 칸의 글(`HT.ITEM_WORDS`). 모르는 종류면 `항목`.
String itemWord(String kind) => const {
  'period': '시대',
  'event': '사건',
  'organ': '기관',
  'culture': '문화',
  'dynasty': '왕조',
  'epoch': '시대 구분',
  'people': '민족',
  'track': '트랙',
  'category': '분류',
  'cell': '칸',
  'figure': '인물',
  'house': '가문',
  'treaty': '조약',
  'scope': '대범위',
}[kind] ??
    '항목';

/// 확실성 칸의 글(`HT.CERTAINTY`). 통설(기본값)은 빈 글이다 — 표에 온통 '통설'이 늘어서지 않게.
String certaintyName(String id) => switch (id) {
  'certain' => '확실',
  'estimated' => '추정',
  'legend' => '전승',
  _ => '',
};

/// 실재성 딱지의 글(`HT.HISTORICITY`). 실재(비움 · attested)는 딱지가 없다.
String historicityName(String id) => switch (id) {
  'semi' => '반전설',
  'legendary' => '전설',
  'disputed' => '실재 논쟁',
  'refuted' => '부정됨',
  _ => '',
};

/// 분류 열쇠 → 이름(`layout`의 categories). 못 찾으면 빈 글.
String categoryName(String key, List<CategoryInfo> categories) {
  if (key.isEmpty) return '';
  for (final c in categories) {
    if (c.key == key) return c.name;
  }
  return '';
}

/// 설명 칸 — 100자에서 자른다(자른 자리에 말줄임표를 붙이지 않는 것은 지금 연표와 같다).
String cutDescription(String text) => text.length <= tableDescLimit ? text : text.substring(0, tableDescLimit);

/// `다른 견해: …`의 뒷글 — 이설마다 `〈채운 연대〉(근거)`, 날짜 없는 견해는 근거만. 쉼표로 잇는다(`renderTable`).
String altsText(Map<String, dynamic> item, {bool figure = false}) {
  final list = item['alternatives'];
  if (list is! List || list.isEmpty) return '';
  final out = <String>[];
  for (final a in list) {
    if (a is! Map) continue;
    final alt = a.cast<String, dynamic>();
    final label = _str(alt['label']);
    final when = altWhen(alt, item, figure: figure);
    out.add(when.isEmpty ? label : '$when($label)');
  }
  out.removeWhere((s) => s.isEmpty);
  return out.join(', ');
}

/// 이설 하나가 말하는 연대의 글(`HT.altWhen`) — 비운 쪽은 통설 값으로 채운다(`HT.altSpan`). 글만 있는 견해는 빈 글.
String altWhen(Map<String, dynamic> alt, Map<String, dynamic> base, {bool figure = false}) {
  if (!_altDated(alt)) return '';
  if (!figure) {
    final span = _altSpan(alt, base, const ['start', 'end']);
    return rangeText(
      start: span.start,
      startAt: span.startAt,
      end: span.end,
      endAt: span.endAt,
      startUnknown: span.startUnknown,
      endUnknown: span.endUnknown,
      ongoing: span.ongoing,
    );
  }
  final life = _altSpan(alt, base, const ['birth', 'death']);
  final work = _altSpan(alt, base, const ['start', 'end']);
  final bits = <String>[];
  if (life.ownStart || life.ownEnd) {
    final born = life.start == null ? '' : whenText(life.start, at: life.startAt);
    final died = life.end == null ? '' : whenText(life.end, at: life.endAt);
    bits.add('생몰 ${[born, died].join(' ~ ').trim()}');
  }
  if (work.ownStart || work.ownEnd) {
    bits.add('활동 ${rangeText(start: work.start, startAt: work.startAt, end: work.end, endAt: work.endAt, ongoing: work.ongoing)}');
  }
  return bits.join(' · ');
}

/// 날짜를 적은 이설인가(`HT.altDated`).
bool _altDated(Map<String, dynamic> alt) =>
    alt['start'] != null || alt['end'] != null || alt['ongoing'] == true || alt['birth'] != null || alt['death'] != null;

/// `HT.altSpan` — 이설이 적은 쪽은 이설의 값, 비운 쪽은 통설(항목)의 값.
_AltSpan _altSpan(Map<String, dynamic> alt, Map<String, dynamic> base, List<String> keys) {
  final loKey = keys[0], hiKey = keys[1];
  final ownLo = alt[loKey] != null;
  final ownHi = alt[hiKey] != null || (hiKey == 'end' && alt['ongoing'] == true);
  final lo = ownLo ? alt : base, hi = ownHi ? alt : base;
  final ongoing = alt['ongoing'] == true || (!ownHi && base['ongoing'] == true);
  return _AltSpan(
    start: _numOrNull(lo[loKey]),
    startAt: _strOrNull(lo['${loKey}At']),
    end: ongoing ? null : _numOrNull(hi[hiKey]),
    endAt: ongoing ? null : _strOrNull(hi['${hiKey}At']),
    startUnknown: !ownLo && base['${loKey}Unknown'] == true,
    endUnknown: !ownHi && base['${hiKey}Unknown'] == true,
    ongoing: ongoing,
    ownStart: ownLo,
    ownEnd: ownHi,
  );
}

@immutable
class _AltSpan {
  const _AltSpan({this.start, this.startAt, this.end, this.endAt, this.startUnknown = false, this.endUnknown = false, this.ongoing = false, this.ownStart = false, this.ownEnd = false});
  final double? start, end;
  final String? startAt, endAt;
  final bool startUnknown, endUnknown, ongoing, ownStart, ownEnd;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. CSV를 쓸 자리
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 저장할 파일 이름과 확장자.
const csvBaseName = '역사연표', csvExtension = '.csv';

/// [folder] 안에서 아직 비어 있는 이름을 고른다 — `역사연표.csv` · `역사연표 (2).csv` …(덮어쓰지 않는다).
/// [exists]는 검사할 때 갈아 끼우는 길이고, 비우면 실제 파일을 본다.
String freeCsvPath(String folder, {bool Function(String path)? exists, String base = csvBaseName}) {
  final has = exists ?? (path) => File(path).existsSync();
  final sep = folder.endsWith('/') || folder.endsWith(r'\') ? '' : Platform.pathSeparator;
  for (int n = 1; n < 1000; n++) {
    final name = n == 1 ? '$base$csvExtension' : '$base ($n)$csvExtension';
    final path = '$folder$sep$name';
    if (!has(path)) return path;
  }
  return '$folder$sep$base (1000)$csvExtension';
}

/// 기본 저장 폴더 — 내려받기 폴더, 없으면 문서 폴더.
Future<Directory?> defaultCsvFolder() async {
  try {
    final down = await getDownloadsDirectory();
    if (down != null) return down;
  } on Object {
    // 내려받기 폴더가 없는 자리(일부 운영체제)에서는 문서 폴더로 물러선다.
  }
  try {
    return await getApplicationDocumentsDirectory();
  } on Object {
    return null;
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 대화 상자
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 표 보기를 연다. 닫힐 때까지 기다린다.
Future<void> showTableDialog(BuildContext context, AppBus bus, {Future<Directory?> Function()? folder}) => showDialog<void>(
  context: context,
  barrierColor: Ui.ink20, // 창 뒤는 흐림 없이 ink20 깔개
  builder: (context) => TableDialog(bus: bus, folder: folder),
);

/// 표 보기의 알맹이. 혼자 띄워도 되도록 공개해 둔다(검사는 이것을 바로 띄운다).
class TableDialog extends StatefulWidget {
  const TableDialog({super.key, required this.bus, this.folder});
  final AppBus bus;

  /// CSV를 저장할 폴더를 고르는 길. 비우면 [defaultCsvFolder].
  final Future<Directory?> Function()? folder;

  @override
  State<TableDialog> createState() => TableDialogState();
}

class TableDialogState extends State<TableDialog> {
  final _rows = <TableItem>[];
  final _extras = <String, TableExtra>{};
  final _want = <String>{};
  final _asked = <String>{};
  final _scroll = ScrollController();

  bool _rangeOnly = false, _withPeriods = false;
  bool _loading = false, _saving = false, _filling = false, _scheduled = false;
  bool _hasMore = true;

  /// 이어 받기 표 — 건너뛸 줄의 수(계약 2-1절의 `after` · 답의 `next`).
  int _after = 0;
  int? _total;
  String _note = '';
  bool _noteBad = false;

  /// 조건이 바뀌면 올라간다 — 늦게 온 답을 버리는 표.
  int _epoch = 0;

  /// 지금까지 받은 줄.
  List<TableItem> get rows => List.unmodifiable(_rows);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 첫 쪽은 곧바로. (setState는 기다린 뒤에만 부른다 — 처음 짓는 도중에 다시 짓자고 하지 않게.)
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  SceneLayout? get _layout => widget.bus.scene.layout;

  Map<String, dynamic> _query(String op, {int? after, int? limit, String? path}) {
    final view = widget.bus.controller.view;
    return {
      'op': op,
      if (_rangeOnly) 'lo': view.lo.round(),
      if (_rangeOnly) 'hi': view.hi.round(),
      'with_periods': _withPeriods,
      // 켠 자료집만 — 화면에 보이는 것과 같은 것이 표에도 담기게.
      'packs': ?_layout?.enabledPacks,
      'after': ?after,
      'limit': ?limit,
      'path': ?path,
    };
  }

  Future<void> _reload() async {
    _epoch++;
    _rows.clear();
    _extras.clear();
    _want.clear();
    _asked.clear();
    _after = 0;
    _total = null;
    _hasMore = true;
    _loading = false;
    _note = '';
    _noteBad = false;
    if (mounted) setState(() {});
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    final epoch = _epoch;
    try {
      final answer = await widget.bus.ask(_query('table', after: _after == 0 ? null : _after, limit: tablePage));
      if (!mounted || epoch != _epoch) return;
      final items = [
        for (final row in _listOf(answer['items']))
          if (row is Map) TableItem.fromJson(row.cast<String, dynamic>()),
      ];
      setState(() {
        _rows.addAll(items);
        final total = answer['count'];
        if (total is num) _total = total.toInt();
        // 줄이 하나도 오지 않으면 더 물어봐야 소용이 없다(끝없이 도는 것을 막는다).
        _hasMore = answer['has_more'] == true && items.isNotEmpty;
        final next = answer['next'];
        _after = next is num ? next.toInt() : _after + items.length;
      });
    } on Object catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _hasMore = false;
        _note = '표를 읽지 못했습니다 — ${_reason(e)}';
        _noteBad = true;
      });
    } finally {
      if (epoch == _epoch) _loading = false;
    }
    _topUp();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // 목록 끝에 닿으면 다음 쪽을 받는다(한 화면 앞에서 미리).
    if (p.pixels > p.maxScrollExtent - 600) unawaited(_loadMore());
  }

  /// 받은 줄이 화면을 채우지 못하면 스크롤이 생기지 않아 다음 쪽을 부를 일이 없다 — 한 프레임 뒤에 손수 이어 받는다.
  void _topUp() {
    if (!_hasMore || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasMore) return;
      if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) unawaited(_loadMore());
    });
  }

  /// 보이는 줄이니 칸을 채워 달라고 적어 둔다 — 한 프레임에 모아 한 번만 묻는다.
  void _need(String uid) {
    if (uid.isEmpty || _extras.containsKey(uid) || _asked.contains(uid) || _want.contains(uid)) return;
    _want.add(uid);
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      unawaited(_fill());
    });
  }

  Future<void> _fill() async {
    if (_filling || _want.isEmpty || !mounted) return;
    _filling = true;
    final epoch = _epoch;
    final uids = _want.take(tableEntityBatch).toList();
    _want.removeAll(uids);
    _asked.addAll(uids);
    try {
      final answer = await widget.bus.ask({'op': 'entities', 'uids': uids});
      if (!mounted || epoch != _epoch) return;
      final categories = _layout?.categories ?? const <CategoryInfo>[];
      setState(() {
        for (final row in _listOf(answer['entities'] ?? answer['items'] ?? answer['rows'])) {
          if (row is! Map) continue;
          final record = row.cast<String, dynamic>();
          final uid = _str(record['uid']);
          if (uid.isNotEmpty) _extras[uid] = TableExtra.fromRecord(record, categories: categories);
        }
        // 답에 없던 것은 빈 칸으로 둔다(다시 묻지 않게).
        for (final uid in uids) {
          _extras.putIfAbsent(uid, () => TableExtra.none);
        }
      });
    } on Object {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        for (final uid in uids) {
          _extras.putIfAbsent(uid, () => TableExtra.none);
        }
      });
    } finally {
      _filling = false;
    }
    if (mounted && epoch == _epoch && _want.isNotEmpty) await _fill();
  }

  void _open(TableItem item) {
    Navigator.of(context).pop();
    // 창을 먼저 열고 그다음에 옮긴다 — 도착 자리가 창에 가려지지 않게(명세 9절 ㈐ 9).
    widget.bus.select(item.uid, kind: item.kind);
    // 날짜를 모르는 줄은 갈 곳이 없다 — 창만 연다.
    final start = item.start;
    if (start != null) widget.bus.goTo(start, item.end ?? start, ring: item.uid);
  }

  Future<void> _saveCsv() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _note = '';
      _noteBad = false;
    });
    final epoch = _epoch;
    try {
      final dir = await (widget.folder ?? defaultCsvFolder)();
      if (dir == null) throw const FileSystemException('내려받기 폴더도 문서 폴더도 찾지 못했습니다');
      final path = freeCsvPath(dir.path);
      final answer = await widget.bus.ask(_query('table_csv', path: path));
      if (!mounted) return;
      final n = answer['rows'];
      final saved = _str(answer['path']).isNotEmpty ? _str(answer['path']) : path;
      setState(() {
        _note = '${n is num ? n.toInt() : 0}줄을 저장했습니다 — $saved';
        _noteBad = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _note = 'CSV로 저장하지 못했습니다 — ${_reason(e)}';
        _noteBad = true;
      });
    } finally {
      if (mounted && epoch == _epoch) setState(() => _saving = false);
    }
  }

  void _setRangeOnly(bool on) {
    if (on == _rangeOnly) return;
    _rangeOnly = on;
    unawaited(_reload());
  }

  void _setWithPeriods(bool on) {
    if (on == _withPeriods) return;
    _withPeriods = on;
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = math.min(820.0, media.size.width - 24);
    final height = math.max(240.0, media.size.height - 32);
    return Center(
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 13, height: 1.5, color: Ui.text, decoration: TextDecoration.none),
        child: _Rise(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Ui.surface,
              borderRadius: BorderRadius.circular(Ui.menuRadius),
              boxShadow: Ui.shadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Ui.menuRadius),
              child: SizedBox(
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [_head(), Flexible(child: _body()), if (_note.isNotEmpty) _noteLine(), _foot()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.dlg-head` — 18/22/12.
  Widget _head() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
    child: Row(
      children: [
        const Expanded(
          child: Text('표', style: TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.38, color: Ui.text)),
        ),
        // `.icon-btn`(32×32 · 둥근 9 · 올리면 surface-2)은 앱 틀의 ShellButton과 같은 값이다.
        ShellButton(tooltip: '닫기', width: 32, padding: EdgeInsets.zero, onPressed: () => Navigator.of(context).pop(), child: const Text('✕', style: TextStyle(fontSize: 15))),
      ],
    ),
  );

  /// `.dlg-body` — 8/22/18. 안내 한 줄 · 머리 줄 · 줄 목록.
  Widget _body() {
    final count = _total ?? _rows.length;
    final more = _total == null && _hasMore;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              '$count개${more ? ' 이상' : ''} · 줄을 누르면 연표에서 그 위치로 갑니다. 지금 켜 둔 필터·검색이 그대로 적용됩니다.',
              style: const TextStyle(fontSize: 13, color: Ui.text3),
            ),
          ),
          const _HeadRow(),
          Flexible(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (_rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(_loading ? '표를 읽고 있습니다' : '표시할 항목이 없습니다.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Ui.text3)),
      );
    }
    final tail = _hasMore ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true, // 줄이 적으면 대화 상자도 그만큼만 — css의 `.dlg { max-height }`와 같다.
      padding: EdgeInsets.zero,
      itemExtent: tableRowHeight,
      itemCount: _rows.length + tail,
      itemBuilder: (context, index) {
        if (index >= _rows.length) {
          return const Align(child: Text('더 읽고 있습니다', style: TextStyle(fontSize: 12, color: Ui.text3)));
        }
        final item = _rows[index];
        _need(item.uid);
        return _Row(item: item, extra: _extras[item.uid] ?? TableExtra.none, track: item.trackName(_layout), onTap: () => _open(item));
      },
    );
  }

  /// CSV를 저장한 결과 한 줄.
  Widget _noteLine() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
    child: Text(_note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: _noteBad ? Ui.ink : Ui.text2)),
  );

  /// `.dlg-foot` — 체크 둘 · CSV · 닫기.
  Widget _foot() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    decoration: const BoxDecoration(
      color: Ui.surface,
      border: Border(top: BorderSide(color: Ui.line)),
    ),
    child: Row(
      children: [
        // 체크 둘은 왼쪽, 단추는 오른쪽 끝(`.dlg-foot`의 `.spacer`) — 창이 좁으면 글만 줄어든다.
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _Check(label: '지금 보이는 시기만', value: _rangeOnly, onChanged: _setRangeOnly)),
              const SizedBox(width: 14),
              Flexible(child: _Check(label: '시대 · 인물도 포함', value: _withPeriods, onChanged: _setWithPeriods)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _Button(label: _saving ? '저장하는 중' : 'CSV 내보내기', onPressed: _saving ? null : () => unawaited(_saveCsv())),
        const SizedBox(width: 8),
        _Button(label: '닫기', onPressed: () => Navigator.of(context).pop()),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 표의 칸 · 작은 부품
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 열의 폭 — 시기 · 구분 · 트랙은 글이 접히지 않게 못박고, 제목과 설명이 남은 자리를 나눈다.
const _whenWidth = 138.0, _wordWidth = 54.0, _trackWidth = 72.0, _categoryWidth = 70.0, _certaintyWidth = 52.0, _columnGap = 6.0;

/// 표의 머리 줄.
class _HeadRow extends StatelessWidget {
  const _HeadRow();

  @override
  Widget build(BuildContext context) => Container(
    height: tableHeadHeight,
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Ui.line))),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: _whenWidth, child: _HeadCell('시기')),
        SizedBox(width: _columnGap),
        SizedBox(width: _wordWidth, child: _HeadCell('구분')),
        SizedBox(width: _columnGap),
        SizedBox(width: _trackWidth, child: _HeadCell('트랙')),
        SizedBox(width: _columnGap),
        Expanded(flex: 5, child: _HeadCell('제목')),
        SizedBox(width: _columnGap),
        SizedBox(width: _categoryWidth, child: _HeadCell('분류')),
        SizedBox(width: _columnGap),
        SizedBox(width: _certaintyWidth, child: _HeadCell('확실성')),
        SizedBox(width: _columnGap),
        Expanded(flex: 6, child: _HeadCell('설명')),
      ],
    ),
  );
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Ui.text3));
}

/// 표의 한 줄. 높이는 [tableRowHeight]로 못박아 칸이 늦게 채워져도 자리가 출렁이지 않는다.
class _Row extends StatefulWidget {
  const _Row({required this.item, required this.extra, required this.track, required this.onTap});
  final TableItem item;
  final TableExtra extra;
  final String track;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item, extra = widget.extra;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: item.name,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            color: _hover ? Ui.accentSoft : const Color(0x00000000),
            padding: const EdgeInsets.symmetric(vertical: 4),
            foregroundDecoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Ui.line))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _whenWidth, child: _cell(item.when)),
                const SizedBox(width: _columnGap),
                SizedBox(width: _wordWidth, child: _cell(itemWord(item.kind))),
                const SizedBox(width: _columnGap),
                SizedBox(width: _trackWidth, child: _cell(widget.track)),
                const SizedBox(width: _columnGap),
                Expanded(flex: 5, child: _title(item, extra)),
                const SizedBox(width: _columnGap),
                SizedBox(width: _categoryWidth, child: _cell(extra.category)),
                const SizedBox(width: _columnGap),
                SizedBox(width: _certaintyWidth, child: _cell(extra.certainty)),
                const SizedBox(width: _columnGap),
                Expanded(flex: 6, child: _cell(extra.description, color: Ui.text2, lines: 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, {Color color = Ui.text, int lines = 1}) =>
      Text(text, maxLines: lines, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.5, color: color));

  /// 제목 · 그 옆 실재성 딱지 · 그 아래 `다른 견해: …`.
  Widget _title(TableItem item, TableExtra extra) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 19.5,
        child: Row(
          children: [
            Flexible(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w700, color: Ui.text))),
            if (extra.historicity.isNotEmpty) ...[
              const SizedBox(width: 4),
              _HistoricityTag(extra.historicity),
            ],
          ],
        ),
      ),
      SizedBox(
        height: 18,
        child: extra.alt.isEmpty
            ? null
            : Text('다른 견해: ${extra.alt}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.warn)),
      ),
    ],
  );
}

/// `.hs-tag` — 제목 옆 실재성 딱지.
class _HistoricityTag extends StatelessWidget {
  const _HistoricityTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(color: _soft(Ui.text3, .16), borderRadius: BorderRadius.circular(4)),
    child: Text(text, maxLines: 1, style: const TextStyle(fontSize: 11, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text2)),
  );
}

/// 표의 켬끔도 같은 공통 토글로 표시한다.
class _Check extends StatelessWidget {
  const _Check({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MotionToggle(label: label, value: value, onChanged: onChanged);
}

/// `.btn` — 높이 34 · 둥근 10 · `--surface-2`.
class _Button extends StatefulWidget {
  const _Button({required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final off = widget.onPressed == null;
    return MouseRegion(
      cursor: off ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: off ? .45 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Ui.ease,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: !off && _hover ? Ui.ink8 : null,
                borderRadius: BorderRadius.circular(Ui.controlRadius),
              ),
              foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.ink20)),
              child: Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Ui.text)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 나타남 — `--t-in`(200ms) `--ease`에 10px 떠오르며 짙어진다(움직임 원칙 ②).
class _Rise extends StatefulWidget {
  const _Rise({required this.child});
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> {
  late final SurfaceMotion _anim;

  @override
  void initState() {
    super.initState();
    _anim = SurfaceMotion()..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, child) {
      final t = _anim.value;
      return Opacity(opacity: _anim.opacity, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child));
    },
    child: widget.child,
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 잔손
// ────────────────────────────────────────────────────────────────────────────────────────────

Color _soft(Color c, double t) => c.withAlpha((c.a * 255 * t).round().clamp(0, 255));

List<Object?> _listOf(Object? v) => v is List ? v : const [];

String _str(Object? v) => v == null ? '' : v.toString();

String? _strOrNull(Object? v) => v?.toString();

double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

/// 잘못된 일의 까닭 한 줄 — 긴 스택은 적지 않는다.
String _reason(Object e) {
  if (e is FileSystemException) return e.message;
  final text = e.toString();
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}
