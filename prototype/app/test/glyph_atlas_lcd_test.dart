import 'load_app_fonts.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

/// 가짜 굽개: 글자마다 6×9 덮임(가운데 열만 진함). [missing]에 든 글자는 ok 거짓.
class FakeBaker implements GlyphBaker {
  FakeBaker({this.missing = const {}, this.blank = const {}});
  final Set<int> missing;

  /// 잉크 없는 글자 — 엔진처럼 ok이고 너비 0으로 답한다.
  final Set<int> blank;
  int calls = 0;

  /// 부를 때마다 청한 글자 수.
  final asked = <int>[];
  @override
  Future<List<LcdGlyph>> bake(String font, double sizePx, List<int> runes) async {
    calls++;
    asked.add(runes.length);
    return [
      for (final r in runes)
        missing.contains(r)
            ? LcdGlyph(r, false, 0, 0, 0, 0, 0, Uint8List(0))
            : blank.contains(r)
                ? LcdGlyph(r, true, 0, 0, 0, 0, 6, Uint8List(0))
                : LcdGlyph(r, true, 0, -8, 6, 9, 6, Uint8List.fromList(List.generate(6 * 9 * 3, (i) => (i ~/ 3) % 6 == 2 ? 255 : 0))),
    ];
  }
}

/// 넓은 가짜 굽개: 글자마다 22×9 덮임(왼쪽으로 6px 삐침 · 덮임 128 고르게) — 9px 글자 사이에서 이웃은 물론 하나 건너 글자와도 겹친다.
class WideBaker implements GlyphBaker {
  @override
  Future<List<LcdGlyph>> bake(String font, double sizePx, List<int> runes) async =>
      [for (final r in runes) LcdGlyph(r, true, -6, -8, 22, 9, 22, Uint8List(22 * 9 * 3)..fillRange(0, 22 * 9 * 3, 128))];
}

const look = TextLook(9, ui.FontWeight.w700, 0xff111111);

Future<void> settle(AtlasText t, String s, {double x = 10.4, double y = 20.3, double alpha = 1, TextLook l = look}) async {
  for (var i = 0; i < 6; i++) {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    t.beginFrame();
    t.paint(c, s, l, x, y, alpha: alpha);
    t.flush(c);
    rec.endRecording().dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late AtlasText t;
  late FakeBaker baker;
  setUp(() {
    baker = FakeBaker(missing: {0x4E00});
    t = AtlasText(baker: baker, fontFileOf: (_) => 'fake.otf');
  });

  testWidgets('허락이 없으면 굽지도 찍지도 않는다', (tester) async {
    await tester.runAsync(() => settle(t, '조선'));
    expect(baker.calls, 0);
    expect(t.lcdSprites, 0);
  });

  testWidgets('허락하면 구운 뒤 ClearType으로 찍는다', (tester) async {
    t.lcdAllowed = true;
    await tester.runAsync(() => settle(t, '조선'));
    expect(baker.calls, greaterThan(0));
    expect(t.lcdSprites, 2);
    expect(t.lcdPending, 0);
  });

  testWidgets('자리가 같다 — 회색과 ClearType의 펜 · 바탕선(검토 초점 1)', (tester) async {
    await tester.runAsync(() async {
      await settle(t, '조선', x: 10.4, y: 20.3);
      final gray = List.of(t.debugLastPens); // 회색으로 찍은 글자마다 (펜 x 화면 px, 바탕선 y 화면 px) — beginFrame이 비우므로 떠 둔다
      expect(gray.length, 2);
      t.lcdAllowed = true;
      await settle(t, '조선', x: 10.4, y: 20.3);
      expect(t.lcdSprites, 2);
      expect(t.debugLastPens, gray);
      // 바탕선은 화면 화소 줄에(정수)
      for (final (_, base) in gray) {
        expect(base, base.roundToDouble());
      }
    });
  });

  testWidgets('글꼴에 없는 글자가 섞인 글줄은 통째로 회색(검토 초점 3)', (tester) async {
    t.lcdAllowed = true;
    await tester.runAsync(() => settle(t, '조一'));
    expect(t.lcdSprites, 0);
    expect(t.debugLastPens.length, 2); // 글자는 빠지지 않는다
  });

  testWidgets('잉크 없는 글자(NBSP · 전각 빈칸 · 폭 없는 빈칸)가 든 글줄은 ClearType — 그 글자만 회색 조각(빈 그림)으로 지나간다', (tester) async {
    final spaced = AtlasText(baker: FakeBaker(blank: {0xA0, 0x3000, 0x200B}), fontFileOf: (_) => 'fake.otf')..lcdAllowed = true;
    await tester.runAsync(() => settle(spaced, '조 선　한​국'));
    expect(spaced.lcdSprites, 4, reason: '조 · 선 · 한 · 국은 ClearType');
    expect(spaced.lcdPending, 0);
    spaced.dispose();
  });

  testWidgets('글자가 많은 묶음은 나눠 청한다 — 엔진의 요청 크기 상한을 넘어 묶음 전체가 회색으로 굳지 않게', (tester) async {
    final many = FakeBaker();
    final text = AtlasText(baker: many, fontFileOf: (_) => 'fake.otf')
      ..lcdAllowed = true
      ..budgetMicros = 1 << 40
      ..maxNewPerFrame = 10000;
    final line = String.fromCharCodes([for (var i = 0; i < AtlasText.bakeChunk + 4; i++) 0xAC00 + i]); // 서로 다른 한글 4100자
    await tester.runAsync(() => settle(text, line, x: 0));
    expect(many.asked, [AtlasText.bakeChunk, 4], reason: '한 묶음(같은 글꼴 파일 · 크기)을 4096자씩');
    expect(text.lcdSprites, AtlasText.bakeChunk + 4, reason: '나눠 구운 글자가 한 글줄에 모두 ClearType');
    text.dispose();
  });

  testWidgets('옅어지는 이름 · 반투명 색은 회색(검토 초점 4)', (tester) async {
    t.lcdAllowed = true;
    await tester.runAsync(() => settle(t, '조선', alpha: .5));
    expect(t.lcdSprites, 0);
    await tester.runAsync(() => settle(t, '조선', l: const TextLook(9, ui.FontWeight.w700, 0x80111111)));
    expect(t.lcdSprites, 0);
  });

  testWidgets('굽개가 없으면 늘 회색', (tester) async {
    final plain = AtlasText(fontFileOf: (_) => 'fake.otf')..lcdAllowed = true;
    await tester.runAsync(() => settle(plain, '조선'));
    expect(plain.lcdSprites, 0);
  });

  testWidgets('두 번 섞기 — 흰 바탕에서 덮인 칸은 글자 색 · 나머지는 바탕 그대로, 한 장면에 청한 두 글줄 모두 찍힌다', (tester) async {
    t.lcdAllowed = true;
    await tester.runAsync(() async {
      // 한 장면에 두 글줄 — 두 글줄의 글자가 모두 그림에 들어 찍혀야 한다(그림에 없는 채 찍히면 흰 바탕 그대로 — 글자가 빠진다).
      // 그림을 뜨는 사이에 다른 묶음의 글자가 장에 드는 길은 아래 '(글꼴 파일, 화면 크기)마다 한 번' 검사(두 묶음)가 지난다.
      ui.Image? shot;
      for (var i = 0; i < 6; i++) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec)..drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint()..color = const ui.Color(0xffffffff));
        t.beginFrame();
        t.paint(c, '조선', look, 10.4, 20.3);
        t.paint(c, '한국', look, 10.4, 40.3);
        t.flush(c);
        final picture = rec.endRecording();
        shot?.dispose();
        shot = picture.toImageSync(64, 64);
        picture.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(t.lcdSprites, 4);
      final px = (await shot!.toByteData())!;
      shot.dispose();
      int at(double x, double y) => px.getUint32((y.toInt() * 64 + x.toInt()) * 4); // 0xRRGGBBAA
      expect(t.debugLastPens.length, 4);
      for (final (pen, base) in t.debugLastPens) {
        expect(at(pen + 2, base - 4), 0x111111ff, reason: '덮인 칸 ($pen, $base)'); // 바탕 × 0 + 글자 색 × 1
        expect(at(pen + 1, base - 4), 0xffffffff, reason: '덮이지 않은 칸 ($pen, $base)'); // 바탕 × 1 + 0
      }
    });
  });

  testWidgets('돋보기 배율을 여러 번 바꿔 멈춰도 ClearType 장이 쌓이지 않는다: 지금 · 직전 · 100%의 것만 남긴다', (tester) async {
    // 장 하나가 바이트 8MB에 그림 8MB — 버리지 않으면 멈춘 배율마다 글자 한 벌이 장에 쌓여 돌아오지 않는다.
    const sample = '가나다라마바사아자차카타파하거너더러머버'; // 6×9 글자 스물 — 64² 장 하나에 든다(장 하나에 54자)
    AtlasText make() => AtlasText(pageSize: 64, baker: FakeBaker(), fontFileOf: (_) => 'fake.otf')
      ..budgetMicros = 1 << 40
      ..maxNewPerFrame = 1000
      ..lcdAllowed = true;
    await tester.runAsync(() async {
      Future<void> rest(AtlasText text, double scale) async {
        text.setScale(scale);
        await settle(text, sample, x: 0, y: 0);
      }

      final text = make();
      for (final scale in [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0]) {
        await rest(text, scale);
      }
      expect(text.lcdSprites, 20, reason: '지금 배율에서 모두 ClearType');
      final fresh = make(); // 100% · 직전 · 지금만 거친 것과 같아야 한다
      for (final scale in [1.0, 2.75, 3.0]) {
        await rest(fresh, scale);
      }
      expect(text.lcdPageCount, fresh.lcdPageCount);
      expect(text.lcdPageCount, 3, reason: '남긴 배율마다 장 하나');
      text.dispose();
      fresh.dispose();
    });
  });

  testWidgets('다른 글줄의 새 글자를 굽고 장을 다시 뜨는 동안에도 이미 ClearType인 글줄은 회색으로 돌아가지 않는다', (tester) async {
    t.lcdAllowed = true;
    await tester.runAsync(() async {
      await settle(t, '조선');
      expect(t.lcdSprites, 2);
      void frame() {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        t.beginFrame();
        t.paint(c, '조선', look, 10.4, 20.3);
        t.paint(c, '한국', look, 10.4, 40.3);
        t.flush(c);
        rec.endRecording().dispose();
      }

      // 마이크로태스크만 돌린다: 가짜 굽개는 그 안에 끝나 '한국'이 '조선'과 같은 장에 들고 장을 다시 뜨기 시작하지만,
      // 그림은 다 떠지지 않는다 — 그 사이의 장면에도 '조선'은 ClearType(앞 세대의 그림으로)이어야 한다.
      for (var i = 0; i < 4; i++) {
        frame();
        expect(t.lcdSprites, 2, reason: '$i번째 장면: 조선은 ClearType · 한국은 아직 회색');
        for (var j = 0; j < 5; j++) {
          await Future<void>.value();
        }
      }
      expect(baker.calls, 2, reason: '한국도 구웠다');
      expect(t.lcdPending, 0, reason: '굽기는 끝났고 장을 뜨는 중이었다');
      for (var i = 0; i < 4; i++) {
        frame();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      frame();
      expect(t.lcdSprites, 4);
    });
  });

  testWidgets('한 장면에 새 글자가 든 글줄 여럿 · 층 여럿이어도 굽기는 (글꼴 파일, 화면 크기)마다 한 번', (tester) async {
    t
      ..lcdAllowed = true
      ..budgetMicros = 1 << 40
      ..maxNewPerFrame = 1000;
    const small = TextLook(11, ui.FontWeight.w700, 0xff111111);
    const thin = TextLook(9, ui.FontWeight.w400, 0xff111111); // look과 글꼴 파일(가짜) · 크기가 같다 — 한 묶음
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        t.beginFrame();
        t.paint(c, '조선', look, 10, 20);
        t.paint(c, '한국', look, 10, 40);
        t.flush(c); // 층의 끝
        t.paint(c, '나라', look, 10, 60);
        t.paint(c, '가나', small, 10, 80);
        t.paint(c, '조국', thin, 10, 100);
        t.flush(c);
        rec.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(baker.calls, 2, reason: '9px · 11px 두 묶음');
      expect(t.lcdSprites, 10, reason: '모두 ClearType');
    });
  });

  // Impeller는 곱하기를 drawRawAtlas 한 번의 조각들을 한 층에 겹쳐 그린 뒤 섞는다 — 한 묶음 안에서 조각이 겹치면 뒤 조각의 흰 여백이
  // 앞 글자를 지운다(과제 6 보고 걱정 1). CPU 검사는 그 섞기를 흉내 내지 못하므로 '묶음 안에서는 겹치지 않는다'를 불변식으로 본다.
  testWidgets('ClearType 조각은 화면 자리가 겹치지 않는 묶음으로 나뉜다 — 이웃 · 하나 건너 글자 · 다른 글줄끼리', (tester) async {
    final wide = AtlasText(baker: WideBaker(), fontFileOf: (_) => 'fake.otf')
      ..lcdAllowed = true
      ..budgetMicros = 1 << 40
      ..maxNewPerFrame = 1000;
    await tester.runAsync(() async {
      for (var i = 0; i < 8; i++) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        wide.beginFrame();
        wide.paint(c, '가나다라마바', look, 10.4, 20.3);
        wide.paint(c, '사아자 차카', look, 14, 24); // 위 글줄과 위아래 · 좌우로 겹친다
        wide.flush(c);
        rec.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(wide.lcdSprites, 11);
    final batches = wide.debugLcdBatches;
    expect(batches.fold<int>(0, (n, b) => n + b.length), 11, reason: '조각이 빠지거나 겹쳐 들지 않는다');
    expect(batches.length, greaterThanOrEqualTo(3), reason: '하나 건너 글자와도 겹치니 홀짝 둘로는 모자란다');
    for (final (b, list) in batches.indexed) {
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final (ax0, ay0, ax1, ay1) = list[i];
          final (bx0, by0, bx1, by1) = list[j];
          expect(ax0 < bx1 && bx0 < ax1 && ay0 < by1 && by0 < ay1, isFalse, reason: '묶음 $b 안의 ${list[i]} · ${list[j]}');
        }
      }
    }
    wide.dispose();
  });

  testWidgets('겹친 자리에는 두 글자의 곱하기 · 더하기가 모두 걸린다(묶음으로 나눠도 CPU의 값은 그대로)', (tester) async {
    final wide = AtlasText(baker: WideBaker(), fontFileOf: (_) => 'fake.otf')
      ..lcdAllowed = true
      ..budgetMicros = 1 << 40
      ..maxNewPerFrame = 1000;
    await tester.runAsync(() async {
      ui.Image? shot;
      for (var i = 0; i < 8; i++) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec)..drawRect(const ui.Rect.fromLTWH(0, 0, 64, 32), ui.Paint()..color = const ui.Color(0xffffffff));
        wide.beginFrame();
        wide.paint(c, '가나', const TextLook(9, ui.FontWeight.w700, 0xff000000), 10, 10);
        wide.flush(c);
        final picture = rec.endRecording();
        shot?.dispose();
        shot = picture.toImageSync(64, 32);
        picture.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(wide.lcdSprites, 2);
      final (pen0, base) = wide.debugLastPens[0];
      final (pen1, _) = wide.debugLastPens[1];
      final px = (await shot!.toByteData())!;
      shot.dispose();
      int red(double x, double y) => px.getUint8((y.toInt() * 64 + x.toInt()) * 4);
      // 두 조각 [pen − 6, pen + 16)이 함께 덮는 칸: 흰 바탕 × (1 − ½) × (1 − ½) + 검정 × … = 64, 한 조각만 덮는 칸: 255 × ½ = 128(반올림 ±1)
      expect(red(pen1 - 6 + 1, base - 4), inInclusiveRange(63, 65), reason: '겹친 칸');
      expect(red(pen0 - 6 + 1, base - 4), inInclusiveRange(127, 129), reason: '한 조각만 덮은 칸');
      expect(wide.debugLcdBatches.length, 2);
    });
    wide.dispose();
  });

  testWidgets('회색 글자의 잉크 바탕선도 그 바탕선 줄에 놓인다 — 반 화소 번지지 않게(검토 초점 1)', (tester) async {
    await tester.runAsync(() async {
      await loadAppFonts(); // 프리텐다드의 바탕선(9px에서 8.6px)은 정수가 아니다 — 검사 글꼴로는 이 어긋남이 드러나지 않는다
      final gray = AtlasText()..budgetMicros = 1 << 40;
      for (final y in [20.3, 20.6, 21.5]) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        gray.beginFrame();
        expect(gray.paint(c, 'H', look, 10.4, y), isTrue);
        final (_, base) = gray.debugLastPens.single;
        gray.flush(c);
        final image = rec.endRecording().toImageSync(48, 48);
        final px = (await image.toByteData())!;
        image.dispose();
        var bottom = -1;
        for (var row = 0; row < 48; row++) {
          for (var col = 0; col < 48; col++) {
            if (px.getUint8((row * 48 + col) * 4 + 3) > 0) bottom = row;
          }
        }
        // H의 아랫변은 바탕선에 닿는다: 맨 아래 잉크 줄 바로 밑이 바탕선. 반 화소 어긋나 찍으면 한 줄 아래까지 옅게 번진다.
        expect(bottom + 1, base, reason: 'y $y');
      }
      gray.dispose();
    });
  });
}
