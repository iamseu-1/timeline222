import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/parts.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/legend.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:archive_prototype/ui/tools_measure.dart';
import 'package:archive_prototype/ui/tools_year.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 보조 도구 셋(명세 06의 7-1 · 7-2 · 7-3): 같은 해 보기 · 기간 재기 · 범례.
// 자료 처리부에 `same_year` · `legend_kinds`가 아직 없어, 견본 월흔해에서 뽑아 둔 test/fixtures의 답으로 가짜 `ask`를 만들어 돌린다.

/// 검사용 AppBus. 보기는 기원전 1000년~기원전 500년(500년 폭)이고, 물어 온 명령은 [asked]에 쌓인다. [legend]를 주면 범례 물음에 그 답을 준다.
({AppBus bus, List<Map<String, dynamic>> asked}) makeBus({Map<String, dynamic>? legend}) {
  final sameYear = jsonDecode(File('test/fixtures/도구-같은해.json').readAsStringSync()) as Map<String, dynamic>;
  final legendAnswer = legend ?? jsonDecode(File('test/fixtures/도구-범례.json').readAsStringSync()) as Map<String, dynamic>;
  final asked = <Map<String, dynamic>>[];
  final controller = TimelineController()
    ..resize(800, 600)
    ..setExtent(-1872000000, 28800000)
    ..setContentHeight(2000);
  controller.showRange(-1000 * minutesPerYear, -500 * minutesPerYear);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 24},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('도구 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      if (query['op'] == 'same_year') return {...sameYear, 'at': query['at'], 'end': query['end']};
      if (query['op'] == 'legend_kinds') return legendAnswer;
      throw StateError('모르는 명령: ${query['op']}');
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, asked: asked);
}

/// 부품 하나를 그 크기의 상자에 띄우는 틀.
Widget host(Widget child, {double width = 800, double height = 600}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    backgroundColor: Ui.bg,
    body: Center(child: SizedBox(width: width, height: height, child: child)),
  ),
);

/// 해 좌표의 한 날짜 → 분.
double at(int year, [int month = 1, int day = 1, double hourFrac = 0]) => minutesOfT(tOfJdn(jdnOf(year, month, day), hourFrac));

void main() {
  group('기간 재기 — 순수 함수', () {
    test('길이 글은 해 → 개월 → 일 → 시간으로 센다', () {
      expect(measureLengthText(at(800), at(2000), DatePrec.year), '1,200년');
      expect(measureLengthText(at(800, 3), at(803, 5), DatePrec.month), '3년 2개월');
      expect(measureLengthText(at(800), at(800, 4, 13), DatePrec.day), '3개월 12일 (103일)'); // 800년은 율리우스력의 윤년(2월 29일)
      expect(measureLengthText(at(800), at(800, 1, 3, 5 / 24), DatePrec.hour), '2일 5시간');
      expect(measureLengthText(at(800), at(800, 1, 10), DatePrec.month), '한 달 미만');
      expect(measureLengthText(at(800), at(800, 1, 1, 5 / 24), DatePrec.day), '하루 미만');
      expect(measureLengthText(at(800), at(800, 1, 1, 10 / 1440), DatePrec.hour), '한 시간 미만');
    });

    test('자세함은 보기 폭과 잰 길이 가운데 좁은 쪽으로 — 넓게 보면서 짧게 재도 0년이 아니다', () {
      expect(measurePrec(1000 * minutesPerYear, 100 * minutesPerYear), DatePrec.year);
      expect(measurePrec(1000 * minutesPerYear, 3 * minutesPerYear), DatePrec.month);
      expect(measurePrec(3 * minutesPerYear, 1000 * minutesPerYear), DatePrec.month);
      expect(measurePrec(minutesPerDay, minutesPerDay), DatePrec.hour);
      // 1,000년을 보면서 3년을 재면 '3년'이지 '0년'이 아니다.
      expect(measureLengthText(at(800), at(803), measurePrec(1000 * minutesPerYear, 3 * minutesPerYear)), '3년');
    });

    test('두 끝의 글은 같은 해면 뒤쪽의 겹치는 앞부분을 줄인다', () {
      expect(measureRangeText(at(1592, 5, 3), at(1592, 5, 20), DatePrec.day), '1592년 5월 3일 ~ 20일');
      expect(measureRangeText(at(-960), at(-400), DatePrec.year), '기원전 960년 ~ 기원전 400년');
    });
  });

  group('기간 재기 — 부품', () {
    testWidgets('끌면 그 범위가 슬롯에 남고, 보기 폭의 0.5%보다 짧으면 없던 일이 된다', (tester) async {
      final h = makeBus();
      h.bus.slot(measureOnSlot).value = true;
      await tester.pumpWidget(host(MeasureLayer(bus: h.bus)));

      final layer = tester.getTopLeft(find.byType(MeasureLayer));
      final view = h.bus.controller.view;
      await tester.dragFrom(layer + const Offset(250, 100), const Offset(400, 0));
      await tester.pump();

      final range = measureRange(h.bus);
      expect(range, isNotNull, reason: '끌었으면 잰 범위가 남는다');
      expect(range![0], closeTo(view.minuteAt(250), view.span * .01));
      expect(range[1], closeTo(view.minuteAt(650), view.span * .01));

      await tester.dragFrom(layer + const Offset(250, 100), const Offset(1, 0));
      await tester.pump();
      expect(measureRange(h.bus), isNull, reason: '보기 폭의 0.5%보다 짧게 끈 것은 재려다 만 것으로 본다');
    });

    testWidgets('끄면 잰 것도 함께 치운다', (tester) async {
      final h = makeBus();
      h.bus.slot(measureOnSlot).value = true;
      h.bus.slot(measureSlot).value = [at(-900), at(-800)];
      await tester.pumpWidget(host(MeasureLayer(bus: h.bus)));
      h.bus.slot(measureOnSlot).value = false;
      await tester.pump();
      expect(measureRange(h.bus), isNull);
      expect(
        find.descendant(of: find.byType(MeasureLayer), matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '꺼져 있으면 끌기 판도 그림도 없어 연표가 손을 그대로 받는다',
      );
    });

    testWidgets('단축키 · 메뉴의 📏 명령이 켜고 끈다', (tester) async {
      final h = makeBus();
      await tester.pumpWidget(host(MeasureLayer(bus: h.bus)));
      runCommand(h.bus, Cmd.measure);
      await tester.pump();
      expect(h.bus.slot(measureOnSlot).value, true);
      expect(h.bus.slot(slotNotice).value, contains('좌우로 드래그'));

      runCommand(h.bus, Cmd.measure);
      await tester.pump();
      expect(h.bus.slot(measureOnSlot).value, false);
    });

    testWidgets('결과 알약은 두 시점과 길이를 보이고 지우기로 지운다', (tester) async {
      final h = makeBus();
      await tester.pumpWidget(host(Align(alignment: Alignment.topLeft, child: MeasurePill(bus: h.bus))));
      expect(find.textContaining(' · '), findsNothing, reason: '잰 것이 없으면 알약도 없다');

      h.bus.slot(measureSlot).value = [at(-900), at(-800)];
      await tester.pump();
      expect(find.text('기원전 900년 ~ 기원전 800년 · '), findsOneWidget);
      expect(find.text('100년'), findsOneWidget);

      await tester.tap(find.text('지우기'));
      await tester.pump();
      expect(find.textContaining('📏'), findsNothing);
      expect(h.bus.slot(measureSlot).value, isNull);
    });
  });

  group('같은 해 보기 — 순수 함수', () {
    test('기준 단위는 확대 정도로 정한다', () {
      expect(yearUnitFor(100 * minutesPerYear), YearUnit.year);
      expect(yearUnitFor(minutesPerYear), YearUnit.month);
      expect(yearUnitFor(10 * minutesPerDay), YearUnit.day);
    });

    test('앞뒤 범위의 글과 처음 값', () {
      expect(windowText(0, YearUnit.year), '±0년');
      expect(windowText(10 * minutesPerYear, YearUnit.year), '±10년');
      expect(windowText(minutesPerMonth, YearUnit.month), '±1개월');
      expect(windowText(7 * minutesPerDay, YearUnit.day), '±7일');
      expect(YearUnit.year.windows.map((w) => windowText(w, YearUnit.year)).toList(), ['±0년', '±5년', '±10년', '±25년', '±50년', '±100년']);
      expect(YearUnit.month.windows.map((w) => windowText(w, YearUnit.month)).toList(), ['±0개월', '±1개월', '±3개월', '±6개월', '±1년', '±5년']);
      expect(YearUnit.day.windows.map((w) => windowText(w, YearUnit.day)).toList(), ['±0일', '±3일', '±7일', '±1개월', '±3개월', '±1년']);
      expect(YearUnit.day.defaultWindow, 7 * minutesPerDay);
    });

    test('기준 때는 그 해 · 달 · 날의 첫 순간으로 맞추고, 보는 구간은 다음 단위까지다', () {
      final middle = at(-840, 7, 15);
      expect(snapTo(middle, YearUnit.year), at(-840));
      expect(unitEndMinute(snapTo(middle, YearUnit.year), YearUnit.year), at(-839));
      expect(snapTo(middle, YearUnit.month), at(-840, 7));
      expect(unitEndMinute(snapTo(middle, YearUnit.month), YearUnit.month), at(-840, 8));
      expect(snapTo(middle, YearUnit.day), at(-840, 7, 15));
      expect(unitEndMinute(snapTo(middle, YearUnit.day), YearUnit.day), at(-840, 7, 16));
    });
  });

  group('같은 해 보기 — 창', () {
    testWidgets('그때의 나라 · 시기 · 인물 · 앞뒤 사건을 보이고 기준선을 놓는다', (tester) async {
      final h = makeBus();
      await tester.pumpWidget(host(Align(alignment: Alignment.topRight, child: SizedBox(height: 560, child: YearPanel(bus: h.bus))), width: 1200, height: 600));
      expect(find.byType(GlassCard), findsNothing, reason: '부탁이 없으면 창도 없다');

      h.bus.slot(yearSlot).value = YearRequest(at(-840, 7, 15));
      await tester.pumpAndSettle();

      expect(find.text('기원전 840년'), findsOneWidget, reason: '제목은 기준 단위만큼만');
      expect(find.text('기준 연도'), findsOneWidget);
      expect(find.text('신유년'), findsOneWidget, reason: '해 단위의 곁들임 줄은 그해의 간지');
      expect(h.bus.slot(markerSlot).value, at(-840), reason: '여는 순간 기준선을 놓는다');
      expect(h.asked.last['op'], 'same_year');
      expect(h.asked.last['at'], at(-840));
      expect(h.asked.last['end'], at(-839));
      expect(h.asked.last['window'], 10 * minutesPerYear, reason: '해 단위의 처음 범위는 ±10년');

      expect(find.text('그때 각 나라는'), findsOneWidget);
      expect(find.descendant(of: find.byType(Linky), matching: find.text('유리항 패총국')), findsOneWidget);
      expect(find.text('그때의 시기 구분(학계)'), findsOneWidget);
      expect(find.text('그때 활동한 인물'), findsOneWidget);
      expect(find.textContaining('안의 사건'), findsOneWidget);
      expect(find.text('이 해로'), findsOneWidget);
    });

    testWidgets('정권을 누르면 그 항목이 골라지고 창은 물러난다', (tester) async {
      final h = makeBus();
      await tester.pumpWidget(host(Align(alignment: Alignment.topRight, child: SizedBox(height: 560, child: YearPanel(bus: h.bus))), width: 1200, height: 600));
      h.bus.slot(yearSlot).value = YearRequest(at(-840));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(Linky), matching: find.text('유리항 패총국')));
      await tester.pumpAndSettle();
      expect(h.bus.selection.value?.uid, 'moonwake-chronicle/p-coast-0');
      expect(h.bus.slot(yearSlot).value, isNull, reason: '상세 창이 같은 자리를 쓰므로 같은 해 보기는 닫힌다');
      expect(h.bus.slot(markerSlot).value, isNull, reason: '닫으면 기준선도 거둔다');
      expect(find.text('기원전 840년'), findsNothing);
    });

    testWidgets('📍 명령은 화면 가운데에서 여닫고, 검색이 싣는 해 좌표 부탁도 받는다', (tester) async {
      final h = makeBus();
      await tester.pumpWidget(host(Align(alignment: Alignment.topRight, child: SizedBox(height: 560, child: YearPanel(bus: h.bus))), width: 1200, height: 600));

      runCommand(h.bus, Cmd.year); // 📍 단추 · Y
      await tester.pumpAndSettle();
      final view = h.bus.controller.view;
      expect(h.asked.last['at'], snapTo(view.lo + view.span / 2, YearUnit.year));
      expect(h.bus.slot(slotNotice).value, contains('기준선'));

      runCommand(h.bus, Cmd.year); // 다시 누르면 닫힌다
      await tester.pumpAndSettle();
      expect(find.text('기준 연도'), findsNothing);
      expect(h.bus.slot(markerSlot).value, isNull);

      // 검색은 해 좌표로 싣는다(`search.dart`) — 분으로 옮겨 읽는다.
      h.bus.slot(yearSlot).value = {'t': -840.0, 'end': -839.0, 'prec': 'y', 'label': '기원전 840년(간지로 찾음)'};
      await tester.pumpAndSettle();
      expect(find.text('기원전 840년(간지로 찾음)'), findsOneWidget);
      expect(h.asked.last['at'], at(-840));
      expect(h.bus.slot(markerSlot).value, at(-840));
    });

    testWidgets('🎯 이 해로 이동은 폭을 그대로 둔 채 그 해를 가운데로 데려간다', (tester) async {
      final h = makeBus();
      await tester.pumpWidget(host(Align(alignment: Alignment.topRight, child: SizedBox(height: 560, child: YearPanel(bus: h.bus))), width: 1200, height: 600));
      h.bus.slot(yearSlot).value = YearRequest(at(-840));
      await tester.pumpAndSettle();

      final span = h.bus.controller.view.span;
      await tester.tap(find.text('이 해로'));
      await tester.pump();
      final go = h.bus.go.value!;
      expect(go.hi - go.lo, closeTo(span, 1));
      expect((go.lo + go.hi) / 2, closeTo((at(-840) + at(-839)) / 2, 1));
    });
  });

  group('범례', () {
    // 서고 폴더로 다시 그린 범례(리메이크 4단계 걸음 4)의 자세한 검사는 legend_test.dart — 여기는 도구 셋의 길(명령 · 슬롯 · 물음 · 폭)만 본다.
    LegendFacts facts() => LegendFacts.fromJson(jsonDecode(File('test/fixtures/도구-범례.json').readAsStringSync()) as Map<String, dynamic>);
    List<LegendRow> rowsOf(LegendFacts f) => [for (final b in buildLegend(f)) ...b.rows];

    test('지금 자료에 쓰인 것만 그린다', () {
      final rows = rowsOf(facts()).map((r) => r.text).join('\n');
      expect(rows, contains('종속 갈래 — 옅은 띠'), reason: '종속 갈래가 여럿이면 한 줄로 묶는다');
      expect(rows, contains('조공·책봉국'), reason: '묶은 줄에 쓰인 종류의 이름이 함께 나온다');
      expect(rows, isNot(contains('부분 승계')), reason: '견본 자료에 부분 승계가 없다');
      expect(rows, isNot(contains('합류 —')), reason: '견본 자료에 합류가 없다');
      expect(rows, contains('시기 구분(학계)'));
      expect(rows, contains('지위 — '));
      expect(rows, contains('조약'));
    });

    test('쓰이지 않은 것은 줄도 묶음도 사라진다', () {
      const bare = LegendFacts(kinds: [LegendKind(kind: 0, name: '국가', hint: '독립 국가·왕조 (기본값) — 보통 띠')], certainty: [1], historicity: [], has: {});
      final boxes = buildLegend(bare);
      final groups = [for (final b in boxes) ...b.groups.map((g) => g.title)];
      expect(groups, isNot(contains(startsWith('실재성'))));
      expect(groups, isNot(contains(startsWith('대범위'))));
      final rows = rowsOf(bare).map((r) => r.text).join('\n');
      expect(rows, contains('통설 연대 — 기본'));
      expect(rows, isNot(contains('추정 연대')));
      expect(rows, isNot(contains('연도 미정')));
      expect(rows, isNot(contains('인물 단')));
      expect(rows, contains('국가 — 보통 띠'), reason: '종류의 뜻은 자료가 준 글의 뒷부분만 쓴다');
    });

    testWidgets('열면 묶음 이름과 견본 그림이 함께 나오고, 닫기 탭으로 닫힌다', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = makeBus();
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1200, height: 800));
      expect(find.text('범례'), findsNothing);

      h.bus.slot(legendSlot).value = true;
      await tester.pumpAndSettle();
      expect(find.text('범례'), findsOneWidget, reason: '폴더 탭의 맨 글');
      expect(find.text('정권 띠'), findsOneWidget);
      expect(find.byType(LegendSample), findsWidgets, reason: '작은 그림은 글자가 아니라 위젯이다');
      expect(h.asked.last['op'], 'legend_kinds');

      await tester.tap(find.bySemanticsLabel('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('범례'), findsNothing);
      expect(h.bus.slot(legendSlot).value, false);

      runCommand(h.bus, Cmd.legend); // ❔ · L
      await tester.pumpAndSettle();
      expect(find.text('범례'), findsOneWidget);
    });

    testWidgets('상세 창이 열려 있으면 폭이 줄고(한 열), 860보다 좁은 창에서는 숨는다', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = makeBus();
      h.bus.slot(legendSlot).value = true;
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1000, height: 800));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SheetFolder)).width, 752, reason: '평소에는 두 열 752px');

      h.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SheetFolder)).width, 384, reason: '1000px 창에서 상세 창이 400을 쓰면 한 열 384px');

      tester.view.physicalSize = const Size(820, 800);
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 820, height: 800));
      await tester.pumpAndSettle();
      expect(find.text('범례'), findsNothing, reason: '상세 창이 열린 860px 아래 창에서는 숨는다');
    });
  });
}
