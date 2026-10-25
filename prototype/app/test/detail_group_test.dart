import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart' show registerDetailKinds;
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_group.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_shell_test.dart' show host;

// 단체 창 · 제도 창(설계 `docs/설계-10건/A-아카이브-이음.md` 4-2 A1-c 2걸음) — 지금 연표의
// `groupDetailHTML` · `institutionDetailHTML`(js/viewer.js)과 같은 글 · 같은 차례인가.
//
// 고정 자료는 손으로 쓴 항목 기록이다(`test/fixtures/group-samples.json` · `group-edge.json`):
// 본문은 견본 `samples/sample-groups.json` · `sample-lens.json`의 단체 · 제도를 본떴고, `x_…`는 설계 부록 가-6의 꼴,
// 글(기간 글 · 갈래 이름)은 웹 모델이 그 견본에서 만드는 글 그대로다. 시간은 내보내기와 같은 셈의 정수 분.

const year = 525960.0;

/// 항목 기록 + `ids_of`(나라 띠의 줄)에 답하는 검사용 AppBus.
({AppBus bus, List<Map<String, dynamic>> asked}) groupBus({Map<String, int> rows = const {}}) {
  final store = <String, Map<String, dynamic>>{};
  for (final name in const ['group-samples.json', 'group-edge.json']) {
    for (final e in jsonDecode(File('test/fixtures/$name').readAsStringSync()) as List) {
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
        {'id': 1, 'name': '단체 견본', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('상세 창 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      switch (query['op']) {
        case 'entity':
          final row = store[query['uid']];
          if (row == null) throw StateError('없는 항목');
          return row;
        case 'ids_of':
          return {
            'bands': [
              for (final uid in (query['uids'] as List).cast<String>())
                if (rows[uid] != null) {'uid': uid, 'id': 1, 'row': rows[uid], 'start': 0, 'end': 1},
            ],
            'events': const [],
          };
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  bus.slot('tracks').value = const {
    'sample-gr-west': {'name': '서쪽 들', 'color': 0xb6c398},
    'sample-ln-a': {'name': '솔 들', 'color': 0xa0bcc5},
  };
  return (bus: bus, asked: asked);
}

/// 창을 띄우고 뜰 때까지 기다린다.
Future<({AppBus bus, List<Map<String, dynamic>> asked})> open(WidgetTester tester, String uid, {Map<String, int> rows = const {}}) async {
  final made = groupBus(rows: rows);
  registerGroupDetail();
  await tester.pumpWidget(host(SizedBox(height: 1000, child: DetailHost(bus: made.bus, framed: false))));
  made.bus.select(uid);
  await tester.pumpAndSettle();
  return made;
}

List<String> badges(WidgetTester tester) => [for (final b in tester.widgetList<DetailBadge>(find.byType(DetailBadge))) b.text];
List<String> boxes(WidgetTester tester) => [for (final b in tester.widgetList<DetailBox>(find.byType(DetailBox))) '${b.title}${b.small == null ? '' : ' (${b.small})'}'];
List<String> lineTexts(WidgetTester tester) => [for (final l in tester.widgetList<DetailLine>(find.byType(DetailLine))) detailPlain(l.text)];
List<String> kidRows(WidgetTester tester) => [for (final r in tester.widgetList<DetailKidRichRow>(find.byType(DetailKidRichRow))) r.text];
List<String> chips(WidgetTester tester, [Finder? within]) => [
  for (final c in tester.widgetList<DetailDotChip>(within == null ? find.byType(DetailDotChip) : find.descendant(of: within, matching: find.byType(DetailDotChip)))) c.label,
];
Finder boxOf(String title) => find.byWidgetPredicate((w) => w is DetailBox && w.title == title);
DetailDotChip chip(WidgetTester tester, String label) => tester.widgetList<DetailDotChip>(find.byType(DetailDotChip)).firstWhere((c) => c.label == label);

/// 창 안에서 그 위젯이 보이도록 스크롤하고 누른다.
Future<void> tapIn(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.first, 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(finder.first);
  await tester.pump();
}

void main() {
  setUp(() {
    for (final k in detailKinds) {
      DetailHost.unregister(k.id);
    }
  });

  group('단체 창', () {
    testWidgets('머리 · 몸통의 글과 차례가 웹 groupDetailHTML과 같다', (tester) async {
      await open(tester, 'sample-groups/gr-east');
      expect(badges(tester), ['서쪽 들', '단체', '붕당·파벌']);
      expect(find.text('동쪽 무리'), findsOneWidget);
      // 이름 바로 아래 원어 줄(잇기 b — 단체에도 names) → 기간 → 있던 나라.
      expect(lineTexts(tester).take(2), ['Dongjjok Muri (로마자 · 한국어 로마자)', '그 밖의 이름: 東黨 (한자 · 한문)']);
      expect(find.text('842년 ~ 905년'), findsOneWidget);
      expect(find.text('있던 나라'), findsOneWidget);
      expect(chips(tester, find.byType(DetailChipLine)), ['갑 왕국']);
      // 설명이 없으면 안내 글.
      expect(find.text('설명이 없습니다.'), findsOneWidget);
      expect(boxes(tester), ['집권 기간 (2)', '갈래', '구성원 (1)']);
      expect(kidRows(tester), ['851년 ~ 866년집권', '880년 ~ 886년연정 새 무리와 함께']);
      expect(chips(tester, boxOf('갈래')), ['옛 무리 갈라짐']);
      expect(chips(tester, boxOf('구성원')), ['구름 대감 대감']);
      expect(lineTexts(tester).last, '맺은 사건 옛 무리가 둘로 갈라짐 842년');
      expect(find.text('단체 견본 — 붕당 · 연합 · 실권'), findsOneWidget, reason: '제공');
      expect(find.text('이 시기로'), findsOneWidget);
      expect(find.text('문서'), findsOneWidget);
    });

    testWidgets('칩과 이름을 누르면 그 창 — 나라 · 앞선 단체 · 구성원 · 맺은 사건', (tester) async {
      final made = await open(tester, 'sample-groups/gr-east');
      await tapIn(tester, find.byWidget(chip(tester, '갑 왕국')));
      expect(made.bus.selection.value!.uid, 'sample-groups/gr-kap');

      final again = await open(tester, 'sample-groups/gr-east');
      await tapIn(tester, find.byWidget(chip(tester, '옛 무리 갈라짐')));
      expect(again.bus.selection.value!.uid, 'sample-groups/gr-old');
      expect(again.bus.selection.value!.kind, 'group');

      final third = await open(tester, 'sample-groups/gr-east');
      await tapIn(tester, find.byWidget(chip(tester, '구름 대감 대감')));
      expect(third.bus.selection.value!.uid, 'sample-groups/gr-f-cloud');
      expect(third.bus.selection.value!.kind, 'figure');
    });

    testWidgets('갈래(계보) — 앞선 단체 둘 · 뒤를 이은 단체, 끝을 비운 집권 칸의 안내', (tester) async {
      await open(tester, 'sample-groups/gr-new');
      final caps = tester.widgetList<Text>(find.descendant(of: boxOf('갈래'), matching: find.byType(Text))).map((t) => t.textSpan?.toPlainText() ?? t.data).toList();
      expect(caps, containsAllInOrder(['앞선 단체 2', '뒤를 이은 단체 1']));
      expect(chips(tester, boxOf('갈래')), ['서쪽 무리 합쳐짐', '남쪽 무리 합쳐짐', '곧은 길 모임 이름 바꿈']);
      expect(kidRows(tester), ['870년 ~ 880년집권', '880년 ~ 886년연정 동쪽 무리와 함께', '886년 ~ 930년집권 끝은 다음 칸 · 단체의 끝까지']);
    });

    testWidgets('연합 — 구성 나라마다 역할 · 다른 트랙 · 기간 · 메모', (tester) async {
      await open(tester, 'sample-groups/gr-pact');
      expect(badges(tester), ['서쪽 들', '단체', '연합·동맹']);
      expect(find.text('있던 나라'), findsNothing);
      expect(boxes(tester), ['구성 나라 (3)']);
      expect(chips(tester, boxOf('구성 나라')), ['갑 왕국', '을 공국', '병 성읍']);
      expect(find.text('맹주'), findsOneWidget);
      expect(find.text('동쪽 바다'), findsNWidgets(2));
      expect(find.text('· 먼저 빠짐'), findsOneWidget);
      expect(find.text('852년 ~ 890년'), findsOneWidget);
      expect(lineTexts(tester).last, '맺은 사건 세 나라 맹약 맺음 850년');
    });

    testWidgets('구성원 — 인물 · 인물 없는 지도자 칸 · 찾지 못한 이름', (tester) async {
      final made = await open(tester, 'sample-groups/gr-curtain');
      expect(boxes(tester), ['집권 기간 (1)', '구성원 (3)']);
      expect(chips(tester, boxOf('구성원')), ['바람 재상 재상', '셋째 임금 갑 왕국', '이름 모를 장수']);
      expect(chip(tester, '이름 모를 장수').onTap, isNull);
      // 있던 나라의 기간(적었을 때만), 설명과 메모(설명이 있으면 메모는 dl로).
      expect(find.text('895년 ~ 935년'), findsOneWidget);
      expect(find.text('어린 임금 뒤에서 실권을 쥔 무리.'), findsOneWidget);
      expect(find.text('메모'), findsOneWidget);
      await tapIn(tester, find.byWidget(chip(tester, '셋째 임금 갑 왕국')));
      expect(made.bus.selection.value!.uid, 'sample-groups/gr-kap');
      expect(made.bus.selection.value!.cell, 'leader:2');
    });

    testWidgets('확인할 것 · 미정 · 연대 폭 · 찾지 못한 나라 · 사건 · 단체 · 다른 견해 · 쟁점', (tester) async {
      await open(tester, 'sample-groups/gr-shadow');
      expect(badges(tester), ['서쪽 들', '단체', '비밀 결사', '추정 연대', '연도 미정']);
      // 기간 줄(다른 견해 상자의 첫 줄에도 같은 글이 선다 — 웹 altHTML의 '이 연표가 쓰는 연대').
      expect(find.descendant(of: find.byType(DetailWhen), matching: find.text('미정 ~ 기원전 150년')), findsOneWidget);
      expect(find.text('미정 ~ 기원전 150년'), findsNWidgets(2));
      expect(find.text('시작 — 이르면 기원전 220년, 늦으면 기원전 200년'), findsOneWidget);
      // 설명이 없으면 메모가 설명 자리에 — dl에는 메모를 다시 적지 않는다.
      expect(find.text('기록이 한 줄뿐인 모임.'), findsOneWidget);
      expect(find.text('메모'), findsNothing);
      expect(chip(tester, '없는 나라').onTap, isNull);
      expect(chip(tester, '찾지 못한 모임 갈라짐 · 전설').onTap, isNull);
      expect(boxes(tester), ['갈래', '구성원 (1)', '확인할 것 (2)', '다른 견해', '쟁점']);
      expect(tester.widget<DetailBox>(boxOf('확인할 것')).warn, isTrue);
      expect(lineTexts(tester).last, '맺은 사건 사라진 회합 (연표에서 찾지 못함)');
      expect(find.text('문서'), findsNothing);
    });

    testWidgets('집권 칸을 누르면 그 시기로 간다', (tester) async {
      final made = await open(tester, 'sample-groups/gr-east');
      await tapIn(tester, find.byWidgetPredicate((w) => w is DetailKidRichRow && w.when == '851년 ~ 866년'));
      final go = made.bus.go.value!;
      final span = jsonDecode(jsonDecode(File('test/fixtures/group-samples.json').readAsStringSync())[0]['json'] as String)['x_power'][0]['span'] as List;
      expect(go.lo, (span[0] as num).toDouble());
      expect(go.hi, closeTo(go.lo + year, year * .01));
    });

    testWidgets('🎯 이 시기로 — 그 나라 띠의 줄로, 기간의 2.2배 폭(웹 focusOn) · 고리 없음', (tester) async {
      final made = await open(tester, 'sample-groups/gr-east', rows: const {'sample-groups/gr-kap': 7});
      await tester.tap(find.text('이 시기로'));
      await tester.pumpAndSettle();
      expect(made.asked.last, {
        'op': 'ids_of',
        'uids': ['sample-groups/gr-kap'],
      });
      final go = made.bus.go.value!;
      final x = jsonDecode(jsonDecode(File('test/fixtures/group-samples.json').readAsStringSync())[0]['json'] as String) as Map;
      final lo = ((x['x_span'] as List)[0] as num).toDouble(), hi = ((x['x_span'] as List)[1] as num).toDouble();
      expect(go.row, 7);
      expect(go.ring, isNull);
      expect(go.hi - go.lo, closeTo((hi - lo) * 2.2, 1));
      expect((go.lo + go.hi) / 2, closeTo((lo + hi) / 2, 1));
    });

    testWidgets('연합은 구성 나라의 첫 나라 줄로 · 줄을 모르면 기간만', (tester) async {
      final made = await open(tester, 'sample-groups/gr-pact');
      await tester.tap(find.text('이 시기로'));
      await tester.pumpAndSettle();
      expect((made.asked.last['uids'] as List).single, 'sample-groups/gr-kap');
      expect(made.bus.go.value!.row, isNull);
    });
  });

  group('제도 창', () {
    testWidgets('머리 · 몸통의 글과 차례가 웹 institutionDetailHTML과 같다', (tester) async {
      await open(tester, 'sample-lens/ln-i-tax');
      expect(badges(tester), ['솔 들', '제도', '조세제도', '고르게 나눔']);
      expect(find.text('조세제도 솔나라', findRichText: true), findsOneWidget);
      expect(lineTexts(tester).first, 'Sol Joseje (로마자 · 한국어 로마자)');
      expect(find.text('612년 ~ 1000년'), findsOneWidget);
      expect(find.text('나라'), findsOneWidget);
      expect(chips(tester, find.byType(DetailChipLine)), ['솔나라']);
      expect(find.text('· 갈래 고르게 나눔'), findsOneWidget);
      expect(find.text('밭에서 물길로, 물길에서 돈으로.'), findsOneWidget);
      expect(boxes(tester), ['칸 (3)', '같은 갈래의 다른 나라 (1)']);
      expect(kidRows(tester), ['612년 ~ 790년밭 나눔 법', '790년 ~ 905년두 철 거둠 법 봄 · 가을', '905년 ~ 1000년돈 거둠 법']);
      expect(chips(tester, boxOf('같은 갈래의 다른 나라')), ['물나라 650년 ~ 990년']);
      expect(find.text('렌즈 견본 — 주제와 제도'), findsOneWidget);
    });

    testWidgets('같은 갈래의 다른 나라를 누르면 그 나라의 제도 창', (tester) async {
      final made = await open(tester, 'sample-lens/ln-i-tax');
      await tapIn(tester, find.byWidget(chip(tester, '물나라 650년 ~ 990년')));
      expect(made.bus.selection.value!.uid, 'sample-lens/ln-i-tax-mul');
      expect(made.bus.selection.value!.kind, 'institution');
    });

    testWidgets('칸 목록 — 다른 나라에서 온 칸 · 짐작한 경계, 그 아래 온 곳(한 번씩)', (tester) async {
      final made = await open(tester, 'sample-lens/ln-i-tax-mul');
      expect(kidRows(tester), [
        '650년 ~ 700년옛 공물',
        '700년 ~ 860년밭 나눔 법 ← 솔나라 «밭 나눔 법»에서 옴',
        '860년 ~ 990년두 철 거둠 법 ← 솔나라에서 옴 경계는 짐작',
      ]);
      final caps = tester.widgetList<Text>(find.descendant(of: boxOf('칸'), matching: find.byType(Text))).map((t) => t.textSpan?.toPlainText() ?? t.data).toList();
      expect(caps, contains('온 곳'));
      expect(chips(tester, boxOf('칸')), ['솔나라']);
      await tapIn(tester, find.byWidget(chip(tester, '솔나라')));
      expect(made.bus.selection.value!.uid, 'sample-lens/ln-sol');
    });

    testWidgets('미리 푼 값이 모자라도 본문의 이름으로 머리가 선다 — 찾지 못한 나라는 누를 수 없는 칩', (tester) async {
      await open(tester, 'sample-lens/ln-i-bare');
      expect(badges(tester), ['제도', '길드 제도']);
      expect(find.text('길드 제도 먼 나라', findRichText: true), findsOneWidget);
      expect(chip(tester, '먼 나라').onTap, isNull);
      expect(boxes(tester), ['칸 (1)', '확인할 것 (1)']);
      expect(find.text('설명이 없습니다.'), findsOneWidget);
    });

    testWidgets('🎯 이 시기로 — 그 나라 줄 · 칸 전체 기간', (tester) async {
      final made = await open(tester, 'sample-lens/ln-i-tax', rows: const {'sample-lens/ln-sol': 3});
      await tester.tap(find.text('이 시기로'));
      await tester.pumpAndSettle();
      final go = made.bus.go.value!;
      final x = jsonDecode(jsonDecode(File('test/fixtures/group-samples.json').readAsStringSync())[4]['json'] as String) as Map;
      final spans = [for (final s in x['x_spans'] as List) ((s as Map)['span'] as List)];
      final lo = (spans.first[0] as num).toDouble(), hi = (spans.last[1] as num).toDouble();
      expect(go.row, 3);
      expect(go.hi - go.lo, closeTo((hi - lo) * 2.2, 1));
    });
  });

  group('연표와의 사이', () {
    test('앱이 세울 때 부르는 registerDetailKinds()가 단체 · 제도 창을 등록한다', () {
      expect(DetailHost.registered('group'), isFalse);
      registerDetailKinds();
      expect(DetailHost.registered('group'), isTrue);
      expect(DetailHost.registered('institution'), isTrue);
      expect(DetailHost.registered('item'), isTrue, reason: '있던 갈래도 그대로');
    });

    testWidgets('단체 · 제도 창은 연표를 고르거나 흐리게 하지 않고 조명도 켜지 않는다', (tester) async {
      for (final uid in ['sample-groups/gr-east', 'sample-lens/ln-i-tax']) {
        final made = await open(tester, uid);
        final state = made.bus.slot('detail').value as DetailState;
        expect(state.open, isTrue);
        expect(state.pick, isFalse, reason: '$uid — 흐림 없음');
        expect(state.lane, isFalse, reason: '$uid — 세로 닻 없음');
        expect(state.spot, isFalse);
        expect(made.bus.slot('spots').value, isNull);
        expect(made.bus.slot('house').value, isNull);
        expect(made.bus.go.value, isNull, reason: '창을 여는 것만으로는 옮기지 않는다');
      }
    });

    test('구간 셈 — 한 점이면 보는 폭을 해 단위 문턱(30~160년) 안으로', () {
      final wide = detailFocusRange(0, 0, viewSpan: 1000 * year);
      expect(wide.hi - wide.lo, closeTo(160 * year, 1));
      final narrow = detailFocusRange(0, 0, viewSpan: year);
      expect(narrow.hi - narrow.lo, closeTo(30 * year, 1));
      final short = detailFocusRange(0, 2 * year);
      expect(short.hi - short.lo, closeTo(30 * year, 1), reason: '해 단위면 30년보다 좁게 가지 않는다');
      final month = detailFocusRange(0, 0, startAt: '900-03', viewSpan: 100 * year);
      expect(month.hi - month.lo, closeTo(5 * year, 1));
    });
  });
}
