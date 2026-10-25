import 'package:archive_prototype/pack_panel.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 옛 이름(`PackPanel`)의 얇은 껍데기 — 알맹이와 그 규칙은 `dlc_manager_test.dart`가 굳힌다.
// 여기서는 옛 이름으로 띄워도 DLC 관리의 알맹이가 그대로 서는지, 그리고 **마지막 하나도 꺼지는지**만 본다.
void main() {
  /// 작은 자리(옛 창의 폭)에 그대로 띄운다.
  Future<void> pumpPanel(WidgetTester tester, TimelineScene scene, {void Function(Set<int> packs)? onChanged}) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 640, child: PackPanel(scene: scene, onChanged: onChanged)))));
  }

  testWidgets('옛 이름으로 띄워도 DLC 목록이 그대로 선다', (tester) async {
    final (scene, _, _) = makePackScene();
    await pumpPanel(tester, scene);
    expect(find.text('DLC'), findsOneWidget, reason: '화면에 보이는 말은 DLC다');
    expect(find.text('별여울 기록집'), findsWidgets);
    expect(find.byType(DlcSwitch), findsNWidgets(4));
  });

  testWidgets('마지막 남은 DLC도 끌 수 있다(2단계의 막음을 걷어냈다)', (tester) async {
    final (scene, _, _) = makePackScene();
    scene.setPacks({3});
    final calls = <Set<int>>[];
    await pumpPanel(tester, scene, onChanged: calls.add);
    await tester.ensureVisible(find.byType(DlcSwitch).at(2));
    await tester.pump();
    await tester.tap(find.byType(DlcSwitch).at(2));
    await tester.pump();
    expect(scene.layout.enabledPacks, isEmpty);
    expect(calls, [<int>{}]);
    expect(dlcTimelineEmpty(scene.layout), isTrue);
  });
}
