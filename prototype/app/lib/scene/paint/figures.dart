import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../marks.dart';
import '../sprites.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import 'context.dart';
import 'ink.dart';
import 'look.dart';
import 'patterns.dart';
import 'rails.dart';

// 인물의 활동 막대와 묶음(구역 37 · 38) — 지금 연표의 `.tl-fig`(js/timeline.js 6358~6460 · css/common.css 1356~1386).
// 막대는 기간 막대 칸 아래, 단마다 15px(사이 2px)이고 섬긴 구간을 제 띠의 기간 안으로 자른 뒤 띠 안쪽 4px에 가둔다.
// 아주 짧은 활동도 3px은 보이게 하고, 그 띠에서 **보이는 막대의 평균 폭이 6px 미만**이면 단 전체를 '인물 n명' 한 칸으로 바꾼다(문턱 둘).
//
// 한 띠의 막대가 여러 타일에 흩어져 있어도 평균은 하나여야 하므로, 장면의 처음(beginFrame)에 그릴 타일을 모두 훑어
// 띠마다의 평균과 나눌지 말지를 먼저 정하고, 타일을 그릴 때는 그 판정만 본다.

/// 인물 단의 값(지금 연표의 css · G).
abstract final class FigureLook {
  /// 단 하나의 높이 15 · 단 사이 2 · 띠 안쪽 여백 4(테두리 1 + 3) · 막대의 최소 폭 3.
  static const height = 15.0, gap = 2.0, inset = 4.0, minWidth = 3.0;

  /// 둥근 모서리 7(폭 8px 미만이면 2) · 이름이 드는 여유(온 이름 +12 · 첫 글자 +8).
  static const radius = 7.0, thinRadius = 2.0, thin = 8.0, fitName = 12.0, fitFirst = 8.0;

  /// 미정 끝의 꼬리: 적어도 3 · 많아야 44 · 폭의 0.4배(이름이 없으면 0.3배)까지.
  static const fadeMin = 3.0, fadeMax = Look.fuzzyFade, fadeOfWidth = .4, fadeNoName = .3;

  /// '인물 n명' 한 칸으로 묶는 문턱(평균 폭 px)과 되돌림(천분율) — 자료가 실어 보내지 않으면 이 값.
  static const denseWidth = 6.0, denseBack = 80;

  /// 옅은 세로 결(1px 긋고 4px마다) — 빽빽한 한 칸의 바탕.
  static const densePattern = PatternSpec.stripes(90, 1, 4);

  /// 한 해의 분(장면이 쓰는 값과 같다) — 1년이 안 되는 활동의 폭을 그 1년으로 셈할 때.
  static const yearMinutes = 525960.0;

  static const secBar = 37, secGroup = 38, secAlt = 39;

  /// 수명선 `.ln`: 막대 세로 가운데의 1px 선(짙기 .85) · 막대 밖으로 2px 넘게 나갈 때만 · 끝 점 4px.
  static const lifeShow = 2.0, lifeAlpha = .85, lifeDot = 4.0;

  /// 생몰 이설의 빈 고리 `.lnalt`: 5px · 막대에서 3px 넘게 떨어진 자리에만.
  static const lifeAltSize = 5.0, lifeAltGap = 3.0;

  /// 유령 구분선 `.tl-calt`: 1px 점선(1 켜고 2 끔) · 위아래 2px 들임 · 짙기는 edge-soft의 75%.
  static const ghostInset = 2.0, ghostDash = 1.0, ghostGap = 2.0, ghostMix = .75;

  /// 유령 구분선을 그을 수 있는 여유(진짜 테두리 · 막대 끝에서 이만큼 안쪽이어야 — 지금 연표의 ALT_GAP과 같은 3px).
  static const ghostEdge = 3.0;

  /// 글자 사이(기준 덤프의 `ls: -0.14px` — 연표 전체가 물려받는 값).
  static const spacing = -.14;

  /// 글자: 10px · 중요도 3은 굵게(700) 아니면 500. 굵기는 이어지는 글꼴의 축(`wght`)으로 못 박는다 —
  /// 이름만 주면 없는 굵기를 억지로 부풀려(가짜 굵게) 브라우저보다 굵게 나온다.
  static TextLook name(int importance, int ink) =>
      TextLook(10, importance >= 3 ? ui.FontWeight.w700 : ui.FontWeight.w500, ink, spacing: spacing, wght: importance >= 3 ? 700 : 500);
}

/// 맞히기(총괄이 잇는다): 인물 막대 하나 또는 '인물 n명' 한 칸.
class FigureHit {
  const FigureHit({required this.band, required this.row, this.figure = '', this.lane = 0, this.group = false, this.count = 0});

  /// 막대가 든 띠의 번호와 줄. [group]이면 그 띠의 정권 상세 → 인물 목록으로 간다.
  final int band, row, lane, count;

  /// 인물의 uid(묶음이면 빈 글).
  final String figure;
  final bool group;

  @override
  String toString() => group ? '인물묶음 띠$band 줄$row ($count명)' : '인물 "$figure" 띠$band 줄$row 단$lane';
}

/// 마지막 장면의 자리 기록 하나(배치 px).
class _Spot {
  _Spot(this.hit, this.x0, this.y0, this.x1, this.y1);
  final FigureHit hit;
  final double x0, y0, x1, y1;
}

/// 이 층의 작은 그림판: 수명선의 끝 점(4px 원)과 생몰 이설의 빈 고리(5px). `scene/sprites.dart`는 공용이라 고치지 않는다.
class FigureParts {
  FigureParts._(this._image, this._scale);
  ui.Image _image;
  double _scale;

  static const cell = 10.0;
  static const dot = ui.Rect.fromLTWH(0, 0, cell, cell); // 4px 원(수명선 끝 점의 바탕)
  static const dotRing = ui.Rect.fromLTWH(cell, 0, cell, cell); // 그 둘레의 1px 테
  static const ring = ui.Rect.fromLTWH(cell * 2, 0, cell, cell); // 5px 빈 고리의 테
  static const ringInner = ui.Rect.fromLTWH(cell * 3, 0, cell, cell); // 그 안(종이색)
  static const _sheetWidth = cell * 4, _sheetHeight = cell;

  static FigureParts? _shared;
  static FigureParts get shared => _shared ??= FigureParts._(_render(1), 1);

  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image.dispose();
    _image = _render(next);
    _scale = next;
  }

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    void disc(ui.Rect at, double size) => canvas.drawCircle(at.center, size / 2, white);
    disc(dotRing, FigureLook.lifeDot);
    disc(dot, FigureLook.lifeDot - 2);
    disc(ring, FigureLook.lifeAltSize);
    disc(ringInner, FigureLook.lifeAltSize - 2);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheetWidth * scale).ceil(), (_sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }

  var _transforms = Float32List(4 * 64), _rects = Float32List(4 * 64);
  var _colors = Int32List(64);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  void add(ui.Rect source, double cx, double cy, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = 1 / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = ((cx - source.width / 2) * s).roundToDouble() / s;
    _transforms[p + 3] = ((cy - source.height / 2) * s).roundToDouble() / s;
    _rects[p] = source.left * s;
    _rects[p + 1] = source.top * s;
    _rects[p + 2] = source.right * s;
    _rects[p + 3] = source.bottom * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }
}

/// 검사가 읽는 기록 하나(자리는 배치 px).
class FigureMark {
  FigureMark(this.kind, this.name, this.x, this.y, this.width, this.height, [this.lane = 0, this.alpha = 1]);
  final String kind, name;
  final int lane;
  final double x, y, width, height;

  /// 그때 색에 곱한 밝기(고르기 · 흐림).
  final double alpha;

  @override
  String toString() =>
      '$kind "$name" 단$lane [${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, ${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)}]${alpha == 1 ? '' : ' 밝기${alpha.toStringAsFixed(2)}'}';
}

/// 한 띠의 인물 단 — 보이는 막대의 평균 폭으로 나눠 그릴지('인물 n명' 한 칸으로) 묶을지 정한다.
class _Group {
  _Group(this.band, this.row, this.lo, this.hi, this.vlo, this.vhi);
  final int band, row;

  /// 띠 안쪽 4px(미정 꼬리 포함)의 가로 범위와, 그 가운데 화면에 보이는 부분.
  final double lo, hi, vlo, vhi;
  int count = 0;
  double total = 0;
  bool split = true;
  bool drawn = false;
}

/// 강조에 든 인물 막대의 테두리(css --warn).
const _matchEdge = 0xff000000;

class FigureLayer extends TileLayer {
  FigureLayer({BandSpans? spans}) : spans = spans ?? BandSpans();

  /// 띠의 가로 범위(기간 막대 층과 같은 것을 써도 된다).
  final BandSpans spans;
  final parts = FigureParts.shared;
  final _groups = <int, _Group>{};

  /// 밝기 상태(총괄이 장면에 넣기 전에는 중립).
  em.Emphasis? emphasis;
  static final em.Emphasis _neutral = em.Emphasis();

  em.Emphasis get _em => emphasis ?? _neutral;

  /// 고른 인물 · 손을 올린 인물의 **uid**(구역 37 `text2`의 첫 칸). 총괄이 채운다 —
  /// 구역 37의 `ref`는 막대가 든 띠라 사람을 가리키지 못하고, 지금 연표도 `data-uid`(인물 uid)로 고름을 가린다.
  String? pickedFigure, hoverFigure;

  /// 띠 번호 → 지난 장면에 나눠 그렸는가(문턱 둘 — 한 번 묶이면 8% 더 넓어져야 풀린다).
  final _wasSplit = <int, bool>{};

  /// 마지막 장면의 자리 기록(맞히기).
  final _spots = <_Spot>[];

  /// (띠 · 단 · 순번) → 이 장면의 이설 표식. 한 항목이 여러 타일에 실리므로 항목 번호로 합친다.
  final _alts = <int, List<(double, int)>>{};

  /// 이설(다른 견해) 표시를 켰는가(표시 상태의 [SceneMarks.showAlt]). 꺼 두면 막대 안의 세로 점선 ·
  /// 이름 밑 '이설 있음' 점선 · 생몰 이설의 빈 고리가 모두 없어진다
  /// (js/timeline.js 6449 `this.showAlt && !this._bird` · 6181 `alt: this.showAlt && !this._bird`).
  bool _showAlt = true;

  // 가문 표시(`show.houses`)는 이 층에 하는 일이 없다: 지금 연표에서 그 체크가 바꾸는 것은 **지도자 칸 밑의 가문 줄**
  // (`.tl-houseline` — js:6274 · 6310 · 6313, 칸 층의 몫)뿐이고, 인물 막대의 가문 짙기는 체크가 아니라
  // **가문 창이 연 가문**(js:6457 `f.houseId && f.houseId === this.house`)이 정한다 — 그것은 `_em.look.house`로 이미 온다
  // (D1 가문 · 성씨 조명이면 `_em.look.houses`까지 — `Look.isHouse`).

  static int _altKey(int band, int lane, int seq) => band << 12 | (lane & 0xf) << 8 | (seq & 0xff);

  @override
  void setScale(double scale) => parts.setScale(scale);

  @override
  void flush(PaintContext c) => parts.flush(c.canvas);

  @override
  void beginFrame(PaintContext c) {
    _showAlt = SceneMarks.of(c.scene).showAlt;
    spans.beginFrame();
    _groups.clear();
    _spots.clear();
    _alts.clear();
    if (c.hide.contains('figures')) return;
    // 조감에는 인물 단이 없다 — figMax = 0(명세 05의 7.1 · 7.2). 자동 조감도 같다.
    if (c.layout.conditions.bird) return;
    spans.ensure(c);
    // 메움 타일은 제 타일이 있으면 건너뛴다(같은 막대를 두 번 세지 않게).
    final own = {for (final d in c.scene.draw) if (!d.isCover) d.key};
    double threshold = FigureLook.denseWidth;
    int back = FigureLook.denseBack;
    for (final d in c.scene.draw) {
      if (d.isCover && own.contains(d.key)) continue;
      final t = d.tile;
      final bars = t.section(FigureLook.secBar);
      if (bars.count == 0) continue;
      final origin = t.origin.toDouble();
      final x0s = bars.f(Tile.itemX0), x1s = bars.f(Tile.itemX1);
      final rows = bars.u(Tile.itemRow), refs = bars.u(Tile.itemRef), lanes = bars.u(Tile.itemA);
      for (int i = 0; i < bars.count; i++) {
        final group = _groupOf(c, refs[i], rows[i]);
        if (group == null) continue;
        final geo = c.layout.geo(rows[i]);
        if (lanes[i] >= geo.figLevels) continue; // 이 밀도에서는 없는 단 — 지금 연표도 그리지 않는다
        final bar = _barOf(c, group, origin + x0s[i], origin + x1s[i]);
        if (bar == null) continue;
        group.count++;
        group.total += bar.$3;
      }
      // 묶는 문턱은 자료가 실어 보낸다(구역 38의 b · c).
      final groups = t.section(FigureLook.secGroup);
      if (groups.count > 0) {
        final b = groups.u(Tile.itemB), cc = groups.u(Tile.itemC);
        if (b[0] > 0) threshold = b[0].toDouble();
        if (cc[0] > 0) back = cc[0];
      }
    }
    for (final group in _groups.values) {
      final avg = group.count == 0 ? 0.0 : group.total / group.count;
      final was = _wasSplit[group.band] ?? false;
      // 지금 연표의 _past: 이미 나뉘어 있으면 문턱의 92%만 넘어도 그대로 나눠 둔다.
      group.split = group.count < 2 || avg >= (was ? threshold * (1 - back / 1000) : threshold);
      _wasSplit[group.band] = group.split;
    }
  }

  /// 그 띠의 인물 단(없으면 만든다). 줄이 보이지 않거나 인물 단이 없는 줄이면 null.
  _Group? _groupOf(PaintContext c, int band, int row) {
    final known = _groups[band];
    if (known != null) return known.row == row ? known : null;
    final layout = c.layout;
    if (row >= layout.rowCount || !layout.hasBody(row)) return null;
    final geo = layout.geo(row);
    if (geo.figTop < 0 || geo.figLevels <= 0) return null;
    final (lo, hi) = spans.screenSpan(c.v, band);
    final inLo = lo + FigureLook.inset, inHi = hi - FigureLook.inset;
    final vlo = math.max(inLo, c.left), vhi = math.min(inHi, c.w);
    if (vhi - vlo < FigureLook.minWidth) return null;
    return _groups[band] = _Group(band, row, inLo, inHi, vlo, vhi);
  }

  /// 막대 하나의 (왼쪽, 오른쪽, 빽빽함을 잴 폭). 띠의 기간 안으로 자르고 띠 안쪽에 가둔 뒤, 화면 밖이면 null.
  (double, double, double)? _barOf(PaintContext c, _Group group, double start, double end) {
    final v = c.v;
    final bandLo = spans.loOf(group.band), bandHi = spans.hiOf(group.band);
    final a = v.xOf(start < bandLo ? bandLo : start), b = v.xOf(end > bandHi ? bandHi : end);
    var la = a > group.lo ? a + .5 : group.lo;
    var rb = b < group.hi ? b - .5 : group.hi;
    if (rb - la < FigureLook.minWidth) {
      // 아주 짧은 활동도 3px은 보이게 — 구간의 가운데에 3px으로.
      la = ((a + b) / 2 - FigureLook.minWidth / 2).clamp(group.lo, math.max(group.lo, group.hi - FigureLook.minWidth));
      rb = la + FigureLook.minWidth;
    }
    if (rb <= group.vlo || la >= group.vhi) return null;
    // 1년이 안 되는 활동은 그 1년의 폭으로 센다 — 억지로 넓힌 3px만 세면 확대해도 영영 6px 아래라서.
    final short = end - start < FigureLook.yearMinutes;
    return (la, rb, short ? math.max(rb - la, FigureLook.yearMinutes * v.ppm) : rb - la);
  }

  @override
  void paintTile(PaintContext c, Tile t) {
    if (c.hide.contains('figures')) return;
    if (c.layout.conditions.bird) return;
    final bars = t.section(FigureLook.secBar), groups = t.section(FigureLook.secGroup);
    if (bars.count + groups.count == 0) return;
    spans.ensure(c);
    _gatherAlts(c, t);
    _paintBars(c, t, bars);
    _paintDense(c, t, groups);
  }

  /// 구역 39 — 활동 기록의 이설. 막대 하나마다 (띠 · 단 · 순번)으로 모아 둔다(`b`: 0 · 1 경계 · 4 생몰의 이설).
  void _gatherAlts(PaintContext c, Tile t) {
    if (!_showAlt) return; // '이설' 체크를 끄면 이 층의 표식이 모두 없어진다(모으지 않으면 [_ghosts]가 그릴 것이 없다)
    final s = t.section(FigureLook.secAlt);
    if (s.count == 0) return;
    final v = c.v, origin = t.origin.toDouble();
    final x0s = s.f(Tile.itemX0);
    final refs = s.u(Tile.itemRef), lanes = s.u(Tile.itemA), bits = s.u(Tile.itemB), seqs = s.u(Tile.itemC);
    for (int i = 0; i < s.count; i++) {
      final key = _altKey(refs[i], lanes[i], seqs[i]);
      final x = v.xOf(origin + x0s[i]);
      final list = _alts[key] ??= <(double, int)>[];
      if (list.any((q) => (q.$1 - x).abs() < .01 && q.$2 == bits[i])) continue; // 여러 타일에 실린 같은 표식
      list.add((x, bits[i]));
    }
  }

  void _paintBars(PaintContext c, Tile t, TileSection s) {
    if (s.count == 0) return;
    final v = c.v, layout = c.layout, origin = t.origin.toDouble(), left = c.left, w = c.w;
    final x0s = s.f(Tile.itemX0), x1s = s.f(Tile.itemX1);
    final rows = s.u(Tile.itemRow), refs = s.u(Tile.itemRef), colors = s.u(Tile.itemColor), names = s.u(Tile.itemName);
    final lanes = s.u(Tile.itemA), bits = s.u(Tile.itemB), seqs = s.u(Tile.itemC), texts = s.u(Tile.itemText2);
    final houseLook = _em.look;
    for (int i = 0; i < s.count; i++) {
      final row = rows[i];
      final group = _groups[refs[i]];
      if (group == null || !group.split || group.row != row) continue;
      final geo = layout.geo(row);
      final (stripTop, stripHeight) = geo.strip(6, lanes[i]);
      if (stripTop < 0) continue;
      final top = v.yOf(layout.rowTop(row) + stripTop);
      if (!c.rowOnScreen(row, top, stripHeight)) continue;
      final bar = _barOf(c, group, origin + x0s[i], origin + x1s[i]);
      if (bar == null) continue;
      final (la, rb, _) = bar;
      final l = math.max(la, left), width = math.min(rb, w) - math.max(la, left);
      if (width < 1) continue;
      final right = l + width;
      // text2 = 인물uid|생분|몰분|가문id(계약 6-7 가).
      final life = t.text(texts[i]).split('|');
      final uid = life.isNotEmpty ? life[0] : '';
      final mine = uid.isNotEmpty && (uid == pickedFigure || uid == hoverFigure);
      // 가문 조명(D1 결정 7 A)이면 누른 가문과 아래 파 · 성씨 조명이면 그 성의 가문 모두(Look.houses) — 웹 setHouse(ids)의 is-house와 같다.
      // houses가 없는 옛 꼴은 지금처럼 가문 창이 연 가문 하나(Look.house).
      final ofHouse = life.length > 3 && houseLook.isHouse(life[3]);
      // 강조에 든 인물(검색 결과 · 창의 강조 — css:1385 `.tl-fig.is-match`)은 테두리가 --warn이다.
      final matched = _em.look.matchedUid(uid);
      // 다른 것을 고른 동안 인물 막대는 .5(css:1383 — 띠 · 사건의 .58 · .45와 다른 값이다) · 강조 밖은 .2(css:1384)로 옅어진다.
      // 강조가 고르기를 덮는다(css에서 1384가 1383보다 뒤) — 고른 인물이라도 강조 밖이면 .2다.
      final alpha = _em.markAlpha(mine: mine, matched: matched, pick: em.Dim.figPick, dim: em.Dim.figDim);
      final color = 0xff000000 | colors[i], importance = math.max(1, bits[i] & 3);
      // 올림 · 고름은 c 55% · 가문 강조는 c 42%(css:1372 · 1452) — 둘 다 테두리가 --edge다.
      final mix = mine ? .55 : (ofHouse ? .42 : (importance >= 3 ? .42 : (importance == 1 ? .18 : .30)));
      final fill = withAlpha(mixSrgb(color, Look.paper, mix), alpha);
      final border = withAlpha(matched ? _matchEdge : (mine || ofHouse || importance >= 3 ? RailLook.edge(colors[i]) : RailLook.edgeSoft(colors[i])), alpha);
      final ink = mine ? Look.ink : (importance == 1 ? mixSrgb(color, Look.muted, .30) : mixSrgb(color, Look.ink, .35));
      final thin = width < FigureLook.thin;
      final radius = thin ? FigureLook.thinRadius : FigureLook.radius;
      final cutL = la < left, cutR = rb > w;
      // 이름: 온 이름 → 첫 글자 → 없음. 폭은 새 엔진의 진짜 글자 폭으로 다시 잰다.
      final look = FigureLook.name(importance, withAlpha(ink, alpha));
      final full = t.text(names[i]);
      var label = '';
      double textWidth = 0;
      if (full.isNotEmpty && !thin) {
        final measured = c.text.widthOf(full, look);
        if (measured != null) {
          if (width >= measured + FigureLook.fitName) {
            label = full;
            textWidth = measured;
          } else {
            final first = full.substring(0, 1);
            final firstWidth = c.text.widthOf(first, look);
            if (firstWidth != null && width >= firstWidth + FigureLook.fitFirst) {
              label = first;
              textWidth = firstWidth;
            }
          }
        }
      }
      // 미정 끝: 그쪽이 막대 안에서 옅어진다(화면에서 잘린 쪽은 미정으로 치지 않는다).
      // 고르거나 올리면 가림을 거둔다 — 막대 밖으로 뻗는 수명선이 잘리지 않게(css:1668).
      double fade = 0;
      if (width >= FigureLook.thin && !mine) {
        fade = math.max(FigureLook.fadeMin, math.min(FigureLook.fadeMax, math.min(width * FigureLook.fadeOfWidth, label.isEmpty ? width * FigureLook.fadeNoName : (width - textWidth) / 2)));
      }
      final fadeL = bits[i] & 4 != 0 && !cutL && width >= FigureLook.thin ? fade : 0.0;
      final fadeR = bits[i] & 8 != 0 && !cutR && width >= FigureLook.thin ? fade : 0.0;
      _box(c, l, top, right, top + stripHeight, radius, fill, border, roundL: !cutL, roundR: !cutR, fadeL: fadeL, fadeR: fadeR, dottedL: cutL, dottedR: cutR);
      c.stats.shapes++;
      // 가문 강조 · 고름의 안쪽 테(inset 0 0 0 1.5px var(--edge)) — 칸과 같은 말(css:1452).
      if (ofHouse || mine) _inset(c, l, top, right, top + stripHeight, withAlpha(RailLook.edge(colors[i]), alpha));
      _spots.add(_Spot(FigureHit(band: refs[i], row: row, figure: uid, lane: lanes[i]), l, top, right, top + stripHeight));
      c.debug?.note('인물', FigureMark('인물', full, l, top, width, stripHeight, lanes[i], alpha));
      if (ofHouse) c.debug?.note('가문인물', FigureMark('가문인물', full, l, top, width, stripHeight, lanes[i], alpha));
      _lifeLine(c, group, life, l, right, top, stripHeight, colors[i], mine, cutL: la < left, cutR: rb > w);
      _ghosts(c, refs[i], lanes[i], seqs[i], l, right, top, stripHeight, colors[i], alpha, label.isNotEmpty ? textWidth : 0, mine);
      if (label.isEmpty) continue;
      c.later.add('fig', label, look, l + (width - textWidth) / 2, top + (stripHeight - look.size * 1.2) / 2, alpha);
    }
  }

  /// 안쪽 1.5px 테(가문 강조 · 고름). 네 변을 네모 묶음으로 — 둥근 모서리에는 두지 않는다(css의 inset box-shadow는 모서리를 따라가지만 1.5px이라 눈에 띄지 않는다).
  void _inset(PaintContext c, double l, double t, double r, double b, int argb) {
    const k = 1.5;
    if (r - l < k * 2 || b - t < k * 2) return;
    c.quads.add(l + 1, t + 1, r - 1, t + 1 + k, argb);
    c.quads.add(l + 1, b - 1 - k, r - 1, b - 1, argb);
    c.quads.add(l + 1, t + 1 + k, l + 1 + k, b - 1 - k, argb);
    c.quads.add(r - 1 - k, t + 1 + k, r - 1, b - 1 - k, argb);
  }

  /// 수명선 `.ln`과 끝 점 · 생몰 이설의 빈 고리 `.lnalt` — 고르거나 올렸을 때만(명세 03의 2.5).
  /// 자리는 `text2`의 생몰 분이고, 막대 밖으로 2px 넘게 나갈 때만 긋는다. 띠 · 화면에서 잘리지 않은 끝에만 끝 점을 찍는다.
  void _lifeLine(PaintContext c, _Group group, List<String> life, double l, double right, double top, double height, int color, bool mine, {required bool cutL, required bool cutR}) {
    if (!mine) return;
    final v = c.v;
    final birth = life.length > 1 ? double.tryParse(life[1]) : null;
    final death = life.length > 2 ? double.tryParse(life[2]) : null;
    final edge = withAlpha(RailLook.edge(color), FigureLook.lifeAlpha);
    final ls = (birth != null ? v.xOf(birth) : l).clamp(group.vlo, group.vhi);
    final le = (death != null ? v.xOf(death) : right).clamp(group.vlo, group.vhi);
    // 선은 막대의 세로 가운데(css의 top: 50% — 테두리 안쪽 상자의 절반). 끝 점은 그보다 0.5px 위다(margin-top −2.5 + 4px).
    final mid = top + 1 + (height - 2) / 2;
    if (ls < l - FigureLook.lifeShow) {
      c.quads.add(ls, mid, l, mid + 1, edge);
      c.stats.shapes++;
      c.debug?.note('수명선', FigureMark('수명선', life[0], ls, mid, l - ls, 1));
      if (ls > group.vlo && !cutL) {
        parts.add(FigureParts.dotRing, ls, mid - .5, edge);
        parts.add(FigureParts.dot, ls, mid - .5, withAlpha(Look.paper, FigureLook.lifeAlpha));
        c.debug?.note('수명선끝', FigureMark('수명선끝', life[0], ls, mid - .5, FigureLook.lifeDot, FigureLook.lifeDot));
      }
    }
    if (le > right + FigureLook.lifeShow) {
      c.quads.add(right, mid, le, mid + 1, edge);
      c.stats.shapes++;
      c.debug?.note('수명선', FigureMark('수명선', life[0], right, mid, le - right, 1));
      if (le < group.vhi && !cutR) {
        parts.add(FigureParts.dotRing, le, mid - .5, edge);
        parts.add(FigureParts.dot, le, mid - .5, withAlpha(Look.paper, FigureLook.lifeAlpha));
        c.debug?.note('수명선끝', FigureMark('수명선끝', life[0], le, mid - .5, FigureLook.lifeDot, FigureLook.lifeDot));
      }
    }
  }

  /// 구역 39 — 활동 기록의 이설. 경계(`b` 0 · 1)는 막대 안의 세로 점선, 생몰의 이설(`b` 4)은 수명선 위의 빈 고리.
  /// 막대 안에 그을 자리가 없으면(끝에서 3px 안 · 이름 글자와 겹침) 이름 밑 가로 점선 하나로 갈음한다(`.is-has`).
  void _ghosts(PaintContext c, int band, int lane, int seq, double l, double right, double top, double height, int color, double alpha, double textWidth, bool mine) {
    final list = _alts[_altKey(band, lane, seq)];
    if (list == null || list.isEmpty) return;
    final gc = withAlpha(RailLook.edgeSoft(color), FigureLook.ghostMix * alpha);
    final mid = (l + right) / 2, half = textWidth / 2 + 2;
    var drawn = false, wanted = false;
    for (final (x, bit) in list) {
      if (bit & 4 != 0) {
        // 생몰의 이설: 고르거나 올렸을 때만 · 띠 안쪽에서 · 막대에서 3px 넘게 떨어진 자리에만.
        if (!mine) continue;
        if (x < l - FigureLook.lifeAltGap || x > right + FigureLook.lifeAltGap) {
          final my = top + 1 + (height - 2) / 2;
          parts.add(FigureParts.ring, x, my, withAlpha(RailLook.edge(color), FigureLook.lifeAlpha));
          parts.add(FigureParts.ringInner, x, my, withAlpha(Look.paper, FigureLook.lifeAlpha));
          c.stats.shapes++;
          c.debug?.note('생몰이설', FigureMark('생몰이설', '', x, my, FigureLook.lifeAltSize, FigureLook.lifeAltSize, lane));
        }
        continue;
      }
      wanted = true;
      if (x < l + FigureLook.ghostEdge || x > right - FigureLook.ghostEdge) continue;
      if (textWidth > 0 && (x - mid).abs() < half) continue; // 이름 글자 위는 비운다
      c.quads.vLine(x, top + FigureLook.ghostInset, top + height - FigureLook.ghostInset, gc, dash: FigureLook.ghostDash, gap: FigureLook.ghostGap, phase: top + FigureLook.ghostInset);
      c.stats.shapes++;
      drawn = true;
      c.debug?.note('활동이설', FigureMark('활동이설', '', x, top, 1, height, lane));
    }
    // 선을 하나도 긋지 못한 막대는 이름 밑에 같은 점의 가로 점선(`.tl-calt.is-has`).
    if (wanted && !drawn && textWidth > 0) {
      c.quads.hLine(mid - textWidth / 2, mid + textWidth / 2, top + height - FigureLook.ghostInset - 1, gc, dash: FigureLook.ghostDash, gap: FigureLook.ghostGap, phase: mid - textWidth / 2);
      c.debug?.note('활동이설', FigureMark('이설있음', '', mid - textWidth / 2, top, textWidth, 1, lane));
    }
  }

  /// 구역 38 — 빽빽하면 단 전체가 '인물 n명' 한 칸(점선 테두리 + 옅은 세로 결).
  void _paintDense(PaintContext c, Tile t, TileSection s) {
    if (s.count == 0) return;
    final v = c.v, layout = c.layout;
    final rows = s.u(Tile.itemRow), refs = s.u(Tile.itemRef), colors = s.u(Tile.itemColor);
    for (int i = 0; i < s.count; i++) {
      final group = _groups[refs[i]];
      if (group == null || group.split || group.drawn || group.row != rows[i]) continue;
      final geo = layout.geo(rows[i]);
      final (stripTop, stripHeight) = geo.strip(6, 0);
      if (stripTop < 0) continue;
      final top = v.yOf(layout.rowTop(rows[i]) + stripTop);
      if (!c.rowOnScreen(rows[i], top, stripHeight)) continue;
      group.drawn = true;
      final l = group.vlo, r = group.vhi, bottom = top + stripHeight;
      final color = 0xff000000 | colors[i];
      // 다른 것을 고른 동안은 인물 막대와 같은 .5 · 강조 밖은 .2(css:1383 · 1384는 `.tl-fig` 전체에 걸린다 — 한 칸도 `.tl-fig.is-dense`다).
      // 모아 놓은 칸에는 제 uid가 없어 늘 `is-dim`이다.
      final alpha = _em.markAlpha(mine: false, matched: false, pick: em.Dim.figPick, dim: em.Dim.figDim);
      final soft = withAlpha(RailLook.edgeSoft(colors[i]), alpha);
      // 바탕: 종이색 60% 위에 제 색 16%의 옅은 세로 결.
      c.quads.add(l, top, r, bottom, withAlpha(Look.paper, .6 * alpha));
      c.patterns.add(FigureLook.densePattern, l, top, r, bottom, withAlpha(color, .16 * alpha), phaseX: l, phaseY: top);
      // 테두리: 1px 파선 네 변(둥근 모서리 자리는 비운다).
      final radius = FigureLook.radius;
      dashRow(c.quads, l + radius, r - radius, top, 1, soft, dash: RailLook.lineDash, gap: RailLook.lineGap, phase: l);
      dashRow(c.quads, l + radius, r - radius, bottom - 1, 1, soft, dash: RailLook.lineDash, gap: RailLook.lineGap, phase: l);
      dashColumn(c.quads, l, top + radius, bottom - radius, 1, soft, dash: RailLook.lineDash, gap: RailLook.lineGap, phase: top);
      dashColumn(c.quads, r - 1, top + radius, bottom - radius, 1, soft, dash: RailLook.lineDash, gap: RailLook.lineGap, phase: top);
      c.stats.shapes++;
      final label = '인물 ${group.count}명';
      final look = TextLook(10, ui.FontWeight.w500, withAlpha(CanvasInk.of(Look.muted), alpha), spacing: FigureLook.spacing, wght: 500);
      final width = c.text.widthOf(label, look);
      // 누르면 그 띠(정권) 상세의 인물 목록으로 간다(지금 연표의 data-cell="figures").
      _spots.add(_Spot(FigureHit(band: refs[i], row: rows[i], group: true, count: group.count), l, top, r, bottom));
      c.debug?.note('인물묶음', FigureMark('인물묶음', label, l, top, r - l, stripHeight, 0, alpha));
      if (width == null || r - l < width + FigureLook.fitName) continue;
      c.later.add('fig', label, look, l + (r - l - width) / 2, top + (stripHeight - look.size * 1.2) / 2, alpha);
    }
  }

  /// 마지막으로 그린 장면에서 [x] · [y](배치 px)에 있는 인물 막대 또는 '인물 n명' 한 칸. 없으면 null.
  FigureHit? hitFigures(double x, double y) {
    for (int i = _spots.length - 1; i >= 0; i--) {
      final s = _spots[i];
      if (x < s.x0 || x > s.x1 || y < s.y0 || y > s.y1) continue;
      return s.hit;
    }
    return null;
  }

  /// 테두리 1px이 있는 둥근 칸. 바깥을 테두리 색으로 깔고 안쪽 1px을 채움 색으로 덮는다 —
  /// 칸마다 둥근 네모를 따로 그리면(drawRRect) 하나하나가 따로 처리되므로, 모서리는 조각 · 몸통은 네모 묶음으로 모은다.
  void _box(PaintContext c, double l, double t, double r, double b, double radius, int fill, int border,
      {bool roundL = true, bool roundR = true, double fadeL = 0, double fadeR = 0, bool dottedL = false, bool dottedR = false}) {
    _roundRect(c, l, t, r, b, radius, border, roundL, roundR, fadeL, fadeR);
    _roundRect(c, l + (dottedL ? 0 : 1), t + 1, r - (dottedR ? 0 : 1), b - 1, radius - 1, fill, roundL, roundR, math.max(0, fadeL - 1), math.max(0, fadeR - 1));
    // 화면 끝에서 잘린 쪽의 테두리는 점선(css의 border-left-style: dotted).
    if (dottedL) dashColumn(c.quads, l, t, b, 1, border, dash: RailLook.dotDash, gap: RailLook.dotGap, phase: t);
    if (dottedR) dashColumn(c.quads, r - 1, t, b, 1, border, dash: RailLook.dotDash, gap: RailLook.dotGap, phase: t);
  }

  void _roundRect(PaintContext c, double l, double t, double r, double b, double radius, int argb, bool roundL, bool roundR, double fadeL, double fadeR) {
    if (r <= l || b <= t) return;
    final clear = argb & 0x00ffffff;
    final left = l + fadeL, right = r - fadeR;
    final roundLeft = roundL && fadeL <= 0, roundRight = roundR && fadeR <= 0;
    final rad = math.max(0.0, math.min(radius, math.min((right - left) / (roundLeft && roundRight ? 2 : 1), (b - t) / 2)));
    final size = rad / Sprites.cornerRadius;
    var bodyL = left, bodyR = right;
    // 미정 끝: 44px까지의 꼬리가 바탕으로 스며든다(css의 mask-image와 같은 말).
    if (fadeL > 0) c.quads.addFade(l, t, left, b, clear, argb);
    if (fadeR > 0) c.quads.addFade(right, t, r, b, argb, clear);
    if (roundLeft && rad > 0) {
      c.sprites.add(Sprites.cornerTopLeft, left, t, argb, size);
      c.sprites.add(Sprites.cornerBottomLeft, left, b - rad, argb, size);
      c.quads.add(left, t + rad, left + rad, b - rad, argb);
      bodyL = left + rad;
    }
    if (roundRight && rad > 0) {
      c.sprites.add(Sprites.cornerTopRight, right - rad, t, argb, size);
      c.sprites.add(Sprites.cornerBottomRight, right - rad, b - rad, argb, size);
      c.quads.add(right - rad, t + rad, right, b - rad, argb);
      bodyR = right - rad;
    }
    if (bodyR > bodyL) c.quads.add(bodyL, t, bodyR, b, argb);
  }
}
