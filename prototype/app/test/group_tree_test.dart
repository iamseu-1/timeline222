import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/ruler.dart' show minuteOfYear;
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/app_shell.dart';
import 'package:archive_prototype/shell/detail_panel.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/mag_pill.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/shell/zoom_buttons.dart';
import 'package:archive_prototype/timeline_view.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_group.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/group_tree.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 단체 계보 창 · 법의 내력 · 의석 막대(설계 D5 결정 4 A · 7 A — docs/설계-10건/7-8-단체와-렌즈.md 9절)의 새 앱 몫.
// 고정 자료 test/fixtures/d5-windows.json은 견본 sample-groups + sample-lens를 내보내기(prototype/scripts/export/entities.mjs의
// groupWindowRefs — 웹 js/group-tree.js의 HT.groupTreeLayout을 그대로 부른 셈)로 낸 항목 기록이다. 이름은 모두 가상이다.

final _store = <String, Map<String, dynamic>>{
  for (final one in jsonDecode(File('test/fixtures/d5-windows.json').readAsStringSync()) as List) (one as Map)['uid'] as String: one.cast<String, dynamic>(),
};

Map<String, dynamic> rec(String uid) => (jsonDecode(_store[uid]!['json'] as String) as Map).cast<String, dynamic>();

const kap = 'sample-groups/gr-kap', east = 'sample-groups/gr-east', old = 'sample-groups/gr-old', newer = 'sample-groups/gr-new';

/// 항목 기록 + `ids_of`에 답하는 검사용 길. 보기는 740 ~ 1000년. [store]를 주면 그 기록들로(덧 그림 · 갈래 검사의 고친 나무).
AppBus makeBus({Map<String, Map<String, dynamic>>? store}) {
  final rows = store ?? _store;
  final controller = TimelineController()
    ..resize(1920, 1000)
    ..setExtent(minuteOfYear(0), minuteOfYear(2000))
    ..showRange(minuteOfYear(740), minuteOfYear(1000));
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '단체 견본', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('계보 창 검사는 타일을 읽지 않는다'),
  );
  return AppBus(
    ask: (query) async {
      switch (query['op']) {
        case 'entity':
          final row = rows[query['uid']];
          if (row == null) throw StateError('없는 항목');
          return row;
        case 'ids_of':
          return {'bands': const [], 'events': const []};
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
}

/// 연표 자리(1920×1000)에 계보 창 층만 띄운다. [detail]을 주면 왼쪽에 상세 창 뼈대도.
Future<void> mount(WidgetTester tester, AppBus bus, {bool layer = true, Widget? detail, bool keys = false}) async {
  tester.view.physicalSize = const Size(1920 + 380, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget body = Row(
    children: [
      SizedBox(width: 380, child: detail ?? const SizedBox()),
      SizedBox(
        width: 1920,
        child: Stack(children: [if (layer) Positioned.fill(child: GroupTreeLayer(bus: bus))]),
      ),
    ],
  );
  if (keys) body = ShellKeys(bus: bus, windowOpen: () => bus.selection.value != null, child: body);
  await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Ui.bg, body: body)));
}

GroupTreeLayerState layerOf(WidgetTester tester) => tester.state<GroupTreeLayerState>(find.byType(GroupTreeLayer));

/// 나무 그림(CustomPaint)의 왼쪽 위 — 막대 자리(그림 영역 안 px)를 화면 자리로 옮길 때.
Offset plotOrigin(WidgetTester tester) => tester.getTopLeft(find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null && w.painter.runtimeType.toString() == '_GroupTreePainter'));

GroupTreeGeometry geoOf(WidgetTester tester) {
  final s = layerOf(tester);
  return GroupTreeGeometry.of(s.data!, s.xOf, width: s.plotOf().width);
}

/// 나무 그림의 그리개(RenderCustomPaint) — 칠한 것을 `paints`로 본다.
RenderObject treePaint(WidgetTester tester) => tester.renderObject(find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null && w.painter.runtimeType.toString() == '_GroupTreePainter'));

/// 갑 왕국 나무를 고친 기록들 — 옛 무리 → 남쪽 무리를 '방식 미상'의 안에서 갈라짐으로(남쪽 무리가 옛 무리가 있던 830년에 시작).
/// 고정 자료에는 그 갈래가 없어서, 열쇠표 · 아랫변 매듭 · 점 실을 실제 창(검사 · 1배 덧 그림)에서 보려고 고친다.
Map<String, Map<String, dynamic>> unknownStore() {
  final json = rec(kap);
  final tree = (json['x_groupTree'] as Map).cast<String, dynamic>();
  final south = ((tree['nodes'] as List)[3] as Map).cast<String, dynamic>();
  south['span'] = [minuteOfYear(830).round(), (south['span'] as List)[1]];
  south['range'] = '830–870';
  south['when'] = '830년 ~ 870년';
  ((tree['edges'] as List)[2] as Map)
    ..['kind'] = 'unknown'
    ..remove('after');
  return {
    ..._store,
    kap: {..._store[kap]!, 'json': jsonEncode(json)},
  };
}

/// 갈래 다섯을 모두 담은 작은 나무(분 = 그림 px — x는 그대로): A(줄 0 · 100 ~ 400)에서 B(끝에서 갈라짐) · C(안에서 · 방식 미상) ·
/// D(안에서 · 적지 않음), B → E 이름 바꿈(같은 줄), C · D → F 합쳐짐(끝난 뒤).
GroupTreeData fiveKinds() {
  const c = Color(0xffa4b1b7);
  GroupTreeNode n(String name, int row, double lo, double hi) => GroupTreeNode(uid: name, name: name, color: c, row: row, lo: lo, hi: hi, range: '${lo.round()}–${hi.round()}');
  return GroupTreeData(
    holder: 'five',
    lo: 100,
    hi: 800,
    rows: 5,
    nodes: [n('A', 0, 100, 400), n('B', 1, 400, 600), n('C', 2, 250, 500), n('D', 3, 300, 500), n('E', 1, 600, 800), n('F', 4, 500, 700)],
    edges: const [
      GroupTreeEdge(from: 0, to: 1, kind: 'split', after: true, ev: 'ev-split'),
      GroupTreeEdge(from: 0, to: 2, kind: 'unknown'),
      GroupTreeEdge(from: 0, to: 3, kind: 'blank'),
      GroupTreeEdge(from: 1, to: 4, kind: 'rename', same: true, after: true),
      GroupTreeEdge(from: 2, to: 5, kind: 'merge', after: true, ev: 'ev-merge'),
      GroupTreeEdge(from: 3, to: 5, kind: 'merge', after: true, ev: 'ev-merge'),
    ],
  );
}

/// 앞에 칠하는 실 토막 · 매듭 · 마름모 · 열쇠표의 자리(글자 가림을 셀 때 — 세로 통로의 실은 꼬리표 뒤라 빼고).
List<Rect> frontMarks(GroupTreeGeometry geo) => [
  for (final t in geo.threads)
    for (final p in t.pieces)
      if (!p.vertical) Rect.fromPoints(p.a, p.b).inflate(t.width / 2).expandToInclude(p.control == null ? Rect.fromPoints(p.a, p.b) : Rect.fromPoints(p.control!, p.control!)),
  for (final k in geo.knots) Rect.fromCircle(center: k.at, radius: GroupTreeLook.knot),
  for (final b in geo.bars)
    if (b.diamond != null) Rect.fromCircle(center: b.diamond!, radius: SheetLook.diamondHalf),
  for (final k in geo.keys) ...[k.box, Rect.fromPoints(k.from, k.hole)],
];

/// 글자 가림 0 — 앞에 칠하는 실 · 매듭 · 마름모 · 열쇠표가 어느 꼬리표의 이름 · 해 글과도 겹치지 않는다.
/// 글 폭은 넉넉히 한 글자 = 글 크기(한글 · 숫자의 실제 폭보다 조금 넓게 — 검사 글꼴은 한글 폭을 재지 못함).
void expectNoCover(GroupTreeData d, GroupTreeGeometry geo) {
  double w(String t, TextStyle style) => t.length * style.fontSize!;
  final marks = frontMarks(geo);
  var labels = 0;
  for (var i = 0; i < d.nodes.length; i++) {
    final l = groupTagLabel(d.nodes[i], geo.bars[i], w);
    for (final r in [?l.nameRect, ?l.yearsRect]) {
      labels++;
      for (final m in marks) {
        expect(r.overlaps(m), isFalse, reason: '${d.nodes[i].name}의 글 $r와 $m');
      }
    }
  }
  expect(labels, greaterThan(0));
}

void main() {
  group('자료 · 자리 셈', () {
    final data = GroupTreeData.parse(kap, rec(kap)['x_groupTree'])!;

    test('나라 기록의 x_groupTree — 웹 HT.groupTreeLayout과 같은 줄 · 이음', () {
      expect(data.polityName, '갑 왕국');
      expect(data.rows, 6);
      expect([for (final n in data.nodes) '${n.name}@${n.row}'], ['옛 무리@0', '동쪽 무리@1', '서쪽 무리@2', '남쪽 무리@3', '새 무리@4', '검은 장막@5', '곧은 길 모임@4']);
      expect([for (final e in data.edges) '${data.nodes[e.from].name}→${data.nodes[e.to].name}:${e.kind}${e.same ? '=' : ''}'], [
        '옛 무리→동쪽 무리:split',
        '옛 무리→서쪽 무리:split',
        '옛 무리→남쪽 무리:blank',
        '서쪽 무리→새 무리:merge',
        '남쪽 무리→새 무리:merge',
        '새 무리→곧은 길 모임:rename=',
      ]);
      final e = data.nodes[data.indexOf(east)];
      expect(e.count, '집권 1번 · 연정 1번');
      expect([for (final s in e.segs) s.kind], [GroupSegKind.power, GroupSegKind.coal]);
      expect(e.tip, '동쪽 무리 · 붕당·파벌 · 842년 ~ 905년 · 집권 1번 · 연정 1번 — 누르면 연표에 조명 · 두 번 누르면 단체 창');
      expect(data.edges.first.ev, 'sample-groups/gr-e-split');
      expect(data.edges.first.tip, '갈라짐 — 옛 무리 → 동쪽 무리 · 842 · 누르면 그 사건');
      // 단체 기록은 같은 나무를 다시 싣지 않고 나라를 가리킨다.
      expect(groupTreeHolder(rec(east), east), kap);
      expect(groupTreeHolder(rec(kap), kap), kap);
      expect(groupTreeHolder(rec('sample-groups/gr-pact'), 'sample-groups/gr-pact'), isNull, reason: '연합(있던 나라 · 앞뒤 단체 없음)은 웹도 단추가 없다');
    });

    test('꼬리표 x는 연표와 같은 자리 · 들임 6(이름 바꿈 4) · 키 40 · 줄 간격 46 · 세로 실이 꼬리표를 가로지르지 않음 · 매듭 · 적지 않음은 옅은 실', () {
      final k = 1600 / (data.hi - data.lo);
      double x(double m) => (m - data.lo) * k;
      final geo = GroupTreeGeometry.of(data, x, width: 1700);
      // 앞선 단체가 없는 꼬리표(옛 무리 · 검은 장막)의 머리는 연표와 같은 x(화소로 반올림 — 들여 쓰지 않음)
      expect(geo.bars[0].x1, x(data.nodes[0].lo).roundToDouble());
      expect(geo.bars[5].x1, x(data.nodes[5].lo).roundToDouble());
      // 앞선 단체가 있으면 머리를 6 들임, 이름 바꿈으로 이어 쓰면 4 · 끝난 뒤 시작한 뒤 단체가 있는 끝은 6, 이름 바꿈으로 잇는 끝은 4
      expect(geo.bars[1].x1, (x(data.nodes[1].lo) + 6).roundToDouble());
      expect(geo.bars[6].x1, (x(data.nodes[6].lo) + 4).roundToDouble());
      expect(geo.bars[0].x2, (x(data.nodes[0].hi) - 6).roundToDouble());
      expect(geo.bars[4].x2, (x(data.nodes[4].hi) - 4).roundToDouble());
      expect(geo.bars[1].x2, x(data.nodes[1].hi).roundToDouble(), reason: '뒤가 없는 끝은 그대로');
      expect(geo.bars[6].row, geo.bars[4].row, reason: '이름 바꿈은 같은 줄에 이어 씀');
      // 키 40(머리 24 + 흰 층 16) · 줄 간격 46(사이 6) · 첫 줄 위 12 — 열쇠표가 없는 나무
      for (final b in geo.bars) {
        expect(b.rect.height, 40);
        expect(b.y, 12 + b.row * 46.0);
      }
      expect(geo.rowTops, [12, 58, 104, 150, 196, 242]);
      expect(geo.height, 242 + 40 + 12);
      // 세로 실은 사이 줄의 꼬리표 안을 지나지 않는다
      for (final t in geo.threads) {
        for (final p in t.pieces.where((p) => p.vertical)) {
          final y0 = p.a.dy < p.b.dy ? p.a.dy : p.b.dy, y1 = p.a.dy < p.b.dy ? p.b.dy : p.a.dy;
          for (final bar in geo.bars) {
            final crossing = bar.rect.bottom > y0 && bar.rect.top < y1 && p.a.dx > bar.x1 && p.a.dx < bar.x2;
            expect(crossing, isFalse, reason: '세로 실 x=${p.a.dx}가 줄 ${bar.row}의 꼬리표를 가로지름');
          }
        }
      }
      // 꼬리 마름모는 실이 떠나는 꼬리표에만(옛 무리 · 서쪽 · 남쪽 · 새 무리)
      expect([for (final b in geo.bars) b.diamond != null], [true, false, true, true, true, false, false]);
      expect(geo.knots, hasLength(1), reason: '합쳐짐 — 서쪽 · 남쪽이 같은 통로(870년)에서 모이는 매듭 하나');
      expect(geo.threads.where((t) => t.style == GroupLineStyle.faint), hasLength(1), reason: '방식을 적지 않은 갈래 하나');
      expect(geo.threads.where((t) => t.style == GroupLineStyle.dotted), isEmpty);
      expect(geo.keys, isEmpty);
      expect(geo.hits.where((h) => h.edge.ev.isNotEmpty), hasLength(3), reason: '사건이 있는 이음(갈라짐 하나 · 합쳐짐 둘)만 누름');
      expectNoCover(data, geo);
    });

    test('실 갈래 다섯의 꼴 — 끝에서 갈라짐 · 안에서 갈라짐(매듭) · 합쳐짐(매듭에서 모임) · 이름 바꿈(같은 줄) · 방식 미상(점 실 + 열쇠표) · 적지 않음(옅은 실)', () {
      final d = fiveKinds();
      final geo = GroupTreeGeometry.of(d, (m) => m, width: 1000, keyWidth: 36);
      final a = geo.bars[0], b = geo.bars[1], c = geo.bars[2], dd = geo.bars[3], e = geo.bars[4], f = geo.bars[5];
      // 열쇠표가 달린 줄(C — 줄 2)부터 아래는 14 더 내려감
      expect(geo.rowTops, [12, 58, 118, 164, 210]);
      expect([a.x1, a.x2, b.x1, b.x2, e.x1, c.x1, c.x2, f.x1], [100, 394, 406, 596, 604, 256, 494, 506]);
      List<Offset> pts(int edge) => geo.hits.firstWhere((h) => identical(h.edge, d.edges[edge])).points;
      GroupThread threadOf(Offset start) => geo.threads.firstWhere((t) => t.points.first == start);
      // 끝에서 갈라짐: A의 꼬리 마름모(오른쪽 7.5 · 위 6.5) → A 끝 6 밖의 통로 → 세로 → B의 구멍 테(구멍 왼쪽 2.5)
      expect(a.diamond, const Offset(386.5, 18.5));
      expect(pts(0), const [Offset(386.5, 18.5), Offset(400.5, 18.5), Offset(400.5, 64.5), Offset(413, 64.5)]);
      final split = threadOf(const Offset(386.5, 18.5));
      expect(split.style, GroupLineStyle.solid);
      expect(split.width, 1.5);
      expect(split.color, SheetLook.ink45);
      expect([for (final p in split.pieces) p.control], [null, const Offset(400.5, 18.5), null, const Offset(400.5, 64.5), null], reason: '꺾이는 곳 둘은 굽음 6');
      expect(split.pieces[1].b, const Offset(400.5, 24.5));
      expect(split.pieces[2].vertical, isTrue, reason: '통로의 세로 실(꼬리표 뒤에 칠함)');
      // 안에서 갈라짐(방식 미상): A 아랫변(반 픽셀)의 매듭에서 C 왼쪽 6으로 곧게 내려가 굽어 C의 구멍으로 · 점 실(3.5마다)
      expect(pts(1), const [Offset(250.5, 51.5), Offset(250.5, 124.5), Offset(263, 124.5)]);
      final unknown = threadOf(const Offset(250.5, 51.5));
      expect(unknown.style, GroupLineStyle.dotted);
      final dots = unknown.dots;
      expect(dots.first, const Offset(250.5, 51.5));
      expect((dots[1] - dots[0]).distance, closeTo(3.5, 1e-6));
      expect(dots.last.dx, greaterThan(258), reason: '점은 구멍 앞까지 이어짐');
      // 열쇠표 '방식 미상': C 왼쪽 19 · C 윗변 1 위(바깥 상자 13) · 45° 실은 C 윗변의 왼쪽 16.5에서 열쇠표 구멍까지(9 옆 · 8 위)
      expect(geo.keys, hasLength(1));
      final key = geo.keys.single;
      expect(key.node, 2);
      expect(key.box, Rect.fromLTWH(c.x1 + 19, c.y - 14, (36 + 11 + 6) + 1, 13));
      expect(key.box.bottom, c.y - 1);
      expect(key.from, Offset(c.x1 + 16.5, c.y + .5));
      expect(key.hole - key.from, const Offset(9, -8));
      // 적지 않음: 옅은 실(1 · 먹 25) · 매듭도 옅게
      final blank = threadOf(const Offset(300.5, 51.5));
      expect((blank.style, blank.width, blank.color), (GroupLineStyle.faint, 1.0, SheetLook.ink25));
      expect([for (final k in geo.knots) (k.at, k.faint)], [(const Offset(250.5, 51.5), false), (const Offset(300.5, 51.5), true), (Offset(500.5, f.hole.dy), false)]);
      // 이름 바꿈: 같은 줄 — B의 마름모에서 E의 구멍까지 짧은 실 하나
      expect(e.row, b.row);
      expect(pts(3), [b.diamond!, Offset(e.hole.dx - 2.5, e.hole.dy)]);
      // 합쳐짐: C · D의 마름모 → 통로(C · D 끝 6 밖) → 세로 → F의 구멍 줄의 매듭 하나 → 구멍
      expect(pts(4), [c.diamond!, Offset(500.5, c.diamond!.dy), Offset(500.5, f.hole.dy), Offset(f.hole.dx - 2.5, f.hole.dy)]);
      expect(pts(5).first, dd.diamond!);
      expect(geo.threads.where((t) => t.points.length == 2 && t.points.first == Offset(500.5, f.hole.dy)), hasLength(1), reason: '모인 매듭에서 구멍까지 실 하나');
      // 이음 누름 = 사건 — 통로의 세로 실 가운데 · 모인 실 위
      expect(geo.edgeAt(const Offset(400.5, 40))?.ev, 'ev-split');
      expect(geo.edgeAt(Offset(500.5, f.hole.dy - 20))?.ev, 'ev-merge');
      expect(geo.edgeAt(const Offset(250.5, 90)), isNull, reason: '사건이 없는 실은 누를 수 없음');
      expect(geo.barAt(Offset(b.x1 + 20, b.cy)), 1);
      expectNoCover(d, geo);
    });

    test('꼬리표 글 — 이름(구멍 뒤 7 · 마름모 앞 6) → 첫 글자 → 없음 · 해는 흰 층에 들 때만 · 보이는 왼쪽 밖에서 시작하면 글을 옮김', () {
      final g = data.nodes[1]; // 동쪽 무리 842 ~ 905 — 이름 5자 · 해 '842 ~ 905' 9자
      double w(String t, TextStyle s) => t.length * 10.0;
      GroupBarGeo bar(double width, {bool tail = false}) => GroupBarGeo(0, width, 0, 0, tail: tail);
      final wide = groupTagLabel(g, bar(200), w);
      expect((wide.name, wide.years), ('동쪽 무리', '842 ~ 905'));
      expect(wide.nameRect, const Rect.fromLTWH(16.5, 12 - 4.5, 50, 9), reason: '구멍(9.5) 뒤 7 · 머리 가운데 12');
      expect(wide.yearsRect, const Rect.fromLTWH(16.5, 31.5 - 4.25, 90, 8.5), reason: '흰 층 가운데(머리 밑선 23.5 + 8)');
      final mid = groupTagLabel(g, bar(80), w);
      expect((mid.name, mid.years), ('동쪽 무리', ''), reason: '해는 오른쪽 끝 4 안에 들 때만');
      expect(groupTagLabel(g, bar(78, tail: true), w).name, '동', reason: '마름모 앞 6까지 들지 않으면 첫 글자');
      expect(groupTagLabel(g, bar(30), w).nameRect, isNull);
      expect(groupTagLabel(g, const GroupBarGeo(-300, 200, 0, 0), w, viewLeft: 0).nameRect!.left, 8, reason: '보이는 왼쪽 + 8');
      expect(groupYears(const GroupTreeNode(uid: 'x', name: 'x', color: Color(0xff000000), row: 0, lo: 0, hi: 1, range: '1402–2026', when: '1402년 ~ 현재')), '1402 ~ 현재');
    });
  });

  group('창', () {
    testWidgets('단체 창의 단추가 연 것처럼 — 나라 나무를 그 단체를 고른 채로 · 조명 · 크기 · 머리글', (tester) async {
      final bus = makeBus();
      await mount(tester, bus);
      openGroupTree(bus, east, group: east);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      expect(s.data!.holder, kap, reason: 'x_treeAt으로 나라 나무를 읽음');
      expect(s.data!.nodes[s.selected].uid, east);
      expect(bus.slot('spots').value, s.data!.nodes[s.selected].spots, reason: '그 나라 띠에 집권 덩이마다 조명');
      expect((bus.slot('spots').value as List).length, 2);
      final sheet = tester.getRect(find.byKey(groupTreeKey));
      expect(sheet.height, 525, reason: 'min(525px, 56%) — 1000의 56%는 560');
      expect(sheet.width, 1920);
      expect(sheet.bottom, 1000);
      // 창 = 그 나라 색 폴더 '단체 계보'(어깨 탭 맨 글) — 화면 양옆 8 · 탭은 흰 둘레 6 아래 · 몸통의 아래 끝은 창 밖
      final folder = tester.widget<SheetFolder>(find.byType(SheetFolder));
      expect((folder.label, folder.color), ('단체 계보', s.data!.polityColor));
      final folderRect = tester.getRect(find.byType(SheetFolder));
      expect(folderRect.left - sheet.left, 8);
      expect(sheet.right - folderRect.right, 8);
      expect(folderRect.top - sheet.top, SheetLook.folderRim);
      expect(folderRect.bottom, greaterThan(sheet.bottom), reason: '아래 귀는 창 밖(연표 밑에 붙은 서랍)');
      // 머리 줄(몸통 위 12 · 키 24): 나라 꼬리표 · 범례 흰 종이 한 줄 · 닫기 종이
      final headTop = folderRect.top + SheetLook.folderTab + 12;
      bool inHead(Finder f) => f.evaluate().any((e) {
        final r = tester.getRect(find.byWidget(e.widget));
        return r.top >= headTop && r.bottom <= headTop + 24;
      });
      expect(inHead(find.text('갑 왕국')), isTrue);
      expect(inHead(find.text('닫기')), isTrue);
      for (final w in const ['갈라짐', '합쳐짐', '이름 바꿈', '방식 미상', '적지 않음', '집권', '연정', '있던 기간']) {
        expect(inHead(find.text(w)), isTrue, reason: '범례 $w');
      }
      // 상자 둘 — 오른쪽 '단체 7'은 그림 영역 왼쪽 4 밖에서, 왼쪽 '고른 단체'는 그 앞 12까지(머리 줄 아래 10)
      final v = bus.controller.view;
      final plotLeft = sheet.left + v.left * v.mag;
      final treeBox = tester.getRect(find.byWidgetPredicate((w) => w is SheetBox && w.label == '단체'));
      final sideBox = tester.getRect(find.byWidgetPredicate((w) => w is SheetBox && w.label == '고른 단체'));
      expect(treeBox.left, plotLeft - 4);
      expect(sideBox.right, plotLeft - 16);
      expect(sideBox.left, sheet.left + 20);
      expect((treeBox.top, sideBox.top), (headTop + 34, headTop + 34));
      expect((treeBox.bottom, sideBox.bottom), (sheet.bottom - 12, sheet.bottom - 12));
      expect(find.text('7'), findsOneWidget, reason: '뚜껑의 단체 수');
      for (final y in const ['750', '800', '850', '900', '950']) {
        expect(find.text(y), findsOneWidget, reason: '뚜껑의 50년 해 글 $y');
      }
      // 왼쪽 상자 — 고른 단체 꼬리표 · 기간 · 조명 중 · 단추 · 집권 1 · 연정 1과 칸 견본 줄 · 이어짐(앞 옛 무리 · 갈라짐) · 안내 두 줄
      final g = s.data!.nodes[s.selected];
      for (final t in ['동쪽 무리', '842년 ~ 905년', '조명 중', '단체 창', '이 시기로', '1 · 연정 1', '이어짐', '앞', '옛 무리', ...GroupTreeLook.tips]) {
        expect(find.text(t), findsOneWidget, reason: '고른 단체 상자 $t');
      }
      for (final seg in g.segs) {
        expect(find.text('${groupYearOf(seg.a)} ~ ${groupYearOf(seg.b)}'), findsOneWidget);
      }
      // 그림 영역은 연표의 이름 칸 오른쪽 · 연표의 그림 영역 폭
      expect(plotOrigin(tester).dx - sheet.left, v.left * v.mag);
      expect(s.plotOf().width, v.plotWidth * v.mag);
      // 꼬리표 x = 위 연표의 같은 해 x(그림 영역 기준 · 화소로 반올림)
      final geo = geoOf(tester);
      expect(geo.bars[0].x1, closeTo((v.xOf(s.data!.nodes[0].lo) - v.left) * v.mag, .5));
      // 고른 단체 — 고른 테(먹 100 · 1.5 · 꼬리표 2 밖)
      final picked = geo.bars[s.selected].rect;
      expect(
        treePaint(tester),
        paints..something((m, a) {
          if (m != #drawPath || (a[1] as Paint).color.toARGB32() != SheetLook.pickInk.toARGB32()) return false;
          final p = a[0] as Path, x = picked.center.dx;
          return p.contains(Offset(x, picked.top - 1.5)) && p.contains(Offset(x, picked.top - 2.1)) && !p.contains(Offset(x, picked.top - 2.5)) && !p.contains(Offset(x, picked.top - .5));
        }),
      );
    });

    testWidgets('머리 줄의 나라 꼬리표는 나라 상세 · 이어짐 꼬리표는 그 단체를 고름 · 고른 단체가 없으면 안내 글만', (tester) async {
      final bus = makeBus();
      await mount(tester, bus);
      openGroupTree(bus, east, group: east);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      await tester.tap(find.text('옛 무리'));
      await tester.pump();
      expect(s.data!.nodes[s.selected].uid, old, reason: '이어짐의 앞 단체를 고름');
      expect(find.text('뒤'), findsWidgets, reason: '옛 무리의 뒤 단체 셋');
      expect(find.text('적지 않음'), findsNWidgets(2), reason: '범례 + 옛 무리 → 남쪽 무리');
      await tester.tap(find.text('갑 왕국'));
      await tester.pump();
      expect(bus.selection.value?.uid, kap, reason: '나라 꼬리표 = 나라 상세');
      s.select(-1);
      await tester.pump();
      expect(find.textContaining('막대를 누르면 위 연표의'), findsOneWidget);
      expect(find.text(GroupTreeLook.tips.first), findsNothing);
    });

    testWidgets('방식 미상 · 안에서 갈라짐 — 점 실 · 아랫변 매듭 · 열쇠표가 창에 그려지고 글자를 덮지 않는다', (tester) async {
      final bus = makeBus(store: unknownStore());
      await mount(tester, bus);
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      final geo = geoOf(tester);
      expect(geo.keys, hasLength(1));
      final south = s.data!.indexOf('sample-groups/gr-south');
      expect(geo.keys.single.node, south);
      expect(geo.knots.where((k) => k.at.dy == geo.bars[0].bottom), hasLength(1), reason: '옛 무리 아랫변의 매듭');
      expect(geo.threads.where((t) => t.style == GroupLineStyle.dotted), hasLength(1));
      expect(geo.rowTops[3] - geo.rowTops[2], 46 + 14, reason: '열쇠표가 달린 줄은 위로 14 더');
      final paint = treePaint(tester);
      // 열쇠표 — 꼬리표 윗변에서 45° 실(먹 45 · 1) 뒤에 흰 종이 열쇠표(테 먹 45 · 키 13)
      final key = geo.keys.single;
      expect(paint, paints..something((m, a) => m == #drawLine && a[0] == key.from && a[1] == key.hole && (a[2] as Paint).color.toARGB32() == SheetLook.ink45.toARGB32()));
      expect(paint, paints..something((m, a) => m == #drawPath && (a[1] as Paint).color.toARGB32() == SheetLook.ink45.toARGB32() && ((a[0] as Path).getBounds().height - 13).abs() < .01));
      // 점 실의 점(지름 1.75 · 먹 45)
      expect(paint, paints..something((m, a) => m == #drawCircle && a[1] == GroupTreeLook.dot / 2 && (a[2] as Paint).color.toARGB32() == SheetLook.ink45.toARGB32()));
      // 글자 가림 0
      expectNoCover(s.data!, geo);
    });

    testWidgets('막대를 누르면 고름 · 두 번 누르면 단체 창 · 이음선은 그 사건 · 닫으면 제 조명만 걷음', (tester) async {
      final bus = makeBus();
      await mount(tester, bus);
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      expect(s.selected, -1);
      expect(find.textContaining('막대를 누르면 위 연표의'), findsOneWidget);
      final origin = plotOrigin(tester);
      var geo = geoOf(tester);
      final i = s.data!.indexOf(newer);
      await tester.tapAt(origin + geo.bars[i].rect.center);
      await tester.pump();
      expect(s.selected, i, reason: '손을 떼면 곧바로 고름(두 번 누름을 기다리지 않음)');
      expect(bus.slot('spots').value, s.data!.nodes[i].spots);
      // 고른 단체는 위 연표의 집권 단에서 그 단체의 칸만 진하게(웹 setGroupFocus) — 장면의 표시 상태에 uid와 색을 적는다
      final marks = SceneMarks.of(bus.scene);
      expect(marks.groupFocus, newer);
      expect(marks.groupFocusColor, s.data!.nodes[i].color.toARGB32() & 0xffffff);
      expect(bus.selection.value, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      // 두 번 누름 → 단체 창
      await tester.tapAt(origin + geo.bars[i].rect.center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(origin + geo.bars[i].rect.center);
      await tester.pumpAndSettle();
      expect(bus.selection.value?.uid, newer);
      expect(bus.selection.value?.kind, 'group');
      // 사건이 있는 이음선(옛 무리 → 동쪽 무리 갈라짐)
      bus.clearSelection();
      geo = geoOf(tester);
      final hit = geo.hits.firstWhere((h) => h.edge.ev == 'sample-groups/gr-e-split');
      final mid = Offset.lerp(hit.points[1], hit.points[2], .5)!; // 통로의 세로 실 가운데(꼬리표 밖)
      expect(geo.barAt(mid), -1);
      await tester.tapAt(origin + mid);
      await tester.pump(const Duration(milliseconds: 400));
      expect(bus.selection.value?.uid, 'sample-groups/gr-e-split');
      // 다른 창이 조명을 걷으면 고른 단체의 조명이 되살아남(웹 restoreSpot)
      bus.slot('spots').value = null;
      await tester.pump();
      expect(bus.slot('spots').value, s.data!.nodes[i].spots);
      // 다른 창이 제 조명을 켠 뒤 닫으면 남의 조명은 그대로
      final other = [
        {'uid': 'x', 'start': 0, 'end': 1},
      ];
      bus.slot('spots').value = other;
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(s.isOpen, isFalse);
      expect(bus.slot('spots').value, same(other));
      expect(marks.groupFocus, isNull, reason: '창을 닫으면 고름도 풀린다');
      expect(find.byKey(groupTreeKey), findsNothing);
    });

    // 리메이크 2부(목업 서고) — 확대 묶음은 맨 위 줄로 옮겼으니 비키지 않는다. 연표 위 오른쪽 아래에 떠서 비키는 것은 배율 알약 · 상세 칸.
    testWidgets('앱 틀: 계보 창이 떠 있는 동안 배율 알약과 상세 칸이 창 높이만큼 위로 비켜 창과 겹치지 않는다(확대 묶음은 맨 위 줄 그대로)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final query = TextEditingController();
      addTearDown(query.dispose);
      Widget shell({required bool sheet}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: AppShell(
            controller: scene.controller,
            timeline: TimelineView(scene: scene),
            searchController: query,
            detail: const Text('고른 항목의 상세'),
            stageBottomInset: sheet ? GroupTreeLayerState.sheetHeight : null,
          ),
        ),
      );
      double below(Type what) => 1080 - tester.getRect(find.byType(what)).bottom;
      await tester.pumpWidget(shell(sheet: false));
      await tester.pump(const Duration(milliseconds: 500));
      final zoom = tester.getRect(find.byType(ZoomButtons));
      expect(zoom.bottom, lessThanOrEqualTo(Ui.top), reason: '확대 묶음은 맨 위 줄 안');
      expect(below(MagPill), closeTo(Ui.zoomBottom, .01));
      expect(below(DetailPanel), closeTo(Ui.detailBottom, .01));
      await tester.pumpWidget(shell(sheet: true));
      await tester.pump(const Duration(milliseconds: 500));
      final h = GroupTreeLayerState.sheetHeight(1080 - Ui.top);
      expect(h, 525, reason: '연표 영역 1020의 56%는 571 — 525까지');
      expect(below(MagPill), closeTo(Ui.zoomBottom + h, .01), reason: '배율 알약은 창 위 16');
      expect(below(DetailPanel), closeTo(Ui.detailBottom + h, .01), reason: '상세 칸은 창 위까지만');
      expect(tester.getRect(find.byType(ZoomButtons)), zoom, reason: '맨 위 줄의 확대 묶음은 계보 창과 겹치지 않아 그대로');
    });

    testWidgets('Esc — 상세 창이 먼저(단축키 부품이 닫음), 그다음 이 창', (tester) async {
      final bus = makeBus();
      // 앱 틀(app_glue)처럼 Esc 명령이면 고른 것을 거둔다 — 계보 창 층보다 먼저 듣는다
      bus.slot(slotCommand).addListener(() {
        final c = bus.slot(slotCommand).value;
        if (c is AppCommand && c.name == Cmd.close) bus.clearSelection();
      });
      await mount(tester, bus, keys: true);
      openGroupTree(bus, kap, group: old);
      await tester.pumpAndSettle();
      bus.select(east, kind: 'group');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.selection.value, isNull, reason: '첫 Esc는 상세 창');
      expect(layerOf(tester).isOpen, isTrue, reason: '같은 누름에 계보 창까지 닫지 않음');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(layerOf(tester).isOpen, isFalse, reason: '둘째 Esc는 계보 창');
      expect(bus.slot('spots').value, isNull, reason: '이 창이 켠 조명을 걷음');
    });

    testWidgets('Esc — 단축키 부품이 같은 누름에 렌즈를 끄면 이 창은 그대로(한 번에 하나)', (tester) async {
      final bus = makeBus();
      // 렌즈 부품의 Esc 갈래(단축키 부품 — 계보 창 층보다 먼저 키를 듣는다)를 흉내: 렌즈가 켜져 있으면 끈다
      bool lensOff(KeyEvent e) {
        if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return false;
        final lens = bus.slot('themeLens').value;
        if (lens is String && lens.isNotEmpty) {
          bus.slot('themeLens').value = null;
          return true;
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(lensOff);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(lensOff));
      await mount(tester, bus);
      bus.slot('themeLens').value = 'faction';
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.slot('themeLens').value, isNull);
      expect(layerOf(tester).isOpen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(layerOf(tester).isOpen, isFalse);
    });

    testWidgets('연표가 배치 도중(LayoutBuilder 안)에 크기를 알려도 다음 장면에 같은 x로 다시 그림', (tester) async {
      final bus = makeBus();
      tester.view.physicalSize = const Size(1920, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // 연표(timeline_view.dart)처럼 배치 도중에 조종부 크기를 알린다
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      bus.controller.resize(box.maxWidth, box.maxHeight);
                      return const SizedBox();
                    },
                  ),
                ),
                Positioned.fill(child: GroupTreeLayer(bus: bus)),
              ],
            ),
          ),
        ),
      );
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1600, 900);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump();
      final s = layerOf(tester);
      final v = bus.controller.view;
      expect(s.plotOf().width, v.plotWidth * v.mag, reason: '크기가 바뀐 뒤의 그림 영역 폭');
      expect(tester.getRect(find.byKey(groupTreeKey)).height, closeTo(900 * .56, 1e-9), reason: '900의 56% = 504 < 525');
    });

    testWidgets('나무가 보기 범위 밖이면 나무 전체가 들어오게 간다', (tester) async {
      final bus = makeBus();
      bus.controller.showRange(minuteOfYear(1500), minuteOfYear(1600));
      await mount(tester, bus);
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      final go = bus.go.value!;
      final d = layerOf(tester).data!;
      expect(go.lo, lessThan(d.lo));
      expect(go.hi, greaterThan(d.hi));
    });

    // 2026-10-14 고침: 전에는 나무 전체가 보기 밖일 때만 옮겨, 고른 단체의 막대와 위 연표의 조명이 화면 밖에 남았다(왼쪽 칸은 '연표에 조명 중').
    testWidgets('나무는 보이지만 고른 단체가 보기 밖이면 그 단체의 기간으로 간다 — 이 시기로와 같은 틀(앞뒤 15% · 적어도 2년)', (tester) async {
      final bus = makeBus();
      bus.controller.showRange(minuteOfYear(900), minuteOfYear(1000)); // 새 무리 · 곧은 길 모임 …은 보이고 옛 무리(760~842)는 밖
      await mount(tester, bus);
      openGroupTree(bus, old, group: old);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      final g = s.data!.nodes[s.selected];
      expect(g.uid, old);
      final go = bus.go.value!;
      final pad = (g.hi - g.lo) * .15;
      expect(go.lo, closeTo(g.lo - pad, 1e-6));
      expect(go.hi, closeTo(g.hi + pad, 1e-6));
      expect(bus.slot('spots').value, g.spots, reason: '고른 단체의 조명');
    });

    testWidgets('고른 단체가 조금이라도 보이면 보기를 옮기지 않는다', (tester) async {
      final bus = makeBus();
      bus.controller.showRange(minuteOfYear(830), minuteOfYear(1000)); // 옛 무리의 830~842가 보임
      await mount(tester, bus);
      openGroupTree(bus, old, group: old);
      await tester.pumpAndSettle();
      expect(layerOf(tester).data!.nodes[layerOf(tester).selected].uid, old);
      expect(bus.go.value, isNull);
    });

    testWidgets('단추 — 계보 창 층이 붙어 있을 때만 단체 창 · 나라 상세에 선다', (tester) async {
      registerGroupDetail();
      final bus = makeBus();
      await mount(tester, bus, layer: false, detail: DetailHost(bus: bus, framed: false));
      bus.select(east, kind: 'group');
      await tester.pumpAndSettle();
      expect(find.text('단체 계보'), findsNothing, reason: '층이 없으면 누를 곳 없는 단추를 두지 않음');

      final bus2 = makeBus();
      await mount(tester, bus2, detail: DetailHost(bus: bus2, framed: false));
      bus2.select(east, kind: 'group');
      await tester.pumpAndSettle();
      final button = find.widgetWithText(DetailSmallButton, '단체 계보');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(bus2.slot(groupTreeSlot).value, const GroupTreeRequest(kap, group: east), reason: '단체 기록의 x_treeAt — 그 나라의 나무를 그 단체를 고른 채로');
      expect(layerOf(tester).data!.nodes[layerOf(tester).selected].uid, east);
      for (final k in detailKinds) {
        DetailHost.unregister(k.id);
      }
    });
  });

  group('법의 내력 · 결과(의석 막대)', () {
    Future<void> show(WidgetTester tester, List<Widget> children) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Ui.bg,
          body: SizedBox(width: Ui.detailWidth, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
        ),
      ),
    );
    final opened = <(String, String)>[];
    void open(String uid, {String kind = '', String? cell}) => opened.add((uid, kind));
    List<String> boxes(WidgetTester tester) => [for (final b in tester.widgetList<DetailBox>(find.byType(DetailBox))) '${b.title}${b.small == null ? '' : ' (${b.small})'}'];

    testWidgets('법의 내력 — 같은 이름의 법을 날짜 차례로 · 사이 간격 · 이 사건 · 폐지 기록 없음', (tester) async {
      final x = rec('sample-lens/ln-e-amend');
      final h = DetailLawHistory(x, open: open);
      expect(h.rowTexts, ['제정760년 새 법전 반포', '개정830년 이 사건70년 뒤', '폐지기록 없음 — 나라가 끝날 때까지 쓴 것으로 봄']);
      await show(tester, [h]);
      expect(boxes(tester), ['법의 내력 (2)']);
      await tester.tap(find.textContaining('760년', findRichText: true));
      expect(opened.last, ('sample-lens/ln-e-enact', ''));
      final one = DetailLawHistory(rec('sample-lens/ln-e-repeal'), open: open);
      expect(one.rowTexts, ['폐지905년 이 사건']);
      await show(tester, [one]);
      expect(boxes(tester), ['법의 내력']);
    });

    testWidgets('아래 묶음 — 제자리 셋을 아직 부르지 않으면 법 이름 · 내력 · 결과도 맨 앞, 부르면 조항 · 관련만', (tester) async {
      final law = rec('sample-lens/ln-e-amend');
      await show(tester, detailLensBottom(law, open));
      expect(find.text('법 이름 새 법전'), findsOneWidget);
      expect(boxes(tester), ['법의 내력 (2)', '조항 (1)', '관련']);
      expect(find.text('개정'), findsWidgets, reason: '개정 사건의 조항 줄마다 개정 딱지');
      await show(tester, detailLensBottom(law, open, topsPlaced: true));
      expect(boxes(tester), ['조항 (1)', '관련']);
      expect(find.text('법 이름 새 법전'), findsNothing);
      // 관련 — 그때의 법률(제도 창) · 앞 고침(사건 창)
      await tester.tap(find.text('새 법전 반포'));
      expect(opened.last, ('sample-lens/ln-e-enact', ''));
      await tester.tap(find.text('새 법전').last);
      expect(opened.last, ('sample-lens/ln-i-law', 'institution'));

      final vote = rec('sample-lens/ln-e-vote1');
      await show(tester, detailLensBottom(vote, open));
      expect(boxes(tester), ['결과 (의석 80)', '관련']);
      expect(find.text('뽑은 자리 의회'), findsOneWidget);
      await show(tester, [...detailLensAka(vote), ...detailElectionTop(vote, open), ...detailLensBottom(vote, open, topsPlaced: true)]);
      expect(boxes(tester), ['결과 (의석 80)', '관련']);
    });

    testWidgets('의석 막대 — 의석만큼 나눔 · 과반 글 · 결과 표 · 득표만 적은 선거', (tester) async {
      final vote = rec('sample-lens/ln-e-vote1');
      await show(tester, detailElectionTop(vote, open));
      expect(find.text('과반 41석 — 푸른 모임 41석'), findsOneWidget);
      final bar = tester.getSize(find.byType(DetailSeatBar));
      expect(bar.height, DetailSeatBar.height);
      final widths = DetailSeatBar.widthsOf(const [41, 33, 6], bar.width);
      expect(widths[0] / widths[1], closeTo(41 / 33, 1e-9));
      expect(widths.reduce((a, b) => a + b) + 2 * DetailSeatBar.gap, closeTo(bar.width, 1e-9));
      expect(find.text('41석'), findsOneWidget);
      expect(find.text('당선'), findsOneWidget);
      expect(find.text('12,034'), findsOneWidget);

      final v2 = rec('sample-lens/ln-e-vote2');
      await show(tester, detailElectionTop(v2, open));
      expect(boxes(tester), ['결과 (득표 30,190)']);
      expect(find.text('가장 많은 표 — 붉은 모임의 사람 50.4%'), findsOneWidget);
      expect(find.text('의석'), findsNothing, reason: '의석을 적지 않은 선거는 의석 열이 없음');
      // 가장 좁아도 3px
      expect(DetailSeatBar.widthsOf(const [1000, 1], 100), [95.0, 3.0]);
    });

    testWidgets('모임이 단체면 막대 조각 · 이름을 누르면 단체 창', (tester) async {
      const vote = {
        'by': 'seats',
        'total': 10,
        'linked': 1,
        'rows': [
          {'who': '동쪽 무리', 'color': '#dab195', 'uid': east, 'seats': 6, 'won': 1, 'part': '동쪽 무리 6석'},
          {'who': '그 밖', 'color': '#9dbea8', 'seats': 4, 'part': '그 밖 4석'},
        ],
        'cap': '과반 6석 — 동쪽 무리 6석',
      };
      opened.clear();
      await show(tester, [const DetailVoteBox(vote, open: _noOpen)]);
      expect(boxes(tester), ['결과 (의석 10 · 누르면 그 모임)']);
      await show(tester, [DetailVoteBox(vote, open: open)]);
      await tester.tap(find.bySemanticsLabel('동쪽 무리 6석 — 단체 창'));
      expect(opened.last, (east, 'group'));
      await tester.tap(find.text('동쪽 무리'));
      expect(opened.last, (east, 'group'));
    });

    test('딱지 — 법 · 선거는 마름모(주제 색) · 뽑은 자리', () {
      final badges = detailLensBadges(rec('sample-lens/ln-e-vote1')).whereType<DetailBadge>().toList();
      final v = badges.firstWhere((b) => b.diamond && b.text.startsWith('선거'));
      expect(v.text, '선거 · 의회');
      expect(v.diamond, isTrue);
      expect(v.color, detailVoteColor);
      final l = detailLensBadges(rec('sample-lens/ln-e-amend')).whereType<DetailBadge>().firstWhere((b) => b.diamond);
      expect(l.text, '법 · 개정');
      expect(l.color, detailLawColor);
    });
  });
}

void _noOpen(String uid, {String kind = '', String? cell}) {}
