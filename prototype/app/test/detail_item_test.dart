import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_item.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_format3_test.dart' show tapSpan;
import 'detail_shell_test.dart' show host, makeBus;

// 기본 상세(㈎)와 조약 상세(㈖) — 견본은 월흔해 항목 기록(test/fixtures/entities-*.json)에서 꺼낸 것이다.

/// 창을 띄우고 뜰 때까지 기다린다.
Future<({dynamic bus, List<Map<String, dynamic>> asked})> open(
  WidgetTester tester,
  String uid, {
  String? cell,
  List<String> fixtures = const ['entities-basic.json'],
  Map<String, dynamic>? tracks,
  Map<String, dynamic>? categories,
}) async {
  final made = makeBus(fixtures: fixtures);
  registerItemDetail();
  made.bus.slot('tracks').value = tracks ?? const {
    'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5},
    'mw-obsidian': {'name': '검은유리', 'color': 0xbbacc8},
    'mw-delta': {'name': '회백둑', 'color': 0xc8b193},
  };
  made.bus.slot('categories').value = categories ?? const {
    'war': {'name': '전쟁', 'color': 0xd4a39b},
    'diplomacy': {'name': '외교', 'color': 0x9dbea8},
    'mw-magic': {'name': '마법', 'color': 0xbbacc8},
  };
  await tester.pumpWidget(host(SizedBox(height: 1000, child: DetailHost(bus: made.bus, framed: false))));
  made.bus.select(uid, cell: cell);
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

  group('기본 상세 — 시대(정권)', () {
    testWidgets('머리 배지와 기간 줄', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-0');
      expect(find.text('유리항 패총국'), findsOneWidget);
      expect(find.text('유리해안'), findsOneWidget); // 트랙
      expect(find.text('해민'), findsOneWidget); // 민족
      expect(find.text('국성 은결 본가'), findsOneWidget); // 가문
      expect(find.text('시대'), findsOneWidget); // 종류
      expect(find.textContaining('기원전 960년 ~ 기원전 400년'), findsWidgets);
    });

    testWidgets('묶음이 명세의 차례대로 선다', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-0');
      final wanted = ['소속', '왕조', '승계', '지위', '시기 구분(학계)', '지도자', '내각', '연호', '도읍', '인물'];
      double last = -1;
      for (final title in wanted) {
        await reveal(tester, find.textContaining(title));
        final y = tester.getTopLeft(find.textContaining(title).first).dy;
        expect(y, isNotNull, reason: '$title 묶음이 없다');
        last = y;
      }
      expect(last, greaterThan(0));
    });

    testWidgets('지도자 목록을 누르면 그 칸이 열린다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/p-coast-0');
      await reveal(tester, find.text('은결 나나나'));
      await tester.tap(find.text('은결 나나나'));
      await tester.pump();
      expect(made.bus.selection.value.cell, 'leader:0');
    });

    testWidgets('🎯 이 위치로는 그 항목의 범위로 데려간다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/p-coast-0');
      await tester.tap(find.text('이 위치로'));
      await tester.pump();
      final go = made.bus.go.value;
      expect(go, isNotNull);
      // 해 좌표 −960 · −400 → 계약의 분.
      expect(go.lo, closeTo(-1540504800, 1));
      expect(go.ring, 'moonwake-chronicle/p-coast-0');
    });

    testWidgets('비어 있는 묶음은 아예 없다', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-0');
      expect(find.textContaining('포함된 사건'), findsNothing);
      expect(find.textContaining('쟁점'), findsNothing);
      expect(find.textContaining('당사국'), findsNothing);
    });
  });

  group('기본 상세 — 부분 승계 줄', () {
    // 정도(약 · 중 · 강)는 연표의 선에 그리지 않고 여기 글로만 보인다(2026-10-13 감독 결정 '가는 한 줄 · 짙기 80%').
    testWidgets('이름 뒤 옅은 글에 정도와 이어진 것이 나온다', (tester) async {
      await open(tester, 'sample-partial/p-b', fixtures: const ['entities-partial.json']);
      expect(find.text('부분'), findsNWidgets(2));
      expect(find.textContaining('다솜 왕국 정도 강 · 지배층 · 백성', findRichText: true), findsOneWidget);
      expect(find.textContaining('가람 공화국 정도 중', findRichText: true), findsOneWidget, reason: '정도 이름이 실리지 않은 옛 저장소는 번호로 읽는다');
    });
  });

  group('기본 상세 — 실재성 · 연대 폭', () {
    testWidgets('반전설 배지와 실재성 상자 · 이르면/늦으면', (tester) async {
      await open(tester, 'moonwake-chronicle/myth-semi');
      expect(find.text('반전설'), findsWidgets);
      expect(find.text('추정 연대'), findsOneWidget);
      expect(find.text('시작 — 이르면 기원전 1060년, 늦으면 기원전 1000년'), findsOneWidget);
      await reveal(tester, find.textContaining('실재성'));
      expect(find.textContaining('실재는 인정되나'), findsOneWidget);
    });
  });

  group('기본 상세 — 사건', () {
    testWidgets('관점 탭을 누르면 이름과 설명이 바뀐다', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-6-black-salt-war');
      expect(find.text('흑염 전쟁'), findsOneWidget);
      expect(find.text('기본'), findsOneWidget);
      await tester.tap(find.text('회백둑'));
      await tester.pumpAndSettle();
      expect(find.text('꿈 반환 전쟁'), findsOneWidget);
      expect(find.text('기본 이름: 흑염 전쟁'), findsOneWidget);
    });

    testWidgets('포함된 사건과 관련 인물이 나온다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/p-coast-6-black-salt-war');
      await reveal(tester, find.textContaining('포함된 사건'));
      expect(find.text('포함된 사건 9', findRichText: true), findsWidgets);
      await tester.tap(find.text('별목 봉쇄'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-6-campaign');
    });

    testWidgets('쟁점 · 다른 견해 · 미정 안내', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/p-coast-6-unknown');
      expect(find.text('연도 미정'), findsOneWidget);
      expect(find.text('시작 연도 미정 — 연표에는 808년 무렵에 자리를 잡았습니다'), findsOneWidget);
      await reveal(tester, find.textContaining('다른 견해'));
      expect(find.text('이 연표가 쓰는 연대'), findsOneWidget);
      expect(find.text('광부 구술설'), findsOneWidget);
      await tester.tap(find.text('804년'));
      await tester.pump();
      expect(made.bus.go.value, isNotNull);
      await reveal(tester, find.text('쟁점'));
      expect(find.textContaining('발견과 대량 생산'), findsOneWidget);
    });

    testWidgets('부모 사건 빵부스러기', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/p-coast-6-campaign');
      expect(find.text('흑염 전쟁 안의 사건'), findsOneWidget);
      await tester.tap(find.text('흑염 전쟁 안의 사건'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/p-coast-6-black-salt-war');
    });
  });

  group('조약 상세 (㈖)', () {
    testWidgets('조약 배지 · 정식 명칭 · 당사국 · 날짜 진행 표', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-6-treaty-1', fixtures: ['entities-treaty.json']);
      expect(find.text('조약 · 휴전'), findsOneWidget);
      expect(find.text('정식 명칭 흰계단 휴전에 관한 공동 인장 원문'), findsOneWidget);
      // 편이 정확히 둘이므로 좌우 두 칸.
      expect(find.text('편 1'), findsOneWidget);
      expect(find.text('편 2'), findsOneWidget);
      expect(find.text('은륜 제국'), findsWidgets);
      // 날짜 진행 표 — 체결 → 비준 → 발효 → 실효와 사이 간격.
      expect(find.text('체결'), findsOneWidget);
      expect(find.text('비준'), findsOneWidget);
      expect(find.text('발효'), findsOneWidget);
      expect(find.text('실효'), findsOneWidget);
      expect(find.text('53일 뒤'), findsOneWidget);
      expect(find.textContaining('새 조약으로 대체'), findsOneWidget);
      // 조약이면 기본 기간 줄을 쓰지 않는다.
      expect(find.byType(DetailWhen), findsNothing);
    });

    testWidgets('조항은 눌러 펴고 관련 · 장소 · 언어가 나온다', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-6-treaty-1', fixtures: ['entities-treaty.json']);
      await reveal(tester, find.text('경계와 거주'));
      expect(find.text('영토'), findsOneWidget);
      expect(find.textContaining('강물이나 하늘길이'), findsNothing);
      await tester.tap(find.text('경계와 거주'));
      await tester.pumpAndSettle();
      expect(find.textContaining('강물이나 하늘길이'), findsOneWidget);
      await reveal(tester, find.text('관련'));
      expect(find.text('대체한 새 조약'), findsOneWidget);
      expect(find.text('흰계단 공용 회당'), findsOneWidget);
      expect(find.text('등불말 · 울림말 · 나이테글'), findsOneWidget);
    });

    testWidgets('서명자를 누르면 그 인물로 간다', (tester) async {
      final made = await open(tester, 'moonwake-chronicle/p-coast-6-treaty-1', fixtures: ['entities-treaty.json']);
      await reveal(tester, find.textContaining('은결 베루'));
      await tester.tap(find.textContaining('은결 베루'));
      await tester.pump();
      expect(made.bus.selection.value.uid, 'moonwake-chronicle/hero-0');
    });
  });

  group('종류마다의 머리 배지', () {
    testWidgets('기관 · 문화 · 왕조', (tester) async {
      await open(tester, 'moonwake-chronicle/agency-p-coast-0');
      expect(find.text('기관'), findsWidgets);
      await open(tester, 'moonwake-chronicle/culture-coast');
      expect(find.text('문화'), findsWidgets);
      await open(tester, 'moonwake-chronicle/d-coast-0-0');
      expect(find.text('왕조'), findsWidgets);
      await reveal(tester, find.textContaining('다스린 나라'));
      expect(find.text('유리항 패총국'), findsWidgets);
      // 왕조는 다스린 나라가 있으면 메아리 스위치를 둔다.
      await reveal(tester, find.text('같은 시기를 타국에도'));
      expect(find.text('같은 시기를 타국에도'), findsOneWidget);
    });

    testWidgets('진행 중인 정권은 끝이 현재', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-8');
      expect(find.textContaining('~ 현재'), findsWidgets);
    });
  });

  group('이름표가 없을 때', () {
    testWidgets('트랙 · 분류 이름표가 비어 있어도 창은 선다', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-0', tracks: const {}, categories: const {});
      expect(find.text('유리항 패총국'), findsOneWidget);
      expect(find.text('유리해안'), findsNothing);
      expect(find.byType(DetailShell), findsOneWidget);
      expect(Ui.detailWidth, 380);
    });
  });

  // 형식 3(설계 A-아카이브-이음 A1-d) — 견본 entities-f3edge.json(가상)의 사건 · 나라.
  group('형식 3의 새 줄', () {
    List<String> lines(WidgetTester tester) => [for (final l in tester.widgetList<DetailLine>(find.byType(DetailLine))) detailPlain(l.text)];
    List<String> boxes(WidgetTester tester) => [for (final b in tester.widgetList<DetailBox>(find.byType(DetailBox))) b.title ?? ''];

    testWidgets('사건 — 딱지(조약 배지 다음) · 원어 줄 · 장소 · 법 · 선거 · 맺은 단체', (tester) async {
      final made = await open(tester, '가상견본/e-water', fixtures: const ['entities-f3edge.json']);
      expect(tester.widgetList<DetailBadge>(find.byType(DetailBadge)).map((b) => b.text), ['유리해안', '외교', '법률', '물길', '법 · 제정', '선거 · 물길 지기']); // 선거 딱지에는 뽑은 자리(웹 lensBadgesHTML과 같은 글 — 감독 선택 D5 결정 7 A)
      expect(lines(tester).take(2), ['Mulgil Nanum (로마자 · 한국어 로마자)', '장소 갈대 나루 갈대 고을에 속함'], reason: '이 고정 자료에는 x_nameHead가 없어 옛 저장소의 이름 줄을 보존한다. 새 머리는 names_display_test에서 확인한다.');
      // 리메이크 2부(목업 서고): 기간 글은 제목 큰 꼬리표 카드 안 — 해까지만 적은 사건은 날 · 시각 곁들임이 없어 따로 날짜 줄이 없다.
      // 원어 줄은 예전처럼 기간 줄보다 위가 아니라, 기간을 품은 제목 카드 바로 아래에 선다.
      expect(tester.widget<DetailTitle>(find.byType(DetailTitle)).when, '700년');
      expect(find.byType(DetailWhen), findsNothing);
      expect(tester.getTopLeft(find.byType(DetailLine).first).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.byType(DetailTitle)).dy));
      expect(boxes(tester), ['법', '선거', '이 일로 맺은 단체']);
      expect(find.text('제1조 물길은 모두의 것이다.'), findsOneWidget);
      expect(find.text('1,200'), findsOneWidget);
      expect(find.text('당선'), findsOneWidget);
      await reveal(tester, find.byType(DetailDotChip));
      await tester.tap(find.byType(DetailDotChip));
      await tester.pump();
      expect(made.bus.selection.value.uid, '가상견본/gr-water');
    });

    // 감독 선택 D5 결정 7 A — 법의 내력 · 의석 막대의 제자리(웹 js/viewer.js의 차례). 견본 sample-lens를 내보낸 항목 기록(d5-windows.json).
    testWidgets('법 사건 — 법 이름은 제목 아래, 법의 내력은 기간 줄 자리(기간 줄 없음), 조항 · 관련은 설명 아래', (tester) async {
      await open(tester, 'sample-lens/ln-e-amend', fixtures: const ['d5-windows.json'], tracks: const {}, categories: const {});
      expect(find.text('법 이름 새 법전'), findsOneWidget);
      expect(find.byType(DetailWhen), findsNothing, reason: '내력 표에 날짜가 든다 — 기본 기간 줄은 두지 않는다');
      expect(boxes(tester), ['법의 내력', '조항', '관련']);
      final aka = tester.getTopLeft(find.text('법 이름 새 법전')).dy, history = tester.getTopLeft(find.byType(DetailLawHistory)).dy;
      final desc = tester.getTopLeft(find.byType(DetailDesc).first).dy;
      expect(aka, lessThan(history));
      expect(history, lessThan(desc));
      await reveal(tester, find.byType(DetailLawArticles));
      expect(tester.getTopLeft(find.byType(DetailLawArticles)).dy, greaterThan(tester.getTopLeft(find.byType(DetailDesc).first).dy));
    });

    // 리메이크 2부(목업 서고): 기간 글은 따로 날짜 줄이 아니라 제목 큰 꼬리표 카드 안이다 — 그래서 뽑은 자리는 기간(카드) 아래에 선다.
    testWidgets('선거 사건 — 제목 카드(기간) → 뽑은 자리 → 결과(의석 막대) → 설명 → 관련', (tester) async {
      await open(tester, 'sample-lens/ln-e-vote1', fixtures: const ['d5-windows.json'], tracks: const {}, categories: const {});
      expect(boxes(tester), ['결과', '관련']);
      expect(tester.widget<DetailTitle>(find.byType(DetailTitle)).when, '900년');
      expect(find.byType(DetailWhen), findsNothing, reason: '해까지만 적은 선거 — 날 · 시각 곁들임이 없으니 따로 날짜 줄이 없다');
      final card = tester.getBottomLeft(find.byType(DetailTitle)).dy, office = tester.getTopLeft(find.text('뽑은 자리 의회')).dy;
      final vote = tester.getTopLeft(find.byType(DetailVoteBox)).dy, desc = tester.getTopLeft(find.byType(DetailDesc).first).dy;
      expect([card <= office, office < vote, vote < desc], [true, true, true], reason: '$card · $office · $vote · $desc');
      expect(find.text('뽑은 자리 의회'), findsOneWidget, reason: '아래 묶음에 한 번 더 서지 않는다');
    });

    testWidgets('나라 — 원어 줄 · 단체 · 제도 칩(대범위 다음 · 왕조 앞)', (tester) async {
      final made = await open(tester, '가상견본/p-sol', fixtures: const ['entities-f3edge.json']);
      expect(lines(tester), ['Solnara (로마자 · 한국어 로마자)', '그 밖의 이름: 옛 솔골 (옛 이름 · 600년 ~ 700년)']);
      expect(boxes(tester), ['대범위', '단체', '제도', '왕조']);
      expect(tester.widgetList<DetailDotChip>(find.byType(DetailDotChip)).map((c) => c.label), ['동녘파 붕당·파벌', '세 물길 연합 구성 나라로', '조세제도 고르게 나눔']);
      await reveal(tester, find.text('조세제도 고르게 나눔'));
      await tester.tap(find.text('조세제도 고르게 나눔'));
      await tester.pump();
      expect(made.bus.selection.value.uid, '가상견본/in-tax');
      expect(made.bus.selection.value.kind, 'institution');
    });

    testWidgets('형식 3 열쇠가 없는 옛 기록은 지금 그림 그대로', (tester) async {
      await open(tester, 'moonwake-chronicle/p-coast-0');
      expect(find.byType(DetailLine), findsNothing);
      expect(find.byType(DetailDotChip), findsNothing);
      expect(boxes(tester).where((t) => t == '단체' || t == '제도' || t == '법' || t == '선거'), isEmpty);
    });

    testWidgets('장소의 지명은 누르지 않는다(웹도 글만)', (tester) async {
      await open(tester, '가상견본/e-water', fixtures: const ['entities-f3edge.json']);
      expect(() => tapSpan(tester, '장소 갈대 나루'), throwsA(isA<TestFailure>()));
    });
  });
}
