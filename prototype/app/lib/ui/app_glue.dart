import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;

import '../controller.dart';
import '../scene/aux_calendar.dart' show AuxCalendarStore;
import '../scene/cleartype_prefs.dart';
import '../scene/emphasis.dart';
import '../scene/hit_test.dart';
import '../scene/scene.dart';
import '../shell/look.dart';
import 'app_bus.dart';
import 'date_text.dart' show AuxTables;
import 'app_memory.dart';
import 'context_menu.dart';
import 'detail_cell.dart';
import 'detail_echo.dart';
import 'detail_group.dart';
import 'detail_item.dart';
import 'detail_people.dart';
import 'detail_scope.dart';
import 'detail_shell.dart';
import 'doc_window.dart' show DocUi, docSideSlot;
import 'filter_state.dart';
import 'kin/succession_view.dart' show registerKinDetail;
import 'legend.dart';
import 'shell_keys.dart';
import 'tools_year.dart';
import 'names_display.dart' show NamesGlue;

/// 날짜 글을 읽을 때 넘기는 보조 달력 표(`ui/date_text.dart`의 `readAt` · `whenText` · `rangeText` …).
/// 넘기면 음력 · 이슬람력 …으로 **적은** 날짜 글을 표로 되짚어 그날로 읽고, 안 넘기면 적힌 수를 서력으로 읽는다(11물결 dates ⑵).
/// 표는 저장소마다 하나(`AuxCalendarStore.shared`)이고, 아직 받지 못한 달력은 null을 돌려준다.
AuxTables? get appCals => AuxCalendarStore.shared?.table;

// 이어 붙이기 — 혼자 서는 부품들(상세 창 · 검색 · 필터 · 도구 · 카드 · 단축키)과 실제 앱(archive_app.dart)을 잇는 자리.
// 부품은 [AppBus]만 알고, 장면 · 조종부는 [SceneBridge]로만 만진다. 그래서 이 파일에는 화면이 거의 없고
// "무슨 말을 들으면 무엇을 하는가"만 있다 — 검사(test/app_glue_test.dart)도 가짜 다리 하나로 돌린다.

/// [AppBus.slot]에 쓰는 이름 — 부품마다 제 파일에 적어 둔 것을 한자리에 모았다.
/// (`command` · `zen` · `notice` · `clearType`은 `shell_keys.dart`, `yearPanel` · `marker`는 `tools_year.dart`,
///  `measure` · `measure_on`은 `tools_measure.dart`, `legend`는 `legend.dart`,
///  `echo` · `echoHits`는 `detail_echo.dart`에 있다.)
const slotDetail = 'detail',
    slotFilters = 'filters',
    slotFoldAll = 'foldAll',
    slotSearchHits = 'searchHits',
    slotSpots = 'spots',
    // 같은 사람의 자리(건의 8의 6-나): 칸 창이 싣는 `[{uid, cell}]` — 고른 칸 자신과 그 사람의 다른 칸들(`x_persons[칸].others`).
    slotTwins = 'twins',
    slotHouse = 'house',
    slotEcho = echoSlot,
    slotEchoHits = echoHitsSlot,
    slotTracks = 'tracks',
    slotCategories = 'categories',
    slotScopes = 'scopes',
    slotDoc = 'doc',
    // D1 승계표 · 세계표(확정 설계 3 · 4절): 세계표 떠 있는 창을 여는 부탁(`kin/family_window.dart`의 FamilyRequest) ·
    // 접힘 기억([KinFoldMemory] — 기억을 붙일 때 싣는다) · 지금 떠 있는 창의 조종 손잡이(KinDriver — 측정 · 검사가 쓴다).
    slotFamily = 'family',
    slotKinFold = 'kinFold',
    slotKinDriver = 'kinDriver';

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 다리 — 앱 틀이 장면 · 조종부에 바라는 것
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 앱 틀이 장면 · 조종부에 바라는 것. 총괄이 나중에 진짜 구현으로 갈아 끼운다.
abstract class SceneBridge {
  /// 가 달라는 부탁(멀리 가기 · 도착 고리). 기본 구현: controller.showRange + scrollTo(바로).
  void go(GoRequest request, {double insetRight = 0});

  /// 고르기 · 강조 · 조명의 밝기 상태를 장면에 넣는다(lib/scene/emphasis.dart의 Look).
  void emphasize(Look look);

  /// 화면의 한 점에 무엇이 있는가(오른쪽 클릭 메뉴 · 손 밑의 알약).
  Future<MenuSpot> probe(Offset local);

  /// 모두 접기/펴기 · 트랙 접기. 바뀌었으면 참.
  bool foldAll(bool folded);
}

/// **지금 있는 공개 API만으로** 만든 기본 다리. 총괄이 장면 쪽(Fly · Emphasis · 띠/칸 맞히기)을 끝내면 갈아 끼운다.
///
/// 채워야 할 것: `go`의 멀리 가기(van Wijk 길)와 도착 고리(`ring`) · `emphasize`의 흐림 · 조명 · 가문 ·
/// `probe`의 띠 · 칸 · 트랙 맞히기 · `foldAll`.
class BasicSceneBridge implements SceneBridge {
  BasicSceneBridge(this.bus);

  final AppBus bus;

  /// 우리가 세로로 옮겼다고 알릴 곳(묶음 카드는 그 뒤 0.2초 동안 손 밑의 알약을 열지 않는다 — 명세 9 ㈐-11).
  VoidCallback? onSelfScroll;

  TimelineController get _c => bus.controller;
  TimelineScene get _scene => bus.scene;

  /// 부탁받은 기간이 **창에 가려지지 않은 부분**에 꼭 맞게 보기를 옮긴다(명세 ㈐-9). 줄을 주면 그 줄도 데려온다.
  @override
  void go(GoRequest request, {double insetRight = 0}) {
    final v = _c.view;
    final plot = v.plotWidth;
    final open = (insetRight / v.mag).clamp(0.0, plot * .8);
    final free = (plot - open).clamp(1.0, plot);
    final want = (request.hi - request.lo).abs();
    final span = want <= 0 ? v.span : want * plot / free;
    _c.showRange(request.lo, request.lo + span);
    final row = request.row;
    if (row == null) return;
    final layout = _scene.layout;
    if (row < 0 || row >= layout.rowCount || !layout.isVisible(row)) return;
    _c.scrollTo(layout.rowTop(row) - v.bodyHeight / 3);
    onSelfScroll?.call();
  }

  /// 지금 장면이 아는 밝기는 '고른 사건' 하나뿐이다 — 나머지(흐림 · 조명 · 가문)는 장면 쪽이 끝난 뒤에 채운다.
  @override
  void emphasize(Look look) => _scene.select(look.event, row: look.row ?? -1);

  /// 지금 있는 맞히기로 사건 · 알약만 찾는다. 띠 · 칸 · 트랙은 아직 맞히지 못해 자리만 비워 둔다.
  @override
  Future<MenuSpot> probe(Offset local) async {
    final v = _c.view;
    final at = v.layoutOf((local.dx, local.dy));
    final minute = v.minuteAt(at.$1);
    final hit = hitTest(_scene, at.$1, at.$2);
    final uid = hit.kind == HitKind.event ? await uidOfEvent(bus, hit.eventId) : null;
    return MenuSpot(uid: uid, at: minute);
  }

  @override
  bool foldAll(bool folded) => false;
}

/// 사건 번호 → 항목 기록의 열쇠(계약 2-1의 `uid_of`). 이름이 없는 사건이면 null.
Future<String?> uidOfEvent(AppBus bus, int eventId) async {
  try {
    final answer = await bus.ask({'op': 'uid_of', 'kind': 'event', 'id': eventId});
    final uid = answer['uid'];
    return uid is String && uid.isNotEmpty ? uid : null;
  } catch (_) {
    return null;
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 강조의 임자 — 검색과 창이 같은 칸을 다툰다(명세 3-2 · 9 ㈐-1)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 지금 강조를 건 쪽.
enum HiOwner { none, search, window }

/// **나중에 건 쪽이 이기고, 한쪽이 물러나면 다른 쪽이 되살아난다.**
/// 화면이 없는 순수 클래스라 검사가 이것만 두드려도 된다.
class HighlightOwner {
  List<String>? _search, _window;
  HiOwner _owner = HiOwner.none;

  HiOwner get owner => _owner;

  /// 지금 강조에 든 uid(없으면 null — 흐림 없음).
  List<String>? get uids => switch (_owner) {
    HiOwner.search => _search,
    HiOwner.window => _window,
    HiOwner.none => null,
  };

  /// 검색이 건 강조. 비우면(검색어를 지우면) 물러나 창의 강조가 되살아난다. 바뀌었으면 참.
  bool setSearch(List<String>? uids) => _set(HiOwner.search, uids, release: uids == null || uids.isEmpty);

  /// 열린 창(조명)이 건 강조. 바뀌었으면 참.
  ///
  /// **빈 목록도 창이 가진 것**이다 — 지금 연표가 창을 열며 `hiOwner = 'spot'`으로 두고
  /// 강조를 걸 것이 없으면 `setHighlight(null)`을 부르는 것과 같다(js/viewer.js:1753 · 2119).
  /// [claim]이 거짓이면 임자를 가로채지 않고 값만 고친다 — 메아리 스위치 · 늦게 온 `echo`의 답처럼
  /// **창은 그대로인데 내용만 바뀐 때**(그 사이에 검색어를 고쳤으면 검색 강조가 그대로 이긴다).
  bool setWindow(List<String>? uids, {bool claim = true}) => _set(HiOwner.window, uids, claim: claim);

  /// 창이 닫혔다 — 임자를 내려놓고 검색 강조를 되살린다.
  bool releaseWindow() => _set(HiOwner.window, null, release: true);

  bool _set(HiOwner who, List<String>? next, {bool claim = true, bool release = false}) {
    final before = uids;
    final value = next == null || next.isEmpty ? null : List<String>.unmodifiable(next);
    if (who == HiOwner.search) {
      _search = value;
    } else {
      _window = value;
    }
    if (release) {
      if (_owner == who) {
        final other = who == HiOwner.search ? _window : _search;
        _owner = other == null ? HiOwner.none : (who == HiOwner.search ? HiOwner.window : HiOwner.search);
      }
    } else if (claim) {
      _owner = who;
    }
    final after = uids;
    if (before == null || after == null) return before != after;
    return before.length != after.length || !before.asMap().entries.every((e) => after[e.key] == e.value);
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 자료 처리부의 답 다듬기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 조회의 답 `data`를 부품이 기다리는 꼴로 — **배열이 오면 `{'items': […]}`로 감싼다**
/// (`entities` · `cells_of`는 배열 그대로 준다 — 계약 2-1).
Map<String, dynamic> wrapAnswer(Object? data) {
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is List) return <String, dynamic>{'items': data};
  return <String, dynamic>{};
}

/// 항목 하나가 연표의 어디에 있는가(`ids_of` · `id_of`의 답).
@immutable
class ItemPlace {
  const ItemPlace({this.band, this.event, this.row, this.start, this.end});
  final int? band, event, row;
  final double? start, end;
}

/// `ids_of`의 답(`{bands:[…], events:[…]}`)이나 `id_of`의 답(`{band,event,row,start,end}`)을 읽는다.
Map<String, ItemPlace> readPlaces(Map<String, dynamic> answer, {String? single}) {
  final out = <String, ItemPlace>{};
  int? num2int(Object? v) => v is num ? v.toInt() : null;
  double? num2double(Object? v) => v is num ? v.toDouble() : null;

  void put(Object? list, bool isBand) {
    if (list is! List) return;
    for (final one in list) {
      if (one is! Map) continue;
      final uid = one['uid'];
      if (uid is! String || uid.isEmpty) continue;
      final was = out[uid];
      out[uid] = ItemPlace(
        band: isBand ? num2int(one['id']) : was?.band,
        event: isBand ? was?.event : num2int(one['id']),
        row: num2int(one['row']) ?? was?.row,
        start: num2double(one['start']) ?? was?.start,
        end: num2double(one['end']) ?? was?.end,
      );
    }
  }

  put(answer['bands'], true);
  put(answer['events'], false);
  if (single != null && !out.containsKey(single)) {
    final band = num2int(answer['band']), event = num2int(answer['event']);
    if (band != null || event != null || answer['row'] != null || answer['start'] != null) {
      out[single] = ItemPlace(band: band, event: event, row: num2int(answer['row']), start: num2double(answer['start']), end: num2double(answer['end']));
    }
  }
  return out;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 갈래 등록 — 어느 창이 열리는가
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 상세 창의 갈래를 모두 등록한다. 앱을 세울 때 한 번 부른다(명세 2-2).
void registerDetailKinds() {
  registerItemDetail();
  registerCellDetail();
  registerPeopleDetail();
  registerScopeDetail();
  registerGroupDetail();
  registerKinDetail(); // 승계표 · 세계표 떠 있는 창 · 칸 창의 `승계표에서 보기`(D1)
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. `⋯` 메뉴 — 명세 8-2의 줄에 앱 틀의 안내와 `측정`을 얹어서
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 독의 `⋯`가 여는 메뉴. `context_menu.dart`의 `showDockMenu`는 줄을 더 얹을 길이 없어
/// 명세 8-2의 줄에 [head] · [tail]을 붙여 같은 자리(`showDockMenuRows` — 단추 밑 12 · 오른쪽 끝을 단추에 · 폭 356)에 연다.
Future<void> showShellMenu(
  BuildContext buttonContext, {
  required AppBus bus,
  MenuFlags flags = const MenuFlags(),
  List<MenuRow> head = const [],
  List<MenuRow> tail = const [],
}) {
  return showDockMenuRows(buttonContext, [...head, ...buildMenuRows(bus: bus, flags: flags), ...tail]);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 명령 나누기 · 상태 잇기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 부품들이 낸 말을 듣고 앱이 할 일로 나눈다.
///
/// 듣는 것: `slot('command')`(단축키 · 메뉴) · `bus.go`(가기) · `bus.conditions`(줄 다시 쌓기) ·
/// `bus.selection` · `slot('searchHits')` · `slot('spots')` · `slot('detail')`(밝기) ·
/// `slot('echo')` · `slot('echoHits')`(같은 시기 타국) · `slot('notice')`(알림 한 줄).
class AppGlue {
  AppGlue({
    required this.bus,
    required this.bridge,
    this.onFilter,
    this.onTable,
    this.onImage,
    this.onPacks,
    this.onSearchFocus,
    this.onSearchClose,
    this.onClose,
    this.onNotice,
    this.onChanged,
  });

  final AppBus bus;
  final SceneBridge bridge;

  /// `☰`(F) — 필터 시트를 여닫는다.
  final VoidCallback? onFilter;

  /// `📋`(T) — 표 보기 대화 상자(`showTableDialog`). `📷`(P) — 이미지 대화 상자(`showExportDialog`).
  /// 대화 상자를 띄우려면 화면의 자리(BuildContext)가 있어야 해서 앱이 맡는다 — 이 파일은 무겁게 그리는 것을 들이지 않는다.
  final VoidCallback? onTable, onImage;

  /// `🧩`(D) — 자료집 창.
  final VoidCallback? onPacks;

  /// `🔍`(/) — 검색 칸으로 초점.
  final VoidCallback? onSearchFocus;

  /// Esc가 검색 칸에서 났을 때 — 검색어를 비운다.
  final VoidCallback? onSearchClose;

  /// Esc(창 닫기). 주지 않으면 고른 것을 놓기만 한다.
  final VoidCallback? onClose;

  /// 알림 한 줄(집중 모드 안내 · 같은 해 보기 안내).
  final void Function(String text)? onNotice;

  /// 화면이 다시 그려져야 할 때(상세 창이 여닫히는 따위).
  final VoidCallback? onChanged;

  final owner = HighlightOwner();

  /// 원어 병기 · 글꼴(10건 3 · 9 — 갈래 D2 · names_display.dart): 이름 정보 묻기 · 글꼴 팩 싣기 · 왼쪽 칸 원어 · 표기 설정 기억.
  late final NamesGlue _names = NamesGlue(bus);
  AppMemory? _memory;
  VoidCallback? _unbindConditions;
  int _lookTurn = 0;
  bool _started = false;

  /// 기억. 측정 모드에서는 붙이지 않는다(장면이 달라지면 측정이 무효라 읽지도 쓰지도 않는다).
  AppMemory? get memory => _memory;

  ValueNotifier<Object?> _slot(String name) => bus.slot(name);

  void start() {
    if (_started) return;
    _started = true;
    _slot(slotCommand).addListener(_onCommand);
    _slot(slotNotice).addListener(_onNotice);
    bus.go.addListener(_onGo);
    bus.conditions.addListener(_onConditions);
    bus.selection.addListener(_onSelection);
    _slot(slotSearchHits).addListener(_onSearchHits);
    _slot(slotDetail).addListener(_onDetail);
    _slot(slotSpots).addListener(refreshLook);
    _slot(slotTwins).addListener(refreshLook);
    _slot(slotHouse).addListener(refreshLook);
    _slot(slotEcho).addListener(_onEcho);
    _slot(slotEchoHits).addListener(_onEcho);
    _slot(slotFilters).addListener(_onFilterEcho);
    _slot(slotFilters).addListener(_syncAutoBird);
    _slot(slotClearType).addListener(_onClearType);
    _names.start();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _slot(slotCommand).removeListener(_onCommand);
    _slot(slotNotice).removeListener(_onNotice);
    bus.go.removeListener(_onGo);
    bus.conditions.removeListener(_onConditions);
    bus.selection.removeListener(_onSelection);
    _slot(slotSearchHits).removeListener(_onSearchHits);
    _slot(slotDetail).removeListener(_onDetail);
    _slot(slotSpots).removeListener(refreshLook);
    _slot(slotTwins).removeListener(refreshLook);
    _slot(slotHouse).removeListener(refreshLook);
    _slot(slotEcho).removeListener(_onEcho);
    _slot(slotEchoHits).removeListener(_onEcho);
    _slot(slotFilters).removeListener(_onFilterEcho);
    _slot(slotFilters).removeListener(_syncAutoBird);
    _unbindConditions?.call();
    _unbindConditions = null;
    bus.controller.removeListener(_saveView);
    _slot(slotFilters).removeListener(_saveFilters);
    _slot(legendSlot).removeListener(_saveLegend);
    _slot(slotClearType).removeListener(_onClearType);
    _names.dispose();
  }

  // ---- 상태 읽기 ----

  /// 지금 열린 상세 창의 상태(닫혔으면 닫힌 상태).
  DetailState get detail {
    final value = _slot(slotDetail).value;
    return value is DetailState ? value : const DetailState.closed();
  }

  /// 같은 해 보기 창이 열려 있는가.
  bool get yearOpen => _slot(yearSlot).value != null;

  /// 떠 있는 창이 있는가 — Esc의 셋째 차례(명세 9 ㈐-19).
  bool get windowOpen => detail.open || yearOpen || bus.selection.value != null;

  /// 연표의 오른쪽에서 창이 가린 폭. 가는 길이 이만큼을 피한다 — 나란히 연 문서 칸(760)은 상세 칸 자리를 덮으므로 그 폭이 이긴다.
  double get insetRight {
    final under = detail.open ? detail.inset : (yearOpen ? Ui.detailCover : 0.0);
    final doc = _slot(slotDoc).value != null && _slot(docSideSlot).value == true ? DocUi.sideWidth : 0.0;
    return doc > under ? doc : under;
  }

  /// 지금 필터 시트의 값(없으면 기본값).
  FilterState get filters {
    final value = _slot(slotFilters).value;
    return value is FilterState ? value : const FilterState();
  }

  // ---- 명령 나누기 ----

  void _onCommand() {
    final command = _slot(slotCommand).value;
    if (command is! AppCommand) return;
    switch (command.name) {
      case Cmd.filter:
        onFilter?.call();
      case Cmd.table:
        onTable?.call();
      case Cmd.image:
        onImage?.call();
      case Cmd.dlc:
        onPacks?.call();
      case Cmd.fit:
        bus.controller.showAll();
      case Cmd.search:
        onSearchFocus?.call();
      case Cmd.searchClose:
        onSearchClose?.call();
      case Cmd.close:
        if (onClose != null) {
          onClose!.call();
        } else {
          bus.clearSelection();
        }
      case Cmd.bird:
        bird();
      case Cmd.foldAll:
        foldAll();
      case Cmd.detail:
        if (command.uid != null && command.uid!.isNotEmpty) bus.select(command.uid!);
      case Cmd.focusOn:
        if (command.uid != null && command.uid!.isNotEmpty) unawaited(focusOn(command.uid!));
      default:
        // year · legend · measure · motion은 그 부품이 스스로 듣는다. 아직 맡은 이가 없는 것(wiki · scope · fold ·
        // trackWiki · succession · map)은 조용히 넘긴다.
        break;
    }
  }

  /// `↕` · `V` — 조감과 직전 밀도를 오간다(명세 9 ㈐-18).
  void bird() {
    final now = bus.conditions.value.density;
    final memory = _memory;
    // 기억이 없으면(측정 모드) 그 자리에서 뒤집기만 한다.
    final int? target = memory != null ? memory.birdTarget(inBird: now == 2) : (now == 2 ? 0 : 2);
    if (target == null) return; // 자동 조감으로 들어가 있을 때의 '풀기'는 아직 맡은 이가 없다
    setDensity(target);
  }

  /// 밀도를 바꾼다 — 보기 조건과 필터 시트의 값을 한 번에 맞춘다.
  void setDensity(int density) {
    final state = _slot(slotFilters).value;
    if (state is FilterState) _slot(slotFilters).value = state.withDensity(density);
    bus.conditions.value = bus.conditions.value.copyWith(density: density);
  }

  /// `▾ 모든 트랙 접기/펴기` — 다리에 시키고 **된 만큼**을 슬롯에 되적는다(필터 시트가 그 값을 읽는다).
  void foldAll() {
    final want = _slot(slotFoldAll).value != true;
    _slot(slotFoldAll).value = bridge.foldAll(want) && want;
  }

  /// `🎯 여기로 확대` — 그 항목의 자리 · 줄을 받아 데려간다(명세 5-3의 focusOn ①).
  Future<void> focusOn(String uid) async {
    final places = await placesOf([uid]);
    final place = places[uid];
    final start = place?.start;
    if (place == null || start == null) return;
    final end = place.end ?? start;
    final length = (end - start).abs();
    final width = length > 0 ? length * 2.2 : bus.controller.view.span;
    final center = start + length / 2;
    bus.goTo(center - width / 2, center + width / 2, row: place.row, ring: uid);
  }

  // ---- 가기 ----

  void _onGo() {
    final request = bus.go.value;
    if (request == null) return;
    bridge.go(request, insetRight: insetRight);
  }

  // ---- 조건이 바뀌면 줄을 다시 쌓는다 ----

  /// 보기 조건(켠 단 · 밀도 · 조감 모양)이 바뀌었다. 장면의 길로 바꿔야 세로 닻을 잡고 빈 줄 접힘을 그 자리에서 다시 센다(움직임-03).
  /// 밀도는 사람이 고른 것이니 자동 조감에 알리고(조감 말고 다른 것을 고르면 문턱 아래로 내려올 때까지 쉰다),
  /// '지금 자동 조감이 걸려 있는가'는 장면의 판정을 그대로 둔다(버스의 값은 그것을 모른다).
  void _onConditions() {
    final scene = bus.scene, wanted = bus.conditions.value;
    _syncAutoBird();
    var changed = false;
    if (wanted.density != scene.layout.conditions.density) changed = scene.applyDensity(wanted.density);
    changed = scene.applyConditions(wanted.copyWith(autoBird: scene.layout.conditions.autoBird)) || changed;
    if (!changed) return;
    scene.applyLayoutToView();
    scene.requestFrame();
  }

  /// 필터 시트의 `축소하면 조감`을 장면의 자동 조감 스위치로(켜는 순간 지금 보기로 한 번 판정한다). 되돌아갈 밀도는 조감에 들기 전의 것.
  void _syncAutoBird() {
    final state = filters, scene = bus.scene;
    final from = state.density == 2 ? state.birdFrom : state.density;
    if (scene.autoBird == (state.birdAuto, from)) return;
    scene.autoBird = (state.birdAuto, from);
    scene.applyLayoutToView();
    scene.requestFrame();
  }

  // ---- 고르기 → 밝기 ----

  void _onSelection() {
    refreshLook();
    onChanged?.call();
  }

  void _onDetail() {
    // 창이 건 조명 강조는 창이 열려 있는 동안만 산다(명세 3-2 — 창을 닫으면 검색 강조가 되살아난다).
    if (!_lightsSpots) {
      owner.releaseWindow();
    } else {
      // 앞 창이 셈해 둔 메아리는 이 창의 것이 아니다 — 새 창의 [EchoSlot]이 답을 받으면 다시 채운다.
      if (_slot(slotEchoHits).value != null) _slot(slotEchoHits).value = null;
      owner.setWindow(_windowHighlight());
    }
    refreshLook();
    onChanged?.call();
  }

  /// 필터 시트의 '같은 시기를 타국에도'를 스위치 자리에 옮겨 적는다 — 어느 쪽을 눌러도 둘이 한 값이다
  /// (지금 연표의 `setSpotEcho` — 창 안의 체크와 필터의 체크가 같은 설정 `ui.show.spotEcho`다).
  void _onFilterEcho() {
    final state = _slot(slotFilters).value;
    if (state is! FilterState) return;
    final on = state.showing('spotEcho');
    if (_slot(slotEcho).value != on) _slot(slotEcho).value = on;
  }

  /// 메아리 스위치 · `echo`의 답이 바뀌었다 — 창의 강조를 다시 셈하되 **임자는 가로채지 않는다**
  /// (지금 연표의 `setSpotEcho` → `spotHighlight` — 창을 다시 그리지 않고 강조와 묶음만 바꾼다).
  void _onEcho() {
    owner.setWindow(_windowHighlight(), claim: false);
    refreshLook();
  }

  /// 조명을 거는 창의 갈래(지금 연표의 `state.spotKind`) — 칸 · 시기 · 지위와 왕조 · 인물이다.
  /// **이 창들만 강조의 임자가 된다.** 그 밖의 창(기본 상세 · 시대 구분 · 대범위 · 가문)은 강조를 걸지도
  /// 빼앗지도 않아, 검색 강조가 살아 있으면 그대로 둔다(js/viewer.js:474의 `searchOwns`).
  static const spotWindows = {'cell', 'phase', 'rank', 'dynasty', 'figure'};

  bool get _lightsSpots {
    final branch = detail.branch;
    return branch != null && detail.uid.isNotEmpty && spotWindows.contains(branch.id);
  }

  /// 지금 열린 창이 연표에 거는 조명 강조(없으면 null) — 지금 연표의 `spotHighlight`(js/viewer.js:2114) 그대로.
  ///
  /// 칸 · 시기 · 지위 창(`always`)은 **늘**, 왕조 · 인물 창은 **메아리를 켰을 때만** 건다.
  /// 강조에 드는 것은 창이 고른 것과 제 조명에 든 사건(`ownUids`)이다.
  List<String>? _windowHighlight() {
    if (!_lightsSpots) return null;
    final hits = echoHits;
    if (!detail.always && !(echoOn && hits != null)) return null;
    return [detail.uid, if (hits != null) ...hits.ownUids];
  }

  /// '같은 시기를 타국에도'가 켜져 있는가 — 필터 시트의 `show.spotEcho`와 **한 설정**이다(기본 끔).
  /// 읽는 차례는 [EchoSlot]과 같다(필터 값이 있으면 그것이 먼저).
  bool get echoOn {
    final state = _slot(slotFilters).value;
    if (state is FilterState) return state.showing('spotEcho');
    return _slot(slotEcho).value == true;
  }

  /// 열린 창이 셈해 둔 메아리에서 연표가 쓰는 것(`detail_echo.dart`의 [EchoSlot]이 싣는다).
  EchoHits? get echoHits {
    final value = _slot(slotEchoHits).value;
    return value is EchoHits ? value : null;
  }

  void _onSearchHits() {
    final value = _slot(slotSearchHits).value;
    owner.setSearch(value is List ? [for (final one in value) if (one is String) one] : null);
    refreshLook();
  }

  /// 지금 상태로 [Look]을 지어 다리에 건넨다. uid → 타일 번호는 자료 처리부에 묻는다(늦게 온 답은 버린다).
  void refreshLook() => unawaited(_buildLook());

  Future<void> _buildLook() async {
    final turn = ++_lookTurn;
    final pick = bus.selection.value;
    final state = detail;
    final hits = owner.uids ?? const <String>[];
    final spots = _spotRequests();
    final twinAsk = twinRequests(_slot(slotTwins).value);
    final wanted = <String>{
      if (pick != null) pick.uid,
      ...hits,
      for (final one in spots) one.$1,
      for (final one in twinAsk) one.$1,
    };
    final places = wanted.isEmpty ? const <String, ItemPlace>{} : await placesOf(wanted.toList());
    if (turn != _lookTurn) return;

    final me = pick == null ? null : places[pick.uid];
    final bands = <int>{}, events = <int>{};
    for (final uid in hits) {
      final place = places[uid];
      if (place?.band != null) bands.add(place!.band!);
      if (place?.event != null) events.add(place!.event!);
    }
    final filtered = bands.isNotEmpty || events.isNotEmpty;
    final house = _slot(slotHouse).value;
    final echo = echoOn;
    // 같은 시기 타국의 사건(메아리) — 강조 밖이어도 흐리지 않는다. 스위치를 켰을 때만이고,
    // 창이 강조의 임자일 때만 걸린다(검색 강조가 이기고 있으면 연표는 검색의 답을 쓴다).
    final byWindow = owner.owner == HiOwner.window;
    final echoing = byWindow && echo ? echoHits : null;
    // 같은 사람의 칸(건의 8의 6-나): 띠 번호를 아는 자리만 — 둘 이상일 때만 싣는다(혼자면 테가 없다).
    // 그 자리들의 나라(띠)는 고른 나라처럼 흐리지 않는다.
    final twins = <String>{
      for (final one in twinAsk)
        if (places[one.$1]?.band != null) '${places[one.$1]!.band}|${one.$2}',
    };
    final twinBands = <int>{
      for (final one in twinAsk)
        if (places[one.$1]?.band != null) places[one.$1]!.band!,
    };

    bridge.emphasize(
      Look(
        band: state.pick ? me?.band : null,
        event: state.pick || pick != null ? (me?.event ?? pick?.eventId) : null,
        // 같은 줄의 띠를 밝게 남기는 것(`is-onrow`)은 **사건을 골랐을 때만**이다(지금 연표 `_applyStates` — 고른 사건이 놓인 줄의 띠들).
        // 띠를 골랐을 때까지 줄을 실으면 같은 줄의 다른 나라가 흐려지지 않아 고른 나라가 도드라지지 않는다.
        row: state.lane && (me?.event != null || pick?.eventId != null) ? (me?.row ?? _rowOfEvent(pick?.eventId)) : null,
        cell: pick?.cell,
        bands: filtered ? bands : null,
        events: filtered ? events : null,
        echo: echoing?.echoIds.toSet(),
        // 왕조 · 인물 창의 강조는 사건 배치에 쓰지 않는다(명세 9 ㈐-2). 검색 강조는 늘 쓴다.
        layout: byWindow ? state.always : true,
        lit: byWindow && echo,
        // 구간(기간 조명)은 **메아리 스위치와 상관없이** 늘 보낸다 — 지금 연표의 `_isSpot`(js:2175)도 `this.spots`만 보고
        // 칸 층(`paint/strips.dart`)이 그 값으로 짙은 칸을 그린다. 여기서 비우면 메아리를 끈 기본 설정에서 기간 조명이 통째로 사라진다
        // (11물결 bands3 ㈑의 제안은 이 길을 지우므로 따르지 않았다 — `test/wiring_audit_test.dart`가 그 회귀를 잡는다).
        // 띠 · 이름표 층이 거두는 160ms은 제 층에서 `lit` · `litMoving`으로 가린다.
        spots: [
          for (final one in spots)
            if (places[one.$1]?.band != null) Spot(places[one.$1]!.band!, one.$2, one.$3, cell: one.$4),
        ],
        // 가문 강조 · 가문 조명(D1 결정 7 A · 확정 설계 5-3 — 본가를 누르면 아래 파의 칸도 함께, 성씨면 그 성의 가문 모두):
        // [house]는 누른 가문 하나(인물 막대 층이 읽는다), [houses]는 조명된 가문 id 묶음. 구간은 [spots]로 함께 온다.
        house: houseLit(house).house,
        houses: houseLit(house).houses,
        // 강조에 든 인물(막대 층이 --warn 테두리를 그린다) — 인물 uid만 막대가 집는다.
        figures: hits.isEmpty ? null : hits.toSet(),
        twins: twins.length < 2 ? null : twins,
        twinBands: twins.length < 2 ? null : twinBands,
      ),
    );
  }

  /// 인물 · 칸 창이 실은 조명(`[{uid, start, end, cell?}]`)을 읽는다.
  List<(String, double, double, String?)> _spotRequests() {
    final value = _slot(slotSpots).value;
    if (value is! List) return const [];
    final out = <(String, double, double, String?)>[];
    for (final one in value) {
      if (one is! Map) continue;
      final uid = one['uid'], start = one['start'], end = one['end'], cell = one['cell'];
      if (uid is! String || uid.isEmpty || start is! num || end is! num) continue;
      out.add((uid, start.toDouble(), end.toDouble(), cell is String ? cell : null));
    }
    return out;
  }

  /// 같은 사람의 자리 부탁(`[{uid, cell}]` — 칸 창이 슬롯 `twins`에 싣는 꼴)을 `(uid, 칸 참조)`로 읽는다.
  static List<(String, String)> twinRequests(Object? value) {
    if (value is! List) return const [];
    return [
      for (final one in value)
        if (one is Map && one['uid'] is String && one['cell'] is String && (one['uid'] as String).isNotEmpty && (one['cell'] as String).isNotEmpty)
          (one['uid'] as String, one['cell'] as String),
    ];
  }

  /// 연표에서 누른 사건의 줄(기록에 자리가 없을 때 쓰는 값).
  int? _rowOfEvent(int? eventId) => eventId == null ? null : (bus.scene.selectedEventRow >= 0 ? bus.scene.selectedEventRow : null);

  /// uid 묶음 → 타일의 번호와 자리. `ids_of`가 없으면 `id_of`를 하나씩, 그것도 없으면 빈 표(= 빈 Look).
  Future<Map<String, ItemPlace>> placesOf(List<String> uids) async {
    if (uids.isEmpty) return const {};
    final asked = uids.length > 2000 ? uids.sublist(0, 2000) : uids; // 계약 2-1: 한 번에 2000개까지
    try {
      return readPlaces(await bus.ask({'op': 'ids_of', 'uids': asked}));
    } catch (_) {
      // ids_of를 아직 모르는 자료 처리부
    }
    final out = <String, ItemPlace>{};
    for (final uid in asked) {
      try {
        out.addAll(readPlaces(await bus.ask({'op': 'id_of', 'uid': uid}), single: uid));
      } catch (_) {
        return out;
      }
    }
    return out;
  }

  // ---- 연표에서 누른 것 ----

  /// 연표에서 사건을 눌렀다 — 항목 기록의 열쇠를 받아 고른다. 이름이 없는 사건이면 그 점만 밝힌다.
  Future<void> pickEvent(int eventId, {int row = -1}) async {
    final uid = await uidOfEvent(bus, eventId);
    if (uid == null) {
      bridge.emphasize(Look(event: eventId, row: row >= 0 ? row : null));
      return;
    }
    bus.select(uid, kind: 'event', eventId: eventId);
  }

  // ---- 알림 한 줄 ----

  void _onNotice() {
    final text = _slot(slotNotice).value;
    if (text is String && text.isNotEmpty) onNotice?.call(text);
  }

  // ---- 기억 ----

  /// 기억을 붙인다: 켠 단 · 밀도는 [AppMemory.bindConditions]가, 필터 시트의 값은 제 꼴 그대로 `parts['filters']`가 맡는다.
  /// **측정 모드에서는 부르지 않는다**(장면이 달라지면 측정이 무효).
  void attachMemory(AppMemory memory) {
    _memory = memory;
    _unbindConditions = memory.bindConditions(bus.conditions);
    _names.attachMemory(memory); // 표기 설정(parts['names'] — 고를 때만 적힌다)
    final saved = memory.parts['filters'];
    if (saved != null) {
      final state = FilterState.fromJson(saved);
      _slot(slotFilters).value = state;
      bus.conditions.value = state.toConditions();
    }
    _slot(legendSlot).value = memory.ui.legend;
    _slot(slotKinFold).value = memory.ui.kinFold; // 승계표 · 세계표가 읽고 적는다(제가 400ms 모아 쓴다)
    // 상세 창 묶음의 접힘(감독 건의 2026-10-14 3번) — 제목마다 · 다음 실행에도.
    DetailFolds.instance.load(memory.parts['detailFold']);
    DetailFolds.instance.onChanged = () {
      memory.parts['detailFold'] = DetailFolds.instance.toJson();
      memory.save();
    };
    _slot(slotFilters).addListener(_saveFilters);
    _slot(legendSlot).addListener(_saveLegend);
    bus.controller.addListener(_saveView);
  }

  void _saveFilters() {
    final memory = _memory;
    final state = _slot(slotFilters).value;
    if (memory == null || state is! FilterState) return;
    memory.parts['filters'] = state.toJson();
    memory.ui.filterOpen = state.filterOpen;
    memory.save();
  }

  void _saveLegend() {
    final memory = _memory;
    if (memory == null) return;
    memory.ui.legend = _slot(legendSlot).value == true;
    memory.save();
  }

  /// 메뉴 '글자 › ClearType'을 골랐다 — 설정을 바꾸고 기억에 남긴 뒤(측정 모드는 기억 없이 설정만) 장면을 한 장 더 그리게 한다.
  /// 그림판이 장면마다 설정을 읽으므로, 멈춘 장면도 곧바로 회색 ↔ ClearType으로 바뀐다.
  void _onClearType() {
    final value = _slot(slotClearType).value;
    if (value is! bool || value == ClearTypePrefs.on) return;
    final memory = _memory;
    if (memory == null) {
      ClearTypePrefs.on = value;
    } else {
      ClearTypePrefs.save(memory, value);
    }
    bus.scene.requestFrame();
  }

  double _savedLo = double.nan, _savedHi = double.nan;

  void _saveView() {
    final memory = _memory;
    if (memory == null) return;
    final v = bus.controller.view;
    if (v.lo == _savedLo && v.hi == _savedHi) return;
    _savedLo = v.lo;
    _savedHi = v.hi;
    memory.setView(v.lo, v.hi); // 400ms 모아 쓰기는 AppMemory가 한다
  }

  /// 필터 시트가 열려 있는가를 한 값으로 둔다(명세 6-4 — 시트의 값과 앱 틀의 열림이 갈라지지 않게).
  void setFilterOpen(bool open) {
    final state = filters;
    if (state.filterOpen != open) _slot(slotFilters).value = state.copyWith(filterOpen: open);
  }

  /// 메뉴의 ✓ 상태.
  MenuFlags menuFlags({bool measuring = false, bool hasMap = false}) {
    final memory = _memory;
    final state = filters;
    final base = memory != null
        ? MenuFlags.from(
            memory,
            measuring: measuring,
            bird: state.density == 2,
            zen: zenOf(bus),
            allFolded: _slot(slotFoldAll).value == true,
            hasMap: hasMap,
            clearType: ClearTypePrefs.on,
            clearTypeShown: ClearTypePrefs.shown,
          )
        : MenuFlags(
            measuring: measuring,
            bird: state.density == 2,
            filterOpen: state.filterOpen,
            legend: _slot(legendSlot).value == true,
            allFolded: _slot(slotFoldAll).value == true,
            zen: zenOf(bus),
            hasMap: hasMap,
            scopesOn: _scopesOn(),
            clearType: ClearTypePrefs.on,
            clearTypeShown: ClearTypePrefs.shown,
          );
    return base;
  }

  Map<String, bool> _scopesOn() {
    final value = _slot(slotScopes).value;
    if (value is Map) {
      return {
        for (final one in value.entries)
          if (one.key is String && one.value is bool) one.key as String: one.value as bool,
      };
    }
    return const {};
  }

  // ---- 트랙 · 분류 표 ----

  /// `{"op":"layout"}`의 답에서 트랙 · 분류의 이름과 색을 뽑아 슬롯에 둔다(상세 창의 배지가 읽는다).
  /// 트랙에 `key`가 아직 없으므로 **번호를 적은 글**을 열쇠로도 함께 둔다.
  void fillTrackSlots(Map<String, dynamic> layout) {
    Map<String, Map<String, Object?>> table(Object? list, int fallbackColor) {
      final out = <String, Map<String, Object?>>{};
      if (list is! List) return out;
      for (final one in list) {
        if (one is! Map) continue;
        final entry = <String, Object?>{'name': '${one['name'] ?? ''}', 'color': one['color'] ?? fallbackColor};
        final key = one['key'], id = one['id'];
        if (key is String && key.isNotEmpty) out[key] = entry;
        if (id != null) out['$id'] = entry;
      }
      return out;
    }

    _slot(slotTracks).value = table(layout['tracks'], 0xc27a45);
    _slot(slotCategories).value = table(layout['categories'], 0x9a8e7c);
  }
}

/// `slot('house')`의 값 → 누른 가문 하나와 조명된 가문 id 묶음(D1-N3 `Look.house` · `Look.houses`).
///
/// 받는 꼴: 가문 id 글 하나(가문 창 — 아래 파가 없는 가문 · 옛 꼴) · `{'house': 누른 가문 id, 'houses': [자기, …아래 파]}`(아래 파가 있는 가문) ·
/// `{'houses': [그 성의 가문 · 아래 파 …]}`(성씨 창 — 누른 가문이 없다) · 글 목록. 비었으면 둘 다 null(조명 없음).
({String? house, Set<String>? houses}) houseLit(Object? value) {
  List<String> ids(Object? list) => [
    if (list is String && list.isNotEmpty) list,
    if (list is Iterable)
      for (final one in list)
        if (one is String && one.isNotEmpty) one,
  ];
  if (value is String) return value.isEmpty ? (house: null, houses: null) : (house: value, houses: {value});
  if (value is Map) {
    final house = value['house'];
    final all = {...ids(value['houses']), if (house is String && house.isNotEmpty) house};
    return (house: house is String && house.isNotEmpty ? house : null, houses: all.isEmpty ? null : all);
  }
  final all = ids(value);
  return (house: null, houses: all.isEmpty ? null : all.toSet());
}

/// 보기 폭에 맞는 날짜의 자세함(0 해 · 1 달 · 2 날 · 3 시) — 묶음 카드의 머리글이 쓴다.
int viewPrecision(double span) {
  const year = 525960.0;
  final years = span / year;
  return years > 12 ? 0 : (years > .75 ? 1 : (years > 4 / 365.25 ? 2 : 3));
}

/// 누른 알약 하나를 묶음 카드가 아는 꼴로(연표의 맞히기는 통의 범위만 알려 준다).
ClusterSpanLike clusterOf(Hit hit) => ClusterSpanLike(row: hit.row, lo: hit.lo, hi: hit.hi);

/// `cards.dart`의 `ClusterSpan`을 짓는 데 필요한 값만 담은 것(그 파일을 이 파일이 들이지 않으려고).
@immutable
class ClusterSpanLike {
  const ClusterSpanLike({required this.row, required this.lo, required this.hi});
  final int row;
  final double lo, hi;

  /// 같은 묶음인지 가리는 열쇠.
  String get key => '$row@${lo.round()}~${hi.round()}';
}

/// 나라 기록의 같은 사람 짝 표(건의 8의 6-나): `x_persons`의 칸 참조 → 그 사람의 다른 칸 `[(나라 uid, 칸 참조)]`. 기록이 없으면 빈 표.
/// 커서가 올라간 칸의 짝을 찾는 앱 틀(archive_app)이 나라마다 한 번 짓는다.
Map<String, List<(String, String)>> twinTableOf(Map<String, dynamic>? entity) {
  final persons = entity?['x_persons'];
  if (persons is! Map) return const {};
  final out = <String, List<(String, String)>>{};
  persons.forEach((ref, v) {
    final others = v is Map ? v['others'] : null;
    if (ref is! String || others is! List) return;
    final list = [
      for (final q in others)
        if (q is Map && q['uid'] is String && q['ref'] is String && (q['uid'] as String).isNotEmpty && (q['ref'] as String).isNotEmpty) (q['uid'] as String, q['ref'] as String),
    ];
    if (list.isNotEmpty) out[ref] = list;
  });
  return out;
}
