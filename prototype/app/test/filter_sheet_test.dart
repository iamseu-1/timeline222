import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/motion_controls.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/filter_sheet_body.dart';
import 'package:archive_prototype/ui/filter_state.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 필터 시트의 속을 혼자 세워 놓고 눌러 본다. 자료는 월흔해 견본(가상)에서 뽑은 test/fixtures/filter-sample.json이고,
// 아직 없는 조회 명령(legend_kinds · scopes)은 그 파일의 답으로 흉내 낸다.

final _sample = jsonDecode(File('test/fixtures/filter-sample.json').readAsStringSync()) as Map<String, dynamic>;

/// [legend] · [scopes]를 false로 두면 그 조회 명령이 아직 없는 자료 처리부가 된다(답 대신 오류).
(AppBus, List<String>) makeBus({bool legend = true, bool scopes = true}) {
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
    if (op == 'legend_kinds' && legend) return _sample['legend_kinds'] as Map<String, dynamic>;
    if (op == 'scopes' && scopes) return _sample['scopes'] as Map<String, dynamic>;
    throw StateError('아직 없는 조회 명령: $op');
  }

  return (AppBus(ask: ask, controller: controller, scene: scene), asked);
}

Future<void> pumpSheet(WidgetTester tester, AppBus bus) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 1080, child: FilterSheetBody(bus: bus)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FilterState filtersOf(AppBus bus) => bus.slot('filters').value! as FilterState;

/// 그 요소가 세그먼트(관점 · 지도자 표기 …의 고르는 칸) 안에 있는가 — 칸의 글이 `관점: ` 머리 없이 트랙 이름 그대로라(건의 8의 3번) 칩과 이름이 겹친다.
bool _inSegment(Element e) {
  var inside = false;
  e.visitAncestorElements((a) {
    if (a.widget is MotionSegmented) inside = true;
    return !inside;
  });
  return inside;
}

/// 칩의 글만 고른다 — 같은 이름이 대범위 줄의 작은 트랙 이름표(11.5px)에도 나오므로 글자 크기로, 관점 칸의 트랙 이름과는 세그먼트 밖인 것으로 가른다.
Finder chipNamed(String name) =>
    find.byElementPredicate((e) => e.widget is Text && (e.widget as Text).data == name && (e.widget as Text).style?.fontSize == 13 && !_inSegment(e), description: '칩 «$name»');

/// 세그먼트/단계 막대에서 원하는 항목을 바로 고른다. 긴 관점 목록은 옆으로 넘길 수 있다.
Future<void> chooseOption(WidgetTester tester, String current, String wanted) async {
  var option = find.byElementPredicate((e) => e.widget is Semantics && (e.widget as Semantics).properties.label == wanted && _inSegment(e));
  if (option.evaluate().isEmpty) option = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == wanted);
  await tester.ensureVisible(option);
  await tester.tap(option);
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
    await chooseOption(tester, '자동', '넉넉하게');
    expect(filtersOf(bus).density, -1);
    expect(bus.conditions.value.density, -1);

    await chooseOption(tester, '넉넉하게', '조감');
    expect(filtersOf(bus).density, 2);
    expect(filtersOf(bus).birdFrom, -1, reason: '↕ · V가 되돌아갈 자리');
    expect(bus.conditions.value.density, 2);

    await chooseOption(tester, '이름 + 점', '띠 · 선만');
    expect(filtersOf(bus).birdShape, 'c');
    await tester.tap(find.text('축소하면 조감'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).birdAuto, isTrue);
  });

  testWidgets('중요도 · 관점 · 지도자 표기 · 대수', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    await chooseOption(tester, '모든 사건', '중요 사건만');
    expect(filtersOf(bus).minImportance, 3);

    await chooseOption(tester, '기본', '청동초원');
    expect(filtersOf(bus).lens, '3', reason: '관점 목록에는 트랙마다 한 줄이 선다');

    await chooseOption(tester, '기본 이름', '묘호');
    expect(filtersOf(bus).leaderLabel, 'temple');
    await tester.tap(find.text('대수'));
    await tester.pumpAndSettle();
    expect(filtersOf(bus).leaderOrdinal, isTrue);
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

  testWidgets('모두 접기/펴기는 명령으로 알리고, 단추 글은 된 만큼을 적는 슬롯을 따른다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    expect(find.text('▾ 모두 접기'), findsOneWidget);
    await tester.tap(find.text('▾ 모두 접기'));
    await tester.pumpAndSettle();
    // 시트는 바라는 값을 슬롯에 적지 않는다 — 메뉴 · `A` 키와 같은 명령을 낸다(그 명령이 다리를 부르고 슬롯을 되적는다).
    final command = bus.slot(slotCommand).value;
    expect(command, isA<AppCommand>());
    expect((command! as AppCommand).name, Cmd.foldAll);
    bus.slot('foldAll').value = true; // 이어 붙이기가 '된 만큼'을 되적었다
    await tester.pumpAndSettle();
    expect(find.text('▸ 모두 펴기'), findsOneWidget);
  });

  testWidgets('치수는 지금 연표의 실측과 같다', (tester) async {
    final (bus, _) = makeBus();
    await pumpSheet(tester, bus);
    double heightOf(Finder of) => tester.getSize(find.ancestor(of: of, matching: find.byType(Container)).first).height;
    expect(heightOf(chipNamed('흑요산맥')), 32, reason: '.chip 높이 32');
    expect(heightOf(find.text('띠 안')), greaterThanOrEqualTo(34), reason: '.filter-show 최소 높이 34');
    expect(tester.getSize(find.byType(MotionSegmented<int>).first).height, 34, reason: '세그먼트 높이 34');
    expect(tester.getSize(find.ancestor(of: find.text('▾ 모두 접기'), matching: find.byType(AnimatedContainer)).first).height, 32, reason: '.btn-sm 높이 32');
    final title = tester.widget<Text>(find.text('트랙'));
    expect(title.style?.fontSize, 12, reason: '.filter-title 12px');
    expect(tester.widget<Text>(find.text('왕조')).style?.fontSize, 13, reason: '.check 13px');
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
    expect(find.text('보통 이상'), findsOneWidget);
    expect(chipNamed('빈 왕좌의 할거'), findsNothing, reason: '끈 트랙의 대범위 칩은 보이지 않는다');
  });
}
