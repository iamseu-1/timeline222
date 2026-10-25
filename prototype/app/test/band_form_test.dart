import 'dart:io';

import 'package:archive_prototype/scene/band_form.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 띠의 form(스키마 4 — 값은 계약 6-1 가의 비트 표 · 타일 띠 구역의 열 10은 계약 5절 띠 행(엔진 tile.rs와 같은 규칙) — 진짜 엔진 대조
// schema4_real_engine_test가 지킴)을 읽고 푸는 검사. 여기서는 엔진 없이 손으로 짠 타일(TileBuilder — form≠0인 띠가 있을 때만 11열이라는
// 계약 5절 규칙의 거울)과 옛 고정 타일로 본다.
// 진짜 엔진 답과의 대조는 schema4_real_engine_test(과제 8 걸음 5).

/// 군벌(종류 7) · 봉국(관계 2) · 대립(정통성 1) · 중요도 3 — bands.mjs formOf와 같은 셈으로 짠 값.
const warlordFief = (7 + 1) | (2 << 5) | ((1 + 1) << 10) | ((3 + 1) << 13);

/// 국가(종류 0)만 적힌 값 — 관계 · 정통성 · 중요도는 비움.
const plainState = 0 + 1;

void main() {
  group('비트 풀기', () {
    test('0은 모두 모름 · 없음 · 비움', () {
      expect(BandForm.parts(0), (type: -1, relation: 0, legit: -1, importance: -1));
      expect((BandForm.typeId(-1), BandForm.relationId(0), BandForm.legitId(-1)), ('', '', ''));
    });

    test('군벌 · 봉국 · 대립 · 중요도 3', () {
      expect(warlordFief, 34888);
      expect(BandForm.parts(warlordFief), (type: 7, relation: 2, legit: 1, importance: 3));
      expect((BandForm.typeOf(warlordFief), BandForm.relationOf(warlordFief), BandForm.legitOf(warlordFief),
          BandForm.importanceOf(warlordFief)), (7, 2, 1, 3), reason: '하나씩 푼 것과 parts가 같다');
      expect(
        (BandForm.typeId(7), BandForm.relationId(2), BandForm.legitId(1)),
        ('warlord', 'fief', 'rival'),
      );
    });

    test('하나만 적힌 값은 나머지가 비어 있다', () {
      expect(BandForm.parts(plainState), (type: 0, relation: 0, legit: -1, importance: -1));
      expect(BandForm.typeId(0), 'state');
      expect(BandForm.parts(4 << 13), (type: -1, relation: 0, legit: -1, importance: 3), reason: '중요도만');
      expect(BandForm.parts(1 << 10), (type: -1, relation: 0, legit: 0, importance: -1), reason: '정통만');
      expect(BandForm.parts(1 << 13), (type: -1, relation: 0, legit: -1, importance: 0), reason: '중요도 0은 비움과 다르다');
    });

    test('뜻이 있는 가장 큰 값 — 사람 · 공동 통치 · 주장 · 중요도 3', () {
      const top = (18 + 1) | (17 << 5) | ((5 + 1) << 10) | ((3 + 1) << 13);
      expect(BandForm.parts(top), (type: 18, relation: 17, legit: 5, importance: 3));
      expect((BandForm.typeId(18), BandForm.relationId(17), BandForm.legitId(5)), ('person', '', 'claim'),
          reason: '공동 통치(17)는 자리만 있고 관계 id가 아직 없다');
      expect((BandForm.relationId(14), BandForm.relationId(15), BandForm.relationId(16)), ('nominal', 'member', 'union'));
    });

    test('비트가 모두 선 값은 번호는 그대로, id는 표 밖이라 빈 글', () {
      expect(BandForm.parts(0xffff), (type: 30, relation: 31, legit: 6, importance: 6));
      expect((BandForm.typeId(30), BandForm.relationId(31), BandForm.legitId(6)), ('', '', ''));
    });

    test('16비트 위는 무시한다', () {
      expect(BandForm.parts(0xabcd0000 | warlordFief), BandForm.parts(warlordFief));
      expect(BandForm.parts(0xffff0000), BandForm.parts(0));
    });

    test('번호표는 bands.mjs의 TYPE_NO · REL_NO · STATUS_NO와 같다', () {
      final src = File('../scripts/export/bands.mjs').readAsStringSync();
      Map<String, int> table(String name) {
        final body = RegExp('$name = \\{([^}]*)\\}').firstMatch(src)!.group(1)!;
        return {for (final m in RegExp(r'(\w+): (\d+)').allMatches(body)) m.group(1)!: int.parse(m.group(2)!)};
      }

      final types = table('TYPE_NO'), rels = table('REL_NO'), status = table('STATUS_NO');
      expect(types.length, BandForm.types.length);
      types.forEach((id, n) => expect(BandForm.types[n], id, reason: '종류 $n'));
      expect(rels.length, 13, reason: '띠에 싣는 관계는 옛 종속 kind 열셋');
      rels.forEach((id, n) => expect(BandForm.relations[n], id, reason: '관계 $n'));
      expect(BandForm.relations.length, 18, reason: '0 없음 + 1 ~ 17');
      expect(status.length, BandForm.legits.length);
      status.forEach((id, n) => expect(BandForm.legits[n - 1], id, reason: '정통성 번호 + 1 = $n'));
    });
  });

  group('타일의 띠 form 열', () {
    test('form≠0인 띠가 있으면 띠 구역이 11열이고 form을 제자리에서 읽는다', () {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(7, 0, 0, 1000, '솔바람국', look: 4, tag: '군벌', sub: 3, form: warlordFief)
        ..band(8, 1, 200, 900, '바탕 문화', look: 17, tag: '문화', sub: 5);
      final t = Tile.decode(b.build());
      expect(t.section(Tile.secBand).columns, 11);
      expect(t.bandCount, 2);
      expect(t.bandForm, [warlordFief, 0], reason: '그림 띠(form 0)는 모름');
      expect((t.bandLook[0], t.text(t.bandTag[0]), t.bandSub[0]), (4, '군벌', 3), reason: 'look · tag · sub는 제자리');
      expect((t.bandLook[1], t.text(t.bandTag[1]), t.bandSub[1]), (17, '문화', 5));
      expect((t.bandId[1], t.bandRow[1], t.bandX0[1], t.bandX1[1]), (8, 1, 200, 900));
      expect(t.text(t.bandName[0]), '솔바람국');
      expect(BandForm.parts(t.bandForm[0]), (type: 7, relation: 2, legit: 1, importance: 3));
      expect(BandForm.parts(t.bandForm[1]).type, -1);
    });

    test('form이 모두 0이면 지금처럼 10열이고 bandForm은 띠 수만큼의 0이다', () {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, 0, 500, '가람국', look: 1)
        ..band(2, 0, 500, 900, '나루국')
        ..band(3, 2, 100, 300, '다솜국');
      final t = Tile.decode(b.build());
      expect(t.section(Tile.secBand).columns, 10);
      expect(t.bandForm, [0, 0, 0]);
      expect(t.bandLook[0], 1);
    });

    test('옛 고정 타일은 form이 모두 0이고 띠 구역은 10열 그대로다', () {
      final t = Tile.decode(File('test/fixtures/tile-100k-L9-x0-c0.bin').readAsBytesSync());
      expect(t.section(Tile.secBand).columns, 10);
      expect(t.bandForm.length, t.bandCount);
      expect(t.bandCount, 19);
      expect(t.bandForm.every((v) => v == 0), isTrue);
      expect(t.bandLook[3], 1, reason: '옛 열은 그대로 읽힌다');
    });

    test('모르는 구역(54 ~ 56)이 끼어도 띠의 form을 제자리에서 읽는다', () {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(7, 0, 0, 1000, '솔바람국', form: warlordFief)
        ..band(9, 1, 0, 800, '물안개국', form: plainState)
        ..cell(70, 0, 0, 400, '첫 임금', kind: 9, lane: 1, style: 1 << 27)
        ..event(500, 0, 300, '어느 날의 일', band: 7)
        ..item(54, 1, 0, 0, 1000, ref: 7, name: '나루국/재상', a: 2, text2: 'naru')
        ..item(55, 2, 0, 0, 1000, ref: 7, name: '셋째 직위', a: 9, b: 2)
        ..item(56, 3, 1, 100, 600, ref: 9, name: '솔바람국', color: 0x123456);
      final t = Tile.decode(b.build());
      expect(t.sectionKinds, [1, 2, 3, 54, 55, 56]);
      expect(t.section(Tile.secBand).columns, 11);
      expect(t.bandForm, [warlordFief, plainState]);
      expect(BandForm.typeId(BandForm.typeOf(t.bandForm[1])), 'state');
      expect((t.cellId[0], t.cellKindOf(0), t.cellLane[0], t.cellStyle[0]), (70, 9, 1, 1 << 27), reason: '띠 뒤의 칸도 제자리');
      expect((t.eventId[0], t.eventBand[0]), (500, 7));
      final borrowed = t.section(54);
      expect((borrowed.count, borrowed.columns), (1, 14));
      expect((t.text(borrowed.u(Tile.itemName)[0]), borrowed.u(Tile.itemRef)[0], t.text(borrowed.u(Tile.itemText2)[0])),
          ('나루국/재상', 7, 'naru'));
      expect(t.section(56).u(Tile.itemColor)[0], 0x123456);
    });
  });
}
