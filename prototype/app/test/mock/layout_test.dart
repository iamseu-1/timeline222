import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/mock/kit.dart';
import 'package:archive_prototype/mock/render.dart';
import 'package:archive_prototype/mock/scene.dart';
import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:flutter_test/flutter_test.dart';

import 'source_sha.dart';

// 옮긴 줄 쌓기(scene.dart)를 원본 scene.js가 노드에서 낸 자리(fixtures/layout.json — prototype/scripts/mock-oracle.mjs로 뽑음)와 견주고,
// 옮긴 틀(render.dart)이 render.js처럼 층 열둘 · 그림판 자르기 · 종이를 만드는지 본다.

void main() {
  // renderScreen은 글 폭을 재어 맞춤을 고른다 — 목업 글꼴이 실려 있어야 크롬과 같은 글을 고른다.
  setUpAll(() => loadMockFonts('assets/fonts'));

  final o = jsonDecode(File('test/mock/fixtures/layout.json').readAsStringSync()) as Map<String, dynamic>;

  test('정답지가 가리키는 판이 원본 사본(source/mock-sha.txt)과 같다', () {
    final sha = mockSourceSha();
    expect(o['source'], {'scene.js': sha['scene.js'], 'render.js': sha['render.js']}, reason: '정답지가 옛 판에서 뽑힘 — docs/목업-판.md 6절의 차례로 다시 뽑는다');
  });

  test('layoutScene이 scene.js와 같은 줄을 쌓는다', () {
    final L = layoutScene(mockScene(), BaseTheme().M);
    expect(L['bottom'], o['bottom']);
    final rows = L['rows'] as List;
    expect(rows.length, (o['rows'] as List).length);
    for (var i = 0; i < rows.length; i++) {
      final a = rows[i] as Map, b = o['rows'][i] as Map;
      expect([a['y'], a['yBand'], a['h'], a['depth'], a['laneY']], [b['y'], b['yBand'], b['h'], b['depth'], b['laneY']], reason: '$i번째 줄');
      expect([for (final x in a['items'] as List) x['n']], b['items']);
    }
    final cs = L['containers'] as List;
    expect([for (final c in cs) [c['n'], c['depth'], c['yTop'], c['yBottom'], (c['rows'] as List).length]],
        [for (final c in o['containers'] as List) [c['n'], c['depth'], c['yTop'], c['yBottom'], c['rows']]]);
    expect([for (final c in L['cultures'] as List) [c['n'], c['y0'], c['y1'], c['closed'] == true, c['rowY']]],
        [for (final c in o['cultures'] as List) [c['n'], c['y0'], c['y1'], c['closed'], c['rowY']]]);
  });

  test('renderScreen(기준 방향)은 층 열둘 · 그림판 자르기 · 1920×1080 종이를 만든다', () {
    final r = renderScreen(BaseTheme());
    expect(r.p.svg.attrs['width'], 1920);
    expect([for (final c in r.p.svg.children) c.tag].where((t) => t == 'g').length, 12);
    for (final layer in [r.p.grid, r.p.under, r.p.cont, r.p.links, r.p.band, r.p.over]) {
      expect('${layer.attrs['clip-path']}', startsWith('url(#'));
    }
    final paper = r.p.bg.children.first;
    expect([paper.tag, paper.attrs['width'], paper.attrs['height']], ['rect', 1920, 1080]);
  });

  test('그리기는 원본 장면을 고치지 않는다 — 장면마다 새것 · 두 번 그려도 같은 나무', () {
    // 자르기 이름(clip1 · clip2)만 그릴 때마다 다르다.
    String tree(MockEl e) =>
        '<${e.tag}${[for (final a in e.attrs.entries) if (a.key != 'id' && a.key != 'clip-path') ' ${a.key}=${a.value}'].join()}>${e.text}${e.children.map(tree).join()}</${e.tag}>';
    final a = renderScreen(BaseTheme()), b = renderScreen(BaseTheme());
    expect(identical(a.S, b.S), isFalse);
    expect(tree(b.p.svg), tree(a.p.svg));
    // 그린 장면에는 이름표의 줄 · 객체의 자리가 적히고, 원본에는 남지 않는다.
    expect(a.S['labels'][2]['lane'], 1);
    expect(a.S['cultures'][0]['tracks'][0]['rows'][0]['items'][0]['geo'], isNotNull);
    expect([for (final l in SCENE['labels'] as List) (l as Map).containsKey('lane')], everyElement(isFalse));
    expect((SCENE['cultures'][0]['tracks'][0]['rows'][0]['items'][0] as Map).containsKey('geo'), isFalse);
  });

  test('갈래는 상속으로: tok · M은 덮을 열쇠만(f · sz는 한 겹 더) · 덮어쓴 고리가 기준 고리 안에서 불린다', () {
    final th = _Red();
    expect([th.tok['paper'], th.tok['fill'], th.tok['sz']['title'], th.tok['sz']['name'], th.tok['f']['title'], th.tok['f']['ui']], ['#fafafa', .24, 18, 9, 'serif', 'sans']);
    expect([th.M['top'], th.M['gap']], [140, 5]);
    expect(BaseTheme().tok['sz']['title'], 15); // 기준 토큰은 그대로
    final r = renderScreen(th);
    expect(r.L['rows'][0]['y'], 140);
    expect(r.p.frame.children.first.attrs['stroke'], '#ff0000'); // frame → rule(…, k(.2))
    expect(r.p.frame.children[1].attrs['font-family'], K.FONT['serif']); // 제목 글은 역할 title의 글꼴
  });
}

class _Red extends BaseTheme {
  @override
  Map<String, dynamic> get tokOverride => {
        'paper': '#fafafa',
        'sz': {'title': 18},
        'f': {'title': 'serif'},
      };

  @override
  Map<String, num> get mOverride => {'top': 140};

  @override
  String k(num a) => '#ff0000';
}
