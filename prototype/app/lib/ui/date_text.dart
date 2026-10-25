import 'dart:math' as math;

import '../scene/aux_calendar.dart' show AuxCalendarTable;

/// 보조 달력의 '달의 시작 표'를 찾아 주는 것 — 부르는 쪽이 넘긴다(앱에서는 `AuxCalendarStore.shared?.table`).
/// 넘기지 않으면(null) 서력 · 그레고리력 · 율리우스력만 셈하고, 나머지 달력은 앞말만 떼고 서력으로 읽는다.
typedef AuxTables = AuxCalendarTable? Function(String calId);

// ════════════════════════════════════════════════════════════════════════════════════════════
//  날짜 글 규칙 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-4절
//
//  지금 연표(js/calendar.js · js/core.js · js/viewer.js:40~150)의 글과 같은 글이 나오게 옮긴 순수 함수들이다.
//  시간의 단위는 **해 좌표**다(항목 기록 entities의 start · end가 쓰는 값): 정수 N = N년 1월 1일,
//  기원전 N년 = −N, **0년 자리는 없다**(기원전 1년 다음이 1년이라 좌표 [0, 1)은 빈 자리다).
//  1582년 10월 15일 앞은 율리우스력, 그 뒤는 그레고리력으로 센다.
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    yearText(-960)                         → '기원전 960년'
//    formatT(t, DatePrec.day)               → '827년 5월 12일'
//    precFor(보기 폭(년))                    → 그 폭에 맞는 자세함
//    spanRange(a, b)                        → '1592년 5월 3일 ~ 20일'
//    whenText(t, at: '827-05-12')           → 날짜 글이 값과 맞으면 그 글, 아니면 서력 날짜
//    endText(t, now: …)                     → 오늘과 같으면 '현재'
//    rangeText(start: …, end: …, …)         → 항목의 기간 줄('미정' · '~ 현재'까지)
//    durationText(a, b, prec)               → '1,200년' · '3년 2개월' · '3개월 12일 (104일)'
//    gapText(a, b, aAt: …, bAt: …)          → 조약 날짜 진행 표의 사이 간격
//    dayNote(t, lunar: 표)                   → '음력 4월 13일 · 경진일 · 토요일'
//    unknownStartNote · cellUnknownEndNote  → 미정 안내 한 줄
//    rangeNote('시작', lo, hi)               → '시작 — 이르면 …, 늦으면 …'
//    readAt('음력 1592-04-13', cals: 표들)    → 읽은 조각([AtParts] — 달력 · 해 · 달 · 윤달 · 날 · 날 번호 · 해 좌표)
//
//  ※ **보조 달력의 표는 밖에서 넣어 준다.** Dart에는 음력을 셈할 산수가 없어, 넣을 때 한 번 ICU로 뜬
//    '달의 시작 표'를 쓴다(`scene/aux_calendar.dart` · 계약 6-3절). 이 글의 함수들은 모두 순수 함수이므로
//    표를 부르는 쪽이 [cals]로 넘긴다 — 앱에서는 받아 두는 곳이 하나다(`AuxCalendarStore.shared?.table`).
//    곁들임([dayNote]의 `lunar`)도 같은 표다.
//  ※ **표를 넘기지 않으면 예전 그대로다**: 음력 따위 다른 달력의 앞말은 떼고 적힌 수를 서력으로 읽는다
//    ([AtParts.exact]가 거짓). 그래서 [atFits]가 어긋나 [whenText]는 셈해 둔 서력 날짜를 적는다.
//    표를 넘기면 지금 연표처럼 `음력 1592년 4월 13일 (양력 5월 23일)`로 적는다(`HT.cal.describe`).
//  ※ **불기**(`불기 2567-01-01`)는 표가 없어도 셈한다 — 서력의 해에 543을 더할 뿐이라 지금 연표도 산수로 바꾼다(`offset`).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 날짜의 자세함.
enum DatePrec { year, month, day, hour, minute }

/// 해 좌표 하나를 달력으로 푼 것.
class CivilAt {
  const CivilAt({required this.year, required this.month, required this.day, required this.jdn, required this.frac, required this.yearDays});

  /// 연표 연도(기원전은 음수 · 0 없음).
  final int year;
  final int month, day;

  /// 날 번호(JDN).
  final int jdn;

  /// 그날 안의 비율(0~1).
  final double frac;

  /// 그해의 날수.
  final int yearDays;
}

const _eps = 1e-9;

/// 그레고리력 첫날(1582-10-15)의 날 번호.
const gregorianStart = 2299161;

int _fl(double v) => v.floor();

int _jdnG(int y, int m, int d) {
  final a = ((14 - m) / 12).floor();
  final yy = y + 4800 - a, mm = m + 12 * a - 3;
  return d + ((153 * mm + 2) / 5).floor() + 365 * yy + (yy / 4).floor() - (yy / 100).floor() + (yy / 400).floor() - 32045;
}

int _jdnJ(int y, int m, int d) {
  final a = ((14 - m) / 12).floor();
  final yy = y + 4800 - a, mm = m + 12 * a - 3;
  return d + ((153 * mm + 2) / 5).floor() + 365 * yy + (yy / 4).floor() - 32083;
}

(int, int, int) _fromG(int j) {
  final a = j + 32044;
  final b = ((4 * a + 3) / 146097).floor();
  final c = a - ((146097 * b) / 4).floor();
  final d = ((4 * c + 3) / 1461).floor();
  final e = c - ((1461 * d) / 4).floor();
  final m = ((5 * e + 2) / 153).floor();
  return (100 * b + d - 4800 + (m / 10).floor(), m + 3 - 12 * (m / 10).floor(), e - ((153 * m + 2) / 5).floor() + 1);
}

(int, int, int) _fromJ(int j) {
  final c = j + 32082;
  final d = ((4 * c + 3) / 1461).floor();
  final e = c - ((1461 * d) / 4).floor();
  final m = ((5 * e + 2) / 153).floor();
  return (d - 4800 + (m / 10).floor(), m + 3 - 12 * (m / 10).floor(), e - ((153 * m + 2) / 5).floor() + 1);
}

/// 천문 연도(0 = 기원전 1년) ↔ 연표 연도.
int _toAstro(int y) => y < 0 ? y + 1 : y;
int _fromAstro(int a) => a <= 0 ? a - 1 : a;

bool _beforeGreg(int y, int m, int d) => y < 1582 || (y == 1582 && (m < 10 || (m == 10 && d < 15)));

/// 연표 연도의 날짜 → 날 번호(1582-10-15 앞은 율리우스력).
int jdnOf(int year, int month, int day) {
  final ay = _toAstro(year);
  return _beforeGreg(ay, month, day) ? _jdnJ(ay, month, day) : _jdnG(ay, month, day);
}

/// 날 번호 → 연표 연도의 날짜.
CivilAt civilOfJdn(int jdn) {
  final (ay, m, d) = jdn < gregorianStart ? _fromJ(jdn) : _fromG(jdn);
  final y = _fromAstro(ay);
  return CivilAt(year: y, month: m, day: d, jdn: jdn, frac: 0, yearDays: _yearDays(ay));
}

int _yearStart(int ay) => ay <= 1582 ? _jdnJ(ay, 1, 1) : _jdnG(ay, 1, 1);
int _yearDays(int ay) => _yearStart(ay + 1) - _yearStart(ay);

/// 해 좌표 → 달력 조각. 0년 자리는 1년 1월 1일로 본다.
CivilAt civilAt(double t) {
  int y = _fl(t + _eps);
  double pos = t - y;
  if (y == 0) {
    y = 1;
    pos = 0;
  }
  final ay = _toAstro(y), start = _yearStart(ay), len = _yearStart(ay + 1) - start;
  final dayPos = math.max(0.0, pos) * len;
  int di = _fl(dayPos + 1e-7);
  if (di >= len) di = len - 1;
  final frac = math.max(0.0, math.min(1.0, dayPos - di));
  final jdn = start + di;
  final (_, m, d) = jdn < gregorianStart ? _fromJ(jdn) : _fromG(jdn);
  return CivilAt(year: y, month: m, day: d, jdn: jdn, frac: frac, yearDays: len);
}

/// 날 번호(+ 그날 안의 비율) → 해 좌표.
double tOfJdn(int jdn, [double frac = 0]) {
  var ay = (jdn < gregorianStart ? _fromJ(jdn) : _fromG(jdn)).$1;
  while (jdn < _yearStart(ay)) {
    ay--;
  }
  while (jdn >= _yearStart(ay + 1)) {
    ay++;
  }
  final start = _yearStart(ay);
  return _fromAstro(ay) + (jdn - start + frac) / (_yearStart(ay + 1) - start);
}

/// 1970-01-01의 날 번호. 계약의 시간(분)은 이 날 0시를 0으로 센다.
const jdnEpoch = 2440588;

/// 그해의 양 끝(분). 내보내기(`prototype/scripts/export/base.mjs`의 `minute`)와 **같은 투영**이다 —
/// 자바스크립트의 `Date`를 쓰므로 1582년 앞도 그레고리력으로 셈한다(화면에 적는 날짜는 율리우스력이라 옛날로 갈수록 며칠 어긋난다.
/// 연표의 가로 자리는 해 좌표의 비례로만 정해지므로 이 어긋남은 자리에 영향을 주지 않는다).
(double, double) _yearEdges(int year) {
  final ay = year < 0 ? year + 1 : year;
  final nextAy = year == -1 ? 1 : (year < 0 ? year + 2 : year + 1);
  return ((_jdnG(ay, 1, 1) - jdnEpoch) * 1440.0, (_jdnG(nextAy, 1, 1) - jdnEpoch) * 1440.0);
}

/// 해 좌표 → 계약의 시간(1970-01-01 UTC 기준 분). `bus.goTo`에 넘길 값이다.
/// 빈 0년 자리는 [civilAt]과 똑같이 1년 1월 1일로 본다(기원전 1년의 다음 해 끝을 셈할 때 거기에 떨어진다).
double minutesOfT(double t) {
  final year = t.floor();
  if (year == 0) return minutesOfT(1);
  final (a, b) = _yearEdges(year);
  return (a + (b - a) * (t - year)).roundToDouble();
}

/// 계약의 시간(분) → 해 좌표.
double tOfMinutes(double minutes) {
  final jdn = (minutes / 1440).floor() + jdnEpoch;
  var year = _fromAstro(_fromG(jdn).$1);
  var (a, b) = _yearEdges(year);
  while (minutes < a) {
    year = year == 1 ? -1 : year - 1;
    (a, b) = _yearEdges(year);
  }
  while (minutes >= b) {
    year = year == -1 ? 1 : year + 1;
    (a, b) = _yearEdges(year);
  }
  return year + (minutes - a) / (b - a);
}

// ── 한 시점의 글 ────────────────────────────────────────────────────────────────────────────

/// `827년` · `기원전 960년`.
String yearText(int year) => year < 0 ? '기원전 ${-year}년' : '$year년';

/// 해 좌표 → 서력 날짜 글.
String formatT(double? t, [DatePrec prec = DatePrec.day]) {
  if (t == null || !t.isFinite) return '';
  final a = civilAt(t);
  if (prec == DatePrec.year) return yearText(a.year);
  var s = '${yearText(a.year)} ${a.month}월';
  if (prec == DatePrec.month) return s;
  s += ' ${a.day}일';
  if (prec == DatePrec.day) return s;
  final mins = (a.frac * 1440).round();
  final h = math.min(23, (mins / 60).floor());
  final mi = prec == DatePrec.minute ? mins - h * 60 : 0;
  return '$s $h시${mi != 0 ? ' $mi분' : ''}';
}

/// 보기 폭(년)에 맞는 자세함 — 12년 넘으면 해, 아홉 달 넘으면 달, 나흘 넘으면 날, 그보다 좁으면 시각.
DatePrec precFor(double spanYears) =>
    spanYears > 12 ? DatePrec.year : (spanYears > .75 ? DatePrec.month : (spanYears > 4 / 365.25 ? DatePrec.day : DatePrec.hour));

/// 두 시점을 한 자세함으로. 같은 해면 뒤쪽의 겹치는 앞부분을 줄인다.
String spanRange(double a, double b, [DatePrec? prec]) {
  final p = prec ?? precFor(b - a);
  final s = formatT(a, p);
  var e = formatT(b, p);
  if (e == s) return s;
  final ya = formatT(a, DatePrec.year);
  if (p != DatePrec.year && formatT(b, DatePrec.year) == ya) {
    final ra = s.substring(ya.length + 1).split(' ');
    final rb = e.substring(ya.length + 1).split(' ');
    var i = 0;
    while (i < rb.length - 1 && ra[i] == rb[i]) {
      i++;
    }
    e = rb.sublist(i).join(' ');
  }
  return '$s ~ $e';
}

// ── 날짜 글(`startAt` · `endAt` …) ──────────────────────────────────────────────────────────
//
//  지금 연표의 `HT.cal.parse`(js/calendar.js 232~380줄)를 그대로 옮겼다. 읽는 차례도 같다:
//  ① 전각 숫자 · 천 단위 쉼표 · 겹친 빈칸 고르기 ② 달력 말보다 앞에 온 '기원전'을 뒤로 옮기기
//  ③ 달력 말(앞말 · 뒷말 · 뒤 괄호) ④ 어림 말('무렵' · 'c.') ⑤ 기원전 · 기원후 ⑥ 한글 꼴 · 숫자 꼴
//  ⑦ 오전 · 오후 ⑧ 값 살피기 ⑨ 날 번호로 셈하기.
//
//  달력은 넷으로 나뉜다:
//   · 서력(`civil`) — 1582-10-15 앞은 율리우스력. 그레고리력 · 율리우스력을 못박은 것도 여기서 산수로 센다.
//   · 표가 있어야 하는 것(음력 · 중국 음력 · 이슬람력 · 움 알쿠라 · 페르시아력 · 히브리력 · 에티오피아력 · 콥트력 · 사카력)
//     — [AuxTables]로 넘긴 표를 되짚는다.
//     표가 없거나 **그 달**이 표 밖이면 예전 그대로 적힌 수를 서력으로 읽고 [AtParts.exact]를 거짓으로 둔다
//     (표의 양 끝 해는 반 토막이라 해는 표 안인데 달은 표 밖인 자리가 있다 — `AuxCalendarTable.coversDate`).
//     13월(히브리력 윤년 · 에티오피아력 · 콥트력)은 서력에 없으므로 그때는 해까지만 읽는다.
//   · 서력의 해만 옮긴 것(불기 — 서력 + 543) — 표 없이 서력 산수로 센다(지금 연표의 `offset`).

/// 날짜 글에 쓰는 달력 하나(지금 연표의 `HT.cal.CALENDARS`).
class _Cal {
  const _Cal(
    this.id,
    this.name,
    this.prefix,
    this.words, {
    this.lunar = false,
    this.table = false,
    this.era = false,
    this.maxMonth = 12,
    this.offset = 0,
  });

  /// 번호 · 이름 · 표준 글의 앞말.
  final String id, name, prefix;

  /// 날짜 글 앞(또는 뒤 괄호)에 붙여 이 달력을 고르는 말.
  final List<String> words;

  /// 음력(한국 · 중국) — 음력 곁들임을 두 번 붙이지 않게 가리는 값이다([isLunarAt]).
  final bool lunar;

  /// '달의 시작 표'가 있어야 셈할 수 있는 달력.
  final bool table;

  /// 1년부터만 적을 수 있는 달력(이슬람력 · 페르시아력 · 히브리력 · 에티오피아력 · 콥트력 · 사카력 · 불기의 기원 — 지금 연표의 `era`).
  final bool era;

  /// 한 해의 달 수의 끝(지금 연표의 `maxMonth`) — 13째 달이 있는 달력만 13.
  final int maxMonth;

  /// 서력(천문 연도)의 해에 더하는 수(지금 연표의 `offset` — 불기 543). 0이 아니면 표 없이 서력 산수로 센다.
  final int offset;
}

/// 차례 · 번호 · 이름 · 앞말 · 낱말은 지금 연표의 `HT.cal.CALENDARS`(js/calendar.js) 그대로다
/// (히브리력 ~ 불기는 2026-10-24 리메이크 6단계 결정 D10에 더했다).
const _cals = <_Cal>[
  _Cal('civil', '양력', '', ['양력', '서력']),
  _Cal('gregorian', '그레고리력', '그레고리력 ', ['그레고리력', '그레고리오력', '신력']),
  _Cal('julian', '율리우스력', '율리우스력 ', ['율리우스력', '구력']),
  _Cal('dangi', '음력', '음력 ', ['한국 음력', '음력', '陰曆', '음'], lunar: true, table: true),
  _Cal('chinese', '중국 음력', '중국 음력 ', ['중국 음력', '농력', '農曆', '农历'], lunar: true, table: true),
  _Cal('islamic', '이슬람력', '이슬람력 ', ['이슬람력', '히즈라력', '히즈라', '회교력', 'AH'], table: true, era: true),
  _Cal('umalqura', '이슬람력(움 알쿠라)', '움알쿠라 ', ['움 알쿠라', '움알쿠라'], table: true, era: true),
  _Cal('persian', '페르시아력', '페르시아력 ', ['페르시아력', '이란력', '태양 히즈라력'], table: true, era: true),
  _Cal('hebrew', '히브리력', '히브리력 ', ['히브리력', '유대력'], table: true, era: true, maxMonth: 13),
  _Cal('ethiopic', '에티오피아력', '에티오피아력 ', ['에티오피아력'], table: true, era: true, maxMonth: 13),
  _Cal('coptic', '콥트력', '콥트력 ', ['콥트력'], table: true, era: true, maxMonth: 13),
  _Cal('indian', '사카력', '사카력 ', ['사카력', '인도 국정력'], table: true, era: true),
  _Cal('buddhist', '불기', '불기 ', ['불기', '타이 불기'], era: true, offset: 543),
];

/// 달력을 고르는 말 — 긴 것부터 맞춘다(`음력`이 `음`보다 먼저).
final _calWords = <(String, _Cal)>[
  for (final c in _cals)
    for (final w in c.words) (w, c),
]..sort((a, b) => b.$1.length - a.$1.length);

/// 날짜 글 하나를 읽은 것.
class AtParts {
  const AtParts({
    required this.cal,
    required this.name,
    required this.year,
    required this.prec,
    required this.t,
    this.month,
    this.leap = false,
    this.day,
    this.hour,
    this.minute,
    this.jdn,
    this.lunar = false,
    this.exact = true,
  });

  /// 달력 번호(`civil` · `gregorian` · `julian` · `dangi` · `chinese` · `islamic` · `umalqura` · `persian` ·
  /// `hebrew` · `ethiopic` · `coptic` · `indian` · `buddhist`).
  final String cal;

  /// 달력 이름(`음력`). 서력이면 `양력`.
  final String name;

  /// **그 달력의** 해(연표 연도 — 기원전은 음수 · 0 없음)와 달 · 날 · 시 · 분. 적지 않은 칸은 null.
  final int year;
  final int? month, day, hour, minute;

  /// 윤달로 적었는가(음력만).
  final bool leap;

  /// 적은 만큼의 자세함.
  final DatePrec prec;

  /// 날 번호. 해만 적은 서력에는 없다(그해 1월 1일이 아니라 해 좌표 그 자체이므로).
  final int? jdn;

  /// 해 좌표.
  final double t;

  /// 음력(한국 · 중국)으로 적었는가.
  final bool lunar;

  /// 그 달력으로 **셈해서** 얻은 값인가. 거짓이면 표가 없어 적힌 수를 서력으로 읽은 것이다.
  final bool exact;

  bool get isCivil => cal == 'civil';
}

const _timePattern = r'(?:\s*(?:T|\s)\s*(?:(오전|오후|AM|PM)\s*)?(\d{1,2})(?::(\d{2})|\s*시(?:\s*(\d{1,2})\s*분)?)(?:\s*(AM|PM))?)?';
final _reKo = RegExp(r'^(\d+)\s*년(?:\s*(윤)?\s*(\d{1,2})\s*월(?:\s*(\d{1,2})\s*일)?)?' '$_timePattern' r'$', caseSensitive: false);
final _reNum = RegExp(r'^(\d+)(?:\s*([-./])\s*(윤)?(\d{1,2})(?:\s*\2\s*(\d{1,2}))?\.?)?' '$_timePattern' r'$', caseSensitive: false);
const _bcWord = r'(?:기원전|서기전|B\.?\s?C\.?(?:\s?E\.?)?)';
const _adWord = r'(?:기원후|서기|A\.?\s?D\.?|C\.?\s?E\.?)';
final _reBcHead = RegExp('^$_bcWord\\s*', caseSensitive: false);
final _reBcTail = RegExp('\\s*$_bcWord\$', caseSensitive: false);
final _reBcMid = RegExp('^(\\d+)\\s*(?:년\\s*)?$_bcWord\\s*(?=[-./\\s]|\$)', caseSensitive: false);
final _reAdHead = RegExp('^$_adWord\\s*', caseSensitive: false);
final _reBcLead = RegExp('^($_bcWord)\\s*(.+)\$', caseSensitive: false);
final _reAbout = RegExp(r'\s*(?:경|무렵|께|쯤)$');
final _reCirca = RegExp(r'^(?:c\.|ca\.|약)\s*', caseSensitive: false);
final _reFullWidth = RegExp('[０-９]');
final _reThousands = RegExp(r'(\d),(?=\d{3}(?!\d))');
final _reSpaces = RegExp(r'\s+');
final _reParen = RegExp(r'\s*[(（]\s*([^)）]+?)\s*[)）]\s*$');
final _reAfterWord = RegExp(r'^\s*[:：]?\s*[-\d기서BbAaCc]');
final _reColon = RegExp(r'^\s*[:：]?\s*');

int? _num(RegExpMatch m, int i) {
  final v = m.group(i);
  return v == null || v.isEmpty ? null : int.tryParse(v);
}

/// 부르는 쪽이 [cals]를 넘기지 않았을 때 쓸 보조 달력 표 — 앱이 저장소를 열 때 한 번 채운다(`archive_app.dart`).
/// 이 값이 비어 있으면(검사 · 도구) 예전 그대로 적힌 수를 서력으로 읽는다. 순수 함수 꼴은 그대로다 — `cals:`를 넘기면 그쪽이 이긴다.
/// 상세 창 · 도구 · 검색의 날짜 글 부름이 서른 곳 가까이라 자리마다 넘기는 대신 한 자리에서 잇는다(11물결 dates ⑵).
AuxTables? defaultAuxTables;

/// 날짜 글을 읽는다 — 못 읽으면 null. [cals]를 넘기면 음력 따위도 그 달력으로 셈한다.
AtParts? readAt(String? text, {AuxTables? cals}) {
  cals ??= defaultAuxTables;
  if (text == null) return null;
  var s = text
      .replaceAllMapped(_reFullWidth, (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xfee0))
      .replaceAllMapped(_reThousands, (m) => m.group(1)!)
      .replaceAll(_reSpaces, ' ')
      .trim();
  if (s.isEmpty) return null;

  // 기원전 말이 달력 말보다 앞에 오면('기원전 음력 100-01-01') 달력 말 뒤로 옮긴다.
  final lead = _reBcLead.firstMatch(s);
  if (lead != null) {
    final rest = lead.group(2)!;
    for (final (word, _) in _calWords) {
      if (rest.toLowerCase().startsWith(word.toLowerCase())) {
        s = '${rest.substring(0, word.length)} ${lead.group(1)} ${rest.substring(word.length).trim()}';
        break;
      }
    }
  }

  // 달력: 뒤 괄호('… (음력)') · 앞말('음력 …') · 뒷말('… 음력').
  var cal = _cals.first;
  final paren = _reParen.firstMatch(s);
  if (paren != null) {
    for (final (word, c) in _calWords) {
      if (word.toLowerCase() == paren.group(1)!.toLowerCase()) {
        cal = c;
        s = s.substring(0, paren.start).trim();
        break;
      }
    }
  }
  if (cal.id == 'civil') {
    final low = s.toLowerCase();
    for (final (word, c) in _calWords) {
      final lw = word.toLowerCase();
      if (low.length > lw.length && low.startsWith(lw) && _reAfterWord.hasMatch(s.substring(word.length))) {
        cal = c;
        s = s.substring(word.length).replaceFirst(_reColon, '');
        break;
      }
      if (low.length > lw.length && low.endsWith(lw) && s[s.length - word.length - 1] == ' ') {
        cal = c;
        s = s.substring(0, s.length - word.length).trim();
        break;
      }
    }
  }

  // 어림('경' · '무렵' · 'c.')과 기원전 · 기원후.
  s = s.replaceFirst(_reAbout, '').replaceFirst(_reCirca, '').trim();
  var bc = false;
  if (_reBcHead.hasMatch(s)) {
    bc = true;
    s = s.replaceFirst(_reBcHead, '');
  } else if (_reBcTail.hasMatch(s)) {
    bc = true;
    s = s.replaceFirst(_reBcTail, '');
  } else if (_reBcMid.hasMatch(s)) {
    bc = true;
    s = s.replaceFirstMapped(_reBcMid, (m) => m.group(1)!);
  } else if (_reAdHead.hasMatch(s)) {
    s = s.replaceFirst(_reAdHead, '');
  }
  if (s.startsWith('-')) {
    bc = true;
    s = s.substring(1).trim();
  }

  int year;
  int? month, day, hour, minute;
  var leap = false;
  String half;
  final ko = _reKo.firstMatch(s);
  if (ko != null) {
    year = int.parse(ko.group(1)!);
    leap = ko.group(2) != null;
    month = _num(ko, 3);
    day = _num(ko, 4);
    hour = _num(ko, 6);
    minute = _num(ko, 7) ?? _num(ko, 8);
    half = (ko.group(5) ?? ko.group(9) ?? '').toUpperCase();
  } else {
    final nu = _reNum.firstMatch(s);
    if (nu == null) return null;
    year = int.parse(nu.group(1)!);
    leap = nu.group(3) != null;
    month = _num(nu, 4);
    day = _num(nu, 5);
    hour = _num(nu, 7);
    minute = _num(nu, 8) ?? _num(nu, 9);
    half = (nu.group(6) ?? nu.group(10) ?? '').toUpperCase();
  }
  if (hour != null && (half == '오후' || half == 'PM') && hour < 12) hour += 12;
  if (hour != null && (half == '오전' || half == 'AM') && hour == 12) hour = 0;
  if (bc) year = -year;

  // 0년 자리는 비어 있다 — 기원전 1년 다음 해가 1년이다(지금 연표는 '0' 한 글자만 해 좌표 0으로 받지만,
  // 새 축에는 그 자리가 아예 없어 여기서는 받지 않는다).
  if (year == 0) return null;
  // 13월은 13째 달이 있는 달력(히브리력 · 에티오피아력 · 콥트력)에서만 — 지금 연표의 '달은 1~12(13) 사이여야 합니다'.
  if (month != null && (month < 1 || month > cal.maxMonth)) return null;
  if (day != null && (day < 1 || day > 31)) return null;
  if (hour != null && (hour < 0 || hour > 23)) return null;
  if (minute != null && (minute < 0 || minute > 59)) return null;
  if (hour != null && day == null) return null; // 시각을 적으려면 날까지 적어야 한다.
  if (leap && !cal.lunar) return null; // 윤달은 음력에만 있다.
  return _buildAt(cal, year, month, leap, day, hour, minute, cals);
}

/// 읽은 조각을 해 좌표로 — 달력마다 다른 셈은 여기 하나에 모았다(지금 연표의 `cal.build`).
AtParts? _buildAt(_Cal cal, int year, int? month, bool leap, int? day, int? hour, int? minute, AuxTables? cals) {
  if (month == null) day = null;
  if (day == null) hour = minute = null;
  if (hour == null) minute = null;
  final prec = hour != null
      ? (minute != null && minute != 0 ? DatePrec.minute : DatePrec.hour)
      : (day != null ? DatePrec.day : (month != null ? DatePrec.month : DatePrec.year));
  final frac = hour == null ? 0.0 : (hour + (minute ?? 0) / 60) / 24;

  AtParts made(int? jdn, double t, {bool exact = true}) => AtParts(
    cal: cal.id,
    name: cal.name,
    year: year,
    month: month,
    leap: leap,
    day: day,
    hour: hour,
    minute: minute,
    prec: prec,
    jdn: jdn,
    t: t,
    lunar: cal.lunar,
    exact: exact,
  );

  // 해만 적은 서력은 해 좌표 그 자체다(1월 1일이 아니다 — 지금 연표의 build와 같다).
  if (cal.id == 'civil' && prec == DatePrec.year) return made(null, year.toDouble());

  // 서력의 해만 옮긴 달력(불기) — 지금 연표의 `cal.build`(offset 길): 해는 천문 연도 + offset, 달과 날은 서력 그대로라
  // 1582-10-15 앞은 율리우스력이고, 없는 날(2월 30일 …)은 되짚어 거른다. 표가 필요 없으므로 늘 셈해 낸다(exact).
  if (cal.offset != 0) {
    if (cal.era && year < 1) return null;
    final civilYear = _fromAstro(year - cal.offset);
    final jdn = jdnOf(civilYear, month ?? 1, day ?? 1);
    if (day != null && civilOfJdn(jdn).month != month) return null;
    return made(jdn, tOfJdn(jdn, frac));
  }

  if (cal.table) {
    if (cal.era && year < 1) return null; // 이슬람력 · 페르시아력 · 히브리력 … 은 1년부터.
    final table = cals == null ? null : cals(cal.id);
    // 가르는 것은 **그 달**이 표 안인가다(해가 아니다). 표는 서력 해로 끊어 떠 오므로 양 끝의 해는 반 토막이고,
    // 해만 보고 가르면 그 반 토막 밖의 달(`음력 2127-12-01` 따위)을 **못 읽은 글(null)**로 만든다 —
    // 그러면 검색도 그 글을 날짜가 아닌 것으로 보고 낱말로 떨어져 조용히 아무것도 못 찾는다(2026-09-22에 고친 자리).
    if (table != null && table.coversDate(year, month ?? 1, leap: leap)) {
      final jdn = table.jdnOfDate(year, month ?? 1, day ?? 1, leap: leap);
      if (jdn == null) return null; // 그해에 없는 윤달 · 그 달에 없는 날(표 안의 해이므로 이것은 잘못 적은 글이다).
      return made(jdn, tOfJdn(jdn, frac));
    }
    // 표가 없거나 표가 덮지 않는 달 — 예전 그대로 적힌 수를 서력으로 읽는다.
    // 윤달 · 13월은 서력에 없으므로 그때는 해까지만 읽는다(옛 [parseAt]도 윤달은 그랬다).
    if (leap || prec == DatePrec.year || month! > 12) {
      return AtParts(cal: cal.id, name: cal.name, year: year, prec: DatePrec.year, t: year.toDouble(), lunar: cal.lunar, exact: false);
    }
    final jdn = jdnOf(year, month, day ?? 1);
    return made(jdn, tOfJdn(jdn, frac), exact: false);
  }

  final ay = _toAstro(year);
  final jdn = switch (cal.id) {
    'gregorian' => _jdnG(ay, month ?? 1, day ?? 1),
    'julian' => _jdnJ(ay, month ?? 1, day ?? 1),
    _ => jdnOf(year, month ?? 1, day ?? 1),
  };
  if (day != null) {
    // 없는 날(2월 30일 …)은 다음 달로 넘어가므로 되돌려 보아 거른다.
    // (서력 1582년 10월 5~14일은 율리우스력의 날로 받아들인다 — 지금 연표와 같다.)
    final back = switch (cal.id) {
      'gregorian' => _fromG(jdn).$2,
      'julian' => _fromJ(jdn).$2,
      _ => (jdn < gregorianStart ? _fromJ(jdn) : _fromG(jdn)).$2,
    };
    if (back != month) return null;
  }
  return made(jdn, tOfJdn(jdn, frac));
}

/// 날짜 글 → 해 좌표. 못 읽으면 null. [cals]를 넘기지 않으면 다른 달력의 앞말은 떼고 서력으로 읽는다.
double? parseAt(String? text, {AuxTables? cals}) => readAt(text, cals: cals)?.t;

/// 날짜 글의 자세함 — 글이 없거나 읽지 못하면 해.
DatePrec precOfAt(String? text, {AuxTables? cals}) => readAt(text, cals: cals)?.prec ?? DatePrec.year;

/// 짝 칸의 날짜 글이 값과 맞는가 — 값만 고치고 글을 못 지운 경우에는 값이 이긴다.
bool atFits(String? at, double? t, {AuxTables? cals}) {
  if (at == null || at.trim().isEmpty) return false;
  if (t == null) return true;
  final parsed = parseAt(at, cals: cals);
  return parsed != null && (parsed - t).abs() < 1e-6;
}

/// 읽은 날짜 글을 사람이 읽는 글로(지금 연표의 `HT.cal.describe`) —
/// 서력이 아니면 `음력 1592년 4월 13일 (양력 5월 23일)`처럼 서력을 곁들인다(같은 해면 해는 줄인다).
String atText(AtParts p, {bool withCivil = true}) {
  final clock = p.hour == null ? '' : ' ${p.hour}시${(p.minute ?? 0) != 0 ? ' ${p.minute}분' : ''}';
  final own = '${p.isCivil ? '' : '${p.name} '}${yearText(p.year)}'
      '${p.month != null ? ' ${p.leap ? '윤' : ''}${p.month}월' : ''}'
      '${p.day != null ? ' ${p.day}일' : ''}$clock';
  // 표가 없어 못 셈한 글은 적힌 그대로만 적는다 — 곁들일 서력을 모른다.
  if (p.isCivil || !withCivil || !p.exact) return own;
  final coarse = p.prec == DatePrec.year || p.prec == DatePrec.month;
  var civ = formatT(p.t, coarse ? DatePrec.day : p.prec);
  if (civilAt(p.t).year == p.year) civ = civ.replaceFirst(RegExp(r'^(기원전 )?\d+년 '), '');
  return '$own (양력 $civ${coarse ? '부터' : ''})';
}

/// 한 시점의 글: 맞는 날짜 글이 있거나 정수면 그 글, 아니면 서력 날짜.
String whenText(double? t, {String? at, AuxTables? cals}) {
  if (t == null || !t.isFinite) return '';
  final p = at == null || at.trim().isEmpty ? null : readAt(at, cals: cals);
  if (p != null && (p.t - t).abs() < 1e-6) return atText(p);
  if (t == t.roundToDouble()) return yearText(t.round());
  return formatT(t, DatePrec.day);
}

/// 끝의 글 — 오늘(진행 중인 항목의 끝)과 같으면 `현재`.
String endText(double? t, {double? now, AuxTables? cals}) {
  if (t == null) return '';
  if (now != null && (t - now).abs() < 1e-9) return '현재';
  return whenText(t, cals: cals);
}

/// 항목의 기간 줄(`HT.formatRange`) — 미정 · 진행 중 · 한 점.
String rangeText({
  double? start,
  String? startAt,
  double? end,
  String? endAt,
  bool startUnknown = false,
  bool endUnknown = false,
  bool ongoing = false,
  AuxTables? cals,
}) {
  final s = startUnknown ? '미정' : whenText(start, at: startAt, cals: cals);
  if (ongoing) return '$s ~ 현재';
  if (endUnknown) return '$s ~ 미정';
  if (end == null || end == start) return s;
  return '$s ~ ${whenText(end, at: endAt, cals: cals)}';
}

/// 그 단위의 끝(해 → 다음 해, 달 → 다음 달, 날 → 다음 날).
/// 달은 [cal]을 주면 **그 달력의 달**(음력이면 29 · 30일)로 센다 — 지금 연표의 `unitEnd(t, prec, calId)`.
double unitEnd(double t, DatePrec prec, {AuxCalendarTable? cal}) {
  if (prec == DatePrec.year) return t + 1;
  final a = civilAt(t);
  if (prec == DatePrec.month) {
    final month = cal?.monthOfJdn(a.jdn);
    if (month != null) return tOfJdn(month.endJdn);
    final nextMonth = a.month == 12 ? 1 : a.month + 1;
    final nextYear = a.month == 12 ? (a.year == -1 ? 1 : a.year + 1) : a.year;
    return tOfJdn(jdnOf(nextYear, nextMonth, 1));
  }
  if (prec == DatePrec.day) return tOfJdn(a.jdn + 1);
  // 나누기는 [math.min] **안**이다 — 밖에 두면 14시의 끝이 1시가 된다(2026-09-22에 고친 자리).
  if (prec == DatePrec.hour) return tOfJdn(a.jdn, math.min(1.0, ((a.frac * 24 + 1e-6).floor() + 1) / 24));
  return tOfJdn(a.jdn, math.min(1.0, a.frac + 1 / 1440));
}

/// 항목이 품는 마지막 순간 — 연도만 적은 1910은 그해 끝까지, `1910-08`은 8월 끝까지.
double? endIn({double? endY, String? endAt, bool ongoing = false, double? now, AuxTables? cals}) {
  cals ??= defaultAuxTables;
  if (ongoing) return now ?? endY;
  if (endY == null) return null;
  final p = endAt == null || endAt.trim().isEmpty ? null : readAt(endAt, cals: cals);
  if (p != null && (p.t - endY).abs() < 1e-6) {
    return unitEnd(endY, p.prec, cal: p.exact && cals != null ? cals(p.cal) : null) - _eps;
  }
  if (endY != endY.roundToDouble()) return endY;
  return endY + 1 - _eps;
}

// ── 그날의 곁들임 ───────────────────────────────────────────────────────────────────────────

const _stems = '갑을병정무기경신임계';
const _branches = '자축인묘진사오미신유술해';
const _week = '일월화수목금토';

/// 날의 간지(일진). 1949-10-01이 갑자일이다.
String dayGanji(int jdn) {
  final i = ((jdn + 49) % 60 + 60) % 60;
  return '${_stems[i % 10]}${_branches[i % 12]}';
}

/// 그날의 곁들임 — `음력 4월 13일 · 경진일 · 토요일`(지금 연표의 `dayNote` · js/viewer.js 112).
///
/// [lunar]는 음력의 '달의 시작 표'다 — 이 함수는 순수 함수이므로 표를 **밖에서 넣어 준다**
/// (상세 창 · 검색 · 도구가 `AuxCalendarStore.shared?.lunar` 하나를 함께 쓴다).
/// 표가 없거나 그 날을 덮지 않으면 음력은 빼고 적는다. 날짜를 이미 음력으로 적었으면 [withLunar]를 거짓으로 준다.
String dayNote(double t, {AuxCalendarTable? lunar, bool withLunar = true}) {
  final a = civilAt(t);
  final out = <String>[];
  if (withLunar && lunar != null) {
    final text = lunar.dayText(a.jdn, withYear: false);
    if (text.isNotEmpty) out.add(text);
  }
  out.add('${dayGanji(a.jdn)}일');
  out.add('${_week[((a.jdn + 1) % 7 + 7) % 7]}요일');
  return out.join(' · ');
}

/// 그 날짜 글이 음력(한국 · 중국)으로 적힌 것인가(지금 연표의 `lunarAt`) — 참이면 음력 곁들임을 또 붙이지 않는다.
/// 표가 없어 못 셈한 글도 '음력으로 적은 것'은 맞으므로 참이다.
bool isLunarAt(String? at, {AuxTables? cals}) => readAt(at, cals: cals)?.lunar ?? false;

// ── 기간 글 ────────────────────────────────────────────────────────────────────────────────

String _thousands(int n) {
  final digits = '${n.abs()}', out = StringBuffer(n < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// a에서 b까지를 달력으로 센다 — a에서 months개월 뒤의 같은 날(그 달에 없으면 끝날)부터 b까지가 days.
({int months, double days, double total}) _calDiff(double a, double b) {
  final ca = civilAt(a), cb = civilAt(b);
  final aay = _toAstro(ca.year), bay = _toAstro(cb.year);
  double dayAfter(int k) {
    final idx = aay * 12 + (ca.month - 1) + k;
    final ay = (idx / 12).floor();
    final m = idx - ay * 12 + 1;
    final y = _fromAstro(ay);
    final first = jdnOf(y, m, 1);
    final next = m == 12 ? jdnOf(_fromAstro(ay + 1), 1, 1) : jdnOf(y, m + 1, 1);
    return first + math.min(ca.day, next - first) - 1 + ca.frac;
  }

  var months = math.max(0, (bay - aay) * 12 + (cb.month - ca.month));
  while (months > 0 && dayAfter(months) > cb.jdn + cb.frac + 1e-9) {
    months--;
  }
  return (months: months, days: math.max(0.0, cb.jdn + cb.frac - dayAfter(months)), total: cb.jdn + cb.frac - (ca.jdn + ca.frac));
}

/// 기간 글 — `1,200년` · `3년 2개월` · `3개월 12일 (104일)` · `2일 5시간` · `하루 미만` · `한 시간 미만`.
String durationText(double a, double b, [DatePrec prec = DatePrec.day]) {
  if (prec == DatePrec.year) return '${_thousands((b - a).round())}년';
  final diff = _calDiff(a, b);
  String parts(int mo, int d, int h) => [
    if (mo >= 12) '${_thousands(mo ~/ 12)}년',
    if (mo % 12 != 0) '${mo % 12}개월',
    if (d != 0) '$d일',
    if (h != 0) '$h시간',
  ].join(' ');

  if (prec == DatePrec.month) {
    final text = parts(diff.months + (diff.days >= 15 ? 1 : 0), 0, 0);
    return text.isEmpty ? '한 달 미만' : text;
  }
  if (prec == DatePrec.day) {
    final text = parts(diff.months, diff.days.round(), 0);
    if (text.isEmpty) return '하루 미만';
    return diff.months != 0 ? '$text (${_thousands(diff.total.round())}일)' : text;
  }
  final hours = (diff.days * 24).round();
  final text = parts(diff.months, hours ~/ 24, hours % 24);
  return text.isEmpty ? '한 시간 미만' : text;
}

/// 조약 날짜 진행 표의 사이 간격 — 둘 다 날까지면 날 · 개월로, 달까지면 개월로, 그 밖에는 해로.
String gapText(double a, double b, {String? aAt, String? bAt}) {
  final d = b - a;
  if (!(d > 1e-6)) return '';
  final pa = atFits(aAt, a) ? precOfAt(aAt) : DatePrec.year;
  final pb = atFits(bAt, b) ? precOfAt(bAt) : DatePrec.year;
  bool fine(DatePrec p) => p == DatePrec.day || p == DatePrec.hour || p == DatePrec.minute;
  if (fine(pa) && fine(pb)) {
    final days = (d * 365.2425).round();
    if (days < 62) return '$days일 뒤';
    if (days < 730) return '${(days / 30.44).round()}개월 뒤';
  } else if (pa != DatePrec.year && pb != DatePrec.year) {
    final mo = (d * 12).round();
    if (mo < 24) return mo != 0 ? '$mo개월 뒤' : '';
  }
  final y = d.round();
  return y >= 1 ? '$y년 뒤' : '같은 해';
}

// ── 미정 · 연대 폭 안내 한 줄 ───────────────────────────────────────────────────────────────

/// 기본 상세의 시작 미정 안내.
String unknownStartNote(double? t, {String? at}) => '시작 연도 미정 — 연표에는 ${whenText(t, at: at)} 무렵에 자리를 잡았습니다';

/// 기본 상세의 끝 미정 안내.
String unknownEndNote(double? t, {String? at, bool ongoing = false}) => '끝 연도 미정 — 연표에는 ${ongoing ? '현재' : whenText(t, at: at)} 무렵까지로 그렸습니다';

/// 칸 · 활동 기록의 시작 미정 안내.
String cellUnknownStartNote(double? t, {String? at}) => '시작 미정 — 연표에는 ${whenText(t, at: at)} 무렵부터 놓았습니다';

/// 칸 · 활동 기록의 끝 미정 안내.
String cellUnknownEndNote(double? t, {String? at, double? now}) => '끝 미정 — 연표에는 ${endText(t, now: now)} 무렵까지 놓았습니다';

/// 연대 폭 안내 — `시작 — 이르면 …, 늦으면 …`. [word]는 `시작` 또는 `끝`.
String rangeNote(String word, double lo, double hi, {String? loAt, String? hiAt}) =>
    '$word — 이르면 ${whenText(lo, at: loAt)}, 늦으면 ${whenText(hi, at: hiAt)}';
