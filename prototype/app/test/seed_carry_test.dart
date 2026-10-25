import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/ui/dlc_add.dart';
import 'package:archive_prototype/ui/dlc_layout_import.dart';
import 'package:archive_prototype/ui/seed_carry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_import.dart';
import 'support/pack_scene.dart';

// 앱의 새 판(시드)을 놓아도 사용자가 넣은 DLC가 남는다(계획 한 벌 P4 정한 것 #14 · 옛 DLC의 약속 2 · 판정 R34 D — 과제 8 · 10a · 10b).
// 흉내로 흐름을 굳힌다: 새 시드를 옆에 먼저 쓰고 → 두 저장소의 DLC 목록 · 보관함을 견주어 사용자 DLC를 가리고 → 자료 처리부로 그 새 시드에 넣은
// 뒤에야 옛 저장소를 바꾼다(넣지 못하면 옛 저장소 그대로 · 알림). 끝의 무리는 진짜 자료 처리부(FFI · archive-tool — 빠른 빌드)로 같은 흐름을 잰다.

/// 임시 폴더의 저장소 자리 · 표식 · DLC 폴더.
class _Seat {
  _Seat() {
    dir = Directory.systemTemp.createTempSync('ht-seed-carry-');
    db = '${dir.path}${Platform.pathSeparator}archive.db';
  }
  late final Directory dir;
  late final String db;
  File get mark => File('$db.seed');
  File get keptMark => File('$db.seed-kept');
  String inDlc(String name) => '${dir.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}$name';
  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// DLC 파일(형식 3 — 팩 파일 종류 1)을 [path]에 쓴다(본문은 맨 바깥 칸만 — 앱이 머리로 id · 판을 읽는다).
String _writeDlc(String path, String id, String version) {
  final plain = utf8.encode(jsonEncode({'format': 'history-timeline-dlc', 'id': id, 'name': id, 'version': version})), body = ZLibCodec().encode(plain);
  final head = Uint8List(packFileHeader)
    ..setAll(0, packFileMagic)
    ..[8] = packFileVersion
    ..[9] = packKindDlc
    ..[10] = 1;
  ByteData.sublistView(head)
    ..setUint32(12, plain.length, Endian.little)
    ..setUint32(16, body.length, Endian.little);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync([...head, ...body]);
  return path;
}

/// 엔진 · 엔진 도구의 흉내 — 저장소의 글(어떤 저장소인가)로 DLC 목록 · 보관함을 답하고, 새 시드에 넣기는 적어 두고 그 파일 글 뒤에 넣은 id를 붙인다.
class _Tool {
  _Tool(this.packsOf, {this.keptOf = const {}});
  final Map<String, List<SeedPack>> packsOf;
  final Map<String, List<SeedPack>> keptOf;
  final listed = <String>[], outs = <String>[];
  final carried = <({String seed, String from, List<SeedCarryAdd> adds, List<String> keep})>[];
  bool failOut = false;
  SeedCarryAnswer answer = const SeedCarryAnswer.ok();

  Future<List<SeedPack>?> list(String db) async {
    final text = File(db).readAsStringSync();
    listed.add(text);
    return packsOf[text];
  }

  Future<List<SeedPack>?> kept(String db) async => keptOf[File(db).readAsStringSync()] ?? const [];

  Future<bool> out(String db, String id, String file) async {
    outs.add('$id → ${file.split(Platform.pathSeparator).last}');
    if (failOut) return false;
    File(file).writeAsStringSync('원본 $id (${File(db).readAsStringSync()}에서)');
    return true;
  }

  Future<SeedCarryAnswer> carry({required String seed, required String from, required List<SeedCarryAdd> adds, required List<String> keep}) async {
    // 흉내가 실제 길([seedCarrySteps] — 판정 R63-1)과 다른 답을 굳히지 않게: 빼고 넣는 거절은 DLC 탓 code만, 멈춤은 그 밖(code 없음 포함)만.
    if (answer.rejected.any((r) => !seedCarryDlcFaults.contains(r.code))) throw StateError('흉내 답이 실제 길과 다르다 — DLC 탓이 아닌 code로 빼고 넣음');
    if (!answer.ok && seedCarryDlcFaults.contains(answer.code)) throw StateError('흉내 답이 실제 길과 다르다 — DLC 탓 code로 멈춤');
    carried.add((seed: seed, from: from, adds: adds, keep: keep));
    if (!answer.ok) return answer;
    final rejected = {for (final r in answer.rejected) r.id};
    final ids = [for (final a in adds) ...a.ids.where((id) => !rejected.contains(id)), for (final a in adds) if (a.file != null && !rejected.contains(a.fileId)) a.file!.split(Platform.pathSeparator).last];
    File(seed).writeAsStringSync('${File(seed).readAsStringSync()}+${ids.join(',')}${keep.isEmpty ? '' : '(끔 ${keep.join(',')})'}');
    return answer;
  }

  /// 컴퓨터(엔진 도구가 있는 곳 — 바탕이 다르면 꺼내 두기).
  SeedCarry get computer => SeedCarry(listPacks: list, listKept: kept, packOut: out, carryInto: carry);

  /// 휴대폰(꺼낼 길 없음 — 자료 처리부만).
  SeedCarry phone({Future<Map<String, String>> Function(String db)? names, bool engine = true}) =>
      SeedCarry(listPacks: list, listKept: kept, carryInto: engine ? carry : null, names: names);
}

/// Node 내장 sqlite로 저장소를 고친다(달력 표 · 원본 지우기 — 이 계획 전의 옛 저장소 꼴을 만든다 · 엔진 도구에는 그런 명령이 없다).
/// Node가 없거나(시작 못 함) 내장 sqlite가 없는 옛 Node면([nodeSqliteMissing]) 건너뛸 까닭을, 되면 null(11c 검토). **그 밖의 실패는 검사 실패**다
/// (③ I-3 — 스크립트 · 저장소가 틀려도 건너뜀으로 숨지 않게).
Future<String?> _nodeSqlite(String script, List<String> args) async {
  try {
    final run = await Process.run('node', ['-e', script, ...args]);
    if (run.exitCode == 0) return null;
    if (nodeSqliteMissing('${run.stderr}')) return 'Node에 내장 sqlite(node:sqlite)가 없습니다 — 옛 저장소 꼴을 만들 수 없어 건너뜁니다';
    fail('Node 내장 sqlite로 저장소를 고치다 실패했습니다(종료 코드 ${run.exitCode}): ${run.stderr}');
  } on ProcessException catch (e) {
    return 'Node가 없습니다 — 옛 저장소 꼴을 만들 수 없어 건너뜁니다: ${e.message}';
  }
}

/// Node의 오류 줄이 '내장 sqlite가 없음'(node:sqlite를 모르는 옛 Node)인가 — 그때만 건너뛴다(③ I-3).
bool nodeSqliteMissing(String stderr) =>
    stderr.contains('ERR_UNKNOWN_BUILTIN_MODULE') || stderr.contains("Cannot find module 'node:sqlite'") || stderr.contains('No such built-in module: node:sqlite');

/// 덩이들을 글로(검사의 기대값) — `ids:a,b` · `file:<이름>`.
List<String> _adds(List<SeedCarryAdd> adds) => [for (final a in adds) a.file != null ? 'file:${a.file!.split(Platform.pathSeparator).last}' : 'ids:${a.ids.join(',')}'];

void main() {
  late _Seat seat;
  setUp(() => seat = _Seat());
  tearDown(() => seat.dispose());

  /// 0.0.3 시드(기본팩 2.0.0 · 견본 등불 1.0.0)에 사용자가 KoreanTimeLine 흉내(1.0.5)를 넣은 저장소 → 0.0.4 시드(기본팩 2.1.0 · 등불 1.1.0).
  final packs = {
    '옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('korean-timeline', '1.0.5'), SeedPack('lantern', '1.0.0')],
    '새 시드': const [SeedPack('east-asia-base', '2.1.0'), SeedPack('lantern', '1.1.0')],
  };
  Future<List<int>> newSeed() async => utf8.encode('새 시드');

  for (final (where, phone) in const [('컴퓨터', false), ('휴대폰', true)]) {
    test('$where: 시드 판이 바뀌어도 사용자 DLC(KoreanTimeLine 흉내)가 남는다 — 옆 파일의 새 시드에 옛 저장소에서(from_store) 넣은 뒤 바꿔 놓는다', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool(packs);
      final result = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.kept, isNull);
      expect(result.placed, isTrue);
      expect(result.moved, ['korean-timeline'], reason: '시드에 든 기본팩 · 견본은 넣지 않는다(새 시드의 판이 이긴다)');
      final carried = tool.carried.single;
      expect(carried.seed, '${seat.db}.새-시드', reason: '옆 파일(새 시드)에 넣는다 — 옛 저장소는 다 넣은 뒤에야 바꾼다');
      expect(carried.from, seat.db);
      expect(_adds(carried.adds), ['ids:korean-timeline']);
      expect(File(seat.db).readAsStringSync(), '새 시드+korean-timeline', reason: '넣은 새 시드가 제자리에');
      expect(seat.mark.readAsStringSync(), '0.0.4');
      expect(result.note, '넣어 두었던 DLC «korean-timeline»을(를) 앱의 새 판 자료로 옮겼습니다.');
      expect(tool.outs, isEmpty, reason: '파일로 꺼내지 않는다(엔진이 옛 저장소에서 바로 읽는다 — 판정 R34 D)');
      expect(tool.listed, ['옛 저장소', '새 시드'], reason: '새 시드는 옆 파일에 먼저 써서 그 목록을 읽는다');
      expect(seat.dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toSet(), {'archive.db', 'archive.db.seed', 'archive.db.seed-packs'},
          reason: '옆 파일 · 비킨 옛 저장소가 남지 않는다(놓은 시드의 팩 기록만 더해짐)');
    });

    test('$where: 넣지 못하면(저장소 쪽 거절) 옛 저장소 · 표식 그대로 · 쉬운 말로 알림 — 옆 파일은 버린다', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      const why = '기본팩이 다릅니다(저장소 «동아시아» · 배치 «등불»)';
      final tool = _Tool(packs)..answer = const SeedCarryAnswer.failed(why, code: 'base');
      final result = await (phone ? tool.phone(names: (db) async => {'korean-timeline': 'Tigers of the East'}) : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isFalse);
      expect(result.kept, startsWith('앱의 새 판 자료로 바꾸지 않았습니다 — 넣어 둔 DLC «${phone ? 'Tigers of the East' : 'korean-timeline'}»를 새 판 자료로 옮기지 못해 지금 저장소를 그대로 둡니다'));
      expect(result.kept, contains(dlcRefusalText('base', why)));
      expect(File(seat.db).readAsStringSync(), '옛 저장소');
      expect(seat.mark.readAsStringSync(), '0.0.3');
      expect(File('${seat.db}.새-시드').existsSync(), isFalse);
      // 휴대폰은 그 판을 다시 해 보지 않는다(실행마다 같은 실패 · 알림이 되풀이되지 않게) · 컴퓨터는 다음에 켤 때 다시 해 본다.
      expect(seat.keptMark.existsSync(), phone);
      final again = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(again.kept, phone ? isNull : isNotNull);
      expect(tool.carried, hasLength(phone ? 1 : 2));
    });

    test('$where: code 없는 실패(디스크 가득 · 열기 실패 · 패닉 — 환경 탓)는 멈추고 다음에 켤 때 다시 해 본다 — DLC를 빼고 새 판을 놓지 않는다(판정 R63-1)', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool(packs)..answer = const SeedCarryAnswer.failed('디스크가 가득 찼습니다');
      final result = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isFalse);
      expect(result.kept, allOf(contains('다음에 앱을 켤 때 다시 해 봅니다'), contains('디스크가 가득 찼습니다')));
      expect(File(seat.db).readAsStringSync(), '옛 저장소');
      expect(seat.keptMark.existsSync(), isFalse, reason: '환경 탓은 그 판을 지킴으로 정하지 않는다(휴대폰도 다음 실행에서 다시)');
      tool.answer = const SeedCarryAnswer.ok();
      final again = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(again.placed, isTrue, reason: again.kept);
      expect(File(seat.db).readAsStringSync(), '새 시드+korean-timeline');
    });

    test('$where: path(앱이 연 저장소가 그새 바뀜)도 다시 해 볼 실패 — 휴대폰도 그 판을 지킴으로 정하지 않는다(판정 R72-2)', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool(packs)..answer = const SeedCarryAnswer.failed('지금 열린 저장소가 이 요청의 저장소와 달라 쓰지 않았습니다(저장소는 그대로) — 다시 해 주세요', code: 'path');
      final result = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isFalse);
      expect(result.kept, allOf(contains('다음에 앱을 켤 때 다시 해 봅니다'), contains('앱이 연 저장소가 그새 바뀌어')));
      expect(seat.keptMark.existsSync(), isFalse, reason: 'path는 판을 붙잡지 않는다');
      tool.answer = const SeedCarryAnswer.ok();
      final again = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(again.placed, isTrue, reason: again.kept);
    });

    test('$where: code 없는 실패는 같은 시드 판에서 세 번까지 — 세 번째 뒤에는 그 판에서 더 해 보지 않고 옛 저장소로 계속 쓴다 · DLC를 빼고 놓지 않는다(판정 R68-2)', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool(packs)..answer = const SeedCarryAnswer.failed('디스크가 가득 찼습니다');
      SeedCarry carry() => phone ? tool.phone() : tool.computer;
      final first = await carry().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      final second = await carry().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect([first.kept, second.kept], everyElement(contains('다음에 앱을 켤 때 다시 해 봅니다')));
      final third = await carry().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(third.kept, allOf(contains('새 판으로 옮기지 못했습니다 — 지금 자료로 계속 씁니다'), contains('다음 앱 판에서 다시'), isNot(contains('다음에 앱을 켤 때'))));
      final fourth = await carry().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect((fourth.placed, fourth.kept, fourth.note), (false, null, null), reason: '그 판에서는 조용히 옛 저장소로');
      expect(tool.carried, hasLength(3));
      expect(File(seat.db).readAsStringSync(), '옛 저장소', reason: 'DLC를 빼고 새 판을 놓지 않는다');
      // 다음 앱 판(새 stamp)에서는 다시 해 본다 · 되면 세던 것을 지운다.
      tool.answer = const SeedCarryAnswer.ok();
      expect((await carry().place(path: seat.db, stamp: '0.0.5', seed: newSeed)).placed, isTrue);
      expect(File('${seat.db}.seed-tries').existsSync(), isFalse);
    });
  }

  test('새 판 자료에 달력 표가 없다는 시드 잇기 알림에도 엔진 글을 (자세히: …)로(② Minor 1) · 엔진의 broken(옛 저장소의 원본을 읽지 못함)은 그 DLC 탓(판정 R68-2)', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool(packs)..answer = const SeedCarryAnswer.failed('달력 표가 없는 옛 저장소입니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요', code: 'calendar');
    final result = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.kept, allOf(contains('기본 자료에 달력 표가 없어'), contains('(자세히: 달력 표가 없는 옛 저장소입니다 — 앱을 새 판으로 올린 뒤 다시 해 주세요)')));
    expect(seedCarryDlcFaults, contains('broken'));
    expect(dlcRefusalText('broken', '«reed»의 원본을 읽지 못했습니다'), allOf(contains('망가져'), contains('메이커에서 다시 저장한'), contains('자세히: «reed»')));
  });

  test('실제 엔진 검사의 Node 건너뜀은 Node가 없거나 node:sqlite가 없을 때만 — 그 밖의 실패는 건너뛰지 않는다(③ I-3)', () {
    expect(nodeSqliteMissing("node:internal/modules/cjs/loader: Error [ERR_UNKNOWN_BUILTIN_MODULE]: No such built-in module: node:sqlite"), isTrue);
    expect(nodeSqliteMissing("Error: Cannot find module 'node:sqlite'"), isTrue);
    expect(nodeSqliteMissing('SqliteError: no such table: meta'), isFalse, reason: '저장소 · 스크립트가 틀린 것은 검사 실패');
    expect(nodeSqliteMissing(''), isFalse);
  });

  test('넣기 차례: 새 판 자료가 받지 않는 DLC(dup_uid · 배치 거절)는 그것만 빼고 나머지를 넣는다 — 덩이는 하나씩 다시 해 보고 · 저장소 쪽 거절(달력 표 · 바탕)은 멈춘다 · 요청마다 쓸 파일(path)을 싣는다(판정 R59 I-3 · M-4)', () {
    final calls = <Map<String, dynamic>>[];
    Map<String, dynamic> Function(Map<String, dynamic>) engine({String? code = 'dup_uid'}) => (request) {
      calls.add(request);
      final words = [...(request['ids'] as List? ?? const []), ...(request['files'] as List? ?? const []), request['id'] ?? ''].map((w) => '$w');
      if (words.any((w) => w.contains('bad'))) return {'ok': false, 'error': '«bad»의 항목 «b-1»이 두 트랙에 있습니다', 'code': code};
      return {'ok': true, 'data': {}};
    };
    final adds = [const SeedCarryAdd.ids(['a', 'bad', 'c']), const SeedCarryAdd.file('D:/DLC/x-v1.0.0.htpack', fileId: 'x'), const SeedCarryAdd.file('D:/DLC/bad2-v1.0.0.htpack', fileId: 'bad2')];
    final answer = seedCarrySteps(seed: 'S', from: 'F', adds: adds, keep: const ['c', 'bad'], call: engine());
    expect(answer.ok, isTrue);
    expect([for (final r in answer.rejected) (r.id, r.code)], [('bad', 'dup_uid'), ('bad2', 'dup_uid')]);
    expect([for (final c in calls) c['ids'] ?? c['files'] ?? c['id']], [
      ['a', 'bad', 'c'], ['a'], ['bad'], ['c'], ['D:/DLC/x-v1.0.0.htpack'], ['D:/DLC/bad2-v1.0.0.htpack'], 'c',
    ], reason: '덩이가 거절되면 하나씩 다시 · 받지 않은 DLC는 다시 끄지도 않는다');
    expect(calls.last, {'op': 'remove_pack', 'id': 'c', 'delete': false, 'path': 'S'});
    expect(calls.every((c) => c['path'] == 'S'), isTrue, reason: '엔진이 옆 파일(새 시드)에 쓰는 것을 알게(갈래 1의 path — 없으면 엔진이 무시)');
    expect(calls.first, {'op': 'add_pack', 'from_store': 'F', 'ids': ['a', 'bad', 'c'], 'path': 'S'});
    // 저장소 쪽 거절은 DLC 탓이 아니다 — 멈추고 그 까닭을 돌려준다(옛 저장소 그대로).
    calls.clear();
    final stopped = seedCarrySteps(seed: 'S', from: 'F', adds: adds, keep: const [], call: engine(code: 'calendar'));
    expect((stopped.ok, stopped.code), (false, 'calendar'));
    expect(calls, hasLength(1));
    // range(그 DLC의 날짜가 달력 범위 밖 — DLC 쪽 잘못 · 판정 R62)는 저장소 쪽이 아니다 — 그 DLC만 빼고 나머지를 넣는다.
    calls.clear();
    final ranged = seedCarrySteps(seed: 'S', from: 'F', adds: adds, keep: const ['c', 'bad'], call: engine(code: 'range'));
    expect(ranged.ok, isTrue);
    expect([for (final r in ranged.rejected) (r.id, r.code)], [('bad', 'range'), ('bad2', 'range')]);
    calls.clear();
    final laid = seedCarrySteps(seed: 'S', from: 'F', adds: adds, keep: const [], call: engine(code: 'layout'));
    expect([for (final r in laid.rejected) (r.id, r.code)], [('bad', 'layout'), ('bad2', 'layout')], reason: '배치 거절(layout)도 그 DLC 탓');
    // DLC 탓 code(dup_uid · layout · range)가 아니면 멈춘다 — code 없는 실패(디스크 가득 · 열기 실패 · 패닉)를 DLC 탓으로 보고 빼면 새 판이 사용자 DLC 없이
    // 놓인다(판정 R63-1). 그 밖의 code(version · original …)도 멈춘다.
    for (final code in [null, 'version', 'original', 'rebuild']) {
      calls.clear();
      final halted = seedCarrySteps(seed: 'S', from: 'F', adds: adds, keep: const ['c'], call: engine(code: code));
      expect((halted.ok, halted.code), (false, code), reason: '$code');
      expect(halted.rejected, isEmpty, reason: '$code');
      expect(calls, hasLength(1), reason: '$code — 하나씩 다시 해 보지도 않는다');
    }
    expect(seedCarryDlcFaults, {'dup_uid', 'layout', 'range', 'broken'});
  });

  test('새 판 자료가 range(그 DLC의 날짜가 달력 범위 밖 — 판정 R62)로 받지 않은 DLC는 그 덩이만 DLC 폴더에 두고 나머지로 새 판을 놓는다 · 알림은 메이커에서 날짜를 고치라는 말', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    const why = '«korean-timeline»의 날짜가 앱이 아는 달력 범위 밖입니다 — 보조 달력 날짜는 -3500 ~ 2500년 안이어야 합니다';
    final tool = _Tool({
      '옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('korean-timeline', '1.0.5'), SeedPack('reed', '1.0.0')],
      '새 시드': packs['새 시드']!,
    })..answer = const SeedCarryAnswer.ok(rejected: [SeedCarryReject('korean-timeline', why, code: 'range')]);
    final result = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue, reason: result.kept);
    expect(result.moved, ['reed']);
    expect(File(seat.db).readAsStringSync(), '새 시드+reed');
    expect(File(seat.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isTrue, reason: '받지 않은 DLC의 원본은 DLC 폴더에(R59 I-3과 같은 길)');
    expect(result.note, allOf(contains(dlcRefusalText('range', why)), contains('메이커에서 그 DLC의 날짜를 고쳐'), isNot(contains('새 판으로 올리'))));
  });

  for (final (where, phone) in const [('컴퓨터', false), ('휴대폰', true)]) {
    test('$where: 새 판 자료가 받지 않는 DLC가 하나 섞여도 나머지로 새 판을 놓고 그 원본은 DLC 폴더에 둔다(판정 R59 I-3 — 막다른 길 풀기)', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool({
        '옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('korean-timeline', '1.0.5'), SeedPack('reed', '1.0.0')],
        '새 시드': packs['새 시드']!,
      })..answer = const SeedCarryAnswer.ok(rejected: [SeedCarryReject('korean-timeline', '«korean-timeline»의 항목 «k-1»이 두 트랙에 있습니다', code: 'dup_uid')]);
      // 휴대폰은 꺼낼 길이 없다 — 앱이 넣을 때 DLC 폴더에 둔 그 파일(이름은 고른 그대로)을 원본으로 남긴다.
      if (phone) _writeDlc(seat.inDlc('내 KTL.htpack'), 'korean-timeline', '1.0.5');
      final result = await (phone ? tool.phone() : tool.computer).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isTrue, reason: result.kept);
      expect(result.moved, ['reed'], reason: '받은 것만 옮겼다');
      expect(File(seat.db).readAsStringSync(), '새 시드+reed');
      expect(seat.mark.readAsStringSync(), '0.0.4');
      expect(seat.keptMark.existsSync(), isFalse);
      final kept = phone ? '내 KTL.htpack' : 'korean-timeline-v1.0.5.htpack';
      expect(tool.outs, phone ? isEmpty : ['korean-timeline → $kept'], reason: '컴퓨터는 옛 저장소에서 원본을 꺼내 둔다(R48의 이름)');
      expect(File(seat.inDlc(kept)).existsSync(), isTrue);
      expect(result.note, allOf(startsWith('넣어 두었던 DLC «reed»을(를) 앱의 새 판 자료로 옮겼습니다.'), contains('«korean-timeline»은(는) 새 판 자료가 받지 않아 옮기지 못했습니다'),
          contains(dlcRefusalText('dup_uid', '«korean-timeline»의 항목 «k-1»이 두 트랙에 있습니다')), contains(kept), contains("'파일에서 더하기'")));
      expect(result.note, isNot(contains('))')), reason: '괄호 안에 괄호를 겹치지 않는다(② 넘김)');
    });
  }

  test('휴대폰: 받지 않은 DLC의 원본을 DLC 폴더에 둘 수 없으면(꺼낼 길 없음 · 폴더에도 없음) 옛 저장소를 그대로 둔다 — 잃지 않게(판정 R59 I-3)', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool({
      '옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('korean-timeline', '1.0.5'), SeedPack('reed', '1.0.0')],
      '새 시드': packs['새 시드']!,
    })..answer = const SeedCarryAnswer.ok(rejected: [SeedCarryReject('korean-timeline', '«korean-timeline»를 연표에 배치하지 못했습니다 — 트랙 열쇠가 겹칩니다', code: 'layout')]);
    final result = await tool.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isFalse);
    expect(result.kept, allOf(contains('«korean-timeline»'), contains('원본을 DLC 폴더에 둘 수 없어')));
    expect(File(seat.db).readAsStringSync(), '옛 저장소');
    expect(seat.keptMark.readAsStringSync(), '0.0.4');
  });

  test('휴대폰: 시드의 바탕이 바뀌어도(동아시아 → 등불) 새 시드의 바탕은 다시 끌 목록(keep)에 넣지 않는다 — 엔진이 바탕 빼기를 거절해 잇기가 멈추지 않게(판정 R59)', () async {
    File(seat.db).writeAsStringSync('옛 동아시아');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool({
      '옛 동아시아': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('haesol', '1.0.0')],
      '새 시드': const [SeedPack('lantern-chronicle', '2.0.1')],
    }, keptOf: {
      '옛 동아시아': const [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('reed', '1.0.0')],
    });
    final result = await tool.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue, reason: result.kept);
    expect(tool.carried.single.keep, ['reed']);
  });

  test('넣어 둔 DLC를 옮기는 동안 진행 말을 낸다(첫 실행이 오래 걸려도 무엇을 하는지 — 판정 R60 M-12) · 옮길 것이 없으면 말하지 않는다', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final said = <String>[];
    final result = await _Tool(packs).phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed, progress: said.add);
    expect(result.placed, isTrue);
    expect(said, ['넣어 둔 DLC를 앱의 새 판 자료로 옮기는 중…']);
    said.clear();
    File(seat.db).writeAsStringSync('빈 옛 저장소');
    await _Tool({'빈 옛 저장소': const [SeedPack('east-asia-base', '2.0.0')], '새 시드': packs['새 시드']!}).phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed, progress: said.add);
    expect(said, isEmpty);
  });

  test('꺼 둔 DLC(보관함)도 옮긴다 — 옛 보관함에서 넣은 뒤 다시 끈다 · 새 시드에 같거나 높은 판이 들었으면 그것을 끄기만', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool(packs, keptOf: {
      '옛 저장소': const [SeedPack('nest-scene', '1.0.0'), SeedPack('lantern', '1.0.0'), SeedPack('east-asia-base', '1.0.0')],
    });
    final result = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue, reason: result.kept);
    expect(_adds(tool.carried.single.adds), ['ids:korean-timeline,nest-scene'], reason: '보관함의 등불(1.0.0)은 새 시드의 1.1.0보다 낮다 — 넣지 않고 새 시드의 것을 끈다');
    expect(tool.carried.single.keep, ['nest-scene', 'lantern'], reason: '바탕(기본팩)은 끌 수 없는 자리라 옮기지 않는다');
    expect(result.moved, ['korean-timeline', 'nest-scene', 'lantern']);
    expect(File(seat.db).readAsStringSync(), '새 시드+korean-timeline,nest-scene(끔 nest-scene,lantern)');
    // 사용자 DLC 없이 꺼 둔 DLC만 있어도 옮긴다.
    File(seat.db).writeAsStringSync('옛 저장소2');
    final only = _Tool({'옛 저장소2': const [SeedPack('east-asia-base', '2.0.0')], '새 시드': packs['새 시드']!}, keptOf: {'옛 저장소2': const [SeedPack('reed', '1.0.0')]});
    final placed = await only.phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed);
    expect(placed.moved, ['reed']);
    expect(only.carried.single.keep, ['reed']);
  });

  test('원본 없이 든 DLC는 DLC 폴더의 그 파일로 넣는다(옛 차례대로 덩이를 나눔) · 그 파일도 없으면 옛 저장소를 지킨다(판정 R34 A)', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool({
      '옛 저장소': const [
        SeedPack('east-asia-base', '2.0.0'), SeedPack('haesol', '1.0.0'), SeedPack('korean-timeline', '1.0.5', original: false), SeedPack('reed', '1.0.0'),
      ],
      '새 시드': packs['새 시드']!,
    });
    // 파일이 없다 — 지킨다(컴퓨터: 둘 이름을 알린다 · 휴대폰: 파일에서 더하기를 알린다).
    final kept = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(kept.placed, isFalse);
    expect(kept.kept, contains('«korean-timeline»는 원본(.htpack)이 저장소에도 DLC 폴더에도 없어(예전 메이커 배치로만 든 것) 옮길 수 없습니다'));
    expect(kept.kept, contains('korean-timeline-v1.0.5.htpack 이름으로 저장소 옆 DLC 폴더에 두면 다음에 켤 때 옮깁니다'));
    expect(tool.carried, isEmpty, reason: '하나라도 옮길 수 없으면 넣어 보지도 않는다');
    expect(File(seat.db).readAsStringSync(), '옛 저장소');
    final phoneKept = await tool.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(phoneKept.kept, contains("그 DLC의 .htpack을 '파일에서 더하기'로 골라 주세요(앱이 DLC 폴더에 두었다가 다시 켤 때 새 판 자료로 함께 옮깁니다)"),
          reason: '막다른 고리를 풀 길 — 앱이 그 파일을 DLC 폴더에 두고 지킴 표식을 지워 다음에 켤 때 옮긴다(과제 11c — .htlayout은 더 받지 않음)');
    expect(phoneKept.kept, isNot(contains('.htpack을 넣어 두면')), reason: '.htpack만으로는 원본을 채우지 못한다');
    expect(seat.keptMark.readAsStringSync(), '0.0.4');
    // 그 이름의 파일을 DLC 폴더에 두면 그것으로 — 옛 차례(해솔 → KoreanTimeLine → 갈대)대로 덩이를 나눈다.
    final file = _writeDlc(seat.inDlc('korean-timeline-v1.0.5.htpack'), 'korean-timeline', '1.0.5');
    final placed = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(placed.placed, isTrue, reason: placed.kept);
    expect(_adds(tool.carried.single.adds), ['ids:haesol', 'file:korean-timeline-v1.0.5.htpack', 'ids:reed']);
    expect(tool.carried.single.adds[1].file, File(file).absolute.path);
    // 이름이 달라도 머리의 id · 판이 같으면 쓴다 · 판이 다르면 쓰지 않는다.
    expect(File(file).renameSync(seat.inDlc('내 KTL.htpack')).existsSync(), isTrue);
    File(seat.db).writeAsStringSync('옛 저장소');
    final renamed = _Tool({'옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('korean-timeline', '1.0.5', original: false)], '새 시드': packs['새 시드']!});
    expect((await renamed.computer.place(path: seat.db, stamp: '0.0.5', seed: newSeed)).placed, isTrue);
    File(seat.db).writeAsStringSync('옛 저장소');
    final other = _Tool({'옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('korean-timeline', '1.0.6', original: false)], '새 시드': packs['새 시드']!});
    expect((await other.computer.place(path: seat.db, stamp: '0.0.6', seed: newSeed)).placed, isFalse);
  });

  test('DLC 목록을 읽지 못해도 옛 저장소 그대로 · 같은 표식이면 아무것도 하지 않는다', () async {
    File(seat.db).writeAsStringSync('깨진 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool(packs);
    var wrote = false;
    final result = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: () async {
      wrote = true;
      return utf8.encode('새 시드');
    });
    expect(result.placed, isFalse);
    expect(result.kept, contains('지금 저장소의 DLC 목록을 읽지 못해'));
    expect(File(seat.db).readAsStringSync(), '깨진 저장소');
    expect(wrote, isFalse, reason: '옛 저장소를 못 읽으면 시드를 읽거나 쓰지도 않는다(실행마다 시드를 다시 쓰지 않게 — 고침 2회차)');

    var read = false;
    final same = await tool.computer.place(path: seat.db, stamp: '0.0.3', seed: () async {
      read = true;
      return utf8.encode('새 시드');
    });
    expect(same.placed, isFalse);
    expect(read, isFalse, reason: '같은 판이면 시드 바이트를 읽지도 않는다');
  });

  test('처음 실행 · DLC 목록을 읽을 길도 없는 곳은 예전처럼 놓는다', () async {
    final first = await SeedCarry().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(first.placed, isTrue);
    expect(File(seat.db).readAsStringSync(), '새 시드');
    File(seat.db).writeAsStringSync('옛 저장소');
    final bare = await SeedCarry().place(path: seat.db, stamp: '0.0.5', seed: newSeed);
    expect(bare.placed, isTrue);
    expect(bare.moved, isEmpty);
    expect(File(seat.db).readAsStringSync(), '새 시드');
    expect(seat.mark.readAsStringSync(), '0.0.5');
  });

  group('휴대폰 — 사용자 DLC 가리기 · 지킴(판정 R34)', () {
    /// 놓은 시드의 팩(`<저장소>.seed-packs` — 글자 id → 판). 없으면 null.
    Map<String, String>? seeded() {
      final f = File('${seat.db}.seed-packs');
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync()) as Map;
      return {for (final p in raw['packs'] as List) '${(p as Map)['id']}': '${p['version']}'};
    }

    test('시드의 바탕이 바뀌어도(등불 → 동아시아) 옛 시드의 팩은 사용자 DLC가 아니다 — 새 시드를 놓는다(8 검토 2회차 Important 1)', () async {
      // 표식만 있는 옛 휴대폰(시드의 팩을 적기 전): 옛 저장소의 바탕(첫 팩)만 뺀다.
      File(seat.db).writeAsStringSync('등불 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool({'등불 저장소': const [SeedPack('lantern', '2.0.1')], '새 시드': packs['새 시드']!});
      final result = await tool.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.kept, isNull);
      expect(result.placed, isTrue);
      expect(tool.carried, isEmpty, reason: '옮길 것이 없다');
      expect(File(seat.db).readAsStringSync(), '새 시드');
      expect(seeded(), {'east-asia-base': '2.1.0', 'lantern': '1.1.0'});
      // 처음 실행에서 놓은 시드도 적는다.
      File(seat.db).deleteSync();
      File('${seat.db}.seed-packs').deleteSync();
      expect((await tool.phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed)).placed, isTrue);
      expect(seeded(), {'east-asia-base': '2.1.0', 'lantern': '1.1.0'});
    });

    test('옛 시드에 든 팩을 새 시드가 빼도 사용자 DLC가 아니다 · 진짜 사용자 DLC는 바탕이 바뀌는 새 시드여도 옮긴다', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      File('${seat.db}.seed-packs').writeAsStringSync(jsonEncode({'version': 1, 'packs': [{'id': 'east-asia-base', 'version': '2.0.0'}, {'id': 'reed', 'version': '1.0.0'}]}));
      final dropped = _Tool({'옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('reed', '1.0.0')], '새 시드': const [SeedPack('east-asia-base', '2.1.0')]});
      final placed = await dropped.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(placed.placed, isTrue, reason: '옛 시드의 둘째 팩(reed)을 새 시드가 뺐다 — 사용자가 넣은 것이 아니다');
      expect(dropped.carried, isEmpty);
      expect(seeded(), {'east-asia-base': '2.1.0'});
      // 옛 시드(등불) + 사용자가 넣은 KoreanTimeLine → 바탕이 바뀌는 새 시드에도 옮긴다(휴대폰은 꺼내 둘 길이 없다 — 엔진이 거절하면 지킴).
      File(seat.db).writeAsStringSync('섞인 저장소');
      File('${seat.db}.seed-packs').writeAsStringSync(jsonEncode({'version': 1, 'packs': [{'id': 'lantern', 'version': '2.0.1'}]}));
      final mixed = _Tool({'섞인 저장소': const [SeedPack('lantern', '2.0.1'), SeedPack('korean-timeline', '1.0.5')], '새 시드': packs['새 시드']!});
      final moved = await mixed.phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed);
      expect(moved.placed, isTrue);
      expect(moved.moved, ['korean-timeline'], reason: '옛 시드의 바탕(등불)은 옮기지 않는다');
      expect(File(seat.db).readAsStringSync(), '새 시드+korean-timeline');
      // 사용자가 판을 올린 시드 팩(옛 시드 1.0.0 → 저장소 1.1.0)은 사용자 DLC로 옮긴다.
      File(seat.db).writeAsStringSync('올린 저장소');
      File('${seat.db}.seed-packs').writeAsStringSync(jsonEncode({'version': 1, 'packs': [{'id': 'east-asia-base', 'version': '2.0.0'}, {'id': 'reed', 'version': '1.0.0'}]}));
      final raised = _Tool({'올린 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('reed', '1.1.0')], '새 시드': const [SeedPack('east-asia-base', '2.1.0')]});
      expect((await raised.phone().place(path: seat.db, stamp: '0.0.6', seed: newSeed)).moved, ['reed']);
    });

    test('옮길 길(자료 처리부)이 없으면 사용자 DLC가 있을 때 새 시드를 놓지 않고 지킨다 — 같은 판에서는 다시 견주지 않는다', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final tool = _Tool(packs);
      final result = await tool.phone(names: (db) async => {'korean-timeline': 'Tigers of the East'}, engine: false).place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isFalse);
      expect(result.kept, '앱의 새 판 자료로 바꾸지 않았습니다 — 넣어 둔 DLC «Tigers of the East»는 옮길 길이 없습니다'
          '(새 기본 자료가 지금 필요하면 앱 정보에서 앱 자료를 지우면 됩니다 — 넣은 DLC는 사라집니다).');
      expect(File(seat.db).readAsStringSync(), '옛 저장소');
      expect(seat.mark.readAsStringSync(), '0.0.3', reason: '표식은 옛 판 그대로');
      expect(seat.keptMark.readAsStringSync(), '0.0.4', reason: '이 판은 지킴으로 정했다(실행마다 시드를 다시 쓰거나 알리지 않게)');
      expect(File('${seat.db}.새-시드').existsSync(), isFalse);

      var read = false;
      final again = await tool.phone(engine: false).place(path: seat.db, stamp: '0.0.4', seed: () async {
        read = true;
        return utf8.encode('새 시드');
      });
      expect(again.placed, isFalse);
      expect(again.kept, isNull, reason: '두 번째 실행은 조용히');
      expect(read, isFalse, reason: '같은 판이면 시드 바이트를 읽지도 않는다');
      expect(File(seat.db).readAsStringSync(), '옛 저장소');
    });

    test('사용자 DLC가 없으면 지금처럼 새 시드를 놓는다(지킴 표식도 지운다)', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      seat.keptMark.writeAsStringSync('0.0.2');
      final tool = _Tool({'옛 저장소': const [SeedPack('east-asia-base', '2.0.0'), SeedPack('lantern', '1.0.0')], '새 시드': packs['새 시드']!});
      final result = await tool.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isTrue);
      expect(result.kept, isNull);
      expect(File(seat.db).readAsStringSync(), '새 시드');
      expect(seat.mark.readAsStringSync(), '0.0.4');
      expect(seat.keptMark.existsSync(), isFalse);
      // DLC 목록이 없는 아주 옛 저장소(0.0.1 — 휴대폰은 그때 DLC를 넣을 수 없었다)도 놓는다.
      File(seat.db).writeAsStringSync('아주 옛 저장소');
      final old = await _Tool({'아주 옛 저장소': const [], '새 시드': packs['새 시드']!}).phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed);
      expect(old.placed, isTrue);
      expect(File(seat.db).readAsStringSync(), '새 시드');
    });

    test('옛 저장소를 읽지 못하면(깨짐 · 열기 실패) 새 시드를 놓되 옛 파일은 지우지 않고 옆에 이름을 바꿔 두고 알린다', () async {
      File(seat.db).writeAsStringSync('깨진 저장소');
      File('${seat.db}-wal').writeAsStringSync('깨진 일지');
      seat.mark.writeAsStringSync('0.0.3');
      final result = await _Tool(packs).phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isTrue);
      expect(File(seat.db).readAsStringSync(), '새 시드');
      expect(seat.mark.readAsStringSync(), '0.0.4');
      expect(File('${seat.db}-wal').existsSync(), isFalse, reason: '새 시드에 옛 일지가 덧대이지 않게');
      final aside = seat.dir.listSync().whereType<File>().where((f) => f.path.split(Platform.pathSeparator).last.startsWith('archive.db.옛-저장소-')).toList();
      final names = aside.map((f) => f.path.split(Platform.pathSeparator).last).toSet();
      expect(aside.where((f) => !f.path.endsWith('-wal')).single.readAsStringSync(), '깨진 저장소', reason: '옛 파일은 옆에 그대로');
      expect(names.where((n) => n.endsWith('-wal')), hasLength(1), reason: '일지도 함께 옆으로');
      expect(result.note, contains('지금 저장소를 읽지 못해'));
      expect(result.note, contains(names.firstWhere((n) => !n.endsWith('-wal'))), reason: '되찾을 파일 이름');
      expect(result.note, contains('파일 앱에서는 보이지 않습니다'), reason: '앱 전용 폴더라는 사정(8 검토 2회차 Minor 3)');
      expect(result.note, isNot(contains('DLC 폴더')), reason: 'DLC 원본이 없던 휴대폰에는 그 말을 하지 않는다');
      expect(seeded(), {'east-asia-base': '2.1.0', 'lantern': '1.1.0'}, reason: '놓은 시드의 팩을 적어 둔다');
      // DLC 원본이 DLC 폴더에 있으면 그곳을 알린다.
      File(seat.db).writeAsStringSync('또 깨진 저장소');
      Directory(seat.inDlc('')).createSync(recursive: true);
      File(seat.inDlc('KoreanTimeLine-v1.0.5.htpack')).writeAsStringSync('원본');
      final again = await _Tool(packs).phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed);
      expect(again.note, contains('DLC 폴더에 남아 있습니다'));
    });

    test('새 시드의 목록을 읽지 못하면 옛 저장소를 그대로 둔다(지킬지 알 수 없다)', () async {
      File(seat.db).writeAsStringSync('옛 저장소');
      seat.mark.writeAsStringSync('0.0.3');
      final result = await _Tool({'옛 저장소': packs['옛 저장소']!}).phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
      expect(result.placed, isFalse);
      expect(result.kept, contains('새 판 자료의 DLC 목록을 읽지 못해'));
      expect(File(seat.db).readAsStringSync(), '옛 저장소');
      expect(seat.keptMark.existsSync(), isFalse, reason: '다음 실행에서 다시 해 본다');
      expect(File('${seat.db}.새-시드').existsSync(), isFalse);
    });
  });

  test('컴퓨터: 바탕(기본팩)이 다른 새 시드면 원본은 꺼내 두되 넣지 않고 알린다', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool({'옛 저장소': packs['옛 저장소']!, '새 시드': const [SeedPack('lantern', '2.0.1')]});
    final result = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue);
    expect(result.moved, isEmpty);
    expect(tool.carried, isEmpty);
    expect(result.note, contains('바탕(기본팩)이 달라'));
    expect(result.note, contains('«korean-timeline»'), reason: '알림에 DLC(이름을 모르면 글자 id)');
    final aside = seat.inDlc('다른-바탕${Platform.pathSeparator}korean-timeline-v1.0.5.htpack');
    expect(File(aside).existsSync(), isTrue, reason: '원본은 DLC 폴더 안의 다른-바탕/에 남는다');
    expect(File(seat.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isFalse, reason: 'DLC 폴더 바로 아래에 두지 않아 판 올림 뒤 다시 들이기(R32)가 넣지 않는다');
    final plan = await DlcFolderSync(readPack: (f) async => DlcFolderPack(f, 'korean-timeline', '1.0.5', '한국')).pending(
        db: seat.db, storeKeys: const ['lantern'], hidden: DlcHidden.none, baseKey: 'east-asia-base');
    expect(plan.add, isEmpty);
  });

  test('기본팩을 뺀 저장소(첫째가 사용자 DLC)도 그 DLC를 빠뜨리지 않는다 · 이름을 알면 알림에 이름', () async {
    const old = [SeedPack('korean-timeline', '1.0.5'), SeedPack('haesol', '1.0.0')];
    const seed = [SeedPack('east-asia-base', '2.1.0'), SeedPack('lantern', '1.1.0')];
    expect(SeedCarry.userPacks(old, seed).map((p) => p.id), ['korean-timeline', 'haesol'], reason: '첫째를 기본팩으로 가정하지 않고 id로 거른다');
    expect(SeedCarry.userPacks(const [SeedPack('east-asia-base', '2.0.0'), SeedPack('haesol', '1.0.0')], const [SeedPack('lantern', '2.0.1')]).map((p) => p.id), ['haesol'],
        reason: '새 시드의 바탕이 달라도 동아시아 기본팩은 사용자 DLC가 아니다');
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool({'옛 저장소': packs['옛 저장소']!, '새 시드': packs['새 시드']!})..answer = const SeedCarryAnswer.failed('디스크가 가득 찼습니다');
    final named = SeedCarry(listPacks: tool.list, packOut: tool.out, carryInto: tool.carry, names: (db) async => {'korean-timeline': 'Tigers of the East'});
    final result = await named.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.kept, contains('«Tigers of the East»'));
    expect(result.kept, contains('DLC를 넣지 못했습니다 — 디스크가 가득 찼습니다'), reason: 'code가 없는 거절은 엔진의 글 그대로');
  });

  test('등불 바탕 저장소(판타지 APK)에 사용자가 넣은 동아시아 DLC는 사용자 DLC다 — 판 올림에 옮기고 꺼 둔 것도 옮긴다(판정 R60 I-1 — 말없이 사라지지 않게)', () async {
    const old = [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('east-asia-base', '1.0.0'), SeedPack('korean-timeline', '1.0.5')];
    const seed = [SeedPack('lantern-chronicle', '2.0.1')];
    expect(SeedCarry.phoneUserPacks(old, seed).map((p) => p.id), ['east-asia-base', 'korean-timeline'], reason: '바탕은 새 시드의 첫째와 휴대폰 옛 저장소의 첫째뿐');
    expect(SeedCarry.userPacks(old, seed).map((p) => p.id), ['east-asia-base', 'korean-timeline']);
    File(seat.db).writeAsStringSync('옛 등불');
    seat.mark.writeAsStringSync('0.0.3');
    final tool = _Tool({'옛 등불': old, '새 시드': seed});
    final result = await tool.phone().place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue, reason: result.kept);
    expect(result.moved, ['east-asia-base', 'korean-timeline']);
    // 꺼 둔 동아시아(보관함)도 옮기고 다시 끈다.
    File(seat.db).writeAsStringSync('옛 등불2');
    final off = _Tool({'옛 등불2': const [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('korean-timeline', '1.0.5')], '새 시드': seed},
        keptOf: {'옛 등불2': const [SeedPack('east-asia-base', '1.0.0')]});
    final carried = await off.phone().place(path: seat.db, stamp: '0.0.5', seed: newSeed);
    expect(carried.moved, ['korean-timeline', 'east-asia-base']);
    expect(off.carried.single.keep, ['east-asia-base']);
  });

  test('pack_info가 없는 옛 저장소: 사용자 DLC를 몰라 시드를 놓고 DLC 폴더로 다시 들이게 한다(실행마다 kept로 남지 않게)', () async {
    File(seat.db).writeAsStringSync('아주 옛 저장소');
    seat.mark.writeAsStringSync('0.0.1');
    final tool = _Tool({'아주 옛 저장소': const [], '새 시드': packs['새 시드']!});
    final result = await tool.computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue);
    expect(result.moved, isEmpty);
    expect(result.note, contains('DLC 폴더'));
    expect(File(seat.db).readAsStringSync(), '새 시드');
    expect(seat.mark.readAsStringSync(), '0.0.4');
  });

  test('옛 저장소의 -wal · -shm · -journal을 새 시드 옆에 남기지 않는다(이름 바꾸기 전에 함께 비킨다)', () async {
    File(seat.db).writeAsStringSync('옛 저장소');
    seat.mark.writeAsStringSync('0.0.3');
    for (final tail in const ['-wal', '-shm', '-journal']) {
      File('${seat.db}$tail').writeAsStringSync('옛 일지$tail');
    }
    final result = await _Tool(packs).computer.place(path: seat.db, stamp: '0.0.4', seed: newSeed);
    expect(result.placed, isTrue);
    expect(File(seat.db).readAsStringSync(), '새 시드+korean-timeline');
    for (final tail in const ['-wal', '-shm', '-journal']) {
      expect(File('${seat.db}$tail').existsSync(), isFalse, reason: '$tail — 새 시드에 옛 일지가 덧대이지 않게');
    }
  });

  test('사용자 DLC 가리기 · 판 견주기 · info · kept_packs 답 읽기', () {
    const old = [SeedPack('east-asia-base', '2.0.0'), SeedPack('lantern', '1.2.0'), SeedPack('reed', '1.0.0'), SeedPack('sol', '0.9.0')];
    const seed = [SeedPack('east-asia-base', '2.1.0'), SeedPack('lantern', '1.1.0'), SeedPack('reed', '1.0.0')];
    expect(SeedCarry.userPacks(old, seed).map((p) => p.id), ['lantern', 'sol'], reason: '사용자가 올린 판(1.2.0 > 1.1.0)과 시드에 없는 DLC');
    expect(compareDlcVersion('1.10.0', '1.9.3'), greaterThan(0));
    expect(compareDlcVersion('2.0', '2.0.0'), 0);
    expect(compareDlcVersion('1.0.0-b', '1.0.0'), 0, reason: '엔진(packs.rs)과 같은 규칙 — 마디의 앞 숫자만');
    expect(compareDlcVersion('v2', '1'), lessThan(0));
    final info = SeedCarry.packsOfInfo({
      'ok': true,
      'data': {'meta': {'pack_info': '{"2":{"id":"korean-timeline","version":"1.0.5","original":false},"1":{"id":"east-asia-base","version":"2.0.0"}}'}},
    })!;
    expect(info.map((p) => '$p'), ['east-asia-base@2.0.0', 'korean-timeline@1.0.5'], reason: '번호 차례(첫째 = 기본팩)');
    expect(info.last.original, isFalse);
    expect(SeedCarry.packsOfInfo({'meta': {'schema': '3'}}), isEmpty, reason: 'pack_info가 없는 옛 저장소(목록은 읽었고 DLC를 모름)');
    expect(SeedCarry.packsOfInfo('깨진 답'), isNull);
    expect(SeedCarry.packsOfKept({'ok': true, 'data': [{'id': 'nest-scene', 'name': '둥지', 'version': '1.0.0', 'bytes': 9}]})!.map((p) => '$p'), ['nest-scene@1.0.0']);
    expect(SeedCarry.packsOfKept([]), isEmpty);
    expect(SeedCarry.packsOfKept({'ok': false}), isNull);
  });

  group('DLC 폴더에만 남은 사용자 DLC — 판을 올린 뒤 연 저장소에 다시 들이기(판정 R32)', () {
    // Windows 설치본 · 포터블은 판을 올릴 때 `자료/…/archive.db`를 새 판의 것(시드)으로 통째로 덮는다 — 저장소에는 기본팩 · 든 견본만,
    // DLC 폴더에는 사용자가 넣어 둔 DLC 파일이 남았다(얹힌 몫 2가 폴더를 저장소와 맞춰 둔다). 앱이 저장소를 열 때 그것을 한 번 들인다.
    late Directory folder;
    late String db;
    late Map<String, DlcFolderPack?> packs;
    String inDlc(String name) => '${folder.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}$name';
    setUp(() {
      folder = Directory.systemTemp.createTempSync('ht-folder-sync-');
      db = '${folder.path}${Platform.pathSeparator}archive.db';
      File(db).writeAsStringSync('새 판이 덮은 저장소');
      Directory(inDlc('')).createSync(recursive: true);
      // 파일 이름 → 엔진 도구(check-pack)가 읽은 값(null = 읽지 못함 — 깨진 파일).
      packs = {
        'KoreanTimeLine-v1.0.4.htpack': DlcFolderPack(inDlc('KoreanTimeLine-v1.0.4.htpack'), 'KoreanTimeLine', '1.0.4', 'Tigers of the East'),
        'KoreanTimeLine-v1.0.5.htpack': DlcFolderPack(inDlc('KoreanTimeLine-v1.0.5.htpack'), 'KoreanTimeLine', '1.0.5', 'Tigers of the East'),
        'moonbay-v2.0.0.htpack': DlcFolderPack(inDlc('moonbay-v2.0.0.htpack'), 'moonbay', '2.0.0', '달물결 기록집'),
        'east-asia.htpack': DlcFolderPack(inDlc('east-asia.htpack'), 'east-asia-base', '1.0.0', '동아시아사 기본팩'),
        'haesol-v1.0.0.htpack': DlcFolderPack(inDlc('haesol-v1.0.0.htpack'), 'haesol', '1.0.0', '해솔 기록집'),
        '깨진-파일.htpack': null,
      };
      for (final name in [...packs.keys, 'notes.txt']) {
        File(inDlc(name)).writeAsStringSync(name);
      }
    });
    tearDown(() => folder.deleteSync(recursive: true));

    DlcFolderSync sync(List<String> read) => DlcFolderSync(readPack: (file) async {
      read.add(file.split(Platform.pathSeparator).last);
      return packs[file.split(Platform.pathSeparator).last];
    });
    const hidden = DlcHidden(off: {'moonbay'});

    test('저장소에도 끈 목록에도 없는 사용자 DLC만(같은 id는 가장 높은 판) · 기본팩 · 끈 DLC는 빼고 · 깨진 파일은 그것만 건너뛰고 알린다', () async {
      final read = <String>[];
      final plan = await sync(read).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base');
      expect([for (final p in plan.add) (p.id, p.version)], [('KoreanTimeLine', '1.0.5')]);
      expect(plan.add.single.path, inDlc('KoreanTimeLine-v1.0.5.htpack'), reason: '원본은 그 폴더 파일');
      expect(plan.broken, ['깨진-파일.htpack']);
      expect(read, isNot(contains('notes.txt')), reason: '.htpack만 읽는다');
    });

    test('저장소에 든 DLC라도 DLC 폴더의 판이 더 높으면 다시 들인다(판 올림 — 판정 R60 M-5) · 판을 모르면 건너뛴다', () async {
      final keys = const ['east-asia-base', 'haesol', 'KoreanTimeLine'];
      final higher = await sync([]).pending(db: db, storeKeys: keys, storeVersions: const {'KoreanTimeLine': '1.0.4'}, hidden: hidden, baseKey: 'east-asia-base');
      expect([for (final p in higher.add) (p.id, p.version)], [('KoreanTimeLine', '1.0.5')]);
      final same = await sync([]).pending(db: db, storeKeys: keys, storeVersions: const {'KoreanTimeLine': '1.0.5'}, hidden: hidden, baseKey: 'east-asia-base');
      expect(same.add, isEmpty);
      final unknown = await sync([]).pending(db: db, storeKeys: keys, hidden: hidden, baseKey: 'east-asia-base');
      expect(unknown.add, isEmpty);
    });

    test('다시 들이기의 기억은 지금 파일에 합친다 — 들이는 동안 다른 DLC 일이 적은 묘비를 옛 값으로 덮지 않는다(판정 R60 M-7)', () {
      const initial = DlcFolderState(removed: {'gone', 'left'}, off: {'moonbay'});
      // 들이기가 셈한 것: 'gone'의 남은 파일을 다 지워 묘비에서 뺌 · 깨진 파일 지문 하나.
      const imported = DlcFolderState(removed: {'left'}, off: {'moonbay'}, skip: {'깨진-파일.htpack': 'abc:1'});
      // 그동안 사용자가 해솔을 끄고(off) 달물결을 켰고(off에서 뺌) 갈대를 지웠다(removed).
      const current = DlcFolderState(removed: {'gone', 'left', 'reed'}, off: {'haesol'});
      final merged = DlcFolderState.mergeImport(current, initial: initial, imported: imported);
      expect(merged.removed, {'left', 'reed'});
      expect(merged.off, {'haesol'});
      expect(merged.skip, {'깨진-파일.htpack': 'abc:1'});
    });

    test('열 때 저장소에 든 DLC 가운데 DLC 폴더 사본이 없는 것을 엔진 도구로 꺼내 채운다 — 판 올림 뒤 다시 들이기가 믿는 사본(판정 R60 I-2)', () async {
      final outs = <String>[];
      Future<bool> packOut(String store, String id, String file) async {
        outs.add('$id → ${file.split(Platform.pathSeparator).last}');
        File(file).writeAsStringSync('원본 $id');
        return true;
      }
      // 저장소: 바탕(등불) · 해솔 1.0.0(폴더에 사본 있음 — 이름은 달라도 id · 판이 같으면 됨) · 바다 2.0.0(사본 없음) · 갈대(원본 없이 든 DLC — 꺼낼 원본 없음).
      _writeDlc(inDlc('내 해솔.htpack'), 'haesol', '1.0.0');
      final filled = await fillDlcFolderCopies(
        db: db,
        packs: const [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('haesol', '1.0.0'), SeedPack('sea', '2.0.0'), SeedPack('reed', '1.0.0', original: false)],
        packOut: packOut,
      );
      expect(outs, ['sea → sea-v2.0.0.htpack'], reason: '바탕은 새 판에 들어 있다 · 사본이 있거나 원본이 없는 것은 건너뛴다');
      expect(filled, ['sea-v2.0.0.htpack']);
      expect(File(inDlc('sea-v2.0.0.htpack')).existsSync(), isTrue);
      // 두 번째는 할 일이 없다.
      _writeDlc(inDlc('sea-v2.0.0.htpack'), 'sea', '2.0.0');
      expect(await fillDlcFolderCopies(db: db, packs: const [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('sea', '2.0.0')], packOut: packOut), isEmpty);
      expect(outs, hasLength(1));
    });

    test('등불 바탕 저장소면 DLC 폴더의 동아시아 DLC도 다시 들인다 — 동아시아는 늘 바탕이 아니다 · 옛 판에서 기본팩을 뺐으면(baseRemoved) 들이지 않는다(판정 R60 I-1)', () async {
      final plan = await sync([]).pending(db: db, storeKeys: const ['lantern-chronicle'], hidden: DlcHidden.none, baseKey: 'east-asia-base');
      expect([for (final p in plan.add) p.id], containsAll(['east-asia-base', 'KoreanTimeLine', 'haesol', 'moonbay']));
      final removed = await sync([]).pending(db: db, storeKeys: const ['lantern-chronicle'], hidden: const DlcHidden(baseRemoved: true), baseKey: 'east-asia-base');
      expect([for (final p in removed.add) p.id], isNot(contains('east-asia-base')));
    });

    test('엔진 도구가 실패하면(없음 · 시작 못 함 · 죽음) 그 파일을 깨짐으로 기억하지 않고 다음 열기에서 다시 읽는다 — 묘비도 지킨다(판정 R58)', () async {
      final plan = await DlcFolderSync(readPack: (file) async => throw const DlcToolFailure('도구를 시작하지 못했습니다'))
          .pending(db: db, storeKeys: const ['east-asia-base'], hidden: hidden, baseKey: 'east-asia-base', state: const DlcFolderState(removed: {'haesol'}));
      expect(plan.add, isEmpty);
      expect(plan.broken, isEmpty, reason: '파일 탓이 아니다');
      expect(plan.state.skip, isEmpty, reason: '지문을 적지 않는다 — 도구가 고쳐지면 다음 열기에서 다시 읽는다');
      expect(plan.toolFailed, hasLength(packs.length));
      expect(plan.state.removed, {'haesol'}, reason: '읽지 못해 지우지 못한 묘비 파일이 남았을 수 있다 — 묘비를 지켜야 뺀 DLC가 되살아나지 않는다');
      expect(dlcFolderNotice(toolFailed: plan.toolFailed), allOf(contains('엔진 도구'), contains('다음에 앱을 열 때 다시')));
      // 한 파일만 도구가 실패해도 그 파일만 기억하지 않는다(나머지는 그대로 — 깨진 파일은 깨짐으로).
      final mixed = await DlcFolderSync(readPack: (file) async {
        final name = file.split(Platform.pathSeparator).last;
        if (name == 'moonbay-v2.0.0.htpack') throw const DlcToolFailure('도구가 죽었습니다');
        return packs[name];
      }).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: DlcHidden.none, baseKey: 'east-asia-base');
      expect([for (final p in mixed.add) p.id], ['KoreanTimeLine']);
      expect(mixed.broken, ['깨진-파일.htpack']);
      expect(mixed.toolFailed, ['moonbay-v2.0.0.htpack']);
      expect(mixed.state.skip.keys, ['깨진-파일.htpack']);
      // 진짜 길: 도구 파일이 없으면(시작하지 못함) 도구 실패로 던진다.
      expect(DlcFolderSync.withTool('${folder.path}${Platform.pathSeparator}없는-도구.exe').readPack(inDlc('haesol-v1.0.0.htpack')), throwsA(isA<DlcToolFailure>()));
    });

    test("'깨진 파일'은 도구가 형식 문제라고 분명히 말할 때만 — 그 밖의 실패(입출력 · 결과 파일 못 씀 · 임시 자리 실패)는 도구 실패(판정 R63-2)", () async {
      // archive-tool check-pack의 실제 오류 줄(Rust main의 Err — 종료 코드 1): 형식 문제는 정해진 글 · JSON 본문 오류.
      for (final said in ['Error: "지원하지 않는 전용 팩 머리"', 'Error: "전용 팩 지문 오류"', 'Error: "전용 팩 선언 크기 오류"', 'Error: "전용 팩 풀린 크기 오류"',
          'Error: "전용 팩 크기 오류"', 'Error: "DLC 본문이 아닙니다"', 'Error: Error("expected value", line: 1, column: 1)', 'Error: "corrupt deflate stream"']) {
        expect(dlcCheckPackBroken(said), isTrue, reason: said);
      }
      for (final said in ['Error: Os { code: 2, kind: NotFound, message: "지정된 파일을 찾을 수 없습니다." }',
          'Error: Os { code: 32, kind: Uncategorized, message: "다른 프로세스가 파일을 사용 중이기 때문에 프로세스가 액세스 할 수 없습니다." }', '사용법: generate2 …', '']) {
        expect(dlcCheckPackBroken(said), isFalse, reason: said);
      }
      // 임시 자리를 만들지 못하면(그 자리에 파일이 있음) 도구를 부르기 전에 도구 실패 — 깨짐으로 기억하지 않는다.
      final blocked = File('${folder.path}${Platform.pathSeparator}임시-자리')..writeAsStringSync('폴더가 아니라 파일');
      expect(DlcFolderSync.withTool('${folder.path}${Platform.pathSeparator}없는-도구.exe', scratch: Directory(blocked.path)).readPack(inDlc('haesol-v1.0.0.htpack')),
          throwsA(isA<DlcToolFailure>()));
    });

    test('깨진 파일이 하나라도 있으면 묘비를 줄이지 않는다 — 그것이 뺀 DLC의 남은 파일일 수 있다(판정 R63-2)', () async {
      final plan = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base',
          state: const DlcFolderState(removed: {'gone'}));
      expect(plan.broken, ['깨진-파일.htpack']);
      expect(plan.state.removed, {'gone'});
    });

    test('기억한 거절(skip)에 앱 판을 함께 적고 · 앱 판이 바뀌면 그 파일을 한 번 다시 본다(판 올림이 고쳤을 수 있다 — 판정 R63-3)', () async {
      final first = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', app: '0.0.4+5');
      expect(first.state.skip.keys, ['깨진-파일.htpack']);
      expect(first.state.skipApp, {'깨진-파일.htpack': '0.0.4+5'});
      final same = <String>[];
      await sync(same).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', app: '0.0.4+5', state: first.state);
      expect(same, isNot(contains('깨진-파일.htpack')), reason: '같은 파일 · 같은 앱 판이면 읽지 않는다');
      final raised = <String>[];
      final again = await sync(raised).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', app: '0.0.5+6', state: first.state);
      expect(raised, contains('깨진-파일.htpack'), reason: '앱 판이 바뀌면 한 번 다시');
      expect(again.state.skipApp, {'깨진-파일.htpack': '0.0.5+6'});
      // 넣기 거절(파일 탓 — 낮은 판 · 배치 거절 · range)도 앱 판과 함께 적는다.
      final failed = DlcFolderState.empty.skipping(inDlc('moonbay-v2.0.0.htpack'), app: '0.0.4+5');
      expect(failed.skipApp, {'moonbay-v2.0.0.htpack': '0.0.4+5'});
      // sync.json에 적고 다시 읽는다 · 앱 판이 없던 옛 기억은 다른 판으로 본다(한 번 다시).
      first.state.write(db);
      expect(DlcFolderState.read(db)!.skipApp, {'깨진-파일.htpack': '0.0.4+5'});
      File('${folder.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}sync.json').writeAsStringSync(jsonEncode({'version': 1, 'removed': [], 'off': [], 'skip': first.state.skip}));
      final old = <String>[];
      await sync(old).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', app: '0.0.4+5', state: DlcFolderState.read(db)!);
      expect(old, contains('깨진-파일.htpack'));
      expect(DlcFolderState.mergeImport(DlcFolderState.empty, initial: DlcFolderState.empty, imported: first.state).skipApp, first.state.skipApp);
    });

    test('열 때 낡은 끄기 묘비(off)를 치운다 — 저장소에 든 채 끈 목록(hidden.json)에 없는 id(중단된 엔진 끄기가 남긴 것 · 판정 R63-5)', () {
      const DlcFolderState(removed: {'gone'}, off: {'haesol', 'moonbay', 'east-asia-base'}).write(db);
      DlcFolderState.dropStaleOff(db, stored: const ['east-asia-base', 'haesol'], hidden: const DlcHidden(off: {'east-asia-base', 'moonbay'}));
      final after = DlcFolderState.read(db)!;
      expect(after.off, {'moonbay', 'east-asia-base'}, reason: "해솔은 저장소에 든 채 끈 목록에 없다 — 끄기가 COMMIT 전에 멈췄다 · 화면에서만 끈 바탕은 남긴다");
      expect(after.removed, {'gone'});
      // 끈 목록이 깨졌으면 무엇이 낡았는지 몰라 그대로 둔다.
      File('${folder.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}hidden.json').writeAsStringSync('{깨짐');
      const DlcFolderState(off: {'haesol'}).write(db);
      DlcFolderState.dropStaleOff(db, stored: const ['haesol'], hidden: DlcHidden.read(db));
      expect(DlcFolderState.read(db)!.off, {'haesol'});
    });

    test('열 때 DLC 폴더의 오래된 임시 파일(*.tmp — 원자적 복사 · 쓰기가 멈추며 남김)을 지운다 · 막 생긴 것은 둔다(① m-5)', () {
      final stale = File(inDlc('KoreanTimeLine-v1.0.5.htpack.1700000000000000.tmp'))..writeAsStringSync('반쯤');
      final staleJson = File(inDlc('hidden.json.1700000000000001.tmp'))..writeAsStringSync('반쯤');
      final fresh = File(inDlc('moonbay-v2.0.0.htpack.1800000000000000.tmp'))..writeAsStringSync('쓰는 중');
      final now = DateTime(2026, 10, 22, 18);
      stale.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
      staleJson.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
      fresh.setLastModifiedSync(now.subtract(const Duration(minutes: 1)));
      expect(cleanDlcTemps(db, now: now), ['KoreanTimeLine-v1.0.5.htpack.1700000000000000.tmp', 'hidden.json.1700000000000001.tmp']);
      expect((stale.existsSync(), staleJson.existsSync(), fresh.existsSync()), (false, false, true));
      expect(File(inDlc('notes.txt')).existsSync(), isTrue);
    });

    test('같은 이름인데 머리가 맞지 않는 사본(깨짐 · 다른 DLC)은 꺼내 바꿔 놓는다(① m-2)', () async {
      File(inDlc('sea-v2.0.0.htpack')).writeAsStringSync('반쯤 쓴 사본');
      final outs = <String>[];
      final filled = await fillDlcFolderCopies(db: db, packs: const [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('sea', '2.0.0')], packOut: (store, id, file) async {
        outs.add(id);
        _writeDlc(file, id, '2.0.0');
        return true;
      });
      expect(outs, ['sea']);
      expect(filled, ['sea-v2.0.0.htpack']);
      expect(readDlcFileHead(inDlc('sea-v2.0.0.htpack')).head?.id, 'sea');
      // 머리를 읽을 수 있는 다른 DLC의 파일이면 바꿔 놓지 않는다 — 남의 원본을 지우지 않게(고침 2회차 Minor 4 · 읽지 못하는 파일만 바꿈).
      _writeDlc(inDlc('reef-v1.0.0.htpack'), 'other', '9.0.0');
      outs.clear();
      await fillDlcFolderCopies(db: db, packs: const [SeedPack('lantern-chronicle', '2.0.0'), SeedPack('reef', '1.0.0')], packOut: (store, id, file) async {
        outs.add(id);
        return true;
      });
      expect(outs, isEmpty);
      expect(readDlcFileHead(inDlc('reef-v1.0.0.htpack')).head?.id, 'other');
    });

    test('열 때의 DLC 폴더 일 배선 — 미리보기 · 저장소를 주지 않은 재기 · 재기 · 그림만이면 하지 않고, 하면 낡은 끄기 묘비 · 임시 파일을 치우며 보관함 카드는 지운 묘비를 거른다(고침 2회차 Minor 6)', () {
      expect(dlcFolderSyncAllowed(preview: false, leaveStore: false, leaveDlcFolder: false), isTrue);
      for (final (preview, leaveStore, leaveDlcFolder) in const [(true, false, false), (false, true, true), (false, false, true)]) {
        expect(dlcFolderSyncAllowed(preview: preview, leaveStore: leaveStore, leaveDlcFolder: leaveDlcFolder), isFalse);
      }
      const DlcFolderState(removed: {'gone'}, off: {'haesol'}).write(db);
      final temp = File(inDlc('x.htpack.1.tmp'))..writeAsStringSync('반쯤');
      temp.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      dlcOpenTidy(db, stored: const ['east-asia-base', 'haesol'], hidden: DlcHidden.none);
      expect(DlcFolderState.read(db)!.off, isEmpty);
      expect(temp.existsSync(), isFalse);
      expect(dlcKeptGone(db), {'gone'});
      expect(dlcKeptGone(null), isEmpty);
    });

    test('check-pack의 형식 글은 엔진 원본(lib.rs)의 글과 같다 — 엔진이 글을 바꾸면 여기서 알게(고침 2회차 Minor 5) · 도구가 읽지 못한 알림에 파일 이름', () {
      final source = File('../engine/src/lib.rs').readAsStringSync();
      for (final said in dlcCheckPackFormatErrors) {
        expect(source, contains('"$said"'), reason: said);
      }
      expect(dlcFolderNotice(toolFailed: const ['a.htpack', 'b.htpack']), contains('a.htpack · b.htpack'));
    });

    test('연 뒤 그 DLC가 저장소에 들고(엔진 add_pack — 폴더 파일 그대로) 화면에 켜진 채 보이며, 끈 DLC는 끈 채 남는다', () async {
      final plan = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base');
      // 앱이 머리로 id · 판을 읽으므로 폴더의 그 파일은 진짜 팩 꼴로.
      _writeDlc(inDlc('KoreanTimeLine-v1.0.4.htpack'), 'KoreanTimeLine', '1.0.4');
      _writeDlc(inDlc('KoreanTimeLine-v1.0.5.htpack'), 'KoreanTimeLine', '1.0.5');
      final requests = <Map<String, dynamic>>[];
      final job = DlcJob()
        ..applier = (request) async {
          requests.add(request);
          return {'ok': true, 'data': {'rewrote': [], 'added': ['koreaA'], 'removed': [], 'first_pos': 0, 'ms': 200}};
        };
      final done = await job.apply(db: db, files: [for (final p in plan.add) p.path], stored: const {'east-asia-base', 'haesol'});
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(requests.single, {'op': 'add_pack', 'files': [File(inDlc('KoreanTimeLine-v1.0.5.htpack')).absolute.path], 'path': db});
      expect(File(inDlc('KoreanTimeLine-v1.0.4.htpack')).existsSync(), isFalse, reason: '같은 DLC의 낮은 판 파일은 지운다(폴더는 id마다 하나)');
      expect(File(inDlc('KoreanTimeLine-v1.0.5.htpack')).existsSync(), isTrue, reason: '넣은 그 파일은 그 자리에');
      // 뼈대를 다시 읽은 뒤 켤 DLC(앱 틀의 `_reloadStore`): 새로 든 KoreanTimeLine은 켜지고, 끈 목록의 DLC는 꺼진 채.
      final on = dlcEnabledAfterReload(
        packOf: {'east-asia-base': 1, 'haesol': 2, 'KoreanTimeLine': 3, 'moonbay': 4},
        off: hidden.off, wasOn: {'east-asia-base', 'haesol'}, known: {'east-asia-base', 'haesol'},
      );
      expect(on, {1, 2, 3});
    });

    test('두 번째 열기는 아무것도 하지 않는다 · 지운 DLC는 폴더에서도 지워져 되살아나지 않는다', () async {
      final again = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol', 'KoreanTimeLine'], hidden: hidden, baseKey: 'east-asia-base');
      expect(again.add, isEmpty, reason: '이미 저장소에 들었다');

      // 그 DLC를 지우면(엔진 remove_pack delete:true — 앱이 그 id의 파일을 모두 지운다 · 얹힌 몫 2) 다음 열기에서 되살아나지 않는다.
      _writeDlc(inDlc('KoreanTimeLine-v1.0.4.htpack'), 'KoreanTimeLine', '1.0.4');
      _writeDlc(inDlc('KoreanTimeLine-v1.0.5.htpack'), 'KoreanTimeLine', '1.0.5');
      final requests = <Map<String, dynamic>>[];
      final job = DlcJob()
        ..applier = (request) async {
          requests.add(request);
          return {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['koreaA'], 'first_pos': 0, 'ms': 150}};
        };
      expect((await job.apply(db: db, removeKey: 'KoreanTimeLine', stored: const {'east-asia-base', 'haesol', 'KoreanTimeLine'})).ok, isTrue);
      expect(requests.single, {'op': 'remove_pack', 'id': 'KoreanTimeLine', 'delete': true, 'path': db});
      expect(File(inDlc('KoreanTimeLine-v1.0.4.htpack')).existsSync(), isFalse);
      expect(File(inDlc('KoreanTimeLine-v1.0.5.htpack')).existsSync(), isFalse);
      final afterRemove = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base');
      expect(afterRemove.add, isEmpty);
    });

    test('DLC 폴더가 없거나 비었으면 읽지도 않는다', () async {
      folder.deleteSync(recursive: true);
      Directory(folder.path).createSync();
      final read = <String>[];
      final plan = await sync(read).pending(db: db, storeKeys: const ['east-asia-base'], hidden: DlcHidden.none, baseKey: 'east-asia-base');
      expect(plan.add, isEmpty);
      expect(plan.broken, isEmpty);
      expect(read, isEmpty);
    });

    // ---- 판정 R33: 묘비 · 깨진 기억 — 뺀 DLC가 지우기 · 끈 목록 쓰기의 실패로 되살아나지 않게 ----

    test('묘비(뺀 DLC)의 id는 폴더에 파일이 남아도 들이지 않고, 지우기가 실패하면 묘비를 남겼다가 다음 열기에서 마저 지운다', () async {
      DlcFolderState(removed: const {'KoreanTimeLine'}).write(db);
      final failing = DlcFolderSync(readPack: sync([]).readPack, deleteFile: (file) async => false);
      final first = await failing.pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', state: DlcFolderState.read(db)!);
      expect(first.add, isEmpty, reason: '파일 잠금으로 못 지웠어도 다시 넣지 않는다');
      expect(first.state.removed, {'KoreanTimeLine'}, reason: '남은 파일이 있으니 묘비를 남긴다');
      expect(File(inDlc('KoreanTimeLine-v1.0.5.htpack')).existsSync(), isTrue);
      // 진짜 읽기 전용 파일(Windows) — 기본 지우기가 실패한다.
      if (Platform.isWindows) {
        Process.runSync('attrib', ['+R', inDlc('KoreanTimeLine-v1.0.5.htpack')]);
        final locked = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', state: first.state);
        expect(locked.add, isEmpty);
        expect(locked.state.removed, {'KoreanTimeLine'}, reason: '읽기 전용이라 하나가 남았다');
        expect(File(inDlc('KoreanTimeLine-v1.0.4.htpack')).existsSync(), isFalse, reason: '지울 수 있는 것은 지웠다');
        Process.runSync('attrib', ['-R', inDlc('KoreanTimeLine-v1.0.5.htpack')]);
      }
      final second = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', state: first.state);
      expect(second.add, isEmpty);
      expect(second.state.removed, isEmpty, reason: '다 지웠으면 묘비에서 뺀다');
      expect(File(inDlc('KoreanTimeLine-v1.0.5.htpack')).existsSync(), isFalse);
      expect(second.cleaned, isNotEmpty);
    });

    test('끈 묘비는 끈 목록이 비어도(쓰기 실패) 들이지 않고 파일도 지우지 않는다(다시 켤 원본)', () async {
      final plan = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: DlcHidden.none, baseKey: 'east-asia-base',
          state: const DlcFolderState(off: {'KoreanTimeLine', 'moonbay'}));
      expect(plan.add, isEmpty);
      expect(File(inDlc('KoreanTimeLine-v1.0.5.htpack')).existsSync(), isTrue);
      expect(plan.state.off, {'KoreanTimeLine', 'moonbay'});
    });

    test('묘비 뒤 같은 DLC를 다시 넣으면(저장소에 들면) 묘비에서 빠져, 다음 판 올림에도 다시 들인다', () async {
      DlcFolderState(removed: const {'KoreanTimeLine'}, off: const {'haesol'}).write(db);
      DlcFolderState.forgetStored(db, const ['east-asia-base', 'KoreanTimeLine']);
      expect(DlcFolderState.read(db)!.removed, isEmpty);
      expect(DlcFolderState.read(db)!.off, {'haesol'}, reason: '저장소에 없는 것은 그대로');
      final plan = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', state: DlcFolderState.read(db)!);
      expect([for (final p in plan.add) p.id], ['KoreanTimeLine'], reason: '판을 올려 저장소에서 빠지면 다시 들인다');
    });

    test('끈 목록(hidden.json)이나 폴더 기억(sync.json)이 있는데 읽지 못하면 들이지 않고 까닭을 돌려준다', () async {
      expect(DlcFolderSync.blocked(db), isNull);
      File(inDlc('hidden.json')).writeAsStringSync('{깨진');
      expect(DlcFolderSync.blocked(db), contains('hidden.json'));
      expect(DlcFolderSync.blocked(db), contains('그 파일을 지우거나 고치면'), reason: '지워도 된다(8 검토) — 지우면 빈 끈 목록');
      expect(DlcHidden.read(db).off, isEmpty, reason: '창은 예전처럼 빈 끈 목록으로 그린다');
      File(inDlc('hidden.json')).deleteSync();
      File(inDlc('sync.json')).writeAsStringSync('[1,');
      expect(DlcFolderSync.blocked(db), contains('sync.json'));
      expect(DlcFolderSync.blocked(db), contains('그 파일을 지우거나 고치면'));
      expect(DlcFolderState.read(db), isNull);
    });

    test('다시 들인 끝의 알림 한 줄 — 들인 것 · 넣지 못한 것 · 읽지 못한 파일 · 묘비로 지운 남은 파일(8 검토)', () {
      expect(dlcFolderNotice(), isNull, reason: '알릴 것이 없으면 알리지 않는다');
      expect(dlcFolderNotice(cleaned: const ['KoreanTimeLine-v1.0.5.htpack']), '뺀 DLC의 남은 파일 KoreanTimeLine-v1.0.5.htpack을(를) DLC 폴더에서 지웠습니다.');
      final all = dlcFolderNotice(added: const ['«Tigers of the East»'], failed: const ['«달물결»: 까닭 (자세히: 엔진의 글)'], retry: const ['«갈대»: 표 없음'], broken: const ['깨진-파일.htpack'], cleaned: const ['a.htpack', 'b.htpack'])!;
      expect(all, startsWith('DLC 폴더에서 DLC 1개를 다시 넣었습니다: «Tigers of the East».'));
      expect(all, contains('넣지 못해 건너뛰었습니다 — «달물결»: 까닭 (자세히: 엔진의 글). 그 파일이 바뀌거나 앱 판이 바뀌기 전에는 다시 해 보지 않습니다.'));
      expect(all, contains('지금 넣지 못해 건너뛰었습니다 — «갈대»: 표 없음. 다음에 앱을 열 때 다시 해 봅니다.'),
          reason: '저장소 쪽 거절은 지문을 적지 않아 다시 해 본다 — 꼬리 말이 거짓이 되지 않게(10b 고침 재검토)');
      expect(all, contains('DLC 폴더의 깨진-파일.htpack은(는) DLC 파일로 읽을 수 없어 건너뛰었습니다 — 그 파일이 바뀌거나 앱 판이 바뀌기 전에는 다시 알리지 않습니다.'));
      expect(all, endsWith('뺀 DLC의 남은 파일 a.htpack · b.htpack을(를) DLC 폴더에서 지웠습니다.'));
      expect(all, isNot(contains('))')), reason: '괄호 안에 괄호를 겹치지 않는다(② 넘김)');
    });

    test('원자적 쓰기는 이름 바꾸기가 잠깐 막혀도(백신 · 색인이 쥠) 짧게 다시 해 본다 — 30ms씩 세 번(8 검토)', () {
      final target = File(inDlc('sync.json'));
      var tries = 0;
      writeFileAtomic(target, '{"version":1}\n', rename: (temp, to) {
        if (++tries < 3) throw FileSystemException('잠김', to);
        temp.renameSync(to);
      });
      expect(tries, 3);
      expect(target.readAsStringSync(), '{"version":1}\n');
      tries = 0;
      final clock = Stopwatch()..start();
      expect(() => writeFileAtomic(target, '바뀐 글', rename: (temp, to) {
        tries++;
        throw FileSystemException('잠김', to);
      }), throwsA(isA<FileSystemException>()));
      expect(tries, 4, reason: '처음 한 번 + 다시 세 번');
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(80), reason: '사이마다 30ms');
      expect(target.readAsStringSync(), '{"version":1}\n', reason: '옛 파일은 온전하다');
      expect(Directory(inDlc('')).listSync().map((f) => f.path.split(Platform.pathSeparator).last).where((n) => n.endsWith('.tmp')), isEmpty, reason: '임시 파일이 남지 않는다');
    });

    test('읽지 못한 파일 · 넣지 못한 파일은 지문으로 기억해, 같은 파일이면 다시 읽거나 알리지 않는다', () async {
      final read = <String>[];
      final first = await sync(read).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base');
      expect(first.broken, ['깨진-파일.htpack']);
      expect(first.state.skip.keys, contains('깨진-파일.htpack'));
      // 넣다 실패한 파일도 기억한다(앱 틀이 하나씩 넣다가 실패하면 적는다).
      final state = first.state.skipping(inDlc('KoreanTimeLine-v1.0.5.htpack'));
      read.clear();
      final second = await sync(read).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', state: state);
      expect(second.broken, isEmpty, reason: '같은 깨진 파일은 다시 알리지 않는다');
      expect(read, isNot(contains('깨진-파일.htpack')), reason: '다시 읽지도 않는다');
      expect([for (final p in second.add) p.version], ['1.0.4'], reason: '넣지 못한 1.0.5는 건너뛰고 다음으로 높은 판');
      // 파일이 바뀌면(지문이 다르면) 다시 본다.
      File(inDlc('깨진-파일.htpack')).writeAsStringSync('고친 파일이지만 아직 읽을 수 없음 — 길이가 다르다');
      final third = await sync([]).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: hidden, baseKey: 'east-asia-base', state: second.state);
      expect(third.broken, ['깨진-파일.htpack']);
    });

    // ---- 다시 들이기의 몸(앱 틀 `_syncDlcFolder` → DlcFolderImport.run — 8 검토 걱정 4) ----

    DlcFolderPack packOf(String name) => packs[name]!;

    test('하나씩 넣고 넣지 못한 파일만 건너뛸 것으로 적는다 — 끝 알림 한 줄 · 잡음은 끝에 푼다', () async {
      final job = DlcJob();
      final kept = <DlcFolderState>[];
      final put = <String>[];
      final notice = await DlcFolderImport.run(
        job: job,
        state: DlcFolderState.empty,
        pending: (state) async => DlcFolderPlan(add: [packOf('KoreanTimeLine-v1.0.5.htpack'), packOf('moonbay-v2.0.0.htpack')], broken: const ['깨진-파일.htpack'], cleaned: const ['옛-파일.htpack'], state: state),
        keep: kept.add,
        put: (p, i, n) async {
          expect(job.running, isTrue, reason: '넣는 동안 잡혀 있다');
          put.add(p.id);
          job.release(); // 진짜 넣기(_runDlcJob(held: true) → DlcJob.apply)는 잡음을 이어받아 끝낸다
          job.lastCode = p.id == 'KoreanTimeLine' ? null : 'layout'; // 넣지 못한 것은 그 파일 탓(DLC code — 판정 R68-3)
          return p.id == 'KoreanTimeLine';
        },
        canPut: (_) => true,
        stopped: () => false,
        restarted: () => false,
      );
      expect(put, ['KoreanTimeLine', 'moonbay']);
      expect(kept.last.skip.keys, ['moonbay-v2.0.0.htpack'], reason: '넣지 못한 것만');
      expect(notice, allOf(startsWith('DLC 폴더에서 DLC 1개를 다시 넣었습니다: «Tigers of the East».'), contains('«달물결 기록집»'), contains('옛-파일.htpack')));
      expect(job.running, isFalse);
    });

    test('저장소 쪽 거절(달력 표 없음 · 원본 없음 …)은 건너뛸 것으로 적지 않고 \'다음에 열 때 다시\'로 알린다(고침 1회차 Minor · 재검토)', () async {
      final job = DlcJob();
      final kept = <DlcFolderState>[];
      final notice = await DlcFolderImport.run(
        job: job,
        state: DlcFolderState.empty,
        pending: (state) async => DlcFolderPlan(add: [packOf('KoreanTimeLine-v1.0.5.htpack'), packOf('moonbay-v2.0.0.htpack')], state: state),
        keep: kept.add,
        put: (p, i, n) async {
          job.release();
          job.lastCode = p.id == 'KoreanTimeLine' ? 'calendar' : 'version';
          return false;
        },
        canPut: (_) => true,
        stopped: () => false,
        restarted: () => false,
      );
      expect(kept.last.skip.keys, ['moonbay-v2.0.0.htpack'], reason: '파일 탓(낮은 판)만 지문으로 적는다');
      expect(notice, contains('지금 넣지 못해 건너뛰었습니다 — «Tigers of the East». 다음에 앱을 열 때 다시 해 봅니다.'));
      expect(notice, contains('넣지 못해 건너뛰었습니다 — «달물결 기록집». 그 파일이 바뀌거나 앱 판이 바뀌기 전에는 다시 해 보지 않습니다.'));
    });

    test('넣기 실패를 그 파일 탓으로 기억(skip)하는 것은 DLC code(layout · range · version · dup_uid · broken)뿐 — code 없음 · path · calendar · original · base는 다음 열기에서 다시(판정 R68-3)', () async {
      for (final (code, remembered) in const [(null, false), ('path', false), ('calendar', false), ('original', false), ('base', false),
          ('layout', true), ('range', true), ('version', true), ('dup_uid', true), ('broken', true)]) {
        final job = DlcJob();
        final kept = <DlcFolderState>[];
        await DlcFolderImport.run(
          job: job,
          state: DlcFolderState.empty,
          pending: (state) async => DlcFolderPlan(add: [packOf('moonbay-v2.0.0.htpack')], state: state),
          keep: kept.add,
          put: (p, i, n) async {
            job.release();
            job.lastCode = code;
            return false;
          },
          canPut: (_) => true,
          stopped: () => false,
          restarted: () => false,
        );
        expect(kept.last.skip.keys, remembered ? ['moonbay-v2.0.0.htpack'] : isEmpty, reason: '$code');
        expect(dlcFileFault(code), remembered, reason: '$code');
      }
    });

    test('range(그 DLC의 날짜가 달력 범위 밖 — 판정 R62)는 그 파일의 문제로 기억한다 — 열 때마다 되풀이하지 않고 · 파일이 바뀌면 다시', () async {
      // 앱이 머리로 id · 판을 읽으므로 진짜 팩 꼴로 · 엔진(쓰기 일꾼)은 range로 거절한다.
      _writeDlc(inDlc('moonbay-v2.0.0.htpack'), 'moonbay', '2.0.0');
      const why = '«달물결 기록집»의 날짜가 앱이 아는 달력 범위 밖입니다 — 보조 달력 날짜는 -3500 ~ 2500년 안이어야 합니다';
      final job = DlcJob()..applier = (request) async => {'ok': false, 'error': why, 'code': 'range'};
      final kept = <DlcFolderState>[];
      final notice = await DlcFolderImport.run(
        job: job,
        state: DlcFolderState.empty,
        pending: (state) async => DlcFolderPlan(add: [packOf('moonbay-v2.0.0.htpack')], state: state),
        keep: kept.add,
        // 앱 틀의 넣기(_runDlcJob(held: true) → DlcJob.apply)처럼 잡음을 이어받아 엔진에 맡긴다.
        put: (p, i, n) async => (await job.apply(db: db, files: [p.path])).ok,
        canPut: (_) => true,
        stopped: () => false,
        restarted: () => false,
      );
      expect(job.lastCode, 'range');
      expect(kept.last.skip.keys, ['moonbay-v2.0.0.htpack'], reason: '지문으로 기억 — 저장소 쪽 거절(calendar)처럼 다음 열기에 다시 해 보지 않는다');
      expect(notice, allOf(contains('넣지 못해 건너뛰었습니다 — «달물결 기록집»: ${dlcRefusalText('range', why)}. 그 파일이 바뀌거나 앱 판이 바뀌기 전에는 다시 해 보지 않습니다.'),
          isNot(contains('저장소가 바뀌면'))));
      final read = <String>[];
      final again = await sync(read).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: DlcHidden.none, baseKey: 'east-asia-base', state: kept.last);
      expect(read, isNot(contains('moonbay-v2.0.0.htpack')), reason: '같은 파일이면 다음 열기에서 읽지도 않는다');
      expect(again.add.map((p) => p.id), isNot(contains('moonbay')));
      _writeDlc(inDlc('moonbay-v2.0.0.htpack'), 'moonbay', '2.0.1-날짜-고침'); // 크기가 달라져 지문이 바뀐다
      final fixed = <String>[];
      await sync(fixed).pending(db: db, storeKeys: const ['east-asia-base', 'haesol'], hidden: DlcHidden.none, baseKey: 'east-asia-base', state: kept.last);
      expect(fixed, contains('moonbay-v2.0.0.htpack'), reason: '메이커에서 고쳐 파일이 바뀌면 다시 본다');
    });

    test('저장소는 고쳐 썼는데 다시 읽지 못해 끝난 것(restart)은 건너뛸 것으로 적지 않고 알리지도 않는다', () async {
      final job = DlcJob();
      final kept = <DlcFolderState>[];
      var restart = false;
      final notice = await DlcFolderImport.run(
        job: job,
        state: DlcFolderState.empty,
        pending: (state) async => DlcFolderPlan(add: [packOf('KoreanTimeLine-v1.0.5.htpack'), packOf('moonbay-v2.0.0.htpack')], state: state),
        keep: kept.add,
        put: (p, i, n) async {
          restart = true;
          job.release();
          return false;
        },
        canPut: (_) => true,
        stopped: () => restart,
        restarted: () => restart,
      );
      expect(notice, isNull);
      expect(kept.every((s) => s.skip.isEmpty), isTrue, reason: '그 파일은 넣지 못한 것이 아니다');
      expect(job.running, isFalse);
    });

    test('살피기가 던지거나 넣기가 던져도 잡음을 푼다(try/finally) · 이미 돌면 아무것도 하지 않는다', () async {
      final job = DlcJob();
      expect(await DlcFolderImport.run(job: job, state: DlcFolderState.empty, pending: (_) async => throw StateError('읽기 실패'), keep: (_) {}, put: (p, i, n) async => true, canPut: (_) => true, stopped: () => false, restarted: () => false), isNull);
      expect(job.running, isFalse);
      await expectLater(
        DlcFolderImport.run(
          job: job, state: DlcFolderState.empty, pending: (state) async => DlcFolderPlan(add: [packOf('KoreanTimeLine-v1.0.5.htpack')], state: state),
          keep: (_) {}, put: (p, i, n) async => throw StateError('넣다 던짐'), canPut: (_) => true, stopped: () => false, restarted: () => false,
        ),
        throwsStateError,
      );
      expect(job.running, isFalse, reason: '던져도 잡음이 남지 않는다');
      expect(job.hold('다른 일'), isTrue);
      var asked = false;
      expect(await DlcFolderImport.run(job: job, state: DlcFolderState.empty, pending: (_) async {
        asked = true;
        return const DlcFolderPlan();
      }, keep: (_) {}, put: (p, i, n) async => true, canPut: (_) => true, stopped: () => false, restarted: () => false), isNull);
      expect(asked, isFalse, reason: '다른 일이 돌면 넘긴다');
      expect(job.running, isTrue, reason: '남의 잡음은 풀지 않는다');
      job.release();
    });

    test('폴더 기억은 원자적으로 쓴다(임시 파일 → 이름 바꾸기 · 있는 파일을 바꿔 씀 · 임시 파일이 남지 않음)', () {
      const DlcFolderState(removed: {'a'}).write(db);
      const DlcFolderState(removed: {'b'}, off: {'c'}, skip: {'x.htpack': 'fp'}).write(db);
      final back = DlcFolderState.read(db)!;
      expect(back.removed, {'b'});
      expect(back.off, {'c'});
      expect(back.skip, {'x.htpack': 'fp'});
      expect(Directory(inDlc('')).listSync().map((f) => f.path.split(Platform.pathSeparator).last).where((n) => n.startsWith('sync.json.')), isEmpty);
      DlcHidden.save(db, {'version': 1, 'off': ['a'], 'baseRemoved': false, 'cards': {}});
      DlcHidden.save(db, {'version': 1, 'off': ['b'], 'baseRemoved': false, 'cards': {}});
      expect(DlcHidden.read(db).off, {'b'});
      expect(Directory(inDlc('')).listSync().map((f) => f.path.split(Platform.pathSeparator).last).where((n) => n.startsWith('hidden.json.')), isEmpty);
    });
  });

  group('진짜 자료 처리부(FFI · archive-tool — 빠른 빌드)로 — 판정 R34 D · R36', () {
    final dll = File('../engine/target/release/archive_engine.dll'), tool = File('../engine/target/release/archive-tool.exe');
    final ready = Platform.isWindows && dll.existsSync() && tool.existsSync();
    final calendar = File('../engine/tests/fixtures/lay/calendar-slice.json').absolute.path;
    final base = File('../fixtures/oracle/east-asia.json').absolute.path;
    // 감독의 실자료 KoreanTimeLine v1.0.5(형식 3 — 읽기만 · 사본을 쓴다). 없는 PC는 정답지의 작은 장면으로.
    final ktl = File('D:/Timeline/KoreanTimeLine-v1.0.5.htpack');

    Future<String> run(List<String> args) async {
      final r = await Process.run(tool.absolute.path, args, stdoutEncoding: utf8, stderrEncoding: utf8);
      if (r.exitCode != 0) throw StateError('archive-tool ${args.first}: ${r.stderr}');
      return r.stdout as String;
    }

    /// 동아시아 정답지로 지은 저장소(달력 표 있음 — 판정 R36의 새 시드).
    Future<String> build(String out) async {
      await run(['build', out, base, '--now=2026-10-22T09:00:00+09:00', '--calendar=$calendar', '--calendar-narrow']);
      return out;
    }

    /// 옛 저장소: 동아시아 + 사용자 DLC(KoreanTimeLine 사본) + 꺼 둔 DLC(nest-scene — 보관함). 돌려주는 것: 사용자 DLC id · 꺼 둔 DLC id.
    Future<(String, String)> oldStore(String db) async {
      await build(db);
      final user = ktl.existsSync() ? ktl.copySync('${seat.dir.path}${Platform.pathSeparator}KoreanTimeLine-v1.0.5.htpack').path : File('../fixtures/oracle/move-scene.htpack').absolute.path;
      final nest = File('../fixtures/oracle/nest-scene.htpack').absolute.path;
      await run(['add-pack', db, user]);
      await run(['add-pack', db, nest]);
      final nestId = readDlcFileHead(nest).head!.id;
      await run(['remove-pack', db, nestId]);
      return (readDlcFileHead(user).head!.id, nestId);
    }

    for (final (where, computer) in const [('휴대폰(withEngine)', false), ('컴퓨터(withTool)', true)]) {
      test('$where: 시드 판이 바뀌어도 사용자 DLC와 꺼 둔 DLC가 남는다 — 옆 파일의 새 시드에 from_store로 넣은 뒤 바꿔 놓는다', () async {
        if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
        final (userId, nestId) = await oldStore(seat.db);
        seat.mark.writeAsStringSync('0.0.3');
        final fresh = await build('${seat.dir.path}${Platform.pathSeparator}새-판-시드.db');
        final bytes = File(fresh).readAsBytesSync();
        final carry = computer ? SeedCarry.withTool(tool.absolute.path, library: dll.absolute.path) : SeedCarry.withEngine(dll.absolute.path);
        final result = await carry.place(path: seat.db, stamp: '0.0.4', seed: () async => bytes);
        expect(result.placed, isTrue, reason: result.kept);
        expect(result.moved, [userId, nestId]);
        expect(seat.mark.readAsStringSync(), '0.0.4');
        final engine = SeedCarry.withEngine(dll.absolute.path);
        expect([for (final p in (await engine.listPacks!(seat.db))!) p.id], ['east-asia-base', userId], reason: '사용자 DLC가 새 시드에 들었다');
        expect([for (final p in (await engine.listKept!(seat.db))!) p.id], [nestId], reason: '꺼 둔 DLC는 새 시드의 보관함에');
        expect(File('${seat.db}.새-시드').existsSync(), isFalse);
        // 같은 판이면 다시 하지 않는다.
        expect((await carry.place(path: seat.db, stamp: '0.0.4', seed: () async => bytes)).placed, isFalse);
      }, timeout: const Timeout(Duration(minutes: 5)));
    }

    test('표 없는 옛 저장소: 넣기는 달력 표로 거절되고, 시드 잇기로 새 판(표 있음)에 옮긴 뒤에는 넣을 수 있다(판정 R36)', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      final (userId, _) = await oldStore(seat.db);
      // 표를 지운다(이 계획 전 Node 길로 지은 저장소의 꼴) — Node 내장 sqlite로.
      final cannot = await _nodeSqlite("const {DatabaseSync}=require('node:sqlite');const d=new DatabaseSync(process.argv[1]);d.prepare(\"DELETE FROM blobs WHERE key='calendar:table'\").run();d.close()", [seat.db]);
      if (cannot != null) return markTestSkipped(cannot);
      final nest = File('../fixtures/oracle/nest-scene.htpack').absolute.path;
      final refused = await Process.run(tool.absolute.path, ['add-pack', seat.db, nest], stdoutEncoding: utf8, stderrEncoding: utf8);
      expect(refused.exitCode, isNot(0), reason: '표 없는 저장소에는 넣지 못한다');
      expect('${refused.stderr}', contains('달력'));
      seat.mark.writeAsStringSync('0.0.3');
      final bytes = File(await build('${seat.dir.path}${Platform.pathSeparator}새-판-시드.db')).readAsBytesSync();
      final result = await SeedCarry.withEngine(dll.absolute.path).place(path: seat.db, stamp: '0.0.4', seed: () async => bytes);
      expect(result.placed, isTrue, reason: result.kept);
      expect(result.moved, contains(userId));
      final added = await Process.run(tool.absolute.path, ['add-pack', seat.db, nest], stdoutEncoding: utf8, stderrEncoding: utf8);
      expect(added.exitCode, 0, reason: '새 판(표 있음)으로 옮긴 뒤에는 넣는다: ${added.stderr}');
      expect([for (final p in (await SeedCarry.withEngine(dll.absolute.path).listPacks!(seat.db))!) p.id], containsAll(['east-asia-base', userId]));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test("예전 배치로만 든 DLC(원본 없음 · 표 없는 옛 휴대폰 저장소 — 판정 R34 A로 지킴): 그 .htpack을 '파일에서 더하기'로 고르면 앱이 DLC 폴더에 두고 지킴 "
        '표식을 지운다 → 다음에 켤 때 시드 잇기가 그 원본으로 새 판에 옮긴다(계획 P4 과제 11c — .htlayout을 더 받지 않아도 길이 막히지 않는다)', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      final sep = Platform.pathSeparator;
      // 사용자가 가진 그 DLC의 .htpack(메이커가 저장한 것 — 지문이 맞는 진짜 전용 팩).
      final downloads = Directory('${seat.dir.path}$sep내려받기')..createSync();
      const version = '1.0.0';
      final picked = await sealDlcWithTool(tool.absolute.path, downloads.path, id: 'tiny-reed', version: version, name: '작은 갈대 기록집');
      // 10a 휴대폰의 저장소: 동아시아 + 메이커 배치(.htlayout)로만 넣은 tiny-reed(원본 없음) · 달력 표 없음(Node 길로 지은 시드) — 그 꼴로 만든다
      // (엔진 검사 tests/apply.rs의 drop_original과 같은 고침 + 표 지우기 — Node 내장 sqlite로).
      await run(['build', seat.db, base, '--now=2026-10-22T09:00:00+09:00', '--calendar=$calendar', '--calendar-narrow', picked]);
      const strip = "const {DatabaseSync}=require('node:sqlite');const d=new DatabaseSync(process.argv[1]);const key=process.argv[2];"
          "const keys=JSON.parse(d.prepare(\"SELECT value FROM meta WHERE key='pack_keys'\").get().value);const n=Object.keys(keys).find(k=>keys[k]===key);"
          "d.prepare('UPDATE packs SET original=NULL,sha256=NULL WHERE id=?').run(Number(n));"
          "const info=JSON.parse(d.prepare(\"SELECT value FROM meta WHERE key='pack_info'\").get().value);info[n].original=false;"
          "d.prepare(\"UPDATE meta SET value=? WHERE key='pack_info'\").run(JSON.stringify(info));d.prepare(\"DELETE FROM blobs WHERE key='calendar:table'\").run();d.close()";
      final cannot = await _nodeSqlite(strip, [seat.db, 'tiny-reed']);
      if (cannot != null) return markTestSkipped(cannot);
      seat.mark.writeAsStringSync('0.0.3');
      final bytes = File(await build('${seat.dir.path}$sep새-판-시드.db')).readAsBytesSync();
      final carry = SeedCarry.withEngine(dll.absolute.path);
      final kept = await carry.place(path: seat.db, stamp: '0.0.4', seed: () async => bytes);
      expect(kept.placed, isFalse, reason: '장면: 원본이 어디에도 없어 지킨다(R34 A)');
      expect(kept.kept, contains("그 DLC의 .htpack을 '파일에서 더하기'로 골라 주세요"));
      final keptMark = File('${seat.db}.seed-kept');
      expect(keptMark.existsSync(), isTrue);
      expect((await carry.place(path: seat.db, stamp: '0.0.4', seed: () async => bytes)).kept, isNull, reason: '지킨 판은 실행마다 다시 해 보지 않는다');
      // 사용자가 그 DLC의 .htpack(메이커가 저장한 것 — 같은 id · 판)을 '파일에서 더하기'로 고른다.
      final reed = (await carry.listPacks!(seat.db))!.firstWhere((p) => p.id == 'tiny-reed');
      expect((reed.original, reed.version), (false, version));
      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine.start(seat.db);
      final job = DlcJob()..phone = true;
      try {
        job.factsFrom(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
        expect(job.packFacts['tiny-reed']?.original, isFalse, reason: '앱 틀이 뼈대를 읽을 때 채우는 카드의 원본');
        final (scene, _, _) = makePackScene();
        final flow = DlcApplyFlow(job: job, scene: scene, engineCall: engine.call, engineApply: engine.write, reload: (_) async {});
        final done = await flow.run(db: seat.db, files: [picked]);
        // 지금 엔진: 표 없는 저장소는 넣고 빼기를 먼저 달력 표로 거절한다(판정 R36 — 원본 채우기 전) → 앱이 그 .htpack을 DLC 폴더에 둔다(과제 11c · R48).
        expect(done.ok, isFalse);
        expect(job.lastCode, 'calendar');
        expect(job.status, allOf(contains('«작은 갈대 기록집»의 원본(.htpack)을 DLC 폴더에 두었습니다'), contains('앱을 다시 켜면')), reason: job.lines.join('\n'));
        expect(job.stashedNote, job.status);
        expect(File('${seat.dir.path}${sep}DLC$sep${dlcOriginalFileName('tiny-reed', version)}').existsSync(), isTrue);
        expect(keptMark.existsSync(), isFalse, reason: '지킴 표식을 지워 다음에 켤 때 다시 해 본다');
      } finally {
        try {
          await engine.call({'op': 'close'});
        } catch (_) {}
        engine.close();
      }
      // 다음에 켤 때: 시드 잇기가 DLC 폴더의 그 원본으로 새 판(표 있음)에 옮긴다.
      final placed = await carry.place(path: seat.db, stamp: '0.0.4', seed: () async => bytes);
      expect(placed.placed, isTrue, reason: placed.kept);
      expect(placed.moved, contains('tiny-reed'));
      final now = (await carry.listPacks!(seat.db))!;
      expect([for (final p in now) p.id], containsAll(['east-asia-base', 'tiny-reed']));
      expect(now.firstWhere((p) => p.id == 'tiny-reed').original, isTrue, reason: '새 판에는 원본과 함께 든다 — 그 뒤로는 넣고 빼기가 엔진으로 된다');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('판 올림 뒤 다시 들이기가 엔진 도구로 DLC 폴더 파일을 읽는다(판정 R58) — check-pack의 임시 결과는 준 자리(--memory-dir 아래 — 판정 R50)에 쓰고 지운다', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      final scratch = Directory('${seat.dir.path}${Platform.pathSeparator}임시');
      final pack = await DlcFolderSync.withTool(tool.absolute.path, scratch: scratch).readPack(File('../fixtures/oracle/nest-scene.htpack').absolute.path);
      expect((pack?.id, pack?.version), ('nest-scene', readDlcFileHead(File('../fixtures/oracle/nest-scene.htpack').absolute.path).head!.version));
      expect(scratch.existsSync(), isTrue, reason: '임시 결과를 그 자리에 썼다');
      expect(scratch.listSync(), isEmpty, reason: '읽은 뒤 지운다');
      // 깨진 파일은 도구가 읽고 거절한다(종료 코드 1) — 도구 실패가 아니라 그 파일의 탓(null · 지문으로 기억).
      final broken = (File('${seat.dir.path}${Platform.pathSeparator}깨진.htpack')..writeAsStringSync('팩이 아님')).path;
      expect(await DlcFolderSync.withTool(tool.absolute.path, scratch: scratch).readPack(broken), isNull);
    });

    test('진짜 자료 처리부(FFI)로 목록을 읽는다 — 저장소의 pack_info · 깨진 파일은 null', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      if (!engineHasImport(dll.absolute.path)) return markTestSkipped('archive_import가 없는 자료 처리부');
      final store = '${seat.dir.path}${Platform.pathSeparator}tiny.db';
      final built = await callArchiveImport(layoutImportRequest(layout: File('test/fixtures/tiny.htlayout').absolute.path, out: store), libraryPath: dll.absolute.path);
      expect(built['ok'], isTrue, reason: '$built');
      final engine = SeedCarry.withEngine(dll.absolute.path);
      final listed = await engine.listPacks!(store);
      expect(listed?.map((p) => p.id), contains('tiny-reed'));
      expect(await engine.names!(store), containsPair('tiny-reed', '작은 갈대 기록집'));
      expect(await engine.listKept!(store), isEmpty, reason: '보관함 표가 없는 저장소는 빈 보관함');
      File(seat.db).writeAsStringSync('저장소가 아님');
      expect(await engine.listPacks!(seat.db), isNull);
    });
  });
}
