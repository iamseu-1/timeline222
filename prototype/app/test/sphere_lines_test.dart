import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';
import 'support/painter_fixture.dart' as painter;

// 문화권 단위 줄(스키마 4 — 계약 1-1의 표 sphere_lines → layout 답 맨 위 sphereLines)을 앱이 받는지 보는 검사.
// 4단계 과제 3 · 4부터 펼친 문화권의 시대(kind 2) · 주기 줄(kind 3) · 사람 띠(kind 1)는 머리 단 밑에 쌓인다(test/sphere_layout_test.dart · sphere_rows_test.dart) —
// 여기서는 받기와, 쌓기에 들지 않는 줄(접힌 문화권의 줄 · 문화권 밖 답)이 쌓은 자리를 바꾸지 않는 것만 본다.
// 엔진은 아직 이 열쇠를 싣지 않으므로 손으로 쓴 답(fold_rows.dart의 twoTrackLayout에 sphereLines를 얹은 것)으로 본다.
// 원소의 꼴은 내보내기 JS(export/persons.mjs · export/axis.mjs)가 싣는 그대로 { kind, sphere, start, end, name, uid, color, data, pack }다.

/// 사람 띠(왕관 둘) · 문화권 시대 · 주기 줄 — 셋 다 data는 JSON 글(엔진 표의 TEXT 열과 같은 꼴).
List<Map<String, dynamic>> threeLines() => [
  {
    'kind': 1, 'sphere': 'east-asia', 'start': 1200000, 'end': 5400000, 'name': '별여울 임금', 'uid': 'fig-star', 'color': 0,
    'data': '[{"uid":"band-star","cell":0},{"uid":"band-sol","cell":3}]', 'pack': 1,
  },
  {'kind': 2, 'sphere': 'east-asia', 'start': 0, 'end': 9000000, 'name': '첫째 시대', 'uid': 'epoch-first', 'color': 0xc8b193, 'data': '', 'pack': 1},
  {
    'kind': 3, 'sphere': 'steppe', 'start': 0, 'end': 0, 'name': '띠', 'uid': '', 'color': 0,
    'data': '{"names":["쥐","소","범"],"start":4,"label":"띠"}', 'pack': 2,
  },
];

/// twoTrackLayout()에 sphereLines를 얹은 답.
Map<String, dynamic> withLines([List<Object?>? lines]) => twoTrackLayout()..['sphereLines'] = lines ?? threeLines();

SceneLayout build(Map<String, dynamic> json) => SceneLayout.fromJson(json)..reduceMotion = true;

/// 쌓은 자리 — [줄마다 위 자리, 트랙마다 위 자리, 전체 높이](목록이라 expect가 속까지 견준다).
List<Object> placed(SceneLayout l) =>
    [[for (int r = 0; r < l.rowCount; r++) l.rowTop(r)], [for (int t = 0; t < l.tracks.length; t++) l.trackTop(t)], l.totalHeight];

void main() {
  // 이 파일의 손셈 자리는 민족 머리 줄이 없는 쌓기(0.1.0) 기준이다 — 머리 줄(0.1.1 감독 고름 나 · 트랙 첫 줄 묶음마다 +14)의 쌓기는 gutter_test가 본다.
  setUp(() => PaintPick.people = false);
  tearDown(PaintPick.reset);
  group('세 갈래 읽기', () {
    test('사람 띠 — data의 왕관 둘을 (uid, cell)로 푼다', () {
      final l = build(withLines());
      expect(l.sphereLines, hasLength(3));
      final p = l.sphereLines[0];
      expect(SphereLine.person, 1);
      expect((p.kind, p.sphere, p.start, p.end, p.name, p.uid, p.color, p.pack), (1, 'east-asia', 1200000, 5400000, '별여울 임금', 'fig-star', 0, 1));
      expect(p.crowns, [(uid: 'band-star', cell: 0), (uid: 'band-sol', cell: 3)]);
      expect(p.decoded, isA<List>());
    });

    test('문화권 시대 — uid · 색 · 구간을 받고, data가 비어 decoded는 null · 왕관은 없다', () {
      final e = build(withLines()).sphereLines[1];
      expect(SphereLine.epoch, 2);
      expect((e.kind, e.sphere, e.start, e.end, e.name, e.uid, e.color, e.pack), (2, 'east-asia', 0, 9000000, '첫째 시대', 'epoch-first', 0xc8b193, 1));
      expect(e.data, '');
      expect(e.decoded, isNull);
      expect(e.crowns, isEmpty);
    });

    test('주기 줄 — data {names, start, label}을 풀고, 구간은 0 ~ 0이다', () {
      final c = build(withLines()).sphereLines[2];
      expect(SphereLine.cycle, 3);
      expect((c.kind, c.sphere, c.start, c.end, c.name, c.pack), (3, 'steppe', 0, 0, '띠', 2));
      expect(c.decoded, {'names': ['쥐', '소', '범'], 'start': 4, 'label': '띠'});
      expect(c.crowns, isEmpty, reason: '왕관은 사람 띠만 — 주기 줄의 data는 목록이 아니다');
    });
  });

  group('옛 답 · 손으로 쓴 답', () {
    test('sphereLines 열쇠가 없는 답은 빈 목록으로 읽는다(P3-18의 칸 없는 답 규칙)', () {
      expect(build(twoTrackLayout()).sphereLines, isEmpty);
      expect(painter.layout().sphereLines, isEmpty);
      expect(build(twoTrackLayout()..['sphereLines'] = null).sphereLines, isEmpty, reason: 'null도 빈 목록');
    });

    test('문화권이 없는 답에 sphereLines를 더해도 쌓은 자리가 같다(1배 같음 — 머리 단이 없으면 줄을 쌓을 자리도 없다)', () {
      final before = placed(build(twoTrackLayout()));
      final after = placed(build(withLines()));
      expect(after, before);
      expect(before[2], 210, reason: 'fold_rows.dart가 적은 전체 높이 그대로');
    });

    test('문화권이 있는 답에 접힌 문화권의 줄만 더하면 머리 단 · 접힘이 같고, 펼친 문화권의 사람 띠 한 줄은 18 · 시대 줄까지는 32 내린다(4단계 과제 3 · 4)', () {
      Map<String, dynamic> sphered([List<Object?>? lines]) {
        final json = lines == null ? twoTrackLayout() : withLines(lines);
        final tracks = json['tracks'] as List;
        (tracks[0] as Map)['sphere'] = 'east-asia';
        (tracks[1] as Map)['sphere'] = 'steppe';
        json['spheres'] = [
          {'id': 'east-asia', 'name': '동아시아', 'count': 12, 'default': true},
          {'id': 'steppe', 'name': '초원', 'count': 8},
        ];
        return json;
      }

      // 초원(접힘)의 주기 줄: 쌓기는 그대로(접힌 문화권은 머리 단뿐).
      final a = build(sphered()), b = build(sphered([threeLines()[2]]));
      expect(placed(b), placed(a));
      expect(b.viewState.foldedSpheres, a.viewState.foldedSpheres);
      expect([b.sphereHeadTop(0), b.sphereHeadTop(1)], [a.sphereHeadTop(0), a.sphereHeadTop(1)]);
      expect([b.sphereHeadHeight(0), b.sphereHeadHeight(1)], [20, 20]);
      // 사람 띠(동아시아 — 펼침)를 더하면 사람 띠 한 줄 16 + 2만큼 동아시아 트랙이 내려선다(과제 4 걸음 1).
      final p = build(sphered([threeLines()[0], threeLines()[2]]));
      expect(p.sphereHeadHeight(0), 38);
      expect(p.trackTop(0), a.trackTop(0) + 18);
      // 셋 다(동아시아 시대 줄 · 사람 띠): 동아시아 트랙이 14 + 16 + 2만큼 내려서고 초원 머리 단도 그만큼 밀린다. 접힘은 그대로.
      final c = build(sphered(threeLines()));
      expect(c.viewState.foldedSpheres, a.viewState.foldedSpheres);
      expect(c.sphereHeadTop(0), a.sphereHeadTop(0));
      expect(c.sphereHeadHeight(0), 52);
      expect(c.trackTop(0), a.trackTop(0) + 32);
      expect(c.sphereHeadTop(1), a.sphereHeadTop(1) + 32);
      expect(c.totalHeight, a.totalHeight + 32);
    });
  });

  group('너그럽게 읽기', () {
    test('빠진 열쇠는 0 · 빈 글, 수는 정수로', () {
      final l = build(withLines([
        <String, dynamic>{},
        {'kind': 2.0, 'start': 10.0, 'end': 20, 'sphere': 'east-asia'},
      ]));
      final empty = l.sphereLines[0];
      expect((empty.kind, empty.sphere, empty.start, empty.end, empty.name, empty.uid, empty.color, empty.data, empty.pack), (0, '', 0, 0, '', '', 0, '', 0));
      expect(empty.decoded, isNull);
      expect(empty.crowns, isEmpty);
      final half = l.sphereLines[1];
      expect((half.kind, half.start, half.end, half.sphere, half.name), (2, 10, 20, 'east-asia', ''));
    });

    test('data가 깨진 글이면 decoded는 null이고 왕관은 빈 목록', () {
      final p = SphereLine.fromJson({'kind': 1, 'data': '[{"uid":"band-star",'});
      expect(p.data, '[{"uid":"band-star",');
      expect(p.decoded, isNull);
      expect(p.crowns, isEmpty);
    });

    test('data가 객체 · 목록이면 JSON 글로 바꿔 담는다', () {
      final l = build(withLines([
        {'kind': 3, 'sphere': 'steppe', 'data': {'era': '갑자', 'from': 4, 'step': 1, 'label': '갑자'}},
        {'kind': 1, 'sphere': 'east-asia', 'data': [{'uid': 'band-star', 'cell': 2}, {'uid': 'band-sol', 'cell': 0}]},
      ]));
      final cycle = l.sphereLines[0], person = l.sphereLines[1];
      expect(cycle.data, '{"era":"갑자","from":4,"step":1,"label":"갑자"}');
      expect(cycle.decoded, {'era': '갑자', 'from': 4, 'step': 1, 'label': '갑자'});
      expect(person.data, '[{"uid":"band-star","cell":2},{"uid":"band-sol","cell":0}]');
      expect(person.crowns, [(uid: 'band-star', cell: 2), (uid: 'band-sol', cell: 0)]);
    });

    test('왕관 목록의 원소가 꼴이 달라도 버티고, 객체가 아닌 원소는 건너뛴다', () {
      final p = SphereLine.fromJson({'kind': 1, 'data': '[{"uid":"band-star"},{"cell":4.0},7,"x",{"uid":5,"cell":"1"}]'});
      expect(p.crowns, [(uid: 'band-star', cell: 0), (uid: '', cell: 4), (uid: '', cell: 0)]);
    });

    test('원소가 객체가 아니어도 자리를 지켜 빈 줄로 담는다(차례가 곧 줄의 번호)', () {
      final l = build(withLines([7, threeLines()[1]]));
      expect([for (final x in l.sphereLines) x.kind], [0, 2]);
    });
  });

  test('모르는 kind(예: 9)도 버리지 않고 그대로 담는다 — 무엇을 그릴지는 4단계', () {
    final l = build(withLines([
      ...threeLines(),
      {'kind': 9, 'sphere': 'steppe', 'start': 30, 'end': 40, 'name': '새 갈래', 'uid': 'u-9', 'color': 0x123456, 'data': '{"x":1}', 'pack': 2},
    ]));
    expect([for (final x in l.sphereLines) x.kind], [1, 2, 3, 9]);
    final unknown = l.sphereLines[3];
    expect((unknown.sphere, unknown.start, unknown.end, unknown.name, unknown.uid, unknown.color, unknown.pack), ('steppe', 30, 40, '새 갈래', 'u-9', 0x123456, 2));
    expect(unknown.decoded, {'x': 1});
    expect(unknown.crowns, isEmpty);
  });

  group('뼈대 갈아 끼우기(replaceWith)', () {
    test('새 답의 목록만 남는다 — 옛 원소가 남지 않는다', () {
      final l = build(withLines());
      final kept = l.sphereLines;
      l.replaceWith(SceneLayout.fromJson(withLines([threeLines()[2]])));
      expect(identical(l.sphereLines, kept), isTrue, reason: '제자리에서 바꾼다 — 쥔 목록이 그대로');
      expect([for (final x in l.sphereLines) (x.kind, x.sphere)], [(3, 'steppe')]);
    });

    test('열쇠가 없는 새 답으로 갈아 끼우면 빈 목록이 된다', () {
      final l = build(withLines());
      l.replaceWith(SceneLayout.fromJson(twoTrackLayout()));
      expect(l.sphereLines, isEmpty);
    });

    test('빈 목록에서 새 답으로 갈아 끼우면 차례대로 채운다', () {
      final l = build(twoTrackLayout());
      l.replaceWith(SceneLayout.fromJson(withLines()));
      expect([for (final x in l.sphereLines) x.kind], [1, 2, 3]);
      expect(l.sphereLines.first.crowns, hasLength(2));
    });
  });
}
