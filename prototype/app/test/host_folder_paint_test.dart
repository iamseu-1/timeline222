import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/band_form.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/hit_test.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show LidLook, LidTags, TagEnd;
import 'package:archive_prototype/scene/paint/gutter.dart' show GutterHit, GutterHitKind, GutLook;
import 'package:archive_prototype/scene/paint/host_folders.dart';
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/links.dart' show LinkLayer;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/timeline_view.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 소속 폴더의 그림(리메이크 4단계 과제 8 걸음 2 · 스위치 folder — paint/host_folders.dart): 쌓기가 등록한 소속 폴더(uid `host:…`)를
// 대범위 층이 [ScopeIn] 꼴로 읽어 그릇 그림 그대로 그린다 — 깊이 0은 폴더(어깨 탭 라벨 '상국 이름 n'), 그릇 안의 상국은 상자.
// 가로는 상국 띠와 소속 줄 띠들의 양 끝(+ 8) · 같은 상국 줄의 다른 띠는 폴더 밖 · 색은 상국 띠 · 수는 구역 26(소속 펼치기 단추)의 a.
// 매다는 실 · 흠 ① 가로대 · 왼쪽 칸 폴더 줄이 따라오고, 오른쪽 클릭 세 상태 자리에는 들지 않는다.
// 걸음 3: 탭 · 뚜껑의 라벨과 왼쪽 칸 폴더 줄을 누르면 소속 펼치기 단추와 같은 맞히기(memberButton · 상국 띠) · 같은 소속 폴더 안의 소속선은 긋지 않음
// (매다는 실이 대신) · 포갠 소속은 상자(뚜껑 밑선 실 · 상자 너비 가로대).

const m = 1000000.0;
final ppm = 32 / bucketMinutes(9);
double px(double pixels) => pixels / ppm;

const hostColor = 0x8b6f47, memberColor = 0xacb4ca, scopeColor = 0xc0b4a3;

Map<String, dynamic> row(int id, {int kind = 0, int variant = 0}) => {
  'id': id, 'height': 80, 'band_top': 19, 'band_h': 61, 'dyn_top': -1, 'lead_top': -1,
  'cab_top': -1, 'text_top': 40, 'text_lines': 1, 'rail_top': -1, 'organ_top': -1,
  'kind': kind, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0,
  'cats': <int>[], 'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': variant,
};

Map<String, dynamic> vrow(int row, int after, {bool fresh = false, int pad = 0, bool start = false}) =>
    {'row': row, 'after': after, 'ord': 0, 'new': fresh ? 1 : 0, 'scope_pad': pad, 'group_start': start ? 1 : 0};

/// 줄 0 ~ 3 기본 · 4 · 5 소속 줄(상국 띠 7 — 줄 1의 소속 펼치기) · 6 포갠 소속 줄(소속 줄 5에 선 띠 12의 소속 펼치기 — 걸음 3) ·
/// [scope]면 그릇 s1(줄 1 · 3)도.
SceneLayout layoutOf({bool scope = false}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '소금 해안 기록', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '소금 해안', 'color': 0xa0bcc5,
      'rows': [row(0), row(1), row(2), row(3), row(4, kind: 1, variant: 1), row(5, kind: 1, variant: 1), row(6, kind: 1, variant: 3)],
    },
  ],
  'epochs': [],
  'variants': [
    {
      'id': 1, 'key': 'host:p/o-fed', 'kind': 1, 'track': 1, 'band': 7, 'uid': '', 'name': '철령 제후 연방',
      'rows': [vrow(4, 1, fresh: true), vrow(5, 4, fresh: true), vrow(2, 5)],
      'groups': <dynamic>[],
    },
    {
      'id': 3, 'key': 'host:p/o-abbey', 'kind': 1, 'track': 1, 'band': 12, 'uid': '', 'name': '흰돌 수도원령',
      'rows': [vrow(6, 5, fresh: true), vrow(2, 6)],
      'groups': <dynamic>[],
    },
    if (scope)
      {
        'id': 2, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '바위골 할거',
        'rows': [vrow(1, 0, pad: 16, start: true), vrow(3, 1), vrow(2, 3, pad: 6)],
        'groups': [
          {'key': '__scope:s1', 'depth': 0, 'name': '바위골 할거', 'color': scopeColor, 'kind': 2, 'rows': [1, 3]},
        ],
        'within': <int>[],
      },
  ],
})..reduceMotion = true;

/// 상국 띠 7(줄 1 · x 200 ~ 1500) · 같은 줄의 다른 띠 20(x 60 ~ 180 — 폴더 밖) · 소속 띠 11(줄 4 · 300 ~ 1100) · 12(줄 5 · 400 ~ 1600) ·
/// 줄 3의 띠 13 · 포갠 소속 띠 14(줄 6 · 700 ~ 1300 — 띠 12의 소속) · 구역 26(상국 띠 7 · 소속 2 · 띠 12 · 소속 1) · 띠마다 구멍 네모(구역 20) ·
/// 소속선(구역 22 — 아래로): 7 → 11 · 7 → 12 · 12 → 14는 소속 폴더 안, 7 → 13은 폴더 밖 줄(걸음 3).
/// [scope]면 그릇 s1의 구역 23(줄 1 ~ 3 · 40 ~ 1700 · 성격 [scopeLabel]). [forms]는 띠 번호 → form(과제 8 걸음 1 — 동군연합 상국 · 구성원 없는 나라 · 교단).
Uint8List tileOf({bool scope = false, Map<int, int> forms = const {}, String scopeLabel = '시대'}) {
  final t = TileBuilder(level: 9, x: 1, chunk: 0);
  final starts = <int, double>{};
  void band(int id, int r, double x0, double x1, String name, int color) {
    t.band(id, r, px(x0), px(x1), name, color: color, form: forms[id] ?? 0);
    t.item(LinkLayer.secSquare, 100 + id, r, px(x0), px(x1), ref: id, name: name, color: color);
    starts[id] = x0;
  }

  band(7, 1, 200, 1500, '철령 제후 연방', hostColor);
  band(20, 1, 60, 180, '외솔 나라', memberColor);
  band(11, 4, 300, 1100, '검은솔 대공국', memberColor);
  band(12, 5, 400, 1600, '흰돌 수도원령', memberColor);
  band(13, 3, 500, 900, '붉은재 군벌', memberColor);
  band(14, 6, 700, 1300, '솔뫼 백령', memberColor);
  t.item(ScopeMarks.secMemBtn, 300, 1, px(200), px(1500), ref: 7, color: hostColor, a: 2);
  t.item(ScopeMarks.secMemBtn, 301, 5, px(400), px(1600), ref: 12, color: memberColor, a: 1);
  var part = 400;
  for (final (host, hostRow, member, memberRow) in [(7, 1, 11, 4), (7, 1, 12, 5), (12, 5, 14, 6), (7, 1, 13, 3)]) {
    t.item(LinkLayer.secPart, part++, hostRow, px(starts[member]!), px(starts[member]! + 40), row2: memberRow, ref: member, b: host, a: 1, color: hostColor);
  }
  if (scope) t.item(ScopeLayer.secScope, 1, 1, px(40), px(1700), row2: 3, name: '바위골 할거', color: scopeColor, b: 2, text2: 's1\u001f$scopeLabel');
  return t.build();
}

/// 1920 × 1080 · 단계 9의 타일 하나(x 1)로 장면을 만든다. 보는 범위의 왼쪽 끝 = 타일 시작(그림판 x 240).
/// 이름 자리는 같은 isolate에서 곧바로 셈한다(화면 시험의 가짜 시계 아래에서도 답이 온다 — timeline_view_test와 같다).
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
    ask: (query) async {
      if (query['op'] == 'rows_near') {
        final all = [for (int r = 0; r < layout.rowCount; r++) r];
        return {'near': all, 'far': all};
      }
      return {};
    },
  );
  scene.hide.add('fade');
  scene.applyLayoutToView();
  showTile(scene);
  return scene;
}

/// 보는 범위를 타일 하나(x 1)의 시작부터 그림판 폭만큼으로.
void showTile(TimelineScene scene) {
  final origin = tileOrigin(9, 1).toDouble();
  scene.controller.showRange(origin, origin + (1920 - scene.layout.gutterWidth) / ppm);
}

(TimelineScene, TimelinePainter) make(SceneLayout layout, Uint8List tile) {
  final scene = sceneOf(layout, tile);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    paint(painter);
    await pumpEventQueue();
    scene.tick(16);
  }
  painter.debugSink.clear();
  paint(painter);
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
List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,~]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

/// 폴더 · 상자 기록('이름 상태 왼쪽,위,너비,높이') — 없으면 null.
List<double>? boxOf(TimelinePainter painter, String kind, String name) {
  for (final s in noted(painter, kind)) {
    if (s.startsWith('$name ')) return nums(s.substring(name.length));
  }
  return null;
}

/// 렌더 결과의 ARGB(rawRgba를 다시 짠다).
int argbAt(ByteData p, int x, int y) {
  final at = (y * 1920 + x) * 4;
  return p.getUint8(at + 3) << 24 | p.getUint8(at) << 16 | p.getUint8(at + 1) << 8 | p.getUint8(at + 2);
}

/// [nested]면 소속 줄 5의 띠 12도 펼친다(포갠 소속 — 소속 폴더 안의 소속 폴더 = 상자).
/// [lid]는 스위치 lid(그릴 때 읽으므로 다음 [opened]까지 그 값 — 찍기는 그 사이에).
Future<(TimelineScene, TimelinePainter)> opened(
    {bool scope = false, bool folder = true, bool nested = false, bool lid = true, Map<int, int> forms = const {}, String scopeLabel = '시대'}) async {
  PaintPick.folder = folder;
  final layout = layoutOf(scope: scope);
  PaintPick.reset();
  PaintPick.lid = lid;
  final (scene, painter) = make(layout, tileOf(scope: scope, forms: forms, scopeLabel: scopeLabel));
  addTearDown(scene.dispose);
  expect(layout.expandHost(7, true), isTrue);
  if (nested) expect(layout.expandHost(12, true), isTrue);
  if (scope) expect(layout.openScope('s1', true), isTrue);
  scene.controller.setContentHeight(layout.totalHeight);
  await settle(scene, painter);
  return (scene, painter);
}

/// 소속 펼치기 단추와 같은 맞히기인가.
void expectMember(Hit? hit, int band) {
  expect(hit, isNotNull);
  expect([hit!.kind, hit.bandId], [HitKind.memberButton, band]);
}

/// 왼쪽 칸에서 그 소속 폴더 줄의 누름 자리(배치 px — 폴더 그림 · 이름 줄의 가운데 · 그림 x + 30).
Offset gutterFolderSpot(TimelineScene scene, String uid) {
  final span = scene.layout.scopeSpanOf(uid)!;
  final depth = scene.layout.scopeDepthOf(uid);
  final cy = (scene.controller.view.yOf(span.top) + GutLook.boxMid).roundToDouble();
  return Offset(GutLook.boxX + depth * GutLook.step + 30, cy);
}

/// 왼쪽 칸 그 소속 폴더 줄의 맞히기(그리개가 적은 자리).
GutterHit gutterFolderHit(TimelineScene scene, TimelinePainter painter, String uid) {
  final at = gutterFolderSpot(scene, uid);
  final hit = painter.gutter.hitTest(at.dx, at.dy);
  expect(hit, isNotNull, reason: '왼쪽 칸 폴더 줄 $at');
  return hit!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);
  const uid = 'host:p/o-fed', name = '철령 제후 연방';

  test('펼친 상국은 폴더 — 가로 = 상국 · 소속 줄 띠의 양 끝 ± 8 · 세로 = 쌓기의 폴더 자리 · 라벨 "상국 이름 2"', () async {
    final (scene, painter) = await opened();
    final layout = scene.layout, v = scene.controller.view;
    final folder = boxOf(painter, '폴더', name);
    expect(folder, isNotNull, reason: noted(painter, '폴더').join(' | '));
    expect(noted(painter, '폴더').single, startsWith('$name open '));
    // 띠 시작 x = 240(그림판 왼쪽) + px. 같은 줄의 띠 20(60 ~ 180)은 폴더 밖이고 소속 띠 12가 상국보다 늦게 끝난다(1600).
    expect(folder![0], 240 + 200 - ScopeLook.padX);
    expect(folder[0] + folder[2], 240 + 1600 + ScopeLook.padX);
    final span = layout.scopeSpanOf(uid)!;
    expect([span.first, span.last], [1, 5]);
    expect(folder[1], v.yOf(span.top).roundToDouble());
    expect(folder[1] + folder[3], v.yOf(span.bottom).roundToDouble());
    // 어깨 탭: 몸통 왼쪽에서 · 라벨 종이는 어깨 7 + 2 뒤 · 몸통 윗변 위 2.
    final tab = nums(noted(painter, '폴더탭').single.substring(name.length));
    final body = folder[1] + G.folderTab;
    expect(tab[0], folder[0]);
    expect([tab[2], tab[3]], [folder[0] + FolderLook.shoulder + 2, body - 2 - FolderLook.labelH]);
    final labels = [for (final l in painter.debugLabels) if (l.kind == 'folder') l.text];
    expect(labels, [name, '2'], reason: '이름은 변형 이름 · 수는 구역 26의 소속 수');
    // 흠 ① 가로대: 소속 줄(둘째 줄부터)마다 폴더 너비 — 첫 줄(상국 줄)은 몸통 윗변에 매듭.
    expect([for (final s in noted(painter, '가로대')) nums(s).first.toInt()], [4, 5]);
    // 왼쪽 칸 폴더 줄도 따라온다.
    expect([for (final l in painter.debugLabels) if (l.kind == 'gutFolder') l.text], [name]);
  });

  test('픽셀: 몸통 왼쪽 테 = 상국 색 55%와 종이 · 라벨 종이는 흰 종이 + 1px 먹 40 — 스위치를 끄면 폴더 · 라벨 · 왼쪽 칸 줄이 없다', () async {
    final (_, painter) = await opened();
    final image = await render(painter);
    final folder = boxOf(painter, '폴더', name)!;
    final tab = nums(noted(painter, '폴더탭').single.substring(name.length));
    final left = folder[0].toInt(), body = (folder[1] + G.folderTab).toInt(), bottom = (folder[1] + folder[3]).toInt();
    final edge = mixOklab(0xff000000 | hostColor, Look.paper, FolderLook.edgePct);
    for (final y in [body + 12, (body + bottom) ~/ 2, bottom - 12]) {
      expect(argbAt(image, left, y), edge, reason: '몸통 왼쪽 테 y $y');
    }
    final lx = tab[2].toInt(), ly = tab[3].toInt();
    expect(argbAt(image, lx + 2, ly + 2), Look.paper, reason: '라벨 종이');
    expect(argbAt(image, lx, ly + 7), CanvasInk.gray(.4), reason: '라벨 왼쪽 테');
    expect(argbAt(image, lx + 7, ly), CanvasInk.gray(.4), reason: '라벨 윗변');

    final (_, off) = await opened(folder: false);
    expect(boxOf(off, '폴더', name), isNull);
    expect(noted(off, '폴더탭'), isEmpty);
    expect(noted(off, '가로대'), isEmpty);
    expect([for (final l in off.debugLabels) if (l.kind == 'folder' || l.kind == 'gutFolder') l.text], isEmpty);
  });

  test('누름(걸음 3): 탭 라벨 · 왼쪽 칸 폴더 줄 = 소속 펼치기 단추와 같은 맞히기(memberButton · 상국 띠 7) · 그릇 세 상태 자리에는 없다', () async {
    final (scene, painter) = await opened();
    final layout = scene.layout;
    final folder = boxOf(painter, '폴더', name)!;
    final tab = nums(noted(painter, '폴더탭').single.substring(name.length));
    final (lx, ly) = (tab[2] + 4, tab[3] + 4);
    expect(painter.scopes.hitFolder(lx, ly), isNull, reason: '그릇 세 상태(펼침 ↔ 접힘)의 누름이 아니다');
    expect(painter.scopes.hitHostFolder(lx, ly), uid);
    expectMember(HostFolders.pressOf(layout, uid), 7);
    expect(painter.scopes.scopeAt(folder[0] + 40, folder[1] + folder[3] - 4), isNull, reason: '세 상태 메뉴 없음');
    // 왼쪽 칸: 폴더 줄(그림 · 이름)은 GutterHitKind.folder · uid host:… — 화면이 같은 맞히기로 바꾼다.
    final g = gutterFolderHit(scene, painter, uid);
    expect([g.kind, g.uid], [GutterHitKind.folder, uid]);
    expectMember(HostFolders.pressOf(layout, g.uid), 7);
    // 그릇 uid · 꺼진 소속 펼치기에는 없다.
    expect(HostFolders.pressOf(layout, 's1'), isNull);
    expect(HostFolders.pressOf(layout, 'host:p/o-abbey'), isNull, reason: '띠 12의 소속 펼치기는 꺼져 있다');
    // 스위치를 끄면 소속 폴더가 없어 라벨 누름도 없다.
    final (_, off) = await opened(folder: false);
    expect(off.scopes.hitHostFolder(lx, ly), isNull);
  });

  testWidgets('화면 누름(걸음 3): 탭 라벨 · 왼쪽 칸 폴더 줄을 누르면 onHit에 memberButton(상국 띠 7) — 왼쪽 칸 맞히기(onGutterHit)로는 가지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 자리는 같은 장면을 따로 그린 그리개에서 잰다(화면의 그리개는 안에 숨어 있다).
    final probe = await tester.runAsync(() => opened());
    final tab = nums(noted(probe!.$2, '폴더탭').single.substring(name.length));
    final tabAt = Offset(tab[2] + 4, tab[3] + 4);
    final gutterAt = gutterFolderSpot(probe.$1, uid);
    final layout = layoutOf();
    final scene = sceneOf(layout, tileOf());
    addTearDown(scene.dispose);
    expect(layout.expandHost(7, true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    final hits = <Hit>[], gutter = <GutterHit>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, onHit: hits.add, onGutterHit: gutter.add))));
    showTile(scene);
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final state = tester.state<TimelineViewState>(find.byType(TimelineView));
    expectMember(state.hitAt(tabAt), 7);
    expect(state.gutterAt(gutterAt)?.uid, uid);
    for (final at in [tabAt, gutterAt]) {
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
    }
    expect(hits.length, 2, reason: hits.map((h) => '${h.kind} ${h.bandId}').join(' | '));
    for (final h in hits) {
      expectMember(h, 7);
    }
    expect(gutter, isEmpty, reason: '소속 폴더 줄은 앱 틀의 그릇 상태 길(GutterHitKind.folder)로 가지 않는다');
    await tester.pumpWidget(const SizedBox());
  });

  test('소속선(걸음 3): 같은 소속 폴더 안의 상국 → 소속은 긋지 않고 폴더 밖 줄은 긋는다 · 스위치를 끄면 예전(모두)', () async {
    final (_, on) = await opened();
    final (_, off) = await opened(folder: false);
    // 7 → 11 · 7 → 12는 폴더 안 · 7 → 13(줄 3)은 폴더 밖. 12 → 14는 띠 12를 펼치지 않아 줄 6이 없다.
    expect(noted(on, '소속선'), hasLength(1), reason: noted(on, '소속선').join(' | '));
    expect(noted(off, '소속선'), hasLength(3), reason: noted(off, '소속선').join(' | '));
    // 남은 하나는 폴더 밖 줄로 내려가는 선 — 끝(아래)이 폴더 아래에 있다.
    final folder = boxOf(on, '폴더', name)!;
    expect(nums(noted(on, '소속선').single)[2], greaterThan(folder[1] + folder[3]));
    // 포갠 소속(띠 12도 펼침): 12 → 14도 안쪽 폴더 안이라 없다 — 끄면 넷 모두.
    final (_, nestOn) = await opened(nested: true);
    final (_, nestOff) = await opened(nested: true, folder: false);
    expect(noted(nestOn, '소속선'), hasLength(1), reason: noted(nestOn, '소속선').join(' | '));
    expect(noted(nestOff, '소속선'), hasLength(4), reason: noted(nestOff, '소속선').join(' | '));
  });

  test('실(걸음 3): 첫 줄 상국 꼬리표의 실은 몸통 윗변에서 · 소속 줄은 가로대 매듭에서 내려온다', () async {
    final (_, painter) = await opened();
    final folder = boxOf(painter, '폴더', name)!;
    final body = folder[1] + G.folderTab;
    final threads = {for (final s in noted(painter, '매다는실')) nums(s)[0].toInt(): nums(s)};
    expect(threads.keys.toSet(), {7, 11, 12}, reason: noted(painter, '매다는실').join(' | '));
    expect(threads[7]![2], body + 1, reason: '상국(첫 줄)의 매듭은 몸통 윗변 바로 밑');
    final rails = {for (final s in noted(painter, '가로대')) nums(s)[0].toInt(): nums(s)};
    expect(threads[11]![2], rails[4]![2], reason: '소속 줄의 매듭은 그 줄의 가로대');
    expect(threads[12]![2], rails[5]![2]);
    // 끄면 폴더가 없어 실도 없다(구멍만).
    final (_, off) = await opened(folder: false);
    expect(noted(off, '매다는실'), isEmpty);
  });

  test('포갠 소속(걸음 3): 안쪽 소속 폴더는 상자 — 그 상국의 실은 뚜껑 밑선에서 · 그 소속 줄의 가로대는 상자 너비 · 라벨 누름은 그 상국', () async {
    final (scene, painter) = await opened(nested: true);
    final layout = scene.layout;
    const inner = 'host:p/o-abbey', innerName = '흰돌 수도원령';
    expect([layout.scopeDepthOf(uid), layout.scopeDepthOf(inner)], [0, 1]);
    final outer = boxOf(painter, '폴더', name)!, box = boxOf(painter, '상자', innerName);
    expect(box, isNotNull, reason: noted(painter, '상자').join(' | '));
    expect(outer[1] + outer[3], greaterThan(box![1] + box[3]), reason: '바깥 폴더가 상자를 품는다');
    expect([box[0], box[0] + box[2]], [240 + 400 - ScopeLook.padX, 240 + 1600 + ScopeLook.padX], reason: '상자 가로 = 띠 12 · 14의 양 끝');
    final threads = {for (final s in noted(painter, '매다는실')) nums(s)[0].toInt(): nums(s)};
    expect(threads[12]![2], box[1] + G.boxLid + 1, reason: '상자 첫 줄(띠 12)의 매듭은 뚜껑 밑선 바로 밑');
    expect(threads[12]![4], 1, reason: '가장 안쪽(상자)에 매달림');
    final rails = {for (final s in noted(painter, '가로대')) nums(s)[0].toInt(): nums(s)};
    // 상자는 안쪽 겹선이 없어 가로대가 테 바로 옆(1)부터 — 맞닿음(구분선 갈래 · 감독 결정 2026-10-25 · 꼴 off면 예전 3 — scopes_paint_test와 같음).
    expect(rails[6]![1], box[0] + 1, reason: '상자 안 줄의 가로대는 상자 너비(테 바로 옆부터)');
    expect(rails[4]![1], outer[0] + FolderLook.railInset, reason: '바깥 폴더 줄은 폴더 너비');
    expect(threads[14]![2], rails[6]![2]);
    // 상자 뚜껑의 라벨 → 띠 12의 소속 펼치기 · 바깥 폴더의 탭 → 띠 7.
    final labels = [for (final l in painter.debugLabels) if (l.kind == 'folder' && l.text == innerName) l];
    expect(labels, hasLength(1));
    final at = (labels.single.at.dx + 2, labels.single.at.dy + 4);
    expect(painter.scopes.hitHostFolder(at.$1, at.$2), inner);
    expectMember(HostFolders.pressOf(layout, inner), 12);
    final tab = nums(noted(painter, '폴더탭').single.substring(name.length));
    expect(painter.scopes.hitHostFolder(tab[2] + 4, tab[3] + 4), uid);
    // 왼쪽 칸: 바깥은 폴더 그림 · 안쪽은 상자 그림(한 단 들임) — 둘 다 소속 폴더 줄.
    expect([for (final l in painter.debugLabels) if (l.kind == 'gutFolder') l.text], [name, innerName]);
    expectMember(HostFolders.pressOf(layout, gutterFolderHit(scene, painter, inner).uid), 12);
  });

  test('그릇 안의 상국은 상자 — 뚜껑 라벨 "상국 이름 2" · 오른쪽 클릭은 바깥 그릇의 세 상태', () async {
    final (scene, painter) = await opened(scope: true);
    final layout = scene.layout, v = scene.controller.view;
    expect(layout.scopeDepthOf(uid), 1);
    expect(boxOf(painter, '폴더', name), isNull, reason: '깊이 1은 폴더가 아니라 상자');
    final box = boxOf(painter, '상자', name);
    expect(box, isNotNull, reason: noted(painter, '상자').join(' | '));
    final outer = boxOf(painter, '폴더', '바위골 할거')!;
    final span = layout.scopeSpanOf(uid)!;
    expect(box![1], v.yOf(span.top).roundToDouble());
    expect(box[1] + box[3], v.yOf(span.bottom).roundToDouble());
    expect(box[1] - outer[1], G.folderHead, reason: '상자 뚜껑은 폴더 머리 밑');
    expect(outer[1] + outer[3], greaterThan(box[1] + box[3]), reason: '그릇이 상자를 품는다');
    expect([box[0], box[0] + box[2]], [240 + 200 - ScopeLook.padX, 240 + 1600 + ScopeLook.padX]);
    expect([for (final l in painter.debugLabels) if (l.kind == 'folder') l.text], containsAll([name, '2', '바위골 할거']));
    // 오른쪽 클릭: 상자 안이어도 소속 폴더는 건너뛰고 바깥 그릇.
    expect(painter.scopes.scopeAt(box[0] + 40, box[1] + box[3] - 4)?.$1, 's1');
    // 소속 줄의 가로대는 상자 너비(가장 안쪽 그릇) — 그릇 줄 3은 폴더 너비.
    final rails = {for (final s in noted(painter, '가로대')) nums(s)[0].toInt(): nums(s)};
    expect(rails.keys.toList()..sort(), [3, 4, 5]);
    expect(rails[4]![1], box[0] + 1, reason: '상자는 테 바로 옆부터(맞닿음 — 구분선 갈래)');
    expect(rails[3]![1], outer[0] + FolderLook.railInset);
    // 왼쪽 칸: 그릇은 폴더 줄 · 소속 폴더는 상자 줄(한 단 들임).
    expect([for (final l in painter.debugLabels) if (l.kind == 'gutFolder') l.text], ['바위골 할거', name]);
  });

  // 과제 8 걸음 1(스위치 lid — paint/lid_tags.dart · host_folders.dart `inked`): 상국이 동군연합이면 그 소속 폴더는 먹(칠 먹 3.5 → 단계 4 · 테 먹 20 → 단계 25),
  // 폴더 첫 줄은 상국 띠의 제 꼬리표(구성원이 있어 뚜껑이 아님) · 다른 소속 줄이 그 앞에 끼지 않음 · 실 매듭은 몸통 윗변 — 동군연합 폴더에서도 같다.
  group('과제 8 걸음 1 — 동군연합 폴더 먹 · 첫 줄 제 꼬리표', () {
    final union = LidTags.typeUnion + 1, realm = LidTags.typeRealm + 1, faith = BandForm.types.indexOf('faith') + 1;
    // 상국 띠 7 = 동군연합 · 같은 줄 폴더 밖 띠 20 = 구성원 없는 나라(뚜껑) · 소속 띠 12 = 교단(제 꼬리표 — 둥근 끝).
    final forms = {7: union, 20: realm, 12: faith};

    Set<int> lidIds(TimelinePainter painter) => {for (final s in noted(painter, '뚜껑')) int.parse(s.split(' ').first)};

    /// 두 빛깔이 채널마다 1 안인가(먹 알파 칠은 그림판 바탕 위에 섞여 반올림이 갈린다).
    bool near(int a, int b) => [16, 8, 0].every((s) => (((a >> s) & 0xff) - ((b >> s) & 0xff)).abs() <= 1);

    /// 폴더 몸통 윗변 바로 밑 줄(테와 안쪽 겹선 사이 — 칠뿐)에서 가장 흔한 빛깔.
    int bodyFill(ByteData image, List<double> folder) {
      final y = folder[1] + G.folderTab + 1, count = <int, int>{};
      for (int x = folder[0].toInt() + 20; x < (folder[0] + folder[2]).toInt() - 20; x++) {
        final p = argbAt(image, x, y.toInt());
        count[p] = (count[p] ?? 0) + 1;
      }
      return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    }

    test('동군연합 상국의 소속 폴더는 먹 — 칠 먹 단계 4 · 테 25 · 끄면 상국 색 · 상국 띠는 구성원이 있어 뚜껑이 아니다', () async {
      final (_, on) = await opened(forms: forms);
      final image = await render(on);
      final folder = boxOf(on, '폴더', name)!;
      final left = folder[0].toInt(), body = (folder[1] + G.folderTab).toInt(), bottom = (folder[1] + folder[3]).toInt();
      for (final y in [body + 12, (body + bottom) ~/ 2, bottom - 12]) {
        expect(argbAt(image, left, y), CanvasInk.gray(LidLook.folderEdge), reason: '몸통 왼쪽 테 y $y');
      }
      expect(CanvasInk.gray(LidLook.folderEdge), CanvasInk.k25);
      final fill = bodyFill(image, folder);
      expect(near(fill, over(CanvasInk.alpha(LidLook.folderFill), Look.ground)), isTrue, reason: '몸통 칠 ${fill.toRadixString(16)}');
      expect(lidIds(on), {20}, reason: '폴더 밖 구성원 없는 나라만 뚜껑 · 동군연합 상국(구성원 있음)은 제 꼬리표');
      // 끄면 상국 색(색 9% 칠 · 55% 테).
      final (_, off) = await opened(forms: forms, lid: false);
      final was = await render(off);
      expect(boxOf(off, '폴더', name), folder, reason: '폴더 자리는 그대로');
      expect(argbAt(was, left, body + 12), mixOklab(0xff000000 | hostColor, Look.paper, FolderLook.edgePct));
      final old = bodyFill(was, folder);
      expect(near(old, over(withAlpha(0xff000000 | hostColor, FolderLook.fillPct), Look.ground)), isTrue, reason: '몸통 칠 ${old.toRadixString(16)}');
      expect(lidIds(off), isEmpty);
      // 동군연합이 아닌 상국은 켜도 상국 색(위 '픽셀' 시험과 같은 테).
      final (_, plain) = await opened();
      final third = await render(plain);
      expect(argbAt(third, left, body + 12), mixOklab(0xff000000 | hostColor, Look.paper, FolderLook.edgePct));
    });

    test('폴더 첫 줄은 상국 줄 — 다른 소속 줄이 앞에 끼지 않고 · 상국 띠가 맨 위 · 실 매듭은 몸통 윗변(동군연합 폴더도) · 교단은 제 꼬리표', () async {
      for (final f in [const <int, int>{}, forms]) {
        final (scene, painter) = await opened(forms: f);
        final layout = scene.layout;
        final rows = layout.scopeOnOf(uid)!.rows.toList()..sort((a, b) => layout.rowTop(a).compareTo(layout.rowTop(b)));
        expect([rows.first, layout.hostFolderRowOf(uid)], [1, 1], reason: '첫 줄 = 상국 줄 ($f)');
        final top7 = painter.debugBands.firstWhere((b) => b.id == 7).rect.top;
        for (final id in [11, 12]) {
          expect(painter.debugBands.firstWhere((b) => b.id == id).rect.top, greaterThan(top7), reason: '소속 띠 $id는 상국 띠 밑');
        }
        expect(lidIds(painter).contains(7), isFalse, reason: '상국 띠는 제 꼬리표');
        final folder = boxOf(painter, '폴더', name)!;
        final threads = {for (final s in noted(painter, '매다는실')) nums(s)[0].toInt(): nums(s)};
        expect(threads[7]![2], folder[1] + G.folderTab + 1, reason: '상국(첫 줄)의 매듭은 몸통 윗변 바로 밑 ($f)');
        if (f.isNotEmpty) {
          expect(painter.bands.endOf(12), TagEnd.key, reason: '교단은 제 꼬리표(둥근 끝)');
          expect(lidIds(painter).contains(12), isFalse);
        }
      }
    });

    // 걸음 4 검토 ①: 상국이 하나뿐인 소속(partOf member)을 가진 동맹 — 내보내기가 동맹에도 소속 펼치기 변형을 지어 쌓기가 소속 폴더를 둔다.
    // 닫힌 뚜껑이 열린 폴더의 머리가 되지 않게, 그 폴더가 펼쳐 있는 동안만 동맹 띠는 제 꼬리표 · 폴더는 상국(동맹) 색(먹은 동군연합만) — 지금 꼴을 못박는다.
    test('동맹 상국: 접힌 동안 뚜껑 · 소속 폴더를 펼치면 첫 줄의 제 꼬리표(폴더는 동맹 색) · 접으면 다시 뚜껑 · 폴더가 없으면(folder 끔) 펼쳐도 뚜껑', () async {
      final league = {7: LidTags.typeLeague + 1};
      final edge = mixOklab(0xff000000 | hostColor, Look.paper, FolderLook.edgePct);
      // 펼침: 소속 폴더가 서고 첫 줄은 동맹 띠의 제 꼬리표.
      final (scene, open) = await opened(forms: league);
      final layout = scene.layout;
      expect(LidTags.folderOpenOf(layout, 7), isTrue);
      expect(LidTags.isLid(layout, league[7]!, 7), isFalse);
      expect(lidIds(open), isEmpty, reason: noted(open, '뚜껑').join(' | '));
      final image = await render(open);
      final folder = boxOf(open, '폴더', name)!;
      final left = folder[0].toInt(), body = (folder[1] + G.folderTab).toInt();
      expect(argbAt(image, left, body + 12), edge, reason: '동맹 상국의 소속 폴더는 상국 색 테(먹이 아님)');
      // 접음: 같은 배치에서 보기만 바뀐다 — 폴더가 걷히고 동맹은 다시 뚜껑.
      expect(layout.expandHost(7, false), isTrue);
      scene.controller.setContentHeight(layout.totalHeight);
      await settle(scene, open);
      expect(boxOf(open, '폴더', name), isNull);
      expect(LidTags.folderOpenOf(layout, 7), isFalse);
      expect(lidIds(open), {7}, reason: noted(open, '뚜껑').join(' | '));
      // 스위치 folder를 끄면 펼쳐도 소속 폴더가 없어(예전 소속 펼치기 꼴) 뚜껑 그대로.
      final (flatScene, flat) = await opened(forms: league, folder: false);
      expect(boxOf(flat, '폴더', name), isNull);
      expect(LidTags.folderOpenOf(flatScene.layout, 7), isFalse);
      expect(lidIds(flat), {7});
      // 동맹이 아닌 상국의 판단은 그대로(구성원이 있으면 늘 제 꼬리표 — 펼침과 무관).
      expect(LidTags.isLid(layout, LidTags.typeUnion + 1, 7), isFalse);
    });

    // 걸음 4 검토 ②: 깊이 0 그릇의 성격(구역 23 label)이 동군연합이면 그 그릇 폴더도 먹(설계 4-1 · 4-6 #6 A — 형식 4 시대 객체의 label · nest-scene.f4의 합스부르크).
    test('성격이 동군연합인 그릇 폴더는 먹 — 칠 단계 4 · 테 25 · 끄면 그릇 색 · 성격이 시대면 그릇 색', () async {
      int fillAt(ByteData image, int x0, int y0, int y1) {
        // 폴더 왼쪽 테 · 안쪽 겹선 안쪽에서 첫 띠(그림판 x 300) 앞까지 — 가장 흔한 빛깔.
        final count = <int, int>{};
        for (int y = y0; y < y1; y++) {
          for (int x = x0 + 6; x < x0 + 24; x++) {
            final p = argbAt(image, x, y);
            count[p] = (count[p] ?? 0) + 1;
          }
        }
        return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      }

      const scopeName = '바위골 할거';
      final (_, on) = await opened(scope: true, scopeLabel: '동군연합');
      final image = await render(on);
      final folder = boxOf(on, '폴더', scopeName);
      expect(folder, isNotNull, reason: noted(on, '폴더').join(' | '));
      final left = folder![0].toInt(), body = (folder[1] + G.folderTab).toInt(), bottom = (folder[1] + folder[3]).toInt();
      for (final y in [body + 12, (body + bottom) ~/ 2, bottom - 12]) {
        expect(argbAt(image, left, y), CanvasInk.gray(LidLook.folderEdge), reason: '몸통 왼쪽 테 y $y');
      }
      final fill = fillAt(image, left, body + 4, bottom - 4);
      expect(near(fill, over(CanvasInk.alpha(LidLook.folderFill), Look.ground)), isTrue, reason: '몸통 칠 ${fill.toRadixString(16)}');
      final scopeEdge = mixOklab(0xff000000 | scopeColor, Look.paper, FolderLook.edgePct);
      // 끄면 그릇 색(9% 칠 · 55% 테) · 폴더 자리는 그대로.
      final (_, off) = await opened(scope: true, scopeLabel: '동군연합', lid: false);
      final was = await render(off);
      expect(boxOf(off, '폴더', scopeName), folder);
      expect(argbAt(was, left, body + 12), scopeEdge);
      final old = fillAt(was, left, body + 4, bottom - 4);
      expect(near(old, over(withAlpha(0xff000000 | scopeColor, FolderLook.fillPct), Look.ground)), isTrue, reason: '몸통 칠 ${old.toRadixString(16)}');
      // 성격이 시대(앞 시험들의 그릇)면 켜도 그릇 색 — 그 안의 소속 상자(깊이 1)는 성격과 무관.
      final (_, era) = await opened(scope: true);
      final third = await render(era);
      expect(argbAt(third, left, body + 12), scopeEdge);
    });
  });
}
