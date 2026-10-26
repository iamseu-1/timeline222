import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/grid.dart' show GridLayer;
import 'package:archive_prototype/scene/paint/hangs.dart' show HangMark;
import 'package:archive_prototype/scene/paint/ink.dart' show CanvasInk;
import 'package:archive_prototype/scene/paint/minibars.dart' show Mini;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart' show FlagLook, FolderLook, ScopeLayer, ScopeLook, ScopeMarks;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart' show Ruler, minuteOfYear;
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/sphere_crowns.dart' show CrownBand, CrownCell;
import 'package:archive_prototype/scene/text_paragraph.dart' show SceneText;
import 'package:archive_prototype/scene/tile.dart' show Tile;
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/ui/export_svg.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart' show twoTrackLayout;
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 세로 눈금(paint/grid.dart)의 쌓임 — 감독 결정 2026-10-25 "연도 세로줄은 띠 위에 안 그려지게 · 뒷바탕으로만" · 14시 "다 막아줘" ·
// 15시 "맨 아래 연도 쭉 그려져 있고 그 위에 차례대로 얹는 것처럼".
// 예전에는 보통 밀도에서 세로 점선 · 0년 파선을 띠 · 칸을 다 그린 뒤(사건 앞)에 그어 띠 위로 지나갔다(지금 연표의 격자 상자 z-index 1).
// 이제는 **그림판 바탕 바로 위에 몸통 높이 통째로 한 번 긋고, 그 위에 그림 층을 차례대로 얹기만 한다**(줄을 빼는 셈은 없다).
// 띠 쪽 그림은 아래를 가리는 종이(불투명 — 반투명 칠은 그 자리 바탕색과 미리 섞은 불투명 색 · 테만 있는 칸은 테 안에 바탕색 종이)라
// 그 자리의 줄은 저절로 덮이고, 띠 사이 빈 바탕에는 아무것도 얹지 않으니 줄이 그대로 남는다:
//   ① 불투명한 띠 칠 안에서는 눈금이 보이지 않고, 띠 밖의 바탕에서는 그대로 보인다.
//   ② 표시(기준선 — 현재선 · 기간 재기도 같은 걸음)는 그대로 띠 위다.
//   ③ 바탕 문화(제 색 9% — 바탕색과 섞은 불투명 종이)는 칠이 있는 데까지 — 옅어지는 두 끝(조각 폭의 10%)까지 — 눈금이 없다.
//      빛은 9%를 바탕에 얹은 색(±1) · 끝은 바탕색. ③-2 그 종이는 뒤 판의 맨 앞(그릇 칠 바로 뒤)에 깔려 매단 이름표 · 바탕 문화 이름이 그 위다(9%에 물들지 않는다).
//   ④ 속국의 받침 카드와 그 둘레의 바탕빛 틈은 꼬리표의 보이는 몸통까지 · 카드가 비치는 자리에만 — 사건 칸을 올려 줄 몫보다 짧은
//      꼬리표 밑의 바탕에는 눈금이 그대로 보인다(띠 사이 빈 바탕에는 줄이 남는다).
//   ⑤ 흐린 띠(다른 띠를 고른 동안 .58 · 검색 강조 밖 .2 — 바탕색과 섞은 불투명 종이)의 꼬리표 안에도 눈금이 없다.
//      빛은 밝은 빛을 그 알파로 바탕에 얹은 색(±1). ⑤-2 그릇 안의 흐린 띠는 그릇 종이 빛에 얹은 색(±1).
//   ⑥ 그릇(폴더) 몸통의 옅은 칠(9% — 불투명 종이) 안에도 — 띠가 없는 몫까지 · 어깨 탭까지 — 눈금이 없다. 그릇 밖 바탕은 그대로.
//      몸통 · 탭 빛은 그릇 색 9%를 바탕에 얹은 색(±1). ⑥-2 사람 띠의 실은 그릇 종이 위라 그릇 안에서도 보인다.
//   ⑦ 기관 칸(칠 없이 빗금 · 테만 — 칸이 없는 꼬리표 밑 바탕에 선다 · 테 안에 바탕색 종이) 안에도 눈금이 없다.
//      그 층을 가진 띠의 기관 칸(띠 몸통 안)에는 종이를 깔지 않는다(몸통 빛 그대로).
//   ⑧ 꼬리표 밑 흰 사슬(왕조 칸 — 칠 없이 테만 · 테 안에 바탕색 종이) 안에도 · 흐린 띠의 사슬 안에도 눈금이 없다.
//   ⑨ 띠가 바탕으로 녹아드는 끝(미정 꼬리 44px · 문화 띠 끝 12% — 그 자리 바탕색으로 녹는 불투명 그러데이션)도 칠이 있는 데까지 눈금이 없다.
//   ⑩ 막 도착해 떠오르는 타일(200ms — 밑에 메움 타일이 없으면 투명도 대신 바탕색에서 짙어진다)의 띠 안에도 눈금이 없다.
//      빛은 다 뜬 빛과 바탕색 사이(±2). 메움 타일이 밑에 있으면 예전처럼 층째 투명도로 엇갈려 바꾼다(그 열쇠 hasUnder).
//   ⑪ 문화권 머리 단(왼쪽 칸과 그림판을 가로지르는 불투명 칠)과 그 안의 사람 띠에도 눈금이 없다.
//   ⑫ 칠 없이 점선 테만 있는 받침 카드(명목상 소속)의 드러난 윗단 안에도 눈금이 없다(테 안에 바탕색 종이).
//   ⑬ 집합 보기의 판 둘레(보는 방법이 깐 가로 전체 판)는 칠을 반투명 그대로 두어 그 안 빈 바탕의 눈금이 그대로다.
//      판 안의 그릇은 판 빛 위에 9%를 얹은 불투명 종이(±1).
//   ⑭ 접힌 민족 줄(여러 줄을 한 줄로 — 90° 줄무늬)의 띠 몸통 자리에는 눈금이 없다(줄무늬 밑에 바탕색 종이 · 줄무늬는 그대로 · 위아래 바탕 줄은 남음).
//   ⑮ 매단 속국 이름표 · 구역 탭(띠 아래 바탕에 매단 것 — 고른 동안 .5) 안에도 눈금이 없다 — 빛은 밝은 빛을 .5로 바탕에 얹은 색(±1).
//   ⑯ 흐린 상국 탭 · 연합 겹 탭 · 받침 카드 윗단(띠 윗변 위 바탕에 선 것) 안에도 눈금이 없다 — 빛은 상국 빛깔 종이를 그 알파로 바탕에 얹은 색(±1).
//   ⑰ SVG 내보내기도 같은 차례 · 같은 불투명 색이다 — 눈금은 몸통 높이 통째 1px 무늬 네모 하나씩(빼기 없음)으로 바탕 종이 바로 다음에 적히고,
//      그릇 · 흐린 띠 · 바탕 문화의 칠은 fill-opacity 없는 불투명 색(종이에 얹은 색 ±1) · 바탕 문화는 매단 이름표보다 · 그릇은 실보다 앞에 적힌다.
//   ⑱ 열쇠표 · 플래그(띠 윗변 위 바탕에 선 것 — 고른 동안 .5) 안에도 눈금이 없다 — 빛은 바탕에 얹은 색(±1).
//   ⑲ 그리개의 걸음 차례: 눈금 → 바탕 종이(접힌 줄) → 그릇 → 바탕 문화 → 칠 없는 받침 카드의 종이 → 사람 띠의 실 → 관계선 → 매단 것 → 받침 카드 → 띠.
//      ⑭-2 접힌 줄 종이는 그릇보다 먼저라 펼친 그릇 안의 접힌 줄에서도 그릇 테 · 안쪽 겹선이 그대로다.
//   ㉑ 조감의 현재선은 띠 아래이되 대범위 테두리 · 그릇 종이 위 — 테두리 안에서도 보인다.
//   ㉒ 띠 끝이 px 사이에 선 기둥(칠이 일부만 덮음 · 흐린 띠의 반투명 세로 테가 선 기둥)에도 눈금 점선이 비치지 않는다(그 기둥 밑에 바탕색 종이).
//   ㉓ 반투명이던 띠 귀(옅어지는 끝 · 흐린 띠)의 종이는 무늬 · 깃대보다 먼저 깔린다 — 귀 칸 안의 제 점무늬 · 빗금이 그대로.
// 눈금 픽셀은 점선(1 켜고 1 끔)이라 '양옆 두 기둥이 위아래 두 줄에서 모두 같은 색인데 이 기둥만 위아래가 다르다'로 알아본다
// (띠 칠 · 점무늬 · 가로 금은 이 꼴이 아니다).

const m = 1000000.0;
final ppm = 32 / bucketMinutes(9);

/// 그림 영역 왼쪽에서 [px]만큼(보는 범위의 왼쪽 끝이 0분이라 그대로 분).
double at(double px) => px / ppm;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 160, 'band_top': 19, 'band_h': 141, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1), row(2)]},
  ],
});

/// 1920×1080 · 단계 9(통 32px — 1m ≈ 122px)의 타일 하나. 화면 왼쪽 끝은 0분(1970년)이라 0년 파선과 현재선은 화면 밖이다.
/// [clock]을 주고 [fade]면 타일이 도착 뒤 200ms 동안 떠오른다(그 밖에는 바로 다 보인다). [text]를 주면 그 글자 뒷단으로 그린다(SVG — [SvgText]).
(TimelineScene, TimelinePainter) make(void Function(TileBuilder) build,
    {SceneLayout? shape, double Function()? clock, bool fade = false, Future<Map<String, dynamic>> Function(Map<String, dynamic>)? ask, SceneText? text}) {
  final controller = TimelineController()
    ..reduceMotion = !fade
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(480);
  final builder = TileBuilder(level: 9, x: 0, chunk: 0);
  build(builder);
  final bytes = builder.build();
  final scene = TimelineScene(
    controller: controller,
    layout: shape ?? layout(),
    clock: clock,
    ask: ask,
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  if (!fade) scene.hide.add('fade');
  if (ask != null) scene.applyLayoutToView();
  controller.showRange(0, (1920 - scene.layout.gutterWidth) / ppm);
  return (scene, TimelinePainter(scene, text: text ?? unbudgetedText())..debug = true);
}

Future<ByteData> settleAndRender(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  for (int i = 0; i < 20 && (i == 0 || painter.text.starved); i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
  return render(painter);
}

Future<ByteData> render(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!;
}

int px(ByteData p, int x, int y) => p.getUint32((y * 1920 + x) * 4);

/// 기둥 [x]의 [y0] ~ [y1]에서 점선 눈금이 보이는 자리 수 — 양옆 기둥이 (y, y + 1) 두 줄에서 모두 같은 색인데 이 기둥만 두 줄이 다르다.
int lineHits(ByteData p, int x, int y0, int y1) {
  var n = 0;
  for (int y = y0; y < y1; y++) {
    final side = px(p, x - 1, y);
    if (px(p, x + 1, y) != side || px(p, x - 1, y + 1) != side || px(p, x + 1, y + 1) != side) continue;
    if (px(p, x, y) != px(p, x, y + 1)) n++;
  }
  return n;
}

/// 띠가 없는 바탕([y0] ~ 1060 — 기본은 줄 아래 700부터)에서 눈금이 보이는 기둥들.
List<int> gridColumns(ByteData p, {int y0 = 700}) => [for (int x = SceneView.gutter.toInt() + 2; x < 1918; x++) if (lineHits(p, x, y0, 1060) > 20) x];

ui.Rect bandRect(TimelinePainter painter, int id) => painter.debugSink.bands.firstWhere((b) => b.id == id).rect;

/// 그 [rect] 안(가장자리 [inset] 빼고 · 가로는 [insetX] — 꼬리표의 귀 밖은 바탕이라 귀 자리를 뺄 때)을 지나는 눈금 기둥마다 눈금이 보이는 자리 수 —
/// 모두 0이어야 한다. 지나는 기둥이 [least]개 이상이어야 검사가 뜻을 가진다.
void expectNoLines(ByteData pixels, List<int> columns, ui.Rect rect, String what, {double inset = 3, double? insetX, int least = 1}) {
  final ix = insetX ?? inset;
  final inside = [for (final x in columns) if (x > rect.left + ix && x < rect.right - ix) x];
  expect(inside.length, greaterThanOrEqualTo(least), reason: '$what: 지나는 눈금 기둥 $columns · 자리 $rect');
  for (final x in inside) {
    expect(lineHits(pixels, x, (rect.top + inset).ceil(), (rect.bottom - inset).floor()), 0, reason: '$what(기둥 $x · ${rect.top.round()} ~ ${rect.bottom.round()})에 눈금이 비친다');
  }
}

/// 검사 기록의 '… l,t,w,h'(10배 정수)를 네모로.
ui.Rect rectOf10(String note) {
  final v = note.split(' ').last.split(',').map((s) => double.parse(s) / 10).toList();
  return ui.Rect.fromLTWH(v[0], v[1], v[2], v[3]);
}

/// 두 장 꼬리표 줄 셋(줄 값이 실린 새 저장소 — 칸 층 비트 19 · 줄에 지도자 층 비트 17): 꼬리표 = 이름 색줄 14 + 지도자 층 14 + 사건 칸 18.
/// 지도자 칸이 없는 띠는 사건 칸을 남의 층(14)만큼 올려 줄 몫(띠 아랫변)보다 짧다(TagLook.eventLift). [organ]이면 줄에 기관 층(비트 6)도 있다.
SceneLayout twoPiece({bool organ = false}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'leader': 0, 'organ': organ ? 1 : 0,
      'rows': [
        for (final id in [0, 1, 2])
          {...row(id), 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
            'fig_wide': (1 << 3) | (1 << 17) | (1 << 19) | (organ ? 1 << 6 : 0), 'dep': 0, 'zones': 0, 'hem': 0},
      ],
    },
  ],
});

/// 그림이 돌려주는 0xRRGGBBAA(불투명)로.
int rgba(int argb) => ((argb & 0x00ffffff) << 8 | 0xff) & 0xffffffff;

/// 그림의 0xRRGGBBAA가 불투명 [argb]와 채널마다 ±1 안인가(미리 섞은 색과 알파 합성의 반올림 차이).
Matcher nearRgba(int argb) => predicate<int>((got) => closeRgba(got, argb), '0x${rgba(argb).toRadixString(16)} ±1');

/// [nearRgba]의 참 · 거짓.
bool closeRgba(int got, int argb) {
  final want = rgba(argb);
  for (final s in [24, 16, 8, 0]) {
    if ((((got >> s) & 0xff) - ((want >> s) & 0xff)).abs() > 1) return false;
  }
  return true;
}

/// style에 함께 실리는 순번(계약 6-2 — 비트 15~26 순번 + 1).
int seqStyle(int seq) => (seq + 1) << 15;

/// 그릇(할거 '남곡 할거' — 줄 2 ~ 4 · 화면 100 ~ 1500px, 그릇 색 0xd4a39b) 하나와 그 오른쪽 몫(800 ~ 1400px)의 띠 셋(12 · 13 · 14 — 줄 2 · 3 · 4).
/// 왼쪽 몫(100 ~ 800)은 띠 없이 그릇 칠만 있다.
(TimelineScene, TimelinePainter) folderScene({SceneText? text}) {
  Map<String, dynamic> low(int id) => {
    'id': id, 'height': 80, 'band_top': 19, 'band_h': 61, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 40, 'text_lines': 1, 'rail_top': -1,
    'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0,
  };
  final shape = SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '등불 기록집', 'events': 0}],
    'tracks': [
      {'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xa0bcc5, 'rows': [for (int r = 0; r < 6; r++) low(r)]},
    ],
    'epochs': [],
    'variants': [
      {
        'id': 1, 'key': 'scope:s2', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's2', 'name': '남곡 할거',
        'rows': [
          for (final (i, r) in [2, 3, 4].indexed) {'row': r, 'after': r - 1, 'ord': 0, 'new': 0, 'scope_pad': i == 0 ? 16 : 0, 'group_start': i == 0 ? 1 : 0},
          {'row': 5, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
        ],
        'groups': [
          {'key': '__scope:s2', 'depth': 0, 'name': '남곡 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [2, 3, 4]},
        ],
      },
    ],
  })..reduceMotion = true;
  return make((t) {
    t.item(ScopeLayer.secScope, 1, 2, at(100), at(1500), row2: 4, name: '남곡 할거', color: 0xd4a39b, b: 3, text2: 's2\u001f시대');
    for (final r in [2, 3, 4]) {
      t.band(10 + r, r, at(800), at(1400), '나라 $r', color: 0xacb4ca);
    }
  }, shape: shape, text: text, ask: (query) async {
    if (query['op'] == 'rows_near') {
      final all = [for (int r = 0; r < 6; r++) r];
      return {'near': all, 'far': all};
    }
    return {};
  });
}

/// 줄 0(옛 저장소 — 덧단 줄 25 · 구역 4단 · 이름 단): 상국 띠 1 + 그 밑에 매단 이름표(단 0) + 같은 줄의 바탕 문화 3(짙은 색이라 9%가 물들면 몇 단이 바뀐다)
/// + 그 이름 단.
(TimelineScene, TimelinePainter) underHangScene({SceneText? text}) {
  final shape = SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
        'rows': [
          {
            'id': 0, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 0, 'text_lines': 2, 'rail_top': 0,
            'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0, 'dep': 25.0, 'zones': 4, 'hem': 1,
          },
        ],
      },
    ],
  });
  return make((t) {
    t.band(1, 0, 1 * m, 14 * m, '은륜 제국');
    t.band(3, 0, 2 * m, 13 * m, '유리항 매듭토기', look: BandKind.culture | BandLook.under, color: 0x204080);
    t.item(16, 101, 0, 3 * m, 9 * m, ref: 1, name: '별목 조공국', color: 0xa0bcc5, a: 0, b: 0, d: 21, text2: '속국:별목');
    t.item(18, 151, 0, 2 * m, 13 * m, ref: 3, name: '유리항 매듭토기', color: 0x204080, c: 1, text2: '문화');
  }, shape: shape, text: text);
}

/// 문화권(설령 방원권) 두 트랙 · 줄 0 ~ 1을 품은 그릇(설령 할거 — 1380 ~ 1500해)과, 그 안을 지나는 사람 띠(은 하림 — 줄 1의 띠 12에 실로 매달림).
/// 보는 범위는 1380 ~ 1500해.
(TimelineScene, TimelinePainter) crownFolderScene({SceneText? text}) {
  int year(double y) => minuteOfYear(y).round();
  Map<String, dynamic> crownRow(int id) => {
    'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 0, 'text_lines': 2, 'rail_top': 0,
    'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0, 'dep': 0, 'zones': 0, 'hem': 0,
  };
  final shape = SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '왕관 기록집', 'events': 0}],
    'tracks': [
      {'id': 1, 'pack': 1, 'ord': 0, 'name': '설령 왕국', 'color': 0xa0bcc5, 'leader': 1, 'rail_levels': 2, 'sphere': 'north', 'rows': [crownRow(0)]},
      {'id': 2, 'pack': 1, 'ord': 1, 'name': '북쪽 칸국', 'color': 0xc8b193, 'leader': 1, 'rail_levels': 2, 'sphere': 'north', 'rows': [crownRow(1)]},
    ],
    'epochs': <dynamic>[],
    'spheres': [{'id': 'north', 'name': '설령 방원권', 'count': 2, 'default': true}],
    'sphereLines': [
      {'kind': 1, 'sphere': 'north', 'start': year(1420), 'end': year(1455), 'name': '은 하림', 'uid': 'fig-은 하림', 'data': '[{"uid":"b2","cell":0}]'},
    ],
  })..reduceMotion = true;
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
    ..setContentHeight(shape.totalHeight);
  // 그릇(줄 0 ~ 1 · 1380 ~ 1500해)을 모든 타일에 — 잘린 조각은 잘린 쪽 표시와 함께(대범위 층이 번호로 잇는다).
  final scene = TimelineScene(controller: controller, layout: shape, fetchTile: (level, x, chunk, packs) async {
    final b = TileBuilder(level: level, x: x, chunk: chunk);
    final lo = year(1380) - b.origin, hi = year(1500) - b.origin;
    if (hi > 0 && lo < b.span) {
      b.item(ScopeLayer.secScope, 1, 0, lo < 0 ? 0 : lo.toDouble(), hi > b.span ? b.span.toDouble() : hi.toDouble(),
          row2: 1, name: '설령 할거', color: 0xd4a39b, flags: (lo < 0 ? Tile.clipLeft : 0) | (hi > b.span ? Tile.clipRight : 0));
    }
    return b.build();
  });
  scene.hide.add('fade');
  scene.crowns.put({'b2': CrownBand(12, 1, year(1390), year(1480), [CrownCell(year(1400), year(1460), seqStyle(0))])}, shape, store: scene.storeVersion);
  final painter = TimelinePainter(scene, text: text ?? unbudgetedText())..debug = true;
  controller.showRange(minuteOfYear(1380), minuteOfYear(1500));
  return (scene, painter);
}

/// 그릇(폴더) 검사 기록('폴더' — 이름 + l,t,w,h)의 몸통(어깨 탭 아래).
ui.Rect folderBody(TimelinePainter painter, String name) {
  final note = (painter.debugSink.notes['폴더'] ?? const []).map((n) => '$n').firstWhere((n) => n.startsWith('$name '), orElse: () => fail('그릇 $name을 그리지 않았다'));
  final v = note.split(' ').firstWhere((s) => s.split(',').length == 4).split(',').map(double.parse).toList();
  return ui.Rect.fromLTWH(v[0], v[1] + G.folderTab, v[2], v[3] - G.folderTab);
}

// ─────────── SVG(⑰) — 그림 저장과 같은 길로 적고, 몸통의 칠 조각을 적힌 차례대로 훑는다 ───────────

/// 다 가라앉힌 [painter]의 장면을 SVG 한 장으로(그림 저장 `buildExportSvg`와 같은 `paintSceneToSvg` — 그리개의 층 · 글자 뒷단 그대로).
Future<String> svgOf(TimelinePainter painter) async {
  final canvas = SvgCanvas(width: 1920, height: 1080);
  paintSceneToSvg(painter, canvas, const ui.Size(1920, 1080),
      text: painter.text as SvgText, quads: SvgQuads(), dividers: SvgLines(Look.line), patterns: SvgPatterns(), ruler: Ruler());
  expect(canvas.skipped, isEmpty, reason: 'SVG가 넘긴 그리기 호출');
  return canvas.toSvg();
}

/// SVG 몸통의 칠 조각 하나 — 적힌 자리([at] · 글 안의 차례) · 네모 · 색(0xrrggbb) · 짙기(fill-opacity) · 무늬 · 번짐의 id([url]) ·
/// 조각 그림판의 가림막이 있는가([masked]).
typedef SvgPiece = ({int at, ui.Rect r, int rgb, double a, String? url, bool masked});

final _pieceRe = RegExp(r'<(rect|path) ([^>]*?)/>');
final _pieceAttrRe = RegExp(r'([-a-zA-Z:]+)="([^"]*)"');
final _quadRe = RegExp(r'M(-?[\d.]+) (-?[\d.]+)H(-?[\d.]+)V(-?[\d.]+)H-?[\d.]+Z');

/// `</defs>` 뒤(몸통)의 `<rect>` · `<path>`(네모 묶음 — `M l t H r V b H l Z`가 여럿)를 적힌 차례대로 칠 조각으로.
List<SvgPiece> svgPieces(String svg) {
  final out = <SvgPiece>[];
  for (final m in _pieceRe.allMatches(svg, svg.indexOf('</defs>'))) {
    final at = {for (final a in _pieceAttrRe.allMatches(m.group(2)!)) a.group(1)!: a.group(2)!};
    final fill = at['fill'];
    if (fill == null || fill == 'none') continue;
    final url = fill.startsWith('url(#') ? fill.substring(5, fill.length - 1) : null;
    final rgb = url == null ? int.parse(fill.substring(1), radix: 16) : 0;
    final a = double.parse(at['fill-opacity'] ?? '1');
    if (m.group(1) == 'rect') {
      final r = ui.Rect.fromLTWH(double.parse(at['x']!), double.parse(at['y']!), double.parse(at['width']!), double.parse(at['height']!));
      out.add((at: m.start, r: r, rgb: rgb, a: a, url: url, masked: at.containsKey('mask')));
    } else {
      for (final q in _quadRe.allMatches(at['d']!)) {
        final r = ui.Rect.fromLTRB(double.parse(q.group(1)!), double.parse(q.group(2)!), double.parse(q.group(3)!), double.parse(q.group(4)!));
        out.add((at: m.start, r: r, rgb: rgb, a: a, url: null, masked: false));
      }
    }
  }
  return out;
}

/// `<defs>`의 무늬(`<pattern>`) id들. [body]를 주면 그 꼴로 시작하는 무늬만.
Set<String> svgPatternIds(String svg, {String body = ''}) =>
    {for (final m in RegExp('<pattern id="(h\\d+)"[^>]*>${RegExp.escape(body)}').allMatches(svg)) m.group(1)!};

/// `<defs>`의 번짐(`<linearGradient>`) id → 두 끝의 짙기(stop-opacity).
Map<String, (double, double)> svgFades(String svg) => {
  for (final m in RegExp(r'<linearGradient id="(h\d+)"[^>]*><stop offset="0" stop-color="#\w+" stop-opacity="([\d.]+)"/><stop offset="1" stop-color="#\w+" stop-opacity="([\d.]+)"/>')
      .allMatches(svg))
    m.group(1)!: (double.parse(m.group(2)!), double.parse(m.group(3)!)),
};

/// 세로 눈금(점선 — 가로 줄무늬 2px 주기 · 1px 줄 · 눈금 빛)의 무늬 id.
Set<String> svgGridIds(String svg) {
  final a = (GridLayer.gridLine >>> 24) & 0xff;
  return svgPatternIds(svg, body: '<rect x="0" y="0" width="2" height="1" fill="${svgHex(GridLayer.gridLine)}"${a == 0xff ? '' : ' fill-opacity="${svgNum(a / 255)}"'}/>');
}

/// ([x], [y])를 덮는 칠 가운데 맨 나중에 적힌 것 — 투명 조각 · 무늬([patterns]) · 조각 그림판(가림막)은 빼고 네모 칠과 번짐만 본다.
SvgPiece? svgTopAt(List<SvgPiece> pieces, Set<String> patterns, double x, double y) {
  for (int i = pieces.length - 1; i >= 0; i--) {
    final p = pieces[i];
    if (p.a == 0 || p.masked || (p.url != null && patterns.contains(p.url))) continue;
    if (p.r.contains(ui.Offset(x, y))) return p;
  }
  return null;
}

/// 조각의 색을 0xffrrggbb로.
int argbOf(SvgPiece p) => 0xff000000 | p.rgb;

void main() {
  tearDown(PaintPick.reset);

  test('① 불투명한 띠 칠 안에는 세로 눈금이 없다 — 띠 밖 바탕에는 그대로', () async {
    final (scene, painter) = make((t) => t.band(1, 0, 1 * m, 9 * m, '해솔국'));
    final pixels = await settleAndRender(scene, painter);
    final columns = gridColumns(pixels);
    expect(columns.length, greaterThan(5), reason: '바탕에 눈금 기둥이 여럿 보인다: $columns');
    final band = bandRect(painter, 1);
    // 이름 색줄 아래 · 아랫변 위(가로 금 · 귀 빼고) — 띠 칠 안의 눈금 기둥마다.
    final inside = [for (final x in columns) if (x > band.left + 14 && x < band.right - 14) x];
    expect(inside.length, greaterThan(3), reason: '띠가 덮는 눈금 기둥이 있어야 검사가 뜻을 가진다');
    for (final x in inside) {
      expect(lineHits(pixels, x, band.top.ceil() + 20, band.bottom.floor() - 3), 0, reason: '띠 칠 안 기둥 $x에 눈금이 보인다(띠 위에 그었다)');
    }
  });

  test('② 기준선은 그대로 띠 위다(연 단위 세로줄이 아닌 표시)', () async {
    final (scene, painter) = make((t) => t.band(1, 0, 1 * m, 9 * m, '해솔국'));
    final marks = SceneMarks.of(scene)
      ..marker = 5 * m
      ..version += 1;
    expect(marks.marker, 5 * m);
    final pixels = await settleAndRender(scene, painter);
    final band = bandRect(painter, 1);
    final x = scene.controller.view.xOf(5 * m).floor();
    final y = ((band.top + band.bottom) / 2).floor();
    // 2px 검은 세로선(`--warn`) — 띠 칠 위로 지나간다.
    expect([for (int dx = 0; dx <= 2; dx++) px(pixels, x + dx, y)], contains(0x000000ff), reason: '띠 가운데에서 기준선이 보인다');
  });

  test('③ 바탕 문화(바탕색과 섞은 불투명 종이)는 칠이 있는 데까지 — 옅어지는 두 끝까지 — 눈금을 덮는다 · 칠 밖 바탕은 그대로', () async {
    final (scene, painter) = make((t) => t.band(2, 1, 4 * m, 12 * m, '은가지 목간 문화', look: BandKind.culture | BandLook.under));
    final pixels = await settleAndRender(scene, painter);
    final columns = gridColumns(pixels);
    final under = bandRect(painter, 2);
    final width = under.right - under.left, soft = width * .10;
    // 가운데(칠이 제 짙기 9%)와 옅어지는 두 끝(폭의 10% — 바깥 끝으로 갈수록 칠이 0에 가깝다) 모두 눈금이 없다.
    expectNoLines(pixels, columns, under, '바탕 문화 칠', inset: 1, least: 4);
    final ends = [for (final x in columns) if ((x > under.left + 1 && x < under.left + soft) || (x < under.right - 1 && x > under.right - soft)) x];
    expect(ends, isNotEmpty, reason: '옅어지는 끝을 지나는 눈금 기둥: $columns · 띠 ${under.left} ~ ${under.right} · 끝 폭 $soft');
    // 같은 기둥의 다른 줄(줄 0 · 2 — 띠가 없는 몫)에서는 눈금이 그대로다.
    for (final x in [for (final x in columns) if (x > under.left + 1 && x < under.right - 1) x]) {
      expect(lineHits(pixels, x, under.bottom.ceil() + 2, 1060), greaterThan(20), reason: '바탕 문화 아래 바탕의 기둥 $x에는 눈금이 있다');
    }
    // 빛: 가운데는 제 색 9%를 바탕에 얹은 색(±1) — 눈금 기둥 위에서도(점선의 켠 점 · 끈 점 두 줄 모두). 바깥 끝은 바탕색으로 녹는다(±1).
    final paper = over(withAlpha(0xffa0bcc5, .09), Look.ground);
    final mid = [for (final x in columns) if (x > under.left + soft + 4 && x < under.right - soft - 4) x];
    expect(mid, isNotEmpty, reason: '가운데를 지나는 눈금 기둥: $columns');
    final y = ((under.top + under.bottom) / 2).floor();
    for (final x in mid) {
      for (final yy in [y, y + 1]) {
        expect(px(pixels, x, yy), nearRgba(paper), reason: '바탕 문화 가운데(기둥 $x · y $yy)는 9% 종이 빛');
      }
    }
    expect(px(pixels, (under.left + 2).floor(), y), nearRgba(Look.ground), reason: '왼쪽 끝은 바탕색으로 녹는다');
    expect(px(pixels, (under.right - 3).floor(), y), nearRgba(Look.ground), reason: '오른쪽 끝은 바탕색으로 녹는다');
  });

  test('③-2 바탕 문화 종이는 매단 이름표 · 바탕 문화 이름 아래다 — 그것들이 9% 칠에 물들지 않는다', () async {
    // 줄 0: 상국 띠 + 그 밑에 매단 이름표(단 0) + 같은 줄의 바탕 문화(짙은 색이라 9%가 물들면 몇 단이 바뀐다) + 그 이름 단([underHangScene]).
    Future<(ByteData, TimelinePainter)> shot(String? hide) async {
      final (scene, painter) = underHangScene();
      // 띠 칠을 끈 그림(bandFill) · 매단 것을 뺀 그림(hangs)과 견준다 — 매단 것이 종이 위면 칠 밖 빛은 칠이 있든 없든 같고, 글자 빛은 그 자리 종이 빛에 얹힌다.
      if (hide != null) scene.hide.add(hide);
      return (await settleAndRender(scene, painter), painter);
    }

    final (lit, painter) = await shot(null);
    final (bare, _) = await shot('bandFill');
    final (paperOnly, _) = await shot('hangs');
    final marks = [for (final n in painter.debugSink.notes['hang'] ?? const <Object>[]) if (n is HangMark) n];
    final tab = marks.firstWhere((h) => h.kind == 'hang', orElse: () => fail('매단 이름표를 그리지 않았다: $marks')).rect;
    final hem = marks.firstWhere((h) => h.kind == 'hem', orElse: () => fail('바탕 문화 이름을 그리지 않았다: $marks')).rect;
    final under = bandRect(painter, 3);
    expect(tab.top, greaterThan(under.top), reason: '이름표는 바탕 문화 칠 안');
    expect(tab.bottom, lessThan(under.bottom), reason: '이름표는 바탕 문화 칠 안');
    // 이름표 칠 안(테 · 귀 · 이름 빼고 오른쪽 몫) — 칠이 있든 없든 같은 픽셀.
    final ty = ((tab.top + tab.bottom) / 2).floor();
    var same = 0;
    for (int x = (tab.right - 30).floor(); x < tab.right - 4; x++) {
      expect(px(lit, x, ty), px(bare, x, ty), reason: '매단 이름표(x $x · y $ty)가 바탕 문화 칠에 물들었다');
      same++;
    }
    expect(same, greaterThan(10));
    // 이름 글자의 속(덮임 1 — 칠을 끈 그림에서 글자 빛을 바탕에 얹은 색 그대로인 픽셀): 칠 위면 글자 빛(85%)을 그 자리 종이 빛(매단 것을 뺀 그림 —
    // 9% 종이 · 점무늬)에 얹은 색(±1). 예전(칠 밑)이면 9% 칠이 글자 위에 얹혀 파랑 쪽이 몇 단 달랐다(글자 빛과 문화 빛의 차 × 9% × 85%).
    final text = withAlpha(mixSrgb(0xff204080, Look.ink, .30), .85);
    final core = over(text, Look.ground);
    var ink = 0;
    for (int y = hem.top.ceil(); y < hem.bottom; y++) {
      for (int x = hem.left.ceil(); x < hem.right; x++) {
        if (!closeRgba(px(bare, x, y), core)) continue;
        final paper = 0xff000000 | (px(paperOnly, x, y) >>> 8);
        expect(px(lit, x, y), nearRgba(over(text, paper)), reason: '바탕 문화 이름(x $x · y $y)은 종이 ${paper.toRadixString(16)} 위 — 칠에 물들지 않는다');
        ink++;
      }
    }
    expect(ink, greaterThan(20), reason: '바탕 문화 이름의 글자 속 픽셀');
  });

  test('④ 받침 카드 · 바탕빛 틈은 꼬리표의 보이는 몸통까지 — 사건 칸을 올린 속국 꼬리표 밑의 바탕에는 눈금이 그대로', () async {
    const host = 0x8b6f47;
    final (scene, painter) = make((t) {
      t.band(1, 0, 1 * m, 3 * m, '별여울국', look: 1 << 20 | 1 << (21 + 5)); // 지도자 층을 가진 띠 — 줄에 지도자 층이 선다
      t.band(2, 0, 4 * m, 12 * m, '갈대 공국'); // 칸 없는 속국 — 사건 칸을 지도자 층만큼 올린 짧은 꼬리표
      t.item(BandLayer.sectionHostTab, 52, 0, 4 * m, 12 * m, ref: 2, name: '하연 왕국', color: host, a: 1, d: 99, text2: 'p/hayeon');
    }, shape: twoPiece());
    final pixels = await settleAndRender(scene, painter);
    expect(painter.debugSink.notes['뒤장'], hasLength(1), reason: '속국 띠 뒤의 받침 카드 한 장');
    final geo = scene.layout.geo(0), band = bandRect(painter, 2);
    final full = band.top + geo.bandHeight; // 줄 몫의 띠 아랫변(예전 카드 · 틈의 아랫변)
    expect(full - band.bottom, G.floor, reason: '속국 꼬리표는 남의 지도자 층만큼 짧다');
    final columns = gridColumns(pixels);
    final inside = [for (final x in columns) if (x > band.left + 14 && x < band.right - 14) x];
    expect(inside.length, greaterThan(3), reason: '속국 꼬리표 밑을 지나는 눈금 기둥: $columns');
    for (final x in inside) {
      expect(lineHits(pixels, x, band.bottom.ceil() + 1, full.floor()), greaterThan(3), reason: '꼬리표 몸통 밑 바탕(기둥 $x)에 눈금이 있다 — 카드 · 틈이 덮지 않는다');
      expect(lineHits(pixels, x, band.top.ceil() + 20, band.bottom.floor() - 3), 0, reason: '꼬리표 칠 안(기둥 $x)에는 눈금이 없다');
    }
    // 카드는 그대로 띠 위로 5 드러나고(카드 칠), 띠 윗변 바로 위 1.5는 바탕빛 틈이다. 몸통 밑에는 카드가 없다(바탕).
    final card = rgba(mixOklab(0xff000000 | host, Look.paper, BandLayer.sheetMix[1]));
    final x = [for (int x = (band.left + 40).floor(); x < band.right - 40; x++) x].firstWhere((x) => columns.every((g) => (g - x).abs() > 2));
    expect(px(pixels, x, (band.top - BandLayer.sheetRise + 2).floor()), card, reason: '카드의 드러난 윗단');
    expect(px(pixels, x, (band.top - 1).floor()), rgba(Look.ground), reason: '띠와 카드 사이의 바탕빛 틈');
    for (final y in [band.bottom + 3, full - 2]) {
      expect(px(pixels, x, y.floor()), rgba(Look.ground), reason: '꼬리표 몸통 밑($y)은 카드가 아니라 바탕');
    }
    // 카드의 드러난 윗단(띠 윗변 위 5) 안에도 눈금이 없다.
    expectNoLines(pixels, columns, ui.Rect.fromLTRB(band.left, band.top - BandLayer.sheetRise, band.right, band.top), '카드 윗단', inset: 0, least: 3);
  });

  test('⑤ 흐린 띠(다른 띠를 고른 동안 .58 · 검색 강조 밖 .2)의 꼬리표 안에도 눈금이 비치지 않는다 — 밝은 띠와 바탕은 그대로', () async {
    // 밝은 그림(고르지 않음)의 띠 2 빛 — 흐린 빛은 이것을 그 알파로 바탕에 얹은 색이어야 한다(±1).
    final (scene0, painter0) = make((t) {
      t.band(1, 0, 1 * m, 9 * m, '해솔국');
      t.band(2, 1, 1 * m, 9 * m, '별여울국');
    });
    final bright = await settleAndRender(scene0, painter0);
    for (final (what, look) in [('고른 동안', const em.Look(band: 1)), ('검색 강조 밖', const em.Look(bands: {1}, events: <int>{}))]) {
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 9 * m, '해솔국');
        t.band(2, 1, 1 * m, 9 * m, '별여울국');
      });
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(look);
      final pixels = await settleAndRender(scene, painter);
      final alpha = em.Emphasis.of(scene).bandAlpha(2, 1);
      expect(alpha, lessThan(1), reason: '$what: 띠 2는 흐리다');
      final columns = gridColumns(pixels);
      for (final id in [1, 2]) {
        final band = bandRect(painter, id);
        final inside = [for (final x in columns) if (x > band.left + 14 && x < band.right - 14) x];
        expect(inside.length, greaterThan(3), reason: '$what: 띠 $id를 지나는 눈금 기둥');
        for (final x in inside) {
          expect(lineHits(pixels, x, band.top.ceil() + 20, band.bottom.floor() - 3), 0, reason: '$what: 띠 $id의 칠 안(기둥 $x)에 눈금이 비친다');
        }
      }
      expect(columns.length, greaterThan(5), reason: '$what: 띠 밖 바탕에는 눈금이 그대로');
      // 흐린 빛 = 밝은 빛을 그 알파로 바탕에 얹은 색(±1) — 이름 색줄 · 몸통(종이) 두 켜, 이름 글자를 피한 오른쪽 몫의 눈금 기둥 위에서.
      final band = bandRect(painter, 2);
      final right = [for (final x in columns) if (x > band.left + 300 && x < band.right - 14) x];
      expect(right, isNotEmpty);
      for (final x in right) {
        for (final y in [band.top + 6, band.top + 7, band.top + 40, band.top + 41]) {
          final was = px(bright, x, y.floor());
          final want = over(withAlpha(0xff000000 | (was >>> 8), alpha), Look.ground);
          expect(px(pixels, x, y.floor()), nearRgba(want), reason: '$what: 흐린 띠 2(기둥 $x · y $y)의 빛 — 밝은 빛 ${was.toRadixString(16)}');
        }
      }
    }
  });

  test('⑤-2 그릇 안의 흐린 띠는 그릇 종이 빛과 섞인 불투명 색이다(±1) · 눈금 없음', () async {
    final (scene0, painter0) = folderScene();
    final bright = await settleAndRender(scene0, painter0);
    final (scene, painter) = folderScene();
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(band: 12));
    final pixels = await settleAndRender(scene, painter);
    final alpha = em.Emphasis.of(scene).bandAlpha(13, 3);
    expect(alpha, lessThan(1), reason: '띠 13은 흐리다');
    final below = (scene.controller.view.yOf(scene.layout.totalHeight) + 4).ceil();
    final columns = gridColumns(pixels, y0: below);
    final band = bandRect(painter, 13);
    expectNoLines(pixels, columns, band, '그릇 안 흐린 띠', insetX: 14, least: 3);
    // 그릇 종이(그릇 색 9%를 바탕에 얹은 색) 위에 밝은 빛을 그 알파로 얹은 색.
    final paper = over(withAlpha(0xffd4a39b, .09), Look.ground);
    final y = ((band.top + band.bottom) / 2).floor();
    final xs = [for (final x in columns) if (x > band.left + 14 && x < band.right - 14) x];
    for (final x in xs) {
      final was = px(bright, x, y);
      expect(px(pixels, x, y), nearRgba(over(withAlpha(0xff000000 | (was >>> 8), alpha), paper)), reason: '그릇 안 흐린 띠(기둥 $x)의 빛');
    }
  });

  test('⑥ 그릇(폴더) 몸통의 옅은 칠(9%) 안에는 — 띠가 없는 몫까지 — 눈금이 없다 · 그릇 밖 바탕은 그대로', () async {
    final (scene, painter) = folderScene();
    final pixels = await settleAndRender(scene, painter);
    final folder = (painter.debugSink.notes['폴더'] ?? const []).map((n) => '$n').firstWhere((n) => n.startsWith('남곡 할거 '));
    final v = folder.split(' ').last.split(',').map(double.parse).toList();
    final box = ui.Rect.fromLTWH(v[0], v[1] + G.folderTab, v[2], v[3] - G.folderTab); // 몸통(어깨 탭 아래)
    final below = (scene.controller.view.yOf(scene.layout.totalHeight) + 4).ceil();
    final columns = gridColumns(pixels, y0: below);
    expect(columns.length, greaterThan(5), reason: '그릇 밖 바탕(줄 아래)에는 눈금이 그대로: $columns');
    expectNoLines(pixels, columns, box, '그릇 몸통 칠', least: 4);
    // 띠가 없는 왼쪽 몫(100 ~ 800)을 지나는 기둥이 있어야 '띠가 아니라 그릇 칠이 뺐다'가 된다.
    final left = scene.controller.view.left;
    final bare = [for (final x in columns) if (x > box.left + 3 && x < left + 790) x];
    expect(bare, isNotEmpty, reason: '띠 없는 그릇 몫을 지나는 기둥');
    // 몸통 색 = 그릇 색 9%를 바탕에 얹은 색(±1) — 눈금 기둥 위에서도(점선의 켠 점 · 끈 점 두 줄 모두).
    final paper = over(withAlpha(0xffd4a39b, .09), Look.ground);
    for (final x in bare) {
      for (final y in [box.top + 10, box.top + 11]) {
        expect(px(pixels, x, y.floor()), nearRgba(paper), reason: '몸통(기둥 $x · y $y)은 그릇 종이 빛');
      }
    }
    // 어깨 탭(라벨 종이 밑 두 줄 — 몸통 윗변 위 1 · 2)도 같은 종이 빛이고 눈금이 없다.
    final tab = (painter.debugSink.notes['폴더탭'] ?? const []).map((n) => '$n').firstWhere((n) => n.startsWith('남곡 할거 '));
    final span = tab.split(' ').firstWhere((s) => s.contains('~')).split('~').map(double.parse).toList();
    final inTab = [for (final x in columns) if (x > span[0] + FolderLook.shoulder + 1 && x < span[1] - FolderLook.shoulder - 1) x];
    expect(inTab, isNotEmpty, reason: '탭을 지나는 기둥: $columns · 탭 $span');
    for (final x in inTab) {
      for (final y in [box.top - 1, box.top - 2]) {
        expect(px(pixels, x, y.floor()), nearRgba(paper), reason: '탭(기둥 $x · y $y)은 그릇 종이 빛');
      }
    }
  });

  test('⑥-2 사람 띠의 실은 그릇 종이 위다 — 그릇 안에서도 실이 보인다(불투명 종이 밑에 깔리면 사라진다)', () async {
    final (scene, painter) = crownFolderScene();
    final pixels = await settleAndRender(scene, painter);
    final box = folderBody(painter, '설령 할거');
    final body = box.top;
    final t = painter.threads.threads.single;
    expect(t.x, inExclusiveRange(box.left + 20, box.right - 20), reason: '실이 그릇 안을 지난다');
    expect(t.to, greaterThan(body + 20), reason: '실이 그릇 몸통 안으로 내려간다 — 몸통 $body · 실 ${t.from} ~ ${t.to}');
    // 실 기둥(실은 .5 자리 — 그 픽셀)과 그 옆 기둥(그릇 종이)이 다른 줄이 점선의 켠 점마다 있다.
    final x = t.x.floor();
    final from = (math.max(t.from, body) + 3).ceil(), to = t.to.floor();
    var shown = 0;
    for (int y = from; y < to; y++) {
      if (px(pixels, x, y) != px(pixels, x + 3, y)) shown++;
    }
    expect(shown, greaterThan((to - from) ~/ 4 - 2), reason: '그릇 안($from ~ $to)에서 실의 점선이 보인다');
  });

  test('⑦ 기관 칸(칠 없이 빗금 · 테만 — 칸 없는 꼬리표 밑 바탕에 선다) 안에도 눈금이 없다', () async {
    final (scene, painter) = make((t) {
      t.band(1, 0, 1 * m, 12 * m, '해솔국'); // 칸 없는 띠 — 꼬리표는 색줄 + 사건 칸뿐이라 줄의 기관 층 자리는 꼬리표 밑 바탕이다
      t.cell(301, 0, 1.5 * m, 11 * m, '바다 관청', kind: 3, style: seqStyle(0));
    }, shape: twoPiece(organ: true));
    final pixels = await settleAndRender(scene, painter);
    final notes = [for (final n in painter.debugSink.notes['칸'] ?? const <Object>[]) '$n'];
    final organ = rectOf10(notes.firstWhere((n) => n.startsWith('3:0:'), orElse: () => fail('기관 칸을 그리지 않았다: $notes')));
    final band = bandRect(painter, 1);
    expect(organ.bottom, greaterThan(band.bottom + 4), reason: '기관 칸은 꼬리표 밑(띠 칠 밖)까지 내려선다 — 띠 $band · 칸 $organ');
    final columns = gridColumns(pixels);
    expectNoLines(pixels, columns, organ, '기관 칸', inset: 2, least: 4);
    // 칸 안 빈자리는 바탕색 종이(칠 없음 — 빛은 바탕 그대로).
    final y = ((organ.top + organ.bottom) / 2).floor();
    var ground = 0;
    for (int x = (organ.left + 40).floor(); x < organ.right - 40; x++) {
      if (px(pixels, x, y) == rgba(Look.ground)) ground++;
    }
    expect(ground, greaterThan(100), reason: '기관 칸 안 빈자리는 바탕색');

    // 그 층을 가진 띠(기관 비트)의 기관 칸은 띠 몸통 안이다 — 몸통 칠이 이미 불투명이라 종이를 깔지 않는다(깔면 몸통 빛이 바탕색으로 바뀐다).
    Future<(ByteData, TimelinePainter)> inBody({required bool cells}) async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 12 * m, '해솔국', look: 1 << 20 | 1 << (21 + 8));
        t.cell(301, 0, 1.5 * m, 11 * m, '바다 관청', kind: 3, style: seqStyle(0));
      }, shape: twoPiece(organ: true));
      if (!cells) scene.hide.add('cells');
      return (await settleAndRender(scene, painter), painter);
    }

    final (lit, painter2) = await inBody(cells: true);
    final (bare, _) = await inBody(cells: false);
    final notes2 = [for (final n in painter2.debugSink.notes['칸'] ?? const <Object>[]) '$n'];
    final organ2 = rectOf10(notes2.firstWhere((n) => n.startsWith('3:0:'), orElse: () => fail('기관 칸을 그리지 않았다: $notes2')));
    final band2 = bandRect(painter2, 1);
    expect(organ2.bottom, lessThanOrEqualTo(band2.bottom + .5), reason: '기관 칸은 띠 몸통 안 — 띠 $band2 · 칸 $organ2');
    // 칸 안(빗금 · 테 · 이름 밖)의 픽셀은 칸이 없을 때와 같다 — 몸통 빛 그대로(바탕색 종이가 깔리지 않았다).
    var same = 0, all = 0;
    for (int yy = organ2.top.ceil() + 2; yy < organ2.bottom - 2; yy++) {
      for (int x = (organ2.left + 200).floor(); x < organ2.right - 40; x++) {
        all++;
        if (px(lit, x, yy) == px(bare, x, yy)) same++;
      }
    }
    expect(all, greaterThan(100));
    // 빗금(20%)이 촘촘해 칸 안 픽셀의 4분의 1쯤이 같다 — 바탕색 종이가 깔리면 0에 가깝다.
    expect(same, greaterThan(all ~/ 8), reason: '몸통 안 기관 칸은 몸통 빛 그대로($same / $all)');
    expect(px(bare, (organ2.left + 200).floor(), ((organ2.top + organ2.bottom) / 2).floor()), isNot(rgba(Look.ground)), reason: '몸통 빛은 바탕색이 아니다(검사가 뜻을 가진다)');
  });

  test('⑧ 꼬리표 밑 흰 사슬(왕조 칸 — 칠 없이 테만)의 칸 안에도 · 흐린 띠의 사슬 칸 안에도 눈금이 없다', () async {
    Map<String, dynamic> chainRow(int id, {bool dynasty = false}) => {
      'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
      'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
      'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
      'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0,
      'rail': 0, 'cell_rows': 1, 'dynasty': dynasty ? 1 : 0, 'leader': 1, 'cabinet': 0, 'hang': 0,
    };
    SceneLayout shape() => SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '사슬 견본', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'chain-a', 'dynasty': 1, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
          'rows': [chainRow(0, dynasty: true), chainRow(1)],
        },
      ],
      'epochs': <dynamic>[],
    })..reduceMotion = true;
    for (final (what, look) in [('밝은 띠', null), ('흐린 띠(다른 띠를 고른 동안)', const em.Look(band: 2))]) {
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 12 * m, '하연국', look: 1 << 20 | 1 << 21); // 왕조 비트(사슬로 뺀 왕조만 — 몸통 칸 층 없음)
        t.band(2, 1, 1 * m, 12 * m, '물결국');
        t.cell(10, 0, 1.2 * m, 6 * m, '은씨 왕조', kind: 0, style: seqStyle(0), color: 0xa0bcc5);
        t.cell(11, 0, 6 * m, 11.8 * m, '서씨 왕조', kind: 0, style: seqStyle(1), color: 0xc8b193);
      }, shape: shape());
      if (look != null) {
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(look);
      }
      final pixels = await settleAndRender(scene, painter);
      final notes = [for (final n in painter.debugSink.notes['칸'] ?? const <Object>[]) '$n'];
      final chains = [for (final n in notes) if (n.startsWith('0:0:')) rectOf10(n)];
      expect(chains, hasLength(2), reason: '$what: 왕조 사슬 칸 둘 — $notes');
      final band = bandRect(painter, 1);
      final columns = gridColumns(pixels);
      for (final chain in chains) {
        expect(chain.top, greaterThanOrEqualTo(band.bottom - .5), reason: '$what: 사슬은 꼬리표 밑 — 띠 $band · 칸 $chain');
        expectNoLines(pixels, columns, chain, '$what의 사슬 칸', inset: 2);
      }
      expectNoLines(pixels, columns, ui.Rect.fromLTRB(band.left, band.top, band.right, band.bottom), '$what의 꼬리표', least: 4);
    }
  });

  test('⑨ 띠가 바탕으로 녹아드는 끝 — 미정 꼬리(44px) · 문화 띠 끝(12%)도 칠이 있는 데까지 눈금을 덮는다', () async {
    // 문화 띠: 두 끝이 폭의 12%만큼 옅어진다.
    final (scene, painter) = make((t) => t.band(3, 0, 1 * m, 14 * m, '은가지 문화', look: BandKind.culture));
    final pixels = await settleAndRender(scene, painter);
    final columns = gridColumns(pixels);
    final culture = bandRect(painter, 3);
    final soft = (culture.right - culture.left) * .12;
    expect([for (final x in columns) if (x > culture.left + 1 && x < culture.left + soft) x], isNotEmpty, reason: '옅어지는 왼쪽 끝을 지나는 기둥: $columns · $culture');
    expectNoLines(pixels, columns, culture, '문화 띠(옅어지는 끝까지)', inset: 1, least: 6);
    // 끝으로 갈수록 바탕색: 맨 끝은 바탕색(±1), 안쪽으로 들어갈수록 바탕에서 멀어진다(그 자리 바탕색으로 녹는 불투명 그러데이션).
    int far(int argb) => [24, 16, 8].map((s) => (((argb >> s) & 0xff) - ((rgba(Look.ground) >> s) & 0xff)).abs()).reduce(math.max);
    final cy = ((culture.top + culture.bottom) / 2).floor();
    expect(px(pixels, (culture.left + 2).floor(), cy), nearRgba(Look.ground), reason: '문화 띠 왼쪽 맨 끝은 바탕색');
    final steps = [for (final f in [.1, .4, .7, .95]) far(px(pixels, (culture.left + soft * f).floor(), cy))];
    expect(steps, orderedEquals([...steps]..sort()), reason: '안쪽으로 갈수록 바탕에서 멀어진다: $steps');
    expect(steps.last, greaterThan(steps.first), reason: '옅은 끝이 있다: $steps');

    // 미정 끝: 오른쪽 끝 뒤로 44px 꼬리가 옅어진다 — 꼬리 한가운데에 눈금 기둥이 오게 끝을 잡는다.
    final target = columns.firstWhere((x) => x > 900);
    final endPx = target - 22 - scene.controller.view.left;
    final (scene2, painter2) = make((t) => t.band(4, 0, 1 * m, at(endPx), '안개 나라', flags: Tile.fuzzyEnd));
    final pixels2 = await settleAndRender(scene2, painter2);
    final fuzzy = bandRect(painter2, 4);
    expect(fuzzy.right - target, closeTo(Look.fuzzyFade - 22, 2), reason: '꼬리 $fuzzy 안에 기둥 $target');
    expect(lineHits(pixels2, target, fuzzy.top.ceil() + 4, fuzzy.bottom.floor() - 4), 0, reason: '미정 꼬리(기둥 $target) 안에 눈금이 비친다');
    expect(lineHits(pixels2, target, fuzzy.bottom.ceil() + 4, 1060), greaterThan(20), reason: '꼬리 밑 바탕에는 그대로');
    // 꼬리의 맨 끝은 바탕색(±1) — 투명이 아니라 그 자리 바탕색으로 녹는다.
    expect(px(pixels2, (fuzzy.right - 1).floor(), (fuzzy.top + 6).floor()), nearRgba(Look.ground), reason: '미정 꼬리 맨 끝은 바탕색');
  });

  test('⑩ 막 도착해 떠오르는 타일(200ms — 메움 타일이 없으면 투명도 대신 바탕색에서 짙어진다)의 띠 안에도 눈금이 없다 · 빛은 띠와 바탕 사이', () async {
    double now = 0;
    final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, 1 * m, 9 * m, '해솔국')).build();
    final controller = TimelineController()
      ..reduceMotion = false
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(480);
    // 다른 타일(더 성긴 단계의 메움 · 이웃)은 오지 않는다 — 떠오르는 타일 밑에 메움이 없다.
    final never = Completer<Uint8List>();
    final scene = TimelineScene(
      controller: controller,
      layout: layout(),
      clock: () => now,
      fetchTile: (level, x, chunk, packs) => level == 9 && x == 0 ? Future.value(bytes) : never.future,
    );
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    controller.showRange(0, (1920 - scene.layout.gutterWidth) / ppm);
    for (int i = 0; i < 40; i++) {
      scene.prepare();
      await pumpEventQueue();
    }
    Future<ByteData> shot() async {
      scene.prepare();
      for (int i = 0; i < 20 && (i == 0 || painter.text.starved); i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(1920, 1080));
        recorder.endRecording().dispose();
      }
      return render(painter);
    }

    now = Motion.enter / 2; // 도착 뒤 100ms — 반쯤 떠올랐다
    scene.prepare();
    final fading = [for (final d in scene.draw) if (!d.isCover && d.alpha < 1) d];
    expect(fading.map((d) => d.alpha), contains(closeTo(.5, .01)), reason: '떠오르는 중인 타일');
    expect(fading.every((d) => !d.hasUnder), isTrue, reason: '메움 타일이 밑에 없다');
    final alpha = fading.first.alpha;
    final pixels = await shot();
    final columns = gridColumns(pixels);
    expect(columns.length, greaterThan(5), reason: '띠 밖 바탕에는 그대로(덮개는 그린 자리에만)');
    final band = bandRect(painter, 1);
    expectNoLines(pixels, columns, band, '떠오르는 띠', insetX: 14, least: 4);
    // 빛: 다 떠오른 빛을 바탕색과 (1 − 알파)로 섞은 색(±2) — 이름 글자를 피한 오른쪽 몫의 눈금 기둥 위에서(색줄 · 몸통 두 켜).
    now = Motion.enter * 4;
    final bright = await shot();
    expect([for (final d in scene.draw) if (!d.isCover) d.alpha], everyElement(1.0), reason: '다 떠올랐다');
    final right = [for (final x in columns) if (x > band.left + 300 && x < band.right - 14) x];
    expect(right, isNotEmpty);
    final g = rgba(Look.ground);
    for (final x in right) {
      for (final y in [band.top + 6, band.top + 7, band.top + 40, band.top + 41]) {
        final was = px(bright, x, y.floor()), got = px(pixels, x, y.floor());
        for (final s in [24, 16, 8]) {
          final want = ((was >> s) & 0xff) * alpha + ((g >> s) & 0xff) * (1 - alpha);
          expect((((got >> s) & 0xff) - want).abs(), lessThanOrEqualTo(2),
              reason: '떠오르는 띠(기둥 $x · y $y)의 빛 ${got.toRadixString(16)} — 다 뜬 빛 ${was.toRadixString(16)} · 바탕 ${g.toRadixString(16)}');
        }
      }
    }

    // 메움 타일이 밑에 깔린 경우(더 성긴 단계가 와 있다)는 예전처럼 층째 투명도로 엇갈려 바꾼다 — 그리개가 고르는 열쇠.
    double now2 = 0;
    final (scene2, _) = make((t) => t.band(1, 0, 1 * m, 9 * m, '해솔국'), clock: () => now2, fade: true);
    for (int i = 0; i < 40; i++) {
      scene2.prepare();
      await pumpEventQueue();
    }
    now2 = Motion.enter / 2;
    scene2.prepare();
    final fading2 = [for (final d in scene2.draw) if (!d.isCover && d.alpha < 1) d];
    expect(fading2, isNotEmpty);
    expect(fading2.every((d) => d.hasUnder), isTrue, reason: '메움 타일이 밑에 있다');
  });

  test('⑪ 문화권 머리 단(옅은 칠)과 그 안의 사람 띠에도 눈금이 없다 — 머리 단 밖 바탕은 그대로', () async {
    final json = twoTrackLayout();
    (json['tracks'] as List)[0]['sphere'] = 'ember-basin';
    (json['tracks'] as List)[1]['sphere'] = 'frost-ridge';
    json['spheres'] = [
      {'id': 'ember-basin', 'name': '등불 분지권', 'count': 3, 'default': true},
      {'id': 'frost-ridge', 'name': '설령 빙원권', 'count': 2},
    ];
    json['sphereLines'] = [
      {'kind': 1, 'sphere': 'ember-basin', 'start': minuteOfYear(300).round(), 'end': minuteOfYear(900).round(), 'name': '불씨 임금', 'uid': 'fig-a', 'data': '[]'},
    ];
    final shape = SceneLayout.fromJson(json)..reduceMotion = true;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
      ..setContentHeight(shape.totalHeight);
    final scene = TimelineScene(controller: controller, layout: shape, fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build());
    scene.hide.add('fade');
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    controller.showRange(minuteOfYear(-20), minuteOfYear(1420));
    final pixels = await settleAndRender(scene, painter);
    final v = controller.view;
    final columns = gridColumns(pixels, y0: (v.yOf(shape.totalHeight) + 4).ceil());
    expect(columns.length, greaterThan(5), reason: '머리 단 밖 바탕에는 눈금이 그대로: $columns');
    for (int k = 0; k < 2; k++) {
      final box = shape.sphereHeadBox(k, v)!;
      expectNoLines(pixels, columns, ui.Rect.fromLTWH(v.left, box.top, 1920 - v.left, box.height), '문화권 머리 단 $k', inset: 1, least: 5);
    }
    expect(painter.gutter.personBands, isNotEmpty, reason: '사람 띠를 그렸다');
  });

  test('⑫ 칠 없이 점선 테만 있는 받침 카드(명목상 소속)의 드러난 윗단 안에도 눈금이 없다', () async {
    final (scene, painter) = make((t) {
      t.band(2, 0, 1 * m, 12 * m, '갈대 공국');
      t.item(BandLayer.sectionHostTab, 52, 0, 1 * m, 12 * m, ref: 2, name: '하연 왕국', color: 0x8b6f47, a: 2, d: 99, text2: 'p/hayeon');
    }, shape: twoPiece());
    final pixels = await settleAndRender(scene, painter);
    expect(painter.debugSink.notes['뒤장']?.single.toString(), contains('깊이=2'), reason: '명목상(칠 없음 · 점선 테) 카드');
    final band = bandRect(painter, 2);
    final columns = gridColumns(pixels);
    // 카드 윗 테 줄(점선 1 · 1)은 뺀다 — 테가 픽셀 칸으로 그어져(조사 결함 24) 점 하나가 그 기둥만 다른 빛이라 눈금처럼 셈된다. 테 아래 윗단 안을 본다.
    expectNoLines(pixels, columns, ui.Rect.fromLTRB(band.left, band.top - BandLayer.sheetRise + 1, band.right, band.top), '점선 카드 윗단', inset: 0, least: 4);
    // 테 안은 바탕색 종이(칠 없음 — 빛은 바탕 그대로).
    final x = [for (int x = (band.left + 40).floor(); x < band.right - 40; x++) x].firstWhere((x) => columns.every((g) => (g - x).abs() > 2));
    expect(px(pixels, x, (band.top - BandLayer.sheetRise + 2).floor()), rgba(Look.ground), reason: '점선 카드 윗단 안은 바탕색');
  });

  test('⑬ 집합 보기의 판 둘레(가로 전체의 옅은 판)는 칠을 반투명 그대로 둔다 — 판 안 빈 바탕의 눈금은 그대로 · 판 안 그릇은 판 빛과 섞인 종이', () async {
    final (scene, painter) = make((t) {
      t.item(ScopeLayer.secScope, 1, 0, 0, 16 * m, row2: 2, name: '집합 판', color: 0xd4a39b, a: 8);
      t.band(1, 0, 1 * m, 5 * m, '해솔국');
      // 판 안의 그릇(줄 2 — 판 안 빈 바탕 검사 자리 밖) — 판 빛 위에 9%를 얹은 불투명 종이.
      t.item(ScopeLayer.secScope, 2, 2, at(300), at(1100), name: '남곡 할거', color: 0xacb4ca);
    });
    final pixels = await settleAndRender(scene, painter);
    expect(painter.debugSink.notes['대범위'], isNotEmpty, reason: '판 둘레를 그렸다');
    final layout = scene.layout, v = scene.controller.view;
    final top = v.yOf(layout.rowTop(1)) + 4, bottom = v.yOf(layout.rowTop(2) + layout.geo(2).height) - 4;
    final columns = gridColumns(pixels);
    final crossing = [for (final x in columns) if (x > v.left + 20) x];
    expect(crossing.length, greaterThan(5));
    for (final x in crossing) {
      expect(lineHits(pixels, x, top.ceil(), bottom.floor()), greaterThan(20), reason: '판 안 빈 바탕(줄 1 · 2 — 기둥 $x)에는 눈금이 그대로');
    }
    // 판 안의 그릇: 몸통 색 = 그릇 9%를 (판 9%를 바탕에 얹은 빛)에 얹은 색(±1) · 몸통을 지나는 눈금 기둥 위에서도.
    final folder = (painter.debugSink.notes['폴더'] ?? const []).map((n) => '$n').firstWhere((n) => n.startsWith('남곡 할거 '), orElse: () => fail('판 안 그릇을 그리지 않았다'));
    final f = folder.split(' ').firstWhere((s) => s.split(',').length == 4).split(',').map(double.parse).toList();
    final body = ui.Rect.fromLTWH(f[0], f[1] + G.folderTab, f[2], f[3] - G.folderTab);
    final paper = over(withAlpha(0xffacb4ca, .09), over(withAlpha(0xffd4a39b, .09), Look.ground));
    final inside = [for (final x in columns) if (x > body.left + 12 && x < body.right - 12) x];
    expect(inside.length, greaterThan(3), reason: '판 안 그릇 몸통을 지나는 기둥: $columns · 몸통 $body');
    for (final x in inside) {
      for (final y in [body.top + 10, body.top + 11]) {
        expect(px(pixels, x, y.floor()), nearRgba(paper), reason: '판 안 그릇 몸통(기둥 $x · y $y)');
      }
    }
    expectNoLines(pixels, columns, body, '판 안 그릇 몸통', least: 4);
  });

  test('⑭ 접힌 민족 줄(여러 줄을 한 줄로 — 90° 줄무늬)의 띠 몸통 자리에는 눈금이 없다 — 줄 아래 바탕은 그대로', () async {
    // 감독의 '다 막아줘' · '폴더 부분에도'를 따라 접힌 줄도 종이로 본다(조정자 판단 — 뒤집으면 줄무늬 밑 종이 걸음 한 줄만 뺀다).
    final shape = SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;
    final track = shape.tracks[0];
    expect(shape.foldGroup(track, track.groups[0], true), isTrue);
    final head = shape.mergedRows.keys.single;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(shape.totalHeight);
    final scene = TimelineScene(controller: controller, layout: shape, fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build());
    scene.hide.add('fade');
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    controller.showRange(0, (1920 - shape.gutterWidth) / ppm);
    final pixels = await settleAndRender(scene, painter);
    final v = controller.view, geo = shape.geo(head);
    final top = v.yOf(shape.rowTop(head) + geo.bandTop), bottom = top + geo.bandHeight;
    final columns = gridColumns(pixels, y0: (v.yOf(shape.totalHeight) + 4).ceil());
    expect(columns.length, greaterThan(5), reason: '줄 아래 바탕에는 눈금이 그대로: $columns');
    expectNoLines(pixels, columns, ui.Rect.fromLTRB(v.left, top, 1920, bottom), '접힌 줄 몸통', inset: 1, least: 5);
    // 줄무늬(7px마다 1px · 먹 12)는 그대로 종이 위에 · 줄무늬 사이는 바탕색 종이.
    final y = ((top + bottom) / 2).floor();
    final stripe = over(CanvasInk.of(withAlpha(Look.line, Mini.stripeAlpha)), Look.ground);
    final first = (v.left + Mini.stripeGap).floor();
    for (int k = 0; k < 40; k++) {
      final x = first + k * (Mini.stripeGap + Mini.stripeWidth).toInt();
      expect(px(pixels, x, y), nearRgba(stripe), reason: '줄무늬 x $x');
      expect(px(pixels, x + 3, y), rgba(Look.ground), reason: '줄무늬 사이 x ${x + 3}은 바탕색 종이');
    }
    // 위아래의 바탕(접힌 줄 띠 몸통 밖 — 둘째 트랙의 빈 줄)에는 줄이 그대로 남는다.
    final below = v.yOf(shape.rowTop(3)).ceil(), end = v.yOf(shape.rowTop(4) + shape.geo(4).height).floor();
    for (final x in [for (final x in columns) if (x > v.left + 20) x].take(8)) {
      expect(lineHits(pixels, x, below, end), greaterThan(10), reason: '둘째 트랙 빈 줄(기둥 $x)에는 눈금이 그대로');
      expect(lineHits(pixels, x, bottom.ceil() + 1, below), greaterThan(0), reason: '접힌 줄 띠 밑 틈(기둥 $x)에도 눈금이 그대로');
    }
  });

  test('⑮ 매단 속국 이름표 · 구역 탭(띠 아래 바탕에 매단 것 — 고른 동안 .5)도 불투명 종이 — 안에 눈금이 없고 빛은 바탕에 얹은 색(±1) · 그 밖 바탕은 그대로', () async {
    // 줄 0(옛 저장소 — 덧단 줄 23px): 상국 띠 1 밑에 매단 이름표(단 0) · 구역 탭(단 3). 같은 줄 오른쪽의 띠 2를 고르면 둘은 .5로 흐려진다.
    final shape = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
          'rows': [
            {
              'id': 0, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 0, 'text_lines': 2, 'rail_top': 0,
              'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0, 'dep': 25.0, 'zones': 4, 'hem': 0,
            },
          ],
        },
      ],
    });
    const zoneColor = 0xff9dbea8;
    Future<(ByteData, TimelinePainter)> shot({required bool pick}) async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 11 * m, '은륜 제국');
        t.band(2, 0, 11.5 * m, 13 * m, '물결국');
        t.item(16, 101, 0, 2 * m, 10 * m, ref: 1, name: '별목 조공국', color: 0xa0bcc5, a: 0, b: 0, d: 21, text2: '속국:별목');
        t.item(17, 131, 0, 2 * m, 10 * m, ref: 1, name: '별목 교환구', color: zoneColor & 0xffffff, a: 3, text2: '구역:별목');
      }, shape: shape);
      if (pick) {
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(const em.Look(band: 2));
      }
      return (await settleAndRender(scene, painter), painter);
    }

    final (bright, _) = await shot(pick: false);
    final (pixels, painter) = await shot(pick: true);
    final marks = [for (final n in painter.debugSink.notes['hang'] ?? const <Object>[]) if (n is HangMark) n];
    final tab = marks.firstWhere((h) => h.kind == 'hang', orElse: () => fail('매단 이름표를 그리지 않았다: $marks')).rect;
    final zoneMark = marks.firstWhere((h) => h.kind == 'zone', orElse: () => fail('구역 탭을 그리지 않았다: $marks'));
    final zone = zoneMark.rect;
    expect(zoneMark.alpha, closeTo(.5, 1e-9), reason: '고른 동안 구역 탭은 .5');
    final columns = gridColumns(pixels);
    expect(columns.length, greaterThan(5), reason: '띠 사이 바탕에는 눈금이 그대로: $columns');
    expectNoLines(pixels, columns, tab, '흐린 매단 이름표', inset: 2, insetX: 4, least: 3);
    expectNoLines(pixels, columns, zone, '흐린 구역 탭', inset: 2, insetX: 4, least: 3);
    // 이름표와 구역 탭 사이의 빈 단(단 1 · 2 — 띠 사이 바탕)에는 눈금이 그대로다.
    final inside = [for (final x in columns) if (x > tab.left + 4 && x < tab.right - 4) x];
    for (final x in inside) {
      expect(lineHits(pixels, x, tab.bottom.ceil() + 3, zone.top.floor() - 3), greaterThan(3), reason: '빈 단(기둥 $x)에는 눈금이 있다');
    }
    // 빛: 이름표 = 밝은 빛을 .5로 바탕에 얹은 색(±1) — 이름 · 구멍을 피한 오른쪽 몫의 눈금 기둥 위에서(점선의 켠 점 · 끈 점 두 줄).
    final ty = ((tab.top + tab.bottom) / 2).floor();
    final right = [for (final x in inside) if (x > tab.left + 90) x];
    expect(right, isNotEmpty);
    for (final x in right) {
      for (final y in [ty, ty + 1]) {
        final was = px(bright, x, y);
        expect(px(pixels, x, y), nearRgba(over(withAlpha(0xff000000 | (was >>> 8), .5), Look.ground)), reason: '흐린 매단 이름표(기둥 $x · y $y)의 빛 — 밝은 빛 ${was.toRadixString(16)}');
      }
    }
    // 구역 탭 = 제 칠(색 6%)을 .5로 바탕에 얹은 색(±1) — 빗금 · 이름을 피해, 밝은 그림에서 칠 그대로인 픽셀만.
    final zoneFill = mixSrgb(zoneColor, Look.paper, .06);
    var plain = 0;
    for (int y = zone.top.ceil() + 2; y < zone.bottom - 2; y++) {
      for (final x in [for (final x in columns) if (x > zone.left + 4 && x < zone.right - 4) x]) {
        if (px(bright, x, y) != rgba(zoneFill)) continue;
        expect(px(pixels, x, y), nearRgba(over(withAlpha(zoneFill, .5), Look.ground)), reason: '흐린 구역 탭(기둥 $x · y $y)의 빛');
        plain++;
      }
    }
    expect(plain, greaterThan(10), reason: '구역 탭 칠 그대로인 눈금 기둥 위 픽셀');
  });

  test('⑯ 흐린 상국 탭 · 연합 겹 탭 · 받침 카드(띠 윗변 위 바탕에 선 것) 안에도 눈금이 없다 · 빛은 바탕에 얹은 색(±1)', () async {
    // 속국 띠 2(줄 1): 받침 카드(칠한 — 깊이 1) + 오른쪽 끝의 상국 탭 + 왼쪽의 연합 겹 탭. 띠 1(줄 0)을 고른 동안 띠 2는 흐리다(.58).
    // 탭 이름을 길게 해 탭이 눈금 기둥 사이(약 120px)보다 넓게 한다.
    const host = 0x8b6f47, coal = 0x6f8b47;
    const hostName = '하연 왕국 하연 왕국 하연 왕국', coalName = '물결 연합 물결 연합 물결 연합';
    final (scene, painter) = make((t) {
      t.band(1, 0, 1 * m, 3 * m, '별여울국', look: 1 << 20 | 1 << (21 + 5));
      t.band(2, 1, 1 * m, 14 * m, '갈대 공국');
      t.item(BandLayer.sectionHostTab, 52, 1, 1 * m, 14 * m, ref: 2, name: hostName, color: host, a: 1, d: 99, text2: 'p/hayeon');
      t.item(BandLayer.sectionHostTab, 53, 1, 1 * m, 9 * m, ref: 2, name: coalName, color: coal, a: BandLayer.coalLook, b: 0, d: 98, text2: 'g/mulgyeol');
    }, shape: twoPiece());
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(band: 1));
    final pixels = await settleAndRender(scene, painter);
    final alpha = em.Emphasis.of(scene).bandAlpha(2, 1);
    expect(alpha, lessThan(1), reason: '띠 2는 흐리다');
    final band = bandRect(painter, 2);
    final columns = gridColumns(pixels);
    expect(columns.length, greaterThan(5), reason: '바탕에는 눈금이 그대로');
    // 상국 탭: 카드 윗변(띠 윗변 − 5) 위로 [TagLook.tabH] 솟는다 — '상국탭' 기록의 x · 폭.
    final hostNote = '${(painter.debugSink.notes['상국탭'] ?? const []).firstWhere((n) => '$n'.contains(hostName), orElse: () => fail('상국 탭을 그리지 않았다'))}';
    final hx = hostNote.split(' ').last.split(',').map((s) => double.parse(s) / 10).toList();
    final hBottom = band.top - BandLayer.sheetRise + 1, hTop = hBottom - 1 - TagLook.tabH;
    final hostTab = ui.Rect.fromLTRB(hx[0], hTop, hx[0] + hx[1], hBottom);
    expectNoLines(pixels, columns, hostTab, '흐린 상국 탭', inset: 1, insetX: 3);
    // 연합 겹 탭(앞 장): 띠 윗변 위로 [TagLook.tabH] + 1 — '연합탭' 기록의 x · 폭.
    final coalNote = '${(painter.debugSink.notes['연합탭'] ?? const []).firstWhere((n) => '$n'.contains(coalName), orElse: () => fail('연합 겹 탭을 그리지 않았다'))}';
    final cx = coalNote.split(' ').last.split(',').map((s) => double.parse(s) / 10).toList();
    final tabBottom = band.top + 1, tabTop = tabBottom - 2 - TagLook.tabH;
    final coalTab = ui.Rect.fromLTRB(cx[0], tabTop, cx[0] + cx[1], tabBottom - 1);
    expectNoLines(pixels, columns, coalTab, '흐린 연합 겹 탭', inset: 1, insetX: 3);
    // 받침 카드의 드러난 윗단(상국 탭 · 연합 탭 밖)도.
    expectNoLines(pixels, columns, ui.Rect.fromLTRB(coalTab.right + 8, band.top - BandLayer.sheetRise, hostTab.left - 4, band.top), '흐린 받침 카드 윗단', inset: 0);
    // 빛: 흐린 상국 탭 · 받침 카드 = 상국 빛깔 종이(깊이 1)를 그 알파로 바탕에 얹은 색(±1) — 눈금 기둥 위에서도.
    final sheet = over(withAlpha(mixOklab(0xff000000 | host, Look.paper, BandLayer.sheetMix[1]), alpha), Look.ground);
    for (final x in [for (final x in columns) if (x > hostTab.left + 3 && x < hostTab.right - 3) x]) {
      expect(px(pixels, x, (hBottom - 1).floor()), nearRgba(sheet), reason: '흐린 상국 탭 밑 덮개(기둥 $x)의 빛');
    }
  });

  test('⑯-2 흐린 속국 띠는 받침 카드 · 바탕빛 틈 위에 섞인다 — 칠이 있는 카드가 비치는 빛 그대로(±1 · 카드도 바탕 칸)', () async {
    // 속국 띠 2(줄 1)의 뒤에 칠한 받침 카드(깊이 1). 띠 1(줄 0)을 고른 동안 띠 2와 그 카드는 흐리다 — 예전(항목마다 알파)처럼 카드 빛이 흐린 띠 안에 비친다.
    const host = 0x8b6f47;
    Future<(ByteData, TimelinePainter, TimelineScene)> shot({required bool pick}) async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 3 * m, '별여울국', look: 1 << 20 | 1 << (21 + 5));
        t.band(2, 1, 1 * m, 14 * m, '갈대 공국');
        t.item(BandLayer.sectionHostTab, 52, 1, 4 * m, 14 * m, ref: 2, name: '하연 왕국', color: host, a: 1, d: 99, text2: 'p/hayeon');
      }, shape: twoPiece());
      if (pick) {
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(const em.Look(band: 1));
      }
      return (await settleAndRender(scene, painter), painter, scene);
    }

    final (bright, _, _) = await shot(pick: false);
    final (pixels, painter, scene) = await shot(pick: true);
    final alpha = em.Emphasis.of(scene).bandAlpha(2, 1);
    expect(alpha, lessThan(1), reason: '띠 2는 흐리다');
    final band = bandRect(painter, 2), v = scene.controller.view;
    final card = over(withAlpha(mixOklab(0xff000000 | host, Look.paper, BandLayer.sheetMix[1]), alpha), Look.ground);
    final under = over(withAlpha(Look.ground, alpha), card); // 띠 밑의 바탕빛 틈(흐림) — 카드 위
    // 카드가 있는 몫(4m ~ 14m)과 없는 몫(1m ~ 4m)의 몸통(이름 색줄 아래 · 가로 금 피함) — 이름 글자를 피해 오른쪽에서.
    final y = (band.top + band.bottom) / 2 + 4;
    var onCard = 0, bare = 0;
    for (final (x, ground) in [(v.xOf(8 * m), under), (v.xOf(12 * m), under), (v.xOf(3.5 * m), Look.ground)]) {
      final was = px(bright, x.floor(), y.floor());
      expect(px(pixels, x.floor(), y.floor()), nearRgba(over(withAlpha(0xff000000 | (was >>> 8), alpha), ground)), reason: '흐린 띠(x $x · y $y)의 빛 — 밝은 빛 ${was.toRadixString(16)}');
      if (ground == under) {
        onCard++;
      } else {
        bare++;
      }
    }
    expect((onCard, bare), (2, 1));
  });

  test('⑱ 열쇠표 · 플래그(띠 윗변 위 바탕에 선 것 — 고른 동안 .5)도 불투명 종이 — 안에 눈금이 없고 빛은 바탕에 얹은 색(±1)', () async {
    // 줄 0: 띠 1 위에 풀린 그릇의 열쇠표 · 줄 1: 띠 2 위에 플래그(소속 단추 하나) · 줄 2: 띠 3을 고른다(표식 .5).
    // 열쇠표의 글 오른쪽 여백(3px)과 플래그의 칠 가운데에 눈금 기둥이 오게 첫 그림에서 자리를 재고 다시 그린다.
    const label = '두 물결 그릇', host = 0x8b6f47;
    Future<(ByteData, TimelinePainter, TimelineScene)> shot(double keyAt, double flagBandAt) async {
      final (scene, painter) = make((t) {
        t.band(1, 0, 1 * m, 12 * m, '본국');
        t.item(ScopeMarks.secKey, 601, 0, keyAt, 12 * m, ref: 1, name: label, color: 0xa27e76, text2: 's-two');
        t.band(2, 1, flagBandAt, 12 * m, '갈대 공국', color: host);
        t.item(ScopeMarks.secMemBtn, 701, 1, flagBandAt, 12 * m, ref: 2, color: host, a: 3);
        t.band(3, 2, 1 * m, 12 * m, '물결국');
      });
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 3));
      return (await settleAndRender(scene, painter), painter, scene);
    }

    List<double> keyOf(TimelinePainter painter) =>
        '${(painter.debugSink.notes['열쇠표'] ?? const []).firstWhere((n) => '$n'.startsWith('$label '), orElse: () => fail('열쇠표를 그리지 않았다'))}'
            .split(' ').last.split(',').map(double.parse).toList();
    final (first, painter0, scene0) = await shot(1 * m, 1 * m);
    final v = scene0.controller.view;
    final w = keyOf(painter0)[2];
    final columns = gridColumns(first);
    final keyCol = columns.firstWhere((x) => x - w > v.xOf(1 * m) + FolderLook.keyFrom + 10);
    final flagCol = columns.firstWhere((x) => x > keyCol + 40);
    final (pixels, painter, scene) = await shot(at(keyCol - w - v.left), at(flagCol - FlagLook.from - FlagLook.w / 2 - v.left));
    expect(em.Emphasis.of(scene).cellDim, .5, reason: '고른 동안 표식은 .5');

    // 열쇠표: 글 오른쪽 여백(오른쪽 테 − 2)에 눈금 기둥 — 칠 안 위아래(테 빼고)가 모두 흰 종이를 .5로 바탕에 얹은 색(±1) · 눈금 없음.
    final k = keyOf(painter);
    final kx = k[0], ky = k[1], kw = k[2];
    expect(kx + kw - 3, keyCol, reason: '열쇠표 오른쪽 여백에 눈금 기둥 $keyCol — 열쇠표 $k');
    final paper = over(withAlpha(Look.paper, .5), Look.ground);
    for (int y = ky.ceil() + 1; y < ky + FolderLook.keyH - 1; y++) {
      expect(px(pixels, keyCol, y), nearRgba(paper), reason: '흐린 열쇠표 종이(기둥 $keyCol · y $y)');
    }
    expect(lineHits(pixels, keyCol, ky.ceil() + 1, (ky + FolderLook.keyH - 2).floor()), 0, reason: '흐린 열쇠표 안에 눈금이 비친다');

    // 플래그: 칠(띠 색 50%)을 .5로 바탕에 얹은 색(±1) — 위 테 아래 · 양옆 테 안.
    final flag = painter.links.flagOf(2);
    expect(flag, isNotNull, reason: '플래그를 놓았다');
    final r = flag!.rect;
    expect(flagCol, inInclusiveRange(r.left + 1, r.right - 2), reason: '플래그 칠 안에 눈금 기둥 $flagCol — 플래그 $r');
    final fill = over(withAlpha(mixSrgb(0xff000000 | host, Look.paper, FlagLook.fillPct), .5), Look.ground);
    for (int y = r.top.ceil() + 1; y < r.bottom; y++) {
      expect(px(pixels, flagCol, y), nearRgba(fill), reason: '흐린 플래그 칠(기둥 $flagCol · y $y)');
    }
    // 그 밖 바탕(띠 사이 · 줄 아래)에는 눈금이 그대로.
    expect(gridColumns(pixels), contains(keyCol), reason: '줄 아래 바탕의 같은 기둥에는 눈금이 그대로');
  });

  test('⑰ SVG 내보내기도 같은 차례 · 같은 불투명 색 — 눈금이 맨 앞에 적히고 반투명 칠이 띠 쪽에 남지 않는다', () async {
    // SVG의 바탕은 종이(Look.paper — 그림판은 Look.ground)라 섞는 바탕만 다르고 길은 그리개와 같다(paint/grounds.dart · paintSceneToSvg).
    // (가) 그릇 + 흐린 띠: 그릇(남곡 할거) 안의 띠 셋 가운데 띠 12를 고른 그림과 고르지 않은 그림.
    Future<(String, TimelinePainter, TimelineScene)> folderSvg({required bool pick}) async {
      final (scene, painter) = folderScene(text: SvgText(inner: unbudgetedText()));
      if (pick) {
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(const em.Look(band: 12));
      }
      await settleAndRender(scene, painter);
      return (await svgOf(painter), painter, scene);
    }

    final (brightSvg, _, _) = await folderSvg(pick: false);
    final (svg, painter, scene) = await folderSvg(pick: true);
    final v = scene.controller.view;
    final pieces = svgPieces(svg), patterns = svgPatternIds(svg), grid = svgGridIds(svg);
    expect(grid, hasLength(1), reason: '눈금 무늬 한 벌(같은 시작 자리)');

    // 눈금: 기둥마다 몸통 높이 통째 1px 무늬 네모 하나(빼기 없음) · 그리개가 그은 수와 같다.
    final lines = [for (final p in pieces) if (grid.contains(p.url)) p];
    expect(lines.length, painter.debugSink.gridLines, reason: '그리개가 그은 눈금 수');
    expect(lines.length, greaterThan(5));
    expect({for (final p in lines) p.r.left}, hasLength(lines.length), reason: '기둥마다 조각 하나 — 줄을 끊어 빼지 않는다');
    for (final p in lines) {
      expect(p.r.width, 1, reason: '눈금 ${p.r}');
      expect(p.r.top, v.head, reason: '눈금 ${p.r} — 몸통 맨 위부터');
      expect(p.r.bottom, 1080, reason: '눈금 ${p.r} — 몸통 맨 아래까지');
    }
    // 차례: 눈금은 바탕 종이 한 장 바로 다음 — 그 앞에 적힌 칠은 바탕 종이(과 투명한 한 칸 걸러 바탕 띠)뿐이다.
    final lastLine = lines.map((p) => p.at).reduce(math.max);
    final before = [for (final p in pieces) if (p.at < lastLine && !grid.contains(p.url) && p.a > 0) p];
    expect(before, hasLength(1), reason: '눈금보다 앞에 적힌 칠: ${before.map((p) => '${p.r} #${p.rgb.toRadixString(16)}').toList()}');
    expect(before.single.r, const ui.Rect.fromLTWH(0, 0, 1920, 1080), reason: '바탕 종이');
    expect(svg, isNot(contains('fill="#d4a39b" fill-opacity="0.09"')), reason: '그릇의 옛 반투명 칠(9%)이 남지 않는다');

    // 그릇 몸통: 몸통을 지나는 눈금 기둥마다 맨 위 칠은 그릇 9%를 종이에 얹은 불투명 색(±1)이고 눈금보다 뒤에 적혔다(덮는다).
    final body = folderBody(painter, '남곡 할거');
    final folderPaper = over(withAlpha(0xffd4a39b, FolderLook.fillPct), Look.paper);
    final bare = [for (final p in lines) if (p.r.left > body.left + 3 && p.r.left < v.left + 790) p];
    expect(bare, isNotEmpty, reason: '띠 없는 그릇 몫을 지나는 눈금');
    for (final line in bare) {
      final top = svgTopAt(pieces, patterns, line.r.left + .5, body.top + 10.5);
      expect(top, isNotNull);
      expect(top!.a, 1, reason: '그릇 몸통(기둥 ${line.r.left})의 칠은 불투명');
      expect(top.at, greaterThan(line.at), reason: '그릇 종이가 눈금 뒤에 적혀 덮는다');
      expect(rgba(argbOf(top)), nearRgba(folderPaper), reason: '그릇 몸통(기둥 ${line.r.left})은 그릇 9%를 종이에 얹은 색');
    }

    // 흐린 띠 13(.58): 띠 안을 지나는 눈금 기둥마다 맨 위 칠은 불투명 — 밝은 그림의 칠을 그 알파로 그릇 종이에 얹은 색(±1).
    final alpha = em.Emphasis.of(scene).bandAlpha(13, 3);
    expect(alpha, lessThan(1), reason: '띠 13은 흐리다');
    final brightPieces = svgPieces(brightSvg), brightPatterns = svgPatternIds(brightSvg);
    final band = bandRect(painter, 13);
    final inBand = [for (final p in lines) if (p.r.left > band.left + 14 && p.r.left < band.right - 14) p];
    expect(inBand.length, greaterThan(2), reason: '흐린 띠를 지나는 눈금');
    for (final line in inBand) {
      // 이름 색줄(위 6px 안)과 몸통 가운데 — 켜 사이 금 · 테(칠 위의 1px 선)는 피한다.
      for (final y in [band.top + 6.5, ((band.top + band.bottom) / 2).floorToDouble() + .5]) {
        final top = svgTopAt(pieces, patterns, line.r.left + .5, y), was = svgTopAt(brightPieces, brightPatterns, line.r.left + .5, y);
        expect(top, isNotNull);
        expect(was, isNotNull);
        expect(was!.a, 1, reason: '밝은 띠 칠은 불투명');
        expect(top!.a, 1, reason: '흐린 띠 13(기둥 ${line.r.left} · y $y)의 칠은 불투명(fill-opacity 없음)');
        expect(top.at, greaterThan(line.at));
        expect(rgba(argbOf(top)), nearRgba(over(withAlpha(argbOf(was), alpha), folderPaper)), reason: '흐린 띠 13(기둥 ${line.r.left} · y $y)의 빛');
      }
    }

    // (나) 바탕 문화 + 매단 이름표: 바탕 문화 종이는 불투명(문화 색 9%를 종이에 얹은 색 ±1) · 두 끝의 번짐도 불투명(짙기 1 → 1)이고,
    // 매단 이름표보다 앞에 적힌다(이름표가 그 위).
    final (uScene, uPainter) = underHangScene(text: SvgText(inner: unbudgetedText()));
    await settleAndRender(uScene, uPainter);
    final uSvg = await svgOf(uPainter);
    final uPieces = svgPieces(uSvg), uPatterns = svgPatternIds(uSvg), fades = svgFades(uSvg);
    final under = bandRect(uPainter, 3);
    final marks = [for (final n in uPainter.debugSink.notes['hang'] ?? const <Object>[]) if (n is HangMark) n];
    final tab = marks.firstWhere((h) => h.kind == 'hang', orElse: () => fail('매단 이름표를 그리지 않았다: $marks')).rect;
    final underPaper = over(withAlpha(0xff204080, .09), Look.paper);
    final ty = (tab.top + tab.bottom) / 2, tx = tab.right - 8;
    final onTab = svgTopAt(uPieces, uPatterns, tx, ty);
    expect(onTab, isNotNull);
    expect(onTab!.a, 1, reason: '매단 이름표 칠은 불투명');
    final paperUnder = [for (final p in uPieces) if (p.r.contains(ui.Offset(tx, ty)) && p.url == null && closeRgba(rgba(argbOf(p)), underPaper)) p];
    expect(paperUnder, isNotEmpty, reason: '이름표 밑에 바탕 문화 종이(문화 9%를 종이에 얹은 색)가 깔렸다');
    for (final p in paperUnder) {
      expect(p.a, 1, reason: '바탕 문화 종이는 불투명');
      expect(p.at, lessThan(onTab.at), reason: '바탕 문화 종이는 매단 이름표보다 앞에 적힌다');
    }
    // 두 끝(조각 폭의 10% — 번짐): 번짐 조각의 두 끝 짙기가 모두 1(종이색으로 녹는다 — 투명으로 사라지지 않는다).
    final my = (under.top + under.bottom) / 2;
    for (final x in [under.left + 3, under.right - 3]) {
      final end = [for (final p in uPieces) if (p.url != null && fades.containsKey(p.url) && p.r.contains(ui.Offset(x, my))) p];
      expect(end, isNotEmpty, reason: '바탕 문화 끝(x $x)의 번짐');
      for (final p in end) {
        expect(fades[p.url], (1.0, 1.0), reason: '바탕 문화 끝(x $x)의 번짐은 불투명');
      }
    }

    // (다) 사람 띠의 실은 그릇 종이 위다 — 실 조각(그림판 + 가림막)이 그 자리 그릇 종이보다 뒤에 적힌다.
    final (cScene, cPainter) = crownFolderScene(text: SvgText(inner: unbudgetedText()));
    await settleAndRender(cScene, cPainter);
    final cSvg = await svgOf(cPainter);
    final cPieces = svgPieces(cSvg), cPatterns = svgPatternIds(cSvg);
    final cBody = folderBody(cPainter, '설령 할거');
    final thread = cPainter.threads.threads.single;
    final ys = [for (double y = cBody.top + 4; y < math.min(cBody.bottom, thread.to) - 2; y += 2) y];
    expect(ys, isNotEmpty);
    var dashes = 0;
    for (final y in ys) {
      final paper = svgTopAt(cPieces, cPatterns, thread.x, y);
      if (paper == null || !closeRgba(rgba(argbOf(paper)), folderPaper)) continue;
      for (final p in cPieces) {
        if (!p.masked || !p.r.contains(ui.Offset(thread.x, y))) continue;
        expect(p.at, greaterThan(paper.at), reason: '실 조각(y $y)이 그릇 종이보다 뒤에 적힌다');
        dashes++;
      }
    }
    expect(dashes, greaterThan(3), reason: '그릇 몸통 안의 실 조각');
  });

  test('⑳ 할거기 칠(띠 위 92% 종이)이 짧은 꼬리표 밑 바탕으로 내려온 몫도 불투명 종이 — 그 안에 눈금이 비치지 않고 빛은 92%를 바탕에 얹은 색(±1)', () async {
    // 지도자 층을 가진 띠 1 때문에 줄에 지도자 층이 서고, 칸 없는 띠 2(할거기의 본국)는 사건 칸을 그만큼 올린 짧은 꼬리표다 — 할거기 칠은 줄 몫의
    // 띠 높이로 깔리므로 꼬리표 밑(띠 아래 바탕)으로 [G.floor]만큼 내려온다.
    final (scene, painter) = make((t) {
      t.band(1, 0, 1 * m, 3 * m, '별여울국', look: 1 << 20 | 1 << (21 + 5));
      t.band(2, 0, 4 * m, 14 * m, '갈대 공국');
      t.item(ScopeLayer.secHollow, 401, 0, 4.5 * m, 13.5 * m, ref: 2, name: '두 물결', color: 0xa27e76, text2: '할거');
    }, shape: twoPiece());
    final pixels = await settleAndRender(scene, painter);
    expect(painter.debugSink.notes['할거기'], hasLength(1), reason: '할거기 칠을 그렸다');
    final band = bandRect(painter, 2), full = band.top + scene.layout.geo(0).bandHeight;
    expect(full - band.bottom, G.floor, reason: '꼬리표는 줄 몫의 띠보다 짧다');
    final v = scene.controller.view;
    final columns = gridColumns(pixels);
    final inside = [for (final x in columns) if (x > v.xOf(4.5 * m) + 3 && x < v.xOf(13.5 * m) - 3) x];
    expect(inside.length, greaterThan(3), reason: '할거기 칠을 지나는 눈금 기둥: $columns');
    // 꼬리표 밑 몫(꼬리표 아랫변 아래 ~ 칠이 옅어져 사라지는 줄 몫 아랫변 − 3)에는 눈금이 없다 — 칠이 다 빠진 맨 아래 2px 밑은 바탕 그대로.
    final paper = over(withAlpha(Look.paper, ScopeLook.hollowPaper), Look.ground);
    for (final x in inside) {
      expect(lineHits(pixels, x, band.bottom.ceil() + 1, (full - 4).floor()), 0, reason: '꼬리표 밑 할거기 칠(기둥 $x)에 눈금이 비친다');
      for (int y = band.bottom.ceil() + 1; y < full - 1 - ScopeLook.hollowFade; y++) {
        expect(px(pixels, x, y), nearRgba(paper), reason: '꼬리표 밑 할거기 칠(기둥 $x · y $y)은 92%를 바탕에 얹은 색');
      }
      expect(lineHits(pixels, x, full.ceil() + 2, 1060), greaterThan(20), reason: '줄 아래 바탕(기둥 $x)에는 눈금이 그대로');
    }
  });

  test('⑭-2 펼친 그릇 안의 접힌 민족 줄 — 접힌 줄 종이가 그릇의 세로 테 · 안쪽 겹선을 지우지 않는다(종이는 그릇보다 먼저)', () async {
    // 줄 2 ~ 5를 품은 그릇(남곡 할거) 안에서 줄 3 ~ 4의 민족 묶음(하연인)을 접는다 — 접힌 줄의 띠 몸통 높이에서도 그릇 테가 위아래 줄과 같은 빛이어야 한다.
    Map<String, dynamic> low(int id, {int gs = 0}) => {
      'id': id, 'height': 80, 'band_top': 19, 'band_h': 61, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 40, 'text_lines': 1, 'rail_top': -1,
      'organ_top': -1, 'kind': 0, 'group_start': gs, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0,
    };
    final shape = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '등불 기록집', 'events': 0}],
      'tracks': [
        {'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xa0bcc5, 'rows': [for (int r = 0; r < 7; r++) low(r, gs: r == 3 ? 1 : 0)],
          'groups': [{'depth': 0, 'first': 3, 'count': 2, 'name': '하연인', 'color': 0xc27a45, 'kind': 0}]},
      ],
      'epochs': [],
      'variants': [
        {
          'id': 1, 'key': 'scope:s2', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's2', 'name': '남곡 할거',
          'rows': [
            for (final (i, r) in [2, 3, 4, 5].indexed) {'row': r, 'after': r - 1, 'ord': 0, 'new': 0, 'scope_pad': i == 0 ? 16 : 0, 'group_start': i == 0 ? 1 : 0},
            {'row': 6, 'after': 5, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
          ],
          'groups': [
            {'key': '__scope:s2', 'depth': 0, 'name': '남곡 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [2, 3, 4, 5]},
          ],
        },
      ],
    })..reduceMotion = true;
    final track = shape.tracks[0];
    expect(shape.foldGroup(track, track.groups[0], true), isTrue);
    final (scene, painter) = make((t) {
      t.item(ScopeLayer.secScope, 1, 2, at(100), at(1500), row2: 5, name: '남곡 할거', color: 0xd4a39b, b: 4, text2: 's2\u001f시대');
    }, shape: shape, ask: (query) async {
      if (query['op'] == 'rows_near') {
        final all = [for (int r = 0; r < 7; r++) r];
        return {'near': all, 'far': all};
      }
      return {};
    });
    final pixels = await settleAndRender(scene, painter);
    final body = folderBody(painter, '남곡 할거');
    final v = scene.controller.view, head = shape.mergedRows.keys.single, geo = shape.geo(head);
    final top = v.yOf(shape.rowTop(head) + geo.bandTop), bottom = top + geo.bandHeight;
    expect(top, greaterThan(body.top + 6), reason: '접힌 줄 $top ~ $bottom이 그릇 몸통 $body 안');
    expect(bottom, lessThan(body.bottom - 6), reason: '접힌 줄 $top ~ $bottom이 그릇 몸통 $body 안');
    // 줄무늬(7px마다 1px)는 맨 끝에 모든 것 위로 그어지므로 줄무늬 기둥은 견주지 않는다.
    final first = (v.left + Mini.stripeGap).floor(), step = (Mini.stripeGap + Mini.stripeWidth).toInt();
    bool stripe(int x) => x >= first && (x - first) % step == 0;
    final mid = ((top + bottom) / 2).floor(), above = (top - 6).floor();
    final folderPaper = rgba(over(withAlpha(0xffd4a39b, .09), Look.ground));
    final x = body.left.round(), xr = body.right.round() - 1;
    var checked = 0;
    for (final (what, col) in [('왼쪽 테', x), ('안쪽 겹선', x + 2), ('오른쪽 테', xr)]) {
      if (stripe(col)) continue;
      expect(px(pixels, col, above), isNot(folderPaper), reason: '$what(기둥 $col)은 위 줄에서 테 빛');
      expect(px(pixels, col, mid), px(pixels, col, above), reason: '$what(기둥 $col)이 접힌 줄 몸통(y $mid)에서도 위 줄(y $above)과 같은 빛 — 접힌 줄 종이에 지워지지 않는다');
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(2), reason: '줄무늬를 피한 테 기둥');
  });

  test('㉑ 조감의 현재선은 대범위 테두리(불투명 종이) 안에서도 보인다 — 띠 아래 · 종이 위', () async {
    final shape = layout();
    final now = DateTime.now().millisecondsSinceEpoch / 60000;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(480);
    final scene = TimelineScene(controller: controller, layout: shape, fetchTile: (level, x, chunk, packs) async {
      final b = TileBuilder(level: level, x: x, chunk: chunk);
      final lo = now - 40 * m - b.origin, hi = now + 40 * m - b.origin;
      if (hi > 0 && lo < b.span) {
        b.item(ScopeLayer.secScope, 1, 0, lo < 0 ? 0 : lo.toDouble(), hi > b.span ? b.span.toDouble() : hi.toDouble(),
            row2: 1, name: '두 물결', color: 0xd4a39b, flags: (lo < 0 ? Tile.clipLeft : 0) | (hi > b.span ? Tile.clipRight : 0));
      }
      return b.build();
    });
    scene.hide.add('fade');
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    controller.showRange(now - 100 * m, now + 100 * m);
    final pixels = await settleAndRender(scene, painter);
    expect(scene.layout.bird, isTrue);
    expect(painter.debugSink.notes['대범위'], isNotEmpty, reason: '대범위 테두리를 그렸다');
    final v = controller.view, nowX = v.xOf(now).floor();
    final y0 = (v.yOf(shape.rowTop(0)) + 30).ceil(), y1 = v.yOf(shape.rowTop(1) + 100).floor();
    // 테두리 안은 종이 빛(바탕색이 아니다) — 그 안에서 현재선 기둥만 파선(3 켜고 3 끔)으로 옆 기둥과 다르다.
    expect(px(pixels, nowX + 3, y0), isNot(rgba(Look.ground)), reason: '현재선 옆(y $y0)은 테두리 종이 안');
    var dashes = 0;
    for (int y = y0; y < y1; y++) {
      if (px(pixels, nowX, y) != px(pixels, nowX + 3, y)) dashes++;
    }
    expect(dashes, greaterThan((y1 - y0) ~/ 3), reason: '테두리 안(y $y0 ~ $y1)에서 현재선(기둥 $nowX)이 보인다');
  });

  test('㉒ 띠 끝이 px 사이에 선 기둥(반쯤 덮인 끝 · 흐린 띠의 반투명 세로 테)에도 눈금이 비치지 않는다 — 띠 밖 바탕은 그대로', () async {
    final (scene0, painter0) = make((t) {});
    final empty = await settleAndRender(scene0, painter0);
    final left = scene0.controller.view.left;
    final cols = gridColumns(empty, y0: 100);
    // 띠 1의 왼쪽 끝은 눈금 기둥 gl의 .6(그 기둥을 40%만 덮음 — 세로 테가 그 기둥에 선다), 오른쪽 끝은 기둥 gr의 .6(60%를 덮음).
    // 띠 3(줄 2)은 오른쪽 끝이 기둥 gr의 .2 — 20%만 덮인 기둥은 띠 밖이라 그 눈금이 그대로 남는다.
    final gl = cols.firstWhere((x) => x > left + 200), gr = cols.firstWhere((x) => x > gl + 300);
    // 점선 눈금의 꼴(한 줄 걸러 바뀜 — ABA)이 기둥 [x]의 [y0] ~ [y1]에 몇 번 나오는가. 띠 쪽 켜 사이 금처럼 한 번 바뀌고 이어지는 것은 세지 않는다.
    int dotted(ByteData p, int x, int y0, int y1) {
      var n = 0;
      for (int y = y0; y + 2 < y1; y++) {
        final a = px(p, x, y);
        if (px(p, x, y + 1) != a && px(p, x, y + 2) == a) n++;
      }
      return n;
    }

    for (final picked in [false, true]) {
      final what = picked ? '흐린 띠(다른 띠를 고름)' : '밝은 띠';
      final (scene, painter) = make((t) {
        t.band(1, 0, at(gl + .6 - left), at(gr + .6 - left), '해솔국');
        t.band(2, 1, 1 * m, 9 * m, '별여울국');
        t.band(3, 2, at(gl + .6 - left), at(gr + .2 - left), '갈대국');
      });
      if (picked) {
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(const em.Look(band: 2));
      }
      final pixels = await settleAndRender(scene, painter);
      if (picked) expect(em.Emphasis.of(scene).bandAlpha(1, 0), lessThan(1), reason: '띠 1은 흐리다');
      final band = bandRect(painter, 1);
      expect(band.left, closeTo(gl + .6, .05), reason: '$what: 띠 왼쪽 끝 $band');
      expect(band.right, closeTo(gr + .6, .05), reason: '$what: 띠 오른쪽 끝 $band');
      for (final (side, x) in [('왼쪽 끝', gl), ('오른쪽 끝', gr)]) {
        expect(dotted(pixels, x, band.top.ceil() + 14, band.bottom.floor() - 14), 0, reason: '$what: $side 기둥 $x에 눈금 점선이 비친다');
        expect(lineHits(pixels, x, 1000, 1060), greaterThan(20), reason: '$what: 띠 밖 바탕(기둥 $x)에는 눈금이 그대로');
      }
      final thin = bandRect(painter, 3);
      expect(thin.right, closeTo(gr + .2, .05), reason: '$what: 띠 3 오른쪽 끝 $thin');
      expect(dotted(pixels, gr, thin.top.ceil() + 14, thin.bottom.floor() - 14), greaterThan(20), reason: '$what: 20%만 덮인 기둥 $gr(띠 3 밖)의 눈금은 그대로');
    }
  });

  test('㉓ 반투명이던 띠 귀(문화 띠의 옅어지는 끝)의 종이가 귀 칸 안의 제 점무늬를 지우지 않는다 — 귀 종이가 무늬보다 먼저', () async {
    // 폭 120px의 문화 띠: 두 끝이 폭의 12%(14px)만큼 옅어지므로 위 두 귀(반지름 12)가 모두 옅어지는 끝 안이다.
    final (scene, painter) = make((t) => t.band(3, 0, 1 * m, 1 * m + at(120), '은가지 문화', look: BandKind.culture));
    final pixels = await settleAndRender(scene, painter);
    final band = bandRect(painter, 3);
    final note = (painter.debugSink.notes['띠'] ?? const []).map((n) => '$n').firstWhere((n) => n.startsWith('3 '));
    final radii = RegExp(r'반지름=(\d+)/(\d+)').firstMatch(note)!;
    // 위 두 귀의 사분원 안쪽(테 호 · 칸 경계를 피해 1.5px 들임)의 빛 가짓수 — 귀 종이가 무늬 뒤에 찍히면 한 가지뿐이다.
    Set<int> colorsIn(double cx, double cy, double k, bool leftSide) => {
      for (int y = band.top.ceil() + 1; y < band.top + k - 1; y++)
        for (int x = (leftSide ? band.left : band.right - k).ceil() + 1; x < (leftSide ? band.left + k : band.right) - 1; x++)
          if (math.sqrt(math.pow(x + .5 - cx, 2) + math.pow(y + .5 - cy, 2)) < k - 1.5) px(pixels, x, y),
    };
    final kl = double.parse(radii.group(1)!), kr = double.parse(radii.group(2)!);
    expect(kl, greaterThan(6), reason: '왼쪽 위 귀: $note');
    final tl = colorsIn(band.left + kl, band.top + kl, kl, true), tr = colorsIn(band.right - kr, band.top + kr, kr, false);
    expect(tl.length + tr.length, greaterThan(2), reason: '귀 칸 안에 점무늬가 보인다(왼쪽 위 ${tl.length}가지 · 오른쪽 위 ${tr.length}가지): $note');
  });

  test('⑲ 그리개의 걸음 차례 — 눈금 → 바탕 종이 → 그릇 → 바탕 문화 → 칠 없는 카드 종이 → 사람 띠의 실 → 관계선 → 매단 것 → 받침 카드 → 띠', () async {
    // 걸음마다 시간을 재는 진단(profile)은 걸음을 마칠 때 그 이름을 처음 적는다 — 적힌 차례가 곧 걸음의 차례다(실이 있어야 실 걸음이 돈다).
    final (scene, painter) = crownFolderScene();
    await settleAndRender(scene, painter);
    TimelinePainter.profile = true;
    addTearDown(() {
      TimelinePainter.profile = false;
      TimelinePainter.layerMicros.clear();
    });
    TimelinePainter.layerMicros.clear();
    await render(painter);
    final order = TimelinePainter.layerMicros.keys.toList();
    final steps = ['grid', 'grounds', 'scopes', 'under', 'host-paper', 'sphere-threads', 'links-back', 'hangs', 'host-sheets', 'bands'];
    for (final s in steps) {
      expect(order, contains(s), reason: '걸음 $s를 돌았다: $order');
    }
    for (int i = 0; i + 1 < steps.length; i++) {
      expect(order.indexOf(steps[i]), lessThan(order.indexOf(steps[i + 1])), reason: '${steps[i]}는 ${steps[i + 1]}보다 앞: $order');
    }
  });
}
