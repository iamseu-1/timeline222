import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _answer(List<(int, bool, int, int, int, int, double)> list) {
  final b = BytesBuilder()..add('HTGL'.codeUnits);
  final head = ByteData(4)..setUint16(0, 1, Endian.little)..setUint16(2, list.length, Endian.little);
  b.add(head.buffer.asUint8List());
  for (final (rune, ok, left, top, w, h, adv) in list) {
    final d = ByteData(18)
      ..setUint32(0, rune, Endian.little)
      ..setUint8(4, 0)
      ..setUint8(5, ok ? 1 : 0)
      ..setInt16(6, left, Endian.little)
      ..setInt16(8, top, Endian.little)
      ..setUint16(10, w, Endian.little)
      ..setUint16(12, h, Endian.little)
      ..setFloat32(14, adv, Endian.little);
    b.add(d.buffer.asUint8List());
    b.add(Uint8List(w * h * 3)..fillRange(0, w * h * 3, 200));
  }
  return b.toBytes();
}

void main() {
  test('답 바이트를 읽는다', () {
    final g = parseGlyphs(_answer([(0xC784, true, -1, -7, 9, 9, 7.5), (0x0E01, false, 0, 0, 0, 0, 0)]));
    expect(g.length, 2);
    expect(g[0].ok, isTrue);
    expect((g[0].left, g[0].top, g[0].width, g[0].height), (-1, -7, 9, 9));
    expect(g[0].cov.length, 9 * 9 * 3);
    expect(g[1].ok, isFalse);
    expect(g[1].cov, isEmpty);
  });

  test('잘린 답은 FormatException', () {
    final whole = _answer([(0xC784, true, 0, 0, 4, 4, 5)]);
    expect(() => parseGlyphs(Uint8List.sublistView(whole, 0, whole.length - 5)), throwsFormatException);
    expect(() => parseGlyphs(Uint8List.fromList('NOPE0000'.codeUnits)), throwsFormatException);
  });

  test('글꼴 파일: 프리텐다드 400 · 600 · 700만 · 기울임은 없음', () {
    const root = 'assets/fonts';
    expect(sceneFontFile(const TextLook(9, ui.FontWeight.w700, 0xff000000), root: root), endsWith('Pretendard-Bold.otf'));
    expect(sceneFontFile(const TextLook(9, ui.FontWeight.w600, 0xff000000), root: root), endsWith('Pretendard-SemiBold.otf'));
    expect(sceneFontFile(const TextLook(9, ui.FontWeight.w400, 0xff000000), root: root), endsWith('Pretendard-Regular.otf'));
    expect(sceneFontFile(const TextLook(9, ui.FontWeight.w700, 0xff000000, italic: true), root: root), isNull);
    expect(sceneFontFile(const TextLook(9, ui.FontWeight.w700, 0xff000000), root: 'no-such-dir'), isNull);
  });

  test('글꼴 파일: 화면 글꼴이 프리텐다드가 아니면(글꼴 팩) 없음', () {
    const root = 'assets/fonts';
    const look = TextLook(9, ui.FontWeight.w700, 0xff000000);
    // 바뀌기 전에는 같은 글자가 파일을 받는다 — 아래의 null이 화면 글꼴 때문임을 가른다.
    expect(sceneFontFile(look, root: root), isNotNull);
    final original = sceneFamilyNow;
    addTearDown(() => sceneFamilyNow = original);
    sceneFamilyNow = '다른 글꼴';
    expect(sceneFontFile(look, root: root), isNull);
  });

  test('ClearType 정보: 답이 ok일 때만 읽고 · 아니면 꺼짐', () {
    final rgb = ClearTypeInfo.read({'ok': true, 'data': {'on': true, 'bgr': false}});
    expect((rgb.on, rgb.bgr), (true, false));
    final bgr = ClearTypeInfo.read({'ok': true, 'data': {'on': true, 'bgr': true}});
    expect((bgr.on, bgr.bgr), (true, true));
    final failed = ClearTypeInfo.read({'ok': false, 'error': '옛 자료 처리부'});
    expect((failed.on, failed.bgr), (false, false));
    final empty = ClearTypeInfo.read({'ok': true});
    expect((empty.on, empty.bgr), (false, false));
  });

  test('열 수 없는 자료 처리부 · archive_glyphs가 없는 옛 것은 null', () {
    expect(ClearTypeBaker.open('no-such-dir/archive_engine.dll'), isNull);
    // 윈도 자신의 DLL은 열리지만 archive_glyphs가 없다.
    expect(ClearTypeBaker.open('kernel32.dll'), isNull);
  });

  final dll = File('../engine/target/release/archive_engine.dll');
  final skipReal = Platform.isWindows && dll.existsSync() ? false : 'Windows · 자료 처리부 DLL이 있어야 합니다';
  test('진짜 굽기: 임은 색 테두리가 있다', () async {
    final baker = ClearTypeBaker.open(dll.absolute.path)!;
    final g = await baker.bake(File('assets/fonts/Pretendard-Bold.otf').absolute.path, 8.5, ['임'.runes.first, 0x0E01]);
    expect(g[0].ok, isTrue);
    var fringe = false;
    for (var i = 0; i + 2 < g[0].cov.length; i += 3) {
      if ((g[0].cov[i] - g[0].cov[i + 2]).abs() > 30) fringe = true;
    }
    expect(fringe, isTrue);
    expect(g[1].ok, isFalse);
  }, skip: skipReal);

  test('굽지 못하면(없는 글꼴 파일) StateError', () async {
    final baker = ClearTypeBaker.open(dll.absolute.path)!;
    await expectLater(baker.bake('no-such-font.otf', 8.5, [0xC784]), throwsStateError);
  }, skip: skipReal);
}
