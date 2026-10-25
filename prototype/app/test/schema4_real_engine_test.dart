import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_import.dart';

// 리메이크 3단계 과제 8 걸음 5 — 앱의 스키마 4 읽기(걸음 1 ~ 3)를 **진짜 자료 처리부(DLL)가 지은 저장소의 답**으로 대조한다.
//
// 왜: 걸음 1 ~ 4의 검사(band_form · sphere_lines · schema4_items · schema4_paint_same)는 손으로 짠 타일 바이트와 JSON만 본다. 앱의 읽개는
// 일부러 너그러워서(없는 열 = 0 배열 · 없는 열쇠 = 빈 목록 — 옛 저장소 · 옛 답을 위해) 엔진이 form을 다른 열이나 다른 조회에 싣거나
// 열쇠 이름을 다르게 주어도 그 검사들은 모두 통과하고, 값만 조용히 0 · 빈 목록이 된다. 그림판은 새 값을 읽지 않으므로 1배 PNG 비교(과제 9)도
// 이 어긋남을 못 잡는다. 그래서 여기서 엔진의 답을 앱의 읽개로 읽어 **내보내기 JS의 값(= 정답 — 고정 자료 그대로)**과 견준다.
//
// 엔진 DLL(archive_import가 있는 것)이 있으면 늘 돈다. 지은 저장소의 판으로 기대가 갈린다:
//   - 스키마 3('3' · '3.1' — 스키마 4 전의 엔진이 지은 판): form 열 · sphere_lines 표가 없다 → 앱은 form을 모두 0(모름),
//     sphereLines를 빈 목록으로 읽어야 한다(계약 1-1의 옛 저장소 = 빈 값).
//   - 그 밖(스키마 4 ~): 앱이 읽은 form · sphereLines가 내보내기 JS의 값과 같아야 한다. 여기가 떨어지면 아래 약속에서 엔진과 앱이
//     어긋난 것이다 — 계약을 기준으로 어느 쪽이 어긋났는지 가르고 그쪽을 고친다.
//   - 칸 종류 9 · 칸 style 27비트 · 일반 구역 54 ~ 56은 판과 상관없이 지금의 칸 · 일반 구역 길로 실리므로 늘 같아야 한다.
//
// 견주는 약속(docs/계약-아카이브-3단계.md — 2026-10-25 진짜 엔진(스키마 4)과 대조해 통과):
//   - 타일 띠 구역(1)의 열 10 = form — 계약 5절 띠 행(엔진 tile.rs `BAND_FORM_COLUMNS` · `band_columns`: form ≠ 0인 띠가 든 타일만 11열)
//     · 앱 tile.dart `bandForm`. 열이 없으면 0 배열.
//   - layout 답 맨 위 열쇠 `sphereLines`(낙타 꼴 — 계약 1-1 · 2절 · 엔진 layout.rs. 이 답의 다른 열쇠 sphere_at · rail_levels는 밑줄 꼴이다)의
//     원소 {kind, sphere, start, end, name, uid, color, data}가 표의 id 차례로. data는 글(TEXT)이든 풀린 JSON이든 받는다(layout.dart `SphereLine.fromJson`).
//   - 칸 종류 9 · 칸 style 27비트 · 일반 구역 54 ~ 56은 schema4_items.dart의 읽개 그대로.
//
// 고정 자료 fixtures/<팩>-layout4.json: 형식 4 가상 팩(prototype/fixtures/f4의 f4-crowns · f4-sphere, fixtures/oracle의 f4-office3)을 지금
// 내보내기로 뽑고, 항목 기록(entities)만 크기 때문에 비웠다(이 검사는 읽지 않는다):
//   TZ=Asia/Seoul node prototype/scripts/remake3-same-check.mjs --one=f4-crowns --out=<임시>.json   (f4-sphere · f4-office3도 같게)
//   → entities를 []로 바꿔 prototype/app/test/fixtures/f4-crowns-layout4.json에. 내보내기가 바뀌면 다시 뽑는다.

/// 훑는 단계(통 4^8분 ≈ 45일 · 타일 ≈ 32년) — 가상 팩의 띠 · 칸 · 일반 항목이 성긴 단계 추림에 걸리지 않을 만큼 잘다.
const _level = 8;

/// 고정 배치 하나로 지어 연 저장소.
class _Built {
  _Built(this.engine, this.schema, this.layout, this.plan);

  final ArchiveEngine engine;

  /// 지은 저장소의 판(`meta.schema`).
  final String schema;

  /// 엔진의 `{"op":"layout"}` 답(`data`).
  final Map<String, dynamic> layout;

  /// 고정 자료(내보내기 JS의 배치) — 견줄 정답.
  final Map<String, dynamic> plan;

  /// 스키마 3 저장소(form 열 · sphere_lines 표가 없음 — 새 값은 빈 값으로 읽혀야 함).
  bool get older => schema == '3' || schema == '3.1';
}

void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  final hasImport = dll.existsSync() && engineHasImport(dll.absolute.path);
  final noEngine = hasImport ? false : '자료 처리부 DLL(archive_import가 있는 것)이 없습니다 — dev.ps1 engine-build 뒤에 돈다';

  /// [name]-layout4.json을 임시 폴더의 새 저장소로 짓고 연다. [cells]를 주면 고정 자료의 칸 목록을 그것으로 바꾼 사본을 임시 폴더에 써서 짓는다
  /// (정답 [_Built.plan]도 그 사본).
  Future<_Built> build(String name, {List<Map<String, dynamic>> Function(List<Map<String, dynamic>> cells)? cells}) async {
    final dir = Directory.systemTemp.createTempSync('ht-schema4-');
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    var started = false;
    // Windows는 열린 저장소 파일을 지우지 못한다 — 저장소를 놓고 작업자를 닫은 뒤에 폴더를 지운다.
    addTearDown(() async {
      if (started) {
        try {
          await engine.call({'op': 'close'});
        } catch (_) {
          // 이미 놓였다.
        }
      }
      engine.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    var plan = File('test/fixtures/$name-layout4.json').absolute.path;
    if (cells != null) {
      final edited = jsonDecode(File(plan).readAsStringSync()) as Map<String, dynamic>;
      edited['cells'] = cells([for (final c in edited['cells'] as List) Map<String, dynamic>.from(c as Map)]);
      plan = (File('${dir.path}${Platform.pathSeparator}$name-layout4.json')..writeAsStringSync(jsonEncode(edited))).path;
    }
    final out = '${dir.path}${Platform.pathSeparator}archive.db';
    final built = await callArchiveImport(layoutImportRequest(layout: plan, out: out), libraryPath: dll.absolute.path);
    expect(built['ok'], isTrue, reason: '$built');
    final info = await engine.start(out);
    started = true;
    final layout = (await engine.call({'op': 'layout'}))['data'] as Map<String, dynamic>;
    return _Built(engine, '${info['data']['meta']['schema']}', layout, jsonDecode(File(plan).readAsStringSync()) as Map<String, dynamic>);
  }

  /// 고정 자료의 시간 범위 전체를 [_level] 단계 타일로 훑는다(줄 묶음마다 · 켠 자료집 전부).
  Future<List<Tile>> sweep(_Built b) async {
    final packs = [for (final p in b.layout['packs'] as List) ((p as Map)['id'] as num).toInt()];
    final rows = (b.layout['tracks'] as List).fold<int>(0, (n, t) => n + ((t as Map)['rows'] as List).length);
    var lo = 0, hi = 0, first = true;
    for (final key in const ['periods', 'cells', 'items']) {
      for (final x in b.plan[key] as List) {
        final start = ((x as Map)['start'] as num).toInt(), end = (x['end'] as num).toInt();
        lo = first ? start : math.min(lo, start);
        hi = first ? end : math.max(hi, end);
        first = false;
      }
    }
    final tiles = <Tile>[];
    for (int chunk = 0; chunk * chunkRows < rows; chunk++) {
      for (int x = tileOf(lo, _level); x <= tileOf(hi, _level); x++) {
        tiles.add(Tile.decode(await b.engine.tile(_level, x, chunk, packs)));
      }
    }
    return tiles;
  }

  /// 타일들의 띠(번호로 겹침을 걷음)를 (이름, form)으로 — 내보내기의 periods[].form과 같은가(스키마 3 저장소면 모두 0인가).
  void expectForms(_Built b, List<Tile> tiles) {
    final seen = <int, (String, int)>{};
    for (final t in tiles) {
      for (int i = 0; i < t.bandCount; i++) {
        seen[t.bandId[i]] = (t.text(t.bandName[i]), t.bandForm[i]);
      }
    }
    final periods = [for (final p in b.plan['periods'] as List) p as Map];
    expect(periods.where((p) => ((p['form'] ?? 0) as num) != 0), isNotEmpty, reason: '고정 자료에 form ≠ 0인 띠가 있어야 견줄 수 있다');
    if (b.older) {
      expect(seen.values.toSet(), {for (final p in periods) ('${p['name']}', 0)},
          reason: '스키마 ${b.schema} 저장소는 form 열이 없다 — 앱은 띠마다 0(모름)으로 읽는다(옛 저장소 = 빈 값)');
      return;
    }
    expect(
      seen.values.toSet(),
      {for (final p in periods) ('${p['name']}', ((p['form'] ?? 0) as num).toInt())},
      reason: '엔진 타일의 띠 form(띠 구역 열 10 — tile.dart bandForm) = 내보내기 JS의 periods[].form. '
          '모두 0이면 엔진이 form을 열 10에 싣지 않는 것(다른 열 · 다른 조회) — 계약 5절의 띠 행과 tile.dart를 맞춘다',
    );
  }

  /// 엔진 layout 답의 sphereLines를 앱이 읽은 것(SceneLayout.fromJson) = 내보내기 JS의 sphereLines(스키마 3 저장소면 빈 목록).
  List<SphereLine> expectSphereLines(_Built b) {
    final want = [for (final x in b.plan['sphereLines'] as List) SphereLine.fromJson(x as Map)];
    expect(want, isNotEmpty, reason: '고정 자료에 문화권 단위 줄이 있어야 견줄 수 있다');
    if (b.older) {
      expect(SceneLayout.fromJson(b.layout).sphereLines, isEmpty, reason: '스키마 ${b.schema} 저장소는 sphere_lines 표가 없다 — 빈 목록');
      return const [];
    }
    expect(
      b.layout.keys,
      contains('sphereLines'),
      reason: 'layout 답 맨 위 열쇠 sphereLines(계약 1-1) — 다른 이름(sphere_lines 같은 밑줄 꼴)이면 앱은 빈 목록으로 읽는다',
    );
    final got = SceneLayout.fromJson(b.layout).sphereLines;
    expect(got, hasLength(want.length), reason: '표 전부가 답에 든다');
    for (int i = 0; i < want.length; i++) {
      final (g, w) = (got[i], want[i]);
      expect((g.kind, g.sphere, g.start, g.end, g.name, g.uid, g.color), (w.kind, w.sphere, w.start, w.end, w.name, w.uid, w.color), reason: '줄 $i(id 차례)');
      expect(g.decoded, w.decoded, reason: '줄 $i의 data — 엔진이 글(TEXT)로 주든 풀린 JSON으로 주든 같은 값으로 읽힌다');
    }
    return got;
  }

  test('f4-crowns: 띠의 form과 사람 띠(sphereLines 갈래 1 · 왕관 여섯)를 진짜 엔진 답에서 읽는다(스키마 3 저장소면 빈 값)', () async {
    final b = await build('f4-crowns');
    expectForms(b, await sweep(b));
    final lines = expectSphereLines(b);
    if (b.older) return;
    final person = lines.where((l) => l.kind == SphereLine.person).toList();
    expect(person, hasLength(1));
    expect(person.single.crowns, hasLength(6), reason: '왕관 목록 data [{uid, cell}]');
  }, skip: noEngine);

  test('f4-sphere: 띠의 form과 문화권 시대 구분(갈래 2) · 주기 줄(갈래 3)을 진짜 엔진 답에서 읽는다(스키마 3 저장소면 빈 값)', () async {
    final b = await build('f4-sphere');
    expectForms(b, await sweep(b));
    final lines = expectSphereLines(b);
    if (b.older) return;
    expect(lines.where((l) => l.kind == SphereLine.epoch), isNotEmpty);
    final cycles = lines.where((l) => l.kind == SphereLine.cycle).toList();
    expect(cycles, isNotEmpty);
    expect(cycles.every((l) => l.decoded is Map), isTrue, reason: '주기 줄의 data는 {names, start, label} 또는 {era, from, step, label}');
  }, skip: noEngine);

  test('f4-office3: 칸 종류 9 · 빌린 칸 27비트 · 구역 54 ~ 56을 Schema4 읽개가 진짜 엔진 타일에서 찾고, 띠의 form도 읽힌다(스키마 3 저장소면 0)', () async {
    final b = await build('f4-office3');
    final tiles = await sweep(b);
    // 타일 경계에 걸친 것은 여러 타일에 실리므로 번호로 겹침을 걷는다.
    final more = <int, String>{}, borrowed = <int>{};
    final heads = <int, String>{}, names = <int, String>{}, powers = <int, String>{};
    for (final t in tiles) {
      for (final i in Schema4.officeMoreCells(t)) {
        more[t.cellId[i]] = t.text(t.cellName[i]);
      }
      for (int i = 0; i < t.cellCount; i++) {
        if (Schema4.isBorrowed(t.cellKind[i], t.cellStyle[i])) borrowed.add(t.cellId[i]);
      }
      for (final h in Schema4.borrowHeads(t)) {
        heads[h.id] = h.source;
      }
      for (final n in Schema4.officeNames(t)) {
        names[n.id] = n.name;
      }
      for (final p in Schema4.powerLines(t)) {
        powers[p.id] = p.holder;
      }
    }
    final cells = [for (final c in b.plan['cells'] as List) c as Map];
    final items = [for (final it in b.plan['items'] as List) it as Map];
    List<String> sorted(Iterable<Object?> names) => [for (final n in names) '$n']..sort();
    List<String> itemNames(int section) => sorted([for (final it in items) if (it['section'] == section) it['name']]);

    final wantMore = sorted([for (final c in cells) if (c['kind'] == Schema4.cellOfficeMore) c['name']]);
    expect(wantMore, isNotEmpty);
    expect(sorted(more.values), wantMore, reason: '칸 종류 9(직위 줄 더)');
    final wantBorrowed = cells.where((c) => Schema4.isBorrowed((c['kind'] as num).toInt(), (c['style'] as num).toInt())).length;
    expect(wantBorrowed, isNonZero);
    expect(borrowed, hasLength(wantBorrowed), reason: '칸 style 27비트(빌린 직위 줄의 칸 — 종류 1 · 2 · 9)');
    for (final (section, got) in [(Schema4.secBorrowHead, heads), (Schema4.secOfficeName, names), (Schema4.secPowerLine, powers)]) {
      expect(itemNames(section), isNotEmpty, reason: '고정 자료의 구역 $section');
      expect(sorted(got.values), itemNames(section), reason: '구역 $section');
    }
    // form은 끝에 — form이 어긋나도 위의 읽개 대조 결과는 먼저 보이게.
    expectForms(b, tiles);
  }, skip: noEngine);


  // 되돌릴 자리(리메이크 4단계 차례 걸음 16)의 엔진 몫: 앱은 칸 종류 9(직위 줄 더)의 줄을 이제 그린다(칸 그림 갈래 걸음 4 · G7 가 —
  // schema4_items.dart `Schema4.officeLinesDrawn` 참 · 앱 몫은 뒤집음). 엔진은 아직 그 칸을 범례 · 필터 시트의 조건부 줄(`legend_kinds`)과 연도 검색(`search_year`)에서
  // 뺀다 — query.rs 740 · 1744줄 주석의 `c.kind<>9` 두 곳 · 계약 2-1(287줄 '스키마 4의 값'). 엔진 거르기는 remake-3 몫이라 이 갈래는 고치지 않고, 엔진 검사
  // tests/queries.rs `직위_줄_더_칸은_범례와_연도_검색에_보이지_않는다`와 같은 물음을 앱이 쓰는 진짜 DLL로 묶어 둔다 — 합칠 때 엔진 두 곳 · 엔진 검사 · 계약 문장과
  // 함께 이 검사를 '종류 9가 범례 · 연도 검색에 나온다'로 뒤집는다(계획 과제 5 걸음 3 '걷을 자리').
  test('f4-office3: 칸 종류 9(직위 줄 더)를 엔진은 아직 범례(legend_kinds) · 연도 검색(search_year)에서 뺀다 — 엔진 거르기는 remake-3 몫', () async {
    const why = '엔진 거르기는 remake-3 몫 — 합칠 때 query.rs 두 곳 · tests/queries.rs · 계약 2-1과 함께 뒤집음';
    bool office(Map<String, dynamic> c) => (c['kind'] as num).toInt() == Schema4.cellOfficeMore;

    /// 범례의 조건부 줄을 켜는 칸 style 비트 — 이설 128 · 범위 64 · 모호 8 · 16 · 미정 1 · 2(엔진 검사와 같은 219).
    const legendBits = 219;

    /// 그 저장소의 타일에 실린 종류 9 칸 가운데 [legendBits]를 모두 단 것의 수와 모든 종류 9 칸의 수(번호로 겹침을 걷음).
    Future<(int, int)> officeCells(_Built b) async {
      final all = <int>{}, marked = <int>{};
      for (final tile in await sweep(b)) {
        for (final i in Schema4.officeMoreCells(tile)) {
          all.add(tile.cellId[i]);
          if (tile.cellStyle[i] & legendBits == legendBits) marked.add(tile.cellId[i]);
        }
      }
      return (marked.length, all.length);
    }

    Future<Map<String, dynamic>> ask(_Built b, Map<String, dynamic> q) async {
      final got = await b.engine.call(q);
      expect(got['ok'], isTrue, reason: '$q: $got');
      return Map<String, dynamic>.from(got['data'] as Map);
    }

    // 같은 고정 자료로 둘을 짓는다: 종류 9 칸에 [legendBits]를 모두 단 것(s)과 종류 9 칸을 지운 것(t). 엔진이 종류 9 칸을 세면 s의 범례가 t와 갈리고,
    // 연도 검색에 종류 9 칸(`cell_kind` 9)이 나온다. 자료 처리부(DLL)는 열린 저장소를 하나만 쥐므로(`{"op":"open"}`) s를 다 묻고 닫은 뒤 t를 짓는다.
    final s = await build('f4-office3', cells: (cells) => [for (final c in cells) office(c) ? {...c, 'style': (c['style'] as num).toInt() | legendBits} : c]);
    final spans = [for (final c in s.plan['cells'] as List) if (office(c as Map<String, dynamic>)) ((c['start'] as num).toInt(), (c['end'] as num).toInt())];
    expect(spans, isNotEmpty, reason: 'f4-office3에 칸 종류 9가 있어야 견줄 수 있다');
    // 헛돌지 않게: s에는 비트를 단 종류 9 칸이 실제로 실렸고 지금 열린 저장소가 s다(짓기가 그 칸을 버렸거나 다른 저장소를 묻는다면 아래 견줌이 늘 같다).
    expect(await officeCells(s), (spans.length, spans.length), reason: 's의 종류 9 칸(style $legendBits 비트를 단 것)이 저장소 타일에 실림');
    // 연도 검색: 종류 9 칸의 때(시작 · 가운데 · 끝)마다 모든 갈래 · 칸 갈래만 두 물음.
    final asks = [
      for (final (start, end) in spans)
        for (final at in [start, start + (end - start) ~/ 2, end]) ...[
          {'op': 'search_year', 'at': at, 'limit': 200},
          {'op': 'search_year', 'at': at, 'kinds': ['cell'], 'limit': 200},
        ],
    ];
    final legendS = await ask(s, {'op': 'legend_kinds'});
    final yearS = [for (final q in asks) await ask(s, q)];
    await s.engine.call({'op': 'close'});

    final t = await build('f4-office3', cells: (cells) => [for (final c in cells) if (!office(c)) c]);
    expect(await officeCells(t), (0, 0), reason: 't는 종류 9 칸을 지운 저장소');
    final legendT = await ask(t, {'op': 'legend_kinds'});
    final yearT = [for (final q in asks) await ask(t, q)];

    // 범례 · 필터 시트의 조건부 줄: 지운 저장소와 같은 답. 헛돌지 않게 — 지운 쪽에는 칸의 이설 · 모호 줄이 서지 않는다(s의 종류 9 칸을 셌다면 섰을 줄).
    final hasT = Map<String, dynamic>.from(legendT['has'] as Map);
    expect([hasT['cellAlt'], hasT['cellFuzzy'], legendT['vague_cell']], [false, false, false], reason: '고정 자료의 다른 칸에는 그 비트가 없어야 견줄 수 있다');
    expect(legendS, legendT, reason: '범례(legend_kinds)에 종류 9 칸이 세어졌다 — $why');

    // 연도 검색: 그때에 걸친 것이 있고, 종류 9 칸이 없고, 지운 저장소와 같은 답.
    for (int k = 0; k < asks.length; k++) {
      final items = [for (final it in yearS[k]['items'] as List) Map<String, dynamic>.from(it as Map)];
      expect(items, isNotEmpty, reason: '${asks[k]}: 그때에 걸친 것이 있어야 견줄 수 있다');
      expect(items.where((it) => it['cell_kind'] == Schema4.cellOfficeMore).map((it) => it['name']), isEmpty, reason: '${asks[k]}: 연도 검색(search_year)에 종류 9 칸 — $why');
      expect(yearS[k], yearT[k], reason: '${asks[k]}: 종류 9 칸을 지운 저장소와 다른 답 — $why');
    }
  }, skip: noEngine);
}
