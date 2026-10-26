import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show LongPressGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/line_icon.dart';
import '../shell/motion_widgets.dart';
import '../motion.dart';
import '../shell/sheet_look.dart';
import '../shell/sheet_parts.dart';
import 'app_bus.dart';
import 'app_memory.dart';
import 'doc_window.dart' show docFrontKey;
import 'shell_keys.dart';

// `⋯` 단추와 연표 위 오른쪽 클릭으로 여는 메뉴 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md`의 8-2.
// 꼴은 서고 폴더 '차림표'(감독 고름 G5 #9 — 다듬기 판 `sm-menu` · 계획 4단계 과제 9 '틀의 시트와 창'): 묶음 = 상자(제목 줄이 뚜껑의 흰 라벨) ·
// 줄 = 실에 꿴 흰 꼬리표 · 승계선 = 종이 사슬 · 글자 = 열쇠표 · 안내 줄 = 폴더 맨 위 글. `⋯` 단추면 탭이 오른쪽 · 단추 밑 · 폭 356.
// 세계표 · 승계표 수준 · 앱 메뉴의 작은 차림표도 같은 폴더다(제목 줄이 없으면 줄을 폴더에 바로 매단다).
// 줄이 하는 일은 모두 bus.slot('command')에 실리는 명령 하나다(shell_keys.dart의 [Cmd]).

/// 손가락 · 펜으로 길게 눌러 메뉴를 여는 데 드는 시간. 기본값(500ms)은 휴대폰에서 끌기 · 누름을 하다가도 메뉴가 튀어나와
/// 감독 검토(2026-09-22 · 실기기)로 늘렸다. 연표 화면의 '길게 누른 손가락은 떼어도 고르지 않는다'도 이 값을 쓴다.
const menuLongPress = Duration(milliseconds: 900);

/// 항목의 구분 말(지금 연표의 `HT.ITEM_WORDS`).
const itemWords = <String, String>{
  'period': '시대',
  'event': '사건',
  'organ': '기관',
  'culture': '문화',
  'dynasty': '왕조',
  'epoch': '시대 구분',
  'figure': '인물',
  'house': '가문',
  'treaty': '조약',
  'scope': '대범위',
  'people': '민족',
  'track': '트랙',
  'category': '분류',
  'cell': '칸',
};

/// 메뉴를 연 자리에서 모아 온 것(명세 8-2의 `{uid, trackId, t}`).
/// [trackName] · [folded]는 트랙 줄의 글에 쓰고, [at]은 `📍 〈때〉에 무슨 일이`에 쓴다(분).
@immutable
class MenuSpot {
  const MenuSpot({this.uid, this.trackId, this.trackName = '', this.at, this.folded = false, this.scope, this.scopeName = '', this.scopeState = ''});
  final String? uid;
  final int? trackId;
  final String trackName;
  final double? at;
  final bool folded;

  /// 그 자리를 품은 가장 안쪽 그릇(폴더 · 상자)의 uid · 이름 · 지금 상태의 이름(장면 ScopeState의 이름 — 'open' · 'shelf' · 'closed' · 'loose' ·
  /// 없으면 빈 글). 그릇 밖이면 null. 메뉴 차례와 ScopeState 차례가 달라(과제 7 걸음 5) 번호가 아니라 이름으로 ✓를 맞춘다.
  final String? scope;
  final String scopeName;
  final String scopeState;
}

/// 그릇의 네 상태(메뉴 글 · 명령의 arg — 장면 ScopeState의 이름). 차례는 메이커 서고 미리보기의 차림표(js/viewer.js menuItems)와 같다 —
/// 펼침 · 선반 · 접음 · 풂(선반은 과제 7 · 펼친 채 상위 다섯만 제 줄 · 나머지는 폴더 발의 작은 꼬리표). ScopeState의 차례(open · closed · loose · shelf)와 다르다.
const scopeStates = [('open', '펼침'), ('shelf', '선반'), ('closed', '접음'), ('loose', '풂')];

/// 메뉴에 ✓로 나오는 지금 상태. 켜고 끈 것은 거의 다 기억(`AppMemory`)에 있다(명세 8-4).
@immutable
class MenuFlags {
  const MenuFlags({
    this.measuring = false,
    this.bird = false,
    this.filterOpen = false,
    this.legend = false,
    this.allFolded = false,
    this.zen = false,
    this.motion = false,
    this.hasMap = false,
    this.succession = Succession.all,
    this.scopesOn = const <String, bool>{},
    this.lensName,
    this.clearType = true,
    this.clearTypeShown = false,
  });

  /// 기억에서 읽어 채운다. 기억에 없는 것(기간 재기 · 움직임 계측 · 조감 여부 · 모두 접힘 · ClearType)은 부르는 쪽이 준다.
  factory MenuFlags.from(
    AppMemory memory, {
    bool measuring = false,
    bool bird = false,
    bool zen = false,
    bool allFolded = false,
    bool motion = false,
    bool hasMap = false,
    bool clearType = true,
    bool clearTypeShown = false,
  }) =>
      MenuFlags(
        measuring: measuring,
        bird: bird || memory.ui.density == 2,
        filterOpen: memory.ui.filterOpen,
        legend: memory.ui.legend,
        allFolded: allFolded,
        zen: zen,
        motion: motion,
        hasMap: hasMap,
        succession: memory.ui.show.succession,
        scopesOn: memory.ui.scopes,
        clearType: clearType,
        clearTypeShown: clearTypeShown,
      );

  final bool measuring, bird, filterOpen, legend, allFolded, zen, motion, hasMap;
  final Succession succession;
  final Map<String, bool> scopesOn;

  /// '글자 › ClearType' 줄: [clearTypeShown]은 줄을 보일 때(Windows에서 켜 볼 수 있을 때만), [clearType]은 지금 켜져 있는가(✓).
  final bool clearType, clearTypeShown;

  /// 렌즈 줄(감독 선택 D5 결정 6 B): 켠 렌즈의 주제 이름(꺼져 있으면 빈 글) — '◎ 렌즈 · 주제' 줄.
  /// null이면 렌즈 부품이 없는 것(부품만 띄운 검사) — 그 줄을 넣지 않는다. 앱은 늘 부품을 잇는다(`ui/theme_lens.dart`).
  final String? lensName;
}

/// 상세 창이 읽는 항목 기록(`{"op":"entity"}`)에서 메뉴가 쓰는 것만 꺼낸 것.
@immutable
class EntityBrief {
  const EntityBrief({required this.uid, required this.kind, required this.name, this.scopes = const []});
  final String uid, kind, name;

  /// 이 항목이 든 대범위(제 것 · 본국으로 품은 것) — 메뉴의 `대범위 모아 보기:` 줄.
  final List<MenuScope> scopes;

  String get word => itemWords[kind] ?? '항목';
}

/// 대범위 하나(uid와 이름만).
@immutable
class MenuScope {
  const MenuScope(this.uid, this.name);
  final String uid, name;
}

/// `{"op":"entity","uid":…}`의 답 `{uid, kind, json}`을 읽는다. 답이 비었거나 json이 깨졌으면 null.
EntityBrief? entityBrief(Map<String, dynamic>? answer) {
  if (answer == null) return null;
  final uid = answer['uid'];
  if (uid is! String || uid.isEmpty) return null;
  final kind = answer['kind'] is String ? answer['kind'] as String : '';
  Map<String, dynamic> item = const {};
  final raw = answer['json'];
  try {
    if (raw is String && raw.isNotEmpty) item = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (raw is Map) item = Map<String, dynamic>.from(raw);
  } catch (_) {
    item = const {};
  }
  final name = (item['title'] ?? item['name'] ?? '').toString();
  // 뿌리가 아닌 곳의 항목은 {"$ref": uid, "name": 이름}이다(계약 6-9).
  List<MenuScope> refs(Object? list) => list is List
      ? [
          for (final one in list)
            if (one is Map && one[r'$ref'] is String) MenuScope(one[r'$ref'] as String, (one['name'] ?? '').toString()),
        ]
      : const [];
  return EntityBrief(uid: uid, kind: kind, name: name, scopes: kind == 'scope' ? [MenuScope(uid, name)] : [...refs(item['scopes']), ...refs(item['hostedScopes'])]);
}

/// 누른 항목의 기록을 물어 온다. 자료 처리부가 아직 `entity`를 모르면 null(메뉴는 항목 줄 없이 열린다).
Future<EntityBrief?> askEntity(AppBus bus, String uid) async {
  try {
    return entityBrief(await bus.ask({'op': 'entity', 'uid': uid}));
  } catch (_) {
    return null;
  }
}

/// 이름이 길면 20자에서 줄인다(지금 연표의 메뉴 제목과 같은 규칙).
String cutName(String name, [int limit = 20]) => name.length > limit ? '${name.substring(0, limit)}…' : name;

/// 오른쪽 클릭한 자리의 때를 확대 정도에 맞춰 적고, 그 단위의 처음으로 맞춘 시각을 함께 돌려준다.
/// 명세 7-1의 `panelPrec`: 보기 폭 < 2/12년 → 날 · < 2년 → 달 · 그 밖 해.
(String, double) whenAt(double minute, double span) {
  const year = 525960.0;
  final at = DateTime.fromMillisecondsSinceEpoch((minute * 60000).floor(), isUtc: true);
  final yearText = at.year > 0 ? '${at.year}년' : '기원전 ${1 - at.year}년';
  DateTime snapped;
  String text;
  if (span < year * 2 / 12) {
    snapped = DateTime.utc(at.year, at.month, at.day);
    text = '$yearText ${at.month}월 ${at.day}일';
  } else if (span < year * 2) {
    snapped = DateTime.utc(at.year, at.month);
    text = '$yearText ${at.month}월';
  } else {
    snapped = DateTime.utc(at.year);
    text = yearText;
  }
  return (text, snapped.millisecondsSinceEpoch / 60000);
}

/// 제목 줄([MenuRow.title])이 여는 묶음의 그리는 꼴(감독 고름 G5 #9 — 차림표 다듬기 판 `sm-menu`).
enum MenuGroup {
  /// 실에 꿴 흰 꼬리표 줄(기본).
  list,

  /// 하나 고르기 — 종이 사슬(승계선: 모두 · 직접만 · 숨김). 켠 줄([MenuRow.checked])이 고른 고리.
  chain,

  /// 켜고 끄기 — 열쇠표(글자: ClearType). 바로 앞 묶음이 사슬이면 한 줄에 상자 둘로 선다.
  keys,
}

/// 메뉴 한 줄. 구분선 · 제목 · 안내 줄은 누를 수 없다.
/// 서고 꼴(감독 고름 G5 #9): 제목 줄 = 상자 뚜껑의 흰 라벨(묶음을 연다) · 구분선 = 상자 안 작은 묶음 틈 6(제목 앞이면 상자 사이) ·
/// 안내 줄 = 폴더 맨 위 글. [icon]은 이름 앞의 선 아이콘(15 · 먹 60 — 예전의 그림 글자 📍 📏 …를 갈음, 건의 8의 1번).
/// 켠 줄([checked])은 꼬리표 구멍을 먹 85로 칠하고 이름을 굵게 쓴다(예전의 체크 그림 대신).
@immutable
class MenuRow {
  const MenuRow(this.label, {this.keyText = '', this.checked = false, this.enabled = true, this.danger = false, this.onSelected, this.icon})
    : sep = false, header = false, note = false, group = MenuGroup.list;
  const MenuRow.sep()
    : label = '', keyText = '', checked = false, enabled = false, danger = false, onSelected = null, icon = null, sep = true, header = false, note = false, group = MenuGroup.list;

  /// 묶음의 제목 — 다음 제목까지의 줄이 이 이름을 뚜껑에 단 상자 하나다. [group]은 그 상자의 그리는 꼴.
  const MenuRow.title(this.label, {this.group = MenuGroup.list})
    : keyText = '', checked = false, enabled = false, danger = false, onSelected = null, icon = null, sep = false, header = true, note = false;

  /// 맨 위의 안내 줄(사건 수 · 원문 수) — 폴더 맨 위 글(12 · 먹 60, 둘이면 둘째는 오른쪽 끝에 먹 45).
  const MenuRow.note(this.label)
    : keyText = '', checked = false, enabled = false, danger = false, onSelected = null, icon = null, sep = false, header = false, note = true, group = MenuGroup.list;

  final String label, keyText;
  final bool checked, enabled, danger, sep, header, note;
  final VoidCallback? onSelected;
  final LineGlyph? icon;

  /// 제목 줄이 여는 묶음의 꼴(제목 줄이 아니면 늘 [MenuGroup.list]).
  final MenuGroup group;
}

/// 메뉴의 줄들(명세 8-2). [item]이 있으면 그 항목의 `자세히 보기`가 맨 위에 온다.
List<MenuRow> buildMenuRows({required AppBus bus, MenuSpot spot = const MenuSpot(), EntityBrief? item, MenuFlags flags = const MenuFlags()}) {
  String key(String name) => Cmd.keyLabel[name] ?? '';
  MenuRow row(String label, String command, {String? uid, int? trackId, double? at, String? arg, bool checked = false, LineGlyph? icon}) => MenuRow(
    label,
    keyText: key(command),
    checked: checked,
    icon: icon,
    onSelected: () => runCommand(bus, command, uid: uid, trackId: trackId, at: at, arg: arg),
  );

  final rows = <MenuRow>[];
  if (item != null) {
    rows.add(MenuRow.title('${item.word} · ${cutName(item.name)}'));
    rows.add(row('자세히 보기', Cmd.detail, uid: item.uid));
    rows.add(row('문서', Cmd.wiki, uid: item.uid, icon: LineGlyph.file));
    rows.add(row('여기로 확대', Cmd.focusOn, uid: item.uid, icon: LineGlyph.locate));
    // 도읍 노선도 카드는 메뉴에 두지 않는다 — 지금 연표는 **왼쪽 줄 이름**과 **상세 창의 노선도 단추** 둘로만 연다(명세 06의 7-19 · 4-2).
    // 대범위 모아 보기는 머리에 한 번 적고 줄에는 이름만(같은 말을 줄마다 되풀이하지 않는다 — 건의 8의 3번).
    if (item.scopes.isNotEmpty) rows.add(const MenuRow.title('대범위 모아 보기'));
    for (final one in item.scopes) {
      rows.add(row(one.name, Cmd.scope, uid: one.uid, checked: flags.scopesOn[one.uid] ?? false));
    }
    rows.add(const MenuRow.sep());
  }
  // 묶음 제목 '보기' · '창' · '그 밖'(감독 고름 G5 #9 — 차림표 다듬기 판대로 상자 뚜껑이 된다). 누르는 줄 · 단축키 · 켬 상태는 그대로.
  rows.add(const MenuRow.title('보기'));
  // 그릇 안을 눌렀으면 그 그릇의 네 상태(리메이크 2부 · 감독 "그릇 옆 버튼 3개 … 그냥 우클릭으로 · 우클릭한 위치가 그 그릇의 안이면" · 선반은 과제 7 걸음 5).
  // 줄 뒤의 작은 회색 글(단축키 자리)에 바뀌는 그릇의 이름(감독 "뒤의 작고 회색 글자로 무슨 그릇이 바뀌는지").
  final scope = spot.scope;
  if (scope != null && scope.isNotEmpty) {
    final name = cutName(spot.scopeName, 12);
    for (final (state, label) in scopeStates) {
      rows.add(MenuRow(label, keyText: name, checked: spot.scopeState == state,
          onSelected: () => runCommand(bus, Cmd.scopeState, uid: scope, arg: state)));
    }
    rows.add(const MenuRow.sep());
  }
  if (spot.trackId != null) {
    rows.add(row(spot.folded ? '${spot.trackName} 펴기' : '${spot.trackName} 접기', Cmd.fold, trackId: spot.trackId, icon: LineGlyph.fold));
    rows.add(row('${spot.trackName} 문서', Cmd.trackWiki, trackId: spot.trackId, icon: LineGlyph.file));
  }
  if (spot.at != null) {
    final (text, at) = whenAt(spot.at!, bus.controller.view.span);
    rows.add(row('$text에 무슨 일이', Cmd.year, at: at, icon: LineGlyph.pin));
  } else {
    rows.add(row('같은 해', Cmd.year, icon: LineGlyph.pin));
  }
  rows.add(const MenuRow.sep());
  rows.add(row('기간 재기', Cmd.measure, checked: flags.measuring, icon: LineGlyph.ruler));
  rows.add(row('전체 보기', Cmd.fit, icon: LineGlyph.expand));
  rows.add(row('조감', Cmd.bird, checked: flags.bird, icon: LineGlyph.bird));
  rows.add(row(flags.allFolded ? '모두 펴기' : '모두 접기', Cmd.foldAll, icon: LineGlyph.fold));
  rows.add(const MenuRow.sep());
  rows.add(const MenuRow.title('창'));
  rows.add(row('필터', Cmd.filter, checked: flags.filterOpen, icon: LineGlyph.menu));
  // 렌즈 차림표(웹의 lens-ui.js가 ⋯ 차림표에 끼우는 한 줄과 같은 자리). 켠 주제의 이름은 렌즈 차림표의 체크로.
  final lensName = flags.lensName;
  if (lensName != null) rows.add(row('렌즈', Cmd.lensMenu, checked: lensName.isNotEmpty, icon: LineGlyph.eye));
  if (flags.hasMap) rows.add(row('지도', Cmd.map, icon: LineGlyph.map));
  // 문서 대문(서재의 문서를 한 번에) — W는 고른 항목의 문서가 먼저라 단축키 글은 적지 않는다.
  rows.add(MenuRow('문서 대문', icon: LineGlyph.library, onSelected: () => runCommand(bus, Cmd.wiki, uid: docFrontKey)));
  rows.add(row('범례', Cmd.legend, checked: flags.legend, icon: LineGlyph.help));
  rows.add(row('표', Cmd.table, icon: LineGlyph.table));
  rows.add(row('이미지 · 인쇄', Cmd.image, icon: LineGlyph.image));
  rows.add(const MenuRow.sep());
  rows.add(const MenuRow.title('승계선', group: MenuGroup.chain));
  rows.add(row('모두', Cmd.succession, arg: 'all', checked: flags.succession == Succession.all));
  rows.add(row('직접만', Cmd.succession, arg: 'direct', checked: flags.succession == Succession.direct));
  rows.add(row('숨김', Cmd.succession, arg: 'off', checked: flags.succession == Succession.off));
  if (flags.clearTypeShown) {
    rows.add(const MenuRow.sep());
    rows.add(const MenuRow.title('글자', group: MenuGroup.keys));
    rows.add(MenuRow('ClearType', checked: flags.clearType, onSelected: () => bus.slot(slotClearType).value = !flags.clearType));
  }
  rows.add(const MenuRow.sep());
  rows.add(const MenuRow.title('그 밖'));
  rows.add(row('DLC 관리', Cmd.dlc, icon: LineGlyph.package));
  rows.add(const MenuRow.sep());
  rows.add(MenuRow('집중 모드', keyText: key(Cmd.zen), checked: flags.zen, icon: LineGlyph.scan, onSelected: () => setZen(bus, !zenOf(bus))));
  rows.add(row('검색', Cmd.search, icon: LineGlyph.search));
  rows.add(const MenuRow.sep());
  rows.add(row('움직임 계측', Cmd.motion, checked: flags.motion, icon: LineGlyph.activity));
  return rows;
}

/// [at](창 좌표)에 메뉴(폴더 '차림표')를 연다. [at]은 폴더의 왼쪽 위(탭 꼭대기) — [alignRight]면 오른쪽 위, [above]면 그 자리의 위쪽으로 펼친다.
/// [tabRight]면 이름 탭이 오른쪽(연 단추 밑), 폭은 [minWidth] 이상 420 이하에서 가장 긴 줄에 맞춘다.
/// 화면 밖으로 나가지 않게 4px 안으로 밀어 넣고, 첫 줄에 초점을 준다. 바깥을 누르거나 Esc로 닫힌다.
Future<void> showTimelineMenu(
  BuildContext context,
  List<MenuRow> rows, {
  required Offset at,
  bool above = false,
  bool alignRight = false,
  bool tabRight = false,
  double minWidth = _menuMinWidth,
}) {
  if (rows.isEmpty) return Future<void>.value();
  return Navigator.of(context, rootNavigator: true).push(_MenuRoute(rows: rows, at: at, above: above, alignRight: alignRight, tabRight: tabRight, minWidth: minWidth));
}

/// `⋯` 단추의 차림표에 [rows]를 연다 — 폴더(폭 356 · 탭이 오른쪽)를 단추 밑 12에 오른쪽 끝을 단추에 맞춰(감독 고름 G5 #9 다듬기 판 `sm-menu`).
Future<void> showDockMenuRows(BuildContext buttonContext, List<MenuRow> rows) {
  final box = buttonContext.findRenderObject() as RenderBox;
  final rightBottom = box.localToGlobal(Offset(box.size.width, box.size.height));
  return showTimelineMenu(
    buttonContext,
    rows,
    at: rightBottom + const Offset(0, SheetLook.menuBelow),
    alignRight: true,
    tabRight: true,
    minWidth: SheetLook.menuWidth,
  );
}

/// `⋯` 단추의 메뉴(명세 8-2의 줄 — 자리는 [showDockMenuRows]).
Future<void> showDockMenu(BuildContext buttonContext, {required AppBus bus, MenuFlags flags = const MenuFlags()}) =>
    showDockMenuRows(buttonContext, buildMenuRows(bus: bus, flags: flags));

/// 작은 차림표(세계표 · 승계표 수준 · 앱 메뉴)의 최소 폭 230(예전 카드와 같음) · 가장 넓은 폭 420 · 화면 끝에서 4 안.
const _menuMinWidth = 230.0, _menuMaxWidth = 420.0, _menuEdge = 4.0;

/// 연표 위 오른쪽 클릭으로 메뉴를 여는 껍데기. 누른 자리에서 [probe]가 무엇을 눌렀는지 찾아 준다
/// (연표의 맞히기는 장면의 몫이라 밖에서 받는다). 상세 창 · 범례 · 입력 칸처럼 위에 뜬 부품은
/// 이 껍데기 밖에 두면 그 부품의 오른쪽 클릭이 여기로 내려오지 않는다.
class ContextMenuArea extends StatelessWidget {
  const ContextMenuArea({super.key, required this.bus, required this.child, required this.probe, this.flagsOf, this.blocked});

  final AppBus bus;
  final Widget child;

  /// 누른 자리(이 껍데기 안의 좌표) → 무엇을 눌렀는가.
  final Future<MenuSpot> Function(Offset local) probe;

  /// 열 때의 ✓ 상태. 주지 않으면 기본값(아무것도 켜지지 않은 꼴).
  final MenuFlags Function()? flagsOf;

  /// 여기서는 열지 않는다(창 좌표) — 상세 창 · 범례 · 문서 창처럼 위에 뜬 부품의 자리.
  /// Flutter에서는 색만 칠한 부품이 누름을 막지 않으므로, 그 부품들의 자리를 여기로 알려 준다.
  final bool Function(Offset global)? blocked;

  Future<void> _open(BuildContext context, Offset local, Offset global) async {
    if (blocked?.call(global) ?? false) return;
    final spot = await probe(local);
    final item = spot.uid == null ? null : await askEntity(bus, spot.uid!);
    if (!context.mounted) return;
    await showTimelineMenu(
      context,
      buildMenuRows(bus: bus, spot: spot, item: item, flags: flagsOf?.call() ?? const MenuFlags()),
      at: global,
      minWidth: SheetLook.menuWidth,
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapUp: (details) => _open(context, details.localPosition, details.globalPosition),
    // 손가락 · 펜에는 오른쪽 버튼이 없다 — 길게 누르면 같은 메뉴가 뜬다(휴대폰). 마우스의 길게 누름은 끌기의 시작이라 치지 않으므로
    // 길게 누름만 받는 안쪽 판을 따로 두고 손가락 · 펜만 듣게 한다(`supportedDevices`는 그 판의 모든 몸짓에 걸린다).
    // 기본 GestureDetector는 길게 누름의 시간을 바꿀 수 없어(500ms 고정) 인식기를 직접 둔다([menuLongPress]).
    child: RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: menuLongPress, supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus}),
          (recognizer) => recognizer.onLongPressStart = (details) => _open(context, details.localPosition, details.globalPosition),
        ),
      },
      child: child,
    ),
  );
}

class _MenuRoute extends PopupRoute<void> {
  _MenuRoute({required this.rows, required this.at, required this.above, required this.alignRight, required this.tabRight, required this.minWidth});
  final List<MenuRow> rows;
  final Offset at;
  final bool above, alignRight, tabRight;
  final double minWidth;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '메뉴 닫기';

  /// 지금 연표의 `.ctx-menu`는 `slide-up .12s ease-out`으로 떠오른다.
  @override
  Duration get transitionDuration => const Duration(milliseconds: Motion.popMs);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: Motion.outMs * 2);

  @override
  void install() {
    _menuKeyboard.value = false; // 열 때마다: 키보드로 옮겨 다니기 전에는 초점 줄을 칠하지 않는다
    super.install();
  }

  // 메뉴는 앱의 화면 나무 밖(길 위)에 서므로 **글자 바탕(Material)을 제 손으로 둔다** — 없으면 Flutter가 글자마다
  // '바탕 없음' 경고 표시인 노란 겹밑줄을 긋는다(감독 검토 2026-09-22 "우클릭할 때 노란 밑줄").
  // 바깥의 Focus는 키가 눌렸는지만 본다(옮겨 다니기는 그대로 아래로 흘린다).
  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondary) => CustomSingleChildLayout(
    delegate: _MenuLayout(at: at, above: above, alignRight: alignRight),
    child: Material(
      type: MaterialType.transparency,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) _menuKeyboard.value = true;
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => MotionPresence(open: animation.status == AnimationStatus.forward || animation.status == AnimationStatus.completed, child: child!),
          child: _MenuCard(rows: rows, tabRight: tabRight, minWidth: minWidth),
        ),
      ),
    ),
  );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
    // 경로의 시간은 수명만 맡는다. 면의 자리·크기·불투명도는 공통 장 한 곳이 쓴다.
    return child;
  }
}

/// 누른 자리에 놓되 화면 밖으로 나가지 않게 4px 안으로 밀어 넣는다. 자리는 온 화소로(폴더의 반 픽셀 테가 화소 한 줄에 앉게).
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.at, required this.above, required this.alignRight});
  final Offset at;
  final bool above, alignRight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.loose(Size(constraints.maxWidth - 2 * _menuEdge, constraints.maxHeight - 2 * _menuEdge));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = alignRight ? at.dx - child.width : at.dx;
    final y = above ? at.dy - child.height : at.dy;
    return Offset(
      math.max(_menuEdge, math.min(x, size.width - child.width - _menuEdge)).roundToDouble(),
      math.max(_menuEdge, math.min(y, size.height - child.height - _menuEdge)).roundToDouble(),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.at != at || old.above != above || old.alignRight != alignRight;
}

/// 이 메뉴에서 키보드를 썼는가 — 초점이 간 줄을 칠할지 가린다. 마우스로 연 메뉴는 첫 줄에 초점이 저절로 가는데(키보드로 곧바로
/// 옮겨 다닐 수 있게), 그것까지 손을 올린 것처럼 주황으로 칠하면 첫 줄이 고른 것처럼 보인다(감독 검토 2026-09-22).
final _menuKeyboard = ValueNotifier<bool>(false);


/// 차림표 줄을 폴더의 짜임으로 가른 묶음 하나 — 제목 줄([MenuRow.title])이 연 상자(제목 없으면 폴더에 바로 매단 줄) · 작은 묶음(구분선으로 가름).
class _MenuBunch {
  _MenuBunch(this.title, this.group);
  final String? title;
  final MenuGroup group;
  final subs = <List<MenuRow>>[[]];

  Iterable<MenuRow> get rows => subs.expand((s) => s);
}

/// 줄 목록 → 맨 위 안내 글 · 묶음. 구분선은 상자 안의 작은 묶음 틈이고, 제목 앞 · 끝의 구분선은 상자 사이라 버린다.
({List<MenuRow> notes, List<_MenuBunch> bunches}) _menuPlan(List<MenuRow> rows) {
  final notes = <MenuRow>[];
  final bunches = <_MenuBunch>[];
  _MenuBunch? now;
  for (final row in rows) {
    if (row.note) {
      notes.add(row);
    } else if (row.header) {
      bunches.add(now = _MenuBunch(row.label, row.group));
    } else if (row.sep) {
      if (now != null && now.subs.last.isNotEmpty) now.subs.add([]);
    } else {
      if (now == null) bunches.add(now = _MenuBunch(null, MenuGroup.list));
      now.subs.last.add(row);
    }
  }
  for (final b in bunches) {
    b.subs.removeWhere((s) => s.isEmpty);
  }
  bunches.removeWhere((b) => b.subs.isEmpty);
  return (notes: notes, bunches: bunches);
}

/// 차림표 = 서고 폴더 '차림표'(감독 고름 G5 #9 다듬기 판 `sm-menu` · 목업 g-sheet-menu `drawMenu` — git 밖):
/// 안내 줄 = 폴더 맨 위 글 · 묶음 = 상자(제목 줄이 뚜껑의 흰 라벨) · 줄 = 뚜껑 밑선의 매듭에서 내려온 실에 꿴 흰 꼬리표(24 · 사이 4 · 작은 묶음 틈 6) ·
/// 승계선 = 종이 사슬 · 글자 = 열쇠표(둘이 있으면 한 줄에 상자 둘). 폭은 [minWidth] 이상 420 이하에서 가장 긴 줄에 맞추고, 키가 넘치면 폴더 안에서 넘긴다.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.rows, required this.tabRight, required this.minWidth});
  final List<MenuRow> rows;
  final bool tabRight;
  final double minWidth;

  static const _boxPad = EdgeInsets.fromLTRB(SheetLook.boxInset, SheetLook.menuTop, SheetLook.boxInset, SheetLook.menuBottom);

  @override
  Widget build(BuildContext context) {
    final plan = _menuPlan(rows);
    var first = true;

    /// 고르면 메뉴를 먼저 닫고 그다음에 줄의 일을 한다(줄 꼬리표와 같은 차례).
    VoidCallback? pick(MenuRow row) => row.enabled && row.onSelected != null
        ? () {
            Navigator.of(context).pop();
            row.onSelected!();
          }
        : null;

    Widget list(_MenuBunch b) {
      final children = <Widget>[];
      final breaks = <int>{};
      for (final sub in b.subs) {
        if (children.isNotEmpty) breaks.add(children.length);
        for (final row in sub) {
          final enabled = row.enabled && row.onSelected != null;
          children.add(_MenuItemView(row: row, enabled: enabled, autofocus: enabled && first));
          if (enabled) first = false;
        }
      }
      return SheetThreadColumn(gap: SheetLook.menuRowGap, breakBefore: breaks, breakGap: SheetLook.menuSubGap, children: children);
    }

    Widget chain(_MenuBunch b) {
      final items = b.rows.toList();
      final on = items.indexWhere((r) => r.checked);
      return SheetBox(
        label: b.title ?? '',
        padding: _boxPad,
        child: SheetChain<int>(
          items: [for (var i = 0; i < items.length; i++) (i, items[i].label)],
          value: on,
          semantics: b.title,
          onSelect: (i) => pick(items[i])?.call(),
        ),
      );
    }

    Widget keys(_MenuBunch b) => SheetBox(
      label: b.title ?? '',
      padding: _boxPad,
      child: SheetRun(children: [for (final row in b.rows) SheetKeyToggle(label: row.label, on: row.checked, onTap: pick(row))]),
    );

    Widget bunch(_MenuBunch b) => switch (b.group) {
      MenuGroup.chain => chain(b),
      MenuGroup.keys => keys(b),
      MenuGroup.list => b.title == null ? list(b) : SheetBox(label: b.title!, padding: _boxPad, child: list(b)),
    };

    final body = <Widget>[];
    final bunches = plan.bunches;
    for (var i = 0; i < bunches.length; i++) {
      if (body.isNotEmpty) body.add(const SizedBox(height: SheetLook.listBoxGap));
      final b = bunches[i];
      // 사슬 바로 뒤의 열쇠표 묶음은 한 줄에 상자 둘(사슬은 제 폭 · 열쇠표가 나머지).
      if (b.group == MenuGroup.chain && i + 1 < bunches.length && bunches[i + 1].group == MenuGroup.keys) {
        body.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 사슬 상자는 제 고리들만큼(상자 몸은 폭을 늘려 채우므로 펼친 폭으로 못 박는다).
          IntrinsicWidth(child: chain(b)),
          const SizedBox(width: SheetLook.listBoxGap),
          Expanded(child: keys(bunches[i + 1])),
        ]));
        i++;
        continue;
      }
      body.add(bunch(b));
    }

    final notes = plan.notes;
    Widget note(String text, Color color) => Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: sheetText(SheetLook.noteText, color: color));
    final head = notes.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: notes.length == 2
                // 안내 둘(사건 수 · 원문 수)은 한 줄 — 왼쪽 먹 60 · 오른쪽 끝 먹 45.
                ? SizedBox(
                    height: SheetLook.noteLine,
                    child: Row(children: [
                      Flexible(child: note(notes[0].label, SheetLook.ink60)),
                      const SizedBox(width: SheetLook.listPad),
                      const Spacer(),
                      note(notes[1].label, SheetLook.ink45),
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final n in notes) SizedBox(height: SheetLook.noteLine, child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: note(n.label, SheetLook.ink60))),
                  ]),
          );

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: _menuMaxWidth),
      child: IntrinsicWidth(
        child: SheetFolder(
          label: '차림표',
          tabRight: tabRight,
          padding: const EdgeInsets.all(SheetLook.listPad),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (head != null) ...[head, if (body.isNotEmpty) const SizedBox(height: SheetLook.noteGap)],
                ...body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 차림표 줄 하나 = 실에 꿴 흰 꼬리표(24): 아이콘 15 먹 60(왼쪽 17) · 이름 13(왼쪽 40) · 단축키 11 먹 45(오른쪽 11).
/// 켠 줄 = 구멍 칠 먹 85 + 이름 굵게 · 못 누르는 줄 = 테 먹 25 · 글 먹 45(초점 없음) · 올림 · 키보드 초점 = 먹 4 칠 + 테 먹 45.
/// 위험한 일은 색 대신 굵게 쓴다. 누름 · 키(Enter · Space) · 첫 줄 초점 · 키보드를 쓸 때만 초점 줄을 칠함([_menuKeyboard])은 예전 그대로.
class _MenuItemView extends StatefulWidget {
  const _MenuItemView({required this.row, required this.enabled, required this.autofocus});
  final MenuRow row;
  final bool enabled, autofocus;

  /// 줄의 바탕 — 검사가 켬 · 끔 · 올림의 칠과 테를 바로 본다.
  static SheetShape shapeOf({required bool checked, required bool enabled, required bool lit}) => SheetTag.row(on: checked, hover: lit, off: !enabled);

  @override
  State<_MenuItemView> createState() => _MenuItemViewState();
}

class _MenuItemViewState extends State<_MenuItemView> {
  bool _hover = false, _focus = false;

  void _run() {
    Navigator.of(context).pop();
    widget.row.onSelected?.call();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.space && event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    _run();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row, enabled = widget.enabled;
    final lit = enabled && (_hover || (_focus && _menuKeyboard.value));
    final icon = row.icon;
    final ink = enabled ? SheetLook.ink85 : SheetLook.ink45;
    Widget body = SheetTag(
      shape: _MenuItemView.shapeOf(checked: row.checked, enabled: enabled, lit: lit),
      height: SheetLook.menuRow,
      child: Padding(
        padding: const EdgeInsets.only(left: SheetLook.menuIconLeft, right: SheetLook.menuKeyRight),
        child: Row(
          children: [
            if (icon == null)
              const SizedBox(width: SheetLook.menuIcon)
            else
              LineIcon(icon, size: SheetLook.menuIcon, color: enabled ? SheetLook.ink60 : SheetLook.ink45),
            const SizedBox(width: SheetLook.menuLabelLeft - SheetLook.menuIconLeft - SheetLook.menuIcon),
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: sheetText(SheetLook.menuLabel, bold: row.checked || row.danger, color: ink),
              ),
            ),
            if (row.keyText.isNotEmpty) ...[
              const SizedBox(width: 14),
              Text(row.keyText, maxLines: 1, softWrap: false, style: sheetText(SheetLook.menuKey, color: SheetLook.ink45)),
            ],
          ],
        ),
      ),
    );
    if (!enabled) return body;
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      onFocusChange: (on) => setState(() => _focus = on),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          selected: row.checked,
          label: row.label,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _run, child: body),
        ),
      ),
    );
  }
}
