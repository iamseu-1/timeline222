import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> px(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
int at(Uint8List p, int w, int x, int y, int ch) => p[(y * w + x) * 4 + ch];

/// 네모 [x0, x1) × [y0, y1) 안에서 먹이 묻은(빨강 < 128) 화소의 수.
int ink(Uint8List p, int w, int x0, int y0, int x1, int y1) {
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (at(p, w, x, y, 0) < 128) n++;
    }
  }
  return n;
}

void main() {
  setUpAll(() => loadMockFonts('assets/fonts'));

  test('경로 읽기: 둥근 네모 · 호 · 상대 좌표', () {
    final p = parsePath('M10,20 H90 A10,10 0 0 1 100,30 V44 H10 Z');
    final b = p.getBounds();
    expect(b.left, 10);
    expect(b.right, closeTo(100, 1e-6));
    expect(b.top, 20);
    expect(b.bottom, 44);
    expect(parsePath('m5 5 l10 0 v10 h-10 z').getBounds(), const ui.Rect.fromLTRB(5, 5, 15, 15));
  });

  test('점선: 3 2로 10을 자르면 조각 둘', () {
    final line = ui.Path()..moveTo(0, 0)..lineTo(10, 0);
    final d = dashed(line, [3, 2], 0);
    expect(d.computeMetrics().length, 2);
  });

  test('E는 null · false 속성을 뺀다 · 모양 속성은 물려받는다', () async {
    final svg = E('svg', {'width': 40, 'height': 20});
    final g = E('g', {'fill': '#ff0000', 'stroke': null, 'opacity': false}, svg);
    E('rect', {'x': 0, 'y': 0, 'width': 10, 'height': 10}, g);
    expect(g.attrs.containsKey('stroke'), isFalse);
    expect(g.attrs.containsKey('opacity'), isFalse);
    final img = await renderMock(svg, width: 40, height: 20);
    final p = await px(img);
    expect([at(p, 40, 5, 5, 0), at(p, 40, 5, 5, 1)], [255, 0]); // 물려받은 빨강
    expect(at(p, 40, 30, 5, 1), 255); // 바탕은 흰색
  });

  test('자르기 · 옮기기: 자르기는 그 요소의 좌표계', () async {
    final svg = E('svg', {'width': 40, 'height': 40});
    final defs = E('defs', {}, svg);
    final cp = E('clipPath', {'id': 'c1'}, defs);
    E('rect', {'x': 0, 'y': 0, 'width': 20, 'height': 40}, cp);
    final g = E('g', {'clip-path': 'url(#c1)', 'transform': 'translate(5,0)'}, svg);
    E('rect', {'x': 0, 'y': 0, 'width': 30, 'height': 10, 'fill': '#000000'}, g);
    final p = await px(await renderMock(svg, width: 40, height: 40));
    expect(at(p, 40, 2, 5, 0), 255); // 옮겨서 0~4는 비었다
    expect(at(p, 40, 10, 5, 0), 0); // 그려짐
    // 자르기 0~20은 g의 좌표 → 화면 5~25: 22는 그려지고(옮기기를 빼먹으면 화면 0~20이라 흰색) 25부터 잘린다
    expect(at(p, 40, 22, 5, 0), 0);
    expect(at(p, 40, 25, 5, 0), 255);
  });

  test('그룹 투명도는 층으로 — 겹친 자식이 두 번 옅어지지 않는다', () async {
    final svg = E('svg', {'width': 40, 'height': 20});
    final g = E('g', {'opacity': .5}, svg);
    E('rect', {'x': 0, 'y': 0, 'width': 30, 'height': 20, 'fill': '#000000'}, g);
    E('rect', {'x': 10, 'y': 0, 'width': 30, 'height': 20, 'fill': '#000000'}, g);
    final p = await px(await renderMock(svg, width: 40, height: 20));
    expect(at(p, 40, 5, 10, 0), closeTo(128, 2));
    expect(at(p, 40, 20, 10, 0), closeTo(128, 2), reason: '겹친 곳도 한 번만 옅어진다(자식마다 곱하면 64 · 빼먹으면 0)');
  });

  test('자르기 자식은 합집합', () async {
    final svg = E('svg', {'width': 40, 'height': 10});
    final cp = E('clipPath', {'id': 'u'}, E('defs', {}, svg));
    E('rect', {'x': 0, 'y': 0, 'width': 10, 'height': 10}, cp);
    E('rect', {'x': 20, 'y': 0, 'width': 10, 'height': 10}, cp);
    E('rect', {'x': 0, 'y': 0, 'width': 40, 'height': 10, 'fill': '#000000', 'clip-path': 'url(#u)'}, svg);
    final p = await px(await renderMock(svg, width: 40, height: 10));
    expect([for (final x in [5, 15, 25, 35]) at(p, 40, x, 5, 0)], [0, 255, 0, 255]);
  });

  test('칠과 선이 함께인 모양의 투명도는 한 장으로 — 칠 위의 선이 두 번 옅어지지 않는다', () async {
    final svg = E('svg', {'width': 40, 'height': 40});
    E('rect', {'x': 10, 'y': 10, 'width': 20, 'height': 20, 'fill': '#000000', 'stroke': '#000000', 'stroke-width': 4, 'opacity': .5}, svg);
    final p = await px(await renderMock(svg, width: 40, height: 40));
    expect(at(p, 40, 20, 20, 0), closeTo(128, 2)); // 칠만
    expect(at(p, 40, 9, 20, 0), closeTo(128, 2)); // 칠 밖의 선
    expect(at(p, 40, 11, 20, 0), closeTo(128, 2), reason: '칠 위의 선(칠 · 선에 따로 곱하면 64)');
  });

  test('점선 offset: 음수 · 홀수 dasharray(두 번 이어 씀)', () {
    final line = ui.Path()..moveTo(0, 0)..lineTo(20, 0);
    List<(double, double)> runs(List<double> dash, double offset) => [
          for (final m in dashed(line, dash, offset).computeMetrics())
            (m.getTangentForOffset(0)!.position.dx, m.getTangentForOffset(0)!.position.dx + m.length),
        ];
    void same(List<(double, double)> got, List<(double, double)> want) {
      expect(got.length, want.length, reason: '$got');
      for (var i = 0; i < want.length; i++) {
        expect(got[i].$1, closeTo(want[i].$1, 1e-6), reason: '$got');
        expect(got[i].$2, closeTo(want[i].$2, 1e-6), reason: '$got');
      }
    }

    // 4 2 1 → 4 2 1 4 2 1(한 벌 14). offset 9: 한 벌이 7이면(두 번 이어 쓰지 않으면) 0~2부터 그려진다.
    same(runs([4, 2, 1], 9), [(2, 4), (5, 9), (11, 12), (16, 18), (19, 20)]);
    // offset −3 = 한 벌의 11부터: 0~2는 무늬 끝의 선(나머지를 0 쪽으로 자르면 3부터 시작해 빠진다).
    same(runs([4, 2, 1], -3), [(0, 2), (3, 7), (9, 10), (14, 16), (17, 20)]);
  });

  test('속성은 허락 목록으로 — 모르는 속성 · 자르기 단위 objectBoundingBox는 실패 · 이름표는 받음', () async {
    MockEl svg([Map<String, Object?> at = const {}]) => E('svg', {'width': 10, 'height': 10, ...at});
    // dx는 글을 옮기는데 그리지 않는다 · 원에 x는 원의 자리가 아니다
    final dx = svg();
    E('text', {'x': 0, 'y': 8, 'dx': 3}, dx).text = '가';
    await expectLater(renderMock(dx, width: 10, height: 10), throwsA(isA<UnsupportedError>()));
    final cx = svg();
    E('circle', {'cx': 5, 'cy': 5, 'r': 2, 'x': 3}, cx);
    await expectLater(renderMock(cx, width: 10, height: 10), throwsA(isA<UnsupportedError>()));
    // 자르기 단위가 objectBoundingBox면 0~1을 모양의 상자에 늘여야 한다 — 그리지 못하니 실패 · 자르기 자식의 clip-path도
    for (final (units, child) in [('objectBoundingBox', <String, Object?>{}), ('userSpaceOnUse', <String, Object?>{'clip-path': 'url(#k)'})]) {
      final s = svg();
      E('rect', {'width': 1, 'height': 1, ...child}, E('clipPath', {'id': 'k', 'clipPathUnits': units}, E('defs', {}, s)));
      E('rect', {'x': 0, 'y': 0, 'width': 10, 'height': 10, 'clip-path': 'url(#k)'}, s);
      await expectLater(renderMock(s, width: 10, height: 10), throwsA(isA<UnsupportedError>()), reason: '$units $child');
    }
    // 받는 것: 이름표(id · class · xmlns · data-*) · 자르기 단위 userSpaceOnUse
    final ok = svg({'xmlns': 'http://www.w3.org/2000/svg', 'class': 'screen'});
    E('rect', {'width': 10, 'height': 10}, E('clipPath', {'id': 'k', 'clipPathUnits': 'userSpaceOnUse'}, E('defs', {}, ok)));
    E('rect', {'x': 0, 'y': 0, 'width': 10, 'height': 10, 'id': 'r', 'data-kind': 'band', 'clip-path': 'url(#k)'}, ok);
    expect(at(await px(await renderMock(ok, width: 10, height: 10)), 10, 5, 5, 0), 0);
  });

  test('ClearType 굽개가 늦어도 판 사이에 기다려 ClearType으로 찍는다 · 반투명 층 안의 글자는 회색', () async {
    final atlas = AtlasText(baker: _Baker(const Duration(milliseconds: 60)), fontFileOf: (_) => 'fake')
      ..budgetMicros = 1 << 30
      ..lcdAllowed = true;
    final svg = E('svg', {'width': 120, 'height': 40});
    E('text', {'x': 10, 'y': 15, 'font-size': 12}, svg).text = '조선';
    E('text', {'x': 10, 'y': 35, 'font-size': 12}, E('g', {'opacity': .5}, svg)).text = '고려';
    await renderMock(svg, width: 120, height: 40, text: atlas);
    // ClearType 섞기(곱하기 · 더하기)는 바탕이 불투명해야 맞다 — 층 안의 글자를 구워 찍으면 층에 흰 네모가 남는다.
    expect(atlas.lcdSprites, 2, reason: '불투명한 글줄(조선)만 ClearType · 층 안(고려)은 회색');
    expect(atlas.lcdAllowed, isTrue, reason: '층을 닫으며 되돌린다');
    expect(mockRenderInfo(svg)!.settled, isTrue);
    atlas.dispose();
  });

  test('굽기가 끝내 오지 않으면 기다림 끝에 회색으로 그리되 알린다 · 굽개 없는 그림은 한 판', () async {
    final atlas = AtlasText(baker: _Baker(null), fontFileOf: (_) => 'fake')
      ..budgetMicros = 1 << 30
      ..lcdAllowed = true;
    final svg = E('svg', {'width': 80, 'height': 20});
    E('text', {'x': 10, 'y': 15, 'font-size': 12}, svg).text = '조선';
    final p = await px(await renderMock(svg, width: 80, height: 20, text: atlas, patience: const Duration(milliseconds: 200)));
    final info = mockRenderInfo(svg)!;
    expect(info.settled, isFalse, reason: '굽기를 기다리다 그침');
    expect(info.rounds, greaterThan(1));
    expect(ink(p, 80, 0, 0, 80, 20), greaterThan(0), reason: '글자는 회색으로 찍혔다');
    atlas.dispose();
    final plain = E('svg', {'width': 80, 'height': 20});
    E('text', {'x': 10, 'y': 15, 'font-size': 12}, plain).text = '조선';
    await renderMock(plain, width: 80, height: 20);
    expect((mockRenderInfo(plain)!.settled, mockRenderInfo(plain)!.rounds), (true, 1));
  });

  test('글자: 바탕선 · 가운데 맞춤 · 이어진 빈칸은 하나로', () async {
    final svg = E('svg', {'width': 200, 'height': 40});
    E('text', {'x': 100, 'y': 25, 'font-size': 12, 'font-weight': 700, 'text-anchor': 'middle', 'font-family': 'Pretendard'}, svg).text = '조선  왕조';
    await renderMock(svg, width: 200, height: 40);
    final box = mockTextBoxes(svg).single;
    expect(box.text, '조선 왕조');
    expect(box.baseline, 25);
    expect(box.left + box.width / 2, closeTo(100, 1));
  });

  test('모르는 색은 까닭과 함께 실패(무늬 · 그라데이션은 아직 없음)', () async {
    final svg = E('svg', {'width': 10, 'height': 10});
    E('rect', {'x': 0, 'y': 0, 'width': 10, 'height': 10, 'fill': 'url(#pat)'}, svg);
    expect(() => renderMock(svg, width: 10, height: 10), throwsA(isA<UnsupportedError>()));
  });

  test('아이콘 조각: 있던 자식을 바꾼다 · 모르는 요소와 속성은 실패', () async {
    final g = E('g', {});
    E('rect', {'width': 1, 'height': 1}, g);
    setInnerSvg(g, '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>');
    expect(g.children.map((e) => e.tag), ['circle', 'path']);
    expect(g.children.first.attrs, {'cx': '11', 'cy': '11', 'r': '8'});
    expect(g.children.last.parent, same(g));
    expect(() => setInnerSvg(g, '<polyline points="1 2 3 4"/>'), throwsA(isA<UnsupportedError>()));
    expect(() => setInnerSvg(g, "<path d='M0 0h4'/>"), throwsA(isA<UnsupportedError>()));
    final svg = E('svg', {'width': 10, 'height': 10});
    E('path', {'d': 'M0 0h10v10h-10z', 'fill-rule': 'evenodd'}, svg);
    expect(() => renderMock(svg, width: 10, height: 10), throwsA(isA<UnsupportedError>()));
  });

  test('바탕선: 그림판이 찍은 글자의 바탕선이 SVG의 y 줄에 온다 · 넘겨받은 글자 그리기는 버리지 않는다', () async {
    final atlas = AtlasText()..budgetMicros = 1 << 30;
    final svg = E('svg', {'width': 200, 'height': 60});
    E('text', {'x': 10, 'y': 25, 'font-size': 12}, svg).text = '조선 왕조';
    E('text', {'x': 10, 'y': 50.4, 'font-size': 15, 'font-weight': 600}, svg).text = '朝鮮 1392';
    await renderMock(svg, width: 200, height: 60, text: atlas);
    expect(atlas.debugLastPens.map((p) => p.$2).toSet(), {25.0, 50.0});
    expect(atlas.glyphCount, greaterThan(0));
    atlas.dispose();
  });

  test('글자도 자르기 · 그리는 차례를 따른다', () async {
    final svg = E('svg', {'width': 160, 'height': 80});
    E('rect', {'x': 0, 'y': 0, 'width': 30, 'height': 40}, E('clipPath', {'id': 'c'}, E('defs', {}, svg)));
    E('text', {'x': 0, 'y': 32, 'font-size': 30}, E('g', {'clip-path': 'url(#c)'}, svg)).text = '가나다라';
    E('text', {'x': 0, 'y': 72, 'font-size': 30}, svg).text = '가나다라';
    E('rect', {'x': 30, 'y': 40, 'width': 130, 'height': 40, 'fill': '#ffffff'}, svg); // 글자 뒤에 그린 덮개
    final p = await px(await renderMock(svg, width: 160, height: 80));
    expect(ink(p, 160, 0, 0, 30, 40), greaterThan(0));
    expect(ink(p, 160, 30, 0, 160, 40), 0, reason: '자르기 밖의 글자');
    expect(ink(p, 160, 0, 40, 30, 80), greaterThan(0));
    expect(ink(p, 160, 30, 40, 160, 80), 0, reason: '뒤에 그린 덮개가 글자를 덮는다');
  });

  test('글꼴 목록의 첫 이름으로 · 세로쓰기는 한 자씩 위에서 아래로', () async {
    const s = '훈민정음 해례';
    final svg = E('svg', {'width': 200, 'height': 100});
    E('text', {'x': 0, 'y': 20, 'font-size': 16, 'font-family': '"Pretendard", "Malgun Gothic", sans-serif'}, svg).text = s;
    E('text', {'x': 0, 'y': 50, 'font-size': 16, 'font-family': '"RIDIBatang", "Batang", serif'}, svg).text = s;
    E('text', {'x': 180, 'y': 10, 'font-size': 10, 'writing-mode': 'vertical-rl'}, svg).text = '가나다';
    final p = await px(await renderMock(svg, width: 200, height: 100));
    final [sans, serif, vertical] = mockTextBoxes(svg);
    expect(sans.width, closeTo(mockTextWidth(s, 16, 400, 'Pretendard'), 1));
    expect(serif.width, closeTo(mockTextWidth(s, 16, 400, '"RIDIBatang", "Batang", serif'), 1));
    expect((sans.width - serif.width).abs(), greaterThan(2), reason: '두 글꼴의 폭이 달라야 글꼴을 가려 그린 것');
    // 세로: 한 자 = 크기 × 1.2 → 세 자는 10 ~ 46, 가운데는 x = 180
    expect(vertical.height, closeTo(36, 1e-9));
    var x0 = 200, x1 = 0, y0 = 100, y1 = 0;
    for (var y = 0; y < 100; y++) {
      for (var x = 160; x < 200; x++) {
        if (at(p, 200, x, y, 0) >= 128) continue;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    expect((x0 + x1 + 1) / 2, closeTo(180, 1.5));
    expect(y0, greaterThanOrEqualTo(10));
    expect(y1, inInclusiveRange(36, 46), reason: '셋째 글자가 아래로 이어진다');
  });

  test('대체 글꼴: ▸는 크롬처럼 Cambria Math — 줄무늬 네모가 아니고 폭이 크롬과 같다 · 앱의 대체 줄은 그대로', () async {
    // 크롬(판 사본 · 조각 ④ 단추)이 잰 '▸ 단체 6'(10px 400)의 폭 — 프리텐다드에 ▸가 없어 Cambria Math 8.354px로 채움. 네모(1em)면 38.44.
    expect(mockTextWidth('▸ 단체 6', 10, 400, 'Pretendard'), closeTo(36.797, .05));
    final svg = E('svg', {'width': 60, 'height': 60});
    E('text', {'x': 10, 'y': 45, 'font-size': 40}, svg).text = '▸';
    final p = await px(await renderMock(svg, width: 60, height: 60));
    // 작은 삼각형(먹 화소 97쯤)이지 칸을 채운 줄무늬 네모(396)가 아니다
    expect(ink(p, 60, 0, 0, 60, 60), inInclusiveRange(20, 200), reason: '▸의 잉크(네모면 396)');
    expect(sceneFallbackNow, sceneFontFallback, reason: '그리는 동안만 목업의 대체 줄');
  }, skip: mockFallbackAvailable() ? false : '대체 글꼴 파일(맑은 고딕 · Cambria)이 없음');
}

/// 늦게 굽는 가짜 굽개 — 글자마다 4×6 덮임을 [delay] 뒤에 돌려준다. [delay]가 null이면 끝내 답하지 않는다.
class _Baker implements GlyphBaker {
  _Baker(this.delay);
  final Duration? delay;

  @override
  Future<List<LcdGlyph>> bake(String font, double sizePx, List<int> runes) async {
    final wait = delay;
    if (wait == null) return Completer<List<LcdGlyph>>().future;
    await Future<void>.delayed(wait);
    return [for (final r in runes) LcdGlyph(r, true, 0, -6, 4, 6, sizePx * .6, Uint8List(4 * 6 * 3)..fillRange(0, 72, 255))];
  }
}
