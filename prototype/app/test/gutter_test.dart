import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagLook;
import 'package:archive_prototype/scene/paint/gutter.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/paint/sphere_lines.dart' show SpherePersonBand;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/row_labels.dart';
import 'package:archive_prototype/scene/ruler.dart' show minuteOfYear;
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart' show twoTrackLayout;
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 왼쪽 칸(리메이크 2부 — 목업 서고 `mock/themes/blend.js`의 gutter)의 검사: 폭 240 하나 · 트랙은 가는 세로 선(x 23) + 세로 이름(가운데 31 · 한 자 12) ·
// 그릇은 폴더 그림(44 + 깊이 × 10) + 이름(+17) · 줄은 작은 꼬리표 그림(47 + 깊이 × 10) + 보는 범위에 든 그 줄의 띠 이름(+16 · ' · '로 이음).
// 옛 민족 칸 · 민족 딱지 · 연도 · 부제 · 노선 표시 · 분류 색 점은 목업에 없어 빠졌다(그것을 보던 검사도 함께 뺐다).

const m = 1000000.0;
final ppm = 32 / bucketMinutes(9);
double px(double pixels) => pixels / ppm;

Map<String, dynamic> row(
  int id, {
  int kind = 0,
  bool groupStart = false,
  List<int> cats = const [],
  int phase = 0,
  int rank = 0,
  int fig = 0,
  int dep = 0,
  int zones = 0,
  int hem = 0,
}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': 23, 'lead_top': 41,
  'cab_top': 64, 'text_top': 84, 'text_lines': 1, 'rail_top': 105, 'organ_top': 127,
  'kind': kind, 'group_start': groupStart ? 1 : 0, 'scope_pad': 0, 'phase': phase, 'rank': rank,
  'cats': cats, 'fig': fig, 'fig_wide': fig, 'dep': dep, 'zones': zones, 'hem': hem,
};

Map<String, dynamic> group(int depth, int first, int count, String name, int color, {int kind = 0}) =>
    {'depth': depth, 'first': first, 'count': count, 'name': name, 'color': color, 'kind': kind};

/// 대범위 모아 보기 하나(계약 3-2절) — 줄 2 · 4 · 6을 한 가지로 모은다(가지의 줄 번호는 이어지지 않는다).
/// 사슬은 −1 → 0 → 1 → 2 → 4 → 6 → 3 → 5로 이어진다.
List<Map<String, dynamic>> scopeVariant() => [
  {
    'id': 1, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '빈 왕좌의 할거',
    'rows': [
      {'row': 2, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
      {'row': 4, 'after': 2, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      {'row': 6, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      {'row': 3, 'after': 6, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
      {'row': 5, 'after': 3, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
    ],
    'groups': [
      {'key': '__scope:s1', 'depth': 0, 'name': '빈 왕좌의 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [2, 4, 6]},
    ],
  },
];

/// 줄 2~4를 차례 그대로 모으는 대범위(폴더 검사용 — 그릇의 줄이 이어져 있다). 사슬은 −1 → 0 → … → 6 그대로다.
List<Map<String, dynamic>> folderVariant() => [
  {
    'id': 1, 'key': 'scope:s2', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's2', 'name': '세 나라 할거',
    'rows': [
      {'row': 2, 'after': 1, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 1},
      {'row': 3, 'after': 2, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      {'row': 4, 'after': 3, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      {'row': 5, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
    ],
    'groups': [
      {'key': '__scope:s2', 'depth': 0, 'name': '세 나라 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [2, 3, 4]},
    ],
  },
];

/// 줄 2 ~ 4를 모으던 그릇 s2(위 [folderVariant])의 선반 변형(kind 6 · 계약 2-4절 · variants_layout_test의 선반 시험 꼴): 그 셋을 빠지는 줄(after −2)로 두고
/// 새 줄 7 · 8(변형 2의 줄 — [layoutJson]의 `more`로 더함)을 줄 1 뒤 가지로 다시 쌓는다 · 숨긴 구성원 둘.
List<Map<String, dynamic>> shelfVariant() => [
  {
    'id': 2, 'key': 'shelf:s2', 'kind': 6, 'track': 1, 'band': 0, 'uid': 's2', 'name': '세 나라 할거',
    'rows': [
      for (final r in [2, 3, 4]) {'row': r, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      {'row': 7, 'after': 1, 'ord': 0, 'new': 1, 'scope_pad': 16, 'group_start': 1},
      {'row': 8, 'after': 7, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
      {'row': 5, 'after': 8, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
    ],
    'groups': [
      {'key': '__scope:s2', 'depth': 0, 'name': '세 나라 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [7, 8]},
    ],
    'shelf': [
      {'uid': 'h/a', 'name': '검은물 의병', 'color': 0x8a9a7b, 'start': 0, 'end': 0, 'ord': 5},
      {'uid': 'h/b', 'name': '남강 임시정부', 'color': 0x8a9a7b, 'start': 0, 'end': 0, 'ord': 6},
    ],
  },
];

/// 월흔해 '유리해안'과 같은 꼴: 민족 3단계 · 줄 7개 · 둘째 줄에 분류별 글줄 8개. [more]는 그 뒤에 붙는 줄(변형의 새 줄 따위).
Map<String, dynamic> layoutJson({List<Map<String, dynamic>> variants = const [], List<Map<String, dynamic>> more = const []}) => {
  'packs': [{'id': 1, 'name': '월흔해 연대기', 'events': 9}],
  'categories': [
    for (final (i, c) in [0xabb3c9, 0xd4a39b, 0x9dbea8, 0xd7c18e, 0xbbacc8, 0xbbacc8, 0x9dbea8, 0xa0bcc5].indexed)
      {'id': i + 1, 'key': 'c$i', 'name': '분류 $i', 'color': c},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '유리해안', 'color': 0xa0bcc5,
      'dynasty': 1, 'leader': 1, 'cabinet': 1, 'organ': 1, 'rail_levels': 3,
      'rows': [
        row(0, groupStart: true),
        row(1, groupStart: true, cats: [0, 1, 2, 3, 4, 5, 6, 7], phase: 3, rank: 1, fig: 1, dep: 64, zones: 11, hem: 1),
        for (int i = 2; i < 7; i++) row(i),
        ...more,
      ],
      'groups': [
        group(0, 0, 1, '문화', 0xa0bcc5, kind: 1),
        group(0, 1, 6, '월흔해의 백성', 0xdab195),
        group(1, 1, 6, '등불사람', 0xa0bcc5),
        group(2, 1, 6, '해민', 0xa0bcc5),
      ],
    },
  ],
  'epochs': [],
  'variants': variants,
};

/// 줄 하나의 후보 띠(계약 6-8절).
Map<String, dynamic> label(String uid, String name, int start, int end,
        {int color = 0xdab195, int cap = 1, String years = '240–480', int row = 1, int kind = 0, int count = 0, int depth = -1}) =>
    {
      'period': uid, 'track': 0, 'row': row, 'kind': kind, 'name': name, 'years': years, 'color': color, 'start': start, 'end': end,
      'cap': cap, 'member': 0, 'lanes': <int>[], 'count': count, 'depth': depth,
    };

(TimelineScene, TimelinePainter) make({
  Map<int, List<Map<String, dynamic>>> labels = const {},
  Uint8List? tile,
  int density = 0,
  double height = 1080,
  List<Map<String, dynamic>> variants = const [],
  List<Map<String, dynamic>> more = const [],
}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, height)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(1000);
  final origin = tileOrigin(9, 1).toDouble();
  final empty = TileBuilder(level: 9, x: 1, chunk: 0).build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(layoutJson(variants: variants, more: more))..reduceMotion = true,
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? (tile ?? empty) : TileBuilder(level: level, x: x, chunk: chunk).build(),
    ask: (query) async {
      // 빈 줄 접기(다른 층)가 함께 묻는다 — 이 검사에서는 모든 줄이 펴져 있어야 한다.
      if (query['op'] == 'rows_near') {
        final all = [for (int r = 0; r < 7 + more.length; r++) r];
        return {'near': all, 'far': all};
      }
      if (query['op'] != 'row_labels') return {};
      return {
        'labels': [
          for (final r in (query['rows'] as List).cast<int>()) {'row': r, 'items': labels[r] ?? const <Map<String, dynamic>>[]},
        ],
      };
    },
  );
  if (density != 0) {
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: density));
    controller.setContentHeight(scene.layout.totalHeight);
  }
  scene.applyLayoutToView();
  controller.resize(1920, height);
  controller.showRange(origin, origin + (1920 - scene.layout.gutterWidth) / ppm);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter, {double height = 1080}) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(1920, height));
  recorder.endRecording().dispose();
}

/// 타일 · 줄 이름 자료 · 글자 폭이 모두 준비될 때까지 장면을 돌린다.
Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    paint(painter, height: scene.controller.view.height);
    await pumpEventQueue();
    scene.tick(16);
  }
  paint(painter, height: scene.controller.view.height);
}

/// 한 장면을 그려 RGBA 바이트로 읽는다(1920 × 1080).
Future<ByteData> pixelsOf(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  picture.dispose();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return bytes;
}

/// 한 장면을 그려 [area] 안에서 가장 어두운 점의 밝기(R + G + B)를 읽는다 — 글의 먹이 얼마나 짙은가.
Future<int> darkestIn(TimelinePainter painter, Rect area) async {
  final bytes = await pixelsOf(painter);
  int darkest = 765;
  for (int y = area.top.floor(); y < area.bottom.ceil(); y++) {
    for (int x = area.left.floor(); x < area.right.ceil(); x++) {
      final at = (y * 1920 + x) * 4;
      darkest = math.min(darkest, bytes.getUint8(at) + bytes.getUint8(at + 1) + bytes.getUint8(at + 2));
    }
  }
  return darkest;
}

List<DebugLabel> of(TimelinePainter painter, String kind) => [for (final l in painter.debugLabels) if (l.kind == kind) l];

/// 줄 이름(11 굵게)의 글자 폭을 잴 때 쓰는 꼴 — 폭은 크기 · 굵기로만 잰다(색은 상관없다).
const rowLook = TextLook(GutLook.rowSize, ui.FontWeight.w700, 0xff000000);

/// 이름 색줄(`G.head` 14 — 리메이크 2부 두 장 꼬리표의 윗장)의 세로 가운데 — 띠 위 + min(높이, 14)/2 − .5(왼쪽 칸이 쓰는 식 그대로).
double rowMid(TimelineScene scene, int r) {
  final layout = scene.layout, geo = layout.geo(r);
  final top = scene.controller.view.yOf(layout.rowTop(r) + geo.bandTop);
  return top + math.min(geo.height - geo.bandTop, G.head) / 2 - .5;
}

/// 세로 가운데 [mid]에 놓인 [size] 글의 글자 상자 위(왼쪽 칸이 쓰는 식 그대로).
double textTop(double mid, double size) => Gut.textTopAt(mid - size * Gut.lineRatio / 2, size * Gut.lineRatio, size);

void main() {
  test('이름 줄임은 뜻이 남는 차례로 — 괄호 · 민족/족 · 첫 글자', () {
    expect(shortNames('한(삼한)'), ['한(삼한)', '한']);
    expect(shortNames('흉노족'), ['흉노족', '흉노', '흉']);
    expect(shortNames('초기 유력 이민족'), ['초기 유력 이민족', '초기']);
    expect(shortNames('여진-만주족'), ['여진-만주족', '여진']);
    // 명세 05의 2.2절 실측: 조감(민족 칸 높이 14)에서 '문화'는 한 글자 '문'만 든다.
    expect(shortName('문화', (t) => t.runes.length * Gut.peopleFits + 2 <= 14), '문');
    expect(shortName('문화', (t) => t.runes.length * Gut.peopleFits + 2 <= 8), '');
    expect(shortName('유리해안', (t) => t.runes.length * Gut.trackFits + 4 <= 620), '유리해안');
  });

  test('줄 이름은 보는 때를 품은 띠, 없으면 화면에 가장 넓게 걸친 띠', () {
    final labels = RowLabels()
      ..accept({
        1: [
          const RowLabel(period: 'a', name: '앞 나라', start: 0, end: 100),
          const RowLabel(period: 'b', name: '뒤 나라', start: 100, end: 400),
        ],
        2: [const RowLabel(period: 'c', kind: RowLabel.common, name: '그 밖')],
      });
    double xOf(num at) => 240 + at.toDouble();
    // 200은 뒤 나라가 품는다.
    expect(labels.pick(1, at: 200, xOf: xOf, left: 240, right: 1920)?.period, 'b');
    // 경계 100은 두 띠가 모두 품는다 — 지금 연표처럼 뒤의 띠가 이긴다.
    expect(labels.pick(1, at: 100, xOf: xOf, left: 240, right: 1920)?.period, 'b');
    // 품는 띠가 없으면 화면에 가장 넓게 걸친 띠.
    expect(labels.pick(1, at: 900, xOf: xOf, left: 240, right: 1920)?.period, 'b');
    expect(labels.pick(2, at: 0, xOf: xOf, left: 240, right: 1920)?.name, '그 밖');
    // 물어본 적이 없는 줄은 빈 줄(색 점만).
    expect(labels.pick(5, at: 0, xOf: xOf, left: 240, right: 1920), isNull);
  });

  test('왼쪽 칸의 가로 자리 — 칸 240 하나 · 트랙 세로 이름은 가운데 31 · 누름은 트랙 18~40 · 줄 44~239(민족 칸 없음)', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(labels: {
      0: [label('p-0', '물가 사람들', at, at + 100000, row: 0)],
      1: [label('p-1', '유리항 물길왕국', at, at + 100000)],
    });
    expect(scene.layout.peopleDepth, 3);
    expect(scene.layout.gutterWidth, 240, reason: '민족 단이 셋이어도 왼쪽 칸은 목업 GUT 240 하나');
    expect(G.gutter, GutLook.width);
    await settle(scene, painter);
    // 트랙 이름: 세로 글 10px — 글자의 자리 폭을 가운데 31의 em 상자 오른쪽(36)에 붙이고, 한 자에 12씩 내려간다.
    final track = of(painter, 'track');
    expect(track.map((l) => l.text).join(), '유리해안');
    expect(track.first.at.dx, closeTo(GutLook.trackX - GutLook.trackSize / 2, 1.5));
    expect(track[1].at.dy - track[0].at.dy, closeTo(GutLook.trackPitch, .001));
    // 세로 이름은 트랙 높이의 가운데에 선다.
    final v = scene.controller.view, layout = scene.layout;
    final y0 = v.yOf(layout.trackTop(0)), y1 = y0 + layout.trackHeight(0);
    expect(track.first.at.dy, closeTo((y0 + y1) / 2 - 4 * GutLook.trackPitch / 2, .01));
    // 누름: 트랙 이름(18~40)은 트랙 접기, 줄은 꼬리표 왼쪽 3 앞(44)부터 칸 오른쪽 끝 앞(239)까지.
    final y = rowMid(scene, 1);
    expect(painter.gutter.hitTest(GutLook.trackHitLeft, y)?.kind, GutterHitKind.trackName);
    expect(painter.gutter.hitTest(GutLook.trackHitRight - .5, y)?.kind, GutterHitKind.trackName);
    expect(painter.gutter.hitTest(10, y), isNull, reason: '세로 선 왼쪽은 비어 있다');
    expect(painter.gutter.hitTest(42, y), isNull, reason: '트랙 이름과 줄 꼬리표 사이');
    // 옛 민족 칸 자리(26 · 48 · 70)는 이제 트랙 이름이거나 줄 이름의 누름이다.
    for (final x in [GutLook.rowX - 3, 48.0, 70.0, 238.5]) {
      final hit = painter.gutter.hitTest(x, y);
      expect(hit?.kind, GutterHitKind.row, reason: 'x $x');
      expect(hit?.row, 1);
    }
    expect(painter.gutter.hitTest(239, y), isNull, reason: '칸 오른쪽 테(239)는 누름 밖');
    expect(of(painter, 'people'), isEmpty, reason: '민족 칸은 없다');
  });

  test('줄 이름 — 작은 꼬리표 47 · 이름 63(11 굵게) · 이름 색줄 14의 세로 가운데 · 누르면 그 띠', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(labels: {
      1: [label('p-1', '유리항 물길왕국', at, at + px(900).round())],
    });
    await settle(scene, painter);
    final names = of(painter, 'rowName');
    expect(names.length, 1);
    expect(names.first.text, '유리항 물길왕국');
    expect(names.first.at.dx, GutLook.rowX + GutLook.rowText);
    expect(names.first.at.dy, closeTo(textTop(rowMid(scene, 1), GutLook.rowSize), .01));
    // 밑줄은 브라우저가 반내림해 정수 px에 놓는다(크기별 실측) — 글 세로 자리의 식이 그대로 쓴다.
    expect(Gut.baselineIn(18.75, 12.5), 14);
    expect(Gut.baselineIn(16.5, 11), 13);
    expect(Gut.baselineIn(15.75, 10.5), 12);
    expect(Gut.baselineIn(20.25, 13.5), 16);
    expect(Gut.baselineIn(9.5, 9.5), 8);
    // 작은 꼬리표 그림(12 × 8)의 세로 가운데 = 그 줄 이름 색줄의 가운데(구멍 높이 TagLook.holeY 7 — 두 장 꼬리표의 윗장 14의 절반).
    // 그림의 오른쪽 테(x 47 + 12 − 1)를 세로로 훑어 바탕과 다른 점의 위 · 아래를 잰다.
    final bytes = await pixelsOf(painter);
    final bandTop = scene.controller.view.yOf(scene.layout.rowTop(1) + scene.layout.geo(1).bandTop);
    expect(G.head, 14);
    const edgeX = GutLook.rowX + GutLook.tagW - 1;
    int pixel(int x, int y) => bytes.getUint32((y * 1920 + x) * 4);
    final paper = pixel(edgeX.toInt(), (bandTop - 6).round());
    final inked = [for (int y = (bandTop - 6).round(); y < (bandTop + G.head + 6).round(); y++) if (pixel(edgeX.toInt(), y) != paper) y];
    expect(inked, isNotEmpty, reason: '작은 꼬리표 그림이 그려져 있다');
    expect(inked.last + 1 - inked.first, GutLook.tagH, reason: '그림 높이 8 — $inked');
    expect((inked.first + inked.last + 1) / 2, closeTo(bandTop + TagLook.holeY, .5), reason: '그림 가운데 = 이름 색줄 가운데(띠 위 $bandTop + 7)');
    // 연도 · 부제는 목업에 없다.
    expect(of(painter, 'rowYears'), isEmpty);
    expect(of(painter, 'rowSub'), isEmpty);
    // 누르면 그 띠의 상세 — 노선 표시 · 분류 색 점(옛 오른쪽 끝 227)도 없어 칸 끝까지 줄 이름이다.
    final y = rowMid(scene, 1);
    for (final x in [50.0, 150.0, 230.0]) {
      final hit = painter.gutter.hitTest(x, y);
      expect(hit?.kind, GutterHitKind.row, reason: 'x $x');
      expect(hit?.uid, 'p-1');
    }
  });

  test('줄 이름은 보는 범위에 든 그 줄의 띠 이름을 시작 차례로 · 로 잇는다 — 같은 이름은 한 번, 범위 밖은 뺀다', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(labels: {
      1: [
        label('p-b', '뒤 나라', at + px(300).round(), at + px(500).round()),
        label('p-a', '앞 나라', at + px(100).round(), at + px(300).round()),
        label('p-c', '앞 나라', at + px(500).round(), at + px(700).round()),
        // 그림 영역(1,680px) 밖 — 오른쪽 뒤에서 시작한다.
        label('p-x', '먼 나라', at + px(5000).round(), at + px(6000).round()),
      ],
    });
    await settle(scene, painter);
    expect(of(painter, 'rowName').map((l) => l.text), ['앞 나라 · 뒤 나라']);
  });

  test('들 폭에 맞추기 — 칸 오른쪽 10 앞까지, 넘치면 들어가는 데까지 자르고 …', () async {
    final at = tileOrigin(9, 1);
    final (short, shortPainter) = make(labels: {
      1: [label('p-1', '해', at, at + 100000)],
    });
    await settle(short, shortPainter);
    expect(of(shortPainter, 'rowName').map((l) => l.text), ['해']);

    const long = '아주아주 긴 이름의 나라 이름이 길고 더 길다';
    final (wide, longPainter) = make(labels: {
      1: [label('p-1', long, at, at + 100000)],
    });
    await settle(wide, longPainter);
    final names = of(longPainter, 'rowName');
    expect(names.length, 1);
    // 들 폭 = 240 − 10 − 63 = 167.
    const room = GutLook.width - GutLook.rightPad - (GutLook.rowX + GutLook.rowText);
    expect(longPainter.text.widthOf(long, rowLook), greaterThan(room), reason: '검사 글꼴로도 다 들지 않는 이름');
    expect(names.first.text, endsWith(GutLook.more));
    expect(long, startsWith(names.first.text.substring(0, names.first.text.length - 1).trimRight()));
    expect(longPainter.text.widthOf(names.first.text, rowLook), lessThanOrEqualTo(room));
    expect(names.first.at.dx, GutLook.rowX + GutLook.rowText);
  });

  test('휴대폰은 왼쪽 칸 160 — 보기 · 줄 이름의 들 폭 · 누름이 함께 좁아진다(감독 2026-10-16)', () async {
    SceneView.phone = true;
    addTearDown(() => SceneView.phone = false);
    final at = tileOrigin(9, 1);
    const long = '아주아주 긴 이름의 나라 이름이 길고 더 길다';
    final (scene, painter) = make(labels: {
      1: [label('p-1', long, at, at + 100000)],
    });
    expect(scene.layout.gutterWidth, 160);
    await settle(scene, painter);
    expect(scene.controller.view.left, SceneView.phoneGutter, reason: '그림판은 160부터');
    // 들 폭 = 160 − 10 − 63 = 87 — 이름은 그 안에서 자르고 …
    final room = SceneView.phoneGutter - GutLook.rightPad - (GutLook.rowX + GutLook.rowText);
    final names = of(painter, 'rowName');
    expect(names.single.text, endsWith(GutLook.more));
    expect(painter.text.widthOf(names.single.text, rowLook), lessThanOrEqualTo(room));
    final y = rowMid(scene, 1);
    expect(painter.gutter.hitTest(SceneView.phoneGutter - 1.5, y)?.kind, GutterHitKind.row);
    expect(painter.gutter.hitTest(SceneView.phoneGutter - 1, y), isNull, reason: '칸 오른쪽 테(159)는 누름 밖');
  });

  test('접힌 트랙 — 가로 이름 + ▸ 하나(11 굵게 · 왼쪽 44), 세로 이름 · 줄 이름 없음, 왼쪽 칸 전체가 펴는 단추', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(labels: {
      1: [label('p-1', '유리항 물길왕국', at, at + 100000)],
    });
    scene.layout.foldTrack(scene.layout.tracks[0].id, true);
    await settle(scene, painter);
    final folded = of(painter, 'foldName');
    expect(folded.map((l) => l.text), ['유리해안 ▸'], reason: '접힌 트랙의 이름은 줄이지 않는다');
    expect(folded.first.at.dx, GutLook.boxX);
    final v = scene.controller.view, layout = scene.layout;
    final y0 = v.yOf(layout.trackTop(0)), y1 = y0 + layout.trackHeight(0);
    expect(folded.first.at.dy, closeTo(textTop((y0 + y1) / 2, GutLook.rowSize), .01));
    // 세로 글 이름 · 줄 이름 · 옛 '펼치기 ▸' 글은 그리지 않는다.
    expect(of(painter, 'track'), isEmpty);
    expect(of(painter, 'rowName'), isEmpty);
    expect(of(painter, 'foldHint'), isEmpty);
    // 머리글 전체가 펼치기 단추다(왼쪽 칸 0~239).
    for (final x in [2.0, 120.0, 238.0]) {
      expect(painter.gutter.hitTest(x, (y0 + y1) / 2)?.kind, GutterHitKind.trackName, reason: 'x $x');
    }
  });

  test('접힌 민족 줄은 그 묶음 이름 뒤에 ▸이고, 누르면 그 묶음을 편다(민족 칸 대신 줄 이름 자리에서)', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(labels: {
      1: [
        label('p-1', '유리항 물길왕국', at, at + 100000),
        label('', '월흔해의 백성', 0, 0, kind: RowLabel.foldedGroup, count: 6, cap: 0, years: '', depth: 0),
      ],
    });
    // 트랙 0의 묶음 1 = '월흔해의 백성'(줄 1~6)
    final track = scene.layout.tracks[0];
    scene.layout.foldGroup(track, track.groups[1], true);
    await settle(scene, painter);
    expect(of(painter, 'rowName').map((l) => l.text), contains('월흔해의 백성 ▸'));
    expect(of(painter, 'rowName').map((l) => l.text), isNot(contains('유리항 물길왕국')), reason: '접힌 줄은 접힘용 후보를 쓴다');
    expect(of(painter, 'peopleFolded'), isEmpty, reason: '옛 민족 칸의 가로 글은 없다');
    final y = rowMid(scene, 1);
    for (final x in [GutLook.rowX - 3, 120.0, 238.0]) {
      final hit = painter.gutter.hitTest(x, y);
      expect(hit?.kind, GutterHitKind.people, reason: 'x $x');
      expect([hit?.track, hit?.row, hit?.group], [0, 1, 1]);
    }
  });

  test('대범위 가지의 줄은 번호가 이어지지 않아도 제 자리에 제 줄 이름이 선다(계약 3-2절 · 점선 칸 없음)', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(
      // 공용3px 틈으로 줄이 커져도 가지의 세 줄 전체를 화면 안에서 검사한다.
      height: 2400,
      variants: scopeVariant(),
      labels: {for (int r = 0; r < 7; r++) r: [label('p-$r', '나라 $r', at, at + 100000, row: r)]},
    );
    final layout = scene.layout;
    expect(layout.gutterWidth, 240, reason: '가지를 켜도 왼쪽 칸의 폭은 그대로다');
    expect(layout.variantGroups(0), isEmpty, reason: '켜기 전에는 가지가 없다');

    expect(layout.openScope('s1', true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    final branch = layout.variantGroups(0).single;
    expect(branch.rows, [2, 4, 6], reason: '가지가 드는 줄 — 번호가 이어지지 않는다');
    // 타일에 그릇이 실려 오지 않았으니 폴더도 없다 — 가지의 줄은 들이지 않고 제 이름 그대로.
    expect(of(painter, 'gutFolder'), isEmpty);
    final names = of(painter, 'rowName');
    for (final r in [2, 4, 6]) {
      final hit = painter.gutter.hitTest(80, rowMid(scene, r));
      expect(hit?.kind, GutterHitKind.row, reason: '줄 $r');
      expect([hit?.row, hit?.uid], [r, 'p-$r']);
      final name = names.firstWhere((l) => l.text == '나라 $r');
      expect(name.at.dx, GutLook.rowX + GutLook.rowText);
      expect(name.at.dy, closeTo(textTop(rowMid(scene, r), GutLook.rowSize), .01));
    }
    expect(of(painter, 'people'), isEmpty, reason: '옛 점선 칸의 세로 글은 없다');
    expect(layout.openScope('s1', false), isTrue);
    await settle(scene, painter);
    expect(painter.gutter.hitTest(80, rowMid(scene, 2))?.uid, 'p-2');
  });

  test('대범위 가지를 접으면 첫 줄 하나에 가지의 접힘용 후보 + ▸ — 누르면 그 가지가 알려진다', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(
      // 공용3px 틈으로 줄이 커져도 가지의 세 줄 전체를 화면 안에서 검사한다.
      height: 2400,
      variants: scopeVariant(),
      labels: {
        for (int r = 0; r < 7; r++)
          r: [
            label('p-$r', '나라 $r', at, at + 100000, row: r),
            // 그 변형을 켰을 때만 쓰는 접힘용 후보(계약 6-8절 · 내보내기가 `variant`를 달아 싣는다).
            if (r == 2)
              {...label('', '빈 왕좌의 할거', 0, 0, row: 2, kind: 2, count: 3, depth: 0, color: 0xd4a39b), 'group': '__scope:s1', 'variant': 'scope:s1'},
          ],
      },
    );
    final layout = scene.layout;
    layout.openScope('s1', true);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect(of(painter, 'rowName').map((l) => l.text), contains('나라 2'), reason: '가지가 펴져 있으면 제 띠 이름');

    expect(layout.foldVariantGroup(0, '__scope:s1', true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    final texts = of(painter, 'rowName').map((l) => l.text);
    // 합쳐진 줄(가지의 첫 줄 2)의 이름은 가지 이름 뒤에 ▸ — 옛 부제 '정권 3개 · 펼치기 ▸'는 없다.
    expect(texts, contains('빈 왕좌의 할거 ▸'));
    expect(texts, isNot(contains('나라 4')), reason: '줄 4 · 6은 합쳐져 숨는다');
    expect(texts, isNot(contains('나라 6')));
    expect(texts, containsAll(['나라 3', '나라 5']), reason: '가지에 들지 않은 줄은 그대로');
    expect(of(painter, 'rowSub'), isEmpty);
    // 줄 이름 자리를 누르면 그 가지가 알려진다(총괄이 이것으로 접고 편다).
    final hit = painter.gutter.hitTest(80, rowMid(scene, 2));
    expect(hit?.kind, GutterHitKind.people);
    expect([hit?.track, hit?.row, hit?.group, hit?.uid], [0, 2, -1, '__scope:s1']);
  });

  test('켠 대범위가 타일에 실려 오면 폴더(그림 44 · 이름 61)가 서고 안의 줄은 한 단(10) 들인다 — 누르면 펼침 ↔ 접힘', () async {
    final at = tileOrigin(9, 1);
    // 그릇(구역 23): 줄 2 ~ 4 · 구성 띠 셋(폴더 라벨의 수).
    final tile = TileBuilder(level: 9, x: 1, chunk: 0)..item(ScopeLayer.secScope, 1, 2, px(0), px(900), row2: 4, name: '세 나라 할거', color: 0xd4a39b, b: 3);
    final (scene, painter) = make(
      height: 2400,
      variants: folderVariant(),
      tile: tile.build(),
      labels: {for (int r = 0; r < 7; r++) r: [label('p-$r', '나라 $r', at, at + 100000, row: r)]},
    );
    final layout = scene.layout;
    expect(layout.openScope('s2', true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect(layout.scopeStateOf('s2'), ScopeState.open);

    final folder = of(painter, 'gutFolder');
    expect(folder.map((l) => l.text), ['세 나라 할거']);
    expect(folder.single.at.dx, GutLook.boxX + GutLook.boxText);
    expect(of(painter, 'gutFolderCount'), isEmpty, reason: '펼친 폴더에는 띠 수를 적지 않는다');
    // 폴더 이름의 세로 가운데 = 그릇 위 + 11(그릇 위 = 첫 줄의 띠 위 − 줄 위 틈 − 폴더 머리 21).
    final v = scene.controller.view;
    final boxTop = layout.rowTop(2) + layout.geo(2).bandTop - layout.tabOf(2) - G.folderHead;
    final cy = (v.yOf(boxTop) + GutLook.boxMid).roundToDouble();
    expect(folder.single.at.dy, closeTo(textTop(cy, GutLook.rowSize), .01));
    // 누르면 접는다(바꿀 상태 2 = 접힘).
    final hit = painter.gutter.hitTest(120, cy);
    expect(hit?.kind, GutterHitKind.folder);
    expect([hit?.uid, hit?.row], ['s2', 2]);
    // 그릇 안의 줄(2 ~ 4)은 한 단 들이고(꼬리표 57 · 이름 73), 밖의 줄은 그대로(63).
    final names = {for (final l in of(painter, 'rowName')) l.text: l.at.dx};
    for (final r in [2, 3, 4]) {
      expect(names['나라 $r'], GutLook.rowX + GutLook.step + GutLook.rowText, reason: '줄 $r');
      expect(painter.gutter.hitTest(GutLook.rowX + GutLook.step - 3, rowMid(scene, r))?.row, r);
    }
    for (final r in [0, 1, 5, 6]) {
      expect(names['나라 $r'], GutLook.rowX + GutLook.rowText, reason: '줄 $r');
    }

    // 접으면(가지를 접은 것과 같다) 폴더 이름 뒤에 띠 수가 붙고, 안의 줄 이름은 폴더 하나로 갈음해 적지 않는다.
    expect(layout.foldVariantGroup(0, '__scope:s2', true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect(layout.scopeStateOf('s2'), ScopeState.closed);
    final closed = of(painter, 'gutFolder').single;
    final count = of(painter, 'gutFolderCount');
    expect(count.map((l) => l.text), ['3']);
    expect(count.single.at.dx, closeTo(closed.at.dx + painter.text.widthOf('세 나라 할거', rowLook)! + GutLook.countGap, .01));
    final texts = of(painter, 'rowName').map((l) => l.text);
    for (final r in [2, 3, 4]) {
      expect(texts, isNot(contains('나라 $r')), reason: '줄 $r');
    }
    expect(texts, containsAll(['나라 0', '나라 1', '나라 5', '나라 6']));
    final boxTop2 = layout.rowTop(2) + layout.geo(2).bandTop - layout.tabOf(2) - G.folderHead;
    final cy2 = (v.yOf(boxTop2) + GutLook.boxMid).roundToDouble();
    final reopen = painter.gutter.hitTest(120, cy2);
    expect(reopen?.kind, GutterHitKind.folder);
    expect([reopen?.uid, reopen?.row], ['s2', 1], reason: '바꿀 상태 1 = 펼침');
  });

  test('선반 그릇(과제 7 걸음 4): 폴더는 다시 지은 가지 줄에 서고 펼친 폴더처럼 이름만 · 누르면 접음 — 수는 접힌 폴더에만, 접힘은 선반 변형을 꺼 b(그릇 전체 수) 그대로', () async {
    final at = tileOrigin(9, 1);
    // 선반을 켠 타일: 그릇(구역 23 — 가지 줄 7 ~ 8 · b = 제 줄에 남은 수 3 · text2에 uid — 가지 줄이 바뀌어도 그릇을 찾게).
    final tile = TileBuilder(level: 9, x: 1, chunk: 0)
      ..item(ScopeLayer.secScope, 1, 7, px(0), px(900), row2: 8, name: '세 나라 할거', color: 0xd4a39b, b: 3, text2: 's2\u001f시대');
    final (scene, painter) = make(
      height: 2400,
      variants: [...folderVariant(), ...shelfVariant()],
      more: [for (final r in [7, 8]) {...row(r), 'variant': 2}],
      tile: tile.build(),
      labels: {for (int r = 0; r < 9; r++) r: [label('p-$r', '나라 $r', at, at + 100000, row: r)]},
    );
    final layout = scene.layout;
    expect(layout.setViewState(layout.viewForScopeState('s2', ScopeState.shelf)), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect([layout.scopeStateOf('s2'), layout.isShelfOn('s2'), layout.variantKeys, layout.shelfOf('s2').length], [ScopeState.shelf, true, ['shelf:s2'], 2]);

    final folder = of(painter, 'gutFolder');
    expect(folder.map((l) => l.text), ['세 나라 할거']);
    expect(of(painter, 'gutFolderCount'), isEmpty, reason: '선반은 펼친 꼴 — 왼쪽 칸은 접힌 폴더에만 수를 적는다');
    // 폴더 이름은 다시 지은 가지의 첫 줄 7 위(그릇 위 + 11) · 안의 줄(7 · 8)만 한 단 들이고 빠진 줄 2 ~ 4는 없다.
    final v = scene.controller.view;
    final cy = (v.yOf(layout.rowTop(7) + layout.geo(7).bandTop - layout.tabOf(7) - G.folderHead) + GutLook.boxMid).roundToDouble();
    expect(folder.single.at.dy, closeTo(textTop(cy, GutLook.rowSize), .01));
    final names = {for (final l in of(painter, 'rowName')) l.text: l.at.dx};
    for (final r in [7, 8]) {
      expect(names['나라 $r'], GutLook.rowX + GutLook.step + GutLook.rowText, reason: '줄 $r');
    }
    for (final r in [2, 3, 4]) {
      expect(names.containsKey('나라 $r'), isFalse, reason: '줄 $r은 선반 변형에서 빠진 줄');
    }
    final hit = painter.gutter.hitTest(120, cy);
    expect([hit?.kind, hit?.uid, hit?.row], [GutterHitKind.folder, 's2', ScopeLayer.pressFold], reason: '누르면 가지 접기 뒤집기(선반 기억은 남김 — 폴더 탭 라벨과 같음 · 과제 7 걸음 5)');
    // 폴더 탭의 라벨은 같은 셈(scopeCountOf)으로 남은 3 + 숨은 2.
    expect([for (final l in painter.debugLabels) if (l.kind == 'folder') l.text], ['세 나라 할거', '5']);

    // 접으면 선반 변형이 꺼지고(접힘이 선반 기억을 이김) 그릇 변형의 가지가 줄 2로 합쳐진다 — 수는 구역 23의 b 그대로(더하지 않음).
    expect(layout.foldVariantGroup(0, '__scope:s2', true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect([layout.scopeStateOf('s2'), layout.isShelfOn('s2'), layout.variantKeys, layout.viewState.shelvedScopes], [ScopeState.closed, false, ['scope:s2'], {'s2'}]);
    expect(of(painter, 'gutFolderCount').map((l) => l.text), ['3']);
    // 접힌 채 선반 기억에 들어 있으면 누름도 5(다시 펴면 선반으로).
    final closed = of(painter, 'gutFolder').single;
    expect(painter.gutter.hitTest(closed.at.dx + 2, closed.at.dy + 6)?.row, ScopeLayer.pressFold);
  });

  test('올린 줄은 이름만 먹으로 짙어진다(바탕 칸 없음) — 고르기 · 강조는 왼쪽 칸을 흐리지 않는다', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(labels: {
      1: [label('p-1', '유리항 물길왕국', at, at + 100000)],
    });
    await settle(scene, painter);
    final name = of(painter, 'rowName').single;
    final shapes = scene.stats.shapes;
    // 이름 글 상자(앞 몇 글자) 안에서 가장 짙은 점.
    final area = Rect.fromLTWH(name.at.dx, name.at.dy, 4 * GutLook.rowSize, GutLook.rowSize * Gut.boxRatio);
    final calm = await darkestIn(painter, area);
    expect(calm, lessThan(700), reason: '글이 그려져 있다');
    painter.gutter.hotRow = 1;
    final hot = await darkestIn(painter, area);
    expect(hot, lessThan(calm), reason: '올린 줄의 이름은 먹 80 → 먹');
    expect(scene.stats.shapes, shapes, reason: '목업은 올려도 바탕 칸을 깔지 않는다');
    expect(of(painter, 'rowName').single.at, name.at, reason: '자리는 그대로');
    painter.gutter.hotRow = null;

    // 밝기: 왼쪽 칸은 기본으로 흐려지지 않는다(css에 규칙이 없다).
    final emphasis = em.Emphasis()..reduceMotion = true;
    painter.gutter.emphasis = emphasis;
    emphasis.set(const em.Look(band: 99));
    paint(painter);
    expect(of(painter, 'rowName').first.alpha, 1, reason: '다른 띠를 골라도 줄 이름은 그대로다');
    // 밭을 켜면 몸통과 같은 길로 색의 알파에 곱한다(고른 것만 1).
    painter.gutter.dims = true;
    paint(painter);
    expect(of(painter, 'rowName').first.alpha, closeTo(.58, 1e-9));
    emphasis.set(const em.Look(band: 0, row: 1));
    paint(painter);
    expect(of(painter, 'rowName').first.alpha, 1, reason: '고른 것과 같은 줄은 1');
  });

  test('조감 — 줄 이름은 이름만(연도 · 부제 없이), 모양 c(띠 8px)는 이름을 적지 않는다', () async {
    final at = tileOrigin(9, 1);
    Map<int, List<Map<String, dynamic>>> labels() => {
      1: [label('p-1', '해', at, at + 100000)],
    };
    final (bird, birdPainter) = make(labels: labels(), density: 2);
    await settle(bird, birdPainter);
    expect(of(birdPainter, 'rowName').map((l) => l.text), ['해']);
    expect(of(birdPainter, 'rowYears'), isEmpty, reason: '조감에서는 연도가 빠진다');
    expect(of(birdPainter, 'rowSub'), isEmpty, reason: '조감에서는 부제가 빠진다');

    final (c, cPainter) = make(labels: labels(), density: 2);
    c.layout.setConditions(c.layout.conditions.copyWith(birdShape: BirdShape.c));
    await settle(c, cPainter);
    // 모양 c는 이름을 싣지 않는 모양이다(BirdShape.c.name == false · 띠 8px에 11px 글이 들 틈이 없다 — 옛 왼쪽 칸도 여기서 글을 적지 않았다).
    expect(BirdShape.c.name, isFalse);
    expect(of(cPainter, 'rowName'), isEmpty, reason: '모양 c는 글 묶음이 숨는다');
  });

  test('조감의 접힌 민족 줄은 부제 대신 이름 뒤에 ▸', () async {
    final at = tileOrigin(9, 1);
    final (scene, painter) = make(
      labels: {
        1: [label('p-2', '월흔해의 백성', at, at + 100000, kind: RowLabel.foldedGroup, count: 24, cap: 0, years: '', depth: 0)],
      },
      density: 2,
    );
    // 접힘 후보(kind 2)는 펴져 있을 때도 실려 오므로, 그 묶음을 접어야 골라진다(계약 6-8절).
    final track = scene.layout.tracks[0];
    scene.layout.foldGroup(track, track.groups[1], true);
    await settle(scene, painter);
    expect(of(painter, 'rowName').first.text, endsWith(' ▸'));
    expect(of(painter, 'rowSub'), isEmpty);
  });

  // 문화권 머리 단 밑 사람 띠의 누름(리메이크 4단계 과제 4 걸음 3 — 사람 창): 띠 자리는 그 사람의 창, 상자 나머지는 그대로 접기 · 펴기.
  // (이 파일의 group은 띠 묶음을 짓는 도우미라 flutter_test의 group 대신 블록 하나로 묶는다.)
  {
    /// 사람 띠 하나 — 초원 대신 두 문화권(등불 분지권 · 설령 빙원권)에 [from] ~ [to]해 · 인물 uid · 왕관(data JSON).
    Map<String, Object?> person(String name, String sphere, double from, double to, {String? uid, String crowns = '[{"uid":"band-a","cell":0},{"uid":"band-b","cell":3}]'}) => {
      'kind': 1, 'sphere': sphere, 'start': minuteOfYear(from).round(), 'end': minuteOfYear(to).round(), 'name': name, 'uid': uid ?? 'fig-$name', 'data': crowns,
    };

    /// 트랙 둘을 등불 분지권 · 설령 빙원권으로 · 사람 띠 다섯(등불 분지권 두 줄 + 인물 기록 없는 사람 · 설령 빙원권 한 줄 + 왕관도 없는 사람) · −20 ~ 1420년.
    (TimelineScene, TimelinePainter) sphereScene({Set<String> folded = const {}, double height = 1080}) {
      final json = twoTrackLayout();
      (json['tracks'] as List)[0]['sphere'] = 'ember-basin';
      (json['tracks'] as List)[1]['sphere'] = 'frost-ridge';
      json['spheres'] = [
        {'id': 'ember-basin', 'name': '등불 분지권', 'count': 3, 'default': true},
        {'id': 'frost-ridge', 'name': '설령 빙원권', 'count': 2},
      ];
      json['sphereLines'] = [
        person('불씨 임금', 'ember-basin', 300, 700),
        person('겹친 임금', 'ember-basin', 500, 900),
        person('이름 없는 임금', 'ember-basin', 1000, 1300, uid: '', crowns: '[{"uid":"","cell":1},{"uid":"band-c","cell":2}]'),
        person('눈 임금', 'frost-ridge', 100, 400),
        person('왕관 없는 임금', 'frost-ridge', 600, 900, uid: '', crowns: '[]'),
      ];
      final layout = SceneLayout.fromJson(json)..reduceMotion = true;
      layout.setViewState(layout.viewState.copyWith(foldedSpheres: folded));
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, height)
        ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      controller.showRange(minuteOfYear(-20), minuteOfYear(1420));
      return (scene, painter);
    }

    void draw(TimelinePainter painter, double height) {
      for (int i = 0; i < 50; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), Size(1920, height));
        recorder.endRecording().dispose();
        if (!painter.text.starved) return;
      }
    }

    SpherePersonBand bandOf(TimelinePainter painter, String name) => painter.gutter.personBands.firstWhere((d) => d.band.person.name == name).band;

    test('사람 띠 누름 — 사람 띠를 누르면 그 인물(GutterHitKind.person · uid = 인물 uid) — 띠의 왼쪽 끝 · 오른쪽 끝 바로 안까지, 위아래 16 안', () {
      final (_, painter) = sphereScene();
      draw(painter, 1080);
      for (final name in ['불씨 임금', '겹친 임금', '눈 임금']) {
        final b = bandOf(painter, name);
        for (final (x, y) in [((b.x0 + b.x1) / 2, b.top + 8), (b.x0, b.top), (b.x1 - .5, b.bottom - .5)]) {
          final hit = painter.gutter.hitTest(x, y);
          expect((hit?.kind, hit?.uid, hit?.cell), (GutterHitKind.person, 'fig-$name', ''), reason: '$name ($x, $y)');
        }
      }
    });

    test('사람 띠 누름 — 인물 기록이 없는 사람은 첫 왕관의 띠 칸 창(띠 uid · leader:i — 띠 uid가 빈 왕관은 건너뜀) · 왕관도 없으면 빈 uid(누름이 아무것도 열지 않음)', () {
      final (_, painter) = sphereScene();
      draw(painter, 1080);
      final nameless = bandOf(painter, '이름 없는 임금');
      expect(nameless.opens, (uid: 'band-c', cell: 'leader:2'));
      final hit = painter.gutter.hitTest((nameless.x0 + nameless.x1) / 2, nameless.top + 8);
      expect((hit?.kind, hit?.uid, hit?.cell), (GutterHitKind.person, 'band-c', 'leader:2'));
      final crownless = bandOf(painter, '왕관 없는 임금');
      expect(crownless.opens, (uid: '', cell: ''));
      expect(painter.gutter.hitTest((crownless.x0 + crownless.x1) / 2, crownless.top + 8)?.kind, GutterHitKind.person, reason: '사람 띠 위는 접기가 아니다');
    });

    test('사람 띠 누름 — 상자의 나머지(머리 줄 · 사람 띠 사이 · 띠 밖 · 왼쪽 칸 몫)는 그대로 문화권 접기 · 펴기', () {
      final (scene, painter) = sphereScene();
      draw(painter, 1080);
      final v = scene.controller.view, layout = scene.layout;
      final y0 = v.yOf(layout.sphereHeadTop(0)).roundToDouble();
      final first = bandOf(painter, '불씨 임금'), second = bandOf(painter, '겹친 임금');
      for (final (x, y) in [
        (v.left + 300, y0 + 10), // 머리 줄(이름 · ▾)
        (first.x1 + 20, first.top + 8), // 첫 줄의 띠 사이(700 ~ 1000해)
        (second.x1 + 20, second.top + 8), // 둘째 줄 띠 오른쪽
        (first.x0 - 3, first.top + 8), // 띠 왼쪽 바로 밖
        (GutLook.rowX + 20, first.top + 8), // 왼쪽 칸 몫
      ]) {
        final hit = painter.gutter.hitTest(x, y);
        expect((hit?.kind, hit?.uid), (GutterHitKind.sphere, 'ember-basin'), reason: '($x, $y)');
      }
    });

    test('사람 띠 누름 — 접힌 문화권은 사람 띠도 누름 자리도 없다(상자 전체가 펴기)', () {
      final (scene, painter) = sphereScene(folded: const {'ember-basin'});
      draw(painter, 1080);
      expect([for (final d in painter.gutter.personBands) d.band.person.name], ['눈 임금', '왕관 없는 임금']);
      final v = scene.controller.view;
      final y0 = v.yOf(scene.layout.sphereHeadTop(0)).roundToDouble();
      for (double x = v.left; x < v.width; x += 40) {
        final hit = painter.gutter.hitTest(x, y0 + 10);
        expect(hit?.kind, GutterHitKind.sphere, reason: '$x');
      }
    });

    test('사람 띠 누름 — 붙은 머리 단(내려 봄)의 사람 띠도 그 사람의 창 — 그 밑을 지나는 줄 이름보다 먼저 · 상자 나머지는 접기', () {
      // 창 높이 150 — 등불 분지권: 머리 단 0 · 상자 20 + 16 × 2 + 2 = 54 · 트랙 1은 58부터.
      final (scene, painter) = sphereScene(height: 150);
      draw(painter, 150);
      final v = scene.controller.view, layout = scene.layout;
      scene.controller.scrollTo(60);
      draw(painter, 150);
      expect(v.top, 60);
      expect(layout.sphereHeadBox(0, v), (top: v.head, height: 54.0, stuck: true));
      final b = bandOf(painter, '불씨 임금');
      expect(b.top, v.head + 20, reason: '붙은 상자 안 — 그림판 위에서 센 자리');
      final hit = painter.gutter.hitTest((b.x0 + b.x1) / 2, b.top + 8);
      expect((hit?.kind, hit?.uid), (GutterHitKind.person, 'fig-불씨 임금'));
      final second = bandOf(painter, '겹친 임금');
      expect(second.top, v.head + 36);
      expect(painter.gutter.hitTest(second.x1 - 2, second.top + 8)?.uid, 'fig-겹친 임금');
      // 붙은 상자의 왼쪽 칸 몫 — 그 밑으로 트랙 1의 줄 이름이 지나가도 머리 단(접기).
      expect(painter.gutter.hitTest(GutLook.rowX + 20, v.head + 30)?.kind, GutterHitKind.sphere);
    });
  }
}
