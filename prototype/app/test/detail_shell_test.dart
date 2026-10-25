import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/detail_item.dart' show kindShortOf;
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 상세 창의 뼈대(명세 06의 2-1 · 2-2절): 치수 · 갈래 고르기 · 등록 방식 · 날짜 칸 폭 맞춤.

/// 검사용 AppBus — 항목 기록은 test/fixtures의 견본에서 꺼내 준다.
({AppBus bus, List<Map<String, dynamic>> asked}) makeBus({List<String> fixtures = const ['entities-basic.json']}) {
  final store = <String, Map<String, dynamic>>{};
  for (final name in fixtures) {
    final raw = File('test/fixtures/$name').readAsStringSync();
    for (final e in jsonDecode(raw) as List) {
      final row = (e as Map).cast<String, dynamic>();
      store[row['uid'] as String] = row;
    }
  }
  final asked = <Map<String, dynamic>>[];
  final controller = TimelineController()..resize(1920, 500);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('상세 창 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      if (query['op'] == 'entity') {
        final row = store[query['uid']];
        if (row == null) throw StateError('없는 항목');
        return row;
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, asked: asked);
}

/// 부품 하나를 띄우는 작은 틀.
Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Ui.bg,
    body: SizedBox(width: Ui.detailWidth, child: child),
  ),
);

void main() {
  group('창 뼈대', () {
    testWidgets('머리 · 몸통 · 아래 단추 줄의 치수가 지금 연표와 같다', (tester) async {
      await tester.pumpWidget(
        host(
          DetailShell(
            onClose: () {},
            badges: const [DetailBadge('유리해안'), DetailBadge('해민')],
            body: const [DetailTitle('유리항 패총국'), DetailWhen('기원전 960년 ~ 기원전 400년'), DetailDesc('마을들이 기억을 물건에 남기기 시작했다.')],
            foot: [DetailSmallButton('이 위치로', onTap: () {})],
          ),
        ),
      );
      // 제목 h2 — 20px/700 · 자간 −.02em(HistoryArchive의 h1 — css/viewer.css 끝의 `.detail h2`).
      final title = tester.widget<Text>(find.text('유리항 패총국'));
      expect(title.style!.fontSize, 20);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(title.style!.letterSpacing, closeTo(-.4, 1e-6));
      // 날짜 줄 — 14px/500 · --text-3.
      final when = tester.widget<Text>(find.textContaining('기원전 960년'));
      expect(when.style!.fontSize, 14);
      expect(when.style!.color, Ui.text3);
      // 설명 — 읽는 글이라 명조 15px · 줄 높이 24.
      expect(tester.widget<Text>(find.textContaining('마을들이')).style!.height, 24 / 15);
      expect(tester.widget<Text>(find.textContaining('마을들이')).style!.fontFamily, Ui.serif);
      // 아래 단추 — 높이 28.
      expect(tester.getSize(find.text('이 위치로').first).height, lessThan(28));
      expect(find.text('✕'), findsOneWidget);
    });

    testWidgets('제목 뒤의 작은 글(제도 창의 `주제 〈나라〉`) — 글자 크기의 1/1.2', (tester) async {
      await tester.pumpWidget(host(const Column(children: [DetailTitle('조세제도', small: '솔나라'), DetailTitle('작은 글 없는 제목')])));
      final rich = tester.widget<Text>(find.text('조세제도 솔나라'));
      expect(rich.style!.fontSize, 20);
      final small = (rich.textSpan! as TextSpan).children!.single as TextSpan;
      expect(small.text, ' 솔나라');
      expect(small.style!.fontSize, 20 / 1.2);
      // 작은 글이 없으면 지금 그대로(글 하나).
      expect(tester.widget<Text>(find.text('작은 글 없는 제목')).data, '작은 글 없는 제목');
    });

    testWidgets('설명이 비면 안내 글이 기울임으로 선다', (tester) async {
      await tester.pumpWidget(host(const DetailShell(body: [DetailDesc('')])));
      final empty = tester.widget<Text>(find.text('설명이 없습니다.'));
      expect(empty.style!.fontStyle, FontStyle.italic);
      expect(empty.style!.color, Ui.text3);
    });

    testWidgets('아래 단추 줄이 비면 그 칸을 아예 그리지 않는다', (tester) async {
      await tester.pumpWidget(host(const DetailShell(body: [DetailTitle('이름만')])));
      expect(find.byType(DetailSmallButton), findsNothing);
    });

    testWidgets('정의 목록은 위에 선 하나를 두고 낱말과 값을 두 칸으로 놓는다', (tester) async {
      await tester.pumpWidget(
        host(
          const DetailShell(
            body: [
              DetailDefs([DetailDef('제공', Text('월흔해 연대기')), DetailDef('중요도', Text('★★★'))]),
            ],
          ),
        ),
      );
      expect(find.text('제공'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);
      final term = tester.widget<Text>(find.text('제공'));
      expect(term.style!.color, Ui.text3);
      expect(term.style!.fontSize, 13);
    });
  });

  group('목록 부품', () {
    testWidgets('승계 줄을 누르면 그 항목이 열린다', (tester) async {
      String? opened;
      await tester.pumpWidget(
        host(
          DetailShell(
            body: [
              DetailSuccList([
                DetailSuccRow(badge: '직접', badgeStyle: SuccBadge.direct, name: '별목 등불연맹', years: '기원전 400년 ~ 기원전 100년', onTap: () => opened = '별목 등불연맹'),
              ]),
            ],
          ),
        ),
      );
      await tester.tap(find.text('별목 등불연맹'));
      expect(opened, '별목 등불연맹');
      expect(find.text('직접'), findsOneWidget);
    });

    testWidgets('구분 칸의 폭은 목록 안에서만 맞춘다 — 다른 목록의 긴 이름표가 넓히지 않는다', (tester) async {
      await tester.pumpWidget(
        host(
          const DetailShell(
            body: [
              DetailSuccList([
                DetailSuccRow(badge: '국가', name: '첫 목록 가'),
                DetailSuccRow(badge: '연맹', name: '첫 목록 나'),
              ]),
              DetailSuccList([
                DetailSuccRow(badge: '할거', name: '둘째 목록 가'),
                DetailSuccRow(badge: '부흥 운동', name: '둘째 목록 나'),
              ]),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final a = tester.getTopLeft(find.text('첫 목록 가')).dx;
      expect(tester.getTopLeft(find.text('첫 목록 나')).dx, closeTo(a, 0.5));
      final b = tester.getTopLeft(find.text('둘째 목록 가')).dx;
      expect(tester.getTopLeft(find.text('둘째 목록 나')).dx, closeTo(b, 0.5));
      expect(b, greaterThan(a + 10));
    });

    testWidgets('종류는 짧은 이름으로 적고, 올리면 긴 이름이 뜬다', (tester) async {
      await tester.pumpWidget(
        host(
          DetailShell(
            body: [
              DetailSuccList([
                DetailSuccRow(badge: kindShortOf('부흥·저항 세력'), badgeHint: '부흥·저항 세력', name: '진주파'),
                DetailSuccRow(badge: kindShortOf('하연인'), badgeHint: '하연인', name: '모르는 글은 그대로'),
              ]),
            ],
          ),
        ),
      );
      expect(find.text('세력'), findsOneWidget);
      expect(find.text('하연인'), findsOneWidget);
      expect(find.text('부흥·저항 세력'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('세력')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('부흥·저항 세력'), findsOneWidget);
    });

    testWidgets('날짜 칸의 폭은 창 안에서 하나로 맞는다', (tester) async {
      await tester.pumpWidget(
        host(
          const DetailShell(
            body: [
              DetailYearEvents([
                DetailYearRow(when: '827년', title: '짧은 날짜'),
                DetailYearRow(when: '기원전 1200년 5월 12일', title: '긴 날짜'),
              ]),
            ],
          ),
        ),
      );
      await tester.pump(); // 잰 폭이 퍼지는 판
      await tester.pump();
      final a = tester.getTopLeft(find.text('짧은 날짜'));
      final b = tester.getTopLeft(find.text('긴 날짜'));
      expect(a.dx, closeTo(b.dx, 0.5));
    });

    testWidgets('칸 목록은 좁으면 한 칸, 넓으면 여러 칸으로 놓는다', (tester) async {
      await tester.pumpWidget(
        host(
          const DetailShell(
            body: [
              DetailCellList([
                DetailCellTile(year: '기원전 960년', name: '은결 나나나'),
                DetailCellTile(year: '기원전 867년', name: '은결 레나나'),
              ]),
            ],
          ),
        ),
      );
      // 창 폭 380 − 안쪽 36 = 344 → (344+8)/148 = 2칸.
      final a = tester.getTopLeft(find.text('은결 나나나'));
      final b = tester.getTopLeft(find.text('은결 레나나'));
      expect(b.dx, greaterThan(a.dx));
      expect(b.dy, closeTo(a.dy, 0.5));
    });

    testWidgets('다른 견해의 첫 줄만 바탕이 있다', (tester) async {
      await tester.pumpWidget(
        host(
          const DetailShell(
            body: [
              DetailAltList([
                DetailAltRow(when: '808년', why: '이 연표가 쓰는 연대', main: true),
                DetailAltRow(when: '804년', why: '광부 구술설'),
              ]),
            ],
          ),
        ),
      );
      expect(find.text('808년'), findsOneWidget);
      expect(find.text('광부 구술설'), findsOneWidget);
    });
  });

  group('갈래 고르기 — 명세 2-2의 표', () {
    test('앞에서부터 처음 맞는 갈래가 이긴다', () {
      expect(pickDetailKind(kind: 'epoch').id, 'epoch');
      expect(pickDetailKind(kind: 'scope').id, 'scope');
      expect(pickDetailKind(kind: 'period', cell: 'phase:0:1').id, 'phase');
      expect(pickDetailKind(kind: 'period', cell: 'rank:2').id, 'rank');
      expect(pickDetailKind(kind: 'period', cell: 'leader:3').id, 'cell');
      expect(pickDetailKind(kind: 'period', cell: 'capital:0').id, 'cell');
      expect(pickDetailKind(kind: 'period', cell: 'figures').id, 'figures-of');
      expect(pickDetailKind(kind: 'figure').id, 'figure');
      expect(pickDetailKind(kind: 'house').id, 'house');
      expect(pickDetailKind(kind: 'period').id, 'item');
      expect(pickDetailKind(kind: 'event').id, 'item');
    });

    test('왕조는 다스린 구간이 있을 때만 제 갈래로 간다', () {
      expect(pickDetailKind(kind: 'dynasty').id, 'item');
      expect(
        pickDetailKind(kind: 'dynasty', json: const {
          'x_ruled': [
            {'uid': 'a'},
          ],
        }).id,
        'dynasty',
      );
    });

    test('갈래의 성질 — 가문은 고르지 않고, 제 줄이 없는 것은 닻을 걸지 않는다', () {
      expect(pickDetailKind(kind: 'house').pick, isFalse);
      expect(pickDetailKind(kind: 'house').lane, isFalse);
      expect(pickDetailKind(kind: 'epoch').lane, isFalse);
      expect(pickDetailKind(kind: 'scope').lane, isFalse);
      // 칸 · 시기 · 지위만 그 강조를 사건 배치에도 쓴다(layout).
      expect(pickDetailKind(kind: 'period', cell: 'leader:0').always, isTrue);
      expect(pickDetailKind(kind: 'figure').always, isFalse);
    });

    test('단체 · 제도(형식 3)는 제 갈래 — 고르지 않고 세로 닻도 조명도 없다(웹 DETAIL_KINDS의 group · institution)', () {
      expect(pickDetailKind(kind: 'group').id, 'group');
      expect(pickDetailKind(kind: 'institution').id, 'institution');
      // 종류를 모르고 골랐어도(검색 · 칩) 기록의 itemKind로 간다.
      expect(pickDetailKind(kind: '', json: const {'itemKind': 'group'}).id, 'group');
      expect(pickDetailKind(kind: '', json: const {'itemKind': 'institution'}).id, 'institution');
      for (final id in ['group', 'institution']) {
        final k = pickDetailKind(kind: id);
        expect(k.pick, isFalse, reason: '$id — 연표를 흐리게 하지 않는다');
        expect(k.lane, isFalse, reason: '$id — 제 줄이 없다');
        expect(k.spot, isFalse);
        expect(k.always, isFalse);
      }
      // 차례: 가문 다음 · 기본 앞(웹이 '기본' 바로 앞에 끼운 자리).
      final ids = [for (final k in detailKinds) k.id];
      expect(ids.sublist(ids.indexOf('house')), ['house', 'group', 'institution', 'item']);
      // 칸 참조가 있으면 칸 창이 먼저다(단체 기록에 칸이 붙을 일은 없지만 차례는 명세 그대로).
      expect(pickDetailKind(kind: 'group', cell: 'leader:0').id, 'cell');
    });
  });

  group('DetailHost', () {
    setUp(() {
      for (final k in detailKinds) {
        DetailHost.unregister(k.id);
      }
    });

    testWidgets('고르면 항목 기록을 받아 등록된 갈래를 띄운다', (tester) async {
      final made = makeBus();
      DetailHost.register('item', (ctx) => DetailShell(onClose: ctx.close, body: [DetailTitle(ctx.name)]));
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [DetailHost(bus: made.bus)]),
        ),
      );
      expect(find.byType(DetailShell), findsNothing);

      made.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      expect(find.text('유리항 패총국'), findsOneWidget);
      expect(made.asked.last, {'op': 'entity', 'uid': 'moonwake-chronicle/p-coast-0'});

      // 창이 연표에 알리는 것: 흐림 · 세로 닻 · 가린 폭.
      final state = made.bus.slot('detail').value as DetailState;
      expect(state.open, isTrue);
      expect(state.pick, isTrue);
      expect(state.lane, isTrue);
      expect(state.inset, Ui.detailCover);
    });

    testWidgets('닫으면 고르기가 풀리고 가린 폭이 0이 된다', (tester) async {
      final made = makeBus();
      DetailHost.register('item', (ctx) => DetailShell(onClose: ctx.close, body: [DetailTitle(ctx.name)]));
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [DetailHost(bus: made.bus)]),
        ),
      );
      made.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      await tester.tap(find.text('✕'));
      await tester.pump();
      expect(find.text('✕').hitTestable(), findsNothing, reason: '물러나는 동안 닫힌 창은 입력을 받지 않는다');
      await tester.pumpAndSettle();
      expect(find.byType(DetailShell), findsNothing);
      expect(made.bus.selection.value, isNull);
      expect((made.bus.slot('detail').value as DetailState).open, isFalse);
    });

    testWidgets('뒤로 단추 — 창에서 거쳐 온 항목으로 차례로 돌아가고, 닫으면 기록을 비운다', (tester) async {
      final made = makeBus();
      DetailHost.register('item', (ctx) => DetailShell(onClose: ctx.close, body: [DetailTitle(ctx.name)]));
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [DetailHost(bus: made.bus)]),
        ),
      );
      final back = find.byTooltip('뒤로');
      made.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      expect(back, findsNothing, reason: '처음 연 창에는 돌아갈 곳이 없다');

      made.bus.select('moonwake-chronicle/myth-semi');
      await tester.pumpAndSettle();
      made.bus.select('moonwake-chronicle/p-coast-0', cell: 'leader:0');
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(made.bus.selection.value, const Selection('moonwake-chronicle/myth-semi'));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(made.bus.selection.value, const Selection('moonwake-chronicle/p-coast-0'));
      expect(back, findsNothing, reason: '뒤로 온 것은 다시 쌓지 않는다');

      // 닫고 다시 열면 처음부터.
      made.bus.select('moonwake-chronicle/myth-semi');
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);
      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();
      made.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      expect(back, findsNothing);
    });

    testWidgets('없는 항목을 고르면 창이 열리지 않는다', (tester) async {
      final made = makeBus();
      DetailHost.register('item', (ctx) => DetailShell(onClose: ctx.close, body: [DetailTitle(ctx.name)]));
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [DetailHost(bus: made.bus)]),
        ),
      );
      made.bus.select('없는-항목');
      await tester.pumpAndSettle();
      expect(find.byType(DetailShell), findsNothing);
    });

    testWidgets('등록되지 않은 갈래도 창은 서고 무엇이 없는지 적는다', (tester) async {
      final made = makeBus();
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [DetailHost(bus: made.bus)]),
        ),
      );
      made.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      expect(find.textContaining('아직 등록되지 않았습니다'), findsOneWidget);
    });

    testWidgets('칸을 고르면 칸 갈래가 열리고 조명을 건다', (tester) async {
      final made = makeBus();
      DetailHost.register('cell', (ctx) => DetailShell(onClose: ctx.close, body: [DetailTitle('칸 ${ctx.cell}')]));
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [DetailHost(bus: made.bus)]),
        ),
      );
      made.bus.select('moonwake-chronicle/p-coast-0', cell: 'leader:3');
      await tester.pumpAndSettle();
      expect(find.text('칸 leader:3'), findsOneWidget);
      expect((made.bus.slot('detail').value as DetailState).spot, isTrue);
    });
  });

  group('항목 기록 읽기', () {
    test(r'$ref 자리와 값 꺼내기', () {
      const json = {
        'name': '유리항 패총국',
        'tags': ['바다', '항구'],
        'successors': [
          {
            'to': {r'$ref': 'moonwake-chronicle/p-coast-1', 'name': '별목 등불연맹'},
          },
        ],
        'color': 0xa0bcc5,
      };
      expect(detailString(json, 'name'), '유리항 패총국');
      expect(detailStrings(json, 'tags'), ['바다', '항구']);
      final to = detailRef(detailList(json, 'successors').first['to'])!;
      expect(to.uid, 'moonwake-chronicle/p-coast-1');
      expect(to.name, '별목 등불연맹');
      expect(detailColor(json['color']), const Color(0xffa0bcc5));
      expect(detailColor('#a0bcc5'), const Color(0xffa0bcc5));
      expect(detailRef('글자'), isNull);
    });
  });
}
