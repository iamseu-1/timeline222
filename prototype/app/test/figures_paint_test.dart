import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/figures.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 인물의 활동 막대와 묶음(구역 37 · 38)을 검사한다. 값의 근거는 docs/명세-3단계/03-띠에-덧붙는-것.md 2절과
// 기준 덤프(prototype/results/dom/밀집-세부.json #292 · #296)의 숫자다.

const m = 1000000.0;

/// 넓게 본 장면(단계 11): 한 해가 4px쯤이라 '인물 n명'으로 묶이는 문턱(평균 6px)을 검사할 수 있다.
const level = 11;
final ppm = 32 / bucketMinutes(level);
double px(double pixels) => pixels / ppm;

/// 3판 줄 하나: 글줄 둘 · 기간 막대 두 단 · 인물 두 단(넉넉하게 — [make]). 자리는 SceneLayout이 계약 3절의 식으로 다시 쌓는다.
Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': -1,
  'cab_top': -1, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': [], 'fig': 2, 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 줄 0의 인물 단 [lane]의 위 자리(배치 px). 줄을 쌓은 결과에서 읽는다.
double figTop(TimelineScene scene, int lane) {
  final v = scene.controller.view, geo = scene.layout.geo(0);
  return v.yOf(scene.layout.rowTop(0) + geo.strip(6, lane).$1);
}

(TimelineScene, TimelinePainter) make(void Function(TileBuilder t) fill, {double zoom = 1}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(600);
  controller.showRange(0, (1920 - SceneView.gutter) / (ppm * zoom));
  final tile = TileBuilder(level: level, x: 0, chunk: 0)..band(7, 0, 0, px(1000), '은륜 제국', color: 0xabb3c9);
  fill(tile);
  final bytes = tile.build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 5}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rail_levels': 2, 'rows': [row(0)]}],
      'epochs': [],
    }),
    fetchTile: (l, x, chunk, packs) async => l == level && x == 0 && chunk == 0 ? bytes : TileBuilder(level: l, x: x, chunk: chunk).build(),
    labelCompute: (input) async => placeLabels(input),
  );
  // 리메이크 2부(목업 서고): 인물 단은 '넉넉하게'(밀도 −1)에서만 쌓인다 — 이 검사는 그 보기에서 인물 막대를 본다.
  scene.layout.setConditions(scene.layout.conditions.copyWith(density: -1));
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 60; i++) {
    paint(painter);
    await pumpEventQueue();
  }
}

List<FigureMark> marks(TimelinePainter painter, String kind) => (painter.debugSink.notes[kind] ?? const []).cast<FigureMark>();

void main() {
  test('인물 막대는 제 단에 놓이고 띠 안쪽 4px에 갇힌다', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3);
      t.item(FigureLook.secBar, 2, 0, px(500), px(700), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 1, b: 2);
      // 띠 밖으로 나간 섬김도 띠의 기간 안으로 잘린다.
      t.item(FigureLook.secBar, 3, 0, px(900), px(1500), ref: 7, color: 0xabb3c9, name: '은결 헤루나', a: 0, b: 2);
    });
    await settle(scene, painter);
    final bars = marks(painter, '인물');
    expect(bars.length, 3);
    expect(bars[0].x, closeTo(SceneView.gutter + 200.5, .01), reason: '띠 안에서 시작하는 막대는 0.5px 안쪽');
    expect(bars[0].width, closeTo(199, .01));
    expect(bars[0].height, G.figure);
    expect(bars[0].y, closeTo(figTop(scene, 0), .01));
    expect(bars[1].y, closeTo(figTop(scene, 1), .01), reason: '단 하나마다 G.figure 20 + G.figGap 3px 아래');
    expect(bars[1].y - bars[0].y, G.figure + G.figGap);
    // 띠는 0 ~ 1000px(화면 240 ~ 1240)이고 안쪽 4px이 한계 — 1236에서 끝난다.
    expect(bars[2].x + bars[2].width, closeTo(SceneView.gutter + 996, .01));
  });

  test('아주 짧은 활동도 3px은 보인다', () async {
    final (scene, painter) = make((t) => t.item(FigureLook.secBar, 1, 0, px(300), px(300.4), ref: 7, color: 0xabb3c9, name: '한 해 인물', a: 0, b: 2));
    await settle(scene, painter);
    final bar = marks(painter, '인물').single;
    expect(bar.width, closeTo(3, .01));
    expect(bar.x, closeTo(SceneView.gutter + 298.7, .01), reason: '구간의 가운데에 3px으로');
  });

  test('보이는 막대의 평균 폭이 6px 미만이면 단 전체가 인물 n명 한 칸이 된다(문턱 둘)', () async {
    // 4px짜리 막대 둘 → 평균 4px → 묶인다.
    void fill(TileBuilder t) {
      t.item(FigureLook.secBar, 1, 0, px(100), px(105), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2);
      t.item(FigureLook.secBar, 2, 0, px(300), px(305), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 0, b: 2);
      t.item(FigureLook.secGroup, 3, 0, 0, px(1000), ref: 7, color: 0xabb3c9, name: '은륜 제국', a: 2, b: 6, c: 80);
    }

    final (scene, painter) = make(fill);
    await settle(scene, painter);
    expect(marks(painter, '인물'), isEmpty);
    final dense = marks(painter, '인물묶음').single;
    expect(dense.name, '인물 2명');
    expect(dense.x, closeTo(SceneView.gutter + 4, .01), reason: '띠 안쪽 4px부터');
    expect(dense.width, closeTo(992, .01));
    expect(dense.height, G.figure);

    // 확대해서 평균이 6px을 넘으면 낱개 막대로 나뉜다(4px → 1.6배 = 6.4px).
    final (wide, widePainter) = make(fill, zoom: 1.6);
    await settle(wide, widePainter);
    expect(marks(widePainter, '인물묶음'), isEmpty);
    expect(marks(widePainter, '인물').length, 2);

    // 한 번 나뉘면 문턱의 92%(5.52px)까지는 나뉜 채로 — 1.4배(5.6px)로 되돌려도 그대로다.
    wide.controller.showRange(0, (1920 - SceneView.gutter) / (ppm * 1.4));
    await settle(wide, widePainter);
    expect(marks(widePainter, '인물').length, 2, reason: '문턱 되돌림 8%');
    expect(marks(widePainter, '인물묶음'), isEmpty);
  });

  test('막대 하나뿐인 띠는 묶지 않는다', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(100), px(105), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2);
      t.item(FigureLook.secGroup, 3, 0, 0, px(1000), ref: 7, color: 0xabb3c9, name: '은륜 제국', a: 1, b: 6, c: 80);
    });
    await settle(scene, painter);
    expect(marks(painter, '인물묶음'), isEmpty);
    expect(marks(painter, '인물').length, 1);
  });

  test('이름은 들어갈 때만 — 온 이름 → 첫 글자 → 없음', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(100), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3);
      t.item(FigureLook.secBar, 2, 0, px(500), px(520), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 1, b: 2);
      t.item(FigureLook.secBar, 3, 0, px(700), px(704), ref: 7, color: 0xabb3c9, name: '은결 헤루나', a: 0, b: 2);
    });
    await settle(scene, painter);
    final names = painter.debugLabels.where((l) => l.kind == 'fig').map((l) => l.text).toList();
    expect(names.contains('은결 디세나'), isTrue, reason: '299px에는 온 이름이 든다');
    expect(names.contains('은'), isTrue, reason: '19px에는 첫 글자만');
    expect(names.length, 2, reason: '3px 막대에는 이름이 없다');
  });

  test('조감에는 인물 단이 없다', () async {
    final (scene, painter) = make((t) => t.item(FigureLook.secBar, 1, 0, px(200), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3));
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
    await settle(scene, painter);
    expect(marks(painter, '인물'), isEmpty);
    expect(marks(painter, '인물묶음'), isEmpty);
  });

  test('다른 것을 고른 동안 인물 막대는 .5로 옅어지고 고른 인물만 1이다', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3, text2: 'f-1|-100|-50|h-0');
      t.item(FigureLook.secBar, 2, 0, px(500), px(700), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 1, b: 2, text2: 'f-2|||');
    });
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(band: 7));
    painter.figures.pickedFigure = 'f-1';
    await settle(scene, painter);
    final bars = {for (final b in marks(painter, '인물')) b.name: b.alpha};
    expect(bars['은결 디세나'], 1, reason: '고른 인물의 막대는 밝다');
    expect(bars['은결 유루나'], closeTo(.5, .001), reason: 'css:1384의 .tl.is-picked .tl-fig:not(.is-selected)');
  });

  test('고른 인물에게만 수명선과 끝 점이 나온다', () async {
    // 띠는 0 ~ 1000px. 생 100px · 몰 800px 자리에 두면 막대(300~500) 양옆으로 선이 뻗는다.
    // 생몰은 세계 분이다(text2의 둘째 · 셋째 칸). 이 장면은 타일 시작이 0분이라 px(…)이 곧 그 분이다.
    final birth = px(100), death = px(800);
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(300), px(500), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3,
          text2: 'f-1|${birth.toStringAsFixed(3)}|${death.toStringAsFixed(3)}|h-0');
    });
    await settle(scene, painter);
    expect(marks(painter, '수명선'), isEmpty, reason: '평소에는 보이지 않는다');

    final (hot, hotPainter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(300), px(500), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3,
          text2: 'f-1|${birth.toStringAsFixed(3)}|${death.toStringAsFixed(3)}|h-0');
    });
    hotPainter.figures.hoverFigure = 'f-1';
    await settle(hot, hotPainter);
    final lines = marks(hotPainter, '수명선');
    expect(lines.length, 2, reason: '막대의 왼쪽(생) · 오른쪽(몰) 두 토막');
    expect(lines[0].x, closeTo(SceneView.gutter + 100, .01));
    expect(marks(hotPainter, '수명선끝').length, 2, reason: '띠 · 화면에서 잘리지 않은 끝에만 끝 점');
  });

  test('가문 강조가 켜지면 그 가문의 막대만 진해진다 — 연표는 흐려지지 않는다', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2 | 32, text2: 'f-1|||h-0');
      t.item(FigureLook.secBar, 2, 0, px(500), px(700), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 1, b: 2 | 32, text2: 'f-2|||h-9');
    });
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(house: 'h-0'));
    await settle(scene, painter);
    // 가문 강조는 흐림을 부르지 않는다(명세 06의 3-5) — 둘 다 밝기 1.
    expect(marks(painter, '인물').every((b) => b.alpha == 1), isTrue);
    expect([for (final b in marks(painter, '가문인물')) b.name], ['은결 디세나'], reason: '그 가문(h-0)의 막대만 진하다');
  });

  // D1 결정 7 A(가문 조명 · 성씨 조명 — D1n 결합): 조명된 가문 묶음(Look.houses — 누른 가문 + 아래 파, 성씨면 그 성의 가문 모두)의
  // 인물 막대가 모두 진하다. 웹 setHouse(ids)의 is-house와 같다. 성씨 조명은 house 없이 houses만 온다.
  test('가문 · 성씨 조명(Look.houses)이면 묶음에 든 가문의 막대가 모두 진하다 — house 없이도', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2 | 32, text2: 'f-1|||h-0');
      t.item(FigureLook.secBar, 2, 0, px(500), px(700), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 1, b: 2 | 32, text2: 'f-2|||h-0-pa');
      t.item(FigureLook.secBar, 3, 0, px(800), px(950), ref: 7, color: 0xabb3c9, name: '은결 마리나', a: 0, b: 2 | 32, text2: 'f-3|||h-9');
    });
    final e = em.Emphasis.of(scene)..reduceMotion = true;
    e.set(const em.Look(houses: {'h-0', 'h-0-pa'}));
    await settle(scene, painter);
    expect([for (final b in marks(painter, '가문인물')) b.name], ['은결 디세나', '은결 유루나'], reason: '본가와 아래 파 — 다른 가문(h-9)은 그대로');
    expect(marks(painter, '인물').every((b) => b.alpha == 1), isTrue, reason: '조명은 연표를 흐리지 않는다');
    // 끄면(옛 꼴 — houses 없음) 진한 막대가 없다.
    e.set(const em.Look());
    painter.debugSink.notes.clear();
    await settle(scene, painter);
    expect(marks(painter, '가문인물'), isEmpty);
  });

  test('활동 기록의 이설은 막대 안의 유령 구분선이 된다', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(600), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2, text2: 'f-1|||');
      t.item(FigureLook.secAlt, 2, 0, px(300), px(600), ref: 7, color: 0xabb3c9, a: 0, b: 0, c: 0);
      // 막대 끝에서 3px 안이라 긋지 못한다.
      t.item(FigureLook.secAlt, 3, 0, px(599), px(600), ref: 7, color: 0xabb3c9, a: 0, b: 1, c: 0);
    });
    await settle(scene, painter);
    final ghosts = marks(painter, '활동이설').where((g) => g.kind == '활동이설').toList();
    expect(ghosts.length, 1);
    expect(ghosts[0].x, closeTo(SceneView.gutter + 300, .01));
  });

  // '이설' 표시 체크(SceneMarks.showAlt)를 끄면 지금 연표는 이 층의 이설을 모두 버린다 —
  // 유령 구분선 · '이설 있음' 점선은 `alt: this.showAlt && !this._bird`(js:6181 · 6444)로,
  // 생몰의 빈 고리는 `this.showAlt && !this._bird`(js:6449)로.
  test('이설 표시를 끄면 유령 구분선과 생몰 이설 고리가 사라진다', () async {
    final birth = px(100), death = px(800);
    void fill(TileBuilder t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(600), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2,
          text2: 'f-1|${birth.toStringAsFixed(3)}|${death.toStringAsFixed(3)}|');
      t.item(FigureLook.secAlt, 2, 0, px(300), px(600), ref: 7, color: 0xabb3c9, a: 0, b: 0, c: 0);
      t.item(FigureLook.secAlt, 3, 0, px(120), px(120), ref: 7, color: 0xabb3c9, a: 0, b: 4, c: 0);
    }

    final (on, onPainter) = make(fill);
    onPainter.figures.hoverFigure = 'f-1'; // 생몰의 이설은 고르거나 올렸을 때만 나온다
    await settle(on, onPainter);
    expect(marks(onPainter, '활동이설').length, 1);
    expect(marks(onPainter, '생몰이설').length, 1);

    final (off, offPainter) = make(fill);
    offPainter.figures.hoverFigure = 'f-1';
    SceneMarks.of(off).showAlt = false;
    await settle(off, offPainter);
    expect(marks(offPainter, '활동이설'), isEmpty);
    expect(marks(offPainter, '생몰이설'), isEmpty);
    expect(marks(offPainter, '인물').length, 1, reason: '막대 · 수명선은 그대로다');
    expect(marks(offPainter, '수명선').length, 2);
  });

  test('맞히기는 인물 막대와 인물 n명 한 칸을 집는다', () async {
    final (scene, painter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(200), px(400), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 3, text2: 'f-1|||');
    });
    await settle(scene, painter);
    final at = figTop(scene, 0) + 7;
    final hit = painter.figures.hitFigures(SceneView.gutter + 300, at);
    expect(hit?.figure, 'f-1');
    expect(hit?.band, 7);
    expect(hit?.group, isFalse);
    expect(painter.figures.hitFigures(SceneView.gutter + 300, at - 40), isNull);

    final (dense, densePainter) = make((t) {
      t.item(FigureLook.secBar, 1, 0, px(100), px(105), ref: 7, color: 0xabb3c9, name: '은결 디세나', a: 0, b: 2, text2: 'f-1|||');
      t.item(FigureLook.secBar, 2, 0, px(300), px(305), ref: 7, color: 0xabb3c9, name: '은결 유루나', a: 0, b: 2, text2: 'f-2|||');
      t.item(FigureLook.secGroup, 3, 0, 0, px(1000), ref: 7, color: 0xabb3c9, name: '은륜 제국', a: 2, b: 6, c: 80);
    });
    await settle(dense, densePainter);
    final group = densePainter.figures.hitFigures(SceneView.gutter + 300, figTop(dense, 0) + 7);
    expect(group?.group, isTrue, reason: '누르면 그 띠의 정권 상세 → 인물 목록');
    expect(group?.band, 7);
    expect(group?.count, 2);
  });
}
