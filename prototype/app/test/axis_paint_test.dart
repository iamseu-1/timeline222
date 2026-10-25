import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/aux_calendar.dart';
import 'package:archive_prototype/scene/axis_model.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/layout.dart';
// `Look`이라는 이름이 paint/look.dart에도 있어 앞가지를 붙여 쓴다.
import 'package:archive_prototype/scene/emphasis.dart' as emph;
import 'package:archive_prototype/scene/paint/axis.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aux_calendar_test.dart' show lunarSlice;
import 'axis_model_test.dart' show cell, layoutOf;
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 날짜 칸과 몸통 바탕 눈금의 그리기. 연도 · 시대 줄은 리메이크 2부의 목업(서고 dateHeader) 값이다:
// 연도 눈금 글은 눈금 오른쪽 4px에 왼쪽 맞춤 · 줄 위에서 12.5가 가운데, 연도 · 시대 줄의 모서리 글은 오른쪽에서 12px 안쪽.
// 그 밖의 줄(간지 · 묶음 · 보조 달력)은 기준 덤프(results/dom/*.json)의 값 그대로다 — 모서리 글은 오른쪽에서 10px 안쪽.
// 간지 · 연호 · 도읍 줄은 처음에 꺼져 있다 — 그 줄을 보는 검사는 [showAllRows]로 켠다.

const _width = 1920.0, _height = 1080.0;

/// 해 [from]~[to]가 보이는 1920×1080 장면.
(TimelineScene, TimelinePainter) make(List<List<Object>> axis, {double from = 240, double to = 340, int tracks = 2}) {
  final layout = layoutOf(axis, tracks: tracks);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(_width, _height)
    ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
    ..setContentHeight(layout.totalHeight);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
  controller.showRange(minuteOfYear(from), minuteOfYear(to));
  return (scene, painter);
}

/// 글줄 준비의 예산이 장면마다 정해져 있으니, 못 그린 이름이 없을 때까지 되풀이해 그린다.
void paint(TimelinePainter painter) {
  for (int i = 0; i < 50; i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), const ui.Size(_width, _height));
    recorder.endRecording().dispose();
    if (!painter.text.starved) return;
  }
}

List<DebugLabel> of(TimelinePainter painter, String kind) => [for (final l in painter.debugLabels) if (l.kind == kind) l];

/// 처음에 꺼진 간지 · 연호 · 도읍 줄(리메이크 2부 — 목업 날짜 칸은 연도 · 시대뿐)을 켠다.
/// 기억을 되살리듯 곧바로 선다(흐름도 미룬 알림도 없이 — 보기의 날짜 칸 높이가 바로 따라온다).
void showAllRows(TimelinePainter painter) => painter.axis.restoreState(const {'show': {'ganji': true, 'eras': true, 'capitals': true}});

void main() {
  test('날짜 칸의 높이를 보기에 알린다 — 몸통은 그 아래에서 시작한다', () {
    final (scene, painter) = make([
      cell(1, 0, 0, 100, 400, '공통 시대'),
      for (int t = 1; t <= 12; t++) ...[
        cell(1, t, 0, 100, 400, '$t번 시대'),
        cell(2, t, 0, 100, 400, '$t번 연호', strip: t),
        cell(3, t, 0, 100, 400, '$t번 도읍', strip: 100 + t),
      ],
    ], tracks: 12);
    // 처음(연도 · 시대): 1 + 24 + 공통 시대 20 + 보조 달력 1 + 나라 시대 20 × 12 + 1.
    expect(scene.axisHeight, 287);
    expect(scene.controller.view.head, 287);
    paint(painter);
    expect(painter.axis.model!.rows.length, 15, reason: '연도 · 공통 시대 · 나라 시대 12에 접힌 보조 달력 줄 하나가 더 있다');
    // 간지 · 연호 · 도읍을 켜면 날짜 칸이 그만큼 높아지고 몸통도 따라 내려간다.
    showAllRows(painter);
    expect(scene.axisHeight, 287 + AxisModel.ganjiHeight + 2 * AxisModel.groupHeight);
    expect(scene.controller.view.head, scene.axisHeight);
    expect(painter.axis.model!.rows.length, 18);
  });

  test('날짜 칸 높이는 move 스프링으로 흐르고, 그리는 도중에는 보기에 알리지 않는다', () async {
    final (scene, painter) = make([
      for (int t = 1; t <= 3; t++) cell(2, t, 0, 240, 340, '$t번 연호', strip: t),
    ], tracks: 3);
    showAllRows(painter); // 연호 줄은 처음에 꺼져 있다
    scene.controller.reduceMotion = false;
    final before = painter.axis.targetHeight;
    painter.axis.toggleGroup('eras');
    expect(painter.axis.targetHeight, greaterThan(before));
    expect(painter.axis.shownHeight, before, reason: '흐름은 지금 값에서 시작한다');
    expect(painter.axis.flowing, isTrue);
    // 한 장면을 그려도 보기에 알리는 일은 마이크로태스크로 미룬다(그리는 도중의 알림은 화면 틀이 막는다).
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), const ui.Size(_width, _height));
    recorder.endRecording().dispose();
    expect(painter.axis.shownHeight, greaterThanOrEqualTo(before));
    expect(painter.axis.shownHeight, lessThan(painter.axis.targetHeight));
    // 실제 장면처럼 16ms마다 갱신하며 move의 400ms 구간을 보낸다.
    for (int i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final frame = ui.PictureRecorder();
      painter.paint(ui.Canvas(frame), const ui.Size(_width, _height));
      frame.endRecording().dispose();
    }
    expect(painter.axis.flowing, isFalse);
    expect(painter.axis.shownHeight, painter.axis.targetHeight);
    await Future<void>.delayed(Duration.zero);
    expect(scene.controller.view.head, painter.axis.targetHeight);
  });

  test('연도 눈금 글은 눈금 오른쪽 4px에 왼쪽 맞춤이고 줄 위에서 12.5가 가운데다 — 오른쪽 끝을 넘는 글은 숨는다(목업 서고)', () {
    final (scene, painter) = make([]);
    paint(painter);
    final ticks = of(painter, 'axis-tick');
    // 340년의 눈금은 그림 영역 오른쪽 끝(1920)에 서서 글이 들 자리가 없다.
    expect(ticks.map((l) => l.text).toList(), ['240', '250', '260', '270', '280', '290', '300', '310', '320', '330']);
    final v = scene.controller.view;
    for (final l in ticks) {
      expect(l.at.dx, closeTo(v.xOf(minuteOfYear(double.parse(l.text))) + AxisLook.mockTickX, .01), reason: '${l.text}이 눈금 오른쪽 4px에서 시작');
      expect(l.at.dy, closeTo(1 + AxisLook.mockMid - AxisLook.mockTick.size * .6, .01));
    }
  });

  test("모서리 글 — 연도 · 시대 줄은 오른쪽에서 12px 안쪽(목업 서고 'N년 보기' · '시대'), 간지 줄은 10px 안쪽", () {
    final (scene, painter) = make([cell(1, 0, 0, 100, 400, '공통 시대')]);
    paint(painter);
    expect(of(painter, 'axis-corner').map((l) => l.text).toList(), ['100년 보기', '시대'], reason: '간지 줄은 처음에 꺼져 있다');
    showAllRows(painter);
    paint(painter);
    final corners = of(painter, 'axis-corner');
    expect(corners.map((l) => l.text).toList(), ['100년 보기', '시대', '간지']);
    final left = scene.controller.view.left;
    expect(corners[0].at.dx + painter.text.widthOf('100년 보기', AxisLook.mockSpan)!, closeTo(left - AxisLook.mockRight, .01));
    expect(corners[1].at.dx + painter.text.widthOf('시대', AxisLook.mockCorner)!, closeTo(left - AxisLook.mockRight, .01));
    expect(corners[2].at.dx + painter.text.widthOf('간지', AxisLook.corner)!, closeTo(left - 10, .01));
    // 세로: 연도 줄은 줄 위(1)에서 12.5 · 시대 줄은 첫 이름 종이(알맹이 26 + 2 ~ + 15)의 가운데 · 간지 줄은 알맹이(46~65)의 가운데.
    expect(corners[0].at.dy, closeTo(1 + 12.5 - 10 * .6, .01));
    expect(corners[1].at.dy, closeTo(26 + 2 + 7.5 - 10 * .6, .01));
    expect(corners[2].at.dy, closeTo(55.5 - 10.5 * .6, .01));
  });

  test('시대 구분 칸(흰 이름 종이): 이름이 다 들면 온 이름, 좁으면 첫 글자, 더 좁으면 없음(목업 서고 labelEra)', () {
    // 1년이 16.8px — 100년 칸은 1,680px, 3년 칸은 50px(글 들 폭 50 − 12 = 38), 1년 칸은 16.8px(글 들 폭 4.8).
    final (scene, painter) = make([
      cell(1, 0, 0, 240, 340, '넓은 시대'),
      cell(1, 0, 1, 240, 243, '좁은 시대'),
      cell(1, 0, 2, 240, 241, '아주 좁은 시대'),
    ]);
    paint(painter);
    final names = of(painter, 'axis-epoch');
    expect(names.map((l) => l.text).toList(), ['넓은 시대', '좁']);
    // 이름은 종이 왼쪽 6에서 시작하고, 단은 17마다(첫 종이는 줄 알맹이 26 + 2 = 28 ~ 43).
    final v = scene.controller.view;
    expect(names[0].at.dx, closeTo(v.xOf(minuteOfYear(240)).roundToDouble() + AxisLook.epochText, .01));
    expect(names[0].at.dy, closeTo((28 + 43) / 2 - .5 - 9.5 * .6, .01));
    expect(names[1].at.dy - names[0].at.dy, closeTo(AxisModel.epochHeight, 1e-9));
  });

  test('간지: 해마다면 이어진 칸, 몇 해마다면 눈금, 넓으면 안내 글', () {
    final (_, painter) = make([], from: 240, to: 340);
    expect(painter.axis.model!.showGanji, isFalse, reason: '간지 줄은 처음에 꺼져 있다(리메이크 2부)');
    showAllRows(painter);
    paint(painter);
    // 100년/1,680px — 해마다 16.8px이라 두 해마다 눈금이다.
    expect(of(painter, 'axis-ganji').length, greaterThan(20));
    expect(of(painter, 'axis-ganji').map((l) => l.text).take(3).toList(), ['경신', '임술', '갑자']);

    final (_, wide) = make([], from: -1500, to: 1500);
    showAllRows(wide);
    paint(wide);
    expect(of(wide, 'axis-ganji').map((l) => l.text).toList(), ['확대하면 간지가 보입니다']);
  });

  test('접힌 묶음의 가는 막대는 나라 넷까지 · 높이 3 · 한 줄 걸러 4px', () {
    final (scene, painter) = make([
      for (int t = 1; t <= 6; t++) cell(2, t, 0, 100, 400, '$t번 연호', strip: t),
    ], tracks: 6);
    showAllRows(painter);
    paint(painter);
    final group = painter.axis.model!.rows.firstWhere((r) => r.kind == AxisRowKind.group);
    expect(group.members.length, 6);
    // n = 4이므로 막대 높이 3 · 첫 막대는 줄 알맹이에서 3.5px 아래(기준 덤프의 428.5 = 425 + 3.5).
    final bh = 3.0, top0 = (AxisModel.groupHeight - (4 * (bh + 1) - 1)) / 2;
    expect(top0, 3.5);
    expect(group.contentTop + top0, group.top + 4.5);
    expect(scene.controller.view.head, group.top + group.height + 1);
  });

  test('묶음을 열면 나라별 연호 · 도읍 칸과 배도 갈래를 그린다', () {
    final (scene, painter) = make([
      cell(2, 1, 0, 240, 290, '첫 연호', strip: 1),
      cell(2, 1, 0, 290, 340, '둘째 연호', strip: 1),
      cell(3, 1, 0, 240, 300, '첫 도읍', strip: 2),
      cell(3, 1, 0, 300, 340, '옮긴 도읍', strip: 2, style: 4), // 임시 도읍(점선 칸)
      cell(4, 1, 0, 250, 330, '두 배도', strip: 3),
    ], tracks: 1);
    final model = painter.axis.model!;
    showAllRows(painter);
    painter.axis.toggleGroup('eras');
    painter.axis.toggleGroup('capitals');
    painter.axis.toggleCapSec(1);
    expect(scene.controller.view.head, model.height);
    paint(painter);
    final names = of(painter, 'axis-cell').map((l) => l.text).toList();
    expect(names, containsAll(['첫 연호', '둘째 연호', '첫 도읍', '옮긴 도읍', '두 배도']));
    // 같은 무리(strip)로 이어 붙은 두 칸의 이름은 저마다 제 칸 안에 온다.
    final v = scene.controller.view;
    final era = of(painter, 'axis-cell').firstWhere((l) => l.text == '첫 연호');
    final next = of(painter, 'axis-cell').firstWhere((l) => l.text == '둘째 연호');
    expect(era.at.dx, greaterThan(v.xOf(minuteOfYear(240))));
    expect(era.at.dx, lessThan(v.xOf(minuteOfYear(290))));
    expect(next.at.dx, greaterThan(v.xOf(minuteOfYear(290))));
    // 연호 줄과 도읍 줄은 각자의 줄 안에서 그려진다.
    final capRow = model.rows.firstWhere((r) => r.kind == AxisRowKind.cap);
    expect(of(painter, 'axis-cell').firstWhere((l) => l.text == '두 배도').at.dy, greaterThan(capRow.contentTop + capRow.lanes * AxisModel.capHeight));
  });

  test('몸통의 바탕 눈금은 연도 눈금과 같은 자리에 선다', () {
    final (_, painter) = make([]);
    paint(painter);
    expect(painter.debugGridLines, 11, reason: '보이는 눈금마다 하나 — 바탕 띠만 까는 보기 밖의 눈금은 세지 않는다');
  });

  test('일진: 하루가 26px을 넘으면 날마다의 간지가 칸으로 나온다', () {
    // 하루가 26px을 넘으려면 보기 폭이 1,680 / 26 / 365.25 = 0.177해보다 좁아야 한다.
    final (_, painter) = make([], from: 300, to: 300.1);
    showAllRows(painter);
    paint(painter);
    final names = of(painter, 'axis-ganji').map((l) => l.text).toList();
    expect(names.length, greaterThan(20));
    // 이름은 모두 두 글자의 간지이고, 이웃한 날은 천간 · 지지가 한 칸씩 나아간다.
    const stems = '갑을병정무기경신임계', branches = '자축인묘진사오미신유술해';
    for (final n in names) {
      expect(n.length, 2);
      expect(stems.contains(n[0]), isTrue);
      expect(branches.contains(n[1]), isTrue);
    }
    for (int i = 1; i < names.length; i++) {
      expect(stems.indexOf(names[i][0]), (stems.indexOf(names[i - 1][0]) + 1) % 10);
      expect(branches.indexOf(names[i][1]), (branches.indexOf(names[i - 1][1]) + 1) % 12);
    }
  });

  test('기간 조명: 연도 줄 아래에 합친 구간마다 가는 괄호가 선다', () {
    final (scene, painter) = make([]);
    painter.axis.spotSpans = [(minuteOfYear(260), minuteOfYear(280)), (minuteOfYear(300), minuteOfYear(320))];
    final before = painter.debugSink.notes.length;
    paint(painter);
    expect(before, before); // 괄호는 도형이라 기록이 없다 — 자리는 아래에서 직접 센다.
    final v = scene.controller.view;
    expect(v.xOf(minuteOfYear(260)), lessThan(v.xOf(minuteOfYear(280))));
    expect(painter.axis.litSpans.map((s) => s.$3).toList(), [1, 1], reason: '넣어 준 구간은 늘 다 켜진 것');
    // 조명이 없으면 괄호도 없다.
    painter.axis.spotSpans = const [];
    expect(painter.axis.litSpans, isEmpty);
    // Emphasis의 조명에서도 구간을 얻는다(겹치는 것은 합친다).
    final emphasis = emph.Emphasis()
      ..reduceMotion = true
      ..set(emph.Look(lit: true, spots: [
        emph.Spot(1, minuteOfYear(260), minuteOfYear(280)),
        emph.Spot(2, minuteOfYear(270), minuteOfYear(300)),
        emph.Spot(3, minuteOfYear(320), minuteOfYear(330)),
      ]));
    painter.axis.emphasis = emphasis;
    expect(painter.axis.litSpans.length, 2);
    expect(painter.axis.litSpans.first.$2, minuteOfYear(300));
    expect(painter.axis.litSpans.map((s) => s.$3).toList(), [1, 1], reason: '움직임 줄이기에서는 곧바로 다 켜진다');
  });

  test('조명 괄호의 짙기는 in/out 스프링의 흐름(Spot.glow)을 따라간다', () {
    final (_, painter) = make([]);
    final emphasis = emph.Emphasis();
    painter.axis.emphasis = emphasis;
    // `Emphasis.tick`은 한 번에 50ms까지만 받는다(한 장면씩 부르는 시계) — 장면을 흉내 내 여러 번 부른다.
    void run(double ms) {
      for (double t = 0; t < ms; t += 20) {
        emphasis.tick(20);
      }
    }

    emphasis.set(emph.Look(lit: true, spots: [emph.Spot(1, minuteOfYear(260), minuteOfYear(280))]));
    // 막 켰을 때는 아직 0 — 괄호도 그려지지 않는다.
    expect(painter.axis.litSpans, isEmpty, reason: 'glow 0은 그리지 않는다');
    run(60);
    final half = painter.axis.litSpans.single.$3;
    expect(half, greaterThan(0));
    expect(half, lessThan(1));
    // 토큰의 길이 뒤에도 남는 임계 감쇠 꼬리까지 기다려 정착을 확인한다.
    run(400);
    expect(painter.axis.litSpans.single.$3, 1);
    expect(emphasis.litMoving, isFalse);

    // 물러남: 조명을 거두면 짙기가 내려가고, 다 꺼지면 괄호가 사라진다(띠가 목표에서 빠져도 따라간다).
    emphasis.set(const emph.Look());
    run(60);
    final fading = painter.axis.litSpans.single.$3;
    expect(fading, lessThan(1));
    expect(fading, greaterThan(0));
    run(320);
    expect(painter.axis.litSpans, isEmpty);

    // 겹치는 두 구간이 한 괄호로 합쳐지면 짙기는 더 짙은 쪽을 쓴다.
    emphasis
      ..reduceMotion = true
      ..set(emph.Look(lit: true, spots: [emph.Spot(1, minuteOfYear(260), minuteOfYear(280)), emph.Spot(2, minuteOfYear(270), minuteOfYear(300))]));
    expect(painter.axis.litSpans.length, 1);
    expect(painter.axis.litSpans.single.$3, 1);
  });

  test("괄호는 '같은 시기를 타국에도'를 켰을 때만 선다(지금 연표의 _echoSpans · 기본 끔)", () {
    final (_, painter) = make([]);
    final emphasis = emph.Emphasis()..reduceMotion = true;
    painter.axis.emphasis = emphasis;

    // 기본값(끔): 칸을 골라 조명이 걸려도 괄호는 없다 — 지금 연표는 show.spotEcho가 꺼져 있으면 아예 그리지 않는다.
    emphasis.set(emph.Look(cell: 'leader:3', spots: [emph.Spot(1, minuteOfYear(260), minuteOfYear(280))]));
    expect(painter.axis.litSpans, isEmpty, reason: '스위치가 꺼져 있으면 괄호가 없다(js/timeline.js 2181)');
    // 켜면 그 자리에 선다.
    emphasis.set(emph.Look(lit: true, cell: 'leader:3', spots: [emph.Spot(1, minuteOfYear(260), minuteOfYear(280))]));
    expect(painter.axis.litSpans.length, 1);
    // 도로 끄면 사라진다(움직임 줄이기에서는 곧바로).
    emphasis.set(emph.Look(cell: 'leader:3', spots: [emph.Spot(1, minuteOfYear(260), minuteOfYear(280))]));
    expect(painter.axis.litSpans, isEmpty);
  });

  // ──────────────── 가문 · 성씨 조명의 괄호(확정 설계 1-2 5-3 · 결정 7 A) ────────────────

  test('가문 조명(Look.houses)은 메아리 스위치와 상관없이 괄호를 세우고, 맞닿은 구간은 하나로 합친다', () {
    final (_, painter) = make([]);
    final emphasis = emph.Emphasis()..reduceMotion = true;
    painter.axis.emphasis = emphasis;
    // 같은 가문이 두 나라에서 이어 다스림: 맞닿은 두 구간 + 떨어진 한 구간 — 괄호 둘.
    emphasis.set(emph.Look(house: 'h-moon', houses: const {'h-moon', 'h-moon-sub'}, spots: [
      emph.Spot(1, minuteOfYear(262), minuteOfYear(284)),
      emph.Spot(2, minuteOfYear(284), minuteOfYear(300)),
      emph.Spot(1, minuteOfYear(320), minuteOfYear(330)),
    ]));
    final spans = painter.axis.litSpans;
    expect(spans.length, 2, reason: '맞닿은 구간은 하나(웹의 .tl-spot-brk와 같은 합치기)');
    expect(spans.first.$1, minuteOfYear(262));
    expect(spans.first.$2, minuteOfYear(300));
    // 끄면(창 닫기) 사라진다 — 움직임 줄이기에서는 곧바로.
    emphasis.set(const emph.Look());
    expect(painter.axis.litSpans, isEmpty);
    // 옛 꼴(house 하나만 · 구간 없음)은 괄호가 없다.
    emphasis.set(const emph.Look(house: 'h-moon'));
    expect(painter.axis.litSpans, isEmpty);
  });

  test('가문 조명에서 칸 조명(스위치 끔)으로 옮기면 물러나는 가문 괄호만 옅어지며 남고, 새 칸 조명의 괄호는 서지 않는다', () {
    final (_, painter) = make([]);
    final emphasis = emph.Emphasis();
    painter.axis.emphasis = emphasis;
    void run(double ms) {
      for (double t = 0; t < ms; t += 20) {
        emphasis.tick(20);
      }
    }

    emphasis.set(emph.Look(house: 'h-moon', houses: const {'h-moon'}, spots: [emph.Spot(1, minuteOfYear(262), minuteOfYear(284))]));
    run(300);
    expect(painter.axis.litSpans.single.$3, 1);
    emphasis.set(emph.Look(cell: 'leader:3', spots: [emph.Spot(2, minuteOfYear(300), minuteOfYear(310), cell: 'leader:3')]));
    run(60);
    final mid = painter.axis.litSpans;
    expect(mid.length, 1, reason: '물러나는 가문 구간 하나만');
    expect(mid.single.$1, minuteOfYear(262));
    expect(mid.single.$3, lessThan(1));
    run(300);
    expect(painter.axis.litSpans, isEmpty, reason: '가라앉으면 스위치를 끈 칸 조명이라 괄호가 없다');
  });

  test('표시 체크 넷: 끄면 그 줄이 빠지고 날짜 칸의 높이가 360ms에 줄어든다', () async {
    final (scene, painter) = make([
      cell(1, 0, 0, 240, 340, '공통 시대'),
      cell(2, 1, 0, 240, 340, '첫 연호', strip: 1),
      cell(3, 1, 0, 240, 340, '첫 도읍', strip: 2),
    ], tracks: 1);
    final axis = painter.axis;
    expect(axis.targetHeight, 1 + AxisModel.yearsHeight + AxisModel.epochPad + AxisModel.epochHeight + AxisModel.calFoldedHeight + 1, reason: '처음에는 연도 · 시대뿐');
    showAllRows(painter); // 넷을 모두 켠 데서 하나씩 끈다
    final all = axis.targetHeight;
    expect(scene.controller.view.head, all);
    scene.controller.reduceMotion = false;
    axis.setShown(ganji: false);
    expect(axis.targetHeight, all - AxisModel.ganjiHeight);
    expect(axis.shownHeight, all, reason: '흐름은 지금 값에서 시작한다');
    expect(axis.flowing, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    paint(painter);
    expect(axis.flowing, isFalse);
    expect(axis.shownHeight, axis.targetHeight);
    await Future<void>.delayed(Duration.zero);
    expect(scene.controller.view.head, all - AxisModel.ganjiHeight);
    // 넷을 다 끄면 연도 줄과 접힌 보조 달력 줄만 남는다.
    scene.controller.reduceMotion = true;
    axis.setShown(eras: false, capitals: false, epochs: false);
    expect(axis.model!.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.cal]);
    expect(axis.shownHeight, 1 + AxisModel.yearsHeight + AxisModel.calFoldedHeight + 1);
    paint(painter);
    expect(of(painter, 'axis-corner').map((l) => l.text).toList(), ['100년 보기'], reason: '간지 · 시대 구분 · 묶음의 모서리 글이 사라진다');
  });

  test('상태 기억: 적어 둔 것을 되돌리면 흐름 없이 곧바로 그 높이에서 선다', () async {
    final (scene, painter) = make([
      cell(2, 1, 0, 240, 340, '첫 연호', strip: 1),
      cell(3, 1, 0, 240, 340, '첫 도읍', strip: 2),
    ], tracks: 1);
    painter.axis.setShown(eras: true); // 연호 줄은 처음에 꺼져 있다(리메이크 2부)
    painter.axis.toggleGroup('eras');
    final saved = painter.axis.stateJson();
    final version = painter.axis.stateVersion;
    expect(version, 2);
    expect(saved['show'], {'ganji': false, 'eras': true, 'capitals': false, 'epochs': true});

    final (scene2, painter2) = make([
      cell(2, 1, 0, 240, 340, '첫 연호', strip: 1),
      cell(3, 1, 0, 240, 340, '첫 도읍', strip: 2),
    ], tracks: 1);
    scene2.controller.reduceMotion = false;
    expect(painter2.axis.restoreState(saved), isTrue);
    expect(painter2.axis.flowing, isFalse, reason: '열 때 되돌린 것은 흐르지 않는다');
    expect(painter2.axis.shownHeight, painter.axis.shownHeight);
    await Future<void>.delayed(Duration.zero);
    expect(scene2.controller.view.head, scene.controller.view.head);
    expect(painter2.axis.stateJson(), saved);
  });

  test('고르기 · 강조 · 흐림은 색의 알파에 곱해진다(saveLayer 없이)', () {
    final (_, painter) = make([
      cell(3, 1, 0, 240, 290, '북쪽성', strip: 1),
      cell(3, 1, 0, 290, 340, '남쪽성', strip: 1),
    ], tracks: 1);
    showAllRows(painter);
    painter.axis.toggleGroup('capitals');
    paint(painter);
    expect(of(painter, 'axis-cell').map((l) => l.alpha).toList(), [1, 1]);
    // 노선도가 한 도시를 비추면 같은 이름이 둘 이상일 때만 나머지가 흐려진다.
    painter.axis.hotCity = '북쪽성';
    paint(painter);
    expect(of(painter, 'axis-cell').map((l) => l.alpha).toList(), [1, 1], reason: '같은 이름이 하나뿐이면 흐리지 않는다');
    painter.axis.hotCity = null;
    // 고른 칸은 진하게(글자색이 바뀐다), 강조에 든 칸은 테두리가 --warn.
    final picked = painter.axis.model!.rows.firstWhere((r) => r.kind == AxisRowKind.cap).data!.cells.first;
    painter.axis.pickedCell = axisCellKey(picked);
    paint(painter);
    expect(of(painter, 'axis-cell').length, 2);
  });

  // 날짜 칸의 묶음을 펼친 모습은 공용 그림 뜨기(test/render_scene_test.dart)가 열 길이 없어 여기서 뜬다.
  // 진짜 저장소와 진짜 자료 처리부를 거치고, 기준 그림은 prototype/results/dom-axis2/의 같은 장면이다.
  //   flutter test --no-pub test/axis_paint_test.dart --dart-define=SHOT=yes [--dart-define=DB=../data/moonwake3-axis2/archive.db]
  test('펼친 연호 · 도읍 줄을 그림으로 뜬다', () async {
    if (const String.fromEnvironment('SHOT') != 'yes') return;
    await shootOpenGroups();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('이설이 있는 칸은 이름 밑에 점선 하나를 긋고, 고른 것이 있으면 그 표식만 흐려진다', () {
    final (_, painter) = make([
      cell(3, 1, 0, 240, 340, '이설 도읍', strip: 1, style: AxisModel.styleVariant),
    ], tracks: 1);
    showAllRows(painter);
    painter.axis.toggleGroup('capitals');
    paint(painter);
    final emphasis = emph.Emphasis()..reduceMotion = true;
    expect(emphasis.trimDim, 1);
    emphasis.set(const emph.Look(band: 3));
    expect(emphasis.trimDim, .45, reason: '고른 것이 있으면 이설 표식은 .45');
    painter.axis.emphasis = emphasis;
    paint(painter);
  });

  // ── 보조 달력(음력 · 이슬람력 · 페르시아력) ──────────────────────────────────────────────
  // 환산은 넣을 때 한 번 뜬 '달의 시작 표'로 한다(계약 6-3절). 검사에서는 296~307년 조각을 꽂는다.
  // 기대하는 달 이름 · 초하루는 기준 덤프 `results/dom-axis2/보조달력-열림` · `일진-하루`에서 읽었다.

  /// 보조 달력 줄이 펼쳐진 장면. [from]~[to]는 해다.
  (TimelineScene, TimelinePainter) calScene({required double from, required double to, bool withTable = true}) {
    AuxCalendarStore.shared = AuxCalendarStore(null);
    if (withTable) AuxCalendarStore.shared!.put('dangi', lunarSlice());
    final made = make([cell(1, 0, 0, 100, 400, '공통 시대')], from: from, to: to);
    paint(made.$2);
    return made;
  }

  test('보조 달력 줄: 표가 있으면 달 눈금이 서고, 없으면 줄이 비어 있다', () {
    final (scene, painter) = calScene(from: 300, to: 302);
    final row = painter.axis.model!.rows.firstWhere((r) => r.kind == AxisRowKind.cal);
    expect(row.height, 20, reason: '한 달이 18px을 넘으면 줄이 열린다');
    final labels = of(painter, 'axis-cal');
    expect(labels, isNotEmpty);
    // 글은 칸 가운데, 칸은 줄의 알맹이에서 위아래 3px 안이다(기준 덤프의 칸 높이 13px).
    final middle = row.contentTop + 3 + (row.contentHeight - 6) / 2 - 10.5 * .6;
    for (final l in labels) {
      expect(l.at.dy, closeTo(middle, .001));
    }
    final (_, without) = calScene(from: 300, to: 302, withTable: false);
    expect(without.axis.model!.rows.firstWhere((r) => r.kind == AxisRowKind.cal).height, 20);
    expect(of(without, 'axis-cal'), isEmpty, reason: '표가 없으면 눈금을 셈하지 않는다');
  });

  // 검사 환경의 글꼴은 글자마다 네모라(진짜 글꼴이 아니다) 이름이 들어가는 폭이 실제보다 넓다 —
  // 해 이름까지 다 드는지 보려면 한 달이 90px쯤 되게 좁혀 본다.
  test('달 눈금 — 해가 바뀌는 달에는 간지 해 이름이 붙고 윤달은 한 번만 나온다', () {
    final (scene, painter) = calScene(from: 300, to: 301.7);
    final texts = [for (final l in of(painter, 'axis-cal')) l.text];
    expect(texts, containsAllInOrder([
      '경신년 1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월',
      '신유년 1월', '2월', '3월', '4월', '5월', '윤5월',
    ]));
    expect(texts.where((t) => t == '윤5월').length, 1);
    expect(texts.where((t) => t.contains('년')).toList(), ['경신년 1월', '신유년 1월']);
    // 경신년 1월의 초하루는 날 번호 1830670이다 — 그 칸 가운데에 글이 앉는다.
    final table = lunarSlice();
    final month = table.monthOfJdn(1830670)!;
    final v = scene.controller.view;
    final x1 = v.xOf(minuteOfYear(tOfJdn(month.startJdn))), x2 = v.xOf(minuteOfYear(tOfJdn(month.endJdn)));
    final width = painter.text.widthOf('경신년 1월', AxisLook.calFirst)!;
    final label = of(painter, 'axis-cal').firstWhere((l) => l.text == '경신년 1월');
    expect(label.at.dx, closeTo((x1 + .5 + x2 - .5) / 2 - width / 2, .01));
  });

  test('하루가 20px을 넘으면 날 눈금이다 — 초하루는 달 이름, 그 밖은 날', () {
    final (_, painter) = calScene(from: 300, to: 300.1);
    final texts = [for (final l in of(painter, 'axis-cal')) l.text];
    // 기준 덤프 `일진-하루`: 299년 11월 23일부터 열흘 남짓, 12월 초하루에서 달 이름이 뜬다.
    expect(texts, containsAllInOrder(['23', '24', '25', '26', '27', '28', '29', '30', '12월', '2', '3']));
    expect(texts.where((t) => t == '12월').length, 1);
    // 날 눈금에서는 해 이름이 붙은 글이 나오지 않는다(다 들지 않아 달 번호만 적는다).
    expect(texts.where((t) => t.contains('년')), isEmpty);
  });

  test('보조 달력의 모서리는 고르기 단추 — 이름이 오른쪽 맞춤이고 내림 세모가 붙는다', () {
    final (scene, painter) = calScene(from: 300, to: 302);
    final left = scene.controller.view.left;
    final label = of(painter, 'axis-corner').firstWhere((l) => l.text == '음력');
    final width = painter.text.widthOf('음력', AxisLook.corner)!;
    // 기준 덤프: 단추의 오른쪽 끝이 모서리에서 11px 안, 안 여백이 오른쪽 12px이다.
    expect(label.at.dx + width, closeTo(left - AxisLook.calPickRight - AxisLook.calPickPadRight, .001));
  });

  // ── 진짜 엔진(DLL) + 진짜 저장소 ────────────────────────────────────────────────────
  // 날짜 칸의 줄은 `layout`의 답으로, 보조 달력의 도움말은 항목 기록 `cal:<달력>`으로 선다 — 가짜 답으로는
  // 그 두 길이 비어 있어도 알 수 없다(2026-09-22의 교훈). 없으면 건너뛴다.
  test('진짜 저장소: 표시 체크 넷이 월흔해의 줄을 실제로 빼고, 보조 달력 칸에 도움말이 선다', () async {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File('../data/moonwake3h/archive.db');
    if (!dll.existsSync() || !db.existsSync()) {
      markTestSkipped('자료 처리부 DLL 또는 data/moonwake3h 저장소가 없습니다');
      return;
    }
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    final shape = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(shape['data'] as Map));
    final model = AxisModel(layout);
    // 처음에는 연도 · 시대(와 접힌 보조 달력)뿐이다(리메이크 2부 — 목업 날짜 칸).
    final base = model.height;
    var kinds = model.rows.map((r) => r.kind).toList();
    expect(kinds.where((k) => k == AxisRowKind.epoch).length, greaterThan(1), reason: '공통 줄 + 나라별 줄');
    expect(kinds, isNot(contains(AxisRowKind.ganji)));
    expect(kinds, isNot(contains(AxisRowKind.group)));
    // 간지 · 연호 · 도읍을 켜면 간지 20 · 묶음 22씩 높아진다.
    model.setShown(ganji: true, eras: true, capitals: true);
    kinds = model.rows.map((r) => r.kind).toList();
    expect(kinds, contains(AxisRowKind.ganji));
    expect([for (final r in model.rows) if (r.kind == AxisRowKind.group) r.groupKey], ['eras', 'capitals']);
    final all = model.height;
    expect(all, base + AxisModel.ganjiHeight + 2 * AxisModel.groupHeight);

    final epochHeights = [for (final r in model.rows) if (r.kind == AxisRowKind.epoch) r.height].fold(0.0, (a, b) => a + b);
    model.setShown(ganji: false, eras: false, capitals: false, epochs: false);
    expect(model.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.cal]);
    expect(
      model.height,
      all - AxisModel.ganjiHeight - 2 * AxisModel.groupHeight - epochHeights,
      reason: '뺀 줄의 높이만큼만 낮아진다',
    );
    model.setShown(ganji: true, eras: true, capitals: true, epochs: true);
    expect(model.height, all, reason: '다시 켜면 그대로 돌아온다');

    // 보조 달력 표는 항목 기록 `cal:<달력>`으로 온다 — 진짜 저장소에서 받아 도움말을 만든다.
    final answer = await engine.call({'op': 'entity', 'uid': 'cal:${AuxCalendar.defaultId}'});
    final table = AuxCalendarTable.parse((answer['data'] as Map)['json']);
    expect(table, isNotNull, reason: '저장소에 달의 시작 표가 실려 있어야 한다');
    AuxCalendarStore.shared = AuxCalendarStore(null)..put(AuxCalendar.defaultId, table);
    addTearDown(() => AuxCalendarStore.shared = null);
    model.setCalOpen(true);
    const left = 240.0;
    double minuteAt(double x) => minuteOfYear(300 + (x - left) / 60); // 1년 = 60px
    final row = model.rows.firstWhere((r) => r.kind == AxisRowKind.cal);
    // 경신년 1월 초하루(날 번호 1,830,670)의 낮이 놓이는 자리.
    final at = minuteOfYear(tOfJdn(table!.monthOfJdn(1830670)!.startJdn)) + 600;
    final hit = model.hitTest(left + (yearAt(at) - 300) * 60, row.contentTop + 8, left, minuteAt);
    expect(hit.kind, AxisHitKind.none, reason: '누를 것은 없고 도움말만 있는 자리');
    expect(hit.tip, '음력 경신년 1월 — 300년 2월 7일부터', reason: '지금 연표의 title 그대로');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// 진짜 저장소로 '연호 펼침' · '도읍 펼침' · '배도 펼침' 장면을 떠서 `../results/render-axis2/`에 적는다.
/// 기준 그림은 `prototype/results/dom-axis2/`의 같은 이름이다(같은 1920×1080 · 맨 위 60px은 앱 틀의 자리).
Future<void> shootOpenGroups() async {
  const width = 1920.0, height = 1080.0, top = 60.0;
  final dll = File('../engine/target/release/archive_engine.dll');
  final dbPath = const String.fromEnvironment('DB', defaultValue: '../data/moonwake3-axis2/archive.db');
  final db = File(dbPath);
  if (!dll.existsSync() || !db.existsSync()) return;
  await loadAppFonts();
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf']),
    ('Malgun Gothic', ['C:/Windows/Fonts/malgun.ttf', 'C:/Windows/Fonts/malgunbd.ttf']),
  ]) {
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
  final engine = ArchiveEngine(libraryPath: dll.absolute.path);
  addTearDown(engine.close);
  final info = await engine.start(db.absolute.path);
  final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
  final shape = await engine.call({'op': 'layout'});
  final folder = Directory('../results/render-axis2')..createSync(recursive: true);

  for (final (name, groups, capSec, from, to, show) in [
    ('연호-펼침-100년', ['eras'], false, 240.0, 340.0, null),
    ('도읍-펼침-100년', ['capitals'], false, 240.0, 340.0, null),
    ('배도-펼침-100년', ['capitals'], true, 240.0, 340.0, null),
    // 이설이 있는 칸(연호 '파도문 조율' 800~880 · 도읍 '별목' 825~888)이 보이는 범위.
    ('연호-펼침-밀집', ['eras'], false, 775.0, 940.0, null),
    ('도읍-펼침-밀집', ['capitals'], false, 775.0, 940.0, null),
    // 표시 체크 넷(필터 시트의 '날짜 칸') — 끈 줄이 빠진 모습.
    ('표시끔-간지', <String>[], false, 775.0, 940.0, {'ganji': false}),
    ('표시끔-시대구분', <String>[], false, 775.0, 940.0, {'epochs': false}),
    ('표시끔-넷다', <String>[], false, 775.0, 940.0, {'ganji': false, 'eras': false, 'capitals': false, 'epochs': false}),
  ]) {
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(shape['data'] as Map));
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(width, height - top)
      ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
      ..setContentHeight(layout.totalHeight);
    final scene = TimelineScene(
      controller: controller, layout: layout, fetchTile: engine.tile,
      ask: (query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map),
    );
    final text = AtlasText()
      ..maxNewPerFrame = 4000
      ..budgetMicros = 2000000;
    final painter = TimelinePainter(scene, text: text)..debug = true;
    for (final key in groups) {
      painter.axis.toggleGroup(key);
    }
    if (capSec) {
      for (final t in layout.tracks) {
        painter.axis.toggleCapSec(t.id);
      }
    }
    if (show != null) {
      painter.axis.setShown(ganji: show['ganji'], eras: show['eras'], capitals: show['capitals'], epochs: show['epochs']);
    }
    scene.applyLayoutToView();
    controller.resize(width, height - top);
    controller.showRange(minuteOfYear(from), minuteOfYear(to));
    controller.scrollTo(0);
    int calm = 0;
    for (int i = 0; i < 200 && calm < 3; i++) {
      final r = ui.PictureRecorder();
      painter.paint(ui.Canvas(r), const ui.Size(width, height - top));
      r.endRecording().dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      scene.tick(20);
      final s = scene.stats, labels = scene.labelOutput;
      final settled = s.blanks == 0 && s.covers == 0 && !scene.fading && labels != null && labels.deferred == 0 && !text.starved && !scene.labelWorker.busy && scene.settled;
      calm = settled ? calm + 1 : 0;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xfff4eee4));
    canvas.drawRect(const ui.Rect.fromLTWH(0, top, width, 1), ui.Paint()..color = const ui.Color(0x1a5a3c14));
    canvas.save();
    canvas.translate(0, top);
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, width, height - top));
    painter.paint(canvas, const ui.Size(width, height - top));
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    File('${folder.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    File('${folder.path}/$name.json').writeAsStringSync(jsonEncode({
      'scene': {'name': name, 'left': controller.view.left, 'head': controller.view.head, 'top': top},
      'labels': [for (final l in painter.debugLabels) {'kind': l.kind, 't': l.text, 'at': [l.at.dx, l.at.dy + top], 'alpha': l.alpha}],
    }));
    // ignore: avoid_print
    print('저장: ${folder.absolute.path}${Platform.pathSeparator}$name.png (날짜 칸 ${controller.view.head})');
    text.dispose();
    scene.dispose();
  }
}
