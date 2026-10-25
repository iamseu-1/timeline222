import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/metro_card.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 도읍 노선도 카드 — 지금 연표의 `js/timeline.js` 5326~5622(`_metroHTML` · `showMetro`)와 맞대는 검사.
//
// 셋으로 나뉜다:
//   ① 값 · 도형 — 가짜 자(글자 한 자 = 10px)로 재서 `_metroHTML`의 셈을 숫자 그대로 굳힌다(가상 견본).
//   ② 부품 — 슬롯을 듣고 뜨고 지는가 · 누르면 가는가 · 도시를 비추는가(가짜 자료 처리부).
//   ③ **진짜 자료 처리부(DLL) + 진짜 저장소**로 도는 맞대기 — 지금 연표의 기준 덤프
//      (`prototype/results/dom-metro/metro-dump.json` · `node prototype/results/dom-metro/dump-metro.mjs`로 뜬다)의
//      좌표와 새 부품의 좌표가 같은가. DLL이나 저장소가 없으면 건너뛴다.
//
// 저장소가 둘인 까닭: `x_metro`(환승 · 발의 단추)는 `scripts/export/metro.mjs`가 얹는 값이고,
// 그 모듈을 `export-layout.mjs`의 MODULES에 더하는 것은 총괄의 몫이다. 그래서
//   · `data/moonwake3-metro` — 이 물결이 낸 저장소(x_metro 있음)
//   · `data/moonwake3h`      — 주 저장소(x_metro **없음**) — 없어도 본선 · 지선 · 우회가 서는지 굳힌다.

/// 글자 한 자를 10px로 보는 가짜 자 — 도형 셈만 재려고(브라우저 글꼴에 기대지 않게).
double ruler(String text, double size, int weight) => text.length * 10.0;

/// 가상 견본 하나 — 본선 하나(같은 도시로 돌아와 합쳐짐) · 우회 하나 · 지선 둘.
Map<String, dynamic> sample({List<Map<String, dynamic>>? capitals, Map<String, dynamic>? metro, bool ongoing = false}) => {
  'uid': '견본/푸른물결국',
  'kind': 'period',
  'json': {
    'uid': '견본/푸른물결국',
    'name': '푸른 물결국',
    'color': '#a0bcc5',
    'start': 100,
    'end': 300,
    'endY': 300,
    if (ongoing) 'ongoing': true,
    'capitals': capitals ??
        [
          {'city': '북쪽성', 'name': '북쪽성', 'role': 'main', 'start': 100, 'end': 200, 'endY': 200},
          {'city': '동쪽성', 'name': '동쪽성', 'role': 'secondary', 'start': 120, 'end': 300, 'endY': 300},
          {'city': '서쪽성', 'name': '서쪽성', 'role': 'secondary', 'start': 130, 'end': 300, 'endY': 300},
          {'city': '남쪽성', 'name': '남쪽성', 'role': 'temporary', 'start': 150, 'end': 160, 'endY': 160},
          {'city': '북쪽성', 'name': '북쪽성', 'role': 'main', 'start': 200, 'end': 300, 'endY': 300},
        ],
    'x_metro': ?metro,
  },
};

/// 가짜 자료 처리부 하나 — `{"op":"entity","uid":…}` 말고는 답하지 않는다.
({AppBus bus, List<Map<String, dynamic>> asked, List<GoRequest> went}) makeBus(List<Map<String, dynamic>> records) {
  final store = {for (final r in records) r['uid'] as String: r};
  final asked = <Map<String, dynamic>>[];
  final went = <GoRequest>[];
  final controller = TimelineController()..resize(1400, 700);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 0},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('노선도 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      if (query['op'] == 'entity') {
        final row = store[query['uid']];
        if (row == null) throw StateError('없는 기록: ${query['uid']}');
        return row;
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  bus.go.addListener(() {
    final one = bus.go.value;
    if (one != null) went.add(one);
  });
  return (bus: bus, asked: asked, went: went);
}

Future<void> pumpCard(WidgetTester tester, AppBus bus, {Size size = const Size(1400, 700)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      home: Scaffold(
        backgroundColor: Ui.bg,
        body: Stack(children: [const SizedBox.expand(), MetroCard(bus: bus)]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 검사 환경에는 시스템 글꼴이 없다 — 지금 연표가 이 PC에서 쓰는 글꼴을 파일에서 읽어 같은 이름으로 올린다.
Future<void> loadFonts() async {
  await loadAppFonts();
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf']),
    ('Malgun Gothic', ['C:/Windows/Fonts/malgun.ttf', 'C:/Windows/Fonts/malgunbd.ttf']),
  ]) {
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
}

/// 그림을 뜰 곳 — `--dart-define=OUT=../results/render-metro`를 줄 때만 뜬다.
const captureTo = String.fromEnvironment('OUT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 값과 도형 ─────────────────────────────────────────────────────────────────────────
  group('기록 읽기', () {
    test('도읍 칸과 x_metro를 푼다', () {
      final data = MetroData.fromAnswer(
        sample(
          metro: {
            'range': '100년 ~ 300년',
            'end': '300',
            'when': ['100년 ~ 200년', '120년 ~ 300년', '130년 ~ 300년', '150년 ~ 160년', '200년 ~ 300년'],
            'alts': {
              '0': ['98년 ~ 200년: 옛 장부 기준'],
            },
            'xfer': {
              '북쪽성': [
                {'uid': '견본/잿빛항', 'name': '잿빛 항국', 'color': '#bba395', 'cell': '북쪽성', 'year': 'BC 20'},
              ],
            },
            'peers': [
              {'uid': '견본/푸른물결국', 'name': '푸른 물결국', 'color': '#a0bcc5'},
              {'uid': '견본/잿빛항', 'name': '잿빛 항국', 'color': '#bba395'},
            ],
          },
        ),
      )!;
      expect(data.name, '푸른 물결국');
      expect(data.range, '100년 ~ 300년');
      expect(data.endLabel, '300');
      expect(data.capitals.length, 5);
      expect(data.capitals[0].when, '100년 ~ 200년');
      expect(data.capitals[0].alts, ['98년 ~ 200년: 옛 장부 기준']);
      expect(data.capitals[3].temporary, isTrue);
      expect(data.xfer['북쪽성']!.single.name, '잿빛 항국');
      expect(data.peers.map((q) => q.uid), ['견본/푸른물결국', '견본/잿빛항']);
    });

    test('x_metro가 없어도 도읍 칸만으로 선다 — 날짜 글은 스스로 만든다', () {
      final data = MetroData.fromAnswer(sample())!;
      expect(data.capitals.length, 5);
      expect(data.capitals[0].when, '100년 ~ 200년');
      expect(data.range, '100년 ~ 300년');
      expect(data.endLabel, '300');
      expect(data.xfer, isEmpty);
      expect(data.peers, isEmpty);
    });

    test('도읍이 없으면 카드를 만들지 않는다', () {
      expect(MetroData.fromAnswer(sample(capitals: [])), isNull);
      expect(MetroData.fromAnswer(const {'uid': '견본/빈것', 'json': '{}'}), isNull);
    });

    test('기원전은 BC로 적는다', () {
      expect(bcYearText(300), '300');
      expect(bcYearText(-960), 'BC 960');
      expect(bcYearText(1), '1');
    });
  });

  group('노선도 셈 (가짜 자 · 한 자 10px)', () {
    late MetroPlan plan;
    late MetroData data;
    setUp(() {
      data = MetroData.fromAnswer(sample())!;
      plan = MetroPlan.of(data, ruler);
    });

    test('같은 도시로 돌아온 정도는 한 역에 합쳐진다', () {
      expect(plan.nodes.length, 2);
      expect(plan.nodes[0].detour, isFalse);
      expect(plan.nodes[0].periods.length, 2); // 100~200과 200~300
      expect(plan.nodes[0].names, ['북쪽성']);
      expect(plan.nodes[1].detour, isTrue); // 임시 도읍은 아래 점선 우회
      expect(plan.nodes[1].head.name, '남쪽성');
    });

    test('역의 이름표와 가로 자리', () {
      expect(plan.nodes[0].labelName, '북쪽성');
      expect(plan.nodes[0].labelSub, '100 · 200');
      expect(plan.nodes[0].labelWidth, 92); // max(30, 90) + 2
      expect(plan.nodes[0].x, 28);
      expect(plan.nodes[1].labelSub, '150–160 · 임시');
      expect(plan.nodes[1].labelWidth, 122);
      expect(plan.nodes[1].x, 152); // 28 + max(60, 92 + 32)
      expect(plan.xEnd, 204); // 152 + max(60 - 8, 28 + 16)
      expect(plan.mainFrom, 28);
    });

    test('지선은 그 해에 있던 역에서 위로 · 왼쪽일수록 높이', () {
      expect(plan.branches.map((b) => b.name), ['동쪽성', '서쪽성']);
      expect(plan.branches[0].x, 41); // 28 + 13
      expect(plan.branches[1].x, 52); // 28 + 13 + 11
      expect(plan.mainY, 71); // 45 + (2 - 1) * 26
      expect(plan.branches[0].y, 17);
      expect(plan.branches[1].y, 43);
      expect(plan.branches[0].text, '120–');
      expect(plan.branches[0].width, 78);
    });

    test('노선도의 크기 · 가장 오래 머문 역 · 머리의 곁글', () {
      expect(plan.mapWidth, 260); // 260보다 좁아지지 않는다
      expect(plan.mapHeight, 147); // 71 + 76(우회가 있을 때)
      expect(plan.longest, same(plan.nodes[0]));
      expect(plan.seats, 2);
      expect(plan.secondaries, 2);
      expect(plan.moves, 2);
      expect(plan.summary(data.range), '도읍 2곳 · 배도 2곳 · 천도 2번 · 100년 ~ 300년');
      expect(plan.hasXfer, isFalse);
      expect(plan.dashes, isEmpty);
    });

    test('진행 중인 정권의 끝은 `지금`', () {
      final live = MetroPlan.of(MetroData.fromAnswer(sample(ongoing: true))!, ruler);
      expect(live.endName, '지금');
      expect(live.endSub, '');
      expect(plan.endName, '끝');
      expect(plan.endSub, '300');
    });

    test('배도 묶음이 같으면 지선 하나 · 넷을 넘으면 나머지는 범례로', () {
      final many = MetroData.fromAnswer(
        sample(
          capitals: [
            {'city': '북쪽성', 'name': '북쪽성', 'role': 'main', 'start': 100, 'end': 300, 'endY': 300},
            for (final (i, name) in ['가', '나', '다', '라', '마', '바'].indexed)
              {'city': '$name쪽성', 'name': '$name쪽성', 'role': 'secondary', 'start': 110 + i, 'end': 300, 'endY': 300},
            {'city': '두물성', 'name': '두물성', 'role': 'secondary', 'group': '두 보조도읍', 'start': 120, 'end': 300, 'endY': 300},
            {'city': '세물성', 'name': '세물성', 'role': 'secondary', 'group': '두 보조도읍', 'start': 130, 'end': 290, 'endY': 290},
          ],
        ),
      )!;
      final made = MetroPlan.of(many, ruler);
      expect(made.branches.length, 4);
      expect(made.hiddenBranches, 3); // 일곱 묶음 가운데 넷만
      expect(made.branches.map((b) => b.name), ['가쪽성', '나쪽성', '다쪽성', '라쪽성']);
      expect(made.mainY, 45 + 3 * 26);
    });

    test('같은 묶음의 배도는 하나로 — 이름은 묶음 이름 · 기간은 양 끝', () {
      final grouped = MetroData.fromAnswer(
        sample(
          capitals: [
            {'city': '북쪽성', 'name': '북쪽성', 'role': 'main', 'start': 100, 'end': 300, 'endY': 300},
            {'city': '두물성', 'name': '두물성', 'role': 'secondary', 'group': '두 보조도읍', 'start': 120, 'end': 280, 'endY': 280},
            {'city': '세물성', 'name': '세물성', 'role': 'secondary', 'group': '두 보조도읍', 'start': 130, 'end': 300, 'endY': 300},
          ],
        ),
      )!;
      final made = MetroPlan.of(grouped, ruler);
      expect(made.branches.length, 1);
      expect(made.branches.single.name, '두 보조도읍');
      expect(made.branches.single.city, ''); // 묶음은 한 도시가 아니므로 환승을 달지 않는다
      expect(made.branches.single.start, 120);
      expect(made.branches.single.endY, 300);
    });

    test('경계가 미정이면 그 사이 본선이 점선', () {
      final unknown = MetroData.fromAnswer(
        sample(
          capitals: [
            {'city': '북쪽성', 'name': '북쪽성', 'role': 'main', 'start': 100, 'end': 200, 'endY': 200},
            {'city': '남쪽성', 'name': '남쪽성', 'role': 'main', 'start': 200, 'endUnknown': true, 'end': 300, 'endY': 300},
            {'city': '동쪽성', 'name': '동쪽성', 'role': 'main', 'start': 300, 'startUnknown': true, 'end': 400, 'endY': 400},
          ],
        ),
      )!;
      final made = MetroPlan.of(unknown, ruler);
      expect(made.nodes.length, 3);
      // 둘째 역의 끝과 셋째 역의 시작이 모두 미정 → 그 사이 한 구간 + 마지막 역 뒤는 미정이 아니다
      expect(made.dashes.length, 1);
      final (from, to) = made.dashes.single;
      expect(from, made.nodes[1].x + 12);
      expect(to, made.nodes[2].x - 12);
      expect(made.nodes[2].labelSub, '미정'); // 시작이 미정인 역의 해
    });

    test('망명 · 공동 도읍은 해 뒤에 꼬리말', () {
      final roles = MetroData.fromAnswer(
        sample(
          capitals: [
            {'city': '북쪽성', 'name': '북쪽성', 'role': 'co', 'start': 100, 'end': 200, 'endY': 200},
            {'city': '남쪽성', 'name': '남쪽성', 'role': 'exile', 'start': 200, 'end': 300, 'endY': 300},
          ],
        ),
      )!;
      final made = MetroPlan.of(roles, ruler);
      expect(made.nodes[0].labelSub, '100 · 공동');
      expect(made.nodes[1].labelSub, '200 · 망명');
    });

    test('환승 칩과 겹고리 — 다른 나라가 같은 도시를 썼을 때만', () {
      final withXfer = MetroData.fromAnswer(
        sample(
          metro: {
            'xfer': {
              '북쪽성': [
                {'uid': '견본/잿빛항', 'name': '잿빛 항국', 'color': '#bba395', 'cell': '북쪽성', 'year': 'BC 20'},
                {'uid': '견본/모래성', 'name': '모래 성국', 'color': '#9dbea8', 'cell': '북쪽성', 'year': '40'},
              ],
            },
          },
        ),
      )!;
      final made = MetroPlan.of(withXfer, ruler);
      expect(made.hasXfer, isTrue);
      final chip = made.nodes[0].chip!;
      expect(chip.text, '⇄ 잿빛 항국 외 1');
      expect(chip.uid, '견본/잿빛항');
      expect(chip.tip, '같은 도시 · 잿빛 항국 북쪽성 BC 20– · 모래 성국 북쪽성 40–');
      expect(made.nodes[1].chip, isNull); // 남쪽성은 다른 나라가 쓰지 않았다
    });

    test('누르면 갈 기간은 앞뒤로 20% · 적어도 6년', () {
      final (lo, hi) = metroViewOf(100, 200);
      expect(lo, minutesOfTFor(80)); // 100 - max(6, 20)
      expect(hi, minutesOfTFor(220));
      final (lo2, hi2) = metroViewOf(100, 110);
      expect(lo2, minutesOfTFor(94)); // 100 - max(6, 2)
      expect(hi2, minutesOfTFor(116));
    });
  });

  // ── ② 부품 ─────────────────────────────────────────────────────────────────────────────
  group('카드', () {
    testWidgets('슬롯에 uid를 실으면 뜨고, 비우면 진다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      expect(find.byType(MetroCard), findsOneWidget);
      expect(find.text('푸른 물결국'), findsNothing);

      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsOneWidget);
      expect(find.text('도읍 2곳 · 배도 2곳 · 천도 2번 · 100년 ~ 300년'), findsOneWidget);
      expect(find.text('북쪽성'), findsOneWidget);
      expect(find.text('남쪽성'), findsOneWidget);
      expect(find.text('정도'), findsOneWidget);
      expect(find.text('배도(지선)'), findsOneWidget);
      expect(find.text('임시(우회)'), findsOneWidget);
      expect(find.text('같은 도시(환승)'), findsNothing);

      made.bus.slot(metroSlot).value = null;
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsNothing);
    });

    testWidgets('닫아도 곧바로 사라지지 않고 snap / out이 정착할 때까지 진다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      final card = tester.state<MetroCardState>(find.byType(MetroCard));
      expect(card.enterValue, 1);
      expect(card.leaving, isFalse);

      made.bus.slot(metroSlot).value = null;
      await tester.pump(); // 되감기가 걸린다
      expect(card.leaving, isTrue);
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('푸른 물결국'), findsOneWidget, reason: '아직 지는 중이다');
      expect(card.enterValue, lessThan(1));
      expect(card.enterValue, greaterThan(0));
      expect(card.openUid, isEmpty, reason: '지는 중인 카드는 열린 것으로 세지 않는다');

      await tester.pumpAndSettle(); // 공통 스프링이 정착하면 비운다
      expect(card.enterValue, 0);
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsNothing);
      expect(card.leaving, isFalse);
    });

    testWidgets('지는 도중에 다시 열면 되돌아 오른다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      final card = tester.state<MetroCardState>(find.byType(MetroCard));

      made.bus.slot(metroSlot).value = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsOneWidget);
      expect(card.leaving, isFalse);
      expect(card.enterValue, 1);
      expect(card.openUid, '견본/푸른물결국');
    });

    testWidgets('움직임을 끄면 지금 연표처럼 그 자리에서 곧바로 감춘다', (tester) async {
      final made = makeBus([sample()]);
      tester.view.physicalSize = const Size(1400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              backgroundColor: Ui.bg,
              body: Stack(children: [const SizedBox.expand(), MetroCard(bus: made.bus)]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsOneWidget);

      made.bus.slot(metroSlot).value = null;
      await tester.pump();
      expect(find.text('푸른 물결국'), findsNothing);
    });

    testWidgets('Esc로 닫힌다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      runCommand(made.bus, Cmd.close);
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsNothing);
      expect(made.bus.slot(metroSlot).value, isNull);
    });

    testWidgets('다른 항목을 고르면 닫히고, 그 정권을 고르면 그대로 있다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();

      made.bus.select('견본/푸른물결국');
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsOneWidget);

      made.bus.select('견본/잿빛항');
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsNothing);
    });

    testWidgets('역을 누르면 그 도읍 기간으로 간다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();

      await tester.tap(find.text('북쪽성'));
      await tester.pumpAndSettle();
      expect(made.went.length, 1);
      // 역이 품는 기간은 합쳐진 칸의 양 끝(100~300)이다.
      final (lo, hi) = metroViewOf(100, 300);
      expect(made.went.single.lo, lo);
      expect(made.went.single.hi, hi);
    });

    testWidgets('도시에 손을 올리면 날짜 칸의 그 이름을 비춘다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      final marks = SceneMarks.of(made.bus.scene);
      expect(marks.hotCity, isNull);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('북쪽성')));
      await tester.pumpAndSettle();
      expect(marks.hotCity, '북쪽성');

      await mouse.moveTo(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(marks.hotCity, isNull);
    });

    testWidgets('발의 다른 정권 단추를 누르면 그 나라의 노선도로 갈아탄다', (tester) async {
      final mine = sample(
        metro: {
          'peers': [
            {'uid': '견본/푸른물결국', 'name': '푸른 물결국', 'color': '#a0bcc5'},
            {'uid': '견본/잿빛항', 'name': '잿빛 항국', 'color': '#bba395'},
          ],
        },
      );
      final other = {
        'uid': '견본/잿빛항',
        'kind': 'period',
        'json': {
          'uid': '견본/잿빛항',
          'name': '잿빛 항국',
          'color': '#bba395',
          'start': 400,
          'endY': 500,
          'capitals': [
            {'city': '잿빛성', 'name': '잿빛성', 'role': 'main', 'start': 400, 'end': 500, 'endY': 500},
          ],
        },
      };
      final made = makeBus([mine, other]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      expect(find.text('역을 누르면 그 시기로 · ← → 다른 정권'), findsOneWidget);

      await tester.tap(find.text('잿빛 항국'));
      await tester.pumpAndSettle();
      expect(find.text('잿빛성'), findsOneWidget);
      expect(metroUidOf(made.bus.slot(metroSlot).value), '견본/잿빛항');
    });

    testWidgets('📌로 고정하면 그 값이 슬롯에도 적힌다(손 올리기로 여는 쪽이 읽는다)', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      expect(made.bus.slot(metroSlot).value, isA<String>()); // 아직 글 하나뿐

      await tester.tap(find.byTooltip('카드 고정'));
      await tester.pumpAndSettle();
      final asked = made.bus.slot(metroSlot).value as MetroRequest;
      expect(asked.uid, '견본/푸른물결국');
      expect(asked.pinned, isTrue);

      await tester.tap(find.byTooltip('고정 풀기'));
      await tester.pumpAndSettle();
      expect((made.bus.slot(metroSlot).value as MetroRequest).pinned, isFalse);
    });

    testWidgets('도읍이 없는 항목이면 열지 않고 한 줄로 알린다', (tester) async {
      final made = makeBus([sample(capitals: [])]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '견본/푸른물결국';
      await tester.pumpAndSettle();
      expect(find.text('푸른 물결국'), findsNothing);
      expect(made.bus.slot(slotNotice).value, '도읍 내력이 없어 노선도를 열 수 없습니다.');
      expect(made.bus.slot(metroSlot).value, isNull);
    });

    testWidgets('기록을 읽지 못해도 빈 카드를 띄우지 않는다', (tester) async {
      final made = makeBus(const []);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = '없는/정권';
      await tester.pumpAndSettle();
      expect(find.byType(MetroCard), findsOneWidget);
      expect(made.bus.slot(slotNotice).value, isNotNull);
    });

    testWidgets('가리킬 자리를 주면 그 오른쪽에 선다', (tester) async {
      final made = makeBus([sample()]);
      await pumpCard(tester, made.bus);
      made.bus.slot(metroSlot).value = const MetroRequest('견본/푸른물결국', anchor: Rect.fromLTWH(40, 300, 150, 22));
      await tester.pumpAndSettle();
      final at = tester.getTopLeft(find.text('푸른 물결국'));
      expect(at.dx, greaterThan(190)); // 줄 이름의 오른쪽(190) 너머
      expect(at.dy, greaterThan(250));
      expect(at.dy, lessThan(340));
    });
  });

  // ── ③ 진짜 자료 처리부 + 진짜 저장소로 지금 연표와 맞대기 ────────────────────────────────
  group('지금 연표와 맞대기(진짜 엔진 · 진짜 저장소)', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final mineDb = File('../data/moonwake3-metro/archive.db');
    final mainDb = File('../data/moonwake3h/archive.db');
    final dump = File('../results/dom-metro/metro-dump.json');

    /// 저장소 하나에서 항목 기록을 읽어 카드가 읽는 꼴로.
    /// [dropX]면 읽어 온 기록에서 `x_metro`만 떼어 낸다 — 저장소에 그것이 실려 있든 아니든
    /// '도읍 칸만으로 선다'를 그대로 굳히려고(뒷날 주 저장소에 metro 모듈이 더해져도 검사가 흔들리지 않는다).
    Future<MetroData?> read(File db, String uid, {bool dropX = false}) async {
      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine.start(db.absolute.path);
      try {
        final answer = await engine.call({'op': 'entity', 'uid': uid});
        final data = answer['data'];
        if (data is! Map) return null;
        final one = Map<String, dynamic>.from(data);
        if (dropX) {
          final raw = one['json'] is Map ? Map<String, dynamic>.from(one['json'] as Map) : jsonDecode('${one['json']}');
          if (raw is! Map) return null;
          raw.remove('x_metro');
          one['json'] = jsonEncode(raw);
        }
        return MetroData.fromAnswer(one);
      } finally {
        engine.close();
      }
    }

    Map<String, dynamic>? scene(String name) {
      if (!dump.existsSync()) return null;
      final all = jsonDecode(dump.readAsStringSync()) as Map;
      final one = all[name];
      return one is Map ? one.cast<String, dynamic>() : null;
    }

    /// 기준 덤프의 svg에서 한 갈래의 좌표를 뽑는다.
    List<double> xsOf(Map<String, dynamic> one, String css, String key) => [
      for (final g in (one['svg'] as List))
        if (g is Map && '${g['c']}' == css && g[key] != null) double.parse('${g[key]}'),
    ];

    final ready = dll.existsSync() && mineDb.existsSync() && dump.existsSync();
    const noData = '자료 처리부 DLL · data/moonwake3-metro 저장소 · results/dom-metro 기준 덤프 가운데 없는 것이 있습니다';

    test('은륜 제국 — 역 · 우회 · 지선의 자리가 지금 연표와 같다', () async {
      await loadFonts();
      final data = await read(mineDb, 'moonwake-chronicle/p-coast-6');
      expect(data, isNotNull, reason: 'x_metro가 실린 항목 기록을 읽어야 한다');
      final plan = MetroPlan.of(data!, measureMetroText);
      final one = scene('은륜제국')!;

      // 기준: 본선 45 · 역 28 / 336.1 / 553.1 / 757.7 · 우회 276.1 · 끝 922.3 · 노선도 946×121
      expect(plan.mainY, closeTo(double.parse('${(one['svg'] as List).first['y1']}'), .01));
      final stops = [for (final n in plan.nodes) n.x];
      final want = [...xsOf(one, 'm-stop is-main', 'cx'), ...xsOf(one, 'm-stop is-temp', 'cx'), ...xsOf(one, 'm-stop', 'cx')]..sort();
      final got = [...stops]..sort();
      expect(got.length, want.length);
      for (int i = 0; i < want.length; i++) {
        expect(got[i], closeTo(want[i], 2), reason: '${i + 1}번째 역');
      }
      expect(plan.xEnd, closeTo(xsOf(one, 'm-end', 'cx').single, 2));
      expect(plan.mapWidth, closeTo((one['map'] as List)[0] as num, 3));
      expect(plan.mapHeight, (one['map'] as List)[1]);
      expect(plan.branches.single.x, closeTo(41, 2));
      expect(plan.branches.single.y, 17);
      expect(plan.summary(data.range), '도읍 4곳 · 천도 4번 · 720년 ~ 960년');
    }, skip: ready ? false : noData);

    test('도읍이 하나뿐인 나라 — 역 하나와 끝', () async {
      await loadFonts();
      final data = (await read(mineDb, 'moonwake-chronicle/client-3'))!;
      final plan = MetroPlan.of(data, measureMetroText);
      final one = scene('잔닻종속국')!;
      expect(plan.nodes.length, 1);
      expect(plan.mainY, 20);
      expect(plan.nodes.single.x, 28);
      expect(plan.xEnd, closeTo(xsOf(one, 'm-end', 'cx').single, 2));
      expect(plan.mapWidth, (one['map'] as List)[0]);
      expect(plan.mapHeight, (one['map'] as List)[1]);
      expect(plan.hasXfer, isFalse);
      expect(plan.hasDetour, isFalse);
    }, skip: ready ? false : noData);

    test('x_metro가 실려 있고 환승 · 발의 단추가 살아 있다', () async {
      final data = (await read(mineDb, 'moonwake-chronicle/p-coast-6'))!;
      expect(data.xfer.keys, containsAll(['유리항', '파도문', '흰계단', '별목']));
      expect(data.peers.length, 22);
      expect(data.peers.any((q) => q.uid == 'moonwake-chronicle/p-coast-6'), isTrue);
      final plan = MetroPlan.of(data, measureMetroText);
      expect(plan.hasXfer, isTrue);
      expect(plan.nodes.first.chip!.text, '⇄ 유리항 패총국 외 15');
    }, skip: ready ? false : noData);

    test('x_metro가 없어도 본선 · 지선 · 우회가 선다(조용히 비지 않는다)', () async {
      // 주 저장소의 진짜 기록을 그대로 읽되 `x_metro`만 떼어 낸다. 저장소에 그것이 실렸는지에 기대지 않으므로
      // `export-layout.mjs`의 MODULES에 'metro'가 더해져 주 저장소를 다시 내보내도 이 검사는 그대로 선다.
      final data = (await read(mainDb, 'moonwake-chronicle/p-coast-6', dropX: true))!;
      expect(data.xfer, isEmpty, reason: 'x_metro를 떼어 냈으니 환승 표가 비어 있어야 한다(떼기가 먹혔는지 확인)');
      final plan = MetroPlan.of(data, measureMetroText);
      expect(plan.nodes.length, 4 + 1); // 역 넷 + 우회 하나
      expect(plan.branches.length, 1);
      expect(plan.hasXfer, isFalse);
      expect(plan.summary(data.range), '도읍 4곳 · 천도 4번 · 720년 ~ 960년');
      expect(data.capitals[0].when, '720년 ~ 825년'); // 스스로 만든 날짜 글이 x_metro의 것과 같다

      // x_metro가 **실린** 저장소에서 떼어 내도 같은 값이 나온다 — 주 저장소에 metro 모듈이
      // 더해진 뒤의 모습을 미리 확인한 것이다(그때도 이 검사는 그대로 선다).
      if (mineDb.existsSync()) {
        final loaded = (await read(mineDb, 'moonwake-chronicle/p-coast-6', dropX: true))!;
        expect(loaded.xfer, isEmpty);
        expect(loaded.peers, isEmpty);
        final planOfLoaded = MetroPlan.of(loaded, measureMetroText);
        expect([for (final n in planOfLoaded.nodes) n.x], [for (final n in plan.nodes) n.x]);
        expect(planOfLoaded.branches.length, plan.branches.length);
        expect(planOfLoaded.hasXfer, isFalse);
        expect(planOfLoaded.summary(loaded.range), plan.summary(data.range));
        expect(loaded.capitals[0].when, data.capitals[0].when);
      }
    }, skip: dll.existsSync() && mainDb.existsSync() ? false : noData);
  });

  // 1920×1080 그림 뜨기 — 지금 연표의 `results/dom-metro/노선도-*.png`와 나란히 놓는다.
  testWidgets(
    '그림 뜨기(OUT을 줄 때만)',
    (tester) async {
      await loadFonts();
      const scenes = [
        ('은륜제국', 'moonwake-chronicle/p-coast-6'),
        ('유리항패총국', 'moonwake-chronicle/p-coast-0'),
        ('잔닻종속국', 'moonwake-chronicle/client-3'),
      ];
      // 저장소 읽기는 진짜 입출력이라 먼저 한 번에 읽어 둔다(그다음은 가짜 자료 처리부가 그대로 물린다).
      final records = <Map<String, dynamic>>[];
      await tester.runAsync(() async {
        final engine = ArchiveEngine(libraryPath: File('../engine/target/release/archive_engine.dll').absolute.path);
        await engine.start(File('../data/moonwake3-metro/archive.db').absolute.path);
        for (final (_, uid) in scenes) {
          final answer = await engine.call({'op': 'entity', 'uid': uid});
          records.add(Map<String, dynamic>.from(answer['data'] as Map));
        }
        engine.close();
      });
      final made = makeBus(records);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
          home: Scaffold(
            backgroundColor: Ui.bg,
            // 카드 한 장만 뜬다 — 지금 연표의 `results/dom-metro/카드-*.png`와 같은 크기 · 같은 자리(0, 0)다.
            body: Stack(children: [const SizedBox.expand(), MetroCard(bus: made.bus, gutter: -8, head: -4)]),
          ),
        ),
      );
      final folder = Directory(captureTo)..createSync(recursive: true);
      for (final (name, uid) in scenes) {
        made.bus.slot(metroSlot).value = uid;
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(metroCardKey));
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ImageByteFormat.png);
          image.dispose();
          File('${folder.path}/카드-$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
        made.bus.slot(metroSlot).value = null;
        await tester.pumpAndSettle();
      }
    },
    skip: captureTo.isEmpty,
  );
}

/// 해 좌표 → 계약의 시간(분). 검사에서 `metroViewOf`의 답을 맞대 볼 때 쓴다.
double minutesOfTFor(double t) => minutesOfT(t);
