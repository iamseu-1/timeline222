import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/aux_calendar.dart';
import 'package:archive_prototype/scene/axis_model.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/axis.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/filter_state.dart';
import 'package:archive_prototype/ui/year_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

const cycle = YearCycle(names: ['샘물', '바람', '새벽'], start: -2, label: '세차', packId: 'sample-order');

SceneLayout _packs(List<String> keys) => SceneLayout.fromJson({
  'packs': [for (int i = 0; i < keys.length; i++) {'id': i + 1, 'key': keys[i], 'name': keys[i], 'events': 0}],
  'tracks': const [], 'epochs': const [], 'axis': const [],
});

class _CycleText extends ParagraphText {
  final measured = <TextLook>[], drawn = <TextLook>[];
  @override
  double? widthOf(String text, TextLook look) {
    if (text.startsWith('순환') && !text.contains(' ')) measured.add(look);
    return super.widthOf(text, look);
  }
  @override
  bool paint(ui.Canvas canvas, String text, TextLook look, double x, double y, {double alpha = 1}) {
    if (text.startsWith('순환000 ')) drawn.add(look);
    return super.paint(canvas, text, look, x, y, alpha: alpha);
  }
}

void main() {
  test('첫 해와 기원전 경계를 천문 연도로 셈하고 0년을 건너뛴다', () {
    expect([for (final y in [-3, -2, -1, 1, 2]) cycle.name(y)], ['새벽', '샘물', '바람', '새벽', '샘물']);
    expect(cycle.firstYears(-5, 5), [-5, -2, 2, 5]);
    expect(const YearCycle(off: true).name(4), '갑자');
    expect(YearCycle.fromMeta({}), isEmpty);
    expect(YearCycle.read({'names': ['하나'], 'start': 4}), isNull);
  });

  test('같은 범위에서도 순환과 글 폭이 바뀌면 눈금을 다시 셈한다 · 날로 확대해도 사용자 순환', () {
    final ruler = Ruler(), lo = minuteOfYear(80), hi = minuteOfYear(120);
    final old = ruler.compute(lo, hi, 30 / 525960);
    final custom = ruler.compute(lo, hi, 30 / 525960, cycle: cycle);
    expect(custom.ganjiMode, GanjiMode.cells);
    expect(custom.ganji.first.name, cycle.name(80));
    expect(custom.ganji.first.name, isNot(old.ganji.first.name));
    expect(ruler.compute(lo, hi, 30 / 525960, cycle: cycle, cycleNeed: 80).ganjiMode, GanjiMode.ticks);
    expect(ruler.compute(lo, hi, 10000 / 525960, cycle: cycle).ganjiMode, GanjiMode.cells);
    expect(ruler.compute(lo, hi, 30 / 525960).ganji.first.name, old.ganji.first.name);
    expect(axisTogglesFor(cycle).first.label, '세차');
    expect(axisTogglesFor(cycle).first.hint, contains('세차'));
    expect(axisTogglesFor(const YearCycle(off: true)).first.label, '간지');
  });

  test('이름 폭은 웹의 굵기 500 · 자간 0, 넓은 한 바퀴 눈금은 일반 글로 그린다', () async {
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(minuteOfYear(-3000), minuteOfYear(3000));
    final scene = TimelineScene(controller: controller, layout: _packs(['가상']), fetchTile: (l, x, c, p) async => TileBuilder(level: l, x: x, chunk: c).build());
    final text = _CycleText(), painter = TimelinePainter(scene, text: text);
    final cycle = YearCycle(names: [for (int i = 0; i < 240; i++) '순환${i.toString().padLeft(3, '0')}'], start: 4);
    // 리메이크 2부: 간지 줄은 처음에 끔(목업 날짜 칸은 연도 · 시대뿐) — 켠 날짜 칸에서 순환 눈금을 본다.
    final marks = SceneMarks.of(scene)
      ..yearCycle = cycle
      ..showGanji = true;
    marks.version++;
    controller.showRange(minuteOfYear(-1500), minuteOfYear(1500));
    try {
      for (int i = 0; i < 50; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1080));
        recorder.endRecording().dispose();
        if (!text.starved) break;
      }
      expect(text.measured, isNotEmpty);
      expect(text.measured.every((look) => look.weight == ui.FontWeight.w500 && look.spacing == 0), isTrue);
      expect(text.drawn, isNotEmpty, reason: '240해 순환은 넓은 보기에서도 첫 이름의 해를 그린다');
      expect(text.drawn.every((look) => look == AxisLook.ganjiTick), isTrue);
    } finally {
      // 날짜 칸 높이를 알리는 미룬 일을 끝낸 뒤 장면을 닫는다.
      await Future<void>.delayed(Duration.zero);
      scene.dispose(); controller.dispose(); text.dispose();
    }
  });

  test('DLC 교체 알림이 옛 기본 끔 후보를 처음 본 것으로 소비하지 않는다', () {
    final controller = TimelineController()..resize(1920, 1080);
    final scene = TimelineScene(controller: controller, layout: _packs(['A', 'B']), fetchTile: (l, x, c, p) async => TileBuilder(level: l, x: x, chunk: c).build());
    final bus = AppBus(controller: controller, scene: scene, ask: (_) async => {});
    // 리메이크 2부: 간지 줄의 기본값이 끔이라, 간지를 켜 둔 사람에게서 기본 끔이 한 번 적용되는지를 본다.
    bus.slot('filters').value = const FilterState(show: {'ganji': true});
    Map<String, dynamic> named(String id) => {'names': ['첫해', '다음해'], 'start': 1, 'packId': id};
    final glue = YearCycleGlue(bus, {'year_cycles': [named('A'), {'off': true, 'packId': 'B'}]})..start(ready: true);
    final shown = <bool>[];
    bus.slot('filters').addListener(() => shown.add((bus.slot('filters').value as FilterState).showing('ganji')));
    try {
      glue.replaceMeta({'year_cycles': [named('B')]}, applyLayout: () => scene.replaceLayout(_packs(['B'])));
      expect(SceneMarks.of(scene).yearCycle?.packId, 'B');
      expect(glue.cycleSeen, isEmpty);
      expect(shown, isEmpty, reason: '한 번의 교체 중간에 간지 줄이 잠시 꺼졌다 켜지지 않는다');
      glue.replaceMeta({'year_cycles': [{'off': true, 'packId': 'B'}]});
      expect(glue.cycleSeen, {'B'});
      expect(shown, [false], reason: 'B의 기본 끔을 실제로 처음 읽을 때 한 번 적용한다');
    } finally {
      glue.dispose(); bus.dispose(); scene.dispose(); controller.dispose();
    }
  });

  test('사용자가 미리 끈 간지는 기본 끔 DLC를 빼도 다시 켜지 않는다', () {
    final controller = TimelineController()..resize(1920, 1080);
    final scene = TimelineScene(controller: controller, layout: _packs(['A']), fetchTile: (l, x, c, p) async => TileBuilder(level: l, x: x, chunk: c).build());
    final bus = AppBus(controller: controller, scene: scene, ask: (_) async => {});
    bus.slot('filters').value = const FilterState(show: {'ganji': false});
    final glue = YearCycleGlue(bus, {'year_cycles': [{'off': true, 'packId': 'A'}]})..start(ready: true);
    try {
      expect(glue.cycleSeen, {'A'});
      expect(glue.cycleAutoOff, isFalse);
      scene.setPacks({});
      expect(SceneMarks.of(scene).yearCycle, isNull);
      expect((bus.slot('filters').value as FilterState).showing('ganji'), isFalse);
    } finally {
      glue.dispose(); bus.dispose(); scene.dispose(); controller.dispose();
    }
  });

  final dll = File('../engine/target/release/archive_engine.dll');
  final db = File('../data/d4-order-pc/archive.db');
  final ready = dll.existsSync() && db.existsSync();
  group('진짜 엔진 · sample-order 저장소', () {
    late ArchiveEngine engine;
    late SceneLayout layout;
    late Map<String, dynamic> meta;
    setUpAll(() async {
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      final info = await engine.start(db.absolute.path);
      meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      layout = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
    });
    tearDownAll(() async { await engine.call({'op': 'close'}); engine.close(); });

    test('내보낸 이름 목록 · 첫 해 · 줄 제목이 엔진을 거쳐 앱 눈금까지 같다', () async {
      final cycles = YearCycle.fromMeta(meta);
      expect(cycles, hasLength(1));
      expect(cycles.single.title, '세차');
      expect(cycles.single.start, 4);
      expect(cycles.single.names.first, '샘물');
      expect(cycles.single.packId, 'sample-order');
      // 리메이크 2부: 간지 줄은 처음에 끔 — 켜서 줄 제목을 본다.
      final axis = AxisModel(layout)
        ..setShown(ganji: true)
        ..setYearCycle(cycles.single);
      expect(axis.rows.singleWhere((r) => r.kind == AxisRowKind.ganji).corner, '세차');
      final tile = await engine.tile(9, tileOf(minuteOfYear(100), 9), 0, layout.enabledPacks);
      expect(tile.length, greaterThan(76));
      expect((await engine.call({'op': 'rows_near', 'near': [minuteOfYear(80), minuteOfYear(620)], 'fade': 0, 'packs': layout.enabledPacks}))['ok'], isNot(false));
    });

    test('시대 접기는 공통 줄까지 모든 시대 구분 줄을 한 줄로 묶고 글 · 높이 · 누름 · 기억을 되돌린다(감독 건의 2026-10-14 2번)', () {
      final axis = AxisModel(layout), before = AxisModel(layout);
      final epochs = axis.rows.where((r) => r.kind == AxisRowKind.epoch).toList();
      expect(epochs.where((r) => r.track != null), hasLength(2));
      // 맨 처음 시대 구분 줄만 이름 끝에 ▾, 어느 줄이든 왼쪽 이름이 접기 단추다.
      expect(epochs.first.arrow, AxisArrow.down);
      expect(epochs.skip(1).every((r) => r.arrow == AxisArrow.none), isTrue);
      for (final row in epochs) {
        expect(axis.hitTest(0, row.top + 5, 100, (x) => x).key, AxisModel.epochFold);
      }
      axis.toggleGroup(AxisModel.epochFold);
      expect(axis.rows.where((r) => r.kind == AxisRowKind.epoch), isEmpty);
      final folded = axis.rows.singleWhere((r) => r.groupKey == AxisModel.epochFold);
      expect(folded.corner, '시대 구분');
      expect(folded.mark, '${epochs.length}줄');
      expect(folded.members, hasLength(epochs.length));
      expect(folded.height, 22);
      expect(folded.top, epochs.first.top);
      expect(axis.hitTest(150, folded.top + 5, 100, (x) => x).key, AxisModel.epochFold);
      expect(axis.height, before.height - epochs.fold<double>(0, (v, r) => v + r.height) + 22);
      final restored = AxisModel(layout)..restoreState(axis.stateJson());
      expect(restored.open, contains('epochFold'));
      restored.toggleGroup(AxisModel.epochFold);
      expect(restored.height, before.height);
      expect(restored.rows.map((r) => (r.corner, r.top, r.height)), before.rows.map((r) => (r.corner, r.top, r.height)));
    });

    test('DLC 기본 끔은 한 번만 · 다시 켬과 재열기 기억 · 순환 후보를 끄면 다음 것', () async {
      final folder = Directory.systemTemp.createTempSync('d4-cycle-');
      final memory = await AppMemory.open(folder: folder, delay: const Duration(days: 1));
      AppMemory? reopened;
      final controller = TimelineController()..resize(1920, 1020);
      final scene = TimelineScene(controller: controller, layout: layout, fetchTile: (l, x, c, p) async => TileBuilder(level: l, x: x, chunk: c).build());
      final bus = AppBus(controller: controller, scene: scene, ask: (q) async => Map<String, dynamic>.from((await engine.call(q))['data'] as Map));
      // 리메이크 2부: 간지 줄의 기본값이 끔이라 간지를 켜 둔 사람에서 시작한다(기본 끔 적용 · 다시 켬을 보려고).
      bus.slot('filters').value = const FilterState(show: {'ganji': true});
      final off = {'off': true, 'packId': 'sample-order', 'packName': '가상 순환'};
      final glue = YearCycleGlue(bus, {'year_cycles': jsonEncode([off])})..start();
      try {
        glue.attachMemory(memory);
        expect((bus.slot('filters').value as FilterState).showing('ganji'), isFalse);
        expect(glue.cycleSeen, {'sample-order'});
        bus.slot('filters').value = const FilterState(show: {'ganji': true});
        glue.sync();
        expect((bus.slot('filters').value as FilterState).showing('ganji'), isTrue);
        await memory.flush();
        reopened = await AppMemory.open(folder: folder, delay: const Duration(days: 1));
        glue.attachMemory(reopened);
        expect((bus.slot('filters').value as FilterState).showing('ganji'), isTrue);
        glue.replaceMeta({'year_cycles': meta['year_cycles']});
        expect(SceneMarks.of(scene).yearCycle?.title, '세차');
        expect(reopened.parts[YearCycleGlue.slotName]?['cycleAutoOff'], isNull);
        expect(reopened.parts[YearCycleGlue.slotName]?['cycleSeen'], ['sample-order']);
        layout.enable({});
        glue.sync();
        expect(SceneMarks.of(scene).yearCycle, isNull);
        layout.enable({for (final p in layout.packs) p.id});
        glue.sync();
        expect(SceneMarks.of(scene).yearCycle?.title, '세차');
      } finally {
        glue.dispose(); bus.dispose(); scene.dispose(); controller.dispose();
        await memory.flush(); memory.dispose();
        if (reopened != null) { await reopened.flush(); reopened.dispose(); }
        folder.deleteSync(recursive: true);
      }
    });
  }, skip: ready ? false : 'engine-build와 sample-order 내보내기 → data/d4-order-pc 가져오기가 필요합니다');
}
