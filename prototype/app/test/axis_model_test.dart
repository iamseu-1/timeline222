import 'package:archive_prototype/scene/aux_calendar.dart';
import 'package:archive_prototype/scene/axis_model.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aux_calendar_test.dart' show lunarSlice;

// 날짜 칸의 줄 구성(지금 연표의 _buildAxis). 리메이크 2부(목업 서고 dateHeader)부터 연도 줄 24 · 시대 줄은 위 3 + 단마다 17이고,
// 처음에는 연도 · 시대만 보인다(간지 · 연호 · 도읍은 끔 — 보기 메뉴에서 켬). 그 밖의 줄은 기준 덤프(results/dom/한-나라의-100년.json)의 값 그대로:
// 간지 20 · **보조 달력 1(접힘)** · 연호 묶음 22 · 도읍 묶음 22.

Map<String, dynamic> _row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

/// [kind, track, lane, start, end, name, color, style, strip, seq]
List<Object> cell(int kind, int track, int lane, double startYear, double endYear, String name, {int color = 0xa0bcc5, int style = 0, int strip = 0, int seq = 0}) =>
    [kind, track, lane, minuteOfYear(startYear).round(), minuteOfYear(endYear).round(), name, color, style, strip, seq];

SceneLayout layoutOf(List<List<Object>> axis, {int tracks = 2}) => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': 0},
  ],
  'tracks': [
    for (int i = 0; i < tracks; i++) {'id': i + 1, 'pack': 1, 'ord': i, 'name': '${i + 1}번 갈래', 'color': 0xa0bcc5 + i, 'rows': [_row(i)]},
  ],
  'epochs': const [],
  'axis': axis,
});

void main() {
  test('줄 구성과 자리 — 연도 24 · 공통 시대 20 · 간지 20 · 나라별 시대 20 · 묶음 22씩', () {
    final model = AxisModel(layoutOf([
      cell(1, 0, 0, 100, 200, '첫 시대'),
      cell(1, 1, 0, 100, 200, '1번 갈래의 시대'),
      cell(1, 2, 0, 100, 200, '2번 갈래의 시대'),
      cell(2, 1, 0, 100, 150, '첫 연호', strip: 1),
      cell(3, 1, 0, 100, 150, '첫 도읍', strip: 2),
    ]));
    // 처음에는 연도 · 시대(와 접힌 보조 달력)뿐이다(리메이크 2부 — 목업 날짜 칸).
    expect(model.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.epoch, AxisRowKind.cal, AxisRowKind.epoch, AxisRowKind.epoch]);
    expect(model.rows.map((r) => r.top).toList(), [1, 25, 45, 46, 66]);
    expect(model.height, 87, reason: '맨 위 1px + 연도 24 + 시대 20 × 3 + 보조 달력 1 + 맨 아래 1px');
    // 간지 · 연호 · 도읍을 켜면 예전 차례 그대로 끼어든다.
    model.setShown(ganji: true, eras: true, capitals: true);
    expect(model.rows.map((r) => r.kind).toList(), [
      AxisRowKind.years, AxisRowKind.epoch, AxisRowKind.ganji, AxisRowKind.cal, AxisRowKind.epoch, AxisRowKind.epoch, AxisRowKind.group, AxisRowKind.group,
    ]);
    expect(model.rows.map((r) => r.top).toList(), [1, 25, 45, 65, 66, 86, 106, 128]);
    expect(model.rows.map((r) => r.height).toList(), [24, 20, 20, 1, 20, 20, 22, 22]);
    expect(model.height, 151, reason: '맨 위 1px + 줄 149(보조 달력 1 포함) + 맨 아래 1px');
    // 시대 줄 = 위 3(구분선 1 + 2) + 단마다 17(이름 종이 15 + 틈 2).
    expect(AxisModel.epochPad + AxisModel.epochHeight, 20);
    // 첫 줄만 위 구분선이 없고, 나머지 줄의 알맹이는 1px 아래에서 시작한다.
    expect(model.rows.first.border, isFalse);
    expect(model.rows[1].contentTop, 26);
    expect(model.rows[1].contentHeight, 19);
    // 접힌 보조 달력 줄은 구분선의 자리(1px)만 차지하고 알맹이가 없다.
    expect(model.rows[3].contentHeight, 0);
    expect(model.rows.map((r) => r.corner).toList(), ['', '시대', '간지', '음력', '1번 갈래 시대', '2번 갈래 시대', '연호', '도읍']);
    expect(model.rows[6].mark, '1개 나라');
    expect(model.rows[6].arrow, AxisArrow.right);
  });

  test('보조 달력 줄: 접히면 1px · 펼치면 20px이고 아래 줄이 그만큼 밀린다', () {
    final model = AxisModel(layoutOf([cell(1, 0, 0, 100, 200, '첫 시대')]));
    final closed = model.height;
    final cal = model.rows.firstWhere((r) => r.kind == AxisRowKind.cal);
    expect(cal.height, 1);
    expect(model.setCalOpen(true), isTrue);
    expect(model.rows.firstWhere((r) => r.kind == AxisRowKind.cal).height, 20);
    expect(model.height, closed + 19);
    expect(model.setCalOpen(true), isFalse, reason: '같은 값이면 다시 쌓지 않는다');
    // 보조 달력을 끄면 줄 자체가 사라져 1px이 더 줄어든다.
    model.setCalOpen(false);
    expect(model.setAltCal(''), isTrue);
    expect(model.rows.map((r) => r.kind), isNot(contains(AxisRowKind.cal)));
    expect(model.height, closed - 1);
  });

  test('월흔해 견본의 날짜 칸 — 처음 287px · 간지 · 연호 · 도읍을 켜면 351px(나라 12 · 나라마다 시대 · 연호 · 도읍 · 접힌 보조 달력 1px)', () {
    final model = AxisModel(layoutOf([
      cell(1, 0, 0, 100, 200, '공통 시대'),
      for (int t = 1; t <= 12; t++) ...[
        cell(1, t, 0, 100, 200, '$t번 시대'),
        cell(2, t, 0, 100, 150, '$t번 연호', strip: t),
        cell(3, t, 0, 100, 150, '$t번 도읍', strip: 100 + t),
      ],
    ], tracks: 12));
    // 처음(연도 · 시대): 1 + 24 + 공통 시대 20 + 보조 달력 1 + 나라 시대 20 × 12 + 1.
    expect(model.height, 287);
    expect(model.rows.length, 1 + 1 + 1 + 12);
    expect(model.rows.firstWhere((r) => r.kind == AxisRowKind.cal).top, 45);
    expect(model.rows[3].top, 46, reason: '보조 달력 1px 바로 아래가 첫 나라 시대 줄');
    // 간지 · 연호 · 도읍을 켜면 간지 20 · 묶음 22 × 2가 더해진다.
    model.setShown(ganji: true, eras: true, capitals: true);
    expect(model.height, 287 + 20 + 2 * 22);
    expect(model.rows.length, 1 + 1 + 1 + 1 + 12 + 2);
    expect(model.rows.last.mark, '12개 나라');
    final cal = model.rows.firstWhere((r) => r.kind == AxisRowKind.cal);
    expect(cal.top, 65);
    expect(model.rows[4].top, 66);
  });

  test('한 줄에 겹치는 시대 구분은 단을 나눠 줄이 높아진다', () {
    final model = AxisModel(layoutOf([
      cell(1, 0, 0, 100, 200, '앞 시대'),
      cell(1, 0, 1, 150, 260, '겹치는 시대'),
    ]));
    final epoch = model.rows[1];
    expect(epoch.lanes, 2);
    expect(epoch.height, 3 + 2 * 17);
    expect(model.rows[2].kind, AxisRowKind.cal);
    expect(model.rows[2].top, 1 + 24 + 37, reason: '아래 줄(보조 달력)이 두 단만큼 밀린다');
  });

  test('이설이 있는 칸은 style 32로 온다(계약 6-3)', () {
    final model = AxisModel(layoutOf([
      cell(2, 1, 0, 100, 150, '이설 연호', strip: 1, style: AxisModel.styleVariant),
    ]))..setShown(eras: true); // 연호 줄은 처음에 꺼져 있다(리메이크 2부)
    model.toggleGroup('eras');
    final era = model.rows.firstWhere((r) => r.kind == AxisRowKind.era);
    expect(era.data!.cells.single.style & AxisModel.styleVariant, AxisModel.styleVariant);
  });

  test('묶음을 열면 나라별 줄이 생기고 날짜 칸이 높아진다', () {
    final model = AxisModel(layoutOf([
      cell(2, 1, 0, 100, 150, '가 연호', strip: 1),
      cell(2, 1, 1, 120, 170, '겹치는 연호', strip: 2),
      cell(2, 2, 0, 100, 150, '나 연호', strip: 3),
    ]))..setShown(eras: true);
    final closed = model.height;
    expect(model.rows.map((r) => r.kind), isNot(contains(AxisRowKind.era)));
    model.toggleGroup('eras');
    final era = model.rows.where((r) => r.kind == AxisRowKind.era).toList();
    expect(era.length, 2);
    expect(era[0].lanes, 2, reason: '겹치는 연호는 두 갈래');
    expect(era[0].height, 44);
    expect(era[1].height, 22);
    expect(model.height, closed + 66);
    // 갈래가 둘인 나라는 한 줄로 접을 수 있다.
    model.toggleEraFold(1);
    expect(model.rows.firstWhere((r) => r.kind == AxisRowKind.era).height, 22);
    expect(model.rows.firstWhere((r) => r.kind == AxisRowKind.era).mark, '2갈래');
  });

  test('도읍 묶음의 배도 갈래는 나라마다 따로 연다', () {
    final model = AxisModel(layoutOf([
      cell(3, 1, 0, 100, 150, '도읍', strip: 1),
      cell(4, 1, 0, 100, 140, '두 배도', strip: 2),
      cell(4, 1, 1, 120, 160, '겹치는 배도', strip: 3),
    ]))..setShown(capitals: true);
    model.toggleGroup('capitals');
    final cap = model.rows.firstWhere((r) => r.kind == AxisRowKind.cap);
    expect(cap.height, 22);
    expect(cap.mark, '배도 2');
    model.toggleCapSec(1);
    final open = model.rows.firstWhere((r) => r.kind == AxisRowKind.cap);
    expect(open.height, 22 + 2 * 16 + 2);
    expect(open.mark, '배도');
    expect(open.arrow, AxisArrow.down);
  });

  test('접힌 묶음의 가는 막대: 같은 무리(strip)는 한 구간으로, 겹치는 구간은 합친다', () {
    final model = AxisModel(layoutOf([
      cell(2, 1, 0, 100, 150, '가', strip: 1),
      cell(2, 1, 0, 150, 200, '나', strip: 1),
      cell(2, 1, 1, 180, 260, '다', strip: 2),
      cell(2, 1, 0, 400, 450, '라', strip: 3),
    ]))..setShown(eras: true);
    final spans = model.rows.last.members.single.spans;
    expect(spans.length, 2);
    expect(spans[0].$1, minuteOfYear(100));
    expect(spans[0].$2, minuteOfYear(260), reason: '100~200과 180~260이 겹쳐 하나로');
    expect(spans[1].$1, minuteOfYear(400));
  });

  test('누른 자리 판정: 묶음 단추 · 칸', () {
    final model = AxisModel(layoutOf([
      cell(1, 0, 0, 100, 200, '첫 시대'),
      cell(2, 1, 0, 100, 150, '첫 연호', strip: 1),
    ]))..setShown(eras: true);
    const left = 240.0;
    double minuteAt(double x) => minuteOfYear(100 + (x - left) / 10); // 1년 = 10px
    // 공통 시대 구분 줄(25~45)의 칸
    final onEpoch = model.hitTest(left + 50, 40, left, minuteAt);
    expect(onEpoch.kind, AxisHitKind.epochCell);
    expect(onEpoch.cell!.name, '첫 시대');
    // 연호 묶음 줄의 모서리 단추와, 접혀 있을 때는 줄 어디를 눌러도 펼친다.
    final group = model.rows.firstWhere((r) => r.kind == AxisRowKind.group);
    expect(model.hitTest(30, group.top + 10, left, minuteAt).kind, AxisHitKind.groupToggle);
    expect(model.hitTest(left + 200, group.top + 10, left, minuteAt).key, 'eras');
    // 펼친 뒤에는 나라별 줄의 칸이 잡힌다.
    model.toggleGroup('eras');
    final era = model.rows.firstWhere((r) => r.kind == AxisRowKind.era);
    final hit = model.hitTest(left + 50, era.contentTop + 8, left, minuteAt);
    expect(hit.kind, AxisHitKind.eraCell);
    expect(hit.cell!.name, '첫 연호');
    expect(model.hitTest(left + 50, model.height + 5, left, minuteAt).kind, AxisHitKind.none);
  });

  // ── 필터 시트의 '날짜 칸' 표시 체크 넷 ──────────────────────────────────────────────
  // 지금 연표의 `_buildAxis`가 `show.ganji` · `show.eras` · `show.capitals` · `show.epochs`로 줄을 빼는 자리와 같다
  // (js/timeline.js 3800 · 3804 · 3814 · 3837 · 3853). 보조 달력 줄은 이 넷에 들지 않는다.

  AxisModel fullModel() => AxisModel(layoutOf([
    cell(1, 0, 0, 100, 200, '공통 시대'),
    cell(1, 1, 0, 100, 200, '1번 갈래의 시대'),
    cell(1, 2, 0, 100, 200, '2번 갈래의 시대'),
    cell(2, 1, 0, 100, 150, '첫 연호', strip: 1),
    cell(3, 1, 0, 100, 150, '첫 도읍', strip: 2),
  ]));

  test('표시 체크를 끄면 그 줄이 통째로 빠지고 날짜 칸이 그만큼 낮아진다', () {
    final model = fullModel();
    // 처음에는 시대만 켜져 있다(리메이크 2부 — 목업 날짜 칸은 연도 · 시대뿐).
    expect([model.showGanji, model.showEras, model.showCapitals, model.showEpochs], [false, false, false, true]);
    expect(model.height, 87);
    expect(model.setShown(ganji: true, eras: true, capitals: true), isTrue);
    final all = model.height; // 1 + 24 + 20 + 20 + 1(보조 달력) + 20 + 20 + 22 + 22 + 1
    expect(all, 151);
    expect(model.showGanji && model.showEras && model.showCapitals && model.showEpochs, isTrue);

    expect(model.setShown(ganji: false), isTrue);
    expect(model.rows.map((r) => r.kind), isNot(contains(AxisRowKind.ganji)));
    expect(model.height, all - AxisModel.ganjiHeight);
    expect(model.setShown(ganji: false), isFalse, reason: '같은 값이면 다시 쌓지 않는다');
    expect(model.rows.firstWhere((r) => r.kind == AxisRowKind.cal).top, 1 + 24 + 20, reason: '아래 줄이 20px 올라온다');
    model.setShown(ganji: true);
    expect(model.height, all);

    // 연호 · 도읍은 묶음 줄 22px씩.
    expect(model.setShown(eras: false), isTrue);
    expect(model.height, all - AxisModel.groupHeight);
    expect([for (final r in model.rows) if (r.kind == AxisRowKind.group) r.groupKey], ['capitals']);
    expect(model.setShown(capitals: false), isTrue);
    expect(model.height, all - 2 * AxisModel.groupHeight);
    expect(model.rows.map((r) => r.kind), isNot(contains(AxisRowKind.group)));

    // 시대 구분은 공통 줄과 나라별 줄을 함께 끈다(지금 연표도 한 체크로 둘 다 뺀다).
    expect(model.setShown(epochs: false), isTrue);
    expect(model.rows.map((r) => r.kind), isNot(contains(AxisRowKind.epoch)));
    expect(model.height, all - 2 * AxisModel.groupHeight - 3 * (AxisModel.epochPad + AxisModel.epochHeight));
    expect(model.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.ganji, AxisRowKind.cal]);
    // 넷을 다 끄면 연도 줄과 보조 달력 줄만 남는다.
    model.setShown(ganji: false);
    expect(model.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.cal]);
    expect(model.height, 1 + AxisModel.yearsHeight + AxisModel.calFoldedHeight + 1);
  });

  test('묶음을 끄면 펼쳐 둔 나라별 줄도 함께 빠지고, 다시 켜면 펼친 채로 돌아온다', () {
    final model = fullModel()..setShown(eras: true);
    model.toggleGroup('eras');
    expect(model.rows.where((r) => r.kind == AxisRowKind.era).length, 1);
    final open = model.height;
    model.setShown(eras: false);
    expect(model.rows.map((r) => r.kind), isNot(contains(AxisRowKind.era)));
    model.setShown(eras: true);
    expect(model.rows.where((r) => r.kind == AxisRowKind.era).length, 1, reason: '펼침(axisOpen)은 그대로 남아 있다');
    expect(model.height, open);
  });

  // ── 열어 둔 상태의 기억 ────────────────────────────────────────────────────────────

  test('상태를 적고 되돌린다 — 열어 둔 묶음 · 접은 연호 · 펼친 배도 · 보조 달력 · 표시 넷', () {
    final model = AxisModel(layoutOf([
      cell(2, 1, 0, 100, 150, '가 연호', strip: 1),
      cell(2, 1, 1, 120, 170, '겹치는 연호', strip: 2),
      cell(3, 1, 0, 100, 150, '가 도읍', strip: 3),
      cell(4, 1, 0, 100, 140, '가 배도', strip: 4),
    ]));
    expect(model.stateVersion, 0);
    model.toggleGroup('eras');
    model.toggleGroup('capitals');
    model.toggleEraFold(1);
    model.toggleCapSec(1);
    model.setShown(eras: true, capitals: true, epochs: false); // 간지는 처음부터 꺼져 있다
    model.setAltCal('');
    expect(model.stateVersion, 6, reason: '사람이 정한 것이 바뀔 때마다 하나씩 오른다');
    final saved = model.stateJson();
    expect(saved, {
      'axisOpen': ['capitals', 'eras'],
      'foldedEras': [1],
      'openCapSec': [1],
      'altCal': '',
      'show': {'ganji': false, 'eras': true, 'capitals': true, 'epochs': false},
    });

    // 새로 연 것처럼 기본값에서 시작해 되돌린다.
    final again = AxisModel(layoutOf([
      cell(2, 1, 0, 100, 150, '가 연호', strip: 1),
      cell(2, 1, 1, 120, 170, '겹치는 연호', strip: 2),
      cell(3, 1, 0, 100, 150, '가 도읍', strip: 3),
      cell(4, 1, 0, 100, 140, '가 배도', strip: 4),
    ]));
    expect(again.restoreState(saved), isTrue);
    expect(again.stateJson(), saved);
    expect(again.height, model.height);
    expect(again.rows.map((r) => r.kind).toList(), model.rows.map((r) => r.kind).toList());
    expect(again.restoreState(saved), isFalse, reason: '같은 값이면 다시 쌓지 않는다');
  });

  test('기억이 비었거나 꼴이 어긋나면 그 열쇠는 건드리지 않는다', () {
    final model = fullModel();
    expect(model.restoreState(const {}), isFalse);
    expect(model.restoreState(const {'axisOpen': '연호', 'foldedEras': 3, 'show': '켬'}), isFalse);
    // 뒤에 생긴 표시가 옛 기억에 없으면 기본값 그대로 둔다(리메이크 2부: 연호 · 도읍은 끔, 시대는 켬).
    expect(model.restoreState(const {'show': {'ganji': true}}), isTrue);
    expect(model.showGanji, isTrue);
    expect([model.showEras, model.showCapitals, model.showEpochs], [false, false, true]);
    // 모르는 달력 이름은 버린다.
    expect(model.restoreState(const {'altCal': '없는달력'}), isFalse);
    expect(model.altCal, AuxCalendar.defaultId);
    expect(model.shown('ganji'), isTrue);
    expect(model.shown('eras'), isFalse);
    expect(model.shown('없는열쇠'), isTrue);
  });

  // ── 도움말과 고르기 단추의 커서 범위 ────────────────────────────────────────────────

  test('묶음 단추 · 접기 단추의 도움말은 지금 연표의 title 그대로다', () {
    final model = AxisModel(layoutOf([
      cell(2, 1, 0, 100, 150, '가 연호', strip: 1),
      cell(2, 1, 1, 120, 170, '겹치는 연호', strip: 2),
      cell(2, 2, 0, 100, 150, '나 연호', strip: 3),
      cell(3, 1, 0, 100, 150, '가 도읍', strip: 4),
      cell(4, 1, 0, 100, 140, '가 배도', strip: 5),
      cell(3, 2, 0, 100, 150, '나 도읍', strip: 6),
    ]))..setShown(eras: true, capitals: true);
    const left = 240.0;
    double minuteAt(double x) => minuteOfYear(100 + (x - left) / 10);
    final group = model.rows.firstWhere((r) => r.kind == AxisRowKind.group);
    expect(model.hitTest(30, group.top + 10, left, minuteAt).tip, '연호 — 1번 갈래 · 2번 갈래 · 눌러서 나라별로 펼치기');
    model.toggleGroup('eras');
    model.toggleGroup('capitals');
    expect(model.hitTest(30, group.top + 10, left, minuteAt).tip, '연호 접기');
    final era = model.rows.firstWhere((r) => r.kind == AxisRowKind.era);
    expect(model.hitTest(30, era.top + 10, left, minuteAt).tip, '1번 갈래 연호 · 한 줄로 접기');
    model.toggleEraFold(1);
    expect(model.hitTest(30, model.rows.firstWhere((r) => r.kind == AxisRowKind.era).top + 10, left, minuteAt).tip, '1번 갈래 연호 · 2갈래로 펼치기');
    final cap = model.rows.firstWhere((r) => r.kind == AxisRowKind.cap);
    expect(model.hitTest(30, cap.top + 10, left, minuteAt).tip, '1번 갈래 도읍 · 배도(별도·5경·소경) 갈래 펼치기');

    // 갈래가 하나인 연호 줄 · 배도가 없는 도읍 줄의 모서리는 단추가 아니지만 도움말은 있다
    // (js/timeline.js 3929 · 3940의 `<div class="tl-corner" title="…">`) — 월흔해에서는 이쪽이 대부분이다.
    final era2 = model.rows.lastWhere((r) => r.kind == AxisRowKind.era);
    final plain = model.hitTest(30, era2.top + 10, left, minuteAt);
    expect(plain.kind, AxisHitKind.none, reason: '누를 것은 없고 도움말만 있는 모서리');
    expect(plain.track, 2);
    expect(plain.tip, '2번 갈래 연호');
    final cap2 = model.rows.lastWhere((r) => r.kind == AxisRowKind.cap);
    expect(model.hitTest(30, cap2.top + 10, left, minuteAt).tip, '2번 갈래 도읍');
  });

  test('보조 달력: 고르기 단추는 제 상자 안에서만 잡히고, 칸에는 도움말이 실린다', () {
    AuxCalendarStore.shared = AuxCalendarStore(null)..put(AuxCalendar.defaultId, lunarSlice());
    addTearDown(() => AuxCalendarStore.shared = null);
    final model = AxisModel(layoutOf([cell(1, 0, 0, 100, 400, '공통 시대')]))..setCalOpen(true);
    const left = 240.0;
    // 296~307년이 보이는 자리 — 1년 = 60px.
    double minuteAt(double x) => minuteOfYear(296 + (x - left) / 60);
    double xOf(double minute) => left + (yearAt(minute) - 296) * 60;
    final row = model.rows.firstWhere((r) => r.kind == AxisRowKind.cal);
    final y = row.contentTop + 8;

    // 아직 단추 자리를 재지 않았으면 모서리 칸 어디서나(그리기 전의 첫 장면).
    expect(model.hitTest(20, y, left, minuteAt).kind, AxisHitKind.calPick);
    model
      ..calPickL = 129
      ..calPickR = 229;
    expect(model.hitTest(20, y, left, minuteAt).kind, AxisHitKind.none, reason: '지금 연표의 <select>는 100px 상자 안에서만 커서를 받는다');
    final pick = model.hitTest(180, y, left, minuteAt);
    expect(pick.kind, AxisHitKind.calPick);
    expect(pick.tip, '보조 달력 — 바꾸거나 끌 수 있습니다');
    expect(pick.x, 129);
    expect(model.hitTest(230, y, left, minuteAt).kind, AxisHitKind.none);

    // 달 칸의 도움말 — 지금 연표의 `title="음력 경신년 1월 — 300년 2월 7일부터"`.
    final table = lunarSlice();
    final month = table.monthOfJdn(1830670)!;
    final at = minuteOfYear(tOfJdn(month.startJdn)) + 600; // 그 달 초하루의 낮
    final cellHit = model.hitTest(xOf(at), y, left, minuteAt, xOf: xOf);
    expect(cellHit.kind, AxisHitKind.none, reason: '누를 것은 없고 도움말만 있는 자리');
    expect(cellHit.tip, '음력 경신년 1월 — 300년 2월 7일부터');
    expect(cellHit.x, closeTo(xOf(minuteOfYear(tOfJdn(month.startJdn))), .001), reason: '도움말은 칸의 왼쪽 끝에 띄운다');

    // 날 눈금이면 그날의 글이다(지금 연표의 `음력 … = 서력 …`).
    model.calDay = true;
    final dayHit = model.hitTest(xOf(at), y, left, minuteAt, xOf: xOf);
    expect(dayHit.tip, '음력 300년 1월 1일 = 300년 2월 7일');

    // 표가 덮지 않는 때는 도움말도 없다(표는 296~307년만 안다).
    model.calDay = false;
    expect(model.hitTest(xOf(minuteOfYear(309)), y, left, minuteAt, xOf: xOf).tip, isEmpty);
    // 줄이 접혀 있으면(1px) 도움말을 만들지 않는다.
    model.setCalOpen(false);
    expect(model.hitTest(xOf(at), model.rows.firstWhere((r) => r.kind == AxisRowKind.cal).top, left, minuteAt, xOf: xOf).tip, isEmpty);
  });

  test('칸을 누르면 그 칸의 왼쪽 끝이 실려 온다(화면 왼쪽으로 잘렸으면 그림 영역의 왼쪽 끝)', () {
    final model = AxisModel(layoutOf([cell(1, 0, 0, 100, 200, '첫 시대')]));
    const left = 240.0;
    double minuteAt(double x) => minuteOfYear(150 + (x - left) / 10);
    double xOf(double minute) => left + (yearAt(minute) - 150) * 10;
    final hit = model.hitTest(left + 50, 40, left, minuteAt, xOf: xOf);
    expect(hit.kind, AxisHitKind.epochCell);
    expect(hit.x, left, reason: '100년에 시작한 칸은 화면 왼쪽으로 잘렸다');
    expect(model.hitTest(left + 50, 40, left, minuteAt).x, left + 50, reason: 'xOf를 주지 않으면 누른 자리 그대로');
  });
}
