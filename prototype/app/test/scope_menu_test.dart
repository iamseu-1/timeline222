import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 그릇 안 오른쪽 클릭 차림표의 네 줄(리메이크 4단계 과제 7 걸음 5): 메이커 서고 미리보기(js/viewer.js menuItems)와 같은 낱말 · 차례 —
// 펼침 · 선반 · 접음 · 풂. ✓는 상태 이름으로 맞추고(장면 ScopeState의 차례 open · closed · loose · shelf와 메뉴 차례가 다르다) 명령의 arg는 상태 이름.

({AppBus bus, List<AppCommand> commands}) makeBus() {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(0, 1000000)
    ..showRange(0, 500000);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [{'id': 1, 'name': '검사 자료집', 'events': 0}],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('차림표 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(ask: (query) async => const {}, controller: controller, scene: scene);
  final commands = <AppCommand>[];
  bus.slot(slotCommand).addListener(() {
    final one = bus.slot(slotCommand).value;
    if (one is AppCommand) commands.add(one);
  });
  return (bus: bus, commands: commands);
}

/// 차림표에서 그릇 줄(줄 뒤 회색 글이 그릇 이름인 줄)만.
List<MenuRow> scopeRows(List<MenuRow> rows, String name) => [for (final r in rows) if (!r.sep && !r.header && r.keyText == name) r];

void main() {
  test('낱말 · 차례 · 명령 arg: 펼침 open · 선반 shelf · 접음 closed · 풂 loose — 메이커 서고 미리보기와 같음 · arg는 장면 ScopeState의 이름', () {
    expect(scopeStates, const [('open', '펼침'), ('shelf', '선반'), ('closed', '접음'), ('loose', '풂')]);
    for (final (name, _) in scopeStates) {
      expect(ScopeState.values.where((s) => s.name == name), hasLength(1), reason: '$name은 ScopeState의 이름');
    }
    expect(ScopeState.values.map((s) => s.name), ['open', 'closed', 'loose', 'shelf'], reason: '장면의 차례는 메뉴와 다르다 — 그래서 ✓는 이름으로');
  });

  test('그릇 안 오른쪽 클릭: 네 줄(줄 뒤 회색 글 = 그릇 이름) · 상태마다 ✓ 하나 · 누르면 Cmd.scopeState(uid · arg 상태 이름)', () {
    final (:bus, :commands) = makeBus();
    for (final state in ScopeState.values) {
      final rows = buildMenuRows(bus: bus, spot: MenuSpot(at: 250000, scope: 'p/s-fed', scopeName: '적석 연방 영지들', scopeState: state.name));
      final four = scopeRows(rows, '적석 연방 영지들');
      expect(four.map((r) => r.label), ['펼침', '선반', '접음', '풂'], reason: state.name);
      expect([for (final r in four) if (r.checked) r.label], [scopeStates.firstWhere((x) => x.$1 == state.name).$2], reason: '${state.name}: ✓ 하나');
      // 네 줄은 맨 앞의 묶음 제목 '보기'(G5 #9 — 시트 갈래) 바로 뒤 · 그 뒤 구분선.
      expect(rows.first.header, isTrue);
      expect(rows.first.label, '보기');
      expect(rows.indexOf(four.first), 1);
      expect(rows[5].sep, isTrue);
    }
    final rows = buildMenuRows(bus: bus, spot: const MenuSpot(scope: 'p/s-fed', scopeName: '적석 연방 영지들', scopeState: 'open'));
    for (final r in scopeRows(rows, '적석 연방 영지들')) {
      r.onSelected!();
    }
    expect([for (final c in commands) (c.name, c.uid, c.arg)], [
      (Cmd.scopeState, 'p/s-fed', 'open'),
      (Cmd.scopeState, 'p/s-fed', 'shelf'),
      (Cmd.scopeState, 'p/s-fed', 'closed'),
      (Cmd.scopeState, 'p/s-fed', 'loose'),
    ]);
  });

  test('상태를 모르면(빈 글) ✓ 없이 네 줄 · 그릇 밖이면 그릇 줄이 없다 · 긴 이름은 12자에서 자른다', () {
    final (:bus, commands: _) = makeBus();
    final none = scopeRows(buildMenuRows(bus: bus, spot: const MenuSpot(scope: 's', scopeName: '그릇')), '그릇');
    expect(none.map((r) => r.label), ['펼침', '선반', '접음', '풂']);
    expect(none.where((r) => r.checked), isEmpty);
    final outside = buildMenuRows(bus: bus, spot: const MenuSpot(at: 250000));
    expect(outside.where((r) => const ['펼침', '선반', '접음', '풂'].contains(r.label)), isEmpty);
    const long = '아주 긴 이름의 그릇 하나 둘 셋 넷';
    final cut = buildMenuRows(bus: bus, spot: const MenuSpot(scope: 's', scopeName: long, scopeState: 'shelf'));
    expect(cut.first.header, isTrue, reason: "맨 앞은 묶음 제목 '보기'");
    expect(cut[1].keyText, cutName(long, 12));
    expect(cut[2].checked, isTrue, reason: '선반');
  });

  // 가장 흔한 길 — 그릇 안의 띠를 오른쪽 클릭(item != null · remake-4-int 검토 고침: 시트 갈래의 '보기' 제목과 과제 7의 네 줄이 합친 판에서 처음 만남).
  // 항목 덩이(제목 · 자세히 보기 · 문서 · 여기로 확대 · 대범위 모아 보기) → 구분선 → '보기' 제목 → 네 줄 → 구분선 → 트랙 · 때 줄.
  const name = '적석 연방 영지들';
  List<MenuRow> rowsOnBand(AppBus bus, String state) => buildMenuRows(
    bus: bus,
    spot: MenuSpot(uid: 'p/o-black', trackId: 1, trackName: '하연', at: 250000, scope: 'p/s-fed', scopeName: name, scopeState: state),
    item: const EntityBrief(uid: 'p/o-black', kind: 'period', name: '검은솔 대공국', scopes: [MenuScope('p/s-fed', name)]),
    flags: const MenuFlags(scopesOn: {'p/s-fed': true}),
  );

  test("그릇 안의 띠를 오른쪽 클릭: 항목 덩이 · 구분선 뒤에 '보기' 제목 → 네 줄(✓ 하나 · 회색 글 = 그릇 이름) → 구분선 → 트랙 줄", () {
    final (:bus, commands: _) = makeBus();
    final rows = rowsOnBand(bus, 'shelf');
    final view = rows.indexWhere((r) => r.header && r.label == '보기');
    expect(rows.first.header, isTrue, reason: '맨 앞은 항목 제목');
    expect(rows.indexWhere((r) => r.label == '자세히 보기'), 1);
    expect(rows.indexWhere((r) => r.header && r.label == '대범위 모아 보기'), lessThan(view));
    expect([rows[view - 2].label, rows[view - 2].checked, rows[view - 1].sep], [name, true, true], reason: '대범위 모아 보기 줄(켬) 뒤 구분선 바로 다음이 보기 제목');
    final four = rows.sublist(view + 1, view + 5);
    expect(four.map((r) => r.label), ['펼침', '선반', '접음', '풂']);
    expect(four.map((r) => r.keyText).toSet(), {name});
    expect([for (final r in four) if (r.checked) r.label], ['선반']);
    expect(rows[view + 5].sep, isTrue, reason: '네 줄 뒤 구분선');
    expect(rows[view + 6].label, '하연 접기', reason: '그 뒤가 트랙 줄');
    expect(scopeRows(rows, name), four, reason: '그릇 줄은 이 넷뿐(대범위 모아 보기 줄은 회색 글이 없다)');
  });

  testWidgets("그린 차림표: 네 줄은 '보기' 상자 안 첫 작은 묶음 — 뒤는 묶음 틈 6 · 회색 글 먹 45 · ✓는 구멍 먹 85 + 굵게 · 상자는 항목 → 대범위 모아 보기 → 보기 차례", (tester) async {
    final (:bus, commands: _) = makeBus();
    final rows = rowsOnBand(bus, 'shelf');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTimelineMenu(context, rows, at: const Offset(40, 20), minWidth: SheetLook.menuWidth),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    SheetBox boxOf(String label) => tester.widget<SheetBox>(find.ancestor(of: find.text(label), matching: find.byType(SheetBox)).first);
    for (final label in ['펼침', '선반', '접음', '풂', '하연 접기', '기간 재기']) {
      expect(boxOf(label).label, '보기', reason: label);
    }
    final column = tester.widget<SheetThreadColumn>(find.ancestor(of: find.text('펼침'), matching: find.byType(SheetThreadColumn)).first);
    expect(column.breakBefore.reduce((a, b) => a < b ? a : b), 4, reason: '네 줄 뒤가 첫 작은 묶음 틈');
    expect([column.gap, column.breakGap], [SheetLook.menuRowGap, SheetLook.menuSubGap]);
    final viewBox = find.byWidgetPredicate((w) => w is SheetBox && w.label == '보기');
    final keys = find.descendant(of: viewBox, matching: find.text(name));
    expect(keys, findsNWidgets(4), reason: '줄 뒤 회색 글(그릇 이름) 넷');
    for (final e in keys.evaluate()) {
      expect((e.widget as Text).style!.color, SheetLook.ink45);
    }
    SheetShape shapeOf(String label) => tester.widget<SheetTag>(find.ancestor(of: find.text(label), matching: find.byType(SheetTag)).first).shape;
    expect([shapeOf('선반').holeFill, tester.widget<Text>(find.text('선반')).style!.fontWeight], [SheetLook.ink85, FontWeight.w700]);
    for (final label in ['펼침', '접음', '풂']) {
      expect([shapeOf(label).holeFill, tester.widget<Text>(find.text(label)).style!.fontWeight], [SheetLook.paper, FontWeight.w400], reason: label);
    }
    final tops = [
      for (final label in ['시대 · 검은솔 대공국', '대범위 모아 보기', '보기'])
        tester.getRect(find.byWidgetPredicate((w) => w is SheetBox && w.label == label)).top,
    ];
    expect(tops, orderedEquals([...tops]..sort()), reason: '$tops');
    expect(tops.toSet(), hasLength(3));
  });
}
