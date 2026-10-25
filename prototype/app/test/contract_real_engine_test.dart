import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/ui/search_parse.dart';
import 'package:flutter_test/flutter_test.dart';

// 자료 계약 검사 — **진짜 자료 처리부(DLL) + 진짜 저장소**(월흔해 `data/moonwake3h`)로 돈다.
//
// 무엇을 지키는가: 앱의 부품이 실제로 보내는 물음(`lib/**`의 `bus.ask` · `engine.call` 자리 그대로)을 던져,
// **부품이 읽는 열쇠가 답에 있고 꼴이 맞는지**를 굳힌다. 부품들은 조회 명령이 생기기 전에 가짜 답으로 만들어졌고
// 엔진은 나중에 맞췄기 때문에 어긋난 곳이 남아 있다 — 어긋난 것은 실패로 남기지 않고 `skip: '어긋남 — 보고서 n번'`으로
// 표시했다. 까닭과 고칠 곳은 `docs/검사-전역-계약-2026-09-22.md`에 번호대로 적었다.
//
// 돌리는 법(계약 0절): 연결 폴더에서
//   Push-Location "$env:TEMP\ht-next-engine\app"
//   & "$env:TEMP\ht-archive-flutter\flutter\bin\flutter.bat" test --no-pub test/contract_real_engine_test.dart
// DLL이나 저장소가 없으면 모든 검사를 건너뛴다. (이름은 Dart가 ASCII만 받아 영문이다 — 검사 이름과 주석은 한국어다.)

/// 이 저장소에서 골라 둔 진짜 값들(`uid_of` · `search` · `layout`의 답에서 골랐다).
const bandId = 1; // moonwake-chronicle/p-coast-0 (유리항 패총국)
const bandUid = 'moonwake-chronicle/p-coast-0';
const bandStart = -1540504800, bandEnd = -1245972960;
const firstDynastyEnd = -1393238880; // 첫 왕조 칸이 끝나는 때
const eventId = 22; // moonwake-chronicle/p-coast-0-capital
const eventUid = 'moonwake-chronicle/p-coast-0-capital';
const leaderCellName = '은결 나나나'; // 유리항 패총국의 첫 지도자 칸(cells.kind = 1)
const figureAt = -1470000000; // 인물 막대가 걸쳐 있는 때
const eventAt = -1503164160; // 사건이 있는 때
const allPacks = [1];

void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  // 새 저장소를 먼저 찾는다(12물결에서 다시 내보내 넣은 것 — 구역 46 · 관점 표 · 노선도의 x_metro가 들어 있다).
  final db = [File('../data/moonwake3i/archive.db'), File('../data/moonwake3h/archive.db')].where((f) => f.existsSync()).firstOrNull ?? File('../data/moonwake3i/archive.db');
  final ready = dll.existsSync() && db.existsSync();
  const noData = '자료 처리부 DLL 또는 data/moonwake3i · moonwake3h 저장소가 없습니다';

  ArchiveEngine? engine;

  setUpAll(() async {
    if (!ready) return;
    engine = ArchiveEngine(libraryPath: dll.absolute.path);
    await engine!.start(db.absolute.path);
  });

  tearDownAll(() => engine?.close());

  /// 조회 하나를 던지고 답의 `data`를 표로 돌려준다(앱 틀의 `ask`와 같은 길 — 배열은 `{items: […]}`로 감싼다).
  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
    final answer = await engine!.call(query);
    final data = answer['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List) return <String, dynamic>{'items': data};
    return <String, dynamic>{};
  }

  /// 답에서 목록 하나를 꺼낸다(없으면 빈 목록).
  List<Map<String, dynamic>> listOf(Map<String, dynamic> answer, String key) => [
    for (final row in (answer[key] as List? ?? const []))
      if (row is Map) row.cast<String, dynamic>(),
  ];

  /// 항목 기록(`entity`)의 본문을 푼다.
  Future<Map<String, dynamic>> record(String uid) async {
    final answer = await ask({'op': 'entity', 'uid': uid});
    final raw = answer['json'];
    if (raw is Map) return raw.cast<String, dynamic>();
    return (jsonDecode('$raw') as Map).cast<String, dynamic>();
  }

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  1. 뼈대 — 앱 틀이 열 때 묻는 것(archive_app.dart의 _open · _buildBus)
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('뼈대', () {
    test('layout이 배치가 읽는 열쇠를 모두 준다', () async {
      final shape = await ask({'op': 'layout'});
      expect(shape.keys, containsAll(['packs', 'tracks', 'categories', 'epochs', 'axis', 'variants']));
      final tracks = listOf(shape, 'tracks');
      final baseTracks = tracks.where((t) => !(t['key'] as String).startsWith('__board:')).toList();
      final boardTracks = tracks.where((t) => (t['key'] as String).startsWith('__board:')).toList();
      expect(baseTracks, hasLength(12), reason: '월흔해의 원래 트랙 열둘을 유지함');
      expect(boardTracks, hasLength(21), reason: '시대 구분 임시 판은 원래 트랙 뒤에 따로 싣음');
      expect(tracks, hasLength(33));
      // 대범위 칩(scopes)이 제 트랙을 찾을 때 쓰는 글자 id.
      expect(baseTracks.first['key'], isA<String>());
      expect(baseTracks.first['key'] as String, isNotEmpty);
      final rows = listOf(baseTracks.first, 'rows');
      expect(
        rows.first.keys,
        containsAll(['height', 'band_top', 'band_h', 'kind', 'group_start', 'scope_pad', 'phase', 'rank', 'cats', 'fig', 'dep', 'zones', 'hem']),
      );
      expect(listOf(baseTracks.first, 'groups'), isNotEmpty);
      expect(listOf(shape, 'categories').length, 8);
      expect((shape['axis'] as List).length, 1008);
      // 기존 변형 다섯과 시대 구분 임시 판 스물하나 · 주제 보기 하나를 따로 검증한다.
      final variants = listOf(shape, 'variants');
      expect(variants.where((v) => v['kind'] == VariantInfo.kindHost), hasLength(1));
      expect(variants.where((v) => v['kind'] == VariantInfo.kindScope), hasLength(4));
      final boards = variants.where((v) => v['kind'] == VariantInfo.kindView).toList();
      final themes = variants.where((v) => v['kind'] == VariantInfo.kindTheme).toList();
      expect(boards, hasLength(21));
      expect(themes, hasLength(1));
      expect(themes.single['key'], startsWith('theme:'));
      expect(variants, hasLength(27));
      for (final variant in variants) {
        expect(variant.keys, containsAll(['id', 'key', 'kind', 'track', 'band', 'uid', 'rows', 'groups']));
      }
      // 판마다 제 트랙 하나와 시대 구분 기록 하나가 연결되어야 한다(수만 늘어난 자료는 통과하지 않음).
      final boardTrackIds = boards.map((v) => v['track']).toSet();
      expect(boardTrackIds, hasLength(21));
      expect(boardTrackIds, boardTracks.map((t) => t['id']).toSet());
      for (final board in boards) {
        expect(board['key'], 'view:epoch:${board['uid']}');
        final track = boardTracks.singleWhere((t) => t['id'] == board['track']);
        expect(track['key'], '__board:${board['key']}');
        expect(listOf(track, 'rows'), isNotEmpty);
        final saved = await record('board:${board['key']}');
        expect(saved['temp'], 1);
        expect(saved['epoch'], board['uid']);
        expect(saved['key'], board['key']);
        expect(saved['members'], isNotEmpty);
      }
    }, skip: ready ? false : noData);

    test('legend_kinds의 실재성 목록을 앱 틀이 읽는 두 꼴로 준다', () async {
      // archive_app._loadShownHistoricity는 `historicity`를 표({id,…})로도 수로도 읽는다.
      final legend = await ask({'op': 'legend_kinds'});
      final raw = legend['historicity'];
      expect(raw, isA<List>());
      expect((raw as List).first, isA<Map>());
      expect(legend['historicity_ids'], isA<List>());
    }, skip: ready ? false : noData);

    test('연표에서 누른 띠 · 사건의 번호가 항목 기록의 열쇠로 바뀐다', () async {
      // archive_app._uidOfBand · app_glue.uidOfEvent
      final band = await ask({'op': 'uid_of', 'kind': 'band', 'id': bandId});
      expect(band['uid'], bandUid);
      expect(band['kind'], 'period');
      final event = await ask({'op': 'uid_of', 'kind': 'event', 'id': eventId});
      expect(event['uid'], eventUid);
      expect(event['kind'], 'event');
    }, skip: ready ? false : noData);

    test('고르면 가는 곳 — ids_of · id_of가 분과 줄을 준다', () async {
      // app_glue.placesOf → readPlaces가 bands · events의 {uid,id,row,start,end}를 읽는다.
      final many = await ask({
        'op': 'ids_of',
        'uids': [bandUid, eventUid],
      });
      final bands = listOf(many, 'bands'), events = listOf(many, 'events');
      expect(bands.single['uid'], bandUid);
      expect(bands.single['id'], bandId);
      expect(bands.single['row'], isA<int>());
      expect(bands.single['start'], bandStart);
      expect(bands.single['end'], bandEnd);
      expect(events.single['uid'], eventUid);
      final one = await ask({'op': 'id_of', 'uid': bandUid});
      expect(one.keys, containsAll(['band', 'event', 'row', 'start', 'end']));
      expect(one['band'], bandId);
      expect(one['event'], isNull);
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  2. 상세 창 다섯 갈래 — 읽는 것은 거의 항목 기록(entities)의 x_ 열쇠다
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('상세 창', () {
    test('entity가 {uid, kind, json}을 주고 json이 풀린다', () async {
      // detail_shell._onSelection
      final answer = await ask({'op': 'entity', 'uid': bandUid});
      expect(answer.keys, containsAll(['uid', 'kind', 'json']));
      expect(answer['kind'], 'period');
      expect(answer['json'], isA<String>());
      final json = (jsonDecode('${answer['json']}') as Map).cast<String, dynamic>();
      expect(json['name'], isA<String>());
      expect(json['itemKind'], isA<String>());
    }, skip: ready ? false : noData);

    test('기본 · 조약 · 인물 · 가문 · 대범위 창이 읽는 x_ 열쇠가 기록에 있다', () async {
      // 갈래마다 그 창이 반드시 읽는 열쇠(detail_item · detail_people · detail_scope · detail_cell).
      const wanted = {
        'moonwake-chronicle/p-coast-0': ['x_cellBounds', 'x_eventStat', 'x_served', 'x_succ', 'x_partOf', 'x_dynasties'],
        'moonwake-chronicle/p-coast-6': ['x_leaderFigures', 'x_hostedScopes'],
        'moonwake-chronicle/client-10': ['x_scopes'],
        'moonwake-chronicle/p-coast-6-treaty-0': ['x_parties'],
        'moonwake-chronicle/p-canopy-6-campaign': ['x_children'],
        'moonwake-chronicle/d-canopy-0-0': ['x_ruled', 'x_rulers', 'x_spots'],
        'moonwake-chronicle/f-canopy-0-0': ['x_services', 'x_rulers', 'x_spots'],
        'house:h-canopy-0': ['x_path', 'x_branches', 'x_nations', 'x_members'],
        'moonwake-chronicle/scope-epoch': ['x_members'],
        'moonwake-chronicle/epoch-7': ['x_scopes'],
        'moonwake-chronicle/agency-p-canopy-0': ['x_partOf'],
        'moonwake-chronicle/culture-canopy': ['x_succ'],
      };
      for (final entry in wanted.entries) {
        final json = await record(entry.key);
        for (final key in entry.value) {
          expect(json.containsKey(key), isTrue, reason: '${entry.key}에 $key가 없다');
        }
      }
    }, skip: ready ? false : noData);

    test('x_cellBounds의 열쇠가 칸 참조와 같은 꼴이고 값은 분 두 개다', () async {
      // detail_cell.cellBoundsOf가 'leader:3' 같은 열쇠로 찾는다.
      final json = await record(bandUid);
      final bounds = (json['x_cellBounds'] as Map).cast<String, dynamic>();
      expect(bounds, isNotEmpty);
      for (final entry in bounds.entries) {
        expect(entry.key, matches(RegExp(r'^(leader|cabinet|phase|rank|dynasty|organ|dep|era|capital):\d+$')));
        final span = entry.value as List;
        expect(span.length, greaterThanOrEqualTo(2));
        expect(span[0], isA<num>());
      }
    }, skip: ready ? false : noData);

    test('x_served의 한 줄이 칸 창의 "이 시기의 인물"이 읽는 꼴이다', () async {
      // detail_cell._cellFigures: span[0] · span[1]이 분이고 uid · name · when · role을 읽는다.
      final json = await record(bandUid);
      final row = (json['x_served'] as List).first as Map;
      expect(row['span'], isA<List>());
      expect((row['span'] as List).first, isA<num>());
      expect(row.keys, containsAll(['uid', 'name', 'when', 'role']));
    }, skip: ready ? false : noData);

    test('여러 자리에 놓인 사건의 상세 창이 열린다', () async {
      // archive_app.hit → app_glue.pickEvent → uid_of → detail_shell이 그 uid로 entity를 묻는다.
      // 공동 사건(조약 · 전쟁)의 둘째 자리부터는 uid에 '#1'이 붙는데 항목 기록은 밑동 uid뿐이라 창이 조용히 닫힌다.
      final uid = await ask({'op': 'uid_of', 'kind': 'event', 'id': 808});
      expect('${uid['uid']}', contains('#'));
      final answer = await ask({'op': 'entity', 'uid': '${uid['uid']}'});
      expect(answer['json'], isNotNull);
    }, skip: ready ? false : noData);

    test('없는 항목 기록은 까닭을 적은 한국어 글로 거절한다', () async {
      // 계약 0절: 잘못된 입력은 한국어로 실패한다. 지금은 rusqlite의 영어 글(QueryReturnedNoRows)이 그대로 나온다.
      await expectLater(
        ask({'op': 'entity', 'uid': 'no-such-uid'}),
        throwsA(isA<StateError>().having((e) => e.message, '까닭', matches(RegExp('[가-힣]')))),
      );
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  3. 칸 상세의 '이 시기의 사건' — events_in
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('칸 상세의 이 시기의 사건', () {
    test('띠 번호로 물으면 사건이 온다', () async {
      final answer = await ask({'op': 'events_in', 'band': bandId, 'lo': bandStart, 'hi': firstDynastyEnd, 'limit': 200});
      final items = listOf(answer, 'items');
      expect(items, isNotEmpty);
      expect(items.first.keys, containsAll(['id', 'uid', 'title', 'start', 'end', 'importance', 'look', 'label']));
      expect(answer.keys, containsAll(['items', 'next', 'has_more']));
    }, skip: ready ? false : noData);

    test('칸 창이 보내는 물음 그대로(band = 정권 uid) 답이 온다', () async {
      // detail_cell._loadEvents가 보내는 것: {'op':'events_in','band': 정권 uid, …}.
      // 엔진은 band를 **띠 번호(정수)**로만 받아 "띠 번호(band)나 줄 번호(row) 하나는 주어야 합니다"로 실패한다.
      final answer = await ask({'op': 'events_in', 'band': bandUid, 'lo': bandStart, 'hi': firstDynastyEnd, 'limit': 200});
      expect(listOf(answer, 'items'), isNotEmpty);
    }, skip: ready ? false : noData);

    test('칸 창이 읽는 열쇠(events)로 목록이 온다', () async {
      // detail_cell._rows(answer, 'events')는 'events' · 'rows' · 'list'만 본다 — 엔진은 'items'로 준다.
      final answer = await ask({'op': 'events_in', 'band': bandId, 'lo': bandStart, 'hi': firstDynastyEnd, 'limit': 200});
      expect(answer['events'] ?? answer['rows'] ?? answer['list'], isA<List>());
    }, skip: ready ? false : noData);

    test('사건 한 줄에 색 · 조약 표시 · 때 글이 실린다', () async {
      // detail_cell._eventRow가 읽는 color · treaty · member · when. 지금은 없고 label · look만 온다.
      final answer = await ask({'op': 'events_in', 'band': bandId, 'lo': bandStart, 'hi': firstDynastyEnd, 'limit': 200});
      final row = listOf(answer, 'items').first;
      expect(row.keys, containsAll(['color', 'treaty', 'when']));
    }, skip: ready ? false : noData);

    test('같은 시기 타국(메아리) 목록을 받을 수 있다', () async {
      // detail_cell._loadEcho가 보내는 {'op':'echo', …} — 엔진에 그 명령이 없다(검증 6절 3).
      final answer = await ask({
        'op': 'echo',
        'spots': [
          {'uid': bandUid, 'start': bandStart, 'end': firstDynastyEnd},
        ],
        'echo': true,
        'limit': 200,
      });
      expect(answer['groups'], isA<List>());
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  4. 검색 — 이름 · 연도 · 날짜 · 간지 · 칸
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('검색', () {
    // search.dart가 보내는 갈래(search_parse.dart의 SearchQuery.kinds).
    // 검색 부품이 실제로 묻는 갈래(낱말로 읽힌 입력) — 베껴 적지 않고 부품의 것을 그대로 쓴다.
    final appKinds = parseSearch('유리항').kinds;
    const allKinds = ['event', 'treaty', 'period', 'organ', 'culture', 'dynasty', 'figure', 'epoch', 'scope', 'house', 'cell', 'doc'];
    const hiddenNames = ['높은잎 첫불 왕조 깊은', '유리항 매듭토기 문화', '높은잎 공동 계량감 깊은'];

    test('검색 결과 한 줄이 SearchHit가 읽는 열쇠를 모두 갖는다', () async {
      final answer = await ask({'op': 'search', 'text': '유리항', 'kinds': appKinds, 'limit': 21, 'after': 0});
      final items = listOf(answer, 'items');
      expect(items, isNotEmpty);
      expect(
        items.first.keys,
        containsAll(['kind', 'uid', 'name', 'sub', 'when', 'track', 'color', 'start', 'end', 'row', 'id', 'prec', 'cell', 'cell_kind']),
      );
      expect(answer.keys, containsAll(['items', 'next', 'has_more', 'total']));
    }, skip: ready ? false : noData);

    test('날짜를 치면 search_year가 그때에 걸친 것을 준다', () async {
      // search.dart는 `t`로 부른다(엔진은 at · t 둘 다 받는다).
      final answer = await ask({'op': 'search_year', 't': eventAt, 'end': eventAt, 'kinds': appKinds, 'limit': 21, 'after': 0});
      final items = listOf(answer, 'items');
      expect(items, isNotEmpty);
      expect(items.first.keys, containsAll(['kind', 'uid', 'name', 'when', 'start', 'end', 'cell', 'prec']));
    }, skip: ready ? false : noData);

    test('간지를 치면 그 해들이 가까운 순으로 온다', () async {
      final answer = await ask({'op': 'ganji_years', 'ganji': '갑오', 'center': -900, 'lo': -1532, 'hi': 1000, 'limit': 8});
      final years = answer['years'] as List;
      expect(years, isNotEmpty);
      expect((years.first as num).toInt(), -926);
    }, skip: ready ? false : noData);

    test('날짜 칸(연호)을 이름으로 찾으면 임자와 칸 참조가 함께 온다', () async {
      // archive_app.axisCell이 누른 날짜 칸의 임자를 이름으로 되찾는 길.
      final answer = await ask({'op': 'search', 'text': '유리항 개문', 'kinds': ['cell'], 'limit': 20});
      final row = listOf(answer, 'items').firstWhere((r) => r['name'] == '유리항 개문');
      expect('${row['uid']}', isNotEmpty);
      expect('${row['cell']}', startsWith('era:'));
    }, skip: ready ? false : noData);

    test('갈래를 모두 주면 왕조 · 문화 · 기관이 찾힌다(엔진 쪽은 멀쩡하다)', () async {
      for (final text in hiddenNames) {
        final answer = await ask({'op': 'search', 'text': text, 'kinds': allKinds, 'limit': 20});
        expect(listOf(answer, 'items'), isNotEmpty, reason: '"$text"을(를) 찾지 못했다');
      }
    }, skip: ready ? false : noData);

    test('띠 안 칸을 이름으로 찾으면 칸 창을 열 참조가 함께 온다', () async {
      // search.activate의 case 'cell': bus.select(uid, cell: hit.cell)로 칸 창을 연다.
      // 지금은 지도자 · 내각 · 시기 · 지위 칸의 cell이 모두 null이라 정권 기본 상세가 열린다.
      final answer = await ask({'op': 'search', 'text': leaderCellName, 'kinds': appKinds, 'limit': 20});
      final row = listOf(answer, 'items').firstWhere((r) => r['kind'] == 'cell');
      expect(row['cell'], isA<String>());
      expect('${row['cell']}', startsWith('leader:'));
    }, skip: ready ? false : noData);

    test('왕조 · 문화 · 기관도 이름으로 찾힌다', () async {
      // search_parse.SearchQuery.kinds에 dynasty · culture · organ · treaty가 빠져 있다(엔진은 받는다).
      for (final text in hiddenNames) {
        final answer = await ask({'op': 'search', 'text': text, 'kinds': appKinds, 'limit': 20});
        expect(listOf(answer, 'items'), isNotEmpty, reason: '"$text"을(를) 찾지 못했다');
      }
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  5. 같은 해 보기 · 표 보기 · 묶음 카드 · 범례 · 필터 시트
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('도구와 시트', () {
    test('같은 해 보기가 도구 부품이 읽는 묶음을 모두 준다', () async {
      // tools_year.SameYear.fromJson: eras · phases · figures · figureCount · events · count.
      final answer = await ask({'op': 'same_year', 'at': figureAt, 'end': figureAt, 'window': 525960});
      expect(answer.keys, containsAll(['tracks', 'eras', 'phases', 'figures', 'figureCount', 'events', 'count']));
      final eras = listOf(answer, 'eras').where((g) => (g['periods'] as List).isNotEmpty);
      expect(eras, isNotEmpty);
      expect((eras.first['periods'] as List).first, isA<Map>());
      final figures = listOf(answer, 'figures').where((g) => (g['figures'] as List).isNotEmpty);
      expect(figures, isNotEmpty);
      expect(((figures.first['figures'] as List).first as Map).keys, containsAll(['uid', 'name', 'role', 'when']));
      expect(answer['figureCount'], greaterThan(0));
    }, skip: ready ? false : noData);

    test('같은 해 보기의 사건 한 줄이 YearEvent가 읽는 꼴이다', () async {
      final answer = await ask({'op': 'same_year', 'at': eventAt, 'end': eventAt, 'window': 525960});
      final events = listOf(answer, 'events');
      expect(events, isNotEmpty);
      expect(events.first.keys, containsAll(['uid', 'title', 'label', 'color', 'track', 'treaty', 'start', 'end', 'id', 'importance']));
    }, skip: ready ? false : noData);

    test('같은 해 보기의 시기 · 지위 줄을 누르면 그 칸의 창이 열린다', () async {
      // tools_year.YearItem.cell → bus.select(uid, cell: …). 칸 참조가 빈 글이라 기본 상세가 열린다(2번과 같은 뿌리).
      final answer = await ask({'op': 'same_year', 'at': eventAt, 'end': eventAt, 'window': 525960});
      final phase = listOf(answer, 'phases').first;
      final cell = (phase['cells'] as List).first as Map;
      expect('${cell['cell']}', startsWith('phase:'));
      final rank = listOf(answer, 'eras').expand((g) => g['periods'] as List).whereType<Map>().firstWhere((p) => p['rank'] is Map)['rank'] as Map;
      expect('${rank['cell']}', startsWith('rank:'));
    }, skip: ready ? false : noData);

    test('표 보기가 줄과 채우는 칸을 받는다', () async {
      // tools_table._loadMore → table, _fill → entities.
      final table = await ask({'op': 'table', 'with_periods': true, 'packs': allPacks, 'limit': 200});
      expect(table.keys, containsAll(['items', 'next', 'has_more', 'count']));
      final items = listOf(table, 'items');
      expect(items.first.keys, containsAll(['kind', 'uid', 'name', 'when', 'start', 'end', 'track', 'track_name', 'importance']));
      final uids = [for (final row in items.take(20)) '${row['uid']}'];
      final extra = await ask({'op': 'entities', 'uids': uids});
      final rows = listOf(extra, 'items');
      expect(rows, isNotEmpty);
      expect(rows.first.keys, containsAll(['uid', 'kind', 'json']));
    }, skip: ready ? false : noData);

    test('CSV는 열 열다섯에 BOM과 CRLF로 나간다', () async {
      // 경로는 ASCII로 — 한글 경로에서 도구가 멈춘 적이 있다(인수인계의 'Windows 빌드 함정').
      final dir = Directory.systemTemp.createTempSync('ht-contract-csv');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/table.csv';
      final answer = await ask({'op': 'table_csv', 'with_periods': true, 'packs': allPacks, 'path': path});
      expect(answer['rows'], greaterThan(0));
      // Dart의 readAsStringSync는 BOM을 삼키므로 바이트로 본다.
      expect(File(path).readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF]);
      final head = File(path).readAsStringSync().split('\r\n').first;
      expect(head.split(','), hasLength(15));
      expect(head, contains('"실재성"'));
    }, skip: ready ? false : noData);

    test('묶음 카드가 보내는 물음 그대로 사건 목록이 온다', () async {
      // cards.dart._load: {'op':'list','lo','hi','lane','lanes','after'} — 줄마다 50개씩.
      final answer = await ask({'op': 'list', 'lo': bandStart, 'hi': firstDynastyEnd, 'lane': 1, 'lanes': 1, 'after': 0});
      final items = listOf(answer, 'items');
      expect(items, isNotEmpty);
      expect(items.first.keys, containsAll(['id', 'uid', 'start', 'importance', 'title', 'color', 'look', 'label']));
      expect(answer.keys, containsAll(['items', 'next', 'has_more']));
    }, skip: ready ? false : noData);

    test('범례가 묻는 것이 모두 온다', () async {
      // legend.LegendFacts.fromJson: kinds · certainty · historicity(_ids) · has의 열쇠 열여덟.
      final legend = await ask({'op': 'legend_kinds'});
      expect(listOf(legend, 'kinds').first.keys, containsAll(['id', 'kind', 'name', 'hint', 'dep']));
      expect(legend['certainty'], isA<List>());
      final has = (legend['has'] as Map).cast<String, dynamic>();
      expect(
        has.keys,
        containsAll([
          'range', 'unknown', 'scope', 'hollow', 'revival', 'partial', 'join', 'depOut', 'depIn',
          'figure', 'cellAlt', 'cellFuzzy', 'phase', 'rank', 'treaty', 'cats', 'culture', 'zone',
        ]),
      );
    }, skip: ready ? false : noData);

    test('필터 시트의 대범위 칩이 읽는 것이 온다', () async {
      // filter_sheet_body._askChips: scopes[].uid · track · name · color · label · members · default.
      final answer = await ask({'op': 'scopes'});
      final scopes = listOf(answer, 'scopes');
      expect(scopes, isNotEmpty);
      expect(scopes.first.keys, containsAll(['uid', 'track', 'name', 'color', 'label', 'members', 'default']));
      expect(scopes.first['track'], isA<int>());
    }, skip: ready ? false : noData);

    test('필터 시트의 분류 칩 번호가 사건의 분류 번호와 같다', () async {
      // filter_sheet_body는 layout의 categories[].id를 칩의 값으로 쓰고 그대로 cats_off에 싣는데,
      // layout의 id는 1부터이고 사건의 분류 번호(look & 0xFF)는 0부터다 — 한 칸씩 어긋난다.
      final shape = await ask({'op': 'layout'});
      final legend = await ask({'op': 'legend_kinds'});
      // 칩의 값은 배치가 읽은 분류 번호(CategoryInfo.id — 목록에서의 자리 · 0부터)다. 답의 `id`(저장소의 표 번호 · 1부터)는 쓰지 않는다.
      final ids = [for (final c in SceneLayout.fromJson(shape).categories) c.id];
      final used = [for (final n in (legend['categories'] as List)) (n as num).toInt()];
      expect(ids, containsAll(used));
      expect(ids.first, used.first);
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  6. 거르개 · 변형 — 필터 시트와 보기 상태가 자료에 닿는가
  // ──────────────────────────────────────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  부품이 **실제로 보내는 꼴** — 분은 double이다(jsonEncode가 `-615360960.0`으로 적는다)
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('부품이 보내는 수의 꼴', () {
    test('분을 소수 꼴로 물어도 정수로 물은 것과 답이 같다', () async {
      // 2026-09-22: 엔진이 정수만 받아 실제 앱에서만 '이 시기의 사건' · 같은 시기 타국 · 같은 해 보기 · 묶음 카드가 조용히 비었다
      // (부품은 실패를 삼켜 그 묶음만 비우고, 이 검사는 그때 정수로만 물었다). 이제 부품과 같은 double로도 묻는다.
      final lo = eventAt.toDouble(), hi = eventAt + 525960.0 * 40;
      for (final (whole, float) in [
        ({'op': 'same_year', 'at': eventAt, 'end': eventAt, 'window': 525960}, {'op': 'same_year', 'at': lo, 'end': lo, 'window': 525960.0}),
        ({'op': 'search_year', 't': eventAt, 'end': eventAt, 'limit': 21, 'after': 0}, {'op': 'search_year', 't': lo, 'end': lo, 'limit': 21, 'after': 0}),
        ({'op': 'events_in', 'band': bandUid, 'lo': eventAt, 'hi': hi.round(), 'limit': 50}, {'op': 'events_in', 'band': bandUid, 'lo': lo, 'hi': hi, 'limit': 50}),
        (
          {'op': 'echo', 'spots': [{'uid': bandUid, 'start': eventAt, 'end': hi.round()}], 'limit': 50},
          {'op': 'echo', 'spots': [{'uid': bandUid, 'start': lo, 'end': hi}], 'limit': 50},
        ),
        ({'op': 'list', 'lo': eventAt, 'hi': hi.round(), 'lane': 1, 'lanes': 1, 'after': 0}, {'op': 'list', 'lo': lo, 'hi': hi, 'lane': 1.0, 'lanes': 1.0, 'after': 0.0}),
      ]) {
        expect(jsonEncode(await ask(float)), jsonEncode(await ask(whole)), reason: '${whole['op']}');
      }
    }, skip: ready ? false : noData);
  });

  group('거르개와 변형', () {
    Map<String, dynamic> nearQuery([Map<String, dynamic>? filter, List<String>? variants]) => {
      'op': 'rows_near',
      'near': [bandStart, bandEnd],
      'far': [-900000000, -800000000],
      'fade': 525960,
      'packs': allPacks,
      'filter': ?filter,
      'variants': ?variants,
    };

    test('거르개가 없으면 답이 거르개를 넣기 전과 같다', () async {
      final plain = await ask(nearQuery());
      final empty = await ask(nearQuery(const {}));
      expect(empty['near'], plain['near']);
      expect(empty['far'], plain['far']);
    }, skip: ready ? false : noData);

    test('끈 트랙 · 중요도 문턱이 빈 줄 접기 · 검색 · 표 · 같은 해 보기에 똑같이 걸린다', () async {
      final plain = await ask(nearQuery());
      final trackOff = await ask(nearQuery(const {'tracks_off': [1]}));
      expect((trackOff['near'] as List).length, lessThan((plain['near'] as List).length));

      final foundAll = await ask({'op': 'search', 'text': '유리항', 'kinds': ['period', 'event'], 'limit': 50});
      final foundOff = await ask({'op': 'search', 'text': '유리항', 'kinds': ['period', 'event'], 'limit': 50, 'filter': const {'tracks_off': [1]}});
      expect(foundOff['total'], lessThan(foundAll['total'] as num));

      final tableAll = await ask({'op': 'table', 'with_periods': true, 'limit': 5});
      final tableTop = await ask({'op': 'table', 'with_periods': true, 'limit': 5, 'filter': const {'min_importance': 3}});
      expect(tableTop['count'], lessThan(tableAll['count'] as num));

      final yearAll = await ask({'op': 'same_year', 'at': figureAt, 'window': 525960});
      final yearOff = await ask({'op': 'same_year', 'at': figureAt, 'window': 525960, 'filter': const {'tracks_off': [1]}});
      expect((yearOff['tracks'] as List).length, lessThan((yearAll['tracks'] as List).length));
    }, skip: ready ? false : noData);

    test('거르개의 잘못된 값은 까닭을 적은 한국어 글로 거절한다', () async {
      await expectLater(
        ask(nearQuery(const {'tracks_off': ['하나']})),
        throwsA(isA<StateError>().having((e) => e.message, '까닭', contains('거르개'))),
      );
    }, skip: ready ? false : noData);

    test('켠 변형을 줄을 돌려주는 명령들이 모두 받는다', () async {
      const on = ['scope:moonwake-chronicle/scope-warlords'];
      await ask(nearQuery(null, on));
      await ask({'op': 'row_labels', 'rows': const [1], 'at': bandStart, 'variants': on});
      final cards = await ask({'op': 'list', 'lo': bandStart, 'hi': bandEnd, 'lane': 1, 'lanes': 1, 'after': 0, 'variants': on});
      expect(listOf(cards, 'items'), isNotEmpty);
      final events = await ask({'op': 'events_in', 'band': bandId, 'lo': bandStart, 'hi': bandEnd, 'variants': on});
      expect(listOf(events, 'items'), isNotEmpty);
    }, skip: ready ? false : noData);

    test('모르는 변형 열쇠는 까닭을 적은 한국어 글로 거절한다', () async {
      await expectLater(
        ask(nearQuery(null, const ['scope:no-such-scope'])),
        throwsA(isA<StateError>().having((e) => e.message, '까닭', matches(RegExp('[가-힣]')))),
      );
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  7. 줄 이름 · 빈 줄 접기 · 보조 달력 — 장면이 곁들여 묻는 것
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('장면이 묻는 것', () {
    test('빈 줄 접기가 가까운 줄 · 먼 줄을 준다', () async {
      // scene/fold.dart FoldQuery.toQuery
      final answer = await ask({
        'op': 'rows_near',
        'near': [bandStart, bandEnd],
        'far': [bandStart - 10000000, bandEnd + 10000000],
        'fade': 525960,
        'packs': allPacks,
      });
      expect(answer['near'], isA<List>());
      expect(answer['far'], isA<List>());
      expect(answer['near'] as List, isNotEmpty);
    }, skip: ready ? false : noData);

    test('줄 이름이 왼쪽 칸이 읽는 꼴로 온다', () async {
      // scene/row_labels.dart: labels[].row · items[]의 RowLabel.fromJson.
      final answer = await ask({'op': 'row_labels', 'rows': const [1], 'at': bandStart});
      final labels = listOf(answer, 'labels');
      expect(labels, hasLength(1));
      final items = (labels.first['items'] as List).cast<Map>();
      expect(items, isNotEmpty);
      expect(items.first.keys, containsAll(['name', 'color', 'start', 'end', 'kind', 'row', 'period', 'years', 'cap', 'member', 'lanes']));
    }, skip: ready ? false : noData);

    test('보조 달력의 환산표를 받을 수 있다', () async {
      // scene/aux_calendar.dart가 {'op':'entity','uid':'cal:<달력>'}로 묻는다 — 저장소에 그런 기록이 없다(검증 6절 4).
      final answer = await ask({'op': 'entity', 'uid': 'cal:chinese'});
      expect(answer['json'], isNotNull);
    }, skip: ready ? false : noData);
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  8. 연표에서 누른 것 → 상세: 자료가 가리키는 이름이 항목 기록과 맞는가
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('연표가 가리키는 이름', () {
    test('띠가 가리키는 이름은 모두 항목 기록에 있다', () async {
      // archive_app._hitMore: 띠 · 네모 · 이름표 · 칸 → uid_of 또는 자료에 실린 uid로 bus.select.
      for (final id in const [1, 2, 3, 7, 28]) {
        final answer = await ask({'op': 'uid_of', 'kind': 'band', 'id': id});
        final uid = '${answer['uid']}';
        expect(uid, isNotEmpty);
        final found = await ask({'op': 'entity', 'uid': uid});
        expect(found['uid'], uid);
      }
    }, skip: ready ? false : noData);

    test('칸이 가리키는 항목 · 속국 이름표 · 인물 막대의 이름이 항목 기록에 있다', () async {
      // 구역 43(왕조 · 기관 · 예속 칸이 가리키는 것) · 16(속국 이름표) · 37(인물 막대)의 text2.
      for (final uid in const [
        'moonwake-chronicle/d-canopy-0-0', // 구역 43이 가리키는 왕조
        'moonwake-chronicle/agency-p-canopy-0', // 구역 43이 가리키는 기관
        'moonwake-chronicle/client-0', // 구역 16의 속국
        'moonwake-chronicle/f-coast-0-0', // 구역 37의 인물
      ]) {
        final found = await ask({'op': 'entity', 'uid': uid});
        expect(found['uid'], uid);
      }
    }, skip: ready ? false : noData);

    test('띠 안 칸의 목록(cells_of)이 온다', () async {
      final answer = await ask({'op': 'cells_of', 'band': bandId, 'kind': 1});
      final items = listOf(answer, 'items');
      expect(items, isNotEmpty);
      expect(items.first.keys, containsAll(['id', 'lane', 'start', 'end', 'name', 'style', 'color']));
    }, skip: ready ? false : noData);
  });

  // ── 12물결에서 이은 새 조회 · 새 구역 ─────────────────────────────────────────
  group('12물결에서 이은 것', () {
    test('관점(lens_names)이 앱 틀이 읽는 꼴로 온다', () async {
      // 앱 틀(`archive_app.dart`의 `_askLens`)은 열쇠가 **글로 적힌 번호**인 표 둘을 읽어 `LensTitles.put`에 넣는다.
      final answer = await ask({'op': 'lens_names', 'lens': 'local'});
      expect(answer.keys, containsAll(['events', 'bands']));
      for (final key in const ['events', 'bands']) {
        final raw = answer[key];
        expect(raw, isA<Map>(), reason: '$key는 표다');
        for (final e in (raw as Map).entries) {
          expect(int.tryParse('${e.key}'), isNotNull, reason: '열쇠는 글로 적힌 번호다: ${e.key}');
          expect('${e.value}', isNotEmpty);
        }
      }
      expect((answer['events'] as Map), isNotEmpty, reason: '월흔해에는 관점을 가진 사건이 있다');

      // 트랙 번호로 물으면 그 나라의 이름, 없는 트랙은 빈 답, 모르는 관점은 거절.
      final byTrack = await ask({'op': 'lens_names', 'lens': '6'});
      expect((byTrack['events'] as Map), isNotEmpty);
      final none = await ask({'op': 'lens_names', 'lens': '999'});
      expect((none['events'] as Map), isEmpty);
      await expectLater(ask({'op': 'lens_names', 'lens': '해솔'}), throwsA(anything), reason: '모르는 관점은 까닭을 적어 거절한다');
    }, skip: ready ? false : noData);

    test('관점도 거르개를 받는다(부품이 보내는 꼴 그대로 · 소수도)', () async {
      // `ui/filter_query.dart`의 `filteredOps`에 `lens_names`가 들어 있어 앱 틀이 거르개를 얹어 보낸다.
      const filter = {'min_importance': 5};
      final filtered = await ask({'op': 'lens_names', 'lens': 'local', 'filter': filter});
      expect(filtered.keys, containsAll(['events', 'bands']));
      final asDouble = await ask({'op': 'lens_names', 'lens': 'local', 'filter': {'min_importance': 5.0}});
      expect(jsonEncode(asDouble), jsonEncode(filtered), reason: '소수 꼴로 보내도 같은 답이다');
    }, skip: ready ? false : noData);

    test('메아리에 `함께 · 〈나라〉` 이름이 실려 온다(정수로도 소수로도)', () async {
      // 창(`ui/detail_echo.dart`)의 `_tailOf`가 읽는 `with`. 지금 연표의 `pl.polityName`과 같은 자리다.
      const start = -640607040, end = -562764960;
      Future<List<Map<String, dynamic>>> rowsOf(Object a, Object b) async {
        final answer = await ask({'op': 'echo', 'spots': [{'uid': 'moonwake-chronicle/client-3', 'start': a, 'end': b}], 'limit': 200});
        return [
          for (final g in listOf(answer, 'groups'))
            for (final e in (g['events'] is List ? (g['events'] as List) : const [])) Map<String, dynamic>.from(e as Map),
        ];
      }
      final whole = await rowsOf(start, end), float = await rowsOf(start.toDouble(), end.toDouble());
      expect(jsonEncode(float), jsonEncode(whole), reason: '부품은 분을 소수 꼴로 보낸다');
      expect(whole, isNotEmpty);
      for (final row in whole) {
        expect(row.keys, contains('with'), reason: '메아리 줄에는 함께 겪은 나라의 자리가 있다');
        expect(row['with'], isA<List>());
      }
      final named = whole.where((r) => (r['with'] as List).isNotEmpty).toList();
      expect(named, isNotEmpty, reason: '월흔해에는 함께 겪은 사건이 있다');
      for (final one in (named.first['with'] as List)) {
        expect('$one', isNotEmpty);
      }
    }, skip: ready ? false : noData);

    test('타일의 구역 46(지도자 칸의 다른 표기)이 칸 층이 읽는 꼴로 실려 온다', () async {
      // 구역 46은 조회가 아니라 **타일**로 온다. 칸 층(`paint/strips.dart`의 `_readItems`)이 읽는 것과 같은 열쇠를 굳힌다:
      // `ref`(그 칸이 든 띠의 번호) · `a`(칸 종류 1 = 지도자) · `c`(칸의 순번 + 1) · `d`(대수 + 1 · 0이면 없음) ·
      // `name`(묘호) · `text2`("시호\t이름"). 앱과 같은 길(`engine.tile`)로 받아 같은 해독기(`Tile.decode`)로 푼다.
      Tile? found;
      for (int level = 14; level >= 6 && found == null; level--) {
        final x = tileOf(bandStart, level);
        for (int chunk = 0; chunk < 4 && found == null; chunk++) {
          final bytes = await engine!.tile(level, x, chunk, allPacks);
          if (bytes.isEmpty) continue;
          final tile = Tile.decode(bytes);
          if (tile.section(46).count > 0) found = tile;
        }
      }
      expect(found, isNotNull, reason: '새 저장소(moonwake3i)에는 구역 46이 실려 있다 — 없으면 `export/strips.mjs`를 붙여 다시 내보내 넣는다');
      final s = found!.section(46);
      final a = s.u(Tile.itemA), c = s.u(Tile.itemC), d = s.u(Tile.itemD);
      final ref = s.u(Tile.itemRef), name = s.u(Tile.itemName), text2 = s.u(Tile.itemText2);
      var withName = 0, withOrdinal = 0;
      for (int i = 0; i < s.count; i++) {
        expect(a[i], 1, reason: '지도자 칸(칸 종류 1)에만 붙는다');
        expect(c[i], greaterThan(0), reason: '칸의 순번 + 1');
        expect(ref[i], greaterThan(0), reason: '그 칸이 든 띠의 번호');
        expect(found.text(text2[i]), contains('\t'), reason: '시호와 이름을 탭으로 잇는다');
        if (found.text(name[i]).isNotEmpty) withName++;
        if (d[i] > 0) withOrdinal++;
      }
      expect(withName + withOrdinal, greaterThan(0), reason: '묘호나 대수 가운데 하나는 실려 있다');
    }, skip: ready ? false : noData);
  });
}
