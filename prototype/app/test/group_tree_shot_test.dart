import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/ruler.dart' show minuteOfYear;
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/group_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'group_tree_test.dart' show makeBus, kap, east, rec, unknownStore;

// 단체 계보 창의 1배 그림 — 웹 창(scripts/group-window-check.mjs가 뜨는 '단체-계보-창-견본-갑왕국-1920-1배.png')과 나란히 놓을 그림.
// 견본 sample-groups의 갑 왕국 나무 · 동쪽 무리를 고른 채 · 보기 747 ~ 987년 · 연표의 이름 칸 폭 240(웹 그림과 같은 자리).
// 사용(app 폴더에서): flutter test --no-pub test/group_tree_shot_test.dart --dart-define=GT_OUT=<그림 폴더>
//   GT_OUT이 없으면 건너뛴다(전체 검사에서는 그리지 않음). 글꼴은 실행본과 같은 내장 프리텐다드 Regular/SemiBold/Bold와 한자 대체 글꼴.
// 그림은 1920×1080 화면에서 창이 차지하는 아래쪽 525px(웹 그림의 y 555 ~ 1080과 같은 자리)만 1920×525로 적는다.
// 법 · 선거 상세는 상세 창 폭(380) 한 장 — 기본 상세가 제자리 셋(법 이름 · 법의 내력 · 결과)을 부른 모습(웹 '법-내력' · '선거-의석-막대' 그림의 오른쪽 창).

const _out = String.fromEnvironment('GT_OUT');

Future<void> _loadFonts() async {
  await loadAppFonts();
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf']),
    ('Malgun Gothic', ['C:/Windows/Fonts/malgun.ttf', 'C:/Windows/Fonts/malgunbd.ttf']),
  ]) {
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
}

void main() {
  // 덧 그림(리메이크 4단계 틀의 시트와 창 걸음 8): 옛 무리 → 남쪽 무리를 '방식 미상'의 안에서 갈라짐으로 고친 나무(unknownStore) —
  // 점 실 · 아랫변 매듭 · 열쇠표를 1배로 보려고(고정 자료에는 그 갈래가 없다). 고른 단체는 남쪽 무리.
  for (final (name, store, pick) in [('갑왕국', null, east), ('갑왕국-방식미상', unknownStore(), 'sample-groups/gr-south')]) {
    testWidgets('단체 계보 창 1배 그림($name)', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bus = makeBus(store: store);
      bus.controller
        ..resize(1920, 1080)
        ..setFrame(240, 74)
        ..showRange(minuteOfYear(747), minuteOfYear(987));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, scaffoldBackgroundColor: Ui.bg),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: SizedBox(width: 1920, height: 1080, child: Stack(children: [Positioned.fill(child: GroupTreeLayer(bus: bus))])),
            ),
          ),
        ),
      );
      openGroupTree(bus, kap, group: pick);
      await tester.pumpAndSettle();
      expect(tester.state<GroupTreeLayerState>(find.byType(GroupTreeLayer)).data!.holder, kap);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawColor(Ui.bg, BlendMode.src)
        ..drawImageRect(image!, const Rect.fromLTWH(0, 1080 - 525, 1920, 525), const Rect.fromLTWH(0, 0, 1920, 525), Paint());
      final cut = await tester.runAsync(() => recorder.endRecording().toImage(1920, 525));
      final png = await tester.runAsync(() => cut!.toByteData(format: ui.ImageByteFormat.png));
      final folder = Directory(_out)..createSync(recursive: true);
      File('${folder.path}/단체-계보-창-앱-$name-1920-1배.png').writeAsBytesSync(png!.buffer.asUint8List());
    }, skip: _out.isEmpty);
  }

  for (final (uid, name) in const [('sample-lens/ln-e-amend', '법-내력-앱'), ('sample-lens/ln-e-vote1', '선거-의석-막대-앱')]) {
    testWidgets('법 · 선거 상세 1배 그림($name)', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(380, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final x = rec(uid);
      void open(String uid, {String kind = '', String? cell}) {}
      final key = GlobalKey();
      final when = (x['start'] as num).toInt();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Ui.bg,
            body: RepaintBoundary(
              key: key,
              child: Container(
                width: 380,
                height: 1000,
                decoration: BoxDecoration(color: Ui.detailGlass, borderRadius: BorderRadius.circular(Ui.detailRadius)),
                // 상세 창 뼈대(DetailShell)의 머리 · 몸통 여백을 그대로 두되 글꼴을 직접 준다 — 뼈대는 DefaultTextStyle을 글꼴 없이 새로 깔아
                // 검사 환경에서는 검사용 글꼴(네모)로 풀리기 때문(앱에서는 시스템 글꼴 — 뼈대의 몫이라 여기서는 그림만 읽히게).
                child: DefaultTextStyle(
                  style: DetailUi.body.copyWith(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(padding: DetailUi.headPad, child: Wrap(spacing: 6, runSpacing: 6, children: detailLensBadges(x))),
                      Padding(
                        padding: DetailUi.bodyPad,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DetailTitle(x['title'] as String),
                            ...detailLensAka(x),
                            ...(detailLawTop(x, open).isNotEmpty ? detailLawTop(x, open) : [DetailWhen('$when년')]),
                            ...detailElectionTop(x, open),
                            const DetailDesc(''),
                            ...detailLensBottom(x, open, topsPlaced: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
      final png = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      final folder = Directory(_out)..createSync(recursive: true);
      File('${folder.path}/$name-380-1배.png').writeAsBytesSync(png!.buffer.asUint8List());
    }, skip: _out.isEmpty);
  }
}
