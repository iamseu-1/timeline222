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

  // ── 진짜 자료 처리부(DLL) + 진짜 저장소 ────────────────────────────────────────────────────
  // 잘라 박은 조각이 아니라 **넣을 때 실제로 실린 표 다섯**을 통째로 받아 되짚기를 건다.
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
      for (final cal in AuxCalendar.list) {
        final answer = await engine!.call({'op': 'entity', 'uid': 'cal:${cal.id}'});
        final table = AuxCalendarTable.parse(answer['data']);
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
