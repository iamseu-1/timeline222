import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/mock/boards.dart';
import 'package:archive_prototype/mock/js.dart';
import 'package:archive_prototype/mock/render.dart';
import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:archive_prototype/mock/themes/s4_common.dart';
import 'package:archive_prototype/mock/themes/t_common.dart';
import 'package:flutter_test/flutter_test.dart';

// 나무 대조의 Dart 쪽 — 기준 방향 + 판 s4의 갈래 열넷을 그려 요소 나무(화면 · 부품 판)와 갈래의 값(meta)을 ../results/mock/tree/<id>.json에,
// 글 폭 표를 widths.json에 남긴다(git이 무시하는 폴더). 견주기는 prototype/scripts/mock-tree.mjs가 한다: 원본 JS를 노드로 돌리되
// 글 폭은 이 표에서 읽어, 같은 폭이면 옮긴 갈래가 원본과 같은 나무를 짓는지 본다(크롬과의 글 폭 차이는 과제 5의 그림 대조가 본다).
// 글 폭 표는 노드가 물을 것을 미리 다 알 수 없어, Dart 나무의 글 · 그 첫 글자로 채우고 노드가 표에 없던 것을 물으면
// mock-tree.mjs가 queries.json에 모아 두므로 이 검사를 다시 돌리면 그것까지 잰다(물음이 0이 될 때까지 — 그 뒤로는 한 번에).

const outDir = '../results/mock/tree';

/// 요소 하나를 JSON으로 — 속성 값은 JS setAttribute처럼 글로(String(v)).
Map<String, Object?> dump(MockEl e, Set<String> seeds) {
  if (e.tag == 'text' && e.text.isNotEmpty) {
    final head = '${jsStr(e.attrs['font-weight'])} ${jsStr(e.attrs['font-size'])}px ${e.attrs['font-family']}|';
    seeds
      ..add('$head${e.text}')
      ..add('$head${e.text[0]}');
  }
  return {
    'tag': e.tag,
    'at': {for (final a in e.attrs.entries) a.key: jsStr(a.value)},
    if (e.tag == 'text') 'text': e.text,
    if (e.children.isNotEmpty) 'ch': [for (final c in e.children) dump(c, seeds)],
  };
}

/// 자동 번호(K.id — clip12 · fade3)를 나무 안에서 처음 나온 차례로 다시 매긴다(clip#1 · fade#1) — 번호 자체는 그림마다 다르지만
/// 어느 것을 가리키는지(id ↔ url(#…))는 그대로 견주게.
String renumbered(Object tree) {
  final seen = <String, String>{}, count = <String, int>{};
  return jsonEncode(tree).replaceAllMapped(RegExp(r'("id":"|url\(#)([A-Za-z]+)(\d+)'), (m) {
    final p = m[2]!;
    return '${m[1]}${seen.putIfAbsent('$p${m[3]}', () => '$p#${count[p] = (count[p] ?? 0) + 1}')}';
  });
}

int count(Map<String, Object?> e) => 1 + [for (final c in (e['ch'] as List? ?? const [])) count(c as Map<String, Object?>)].fold(0, (a, b) => a + b);

/// 크롬 measureText의 글꼴 줄(`${wt} ${size}px ${FONT}`)과 글 → 앱의 글 폭.
double widthOf(String key) {
  final bar = key.indexOf('|');
  final m = RegExp(r'^(\d+) ([\d.]+)px (.*)$').firstMatch(key.substring(0, bar))!;
  return mockTextWidth(key.substring(bar + 1), double.parse(m.group(2)!), int.parse(m.group(1)!), m.group(3)!);
}

/* 연습 갈래 둘(원본에 없음) — s4가 쓰지 않는 t-common 함수(장면 · layoutApp · layoutSeogo · appCells · chain · tieCross · fade 등)도
   원본과 같은 나무를 짓는지 보려고, mock-tree.mjs의 DRILLS와 같은 꼴로 둔다(두 쪽을 함께 고칠 것). */
class _DrillApp extends BaseTheme {
  @override
  String get id => 't-drill-app';
  @override
  Map<String, num> get mOverride => const {'top': 128};
  @override
  Map<String, dynamic>? scene(Map<String, dynamic> S) => TAG.scene(S);
  @override
  void frame(Map<String, dynamic> S, MockLayers p, [Map<String, dynamic>? L]) {
    TAG.layoutApp(S, L!, M);
    super.frame(S, p, L);
  }

  @override
  void object(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g) {
    final b = TAG.geom(p, o, g), kind = TAG.kindOf(o);
    final fill = TAG.paintTag(this, p, o, b, b['X0'], b['Y'], b['H'] - 1, kind, p.band).fill;
    TAG.appCells(this, p, o, b, b['X0'] + 4, b['X1'] - 4, b['leaderTop'], fill);
    TAG.events(this, p, o, b, {
      'lines': [b['lineY'](0), b['lineY'](1)],
      'lo': b['X0'] + 9, 'hi': b['X1'] - 9, 'rlim': b['X1'] - 4, //
    });
  }
}

class _DrillSeogo extends BaseTheme {
  @override
  String get id => 't-drill-seogo';
  @override
  Map<String, num> get mOverride => const {'top': 128, 'tabH0': 5, 'tabHS': 20, 'chainH': 16, 'gap': 3, 'trackGap': 4};
  @override
  Map<String, dynamic>? scene(Map<String, dynamic> S) => TAG.scene(S);
  @override
  void frame(Map<String, dynamic> S, MockLayers p, [Map<String, dynamic>? L]) {
    TAG.layoutSeogo(S, L!, M);
    super.frame(S, p, L);
  }

  @override
  void object(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g) {
    final b = TAG.geom(p, o, g), kind = TAG.kindOf(o);
    final num head = b['sp']['head'], ch = b['sp']['chain'];
    final cd = jsTruthy(o['serve']) ? TAG.card(this, p, o, g, b, b['Y'], head - 1, kind) : null;
    TAG.paintTag(this, p, o, b, b['X0'], b['Y'], head - 1, kind, p.band);
    if (ch != 0) TAG.chain(this, p, o, b, b['Y'] + head - 1, ch, kind);
    final tie = g['tie'] = <String, dynamic>{'xe': b['X1']};
    if (!b['cl'] && !b['short']) {
      tie['hx'] = TAG.holeX(b, kind);
      tie['hy'] = b['Y'] + TAG.HOLE;
      TAG.hole(this, p, tie['hx'], tie['hy'], jsTruthy(o['selected']));
    }
    if (jsTruthy(o['out']) && !b['cr'] && !b['short']) {
      tie['dx'] = b['X1'] - 7;
      tie['dy'] = b['Y'] + TAG.HOLE;
    }
    if (cd != null) {
      final tr = (cd['xr'] < p.CR ? cd['xr'] : p.CR) - 8;
      if (tr - TAG.hostW(this, o['serve']) > cd['xs'] + 30) TAG.hostTab(this, p, cd, tr, cd['cy']);
    }
  }

  @override
  void link(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> a, Map<String, dynamic> b, String how) => TAG.tieLink(this, p, a, b, how);
  @override
  void extra(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) => TAG.tieCross(this, p, L);
}

void main() {
  final themes = <BaseTheme>[BaseTheme(), ...boards['s4']!, _DrillApp(), _DrillSeogo()];
  final seeds = <String>{};
  setUpAll(() async {
    await loadMockFonts('assets/fonts');
    final dir = Directory(outDir)..createSync(recursive: true);
    // 지난 덤프(<id>.json · ids.json · widths.json)를 지운다 — 갈래 하나가 여기서 실패하면 그 덤프가 빠져 mock-tree.mjs가 실패하게
    // (남겨 두면 옛 덤프로 거짓 통과). queries.json은 mock-tree.mjs가 모은 물음이라 남긴다.
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.json') && name != 'queries.json') f.deleteSync();
    }
  });

  test('판 s4는 갈래 열넷 — 갈래 파일의 등록 차례 그대로', () {
    expect([for (final th in boards['s4']!) th.id], [
      's4-2-ga', 's4-2-ga-open', 's4-2-na', 's4-2-na-open', 's4-3-g', 's4-3-g-open', 's4-3-n', //
      's4-3-n-open', 's4-4-a', 's4-4-b', 's4-5-a', 's4-5-b', 's4-6-flag', 's4-6-flag-open',
    ]);
  });

  for (final th in themes) {
    test('${th.id} — 요소 나무를 남긴다', () {
      final screen = dump(renderScreen(th).p.svg, seeds), parts = dump(renderParts(th), seeds);
      // 빈 덤프로 대조가 거짓으로 통과하지 않게 — 화면은 이백 넘게, 부품 판은 마흔 넘게(갈래마다 300 · 70쯤).
      expect(count(screen), greaterThan(200));
      expect(count(parts), greaterThan(40));
      // 같은 갈래 객체로 다시 그려도 같은 나무 — 갈래 · tok · M에 그리기 상태가 남지 않는다(자동 번호만 다름).
      expect(renumbered(dump(renderScreen(th).p.svg, {})), renumbered(screen));
      expect(renumbered(dump(renderParts(th), {})), renumbered(parts));
      final meta = {
        'id': th.id, 'code': th.code, 'name': th.name, 'idea': th.idea, 'pro': th.pro, 'con': th.con, 'rec': th.rec, 'by': th.by, //
        'opt': th.opt, 'M': th.M, 'tok': th.tok, 'layoutRec': S4_REC[th.id],
      };
      File('$outDir/${th.id}.json').writeAsStringSync(jsonEncode({'meta': meta, 'screen': screen, 'parts': parts}));
    });
  }

  test('글 폭 표 · 갈래 목록을 남긴다(widths.json · ids.json)', () {
    final qf = File('$outDir/queries.json');
    final keys = {...seeds, if (qf.existsSync()) ...(jsonDecode(qf.readAsStringSync()) as List).cast<String>()};
    final widths = {for (final k in keys) k: widthOf(k)};
    expect(widths.length, greaterThan(200));
    File('$outDir/widths.json').writeAsStringSync(jsonEncode(widths));
    // 덤프한 갈래의 차례 — mock-tree.mjs가 원본 쪽 목록(기준 방향 + 판 갈래 + 연습)과 차례까지 맞춘다(한쪽이 적게 실려 거짓 통과하지 않게).
    File('$outDir/ids.json').writeAsStringSync(jsonEncode([for (final th in themes) th.id]));
  });
}
