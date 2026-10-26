import 'dart:io';

import 'package:archive_prototype/scene/band_form.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellKind, CellStyle;
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 스키마 4(계약 1-1)의 칸 종류 9 · 칸 style 27비트 · 일반 구역 54 ~ 56을 받는 읽개(lib/scene/schema4_items.dart)의 검사.
// 칸 그림 갈래 걸음 1에서 배치 갈래가 실은 구역 57 · 58(칸 · 소속 구간의 정통성)과 띠 비트(look 30 · sub 17 ~ 23)의 읽개 검사를 더했다.
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

    test('옛 고정 타일에는 종류 9 칸 · 구역 54 ~ 58이 없고 띠 비트도 0', () {
      final t = Tile.decode(File('test/fixtures/tile-100k-L9-x0-c0.bin').readAsBytesSync());
      expect(t.cellCount, greaterThan(0));
      expect(Schema4.officeMoreCells(t), isEmpty);
      expect(t.sectionKinds.where((k) => k >= Schema4.secBorrowHead && k <= Schema4.secHostLegit), isEmpty);
      expect(Schema4.borrowHeads(t), isEmpty);
      expect(Schema4.officeNames(t), isEmpty);
      expect(Schema4.powerLines(t), isEmpty);
      expect(Schema4.cellLegits(t), isEmpty);
      expect(Schema4.hostLegits(t), isEmpty);
      // 배치 갈래의 띠 비트(look 30 · sub 17 ~ 23)는 옛 타일에 없다 — 직위 줄 더 0 · 지도자 한 단.
      expect(t.bandCount, greaterThan(0));
      for (int i = 0; i < t.bandCount; i++) {
        expect(Schema4.hasOfficeFloor(t.bandLook[i]), isFalse, reason: '띠 $i');
        expect(Schema4.officeMoreOf(t.bandSub[i]), 0, reason: '띠 $i');
        expect(Schema4.leaderLanesOf(t.bandSub[i]), 1, reason: '띠 $i');
      }
    });
  });

  // 칸 그림 갈래(가지 remake-4-cells) 걸음 1 — 배치 갈래(remake-4-lay)가 실은 칸 · 소속 정통성 구역 57 · 58과 띠 비트(계약 1-1 덧붙임)의 읽개.
  group('정통성 구역 57 · 58 · 띠 비트(배치 갈래가 실은 값)', () {
    test('구역 번호 · 정통성 번호가 내보내기 JS(strips.mjs · bands.mjs)와 BandForm의 차례와 같다', () {
      final strips = File('../scripts/export/strips.mjs').readAsStringSync();
      final bands = File('../scripts/export/bands.mjs').readAsStringSync();
      String one(String text, String pattern) => RegExp(pattern).firstMatch(text)!.group(1)!;
      expect(int.parse(one(strips, r'legit: (\d+) \}')), Schema4.secCellLegit);
      expect(int.parse(one(bands, r'export const SECTION_HOST_STATUS = (\d+);')), Schema4.secHostLegit);
      expect((Schema4.secCellLegit, Schema4.secHostLegit), (57, 58));
      // 정통성 번호 = BandForm.legits의 차례 = STATUS_NO − 1(d = 번호 + 1).
      final table = one(bands, r'export const STATUS_NO = \{([^}]*)\};');
      final statusNo = {for (final m in RegExp(r'(\w+): (\d+)').allMatches(table)) m.group(1)!: int.parse(m.group(2)!)};
      final ours = {
        'legit': Schema4.legitOfficial,
        'rival': Schema4.legitRival,
        'joint': Schema4.legitJoint,
        'regent': Schema4.legitRegent,
        'nominal': Schema4.legitNominal,
        'claim': Schema4.legitClaim,
      };
      expect(statusNo.keys.toList(), BandForm.legits, reason: '내보내기 번호표와 BandForm의 차례');
      for (final e in ours.entries) {
        expect(BandForm.legits.indexOf(e.key), e.value, reason: e.key);
        expect(statusNo[e.key]! - 1, e.value, reason: '${e.key}: d − 1');
      }
    });

    test('띠 비트 풀개 — look 30 · sub 17 ~ 21 · sub 22 ~ 23(내보내기 tracks.mjs가 켜는 자리)', () {
      final tracks = File('../scripts/export/tracks.mjs').readAsStringSync();
      expect(tracks, contains('p.look |= 1 << 30;'));
      expect(tracks, contains('p.sub |= n << 17;'));
      expect(tracks, contains('p.sub |= (n - 1) << 22;'));
      expect(Schema4.lookOfficeMore, 1 << 30);
      // 칸 층 비트 21 ~ 29 · 다른 look 비트와 섞이지 않는다.
      expect(Schema4.hasOfficeFloor(1 << 30), isTrue);
      expect(Schema4.hasOfficeFloor(0x1ff << 21 | 1 << 20 | 1 << 19), isFalse);
      expect(Schema4.hasOfficeFloor(0x3fffffff), isFalse);
      for (int n = 0; n <= 31; n++) {
        // 예속 수(sub 12 ~ 16) · 지위(0 ~ 2) · 지도자 단(22 ~ 23)과 함께 서도 제 자리만 읽는다.
        final sub = 31 << 12 | 7 | n << 17 | 3 << 22;
        expect(Schema4.officeMoreOf(sub), n, reason: '직위 줄 더 $n');
        expect(Schema4.officeMoreOf(n << 17), n);
      }
      for (int lanes = 1; lanes <= 4; lanes++) {
        final sub = (lanes - 1) << 22 | 31 << 17 | 31 << 12 | 7;
        expect(Schema4.leaderLanesOf(sub), lanes, reason: '지도자 단 $lanes');
        expect(Schema4.leaderLanesOf((lanes - 1) << 22), lanes);
      }
      expect(Schema4.leaderLanesOf(0), 1, reason: '옛 띠는 한 단');
      expect(Schema4.officeMoreOf(0), 0);
    });

    test('구역 57 · 58의 항목을 실린 차례대로 읽는다(f4-legit 정답지의 꼴 — 다빈왕 c 3 d 3 · 태후 서리 d 4 · 백사 공국 빙원 동맹 명목)', () {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(7, 0, 0, 4000, '하연 왕국', sub: 1 << 22)
        ..band(9, 3, 500, 3000, '백사 공국')
        // 칸의 정통성: 순번 + 1(c) · 정통성 + 1(d) · 두 단 띠의 지도자 칸은 b가 그 단.
        ..item(57, 11, 0, 100, 900.5, ref: 7, a: 1, b: 1, c: 3, d: 3) // 다빈왕 — 공동 · 아래 단
        ..item(57, 12, 0, 900.5, 1200, ref: 7, a: 1, b: 0, c: 5, d: 4) // 태후 서리 — 섭정
        ..item(57, 13, 0, 0, 4000, ref: 7, a: 2, b: 0, c: 1, d: 5) // 내각 — 명목
        ..item(57, 14, 0, 0, 4000, ref: 7, a: 9, b: 2, c: 1, d: 6) // 직위 줄 더(셋째 줄 차례 2) — 주장
        ..item(58, 21, 3, 1000, 3000, ref: 9, name: '빙원 동맹', color: 0x5b8bb0, a: 0, b: 1, d: 5, text2: 'f4-legit/o-icefield')
        ..item(58, 22, 3, 500, 1000, ref: 9, name: '해협 동맹', a: 1, b: 0, d: 2) // a 1은 시대 그릇 소속의 몫(계약은 아직 싣지 않음) · 상위 uid 없음
        // 이웃 번호의 구역은 섞여 들지 않는다.
        ..item(56, 31, 0, 0, 4000, ref: 7, name: '이웃 56', a: 1, b: 1, c: 1, d: 1)
        ..item(59, 32, 0, 0, 4000, ref: 7, name: '이웃 59', a: 1, b: 1, c: 1, d: 1);
      final t = Tile.decode(b.build());
      expect(t.sectionKinds, [1, 56, 57, 58, 59]);

      expect(Schema4.cellLegits(t), const [
        CellLegit(id: 11, band: 7, row: 0, x0: 100, x1: 900.5, kind: 1, lane: 1, seq: 2, legit: Schema4.legitJoint),
        CellLegit(id: 12, band: 7, row: 0, x0: 900.5, x1: 1200, kind: 1, lane: 0, seq: 4, legit: Schema4.legitRegent),
        CellLegit(id: 13, band: 7, row: 0, x0: 0, x1: 4000, kind: 2, lane: 0, seq: 0, legit: Schema4.legitNominal),
        CellLegit(id: 14, band: 7, row: 0, x0: 0, x1: 4000, kind: Schema4.cellOfficeMore, lane: 2, seq: 0, legit: Schema4.legitClaim),
      ]);
      expect(Schema4.hostLegits(t), const [
        HostLegit(id: 21, band: 9, row: 3, x0: 1000, x1: 3000, hostName: '빙원 동맹', hostColor: 0x5b8bb0, era: false, seq: 1, legit: Schema4.legitNominal,
            hostUid: 'f4-legit/o-icefield'),
        HostLegit(id: 22, band: 9, row: 3, x0: 500, x1: 1000, hostName: '해협 동맹', hostColor: 0, era: true, seq: 0, legit: Schema4.legitRival, hostUid: ''),
      ]);
      // 띠 비트: 두 단 띠는 sub 22 ~ 23 = 1.
      expect(Schema4.leaderLanesOf(t.bandSub[0]), 2);
      expect(Schema4.leaderLanesOf(t.bandSub[1]), 1);
      // 받은 목록은 바꿀 수 없다.
      expect(() => Schema4.cellLegits(t).add(Schema4.cellLegits(t).first), throwsUnsupportedError);
      expect(() => Schema4.hostLegits(t).add(Schema4.hostLegits(t).first), throwsUnsupportedError);
    });

    test('구역 57 · 58이 없는 타일은 빈 목록 · 0으로 온 c · d는 −1(모름)', () {
      final none = Tile.decode((TileBuilder(level: 9, x: 0, chunk: 0)..band(7, 0, 0, 4000, '솔바람국')).build());
      expect(Schema4.cellLegits(none), isEmpty);
      expect(Schema4.hostLegits(none), isEmpty);
      final zero = Tile.decode((TileBuilder(level: 9, x: 0, chunk: 0)
            ..item(57, 1, 0, 0, 10, ref: 7)
            ..item(58, 2, 0, 0, 10, ref: 7))
          .build());
      expect(Schema4.cellLegits(zero).single, const CellLegit(id: 1, band: 7, row: 0, x0: 0, x1: 10, kind: 0, lane: 0, seq: -1, legit: -1));
      expect(Schema4.hostLegits(zero).single,
          const HostLegit(id: 2, band: 7, row: 0, x0: 0, x1: 10, hostName: '', hostColor: 0, era: false, seq: 0, legit: -1, hostUid: ''));
    });
  });
}
