import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../marks.dart';
import '../ruler.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import '../viewport.dart';
import 'context.dart';
import 'look.dart';
import 'paint_pick.dart';
import 'patterns.dart';

// 기간 사건의 막대와 표식: 가는 선 · 양 끝 세로바 · 연대 폭 · 이설 · 조약 발효(구역 33~36).
// 지금 연표의 `.tl-rail` · `.tl-fuzz` · `.tl-alt` · `.tl-altline` · `.tl-thread` · `.tl-edge` · `.tl-bead` · `.tl-eff`을 옮긴 것이다
// (js/timeline.js 7062~7130 · css/common.css 359~370 · 829~861 · 1484~1490, 명세 docs/명세-3단계/03-띠에-덧붙는-것.md 1절).
//
// 막대로 그릴지 구슬로 그릴지는 **화면 폭**이 정한다(`X(끝) − X(시작) > 2`) — 날수가 아니다. 그래서 확대하면 하루짜리도 막대가 되고
// 축소하면 천 년짜리도 '점선 실에 꿴 구슬'이 된다. 단(0~2)은 자료가 정해 실어 보낸 값(구역 33~36의 `a`)을 그대로 쓴다(계약 6-6절).
// 0.1.1(스위치 route — 조사 결함 49): 6px보다 좁은 막대(3px 막대 + 6px 세로바의 'H' 꼴)는 막대 대신 시작 자리의 구슬 하나로 그린다([_Ev.single]).
// 단이 모자라 이웃 막대가 같은 단에 붙는 몫은 그대로다(단 수는 배치 몫 · 구슬로 줄이면 기간이 사라진다).
//
// 모든 도형은 묶음에 모은다: 막대 몸통 · 세로바 · 눈금 · 점선은 `c.quads`, 연대 폭의 빗금은 `c.patterns`,
// 구슬과 발효 마름모는 이 파일의 작은 그림판(`RailParts`)에 모아 층의 flush에서 한 번에 찍는다.

/// 기간 막대 칸의 값(지금 연표의 css에서 옮긴 것).
abstract final class RailLook {
  /// 단 사이 7px · 첫 단은 줄의 railTop + 3.5(G.railPitch).
  static const pitch = 7.0, offset = 3.5;

  /// 가는 선의 높이 2 · 조약의 겹줄 4(위아래 1px 두 줄) · 양 끝 세로바 1.5 × 6.
  static const body = 2.0, treaty = 4.0, cap = 1.5, capHeight = 6.0;

  /// 막대의 최소 폭 3px · 막대로 그리는 화면 폭 문턱 2px · 제 띠 안쪽으로 가두는 여백 5px.
  static const minWidth = 3.0, rangedPx = 2.0, inset = 5.0;

  /// 스위치 route(0.1.1 · 조사 결함 49)의 막대 문턱: 이보다 좁은 막대는 막대 + 세로바(3px 막대 + 6px 세로바 = 'H' 꼴) 대신 구슬 하나로.
  static const narrowPx = 6.0;

  /// 연대 폭(빗금 구간)의 높이 5 · 최소 폭 2.
  static const fuzzHeight = 5.0, fuzzMinWidth = 2.0;

  /// 이설 세로바 1.5 × 9 · 통설의 세로바와 4px 안이면 4px 바깥으로 비킨다.
  static const altWidth = 1.5, altHeight = 9.0, altNudge = 4.0;

  /// 구슬 6px · 6px 안이면 합친다. 실은 3px 미만이면 그리지 않는다.
  static const bead = 6.0, beadMerge = 6.0, threadMin = 3.0;

  /// 발효 마름모: 4 × 4를 45° 돌린 것(외접 네모 5.66) · 막대의 양 끝에서 3px보다 안쪽일 때만.
  /// 종이색 테는 css의 `box-shadow: 0 0 0 1px`인데, 그림자는 **돌리기 전 네모**에 붙으므로 6 × 6을 돌린 크기(8.49)가 된다
  /// — 기준 그림에서도 마름모 둘레로 8px이 밝다.
  static const effect = 5.657, effectRing = 8.485, effectInset = 3.0;

  /// 끊어 그리는 무늬: 공동 사건의 파선(4 켜고 3 끔) · 이설 세로바(2/2) · 실의 점선(1/1) · css의 1px dashed(주기 5 — Edge에서 잰 값).
  static const pairDash = 4.0, pairGap = 3.0, altDash = 2.0, altGap = 2.0, dotDash = 1.0, dotGap = 1.0, lineDash = 3.5, lineGap = 1.5;

  /// 135°로 3px 긋고 6px마다 되풀이하는 빗금(연대 폭).
  static const fuzzPattern = PatternSpec.stripes(135, 3, 6);

  /// 구역 번호(계약 6-7절). 32는 하위 사건의 부모 기간 — 접힌 자식의 막대는 그리지 않으려고 읽기만 한다.
  static const secChild = 32, secRail = 33, secFuzz = 34, secAlt = 35, secEffect = 36;

  /// 하위 사건을 펼치는 문턱(부모 기간의 화면 폭 px)과 되돌림(천분율) — 자료가 실어 보내지 않으면 이 값.
  static const openWidth = 90.0, openBack = 80;

  /// 배율마다 단을 다시 고를 때 xs의 양옆에 더하는 여유(js/timeline.js 7072의 `Math.min(...xs) − 4`).
  static const pickPad = 4.0;

  /// 고르거나 올렸을 때 막대 둘레의 빛(`box-shadow: 0 0 0 1.5px color-mix(edge 30%, transparent)`).
  static const glow = 1.5, glowMix = .3;

  /// 구슬 위 연도(`.tl-bead::after`): 9px · 굵기 600 · 구슬 상자 아래에서 6px 위 — 고르거나 올렸을 때만.
  static const beadYearSize = 9.0, beadYearGap = 6.0;

  /// 막대를 누를 때 위아래로 잡는 여유(hit_test.dart의 barGrab과 같은 값).
  static const grab = 5.0;

  /// `--edge`(양 끝 세로바 · 이설 · 구슬 테 · 발효) · `--edge-soft`(막대 몸통 · 실 · 눈금 · 구슬 안)의 css 식.
  static int edge(int color) => mixOklab(0xff000000 | color, Look.ink, .84);
  static int edgeSoft(int color) => mixOklab(0xff000000 | color, Look.ink, .92);
}

/// 맞히기(총괄이 잇는다): 마지막으로 그린 장면에서 기간 막대 칸의 무엇이 그 자리에 있었는가.
enum RailPart { bar, bead, alt, effect }

class RailHit {
  const RailHit(this.part, this.eventId, this.band, this.row, this.lane);
  final RailPart part;

  /// 사건 번호 · 그 사건이 든 띠의 번호(모르면 0) · 줄 · 단.
  final int eventId, band, row, lane;

  @override
  String toString() => '${part.name}#$eventId 띠$band 줄$row 단$lane';
}

/// 마지막 장면의 자리 기록 하나(배치 px — 맞히기가 훑는다).
class _Spot {
  _Spot(this.part, this.eventId, this.band, this.row, this.lane, this.x0, this.x1, this.y, this.grab);
  final RailPart part;
  final int eventId, band, row, lane;
  final double x0, x1, y, grab;
}

/// 검사가 읽는 기록 하나(자리는 배치 px).
class RailMark {
  RailMark(this.kind, this.eventId, this.x, this.y, this.width, this.height, [this.lane = 0, this.alpha = 1]);
  final String kind;
  final int eventId, lane;
  final double x, y, width, height;

  /// 그때 색에 곱한 밝기(고르기 · 흐림).
  final double alpha;

  @override
  String toString() =>
      '$kind#$eventId 단$lane [${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, ${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)}]${alpha == 1 ? '' : ' 밝기${alpha.toStringAsFixed(2)}'}';
}

/// 한 장면에 그리는 타일들에서 모은 띠의 가로 범위(세계 분). 기간 막대와 인물 막대는 제 띠 안에 갇히므로 띠의 양 끝이 있어야 한다.
/// 타일 경계에서 잘린 쪽은 진짜 끝을 모르니 막지 않는다(label_batch.dart의 `_findBand`와 같은 규칙) — 여러 타일에 걸친 띠는 이어 붙여 본다.
class BandSpans {
  final _lo = <int, double>{}, _hi = <int, double>{};
  final _fade = <int, int>{};

  /// 줄 → [시작, 끝, 띠 번호] 셋씩(타일 조각 그대로 — 자리로 띠를 찾는 데만 쓴다).
  final _rows = <int, List<double>>{};
  bool _ready = false;

  /// 장면의 처음에 한 번: 다음에 쓸 때 다시 모은다.
  void beginFrame() => _ready = false;

  /// 이번 장면에서 아직 모으지 않았으면 모은다(쓰는 층이 없으면 셈하지 않는다).
  void ensure(PaintContext c) {
    if (_ready) return;
    _ready = true;
    _lo.clear();
    _hi.clear();
    _fade.clear();
    _rows.clear();
    for (final d in c.scene.draw) {
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        final id = t.bandId[i], flags = t.bandFlags[i];
        final lo = origin + t.bandX0[i], hi = origin + t.bandX1[i];
        if (flags & Tile.clipLeft == 0 && lo < (_lo[id] ?? double.infinity)) _lo[id] = lo;
        if (flags & Tile.clipRight == 0 && hi > (_hi[id] ?? double.negativeInfinity)) _hi[id] = hi;
        _fade[id] = (_fade[id] ?? 0) | (flags & Tile.fuzzyStart != 0 ? 1 : 0) | (flags & Tile.fuzzyEnd != 0 ? 2 : 0);
        (_rows[t.bandRow[i]] ??= <double>[]).addAll([lo, hi, id.toDouble()]);
      }
    }
  }

  /// 그 줄에서 [lo]~[hi](세계 분)에 걸치는 띠의 번호(없으면 0). 품은 띠가 먼저이고, 없으면 겹치는 첫 띠다 —
  /// 막대의 표식은 띠 밖으로 나가 있을 수 있어서(가두기 전) 품기만으로는 제 띠를 놓친다.
  int idAt(int row, double lo, [double? hi]) {
    final list = _rows[row];
    if (list == null) return 0;
    final end = hi ?? lo, mid = (lo + end) / 2;
    for (int i = 0; i < list.length; i += 3) {
      if (mid >= list[i] && mid <= list[i + 1]) return list[i + 2].toInt();
    }
    for (int i = 0; i < list.length; i += 3) {
      if (end >= list[i] && lo <= list[i + 1]) return list[i + 2].toInt();
    }
    return 0;
  }

  /// 띠의 시작 · 끝(세계 분). 모르면 ∓무한.
  double loOf(int id) => _lo[id] ?? double.negativeInfinity;
  double hiOf(int id) => _hi[id] ?? double.infinity;

  /// 1 시작 미정 · 2 끝 미정(미정 쪽은 44px 꼬리만큼 넓게 본다 — 지금 연표의 bandBounds와 같다).
  int fadeOf(int id) => _fade[id] ?? 0;

  /// 띠가 화면에서 차지하는 가로 범위(미정 꼬리 포함). 띠를 모르면 (−무한, +무한).
  (double, double) screenSpan(SceneView v, int id) {
    final lo = loOf(id), hi = hiOf(id), fade = fadeOf(id);
    return (
      lo.isFinite ? v.xOf(lo) - (fade & 1 != 0 ? Look.fuzzyFade : 0) : double.negativeInfinity,
      hi.isFinite ? v.xOf(hi) + (fade & 2 != 0 ? Look.fuzzyFade : 0) : double.infinity,
    );
  }
}

/// 제 띠 안쪽 [margin]px에 가둔다(지금 연표의 `inside(e, x, m)` — 띠가 그보다 좁으면 띠 한가운데).
double clampInside(double x, double lo, double hi, double margin) {
  final l = lo + margin, h = hi - margin;
  if (h <= l) return (lo + hi) / 2;
  return x < l ? l : (x > h ? h : x);
}

/// 가로 점선 · 파선. 정수 px에 맞추지 않는다 — 지금 연표도 소수 자리(785.5 …)에 그린다.
/// [phase]는 무늬가 시작하는 자리(요소의 제 왼쪽 끝 — css의 background-position 0과 같다).
void dashRow(Quads q, double x0, double x1, double top, double height, int argb, {double dash = 0, double gap = 0, double phase = 0}) {
  if (dash <= 0) {
    if (x1 > x0) q.add(x0, top, x1, top + height, argb);
    return;
  }
  final period = dash + gap;
  var x = x0 - ((x0 - phase) % period + period) % period;
  for (; x < x1; x += period) {
    final a = x < x0 ? x0 : x, b = x + dash > x1 ? x1 : x + dash;
    if (b > a) q.add(a, top, b, top + height, argb);
  }
}

/// 세로 점선 · 파선(같은 규칙).
void dashColumn(Quads q, double left, double y0, double y1, double width, int argb, {double dash = 0, double gap = 0, double phase = 0}) {
  if (dash <= 0) {
    if (y1 > y0) q.add(left, y0, left + width, y1, argb);
    return;
  }
  final period = dash + gap;
  var y = y0 - ((y0 - phase) % period + period) % period;
  for (; y < y1; y += period) {
    final a = y < y0 ? y0 : y, b = y + dash > y1 ? y1 : y + dash;
    if (b > a) q.add(left, a, left + width, b, argb);
  }
}

/// 이 층의 작은 그림판: 구슬(채운 것 · 빈 고리)과 발효 마름모. 흰색으로 한 번 그려 두고 찍을 때 색을 입힌다.
/// `scene/sprites.dart`의 방식을 본떴지만 그 파일은 고치지 않는다(공용) — 새 조각은 제 층에 둔다.
///
/// 조각은 **쓸 크기 그대로** 그려 둔다(줄여 찍지 않는다): 16px 동그라미를 3.5px으로 줄여 찍었더니
/// 안쪽 몇 점만 집혀 네모로 보였다 — 줄이지 않으면 그림판의 가장자리가 그대로 살아난다.
class RailParts {
  RailParts._(this._image, this._scale);
  ui.Image _image;
  double _scale;

  /// 조각 하나의 칸(1배 px)과 그 안에 그린 모양의 크기.
  static const cell = 12.0;
  static const bead = ui.Rect.fromLTWH(0, 0, cell, cell); // 6px 동그라미(구슬 바깥)
  static const beadInner = ui.Rect.fromLTWH(cell, 0, cell, cell); // 4px(통설 구슬의 안)
  static const beadAltInner = ui.Rect.fromLTWH(cell * 2, 0, cell, cell); // 3.5px(이설 고리의 안 — 테 1.25)
  static const diamond = ui.Rect.fromLTWH(cell * 3, 0, cell, cell); // 4px 네모를 45° 돌린 것
  static const diamondRing = ui.Rect.fromLTWH(cell * 4, 0, cell, cell); // 그 둘레의 종이색 1px 테
  static const _sheetWidth = cell * 5, _sheetHeight = cell;

  static RailParts? _shared;
  static RailParts get shared => _shared ??= RailParts._(_render(1), 1);

  double get scale => _scale;

  /// 멎은 돋보기 배율이 바뀌면 그 배율로 다시 뜬다(작아서 싸다).
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
    void rhombus(ui.Rect at, double size) {
      final c = at.center, r = size / 2;
      canvas.drawPath(
        ui.Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close(),
        white,
      );
    }

    disc(bead, RailLook.bead);
    disc(beadInner, RailLook.bead - 2);
    disc(beadAltInner, RailLook.bead - 2.5);
    rhombus(diamond, RailLook.effect);
    rhombus(diamondRing, RailLook.effectRing);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheetWidth * scale).ceil(), (_sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }

  var _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  var _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 조각 하나를 가운데 자리 [cx] · [cy]에 제 크기 그대로 찍는다.
  void add(ui.Rect source, double cx, double cy, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = 1 / s;
    _transforms[p + 1] = 0;
    // 화면 px에 맞춰 찍는다 — 소수 자리에 찍으면 조각이 두 점에 걸쳐 흐려진다(숫자 조각과 같은 규칙).
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

/// 배율마다 단을 다시 고르려고 모으는 사건 하나(js/timeline.js의 pickLevel이 보는 값).
/// `lo`~`hi`는 그 사건의 그림이 통틀어 차지하는 화면 범위(막대 · 연대 폭 · 이설 · 구슬)에 좌우 4px을 더한 것이다.
class _Cand {
  _Cand(this.id, this.row, this.importance, this.rank);
  final int id, row, importance, rank;
  double lo = double.infinity, hi = double.negativeInfinity;

  /// 막대로 그리는가(화면 폭 2px) · 이 사건에 기간 막대 칸에 그릴 것이 하나라도 있는가.
  bool ranged = false, any = false;

  void grow(double a, double b) {
    if (a < lo) lo = a;
    if (b > hi) hi = b;
  }
}

/// 한 사건의 기간 막대 칸 — 막대와 곁들임(연대 폭 · 이설 · 발효)이 같은 자리 셈을 나눠 쓴다.
class _Ev {
  _Ev(this.row, this.lane, this.y, this.color, this.lo, this.hi, this.ranged, this.rx, this.rx2, this.mainX);
  final int row, lane, color;
  final double y, lo, hi;

  /// 막대로 그리는가(화면 폭 2px 문턱). 아니면 '점선 실에 꿴 구슬'.
  final bool ranged;

  /// 막대의 양 끝(띠 안에 가둔 뒤) · 점으로 그릴 때의 제자리.
  final double rx, rx2, mainX;

  /// 점으로 그릴 때 모으는 것: 구슬(통설 · 이설).
  List<double>? beads;

  /// 막대 대신 구슬 하나로 그리는 기간 사건(0.1.1 · 조사 결함 49 — 6px보다 좁은 막대): 이설이 없어 구슬이
  /// 하나뿐이어도 그 구슬을 찍는다(점 사건은 이설이 있을 때만 '실에 꿴 구슬').
  bool single = false;
  List<bool>? beadAlt;

  /// 막대로 그릴 때 모으는 것: 이설의 시작 · 끝.
  List<double>? altStarts, altEnds;

  /// 이 사건이 든 띠의 번호(맞히기가 돌려준다).
  int band = 0;

  /// 막대를 그린 오른쪽 끝(화면에서 자른 뒤)과 그때 쓴 색 · 모양 — 빗금 위에 덮어 그릴 때 그대로 쓴다.
  double drawnRight = double.nan;
  int soft = 0, edge = 0;
  bool treaty = false, pair = false;

  double clamp(double x) => clampInside(x, lo, hi, RailLook.inset);
}

class RailLayer extends TileLayer {
  RailLayer({BandSpans? spans, Quads? overlay}) : spans = spans ?? BandSpans(), _overlay = overlay ?? Quads();

  /// 띠의 가로 범위(인물 막대 층과 같은 것을 써도 된다).
  final BandSpans spans;
  final parts = RailParts.shared;

  /// 연대 폭의 빗금(무늬 묶음)은 공통 묶음의 네모보다 뒤에 나가므로 막대를 덮는다 — 지금 연표는 막대(z 2)가 위다.
  /// 빗금과 겹치는 막대 토막을 여기에 다시 모아 층의 flush(무늬 뒤)에서 한 번에 덮어 그린다.
  /// 내보내기(SVG)가 제 묶음으로 갈아 끼운다 — 갈아 끼우지 못하면 이 토막만 SVG에서 빠진다.
  final Quads _overlay;

  /// 밝기 상태(총괄이 장면에 넣기 전에는 중립). 층은 장면마다 여기서만 밝기를 묻는다.
  em.Emphasis? emphasis;
  static final em.Emphasis _neutral = em.Emphasis();

  em.Emphasis get _em => emphasis ?? _neutral;

  final _events = <int, _Ev>{};

  /// 이 장면에서 다시 고른 단(사건 번호 → 단) — 자료의 단(`a`)은 해로만 정한 값이라 확대하면 겹친다.
  final _lane = <int, int>{};
  final _cands = <int, _Cand>{};
  final _byRow = <int, List<_Cand>>{};
  final _pointed = <int>{};

  /// 이 장면에서 접혀 있는 하위 사건(부모가 좁아 펼쳐지지 않은 것)과, 사건마다 지난 장면에 펼쳐져 있었는가(문턱 둘).
  final _collapsed = <int>{};
  final _wasOpen = <int, bool>{};

  /// 마지막 장면의 자리 기록(맞히기).
  final _spots = <_Spot>[];

  /// 밝기를 다시 셈하지 않아도 되는지 가리는 값(`emphasis.version`) — 흐르는 중에는 장면마다 다르다.
  int _lookVersion = -1;

  /// 이설(다른 견해) 표시를 켰는가(표시 상태의 [SceneMarks.showAlt]). 꺼 두면 지금 연표처럼
  /// 이설의 세로바 · 연결선 · 빈 고리 구슬이 없어지고 단 고르기에도 이설의 자리가 들지 않는다
  /// (js/timeline.js 7063 `const alts = this.showAlt && !it.sec ? HT.datedAlts(e) : []`).
  bool _showAlt = true;

  /// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A)를 켰으면 그 주제의 사건 번호 — 아닌 사건의 막대는 .26(웹의 `.tl-rail.no-lens`). 끄거나 받는 중이면 null.
  Set<int>? _lensEvents;

  @override
  void beginFrame(PaintContext c) {
    final marks = SceneMarks.of(c.scene);
    _showAlt = marks.showAlt;
    _lensEvents = c.layout.themeLens.isEmpty ? null : marks.lensEvents;
    spans.beginFrame();
    _events.clear();
    _lane.clear();
    _cands.clear();
    _byRow.clear();
    _pointed.clear();
    _collapsed.clear();
    _spots.clear();
    _lookVersion = _em.active ? -1 : _em.version;
    if (c.hide.contains('events') || c.hide.contains('rails')) return;
    // 조감에는 기간 막대 칸 자체가 없다 — railH = 0(명세 05의 7.2 · 명세 03의 1.10). 자동 조감도 같다.
    if (c.layout.conditions.bird) return;
    spans.ensure(c);
    _foldChildren(c);
    _pickLevels(c);
  }

  /// 묶음을 다시 만들지 않아도 되는 장면인가(총괄이 장면을 아낄 때 쓰라고 남겨 둔다 — 밝기가 흐르는 중에는 늘 거짓).
  bool get lookSettled => !_em.active && _lookVersion == _em.version;

  @override
  void setScale(double scale) => parts.setScale(scale);

  @override
  void flush(PaintContext c) {
    _overlay.flush(c.canvas);
    parts.flush(c.canvas);
  }

  @override
  void paintTile(PaintContext c, Tile t) {
    if (c.hide.contains('events') || c.hide.contains('rails')) return;
    if (c.layout.conditions.bird) return;
    final rails = t.section(RailLook.secRail), fuzz = t.section(RailLook.secFuzz);
    final alts = t.section(RailLook.secAlt), effects = t.section(RailLook.secEffect);
    if (rails.count + fuzz.count + alts.count + effects.count == 0) return;
    spans.ensure(c);
    _events.clear();
    _paintBars(c, t, rails);
    _paintEffects(c, t, effects);
    _gatherFuzz(c, t, fuzz);
    _gatherAlts(c, t, alts);
    _finish(c, t);
  }

  /// 구역 32 — 하위 사건의 부모 기간. 부모가 화면에서 90px보다 좁으면 그 자식은 접혀 있으므로 막대도 그리지 않는다
  /// (지금 연표도 접힌 자식은 `_placeRow`에서 빠져 기간 막대가 나오지 않는다). 문턱은 둘 — 한 번 펼쳐지면 8% 더 좁아져야 접힌다.
  void _foldChildren(PaintContext c) {
    final ppm = c.v.ppm;
    for (final d in c.scene.draw) {
      final s = d.tile.section(RailLook.secChild);
      if (s.count == 0) continue;
      final x0s = s.f(Tile.itemX0), x1s = s.f(Tile.itemX1);
      final refs = s.u(Tile.itemRef), thresholds = s.u(Tile.itemB), backs = s.u(Tile.itemC);
      for (int i = 0; i < s.count; i++) {
        final width = (x1s[i] - x0s[i]) * ppm;
        final threshold = thresholds[i] > 0 ? thresholds[i].toDouble() : RailLook.openWidth;
        final back = backs[i] > 0 ? backs[i] : RailLook.openBack;
        final was = _wasOpen[refs[i]] ?? false;
        final open = width >= (was ? threshold * (1 - back / 1000) : threshold);
        _wasOpen[refs[i]] = open;
        if (!open) _collapsed.add(refs[i]);
      }
    }
  }

  /// 배율마다 단을 다시 고른다(지금 연표의 `pickLevel` — js/timeline.js 207 · 7072).
  /// 줄마다 `(고른 것 100 + 강조 10 + 중요도)`가 큰 것 먼저 · 같으면 자료가 실어 준 차례(계약 6-7 가)대로 늘어놓고,
  /// 그 사건의 그림이 통틀어 차지하는 화면 범위 ±4px이 겹치지 않는 첫 단에, 빈 단이 없으면 가장 적게 겹치는 단에 둔다.
  void _pickLevels(PaintContext c) {
    final look = _em.look;
    final hiSet = look.layout ? look.events : null;
    final own = {for (final d in c.scene.draw) if (!d.isCover) d.key};
    for (final d in c.scene.draw) {
      if (d.isCover && own.contains(d.key)) continue;
      _gatherCands(c, d.tile);
    }
    for (final cand in _cands.values) {
      if (!cand.any || cand.hi < cand.lo) continue;
      (_byRow[cand.row] ??= <_Cand>[]).add(cand);
    }
    for (final entry in _byRow.entries) {
      final geo = c.layout.geo(entry.key);
      final count = geo.railLevels < 1 ? 1 : geo.railLevels;
      final list = entry.value;
      int prio(_Cand x) => (look.event == x.id ? 100 : 0) + ((hiSet?.contains(x.id) ?? false) ? 10 : 0) + x.importance;
      list.sort((a, b) => prio(b) - prio(a) != 0 ? prio(b) - prio(a) : a.rank - b.rank);
      final levels = List.generate(count, (_) => <double>[]);
      for (final x in list) {
        final l = x.lo - RailLook.pickPad, r = x.hi + RailLook.pickPad;
        int lvl = -1;
        for (int i = 0; i < count && lvl < 0; i++) {
          var free = true;
          for (int j = 0; j < levels[i].length; j += 2) {
            if (levels[i][j] < r && l < levels[i][j + 1]) {
              free = false;
              break;
            }
          }
          if (free) lvl = i;
        }
        if (lvl < 0) {
          var best = double.infinity;
          for (int i = 0; i < count; i++) {
            var over = 0.0;
            for (int j = 0; j < levels[i].length; j += 2) {
              final w = math.min(levels[i][j + 1], r) - math.max(levels[i][j], l);
              if (w > 0) over += w;
            }
            if (over < best) {
              best = over;
              lvl = i;
            }
          }
        }
        levels[lvl]
          ..add(l)
          ..add(r);
        _lane[x.id] = lvl;
      }
    }
  }

  /// 한 타일에서 단 고르기에 쓸 값을 모은다: 막대(33) · 연대 폭(34) · 이설(35)의 자리와 중요도 · 차례.
  void _gatherCands(PaintContext c, Tile t) {
    final v = c.v, origin = t.origin.toDouble();
    _Cand? cand(int id, int row, int b, int d) {
      if (_collapsed.contains(id)) return null;
      final layout = c.layout;
      if (row >= layout.rowCount || !layout.hasBody(row) || layout.geo(row).railTop < 0) return null;
      return _cands[id] ??= _Cand(id, row, math.max(1, (b >> 5) & 3), d >> 8);
    }

    final rails = t.section(RailLook.secRail);
    if (rails.count > 0) {
      final x0s = rails.f(Tile.itemX0), x1s = rails.f(Tile.itemX1);
      final rows = rails.u(Tile.itemRow), refs = rails.u(Tile.itemRef), bits = rails.u(Tile.itemB), ds = rails.u(Tile.itemD);
      for (int i = 0; i < rails.count; i++) {
        final x = cand(refs[i], rows[i], bits[i], ds[i]);
        if (x == null) continue;
        final band = spans.idAt(rows[i], origin + x0s[i], origin + x1s[i]);
        final (lo, hi) = spans.screenSpan(v, band);
        final rawL = v.xOf(origin + x0s[i]), rawR = v.xOf(origin + x1s[i]);
        final rx = clampInside(rawL, lo, hi, RailLook.inset), rx2 = clampInside(rawR, lo, hi, RailLook.inset);
        if (rawR - rawL > RailLook.rangedPx) {
          x.ranged = true;
          x.any = true;
        }
        x.grow(math.min(rx, rx2), math.max(rx, rx2));
      }
    }
    for (final kind in const [RailLook.secFuzz, RailLook.secAlt]) {
      if (kind == RailLook.secAlt && !_showAlt) continue; // 이설을 끄면 단 고르기의 xs에도 이설의 자리가 들지 않는다
      final s = t.section(kind);
      if (s.count == 0) continue;
      final x0s = s.f(Tile.itemX0), x1s = s.f(Tile.itemX1);
      final rows = s.u(Tile.itemRow), refs = s.u(Tile.itemRef), bits = s.u(Tile.itemB), ds = s.u(Tile.itemD);
      for (int i = 0; i < s.count; i++) {
        final x = cand(refs[i], rows[i], bits[i], ds[i]);
        if (x == null) continue;
        final band = spans.idAt(rows[i], origin + x0s[i], origin + x1s[i]);
        final (lo, hi) = spans.screenSpan(v, band);
        final a = clampInside(v.xOf(origin + x0s[i]), lo, hi, RailLook.inset);
        final b = clampInside(v.xOf(origin + x1s[i]), lo, hi, RailLook.inset);
        x
          ..any = true
          ..grow(math.min(a, b), math.max(a, b));
        // 점 사건은 제자리(구슬)도 xs에 든다 — 그 줄의 사건에서 번호로 찾는다(사건마다 한 번만).
        if (_pointed.add(refs[i])) {
          final at = _eventAt(t, rows[i], refs[i]);
          if (!at.isNaN) {
            final p = clampInside(v.xOf(at), lo, hi, RailLook.inset);
            x.grow(p, p);
          }
        }
      }
    }
  }

  /// 그 항목이 앉는 자리 — 줄이 보이고 화면에 걸치면 (단, 세로 자리)를 준다. [id]의 단을 이 장면에서 다시 골랐으면 그것을 쓴다.
  (int, double)? _seat(PaintContext c, int row, int lane, int id) {
    final layout = c.layout;
    if (row >= layout.rowCount || !layout.hasBody(row)) return null;
    final geo = layout.geo(row);
    if (geo.railTop < 0) return null;
    final picked = _lane[id] ?? lane;
    final lvl = picked >= geo.railLevels ? geo.railLevels - 1 : picked;
    final y = c.v.yOf(layout.rowTop(row) + geo.railTop + RailLook.offset + lvl * RailLook.pitch);
    // 막대 칸이 차지하는 세로 자리는 세로바(±3)까지다.
    if (!c.rowOnScreen(row, y - RailLook.capHeight / 2, RailLook.capHeight)) return null;
    return (lvl, y);
  }

  /// 이 사건의 막대 칸 밝기: 다른 것을 고른 동안 `.45`(css:861 · 1491), 고른 사건은 1.
  double _dim(int id) => (_em.look.event == id ? 1 : _em.trimDim) * (_lensEvents == null || _lensEvents!.contains(id) ? 1 : .26);

  /// 구역 33 — 기간 막대(가는 선 + 양 끝 세로바). 조약은 겹줄, 공동 사건의 다른 자리는 파선.
  void _paintBars(PaintContext c, Tile t, TileSection s) {
    if (s.count == 0) return;
    final v = c.v, origin = t.origin.toDouble(), w = c.w, left = c.left;
    final x0s = s.f(Tile.itemX0), x1s = s.f(Tile.itemX1);
    final rows = s.u(Tile.itemRow), flags = s.u(Tile.itemFlags), refs = s.u(Tile.itemRef), colors = s.u(Tile.itemColor);
    final lanes = s.u(Tile.itemA), bits = s.u(Tile.itemB);
    for (int i = 0; i < s.count; i++) {
      final row = rows[i];
      final id = refs[i];
      if (_collapsed.contains(id)) continue; // 접힌 하위 사건
      final seat = _seat(c, row, lanes[i], id);
      if (seat == null) continue;
      final (lane, y) = seat;
      final color = colors[i];
      final band = spans.idAt(row, origin + x0s[i], origin + x1s[i]);
      final (bandLo, bandHi) = spans.screenSpan(v, band);
      final rawL = v.xOf(origin + x0s[i]), rawR = v.xOf(origin + x1s[i]);
      final cutL = flags[i] & Tile.clipLeft != 0, cutR = flags[i] & Tile.clipRight != 0;
      var rx = clampInside(rawL, bandLo, bandHi, RailLook.inset), rx2 = clampInside(rawR, bandLo, bandHi, RailLook.inset);
      // 타일 경계에서 잘린 쪽은 정수 px에서 만나게 한다 — 두 조각이 이어져 하나로 보이게(띠 · 칸과 같은 규칙).
      if (cutL) rx = rx.roundToDouble();
      if (cutR) rx2 = rx2.roundToDouble();
      // 스위치 mend(0.1.1 · 조사 결함 49 — 0.1.1 다-1 뒤 route에서 뗌): 6px보다 좁은 막대('H' 꼴)는 막대 + 세로바 대신 시작 자리의 구슬 하나로. 2px 이하는 예전처럼 점 사건
      // (이설이 있을 때만 구슬). 빈 단이 없어 겹치는 단에 넣은 긴 막대는 그대로 — 구슬로 줄이면 기간이 사라지고 구슬이 이웃 막대 끝에 붙었다(감독 확인 몫).
      // 타일 경계에서 잘린 조각은 폭이 막대의 폭이 아니다 — 긴 막대의 2 ~ 6px 끝 조각을 구슬로 바꾸면 막대가 끊기고 타일 경계에 구슬이 홀로 선다.
      final data = rawR - rawL > RailLook.rangedPx;
      final single = data && PaintPick.mend && !cutL && !cutR && rawR - rawL <= RailLook.narrowPx;
      final ranged = data && !single;
      final ev = _events[id] = _Ev(row, lane, y, color, bandLo, bandHi, ranged, rx, rx2, rx)
        ..band = band
        ..single = single;
      if (!ranged) continue; // 2px 이하로 좁아지면 막대가 아니라 점 사건으로(구슬은 _finish에서)
      final width = math.max(RailLook.minWidth, math.min(rx2, w + 4) - rx);
      if (rx > w || rx + width < left) continue;
      final alpha = _dim(id);
      final soft = withAlpha(RailLook.edgeSoft(color), alpha), edge = withAlpha(RailLook.edge(color), alpha);
      final pair = bits[i] & 1 != 0, treaty = bits[i] & 2 != 0;
      final right = rx + width;
      ev.drawnRight = right;
      ev.soft = soft;
      ev.edge = edge;
      ev.treaty = treaty;
      ev.pair = pair;
      // 고르거나 올린 막대의 둘레 빛(box-shadow 0 0 0 1.5px color-mix(edge 30%, transparent)).
      if (_em.look.event == id || c.scene.selectedEventId == id) {
        final half = (treaty ? RailLook.treaty : RailLook.body) / 2 + RailLook.glow;
        c.quads.add(rx - RailLook.glow, y - half, right + RailLook.glow, y + half, withAlpha(RailLook.edge(color), RailLook.glowMix));
      }
      _bar(c.quads, ev, rx, right, y);
      // 양 끝 세로바(1.5 × 6): 잘린 쪽에는 두지 않는다 — 이어지는 조각과 하나로 보이게.
      final capTop = y - RailLook.capHeight / 2, capBottom = y + RailLook.capHeight / 2;
      if (!cutL) c.quads.add(rx, capTop, rx + RailLook.cap, capBottom, edge);
      if (!cutR) c.quads.add(right - RailLook.cap, capTop, right, capBottom, edge);
      c.stats.shapes++;
      _spots.add(_Spot(RailPart.bar, id, band, row, lane, rx - 2, right + 2, y, RailLook.grab));
      c.debug?.bars.add(DebugBar(id, ui.Rect.fromLTRB(rx, y - (treaty ? RailLook.treaty : RailLook.body) / 2, right, y + (treaty ? RailLook.treaty : RailLook.body) / 2)));
      c.debug?.note('막대', RailMark(treaty ? '조약' : (pair ? '공동' : '기간'), id, rx, y, width, treaty ? RailLook.treaty : RailLook.body, lane, alpha));
    }
  }

  /// 막대 몸통 한 토막(보통 2px · 조약은 위아래 1px 겹줄 · 공동 사건의 다른 자리는 파선). [q]를 갈아 끼우면 빗금 위에 덮어 그린다.
  void _bar(Quads q, _Ev ev, double from, double to, double y) {
    if (to <= from) return;
    if (ev.treaty) {
      dashRow(q, from, to, y - 2, 1, ev.soft, dash: ev.pair ? RailLook.pairDash : 0, gap: RailLook.pairGap, phase: ev.rx);
      dashRow(q, from, to, y + 1, 1, ev.soft, dash: ev.pair ? RailLook.pairDash : 0, gap: RailLook.pairGap, phase: ev.rx);
    } else {
      dashRow(q, from, to, y - RailLook.body / 2, RailLook.body, ev.soft, dash: ev.pair ? RailLook.pairDash : 0, gap: RailLook.pairGap, phase: ev.rx);
    }
  }

  /// 구역 36 — 조약의 발효 눈금(작은 마름모). 막대가 있고, 막대의 양 끝에서 3px보다 안쪽일 때만.
  void _paintEffects(PaintContext c, Tile t, TileSection s) {
    if (s.count == 0) return;
    final v = c.v, origin = t.origin.toDouble(), w = c.w;
    final x0s = s.f(Tile.itemX0);
    final refs = s.u(Tile.itemRef);
    for (int i = 0; i < s.count; i++) {
      final ev = _events[refs[i]];
      if (ev == null || !ev.ranged) continue;
      final x = v.xOf(origin + x0s[i]);
      if (x <= ev.rx + RailLook.effectInset || x >= math.min(ev.rx2, w + 4) - RailLook.effectInset) continue;
      final alpha = _dim(refs[i]);
      // 종이색 테를 먼저, 그 위에 제 색 마름모 — 겹줄 위에서도 또렷하게(css의 box-shadow 0 0 0 1px var(--paper)).
      parts.add(RailParts.diamondRing, x, ev.y, withAlpha(Look.paper, alpha));
      parts.add(RailParts.diamond, x, ev.y, withAlpha(RailLook.edge(ev.color), alpha));
      c.stats.shapes++;
      _spots.add(_Spot(RailPart.effect, refs[i], ev.band, ev.row, ev.lane, x - RailLook.effect / 2, x + RailLook.effect / 2, ev.y, RailLook.effect / 2 + 2));
      c.debug?.note('발효', RailMark('발효', refs[i], x, ev.y, RailLook.effect, RailLook.effect, ev.lane, alpha));
    }
  }

  /// 구역 34 — 연대 폭. 기간 사건이면 빗금 구간. 점 사건은 그리지 않는다 — 날짜를 정확히 모르면 범위 없이 점 하나로
  /// (감독 결정 2026-10-13 "적당하게 한 곳을 찍어서 단일로 · 범위 표현 x"; 예전의 '실 위 연대 폭 눈금'을 없앰 · 자료와 단 자리는 그대로).
  void _gatherFuzz(PaintContext c, Tile t, TileSection s) {
    if (s.count == 0) return;
    final v = c.v, origin = t.origin.toDouble();
    final x0s = s.f(Tile.itemX0), x1s = s.f(Tile.itemX1);
    final rows = s.u(Tile.itemRow), refs = s.u(Tile.itemRef), colors = s.u(Tile.itemColor), lanes = s.u(Tile.itemA), sides = s.u(Tile.itemC);
    for (int i = 0; i < s.count; i++) {
      final ev = _at(c, t, refs[i], rows[i], lanes[i], colors[i], origin + x0s[i], sides[i] == 1);
      if (ev == null) continue;
      if (!ev.ranged) continue;
      final l = ev.clamp(v.xOf(origin + x0s[i])), r = ev.clamp(v.xOf(origin + x1s[i]));
      final width = math.max(RailLook.fuzzMinWidth, r - l);
      final top = ev.y - RailLook.fuzzHeight / 2;
      // 135° 빗금(3px 긋고 6px마다) — 무늬 묶음에 모아 한 번에. 무늬의 시작은 제 왼쪽 위(css의 background-position 0 0).
      c.patterns.add(RailLook.fuzzPattern, l, top, l + width, top + RailLook.fuzzHeight, withAlpha(0xff000000 | ev.color, .4), phaseX: l, phaseY: top);
      // 무늬 묶음은 공통 네모 묶음보다 뒤에 나가 막대를 덮는다 — 겹친 토막만큼 막대를 제 층의 묶음에 다시 담아 무늬 위에 덮는다(z 2).
      if (ev.drawnRight.isFinite) {
        final from = math.max(l, ev.rx), to = math.min(l + width, ev.drawnRight);
        _bar(_overlay, ev, from, to, ev.y);
        if (to > from) c.debug?.note('덧그림', RailMark('덧그림', refs[i], from, ev.y, to - from, RailLook.body, ev.lane));
      }
      c.stats.shapes++;
      c.debug?.note('연대폭', RailMark('연대폭', refs[i], l, ev.y, width, RailLook.fuzzHeight, ev.lane));
    }
  }

  /// 구역 35 — 이설. 기간 사건이면 점선 세로바 + 통설까지 잇는 점선, 점 사건이면 빈 고리 구슬.
  void _gatherAlts(PaintContext c, Tile t, TileSection s) {
    if (s.count == 0 || !_showAlt) return;
    final v = c.v, origin = t.origin.toDouble();
    final x0s = s.f(Tile.itemX0), x1s = s.f(Tile.itemX1);
    final rows = s.u(Tile.itemRow), refs = s.u(Tile.itemRef), colors = s.u(Tile.itemColor), lanes = s.u(Tile.itemA), bits = s.u(Tile.itemB);
    for (int i = 0; i < s.count; i++) {
      final ev = _at(c, t, refs[i], rows[i], lanes[i], colors[i], origin + x0s[i], bits[i] & 8 != 0);
      if (ev == null) continue;
      final start = ev.clamp(v.xOf(origin + x0s[i]));
      final hasEnd = bits[i] & 1 != 0, differs = bits[i] & 2 != 0;
      if (ev.ranged) {
        (ev.altStarts ??= <double>[]).add(start);
        // 끝이 통설과 다른 이설은 끝에도 같은 세로바.
        if (differs) (ev.altEnds ??= <double>[]).add(ev.clamp(v.xOf(origin + x1s[i])));
        continue;
      }
      _bead(ev, start, true);
      if (hasEnd) _bead(ev, ev.clamp(v.xOf(origin + x1s[i])), true);
    }
  }

  /// 항목이 가리키는 사건의 막대 칸. 이 타일에 막대가 없으면(점 사건이거나 막대가 옆 타일에 있으면) 항목의 값으로 만든다.
  _Ev? _at(PaintContext c, Tile t, int ref, int row, int lane, int color, double minute, bool rangedByData) {
    final known = _events[ref];
    if (known != null) return known;
    if (_collapsed.contains(ref)) return null;
    final seat = _seat(c, row, lane, ref);
    if (seat == null) return null;
    final (lvl, y) = seat;
    final band = spans.idAt(row, minute);
    final (lo, hi) = spans.screenSpan(c.v, band);
    // 점 사건의 통설 구슬은 사건 제자리에 찍는다 — 그 줄의 사건에서 번호로 찾는다(막대가 없는 사건만이라 드물다).
    final at = rangedByData ? double.nan : _eventAt(t, row, ref);
    final made = _Ev(row, lvl, y, color, lo, hi, rangedByData, double.nan, double.nan, at.isNaN ? double.nan : clampInside(c.v.xOf(at), lo, hi, RailLook.inset))..band = band;
    _events[ref] = made;
    return made;
  }

  /// 그 줄에서 번호가 [id]인 사건의 시작(세계 분). 없으면 NaN.
  double _eventAt(Tile t, int row, int id) {
    final (from, to) = t.eventsIn(row, double.negativeInfinity, double.infinity);
    for (int i = from; i < to; i++) {
      if (t.eventId[i] == id) return t.origin + t.eventX0[i];
    }
    return double.nan;
  }

  /// 구슬 하나를 더한다 — 이미 있는 구슬과 6px 안이면 합친다(지금 연표의 beadsOf).
  void _bead(_Ev ev, double x, bool alt) {
    final beads = ev.beads ??= <double>[];
    final kinds = ev.beadAlt ??= <bool>[];
    for (final b in beads) {
      if ((b - x).abs() < RailLook.beadMerge) return;
    }
    beads.add(x);
    kinds.add(alt);
  }

  /// 사건마다 마무리: 막대면 이설의 세로바와 연결선, 점이면 '점선 실에 꿴 구슬'.
  void _finish(PaintContext c, Tile t) {
    for (final entry in _events.entries) {
      final ev = entry.value;
      if (ev.ranged) {
        _altBars(c, entry.key, ev, ev.altStarts, ev.rx);
        _altBars(c, entry.key, ev, ev.altEnds, ev.rx2);
      } else {
        _thread(c, entry.key, ev);
      }
    }
  }

  /// 이설의 점선 세로바와 통설까지 잇는 1px 점선. 통설의 세로바와 4px 안이면 4px 바깥으로 비킨다.
  void _altBars(PaintContext c, int id, _Ev ev, List<double>? list, double base) {
    if (list == null || list.isEmpty || !base.isFinite) return;
    // 이설 세로바 · 연결선에는 css에 고른 동안의 흐림 규칙이 없다(`.tl.is-picked`의 목록은 막대 · 구슬 · 실 · 눈금 · 발효뿐 — css:369 · 861 · 1491).
    final edge = RailLook.edge(ev.color), soft = withAlpha(RailLook.edgeSoft(ev.color), .8);
    double lo = base, hi = base;
    for (int i = 0; i < list.length; i++) {
      var x = list[i];
      if ((x - base).abs() < RailLook.altNudge) x = base + (x < base ? -RailLook.altNudge : RailLook.altNudge);
      list[i] = x;
      if (x < lo) lo = x;
      if (x > hi) hi = x;
    }
    // 연결선 먼저(css의 차례대로 세로바가 그 위에 온다).
    if (hi > lo) dashRow(c.quads, lo, hi, ev.y, 1, soft, dash: RailLook.lineDash, gap: RailLook.lineGap, phase: lo);
    final top = ev.y - RailLook.altHeight / 2;
    for (final x in list) {
      dashColumn(c.quads, x - RailLook.altWidth / 2, top, top + RailLook.altHeight, RailLook.altWidth, edge, dash: RailLook.altDash, gap: RailLook.altGap, phase: top);
      c.stats.shapes++;
      // 누르기 여유는 css의 `::before { inset: −2px −4px }`.
      _spots.add(_Spot(RailPart.alt, id, ev.band, ev.row, ev.lane, x - RailLook.altWidth / 2 - 4, x + RailLook.altWidth / 2 + 4, ev.y, RailLook.altHeight / 2 + 2));
      c.debug?.note('이설', RailMark('이설', id, x, ev.y, RailLook.altWidth, RailLook.altHeight, ev.lane));
    }
  }

  /// 점 사건의 '점선 실에 꿴 구슬': 실(1px 점선) · 통설의 채운 구슬 · 이설의 빈 고리.
  void _thread(PaintContext c, int id, _Ev ev) {
    final beads = ev.beads ?? <double>[];
    final kinds = ev.beadAlt ?? <bool>[];
    if (ev.mainX.isFinite) {
      // 통설은 늘 첫 구슬이다 — 합치기는 이설 쪽이 양보한다(지금 연표의 차례와 같게).
      beads.insert(0, ev.mainX);
      kinds.insert(0, false);
      for (int i = beads.length - 1; i >= 1; i--) {
        if ((beads[i] - ev.mainX).abs() < RailLook.beadMerge) {
          beads.removeAt(i);
          kinds.removeAt(i);
        }
      }
    }
    if (beads.isEmpty) return;
    double lo = beads.first, hi = beads.first;
    for (final x in beads) {
      if (x < lo) lo = x;
      if (x > hi) hi = x;
    }
    final line = hi - lo >= RailLook.threadMin;
    if (!line && !ev.single) return;
    final alpha = _dim(id);
    final soft = withAlpha(RailLook.edgeSoft(ev.color), alpha), edge = withAlpha(RailLook.edge(ev.color), alpha);
    // 실: 1px 점선, 짙기 .85. 자리는 막대 top의 위아래 0.5px(css의 margin-top −0.5 + border-top 1px).
    if (line) {
      dashRow(c.quads, lo, hi, ev.y - .5, 1, withAlpha(soft, .85), dash: RailLook.dotDash, gap: RailLook.dotGap, phase: lo);
      c.debug?.note('실', RailMark('실', id, lo, ev.y, hi - lo, 1, ev.lane, alpha));
    }
    // 구슬 위 연도는 고르거나 올렸을 때만 나온다(css:854~859의 opacity 0 → 1).
    final hot = _em.look.event == id || c.scene.selectedEventId == id;
    for (int i = 0; i < beads.length; i++) {
      // 통설은 테(edge) + 안(edge-soft), 이설은 테(edge-soft) + 안(종이색)의 빈 고리 — 테 두께 1 · 1.25.
      final ring = kinds[i] ? soft : edge, inner = kinds[i] ? withAlpha(Look.paper, alpha) : soft;
      parts.add(RailParts.bead, beads[i], ev.y, ring);
      parts.add(kinds[i] ? RailParts.beadAltInner : RailParts.beadInner, beads[i], ev.y, inner);
      c.stats.shapes++;
      _spots.add(_Spot(RailPart.bead, id, ev.band, ev.row, ev.lane, beads[i] - RailLook.bead / 2 - 3, beads[i] + RailLook.bead / 2 + 3, ev.y, RailLook.bead / 2 + 3));
      c.debug?.note('구슬', RailMark(kinds[i] ? '이설구슬' : '통설구슬', id, beads[i], ev.y, RailLook.bead, RailLook.bead, ev.lane, alpha));
      if (!hot) continue;
      final text = yearLabel(yearAt(c.v.minuteAt(beads[i])).floor());
      final look = TextLook(RailLook.beadYearSize, ui.FontWeight.w600, RailLook.edge(ev.color));
      final width = c.text.widthOf(text, look);
      if (width == null) continue;
      // 구슬 상자(6px)의 아래에서 6px 위 · 가로 가운데 — 글자의 아랫변이 구슬 위 3px에 닿는다.
      c.later.add('bead', text, look, beads[i] - width / 2, ev.y + RailLook.bead / 2 - RailLook.beadYearGap - RailLook.beadYearSize);
    }
  }

  /// 마지막으로 그린 장면에서 [x] · [y](배치 px)에 있는 기간 막대 칸의 것. 없으면 null.
  /// 앞에 그린 것일수록 위에 있으므로 뒤에서부터 본다(구슬 · 발효는 z 2라 막대보다 위다).
  RailHit? hitRails(double x, double y) {
    for (int i = _spots.length - 1; i >= 0; i--) {
      final s = _spots[i];
      if ((y - s.y).abs() > s.grab || x < s.x0 || x > s.x1) continue;
      return RailHit(s.part, s.eventId, s.band, s.row, s.lane);
    }
    return null;
  }
}
