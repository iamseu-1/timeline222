import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/labels.dart' show placeLabels;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellKind, CellStyle;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 3단계 과제 8 걸음 4 — 지금 그림판이 스키마 4의 새 값을 건너뛰는지(1배 그대로인지) 못 박는 검사.
// 새 값은 계약 1-1의 다섯 가운데 타일에 실리는 넷이다: 띠의 form(열 10 → 띠 구역 11열) · 빌린 칸의 style 27비트 ·
// 칸 종류 9(직위 줄 더) · 일반 구역 54(빌린 줄의 머리 글) · 55(직위 줄 더의 이름) · 56(실권 밑줄). 그리기는 4단계 몫이다(계획 정한 것 #14).
//
// 같은 장면을 타일 두 벌로 그려 견준다(strips_paint_test · painter_fixture와 같은 꼴 — 단계 9 · 통 32px · 1920×1080 · 1배).
//   A(옛 값): 띠 · 칸 · 사건 · 구역 43 · 49와, 다리가 복제한 '빌린' 지도자 · 내각 칸(27비트 없이 — 다리는 지금도 칸을 복제해 싣는다).
//   B(새 값): A + 띠의 form≠0 · 빌린 칸의 27비트 · 종류 9 칸(단 0 · 1) · 구역 54 · 55 · 56(같은 줄 · 같은 띠 ref).
// 밀도 넷(보통 · 빽빽하게 · 넉넉하게 · 조감) × 표시 체크 '단체' 켬 · 끔에서(렌즈 끔) 다음이 같아야 한다:
//   검사 기록(painter.debugSink.notes — 모든 열쇠를 글로) · 이름(labels) · 띠 조각 · 점 · 막대 · 동군연합 줄 · 장면 통계 ·
//   `toImage` 뒤 rawRgba 바이트(bands_paint_test의 render와 같은 길) · `StripLayer.hitStrips`로 종류 9 칸 자리 · 빌린 칸 자리를 누른 답.
//
// 견줄 때 고쳐 쓰는 것은 '칸이음' 기록의 두 값뿐이다 — 이 기록은 그림의 결정이 아니라 칸의 입력을 그대로 적어 두는 검사용 글이라
// `st=`(칸의 style 그대로)에는 27비트가 보이고, `i=`(타일 칸 배열 안의 자리)는 B의 줄 0에 낀 종류 9 칸만큼 뒤 줄 칸에서 밀린다.
// 그래서 `st=`는 27비트를 지운 값으로, `i=`는 그 자리의 칸 번호(id)로 바꿔 견준다. 다른 기록은 글 그대로 견준다.
// (B의 '칸이음'에 27비트가 실제로 실려 있음 — 그림판이 값을 받고도 쓰지 않음 — 은 따로 확인한다.)

/// 단계 9에서 통 하나가 32px일 때의 1분 폭. 자리는 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(strips_paint_test와 같은 셈).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// style에 함께 실리는 순번(계약 6-2: 비트 15 ~ 26 = 순번 + 1).
int st(int style, {int seq = -1}) => style | ((seq < 0 ? 0 : seq + 1) << 15);

/// 사건 점의 단을 비워 둔 look(events_paint_test의 freeLane).
const freeLane = 255 << 8;

/// 띠의 form(계약 1-1 비트 — band_form.dart의 BandForm으로 풀린다). 종류 + 1 · 관계 << 5 · (정통성 + 1) << 10 · (중요도 + 1) << 13.
/// 첫불 성채국 = 국가(0) · 중요도 2 / 해솔국 = 속령(6) · 봉신(4) · 정통(0) / 가람 왕국 = 국가(0) · 섭정(3) · 중요도 3.
const formCheotbul = 1 | 3 << 13, formHaesol = 7 | 4 << 5 | 1 << 10, formGaram = 1 | 4 << 10 | 4 << 13;

/// 3판의 줄 하나(strips_paint_test의 row와 같은 값 + 줄 깃발 [figWide]).
Map<String, dynamic> row(int id, {int phase = 0, int rank = 0, int figWide = 0}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': 4, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': phase, 'rank': rank, 'cats': <int>[],
  'fig': 0, 'fig_wide': figWide, 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 트랙 하나 · 줄 셋. 줄 0 · 1은 왕조 · 시기(단 1) · 지위 · 지도자 · 내각 단, 줄 2는 단체 단 줄(집권 · 실권 — `fig_wide` 비트 7 · 8,
/// 비트 3 ~ 5가 0이 아니어야 읽힌다 — layout.dart RowFlags.legacy)에 지도자 · 내각 단.
SceneLayout shape({required int density, required bool groups}) {
  final layout = SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 4}],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5,
        'dynasty': 1, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
        'rows': [row(0, phase: 1, rank: 1), row(1, phase: 1, rank: 1), row(2, figWide: 8 | 128 | 256)],
      },
    ],
    'epochs': <dynamic>[],
    'categories': [{'id': 1, 'key': 'politics', 'name': '정치', 'color': 0xd4a39b}],
  });
  layout
    ..setConditions(layout.conditions.copyWith(density: density, groups: groups))
    ..finishFlow();
  return layout;
}

/// 칸 하나(타일에 싣기 전). 타일의 칸은 (줄, 종류, 단, 시작) 순이어야 하므로(엔진 부호화의 약속) 모아서 정렬한 뒤 싣는다.
typedef CellSpec = ({int id, int row, double x0, double x1, String name, int kind, int lane, int style, int color});

CellSpec c(int id, int row, double x0, double x1, String name, int kind, {int lane = 0, int style = 0, int color = 0}) =>
    (id: id, row: row, x0: at(x0), x1: at(x1), name: name, kind: kind, lane: lane, style: style, color: color);

/// 동군연합(구역 49)의 풍선 글.
const tip = '동군연합 · 셋째 지도자 = 어린 임금';

/// 타일 하나(단계 9 · x 0). [next]가 거짓이면 A(옛 값), 참이면 B(A + 스키마 4의 새 값).
Uint8List tileOf({required bool next}) {
  final borrow = next ? Schema4.borrowed : 0;
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1600), '첫불 성채국', color: 0xa0bcc5, form: next ? formCheotbul : 0)
    ..band(2, 1, at(200), at(1500), '해솔국', color: 0xc8b193, form: next ? formHaesol : 0)
    ..band(3, 2, at(150), at(1550), '가람 왕국', color: 0xb1a0c9, form: next ? formGaram : 0);
  final cells = <CellSpec>[
    // ── 줄 0: 첫불 성채국 — 제 칸만
    c(1, 0, 150, 700, '유리항 깊은 왕조', CellKind.dynasty, style: st(0, seq: 0), color: 0xa0bcc5),
    c(2, 0, 700, 1500, '은결 왕가', CellKind.dynasty, style: st(0, seq: 1), color: 0xc8b193),
    c(10, 0, 150, 500, '은결 나나나', CellKind.leader, style: st(0, seq: 0)),
    c(11, 0, 500, 900, '둘째 지도자', CellKind.leader, style: st(CellStyle.joinLeft | 1 << 14, seq: 1)),
    c(12, 0, 900, 1300, '셋째 지도자', CellKind.leader, style: st(CellStyle.joinLeft, seq: 2)),
    c(13, 0, 150, 800, '첫 내각', CellKind.cabinet, style: st(0, seq: 0)),
    c(14, 0, 800, 1400, '둘째 내각', CellKind.cabinet, style: st(0, seq: 1)),
    c(20, 0, 150, 800, '장부 학파\t복구기', CellKind.phase, style: st(CellStyle.tagged, seq: 0)),
    c(21, 0, 800, 1400, '장부 학파\t안정기', CellKind.phase, style: st(CellStyle.tagged | CellStyle.joinLeft, seq: 1)),
    c(30, 0, 150, 1400, '문지기', CellKind.rank, style: st(4 << 8, seq: 0)),
    // ── 줄 1: 해솔국 — 지도자 · 내각 줄을 첫불 성채국에서 빌림(`leadersFrom` · `cabinetsFrom`: 다리가 출처의 칸을 제 구간으로 잘라 복제)
    c(50, 1, 250, 1400, '해솔 왕가', CellKind.dynasty, style: st(0, seq: 0), color: 0xc8b193),
    c(60, 1, 200, 500, '은결 나나나', CellKind.leader, style: st(0, seq: 0) | borrow),
    c(61, 1, 500, 900, '둘째 지도자', CellKind.leader, style: st(CellStyle.joinLeft | 1 << 14, seq: 1) | borrow),
    c(62, 1, 900, 1300, '셋째 지도자', CellKind.leader, style: st(CellStyle.joinLeft, seq: 2) | borrow),
    c(63, 1, 200, 800, '첫 내각', CellKind.cabinet, style: st(0, seq: 0) | borrow),
    c(64, 1, 800, 1400, '둘째 내각', CellKind.cabinet, style: st(0, seq: 1) | borrow),
    c(70, 1, 250, 1400, '물길 학파\t한 시기', CellKind.phase, style: st(CellStyle.tagged, seq: 0)),
    c(71, 1, 250, 1400, '파수꾼', CellKind.rank, style: st(3 << 8, seq: 0)),
    // ── 줄 2: 가람 왕국(단체 단 줄) — 지도자 줄을 빌림(가운데는 명목 지도자 — 29비트와 27비트가 함께 선다) · 제 내각 · 집권 단(단 2) · 실권 단(단 3)
    c(80, 2, 150, 600, '첫 가람왕', CellKind.leader, style: st(0, seq: 0) | borrow),
    c(81, 2, 600, 1000, '어린 임금', CellKind.leader, style: st(CellStyle.joinLeft | CellStyle.nominalLeader, seq: 1) | borrow),
    c(82, 2, 1000, 1500, '늦은 임금', CellKind.leader, style: st(CellStyle.joinLeft, seq: 2) | borrow),
    c(83, 2, 150, 1500, '가람 내각', CellKind.cabinet, style: st(0, seq: 0)),
    c(90, 2, 200, 700, '들\t들 무리', CellKind.common, lane: 2, style: st(CellStyle.groupOne << 27 | CellStyle.tagged, seq: 0), color: 0xc8b193),
    c(91, 2, 700, 1200, '물·새\t물 무리 · 새벽 무리', CellKind.common, lane: 2, style: st(CellStyle.groupTwo << 27 | CellStyle.tagged | CellStyle.joinLeft, seq: 1), color: 0xd7c18e),
    c(92, 2, 600, 1000, '푸\t푸른 집안', CellKind.common, lane: 3, style: st(CellStyle.groupReal << 27 | CellStyle.tagged, seq: 0), color: 0xa0bcc5),
    // ── B에만: 종류 9(직위 줄 더) — 줄 0의 단 0(제 줄) · 단 1(빌린 줄 — 27비트). (줄, 종류, 단, 시작) 순이라 줄 0의 맨 뒤에 낀다.
    if (next) ...[
      c(40, 0, 200, 900, '첫 재상', Schema4.cellOfficeMore, style: st(0, seq: 0)),
      c(41, 0, 900, 1500, '둘째 재상', Schema4.cellOfficeMore, style: st(CellStyle.joinLeft, seq: 1)),
      c(42, 0, 300, 1200, '나루 재상', Schema4.cellOfficeMore, lane: 1, style: st(0, seq: 0) | Schema4.borrowed),
    ],
  ]..sort((p, q) {
      for (final d in [p.row - q.row, p.kind - q.kind, p.lane - q.lane]) {
        if (d != 0) return d;
      }
      return p.x0.compareTo(q.x0);
    });
  for (final s in cells) {
    t.cell(s.id, s.row, s.x0, s.x1, s.name, kind: s.kind, lane: s.lane, style: s.style, color: s.color);
  }
  t
    // 사건(띠 안 · 점과 이름)
    ..event(100, 0, at(300), '첫불 성채 세움', look: freeLane, band: 1)
    ..event(101, 0, at(1000), '둘째 성 쌓음', look: freeLane, band: 1)
    ..event(102, 1, at(700), '해솔 나루 엶', look: freeLane, band: 2)
    ..event(103, 2, at(1100), '가람 큰물', look: freeLane, band: 3)
    // 구역 43 — 단체 칸이 가리키는 단체(연정 칸은 둘째 색 · 색 점)
    ..item(43, 200, 2, at(200), at(700), ref: 3, a: CellKind.common, b: 2, c: 1, text2: 'sample/pw-deul')
    ..item(43, 201, 2, at(700), at(1200), ref: 3, a: CellKind.common, b: 2, c: 2, color: 0xbbacc8, text2: 'sample/pw-mul\td7c18e,bbacc8')
    ..item(43, 202, 2, at(600), at(1000), ref: 3, a: CellKind.common, b: 3, c: 1, text2: 'sample/pw-pureun')
    // 구역 49 — 동군연합: 해솔국의 빌린 셋째 지도자(순번 2) = 가람 왕국의 빌린 명목 지도자(순번 1). 겹친 기간 900 ~ 1000의 가운데 950.
    ..item(49, 300, 1, at(950), at(1000), ref: 2, name: tip, a: 2, b: 3, c: 1, text2: 'k1')
    ..item(49, 301, 2, at(950), at(1000), ref: 3, name: tip, a: 1, b: 2, c: 2, text2: 'k1');
  if (next) {
    t
      // 구역 54 — 빌린 직위 줄의 머리 글(ref = 빌린 쪽 띠 · a = 칸 종류 · b = 직위 줄 더의 단 · text2 = 출처 uid)
      ..item(Schema4.secBorrowHead, 400, 1, at(200), at(1500), ref: 2, name: '첫불 성채국/지도자', a: CellKind.leader, text2: 'sample/cheotbul')
      ..item(Schema4.secBorrowHead, 401, 1, at(200), at(1500), ref: 2, name: '첫불 성채국/내각', a: CellKind.cabinet, text2: 'sample/cheotbul')
      ..item(Schema4.secBorrowHead, 402, 0, at(100), at(1600), ref: 1, name: '나루국/재상', a: Schema4.cellOfficeMore, b: 1, text2: 'sample/naru')
      ..item(Schema4.secBorrowHead, 403, 2, at(150), at(1550), ref: 3, name: '큰 뭍 제국/황제', a: CellKind.leader, text2: 'sample/keunmut')
      // 구역 55 — 직위 줄 더의 이름(b = 그 줄의 단)
      ..item(Schema4.secOfficeName, 410, 0, at(100), at(1600), ref: 1, name: '재상', b: 0)
      ..item(Schema4.secOfficeName, 411, 0, at(100), at(1600), ref: 1, name: '나루 재상', b: 1)
      // 구역 56 — 실권 밑줄(빼앗긴 띠에 · 쥔 쪽 이름 · 색 · uid) · 제 안의 실권자(a = 1)
      ..item(Schema4.secPowerLine, 420, 2, at(600), at(1000), ref: 3, name: '큰 뭍 제국', color: 0xc8b193, text2: 'sample/keunmut')
      ..item(Schema4.secPowerLine, 421, 2, at(1100), at(1400), ref: 3, name: '세도 가문', a: 1);
  }
  return t.build();
}

/// 장면 하나를 그린 결과 — 견줄 것을 모두 글과 바이트로.
class Shot {
  Shot(this.pixels, this.notes, this.labels, this.marks, this.stats, this.hits, this.borrowedStyles);
  final Uint8List pixels;
  final Map<String, List<String>> notes;
  final List<String> labels, marks, stats, hits;

  /// 고쳐 쓰기 전의 '칸이음' 기록 가운데 `st=`에 27비트가 선 것의 수 — 그림판이 그 값을 받았다는 표시.
  final int borrowedStyles;
}

/// '칸이음' 기록('종류:줄:단 … st=… … i=…')의 칸 종류와 style.
(int, int) joinKindStyle(String note) =>
    (int.parse(note.substring(0, note.indexOf(':'))), int.parse(RegExp(r'\bst=(\d+)').firstMatch(note)![1]!));

/// 그 '칸이음' 기록의 칸이 빌린 칸(27비트 — 종류 1 · 2 · 9에서만. 종류 8의 27비트는 단 갈래의 아래 비트다)인가.
bool joinBorrowed(String note) {
  final (kind, style) = joinKindStyle(note);
  return Schema4.isBorrowed(kind, style);
}

/// '칸이음' 기록의 두 값을 견줄 꼴로 — 머리 주석의 까닭. [t]는 그 장면의 타일(배열 자리 → 칸 번호).
/// 27비트는 빌린 칸(종류 1 · 2 · 9)에서만 지운다 — 종류 8(단체 단)의 갈래 5 · 7은 27비트가 선 그대로 견준다.
String normalJoin(String note, Tile t) => note
    .replaceAllMapped(RegExp(r'\bst=(\d+)'), (m) => 'st=${joinBorrowed(note) ? int.parse(m[1]!) & ~Schema4.borrowed : int.parse(m[1]!)}')
    .replaceAllMapped(RegExp(r' i=(\d+)$'), (m) => ' id=${t.cellId[int.parse(m[1]!)]}');

String r1(double v) => v.toStringAsFixed(2);
String rect(ui.Rect r) => '${r1(r.left)},${r1(r.top)},${r1(r.width)},${r1(r.height)}';

/// 누를 자리: 종류 9 칸 · 빌린 칸(B 기준 — A에는 같은 자리에 같은 빌린 칸이 27비트 없이 있다)의 가운데 · 두 끝 안쪽 2px을
/// 그 줄의 몫 위아래 전부(1px 걸음)로, 그리고 화면 몸통 전체를 성기게(25px · 3px 걸음).
List<ui.Offset> pokesOf(TimelineScene scene) {
  final v = scene.controller.view, layout = scene.layout;
  final b = Tile.decode(tileOf(next: true));
  final xsOf = <int, List<double>>{};
  for (int i = 0; i < b.cellCount; i++) {
    if (!Schema4.isBorrowed(b.cellKind[i], b.cellStyle[i]) && b.cellKindOf(i) != Schema4.cellOfficeMore) continue;
    final l = v.xOf(b.cellX0[i].toDouble()), r = v.xOf(b.cellX1[i].toDouble());
    (xsOf[b.cellRow[i]] ??= []).addAll([(l + r) / 2, l + 2, r - 2]);
  }
  final out = <ui.Offset>[];
  for (final MapEntry(key: r, value: xs) in xsOf.entries) {
    if (r >= layout.rowCount || !layout.isVisible(r)) continue;
    final top = v.yOf(layout.rowTop(r)), height = layout.geo(r).height;
    for (double y = top; y <= top + height; y += 1) {
      for (final x in xs) {
        out.add(ui.Offset(x, y + .5));
      }
    }
  }
  for (double y = v.head; y < 1080; y += 3) {
    for (double x = v.left; x < 1920; x += 25) {
      out.add(ui.Offset(x + .5, y + .5));
    }
  }
  return out;
}

/// 장면을 지어 이름 판까지 가라앉힌 뒤 한 번 그려(그림을 떠서) 견줄 것을 모은다.
Future<Shot> shoot({required bool next, required int density, required bool groups}) async {
  var now = 0.0;
  final layout = shape(density: density, groups: groups);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(layout.totalHeight);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final bytes = tileOf(next: next);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    clock: () => now,
    labelCompute: (input) async => placeLabels(input),
    fetchTile: (level, x, chunk, packs) async =>
        level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  addTearDown(scene.dispose);
  final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
  void paintOnce() {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }

  // 타일 받기 → 이름 판(작업자) → 글자 폭이 처음 그릴 때 재지는 것까지 가라앉힌다(events_paint_test의 settle).
  int calm = 0;
  for (int i = 0; i < 80 && calm < 3; i++) {
    now += 1000;
    scene.prepare();
    paintOnce();
    await pumpEventQueue();
    final out = scene.labelOutput;
    calm = out != null && out.deferred == 0 && !scene.labelWorker.busy && scene.stats.blanks == 0 && scene.stats.tiles > 0 ? calm + 1 : 0;
  }
  expect(calm, 3, reason: '장면이 가라앉지 않았다');

  // 견주는 장면 — 그림을 뜨는 이 한 번의 그리기에서 기록도 함께 읽는다.
  now += 1000;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  expect(painter.text.starved, isFalse, reason: '글줄 준비가 모자란 장면이다');
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();

  final tile = Tile.decode(bytes);
  final sink = painter.debugSink;
  final notes = <String, List<String>>{
    for (final key in sink.notes.keys.toList()..sort())
      key: [for (final v in sink.notes[key]!) key == '칸이음' ? normalJoin('$v', tile) : '$v'],
  };
  final s = scene.stats;
  final hit = painter.strips;
  return Shot(
    data!.buffer.asUint8List(),
    notes,
    [for (final l in sink.labels) '${l.kind} ${l.text} ${r1(l.at.dx)},${r1(l.at.dy)} ${l.alpha}'],
    [
      for (final b in sink.bands) '띠 ${b.id} ${rect(b.rect)} ${b.roundLeft} ${b.roundRight} ${b.fadeLeft} ${b.fadeRight}',
      for (final d in sink.dots) '점 ${d.eventId} ${r1(d.at.dx)},${r1(d.at.dy)} ${d.extra}',
      for (final b in sink.bars) '막대 ${b.eventId} ${rect(b.rect)}',
      for (final (x, y0, y3, a) in painter.unions.debugLines) '연합줄 ${r1(x)} ${r1(y0)}~${r1(y3)} $a',
      for (final (band, ref, x) in painter.unions.debugMarks) '연합표지 $band|$ref ${r1(x)}',
      '고름 ${sink.selectionAt} · 눈금 ${sink.gridLines}',
    ],
    [
      'shapes ${s.shapes}', 'labels ${s.labels}', 'tiles ${s.tiles}', 'covers ${s.covers}', 'blanks ${s.blanks}',
      'nameBatch ${s.nameBatch}', 'namesDrawn ${s.namesDrawn}', 'ghostNames ${s.ghostNames}',
    ],
    [
      for (final p in pokesOf(scene))
        switch (hit.hitStrips(p.dx, p.dy)) {
          null => '',
          final h => '${h.band} ${h.row} ${h.kind} ${h.ref} ${h.uid} ${h.name} ${rect(h.rect)} ${h.houseId} ${h.houseName} ${h.houseColor}',
        },
    ],
    [
      for (final v in sink.notes['칸이음'] ?? const <Object>[])
        if (joinBorrowed('$v')) v,
    ].length,
  );
}

/// 두 그림의 첫 다른 픽셀(없으면 null).
String? firstPixelDiff(Uint8List a, Uint8List b) {
  if (a.length != b.length) return '길이 ${a.length} · ${b.length}';
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      final p = i ~/ 4;
      return '(${p % 1920}, ${p ~/ 1920}) 채널 ${i % 4}: ${a[i]} → ${b[i]}';
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('견본 타일', () {
    test('B는 A에 스키마 4의 새 값만 더했다 — 검사가 헛돌지 않게 새 값이 실제로 실렸는지', () {
      final a = Tile.decode(tileOf(next: false)), b = Tile.decode(tileOf(next: true));
      // 띠: B만 form 열이 있어 11열, 나머지 열은 같다.
      expect((a.section(Tile.secBand).columns, b.section(Tile.secBand).columns), (10, 11));
      expect(a.bandForm, [0, 0, 0]);
      expect(b.bandForm, [formCheotbul, formHaesol, formGaram]);
      for (final (x, y) in [(a.bandId, b.bandId), (a.bandRow, b.bandRow), (a.bandColor, b.bandColor), (a.bandLook, b.bandLook), (a.bandFlags, b.bandFlags)]) {
        expect(y, x);
      }
      // 칸: B에서 종류 9를 빼고 27비트를 지우면 A와 칸마다 같다(차례도 — 종류 9는 줄 0의 맨 뒤에 낀다).
      String cellOf(Tile t, int i) =>
          '${t.cellId[i]} ${t.cellRow[i]} ${t.cellKind[i]} ${t.cellLane[i]} ${t.cellX0[i]} ${t.cellX1[i]} ${t.text(t.cellName[i])} '
          '${Schema4.isBorrowed(t.cellKind[i], t.cellStyle[i]) ? t.cellStyle[i] & ~Schema4.borrowed : t.cellStyle[i]} ${t.cellColor[i]}';
      final officeMore = Schema4.officeMoreCells(b);
      expect([for (final i in officeMore) b.cellId[i]], [40, 41, 42]);
      expect(officeMore, [10, 11, 12], reason: '줄 0의 칸 열 개 뒤 — 줄 1의 칸부터 배열 자리가 셋씩 밀린다');
      expect([for (int i = 0; i < b.cellCount; i++) if (!officeMore.contains(i)) cellOf(b, i)], [for (int i = 0; i < a.cellCount; i++) cellOf(a, i)]);
      expect([for (int i = 0; i < a.cellCount; i++) if (Schema4.isBorrowed(a.cellKind[i], a.cellStyle[i])) a.cellId[i]], isEmpty);
      expect([for (int i = 0; i < b.cellCount; i++) if (Schema4.isBorrowed(b.cellKind[i], b.cellStyle[i])) b.cellId[i]],
          [42, 60, 61, 62, 63, 64, 80, 81, 82]);
      // 빌린 명목 지도자: 27비트와 29비트가 함께 서고 순번은 그대로다.
      final nominal = [for (int i = 0; i < b.cellCount; i++) b.cellId[i]].indexOf(81);
      expect(b.cellStyle[nominal] & CellStyle.nominalLeader, isNonZero);
      expect(CellStyle.seqOf(b.cellStyle[nominal]), 1);
      // 일반 구역: B만 54 · 55 · 56(같은 띠 ref · 같은 줄). 사건 · 구역 43 · 49는 같다.
      expect(Schema4.borrowHeads(a), isEmpty);
      expect(Schema4.officeNames(a), isEmpty);
      expect(Schema4.powerLines(a), isEmpty);
      expect([for (final h in Schema4.borrowHeads(b)) (h.band, h.row, h.kind, h.lane)], [(2, 1, 1, 0), (2, 1, 2, 0), (1, 0, 9, 1), (3, 2, 1, 0)]);
      expect([for (final n in Schema4.officeNames(b)) (n.band, n.row, n.lane, n.name)], [(1, 0, 0, '재상'), (1, 0, 1, '나루 재상')]);
      expect([for (final p in Schema4.powerLines(b)) (p.band, p.row, p.holder, p.own)], [(3, 2, '큰 뭍 제국', false), (3, 2, '세도 가문', true)]);
      expect(b.sectionKinds, [...a.sectionKinds, 54, 55, 56]);
      expect((a.eventCount, b.eventCount), (4, 4));
    });
  });

  // 밀도(−1 넉넉하게 · 0 보통 · 1 빽빽하게 · 2 조감) × 표시 체크 '단체'. 렌즈는 끈 채(기본).
  for (final (density, name) in const [(0, '보통'), (1, '빽빽하게'), (-1, '넉넉하게'), (2, '조감')]) {
    for (final groups in const [true, false]) {
      final label = '밀도 $name · 단체 ${groups ? '켬' : '끔'}';
      test('$label: 옛 값 타일(A)과 새 값 타일(B)의 장면이 1배 같다 — 기록 · 이름 · 통계 · 그림 바이트 · 누른 답', () async {
        final a = await shoot(next: false, density: density, groups: groups);
        final b = await shoot(next: true, density: density, groups: groups);
        // 검사가 헛돌지 않게: 장면이 실제로 그려졌다(띠 · 이름 · 칸).
        expect(a.marks.where((m) => m.startsWith('띠 ')), isNotEmpty, reason: '띠가 그려지지 않았다');
        expect(a.labels, isNotEmpty, reason: '이름이 그려지지 않았다');
        final drawnCells = a.notes['칸'] ?? const <String>[];
        if (density == 2) {
          expect(drawnCells, isEmpty, reason: '조감에는 띠 안의 단이 없다');
        } else {
          // 빌린 지도자 칸(줄 1 · 줄 2의 종류 1)이 그려졌고, 그 자리를 누르면 칸이 잡힌다.
          expect(drawnCells.where((n) => n.startsWith('1:1:')), isNotEmpty, reason: '줄 1의 빌린 지도자 칸');
          expect(drawnCells.where((n) => n.startsWith('2:1:')), isNotEmpty, reason: '줄 1의 빌린 내각 칸');
          expect(a.hits.where((h) => h.isNotEmpty), isNotEmpty, reason: '누른 자리에서 잡힌 칸이 하나도 없다');
          // B의 '칸이음' 원래 글에는 빌린 칸의 27비트가 실려 있다 — 그림판이 값을 받고도 그림에 쓰지 않는다.
          expect(a.borrowedStyles, 0);
          expect(b.borrowedStyles, greaterThan(0), reason: '빌린 칸이 그려지며 27비트가 그림판에 닿았다');
        }
        // 기록: 열쇠 목록과 열쇠마다의 글 목록이 같다.
        expect(b.notes.keys.toList(), a.notes.keys.toList(), reason: '$label 기록 열쇠');
        for (final key in a.notes.keys) {
          expect(b.notes[key], a.notes[key], reason: '$label 기록 \'$key\'');
        }
        expect(b.labels, a.labels, reason: '$label 이름');
        expect(b.marks, a.marks, reason: '$label 띠 · 점 · 막대 · 동군연합');
        expect(b.stats, a.stats, reason: '$label 통계');
        expect(b.hits.length, a.hits.length);
        for (int i = 0; i < a.hits.length; i++) {
          if (a.hits[i] != b.hits[i]) fail('$label 누른 답 $i번: A「${a.hits[i]}」 · B「${b.hits[i]}」');
        }
        expect(firstPixelDiff(a.pixels, b.pixels), isNull, reason: '$label 그림 바이트');
      });
    }
  }

  test("'칸이음' 고쳐 쓰기는 27비트와 배열 자리만 건드린다", () {
    final b = Tile.decode(tileOf(next: true));
    final i = [for (int k = 0; k < b.cellCount; k++) b.cellId[k]].indexOf(81);
    final style = b.cellStyle[i];
    expect(normalJoin('1:2:0 jl=true jr=true zl=false zr=false st=$style seq=1 a=1.0 b=2.0 i=$i', b),
        '1:2:0 jl=true jr=true zl=false zr=false st=${style & ~Schema4.borrowed} seq=1 a=1.0 b=2.0 id=81');
    expect(style & ~Schema4.borrowed & CellStyle.nominalLeader, isNonZero, reason: '명목 비트(29)는 남는다');
    // 종류 8(단체 단)의 갈래 5 · 7은 27비트가 서 있어도 빌림이 아니라 그대로 둔다.
    final group = CellStyle.groupOne << 27 | 1 << 15;
    expect(group & Schema4.borrowed, isNonZero);
    expect(normalJoin('8:2:2 jl=false jr=false zl=false zr=false st=$group seq=0 a=1.0 b=2.0 i=0', b),
        '8:2:2 jl=false jr=false zl=false zr=false st=$group seq=0 a=1.0 b=2.0 id=${b.cellId[0]}');
  });
}
