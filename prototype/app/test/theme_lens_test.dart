import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:archive_prototype/ui/theme_lens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 렌즈(주제 보기 — 10건 8 · 감독 선택 D5 결정 5 A · 6 B)의 새 앱 몫.
//   · 자료: 항목 기록 `themes`와 그 `x_lens`(내보내기 prototype/scripts/export/lens.mjs가 미리 푼 것)를 읽는 셈(LensBook)
//   · 배치: 렌즈를 켜면 x_lens.slot 트랙에 지도자 자리 — 줄 배치는 렌즈 종류와 상관없이 하나, 끄면 예전 그대로(SceneLayout.setThemeLens)
//   · 그리기: 칸 종류 8(공용 칸 단)을 지도자 칸 자리에, 남은 지도자 칸은 .4, 단체 칸의 색 점(paint/strips.dart)
//   · 고르기: 독의 '렌즈' 단추 · 차림표 · S · Shift+S · Esc 차례 · ⋯ 메뉴 한 줄 · 기억(ui/theme_lens.dart)
// 고정 자료 test/fixtures/lens-*.json은 lens-export-check.mjs --fixtures가 견본에서 뜬 것(손으로 고치지 않음). 이름은 모두 가상이다.

/// 고정 자료 하나(themes 기록의 json 글 · 트랙 열쇠 …).
Map<String, dynamic> fixture(String name) => (jsonDecode(File('test/fixtures/lens-$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

/// 엔진 `{"op":"entity","uid":"themes"}`의 답 꼴.
Map<String, dynamic> themesAnswer(String json) => {'uid': 'themes', 'kind': 'themes', 'json': json};

/// 손으로 지은 주제 사전 — DLC가 이름을 바꾼 주제 · 렌즈에서 숨긴 주제 · 더한 주제 · 사전 밖 이름(auto)으로 적힌 자료 없는 주제.
final customThemes = jsonEncode({
  'list': [
    {'id': 'system', 'name': '나라 짜임', 'color': '#abb3c9', 'order': 0},
    {'id': 'faction', 'name': '붕당', 'color': '#d4a39b', 'order': 1},
    {'id': 'guild', 'name': '길드 제도', 'color': '#c8b193', 'order': 8},
    {'id': 'stray', 'name': '떠돌이 주제', 'color': '', 'order': 9, 'auto': 1},
  ],
  'x_lens': {
    'slot': ['lens-b'],
    'themes': [
      {'id': 'system', 'hint': '나라의 짜임', 'has': 1, 'v': 1},
      {'id': 'faction', 'hint': '집권한 단체', 'has': 1, 'hidden': 1, 'v': 1},
      {'id': 'guild', 'hint': '경제', 'has': 0},
      {'id': 'stray', 'hint': '', 'has': 0},
    ],
  },
});

// ──────────────────────────────── 배치 · 그리기의 뼈대 ────────────────────────────────

/// 3판의 줄 하나(쌓는 값은 다시 셈하므로 최소만).
Map<String, dynamic> row(int id) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0,
};

/// 트랙 둘: 'lens-a'는 지도자 칸이 있고 'lens-b'는 없다. 변형은 렌즈 둘(`theme:<주제>` — kind 4 · 줄을 옮기지 않음).
Map<String, dynamic> skeleton() => {
  'packs': [
    {'id': 1, 'name': '렌즈 견본', 'events': 0},
  ],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'key': 'lens-a', 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 2, 'rows': [row(0)]},
    {'id': 2, 'pack': 1, 'ord': 1, 'name': '물결 갈래', 'color': 0xc8b193, 'key': 'lens-b', 'dynasty': 0, 'leader': 0, 'cabinet': 0, 'organ': 0, 'rail_levels': 2, 'rows': [row(1)]},
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
  'variants': [
    {'id': 1, 'key': 'theme:system', 'kind': 4, 'track': 0, 'band': 0, 'uid': 'system', 'name': '체제', 'rows': <dynamic>[], 'groups': <dynamic>[]},
    {'id': 2, 'key': 'theme:faction', 'kind': 4, 'track': 0, 'band': 0, 'uid': 'faction', 'name': '붕당', 'rows': <dynamic>[], 'groups': <dynamic>[]},
  ],
};

List<double> heights(SceneLayout l) => [l.geo(0).height, l.geo(1).height, l.totalHeight];

/// 단계 9에서 통 하나가 32px일 때의 1분 폭 — 자리는 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(strips_paint_test와 같은 셈).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// style 비트(계약 6-2 · 가-9): 27~29 단 갈래 · 15~26 순번 + 1 · 32 줄임이 탭으로 붙은 이름.
int lensStyle(int band, int seq, {bool tagged = false}) => (band << 27) | ((seq + 1) << 15) | (tagged ? 32 : 0);

/// 렌즈를 끈 타일: 띠 둘 · 'lens-a'의 지도자 칸 하나.
Uint8List offTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, at(100), at(1500), '해솔 왕국', color: 0xa0bcc5)
      ..band(2, 1, at(100), at(1500), '물결 공국', color: 0xc8b193)
      ..cell(10, 0, at(150), at(900), '해솔 첫 임금', kind: 1, style: (0 + 1) << 15))
    .build();

/// 렌즈 '체제'를 켠 타일(변형 theme:system): 'lens-a'는 그 주제 자료가 없어 지도자 칸이 남고, 'lens-b'에는 렌즈 칸(갈래 1 · 단 0).
Uint8List systemTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, at(100), at(1500), '해솔 왕국', color: 0xa0bcc5)
      ..band(2, 1, at(100), at(1500), '물결 공국', color: 0xc8b193)
      ..cell(10, 0, at(150), at(900), '해솔 첫 임금', kind: 1, style: (0 + 1) << 15)
      ..cell(20, 1, at(200), at(800), '의회 공국', kind: 8, lane: 0, style: lensStyle(1, 0), color: 0xabb3c9)
      ..item(43, 30, 1, at(200), at(800), a: 8, b: 0, c: 1, ref: 2, name: '의회 갈래', text2: 'lens/inst-council'))
    .build();

/// 렌즈 '붕당'을 켠 타일(변형 theme:faction): 'lens-b'에 연정 칸 하나(갈래 2 · 위아래 두 색 · 색 점 둘).
Uint8List factionTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, at(100), at(1500), '해솔 왕국', color: 0xa0bcc5)
      ..band(2, 1, at(100), at(1500), '물결 공국', color: 0xc8b193)
      ..cell(10, 0, at(150), at(900), '해솔 첫 임금', kind: 1, style: (0 + 1) << 15)
      ..cell(21, 1, at(200), at(1000), '동·서\t동쪽 무리 · 서쪽 무리', kind: 8, lane: 0, style: lensStyle(2, 0, tagged: true), color: 0xc0a0a0)
      ..item(43, 31, 1, at(200), at(1000), a: 8, b: 0, c: 1, ref: 2, color: 0xa0c0a0, text2: 'lens/gr-east\tc0a0a0,a0c0a0'))
    .build();

(TimelineScene, TimelinePainter) makeScene() {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..reduceMotion = true;
  controller.showRange(0, at(1920 - SceneView.gutter));
  late final TimelineScene scene;
  scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(skeleton()),
    fetchTile: (level, x, chunk, packs) async {
      if (level != 9 || x != 0 || chunk != 0) return TileBuilder(level: level, x: x, chunk: chunk).build();
      return switch (scene.layout.themeLens) {
        'system' => systemTile(),
        'faction' => factionTile(),
        _ => offTile(),
      };
    },
  );
  controller.setContentHeight(scene.layout.totalHeight);
  return (scene, TimelinePainter(scene)..debug = true);
}

Future<TimelinePainter> drawn(TimelineScene scene) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  final painter = TimelinePainter(scene)..debug = true;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
  return painter;
}

/// '종류:줄:단 l,t,w,h'(0.1px 단위) 기록 하나.
class Noted {
  Noted(String text)
    : kind = int.parse(text.split(' ')[0].split(':')[0]),
      row = int.parse(text.split(' ')[0].split(':')[1]),
      t = int.parse(text.split(' ')[1].split(',')[1]) / 10,
      w = int.parse(text.split(' ')[1].split(',')[2]) / 10,
      h = int.parse(text.split(' ')[1].split(',')[3]) / 10;
  final int kind, row;
  final double t, w, h;
}

List<Noted> cellsOf(TimelinePainter p) => [for (final v in p.debugSink.notes['칸'] ?? const <Object>[]) Noted(v as String)];
List<String> notes(TimelinePainter p, String kind) => [for (final v in p.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// 줄의 띠 윗변(화면 y).
double bandTopOf(TimelineScene s, int r) => s.controller.view.yOf(s.layout.rowTop(r) + s.layout.geo(r).bandTop);

/// 칸 밝기 기록('종류:줄:단 왼쪽,오른쪽' — 1000이 온 밝기)의 왼쪽 값.
int brightOf(TimelinePainter p, String head) => int.parse(notes(p, '칸밝기').firstWhere((s) => s.startsWith('$head ')).split(' ')[1].split(',')[0]);

// ──────────────────────────────── 고르기의 틀 ────────────────────────────────

/// 렌즈 부품이 쓰는 길: 항목 기록 themes와 `ids_of`(사건 uid → 번호 100, 101 …)에 답한다. [themes]가 null이면 옛 저장소(기록 없음).
AppBus lensBus({String? themes, List<Map<String, dynamic>>? asked}) {
  final controller = TimelineController()
    ..resize(1200, 800)
    ..setExtent(-at(100000), at(100000))
    ..reduceMotion = true;
  controller.showRange(0, at(1200 - SceneView.gutter));
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(skeleton()),
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  return AppBus(
    ask: (query) async {
      asked?.add(query);
      switch (query['op']) {
        case 'entity':
          if (query['uid'] == 'themes' && themes != null) return themesAnswer(themes);
          throw StateError('없는 항목');
        case 'ids_of':
          final uids = (query['uids'] as List).cast<String>();
          return {
            'bands': const <dynamic>[],
            'events': [for (int i = 0; i < uids.length; i++) {'uid': uids[i], 'id': 100 + i}],
          };
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
}

/// 단추 · 단축키를 띄운다(연표 자리는 초점만 잡는 빈 칸 — 단축키가 그 바깥 껍데기에 닿게).
Future<ThemeLensGlue> mountLens(WidgetTester tester, AppBus bus) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final glue = ThemeLensGlue(bus: bus)..start();
  addTearDown(glue.dispose);
  // 앱 틀(app_glue)처럼 Esc 명령이면 고른 것을 거둔다.
  bus.slot(slotCommand).addListener(() {
    final c = bus.slot(slotCommand).value;
    if (c is AppCommand && c.name == Cmd.close) bus.clearSelection();
  });
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: ShellKeys(
          bus: bus,
          child: Stack(
            children: [
              const Positioned.fill(child: Focus(autofocus: true, child: SizedBox.expand())),
              Positioned(left: 12, top: 10, child: LensDockButton(glue: glue)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return glue;
}

/// 차림표의 한 줄(이름으로 시작하는 글 — 한마디 · '자료 없음'이 같은 글 묶음에 붙는다).
Finder menuItem(String name) =>
    find.byWidgetPredicate((w) => w is RichText && RegExp('^${RegExp.escape(name)}(￼|\$)').hasMatch(w.text.toPlainText()));

String? lensOf(AppBus bus) => bus.slot(slotThemeLens).value as String?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('주제 사전 읽기', () {
    test('견본 lens: 내장 여덟 + DLC가 더한 주제 · 한마디 · 자료 있음 · 갈래 견본 · 사건 uid · 자리 트랙', () {
      final f = fixture('lens');
      final book = LensBook.read(themesAnswer(f['themes'] as String));
      expect([for (final t in book.menu) t.id], ['system', 'faction', 'law', 'election', 'ideology', 'military', 'tax', 'selection', 'guild']);
      expect(book.slot, {for (final t in f['tracks'] as List) (t as Map)['key']});
      final guild = book.byId('guild')!;
      expect(guild.name, '길드 제도');
      expect(guild.hint, '경제', reason: 'DLC 주제의 한마디는 x_lens에서');
      expect(guild.color, 0xffc8b193);
      final law = book.byId('law')!;
      expect(law.has && law.variant, isTrue);
      expect(law.swatchTitle, '법률의 갈래 — 같은 색은 나라 너머 같은 갈래');
      expect(law.swatches, [('두루 법전', 0xff000000 | 10793399)]);
      expect(law.events, ['sample-lens/ln-e-enact', 'sample-lens/ln-e-amend', 'sample-lens/ln-e-repeal']);
      expect(book.byId(''), isNull);
    });

    test('견본 groups: 자료 있는 주제가 붕당 하나면 앞뒤로 넘기기는 없음 ↔ 붕당만 돈다(자료 없는 주제는 건너뜀)', () {
      final book = LensBook.read(themesAnswer(fixture('groups')['themes'] as String));
      expect(book.menu.length, 8, reason: '자료 없는 주제도 차림표에는 남는다(자료 없음 딱지)');
      expect([for (final t in book.menu) if (!t.has) t.id], ['system', 'law', 'election', 'ideology', 'military', 'tax', 'selection']);
      expect(book.step('', 1), 'faction');
      expect(book.step('faction', 1), '');
      expect(book.step('', -1), 'faction');
      expect(book.step('law', 1), 'faction', reason: '돌지 않는 주제에서 넘기면 처음부터');
      expect(book.byId('faction')!.swatches.length, 4);
    });

    test('DLC가 이름을 바꾼 주제는 새 이름, 렌즈에서 숨긴 주제와 자료 없는 사전 밖 주제는 차림표에서 빠진다', () {
      final book = LensBook.read({'uid': 'themes', 'json': customThemes});
      expect([for (final t in book.menu) '${t.id}:${t.name}'], ['system:나라 짜임', 'guild:길드 제도']);
      expect(book.byId('faction'), isNull, reason: '숨긴 주제는 켤 수 없다');
      expect(book.byId('stray'), isNull);
      expect(book.themes.length, 4, reason: '사전 차례는 그대로 들고 있다');
      expect(book.byId('guild')!.has, isFalse);
      expect(book.step('', 1), 'system');
      expect(book.step('system', 1), '');
      expect(book.slot, {'lens-b'});
    });

    test('본문이 Map으로 와도 읽고, 읽지 못하면 빈 사전', () {
      expect(LensBook.read({'json': jsonDecode(customThemes)}).menu.length, 2);
      expect(LensBook.read({'json': '{깨진'}).themes, isEmpty);
      expect(LensBook.read(null).themes, isEmpty);
      expect(LensBook.read(const {'uid': 'themes'}).slot, isEmpty);
    });
  });

  group('배치', () {
    test('렌즈를 켜면 자리 트랙에만 지도자 자리(칸 층 +14)가 생기고 · 렌즈 종류를 바꿔도 같은 배치 · 끄면 예전 그대로', () {
      final layout = SceneLayout.fromJson(skeleton())..reduceMotion = true;
      final before = heights(layout);
      expect(layout.geo(1).leaderTop, -1, reason: "'lens-b'는 지도자 칸이 없다");
      expect(layout.variantKeys, isEmpty);

      expect(layout.setThemeLens('system', slots: {'lens-a', 'lens-b'}), isTrue);
      expect(layout.variantKeys, ['theme:system']);
      expect(layout.geo(0).height, before[0], reason: '지도자 칸이 있던 트랙은 줄 높이 그대로(칸만 바꿔 끼움)');
      expect(layout.geo(1).height, before[1] + G.leader, reason: '칸 층은 틈 없이 14씩 맞붙는다(두 장 꼬리표의 몸통 · G.floor)');
      expect(layout.geo(1).height, before[1] + 14);
      expect(layout.geo(1).leaderTop, layout.geo(0).leaderTop);
      final on = heights(layout);

      expect(layout.setThemeLens('faction'), isTrue);
      expect(layout.variantKeys, ['theme:faction']);
      expect(heights(layout), on, reason: '줄 배치는 렌즈 종류와 상관없이 하나');
      expect(layout.setThemeLens('faction'), isFalse);

      expect(layout.setThemeLens(''), isTrue);
      expect(heights(layout), before);
      expect(layout.variantKeys, isEmpty);
      expect(layout.geo(1).leaderTop, -1);
    });

    test("표시 '지도자'를 꺼도 렌즈를 켠 동안 자리 트랙에는 지도자 자리가 있다(웹 _layoutTrack)", () {
      final layout = SceneLayout.fromJson(skeleton())..reduceMotion = true;
      layout.setConditions(layout.conditions.copyWith(leaders: false));
      expect(layout.geo(0).leaderTop, -1);
      layout.setThemeLens('system', slots: {'lens-b'});
      expect(layout.geo(0).leaderTop, -1, reason: '자리 트랙이 아니면 지도자 자리가 없다');
      expect(layout.geo(1).leaderTop, greaterThanOrEqualTo(0));
    });

    test('끈 채로 자리 트랙만 바뀌면 다시 쌓지 않는다', () {
      final layout = SceneLayout.fromJson(skeleton())..reduceMotion = true;
      final stack = layout.stackVersion;
      expect(layout.setThemeLens('', slots: {'lens-b'}), isFalse);
      expect(layout.lensSlots, {'lens-b'});
      expect(layout.stackVersion, stack);
      expect(layout.setThemeLens('system'), isTrue, reason: '켤 때는 들고 있던 자리 트랙을 쓴다');
      expect(layout.geo(1).leaderTop, greaterThanOrEqualTo(0));
    });
  });

  group('그리기', () {
    test('렌즈를 끈 동안은 옛 그림 그대로 — 칸 종류 8이 없고 지도자 칸은 온 밝기', () async {
      final (scene, _) = makeScene();
      final p = await drawn(scene);
      expect(cellsOf(p).where((n) => n.kind == 8), isEmpty);
      expect(cellsOf(p).where((n) => n.kind == 1).length, 1);
      expect(brightOf(p, '1:0:0'), 1000);
    });

    test("렌즈 '체제': 렌즈 칸은 지도자 칸 자리(띠 윗변 + 14의 칸 층 — 윗선 아래 13)에, 그 주제 자료가 없는 나라의 지도자 칸은 .4", () async {
      final (scene, _) = makeScene();
      final off = await drawn(scene);
      final offBright = brightOf(off, '1:0:0');
      expect(scene.applyThemeLens('system', slots: {'lens-a', 'lens-b'}), isTrue);
      scene.controller.setContentHeight(scene.layout.totalHeight);
      final p = await drawn(scene);
      final lens = cellsOf(p).singleWhere((n) => n.kind == 8);
      final leader = cellsOf(p).singleWhere((n) => n.kind == 1);
      expect(lens.row, 1);
      // 두 장 꼬리표(리메이크 2부 · 감독 결정 '두 장 ㄴ'): 지도자 층 = 이름 색줄 14 바로 밑(몸통의 첫 층) = 띠 윗변 + 14 — 그 위의 칸 층이 없다.
      // 칸은 그 층의 윗선(1px — 색줄 아랫변의 테) 아래에 든다: 칸 위 = 14 + 1 · 높이 = 14 − 1(paint/strips.dart).
      expect(lens.t - bandTopOf(scene, 1), G.head + 1);
      expect(lens.t - bandTopOf(scene, 1), 14 + 1);
      expect(lens.h, G.leader - 1);
      expect(lens.h, 13);
      expect(leader.t - bandTopOf(scene, 0), 14 + 1, reason: '지도자 칸은 제자리');
      expect(brightOf(p, '1:0:0') / offBright, closeTo(.4, .002));
      expect(brightOf(p, '8:1:0'), offBright, reason: '렌즈 칸은 온 밝기');
      expect(p.debugLabels.where((l) => l.kind == 'cell').map((l) => l.text), contains('의회 공국'));
    });

    // 감독 고름 G5 #9 나(차례 걸음 14): 지위는 꼬리표 밑 흰 사슬 — 렌즈 '체제'를 지위 변천으로 대신한 나라(내보내기 lens.mjs L.src 'rank')의
    // 내린 지도자 칸(종류 8 단 1 · 갈래 4)은 지위 단 자리(paint/strips.dart _stripAt → RowGeo.strip(5))라 사슬 자리에 선다.
    test("렌즈 '체제'(지위로 대신): 지위 칸 꼴은 지도자 자리(몸통 첫 층) · 내린 지도자 칸(단 1)은 꼬리표 밑 지위 사슬 자리 — 스위치 chain을 끄면 몸통의 지위 층", () async {
      addTearDown(PaintPick.reset);
      for (final chain in [true, false]) {
        PaintPick.chain = chain;
        final json = skeleton();
        (((json['tracks'] as List)[1] as Map)['rows'] as List).first['rank'] = 1; // 'lens-b'의 줄에 지위 단
        final controller = TimelineController()
          ..resize(1920, 1080)
          ..setExtent(-at(100000), at(100000))
          ..reduceMotion = true;
        controller.showRange(0, at(1920 - SceneView.gutter));
        late final TimelineScene scene;
        scene = TimelineScene(
          controller: controller,
          layout: SceneLayout.fromJson(json),
          fetchTile: (level, x, chunk, packs) async {
            if (level != 9 || x != 0 || chunk != 0) return TileBuilder(level: level, x: x, chunk: chunk).build();
            if (scene.layout.themeLens != 'system') return offTile();
            return (TileBuilder(level: 9, x: 0, chunk: 0)
                  ..band(1, 0, at(100), at(1500), '해솔 왕국', color: 0xa0bcc5)
                  ..band(2, 1, at(100), at(1500), '물결 공국', color: 0xc8b193)
                  ..cell(10, 0, at(150), at(900), '해솔 첫 임금', kind: 1, style: (0 + 1) << 15)
                  // 갈래 3(지위로 대신한 체제 — 지위 칸 꼴 · 서열 1)을 지도자 자리(단 0)에, 갈래 4(내린 지도자 칸)를 지위 단 자리(단 1)에
                  ..cell(22, 1, at(200), at(800), '대공국', kind: 8, lane: 0, style: lensStyle(3, 0) | (2 << 8), color: 0xc8b193)
                  ..cell(23, 1, at(200), at(800), '물결 첫 공', kind: 8, lane: 1, style: lensStyle(4, 0), color: 0xc8b193))
                .build();
          },
        );
        expect(scene.applyThemeLens('system', slots: {'lens-b'}), isTrue);
        controller.setContentHeight(scene.layout.totalHeight);
        final p = await drawn(scene);
        final geo = scene.layout.geo(1), top = bandTopOf(scene, 1), bottom = top + geo.bandHeight;
        final asRank = cellsOf(p).singleWhere((n) => n.row == 1 && n.kind == 5), lowered = cellsOf(p).singleWhere((n) => n.row == 1 && n.kind == 1);
        if (chain) {
          expect(geo.chainKinds, [5]);
          expect(asRank.t - top, G.head + 1, reason: '지위 칸 꼴(단 0)은 지도자 자리 = 몸통 첫 층(지위 층이 몸통에 없다)');
          // 차례 걸음 15: 사슬 자리의 칸은 흰 사슬 꼴(종이 윗변부터 높이 14) — 왼쪽 칸의 사슬 이름은 '지도자'(chains_paint_test).
          expect(lowered.t - bottom, G.chainGap, reason: '내린 지도자 칸(단 1)은 띠 아랫변 밑 지위 사슬 자리');
          expect(lowered.h, G.chain);
          expect(p.strips.chainMarks.values.map((m) => m.label), contains('지도자'), reason: '지위 사슬 자리에 내린 지도자 칸 — 왼쪽 칸 이름도 지도자');
        } else {
          expect(geo.chainKinds, isEmpty);
          expect(lowered.t - top, G.head + 1, reason: '예전: 지위 층이 몸통 첫 층');
          expect(asRank.t - top, G.head + G.floor + 1, reason: '예전: 렌즈의 지도자 자리는 지위 층 밑');
        }
      }
    });

    test("렌즈 '붕당': 연정 칸은 색 점 둘(제 색 차례) — 렌즈를 끄면 다시 옛 그림", () async {
      final (scene, _) = makeScene();
      scene.applyThemeLens('faction', slots: {'lens-b'});
      scene.controller.setContentHeight(scene.layout.totalHeight);
      final p = await drawn(scene);
      final dots = notes(p, '색점');
      expect(dots.length, 2);
      expect([for (final d in dots) d.split(' ').last], ['c0a0a0', 'a0c0a0']);
      expect(dots.every((d) => d.startsWith('1 ')), isTrue, reason: "'lens-b'의 줄");

      scene.applyThemeLens('');
      scene.controller.setContentHeight(scene.layout.totalHeight);
      final back = await drawn(scene);
      expect(cellsOf(back).where((n) => n.kind == 8), isEmpty);
      expect(notes(back, '색점'), isEmpty);
      expect(brightOf(back, '1:0:0'), 1000);
    });
  });

  group('잇기(ThemeLensGlue)', () {
    test('켜면 장면 배치 · 사건 고리 색 · 그 주제의 사건 번호가 따라오고, 끄면 걷힌다', () async {
      final asked = <Map<String, dynamic>>[];
      final bus = lensBus(themes: fixture('lens')['themes'] as String, asked: asked);
      final glue = ThemeLensGlue(bus: bus)..start();
      await pumpEventQueue();
      expect(glue.book.menu.length, 9);
      glue.set('law');
      await pumpEventQueue();
      expect(bus.scene.layout.themeLens, 'law');
      expect(bus.scene.layout.lensSlots, {'sample-ln-a', 'sample-ln-b'});
      final marks = SceneMarks.of(bus.scene);
      expect(marks.lensColor, 0xbba395);
      expect(marks.lensEvents, {100, 101, 102});
      expect(asked.last['uids'], ['sample-lens/ln-e-enact', 'sample-lens/ln-e-amend', 'sample-lens/ln-e-repeal']);
      expect(glue.current!.name, '법률');

      // 저장소를 다시 지으면(DLC 더하기 · 빼기) 사건 번호가 바뀐다 — 켠 렌즈가 그대로여도 다시 묻는다
      final before = asked.where((q) => q['op'] == 'ids_of').length;
      marks.lensEvents = {1};
      await glue.load();
      await pumpEventQueue();
      expect(asked.where((q) => q['op'] == 'ids_of').length, before + 1);
      expect(marks.lensEvents, {100, 101, 102});
      expect(bus.scene.layout.themeLens, 'law');

      glue.set('ideology');
      await pumpEventQueue();
      expect(marks.lensEvents, isEmpty, reason: '사건이 없는 주제는 모든 사건이 옅다');

      glue.set('');
      await pumpEventQueue();
      expect(bus.scene.layout.themeLens, '');
      expect(glue.current, isNull);
      glue.dispose();
    });

    test('숨긴 주제 · 없는 주제를 켜려 하면 끈 채로 남는다', () async {
      final bus = lensBus(themes: customThemes);
      final glue = ThemeLensGlue(bus: bus)..start();
      await pumpEventQueue();
      glue.set('faction');
      await pumpEventQueue();
      expect(lensOf(bus), isNull);
      expect(bus.scene.layout.themeLens, '');
      glue.set('nothing');
      await pumpEventQueue();
      expect(lensOf(bus), isNull);
      glue.dispose();
    });

    test('주제 사전이 없는 옛 저장소: 내장 여덟이 자료 없음으로, 켜도 칸 변형이 없어 지도자 칸만 옅어진다', () async {
      final bus = lensBus();
      final glue = ThemeLensGlue(bus: bus)..start();
      await pumpEventQueue();
      expect([for (final t in glue.book.menu) t.name], ['체제', '붕당', '법률', '선거제도', '이념', '군사제도', '조세제도', '선발제도']);
      expect(glue.book.menu.every((t) => !t.has), isTrue);
      expect(glue.book.step('', 1), 'system', reason: '자료 있는 주제가 없으면 모두 돈다');
      glue.dispose();
    });

    test('기억: 기억해 둔 렌즈를 켜고, 바꾸면 적고, 끄면 지운다 · 숨은 주제를 기억하고 있었으면 끄고 지운다', () async {
      final folder = await Directory.systemTemp.createTemp('lens-memory');
      addTearDown(() => folder.delete(recursive: true));
      final memory = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
      // 뒤처리는 건 차례의 거꾸로 돈다 — 미뤄 둔 쓰기를 먼저 끝내야 Windows에서 쓰는 중인 파일의 폴더를 지우다 실패하지 않는다.
      addTearDown(memory.flush);
      memory.parts['themeLens'] = {'id': 'guild'};
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      final glue = ThemeLensGlue(bus: bus)..start();
      glue.attachMemory(memory);
      await pumpEventQueue();
      expect(bus.scene.layout.themeLens, 'guild');
      glue.set('tax');
      await pumpEventQueue();
      expect(memory.parts['themeLens'], {'id': 'tax'});
      glue.set('');
      await pumpEventQueue();
      expect(memory.parts.containsKey('themeLens'), isFalse);
      glue.dispose();

      final memory2 = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
      addTearDown(memory2.flush);
      memory2.parts['themeLens'] = {'id': 'faction'};
      final bus2 = lensBus(themes: customThemes);
      final glue2 = ThemeLensGlue(bus: bus2)..start();
      await pumpEventQueue();
      glue2.attachMemory(memory2);
      await pumpEventQueue();
      expect(lensOf(bus2), isNull, reason: 'DLC가 숨긴 주제');
      expect(memory2.parts.containsKey('themeLens'), isFalse);
      glue2.dispose();
    });
  });

  group('⋯ 메뉴 한 줄', () {
    test("'필터' 다음에 '렌즈'(S) — 켠 동안은 ✓(주제 이름은 렌즈 차림표에), 렌즈 부품이 없으면 줄이 없다", () {
      final bus = lensBus();
      final rows = buildMenuRows(bus: bus, flags: const MenuFlags(lensName: ''));
      final at = rows.indexWhere((r) => r.label == '필터');
      expect(rows[at + 1].label, '렌즈');
      expect(rows[at + 1].keyText, 'S');
      expect(rows[at + 1].checked, isFalse);
      final on = buildMenuRows(bus: bus, flags: const MenuFlags(lensName: '법률'));
      expect(on[at + 1].label, '렌즈');
      expect(on[at + 1].checked, isTrue);
      expect(buildMenuRows(bus: bus).any((r) => r.label == '렌즈'), isFalse);
      expect(buildMenuRows(bus: bus).length, rows.length - 1);
    });
  });

  group('단추 · 차림표 · 단축키', () {
    // 단추는 기호만(건의 8의 1번 꼴 A) — 이름은 풍선으로: 꺼져 있으면 '렌즈 (S)', 켠 동안 '렌즈 · 주제 (S)'. 차림표의 머리는 '렌즈' 한 낱말.
    Finder head() => find.descendant(of: find.byType(LensMenuCard), matching: find.text('렌즈'));

    testWidgets('단추를 누르면 아래에 차림표 — 없음 · 주제(한마디) · 앞뒤로 넘기기, 고르면 켜지고 단추의 풍선이 주제 이름이 된다', (tester) async {
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      final glue = await mountLens(tester, bus);
      expect(find.byTooltip('렌즈 (S)'), findsOneWidget);
      final button = tester.getRect(find.byKey(glue.buttonKey));
      await tester.tap(find.byKey(glue.buttonKey));
      await tester.pumpAndSettle();
      expect(head(), findsOneWidget);
      expect(menuItem('없음'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
      for (final name in ['체제', '붕당', '법률', '선거제도', '이념', '군사제도', '조세제도', '선발제도', '길드 제도']) {
        expect(menuItem(name), findsOneWidget, reason: name);
      }
      expect(menuItem('렌즈 앞뒤로 넘기기'), findsOneWidget);
      final card = tester.getRect(find.byType(LensMenuCard));
      expect(card.top, closeTo(button.bottom + 8, .01), reason: '단추 아래 8px');
      expect(card.left, closeTo(button.left, .01));
      expect(glue.menuOpen, isTrue);

      await tester.tap(menuItem('법률'));
      await tester.pumpAndSettle();
      expect(lensOf(bus), 'law');
      expect(bus.scene.layout.themeLens, 'law');
      expect(head(), findsNothing, reason: '고르면 닫힌다');
      expect(find.byTooltip('렌즈 · 법률 (S)'), findsOneWidget);
      expect(find.text('✕'), findsNothing, reason: '단추에는 끄기(✕)가 없다 — 차림표의 없음 · Esc로');
      expect(glue.menuOpen, isFalse);

      // 켠 동안 차림표에는 그 렌즈의 갈래 견본이 붙는다
      await tester.tap(find.byKey(glue.buttonKey));
      await tester.pumpAndSettle();
      expect(find.text('법률의 갈래 — 같은 색은 나라 너머 같은 갈래'), findsOneWidget);
      expect(find.text('두루 법전'), findsOneWidget);
      // 앞뒤로 넘기기는 차림표를 연 채로 넘긴다
      await tester.tap(menuItem('렌즈 앞뒤로 넘기기'));
      await tester.pumpAndSettle();
      expect(lensOf(bus), 'election');
      expect(head(), findsOneWidget);
      expect(find.text('법률의 갈래 — 같은 색은 나라 너머 같은 갈래'), findsNothing);
      // 바깥을 누르면 닫힌다
      await tester.tapAt(const Offset(900, 700));
      await tester.pumpAndSettle();
      expect(head(), findsNothing);
      expect(lensOf(bus), 'election');

      // 차림표의 '없음'으로 끈다
      await tester.tap(find.byKey(glue.buttonKey));
      await tester.pumpAndSettle();
      await tester.tap(menuItem('없음'));
      await tester.pumpAndSettle();
      expect(lensOf(bus), isNull);
      expect(find.byTooltip('렌즈 (S)'), findsOneWidget);
      expect(head(), findsNothing);
    });

    testWidgets("차림표의 '없음'는 끄고, Esc는 차림표만 닫는다", (tester) async {
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      final glue = await mountLens(tester, bus);
      glue.set('tax');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(glue.buttonKey));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(head(), findsNothing);
      expect(lensOf(bus), 'tax', reason: '같은 누름에 렌즈까지 끄지 않음');
      await tester.tap(find.byKey(glue.buttonKey));
      await tester.pumpAndSettle();
      await tester.tap(menuItem('없음'));
      await tester.pumpAndSettle();
      expect(lensOf(bus), isNull);
    });

    testWidgets('S는 다음 렌즈 · Shift+S는 앞 렌즈(없음 → 주제들 → 없음)', (tester) async {
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      await mountLens(tester, bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(lensOf(bus), 'system');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(lensOf(bus), 'faction');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(lensOf(bus), 'guild', reason: 'faction → system → 없음 → 끝의 guild');
      await tester.pumpAndSettle();
      expect(find.byTooltip('렌즈 · 길드 제도 (S)'), findsOneWidget);
    });

    testWidgets('Esc 차례: 상세 창 → 단체 계보 창 → 렌즈 → 집중 모드, 한 번에 하나씩', (tester) async {
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      final glue = await mountLens(tester, bus);
      glue.set('law');
      setZen(bus, true);
      bus.slot('groupTree').value = 'sample-groups/gr-kap';
      bus.select('sample-lens/ln-e-enact', kind: 'event');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.selection.value, isNull, reason: '첫 Esc는 상세 창');
      expect(bus.slot('groupTree').value, isNotNull);
      expect(lensOf(bus), 'law');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.slot('groupTree').value, isNull, reason: '둘째 Esc는 단체 계보 창');
      expect(lensOf(bus), 'law');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(lensOf(bus), isNull, reason: '셋째 Esc는 렌즈');
      expect(bus.scene.layout.themeLens, '');
      expect(zenOf(bus), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(zenOf(bus), isFalse, reason: '넷째 Esc는 집중 모드');
      await tester.pumpAndSettle();
    });

    testWidgets("⋯ 메뉴의 '렌즈'(명령 lensMenu)는 단추 아래에 차림표를 연다", (tester) async {
      final bus = lensBus(themes: fixture('lens')['themes'] as String);
      final glue = await mountLens(tester, bus);
      runCommand(bus, Cmd.lensMenu);
      await tester.pumpAndSettle();
      expect(find.byType(LensMenuCard), findsOneWidget);
      expect(glue.menuOpen, isTrue);
      runCommand(bus, Cmd.lensMenu);
      await tester.pumpAndSettle();
      expect(find.byType(LensMenuCard), findsOneWidget, reason: '이미 열려 있으면 하나만');
      await tester.tapAt(const Offset(900, 700));
      await tester.pumpAndSettle();
      expect(glue.menuOpen, isFalse);
    });
  });
}
