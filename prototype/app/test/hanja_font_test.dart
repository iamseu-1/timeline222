import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_app_fonts.dart';

// 글꼴 이름뿐 아니라 배포한 Regular/SemiBold/Bold 파일을 따로 실어 실제 그린 화소를 비교한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    for (final (family, file) in [
      ('PretendardRegularReference', 'Pretendard-Regular.otf'),
      ('PretendardSemiBoldReference', 'Pretendard-SemiBold.otf'),
      ('PretendardBoldReference', 'Pretendard-Bold.otf'),
      ('ChosunReference', 'ChosunKm.ttf'),
    ]) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      await (FontLoader(family)..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();
    }
  });

  Future<List<int>> pixels(String text, String family, List<String> fallback, {FontWeight weight = FontWeight.w400}) async {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: family, fontFamilyFallback: fallback,
        fontSize: 24, fontWeight: weight, color: const ui.Color(0xff000000),
      )),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), ui.Offset(4, 50 - painter.computeDistanceToActualBaseline(ui.TextBaseline.alphabetic)));
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 80);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = bytes!.buffer.asUint8List().toList();
    image.dispose();
    picture.dispose();
    painter.dispose();
    return result;
  }

  test('본문·연표·제목은 프리텐다드이고 제목의 굵기를 유지한다', () {
    expect(sceneFontFamily, 'Pretendard');
    expect(sceneTitleFontFamily, 'Pretendard');
    expect(Ui.serif, 'Pretendard');
    expect(Ui.title, 'Pretendard');
    expect(Ui.titleFallback, sceneFontFallback);
    expect(DetailUi.body.fontWeight, FontWeight.w400);
    expect(DetailTitle.style.fontWeight, FontWeight.w700);
  });

  test('본문과 제목의 한자는 조선굵은명조 보조 글꼴로 그린다', () async {
    // 내장 Pretendard에는 한자가 없어, 같은 한자를 보조 글꼴의 원본 화소와 비교한다.
    const text = '海溫國溫羅海王海谷海氏波泉';
    for (final weight in [FontWeight.w400, FontWeight.w700]) {
      final actual = await pixels(text, sceneFontFamily, sceneFontFallback, weight: weight);
      expect(actual, await pixels(text, 'ChosunReference', const [], weight: weight));
      expect(actual.any((v) => v != 0), true);
    }
  });

  test('한글과 로마자는 프리텐다드 Regular 원본의 글자를 쓴다', () async {
    const text = '해온국 Haeon-guk';
    final actual = await pixels(text, sceneFontFamily, sceneFontFallback);
    expect(actual, await pixels(text, 'PretendardRegularReference', const []));
    expect(actual.any((v) => v != 0), true);
  });

  test('중간 굵기는 프리텐다드 SemiBold 원본의 글자를 쓴다', () async {
    const text = '해온국 Haeon-guk';
    final actual = await pixels(text, sceneFontFamily, sceneFontFallback, weight: FontWeight.w600);
    expect(actual, await pixels(text, 'PretendardSemiBoldReference', const [], weight: FontWeight.w600));
    expect(actual, isNot(await pixels(text, 'PretendardRegularReference', const [])));
  });

  test('제목은 프리텐다드 Bold 원본의 글자를 쓴다', () async {
    const text = '해온국 Haeon-guk';
    final actual = await pixels(text, sceneTitleFontFamily, Ui.titleFallback, weight: FontWeight.w700);
    expect(actual, await pixels(text, 'PretendardBoldReference', const [], weight: FontWeight.w700));
    expect(actual, isNot(await pixels(text, 'PretendardRegularReference', const [])));
  });
}
