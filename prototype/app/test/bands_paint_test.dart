import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/reserved.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 띠 층(paint/bands.dart)의 검사. 값은 docs/명세-3단계/01-띠의-표현.md와 기준 덤프(prototype/results/dom · dom-r1)에서 왔다.

const m = 1000000.0;

/// 명세 0-3절이 확인한 보기: `--c ≈ #acb4ca`인 띠는 바탕 `#e8e7e6` · 테두리 `#959bab`(실측 A-1).
const sample = 0xacb4ca;

int look({int kind = 0, int cert = 1, int hs = 0, bool range = false, bool dep = false, bool under = false, bool folded = false}) =>
    kind |
    cert << BandLook.certShift |
    (range ? BandLook.hasRange : 0) |
    hs << BandLook.hsShift |
    (dep ? BandLook.famDep : 0) |
    (under ? BandLook.under : 0) |
    (folded ? BandLook.folded : 0);

String hex(int argb) => argb.toRadixString(16).padLeft(8, '0');

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 160, 'band_top': 19, 'band_h': 141, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1), row(2)]},
  ],
});

/// 줄 1이 **접힌 민족 줄**(kind 3)인 3판 배치 — 그 줄에는 띠도 탭도 그리지 않는다.
SceneLayout folded() {
  Map<String, dynamic> at(int id, int kind) => {...row(id), 'kind': kind, 'cats': <int>[]};
  return SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
    'tracks': [
      {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [at(0, RowKind.normal), at(1, RowKind.foldedGroup), at(2, RowKind.normal)]},
    ],
  });
}

/// 1920×1080 · 단계 9의 타일 하나로 장면을 만든다. [build]가 그 타일에 띠를 넣고, [from]은 화면 왼쪽 끝의 시각(분)이다.
(TimelineScene, TimelinePainter) make(void Function(TileBuilder) build, {double from = 0, SceneLayout? shape}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(480);
  final ppm = 32 / bucketMinutes(9);
  controller.showRange(from, from + (1920 - SceneView.gutter) / ppm);
  final builder = TileBuilder(level: 9, x: 0, chunk: 0);
  build(builder);
  final bytes = builder.build();
  final scene = TimelineScene(
    controller: controller,
    layout: shape ?? layout(),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  scene.hide.add('fade');
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  for (int i = 0; i < 20 && (i == 0 || painter.text.starved); i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
}

/// 검사용 기록에서 '띠' 줄을 띠 번호로 찾는다.
String noteOf(TimelinePainter painter, int id) =>
    (painter.debugSink.notes['띠'] ?? const []).map((v) => '$v').firstWhere((s) => s.startsWith('$id '));

void main() {
  group('띠의 색과 선 — css의 차례 그대로', () {
    test('보통 띠는 바탕 c 24% · 테두리 oklab 84%, 모서리 10', () {
      final tone = BandLayer.toneOf(sample, look(), fuzzy: false);
      expect(hex(tone.fill), 'ffebedf2', reason: '흰 바탕에 c 24% — 브라우저의 color-mix(in srgb, #abb3c9 24%, #fff)');
      // 명세가 바탕에서 거꾸로 푼 --c는 1/255쯤 어긋나므로 테두리는 그만큼 넉넉하게 본다.
      for (final shift in [16, 8, 0]) {
        expect(((tone.edge >> shift) & 0xff).toDouble(), closeTo((0xff878d9f >> shift) & 0xff, 2), reason: '브라우저의 color-mix(in oklab, #abb3c9 84%, #000) = #878d9f');
      }
      expect(tone.radius, 10);
      expect(tone.stroke, EdgeStroke.solid);
      expect(tone.hatch, isFalse);
      expect(tone.fog, 0);
    });

    test('종류마다 바탕이 다르고 조직체는 점선 · 문화는 옅은 실선(건의 2026-10-15 4번 A — 끊긴 선은 관계선만)에 반지름 12', () {
      int fill(int kind, {bool dep = false}) => BandLayer.toneOf(sample, look(kind: kind, dep: dep), fuzzy: false).fill;
      expect(hex(fill(BandKind.vassal)), hex(mixSrgb(0xff000000 | sample, Look.paper, .09)));
      expect(hex(fill(BandKind.tributary, dep: true)), hex(mixSrgb(0xff000000 | sample, Look.paper, .09)), reason: '종속 갈래는 모두 9%');
      expect(hex(fill(BandKind.federation)), hex(mixSrgb(0xff000000 | sample, Look.paper, .06)));
      expect(hex(fill(BandKind.org)), hex(mixSrgb(0xff000000 | sample, Look.paper, .10)));
      expect(hex(fill(BandKind.era)), hex(mixSrgb(0xff000000 | sample, Look.paper, .10)));
      expect(hex(fill(BandKind.culture)), hex(mixSrgb(0xff000000 | sample, Look.paper, .09)));
      expect(BandLayer.toneOf(sample, look(kind: BandKind.org), fuzzy: false).stroke, EdgeStroke.dotted);
      final culture = BandLayer.toneOf(sample, look(kind: BandKind.culture), fuzzy: false);
      expect(culture.stroke, EdgeStroke.solid);
      expect(culture.radius, 12);
      expect(culture.dots, isTrue);
      expect(hex(culture.edge), hex(mixSrgb(over(withAlpha(mixOklab(0xff000000 | sample, Look.ink, .92), .70), Look.paper), Look.paper, BandLayer.unsureEdge)), reason: '테 빛깔을 종이와 반씩 섞은 고른 색');
      expect(hex(BandLayer.toneOf(sample, look(kind: BandKind.era), fuzzy: false).edge), hex(withAlpha(mixOklab(0xff000000 | sample, Look.ink, .92), .60)));
    });

    test('미정의 6%는 제 바탕 규칙이 없는 보통 띠에만 이긴다(명세 5-3 열둘째)', () {
      expect(hex(BandLayer.toneOf(sample, look(), fuzzy: true).fill), hex(mixSrgb(0xff000000 | sample, Look.paper, .06)));
      expect(hex(BandLayer.toneOf(sample, look(kind: BandKind.org), fuzzy: true).fill), hex(mixSrgb(0xff000000 | sample, Look.paper, .10)));
      expect(hex(BandLayer.toneOf(sample, look(dep: true), fuzzy: true).fill), hex(mixSrgb(0xff000000 | sample, Look.paper, .09)));
      expect(BandLayer.toneOf(sample, look(), fuzzy: true).stroke, EdgeStroke.solid);
      expect(hex(BandLayer.toneOf(sample, look(), fuzzy: true).edge), hex(mixSrgb(over(mixOklab(0xff000000 | sample, Look.ink, .84), Look.paper), Look.paper, BandLayer.unsureEdge)), reason: '미정 띠는 옅은 실선 테');
    });

    test('전승 연대의 빗금은 띠 전체에, 연대 폭이 있거나 바탕이 옅은 종류에는 붙지 않는다', () {
      final legend = BandLayer.toneOf(sample, look(cert: BandLook.certLegend), fuzzy: false);
      expect(legend.hatch, isTrue);
      expect(legend.stroke, EdgeStroke.solid);
      expect(hex(legend.hatchColor), hex(mixSrgb(0xff000000 | sample, Look.paper, .14)));
      expect(hex(legend.fill), hex(mixSrgb(0xff000000 | sample, Look.paper, .05)));
      expect(BandLayer.toneOf(sample, look(cert: BandLook.certLegend, range: true), fuzzy: false).hatch, isFalse, reason: '연대 폭을 적었으면 그 구간만');
      expect(BandLayer.toneOf(sample, look(cert: BandLook.certLegend, dep: true), fuzzy: false).hatch, isFalse, reason: '바탕이 이미 옅은 종류');
      expect(BandLayer.toneOf(sample, look(cert: BandLook.certEstimated), fuzzy: false).stroke, EdgeStroke.solid);
      expect(hex(BandLayer.toneOf(sample, look(cert: BandLook.certEstimated), fuzzy: false).edge), hex(mixSrgb(over(mixOklab(0xff000000 | sample, Look.ink, .84), Look.paper), Look.paper, BandLayer.unsureEdge)));
      expect(hex(BandLayer.toneOf(sample, look(), fuzzy: false).edge), hex(mixOklab(0xff000000 | sample, Look.ink, .84)), reason: '확실한 띠의 테는 그대로');
      expect(BandLayer.toneOf(sample, look(cert: BandLook.certEstimated), fuzzy: false).hatch, isFalse);
    });

    test('실재성: 전설 · 반전설은 안개, 부정됨은 회색 안개(묶음 5 · 5번), 논쟁은 보통 띠와 같다', () {
      final legendary = BandLayer.toneOf(sample, look(hs: BandLook.hsLegendary), fuzzy: false);
      expect(legendary.fog, .24);
      expect(hex(legendary.fill), hex(mixSrgb(0xff000000 | sample, Look.paper, .24)));
      expect(BandLayer.toneOf(sample, look(hs: BandLook.hsSemi, dep: true), fuzzy: false).fog, .10);
      expect(BandLayer.toneOf(sample, look(hs: BandLook.hsSemi, kind: BandKind.federation), fuzzy: false).fog, .07);
      expect(BandLayer.toneOf(sample, look(hs: BandLook.hsSemi), fuzzy: true).fog, .07);
      final refuted = BandLayer.toneOf(sample, look(hs: BandLook.hsRefuted), fuzzy: false);
      expect(refuted.fog, .24, reason: '부정됨 = 전설과 같은 안개를 색 없이 회색으로(감독 결정 A · common.css 실재성 블록의 .hs-refuted)');
      expect(hex(refuted.fill), hex(mixSrgb(Look.muted, Look.paper, .24)));
      expect(hex(refuted.edge), hex(withAlpha(Look.muted, .50)));
      expect(BandLayer.toneOf(sample, look(hs: BandLook.hsRefuted, kind: BandKind.federation), fuzzy: false).fog, .07);
      expect(BandLayer.toneOf(sample, look(hs: BandLook.hsRefuted, dep: true), fuzzy: false).fog, .10);
      final disputed = BandLayer.toneOf(sample, look(hs: BandLook.hsDisputed), fuzzy: false);
      final plain = BandLayer.toneOf(sample, look(), fuzzy: false);
      expect((disputed.fill, disputed.edge, disputed.stroke), (plain.fill, plain.edge, plain.stroke));
    });

    test('부흥·저항 세력에만 깃대, 바탕 문화는 종이가 비치는 점무늬 띠', () {
      expect(BandLayer.toneOf(sample, look(kind: BandKind.movement), fuzzy: false).pole, isNot(0));
      expect(BandLayer.toneOf(sample, look(kind: BandKind.exile), fuzzy: false).pole, 0);
      final under = BandLayer.toneOf(sample, look(under: true), fuzzy: false);
      expect(under.dots, isTrue);
      expect(under.radius, 12);
      expect(under.stroke, EdgeStroke.solid);
      expect(hex(under.edge), hex(mixSrgb(over(withAlpha(mixOklab(0xff000000 | sample, Look.ink, .92), .70), Look.paper), Look.paper, BandLayer.unsureEdge)));
      expect(hex(under.fill), hex(withAlpha(0xff000000 | sample, .09)), reason: '줄 바탕이 비친다');
    });
  });

  group('자리와 모양', () {
    // 꼬리표 갈래 E(설계 4-1 '실제 띠에 입힘'): 오른쪽 끝은 늘 직각, 왼쪽은 갈래의 꼴(다스림 = 귀 모따기 5).
    // 미정인 쪽은 옅어지며 열리므로 직각이다(예전 둥근 22 대신).
    test('미정 끝은 44px 꼬리가 붙고 그쪽 귀는 직각 — 확정된 띠는 왼쪽 모따기 5 · 오른쪽 직각', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 8 * m, '별여울국', color: sample, flags: Tile.fuzzyStart | Tile.fuzzyEnd, look: look());
        t.band(2, 1, 2 * m, 8 * m, '해솔국', color: sample, look: look());
      });
      await settle(scene, painter);
      final v = scene.controller.view;
      final fuzzy = painter.debugBands.firstWhere((b) => b.id == 1);
      final plain = painter.debugBands.firstWhere((b) => b.id == 2);
      expect(fuzzy.rect.left, closeTo(plain.rect.left - 44, .01));
      expect(fuzzy.rect.right, closeTo(plain.rect.right + 44, .01));
      expect(plain.rect.left, closeTo(v.xOf(2 * m), .01));
      expect(noteOf(painter, 1), contains('반지름=0/0'), reason: '미정 쪽은 옅어지며 열린다 — 귀가 없다');
      expect(noteOf(painter, 1), contains('옅은끝=44/44'));
      expect(noteOf(painter, 2), contains('반지름=12/0'), reason: '다스림의 꼬리표: 왼쪽 귀 모따기(키에 맞춤 — 이 띠는 키 120 넘어 12) · 오른쪽 직각');
      expect(noteOf(painter, 2), contains('옅은끝=0/0'));
    });

    test('화면 왼쪽 밖에서 시작한 띠는 그쪽 귀를 펴고 꼬리를 그만큼 줄인다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 0, 8 * m, '별여울국', color: sample, flags: Tile.fuzzyStart, look: look());
      });
      await settle(scene, painter);
      // 미정 꼬리 44px 가운데 화면 밖으로 나간 만큼이 줄어든다(T:6787). 왼쪽은 미정 · 화면 밖이라 직각, 오른쪽은 꼬리표라 늘 직각.
      expect(noteOf(painter, 1), contains('반지름=0/0'));
      expect(noteOf(painter, 1), contains('옅은끝=1/0'));
    });

    test('연대 폭(구역 19)은 띠의 자리를 넓히고 그 구간에만 무늬를 깐다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 4 * m, 8 * m, '별여울국', color: sample, look: look(range: true));
        t.item(19, 1, 0, 2 * m, 4 * m, ref: 1, color: sample, a: 0, b: 0);
        t.band(2, 1, 4 * m, 8 * m, '해솔국', color: sample, look: look());
      });
      await settle(scene, painter);
      final withZone = painter.debugBands.firstWhere((b) => b.id == 1);
      final plain = painter.debugBands.firstWhere((b) => b.id == 2);
      final v = scene.controller.view;
      expect(withZone.rect.left, closeTo(v.xOf(2 * m), .01), reason: 'bandStart는 startRange[0]이다(명세 5-3 둘째)');
      expect(plain.rect.left, closeTo(v.xOf(4 * m), .01));
      expect(withZone.rect.right, closeTo(plain.rect.right, .01));
    });

    test('타일에 걸친 띠는 이음매에 모서리도 세로 테두리도 두지 않는다', () async {
      final builderRight = TileBuilder(level: 9, x: 1, chunk: 0);
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-2000 * m, 2000 * m)
        ..setContentHeight(480);
      final ppm = 32 / bucketMinutes(9);
      final span = (1920 - SceneView.gutter) / ppm;
      controller.showRange(67108864 - span / 2, 67108864 + span / 2);
      final left = TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, 67108864 - span / 4, 67108864, '별여울국', color: sample, flags: Tile.clipRight, look: look());
      builderRight.band(1, 0, 0, span / 4, '별여울국', color: sample, flags: Tile.clipLeft, look: look());
      final data = {(9, 0): left.build(), (9, 1): builderRight.build()};
      final scene = TimelineScene(
        controller: controller,
        layout: layout(),
        fetchTile: (level, x, chunk, packs) async => data[(level, x)] ?? TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      scene.hide.add('fade');
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      await settle(scene, painter);
      final pieces = painter.debugBands.where((b) => b.id == 1).toList()..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      expect(pieces.length, 2);
      // 꼬리표: 진짜 왼쪽 끝만 모따기, 이음매 쪽(뒤 조각의 왼쪽)은 귀가 없다. 오른쪽은 진짜 끝도 늘 직각이다.
      expect((pieces[0].roundLeft, pieces[0].roundRight), (true, false));
      expect((pieces[1].roundLeft, pieces[1].roundRight), (false, false));
      expect(pieces[0].rect.right, pieces[1].rect.left, reason: '이음매는 같은 정수 px에서 만난다');
      // 이음매의 양쪽 1px은 테두리가 아니라 바탕 — 세로 테두리를 긋지 않는다(띠 가운데 높이 — 머리 이름 · 칸이 없는 자리).
      final pixels = await render(painter);
      final seam = pieces[1].rect.left, y = pieces[1].rect.center.dy;
      int at(double x) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      final fill = BandLayer.toneOf(sample, look(), fuzzy: false).fill;
      expect(at(seam - .5), rgba(fill), reason: '앞 조각의 오른쪽 끝(이음매)에 세로 테두리가 없다');
      expect(at(seam + .5), rgba(fill), reason: '뒤 조각의 왼쪽 끝(이음매)에 세로 테두리가 없다');
      // 이름은 앞 조각에만 한 번.
      expect(painter.debugLabels.where((l) => l.kind == 'tab' && l.text == '별여울국').length, 1);
    });
  });

  // 꼬리표 갈래 E(설계 4-1 '구멍과 꼬리 마름모' · '실제 띠에 입힘'): 띠 위 탭 줄이 없어지고 이름이 띠 안 **머리**에 든다 —
  // 리메이크 2부 '두 장 ㄴ'부터 머리 = 이름 색줄 `G.head` 14(구멍 · 이름이 그 세로 가운데 7). 이 묶음의 배치(줄 종류 없음 · 고정 생김새)는 몸통이 없는 한 장 꼬리표지만
  // 이름 자리는 같은 식이다. 리메이크 2부(목업 서고): 머리에는 이름만 — 종류 · 실재성 · 지위 딱지('tabTag')는 그리지 않는다(상세 창에서). 검사 기록의 글 종류는 예전 그대로 'tab'이다.
  group('꼬리표 머리의 이름', () {
    // 이름이 차지한 구간의 오른쪽 끝 − 이름의 왼쪽(딱지가 있으면 그만큼 길어진다).
    Future<double> nameSpan(void Function(TileBuilder) build) async {
      final (scene, painter) = make(build);
      await settle(scene, painter);
      expect(painter.debugLabels.where((l) => l.kind == 'tab').single.text, '별여울국');
      expect(painter.debugLabels.where((l) => l.kind == 'tabTag'), isEmpty, reason: '머리에 딱지가 없다');
      return painter.bands.headNameEnd[1]! - painter.debugLabels.firstWhere((l) => l.kind == 'tab').at.dx;
    }

    test('머리에는 이름만 — 종류 · 실재성 · 지위 딱지를 그리지 않고 자리도 잡지 않는다', () async {
      final tagged = await nameSpan((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look(kind: BandKind.federation, hs: BandLook.hsSemi), tag: '연맹|반전설|대공국', sub: 3);
      });
      final plain = await nameSpan((t) => t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look()));
      expect(tagged, closeTo(plain, .01), reason: '이름이 차지한 구간은 이름 끝에서 닫힌다(딱지 몫 없음)');
    });

    test('종속 갈래 · 부정된 띠도 머리에 딱지가 없다', () async {
      await nameSpan((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look(kind: BandKind.tributary, dep: true, hs: BandLook.hsRefuted), tag: '부정');
      });
    });

    test('자리가 모자라면 첫 글자만, 그것도 안 되면 탭이 없다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울 은빛 나루 연맹국', color: sample, look: look());
        t.band(2, 1, 2 * m, 2.6 * m, '별여울 은빛 나루 연맹국', color: sample, look: look());
        t.band(3, 2, 2 * m, 2.16 * m, '별여울 은빛 나루 연맹국', color: sample, look: look());
      });
      await settle(scene, painter);
      final tabs = painter.debugLabels.where((l) => l.kind == 'tab').toList();
      expect(tabs.map((l) => l.text).toList(), ['별여울 은빛 나루 연맹국', '별'], reason: '온 이름 → 첫 글자 → 없음');
    });

    test('화면 왼쪽 밖에서 시작한 띠의 머리 이름은 화면 끝 6px 안쪽에 붙는다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 0, 10 * m, '별여울국', color: sample, look: look());
      }, from: 2 * m);
      await settle(scene, painter);
      final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab');
      // 띠의 진짜 왼쪽 끝 + 14(구멍 7 + 7)는 화면 밖 — 화면 왼쪽 + 6이 더 크다.
      expect(tab.at.dx, SceneView.gutter + Look.tabInset, reason: '화면 가장자리에서 6px 안쪽(탭 어깨 · 안 여백 없이)');
    });

    test('머리 이름은 구멍(띠 왼쪽 끝 + 7) 오른쪽 7에서 · 이름 색줄 14의 가운데에 — 구멍 위에 걸치지 않는다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
      });
      await settle(scene, painter);
      final rect = painter.debugBands.single.rect;
      final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab');
      // x = 띠 왼쪽 + 구멍(이름 색줄 14의 귀에 맞춤 — 모따기 5 + 2 = 7) + 7 · 글줄 윗변 = 윗변 + 7(색줄 14의 가운데 = 구멍 높이) − 9 × 0.6.
      // 구멍은 띠 전체 키가 아니라 색줄 키로 잰다 — 키 141인 이 띠의 귀(14)로 재면 이름이 7px 더 밀린다.
      final hole = TagLook.holeAt(TagEnd.cham, G.head);
      expect(hole, TagLook.holeX);
      expect(tab.at.dx, closeTo(rect.left + hole + TagLook.nameGap, .01), reason: '구멍 가운데에서 7 오른쪽');
      expect(tab.at.dy, closeTo(rect.top + G.head / 2 - 9 * .6, .01), reason: '이름 색줄 14의 가운데(구멍 높이 7)에 글줄 가운데');
      expect(G.head / 2, TagLook.holeY);
      expect(painter.bands.hitBands(rect.left + hole, rect.top + TagLook.holeY)?.tab, isFalse, reason: '구멍 자리는 이름(탭)이 아니라 띠 몸통');
      // 이름이 차지한 구간(앞뒤 4) — 플래그 · 단추 층(조감)이 비킨다.
      final end = painter.bands.headNameEnd[1]!;
      expect(end, greaterThan(tab.at.dx + 20), reason: '이름의 오른쪽 끝');
      expect(painter.bands.headNameZones[0]!.single, (tab.at.dx - 4, end + 4));
      // 두 장 꼬리표(리메이크 2부): 이름은 색줄에, 사건은 몸통의 흰 사건 칸에 — 다른 줄이라 사건 이름 · 점이 머리 이름을 비켜 가지 않는다
      // (예전: 첫 글줄에 비킬 구간 하나 · 출처 'names'). 출처 'names'는 빈 채로 남는다.
      final zones = ReservedZones.of(scene);
      expect(zones.at(0).length, zones.at(0, except: 'names').length, reason: '머리 이름은 사건 줄을 막지 않는다: ${zones.at(0)}');
    });
  });

  // 리메이크 2부 '두 장 ㄴ'(계약 3절 머리 상자): 줄의 띠 = 이름 색줄 `G.head` 14 + 몸통(칸 층 `G.floor` 14씩 → 흰 사건 칸 `G.evLine` 18 × 글줄).
  // 띠마다 제 칸 층만 몸통 윗변부터 맞붙이고 사건 칸은 그 바로 밑(`TagLook.compactOf` · `eventLift`) — 칸이 없는 띠도 색줄 + 사건 칸.
  // 위 묶음들의 배치는 줄 종류가 없는 고정 생김새라 몸통이 없는 한 장 꼬리표다 — 여기서는 줄 값(`fig_wide` 비트 19)이 실린 새 저장소로 본다.
  group('한 장 꼬리표(예전 두 장 — 건의 2026-10-15 3번)', () {
    /// 줄 하나: 줄 값으로 칸 층을 두고(비트 19) 그 줄에 지도자 칸이 있다(비트 17). 기간 막대 단 수 + 1 = 1(비트 3~5 — 새 저장소 표시).
    SceneLayout twoPiece() => SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'leader': 0,
          'rows': [
            {...row(0), 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
              'fig_wide': (1 << 3) | (1 << 17) | (1 << 19), 'dep': 0, 'zones': 0, 'hem': 0},
          ],
        },
      ],
    });

    test('색줄 14 아래 몸통 — 지도자 층을 가진 띠는 그 층 + 사건 칸, 칸이 없는 띠는 색줄 + 사건 칸(남의 층만큼 몸통이 짧다)', () async {
      // 띠 look 비트 20 = 그 띠에 칸이 있다 · 21 + 5 = 지도자 층을 가진다.
      final withLeader = look() | 1 << 20 | 1 << (21 + 5);
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 5 * m, '별여울국', color: sample, look: withLeader);
        t.band(2, 0, 6 * m, 9 * m, '해솔국', color: sample, look: look());
      }, shape: twoPiece());
      await settle(scene, painter);
      final geo = scene.layout.geo(0);
      expect(geo.bodyTop - geo.bandTop, G.head, reason: '몸통 윗변 = 이름 색줄 아랫변');
      expect(geo.leaderTop, geo.bodyTop, reason: '그 줄의 첫 칸 층');
      expect(geo.floorEnd - geo.bodyTop, G.floor);
      expect(geo.textTop, geo.floorEnd, reason: '흰 사건 칸은 칸 뭉치 바로 밑');
      expect(geo.lineH, G.evLine);
      expect(geo.bandHeight, G.head + G.floor + G.evLine, reason: '자동 밀도는 글줄 하나 · 기간 막대 · 인물 단 없음');
      expect(noteOf(painter, 1), contains('한 장 색줄=14 몸통=32 칸=true'));
      expect(noteOf(painter, 2), contains('한 장 색줄=14 몸통=18 칸=false'), reason: '칸이 없는 띠도 색줄 + 사건 칸(감독 "사건 부분은 항상")');
      final a = painter.debugBands.firstWhere((b) => b.id == 1), b = painter.debugBands.firstWhere((b) => b.id == 2);
      expect(a.rect.height, G.head + G.floor + G.evLine);
      expect(b.rect.height, G.head + G.evLine, reason: '사건 칸을 남의 층(지도자 14)만큼 올린다');
      expect(TagLook.eventLift(geo, withLeader, oldStore: false, loose: false), 0);
      expect(TagLook.eventLift(geo, look(), oldStore: false, loose: false), G.floor);
      expect(TagLook.eventLift(geo, look(), oldStore: false, loose: true), 0, reason: '넉넉하게는 올리지 않는다');
      expect(TagLook.bodyBottom(geo, look(), oldStore: true), geo.bandTop + geo.bandHeight, reason: '옛 저장소는 몸통이 늘 띠 아랫변까지');
      // 한 장의 세 켜(감독 건의 2026-10-15 3번): 이름 색줄 = 띠 칠 · 가운데 켜 = 그 50% · 사건 칸 = 종이, 색줄 아랫변의 금은 테보다 옅다.
      final pixels = await render(painter);
      int at(double x, double y) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      final tone = BandLayer.toneOf(sample, withLeader, fuzzy: false), x = a.rect.right - 30, top = a.rect.top; // 이름 글자를 비킨 자리
      expect(at(x, top + 4), rgba(tone.fill), reason: '이름 색줄이 가장 진하다');
      expect(at(x, top + G.head + G.floor / 2), rgba(mixSrgb(tone.fill, Look.paper, BandLayer.bodyTint)), reason: '가운데 켜는 색줄 칠의 절반 한 색');
      expect(at(x, top + G.head + G.floor + G.evLine / 2), rgba(Look.paper), reason: '사건 칸은 흰색');
      expect(at(x, top + G.head - 1), rgba(mixSrgb(over(tone.edge, Look.paper), Look.paper, BandLayer.innerLine)), reason: '켜 사이 금은 테보다 옅은 고른 색');
      expect(at(x, a.rect.bottom + 3), rgba(Look.ground), reason: '띠 밖은 그림판 바탕(흰색이 아님)');
    });
  });

  test('띠와 탭은 도형 묶음으로만 그린다 — drawRRect · drawPath · clipRect를 부르지 않는다', () async {
    final (scene, painter) = make((t) {
      for (int k = 0; k < 3; k++) {
        t.band(k + 1, k, (2 + k) * m, (8 + k) * m, '별여울국\$k', color: sample,
            look: look(kind: k == 0 ? BandKind.federation : (k == 1 ? BandKind.culture : BandKind.movement), cert: BandLook.certLegend, hs: k == 2 ? BandLook.hsLegendary : 0),
            tag: '연맹');
      }
    });
    await settle(scene, painter);
    final spy = _SpyCanvas();
    painter.paint(spy, const Size(1920, 1080));
    expect(painter.debugBands.length, 3);
    expect((spy.rrects, spy.paths), (0, 0), reason: '둥근 네모와 길은 하나하나가 따로 처리돼 칠하기가 한도를 넘는다');
  });

  group('그려진 픽셀', () {
    test('연맹은 테두리 안쪽에 종이빛 2px · 테 55% 1px의 겹줄이 있다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 8 * m, '별여울 등불연맹', color: sample, look: look(kind: BandKind.federation));
      });
      await settle(scene, painter);
      final pixels = await render(painter);
      final rect = painter.debugBands.single.rect;
      final y = rect.center.dy, ground = rect.top + 200;
      final tone = BandLayer.toneOf(sample, look(kind: BandKind.federation), fuzzy: false);
      int at(double x) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      int want(double x, int color) => filmed(pixels, x, ground, color);
      expect(at(rect.left + .5), want(rect.left + .5, tone.edge), reason: '바깥 1px은 테두리');
      expect(at(rect.left + 1.5), want(rect.left + 1.5, Look.paper), reason: '그 안쪽 2px은 종이빛');
      expect(at(rect.left + 2.5), want(rect.left + 2.5, Look.paper));
      expect(at(rect.left + 3.5), want(rect.left + 3.5, over(withAlpha(tone.edge, .55), tone.fill)), reason: '그다음 1px은 테 55%');
      expect(at(rect.left + 4.5), want(rect.left + 4.5, tone.fill), reason: '그 안은 바탕');
    });

    test('전설 · 반전설의 안개는 투명도로 사라지지 않고 고른 옅은 색 — 전설이 반전설보다 옅다(감독 건의 2026-10-15 2번)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 8 * m, '두 달의 궁정', color: sample, look: look(hs: BandLook.hsLegendary));
        t.band(2, 1, 2 * m, 8 * m, '안개 문지기국', color: sample, look: look(hs: BandLook.hsSemi));
      });
      await settle(scene, painter);
      final pixels = await render(painter);
      int at(double x, double y) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      for (final (id, hs, mix) in [(1, BandLook.hsLegendary, BandLayer.fogSolid), (2, BandLook.hsSemi, BandLayer.fogSemi)]) {
        final rect = painter.debugBands.firstWhere((b) => b.id == id).rect;
        final x = rect.right - 30; // 이름 글자를 비킨 자리
        final want = rgba(mixSrgb(BandLayer.toneOf(sample, look(hs: hs), fuzzy: false).fill, Look.paper, mix));
        expect(at(x, rect.top + 3), want, reason: '$id 띠의 위쪽 — 고른 색');
        expect(at(x, rect.top + rect.height * .5), want, reason: '$id 띠의 가운데 — 위와 같은 색(아래로 사라지지 않는다)');
      }
    });

    test('부흥·저항 세력은 띠 안쪽 왼쪽 3px에 깃대가 선다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 8 * m, '되찾는 깃발', color: sample, look: look(kind: BandKind.movement));
      });
      await settle(scene, painter);
      final pixels = await render(painter);
      final rect = painter.debugBands.single.rect;
      final tone = BandLayer.toneOf(sample, look(kind: BandKind.movement), fuzzy: false);
      final y = rect.center.dy, ground = rect.top + 200;
      int at(double x) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      expect(at(rect.left + 2.5), filmed(pixels, rect.left + 2.5, ground, over(tone.pole, tone.fill)), reason: '깃대는 테 색을 85%로');
      expect(at(rect.left + 4.5), filmed(pixels, rect.left + 4.5, ground, tone.fill), reason: '3px을 지나면 바탕');
    });
  });

  group('고르기 · 흐림 · 조명 (명세 06의 3절)', () {
    /// 같은 자리의 같은 띠 둘(줄 0 · 1)과 빈 셋째 줄. 같은 x의 빈 줄을 바탕으로 잡으면
    /// 세로 눈금 칸의 옅은 바탕이 지워져 띠가 얼마나 짙은지만 남는다(겹치기는 선형이라 비가 곧 밝기다).
    Future<(TimelineScene, TimelinePainter, ByteData)> two(em.Look state) async {
      final (scene, painter) = make((t) {
        // 그림판 바탕이 회색(건의 2026-10-15 1번)이라 아주 옅은 견본 색은 바탕과 차이가 작아 비가 흔들린다 — 짙은 색으로 잰다.
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: _deep, look: look());
        t.band(2, 1, 2 * m, 10 * m, '해솔국', color: _deep, look: look());
      });
      // 밝기 상태는 그리개가 장면 곁의 것을 층마다 걸어 준다(painter._emphasize).
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(state);
      await settle(scene, painter);
      return (scene, painter, await render(painter));
    }

    /// 둘째 띠가 첫째 띠에 견주어 얼마나 짙은가(= 그 자리의 밝기).
    double ratioAt(TimelinePainter painter, ByteData pixels, double x) {
      double tint(double px, double py) {
        final v = pixels.getUint32((py.floor() * 1920 + px.floor()) * 4);
        return (255 * 3 - (((v >> 24) & 0xff) + ((v >> 16) & 0xff) + ((v >> 8) & 0xff))).toDouble();
      }

      final first = painter.debugBands.firstWhere((b) => b.id == 1).rect;
      final second = painter.debugBands.firstWhere((b) => b.id == 2).rect;
      // 셋째 줄에는 띠가 없다 — 같은 세로 눈금 칸의 바탕을 재 두고 그만큼을 뺀다.
      final ground = tint(x, first.top + 360);
      final full = tint(x, first.center.dy) - ground;
      expect(full, greaterThan(20), reason: '고른 띠는 제 색 그대로여야 한다');
      return (tint(x, second.center.dy) - ground) / full;
    }

    void expectRatio(TimelinePainter painter, ByteData pixels, double x, double want, {String? reason}) =>
        expect(ratioAt(painter, pixels, x), closeTo(want, .06), reason: reason);

    test('고른 띠만 1 · 다른 띠는 .58 — 밝기가 묶음의 색 알파에 곱해진다', () async {
      final (_, painter, pixels) = await two(const em.Look(band: 1));
      expectRatio(painter, pixels, painter.debugBands.first.rect.left + 60, .58, reason: 'C:330의 .58');
      expect(noteOf(painter, 1), isNot(contains('밝기=')), reason: '고른 띠는 1이라 적지 않는다');
      expect(noteOf(painter, 2), contains('밝기=0.58'));
    });

    test('강조 밖은 .2 · 강조에 든 띠는 테두리가 --warn', () async {
      final (_, painter, pixels) = await two(const em.Look(bands: {1}));
      expectRatio(painter, pixels, painter.debugBands.first.rect.left + 60, .2, reason: 'C:336~337의 .2');
      expect(noteOf(painter, 1), contains('테두리=ff000000'), reason: 'is-match의 --warn(C:339 · C:882) — 색 없이 ink');
      expect(noteOf(painter, 2), contains('밝기=0.20'));
      expect(noteOf(painter, 2), isNot(contains('테두리=ff000000')));
    });

    test('흐린 띠 안의 조명 구간만 밝다 — 경계는 곧은 세로', () async {
      final (scene, painter, pixels) = await two(em.Look(band: 1, lit: true, spots: const [em.Spot(2, 5 * m, 7 * m)]));
      final v = scene.controller.view;
      expectRatio(painter, pixels, v.xOf(6 * m), 1, reason: '조명 구간 안은 흐리지 않는다');
      expectRatio(painter, pixels, v.xOf(3.5 * m), .58, reason: '구간 밖은 그 띠의 흐림 그대로');
      expectRatio(painter, pixels, v.xOf(8.5 * m), .58);
      expect(noteOf(painter, 2), contains('조명=1'));
    });

    // 조명의 흐름(명세 06의 3-3 · 움직임-원칙): 구간의 밝기는 `띠의 밝기 + (조명 밝기 − 띠의 밝기) × glow`다.
    // 켜질 때 200ms · 꺼질 때 160ms을 재는 것은 Emphasis의 몫(emphasis_test)이고, 여기서는 진행이 그림에 닿는지를 본다.
    test('조명의 흐름 — 구간의 밝기가 진행(glow)에 따라 띠의 밝기와 조명 밝기 사이를 흐른다', () async {
      for (final (glow, want) in const [(0.0, .58), (.5, .79), (1.0, 1.0)]) {
        final (scene, painter, pixels) = await two(em.Look(band: 1, lit: true, spots: [em.Spot(2, 5 * m, 7 * m, glow: glow)]));
        final v = scene.controller.view;
        expectRatio(painter, pixels, v.xOf(6 * m), want, reason: '진행 $glow에서 구간 안은 $want');
        expectRatio(painter, pixels, v.xOf(3.5 * m), .58, reason: '구간 밖은 언제나 그 띠의 흐림 그대로');
      }
    });

    test('다 꺼진 구간(glow 0)은 아예 싣지 않는다 — 끊을 자리도 만들지 않는다', () async {
      final (_, painter, _) = await two(em.Look(band: 1, lit: true, spots: const [em.Spot(2, 5 * m, 7 * m, glow: 0)]));
      expect(noteOf(painter, 2), isNot(contains('조명=')));
    });

    /// 흐르는 조명을 손으로 돌려 본다 — 그리개의 시계(`_emphasisWatch`)는 밝기 상태가 가라앉아 있는 동안 멎어 있어,
    /// 다 가라앉힌 뒤에 세워 두면 [em.Emphasis.tick]으로 준 만큼만 흐른다(그림 한 장에 실시간이 끼어들지 않는다).
    Future<(TimelineScene, TimelinePainter, em.Emphasis)> flowing() async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: _deep, look: look()); // 짙은 견본 색 — 위 [two]와 같은 까닭
        t.band(2, 1, 2 * m, 10 * m, '해솔국', color: _deep, look: look());
      });
      scene.controller.reduceMotion = false;
      await settle(scene, painter);
      return (scene, painter, em.Emphasis.of(scene)..reduceMotion = false);
    }

    // 명세 06의 3-3 '물러남': 창을 닫아 조명을 거두면 구간이 160ms에 옅어진다(css:1747 `.lit-out`).
    // 거두는 순간 `lit`도 함께 꺼지므로, 층이 `lit`만 보고 구간을 버리면 이 160ms가 한 장면에 튄다.
    test('조명을 거두면 구간이 160ms에 옅어진다 — 한 장면에 튀지 않는다', () async {
      final (scene, painter, e) = await flowing();
      e.set(em.Look(band: 1, lit: true, spots: const [em.Spot(2, 5 * m, 7 * m)]));
      for (int i = 0; i < 6; i++) {
        e.tick(50); // 200ms을 넘겨 다 켠다
      }
      expect(e.litMoving, isFalse, reason: '켜기가 가라앉았다');
      e.set(const em.Look(band: 1)); // 창을 닫아 조명을 거둔다
      e.tick(20); // 160ms의 1/8 — 이 굽이(Cubic(.32,.72,0,1))는 앞이 가팔라 절반이면 이미 거의 꺼진다
      expect(e.litMoving, isTrue);
      final pixels = await render(painter);
      final at = ratioAt(painter, pixels, scene.controller.view.xOf(6 * m));
      expect(at, greaterThan(.70), reason: '아직 조명이 남아 있다 — 띠의 밝기(.58)로 주저앉지 않는다');
      expect(at, lessThan(.98), reason: '이미 옅어지기 시작했다');
      expect(noteOf(painter, 2), contains('조명=1'));
    });

    test('다 옅어지면 조명이 사라진다 — 보통 흐린 띠로 돌아간다', () async {
      final (scene, painter, e) = await flowing();
      e.set(em.Look(band: 1, lit: true, spots: const [em.Spot(2, 5 * m, 7 * m)]));
      for (int i = 0; i < 6; i++) {
        e.tick(50);
      }
      e.set(const em.Look(band: 1));
      for (int i = 0; i < 5; i++) {
        e.tick(50); // 160ms을 넘긴다
      }
      expect(e.litMoving, isFalse);
      final pixels = await render(painter);
      expectRatio(painter, pixels, scene.controller.view.xOf(6 * m), .58, reason: '조명이 다 가라앉았다');
      expect(noteOf(painter, 2), isNot(contains('조명=')));
    });

    test('조명이 꺼진 채 새로 온 구간은 밝히지 않는다 — 거두는 구간과 가른다', () async {
      final (scene, painter, e) = await flowing();
      e.set(const em.Look(band: 1));
      for (int i = 0; i < 5; i++) {
        e.tick(50); // 흐림이 가라앉기를 기다린다(띠의 밝기가 흐르면 조명과 섞여 보인다)
      }
      // `lit`이 거짓인데 구간만 온 것(메아리를 끈 채 창이 구간을 올린 것)은 조명이 아니다.
      e.set(em.Look(band: 1, spots: const [em.Spot(2, 5 * m, 7 * m)]));
      e.tick(20);
      final pixels = await render(painter);
      expectRatio(painter, pixels, scene.controller.view.xOf(6 * m), .58, reason: '구간이 와도 밝아지지 않는다');
      expect(noteOf(painter, 2), isNot(contains('조명=')));
    });

    test('탭의 흐림은 띠와 달리 고른 동안 .5 · 강조 밖 .25', () async {
      final picked = (await two(const em.Look(band: 1))).$2;
      double tab(TimelinePainter p, String name) => p.debugLabels.firstWhere((l) => l.kind == 'tab' && l.text == name).alpha;
      expect(tab(picked, '별여울국'), closeTo(1, .001));
      expect(tab(picked, '해솔국'), closeTo(.5, .001), reason: 'C:1187');
      final other = (await two(const em.Look(bands: {1}))).$2;
      expect(tab(other, '별여울국'), closeTo(1, .001));
      expect(tab(other, '해솔국'), closeTo(.25, .001), reason: 'C:1189');
    });
  });

  group('조감 · 접힌 줄 · 맞히기', () {
    test('조감에서는 탭이 빠지고 이름이 띠 안으로 · 모서리는 네 곳이 같다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 12 * m, '별여울국', color: sample, look: look());
      });
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      await settle(scene, painter);
      expect(painter.debugLabels.where((l) => l.kind == 'tab'), isEmpty, reason: 'G_BIRD.tab = 0');
      final name = painter.debugLabels.singleWhere((l) => l.kind == 'bandName');
      expect(name.text, '별여울국');
      final rect = painter.debugBands.single.rect;
      expect(name.at.dx, closeTo(rect.left + 6, .01), reason: 'BIRD_NAME.inset 6px · 자리는 띠 시작에 고정');
      // 4.5는 반올림해 5로 적힌다 — 종류 · 미정을 가리지 않고 네 모서리가 같다(C:1769).
      expect(noteOf(painter, 1), contains('반지름=5/5'));
      expect(painter.bands.birdNameEnd[1], greaterThan(rect.left + 6));
      expect(painter.bands.birdNameZones[0]!.single.$1, closeTo(rect.left + 3, .01), reason: 'BIRD_NAME.clear 3px');
      // 지금 연표의 birdClear(js:7454) — 구간과 4px 안에서 스치기만 해도 비킨 것이 아니다.
      final (zl, zr) = painter.bands.birdNameZones[0]!.single;
      expect(painter.bands.birdClear(0, (zl + zr) / 2), isFalse);
      expect(painter.bands.birdClear(0, zl - 3.99), isFalse, reason: '구간의 4px 안은 막힌다');
      expect(painter.bands.birdClear(0, zl - 4), isTrue, reason: '꼭 4px 떨어지면 비킨 것이다(js의 `l < x + 4`)');
      expect(painter.bands.birdClear(1, (zl + zr) / 2), isTrue, reason: '다른 줄은 막지 않는다');
      // 점 · 알약은 4px의 여유 없이 상자끼리의 겹침만 본다(js:3608 · 3714의 `overlaps`) — 사건 층 · 맞히기가 이 답으로 숨긴다.
      expect(painter.bands.birdHides(0, zl + 1, zr - 1), isTrue, reason: '이름 자리에 걸친 점 · 알약은 숨는다');
      expect(painter.bands.birdHides(0, zl - 6, zl - 1), isFalse, reason: '닿지 않으면 그대로 선다(비킴의 4px 여유는 없다)');
      expect(painter.bands.birdHides(1, zl + 1, zr - 1), isFalse, reason: '다른 줄은 막지 않는다');
      // 층 배선 없이 장면 곁에서 찾는 길(사건 층 · 맞히기가 쓴다).
      expect(BandLayer.of(scene), same(painter.bands));
    });

    test('조감: 이름이 들어가지 않아도 단추가 설 자리(bnR)는 남는다', () async {
      // 지금 연표의 `bnR = nm.text ? nm.l + nm.w : nm.l − 4`(js:6934) — 이름이 없으면 단추가 이름이 섰을 자리에서 시작한다.
      final ppm = 32 / bucketMinutes(9);
      final (scene, painter) = make((t) {
        t.band(1, 0, 0, 20 / ppm, '별여울국', color: sample, look: look());
      });
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      await settle(scene, painter);
      final rect = painter.debugBands.single.rect;
      expect(painter.debugLabels.where((l) => l.kind == 'bandName'), isEmpty, reason: '20px 띠에는 첫 글자도 들어가지 않는다');
      expect(painter.bands.birdNameEnd[1], closeTo(rect.left + 6 - BandLayer.birdBtnGap, .01), reason: '이름이 섰을 자리 − 4');
      expect(painter.bands.birdNameZones[0], isNull, reason: '이름이 없으면 비울 자리도 없다');
      expect(painter.bands.birdClear(0, rect.left + 6), isTrue);
    });

    // 단추 층(paint/scopes.dart)과 관계선 층은 **제 beginFrame에서** 이 자리를 읽고 제 구간을 birdNameZones에 더한다.
    // 그러므로 자리는 그리는 때가 아니라 beginFrame에 서 있어야 한다 — 그리기를 감춘 장면으로 그것을 가린다.
    test('조감의 이름 자리는 그리기 전에(beginFrame) 선다 — 단추 층이 같은 장면에 읽는다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 12 * m, '별여울국', color: sample, look: look());
      });
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      scene.hide.add('bands'); // 띠도 이름도 그리지 않는다 — 자리를 재는 몫만 남는다
      await settle(scene, painter);
      expect(painter.debugBands, isEmpty, reason: '그리지 않았다');
      expect(painter.debugLabels.where((l) => l.kind == 'bandName'), isEmpty);
      final left = scene.controller.view.xOf(2 * m);
      expect(painter.bands.birdNameEnd[1], greaterThan(left + 6), reason: '그려지지 않아도 단추가 붙을 끝은 섰다');
      expect(painter.bands.birdNameZones[0]!.single.$1, closeTo(left + 3, .01), reason: 'BIRD_NAME.clear 3px');
      expect(painter.bands.birdClear(0, left + 6), isFalse);
    });

    test('접힌 민족 줄에는 띠도 탭도 그리지 않는다(가는 막대는 다른 층)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 12 * m, '별여울국', color: sample, look: look());
        t.band(2, 1, 2 * m, 12 * m, '해솔국', color: sample, look: look(folded: true));
      }, shape: folded());
      await settle(scene, painter);
      expect(painter.debugBands.map((b) => b.id).toList(), [1]);
      expect(painter.debugLabels.where((l) => l.kind == 'tab').map((l) => l.text).toList(), ['별여울국']);
    });

    test('맞히기는 띠와 머리 이름(탭)을 가려낸다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 12 * m, '별여울국', color: sample, look: look());
      });
      await settle(scene, painter);
      final rect = painter.debugBands.single.rect;
      final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab');
      expect(painter.bands.hitBands(rect.center.dx, rect.center.dy)?.band, 1);
      expect(painter.bands.hitBands(rect.center.dx, rect.center.dy)?.tab, isFalse);
      expect(painter.bands.hitBands(tab.at.dx + 2, rect.top - 5), isNull, reason: '띠 위에는 탭 줄이 없다');
      // 머리 이름의 맞히기 상자 = [이름 왼쪽, 띠 윗변, 딱지 끝, 띠 윗변 + 24] — 띠 몸통보다 앞에서 맞아야 한다.
      final onTab = painter.bands.hitBands(tab.at.dx + 2, rect.top + 12);
      expect((onTab?.band, onTab?.row, onTab?.tab), (1, 0, true));
      expect(painter.bands.hitBands(tab.at.dx + 2, rect.top + 30)?.tab, isFalse, reason: '머리(24) 아래는 띠 몸통');
      expect(painter.bands.hitBands(rect.left - 20, rect.center.dy), isNull);
    });
  });

  test('키에 맞춘 귀(감독 2026-10-15 갈래 1): 모따기 = 키 × 0.1(5 ~ 12) · 둥근 끝 = 키 × 0.22(12 ~ 24) · 구멍은 귀 + 2(둥근 끝은 × 0.6 · 최소 9)', () {
    // 목업 서고의 꼬리표(키 52)까지는 예전 값 그대로.
    expect([TagLook.cornerOf(TagEnd.cham, 24), TagLook.cornerOf(TagEnd.cham, 52), TagLook.holeAt(TagEnd.cham, 52)], [5, 5, 7]);
    expect([TagLook.cornerOf(TagEnd.key, 24), TagLook.cornerOf(TagEnd.key, 52), TagLook.holeAt(TagEnd.key, 52)], [12, 12, 9]);
    // 큰 꼬리표는 함께 커진다(갈래 E의 실제 띠 — 키 80 · 110 · 140).
    expect([TagLook.cornerOf(TagEnd.cham, 80), TagLook.cornerOf(TagEnd.cham, 110), TagLook.cornerOf(TagEnd.cham, 140)], [8, 11, 12]);
    expect([TagLook.holeAt(TagEnd.cham, 80), TagLook.holeAt(TagEnd.cham, 110), TagLook.holeAt(TagEnd.cham, 140)], [10, 13, 14]);
    expect([TagLook.cornerOf(TagEnd.key, 80), TagLook.cornerOf(TagEnd.key, 140), TagLook.holeAt(TagEnd.key, 140)], [18, 24, 14]);
    // 직각 꼴은 귀가 없고, 귀는 키의 절반을 넘지 않는다.
    expect([TagLook.cornerOf(TagEnd.plain, 140), TagLook.cornerOf(TagEnd.cham, 8)], [0, 4]);
  });

  test('그림판 한 장에 모서리 조각이 다 들어간다', () {
    expect(BandSprites.sheetWidth, 88);
    // 149(겹 탭 뒤 장의 키 큰 어깨 줄까지) + 꼬리표의 귀 모따기 줄(갈래 E — 10px 칸 둘 · 키에 맞춘 큰 귀의 24px 칸 둘 + 여백 2) = 175
    expect(BandSprites.chamTop, 149);
    expect(BandSprites.sheetHeight, 175);
    expect(BandSprites.chamLineBig.$1 + BandSprites.chamLineBig.$3, lessThanOrEqualTo(BandSprites.sheetWidth));
    expect([BandSprites.chamFill(5), BandSprites.chamFill(7), BandSprites.chamEdge(12)], [BandSprites.cham, BandSprites.chamBig, BandSprites.chamLineBig]);
    expect(BandSprites.arc(22), BandSprites.arc22);
    expect(BandSprites.arc(12), BandSprites.arc12);
    expect(BandSprites.arc(10), BandSprites.arc10);
    // 간지 탭의 어깨(묶음 3 · 1번): 어깨 7 · 4의 칠과 선(실선 · 파선 · 점선)이 서로 겹치지 않고 그림판 안에 든다
    final cells = <Rect>[];
    for (final s in [Look.tabShoulder, Look.tabShoulderShort]) {
      for (final stroke in EdgeStroke.values) {
        final c = BandSprites.shoulders(s, stroke);
        for (final r in [c.fillL, c.fillR, c.lineL, c.lineR]) {
          expect(r.width, s);
          expect(r.height, BandSprites.shoulderH);
          expect(r.left >= 0 && r.right <= BandSprites.sheetWidth && r.top >= 88 && r.bottom <= BandSprites.shoulderTallTop, isTrue, reason: '$r');
          if (!cells.contains(r)) cells.add(r);
        }
      }
    }
    // 겹 탭 뒤 장의 키 큰 어깨(어깨 7 · 높이 14 — 앞 장보다 3px 위에서 띠 윗변까지 · 실선만): 칠 둘 · 선 둘이 맨 아랫줄(y 112 ~ 126)에 서로 겹치지 않게 든다
    final tall = BandSprites.shouldersTall();
    for (final r in [tall.fillL, tall.fillR, tall.lineL, tall.lineR]) {
      expect(r.width, Look.tabShoulder);
      expect(r.height, BandSprites.shoulderTallH);
      expect(r.height, BandSprites.shoulderH + BandLayer.coalBackDy, reason: '뒤 장은 앞 장보다 3px 높다');
      expect(r.left >= 0 && r.right <= BandSprites.sheetWidth && r.top >= BandSprites.shoulderTallTop && r.bottom <= BandSprites.chamTop, isTrue, reason: '$r');
      cells.add(r);
    }
    // 꼬리표의 귀 모따기(칠 · 빗변 선): 10px 칸 둘이 맨 아랫줄(y 149 ~ 159)에 서로 겹치지 않게 든다.
    for (final (x, y, w) in [BandSprites.cham, BandSprites.chamLine]) {
      final r = Rect.fromLTWH(x, y, w, w);
      expect(r.width, 10);
      expect(r.left >= 0 && r.right <= BandSprites.sheetWidth && r.top >= BandSprites.chamTop && r.bottom <= BandSprites.sheetHeight, isTrue, reason: '$r');
      cells.add(r);
    }
    for (int a = 0; a < cells.length; a++) {
      for (int b = a + 1; b < cells.length; b++) {
        expect(cells[a].overlaps(cells[b]), isFalse, reason: '${cells[a]} · ${cells[b]}');
      }
    }
  });
}

/// 그림을 떠서 픽셀을 본다.
Future<ByteData> render(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!;
}

/// 0xAARRGGBB → 그림이 돌려주는 0xRRGGBBAA(불투명).
int rgba(int argb) => ((argb & 0x00ffffff) << 8 | 0xff) & 0xffffffff;

/// 세로 눈금 칸의 옅은 바탕(`--grid-band` — 회색 · 흰색의 구간 구분)은 띠 **아래**다(감독 결정 2026-09-22 — 띠는 불투명한 파스텔이라
/// 그 구분 색이 띠 위로 비치지 않는다. 지금 연표는 격자 상자가 띠 위에 얹혀 비친다). 그래서 띠의 불투명한 픽셀은 바라는 색 그대로다.
int filmed(ByteData pixels, double x, double groundY, int want) => rgba(want);

/// 그리기 호출을 세는 가짜 화폭.
class _SpyCanvas implements ui.Canvas {
  int rrects = 0, paths = 0;
  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) => rrects++;
  @override
  void drawPath(ui.Path path, ui.Paint paint) => paths++;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 흐림 · 조명의 비를 재는 짙은 견본 색(회색 바탕 위에서도 차이가 넉넉하게).
const _deep = 0x2a4f9a;
