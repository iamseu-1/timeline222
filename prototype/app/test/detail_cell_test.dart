import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/detail_cell.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_format3_test.dart' show tapSpan;

// 칸 창 · 시기 창 · 지위 창(명세 06의 2-3 ㈏ ㈐ ㈑)과 칸의 경계 [lo, hi)(9절 ㈐-4 · 5).
// 견본은 월흔해의 항목 기록에서 뽑은 test/fixtures/cells-basic.json(은륜 제국)과,
// 가장자리 경우를 보는 작은 가상 견본 cells-edge.json(물빛 성좌국)이다.

const basic = 'moonwake-chronicle/p-coast-6';
const edge = '가상견본/p-edge';

/// 견본에서 항목 기록 하나를 푼다.
Map<String, dynamic> entityOf(String file, String uid) {
  final raw = File('test/fixtures/$file').readAsStringSync();
  for (final row in jsonDecode(raw) as List) {
    final e = (row as Map).cast<String, dynamic>();
    if (e['uid'] == uid) return (jsonDecode(e['json'] as String) as Map).cast<String, dynamic>();
  }
  throw StateError('견본에 $uid 가 없습니다');
}

/// 검사용 AppBus — 항목 기록은 견본에서, 그 밖의 조회는 주어진 답으로(주지 않으면 '없는 명령'으로 거절한다).
({AppBus bus, List<Map<String, dynamic>> asked}) cellBus({
  List<String> fixtures = const ['cells-basic.json'],
  List<Map<String, dynamic>>? events,
  Map<String, dynamic>? echo,
}) {
  final store = <String, Map<String, dynamic>>{};
  for (final name in fixtures) {
    for (final row in jsonDecode(File('test/fixtures/$name').readAsStringSync()) as List) {
      final e = (row as Map).cast<String, dynamic>();
      store[e['uid'] as String] = e;
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
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('칸 창 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      switch (query['op']) {
        case 'entity':
          final row = store[query['uid']];
          if (row == null) throw StateError('없는 항목');
          return row;
        case 'events_in':
          if (events == null) throw StateError('없는 명령');
          return {'events': events};
        case 'echo':
          if (echo == null) throw StateError('없는 명령');
          return echo;
      }
      throw StateError('없는 명령');
    },
    controller: controller,
    scene: scene,
  );
  bus.slot('tracks').value = const {
    'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5},
    'mw-edge': {'name': '물빛', 'color': 0x9dbea8},
  };
  return (bus: bus, asked: asked);
}

/// 부품 하나를 띄우는 작은 틀(상세 창의 폭 380).
Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Ui.bg,
    body: SizedBox(width: Ui.detailWidth, height: 1000, child: child),
  ),
);

/// 칸 창을 혼자 세운다(뼈대 없이 — 공개 생성자 그대로).
Future<({AppBus bus, List<Map<String, dynamic>> asked})> open(
  WidgetTester tester,
  String cell, {
  String file = 'cells-basic.json',
  String uid = basic,
  List<Map<String, dynamic>>? events,
  Map<String, dynamic>? echo,
}) async {
  final made = cellBus(fixtures: [file], events: events, echo: echo);
  await tester.pumpWidget(host(CellDetail(bus: made.bus, entity: entityOf(file, uid), cell: cell)));
  await tester.pumpAndSettle();
  return made;
}

/// 창 안에서 그 글이 보이도록 스크롤한다(몸통은 맨 바깥 스크롤 하나뿐).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.first, 120, scrollable: find.byType(Scrollable).first);
}

void main() {
  group('칸의 경계 [lo, hi) — 명세 9절 ㈐-4 · 5', () {
    final x = entityOf('cells-basic.json', basic);

    test('내보내기가 확정해 둔 x_cellBounds가 먼저다 — 경계 해는 뒤 칸의 것', () {
      final a = cellBoundsOf(x, 'leader:0')!;
      final b = cellBoundsOf(x, 'leader:1')!;
      // 720년에 시작해 760년에 끝난 칸과 760년에 시작한 칸: 760년은 뒤 칸의 것이라 두 구간이 한 순간에서 맞닿는다.
      expect(a.lo, minutesOfT(720));
      expect(a.hi, minutesOfT(760));
      expect(b.lo, a.hi);
      // 내보내기(export/base.mjs의 minute)와 같은 투영이다.
      expect(a.lo, -657437760);
      expect(a.hi, -636399360);
    });

    test('x_cellBounds가 없으면 칸 하나만 보고 — 연도만 적은 끝은 그해 끝까지', () {
      final bare = Map<String, dynamic>.from(x)..remove('x_cellBounds');
      final a = cellBoundsOf(bare, 'leader:0')!;
      expect(a.lo, minutesOfT(720));
      expect(a.hi, minutesOfT(761 - 1e-9));
      // 이웃을 보지 않으면 경계 해(760년)를 앞 칸이 그대로 가진다 — 이것이 미리 풀어 두어야 하는 까닭이다.
      expect(a.hi, greaterThan(cellBoundsOf(x, 'leader:0')!.hi));
    });

    test('이어받는 칸이 없는 무리(배도)는 두 길의 값이 같다', () {
      final bare = Map<String, dynamic>.from(x)..remove('x_cellBounds');
      expect(cellBoundsOf(bare, 'capital:1'), cellBoundsOf(x, 'capital:1'));
    });

    test('연도만 적은 사건은 그해 한가운데 한 점 — 경계 해의 사건이 두 칸에 모두 들지 않는다', () {
      final a = cellBoundsOf(x, 'leader:0')!;
      final b = cellBoundsOf(x, 'leader:1')!;
      final at760 = minutesOfT(760);
      expect(spanHit(start: at760, lo: a.lo, hi: a.hi), isFalse);
      expect(spanHit(start: at760, lo: b.lo, hi: b.hi), isTrue);
      // 날짜까지 적은 사건도 그날 한가운데로 — 760년 3월 5일은 뒤 칸의 것.
      final day = minutesOfT(parseAt('760-03-05')!);
      expect(spanHit(start: day, startPrec: DatePrec.day, lo: a.lo, hi: a.hi), isFalse);
      expect(spanHit(start: day, startPrec: DatePrec.day, lo: b.lo, hi: b.hi), isTrue);
      // 기간이 있는 사건은 두 칸에 걸친다.
      final ranged = (start: minutesOfT(750), end: minutesOfT(770));
      expect(spanHit(start: ranged.start, end: ranged.end, lo: a.lo, hi: a.hi), isTrue);
      expect(spanHit(start: ranged.start, end: ranged.end, lo: b.lo, hi: b.hi), isTrue);
    });

    test('폭 0인 쪽은 한 점으로 본다(spanMeets)', () {
      expect(spanMeets(10, 10, 0, 20), isTrue);
      expect(spanMeets(20, 20, 0, 20), isFalse); // [lo, hi)의 끝은 들지 않는다
      expect(spanMeets(0, 20, 10, 10), isTrue); // 폭 0인 칸은 그 한 점이 들면
      expect(spanMeets(0, 10, 10, 10), isFalse); // 끝이 그 점에 닿기만 하면 들지 않는다
      expect(spanMeets(10, 10, 10, 10), isTrue);
      expect(spanMeets(0, 5, 10, 20), isFalse);
    });

    test('없는 칸 참조는 null', () {
      expect(cellBoundsOf(x, 'leader:99'), isNull);
      expect(cellBoundsOf(x, '없는칸'), isNull);
      expect(findCell(x, 'phase:4')!.index, 1); // 시기는 체계를 가로지른 번호(ci)로 찾는다
      expect(findCell(x, 'phase:4')!.list.length, 2);
    });
  });

  group('㈏ 칸 창 — 지도자', () {
    testWidgets('머리 배지 · 이름 아래 날짜만 · 묘호 · 시호 · 이름', (tester) async {
      await open(tester, 'leader:3');
      expect(find.text('유리해안'), findsOneWidget); // 트랙
      expect(find.text('은륜 제국'), findsOneWidget); // 정권
      expect(find.text('지도자 · 제4대'), findsOneWidget);
      expect(find.text('지위 서약공'), findsOneWidget);
      expect(find.text('가문 은결 물결가'), findsOneWidget);
      expect(find.text('은결 베루'), findsWidgets); // 제목
      expect(find.text('묘호 환야 · 시호 밤을 돌려준 왕 · 이름 은결 베루'), findsOneWidget);
      // 시작이 미정인 칸 — 날짜 줄은 '미정 ~ …'이고 어디에 놓았는지 한 줄.
      expect(find.text('미정 ~ 880년'), findsOneWidget);
      expect(find.text('시작 미정 — 연표에는 840년 무렵부터 놓았습니다'), findsOneWidget);
      // 왕조는 적지 않아 짐작한 것.
      expect(find.text('왕조 파도문 이음 왕조 흑염 (시작한 해로 짐작)'), findsOneWidget);
    });

    testWidgets('같은 이름의 인물을 누르면 그 인물로 간다', (tester) async {
      final made = await open(tester, 'leader:3');
      await tester.tap(find.text('같은 이름의 인물: 은결 베루 · 인장을 내려놓은 군주'));
      await tester.pump();
      expect(made.bus.selection.value!.uid, 'moonwake-chronicle/hero-0');
    });

    testWidgets('앞뒤 칸으로 넘긴다', (tester) async {
      final made = await open(tester, 'leader:3');
      expect(find.textContaining('◀ 은결 이오'), findsOneWidget);
      await tester.tap(find.textContaining('은결 사나 ▶'));
      await tester.pump();
      expect(made.bus.selection.value!.cell, 'leader:4');
    });

    testWidgets('🎯 이 시기로는 칸이 품는 구간으로 데려간다', (tester) async {
      final made = await open(tester, 'leader:3');
      await tester.tap(find.text('이 시기로'));
      await tester.pump();
      final go = made.bus.go.value!;
      final b = cellBoundsOf(entityOf('cells-basic.json', basic), 'leader:3')!;
      final pad = (b.hi - b.lo) * .35;
      expect(go.lo, closeTo(b.lo - pad, 1));
      expect(go.hi, closeTo(b.hi + pad, 1));
      expect(go.ring, basic);
    });

    testWidgets('창을 열면 그 칸의 기간에 조명을 켠다', (tester) async {
      final made = await open(tester, 'leader:3');
      final spots = made.bus.slot('spots').value as List;
      final b = cellBoundsOf(entityOf('cells-basic.json', basic), 'leader:3')!;
      expect(spots.first, {'uid': basic, 'cell': 'leader:3', 'start': b.lo, 'end': b.hi});
    });

    testWidgets('다른 견해 상자 — 첫 줄은 이 연표가 쓰는 연대', (tester) async {
      final made = await open(tester, 'leader:1');
      await reveal(tester, find.textContaining('다른 견해'));
      expect(find.text('이 연표가 쓰는 연대'), findsOneWidget);
      expect(find.text('즉위 의식 기준 · 가상 문헌 『흰계단 의례록』'), findsOneWidget);
      expect(find.text('인장 반환 기준'), findsOneWidget);
      // 날짜 없이 근거만 적은 견해는 누르지 않는 줄.
      expect(find.text('공동 재위설'), findsOneWidget);
      await tester.tap(find.text('756년 ~ 800년'));
      await tester.pump();
      expect(made.bus.go.value, isNotNull);
    });

    testWidgets('연대 폭과 확실성', (tester) async {
      await open(tester, 'leader:2');
      expect(find.text('추정 연대'), findsOneWidget);
      expect(find.text('시작 — 이르면 797년, 늦으면 804년'), findsOneWidget);
      expect(find.text('끝 — 이르면 838년, 늦으면 844년'), findsOneWidget);
    });

    testWidgets('이 시기의 인물 — 활동 기록이 그 구간과 겹치는 사람', (tester) async {
      final made = await open(tester, 'leader:3');
      await reveal(tester, find.textContaining('이 시기의 인물'));
      expect(find.text('은결 베루'), findsWidgets);
      await tester.tap(find.textContaining('은결 보세나'));
      await tester.pump();
      expect(made.bus.selection.value!.uid, 'moonwake-chronicle/f-coast-6-1');
    });

    testWidgets('이 시기의 사건 — 자료 처리부의 답을 그대로 줄로', (tester) async {
      final made = await open(
        tester,
        'leader:3',
        events: [
          {'uid': '가상/ev-1', 'title': '별목 봉쇄', 'when': '842년', 'color': 0xd4a39b},
          {'uid': '가상/ev-2', 'title': '아홉 인장 회담', 'when': '858년 ~ 876년', 'treaty': true, 'member': '잔물 자치령'},
        ],
      );
      await reveal(tester, find.textContaining('이 시기의 사건'));
      expect(find.text('이 시기의 사건 2', findRichText: true), findsOneWidget);
      expect(find.text('842년'), findsOneWidget);
      // 숨은 소속의 사건에는 꼬리표.
      expect(find.textContaining('소속 · 잔물 자치령'), findsOneWidget);
      await tester.tap(find.text('별목 봉쇄'));
      await tester.pump();
      expect(made.bus.selection.value!.uid, '가상/ev-1');
      // 물어본 구간은 칸이 품는 구간 그대로다.
      final b = cellBoundsOf(entityOf('cells-basic.json', basic), 'leader:3')!;
      final query = made.asked.firstWhere((q) => q['op'] == 'events_in');
      expect(query['lo'], b.lo);
      expect(query['hi'], b.hi);
      expect(query['band'], basic);
    });

    testWidgets('그 조회 명령이 없으면 사건 묶음만 빠진다', (tester) async {
      await open(tester, 'leader:3');
      expect(find.textContaining('이 시기의 사건'), findsNothing);
      expect(find.byType(DetailShell), findsOneWidget);
    });

    testWidgets('같은 시기 타국은 스위치를 켰을 때만 채워진다', (tester) async {
      final made = await open(
        tester,
        'leader:3',
        echo: {
          'count': 3,
          'groups': [
            {
              'uid': '가상/p-other',
              'name': '잎울 나이테국',
              'color': 0xb6c398,
              'track': '숲기슭',
              'count': 3,
              'events': [
                {'uid': '가상/ev-9', 'title': '나이테 개정', 'when': '850년'},
              ],
            },
          ],
        },
      );
      expect(find.textContaining('같은 시기 타국'), findsNothing);
      await reveal(tester, find.text('같은 시기를 타국에도'));
      await tester.tap(find.text('같은 시기를 타국에도'));
      await tester.pumpAndSettle();
      expect(made.bus.slot('echo').value, isTrue);
      await reveal(tester, find.textContaining('같은 시기 타국'));
      expect(find.text('잎울 나이테국'), findsOneWidget);
      expect(find.text('나이테 개정'), findsOneWidget);
    });
  });

  group('㈏ 칸 창 — 도읍 · 연호', () {
    testWidgets('도읍은 역할 딱지와 역할 · 도시 · 시기 이름', (tester) async {
      await open(tester, 'capital:0');
      expect(find.text('도읍'), findsOneWidget); // 정도는 딱지를 달지 않는다
      expect(find.text('유리항 첫뜰'), findsWidgets);
      expect(find.text('역할 정도 · 도시 유리항 · 시기 이름 첫 정착'), findsOneWidget);
      await open(tester, 'capital:3');
      expect(find.text('도읍 · 임시'), findsOneWidget);
    });

    testWidgets('연호의 시작 미정', (tester) async {
      await open(tester, 'era:1');
      expect(find.text('연호'), findsOneWidget);
      // 날짜 줄과 '다른 견해'의 첫 줄(이 연표가 쓰는 연대)에 같은 글이 선다.
      expect(find.text('미정 ~ 880년'), findsWidgets);
      expect(find.text('시작 미정 — 연표에는 800년 무렵부터 놓았습니다'), findsOneWidget);
      expect(find.text('메모가 없습니다.'), findsOneWidget);
    });

    testWidgets('끝을 비운 칸은 진행 중인 정권의 끝까지 — 현재', (tester) async {
      await open(tester, 'leader:1', file: 'cells-edge.json', uid: edge);
      expect(find.text('노을 미리'), findsWidgets);
      expect(find.text('1440년 ~ 현재'), findsOneWidget);
    });
  });

  group('㈐ 시기 창', () {
    testWidgets('체계 배지 · 체계 한마디 · 기간 · 앞뒤 시기', (tester) async {
      final made = await open(tester, 'phase:1');
      expect(find.text('시기 구분(학계) · 장부 학파'), findsOneWidget);
      expect(find.text('조정기'), findsWidgets);
      expect(find.text('체계 장부 학파 — 과세 장부와 공용 창고 기록으로 구분한다.'), findsOneWidget);
      expect(find.text('800년 ~ 880년'), findsWidgets);
      expect(find.text('시작 — 이르면 797년, 늦으면 808년'), findsOneWidget);
      expect(find.textContaining('◀ 복구기'), findsOneWidget);
      await tester.tap(find.textContaining('전환기 ▶'));
      await tester.pump();
      expect(made.bus.selection.value!.cell, 'phase:2');
    });

    testWidgets('체계 견주기 — 체계마다 한 줄, 막대를 누르면 그 시기', (tester) async {
      final made = await open(tester, 'phase:1');
      await reveal(tester, find.textContaining('체계 견주기'));
      expect(find.text('체계 견주기 3', findRichText: true), findsOneWidget);
      expect(find.text('장부 학파'), findsWidgets);
      expect(find.text('생활사 학파'), findsOneWidget);
      expect(find.text('꿈실 학파'), findsOneWidget);
      // 축의 두 끝(정권과 모든 시기를 품는 범위).
      expect(find.text('720년'), findsWidgets);
      expect(find.text('960년'), findsWidgets);
      await tester.tap(find.text('살아남는 시기'));
      await tester.pump();
      expect(made.bus.selection.value!.cell, 'phase:3');
    });

    testWidgets('체계가 하나면 시기 한눈에 · 비운 경계가 어디서 왔는지', (tester) async {
      await open(tester, 'phase:0', file: 'cells-edge.json', uid: edge);
      expect(find.text('첫 무렵'), findsWidgets);
      expect(find.text('시작은 정권 시작'), findsOneWidget);
      await reveal(tester, find.textContaining('시기 한눈에'));
      expect(find.textContaining('시기 한눈에'), findsOneWidget);
      await open(tester, 'phase:1', file: 'cells-edge.json', uid: edge);
      expect(find.text('끝은 정권 끝'), findsOneWidget);
    });
  });

  group('㈑ 지위 창', () {
    testWidgets('서열 · 짙기 · 기간', (tester) async {
      await open(tester, 'rank:2');
      expect(find.text('지위 · 서열 8'), findsOneWidget);
      expect(find.text('월인황'), findsWidgets);
      expect(find.textContaining('서열 8 · 짙기 4단계(넷 중)'), findsOneWidget);
      expect(find.textContaining('열두 땅의 계량법'), findsOneWidget);
      expect(find.text('824년 ~ 미정'), findsWidgets);
    });

    testWidgets('지위 변천 — 승격 ▲ · 격하 ▼', (tester) async {
      final made = await open(tester, 'rank:3');
      await reveal(tester, find.textContaining('지위 변천'));
      expect(find.text('지위 변천 4', findRichText: true), findsWidgets);
      expect(find.text('▲ 승격'), findsWidgets);
      expect(find.text('▼ 격하'), findsOneWidget); // 월인황(서열 8) → 환관왕(서열 7)
      await tester.tap(find.text('서약공'));
      await tester.pump();
      expect(made.bus.selection.value!.cell, 'rank:0');
    });

    testWidgets('이 지위의 지도자', (tester) async {
      final made = await open(tester, 'rank:3');
      await reveal(tester, find.textContaining('이 지위의 지도자'));
      expect(find.text('이 지위의 지도자 2', findRichText: true), findsOneWidget); // 916~960에 걸친 지도자 둘
      await tester.tap(find.text('은결 테온'));
      await tester.pump();
      expect(made.bus.selection.value!.cell, 'leader:5');
    });

    testWidgets('사전에 없는 지위는 서열 없이', (tester) async {
      await open(tester, 'rank:0', file: 'cells-edge.json', uid: edge);
      expect(find.text('지위'), findsOneWidget); // 서열이 없어 배지에 숫자가 없다
      expect(find.text('사전에 없는 지위 — 서열 없이 중립 색으로 그립니다'), findsOneWidget);
      expect(find.text('시작은 정권 시작'), findsOneWidget);
    });
  });

  group('갈래 등록과 가장자리', () {
    setUp(() {
      for (final k in detailKinds) {
        DetailHost.unregister(k.id);
      }
    });

    testWidgets('뼈대에 등록하면 칸 · 시기 · 지위 창이 열린다', (tester) async {
      final made = cellBus();
      registerCellDetail();
      await tester.pumpWidget(host(DetailHost(bus: made.bus, framed: false)));
      for (final pair in const [('leader:0', '은결 나엔'), ('phase:5', '거두어 간 꿈'), ('rank:1', '환관왕')]) {
        made.bus.select(basic, cell: pair.$1);
        await tester.pumpAndSettle();
        expect(find.text(pair.$2), findsWidgets, reason: '${pair.$1} 창이 서지 않았다');
      }
      expect((made.bus.slot('detail').value as DetailState).spot, isTrue);
    });

    testWidgets('없는 칸 참조여도 창은 서고 닫을 수 있다', (tester) async {
      final made = await open(tester, 'leader:99');
      expect(find.textContaining('칸이 없습니다'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pump();
      expect(made.bus.selection.value, isNull);
    });

    testWidgets('문서가 있는 칸에만 📄를 둔다', (tester) async {
      final made = cellBus();
      const key = 'cell:$basic:leaders:은결 나엔@720';
      made.bus.slot('docKeys').value = const {key};
      await tester.pumpWidget(host(CellDetail(bus: made.bus, entity: entityOf('cells-basic.json', basic), cell: 'leader:0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('문서'));
      await tester.pump();
      expect(made.bus.slot('doc').value, key);
      // 지위 칸에는 제 문서가 없다 — 그 정권의 문서로 간다.
      made.bus.slot('docKeys').value = const {basic};
      await tester.pumpWidget(host(CellDetail(bus: made.bus, entity: entityOf('cells-basic.json', basic), cell: 'rank:0')));
      await tester.pumpAndSettle();
      expect(find.text('은륜 제국 문서'), findsOneWidget);
    });

    testWidgets('문서 목록이 없으면 📄 단추를 두지 않는다', (tester) async {
      await open(tester, 'leader:0');
      expect(find.textContaining('📄'), findsNothing);
      expect(find.text('이 시기로'), findsOneWidget);
      expect(find.text('닫기'), findsOneWidget);
    });
  });

  // 형식 3(설계 A-아카이브-이음 A1-d) — 미리 푼 x_cellNames · x_lineage · x_persons · x_cellPlaces로 선 새 줄.
  // 견본 cells-f3edge.json(솔나라 — 가상)은 손으로 쓴 부록 가-6의 꼴이고, 글은 웹 cellPersonHTML · placeHTML의 글이다.
  // 건의 8의 6-가 · 6-나(2026-10-13 감독 선택 '후'): 같은 사람이 두 나라의 임금 — 견본 cells-twins.json(가람 나라 · 포구 나라 · 가상).
  group('㈏ 칸 창 — 한 사람의 창(건의 8의 6-가 · 6-나)', () {
    const garam = '가상견본/p-garam', pogu = '가상견본/p-pogu';
    Future<({AppBus bus, List<Map<String, dynamic>> asked})> openTwin(WidgetTester tester, String uid, String cell) =>
        open(tester, cell, file: 'cells-twins.json', uid: uid);
    Finder box(String title, [String? small]) => find.byWidgetPredicate((w) => w is DetailBox && w.title == title && (small == null || w.small == small));
    // 자리 줄의 왼쪽 3px 먹 줄(이 창을 연 자리).
    Finder marked(String polity) => find.ancestor(
      of: find.text(polity),
      matching: find.byWidgetPredicate((w) {
        if (w is! DecoratedBox || w.decoration is! BoxDecoration) return false;
        final border = (w.decoration as BoxDecoration).border;
        return border is Border && border.left.width == 3 && border.left.color == Ui.ink;
      }),
    );

    testWidgets('인물 배지 · 합친 기간 · 자리 둘(시작 순 · 자리 이음) · 겹친 기간 · 가족 — 연표에 같은 사람의 칸을 싣는다', (tester) async {
      final made = await openTwin(tester, garam, 'leader:3');
      expect(find.text('인물'), findsOneWidget);
      expect(find.text('지도자 · 제4대'), findsNothing, reason: '나라 · 대수는 자리 줄로 간다');
      expect(find.text('1455년 ~ 1480년'), findsOneWidget, reason: '두 자리를 합친 기간');
      expect(box('자리', '2'), findsOneWidget);
      for (final t in ['가람 나라', '지도자 · 4대', '1455 ~ 1480', '포구 나라', '지도자 · 2대', '1470 ~ 1480']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(tester.getTopLeft(find.text('가람 나라')).dy, lessThan(tester.getTopLeft(find.text('포구 나라')).dy), reason: '시작 순');
      expect(find.text('앞 셋째 임금의 동생 · 찬탈'), findsOneWidget);
      expect(find.text('앞 포구 첫 임금 · 정복'), findsOneWidget);
      expect(find.text('겹친 기간  1470 ~ 1480  · 10년'), findsOneWidget);
      expect(box('가족'), findsOneWidget);
      expect(find.descendant(of: box('가족'), matching: find.text('부모 · 조상: 부 둘째 임금')), findsOneWidget);
      expect(marked('가람 나라'), findsOneWidget, reason: '이 창을 연 자리');
      expect(marked('포구 나라'), findsNothing);
      // 연표의 같은 사람 테(6-나) — 이 칸이 맨 앞.
      expect(made.bus.slot('twins').value, [
        {'uid': garam, 'cell': 'leader:3'},
        {'uid': pogu, 'cell': 'leader:1'},
      ]);
      // 다른 자리를 누르면 그 나라의 그 칸 · 이 창의 자리는 누르지 않는다.
      await tester.tap(find.text('가람 나라'));
      expect(made.bus.selection.value, isNull);
      await tester.tap(find.text('포구 나라'));
      expect(made.bus.selection.value!.uid, pogu);
      expect(made.bus.selection.value!.cell, 'leader:1');
      // 창이 닫히면 제가 실은 테를 거둔다.
      await tester.pumpWidget(const SizedBox());
      expect(made.bus.slot('twins').value, isNull);
    });

    testWidgets('다른 나라의 칸에서 열어도 같은 꼴 — 표시는 누른 자리로', (tester) async {
      final made = await openTwin(tester, pogu, 'leader:1');
      expect(find.text('1455년 ~ 1480년'), findsOneWidget);
      expect(box('자리', '2'), findsOneWidget);
      expect(marked('포구 나라'), findsOneWidget);
      expect(marked('가람 나라'), findsNothing);
      expect(made.bus.slot('twins').value, [
        {'uid': pogu, 'cell': 'leader:1'},
        {'uid': garam, 'cell': 'leader:3'},
      ]);
    });

    testWidgets('같은 사람이 없는 칸은 지금 그대로 — 나라 배지 · 자리 묶음 없음 · 연표에 싣지 않음', (tester) async {
      final made = await openTwin(tester, garam, 'leader:2');
      expect(find.text('인물'), findsNothing);
      expect(find.text('지도자 · 제3대'), findsOneWidget);
      expect(box('자리'), findsNothing);
      expect(made.bus.slot('twins').value, isNull);
    });
  });

  group('㈏ 칸 창 — 형식 3의 새 줄', () {
    const f3 = '가상견본/p-f3';
    Future<({AppBus bus, List<Map<String, dynamic>> asked})> openF3(WidgetTester tester, String cell) => open(tester, cell, file: 'cells-f3edge.json', uid: f3);
    List<String> lines(WidgetTester tester) => [for (final l in tester.widgetList<DetailLine>(find.byType(DetailLine))) detailPlain(l.text)];
    // 한 사람의 창(건의 8의 6-가)의 '자리' 묶음 안 줄(자리마다의 자리 이음)과 그 밖의 줄.
    final seatBox = find.byWidgetPredicate((w) => w is DetailBox && w.title == '자리');
    List<String> seatLines(WidgetTester tester) => [
      for (final l in tester.widgetList<DetailLine>(find.descendant(of: seatBox, matching: find.byType(DetailLine)))) detailPlain(l.text),
    ];
    List<String> outside(WidgetTester tester) => [...lines(tester)]..removeWhere(seatLines(tester).contains);

    testWidgets('원어 줄은 칸 사실 줄 다음 · 날짜 줄 앞, 사람 글은 같은 이름의 인물 다음 · 메모 앞', (tester) async {
      await openF3(tester, 'leader:1');
      expect(lines(tester), [
        'Sol Baram (로마자 · 한국어 로마자)',
        '그 밖의 이름: 率風 (한자)',
        '앞 지도자 솔 바위의 동생 · 찬탈',
        '부모 · 조상: 부 솔 바위 · 모 나루 달 추정',
        '배우자: 갈마국 갈마 이슬 640년 ~ 670년',
        '자식 · 후손: 솔 새벽',
        '속한 단체: 동녘파',
      ]);
      double y(Finder f) => tester.getTopLeft(f.first).dy;
      expect(y(find.byType(DetailLine)), lessThan(y(find.byType(DetailWhen))));
      expect(y(find.textContaining('같은 이름의 인물')), lessThan(y(find.byWidgetPredicate((w) => w is DetailLine && w.text.startsWith('앞 지도자')))));
      // 관계는 굵게(웹 <b>).
      final rich = tester.widgetList<RichText>(find.byType(RichText)).firstWhere((r) => r.text.toPlainText().startsWith('앞 지도자'));
      TextSpan? kin;
      rich.text.visitChildren((s) {
        if (s is TextSpan && s.text == '동생') kin = s;
        return kin == null;
      });
      expect(kin!.style!.fontWeight, FontWeight.w700);
      // 칸에 적은 사람이 '같은 이름의 인물'과 같으면 `사람:` 줄은 없다.
      expect(lines(tester).where((l) => l.startsWith('사람:')), isEmpty);
    });

    testWidgets('자리 이음 네 꼴 — 관계 앎 · 관계 미상 · 앞 지도자 미상 · 다시 오름', (tester) async {
      final want = {
        'leader:1': '앞 지도자 솔 바위의 동생 · 찬탈',
        'leader:2': '앞 지도자 솔 바람 · 관계 미상',
        'leader:3': '앞 지도자 미상 · 선거',
        'leader:4': '앞 지도자 솔 들 · 다시 오름 쫓겨났다 돌아옴',
      };
      for (final e in want.entries) {
        await openF3(tester, e.key);
        expect(lines(tester).where((l) => l.startsWith('앞 지도자')), [e.value], reason: e.key);
      }
      // 칸에 accession을 적지 않았으면 미리 푼 값이 있어도 줄이 없다(웹과 같다). 솔 바위는 다시 올라(leader:4) 자리가 둘 이상이라
      // 창은 한 사람의 창 — 자리 이음은 자리 줄마다 서고, 이 칸(첫 자리)의 줄은 없다.
      await openF3(tester, 'leader:0');
      expect(outside(tester).where((l) => l.startsWith('앞 지도자')), isEmpty);
      expect(seatLines(tester), ['앞 솔 들 · 다시 오름'], reason: '자리 줄은 앞 지도자 · 메모 없이(목업)');
    });

    testWidgets('사람 · 같은 사람의 다른 칸 — 누르면 그 인물 · 그 칸', (tester) async {
      final made = await openF3(tester, 'leader:3');
      expect(lines(tester), ['앞 지도자 미상 · 선거', '사람: 솔 들 · 뽑힌 이']);
      tapSpan(tester, '솔 들 · 뽑힌 이');
      expect(made.bus.selection.value!.uid, '가상견본/f-deul');
      expect(made.bus.selection.value!.kind, 'figure');

      // 같은 사람의 다른 칸이 있으면 한 사람의 창(건의 8의 6-가): '자리' 묶음에 자리마다 한 줄 — 누르면 그 칸. 혈연은 '가족' 묶음으로.
      // 갈마국 기록은 이 견본에 없어 그 자리는 칸 기록의 글(나라 이름 · 기간 글)만으로 선다.
      final other = await openF3(tester, 'leader:0');
      expect(outside(tester), ['자식 · 후손: 솔 바람 · 솔 새벽']);
      expect(find.byWidgetPredicate((w) => w is DetailBox && w.title == '가족'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is DetailBox && w.title == '자리' && w.small == '3'), findsOneWidget);
      expect(find.text('600 ~ 640'), findsOneWidget);
      await tester.tap(find.text('720 ~ 730'));
      expect(other.bus.selection.value!.uid, f3);
      expect(other.bus.selection.value!.cell, 'leader:4');
      await tester.tap(find.text('735년 ~ 740년'));
      expect(other.bus.selection.value!.uid, '가상견본/p-gal');
      expect(other.bus.selection.value!.cell, 'leader:2');
    });

    testWidgets('혈연의 같은 나라 칸은 이름만 — 누르면 그 칸', (tester) async {
      final made = await openF3(tester, 'leader:1');
      tapSpan(tester, '솔 바위');
      expect(made.bus.selection.value!.uid, f3);
      expect(made.bus.selection.value!.cell, 'leader:0');
      tapSpan(tester, '갈마국 갈마 이슬');
      expect(made.bus.selection.value!.uid, '가상견본/p-gal');
      tapSpan(tester, '동녘파');
      expect(made.bus.selection.value!.kind, 'group');
    });

    testWidgets('도읍의 지명 줄 — 원어 · 위 구역, 지명 사전에 원어도 위 구역도 없는 도읍은 줄이 없다', (tester) async {
      await openF3(tester, 'capital:0');
      expect(lines(tester), ['지명 푸른 벼랑 청해에 속함 — Pureun Byeorang (로마자 · 한국어 로마자)', '그 밖의 이름: 靑崖 (한자)']);
      await openF3(tester, 'capital:1');
      expect(find.byType(DetailLine), findsNothing);
    });

    testWidgets('형식 3 열쇠가 없는 옛 기록은 지금 그림 그대로', (tester) async {
      await open(tester, 'leader:3');
      expect(find.byType(DetailLine), findsNothing);
      await open(tester, 'capital:0', file: 'cells-edge.json', uid: edge);
      expect(find.byType(DetailLine), findsNothing);
    });
  });
}
