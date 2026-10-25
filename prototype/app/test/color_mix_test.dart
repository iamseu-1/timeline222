import 'package:archive_prototype/scene/color_mix.dart';
import 'package:flutter_test/flutter_test.dart';

// 기대값은 기준 덤프(scripts/dump-dom.mjs — 지금 연표를 브라우저가 실제로 그린 색)에서 읽었다.
void main() {
  const paper = 0xfffbf7ef, ink = 0xff2e2820, track = 0xffa0bcc5; // 종이 · 글자 · 월흔해 첫 트랙의 색
  void near(int actual, int expected) {
    for (final shift in [24, 16, 8, 0]) {
      expect(((actual >> shift) & 0xff) - ((expected >> shift) & 0xff), inInclusiveRange(-1, 1), reason: '${actual.toRadixString(16)} ↔ ${expected.toRadixString(16)}');
    }
  }

  test('srgb 섞기: 시대 구분 칸의 바탕(제 색 22% + 종이)과 글자(제 색 40% + 글자색)', () {
    near(mixSrgb(track, paper, .22), 0xffe7eae6);
    near(mixSrgb(track, ink, .40), 0xff5c6362);
    near(mixSrgb(0xffbba395, paper, .22), 0xffede5db);
  });

  test('oklab 섞기: 테두리(제 색 84% + 글자색)', () {
    near(mixOklab(track, ink, .84), 0xff8da2a8);
    near(mixOklab(0xffbba395, ink, .84), 0xffa28e81);
    near(mixOklab(0xff9dbea8, ink, .84), 0xff8aa490);
    near(mixOklab(0xffd7c18e, ink, .84), 0xffb9a67b);
  });

  test('투명과 섞으면 색은 그대로이고 투명도만 준다', () {
    expect(mixSrgb(0xffebe2d2, 0x00000000, .7), 0xb3ebe2d2);
    expect(withAlpha(0xffc27a45, .55), 0x8cc27a45);
  });

  test('반투명을 불투명 바탕에 얹는다', () {
    expect(over(0x80ffffff, 0xff000000), 0xff808080);
  });
}
