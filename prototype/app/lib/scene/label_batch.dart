import 'dart:typed_data';
import 'dart:ui' show FontWeight;

import 'color_mix.dart';
import 'emphasis.dart' show Emphasis;
import 'labels.dart';
import 'layout.dart';
import 'lens_titles.dart';
import 'levels.dart';
import 'paint/look.dart';
import 'reserved.dart';
import 'scene.dart';
import 'text_paragraph.dart';
import 'tile.dart';
import 'viewport.dart';

/// 사건 글자의 생김새(명세 02-사건의-표현 3.2). 크기는 그 트랙의 **기본** 글줄 수가 정한다(둘 이상이면 12 · 하나면 11.5) —
/// 분류별 글줄로 글줄이 늘어도 글자는 커지지 않는다.
///
/// **글자 사이는 0이다.** 본문의 `letter-spacing: -.01em`(= −0.14px)을 그대로 넣으면 이름이 기준 그림보다
/// 글자마다 0.14px씩 좁아진다. 기준 덤프의 화면 폭과 맞대 본 값(Noto Sans KR · 11.5px):
/// `별목 습원 · 번식지의 임시 폐쇄` 화면 146.52 ↔ 사이 0 → 146.498 · 사이 −0.14 → 143.978,
/// `흰계단 공방 · 노동 시간표의 개정` 156.95 ↔ 157.078 / 154.418, `기억고 정비의 달` 79.25 ↔ 79.235 / 77.975.
/// 글자 수 7~19자에서 모두 사이 0이 ±0.13px 안으로 맞는다 — 명세 3.2가 "글자마다 −0.14px을 더하라"고 적은 것은
/// 크롬이 실제로 그리는 폭과 다르다(명세 10.9가 확인하지 못한 채 남긴 자리다).
abstract final class EventFont {
  static const spacing = 0.0;

  /// `.cnt`(하위 수 알약)의 글자 크기는 본문 14px × 0.82 = 11.48px으로 고정이다 —
  /// 배치가 재는 폭(`g.font × 0.82`)과 다른 것이 지금 연표의 모습이다(명세 8.3-2).
  static const countSize = 11.48;

  static final _ink1 = mixSrgb(Look.ink, Look.paper, .72), _inkChild = mixSrgb(Look.ink, Look.paper, .78);

  /// 트랙의 기본 글줄 수로 정하는 사건 글자의 크기 — 자리 쌓기가 정한 값 그대로다(넉넉 12 · 자동 12/11.5 · 빽빽 11.5 · 조감 10).
  static double sizeOf(SceneLayout layout, int row) => layout.eventSize(row);

  /// 글의 모양은 크기 · 중요도 · (하위 · 기울임)만으로 갈린다 — 장면마다 수천 개를 새로 만들지 않게 그 열쇠로 보관한다.
  static final _names = <int, TextLook>{};

  static TextLook name(double size, int importance, int look) {
    final child = EventLook.child(look), italic = EventLook.italic(look);
    final imp = importance < 0 ? 0 : (importance > 7 ? 7 : importance);
    final key = ((size * 16).round() << 6) | (imp << 3) | (child ? 4 : 0) | (italic ? 1 : 0);
    final known = _names[key];
    if (known != null) return known;
    final weight = child ? FontWeight.w400 : (importance >= 3 ? FontWeight.w700 : (importance == 2 ? FontWeight.w500 : FontWeight.w400));
    final color = child ? _inkChild : (importance >= 3 || importance == 2 ? Look.ink : _ink1);
    return _names[key] = TextLook(size, weight, color, italic: italic, spacing: spacing);
  }

  /// 연도 글은 `font-variant-numeric: tabular-nums`라 숫자 폭이 화면에서 조금 좁다 — 글줄 방식에 그 설정을 줄 길이 없어
  /// 글자 사이로 대신한다(기준 `838년` 26.59 ↔ 사이 0 → 27.143 · 사이 −0.14 → 26.583).
  static const yearSpacing = -0.14;

  /// **자리 셈이 재는 폭은 그리는 폭보다 글자마다 0.14px 넓다.** 지금 연표는 캔버스의 `measureText`로 재는데
  /// 그 셈에는 `letter-spacing`이 들어가지 않기 때문이다(명세 10.9). 그래서 이름이 들지 말지의 판정은 이만큼
  /// 넉넉한 폭으로 하고, 그릴 때는 화면에 나오는 폭을 쓴다(`.cnt`의 11.48 ↔ 9.43과 같은 갈림이다 · 명세 8.3-2).
  static const placeSpacing = 0.14;

  static final _years = <int, TextLook>{}, _counts = <int, TextLook>{}, _countMeasures = <int, TextLook>{};

  static TextLook year(double size) => _years[(size * 16).round()] ??= TextLook(size - 1, FontWeight.w400, Look.muted, spacing: yearSpacing);

  /// 하위 수 알약의 글자. 색은 그 띠의 색에서 끌어낸다(`mixSrgb(띠색, 글자색, .78)`).
  static TextLook count(int argb) => _counts[argb] ??= TextLook(countSize, FontWeight.w400, argb);

  /// 배치가 알약 폭을 잴 때 쓰는 크기 — 그리는 크기(11.48)와 일부러 다르다.
  static TextLook countMeasure(double size) => _countMeasures[(size * 16).round()] ??= TextLook(size * 0.82, FontWeight.w400, Look.ink, spacing: spacing);
}

/// 글자 폭을 재는 길. 그리는 쪽(사건 층)이 장면마다 걸어 준다 — 아직 없으면 폭을 모르는 것으로 두고 다음 판으로 미룬다.
/// 층이 쓰는 글자 크기(11.5 · 12 · 11.48)가 공용 [Look.event](12 고정)와 달라, 장면의 `measureName` 대신 이 길로 잰다.
abstract final class EventText {
  static double? Function(String text, TextLook look)? measure;

  static double widthOf(String text, TextLook look) {
    if (text.isEmpty) return 0;
    return measure?.call(text, look) ?? double.nan;
  }
}

/// 타일 하나에서 **한 번만** 셈하면 되는 후보의 값들. 모두 분 단위이거나 배율과 무관한 것이라, 확대 · 돋보기로
/// 배율이 바뀔 때마다 다시 셈하지 않는다(100만 건에서는 한 장면에 후보가 수천 개라 이 되풀이가 만들기 시간의 큰 몫이었다).
/// 타일이 보관에서 빠지면 이 기록도 함께 사라진다(곁에 매단다 — 타일의 밭을 늘리지 않는다).
class _TileLabels {
  _TileLabels(this.tile)
    : precLo = Float64List(tile.eventCount),
      precHi = Float64List(tile.eventCount),
      precDone = Uint8List(tile.eventCount),
      color = Int32List(tile.eventCount),
      colorDone = Uint8List(tile.eventCount),
      dateText = List<String?>.filled(tile.eventCount, null),
      dateWidth = Float32List(tile.eventCount),
      dateSize = Float32List(tile.eventCount);
  final Tile tile;

  /// 시작 날짜의 정밀도가 덮는 구간(분) — 달력 셈이라 값이 비싸다. [precDone]이 0이면 아직 셈하지 않은 것.
  final Float64List precLo, precHi;
  final Uint8List precDone;

  /// 그 사건이 든 띠의 색(0xAARRGGBB · 띠를 못 찾으면 0).
  final Int32List color;
  final Uint8List colorDone;

  /// 띠 번호 → 띠 차례. 성긴 타일에는 띠가 수천 개라 장면마다 다시 짓지 않는다.
  late final Map<int, int> bandById = {for (int b = 0; b < tile.bandCount; b++) tile.bandId[b]: b};

  /// 화면에 맞게 다듬은 날짜 글과 그 폭. 다듬는 규칙(해 눈금인가 · 한 해 안인가)이 바뀌면 통째로 비운다.
  int mode = -1;
  final List<String?> dateText;
  final Float32List dateWidth, dateSize;

  void setMode(int next) {
    if (mode == next) return;
    mode = next;
    dateText.fillRange(0, dateText.length, null);
    dateSize.fillRange(0, dateSize.length, 0);
  }
}

final _tileLabels = Expando<_TileLabels>('타일의 후보');

_TileLabels _labelsOf(Tile t) => _tileLabels[t] ??= _TileLabels(t);

/// 이름 자리 계산에 넘긴 후보 한 판. 출력의 후보 번호는 이 판의 번호라, 입력과 출력을 늘 같은 판끼리 짝지어 쓴다.
class LabelBatch {
  LabelBatch._(this.input, this._tile, this._index, this._date, this._color, this._size, this._drawName, this._drawYear, this._lens);
  final LabelInput input;
  final List<Tile> _tile;
  final Int32List _index;
  final List<String> _date;

  /// 관점(lens)이 준 이름(없으면 null) — 자료의 이름 대신 이것을 적는다.
  final List<String?>? _lens;
  final Int32List _color;
  final Float32List _size;

  /// 화면에 나오는 이름 · 연도의 폭(자리 셈이 쓰는 [LabelInput.nameWidth]는 글자마다 0.14px 넓다).
  final Float32List _drawName, _drawYear;

  /// [runOf]와 같은 셈을 돌려 쓰는 그릇에 담는다 — 그리는 쪽이 장면마다 수백 개의 새 객체를 만들지 않게.
  void runInto(LabelRunBox box, int candidate, double x, int side, int flags) => labelRunInto(
    box,
    x: x,
    side: side,
    look: input.look[candidate],
    nameWidth: _drawName[candidate],
    countWidth: flags & LabelFlag.count != 0 ? input.countWidth[candidate] : 0,
    yearWidth: flags & LabelFlag.year != 0 ? _drawYear[candidate] : 0,
  );

  /// 그릴 때의 조각 자리 — 폭은 **그리는 폭**으로 잡는다. [flags]는 그 점의 [LabelFlag].
  LabelRun runOf(int candidate, double x, int side, int flags) => labelRun(
    x: x,
    side: side,
    look: input.look[candidate],
    nameWidth: _drawName[candidate],
    countWidth: flags & LabelFlag.count != 0 ? input.countWidth[candidate] : 0,
    yearWidth: flags & LabelFlag.year != 0 ? _drawYear[candidate] : 0,
  );

  /// 화면에 적는 이름. 관점(lens)이 그 사건의 이름을 주었으면 그것을, 아니면 자료의 이름을 쓴다.
  String title(int candidate) =>
      _lens?[candidate] ?? _tile[candidate].text(_tile[candidate].eventName[_index[candidate]]);

  /// 이름 옆 날짜 글(붙지 않으면 빈 글).
  String date(int candidate) => _date[candidate];

  /// 시작 날짜의 정밀도(계약 6-6의 rail 8~10비트: 0 해 · 1 달 · 2 날 · 3 시 · 5 세기 · 6 반세기 · 7 세기의 셋째).
  int precisionOf(int candidate) => (_tile[candidate].eventRail[_index[candidate]] >> 8) & 7;

  /// 날짜를 정확히 모르는 점의 풍선 글(지금 연표 `.tl-ev` title의 뒤 — 예전 정밀도 괄호의 설명): "을사늑약 · 1905년 — 그해 안 어느 날인지 모름".
  String precTip(int candidate) {
    final t = _tile[candidate], i = _index[candidate];
    final when = t.text(t.eventLabel[i]).trim();
    final unknown = switch (precisionOf(candidate)) {
      0 => '그해 안 어느 날인지 모름',
      1 => '그달 안 어느 날인지 모름',
      2 => '그날 몇 시인지 모름',
      5 => '그 세기 안 어느 해인지 모름',
      6 => '그 반세기 안 어느 해인지 모름',
      7 => '그 33년 안 어느 해인지 모름',
      _ => '그 시각 안',
    };
    return '${title(candidate)}${when.isEmpty ? '' : ' · $when'} — $unknown';
  }

  /// 그 사건이 든 띠의 색(띠를 못 찾으면 분류 색). 0xAARRGGBB.
  int colorOf(int candidate) => _color[candidate] & 0xffffffff;

  /// 그 줄의 사건 글자 크기.
  double sizeOf(int candidate) => _size[candidate];

  /// 이름의 폭은 타일에 적어 두고 다시 쓴다(배율과 무관) — 확대할 때마다 수천 개를 다시 재지 않는다. 아직 모르면 NaN.
  static double _nameWidth(Tile t, int i, double size, int importance) {
    var known = t.eventNameWidth[i];
    if (known.isNaN) {
      known = EventText.widthOf(t.text(t.eventName[i]), EventFont.name(size, importance, t.eventLook[i]));
      t.eventNameWidth[i] = known;
    }
    return known;
  }

  /// 사건이 든 띠의 범위(점 · 이름 · 묶음이 그 안에 머문다). 실린 띠 번호(계약 5절 사건 구역의 열 9)로 찾고,
  /// 아직 없는 자료(열이 없으면 0)면 같은 줄에서 그 시각을 품은 띠로 떨어진다. 타일 경계에서 잘린 쪽은 끝을 모르므로 막지 않는다.
  static int _findBand(Tile t, int i, _TileLabels memo) {
    if (memo.colorDone[i] != 0) return memo.color[i];
    memo.colorDone[i] = 1;
    return memo.color[i] = _bandColor(t, i, memo);
  }

  static int _bandColor(Tile t, int i, _TileLabels memo) {
    final want = t.eventBand[i], x = t.eventX0[i], r = t.eventRow[i];
    if (want != 0) {
      final b = memo.bandById[want];
      if (b != null) {
        if (t.eventBandLo[i].isNaN) {
          t.eventBandLo[i] = t.bandFlags[b] & Tile.clipLeft == 0 ? t.origin + t.bandX0[b] : double.negativeInfinity;
          t.eventBandHi[i] = t.bandFlags[b] & Tile.clipRight == 0 ? t.origin + t.bandX1[b] : double.infinity;
        }
        return 0xff000000 | t.bandColor[b];
      }
      if (t.eventBandLo[i].isNaN) {
        t.eventBandLo[i] = double.negativeInfinity;
        t.eventBandHi[i] = double.infinity;
      }
      return 0;
    }
    double inLo = double.negativeInfinity, inHi = double.infinity;
    int argb = 0;
    for (int b = 0; b < t.bandCount; b++) {
      if (t.bandRow[b] != r || x < t.bandX0[b] || x > t.bandX1[b]) continue;
      if (t.bandFlags[b] & Tile.clipLeft == 0) inLo = t.origin + t.bandX0[b];
      if (t.bandFlags[b] & Tile.clipRight == 0) inHi = t.origin + t.bandX1[b];
      argb = 0xff000000 | t.bandColor[b];
      break;
    }
    if (t.eventBandLo[i].isNaN) {
      t.eventBandLo[i] = inLo;
      t.eventBandHi[i] = inHi;
    }
    return argb;
  }

  /// 시작 날짜의 정밀도가 덮는 구간(분). 끝이 있는 사건 · 미정인 사건은 없다(js의 `_precSpan`).
  static (double, double)? _precSpan(double minute, int precision) {
    final t = DateTime.fromMillisecondsSinceEpoch((minute * 60000).round(), isUtc: true);
    final DateTime lo, hi;
    switch (precision) {
      case 0:
        lo = DateTime.utc(t.year);
        hi = DateTime.utc(t.year + 1);
      case 1:
        lo = DateTime.utc(t.year, t.month);
        hi = DateTime.utc(t.year, t.month + 1);
      case 2:
        lo = DateTime.utc(t.year, t.month, t.day);
        hi = DateTime.utc(t.year, t.month, t.day + 1);
      case 3:
        lo = DateTime.utc(t.year, t.month, t.day, t.hour);
        hi = DateTime.utc(t.year, t.month, t.day, t.hour + 1);
      case 5 || 6 || 7:
        final span = _centurySpan(t.year, precision);
        if (span == null) return null;
        lo = DateTime.utc(span.$1);
        hi = DateTime.utc(span.$2);
      default:
        return null;
    }
    return (lo.millisecondsSinceEpoch / 60000, hi.millisecondsSinceEpoch / 60000);
  }

  /// 세기로 적은 연대(정밀도 5 세기 · 6 반세기 · 7 세기의 셋째)의 구간 [첫해, 마지막 해 다음 해) — 천문 연도.
  /// 사건의 시작이 구간의 첫해이므로 거기서 세기 블록을 되짚는다. js의 `cal.centurySpan`과 같은 잣대(초 · 중 · 말 33 · 33 · 34년, 전반 · 후반 50년, 세기 100년).
  static (int, int)? _centurySpan(int astro, int precision) {
    final hist = astro <= 0 ? astro - 1 : astro; // 역사 연도(0년 없음): 천문 0 = 기원전 1년
    final bc = hist < 0;
    final n = bc ? ((-hist - 1) ~/ 100) + 1 : ((hist - 1) ~/ 100) + 1; // 세기 번호
    final first = bc ? -n * 100 : (n - 1) * 100 + 1;
    final off = hist - first; // 0 · 33 · 66 · 50
    if (off < 0 || off >= 100) return null;
    final int len;
    switch (precision) {
      case 5:
        len = 100;
      case 6:
        len = 50;
      case 7:
        len = off >= 66 ? 34 : 33;
      default:
        return null;
    }
    final lastHist = hist + len - 1;
    final nextHist = lastHist == -1 ? 1 : lastHist + 1; // 마지막 해 다음 해(0년 없음)
    int toAstro(int h) => h < 0 ? h + 1 : h;
    return (toAstro(hist), toAstro(nextHist));
  }

  static final _leadingYear = RegExp(r'^(기원전 )?\d+년');
  static final _dropYear = RegExp(r'^(기원전 )?\d+년 ');

  /// 타일이 실어 준 온전한 날짜 글을 화면에 맞게 다듬는다(계약 6-6): 해 눈금이면 앞의 해만, 화면이 한 해 안에 들면 앞의 해를 뗀다.
  static String _dateText(String label, bool subRuler, bool oneYear) {
    if (label.isEmpty) return '';
    if (!subRuler) return _leadingYear.firstMatch(label)?.group(0) ?? label;
    return oneYear ? label.replaceFirst(_dropYear, '') : label;
  }

  /// 부모 사건의 열쇠(시작 분 + 자식 수) — 펼침 문턱의 이력을 판 사이로 잇는다.
  static int _parentKey(double start, int kids) => (start.toInt() * 31 + kids) & 0x7fffffff;

  /// 그릴 타일들에서 점으로 그릴 대표(막대 제외)와 통의 나머지 개수를 모은다. 보이는 줄, 보기의 앞뒤 반 화면까지만.
  static LabelBatch collect(TimelineScene scene, SceneView v, int firstRow, int lastRow, int version) {
    final layout = scene.layout;
    final spanYears = v.span / 525960;
    final previous = scene.labelOutput;
    // 조감에서는 이름을 아예 붙이지 않는다(명세 02 4.1 · 05 7.5) — 폭을 재지도 않는다. 자동 조감도 같다.
    final bird = layout.bird;
    final least = bird ? 99 : minImportanceOf(importanceGates(spanYears, previous?.gates));
    // 강조에 든 사건은 이름 자리에서 앞선다(hiLayout). 왕조 · 인물 창의 메아리 강조는 `layout`이 거짓이라 쓰지 않는다.
    final emphasis = Emphasis.of(scene).look;
    final highlighted = emphasis.layout ? emphasis.events : null;
    final from = v.lo - v.span * .5, to = v.hi + v.span * .5;
    // 달 · 날 눈금인가, 화면이 한 해 안에 드는가 — 날짜 글을 다듬는 두 조건.
    final subRuler = spanYears < 2;
    final loYear = DateTime.fromMillisecondsSinceEpoch((v.lo * 60000).round(), isUtc: true).year;
    final hiYear = DateTime.fromMillisecondsSinceEpoch((v.hi * 60000).round(), isUtc: true).year;
    final oneYear = loYear == hiYear;
    // 날짜 글을 다듬는 방식은 이 두 조건뿐이다 — 타일에 걸어 둔 글과 폭은 방식이 그대로면 그대로 쓴다.
    final dateMode = !subRuler ? 0 : (oneYear ? 2 : 1);

    // 1) 타일마다 보이는 줄 · 보이는 시간 범위에 든 구간만 짚는다(타일 하나에 사건이 8천 개까지 들어 있다).
    final segments = <(Tile, int, double, int, int, int, int)>[]; // 타일 · 줄 · 메움의 끝 · 사건 [처음, 끝) · 알약 [처음, 끝)
    int eventMax = 0, pillMax = 0;
    final own = {for (final d in scene.draw) if (!d.isCover) d.key};
    final tiles = <Tile>{};
    for (final d in scene.draw) {
      if (d.isCover && own.contains(d.key)) continue; // 떠오르는 제 타일 밑에 깔린 메움
      if (d.ghost) continue; // 사라지는 줄에 잘라 그리는 직전 조합의 타일 — 이름 자리는 새 조합의 타일로만
      final t = d.tile;
      tiles.add(t);
      final lo = d.isCover ? tileOrigin(d.key.level, d.key.x).toDouble() : double.negativeInfinity;
      final hi = d.isCover ? tileOrigin(d.key.level, d.key.x + 1).toDouble() : double.infinity;
      final rowLo = d.key.chunk * chunkRows, rowHi = rowLo + chunkRows - 1;
      final first = rowLo > firstRow ? rowLo : firstRow, last = rowHi < lastRow ? rowHi : lastRow;
      final lower = (lo > from ? lo : from) - t.origin, upper = (hi < to ? hi : to) - t.origin;
      for (int r = first; r <= last; r++) {
        if (!layout.hasBody(r)) continue;
        final (eventFrom, eventTo) = t.eventsIn(r, lower, upper);
        final (pillFrom, pillTo) = t.pillsIn(r, lower, upper);
        if (eventTo == eventFrom && pillTo == pillFrom) continue;
        segments.add((t, r, hi, eventFrom, eventTo, pillFrom, pillTo));
        eventMax += eventTo - eventFrom;
        pillMax += pillTo - pillFrom;
      }
    }

    // 2) 하위 사건(구역 32): 부모의 기간이 문턱(90px)보다 넓으면 펼치고, 아니면 자식을 빼고 부모에 하위 수 알약을 붙인다.
    //    한 번 펼쳐지면 8% 더 좁아져야 다시 접힌다(문턱 둘) — 지난 판의 열쇠를 이력으로 쓴다.
    final was = {...?previous?.expandedKeys};
    final expanded = <int>{}, childWide = <int, bool>{};
    for (final t in tiles) {
      final sec = t.section(32);
      if (sec.count == 0) continue;
      final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
      final ref = sec.u(Tile.itemRef), a = sec.u(Tile.itemA), b = sec.u(Tile.itemB), cc = sec.u(Tile.itemC);
      for (int i = 0; i < sec.count; i++) {
        final start = t.origin + x0[i], key = _parentKey(start, a[i]);
        final limit = (b[i] == 0 ? 90.0 : b[i].toDouble()) * (was.contains(key) ? 1 - (cc[i] == 0 ? 80 : cc[i]) / 1000 : 1);
        final wide = (x1[i] - x0[i]) * v.ppm >= limit;
        if (wide) expanded.add(key);
        childWide[ref[i]] = wide || (childWide[ref[i]] ?? false);
      }
    }

    // 3) 채운다.
    final at = Float64List(eventMax), bandLo = Float64List(eventMax), bandHi = Float64List(eventMax);
    final precLo = Float64List(eventMax), precHi = Float64List(eventMax);
    final width = Float32List(eventMax), yearWidth = Float32List(eventMax), countWidth = Float32List(eventMax), size = Float32List(eventMax);
    final drawName = Float32List(eventMax), drawYear = Float32List(eventMax);
    final row = Int32List(eventMax), importance = Int32List(eventMax), id = Int32List(eventMax), index = Int32List(eventMax);
    final band = Int32List(eventMax), kids = Int32List(eventMax), color = Int32List(eventMax);
    final look = Uint32List(eventMax);
    final dates = List<String>.filled(eventMax, '');
    // 관점(lens)이 준 이름 — 답이 비어 있으면(기본 관점) 자리도 잡지 않는다.
    final lens = LensTitles.of(scene);
    final lensNames = lens.events;
    final lensTitle = lensNames.isEmpty ? null : List<String?>.filled(eventMax, null);
    final pillLo = Float64List(pillMax), pillHi = Float64List(pillMax);
    final pillRow = Int32List(pillMax), pillRest = Int32List(pillMax);
    final hold = segments.isEmpty ? <Tile>[] : List<Tile>.filled(eventMax, segments.first.$1);
    // 통마다의 분류 비율(자료 처리부가 알약 구역에 열을 더하면 채워진다 — 4절 참조).
    final catAt = Int32List(pillMax + 1), cats = <int>[], catCounts = <int>[];
    var anyCats = false;
    // 띠를 못 찾으면 분류 색으로 떨어진다(지금 연표의 `e.polityColor || e.color`와 같은 떨어짐).
    final fallback = [for (final c in layout.categories) 0xff000000 | c.color];
    int n = 0, p = 0;
    for (final (t, r, hi, eventFrom, eventTo, pillFrom, pillTo) in segments) {
      final rowSize = EventFont.sizeOf(layout, r), rowLines = layout.geo(r).textLines;
      final memo = _labelsOf(t)..setMode(dateMode);
      final pillCats = _pillCatColumns(t);
      for (int i = pillFrom; i < pillTo; i++) {
        final minute = t.origin + t.pillX0[i];
        if (minute >= hi) continue; // 메움의 자리는 끝을 포함하지 않는다
        pillLo[p] = minute;
        pillHi[p] = t.origin + t.pillX1[i];
        pillRow[p] = r;
        pillRest[p] = t.pillRest[i];
        catAt[p] = cats.length;
        if (pillCats != null) {
          for (int k = pillCats.at[i]; k < pillCats.at[i + 1]; k++) {
            cats.add(pillCats.cat[k]);
            catCounts.add(pillCats.count[k]);
            anyCats = true;
          }
        }
        p++;
      }
      for (int i = eventFrom; i < eventTo; i++) {
        // 기간이 있는 사건도 글줄에는 점과 이름으로 선다(지금 연표의 `.tl-ev`) — 기간 막대 칸(구역 33~36)은 그와 별개다.
        final minute = t.origin + t.eventX0[i];
        if (minute >= hi) continue;
        final bits = t.eventLook[i];
        // 접힌 부모의 자식은 아예 보이지 않는다.
        if (EventLook.child(bits) && childWide[t.eventId[i]] == false) continue;
        final imp = t.importanceOf(i);
        final child = EventLook.child(bits);
        final kidCount = EventLook.kids(bits);
        at[n] = minute;
        row[n] = r;
        importance[n] = imp;
        id[n] = t.eventId[i];
        look[n] = bits;
        band[n] = t.eventBand[i];
        size[n] = rowSize;
        kids[n] = kidCount > 0 && !expanded.contains(_parentKey(minute, kidCount)) ? kidCount : 0;
        // 관점이 이 사건의 이름을 주었으면 그 글로 적고 **그 글의 폭으로** 자리를 잡는다(명세 06 8-15).
        final renamed = lensNames.isEmpty ? null : lensNames[t.eventId[i]];
        if (renamed != null) lensTitle![n] = renamed;
        final nameSize = child ? rowSize - .5 : rowSize;
        final drawn = imp < least || EventLook.pair(bits)
            ? double.nan
            : (renamed != null
                  ? lens.widthOf(t.eventId[i], renamed, EventFont.name(nameSize, imp, bits), EventText.widthOf)
                  : _nameWidth(t, i, nameSize, imp));
        drawName[n] = drawn;
        // 자리 셈에는 글자 수 × 0.14px을 더한 폭을 준다(지금 연표의 `textWidth`가 그만큼 넉넉하다 — 명세 10.9).
        width[n] = drawn.isNaN ? drawn : drawn + EventFont.placeSpacing * (renamed ?? t.text(t.eventName[i])).length;
        // 날짜 글은 글줄이 둘 이상인 줄의, 하위가 아닌 사건에만. 다듬은 글과 그 폭은 타일에 걸어 둔다(배율과 무관).
        final label = rowLines > 1 && !child ? (memo.dateText[i] ??= _dateText(t.text(t.eventLabel[i]), subRuler, oneYear)) : '';
        dates[n] = label;
        if (label.isEmpty || width[n].isNaN) {
          drawYear[n] = 0;
        } else {
          if (memo.dateSize[i] != rowSize) {
            memo.dateWidth[i] = EventText.widthOf(label, EventFont.year(rowSize)).clamp(0.0, 1e4);
            memo.dateSize[i] = rowSize;
          }
          drawYear[n] = memo.dateWidth[i];
        }
        yearWidth[n] = drawYear[n] == 0 ? 0 : drawYear[n] + EventFont.placeSpacing * label.length;
        countWidth[n] = kids[n] == 0 || width[n].isNaN ? 0 : _countWidth(kids[n], rowSize);
        hold[n] = t;
        index[n] = i;
        final argb = _findBand(t, i, memo);
        bandLo[n] = t.eventBandLo[i];
        bandHi[n] = t.eventBandHi[i];
        final cat = EventLook.category(bits);
        color[n] = argb != 0 ? argb : (cat < fallback.length ? fallback[cat] : 0xffa4b1b7);
        // 정밀도 구간(달력 셈): 끝이 있는 사건 · 미정인 사건은 제 시각에 그대로 선다. 배율과 무관해 타일에 걸어 둔다.
        if (memo.precDone[i] == 0) {
          memo.precDone[i] = 1;
          final span = t.eventX1[i] > t.eventX0[i] || EventLook.unknown(bits) ? null : _precSpan(minute, (t.eventRail[i] >> 8) & 7);
          memo.precLo[i] = span?.$1 ?? double.nan;
          memo.precHi[i] = span?.$2 ?? double.nan;
        }
        precLo[n] = memo.precLo[i];
        precHi[n] = memo.precHi[i];
        n++;
      }
    }
    catAt[p] = cats.length;
    // 이름과 점이 비켜 갈 구간(건국 · 멸망 네모 · 소속/대범위 단추 · 내림줄): 관계선 층이 장면마다 적어 둔 것을 줄 차례로 편다.
    final reserved = ReservedZones.of(scene);
    final rows = lastRow >= firstRow ? lastRow - firstRow + 1 : 0;
    final zoneAt = Int32List(rows + 1);
    final lo = <double>[], hi = <double>[];
    final line = <int>[], noDot = <int>[], sq = <int>[], dir = <int>[];
    // 줄마다의 구간 **생김새** 지문 — 구간이 달라진 줄에서는 이름 이력을 한 번 버린다(labels.dart의 `zoneSig`).
    // 자리(분)는 넣지 않는다: 배율이 흐르는 동안 `ReservedZones.version`은 장면마다 오르는데(네모의 분 자리가 ppm만큼
    // 미세하게 달라진다) 그때마다 이력을 버리면 이름이 확대 내내 깜박인다. 구간이 생기거나 사라지거나 갈래가 바뀔 때에만 달라진다.
    // **세기 0인 구간만** 센다: 이름 줄 전체를 막는 것(소속 · 대범위 단추 · 내림줄)이라야 한 장면 늦게 와서 이름을
    // 잘못 눌러앉힌다. 건국 · 멸망 네모(세기 1 · 2)는 글자 상자만 밀 뿐인데, 그 네모는 화면 가장자리를 넘나들 때마다
    // 생겼다 사라진다(links.dart의 `showF`/`showE`가 `c.left` · `c.w`로 자른다) — 그것까지 세면 옆으로 끌 때마다
    // 그 줄의 이름 이력이 통째로 버려져 이름이 깜박인다.
    final sig = Int32List(rows);
    for (int r = firstRow; r <= lastRow; r++) {
      zoneAt[r - firstRow] = lo.length;
      var mark = 0;
      for (final z in reserved.at(r)) {
        lo.add(z.lo);
        hi.add(z.hi);
        line.add(z.line);
        noDot.add(z.noDot ? 1 : 0);
        sq.add(z.strength);
        dir.add(z.dir);
        if (z.strength != 0) continue;
        mark = (mark * 31 + Object.hash(z.line, z.noDot, z.strength, z.dir)) & 0x3fffffff;
      }
      sig[r - firstRow] = mark;
    }
    zoneAt[rows] = lo.length;
    final zoneLo = Float64List.fromList(lo), zoneHi = Float64List.fromList(hi);
    final zoneLine = Int32List.fromList(line), zoneNoDot = Int32List.fromList(noDot);
    final zoneSq = Int32List.fromList(sq), zoneDir = Int32List.fromList(dir);

    return LabelBatch._(
      LabelInput(
        version: version, pxPerMinute: v.ppm, spanYears: spanYears,
        at: Float64List.sublistView(at, 0, n), row: Int32List.sublistView(row, 0, n), importance: Int32List.sublistView(importance, 0, n),
        eventId: Int32List.sublistView(id, 0, n), look: Uint32List.sublistView(look, 0, n), band: Int32List.sublistView(band, 0, n),
        nameWidth: Float32List.sublistView(width, 0, n), yearWidth: Float32List.sublistView(yearWidth, 0, n), countWidth: Float32List.sublistView(countWidth, 0, n),
        kids: Int32List.sublistView(kids, 0, n),
        bandLo: Float64List.sublistView(bandLo, 0, n), bandHi: Float64List.sublistView(bandHi, 0, n),
        precLo: Float64List.sublistView(precLo, 0, n), precHi: Float64List.sublistView(precHi, 0, n),
        pillLo: Float64List.sublistView(pillLo, 0, p), pillHi: Float64List.sublistView(pillHi, 0, p),
        pillRow: Int32List.sublistView(pillRow, 0, p), pillRest: Int32List.sublistView(pillRest, 0, p), rowBase: firstRow,
        rowLines: Int32List.fromList([for (int r = firstRow; r <= lastRow; r++) layout.geo(r).textLines]),
        expandedKeys: Int32List.fromList(expanded.toList()),
        zoneAt: zoneAt, zoneLo: zoneLo, zoneHi: zoneHi, zoneLine: zoneLine, zoneNoDot: zoneNoDot, zoneSq: zoneSq, zoneDir: zoneDir, zoneSig: sig,
        pillCatAt: anyCats ? Int32List.sublistView(catAt, 0, p + 1) : null,
        pillCat: anyCats ? Int32List.fromList(cats) : null,
        pillCatCount: anyCats ? Int32List.fromList(catCounts) : null,
        selectedEventId: scene.selectedEventId ?? 0,
        highlighted: highlighted, bird: bird,
      ),
      hold,
      Int32List.sublistView(index, 0, n),
      dates.sublist(0, n),
      Int32List.sublistView(color, 0, n),
      Float32List.sublistView(size, 0, n),
      Float32List.sublistView(drawName, 0, n),
      Float32List.sublistView(drawYear, 0, n),
      lensTitle?.sublist(0, n),
    );
  }
}

/// 하위 수 알약의 폭 — 수와 글자 크기만으로 정해진다. 장면마다 · 후보마다 다시 재지 않는다.
final _countWidths = <int, double>{};

double _countWidth(int kids, double size) =>
    _countWidths[(kids << 8) | (size * 4).round()] ??= EventText.widthOf('$kids', EventFont.countMeasure(size)).clamp(0.0, 1e4);

/// 통의 분류 비율 열(계약 5절 구역 4 · 5-2): 굳은 네 열(x0 · x1 · 나머지 개수 · 줄) 뒤의 다섯째 열. 없으면 색줄은 예전처럼 대표의 분류로만 셈한다.
const _pillFixedColumns = 4;

/// 알약 구역의 다섯째 열(엔진 계약 5-2): 통 **전체**의 분류별 수를 적은 글 `"<분류>:<개수>,…"`(분류 번호 오름차순)의 글자 번호.
/// 실을 것이 없는 저장소는 그 열을 아예 싣지 않는다(열 수 4) — 없는 열을 읽으면 0(글자표의 첫 글)이 오므로 **열 수를 먼저 본다**.
/// 글을 푸는 일은 타일마다 한 번만(타일에 걸어 둔다).
class _PillCats {
  _PillCats(this.at, this.cat, this.count);

  /// 알약 i의 몫은 [cat] · [count]의 `at[i] ..< at[i + 1]`.
  final Int32List at;
  final List<int> cat, count;
}

final Expando<Object> _pillCatsOf = Expando<Object>('pillCats');
const _noPillCats = Object();

_PillCats? _pillCatColumns(Tile t) {
  final known = _pillCatsOf[t];
  if (known != null) return known is _PillCats ? known : null;
  final sec = t.section(Tile.secPill);
  if (sec.columns <= _pillFixedColumns || sec.count == 0) {
    _pillCatsOf[t] = _noPillCats;
    return null;
  }
  final ids = sec.u(_pillFixedColumns);
  final at = Int32List(sec.count + 1);
  final cat = <int>[], count = <int>[];
  for (int i = 0; i < sec.count; i++) {
    at[i] = cat.length;
    for (final part in t.text(ids[i]).split(',')) {
      final k = part.indexOf(':');
      if (k <= 0) continue;
      final c = int.tryParse(part.substring(0, k)), many = int.tryParse(part.substring(k + 1));
      if (c == null || many == null || many <= 0) continue;
      cat.add(c);
      count.add(many);
    }
  }
  at[sec.count] = cat.length;
  final made = _PillCats(at, cat, count);
  _pillCatsOf[t] = made;
  return made;
}

