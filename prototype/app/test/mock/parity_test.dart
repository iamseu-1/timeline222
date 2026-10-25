import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/mock/boards.dart';
import 'package:archive_prototype/mock/render.dart';
import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:flutter_test/flutter_test.dart';

// 옮긴 갈래가 크롬의 자바스크립트 목업과 같은가(설계 3-1 '기준 그림 지키기' · 1-4 시험 1의 대조 그대로).
//   글자 밖: 다른 화소 0.5% 안 · 크게 다른(> 16) 화소 0.1% 안 · 0.05% 안(지금 그림은 0.03% 안 — 그리기 회귀를 잡으려고 덧댐)
//   줄 자리 = 배치 자리: 줄마다 글이 같고(글 폭 → 맞춤이 같은 글을 고름) 시작 x · 바탕선이 1px 안(글 폭 · 맞춤으로 정해지는 자리)
//   그린 자리와 글꼴 = 잉크 윤곽: 글줄마다 그 글 상자 안의 행 · 열 잉크가 밀림 없이 겹치고, 잉크 양의 비(Dart/크롬)가 그 갈래의 가운데값 ±30% 안
//   (Dart 회색 글자가 크롬 ClearType보다 진해 비 자체는 1이 아님 — 엉뚱한 글꼴 · 빠진 글자 · 대체 글자의 네모가 비를 벗어난다.
//   굵기 400↔700 바꿈은 잉크 단정이 일부만 잡는다 — 굵기 속성 오류는 mock-tree가 잡음).
// 기준(test/mock/goldens/<id>.png · <id>.text.json)은 prototype/scripts/mock-golden.mjs가 원본 사본(test/mock/source — 옮긴 판과 같은 지문)으로 다시 지은 판(mock-build-board.mjs)에서 뽑는다 —
// 기준을 고쳐 맞추지 않는다. 판 글꼴 = 앱 assets/fonts(Pretendard-Regular.otf sha256 3ffbacde6ab8 · Pretendard-Bold.otf 2e91915fab54) —
// 앱 글꼴이 바뀌면 기준을 다시 뽑는다. 대체 글꼴(svg_lite의 mockFallback — ▸는 Cambria Math)이 없는 PC에서는 건너뛴다.
// Dart 판의 그림과 차이 그림은 ../results/mock/parity/<id>-dart.png · <id>-diff.png에 남는다(견줄 때 보려고).

const ids = ['s4-2-ga', 's4-2-na', 's4-5-a', 's4-6-flag-open'];

void main() {
  // testWidgets의 skip은 bool뿐이라 까닭 글은 묶음(group)에 붙인다.
  final skipWhy = mockFallbackAvailable() ? false : '대체 글꼴 파일(맑은 고딕 · Cambria)이 없어 크롬 대조를 건너뜀 — ▸ 같은 글자가 크롬과 다르게 찍힘';
  group('크롬 목업 대조', () {
    setUpAll(() => loadMockFonts('assets/fonts'));
    for (final id in ids) {
      testWidgets('$id — 크롬 목업과 같다', (tester) async {
        await tester.runAsync(() async {
          final th = boards['s4']!.firstWhere((t) => t.id == id);
          final svg = renderScreen(th).p.svg;
          final dart = await renderMock(svg);
          final chrome = await decodePng('test/mock/goldens/$id.png');
          final ref = (jsonDecode(File('test/mock/goldens/$id.text.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
          final mine = mockTextBoxes(svg);
          await writePng(dart, '../results/mock/parity/$id-dart.png');
          final mask = textMask(ref, mine, 1920, 1080); // 두 쪽 글 상자의 합 + 1px
          final d = await diffOutside(dart, chrome, mask);
          await writePng(d.picture, '../results/mock/parity/$id-diff.png');
          final lines = lineCheck(ref, mine);
          final ink = inkCheck(ref, mine, await rgba(dart), await rgba(chrome), 1920, 1080);
          // ignore: avoid_print
          print('$id: $d · $lines · $ink');
          dart.dispose();
          chrome.dispose();
          d.picture.dispose();
          expect(d.any / d.pixels, lessThan(.005), reason: '$d');
          expect(d.big / d.pixels, lessThan(.001), reason: '$d');
          expect(d.big / d.pixels, lessThan(.0005), reason: '$d');
          expect(mine.length, ref.length);
          expect(lines.bad, isEmpty, reason: lines.bad.join('\n'));
          expect(ink.bad, isEmpty, reason: ink.bad.join('\n'));
        });
      });
    }
  }, skip: skipWhy);
}

/// 줄 자리(배치 자리) 대조: 줄마다 글이 같고 시작 x · 바탕선이 1px 안. 글줄 폭은 알리기만 한다 — 그림판은 글자 사이 다듬기(커닝) 없이
/// 글자 폭을 더하고 크롬의 SVG 글줄은 다듬는다(맞춤에 쓰는 mockTextWidth는 다듬는다).
class LineCheck {
  final bad = <String>[];
  double dx = 0, db = 0, dw = 0;
  String widest = '';

  @override
  String toString() => '글줄 x 최대 ${dx.toStringAsFixed(3)} · 바탕선 최대 ${db.toStringAsFixed(3)} · 폭 최대 ${dw.toStringAsFixed(3)}($widest)';
}

LineCheck lineCheck(List<Map<String, dynamic>> ref, List<MockTextBox> mine) {
  final out = LineCheck();
  for (var i = 0; i < math.min(mine.length, ref.length); i++) {
    final r = ref[i], m = mine[i];
    final x = (m.left - (r['x'] as num)).abs(), b = (m.baseline - (r['baseline'] as num)).abs(), w = (m.width - (r['w'] as num)).abs();
    out
      ..dx = math.max(out.dx, x)
      ..db = math.max(out.db, b);
    if (w > out.dw) {
      out
        ..dw = w
        ..widest = m.text;
    }
    if (m.text != r['s'] || x > 1 || b > 1) {
      out.bad.add('#$i "${m.text}" ↔ "${r['s']}" · x ${m.left.toStringAsFixed(2)} ↔ ${r['x']} · 바탕선 ${m.baseline} ↔ ${r['baseline']}'
          ' · 폭 ${m.width.toStringAsFixed(2)} ↔ ${r['w']}');
    }
  }
  return out;
}

/// 잉크 윤곽 대조(그린 자리 · 글꼴). 글줄마다 그 글 상자(크롬 상자와 Dart 상자의 합)에서 바탕 = 상자 안 가장 흔한 회색(크롬),
/// 잉크 = 바탕과 다른 만큼의 합으로 행 · 열 윤곽을 만들어
/// (가) 두 윤곽이 가장 잘 겹치는 세로 · 가로 밀림(±3px)이 0 — 가로는 그림판이 글자마다 펜을 정수 화소에 맞춘 양(round(펜) − 펜, 0.5px 안)의
///     평균을 크롬 윤곽에 먼저 옮겨 둔다(크롬은 소수 자리에 그림 — 그대로 견주면 x.46 같은 홑 글자가 1px 밀림으로 보임). 글꼴은 프리텐다드(판이 품은 것)
/// (나) 잉크 비(Dart/크롬)가 그 갈래 가운데값의 ±30% 안.
/// 크롬 잉크가 [minInk]보다 적은 글줄(거의 잘려 안 보이는 글 등)은 건너뛴다.
class InkCheck {
  final bad = <String>[];
  final ratios = <double>[];
  int skipped = 0;
  double median = 0;

  @override
  String toString() => ratios.isEmpty
      ? '잉크 대조 없음'
      : '잉크 글줄 ${ratios.length}(건너뜀 $skipped) · 비 ${ratios.reduce(math.min).toStringAsFixed(2)} ~ ${ratios.reduce(math.max).toStringAsFixed(2)}'
          '(가운데 ${median.toStringAsFixed(2)})';
}

InkCheck inkCheck(List<Map<String, dynamic>> ref, List<MockTextBox> mine, Uint8List dart, Uint8List chrome, int w, int h, {double minInk = 200}) {
  final out = InkCheck();
  double gray(Uint8List p, int x, int y) {
    final o = (y * w + x) * 4;
    return (p[o] + p[o + 1] + p[o + 2]) / 3;
  }

  /// [q]를 k만큼 옮겨 [p]와 가장 잘 겹치는 k(차이가 같으면 0에 가까운 쪽).
  int bestShift(List<double> p, List<double> q) {
    var best = 0;
    var bestErr = double.infinity;
    for (final k in const [0, -1, 1, -2, 2, -3, 3]) {
      var e = 0.0;
      for (var i = 0; i < p.length; i++) {
        final j = i + k;
        e += (p[i] - (j >= 0 && j < q.length ? q[j] : 0)).abs();
      }
      if (e < bestErr - 1e-9) {
        bestErr = e;
        best = k;
      }
    }
    return best;
  }

  /// 윤곽을 소수 [d]px 옮긴 것(사이는 곧게 이음).
  List<double> moved(List<double> p, double d) => [
    for (var i = 0; i < p.length; i++)
      () {
        final at = i - d, a = at.floor(), f = at - a;
        double v(int k) => k >= 0 && k < p.length ? p[k] : 0;
        return v(a) * (1 - f) + v(a + 1) * f;
      }(),
  ];

  final rows = <(int, String, double, double, int, int)>[];
  for (var i = 0; i < math.min(mine.length, ref.length); i++) {
    final m = mine[i], cb = (ref[i]['box'] as List).cast<num>();
    final l = math.max(0, math.min(cb[0], m.left).floor()), r = math.min(w, math.max(cb[2], m.left + m.width).ceil());
    final t = math.max(0, math.min(cb[1], m.baseline - m.height * 5 / 6).floor()), b = math.min(h, math.max(cb[3], m.baseline + m.height / 6).ceil());
    if (r <= l || b <= t) continue;
    final count = <int, int>{};
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        final g = gray(chrome, x, y).round();
        count[g] = (count[g] ?? 0) + 1;
      }
    }
    final bg = count.entries.reduce((a, e) => e.value > a.value ? e : a).key;
    List<double> profile(Uint8List p, bool byRow) {
      final out = List<double>.filled(byRow ? b - t : r - l, 0);
      for (var y = t; y < b; y++) {
        for (var x = l; x < r; x++) {
          out[byRow ? y - t : x - l] += (gray(p, x, y) - bg).abs();
        }
      }
      return out;
    }

    final cr = profile(chrome, true), dr = profile(dart, true);
    final inkC = cr.fold(0.0, (a, v) => a + v), inkD = dr.fold(0.0, (a, v) => a + v);
    if (inkC < minInk) {
      out.skipped++;
      continue;
    }
    // 그림판이 글자마다 펜을 정수 화소에 맞춰 옮긴 양의 평균(글자 폭은 그림판과 같은 셈 — 한 글자 문단의 폭 = mockTextWidth).
    // 이 셈은 가로쓰기 · 글자 사이 0 · 프리텐다드(판이 품은 글꼴)를 가정함 — 세로쓰기 · 글자 사이 간격 · 다른 글꼴의 글줄이 생기면 고쳐야 함.
    var pen = m.left, snap = 0.0, n = 0;
    for (final rune in m.text.runes) {
      if (rune != 0x20) {
        snap += pen.roundToDouble() - pen;
        n++;
      }
      pen += mockTextWidth(String.fromCharCode(rune), (ref[i]['size'] as num).toDouble(), ref[i]['wt'] as int, 'Pretendard');
    }
    snap /= math.max(1, n);
    rows.add((i, m.text, inkC, inkD, bestShift(cr, dr), bestShift(moved(profile(chrome, false), snap), profile(dart, false))));
  }
  if (rows.isEmpty) return out;
  out.ratios.addAll([for (final r in rows) r.$4 / r.$3]);
  final sorted = [...out.ratios]..sort();
  out.median = sorted[sorted.length ~/ 2];
  for (final (i, s, inkC, inkD, dy, dx) in rows) {
    final ratio = inkD / inkC;
    if (dy != 0 || dx != 0 || (ratio - out.median).abs() > out.median * .3) {
      out.bad.add('#$i "$s" · 밀림 세로 $dy 가로 $dx · 잉크 ${inkD.round()} / ${inkC.round()} = ${ratio.toStringAsFixed(2)}(가운데 ${out.median.toStringAsFixed(2)})');
    }
  }
  return out;
}

Future<Uint8List> rgba(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

Future<ui.Image> decodePng(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<void> writePng(ui.Image img, String path) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

/// 글자 자리를 가린 판(1 = 견주지 않음): 크롬의 글 상자와 Dart 글줄의 상자(글 상자 높이는 크기 × 1.2 — 바탕선 위 5/6 · 아래 1/6,
/// 크롬의 SVG 글 상자와 같은 짜임)의 합 + 둘레 1px. 글자는 줄 자리로 따로 견준다.
Uint8List textMask(List<Map<String, dynamic>> ref, List<MockTextBox> mine, int w, int h) {
  final m = Uint8List(w * h);
  void cover(double l, double t, double r, double b) {
    final x0 = math.max(0, l.floor() - 1), x1 = math.min(w, r.ceil() + 1), y0 = math.max(0, t.floor() - 1), y1 = math.min(h, b.ceil() + 1);
    for (var y = y0; y < y1; y++) {
      m.fillRange(y * w + x0, y * w + math.max(x0, x1), 1);
    }
  }

  for (final r in ref) {
    final box = (r['box'] as List).cast<num>();
    cover(box[0].toDouble(), box[1].toDouble(), box[2].toDouble(), box[3].toDouble());
  }
  for (final b in mine) {
    cover(b.left, b.baseline - b.height * 5 / 6, b.left + b.width, b.baseline + b.height / 6);
  }
  return m;
}

/// 글자 밖 화소 대조: 견준 화소 수 · 다른 화소(빨강 · 초록 · 파랑 가운데 하나라도 다름) · 크게 다른 화소(차이 > 16)와
/// 크게 다른 화소의 둘레 · 차이 그림(흰색 = 같음 · 회색 = 가림 · 노랑 = 조금 다름 · 빨강 = 크게 다름).
class Diff {
  Diff(this.pixels, this.any, this.big, this.bigBox, this.picture);
  final int pixels, any, big;
  final ui.Rect? bigBox;
  final ui.Image picture;

  @override
  String toString() => '견준 화소 $pixels · 다름 $any(${(any / pixels * 100).toStringAsFixed(3)}%) · 크게 다름 $big(${(big / pixels * 100).toStringAsFixed(3)}%)'
      '${bigBox == null ? '' : ' · 크게 다른 곳 ${bigBox!.left.toInt()},${bigBox!.top.toInt()} ~ ${bigBox!.right.toInt()},${bigBox!.bottom.toInt()}'}';
}

Future<Diff> diffOutside(ui.Image a, ui.Image b, Uint8List mask) async {
  expect([a.width, a.height], [b.width, b.height]);
  final w = a.width, h = a.height;
  final pa = (await a.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final pb = (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final out = Uint8List(w * h * 4);
  var pixels = 0, any = 0, big = 0;
  int? l, t, r, bt;
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    var c = [255, 255, 255];
    if (mask[i] == 1) {
      c = [230, 230, 230];
    } else {
      pixels++;
      var d = 0;
      for (var ch = 0; ch < 3; ch++) {
        d = math.max(d, (pa[o + ch] - pb[o + ch]).abs());
      }
      if (d > 0) {
        any++;
        c = [255, 210, 0];
      }
      if (d > 16) {
        big++;
        c = [230, 0, 0];
        final x = i % w, y = i ~/ w;
        l = math.min(l ?? x, x);
        r = math.max(r ?? x, x);
        t = math.min(t ?? y, y);
        bt = math.max(bt ?? y, y);
      }
    }
    out
      ..[o] = c[0]
      ..[o + 1] = c[1]
      ..[o + 2] = c[2]
      ..[o + 3] = 255;
  }
  final buf = await ui.ImmutableBuffer.fromUint8List(out);
  final desc = ui.ImageDescriptor.raw(buf, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await desc.instantiateCodec();
  final picture = (await codec.getNextFrame()).image;
  codec.dispose();
  desc.dispose();
  buf.dispose();
  return Diff(pixels, any, big, l == null ? null : ui.Rect.fromLTRB(l.toDouble(), t!.toDouble(), r! + 1.0, bt! + 1.0), picture);
}
