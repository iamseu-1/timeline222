import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/aux_calendar.dart' show AuxCalendar, AuxCalendarTable;
import 'package:flutter_test/flutter_test.dart';
import 'package:archive_prototype/ui/date_text.dart';

import 'aux_calendar_test.dart' show auxSlice, lunarSlice;

// 명세 06의 2-4절(날짜 글 규칙)과 같은 글이 나오는지 — 기준은 지금 연표의 js/viewer.js:40~150 · js/calendar.js · js/core.js.
// 견본의 값은 월흔해 가져오기(prototype/results/compat/moonwake-layout3.json)의 해 좌표를 썼다.
//
// 아래 '지금 연표와 대조' 묶음의 기대값은 **지금 연표의 js/calendar.js를 노드로 돌려** 떴다
// (임시 도구 `prototype/scripts/tmp-11-dates-ref.mjs` — js는 읽기만 한다). 분은 내보내기의 투영
// (`scripts/export/base.mjs`의 `minute`) 그대로다.

/// 검사에 쓰는 보조 달력 표 — 296~307년의 음력 조각 하나뿐이다(`aux_calendar_test.dart`).
final _lunar = lunarSlice();
AuxCalendarTable? _cals(String id) => id == 'dangi' ? _lunar : null;

/// (날짜 글, 해 좌표, 분, 서력 글) — 지금 연표에서 뜬 값.
const _civilTruth = <(String, double, int, String)>[
  ('1582-10-04', 1582.7774647887325, -203659525, '1582년 10월 4일'),
  ('1582-10-05', 1582.7802816901408, -203658044, '1582년 10월 15일'), // 없던 열흘은 율리우스력의 날로 받는다
  ('1582-10-14', 1582.8056338028168, -203644719, '1582년 10월 24일'),
  ('1582-10-15', 1582.7802816901408, -203658044, '1582년 10월 15일'),
  ('1582-10-16', 1582.7830985915493, -203656563, '1582년 10월 16일'),
  ('1500-02-20', 1500.136612021858, -247124357, '1500년 2월 20일'),
  ('1500-02-29', 1500.1612021857923, -247111432, '1500년 2월 29일'), // 율리우스력의 윤날
  ('1500-03-01', 1500.1639344262296, -247109996, '1500년 3월 1일'),
  ('1500-12-31', 1500.9972677595629, -246671996, '1500년 12월 31일'),
  ('1000-01-01', 1000, -510170400, '1000년 1월 1일'),
  ('1000-03-15', 1000.2021857923497, -510064131, '1000년 3월 15일'),
  ('1000-12-31', 1000.9972677595629, -509646236, '1000년 12월 31일'),
  ('900-12-03', 900.9207650273224, -562281006, '900년 12월 3일'),
  ('100-02-25', 100.15027322404372, -983445336, '100년 2월 25일'),
  ('300-01-23', 300.0601092896175, -878303607, '300년 1월 23일'),
  ('기원전 1101-10-07', -1100.2349726775956, -1614261262, '기원전 1101년 10월 7일'),
  ('기원전 100-03-01', -99.83835616438355, -1088104320, '기원전 100년 3월 1일'),
  ('기원전 1-12-31', -0.002732240437158473, -1035594720, '기원전 1년 12월 31일'),
  ('1-01-01', 1, -1035593280, '1년 1월 1일'),
  ('827-05-12', 827.358904109589, -600971040, '827년 5월 12일'),
  ('842-06-17 16:10', 842.4593797564688, -593028470, '842년 6월 17일 16시 10분'),
  ('1592-05-23', 1592.3907103825136, -198603360, '1592년 5월 23일'),
  ('2026-09-20', 2026.717808219178, 29831040, '2026년 9월 20일'),
];

/// 무작위 대조 — 앞의 열하나는 율리우스력과 그레고리력의 윤년이 어긋나는 세기 해다.
const _randomTruth = <(String, double, int)>[
  ('기원전 1901-10-18', -1900.204918032787, -2035004825),
  ('기원전 1501-03-13', -1500.8032786885246, -1824939643),
  ('기원전 1101-12-27', -1100.0136612021859, -1614144940),
  ('기원전 101-03-19', -100.78688524590164, -1088602867),
  ('100-12-25', 100.98087431693989, -983008772),
  ('300-06-15', 300.4535519125683, -878096813),
  ('500-02-16', 500.1256830601093, -773078581),
  ('900-05-14', 900.3661202185792, -562572527),
  ('1000-08-16', 1000.6229508196722, -509842977),
  ('1400-05-06', 1400.344262295082, -299609776),
  ('1500-05-18', 1500.377049180328, -246997983),
  ('477-03-28', 477.23561643835615, -785116800),
  ('기원전 1474-10-12', -1473.2219178082191, -1810434240),
  ('기원전 131-04-05', -130.74246575342465, -1104357600),
  ('기원전 397-03-03', -396.8306010928962, -1244306880),
  ('824-10-20', 824.8005464480874, -602316000),
  ('기원전 1167-02-26', -1166.8465753424657, -1649295360),
  ('1324-09-16', 1324.707650273224, -339390720),
  ('173-12-27', 173.986301369863, -944611200),
  ('1424-01-19', 1424.049180327869, -287143200),
  ('869-07-17', 869.5397260273973, -578784960),
  ('490-09-23', 490.7260273972603, -778021920),
  ('1033-01-25', 1033.0657534246575, -492779520),
  ('기원전 602-11-16', -601.1260273972603, -1351755360),
  ('1222-12-14', 1222.9506849315069, -392909760),
  ('688-06-22', 688.4726775956284, -674017920),
  ('기원전 295-01-01', -295, -1190748960),
  ('1209-12-21', 1209.9698630136986, -399736800),
  ('643-02-12', 643.1150684931507, -697874400),
  ('1031-03-09', 1031.1835616438357, -493770240),
  ('기원전 239-01-03', -238.9945205479452, -1161292320),
  ('기원전 322-04-23', -321.6931506849315, -1204787520),
  ('기원전 977-07-28', -976.4289617486339, -1549146240),
  ('기원전 983-07-25', -982.4383561643835, -1552307040),
  ('1005-06-10', 1005.4383561643835, -507310560),
];

void main() {
  group('해 좌표와 달력', () {
    test('정수는 그해 1월 1일이고 0년 자리는 없다', () {
      expect(civilAt(1).month, 1);
      expect(civilAt(1).day, 1);
      expect(civilAt(1).year, 1);
      expect(civilAt(-1).year, -1);
      // 0년 자리는 1년 1월 1일로 본다(js/calendar.js cal.at).
      expect(civilAt(0).year, 1);
      expect(civilAt(0).month, 1);
    });

    test('1582년 10월 15일 앞은 율리우스력으로 센다', () {
      // 그레고리력 첫날의 날 번호.
      expect(jdnOf(1582, 10, 15), 2299161);
      // 그 바로 앞날은 율리우스력 1582년 10월 4일.
      final before = civilOfJdn(2299160);
      expect([before.year, before.month, before.day], [1582, 10, 4]);
    });

    test('날짜 글을 읽고 다시 적으면 같다', () {
      final t = parseAt('827-05-12')!;
      expect(formatT(t, DatePrec.day), '827년 5월 12일');
      expect(atFits('827-05-12', t), isTrue);
      expect(atFits('827-05-13', t), isFalse);
      expect(parseAt('기원전 108'), closeTo(-108, 1e-9));
      expect(formatT(parseAt('기원전 108')!, DatePrec.year), '기원전 108년');
    });
  });

  group('계약의 시간(분)과 해 좌표', () {
    test('견본의 분 값과 맞는다', () {
      // 월흔해 견본의 x_dynasties: 해 좌표 −960 · −680 → 분 −1540504800 · −1393238880.
      expect(minutesOfT(-960), closeTo(-1540504800, 1));
      expect(minutesOfT(-680), closeTo(-1393238880, 1));
      expect(tOfMinutes(-1540504800), closeTo(-960, 1e-6));
    });
  });

  group('한 시점의 글', () {
    test('기원전과 해 · 달 · 날 · 시각', () {
      expect(yearText(-960), '기원전 960년');
      expect(yearText(827), '827년');
      final t = parseAt('827-05-12 03:20')!;
      expect(formatT(t, DatePrec.year), '827년');
      expect(formatT(t, DatePrec.month), '827년 5월');
      expect(formatT(t, DatePrec.day), '827년 5월 12일');
      expect(formatT(t, DatePrec.hour), '827년 5월 12일 3시');
      expect(formatT(t, DatePrec.minute), '827년 5월 12일 3시 20분');
    });

    test('whenText는 날짜 글이 값과 맞으면 그 글, 아니면 서력 날짜', () {
      expect(whenText(827, at: '827-05-12'), '827년'); // 글이 값과 맞지 않으면 값이 이긴다
      final t = parseAt('827-05-12')!;
      expect(whenText(t, at: '827-05-12'), '827년 5월 12일');
      expect(whenText(t), '827년 5월 12일'); // 정수가 아니면 서력 날짜
      expect(whenText(-960), '기원전 960년');
    });

    test('endText는 오늘과 같으면 현재', () {
      expect(endText(2026.72, now: 2026.72), '현재');
      expect(endText(876, now: 2026.72), '876년');
    });
  });

  group('보기 폭과 두 시점', () {
    test('precFor — 12년 · 9달 · 나흘의 문턱', () {
      expect(precFor(20), DatePrec.year);
      expect(precFor(5), DatePrec.month);
      expect(precFor(.5), DatePrec.day);
      expect(precFor(.001), DatePrec.hour);
    });

    test('spanRange — 같은 해면 뒤쪽의 겹치는 앞부분을 줄인다', () {
      expect(spanRange(-960, -400), '기원전 960년 ~ 기원전 400년');
      final a = parseAt('1592-05-03')!, b = parseAt('1592-05-20')!;
      expect(spanRange(a, b, DatePrec.day), '1592년 5월 3일 ~ 20일');
      final c = parseAt('1594-02-01')!;
      expect(spanRange(a, c, DatePrec.month), '1592년 5월 ~ 1594년 2월');
    });
  });

  group('기간 글 · 미정 · 현재까지', () {
    test('rangeText — 미정 · 현재 · 한 점', () {
      expect(rangeText(start: -960, end: -400), '기원전 960년 ~ 기원전 400년');
      expect(rangeText(start: 808, startUnknown: true), '미정');
      expect(rangeText(start: 1000, end: 1200, endUnknown: true), '1000년 ~ 미정');
      expect(rangeText(start: 1980, ongoing: true), '1980년 ~ 현재');
      expect(rangeText(start: 827, end: 827), '827년');
    });

    test('durationText', () {
      expect(durationText(-960, 240, DatePrec.year), '1,200년');
      final a = parseAt('1000-01-01')!, b = parseAt('1003-03-01')!;
      expect(durationText(a, b, DatePrec.month), '3년 2개월');
      final c = parseAt('1000-04-12')!;
      expect(durationText(a, c, DatePrec.day), '3개월 11일 (102일)');
      final d = parseAt('1000-01-03 05:00')!;
      expect(durationText(a, d, DatePrec.hour), '2일 5시간');
      expect(durationText(a, a + .0001, DatePrec.day), '하루 미만');
      expect(durationText(a, a + 1e-7, DatePrec.hour), '한 시간 미만');
    });

    test('미정 안내와 연대 폭의 이르면 · 늦으면', () {
      expect(unknownStartNote(808), '시작 연도 미정 — 연표에는 808년 무렵에 자리를 잡았습니다');
      expect(unknownEndNote(876), '끝 연도 미정 — 연표에는 876년 무렵까지로 그렸습니다');
      expect(cellUnknownStartNote(808), '시작 미정 — 연표에는 808년 무렵부터 놓았습니다');
      expect(cellUnknownEndNote(876), '끝 미정 — 연표에는 876년 무렵까지 놓았습니다');
      expect(rangeNote('시작', -1060, -1000), '시작 — 이르면 기원전 1060년, 늦으면 기원전 1000년');
    });
  });

  group('조약의 사이 간격 · 그날의 곁들임', () {
    test('gapText — 날까지면 일 · 개월, 달까지면 개월, 아니면 해', () {
      final sign = parseAt('827-05-12')!, ratify = parseAt('827-07-04')!;
      expect(gapText(sign, ratify, aAt: '827-05-12', bAt: '827-07-04'), '53일 뒤');
      final far = parseAt('829-01-01')!;
      expect(gapText(sign, far, aAt: '827-05-12', bAt: '829-01-01'), '20개월 뒤');
      expect(gapText(827, 876), '49년 뒤');
      expect(gapText(827, 827.4), '같은 해');
      expect(gapText(876, 827), '');
    });

    test('dayNote — 일진과 요일', () {
      final t = parseAt('1949-10-01')!;
      expect(dayNote(t), '갑자일 · 토요일');
    });

    test('dayNote — 음력 표를 넣어 주면 앞에 음력을 곁들인다', () {
      // 표는 넣을 때 한 번 뜬 '달의 시작 표'다(계약 6-3절). 기준은 지금 연표의 기준 덤프 `일진-하루`:
      // 음력 299년 12월 15일 = 서력 300년 1월 23일.
      final table = lunarSlice();
      final t = parseAt('300-01-23')!;
      expect(civilAt(t).jdn, 1830655);
      expect(dayNote(t), '무신일 · 화요일', reason: '표를 안 주면 예전 그대로');
      expect(dayNote(t, lunar: table), '음력 12월 15일 · 무신일 · 화요일');
      // 날짜를 이미 음력으로 적었으면 곁들임을 또 붙이지 않는다(지금 연표의 dayNote(t, !lunarAt(x))).
      expect(dayNote(t, lunar: table, withLunar: false), '무신일 · 화요일');
      // 표가 덮지 않는 날은 음력 없이 적는다.
      expect(dayNote(parseAt('1949-10-01')!, lunar: table), '갑자일 · 토요일');
    });

    test('isLunarAt — 음력으로 적은 날짜 글을 가린다', () {
      expect(isLunarAt('음력 1592-04-13'), isTrue);
      expect(isLunarAt('음력 1592년 윤4월 13일'), isTrue);
      expect(isLunarAt('중국 음력 1592-04-13'), isTrue);
      expect(isLunarAt('음 1592.4.13'), isTrue);
      expect(isLunarAt('1592-04-13 음력'), isTrue, reason: '뒷말로 적어도 음력이다');
      expect(isLunarAt('1592-04-13 (음력)'), isTrue, reason: '뒤 괄호로 적어도 음력이다');
      expect(isLunarAt('1592-04-13'), isFalse);
      expect(isLunarAt('이슬람력 1000-08-11'), isFalse, reason: '음력이 아닌 달력에는 음력을 곁들인다');
      expect(isLunarAt('율리우스력 1000-03-15'), isFalse);
      expect(isLunarAt(null), isFalse);
    });
  });

  // ── 2026-09-22에 더한 것 ────────────────────────────────────────────────────────────────
  group('지금 연표와 대조 — 서력 · 율리우스력 · 분', () {
    test('날짜 글 → 해 좌표 · 분 · 서력 글이 지금 연표와 같다(경계 23건)', () {
      for (final (text, t, minute, shown) in _civilTruth) {
        final p = readAt(text);
        expect(p, isNotNull, reason: text);
        expect(p!.t, closeTo(t, 1e-12), reason: '$text의 해 좌표');
        expect(minutesOfT(p.t), minute.toDouble(), reason: '$text의 분(내보내기와 같은 투영)');
        expect(formatT(p.t, p.prec), shown, reason: '$text를 다시 적은 글');
        expect(tOfMinutes(minutesOfT(p.t)), closeTo(p.t, 1e-6), reason: '$text: 분 → 해 좌표가 제자리');
      }
    });

    test('무작위 35건도 한 분도 어긋나지 않는다(율리우스력 윤년이 어긋나는 세기 해 포함)', () {
      for (final (text, t, minute) in _randomTruth) {
        final p = readAt(text);
        expect(p, isNotNull, reason: text);
        expect(p!.t, closeTo(t, 1e-12), reason: '$text의 해 좌표');
        expect(minutesOfT(p.t), minute.toDouble(), reason: '$text의 분');
      }
    });

    test('달력을 못박으면 그 달력으로 센다 — 1000년 3월 15일은 엿새가 다르다', () {
      expect(readAt('율리우스력 1000-03-15')!.jdn, 2086382);
      expect(readAt('그레고리력 1000-03-15')!.jdn, 2086376);
      expect(readAt('1000-03-15')!.jdn, 2086382, reason: '서력은 1582년 앞에서 율리우스력이다');
      expect(atText(readAt('율리우스력 1000-03-15')!), '율리우스력 1000년 3월 15일 (양력 3월 15일)');
      expect(atText(readAt('그레고리력 1000-03-15')!), '그레고리력 1000년 3월 15일 (양력 3월 9일)');
    });

    test('없는 날은 읽지 않는다 — 그레고리력의 1700년 2월 29일', () {
      expect(readAt('1700-02-29'), isNull);
      expect(readAt('1592-02-30'), isNull);
      expect(readAt('1500-02-29'), isNotNull, reason: '율리우스력 1500년은 윤년이다');
      expect(readAt('1600-02-29'), isNotNull);
    });

    test('일진과 요일은 달력과 무관하게 날 번호로만 센다', () {
      // 지금 연표의 기준값(js/calendar.js의 dayGanji).
      expect(dayGanji(2433191), '갑자'); // 1949-10-01
      expect(dayGanji(2299160), '계유'); // 율리우스력 1582-10-04
      expect(dayGanji(2299161), '갑술'); // 그다음 날 = 그레고리력 1582-10-15
      // 없던 열흘을 건너뛰어도 일진 · 요일은 하루씩만 나아간다.
      final a = readAt('1582-10-04')!, b = readAt('1582-10-15')!;
      expect(b.jdn! - a.jdn!, 1);
      expect(dayNote(a.t), '계유일 · 목요일');
      expect(dayNote(b.t), '갑술일 · 금요일');
    });

    test('unitEnd — 14시의 끝은 15시다(1시가 아니다)', () {
      final t = parseAt('1592-05-23 14시')!;
      expect(minutesOfT(unitEnd(t, DatePrec.hour)) - minutesOfT(t), 60);
      expect(formatT(unitEnd(t, DatePrec.hour), DatePrec.hour), '1592년 5월 23일 15시');
      final m = parseAt('1592-05-23 14:30')!;
      expect(minutesOfT(unitEnd(m, DatePrec.minute)) - minutesOfT(m), 1);
      final d = parseAt('1592-05-23')!;
      expect(minutesOfT(unitEnd(d, DatePrec.day)) - minutesOfT(d), 1440);
    });
  });

  group('음력으로 적은 날짜 글', () {
    test('표를 넣어 주면 음력 · 윤달까지 읽는다', () {
      // 기대값은 지금 연표(ICU)에서 뜬 것. 표는 296~307년 조각이다.
      final p = readAt('음력 299-11-23', cals: _cals)!;
      expect((p.cal, p.year, p.month, p.leap, p.day), ('dangi', 299, 11, false, 23));
      expect(p.jdn, 1830633);
      expect(p.t, closeTo(300, 1e-12), reason: '음력 299년 11월 23일 = 서력 300년 1월 1일');
      expect(p.exact, isTrue);
      expect(p.lunar, isTrue);

      final leap = readAt('음력 301-윤05-01', cals: _cals)!;
      expect((leap.month, leap.leap, leap.jdn), (5, true, 1831172));
      expect(leap.t, closeTo(301.4739726027397, 1e-12));
      expect(readAt('음력 301년 윤5월 1일', cals: _cals)!.jdn, 1831172, reason: '한글 꼴도 같다');
      expect(readAt('음 301.5.1', cals: _cals)!.jdn, 1831143, reason: '윤달이 아닌 5월');
      expect(readAt('300-01-23 (음력)', cals: _cals)!.jdn, 1830692, reason: '뒤 괄호로 적어도 음력');
      expect(readAt('음력 304-윤03-01', cals: _cals)!.jdn, 1832206);
      expect(readAt('음력 301-윤05-01 14:30', cals: _cals)!.t, closeTo(301.4756278538813, 1e-12));
    });

    test('달까지 · 해까지 적은 음력', () {
      final month = readAt('음력 301-05', cals: _cals)!;
      expect((month.prec, month.jdn), (DatePrec.month, 1831143));
      expect(atText(month), '음력 301년 5월 (양력 5월 25일부터)');
      final year = readAt('음력 301', cals: _cals)!;
      expect((year.prec, year.jdn), (DatePrec.year, 1831025));
      expect(atText(year), '음력 301년 (양력 1월 27일부터)');
      // 달의 끝은 **음력의 달**이다(29 · 30일).
      expect(unitEnd(month.t, DatePrec.month, cal: _lunar), closeTo(301.4739726027397, 1e-12));
    });

    test('없는 윤달 · 없는 날은 읽지 않는다', () {
      expect(readAt('음력 301-윤04-01', cals: _cals), isNull, reason: '301년에는 윤4월이 없다');
      expect(readAt('음력 299-11-31', cals: _cals), isNull, reason: '그 달은 30일까지다');
      expect(readAt('음력 301-13-01', cals: _cals), isNull);
      expect(readAt('율리우스력 1000-윤03-01'), isNull, reason: '윤달은 음력에만 있다');
    });

    test('표가 없거나 표 밖의 해면 예전 그대로 — 적힌 수를 서력으로 읽고 그렇다고 적어 둔다', () {
      final far = readAt('음력 1592-04-13', cals: _cals)!; // 조각(296~307년) 밖
      expect(far.exact, isFalse);
      expect(far.cal, 'dangi');
      expect(far.lunar, isTrue, reason: '못 셈해도 음력으로 적은 것은 맞다');
      expect(far.t, closeTo(parseAt('1592-04-13')!, 1e-12));
      expect(atText(far), '음력 1592년 4월 13일', reason: '곁들일 서력을 모르니 적힌 그대로만');
      expect(readAt('음력 299-11-23')!.exact, isFalse, reason: '표를 안 넘기면 예전 그대로');
      expect(readAt('중국 음력 301-05-01', cals: _cals)!.exact, isFalse, reason: '중국 음력 표는 넘기지 않았다');
      // 윤달은 서력으로 읽을 수 없어 해까지만 읽는다(옛 parseAt도 그랬다).
      final leap = readAt('음력 301년 윤5월 1일')!;
      expect((leap.prec, leap.t, leap.exact), (DatePrec.year, 301.0, false));
    });

    test('표 양 끝의 반 토막 해 — 표 밖의 달도 예전 길로 읽는다(못 읽은 글로 만들지 않는다)', () {
      // 표는 서력 해로 끊어 떠 오므로 첫 해 · 마지막 해는 반 토막이다(조각은 296년 11월 ~ 308년 1월).
      // 해로만 가르면 296년 1월 · 308년 12월이 null이 되어, 검색이 그 글을 날짜가 아닌 것으로 보고
      // 낱말로 떨어져 조용히 아무것도 못 찾는다(2026-09-22에 고친 자리).
      final head = readAt('음력 296-01-01', cals: _cals);
      expect(head, isNotNull, reason: '296년 1월은 표(296년 11월부터)보다 앞이다');
      expect(head!.exact, isFalse);
      expect(head.lunar, isTrue);
      expect(head.t, closeTo(parseAt('296-01-01')!, 1e-12), reason: '적힌 수를 서력으로 읽는다');
      final tail = readAt('음력 308-12-01', cals: _cals);
      expect(tail, isNotNull, reason: '308년 12월은 표(308년 1월까지)보다 뒤다');
      expect(tail!.exact, isFalse);
      expect(tail.t, closeTo(parseAt('308-12-01')!, 1e-12));
      expect(readAt('음력 296', cals: _cals)!.exact, isFalse, reason: '해까지만 적어도 296년의 1월은 표 밖이다');
      expect(readAt('음력 308', cals: _cals)!.exact, isTrue, reason: '308년은 1월이 표 안이라 해의 시작을 셈할 수 있다');
      // 반 토막 해라도 표가 닿는 달은 그대로 셈한다.
      final first = readAt('음력 296-11-01', cals: _cals)!;
      expect((first.exact, first.jdn), (true, 1829518));
      final last = readAt('음력 308-01-01', cals: _cals)!;
      expect((last.exact, last.jdn), (true, _lunar.jdnOfDate(308, 1, 1)));
      // 표가 닿는 해에서 잘못 적은 글은 그대로 null이다.
      expect(readAt('음력 301-윤04-01', cals: _cals), isNull, reason: '301년에는 윤4월이 없다');
      expect(readAt('음력 299-11-31', cals: _cals), isNull, reason: '그 달은 30일까지다');
    });

    test('whenText — 음력으로 적은 값은 서력을 곁들여 적는다(지금 연표의 describe)', () {
      final t = parseAt('음력 301-윤05-01', cals: _cals)!;
      expect(whenText(t, at: '음력 301-윤05-01', cals: _cals), '음력 301년 윤5월 1일 (양력 6월 23일)');
      expect(whenText(t, at: '음력 301-윤05-01'), '301년 6월 23일', reason: '표가 없으면 예전처럼 셈해 둔 서력 날짜');
      expect(whenText(parseAt('음력 300-12-15', cals: _cals)!, at: '음력 300-12-15', cals: _cals), '음력 300년 12월 15일 (양력 301년 1월 11일)',
          reason: '해가 다르면 서력의 해도 적는다');
      expect(
        rangeText(start: parseAt('음력 299-11-23', cals: _cals), startAt: '음력 299-11-23', end: t, endAt: '음력 301-윤05-01', cals: _cals),
        '음력 299년 11월 23일 (양력 300년 1월 1일) ~ 음력 301년 윤5월 1일 (양력 6월 23일)',
      );
    });

    test('dayNote — 음력으로 적은 날에는 곁들임을 또 붙이지 않는다', () {
      final at = '음력 300-01-23';
      final t = parseAt(at, cals: _cals)!;
      expect(civilAt(t).jdn, 1830692);
      expect(dayNote(t, lunar: _lunar), '음력 1월 23일 · 을유일 · 목요일');
      expect(dayNote(t, lunar: _lunar, withLunar: !isLunarAt(at)), '을유일 · 목요일');
    });

    test('endIn — 음력 달까지 적은 끝은 그 음력 달의 끝까지다', () {
      final month = readAt('음력 301-05', cals: _cals)!;
      final got = endIn(endY: month.t, endAt: '음력 301-05', cals: _cals)!;
      expect(got, closeTo(301.4739726027397 - 1e-9, 1e-9), reason: '윤5월 초하루 바로 앞');
    });
  });

  // ── 달력 다섯(2026-10-24 리메이크 6단계 결정 D10) ───────────────────────────────────────────────
  // 기대값(날 번호 · 해 좌표 · 글)은 지금 연표의 `HT.cal.parse` · `HT.cal.describe`를 노드로 돌려 떴다.
  // 표는 `aux_calendar_test.dart`의 2023 ~ 2024년 조각이다(불기는 표가 없다).
  group('달력 다섯 — 이름 · 앞말 · 낱말', () {
    final slices = {for (final id in ['hebrew', 'ethiopic', 'coptic', 'indian']) id: auxSlice(id)};
    AuxCalendarTable? cals(String id) => slices[id];
    AuxCalendarTable? none(String id) => null;

    test('앞말 · 낱말 · 뒤 괄호로 달력을 고르고, 그 달력의 이름으로 적는다', () {
      // (글, 달력, 이름, 날 번호, 해 좌표, 지금 연표의 describe)
      const truth = <(String, String, String, int, double, String)>[
        ('히브리력 5784-01-01', 'hebrew', '히브리력', 2460204, 2023.7068493150684, '히브리력 5784년 1월 1일 (양력 2023년 9월 16일)'),
        ('히브리력 5784-13-29', 'hebrew', '히브리력', 2460586, 2024.7513661202186, '히브리력 5784년 13월 29일 (양력 2024년 10월 2일)'),
        ('히브리력 5784-06-01', 'hebrew', '히브리력', 2460351, 2024.1092896174864, '히브리력 5784년 6월 1일 (양력 2024년 2월 10일)'),
        ('유대력 5784년 7월 14일', 'hebrew', '히브리력', 2460394, 2024.2267759562842, '히브리력 5784년 7월 14일 (양력 2024년 3월 24일)'),
        ('에티오피아력 2015-13-06', 'ethiopic', '에티오피아력', 2460199, 2023.6931506849314, '에티오피아력 2015년 13월 6일 (양력 2023년 9월 11일)'),
        ('에티오피아력 2016-01-01', 'ethiopic', '에티오피아력', 2460200, 2023.695890410959, '에티오피아력 2016년 1월 1일 (양력 2023년 9월 12일)'),
        ('에티오피아력 2016-13-05', 'ethiopic', '에티오피아력', 2460564, 2024.691256830601, '에티오피아력 2016년 13월 5일 (양력 2024년 9월 10일)'),
        ('콥트력 1739-13-06', 'coptic', '콥트력', 2460199, 2023.6931506849314, '콥트력 1739년 13월 6일 (양력 2023년 9월 11일)'),
        ('콥트력 1740년 13월 5일', 'coptic', '콥트력', 2460564, 2024.691256830601, '콥트력 1740년 13월 5일 (양력 2024년 9월 10일)'),
        ('사카력 1945-01-01', 'indian', '사카력', 2460026, 2023.2191780821918, '사카력 1945년 1월 1일 (양력 2023년 3월 22일)'),
        ('사카력 1946-01-01', 'indian', '사카력', 2460391, 2024.2185792349726, '사카력 1946년 1월 1일 (양력 2024년 3월 21일)'),
        ('불기 2567-01-01', 'buddhist', '불기', 2460311, 2024, '불기 2567년 1월 1일 (양력 2024년 1월 1일)'),
        ('타이 불기 2567-02-29', 'buddhist', '불기', 2460370, 2024.1612021857923, '불기 2567년 2월 29일 (양력 2024년 2월 29일)'),
        ('2567-05-01 (불기)', 'buddhist', '불기', 2460432, 2024.3306010928961, '불기 2567년 5월 1일 (양력 2024년 5월 1일)'),
        ('불기 2125-10-04', 'buddhist', '불기', 2299160, 1582.7774647887325, '불기 2125년 10월 4일 (양력 1582년 10월 4일)'),
        ('불기 2125-10-05', 'buddhist', '불기', 2299161, 1582.7802816901408, '불기 2125년 10월 5일 (양력 1582년 10월 15일)'),
        ('불기 2125-10-15', 'buddhist', '불기', 2299161, 1582.7802816901408, '불기 2125년 10월 15일 (양력 1582년 10월 15일)'),
        ('불기 544-01-01', 'buddhist', '불기', 1721424, 1, '불기 544년 1월 1일 (양력 1년 1월 1일)'),
      ];
      for (final (text, cal, name, jdn, t, described) in truth) {
        final p = readAt(text, cals: cals);
        expect(p, isNotNull, reason: text);
        expect((p!.cal, p.name, p.jdn, p.exact, p.lunar), (cal, name, jdn, true, false), reason: text);
        expect(p.t, closeTo(t, 1e-12), reason: text);
        expect(atText(p), described, reason: '$text — 지금 연표의 describe');
        expect(whenText(p.t, at: text, cals: cals), described, reason: '$text — 값과 맞는 날짜 글은 그 글로');
        expect(isLunarAt(text, cals: cals), isFalse, reason: '$text — 음력이 아니니 음력 곁들임은 그대로 붙는다');
      }
    });

    test('해까지 적은 글 — 그 달력의 새해부터', () {
      final hebrew = readAt('히브리력 5784', cals: cals)!;
      expect((hebrew.prec, hebrew.jdn, hebrew.exact), (DatePrec.year, 2460204, true));
      expect(atText(hebrew), '히브리력 5784년 (양력 2023년 9월 16일부터)');
      final be = readAt('불기 2567', cals: none)!;
      expect((be.prec, be.t, be.jdn, be.exact), (DatePrec.year, 2024.0, 2460311, true));
      expect(atText(be), '불기 2567년 (양력 2024년 1월 1일부터)');
      final first = readAt('불기 543', cals: none)!;
      expect(first.t, -1, reason: '불기 543년 = 기원전 1년');
      expect(atText(first), '불기 543년 (양력 기원전 1년 1월 1일부터)');
    });

    test('없는 날 · 없는 13월 · 0년은 읽지 않는다(지금 연표가 거절하는 글)', () {
      for (final text in [
        '히브리력 5783-13-01', // 5783년은 평년 — 13월이 없다
        '에티오피아력 2015-13-07', // 그해의 13째 달은 6일까지
        '에티오피아력 2016-13-06', // 그해의 13째 달은 5일까지
        '불기 2566-02-29', // 2023년 2월은 28일까지
        '사카력 1946-13-01', // 12달 달력
        '불기 2567-13-01',
        '페르시아력 1400-13-01',
        '음력 301-13-01',
        '히브리력 0',
        '불기 0',
        '불기 2567-윤01-01', // 윤달은 음력에만
      ]) {
        expect(readAt(text, cals: cals), isNull, reason: text);
      }
      expect(readAt('기원전 불기 5', cals: none), isNull, reason: '불기는 1년부터');
    });

    test('불기는 표 없이도 셈한다 · 표가 있어야 하는 넷은 표가 없으면 예전 길로', () {
      expect(readAt('불기 2567-01-01')!.exact, isTrue, reason: '표를 넘기지 않아도');
      expect(readAt('불기 2567-01-01')!.jdn, 2460311);
      // 표가 없으면 적힌 수를 서력으로 읽는다 — 13월은 서력에 없으므로 해까지만(윤달과 같은 길).
      final m13 = readAt('히브리력 5784-13-29', cals: none)!;
      expect((m13.cal, m13.exact, m13.prec, m13.t), ('hebrew', false, DatePrec.year, 5784.0));
      final m7 = readAt('히브리력 5784-07-14', cals: none)!;
      expect((m7.exact, m7.prec), (false, DatePrec.day));
      expect(m7.t, closeTo(parseAt('5784-07-14')!, 1e-12));
      expect(atText(m7), '히브리력 5784년 7월 14일', reason: '못 셈한 글은 적힌 그대로');
      // 표 밖의 달도 같은 길(조각은 사카력 1946년 10월까지다).
      final far = readAt('인도 국정력 1946-12-30', cals: cals)!;
      expect((far.cal, far.name, far.exact), ('indian', '사카력', false));
    });

    test('endIn — 13째 달까지 적은 끝은 그 짧은 달의 끝까지다', () {
      final m = readAt('에티오피아력 2016-13', cals: cals)!;
      expect((m.prec, m.jdn), (DatePrec.month, 2460560));
      expect(endIn(endY: m.t, endAt: '에티오피아력 2016-13', cals: cals), closeTo(tOfJdn(2460565) - 1e-9, 1e-12), reason: '5일 뒤 새해 바로 앞');
      final be = readAt('불기 2567-02', cals: none)!;
      expect(endIn(endY: be.t, endAt: '불기 2567-02', cals: none), closeTo(tOfJdn(jdnOf(2024, 3, 1)) - 1e-9, 1e-12), reason: '불기의 달은 서력의 달');
    });
  });

  // ── 진짜 자료 처리부(DLL) + 진짜 저장소 ────────────────────────────────────────────────────
  // 잘라 박은 조각이 아니라 **넣을 때 실제로 실린 표 다섯**으로 날짜 글을 읽는다.
  // (어제의 교훈: 가짜 답으로만 검사하면 실제 앱에서만 비는 일이 생긴다.
  //  실제 표는 서력 해로 끊어 떠 오므로 양 끝의 해가 반 토막이다 — 조각 검사만으로는 그 자리가 안 잡힌다.)
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

    test('표 다섯의 반 토막 해 — 표 밖의 달도 날짜로 읽힌다(exact는 거짓)', () async {
      if (!ready) {
        markTestSkipped('자료 처리부 DLL 또는 data/moonwake3h 저장소가 없습니다');
        return;
      }
      // 달력 다섯(결정 D10) 가운데 표가 있는 넷은 그 뒤에 지은 저장소에만 있다 — 없으면 건너뛴다(불기는 표가 없다).
      for (final cal in AuxCalendar.list.where((c) => !c.arithmetic)) {
        AuxCalendarTable? table;
        try {
          final answer = await engine!.call({'op': 'entity', 'uid': 'cal:${cal.id}'});
          table = AuxCalendarTable.parse(answer['data']);
        } catch (_) {
          table = null;
        }
        if (table == null && !const {'dangi', 'chinese', 'islamic', 'umalqura', 'persian'}.contains(cal.id)) continue;
        expect(table, isNotNull, reason: '${cal.name} 표를 받지 못했다');
        AuxCalendarTable? cals(String id) => id == cal.id ? table : null;
        final first = table!.monthAt(0), last = table.monthAt(table.count - 1);

        // 마지막 해의 12월 — 표는 그 앞에서 끝나므로 표 밖이다.
        expect(last.month, lessThan(12), reason: '${cal.name}: 마지막 해가 반 토막이어야 이 검사가 뜻이 있다');
        expect(table.coversDate(last.year, 12), isFalse, reason: '${cal.name} ${last.year}년 12월');
        final tail = '${table.prefix}${last.year}-12-01';
        final t = readAt(tail, cals: cals);
        expect(t, isNotNull, reason: '$tail — 표 밖이라고 못 읽은 글로 만들면 검색이 낱말로 떨어져 조용히 빈다');
        expect(t!.exact, isFalse, reason: '$tail — 표가 안 닿으니 적힌 수를 서력으로 읽는다');
        expect(t.cal, cal.id);
        expect(t.t, closeTo(parseAt('${last.year}-12-01')!, 1e-12));

        // 첫 해의 1월도 마찬가지다(이슬람력 · 페르시아력의 첫 해는 기원전이라 기원 규칙에 먼저 걸린다).
        if (cal.lunar) {
          expect(table.coversDate(first.year, 1), isFalse, reason: '${cal.name} ${first.year}년 1월');
          final head = '${table.prefix}${first.year < 0 ? '기원전 ${-first.year}' : '${first.year}'}-01-01';
          final h = readAt(head, cals: cals);
          expect(h, isNotNull, reason: '$head — 첫 달보다 앞이라고 못 읽은 글로 만들지 않는다');
          expect(h!.exact, isFalse, reason: head);
        }

        // 표가 닿는 달은 그대로 셈한다 — 되짚기가 살아 있는지 같은 자리에서 함께 본다.
        final inside = '${table.prefix}${last.year}-${last.leap ? '윤' : ''}${last.month}-01';
        final p = readAt(inside, cals: cals);
        expect(p, isNotNull, reason: inside);
        expect((p!.exact, p.jdn), (true, last.startJdn), reason: inside);
      }
    });
  });
}
