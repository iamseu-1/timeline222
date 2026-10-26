import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:flutter_test/flutter_test.dart';

// 3판의 줄 쌓기가 2판의 굳은 자리와 1px도 다르지 않은지 월흔해의 모든 줄에서 확인한다.
// 저장소의 rows에는 '모두 켠 · 자동 밀도 · 접힘 없음'에서 지금 연표가 낸 값(height · band_top · band_h · dyn_top ·
// lead_top · cab_top · text_top · text_lines · rail_top · organ_top)이 그대로 있다(계약 1절 · 6-5절).
// 여기서는 그 값을 읽지 않고 kind · phase · rank · cats · fig · dep · zones · hem으로 다시 쌓아 견준다.
//
// 굳은 값은 트랙의 위 여백(9)을 첫 줄의 몫에, 아래 여백을 마지막 줄의 몫에 넣은 셈이고(첫 줄의 band_top 27 = pad 9 + 탭 18),
// 다시 쌓기는 여백을 트랙 쪽에 둔다 — 그래서 트랙 안의 '절대 자리'로 견준다.
void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  final db = [File('../data/moonwake3i/archive.db'), File('../data/moonwake3h/archive.db'), File('../data/moonwake3-stack2/archive.db'), File('../data/moonwake3-stack/archive.db'), File('../data/moonwake3/archive.db'), File('../data/moonwake3-fold/archive.db')].where((f) => f.existsSync()).firstOrNull;
  final ready = dll.existsSync() && db != null;

  Future<SceneLayout> load(ArchiveEngine engine) async {
    await engine.start(db!.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    return SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map))..reduceMotion = true;
  }

  test('모두 켠 · 자동 밀도 · 접힘 없음에서 다시 쌓은 자리 = 내보낸 2판의 굳은 값', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db!.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final json = Map<String, dynamic>.from(answer['data'] as Map);
    final layout = SceneLayout.fromJson(json);
    expect(layout.detailed, isTrue, reason: '3판의 줄 값(kind …)이 있어야 다시 쌓는다');
    expect(layout.conditions, const ViewConditions(), reason: '모두 켠 · 자동 밀도');
    expect(layout.foldedRows, isEmpty);

    final tracks = (json['tracks'] as List).toList()..sort((a, b) => (a['ord'] as int).compareTo(b['ord'] as int));
    int checked = 0;
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i] as Map<String, dynamic>;
      final rows = t['rows'] as List;
      if (layout.isBoardTrack(i)) {
        expect(layout.trackTop(i), -1, reason: '켜지 않은 판 트랙은 기본 배치에 없다');
        expect(layout.trackHeight(i), 0);
        for (final r in rows) {
          expect(layout.isVisible(r['id'] as int), isFalse);
        }
        continue;
      }
      final base = layout.trackTop(i);
      double cum = 0; // 굳은 값의 셈에서 트랙 안의 자리
      for (final raw in rows) {
        final r = Map<String, dynamic>.from(raw as Map);
        final row = r['id'] as int;
        // 켜지 않은 변형의 줄(소속 펼치기 · 대범위가 만든 줄)은 기본 보기에 없다 — 굳은 값도 그 변형 상태의 것이라 견주지 않는다.
        if (((r['variant'] ?? 0) as num) != 0) continue;
        final at = layout.rowTop(row) - base; // 다시 쌓기에서 트랙 안의 자리
        final geo = layout.geo(row);
        final where = '트랙 ${t['name']} · 줄 $row';
        void same(String key, double mine) {
          final baked = (r[key] as num).toDouble();
          if (baked < 0) {
            expect(mine, -1, reason: '$where의 $key은 없는 단이다');
            return;
          }
          expect(at + mine, baked + cum, reason: '$where의 $key');
        }

        same('band_top', geo.bandTop);
        same('dyn_top', geo.dynastyTop);
        same('lead_top', geo.leaderTop);
        same('cab_top', geo.cabinetTop);
        same('text_top', geo.textTop);
        same('rail_top', geo.railTop);
        same('organ_top', geo.organTop);
        expect(geo.bandHeight, (r['band_h'] as num).toDouble(), reason: '$where의 band_h');
        expect(geo.textLines, r['text_lines'] as int, reason: '$where의 text_lines');
        cum += (r['height'] as num).toDouble();
        checked++;
      }
      // 트랙 높이 = 굳은 값의 합(위 여백은 첫 줄의 몫에, 아래 여백은 마지막 줄의 몫에 들어 있다). 적어도 34.
      expect(layout.trackHeight(i), cum < G.folded ? G.folded : cum, reason: '${t['name']}의 트랙 높이');
    }
    expect(checked, greaterThanOrEqualTo(40), reason: '월흔해의 모든 줄을 견줬다');
  }, skip: ready ? false : '자료 처리부 DLL 또는 월흔해 3판 저장소가 없습니다');

  test('빽빽하게 · 넉넉하게는 글줄과 인물 단만 달라지고 나머지 차례는 그대로다', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db!.absolute.path);
    final answer = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map));
    // 밀도는 현재 기본 판의 줄을 다시 쌓는다. 켜지 않은 판 · 소속 · 대범위 변형의 줄은
    // 굳은 좌표를 보관만 하므로 textLines를 밀도 값으로 바꾸지 않고, 계속 숨겨져 있어야 한다.
    final baseRows = [for (int r = 0; r < layout.rowCount; r++) if (layout.spec(r)!.variant == 0) r];
    final inactiveRows = [for (int r = 0; r < layout.rowCount; r++) if (layout.spec(r)!.variant != 0) r];
    expect(baseRows.length, greaterThanOrEqualTo(40), reason: '월흔해의 기본 줄을 모두 비교한다');
    void sameVisibility() {
      for (final r in baseRows) {
        expect(layout.isVisible(r), isTrue, reason: '밀도를 바꿔도 기본 줄 $r은 보인다');
      }
      for (final r in inactiveRows) {
        expect(layout.isVisible(r), isFalse, reason: '밀도를 바꿔도 비활성 변형 줄 $r은 숨긴다');
        expect(layout.rowTop(r), -1);
      }
      for (int i = 0; i < layout.tracks.length; i++) {
        if (layout.isBoardTrack(i)) {
          expect(layout.trackTop(i), -1);
          expect(layout.trackHeight(i), 0);
        }
      }
    }
    sameVisibility();
    final auto = [for (final r in baseRows) layout.geo(r).height];
    layout.setConditions(const ViewConditions(density: 1));
    layout.finishFlow();
    sameVisibility();
    final dense = [for (final r in baseRows) layout.geo(r).height];
    expect(dense.reduce((a, b) => a + b), lessThan(auto.reduce((a, b) => a + b)), reason: '빽빽하게는 글줄 하나 · 시기 · 지위 단이 빠져 더 낮다');
    for (final r in baseRows) {
      expect(layout.geo(r).textLines, 1, reason: '빽빽하게의 기본 줄 $r의 글줄은 늘 하나');
    }
    layout.setConditions(const ViewConditions());
    layout.finishFlow();
    sameVisibility();
    expect([for (final r in baseRows) layout.geo(r).height], auto, reason: '자동으로 돌아오면 같은 값');
  }, skip: ready ? false : '자료 처리부 DLL 또는 월흔해 3판 저장소가 없습니다');

  // ---- 통합 공용 기하의 웹 실측과 나란히(2026-10-13 · 단 20/22/21 · 탭 18 · 조감 a/b 21) ----
  //
  // 지금 연표는 트랙 안의 줄을 `rowGap`(위 틈) + `rowHs`(줄 높이)로 적고, 여기서는 그 둘을 '줄의 몫'(geo.height) 하나로
  // 들고 다닌다. 옮겨 보는 식은 `rowGap = geo.bandTop` · `rowHs = geo.height − geo.bandTop` · `rowTop = 줄의 몫의 위 + bandTop`이다.
  group('통합 공용 기하의 웹 실측과 대조', () {
    late ArchiveEngine engine;
    late SceneLayout layout;
    late TrackInfo glass; // 유리해안(줄 20 · 민족 묶음이 줄 1~16)

    setUp(() async {
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      layout = await load(engine);
      glass = layout.tracks[0];
    });
    tearDown(() => engine.close());

    double rowTopIn(int track, int row) => layout.rowTop(row) - layout.trackTop(track) + layout.geo(row).bandTop;
    double rowHeight(int row) => layout.geo(row).height - layout.geo(row).bandTop;
    double rowGap(int row) => layout.geo(row).bandTop;

    test('트랙끼리는 틈 없이 이어 쌓인다 — 1px 테는 트랙 높이 안에 든다(명세 05 1.2 · 실측 9.2)', () {
      // 지금 연표의 `_modelTops`는 `total += tr.height`로 쌓고, 실측(접힌-트랙-전체)에서도 34px짜리가 469 → 503 → 537이다.
      // 트랙 사이에 1px을 더하면 트랙 하나마다 1px씩 밀려 먼 줄에서 몇 px까지 벌어진다.
      double at = 0;
      for (int i = 0; i < layout.tracks.length; i++) {
        if (layout.isBoardTrack(i)) {
          expect(layout.trackTop(i), -1);
          expect(layout.trackHeight(i), 0);
          continue;
        }
        expect(layout.trackTop(i), at, reason: '${layout.tracks[i].name}의 위');
        at += layout.trackHeight(i);
      }
      expect(layout.totalHeight, at);
      // 같은 월흔해를 현재 웹 _layoutTrack으로 독립 추출한 `전체`의 트랙 높이.
      expect([for (int i = 0; i < 5; i++) layout.trackHeight(i)], [4098, 696, 682, 682, 1458]);
      expect([for (int i = 0; i < 5; i++) layout.trackTop(i)], [0, 4098, 4794, 5476, 6158]);
    });

    test('장면 `전체`의 줄 자리 · 높이 · 틈(자동 밀도 · 접힘 없음)', () {
      expect([for (int r = 0; r < 20; r++) rowTopIn(0, r)], [27, 212, 1037, 1208, 1379, 1550, 1721, 1892, 2063, 2234, 2405, 2576, 2747, 2918, 3089, 3260, 3431, 3602, 3773, 3944]);
      expect([for (int r = 0; r < 20; r++) rowHeight(r)], [145, 799, ...List.filled(18, 145)]);
      expect([for (int r = 0; r < 20; r++) rowGap(r)], [18, 40, ...List.filled(18, 26)], reason: '첫 줄 0+탭 18 · 민족 경계 8+14+18 · 그 밖 8+18');
      final obsidian = layout.tracks[1].firstRow; // 흑요산맥(유리해안 뒤 — 변형이 만든 줄이 유리해안의 목록 끝에 붙어 번호가 밀린다)
      expect([for (int r = obsidian; r < obsidian + 2; r++) rowHeight(r)], [166, 454], reason: '흑요산맥은 줄이 둘이라 글줄 2');
    });

    test('실측 9.2 — 모든 트랙을 접으면 34px씩 이어 쌓이고 가는 막대는 5 · 13 · 21', () {
      layout.foldAll(true);
      expect(layout.allFolded, isTrue);
      expect([for (int i = 0; i < 4; i++) layout.trackTop(i)], [0, 34, 68, 102]);
      final baseTracks = [for (int i = 0; i < layout.tracks.length; i++) if (!layout.isBoardTrack(i)) i];
      expect(baseTracks, hasLength(12), reason: '월흔해 기본 트랙은 열둘, 켜지 않은 판은 별도');
      expect([for (final i in baseTracks) layout.trackHeight(i)], everyElement(34));
      for (int i = 0; i < layout.tracks.length; i++) {
        if (layout.isBoardTrack(i)) expect(layout.trackHeight(i), 0);
      }
      expect(layout.totalHeight, 34 * baseTracks.length);
      expect([layout.miniTop(0), layout.miniTop(1), layout.miniTop(2)], [5, 13, 21]);
      expect(layout.isVisible(0), isFalse);
      expect(layout.rowTop(0), -1);

      // 같은 상태 + 조감 a: 트랙 22 · 막대 474.5 / 478.5 / 482.5(트랙 위 469).
      layout.setConditions(const ViewConditions(density: 2));
      expect([for (int i = 0; i < 4; i++) layout.trackTop(i)], [0, 22, 44, 66]);
      expect(layout.trackHeight(0), 22);
      expect([layout.miniTop(0), layout.miniTop(1), layout.miniTop(2)], [5.5, 9.5, 13.5]);
      expect(layout.miniHeight, 3);
    });

    test('실측 9.3 — 유리해안의 민족을 접으면 20줄이 5줄이 되고 틈이 [18, 22, 26, 26, 26]가 된다', () {
      final people = glass.groups.firstWhere((g) => g.name == '월흔해의 백성');
      expect(people.firstRow, 1);
      expect(people.rowCount, 16);
      expect(layout.foldGroup(glass, people, true), isTrue);
      expect(layout.isGroupFolded(people), isTrue);
      expect(layout.visibleRowCount(0), 5, reason: '20줄 가운데 16줄이 한 줄로');
      expect(layout.mergedGroups, {1: 17});

      final shown = [for (int r = 0; r < 20; r++) if (layout.isVisible(r)) r];
      expect(shown, [0, 1, 17, 18, 19]);
      expect([for (final r in shown) rowGap(r)], [18, 22, 26, 26, 26]);
      expect(rowHeight(1), 30, reason: '접힌 민족 줄은 G.foldedGroup 30 · 탭 0');
      expect(layout.tabOf(1), 0);
      expect(layout.nameSize(0), 13.5, reason: '줄이 여섯 이하가 되어 자동 밀도의 글줄이 둘 — --nameSize 12.5 → 13.5');
      expect(layout.geo(0).textLines, 2);

      // 민족을 접으면 그 줄들의 정권 · 사건이 빠져 **트랙 단위 값**을 다시 셈한다(계약 3절 끝):
      // 기관 칸과 그 앞 틈(20 + 3)이 빠지고 기간 막대가 3단 → 2단(7)으로 줄어, 같은 글줄 수의 띠가 30px 낮아진다.
      expect([layout.railLevelsOf(0), layout.organOf(0)], [2, false], reason: '접힌 뒤 보이는 줄에는 기관도 3단 막대도 없다');
      expect(rowHeight(0), 136);
      expect([for (final r in shown) rowHeight(r)], [136, 30, 136, 136, 136], reason: '현재 웹의 민족 접힘 rowHs');
      expect([for (final r in shown) rowTopIn(0, r)], [27, 185, 241, 403, 565], reason: '현재 웹의 민족 접힘 rowTop');
      expect(layout.trackHeight(0), 710, reason: '현재 웹의 민족 접힘 트랙 높이');

      expect(layout.foldGroup(glass, people, false), isTrue);
      expect(layout.visibleRowCount(0), 20);
      expect([layout.railLevelsOf(0), layout.organOf(0)], [3, true], reason: '펴면 줄 1의 기관 칸 · 3단 막대가 돌아온다');
      expect(rowHeight(0), 145);
    });

    test('트랙 값(기관 칸 · 기간 막대 단 수)은 보이는 줄들의 최댓값이다(계약 3절 끝)', () {
      // 유리해안에서 그 값을 가진 줄은 줄 1 하나뿐이다 — 그 줄만 감추면 트랙 값이 내려간다.
      expect([layout.railLevelsOf(0), layout.organOf(0)], [3, true]);
      expect(layout.spec(1)!.rail, 3, reason: '줄 단위 트랙 값이 실린 저장소가 필요하다 — data/moonwake3-stack2를 다시 만든다(계약 3-3절)');
      expect(layout.spec(1)!.organ, isTrue);
      expect(layout.spec(0)!.rail, 0, reason: '−1이면 값이 실리지 않은 옛 저장소다');
      expect(layout.spec(0)!.organ, isFalse);
      // 트랙을 접어도 트랙 값은 그대로다(줄을 감추는 것이 아니라 트랙째 줄이는 것이라 띠를 그리지 않는다).
      layout.foldTrack(glass.id, true);
      expect([layout.railLevelsOf(0), layout.organOf(0)], [3, true]);
    });

    test('실측 9.4 — 조감 a는 줄 21 · 트랙 548, 조감 c는 줄 8 · 트랙 288', () {
      for (final (shape, band, glassHeight, second) in [(BirdShape.a, 21.0, 548.0, 62.0), (BirdShape.c, 8.0, 288.0, 36.0)]) {
        layout.setConditions(ViewConditions(density: 2, birdShape: shape));
        expect(layout.bird, isTrue);
        expect([for (int r = 0; r < 20; r++) rowHeight(r)], everyElement(band), reason: '조감 $shape의 줄 높이');
        expect([for (int r = 0; r < 20; r++) rowGap(r)], [0, 12, ...List.filled(18, 6)], reason: '첫 줄 0 · 민족 경계 6+6 · 그 밖 6 · 책갈피 탭 없음');
        expect(layout.trackHeight(0), glassHeight, reason: '유리해안(위아래 여백 4)');
        expect(layout.trackHeight(1), second, reason: '흑요산맥');
        expect(rowTopIn(0, 0), 4);
        expect(rowTopIn(0, 1), 4 + band + 12);
        final g = layout.geo(1);
        expect([g.dynastyTop, g.leaderTop, g.cabinetTop, g.railTop, g.organTop, g.figTop, g.depTop, g.zoneTop, g.hemTop], everyElement(-1.0));
        expect(g.textLines, 1);
        expect(g.lineH, band, reason: '글줄 하나가 띠 전체');
        expect([layout.nameSize(1), layout.eventSize(1)], [10.5, 10]);
        expect([layout.foldedHeight, layout.foldedGroupHeight], [22, 14]);
      }
    });

    test('실측 9.7 — 밀도별 줄 높이와 글자 크기(유리해안 · 줄 1)', () {
      const want = {
        -1: (2, 12.0, 13.5, 845.0),
        0: (1, 11.5, 12.5, 799.0),
        1: (1, 11.5, 12.5, 560.0),
      };
      for (final entry in want.entries) {
        final (lines, event, name, height) = entry.value;
        layout.setConditions(ViewConditions(density: entry.key));
        expect(layout.baseLines(1), lines, reason: '밀도 ${entry.key}의 글줄 수');
        expect(layout.eventSize(1), event, reason: '밀도 ${entry.key}의 사건 글자');
        expect(layout.nameSize(1), name, reason: '밀도 ${entry.key}의 줄 이름 글자');
        expect(rowHeight(1), height, reason: '밀도 ${entry.key}의 줄 1 높이');
      }
      // 조감: 줄 21(모양 a) — 트랙 단위 값과 무관하게 띠 하나뿐이다.
      layout.setConditions(const ViewConditions(density: 2));
      expect(rowHeight(1), 21);
    });

    test('트랙 끔(필터)은 줄이 통째로 빠지고 아래가 올라온다 — 흐르지 않는다', () async {
      final answer = await engine.call({'op': 'layout'});
      final l = SceneLayout.fromJson(Map<String, dynamic>.from(answer['data'] as Map)); // 움직임 줄이기를 켜지 않은 판
      expect(l.offTrack(glass.id, true), isTrue);
      expect(l.flowing, isFalse, reason: '자료집 끔과 같은 길 — 흐르지 않는다');
      expect(l.trackTop(0), -1);
      expect(l.trackHeight(0), 0);
      expect(l.rowTop(0), -1);
      expect(l.trackTop(1), 0);
      expect(l.totalHeight, layout.totalHeight - layout.trackHeight(0));
      expect(l.foldTrack(layout.tracks[1].id, true), isTrue);
      expect(l.flowing, isTrue, reason: '접기는 흐른다');
    });
  }, skip: ready ? false : '자료 처리부 DLL 또는 월흔해 3판 저장소가 없습니다');
}
