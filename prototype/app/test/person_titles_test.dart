import 'dart:convert';

import 'package:archive_prototype/ui/person_titles.dart';
import 'package:flutter_test/flutter_test.dart';

// 인물 항목 기록의 x_titles(스키마 4 — 계약 1-1) 풀개 검사(리메이크 4단계 과제 1 걸음 1).
// 계약의 꼴은 내보내기 JS(export/entities.mjs)가 견본 등불 연대기에서 낸 기록 그대로 옮겨 적었다(2026-10-25 — 인물 41명에 칭호가 있음).
// 진짜 엔진의 답(archive-tool query `{"op":"entity"}`의 json 글)에도 같은 값으로 실림을 걸음 1에서 확인했다(계획 문서 과제 1 걸음 1 덧글).

/// 등불 연대기 `lantern-chronicle/f-luna`의 기록에서 뗀 것(내보내기 그대로).
const _luna = '{"name":"루나","x_titles":[{"uid":"lantern-chronicle/p-cheong-priest","cell":0,"office":"지도자",'
    '"name":"청림 신관국","start":-1151301600,"end":-1082930400,"rank":""}]}';

void main() {
  group('계약의 꼴', () {
    test('지도자 칸 하나 — 칸 참조 leader:0', () {
      final titles = PersonTitles.of(jsonDecode(_luna) as Map);
      expect(titles, hasLength(1));
      final t = titles.single;
      expect(t, const PersonTitle(
        uid: 'lantern-chronicle/p-cheong-priest', cell: 0, office: TitleOffice.leader, name: '청림 신관국',
        start: -1151301600, end: -1082930400,
      ));
      expect(t.cellRef, 'leader:0');
      expect(t.rank, '');
    });

    test('내각 칸 · 지위 · 받은 차례 그대로', () {
      final titles = PersonTitles.read([
        {'uid': 'p/a', 'cell': 2, 'office': '내각', 'name': '가람국', 'start': 10, 'end': 20, 'rank': '재상'},
        {'uid': 'p/b', 'cell': 5, 'office': '지도자', 'name': '나루국', 'start': 5, 'end': 30, 'rank': '왕'},
      ]);
      expect([for (final t in titles) t.cellRef], ['cabinet:2', 'leader:5'], reason: '시작 차례로 다시 늘어놓지 않는다(짓는 쪽의 몫)');
      expect([for (final t in titles) t.rank], ['재상', '왕']);
      expect(titles.first.office, TitleOffice.cabinet);
    });

    test('칭호가 없는 인물 · 기록이 없음 → 빈 목록', () {
      expect(PersonTitles.of({'name': '누구'}), isEmpty);
      expect(PersonTitles.of(null), isEmpty);
      expect(PersonTitles.read(null), isEmpty);
      expect(PersonTitles.read(const []), isEmpty);
    });

    test('목록을 담은 JSON 글도 읽는다', () {
      final inner = jsonEncode((jsonDecode(_luna) as Map)['x_titles']);
      expect(PersonTitles.read(inner), PersonTitles.of(jsonDecode(_luna) as Map));
      expect(PersonTitles.read(''), isEmpty);
      expect(PersonTitles.read('{깨진'), isEmpty);
      expect(PersonTitles.read('{"uid":"p/a"}'), isEmpty, reason: '목록이 아닌 JSON');
    });
  });

  group('너그럽게 받기', () {
    test('수가 글 · 소수로 와도 읽는다', () {
      final t = PersonTitles.read([
        {'uid': 'p/a', 'cell': '3', 'office': '지도자', 'name': '가람국', 'start': '-120', 'end': 99.6},
      ]).single;
      expect((t.cell, t.start, t.end, t.cellRef), (3, -120, 100, 'leader:3'));
    });

    test('셈하지 못한 때(JS NaN → null) · 빠진 때는 null', () {
      final t = PersonTitles.read([
        {'uid': 'p/a', 'cell': 0, 'office': '지도자', 'name': '가람국', 'start': null},
        {'uid': 'p/b', 'cell': 1, 'office': '지도자', 'name': '나루국', 'start': double.nan, 'end': double.infinity},
      ]);
      expect([for (final x in t) (x.start, x.end)], [(null, null), (null, null)]);
    });

    test('직위 줄을 모르거나 순번이 없으면 칸 참조가 없다', () {
      final t = PersonTitles.read([
        {'uid': 'p/a', 'cell': 0, 'office': '섭정', 'name': '가람국'},
        {'uid': 'p/b', 'office': '지도자', 'name': '나루국'},
        {'uid': 'p/c', 'cell': 'x', 'office': 'cabinet', 'name': '다솜국'},
        {'uid': 'p/d', 'cell': 1, 'office': 'leader', 'name': '라온국'},
      ]);
      expect([for (final x in t) x.office], [TitleOffice.other, TitleOffice.leader, TitleOffice.cabinet, TitleOffice.leader]);
      expect([for (final x in t) x.cell], [0, -1, -1, 1]);
      expect([for (final x in t) x.cellRef], [null, null, null, 'leader:1']);
    });

    test('표가 아닌 원소 · 객체 uid와 이름이 모두 없는 원소만 버린다', () {
      final t = PersonTitles.read([
        'leader:0',
        7,
        null,
        {'cell': 0, 'office': '지도자'},
        {'uid': '', 'name': '', 'cell': 1},
        {'name': 12, 'office': '지도자', 'cell': 0},
        {'uid': 'p/e'},
      ]);
      expect(t, hasLength(2));
      expect((t[0].uid, t[0].name, t[0].cellRef), ('', '12', 'leader:0'), reason: '이름만 있어도 보일 수 있다');
      expect((t[1].uid, t[1].name, t[1].cell, t[1].office, t[1].rank), ('p/e', '', -1, TitleOffice.other, ''));
    });

    test('읽은 목록은 고칠 수 없다', () {
      final t = PersonTitles.of(jsonDecode(_luna) as Map);
      expect(() => t.add(t.first), throwsUnsupportedError);
    });
  });
}
