import 'dart:io';

import 'package:archive_prototype/scene/paint/strips.dart' show CellKind, CellStyle;
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 스키마 4(계약 1-1)의 칸 종류 9 · 칸 style 27비트 · 일반 구역 54 ~ 56을 받는 읽개(lib/scene/schema4_items.dart)의 검사.
// 여기서는 엔진 없이 손으로 짠 타일(TileBuilder)과 옛 고정 타일로 본다(진짜 엔진 타일과의 대조는 schema4_real_engine_test). 그림판(strips.dart)의 CellKind · CellStyle은
// 번호와 비트 풀개를 견주려고 import만 한다.

/// 칸 목록에서의 순번(비트 15 ~ 26 — 0 = 싣지 않음이라 순번 + 1). 내보내기 export/power.mjs의 styleWith와 같은 셈.
int seqBits(int seq) => (seq + 1) << 15;

void main() {
  group('상수', () {
    test('계약 1-1 그대로의 번호와 비트', () {
      expect(Schema4.cellOfficeMore, 9);
      expect(Schema4.borrowed, 0x8000000);
      expect((Schema4.secBorrowHead, Schema4.secOfficeName, Schema4.secPowerLine), (54, 55, 56));
      expect(Schema4.cellOfficeMore, isNot(CellKind.common), reason: '8은 공용 칸 단이 쓴다');
      expect(Schema4.secBorrowHead, greaterThanOrEqualTo(Tile.secGeneral), reason: '일반 구역(16 이상)');
    });

    test('내보내기 JS(strips.mjs · power.mjs)의 번호와 같다', () {
      final strips = File('../scripts/export/strips.mjs').readAsStringSync();
      final power = File('../scripts/export/power.mjs').readAsStringSync();
      String one(String text, String pattern) => RegExp(pattern).firstMatch(text)!.group(1)!;
      expect(int.parse(one(strips, r'export const KIND_OFFICE = (\d+);')), Schema4.cellOfficeMore);
      expect(1 << int.parse(one(strips, r'export const ST_BORROW = 1 << (\d+);')), Schema4.borrowed);
      expect(int.parse(one(strips, r'borrow: (\d+)')), Schema4.secBorrowHead);
      expect(int.parse(one(strips, r'officeName: (\d+)')), Schema4.secOfficeName);
      expect(int.parse(one(power, r'export const SECTION_POWER_LINE = (\d+);')), Schema4.secPowerLine);
    });
  });

  group('칸 style 27비트', () {
    test('isBorrowed 진리표 — 종류 1 · 2 · 9에서 27비트가 설 때만 참', () {
      for (int kind = 0; kind <= 10; kind++) {
        final want = kind == CellKind.leader || kind == CellKind.cabinet || kind == Schema4.cellOfficeMore;
        expect(Schema4.isBorrowed(kind, Schema4.borrowed), want, reason: '종류 $kind · 27비트만');
        expect(Schema4.isBorrowed(kind, 0), isFalse, reason: '종류 $kind · 비트 없음');
        expect(Schema4.isBorrowed(kind, ~Schema4.borrowed & 0xffffffff), isFalse, reason: '종류 $kind · 27비트 밖이 모두 서도');
      }
      // 잘림 표시(256 · 512)가 붙은 cellKind 값을 그대로 넘겨도 종류만 본다.
      expect(Schema4.isBorrowed(CellKind.leader | 256 | 512, Schema4.borrowed), isTrue);
      expect(Schema4.isBorrowed(Schema4.cellOfficeMore | 512, Schema4.borrowed), isTrue);
      expect(Schema4.isBorrowed(CellKind.common | 256, Schema4.borrowed), isFalse);
    });

    test('종류 8의 27 ~ 29비트는 단 갈래 — 27비트가 선 갈래(1 · 3 · 5 · 7)도 빌림이 아니다', () {
      for (int band = 1; band <= 7; band++) {
        final style = band << 27 | seqBits(3);
        expect(CellStyle.bandOf(style), band);
        expect(style & Schema4.borrowed != 0, band.isOdd, reason: '갈래 $band의 아래 비트가 27비트');
        expect(Schema4.isBorrowed(CellKind.common, style), isFalse, reason: '종류 8 · 갈래 $band');
      }
    });

    test('27비트는 순번(15 ~ 26) · 명목 지도자(29) · 아래 표시 비트를 건드리지 않는다', () {
      expect(Schema4.borrowed & (0xfff << 15), 0);
      expect(Schema4.borrowed & CellStyle.nominalLeader, 0);
      expect(Schema4.borrowed & CellStyle.nominalLowered, 0);
      expect(Schema4.borrowed & 0x7fff, 0, reason: '아래 표시 · 서열 · 예속 모양 · 번갈아 짙기(0 ~ 14)');
      for (final seq in [0, 1, 41, 4093]) {
        final plain = seqBits(seq) | CellStyle.nominalLeader | CellStyle.unkStart | CellStyle.joinLeft | CellStyle.alt;
        final style = plain | Schema4.borrowed;
        expect(CellStyle.seqOf(style), seq, reason: '순번 $seq');
        expect(CellStyle.seqOf(style), CellStyle.seqOf(plain));
        expect(style & CellStyle.nominalLeader, isNonZero);
        expect(style & 0xff, plain & 0xff);
        expect((CellStyle.rankOf(style), CellStyle.depLookOf(style), CellStyle.altOf(style)),
            (CellStyle.rankOf(plain), CellStyle.depLookOf(plain), CellStyle.altOf(plain)));
        expect(Schema4.isBorrowed(CellKind.leader, style), isTrue);
        expect(Schema4.isBorrowed(CellKind.leader, plain), isFalse);
      }
      // 순번이 넘친 값(0xfff → −1)도 27비트와 상관없이 그대로다.
      expect(CellStyle.seqOf(0xfff << 15 | Schema4.borrowed), -1);
    });
  });

  group('타일에서 읽기', () {
    test('종류 9 칸 · 빌린 지도자 · 내각 칸 · 종류 8 단체 칸', () {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(7, 0, 0, 4000, '솔바람국')
        ..band(9, 1, 0, 4000, '물안개국')
        ..cell(100, 0, 0, 1000, '첫 임금', kind: CellKind.leader, style: seqBits(0))
        ..cell(101, 0, 1000, 2000, '빌린 임금', kind: CellKind.leader, style: Schema4.borrowed | CellStyle.nominalLeader | seqBits(1))
        ..cell(102, 0, 0, 1500, '빌린 재상', kind: CellKind.cabinet, style: Schema4.borrowed | seqBits(0))
        ..cell(103, 0, 0, 2000, '도독 첫 칸', kind: Schema4.cellOfficeMore, lane: 0, style: seqBits(0))
        ..cell(104, 0, 2000, 4000, '빌린 대장군', kind: Schema4.cellOfficeMore, lane: 1, flags: Tile.clipRight,
            style: Schema4.borrowed | seqBits(0))
        ..cell(105, 1, 0, 3000, '집권 단체', kind: CellKind.common, lane: 2, style: CellStyle.groupOne << 27 | seqBits(2));
      final t = Tile.decode(b.build());
      expect(t.cellCount, 6);

      // 종류 9는 칸 배열 그대로 — 번호 목록만.
      final more = Schema4.officeMoreCells(t);
      expect(more, [3, 4]);
      expect([for (final i in more) (t.cellId[i], t.cellLane[i] & 0xff, t.text(t.cellName[i]))], [(103, 0, '도독 첫 칸'), (104, 1, '빌린 대장군')]);
      expect(t.cellFlagsOf(4), Tile.clipRight, reason: '잘림 표시가 붙어도 종류 9로 센다');

      // 빌림 — cellKind 값 그대로나 cellKindOf나 같다.
      final want = [false, true, true, false, true, false];
      expect([for (int i = 0; i < t.cellCount; i++) Schema4.isBorrowed(t.cellKind[i], t.cellStyle[i])], want);
      expect([for (int i = 0; i < t.cellCount; i++) Schema4.isBorrowed(t.cellKindOf(i), t.cellStyle[i])], want);

      // 빌린 지도자 칸: 명목 지도자 · 순번이 함께 선다.
      expect(CellStyle.seqOf(t.cellStyle[1]), 1);
      expect(t.cellStyle[1] & CellStyle.nominalLeader, isNonZero);
      expect(CellStyle.seqOf(t.cellStyle[2]), 0);

      // 종류 8 단체 칸: 갈래 5(0b101)라 27비트가 서 있지만 빌림이 아니다.
      expect(t.cellStyle[5] & Schema4.borrowed, isNonZero);
      expect(CellStyle.bandOf(t.cellStyle[5]), CellStyle.groupOne);
      expect(CellStyle.isGroupBand(CellStyle.bandOf(t.cellStyle[5])), isTrue);
      expect(CellStyle.seqOf(t.cellStyle[5]), 2);

      // 구역 54 ~ 56이 없는 타일은 빈 목록.
      expect(Schema4.borrowHeads(t), isEmpty);
      expect(Schema4.officeNames(t), isEmpty);
      expect(Schema4.powerLines(t), isEmpty);
    });

    test('구역 54 · 55 · 56의 항목을 실린 차례대로 읽는다', () {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(7, 0, 0, 4000, '솔바람국')
        ..band(9, 2, 500, 3000, '물안개국')
        ..item(54, 11, 0, 0, 4000, ref: 7, name: '나루국/지도자', a: CellKind.leader, text2: 'naru')
        ..item(54, 12, 0, 0, 4000, ref: 7, name: '나루국/재상', a: CellKind.cabinet, text2: 'naru')
        ..item(54, 13, 0, 0, 4000, ref: 7, name: '하늬국/대장군', a: Schema4.cellOfficeMore, b: 1) // 출처를 못 찾으면 uid ''
        ..item(55, 21, 0, 0, 4000, ref: 7, name: '도독', a: Schema4.cellOfficeMore, b: 0)
        ..item(55, 22, 0, 0, 4000, ref: 7, name: '대장군', a: Schema4.cellOfficeMore, b: 1)
        ..item(56, 31, 2, 800, 1600.5, ref: 9, name: '솔바람국', color: 0x3366cc, text2: 'sol')
        ..item(56, 32, 2, 500, 3000, ref: 9, name: '세도 가문', a: 1)
        // 이웃 번호의 구역(뜻과 상관없이)은 섞여 들지 않는다.
        ..item(53, 41, 0, 0, 4000, ref: 7, name: '이웃 53', a: 1, b: 1)
        ..item(57, 42, 0, 0, 4000, ref: 7, name: '이웃 57', a: 1);
      final t = Tile.decode(b.build());
      expect(t.sectionKinds, [1, 53, 54, 55, 56, 57]);

      expect(Schema4.borrowHeads(t), const [
        BorrowHead(id: 11, band: 7, row: 0, x0: 0, x1: 4000, source: '나루국/지도자', kind: 1, lane: 0, sourceUid: 'naru'),
        BorrowHead(id: 12, band: 7, row: 0, x0: 0, x1: 4000, source: '나루국/재상', kind: 2, lane: 0, sourceUid: 'naru'),
        BorrowHead(id: 13, band: 7, row: 0, x0: 0, x1: 4000, source: '하늬국/대장군', kind: 9, lane: 1, sourceUid: ''),
      ]);
      expect(Schema4.officeNames(t), const [
        OfficeName(id: 21, band: 7, row: 0, lane: 0, name: '도독'),
        OfficeName(id: 22, band: 7, row: 0, lane: 1, name: '대장군'),
      ]);
      expect(Schema4.powerLines(t), const [
        PowerLine(id: 31, band: 9, row: 2, x0: 800, x1: 1600.5, holder: '솔바람국', color: 0x3366cc, own: false, holderUid: 'sol'),
        PowerLine(id: 32, band: 9, row: 2, x0: 500, x1: 3000, holder: '세도 가문', color: 0, own: true, holderUid: ''),
      ]);
      // 머리 글의 lane과 직위 줄 더 이름의 lane은 같은 줄을 가리킨다.
      final heads = Schema4.borrowHeads(t).where((h) => h.kind == Schema4.cellOfficeMore).map((h) => h.lane);
      expect(Schema4.officeNames(t).map((o) => o.lane), containsAll(heads));
      // 받은 목록은 바꿀 수 없다.
      expect(() => Schema4.powerLines(t).add(Schema4.powerLines(t).first), throwsUnsupportedError);
    });

    test('옛 고정 타일에는 종류 9 칸 · 구역 54 ~ 56이 없다', () {
      final t = Tile.decode(File('test/fixtures/tile-100k-L9-x0-c0.bin').readAsBytesSync());
      expect(t.cellCount, greaterThan(0));
      expect(Schema4.officeMoreCells(t), isEmpty);
      expect(t.sectionKinds.where((k) => k >= Schema4.secBorrowHead && k <= Schema4.secPowerLine), isEmpty);
      expect(Schema4.borrowHeads(t), isEmpty);
      expect(Schema4.officeNames(t), isEmpty);
      expect(Schema4.powerLines(t), isEmpty);
    });
  });
}
