import 'package:archive_prototype/scene/ruler.dart';
import 'package:flutter_test/flutter_test.dart';

const year = 525960.0; // 365.25일

double minuteOf(int astronomicalYear, [int month = 1, int day = 1]) => DateTime.utc(astronomicalYear, month, day).millisecondsSinceEpoch / 60000;

/// 그림 폭 1,700px에 [years]년이 보이는 보기의 눈금.
RulerModel ticksFor(Ruler ruler, double years, {double from = 1000}) {
  final lo = minuteOf(from.floor());
  return ruler.compute(lo, lo + years * year, 1700 / (years * year));
}

/// 화면에 그리는 눈금만(맨 앞의 것은 바탕 띠를 깔려고 보기 밖에서 하나 더 온다).
List<Tick> shown(RulerModel model) => [for (final t in model.ticks) if (t.shown) t];

void main() {
  test('눈금 사이가 96px 이상인 가장 촘촘한 간격을 고른다', () {
    expect(ticksFor(Ruler(), 5500, from: -1500).unit, '500년');
    expect(ticksFor(Ruler(), 100).unit, '10년');
    expect(ticksFor(Ruler(), 17).unit, '1년');
    expect(ticksFor(Ruler(), 3).unit, '3개월', reason: '한 달이 47px이라 58px에 못 미친다');
    expect(ticksFor(Ruler(), 2).unit, '1개월');
    expect(ticksFor(Ruler(), .2).unit, '2일', reason: '하루 23px → 이틀 47px(문턱 40px)');
    expect(ticksFor(Ruler(), .01).unit, '3시간', reason: '한 시간 19px → 세 시간 58px(문턱 46px)');
  });

  test('연도 눈금은 그 해의 1월 1일에 서고 이름은 해 숫자다', () {
    final model = ticksFor(Ruler(), 100, from: 1200);
    expect(shown(model).map((t) => t.label).take(4).toList(), ['1200', '1210', '1220', '1230']);
    expect(shown(model)[1].minute, minuteOf(1210));
    expect(shown(model).length, 11);
    // 보기 왼쪽 밖의 눈금 하나는 바탕 띠만 깐다(지금 연표와 같이 한 칸 걸러 깐다).
    expect(model.ticks.first.shown, isFalse);
    expect(model.ticks.first.label, '1190');
    expect(model.ticks.where((t) => t.band).map((t) => t.label).take(3).toList(), ['1200', '1220', '1240']);
  });

  test('기원전 1년 다음은 기원후 1년이고, 0년 자리는 간격이 1년일 때만 건너뛴다', () {
    final ruler = Ruler();
    final lo = minuteOf(-4); // 천문학적 −4년 = 기원전 5년
    final model = ruler.compute(lo, lo + 15 * year, 1700 / (15 * year)); // 해마다 113px
    expect(model.unit, '1년');
    expect(shown(model).map((t) => t.label).toList(), containsAllInOrder(['기원전 3', '기원전 2', '기원전 1', '1', '2']));
    expect(shown(model).map((t) => t.label), isNot(contains('0')));
    // 간격이 1년보다 크면 지금 연표처럼 0년 자리에도 눈금이 선다(0년 자리의 선은 파선).
    final wide = ruler.compute(minuteOf(-250), minuteOf(260), 1700 / (510 * year));
    expect(shown(wide).map((t) => t.label).toList(), containsAllInOrder(['기원전 200', '기원전 100', '0', '100', '200']));
    expect(wide.ticks.where((t) => t.zero).length, 1);
  });

  test('달 · 날 · 시간 눈금의 이름과 윗단위 표시', () {
    final months = Ruler().compute(minuteOf(1203, 11, 1), minuteOf(1205, 3, 15), 1700 / (500 * 1440));
    expect(months.unit, '1개월');
    expect(shown(months).map((t) => t.label).take(5).toList(), ['11월', '12월', '1204년', '2월', '3월']);
    expect(shown(months)[2].minute, minuteOf(1204));
    expect(shown(months)[2].major, isTrue, reason: '해가 바뀌는 눈금은 짙게');
    final days = Ruler().compute(minuteOf(1203, 2, 15), minuteOf(1203, 3, 17), 1700 / (30 * 1440));
    expect(days.unit, '1일');
    expect(shown(days).map((t) => t.label).toList(), containsAllInOrder(['27일', '28일', '3월', '2일', '3일']), reason: '평년의 2월');
  });

  test('며칠마다의 눈금은 정해진 날에만 선다(5일은 1 · 6 · 11 · 16 · 21 · 26일)', () {
    final lo = minuteOf(1203, 1, 1);
    final five = Ruler().compute(lo, lo + 113 * 1440, 1700 / (113 * 1440)); // 하루 15px — 이틀은 문턱 40px에 못 미친다
    expect(five.unit, '5일');
    expect(shown(five).map((t) => t.label).take(7).toList(), ['1203년 1월', '6일', '11일', '16일', '21일', '26일', '2월']);
  });

  test('경계에서 간격이 흔들리지 않는다', () {
    final ruler = Ruler();
    // 10년 간격이 97px → 95px → 89px로 좁아져도 그대로이고, 88px 아래에서야 20년으로 성겨진다.
    double ppmFor(double px) => px / (10 * year);
    expect(ruler.compute(0, 100 * year, ppmFor(97)).unit, '10년');
    expect(ruler.compute(0, 100 * year, ppmFor(95)).unit, '10년');
    expect(ruler.compute(0, 100 * year, ppmFor(89)).unit, '10년');
    expect(ruler.compute(0, 100 * year, ppmFor(87)).unit, '20년');
    // 다시 넓어질 때는 10년 간격이 96px이 되어야 촘촘해진다.
    expect(ruler.compute(0, 100 * year, ppmFor(93)).unit, '20년');
    expect(ruler.compute(0, 100 * year, ppmFor(96.5)).unit, '10년');
  });

  test('간지는 60갑자 계산이고 26px 규칙으로 촘촘해진다', () {
    expect(ganjiOf(1984), '갑자');
    expect(ganjiOf(2024), '갑진');
    expect(ganjiOf(1), '신유');
    expect(ganjiOf(0), '경신', reason: '천문학적 0년 = 기원전 1년');
    expect(ganjiOf(-56), '갑자');
    final ruler = Ruler();
    final dense = ruler.compute(minuteOf(1200), minuteOf(1230), 1700 / (30 * year));
    expect(dense.ganjiMode, GanjiMode.cells);
    expect(dense.ganji.map((g) => g.name).take(3).toList(), ['경신', '신유', '임술']);
    expect(dense.ganji.first.end, minuteOf(1201), reason: '해마다 이어진 칸');
    final sparse = ruler.compute(minuteOf(1200), minuteOf(1800), 1700 / (600 * year));
    expect(sparse.ganjiMode, GanjiMode.ticks);
    expect(sparse.ganjiStep, 10, reason: '해마다 2.8px → 10년(28px)');
    final none = ruler.compute(minuteOf(-1500), minuteOf(2000), 1700 / (3500 * year));
    expect(none.ganjiMode, GanjiMode.hint);
    expect(none.ganji, isEmpty, reason: '30년도 26px에 못 미치고 갑자도 56px에 못 미친다');
  });

  test('몇 해마다의 간지 눈금은 간격이 64px을 넘으면 연도를 곁들인다', () {
    // 해마다 12.88px — 두 해는 26px에 못 미쳐 5년 간격이고, 그 간격이 64.4px이라 연도가 붙는다.
    final wide = Ruler().compute(minuteOf(1200), minuteOf(1332), 1700 / (132 * year));
    expect(wide.ganjiStep, 5);
    expect(wide.ganji.first.year, isNotEmpty);
    final narrow = Ruler().compute(minuteOf(1200), minuteOf(1800), 1700 / (600 * year));
    expect(narrow.ganjiStep, 10);
    expect(narrow.ganji.first.year, isEmpty, reason: '10년이 28px이라 연도는 붙지 않는다');
  });

  test('일진: 하루가 26px을 넘으면 날마다의 간지가 칸으로 나온다', () {
    // 하루가 26px을 넘으려면 보기 폭이 1,700 / 26 / 365.25 = 0.179해보다 좁아야 한다.
    final days = ticksFor(Ruler(), .1, from: 1200);
    expect(days.ganjiMode, GanjiMode.days);
    expect(days.ganjiStep, 0);
    expect(days.ganji.length, greaterThan(30));
    // 60일마다 갑자일이 돌아온다(js/calendar.js의 `dayGanjiIndex` — 1949-10-01이 갑자일).
    final indices = days.ganji.map((g) => g.index).toList();
    for (int i = 1; i < indices.length; i++) {
      expect(indices[i], (indices[i - 1] + 1) % 60);
    }
    // 칸은 날마다 이어지고 한 칸 걸러 짙다.
    for (int i = 1; i < days.ganji.length; i++) {
      expect(days.ganji[i].start, closeTo(days.ganji[i - 1].end, 1));
      expect(days.ganji[i].alt, isNot(days.ganji[i - 1].alt));
    }
    // 문턱이 조금만 낮아도 해마다의 칸으로 돌아간다.
    final years = ticksFor(Ruler(), .5, from: 1200);
    expect(years.ganjiMode, GanjiMode.cells);
  });

  test('보조 달력 줄은 한 달이 18px을 넘을 때 열리고, 모서리에 지금 자리가 굵게 붙는다', () {
    final ruler = Ruler();
    expect(ticksFor(ruler, 100).calOpen, isFalse);
    expect(ticksFor(ruler, 100).context, '', reason: '해 눈금에서는 굵은 자리 글이 없다');
    // 한 달이 18px을 넘으려면 한 해가 216px — 1,700px에 7.87해보다 좁아야 한다.
    final open = ticksFor(ruler, 5, from: 1200);
    expect(open.sub, isTrue);
    expect(open.calOpen, isTrue);
    expect(open.context, '1200년', reason: '달 눈금에서는 그 해');
    final day = ticksFor(Ruler(), .2, from: 1200);
    expect(day.context, '1200년 1월');
    final hour = ticksFor(Ruler(), .01, from: 1200);
    expect(hour.context, '1200년 1월 1일');
  });

  test('보기의 폭은 해 좌표의 차(0년 자리를 한 해로 센다)', () {
    expect(yearsBetween(-1500, 1500), 3000);
    expect(yearAt(minuteOfYear(-1500)), closeTo(-1500, 1e-6));
    expect(yearAt(minuteOfYear(1500)), closeTo(1500, 1e-6));
    expect(spanText(3000), '3,000년');
    expect(spanText(100), '100년');
    expect(spanText(165), '165년');
    expect(spanText(3.25), '3.3년');
    expect(spanText(.5), '약 6개월');
  });
}
