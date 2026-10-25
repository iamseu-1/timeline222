import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/shell/motion_widgets.dart';

void main() {
  tearDown(() => Motion.slow = 1);

  testWidgets('면을 닫다 다시 열면 지금 위치에서 이어지고 퇴장 뒤 입력이 사라진다', (tester) async {
    var open = true;
    late StateSetter change;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return Center(
              child: MotionPresence(
                key: const ValueKey('면'),
                open: open,
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const SizedBox(
                    width: 300,
                    height: 160,
                    child: Text('은빛 강'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    final transforms = find.descendant(
      of: find.byKey(const ValueKey('면')),
      matching: find.byType(Transform),
    );
    double y() =>
        tester.widget<Transform>(transforms.first).transform.getTranslation().y;
    change(() => open = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = y();
    change(() => open = true);
    await tester.pump();
    expect(y(), closeTo(before, .001));
    await tester.pumpAndSettle();
    expect(y(), closeTo(0, .001));
    await tester.tap(find.text('은빛 강'));
    expect(taps, 1);
    change(() => open = false);
    await tester.pumpAndSettle();
    expect(find.text('은빛 강'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('닫혀 있는 면은 내용부터 만들지 않는다', (tester) async {
    var built = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MotionPresence(
          open: false,
          child: Builder(
            builder: (_) {
              built++;
              return const Text('별여울');
            },
          ),
        ),
      ),
    );
    expect(built, 0);
  });

  testWidgets('닫는 순간 면 안의 키보드 초점과 실행도 차단한다', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var open = true;
    var activations = 0;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MotionPresence(
                open: open,
                child: TextButton(
                  focusNode: focus,
                  onPressed: () => activations++,
                  child: const Text('별여울 보기'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 1);

    change(() => open = false);
    await tester.pump();
    expect(find.text('별여울 보기'), findsOneWidget, reason: '내용이 물러나는 도중을 검사한다');
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(focus.hasFocus, isFalse);
    expect(activations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('움직임 줄이기는 면의 이동과 크기를 즉시 정착시킨다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const MotionPresence(
            open: true,
            child: SizedBox(width: 240, height: 100, child: Text('구름 성')),
          ),
        ),
      ),
    );
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    for (final transform in transforms) {
      expect(transform.transform.isIdentity(), isTrue);
    }
    expect(tester.takeException(), isNull);
  });
}
