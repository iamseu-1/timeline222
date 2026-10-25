import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellKind, StripHit;
import 'package:archive_prototype/scene/viewport.dart' show SceneView;
import 'package:archive_prototype/shell/parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/cards.dart';
import 'package:archive_prototype/ui/date_text.dart' show minutesOfT;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 묶음 카드와 도착 고리 검사(명세 06의 4-1 · 4-4).
// 자료는 월흔해 견본(가상)에서 뽑은 test/fixtures/cluster-events.json — 한 줄에 몰린 사건 열둘이고,
// 가짜 ask가 {op:'list'}의 답 꼴로 50개씩 돌려준다. uid · color · look · label은 자료 처리부에 더 달라고 적어 둔 열이다.

final List<Map<String, dynamic>> fixture = [
  for (final raw in (jsonDecode(File('test/fixtures/cluster-events.json').readAsStringSync()) as Map)['items'] as List)
    Map<String, dynamic>.from(raw as Map),
];

/// 견본으로 {op:'list'}에 답하는 가짜 자료 처리부. 물은 것을 [asked]에 적는다.
Future<Map<String, dynamic>> Function(Map<String, dynamic>) fakeAsk(List<Map<String, dynamic>> asked) => (query) async {
  asked.add(query);
  if (query['op'] != 'list') return <String, dynamic>{};
  final lo = (query['lo'] as num).toDouble(), hi = (query['hi'] as num).toDouble();
  final lane = query['lane'] as int, lanes = query['lanes'] as int, after = (query['after'] as num?)?.toInt() ?? 0;
  final hit = [
    for (final item in fixture)
      if ((item['start'] as num) >= lo && (item['start'] as num) <= hi && item['lane'] as int >= lane && (item['lane'] as int) < lane + lanes && (item['id'] as int) > after) item,
  ];
  final page = hit.length > 50 ? hit.sublist(0, 50) : hit;
  return {'items': page, 'has_more': hit.length > 50, 'next': page.isEmpty ? null : page.last['id']};
};

/// 견본 열둘을 모두 품는 묶음. 기간이 넓어 '이 구간 확대'가 붙는다.
ClusterSpan wholeCluster({String key = 'c1', int count = 12}) => ClusterSpan(
  key: key,
  row: 1,
  lo: (fixture.first['start'] as num).toDouble(),
  hi: (fixture.last['start'] as num).toDouble(),
  count: count,
  color: const Color(0xff9c978d),
);

void main() {
  group('날짜 글', () {
    test('자세함만큼 적는다 — 기원전도 같은 꼴', () {
      final at842 = (fixture.first['start'] as num).toDouble();
      expect(stampAt(at842, 0), '842년');
      expect(stampAt(at842, 1), '842년 1월');
      expect(stampAt(-1497378240, 0), '기원전 878년');
    });

    test('카드 줄의 날짜는 적힌 만큼 자세히, 다만 날까지만', () {
      expect(cardWhen('842년', (fixture.first['start'] as num).toDouble()), '842년');
      expect(cardWhen('842년 5월 12일', (fixture[2]['start'] as num).toDouble()), '842년 5월 12일');
      // 시 · 분까지 적힌 사건도 카드에서는 날까지만(지금 연표의 showCard와 같다).
      expect(cardWhen('842년 6월 17일 16시 10분', (fixture[4]['start'] as num).toDouble()), '842년 6월 17일');
      expect(cardWhen(null, 0, startUnknown: true), '미정');
    });
  });

  group('여는 때 · 닫는 때(ClusterCardController)', () {
    Future<(AppBus, ClusterCardController)> pumpBus(WidgetTester tester) async {
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final bus = AppBus(ask: fakeAsk([]), controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      final cards = ClusterCardController(bus: bus);
      addTearDown(cards.dispose);
      await tester.pumpWidget(const SizedBox());
      return (bus, cards);
    }

    testWidgets('처음은 160ms · 이미 열려 있으면 60ms 뒤에 열리고, 벗어나면 220ms 뒤에 닫힌다', (tester) async {
      final (_, cards) = await pumpBus(tester);
      final one = wholeCluster(), two = wholeCluster(key: 'c2');
      cards.hover(one, anchor: Rect.zero);
      await tester.pump(const Duration(milliseconds: 159));
      expect(cards.cluster, isNull, reason: '처음은 160ms를 기다린다');
      await tester.pump(const Duration(milliseconds: 2));
      expect(cards.cluster, one);

      cards.hover(two, anchor: Rect.zero);
      await tester.pump(const Duration(milliseconds: 59));
      expect(cards.cluster, one, reason: '카드가 이미 열려 있으면 60ms');
      await tester.pump(const Duration(milliseconds: 2));
      expect(cards.cluster, two);

      cards.hover(null);
      await tester.pump(const Duration(milliseconds: 219));
      expect(cards.cluster, two);
      await tester.pump(const Duration(milliseconds: 2));
      expect(cards.cluster, isNull);
    });

    testWidgets('움직이는 중에는 열지 않고, 멎은 뒤에 손이 그 위면 그때 연다', (tester) async {
      final (bus, cards) = await pumpBus(tester);
      bus.controller.dragging = true;
      cards.hover(wholeCluster(), anchor: Rect.zero);
      await tester.pump(const Duration(milliseconds: 400));
      expect(cards.cluster, isNull, reason: '손에 잡힌 동안은 고요하다');

      bus.controller.dragging = false;
      cards.motionEnded();
      await tester.pump(const Duration(milliseconds: 160));
      expect(cards.cluster, isNotNull);
    });

    testWidgets('우리가 세로로 옮긴 직후 0.2초도 열지 않는다', (tester) async {
      final (_, cards) = await pumpBus(tester);
      cards.markSelfScroll();
      cards.hover(wholeCluster(), anchor: Rect.zero);
      await tester.pump(const Duration(milliseconds: 190));
      expect(cards.cluster, isNull);
      // 0.2초가 지나면 손 밑의 것을 그때 연다(다시 160ms).
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 170));
      expect(cards.cluster, isNotNull);
    });

    testWidgets('누르면 좁은 묶음은 고정, 넓은 묶음은 그 구간 확대가 된다', (tester) async {
      final (bus, cards) = await pumpBus(tester);
      // 가장 좁은 보기의 두 배보다 좁은 묶음 → 고정.
      final tight = ClusterSpan(key: 'tight', row: 1, lo: 0, hi: TimelineController.minSpan, count: 3, color: const Color(0xff9c978d));
      expect(tight.canZoom, isFalse);
      cards.press(tight, anchor: Rect.zero);
      expect(cards.cluster, tight);
      expect(cards.pinned, isTrue);
      // 고정된 카드는 손이 벗어나도 닫히지 않는다.
      cards.hover(null);
      await tester.pump(const Duration(milliseconds: 400));
      expect(cards.cluster, tight);
      cards.close();

      // 넓은 묶음 → 카드 대신 그 구간 확대. 묶인 폭의 두 배가 새 보기다.
      final wide = wholeCluster();
      expect(wide.canZoom, isTrue);
      cards.press(wide, anchor: Rect.zero);
      expect(cards.cluster, isNull);
      final go = bus.go.value!;
      expect(go.hi - go.lo, closeTo((wide.hi - wide.lo) * 2, .001));
      expect((go.lo + go.hi) / 2, closeTo((wide.lo + wide.hi) / 2, .001));
    });
  });

  group('묶음 카드', () {
    Future<(AppBus, List<Map<String, dynamic>>, List<String>)> pumpCard(
      WidgetTester tester, {
      required Rect anchor,
      ClusterSpan? cluster,
      bool pinned = false,
      int precision = 0,
    }) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final asked = <Map<String, dynamic>>[];
      final closed = <String>[];
      final bus = AppBus(ask: fakeAsk(asked), controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: ClusterCard(
                    bus: bus,
                    cluster: cluster ?? wholeCluster(),
                    anchor: anchor,
                    pinned: pinned,
                    precision: precision,
                    onClose: () => closed.add('닫기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(); // 가짜 ask의 답
      await tester.pumpAndSettle(); // 공통 pop / in 스프링이 정착한 자리
      return (bus, asked, closed);
    }

    testWidgets('머리에 개수와 기간, 줄은 아홉까지, 나머지는 외 n개', (tester) async {
      final (_, asked, _) = await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16));
      expect(asked.single['op'], 'list');
      expect(asked.single['lane'], 1);
      expect(asked.single['lanes'], 1);
      expect(find.text('사건 12개'), findsOneWidget);
      expect(find.text('842년'), findsWidgets, reason: '해 눈금이면 머리의 기간도 해까지');
      expect(find.text('외 3개'), findsOneWidget);
      // 아홉 줄: 첫 줄은 시작이 같으면 중요도가 높은 것.
      expect(find.text('뒤늦게 읽힌 등대 일지'), findsOneWidget);
      expect(find.text('검푸른문 절벽 · 사라진 길의 재출현'), findsOneWidget);
      expect(find.text('긴 밤 · 물밑 회랑 개방'), findsOneWidget);
      expect(find.text('긴 밤 · 첫 기억 반환'), findsNothing, reason: '열째부터는 외 n개로만');
      // ★는 중요도 3에만 — 견본에는 셋.
      expect(find.text('★'), findsNWidgets(3));
    });

    testWidgets('차례는 시작 → 중요도 내림차순', (tester) async {
      await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16));
      double topOf(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(topOf('뒤늦게 읽힌 등대 일지'), lessThan(topOf('검푸른문 절벽 · 사라진 길의 재출현')), reason: '시작이 같으면 중요한 것이 먼저');
      expect(topOf('검푸른문 절벽 · 사라진 길의 재출현'), lessThan(topOf('소금끝 반환 협약')));
      expect(topOf('소금끝 반환 협약'), lessThan(topOf('별목의 가장 긴 밤')));
    });

    testWidgets('자리: 알약 아래 4px · 폭 288 · 아래가 모자라면 위 4px · 왼쪽 칸 안으로는 들어가지 않는다', (tester) async {
      await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16));
      final card = tester.renderObject<RenderBox>(find.byType(GlassCard));
      final at = card.localToGlobal(Offset.zero);
      expect(card.size.width, CardLook.width);
      expect(at.dy, closeTo(316 + CardLook.anchorGap, .01));
      expect(at.dx, closeTo(810 - CardLook.width / 2, .01), reason: '알약 가운데에 맞춘다');
      final height = card.size.height;

      // 아래가 모자라면 알약 위 4px.
      await pumpCard(tester, anchor: const Rect.fromLTWH(800, 900, 20, 16));
      final above = tester.renderObject<RenderBox>(find.byType(GlassCard)).localToGlobal(Offset.zero);
      expect(above.dy, closeTo(900 - height - CardLook.anchorGap, .01));

      // 왼쪽 끝에서는 왼쪽 칸(리메이크 2부 — 폭 240 고정) + 6px 안으로 밀려 들어간다.
      await pumpCard(tester, anchor: const Rect.fromLTWH(100, 300, 20, 16));
      final left = tester.renderObject<RenderBox>(find.byType(GlassCard)).localToGlobal(Offset.zero);
      expect(SceneView.gutter, 240);
      expect(left.dx, closeTo(SceneView.gutter + CardLook.gutterGap, .01));
    });

    testWidgets('줄을 누르면 그 사건을 고르고 카드를 닫는다', (tester) async {
      final (bus, _, closed) = await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16));
      await tester.tap(find.text('별목의 가장 긴 밤'));
      await tester.pump();
      expect(bus.selection.value!.uid, fixture[3]['uid']);
      expect(bus.selection.value!.eventId, fixture[3]['id']);
      expect(closed, ['닫기']);
    });

    testWidgets('이 구간 확대는 묶인 폭의 두 배가 새 보기가 되게 한다', (tester) async {
      final (bus, _, closed) = await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16));
      final cluster = wholeCluster();
      await tester.tap(find.text('⤢ 이 구간 확대'));
      await tester.pump();
      final go = bus.go.value!;
      expect(go.hi - go.lo, closeTo((cluster.hi - cluster.lo) * 2, .001));
      expect(closed, ['닫기']);
    });

    testWidgets('좁은 묶음에는 이 구간 확대가 붙지 않고, 아홉 줄 안이면 외 n개도 없다', (tester) async {
      final tight = ClusterSpan(
        key: 'tight',
        row: 1,
        lo: (fixture.first['start'] as num).toDouble(),
        hi: (fixture.first['start'] as num).toDouble() + TimelineController.minSpan,
        count: 2,
        color: const Color(0xff9c978d),
      );
      await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16), cluster: tight);
      expect(find.text('사건 2개'), findsOneWidget);
      expect(find.text('⤢ 이 구간 확대'), findsNothing);
      expect(find.textContaining('외 '), findsNothing);
    });

    testWidgets('고정한 카드에만 ✕가 붙는다', (tester) async {
      await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16));
      expect(find.text('✕'), findsNothing);
      final (_, _, closed) = await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16), pinned: true);
      expect(find.text('✕'), findsOneWidget);
      await tester.tap(find.text('✕'));
      await tester.pump();
      expect(closed, ['닫기']);
    });

    testWidgets('머리의 기간은 지금 눈금 단위만큼 자세히 — 날 눈금이면 두 끝을 날까지', (tester) async {
      await pumpCard(tester, anchor: const Rect.fromLTWH(800, 300, 20, 16), precision: 2);
      expect(find.text('842년 1월 1일 ~ 842년 6월 17일'), findsOneWidget);
    });

    testWidgets('열릴 때 pop으로 떠오르고 in으로 짙어진다', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final bus = AppBus(ask: fakeAsk([]), controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Stack(children: [Positioned.fill(child: ClusterCard(bus: bus, cluster: wholeCluster(), anchor: const Rect.fromLTWH(800, 300, 20, 16)))]),
          ),
        ),
      );
      await tester.pump(); // 답이 왔다 — 이제부터 떠오른다
      double opacity() => tester.widgetList<Opacity>(find.descendant(of: find.byType(ClusterCard), matching: find.byType(Opacity))).first.opacity;
      await tester.pump(const Duration(milliseconds: 90));
      final half = opacity();
      expect(half, greaterThan(0));
      expect(half, lessThan(1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });
  });

  group('도착 고리', () {
    testWidgets('ring 스프링으로 한 번 옅어지고, 다시 불리면 처음부터', (tester) async {
      final trigger = ValueNotifier<int?>(null);
      addTearDown(trigger.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<int?>(
                valueListenable: trigger,
                builder: (context, value, _) => ArrivalRing(trigger: value, radius: 6, child: const SizedBox(width: 120, height: 20)),
              ),
            ),
          ),
        ),
      );
      double ring() => (tester.widget<CustomPaint>(find.descendant(of: find.byType(ArrivalRing), matching: find.byType(CustomPaint)).first).foregroundPainter! as ArrivalRingPainter).opacity;
      expect(ring(), 0, reason: '부를 때까지는 그리지 않는다');

      trigger.value = 1;
      await tester.pump();
      expect(ring(), 1);
      await tester.pump(const Duration(milliseconds: 300));
      final mid = ring();
      expect(mid, lessThan(1));
      expect(mid, greaterThan(0));
      await tester.pumpAndSettle();
      expect(ring(), 0, reason: '되풀이하지 않는다');

      // 다시 부르면 앞 고리를 걷고 처음부터.
      trigger.value = 2;
      await tester.pump();
      expect(ring(), 1);
      await tester.pumpAndSettle();
      expect(ring(), 0);
    });
  });

  // ──────────────── 성씨 풍선(확정 설계 1-2 5-2 · 결정 6 A — D1-N3) ────────────────
  group('성씨 풍선', () {
    // 가상 견본: 가람 나라(띠 11)의 둘째 임금 칸이 '바람대군파'(본가 '물빛 온씨' — 성 온 · 본관 물빛)이고, 그 시기를 '온씨 왕실'이 다스렸다.
    final records = <String, Map<String, dynamic>>{
      'kin-example/garam': {
        'name': '가람 나라',
        'leaders': [
          {'name': '첫 임금', 'start': 1400, 'end': 1418, 'ordinal': 1},
          {'name': '둘째 임금', 'start': 1418, 'end': 1450, 'ordinal': 2, 'temple': '고요조', 'houseId': 'h-on-baram', 'note': '바람대군의 아들'},
        ],
        'x_dynasties': [
          {'uid': 'kin-example/d-on', 'name': '온씨 왕실', 'when': '1400년 ~ 1500년', 'span': [minutesOfT(1400), minutesOfT(1500)]},
        ],
        'x_cellNames': {
          'leader:1': {'main': [{'text': 'Dulsseo', 'lang': 'x-moon-Latn'}]},
        },
      },
      'kin-example/d-on': {'name': '온씨 왕실', 'houseId': 'h-on'},
      'house:h-on': {'id': 'h-on', 'name': '물빛 온씨', 'color': '#c8b193', 'surname': '온', 'seat': '물빛', 'path': ['h-on'], 'x_surname': {'uid': 'surname:on', 'name': '온'}},
      'house:h-on-baram': {
        'id': 'h-on-baram', 'name': '바람대군파', 'color': '#a0bcc5', 'path': ['h-on', 'h-on-baram'],
        'x_path': [
          {'uid': 'house:h-on', 'name': '물빛 온씨', 'color': '#c8b193'},
          {'uid': 'house:h-on-baram', 'name': '바람대군파', 'color': '#a0bcc5'},
        ],
      },
    };
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) balloonAsk(List<Map<String, dynamic>> asked) => (query) async {
      asked.add(query);
      if (query['op'] == 'uid_of' && query['kind'] == 'band' && query['id'] == 11) return {'uid': 'kin-example/garam', 'kind': 'period'};
      if (query['op'] == 'entity') {
        final r = records[query['uid']];
        if (r != null) return {'uid': query['uid'], 'kind': 'x', 'json': jsonEncode(r)};
      }
      throw StateError('모르는 물음 $query');
    };
    StripHit leader({Rect rect = const Rect.fromLTWH(800, 300, 120, 18), bool house = true}) => StripHit(
      11, 0, CellKind.leader, house ? 'leader:1' : 'leader:0', '', house ? '둘째 임금' : '첫 임금', rect,
      houseId: house ? 'h-on-baram' : '', houseName: house ? '바람대군파' : '', houseColor: house ? 0xffa0bcc5 : 0,
    );
    const dynasty = StripHit(11, 0, CellKind.dynasty, 'dynasty:0', 'kin-example/d-on', '온씨 왕실', Rect.fromLTWH(800, 280, 300, 15),
        houseId: 'h-on', houseName: '물빛 온씨', houseColor: 0xffc8b193);

    Future<(AppBus, HouseBalloonController, ValueNotifier<StripHit?>, List<Map<String, dynamic>>)> pumpLayer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final asked = <Map<String, dynamic>>[];
      final bus = AppBus(ask: balloonAsk(asked), controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      final source = ValueNotifier<StripHit?>(null);
      addTearDown(source.dispose);
      final balloons = HouseBalloonController(bus: bus, source: source);
      addTearDown(balloons.dispose);
      final cards = ClusterCardController(bus: bus);
      addTearDown(cards.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Stack(children: [Positioned.fill(child: ClusterCardLayer(bus: bus, cards: cards, balloons: balloons))])),
        ),
      );
      return (bus, balloons, source, asked);
    }

    Future<void> open(WidgetTester tester, ValueNotifier<StripHit?> source, StripHit hit) async {
      source.value = hit;
      await tester.pump(CardLook.hoverFirst);
      await tester.pump(); // 기록 받기
      await tester.pump();
      await tester.pumpAndSettle(); // 공통 pop / in 정착
    }

    test('지도자 칸: 머리 = 이름 · 기간, 그 아래 묘호 · 시호 · 이름 · 지위 한 줄, 원어 한 줄, 성씨(본가에서 물려받음) · 본관 · 가문(본가 길) · 왕조, 메모, 누르는 길', () async {
      final (scene, _, _) = makePackScene();
      final bus = AppBus(ask: balloonAsk([]), controller: scene.controller, scene: scene);
      final balloons = HouseBalloonController(bus: bus, source: ValueNotifier<StripHit?>(null));
      final data = (await loadBalloon(balloons, leader()))!;
      expect(data.head, '둘째 임금', reason: '머리는 이름 · 기간(웹 W3 _tipHTML)');
      expect(data.sub, '묘호 고요조', reason: '그 아래 옅은 한 줄');
      expect(data.when, '1418년 ~ 1450년');
      expect(data.native, '\u2068Dulsseo\u2069');
      expect([for (final r in data.rows) '${r.label} ${r.text}'], ['성씨 온', '본관 물빛', '가문 물빛 온씨 › 바람대군파', '왕조 온씨 왕실']);
      expect(data.rows[0].open, 'surname:on');
      expect(data.rows[0].kind, 'surname');
      expect(data.rows[2].open, 'house:h-on-baram');
      expect(data.rows[2].dot, const Color(0xffa0bcc5));
      expect(data.rows[3].open, isNull, reason: '왕조 줄은 누를 수 없다');
      expect(data.notes, ['바람대군의 아들']);
      expect(data.foot, '누르면 그 칸 · 가문을 누르면 가문 조명');
      balloons.dispose();
      bus.dispose();
      scene.dispose();
    });

    test('왕조 칸: 머리 = 왕조 이름 · 그 띠의 다스림 기간, 왕조 줄 없음 · 가문이 없는 칸은 가문 줄 없이', () async {
      final (scene, _, _) = makePackScene();
      final bus = AppBus(ask: balloonAsk([]), controller: scene.controller, scene: scene);
      final balloons = HouseBalloonController(bus: bus, source: ValueNotifier<StripHit?>(null));
      final data = (await loadBalloon(balloons, dynasty))!;
      expect(data.head, '온씨 왕실');
      expect(data.when, '1400년 ~ 1500년');
      expect([for (final r in data.rows) '${r.label} ${r.text}'], ['성씨 온', '본관 물빛', '가문 물빛 온씨']);
      expect(data.foot, '누르면 그 왕조 · 가문을 누르면 가문 조명');
      final plain = (await loadBalloon(balloons, leader(house: false)))!;
      expect(plain.head, '첫 임금');
      expect(plain.sub, isEmpty);
      expect([for (final r in plain.rows) r.label], ['왕조'], reason: '없는 줄은 뺀다');
      expect(plain.foot, '누르면 그 칸');
      balloons.dispose();
      bus.dispose();
      scene.dispose();
    });

    testWidgets('여는 때 · 닫는 때: 처음 160ms 뒤에 열리고, 벗어나면 220ms 뒤에 닫힌다 · 내각 칸에는 서지 않는다', (tester) async {
      final (_, balloons, source, _) = await pumpLayer(tester);
      source.value = leader();
      await tester.pump(const Duration(milliseconds: 159));
      expect(balloons.hit, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(balloons.hit?.key, '11|leader:1');
      source.value = null;
      await tester.pump(const Duration(milliseconds: 219));
      expect(balloons.hit, isNotNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(balloons.hit, isNull);
      // 내각 칸(종류 2)은 풍선이 없다.
      source.value = StripHit(11, 0, CellKind.cabinet, 'cabinet:0', '', '어느 내각', const Rect.fromLTWH(800, 330, 100, 16));
      await tester.pump(const Duration(milliseconds: 400));
      expect(balloons.hit, isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('움직이는 동안은 열지 않고, 열린 풍선도 걷는다', (tester) async {
      final (bus, balloons, source, _) = await pumpLayer(tester);
      await open(tester, source, leader());
      expect(find.text('둘째 임금'), findsOneWidget);
      expect(find.text('묘호 고요조'), findsOneWidget);
      bus.controller.active.value = true;
      expect(balloons.hit, isNull, reason: '보기가 옮겨지면 걷음');
      source.value = leader(rect: const Rect.fromLTWH(700, 300, 120, 18));
      await tester.pump(const Duration(milliseconds: 400));
      expect(balloons.hit, isNull);
      bus.controller.active.value = false;
      await tester.pump(CardLook.hoverFirst);
      expect(balloons.hit, isNotNull, reason: '멎은 뒤 손이 그 위면 그때 연다');
      await tester.pumpAndSettle();
    });

    testWidgets('자리: 칸 아래 8px · 칸 왼쪽에서 8px 앞 · 오른쪽 끝에서는 화면 안으로 · 아래가 모자라면 칸 위 8px · 화면 밖으로 나가지 않는다', (tester) async {
      final (bus, _, source, _) = await pumpLayer(tester);
      await open(tester, source, leader());
      var box = tester.renderObject<RenderBox>(find.byType(GlassCard));
      var at = box.localToGlobal(Offset.zero);
      expect(at.dx, closeTo(800 - BalloonLook.gap, .01));
      expect(at.dy, closeTo(318 + BalloonLook.gap, .01));
      expect(box.size.width, inInclusiveRange(BalloonLook.minWidth, BalloonLook.maxWidth));

      final head = bus.controller.view.head;
      for (final rect in const [Rect.fromLTWH(1850, 300, 60, 18), Rect.fromLTWH(1500, 1000, 120, 18), Rect.fromLTWH(200, 140, 40, 18), Rect.fromLTWH(1880, 1050, 30, 18)]) {
        source.value = null;
        await tester.pumpAndSettle();
        await open(tester, source, leader(rect: rect));
        box = tester.renderObject<RenderBox>(find.byType(GlassCard));
        at = box.localToGlobal(Offset.zero);
        final r = at & box.size;
        expect(r.left, greaterThanOrEqualTo(SceneView.gutter + BalloonLook.gutterGap - .01), reason: '$rect');
        expect(r.right, lessThanOrEqualTo(1920 - BalloonLook.edgeGap + .01), reason: '$rect');
        expect(r.top, greaterThanOrEqualTo(head + BalloonLook.topGap - .01), reason: '$rect');
        expect(r.bottom, lessThanOrEqualTo(1080 + .01), reason: '$rect');
        // 칸과 겹치지 않는다(아래 아니면 위).
        expect(r.overlaps(rect.deflate(.5)), isFalse, reason: '$rect · $r');
      }
      // 아래가 모자라면 칸 위 8px.
      source.value = null;
      await tester.pumpAndSettle();
      await open(tester, source, leader(rect: const Rect.fromLTWH(800, 1000, 120, 18)));
      box = tester.renderObject<RenderBox>(find.byType(GlassCard));
      expect(box.localToGlobal(Offset.zero).dy + box.size.height, closeTo(1000 - BalloonLook.gap, .01));
      await tester.pumpAndSettle();
    });

    testWidgets('가문 줄을 누르면 가문 창 · 성씨 줄을 누르면 성씨 창을 고르고 풍선을 걷는다', (tester) async {
      final (bus, balloons, source, _) = await pumpLayer(tester);
      await open(tester, source, leader());
      expect(find.text('물빛 온씨 › 바람대군파'), findsOneWidget);
      expect(find.text('누르면 그 칸 · 가문을 누르면 가문 조명'), findsOneWidget);
      await tester.tap(find.text('물빛 온씨 › 바람대군파'));
      await tester.pump();
      expect(bus.selection.value?.uid, 'house:h-on-baram');
      expect(bus.selection.value?.kind, 'house');
      expect(balloons.hit, isNull);
      await tester.pumpAndSettle();
      expect(find.byType(GlassCard), findsNothing, reason: '160ms에 옅어지며 걷힘');
      source.value = null;
      await tester.pump();
      await open(tester, source, leader());
      await tester.tap(find.text('온'));
      await tester.pump();
      expect(bus.selection.value?.uid, 'surname:on');
      expect(bus.selection.value?.kind, 'surname');
      await tester.pumpAndSettle();
    });

    testWidgets('풍선 위에 손이 있으면 칸에서 벗어나도 닫지 않고, 풍선에서 벗어나면 220ms 뒤에 닫는다', (tester) async {
      final (_, balloons, source, _) = await pumpLayer(tester);
      await open(tester, source, leader());
      balloons.enterCard();
      source.value = null;
      await tester.pump(const Duration(milliseconds: 500));
      expect(balloons.hit, isNotNull);
      balloons.exitCard();
      await tester.pump(const Duration(milliseconds: 219));
      expect(balloons.hit, isNotNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(balloons.hit, isNull);
      await tester.pumpAndSettle();
    });
  });
}
