import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/timeline_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 단체 단(집권 · 실권) · 명목 지도자 · 연합의 겹 탭 — 10건 7의 D5 결정 1 A · 2(자리 A) · 3 C와 덧판 x1 A · x2 A · x3 C의 새 앱 몫.
//   · 배치: 그 줄에 집권 단 · 실권 단이 있으면 지위 층 아래 · 지도자 층 위에 칸 층 14씩(줄 단위 · 두 장 꼬리표의 몸통) — 표시 체크 '단체'를 끄면 예전 높이
//   · 그리기: 칸 종류 8의 단 2 · 3(단 갈래 5 ~ 7) · 연정 칸의 색 점 · 명목 지도자의 이름(paint/strips.dart),
//             구역 47의 모습 7 = 연합의 겹 탭 · 올렸을 때의 가담 기간 조명(paint/bands.dart) · 나머지 줄의 흐림(paint/overlay.dart)
//   · 올림: 탭에 커서를 올리면 `SceneMarks.hotCoal`이 켜지고 떠나면 · 끌면 꺼진다(timeline_view.dart) · 풍선 글
// 띠 위에는 딱지 글('집권' · '실권' · '연정' · '연합')이 없다 — 감독 원칙 "테두리나 여타 모양이나 색으로 구분해야지, 단어로 구분하지 말 것".
// 고정 자료 test/fixtures/power-base.json은 `node prototype/scripts/lens-export-check.mjs --fixtures`가 견본 sample-power를 내보낸 꼴 그대로
// 뜬 것이다(손으로 고치지 않음 — 웹 검사 scripts/power-check.mjs와 같은 견본 · 같은 보기 범위). 이름은 모두 가상이다.

final Map<String, dynamic> fx = (jsonDecode(File('test/fixtures/power-base.json').readAsStringSync()) as Map).cast<String, dynamic>();
List<Map<String, dynamic>> listOf(String key) => [for (final v in fx[key] as List) (v as Map).cast<String, dynamic>()];

/// 지금 연표의 해 좌표 → 1970년 기준 분(내보내기 base.mjs의 minute · render_scene_test와 같은 투영).
double minuteOfYear(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return (a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000;
}

/// 단계 9에서 통 하나가 32px일 때의 1분 폭 — 자리는 '타일 왼쪽에서 몇 px'로 적고 타일의 분으로 바꾼다(strips_paint_test와 같은 셈).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;
const bodyW = 1920 - SceneView.gutter;

/// 트랙의 첫 줄(전체 줄 번호).
int firstRowOf(int track) {
  var n = 0;
  final tracks = listOf('tracks');
  for (int i = 0; i < track; i++) {
    n += (tracks[i]['rows'] as List).length;
  }
  return n;
}

/// 띠 번호 = 고정 자료의 띠 차례 + 1(내보내기의 번호와 같다 — 구역 47의 d가 이 번호로 상국 띠를 가리킨다).
final bandIdOf = {for (final (i, p) in listOf('periods').indexed) p['uid'] as String: i + 1};
final periodOf = {for (final p in listOf('periods')) p['uid'] as String: p};
int rowOfPeriod(String uid) => firstRowOf(periodOf[uid]!['track'] as int) + (periodOf[uid]!['row'] as int);

/// 그 줄에 위로 솟는 것(받침 카드 + 상국 탭 · 연합의 겹 탭 — 구역 47)이 있으면 `fig_wide` 비트 14(꼬리표 갈래 E — `RowSpec.raised` · 위 틈 + 15).
/// 내보내기 `export/tracks.mjs`의 contributeLate와 같은 규칙(구역 47을 실은 줄 · 비트 3~5가 있는 줄)이다 — 고정 자료는 그 비트가 생기기 전에 떠서
/// 손대지 않고 여기서 얹는다.
int raisedBit(int track, int row, int figWide) =>
    (figWide >> 3) & 7 != 0 && listOf('items').any((it) => it['section'] == 47 && it['track'] == track && it['row'] == row) ? 1 << 14 : 0;

Map<String, dynamic> skeleton() {
  var id = 0;
  return {
    'packs': [
      {'id': 1, 'name': '단체 단 견본', 'events': 0},
    ],
    'tracks': [
      for (final (i, t) in listOf('tracks').indexed)
        {
          'id': i + 1, 'pack': 1, 'ord': i, 'name': t['name'], 'color': 0xa0bcc5, 'key': t['key'],
          'dynasty': 0, 'leader': t['leader'], 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
          'rows': [
            for (final (j, r) in (t['rows'] as List).indexed)
              {
                'id': id++, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
                'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
                'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
                'fig': 0, 'fig_wide': (r['figWide'] as int) | raisedBit(i, j, r['figWide'] as int), 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0,
              },
          ],
        },
    ],
    'epochs': <dynamic>[],
    'categories': <dynamic>[],
    'axis': <dynamic>[],
    'variants': <dynamic>[],
  };
}

/// 보기 범위 [y0] ~ [y1](해)이 그림 영역 폭에 꼭 맞게 — 고정 자료의 분을 타일 안의 자리로.
class Window {
  Window(this.y0, this.y1) : m0 = minuteOfYear(y0), m1 = minuteOfYear(y1);
  final double y0, y1, m0, m1;

  /// 타일의 왼쪽 끝 = 가장 이른 띠보다 앞(1380년) — 띠 · 칸이 타일에 잘리지 않게.
  static final base = minuteOfYear(1380);
  double get k => bodyW / (m1 - m0);
  double px(num minute) => (minute - base) * k;
  double tileX(num minute) => at(px(minute));

  Uint8List tile() {
    final b = TileBuilder(level: 9, x: 0, chunk: 0);
    for (final p in listOf('periods')) {
      b.band(bandIdOf[p['uid']]!, rowOfPeriod(p['uid'] as String), tileX(p['start'] as num), tileX(p['end'] as num), p['name'] as String, color: p['color'] as int, look: p['look'] as int);
    }
    var id = 100;
    for (final c in listOf('cells')) {
      b.cell(id++, rowOfPeriod(c['period'] as String), tileX(c['start'] as num), tileX(c['end'] as num), c['name'] as String,
          kind: c['kind'] as int, lane: c['lane'] as int, style: c['style'] as int, color: c['color'] as int);
    }
    for (final it in listOf('items')) {
      b.item(it['section'] as int, id++, rowOfPeriod(it['ref'] as String), tileX(it['start'] as num), tileX(it['end'] as num),
          ref: bandIdOf[it['ref']]!, name: it['name'] as String, color: it['color'] as int,
          a: it['a'] as int, b: it['b'] as int, c: it['c'] as int, d: it['d'] as int, text2: it['text2'] as String);
    }
    return b.build();
  }
}

TimelineScene makeScene(Window w, {bool groups = true}) {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..reduceMotion = true;
  controller.showRange(w.tileX(w.m0), w.tileX(w.m1));
  final layout = SceneLayout.fromJson(skeleton());
  if (!groups) {
    layout
      ..setConditions(layout.conditions.copyWith(groups: false))
      ..finishFlow();
  }
  final bytes = w.tile();
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    labelCompute: (input) async => placeLabels(input),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  controller.setContentHeight(scene.layout.totalHeight);
  return scene;
}

Future<TimelinePainter> drawn(TimelineScene scene) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  final painter = TimelinePainter(scene, text: ParagraphText())..debug = true;
  // 글자 폭은 처음 그릴 때 재므로(탭은 폭을 알아야 선다) 두 번 그린다.
  for (int i = 0; i < 2; i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
  return painter;
}

List<String> notes(TimelinePainter p, String kind) => [for (final v in p.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// '칸' 기록('종류:줄:단 l,t,w,h' — 0.1px 단위) 하나.
class Cell {
  Cell(String text)
    : kind = int.parse(text.split(' ')[0].split(':')[0]),
      row = int.parse(text.split(' ')[0].split(':')[1]),
      lane = int.parse(text.split(' ')[0].split(':')[2]),
      l = int.parse(text.split(' ')[1].split(',')[0]) / 10,
      t = int.parse(text.split(' ')[1].split(',')[1]) / 10,
      w = int.parse(text.split(' ')[1].split(',')[2]) / 10,
      h = int.parse(text.split(' ')[1].split(',')[3]) / 10;
  final int kind, row, lane;
  final double l, t, w, h;
}

List<Cell> cellsOf(TimelinePainter p) => [for (final s in notes(p, '칸')) Cell(s)];

/// '연합탭' 기록('줄 이름 x,w[ 올림]' — 0.1px 단위) 하나.
class CoalTab {
  CoalTab(String text)
    : row = int.parse(text.split(' ').first),
      on = text.endsWith(' 올림'),
      name = (text.endsWith(' 올림') ? text.substring(0, text.length - 3) : text).split(' ').skip(1).toList().reversed.skip(1).toList().reversed.join(' '),
      x = int.parse((text.endsWith(' 올림') ? text.substring(0, text.length - 3) : text).split(' ').last.split(',')[0]) / 10,
      w = int.parse((text.endsWith(' 올림') ? text.substring(0, text.length - 3) : text).split(' ').last.split(',')[1]) / 10;
  final int row;
  final String name;
  final double x, w;
  final bool on;
}

List<CoalTab> coalTabs(TimelinePainter p) => [for (final s in notes(p, '연합탭')) CoalTab(s)];

/// 줄의 띠 윗변(화면 y).
double bandTopOf(TimelineScene s, int r) => s.controller.view.yOf(s.layout.rowTop(r) + s.layout.geo(r).bandTop);

/// 연합 단체의 uid(구역 47의 text2) — 이름으로 찾는다.
String coalUid(String name) => listOf('items').firstWhere((it) => it['section'] == 47 && it['a'] == BandLayer.coalLook && it['name'] == name)['text2'] as String;

/// 그 띠에서의 가담 기간(분) — 구역 47의 구간.
(num, num) joinOf(String coal, String band) {
  final uid = listOf('periods').firstWhere((p) => p['name'] == band)['uid'];
  final it = listOf('items').firstWhere((it) => it['section'] == 47 && it['a'] == BandLayer.coalLook && it['name'] == coal && it['ref'] == uid);
  return (it['start'] as num, it['end'] as num);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final garam = rowOfPeriod(listOf('periods').firstWhere((p) => p['name'] == '가람 왕국')['uid'] as String);
  final narae = rowOfPeriod(listOf('periods').firstWhere((p) => p['name'] == '나래 공국')['uid'] as String);
  final keunmut = rowOfPeriod(listOf('periods').firstWhere((p) => p['name'] == '큰 뭍 제국')['uid'] as String);

  group('고정 자료', () {
    test('견본 power의 기본 판: 줄 값의 집권 · 실권 비트 · 단 2 · 3의 칸과 그 칸의 구역 43 · 명목 비트 · 구역 47의 모습 7', () {
      final layout = SceneLayout.fromJson(skeleton());
      expect([layout.spec(garam)!.power, layout.spec(garam)!.real], [true, true]);
      expect([layout.spec(narae)!.power, layout.spec(narae)!.real], [false, false]);
      final cells = listOf('cells');
      final strip = cells.where((c) => c['kind'] == 8);
      expect(strip.map((c) => c['lane']).toSet(), {2, 3});
      expect(strip.map((c) => (c['style'] as int) >> 27 & 7).toSet(), {5, 6, 7}, reason: '단 갈래: 한 단체 · 연정 · 실권');
      expect(listOf('items').where((it) => it['section'] == 43).length, strip.length, reason: '칸마다 구역 43 하나');
      expect(cells.where((c) => c['kind'] == 1 && (c['style'] as int) & (1 << 29) != 0).map((c) => c['name']), ['어린 임금', '열째 가람왕', '열한째 가람왕']);
      final tabs = listOf('items').where((it) => it['section'] == 47 && it['a'] == BandLayer.coalLook);
      expect(tabs.map((it) => it['name']).toSet(), {'서녘 맹약', '북녘 맹약', '남녘 맹약'});
      expect(tabs.every((it) => (it['text2'] as String).isNotEmpty), isTrue);
      // 구역 47(받침 카드 · 상국 탭 · 겹 탭)을 실은 줄만 위로 솟는 것이 있다 — 그 줄의 띠 위 틈은 5 + 15(꼬리표 갈래 E).
      expect([for (int r = 0; r < layout.rowCount; r++) layout.spec(r)!.raised], [true, false, true, true, true]);
      expect([layout.tabOf(garam), layout.tabOf(narae)], [5 + 15, 5]);
    });
  });

  group('배치 — 덧단', () {
    test('집권 층 · 실권 층은 지도자 층 바로 위에 14씩(위 = 집권 · 아래 = 실권), 단체 없는 줄은 그대로', () {
      final scene = makeScene(Window(1700, 1900));
      final geo = scene.layout.geo(garam), plain = scene.layout.geo(narae);
      expect(geo.powerTop, greaterThan(0));
      expect(geo.realTop - geo.powerTop, G.power + G.powerGap);
      expect(geo.leaderTop - geo.realTop, G.power + G.powerGap);
      expect(geo.leaderTop - geo.realTop, 14, reason: '칸 층은 틈 없이 14씩 맞붙는다(G.floor)');
      expect([plain.powerTop, plain.realTop], [-1, -1]);
      // 두 장 꼬리표(리메이크 2부 · 감독 결정 '두 장 ㄴ'): 이름 색줄 14 바로 밑이 몸통 — 단체 없는 줄의 지도자 층은 몸통의 첫 층이고,
      // 집권 층이 있는 줄은 이 자리에 집권 층이 선다(집권 · 실권은 칸 층이 없는 꼬리표도 몸통의 첫 단 — 빽빽하게만 층 없이 색줄 밑줄).
      // 고정 자료는 줄 값 칸 층 비트(fig_wide 비트 19)가 생기기 전에 떠서 지도자 층은 트랙 값으로 둔다.
      expect(plain.leaderTop - plain.bandTop, G.head);
      expect(geo.powerTop - geo.bandTop, G.head);
      expect([geo.bodyTop, plain.bodyTop], [geo.powerTop, plain.leaderTop], reason: '첫 층 = 몸통 윗변');
    });

    test("표시 체크 '단체'를 끄면 그 줄만 28 낮아지고(두 층) 다른 줄은 1px도 그대로", () {
      final on = makeScene(Window(1700, 1900)).layout, off = makeScene(Window(1700, 1900), groups: false).layout;
      expect(on.geo(garam).height - off.geo(garam).height, 2 * (G.power + G.powerGap));
      expect(2 * (G.power + G.powerGap), 28);
      expect([off.geo(garam).powerTop, off.geo(garam).realTop], [-1, -1]);
      for (int r = 0; r < on.rowCount; r++) {
        if (r != garam) expect(on.geo(r).height, off.geo(r).height, reason: '줄 $r');
      }
    });
  });

  group('그리기 — 단체 칸 · 명목', () {
    // 칸은 층의 윗선(1px — 첫 층은 색줄 아랫변의 테 · 그 아래는 층 사이 금) 아래에 든다: 칸 위 = 층 위 + 1 · 높이 = 14 − 1 = 13(paint/strips.dart · 두 장 꼬리표).
    test('집권 칸은 집권 층 · 실권 칸은 실권 층 자리에(층의 윗선 아래 13) — 띠 안 · 지도자 칸 위', () async {
      final scene = makeScene(Window(1700, 1900));
      final p = await drawn(scene);
      final geo = scene.layout.geo(garam), top = bandTopOf(scene, garam);
      final power = cellsOf(p).where((c) => c.kind == 8 && c.lane == 2), real = cellsOf(p).where((c) => c.kind == 8 && c.lane == 3);
      expect(power, isNotEmpty);
      expect(real.length, 2, reason: '실권 집단의 칸 둘(웹 power-check ①)');
      for (final c in power) {
        expect([c.row, c.t - top, c.h], [garam, geo.powerTop - geo.bandTop + 1, G.power - 1]);
      }
      for (final c in real) {
        expect([c.row, c.t - top, c.h], [garam, geo.realTop - geo.bandTop + 1, G.power - 1]);
      }
      final leaders = cellsOf(p).where((c) => c.kind == 1 && c.row == garam);
      expect(leaders, isNotEmpty);
      expect(leaders.every((c) => c.t - top == geo.leaderTop - geo.bandTop + 1 && c.h == G.leader - 1), isTrue);
      expect(G.leader - 1, 13);
    });

    test('연정 칸의 색 점은 함께 집권한 단체 수만큼(셋이면 셋) · 다 들어갈 때만 — 색은 자료의 차례 그대로', () async {
      final p = await drawn(makeScene(Window(1700, 1900)));
      // '색점' 기록: '줄 x,y 색'(0.1px 단위) — 같은 칸의 점은 지름6 + 틈3 = x가 9씩 늘어난다.
      final dots = [for (final s in notes(p, '색점')) (int.parse(s.split(' ')[1].split(',')[0]) / 10, s.split(' ').last)];
      final runs = <List<String>>[];
      double? last;
      for (final (x, color) in dots) {
        if (last != null && (x - last - 9).abs() < .01) {
          runs.last.add(color);
        } else {
          runs.add([color]);
        }
        last = x;
      }
      // 자료의 색 점 목록(구역 43의 text2 — "uid\t색,색")과 같은 묶음만 그려진다.
      final want = [for (final it in listOf('items')) if (it['section'] == 43 && (it['text2'] as String).contains('\t')) (it['text2'] as String).split('\t')[1]];
      expect(runs, isNotEmpty);
      for (final run in runs) {
        expect(want, contains(run.join(',')), reason: '점이 일부만 그려진 칸이 없어야 한다');
      }
      expect(runs.any((r) => r.length == 3), isTrue, reason: '셋이 함께 집권한 칸은 점 셋');
      expect(runs.any((r) => r.length == 2), isTrue);
    });

    test('명목 지도자는 이름 글만 옅게 — 실권과 절반 이상 겹친 셋만, 표시를 끄면 없음', () async {
      final p = await drawn(makeScene(Window(1700, 1900)));
      expect(notes(p, '명목').map((s) => s.split(' ').skip(1).join(' ')), ['어린 임금', '열째 가람왕', '열한째 가람왕']);
      final off = await drawn(makeScene(Window(1700, 1900), groups: false));
      expect(notes(off, '명목'), isEmpty);
      expect(cellsOf(off).where((c) => c.kind == 8), isEmpty, reason: '단이 없으면 단체 칸도 없다');
    });

    test("띠 위에 딱지 글이 없다 — '집권' · '실권' · '연정' · '연합'은 풍선 글과 단체 창에만", () async {
      for (final w in [Window(1700, 1900), Window(1560, 1700), Window(1400, 1950)]) {
        final p = await drawn(makeScene(w));
        final words = p.debugLabels.map((l) => l.text).where((t) => RegExp(r'^(집권|실권|연정|연합)( \d+)?$').hasMatch(t));
        expect(words, isEmpty, reason: '${w.y0} ~ ${w.y1}');
      }
    });
  });

  group('그리기 — 계보 창에서 고른 단체', () {
    test('고른 단체가 든 칸만 진한 테두리(연정 칸은 색 점으로 가림) · 나머지 단체 칸은 .4 — 풀면 처음 그대로', () async {
      final w = Window(1700, 1900);
      final scene = makeScene(w);
      final plain = await drawn(scene);
      expect(notes(plain, '단체고름'), isEmpty);
      // 한 단체만 집권한 칸(구역 43의 text2에 색 점이 없는 집권 칸 — 보기 범위에 걸친 것)의 단체 하나를 고른다.
      final one = listOf('items').firstWhere((it) => it['section'] == 43 && it['b'] == 2 && !(it['text2'] as String).contains('	') && (it['start'] as num) < w.m1 && (it['end'] as num) > w.m0);
      final uid = one['text2'] as String;
      final cell = listOf('cells').firstWhere((c) => c['kind'] == 8 && c['lane'] == 2 && (((c['style'] as int) >> 15) & 0xfff) == one['c']);
      final color = cell['color'] as int;
      SceneMarks.of(scene)
        ..groupFocus = uid
        ..groupFocusColor = color
        ..version += 1;
      final p = await drawn(scene);
      final picked = notes(p, '단체고름');
      expect(picked, isNotEmpty);
      expect(picked.every((s) => s.startsWith('$garam:')), isTrue);
      expect(picked.where((s) => s.endsWith(' $uid')), isNotEmpty, reason: '제 uid가 실린 칸');
      // 나머지 단체 칸은 .4(칸 밝기 기록의 값이 처음의 0.4배) — 고른 칸은 그대로.
      int bright(TimelinePainter x, int k) => int.parse(notes(x, '칸밝기').where((s) => s.startsWith('8:$garam:')).elementAt(k).split(' ')[1].split(',')[0]);
      final n = notes(p, '칸밝기').where((s) => s.startsWith('8:$garam:')).length;
      var dimmed = 0, kept = 0;
      for (int k = 0; k < n; k++) {
        final a = bright(plain, k), b = bright(p, k);
        if ((b / a - .4).abs() < .005) {
          dimmed++;
        } else {
          expect(b, a);
          kept++;
        }
      }
      expect(kept, picked.length);
      expect(dimmed, greaterThan(0));
      expect(dimmed + kept, n);

      SceneMarks.of(scene)
        ..groupFocus = null
        ..groupFocusColor = 0
        ..version += 1;
      final back = await drawn(scene);
      expect(notes(back, '단체고름'), isEmpty);
      expect([for (int k = 0; k < n; k++) bright(back, k)], [for (int k = 0; k < n; k++) bright(plain, k)]);
    });

    test('연정 칸에서 둘째부터의 단체는 색 점으로 가린다 — 그 나라 띠에 조명이 켜져 있을 때만(다른 나라의 같은 색 칸은 아님)', () async {
      final w = Window(1700, 1900);
      // 첫째로 실린 적이 없는 단체의 색(연정 칸의 둘째 색 · 색 점에만 있다).
      final firsts = {for (final c in listOf('cells')) if (c['kind'] == 8) c['color'] as int};
      final second = listOf('items').map((it) => it['section'] == 43 ? it['color'] as int : 0).firstWhere((c) => c != 0 && !firsts.contains(c));
      final hex = second.toRadixString(16).padLeft(6, '0');
      final want = listOf('items').where((it) => it['section'] == 43 && (it['text2'] as String).contains('	') && (it['text2'] as String).split('	')[1].split(',').contains(hex) && (it['start'] as num) < w.m1 && (it['end'] as num) > w.m0).length;
      expect(want, greaterThan(0));
      final scene = makeScene(w);
      SceneMarks.of(scene)
        ..groupFocus = 'sample-power/첫째로-실리지-않은-단체'
        ..groupFocusColor = second
        ..version += 1;
      expect(notes(await drawn(scene), '단체고름'), isEmpty, reason: '조명이 없는 띠에서는 색만으로 고르지 않는다');
      // 계보 창이 고른 단체의 집권 덩이를 그 나라 띠에 조명으로 켠 것처럼.
      final band = bandIdOf[listOf('periods').firstWhere((p) => p['name'] == '가람 왕국')['uid']]!;
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(em.Look(lit: true, spots: [em.Spot(band, w.tileX(minuteOfYear(1760)), w.tileX(minuteOfYear(1786)))]));
      final p = await drawn(scene);
      expect(notes(p, '단체고름').length, want);
      expect(notes(p, '단체고름').every((s) => s.startsWith('$garam:2 ')), isTrue);
    });
  });

  group('그리기 — 연합의 겹 탭', () {
    // 꼬리표 갈래 E: 띠 위 탭 줄이 없어 겹 탭은 띠 윗변 위에 바로 서는 낮은 탭이다 — 앞 장 [윗변 − 12, 윗변 + 1] · 뒤 장 4px 오른쪽 · 3px 위.
    test('구성 나라 띠마다(트랙이 달라도) 가담이 시작한 해의 자리에, 이름 폭 + 안 여백 9씩 · 띠 윗변 위의 낮은 탭(12)', () async {
      final w = Window(1560, 1700);
      final scene = makeScene(w);
      final p = await drawn(scene);
      final tabs = coalTabs(p);
      expect([for (final t in tabs.where((t) => t.row == garam)) t.name]..sort(), ['북녘 맹약', '서녘 맹약']);
      expect([for (final t in tabs.where((t) => t.row == keunmut)) t.name]..sort(), ['북녘 맹약', '서녘 맹약']);
      expect(tabs.where((t) => t.row != garam && t.row != keunmut), isEmpty);
      final v = scene.controller.view;
      for (final t in tabs) {
        final band = listOf('periods').firstWhere((x) => rowOfPeriod(x['uid'] as String) == t.row)['name'] as String;
        final start = joinOf(t.name, band).$1;
        expect(t.x, closeTo(v.xOf(w.tileX(start)), .06), reason: '${t.name} — $band에 가담한 해');
        expect(t.w, closeTo(p.text.widthOf(t.name, BandLayer.hostLook)! + 2 * BandLayer.coalPad, .06));
        // 누르기 자리 = 앞 장 + 뒤 장의 4px, 앞 장의 높이(윗변 − 12 ~ 윗변 + 1).
        final top = bandTopOf(scene, t.row);
        final y = top - TagLook.tabH + 2;
        final hit = p.bands.hitBands(t.x + t.w + BandLayer.coalBackDx - .5, y);
        expect(hit, isNotNull);
        expect([hit!.coal, hit.tab, hit.uid], [true, true, coalUid(t.name)]);
        expect(p.bands.hitBands(t.x + t.w + BandLayer.coalBackDx + 1.5, y)?.coal ?? false, isFalse);
        expect(p.bands.hitBands(t.x + 2, top - TagLook.tabH - 1.5)?.coal ?? false, isFalse, reason: '앞 장의 윗변(윗변 − 12) 위는 탭 밖');
      }
      expect(tabs.every((t) => !t.on), isTrue);
    });

    test('상국 탭이 먼저 — 연합 탭을 더해도 상국 탭은 1px도 안 움직이고, 탭끼리(뒤 장까지) 4px 안으로 닿지 않는다', () async {
      final on = await drawn(makeScene(Window(1560, 1700))), off = await drawn(makeScene(Window(1560, 1700), groups: false));
      List<(String, double)> hosts(TimelinePainter p) => [for (final l in p.debugLabels) if (l.kind == 'hostTab' && l.text.endsWith('제국')) (l.text, l.at.dx)];
      expect(hosts(off), isNotEmpty);
      expect(hosts(on), hosts(off));
      // 표시 체크 '단체'를 끄면 연합 탭이 없다(웹 _coalTabPlan의 show.groups).
      expect(coalTabs(off), isEmpty);
      expect(off.debugLabels.where((l) => l.kind == 'hostTab' && l.text.endsWith('맹약')), isEmpty);
      // 같은 줄의 연합 탭 · 상국 탭이 서로 닿지 않는다.
      final tabs = coalTabs(on);
      for (final a in tabs) {
        for (final b in tabs) {
          if (identical(a, b) || a.row != b.row || a.x > b.x) continue;
          expect(a.x + a.w + BandLayer.coalBackDx + 4, lessThanOrEqualTo(b.x + .01), reason: '${a.name} · ${b.name}');
        }
      }
    });

    test('시작 해 자리가 상국 탭에 막힌 띠에서는 그리지 않는다(밀지 않음) — 다른 구성 띠에는 있다', () async {
      final p = await drawn(makeScene(Window(1400, 1950)));
      final tabs = coalTabs(p);
      expect(tabs.where((t) => t.row == garam && t.name == '북녘 맹약'), isEmpty, reason: '가람 왕국: 1619의 자리가 넓은 땅 제국 상국 탭(1637)에 닿는다');
      expect(tabs.where((t) => t.row == keunmut && t.name == '북녘 맹약').length, 1);
    });

    test('올리면 같은 연합의 탭이 모두 진해지고 구성 띠에 가담 기간 조명 · 나머지 줄은 옅게 — 풀면 처음 그대로', () async {
      final w = Window(1560, 1700);
      final scene = makeScene(w);
      final uid = coalUid('북녘 맹약');
      SceneMarks.of(scene)
        ..hotCoal = uid
        ..version += 1;
      final p = await drawn(scene);
      final tabs = coalTabs(p);
      expect(tabs.where((t) => t.on).map((t) => t.name).toSet(), {'북녘 맹약'});
      expect(tabs.where((t) => t.on).map((t) => t.row).toSet(), {garam, keunmut});
      expect(tabs.where((t) => t.name == '서녘 맹약').every((t) => !t.on), isTrue);
      expect(p.bands.coalRows(uid), {garam, keunmut});
      // 조명: '띠 왼쪽,오른쪽'(0.1px) — 띠마다 제 가담 기간.
      final v = scene.controller.view;
      final lit = {for (final s in notes(p, '연합조명')) int.parse(s.split(' ')[0]): s.split(' ')[1].split(',').map((n) => int.parse(n) / 10).toList()};
      for (final band in ['가람 왕국', '큰 뭍 제국']) {
        final id = bandIdOf[listOf('periods').firstWhere((x) => x['name'] == band)['uid']]!;
        final (a, b) = joinOf('북녘 맹약', band);
        expect(lit[id], isNotNull, reason: band);
        expect(lit[id]![0], closeTo(v.xOf(w.tileX(a)), .06), reason: '$band 가담 시작');
        expect(lit[id]![1], closeTo(v.xOf(w.tileX(b)), .06), reason: '$band 가담 끝');
      }
      expect(lit.length, 2);
      expect(notes(p, '연합흐림'), ['구성 줄 2']);

      SceneMarks.of(scene)
        ..hotCoal = null
        ..version += 1;
      final back = await drawn(scene);
      expect(coalTabs(back).every((t) => !t.on), isTrue);
      expect(notes(back, '연합조명'), isEmpty);
      expect(notes(back, '연합흐림'), isEmpty);
    });

    test("표시 체크 '단체'를 끄거나 그 연합의 탭이 화면에 없으면 올림이 남아 있어도 줄을 옅게 하지 않는다", () async {
      final off = makeScene(Window(1560, 1700), groups: false);
      SceneMarks.of(off)
        ..hotCoal = coalUid('북녘 맹약')
        ..version += 1;
      final p = await drawn(off);
      expect(notes(p, '연합조명'), isEmpty);
      expect(notes(p, '연합흐림'), isEmpty);

      final stale = makeScene(Window(1560, 1700));
      SceneMarks.of(stale)
        ..hotCoal = 'sample-power/없는-연합'
        ..version += 1;
      expect(notes(await drawn(stale), '연합흐림'), isEmpty);
    });

    test("풍선 글: '연합'이라는 말과 구성 나라(위에서 아래로) — 띠 위가 아니라 여기에만", () async {
      final p = await drawn(makeScene(Window(1560, 1700)));
      expect(p.bands.coalTip(coalUid('북녘 맹약')), '북녘 맹약 — 연합 · 구성 가람 왕국 · 큰 뭍 제국 — 누르면 단체 창');
      expect(p.bands.coalTip('sample-power/없는-연합'), '');
    });

    test('뒤 장의 왼쪽 어깨는 앞 장 위로 솟은 3px만 찍는다 — 묶음을 중간에 내보내지 않고도 앞 장이 위', () async {
      final p = await drawn(makeScene(Window(1560, 1700)));
      // 탭 넷(겹 탭) · 탭마다 조각 8(뒤 장 4 + 앞 장 4)이 띠 층의 그림판 묶음에 한 번에 쌓였다가 걸음 끝에 한 번 나간다.
      expect(coalTabs(p).length, 4);
      expect(BandSprites.shouldersTall().fillL.height, BandSprites.shoulderTallH);
      expect(BandLayer.coalBackDy, lessThan(BandSprites.shoulderTallH));
    });
  });

  // 감독 원칙 "모든 글자 위 아래로는 적당한 공간이 있어야 해. 겹쳐보이잖아"와 그 안의 선택 "글자 한 단계 작게"(2026-10-13 — 줄 높이는 그대로):
  // 제 이름 탭 10 → 9 · 상국 탭과 겹 탭 9.5 → 8.5 · 단체 칸 9.5 → 8.5, 글줄은 위아래 선 사이의 가운데.
  // 틈은 글자 틀(글자 크기만큼의 높이 — 글줄 1.2배의 가운데)에서 잰다: 틀 윗변 = 글줄 윗변 + 크기 × .1 · 틀 아랫변 = 글줄 윗변 + 크기 × 1.1.
  // 꼬리표 갈래 E(2026-10-15): 띠 위 탭 줄이 없어져 제 이름(9)은 띠 안 **머리**의 가운데에 — 리메이크 2부 '두 장 ㄴ'부터 머리 = 이름 색줄 14(윗변 ~ +14 ·
  // 아랫변 1px은 색줄의 테) — 상국 탭 · 연합의 겹 탭(8.5)은
  // 높이 12의 **낮은 탭** 안에 선다 — 상국 탭은 받침 카드 윗변 위([윗변 − 17, 윗변 − 4]), 겹 탭의 앞 장은 띠 윗변 위([윗변 − 13, 윗변 + 1] —
  // 밑 1px은 띠 윗변의 테두리가 덮으므로 1px 높여 보이는 안이 띠 윗변까지 12).
  group('글자 위아래 틈 — 글자 한 단계 작게', () {
    const nameSize = 9.0, hostSize = 8.5, groupSize = 8.5;

    /// 글줄 윗변 [y]를 품은 줄의 띠 윗변 — 그 글이 [lo, hi](띠 윗변에서의 거리) 안에 서는 줄.
    double bandTopFor(TimelineScene s, double y, double lo, double hi) {
      for (int r = 0; r < s.layout.rowCount; r++) {
        final top = bandTopOf(s, r);
        if (y >= top + lo && y <= top + hi) return top;
      }
      fail('글줄 윗변 $y을 품은 줄이 없다');
    }

    test('머리의 제 이름(9)은 이름 색줄 14의 가운데 · 낮은 탭의 글(상국과 연합 8.5)은 탭 윗선 아래 · 밑변 위로 틈을 고르게 두고 선다', () async {
      expect(BandLayer.hostLook.size, hostSize);
      expect(G.head, 14);
      for (final w in [Window(1560, 1700), Window(1700, 1900)]) {
        final scene = makeScene(w);
        final p = await drawn(scene);
        final names = p.debugLabels.where((l) => l.kind == 'tab').toList(), hosts = p.debugLabels.where((l) => l.kind == 'hostTab').toList();
        expect(names, isNotEmpty);
        expect(hosts.any((l) => l.text.endsWith('제국')) && (w.y0 != 1560 || hosts.any((l) => l.text.endsWith('맹약'))), isTrue, reason: '상국 탭과 연합의 겹 탭이 모두 보이는 범위');
        // 글자 틀(크기만큼 — 글줄 1.2배의 가운데): 틀 윗변 = 글줄 윗변 + 크기 × .1 · 틀 아랫변 = 글줄 윗변 + 크기 × 1.1.
        void check(String text, double above, double below) {
          expect(above, greaterThanOrEqualTo(.5 - 1e-9), reason: '$text — 윗선과 글자 사이');
          expect(below, greaterThanOrEqualTo(.5 - 1e-9), reason: '$text — 글자와 아랫선 사이');
          expect((above - below).abs(), lessThanOrEqualTo(.5 + 1e-9), reason: '$text — 위아래 틈이 한쪽으로 쏠리지 않는다(위 $above · 아래 $below)');
        }

        for (final l in names) {
          // 이름 색줄 = 띠 윗변(테두리 1px) 아래 ~ 윗변 + 13(아랫변 테 1px — 몸통과 나눠 씀). 글자 틀의 가운데가 색줄의 가운데(윗변 + 7 = 구멍 높이).
          final top = bandTopFor(scene, l.at.dy, 0, G.head);
          expect(l.at.dy + nameSize * .6, closeTo(top + G.head / 2, 1e-6), reason: '${l.text} — 이름 색줄 14의 가운데');
          check(l.text, l.at.dy + nameSize * .1 - (top + 1), top + G.head - 1 - (l.at.dy + nameSize * 1.1));
          expect(l.at.dy + nameSize * .1 - (top + 1), greaterThanOrEqualTo(1), reason: '${l.text} — 띠 윗변 테두리와 글자 사이(1배에서 1px 넘게)');
          expect(top + G.head - 1 - (l.at.dy + nameSize * 1.1), greaterThanOrEqualTo(1), reason: '${l.text} — 글자와 색줄 아랫변 테 사이');
        }
        for (final l in hosts.where((l) => l.text.endsWith('제국'))) {
          // 상국 탭: 탭 밑 = 띠 윗변 − 받침 카드 5 + 1 · 탭 위 = 그 위 1 + 12. 안 = 윗선 1px 아래 ~ 탭 밑(카드와 한 칠로 이어진다).
          final top = bandTopFor(scene, l.at.dy, -BandLayer.sheetRise - TagLook.tabH, 0);
          final hBottom = top - BandLayer.sheetRise + 1, hTop = hBottom - 1 - TagLook.tabH;
          check(l.text, l.at.dy + hostSize * .1 - (hTop + 1), hBottom - (l.at.dy + hostSize * 1.1));
        }
        for (final l in hosts.where((l) => l.text.endsWith('맹약'))) {
          // 겹 탭의 앞 장: [윗변 − 13, 윗변 + 1]. 보이는 안 = 윗선 1px 아래 ~ 띠 윗변(밑 1px은 띠 윗변의 테두리 밑) — 12.
          final top = bandTopFor(scene, l.at.dy, -TagLook.tabH - 1, 0);
          check(l.text, l.at.dy + hostSize * .1 - (top - TagLook.tabH), top - (l.at.dy + hostSize * 1.1));
        }
      }
    });

    test('머리 이름의 폭은 9px로 잰 이름 그대로 — 탭의 어깨 · 안 여백 없이 맞히기 상자 · 단추 자리가 이름 끝에서 끝난다', () async {
      final scene = makeScene(Window(1700, 1900));
      final p = await drawn(scene);
      final tab = p.debugLabels.firstWhere((l) => l.kind == 'tab' && l.text == '가람 왕국');
      // 그리개의 글자 예산과 따로 잰다(새 글줄 재기는 장면마다 예산이 있다).
      final width = ParagraphText().widthOf('가람 왕국', const TextLook(nameSize, ui.FontWeight.w700, 0xff000000, spacing: -.1))!;
      final band = bandIdOf[listOf('periods').firstWhere((x) => x['name'] == '가람 왕국')['uid']]!;
      // 딱지가 없는 띠: 이름의 끝 = 글 왼쪽 + 9px로 잰 폭(소속 단추가 그 뒤 4px에 앉는다).
      expect(p.bands.headNameEnd[band], closeTo(tab.at.dx + width, .01));
      // 맞히기 상자 = [이름 왼쪽, 띠 윗변, 이름 끝, 띠 윗변 + 14(이름 색줄)] — 색줄의 가운데 줄에서 잰다.
      final left = tab.at.dx, right = tab.at.dx + width, y = bandTopOf(scene, garam) + G.head / 2;
      expect(p.bands.hitBands(right - .5, y)?.tab, isTrue);
      expect(p.bands.hitBands(right + .5, y)?.tab, isFalse, reason: '이름 끝 뒤는 띠 몸통');
      expect(p.bands.hitBands(left + .5, y)?.tab, isTrue);
      expect(p.bands.hitBands(left - .5, y)?.tab, isFalse, reason: '이름 앞(구멍 자리)은 띠 몸통');
    });

    test('단체 칸의 글(8.5)은 칸의 위아래 테두리에서 1px 넘게 떨어진다', () async {
      final scene = makeScene(Window(1700, 1900));
      final p = await drawn(scene);
      final cells = cellsOf(p).where((c) => c.kind == 8).toList();
      var seen = 0;
      for (final l in p.debugLabels.where((l) => l.kind == 'cell')) {
        for (final c in cells) {
          if (l.at.dx < c.l || l.at.dx > c.l + c.w || l.at.dy < c.t - 2 || l.at.dy > c.t + c.h) continue;
          seen++;
          final above = l.at.dy + groupSize * .1 - (c.t + 1), below = c.t + c.h - 1 - (l.at.dy + groupSize * 1.1);
          expect(above, greaterThanOrEqualTo(1), reason: '${l.text} — 칸 윗선과 글자 사이');
          expect(below, greaterThanOrEqualTo(1), reason: '${l.text} — 글자와 칸 아랫선 사이');
          expect(above, closeTo(below, 1e-6), reason: '${l.text} — 칸의 가운데');
        }
      }
      expect(seen, greaterThan(3), reason: '이름이 든 단체 칸');
    });
  });

  // 상국 표기 C(건의 8의 2번 · 2026-10-13 감독 선택): 속국 띠 뒤에 상국 빛깔의 뒤 장 · 상국 이름 탭은 관계가 끝나는 쪽에서 뒤 장 윗변 위로.
  group('상국 표기 C — 어긋난 겹장 + 끝 쪽 탭', () {
    test('뒤 장은 관계의 기간 그대로(옆으로 어긋나지 않음) · 상국 탭은 뒤 장의 평평한 윗변 안 — 오른쪽 끝이 뒤 장 끝에서 둥근 정도(10) 안', () async {
      final scene = makeScene(Window(1700, 1900));
      final p = await drawn(scene);
      final sheets = notes(p, '뒤장'), tabs = notes(p, '상국탭');
      expect(sheets, isNotEmpty);
      expect(tabs, isNotEmpty);
      for (final t in tabs) {
        final head = t.substring(0, t.lastIndexOf(' '));
        final xw = t.split(' ').last.split(',').map((v) => int.parse(v) / 10).toList();
        final sheet = sheets.firstWhere((s) => s.startsWith('$head '));
        final lr = sheet.split(' ')[head.split(' ').length].split(',').map((v) => int.parse(v) / 10).toList();
        final sheetEnd = lr[1];
        final right = xw[0] + xw[1];
        expect(BandLayer.sheetShift, 0, reason: '옆으로 어긋나지 않는다(감독 2026-10-14)');
        expect(right, closeTo(sheetEnd - BandLayer.sheetRadius, .05), reason: '$t — 뒤 장 끝의 둥근 모서리 바로 안쪽');
        expect(xw[0], greaterThanOrEqualTo(lr[0] + BandLayer.sheetRadius - .05), reason: '$t — 뒤 장 왼쪽 둥근 모서리보다 안쪽');
      }
    });

    test('조감에서는 뒤 장도 상국 탭도 없다', () async {
      final scene = makeScene(Window(1700, 1900));
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      scene.controller.setContentHeight(scene.layout.totalHeight);
      final p = await drawn(scene);
      expect(notes(p, '뒤장'), isEmpty);
      expect(notes(p, '상국탭'), isEmpty);
    });
  });

  group('올림 잇기(timeline_view.dart)', () {
    testWidgets('겹 탭에 커서를 올리면 그 연합이 켜지고 풍선 글이 뜨며, 떠나면 · 끌면 꺼진다', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = Window(1560, 1700);
      final scene = makeScene(w);
      addTearDown(scene.dispose);
      final tips = <String>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, atlasText: false, onAxisTip: (tip, x, y) => tips.add(tip)))));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      // 같은 장면을 따로 그려 탭의 자리를 읽는다(보기 부품의 그리개는 검사 기록을 켜지 않는다).
      final probe = TimelinePainter(scene, text: ParagraphText())..debug = true;
      for (int i = 0; i < 2; i++) {
        final recorder = ui.PictureRecorder();
        probe.paint(Canvas(recorder), const Size(1920, 1080));
        recorder.endRecording().dispose();
      }
      final tab = coalTabs(probe).firstWhere((t) => t.row == garam && t.name == '북녘 맹약');
      final at = Offset(tab.x + tab.w / 2, bandTopOf(scene, garam) - 5);
      final marks = SceneMarks.of(scene);
      expect(marks.hotCoal, isNull);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(900, 900));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(at);
      await tester.pump();
      expect(marks.hotCoal, coalUid('북녘 맹약'));
      expect(tips.last, '북녘 맹약 — 연합 · 구성 가람 왕국 · 큰 뭍 제국 — 누르면 단체 창');

      // 띠 몸통으로 내려가면 꺼진다(풍선도).
      await mouse.moveTo(at + const Offset(0, 60));
      await tester.pump();
      expect(marks.hotCoal, isNull);
      expect(tips.last, '');

      // 다시 올린 채 끌기 시작하면 꺼진다(웹 — 움직이는 동안은 올림이 없다).
      await mouse.moveTo(at);
      await tester.pump();
      expect(marks.hotCoal, isNotNull);
      await mouse.down(at);
      await mouse.moveTo(at + const Offset(40, 0));
      await tester.pump();
      expect(marks.hotCoal, isNull);
      expect(tips.last, '');
      await mouse.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 20));

      // 날짜 칸으로 올라가도 꺼진다.
      scene.controller.showRange(w.tileX(w.m0), w.tileX(w.m1));
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      final again = Offset(tab.x + tab.w / 2, bandTopOf(scene, garam) - 5);
      await mouse.moveTo(again);
      await tester.pump();
      expect(marks.hotCoal, isNotNull);
      await mouse.moveTo(const Offset(400, 20)); // 날짜 칸
      await tester.pump();
      expect(marks.hotCoal, isNull);
    });
  });
}
