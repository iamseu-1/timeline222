import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/aux_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

// 보조 달력의 '달의 시작 표'. 표는 넣을 때 한 번 노드의 ICU로 떠서 저장소에 실은 것이고
// (`prototype/scripts/export/calendar.mjs` · 계약 6-3절), 여기서는 그 표를 푸는 쪽이 지금 연표와
// 한 날도 어긋나지 않는지 본다.
//
// 기대값은 **지금 연표의 기준 덤프**에서 읽었다(`prototype/results/dom-axis2/`):
//   · `보조달력-열림`(300~305년) — 달 칸의 `data-k="cm<날 번호>"`와 도움말 '음력 기미년 11월 — 299년 12월 10일부터'
//   · `일진-하루`(300~300.1년) — 날 칸의 `cd<날 번호>`와 '음력 299년 11월 23일 = 300년 1월 1일'
//
// 표 전체는 46,716달(글자 9만)이라 검사에는 296~307년의 139달만 잘라 박았다
// (자르는 법은 `from`을 그 조각의 첫 초하루로, `year0`을 그 달이 든 해로 바꾸는 것뿐이다).

/// 음력 표의 296~307년 조각.
const _slice = 'W1Y0C0E1G1I0K1M0O1Q1S0U1W0Y1C0E0G1I0K1M0O1P1Q0S1U1W0Y1C0E1G0I0K1M0O1Q0S1U1W1Y0C1E0G1I0K0M1O0Q1S0U1W1Y1C0E1G0I1K0L0M0O1Q0S1U1W1Y0C1E1G0I1K0M0O0Q1S0U1W1Y0C1E1G1I0K0M1O0Q1S0U0W1Y0C1E1G1H0I1K0M1O0Q1S0U0W1Y0C1E1G0I1K1M0O1Q0S1U0W0Y1C0E1G0I1K1M0O1Q1R0S1U0W1Y0C0E1G0I1K0M1O1Q0S1U1W0Y1C0';

/// 그 조각으로 푼 음력 표. 날짜 칸 그리기 검사(`axis_paint_test.dart`)도 이것을 꽂아 쓴다.
AuxCalendarTable lunarSlice() => AuxCalendarTable.parse(jsonEncode({
  'cal': 'dangi', 'calName': '음력', 'lunar': true, 'prefix': '음력 ',
  'from': 1829518, 'year0': 296, 'count': _slice.length ~/ 2, 'months': _slice,
}))!;

AuxCalendarTable get _table => lunarSlice();

// ── 달력 다섯(2026-10-24 리메이크 6단계 결정 D10) ─────────────────────────────────────────────────
// 히브리력 · 에티오피아력 · 콥트력 · 사카력은 넓게 뜬 표(`prototype/results/calendar-cache.json` — 꼴 2)를
// 내보내기의 `sliceTable`로 서력 2023 ~ 2024년만큼 잘라 박았다. 기대값(초하루 · 해 · 달 · 날수)은 지금 연표의
// `HT.cal.partsIn` · `HT.cal.nextMonthIn`을 노드로 돌려 떴다. 표는 넓힌 꼴이다 — 13째 달 '[' · 28일 이하인 달 'a' ~ '|'.

/// (달력, 첫 초하루, 첫 달의 해, 달 표, 확인 [초하루, 해, 달, 날수]).
const _sliceOf = <String, (int, int, String, List<(int, int, int, int)>)>{
  // 히브리력: 티슈리가 1월 · 윤년(5784)은 13달이라 엘룰이 13월, 평년(5783)은 12월.
  'hebrew': (2460175, 5783, 'Y0C1E0G0I0K1M1O0Q1S0U1W0Y1[0C1E1G1', [
    (2460175, 5783, 12, 29), (2460204, 5784, 1, 30), (2460234, 5784, 2, 29), (2460263, 5784, 3, 29),
    (2460292, 5784, 4, 29), (2460321, 5784, 5, 30), (2460351, 5784, 6, 30), (2460381, 5784, 7, 29),
    (2460410, 5784, 8, 30), (2460440, 5784, 9, 29), (2460469, 5784, 10, 30), (2460499, 5784, 11, 29),
    (2460528, 5784, 12, 30), (2460558, 5784, 13, 29), (2460587, 5785, 1, 30), (2460617, 5785, 2, 30), (2460647, 5785, 3, 30),
  ]),
  // 에티오피아력: 13째 달(파구메)은 6일(2015년) · 5일(2016년).
  'ethiopic': (2460134, 2015, 'W1Y1[fC1E1G1I1K1M1O1Q1S1U1W1Y1[eC1', [
    (2460134, 2015, 11, 30), (2460164, 2015, 12, 30), (2460194, 2015, 13, 6), (2460200, 2016, 1, 30),
    (2460230, 2016, 2, 30), (2460260, 2016, 3, 30), (2460290, 2016, 4, 30), (2460320, 2016, 5, 30),
    (2460350, 2016, 6, 30), (2460380, 2016, 7, 30), (2460410, 2016, 8, 30), (2460440, 2016, 9, 30),
    (2460470, 2016, 10, 30), (2460500, 2016, 11, 30), (2460530, 2016, 12, 30), (2460560, 2016, 13, 5), (2460565, 2017, 1, 30),
  ]),
  // 콥트력: 달의 경계는 에티오피아력과 같고 해만 276년 뒤다.
  'coptic': (2460134, 1739, 'W1Y1[fC1E1G1I1K1M1O1Q1S1U1W1Y1[eC1', [
    (2460134, 1739, 11, 30), (2460194, 1739, 13, 6), (2460200, 1740, 1, 30), (2460560, 1740, 13, 5), (2460565, 1741, 1, 30),
  ]),
  // 사카력: 새해는 서력 3월 22일(윤년은 21일) · 앞 여섯 달은 31일(윤년은 1월도).
  'indian': (2459936, 1944, 'U1W1Y1C1E2G2I2K2M2O1Q1S1U1W1Y1C2E2G2I2K2M2O1Q1S1U1', [
    (2459936, 1944, 10, 30), (2459966, 1944, 11, 30), (2459996, 1944, 12, 30), (2460026, 1945, 1, 30),
    (2460056, 1945, 2, 31), (2460087, 1945, 3, 31), (2460118, 1945, 4, 31), (2460149, 1945, 5, 31),
    (2460180, 1945, 6, 31), (2460211, 1945, 7, 30), (2460241, 1945, 8, 30), (2460271, 1945, 9, 30),
    (2460301, 1945, 10, 30), (2460331, 1945, 11, 30), (2460361, 1945, 12, 30), (2460391, 1946, 1, 31),
    (2460422, 1946, 2, 31), (2460453, 1946, 3, 31), (2460484, 1946, 4, 31), (2460515, 1946, 5, 31),
    (2460546, 1946, 6, 31), (2460577, 1946, 7, 30), (2460607, 1946, 8, 30), (2460637, 1946, 9, 30), (2460667, 1946, 10, 30),
  ]),
};

/// 달력 다섯 가운데 표가 있는 넷의 2023 ~ 2024년 조각(날짜 글 검사 `date_text_test.dart`도 이것을 꽂아 쓴다).
/// 이름 · 앞말은 표에 싣지 않는다 — 표가 `AuxCalendar.list`의 이름에서 되살리는지도 함께 본다.
AuxCalendarTable auxSlice(String id) {
  final s = _sliceOf[id]!;
  return AuxCalendarTable.parse({'cal': id, 'lunar': false, 'from': s.$1, 'year0': s.$2, 'months': s.$3})!;
}

/// 불기 — 표 없이 산수로 셈하는 달력(저장소에 묻지 않는다).
AuxCalendarTable get _buddhist => AuxCalendarTable.shifted(AuxCalendar.of('buddhist')!);

/// 처음 다섯 달력 — 달력 다섯을 더하기 전에 지은 저장소에도 표가 있다.
const _firstFive = {'dangi', 'chinese', 'islamic', 'umalqura', 'persian'};

void main() {
  test('표를 푼다 — 달 수와 덮는 범위', () {
    final table = _table;
    expect(table.id, 'dangi');
    expect(table.name, '음력');
    expect(table.lunar, isTrue);
    expect(table.count, 139);
    expect(table.fromJdn, 1829518);
    // 표가 덮지 않는 날은 아무것도 셈하지 않는다(ICU가 준 만큼만 안다).
    expect(table.covers(table.fromJdn), isTrue);
    expect(table.covers(table.fromJdn - 1), isFalse);
    expect(table.covers(table.toJdn), isFalse);
    expect(table.dateOfJdn(table.fromJdn - 1), isNull);
    expect(table.monthOfJdn(table.toJdn), isNull);
  });

  test('달의 초하루 · 이름 · 날수가 지금 연표와 같다(기준 덤프 보조달력-열림의 달 칸)', () {
    final table = _table;
    // 날 번호 → (간지 해 이름, 달 이름, 그 달의 날수)
    const truth = {
      1830611: ('기미년', '11월', 30),
      1830641: ('기미년', '12월', 29),
      1830670: ('경신년', '1월', 30),
      1830935: ('경신년', '10월', 30),
      1831172: ('신유년', '윤5월', 29), // 윤달
      1831201: ('신유년', '6월', 29),
      1832116: ('갑자년', '1월', 30),
      1832206: ('갑자년', '윤3월', 29), // 윤달
      1832441: ('갑자년', '11월', 30),
    };
    truth.forEach((jdn, want) {
      final month = table.monthOfJdn(jdn)!;
      expect(month.startJdn, jdn, reason: '$jdn은 초하루다');
      expect(table.yearName(month.year), want.$1);
      expect(table.monthName(month), want.$2);
      expect(month.days, want.$3);
    });
    // 윤달은 해가 바뀌는 달이 아니다.
    expect(table.monthOfJdn(1832206)!.yearStart, isFalse);
    expect(table.monthOfJdn(1832116)!.yearStart, isTrue);
  });

  test('하루하루의 환산이 지금 연표와 같다(기준 덤프 일진-하루의 날 칸)', () {
    final table = _table;
    // 날 번호 → (해, 달, 윤달, 날)
    const truth = {
      1830633: (299, 11, false, 23),
      1830640: (299, 11, false, 30),
      1830641: (299, 12, false, 1),
      1830655: (299, 12, false, 15),
      1830669: (299, 12, false, 29),
      1830670: (300, 1, false, 1),
      1831172: (301, 5, true, 1), // 윤5월 초하루
      1831200: (301, 5, true, 29),
      1831201: (301, 6, false, 1),
    };
    truth.forEach((jdn, want) {
      final date = table.dateOfJdn(jdn)!;
      expect((date.year, date.month, date.leap, date.day), want, reason: '날 번호 $jdn');
    });
  });

  test('날짜 글 — 상세 창의 곁들임은 해를 뺀 글이다', () {
    final table = _table;
    expect(table.dayText(1830655), '음력 299년 12월 15일');
    expect(table.dayText(1830655, withYear: false), '음력 12월 15일');
    expect(table.dayText(1831172, withYear: false), '음력 윤5월 1일');
    expect(table.dayText(table.toJdn), '', reason: '표 밖은 빈 글');
  });

  test('해 이름 — 음력은 간지, 그 밖의 달력은 해', () {
    expect(_table.yearName(299), '기미년');
    expect(_table.yearName(304), '갑자년');
    // 음력이 아닌 표는 해를 그대로 적는다(기원전은 '기원전 N년').
    final solar = AuxCalendarTable.parse({'cal': 'persian', 'calName': '페르시아력', 'lunar': false, 'from': 1829518, 'year0': -3, 'months': 'C2E2G2'})!;
    expect(solar.yearName(1592), '1592년');
    expect(solar.yearName(-44), '기원전 44년');
    expect(solar.monthOfJdn(1829518)!.days, 31);
  });

  test('해는 셈으로 되살린다 — 윤달이 아닌 1월마다 한 살', () {
    final table = _table;
    expect(table.monthOfJdn(1830611)!.year, 299); // 기미년 11월
    expect(table.monthOfJdn(1830670)!.year, 300); // 경신년 1월에서 한 살
    expect(table.monthOfJdn(1830965)!.year, 300); // 같은 해 11월
    expect(table.monthOfJdn(1831172)!.year, 301); // 윤5월은 해를 올리지 않는다
    expect(table.monthOfJdn(1832116)!.year, 304);
  });

  test('보기에 걸리는 달 — 왼쪽 밖의 한 달까지 담고, 서력 12해보다 넓으면 비운다', () {
    final table = _table;
    // 지금 연표의 300~305년 보기(`보조달력-열림`): 화면에 그려진 달이 63개이고,
    // 목록에는 왼쪽 밖에서 시작한 달 하나가 더 들어 있다(한 칸 걸러 짙은 바탕의 차례가 거기서 시작한다).
    final j0 = dayAt(300).j, j1 = dayAt(305).j;
    expect(j0, 1830633, reason: '기준 덤프의 300년 1월 1일');
    final months = table.monthsIn(j0 - 1, j1 + 1);
    expect(months.length, 64);
    expect(months.first.startJdn, 1830581);
    expect(months[1].startJdn, 1830611);
    expect(months.last.startJdn, 1832441);
    // 넓게 보면 지금 연표처럼 아무것도 내놓지 않는다(`HT.cal.monthsIn`의 안전장치).
    expect(table.monthsIn(dayAt(296).j, dayAt(307).j).isNotEmpty, isTrue);
    expect(table.monthsIn(dayAt(290).j, dayAt(307).j), isEmpty);
  });

  test('되짚기 — 그 달력의 날짜를 날 번호로(음력으로 적은 날짜 글이 이 길로 읽힌다)', () {
    final table = _table;
    expect((table.fromYear, table.toYear), (296, 308), reason: '조각의 첫 달은 296년 11월, 마지막 달은 308년 1월');
    // 날 번호 → 날짜 → 날 번호가 제자리로 돌아온다.
    const truth = {
      (299, 11, false, 1): 1830611,
      (299, 11, false, 23): 1830633,
      (299, 12, false, 1): 1830641,
      (300, 1, false, 1): 1830670,
      (300, 1, false, 23): 1830692,
      (301, 5, true, 1): 1831172, // 윤5월
      (301, 6, false, 1): 1831201,
      (304, 1, false, 1): 1832116,
      (304, 3, true, 1): 1832206, // 윤3월
      (307, 1, false, 1): 1833239,
    };
    truth.forEach((want, jdn) {
      expect(table.jdnOfDate(want.$1, want.$2, want.$4, leap: want.$3), jdn, reason: '음력 ${want.$1}년 ${want.$3 ? '윤' : ''}${want.$2}월 ${want.$4}일');
      final back = table.dateOfJdn(jdn)!;
      expect((back.year, back.month, back.leap, back.day), want, reason: '되짚은 날을 다시 풀면 제자리');
    });
    expect(table.monthOfDate(301, 5, leap: true)!.startJdn, 1831172);
    expect(table.newYearJdn(300), 1830670);
  });

  test('되짚기 — 없는 날 · 없는 윤달 · 표 밖은 null', () {
    final table = _table;
    expect(table.jdnOfDate(299, 11, 31), isNull, reason: '그 달은 30일까지다');
    expect(table.jdnOfDate(299, 11, 0), isNull);
    expect(table.jdnOfDate(301, 4, 1, leap: true), isNull, reason: '301년에는 윤4월이 없다');
    expect(table.jdnOfDate(300, 13, 1), isNull);
    expect(table.jdnOfDate(1592, 4, 13), isNull, reason: '표가 덮지 않는 해');
    expect(table.jdnOfDate(296, 1, 1), isNull, reason: '첫 달(296년 11월)보다 앞');
    expect(table.indexOfDate(296, 11), 0);
  });

  test('coversDate — 표 밖의 달과 없는 달을 가른다(양 끝의 해는 반 토막이다)', () {
    final table = _table;
    // 조각은 296년 11월에서 308년 1월까지다 — 해로만 보면 296년 · 308년도 '표 안'이지만 그 해의 달은 대부분 표 밖이다.
    expect((table.fromYear, table.toYear), (296, 308));
    expect(table.coversDate(296, 11), isTrue);
    expect(table.coversDate(296, 10), isFalse, reason: '첫 달보다 앞선 달');
    expect(table.coversDate(296, 1), isFalse);
    expect(table.coversDate(308, 1), isTrue);
    expect(table.coversDate(308, 2), isFalse, reason: '마지막 달보다 뒤인 달');
    expect(table.coversDate(308, 12), isFalse);
    expect(table.coversDate(295, 12), isFalse);
    expect(table.coversDate(309, 1), isFalse);
    // 범위 **안**이지만 그런 달이 없는 것은 표 밖이 아니다 — 잘못 적은 날짜 글이다.
    expect(table.coversDate(301, 4, leap: true), isTrue);
    expect(table.indexOfDate(301, 4, leap: true), -1, reason: '301년에는 윤4월이 없다');
    expect(table.coversDate(300, 13), isFalse, reason: '13월은 어느 달력에도 없다');
  });

  test('모양이 깨진 표는 받지 않는다', () {
    expect(AuxCalendarTable.parse(null), isNull);
    expect(AuxCalendarTable.parse(''), isNull);
    expect(AuxCalendarTable.parse('{'), isNull);
    expect(AuxCalendarTable.parse({'months': 'C1', 'from': 1, 'year0': 1}), isNotNull);
    expect(AuxCalendarTable.parse({'months': 'C1E', 'from': 1, 'year0': 1}), isNull, reason: '한 달은 두 글자');
    expect(AuxCalendarTable.parse({'months': 'A1', 'from': 1, 'year0': 1}), isNull, reason: '0월은 없다');
    expect(AuxCalendarTable.parse({'months': 'C9', 'from': 1, 'year0': 1}), isNull, reason: '38일짜리 달은 없다');
  });

  test('받아 두는 곳은 하나 — 같은 달력을 두 번 묻지 않는다', () async {
    int asked = 0;
    final store = AuxCalendarStore((query) async {
      asked++;
      expect(query['uid'], 'cal:dangi');
      return {'uid': 'cal:dangi', 'kind': 'cal', 'json': jsonEncode({'cal': 'dangi', 'calName': '음력', 'lunar': true, 'from': 1829518, 'year0': 296, 'months': _slice})};
    });
    expect(store.table('dangi'), isNull);
    store.ensure('dangi');
    store.ensure('dangi'); // 받는 중에 또 물어도 한 번만 나간다
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);
    expect(store.lunar, isNotNull);
    expect(store.lunar!.count, 139);
    store.ensure('dangi');
    expect(asked, 1, reason: '이미 받아 두었으면 다시 묻지 않는다');
  });

  test('못 받으면 없음으로 두고 다시 묻지 않는다 — 줄은 비어 있을 뿐이다', () async {
    int asked = 0;
    final store = AuxCalendarStore((query) async {
      asked++;
      throw StateError('그런 기록이 없습니다');
    });
    store.ensure('persian');
    await Future<void>.delayed(Duration.zero);
    expect(store.table('persian'), isNull);
    store.ensure('persian');
    expect(asked, 1);
  });

  // ── 달력 다섯(결정 D10) ────────────────────────────────────────────────────────────────────
  group('달력 다섯', () {
    test('고르기 목록 — 지금 연표의 HT.cal.CALENDARS 차례 · 이름 그대로(양력 · 그레고리력 · 율리우스력 뺌)', () {
      expect([for (final c in AuxCalendar.list) c.id], [
        'dangi', 'chinese', 'islamic', 'umalqura', 'persian', 'hebrew', 'ethiopic', 'coptic', 'indian', 'buddhist',
      ]);
      expect([for (final c in AuxCalendar.list) c.name], [
        '음력', '중국 음력', '이슬람력', '이슬람력(움 알쿠라)', '페르시아력', '히브리력', '에티오피아력', '콥트력', '사카력', '불기',
      ]);
      expect([for (final c in AuxCalendar.list) if (c.maxMonth == 13) c.id], ['hebrew', 'ethiopic', 'coptic'], reason: '13째 달이 있는 달력');
      expect([for (final c in AuxCalendar.list) if (c.arithmetic) (c.id, c.offset)], [('buddhist', 543)], reason: '표 없이 산수로 셈하는 달력');
      expect(AuxCalendar.of('buddhist')!.lunar, isFalse);
    });

    test('넓힌 표의 꼴을 푼다 — 13째 달 \'[\' · 28일 이하인 달(\'a\' ~ \'|\')', () {
      for (final id in _sliceOf.keys) {
        final table = auxSlice(id), want = _sliceOf[id]!.$4;
        final cal = AuxCalendar.of(id)!;
        expect((table.id, table.name, table.prefix, table.lunar), (id, cal.name, '${cal.name} ', false), reason: '$id — 이름 · 앞말은 달력 목록에서');
        expect(table.maxMonth, cal.maxMonth, reason: id);
        for (final (jdn, year, month, days) in want) {
          final m = table.monthOfJdn(jdn)!;
          expect((m.startJdn, m.year, m.month, m.leap, m.days), (jdn, year, month, false, days), reason: '$id 날 번호 $jdn');
          // 초하루 · 그믐을 되짚어도 제자리다.
          expect(table.jdnOfDate(year, month, 1), jdn, reason: '$id $year년 $month월 1일');
          expect(table.jdnOfDate(year, month, days), jdn + days - 1, reason: '$id $year년 $month월 $days일');
          expect(table.jdnOfDate(year, month, days + 1), isNull, reason: '$id $year년 $month월은 $days일까지다');
        }
      }
      // 짧은 달 · 13월은 표의 다른 달처럼 해를 올리지 않는다 — 그다음 1월이 새해다.
      final ethiopic = auxSlice('ethiopic');
      expect(ethiopic.monthOfJdn(2460194)!.yearStart, isFalse);
      expect(ethiopic.monthOfJdn(2460200)!.yearStart, isTrue);
      expect(ethiopic.toJdn, 2460595);
    });

    test('날짜 글 · 해 이름 — 13월도 그 달력의 이름 그대로', () {
      expect(auxSlice('ethiopic').dayText(2460199), '에티오피아력 2015년 13월 6일');
      expect(auxSlice('coptic').dayText(2460564, withYear: false), '콥트력 13월 5일');
      expect(auxSlice('hebrew').dayText(2460586), '히브리력 5784년 13월 29일');
      // 지금 연표의 `HT.cal.formatIn(id, 2024년 1월 1일)`과 같은 글.
      expect(auxSlice('hebrew').dayText(2460311), '히브리력 5784년 4월 20일');
      expect(auxSlice('ethiopic').dayText(2460311), '에티오피아력 2016년 4월 22일');
      expect(auxSlice('coptic').dayText(2460311), '콥트력 1740년 4월 22일');
      expect(auxSlice('indian').dayText(2460311), '사카력 1945년 10월 11일');
      expect(auxSlice('hebrew').yearName(5784), '5784년', reason: '음력이 아니면 해를 그대로');
      final m13 = auxSlice('hebrew').monthOfJdn(2460558)!;
      expect(auxSlice('hebrew').monthName(m13), '13월');
    });

    test('13월의 되짚기 — 13째 달이 있는 달력의 그해에만 있다', () {
      final hebrew = auxSlice('hebrew');
      expect(hebrew.coversDate(5784, 13), isTrue);
      expect(hebrew.jdnOfDate(5784, 13, 29), 2460586);
      // 5783년은 평년이라 엘룰이 12월이다 — 범위 안이지만 그런 달이 없다(잘못 적은 글).
      expect(hebrew.coversDate(5783, 13), isTrue);
      expect(hebrew.indexOfDate(5783, 13), -1);
      expect(hebrew.jdnOfDate(5783, 12, 1), 2460175);
      expect(hebrew.coversDate(5784, 14), isFalse);
      final ethiopic = auxSlice('ethiopic');
      expect(ethiopic.jdnOfDate(2015, 13, 6), 2460199);
      expect(ethiopic.jdnOfDate(2015, 13, 7), isNull, reason: '2015년의 13째 달은 6일까지');
      expect(ethiopic.jdnOfDate(2016, 13, 6), isNull, reason: '2016년의 13째 달은 5일까지');
      // 12달 달력은 13월을 범위 밖으로 본다(지금 연표의 '달은 1~12 사이여야 합니다').
      expect(auxSlice('indian').coversDate(1945, 13), isFalse);
      expect(auxSlice('indian').maxMonth, 12);
    });

    test('넓힌 표의 글자 — 깨진 글자는 받지 않는다', () {
      expect(auxMonthDays('0'.codeUnitAt(0)), 29);
      expect(auxMonthDays('2'.codeUnitAt(0)), 31);
      expect(auxMonthDays('a'.codeUnitAt(0)), 1);
      expect(auxMonthDays('e'.codeUnitAt(0)), 5);
      expect(auxMonthDays('|'.codeUnitAt(0)), 28);
      for (final bad in ['3', '/', '`', '}', 'A']) {
        expect(auxMonthDays(bad.codeUnitAt(0)), 0, reason: '\'$bad\'는 길이 글자가 아니다');
      }
      expect(AuxCalendarTable.parse({'months': 'Cf[e', 'from': 1, 'year0': 1}), isNotNull);
      expect(AuxCalendarTable.parse({'months': 'C3', 'from': 1, 'year0': 1}), isNull, reason: '32일짜리 달은 없다');
      expect(AuxCalendarTable.parse({'months': 'C}', 'from': 1, 'year0': 1}), isNull);
      expect(AuxCalendarTable.parse({'months': ']0', 'from': 1, 'year0': 1}), isNull, reason: '14월은 없다');
      // 13월을 품은 표는 이름을 몰라도 13월까지 받는다.
      expect(AuxCalendarTable.parse({'months': 'Y0[0C0', 'from': 1, 'year0': 1})!.maxMonth, 13);
      expect(AuxCalendarTable.parse({'months': 'Y0C0', 'from': 1, 'year0': 1})!.maxMonth, 12);
    });

    test('불기 — 표 없이 산수로: 해는 천문 연도 + 543 · 달과 날은 서력 그대로', () {
      final table = _buddhist;
      expect((table.id, table.name, table.prefix, table.lunar, table.maxMonth), ('buddhist', '불기', '불기 ', false, 12));
      // 지금 연표의 `HT.cal.partsIn('buddhist', …)`과 같다.
      const truth = {
        2460311: (2567, 1, 1), // 2024년 1월 1일
        2460370: (2567, 2, 29),
        2299160: (2125, 10, 4), // 1582년 10월 4일(율리우스력)
        2299161: (2125, 10, 15), // 그다음 날은 10월 15일(그레고리력)
        1721424: (544, 1, 1), // 1년 1월 1일
        1721423: (543, 12, 31), // 기원전 1년 12월 31일
      };
      truth.forEach((jdn, want) {
        final d = table.dateOfJdn(jdn)!;
        expect((d.year, d.month, d.leap, d.day), (want.$1, want.$2, false, want.$3), reason: '날 번호 $jdn');
      });
      expect(table.dayText(2460311), '불기 2567년 1월 1일');
      expect(table.yearName(2567), '2567년');
      // 1582년 10월은 21날(1 ~ 4일 · 15 ~ 31일)이다 — 초하루에서 이어 세면 10월 15일이 5일이 된다(그래서 표로 싣지 않는다).
      final october = table.monthOfJdn(2299161)!;
      expect((october.startJdn, october.days, october.year, october.month), (2299157, 21, 2125, 10));
      expect(table.monthOfJdn(2299178)!.month, 11);
      // 되짚기 — 없는 날은 null, 서력에 없던 열흘(10월 5 ~ 14일)은 율리우스력의 날로 받는다(지금 연표와 같다).
      expect(table.jdnOfDate(2567, 2, 29), 2460370);
      expect(table.jdnOfDate(2566, 2, 29), isNull, reason: '2023년 2월은 28일까지');
      expect(table.jdnOfDate(2125, 10, 4), 2299160);
      expect(table.jdnOfDate(2125, 10, 5), 2299161);
      expect(table.jdnOfDate(2125, 10, 15), 2299161);
      expect(table.jdnOfDate(2567, 13, 1), isNull);
      expect(table.jdnOfDate(2567, 1, 1, leap: true), isNull, reason: '윤달은 없다');
      expect(table.newYearJdn(544), 1721424);
      // 보기에 걸리는 달 — 서력의 달과 같고, 해는 1월에 오른다.
      final months = table.monthsIn(dayAt(2024).j, dayAt(2025).j);
      expect(months.where((m) => m.yearStart).map((m) => m.year), containsAll([2567, 2568]));
      expect(months.firstWhere((m) => m.year == 2567 && m.month == 2).days, 29);
      // 달마다 초하루 · 그믐을 되짚어도 제자리다(1400 ~ 1700년 — 1582년의 열흘 건너뜀을 품는다).
      final from = table.indexOfJdn(dayAt(1400).j), to = table.indexOfJdn(dayAt(1700).j);
      for (int i = from; i <= to; i++) {
        final m = table.monthAt(i);
        expect(table.indexOfDate(m.year, m.month), i);
        for (final jdn in [m.startJdn, m.endJdn - 1]) {
          final d = table.dateOfJdn(jdn)!;
          expect(table.jdnOfDate(d.year, d.month, d.day), jdn, reason: '불기 ${d.year}년 ${d.month}월 ${d.day}일');
        }
      }
    });

    test('불기는 저장소에 묻지 않고 그 자리에서 만든다 — 묻는 곳이 없어도', () {
      int asked = 0;
      final store = AuxCalendarStore((query) async {
        asked++;
        return const {};
      });
      store.ensure('buddhist');
      expect(asked, 0);
      expect(store.table('buddhist')?.dayText(2460311), '불기 2567년 1월 1일');
      final quiet = AuxCalendarStore(null)..ensure('buddhist');
      expect(quiet.table('buddhist'), isNotNull);
      expect((AuxCalendarStore(null)..ensure('hebrew')).table('hebrew'), isNull, reason: '표가 있어야 하는 달력은 묻는 곳이 없으면 그대로 없다');
    });

    test('옛 저장소(달력 표 다섯)에는 나중 달력 넷의 기록이 없다 — 고르기에 그 이름을 내놓지 않는다(감독 결정 2026-10-25)', () async {
      const later = {'hebrew', 'ethiopic', 'coptic', 'indian'};
      final store = AuxCalendarStore((query) async {
        final id = (query['uid'] as String).substring(4);
        if (later.contains(id)) throw StateError('그런 기록이 없습니다'); // 엔진은 그 달력을 건너뛰고 넣었다
        return {'uid': 'cal:$id', 'kind': 'cal', 'json': jsonEncode({'cal': id, 'calName': AuxCalendar.of(id)!.name, 'lunar': id == 'dangi' || id == 'chinese', 'from': 1829518, 'year0': 296, 'months': _slice})};
      });
      expect(store.offered().map((c) => c.id), AuxCalendar.list.map((c) => c.id), reason: '묻기 전에는 모두 내놓는다');
      for (final cal in AuxCalendar.list) {
        store.ensure(cal.id);
      }
      await Future<void>.delayed(Duration.zero);
      expect(store.offered().map((c) => c.name), ['음력', '중국 음력', '이슬람력', '이슬람력(움 알쿠라)', '페르시아력', '불기'], reason: '불기는 표 없이 산수라 남는다');
      expect(later.every(store.lacks) && !store.lacks('dangi') && !store.lacks('buddhist'), isTrue);
    });

    // 넓게 떠 둔 표(정답지 도구가 쓰는 git 밖 파일)가 있으면 아홉 달력을 통째로 풀어 되짚는다 —
    // 열쇠(해 × 64 + 달 × 2 + 윤달)가 줄곧 오른다는 약속을 13째 달 · 짧은 달까지 넣고 다시 본다.
    test('넓은 표 아홉(있으면) — 달마다 되짚어도 제자리 · 열쇠가 줄곧 오른다', () {
      final file = File('../results/calendar-cache.json');
      if (!file.existsSync()) {
        markTestSkipped('prototype/results/calendar-cache.json이 없습니다(node prototype/scripts/warm-calendar.mjs로 뜸)');
        return;
      }
      final cache = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final tables = (cache['tables'] as Map).cast<String, dynamic>();
      expect(tables.keys, containsAll([for (final c in AuxCalendar.list) if (!c.arithmetic) c.id]));
      for (final c in AuxCalendar.list.where((c) => !c.arithmetic)) {
        final raw = tables[c.id] as Map;
        final table = AuxCalendarTable.parse({'cal': c.id, 'lunar': c.lunar, 'from': raw['start'], 'year0': raw['year0'], 'months': raw['months']})!;
        expect(table.toJdn, raw['end'], reason: '${c.name}: 날수를 다 더하면 표의 끝');
        expect(table.maxMonth, c.maxMonth, reason: c.name);
        for (int i = 0; i < table.count; i++) {
          final m = table.monthAt(i);
          expect(m.month, inInclusiveRange(1, c.maxMonth));
          if (table.indexOfDate(m.year, m.month, leap: m.leap) != i) {
            fail('${c.name} ${m.year}년 ${m.leap ? '윤' : ''}${m.month}월(달 번호 $i)을 되짚지 못했다');
          }
          final last = m.endJdn - 1, d = table.dateOfJdn(last)!;
          if (table.jdnOfDate(d.year, d.month, d.day, leap: d.leap) != last) fail('${c.name} 날 번호 $last');
        }
      }
    });
  });

  // ── 진짜 자료 처리부(DLL) + 진짜 저장소 ────────────────────────────────────────────────────
  // 잘라 박은 조각이 아니라 **넣을 때 실제로 실린 표 다섯**을 통째로 받아 되짚기를 건다.
  // 달력 다섯(결정 D10) 가운데 표가 있는 넷은 그 뒤에 지은 저장소에만 있다 — 없으면 그 달력만 건너뛴다(불기는 표가 없다).
  // (어제의 교훈: 가짜 답으로만 검사하면 실제 앱에서만 비는 일이 생긴다.)
  group('real store', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File('../data/moonwake3h/archive.db');
    final ready = dll.existsSync() && db.existsSync();
    ArchiveEngine? engine;

    setUpAll(() async {
      if (!ready) return;
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine!.start(db.absolute.path);
    });
    tearDownAll(() => engine?.close());

    test('다섯 달력의 표를 받아 달마다 되짚어도 제자리다', () async {
      if (!ready) {
        markTestSkipped('자료 처리부 DLL 또는 data/moonwake3h 저장소가 없습니다');
        return;
      }
      for (final cal in AuxCalendar.list.where((c) => !c.arithmetic)) {
        AuxCalendarTable? table;
        try {
          final answer = await engine!.call({'op': 'entity', 'uid': 'cal:${cal.id}'});
          table = AuxCalendarTable.parse(answer['data']);
        } catch (_) {
          table = null;
        }
        if (table == null && !_firstFive.contains(cal.id)) continue; // 달력 다섯을 더하기 전에 지은 저장소
        expect(table, isNotNull, reason: '${cal.name} 표를 받지 못했다');
        expect(table!.count, greaterThan(40000), reason: '${cal.name}: 넣을 때 실린 달 수');
        // 달마다 초하루 · 그믐을 되짚어 본다(46,716달 × 2).
        for (int i = 0; i < table.count; i++) {
          final month = table.monthAt(i);
          for (final day in [1, month.days]) {
            final jdn = month.startJdn + day - 1;
            final date = table.dateOfJdn(jdn)!;
            expect(
              table.jdnOfDate(date.year, date.month, date.day, leap: date.leap),
              jdn,
              reason: '${cal.name} ${date.year}년 ${date.leap ? '윤' : ''}${date.month}월 ${date.day}일',
            );
          }
        }
      }
    });
  });
}
