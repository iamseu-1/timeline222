import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'cleartype_prefs.dart';
import 'emphasis.dart' show Emphasis;
import 'glyph_atlas.dart' show AtlasText;
import 'marks.dart';
import 'paint/axis.dart';
import 'paint/bands.dart';
import 'paint/bars.dart';
import 'paint/context.dart';
import 'paint/events.dart';
import 'paint/figures.dart';
import 'paint/grid.dart';
import 'paint/gutter.dart';
import 'paint/hangs.dart';
import 'paint/links.dart';
import 'paint/look.dart';
import 'paint/minibars.dart';
import 'paint/overlay.dart';
import 'paint/patterns.dart';
import 'paint/rails.dart';
import 'paint/scopes.dart';
import 'paint/strips.dart';
import 'paint/unions.dart';
import 'ruler.dart';
import 'scene.dart';
import 'sprites.dart';
import 'text_paragraph.dart';
import 'tile.dart';

export 'paint/context.dart' show DebugBand, DebugBar, DebugDot, DebugLabel, DebugSink;
export 'paint/look.dart';

// 한 장면 그리기. 보이는 타일의 배열을 훑어 화면 좌표로 바꾸고 층마다 묶어 그린다.
// 장면마다 자료를 조회하거나 정렬하거나 글자 모양을 새로 잡지 않는다(글줄은 보관한 것을 쓰고 새 것은 예산만큼만).
// saveLayer는 막 도착해 떠오르는 타일에만, clipRect는 그림 영역 · 메움 자리에만 쓴다 — 항목마다 쓰지 않는다.
// 층은 paint/ 아래의 파일 하나씩이다. 여기는 층의 차례와 묶음을 내보내는 때만 정한다(지금 연표의 쌓임 순서):
//   바탕 눈금
//   → 뒤 판(타일마다): 대범위 테두리 → 띠 뒤의 관계선 → 띠 아래에 매달린 것(속국 이름표 · 구역 탭 · 바탕 문화 이름)
//   → 앞 판(타일마다): 띠 채움과 무늬 → 띠 안의 칸 → 인물 막대 → 기간 막대 → 띠 테두리 → 띠 위의 네모 · 다리 · 문 → 글자
//   → 사건(점 · 알약 · 이름) → 왼쪽 칸 → 날짜 칸
// 층 사이마다 공통 묶음(네모 → 무늬 → 조각 → 가는 선)과 그 층의 묶음을 내보낸다 — 앞 층의 도형이 뒤 층의 도형 위로 올라오지 않게.
class TimelinePainter extends CustomPainter {
  TimelinePainter(
    this.scene, {
    SceneText? text,
    Quads Function()? quads,
    Lines Function(int argb)? lines,
    Patterns Function()? patterns,
    this.clearType = true,
  }) : text = text ?? ParagraphText(),
       _newQuads = quads ?? Quads.new,
       _newLines = lines ?? Lines.new,
       _newPatterns = patterns ?? Patterns.new,
       super(repaint: scene) {
    scene.nameFade.enabled = this.text.canFade;
    axis.attach(scene);
    gutter.attach(scene);
    // 조감에서 단추 · 내림줄 · 오름줄이 띠 안 이름을 비키려면 띠 층이 잰 값을 봐야 한다(bands3 ㈎ · ㈏).
    // 단추 층(`ScopeMarks`)은 관계선 층이 들고 있으므로 `links.bands` 하나가 둘을 다 잇는다.
    links.bands = bands;
  }
  final TimelineScene scene;

  /// 글자 방식: (가) 글줄 보관 ParagraphText, (나) 그림판 AtlasText. 같은 장면으로 재서 고른다.
  final SceneText text;

  /// ClearType을 써도 되는 그림판인가. 화면은 참, 그림 저장(이미지 · 인쇄)은 거짓 — 색 테두리가 파일에 남지 않게(검토 초점 5).
  final bool clearType;

  /// 화면의 px 비율(배치 px 하나가 화면 px 몇 개인가). 그림판 방식이 글자를 화면 px에 맞춰 준비하는 데 쓴다.
  double devicePixelRatio = 1;

  /// 검사용: 그린 띠 조각과 이름을 적어 둔다.
  bool debug = false;
  final debugSink = DebugSink();
  List<DebugBand> get debugBands => debugSink.bands;
  List<DebugLabel> get debugLabels => debugSink.labels;
  List<DebugDot> get debugDots => debugSink.dots;
  List<DebugBar> get debugBars => debugSink.bars;
  ui.Offset? get debugSelectionAt => debugSink.selectionAt;
  int get debugGridLines => debugSink.gridLines;

  final _ruler = Ruler();

  /// 묶음을 짓는 길. 내보내기(SVG)가 SVG 묶음으로 갈아 끼운다 — 갈아 끼우지 못하는 묶음은 SVG에서만 그림이 빠진다.
  final Quads Function() _newQuads;
  final Lines Function(int argb) _newLines;
  final Patterns Function() _newPatterns;

  late final _quads = _newQuads();
  late final _dividers = _newLines(Look.line);
  final _later = TextQueue();
  late final _patterns = _newPatterns();
  final _watch = Stopwatch();

  /// 층별 시간 재기(진단용 — 켜면 [layerMicros]에 층 이름별로 쌓인다). 끄면 비용이 없다.
  static bool profile = false;
  static final layerMicros = <String, int>{};
  final _lap = Stopwatch();
  void _mark(String name) {
    if (!profile) return;
    layerMicros[name] = (layerMicros[name] ?? 0) + _lap.elapsedMicroseconds;
    _lap
      ..reset()
      ..start();
  }
  double _scale = 1;

  // 층
  final grid = GridLayer();
  final scopes = ScopeLayer();
  final links = LinkLayer();
  final hangs = HangLayer();
  final bands = BandLayer();
  final minibars = MiniBarLayer();
  final strips = StripLayer();
  // 동군연합 이음줄(건의 8의 6-다): 칸 층이 그린 이름 자리를 묻는다.
  late final unions = UnionLayer()..strips = strips;
  // 띠의 제 끝(분)과 미정 꼬리는 막대 층과 인물 층이 함께 쓴다 — 장면마다 띠 훑기가 한 번이 되게 하나를 나눠 준다.
  final _spans = BandSpans();
  late final figures = FigureLayer(spans: _spans);
  late final rails = RailLayer(spans: _spans, overlay: _newQuads());
  final bars = BarLayer();
  final events = EventLayer();
  final overlay = OverlayLayer();
  final gutter = GutterLayer();
  final axis = AxisLayer();

  // 차례는 장면 준비(beginFrame)와 배율 전하기에만 쓴다(그리는 차례는 paint 안에). 막대 층이 띠 범위를 비운 뒤에 인물 층이 모으게 rails가 먼저다.
  // **띠 층이 맨 앞이다**: 조감의 띠 안 이름 자리(`birdNameEnd` · `birdNameZones`)를 `BandLayer.beginFrame`이 채우고,
  // 단추 층(scopes)과 관계선 층(links)이 같은 장면에 그것을 읽는다(bands3 ㈐). 띠 층의 beginFrame은 다른 층에서 받는 것이 없다.
  late final List<TileLayer> _tileLayers = [bands, scopes, links, hangs, minibars, strips, rails, figures, bars, unions];

  // 판을 이루는 걸음들. 한 번 지어 두고 장면마다 다시 쓴다(장면마다 닫힘꼴을 새로 만들지 않는다).
  late final List<_Step> _backSteps = [
    _Step('scopes', scopes.paintTile, scopes),
    _Step('links-back', links.paintTile, links),
    // 동군연합 이음줄의 두 나라 띠 사이 몫(승계선처럼 띠 뒤 · 매달린 이름표보다도 뒤).
    _Step('unions-back', null, unions, once: unions.paintBack),
    _Step('hangs', hangs.paintTile, hangs, text: true),
  ];
  late final List<_Step> _frontSteps = [
    // 속국 띠 뒤의 상국 빛깔 종이(건의 8의 2번 C) — 띠 걸음보다 먼저 내보내 띠 · 탭 아래에 깔린다.
    _Step('host-sheets', null, bands, once: bands.paintHostSheets),
    // 띠의 채움(네모 묶음 → 무늬 → 모서리 조각)을 칸보다 먼저 내보낸다.
    _Step('bands', bands.paintTile, bands),
    // 접힌 트랙 · 접힌 민족 줄의 가는 막대(띠 대신).
    _Step('minibars', minibars.paintTile, minibars),
    // 할거기 칠: 띠 바탕 위 · 칸 아래.
    _Step('scopes-over', scopes.paintOverBands, scopes),
    _Step('strips', strips.paintTile, strips),
    _Step('figures', figures.paintTile, figures),
    _Step('rails', _railsAndBars, rails),
    // 속국 이름표의 세로 끈은 띠 위에 온다(지금 연표의 .tl-hang-link에는 z가 없다).
    _Step('hangs-front', hangs.paintFront, hangs),
    // 층의 순서: (띠 채움) → 칸 바탕 → 구분선 → 띠 테두리 → 띠 위의 것 → 글자. 글자를 맨 끝에 몰아야 글자 그리기끼리 이어져 한 번에 묶인다.
    _Step('band-edges', null, bands, once: bands.paintEdges, text: true),
  ];
  late final List<_Step> _markSteps = [
    // 그릇 폴더 탭의 이름 종이(라벨 · 세 칸 손잡이 · 접힌 폴더의 작은 꼬리표 — 리메이크 조각 ③): 날짜 눈금이 지나가지 않게 표식 판에.
    _Step('scopes-labels', null, scopes, once: scopes.paintLabels, text: true),
    // 동군연합 이음줄의 띠 안 몫 · 끝의 고리 · 겹고리 표지(칸 · 이름 위).
    _Step('unions-front', null, unions, once: unions.paintFront),
    _Step('links-front', links.paintFront, links, text: true),
  ];
  late final _foldedRowsStep = _Step('folded-rows', null, minibars);

  void _railsAndBars(PaintContext c, Tile t) {
    rails.paintTile(c, t);
    bars.paintTile(c, t);
  }

  /// 걸음 하나를 마무리한다: 타일과 상관없는 몫(띠 테두리)을 그리고 모은 것을 내보낸다.
  /// 진단을 켜면 '모으기'(층 이름) · '내보내기'(flush) · '글자'(text)를 따로 적는다 — 어느 쪽을 줄일지 이것으로 갈랐다.
  void _finish(PaintContext c, _Step s) {
    s.once?.call(c);
    _mark(s.name);
    c.flushShapes();
    s.layer.flush(c);
    _mark('flush');
    if (s.text) {
      c.flushText();
      _mark('text');
    }
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    _watch
      ..reset()
      ..start();
    // 글줄 준비의 예산은 장면 준비(사건 이름의 폭 재기)부터 센다.
    text.beginFrame();
    // 이 그림판이 ClearType을 그릴 수 있는가 — 장면이 멈춘 뒤의 기다림(150ms)에 깨울 타이머를 걸지 정한다. 그림 저장의 그림판(clearType 거짓)은 알리지 않는다.
    final t = text;
    final lcdPossible = clearType && ClearTypePrefs.on && ClearTypePrefs.system.on && devicePixelRatio < 1.5;
    if (clearType) scene.clearTypeWanted = lcdPossible && t is AtlasText && t.baker != null;
    // 돋보기가 멎으면 그 배율(× 화면의 px 비율)로 글자 · 조각 · 무늬를 다시 준비한다(움직이는 동안은 옛 그림을 키워 쓴다).
    if (!scene.controller.active.value) {
      final scale = scene.controller.view.mag * devicePixelRatio;
      text.setScale(scale);
      Sprites.shared.setScale(scale);
      if (scale != _scale) {
        _scale = scale;
        _patterns.setScale(scale);
        for (final layer in _tileLayers) {
          layer.setScale(scale);
        }
        events.setScale(scale);
        gutter.setScale(scale);
        axis.setScale(scale);
        overlay.setScale(scale); // 도착 고리의 조각도 같은 배율로(돋보기에서 무르지 않게)
      }
    }
    scene.measureName ??= (title, importance) => text.widthOf(title, Look.event(importance));
    if (profile) {
      _lap
        ..reset()
        ..start();
    }
    _emphasize();
    scene.prepare();
    _sortDraw();
    _mark('prepare');
    // ClearType(설계 3-2): 멈춘 장면 · 1배 언저리 · 켬 · 그림 저장이 아님일 때만. 그 밖은 회색 판 그대로.
    // 장면 준비(prepare) 뒤에 정한다 — 타일이 막 도착해 떠오르기 시작한 장면을 이번 장면에서 바로 회색으로 알아보게(앞에서 정하면 한 장면 늦어 ClearType이 한 번 번쩍인다).
    if (t is AtlasText) {
      t.lcdAllowed = lcdPossible && t.baker != null && scene.stillForClearType; // 굽개가 없으면 글줄마다 글꼴 파일을 찾는 헛일도 하지 않게
      t.bgr = ClearTypePrefs.system.bgr;
    }
    final v = scene.controller.view;
    final stats = scene.stats
      ..shapes = 0
      ..labels = 0;
    if (debug) debugSink.clear();
    final w = size.width / v.mag, h = size.height / v.mag;
    final c = PaintContext(canvas: canvas, scene: scene, text: text, w: w, h: h, quads: _quads, dividers: _dividers, later: _later, patterns: _patterns, debug: debug ? debugSink : null);
    canvas.save();
    canvas.scale(v.mag);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), c.fill..color = ui.Color(Look.ground));

    for (final layer in _tileLayers) {
      layer.beginFrame(c);
      if (profile) _mark('begin:${layer.runtimeType}');
    }

    // 몸통: 그림 영역으로 한 번만 자른다.
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTRB(v.left, v.head, w, h));
    final marks = _ruler.compute(v.lo, v.hi, v.ppm, cycle: axis.model?.yearCycle, cycleNeed: axis.cycleNeed(c));
    grid.paint(c, marks);
    _mark('grid');

    // 뒤 판: 띠보다 아래에 깔리는 것. 타일을 모두 돈 뒤에 앞 판을 그려야 이웃 타일의 띠가 이 선들을 덮는다.
    _pass(c, _backSteps);
    // 앞 판
    _pass(c, _frontSteps);
    // 몸통 쪽 접힌 줄의 바탕(90° 줄무늬)은 타일 바퀴가 끝난 뒤 한 번.
    minibars.paintFoldedRows(c);
    _finish(c, _foldedRowsStep);
    grid.paintOver(c, marks);
    c.flushShapes();
    _mark('grid-over');
    events.paint(c);
    _mark('events');
    // 표식 판: 건국 · 멸망 네모 · 문 · 다리 · 단추는 사건보다 위다(지금 연표의 .tl-marks z-3 > 사건 z-1) — 사건 이름의 종이색 바탕이 네모를 지우지 않게.
    _pass(c, _markSteps);
    // 맨 위: 도착 고리 같은 한 번의 표시.
    overlay.paint(c);
    c.flushShapes();
    c.flushText();
    _mark('overlay');
    canvas.restore();

    // 왼쪽 칸도 몸통 높이로 자른다: 민족 · 대범위 칸은 화면 위로 넘어간 줄부터 한 덩이로 그리므로, 자르지 않으면 내려 본 동안
    // 그 칸의 윗부분이 날짜 칸 위(맨 위 줄 — 기간 · 검색 칸 뒤)로 비쳐 올라온다(감독 건의 2026-10-14 1번).
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTRB(0, v.head, w, h));
    gutter.paint(c);
    overlay.paintGutter(c); // 연합의 겹 탭에 올렸을 때 구성 나라가 아닌 줄 이름의 흐림(감독 선택 D5 결정 3 C)
    canvas.restore();
    _mark('gutter');
    axis.paint(c, marks);
    _mark('axis');
    canvas.restore();

    stats
      ..newParagraphs = text.newThisFrame
      ..textMs = text.spentMs
      ..paintMs = _watch.elapsedMicroseconds / 1000;
    if (text.starved) scene.requestFrame();
    scene.onPainted?.call(stats);
  }

  // 밝기 상태(고르기 · 강조 · 조명)를 층마다 걸어 주고, 흐르는 동안에는 장면마다 시계를 돌려 다음 장면을 청한다.
  // 시간은 **장면의 시계**(`scene.now`)로 잰다 — 느리게 보기(`Motion.slow`)와 함께 느려지게(11물결 motion ⑤).
  double _emphasisAt = -1;
  // 아무도 적지 않은 동안(번호 0)에는 층의 밭을 건드리지 않는다 — 층에 값을 직접 넣어 보는 검사와 부딪히지 않게.
  int _marksVersion = 0;
  void _emphasize() {
    final e = Emphasis.of(scene)..reduceMotion = scene.controller.reduceMotion;
    if (!identical(bands.emphasis, e)) {
      bands.emphasis = e;
      strips.emphasis = e;
      figures.emphasis = e;
      rails.emphasis = e;
      hangs.emphasis = e;
      links.emphasis = e;
      unions.emphasis = e;
      scopes.emphasis = e;
      events.emphasis = e;
      gutter.emphasis = e;
      axis.emphasis = e;
    }
    // 표시 상태(기준선 · 기간 재기 · 커서가 올라간 것 · 펼친 상위 정권 · 켠 대범위 · 승계선 보기)를 층의 밭에 옮긴다.
    final m = SceneMarks.of(scene);
    if (m.version != _marksVersion) {
      _marksVersion = m.version;
      grid
        ..marker = m.marker
        ..markerText = m.markerText + (m.marker != null && m.yearCycle?.custom == true ? ' ${m.yearCycle!.name(yearAt(m.marker!).floor())}' : '')
        ..measure = m.measure
        ..measureText = m.measureText;
      axis
        ..pickedCell = m.pickedAxisCell
        ..hotCity = m.hotCity;
      // 날짜 칸 표시 체크 넷(간지 · 연호 · 도읍 · 시대 구분) — 바뀌지 않았으면 층이 아무 일도 하지 않는다(다시 그리기 고리 없음).
      // 그리는 도중이라 보기에 알리는 일은 마이크로태스크로 미룬다(defer).
      axis.setShown(ganji: m.showGanji, eras: m.showEras, capitals: m.showCapitals, epochs: m.showEpochs);
      axis.setYearCycle(m.yearCycle);
      bands.hotBand = m.hotBand;
      strips
        ..hotCell = m.hotCell
        ..hotTwins = m.hotTwins;
      figures
        ..pickedFigure = m.pickedFigure
        ..hoverFigure = m.hoverFigure;
      gutter
        ..hotRow = m.hotRow
        ..hotTrack = m.hotTrack;
      links
        ..successionMode = m.successionMode
        ..showPartOf = m.showPartOf
        ..hotBand = m.hotBand
        ..hotLink = m.hotLink;
      links.expanded
        ..clear()
        ..addAll(m.expanded);
      links.scopesOn
        ..clear()
        ..addAll(m.scopesOn);
      hangs.expanded
        ..clear()
        ..addAll(m.expanded);
    }
    if (e.active) {
      final now = scene.now;
      e.tick(_emphasisAt < 0 ? 0 : now - _emphasisAt);
      _emphasisAt = now;
      if (e.active) scene.requestFrame();
    } else {
      _emphasisAt = -1;
    }
  }

  /// 그릴 타일을 한 바퀴 돈다.
  ///
  /// 타일은 가로(x)와 줄 묶음(chunk)으로 갈려 **서로 겹치지 않는다** → 다 뜬 보통 타일은 **층을 바깥 · 타일을 안쪽**으로 돌아
  /// 층마다 한 번만 내보낸다(타일이 넷이면 내보내기가 넷에서 하나로 준다. 겹치지 않으니 이웃 타일의 층 차례가 뒤바뀌어도
  /// 같은 픽셀을 두고 다투는 일이 없다).
  /// 제 자리만큼 잘라야 하는 메움 타일과 떠오르는 중(alpha < 1)인 타일만 예전처럼 타일마다 층을 다 돈다 —
  /// 자르기 · 층 감싸기가 그 타일의 그리기 전부를 품어야 하기 때문이다.
  void _pass(PaintContext c, List<_Step> steps) {
    if (_plain.isNotEmpty) {
      for (final s in steps) {
        final each = s.each;
        if (each != null) {
          for (final d in _plain) {
            each(c, d.tile);
          }
        }
        _finish(c, s);
      }
    }
    final canvas = c.canvas;
    for (final d in _wrapped) {
      final layered = d.alpha < 1;
      if (d.clip != null) {
        canvas.save();
        canvas.clipRect(d.clip!);
      }
      if (layered) {
        canvas.saveLayer(d.fadeRect, ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, d.alpha));
      }
      for (final s in steps) {
        s.each?.call(c, d.tile);
        _finish(c, s);
      }
      if (layered) canvas.restore();
      if (d.clip != null) canvas.restore();
    }
  }

  /// 겹치지 않는 보통 타일과, 제 자리를 감싸야 하는 타일(메움 · 떠오르는 중)을 갈라 둔다(장면마다 한 번).
  final _plain = <DrawTile>[], _wrapped = <DrawTile>[];
  void _sortDraw() {
    _plain.clear();
    _wrapped.clear();
    for (final d in scene.draw) {
      (d.clip == null && d.alpha >= 1 ? _plain : _wrapped).add(d);
    }
  }

  @override
  bool shouldRepaint(covariant TimelinePainter old) => old.scene != scene;
}

/// 판을 이루는 걸음 하나: 타일마다 하는 일([each]) · 타일과 상관없이 한 번만 하는 일([once]) · 그 뒤에 내보낼 층.
class _Step {
  const _Step(this.name, this.each, this.layer, {this.once, this.text = false});

  /// 진단(`TimelinePainter.layerMicros`)에 적히는 이름.
  final String name;
  final void Function(PaintContext c, Tile t)? each;
  final void Function(PaintContext c)? once;
  final TileLayer layer;

  /// 이 걸음 뒤에 모아 둔 글자도 내보내는가(글자는 층의 끝에 몰아 그린다).
  final bool text;
}
