import 'dart:ui' as ui;

import 'package:archive_prototype/scene/lens_titles.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

// 관점(lens — 나라마다 제 이름)의 이름표. 자료에는 닿지 않고 화면에 적는 글만 갈린다(명세 06의 8-15).
// 사건 이름을 실제로 갈아 끼우는 길은 `label_batch.dart`가 쓰고, 여기서는 담는 그릇의 약속만 본다.

void main() {
  test('빈 관점은 아무 이름도 주지 않는다', () {
    final scene = Object();
    final lens = LensTitles.of(scene);
    expect(identical(LensTitles.of(scene), lens), isTrue, reason: '장면마다 하나');
    expect(lens.isEmpty, isTrue);
    expect(lens.titleOf(7), isNull);
    expect(lens.bandTitleOf(3), isNull);
    expect(lens.version, 0);
  });

  test('답을 갈아 끼우면 이름이 바뀌고 판 번호가 오른다', () {
    final lens = LensTitles.of(Object());
    lens.put(events: {7: '해솔에서 부르는 이름'}, bands: {3: '해솔에서 부르는 나라'});
    expect(lens.titleOf(7), '해솔에서 부르는 이름');
    expect(lens.bandTitleOf(3), '해솔에서 부르는 나라');
    expect(lens.titleOf(8), isNull, reason: '답에 없는 사건은 자료의 이름 그대로');
    expect(lens.version, 1);
    // 같은 답이면 번호를 올리지 않는다(장면을 괜히 다시 그리지 않게).
    lens.put(events: {7: '해솔에서 부르는 이름'}, bands: {3: '해솔에서 부르는 나라'});
    expect(lens.version, 1);
    lens.put(events: {7: '달마루에서 부르는 이름'});
    expect(lens.version, 2);
    expect(lens.bandTitleOf(3), isNull, reason: '띠 이름을 주지 않으면 비운다');
    lens.clear();
    expect(lens.isEmpty, isTrue);
    expect(lens.version, 3);
  });

  test('이름의 폭은 사건 · 글자 모양마다 한 번만 재고 판이 바뀌면 버린다', () {
    final lens = LensTitles.of(Object())..put(events: {7: '해솔의 이름'});
    var asked = 0;
    double measure(String text, TextLook look) {
      asked++;
      return text.length * look.size;
    }

    const look = TextLook(11.5, ui.FontWeight.w400, 0xff000000);
    const other = TextLook(12, ui.FontWeight.w700, 0xff000000);
    expect(lens.widthOf(7, '해솔의 이름', look, measure), closeTo(6 * 11.5, .001));
    expect(lens.widthOf(7, '해솔의 이름', look, measure), closeTo(6 * 11.5, .001));
    expect(asked, 1, reason: '같은 사건 · 같은 글자 모양이면 다시 재지 않는다');
    expect(lens.widthOf(7, '해솔의 이름', other, measure), closeTo(6 * 12, .001));
    expect(asked, 2, reason: '글자 모양이 다르면 다시 잰다');
    // 폭을 아직 모르면(NaN) 걸어 두지 않는다 — 글자가 올라온 다음 판에서 다시 잰다.
    final unknown = LensTitles.of(Object())..put(events: {7: '해솔의 이름'});
    var tries = 0;
    double later(String text, TextLook look) {
      tries++;
      return tries == 1 ? double.nan : 42;
    }

    expect(unknown.widthOf(7, '해솔의 이름', look, later).isNaN, isTrue);
    expect(unknown.widthOf(7, '해솔의 이름', look, later), 42);
    // 판이 바뀌면 걸어 둔 폭을 버린다.
    lens.put(events: {7: '달마루의 이름'});
    expect(lens.widthOf(7, '달마루의 이름', look, measure), closeTo('달마루의 이름'.length * 11.5, .001));
    expect(asked, 3);
  });
}
