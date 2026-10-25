import 'dart:convert';

import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_people.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/doc_window.dart' show DocChip;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_format3_test.dart' show tapSpan;
import 'detail_shell_test.dart' show host, makeBus;

// 인물 창(㈒)과 가문 창(㈓) — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-3절.
//
// 견본은 월흔해 항목 기록에서 그대로 꺼낸 것이다(`test/fixtures/people-figures.json` ·
// `people-houses.json` — `prototype/results/compat/moonwake-layout3.json`의 entities에서 뽑았다).
// `people-edge.json`만은 견본에 없는 가장자리(짐작한 활동 시기 · 못 찾은 정권 · 가문 목록에 없는 가문)를
// 보려고 같은 세계의 가상 이름으로 지어 넣은 두 줄이다.

/// 창을 띄우고 뜰 때까지 기다린다.
Future<({dynamic bus, List<Map<String, dynamic>> asked})> open(
  WidgetTester tester,
  String uid, {
  List<String> fixtures = const ['people-figures.json', 'people-houses.json', 'people-edge.json'],
  Map<String, dynamic>? tracks,
}) async {
  final made = makeBus(fixtures: fixtures);
  registerPeopleDetail();
  made.bus.slot('tracks').value = tracks ?? const {
    'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5},
    'mw-obsidian': {'name': '검은유리', 'color': 0xbbacc8},
    'mw-root': {'name': '뿌리숲', 'color': 0xb6c398},
  };
  await tester.pumpWidget(host(SizedBox(height: 1000, child: DetailHost(bus: made.bus, framed: false))));
  made.bus.select(uid);
  await tester.pumpAndSettle();
  return made;
}

/// 창 안에서 그 글이 보이도록 스크롤한다(몸통은 맨 바깥 스크롤 하나뿐).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.first, 120, scrollable: find.byType(Scrollable).first);
}

void main() {
  setUp(() {
    for (final k in detailKinds) {
      DetailHost.unregister(k.id);
    }
  });

  group('인물 창 (㈒)', () {
    testWidgets('머리 배지 — 트랙 · 정권 · 인물·역할 · 가문', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-0');
      expect(find.text('유리해안'), findsOneWidget);
      expect(find.text('은륜 제국'), findsWidgets);
      expect(find.text('인물 · 인장을 내려놓은 군주'), findsOneWidget);
      expect(find.text('가문 은결 먼길가'), findsOneWidget);
    });

    testWidgets('이름 · 다른 이름 · 생몰(향년) · 활동', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-0');
      expect(find.text('은결 베루'), findsWidgets);
      expect(find.text('다른 이름: 나엔 · 닫힌 고리'), findsOneWidget);
      // 향년은 세는나이 — 906 − 790 + 1.
      expect(find.text('790년 ~ 906년 (향년 117세)'), findsOneWidget);
      expect(find.text('활동 808년 ~ 896년'), findsOneWidget);
    });

    testWidgets('묶음이 명세의 차례대로 선다', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-0');
      // 몸통에 쌓인 차례 그대로 — 스크롤과 상관없이 나무의 차례로 잰다.
      final titles = tester.widgetList<DetailBox>(find.byType(DetailBox)).map((b) => b.title).toList();
      expect(titles, ['다른 견해', '활동 기록', '관련 사건', '서명한 조약', '같은 시기의 지도자']);
    });

    testWidgets('활동 기록을 누르면 그 정권이 열린다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await reveal(tester, find.text('아홉 인장 공동 조사관'));
      await tester.tap(find.text('아홉 인장 공동 조사관'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-6');
    });

    testWidgets('같은 이름의 지도자를 누르면 그 칸 창이 열린다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await tester.tap(find.text('은륜 제국 은결 베루'));
      await tester.pump();
      expect(made.bus.selection.value.cell, 'leader:3');
    });

    testWidgets('같은 시기의 지도자를 누르면 그 지도자 칸으로', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await reveal(tester, find.textContaining('같은 시기의 지도자'));
      // 섬긴 정권이 둘 이상이면 이름 뒤에 그 나라를 밝힌다.
      await tester.tap(find.text('은결 이오 · 은륜 제국'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-6');
      expect(made.bus.selection.value.cell, 'leader:2');
    });

    testWidgets('관련 사건을 누르면 그 상세로', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await reveal(tester, find.text('흑염 전쟁'));
      await tester.tap(find.text('흑염 전쟁'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-6-black-salt-war');
    });

    testWidgets('서명한 조약은 편과 서명 직함을 꼬리표로 달고 조약 창으로 간다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await reveal(tester, find.textContaining('아홉 인장 평화'));
      expect(find.text('아홉 인장 평화 은륜 제국 · 인장을 내려놓은 군주'), findsOneWidget);
      await tester.tap(find.textContaining('아홉 인장 평화'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-6-treaty-0');
    });

    testWidgets('다른 견해는 생몰과 활동을 따로 적는다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await reveal(tester, find.text('이 연표가 쓰는 연대'));
      expect(find.text('생몰 790년 ~ 906년 · 활동 808년 ~ 896년'), findsOneWidget);
      // 생몰만 적은 이설 — 비운 쪽은 통설 값으로 채운다.
      expect(find.text('생몰 788년 ~ 906년'), findsOneWidget);
      // 사망과 활동 끝을 함께 적은 이설.
      expect(find.text('생몰 790년 ~ 908년 · 활동 808년 ~ 901년'), findsOneWidget);
      // 날짜 없이 근거만 적은 견해는 누르지 않는 줄(연대 자리에 —).
      expect(find.text('베루를 두 사람으로 보는 설'), findsOneWidget);
      await tester.tap(find.text('생몰 788년 ~ 906년'));
      await tester.pump();
      expect(made.bus.go.value, isNotNull);
    });

    testWidgets('🎯 이 위치로는 생몰까지 품은 범위로 데려간다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await tester.tap(find.text('이 위치로'));
      await tester.pump();
      final go = made.bus.go.value;
      expect(go, isNotNull);
      expect(go.ring, 'moonwake-chronicle/hero-0');
      // spanMin 790 · spanMax 906 — 해 좌표가 아니라 계약의 분(1970-01-01 기준)이어야 한다.
      expect(go.lo, minutesOfT(790));
      expect(go.hi, minutesOfT(906));
    });

    testWidgets('섬긴 띠마다 기간 조명을 켜고 닫으면 끈다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      final spots = made.bus.slot('spots').value as List;
      expect(spots.length, 2);
      expect(spots.first['uid'], 'moonwake-chronicle/p-coast-6');
      expect(spots.first['start'], isA<num>());
      made.bus.clearSelection();
      await tester.pumpAndSettle();
      expect(made.bus.slot('spots').value, isNull);
    });

    testWidgets('메아리 스위치는 그려지는 활동이 있을 때만 서고 slot에 실린다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/hero-0');
      await reveal(tester, find.text('같은 시기를 타국에도'));
      await tester.tap(find.text('같은 시기를 타국에도'));
      await tester.pump();
      expect(made.bus.slot('echo').value, true);
    });

    testWidgets('활동 시기가 미정이면 어디에 놓았는지 적고, 그 줄의 이설·연대 폭은 작은 상자로', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-8');
      expect(find.text('시작 미정 — 연표에는 800년 무렵부터 놓았습니다'), findsOneWidget);
      await reveal(tester, find.textContaining('활동 기록'));
      expect(find.textContaining('미정 ~ 858년'), findsWidgets);
      // 목록 줄의 작은 딱지.
      expect(find.textContaining('이설 1'), findsOneWidget);
      // 딸린 작은 상자 — 확실성과 연대 폭.
      await reveal(tester, find.textContaining('기억망 분리자 활동 기록'));
      expect(find.text('연대의 확실성 — 추정'), findsOneWidget);
      expect(find.text('시작 — 이르면 796년, 늦으면 808년'), findsOneWidget);
      expect(find.text('첫 분리 실험 포함'), findsOneWidget);
    });

    testWidgets('끝이 미정인 활동', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-11');
      expect(find.text('끝 미정 — 연표에는 896년 무렵까지 놓았습니다'), findsOneWidget);
      await reveal(tester, find.textContaining('활동 기록'));
      expect(find.text('858년 ~ 미정'), findsOneWidget);
    });

    testWidgets('짐작한 활동 · 못 찾은 정권 · 다른 트랙 · 태그', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-edge');
      // 생몰이 한쪽뿐이면 그 쪽만 적는다.
      expect(find.text('~ 902년'), findsOneWidget);
      expect(find.text('활동 830년 ~ 890년 (생몰에서 짐작)'), findsOneWidget);
      await reveal(tester, find.textContaining('활동 기록'));
      expect(find.textContaining('연표에서 찾지 못한 정권'), findsOneWidget);
      expect(find.textContaining('검은유리'), findsWidgets);
      // 그려지는 활동이 없으면 메아리 스위치도 없다.
      expect(find.text('같은 시기를 타국에도'), findsNothing);
      await reveal(tester, find.text('#기억염'));
      expect(find.text('#귀환선'), findsOneWidget);
    });

    testWidgets('비어 있는 묶음은 아예 없다', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-edge');
      expect(find.textContaining('관련 사건'), findsNothing);
      expect(find.textContaining('서명한 조약'), findsNothing);
      expect(find.textContaining('같은 시기의 지도자'), findsNothing);
      expect(find.textContaining('다른 견해'), findsNothing);
      expect(find.textContaining('같은 이름의 지도자'), findsNothing);
    });
  });

  group('가문 창 (㈓)', () {
    testWidgets('배지와 머리 — 가문 · 성 · 본관 · 시조', (tester) async {
      await open(tester, 'house:h-coast-0');
      expect(find.text('가문'), findsOneWidget);
      expect(find.text('성 은결'), findsOneWidget);
      expect(find.text('본관 유리항'), findsOneWidget);
      expect(find.text('은결 본가'), findsWidgets);
      expect(find.text('시조 은결 아디아'), findsOneWidget);
    });

    testWidgets('본가 · 분가 · 국성으로 삼은 나라', (tester) async {
      final made = await open(tester, 'house:h-coast-0');
      await reveal(tester, find.textContaining('본가 · 분가'));
      expect(find.text('갈라져 나간 분가 2개'), findsOneWidget);
      expect(find.text('은결 물결가'), findsWidgets);
      await reveal(tester, find.textContaining('국성 나라'));
      expect(find.text('국성 나라 9', findRichText: true), findsOneWidget);
      await tester.tap(find.text('유리항 패총국').first);
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-0');
    });

    testWidgets('본가에서 이 가문까지의 길 — 마지막은 누르지 않는다', (tester) async {
      final made = await open(tester, 'house:h-coast-2');
      await reveal(tester, find.text('본가에서 이 가문까지'));
      expect(find.text('은결 본가'), findsOneWidget);
      await tester.tap(find.text('은결 본가'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'house:h-coast-0');
    });

    testWidgets('구성원은 나라별로 묶이고 역할 딱지가 붙는다', (tester) async {
      await open(tester, 'house:h-coast-0');
      await reveal(tester, find.textContaining('구성원'));
      expect(find.text('왕조'), findsWidgets);
      expect(find.text('지도자'), findsWidgets);
      expect(find.text('내각'), findsWidgets);
      await reveal(tester, find.text('은결 나나나'));
      expect(find.text('은결 나나나'), findsOneWidget);
    });

    testWidgets('지도자 · 내각 구성원은 누르면 그 시기로, 왕조 · 인물은 상세로', (tester) async {
      final made = await open(tester, 'house:h-coast-0');
      await reveal(tester, find.text('은결 나나나'));
      await tester.tap(find.text('은결 나나나'));
      await tester.pump();
      expect(made.bus.go.value, isNotNull);
      expect(made.bus.selection.value.uid, 'house:h-coast-0'); // 칸 창으로 옮겨 가지 않는다

      await reveal(tester, find.text('유리항 첫불 왕조 깊은'));
      await tester.tap(find.text('유리항 첫불 왕조 깊은'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/d-coast-0-0');
    });

    testWidgets('가문 창은 연표를 흐리게 하지 않고 그 가문만 진하게 한다', (tester) async {
      final made = await open(tester, 'house:h-coast-0');
      final state = made.bus.slot('detail').value as DetailState;
      expect(state.pick, isFalse); // 명세 9절 ㈐-6
      expect(state.lane, isFalse);
      expect(made.bus.slot('house').value, 'h-coast-0');
      made.bus.clearSelection();
      await tester.pumpAndSettle();
      expect(made.bus.slot('house').value, isNull);
    });

    testWidgets('가문 목록에 없는 가문 — 안내 한 줄 · 빈 구성원 · 제공', (tester) async {
      await open(tester, 'house:h-edge');
      expect(find.text('가문 목록에 없는 이름이라, 적힌 이름 그대로 가문으로 묶었습니다'), findsOneWidget);
      expect(find.text('이 가문을 가리키는 지도자 · 내각 · 왕조 · 인물이 없습니다.'), findsOneWidget);
      expect(find.textContaining('본가 · 분가'), findsNothing);
      expect(find.textContaining('국성 나라'), findsNothing);
      expect(find.text('가문 목록에 없음'), findsOneWidget);
    });
  });

  group('혼자 서기', () {
    testWidgets('AppBus와 항목 기록만으로도 창이 선다', (tester) async {
      final made = makeBus(fixtures: const ['people-figures.json']);
      final entity = await made.bus.ask({'op': 'entity', 'uid': 'moonwake-chronicle/hero-0'});
      final json = (entity['json'] as String);
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 1000,
            child: FigureDetail.of(bus: made.bus, entity: _decode(json)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('은결 베루'), findsWidgets);
      expect(find.byType(DetailShell), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────────────────────
  //  하위 문서 칩 — 지금 연표는 인물 창의 '같은 시기의 지도자' 다음(js/viewer.js:1329)과
  //  가문 창의 '구성원' 다음(js/viewer.js:1594)에 둔다.
  // ────────────────────────────────────────────────────────────────────────────────────────────

  group('하위 문서 칩', () {
    /// 하위 문서 둘을 단 가문 견본 하나.
    const houseDocs = {
      'uid': 'house:h-docs',
      'id': 'h-docs',
      'name': '은결 물결가',
      'surname': '은결',
      'color': 0xa0bcc5,
      'packName': '월흔해 연대기',
      'x_members': [
        {'uid': 'moonwake-chronicle/hero-0', 'name': '은결 베루', 'role': 'figure', 'when': '812년 ~ 870년'},
      ],
      'x_docs': [
        {'key': 'house:h-docs//내력', 'sub': '내력'},
        {'key': 'house:h-docs//혼맥', 'sub': '혼맥'},
      ],
    };

    testWidgets('가문 창에 칩이 서고, 되묻지 않는다', (tester) async {
      final made = makeBus(fixtures: const ['people-houses.json']);
      await tester.pumpWidget(host(SizedBox(height: 1000, child: HouseDetail.of(bus: made.bus, entity: houseDocs))));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('하위 문서', findRichText: true));
      expect(find.text('하위 문서 2', findRichText: true), findsOneWidget);
      expect(find.text('내력'), findsOneWidget);
      expect(find.text('혼맥'), findsOneWidget);
      expect(made.asked, isEmpty);
    });

    testWidgets('가문 창의 칩은 구성원 다음 · 제공 앞(지금 연표의 차례)', (tester) async {
      final made = makeBus(fixtures: const ['people-houses.json']);
      await tester.pumpWidget(host(SizedBox(height: 1000, child: HouseDetail.of(bus: made.bus, entity: houseDocs))));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('제공'));
      expect(tester.getTopLeft(find.textContaining('구성원', findRichText: true)).dy, lessThan(tester.getTopLeft(find.text('내력')).dy));
      expect(tester.getTopLeft(find.text('내력')).dy, lessThan(tester.getTopLeft(find.text('제공')).dy));
    });

    testWidgets('가문 창의 칩을 누르면 문서 열쇠가 실린다', (tester) async {
      final made = makeBus(fixtures: const ['people-houses.json']);
      await tester.pumpWidget(host(SizedBox(height: 1000, child: HouseDetail.of(bus: made.bus, entity: houseDocs))));
      await tester.pumpAndSettle();
      final chip = find.ancestor(of: find.text('내력'), matching: find.byType(DocChip));
      await reveal(tester, chip);
      await tester.tap(chip.first);
      await tester.pump();
      expect(made.bus.slot('doc').value, 'house:h-docs//내력');
    });

    testWidgets('인물 창의 칩은 같은 시기의 지도자 다음에 선다', (tester) async {
      final made = makeBus(fixtures: const ['people-figures.json']);
      final entity = await made.bus.ask({'op': 'entity', 'uid': 'moonwake-chronicle/hero-0'});
      final json = _decode(entity['json'] as String)
        ..['x_docs'] = [
          {'key': 'moonwake-chronicle/hero-0//행적', 'sub': '행적'},
        ];
      await tester.pumpWidget(host(SizedBox(height: 1000, child: FigureDetail.of(bus: made.bus, entity: json))));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('행적'));
      expect(tester.getTopLeft(find.textContaining('같은 시기의 지도자', findRichText: true)).dy, lessThan(tester.getTopLeft(find.text('행적')).dy));
    });
  });

  // 형식 3(설계 A-아카이브-이음 A1-d) — 견본 people-f3edge.json(가상)의 인물 · 가문.
  group('형식 3의 새 줄', () {
    List<String> lines(WidgetTester tester) => [for (final l in tester.widgetList<DetailLine>(find.byType(DetailLine))) detailPlain(l.text)];

    testWidgets('인물 — 원어 줄(다른 이름 다음) · 다스린 칸(같은 이름의 지도자는 뺌) · 혈연 · 속한 단체', (tester) async {
      final made = await open(tester, '가상견본/f-baram', fixtures: const ['people-f3edge.json']);
      expect(lines(tester), [
        'Sol Baram (로마자 · 한국어 로마자)',
        '다스린 칸: 갈마국 바람 왕',
        '부모 · 조상: 부 솔나라 솔 바위 · 모 나루 달 추정',
        '배우자: 갈마 이슬 640년 ~ 670년',
        '자식 · 후손: 솔나라 솔 새벽 · 솔 들 양자',
        '속한 단체: 동녘파',
      ]);
      // 같은 이름의 지도자 줄은 그대로 — 다스린 칸 줄은 그 다음.
      expect(find.text('솔나라 솔 바람'), findsOneWidget);
      expect(tester.getTopLeft(find.text('솔나라 솔 바람')).dy, lessThan(tester.getTopLeft(find.byWidgetPredicate((w) => w is DetailLine && w.text.startsWith('다스린 칸'))).dy));
      tapSpan(tester, '갈마국 바람 왕');
      expect(made.bus.selection.value.uid, '가상견본/p-gal');
      expect(made.bus.selection.value.cell, 'leader:3');
      tapSpan(tester, '솔 들');
      expect(made.bus.selection.value.uid, '가상견본/f-deul');
      expect(made.bus.selection.value.kind, 'figure');
    });

    testWidgets('가문 — 성 배지는 사전의 이름, 제목 다음에 원어 줄과 `성 X — 원어`', (tester) async {
      await open(tester, 'house:h-solbawi', fixtures: const ['people-f3edge.json']);
      expect(tester.widgetList<DetailBadge>(find.byType(DetailBadge)).map((b) => b.text), ['가문', '성 솔', '본관 푸른 벼랑']);
      expect(lines(tester), ['Solbawi (로마자 · 한국어 로마자)', '성 솔 — Sol (로마자 · 한국어 로마자)', '그 밖의 이름: 率 (한자)']);
    });

    testWidgets('형식 3 열쇠가 없는 옛 기록은 지금 그림 그대로', (tester) async {
      await open(tester, 'moonwake-chronicle/hero-0');
      expect(find.byType(DetailLine), findsNothing);
      await open(tester, 'house:h-coast-0');
      expect(find.byType(DetailLine), findsNothing);
      expect(find.text('성 은결'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _decode(String raw) => (jsonDecode(raw) as Map).cast<String, dynamic>();
