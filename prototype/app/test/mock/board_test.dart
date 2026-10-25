import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/mock/boards.dart';
import 'package:archive_prototype/mock/render.dart';
import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

// 목업 판 찍기 — 판(boards.dart)의 갈래마다 한 화면을 1배 PNG로, 부품 판(renderParts)을 PNG로, 판의 자를 자리(boardCrops)마다 1배 · 2배 조각을 찍고
// board.json을 남긴다.
//   flutter test --no-pub test/mock/board_test.dart --dart-define=BOARD=<판> [--dart-define=OUT=../results/mock/board] [--dart-define=CLEARTYPE=on]
//   → <OUT>/<판>/full/<id>.png(1920×1080) · parts/<id>.png(1800×300) · crop/<id>-<n>.png(1배) · crop/<id>-<n>-2배.png(최근접 확대) · board.json
//   묶기: node prototype/scripts/mock-board.mjs <OUT>/<판> → <OUT>/<판>/<판>.html(고르기 판)
// BOARD가 없으면 건너뛴다(보통의 검사 돌림에서 판을 찍지 않게). 한 판이 30초를 넘으면 실패 — 고르기가 늘어지지 않게.
// CLEARTYPE=on이면 판 글자를 ClearType으로 굽는다(크롬 목업의 글자와 같은 꼴로 보이게). Windows · 자료 처리부 DLL이 있어야 하고, 없으면 실패한다
// (말없이 회색으로 찍지 않게). 프리텐다드가 아닌 글꼴 · 글꼴에 없는 글자(▸ · 한자)가 든 글줄은 앱처럼 회색이다.

const board = String.fromEnvironment('BOARD');
const out = String.fromEnvironment('OUT', defaultValue: '../results/mock/board');
const clearType = String.fromEnvironment('CLEARTYPE') == 'on';

/// 자료 처리부 DLL(ClearType 굽개) — app 폴더 기준.
const dll = '../engine/target/release/archive_engine.dll';

/// 판의 머리 — 판 이름 · 한 줄 설명(고르기 판 HTML의 맨 위). 없으면 판 이름만.
const heads = <String, (String, String)>{
  's4': (
    '조각 ④ 결정 판 — 단체 · 옮겨 앉기',
    '같은 장면(1180 ~ 1700년 — 고려 · 최씨 정권 · 조선 여섯 붕당 · 명 · 보헤미아 왕국의 옮겨 앉기)을 갈래 E 꼬리표(머리 · 흰 층 · 구멍 · 꼬리 마름모)로 '
        '갈림마다 그렸습니다. 작은 그림을 누르면 1920×1080 실제 크기(1배)로 열리고, ← → 로 갈래를 넘깁니다. 상국 표시(받침 카드 + 끝 쪽 탭)는 감독 확정대로 그대로입니다.',
  ),
};

/// 한 판이 넘으면 안 되는 시간(설계 1-4: 한 판 5~12초).
const limit = Duration(seconds: 30);

Future<void> writePng(ui.Image img, String path) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

/// [src]의 [r]을 [k]배로 — 최근접 확대(화소를 그대로 키워 글자 화소를 읽게).
Future<ui.Image> cropOf(ui.Image src, ui.Rect r, int k) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawImageRect(src, r, ui.Rect.fromLTWH(0, 0, r.width * k, r.height * k), ui.Paint()..filterQuality = ui.FilterQuality.none);
  final pic = rec.endRecording();
  final img = await pic.toImage((r.width * k).round(), (r.height * k).round());
  pic.dispose();
  return img;
}

void main() {
  test('판 $board을 찍는다', () async {
    final themes = boards[board];
    expect(themes, isNotNull, reason: '모르는 판: $board — 있는 판: ${boards.keys.join(' · ')}');
    final clock = Stopwatch()..start();
    await loadMockFonts('assets/fonts');
    final dir = '$out/$board';
    for (final sub in ['full', 'parts', 'crop']) {
      final d = Directory('$dir/$sub');
      if (d.existsSync()) d.deleteSync(recursive: true); // 지난 판의 그림이 남아 섞이지 않게
      d.createSync(recursive: true);
    }
    // 판 하나에 글자 그리기 하나 — 갈래끼리 같은 글자를 다시 만들거나 굽지 않게.
    final baker = clearType ? ClearTypeBaker.open(File(dll).absolute.path) : null;
    if (clearType) expect(baker, isNotNull, reason: 'CLEARTYPE=on인데 굽개를 열지 못함 — Windows · $dll(archive_glyphs)');
    final atlas = AtlasText(baker: baker, fontFileOf: (look) => sceneFontFile(look, root: 'assets/fonts'))
      ..maxNewPerFrame = 1 << 20
      ..budgetMicros = 1 << 30
      ..lcdAllowed = clearType;
    final crops = boardCrops[board] ?? const <ui.Rect>[];
    final rows = <Map<String, Object?>>[], report = StringBuffer();
    try {
      for (final th in themes!) {
        final began = clock.elapsedMilliseconds;
        final svg = renderScreen(th).p.svg;
        final img = await renderMock(svg, text: atlas);
        final info = mockRenderInfo(svg)!;
        expect(info.settled, isTrue, reason: '${th.id}: 글자를 다 준비하지 못한 채 그림(${info.rounds}판)');
        final pens = atlas.debugLastPens.length, lcd = atlas.lcdSprites;
        if (clearType) expect(lcd, greaterThan(pens ~/ 2), reason: '${th.id}: ClearType 글자 $lcd / $pens');
        await writePng(img, '$dir/full/${th.id}.png');
        final cropRows = <Map<String, Object?>>[];
        for (final (n, r) in crops.indexed) {
          final name = '${th.id}-${n + 1}';
          for (final k in [1, 2]) {
            final c = await cropOf(img, r, k);
            await writePng(c, '$dir/crop/$name${k == 2 ? '-2배' : ''}.png');
            c.dispose();
          }
          cropRows.add({'x1': 'crop/$name.png', 'x2': 'crop/$name-2배.png', 'rect': [r.left, r.top, r.width, r.height]});
        }
        img.dispose();
        // 부품 판 — 원본 판이 카드 아래에 두는 것(장면의 작은 조각에서 갈래의 고리가 그리는 모습)
        final partsSvg = renderParts(th);
        final parts = await renderMock(partsSvg, width: 1800, height: 300, text: atlas);
        expect(mockRenderInfo(partsSvg)!.settled, isTrue, reason: '${th.id} 부품 판: 글자를 다 준비하지 못한 채 그림');
        await writePng(parts, '$dir/parts/${th.id}.png');
        parts.dispose();
        rows.add({
          'id': th.id, 'code': th.code, 'name': th.name, 'by': th.by, 'idea': th.idea, 'pro': th.pro, 'con': th.con, 'rec': th.rec, //
          'full': 'full/${th.id}.png', 'parts': 'parts/${th.id}.png', 'crops': cropRows,
        });
        report.writeln('  ${th.id}: ${clock.elapsedMilliseconds - began}ms · ${info.rounds}판${clearType ? ' · ClearType 글자 $lcd / $pens' : ''}');
      }
    } finally {
      atlas.dispose();
    }
    final (title, lede) = heads[board] ?? (board, '');
    final seconds = clock.elapsedMilliseconds / 1000;
    File('$dir/board.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'board': board, 'title': title, 'lede': lede, 'cleartype': clearType, 'seconds': seconds, 'themes': rows, //
    }));
    // ignore: avoid_print
    print('판 $board: 갈래 ${rows.length} · 조각 자리 ${crops.length} · ClearType ${clearType ? '켬' : '끔'} · ${seconds.toStringAsFixed(1)}초\n$report');
    expect(rows, isNotEmpty);
    expect(clock.elapsed, lessThan(limit), reason: '한 판 ${seconds.toStringAsFixed(1)}초');
  }, skip: board.isEmpty ? 'BOARD가 없음 — 판을 찍으려면 --dart-define=BOARD=<판>' : false, timeout: const Timeout(Duration(minutes: 3)));
}
