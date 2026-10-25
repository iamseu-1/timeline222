import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/hangs.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 띠 밖에 덧붙는 것(속국 이름표 · 세로 끈 · 구역 탭 · 바탕 문화 이름)의 자리와 이음을 순수 로직으로 잰다.
// 값의 근거는 docs/명세-3단계/03-띠에-덧붙는-것.md 3~5절과 기준 덤프(prototype/results/dom/밀집-세부.json)의 실측:
//   · 매달린 탭: 띠 아랫변 밑으로 2px 끼워서 · 한 줄 20 + 틈 3 = 23 · 아래 모서리만 둥금
//   · 구역 탭: 매달린 이름표 줄 뒤에 이어 · 띠 아랫변에서 3px 띄워서 · 높이 20
//   · 바탕 문화 이름 단: 줄 아랫변에서 21px 높이 · 왼쪽에서 13px(테두리 1 + 12)
// 위 23px 줄은 매달린 줄 수가 없는 옛 저장소의 값이다. 새 저장소(리메이크 2부 '두 장 ㄴ')의 실로 매단 작은 꼬리표 · 처음 접힘은 맨 아래 묶음.

const m = 1000000.0; // 백만 분
const level = 9;

Map<String, dynamic> rowSpec(int id, {int zones = 0, int hem = 0, double dep = 0, int? figWide}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 2, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'dep': dep, 'zones': zones, 'hem': hem,
  'fig_wide': ?figWide,
};

/// [half]면 새 저장소: 줄 1의 매달린 이름표 줄 수(3 — 단 0~2, 단 3은 구역 탭)를 `fig_wide` 비트 9~13에 싣는다
/// (비트 3~5 = 기간 막대 단 수 + 1이 있어야 새 저장소로 읽는다 — 내보내기 `export/tracks.mjs`의 packRowValues).
/// 아니면 그 수가 없는 옛 저장소 — 모든 덧단 줄이 23px이다.
SceneLayout makeLayout({bool half = false}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
      'rows': [rowSpec(0, zones: 1, hem: 1), rowSpec(1, zones: 4, dep: 25, figWide: half ? (3 << 3) | (3 << 9) : null)],
    },
  ],
});

/// 줄 0에 작은 상국 띠(2번)와 바탕 문화, 줄 1에 화면을 넘는 상국 띠(1번)와 이름표 · 구역 탭을 실은 타일.
/// 이름표의 `d`는 속국 띠의 번호다(계약 6-4 끝 — 고르기 · 강조가 속국을 짚는다).
Uint8List makeTile({bool half = false}) {
  final t = TileBuilder(level: level, x: 0, chunk: 0)
    ..band(1, 1, 2 * m, 30 * m, '은륜 제국')
    ..band(2, 0, 12 * m, 20 * m, '해솔국')
    ..band(3, 0, 12 * m, 20 * m, '유리항 매듭토기') // 바탕 문화 띠 — 이름 단은 이 띠의 좌우를 따른다
    // 줄 1 · 단 0: 같은 속국(별목)의 이어지는 두 구간 + 안으로 옮기는 세로 끈
    ..item(16, 101, 1, 4 * m, 12 * m, ref: 1, name: '별목 조공국', color: 0xa0bcc5, a: 0, b: 0, d: 21, text2: '속국:별목')
    ..item(16, 102, 1, 12 * m, 18 * m, ref: 1, name: '별목 조공국', color: 0xa0bcc5, a: 0, b: 1, c: 4 | 64, d: 21, text2: '속국:별목')
    ..item(16, 103, 1, 18 * m, 22 * m, ref: 1, color: 0xa0bcc5, a: 0, b: 4, c: 8, d: 1, text2: '속국:별목')
    // 줄 1 · 단 0의 연대 폭(구역 44): 둘째 조각의 끝 쪽만 무늬가 깔리고 그 오른쪽 테두리가 점선이 된다
    ..item(44, 104, 1, 16 * m, 24 * m, ref: 1, color: 0xa0bcc5, a: 0, b: 0, c: 1, d: 21, text2: '속국:별목')
    // 줄 1 · 단 1: 서로 다른 속국이 맞닿는다 — 이어 붙지 않으므로 0.5px씩 물러난다
    ..item(16, 111, 1, 6 * m, 12 * m, ref: 1, name: '흰계단 봉국', color: 0xbba395, a: 1, b: 1, d: 22, text2: '속국:흰계단')
    ..item(16, 112, 1, 12 * m, 22 * m, ref: 1, name: '거울관 왕국', color: 0x9dbea8, a: 1, b: 2, d: 23, text2: '속국:거울관')
    // 거울관 왕국의 이설이 말하는 끝(구역 45) — 그 조각 안의 유령 구분선 하나
    ..item(45, 113, 1, 20 * m, 22 * m, ref: 1, color: 0x9dbea8, a: 1, b: 1, d: 23, text2: '속국:거울관')
    // 줄 1 · 단 2: 2px보다 좁아 그리지 않는 칸
    ..item(16, 121, 1, 15 * m, 15.001 * m, ref: 1, name: '잔닻 종속국', color: 0xd7c18e, a: 2, b: 3, d: 24, text2: '속국:잔닻')
    // 줄 1 · 단 3: 구역 탭(매달린 이름표 세 줄 뒤에 이어 센다)
    ..item(17, 131, 1, 8 * m, 26 * m, ref: 1, name: '별목 교환구', color: 0x9dbea8, a: 3, text2: '구역:별목')
    // 줄 0: 띠 안쪽 10px에 갇히는 이름표
    ..item(16, 141, 0, 11 * m, 21 * m, ref: 2, name: '뜬닻 조공항', color: 0xa4b1b7, a: 0, d: 25, text2: '속국:뜬닻')
    // 줄 0: 바탕 문화의 아래 이름 단
    ..item(18, 151, 0, 12 * m, 20 * m, ref: 3, name: '유리항 매듭토기', color: 0xa0bcc5, c: 1, text2: '문화');
  // 새 저장소: 상국 띠(1번)의 속국 접기 단추(구역 48 · a = 매달린 속국 수)
  if (half) t.item(48, 161, 1, 2 * m, 30 * m, ref: 1, color: 0xa0bcc5, a: 3);
  return t.build();
}

(TimelineScene, TimelinePainter) make({bool half = false}) {
  final layout = makeLayout(half: half);
  final bytes = makeTile(half: half);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(layout.totalHeight);
  // 통 하나가 32px이 되게 — 단계 9가 잡히고 타일 0(0 ~ 67.1백만 분) 안에 화면이 든다.
  final span = (1920 - SceneView.gutter) / (32 / bucketMinutes(level));
  controller.showRange(10 * m, 10 * m + span);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (l, x, chunk, packs) async =>
        l == level && x == 0 && chunk == 0 ? bytes : TileBuilder(level: l, x: x, chunk: chunk).build(),
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  // 글줄 보관이 찰 때까지 몇 장면 — 이름 맞춤은 실제 글자 폭으로 재기 때문이다.
  for (int i = 0; i < 5; i++) {
    paint(painter);
  }
}

List<HangMark> marksOf(TimelinePainter painter, String kind) =>
    [for (final v in painter.debugSink.notes['hang'] ?? const <Object>[]) v as HangMark]..retainWhere((t) => t.kind == kind);

void main() {
  test('매달린 이름표는 띠 아랫변 밑으로 2px 끼워 한 줄 23px씩 쌓인다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final geo = scene.layout.geo(1);
    final hangs = marksOf(painter, 'hang').where((t) => t.row == 1).toList();
    expect(hangs.map((t) => t.lane).toSet(), {0, 1}, reason: '2px보다 좁은 단 2의 칸은 그리지 않는다');
    for (final tab in hangs) {
      expect(tab.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + geo.zoneLaneTop(tab.lane) - 2), 1e-6));
      expect(tab.rect.height, G.zoneTab + G.zoneGap);
    }
    // 단 사이는 23px(G.zoneTab 20 + G.zoneGap 3)
    final lane0 = hangs.firstWhere((t) => t.lane == 0), lane1 = hangs.firstWhere((t) => t.lane == 1);
    expect(lane1.rect.top - lane0.rect.top, closeTo(G.zoneTab + G.zoneGap, 1e-6));
  });

  test('같은 속국의 이어지는 두 구간은 틈 없이 하나의 긴 칸이 되고 이름은 첫 칸에만 적는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final lane0 = marksOf(painter, 'hang').where((t) => t.row == 1 && t.lane == 0).toList()..sort((p, q) => p.rect.left.compareTo(q.rect.left));
    expect(lane0.length, 2);
    expect(lane0[0].joinRight, isTrue);
    expect(lane0[1].joinLeft, isTrue);
    // 맞닿은 쪽에는 0.5px 틈이 없다
    expect(lane0[1].rect.left, closeTo(lane0[0].rect.right, 1e-6));
    expect(lane0[0].rect.right, closeTo(v.xOf(12 * m), 1e-6));
    final names = painter.debugLabels.where((l) => l.kind == 'hang').map((l) => l.text).toList();
    expect(names.where((t) => t == '별목 조공국').length, 1, reason: '이어 붙은 칸에는 이름을 적지 않는다');
  });

  test('이어 붙지 않는 이웃 칸은 0.5px씩 물러나 가는 틈을 남긴다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final lane1 = marksOf(painter, 'hang').where((t) => t.row == 1 && t.lane == 1).toList()..sort((p, q) => p.rect.left.compareTo(q.rect.left));
    expect(lane1.length, 2);
    expect(lane1[0].joinRight, isFalse);
    expect(lane1[1].joinLeft, isFalse);
    expect(lane1[0].rect.right, closeTo(v.xOf(12 * m) - .5, 1e-6));
    expect(lane1[1].rect.left, closeTo(v.xOf(12 * m) + .5, 1e-6));
  });

  test('이름표는 상국 띠 안쪽 10px에 갇힌다 — 띠가 화면을 넘으면 화면 가장자리까지', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    // 줄 0: 띠(2번)가 화면 안에 다 보이므로 양 끝에서 10px 들어온다
    final inner = marksOf(painter, 'hang').firstWhere((t) => t.row == 0);
    expect(inner.rect.left, closeTo(v.xOf(12 * m) + 10, 1e-6));
    expect(inner.rect.right, closeTo(v.xOf(20 * m) - 10, 1e-6));
    expect(inner.openLeft, isFalse);
    // 줄 1: 띠(1번)가 화면 밖으로 이어지므로 화면 가장자리(−1 · W+1)까지
    final wide = marksOf(painter, 'hang').firstWhere((t) => t.row == 1 && t.lane == 0);
    expect(wide.rect.left, closeTo(v.left - 1, 1e-6));
    expect(wide.openLeft, isTrue);
  });

  test('구역 탭은 매달린 이름표 줄 뒤에 이어, 띠 아랫변에서 3px 띄우고 높이 20으로 온다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final geo = scene.layout.geo(1);
    final zone = marksOf(painter, 'zone').single;
    expect(zone.lane, 3);
    expect(zone.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + geo.zoneLaneTop(3) + G.zoneGap), 1e-6));
    expect(zone.rect.height, G.zoneTab);
    // 가로도 얹히는 띠 안쪽 10px에 가둔다(양쪽이 화면 밖이면 화면까지)
    expect(zone.rect.left, closeTo(v.left, 1e-6));
    expect(zone.rect.right, closeTo(1920, 1e-6));
  });

  test('바탕 문화의 이름 단은 줄 아랫변의 21px 자리에, 띠 왼쪽에서 13px 들어와 적는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final geo = scene.layout.geo(0);
    expect(geo.hemTop, greaterThan(0));
    final hem = marksOf(painter, 'hem').single;
    expect(hem.rect.top, closeTo(v.yOf(scene.layout.rowTop(0) + geo.hemTop - 1), 1e-6));
    expect(hem.rect.left, closeTo(v.xOf(12 * m) + 13, 1e-6));
    final texts = painter.debugLabels.where((l) => l.kind == 'hem').map((l) => l.text).toList();
    expect(texts, containsAll(<String>['유리항 매듭토기', '문화']));
  });

  test('밖에서 안으로 옮긴 속국에는 매달린 탭과 품은 칸을 잇는 세로 끈 하나', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final geo = scene.layout.geo(1);
    final link = marksOf(painter, 'link').single;
    expect(link.rect.width, closeTo(1.5, 1e-6));
    expect(link.rect.left, closeTo(v.xOf(18 * m) - .75, 1e-6));
    // 품은 칸은 0번 줄이 띠 아랫변에 가장 가깝다: 두 줄이면 0번 줄의 윗변이 예속 자리에서 16px(흰 층 한 단 — 틈 없음) 아래
    final top = scene.layout.rowTop(1);
    final yIn = geo.depTop + G.depPitch + G.dep / 2, yOut = geo.zoneLaneTop(0) + 6;
    expect(link.rect.top, closeTo(v.yOf(top + yIn), 1e-6));
    expect(link.rect.height, closeTo(yOut - yIn, 1e-6));
  });

  test('모호한 연대(구역 44)는 그 구간에만 무늬를 깔고 걸친 경계를 점선으로 바꾼다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final lane0 = marksOf(painter, 'hang').where((t) => t.row == 1 && t.lane == 0).toList()..sort((p, q) => p.rect.left.compareTo(q.rect.left));
    expect(lane0[0].zones, 0, reason: '연대 폭이 닿지 않는 앞 조각에는 무늬가 없다');
    expect(lane0[0].dotted, '');
    expect(lane0[1].zones, 1, reason: '뒤 조각의 끝 쪽만 무늬 한 조각');
    expect(lane0[1].dotted, 'r', reason: '연대 폭이 오른쪽 끝을 품으므로 그쪽 테두리가 점선');
  });

  test('이설이 말하는 경계(구역 45)에는 조각 높이만 한 1px 유령 구분선을 긋는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final geo = scene.layout.geo(1);
    final alt = marksOf(painter, 'alt').single;
    expect(alt.lane, 1);
    expect(alt.rect.left, closeTo(v.xOf(20 * m), 1e-6));
    expect(alt.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + geo.zoneLaneTop(1) - 2) + 2, 1e-6));
    expect(alt.rect.height, G.zoneTab + G.zoneGap - 2 * HangLook.ghostInset);
  });

  // '이설' 체크를 끄면 지금 연표는 `alt: this.showAlt && !this._bird`(js:6181)로 `altRowPlan`의 `lines` · `shift`를
  // 비운다 — 유령 구분선이 사라지고 그 선을 비켜 가던 이름표도 제자리다. 구역 44의 모호한 연대 무늬는 그대로다.
  test('이설 표시를 끄면 유령 구분선이 사라지고 모호한 연대 무늬는 남는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    SceneMarks.of(scene).showAlt = false;
    await settle(scene, painter);
    expect(marksOf(painter, 'alt'), isEmpty);
    final lane0 = marksOf(painter, 'hang').where((t) => t.row == 1 && t.lane == 0).toList()..sort((p, q) => p.rect.left.compareTo(q.rect.left));
    expect(lane0[1].zones, 1, reason: '무늬는 이설 체크와 상관없다');
    expect(lane0[1].dotted, 'r');
  });

  // 기간 조명의 흐름(명세 06의 3-3): 구간의 밝기는 `이름표의 밝기 + (조명 밝기 − 이름표의 밝기) × glow`다.
  // 이름표는 줄 직속이라 다른 띠를 고른 동안 .5다(C:1724) — 구간만 1로 켜지므로 .5 → .75 → 1로 흐른다.
  test('조명의 흐름 — 구간 안의 이름표 글자가 진행(glow)만큼 밝아진다', () async {
    Future<double> litAt(double glow) async {
      final (scene, painter) = make();
      addTearDown(scene.dispose);
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(em.Look(band: 2, lit: true, spots: [em.Spot(1, 0, 40 * m, glow: glow)]));
      await settle(scene, painter);
      return painter.debugLabels.firstWhere((l) => l.kind == 'hang' && l.text == '거울관 왕국').alpha;
    }

    expect(await litAt(0), closeTo(.5, 1e-9), reason: '아직 켜지지 않은 구간은 이름표의 흐림 그대로');
    expect(await litAt(.5), closeTo(.75, 1e-9), reason: '.5 + (1 − .5) × .5');
    expect(await litAt(1), closeTo(1, 1e-9), reason: '다 켜지면 흐리지 않다');
  });

  // 명세 06의 3-3 '물러남': 창을 닫아 조명을 거두면 구간이 160ms에 옅어진다(css:1747 `.lit-out`).
  // 거두는 순간 `lit`도 함께 꺼지므로, 층이 `lit`만 보고 구간을 버리면 이 160ms가 한 장면에 튄다.
  // 흐르는 조명을 손으로 돌린다 — 밝기 상태가 가라앉아 있는 동안 그리개의 시계는 멎어 있어 실시간이 끼어들지 않는다.
  test('조명을 거두면 이름표의 구간도 160ms에 옅어진다 — 한 장면에 튀지 않는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    scene.controller.reduceMotion = false;
    await settle(scene, painter);
    double litAlpha() => painter.debugLabels.firstWhere((l) => l.kind == 'hang' && l.text == '거울관 왕국').alpha;

    final e = em.Emphasis.of(scene)..reduceMotion = false;
    e.set(em.Look(band: 2, lit: true, spots: const [em.Spot(1, 0, 40 * m)]));
    for (int i = 0; i < 6; i++) {
      e.tick(50); // 200ms을 넘겨 다 켠다
    }
    paint(painter);
    expect(litAlpha(), closeTo(1, 1e-9), reason: '다 켜졌다');

    e.set(const em.Look(band: 2)); // 창을 닫아 조명을 거둔다
    e.tick(20); // 160ms의 1/8 — 이 굽이(Cubic(.32,.72,0,1))는 앞이 가팔라 절반이면 이미 거의 꺼진다
    paint(painter);
    final at = litAlpha();
    expect(at, greaterThan(.62), reason: '아직 조명이 남아 있다 — 이름표의 밝기(.5)로 주저앉지 않는다');
    expect(at, lessThan(.98), reason: '이미 옅어지기 시작했다');

    for (int i = 0; i < 5; i++) {
      e.tick(50); // 160ms을 넘긴다
    }
    paint(painter);
    expect(litAlpha(), closeTo(.5, 1e-9), reason: '다 가라앉으면 보통 흐림으로');
  });

  test('조명이 꺼진 채 새로 온 구간은 이름표를 밝히지 않는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    scene.controller.reduceMotion = false;
    await settle(scene, painter);
    final e = em.Emphasis.of(scene)..reduceMotion = false;
    e.set(const em.Look(band: 2));
    for (int i = 0; i < 8; i++) {
      e.tick(50); // 임계 감쇠의 꼬리까지 흐림이 가라앉기를 기다린다
    }
    // `lit`이 거짓인데 구간만 온 것은 조명이 아니다 — 거두는 중인 구간과 갈라야 한다.
    e.set(em.Look(band: 2, spots: const [em.Spot(1, 0, 40 * m)]));
    e.tick(20);
    paint(painter);
    expect(painter.debugLabels.firstWhere((l) => l.kind == 'hang' && l.text == '거울관 왕국').alpha, closeTo(.5, 1e-9));
  });

  // 이름표 · 구역 탭은 상국 띠의 자식이 아니라 줄(`.tl-lane`) 직속이다 — 띠의 흐림(.58)이 아니라 제 값 .5를 쓴다(C:717 · C:1724).
  test('고른 띠가 있으면 이름표 · 구역 탭은 .5로 흐려지고, 고른 것이 그 속국이면 1로 남는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    // 밝기 상태는 그리개가 장면에 걸어 준다(painter.dart의 Emphasis.of) — 검사도 같은 것을 채운다.
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(band: 21)); // 21 = 속국 '별목'의 띠 번호(이름표의 d)
    await settle(scene, painter);
    final hangs = marksOf(painter, 'hang').where((t) => t.row == 1).toList();
    for (final tab in hangs.where((t) => t.lane == 0)) {
      expect(tab.alpha, closeTo(1, 1e-9), reason: '고른 속국의 이름표는 흐려지지 않는다');
    }
    for (final tab in hangs.where((t) => t.lane == 1)) {
      expect(tab.alpha, closeTo(.5, 1e-9), reason: '다른 속국의 이름표는 .5(띠의 .58이 아니다)');
    }
    expect(marksOf(painter, 'zone').single.alpha, closeTo(.5, 1e-9), reason: '구역 탭도 `.tl-org`이라 .5');
  });

  test('강조(흐림)에 든 속국의 이름표만 밝게 남고 나머지는 .25로 흐려진다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(bands: {22}));
    await settle(scene, painter);
    final hangs = marksOf(painter, 'hang').where((t) => t.row == 1).toList();
    final hit = hangs.firstWhere((t) => t.name == '흰계단 봉국');
    expect(hit.alpha, closeTo(1, 1e-9));
    expect(hangs.firstWhere((t) => t.name == '거울관 왕국').alpha, closeTo(.25, 1e-9), reason: 'C:1725 — 이름표의 강조 밖은 .25(띠의 .2가 아니다)');
  });

  test('조감(밀도 2)에서는 이름표 · 세로 끈 · 구역 탭 · 바탕 문화 이름 단이 모두 빠진다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
    await settle(scene, painter);
    expect(painter.debugSink.notes['hang'] ?? const <Object>[], isEmpty);
    expect(painter.hangs.hitHangs(500, 900), isNull);
  });

  test('소속을 펼친 상위 띠의 이름표와 끈은 그리지 않는다 — 구역 탭은 그대로', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    painter.hangs.expanded.add(1);
    await settle(scene, painter);
    expect(marksOf(painter, 'hang').where((t) => t.row == 1), isEmpty);
    expect(marksOf(painter, 'link'), isEmpty);
    expect(marksOf(painter, 'zone').length, 1);
    expect(marksOf(painter, 'hang').where((t) => t.row == 0).length, 1, reason: '펼치지 않은 띠(2번)의 이름표는 그대로');
  });

  test('맞히기: 이름표를 누르면 그 속국, 구역 탭 · 바탕 문화 이름을 누르면 그 항목', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final hang = marksOf(painter, 'hang').firstWhere((t) => t.name == '거울관 왕국');
    final at = painter.hangs.hitHangs(hang.rect.center.dx, hang.rect.center.dy);
    expect(at?.kind, 'hang');
    expect(at?.band, 23, reason: '속국 띠의 번호(이름표의 d)를 돌려준다');
    expect(at?.host, 1);
    expect(at?.row, 1);
    expect(at?.uid, '속국:거울관');
    final zone = marksOf(painter, 'zone').single;
    expect(painter.hangs.hitHangs(zone.rect.center.dx, zone.rect.center.dy)?.kind, 'zone');
    final hem = marksOf(painter, 'hem').single;
    expect(painter.hangs.hitHangs(hem.rect.center.dx, hem.rect.center.dy)?.uid, '문화');
    final hostBandTop = scene.controller.view.yOf(scene.layout.rowTop(hang.row) + scene.layout.geo(hang.row).bandTop);
    expect(painter.hangs.hitHangs(hang.rect.center.dx, hostBandTop + 1), isNull, reason: '해당 상국 띠의 윗부분은 이 층의 몫이 아니다');
  });

  test('이름표 · 구역 탭은 항목마다 그리지 않고 네모 · 조각 묶음에 모인다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    // 그린 것(이름표 5 + 구역 탭 1 + 세로 끈 1)은 모두 네모 · 조각 묶음으로 나간다 — 항목마다 캔버스를 부르지 않는다.
    expect(marksOf(painter, 'hang').length + marksOf(painter, 'zone').length + marksOf(painter, 'link').length, 7);
    expect(painter.hangs.sprites.count, 0, reason: '층이 끝나면 조각 묶음은 비워져 있다(flush)');
  });

  // 건의 8(2026-10-14 '원래대로 두고 크기만 줄이자')에서 리메이크 2부(감독 결정 '두 장 ㄴ' · 2026-10-15 · 계약 3절 머리 상자)로:
  // 매달린 속국 이름표는 **실로 매단 작은 꼬리표**다 — 상국 몸통 아랫변 아래 5에 높이 13 · 꼬리표 사이 4 · 마지막 아래 2(`G.hangDepthOf`) ·
  // 구멍(왼쪽 + 6) · 이름 8.5 굵게(왼쪽 + 12). 구역 탭은 그 뒤 23px 줄 그대로. **처음에는 접혀 있고**(`ViewState.openHangs`)
  // 꼬리표 윗변의 플래그 창 '속국'으로 편다(머리 줄의 '▾ 속국 n' 단추는 조감에만 남는다).
  group('실로 매단 작은 꼬리표 · 접기(새 저장소)', () {
    /// 새 저장소 장면을 줄 1의 매단 꼬리표를 편 채로 세운다.
    Future<(TimelineScene, TimelinePainter)> opened() async {
      final (scene, painter) = make(half: true);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(1, true)), isTrue);
      await settle(scene, painter);
      return (scene, painter);
    }

    test('편 꼬리표는 몸통 아랫변 아래 5에서 높이 13 · 사이 4로 쌓이고 구역 탭은 그 아래(+ 2) 23px 줄에 온다', () async {
      final (scene, painter) = await opened();
      final v = scene.controller.view;
      final geo = scene.layout.geo(1);
      expect(geo.hangLanes, 3);
      expect(geo.hangOpen, isTrue);
      expect(geo.hangHeight, G.hang);
      final bandBottom = geo.bandTop + geo.bandHeight;
      // 덧단: 매단 3줄(5 + 3 × 13 + 2 × 4 + 2 = 54) + 구역 탭 1줄 × 23 + 3
      expect(G.hangDepthOf(3), 54);
      expect(geo.height - bandBottom, G.hangDepthOf(3) + (G.zoneTab + G.zoneGap) + 3);
      final hangs = marksOf(painter, 'hang').where((t) => t.row == 1).toList();
      expect(hangs.map((t) => t.lane).toSet(), {0, 1}, reason: '2px보다 좁은 단 2의 칸은 그리지 않는다');
      for (final tab in hangs) {
        // 띠 밑에 끼우지 않는다(예전 2px) — 몸통 아래 5에서 꼬리표 하나씩 13 + 4.
        expect(tab.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + bandBottom + G.hangGap + tab.lane * (G.hang + G.hangBetween)), 1e-6));
        expect(tab.rect.height, G.hang);
      }
      final zone = marksOf(painter, 'zone').single;
      expect(zone.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + bandBottom + G.hangDepthOf(3) + G.zoneGap), 1e-6));
      expect(zone.rect.height, G.zoneTab, reason: '구역 탭은 줄이지 않는다');
    });

    test('이름은 8.5px 굵게 · 구멍 뒤(왼쪽 + 12)에서 꼬리표 13의 세로 가운데에 — 위아래 테에 닿지 않는다', () async {
      final (scene, painter) = await opened();
      final v = scene.controller.view;
      final geo = scene.layout.geo(1);
      final tab = marksOf(painter, 'hang').firstWhere((t) => t.row == 1 && t.lane == 0 && t.name == '별목 조공국' && !t.joinLeft);
      final label = painter.debugLabels.firstWhere((l) => l.kind == 'hang' && l.text == '별목 조공국');
      final top = v.yOf(scene.layout.rowTop(1) + geo.zoneLaneTop(0));
      expect(label.at.dx, closeTo(tab.rect.left + HangLook.tagTextX, 1e-6));
      // 글줄(8.5 × 1.2 = 10.2)의 가운데가 꼬리표의 세로 가운데 — 위아래 틈 1.4씩(1px 테 안쪽에도 0.4 남음).
      expect(label.at.dy + HangLook.tagSize * .6, closeTo(top + G.hang / 2, 1e-6));
      expect(label.at.dy, greaterThan(top + 1));
      expect(label.at.dy + HangLook.tagSize * 1.2, lessThan(top + G.hang - 1));
    });

    test('세로 끈은 품은 칸에서 매단 꼬리표의 윗변까지 내려간다', () async {
      final (scene, painter) = await opened();
      final v = scene.controller.view;
      final geo = scene.layout.geo(1);
      final link = marksOf(painter, 'link').single;
      final yIn = geo.depTop + G.depPitch + G.dep / 2, yOut = geo.zoneLaneTop(0);
      expect(link.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + yIn), 1e-6));
      expect(link.rect.height, closeTo(yOut - yIn, 1e-6));
    });

    test('처음에는 접혀 있다 — 꼬리표 · 끈 없이 구역 탭이 띠 밑으로 올라오고, 플래그 창의 \'속국 3\'(꺼짐)으로 펴면 매단 몫만큼 줄이 길어진다', () async {
      final (scene, painter) = make(half: true);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final v = scene.controller.view;
      expect(scene.layout.viewState.openHangs, isEmpty, reason: '처음에는 모두 접힘');
      expect(scene.layout.isHangFolded(1), isTrue);
      final folded = scene.layout.geo(1);
      expect(folded.hangOpen, isFalse);
      expect(folded.zoneLaneTop(0), -1, reason: '접은 매단 줄은 자리가 없다');
      expect(marksOf(painter, 'hang').where((t) => t.row == 1), isEmpty);
      expect(marksOf(painter, 'link'), isEmpty, reason: '세로 끈도 접힌다');
      expect(marksOf(painter, 'hang').where((t) => t.row == 0), isNotEmpty, reason: '매단 줄 수가 없는 줄(옛 값)은 그대로');
      final bandBottom = folded.bandTop + folded.bandHeight;
      expect(folded.height - bandBottom, (G.zoneTab + G.zoneGap) + 3, reason: '덧단은 구역 탭 줄뿐');
      expect(marksOf(painter, 'zone').single.rect.top, closeTo(v.yOf(scene.layout.rowTop(1) + bandBottom + G.zoneGap), 1e-6));
      // 머리 줄 단추 대신 상국 꼬리표 윗변의 플래그 하나 — 그 창의 칸 '속국 3'이 이 줄을 펴고 접는다.
      expect(painter.debugLabels.where((l) => l.kind == 'mem'), isEmpty, reason: '조감이 아니면 단추를 그리지 않는다');
      final flag = painter.links.flagOf(1);
      expect(flag, isNotNull);
      expect([for (final e in flag!.entries) (e.kind, e.label, e.count, e.on, e.row)], [(FlagKind.hangs, '속국', 3, false, 1)]);
      final hit = painter.links.hitLinks(flag.rect.center.dx, flag.rect.center.dy);
      expect((hit?.kind, hit?.band), (LinkHitKind.flag, 1));
      // 펴기(플래그 창의 칸이 부르는 것과 같은 보기 상태).
      expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(1, true)), isTrue);
      await settle(scene, painter);
      final open = scene.layout.geo(1);
      expect(open.hangOpen, isTrue);
      expect(open.height - folded.height, G.hangDepthOf(3), reason: '매단 세 줄의 몫(54)만 늘어난다');
      expect(marksOf(painter, 'hang').where((t) => t.row == 1), isNotEmpty);
      expect(marksOf(painter, 'link').length, 1);
      expect(painter.links.flagOf(1)!.entries.single.on, isTrue, reason: '창의 칸이 켜짐으로');
      // 다시 접으면 처음과 같다.
      expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(1, false)), isTrue);
      await settle(scene, painter);
      expect(scene.layout.geo(1).height, folded.height);
      expect(marksOf(painter, 'hang').where((t) => t.row == 1), isEmpty);
    });

    test('옛 저장소(매달린 줄 수가 없음)에는 플래그 칸 · 단추가 없고 덧단은 모두 23px 그대로다', () async {
      final (scene, painter) = make();
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final geo = scene.layout.geo(1);
      expect(geo.hangLanes, 0);
      expect(geo.height - geo.bandTop - geo.bandHeight, 4 * (G.zoneTab + G.zoneGap) + 3);
      expect(painter.debugLabels.where((l) => l.kind == 'mem'), isEmpty);
      expect(painter.links.flagOf(1), isNull, reason: '접을 것(구역 48)이 없다');
    });
  });
}
