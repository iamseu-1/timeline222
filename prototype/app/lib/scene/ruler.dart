// 날짜 칸의 눈금 계산. 규칙은 지금 연표에서 옮겼다(js/timeline.js의 AXIS_STEPS · _stepAt · _past · _draw 5699~5820줄, js/calendar.js의 SUB · subTicks):
// 연도 눈금은 사이가 96px 이상인 가장 촘촘한 간격(성겨질 때는 88px까지 버팀), 해보다 작은 눈금은 단위마다 문턱이 있다.
//
// 지금 연표의 '해 좌표'에는 0년이 **빈 자리**로 들어 있다(기원전 1년 = −1 · 기원후 1년 = 1 · 0은 아무 해도 아닌 칸).
// 분 축에는 그 빈 자리가 없어서 해 좌표 0과 −1은 같은 분을 가리킨다 — 간격이 1년일 때만 0을 건너뛴다(그때만 −1과 겹친다).
// 그래서 보기의 폭을 해로 셀 때는 0을 건너뛴 만큼 한 해를 더 센다([yearsBetween]) — 모서리의 'N년 보기'가 지금 연표와 같게.

import 'aux_calendar.dart';

const _yearSteps = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000];
const _ganjiSteps = [1, 2, 5, 10, 20, 30];
const _stems = '갑을병정무기경신임계', _branches = '자축인묘진사오미신유술해';
const _yearMinutes = 525960.0; // 365.25일
const _minPx = 96.0, _ganjiPx = 26.0, _gap = .08;

/// 일진(날마다의 간지)이 나오는 문턱: 하루가 26px 넘게 보일 때(지금 연표의 `_past('ganjiDay', dayW, 26)`).
const _ganjiDayPx = 26.0;

/// 보조 달력 줄이 열리는 문턱: 해보다 작은 눈금이고 한 달이 18px 넘게 보일 때(`_past('calOpen', k / 12, 18)`).
const _calOpenPx = 18.0;

/// 일진을 한 화면에 500칸까지만 만든다(지금 연표와 같은 안전장치).
const _maxDays = 500;

/// 해보다 작은 눈금: (이름, 분으로 친 어림 너비, 문턱 px). 촘촘한 것부터 — js/calendar.js의 SUB 그대로.
const _subSteps = [
  ('1시간', 60.0, 46.0), ('3시간', 180.0, 46.0), ('6시간', 360.0, 46.0), ('12시간', 720.0, 46.0),
  ('1일', 1440.0, 40.0), ('2일', 2880.0, 40.0), ('5일', 7200.0, 44.0), ('10일', 14400.0, 48.0),
  ('1개월', 43830.0, 58.0), ('3개월', 131490.0, 62.0), ('6개월', 262980.0, 66.0),
];

/// 며칠마다의 눈금이 서는 날(js/calendar.js의 DAY_MARKS). 1 · 2는 따로 센다.
const _dayMarks = {5: [1, 6, 11, 16, 21, 26], 10: [1, 11, 21]};

/// 천문학적 해(0년 있음)의 간지.
String ganjiOf(int astronomicalYear) {
  final i = (astronomicalYear - 4) % 60;
  return _stems[i % 10] + _branches[i % 12];
}

/// 해 좌표의 60갑자 번호(0 = 갑자). 지금 연표의 HT.ganjiIndex.
int ganjiIndexOf(int year) => ((year < 0 ? year + 1 : year) - 4) % 60;

/// 해 좌표 → 눈금 이름(지금 연표의 HT.formatAxisYear — '년'을 붙이지 않는다).
String yearLabel(int year) => year < 0 ? '기원전 ${-year}' : '$year';

/// 해 좌표 → 해 글(지금 연표의 yearText).
String yearText(int year) => year < 0 ? '기원전 ${-year}년' : '$year년';

/// 지금 연표의 해 좌표(정수 N = N년 1월 1일 · 기원전 1년 = −1 · 0은 빈 자리) → 1970년 기준 분.
/// 내보내기(scripts/export/base.mjs의 minute) · 그림 뜨기 검사와 같은 투영이다.
double minuteOfYear(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year).millisecondsSinceEpoch.toDouble();
  final b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1)).millisecondsSinceEpoch.toDouble();
  return (a + (b - a) * (y - year)) / 60000;
}

/// 분 → 해 좌표. 빈 자리(0)는 나오지 않는다 — 기원전 1년은 −1이다.
double yearAt(double minute) {
  final ms = minute * 60000;
  final astronomical = DateTime.fromMillisecondsSinceEpoch(ms.floor(), isUtc: true).year;
  final a = DateTime.utc(astronomical).millisecondsSinceEpoch.toDouble();
  final b = DateTime.utc(astronomical + 1).millisecondsSinceEpoch.toDouble();
  return (astronomical <= 0 ? astronomical - 1 : astronomical) + (ms - a) / (b - a);
}

/// 두 해 좌표 사이의 해 수. 해 좌표에는 0년 자리가 비어 있어서, 0을 건너뛰는 구간은 실제 시간보다 한 해가 더 세어진다 —
/// 지금 연표의 span(`end - start`)과 같은 값이다(전체 장면의 −1500~1500은 3,000년).
double yearsBetween(double from, double to) => to - from;

/// 보기의 폭을 해로(모서리 글 'N년 보기').
String spanText(double years) {
  if (years >= 10) return '${_grouped(years.round())}년';
  if (years >= 2) return '${years.toStringAsFixed(1)}년';
  final days = years * 365.25;
  if (days >= 60) return '약 ${(days / 30.44).round()}개월';
  if (days >= 2) return '${days.round()}일';
  final hours = (days * 24).round();
  return '${hours < 1 ? 1 : hours}시간';
}

String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// 눈금 하나. [end]는 한 칸 걸러 깔리는 바탕 띠의 오른쪽 끝(다음 눈금)이고, 마지막 눈금은 무한이다.
class Tick {
  const Tick(this.minute, this.end, this.label, {this.shown = true, this.major = false, this.band = false, this.zero = false});
  final double minute, end;
  final String label;

  /// 보기 왼쪽 밖의 눈금은 바탕 띠만 깔고 눈금선 · 이름은 그리지 않는다(지금 연표의 `shown`).
  final bool shown;

  /// 윗단위가 바뀌는 눈금(1월 · 1일 · 0시) — 이름을 짙게.
  final bool major;

  /// 이 눈금부터 다음 눈금까지 바탕 띠를 깐다.
  final bool band;

  /// 0년 자리의 눈금 — 눈금선을 파선으로.
  final bool zero;
}

/// 간지 줄의 모습.
enum GanjiMode {
  /// 확대하면 간지가 보입니다.
  hint,

  /// 날마다 이어진 둥근 칸(일진) — 하루가 26px을 넘을 때.
  days,

  /// 해마다 이어진 둥근 칸.
  cells,

  /// 몇 해마다 눈금.
  ticks,

  /// 60년마다 갑자년.
  gapja,
}

/// 간지 줄의 한 칸(또는 눈금). [end]는 칸일 때만 쓴다.
class GanjiMark {
  const GanjiMark(this.start, this.end, this.name, this.index, {this.year = '', this.alt = false});
  final double start, end;
  final String name;

  /// 60갑자 번호(0 = 갑자 — 강조).
  final int index;

  /// 눈금에 곁들이는 연도 글(없으면 빈 글).
  final String year;

  /// 한 칸 걸러 짙은 바탕(`is-alt`). 해마다는 간지 번호가 홀수일 때, 일진은 날 번호가 홀수일 때다.
  final bool alt;
}

class RulerModel {
  const RulerModel({
    required this.unit, required this.ticks, required this.sub, required this.spanYears,
    required this.ganjiMode, required this.ganjiStep, required this.ganji, required this.context, required this.calOpen,
  });

  /// 눈금 간격의 이름(예: '10년', '1개월').
  final String unit;
  final List<Tick> ticks;

  /// 해보다 작은 눈금인가.
  final bool sub;

  /// 보기의 폭(해).
  final double spanYears;

  final GanjiMode ganjiMode;

  /// 간지 줄의 간격(년). 눈금 · 칸이 아니면 0.
  final int ganjiStep;
  final List<GanjiMark> ganji;

  /// 해보다 작은 눈금일 때 모서리에 굵게 적는 지금 자리(`HT.cal.context` — '827년 5월'). 해 눈금이면 빈 글.
  final String context;

  /// 보조 달력 줄이 열려 있는가(한 달이 18px을 넘을 때 — 문턱 둘).
  final bool calOpen;
}

class Ruler {
  YearCycle? _cycle;
  double _cycleNeed = 26;
  int? _yearStep, _ganjiStep;
  final _memory = <String, bool>{};
  RulerModel? _last;
  double _lastLo = 0, _lastHi = 0, _lastPpm = 0;

  /// 문턱 두 개: v가 th 이상이면 켜지고, 한 번 켜지면 th의 92% 아래로 내려가야 꺼진다(지금 연표의 `_past`).
  bool _past(String key, double v, double th) => _memory[key] = (_memory[key] ?? false) ? v >= th * (1 - _gap) : v >= th;

  /// 간격의 이력: 더 촘촘한 간격이 문턱을 채우면 그리로 가고, 지금 간격은 문턱의 92%까지 버틴다.
  static int? _step(List<int> steps, double pxPerYear, double minPx, int? current) {
    int? ideal;
    for (final s in steps) {
      if (s * pxPerYear >= minPx) {
        ideal = s;
        break;
      }
    }
    if (current == null || ideal == null) return ideal;
    if (ideal < current) return ideal;
    return current * pxPerYear >= minPx * (1 - _gap) ? current : ideal;
  }

  RulerModel compute(double lo, double hi, double ppm, {YearCycle? cycle, double cycleNeed = 26}) {
    if (!identical(_cycle, cycle) || _cycleNeed != cycleNeed) {
      _cycle = cycle;
      _cycleNeed = cycleNeed;
      _last = null;
      _ganjiStep = null;
      _memory.removeWhere((key, _) => key.startsWith('cycle'));
    }
    if (_last != null && lo == _lastLo && hi == _lastHi && ppm == _lastPpm) return _last!;
    final pxPerYear = ppm * _yearMinutes;
    final startYear = yearAt(lo), endYear = yearAt(hi);
    final ticks = <Tick>[];
    String unit;
    (String, double, double)? sub;
    for (final s in _subSteps) {
      if (s.$2 * ppm >= s.$3) {
        sub = s;
        break;
      }
    }
    if (sub != null) {
      unit = sub.$1;
      _yearStep = 1;
      _subTicks(ticks, sub, lo, hi);
    } else {
      final step = _yearStep = _step(_yearSteps, pxPerYear, _minPx, _yearStep) ?? _yearSteps.last;
      unit = '$step년';
      _yearTicks(ticks, step, startYear, endYear);
    }
    final (ganjiMode, ganjiStep, ganji) = _ganji(pxPerYear, startYear, endYear);
    // 모서리의 굵은 글과 보조 달력 줄은 해보다 작은 눈금일 때만(지금 연표의 `cal.context` · `_past('calOpen', k / 12, 18)`).
    final calOpen = _past('calOpen', sub == null ? 0 : pxPerYear / 12, _calOpenPx);
    _lastLo = lo;
    _lastHi = hi;
    _lastPpm = ppm;
    return _last = RulerModel(
      unit: unit, ticks: ticks, sub: sub != null, spanYears: yearsBetween(startYear, endYear),
      ganjiMode: ganjiMode, ganjiStep: ganjiStep, ganji: ganji,
      context: sub == null ? '' : contextText(startYear, sub.$1), calOpen: calOpen,
    );
  }

  /// 해보다 작은 눈금일 때 모서리에 굵게 적는 글(`HT.cal.context`): 달 눈금이면 '827년' · 날이면 '827년 5월' · 시면 '827년 5월 12일'.
  static String contextText(double startYear, String unit) {
    final at = dayAt(startYear);
    final c = civilOf(at.j);
    if (unit.endsWith('개월')) return yearText(at.y);
    if (unit.endsWith('일')) return '${yearText(at.y)} ${c.m}월';
    return '${yearText(at.y)} ${c.m}월 ${c.d}일';
  }

  /// 연도 눈금은 해 좌표의 배수에 선다. 보기 왼쪽 밖의 한 칸도 넣는다(바탕 띠를 거기서부터 깔려고).
  static void _yearTicks(List<Tick> out, int step, double startYear, double endYear) {
    final first = (startYear / step).ceil() * step;
    for (int t = first - step; t <= endYear; t += step) {
      if (t == 0 && step == 1) continue; // 해 좌표 0은 빈 자리 — 간격이 1년이면 −1(기원전 1년)과 같은 분이다
      out.add(Tick(
        minuteOfYear(t.toDouble()), minuteOfYear((t + step).toDouble()), yearLabel(t),
        shown: t >= first, band: (t / step).round() % 2 == 0, zero: t == 0,
      ));
    }
  }

  /// 해보다 작은 눈금(달 · 날 · 시간). 윗단위가 바뀌는 눈금은 짙게, 한 칸 걸러 바탕 띠.
  static void _subTicks(List<Tick> out, (String, double, double) sub, double lo, double hi) {
    final name = sub.$1;
    final made = <(double, String, bool, int)>[]; // (분, 이름, major, 띠 번호)
    final from = DateTime.fromMillisecondsSinceEpoch((lo * 60000).floor(), isUtc: true);
    double at(int y, [int m = 1, int d = 1, int h = 0]) => DateTime.utc(y, m, d, h).millisecondsSinceEpoch / 60000;
    String yearOf(int astronomical) => yearText(astronomical <= 0 ? astronomical - 1 : astronomical);
    if (name.endsWith('개월')) {
      final n = int.parse(name.substring(0, name.length - 2));
      var y = from.year, m = ((from.month - 1) ~/ n) * n + 1;
      // 보기 왼쪽 밖의 한 칸부터
      m -= n;
      if (m < 1) {
        m += 12;
        y--;
      }
      while (true) {
        final t = at(y, m);
        if (t > hi) break;
        made.add((t, m == 1 ? yearOf(y) : '$m월', m == 1, ((y * 12 + m - 1) / n).floor()));
        m += n;
        if (m > 12) {
          m -= 12;
          y++;
        }
      }
    } else if (name.endsWith('일')) {
      final n = int.parse(name.substring(0, name.length - 1));
      final marks = _dayMarks[n];
      var y = from.year, m = from.month;
      if (--m < 1) {
        m = 12;
        y--;
      }
      while (true) {
        if (at(y, m) > hi) break;
        final length = DateTime.utc(y, m + 1, 0).day;
        for (int d = 1; d <= length; d++) {
          final ok = n == 1 ? true : (n == 2 ? d.isOdd && d < 31 : marks!.contains(d));
          if (!ok) continue;
          final t = at(y, m, d);
          if (t > hi) break;
          final index = n == 1 ? (t / 1440).floor() : (n == 2 ? (t / 2880).floor() : (y * 12 + m) * marks!.length + marks.indexOf(d));
          made.add((t, d == 1 ? (m == 1 ? '${yearOf(y)} 1월' : '$m월') : '$d일', d == 1, index));
        }
        m++;
        if (m > 12) {
          m = 1;
          y++;
        }
      }
    } else {
      final n = int.parse(name.substring(0, name.length - 2));
      var y = from.year, m = from.month, d = from.day;
      var day = DateTime.utc(y, m, d).subtract(const Duration(days: 1));
      y = day.year;
      m = day.month;
      d = day.day;
      while (true) {
        if (at(y, m, d) > hi) break;
        for (int h = 0; h < 24; h += n) {
          final t = at(y, m, d, h);
          if (t > hi) break;
          made.add((t, h == 0 ? '$m월 $d일' : '$h시', h == 0, (t / (n * 60)).floor()));
        }
        day = day.add(const Duration(days: 1));
        y = day.year;
        m = day.month;
        d = day.day;
      }
    }
    // 0년 자리는 건너뛰고, 보기 시작 전의 눈금은 하나만 남긴다(그 눈금부터 바탕 띠를 깐다).
    var first = made.indexWhere((x) => x.$1 >= lo);
    if (first > 0) {
      first -= 1;
    } else if (first < 0) {
      first = made.length - 1;
    }
    for (int i = first < 0 ? 0 : first; i < made.length; i++) {
      final x = made[i];
      out.add(Tick(x.$1, i + 1 < made.length ? made[i + 1].$1 : double.infinity, x.$2, shown: x.$1 >= lo, major: x.$3, band: x.$4.isEven));
    }
  }

  (GanjiMode, int, List<GanjiMark>) _ganji(double pxPerYear, double startYear, double endYear) {
    if (_cycle?.custom == true) return _customCycle(pxPerYear, startYear, endYear);
    final step = _ganjiStep = _step(_ganjiSteps, pxPerYear, _ganjiPx, _ganjiStep);
    final out = <GanjiMark>[];
    // 하루가 26px을 넘으면 날마다의 간지(일진) — 지금 연표는 간격보다 이 문턱을 먼저 본다.
    if (_past('ganjiDay', pxPerYear / 365.25, _ganjiDayPx)) {
      final j0 = dayAt(startYear).j, j1 = dayAt(endYear).j;
      for (int j = j0; j <= j1 && out.length < _maxDays; j++) {
        out.add(GanjiMark(
          minuteOfYear(tOfJdn(j)), minuteOfYear(dayEndT(j)), dayGanji(j), dayGanjiIndex(j),
          alt: j.isOdd,
        ));
      }
      return (GanjiMode.days, 0, out);
    }
    if (step == 1) {
      for (int y = startYear.floor(); y <= endYear.ceil(); y++) {
        if (y == 0) continue;
        // 해 좌표 −1의 다음은 1이다(0은 빈 자리).
        out.add(GanjiMark(
          minuteOfYear(y.toDouble()), minuteOfYear(y == -1 ? 1 : y + 1.0), ganjiOf(y < 0 ? y + 1 : y), ganjiIndexOf(y),
          alt: ganjiIndexOf(y).isOdd,
        ));
      }
      return (GanjiMode.cells, 1, out);
    }
    if (step != null) {
      final withYear = _past('ganjiYear$step', step * pxPerYear, 64);
      for (int y = (startYear / step).floor() * step; y <= endYear; y += step) {
        if (y == 0) continue;
        final at = minuteOfYear(y.toDouble());
        out.add(GanjiMark(at, at, ganjiOf(y < 0 ? y + 1 : y), ganjiIndexOf(y), year: withYear ? yearLabel(y) : ''));
      }
      return (GanjiMode.ticks, step, out);
    }
    if (_past('ganji60', pxPerYear * 60, 56)) {
      // 넓게 볼 때는 60년마다 돌아오는 갑자년만. 천문학적 해로 세고(4년마다 갑자) 해 좌표로 되돌린다.
      // (지금 연표도 그렇듯 이 갈래에는 닿지 않는다 — 30년이 26px에 못 미치려면 한 해가 0.87px 아래여야 하는데,
      //  그때는 60년도 56px에 못 미친다. 문턱을 고칠 때를 위해 지금 연표의 식을 그대로 옮겨 둔다.)
      final firstAstronomical = ((startYear - 4) / 60).ceil() * 60 + 4;
      for (int a = firstAstronomical; a <= endYear; a += 60) {
        final y = a <= 0 ? a - 1 : a;
        out.add(GanjiMark(minuteOfYear(y.toDouble()), 0, '갑자', 0, year: yearLabel(y)));
      }
      return (GanjiMode.gapja, 0, out);
    }
    return (GanjiMode.hint, 0, const []);
  }

  /// 이름 폭 문턱과 첫 해 눈금은 웹의 순환 줄과 같다. 사용자 순환은 날의 일진으로 바뀌지 않는다.
  (GanjiMode, int, List<GanjiMark>) _customCycle(double px, double lo, double hi) {
    final cycle = _cycle!;
    final step = _ganjiStep = _step(_ganjiSteps, px, _cycleNeed, _ganjiStep);
    final out = <GanjiMark>[];
    if (step == 1) {
      for (int y = lo.floor(); y <= hi.ceil(); y++) {
        if (y == 0) continue;
        out.add(GanjiMark(minuteOfYear(y.toDouble()), minuteOfYear(y == -1 ? 1 : y + 1.0), cycle.name(y), cycle.index(y), alt: cycle.index(y).isOdd));
      }
      return (GanjiMode.cells, 1, out);
    }
    if (step != null) {
      final withYear = _past('cycleYear$step', step * px, _cycleNeed + 38);
      for (int y = (lo / step).floor() * step; y <= hi; y += step) {
        if (y == 0) continue;
        final at = minuteOfYear(y.toDouble());
        out.add(GanjiMark(at, at, cycle.name(y), cycle.index(y), year: withYear ? yearLabel(y) : ''));
      }
      return (GanjiMode.ticks, step, out);
    }
    if (_past('cycleRound', px * cycle.length, _cycleNeed + 30 > 56 ? _cycleNeed + 30 : 56)) {
      for (final y in cycle.firstYears(lo, hi)) {
        out.add(GanjiMark(minuteOfYear(y.toDouble()), 0, cycle.names.first, 0, year: yearLabel(y)));
      }
      return (GanjiMode.gapja, 0, out);
    }
    return (GanjiMode.hint, 0, const []);
  }
}
