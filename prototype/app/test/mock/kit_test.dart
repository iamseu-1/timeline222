import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/mock/kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'source_sha.dart';

// 옮긴 kit.dart를 원본 kit.js가 노드에서 낸 수(fixtures/kit.json — prototype/scripts/mock-oracle.mjs로 뽑음)와 견준다.
// 색도 경로도 글자 그대로 견준다 — 경로는 수를 글로 쓰는 jsNum('22.0'이 아니라 '22')까지 함께 지킨다.

void expectSamePath(String dart, String js) => expect(dart, js);

void main() {
  final o = jsonDecode(File('test/mock/fixtures/kit.json').readAsStringSync()) as Map<String, dynamic>;

  test('정답지가 가리키는 판이 원본 사본(source/mock-sha.txt)과 같다', () {
    final sha = mockSourceSha();
    expect(o['source'], {'kit.js': sha['kit.js']}, reason: '정답지가 옛 판에서 뽑힘 — docs/목업-판.md 6절의 차례로 다시 뽑는다');
  });

  test('mix · mixOk가 kit.js와 같다', () {
    for (final r in o['mix'] as List) {
      expect(K.mix(r[0], r[1]), r[2], reason: '$r');
    }
    for (final r in o['mixOk'] as List) {
      expect(K.mixOk(r[0], r[1], K.INK), r[2], reason: '$r');
    }
  });

  test('edge · edgeSoft · fillC · tabInk · nameInk · ink', () {
    for (final r in o['fn'] as List) {
      final c = r[0] as String;
      expect([K.edge(c), K.edgeSoft(c), K.fillC(c), K.fillC(c, .09), K.tabInk(c), K.nameInk(c), K.ink(.6)], (r as List).sublist(1), reason: c);
    }
  });

  test('종이 · 먹을 넘기는 꼴(render.js가 부르는 대로)', () {
    for (final r in o['ink3'] as List) {
      expect(K.ink(r[0], r[1], r[2]), r[3], reason: '$r');
    }
    for (final r in o['paper'] as List) {
      final c = r[0] as String, paper = r[1] as String;
      expect([K.mixOk(c, .35, paper), K.mixOk(c, .55, paper), K.mixOk(c, .7, paper), K.mix(c, .5, paper), K.fillC(c, .09, paper)], (r as List).sublist(2), reason: '$c · $paper');
    }
  });

  test('rr · tabPath · roundPoly 경로', () {
    // 인자는 정답지에 적힌 그대로 — rr의 다섯째는 수이거나 [tl, tr, br, bl] 목록, 여섯째는 있을 때만.
    for (final r in o['rr'] as List) {
      final a = r[0] as List;
      expectSamePath(K.rr(a[0], a[1], a[2], a[3], a.length > 4 ? a[4] : 10, a.length > 5 ? a[5] : null), r[1]);
    }
    for (final r in o['tab'] as List) {
      final a = r[0] as List;
      final t = K.tabPath(a[0], a[1], a[2], a[3], a.length > 4 ? a[4] : 7);
      expectSamePath(t.fill, r[1]['fill']);
      expectSamePath(t.open, r[1]['open']);
      expectSamePath(t.stroke, r[1]['stroke']);
    }
    final p = (o['poly'] as List).first;
    expectSamePath(K.roundPoly([for (final q in p[0] as List) [for (final v in q as List) v as num]], p[1]), p[2]);
  });

  test('px(JS 반올림) · base', () {
    for (final r in o['px'] as List) {
      expect(K.px(r[0]), r[1], reason: '$r');
    }
    for (final r in o['base'] as List) {
      expect(K.base(r[0], r[1]), closeTo(r[2], 1e-12), reason: '$r');
    }
  });
}
