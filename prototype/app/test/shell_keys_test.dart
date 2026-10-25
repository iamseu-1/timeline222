import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/doc_window.dart' show docFrontKey;
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 단축키 · 메뉴 · 집중 모드 검사 — 명세 06의 8-1 · 8-2 · 8-3.
// 자료 처리부 없이 돈다: 항목 기록은 test/fixtures/entities-menu.json(월흔해 견본에서 뽑은 일곱 개)으로 가짜 ask를 만든다.

const _uidPolity = 'moonwake-chronicle/p-coast-6'; // 시대 '은륜 제국' — 품은 대범위 둘
const _uidEvent = 'moonwake-chronicle/p-coast-0-chronicle-0-0'; // 사건 — 이름이 20자보다 길다
const _uidScope = 'moonwake-chronicle/scope-warlords'; // 대범위 '빈 왕좌의 할거'

double _year(int year) => DateTime.utc(year).millisecondsSinceEpoch / 60000;

/// 검사용 AppBus — 항목 기록은 견본에서 꺼내 주고, 보기는 [span]년 폭으로 잡는다.
({AppBus bus, List<AppCommand> commands}) makeBus({int from = 200, int to = 300}) {
  final store = <String, Map<String, dynamic>>{};
  for (final one in jsonDecode(File('test/fixtures/entities-menu.json').readAsStringSync()) as List) {
    final row = (one as Map).cast<String, dynamic>();
    store[row['uid'] as String] = row;
  }
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(_year(-3000), _year(3000))
    ..showRange(_year(from), _year(to));
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('단축키 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      if (query['op'] == 'entity') return store[query['uid']] ?? const {};
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  final commands = <AppCommand>[];
  bus.slot(slotCommand).addListener(() {
    final one = bus.slot(slotCommand).value;
    if (one is AppCommand) commands.add(one);
  });
  return (bus: bus, commands: commands);
}

final _dockKey = GlobalKey(debugLabel: '알약 창'), _menuButtonKey = GlobalKey(debugLabel: '⋯ 단추');

/// 연표 자리 — `0 + − ← → Esc`를 제가 처리하고 삼킨다(지금 연표와 같다).
class _FakeTimeline extends StatelessWidget {
  const _FakeTimeline({required this.taken});
  final List<String> taken;

  static final _mine = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.equal,
    LogicalKeyboardKey.minus,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.escape,
  ];

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent && _mine.contains(event.logicalKey)) {
        taken.add(event.logicalKey.keyLabel);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: const SizedBox.expand(),
  );
}

class _Host extends StatefulWidget {
  const _Host({required this.bus, this.spot = const MenuSpot(), this.flags = const MenuFlags(), this.hasMap = false, this.blocked});
  final AppBus bus;
  final MenuSpot spot;
  final MenuFlags flags;
  final bool hasMap;

  /// 위에 뜬 부품의 자리 — 여기서는 메뉴를 열지 않는다.
  final Rect? blocked;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final search = TextEditingController();
  final searchFocus = FocusNode(debugLabel: '검색');

  /// 연표가 이미 처리한 키.
  final taken = <String>[];

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Ui.bg,
      body: ShellKeys(
        bus: widget.bus,
        hasMap: widget.hasMap,
        child: Stack(
          children: [
            Positioned.fill(
              child: ContextMenuArea(
                bus: widget.bus,
                probe: (local) async => widget.spot,
                flagsOf: () => widget.flags,
                blocked: (at) => widget.blocked?.contains(at) ?? false,
                child: _FakeTimeline(taken: taken),
              ),
            ),
            Positioned(
              left: 12,
              top: 10,
              child: ZenHide(
                bus: widget.bus,
                child: Container(
                  key: _dockKey,
                  width: 260,
                  height: 40,
                  color: Ui.surface,
                  child: Center(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: search,
                        focusNode: searchFocus,
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: 8, top: 8, child: ZenExitButton(bus: widget.bus)),
            Positioned(
              right: 12,
              top: 10,
              child: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => showDockMenu(context, bus: widget.bus, flags: widget.flags),
                  child: SizedBox(key: _menuButtonKey, width: 44, height: 32, child: const Center(child: Text('⋯'))),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<_HostState> _pumpKeys(WidgetTester tester, AppBus bus, {MenuSpot spot = const MenuSpot(), MenuFlags flags = const MenuFlags(), bool hasMap = false, Rect? blocked}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_Host(bus: bus, spot: spot, flags: flags, hasMap: hasMap, blocked: blocked));
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  group('단축키', () {
    testWidgets('글자 키가 저마다의 명령이 된다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      for (final key in [
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyY,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.slash,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(commands.map((c) => c.name).toList(), [
        Cmd.filter, Cmd.year, Cmd.legend, Cmd.table, Cmd.foldAll, Cmd.measure, Cmd.bird, Cmd.image, Cmd.dlc, Cmd.search,
      ]);
    });

    testWidgets('같은 키를 두 번 누르면 명령도 두 번 실린다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      expect(commands.length, 2, reason: '같은 이름이라도 새 명령이라 듣는 쪽이 두 번 다 받는다(여닫이)');
      expect(commands[1].seq, greaterThan(commands[0].seq));
    });

    testWidgets('연표가 이미 처리한 키(0 + − ← →)는 두 번 실행되지 않는다', (tester) async {
      final (:bus, :commands) = makeBus();
      final host = await _pumpKeys(tester, bus);
      for (final key in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.equal, LogicalKeyboardKey.minus, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
        await tester.sendKeyEvent(key);
      }
      expect(host.taken.length, 5, reason: '연표가 다섯 키를 모두 제가 처리했다');
      expect(commands, isEmpty, reason: '연표가 삼킨 키는 단축키까지 올라오지 않는다');
    });

    testWidgets('입력 칸에 초점이 있으면 글자 키는 건너뛴다', (tester) async {
      final (:bus, :commands) = makeBus();
      final host = await _pumpKeys(tester, bus);
      host.searchFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      expect(commands, isEmpty, reason: '글을 치는 동안 F · T · /는 단축키가 아니다');
    });

    testWidgets('Alt · Ctrl과 함께 누른 글자는 받지 않는다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(commands, isEmpty);
    });

    testWidgets('W는 고른 항목의 문서다 — 고른 것이 없으면 uid 없는 명령(문서 창이 대문으로 받는다)', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(commands.single.name, Cmd.wiki);
      expect(commands.single.uid, isNull);
      commands.clear();
      bus.select(_uidPolity, kind: 'period');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(commands.single.name, Cmd.wiki);
      expect(commands.single.uid, _uidPolity);
    });

    testWidgets('M은 지도 부품이 있을 때만 듣는다', (tester) async {
      final first = makeBus();
      await _pumpKeys(tester, first.bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(first.commands, isEmpty);
      final second = makeBus();
      await _pumpKeys(tester, second.bus, hasMap: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(second.commands.single.name, Cmd.map);
    });
  });

  group('Esc의 차례', () {
    testWidgets('메뉴가 먼저 닫히고, 그다음이 검색 칸 · 창 · 집중 모드다', (tester) async {
      final (:bus, :commands) = makeBus();
      final host = await _pumpKeys(tester, bus);

      // ① 메뉴: 열려 있으면 메뉴만 닫힌다.
      await tester.tap(find.text('⋯'));
      await tester.pumpAndSettle();
      expect(find.text('같은 해'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('같은 해'), findsNothing);
      expect(commands, isEmpty, reason: '메뉴를 닫는 Esc는 창까지 닫지 않는다');

      // ② 검색 칸: 비우고 초점을 놓는다.
      host.searchFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(commands.single.name, Cmd.searchClose);
      expect(host.searchFocus.hasFocus, isFalse);
      commands.clear();

      // ③ 창: 고른 것이 있으면 창을 닫으라는 명령.
      bus.select(_uidPolity, kind: 'period');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(commands.single.name, Cmd.close);
      commands.clear();

      // ④ 집중 모드: 창이 없을 때에만 나간다.
      bus.clearSelection();
      setZen(bus, true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(zenOf(bus), isFalse);
      expect(commands, isEmpty);
    });
  });

  group('집중 모드', () {
    testWidgets('Z가 켜고 끄며 알약 창이 70px 물러나고, 들어갈 때 안내 한 줄이 실린다', (tester) async {
      final (:bus, commands: _) = makeBus();
      await _pumpKeys(tester, bus);
      expect(tester.getTopLeft(find.byKey(_dockKey)).dy, 10);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(zenOf(bus), isTrue);
      expect(bus.slot(slotNotice).value, zenNotice);
      expect(tester.getTopLeft(find.byKey(_dockKey)).dy, closeTo(10 - 70, .01), reason: '독은 위로 70px 물러난다');
      final dockOpacity = find.ancestor(of: find.byKey(_dockKey), matching: find.byType(Opacity)).first;
      expect(tester.renderObject<RenderOpacity>(dockOpacity).opacity, 0, reason: '집중 모드에서는 독이 완전히 투명하다');
      expect(find.bySemanticsLabel('집중 모드 나가기'), findsOneWidget, reason: '왼쪽 위 삼선 단추만 남는다');

      // ☰를 누르면 돌아온다.
      await tester.tap(find.bySemanticsLabel('집중 모드 나가기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(zenOf(bus), isFalse);
      expect(tester.getTopLeft(find.byKey(_dockKey)).dy, closeTo(10, .01));
      expect(tester.renderObject<RenderOpacity>(dockOpacity).opacity, 1, reason: '집중 모드를 나가면 독이 다시 완전히 보인다');
      expect(find.bySemanticsLabel('집중 모드 나가기'), findsNothing);
    });
  });

  group('메뉴 줄', () {
    test('빈 곳에서 연 메뉴는 명세 8-2의 스물세 줄 + 문서 대문(2026-10-16) + 묶음 제목 셋(보기 · 창 · 그 밖 — 서고 꼴)이다', () {
      final (:bus, commands: _) = makeBus();
      final rows = buildMenuRows(bus: bus);
      expect(rows.length, 27);
      expect([for (final r in rows) if (r.header) r.label], ['보기', '창', '승계선', '그 밖'], reason: '묶음 제목 = 상자 뚜껑(다듬기 판 sm-menu)');
      expect(rows.where((r) => !r.header && !r.sep).length, 17, reason: '누르는 줄은 예전 그대로');
      expect(rows[0].header, isTrue);
      expect(rows[0].label, '보기');
      expect(rows[1].label, '같은 해');
      expect(rows[1].keyText, 'Y');
      expect(rows[2].sep, isTrue);
      expect([for (final r in rows.skip(3).take(4)) r.label], ['기간 재기', '전체 보기', '조감', '모두 접기']);
      expect(rows[8].label, '창');
      expect([for (final r in rows.skip(9).take(5)) r.label], ['필터', '문서 대문', '범례', '표', '이미지 · 인쇄']);
      expect(rows[10].keyText, '', reason: 'W는 고른 항목의 문서가 먼저라 대문 줄에는 단축키 글이 없다');
      expect(rows[15].header, isTrue);
      expect(rows[15].label, '승계선');
      expect(rows[15].group, MenuGroup.chain, reason: '승계선은 종이 사슬');
      expect(rows[16].checked, isTrue, reason: '승계선의 처음 값은 모두 보기');
      expect(rows[20].label, '그 밖');
      expect(rows[21].label, 'DLC 관리');
      expect(rows[23].label, '집중 모드');
      expect(rows[23].keyText, 'Z');
      expect(rows[26].label, '움직임 계측');
      expect(rows.where((r) => r.sep).length, 6);
    });

    test('문서 대문 줄은 대문 열쇠로 문서 명령을 낸다', () {
      final (:bus, :commands) = makeBus();
      buildMenuRows(bus: bus).firstWhere((r) => r.label == '문서 대문').onSelected!();
      expect(commands.single.name, Cmd.wiki);
      expect(commands.single.uid, docFrontKey);
    });

    test('켜져 있는 것에 ✓가 붙고, 모두 접혀 있으면 글이 펴기로 바뀐다', () {
      final (:bus, commands: _) = makeBus();
      final rows = buildMenuRows(
        bus: bus,
        flags: const MenuFlags(measuring: true, bird: true, filterOpen: true, legend: true, allFolded: true, zen: true, motion: true, succession: Succession.direct),
      );
      String labelOf(String key) => rows.firstWhere((r) => r.keyText == key).label;
      expect(rows.firstWhere((r) => r.keyText == 'R').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'V').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'F').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'L').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'Z').checked, isTrue);
      expect(labelOf('A'), '모두 펴기');
      expect(rows.firstWhere((r) => r.label == '직접만').checked, isTrue);
      expect(rows.firstWhere((r) => r.label == '모두').checked, isFalse);
      expect(rows.last.checked, isTrue, reason: '움직임 계측이 열려 있다');
    });

    test('트랙을 누르면 접기 · 문서 줄이 붙고, 연표 위를 누르면 그때에 무슨 일이가 된다', () {
      final (:bus, :commands) = makeBus();
      final rows = buildMenuRows(bus: bus, spot: MenuSpot(trackId: 3, trackName: '유리해안', at: _year(240) + 12345));
      expect(rows[0].label, '보기', reason: '트랙 줄은 보기 상자의 첫 작은 묶음');
      expect(rows[1].label, '유리해안 접기');
      expect(rows[2].label, '유리해안 문서');
      expect(rows[3].label, '240년에 무슨 일이', reason: '100년을 보고 있으니 해 단위');
      rows[3].onSelected!();
      expect(commands.single.at, _year(240), reason: '누른 자리를 그 해의 처음으로 맞춰 싣는다');
      rows[1].onSelected!();
      expect(commands.last.trackId, 3);

      final folded = buildMenuRows(bus: bus, spot: const MenuSpot(trackId: 3, trackName: '유리해안', folded: true));
      expect(folded[1].label, '유리해안 펴기');
    });

    test('좁게 보고 있으면 그때가 달 · 날까지 적힌다', () {
      final (:bus, commands: _) = makeBus(from: 240, to: 241); // 한 해 폭 → 달
      expect(buildMenuRows(bus: bus, spot: MenuSpot(at: _year(240) + 40 * 24 * 60)).firstWhere((r) => !r.header).label, '240년 2월에 무슨 일이');
    });

    test('항목 위에서 열면 그 항목의 자세히 보기가 맨 위이고, 품은 대범위가 함께 온다', () async {
      final (:bus, :commands) = makeBus();
      final item = await askEntity(bus, _uidPolity);
      final rows = buildMenuRows(bus: bus, item: item, flags: const MenuFlags(scopesOn: {_uidScope: true}));
      expect(rows[0].header, isTrue);
      expect(rows[0].label, '시대 · 은륜 제국');
      expect(rows[1].label, '자세히 보기');
      expect(rows[2].label, '문서');
      expect(rows[2].keyText, 'W');
      expect(rows[3].label, '여기로 확대');
      expect(rows[4].header, isTrue, reason: '대범위 모아 보기는 머리에 한 번(건의 8의 3번)');
      expect(rows[4].label, '대범위 모아 보기');
      expect(rows[5].label, '빈 왕좌의 할거');
      expect(rows[5].checked, isTrue, reason: '이미 모아 보고 있으면 ✓');
      expect(rows[6].label, '은륜 부흥 운동');
      expect(rows[6].checked, isFalse);
      expect(rows[7].sep, isTrue);
      rows[1].onSelected!();
      expect(commands.single.name, Cmd.detail);
      expect(commands.single.uid, _uidPolity);
    });

    test('이름이 스무 자를 넘으면 줄여 적는다', () async {
      final (:bus, commands: _) = makeBus();
      final item = await askEntity(bus, _uidEvent);
      expect(item!.word, '사건');
      expect(buildMenuRows(bus: bus, item: item).first.label, '사건 · ${cutName(item.name)}');
      expect(cutName(item.name).length, 21, reason: '스무 자 + 말줄임표');
    });

    test('자료 처리부가 항목을 모르면 항목 줄 없이 연다', () async {
      final (:bus, commands: _) = makeBus();
      expect(await askEntity(bus, '없는 항목'), isNull);
      final rows = buildMenuRows(bus: bus, item: null);
      expect(rows.first.label, '보기', reason: '항목 상자 없이 보기 상자부터');
      expect(rows[1].label, '같은 해');
    });
  });

  group('메뉴 열기', () {
    testWidgets('⋯ 단추의 차림표는 단추 밑 12에 오른쪽 끝을 맞춘 폭 356 폴더(탭 오른쪽)이고, 고른 줄이 명령이 된다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      final button = tester.getRect(find.byKey(_menuButtonKey));
      await tester.tap(find.text('⋯'));
      await tester.pumpAndSettle();
      final folder = find.ancestor(of: find.text('같은 해'), matching: find.byType(SheetFolder));
      final card = tester.getRect(folder);
      expect(card.width, SheetLook.menuWidth, reason: '폭 356(다듬기 판 sm-menu)');
      expect(card.right, closeTo(button.right, .01), reason: '오른쪽 끝을 단추에');
      expect(card.top, closeTo(button.bottom + SheetLook.menuBelow, .01), reason: '단추 밑 12(탭 꼭대기)');
      expect(tester.widget<SheetFolder>(folder).label, '차림표');
      expect(tester.widget<SheetFolder>(folder).tabRight, isTrue, reason: '탭은 연 단추 밑(오른쪽)');
      expect(find.text('범례'), findsOneWidget);
      expect(find.text('승계선'), findsOneWidget);

      await tester.tap(find.text('표'));
      await tester.pumpAndSettle();
      expect(commands.single.name, Cmd.table);
      expect(find.text('표'), findsNothing, reason: '고르면 메뉴가 닫힌다');
    });

    testWidgets('연표 위 오른쪽 클릭은 누른 항목의 줄을 맨 위에 두고, 바깥을 누르면 닫힌다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus, spot: const MenuSpot(uid: _uidPolity));
      final gesture = await tester.startGesture(const Offset(900, 700), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('시대 · 은륜 제국'), findsOneWidget);
      expect(find.text('자세히 보기'), findsOneWidget);
      // 항목 제목 줄이 첫 상자의 뚜껑 · 탭은 왼쪽.
      final first = tester.widgetList<SheetBox>(find.byType(SheetBox)).first;
      expect(first.label, '시대 · 은륜 제국');
      expect(tester.widget<SheetBox>(find.ancestor(of: find.text('자세히 보기'), matching: find.byType(SheetBox))).label, '시대 · 은륜 제국');
      expect(tester.widget<SheetFolder>(find.byType(SheetFolder)).tabRight, isFalse);
      expect(tester.getSize(find.byType(SheetFolder)).width, greaterThanOrEqualTo(SheetLook.menuWidth));

      await tester.tapAt(const Offset(1800, 1000));
      await tester.pumpAndSettle();
      expect(find.text('자세히 보기'), findsNothing);
      expect(commands, isEmpty);
    });

    testWidgets('위에 뜬 창(상세 · 범례)의 자리에서는 열지 않는다', (tester) async {
      final (:bus, commands: _) = makeBus();
      await _pumpKeys(tester, bus, spot: const MenuSpot(uid: _uidPolity), blocked: const Rect.fromLTWH(1528, 12, 380, 1052));
      final gesture = await tester.startGesture(const Offset(1700, 500), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('자세히 보기'), findsNothing, reason: '상세 창 위에서는 연표의 메뉴가 열리지 않는다');
    });
  });

  // 서고 꼴(감독 고름 G5 #9 — 다듬기 판 sm-menu · 계획 4단계 과제 9 '틀의 시트와 창' 걸음 3).
  group('차림표 서고 꼴', () {
    SheetShape shapeOf(WidgetTester tester, String label) =>
        tester.widget<SheetTag>(find.ancestor(of: find.text(label), matching: find.byType(SheetTag)).first).shape;

    testWidgets('제목 줄은 상자 뚜껑 · 켠 줄은 구멍 칠 먹 85 + 굵게 · 승계선 사슬은 하나만 고름', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus, flags: const MenuFlags(measuring: true, succession: Succession.direct));
      await tester.tap(find.text('⋯'));
      await tester.pumpAndSettle();

      // 제목 줄 = 상자 뚜껑의 흰 라벨 · 그 아래 줄들이 그 상자 안(구분선은 상자 안 작은 묶음 틈).
      for (final title in ['보기', '창', '승계선', '그 밖']) {
        expect(find.descendant(of: find.byType(SheetLidLabel), matching: find.text(title)), findsOneWidget, reason: title);
      }
      expect(tester.widget<SheetBox>(find.ancestor(of: find.text('필터'), matching: find.byType(SheetBox))).label, '창');
      expect(tester.widget<SheetBox>(find.ancestor(of: find.text('같은 해'), matching: find.byType(SheetBox))).label, '보기');
      final view = find.ancestor(of: find.text('기간 재기'), matching: find.byType(SheetThreadColumn));
      expect(tester.widget<SheetThreadColumn>(view).breakBefore, {1}, reason: '같은 해 | 기간 재기 … 사이가 작은 묶음 틈');
      expect(tester.widget<SheetThreadColumn>(view).gap, SheetLook.menuRowGap);

      // 켠 줄(기간 재기)은 구멍 칠 먹 85 + 이름 굵게 · 끈 줄(전체 보기)은 흰 구멍 + 보통 — 체크 그림은 없다.
      expect(shapeOf(tester, '기간 재기').holeFill, SheetLook.ink85);
      expect(shapeOf(tester, '전체 보기').holeFill, SheetLook.paper);
      expect(shapeOf(tester, '전체 보기').stroke, SheetLook.ink25);
      expect(tester.widget<Text>(find.text('기간 재기')).style!.fontWeight, FontWeight.w700);
      expect(tester.widget<Text>(find.text('전체 보기')).style!.fontWeight, FontWeight.w400);

      // 승계선 = 종이 사슬 · 고른 고리는 하나(직접만).
      final chain = tester.widget<SheetChain<int>>(find.byType(SheetChain<int>));
      expect([for (final i in chain.items) i.$2], ['모두', '직접만', '숨김']);
      expect(chain.value, 1);
      final picked = find.descendant(of: find.byType(SheetChain<int>), matching: find.byWidgetPredicate((w) => w is SheetTag && w.shape.stroke == SheetLook.pickInk));
      expect(picked, findsOneWidget);
      expect(find.descendant(of: picked, matching: find.text('직접만')), findsOneWidget);

      await tester.tap(find.text('숨김'));
      await tester.pumpAndSettle();
      expect(commands.single.name, Cmd.succession);
      expect(commands.single.arg, 'off');
      expect(find.byType(SheetChain<int>), findsNothing, reason: '고르면 차림표가 닫힌다');
    });

    testWidgets('글자(ClearType)는 열쇠표 · 승계선 사슬과 한 줄에 상자 둘', (tester) async {
      final (:bus, commands: _) = makeBus();
      await _pumpKeys(tester, bus, flags: const MenuFlags(clearTypeShown: true, clearType: true));
      await tester.tap(find.text('⋯'));
      await tester.pumpAndSettle();
      final key = tester.widget<SheetKeyToggle>(find.byType(SheetKeyToggle));
      expect(key.label, 'ClearType');
      expect(key.on, isTrue);
      final chainBox = tester.getRect(find.ancestor(of: find.byType(SheetChain<int>), matching: find.byType(SheetBox)));
      final keyBox = tester.getRect(find.ancestor(of: find.byType(SheetKeyToggle), matching: find.byType(SheetBox)));
      expect(keyBox.top, chainBox.top, reason: '한 줄');
      expect(keyBox.left, greaterThan(chainBox.right));
      expect(keyBox.height, chainBox.height);
    });

    testWidgets('못 누르는 줄은 테 먹 25 · 글 먹 45 · 초점 없음 — 첫 초점은 누를 수 있는 첫 줄 · 올리면 먹 4 칠 + 테 먹 45', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTimelineMenu(context, [
                  const MenuRow('못 누름'),
                  MenuRow('누름', onSelected: () => picked.add('누름')),
                ], at: const Offset(100, 100)),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(shapeOf(tester, '못 누름').stroke, SheetLook.ink25);
      expect(shapeOf(tester, '못 누름').holeStroke, SheetLook.ink25);
      expect(tester.widget<Text>(find.text('못 누름')).style!.color, SheetLook.ink45);
      Finder focusIn(String label) => find.descendant(of: find.byType(SheetThreadColumn), matching: find.ancestor(of: find.text(label), matching: find.byType(Focus)));
      expect(focusIn('못 누름'), findsNothing, reason: '못 누르는 줄은 초점을 받지 않는다');
      expect(focusIn('누름'), findsOneWidget);
      expect(tester.widget<Focus>(focusIn('누름')).autofocus, isTrue, reason: '첫 초점은 누를 수 있는 첫 줄');
      expect(find.byType(SheetFolder), findsOneWidget, reason: '작은 차림표도 같은 폴더');
      expect(find.byType(SheetBox), findsNothing, reason: '제목 줄이 없으면 줄을 폴더에 바로 매단다');

      // 올리면 먹 4 칠 + 테 먹 45.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('누름')));
      await tester.pumpAndSettle();
      expect(shapeOf(tester, '누름').fill, SheetLook.ink4);
      expect(shapeOf(tester, '누름').stroke, SheetLook.ink45);

      await tester.tap(find.text('못 누름'));
      await tester.pumpAndSettle();
      expect(find.text('누름'), findsOneWidget, reason: '못 누르는 줄은 눌러도 닫히지 않는다');
      await tester.tap(find.text('누름'));
      await tester.pumpAndSettle();
      expect(picked, ['누름']);
    });

    testWidgets('안내 줄 둘은 폴더 맨 위 한 줄(왼쪽 먹 60 · 오른쪽 먹 45)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTimelineMenu(context, [
                  const MenuRow.note('사건 120 · 날짜 미정 0'),
                  const MenuRow.note('원문 0'),
                  const MenuRow.sep(),
                  const MenuRow.title('보기'),
                  MenuRow('같은 해', onSelected: () {}),
                ], at: const Offset(100, 100)),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final left = tester.getRect(find.text('사건 120 · 날짜 미정 0')), right = tester.getRect(find.text('원문 0'));
      expect(left.center.dy, closeTo(right.center.dy, .5), reason: '한 줄');
      expect(right.left, greaterThan(left.right));
      expect(tester.widget<Text>(find.text('사건 120 · 날짜 미정 0')).style!.color, SheetLook.ink60);
      expect(tester.widget<Text>(find.text('원문 0')).style!.color, SheetLook.ink45);
      expect(left.bottom, lessThan(tester.getRect(find.byType(SheetBox)).top), reason: '안내 글은 상자 위(폴더 맨 위)');
    });
  });
}
