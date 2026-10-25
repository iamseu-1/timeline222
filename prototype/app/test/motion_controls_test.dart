import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/shell/motion_controls.dart';
import 'package:archive_prototype/shell/range_roll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget frame(Widget child, {double width = 600, bool reduce = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

void main() {
  tearDown(() => Motion.slow = 1);

  testWidgets('토글은 42×24이며 움직이는 도중 반대로 골라도 그 자리에서 이어간다', (tester) async {
    final on = ValueNotifier(false);
    addTearDown(on.dispose);
    await tester.pumpWidget(
      frame(
        ValueListenableBuilder<bool>(
          valueListenable: on,
          builder: (context, value, _) => Align(
            alignment: Alignment.topLeft,
            child: MotionToggle(value: value, onChanged: (v) => on.value = v),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MotionToggle)), const Size(42, 24));
    double x() => tester
        .widget<Transform>(find.byKey(const ValueKey('motion-toggle-knob')))
        .transform
        .storage[12];
    on.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final before = x();
    expect(before, greaterThan(0));
    expect(before, lessThan(18));
    on.value = false;
    await tester.pump();
    expect(x(), closeTo(before, .001), reason: '새 목표를 적는 순간 위치를 초기화하지 않는다');
    await tester.pumpAndSettle();
    expect(x(), closeTo(0, .01));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('칩 채움은 안에서 자라고 빠른 재선택에서도 사라졌다 새로 생기지 않는다', (tester) async {
    final on = ValueNotifier(false);
    addTearDown(on.dispose);
    await tester.pumpWidget(
      frame(
        ValueListenableBuilder<bool>(
          valueListenable: on,
          builder: (context, value, _) => Align(
            alignment: Alignment.topLeft,
            child: MotionChip(
              label: '별바람',
              value: value,
              onTap: () => on.value = !on.value,
            ),
          ),
        ),
      ),
    );
    double scale() => tester
        .widget<Transform>(find.byKey(const ValueKey('motion-chip-fill')))
        .transform
        .storage[0];
    expect(scale(), .7);
    await tester.tap(find.text('별바람'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final before = scale();
    expect(before, greaterThan(.7));
    expect(before, lessThan(1));
    on.value = false;
    await tester.pump();
    expect(scale(), closeTo(before, .001));
    await tester.pumpAndSettle();
    expect(scale(), closeTo(.7, .001));
    expect(
      tester.getSize(find.byType(MotionChip)).width,
      lessThan(150),
      reason: '글만큼만 차지하며 줄을 늘이지 않는다',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('세그먼트는 표시만 옮기고 글자 자리는 지키며 키보드로도 고른다', (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      frame(
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, _) => MotionSegmented<int>(
            value: value,
            options: const [
              MotionChoice(0, '성긴'),
              MotionChoice(1, '기본'),
              MotionChoice(2, '촘촘'),
            ],
            onChanged: (v) => selected.value = v,
            label: '줄 높이',
          ),
        ),
      ),
    );
    final before = tester.getCenter(find.text('촘촘'));
    await tester.tap(find.text('촘촘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getCenter(find.text('촘촘')), before);
    final position = tester
        .widget<Positioned>(
          find.byKey(const ValueKey('motion-segment-indicator')),
        )
        .left!;
    expect(position, greaterThan(0));
    expect(position, lessThan(112));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected.value, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('중요도를 빠르게 내리면 올라가던 단계의 예약도 취소한다', (tester) async {
    final selected = ValueNotifier(1);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      frame(
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, _) => MotionSteps(
            value: value,
            onChanged: (v) => selected.value = v,
            labels: const ['모두', '보통 이상', '중요만'],
          ),
        ),
      ),
    );
    selected.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    selected.value = 1;
    await tester.pump();
    await tester.pumpAndSettle();
    final scales = tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(MotionSteps),
            matching: find.byType(Transform),
          ),
        )
        .map((t) => t.transform.storage[5])
        .toList();
    expect(scales, [1.0, 0.0, 0.0]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('움직임을 줄이면 손잡이는 바로 도착하고 켬끔의 의미는 그대로다', (tester) async {
    bool selected = false;
    late StateSetter change;
    await tester.pumpWidget(
      frame(
        StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return MotionToggle(
              value: selected,
              onChanged: (_) {},
              label: '눈금선',
            );
          },
        ),
        reduce: true,
      ),
    );
    change(() => selected = true);
    await tester.pump();
    final knob = tester.widget<Transform>(
      find.byKey(const ValueKey('motion-toggle-knob')),
    );
    expect(knob.transform.storage[12], 18);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('시기 글은 기원전/자릿수/월일시 전환과 빠른 재입력 때도 주어진 칸 안에서 그린다', (tester) async {
    final label = ValueNotifier('기원전 2345년 ~ 기원전 3년');
    addTearDown(label.dispose);
    await tester.pumpWidget(
      frame(
        ValueListenableBuilder<String>(
          valueListenable: label,
          builder: (context, value, _) => RangeRoll(label: value),
        ),
        width: 180,
      ),
    );
    expect(tester.getSize(find.byType(RangeRoll)), const Size(180, 34));
    for (final value in [
      '9년 ~ 10년',
      '100년 12월 31일 23시 ~ 101년 1월 1일 1시',
      '기원전 1년 ~ 1년',
    ]) {
      label.value = value;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == value,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
