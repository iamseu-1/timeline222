import 'package:archive_prototype/scene/aux_calendar.dart';
import 'package:archive_prototype/scene/axis_model.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
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

/// [sphereLines]는 layout 답의 문화권 단위 줄(리메이크 4단계 과제 3), [spheres]는 문화권 목록의 id.
/// 문화권이 있으면 i번 트랙을 [spheres]의 i번(모자라면 마지막) 문화권에 두고 줄 꼴(kind)을 실어 머리 단을 세운다 —
/// 그리고 [folded]만 접는다(기본은 모두 펼침 · 처음 접힘을 보려면 [initialFold]). 문화권이 없으면 트랙은 문화권 밖 · 옛 줄 그대로.
/// [oldRows]면 문화권이 있어도 줄 꼴(kind)을 싣지 않는다 — 머리 단을 세우지 않는 옛 배치.
SceneLayout layoutOf(List<List<Object>> axis,
    {int tracks = 2,
    List<Map<String, Object>> sphereLines = const [],
    List<String> spheres = const [],
    Set<String> folded = const {},
    bool initialFold = false,
    bool oldRows = false}) {
  final layout = SceneLayout.fromJson({
    'packs': [
      {'id': 1, 'name': '별여울 기록집', 'events': 0},
    ],
    'tracks': [
      for (int i = 0; i < tracks; i++)
        {
          'id': i + 1, 'pack': 1, 'ord': i, 'name': '${i + 1}번 갈래', 'color': 0xa0bcc5 + i,
          'rows': [if (spheres.isEmpty || oldRows) _row(i) else {..._row(i), 'kind': 0}],
          if (spheres.isNotEmpty) 'sphere': spheres[i < spheres.length ? i : spheres.length - 1],
        },
    ],
    'epochs': const [],
    'axis': axis,
    'spheres': [for (final id in spheres) {'id': id, 'name': '$id 권'}],
    'sphereLines': sphereLines,
  });
  if (!initialFold) layout.setViewState(layout.viewState.copyWith(foldedSpheres: folded));
  return layout;
}

/// 문화권 시대(sphereLines kind 2) 하나 — [from] ~ [to]해.
Map<String, Object> sphereEpoch(String sphere, double from, double to, String name) =>
    {'kind': 2, 'sphere': sphere, 'start': minuteOfYear(from).round(), 'end': minuteOfYear(to).round(), 'name': name, 'uid': 'ep-$name', 'color': 0xc8b193};

/// 문화권 주기 줄(sphereLines kind 3) 하나 — [data]는 이름 돌림 {names, start, label} 또는 연호 눈금 {era, from, step, label}.
Map<String, Object> sphereCycle(String sphere, Map<String, Object> data) => {'kind': 3, 'sphere': sphere, 'start': 0, 'end': 0, 'name': '', 'data': data};

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

  // ── 문화권 시대(리메이크 4단계 과제 3 걸음 3 · 계획 정한 것 #4) ──────────────────────────
  // 3단계는 문화권 시대(sphereLines kind 2)를 날짜 칸 공통 줄에도 실었다(계약 1-1). 문화권 머리 단 밑 시대 줄에 그리므로 공통 줄에서는 뺀다 —
  // 날짜 칸의 칸에는 uid가 없어 (시작 · 끝 · 이름)으로 가린다. 빠졌으면 남은 칸의 단을 지금 연표의 packLanes로 다시 나눈다.
  group('문화권 시대는 공통 줄에 그리지 않는다', () {
    /// 가상 팩 f4-sphere의 공통 줄 꼴(엔진이 실은 단 그대로): 등불 왕국(0단) · 안개(1단) · 칸국기(2단) · 아홉 불씨(0단) · 제국기(2단) — 안개 시대만 문화권 밖.
    /// 1번 갈래에는 제 시대 줄(하연 줄 시대)이 있다.
    final axis = [
      cell(1, 0, 0, 1, 788, '등불 왕국 시대', seq: 0),
      cell(1, 0, 1, 1, 1031, '안개 시대', seq: 1),
      cell(1, 0, 2, 300, 788, '칸국기', seq: 2),
      cell(1, 1, 0, 455, 900, '하연 줄 시대'),
      cell(1, 0, 0, 788, 1031, '아홉 불씨 시대', seq: 3),
      cell(1, 0, 2, 788, 1031, '제국기', seq: 4),
    ];
    final lines = [
      sphereEpoch('ember', 1, 788, '등불 왕국 시대'),
      sphereEpoch('frost', 300, 788, '칸국기'),
      sphereEpoch('ember', 788, 1031, '아홉 불씨 시대'),
      sphereEpoch('frost', 788, 1031, '제국기'),
    ];

    test('문화권 시대와 (시작 · 끝 · 이름)이 같은 칸이 빠지고, 남은 칸은 빈 단 없이 다시 나뉘어 날짜 칸이 낮아진다', () {
      final before = AxisModel(layoutOf(axis));
      final after = AxisModel(layoutOf(axis, sphereLines: lines, spheres: const ['ember', 'frost']));
      expect(before.rows[1].epochs.map((e) => e.name), ['등불 왕국 시대', '안개 시대', '칸국기', '아홉 불씨 시대', '제국기']);
      expect(before.rows[1].lanes, 3);
      // 안개 시대 하나 — 엔진이 실은 1단이 아니라 0단(빠진 칸의 빈 단이 남지 않음).
      expect(after.rows[1].epochs.map((e) => (e.name, e.lane)), [('안개 시대', 0)]);
      expect(after.rows[1].lanes, 1);
      expect(after.rows[1].height, 3 + 17);
      expect(after.height, before.height - 2 * 17, reason: '공통 줄이 세 단에서 한 단으로');
      // 나라별 시대 줄은 그대로.
      expect(after.rows.last.epochs.map((e) => e.name), ['하연 줄 시대']);
      // 빠진 칸은 누를 수 없고 남은 칸은 0단에서 잡힌다(줄 25 ~ 45 · 단 하나).
      const left = 240.0;
      double minuteAt(double x) => minuteOfYear(1 + (x - left)); // 1년 = 1px
      expect(after.hitTest(left + 100, 40, left, minuteAt).cell?.name, '안개 시대');
      expect(before.hitTest(left + 100, 40, left, minuteAt).cell?.name, '등불 왕국 시대', reason: '4단계 전에는 0단이 등불 왕국 시대');
    });

    test('문화권 시대가 없는 저장소 · 이름이나 때가 다른 칸 · 목록 밖 문화권의 시대는 그대로(받은 목록 그대로 — 단도 엔진 값)', () {
      final bare = AxisModel(layoutOf(axis));
      final common = bare.rows[1].epochs;
      expect(identical(AxisModel.withoutSphereEpochs(common, const {}), common), isTrue);
      final other = AxisModel(layoutOf(axis, sphereLines: [sphereEpoch('ember', 1, 787, '등불 왕국 시대'), sphereEpoch('ember', 1, 788, '등불 시대')], spheres: const ['ember']));
      expect(other.rows[1].epochs.map((e) => (e.name, e.lane)), [for (final e in common) (e.name, e.lane)]);
      // 문화권 목록에 없는 문화권(머리 단이 없어 그 밑 시대 줄도 없음)의 시대는 공통 줄에 남는다.
      final unknown = AxisModel(layoutOf(axis, sphereLines: lines, spheres: const ['ember']));
      expect(unknown.rows[1].epochs.map((e) => (e.name, e.lane)), [('안개 시대', 0), ('칸국기', 1), ('제국기', 1)]);
      expect(bare.height, AxisModel(layoutOf(axis, sphereLines: const [], spheres: const ['ember', 'frost'])).height);
    });

    // 검토 지적(2026-10-25): 머리 단 밑 시대 줄은 펼친 문화권에만, 그 머리 단이 설 때만 그린다. 그러니 접힌 문화권 · 트랙이 하나도 서지 않은 문화권의
    // 시대까지 공통 줄에서 빼면 화면 어디에도 없다 — 앱은 기억이 없으면 기본 문화권 하나만 편다(처음 접힘). 그런 문화권의 시대는 공통 줄에 남는다.
    test('접힌 문화권 · 트랙이 모두 꺼진 문화권의 시대는 공통 줄에 남는다(처음 접힘 포함) · 접고 펴면 날짜 칸이 따라 다시 진다', () {
      const kept = [('안개 시대', 0), ('칸국기', 1), ('제국기', 1)];
      List<(String, int)> common(AxisModel m) => [for (final e in m.rows[1].epochs) (e.name, e.lane)];
      // 설령(frost)만 접힘: 분지(ember)의 시대만 빠진다 — 문화권 목록에 없는 문화권과 같은 꼴.
      final half = layoutOf(axis, sphereLines: lines, spheres: const ['ember', 'frost'], folded: const {'frost'});
      expect(common(AxisModel(half)), kept);
      expect(half.sphereEpochUids, {'ep-등불 왕국 시대', 'ep-아홉 불씨 시대'}, reason: '누름의 이름 찾기도 그리는 것만 건너뜀');
      // 처음 접힘(기억 없음 — 자료의 default, 없으면 첫 문화권 하나만 폄): 같은 모습.
      final first = layoutOf(axis, sphereLines: lines, spheres: const ['ember', 'frost'], initialFold: true);
      expect(first.isSphereFolded('frost'), isTrue);
      expect(common(AxisModel(first)), kept);
      // 접고 펴면 쌓기 판이 올라 날짜 칸이 다시 진다(sync).
      final model = AxisModel(half);
      half.foldSphere('frost', false);
      expect(model.sync(), isTrue);
      expect(common(model), [('안개 시대', 0)]);
      half.foldSphere('ember', true);
      expect(model.sync(), isTrue);
      expect(common(model), [('등불 왕국 시대', 0), ('안개 시대', 1), ('아홉 불씨 시대', 0)]);
      // 설령의 트랙(2번)을 모두 끄면 머리 단이 서지 않는다 — 그 시대도 공통 줄에.
      final off = layoutOf(axis, sphereLines: lines, spheres: const ['ember', 'frost']);
      off.setViewState(off.viewState.copyWith(offTracks: const {2}));
      expect(common(AxisModel(off)), kept);
      // 모두 접으면 4단계 전 공통 줄 그대로(엔진이 실은 단 · 받은 목록 그대로).
      final all = layoutOf(axis, sphereLines: lines, spheres: const ['ember', 'frost'], folded: const {'ember', 'frost'});
      expect(common(AxisModel(all)), common(AxisModel(layoutOf(axis))));
      expect(all.sphereEpochKeys, isEmpty);
    });

    test('공통 줄이 다 빠지면 줄이 없다 — 첫 나라별 시대 줄이 맨 처음 시대 줄(▾) · 나라별 줄도 없으면 시대 줄이 하나도 없다', () {
      final model = AxisModel(layoutOf([cell(1, 0, 0, 100, 200, '첫 시대'), cell(1, 1, 0, 100, 200, '1번 갈래의 시대')],
          sphereLines: [sphereEpoch('ember', 100, 200, '첫 시대')], spheres: const ['ember']));
      expect(model.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.cal, AxisRowKind.epoch]);
      expect(model.rows.last.corner, '1번 갈래 시대');
      expect(model.rows.last.arrow, AxisArrow.down, reason: '맨 처음 시대 줄의 ▾');
      expect(model.height, 1 + 24 + 1 + 20 + 1);
      // 접으면 공통 줄이 없을 때의 자리(나라별 자리)에 접힌 줄 하나 — 1줄.
      model.toggleGroup(AxisModel.epochFold);
      expect(model.rows.last.kind, AxisRowKind.group);
      expect(model.rows.last.mark, '1줄');
      final none = AxisModel(layoutOf([cell(1, 0, 0, 100, 200, '첫 시대')], sphereLines: [sphereEpoch('ember', 100, 200, '첫 시대')], spheres: const ['ember']));
      expect(none.rows.map((r) => r.kind).toList(), [AxisRowKind.years, AxisRowKind.cal]);
    });

    test('다시 나누는 단은 지금 연표의 packLanes — 시작 차례(같은 시작이면 원래 차례 seq) · 끝 ≤ 시작인 첫 단', () {
      AxisCell at(int lane, double from, double to, String name, int seq) => AxisCell(1, 0, lane, minuteOfYear(from).round(), minuteOfYear(to).round(), name, 0, 0, 0, seq);
      final cells = [at(0, 100, 200, '가', 0), at(1, 100, 300, '나', 2), at(2, 100, 150, '다', 1), at(0, 200, 260, '라', 3), at(1, 150, 400, '마', 4)];
      final out = AxisModel.withoutSphereEpochs(cells, {(cells[0].start, cells[0].end, '가')});
      // 남은 넷을 시작 · seq 차례로: 다(100 · seq 1) 0단 · 나(100 · seq 2) 1단 · 마(150)는 다의 끝 150 ≤ 150이라 0단 ·
      // 라(200)는 0단(마 ~ 400) · 1단(나 ~ 300)이 아직 차 있어 2단.
      expect([for (final c in out) (c.name, c.lane)], [('다', 0), ('나', 1), ('마', 0), ('라', 2)]);
    });
  });

  // ── 같은 주기는 머리 단 주기 줄만(감독 결정 2026-10-25 '육십갑자는 머리 단 주기 줄만' · 스위치 cycle) ──────────────────────────
  // 날짜 칸 간지 줄과 같은 주기를 펼친 문화권 머리 단의 주기 줄이 그리고 있으면 날짜 칸 간지 줄을 넣지 않는다(정한 것 #4 — 문화권 시대를 공통 줄에서 가림과
  // 같은 자리 · 같은 규칙). 접거나 트랙을 모두 끄면 돌아온다. 자료는 f4-sphere 꼴: 맨 위 yearCycle(불씨해 — 이름 아홉 · 기준 1년)과 분지권(ember) 주기 줄이
  // 같은 이름 돌림이고, 설령권(frost)은 연호 눈금(빙원력).
  group('같은 주기는 머리 단 주기 줄만', () {
    const fire = ['한낮', '별', '바람', '쇠', '새벽', '노을', '달', '물', '숲'];
    const fireAxis = YearCycle(names: fire, start: 1, label: '불씨해');
    final lines = [
      sphereCycle('ember', {'names': fire, 'start': 1, 'label': '불씨해'}),
      sphereCycle('frost', {'era': '빙원', 'from': 300, 'step': 10, 'label': '빙원력'}),
    ];
    final axis = [cell(1, 0, 0, 100, 200, '첫 시대')];
    const spheres = ['ember', 'frost'];

    /// 간지 줄을 켠 날짜 칸(주기 [cycle]).
    AxisModel ganjiOn(SceneLayout layout, {YearCycle? cycle = fireAxis}) => AxisModel(layout)
      ..setYearCycle(cycle)
      ..setShown(ganji: true);
    bool hasGanji(AxisModel m) => m.rows.any((r) => r.kind == AxisRowKind.ganji);

    tearDown(PaintPick.reset);

    test('같으면 간지 줄이 빠지고 날짜 칸이 20 낮아진다 — 그 아래 줄이 20 올라옴', () {
      final bare = ganjiOn(layoutOf(axis));
      final layout = layoutOf(axis, sphereLines: lines, spheres: spheres);
      final model = ganjiOn(layout);
      expect(hasGanji(bare), isTrue);
      expect(bare.rows.firstWhere((r) => r.kind == AxisRowKind.ganji).corner, '불씨해');
      expect(layout.sphereCyclesShown.map((c) => c.title), ['불씨해', '빙원력'], reason: '펼친 문화권 둘의 주기 줄');
      expect(hasGanji(model), isFalse);
      expect(model.height, bare.height - AxisModel.ganjiHeight);
      final cal = bare.rows.firstWhere((r) => r.kind == AxisRowKind.cal).top;
      expect(model.rows.firstWhere((r) => r.kind == AxisRowKind.cal).top, cal - 20);
      // 간지 줄만 빠진다 — 간지를 끈 날짜 칸과 줄 구성 · 높이가 같다.
      final off = AxisModel(layout)..setYearCycle(fireAxis);
      expect(model.rows.map((r) => (r.kind, r.top, r.height)).toList(), off.rows.map((r) => (r.kind, r.top, r.height)).toList());
      expect(model.height, off.height);
      // remake-6과 합치면: 문화권이 내장 육십갑자(이름 60 · 기준 해 4)를 돌리고 날짜 칸이 내장 간지(주기 없음)여도 같은 셈으로 빠진다(검토 지적 3).
      final sixty = [for (int i = 0; i < 60; i++) yearGanji(4 + i)];
      final east = layoutOf(axis, sphereLines: [sphereCycle('ember', {'names': sixty, 'start': 4, 'label': '육십갑자'})], spheres: spheres);
      expect(hasGanji(ganjiOn(east, cycle: null)), isFalse);
      expect(hasGanji(ganjiOn(east, cycle: const YearCycle(off: true))), isFalse);
    });

    test('접거나 트랙을 모두 끄면 돌아온다 · 다시 펴면 다시 빠진다(쌓기 판이 올라 날짜 칸이 다시 진다)', () {
      final layout = layoutOf(axis, sphereLines: lines, spheres: spheres);
      final model = ganjiOn(layout);
      final full = ganjiOn(layoutOf(axis)).height;
      expect(hasGanji(model), isFalse);
      layout.foldSphere('ember', true);
      expect(model.sync(), isTrue);
      expect(hasGanji(model), isTrue, reason: '분지권을 접으면 날짜 칸 줄이 돌아옴');
      expect(model.height, full);
      expect(layout.sphereCyclesShown.map((c) => c.title), ['빙원력'], reason: '설령권(다른 주기)은 펼친 채');
      layout.foldSphere('ember', false);
      expect(model.sync(), isTrue);
      expect(hasGanji(model), isFalse);
      // 분지권의 트랙(1번)을 끄면 머리 단이 서지 않는다 — 그 주기 줄도 없으니 날짜 칸 줄이 돌아온다.
      layout.setViewState(layout.viewState.copyWith(offTracks: const {1}));
      expect(model.sync(), isTrue);
      expect(hasGanji(model), isTrue);
      expect(model.height, full);
      // 처음 접힘(기억 없음 — 첫 문화권 하나만 폄): 분지권이 둘째면 접혀 날짜 칸 줄이 남는다.
      final first = layoutOf(axis, sphereLines: lines, spheres: const ['frost', 'ember'], initialFold: true);
      expect(first.isSphereFolded('ember'), isTrue);
      expect(hasGanji(ganjiOn(first)), isTrue);
    });

    test('다른 주기면 그대로 — 기준 해 · 이름이 다르거나 날짜 칸이 내장 간지 · 연호 눈금뿐인 문화권', () {
      final layout = layoutOf(axis, sphereLines: lines, spheres: spheres);
      final full = ganjiOn(layoutOf(axis)).height;
      for (final (why, cycle) in [
        ('기준 해 다름', const YearCycle(names: fire, start: 2, label: '불씨해')),
        ('이름 다름', const YearCycle(names: ['한낮', '별', '바람', '쇠', '새벽', '노을', '달', '물', '구름'], start: 1, label: '불씨해')),
        ('내장 간지(주기 없음)', null),
        ('사용자 순환을 끔 — 내장 간지', const YearCycle(names: fire, start: 1, label: '불씨해', off: true)),
      ]) {
        final model = ganjiOn(layout, cycle: cycle);
        expect(hasGanji(model), isTrue, reason: why);
        expect(model.height, full, reason: why);
      }
      // 연호 눈금(빙원력)만 펼친 문화권은 해 이름을 돌리지 않으니 날짜 칸 줄이 그대로다.
      final era = layoutOf(axis, sphereLines: [lines[1]], spheres: const ['frost']);
      expect(era.sphereCyclesShown.single.title, '빙원력');
      expect(hasGanji(ganjiOn(era)), isTrue);
      expect(hasGanji(ganjiOn(era, cycle: null)), isTrue);
    });

    test('간지 끔 · 스위치 cycle 끔 · 옛 배치면 그대로', () {
      final full = ganjiOn(layoutOf(axis)).height;
      // 간지 끔: 줄이 없으니 아무 일도 없다(날짜 칸이 문화권 없는 저장소와 같음).
      final layout = layoutOf(axis, sphereLines: lines, spheres: spheres);
      expect(hasGanji(AxisModel(layout)..setYearCycle(fireAxis)), isFalse);
      expect((AxisModel(layout)..setYearCycle(fireAxis)).height, (AxisModel(layoutOf(axis))..setYearCycle(fireAxis)).height);
      // 스위치 cycle 끔(--paint-off=cycle — 찍기 · 증명 전용): 배치를 지을 때 읽어 두므로 끈 뒤 지은 배치는 목록이 비고 날짜 칸이 예전 그대로.
      PaintPick.cycle = false;
      final unpicked = layoutOf(axis, sphereLines: lines, spheres: spheres);
      expect(unpicked.sphereCyclesShown, isEmpty);
      final model = ganjiOn(unpicked);
      expect(hasGanji(model), isTrue);
      expect(model.height, full);
      // 켤 때 지은 배치는 지을 때의 값을 따른다(스위치는 앱을 띄울 때 정해지고 바뀌지 않는다).
      expect(hasGanji(ganjiOn(layout)), isFalse);
      PaintPick.reset();
      // 옛 배치(줄 꼴 없음 — 머리 단을 세우지 않음)는 주기 줄을 그리지 않으니 빈 목록 · 날짜 칸 줄 그대로.
      final old = layoutOf(axis, sphereLines: lines, spheres: spheres, oldRows: true);
      expect(old.sphereCyclesShown, isEmpty);
      expect(hasGanji(ganjiOn(old)), isTrue);
    });
  });
}
