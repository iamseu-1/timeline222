import 'dart:ui' as ui;

import '../layout.dart';
import '../scene.dart';
import '../sprites.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import '../viewport.dart';
import 'batch.dart';
import 'grounds.dart';
import 'look.dart';
import 'patterns.dart';

// 층은 이 파일만 불러도 묶음 도구(Quads의 hLine · vLine 같은 덧붙임 포함)와 바탕 칸 목록을 쓸 수 있게 함께 내보낸다.
export 'batch.dart';
export 'grounds.dart';

// 한 장면을 그리는 동안 층들이 함께 쓰는 것. 층은 제 파일에서 [TileLayer] · [SceneLayer]를 구현하고, 그리기 호출은 여기의 묶음 연장으로만 한다.
// 층의 차례와 묶음을 내보내는 때는 painter.dart가 정한다 — 층은 "모으기"만 하고 제멋대로 내보내지 않는다(같은 종류의 그리기가 이어져야 GPU가 묶는다).

class DebugBand {
  DebugBand(this.id, this.rect, this.roundLeft, this.roundRight, this.fadeLeft, this.fadeRight);
  final int id;
  final ui.Rect rect;
  final bool roundLeft, roundRight, fadeLeft, fadeRight;
}

class DebugLabel {
  DebugLabel(this.kind, this.text, this.at, [this.alpha = 1]);
  final String kind, text;
  final ui.Offset at;
  final double alpha;
}

class DebugDot {
  DebugDot(this.eventId, this.at, this.extra);
  final int eventId, extra;
  final ui.Offset at;
}

class DebugBar {
  DebugBar(this.eventId, this.rect);
  final int eventId;
  final ui.Rect rect;
}

/// 검사용 기록: 그린 띠 조각 · 이름 · 점 · 막대. 층이 더 적고 싶은 것은 [notes]에 (종류 → 목록)으로.
class DebugSink {
  final bands = <DebugBand>[];
  final labels = <DebugLabel>[];
  final dots = <DebugDot>[];
  final bars = <DebugBar>[];
  final notes = <String, List<Object>>{};
  ui.Offset? selectionAt;
  int gridLines = 0;

  void clear() {
    bands.clear();
    labels.clear();
    dots.clear();
    bars.clear();
    notes.clear();
    selectionAt = null;
  }

  void note(String kind, Object what) => (notes[kind] ??= []).add(what);
}

class PaintContext {
  PaintContext({required this.canvas, required this.scene, required this.text, required this.w, required this.h, required this.quads, required this.dividers, required this.later, required this.patterns, this.debug, Grounds? grounds, Quads? under})
    : grounds = grounds ?? (Grounds()..reset(Look.ground)),
      under = under ?? Quads(),
      v = scene.controller.view,
      layout = scene.layout,
      stats = scene.stats,
      hide = scene.hide,
      sprites = Sprites.shared;
  final ui.Canvas canvas;
  final TimelineScene scene;
  final SceneText text;

  /// 그림 전체의 폭과 높이(배치 px — 돋보기 배율로 나눈 값).
  final double w, h;
  final Quads quads;

  /// 이 걸음의 다른 네모보다 먼저 나가는 밑 종이 네모(띠 끝이 px 사이에 선 기둥 밑의 바탕색 종이 — paint/bands.dart `_edgePaper`).
  /// 같은 기둥을 나눠 덮는 이웃 띠의 칠이 둘 다 이 종이 위에 섞이게 따로 모은다. 그리개 · SVG가 [quads]와 같은 길로 지어 넘긴다.
  final Quads under;
  final Lines dividers;
  final TextQueue later;
  final DebugSink? debug;

  /// 무늬(빗금 · 세로 줄 · 점무늬)의 묶음 — 모든 층이 함께 쓴다.
  final Patterns patterns;

  /// 그 자리의 바탕색(불투명) — 바탕 종이를 까는 층(그릇 · 판 · 바탕 문화)이 칸을 등록하고, 그 위에 반투명 칠을 얹는 층이 묻는다(paint/grounds.dart).
  /// 띠 쪽 그림은 아래의 연도 세로줄을 가리는 종이라 반투명 칠도 그 자리 바탕색과 미리 섞은 불투명 색으로 칠한다(그리개 머리 주석).
  final Grounds grounds;

  // 장면마다 한 번 굳힌 밭. 층은 `c.v` · `c.layout` · `c.stats`를 항목마다 부르는데, getter 사슬(scene → controller → view)로 두면
  // 그 사슬을 장면마다 수만 번 탄다. 한 장면 안에서는 가리키는 것이 바뀌지 않으므로 여기서 한 번만 집는다.
  final SceneView v;
  final SceneLayout layout;
  final SceneStats stats;
  final Set<String> hide;
  final Sprites sprites;

  /// 그림 영역의 왼쪽 끝(왼쪽 칸의 폭)과 몸통의 위 끝(날짜 칸의 높이).
  double get left => v.left;
  double get head => v.head;

  final fill = ui.Paint();
  final stroke = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1;

  /// 모아 둔 도형을 내보낸다: 밑 종이 네모 → 네모 → 무늬 → 작은 그림판의 조각 → 가는 선.
  void flushShapes() {
    under.flush(canvas);
    quads.flush(canvas);
    patterns.flush(canvas);
    sprites.flush(canvas);
    dividers.flush(canvas);
  }

  /// 모아 둔 글자를 내보낸다.
  void flushText() {
    stats.labels += later.paint(canvas, text, onPainted: debug == null ? null : (kind, what, x, y, alpha) => debug!.labels.add(DebugLabel(kind, what, ui.Offset(x, y), alpha)));
  }

  /// 줄이 보이는가(켠 자료집 · 접히지 않음)와 그 줄의 띠 상자가 세로로 화면에 걸치는가.
  /// 줄이 흐르며 자라거나 줄어드는 동안([SceneLayout.rowClip])은 상자가 그 줄의 보이는 몫 안에 다 들 때만 — 다 자라지 않은 줄의 내용
  /// (머리 이름 · 탭 · 칸 · 열쇠표 …)이 아래 줄의 띠 위로 넘쳐 포개지지 않게(감독 2026-10-26 '신라 쪽 휠 — 신라 이름표가 튀어나감').
  /// 띠 몸은 띠 층이 그 몫에서 잘라 넘긴다([BandLayer] — 높이를 줄여 이 문을 지난다).
  bool rowOnScreen(int row, double top, double height) => top <= h && top + height >= head && fitsRow(row, top + height);

  /// 화면 y [bottom]까지가 줄 [row]의 보이는 몫 안인가 — 흐르지 않는 줄은 늘 참.
  bool fitsRow(int row, double bottom) {
    final clip = layout.rowClip(row);
    return clip == null || bottom <= v.yOf(layout.rowTop(row) + clip) + .5;
  }
}

/// 타일마다 부르는 층(띠 · 칸 · 막대 …).
abstract class TileLayer {
  /// 장면의 처음에 한 번(장면마다 다시 쓰는 기억을 비운다).
  void beginFrame(PaintContext c) {}
  void paintTile(PaintContext c, Tile t);

  /// 제 층만의 묶음(제 그림판 · 무늬)을 내보낸다. 공통 묶음(네모 · 조각 · 선)이 나간 바로 뒤에 불린다.
  void flush(PaintContext c) {}

  /// 제 층의 밑 조각(그 걸음의 네모 · 무늬보다 아래에 깔릴 것 — 반투명이던 띠 귀 · 구역 탭 귀의 불투명 종이)을 내보낸다.
  /// 공통 묶음(네모 · 무늬 · 조각 · 선)이 나가기 바로 앞에 불린다 — 귀 칸 안의 제 무늬 · 깃대를 덮지 않게(리메이크 4단계 세로줄 얹기 검토).
  void flushUnder(PaintContext c) {}

  /// 멎은 돋보기 배율(× 화면의 px 비율)이 바뀌었다 — 제 그림판을 그 배율로 다시 뜬다.
  void setScale(double scale) {}
}

/// 장면마다 한 번 부르는 층(바탕 눈금 · 사건 · 왼쪽 칸 · 날짜 칸).
abstract class SceneLayer {
  /// 그리는 쪽이 만들어질 때 한 번: 장면에 곁들이는 자료(줄 이름 …)를 받아 오는 길을 걸어 둔다.
  void attach(TimelineScene scene) {}
  void paint(PaintContext c);
  void setScale(double scale) {}
}

/// 색 섞기의 짧은 이름(2단계의 단순 섞기 — css와 같은 식은 color_mix.dart).
int mixPaper(int color, double amount) => Look.mix(Look.paper, color, amount);
