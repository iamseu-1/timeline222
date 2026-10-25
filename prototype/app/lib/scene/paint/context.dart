import 'dart:ui' as ui;

import '../layout.dart';
import '../scene.dart';
import '../sprites.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import '../viewport.dart';
import 'batch.dart';
import 'look.dart';
import 'patterns.dart';

// 층은 이 파일만 불러도 묶음 도구(Quads의 hLine · vLine 같은 덧붙임 포함)를 쓸 수 있게 함께 내보낸다.
export 'batch.dart';

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
  PaintContext({required this.canvas, required this.scene, required this.text, required this.w, required this.h, required this.quads, required this.dividers, required this.later, required this.patterns, this.debug})
    : v = scene.controller.view,
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
  final Lines dividers;
  final TextQueue later;
  final DebugSink? debug;

  /// 무늬(빗금 · 세로 줄 · 점무늬)의 묶음 — 모든 층이 함께 쓴다.
  final Patterns patterns;

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

  /// 모아 둔 도형을 내보낸다: 네모 → 작은 그림판의 조각 → 가는 선.
  void flushShapes() {
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
  bool rowOnScreen(int row, double top, double height) => top <= h && top + height >= head;
}

/// 타일마다 부르는 층(띠 · 칸 · 막대 …).
abstract class TileLayer {
  /// 장면의 처음에 한 번(장면마다 다시 쓰는 기억을 비운다).
  void beginFrame(PaintContext c) {}
  void paintTile(PaintContext c, Tile t);

  /// 제 층만의 묶음(제 그림판 · 무늬)을 내보낸다. 공통 묶음(네모 · 조각 · 선)이 나간 바로 뒤에 불린다.
  void flush(PaintContext c) {}

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
