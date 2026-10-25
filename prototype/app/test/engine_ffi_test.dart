import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/ui/dlc_layout_import.dart' show DlcPackFacts;
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_import.dart';
import 'support/engine_source.dart';

// 진짜 자료 처리부(DLL)와 진짜 저장소를 거치는 검사. 둘 다 만들어 둔 컴퓨터에서만 돈다:
//   scripts/dev.ps1 engine-build  ·  archive-tool generate2 data/v3-100k/archive.db 100000 fixtures
void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  final db = File('../data/v3-100k/archive.db');
  final ready = dll.existsSync() && db.existsSync();

  test('작업자가 받아 온 타일은 도구가 만든 고정 파일과 바이트까지 같다', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final info = await engine.start(db.absolute.path);
    // v3-100k는 따로 지어 둔 저장소라 판이 지은 도구를 따른다(스키마 3 도구 '3' · 스키마 4 도구 '4') — 지금 엔진이 여는 판(schema.rs OPENS)이면 된다.
    expect(info['data']['meta']['schema'], isIn(engineOpensVersions()));
    final bytes = await engine.tile(9, 0, 0, const [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(bytes, File('test/fixtures/tile-100k-L9-x0-c0.bin').readAsBytesSync());
    expect(Tile.decode(bytes).bandCount, 19);
    final layout = await engine.call({'op': 'layout'});
    expect((layout['data']['tracks'] as List).length, 56);
    // 3판의 뼈대: 트랙의 색과 단 · 민족 묶음 · 분류 · 나라별 날짜 칸.
    final first = (layout['data']['tracks'] as List).first as Map<String, dynamic>;
    expect(first['color'], isNot(0));
    expect((first['groups'] as List).length, greaterThanOrEqualTo(2));
    expect((first['rows'] as List).first, containsPair('fig_wide', isA<int>()));
    expect((layout['data']['categories'] as List).length, 5);
    expect((layout['data']['axis'] as List).length, 96);
  }, skip: ready ? false : '자료 처리부 DLL 또는 data/v3-100k 저장소가 없습니다');

  test('3판의 조회 명령도 작업자를 거쳐 온다', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    final near = await engine.call({
      'op': 'rows_near',
      'near': [0, 1440 * 365],
      'fade': 0,
      'packs': const [1, 2, 3, 4, 5, 6, 7, 8],
    });
    expect((near['data']['near'] as List), isNotEmpty);
    expect((near['data']['far'] as List), isEmpty);
    final labels = await engine.call({'op': 'row_labels', 'rows': const [0, 1]});
    expect((labels['data']['labels'] as List).length, 2);
    expect(((labels['data']['labels'] as List).first as Map)['items'], isNotEmpty);
  }, skip: ready ? false : '자료 처리부 DLL 또는 data/v3-100k 저장소가 없습니다');

  test('저장소를 놓으면(close) 조회 · 타일이 까닭과 함께 실패하고, 다시 열면(open) 돌아온다 — DLC를 바꿔 넣는 길', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    expect((await engine.tile(9, 0, 0, const [1])).length, greaterThan(76));
    final closed = await engine.call({'op': 'close'});
    expect(closed['data']['closed'], isTrue);
    await expectLater(engine.call({'op': 'layout'}), throwsA(isA<StateError>().having((e) => e.message, '까닭', contains('열리지 않았습니다'))));
    await expectLater(engine.tile(9, 0, 0, const [1]), throwsA(isA<StateError>().having((e) => e.message, '까닭', contains('열리지 않았습니다'))));
    final again = await engine.call({'op': 'open', 'path': db.absolute.path});
    expect(again['data']['meta']['schema'], isIn(engineOpensVersions()), reason: '다시 연 저장소도 지금 엔진이 여는 판');
    expect((await engine.tile(9, 0, 0, const [1])).length, greaterThan(76));
    expect(((await engine.call({'op': 'layout'}))['data']['packs'] as List).first, containsPair('key', isA<String>()), reason: '3판의 뼈대는 DLC의 글자 열쇠도 준다(옛 저장소는 빈 글)');
  }, skip: ready ? false : '자료 처리부 DLL 또는 data/v3-100k 저장소가 없습니다');

  test('잘못된 타일 요청은 까닭과 함께 실패한다', () async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    await expectLater(
      engine.tile(99, 0, 0, const [1]),
      throwsA(isA<StateError>().having((e) => e.message, '까닭', contains('범위 밖'))),
    );
    // 실패한 뒤에도 작업자는 계속 일한다.
    expect((await engine.tile(9, 0, 0, const [1])).length, greaterThan(76));
  }, skip: ready ? false : '자료 처리부 DLL 또는 data/v3-100k 저장소가 없습니다');

  // 배치 가져오기(A2 — `archive_import` · `docs/설계-10건/A-아카이브-이음.md` 5-5 · 5-6): 메이커의 .htlayout을 Node 없이 저장소로.
  // 저장소 자료는 필요 없다(고정 자료 tiny.htlayout으로 짓는다). 자료 처리부에 archive_import가 들어온 뒤(A2-a 합친 뒤)에 돈다.
  final hasImport = dll.existsSync() && engineHasImport(dll.absolute.path);
  final importSkip = hasImport ? false : '자료 처리부에 archive_import가 없습니다(A2-a 합친 뒤에 돈다)';
  final tiny = File('test/fixtures/tiny.htlayout').absolute.path;

  /// tiny.htlayout을 원본 없이 새 저장소로 짓는다(지금 저장소를 주면 조합을 대조하고 그 원본을 옮긴다).
  Future<(String, Map<String, dynamic>)> importTiny(Directory dir, String name, {String? fromStore}) async {
    final out = '${dir.path}/$name';
    final answer = await callArchiveImport(layoutImportRequest(layout: tiny, out: out, fromStore: fromStore), libraryPath: dll.absolute.path);
    return (out, answer);
  }

  Directory scratch() {
    final dir = Directory.systemTemp.createTempSync('ht-ffi-import-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  /// 저장소를 놓고 작업자를 닫는다. Windows는 열린 저장소 파일을 지우지 못하는데, 작업자만 닫으면(close) 자료 처리부가
  /// 저장소를 쥔 채로 남는다 — 그래서 임시 폴더를 지우기 전에(뒤처리는 등록의 거꾸로 차례) 저장소부터 놓는다.
  Future<void> release(ArchiveEngine engine) async {
    try {
      await engine.call({'op': 'close'});
    } catch (_) {
      // 저장소를 열기 전에 끝난 검사 — 놓을 것이 없다.
    }
    engine.close();
  }

  test('쓰기 일꾼(apply — 계약 2-7)은 따로 된 isolate에서 같은 자료 처리부를 열어 작업자가 연 저장소를 고쳐 쓰고, 그동안에도 작업자의 타일이 답한다', () async {
    final dir = scratch();
    final (out, built) = await importTiny(dir, 'archive.db');
    expect(built['ok'], isTrue, reason: '$built');
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(() => release(engine));
    await engine.start(out);
    final before = await engine.call({'op': 'layout'});
    // 같은 배치를 다시: 바뀐 것 없음(first_pos −1). 쓰기 일꾼이 작업자의 열린 저장소를 본다(같은 DLL을 다시 열어도 같은 전역 저장소 — 아니면 '열리지 않았습니다').
    final writing = engine.apply({'layout': tiny});
    final tiles = await Future.wait([for (int i = 0; i < 4; i++) engine.tile(9, 0, 0, const [1])]);
    final answer = await writing;
    expect(answer['ok'], isTrue, reason: '$answer');
    expect((answer['data'] as Map)['first_pos'], -1);
    expect((answer['data'] as Map)['rewrote'], isEmpty);
    expect(tiles.every((t) => t.isNotEmpty), isTrue, reason: '쓰는 동안에도 작업자의 타일이 답한다');
    // 거절(배치 파일로는 뺄 수 없다)은 저장소 그대로 · committed 없음 · 작업자는 계속 답한다.
    final refused = await engine.apply({'layout': tiny, 'remove': ['tiny-reed']});
    expect(refused['ok'], isFalse, reason: '$refused');
    expect(refused.containsKey('committed'), isFalse);
    expect((await engine.call({'op': 'layout'}))['data'], before['data']);
  }, skip: importSkip);

  test('진짜 자료 처리부로 tiny.htlayout → 저장소 → open → layout(원본 없이 · 판이 실리기 전의 배치)', () async {
    final dir = scratch();
    final (out, answer) = await importTiny(dir, 'archive.db');
    expect(answer['ok'], isTrue, reason: '$answer');
    final data = answer['data'] as Map;
    expect([for (final p in data['packs'] as List) (p as Map)['id']], ['tiny-reed']);
    expect(data['events'], 2);
    expect(data['verify'], allOf(containsPair('missing', 0), containsPair('dup', 0)));
    expect(File(out).existsSync(), isTrue);
    // 같은 자리에 다시 지으라 하면 덮어쓰지 않는다.
    final (_, again) = await importTiny(dir, 'archive.db');
    expect(again['ok'], isFalse);

    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(() => release(engine));
    final info = await engine.start(out);
    // 새로 지은 저장소의 판 = 지금 엔진이 짓는 판(schema.rs VERSION — 스키마 4 엔진은 '4'). 위의 v3-100k는 따로 지어 둔 저장소라 여는 판(OPENS)이면 된다.
    expect(info['data']['meta']['schema'], engineSchemaVersion());
    expect(DlcPackFacts.fromMeta(info['data']['meta'] as Map)['tiny-reed']?.original, isFalse, reason: '원본 없이 넣었다 — meta.pack_info');
    final layout = await engine.call({'op': 'layout'});
    final packs = layout['data']['packs'] as List;
    expect(packs.single, containsPair('key', 'tiny-reed'));
    expect(DlcPackFacts.fromLayoutJson(layout['data'] as Map)['tiny-reed']?.original, isFalse, reason: 'layout.packs[].original');
    expect([for (final t in layout['data']['tracks'] as List) (t as Map)['name']], ['갈대 들']);
    expect((await engine.tile(9, 0, 0, const [1])).length, greaterThan(0));
  }, skip: importSkip);

  test('가져오기가 도는 동안에도 엔진 작업자의 조회가 답한다 — archive_import는 STORE를 잡지 않는다', () async {
    final dir = scratch();
    final (live, first) = await importTiny(dir, 'archive.db');
    expect(first['ok'], isTrue, reason: '$first');
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(() => release(engine));
    await engine.start(live);
    // 지금 저장소(같은 조합)를 주고 옆에 다시 짓는 동안 엔진 작업자에 조회를 잇달아 보낸다.
    final importing = importTiny(dir, 'archive.새로-지음.db', fromStore: live);
    final answers = await Future.wait([for (int i = 0; i < 20; i++) engine.call({'op': 'layout'})]);
    expect(answers.every((a) => a['ok'] == true), isTrue);
    final (fresh, second) = await importing;
    expect(second['ok'], isTrue, reason: '$second');
    expect(File(fresh).existsSync(), isTrue);
    expect((second['data'] as Map)['warnings'], anyElement(contains('판을 확인할 수 없습니다')), reason: '판이 실리기 전의 배치 — id로만 대조(5-3 넷째)');
  }, skip: importSkip);
}
