import 'dart:ui' as ui;

import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/paint/grounds.dart';
import 'package:archive_prototype/ui/export_svg.dart' show SvgQuads;
import 'package:flutter_test/flutter_test.dart';

// 그 자리의 바탕색(scene/paint/grounds.dart — 리메이크 4단계 세로줄 얹기 걸음 2): 바탕 종이를 까는 층이 칸을 등록하고, 그 위에 반투명 칠을 얹는 층이 묻는다.
// 나중 칸이 위 · 칸 밖은 바탕 · 가로로 선형인 칸 · 섞은 색이 알파 합성과 ±1 · 종이와 칠이 등록 칸 경계에서 나뉨 · 메움 타일의 자르기.

const ground = 0xfff0f0f0;

/// 알파 합성(float)으로 셈한 불투명 색 — [over]가 이것과 ±1이어야 한다.
int composite(int top, int bottom) {
  final a = ((top >> 24) & 0xff) / 255;
  int ch(int s) => (((top >> s) & 0xff) * a + ((bottom >> s) & 0xff) * (1 - a)).round();
  return 0xff000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
}

/// 두 색이 채널마다 ±[tol] 안인가.
Matcher near(int want, {int tol = 1}) => predicate<int>((got) {
  for (final s in [24, 16, 8, 0]) {
    if ((((got >> s) & 0xff) - ((want >> s) & 0xff)).abs() > tol) return false;
  }
  return true;
}, '0x${want.toRadixString(16)} ±$tol');

/// 묶음에 담긴 네모(왼 · 위 · 오른 · 아래 · 왼쪽 위 색 · 오른쪽 위 색).
List<(double, double, double, double, int, int)> rects(SvgQuads q) => [
  for (int i = 0; i < q.count; i++) (q.left(i), q.top(i), q.right(i), q.bottom(i), q.cornerAt(i, 0), q.cornerAt(i, 1)),
];

void main() {
  test('칸이 없으면 바탕 · 나중에 등록한 칸이 위 · 칸의 경계는 왼 · 위 포함 오른 · 아래 뺌', () {
    final g = Grounds()..reset(ground);
    expect(g.base, ground);
    expect(g.at(10, 10), ground);
    g.add(0, 0, 100, 100, 0xffaa0000);
    g.add(50, 50, 150, 150, 0xff00bb00);
    expect(g.at(10, 10), 0xffaa0000);
    expect(g.at(60, 60), 0xff00bb00, reason: '겹친 자리는 나중 칸');
    expect(g.at(120, 120), 0xff00bb00);
    expect(g.at(0, 0), 0xffaa0000, reason: '왼 · 위 끝은 든다');
    expect(g.at(150, 100), ground, reason: '오른 끝은 들지 않는다');
    expect(g.at(100, 20), ground);
    g.reset(0xffffffff);
    expect((g.length, g.at(10, 10)), (0, 0xffffffff), reason: '장면마다 비운다');
  });

  test('가로로 선형인 칸 — 옅어지는 끝(왼쪽 색 → 오른쪽 색)', () {
    final g = Grounds()..reset(ground);
    g.add(0, 0, 100, 10, 0xff000000, 0xffffffff);
    expect(g.at(0, 5), 0xff000000);
    expect(g.at(50, 5), near(0xff808080));
    expect(g.at(99.9, 5), near(0xffffffff));
  });

  test('섞은 색은 알파 합성과 ±1 — 불투명 색은 그대로', () {
    final g = Grounds()..reset(ground);
    for (final color in [0xffd4a39b, 0xffacb4ca, 0xffa0bcc5, 0xff8b6f47]) {
      for (final a in [.09, .09 * .45, .58, .2]) {
        final top = withAlpha(color, a);
        expect(g.over(top, 5, 5), near(composite(top, ground)), reason: '바탕 위 ${color.toRadixString(16)} × $a');
      }
    }
    // 판(9%) 위의 그릇(9%) — 두 번 얹은 것과 같다.
    final board = withAlpha(0xffd4a39b, .09), folder = withAlpha(0xffacb4ca, .09);
    g.tint(0, 0, 200, 200, board);
    expect(g.at(10, 10), near(composite(board, ground)));
    expect(g.over(folder, 10, 10), near(composite(folder, composite(board, ground))));
    expect(g.over(0xff123456, 10, 10), 0xff123456);
  });

  test('종이는 등록 칸 경계에서 나눠 깐다 — 가로 · 세로', () {
    final g = Grounds()..reset(ground);
    g.add(40, 0, 60, 100, 0xffaa0000);
    final q = SvgQuads();
    g.paper(q, 0, 10, 100, 20);
    expect(rects(q), [(0.0, 10.0, 40.0, 20.0, ground, ground), (40.0, 10.0, 60.0, 20.0, 0xffaa0000, 0xffaa0000), (60.0, 10.0, 100.0, 20.0, ground, ground)]);
    // 세로로 걸친 칸: 칸 위 · 칸 · 칸 아래.
    final g2 = Grounds()..reset(ground)..add(0, 5, 100, 15, 0xff00bb00);
    final q2 = SvgQuads();
    g2.paper(q2, 10, 0, 20, 20);
    expect(rects(q2), [(10.0, 0.0, 20.0, 5.0, ground, ground), (10.0, 5.0, 20.0, 15.0, 0xff00bb00, 0xff00bb00), (10.0, 15.0, 20.0, 20.0, ground, ground)]);
    // 한 칸이 통째로 품으면 하나 · 칸이 없으면 바탕 하나.
    final q3 = SvgQuads();
    g.paper(q3, 45, 0, 55, 50);
    g.paper(q3, 200, 0, 300, 50);
    expect(rects(q3), [(45.0, 0.0, 55.0, 50.0, 0xffaa0000, 0xffaa0000), (200.0, 0.0, 300.0, 50.0, ground, ground)]);
  });

  test('칠은 조각마다 그 바탕과 섞고 · register면 칠한 몫이 바탕 칸이 된다(같은 칠의 조각끼리는 서로의 바탕이 아니다)', () {
    final g = Grounds()..reset(ground)..add(40, 0, 60, 100, 0xffaa0000);
    final fill = withAlpha(0xffacb4ca, .09);
    final q = SvgQuads();
    g.fill(q, 0, 0, 100, 10, fill, register: true);
    final got = rects(q);
    expect(got, hasLength(3));
    expect(got[0].$5, near(composite(fill, ground)));
    expect(got[1].$5, near(composite(fill, 0xffaa0000)));
    expect(got[2].$5, near(composite(fill, ground)));
    expect(g.at(10, 5), got[0].$5, reason: '등록된 칠');
    expect(g.at(50, 5), got[1].$5);
    expect(g.at(50, 50), 0xffaa0000, reason: '칠 밖은 그대로');
    // 불투명 칠은 나누지 않는다.
    final q2 = SvgQuads();
    g.fill(q2, 0, 0, 100, 10, 0xff112233);
    expect(rects(q2), [(0.0, 0.0, 100.0, 10.0, 0xff112233, 0xff112233)]);
  });

  test('번지는 칠(투명 → 색)은 그 자리 바탕색에서 짙어지는 불투명 그러데이션 — 바탕도 번지면 4px씩 나눠 섞는다', () {
    final g = Grounds()..reset(ground);
    final color = 0xffd4a39b, clear = color & 0x00ffffff;
    final q = SvgQuads();
    g.fade(q, 0, 0, 44, 10, withAlpha(color, .58), clear);
    final got = rects(q);
    expect(got, hasLength(1));
    expect(got.single.$5, near(composite(withAlpha(color, .58), ground)));
    expect(got.single.$6, ground, reason: '투명 끝은 그 자리 바탕색');
    // 바탕이 번지는 칸(검은 → 흰) 위의 번지는 칠: 조각 끝마다 알파 합성과 ±1.
    final g2 = Grounds()..reset(ground)..add(0, 0, 40, 10, 0xff000000, 0xffffffff);
    final q2 = SvgQuads();
    g2.fade(q2, 0, 0, 40, 10, clear, withAlpha(color, .5));
    final pieces = rects(q2);
    expect(pieces.length, 10);
    for (final p in pieces) {
      final f = p.$1 / 40;
      final bottom = 0xff000000 | (255 * f).round() * 0x010101;
      expect(p.$5, near(composite(withAlpha(color, .5 * f), bottom), tol: 2), reason: '조각 ${p.$1}');
    }
  });

  test('칠하지 않고 등록만(tint) — 투명이면 아무것도 등록하지 않는다', () {
    final g = Grounds()..reset(ground);
    g.tint(0, 0, 100, 100, 0x00000000);
    expect(g.length, 0);
    g.tint(0, 0, 100, 100, withAlpha(0xffd4a39b, .09));
    expect(g.length, 1);
    expect(g.at(50, 50), near(composite(withAlpha(0xffd4a39b, .09), ground)));
  });

  test('메움 타일의 자르기 안에서 등록한 칸은 그 자리만큼만 — 선형 칸은 잘린 끝의 색을 그 자리 값으로', () {
    final g = Grounds()..reset(ground);
    g.clip = const ui.Rect.fromLTRB(0, 0, 50, 100);
    g.add(0, 0, 100, 10, 0xffaa0000);
    expect(g.at(20, 5), 0xffaa0000);
    expect(g.at(70, 5), ground, reason: '자르기 밖에는 그 칠이 그려지지 않았다');
    g.clip = const ui.Rect.fromLTRB(50, 0, 100, 100);
    g.add(0, 20, 100, 30, 0xff000000, 0xffffffff);
    expect(g.at(20, 25), ground);
    expect(g.at(75, 25), near(0xffbfbfbf), reason: '잘린 뒤에도 제 자리의 색');
    g.clip = null;
    g.add(0, 40, 10, 50, 0xff00bb00);
    expect(g.at(5, 45), 0xff00bb00);
  });
}
