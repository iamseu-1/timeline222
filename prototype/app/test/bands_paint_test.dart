import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/band_form.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/links.dart' show LinkLayer;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellStyle;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/reserved.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
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

/// 검사용 기록의 한 열쇠(없으면 빈 목록)를 글로.
List<String> noted(TimelinePainter painter, String key) => [for (final v in painter.debugSink.notes[key] ?? const <Object>[]) '$v'];

/// '1 331.0,195.0,1680.0,262.0 카드' 같은 기록을 숫자로.
List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

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

  // 리메이크 4단계 과제 5 걸음 2 — 빌린 직위 줄의 출처 글(구역 54 · 서고 미리보기 `.tl-borrow` — timeline.js 8272 ~ 8278 · common.css 2497).
  group('빌린 직위 줄의 출처 글', () {
    /// 구역 54 항목 하나(빌린 쪽 띠 [band] · 줄 [row] · 칸 종류 [a] · 출처 글 [name]).
    void borrowItem(TileBuilder t, int id, int band, int row, double x0, double x1, int a, String name, {int b = 0}) =>
        t.item(Schema4.secBorrowHead, id, row, x0, x1, ref: band, name: name, a: a, b: b, text2: 'p/src');

    test('지도자 · 내각을 한 글로 머리 이름 탭 뒤에 — 미리보기 tabEnd 자리 · 색줄 가운데 · 8.5 보통 굵기 먹 55%', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        borrowItem(t, 1, 1, 0, 2 * m, 10 * m, 1, '해솔국/지도자');
        borrowItem(t, 2, 1, 0, 2 * m, 10 * m, 2, '해솔국/내각');
        borrowItem(t, 3, 1, 0, 2 * m, 10 * m, 9, '나루국/재상', b: 0); // 직위 줄 더의 빌림 — G7 뒤라 그리지 않는다
      });
      await settle(scene, painter);
      final tab = painter.debugLabels.singleWhere((l) => l.kind == 'tab');
      final borrow = painter.debugLabels.singleWhere((l) => l.kind == 'borrow');
      expect(borrow.text, '· 지도자 ← 해솔국/지도자 · 내각 ← 해솔국/내각', reason: '지도자 → 내각 차례 · 빈칸 하나로 잇고 a = 9는 뺀다');
      // 자리: 미리보기 tabEnd = 탭 왼쪽(이름 − 13) + 탭 폭(이름 폭 × 9.5/9 + 14 + 어깨 12) + 틈 4.
      final nameW = painter.bands.headNameEnd[1]! - tab.at.dx;
      expect(borrow.at.dx, closeTo(tab.at.dx - TagLook.namePad + nameW * BandLayer.tabNameUp + 14 + Look.tabExt + Look.tabGap, .01));
      expect(borrow.at.dx, greaterThan(painter.bands.headNameEnd[1]! + 4), reason: '이름 구간(앞뒤 4)과 겹치지 않는다');
      final rect = painter.debugBands.single.rect;
      expect(borrow.at.dy, closeTo(rect.top + G.head / 2 - 8.5 * .6, .01), reason: '이름 색줄 14의 가운데 — 이름과 같은 줄');
      expect(borrow.alpha, tab.alpha, reason: '이름과 같은 흐림');
      expect((BandLayer.borrowLook.size, BandLayer.borrowLook.weight, hex(BandLayer.borrowLook.color)), (8.5, ui.FontWeight.w400, hex(CanvasInk.k60)), reason: '먹 55 → 그림판 먹 단계 60(4단계 G5 #8 먹 가)');
      // 머리 줄의 글 구간에 더한다(앞뒤 4) — 뒤에 놓는 머리 줄 글(칸 층 없는 꼬리표의 집권 · 실권 이름)이 비킨다.
      final zones = painter.bands.headNameZones[0]!;
      expect(zones.length, 2);
      expect(zones[1].$1, closeTo(borrow.at.dx - 4, .01));
      expect(zones[1].$2, greaterThan(borrow.at.dx + 100), reason: '출처 글의 폭(앞뒤 4)');
      // 사건은 몸통의 흰 사건 칸에 서서 머리 줄을 지나지 않는다 — 사건 이름 셈의 비킬 구간(출처 'names')은 그대로 빈다.
      final reserved = ReservedZones.of(scene);
      expect(reserved.at(0).length, reserved.at(0, except: 'names').length);
      expect(noted(painter, '빌린머리'), ['1 ${(borrow.at.dx * 10).round()} ${borrow.text}']);
      // 누르면 띠(미리보기 pointer-events: none) — 이름 탭이 아니다.
      expect(painter.bands.hitBands(borrow.at.dx + 20, rect.top + G.head / 2)?.tab, isFalse);
    });

    test('a = 9만 있거나 출처가 빈 글이면 쓰지 않는다 — 내각만이면 내각 글 하나', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        t.band(2, 1, 2 * m, 10 * m, '해솔국', color: sample, look: look());
        t.band(3, 2, 2 * m, 10 * m, '가람국', color: sample, look: look());
        borrowItem(t, 1, 1, 0, 2 * m, 10 * m, 9, '나루국/재상');
        borrowItem(t, 2, 2, 1, 2 * m, 10 * m, 1, '');
        borrowItem(t, 3, 3, 2, 2 * m, 10 * m, 2, '나루국/내각');
      });
      await settle(scene, painter);
      expect([for (final l in painter.debugLabels) if (l.kind == 'borrow') l.text], ['· 내각 ← 나루국/내각']);
      expect(painter.bands.headNameZones[0]!.length, 1, reason: '그리지 않은 띠는 이름 구간만');
      expect(painter.bands.headNameZones[1]!.length, 1);
    });

    test('꼬리 마름모 앞(띠 오른쪽 끝 − 15)까지 다 들지 않으면 쓰지 않는다 — 줄여 쓰지 않고 이름은 그대로', () async {
      final ppm = 32 / bucketMinutes(9);
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 2 * m + 120 / ppm, '별여울국', color: sample, look: look()); // 120px — 이름은 들고 출처 글은 넘친다
        borrowItem(t, 1, 1, 0, 2 * m, 2 * m + 120 / ppm, 1, '해솔국/지도자');
      });
      await settle(scene, painter);
      expect(painter.debugLabels.singleWhere((l) => l.kind == 'tab').text, '별여울국');
      expect(painter.debugLabels.where((l) => l.kind == 'borrow'), isEmpty);
      expect(painter.bands.headNameZones[0]!.length, 1);
      expect(noted(painter, '빌린머리'), isEmpty);
    });

    test('띠 시작이 화면 왼쪽 밖이면 붙은 이름을 따라온다', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 0, 10 * m, '별여울국', color: sample, look: look());
        borrowItem(t, 1, 1, 0, 0, 10 * m, 1, '해솔국/지도자');
      }, from: 2 * m);
      await settle(scene, painter);
      final tab = painter.debugLabels.singleWhere((l) => l.kind == 'tab');
      final borrow = painter.debugLabels.singleWhere((l) => l.kind == 'borrow');
      expect(tab.at.dx, SceneView.gutter + Look.tabInset);
      final nameW = painter.bands.headNameEnd[1]! - tab.at.dx;
      expect(borrow.at.dx, closeTo(tab.at.dx - TagLook.namePad + nameW * BandLayer.tabNameUp + 14 + Look.tabExt + Look.tabGap, .01));
    });

    test('조감에서는 쓰지 않는다(머리 이름이 없고 띠 안 이름뿐)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        borrowItem(t, 1, 1, 0, 2 * m, 10 * m, 1, '해솔국/지도자');
      });
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      await settle(scene, painter);
      expect(painter.debugLabels.where((l) => l.kind == 'borrow'), isEmpty);
      expect(noted(painter, '빌린머리'), isEmpty);
    });
  });

  // 리메이크 4단계 과제 6 — 실권 밑줄(구역 56 · 서고 미리보기 `.tl-power-ul` · `.tl-power-name` — timeline.js 8280 ~ 8287 · common.css 2498 ~ 2499).
  group('실권 밑줄', () {
    final ppm = 32 / bucketMinutes(9);

    /// 구역 56 항목 하나(빼앗긴 띠 [band] · 줄 [row] · 쥔 쪽 이름 [holder] · 색 [color] · 제 안의 실권자 [own]).
    void powerItem(TileBuilder t, int id, int band, int row, double x0, double x1, String holder, {int color = 0, bool own = false}) =>
        t.item(Schema4.secPowerLine, id, row, x0, x1, ref: band, name: holder, color: color, a: own ? 1 : 0, text2: own ? '' : 'p/holder');

    String hex6(int argb) => (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
    const holderColor = 0x8b6f47;

    test('남의 실권: 머리 아랫변 바로 위 2px(띠 윗변 + 11) · 기간을 띠 안 3px 안쪽으로 자름 · 쥔 쪽 색 80% + 먹 — 끝 이름은 오른쪽 끝 − 3에 오른쪽 맞춤 8 굵게 · 쥔 쪽 색 30% + 먹', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        powerItem(t, 1, 1, 0, 2 * m, 6 * m, '북설 칸국', color: holderColor);
      });
      await settle(scene, painter);
      final pixels = await render(painter);
      final rect = painter.debugBands.single.rect;
      final v = scene.controller.view;
      final a = rect.left + 3, b = v.xOf(6 * m);
      final y = (rect.top + BandLayer.powerTop).floor();
      final line = mixSrgb(0xff000000 | holderColor, Look.ink, BandLayer.powerMix);
      expect(noted(painter, '실권밑줄'), ['1 ${a.round() * 10},${y * 10},${(b.round() - a.round()) * 10} ${hex6(line)}'], reason: '띠 시작 + 3(실권이 띠 시작부터) ~ 실권 끝');
      int at(double x, int py) => pixels.getUint32((py * 1920 + x.floor()) * 4);
      for (final x in [a + 1, (a + b) / 2, b - 1]) {
        expect(at(x, y), rgba(line), reason: '밑줄 윗줄 x=$x');
        expect(at(x, y + 1), rgba(line), reason: '밑줄 아랫줄 x=$x');
        expect(at(x, y - 1), isNot(rgba(line)), reason: '밑줄은 2px — 위는 머리 칠');
        expect(at(x, y + 2), isNot(rgba(line)), reason: '밑줄은 2px — 아래는 머리 아랫금');
      }
      expect(at(a - 2, y), isNot(rgba(line)), reason: '띠 안 3px 안쪽에서 시작');
      // 끝 이름: 머리 줄 글 구간(앞뒤 4)으로 오른쪽 끝을 본다 — 이름 구간 다음에 더해진다.
      final name = painter.debugLabels.singleWhere((l) => l.kind == 'powerName');
      expect(name.text, '북설 칸국');
      final zones = painter.bands.headNameZones[0]!;
      expect(zones.length, 2, reason: '머리 이름 · 끝 이름');
      expect(zones[1].$1, closeTo(name.at.dx - 4, .01));
      expect(zones[1].$2 - 4, closeTo(b - 3, .01), reason: '밑줄 오른쪽 끝 − 3에 오른쪽 맞춤');
      expect(name.at.dy, closeTo(rect.top + 2 + 9 / 2 - 8 * .6, .01), reason: '띠 윗변 + 2의 9px 글줄 가운데');
      final tab = painter.debugLabels.singleWhere((l) => l.kind == 'tab');
      expect(name.alpha, tab.alpha, reason: '이름과 같은 흐림');
      expect((BandLayer.powerNameLook.size, BandLayer.powerNameLook.weight), (8.0, ui.FontWeight.w700));
      expect(noted(painter, '실권이름'), ['1 ${(name.at.dx * 10).round()} ${hex6(mixSrgb(0xff000000 | holderColor, Look.ink, BandLayer.powerNameMix))} 북설 칸국']);
      // 누르면 띠(미리보기 pointer-events: none).
      expect(painter.bands.hitBands((a + b) / 2, y + 1.0)?.tab, isFalse);
    });

    test('제 안의 실권자(a = 1): 밑줄 · 끝 이름 모두 먹(그림판 먹 단계 85) — 미리보기는 그리지 않는다(계획 걸음 1-1)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        powerItem(t, 1, 1, 0, 5 * m, 8 * m, '세도 가문', own: true);
      });
      await settle(scene, painter);
      final pixels = await render(painter);
      final rect = painter.debugBands.single.rect;
      final v = scene.controller.view;
      final a = v.xOf(5 * m), b = v.xOf(8 * m), y = (rect.top + BandLayer.powerTop).floor();
      expect(noted(painter, '실권밑줄'), ['1 ${a.round() * 10},${y * 10},${(b.round() - a.round()) * 10} 262626']);
      expect(pixels.getUint32((y * 1920 + ((a + b) / 2).floor()) * 4), rgba(CanvasInk.k85));
      final name = painter.debugLabels.singleWhere((l) => l.kind == 'powerName');
      expect(noted(painter, '실권이름'), ['1 ${(name.at.dx * 10).round()} 262626 세도 가문']);
    });

    test('4px 미만이면 밑줄이 없고, 밑줄 폭이 이름(8.5 굵게로 잰 폭) + 8보다 좁으면 끝 이름 없이 밑줄만', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        powerItem(t, 1, 1, 0, 2 * m, 2 * m + 6 / ppm, '북설 칸국', color: holderColor); // 띠 시작 + 3 ~ + 6 — 3px
        powerItem(t, 2, 1, 0, 5 * m, 5 * m + 30 / ppm, '북설 칸국', color: holderColor); // 30px — 이름(≈ 40)이 들지 않는다
        t.band(2, 1, 2 * m, 2 * m + 9 / ppm, '좁은 나라', color: sample, look: look()); // 9px 띠 — 안쪽 3px씩 빼면 3px
        powerItem(t, 3, 2, 1, 2 * m, 2 * m + 9 / ppm, '북설 칸국', color: holderColor);
      });
      await settle(scene, painter);
      expect([for (final n in noted(painter, '실권밑줄')) n.split(' ').first], ['1'], reason: '30px짜리 하나만');
      expect(painter.debugLabels.where((l) => l.kind == 'powerName'), isEmpty);
      expect(noted(painter, '실권이름'), isEmpty);
      expect(painter.bands.headNameZones[0]!.length, 1, reason: '머리 이름 구간만');
    });

    test('머리 이름 · 출처 글과 겹치면 끝 이름을 빼고 밑줄은 남긴다(글자 가림 0)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        t.item(Schema4.secBorrowHead, 9, 0, 2 * m, 10 * m, ref: 1, name: '해솔국/지도자', a: 1, text2: 'p/src');
        // 띠 시작부터 출처 글 가운데쯤까지 — 끝 이름(오른쪽 끝 − 3)이 출처 글 위에 선다.
        powerItem(t, 1, 1, 0, 2 * m, 2 * m + 120 / ppm, '북설 칸국', color: holderColor);
      });
      await settle(scene, painter);
      final borrow = painter.debugLabels.singleWhere((l) => l.kind == 'borrow');
      final v = scene.controller.view;
      expect(v.xOf(2 * m + 120 / ppm) - 3, greaterThan(borrow.at.dx + 4), reason: '견본: 이름 오른쪽 끝이 출처 글 안');
      expect(noted(painter, '실권밑줄').length, 1, reason: '밑줄은 그대로');
      expect(painter.debugLabels.where((l) => l.kind == 'powerName'), isEmpty, reason: '출처 글과 겹치는 끝 이름은 뺀다');
      expect(painter.bands.headNameZones[0]!.length, 2, reason: '머리 이름 · 출처 글');
    });

    test('단체의 실권 단(칸 종류 8 · 단 3)이 같은 기간에 그려지면 끝 이름만 뺀다 — 빽빽하게의 머리 줄 실권 단 · 단체를 끄거나 층이 없으면 이름이 선다', () async {
      Future<TimelinePainter> drawn({required int density, required bool groups}) async {
        final (scene, painter) = make((t) {
          t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
          powerItem(t, 1, 1, 0, 5 * m, 8 * m, '북설 칸국', color: holderColor);
          // 같은 띠 · 겹치는 기간의 실권 칸(단 갈래 7 · 줄임\t이름)
          t.cell(50, 0, 6 * m, 9 * m, '푸\t푸른 집안', kind: 8, lane: 3, style: CellStyle.groupReal << 27 | CellStyle.tagged | 1 << 15, color: 0xa0bcc5);
        });
        scene.layout.setConditions(scene.layout.conditions.copyWith(density: density, groups: groups));
        await settle(scene, painter);
        return painter;
      }

      final dense = await drawn(density: 1, groups: true);
      expect(dense.debugLabels.where((l) => l.kind == 'power').map((l) => l.text), ['푸른 집안'], reason: '견본: 빽빽하게는 실권 단을 머리 줄에 그린다');
      expect(noted(dense, '실권밑줄').length, 1, reason: '밑줄은 그대로');
      expect(dense.debugLabels.where((l) => l.kind == 'powerName'), isEmpty, reason: '실권 단과 같은 기간 — 끝 이름을 뺀다');
      final off = await drawn(density: 1, groups: false);
      expect(off.debugLabels.where((l) => l.kind == 'power'), isEmpty);
      expect(off.debugLabels.where((l) => l.kind == 'powerName').map((l) => l.text), ['북설 칸국'], reason: '단체를 끄면 실권 단이 없다');
      final plain = await drawn(density: 0, groups: true);
      expect(plain.debugLabels.where((l) => l.kind == 'power'), isEmpty, reason: '견본: 보통 밀도에 실권 층이 없는 줄');
      expect(plain.debugLabels.where((l) => l.kind == 'powerName').map((l) => l.text), ['북설 칸국']);
    });

    test('미정 끝의 띠는 꼬리(44)까지 띠 상자 — 띠 끝까지 가는 실권 밑줄은 끝에서 3px 안쪽이 아니라 끝까지(미리보기 x2)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 6 * m, '별여울국', color: sample, look: look());
        t.band(2, 1, 2 * m, 6 * m, '해솔국', color: sample, look: look(), flags: Tile.fuzzyEnd);
        powerItem(t, 1, 1, 0, 4 * m, 6 * m, '북설 칸국', color: holderColor);
        powerItem(t, 2, 2, 1, 4 * m, 6 * m, '북설 칸국', color: holderColor);
      });
      await settle(scene, painter);
      final v = scene.controller.view;
      final widths = {for (final n in noted(painter, '실권밑줄')) n.split(' ').first: int.parse(n.split(' ')[1].split(',')[2])};
      final a = v.xOf(4 * m).round(), end = v.xOf(6 * m);
      expect(widths['1'], ((end - 3).round() - a) * 10, reason: '확정된 끝: 띠 끝 − 3');
      expect(widths['2'], (end.round() - a) * 10, reason: '미정 끝: 꼬리 끝 − 3이 실권 끝보다 멀다');
    });

    test('조감에서는 없다(머리가 없다)', () async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample, look: look());
        powerItem(t, 1, 1, 0, 5 * m, 8 * m, '북설 칸국', color: holderColor);
      });
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      await settle(scene, painter);
      expect(noted(painter, '실권밑줄'), isEmpty);
      expect(painter.debugLabels.where((l) => l.kind == 'powerName'), isEmpty);
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
      expect(TagLook.eventLift(geo, withLeader, oldStore: false, loose: false, sub: 0), 0);
      expect(TagLook.eventLift(geo, look(), oldStore: false, loose: false, sub: 0), G.floor);
      expect(TagLook.eventLift(geo, look(), oldStore: false, loose: true, sub: 0), 0, reason: '넉넉하게는 올리지 않는다');
      expect(TagLook.bodyBottom(geo, look(), oldStore: true, sub: 0), geo.bandTop + geo.bandHeight, reason: '옛 저장소는 몸통이 늘 띠 아랫변까지');
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

  // 감독 고름 G6 가(2026-10-25 · 계획 과제 2 걸음 1 · 2 · 차례 걸음 12): 꼬리표 왼쪽 끝은 form의 종류 갈래로(다스림 = 모따기 · 영토 밖 = 둥근 끝 · 무리 = 직각),
  // 그릇 · 사람 · form 0(옛 저장소 · 그림 띠)은 옛 종류 짐작 그대로(옛 조직체 · 군벌 모두 모따기). 정통성 '대립'은 테를 파선 3 · 2(조직체의 점선 1 · 1보다 이김 —
  // 직각은 테가 없는 그대로) · 머리 이름 먹 60. 칠 · 테 빛깔은 look 그대로. 스위치 `tag`를 끄면(찍기 · 증명 전용) 예전 그대로.
  group('꼬리표 끝 — form의 종류 갈래 · 대립(G6 가 · 과제 2)', () {
    tearDown(PaintPick.reset);

    /// 띠의 form(계약 1-1 비트 — 종류 번호 + 1 · (정통성 번호 + 1) << 10). [legit]이 빈 글이면 정통성 비움.
    int form(String type, {String legit = ''}) {
      final t = BandForm.types.indexOf(type), l = legit.isEmpty ? -1 : BandForm.legits.indexOf(legit);
      expect(t, greaterThanOrEqualTo(0), reason: type);
      return (t + 1) | (l + 1) << 10;
    }

    /// 형식 4 종류 id → 갈래(js/core.js `HT.F4` TYPES의 group — 원본을 읽어 대조한다).
    Map<String, String> groupsOfCore() {
      // 앱 검사는 dev.ps1의 ASCII 이음 폴더(%TEMP%/<이름> → prototype)에서 돈다 — 진짜 자리로 풀어 저장소 맨 위의 js를 읽는다.
      final app = Directory.current.resolveSymbolicLinksSync();
      final src = File('$app/../../js/core.js').readAsStringSync();
      return {for (final m in RegExp(r"\{ id: '(\w+)', name: '[^']*', group: '(\w+)'").allMatches(src)) m.group(1)!: m.group(2)!};
    }

    test('갈래 표는 형식 4 종류의 group(js/core.js HT.F4 TYPES)과 같다 — 다스림 여덟 · 영토 밖 다섯 · 무리 하나 · 그릇 넷 · 사람', () {
      final groups = groupsOfCore();
      expect(groups.keys.toSet(), BandForm.types.toSet(), reason: '종류 열아홉');
      for (int n = 0; n < BandForm.types.length; n++) {
        final want = switch (groups[BandForm.types[n]]) {
          'ruling' => 'cham',
          'offland' => 'key',
          'folk' => 'plain',
          _ => 'guess',
        };
        final got = n <= TagLook.formRulingLast ? 'cham' : (n <= TagLook.formOfflandLast ? 'key' : (n == TagLook.formFolk ? 'plain' : 'guess'));
        expect(got, want, reason: '종류 $n ${BandForm.types[n]}(${groups[BandForm.types[n]]})');
      }
      expect(BandForm.legits[TagLook.formRival], 'rival');
    });

    test('갈래 넷 × form 있음 · 0 — form이 있으면 종류 갈래가 옛 짐작을 이기고, 그릇 · 사람 · form 0은 옛 짐작', () {
      // 옛 짐작: 복속 세력 → 직각 · 부흥 · 저항 → 둥근 끝 · 나머지(옛 조직체 · 군벌 포함) → 모따기.
      final looks = {for (final k in [BandKind.state, BandKind.org, BandKind.warlord, BandKind.client, BandKind.movement, BandKind.era, BandKind.fief]) k: look(kind: k)};
      for (final MapEntry(key: kind, value: lk) in looks.entries) {
        final guess = TagLook.endOf(lk);
        expect(TagLook.endOfBand(lk, 0), guess, reason: '옛 종류 $kind · form 0 → 옛 짐작');
        for (final t in ['state', 'federation', 'principality', 'city', 'government', 'regime', 'dependency', 'warlord']) {
          expect(TagLook.endOfBand(lk, form(t)), TagEnd.cham, reason: '다스림 $t (옛 종류 $kind)');
        }
        for (final t in ['organization', 'faith', 'order', 'company', 'office']) {
          expect(TagLook.endOfBand(lk, form(t)), TagEnd.key, reason: '영토 밖 $t (옛 종류 $kind)');
        }
        expect(TagLook.endOfBand(lk, form('group')), TagEnd.plain, reason: '무리 (옛 종류 $kind)');
        for (final t in ['era', 'realm', 'union', 'league', 'person']) {
          expect(TagLook.endOfBand(lk, form(t)), guess, reason: '그릇 · 사람 $t는 옛 짐작 (옛 종류 $kind)');
        }
        // 종류를 비우고 정통성만 실은 form(종류 비트 0 = 모름)도 옛 짐작.
        expect(TagLook.endOfBand(lk, 2 << 10), guess);
      }
      expect([TagLook.endOf(look(kind: BandKind.org)), TagLook.endOf(look(kind: BandKind.warlord))], [TagEnd.cham, TagEnd.cham], reason: 'G6 가 — 옛 조직체 · 군벌 모두 모따기');
      // 대립: 정통성 번호 1만. 다른 정통성 · 비움 · form 0은 아니다.
      expect(TagLook.rivalOf(form('government', legit: 'rival')), isTrue);
      expect([for (final l in ['legit', 'joint', 'regent', 'nominal', 'claim']) TagLook.rivalOf(form('state', legit: l))], everyElement(isFalse));
      expect([TagLook.rivalOf(form('state')), TagLook.rivalOf(0)], [false, false]);
      // 스위치 tag를 끄면 form을 보지 않는다.
      PaintPick.tag = false;
      expect(TagLook.endOfBand(look(kind: BandKind.org), form('faith')), TagEnd.cham);
      expect(TagLook.endOfBand(look(kind: BandKind.client), form('state')), TagEnd.plain);
      expect(TagLook.rivalOf(form('government', legit: 'rival')), isFalse);
    });

    /// 줄 셋 × 넷 — (id, 줄, 옛 종류, form, 바라는 끝). 띠마다 3m 폭(약 370px).
    final ends = <(int, int, int, int Function(), TagEnd)>[
      (1, 0, BandKind.org, () => form('faith'), TagEnd.key), // 교단 form — 옛 짐작(모따기)과 갈림
      (2, 0, BandKind.org, () => 0, TagEnd.cham), // 옛 조직체 form 0 — 모따기(G6 가)
      (3, 0, BandKind.movement, () => 0, TagEnd.key), // 옛 부흥 · 저항 form 0 — 둥근 끝
      (4, 0, BandKind.movement, () => form('state'), TagEnd.cham), // form 국가 — 옛 짐작(둥근 끝)과 갈림
      (5, 1, BandKind.warlord, () => 0, TagEnd.cham), // 옛 군벌 form 0 — 모따기(G6 가)
      (6, 1, BandKind.warlord, () => form('warlord'), TagEnd.cham),
      (7, 1, BandKind.client, () => 0, TagEnd.plain), // 옛 복속 세력 form 0 — 직각
      (8, 1, BandKind.state, () => form('group'), TagEnd.plain), // form 집단 — 옛 짐작(모따기)과 갈림
      (9, 2, BandKind.org, () => form('league'), TagEnd.cham), // 그릇(동맹) — 옛 짐작
      (10, 2, BandKind.client, () => form('era'), TagEnd.plain), // 그릇(시대) — 옛 짐작
      (11, 2, BandKind.movement, () => form('person'), TagEnd.key), // 사람 — 옛 짐작
      (12, 2, BandKind.state, () => form('company'), TagEnd.key), // 회사 form — 옛 짐작(모따기)과 갈림
    ];
    double startOf(int id) => (.5 + ((id - 1) % 4) * 3.4) * m;

    /// 띠 [id]의 '띠' 기록에 적힌 귀(반지름) — 동맹(띠 9)은 과제 8 걸음 1의 납작한 뚜껑(네 귀 모따기 [LidLook.cham] — lid_tags_test가 그림을 본다).
    /// 끝 꼴([BandLayer.endOf]) · 구멍 · 머리 이름 자리는 뚜껑도 그 꼬리표 끝 그대로다.
    String cornerNote(int id, TagEnd end, double h) =>
        id == 9 ? '반지름=${LidLook.cham.round()}/${LidLook.cham.round()}' : '반지름=${TagLook.cornerOf(end, h).round()}/0';

    (TimelineScene, TimelinePainter) endsScene() => make((t) {
      for (final (id, row, kind, f, _) in ends) {
        t.band(id, row, startOf(id), startOf(id) + 3 * m, '띠 $id', color: sample, look: look(kind: kind), form: f());
        // 관계선 층의 구멍(건국 네모 — 구역 20) — 띠 층이 정한 끝([BandLayer.endOf])을 따른다.
        t.item(LinkLayer.secSquare, 100 + id, row, startOf(id), startOf(id) + 3 * m, ref: id, name: '띠 $id', color: sample);
      }
    });

    test('장면: 띠의 왼쪽 귀 · 머리 이름(구멍 + 7) · 관계선 구멍이 form의 종류 갈래를 따른다 — 교단 · 회사 form은 둥근 끝(구멍 9), 옛 조직체 · 군벌 form 0은 모따기', () async {
      final (scene, painter) = endsScene();
      await settle(scene, painter);
      final holes = noted(painter, '네모');
      for (final (id, _, kind, _, want) in ends) {
        expect(painter.bands.endOf(id), want, reason: '띠 $id(옛 종류 $kind)');
        final rect = painter.debugBands.firstWhere((b) => b.id == id).rect;
        // 한 장 꼬리표(이 배치는 몸통 없는 키 141): 귀 = 모따기 12 · 둥근 끝 24 · 직각 0(동맹은 뚜껑 — [cornerNote]).
        expect(noteOf(painter, id), contains(cornerNote(id, want, rect.height)), reason: '띠 $id의 왼쪽 귀');
        final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab' && l.text == '띠 $id');
        expect(tab.at.dx, closeTo(rect.left + TagLook.holeAt(want, G.head) + TagLook.nameGap, .01), reason: '띠 $id의 머리 이름 = 구멍 + 7');
        final hole = holes.firstWhere((s) => s.startsWith('건국 $id '));
        expect(double.parse(hole.split(' ')[2].split(',')[0]), closeTo(rect.left + TagLook.holeAt(want, G.head), .05), reason: '띠 $id의 관계선 구멍');
      }
      expect(TagLook.holeAt(TagEnd.key, G.head) - TagLook.holeAt(TagEnd.cham, G.head), 2, reason: '둥근 끝은 구멍 · 이름이 2px 안쪽');
    });

    test('스위치 tag를 끄면 form을 보지 않는다 — 모든 띠가 옛 짐작(4단계 전 그림)', () async {
      PaintPick.tag = false;
      final (scene, painter) = endsScene();
      await settle(scene, painter);
      for (final (id, _, kind, _, _) in ends) {
        final guess = TagLook.endOf(look(kind: kind));
        expect(painter.bands.endOf(id), guess, reason: '띠 $id');
        final rect = painter.debugBands.firstWhere((b) => b.id == id).rect;
        expect(noteOf(painter, id), contains(cornerNote(id, guess, rect.height)));
      }
    });

    test('받침 카드 · 종이 틈은 띠의 꼬리표 끝을 따른다 — 기사단 form(둥근 끝)의 카드는 왼쪽 위가 둥글게 비고, form 0(모따기)은 모따기 안까지 칠', () async {
      const host = 0x8b6f47;
      final (scene, painter) = make((t) {
        for (final (id, row, f) in [(1, 0, form('order')), (2, 1, 0)]) {
          t.band(id, row, 2 * m, 7 * m, '갈대 공국 $id', color: sample, look: look(), form: f);
          t.item(BandLayer.sectionHostTab, 50 + id, row, 2 * m, 7 * m, ref: id, name: '하연 왕국', color: host, a: 1, d: 99, text2: 'p/hayeon');
        }
      });
      await settle(scene, painter);
      expect(noted(painter, '뒤장').length, 2, reason: '띠마다 받침 카드 한 장');
      final pixels = await render(painter);
      int at(double x, double y) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      final card = rgba(mixOklab(0xff000000 | host, Look.paper, BandLayer.sheetMix[1]));
      // 카드는 띠 윗변 위로 5 드러난다. 그 드러난 띠의 윗줄 + 1.5에서 왼쪽 끝 + 13.5: 모따기(키 141의 귀 12)는 빗변 안쪽이라 카드 칠,
      // 둥근 끝(귀 24)은 호 밖이라 카드가 없다(그림판 바탕).
      final key = painter.debugBands.firstWhere((b) => b.id == 1).rect, cham = painter.debugBands.firstWhere((b) => b.id == 2).rect;
      final y = key.top - BandLayer.sheetRise + 1.5;
      expect(at(cham.left + 13.5, cham.top - BandLayer.sheetRise + 1.5), card, reason: '모따기 카드 — 빗변 안쪽');
      expect(at(key.left + 13.5, y), isNot(card), reason: '둥근 끝 카드 — 호 밖');
      expect(at(key.left + 30.5, y), card, reason: '둥근 끝 카드도 귀를 지나면 칠');
    });

    /// 대립 장면: 줄 0 = 대립 둘(정부 · 다스림 / 옛 조직체 + 실권 정권 form — 점선 대신 파선) · 줄 1 = 견줌(국가 실선 · 옛 조직체 점선) · 줄 2 = 대립 + 집단(직각 — 테 없음).
    (TimelineScene, TimelinePainter) rivalScene() => make((t) {
      t.band(1, 0, 1 * m, 6 * m, '서하연 조정', color: sample, look: look(), form: form('government', legit: 'rival'));
      t.band(2, 0, 7 * m, 12 * m, '등불 결사', color: sample, look: look(kind: BandKind.org), form: form('regime', legit: 'rival'));
      t.band(3, 1, 1 * m, 6 * m, '하연 왕국', color: sample, look: look(), form: form('state', legit: 'legit'));
      t.band(4, 1, 7 * m, 12 * m, '그믐 결사', color: sample, look: look(kind: BandKind.org));
      t.band(5, 2, 1 * m, 6 * m, '모래 조정', color: sample, look: look(kind: BandKind.client), form: form('group', legit: 'rival'));
    });

    /// 띠 [id]의 윗변 줄(테 한 줄)에서 왼쪽 + 30부터 100px의 픽셀.
    List<int> topRow(ByteData pixels, ui.Rect rect) => [for (int x = (rect.left + 30).floor(); x < (rect.left + 130).floor(); x++) pixels.getUint32((rect.top.floor() * 1920 + x) * 4)];

    /// 띠의 왼쪽 세로 테(귀 아래 ~ 아래 귀 위) 픽셀.
    List<int> leftColumn(ByteData pixels, ui.Rect rect) => [for (int y = (rect.top + 30).floor(); y < (rect.bottom - 30).floor(); y++) pixels.getUint32((y * 1920 + rect.left.floor()) * 4)];

    /// 파선 3 · 2(5px마다 되풀이 — 띠의 진짜 왼쪽 · 윗변에서 잼): 테 빛깔 픽셀이 5로 나눈 나머지 둘 · 셋 자리에만 서고(실선은 다섯 · 점선 1 · 1도 다섯),
    /// 테 픽셀이 2/5 ~ 3/5다. 띄운 자리는 그 밑의 칠이라 테 빛깔인 자리만 센다(세로 눈금은 이제 띠 아래라 띄운 자리에 비치지 않는다 —
    /// 감독 결정 2026-10-25 '세로줄은 늘 바탕' · paint/grid.dart).
    void expectDashed(List<int> px, int edge, String why) {
      final on = {for (int i = 0; i < px.length; i++) if (px[i] == edge) i % 5};
      expect(on.length, inInclusiveRange(2, 3), reason: '$why — 5px마다 같은 자리에만 테(파선 3 · 2)');
      expect(px.where((p) => p == edge).length / px.length, inInclusiveRange(.35, .65), reason: '$why — 테 픽셀은 3/5 언저리');
    }

    /// 이름 글자 상자 안에서 [argb]와 같은 픽셀 수.
    int inkIn(ByteData pixels, TimelinePainter painter, String name, int argb) {
      final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab' && l.text == name);
      var n = 0;
      for (int y = tab.at.dy.floor(); y < (tab.at.dy + BandLayer.tabNameSize * 1.2).ceil(); y++) {
        for (int x = tab.at.dx.floor(); x < tab.at.dx + 60; x++) {
          if (pixels.getUint32((y * 1920 + x) * 4) == rgba(argb)) n++;
        }
      }
      return n;
    }

    test('대립(form 정통성 1): 테는 파선 3 · 2(조직체의 점선 1 · 1보다 이김) · 머리 이름 먹 60 — 칠 · 테 빛깔은 look 그대로', () async {
      final (scene, painter) = rivalScene();
      await settle(scene, painter);
      expect([for (final id in [1, 2, 3, 4]) noteOf(painter, id).split(' ').last], ['dashed', 'dashed', 'solid', 'dotted'], reason: '대립 둘은 파선 · 견줌은 실선 · 점선');
      final tone = BandLayer.toneOf(sample, look(), fuzzy: false);
      expect(noteOf(painter, 1), contains('바탕=${tone.fill.toRadixString(16)} 테두리=${tone.edge.toRadixString(16)}'), reason: '빛깔은 look 그대로');
      final pixels = await render(painter);
      ui.Rect rectOf(int id) => painter.debugBands.firstWhere((b) => b.id == id).rect;
      // 윗변: 대립은 5px마다 되풀이(3 긋고 2 띄움 — 띠의 진짜 왼쪽에서 잼) · 테가 아닌 칸이 있다. 견줌(실선)은 모두 테.
      for (final (id, lk) in [(1, look()), (2, look(kind: BandKind.org))]) {
        final edge = rgba(BandLayer.toneOf(sample, lk, fuzzy: false).edge);
        expectDashed(topRow(pixels, rectOf(id)), edge, '띠 $id 윗변');
        expectDashed(leftColumn(pixels, rectOf(id)), edge, '띠 $id 왼쪽 세로 테');
      }
      expect(topRow(pixels, rectOf(3)), everyElement(rgba(tone.edge)), reason: '대립이 아닌 띠는 실선');
      // 머리 이름: 대립은 먹 60 · 견줌은 나라 색 + 먹 22%(그림판 먹 단계 60은 없음).
      expect(inkIn(pixels, painter, '서하연 조정', TagLook.rivalName), greaterThan(0), reason: '대립 이름 먹 60');
      expect(inkIn(pixels, painter, '등불 결사', TagLook.rivalName), greaterThan(0));
      expect(inkIn(pixels, painter, '하연 왕국', TagLook.rivalName), 0);
      expect(inkIn(pixels, painter, '하연 왕국', mixSrgb(0xff000000 | sample, Look.ink, .22)), greaterThan(0), reason: '견줌 — 나라 색 + 먹');
      expect(TagLook.rivalName, CanvasInk.k60);
    });

    test('대립 + 무리(집단 — 직각): 테가 없는 그대로 · 이름만 먹 60', () async {
      final (scene, painter) = rivalScene();
      await settle(scene, painter);
      final rect = painter.debugBands.firstWhere((b) => b.id == 5).rect;
      expect(painter.bands.endOf(5), TagEnd.plain);
      expect(noteOf(painter, 5), contains('반지름=0/0'));
      final pixels = await render(painter);
      final fill = BandLayer.toneOf(sample, look(kind: BandKind.client), fuzzy: false).fill;
      expect(topRow(pixels, rect), everyElement(rgba(fill)), reason: '윗변에 테(실선 · 파선 모두)가 없다 — 칠만');
      expect(inkIn(pixels, painter, '모래 조정', TagLook.rivalName), greaterThan(0));
    });

    test('스위치 tag를 끄면 대립도 예전 그대로 — 테는 look의 선 · 이름은 나라 색 + 먹', () async {
      PaintPick.tag = false;
      final (scene, painter) = rivalScene();
      await settle(scene, painter);
      expect([for (final id in [1, 2]) noteOf(painter, id).split(' ').last], ['solid', 'dotted']);
      final pixels = await render(painter);
      final edge = BandLayer.toneOf(sample, look(), fuzzy: false).edge;
      expect(topRow(pixels, painter.debugBands.firstWhere((b) => b.id == 1).rect), everyElement(rgba(edge)));
      expect(inkIn(pixels, painter, '서하연 조정', TagLook.rivalName), 0);
    });

    test('한 장 꼬리표(새 저장소의 두 장 ㄴ 배치)에서도 — 바깥 테가 파선 · 켜 사이 금은 실선 · 둥근 끝은 구멍 9', () async {
      final shape = SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
        'tracks': [
          {
            'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'leader': 0,
            'rows': [
              for (final id in [0, 1])
                {...row(id), 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
                  'fig_wide': (1 << 3) | (1 << 19), 'dep': 0, 'zones': 0, 'hem': 0},
            ],
          },
        ],
      });
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 6 * m, '서하연 조정', color: sample, look: look(), form: form('government', legit: 'rival'));
        t.band(2, 1, 1 * m, 6 * m, '등불 교단', color: sample, look: look(kind: BandKind.org), form: form('faith'));
      }, shape: shape);
      await settle(scene, painter);
      expect(scene.layout.geo(0).bodyTop, greaterThanOrEqualTo(0), reason: '두 장 ㄴ 배치');
      expect(noteOf(painter, 1), contains('한 장 색줄=14'));
      final pixels = await render(painter);
      final rival = painter.debugBands.firstWhere((b) => b.id == 1).rect;
      final tone = BandLayer.toneOf(sample, look(), fuzzy: false);
      expectDashed(topRow(pixels, rival), rgba(tone.edge), '바깥 테(윗변)');
      // 색줄 아랫변의 켜 사이 금(테보다 옅은 고른 색)은 실선 그대로.
      final inner = [for (int x = (rival.left + 30).floor(); x < (rival.left + 130).floor(); x++) pixels.getUint32(((rival.top + G.head - 1).floor() * 1920 + x) * 4)];
      expect(inner, everyElement(rgba(mixSrgb(over(tone.edge, Look.paper), Look.paper, BandLayer.innerLine))), reason: '켜 사이 금은 실선');
      // 교단 form — 둥근 끝 · 구멍 9(이름 = 띠 왼쪽 + 16).
      final faith = painter.debugBands.firstWhere((b) => b.id == 2).rect;
      expect(painter.bands.endOf(2), TagEnd.key);
      final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab' && l.text == '등불 교단');
      expect(tab.at.dx, closeTo(faith.left + TagLook.holeAt(TagEnd.key, G.head) + TagLook.nameGap, .01));
    });
  });

  // 정통성 넷 가 다듬은 꼴(lg2-ga — 칸 그림 갈래 걸음 3 · 스위치 legit · 다듬기 판 `themes/g-legit2.js`): 띠 자체의 주장 = 이름 색줄 바탕 빗금(이름 끝 + 6부터) ·
  // 소속 구간(구역 58 ↔ 구역 47의 상국 탭 — 같은 띠 · 같은 소속 순번 b): 명목 = 탭 글 먹 45 · 탭 테와 이어진 뒤 장 테 먹 25 · 주장 = 탭 칠 빗금 · 대립 = 파선 테.
  group('정통성 무늬 — 띠 주장 머리 빗금 · 소속 구간(칸 그림 갈래 걸음 3)', () {
    tearDown(PaintPick.reset);
    const host = 0x8b6f47;

    int form(String type, {String legit = ''}) => (BandForm.types.indexOf(type) + 1) | (legit.isEmpty ? 0 : BandForm.legits.indexOf(legit) + 1) << 10;

    /// 한 장 꼬리표(새 저장소의 두 장 ㄴ 배치) 줄 둘.
    SceneLayout twoPiece() => SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'leader': 0,
          'rows': [
            for (final id in [0, 1])
              {...row(id), 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
                'fig_wide': (1 << 3) | (1 << 19), 'dep': 0, 'zones': 0, 'hem': 0},
          ],
        },
      ],
    });

    /// 주장 빗금(5px 칸의 1px 화소 계단 — 칸 (i, 4 − i))이 화소 [x] · [y]에 서는가(분 0이 선 열 · [phaseY]에 붙음).
    bool stair(TimelineScene scene, int x, int y, double phaseY) => ((x - LegitLook.phaseX(scene.controller.view.xOf(0))) % 5 + (y - phaseY) % 5).round() == 4;

    /// 두 RGBA 픽셀이 채널마다 ±2 안에서 같은가.
    bool close(int a, int b) => [24, 16, 8].every((s) => (((a >> s) & 0xff) - ((b >> s) & 0xff)).abs() <= 2);

    /// [x0] ~ [x1) × [y0] ~ [y1)이 빗금 자리는 [fill] 위 먹 25 · 그 밖은 [fill] 그대로인가.
    void expectHatch(TimelineScene scene, ByteData pixels, int x0, int x1, int y0, int y1, int fill, double phaseY, String why) {
      final ink = rgba(over(CanvasInk.alpha(LegitLook.hatchInk), fill));
      var stairs = 0;
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final got = pixels.getUint32((y * 1920 + x) * 4), want = stair(scene, x, y, phaseY);
          if (want) stairs++;
          expect(want ? close(got, ink) : got == rgba(fill), isTrue, reason: '$why ($x, $y) ${got.toRadixString(16)} 빗금=$want');
        }
      }
      expect(stairs, greaterThan(0), reason: '$why — 빗금이 없다');
    }

    test('띠 자체의 주장: 이름 색줄 바탕(윗 테 아래 ~ 아랫금 위)에 1px 화소 빗금 먹 25 — 이름 끝 + 6부터 · 구멍과 이름 둘레는 띠 칠 · 끄면 없음', () async {
      Future<(TimelineScene, TimelinePainter, ByteData)> scene() async {
        final (scene, painter) = make((t) {
          t.band(1, 0, 1 * m, 6 * m, '붉은탑 망명 조정', color: sample, look: look(), form: form('government', legit: 'claim'));
          t.band(2, 1, 1 * m, 6 * m, '하연 왕국', color: sample, look: look(), form: form('state', legit: 'legit'));
        }, shape: twoPiece());
        await settle(scene, painter);
        return (scene, painter, await render(painter));
      }

      final (s, painter, pixels) = await scene();
      final rect = painter.debugBands.firstWhere((b) => b.id == 1).rect, top = rect.top.round();
      final end = painter.bands.headNameEnd[1]!, from = (end + LegitLook.headPad).ceil();
      expect(nums(noted(painter, '주장머리').single)[1], closeTo(from * 10, .5), reason: '빗금 시작 = 이름 끝 + 6');
      final fill = BandLayer.toneOf(sample, look(), fuzzy: false).fill;
      expectHatch(s, pixels, from, from + 60, top + 1, top + G.head.round() - 1, fill, top.toDouble(), '머리 빗금');
      // 이름 끝 ~ + 6은 띠 칠(받침) · 색줄 아랫금(+ 13)과 윗 테(+ 0)는 그대로.
      for (int x = end.ceil() + 2; x < from; x++) {
        for (int y = top + 1; y < top + G.head.round() - 1; y++) {
          expect(pixels.getUint32((y * 1920 + x) * 4), rgba(fill), reason: '받침 ($x, $y)');
        }
      }
      final line = rgba(mixSrgb(over(BandLayer.toneOf(sample, look(), fuzzy: false).edge, Look.paper), Look.paper, BandLayer.innerLine));
      for (int x = from; x < from + 60; x++) {
        expect(pixels.getUint32(((top + G.head.round() - 1) * 1920 + x) * 4), line, reason: '색줄 아랫금 ($x)');
      }
      expect(noted(painter, '주장머리').length, 1, reason: '주장이 아닌 띠(하연 왕국)에는 없다');
      // 스위치 legit을 끄면 빗금이 없다.
      PaintPick.legit = false;
      final (_, offPainter, offPixels) = await scene();
      expect(noted(offPainter, '주장머리'), isEmpty);
      for (int x = from; x < from + 60; x++) {
        expect(offPixels.getUint32(((top + 3) * 1920 + x) * 4), rgba(fill));
      }
    });

    /// 줄 셋의 속국 띠(갈대 공국 1 · 2 · 3 — 2 ~ 9 백만 분)마다 상국 탭(구역 47 · 소속 순번 0)과 그 소속의 정통성(구역 58 — [legits] 차례: 명목 · 주장 · 대립).
    Future<(TimelineScene, TimelinePainter, ByteData)> hosted({bool legits = true}) async {
      final (scene, painter) = make((t) {
        for (final (id, legit) in [(1, 'nominal'), (2, 'claim'), (3, 'rival')]) {
          t.band(id, id - 1, 2 * m, 9 * m, '갈대 공국 $id', color: sample, look: look());
          t.item(BandLayer.sectionHostTab, 50 + id, id - 1, 2 * m, 9 * m, ref: id, name: '빙원 동맹', color: host, a: 1, b: 0, d: 99, text2: 'p/icefield');
          if (legits) {
            t.item(Schema4.secHostLegit, 60 + id, id - 1, 2 * m, 9 * m, ref: id, name: '빙원 동맹', color: host, b: 0, d: BandForm.legits.indexOf(legit) + 1, text2: 'p/icefield');
          }
        }
      });
      await settle(scene, painter);
      return (scene, painter, await render(painter));
    }

    test('소속 구간: 명목 = 탭 글 먹 45 · 탭 테와 이어진 뒤 장 테 먹 25 / 주장 = 탭 칠 빗금(글 앞뒤 1 받침 · 모따기 귀 밖) / 대립 = 탭 · 뒤 장 파선 테', () async {
      final (s, painter, pixels) = await hosted();
      expect(noted(painter, '소속정통'), ['1 빙원 동맹 4', '2 빙원 동맹 5', '3 빙원 동맹 1']);
      int at(num x, num y) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
      ui.Rect bandOf(int id) => painter.debugBands.firstWhere((b) => b.id == id).rect;
      (double, double) tabOf(int id) {
        final n = nums(noted(painter, '상국탭').firstWhere((v) => v.startsWith('$id ')));
        return (n[1] / 10, n[2] / 10);
      }

      final hc = 0xff000000 | host, fill = mixOklab(hc, Look.paper, BandLayer.sheetMix[1]), edge = mixOklab(hc, Look.ink, .78);
      // 명목: 탭 윗 테(모따기 뒤) · 탭 밖 뒤 장 윗변이 먹 25.
      {
        final (x, w) = tabOf(1);
        final top = bandOf(1).top.round(), tabTop = top - BandLayer.sheetRise.round() - TagLook.tabH.round();
        for (int px = (x + TagLook.tabCham + 1).ceil(); px < x + w - 1; px++) {
          expect(at(px, tabTop), rgba(LegitLook.nominalLine), reason: '명목 탭 윗 테 ($px)');
        }
        final sheetTop = top - BandLayer.sheetRise.round();
        for (int px = (x - 40).round(); px < x - 10; px++) {
          expect(close(at(px, sheetTop), rgba(LegitLook.nominalLine)), isTrue, reason: '명목 뒤 장 윗 테 ($px) ${at(px, sheetTop).toRadixString(16)}');
        }
        final label = painter.debugLabels.firstWhere((l) => l.kind == 'hostTab' && (l.at.dx - (x + 7)).abs() < .5);
        var dark = 0;
        for (int y = label.at.dy.floor(); y < label.at.dy + 11; y++) {
          for (int px = label.at.dx.floor(); px < x + w - 7; px++) {
            if (at(px, y) == rgba(LegitLook.nominalName)) dark++;
          }
        }
        expect(dark, greaterThan(0), reason: '명목 탭 글 먹 45');
      }
      // 주장: 탭 칠(글 받침 오른쪽)에 빗금 · 글 받침은 칠 그대로.
      {
        final top = bandOf(2).top.round(), tabTop = top - BandLayer.sheetRise.round() - TagLook.tabH.round();
        // 기록: 테 안 왼쪽 · 글 받침 왼쪽 · 오른쪽 · 테 안 오른쪽(오른쪽 테 열) · 윗 테 아래 줄.
        final n = [for (final v in nums(noted(painter, '주장탭').single)) (v / 10).round()];
        final (inL, gapL, gapR, inR, inT) = (n[0], n[1], n[2], n[3], n[4]);
        final (x, w) = tabOf(2);
        expect([(inL - x).abs() <= 1.5, (inR - (x + w - 1)).abs() <= 1.5, inT == tabTop + 1], everyElement(isTrue), reason: '빗금은 그 탭의 테 안');
        expectHatch(s, pixels, gapR, inR, inT, inT + TagLook.tabH.round(), fill, inT - 1.0, '주장 탭 오른쪽');
        expectHatch(s, pixels, inL, gapL, inT + TagLook.tabCham.round(), inT + TagLook.tabH.round(), fill, inT - 1.0, '주장 탭 왼쪽(귀 아래)');
        for (int px = gapL; px < gapR; px++) {
          expect(at(px, inT), rgba(fill), reason: '글 받침 ($px)');
        }
        for (int y = inT + TagLook.tabCham.round(); y < inT + TagLook.tabH.round() - 1; y++) {
          expect([at(inL - 1, y), at(inR, y)], everyElement(rgba(edge)), reason: '두 옆 테는 그대로 (y $y)');
        }
      }
      // 대립: 탭 윗 테와 뒤 장 윗변이 파선(테 빛깔 화소가 2/5 ~ 3/5).
      {
        final (x, w) = tabOf(3);
        final top = bandOf(3).top.round(), tabTop = top - BandLayer.sheetRise.round() - TagLook.tabH.round();
        final tabRow = [for (int px = (x + TagLook.tabCham + 1).ceil(); px < x + w - 1; px++) at(px, tabTop)];
        final share = tabRow.where((p) => p == rgba(edge)).length / tabRow.length;
        expect(share, inInclusiveRange(.3, .7), reason: '대립 탭 윗 테는 파선');
        final sheetRow = [for (int px = (x - 60).round(); px < x - 10; px++) at(px, top - BandLayer.sheetRise.round())];
        final sheetShare = sheetRow.where((p) => close(p, rgba(edge))).length / sheetRow.length;
        expect(sheetShare, inInclusiveRange(.3, .7), reason: '대립 뒤 장 윗변도 파선');
      }
    });

    test('구역 58이 없거나 스위치 legit을 끄면 상국 탭 · 뒤 장은 예전 그대로(픽셀 같음)', () async {
      final (_, plainPainter, plain) = await hosted(legits: false);
      PaintPick.legit = false;
      final (_, offPainter, off) = await hosted();
      expect(noted(plainPainter, '소속정통'), isEmpty);
      expect(noted(offPainter, '소속정통'), isEmpty);
      expect(off.buffer.asUint8List(), plain.buffer.asUint8List());
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

  // 4단계 감독 고름 G5 #8 흠 라 ②(2026-10-25 · 차례 걸음 13 · 스위치 flaw · 고르기 판 g-g5-8.js pickRing · 기준 그림 g58-ra.png): 예전 고른 테는 꼬리표만 감싸
  // 받침 카드의 드러난 윗단(5)을 가로질렀다 — 카드가 있는 고른 띠는 테가 카드까지 감싼다(위 = 카드 윗변 − 1 · 오른쪽 = 카드와 띠 가운데 큰 쪽 + 1 ·
  // 왼쪽 귀 = 띠의 끝 꼴 — 카드가 첫머리에 서면 위 귀는 카드의 귀를 두름) · 상국 탭은 테 위 · 굵기 1 그대로(앱 B안 — 목업 1.5는 감독 확인 전 바꾸지 않음).
  group('흠 ② 고른 테가 받침 카드까지 감쌈(G5 #8 흠 라)', () {
    const host = 0x8b6f47;

    /// 줄 0의 띠 갈대 공국(2 ~ 9 백만 분)을 고른 장면 — 하연 왕국의 받침 카드는 [from] ~ 8.
    Future<(TimelineScene, TimelinePainter, ByteData)> picked({double from = 4 * m, SceneLayout? shape}) async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 2 * m, 9 * m, '갈대 공국', color: sample, look: look());
        t.item(BandLayer.sectionHostTab, 51, 0, from, 8 * m, ref: 1, name: '하연 왕국', color: host, a: 1, d: 99, text2: 'p/hayeon');
        t.band(2, 1, 2 * m, 9 * m, '하연 왕국', color: host, look: look());
      }, shape: shape);
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 1));
      await settle(scene, painter);
      return (scene, painter, await render(painter));
    }

    int px(ByteData p, double x, double y) => p.getUint32((y.floor() * 1920 + x.floor()) * 4);
    final ink = rgba(Look.ink);

    test('테가 카드 윗변 − 1까지 올라 카드의 드러난 윗단을 가로지르지 않는다 · 오른쪽은 띠 끝 + 1 · 왼쪽 귀는 띠의 모따기 · 상국 탭이 테 위', () async {
      final (scene, painter, pixels) = await picked();
      final band = painter.debugBands.firstWhere((b) => b.id == 1).rect;
      final cardTop = band.top - BandLayer.sheetRise, cardL = scene.controller.view.xOf(4 * m);
      final note = nums(noted(painter, '고른테').single);
      final want = [1, band.left - 1, cardTop - 1, band.right + 1, band.bottom + 1];
      for (int i = 0; i < want.length; i++) {
        expect(note[i], closeTo(want[i], .06), reason: '고른테 기록 $i: 띠 · 왼쪽 · 위 · 오른쪽 · 아래');
      }
      // 윗변: 카드 윗변 − 1 줄이 먹 — 카드 앞(띠 첫머리 쪽) · 카드 위 모두. 예전 자리(띠 윗변 − 1)는 먹이 아니다.
      for (final x in [band.left + 20, cardL + 20, band.right - 20]) {
        expect(px(pixels, x, cardTop - 1), ink, reason: 'x $x: 새 윗변');
        expect(px(pixels, x, band.top - 1), isNot(ink), reason: 'x $x: 예전 윗변 자리는 비었다');
        expect(px(pixels, x, cardTop), isNot(ink), reason: 'x $x: 카드 윗단은 테가 가리지 않는다');
      }
      // 오른쪽 세로(띠 끝 + 1의 바깥 1px)는 카드 윗변 − 1부터 — 띠 옆 몫은 예전 테와 같은 길(띠 끝이 픽셀 반 넘게 걸치면 그 픽셀은 띠 칠이 덮는다 —
      // 예전부터의 꼴이라 여기서는 띠 위로 솟은 몫만 본다).
      expect(px(pixels, band.right, cardTop + 2), ink);
      expect(px(pixels, band.right + 1, cardTop + 2), isNot(ink), reason: '오른쪽은 띠 끝 + 1까지(카드는 띠 안에서 끝남)');
      // 왼쪽 세로 · 모따기 귀: 귀 아래는 먹, 맨 위 귀 자리는 비고(모따기), 귀의 빗변 위 한 점은 먹.
      final k = TagLook.cornerOf(TagEnd.cham, band.height) + 1;
      expect(px(pixels, band.left - 1, cardTop - 1 + k + 2), ink, reason: '왼쪽 세로');
      expect(px(pixels, band.left - 1, cardTop - 1), isNot(ink), reason: '왼쪽 위 귀는 모따기');
      // 상국 탭(카드 윗변 위로 솟은 탭 — 테의 윗변 줄을 덮음)은 테 위: 탭 안 테 줄은 먹이 아니다.
      final tab = nums(noted(painter, '상국탭').single);
      final tx = tab[1] / 10, tw = tab[2] / 10;
      expect(px(pixels, tx + tw / 2, cardTop - 1), isNot(ink), reason: '상국 탭이 테 위');
      expect(px(pixels, tx - 3, cardTop - 1), ink, reason: '탭 밖은 테');
    });

    test('카드가 띠 첫머리에 서면 위 귀가 카드의 귀를 두른다 · 한 장 꼬리표(새 저장소 배치)에서도 같다', () async {
      final shape = SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
        'tracks': [
          {
            'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'leader': 0,
            'rows': [
              for (final id in [0, 1])
                {...row(id), 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
                  'fig_wide': (1 << 3) | (1 << 19), 'dep': 0, 'zones': 0, 'hem': 0},
            ],
          },
        ],
      });
      final (scene, painter, pixels) = await picked(from: 2 * m, shape: shape);
      expect(noteOf(painter, 1), contains('한 장'));
      final band = painter.debugBands.firstWhere((b) => b.id == 1).rect;
      final cardTop = band.top - BandLayer.sheetRise;
      expect(nums(noted(painter, '고른테').single)[2], cardTop - 1);
      // 위 귀 = 카드의 귀(키 = 띠 높이의 모따기) + 1 — 그 아래 왼쪽 세로가 먹, 귀 안쪽 빗변 자리.
      final h = scene.layout.geo(0).bandHeight, kt = TagLook.cornerOf(TagEnd.cham, h) + 1;
      expect(px(pixels, band.left - 1, cardTop - 1 + kt + 1), ink, reason: '귀 아래 왼쪽 세로');
      expect(px(pixels, band.left - 1, cardTop - 1 + kt - 2), isNot(ink), reason: '귀 자리는 비었다(모따기)');
      expect(px(pixels, band.left + 20, cardTop - 1), ink);
    });

    test('스위치 flaw를 끄면 예전 — 꼬리표만 감싸 테가 띠 윗변 − 1(카드의 드러난 윗단을 가로지름) · 카드 없는 고른 띠는 켜도 예전과 같다', () async {
      PaintPick.flaw = false;
      addTearDown(PaintPick.reset);
      final (_, painter, pixels) = await picked();
      expect(noted(painter, '고른테'), isEmpty);
      final band = painter.debugBands.firstWhere((b) => b.id == 1).rect;
      expect(px(pixels, band.left + 20, band.top - 1), ink);
      expect(px(pixels, band.left + 20, band.top - BandLayer.sheetRise - 1), isNot(ink));
      PaintPick.reset();
      // 카드 없는 고른 띠(줄 1의 하연 왕국)는 켜도 테가 띠 윗변 − 1.
      final (scene2, painter2) = make((t) => t.band(1, 0, 2 * m, 9 * m, '갈대 공국', color: sample, look: look()));
      em.Emphasis.of(scene2)
        ..reduceMotion = true
        ..set(const em.Look(band: 1));
      await settle(scene2, painter2);
      final p2 = await render(painter2);
      final b2 = painter2.debugBands.firstWhere((b) => b.id == 1).rect;
      expect(noted(painter2, '고른테'), isEmpty);
      expect(px(p2, b2.left + 20, b2.top - 1), ink);
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

    // 자동 조감(보기 폭이 2,600년을 넘음 — 보기 조건 autoBird)도 조감이다(지금 연표의 `isBird()` · js:1434 · 1742). 예전에는 격자 층이 밀도만 보아
    // (`density >= 2`) 자동 조감에서 세로 점선 · 0년 파선 · 현재선을 띠 **위**에 그어 띠 안 이름을 가로질렀다(2026-10-25 조감 글자 겹침 검증).
    // remake-4-int에서 remake-4-grid(감독 결정 2026-10-25 — 세로줄은 밀도와 상관없이 늘 띠 아래 바탕 · grid_under_test)와 합침: 보통 밀도도 띠 안은
    // 한 빛깔이 되어, 이 검사가 선을 잡는다는 증거는 띠 밖 바탕(줄 아래 · y 700 ~ 1060)의 점선 기둥으로 세운다(grid_under_test와 같은 판별).
    test('자동 조감에서도 세로 점선은 띠 아래다 — 띠 안은 바탕 한 빛깔', () async {
      Future<(Set<int>, int)> inside(ViewConditions Function(ViewConditions)? wanted) async {
        final (scene, painter) = make((t) => t.band(1, 0, 0, 40 * m, '별여울국', color: sample, look: look()));
        if (wanted != null) scene.layout.setConditions(wanted(scene.layout.conditions));
        await settle(scene, painter);
        final rect = painter.debugBands.single.rect;
        final pixels = await render(painter);
        int at(int x, int y) => pixels.getUint32((y * 1920 + x) * 4);
        final seen = <int>{};
        final right = rect.right < 1900 ? rect.right - 20 : 1900.0;
        // 이름(띠 시작 + 6)에서 떨어진 몸통 · 띠 가운데 아래 두 줄(점선은 1 켜고 1 끔이라 두 줄이면 반드시 걸린다).
        for (double x = rect.left + 120; x < right; x++) {
          for (final y in [rect.center.dy + 1, rect.center.dy + 2]) {
            seen.add(at(x.floor(), y.floor()));
          }
        }
        // 띠 밖 바탕의 점선 기둥 수 — 양옆 기둥은 위아래 두 줄이 같은 색인데 이 기둥만 위아래가 다르다(바탕 구간 띠 · 가로 금은 이 꼴이 아님).
        var columns = 0;
        for (int x = SceneView.gutter.toInt() + 2; x < 1918; x++) {
          var hits = 0;
          for (int y = 700; y < 1060; y++) {
            final side = at(x - 1, y);
            if (at(x + 1, y) != side || at(x - 1, y + 1) != side || at(x + 1, y + 1) != side) continue;
            if (at(x, y) != at(x, y + 1)) hits++;
          }
          if (hits > 20) columns++;
        }
        return (seen, columns);
      }

      final normal = await inside(null);
      expect(normal.$2, greaterThan(5), reason: '띠 밖 바탕에는 세로 점선이 보인다 — 이 검사가 선을 잡는다는 증거');
      expect(normal.$1, hasLength(1), reason: '보통 밀도도 세로 점선은 띠 아래(remake-4-grid — 감독 결정 2026-10-25)');
      expect((await inside((c) => c.copyWith(density: 2))).$1, hasLength(1), reason: '밀도 조감(V)');
      expect((await inside((c) => c.copyWith(autoBird: true))).$1, hasLength(1), reason: '자동 조감도 격자가 띠 아래');
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
