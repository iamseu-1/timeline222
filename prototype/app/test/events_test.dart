import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/hit_test.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/lens_titles.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/physics.dart';
import 'package:archive_prototype/motion.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

/// 줄 생김새를 그대로 실은 옛 저장소의 줄(`kind` 없음 — 글줄 21 · 글줄 자리 66). 두 장 꼬리표(새 저장소)의 사건 칸은 아래 '두 장 꼬리표' 시험이 본다.
Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

const m = 1000000.0;

/// 분류별 글줄이 없는 줄의 모양: 글줄 번호 255 = 자유 배치.
const freeLane = 255 << 8;

/// 날짜 정밀도 '분'(rail 8~10비트) — 정밀도 구간이 없어 점이 제 시각에 그대로 선다.
const minutePrec = 4 << 8;
final ppm = 32 / bucketMinutes(9); // 통 32px → 단계 9
double px(double pixels) => pixels / ppm; // 화면 px → 분

/// 타일 하나(단계 9 · x 1)에 사건 넷과 나머지 개수 하나, 긴 기간 막대 하나.
/// [dates]면 사건에 날짜 글을 실어 이름 옆 연도까지 재게 하고, [hold]를 주면 이름 자리 계산의 답을 붙잡아 둔다(그 목록의 함수를 부르면 답이 온다).
(TimelineScene, TimelinePainter) make({double Function()? clock, SceneText? text, bool dates = false, List<void Function()>? hold}) {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(284);
  final origin = tileOrigin(9, 1).toDouble();
  controller.showRange(origin, origin + (1920 - SceneView.gutter) / ppm);
  final tile = TileBuilder(level: 9, x: 1, chunk: 0)
    ..band(1, 0, 0, px(1700), '별여울국')
    ..event(11, 0, px(200), '별여울의 첫 기록', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, label: dates ? '838년' : '')
    ..event(12, 0, px(206), '묻힌 작은 일', bits: 1 | Tile.counted, look: freeLane, rail: minutePrec, label: dates ? '839년' : '') // 11번과 6px
    ..event(13, 0, px(700), '해솔의 나루 열기', bits: 2 | Tile.counted, look: freeLane, rail: minutePrec, label: dates ? '851년' : '')
    ..event(14, 1, px(900), '은빛 나루의 약속', bits: 1 | Tile.counted, look: freeLane, rail: minutePrec, label: dates ? '866년' : '')
    ..event(15, 1, px(300), '긴 공사', x1: px(620), bits: 2 | Tile.bar | Tile.counted, look: freeLane)
    ..pill(0, px(192), px(224), 37) // 11 · 12번이 든 통의 나머지 — 그 통은 이름으로 꽉 차 있다
    ..pill(0, px(1200), px(1232), 12); // 대표가 하나도 없는 통 — 제 개수 알약으로 선다
  final bytes = tile.build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 5}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]}],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
    labelCompute: hold == null
        ? (input) async => placeLabels(input)
        : (input) {
            final waiting = Completer<LabelOutput>();
            hold.add(() => waiting.complete(placeLabels(input)));
            return waiting.future;
          },
    clock: clock,
  );
  return (scene, TimelinePainter(scene, text: text ?? unbudgetedText())..debug = true);
}

/// 몸통 안의 세로 자리(줄 자리 기준) → 배치 y. 날짜 칸의 높이는 날짜 칸의 구성이 정하므로 하드코딩하지 않는다.
double bodyY(TimelineScene scene, double y) => scene.controller.view.yOf(y);

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

/// 타일이 오고, 이름 폭이 준비되고, 이름 자리가 계산될 때까지 장면을 돌린다.
Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  int calm = 0;
  for (int i = 0; i < 80 && calm < 3; i++) {
    paint(painter);
    await pumpEventQueue();
    final out = scene.labelOutput;
    calm = out != null && out.deferred == 0 && !scene.labelWorker.busy ? calm + 1 : 0;
  }
}

void main() {
  test('점은 글줄에 놓이고, 통의 나머지 개수는 개수 알약 하나로 선다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    expect(painter.debugDots.map((d) => d.eventId).toList()..sort(), [11, 12, 13, 14, 15], reason: '기간이 있는 15번도 글줄에는 점으로 선다');
    final lead = painter.debugDots.firstWhere((d) => d.eventId == 11);
    // 11번은 이름이 뒤집혀 붙는다 — 뒤집힌 `.tl-ev`는 점이 `it.x + 1.5 − 점폭/2`에 선다(명세 8.3-1 · 9.4).
    expect(lead.at.dx, closeTo(SceneView.gutter + 200 + EventLook.dotDx(freeLane, side: LabelSide.left), .01));
    expect(EventLook.dotDx(freeLane, side: LabelSide.left), -2);
    // 글줄의 가운데 = 줄의 글줄 자리 66 + 글줄 높이 21 × 글줄 번호 + 10.5.
    expect(lead.at.dy, closeTo(bodyY(scene, 66 + 10.5), .01), reason: '가장 중요한 사건이 첫 글줄을 차지한다');
    expect(painter.debugDots.firstWhere((d) => d.eventId == 12).at.dy, closeTo(bodyY(scene, 66 + 21 + 10.5), .01), reason: '첫 글줄이 찬 뒤의 둘째 글줄');
    expect(painter.debugDots.firstWhere((d) => d.eventId == 14).at.dy, closeTo(bodyY(scene, 142 + 66 + 10.5), .01), reason: '둘째 줄의 첫 글줄');
    final out = scene.labelOutput!;
    expect(out.clusters, 1);
    expect(out.clusterCount[0], 12, reason: '대표가 없는 통은 제 개수 알약으로 선다');
    expect(out.clusterRow[0], 0);
    // 이름으로 꽉 찬 통의 나머지는 그 통의 으뜸 대표 뒤에 포갠다(동전 겹침 — 지금 연표의 .has-more와 같은 모습).
    final at11 = [for (int i = 0; i < out.shownCount; i++) if (scene.labelBatch!.input.eventId[out.shownCandidate[i]] == 11) i].single;
    expect(out.shownCoins[at11], 37);
    expect(out.shownFlags[at11] & LabelFlag.more, LabelFlag.more);
    final names = painter.debugLabels.where((l) => l.kind == 'event').map((l) => l.text).toSet();
    expect(names, {'별여울의 첫 기록', '묻힌 작은 일', '해솔의 나루 열기', '은빛 나루의 약속', '긴 공사'});
  });

  test('기간이 있는 사건은 글줄의 점 · 이름과 기간 막대 칸에서 모두 잡힌다', () async {
    // 지금 연표도 기간 사건에 `.tl-ev`(점 + 이름)와 `.tl-rail`(막대)을 함께 둔다. 막대 자체를 그리는 일은 기간 막대 칸(구역 33~36 · paint/rails.dart)의 몫이다.
    final (scene, painter) = make();
    await settle(scene, painter);
    final dot = painter.debugDots.firstWhere((d) => d.eventId == 15);
    expect(dot.at.dx, closeTo(SceneView.gutter + 300, .01), reason: '점은 시작 자리에 선다');
    expect(painter.debugLabels.where((l) => l.kind == 'event' && l.text == '긴 공사'), isNotEmpty);
    // 막대의 자리 = 그 줄의 railTop + 3.5 + 단 × 7.
    expect(hitTest(scene, SceneView.gutter + 400, bodyY(scene, 142 + 108 + railOffset)).eventId, 15);
    expect(hitTest(scene, SceneView.gutter + 400, bodyY(scene, 142 + 108 + railOffset + 20)).kind, HitKind.none, reason: '막대에서 멀면 잡히지 않는다');
  });

  // 0.1.0 1배 지적(등불 150년 보기 · 짝 꼬리표 장면의 1459년 자리): 진행 중인 조약처럼 긴 기간 사건은 시작이 든 타일 뒤의 타일에도 막대 조각
  // (구역 3의 막대 · 왼쪽 잘림 — 계약 6절 bits 4 · 8)으로 실린다. 그 조각의 x0은 타일 시작으로 잘린 값이라, 점으로 세우면 타일 경계마다 띠를 못 찾은(±무한)
  // 마름모 · 이름 · 개수 알약이 끝난 띠 뒤 바탕에 떴다. 점은 시작에 하나다.
  test('긴 기간 사건의 점은 시작에 하나 — 다음 타일로 이어진 막대 조각(왼쪽 잘림)은 점 · 이름 · 개수 알약이 되지 않는다', () async {
    final controller = TimelineController()
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(284);
    final span = tileSpan(9).toDouble(), o2 = tileOrigin(9, 2).toDouble();
    // 타일 1 · 2의 경계가 화면 가운데(그림판 왼쪽 + 800)에 온다.
    controller.showRange(o2 - px(800), o2 + px(880));
    // 띠는 경계 300px 앞에서 끝나고, 그 띠 안에서 시작한 긴 사건 둘(진행 중 — 막대가 다음 타일로 이어짐)이 같은 줄에 있다.
    final first = (TileBuilder(level: 9, x: 1, chunk: 0)
          ..band(1, 0, span - px(1300), span - px(300), '산호 해상 동맹')
          ..event(21, 0, span - px(600), '오랜 통상 화약', x1: span, bits: 2 | Tile.bar | Tile.counted | Tile.eventClipRight, look: freeLane, rail: minutePrec, band: 1)
          ..event(22, 0, span - px(450), '주권 반환 협정', x1: span, bits: 2 | Tile.bar | Tile.counted | Tile.eventClipRight, look: freeLane, rail: minutePrec, band: 1))
        .build();
    final second = (TileBuilder(level: 9, x: 2, chunk: 0)
          ..event(21, 0, 0, '오랜 통상 화약', x1: px(900), bits: 2 | Tile.bar | Tile.eventClipLeft | Tile.eventClipRight, look: freeLane, rail: minutePrec, band: 1)
          ..event(22, 0, 0, '주권 반환 협정', x1: px(900), bits: 2 | Tile.bar | Tile.eventClipLeft | Tile.eventClipRight, look: freeLane, rail: minutePrec, band: 1))
        .build();
    final scene = TimelineScene(
      controller: controller,
      layout: SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 2}],
        'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]}],
        'epochs': [],
      }),
      fetchTile: (level, x, chunk, packs) async =>
          level == 9 && chunk == 0 && x == 1 ? first : (level == 9 && chunk == 0 && x == 2 ? second : TileBuilder(level: level, x: x, chunk: chunk).build()),
      labelCompute: (input) async => placeLabels(input),
    );
    addTearDown(scene.dispose);
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    await settle(scene, painter);
    final v = controller.view, edge = v.xOf(o2);
    expect(scene.draw.map((d) => d.key.x).toSet(), containsAll([1, 2]), reason: '두 타일이 다 그려진다');
    final input = scene.labelBatch!.input;
    expect([for (int i = 0; i < input.at.length; i++) input.eventId[i]]..sort(), [21, 22], reason: '후보는 사건마다 하나(시작 조각) — 이어진 조각은 후보가 아니다');
    for (final id in [21, 22]) {
      final dots = painter.debugDots.where((d) => d.eventId == id).toList();
      expect(dots.length, 1, reason: '$id: 점은 하나');
      expect(dots.single.at.dx, lessThan(edge - 250), reason: '$id: 점은 띠 안의 시작 자리 — 타일 경계($edge)의 바탕이 아니다');
    }
    final out = scene.labelOutput!;
    for (int i = 0; i < out.clusters; i++) {
      expect(v.xOf(out.clusterAt[i]), lessThan(edge - 250), reason: '개수 알약도 타일 경계에 서지 않는다');
    }
    expect(painter.debugLabels.where((l) => l.kind == 'event' && l.at.dx > edge - 20), isEmpty, reason: '경계 뒤에 이름이 다시 서지 않는다');
  });

  // 리메이크 2부 · 두 장 꼬리표(감독 결정 '두 장 ㄴ'): 새 저장소의 줄(`rows.fig_wide` 비트 19)은 이름 색줄 G.head 14 → 칸 뭉치(층마다 14) →
  // 흰 사건 칸(G.evLine 18 × 글줄). 사건은 그 흰 칸의 가운데에 서고, 칸 층을 갖지 않은 띠는 사건 칸을 제 색줄 바로 밑으로 올린다
  // (BandLayer.eventLiftOf — 그리기 · 누름이 같은 값). 이름은 색줄에 · 사건은 사건 칸에 있어 사건이 머리 이름을 비켜 가지 않는다.
  test('두 장 꼬리표: 사건은 몸통의 흰 사건 칸 가운데 — 칸 없는 띠는 올리고, 머리 이름을 비켜 가지 않는다', () async {
    final controller = TimelineController()
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(284);
    final origin = tileOrigin(9, 1).toDouble();
    controller.showRange(origin, origin + (1920 - SceneView.gutter) / ppm);
    // 띠 look 비트 20(그 띠에 칸이 있다) · 26(지도자 층 — 비트 21 + 5). 둘째 띠는 칸이 없다.
    const leaderCells = 1 << 20 | 1 << 26;
    final bytes = (TileBuilder(level: 9, x: 1, chunk: 0)
          ..band(1, 0, 0, px(800), '별여울국', look: leaderCells)
          ..band(2, 0, px(900), px(1700), '해솔국')
          ..event(21, 0, px(300), '별여울의 일', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1)
          // 둘째 띠의 머리 이름(띠 시작 + 구멍 7 + 7)이 선 바로 그 자리.
          ..event(22, 0, px(930), '해솔의 첫 일', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 2))
        .build();
    final scene = TimelineScene(
      controller: controller,
      layout: SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 2}],
        // 줄 값 `fig_wide`: 비트 3(막대 단 + 1 — 줄 값이 실린 저장소) · 17(그 줄에 지도자 칸) · 19(줄마다의 칸 값 — 두 장 꼬리표의 몸통).
        'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [{...row(0), 'kind': 0, 'fig_wide': 1 << 3 | 1 << 17 | 1 << 19}]}],
        'epochs': [],
      }),
      fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      labelCompute: (input) async => placeLabels(input),
    );
    addTearDown(scene.dispose);
    final painter = TimelinePainter(scene)..debug = true;
    await settle(scene, painter);
    final layout = scene.layout, geo = layout.geo(0), top = layout.rowTop(0);
    // 몸통 = 색줄 14 밑 · 지도자 층 14 → 흰 사건 칸(자동 밀도라 글줄 하나 · 18).
    expect(geo.bodyTop, geo.bandTop + G.head);
    expect(geo.floorEnd, geo.bodyTop + G.floor);
    expect((geo.textTop, geo.lineH, geo.textLines), (geo.floorEnd, G.evLine, 1));
    final dots = {for (final d in painter.debugDots) d.eventId: d.at};
    expect(dots.keys.toSet(), {21, 22});
    expect(BandLayer.of(scene)!.eventLiftOf(layout, 0, 1), 0, reason: '지도자 층을 가진 띠는 그대로');
    expect(BandLayer.of(scene)!.eventLiftOf(layout, 0, 2), G.floor, reason: '칸이 없는 띠는 남의 층(지도자 14)만큼 올린다');
    expect(dots[21]!.dy, closeTo(bodyY(scene, top + geo.textTop + G.evLine / 2), .01), reason: '사건 칸은 지도자 층 바로 밑');
    expect(dots[22]!.dy, closeTo(bodyY(scene, top + geo.bodyTop + G.evLine / 2), .01), reason: '칸 없는 띠: 사건 칸이 색줄 바로 밑');
    // 머리 이름과 다른 줄이라 점은 제 시각 그대로이고 이름도 숨지 않는다(예전: 첫 글줄의 비킬 구간 · 머리 이름 아래 점 숨김).
    expect(dots[22]!.dx, closeTo(SceneView.gutter + 930, 3));
    expect(painter.debugLabels.where((l) => l.kind == 'event').map((l) => l.text).toSet(), {'별여울의 일', '해솔의 첫 일'});
    // 누름도 그린 자리에서 — 올린 몫을 같은 셈으로 뺀다.
    for (final id in [21, 22]) {
      expect(hitTest(scene, dots[id]!.dx, dots[id]!.dy).eventId, id);
    }
    expect(hitTest(scene, dots[22]!.dx, dots[22]!.dy + G.floor).eventId, isNot(22), reason: '올리기 전의 자리에서는 잡히지 않는다');
  });

  test('선택 판정은 그린 것과 같은 목록에서 한다: 점 · 이름 · 알약 · 막대 · 빈 곳', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final dot = painter.debugDots.firstWhere((d) => d.eventId == 13);
    expect(hitTest(scene, dot.at.dx, dot.at.dy), isA<Hit>().having((h) => (h.kind, h.eventId), '점', (HitKind.event, 13)));
    final name = painter.debugLabels.firstWhere((l) => l.kind == 'event' && l.text == '해솔의 나루 열기');
    expect(hitTest(scene, name.at.dx + 20, name.at.dy + 6).eventId, 13);
    final out = scene.labelOutput!;
    final pillX = scene.controller.view.xOf(out.clusterAt[0]);
    final pillY = lineCenter(scene.controller.view, scene.layout, out.clusterRow[0], out.clusterLine[0]);
    final onPill = hitTest(scene, pillX, pillY);
    expect(onPill.kind, HitKind.pill);
    expect(onPill.row, 0);
    expect((onPill.lo, onPill.hi), (tileOrigin(9, 1) + px(1200), tileOrigin(9, 1) + px(1232)), reason: '알약을 누르면 그 통의 범위로 목록을 연다');
    expect(onPill.count, 12, reason: '알약에 적힌 수를 함께 실어 준다 — 묶음 카드의 머리글이 목록을 받기 전에도 수를 적는다');
    expect(hitTest(scene, dot.at.dx, dot.at.dy).count, 0, reason: '알약이 아니면 0');
    expect(hitTest(scene, SceneView.gutter + 400, bodyY(scene, 142 + 108 + railOffset)).eventId, 15, reason: '막대 위');
    // 사건 · 막대가 없는 띠 안은 이제 띠로 잡힌다(겹침 차례의 맨 아래).
    final onBand = hitTest(scene, SceneView.gutter + 1200, bodyY(scene, 120));
    expect((onBand.kind, onBand.bandId, onBand.row), (HitKind.band, 1, 0));
    expect(hitTest(scene, SceneView.gutter + 1200, bodyY(scene, 160)).kind, HitKind.none, reason: '띠 밖의 빈 곳');
    expect(hitTest(scene, 50, 300).kind, HitKind.none, reason: '줄 이름 칸');
  });

  test('선택 판정은 다른 층의 맞히기 함수를 겹침 차례대로 부른다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final asked = <String>[];
    // 층마다 제 갈래에 함수를 걸어 둔다 — 그 층의 파일을 불러오지 않는다.
    List<HitProbe> one(String name, HitKind kind, {bool hit = false}) => [
      (double x, double y) {
        asked.add(name);
        return hit ? Hit(kind, itemId: 7) : null;
      },
    ];
    final dot = painter.debugDots.firstWhere((d) => d.eventId == 13);
    // 표식 · 단추가 맞으면 사건보다 먼저 이긴다.
    final marked = hitTest(scene, dot.at.dx, dot.at.dy,
        sources: HitSources(marks: one('표식', HitKind.square, hit: true), bands: one('띠', HitKind.band)));
    expect((marked.kind, marked.itemId), (HitKind.square, 7));
    expect(asked, ['표식']);
    // 맞지 않으면 사건 → 막대 → 인물 → 이름표 → 칸 → 띠 차례로 내려간다.
    asked.clear();
    final none = hitTest(scene, SceneView.gutter + 1200, bodyY(scene, 160),
        sources: HitSources(
          marks: one('표식', HitKind.square),
          rails: one('막대', HitKind.event),
          figures: one('인물', HitKind.figure),
          hangs: one('이름표', HitKind.hang),
          cells: one('칸', HitKind.cell),
          bands: one('띠', HitKind.band),
        ));
    expect(none.kind, HitKind.none);
    expect(asked, ['표식', '막대', '인물', '이름표', '칸', '띠']);
  });

  test('돋보기를 켜도 같은 항목이 잡힌다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final c = scene.controller..reduceMotion = true;
    c.magnifyTo(1.5, const Offset(900, 500));
    await settle(scene, painter);
    final dot = painter.debugDots.firstWhere((d) => d.eventId == 13);
    // 화면 px → 배치 px은 보기가 바꾼다. 그린 자리(배치 px)에 1.5를 곱한 화면 자리를 누른 셈.
    final screen = Offset(dot.at.dx * 1.5, dot.at.dy * 1.5);
    final layout = c.view.layoutOf((screen.dx, screen.dy));
    expect(hitTest(scene, layout.$1, layout.$2).eventId, 13);
  });

  test('고른 사건에는 강조 고리가 그려진다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    expect(painter.debugSelectionAt, isNull);
    scene.selectedEventId = 13;
    paint(painter);
    final dot = painter.debugDots.firstWhere((d) => d.eventId == 13);
    expect(painter.debugSelectionAt, dot.at);
  });

  test('관점(lens)이 준 이름이 있으면 그 글로 적고 그 폭으로 자리를 잡는다', () async {
    // 관점은 자료에 닿지 않는다(대조표 기능-10) — 같은 타일 · 같은 후보인데 화면에 적는 글만 갈린다.
    final (scene, painter) = make();
    LensTitles.of(scene).put(events: {13: '해솔이 부르는 나루 열기 — 아주 긴 다른 이름'});
    await settle(scene, painter);
    final names = painter.debugLabels.where((l) => l.kind == 'event').map((l) => l.text).toSet();
    expect(names, contains('해솔이 부르는 나루 열기 — 아주 긴 다른 이름'));
    expect(names, isNot(contains('해솔의 나루 열기')), reason: '자료의 이름 대신 관점의 이름');
    expect(names, contains('별여울의 첫 기록'), reason: '관점이 이름을 주지 않은 사건은 그대로');
    // 폭도 그 글로 잰다 — 이름 줄의 오른쪽 끝이 긴 이름만큼 늘어난다.
    final batch = scene.labelBatch!, out = scene.labelOutput!;
    final at = [for (int i = 0; i < out.shownCount; i++) if (batch.input.eventId[out.shownCandidate[i]] == 13) i].single;
    final cand = out.shownCandidate[at];
    final plain = EventText.widthOf('해솔의 나루 열기', EventFont.name(batch.sizeOf(cand), batch.input.importance[cand], batch.input.look[cand]));
    expect(batch.input.nameWidth[cand], greaterThan(plain), reason: '자리 셈이 쓰는 폭도 관점의 글로 잰 것');
  });

  test('이름 자리는 배율이 4% 넘게 바뀌거나 새 타일이 올 때만 다시 계산한다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final before = scene.labelWorker.requested;
    // 옆으로 조금 움직이기만 하면 다시 계산하지 않는다(자리는 분에 매여 있다).
    scene.controller.showRange(scene.controller.view.lo + px(50), scene.controller.view.hi + px(50));
    await settle(scene, painter);
    expect(scene.labelWorker.requested, before);
    final c = scene.controller..reduceMotion = true;
    c.wheel(const Offset(900, 500), -30); // 5.5% 확대
    await settle(scene, painter);
    expect(scene.labelWorker.requested, greaterThan(before));
  });

  test('확대해서 후보를 다시 모아도 같은 타일의 이름은 다시 풀지도 재지도 않는다', () async {
    // 1,000만 건에서는 타일마다 대표가 꽉 차서, 배율이 4% 바뀔 때마다 수천 개의 제목을 다시 풀고 재느라
    // 확대 중의 만들기 시간이 자료 크기와 함께 늘었다(p99 1.0 → 1.9 → 2.7ms).
    final (scene, painter) = make();
    await settle(scene, painter);
    final inner = EventText.measure!;
    final measured = <String>[];
    // 그리는 층이 장면마다 다시 걸지만, 확대 바로 뒤의 후보 모으기는 이 길로 잰다.
    EventText.measure = (title, look) {
      measured.add(title);
      return inner(title, look);
    };
    final before = scene.labelWorker.requested;
    final c = scene.controller..reduceMotion = true;
    c.wheel(const Offset(900, 500), -30); // 5.5% 확대 → 후보를 다시 모은다
    await settle(scene, painter);
    expect(scene.labelWorker.requested, greaterThan(before));
    expect(measured, isEmpty, reason: '이름의 폭은 배율과 무관하다 — 타일에 적어 둔 것을 쓴다');
    final input = scene.labelBatch!.input;
    expect(input.nameWidth.every((w) => w > 0), isTrue);
    expect(input.bandHi.where((hi) => hi.isFinite).length, 3, reason: '사건이 든 띠의 범위도 그대로(첫 줄의 셋은 띠 안, 둘째 줄의 하나는 띠 밖)');
  });

  test('배율만 바뀌면 날짜 글 · 그 폭 · 정밀도 구간도 다시 셈하지 않는다', () async {
    // 확대 · 돋보기 도중에는 배율이 장면마다 바뀌어 후보를 처음부터 다시 모은다. 분 단위의 값(이름 폭 · 날짜 글과 그 폭 ·
    // 정밀도 구간 · 든 띠)은 타일에 걸어 두고 다시 쓴다 — 100만 건에서 한 장면에 후보가 수천 개라 이 되풀이가 컸다.
    final (scene, painter) = make(dates: true);
    await settle(scene, painter);
    expect(scene.labelBatch!.input.yearWidth.where((w) => w > 0), isNotEmpty, reason: '연도 폭을 한 번은 잰다');
    final inner = EventText.measure!;
    final measured = <String>[];
    EventText.measure = (title, look) {
      measured.add(title);
      return inner(title, look);
    };
    final before = scene.labelWorker.requested;
    final c = scene.controller..reduceMotion = true;
    for (int i = 0; i < 6; i++) {
      c.wheel(const Offset(900, 500), -30); // 5.5%씩 확대 → 배율이 바뀔 때마다 후보를 다시 모은다
      await settle(scene, painter);
    }
    expect(scene.labelWorker.requested, greaterThan(before));
    expect(measured, isEmpty, reason: '이름 · 날짜 글의 폭은 배율과 무관하다 — 타일에 걸어 둔 것을 쓴다');
  });

  test('후보가 많은 타일에서 배율이 바뀔 때의 후보 모으기 시간을 잰다', () async {
    // 진단용(값을 단정하지 않고 찍기만 한다). 줄 8 · 사건 1,600개인 타일 하나에서 배율을 4%씩 바꾸며 후보를 다시 모은다 —
    // 확대 · 돋보기 도중에 장면마다 도는 그 일이다.
    const rows = 8, per = 200;
    final origin = tileOrigin(9, 1).toDouble();
    final builder = TileBuilder(level: 9, x: 1, chunk: 0);
    for (int r = 0; r < rows; r++) {
      builder.band(r + 1, r, 0, px(1800), '별여울 갈래 ${r + 1}');
      for (int i = 0; i < per; i++) {
        builder.event(r * per + i + 1, r, px(10 + i * 9.0), '별여울의 기록 ${r * per + i}',
            bits: 1 + (i % 3) | Tile.counted, look: freeLane, rail: minutePrec, label: '${700 + i}년', band: r + 1);
      }
    }
    final bytes = builder.build();
    final controller = TimelineController()
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(142.0 * rows);
    controller.showRange(origin, origin + (1920 - SceneView.gutter) / ppm);
    final scene = TimelineScene(
      controller: controller,
      layout: SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': rows * per}],
        'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [for (int r = 0; r < rows; r++) row(r)]}],
        'epochs': [],
      }),
      fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      labelCompute: (input) async => placeLabels(input),
    );
    addTearDown(scene.dispose);
    final text = AtlasText()
      ..maxNewPerFrame = 8000
      ..budgetMicros = 1 << 40;
    addTearDown(text.dispose);
    final painter = TimelinePainter(scene, text: text);
    for (int i = 0; i < 60; i++) {
      paint(painter);
      await pumpEventQueue();
      scene.tick(7);
    }
    final watch = Stopwatch()..start();
    const frames = 30;
    for (int i = 0; i < frames; i++) {
      final v = controller.view;
      controller.showRange(v.lo, v.lo + v.span * .96); // 4%씩 확대 — 장면마다 후보를 다시 모으는 폭
      scene.prepare();
      LabelBatch.collect(scene, controller.view, 0, rows - 1, 1000 + i);
    }
    watch.stop();
    final n = scene.labelBatch?.input.at.length ?? 0;
    // ignore: avoid_print
    print('후보 모으기: 장면 $frames번 · 한 번 ${(watch.elapsedMicroseconds / frames / 1000).toStringAsFixed(3)}ms · 후보 $n개');
    expect(n, greaterThan(100));
  });

  test('뒤의 작업자가 셈하는 동안에는 후보를 다시 모으지 않는다', () async {
    // 빈 줄 접기의 `maybeAsk`와 같은 길: 답이 오기 전에 모은 판은 그대로 버려지므로, 한 번에 하나만 묻고 답이 온 뒤 최신 보기로 한 번 모은다.
    final done = <void Function()>[];
    final (scene, painter) = make(hold: done);
    // 처음 한 판이 걸릴 때까지 돌린 뒤, 답을 붙잡아 둔 채 배율을 여러 번 바꾼다.
    for (int i = 0; i < 40 && done.isEmpty; i++) {
      paint(painter);
      await pumpEventQueue();
    }
    expect(done, isNotEmpty, reason: '첫 물음이 나갔다');
    final asked = scene.labelWorker.requested;
    final c = scene.controller..reduceMotion = true;
    for (int i = 0; i < 5; i++) {
      c.wheel(const Offset(900, 500), -30);
      paint(painter);
      await pumpEventQueue();
    }
    expect(scene.labelWorker.requested, asked, reason: '앞 판이 도는 동안에는 새로 모으지 않는다');
    // 답이 오면 그때의 보기로 한 번 모은다.
    for (final f in done) {
      f();
    }
    done.clear();
    await pumpEventQueue();
    paint(painter);
    await pumpEventQueue();
    expect(scene.labelWorker.requested, asked + 1);
  });

  test('이름 자리 입력은 Float64List · Int32List라 작업자로 넘길 수 있다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final input = scene.labelBatch!.input;
    expect(input.at, isA<Float64List>());
    expect(input.look, isA<Uint32List>());
    expect(input.at.length, 5, reason: '기간 사건까지 대표 다섯');
    expect(input.pillRest, [37, 12]);
    expect(input.rowLines, [2, 2]);
  });

  test('그림판 방식에서는 새 이름이 in 스프링으로 짙어지고, 빠진 이름은 out 스프링으로 옅어진다', () async {
    double now = 0;
    final (scene, painter) = make(clock: () => now, text: AtlasText()..budgetMicros = 1 << 40);
    await settle(scene, painter);
    List<DebugLabel> names(String kind) => painter.debugLabels.where((l) => l.kind == kind).toList();
    expect(names('event'), isEmpty, reason: '막 들어온 이름은 아직 안 보인다(짙기 0)');
    expect(scene.busy.value, isTrue, reason: '짙어지는 동안 화면의 시계가 돈다');
    now = 100;
    paint(painter);
    final entering = SpringSimulation(Motion.spring(MotionToken.enter), 0, 1, 0);
    expect(names('event').map((l) => l.alpha), everyElement(closeTo(entering.x(.1), 1e-9)));
    now = 400;
    paint(painter);
    scene.tick(7);
    final settled = names('event');
    expect(settled.length, 5);
    expect(settled.map((l) => l.alpha), everyElement(1));
    expect(scene.busy.value, isFalse);

    // 이름이 모두 빠진 판이 왔다고 치면: 제자리에서 out 스프링으로 옅어진다.
    scene.nameFade.accept([], now: 1000);
    now = 1080;
    paint(painter);
    final ghosts = names('ghost');
    expect(ghosts.map((l) => l.text).toSet(), settled.map((l) => l.text).toSet());
    final leaving = SpringSimulation(Motion.spring(MotionToken.exit), 1, 0, 0);
    expect(ghosts.map((l) => l.alpha), everyElement(closeTo(leaving.x(.08), 1e-9)));
    now = 1320;
    paint(painter);
    expect(names('ghost'), isEmpty);
  });

  test('글줄 방식에서는 이름이 옅어짐 없이 바로 드나든다', () async {
    double now = 0;
    final (scene, painter) = make(clock: () => now);
    await settle(scene, painter);
    expect(painter.debugLabels.where((l) => l.kind == 'event').map((l) => l.alpha), [1, 1, 1, 1, 1]);
    scene.nameFade.accept([], now: 0);
    paint(painter);
    expect(painter.debugLabels.where((l) => l.kind == 'ghost'), isEmpty);
  });
}
