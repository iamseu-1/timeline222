import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/aux_calendar.dart' show AuxCalendarTable;
import 'package:archive_prototype/scene/ruler.dart' show ganjiOf;
import 'package:archive_prototype/ui/search_parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aux_calendar_test.dart' show lunarSlice;

// 검색 입력 해석(명세 06의 5-1)의 검사. 화면도 자료 처리부도 없이 순수 함수만 돌린다
// (맨 끝의 'real store' 묶음만 진짜 DLL + 진짜 저장소로 돈다).
// 기준은 지금 연표의 js/viewer.js(dateQuery · GANJI_ONLY · jumpSpan · focusOn)와 js/calendar.js(parse)다.

/// 검사에 쓰는 보조 달력 표 — 296~307년의 음력 조각 하나뿐이다(`aux_calendar_test.dart`).
final _lunar = lunarSlice();
AuxCalendarTable? _cals(String id) => id == 'dangi' ? _lunar : null;

void main() {
  group('낱말', () {
    test('공백으로 나누고 소문자로 맞춘다', () {
      final q = parseSearch('  유리항  Chronicle  ');
      expect(q.raw, '유리항  Chronicle');
      expect(q.terms, ['유리항', 'chronicle']);
      expect(q.date, isNull);
      expect(q.ganji, '');
      expect(q.isEmpty, isFalse);
    });

    test('빈 글은 아무것도 아니다', () {
      expect(parseSearch('   ').isEmpty, isTrue);
      expect(parseSearch('').terms, isEmpty);
    });

    test('낱말만 있으면 칸 · 가문 · 하위 문서까지 묻는다', () {
      expect(parseSearch('은결').kinds, contains('cell'));
      expect(parseSearch('은결').kinds, contains('house'));
      expect(parseSearch('은결').kinds, contains('doc'));
    });
  });

  group('연도와 날짜', () {
    test('연도만 적으면 그해 전체다', () {
      final d = parseSearch('1592').date!;
      expect(d.prec, Prec.year);
      expect(d.t, minuteOf(1592));
      expect(d.end, minuteOf(1593) - 1);
      expect(d.label, '1592년');
      expect(d.cal, 'civil');
      expect(d.note, '');
    });

    test('"년"을 붙여도 같다', () {
      expect(parseSearch('1592년').date!.t, minuteOf(1592));
    });

    test('기원전은 천문 해로 바꿔 읽는다 — 기원전 1년 다음이 1년', () {
      final d = parseSearch('기원전 108').date!;
      expect(d.year, -107);
      expect(d.t, minuteOf(-107));
      expect(d.end, minuteOf(-106) - 1);
      expect(d.label, '기원전 108년');
      expect(parseSearch('기원전 108년').date!.t, d.t);
      expect(parseSearch('BC 108').date!.t, d.t);
      expect(parseSearch('-108').date!.t, d.t);
    });

    test('0년은 없으므로 날짜로 읽지 않는다', () {
      expect(parseSearch('0').date, isNull);
    });

    test('달까지 적으면 그달 전체다', () {
      final d = parseSearch('1592년 5월').date!;
      expect(d.prec, Prec.month);
      expect(d.t, minuteOf(1592, 5));
      expect(d.end, minuteOf(1592, 6) - 1);
      expect(d.label, '1592년 5월');
    });

    test('날까지 적으면 그날 전체다', () {
      final d = parseSearch('1592-05-23').date!;
      expect(d.prec, Prec.day);
      expect(d.t, minuteOf(1592, 5, 23));
      expect(d.end, minuteOf(1592, 5, 24) - 1);
      expect(d.label, '1592년 5월 23일');
      expect(parseSearch('1592.5.23').date!.t, d.t);
      expect(parseSearch('1592년 5월 23일').date!.t, d.t);
    });

    test('시각까지 적으면 그 시간 · 그 분이다', () {
      final h = parseSearch('1592-05-23 14시').date!;
      expect(h.prec, Prec.hour);
      expect(h.t, minuteOf(1592, 5, 23, 14));
      expect(h.end, h.t + 59);
      final m = parseSearch('1592-05-23 14:30').date!;
      expect(m.prec, Prec.minute);
      expect(m.t, minuteOf(1592, 5, 23, 14, 30));
      expect(m.end, m.t);
      expect(m.label, '1592년 5월 23일 14시 30분');
    });

    test('짧은 수와 이름은 날짜로 읽지 않는다', () {
      expect(parseSearch('3.1').date, isNull);
      expect(parseSearch('유리항').date, isNull);
      expect(parseSearch('기원전 108 유리항').date, isNull, reason: '날짜 하나만 적었을 때만 날짜로 읽는다');
    });

    test('말이 안 되는 날짜는 읽지 않는다', () {
      expect(parseSearch('1592-13-01').date, isNull);
      expect(parseSearch('1592-05-32').date, isNull);
    });

    test('음력 표를 넘기지 않으면 예전 그대로 — 서력의 그해로 찾는다', () {
      final d = parseSearch('음력 1592-04-13').date!;
      expect(d.cal, 'dangi');
      expect(d.prec, Prec.year, reason: '달·날은 환산해야 알 수 있어 해까지만 쓴다');
      expect(d.t, minuteOf(1592));
      expect(d.label, '음력 1592년 4월 13일');
      expect(d.note, contains('음력 환산은 아직'));
      // 표를 넘겨도 그 표가 덮지 않는 해면 마찬가지다(조각은 296~307년).
      expect(parseSearch('음력 1592-04-13', cals: _cals).date!.note, contains('음력 환산은 아직'));
    });

    test('날짜로 읽히면 칸 · 가문 · 하위 문서는 묻지 않는다', () {
      final kinds = parseSearch('1592').kinds;
      expect(kinds, isNot(contains('cell')));
      expect(kinds, isNot(contains('house')));
      expect(kinds, contains('event'));
      expect(kinds, contains('figure'));
    });
  });

  group('간지', () {
    test('간지 하나면 "년"을 붙여도 읽는다', () {
      expect(parseSearch('갑오').ganji, '갑오');
      expect(parseSearch('갑오년').ganji, '갑오');
      expect(parseSearch('임진년').ganji, '임진');
      expect(parseSearch('갑오 전쟁').ganji, '', reason: '간지 하나만 적었을 때만');
      expect(parseSearch('갑자기').ganji, '');
    });

    test('간지 해는 60년마다 돌아오고 보기 가운데에 가까운 순이다', () {
      final years = ganjiYears('갑오', center: 1900, lo: 1500, hi: 2000);
      expect(years, isNotEmpty);
      for (final y in years) {
        expect(ganjiOf(y), '갑오');
        expect(y, greaterThanOrEqualTo(1500 - 60));
        expect(y, lessThanOrEqualTo(2000 + 60));
      }
      for (int i = 1; i < years.length; i++) {
        expect((years[i] - 1900).abs(), greaterThanOrEqualTo((years[i - 1] - 1900).abs()));
      }
      expect(years.first, 1894, reason: '1900에 가장 가까운 갑오년');
      expect(years.toSet().length, years.length);
    });

    test('기원전으로도 세고, 몇 건까지만 준다', () {
      final years = ganjiYears('갑오', center: -900, lo: -960, hi: -400, limit: 3);
      expect(years.length, 3);
      for (final y in years) {
        expect(ganjiOf(y), '갑오');
      }
      expect(years.first, -926, reason: '천문 해 −926(기원전 927년)이 −900에 가장 가깝다');
    });

    test('간지로 읽히면 칸 · 가문은 묻지 않는다', () {
      expect(parseSearch('갑오').kinds, isNot(contains('cell')));
    });
  });

  group('해와 분', () {
    test('내보내기와 같은 자리에 떨어진다', () {
      // 견본 월흔해의 첫 정권 시작(기원전 960년 = 천문 해 −959)이 −1540504800분이다.
      expect(minuteOf(-959), -1540504800);
      expect(yearAt(-1540504800), -959);
      expect(yearAt(-1540504800 + 10), -959);
      expect(yearAt(minuteOf(-959) - 1), -960);
      expect(yearText(-959), '기원전 960년');
      expect(yearText(1592), '1592년');
    });
  });

  group('가는 곳', () {
    test('날짜로 갈 때의 폭은 그 자세함 안으로 가둔다', () {
      // 해: 1.6~200년 · 달: 1.5개월~2년 · 날: 4일~2개월 · 시각: 6시간~4일
      expect(jumpSpan(Prec.year, 5000 * yearMinutes), 200 * yearMinutes);
      expect(jumpSpan(Prec.year, 5000 * yearMinutes, yearMax: 120), 120 * yearMinutes);
      expect(jumpSpan(Prec.year, 0.5 * yearMinutes), 1.6 * yearMinutes);
      expect(jumpSpan(Prec.year, 40 * yearMinutes), 40 * yearMinutes, reason: '범위 안이면 지금 폭 그대로');
      expect(jumpSpan(Prec.month, 5000 * yearMinutes), 2 * yearMinutes);
      expect(jumpSpan(Prec.day, 5000 * yearMinutes), 2 * monthMinutes);
      expect(jumpSpan(Prec.hour, 0), 6 * 60);
    });

    test('그 단위의 한가운데가 보기 한가운데에 온다', () {
      final d = parseSearch('1592').date!;
      final (lo, hi) = dateRange(d, 40 * yearMinutes);
      expect(hi - lo, closeTo(40 * yearMinutes, 1));
      expect((lo + hi) / 2, closeTo((d.t + d.end + 1) / 2, 1));
    });

    test('항목으로 갈 때는 기간의 2.2배, 점이면 지금 폭을 가둔다', () {
      const start = 0.0, len = 100 * yearMinutes;
      final (lo, hi) = itemRange(start: start, end: start + len);
      expect(hi - lo, closeTo(len * 2.2, 1));
      expect((lo + hi) / 2, closeTo(start + len / 2, 1));

      final (plo, phi) = itemRange(start: start, span: 5000 * yearMinutes);
      expect(phi - plo, closeTo(160 * yearMinutes, 1), reason: '점 사건은 해 30~160년 안으로');
      final (nlo, nhi) = itemRange(start: start, span: 2 * yearMinutes);
      expect(nhi - nlo, closeTo(30 * yearMinutes, 1));

      final (slo, shi) = itemRange(start: start, end: start + 30 * dayMinutes);
      expect(shi - slo, closeTo(30 * yearMinutes, 1), reason: '짧은 기간이어도 해 자세함이면 30년보다 좁히지 않는다');
    });
  });

  // ── 2026-09-22에 더한 것 ────────────────────────────────────────────────────────────────
  group('1582년 앞의 날짜(율리우스력)', () {
    // 기대값은 지금 연표(js/calendar.js)와 내보내기의 투영(scripts/export/base.mjs의 minute)에서 떴다.
    // 프롤렙틱 그레고리력으로 곧바로 셈하던 옛 값도 함께 적어 둔다 — 어긋나던 자리가 여기다.
    const truth = <(String, int, int, int)>[
      // (검색어, 분, 그 단위의 끝, 옛 값)
      ('1500-02-20', -247124357, -247122922, -247124160),
      ('1000-03-15', -510064131, -510062696, -510065280),
      ('100-02-25', -983445336, -983443901, -983445120),
      ('기원전 1101-10-07', -1614261262, -1614259827, -1614261600),
      ('1582-10-05', -203658044, -203656564, -203669280), // 없던 열흘 = 율리우스력의 날
      ('842-06-17', -593029440, -593028001, -593029440), // 어긋나지 않는 해(견본의 사건이 있는 날)
    ];

    test('날짜 글 → 분이 내보내기와 한 분도 어긋나지 않는다', () {
      for (final (text, t, end, _) in truth) {
        final d = parseSearch(text).date!;
        expect(d.prec, Prec.day, reason: text);
        expect(d.t, t, reason: '$text의 분');
        expect(d.end, end, reason: '$text가 걸치는 마지막 분');
      }
    });

    test('옛 값(그레고리력으로 곧바로)은 세기 해에서 최대 하루까지 밀렸다 — 그래서 놓치던 날이 있었다', () {
      for (final (text, t, _, old) in truth) {
        final d = parseSearch(text).date!;
        // 옛 창은 [옛 값, 옛 값 + 1439]였다. 사건이 그 앞에 있으면 검색이 놓쳤다.
        final missed = t < old || t > old + 1439;
        expect(d.t, t, reason: text);
        if (text == '1500-02-20' || text == '100-02-25') {
          expect(missed, isTrue, reason: '$text: 사건이 옛 창보다 앞에 있어 놓쳤다');
        }
      }
      expect(parseSearch('842-06-17').date!.t, minuteOf(842, 6, 17), reason: '어긋나지 않는 해는 옛 값과 같다');
      expect(parseSearch('1592-05-23').date!.t, minuteOf(1592, 5, 23), reason: '1582년 뒤는 늘 같다');
    });

    test('율리우스력의 윤날도 읽고, 없는 날은 거른다', () {
      expect(parseSearch('1500-02-29').date, isNotNull, reason: '율리우스력 1500년은 윤년이다');
      expect(parseSearch('1700-02-29').date, isNull);
      expect(parseSearch('1592-02-30').date, isNull);
    });
  });

  group('음력으로 적은 날짜', () {
    test('표를 넘기면 그 달로 되짚어 진짜 그날을 찾는다', () {
      final d = parseSearch('음력 301-윤05-01', cals: _cals).date!;
      expect(d.cal, 'dangi');
      expect(d.prec, Prec.day, reason: '표가 있으면 날까지 쓴다');
      expect(d.t, -877560480);
      expect(d.end, -877559041);
      expect(d.label, '음력 301년 윤5월 1일 (양력 6월 23일)', reason: '지금 연표의 describe와 같은 글');
      expect(d.note, '');
      expect(d.year, 301);
      // 서력으로 적은 같은 날과 같은 자리에 떨어진다.
      expect(parseSearch('301-06-23').date!.t, d.t);
    });

    test('달까지 · 해까지 적은 음력은 그 달 · 그 해만큼 걸친다', () {
      final month = parseSearch('음력 301-05', cals: _cals).date!;
      expect((month.prec, month.t, month.end), (Prec.month, -877602240, -877560481));
      expect(month.label, '음력 301년 5월 (양력 5월 25일부터)');
      expect(month.end + 1, parseSearch('음력 301-윤05-01', cals: _cals).date!.t, reason: '음력 5월의 끝은 윤5월 초하루 앞이다');
      final year = parseSearch('음력 301', cals: _cals).date!;
      expect((year.prec, year.t, year.end), (Prec.year, -877772160, -877246561));
      expect(year.label, '음력 301년 (양력 1월 27일부터)');
    });

    test('해 바뀜 · 없는 윤달 · 다른 달력', () {
      expect(parseSearch('음력 299-11-23', cals: _cals).date!.t, -878335200, reason: '음력 299년 11월 23일 = 서력 300년 1월 1일');
      expect(parseSearch('음력 301-윤04-01', cals: _cals).date, isNull, reason: '301년에는 윤4월이 없다');
      expect(parseSearch('음력 299-11-31', cals: _cals).date, isNull);
      // 표를 넘기지 않은 달력은 예전 그대로.
      expect(parseSearch('중국 음력 301-05-01', cals: _cals).date!.note, contains('중국 음력 환산은 아직'));
    });

    test('표 양 끝의 반 토막 해 — 표 밖의 달도 날짜로 읽어 그해로 찾는다', () {
      // 표는 서력 해로 끊어 떠 오므로 첫 해 · 마지막 해는 반 토막이다(조각은 296년 11월 ~ 308년 1월).
      // 그 밖의 달을 '날짜가 아님'으로 돌리면 검색이 낱말로 떨어져 조용히 아무것도 못 찾는다.
      final tail = parseSearch('음력 308-12-01', cals: _cals).date;
      expect(tail, isNotNull, reason: '308년 12월은 표(308년 1월까지)보다 뒤다');
      expect(tail!.note, contains('음력 환산은 아직'));
      expect((tail.prec, tail.year, tail.cal), (Prec.year, 308, 'dangi'));
      final head = parseSearch('음력 296-01-01', cals: _cals).date;
      expect(head, isNotNull, reason: '296년 1월은 표(296년 11월부터)보다 앞이다');
      expect(head!.year, 296);
      // 반 토막 해라도 표가 닿는 달은 그대로 되짚는다.
      final inside = parseSearch('음력 308-01-01', cals: _cals).date!;
      expect((inside.prec, inside.note), (Prec.day, ''));
    });
  });

  // ── 진짜 자료 처리부(DLL) + 진짜 저장소 ────────────────────────────────────────────────────
  // 가짜 답으로는 '분이 어긋난 채 통과'하는 일이 다시 생길 수 있다(2026-09-21의 교훈).
  // 그래서 **넣을 때 실린 음력 표**로 음력 날짜를 읽고, 그 분으로 실제 사건이 찾아지는지까지 본다.
  group('real store', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File('../data/moonwake3h/archive.db');
    final ready = dll.existsSync() && db.existsSync();
    // 월흔해의 유일한 '날까지 적은' 사건 — 서력 842년 6월 17일(음력 842년 5월 6일).
    const uid = 'moonwake-chronicle/p-coast-6-longest-night';
    const at = -593029440;
    ArchiveEngine? engine;
    AuxCalendarTable? table;

    setUpAll(() async {
      if (!ready) return;
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine!.start(db.absolute.path);
      table = AuxCalendarTable.parse((await engine!.call({'op': 'entity', 'uid': 'cal:dangi'}))['data']);
    });
    tearDownAll(() => engine?.close());

    test('음력으로 친 날짜가 그 사건을 찾아낸다', () async {
      if (!ready) {
        markTestSkipped('자료 처리부 DLL 또는 data/moonwake3h 저장소가 없습니다');
        return;
      }
      expect(table, isNotNull);
      AuxCalendarTable? cals(String id) => id == 'dangi' ? table : null;

      final solar = parseSearch('842-06-17', cals: cals).date!;
      final lunar = parseSearch('음력 842-05-06', cals: cals).date!;
      expect(solar.t, at, reason: '저장소에 실린 그 사건의 분');
      expect(lunar.t, at, reason: '음력으로 적어도 같은 자리');
      expect(lunar.label, '음력 842년 5월 6일 (양력 6월 17일)');
      expect(lunar.note, '');

      for (final date in [solar, lunar]) {
        final answer = await engine!.call({
          'op': 'search_year',
          't': date.t,
          'end': date.end,
          'kinds': ['event'],
          'limit': 21,
          'after': 0,
        });
        final data = answer['data'];
        final items = data is Map ? (data['items'] as List? ?? const []) : (data as List? ?? const []);
        expect(items.map((row) => (row as Map)['uid']), contains(uid), reason: '${date.label}로 찾은 결과');
      }
    });
  });
}
