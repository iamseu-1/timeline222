import 'dart:math' as math;

import '../scene/ruler.dart' show ganjiOf;
import 'date_text.dart' as dt;

// 검색 입력을 읽는 순수 함수만 둔다 — 화면도 자료 처리부도 모른다(검사: test/search_parse_test.dart).
// 규칙은 지금 연표에서 옮겼다: js/viewer.js의 dateQuery · GANJI_ONLY · jumpSpan · focusOn ①, js/calendar.js의 parse.
// 시간은 모두 1970-01-01 UTC 기준 정수 분(계약 0절)이고, 밖으로 오가는 해는 모두 **천문 해**다 — 0년 = 기원전 1년.
//
// 날짜 글 읽기는 `date_text.dart`의 [dt.readAt] 하나에 모았다(상세 창이 쓰는 것과 같은 함수다).
// **분으로 옮기는 길도 하나다**: 글 → 날 번호(1582-10-15 앞은 율리우스력) → 해 좌표 → 분.
// 마지막 걸음이 내보내기(`scripts/export/base.mjs`의 `minute`)와 같은 투영이라, 검색이 찾는 자리와
// 사건이 실린 자리가 한 분도 어긋나지 않는다. (프롤렙틱 그레고리력으로 곧바로 셈하면 율리우스력 윤년이
// 어긋나는 세기 해 — 100 · 200 · 300 · 500 … — 에서 최대 하루가 밀린다. 2026-09-22에 고쳤다.)

/// 한 해 · 한 달 · 하루의 분. 보기 폭을 가둘 때만 쓰는 어림값이다.
const double yearMinutes = 525960, monthMinutes = 43830, dayMinutes = 1440;

/// 날짜를 적은 자세함.
enum Prec { year, month, day, hour, minute }

/// 자료 처리부가 쓰는 한 글자 이름('y' · 'm' · 'd' · 'h' · 'min')으로 오가기.
Prec precOf(Object? code) => switch (code) {
  'm' => Prec.month,
  'd' => Prec.day,
  'h' => Prec.hour,
  'min' => Prec.minute,
  _ => Prec.year,
};
String precCode(Prec prec) => switch (prec) {
  Prec.year => 'y',
  Prec.month => 'm',
  Prec.day => 'd',
  Prec.hour => 'h',
  Prec.minute => 'min',
};

/// 천문 해(0년 있음)의 첫 분. **해 단위에만 쓴다** — 해의 경계는 분 축의 경계와 같다.
/// (달·날까지 주면 프롤렙틱 그레고리력으로 곧바로 셈하므로 1582년 앞에서는 연표의 자리와 어긋난다.
///  날짜 글을 분으로 옮기는 일은 [parseDate]가 날 번호를 거쳐서 한다.)
int minuteOf(int year, [int month = 1, int day = 1, int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).millisecondsSinceEpoch ~/ 60000;

/// 분이 든 천문 해.
int yearAt(num minute) => DateTime.fromMillisecondsSinceEpoch((minute * 60000).round(), isUtc: true).year;

/// 천문 해 → 사람이 읽는 글('1592년' · '기원전 960년').
String yearText(int year) => year > 0 ? '$year년' : '기원전 ${1 - year}년';

/// 읽어 낸 날짜 하나. [t]는 그 단위의 첫 분, [end]는 마지막 분이다(양 끝 포함 — 계약 0절과 같은 셈).
class DateQuery {
  const DateQuery({
    required this.t,
    required this.end,
    required this.prec,
    required this.label,
    required this.year,
    this.cal = 'civil',
    this.note = '',
  });

  /// 그 단위의 첫 분과 마지막 분.
  final int t, end;
  final Prec prec;

  /// 목록 맨 위 줄에 쓰는 글('기원전 108년' · '1592년 5월 23일').
  final String label;

  /// 천문 해.
  final int year;

  /// 달력 이름('civil' · 'dangi' · 'chinese' · 'islamic' · 'umalqura' · 'persian' · 'gregorian' · 'julian').
  final String cal;

  /// 아직 못 하는 것을 적어 두는 자리(달의 시작 표가 없어 환산하지 못했다 …). 없으면 빈 글.
  final String note;
}

/// 입력 하나를 세 갈래로 동시에 읽은 것(명세 5-1).
class SearchQuery {
  const SearchQuery({required this.raw, required this.terms, this.date, this.ganji = ''});
  const SearchQuery.empty() : raw = '', terms = const [], date = null, ganji = '';

  /// 앞뒤 빈칸만 없앤 입력.
  final String raw;

  /// 공백으로 나눈 낱말(소문자) — 모두 들어 있어야 맞는 것이다.
  final List<String> terms;
  final DateQuery? date;

  /// 간지 두 글자('갑오'). 간지가 아니면 빈 글.
  final String ganji;

  bool get isEmpty => raw.isEmpty;

  /// 이 입력으로 물어볼 갈래. 날짜 · 간지로 읽혔으면 칸 · 가문 · 하위 문서는 빼고 묻는다(지금 연표와 같다).
  List<String> get kinds => date != null || ganji.isNotEmpty
      ? const ['event', 'treaty', 'period', 'dynasty', 'culture', 'organ', 'figure', 'epoch', 'scope']
      : const ['event', 'treaty', 'period', 'dynasty', 'culture', 'organ', 'figure', 'epoch', 'scope', 'cell', 'house', 'doc'];
}

/// 입력 하나를 낱말 · 날짜 · 간지로 한꺼번에 읽는다.
/// [cals]는 보조 달력의 '달의 시작 표'를 찾아 주는 것 — 앱에서는 `AuxCalendarStore.shared?.table`을 넘긴다.
SearchQuery parseSearch(String input, {dt.AuxTables? cals}) {
  final raw = input.trim();
  if (raw.isEmpty) return const SearchQuery.empty();
  return SearchQuery(
    raw: raw,
    terms: raw.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList(growable: false),
    date: parseDate(raw, cals: cals),
    ganji: parseGanji(raw),
  );
}

// ---- 간지 ----

const _stems = '갑을병정무기경신임계', _branches = '자축인묘진사오미신유술해';
final _ganjiOnly = RegExp('^\\s*([$_stems][$_branches])\\s*년?\\s*\$');

/// 입력이 간지 하나면 그 두 글자, 아니면 빈 글('갑오' · '임진년' → '임진').
String parseGanji(String input) => _ganjiOnly.firstMatch(input)?.group(1) ?? '';

/// [lo]~[hi](천문 해)의 ±60년에서 그 간지에 해당하는 해들을 **[center]에 가까운 순**으로.
/// 60년마다 돌아오므로 연대순으로 주면 쓸모가 없다(명세 ㈐-15).
List<int> ganjiYears(String ganji, {required int center, required int lo, required int hi, int limit = 60}) {
  if (parseGanji(ganji).isEmpty) return const [];
  final from = lo - 60, to = hi + 60;
  final years = <int>[];
  int? first;
  for (int y = from; y < from + 60 && y <= to; y++) {
    if (ganjiOf(y) == ganji) {
      first = y;
      break;
    }
  }
  if (first == null) return const [];
  for (int y = first; y <= to; y += 60) {
    years.add(y);
  }
  years.sort((a, b) {
    final d = (a - center).abs() - (b - center).abs();
    return d != 0 ? d : a - b;
  });
  return years.length > limit ? years.sublist(0, limit) : years;
}

// ---- 날짜 ----

/// 날짜로 읽어 볼 검색어: 연도만, 또는 세 자리 이상 수 · '년' · 기원전이 든 것('3.1'처럼 짧은 수는 이름으로 찾는다).
final _yearOnly = RegExp(r'^\s*(?:기원전|BC|B\.C\.)?\s*-?\d{1,5}\s*년?\s*$', caseSensitive: false);
final _dateHint = RegExp(r'\d{3}|년|기원전|서기전|B\.?\s?C', caseSensitive: false);

/// 날짜 글의 자세함을 검색의 자세함으로.
Prec _precFrom(dt.DatePrec prec) => switch (prec) {
  dt.DatePrec.year => Prec.year,
  dt.DatePrec.month => Prec.month,
  dt.DatePrec.day => Prec.day,
  dt.DatePrec.hour => Prec.hour,
  dt.DatePrec.minute => Prec.minute,
};

/// 검색어가 날짜 하나뿐이면 그 날짜, 아니면 null('1592' · '기원전 108' · '1592년 5월' · '1592-05-23' · '음력 1592-04-13').
///
/// [cals]를 넘기면 음력 · 중국 음력 · 이슬람력 · 움 알쿠라 · 페르시아력으로 **적은** 날짜도 그 달력으로 되짚어
/// 진짜 그날을 찾는다. 넘기지 않거나 표가 그 달을 덮지 않으면 예전처럼 적은 해를 서력의 그해로 보고 찾고,
/// 그렇다고 [DateQuery.note]에 적어 둔다.
DateQuery? parseDate(String input, {dt.AuxTables? cals}) {
  cals ??= dt.defaultAuxTables;
  final s = input.trim();
  if (s.isEmpty) return null;
  if (!(_yearOnly.hasMatch(s) || _dateHint.hasMatch(s))) return null;
  final p = dt.readAt(s, cals: cals);
  if (p == null) return null;

  // 표가 없어 못 셈한 달력 — 적은 해를 서력의 그해로 보고 찾는다.
  if (!p.exact) {
    final written = p.year < 0 ? p.year + 1 : p.year;
    return DateQuery(
      t: minuteOf(written),
      end: minuteOf(written + 1) - 1,
      prec: Prec.year,
      label: dt.atText(p),
      year: written,
      cal: p.cal,
      note: '${p.name} 환산은 아직 — 서력 ${yearText(written)}으로 찾습니다',
    );
  }

  // 글 → 날 번호 → 해 좌표 → 분. 마지막 걸음이 내보내기와 같은 투영이다(글 첫머리).
  final table = p.isCivil || cals == null ? null : cals(p.cal);
  final t = dt.minutesOfT(p.t).round();
  final end = dt.minutesOfT(dt.unitEnd(p.t, p.prec, cal: table)).round() - 1;
  final civilYear = dt.civilAt(p.t).year;
  return DateQuery(
    t: t,
    end: end,
    prec: _precFrom(p.prec),
    // 서력이 아니면 지금 연표처럼 서력을 곁들인다('음력 1592년 4월 13일 (양력 5월 23일)' — js/viewer.js의 dateQuery).
    label: p.isCivil ? dt.formatT(p.t, p.prec) : dt.atText(p),
    year: civilYear < 0 ? civilYear + 1 : civilYear,
    cal: p.cal,
  );
}

// ---- 가는 곳 ----

/// 한 시점으로 갈 때의 보기 폭(분): 지금 폭을 그 자세함에 맞는 범위 안으로(지금 연표의 jumpSpan).
/// 해 1.6~[yearMax]년 · 달 1.5개월~2년 · 날 4일~2개월 · 시각 6시간~4일.
double jumpSpan(Prec prec, double span, {double yearMax = 200}) {
  final (lo, hi) = switch (prec) {
    Prec.year => (1.6 * yearMinutes, yearMax * yearMinutes),
    Prec.month => (1.5 * monthMinutes, 2 * yearMinutes),
    Prec.day => (4 * dayMinutes, 2 * monthMinutes),
    Prec.hour || Prec.minute => (6 * 60.0, 4 * dayMinutes),
  };
  return !span.isFinite || span <= 0 ? lo : span.clamp(lo, hi);
}

/// 날짜 결과로 갈 곳: 그 해 · 달 · 날의 한가운데가 보기 한가운데에 오게(지금 연표의 goToDate).
(double, double) dateRange(DateQuery date, double span, {double yearMax = 200}) {
  final width = jumpSpan(date.prec, span, yearMax: yearMax);
  final center = (date.t + date.end + 1) / 2;
  return (center - width / 2, center + width / 2);
}

/// 항목 결과로 갈 곳(지금 연표의 focusOn ①): 기간이 있으면 기간 × 2.2, 점이면 지금 폭을 그 자세함 안으로.
/// 해 30~160년 · 달 2~5년 · 날 두 달~반년 · 시각 사흘~열흘.
(double, double) itemRange({required num start, num? end, Prec prec = Prec.year, double span = 0}) {
  final (lo, hi) = switch (prec) {
    Prec.year => (30 * yearMinutes, 160 * yearMinutes),
    Prec.month => (2 * yearMinutes, 5 * yearMinutes),
    Prec.day => (60 * dayMinutes, .5 * yearMinutes),
    Prec.hour || Prec.minute => (3 * dayMinutes, 10 * dayMinutes),
  };
  final length = math.max(0.0, ((end ?? start) - start).toDouble());
  final width = length > 0 ? math.max(length * 2.2, math.min(lo, 30 * yearMinutes)) : (!span.isFinite || span <= 0 ? lo : span.clamp(lo, hi));
  final center = start + length / 2;
  return (center - width / 2, center + width / 2);
}
