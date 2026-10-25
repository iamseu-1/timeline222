import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive_prototype/scene/labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// 검사용 입력 만들기. 자리는 px로 주고(1px = 1분으로 환산) 이름 · 연도 · 하위 수의 폭도 px.
/// 기본 모양(look)은 '자유 배치'(분류별 글줄 번호 255)다 — 분류별 글줄이 없는 줄과 같다.
const freeLane = 255 << 8;

class Make {
  final at = <double>[], width = <double>[], year = <double>[], count = <double>[];
  final row = <int>[], importance = <int>[], id = <int>[], look = <int>[], kids = <int>[];
  final pillLo = <double>[], pillHi = <double>[];
  final pillRow = <int>[], pillRest = <int>[];

  void event(int eventId, double x, {int r = 0, int imp = 1, double w = 60, int look = freeLane, double yr = 0, int kids = 0, double countWidth = 6}) {
    at.add(x);
    row.add(r);
    importance.add(imp);
    id.add(eventId);
    width.add(w);
    year.add(yr);
    count.add(countWidth);
    this.look.add(look);
    this.kids.add(kids);
  }

  void rest(double lo, double hi, int count, {int r = 0}) {
    pillLo.add(lo);
    pillHi.add(hi);
    pillRow.add(r);
    pillRest.add(count);
  }

  /// 비켜 갈 구간(건국 · 멸망 네모 · 단추 · 내림줄): 줄 0에 (시작 px, 끝 px, 글줄 · −1이면 모두, 점도 비킴, 세기 · −1이면 점 비킴에서 끌어냄, 미는 쪽).
  final zones = <(double, double, int, bool, int, int)>[];

  void zone(double lo, double hi, {int line = -1, bool noDot = false, int sq = -1, int dir = 1}) => zones.add((lo, hi, line, noDot, sq, dir));

  /// 줄마다의 구간 생김새 지문(앞 판과 다르면 그 줄의 이름 이력을 버린다). 비우면 판마다 같은 것으로 친다.
  Int32List? sig;

  /// [bands]는 후보마다 제 띠의 (시작, 끝) px. 비우면 띠의 제한이 없다.
  LabelInput build({
    double scale = 1,
    double spanYears = 100,
    int lines = 2,
    LabelOutput? previous,
    List<(double, double)>? bands,
    int selected = 0,
    Set<int>? highlighted,
    bool bird = false,
  }) => LabelInput(
    version: 1,
    pxPerMinute: scale,
    spanYears: spanYears,
    bandLo: Float64List.fromList([for (int i = 0; i < at.length; i++) bands == null ? double.negativeInfinity : bands[i].$1]),
    bandHi: Float64List.fromList([for (int i = 0; i < at.length; i++) bands == null ? double.infinity : bands[i].$2]),
    at: Float64List.fromList(at),
    row: Int32List.fromList(row),
    importance: Int32List.fromList(importance),
    eventId: Int32List.fromList(id),
    look: Uint32List.fromList(look),
    band: Int32List.fromList([for (int i = 0; i < at.length; i++) bands == null ? 0 : 1]),
    nameWidth: Float32List.fromList(width),
    yearWidth: Float32List.fromList(year),
    countWidth: Float32List.fromList(count),
    kids: Int32List.fromList(kids),
    precLo: Float64List.fromList([for (int i = 0; i < at.length; i++) double.nan]),
    precHi: Float64List.fromList([for (int i = 0; i < at.length; i++) double.nan]),
    pillLo: Float64List.fromList(pillLo),
    pillHi: Float64List.fromList(pillHi),
    pillRow: Int32List.fromList(pillRow),
    pillRest: Int32List.fromList(pillRest),
    rowBase: 0,
    rowLines: Int32List.fromList(List.filled(8, lines)),
    expandedKeys: Int32List(0),
    // 줄 0에만 구간을 둔다(rowBase 0 · rowLines 8줄).
    zoneAt: Int32List.fromList([0, zones.length, for (int i = 0; i < 8; i++) zones.length]),
    zoneLo: Float64List.fromList([for (final z in zones) z.$1 / scale]),
    zoneHi: Float64List.fromList([for (final z in zones) z.$2 / scale]),
    zoneLine: Int32List.fromList([for (final z in zones) z.$3]),
    zoneNoDot: Int32List.fromList([for (final z in zones) z.$4 ? 1 : 0]),
    zoneSq: zones.any((z) => z.$5 >= 0) ? Int32List.fromList([for (final z in zones) z.$5 >= 0 ? z.$5 : (z.$4 ? 2 : 1)]) : null,
    zoneDir: Int32List.fromList([for (final z in zones) z.$6]),
    zoneSig: sig,
    selectedEventId: selected,
    highlighted: highlighted,
    bird: bird,
    previous: previous,
  );
}

/// 출력에서 (줄, 글줄)마다 차지한 가로 구간을 모아 겹침을 찾는다.
List<String> overlaps(LabelInput input, LabelOutput out) {
  final taken = <(int, int), List<(double, double, String)>>{};
  void take(int row, int line, double lo, double hi, String what) => (taken[(row, line)] ??= []).add((lo, hi, what));
  for (int i = 0; i < out.shownCount; i++) {
    final c = out.shownCandidate[i], x = out.shownAt[i] * input.pxPerMinute, row = input.row[c], line = out.shownLine[i];
    final look = input.look[c], id = input.eventId[c];
    take(row, line, x - EventLook.dotWidth(look) / 2, x + EventLook.dotWidth(look) / 2, 'dot$id');
    if (out.shownSide[i] == LabelSide.none) continue;
    final run = labelRun(
      x: x, side: out.shownSide[i], look: look, nameWidth: input.nameWidth[c],
      countWidth: out.shownFlags[i] & LabelFlag.count != 0 ? input.countWidth[c] : 0,
      yearWidth: out.shownFlags[i] & LabelFlag.year != 0 ? input.yearWidth[c] : 0,
    );
    take(row, line, run.left, run.right, 'name$id');
  }
  for (int i = 0; i < out.clusters; i++) {
    final x = out.clusterAt[i] * input.pxPerMinute, w = out.clusterWidth[i];
    take(out.clusterRow[i], out.clusterLine[i], x - w / 2, x + w / 2, 'pill$i');
  }
  final found = <String>[];
  for (final entry in taken.entries) {
    final list = entry.value..sort((a, b) => a.$1.compareTo(b.$1));
    for (int i = 1; i < list.length; i++) {
      // 점과 제 이름은 붙어 있어도 된다(같은 사건). 서로 다른 것끼리만 본다.
      if (list[i].$1 < list[i - 1].$2 - 1e-6 && list[i].$3.replaceAll(RegExp('[a-z]'), '') != list[i - 1].$3.replaceAll(RegExp('[a-z]'), '')) {
        found.add('${entry.key}: ${list[i - 1].$3} ↔ ${list[i].$3}');
      }
    }
  }
  return found;
}

/// 그려진 점 · 포갠 점 · 알약이 품은 사건의 수.
int totalShown(LabelOutput out) {
  int n = 0;
  for (int i = 0; i < out.shownCount; i++) {
    n += 1 + out.shownCoins[i];
  }
  for (int i = 0; i < out.clusters; i++) {
    n += out.clusterCount[i];
  }
  return n;
}

Set<int> namedIds(LabelInput input, LabelOutput out) =>
    {for (int i = 0; i < out.shownCount; i++) if (out.shownSide[i] != LabelSide.none) input.eventId[out.shownCandidate[i]]};

void main() {
  test('씨앗 고정 난수 200벌: 이름 · 알약 · 점이 서로 겹치지 않고 개수가 보존된다', () {
    final random = math.Random(20260921);
    for (int round = 0; round < 200; round++) {
      final m = Make();
      final n = 5 + random.nextInt(120);
      int rests = 0;
      for (int i = 0; i < n; i++) {
        m.event(i + 1, random.nextDouble() * 1600, r: random.nextInt(3), imp: 1 + random.nextInt(3), w: 30 + random.nextDouble() * 110);
      }
      for (int b = 0; b < 8; b++) {
        if (random.nextBool()) continue;
        final count = 1 + random.nextInt(900);
        m.rest(b * 200.0, b * 200.0 + 200, count, r: random.nextInt(3));
        rests += count;
      }
      final input = m.build();
      final out = placeLabels(input);
      expect(overlaps(input, out), isEmpty, reason: '벌 $round');
      expect(totalShown(out), n + rests, reason: '벌 $round: 점 + 포갠 점 + 알약 = 대표 + 나머지');
    }
  });

  test('같은 입력이면 같은 출력이다', () {
    final m = Make();
    final random = math.Random(7);
    for (int i = 0; i < 80; i++) {
      m.event(i + 1, random.nextDouble() * 900, imp: 1 + random.nextInt(3), w: 40 + random.nextDouble() * 80);
    }
    final a = placeLabels(m.build()), b = placeLabels(m.build());
    expect(a.shownCandidate, b.shownCandidate);
    expect(a.shownSide, b.shownSide);
    expect(a.shownLine, b.shownLine);
    expect(a.shownExtra, b.shownExtra);
    expect(a.clusterAt, b.clusterAt);
  });

  test('자리를 다투면 중요도가 큰 사건이 이름을 얻는다', () {
    // 띠는 0~600px. 1번의 오른쪽 자리(93~273)와 3번의 왼쪽 자리(133~309)가 같은 곳을 다툰다 —
    // 1번의 왼쪽은 띠 밖이고, 3번의 오른쪽은 9번 점이 막는다(9번은 이름이 띠에 들지 않아 점만 남는다).
    Make contest({required int first, required int third}) => Make()
      ..event(9, 320, imp: 1, w: 600)
      ..event(1, 100, imp: first, w: 150)
      ..event(3, 300, imp: third, w: 150);
    Set<int> named(Make m) {
      final input = m.build(lines: 1, bands: [(0, 600), (0, 600), (0, 600)]);
      return namedIds(input, placeLabels(input));
    }

    expect(named(contest(first: 1, third: 3)), allOf(contains(3), isNot(contains(1))));
    expect(named(contest(first: 3, third: 1)), allOf(contains(1), isNot(contains(3))));
  });

  test('이름 없는 점은 11px 안이면 개수 알약으로 묶이고, 묶인 것은 14px 벌어져야 풀린다', () {
    // 보기 폭이 3,000년이면 이름이 아예 붙지 않는다 — 남은 점이 묶인다.
    Make apart(double gap) => Make()
      ..event(1, 100, imp: 1)
      ..event(2, 100 + gap, imp: 2);
    LabelOutput run(double gap, {LabelOutput? previous}) => placeLabels(apart(gap).build(spanYears: 3000, previous: previous));
    final near = run(8);
    expect(near.clusters, 1);
    expect(near.clusterCount[0], 2);
    expect(near.shownCount, 0, reason: '묶인 점은 알약 뒤에 숨는다');
    // 12px: 처음 보면 따로, 앞 판에서 묶여 있었으면 그대로 묶음, 15px이면 풀림.
    expect(run(12).clusters, 0);
    expect(run(12, previous: near).clusters, 1);
    expect(run(15, previous: near).clusters, 0);
  });

  test('이름 붙은 점 곁의 이름 없는 점은 그 점에 포개진다(동전 겹침)', () {
    final m = Make()
      ..event(1, 300, imp: 3, w: 60)
      ..event(2, 306, imp: 1, w: 4000); // 이름이 들어갈 수 없는 폭 → 점만
    final input = m.build(lines: 1);
    final out = placeLabels(input);
    expect(out.shownCount, 1);
    expect(input.eventId[out.shownCandidate[0]], 1);
    expect(out.shownCoins[0], 1);
    expect(out.shownFlags[0] & LabelFlag.more, LabelFlag.more);
  });

  test('통의 나머지 개수는 그 통의 대표가 든 묶음에 붙고, 대표가 없으면 제 알약으로 선다', () {
    // 이름이 붙지 않는 보기 폭에서: 120 · 126의 두 점이 한 묶음, 그 통의 나머지 37이 거기에 붙는다.
    final m = Make()
      ..event(1, 120, imp: 3)
      ..event(2, 126, imp: 1)
      ..rest(100, 164, 37)
      ..rest(400, 464, 5);
    final out = placeLabels(m.build(spanYears: 3000));
    expect(out.clusters, 2);
    expect(out.clusterCount[0], 39, reason: '묶인 둘 + 통의 나머지 37');
    expect(out.clusterCount[1], 5);
    expect(out.clusterAt[1], 432);
  });

  test('보기 폭에 따라 이름을 보일 중요도가 달라지고 경계에서 흔들리지 않는다', () {
    Make three() => Make()
      ..event(1, 100, imp: 1)
      ..event(2, 500, imp: 2)
      ..event(3, 900, imp: 3);
    Set<int> named(double spanYears, {LabelOutput? previous}) {
      final input = three().build(spanYears: spanYears, previous: previous);
      return namedIds(input, placeLabels(input));
    }

    expect(named(3000), isEmpty);
    expect(named(2000), {3});
    expect(named(800), {2, 3});
    expect(named(300), {1, 2, 3});
    final all = placeLabels(three().build(spanYears: 300));
    expect(named(530, previous: all), {1, 2, 3}, reason: '500년을 조금 넘어도(8% 안) 보이던 이름은 남는다');
    expect(named(560, previous: all), {2, 3});
  });

  test('배율이 조금 바뀌어도 보이던 이름은 가능한 한 남는다', () {
    final m = Make();
    final random = math.Random(11);
    for (int i = 0; i < 60; i++) {
      m.event(i + 1, random.nextDouble() * 1500, w: 50 + random.nextDouble() * 70);
    }
    final first = m.build();
    final before = placeLabels(first);
    final next = m.build(scale: 1.05, previous: before);
    final after = placeLabels(next);
    final kept = namedIds(first, before).intersection(namedIds(next, after));
    expect(kept.length, greaterThanOrEqualTo((namedIds(first, before).length * .9).floor()), reason: '5% 넓어졌는데 이름이 우수수 바뀌면 깜빡인다');
    expect(overlaps(next, after), isEmpty);
  });

  test('이름은 제 띠 밖으로 나가지 않는다', () {
    // 띠는 100~400px. 오른쪽 끝 가까이의 사건은 이름이 왼쪽으로 가고, 어느 쪽으로도 띠를 넘으면 이름을 보이지 않는다.
    final m = Make()
      ..event(1, 330, w: 100)
      ..event(2, 250, w: 200, r: 1);
    final input = m.build(bands: [(100, 400), (100, 400)]);
    final out = placeLabels(input);
    expect(out.shownSide[0], LabelSide.left, reason: '오른쪽(323~447)은 띠 끝 403을 넘는다');
    expect(out.shownSide[1], LabelSide.none, reason: '오른쪽 · 왼쪽 모두 띠를 넘는다');
    // 띠의 끝을 모르면(타일 경계에서 잘린 띠) 막지 않는다.
    final open = placeLabels(m.build(bands: [(100, double.infinity), (double.negativeInfinity, 400)]));
    expect(open.shownSide[0], LabelSide.right);
    expect(open.shownSide[1], LabelSide.left);
  });

  test('폭을 아직 모르는 이름은 다음 판으로 미룬다', () {
    final m = Make()
      ..event(1, 100, w: double.nan)
      ..event(2, 600, w: 50);
    final out = placeLabels(m.build());
    expect(out.deferred, 1);
    expect(out.shownSide[0], LabelSide.none);
    expect(out.shownSide[1], isNot(LabelSide.none));
  });

  test('분류별 글줄이 있는 줄에서는 사건이 제 분류의 글줄에만 놓인다', () {
    // look 8~15비트가 글줄 번호다: 1번은 글줄 0, 2번은 글줄 2.
    final m = Make()
      ..event(1, 200, imp: 3, w: 40, look: 0 << 8)
      ..event(2, 220, imp: 3, w: 40, look: 2 << 8);
    final input = m.build(lines: 3);
    final out = placeLabels(input);
    final line = {for (int i = 0; i < out.shownCount; i++) input.eventId[out.shownCandidate[i]]: out.shownLine[i]};
    expect(line, {1: 0, 2: 2});
  });

  test('공동 사건의 다른 자리에는 이름을 붙이지 않는다', () {
    const pair = freeLane | 1 << 17 | 1 << 18;
    final m = Make()
      ..event(1, 300, imp: 3, w: 40, look: pair)
      ..event(2, 800, imp: 3, w: 40);
    final input = m.build();
    expect(namedIds(input, placeLabels(input)), {2});
  });

  test('자리가 모자라면 연도부터 뗀다(둘째 차례)', () {
    // 띠는 0~470px. 1번이 먼저 연도까지 붙여 오른쪽(93~273)에 자리를 잡으면,
    // 2번은 연도를 단 채로는 오른쪽이 띠를 넘고 왼쪽이 1번에 걸린다 — 연도를 떼야 오른쪽에 든다.
    final m = Make()
      ..event(1, 100, imp: 3, w: 120, yr: 30)
      ..event(2, 330, imp: 2, w: 120, yr: 30);
    final input = m.build(lines: 1, bands: [(0, 470), (0, 470)]);
    final out = placeLabels(input);
    final flags = {for (int i = 0; i < out.shownCount; i++) input.eventId[out.shownCandidate[i]]: out.shownFlags[i]};
    expect(flags[1]! & LabelFlag.year, LabelFlag.year, reason: '먼저 자리를 잡은 이름은 연도를 그대로 단다');
    expect(namedIds(input, out), {1, 2});
    expect(flags[2]! & LabelFlag.year, 0, reason: '뒤에 든 이름은 연도를 떼고 들어간다');
  });

  test('접힌 하위 사건이 있으면 이름 뒤에 그 수의 알약이 붙는다', () {
    final m = Make()..event(1, 300, imp: 3, w: 60, kids: 8, countWidth: 6);
    final input = m.build(lines: 1);
    final out = placeLabels(input);
    expect(out.shownExtra[0], 8);
    expect(out.shownFlags[0] & LabelFlag.count, LabelFlag.count);
    final run = labelRun(x: 300, side: out.shownSide[0], look: freeLane, nameWidth: 60, countWidth: 6, yearWidth: 0);
    expect(run.countLeft, greaterThan(run.nameRight), reason: '알약은 이름의 바깥쪽에 붙는다');
  });

  test('점은 제 띠 안쪽 9px로 당겨진다', () {
    final m = Make()..event(1, 102, imp: 3, w: 40);
    final out = placeLabels(m.build(bands: [(100, 400)]));
    expect(out.shownAt[0], 109);
  });

  test('비켜 갈 구간(네모 · 단추 · 내림줄)에는 이름이 들지 않고, 점도 비킨다', () {
    // 글줄 하나 · 300px에 놓인 네모(점까지 비키는 구간). 부풀리기는 [a − 4.5, b + 8]이다.
    final m = Make()
      ..event(1, 300, imp: 3, w: 60)
      ..zone(295, 305, noDot: true);
    final out = placeLabels(m.build(lines: 1));
    expect(out.shownAt[0], 290.5, reason: '점은 부푼 구간 [295 − 4.5, 305 + 8]의 가까운 바깥으로 밀린다');
    // 구간을 빼면 제자리에 선다.
    final plain = Make()..event(1, 300, imp: 3, w: 60);
    expect(placeLabels(plain.build(lines: 1)).shownAt[0], 300);
  });

  test('점을 밀지 않는 구간은 이름만 비킨다', () {
    // 글줄이 둘 이상인 줄의 네모는 글자만 비킨다(지금 연표 _sqZones의 세기 1).
    final m = Make()
      ..event(1, 300, imp: 3, w: 200)
      ..zone(320, 420);
    final input = m.build(lines: 1);
    final out = placeLabels(input);
    expect(out.shownAt[0], 300, reason: '점은 그대로');
    expect(out.shownSide[0], LabelSide.left, reason: '오른쪽은 구간에 막혀 이름이 뒤집힌다');
  });

  test('강조에 든 사건이 이름 자리에서 앞선다', () {
    // 같은 중요도의 두 사건이 한 자리를 다툰다 — 강조(prio +10)가 걸린 쪽이 먼저 자리를 잡는다.
    Set<int> named(Set<int>? highlighted) {
      final m = Make()
        ..event(1, 300, imp: 2, w: 150)
        ..event(2, 300.5, imp: 2, w: 150); // 같은 해의 두 점 — 서로의 이름을 덮지 않는다
      final input = m.build(lines: 1, bands: [(250, 480), (250, 480)], highlighted: highlighted);
      return namedIds(input, placeLabels(input));
    }

    expect(named(null), {1}, reason: '같은 중요도면 이른 것이 먼저');
    expect(named({2}), {2}, reason: '강조에 든 2번이 앞선다');
  });

  test('조감에서는 이름이 아예 붙지 않고, 알약은 작은 알약이다', () {
    final m = Make()
      ..event(1, 300, imp: 3, w: 60)
      ..event(2, 306, imp: 3, w: 60)
      ..event(3, 312, imp: 3, w: 60);
    final input = m.build(lines: 1, bands: [(0, 900), (0, 900), (0, 900)], bird: true);
    final out = placeLabels(input);
    expect(namedIds(input, out), isEmpty, reason: '조감은 minImp 99');
    expect(out.clusters, 1);
    expect(out.clusterFlags[0] & ClusterFlag.small, ClusterFlag.small);
    expect(out.clusterWidth[0], LabelGeo.smallPillWidth(3));
  });

  test('통의 나머지에서 접힌 하위 사건 수를 뺀다', () {
    // 통에는 부모와 그 접힌 자식 여덟이 들어 있다(자료 처리부는 자식도 센다) — 화면에는 부모의 알약 `8`만 남는다.
    final m = Make()
      ..event(1, 300, imp: 3, w: 60, kids: 8)
      ..rest(290, 320, 8);
    final out = placeLabels(m.build(lines: 1));
    expect(out.clusters, 0, reason: '나머지가 모두 접힌 자식이면 알약을 세우지 않는다');
    expect(out.shownExtra[0], 8);
    // 자식 말고 하나가 더 있으면 그 하나는 대표 뒤에 포갠다.
    final m2 = Make()
      ..event(1, 300, imp: 3, w: 60, kids: 8)
      ..rest(290, 320, 9);
    final out2 = placeLabels(m2.build(lines: 1));
    expect(out2.clusters, 0);
    expect(out2.shownCoins[0], 1);
    expect(out2.shownFlags[0] & LabelFlag.more, LabelFlag.more);
  });

  test('나머지가 남은 통의 이름 없는 대표들은 나머지와 묶인다 — 붙어 있으면 한 묶음', () {
    // 이름이 꺼진 배율(보기 폭 3,000년)에서 대표 셋이 11px 안에 붙어 있으면 통 하나가 통째로 한 묶음이다.
    final m = Make()
      ..event(1, 300, imp: 3, w: 60)
      ..event(2, 308, imp: 3, w: 60)
      ..event(3, 316, imp: 3, w: 60)
      ..rest(280, 440, 40);
    final input = m.build(lines: 1, spanYears: 3000, bands: [(0, 900), (0, 900), (0, 900)]);
    final out = placeLabels(input);
    expect(out.clusters, 1, reason: '붙어 있는 대표 셋은 한 묶음');
    expect(out.clusterCount[0], 43, reason: '대표 셋 + 나머지 마흔');
    expect(totalShown(out), 43);
  });

  test('통의 나머지는 묶음 규칙으로 나뉜 묶음마다 나뉘어 붙는다', () {
    // 같은 통 안이라도 대표가 60px씩 떨어져 있으면 지금 연표는 알약이 따로 선다(이웃 거리 11px · 알약 폭까지).
    // 통의 나머지는 묶음에 든 대표 수에 맞춰 나뉘고, 합은 통의 수 그대로다.
    final m = Make()
      ..event(1, 300, imp: 3, w: 60)
      ..event(2, 360, imp: 3, w: 60)
      ..event(3, 420, imp: 3, w: 60)
      ..rest(280, 440, 40);
    final input = m.build(lines: 1, spanYears: 3000, bands: [(0, 900), (0, 900), (0, 900)]);
    final out = placeLabels(input);
    expect(out.clusters, 3, reason: '떨어진 자리마다 알약 하나');
    expect([for (int i = 0; i < out.clusters; i++) out.clusterCount[i]].reduce((a, b) => a + b), 43);
    expect(totalShown(out), 43, reason: '개수는 보존된다');
    expect(out.shownCount, 0, reason: '묶인 대표는 알약 뒤에 숨는다 — 홀로 선 점으로 남지 않는다');
  });

  test('통의 나머지는 글줄마다 나뉜다 — 다른 글줄의 대표가 홀로 선 점으로 남지 않는다', () {
    // 분류별 글줄이 셋인 줄에서 대표가 글줄마다 하나씩. 통의 나머지를 한 글줄에만 얹으면 나머지 둘이 점으로 남는다.
    final m = Make()
      ..event(1, 300, imp: 3, w: 60, look: 0 << 8)
      ..event(2, 304, imp: 3, w: 60, look: 1 << 8)
      ..event(3, 308, imp: 3, w: 60, look: 2 << 8)
      ..rest(280, 340, 30);
    final input = m.build(lines: 3, spanYears: 3000, bands: [(0, 900), (0, 900), (0, 900)]);
    final out = placeLabels(input);
    expect(out.clusters, 3, reason: '글줄마다 알약 하나');
    expect({for (int i = 0; i < out.clusters; i++) out.clusterLine[i]}, {0, 1, 2});
    expect([for (int i = 0; i < out.clusters; i++) out.clusterCount[i]].reduce((a, b) => a + b), 33);
    expect(totalShown(out), 33);
    expect(out.shownCount, 0);
  });

  test('이웃 통의 알약 곁에 홀로 선 점은 그 알약에 다시 묶인다', () {
    // 왼쪽 통(280~320)은 대표가 하나도 없어 제 알약으로 서고, 그 곁의 대표 하나는 제 통에 나머지가 없어 점으로 남는다 —
    // 두 자리가 지금 연표의 이웃 거리 안이면 한 알약이다.
    final m = Make()
      ..rest(280, 320, 6)
      ..event(3, 325, imp: 3, w: 60);
    final input = m.build(lines: 1, spanYears: 3000, bands: [(0, 900)]);
    final out = placeLabels(input);
    expect(out.clusters, 1);
    expect(out.clusterCount[0], 7, reason: '통의 나머지 여섯 + 이웃의 점 하나');
    expect(out.shownCount, 0);
    expect(totalShown(out), 7);
    // 멀리 떨어진 점은 그대로 점이다.
    final far = Make()
      ..rest(280, 320, 6)
      ..event(3, 380, imp: 3, w: 60);
    final out2 = placeLabels(far.build(lines: 1, spanYears: 3000, bands: [(0, 900)]));
    expect(out2.shownCount, 1);
    expect(out2.clusterCount[0], 6);
  });

  test('세기 0인 구간(소속 · 대범위 단추)은 이름 줄 전체를 막는다', () {
    // 지금 연표의 단추 자리는 `reserved[줄][0].push([l, r])` — 셋째 값이 없어 blocks의 마지막 갈래(이름 줄 전체)로 걸린다.
    // 세기 1(네모)이면 글자 상자만 막아 단추 오른쪽에 이름이 비집고 들어간다(기준 그림에 없는 이름 하나가 그것이었다).
    // 이름 줄은 300 − 7 ~ 377이고 글자 상자는 309 ~ 370이다 — 그 사이(371~376)에 구간을 두면 세기가 갈린다.
    Make one() => Make()..event(1, 300, imp: 3, w: 60);
    final blocked = one()..zone(371, 376, sq: 0);
    final input = blocked.build(lines: 1, bands: [(0, 900)]);
    expect(placeLabels(input).shownSide[0], LabelSide.left, reason: '세기 0은 이름 줄 전체가 걸려 뒤집힌다');
    final weak = one()..zone(371, 376, sq: 1);
    expect(placeLabels(weak.build(lines: 1, bands: [(0, 900)])).shownSide[0], LabelSide.right, reason: '세기 1은 글자 상자만 막아 그대로 오른쪽');
    // 점을 미는가는 세기와 따로다(지금 연표도 목록이 둘) — 단추도 글줄이 하나인 줄에서는 점을 민다.
    final push = one()..zone(290, 330, noDot: true, sq: 0);
    expect(placeLabels(push.build(lines: 1, bands: [(0, 900)])).shownAt[0], lessThan(300.0));
  });

  test('점을 미는 부풀리기는 구간이 미는 쪽(dir)에 따라 다르다', () {
    // 지금 연표의 `avoid`: 오른쪽으로 미는 구간(건국 네모 · 단추 — dir +1)은 [a−4.5, b+8],
    // 왼쪽으로 미는 구간(멸망 네모 — dir −1)은 [a−10, b+4.5]. 구간의 자리가 같아도 미는 쪽이 다르면 점이 다른 데로 간다.
    final right = Make()
      ..event(1, 300, imp: 3, w: 4000)
      ..zone(295, 305, noDot: true);
    expect(placeLabels(right.build(lines: 1, bands: [(0, 900)])).shownAt[0], 290.5, reason: 'dir +1: 왼쪽 바깥이 a − 4.5');
    final left = Make()
      ..event(1, 300, imp: 3, w: 4000)
      ..zone(295, 305, noDot: true, dir: -1);
    expect(placeLabels(left.build(lines: 1, bands: [(0, 900)])).shownAt[0], 309.5, reason: 'dir −1: 오른쪽 바깥이 b + 4.5');
  });

  test('구간이 달라진 줄은 이름 이력을 한 번 버린다', () {
    // 구간(네모 · 단추)은 그리기보다 한 장면 늦게 온다. 구간이 없던 판에 놓인 이름이 이력(namedBefore) 때문에
    // 여유 0으로 눌러앉으면, 구간이 온 뒤에도 지금 연표에는 없는 자리에 이름이 남는다.
    // 이름 줄은 300 − 7 ~ 300 + 60 + 17 = 293 ~ 377이고, 새 이름의 여유는 4px이다.
    // 380~390의 구간은 여유 0이면 안 걸리고(380 < 377 거짓), 여유 4면 걸린다(380 < 381 참).
    Int32List sigOf(int head) => Int32List.fromList([head, 0, 0, 0, 0, 0, 0, 0]);
    Make one() => Make()..event(1, 300, imp: 3, w: 60);
    // ① 구간이 없는 첫 판 — 이름은 오른쪽.
    final firstOut = placeLabels((one()..sig = sigOf(0)).build(lines: 1, bands: [(0, 900)]));
    expect(firstOut.shownSide[0], LabelSide.right);
    // ② 구간이 도착한 둘째 판. 지문이 그대로면 이력이 살아 여유 0으로 눌러앉는다.
    final kept = one()
      ..zone(380, 390, sq: 0)
      ..sig = sigOf(0);
    final keptOut = placeLabels(kept.build(lines: 1, bands: [(0, 900)], previous: firstOut));
    expect(keptOut.shownSide[0], LabelSide.right, reason: '지문이 같으면 이력 그대로 — 여유 0이라 구간에 안 걸린다');
    // ③ 같은 판인데 지문만 달라지면(구간이 새로 생긴 줄) 이력을 버리고 새 이름의 여유로 다시 잰다.
    final dropped = one()
      ..zone(380, 390, sq: 0)
      ..sig = sigOf(7);
    final droppedOut = placeLabels(dropped.build(lines: 1, bands: [(0, 900)], previous: firstOut));
    expect(droppedOut.shownSide[0], LabelSide.left, reason: '지문이 달라진 줄은 이력을 버려 여유 4로 다시 잰다 — 오른쪽이 막혀 뒤집힌다');
    // 버리는 것은 한 번뿐이다 — 다음 판에서 지문이 같으면 이력이 다시 산다.
    final again = one()
      ..zone(380, 390, sq: 0)
      ..sig = sigOf(7);
    final againOut = placeLabels(again.build(lines: 1, bands: [(0, 900)], previous: droppedOut));
    expect(againOut.shownSide[0], LabelSide.left, reason: '지문이 그대로면 앞 판의 자리를 이어 간다');
  });

  test('통이 실어 준 분류 비율이 있으면 색줄을 그것으로 센다', () {
    // 대표가 하나도 없는 통(나머지만) — 지금은 색줄이 비지만, 자료 처리부가 비율을 실어 주면 그대로 쓴다.
    final m = Make()..rest(280, 340, 12);
    final plain = placeLabels(m.build(lines: 1, spanYears: 3000));
    expect(plain.clusterCatAt[1] - plain.clusterCatAt[0], 0, reason: '열이 없으면 예전처럼 빈 채로');
    final withCats = LabelInput(
      version: 1, pxPerMinute: 1, spanYears: 3000,
      at: Float64List(0), row: Int32List(0), importance: Int32List(0), eventId: Int32List(0), look: Uint32List(0), band: Int32List(0),
      nameWidth: Float32List(0), yearWidth: Float32List(0), countWidth: Float32List(0), kids: Int32List(0),
      bandLo: Float64List(0), bandHi: Float64List(0), precLo: Float64List(0), precHi: Float64List(0),
      pillLo: Float64List.fromList([280]), pillHi: Float64List.fromList([340]),
      pillRow: Int32List.fromList([0]), pillRest: Int32List.fromList([12]),
      pillCatAt: Int32List.fromList([0, 2]), pillCat: Int32List.fromList([1, 3]), pillCatCount: Int32List.fromList([8, 4]),
      rowBase: 0, rowLines: Int32List.fromList([1]), expandedKeys: Int32List(0),
    );
    final out = placeLabels(withCats);
    expect(out.clusters, 1);
    expect(out.clusterCat.toList(), [1, 3]);
    expect(out.clusterCatCount.toList(), [8, 4]);
  });
}
