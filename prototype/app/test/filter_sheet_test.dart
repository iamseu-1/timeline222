import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/filter_sheet.dart';
import 'package:archive_prototype/shell/line_icon.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/filter_sheet_body.dart';
import 'package:archive_prototype/ui/filter_state.dart';
import 'package:archive_prototype/ui/names_display.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 필터 시트의 속을 혼자 세워 놓고 눌러 본다. 자료는 월흔해 견본(가상)에서 뽑은 test/fixtures/filter-sample.json이고,
// 아직 없는 조회 명령(legend_kinds · scopes)은 그 파일의 답으로 흉내 낸다.
// 꼴은 리메이크 4단계 서고 시트(감독 고름 G5 #9 다듬기 판 — 상자 두 열 · 꼬리표 칩 · 열쇠표 · 고르는 칸 · 종이 사슬)이고,
// 항목 · 누르는 길(누름 · Alt+누름) · 기억은 4단계 전 그대로인지를 함께 본다.

final _sample = jsonDecode(File('test/fixtures/filter-sample.json').readAsStringSync()) as Map<String, dynamic>;

/// [legend] · [scopes]를 false로 두면 그 조회 명령이 아직 없는 자료 처리부가 된다(답 대신 오류). [kinds]를 주면 종류 목록을 그것으로 바꾼다.
(AppBus, List<String>) makeBus({bool legend = true, bool scopes = true, List<Map<String, dynamic>>? kinds}) {
  final asked = <String>[];
  final controller = TimelineController()
    ..resize(1920, 600)
    ..setExtent(-1000 * 525960, 1000 * 525960)
    ..setContentHeight(2000);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(_sample['layout'] as Map<String, dynamic>),
    // 이 검사는 연표를 그리지 않는다 — 타일도 이름 자리도 쓰지 않는다.
    fetchTile: (level, x, chunk, packs) async => Uint8List(0),
  );
  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
    final op = '${query['op']}';
    asked.add(op);
    if (op == 'legend_kinds' && legend) return {..._sample['legend_kinds'] as Map<String, dynamic>, 'kinds': ?kinds};
    if (op == 'scopes' && scopes) return _sample['scopes'] as Map<String, dynamic>;
    throw StateError('아직 없는 조회 명령: $op');
  }

  return (AppBus(ask: ask, controller: controller, scene: scene), asked);
}

Future<void> pumpSheet(WidgetTester tester, AppBus bus, {double width = 1080, Widget? tools, FilterState Function()? seed}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: FilterSheetBody(bus: bus, tools: tools, seed: seed)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FilterState filtersOf(AppBus bus) => bus.slot('filters').value! as FilterState;

/// 칩 하나(꼬리표 칩 · 사건 점 칩 · 폴더 칩) — 같은 이름이 관점 고르기 목록 · 작은 꼬리표에도 나오므로 부품으로 가른다.
Finder chipNamed(String name) => find.byWidgetPredicate(
  (w) => (w is SheetTagChip && w.label == name) || (w is SheetDotChip && w.label == name) || (w is SheetScopeChip && w.label == name),
  description: '칩 «$name»',
);

/// 상자 하나(뚜껑의 흰 라벨 이름으로).
Finder boxNamed(String name) => find.byWidgetPredicate((w) => w is SheetBox && w.label == name, description: '상자 «$name»');

/// 고르는 칸(읽기 글 이름으로)을 열고 [wanted] 줄을 고른다 — 펼친 목록은 길 위(맨 끝)에 선다.
Future<void> choose(WidgetTester tester, String semantics, String wanted) async {
  final select = find.byWidgetPredicate((w) => w is SheetChoice && w.semantics == semantics, description: '고르는 칸 «$semantics»');
  await tester.ensureVisible(select);
  await tester.tap(find.descendant(of: select, matching: find.byType(LineIcon)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(wanted).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('칩 묶음은 자료에서 오고, 눌러 켜고 끈다', (tester) async {
    final (bus, asked) = makeBus();
    await pumpSheet(tester, bus);
    expect(asked, containsAll(<String>['legend_kinds', 'scopes']));

    expect(find.text('트랙'), findsOneWidget);
    expect(chipNamed('흑요산맥'), findsOneWidget, reason: '트랙 칩은 bus.scene.layout.tracks에서');
    expect(chipNamed('재의삼각주'), findsOneWidget);
    expect(find.text('분류'), findsOneWidget);
    expect(chipNamed('외교·교류'), findsOneWidget, reason: '분류 칩은 layout.categories에서');
    expect(find.text('종류'), findsOneWidget);
    expect(chipNamed('조직체'), findsOneWidget, reason: '종류 칩은 legend_kinds에서');
    expect(find.text('실재성'), findsOneWidget);
    expect(chipNamed('반전설'), findsOneWidget);
    expect(find.text('대범위'), findsOneWidget);
    expect(chipNamed('빈 왕좌의 할거'), findsOneWidget, reason: '대범위 칩은 scopes에서');

    await tester.tap(chipNamed('흑요산맥'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).chipOn(ChipGroup.tracks, '1'), isFalse);
    await tester.tap(chipNamed('흑요산맥'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).tracksOff, isEmpty);
  });

  testWidgets('Alt+클릭은 그 묶음에서 누른 칩만 켠다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tap(chipNamed('수관림'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    final state = filtersOf(bus);
    expect(state.chipOn(ChipGroup.tracks, '2'), isTrue);
    expect(state.tracksOff, {'1', '3', '4', '5'}, reason: '같은 묶음의 나머지는 모두 꺼진다');
  });

  testWidgets('칩의 풍선 · 읽기 글은 4단계 전 그대로', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    final chip = tester.widget<SheetTagChip>(chipNamed('흑요산맥'));
    expect(chip.hint, '클릭: 켜기/끄기 · Alt+클릭: 이것만 보기');
    expect(tester.widget<SheetDotChip>(chipNamed('외교·교류')).hint, chip.hint);
    final handle = tester.ensureSemantics();
    // 칩마다 제 읽기 마디 — 이름 하나 · 누름 · 켬끔(4단계 전 MotionChip과 같은 읽기).
    expect(tester.getSemantics(find.bySemanticsLabel('흑요산맥').first), matchesSemantics(label: '흑요산맥', hasToggledState: true, isToggled: true, hasTapAction: true, hasEnabledState: true, isEnabled: true));
    handle.dispose();
  });

  testWidgets('조회 명령이 아직 없으면 그 칩 줄만 나오지 않고 나머지는 그대로 쓴다', (tester) async {
    final (bus, _) = makeBus(legend: false, scopes: false);
    await pumpSheet(tester, bus);
    expect(find.text('트랙'), findsOneWidget);
    expect(find.text('분류'), findsOneWidget);
    expect(chipNamed('정치'), findsOneWidget, reason: '쓰인 분류를 모르면 모두 보인다');
    expect(find.text('종류'), findsNothing);
    expect(find.text('실재성'), findsNothing);
    expect(find.text('대범위'), findsNothing);
  });

  testWidgets('띠 안의 단을 끄면 보기 조건으로 넘어가고, 가문은 칠만 바꾼다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    expect(find.text('띠 안'), findsOneWidget);
    expect(find.text('날짜 칸'), findsOneWidget);
    expect(find.text('선·견해'), findsOneWidget);
    expect(bus.conditions.value.phases, isTrue);

    await tester.tap(find.text('시기'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).showing('phases'), isFalse);
    expect(bus.conditions.value.phases, isFalse, reason: '단을 끄면 줄을 다시 쌓아야 한다');

    final before = bus.conditions.value;
    await tester.tap(find.text('가문'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).showing('houses'), isTrue);
    expect(bus.conditions.value, before, reason: '가문 줄은 칠만 — 다시 쌓지 않는다');

    // 간지 줄은 기본 끔(리메이크 2부 — 목업 날짜 칸은 연도 · 시대뿐)이라 누르면 켜진다.
    expect(filtersOf(bus).showing('ganji'), isFalse);
    await tester.tap(find.text('간지'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).showing('ganji'), isTrue);
    await tester.tap(find.text('같은 시기를 타국에도'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).showing('spotEcho'), isTrue, reason: '메아리는 기본 끔이라 누르면 켜진다');
    await tester.tap(find.text('이설'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).showAlt, isFalse);
  });

  testWidgets('밀도를 조감으로 바꾸면 직전 밀도를 기억하고 보기 조건에 싣는다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    await choose(tester, '띠 밀도', '넉넉하게');
    expect(filtersOf(bus).density, -1);
    expect(bus.conditions.value.density, -1);

    await choose(tester, '띠 밀도', '조감');
    expect(filtersOf(bus).density, 2);
    expect(filtersOf(bus).birdFrom, -1, reason: '↕ · V가 되돌아갈 자리');
    expect(bus.conditions.value.density, 2);

    await choose(tester, '조감 모양', '띠 · 선만');
    expect(filtersOf(bus).birdShape, 'c');
    await tester.tap(find.text('축소하면 조감'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).birdAuto, isTrue);
  });

  testWidgets('중요도 · 관점 · 지도자 표기 · 대수', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    await tester.tap(find.text('중요 사건만'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).minImportance, 3);

    await choose(tester, '관점', '청동초원');
    expect(filtersOf(bus).lens, '3', reason: '관점 목록에는 트랙마다 한 줄이 선다');

    await choose(tester, '지도자 표기', '묘호');
    expect(filtersOf(bus).leaderLabel, 'temple');
    await tester.tap(find.text('대수'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).leaderOrdinal, isTrue);
  });

  testWidgets('고르는 칸의 목록은 바깥을 누르면 닫히고 값은 그대로', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    final select = find.byWidgetPredicate((w) => w is SheetChoice && w.semantics == '띠 밀도');
    await tester.tap(find.descendant(of: select, matching: find.byType(LineIcon)));
    await tester.pumpAndSettle();
    expect(find.text('넉넉하게'), findsOneWidget, reason: '목록이 펴졌다');
    // 고른 값(자동)의 줄에는 안쪽 고른 테 — 먹 100 · 1.5.
    final picked = find.ancestor(of: find.text('자동').last, matching: find.byType(SheetPickRing)).first;
    expect(tester.widget<SheetPickRing>(picked).on, isTrue);
    await tester.tapAt(const Offset(1150, 1700));
    await tester.pumpAndSettle();
    expect(find.text('넉넉하게'), findsNothing, reason: '닫혔다');
    expect(filtersOf(bus).density, 0);
  });

  testWidgets('대범위 칩은 시트를 먼저 접고 나서 모아 보기를 켠다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    await tester.tap(chipNamed('세 자유 항구'));
    await tester.pump();
    expect(filtersOf(bus).filterOpen, isFalse, reason: '모여드는 움직임을 시트가 가리지 않게 먼저 접는다');
    expect(filtersOf(bus).scopes, isEmpty, reason: '아직 켜지 않는다');

    await tester.pump(const Duration(milliseconds: 200));
    expect(filtersOf(bus).scopeOn('moonwake-chronicle/scope-scattered'), isTrue);
  });

  testWidgets('대범위: 한 트랙의 칩뿐이면 그 트랙의 작은 꼬리표가 뚜껑 오른쪽에, 둘 이상이면 트랙마다 칩 앞에', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    final box = boxNamed('대범위');
    // 견본은 흑요산맥 · 수관림 두 트랙의 대범위 — 꼬리표가 칩 줄 안에 둘.
    expect(find.descendant(of: box, matching: find.byType(SheetSmallTag)), findsNWidgets(2));
    expect(tester.widget<SheetBox>(box).trailing, isNull);

    await tester.tap(chipNamed('수관림'));
    await tester.pumpAndSettle();
    expect(tester.widget<SheetBox>(box).trailing, isNotNull, reason: '수관림을 끄면 흑요산맥 하나만 남는다');
    final lid = find.descendant(of: box, matching: find.byType(SheetSmallTag));
    expect(lid, findsOneWidget);
    expect(tester.widget<SheetSmallTag>(lid).label, '흑요산맥');
    // 뚜껑 안 위 3 · 오른쪽 안쪽 10.
    final boxRect = tester.getRect(box), tag = tester.getRect(lid);
    expect(tag.top - boxRect.top, 3);
    expect(boxRect.right - tag.right, 10);
    expect(tag.height, 16);
  });

  testWidgets('모두 접기/펴기는 명령으로 알리고, 단추 글은 된 만큼을 적는 슬롯을 따른다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    expect(find.text('모두 접기'), findsOneWidget);
    await tester.tap(find.text('모두 접기'));
    await tester.pumpAndSettle();
    // 시트는 바라는 값을 슬롯에 적지 않는다 — 메뉴 · `A` 키와 같은 명령을 낸다(그 명령이 다리를 부르고 슬롯을 되적는다).
    final command = bus.slot(slotCommand).value;
    expect(command, isA<AppCommand>());
    expect((command! as AppCommand).name, Cmd.foldAll);
    bus.slot('foldAll').value = true; // 이어 붙이기가 '된 만큼'을 되적었다
    await tester.pumpAndSettle();
    expect(find.text('모두 펴기'), findsOneWidget);
    // 단추는 트랙 상자의 뚜껑 밑 첫 줄 오른쪽 끝(안쪽 10).
    final box = tester.getRect(boxNamed('트랙')), button = tester.getRect(find.byType(SheetPaperButton));
    expect(box.right - button.right, 10);
    expect(button.top - box.top, 33, reason: '뚜껑 22 + 밑선 1 + 안쪽 10');
  });

  testWidgets('서고 꼴의 치수 — 칩 · 단추 · 고르는 칸 24 · 뚜껑 22 · 흰 라벨 16', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    expect(tester.getSize(chipNamed('흑요산맥')).height, 24);
    expect(tester.getSize(chipNamed('외교·교류')).height, 24);
    expect(tester.getSize(chipNamed('빈 왕좌의 할거')).height, 24);
    expect(tester.getSize(find.widgetWithText(SheetKeyToggle, '왕조')).height, 24);
    expect(tester.getSize(find.byType(SheetPaperButton)).height, 24);
    final density = find.byWidgetPredicate((w) => w is SheetChoice && w.semantics == '띠 밀도');
    expect(tester.getSize(density).height, 24);
    expect(tester.getSize(find.widgetWithText(SheetLidLabel, '트랙')).height, 16);
    // 상자: 뚜껑 22 + 밑선 1 + 안쪽 10 아래에 칩, 칩 줄 아래 안쪽 11(테 포함)까지가 상자 — 같은 줄의 두 상자 가운데 키 큰 쪽이 그 키를 정한다.
    final box = tester.getRect(boxNamed('분류')), chip = tester.getRect(chipNamed('정치'));
    expect(chip.top - box.top, 33);
    expect(chip.left - box.left, 10);
    double runBottom(String name) => tester.getRect(find.descendant(of: boxNamed(name), matching: find.byType(SheetRun)).first).bottom;
    final row = tester.getRect(boxNamed('날짜 칸'));
    expect(row.height, box.height);
    expect([box.bottom - runBottom('분류'), row.bottom - runBottom('날짜 칸')].reduce((a, b) => a < b ? a : b), 11);
    // 글: 뚜껑 라벨 11 굵게 · 칩 12 굵게.
    expect(tester.widget<Text>(find.text('트랙')).style?.fontSize, 11);
    expect(tester.widget<Text>(find.text('왕조')).style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('왕조')).style?.fontWeight, FontWeight.w700);
    // 사슬의 잇는 실은 고리들만큼 — 상자 끝까지 뻗지 않는다.
    final chain = find.byWidgetPredicate((w) => w is SheetChain);
    final link = tester.getRect(find.descendant(of: chain, matching: find.byType(CustomPaint)).first);
    expect(link.right, tester.getRect(find.ancestor(of: find.text('중요 사건만'), matching: find.byType(SheetTag)).first).right);
    // 고르는 칸의 폭은 가장 긴 값에 맞춘다 — 값을 바꿔도 폭이 그대로.
    final wide = tester.getSize(density).width;
    await choose(tester, '띠 밀도', '조감');
    expect(tester.getSize(density).width, wide);
  });

  testWidgets('끈 칩은 흰 종이 · 먹 25 실선 · 글 먹 45 — 점선이 아니다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    await tester.tap(chipNamed('흑요산맥'));
    await tester.tap(chipNamed('정치'));
    await tester.tap(chipNamed('반전설'));
    await tester.tap(find.text('왕조'));
    await tester.pumpAndSettle();
    for (final name in ['흑요산맥', '정치', '반전설']) {
      final chip = chipNamed(name);
      final shape = tester.widget<SheetTag>(find.descendant(of: chip, matching: find.byType(SheetTag))).shape;
      expect(shape.fill, SheetLook.paper, reason: '$name: 흰 종이');
      expect(shape.stroke, SheetLook.ink25, reason: '$name: 먹 25');
      expect(shape.dash, isNull, reason: '$name: 실선');
      expect(tester.widget<Text>(find.descendant(of: chip, matching: find.byType(Text))).style?.color, SheetLook.ink45, reason: '$name: 글 먹 45');
      expect(tester.renderObject(find.descendant(of: chip, matching: find.byType(CustomPaint)).first), paints..path(color: SheetLook.paper)..path(color: SheetLook.ink25, includes: const [Offset(30, .5), Offset(30, 23.5)], excludes: const [Offset(30, 12)]));
    }
    final key = find.widgetWithText(SheetKeyToggle, '왕조');
    final keyShape = tester.widget<SheetTag>(find.descendant(of: key, matching: find.byType(SheetTag))).shape;
    expect([keyShape.fill, keyShape.stroke, keyShape.dash], [SheetLook.paper, SheetLook.ink25, null]);
    // 켠 칩은 그림판 그대로(꼬리표 칠 24% · 테 84%).
    final on = tester.widget<SheetTag>(find.descendant(of: chipNamed('수관림'), matching: find.byType(SheetTag))).shape;
    expect(on.fill, isNot(SheetLook.paper));
    expect(on.stroke, isNot(SheetLook.ink25));
  });

  testWidgets('종류 칩의 끝 꼴은 그림판 꼬리표와 같은 갈래 — 부흥·저항 둥근 끝 · 복속 세력 직각 · 그 밖 모따기', (tester) async {
    final (bus, _) = makeBus(kinds: [
      {'id': 0, 'kind': 0, 'name': '국가'},
      {'id': 16, 'kind': 16, 'name': '부흥·저항 세력'},
      {'id': 20, 'kind': 20, 'name': '복속 세력·부용'},
      {'id': 'movement', 'name': '옛 답의 부흥'},
    ]);
    await pumpSheet(tester, bus);
    SheetTagKind kindOf(String name) => tester.widget<SheetTagChip>(chipNamed(name)).kind;
    expect(kindOf('국가'), SheetTagKind.cham);
    expect(kindOf('부흥·저항 세력'), SheetTagKind.key);
    expect(kindOf('복속 세력·부용'), SheetTagKind.plain);
    expect(kindOf('옛 답의 부흥'), SheetTagKind.key, reason: '번호 없이 종류 id만 오면 계약 6-1의 차례로 찾는다');
    expect(kindOf('흑요산맥'), SheetTagKind.cham, reason: '트랙 칩은 모따기');
  });

  testWidgets('상자 두 열: 같은 너비 · 같은 줄은 같은 키 · 왼쪽 트랙 … 대범위 · 오른쪽 띠 안 … 중요도', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    final columns = tester.renderObject<RenderSheetColumns>(find.byType(SheetColumns));
    expect(columns.twoColumns, isTrue);
    expect(columns.column, lessThanOrEqualTo((1080 - 12) / 2));
    final boxes = tester.widgetList<SheetBox>(find.byType(SheetBox)).toList();
    expect([for (final b in boxes) b.label], ['트랙', '분류', '종류', '실재성', '대범위', '띠 안', '날짜 칸', '선·견해', '중요도']);
    final rects = [for (final b in boxes) tester.getRect(boxNamed(b.label))];
    expect({for (final r in rects) r.width}, {columns.column}, reason: '상자 너비는 모두 같다');
    expect({for (final r in rects) r.left}.length, 2, reason: '두 열');
    expect(rects[5].left - rects[0].right, 12, reason: '열 사이 12');
    for (final (l, r) in [('트랙', '띠 안'), ('분류', '날짜 칸'), ('종류', '선·견해'), ('실재성', '중요도')]) {
      expect(tester.getRect(boxNamed(l)).top, tester.getRect(boxNamed(r)).top, reason: '$l · $r 같은 줄');
      expect(tester.getSize(boxNamed(l)).height, tester.getSize(boxNamed(r)).height, reason: '$l · $r 같은 키');
    }
    expect(tester.getRect(boxNamed('분류')).top - tester.getRect(boxNamed('트랙')).bottom, 8, reason: '줄 사이 8');
    // 열 너비 = 가장 긴 칩 줄 + 안쪽 10 · 10(들어갈 자리 안에서) — 칩이 넘치는 상자가 없으면 그 폭이 곧 가장 넓은 상자의 펼친 폭이다.
    final natural = [for (final b in boxes) tester.renderObject<RenderBox>(boxNamed(b.label)).getMaxIntrinsicWidth(double.infinity).ceilToDouble()];
    expect(columns.column, natural.reduce((a, b) => a > b ? a : b).clamp(0, ((1080 - 12) / 2).floorToDouble()));
  });

  testWidgets('두 열이 들지 않는 폭은 한 열 — 왼쪽 상자 다음 오른쪽 상자', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus, width: 560);
    final columns = tester.renderObject<RenderSheetColumns>(find.byType(SheetColumns));
    expect(columns.twoColumns, isFalse);
    final boxes = tester.widgetList<SheetBox>(find.byType(SheetBox)).toList();
    final rects = [for (final b in boxes) tester.getRect(boxNamed(b.label))];
    expect({for (final r in rects) r.left}.length, 1, reason: '한 열');
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, greaterThan(rects[i - 1].top), reason: '차례대로 아래로');
    }
    expect(tester.getRect(boxNamed('띠 안')).top, greaterThan(tester.getRect(boxNamed('대범위')).top));
    expect(rects.every((r) => r.right <= 560), isTrue);
  });

  testWidgets('발: 가로대(먹 12) 아래에 고르는 칸 셋 + 축소하면 조감 · 오른쪽 끝에 도구', (tester) async {
    final (bus, _) = makeBus();
    const tools = SizedBox(key: Key('tools'), width: 200, height: 24);
    await pumpSheet(tester, bus, tools: tools);
    final columns = tester.getRect(find.byType(SheetColumns));
    final tool = tester.getRect(find.byKey(const Key('tools')));
    expect(tool.right, columns.right, reason: '도구는 발 오른쪽 끝');
    final rail = tester.getRect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == SheetLook.ink12));
    expect(rail.height, 1);
    expect(rail.width, columns.width);
    final lastBox = tester.getRect(boxNamed('대범위'));
    expect(rail.top - lastBox.bottom, 12);
    final view = find.byWidgetPredicate((w) => w is SheetChoice && w.semantics == '관점');
    expect(tester.getRect(view).top - rail.bottom, 12);
    expect(tester.getRect(view).left, columns.left);
    expect(tool.top, tester.getRect(view).top, reason: '한 줄에 든다');
  });

  testWidgets('표기 무리는 이름 목록이 있는 자료집이 켜져 있을 때만', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    expect(find.text('표기'), findsNothing);
    bus.slot(slotNamesInfo).value = NamesInfo.fromJson({'packs': [1]});
    await tester.pumpAndSettle();
    expect(boxNamed('표기'), findsOneWidget);
    expect(tester.getRect(boxNamed('표기')).top, tester.getRect(boxNamed('실재성')).top, reason: '오른쪽 넷째 — 중요도는 다섯째로');
    expect(tester.getRect(boxNamed('중요도')).top, tester.getRect(boxNamed('대범위')).top);
  });

  testWidgets('기억해 둔 값을 실어 두면 그대로 열린다', (tester) async {
    final (bus, _) = makeBus();
    bus.slot('filters').value = FilterState.fromJson(const {
      'tracks': {'1': false},
      'density': 1,
      'minImportance': 2,
      'show': {'leaders': false},
    });
    await pumpSheet(tester, bus);
    expect(filtersOf(bus).chipOn(ChipGroup.tracks, '1'), isFalse, reason: '실어 둔 값을 덮어쓰지 않는다');
    expect(bus.conditions.value.density, 1);
    expect(bus.conditions.value.leaders, isFalse);
    expect(find.text('빽빽하게'), findsOneWidget);
    expect(tester.widget<Text>(find.text('보통 이상')).style?.color, SheetLook.ink100, reason: '고른 사슬 고리는 먹 100');
    expect(chipNamed('빈 왕좌의 할거'), findsNothing, reason: '끈 트랙의 대범위 칩은 보이지 않는다');
  });

  testWidgets('필터 값이 아직 없으면 지금 보기 조건에서 시작한다 — 시트를 처음 열어도 조감 · 끈 단이 풀리지 않는다(0.1.1)', (tester) async {
    final (bus, _) = makeBus();
    // 옛 기억(필터 칸 없음)으로 조감에 들고 지도자 · 인물 단을 끈 채 시트를 처음 연다 — 보기 조건은 기억(AppMemory.bindConditions)이 넣은 값.
    const now = ViewConditions(leaders: false, figures: false, density: 2);
    bus.conditions.value = now;
    await pumpSheet(tester, bus);
    expect(bus.conditions.value, now, reason: '예전에는 첫 그리기 뒤 기본값(밀도 0 · 단 모두 켬)으로 덮었다');
    expect([filtersOf(bus).density, filtersOf(bus).showing('leaders'), filtersOf(bus).showing('figures'), filtersOf(bus).showing('cabinets')], [2, false, false, true]);
    expect(find.text('조감'), findsWidgets, reason: '밀도 고르는 칸이 조감');
    // 조건에 없는 표시 · 거르기는 기본값 그대로(시트를 연 적이 없으면 그 값이 쓰이고 있다).
    expect([filtersOf(bus).minImportance, filtersOf(bus).tracksOff], [1, isEmpty]);
  });

  testWidgets('첫 값을 짓는 길(seed)을 주면 그 값에서 시작한다 — 앱 틀은 이어 붙이기의 값(기억의 조감 전 밀도까지 · 0.1.1)', (tester) async {
    final (bus, _) = makeBus();
    const now = ViewConditions(cabinets: false, density: 2, birdShape: BirdShape.b);
    bus.conditions.value = now;
    await pumpSheet(tester, bus, seed: () => FilterState.fromConditions(bus.conditions.value, birdFrom: 1));
    expect(bus.conditions.value, now);
    expect([filtersOf(bus).birdFrom, filtersOf(bus).birdShape, filtersOf(bus).showing('cabinets')], [1, 'b', false]);
    // 슬롯에 값이 실린 뒤에는 그 값이 이긴다 — 첫 값을 다시 짓지 않는다.
    await choose(tester, '띠 밀도', '빽빽하게');
    expect([filtersOf(bus).density, bus.conditions.value.density], [1, 1]);
  });

  testWidgets('시트는 폴더 «필터 · 표시» — 탭은 맨 글 12 · 흰 라벨은 상자 뚜껑에만', (tester) async {
    final (bus, _) = makeBus();
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 640), child: FilterSheet(child: FilterSheetBody(bus: bus))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('필터 · 표시'), findsOneWidget);
    expect(find.ancestor(of: find.text('필터 · 표시'), matching: find.byType(SheetLidLabel)), findsNothing, reason: '폴더 탭은 맨 글');
    expect(tester.widget<Text>(find.text('필터 · 표시')).style?.fontSize, 12);
    expect(find.ancestor(of: find.text('트랙'), matching: find.byType(SheetLidLabel)), findsOneWidget, reason: '상자 이름은 흰 라벨');
    final folder = tester.getRect(find.byType(SheetFolder));
    expect(folder.width, lessThanOrEqualTo(1080));
    expect(folder.height, lessThanOrEqualTo(640), reason: '앱 틀이 준 키를 넘으면 폴더 안에서 넘긴다');
  });
}
