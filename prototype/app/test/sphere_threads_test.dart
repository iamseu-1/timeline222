import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/gutter.dart' show Gut;
import 'package:archive_prototype/scene/paint/links.dart' show LinkColumn;
import 'package:archive_prototype/scene/paint/sphere_lines.dart';
import 'package:archive_prototype/scene/paint/sphere_threads.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/sphere_crowns.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/ui/export_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_app_fonts.dart';
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 사람 띠의 실 · 뿔 매듭(리메이크 4단계 과제 4 걸음 2 — scene/paint/sphere_threads.dart)과 왕관 표(scene/sphere_crowns.dart).
// 기준은 메이커 서고 미리보기 js/timeline.js `_drawF4Threads`(2217 ~ 2274줄) · css `.tl-f4-threads`(2491 ~ 2494줄):
//   왕관의 띠가 보이고(트랙 · 문화권 펼침 · 지도자 단) 그 지도자 칸이 4px 이상 그려졌을 때만 —
//   x = round(칸 왼쪽) + 8.5 · 점선은 사람 띠 아랫변(+ .5) + 1.5부터 띠 윗변(+ .5) − 4.5까지 · 뿔은 띠 윗변 · 점은 사람 띠 아랫변 ·
//   띠 윗변이 사람 띠 아래 4.5 + 2 안(또는 위)이면 긋지 않는다.
// 장면은 손으로 쓴 뼈대(문화권 둘 · 트랙 셋 · 지도자 단)와 손으로 넣은 왕관 표 — 타일은 비어 있어도 실은 표로 긋는다(화면 밖 띠까지 — 미리보기처럼).

int m(double year) => minuteOfYear(year).round();

/// style에 함께 실리는 순번(계약 6-2: 비트 15~26 = 순번 + 1)과 앞 칸 이음(비트 2).
int seq(int i, {bool join = false}) => (i + 1) << 15 | (join ? 4 : 0);

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 2, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 사람 띠 한 줄(kind 1) — [sphere] 밑 · [from] ~ [to]해 · 왕관 [crowns](띠 uid, 칸 순번).
Map<String, dynamic> person(String name, String sphere, double from, double to, List<(String, int)> crowns) => {
  'kind': 1, 'sphere': sphere, 'start': m(from), 'end': m(to), 'name': name, 'uid': 'fig-$name',
  'data': '[${[for (final (uid, cell) in crowns) '{"uid":"$uid","cell":$cell}'].join(',')}]',
};

/// 설령 방원권(트랙 1 · 2 — 줄 0 · 1) · 백사 해안권(트랙 3 — 줄 2). 모두 지도자 단이 있다.
Map<String, dynamic> layoutJson(List<Map<String, dynamic>> persons) => {
  'packs': [
    {'id': 1, 'name': '왕관 기록집', 'events': 0},
  ],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '설령 왕국', 'color': 0xa0bcc5, 'leader': 1, 'rail_levels': 2, 'sphere': 'north', 'rows': [row(0)]},
    {'id': 2, 'pack': 1, 'ord': 1, 'name': '북쪽 칸국', 'color': 0xc8b193, 'leader': 1, 'rail_levels': 2, 'sphere': 'north', 'rows': [row(1)]},
    {'id': 3, 'pack': 1, 'ord': 2, 'name': '남쪽 공국', 'color': 0x93b1c8, 'leader': 1, 'rail_levels': 2, 'sphere': 'south', 'rows': [row(2)]},
  ],
  'epochs': <Map<String, dynamic>>[],
  'spheres': [
    {'id': 'north', 'name': '설령 방원권', 'count': 2, 'default': true},
    {'id': 'south', 'name': '백사 해안권', 'count': 1},
  ],
  'sphereLines': persons,
};

/// 왕관 띠 셋: 설령 왕국(띠 11 · 줄 0 — 둘째 칸이 왕관 · 앞 칸과 이어짐) · 북쪽 칸국(띠 12 · 줄 1 — 첫 칸) · 남쪽 공국(띠 13 · 줄 2 — 둘째 칸은 0.1해 = 4px 아래).
Map<String, CrownBand> crownBands() => {
  'b1': CrownBand(11, 0, m(1300), m(1500), [
    CrownCell(m(1300), m(1420), seq(0)),
    CrownCell(m(1420), m(1440), seq(1, join: true)),
    CrownCell(m(1440), m(1500), seq(2, join: true)),
  ]),
  'b2': CrownBand(12, 1, m(1390), m(1480), [CrownCell(m(1400), m(1460), seq(0))]),
  'b3': CrownBand(13, 2, m(1395), m(1490), [
    CrownCell(m(1400), m(1430), seq(0)),
    CrownCell(m(1430), m(1430.1), seq(1)),
    CrownCell(m(1430.1), m(1470), seq(2)),
  ]),
};

const _w = 1920.0, _h = 1080.0;

(TimelineScene, TimelinePainter) make(List<Map<String, dynamic>> persons, {Set<int> foldedTracks = const {}, Map<String, CrownBand>? crowns, double from = 1380, double to = 1500, double height = _h}) {
  final layout = SceneLayout.fromJson(layoutJson(persons))..reduceMotion = true;
  layout.setViewState(layout.viewState.copyWith(foldedTracks: foldedTracks, foldedSpheres: const {})); // 백사 해안권(기본 펼침이 아님)도 펼침
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(_w, height)
    ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
    ..setContentHeight(layout.totalHeight);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  scene.crowns.put(crowns ?? crownBands(), layout, store: scene.storeVersion);
  controller.showRange(minuteOfYear(from), minuteOfYear(to));
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter, {double height = _h}) {
  for (int i = 0; i < 50; i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), ui.Size(_w, height));
    recorder.endRecording().dispose();
    if (!painter.text.starved) return;
  }
}

/// 은 하림(설령 방원권 · 1420 ~ 1455) — 왕관 셋(설령 왕국 둘째 칸 · 북쪽 칸국 첫 칸 · 남쪽 공국의 좁은 둘째 칸).
final harim = person('은 하림', 'north', 1420, 1455, [('b1', 1), ('b2', 0), ('b3', 1)]);

void main() {
  setUpAll(loadAppFonts);

  group('실 · 뿔 매듭의 자리', () {
    test('왕관 셋 가운데 접힌 트랙 · 4px 아래 칸은 긋지 않는다 — 남은 실 하나의 x · 점 · 뿔(.5 자리)', () {
      final (scene, painter) = make([harim], foldedTracks: {2});
      paint(painter);
      final v = scene.controller.view, layout = scene.layout;
      final drawn = painter.gutter.personBands.single.band;
      expect(painter.threads.threads, hasLength(1), reason: '북쪽 칸국은 접힌 트랙 · 남쪽 공국 둘째 칸은 1.4px');
      final t = painter.threads.threads.single;
      expect((t.band, t.cell, t.person, t.sphere), (11, 1, 'fig-은 하림', 0));
      // 앞 칸과 이어진 칸(비트 2 · 픽셀로 맞닿음)은 .5 틈이 없다 — 칸 왼쪽 = 시작 x.
      expect(t.x, v.xOf(m(1420)).roundToDouble() + 8.5);
      expect(t.dot, drawn.bottom + .5, reason: '사람 띠 아랫변');
      expect(t.knot, v.yOf(layout.rowTop(0) + layout.geo(0).bandTop).roundToDouble() + .5, reason: '띠 윗변');
      expect((t.from, t.to), (t.dot + 1.5, t.knot - 4.5));
      // 점선: 처음부터 4마다 길이 1 — 끝(뿔 꼭짓점)을 넘지 않는다.
      final dashes = t.dashes().toList();
      expect(dashes.first, (t.from, t.from + 1));
      for (int i = 1; i < dashes.length; i++) {
        expect(dashes[i].$1 - dashes[i - 1].$1, 4);
      }
      expect(dashes.last.$2, lessThanOrEqualTo(t.to));
      expect(t.to - dashes.last.$1, lessThan(4 + 1e-9));
      // 그리개 기록: 실은 모든 글자보다 먼저 그렸다.
      final notes = painter.debugSink.notes['사람 실']!;
      expect(notes, [t]);
      expect(t.labelsBefore, 0);
    });

    test('트랙을 펴면 그 왕관에도 실 — 앞 칸과 이어지지 않는 칸은 .5 틈 뒤가 칸 왼쪽', () {
      final (scene, painter) = make([harim]);
      paint(painter);
      final v = scene.controller.view, layout = scene.layout;
      expect([for (final t in painter.threads.threads) t.band], [11, 12], reason: '왕관 차례');
      final t = painter.threads.threads[1];
      expect(t.x, (v.xOf(m(1400)) + .5).roundToDouble() + 8.5);
      expect(t.knot, v.yOf(layout.rowTop(1) + layout.geo(1).bandTop).roundToDouble() + .5);
      expect(t.dot, painter.threads.threads[0].dot, reason: '한 사람 띠에서 떠난다');
    });

    test('띠 윗변이 사람 띠 위 · 아래 4.5 + 2 안이면 긋지 않는다 — 아래 문화권의 사람 띠에서 위 문화권 띠로는 없음', () {
      // 백사 해안권의 사람 — 왕관 하나는 위 문화권(설령 왕국), 하나는 제 문화권(남쪽 공국 첫 칸).
      final low = person('물결 임금', 'south', 1400, 1440, [('b1', 1), ('b3', 0)]);
      final (scene, painter) = make([low]);
      paint(painter);
      expect([for (final t in painter.threads.threads) (t.band, t.cell)], [(13, 0)]);
      final t = painter.threads.threads.single;
      expect(t.knot, greaterThan(t.dot + 4.5 + 2));
    });

    test('빽빽한 칸(칸 하나가 6px도 못 됨)에는 낱칸이 없어 긋지 않는다 · 조감도 없다 · 접힌 문화권의 사람 띠도 없다', () {
      final dense = {
        ...crownBands(),
        'b1': CrownBand(11, 0, m(1300), m(1500), [for (int i = 0; i < 800; i++) CrownCell(m(1300 + i * .25), m(1300.25 + i * .25), seq(i, join: i > 0))]),
      };
      final (scene, painter) = make([person('은 하림', 'north', 1420, 1455, [('b1', 500)])], crowns: dense);
      paint(painter);
      expect(painter.threads.threads, isEmpty);

      final (bird, birdPainter) = make([harim]);
      bird.applyConditions(bird.layout.conditions.copyWith(density: 2));
      paint(birdPainter);
      expect(birdPainter.threads.threads, isEmpty);

      final (folded, foldedPainter) = make([harim]);
      folded.layout.setViewState(folded.layout.viewState.copyWith(foldedSpheres: {'north'}));
      paint(foldedPainter);
      expect(foldedPainter.threads.threads, isEmpty);
    });

    test('같은 칸 x로 떠나는 실 여럿은 겹친 점선 조각을 한 번만 찍는다(미리보기의 svg 길 하나처럼 — 겹쳐 짙어지지 않게)', () {
      // 은 하림의 왕관 둘이 같은 띠 · 같은 칸(띠 b1 둘째 칸)과 같은 x의 다른 띠(남쪽 공국 첫 칸이 1420년에 시작)로.
      final bands = {...crownBands(), 'b3': CrownBand(13, 2, m(1395), m(1490), [CrownCell(m(1420), m(1470), seq(0, join: true)), CrownCell(m(1470), m(1480), seq(1))])};
      final (scene, painter) = make([person('은 하림', 'north', 1420, 1455, [('b1', 1), ('b3', 0)])], crowns: bands);
      paint(painter);
      final ts = painter.threads.threads;
      expect(ts, hasLength(2));
      expect(ts[0].x, ts[1].x, reason: '앞 칸과 이어진 칸 — 둘 다 1420년 x');
      final long = ts.reduce((a, b) => a.to > b.to ? a : b);
      final v = scene.controller.view;
      expect(painter.threads.drawnDashes, long.dashes(lo: v.head - 2, hi: _h + 2).length, reason: '짧은 실의 조각은 긴 실의 조각과 같은 자리');
    });

    test('머리 단 고정(과제 3 걸음 4): 내려 보아 설령 방원권 머리 단이 그림판 위에 붙으면 실은 붙은 사람 띠의 아랫변에서 떠난다', () {
      const height = 240.0;
      final (scene, painter) = make([harim], height: height);
      paint(painter, height: height);
      final v = scene.controller.view, layout = scene.layout;
      final before = painter.threads.threads.map((t) => (t.band, t.x, t.knot)).toList();
      expect(before, isNotEmpty);
      scene.controller.scrollTo(12);
      paint(painter, height: height);
      expect(v.top, 12);
      final box = layout.sphereHeadBox(0, v)!;
      expect((box.top, box.stuck), (v.head, true));
      final drawn = painter.gutter.personBands.firstWhere((d) => d.sphere == 0).band;
      expect(drawn.top, v.head + G.sphereHead, reason: '붙은 상자 안의 사람 띠 — 제자리(그림판 위 − 12)가 아니라');
      final ts = painter.threads.threads;
      expect(ts, isNotEmpty);
      const rowOf = {11: 0, 12: 1, 13: 2}; // crownBands()의 띠 번호 → 줄
      for (final t in ts) {
        final row = rowOf[t.band]!;
        expect(t.dot, drawn.bottom + .5, reason: '$t');
        expect(t.knot, v.yOf(layout.rowTop(row) + layout.geo(row).bandTop).roundToDouble() + .5);
        expect(t.knot, greaterThan(t.dot + 4.5 + 2));
      }
      // 띠 쪽(x · 뿔)은 내려 본 만큼 올라갈 뿐 칸 자리는 그대로.
      expect([for (final t in ts) (t.band, t.x)], [for (final b in before) if (ts.any((t) => t.band == b.$1)) (b.$1, b.$2)]);
    });

    test('왕관 표가 없으면(풀리기 전 · 모르는 띠) 긋지 않는다', () {
      final (scene, painter) = make([harim], crowns: const {});
      paint(painter);
      expect(painter.threads.threads, isEmpty);
      expect(painter.gutter.personBands, hasLength(1), reason: '사람 띠는 그린다');
    });

    test('점선 조각: 머리 단이 화면 위로 지나가도 보이는 몫만 — 차례(4마다)는 처음에서 센 그대로 · 끝을 넘지 않음', () {
      final t = SphereThread(300.5, 100.5, 900.5, sphere: 0, person: '', band: 1, cell: 0);
      final all = t.dashes().toList();
      expect(all.first, (102.0, 103.0));
      expect(all.last.$2, lessThanOrEqualTo(896));
      expect(all.length, 199, reason: '102 · 106 · … · 894 — 896(뿔 꼭짓점)에서 떠나는 조각은 길이 0이라 없음');
      final shown = t.dashes(lo: 500, hi: 600).toList();
      expect(shown.first.$1, 502, reason: '498 조각은 둥근 끝까지 499.6 — 500에 닿지 않음');
      expect(shown.last.$1, 598);
      expect(shown.every((d) => (d.$1 - 102) % 4 == 0), isTrue);
      expect(t.dashes(lo: 2000).toList(), isEmpty);
    });
  });

  group('글자 가림 점검(설계 4-6 #11 — 서고 전수 점검 ④ 줄 걸림을 앱 그림에)', () {
    test('실은 모든 글자보다 먼저 그리고, 바탕 없는 글자(머리 이름 · 줄 이름표)와 겹치는 곳이 0', () {
      final (scene, painter) = make([harim, person('물결 임금', 'south', 1400, 1440, [('b3', 0), ('b3', 2)])]);
      paint(painter);
      expect(painter.threads.threads.length, greaterThanOrEqualTo(3));
      for (final t in painter.threads.threads) {
        expect(t.labelsBefore, 0, reason: '$t');
      }
      expect(painter.debugLabels, isNotEmpty);
      final looks = {
        'sphereName': TextLook(Gut.sphereName, ui.FontWeight.w700, 0xd9000000),
        'sphereCount': TextLook(Gut.sphereCount, ui.FontWeight.w400, 0x73000000),
        'sphereLineLabel': SphereLinesLook.label,
        'spherePersonName': SphereLinesLook.personName,
        'spherePersonWhen': SphereLinesLook.personWhen,
      };
      final rects = [
        for (final l in painter.debugLabels)
          if (looks[l.kind] != null) ui.Rect.fromLTWH(l.at.dx, l.at.dy, painter.text.widthOf(l.text, looks[l.kind]!)!, looks[l.kind]!.size * 1.4),
      ];
      expect(rects.where((r) => r.width > 0), isNotEmpty);
      final v = scene.controller.view;
      expect(SphereThreadLayer.textHits(painter.threads.threads, rects, lo: v.head, hi: _h), 0);
      // 세는 길이 맞는지: 실이 지나는 자리에 글자 상자를 두면 센다.
      final t = painter.threads.threads.first;
      expect(SphereThreadLayer.textHits([t], [ui.Rect.fromLTWH(t.x - 10, t.from + 8, 20, 10)]), greaterThan(0));
    });
  });

  group('SVG 저장', () {
    test('실 · 뿔 · 점은 조각 + 가림막으로 적힌다 — 넘긴 그리기 호출이 없다', () async {
      Future<(SvgCanvas, String)> svgOf(Map<String, CrownBand> crowns) async {
        final (scene, painter) = make([harim], crowns: crowns);
        final text = SvgText(inner: unbudgetedText());
        paint(painter);
        final canvas = SvgCanvas(width: _w, height: _h);
        paintSceneToSvg(painter, canvas, const ui.Size(_w, _h),
            text: text, quads: SvgQuads(), dividers: SvgLines(Look.line), patterns: SvgPatterns(), ruler: Ruler());
        return (canvas, await canvas.toSvg());
      }

      final (withThreads, svg) = await svgOf(crownBands());
      final (bare, plain) = await svgOf(const {});
      expect(withThreads.skipped, isEmpty);
      final masks = RegExp('mask="url').allMatches(svg).length, masksBare = RegExp('mask="url').allMatches(plain).length;
      final (scene, painter) = make([harim]);
      paint(painter);
      final dashes = {for (final t in painter.threads.threads) for (final d in t.dashes(lo: scene.controller.view.head - 2, hi: _h + 2)) (t.x, d.$1)}.length;
      expect(painter.threads.drawnDashes, dashes);
      expect(masks - masksBare, dashes + painter.threads.threads.length * 3, reason: '점선 조각마다 하나(겹친 자리는 하나) · 실마다 뿔 칠 · 뿔 테 · 점');
      expect(bare.skipped, isEmpty);
    });
  });

  group('왕관 표(장면 곁 — sphere_crowns.dart)', () {
    SceneLayout layoutOf(List<Map<String, dynamic>> persons) => SceneLayout.fromJson(layoutJson(persons));

    test('ids_of로 띠 번호 · 줄 · 때를, cells_of로 지도자 칸을 — 다 오면 풀림을 알리고 왕관 칸 묶음(띠 번호, 순번)을 짓는다', () async {
      final asked = <Map<String, dynamic>>[];
      var ready = 0;
      final table = CrownTable(
        ask: (q) async {
          asked.add(q);
          if (q['op'] == 'ids_of') {
            return {
              'bands': [
                {'uid': 'b1', 'id': 11, 'row': 0, 'start': m(1300), 'end': m(1500)},
                {'uid': 'b3', 'id': 13, 'row': 2, 'start': m(1395), 'end': null},
              ],
              'events': const [],
            };
          }
          if (q['op'] == 'cells_of') {
            return {
              'items': q['band'] == 11
                  ? [
                      {'id': 1, 'lane': 0, 'start': m(1420), 'end': m(1440), 'name': '은 하림', 'style': seq(1, join: true), 'color': 0},
                      {'id': 0, 'lane': 0, 'start': m(1300), 'end': m(1420), 'name': '앞 임금', 'style': seq(0), 'color': 0},
                    ]
                  : [
                      {'id': 5, 'lane': 0, 'start': m(1400), 'end': m(1430), 'name': '은 하림', 'style': seq(0), 'color': 0},
                    ],
            };
          }
          throw StateError('모르는 물음');
        },
        onReady: () => ready++,
      );
      final layout = layoutOf([harim]);
      table.sync(layout, 0);
      expect(table.pending, isTrue);
      expect(table.bandOf('b1'), isNull);
      await pumpEventQueue();
      expect(table.pending, isFalse);
      expect(ready, 1);
      expect(asked.first, {'op': 'ids_of', 'uids': ['b1', 'b2', 'b3']});
      expect(asked.where((q) => q['op'] == 'cells_of').map((q) => (q['band'], q['kind'])).toSet(), {(11, 1), (13, 1)});
      final b1 = table.bandOf('b1')!;
      expect((b1.id, b1.row, b1.start, b1.end), (11, 0, m(1300), m(1500)));
      expect([for (final c in b1.leaders) c.seq], [0, 1], reason: '시작 차례');
      expect(b1.indexOf(1), 1);
      expect(b1.leaders[1].joinLeft, isTrue);
      expect(table.bandOf('b3')!.end, isNull, reason: '끝을 모르는 띠');
      expect(table.bandOf('b2'), isNull, reason: '답에 없는 띠');
      expect(table.cells, {(11, 1), (13, 1)});
      // 같은 저장소 판이면 다시 묻지 않는다 · 판이 바뀌면 다시.
      final count = asked.length;
      table.sync(layout, 0);
      expect(asked.length, count);
      table.sync(layout, 1);
      expect(table.pending, isTrue);
      await pumpEventQueue();
      expect(asked.length, greaterThan(count));
    });

    test('ids_of를 모르는 처리부면 id_of를 하나씩(app_glue placesOf와 같은 물러섬) · cells_of가 실패한 띠는 칸 없이', () async {
      final table = CrownTable(ask: (q) async {
        if (q['op'] == 'id_of') return {'band': q['uid'] == 'b1' ? 11 : 12, 'event': null, 'row': 0, 'start': 0, 'end': 10};
        throw StateError('모름');
      });
      table.sync(layoutOf([harim]), 0);
      await pumpEventQueue();
      expect(table.pending, isFalse);
      expect([table.bandOf('b1')?.id, table.bandOf('b2')?.id], [11, 12]);
      expect(table.bandOf('b1')!.leaders, isEmpty);
    });

    test('사람 띠가 없으면 묻지 않고 곧바로 빈 표 · 묻는 길이 없어도 빈 표(기다리지 않는다)', () {
      var asked = 0;
      final table = CrownTable(ask: (q) async {
        asked++;
        return const {};
      });
      table.sync(layoutOf(const []), 0);
      expect((table.pending, asked, table.cells.isEmpty), (false, 0, true));
      final none = CrownTable()..sync(layoutOf([harim]), 0);
      expect(none.pending, isFalse);
      expect(none.bandOf('b1'), isNull);
    });

    test('장면: 준비마다 맞추고, 기다리는 동안은 가라앉지 않는다(그림을 뜨는 도구가 실이 다 선 뒤에 뜨게) · 풀리면 다시 그린다', () async {
      final layout = SceneLayout.fromJson(layoutJson([harim]))..reduceMotion = true;
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(_w, _h)
        ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
        ask: (q) async => switch (q['op']) {
          'ids_of' => {
              'bands': [
                {'uid': 'b1', 'id': 11, 'row': 0, 'start': m(1300), 'end': m(1500)},
              ],
            },
          'cells_of' => {
              'items': [
                {'id': 1, 'lane': 0, 'start': m(1420), 'end': m(1440), 'name': '은 하림', 'style': seq(1), 'color': 0},
              ],
            },
          _ => throw StateError('이 검사에서는 모르는 물음'),
        },
      );
      controller.showRange(minuteOfYear(1380), minuteOfYear(1500));
      final painter = TimelinePainter(scene, text: unbudgetedText());
      paint(painter);
      expect(scene.crowns.pending, isTrue);
      expect(scene.settled, isFalse);
      expect(painter.threads.threads, isEmpty, reason: '풀리기 전에는 긋지 않는다');
      await pumpEventQueue();
      expect(scene.crowns.pending, isFalse);
      expect(scene.busy.value, isTrue, reason: '풀리면 장면을 다시 청한다');
      paint(painter);
      expect([for (final t in painter.threads.threads) (t.band, t.cell)], [(11, 1)]);
    });
  });

  group('실 비킴(명세 04 3-6 · 조사 결함 14 · 40 · 이어 주는 선 걸음 6) — 승계선 세로 기둥과 3px 안이면 칸 안에서 4px 오른쪽으로', () {
    // 실 x 100.5 · 세로 10 ~ 200(뿔 밑변) · 칸 오른쪽 끝 130.
    const x = 100.5, from = 10.0, to = 200.0, right = 130.0;

    test('세로로 겹치는 기둥이 3px 안이면 4px 오른쪽 — 오름줄이 구멍(띠 시작 + 7)으로 들고 실이 첫 칸 + 8.5에 서는 1.5px 겹침', () {
      expect(SphereThreadLayer.dodge(x, from, to, right, const [LinkColumn(99, 0, 300)]), x + 4);
      expect(SphereThreadLayer.dodge(x, from, to, right, const [LinkColumn(98, 150, 220)]), x + 4, reason: '2.5px 안 · 아래쪽만 겹쳐도');
      expect(SphereThreadLayer.dodge(x, from, to, right, const [LinkColumn(97.9, 0, 300)]), x + 4, reason: '2.6px — 백탑 → 서해 삼부 오름줄과 양리 1세 실(2026-10-25 저녁 문턱 3)');
    });

    test('기둥이 멀거나(3px 밖) 세로로 겹치지 않으면 그대로', () {
      expect(SphereThreadLayer.dodge(x, from, to, right, const [LinkColumn(97.4, 0, 300)]), x);
      expect(SphereThreadLayer.dodge(x, from, to, right, const [LinkColumn(100, 200, 300)]), x, reason: '뿔 밑변(띠 윗변) 아래에서만 — 띠 뒤 통로');
      expect(SphereThreadLayer.dodge(x, from, to, right, const []), x);
    });

    test('옮긴 뿔(반 밑변 2.5 + 테 .5)이 칸 밖으로 나가거나 옮긴 자리에도 기둥이 있으면 그대로', () {
      expect(SphereThreadLayer.dodge(x, from, to, x + 4 + 2.9, const [LinkColumn(100, 0, 300)]), x, reason: '칸 오른쪽 끝 안에 들지 않음');
      expect(SphereThreadLayer.dodge(x, from, to, x + 4 + 3, const [LinkColumn(100, 0, 300)]), x + 4, reason: '꼭 맞으면 든다');
      expect(SphereThreadLayer.dodge(x, from, to, right, const [LinkColumn(100, 0, 300), LinkColumn(105, 0, 300)]), x, reason: '옮긴 자리도 막힘');
    });
  });
}
