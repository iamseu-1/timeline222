import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/detail_scope.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/doc_window.dart' show DocChip;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_shell_test.dart' show host, makeBus;

// 시대 구분 창(㈔)과 대범위 창(㈕) — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-3절.
// 견본은 월흔해 항목 기록(test/fixtures/scopes-*.json)에서 꺼낸 것이고,
// 월흔해에 없는 '확인할 것' · 다른 트랙 구성 정권 · 빈 구성 정권은 같은 꼴로 지어 넣었다(scope-check · scope-empty).

const pack = 'moonwake-chronicle/';

/// 창을 띄우고 뜰 때까지 기다린다.
Future<({AppBus bus, List<Map<String, dynamic>> asked})> open(
  WidgetTester tester,
  String uid, {
  List<String> fixtures = const ['scopes-epoch.json', 'scopes-scope.json'],
  Map<String, dynamic>? tracks,
  Map<String, bool>? scopes,
}) async {
  final made = makeBus(fixtures: fixtures);
  registerScopeDetail();
  made.bus.slot('tracks').value = tracks ?? const {
    'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5},
    'mw-obsidian': {'name': '흑요산맥', 'color': 0xbbacc8},
  };
  if (scopes != null) made.bus.slot('scopes').value = scopes;
  await tester.pumpWidget(host(SizedBox(height: 1000, child: DetailHost(bus: made.bus, framed: false))));
  made.bus.select(pack + uid);
  await tester.pumpAndSettle();
  return made;
}

/// 창 안에서 그 글이 보이도록 스크롤한다(몸통은 맨 바깥 스크롤 하나뿐).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.first, 120, scrollable: find.byType(Scrollable).first);
}

/// 그 글이 든 [LinkNote]의 이름을 누른다.
Future<void> tapLink(WidgetTester tester, String name) async {
  final finder = find.descendant(of: find.byType(LinkNote), matching: find.text(name));
  await reveal(tester, finder);
  await tester.tap(finder.first);
  await tester.pump();
}

void main() {
  setUp(() {
    for (final k in detailKinds) {
      DetailHost.unregister(k.id);
    }
  });

  group('시대 구분 창 (㈔)', () {
    testWidgets('배지 · 제목 · 기간 · 설명', (tester) async {
      await open(tester, 'epoch-6');
      expect(find.text('공통'), findsOneWidget); // 트랙이 없는 시대 구분
      expect(find.text('시대 구분'), findsOneWidget);
      expect(find.text('흑염 전쟁 시대'), findsOneWidget);
      expect(tester.widget<DetailWhen>(find.byType(DetailWhen)).text, '720년 ~ 960년');
      expect(find.textContaining('기억을 돌려 달라는 봉기'), findsOneWidget);
      expect(find.text('제공'), findsOneWidget);
    });

    testWidgets('트랙이 있으면 그 트랙 배지 · 누르면 트랙 문서', (tester) async {
      final made = await open(tester, 'local-epoch-coast');
      expect(find.text('유리해안'), findsOneWidget);
      await tester.tap(find.text('유리해안'));
      await tester.pump();
      expect(made.bus.slot('doc').value, 'track:mw-coast');
    });

    testWidgets('진행 중인 시대는 끝이 현재', (tester) async {
      await open(tester, 'epoch-8');
      expect(find.text('1200년 ~ 현재'), findsOneWidget);
    });

    testWidgets('다른 견해 — 첫 줄은 이 연표가 쓰는 연대, 연대를 누르면 그 해로', (tester) async {
      final made = await open(tester, 'epoch-6');
      await reveal(tester, find.textContaining('다른 견해'));
      expect(find.text('이 연표가 쓰는 연대'), findsOneWidget);
      expect(find.text('꿈실 학파의 긴 전쟁설 · 가상 문헌 『돌려받지 못한 밤』'), findsOneWidget);
      // 날짜 없이 근거만 적은 견해는 '—' 한 줄로 서고 누르지 않는다.
      expect(find.text('—'), findsOneWidget);
      await tester.tap(find.text('708년 ~ 968년'));
      await tester.pump();
      expect(made.bus.go.value, isNotNull);
      expect(made.bus.go.value!.lo, closeTo(minutesOfT(708), 1));
    });

    testWidgets('이어진 대범위 — 칩과 모아 보기 스위치', (tester) async {
      final made = await open(tester, 'epoch-7');
      await reveal(tester, find.textContaining('이어진 대범위'));
      expect(find.text('이어진 대범위', findRichText: true), findsOneWidget);
      expect(find.text('모아 보기'), findsOneWidget);
      expect(find.text('끔'), findsOneWidget);
      await tester.tap(find.text('모아 보기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot('scopes').value, {'${pack}scope-epoch': true});
      expect(find.text('켬'), findsOneWidget);
      // 칩을 누르면 그 대범위의 창으로.
      final chip = find.descendant(of: find.byType(DetailChip), matching: find.text('무왕 협약 시대'));
      await tester.tap(chip.first);
      await tester.pump();
      expect(made.bus.selection.value!.uid, '${pack}scope-epoch');
    });

    testWidgets('비어 있는 묶음은 아예 없다', (tester) async {
      await open(tester, 'epoch-8');
      expect(find.textContaining('다른 견해'), findsNothing);
      expect(find.textContaining('이어진 대범위'), findsNothing);
      expect(find.text('모아 보기'), findsNothing);
    });

    testWidgets('🎯 이 시기로는 그 시대의 범위로 데려간다', (tester) async {
      final made = await open(tester, 'epoch-6');
      expect(find.text('이 시기로'), findsOneWidget);
      await tester.tap(find.text('이 시기로'));
      await tester.pump();
      final go = made.bus.go.value!;
      expect(go.lo, closeTo(minutesOfT(720), 1));
      expect(go.hi, closeTo(minutesOfT(960), 1));
      expect(go.ring, '${pack}epoch-6');
    });

    testWidgets('📄 문서는 그 항목의 uid를 알린다', (tester) async {
      final made = await open(tester, 'epoch-6');
      await tester.tap(find.text('문서'));
      await tester.pump();
      expect(made.bus.slot('doc').value, '${pack}epoch-6');
    });
  });

  group('대범위 창 (㈕)', () {
    testWidgets('배지 셋 · 제목 · 기간', (tester) async {
      await open(tester, 'scope-warlords');
      expect(find.text('유리해안'), findsOneWidget);
      expect(find.text('대범위'), findsOneWidget);
      expect(find.text('할거'), findsOneWidget); // 성격 딱지
      expect(find.text('빈 왕좌의 할거'), findsOneWidget);
      expect(find.text('818년 ~ 930년'), findsOneWidget);
    });

    testWidgets('기간을 물려받았으면 어디에서인지 적는다', (tester) async {
      await open(tester, 'scope-epoch');
      expect(find.text('시대 구분의 기간'), findsOneWidget);
      await open(tester, 'scope-scattered');
      expect(find.text('구성 정권의 범위'), findsOneWidget);
    });

    testWidgets('모아 보기 스위치가 기간 줄 바로 아래에 선다', (tester) async {
      final made = await open(tester, 'scope-warlords');
      expect(find.text('모아 보기'), findsOneWidget);
      expect(tester.getTopLeft(find.text('모아 보기')).dy, lessThan(tester.getTopLeft(find.byType(DetailDesc)).dy));
      await tester.tap(find.text('모아 보기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot('scopes').value, {'${pack}scope-warlords': true});
    });

    testWidgets('기본으로 켜 둔 대범위는 기록이 없어도 켬', (tester) async {
      await open(tester, 'scope-check');
      expect(find.text('켬'), findsOneWidget);
    });

    testWidgets('밖에서 켜 둔 값을 그대로 보인다', (tester) async {
      await open(tester, 'scope-warlords', scopes: {'${pack}scope-warlords': true});
      expect(find.text('켬'), findsOneWidget);
    });

    testWidgets('상징적 본국 한마디 — 누르면 그 나라로', (tester) async {
      final made = await open(tester, 'scope-warlords');
      expect(find.textContaining('이름만 남은 본국'), findsOneWidget);
      await tapLink(tester, '은륜 제국');
      expect(made.bus.selection.value!.uid, '${pack}p-coast-6');
    });

    testWidgets('본국이 끝난 뒤의 부흥은 다른 한마디', (tester) async {
      await open(tester, 'scope-revival');
      expect(find.textContaining('본국이 끝난 뒤의 부흥'), findsOneWidget);
    });

    testWidgets('구성 정권 목록 — 누르면 그 정권의 창으로', (tester) async {
      final made = await open(tester, 'scope-warlords');
      await reveal(tester, find.textContaining('구성 정권'));
      expect(find.text('구성 정권 3', findRichText: true), findsOneWidget);
      expect(find.text('검은 인장 정부'), findsOneWidget);
      expect(find.text('772년 ~ 912년'), findsOneWidget);
      expect(find.text('해민'), findsWidgets); // 민족 이름이 배지 자리에
      await tester.tap(find.text('검은 인장 정부'));
      await tester.pump();
      expect(made.bus.selection.value!.uid, '${pack}client-6');
    });

    testWidgets('다른 트랙의 구성 정권은 따로 · 곳 수에 들지 않는다', (tester) async {
      await open(tester, 'scope-check');
      await reveal(tester, find.textContaining('구성 정권'));
      expect(find.text('구성 정권 1', findRichText: true), findsOneWidget);
      expect(find.text('다른 트랙 — 모이지 않음'), findsOneWidget);
      expect(find.text('잿빛 회랑 상단'), findsOneWidget);
    });

    testWidgets('구성 정권이 없으면 그 자리에 안내', (tester) async {
      await open(tester, 'scope-empty');
      expect(find.text('구성 정권 0', findRichText: true), findsOneWidget);
      expect(find.text('이 트랙에서 찾은 구성 정권이 없습니다.'), findsOneWidget);
      expect(find.text('설명이 없습니다.'), findsOneWidget);
      expect(find.text('문서'), findsNothing); // 문서가 없으면 단추도 없다
    });

    testWidgets('이어진 시대 구분 — 물려받은 것을 적고 누르면 그 시대로', (tester) async {
      final made = await open(tester, 'scope-epoch');
      expect(find.textContaining('비워 둔 이름 · 기간 · 색을 물려받음'), findsOneWidget);
      await tapLink(tester, '무왕 협약 시대');
      expect(made.bus.selection.value!.uid, '${pack}epoch-7');
      expect(made.bus.selection.value!.kind, 'epoch');
    });

    testWidgets('확인할 것은 노란 상자로', (tester) async {
      await open(tester, 'scope-check');
      await reveal(tester, find.textContaining('확인할 것'));
      expect(find.text('확인할 것 2', findRichText: true), findsOneWidget);
      expect(find.textContaining('다른 트랙에 있어 모이지 않습니다'), findsOneWidget);
      final box = tester.widgetList<DetailBox>(find.byType(DetailBox)).firstWhere((b) => b.title == '확인할 것');
      expect(box.warn, isTrue);
    });

    testWidgets('설명이 따로 있을 때만 메모가 dl에 든다', (tester) async {
      await open(tester, 'scope-check');
      await reveal(tester, find.text('제공'));
      expect(find.text('메모'), findsOneWidget);
      expect(find.text('구성 정권을 더 확인해야 한다.'), findsOneWidget);
      await open(tester, 'scope-warlords');
      await reveal(tester, find.text('제공'));
      expect(find.text('메모'), findsNothing);
    });

    testWidgets('비어 있는 묶음은 아예 없다', (tester) async {
      await open(tester, 'scope-scattered');
      expect(find.textContaining('이름만 남은 본국'), findsNothing);
      expect(find.textContaining('확인할 것'), findsNothing);
      expect(find.byType(LinkNote), findsNothing);
    });

    testWidgets('🎯 이 시기로는 그 대범위의 범위로 데려간다', (tester) async {
      final made = await open(tester, 'scope-warlords');
      await tester.tap(find.text('이 시기로'));
      await tester.pump();
      final go = made.bus.go.value!;
      expect(go.lo, closeTo(minutesOfT(818), 1));
      expect(go.hi, closeTo(minutesOfT(930), 1));
    });
  });

  group('갈래 — 제 줄이 없는 항목 (명세 9절 ㈐-7)', () {
    testWidgets('시대 구분 · 대범위는 세로 닻을 걸지 않고 조명도 켜지 않는다', (tester) async {
      final made = await open(tester, 'epoch-6');
      final epoch = made.bus.slot('detail').value! as DetailState;
      expect(epoch.branch!.id, 'epoch');
      expect(epoch.lane, isFalse);
      expect(epoch.spot, isFalse);
      expect(epoch.pick, isTrue);

      made.bus.select('${pack}scope-warlords');
      await tester.pumpAndSettle();
      final scope = made.bus.slot('detail').value! as DetailState;
      expect(scope.branch!.id, 'scope');
      expect(scope.lane, isFalse);
      expect(scope.spot, isFalse);
    });

    testWidgets('트랙 이름표가 비어 있어도 창은 선다', (tester) async {
      await open(tester, 'scope-warlords', tracks: const {});
      expect(find.text('빈 왕좌의 할거'), findsOneWidget);
      expect(find.text('유리해안'), findsOneWidget); // 항목 기록의 trackName으로
      expect(find.byType(DetailShell), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────────────────────
  //  하위 문서 칩 — 지금 연표는 대범위 창에만 둔다(`scopeDetailHTML`의 `subdocsHTML` · js/viewer.js:1043).
  //  시대 구분 창(`epochDetailHTML`)에는 없으므로 여기에도 두지 않는다.
  // ────────────────────────────────────────────────────────────────────────────────────────────

  group('하위 문서 칩', () {
    /// 하위 문서 둘을 단 견본 하나(항목 기록에 미리 푼 `x_docs`).
    const withDocs = {
      'uid': '${pack}scope-docs',
      'name': '아홉 인장 협약',
      'start': 818.0,
      'end': 930.0,
      'color': 0xa0bcc5,
      'track': 'mw-coast',
      'trackName': '유리해안',
      'packName': '월흔해 연대기',
      'warnings': ['구성 정권의 끝이 서로 다릅니다'],
      'x_docs': [
        {'key': '${pack}scope-docs//역사', 'sub': '역사'},
        {'key': '${pack}scope-docs//문화', 'sub': '문화'},
      ],
    };

    Future<({AppBus bus, List<Map<String, dynamic>> asked})> pump(WidgetTester tester, Widget Function(AppBus bus) build) async {
      final made = makeBus();
      await tester.pumpWidget(host(SizedBox(height: 1000, child: build(made.bus))));
      await tester.pumpAndSettle();
      return made;
    }

    testWidgets('대범위 창에 칩이 서고, 되묻지 않는다', (tester) async {
      final made = await pump(tester, (bus) => ScopeDetail(bus: bus, entity: withDocs));
      await reveal(tester, find.textContaining('하위 문서', findRichText: true));
      expect(find.text('하위 문서 2', findRichText: true), findsOneWidget);
      expect(find.text('역사'), findsOneWidget);
      expect(find.text('문화'), findsOneWidget);
      expect(made.asked, isEmpty, reason: '기록에 x_docs가 있으면 되묻지 않는다');
    });

    testWidgets('칩은 확인할 것 다음 · 제공 앞에 선다(지금 연표의 차례)', (tester) async {
      await pump(tester, (bus) => ScopeDetail(bus: bus, entity: withDocs));
      await reveal(tester, find.text('제공'));
      expect(tester.getTopLeft(find.textContaining('확인할 것', findRichText: true)).dy, lessThan(tester.getTopLeft(find.text('역사')).dy));
      expect(tester.getTopLeft(find.text('역사')).dy, lessThan(tester.getTopLeft(find.text('제공')).dy));
    });

    testWidgets('칩을 누르면 문서 열쇠가 실린다', (tester) async {
      final made = await pump(tester, (bus) => ScopeDetail(bus: bus, entity: withDocs));
      final chip = find.ancestor(of: find.text('역사'), matching: find.byType(DocChip));
      await reveal(tester, chip);
      await tester.tap(chip.first);
      await tester.pump();
      expect(made.bus.slot('doc').value, '${pack}scope-docs//역사');
    });

    testWidgets('시대 구분 창에는 하위 문서 묶음이 없다', (tester) async {
      await pump(tester, (bus) => EpochDetail(bus: bus, entity: withDocs));
      expect(find.byType(DocChip), findsNothing);
      expect(find.textContaining('하위 문서', findRichText: true), findsNothing);
    });
  });
}
