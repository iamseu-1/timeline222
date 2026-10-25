import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/theme_lens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'theme_lens_test.dart' show fixture, lensBus;

// 렌즈 고르기의 1배 그림 — 웹(scripts/lens-check.mjs가 뜨는 '렌즈-차림표-1920-1배.png' · 1120×600 자르기)과 나란히 놓을 그림.
// 견본 sample-lens의 주제 사전(test/fixtures/lens-lens.json). 독의 '렌즈' 단추와 그 아래 8px의 렌즈 차림표를 그린다
// (앱에서는 차림표가 길라잡이 위 창으로 뜨지만, 그림 한 장에 담으려고 같은 자리에 카드를 바로 놓는다 — 자리 셈은 test/theme_lens_test.dart가 본다).
// 독의 다른 단추(필터 · ⋯ …)는 그리지 않는다 — 단추 하나와 차림표의 꼴 · 글 · 색만 견준다.
// 사용(app 폴더에서): flutter test --no-pub test/theme_lens_shot_test.dart --dart-define=TL_OUT=<그림 폴더>
//   TL_OUT이 없으면 건너뛴다(전체 검사에서는 그리지 않음). 글꼴은 실행본과 같은 내장 프리텐다드 Regular/SemiBold/Bold와 한자 대체 글꼴.

const _out = String.fromEnvironment('TL_OUT');

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
  for (final (lens, name) in const [('', '렌즈-차림표-앱'), ('law', '렌즈-법률-차림표-앱')]) {
    testWidgets('렌즈 단추 · 차림표 1배 그림($name)', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1120, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      final glue = ThemeLensGlue(bus: bus)..start();
      addTearDown(glue.dispose);
      await tester.runAsync(() async => glue.load());
      glue.set(lens);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, scaffoldBackgroundColor: Ui.bg),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 1120,
                height: 600,
                child: Stack(
                  children: [
                    Positioned(left: 12, top: 10, child: LensDockButton(glue: glue)),
                    Positioned(left: 12, top: 10 + Ui.buttonHeight + 8, child: LensMenuCard(glue: glue)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LensMenuCard), findsOneWidget);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
      final png = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      final folder = Directory(_out)..createSync(recursive: true);
      File('${folder.path}/$name-1120-1배.png').writeAsBytesSync(png!.buffer.asUint8List());
    }, skip: _out.isEmpty);
  }
}
