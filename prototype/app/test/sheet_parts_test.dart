import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/shell/line_icon.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 서고 시트 부품(리메이크 4단계 · 틀의 시트와 창 걸음 1)의 토큰과 꼴을 본다 — 감독 고름 G5 #9 다듬기 판:
// 먹 여섯은 흰 종이 위의 불투명 색 · 뚜껑 22 · 흰 라벨 16 · 고른 테 1.5 · 끈 칩은 실선(점선 아님) · 테는 반 픽셀 자리 · 폴더 탭은 맨 글(흰 라벨 없음).
// 걸음 2 ~ 9가 창마다 바꿔 끼운다(걸음 5 — DLC 관리의 꼬리표 + 글 한 줄 · 상자 fill · 종이 단추 읽기 글을 더함).

const _peri = Color(0xffabb3c9), _butter = Color(0xffd7c18e);

Widget _host(Widget child, {double width = 420}) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(40), child: SizedBox(width: width, child: child))),
  ),
);

void main() {
  group('먹 여섯', () {
    test('흰 종이 위의 불투명 색 — 목업 kit.js ink(a)와 같은 셈', () {
      final tokens = [SheetLook.ink85, SheetLook.ink60, SheetLook.ink45, SheetLook.ink25, SheetLook.ink12, SheetLook.ink4];
      expect(SheetLook.inkSteps, [.85, .60, .45, .25, .12, .04]);
      for (var i = 0; i < tokens.length; i++) {
        final a = SheetLook.inkSteps[i], c = tokens[i];
        expect(c.toARGB32() >>> 24, 0xff, reason: '먹 ${a * 100}은 불투명');
        // kit.js: mix('#000000', a, '#ffffff') = 채널마다 Math.round(255 × (1 − a))
        final v = (255 * (1 - a)).round();
        expect(c.toARGB32(), 0xff000000 | v << 16 | v << 8 | v, reason: '먹 ${a * 100}');
        expect(SheetLook.inkOf(a), c);
        expect(c.toARGB32(), mixSrgb(0xff000000, 0xffffffff, a));
      }
      expect([for (final c in tokens) c.toARGB32()], [0xff262626, 0xff666666, 0xff8c8c8c, 0xffbfbfbf, 0xffe0e0e0, 0xfff5f5f5]);
    });

    test('나라 색 섞임 — 꼬리표 24 · 84 · 22 · 45 / 나라 시트 9 · 55 · 25', () {
      final c = _peri.toARGB32();
      expect(SheetLook.tagFill(_peri).toARGB32(), mixSrgb(c, 0xffffffff, .24));
      expect(SheetLook.tagEdge(_peri).toARGB32(), mixOklab(c, 0xff000000, .84));
      expect(SheetLook.tagInk(_peri).toARGB32(), mixSrgb(c, 0xff000000, .22));
      expect(SheetLook.nameInk(_peri).toARGB32(), mixSrgb(c, 0xff000000, .45));
      expect(SheetLook.folderFill(_peri).toARGB32(), mixSrgb(c, 0xffffffff, .09));
      expect(SheetLook.folderEdge(_peri).toARGB32(), mixOklab(c, 0xffffffff, .55));
      expect(SheetLook.folderInk(_peri).toARGB32(), mixSrgb(c, 0xff000000, .25));
    });
  });

  group('치수 — 감독 고름', () {
    test('뚜껑 22 · 흰 라벨 16 · 고른 테 1.5 · 꼬리표 · 칩 · 열쇠표 · 실', () {
      expect(SheetLook.boxLid, 22);
      expect(SheetLook.boxLabel, 16);
      expect(SheetLook.pickWidth, 1.5);
      expect(SheetLook.pickInk, const Color(0xff000000));
      expect(SheetLook.folderTab, 20);
      expect(SheetLook.folderTabText, 12);
      expect(SheetLook.folderRadius, 10);
      expect(SheetLook.folderRim, 6);
      expect(SheetLook.boxChamfer, 6);
      expect(SheetLook.boxInset, 10);
      expect([SheetLook.tagChamfer, SheetLook.tagRound, SheetLook.holeRadius, SheetLook.holeLeft, SheetLook.holeLeftRound, SheetLook.holeTop, SheetLook.diamondHalf], [5, 12, 2.5, 7, 9, 6, 3]);
      expect([SheetLook.paperChamfer, SheetLook.chip, SheetLook.keyTag, SheetLook.keyRound, SheetLook.keyHole, SheetLook.keyText], [3, 24, 12, 6, 1.5, 8.5]);
      expect([SheetLook.threadInk, SheetLook.threadWidth, SheetLook.knotRadius], [SheetLook.ink45, 1, 1.5]);
      // 뚜껑 밑선은 상자 윗변에서 22.5(반 픽셀) — 실의 첫 매듭이 앉는 자리.
      expect(sheetLidLineY(0), 22.5);
      // 고른 단추 · 사슬 고리 = 먹 100 · 1.5.
      final picked = SheetPaperButton.shapeOf(selected: true);
      expect(picked.stroke, SheetLook.ink100);
      expect(picked.strokeWidth, 1.5);
    });

    testWidgets('상자: 뚜껑 22 + 밑선 1 아래에 몸 · 흰 라벨 키 16(위 3)', (tester) async {
      await tester.pumpWidget(_host(const SheetBox(label: '트랙', count: '4', child: SizedBox(height: 30))));
      final box = tester.getRect(find.byType(SheetBox));
      final label = tester.getRect(find.byType(SheetLidLabel));
      expect(label.height, 16);
      expect(label.top - box.top, 3);
      expect(label.left - box.left, 10);
      final body = tester.getRect(find.byWidgetPredicate((w) => w is SizedBox && w.height == 30));
      expect(body.top - box.top, 22 + 1 + 10);
      expect(box.height, 23 + 10 + 30 + 10);
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('끈 칩 · 꺼 둔 줄은 흰 종이 + 먹 25 실선', () {
    test('점선이 아니다 — 점선은 대립 · 얹은 트랙만', () {
      final off = [
        SheetTagChip.shapeOf(_peri, on: false),
        SheetTagChip.shapeOf(_peri, on: false, kind: SheetTagKind.key),
        SheetTagChip.shapeOf(_peri, on: false, kind: SheetTagKind.plain),
        SheetKeyToggle.shapeOf(on: false),
        SheetDotChip.shapeOf(_peri, on: false),
        SheetScopeChip.shapeOf(_butter, on: false),
        SheetTag.row(off: true),
      ];
      for (final s in off) {
        expect(s.dash, isNull);
        expect(s.stroke, SheetLook.ink25);
        expect(s.fill, SheetLook.paper);
      }
      // 끈 칩의 글은 먹 45 · 구멍 테도 25.
      expect(SheetTagChip.inkOf(_peri, on: false), SheetLook.ink45);
      expect(SheetTagChip.shapeOf(_peri, on: false).holeStroke, SheetLook.ink25);
      // 켠 칩은 그림판 그대로(칠 24 · 테 84) — 역시 실선.
      final on = SheetTagChip.shapeOf(_peri, on: true);
      expect(on.fill, SheetLook.tagFill(_peri));
      expect(on.stroke, SheetLook.tagEdge(_peri));
      expect(on.dash, isNull);
      // 대립만 점선 '3 2'.
      expect(SheetTag.colored(_peri, rival: true).dash, [3, 2]);
      expect(SheetTag.colored(_peri).dash, isNull);
    });

    testWidgets('끈 칩을 그리면 테가 먹 25 실선 한 길', (tester) async {
      await tester.pumpWidget(_host(const Row(children: [SheetTagChip(label: '청림', color: _peri, on: false)])));
      await tester.pumpAndSettle();
      final chip = tester.renderObject(find.byType(SheetTagChip));
      // 칠(흰 종이) → 테(먹 25 · 실선 — 테 자리를 꽉 칠한 고리 하나: 테 화소는 들고 안쪽은 빔) → 구멍(종이 · 테 25)
      expect(chip, paints..path(color: SheetLook.paper)..path(color: SheetLook.ink25, includes: const [Offset(30, .5), Offset(30, 23.5), Offset(.5, 12)], excludes: const [Offset(30, 1.5), Offset(30, 12)])
        ..circle(color: SheetLook.paper)..circle(color: SheetLook.ink25));
    });
  });

  group('테는 반 픽셀 자리', () {
    test('꼬리표 · 이름 종이 · 상자 · 뚜껑의 길이 바깥 상자 안쪽 .5를 지남', () {
      const box = Rect.fromLTWH(10, 20, 100, 24);
      for (final kind in SheetTagKind.values) {
        expect(sheetTagPath(box, kind).getBounds(), const Rect.fromLTRB(10.5, 20.5, 109.5, 43.5), reason: '$kind');
      }
      expect(sheetPaperPath(box).getBounds(), const Rect.fromLTRB(10.5, 20.5, 109.5, 43.5));
      expect(sheetBoxPath(const Rect.fromLTWH(0, 0, 200, 80)).getBounds(), const Rect.fromLTRB(.5, .5, 199.5, 79.5));
      expect(sheetLidPath(const Rect.fromLTWH(0, 0, 200, 80)).getBounds(), const Rect.fromLTRB(.5, .5, 199.5, 22.5));
      // 구멍 — 다스림 7 · 둥근 끝 9 · 위 6(테 자리에서) · 꼬리 마름모 — 오른쪽 7.
      expect(sheetHoleAt(box, SheetTagKind.cham), const Offset(17.5, 26.5));
      expect(sheetHoleAt(box, SheetTagKind.key), const Offset(19.5, 26.5));
      expect(sheetDiamondAt(box), const Offset(102.5, 26.5));
      // 둥근 끝의 반지름은 키의 반까지(24 칩 → 11.5).
      final key = sheetTagPath(box, SheetTagKind.key);
      expect(key.contains(const Offset(11, 21)), isFalse);
      expect(key.contains(const Offset(22.5, 32)), isTrue);
    });

    test('테는 획이 아니라 고리 칠 — 곧은 테는 화소 한 줄을 꽉, 귀의 대각선도 굵기 1', () {
      // 실제 앱(Windows GPU 그리기)에서 꺾인 길의 1px 획은 이음 뒤 한동안 반만 칠해져 옅었다(걸음 2) — 그래서 고리를 칠한다.
      const box = Rect.fromLTWH(10, 20, 100, 24);
      for (final kind in [SheetTagKind.cham, SheetTagKind.key]) {
        final ring = sheetTagRing(box, kind);
        expect(ring.fillType, PathFillType.evenOdd);
        for (final p in const [Offset(60, 20.5), Offset(60, 43.5), Offset(10.5, 32), Offset(109.5, 32)]) {
          expect(ring.contains(p), isTrue, reason: '$kind $p 테 화소');
        }
        for (final p in const [Offset(60, 21.5), Offset(60, 19.5), Offset(60, 32), Offset(11.5, 32)]) {
          expect(ring.contains(p), isFalse, reason: '$kind $p 테 밖');
        }
      }
      // 모따기 5의 대각선(가운데 줄 x + y = 36): 줄 위는 들고 1.41 떨어진 곳은 빈다.
      final cham = sheetTagRing(box, SheetTagKind.cham);
      expect(cham.contains(const Offset(13, 23)), isTrue);
      expect(cham.contains(const Offset(14, 24)), isFalse);
      // 상자 고리(네 귀 모따기 6).
      final boxRing = sheetBoxRing(const Rect.fromLTWH(0, 0, 200, 80));
      expect(boxRing.contains(const Offset(100, 79.5)), isTrue);
      expect(boxRing.contains(const Offset(100, 78.5)), isFalse);
      expect(boxRing.contains(const Offset(199.5, 40)), isTrue);
      expect(boxRing.getBounds(), const Rect.fromLTRB(0, 0, 200, 80));
    });

    testWidgets('칩 · 단추의 바깥 상자는 정수 폭 · 키', (tester) async {
      await tester.pumpWidget(_host(const Wrap(spacing: 6, children: [
        SheetTagChip(label: '하연', color: _butter, on: true),
        SheetKeyToggle(label: '승계선', on: true),
        SheetDotChip(label: '정치', color: _peri, on: true),
        SheetScopeChip(label: '아홉 불씨 연방', color: _butter, on: true),
        SheetPaperButton(label: '같은 해 보기'),
        SheetKeyLabel(parts: [(text: '아들', bold: true, color: SheetLook.ink85), (text: '세습', bold: false, color: SheetLook.ink60)]),
      ])));
      await tester.pumpAndSettle();
      for (final type in [SheetTagChip, SheetKeyToggle, SheetDotChip, SheetScopeChip, SheetPaperButton]) {
        final s = tester.getSize(find.byType(type));
        expect(s.height, 24, reason: '$type');
        expect(s.width, s.width.roundToDouble(), reason: '$type 폭');
      }
      // 열쇠표: 테 가운데끼리 12 → 바깥 13.
      expect(tester.getSize(find.byType(SheetKeyLabel)).height, 13);
    });
  });

  group('폴더 탭은 맨 글 — 흰 라벨은 상자 뚜껑에만', () {
    testWidgets('탭 글에는 흰 라벨이 없고 상자 이름에는 있다', (tester) async {
      await tester.pumpWidget(_host(
        const SheetFolder(label: '필터 · 표시', count: '12', child: SheetBox(label: '트랙', child: SizedBox(height: 24))),
        width: 500,
      ));
      final tabText = find.text('필터 · 표시');
      expect(tabText, findsOneWidget);
      expect(find.ancestor(of: tabText, matching: find.byType(SheetLidLabel)), findsNothing);
      expect(find.ancestor(of: tabText, matching: find.byType(SheetFolderTab)), findsOneWidget);
      expect(find.ancestor(of: find.text('트랙'), matching: find.byType(SheetLidLabel)), findsOneWidget);
      // 맨 글 12 굵게 먹 85 · 수 12 보통 먹 45.
      final style = tester.widget<Text>(tabText).style!;
      expect([style.fontSize, style.fontWeight, style.color], [12, FontWeight.w700, SheetLook.ink85]);
      final count = tester.widget<Text>(find.text('12')).style!;
      expect([count.fontSize, count.fontWeight, count.color], [12, FontWeight.w400, SheetLook.ink45]);
      // 탭 키 20 · 왼쪽 들임 12 · 몸통은 그 아래부터.
      final folder = tester.getRect(find.byType(SheetFolder)), tab = tester.getRect(find.byType(SheetFolderTab));
      expect(tab.height, 20);
      expect(tab.left - folder.left, 12);
      expect(tester.getRect(find.byType(SheetBox)).top - folder.top, 20 + 14);
      expect(folder.width, folder.width.roundToDouble());
    });

    testWidgets('나라 시트 — 칠 9 · 테 55 · 탭 글 25% + 먹 · 닫기 탭', (tester) async {
      var closed = 0;
      await tester.pumpWidget(_host(SheetFolder(label: '승계표', color: _peri, onClose: () => closed++, child: const SizedBox(height: 40))));
      final style = tester.widget<Text>(find.text('승계표')).style!;
      expect(style.color, SheetLook.folderInk(_peri));
      final tabs = tester.widgetList<SheetFolderTab>(find.byType(SheetFolderTab)).toList();
      expect(tabs.length, 2);
      expect(tabs.first.fill, SheetLook.folderFill(_peri));
      expect(tabs.first.edge, SheetLook.folderEdge(_peri));
      await tester.tap(find.bySemanticsLabel('닫기'));
      await tester.pumpAndSettle();
      expect(closed, 1);
      // 닫기 탭은 오른쪽 끝(테 자리를 이름 탭과 맞추려 13 들임) · 폭 44.
      final folder = tester.getRect(find.byType(SheetFolder)), close = tester.getRect(find.byType(SheetFolderTab).last);
      expect(folder.right - close.right, 13);
      expect(close.width, 44);
    });
  });

  group('실 기둥', () {
    testWidgets('가로대 갈래: 첫 매듭은 뚜껑 밑선 · 줄마다 위 가로대에서 제 구멍으로', (tester) async {
      Widget row(SheetTagKind kind) => SheetTag(shape: SheetTag.row(kind: kind), height: 24, child: const SizedBox(width: 300));
      await tester.pumpWidget(_host(SheetBox(
        label: '객체',
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 9),
        child: SheetThreadColumn(gap: 13, rails: true, kinds: const [SheetTagKind.cham, SheetTagKind.key], children: [row(SheetTagKind.cham), row(SheetTagKind.key)]),
      )));
      final column = tester.renderObject(find.byType(SheetThreadColumn));
      final w = tester.getSize(find.byType(SheetThreadColumn)).width;
      expect(
        column,
        paints
          // 첫 줄: 뚜껑 밑선(기둥 위 6.5)의 매듭 → 구멍(7.5, 6.5) 위 3까지
          ..line(p1: const Offset(7.5, -5), p2: const Offset(7.5, 3.5), color: SheetLook.ink45)
          ..circle(x: 7.5, y: -6.5, radius: 1.5, color: SheetLook.ink45)
          // 둘째 줄(위 37): 가로대 30.5(먹 12 · 양옆 8.5 더) → 둥근 끝 구멍(9.5, 43.5)
          ..line(p1: const Offset(-8.5, 30.5), p2: Offset(w + 8.5, 30.5), color: SheetLook.ink12)
          ..line(p1: const Offset(9.5, 32), p2: const Offset(9.5, 40.5), color: SheetLook.ink45)
          ..circle(x: 9.5, y: 30.5, radius: 1.5, color: SheetLook.ink45),
      );
    });

    testWidgets('기둥 갈래: 매듭 하나에서 마지막 구멍까지 곧게 · 작은 묶음 앞은 더 띄움', (tester) async {
      Widget row() => SheetTag(shape: SheetTag.row(), height: 24, child: const SizedBox(width: 300));
      await tester.pumpWidget(_host(SheetBox(
        label: '보기',
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: SheetThreadColumn(gap: 4, breakBefore: const {2}, children: [row(), row(), row()]),
      )));
      final column = tester.renderObject(find.byType(SheetThreadColumn));
      // 줄 위: 0 · 28 · 62(28 + 24 + 4 + 6) → 마지막 구멍 68.5
      expect(tester.getSize(find.byType(SheetThreadColumn)).height, 62 + 24);
      expect(column, paints..line(p1: const Offset(7.5, -7), p2: const Offset(7.5, 65.5), color: SheetLook.ink45)..circle(x: 7.5, y: -8.5, radius: 1.5));
    });
  });

  group('누름 · 고르기', () {
    testWidgets('칩 · 사슬 · 고르는 칸을 누르면 제 값이 온다', (tester) async {
      var toggled = 0, picked = '', opened = 0;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => Wrap(spacing: 6, runSpacing: 6, children: [
          SheetTagChip(label: '하연', color: _butter, on: true, onTap: () => toggled++),
          SheetChain<String>(items: const [('all', '모든 사건'), ('mid', '보통 이상'), ('top', '중요 사건만')], value: 'mid', onSelect: (v) => picked = v),
          SheetSelect(title: '관점', value: '기본', onTap: () => opened++),
        ]),
      ), width: 800));
      await tester.tap(find.text('하연'));
      await tester.tap(find.text('중요 사건만'));
      await tester.tap(find.text('기본'));
      await tester.pumpAndSettle();
      expect([toggled, picked, opened], [1, 'top', 1]);
      // 고른 고리만 먹 100 · 글도 먹 100.
      expect(tester.widget<Text>(find.text('보통 이상')).style!.color, SheetLook.ink100);
      expect(tester.widget<Text>(find.text('모든 사건')).style!.color, SheetLook.ink60);
    });

    testWidgets('고른 테는 바깥 2에 먹 100 · 1.5', (tester) async {
      await tester.pumpWidget(_host(const Row(children: [SheetPickRing(child: SizedBox(width: 120, height: 24))])));
      final ring = tester.renderObject(find.byType(SheetPickRing));
      // 굵기 1.5의 고리 — 가운데 줄(바깥 1.5)을 사이에 두고 .75씩.
      expect(ring, paints..path(color: SheetLook.ink100, includes: const [Offset(60, -1.5), Offset(60, -2.1), Offset(60, -.9)], excludes: const [Offset(60, -2.5), Offset(60, -.5), Offset(60, 12)]));
      final path = SheetPickRing.outsidePath(const Rect.fromLTWH(0, 0, 120, 24), SheetTagKind.cham);
      expect(path.getBounds(), const Rect.fromLTRB(-1.5, -1.5, 121.5, 25.5));
    });
  });

  group('걸음 5에 더한 것(DLC 관리)', () {
    testWidgets('꼬리표 + 글 한 줄: 들지 않는 꼬리표는 그리지 않고 글이 남는 폭 · 넉넉하면 모두', (tester) async {
      Widget tag(String s) => SizedBox(width: 60, height: 14, child: Text(s));
      Widget run(double width) => _host(SizedBox(height: 14, child: SheetFitRun(children: [tag('가'), tag('나'), tag('다'), tag('라'), const Text('담긴 것 글', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)])), width: width);
      await tester.pumpWidget(run(420));
      final wide = tester.renderObject<RenderSheetFitRun>(find.byType(SheetFitRun));
      expect(wide.shown, 4);
      final text = tester.getRect(find.text('담긴 것 글')), last = tester.getRect(find.text('라'));
      expect(text.left - (last.left + 60), SheetLook.dlcContentsGap, reason: '글은 마지막 꼬리표 뒤 6');
      expect(tester.getRect(find.text('나')).left - tester.getRect(find.text('가')).left, 60 + SheetLook.dlcMiniGap);
      await tester.pumpWidget(run(200));
      final narrow = tester.renderObject<RenderSheetFitRun>(find.byType(SheetFitRun));
      expect(narrow.shown, lessThan(4));
      expect(tester.takeException(), isNull, reason: '넘침 없음');
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.semantics.byLabel('가'), findsOne);
      expect(find.semantics.byLabel('라'), findsNothing, reason: '그리지 않은 꼬리표는 읽기에서도 빠진다');
      semantics.dispose();
    });

    testWidgets('상자 fill: 받은 키를 몸이 다 받는다 · 흰 종이 단추의 읽기 글', (tester) async {
      await tester.pumpWidget(_host(SizedBox(height: 200, child: SheetBox(label: '자세히', fill: true, child: Column(children: [Expanded(child: Container(key: const Key('몸'), color: SheetLook.ink4))])))));
      expect(tester.getSize(find.byKey(const Key('몸'))).height, 200 - (SheetLook.boxLid + 1) - 2 * SheetLook.boxInset);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(SheetPaperButton(label: '끄기', semantics: '설령 빙원 끄기', onTap: () {})));
      await tester.pump();
      expect(find.semantics.byLabel('설령 빙원 끄기'), findsOne);
      semantics.dispose();
    });
  });

  group('걸음 8에 더한 것(단체 계보)', () {
    testWidgets('누르는 나라 꼬리표 — 칠 24% · 테 84% + 먹 · 구멍 · 글은 구멍 뒤 7 · 올리면 칠에 먹 4% · 누르면 부름 · 읽기 글', (tester) async {
      var pressed = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(Row(children: [SheetTagButton(label: '갑 왕국', color: _peri, semantics: '갑 왕국 — 나라 상세', onTap: () => pressed++)])));
      final shape = SheetTagButton.shapeOf(_peri);
      expect((shape.kind, shape.fill, shape.stroke, shape.hole, shape.dash), (SheetTagKind.cham, SheetLook.tagFill(_peri), SheetLook.tagEdge(_peri), true, null));
      expect(SheetTagButton.shapeOf(_peri, hover: true).fill, Color.alphaBlend(const Color(0x0a000000), SheetLook.tagFill(_peri)));
      expect(SheetTagButton.shapeOf(_peri, kind: SheetTagKind.key).kind, SheetTagKind.key);
      final tag = tester.getRect(find.byType(SheetTagButton)), text = tester.getRect(find.text('갑 왕국'));
      expect(tag.height, SheetLook.chip);
      expect(text.left - tag.left, .5 + SheetLook.holeLeft + 7, reason: '글은 구멍 가운데 뒤 7');
      expect(tester.widget<Text>(find.text('갑 왕국')).style!.color, SheetLook.tagInk(_peri));
      await tester.tap(find.byType(SheetTagButton));
      expect(pressed, 1);
      expect(find.semantics.byLabel('갑 왕국 — 나라 상세'), findsOne);
      semantics.dispose();
    });
  });

  group('걸음 9에 더한 것(문서 창)', () {
    Finder paintOf(Type type) => find.descendant(of: find.byType(type), matching: find.byType(CustomPaint)).first;

    testWidgets('받침 카드: 카드(칠 24% · 테 84% 고리) 위 흰 종이(테 먹 25 고리) — 종이는 위 18 + 6 · 오른쪽 6 안 · 몸은 종이 테 안쪽', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(height: 200, child: SheetCard(color: _peri, child: SizedBox.expand(key: Key('몸'))))));
      final card = tester.getRect(find.byType(SheetCard));
      expect(SheetCard.cardRect(card.size), Rect.fromLTRB(6, 18, card.width, card.height));
      expect(SheetCard.pageRect(card.size), Rect.fromLTRB(0, 24, card.width - 6, card.height));
      // 테는 고리 칠 — 카드 오른쪽 테(w − .5)는 들고 그 안 1은 빔 · 종이 오른쪽 테(w − 6.5)도 같게.
      final w = card.width;
      expect(
        tester.renderObject(paintOf(SheetCard)),
        paints
          ..path(color: SheetLook.tagFill(_peri))
          ..path(color: SheetLook.tagEdge(_peri), includes: [Offset(w - .5, 100), Offset(100, 18.5)], excludes: [Offset(w - 1.5, 100), Offset(100, 19.5)])
          ..path(color: SheetLook.paper)
          ..path(color: SheetLook.ink25, includes: [Offset(w - 6.5, 100), Offset(100, 24.5), Offset(.5, 100)], excludes: [Offset(w - 7.5, 100), Offset(100, 25.5)]),
      );
      final body = tester.getRect(find.byKey(const Key('몸')));
      expect(body, Rect.fromLTRB(card.left + 1, card.top + 25, card.right - 7, card.bottom - 1));
      // 탭이 없으면 누를 곳도 없다(카드 윗변 자리 18은 그대로).
      expect(find.descendant(of: find.byType(SheetCard), matching: find.byType(GestureDetector)), findsNothing);
      expect(find.descendant(of: find.byType(SheetCard), matching: find.byType(LineIcon)), findsNothing);
    });

    testWidgets('이름 탭: 카드 오른쪽 테에서 10 안 · 키 18(카드 윗테를 덮어 한 장) · 맨 글 12 굵게 + 과녁 12 · 누르면 부름 · 풍선 · 읽기 글', (tester) async {
      var pressed = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(SizedBox(
        height: 200,
        child: SheetCard(color: _peri, tab: '갑 왕국', tabHint: '연표에서', tabSemantics: '연표에서 — 갑 왕국', onTab: () => pressed++, child: const SizedBox.expand()),
      )));
      final card = tester.getRect(find.byType(SheetCard)), tab = tester.getRect(find.byTooltip('연표에서'));
      expect(tab.right, card.right - SheetCard.tabInset);
      expect(tab.top, card.top);
      expect(tab.height, SheetCard.tabHeight + 2, reason: '탭 칠은 카드 윗테(18)를 덮고 그 밑 1까지');
      final text = tester.widget<Text>(find.text('갑 왕국')).style!;
      expect([text.fontSize, text.fontWeight, text.color], [12, FontWeight.w700, SheetLook.tagInk(_peri)]);
      final icon = tester.widget<LineIcon>(find.byType(LineIcon));
      expect((icon.glyph, icon.size, icon.color), (LineGlyph.locate, SheetCard.tabIcon, SheetLook.tagInk(_peri)));
      expect(tester.getTopLeft(find.text('갑 왕국')).dx - tab.left, SheetCard.tabLead);
      expect(tab.right - tester.getRect(find.byType(LineIcon)).right, SheetCard.tabTail);
      // 탭의 칠 · 테는 카드와 같은 빛깔.
      expect(tester.renderObject(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_CardTabPainter')), paints..path(color: SheetLook.tagFill(_peri))..rect(color: SheetLook.tagEdge(_peri)));
      await tester.tap(find.text('갑 왕국'));
      expect(pressed, 1);
      expect(find.semantics.byLabel('연표에서 — 갑 왕국'), findsOne);
      semantics.dispose();
    });

    testWidgets('주인이 없으면 먹 카드 — 칠 먹 4 · 테 먹 25 · 탭 글 먹 85', (tester) async {
      expect((SheetCard.fillOf(null), SheetCard.edgeOf(null), SheetCard.inkOf(null)), (SheetLook.ink4, SheetLook.ink25, SheetLook.ink85));
      expect((SheetCard.fillOf(_peri), SheetCard.edgeOf(_peri), SheetCard.inkOf(_peri)), (SheetLook.tagFill(_peri), SheetLook.tagEdge(_peri), SheetLook.tagInk(_peri)));
      await tester.pumpWidget(_host(const SizedBox(height: 120, child: SheetCard(tab: '대문', child: SizedBox.expand()))));
      expect(tester.renderObject(paintOf(SheetCard)), paints..path(color: SheetLook.ink4)..path(color: SheetLook.ink25)..path(color: SheetLook.paper)..path(color: SheetLook.ink25));
      expect(tester.widget<Text>(find.text('대문')).style!.color, SheetLook.ink85);
    });

    testWidgets('누르는 겉(SheetPress): 올리면 builder에 참 · 누르면 부름 · 읽기 글은 label 하나 · 누를 것이 없으면 올려도 거짓', (tester) async {
      var pressed = 0;
      final hovers = <bool>[];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(Column(children: [
        SheetPress(
          onTap: () => pressed++,
          label: '1 개요',
          hint: '풍선',
          builder: (hover) {
            hovers.add(hover);
            return SizedBox(height: 26, child: Text(hover ? '올림' : '그냥'));
          },
        ),
        SheetPress(builder: (hover) => SizedBox(height: 26, child: Text(hover ? '꺼진 올림' : '꺼짐'))),
      ])));
      expect(find.text('그냥'), findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('그냥')));
      await tester.pumpAndSettle();
      expect(find.text('올림'), findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.text('꺼짐')));
      await tester.pumpAndSettle();
      expect(find.text('꺼짐'), findsOneWidget, reason: '누를 것이 없으면 올려도 그대로');
      await tester.tap(find.text('그냥'));
      expect(pressed, 1);
      expect(find.byTooltip('풍선'), findsOneWidget);
      expect(find.semantics.byLabel('1 개요'), findsOne);
      semantics.dispose();
    });
  });
}
