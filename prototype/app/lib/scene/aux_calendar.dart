// 보조 달력과 날 번호(JDN) 셈. `js/calendar.js`의 30~121줄(날 번호 ↔ 율리우스력 · 그레고리력 · 해 좌표)과
// 452~456줄(일진)을 그대로 옮겼다. 순수한 산수만 옮겼으므로 지금 연표와 한 날도 어긋나지 않는다.
//
// **음력 · 이슬람력 · 페르시아력의 환산**(`js/calendar.js`의 `intlParts`)은 브라우저의
// `Intl.DateTimeFormat('en-u-ca-dangi' …)` — ICU의 달력 표 — 에 기대어 있어 Dart에는 옮길 산수가 없다.
// 그래서 **넣을 때 한 번** 노드의 같은 ICU로 '달의 시작 표'를 떠서 저장소에 싣고([AuxCalendarTable]),
// 화면은 그 표를 이분 탐색해 분 ↔ (해, 달, 날)을 옮긴다 — 뜨는 쪽은 `prototype/scripts/export/calendar.mjs`,
// 표의 모양은 계약 `docs/계약-아카이브-3단계.md` 6-3절.
//
//   조회 {"op":"entity","uid":"cal:dangi"} → {uid, kind:'cal', json:'{…}'}
//   AuxCalendarTable.parse(답) → 표 · 표가 덮지 않는 범위에서는 아무것도 셈하지 않는다(null).

import 'dart:convert';
import 'dart:typed_data';

/// 그레고리력의 날 번호(천문 연도 — 0 = 기원전 1년).
int jdnGregorian(int y, int m, int d) {
  final a = (14 - m) ~/ 12, yy = y + 4800 - a, mm = m + 12 * a - 3;
  return d + (153 * mm + 2) ~/ 5 + 365 * yy + _fl(yy / 4) - _fl(yy / 100) + _fl(yy / 400) - 32045;
}

/// 율리우스력의 날 번호(천문 연도).
int jdnJulian(int y, int m, int d) {
  final a = (14 - m) ~/ 12, yy = y + 4800 - a, mm = m + 12 * a - 3;
  return d + (153 * mm + 2) ~/ 5 + 365 * yy + _fl(yy / 4) - 32083;
}

int _fl(double v) => v.floor();

/// 그레고리력 첫날(1582-10-15)의 날 번호.
const gregorianStart = 2299161;

/// 날 번호 → 그레고리력의 (해 · 달 · 날).
({int y, int m, int d}) gregorianOf(int j) {
  final a = j + 32044, b = (4 * a + 3) ~/ 146097, c = a - (146097 * b) ~/ 4;
  final d = (4 * c + 3) ~/ 1461, e = c - (1461 * d) ~/ 4, m = (5 * e + 2) ~/ 153;
  return (y: 100 * b + d - 4800 + m ~/ 10, m: m + 3 - 12 * (m ~/ 10), d: e - (153 * m + 2) ~/ 5 + 1);
}

/// 날 번호 → 율리우스력의 (해 · 달 · 날).
({int y, int m, int d}) julianOf(int j) {
  final c = j + 32082, d = (4 * c + 3) ~/ 1461, e = c - (1461 * d) ~/ 4, m = (5 * e + 2) ~/ 153;
  return (y: d - 4800 + m ~/ 10, m: m + 3 - 12 * (m ~/ 10), d: e - (153 * m + 2) ~/ 5 + 1);
}

/// 지금 연표의 '서력'(1582-10-15 앞은 율리우스력) — 날 번호 → (해 · 달 · 날).
({int y, int m, int d}) civilOf(int j) => j < gregorianStart ? julianOf(j) : gregorianOf(j);

/// 천문 연도 ay년 1월 1일의 날 번호.
int yearStartJdn(int ay) => ay <= 1582 ? jdnJulian(ay, 1, 1) : jdnGregorian(ay, 1, 1);

/// 해 좌표(기원전 = 음수 · 0은 빈 자리) ↔ 천문 연도.
int toAstro(int y) => y < 0 ? y + 1 : y;
int fromAstro(int a) => a <= 0 ? a - 1 : a;

/// 날 번호(+ 그날 안의 비율) → 해 좌표. `HT.cal.tOf`.
double tOfJdn(int j, [double frac = 0]) {
  var ay = civilOf(j).y;
  while (j < yearStartJdn(ay)) {
    ay--;
  }
  while (j >= yearStartJdn(ay + 1)) {
    ay++;
  }
  final s = yearStartJdn(ay);
  return fromAstro(ay) + (j - s + frac) / (yearStartJdn(ay + 1) - s);
}

/// 해 좌표 → 그 날. `HT.cal.at`. 0년 자리는 1년 1월 1일로 본다.
({int y, int ay, int j, double frac, int len}) dayAt(double t) {
  var y = (t + 1e-9).floor();
  var pos = t - y;
  if (y == 0) {
    y = 1;
    pos = 0;
  }
  final ay = toAstro(y), s = yearStartJdn(ay), len = yearStartJdn(ay + 1) - s;
  final dayPos = (pos < 0 ? 0.0 : pos) * len;
  var di = (dayPos + 1e-7).floor();
  if (di >= len) di = len - 1;
  final frac = (dayPos - di).clamp(0.0, 1.0);
  return (y: y, ay: ay, j: s + di, frac: frac, len: len);
}

/// 날 j의 끝 좌표. 기원전 1년 12월 31일 다음은 빈 0년 자리를 건너뛰므로 그날만 하루 폭으로 끊는다.
double dayEndT(int j) {
  final a = tOfJdn(j), b = tOfJdn(j + 1);
  return b - a > 0.01 ? a + 1 / 366 : b;
}

/// 일진(날마다의 간지) 번호 — 1949-10-01이 갑자일. `HT.cal.dayGanjiIndex`.
int dayGanjiIndex(int j) => ((j + 49) % 60 + 60) % 60;

const _stems = '갑을병정무기경신임계', _branches = '자축인묘진사오미신유술해';

/// 일진의 이름.
String dayGanji(int j) {
  final i = dayGanjiIndex(j);
  return _stems[i % 10] + _branches[i % 12];
}

/// 해의 간지(`HT.ganji` — 연표 연도를 받아 천문 연도로 셈한다).
String yearGanji(int year) {
  final i = ((year < 0 ? year + 1 : year) - 4) % 60;
  return _stems[i % 10] + _branches[i % 12];
}

/// DLC가 정한 해 순환(결정 D4-8). 날의 일진은 바꾸지 않는다.
class YearCycle {
  const YearCycle({this.names = const [], this.start = 4, this.label = '간지', this.off = false, this.packId = '', this.packName = ''});
  final List<String> names;
  final int start;
  final String label, packId, packName;
  final bool off;
  bool get custom => !off && names.length >= 2;
  String get title => custom ? label : '간지';
  int get length => custom ? names.length : 60;
  int index(int year) => (toAstro(year) - (custom ? toAstro(start) : 4)) % length;
  String name(int year) => custom ? names[index(year)] : yearGanji(year);

  Iterable<int> firstYears(double lo, double hi) sync* {
    final base = custom ? toAstro(start) : 4;
    final low = lo < 1 ? lo + 1 : lo;
    int a = ((low - base) / length).ceil() * length + base;
    for (int n = 0; n < 2000; n++, a += length) {
      final y = fromAstro(a);
      if (y > hi) break;
      yield y;
    }
  }

  static YearCycle? read(Object? value) {
    if (value is! Map) return null;
    final off = value['off'] == true;
    final raw = value['names'];
    final start = value['start'];
    if (!off && (raw is! List || raw.length < 2 || raw.length > 240 || raw.any((n) => n is! String || n.isEmpty || n.runes.length > 20) || start is! num || !start.isFinite || start == 0)) return null;
    final label = value['label'];
    return YearCycle(
      off: off, names: off ? const [] : List<String>.unmodifiable(raw as List), start: off ? 4 : (start as num).floor(),
      label: label is String && label.isNotEmpty ? label : '간지',
      packId: '${value['packId'] ?? ''}', packName: '${value['packName'] ?? ''}',
    );
  }

  static List<YearCycle> fromMeta(Map<String, dynamic> meta) {
    Object? decode(Object? value) {
      if (value is! String) return value;
      try { return jsonDecode(value); } catch (_) { return null; }
    }
    final many = decode(meta['year_cycles']);
    final raw = many is List ? many : [decode(meta['year_cycle'])];
    return [for (final item in raw) if (read(item) case final YearCycle c) c];
  }
}

/// 해 글(`기원전 960년` · `1592년`).
String _yearText(int year) => year < 0 ? '기원전 ${-year}년' : '$year년';

/// 보조 달력 하나(`HT.cal.CALENDARS`). 이름과 차례는 고르는 단추에 쓴다.
class AuxCalendar {
  const AuxCalendar(this.id, this.name, {this.lunar = false});
  final String id, name;
  final bool lunar;

  /// 날짜 칸의 보조 달력 줄이 고르게 내놓는 것 — 지금 연표의 고르기 목록에서 양력 · 그레고리력 · 율리우스력을 뺀 것.
  static const list = [
    AuxCalendar('dangi', '음력', lunar: true),
    AuxCalendar('chinese', '중국 음력', lunar: true),
    AuxCalendar('islamic', '이슬람력'),
    AuxCalendar('umalqura', '이슬람력(움 알쿠라)'),
    AuxCalendar('persian', '페르시아력'),
  ];

  /// 지금 연표가 처음에 켜 두는 달력(`opts.altCal`의 기본값).
  static const defaultId = 'dangi';

  static AuxCalendar? of(String id) {
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// 보조 달력의 한 달. [startJdn]은 초하루, [endJdn]은 다음 달의 초하루(그 달은 품지 않는다).
class AuxMonth {
  const AuxMonth(this.index, this.startJdn, this.endJdn, this.year, this.month, this.leap);

  /// 표 안에서의 자리.
  final int index;
  final int startJdn, endJdn;

  /// 그 달이 든 해 — 음력은 그 해가 시작한 서력 연표 연도, 이슬람력 · 페르시아력은 그 달력의 해다.
  final int year;
  final int month;
  final bool leap;

  int get days => endJdn - startJdn;

  /// 그 달력의 해가 여기서 시작하는가(윤달이 아닌 1월).
  bool get yearStart => month == 1 && !leap;
}

/// 보조 달력의 하루.
class AuxDate {
  const AuxDate(this.year, this.month, this.leap, this.day);
  final int year, month;
  final bool leap;
  final int day;
}

/// **달의 시작 표** — 넣을 때 한 번 ICU로 떠서 저장소에 실은 것(`{"op":"entity","uid":"cal:<달력>"}`).
///
/// 글 하나에 한 달을 두 글자로 담는다(계약 6-3절): 첫 글자 `65 + 달*2 + 윤달`, 둘째 글자 `48 + 날수 − 29`.
/// 해는 실어 오지 않고 셈으로 되살린다 — 윤달이 아닌 1월마다 한 살(음력은 빈 0년 자리를 건너뛴다).
/// 읽을 때 한 번만 풀어 세 배열로 두고, 그 뒤로는 이분 탐색만 한다.
///
/// 두 길이 있다: 날 번호 → 그 달력([monthOfJdn] · [dateOfJdn] · [dayText])과
/// **되짚기** — 그 달력의 날짜 → 날 번호([indexOfDate] · [monthOfDate] · [jdnOfDate]).
/// 되짚기는 음력으로 **적은** 날짜 글(`음력 1592-04-13`)을 읽는 데 쓴다(`ui/date_text.dart`).
class AuxCalendarTable {
  AuxCalendarTable._(this.id, this.name, this.prefix, this.lunar, this._start, this._code, this._year);

  /// 달력 번호(`dangi` …) · 이름(`음력`) · 날짜 글 앞말(`음력 `).
  final String id, name, prefix;
  final bool lunar;

  /// 달마다의 초하루(칸 수 = 달 수 + 1 — 마지막은 표가 끝나는 날).
  final Int32List _start;

  /// 달마다의 `달*2 + 윤달`.
  final Uint8List _code;

  /// 달마다의 해.
  final Int32List _year;

  int get count => _code.length;

  /// 표가 덮는 날 번호의 양 끝(뒤는 품지 않는다).
  int get fromJdn => _start[0];
  int get toJdn => _start[count];

  /// 그 날이 표 안에 있는가. 밖이면 눈금을 그리지 않는다(ICU가 준 만큼만 안다).
  bool covers(int jdn) => jdn >= fromJdn && jdn < toJdn;

  /// 항목 기록의 답(`{uid, kind, json}`) 또는 그 `json`을 푼 표. 모양이 깨졌으면 null.
  static AuxCalendarTable? parse(Object? answer) {
    Object? raw = answer;
    if (raw is Map && raw['json'] != null) raw = raw['json'];
    Map<String, dynamic> body;
    try {
      if (raw is String) {
        if (raw.isEmpty) return null;
        raw = jsonDecode(raw);
      }
      if (raw is! Map) return null;
      body = Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
    final months = body['months'];
    final from = body['from'], year0 = body['year0'];
    if (months is! String || months.length < 2 || months.length.isOdd || from is! num || year0 is! num) return null;
    final n = months.length ~/ 2;
    final start = Int32List(n + 1), code = Uint8List(n), years = Int32List(n);
    final lunar = body['lunar'] == true;
    int j = from.toInt(), y = year0.toInt();
    for (int i = 0; i < n; i++) {
      final c = months.codeUnitAt(i * 2) - 65, len = months.codeUnitAt(i * 2 + 1) - 48 + 29;
      if (c < 2 || c > 25 || len < 29 || len > 31) return null;
      // 윤달이 아닌 1월마다 한 살. 음력의 해는 연표 연도라 0년 자리를 건너뛴다.
      if (i > 0 && (c >> 1) == 1 && c.isEven) y = lunar && y == -1 ? 1 : y + 1;
      start[i] = j;
      code[i] = c;
      years[i] = y;
      j += len;
    }
    start[n] = j;
    final id = body['cal'] is String ? body['cal'] as String : '';
    // 이름은 `calName`이다 — `name`을 쓰면 엔진의 이름 표(검색)에 달력이 섞인다(계약 6-3절).
    final name = body['calName'] is String ? body['calName'] as String : (AuxCalendar.of(id)?.name ?? id);
    final prefix = body['prefix'] is String ? body['prefix'] as String : '$name ';
    return AuxCalendarTable._(id, name, prefix, lunar, start, code, years);
  }

  /// 표가 덮는 그 달력의 해의 양 끝(첫 달 · 마지막 달이 든 해 — 양 끝의 해는 반 토막일 수 있다).
  int get fromYear => _year[0];
  int get toYear => _year[count - 1];

  /// 표의 차례를 정하는 열쇠 — `해 × 64 + 달 × 2 + 윤달`. 달은 1~12라 열쇠는 64를 넘지 않고,
  /// 윤4월은 4월과 5월 사이에 놓이며 해는 윤달이 아닌 1월마다 오르므로 표를 따라가면 열쇠도 줄곧 오른다
  /// (다섯 달력 46,716달에서 모두 확인했다). 되짚기는 이 열쇠를 이분 탐색한다.
  int _keyAt(int i) => _year[i] * 64 + _code[i];

  /// 그 날이 든 달의 번호. 표 밖이면 −1.
  int indexOfJdn(int jdn) {
    if (!covers(jdn)) return -1;
    int lo = 0, hi = count - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_start[mid] <= jdn) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// 표 안의 달 하나.
  AuxMonth monthAt(int index) => AuxMonth(index, _start[index], _start[index + 1], _year[index], _code[index] >> 1, _code[index].isOdd);

  /// 그 날이 든 달. 표 밖이면 null.
  AuxMonth? monthOfJdn(int jdn) {
    final i = indexOfJdn(jdn);
    return i < 0 ? null : monthAt(i);
  }

  /// 그 날을 이 달력으로(`HT.cal.partsIn`). 표 밖이면 null.
  AuxDate? dateOfJdn(int jdn) {
    final i = indexOfJdn(jdn);
    return i < 0 ? null : AuxDate(_year[i], _code[i] >> 1, _code[i].isOdd, jdn - _start[i] + 1);
  }

  // ── 되짚기(그 달력의 날짜 → 날 번호) ─────────────────────────────────────────────────────
  //  지금 연표는 ICU에 이분 탐색을 걸어 되짚지만(`js/calendar.js`의 `intlJdn`), 여기서는 표를 바로 뒤진다.

  /// 그 달이 표가 덮는 범위 **안**인가 — 표는 서력 해로 끊어 떠 오므로 **양 끝의 해는 반 토막이다**.
  /// 그래서 해가 [fromYear]~[toYear] 안이어도 그 달은 표 밖일 수 있다(첫 해의 앞 달 · 마지막 해의 뒤 달).
  /// 범위 안이어도 그런 달이 없을 수는 있다(그해에 없는 윤달) — 그것은 [indexOfDate]가 −1로 가른다.
  /// 날짜 글을 읽는 쪽은 이 둘을 갈라야 한다: 표 밖이면 '못 읽은 글'이 아니라 '표가 안 닿는 글'이다(`ui/date_text.dart`).
  bool coversDate(int year, int month, {bool leap = false}) {
    if (count == 0 || month < 1 || month > 12) return false;
    final key = year * 64 + month * 2 + (leap ? 1 : 0);
    return key >= _keyAt(0) && key <= _keyAt(count - 1);
  }

  /// 그 달력의 (해 · 달 · 윤달) → 표 안의 달 번호. 그런 달이 없거나 표 밖이면 −1.
  int indexOfDate(int year, int month, {bool leap = false}) {
    if (!coversDate(year, month, leap: leap)) return -1;
    final key = year * 64 + month * 2 + (leap ? 1 : 0);
    int lo = 0, hi = count - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_keyAt(mid) < key) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return _keyAt(lo) == key ? lo : -1;
  }

  /// 그 달력의 (해 · 달 · 윤달)에 해당하는 달. 없으면 null(그해에 윤달이 없으면 그렇다).
  AuxMonth? monthOfDate(int year, int month, {bool leap = false}) {
    final i = indexOfDate(year, month, leap: leap);
    return i < 0 ? null : monthAt(i);
  }

  /// **되짚기** — 그 달력의 날짜 → 날 번호(JDN). 표가 덮지 않는 달 · 없는 윤달 · 그 달에 없는 날이면 null.
  /// (앞의 하나와 뒤의 둘을 갈라야 하는 쪽은 [coversDate]로 먼저 묻는다.)
  int? jdnOfDate(int year, int month, int day, {bool leap = false}) {
    final i = indexOfDate(year, month, leap: leap);
    if (i < 0 || day < 1 || day > _start[i + 1] - _start[i]) return null;
    return _start[i] + day - 1;
  }

  /// 그 달력의 해가 시작하는 날(윤달이 아닌 1월의 초하루). 표 밖이면 null.
  /// (이름은 바깥의 [yearStartJdn]과 겹치지 않게 다르게 짓는다 — 이 클래스 안에서 그 함수도 쓴다.)
  int? newYearJdn(int year) => jdnOfDate(year, 1, 1);

  /// 달 이름(`윤3월`).
  String monthName(AuxMonth m) => '${m.leap ? '윤' : ''}${m.month}월';

  /// 날짜 칸이 쓰는 해 이름 — 음력은 간지(`경신년`), 그 밖은 해(`1592년`). 지금 연표의 `yearName`(js/timeline.js 5836).
  String yearName(int year) => lunar ? '${yearGanji(year)}년' : _yearText(year);

  /// 한 날의 글(`HT.cal.formatIn`) — `음력 1592년 4월 13일`, [withYear]가 거짓이면 `음력 4월 13일`.
  /// 표가 그 날을 덮지 않으면 빈 글이다.
  String dayText(int jdn, {bool withYear = true}) {
    final d = dateOfJdn(jdn);
    if (d == null) return '';
    return '$name ${withYear ? '${_yearText(d.year)} ' : ''}${d.leap ? '윤' : ''}${d.month}월 ${d.day}일';
  }

  /// 보기에 걸리는 달 — 지금 연표의 `HT.cal.monthsIn` 그대로다.
  /// 서력 해 단위로 끊어 모으고(전해부터 — 왼쪽 끝을 덮는 달이 전해에 시작했을 수 있다), 앞의 군더더기는 62일까지만 남긴다.
  /// 보기가 서력 12해보다 넓으면 빈 목록이다(지금 연표의 안전장치).
  List<AuxMonth> monthsIn(int startJdn, int endJdn) {
    final out = <AuxMonth>[];
    final ys = civilOf(startJdn).y, ye = civilOf(endJdn).y;
    if (ye - ys > 12) return out;
    final lo = yearStartJdn(ys - 1), hi = yearStartJdn(ye + 1);
    int i = indexOfJdn(lo);
    if (i < 0) i = lo < fromJdn ? 0 : count;
    for (; i < count; i++) {
      final at = _start[i];
      if (at >= hi) break;
      if (at < lo || at < startJdn - 62 || at > endJdn) continue;
      out.add(monthAt(i));
    }
    return out;
  }
}

/// 보조 달력 표를 **한 번만** 받아 두는 곳. 자료 처리부에 `{"op":"entity","uid":"cal:<달력>"}`으로 묻는다.
/// 날짜 칸 층도 상세 창 · 검색의 음력 곁들임도 [shared] 하나를 함께 읽는다 — 같은 물음을 두 번 내지 않는다.
class AuxCalendarStore {
  AuxCalendarStore(this.ask);

  /// 앱이 세워질 때 총괄이 한 번 채운다(`app_glue.dart`). 비어 있으면 날짜 칸 층이 제 것으로 채운다.
  static AuxCalendarStore? shared;

  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query)? ask;
  final _tables = <String, AuxCalendarTable?>{};
  final _asking = <String>{};

  /// 받아 둔 표(아직 없으면 null).
  AuxCalendarTable? table(String id) => _tables[id];

  /// 표를 바로 넣어 둔다 — 총괄이 미리 읽어 둔 표를 넘기거나 검사가 표를 꽂을 때. 그 뒤로는 다시 묻지 않는다.
  void put(String id, AuxCalendarTable? table) => _tables[id] = table;

  /// 음력 표 — 상세 창 · 검색의 곁들임이 쓴다.
  AuxCalendarTable? get lunar => _tables[AuxCalendar.defaultId];

  /// 그 달력의 표를 받아 둔다. 이미 받았거나 받는 중이면 다시 묻지 않는다.
  /// [onReady]는 새로 받았을 때만 부른다(그리는 쪽이 다음 장면을 부탁하게).
  void ensure(String id, {void Function(String id, AuxCalendarTable? table)? onReady}) {
    if (id.isEmpty || _tables.containsKey(id) || _asking.contains(id) || ask == null) return;
    _asking.add(id);
    ask!({'op': 'entity', 'uid': 'cal:$id'}).then((answer) {
      _asking.remove(id);
      final table = AuxCalendarTable.parse(answer);
      _tables[id] = table;
      if (onReady != null) onReady(id, table);
    }, onError: (_) {
      _asking.remove(id);
      _tables[id] = null; // 못 받으면 '없음'으로 두고 다시 묻지 않는다(눈금은 비어 있다).
      if (onReady != null) onReady(id, null);
    });
  }
}
