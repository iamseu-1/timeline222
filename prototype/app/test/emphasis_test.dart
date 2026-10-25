import 'package:archive_prototype/scene/emphasis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('고른 것이 없으면 모두 제 밝기', () {
    const l = Look();
    expect(l.bandAlpha(1, 0), 1);
    expect(l.eventAlpha(1, 0), 1);
    expect(l.linkAlpha(1, 2), 1);
  });

  test('띠를 고르면 그 띠만 밝고 선은 닿는 것만', () {
    const l = Look(band: 7);
    expect(l.bandAlpha(7, 3), 1);
    expect(l.bandAlpha(8, 3), .58);
    expect(l.eventAlpha(1, 3), .45);
    expect(l.linkAlpha(7, 9), 1);
    expect(l.linkAlpha(8, 9), .14);
  });

  test('사건을 고르면 같은 줄의 띠와 사건이 덜 어둡다', () {
    const l = Look(event: 5, row: 2);
    expect(l.eventAlpha(5, 2), 1);
    expect(l.eventAlpha(6, 2), .7);
    expect(l.eventAlpha(6, 4), .45);
    expect(l.bandAlpha(1, 2), 1);
    expect(l.bandAlpha(1, 4), .58);
  });

  test('강조 밖은 .2 — 고른 줄이어도 · 메아리는 흐리지 않는다', () {
    const l = Look(event: 5, row: 2, bands: {1}, events: {5}, echo: {9});
    expect(l.bandAlpha(2, 2), .2);
    expect(l.bandAlpha(1, 2), 1);
    expect(l.eventAlpha(6, 2), .2);
    expect(l.eventAlpha(9, 4), .45);
  });

  test('같은 사람이 앉은 나라(건의 8의 6-나)는 고른 나라처럼 — 고름의 .58 · 강조 밖 .2에서 빠진다', () {
    const l = Look(band: 7, bands: {7}, twins: {'7|leader:3', '9|leader:1'}, twinBands: {7, 9});
    expect(l.bandAlpha(7, 0), 1);
    expect(l.bandAlpha(9, 4), 1);
    expect(l.bandAlpha(8, 0), .2);
    expect(l.tabAlpha(9), 1, reason: '탭도 고른 나라처럼');
    expect(l.isTwin(9, 'leader:1'), isTrue);
    expect(l.isTwin(9, 'leader:0'), isFalse);
  });

  test('바뀌면 지금 밝기에서 흐르고, 도중에 또 바뀌어도 튀지 않는다', () {
    final e = Emphasis();
    e.set(const Look(band: 7));
    expect(e.bandAlpha(8, 0), 1, reason: '첫 장면은 떠난 값');
    e.tick(80);
    final mid = e.bandAlpha(8, 0);
    expect(mid, inExclusiveRange(.58, 1));
    e.set(const Look()); // 되돌아감
    expect(e.bandAlpha(8, 0), closeTo(mid, 1e-9), reason: '목표가 바뀐 순간 값이 이어진다');
    for (var i = 0; i < 10; i++) {
      e.tick(40);
    }
    expect(e.active, isFalse);
    expect(e.bandAlpha(8, 0), 1);
  });

  test('움직임 줄이기면 바로 도착', () {
    final e = Emphasis()..reduceMotion = true;
    e.set(const Look(band: 7));
    expect(e.active, isFalse);
    expect(e.bandAlpha(8, 0), .58);
  });

  // ---- 기간 조명의 흐름(명세 06의 3-3절 `_litState`) ----
  // 구간마다 진행([Spot.glow])이 실려 온다: 등장 200ms에 0 → 1 · 물러남 160ms에 1 → 0 ·
  // 옮길 때 두 구간에 다 드는 곳은 1 그대로 · 한 번에 한 옮김. 가라앉은 값은 늘 1이라 읽지 않는 층은 지금과 같다.
  group('기간 조명의 흐름', () {
    Look lit(List<Spot> spots) => Look(lit: true, spots: spots);
    List<Spot> of(Emphasis e, int band) => e.spotsOf(band).toList();
    Spot at(Emphasis e, int band, double start) => of(e, band).firstWhere((s) => s.start == start);
    // 토큰 길이는 정착 시각이 아니다. 검사에서는 임계 감쇠의 꼬리까지 기다린다.
    void run(Emphasis e, double ms, {double step = 20}) {
      for (double t = 0; t < ms * 2; t += step) {
        e.tick(step);
      }
    }

    test('나타남 — 바깥 밝기에서 시작해 200ms에 1로', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100)]));
      expect(of(e, 1).single.glow, 0, reason: '첫 장면은 아직 어둡다');
      expect(e.litMoving, isTrue);
      e.tick(50); // 한 장면에 세는 시간은 50ms까지다
      expect(of(e, 1).single.glow, inExclusiveRange(0, 1));
      run(e, 200);
      expect(of(e, 1).single.glow, 1);
      expect(e.litMoving, isFalse);
      expect(of(e, 1).single.start, 0, reason: '가라앉으면 Look.spots 그대로');
    });

    test('물러남 — 160ms에 0으로 옅어진 뒤 사라진다', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100)]));
      run(e, 220);
      e.set(const Look());
      expect(of(e, 1).single.glow, 1, reason: '지금 밝기에서 옅어지기 시작한다');
      e.tick(80);
      expect(of(e, 1).single.glow, inExclusiveRange(0, 1));
      run(e, 120);
      expect(of(e, 1), isEmpty);
      expect(e.litMoving, isFalse);
    });

    test('옮김 — 새 구간만 밝아지고 옛 구간만 어두워진다', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100, cell: 'leader:0')]));
      run(e, 220);
      e.set(lit(const [Spot(1, 100, 200, cell: 'leader:1')]));
      expect(of(e, 1).length, 2);
      expect(at(e, 1, 0).glow, 1, reason: '옛 구간은 지금 밝기에서 떠난다');
      expect(at(e, 1, 100).glow, 0, reason: '새 구간은 어두운 데서 밝아진다');
      e.tick(80);
      expect(at(e, 1, 0).glow, lessThan(1));
      expect(at(e, 1, 100).glow, greaterThan(0));
      run(e, 220);
      expect(of(e, 1).map((s) => s.start), [100]);
      expect(of(e, 1).single.glow, 1);
    });

    test('두 구간에 다 드는 곳은 그대로 — 품는 구간으로 옮겨도 어두워지지 않는다', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100)]));
      run(e, 220);
      // 새 구간이 옛 구간을 통째로 품는다: 겹치는 자리는 새 구간이 다 밝아질 때까지 1로 버틴다.
      e.set(lit(const [Spot(1, 0, 300)]));
      for (final ms in [0.0, 60.0, 120.0]) {
        if (ms > 0) e.tick(ms);
        expect(at(e, 1, 0).end, 100, reason: '옛 구간이 아직 겹친 자리를 지킨다');
        expect(at(e, 1, 0).glow, 1);
      }
      run(e, 220);
      expect(of(e, 1).map((s) => s.end), [300]);
      expect(of(e, 1).single.glow, 1);
      // 반대로 이미 밝은 구간 안으로 옮기면 새 구간은 1에서 시작한다(다시 밝아지지 않는다).
      e.set(lit(const [Spot(1, 50, 80)]));
      expect(at(e, 1, 50).glow, 1);
    });

    test('되돌아감은 바로 뒤집고, 셋째 구간은 가라앉은 뒤에 이어 간다', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100)]));
      run(e, 220);
      e.set(lit(const [Spot(1, 200, 300)]));
      e.tick(60);
      // ▶ 뒤 곧바로 ◀ — 목표만 뒤집어 지금 진행에서 되돌아간다.
      e.set(lit(const [Spot(1, 0, 100)]));
      run(e, 220);
      expect(of(e, 1).map((s) => s.start), [0]);

      // 옮기는 도중에 셋째 구간으로: 이번 옮김이 가라앉은 뒤에 이어 간다(한 번에 한 옮김).
      e.set(lit(const [Spot(1, 200, 300)]));
      e.tick(40);
      e.set(lit(const [Spot(1, 400, 500)]));
      expect(of(e, 1).map((s) => s.start), containsAll([0, 200]), reason: '셋째 구간은 아직 오지 않았다');
      run(e, 260);
      expect(of(e, 1).map((s) => s.start), contains(400));
      run(e, 260);
      expect(of(e, 1).map((s) => s.start), [400]);
      expect(e.litMoving, isFalse);
    });

    test('띠마다 제 것만 · 움직임 줄이기면 바로 도착', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100), Spot(2, 0, 100)]));
      expect(of(e, 1).length, 1);
      expect(of(e, 2).length, 1);
      expect(of(e, 3), isEmpty);

      final quick = Emphasis()..reduceMotion = true;
      quick.set(lit(const [Spot(1, 0, 100)]));
      expect(of(quick, 1).single.glow, 1);
      expect(quick.litMoving, isFalse);
      quick.set(const Look());
      expect(of(quick, 1), isEmpty);
    });

    test('조명 구간의 밝기 규칙은 그대로 — lit이면 1, 아니면 띠의 밝기', () {
      final e = Emphasis()..set(lit(const [Spot(1, 0, 100)]));
      expect(e.spotAlpha(1, 0), 1);
      e.set(const Look(band: 7, spots: [Spot(1, 0, 100)]));
      expect(e.spotAlpha(1, 0), e.bandAlpha(1, 0));
    });
  });

  // ──────────────── 가문 조명(확정 설계 1-2 5-3 · D1-N3) ────────────────
  group('가문 조명(Look.houses)', () {
    test('묶음의 가문 칸은 진하게(isHouse) · 조명된 띠의 다른 지도자 칸은 .55 · 다른 띠는 1', () {
      const l = Look(house: 'h-a', houses: {'h-a', 'h-a-sub'}, spots: [Spot(3, 0, 100), Spot(5, 50, 80)]);
      expect(l.housed, isTrue);
      expect(l.isHouse('h-a'), isTrue);
      expect(l.isHouse('h-a-sub'), isTrue, reason: '아래 파도 함께(10절 12번)');
      expect(l.isHouse('h-b'), isFalse);
      expect(l.isHouse(''), isFalse);
      expect(l.houseCellAlpha(3, 'h-b'), Dim.houseOther);
      expect(l.houseCellAlpha(3, ''), Dim.houseOther, reason: '가문이 없는 칸도 다른 칸');
      expect(l.houseCellAlpha(3, 'h-a-sub'), 1);
      expect(l.houseCellAlpha(4, 'h-b'), 1, reason: '조명이 없는 띠는 흐리지 않는다');
      // 옛 꼴(house 하나)은 .55가 없다.
      const old = Look(house: 'h-a');
      expect(old.housed, isFalse);
      expect(old.isHouse('h-a'), isTrue);
      expect(old.houseCellAlpha(3, 'h-b'), 1);
      // 가문 조명은 연표를 흐리게 하지 않는다(고르지 않는 창).
      expect(l.bandAlpha(4, 0), 1);
      expect(l.trimDim, 1);
    });

    test('.55는 흐른다 — 켤 때 160ms에 옅어지고 끌 때 200ms에 1로', () {
      final e = Emphasis();
      expect(e.housing, isFalse);
      e.set(const Look(houses: {'h-a'}, spots: [Spot(3, 0, 100)]));
      expect(e.housing, isTrue);
      e.tick(40);
      final mid = e.houseCellAlpha(3, 'h-b');
      expect(mid, lessThan(1));
      expect(mid, greaterThan(Dim.houseOther));
      for (int i = 0; i < 16; i++) {
        e.tick(25);
      }
      expect(e.houseCellAlpha(3, 'h-b'), Dim.houseOther);
      e.set(const Look());
      expect(e.housing, isTrue, reason: '꺼지며 흐르는 동안');
      e.tick(40);
      expect(e.houseCellAlpha(3, 'h-b'), greaterThan(Dim.houseOther));
      for (int i = 0; i < 16; i++) {
        e.tick(25);
      }
      expect(e.houseCellAlpha(3, 'h-b'), 1);
      expect(e.housing, isFalse);
    });

    test('isHouseSpot: 가문 조명의 구간만 — 꺼지며 옅어지는 동안에도 참, 가라앉으면 잊고, 같은 구간을 칸 조명이 바라면 거짓', () {
      const spot = Spot(3, 0, 100);
      final e = Emphasis();
      e.set(const Look(houses: {'h-a'}, spots: [spot]));
      expect(e.isHouseSpot(spot), isTrue);
      for (int i = 0; i < 12; i++) {
        e.tick(25);
      }
      e.set(const Look());
      e.tick(40);
      expect(e.spotsOf(3), isNotEmpty, reason: '옅어지는 중');
      expect(e.isHouseSpot(e.spotsOf(3).single), isTrue);
      for (int i = 0; i < 12; i++) {
        e.tick(25);
      }
      expect(e.spotsOf(3), isEmpty);
      expect(e.isHouseSpot(spot), isFalse, reason: '다 꺼지면 잊는다');
      // 칸 조명 · 인물 조명은 가문의 것이 아니다.
      final f = Emphasis()..reduceMotion = true;
      f.set(const Look(houses: {'h-a'}, spots: [spot]));
      expect(f.isHouseSpot(spot), isTrue);
      f.set(const Look(spots: [spot]));
      expect(f.isHouseSpot(spot), isFalse, reason: '같은 구간을 가문 조명이 아닌 상태가 바란다');
      f.set(const Look(cell: 'leader:0', spots: [Spot(3, 0, 100, cell: 'leader:0')]));
      expect(f.isHouseSpot(const Spot(3, 0, 100, cell: 'leader:0')), isFalse);
    });
  });
}
