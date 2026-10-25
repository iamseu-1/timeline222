import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/band_form.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/links.dart' show LinkLayer;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart' show ScopeLook;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 그릇 노릇 객체의 납작한 뚜껑(리메이크 4단계 과제 8 걸음 1 · 스위치 lid — paint/lid_tags.dart · 설계 4-6 #6 A):
// 동맹은 늘 · 나라 · 동군연합은 구성원(그 띠를 상국으로 삼는 소속 펼치기 변형)이 없을 때만 — 띠 상자(줄 높이 · 윗변 · 아랫변) · 구멍 · 머리 이름 자리는
// 그대로 두고 칠(먹 6 → 단계 4 · 사건 칸까지 하나) · 테(먹 30 → 단계 25 · 네 귀 모따기 6) · 밑선(먹 12 · 색줄 끝 − 1) · 이름 먹 85만 바뀐다.
// 국가 · 교단 · 시대 · 사람 · form 0 · 구성원이 있는 그릇 · 조감은 그대로이고, 스위치를 끄면 픽셀까지 예전과 같다.

const m = 1000000.0;
final ppm = 32 / bucketMinutes(9);
double px(double pixels) => pixels / ppm;

const sample = 0xacb4ca;

Map<String, dynamic> row(int id, {int kind = 0, int variant = 0}) => {
  'id': id, 'height': 80, 'band_top': 19, 'band_h': 61, 'dyn_top': -1, 'lead_top': -1,
  'cab_top': -1, 'text_top': 40, 'text_lines': 1, 'rail_top': -1, 'organ_top': -1,
  'kind': kind, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0,
  'cats': <int>[], 'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': variant,
};

Map<String, dynamic> vrow(int row, int after) => {'row': row, 'after': after, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0};

/// 줄 0 ~ 3 기본 · 4 · 5 소속 줄(띠 4 · 5의 소속 펼치기 — 켜지 않음. 변형이 있다 = 구성원이 있는 그릇).
SceneLayout layoutOf() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '세 포구 기록', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '세 포구', 'color': 0xa0bcc5,
      'rows': [row(0), row(1), row(2), row(3), row(4, kind: 1, variant: 1), row(5, kind: 1, variant: 2)],
    },
  ],
  'epochs': [],
  'variants': [
    {'id': 1, 'key': 'host:p/o-crown', 'kind': 1, 'track': 1, 'band': 4, 'uid': '', 'name': '해성 · 달섬 연합 왕관', 'rows': [vrow(4, 1)], 'groups': <dynamic>[]},
    {'id': 2, 'key': 'host:p/o-pine', 'kind': 1, 'track': 1, 'band': 5, 'uid': '', 'name': '솔 나라', 'rows': [vrow(5, 2)], 'groups': <dynamic>[]},
  ],
})..reduceMotion = true;

/// 띠의 form(계약 1-1 비트 — 종류 번호 + 1 · (정통성 번호 + 1) << 10). [type]이 빈 글이면 종류 비움.
int form(String type, {String legit = ''}) {
  final t = type.isEmpty ? -1 : BandForm.types.indexOf(type), l = legit.isEmpty ? -1 : BandForm.legits.indexOf(legit);
  return (t + 1) | (l + 1) << 10;
}

/// (id, 줄, 왼쪽, 오른쪽, 이름, 종류, 정통성) — 띠마다 관계선 층의 구멍(건국 네모 · 구역 20)도.
const bands = <(int, int, double, double, String, String, String)>[
  (1, 0, 200, 700, '세 포구 동맹', 'league', ''), // 동맹 — 늘 뚜껑
  (2, 0, 800, 1300, '외솔 나라', 'realm', ''), // 구성원 없는 나라 — 뚜껑
  (9, 0, 1400, 1650, '옛 그림 띠', '', ''), // form 0 — 그대로
  (3, 1, 200, 700, '달섬 연합', 'union', ''), // 구성원 없는 동군연합 — 뚜껑
  (4, 1, 800, 1300, '해성 · 달섬 연합 왕관', 'union', ''), // 구성원 있는 동군연합 — 그대로
  (10, 1, 1400, 1650, '바위골 사람', 'person', ''), // 사람 — 그대로
  (5, 2, 200, 700, '솔 나라', 'realm', ''), // 구성원 있는 나라 — 그대로
  (6, 2, 800, 1300, '하연 왕국', 'state', ''), // 국가 — 그대로
  (11, 2, 1400, 1650, '분지 상인 동맹', 'league', 'rival'), // 대립 동맹 — 뚜껑 · 파선 · 이름 먹 60
  (7, 3, 200, 700, '흰돌 교단', 'faith', ''), // 교단 — 제 꼬리표(둥근 끝)
  (8, 3, 800, 1300, '바위골 할거', 'era', ''), // 시대 — 그대로(감독 확인거리)
];

const lids = {1, 2, 3, 11};

/// [plain]이면 그릇 종류(나라 · 동군연합 · 동맹)를 비운 form(정통성은 그대로) — 그릇 종류도 끝 꼴은 옛 짐작이라 '뚜껑이 없던 그림'과 같다.
Uint8List tileOf({bool plain = false}) {
  final t = TileBuilder(level: 9, x: 1, chunk: 0);
  for (final (id, r, x0, x1, name, type, legit) in bands) {
    final kind = plain && const {'realm', 'union', 'league'}.contains(type) ? '' : type;
    t.band(id, r, px(x0), px(x1), name, color: sample, form: kind.isEmpty && legit.isEmpty ? 0 : form(kind, legit: legit));
    t.item(LinkLayer.secSquare, 100 + id, r, px(x0), px(x1), ref: id, name: name, color: sample);
  }
  return t.build();
}

TimelineScene sceneOf(SceneLayout layout, Uint8List tile) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(1000);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    labelCompute: (input) async => placeLabels(input),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? tile : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  scene.hide.add('fade');
  scene.applyLayoutToView();
  final origin = tileOrigin(9, 1).toDouble();
  controller.showRange(origin, origin + (1920 - layout.gutterWidth) / ppm);
  return scene;
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

/// 장면 하나를 짓고 이름까지 다 실릴 때까지 그린다. [lid]가 스위치 · [bird]면 조감(밀도 넷째 단계).
Future<(TimelineScene, TimelinePainter)> drawn({bool lid = true, bool plain = false, bool bird = false}) =>
    drawnOf(layoutOf(), tileOf(plain: plain), lid: lid, bird: bird);

// ---- 새 저장소 줄(걸음 4 검토 — 위 배치는 줄 값이 없는 옛 저장소 길만 돈다) ----

/// 줄 값이 실린 엔진 답 꼴의 줄(`rail` 칸이 있어 [RowFlags.fromAnswer] · `cell_rows` — chains_paint_test와 같은 꼴): 지도자 층 하나.
Map<String, dynamic> cellRow(int id) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 0, 'text_lines': 1,
  'rail_top': 0, 'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
  'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0, 'rail': 0, 'cell_rows': 1, 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'hang': 0,
};

SceneLayout cellLayoutOf() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '세 포구 기록', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '세 포구', 'color': 0xa0bcc5,
      'dynasty': 0, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 0,
      'rows': [cellRow(0), cellRow(1)],
    },
  ],
  'epochs': [],
})..reduceMotion = true;

/// 띠 look 비트 20 = 그 띠에 칸이 있다 · 21 + 5 = 지도자 층.
const withCells = 1 << 20 | 1 << 26;

/// (id, 줄, 왼쪽, 오른쪽, 이름, 종류, look) — 칸이 있는 뚜껑(몸통 = 지도자 층 + 사건 칸) · 칸이 없는 뚜껑(색줄 + 사건 칸 — 몸통 아랫변이 지도자 층만큼 올라감) ·
/// 같은 두 꼴의 국가 띠(늘 두 장 꼬리표).
const cellBands = <(int, int, double, double, String, String, int)>[
  (1, 0, 200, 700, '세 포구 동맹', 'league', withCells),
  (2, 0, 800, 1300, '외솔 나라', 'realm', 0),
  (6, 1, 200, 700, '하연 왕국', 'state', withCells),
  (7, 1, 800, 1300, '솔 왕국', 'state', 0),
];

Uint8List cellTileOf() {
  final t = TileBuilder(level: 9, x: 1, chunk: 0);
  for (final (id, r, x0, x1, name, type, look) in cellBands) {
    t.band(id, r, px(x0), px(x1), name, color: sample, look: look, form: form(type));
    t.item(LinkLayer.secSquare, 100 + id, r, px(x0), px(x1), ref: id, name: name, color: sample);
  }
  return t.build();
}

/// [layout] · [tile]로 장면을 짓고 이름까지 다 실릴 때까지 그린다.
Future<(TimelineScene, TimelinePainter)> drawnOf(SceneLayout layout, Uint8List tile, {bool lid = true, bool bird = false}) async {
  PaintPick.lid = lid;
  final scene = sceneOf(layout, tile);
  addTearDown(scene.dispose);
  if (bird) layout.setConditions(layout.conditions.copyWith(density: 2));
  scene.controller.setContentHeight(layout.totalHeight);
  final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
  for (int i = 0; i < 40; i++) {
    paint(painter);
    await pumpEventQueue();
    scene.tick(16);
  }
  painter.debugSink.clear();
  paint(painter);
  return (scene, painter);
}

Future<ByteData> render(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  picture.dispose();
  image.dispose();
  return data;
}

List<String> noted(TimelinePainter painter, String key) => [for (final v in painter.debugSink.notes[key] ?? const <Object>[]) '$v'];

/// '뚜껑' 기록의 띠 번호들.
Set<int> lidIds(TimelinePainter painter) => {for (final s in noted(painter, '뚜껑')) int.parse(s.split(' ').first)};

ui.Rect rectOf(TimelinePainter painter, int id) => painter.debugBands.firstWhere((b) => b.id == id).rect;

/// 렌더 결과의 ARGB(rawRgba를 다시 짠다).
int argbAt(ByteData p, double x, double y) {
  final at = (y.floor() * 1920 + x.floor()) * 4;
  return p.getUint8(at + 3) << 24 | p.getUint8(at) << 16 | p.getUint8(at + 1) << 8 | p.getUint8(at + 2);
}

/// 이름 글자 상자 안에서 [argb]와 같은 픽셀 수.
int inkIn(ByteData pixels, TimelinePainter painter, String name, int argb) {
  final tab = painter.debugLabels.firstWhere((l) => l.kind == 'tab' && l.text == name);
  var n = 0;
  for (int y = tab.at.dy.floor(); y < (tab.at.dy + BandLayer.tabNameSize * 1.2).ceil(); y++) {
    for (int x = tab.at.dx.floor(); x < tab.at.dx + 60; x++) {
      if (argbAt(pixels, x.toDouble(), y.toDouble()) == argb) n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);

  test('판단: 동맹은 늘 · 나라 · 동군연합은 구성원(소속 펼치기 변형)이 없을 때만 — 국가 · 교단 · 시대 · 사람 · form 0은 아니다 · 스위치를 끄면 없다', () {
    final layout = layoutOf();
    expect(LidTags.hostsOf(layout), {4, 5}, reason: '그 띠를 상국으로 삼는 소속 펼치기 변형');
    expect(identical(LidTags.hostsOf(layout), LidTags.hostsOf(layout)), isTrue, reason: '배치마다 한 번만 센다');
    for (final (id, _, _, _, name, type, legit) in bands) {
      final f = type.isEmpty && legit.isEmpty ? 0 : form(type, legit: legit);
      expect(LidTags.isLid(layout, f, id), lids.contains(id), reason: '$id $name($type)');
    }
    expect([BandForm.types[LidTags.typeRealm], BandForm.types[LidTags.typeUnion], BandForm.types[LidTags.typeLeague]], ['realm', 'union', 'league']);
    expect(LidLook.cham, ScopeLook.boxCham, reason: '그릇 그림의 상자 모따기와 같은 값');
    PaintPick.lid = false;
    expect(LidTags.isLid(layout, form('league'), 1), isFalse);
  });

  test('장면: 뚜껑은 동맹 · 구성원 없는 나라 · 동군연합 · 대립 동맹 넷 — 조감 · 스위치 끔에서는 없다', () async {
    final (_, on) = await drawn();
    expect(lidIds(on), lids, reason: noted(on, '뚜껑').join(' | '));
    final (_, bird) = await drawn(bird: true);
    expect(noted(bird, '뚜껑'), isEmpty, reason: '조감은 꼬리표가 아니다');
    final (_, off) = await drawn(lid: false);
    expect(noted(off, '뚜껑'), isEmpty);
  });

  test('자리는 그대로: 띠 상자 · 줄 높이 · 구멍(끝 꼴) · 머리 이름 자리 · 띠 기록이 스위치를 꺼도 같다', () async {
    final (onScene, on) = await drawn();
    final (offScene, off) = await drawn(lid: false);
    for (final (id, _, _, _, name, _, _) in bands) {
      expect(rectOf(on, id), rectOf(off, id), reason: '$id $name 띠 상자');
      expect(on.bands.endOf(id), off.bands.endOf(id), reason: '$id 끝 꼴(구멍 · 관계선)');
    }
    for (int r = 0; r < onScene.layout.rowCount; r++) {
      expect([onScene.layout.rowTop(r), onScene.layout.geo(r).height], [offScene.layout.rowTop(r), offScene.layout.geo(r).height], reason: '줄 $r');
    }
    expect(noted(on, '네모'), noted(off, '네모'), reason: '관계선 구멍 자리');
    expect(noted(on, '띠'), noted(off, '띠'), reason: '두 장 꼬리표와 같은 띠 기록');
    String tabs(TimelinePainter p) => [for (final l in p.debugLabels) if (l.kind == 'tab') '${l.text} ${l.at}'].join(' | ');
    expect(tabs(on), tabs(off), reason: '머리 이름 자리 · 크기');
    // 뚜껑 기록: 귀 6/6 · 밑선 = 색줄 끝 − 1(띠 윗변 + 13).
    for (final s in noted(on, '뚜껑')) {
      final id = int.parse(s.split(' ').first), rect = rectOf(on, id);
      expect(s, contains('귀=6/6'), reason: s);
      expect(s, contains('밑선=${(rect.top + G.head - 1).toStringAsFixed(1)}'), reason: s);
    }
  });

  // 걸음 4 검토: 뚜껑의 띠 상자는 두 장 꼬리표와 한 셈(bands.dart `_tagBox`)이다 — 새 저장소 길(칸 비트 20 · [TagLook.floorEndOf] · 사건 칸 올림
  // [TagLook.bodyBottom])도 스위치를 끈 두 장 꼬리표와 같은 상자인지 본다(합칠 때 칸 그림 갈래가 상자 셈을 고쳐도 이 시험이 둘을 묶는다).
  test('새 저장소 줄(cell_rows)에서도 자리는 그대로 — 칸 있는 뚜껑 · 칸 없는 뚜껑(지도자 층만큼 짧음)의 띠 상자 · 띠 기록이 스위치를 꺼도 같다', () async {
    // 스위치는 그릴 때 읽으므로 켠 장면의 기록 · 그림을 끈 장면을 짓기 전에 모두 받아 둔다(다시 그리면 기록도 빈다).
    final (onScene, on) = await drawnOf(cellLayoutOf(), cellTileOf());
    final lidNotes = noted(on, '뚜껑'), bandNotes = noted(on, '띠');
    final rects = {for (final b in cellBands) b.$1: rectOf(on, b.$1)};
    final image = await render(on);
    final (_, off) = await drawnOf(cellLayoutOf(), cellTileOf(), lid: false);
    expect({for (final s in lidNotes) int.parse(s.split(' ').first)}, {1, 2}, reason: lidNotes.join(' | '));
    final layout = onScene.layout;
    expect(layout.spec(0)!.cellRows, isTrue, reason: '새 저장소 줄');
    expect(layout.geo(0).leaderTop, greaterThanOrEqualTo(0), reason: '지도자 층');
    for (final (id, _, _, _, name, _, _) in cellBands) {
      expect(rects[id], rectOf(off, id), reason: '$id $name 띠 상자');
    }
    expect(bandNotes, noted(off, '띠'), reason: '두 장 꼬리표와 같은 띠 기록(색줄 · 몸통 · 칸)');
    // 새 저장소 길을 지났는가: 칸 비트가 기록에 실리고, 칸 없는 띠는 사건 칸이 색줄 바로 밑이라 지도자 층(14)만큼 짧다.
    String bandNote(int id) => bandNotes.singleWhere((s) => s.startsWith('$id '));
    expect(bandNote(1), contains('칸=true'));
    expect(bandNote(2), contains('칸=false'));
    final full = rects[1]!, short = rects[2]!;
    expect(full.height - short.height, G.floor, reason: '칸 없는 뚜껑의 아랫변은 지도자 층만큼 위');
    expect(rects[7]!.height, short.height, reason: '같은 꼴의 국가 띠와 같은 키');
    // 픽셀: 밑선은 둘 다 색줄 끝 − 1 · 아랫변 테는 짧아진 상자 끝 · 그 밑(올라간 몫)은 뚜껑 칠이 아니다.
    for (final id in [1, 2]) {
      final r = rects[id]!;
      expect(lidNotes.singleWhere((s) => s.startsWith('$id ')), contains('밑선=${(r.top + G.head - 1).toStringAsFixed(1)}'));
      expect(argbAt(image, r.center.dx, r.top + G.head - 1), CanvasInk.k12, reason: '$id 밑선');
      expect(argbAt(image, r.center.dx, r.bottom - 4), CanvasInk.k4, reason: '$id 사건 칸까지 칠 하나');
      expect(argbAt(image, r.center.dx, r.bottom - 1), CanvasInk.k25, reason: '$id 아랫변 테');
    }
    expect(argbAt(image, short.center.dx, short.bottom + 3), isNot(CanvasInk.k4), reason: '칸 없는 뚜껑 밑은 칠하지 않는다');
  });

  test('픽셀: 칠 먹 단계 4(사건 칸까지 하나) · 테 25(네 귀 모따기 6) · 밑선 12 · 이름 먹 85 — 국가 띠 · 끈 찍기는 예전 빛깔', () async {
    final (_, on) = await drawn();
    final image = await render(on);
    final rect = rectOf(on, 2);
    final x = rect.center.dx, mid = rect.center.dy;
    expect(argbAt(image, x, rect.top + 4), CanvasInk.k4, reason: '이름 색줄도 칠 하나');
    expect(argbAt(image, x, rect.bottom - 4), CanvasInk.k4, reason: '사건 칸도 같은 칠(흰 종이가 아님)');
    expect(argbAt(image, x, rect.top), CanvasInk.k25, reason: '윗변 테');
    expect(argbAt(image, x, rect.bottom - 1), CanvasInk.k25, reason: '아랫변 테');
    expect(argbAt(image, rect.left, mid), CanvasInk.k25, reason: '왼쪽 테');
    expect(argbAt(image, rect.right - 1, mid), CanvasInk.k25, reason: '오른쪽 테');
    expect(argbAt(image, x, rect.top + G.head - 1), CanvasInk.k12, reason: '밑선 = 색줄 끝 − 1');
    // 네 귀 모따기: 맨 귀 픽셀은 띠 밖(그림판 바탕) · 귀를 지나면 테.
    for (final (cx, cy) in [(rect.left, rect.top), (rect.right - 1, rect.top), (rect.left, rect.bottom - 1), (rect.right - 1, rect.bottom - 1)]) {
      expect(argbAt(image, cx, cy), Look.ground, reason: '귀 ($cx, $cy)는 모따기 밖');
    }
    expect(argbAt(image, rect.left + LidLook.cham + 2, rect.top), CanvasInk.k25, reason: '귀 뒤 윗변');
    expect(argbAt(image, rect.right - LidLook.cham - 3, rect.bottom - 1), CanvasInk.k25, reason: '오른쪽 아래 귀 앞 아랫변');
    expect(inkIn(image, on, '외솔 나라', LidLook.name), greaterThan(0), reason: '이름 먹 85');
    expect(inkIn(image, on, '외솔 나라', mixSrgb(0xff000000 | sample, Look.ink, .22)), 0);
    // 국가 띠는 예전 그대로 — 나라 색 칠 · 테 · 흰 사건 칸 · 이름은 나라 색 + 먹.
    final state = rectOf(on, 6), tone = BandLayer.toneOf(sample, 0, fuzzy: false);
    expect(argbAt(image, state.center.dx, state.top + 4), tone.fill);
    expect(argbAt(image, state.center.dx, state.top), tone.edge);
    expect(argbAt(image, state.center.dx, state.bottom - 4), Look.paper);
    expect(inkIn(image, on, '하연 왕국', mixSrgb(0xff000000 | sample, Look.ink, .22)), greaterThan(0));
    // 대립 동맹: 테는 파선(3 긋고 2 띄움) · 이름 먹 60이 85보다 이긴다.
    final rival = rectOf(on, 11);
    final top = [for (int k = 30; k < 130; k++) argbAt(image, rival.left + k, rival.top)];
    expect(top.where((p) => p == CanvasInk.k25).length / top.length, inInclusiveRange(.35, .65), reason: '파선 테');
    expect(inkIn(image, on, '분지 상인 동맹', TagLook.rivalName), greaterThan(0));
    expect(inkIn(image, on, '분지 상인 동맹', LidLook.name), 0);
    // 끄면 그 띠는 나라 색 칠 · 테 · 흰 사건 칸으로(스위치는 그릴 때 읽으므로 지은 바로 뒤에 찍는다).
    final (_, off) = await drawn(lid: false);
    final was = await render(off);
    expect(argbAt(was, x, rect.top + 4), tone.fill);
    expect(argbAt(was, x, rect.bottom - 4), Look.paper);
    expect(inkIn(was, off, '외솔 나라', LidLook.name), 0);
  });

  test('흐린 뚜껑(다른 띠를 고른 동안)도 아래의 연도 세로줄을 가리는 종이 — 칠은 그 자리 바탕과 섞은 불투명 색이라 한 줄 안에서 빛이 고르다(세로줄 얹기 · 4단계 마지막 합치기)', () async {
    final (scene, painter) = await drawn();
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(band: 6));
    for (int i = 0; i < 10; i++) {
      paint(painter);
      await pumpEventQueue();
      scene.tick(16);
    }
    final image = await render(painter);
    final rect = rectOf(painter, 2);
    // 이름(왼쪽 위)을 비켜 띠 오른쪽 반에서 — 색줄 위 칸 · 밑선 아래 칸.
    final xs = [for (var x = rect.center.dx.ceil(); x < rect.right - LidLook.cham - 2; x++) x.toDouble()];
    for (final y in [rect.top + 2, rect.top + 3, rect.bottom - 4, rect.bottom - 5]) {
      final row = {for (final x in xs) argbAt(image, x, y)};
      expect(row, hasLength(1), reason: '흐린 뚜껑 안 y $y에 세로줄이 비친다 — ${row.map((c) => c.toRadixString(16)).toList()}');
      expect(row.single, isNot(CanvasInk.k4), reason: '흐려졌다(고른 띠가 아니다)');
    }
    // 같은 열들의 뚜껑 밖 바탕(맨 아래 줄 밑)에는 세로줄이 그대로 — 이 시험이 헛돌지 않게.
    final below = rectOf(painter, 8).bottom + 20;
    final ground = {for (final y in [below, below + 1]) for (final x in xs) argbAt(image, x, y)};
    expect(ground.length, greaterThan(1), reason: '뚜껑 밖 바탕의 세로줄');
  });

  test('스위치를 끄면 바이트까지 예전 그림 — 그릇 종류를 비운 form(뚜껑이 없던 그림)과 같다', () async {
    // 스위치는 그릴 때 읽으므로 장면마다 지은 바로 뒤에 찍는다.
    final (_, off) = await drawn(lid: false);
    final a = await render(off);
    final (_, plain) = await drawn(plain: true);
    expect(noted(plain, '뚜껑'), isEmpty);
    final b = await render(plain);
    expect(a.lengthInBytes, b.lengthInBytes);
    var diff = 0;
    for (int i = 0; i < a.lengthInBytes; i += 4) {
      if (a.getUint32(i) != b.getUint32(i)) diff++;
    }
    expect(diff, 0, reason: '다른 픽셀 수');
    // 켠 그림은 뚜껑 자리만 다르다.
    final (_, on) = await drawn();
    final c = await render(on);
    final boxes = [for (final id in lids) rectOf(on, id).inflate(2)];
    var outside = 0, inside = 0;
    for (int y = 0; y < 1080; y++) {
      for (int x = 0; x < 1920; x++) {
        final i = (y * 1920 + x) * 4;
        if (a.getUint32(i) == c.getUint32(i)) continue;
        if (boxes.any((r) => r.contains(Offset(x + .5, y + .5)))) {
          inside++;
        } else {
          outside++;
        }
      }
    }
    expect(inside, greaterThan(0));
    expect(outside, 0, reason: '뚜껑 상자 밖은 같다');
  });
}
