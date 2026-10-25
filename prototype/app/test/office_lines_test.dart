import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagLook;
import 'package:archive_prototype/scene/paint/chains.dart';
import 'package:archive_prototype/scene/paint/gutter.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show StripLayer;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 직위 줄 더 층(G7 가 · 칸 그림 갈래 걸음 4 · 스위치 `office` — docs/계획-리메이크-4단계.md 과제 5 걸음 3 · 계약 1-1 덧붙임 · 고르기 판 G7 가
// `.claude/research/stage4-choose/themes/g-g7.js`): 줄 fig_wide 21 ~ 25(그 줄 띠들의 직위 줄 더 수 가운데 큰 값 n)가 선 줄은 내각 다음 · 예속 앞에
// n × 14(layout.dart `_bandOf` — RowGeo.officeTop · officeLanes) · 칸 종류 9의 lane k는 그 층의 k번째 줄(RowGeo.strip(9, k)). 띠는 제 수(sub 17 ~ 21)만
// 맞붙이고 남는 줄 · look 30이 없는 띠는 층을 뺀다(bands.dart TagLook.compactOf — 지도자 두 단과 같은 꼴). 그림은 지도자 칸과 같은 흰 각진 층 · 27비트면
// 빌림 꼴(.72 · 윗변 파선) · 머리 출처 글 `· 재상 ← 출처`(구역 54 a = 9 · 구역 55의 줄 이름) · 왼쪽 칸 줄 이름(구역 55 — 사슬 이름 꼴).
// 표시 '지도자'를 끄거나 · 줄 값이 없는 줄(변형이 새로 만든 줄 · 옛 저장소)이거나 · 스위치 office를 끄면 층이 없다(예전 그대로).

/// 줄 fig_wide의 배치 값: 비트 3 ~ 5 = 기간 막대 단 수 + 1(이 값이 서야 줄 값 셋을 읽음) · 17 지도자 칸 · 21 ~ 25 직위 줄 더 수 · 26 ~ 27 지도자 층 단 수 − 1.
int figWide({int office = 0, int lanes = 1, bool leader = true}) => 1 << 3 | (leader ? 1 << 17 : 0) | office << 21 | (lanes - 1) << 26;

/// 엔진 답 꼴의 줄 하나(legit_layout_test와 같은 꼴 — `rail` 칸이 있으면 나머지 칸도 읽는다).
Map<String, dynamic> row(int id, {int office = 0, int lanes = 1, bool leader = true, bool cabinet = true, bool cellRows = true}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': figWide(office: office, lanes: lanes, leader: leader), 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0,
  'rail': 0, 'cell_rows': cellRows ? 1 : 0, 'dynasty': 0, 'leader': leader ? 1 : 0, 'cabinet': cabinet ? 1 : 0, 'hang': 0,
};

/// 트랙 하나('office-a'): 줄 0 지도자 · 내각 · 직위 줄 더 2 / 1 지도자 · 내각(직위 줄 더 없음) / 2 지도자 두 단 · 내각 · 직위 줄 더 1 /
/// 3 줄 값 없음(cell_rows 0 — 변형이 새로 만든 줄의 꼴)이지만 직위 줄 더 비트 1 / 4 직위 줄 더 1뿐(지도자 · 내각 칸 없음). [bits]가 거짓이면 직위 줄 더 수를 모두 0으로.
Map<String, dynamic> officeLayout({bool bits = true}) {
  int n(int v) => bits ? v : 0;
  return {
    'packs': [
      {'id': 1, 'name': '직위 줄 더 견본', 'events': 0},
    ],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'office-a', 'dynasty': 0, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
        'rows': [
          row(0, office: n(2)),
          row(1),
          row(2, office: n(1), lanes: 2),
          row(3, office: n(1), cellRows: false),
          row(4, office: n(1), leader: false, cabinet: false),
        ],
      },
    ],
    'epochs': <dynamic>[],
    'categories': <dynamic>[],
    'axis': <dynamic>[],
  };
}

/// 스위치 office · legit을 두고 짓는다(배치는 지을 때 스위치를 읽는다).
SceneLayout build({bool office = true, bool legit = true, bool bits = true}) {
  PaintPick.office = office;
  PaintPick.legit = legit;
  return SceneLayout.fromJson(officeLayout(bits: bits))..reduceMotion = true;
}

/// 줄 생김새의 모든 값(legit_layout_test의 fields + 직위 줄 더).
List<Object> fields(RowGeo g) => [
  g.height, g.bandTop, g.bandHeight, g.dynastyTop, g.leaderTop, g.cabinetTop, g.textTop, g.textLines, g.railTop, g.organTop, g.phaseTop, g.phaseLanes,
  g.rankTop, g.powerTop, g.realTop, g.railLevels, g.figTop, g.figLevels, g.depTop, g.depHeight, g.zoneTop, g.zoneLanes, g.hangLanes, g.hangOpen, g.hemTop,
  g.lineH, g.bodyTop, g.floorEnd, g.chainTop, g.chainLanes, g.leaderLanes, g.officeTop, g.officeLanes, g.floorTops,
];

/// 띠 look: 비트 20 = 칸이 있다 · 21 + 5 지도자 · 21 + 6 내각 · 30 직위 줄 더 층. sub 17 ~ 21 = 띠의 직위 줄 더 수 · 22 ~ 23 = 지도자 단 수 − 1.
const hasCells = 1 << 20, leaderBit = 1 << 26, cabinetBit = 1 << 27, officeBit = Schema4.lookOfficeMore;
const lead = hasCells | leaderBit | cabinetBit, withOffice = lead | officeBit;
const twoLanes = 1 << 22;
int own(int n) => n << 17;

// ───────────── 그림 견본(장면) ─────────────

/// 단계 9에서 통 하나가 32px일 때의 1분 폭 — 자리는 모두 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(strips_paint_test와 같은 식).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// style: 순번(비트 15 ~ 26 = 순번 + 1).
int st(int seq) => (seq + 1) << 15;

/// 그림 장면의 배치: 줄 0 등불 성좌령(지도자 · 내각 · 직위 줄 더 1 — 제 줄 '재상') · 줄 1 등불 교단(지도자 · 직위 줄 더 1 — 둘 다 성좌령에서 빌림).
SceneLayout paintLayout() => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '직위 줄 더 견본', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'office-p', 'dynasty': 0, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
      'rows': [row(0, office: 1), row(1, office: 1, cabinet: false)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
})..reduceMotion = true;

/// 출처 글(구역 54의 a = 1 · 9 — 지도자 → 직위 줄 더 차례). 직위 줄 더 몫이 서면 출처 끝의 '/직위'(낱말과 같은 것)를 떼고 같은 출처를 한 글로(G7 가 꼴).
const borrowLeader = '· 지도자 ← 등불 성좌령/지도자', borrowBoth = '· 지도자 · 재상 ← 등불 성좌령';

/// 그림 영역 100 ~ 1600 px의 띠 둘. 지도자 · 내각 · 직위 줄 더 칸은 같은 자리(150 ~ 900 · 900 ~ 1500)라 칸 금이 세로로 맞는다.
Uint8List officeTile() {
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1600), '등불 성좌령', look: withOffice, sub: own(1))
    ..band(2, 1, at(100), at(1600), '등불 교단', look: hasCells | leaderBit | officeBit, sub: own(1), color: 0xc8b193)
    ..cell(10, 0, at(150), at(900), '등좌 서하', kind: 1, style: st(0))
    ..cell(11, 0, at(900), at(1500), '등좌 온결', kind: 1, style: st(1))
    ..cell(20, 0, at(150), at(900), '백등 내각', kind: 2, style: st(0))
    ..cell(21, 0, at(900), at(1500), '청등 내각', kind: 2, style: st(1))
    ..cell(30, 0, at(150), at(900), '재상 무결', kind: Schema4.cellOfficeMore, style: st(0))
    ..cell(31, 0, at(900), at(1500), '재상 은솔', kind: Schema4.cellOfficeMore, style: st(1))
    ..cell(40, 1, at(150), at(900), '등좌 서하', kind: 1, style: st(0) | Schema4.borrowed)
    ..cell(41, 1, at(900), at(1500), '등좌 온결', kind: 1, style: st(1) | Schema4.borrowed)
    ..cell(50, 1, at(150), at(900), '재상 무결', kind: Schema4.cellOfficeMore, style: st(0) | Schema4.borrowed)
    ..cell(51, 1, at(900), at(1500), '재상 은솔', kind: Schema4.cellOfficeMore, style: st(1) | Schema4.borrowed)
    // 구역 55 — 직위 줄 더의 줄 이름(b = 그 줄) · 구역 54 — 빌린 줄의 머리 글(a = 칸 종류 · b = 직위 줄 더의 줄)
    ..item(Schema4.secOfficeName, 60, 0, at(100), at(1600), ref: 1, name: '재상', b: 0)
    ..item(Schema4.secOfficeName, 61, 1, at(100), at(1600), ref: 2, name: '재상', b: 0)
    ..item(Schema4.secBorrowHead, 70, 1, at(100), at(1600), ref: 2, name: '등불 성좌령/지도자', a: 1, text2: 'sample/seat')
    ..item(Schema4.secBorrowHead, 71, 1, at(100), at(1600), ref: 2, name: '등불 성좌령/재상', a: Schema4.cellOfficeMore, b: 0, text2: 'sample/seat');
  return t.build();
}

(TimelineScene, TimelinePainter) make({bool office = true, bool leaders = true}) {
  PaintPick.office = office;
  final layout = paintLayout();
  if (!leaders) {
    layout
      ..setConditions(layout.conditions.copyWith(leaders: false))
      ..finishFlow();
  }
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(layout.totalHeight + 200);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final tile = officeTile();
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? tile : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  addTearDown(scene.dispose);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  for (int i = 0; i < 6; i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
    if (!painter.text.starved) break;
  }
  expect(painter.text.starved, isFalse, reason: '글줄 준비가 모자란 장면이다');
}

/// 장면을 그림으로 떠서 RGBA 바이트(1920×1080).
Future<Uint8List> pixelsOf(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 그 픽셀의 0xRRGGBB(알파는 뺌).
int rgbAt(Uint8List px, num x, num y) {
  final i = (y.floor() * 1920 + x.floor()) * 4;
  return px[i] << 16 | px[i + 1] << 8 | px[i + 2];
}

List<String> noted(TimelinePainter painter, String kind) => [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// 검사용 칸 기록 '종류:줄:단 l,t,w,h'(0.1px 단위).
typedef Cell = ({int kind, int row, int lane, double l, double t, double w, double h});

List<Cell> cellsOf(TimelinePainter painter) => [
  for (final n in noted(painter, '칸'))
    () {
      final head = n.split(' ')[0].split(':'), box = [for (final v in n.split(' ')[1].split(',')) int.parse(v) / 10];
      return (kind: int.parse(head[0]), row: int.parse(head[1]), lane: int.parse(head[2]), l: box[0], t: box[1], w: box[2], h: box[3]);
    }(),
];

/// 줄 [row]의 줄 몫 안 y를 화면 y로.
double screenY(TimelineScene scene, int row, double y) => scene.controller.view.yOf(scene.layout.rowTop(row) + y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);

  group('쌓기(layout.dart _bandOf)', () {
    test('직위 줄 더 n줄은 내각 다음 · 예속 앞에 n × 14 — 줄 높이 +14n · 줄마다 층 윗변 · 뒤 줄은 그만큼 내려선다', () {
      final l = build(), off = build(office: false);
      final g = l.geo(0), o = off.geo(0);
      expect(l.spec(0)!.officeMore, 2, reason: '줄 fig_wide 21 ~ 25');
      expect([g.officeLanes, g.officeDepth], [2, 2 * G.floor]);
      expect([g.leaderTop, g.cabinetTop], [o.leaderTop, o.cabinetTop], reason: '위 층은 그대로');
      expect(g.officeTop, g.cabinetTop + G.floor, reason: '내각 다음');
      expect(g.floorEnd, g.officeTop + 2 * G.floor);
      expect(g.textTop, g.floorEnd, reason: '사건 칸은 칸 뭉치 바로 밑');
      expect(g.floorTops, [g.leaderTop, g.cabinetTop, g.officeTop, g.officeTop + G.floor], reason: '직위 줄 더는 줄마다 제 층');
      expect(g.height - o.height, 2 * G.floor);
      expect(g.bandHeight - o.bandHeight, 2 * G.floor);
      // 칸 종류 9의 자리: 줄 k = 층 윗변 + 14k · 줄 밖 · 층 없는 줄은 (−1, 0).
      expect(g.strip(9), (g.officeTop, 14.0));
      expect(g.strip(9, 1), (g.officeTop + 14, 14.0));
      expect(g.strip(9, 2), (-1.0, 0.0));
      expect(l.geo(1).officeTop, -1);
      expect(l.geo(1).strip(9), (-1.0, 0.0));
      // 직위 줄 더만 있는 줄(지도자 · 내각 칸 없음): 몸통의 첫 층.
      final only = l.geo(4);
      expect([only.leaderTop, only.cabinetTop, only.officeTop, only.officeLanes], [-1, -1, only.bodyTop, 1]);
      expect(only.floorTops, [only.bodyTop]);
      // 뒤 줄: 줄 0 · 2 · 4의 층만큼(줄 3은 줄 값이 없어 층 없음).
      expect(l.rowTop(1) - off.rowTop(1), 2 * G.floor);
      expect(l.rowTop(3) - off.rowTop(3), 3 * G.floor);
      expect(l.rowTop(4) - off.rowTop(4), 3 * G.floor);
      expect(l.totalHeight - off.totalHeight, 4 * G.floor);
      // 흐르는 동안의 생김새(withHeight)도 층을 지닌다.
      final flowing = g.withHeight(10);
      expect([flowing.officeTop, flowing.officeLanes, flowing.strip(9, 1), flowing.floorTops], [g.officeTop, 2, g.strip(9, 1), g.floorTops]);
    });

    test('띠마다 제 수 — 제 수만 맞붙이고 남는 줄 · look 30이 없는 띠는 층을 뺀다(층 안 제 줄 자리는 그대로)', () {
      final g = build().geo(0);
      double compact(int look, double y, {int sub = 0}) => TagLook.compactOf(g, look, y, sub: sub);
      // 제 수 2(줄과 같음): 줄의 자리 그대로.
      expect(compact(withOffice, g.floorEnd, sub: own(2)), g.floorEnd);
      expect(compact(withOffice, g.officeTop + 14, sub: own(2)), g.officeTop + 14, reason: '제 줄 1의 자리');
      // 제 수 1: 층 아래 자리만 남는 줄(14)만큼 올림 · 층 안은 그대로.
      expect(compact(withOffice, g.floorEnd, sub: own(1)), g.floorEnd - 14);
      expect(compact(withOffice, g.officeTop, sub: own(1)), g.officeTop);
      // 제 수가 줄보다 크면 줄 수까지만(예전 셈 그대로).
      expect(compact(withOffice, g.floorEnd, sub: own(5)), g.floorEnd);
      // look 30이 없는 띠: 층 전체(28)만큼 · 층 윗변 자체는 위 층만 뺀다.
      expect(compact(lead, g.floorEnd), g.floorEnd - 28);
      expect(compact(lead, g.officeTop), g.officeTop);
      // 직위 줄 더만 가진 띠(지도자 · 내각 없음): 위 층(지도자 · 내각)을 빼고 몸통 윗변부터 제 층.
      expect(compact(hasCells | officeBit, g.officeTop, sub: own(2)), g.bodyTop);
      expect(compact(hasCells | officeBit, g.officeTop + 14, sub: own(2)), g.bodyTop + 14);
      // 몸통 아랫변 · 사건 칸 올림(floorEndOf · eventLift · bodyBottom)이 같은 셈을 따른다.
      expect(TagLook.floorEndOf(g, withOffice, sub: own(2)), g.floorEnd);
      expect(TagLook.floorEndOf(g, withOffice, sub: own(1)), g.floorEnd - 14);
      expect(TagLook.eventLift(g, withOffice, oldStore: false, loose: false, sub: own(1)), 14.0);
      expect(TagLook.eventLift(g, lead, oldStore: false, loose: false, sub: 0), 28.0);
      expect(TagLook.eventLift(g, hasCells | officeBit, oldStore: false, loose: false, sub: own(2)), 28.0, reason: '남의 지도자 · 내각 층');
      expect(TagLook.bodyBottom(g, withOffice, oldStore: false, sub: own(1)), g.bandTop + g.bandHeight - 14);
      expect(TagLook.eventLift(g, withOffice, oldStore: true, loose: false, sub: own(1)), 0.0, reason: '옛 저장소는 줄의 자리');
      expect(TagLook.eventLift(g, withOffice, oldStore: false, loose: true, sub: own(1)), 0.0, reason: '넉넉하게는 올리지 않는다');
    });

    test('두 단 지도자와 함께인 줄 — 걸음 2의 지도자 단 셈(줄 단 − 제 단)과 직위 줄 더 셈(줄 수 − 제 수)이 차례대로 맞는다(손셈)', () {
      final g = build().geo(2);
      expect([g.leaderLanes, g.officeLanes], [2, 1]);
      expect(g.cabinetTop, g.leaderTop + 2 * G.floor);
      expect(g.officeTop, g.cabinetTop + G.floor);
      expect(g.floorEnd, g.officeTop + G.floor);
      expect(g.floorTops, [g.leaderTop, g.cabinetTop, g.officeTop]);
      double compact(int look, double y, {int sub = 0}) => TagLook.compactOf(g, look, y, sub: sub);
      final body = g.bodyTop;
      // 두 단 띠 · 직위 줄 더 1: 지도자 28 → 내각 14 → 직위 줄 더 14(줄 자리 그대로).
      expect(compact(withOffice, g.officeTop, sub: twoLanes | own(1)), body + 42);
      expect(TagLook.floorEndOf(g, withOffice, sub: twoLanes | own(1)), body + 56);
      // 한 단 띠 · 직위 줄 더 1: 지도자 14 → 내각 14 → 직위 줄 더 14.
      expect(compact(withOffice, g.cabinetTop, sub: own(1)), body + 14);
      expect(compact(withOffice, g.officeTop, sub: own(1)), body + 28);
      expect(TagLook.floorEndOf(g, withOffice, sub: own(1)), body + 42);
      // 한 단 띠 · 직위 줄 더 없음: 지도자 14 → 내각 14(남는 지도자 단 14 + 직위 줄 더 층 14를 뺌).
      expect(TagLook.floorEndOf(g, lead, sub: 0), body + 28);
      // 지도자 칸 없는 띠(내각 · 직위 줄 더): 지도자 층 전체(28)를 뺌 — 내각 14 → 직위 줄 더 14.
      expect(compact(hasCells | cabinetBit | officeBit, g.officeTop, sub: own(1)), body + 14);
      expect(TagLook.floorEndOf(g, hasCells | cabinetBit | officeBit, sub: own(1)), body + 28);
      // 직위 줄 더만: 몸통 윗변부터 제 층 하나.
      expect(TagLook.floorEndOf(g, hasCells | officeBit, sub: own(1)), body + 14);
    });

    test("표시 '지도자' 끔 · 줄 값 없는 줄은 층이 없다", () {
      final l = build();
      final before = l.geo(0);
      l.setConditions(l.conditions.copyWith(leaders: false));
      l.finishFlow();
      final hidden = l.geo(0);
      expect([hidden.officeTop, hidden.officeLanes, hidden.officeDepth], [-1, 0, 0]);
      expect(hidden.floorTops, [hidden.cabinetTop]);
      expect(before.height - hidden.height, 3 * G.floor, reason: '지도자 14 + 직위 줄 더 28');
      expect(l.geo(4).floorTops, isEmpty, reason: '직위 줄 더만 있는 줄은 칸 층이 하나도 없다');
      expect(l.geo(4).floorEnd, l.geo(4).bodyTop);
      // 줄 값 없는 줄(cell_rows 0 — 변형이 새로 만든 줄과 같은 꼴): fig_wide의 수가 1이어도 층 없음(트랙 값으로 쌓음).
      final bare = build();
      expect(bare.spec(3)!.officeMore, 1);
      expect([bare.geo(3).officeTop, bare.geo(3).officeLanes], [-1, 0]);
      expect(bare.geo(3).floorEnd, bare.geo(3).cabinetTop + G.floor);
    });

    test('스위치 office를 끄면 예전 손셈 그대로 — 직위 줄 더 비트가 있어도 층 없음 · look 30은 칸 층 비트로 읽지 않는다', () {
      final off = build(office: false);
      final plain = build(office: false, bits: false);
      for (int r = 0; r < 5; r++) {
        expect(fields(off.geo(r)), fields(plain.geo(r)), reason: '줄 $r: 직위 줄 더 수가 없는 줄과 같다');
      }
      // 직위 줄 더 수가 없는 줄은 스위치와 상관없이 같다.
      final on = build(bits: false);
      for (int r = 0; r < 5; r++) {
        expect(fields(on.geo(r)), fields(plain.geo(r)), reason: '줄 $r');
      }
      // 끈 동안의 맞붙이기: 가림이 예전 0x1ff — 직위 줄 더만 가진 띠는 '칸 종류 비트 없음'(줄의 칸 뭉치 끝) · 비트 30은 셈에 들지 않는다.
      PaintPick.office = false;
      final g = off.geo(0);
      expect(TagLook.floorBitsOf(hasCells | officeBit), 0);
      expect(TagLook.floorEndOf(g, hasCells | officeBit, sub: own(2)), g.floorEnd);
      expect(TagLook.compactOf(g, withOffice, g.floorEnd, sub: own(1)), TagLook.compactOf(g, lead, g.floorEnd, sub: 0));
      PaintPick.office = true;
      expect(TagLook.floorBitsOf(hasCells | officeBit), 1 << TagLook.officeFloorBit);
    });
  });

  group('그림(paint/strips.dart · bands.dart · gutter.dart)', () {
    test('층 칸 — 지도자 칸과 같은 흰 각진 층(층 윗금 · 칠 · 칸 금 픽셀이 내각 층과 같음) · 이름 8.5 지도자 꼴', () async {
      final (scene, painter) = make();
      await settle(scene, painter);
      final px = await pixelsOf(painter);
      final geo = scene.layout.geo(0);
      final cells = cellsOf(painter);
      final office = cells.where((c) => c.kind == Schema4.cellOfficeMore && c.row == 0).toList()..sort((a, b) => a.l.compareTo(b.l));
      final cabinet = cells.where((c) => c.kind == 2 && c.row == 0).toList()..sort((a, b) => a.l.compareTo(b.l));
      expect(office.length, 2, reason: '줄 0의 직위 줄 더 칸 둘');
      final top = screenY(scene, 0, geo.officeTop);
      expect([for (final c in office) c.t], everyElement(top + 1), reason: '층 윗금 아래부터(칸 칠 · 금 · 글)');
      expect([for (final c in office) c.h], everyElement(G.floor - 1));
      expect([for (final c in office) (c.l, c.w)], [for (final c in cabinet) (c.l, c.w)], reason: '같은 구간의 내각 칸과 같은 가로 자리');
      // 픽셀: 직위 줄 더 층(윗금 포함 14줄) = 내각 층(같은 x) — 이름이 없는 왼쪽 몫(칸 왼쪽 + 4 ~ + 120).
      final cabTop = screenY(scene, 0, geo.cabinetTop);
      var seen = 0;
      for (final c in office) {
        for (double x = c.l + 4; x < c.l + 120; x += 3) {
          for (int dy = 0; dy < 14; dy++) {
            expect(rgbAt(px, x, top + dy), rgbAt(px, x, cabTop + dy), reason: 'x $x · 층 안 $dy');
            seen++;
          }
        }
      }
      expect(seen, greaterThan(100));
      expect(rgbAt(px, office.first.l + 10, top), isNot(rgbAt(px, office.first.l + 10, top + 5)), reason: '층 윗금이 그어졌다');
      // 이름: 칸마다 하나(밝기 1) · 층 안.
      final names = painter.debugLabels.where((l) => l.kind == 'cell' && l.text.startsWith('재상') && l.at.dy < screenY(scene, 1, 0)).toList();
      expect([for (final l in names) l.text], unorderedEquals(['재상 무결', '재상 은솔']));
      for (final l in names) {
        expect(l.alpha, 1.0);
        expect(l.at.dy, greaterThan(top));
        expect(l.at.dy, lessThan(top + G.floor));
      }
    });

    test('빌린 층(27비트) — 칸 전체 .72 · 층 맨 윗줄 파선 · 이름 짙기 .72', () async {
      final (scene, painter) = make();
      await settle(scene, painter);
      final geo = scene.layout.geo(1);
      final top = screenY(scene, 1, geo.officeTop);
      final office = cellsOf(painter).where((c) => c.kind == Schema4.cellOfficeMore && c.row == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
      expect(office.length, 2);
      expect([for (final c in office) c.t], everyElement(top + 1));
      expect(noted(painter, '칸밝기').where((n) => n.startsWith('9:1:0 ')), everyElement(endsWith(' 720,720')));
      expect(noted(painter, '칸밝기').where((n) => n.startsWith('9:0:0 ')), everyElement(endsWith(' 1000,1000')), reason: '제 줄은 그대로');
      final dashes = noted(painter, '빌린칸').where((n) => n.startsWith('9:1:0 ')).toList();
      expect(dashes, [
        for (final c in office) '9:1:0 ${(c.l * 10).round()},${((top) * 10).round()},${(c.w * 10).round()} 720',
      ], reason: '칸마다 층 맨 윗줄(칸 한 줄 위)에 파선');
      expect(noted(painter, '빌린칸').where((n) => n.startsWith('9:0:')), isEmpty, reason: '제 줄은 파선 없음');
      final names = painter.debugLabels.where((l) => l.kind == 'cell' && l.text.startsWith('재상') && l.at.dy > top).toList();
      expect(names.length, 2);
      expect(names.map((l) => l.alpha), everyElement(closeTo(StripLayer.borrowedAlpha, 1e-9)));
      // 이름 비키기 열쇠: 줄 0의 직위 줄 더 열쇠(`row << 11 | 9 << 8`이면 0x900)가 줄 1의 지도자 열쇠(0x800 | 0x100)와 같아져 줄 1의 이름이 모두
      // 빠지던 겹침을 종류 9만 제 열쇠로 막았다 — 줄 1의 지도자 · 직위 줄 더 이름이 다 그려진다.
      final leaders = painter.debugLabels.where((l) => l.kind == 'cell' && l.text.startsWith('등좌') && l.at.dy > screenY(scene, 1, 0)).toList();
      expect([for (final l in leaders) l.text], unorderedEquals(['등좌 서하', '등좌 온결']));
    });

    test("머리 출처 글 — 빌린 직위 줄 더는 구역 55의 줄 이름으로(지도자 몫 뒤 · 같은 출처는 '· 지도자 · 재상 ← 출처' 한 글) · 층이 없으면 그 몫은 빠지고 예전 글", () async {
      String? borrowOf(TimelinePainter p) {
        final b = p.debugLabels.where((l) => l.kind == 'borrow').toList();
        return b.isEmpty ? null : b.single.text;
      }

      final (scene, painter) = make();
      await settle(scene, painter);
      expect(borrowOf(painter), borrowBoth);
      // 스위치 office 끔: 층이 없어 직위 줄 더 몫이 빠지고 지도자 몫은 예전 그대로 · 종류 9 칸 · 왼쪽 칸 이름도 없다.
      final (scene2, painter2) = make(office: false);
      await settle(scene2, painter2);
      expect(borrowOf(painter2), borrowLeader);
      expect(cellsOf(painter2).where((c) => c.kind == Schema4.cellOfficeMore), isEmpty);
      expect(painter2.debugLabels.where((l) => l.kind == 'officeLabel'), isEmpty);
      expect(painter2.strips.officeMarks, isEmpty);
      // 표시 '지도자' 끔: 층이 없어 직위 줄 더 몫이 빠진다(지도자 몫은 칸이 없어도 예전처럼 쓴다).
      final (scene3, painter3) = make(leaders: false);
      await settle(scene3, painter3);
      expect(borrowOf(painter3), borrowLeader);
      expect(cellsOf(painter3).where((c) => c.kind == Schema4.cellOfficeMore), isEmpty);
    });

    test('왼쪽 칸 줄 이름 — 줄마다 그 층 가운데 · 칸 오른쪽 끝 − 12에 오른쪽 맞춤(10 · 틀 먹 50 — 사슬 이름 꼴) + 6px 금(틀 먹 20)', () async {
      final (scene, painter) = make();
      await settle(scene, painter);
      final px = await pixelsOf(painter);
      final labels = painter.debugLabels.where((l) => l.kind == 'officeLabel').toList();
      expect([for (final l in labels) l.text], ['재상', '재상'], reason: '줄 0 · 1의 직위 줄 더 층');
      expect(painter.strips.officeMarks.keys.toSet(), {0 * 32 + 0, 1 * 32 + 0});
      const look = TextLook(ChainLook.labelSize, ui.FontWeight.w400, 0xff000000);
      for (final (i, l) in labels.indexed) {
        final row = painter.strips.officeMarks.values.elementAt(i).row;
        final y = screenY(scene, row, scene.layout.geo(row).officeTop) + G.floor / 2;
        final w = painter.text.widthOf(l.text, look)!;
        expect(l.at.dx + w, closeTo(GutLook.width - ChainLook.labelRight, 1e-6), reason: '줄 $row 오른쪽 맞춤');
        expect(l.at.dy, Gut.textTopAt(y - 10 * Gut.lineRatio / 2, 10 * Gut.lineRatio, 10), reason: '줄 $row 층 가운데');
        var ink = 0;
        for (int x = (GutLook.width - ChainLook.lineFrom).round(); x < GutLook.width - ChainLook.lineTo; x++) {
          if (rgbAt(px, x, y) != 0xffffff) ink++;
        }
        expect(ink, 6, reason: '줄 $row 금');
      }
      expect(noted(painter, '직위줄이름').length, 2);
    });

    test('왼쪽 칸 — 사슬 이름과 직위 줄 더 이름이 맞닿으면 화면 왼쪽에 가까운 띠의 이름 하나만(칸 그림 갈래 걸음 6 · f4-legit 몸통 줄 20 지위 ↔ 재상)', () async {
      // 줄 하나: 지도자 · 내각 · 직위 줄 더 1 · 지위 사슬. 가람 나라는 지도자 칸과 지위 사슬뿐(직위 줄 더 · 내각 층이 없어 사슬이 그만큼 올라섬 —
      // TagLook.compactOf) · 포구 나라는 지도자 · 내각 · 직위 줄 더('재상'). 두 이름이 몇 px 차로 선다.
      Future<(TimelineScene, TimelinePainter)> scene2({required bool chainLeft, bool office = true}) async {
        PaintPick.office = office;
        final layout = SceneLayout.fromJson({
          'packs': [
            {'id': 1, 'name': '맞닿는 이름 견본', 'events': 0},
          ],
          'tracks': [
            {
              'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'office-c', 'dynasty': 0, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
              'rows': [{...row(0, office: 1), 'rank': 1}],
            },
          ],
          'epochs': <dynamic>[],
          'categories': <dynamic>[],
          'axis': <dynamic>[],
        })..reduceMotion = true;
        final (aL, aR, bL, bR) = chainLeft ? (100.0, 800.0, 900.0, 1600.0) : (900.0, 1600.0, 100.0, 800.0);
        final t = TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(aL), at(aR), '가람 나라', look: hasCells | 1 << 23 | leaderBit)
          ..band(2, 0, at(bL), at(bR), '포구 나라', look: withOffice, sub: own(1), color: 0xc8b193)
          ..cell(10, 0, at(aL + 50), at(aR - 50), '가람 첫왕', kind: 1, style: st(0))
          ..cell(11, 0, at(aL + 50), at(aR - 50), '왕국', kind: 5, style: st(0) | 1 << 8)
          ..cell(20, 0, at(bL + 50), at(bR - 50), '포구 첫왕', kind: 1, style: st(0))
          ..cell(21, 0, at(bL + 50), at(bR - 50), '포구 내각', kind: 2, style: st(0))
          ..cell(22, 0, at(bL + 50), at(bR - 50), '포구 재상', kind: Schema4.cellOfficeMore, style: st(0))
          ..item(Schema4.secOfficeName, 60, 0, at(bL), at(bR), ref: 2, name: '재상', b: 0);
        final tile = t.build();
        final controller = TimelineController()
          ..reduceMotion = true
          ..resize(1920, 1080)
          ..setExtent(-at(100000), at(100000))
          ..setContentHeight(layout.totalHeight + 200);
        controller.showRange(0, at(1920 - SceneView.gutter));
        final scene = TimelineScene(
          controller: controller,
          layout: layout,
          fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? tile : TileBuilder(level: level, x: x, chunk: chunk).build(),
        );
        addTearDown(scene.dispose);
        final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
        await settle(scene, painter);
        return (scene, painter);
      }

      List<String> labels(TimelinePainter p, String kind) => [for (final l in p.debugLabels.where((l) => l.kind == kind)) l.text];

      // 사슬 띠가 왼쪽: 두 이름의 높이 차가 글 크기 + 2 안(맞닿음)이고 '지위'만 남음.
      final (_, p1) = await scene2(chainLeft: true);
      final chain = p1.strips.chainMarks.values.single, office = p1.strips.officeMarks.values.single;
      expect((chain.y - office.y).abs(), lessThan(ChainLook.labelSize + 2), reason: '견본이 맞닿는 자리여야 한다(사슬 ${chain.y} · 직위 ${office.y})');
      expect(chain.x, lessThan(office.x));
      expect(labels(p1, 'chainLabel'), ['지위']);
      expect(labels(p1, 'officeLabel'), isEmpty);
      expect(noted(p1, '왼쪽칸이름비킴'), ['직위 0:0 재상']);

      // 직위 줄 더 띠가 왼쪽: '재상'만 남고 사슬 이름이 비킴.
      final (_, p2) = await scene2(chainLeft: false);
      expect(labels(p2, 'officeLabel'), ['재상']);
      expect(labels(p2, 'chainLabel'), isEmpty);
      expect(noted(p2, '왼쪽칸이름비킴'), ['사슬 0:1 지위']);

      // 스위치 office 끔: 직위 줄 더 층 · 이름이 없어 사슬 이름은 예전 그대로.
      final (_, p3) = await scene2(chainLeft: true, office: false);
      expect(labels(p3, 'chainLabel'), ['지위']);
      expect(p3.strips.officeMarks, isEmpty);
      expect(noted(p3, '왼쪽칸이름비킴'), isEmpty);
    });

    test('왼쪽 칸 이름 비킴은 화면 왼쪽부터 한 번에 — 비킨 이름은 상대가 되지 않는다(사슬 A · 직위 B · 사슬 C 엇갈림 · 앞 이름에게 비킨 사슬 뒤의 직위)', () {
      ChainMark chain(double x, double y, [String label = '지위']) => ChainMark(0, 1, label, x, y);
      ChainMark office(double x, double y, [String label = '재상']) => ChainMark(0, 0, label, x, y);
      List<String> yielded(List<ChainMark> chains, List<ChainMark> offices) =>
          [for (final m in GutterLayer.yieldedNames(chains, offices, 0, 1000)) '${m.label}@${m.x.round()}'];
      // A(사슬 10) · B(직위 20 — A와 8 · C와 9 차) · C(사슬 30): B만 비키고 C는 그린다(예전 셈은 C가 그리지 않는 B에게 비켜 이름 둘이 사라졌다).
      final a = chain(10, 100, 'A'), b = office(20, 108, 'B'), c = chain(30, 117, 'C');
      expect(yielded([a, c], [b]), ['B@20']);
      // D(직위 5) · A(사슬 10 — D와 8 차) · B(직위 20 — A와 8 · D와 16 차): A가 D에게 비키므로 B는 남는다(직위 이름끼리는 14 떨어져 겹치지 않음).
      final d = office(5, 92, 'D');
      expect(yielded([a], [d, b]), ['A@10']);
      // 같은 자리면 직위 줄 더 이름이 비킨다 · 12 이상 떨어지면 둘 다 · 왼쪽 칸 밖(위 · 아래)의 이름은 상대가 아니다.
      expect(yielded([chain(10, 100)], [office(10, 105)]), ['재상@10']);
      expect(yielded([chain(10, 100)], [office(5, 112)]), isEmpty);
      expect(GutterLayer.yieldedNames([chain(10, 3)], [office(20, 8)], 0, 1000), isEmpty, reason: '위 밖(y − 6 < 0)의 사슬 이름은 그리지 않아 상대가 아니다');
      expect(GutterLayer.yieldedNames([chain(10, 100)], const [], 0, 1000), isEmpty);
    });
  });

  // 직위 줄 더 두 줄(재상 · 서기)인 띠 하나 — 칸 참조 · 출처 글 묶음 · 줄마다 빽빽한 칸 · 매단 속국 실의 sub(칸 그림 갈래 검토 고침).
  group('두 줄 — 칸 참조 · 출처 글 · 빽빽한 칸 · 매단 실', () {
    /// 줄 0(지도자 · 내각 · 직위 줄 더 2)에 띠 하나([from] ~ [to] px · 제 수 2): 지도자 [leaders]칸 · 내각 한 칸 · 재상 [lane0]칸 · 서기 [lane1]칸(고르게 · 순번은 줄마다 0부터 — 내보내기 strips.mjs).
    /// [borrows]는 구역 54(빌린 줄의 머리 글 — (칸 종류, 직위 줄 더의 줄, 출처 글)). [lines]는 띠의 제 수(sub 17 ~ 21) · [hang]이면 그림 영역 300 ~ 800에 매단 속국 꼬리표 하나(펼침) ·
    /// [plain]이면 오른쪽([to] + 20 ~ + 400)에 직위 줄 더가 없는 띠(지도자 · 내각 — look 30 없음) 하나 더.
    Future<(TimelineScene, TimelinePainter)> twoLines({double from = 100, double to = 1600, int leaders = 1, int lane0 = 1, int lane1 = 1, List<(int, int, String)> borrows = const [], int lines = 2, bool hang = false, bool office = true, bool plain = false}) async {
      PaintPick.office = office;
      final layout = SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '두 줄 견본', 'events': 0},
        ],
        'tracks': [
          {
            'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'office-d', 'dynasty': 0, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
            'rows': [{...row(0, office: 2), 'hang': hang ? 1 : 0, 'zones': hang ? 1 : 0}],
          },
        ],
        'epochs': <dynamic>[],
        'categories': <dynamic>[],
        'axis': <dynamic>[],
      })..reduceMotion = true;
      double x(int k, int n) => from + 50 + (to - from - 100) * k / n;
      var id = 10;
      final t = TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, at(from), at(to), '등불 성좌령', look: withOffice, sub: own(lines));
      if (plain) t.band(2, 0, at(to + 20), at(to + 400), '등불 교단', look: lead, color: 0xc8b193);
      // 칸은 (줄 · 종류 · 단 · 시작) 차례 — 둘째 띠의 칸은 그 종류의 끝에.
      for (int k = 0; k < leaders; k++) {
        t.cell(id++, 0, at(x(k, leaders)), at(x(k + 1, leaders)), '등좌 $k', kind: 1, style: st(k));
      }
      if (plain) t.cell(90, 0, at(to + 50), at(to + 350), '교주 하람', kind: 1, style: st(0));
      t.cell(id++, 0, at(x(0, 1)), at(x(1, 1)), '백등 내각', kind: 2, style: st(0));
      if (plain) t.cell(91, 0, at(to + 50), at(to + 350), '교단 내각', kind: 2, style: st(0));
      for (final (lane, n, word) in [(0, lane0, '재상'), (1, lane1, '서기')]) {
        for (int k = 0; k < n; k++) {
          t.cell(id++, 0, at(x(k, n)), at(x(k + 1, n)), '$word $k', kind: Schema4.cellOfficeMore, lane: lane, style: st(k));
        }
      }
      t
        ..item(Schema4.secOfficeName, 60, 0, at(from), at(to), ref: 1, name: '재상', b: 0)
        ..item(Schema4.secOfficeName, 61, 0, at(from), at(to), ref: 1, name: '서기', b: 1);
      for (final (k, (kind, lane, source)) in borrows.indexed) {
        t.item(Schema4.secBorrowHead, 70 + k, 0, at(from), at(to), ref: 1, name: source, a: kind, b: lane, text2: 'sample/seat');
      }
      if (hang) t.item(16, 501, 0, at(300), at(800), ref: 1, name: '갈대 공국', color: 0xb1a0c9, a: 0, b: 0, d: 9, text2: '속국:갈대');
      final tile = t.build();
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-at(100000), at(100000))
        ..setContentHeight(layout.totalHeight + 200);
      controller.showRange(0, at(1920 - SceneView.gutter));
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? tile : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      addTearDown(scene.dispose);
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      await settle(scene, painter);
      if (hang) {
        expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(0, true)), isTrue);
        await settle(scene, painter);
      }
      return (scene, painter);
    }

    test("칸 참조는 줄을 담는다('office:<줄>:<순번>') — 두 줄의 순번 0 칸이 따로 · 커서 비춤은 제 칸만", () async {
      final (scene, painter) = await twoLines();
      final geo = scene.layout.geo(0);
      final y0 = screenY(scene, 0, geo.officeTop) + 7, y1 = screenY(scene, 0, geo.officeTop + G.floor) + 7, mid = scene.controller.view.xOf(at(500));
      final hit = painter.strips.hitStrips;
      expect([hit(mid, y0)?.kind, hit(mid, y0)?.ref], [Schema4.cellOfficeMore, 'office:0:0'], reason: '재상 줄');
      expect([hit(mid, y1)?.kind, hit(mid, y1)?.ref], [Schema4.cellOfficeMore, 'office:1:0'], reason: '서기 줄 — 순번이 같아도 참조가 다르다');
      expect(hit(mid, screenY(scene, 0, geo.leaderTop) + 7)?.ref, 'leader:0', reason: '다른 종류는 그대로');
      final before = await pixelsOf(painter);
      SceneMarks.of(scene)
        ..hotCell = '1|office:0:0'
        ..version += 1;
      final after = await pixelsOf(painter);
      // 이름이 없는 자리(칸 왼쪽 몫 — 이름은 가운데)의 칠: 재상 칸만 올림 모습 · 서기 칸은 그대로.
      final left = scene.controller.view.xOf(at(170));
      expect(rgbAt(after, left, y0), isNot(rgbAt(before, left, y0)), reason: '올린 칸(재상 0)');
      expect(rgbAt(after, left, y1), rgbAt(before, left, y1), reason: '서기 0은 올림이 아니다');
    });

    test("머리 출처 글 — 출처 끝 '/직위'가 낱말과 같으면 떼고 같은 출처의 이웃 몫은 한 글 · 다른 출처는 따로 · 낱말과 다른 꼬리는 그대로", () async {
      String? borrowOf(TimelinePainter p) {
        final b = p.debugLabels.where((l) => l.kind == 'borrow').toList();
        return b.isEmpty ? null : b.single.text;
      }

      final (_, p1) = await twoLines(borrows: [(1, 0, '등불 성좌령'), (Schema4.cellOfficeMore, 0, '등불 성좌령/재상'), (Schema4.cellOfficeMore, 1, '모래 서원/서기')]);
      expect(borrowOf(p1), '· 지도자 · 재상 ← 등불 성좌령 · 서기 ← 모래 서원');
      // 내각 몫의 꼬리(내각)도 떼고 · 재상 줄은 출처 꼬리(서기)가 낱말과 달라 그대로 — 그래서 서기 줄(꼬리를 뗀 모래 서원)과 출처가 달라 따로.
      final (_, p2) = await twoLines(borrows: [(2, 0, '나루국/내각'), (Schema4.cellOfficeMore, 0, '모래 서원/서기'), (Schema4.cellOfficeMore, 1, '모래 서원/서기')]);
      expect(borrowOf(p2), '· 내각 ← 나루국 · 재상 ← 모래 서원/서기 · 서기 ← 모래 서원');
    });

    test('빽빽한 칸은 줄마다 — 재상 줄만 빽빽하면 그 줄만 한 칸 · 서기 줄 · 지도자 층은 낱칸 · 왼쪽 칸 줄 이름은 두 줄 모두', () async {
      // 띠 100 ~ 400 — 칸은 150 ~ 350(200px · 칸 상자 안 폭 298 — (298 − 6) ÷ 수 < 6이면 빽빽: 49칸부터). 재상 60칸 · 서기 3칸 · 지도자 2칸.
      final (scene, painter) = await twoLines(to: 400, leaders: 2, lane0: 60, lane1: 3);
      final geo = scene.layout.geo(0);
      final dense = [for (final v in painter.debugSink.notes['빽빽'] ?? const <Object>[]) '$v'];
      final l = scene.controller.view.xOf(at(100)) + 1, r = scene.controller.view.xOf(at(400)) - 1, top = screenY(scene, 0, geo.officeTop) + 1;
      expect(dense, ['1:9:0 ${(l * 10).round()},${(top * 10).round()},${((r - l) * 10).round()},130'], reason: '재상 줄(줄 0)만 · 띠 하나에 한 번');
      final cells = cellsOf(painter);
      expect(cells.where((c) => c.kind == Schema4.cellOfficeMore && c.lane == 0), isEmpty, reason: '재상 줄은 낱칸이 없다');
      expect(cells.where((c) => c.kind == Schema4.cellOfficeMore && c.lane == 1).length, 3, reason: '서기 줄은 낱칸');
      expect([for (final c in cells.where((c) => c.kind == Schema4.cellOfficeMore && c.lane == 1)) c.t], everyElement(screenY(scene, 0, geo.officeTop + G.floor) + 1));
      expect(cells.where((c) => c.kind == 1).length, 2, reason: '지도자 층은 그대로');
      expect(cells.where((c) => c.kind == 2).length, 1, reason: '내각 층은 그대로');
      expect(painter.strips.officeMarks.keys.toSet(), {0 * 32 + 0, 0 * 32 + 1}, reason: '빽빽한 줄도 왼쪽 칸 줄 이름 자리');
      expect([for (final m in painter.debugLabels.where((m) => m.kind == 'officeLabel')) m.text], unorderedEquals(['재상', '서기']));
    });

    test('매단 속국 실은 그 띠의 sub로 셈한 몸통 아랫변에서(paint/hangs.dart — 제 수 1 · 줄 2면 띠 아랫변 − 14 · sub를 모르면 − 28)', () async {
      final (scene, painter) = await twoLines(lane1: 0, lines: 1, hang: true);
      final px = await pixelsOf(painter);
      final geo = scene.layout.geo(0);
      expect(geo.hangLanes, 1);
      final bottom = TagLook.bodyBottom(geo, withOffice, oldStore: false, loose: false, sub: own(1));
      expect(bottom, geo.bandTop + geo.bandHeight - G.floor, reason: '제 수 1 — 남는 줄 하나만큼 올라선 몸통');
      expect(TagLook.bodyBottom(geo, withOffice, oldStore: false, loose: false, sub: 0), bottom - G.floor, reason: 'sub를 모르면(제 수 0) 14 더 위');
      // 실의 윗끝(띠가 덮어 화소로는 안 보임 — 기록 '매단실'): 그 띠 sub로 셈한 몸통 아랫변.
      final thread = noted(painter, '매단실');
      expect(thread.length, 1);
      expect(thread.single, endsWith(',${(screenY(scene, 0, bottom) * 10).round()}'));
      // 화소: 몸통 아랫변 밑(짧은 꼬리표 밖 — 바탕)에 실이 보인다.
      final x = int.parse(thread.single.split(' ')[1].split(',')[0]) / 10, below = screenY(scene, 0, bottom) + 4;
      expect(rgbAt(px, x, below), isNot(rgbAt(px, x + 5, below)), reason: '몸통 아랫변 밑의 실');
      // 스위치 office 끔: 층이 없어 sub를 보지 않는다(예전 셈 — 띠 아랫변).
      final (off, offPainter) = await twoLines(lane1: 0, lines: 1, hang: true, office: false);
      expect(off.layout.geo(0).officeLanes, 0);
      final g = off.layout.geo(0);
      expect(noted(offPainter, '매단실').single, endsWith(',${(screenY(off, 0, g.bandTop + g.bandHeight) * 10).round()}'));
    });

    test('몸통 층 사이 금은 한 번만 — look 30이 없는 띠는 맞붙이면 직위 줄 더 둘째 줄 윗변이 내각 윗선과 같은 y(전엔 같은 금을 두 번)', () async {
      final (scene, painter) = await twoLines(to: 1200, plain: true);
      final geo = scene.layout.geo(0);
      List<String> lines(int band) => [for (final n in noted(painter, '층금')) if (n.startsWith('$band ')) n];
      int y(double v) => (screenY(scene, 0, v) * 10).round();
      expect(lines(1), ['1 ${y(geo.cabinetTop)}', '1 ${y(geo.officeTop)}', '1 ${y(geo.officeTop + G.floor)}'], reason: '제 수 2 — 내각 · 직위 줄 더 두 줄의 윗선');
      expect(lines(2), ['2 ${y(geo.cabinetTop)}'], reason: '지도자 · 내각 띠 — 직위 줄 더 둘째 줄 윗변은 맞붙이면 내각 윗선이라 건너뜀(첫 줄 윗변은 몸통 아랫변)');
    });
  });
}
