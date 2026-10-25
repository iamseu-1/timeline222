import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

/// 고정 파일은 10만 건 가상 자료의 타일 하나다(단계 9 · x 0 · 줄 묶음 0 · 자료집 전부):
/// archive-tool tile data/v3-100k/archive.db '{"level":9,"x":0,"chunk":0,"packs":[1,2,3,4,5,6,7,8]}' app/test/fixtures/tile-100k-L9-x0-c0.bin
/// 타일 형식이나 가상 자료의 규칙이 바뀌면 다시 떠서 아래 숫자를 고친다(2026-10-13 다시 뜸 — 알약의 분류 비율 열이 실린 타일).
Uint8List fixture() =>
    File('test/fixtures/tile-100k-L9-x0-c0.bin').readAsBytesSync();

void main() {
  test('머리와 구역 표와 배열 길이를 읽는다', () {
    final t = Tile.decode(fixture());
    expect((t.level, t.x, t.chunk), (9, 0, 0));
    expect((t.origin, t.span), (0, 67108864));
    expect(t.byteLength, 19176);
    expect(
      (t.bandCount, t.cellCount, t.eventCount, t.pillCount, t.stringCount),
      (19, 237, 82, 4, 306),
    );
    expect(t.sectionKinds, [1, 2, 3, 4, 16], reason: '띠 · 칸 · 사건 · 알약 · 일반 구역 16');
    expect((t.section(1).columns, t.section(2).columns, t.section(3).columns, t.section(4).columns), (10, 9, 10, 5),
        reason: '알약은 네 열 뒤에 분류 비율 열 cats가 더해져 다섯이다(계약 5-1절)');
    expect(t.bandX0.length, 19);
    expect(t.cellKind.length, 237);
    expect(t.eventBits.length, 82);
    expect(t.pillCount, t.pillRow.length);
  });

  test('없는 구역은 빈 구역, 없는 열은 0으로 찬 배열이다', () {
    final t = Tile.decode(fixture());
    expect(t.section(99).count, 0);
    expect(t.section(99).u(3), isEmpty);
    // 열 수를 넘겨 물으면 항목 수만큼의 0이 온다 — 옛 타일에 새 열을 물어도 죽지 않는다.
    expect(t.section(4).u(9).length, t.pillCount);
    expect(t.section(4).u(9).every((v) => v == 0), isTrue);
  });

  test('띠와 칸과 사건의 값을 그대로 읽는다', () {
    final t = Tile.decode(fixture());
    expect(t.bandX0[0], 0);
    expect(t.bandX1[0], 19352160);
    expect(t.bandId[0], 104);
    expect(t.bandColor[0], 0xdab195);
    expect(t.text(t.bandName[0]), '솔바람국 8');
    expect(t.bandRow[0], 0);
    expect(t.bandFlags[0], Tile.clipLeft, reason: '타일 왼쪽 경계에서 잘린 띠');
    expect((t.bandLook[0], t.text(t.bandTag[0]), t.bandSub[0]), (0, '', 0));
    expect(t.bandLook[3], 1, reason: '열에 하나쯤은 0이 아닌 표현 값');
    expect(t.text(t.bandName[18]), '여울마루 68');
    expect(t.bandRow[18], 7);
    expect(t.text(t.cellName[0]), '물안개 왕조');
    expect(t.cellKindOf(0), 0);
    expect(t.cellFlagsOf(1), Tile.clipLeft);
    expect((t.cellKindOf(1), t.cellLane[1], t.cellStyle[1], t.cellColor[1]), (1, 0, 4, 0));
    expect(t.cellLane[28], 1, reason: '겹치면 단을 나눈다');
    expect(t.cellColor[55], 0x9dbea8, reason: '0이 아니면 제 색');
    expect(t.eventX0[0], 4919544);
    expect(t.text(t.eventName[0]), '별여울 기록 0000504');
    expect(t.importanceOf(0), 2);
    expect(t.isCounted(0), isTrue);
    expect(t.isBar(0), isFalse);
    expect((t.eventLook[0], t.text(t.eventLabel[0]), t.eventRail[0]), (4, '1979년', 0));
    expect(t.eventBand[0], 104, reason: '그 사건이 든 띠');
  });

  test('일반 구역은 열 번호로 읽는다', () {
    final t = Tile.decode(fixture());
    final tags = t.section(16);
    expect((tags.count, tags.columns), (1, 14));
    expect(t.text(tags.u(Tile.itemName)[0]), '새벽 속국');
    expect((tags.u(Tile.itemRow)[0], tags.u(Tile.itemRow2)[0]), (1, 1));
    expect(tags.u(Tile.itemRef)[0], 210, reason: '가리키는 띠의 번호');
    expect(tags.u(Tile.itemA)[0], 1);
    expect(tags.f(Tile.itemX0)[0], lessThan(tags.f(Tile.itemX1)[0]));
    expect(t.text(tags.u(Tile.itemText2)[0]), '');
  });

  test('센 대표와 알약 개수의 합, 막대, 중요도 3의 수', () {
    final t = Tile.decode(fixture());
    int counted = 0, bars = 0, grand = 0, rest = 0;
    for (int i = 0; i < t.eventCount; i++) {
      if (t.isCounted(i)) counted++;
      if (t.isBar(i)) bars++;
      if (t.importanceOf(i) == 3) grand++;
    }
    for (int i = 0; i < t.pillCount; i++) {
      rest += t.pillRest[i];
    }
    expect((counted, bars, grand, rest), (68, 18, 3, 301));
    // 알약의 다섯째 열(계약 5-1절): 통 전체의 분류별 수를 적은 글 — 대표 넷을 뺀 나머지(75 · 76 · 75 · 75)보다 넷씩 많다.
    final cats = t.section(Tile.secPill).u(4);
    expect([for (int i = 0; i < t.pillCount; i++) t.text(cats[i])], ['0:79', '0:80', '0:79', '0:79']);
  });

  test('글자표는 한글과 한문을 되살리고 없는 이름은 빈 글자다', () {
    final t = Tile.decode(fixture());
    final all = [for (int i = 0; i < t.stringCount; i++) t.text(i)];
    expect(all.any((s) => s.contains('星河')), isTrue);
    expect(all.toSet().length, all.length, reason: '같은 글자는 표에 한 번만');
    expect(t.text(Tile.noName), '');
    expect(identical(t.text(3), t.text(3)), isTrue, reason: '한 번 푼 글자는 타일이 기억한다');
  });

  test('잘린 바이트와 틀린 표지는 거절한다', () {
    final bytes = fixture();
    expect(() => Tile.decode(Uint8List.sublistView(bytes, 0, 40)), throwsFormatException);
    expect(() => Tile.decode(Uint8List.sublistView(bytes, 0, 9000)), throwsFormatException);
    final broken = Uint8List.fromList(bytes)..[0] ^= 1;
    expect(() => Tile.decode(broken), throwsFormatException);
    final old = Uint8List.fromList(bytes)..[4] = 1;
    expect(() => Tile.decode(old), throwsFormatException, reason: '1판 타일은 거절한다');
  });

  test('4바이트에 맞지 않게 놓인 바이트도 읽는다', () {
    final bytes = fixture();
    final shifted = Uint8List(bytes.length + 1)..setRange(1, bytes.length + 1, bytes);
    final t = Tile.decode(Uint8List.sublistView(shifted, 1));
    expect(t.text(t.bandName[0]), '솔바람국 8');
    expect(t.eventX0[0], 4919544);
  });

  test('빈 타일', () {
    final empty = Uint8List(76);
    final head = ByteData.sublistView(empty);
    head.setUint32(0, 0x32545448, Endian.little);
    head.setUint16(4, 2, Endian.little);
    final t = Tile.decode(empty);
    expect((t.bandCount, t.cellCount, t.eventCount, t.pillCount, t.stringCount), (0, 0, 0, 0, 0));
    expect(t.sectionKinds, isEmpty);
    expect(t.barIndices, isEmpty);
    expect(t.eventsIn(0, 0, 1e9), (0, 0));
  });

  test('모르는 구역이 사이에 끼어도 아는 구역을 제자리에서 읽는다', () {
    final b = TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, 0, 100, '별여울국', look: 5, tag: '전해 오는 이야기', sub: 3)
      ..event(7, 0, 50, '별여울 기록', look: 0x0103, label: '12년', rail: 2, band: 1)
      ..pill(0, 0, 64, 9)
      ..item(16, 11, 0, 0, 100, ref: 1, name: '해솔 속국', a: 1, b: 2, text2: '곁글')
      ..item(40, 12, 0, 10, 20, row2: 3, color: 0x8a8f96);
    final t = Tile.decode(b.build());
    expect(t.sectionKinds, [1, 3, 4, 16, 40]);
    expect((t.bandLook[0], t.text(t.bandTag[0]), t.bandSub[0]), (5, '전해 오는 이야기', 3));
    expect((t.eventLook[0], t.text(t.eventLabel[0]), t.eventRail[0], t.eventBand[0]), (0x0103, '12년', 2, 1));
    expect(t.pillRest[0], 9, reason: '모르는 구역이 있어도 알약은 제자리에서 읽힌다');
    final tags = t.section(16);
    expect((t.text(tags.u(Tile.itemName)[0]), tags.u(Tile.itemRef)[0], tags.u(Tile.itemB)[0]), ('해솔 속국', 1, 2));
    expect(t.section(40).u(Tile.itemRow2)[0], 3);
    expect(t.cellCount, 0, reason: '없는 구역은 빈 구역');
  });

  test('보이는 범위의 사건만 짚는다: 줄마다의 구간에서 시각으로 이분 검색', () {
    // 자료 처리부는 사건을 (줄, 시각, 번호) 순으로 보낸다. 1,000만 건에서는 타일 하나에 사건이 8천 개까지 들어 있어,
    // 화면 밖의 것까지 장면마다 훑으면 만들기 시간이 자료 크기와 함께 는다.
    final b = TileBuilder(level: 9, x: 0, chunk: 1); // 줄 8~15
    for (int i = 0; i < 10; i++) {
      b.event(100 + i, 9, i * 100.0, '별여울 $i');
    }
    b
      ..event(200, 12, 50, '해솔')
      ..event(201, 12, 450, '은빛 나루')
      ..event(300, 9, 250, '긴 공사', x1: 800, bits: 2 | Tile.bar | Tile.counted)
      ..event(301, 15, 0, '긴 뱃길', x1: 90, bits: 1 | Tile.bar)
      ..pill(12, 64, 128, 3)
      ..pill(9, 640, 704, 7)
      ..pill(9, 0, 64, 5);
    final t = Tile.decode(b.build());
    expect([for (int i = t.pillsIn(9, 600, 700).$1; i < t.pillsIn(9, 600, 700).$2; i++) t.pillRest[i]], [7]);
    expect([for (int i = t.pillsIn(9, 0, 700).$1; i < t.pillsIn(9, 0, 700).$2; i++) t.pillRest[i]], [5, 7]);
    expect(t.pillsIn(10, 0, 700).$2 - t.pillsIn(10, 0, 700).$1, 0, reason: '알약이 없는 줄은 빈 범위');
    List<int> ids((int, int) range) => [for (int i = range.$1; i < range.$2; i++) t.eventId[i]];
    expect(ids(t.eventsIn(9, 200, 400)), [102, 300, 103, 104], reason: '양 끝 포함, 시각 순(막대도 제 시작 시각에)');
    expect(ids(t.eventsIn(9, -50, 0)), [100]);
    expect(ids(t.eventsIn(9, 901, 5000)), isEmpty);
    expect(ids(t.eventsIn(12, 0, 1000)), [200, 201]);
    expect(ids(t.eventsIn(10, 0, 1000)), isEmpty, reason: '사건이 없는 줄');
    expect(ids(t.eventsIn(3, 0, 1000)), isEmpty, reason: '이 묶음 밖의 줄');
    expect([for (final i in t.barIndices) t.eventId[i]], [300, 301], reason: '막대만 따로 짚어 둔다');
  });
}
