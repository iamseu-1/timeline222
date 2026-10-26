import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../engine.dart' show callEngineOnce;
import 'dlc_add.dart'
    show DlcFolderState, DlcHidden, DlcJob, copyFileAtomic, dlcAppVersion, dlcErrorText, dlcFileFingerprint, dlcFileFault, dlcOriginalFileName, dlcPlainEngineError, dlcRefusalText, seedKeptPath, writeFileAtomic;
import 'dlc_layout_import.dart' show compareDlcVersion, readDlcFileHead;

// 앱의 새 판(시드)을 놓을 때 사용자가 넣은 DLC를 잇는 길(계획 한 벌 P4 정한 것 #14 · 옛 DLC의 약속 2 — 과제 8 · 10a · 10b).
//
// 시드 = 앱 묶음에 든 저장소(`assets/seed/archive.db` — 표식은 `seed.json`의 stamp). 판이 바뀌면 앱이 그것을 저장소 자리에 놓는데, 예전에는 옛 저장소를
// 그냥 덮어써 사용자가 넣은 DLC가 사라졌다. 이제는(판정 R34 D — 휴대폰 · 컴퓨터가 같은 길):
//   1) 옛 저장소의 DLC 목록을 먼저 읽고(못 읽으면 시드를 읽거나 쓰지도 않고 그대로 — 휴대폰은 아래) 새 시드를 옆 파일(`<저장소>.새-시드`)에 써 두 목록을
//      견준다 — 사용자 DLC = 옛 저장소의 DLC 가운데 기본팩(동아시아 · 새 시드의 첫째)이 아니고 새 시드에 없거나 새 시드의 것보다 판이 높은 것(사용자가
//      올린 판) · 꺼 둔 DLC = 옛 저장소의 보관함(`kept_packs` — 계약 2-7-1). 옛 저장소에 목록(`pack_info`)이 없으면(아주 옛 저장소) 사용자 DLC를 몰라
//      시드를 놓고 알린다 — DLC 폴더의 DLC는 연 뒤 다시 들인다(R32).
//   2) **옆 파일의 새 시드에** 자료 처리부(FFI)로 그 DLC를 넣는다([SeedCarry.carryInto] — `add_pack` `from_store`=옛 저장소 + `ids`: 든 원본 · 없으면 그
//      저장소의 보관함 / 원본 없이 든 DLC는 DLC 폴더의 `<id>-v<판>.htpack`을 `files`로 / 꺼 둔 DLC는 넣은 뒤 `remove_pack delete:false`로 다시 보관함에).
//      새 시드에는 달력 표가 있어(판정 R36) 표 없는 옛 저장소의 DLC도 이 길로 옮겨진다. 새 판 자료가 어느 DLC를 받지 않으면(같은 항목이 두 트랙 ·
//      배치 거절 — DLC 탓) 그 DLC만 빼고 나머지를 넣고, 그 원본은 DLC 폴더에 둔 뒤 알린다(판정 R59 — [seedCarrySteps] · 원본을 둘 수 없으면 옛 저장소
//      그대로). **저장소 쪽 거절(새 판 자료에 달력 표가 없음 · 바탕이 다름)이면 옛 저장소를 그대로 두고**(새 시드를 놓지 않고) 까닭을 돌려준다 — 앱이
//      알린다. 원본이 저장소에도 DLC 폴더에도 없는 DLC(메이커 배치로만 든 것)가 있어도 지킨다(판정 R34 A의 지킴).
//   3) 다 넣었으면 옛 저장소를 그 새 시드로 바꿔 놓고 표식을 적는다(앱은 연 뒤 할 일이 없다).
//      컴퓨터(엔진 도구가 있는 곳)에서 옛 저장소와 새 시드의 바탕(기본팩)이 다르면 원본은 `DLC/다른-바탕/`에 꺼내 두되 넣지 않고(`pack-out` · 폴더
//      기억의 끈 묘비 — 연 뒤 다시 들이기도 넣지 않게) 알린다(다른 바탕 위에 얹으면 그 DLC가 기대던 트랙이 없다). 휴대폰은 꺼낼 길이 없어 넣어 본다
//      (엔진이 거절하면 지킴).
// 휴대폰([SeedCarry.withEngine] — 목록 · 보관함 · 넣기 모두 자료 처리부): 지키기로 정한 판은 `<저장소>.seed-kept`에 적어 실행마다 다시 견주거나 알리지
// 않는다. 옛 저장소를 읽지 못하면(깨짐 · 열기 실패) 새 시드를 놓되 옛 파일은 지우지 않고 옆에 이름을 바꿔 둔다(`<저장소>.옛-저장소-<시각>` — 되찾을 길).
// 휴대폰의 '사용자 DLC'는 새 시드와만 견주지 않는다([SeedCarry.phoneUserPacks] — 8 검토 2회차): 옛 저장소의 바탕(첫 팩)과 옛 시드에 든 그대로인 팩
// (시드를 놓을 때 `<저장소>.seed-packs`에 적어 둠)은 뺀다 — 시드의 바탕이 바뀌거나 옛 시드의 팩을 새 시드가 빼도 옛 저장소에 묶이지 않게.
// 목록을 읽을 길도 없으면([listPacks] 없음) 예전처럼 덮어쓴다.
// 주의: Windows 실행본은 시드를 쓰지 않는다(설치 프로그램 · 포터블이 저장소를 `자료/`에 둔다 — `prototype.json`) — 이 길은 `_placeSeed`를 거치는 곳만.
// Windows는 판을 올리면 설치 프로그램 · 포터블이 `자료/…/archive.db`를 새 판의 것으로 통째로 덮는다 — 사용자 DLC의 파일은 `DLC/` 폴더에 남으므로
// (고쳐 쓰기가 끝날 때마다 폴더를 저장소와 맞춘다 — 얹힌 몫 2) 앱이 저장소를 열 때 '폴더에는 있는데 저장소에도 끈 목록에도 없는 사용자 DLC'를
// 한 번 들인다([DlcFolderSync] — 판정 R32 · 엔진 `add_pack`).

/// 엔진 도구로 저장소의 DLC 원본을 파일로 꺼낸다(`archive-tool pack-out`). 같은 폴더의 임시 파일(`<file>.<시각>.tmp`)에 꺼낸 뒤 이름을 바꿔 놓는다
/// (① m-2 — 꺼내다 멈춰도 반쯤 쓴 사본이 [file] 자리에 남지 않게 · 같은 이름의 파일은 바꿔 놓는다 · 남은 임시 파일은 열 때 치운다 — [cleanDlcTemps]).
/// 참이면 꺼냈다.
Future<bool> archiveToolPackOut(String tool, String db, String id, String file) async {
  final temp = File('$file.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    final run = await Process.run(tool, ['pack-out', db, id, temp.path], stdoutEncoding: utf8, stderrEncoding: utf8);
    if (run.exitCode != 0 || !temp.existsSync()) return false;
    copyFileAtomic(temp.path, file);
    return File(file).existsSync();
  } catch (_) {
    return false;
  } finally {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } catch (_) {}
  }
}

/// 열 때(엔진 도구가 있는 곳 — 앱 틀의 `_syncDlcFolder`): 저장소에 든 DLC([packs] — 첫째가 바탕) 가운데 DLC 폴더에 그 id · 판의 사본이 없는 것을 저장소에서
/// 꺼내(`pack-out` — [packOut]) `<id>-v<판>.htpack`으로 채운다(판정 R60 I-2 — 판 올림 뒤 다시 들이기(R32)는 그 사본을 믿는다: 사본이 없으면 새 판이 덮은
/// 저장소에서 그 DLC가 말없이 사라진다). 바탕(새 판에 늘 들어 있다)과 원본 없이 든 DLC(꺼낼 원본 없음)는 건너뛴다. 채운 파일 이름들을 돌려준다.
Future<List<String>> fillDlcFolderCopies({
  required String db,
  required List<SeedPack> packs,
  required Future<bool> Function(String store, String id, String file) packOut,
}) async {
  if (packs.length < 2) return const [];
  final sep = Platform.pathSeparator;
  final dir = Directory('${File(db).absolute.parent.path}${sep}DLC');
  final heads = [
    if (dir.existsSync())
      for (final f in dir.listSync(followLinks: false))
        if (f is File && f.path.toLowerCase().endsWith('.htpack')) ?readDlcFileHead(f.path).head,
  ];
  final filled = <String>[];
  for (final p in packs.skip(1)) {
    if (!p.original || p.id.isEmpty) continue;
    if (heads.any((h) => h.id == p.id && (p.version.isEmpty || compareDlcVersion(h.version, p.version) == 0))) continue;
    final name = dlcOriginalFileName(p.id, p.version);
    final target = '${dir.path}$sep$name';
    // 같은 이름의 파일이 있는데 머리를 읽지 못하면(반쯤 쓴 사본 · 깨짐) 꺼내 바꿔 놓는다(① m-2 — [archiveToolPackOut]은 바꿔 놓는다). 머리를 읽을 수 있는
    // 다른 DLC의 파일이면 남의 원본이라 그대로 둔다(고침 2회차 Minor 4).
    if (File(target).existsSync() && readDlcFileHead(target).head != null) continue;
    try {
      await dir.create(recursive: true);
      if (await packOut(db, p.id, target)) filled.add(name);
    } catch (_) {}
  }
  return filled;
}

/// 저장소에 든 DLC 하나(`meta.pack_info` — 첫째가 기본팩).
class SeedPack {
  const SeedPack(this.id, this.version, {this.original = true});
  final String id, version;

  /// 원본(.htpack)을 저장소에 품었는가(`pack_info.original` — 없으면 참).
  final bool original;

  @override
  String toString() => '$id@$version';
}

/// 시드 놓기의 끝.
class SeedCarryResult {
  const SeedCarryResult({this.placed = false, this.moved = const [], this.kept, this.note});

  /// 새 시드를 놓았는가.
  final bool placed;

  /// 새 시드에 옮겨 넣은 사용자 DLC의 글자 id(꺼 둔 것 포함 — 판정 R34 D).
  final List<String> moved;

  /// 옛 저장소를 그대로 둔 까닭(사용자 DLC를 옮기지 못함 — 판정 R34) — null이면 해당 없음.
  final String? kept;

  /// 놓은 뒤에도 알릴 것(옮긴 DLC · 바탕이 달라 넣지 않은 DLC …).
  final String? note;
}

/// 새 시드에 옛 저장소의 DLC를 넣은 끝([SeedCarry.carryInto]) — 실패면 엔진의 까닭([error])과 기계용 `code`(계약 2-7-1). 성공이어도 새 판 자료가
/// 받지 않아 빼고 넣은 DLC가 있을 수 있다([rejected] — 판정 R59).
class SeedCarryAnswer {
  const SeedCarryAnswer.ok({this.rejected = const []}) : error = null, code = null, removing = false;
  const SeedCarryAnswer.failed(String this.error, {this.code, this.removing = false}) : rejected = const [];
  final String? error, code;

  /// 멈춘 걸음이 꺼 둔 DLC를 새 시드에서 다시 끄기(`remove_pack`)였는가 — 알림이 '빼지 않았습니다'.
  final bool removing;

  /// 새 판 자료가 받지 않아(같은 항목이 두 트랙 · 배치 거절 … — DLC 탓) 빼고 넣은 DLC — 나머지는 넣었다.
  final List<SeedCarryReject> rejected;
  bool get ok => error == null;
}

/// 새 판 자료가 받지 않은 DLC 하나 — 글자 id와 엔진의 까닭 · `code`.
class SeedCarryReject {
  const SeedCarryReject(this.id, this.error, {this.code});
  final String id, error;
  final String? code;
}

/// 새 시드에 넣을 것 한 덩이 — 옛 저장소에서 꺼낼 id들(`from_store` + `ids`) 또는 DLC 폴더의 파일 하나(원본 없이 든 DLC — `files` · 그 DLC의 [fileId]).
class SeedCarryAdd {
  const SeedCarryAdd.ids(this.ids) : file = null, fileId = '';
  const SeedCarryAdd.file(String this.file, {this.fileId = ''}) : ids = const [];
  final List<String> ids;
  final String? file;
  final String fileId;
}

/// 시드 잇기가 '그 DLC 탓'으로 보고 그 DLC만 빼고 나머지를 넣는 거절 code(판정 R63-1 — 엔진 `packs.rs` · `patch.rs`의 `refuse` 가운데 DLC 하나의 잘못):
/// 같은 항목이 두 트랙(`dup_uid`) · 연표에 배치하지 못함(`layout`) · 날짜가 달력 범위 밖(`range` — 판정 R62). **그 밖은 모두 멈춘다** — code 없는 실패는
/// 디스크 가득 · 열기 실패 · 패닉 같은 환경 탓이라 그 DLC를 빼고 새 판을 놓으면 사용자 DLC가 사라지고, 저장소 쪽 거절(달력 표 없음 · 바탕이 다름)은
/// 빼도 소용없다.
/// 옛 저장소에 든 그 DLC의 원본을 읽지 못함(`broken` — 갈래 1 · 판정 R68-1)도 그 DLC 탓이다.
const seedCarryDlcFaults = {'dup_uid', 'layout', 'range', 'broken'};

/// code 없는 실패(환경 탓)를 같은 시드 판에서 다시 해 보는 수(판정 R68-2) — 이만큼 멈추면 그 판에서는 옛 저장소로 계속 쓴다.
const seedCarryTries = 3;

/// 시드 잇기의 넣기 차례(판정 R34 D · R59 — [_carryWithEngine]이 따로 된 일꾼에서 자료 처리부로 부른다 · [call]은 요청 하나의 답):
/// [adds]를 차례로 `add_pack`(옛 저장소 `from_store` + `ids` · DLC 폴더의 `files`) → 꺼 둔 DLC([keep])마다 `remove_pack delete:false`.
/// 요청마다 쓸 파일(`path` = 새 시드 — 갈래 1의 선택 칸: 엔진이 열린 저장소 대신 그 파일에 쓰는지 본다 · 없는 엔진은 무시)을 싣는다(M-4).
/// 덩이가 DLC 탓 code([seedCarryDlcFaults])로 거절되면 id 하나씩 다시 해 보고 받지 않는 DLC만 [SeedCarryAnswer.rejected]에 적고 나머지를 넣는다 —
/// 하나 때문에 판마다 옛 저장소에 묶이지 않게(표 없는 옛 저장소에서는 그 DLC를 뺄 수도 없다). 받지 않은 DLC는 다시 끄지도 않는다. 그 밖의 거절 ·
/// code 없는 실패 · `committed`나 끄기 실패는 거기서 멈춘다(부르는 쪽이 새 시드 파일을 버리고 옛 저장소 그대로 — 판정 R63-1).
SeedCarryAnswer seedCarrySteps({
  required String seed,
  required String from,
  required List<SeedCarryAdd> adds,
  required List<String> keep,
  required Map<String, dynamic> Function(Map<String, dynamic> request) call,
}) {
  String? codeOf(Map<String, dynamic> a) => a['code'] is String ? a['code'] as String : null;
  SeedCarryAnswer? halt(Map<String, dynamic> a) =>
      a['committed'] == true || !seedCarryDlcFaults.contains(codeOf(a)) ? SeedCarryAnswer.failed('${a['error'] ?? '새 판 자료에 넣지 못했습니다'}', code: codeOf(a)) : null;
  final rejected = <SeedCarryReject>[];
  for (final add in adds) {
    final file = add.file;
    final answer = call(file != null ? {'op': 'add_pack', 'files': [file], 'path': seed} : {'op': 'add_pack', 'from_store': from, 'ids': add.ids, 'path': seed});
    if (answer['ok'] == true) continue;
    final stop = halt(answer);
    if (stop != null) return stop;
    if (file != null || add.ids.length == 1) {
      rejected.add(SeedCarryReject(file != null ? add.fileId : add.ids.single, '${answer['error'] ?? ''}', code: codeOf(answer)));
      continue;
    }
    // 덩이 가운데 어느 DLC인지 — 하나씩 다시(거절된 요청은 새 시드를 바꾸지 않았다 — 한 거래).
    for (final id in add.ids) {
      final one = call({'op': 'add_pack', 'from_store': from, 'ids': [id], 'path': seed});
      if (one['ok'] == true) continue;
      final stopOne = halt(one);
      if (stopOne != null) return stopOne;
      rejected.add(SeedCarryReject(id, '${one['error'] ?? ''}', code: codeOf(one)));
    }
  }
  final gone = {for (final r in rejected) r.id};
  for (final id in keep) {
    if (gone.contains(id)) continue;
    final answer = call({'op': 'remove_pack', 'id': id, 'delete': false, 'path': seed});
    if (answer['ok'] != true) return SeedCarryAnswer.failed('${answer['error'] ?? '새 판 자료에서 끄지 못했습니다'}', code: codeOf(answer), removing: true);
  }
  return SeedCarryAnswer.ok(rejected: rejected);
}

class SeedCarry {
  /// [listPacks]가 없으면(목록을 읽을 길 없음) 잇지 않고 예전처럼 덮어쓴다. [carryInto]가 없으면 옮길 길이 없어 사용자 DLC가 있으면 옛 저장소를 지킨다.
  SeedCarry({this.listPacks, this.listKept, this.packOut, this.carryInto, this.names, this.baseKey = 'east-asia-base'});

  /// 컴퓨터(엔진 도구 `archive-tool`이 있는 곳)의 길 — 목록 · 보관함은 `query <저장소> {"op":"info"}` · `{"op":"kept_packs"}`, 바탕이 다를 때 꺼내 두기는
  /// `pack-out`, 새 시드에 넣기는 자료 처리부([library] — FFI · 앱이 엔진을 열기 전).
  factory SeedCarry.withTool(String tool, {String? library}) => SeedCarry(
    listKept: (db) async {
      try {
        final run = await Process.run(tool, ['query', db, '{"op":"kept_packs"}'], stdoutEncoding: utf8, stderrEncoding: utf8);
        if (run.exitCode != 0) return null;
        final lines = const LineSplitter().convert(run.stdout as String).where((l) => l.trim().isNotEmpty).toList();
        return lines.isEmpty ? null : packsOfKept(jsonDecode(lines.last));
      } catch (_) {
        return null;
      }
    },
    carryInto: library == null ? null : ({required seed, required from, required adds, required keep}) => _carryWithEngine(library, seed: seed, from: from, adds: adds, keep: keep),
    listPacks: (db) async {
      try {
        final run = await Process.run(tool, ['query', db, '{"op":"info"}'], stdoutEncoding: utf8, stderrEncoding: utf8);
        if (run.exitCode != 0) return null;
        final lines = const LineSplitter().convert(run.stdout as String).where((l) => l.trim().isNotEmpty).toList();
        return lines.isEmpty ? null : packsOfInfo(jsonDecode(lines.last));
      } catch (_) {
        return null;
      }
    },
    packOut: (db, id, file) => archiveToolPackOut(tool, db, id, file),
    names: (db) async {
      final run = await Process.run(tool, ['query', db, '{"op":"layout"}'], stdoutEncoding: utf8, stderrEncoding: utf8);
      if (run.exitCode != 0) return const {};
      final lines = const LineSplitter().convert(run.stdout as String).where((l) => l.trim().isNotEmpty).toList();
      final answer = lines.isEmpty ? null : jsonDecode(lines.last);
      final body = answer is Map && answer['data'] is Map ? answer['data'] as Map : answer;
      final packs = body is Map ? body['packs'] : null;
      return {
        if (packs is List)
          for (final pk in packs)
            if (pk is Map && '${pk['key'] ?? ''}'.isNotEmpty && '${pk['name'] ?? ''}'.isNotEmpty) '${pk['key']}': '${pk['name']}',
      };
    },
  );

  /// 휴대폰의 길(판정 R34 D) — 자료 처리부(FFI · [library])로 저장소를 잠깐 열어 목록 · 보관함 · 이름을 읽고(앱이 엔진을 열기 전), 새 시드에도 그것으로
  /// 넣는다([carryInto]). 파일로 꺼내지는 않는다([packOut] 없음).
  factory SeedCarry.withEngine(String library) => SeedCarry(
    listPacks: (db) async {
      final answers = await _askStoreBeforeEngineOpens(library, db, const []);
      return answers.first['ok'] == true ? packsOfInfo(answers.first) : null;
    },
    listKept: (db) async {
      final answers = await _askStoreBeforeEngineOpens(library, db, const [{'op': 'kept_packs'}]);
      return answers.length > 1 && answers[1]['ok'] == true ? packsOfKept(answers[1]) : null;
    },
    carryInto: ({required seed, required from, required adds, required keep}) => _carryWithEngine(library, seed: seed, from: from, adds: adds, keep: keep),
    names: (db) async {
      final answers = await _askStoreBeforeEngineOpens(library, db, const [{'op': 'layout'}]);
      final body = answers.length > 1 && answers[1]['ok'] == true ? answers[1]['data'] : null;
      final packs = body is Map ? body['packs'] : null;
      return {
        if (packs is List)
          for (final pk in packs)
            if (pk is Map && '${pk['key'] ?? ''}'.isNotEmpty && '${pk['name'] ?? ''}'.isNotEmpty) '${pk['key']}': '${pk['name']}',
      };
    },
  );

  /// 저장소의 DLC(첫째 = 기본팩). 읽지 못하면 null.
  final Future<List<SeedPack>?> Function(String db)? listPacks;

  /// 저장소의 보관함(꺼 둔 DLC의 원본 — `{"op":"kept_packs"}` · 계약 2-7-1). 읽지 못하면 null(꺼 둔 DLC는 옮기지 못한다 — 빈 것으로 본다).
  final Future<List<SeedPack>?> Function(String db)? listKept;

  /// 저장소의 DLC 원본을 파일로 꺼낸다(컴퓨터 — 바탕이 다른 새 시드일 때 `DLC/다른-바탕/`에 꺼내 둔다). 참이면 꺼냈다.
  final Future<bool> Function(String db, String id, String file)? packOut;

  /// 새 시드 파일([seed])에 옛 저장소([from])의 DLC를 넣는다 — [adds]를 차례로(`add_pack`) 넣은 뒤 꺼 둔 DLC([keep])는 `remove_pack delete:false`로 보관함에.
  /// 하나라도 실패하면 그 까닭(새 시드 파일은 반쯤 바뀌었을 수 있다 — 부르는 쪽이 버린다).
  final Future<SeedCarryAnswer> Function({required String seed, required String from, required List<SeedCarryAdd> adds, required List<String> keep})? carryInto;

  /// 저장소의 DLC 이름(글자 id → 이름 — 알림에 쓴다). 없거나 실패하면 글자 id로 적는다.
  final Future<Map<String, String>> Function(String db)? names;

  /// 동아시아 기본팩의 글자 id — 옛 저장소의 **첫째**가 이것이면(옛 시드의 바탕) 시드의 바탕이 달라도 사용자 DLC로 치지 않는다. 첫째가 아니면(등불 바탕
  /// 저장소에 사용자가 넣은 동아시아 DLC) 사용자 DLC다(판정 R60 I-1).
  final String baseKey;

  /// `{"op":"info"}`의 답(겉 `data`가 있든 없든)에서 `meta.pack_info`를 번호 차례로 읽는다(`add-dlc.mjs`의 packList와 같다).
  /// 답을 읽지 못하면 null, 목록은 읽었는데 `pack_info`가 없으면(아주 옛 저장소 — DLC를 모름) 빈 목록.
  static List<SeedPack>? packsOfInfo(Object? answer) {
    if (answer is! Map) return null;
    final meta = (answer['meta'] ?? (answer['data'] is Map ? (answer['data'] as Map)['meta'] : null));
    if (meta is! Map) return null;
    var info = meta['pack_info'];
    if (info == null || info == '') return const [];
    if (info is String) {
      try {
        info = jsonDecode(info);
      } catch (_) {
        return null;
      }
    }
    if (info is! Map) return null;
    final numbers = [for (final k in info.keys) int.tryParse('$k')].whereType<int>().toList()..sort();
    bool off(Object? v) => v == false || v == 0 || v == '0' || v == 'false';
    return [
      for (final n in numbers)
        if (info['$n'] is Map) SeedPack('${(info['$n'] as Map)['id'] ?? ''}', '${(info['$n'] as Map)['version'] ?? ''}', original: !off((info['$n'] as Map)['original'])),
    ];
  }

  /// `{"op":"kept_packs"}`의 답(겉 `data`가 있든 없든 — `[{id, name, version, bytes}]`)을 읽는다. 읽지 못하면 null.
  static List<SeedPack>? packsOfKept(Object? answer) {
    final list = answer is Map ? answer['data'] : answer;
    if (list is! List) return null;
    return [
      for (final p in list)
        if (p is Map && '${p['id'] ?? ''}'.isNotEmpty) SeedPack('${p['id']}', '${p['version'] ?? ''}'),
    ];
  }

  /// 옛 저장소의 사용자 DLC — 바탕 말고, 새 시드에 없는 id이거나 새 시드의 것보다 판이 높은 것. 바탕 = 새 시드의 첫째와, 옛 저장소의 첫째가 동아시아
  /// 기본팩([baseKey] — 옛 시드의 바탕)이면 그것. 옛 저장소의 첫째를 늘 바탕으로 가정하지는 않는다(컴퓨터는 옛 판에서 기본팩을 뺄 수 있었다 — 그 저장소는
  /// 첫째가 사용자 DLC다 · 휴대폰은 [phoneUserPacks]가 옛 첫째를 뺀다). 동아시아 id라도 첫째가 아니면 사용자 DLC다(판정 R60 I-1 — 등불 바탕 저장소(판타지
  /// APK)에 넣은 동아시아 DLC가 판 올림에 말없이 사라지지 않게).
  static List<SeedPack> userPacks(List<SeedPack> old, List<SeedPack> seed, {String baseKey = 'east-asia-base'}) {
    final given = {for (final p in seed) p.id: p.version};
    final bases = {if (seed.isNotEmpty) seed.first.id, if (old.isNotEmpty && old.first.id == baseKey) baseKey};
    return [
      for (final p in old)
        if (p.id.isNotEmpty && !bases.contains(p.id) && (!given.containsKey(p.id) || compareDlcVersion(p.version, given[p.id]!) > 0)) p,
    ];
  }

  /// 휴대폰의 사용자 DLC(판정 R34 A · 8 검토 2회차 Important 1) — [userPacks]에서 더 뺀다: 옛 저장소의 바탕(첫 팩 — 휴대폰은 저장소에서 DLC를 뺄 수 없어
  /// 첫 팩은 늘 그 시드의 바탕이다)과, 옛 시드에 든 그대로인 팩([seeded] — 시드를 놓을 때 적어 둔 글자 id → 판 · 판이 그대로일 때만 — 사용자가 판을
  /// 올렸으면 지킨다). 새 시드와만 견주면 시드의 바탕이 바뀌거나(등불 → 동아시아) 옛 시드의 팩을 새 시드가 뺄 때 휴대폰이 옛 저장소에 영영 묶인다.
  /// [seeded]가 없는 옛 휴대폰(적기 전에 놓은 시드)은 바탕만 뺀다.
  static List<SeedPack> phoneUserPacks(List<SeedPack> old, List<SeedPack> seed, {Map<String, String> seeded = const {}, String baseKey = 'east-asia-base'}) => [
    for (final p in userPacks(old, seed, baseKey: baseKey))
      if (p.id != old.first.id && seeded[p.id] != p.version) p,
  ];

  /// 놓은 시드의 팩(`<저장소>.seed-packs` — `{"version":1,"packs":[{"id","version"}…]}` · 원자적). 없거나 읽지 못하면 빈 표.
  static Map<String, String> seededPacks(String path) {
    try {
      final f = File('$path.seed-packs');
      if (!f.existsSync()) return const {};
      final raw = jsonDecode(f.readAsStringSync());
      final packs = raw is Map ? raw['packs'] : null;
      return {
        if (packs is List)
          for (final p in packs)
            if (p is Map && '${p['id'] ?? ''}'.isNotEmpty) '${p['id']}': '${p['version'] ?? ''}',
      };
    } catch (_) {
      return const {};
    }
  }

  /// 놓은 시드의 팩을 적는다([packs]가 null이면 — 읽지 못함 — 옛 기록을 지운다: 낡은 기록이 사용자 DLC를 시드 것으로 잘못 빼지 않게). 실패는 조용히.
  static void _rememberSeeded(String path, List<SeedPack>? packs) {
    try {
      final f = File('$path.seed-packs');
      if (packs == null) {
        if (f.existsSync()) f.deleteSync();
        return;
      }
      writeFileAtomic(f, '${jsonEncode({'version': 1, 'packs': [for (final p in packs) {'id': p.id, 'version': p.version}]})}\n');
    } catch (_) {}
  }

  /// 새 시드([seed] — 바이트를 늦게 읽는다)를 [path]에 놓는다. 표식(`<path>.seed`)이 [stamp]와 같으면 아무것도 하지 않는다 — 위 머리말의 차례.
  /// [progress]: 넣어 둔 DLC를 옮기거나 꺼내 두는 동안의 진행 말(앱 틀이 첫 화면의 준비 말에 적는다 — 판 올림 뒤 첫 실행은 DLC 크기만큼 오래 걸릴 수
  /// 있어 무엇을 하는지 보인다 · 판정 R60 M-12). 옮길 것이 없으면 부르지 않는다.
  Future<SeedCarryResult> place({required String path, required String stamp, required Future<List<int>> Function() seed, void Function(String line)? progress}) async {
    final sep = Platform.pathSeparator;
    final live = File(path), mark = File('$path.seed'), keptMark = File(seedKeptPath(path));
    // 바꿔 놓다 멈춘 자리(옛 저장소는 `.이전-시드`로 비켰는데 새 시드를 놓기 전에 죽음 — [_swap]): 옛 저장소를 되돌린 뒤 이어 간다(고침 1회차 Minor —
    // 저장소가 없다고 보고 빈 새 시드를 놓아 넣어 둔 DLC를 잃지 않게).
    if (!live.existsSync() && File('$path.이전-시드').existsSync()) await _moveTails('$path.이전-시드', path);
    if (live.existsSync() && mark.existsSync() && await mark.readAsString() == stamp) return const SeedCarryResult();
    final list = listPacks;
    await live.parent.create(recursive: true);
    if (!live.existsSync() || list == null) {
      // 처음이거나 목록을 읽을 길도 없다 — 예전처럼 놓는다(놓은 시드의 팩은 읽을 수 있으면 적어 둔다 — 다음 판의 사용자 DLC 가리기).
      final bytes = await seed();
      await _drop(path);
      await live.writeAsBytes(bytes, flush: true);
      await mark.writeAsString(stamp);
      await _forgetKept(path);
      _rememberSeeded(path, list == null ? null : await list(path));
      return const SeedCarryResult(placed: true);
    }
    // 휴대폰(파일로 꺼낼 길 없음): 이 판은 이미 지킴으로 정했다(실행마다 다시 해 보거나 알리지 않는다).
    final phone = packOut == null;
    if (phone && keptMark.existsSync() && await keptMark.readAsString() == stamp) return const SeedCarryResult();
    // code 없는 실패(환경 탓)를 이 판에서 [seedCarryTries]번 겪었다 — 이 판에서는 더 해 보지 않고 옛 저장소로 계속 쓴다(판정 R68-2 · 다음 앱 판에서 다시).
    if (_tries(path, stamp) >= seedCarryTries) return const SeedCarryResult();
    // 옛 저장소의 목록을 먼저 — 읽지 못하면 컴퓨터는 시드를 읽거나 쓰지도 않는다(실행마다 시드를 다시 쓰지 않게) · 휴대폰은 옛 파일을 옆에 두고 놓는다.
    final old = await list(path);
    if (old == null) {
      if (phone) return _placeOverUnreadable(path: path, stamp: stamp, seed: seed, list: list);
      return const SeedCarryResult(kept: '앱의 새 판 자료로 바꾸지 않았습니다 — 지금 저장소의 DLC 목록을 읽지 못해 넣어 둔 DLC를 옮길 수 없습니다.');
    }
    final fresh = File('$path.새-시드');
    try {
      await _drop(fresh.path);
      await fresh.writeAsBytes(await seed(), flush: true);
      final given = await list(fresh.path);
      if (given == null) {
        return SeedCarryResult(
          kept: '앱의 새 판 자료로 바꾸지 않았습니다 — 새 판 자료의 DLC 목록을 읽지 못해 넣어 둔 DLC를 ${phone ? '지킬 수 있는지 알 수 없습니다' : '옮길 수 없습니다'}.',
        );
      }
      final user = phone ? phoneUserPacks(old, given, seeded: seededPacks(path), baseKey: baseKey) : userPacks(old, given, baseKey: baseKey);
      // 꺼 둔 DLC(보관함 — 계약 2-7-1). 새 시드의 바탕(첫째)은 끌 수 없는 자리라 옮기지 않는다(다시 끄면 엔진이 거절해 잇기가 멈춘다 — 판정 R59) ·
      // 꺼 둔 동아시아 DLC(등불 바탕 저장소)는 옮긴다(판정 R60 I-1). 사용자가 꺼 둔 채 지운 DLC(묘비 `DLC/sync.json`의 removed)도 옮기지 않는다
      // (고침 1회차 Minor) — 지금 앱은 꺼 둔 채 지우면 보관함의 원본까지 버리지만(`remove_pack delete:true` — 판정 R42), 그 전의 앱이 지운 것은 보관함에
      // 원본이 남아 있다.
      final gone = DlcFolderState.read(path)?.removed ?? const <String>{};
      final off = [
        for (final p in await _keptOf(path))
          if ((given.isEmpty || p.id != given.first.id) && !gone.contains(p.id)) p,
      ];
      // 이름은 옛 저장소에서(바꿔 놓기 전에) 알림에 쓸 때만 한 번 읽는다.
      Map<String, String>? named;
      Future<String> which(Iterable<String> ids) async {
        if (named == null) {
          try {
            named = await names?.call(path) ?? const {};
          } catch (_) {
            named = const {};
          }
        }
        return [for (final id in ids) '«${named![id] ?? id}»'].join(' · ');
      }

      if (user.isEmpty && off.isEmpty) {
        await _swap(path, fresh);
        await mark.writeAsString(stamp);
        await _forgetKept(path);
        _rememberSeeded(path, given);
        if (old.isEmpty && !phone) {
          return const SeedCarryResult(placed: true, note: '지금 저장소에 DLC 목록이 없어(아주 옛 저장소) 넣어 두었던 DLC를 가리지 못한 채 앱의 새 판 자료로 바꾸었습니다 — '
              'DLC 폴더에 있는 DLC는 앱이 열 때 다시 넣습니다.');
        }
        return const SeedCarryResult(placed: true);
      }
      final sameBase = old.isNotEmpty && given.isNotEmpty && old.first.id == given.first.id;
      final out = packOut;
      if (out != null && !sameBase && user.isNotEmpty) {
        // 컴퓨터: 바탕이 다르면 넣지 않고 원본을 DLC 폴더 안의 다른-바탕/에 꺼내 둔다(DLC 폴더 바로 아래가 아니라 — 연 뒤 다시 들이기(R32)가 넣지 않게).
        progress?.call('넣어 둔 DLC의 원본을 DLC 폴더에 꺼내 두는 중…');
        final home = Directory('${live.parent.path}${sep}DLC$sep다른-바탕');
        for (final p in user) {
          final name = '${p.id.replaceAll(RegExp(r'[^\w.-]'), '_')}-v${p.version.isEmpty ? '0' : p.version}.htpack';
          final file = '${home.path}$sep$name';
          if (File(file).existsSync()) continue;
          await home.create(recursive: true);
          if (!await out(path, p.id, file)) {
            return SeedCarryResult(kept: '앱의 새 판 자료로 바꾸지 않았습니다 — 넣어 둔 DLC ${await which([p.id])}의 원본을 꺼내지 못해 지금 저장소를 그대로 둡니다.');
          }
        }
        final listed = await which(user.map((p) => p.id));
        await _swap(path, fresh);
        await mark.writeAsString(stamp);
        _rememberSeeded(path, given);
        // 저장소 옆 DLC 폴더 바로 아래에도 같은 DLC의 파일이 있을 수 있다(고쳐 쓰기가 폴더를 저장소와 맞춰 둔다) — 끈 묘비로 다시 들이지 않게.
        try {
          DlcFolderState.update(path, (s) => s.copyWith(off: {...s.off, for (final p in user) p.id}));
        } catch (_) {}
        return SeedCarryResult(placed: true, note: '앱의 새 판 자료는 바탕(기본팩)이 달라 넣어 두었던 DLC $listed을(를) 다시 넣지 않았습니다 — 원본은 ${home.path}에 있습니다.');
      }
      // 넣을 것: 저장소에 원본이 든 DLC는 옛 저장소에서(`from_store` + `ids` — 옛 차례대로 한 덩이씩), 원본 없이 든 DLC는 DLC 폴더의 그 파일(`files`).
      // 꺼 둔 DLC는 새 시드에 같거나 높은 판이 들었으면 그것을 끄고, 아니면 옛 보관함에서 꺼내 넣은 뒤 끈다.
      final adds = <SeedCarryAdd>[];
      final missing = <SeedPack>[];
      var group = <String>[];
      for (final p in user) {
        if (p.original) {
          group.add(p.id);
          continue;
        }
        final local = _folderOriginal(path, p);
        if (local == null) {
          missing.add(p);
          continue;
        }
        if (group.isNotEmpty) adds.add(SeedCarryAdd.ids(group));
        group = [];
        adds.add(SeedCarryAdd.file(local, fileId: p.id));
      }
      for (final p in off) {
        final seeded = given.where((g) => g.id == p.id).firstOrNull;
        if (seeded == null || compareDlcVersion(p.version, seeded.version) > 0) group.add(p.id);
      }
      if (group.isNotEmpty) adds.add(SeedCarryAdd.ids(group));
      final carry = carryInto;
      if (missing.isNotEmpty || carry == null) {
        if (phone) await keptMark.writeAsString(stamp);
        final lost = missing.isNotEmpty ? missing : user;
        final why = missing.isNotEmpty
            ? '원본(.htpack)이 저장소에도 DLC 폴더에도 없어(예전 메이커 배치로만 든 것) 옮길 수 없습니다 — '
                  "${phone ? "그 DLC의 .htpack을 '파일에서 더하기'로 골라 주세요(앱이 DLC 폴더에 두었다가 다시 켤 때 새 판 자료로 함께 옮깁니다)" : "그 DLC의 .htpack을 '파일에서 더하기'로 고르거나 ${missing.map(_fileName).join(' · ')} 이름으로 저장소 옆 DLC 폴더에 두면 다음에 켤 때 옮깁니다"}"
            : '옮길 길이 없습니다';
        return SeedCarryResult(kept: '앱의 새 판 자료로 바꾸지 않았습니다 — 넣어 둔 DLC ${await which(lost.map((p) => p.id))}는 $why${phone ? _phoneTail : ''}.');
      }
      final moved = [...user.map((p) => p.id), ...off.map((p) => p.id)];
      progress?.call('넣어 둔 DLC를 앱의 새 판 자료로 옮기는 중…');
      final answer = await carry(seed: fresh.path, from: path, adds: adds, keep: [for (final p in off) p.id]);
      if (!answer.ok) {
        // code 없는 실패(디스크 가득 · 열기 실패 · 패닉 · 다시 열기 실패 — 환경 탓)는 다음에 켤 때 다시 해 본다(휴대폰도 지킴 표식을 적지 않음 · 판정 R63-1).
        // code가 있는 거절(저장소 쪽 · 새 판 자료의 사정)은 같은 판에서 되풀이해도 같으니 휴대폰은 그 판을 지킴으로 정한다. 다만 `path`(앱이 연 저장소가
        // 그새 바뀜)는 그때의 사정이라 code 없는 실패와 같이 다시 해 본다(판정 R72-2).
        final retry = answer.code == null || answer.code == 'path';
        if (phone && !retry) await keptMark.writeAsString(stamp);
        // code 없는 실패는 같은 판에서 [seedCarryTries]번까지 — 그 뒤에는 이 판에서 더 해 보지 않고 옛 저장소로 계속 쓴다(DLC를 빼고 놓지 않는다 — 환경 탓일 수
        // 있어 사용자 DLC를 잃지 않는 쪽 · 판정 R68-2).
        final tries = retry ? _countTry(path, stamp) : 0;
        // 새 판 자료에 달력 표가 없으면(그 판이 표 없이 지어짐) '앱을 새 판으로 올리면…'(옛 저장소 쪽 풀이)은 맞지 않아 따로 말한다(고침 1회차 Minor) —
        // 엔진의 글도 '(자세히: …)'로(② Minor 1).
        final why = answer.code == 'calendar'
            ? '이 판의 앱에 든 기본 자료에 달력 표가 없어 옮길 수 없습니다 — 다음 판을 기다려 주세요'
                  '${answer.error!.trim().isEmpty ? '' : ' (자세히: ${dlcPlainEngineError(answer.error!)})'}'
            : dlcRefusalText(answer.code, answer.error!, removing: answer.removing);
        if (retry && tries >= seedCarryTries) {
          return SeedCarryResult(
            kept: '넣어 둔 DLC ${await which(moved)}를 새 판으로 옮기지 못했습니다 — 지금 자료로 계속 씁니다 · 다음 앱 판에서 다시 해 봅니다'
                '(같은 까닭으로 $seedCarryTries번 멈췄습니다: $why)',
          );
        }
        return SeedCarryResult(
          kept: '앱의 새 판 자료로 바꾸지 않았습니다 — 넣어 둔 DLC ${await which(moved)}를 새 판 자료로 옮기지 못해 지금 저장소를 그대로 둡니다'
              '${retry ? '(다음에 앱을 켤 때 다시 해 봅니다)' : ''}: $why${phone && !retry ? _phoneTail : ''}',
        );
      }
      // 새 판 자료가 받지 않은 DLC(판정 R59 — 같은 항목이 두 트랙 · 배치 거절): 그 원본을 DLC 폴더에 두고(R48처럼 — 사용자가 고쳐 다시 넣게) 나머지로
      // 새 판을 놓는다. 원본을 둘 수 없으면(휴대폰 — 꺼낼 길이 없고 폴더에도 없음) 잃지 않게 옛 저장소 그대로.
      final rejectedNotes = <String>[];
      if (answer.rejected.isNotEmpty) {
        final versions = {for (final p in [...user, ...off]) p.id: p.version};
        for (final r in answer.rejected) {
          final kept = await _keepRejectedOriginal(path, r.id, versions[r.id] ?? '');
          if (kept == null) {
            if (phone) await keptMark.writeAsString(stamp);
            return SeedCarryResult(
              kept: '앱의 새 판 자료로 바꾸지 않았습니다 — 넣어 둔 DLC ${await which([r.id])}는 새 판 자료가 받지 않는데 그 원본을 DLC 폴더에 둘 수 없어 '
                  "지금 저장소를 그대로 둡니다. 받지 않은 까닭: ${dlcRefusalText(r.code, r.error)} 메이커에서 고친 그 DLC의 .htpack을 '파일에서 더하기'로 "
                  '넣어 주세요${phone ? _phoneTail : ''}.',
            );
          }
          // 까닭(엔진 거절 글 · '(자세히: …)')을 괄호 안에 또 싸지 않는다(② 넘김 — 괄호 겹침).
          rejectedNotes.add('${await which([r.id])}은(는) 새 판 자료가 받지 않아 옮기지 못했습니다 — ${dlcRefusalText(r.code, r.error)} 원본은 DLC 폴더의 $kept에 '
              "두었습니다. 메이커에서 고친 뒤 '파일에서 더하기'로 다시 넣어 주세요.");
        }
      }
      final rejectedIds = {for (final r in answer.rejected) r.id};
      final carried = [for (final id in moved) if (!rejectedIds.contains(id)) id];
      final listed = await which(carried);
      await _swap(path, fresh);
      await mark.writeAsString(stamp);
      await _forgetKept(path);
      _rememberSeeded(path, given);
      return SeedCarryResult(
        placed: true,
        moved: carried,
        note: [if (carried.isNotEmpty) '넣어 두었던 DLC $listed을(를) 앱의 새 판 자료로 옮겼습니다.', ...rejectedNotes].join(' '),
      );
    } finally {
      try {
        await _drop(fresh.path);
      } catch (_) {}
    }
  }

  /// 휴대폰 알림의 꼬리 — 지킴의 값(새 기본 자료가 지금 필요하면).
  static const _phoneTail = '(새 기본 자료가 지금 필요하면 앱 정보에서 앱 자료를 지우면 됩니다 — 넣은 DLC는 사라집니다)';

  /// 원본 없이 든 DLC를 DLC 폴더에 둘 이름(`<id>-v<판>.htpack` — 메이커의 파일 이름).
  static String _fileName(SeedPack p) => dlcOriginalFileName(p.id, p.version);

  /// 원본 없이 든 DLC [p]의 원본 — 저장소 옆 DLC 폴더의 파일 가운데 글자 id · 판이 같은 것([_fileName]을 먼저 · 저장소가 판을 모르면 id만). 없으면 null.
  /// 앱이 '파일에서 더하기'로 고른 그 .htpack을 넣지 못했을 때 여기에 둔다(`DlcJob._stashOriginals` — 계획 P4 과제 11c).
  static String? _folderOriginal(String path, SeedPack p) {
    final dir = Directory('${File(path).parent.path}${Platform.pathSeparator}DLC');
    if (!dir.existsSync()) return null;
    final named = File('${dir.path}${Platform.pathSeparator}${_fileName(p)}');
    final files = [
      if (named.existsSync()) named.path,
      for (final f in dir.listSync(followLinks: false))
        if (f is File && f.path.toLowerCase().endsWith('.htpack') && f.path != named.path) f.path,
    ];
    for (final file in files) {
      final head = readDlcFileHead(file).head;
      if (head != null && head.id == p.id && (p.version.isEmpty || compareDlcVersion(head.version, p.version) == 0)) return File(file).absolute.path;
    }
    return null;
  }

  /// 새 판 자료가 받지 않은 DLC [id]의 원본을 DLC 폴더에 둔다(판정 R59 — R48처럼 `<id>-v<판>.htpack`): 그 id · 판의 파일이 이미 폴더에 있으면(앱이 넣을 때
  /// 둔 것 · 꺼 둔 DLC의 파일) 그것, 없으면 옛 저장소에서 꺼내 둔다(컴퓨터 — [packOut]). 둔(있는) 파일 이름, 둘 수 없으면 null.
  Future<String?> _keepRejectedOriginal(String path, String id, String version) async {
    final there = _folderOriginal(path, SeedPack(id, version));
    if (there != null) return there.split(RegExp(r'[\\/]')).last;
    final out = packOut;
    if (out == null) return null;
    final sep = Platform.pathSeparator;
    final dir = Directory('${File(path).parent.path}${sep}DLC');
    final name = dlcOriginalFileName(id, version);
    try {
      await dir.create(recursive: true);
      return await out(path, id, '${dir.path}$sep$name') ? name : null;
    } catch (_) {
      return null;
    }
  }

  /// 옛 저장소의 보관함 — 읽을 길이 없거나 읽지 못하면 빈 목록.
  Future<List<SeedPack>> _keptOf(String path) async {
    try {
      return await listKept?.call(path) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 휴대폰에서 옛 저장소를 읽지 못할 때(깨짐 · 열기 실패): 새 시드를 놓되 옛 파일은 지우지 않고 옆에 둔다(되찾을 길).
  Future<SeedCarryResult> _placeOverUnreadable({required String path, required String stamp, required Future<List<int>> Function() seed, required Future<List<SeedPack>?> Function(String db) list}) async {
    final mark = File('$path.seed');
    final bytes = await seed();
    final aside = await _setAside(path);
    try {
      await File(path).writeAsBytes(bytes, flush: true);
    } catch (_) {
      // 놓지 못했다 — 비킨 옛 파일을 제자리로(다음 실행에서 다시 해 본다).
      try {
        if (File(path).existsSync()) await File(path).delete();
      } catch (_) {}
      await _moveTails('${File(path).parent.path}${Platform.pathSeparator}$aside', path);
      rethrow;
    }
    await mark.writeAsString(stamp);
    await _forgetKept(path);
    _rememberSeeded(path, await list(path));
    // DLC 원본이 DLC 폴더에 있을 때만 그곳을 말한다(8 검토 2회차 Minor 3) — 앱 전용 폴더라 파일 앱에서는 보이지 않는다.
    final dlc = Directory('${File(path).parent.path}${Platform.pathSeparator}DLC');
    var originals = false;
    try {
      originals = dlc.existsSync() && dlc.listSync().any((f) => f is File && f.path.toLowerCase().endsWith('.htpack'));
    } catch (_) {}
    return SeedCarryResult(
      placed: true,
      note: '지금 저장소를 읽지 못해 앱의 새 판 자료로 바꾸었습니다 — 옛 저장소는 지우지 않고 앱 전용 자료 폴더에 «$aside»(으)로 두었습니다'
          '(앱 전용 폴더라 파일 앱에서는 보이지 않습니다${originals ? ' · 넣어 두었던 DLC의 원본(.htpack)은 같은 곳의 DLC 폴더에 남아 있습니다' : ''}).',
    );
  }

  /// 읽지 못한 옛 저장소와 그 일지를 `<저장소>.옛-저장소-<시각>`으로 비킨다(지우지 않음 · 도중에 실패하면 되돌리고 던진다). 비킨 저장소 파일의 이름을 돌려준다.
  static Future<String> _setAside(String path) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stem = '$path.옛-저장소-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    // 같은 이름이 이미 있으면(같은 초에 두 번) 뒤에 번호 — 옛 파일을 덮거나 남기지 않게.
    var aside = stem;
    for (var n = 2; File(aside).existsSync(); n++) {
      aside = '$stem-$n';
    }
    try {
      await _moveTails(path, aside);
    } catch (_) {
      await _moveTails(aside, path);
      rethrow;
    }
    return aside.split(RegExp(r'[\\/]')).last;
  }

  /// 저장소 파일과 일지(`-wal` · `-shm` · `-journal`)를 [from] 이름에서 [to] 이름으로 옮긴다(있는 것만).
  static Future<void> _moveTails(String from, String to) async {
    for (final tail in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$from$tail');
      if (f.existsSync() && !File('$to$tail').existsSync()) await f.rename('$to$tail');
    }
  }

  static Future<void> _forgetKept(String path) async {
    for (final f in [File(seedKeptPath(path)), File('$path.seed-tries')]) {
      try {
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  /// 이 시드 판([stamp])에서 code 없는 실패를 겪은 수(`<저장소>.seed-tries` — `{"stamp","count"}` · 판정 R68-2). 다른 판의 기록이거나 없으면 0.
  static int _tries(String path, String stamp) {
    try {
      final raw = jsonDecode(File('$path.seed-tries').readAsStringSync());
      return raw is Map && raw['stamp'] == stamp && raw['count'] is int ? raw['count'] as int : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 한 번 더 셈해 적고 그 수를 돌려준다(실패는 조용히 — 적지 못하면 다음 실행에서 다시 해 본다).
  static int _countTry(String path, String stamp) {
    final count = _tries(path, stamp) + 1;
    try {
      writeFileAtomic(File('$path.seed-tries'), '${jsonEncode({'stamp': stamp, 'count': count})}\n');
    } catch (_) {}
    return count;
  }

  /// 옛 저장소와 그 일지(`-wal` · `-shm` · `-journal`)를 함께 비키고 새 시드를 제자리에 놓는다 — 이름을 바꾼 뒤에 일지를 지우면 그 사이 새 시드에
  /// 옛 일지가 덧대일 수 있어 먼저 비킨다. 놓다가 실패하면 비킨 것을 되돌리고 던진다.
  static Future<void> _swap(String path, File fresh) async {
    const tails = ['', '-wal', '-shm', '-journal'];
    final aside = '$path.이전-시드';
    for (final tail in tails) {
      final f = File('$aside$tail');
      if (f.existsSync()) await f.delete();
    }
    final moved = <String>[];
    try {
      for (final tail in tails) {
        final f = File('$path$tail');
        if (!f.existsSync()) continue;
        await f.rename('$aside$tail');
        moved.add(tail);
      }
      await fresh.rename(path);
    } catch (_) {
      for (final tail in moved.reversed) {
        try {
          await File('$aside$tail').rename('$path$tail');
        } catch (_) {}
      }
      rethrow;
    }
    for (final tail in moved) {
      try {
        await File('$aside$tail').delete();
      } catch (_) {}
    }
  }

  static Future<void> _drop(String path) async {
    for (final tail in const ['', '-wal', '-shm', '-journal']) {
      final old = File('$path$tail');
      if (old.existsSync()) await old.delete();
    }
  }
}

/// DLC 폴더의 파일 하나 — 엔진 도구(`archive-tool check-pack`)가 읽은 글자 id · 판 · 이름.
class DlcFolderPack {
  const DlcFolderPack(this.path, this.id, this.version, this.name);
  final String path, id, version, name;
}

/// 저장소를 열 때 다시 들일 DLC 폴더의 파일([add] — 같은 id는 판이 가장 높은 파일 하나 · 파일 이름 차례)과 읽지 못해 건너뛴 파일 이름([broken] —
/// 지문으로 기억한 것은 다시 적지 않는다), 새 폴더 기억([state] — 앱 틀이 `DLC/sync.json`에 적는다), 묘비의 DLC라 이번에 지운 파일 이름([cleaned]),
/// 엔진 도구가 실패해 읽지 못한 파일 이름([toolFailed] — 파일 탓이 아니라 기억하지 않고 다음 열기에서 다시 읽는다 · 판정 R58).
class DlcFolderPlan {
  const DlcFolderPlan({this.add = const [], this.broken = const [], this.state = DlcFolderState.empty, this.cleaned = const [], this.toolFailed = const []});
  final List<DlcFolderPack> add;
  final List<String> broken;
  final DlcFolderState state;
  final List<String> cleaned;
  final List<String> toolFailed;
}

/// 엔진 도구가 DLC 폴더의 파일을 읽지 못한 까닭이 파일이 아니라 도구 쪽(도구가 없음 · 시작하지 못함 · 죽음 · 모르는 명령)일 때
/// [DlcFolderSync.readPack]이 던진다 — 그 파일을 '깨짐'으로 기억하지 않는다(판정 R58: 기억하면 도구가 고쳐져도 그 파일을 영영 다시 들이지 않는다).
class DlcToolFailure implements Exception {
  const DlcToolFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `archive-tool check-pack`이 종료 코드 1과 함께 낸 오류 줄([stderr] — Rust main이 `Error: <까닭>`으로 적는다)이 **그 파일의 형식 문제**인가(판정 R63-2):
/// 엔진(`lib.rs`의 `read_htpack` · `htpack_raw`)이 정해 둔 글(머리 · 크기 · 지문 · 풀린 크기 · DLC 본문 아님)과 본문 JSON 오류(`line: n, column: m`) ·
/// 압축 풀기 오류(`deflate`)만 참. 입출력 오류(`Os { … }` — 파일을 쥠 · 못 찾음 · 결과 못 씀) · 옛 도구의 '사용법' · 빈 줄은 거짓(도구 쪽 — 기억하지 않음).
bool dlcCheckPackBroken(String stderr) {
  final said = stderr.trim();
  if (said.isEmpty || said.contains('Os {') || said.contains('사용법')) return false;
  return dlcCheckPackFormatErrors.any((f) => said.contains('"$f"')) || RegExp(r'line: \d+, column: \d+').hasMatch(said) || said.toLowerCase().contains('deflate');
}

/// 엔진(`lib.rs` `read_htpack` · `htpack_raw`)이 형식 문제로 정해 둔 글 — 검사가 엔진 원본과 대조한다(엔진이 글을 바꾸면 알게 · 고침 2회차 Minor 5).
const dlcCheckPackFormatErrors = ['지원하지 않는 전용 팩 머리', '전용 팩 선언 크기 오류', '전용 팩 지문 오류', '전용 팩 풀린 크기 오류', '전용 팩 크기 오류', 'DLC 본문이 아닙니다', '전용 팩 확장자가 아닙니다'];

/// 판을 올린 뒤 DLC 폴더에서 다시 들인 끝의 알림 한 줄(앱 틀의 `_syncDlcFolder`) — 들인 DLC · 넣지 못한 DLC(파일 탓 [failed] · 그 밖 [retry]) ·
/// 읽지 못한 파일 · 묘비로 지운 남은 파일([DlcFolderPlan.cleaned] — 8 검토: 사용자 폴더에서 파일이 사라진 까닭을 알게). 알릴 것이 없으면 null.
/// 파일 탓이 아닌 거절(code 없음 · 달력 표 없음 · 원본 없이 든 DLC … — [dlcFileFault]가 거짓)은 지문을 적지 않아 다음 열기에서 다시 해 보므로 꼬리 말이 다르다.
String? dlcFolderNotice({
  List<String> added = const [],
  List<String> failed = const [],
  List<String> retry = const [],
  List<String> broken = const [],
  List<String> cleaned = const [],
  List<String> toolFailed = const [],
}) {
  // 문장마다 끊어 적는다 — 넣지 못한 까닭(엔진 거절 글 · '(자세히: …)')을 괄호 안에 또 싸지 않게(② 넘김 — 괄호 겹침).
  final parts = [
    if (added.isNotEmpty) 'DLC 폴더에서 DLC ${added.length}개를 다시 넣었습니다: ${added.join(' · ')}.',
    if (failed.isNotEmpty) '넣지 못해 건너뛰었습니다 — ${failed.join(' · ')}. 그 파일이 바뀌거나 앱 판이 바뀌기 전에는 다시 해 보지 않습니다.',
    if (retry.isNotEmpty) '지금 넣지 못해 건너뛰었습니다 — ${retry.join(' · ')}. 다음에 앱을 열 때 다시 해 봅니다.',
    if (broken.isNotEmpty) 'DLC 폴더의 ${broken.join(' · ')}은(는) DLC 파일로 읽을 수 없어 건너뛰었습니다 — 그 파일이 바뀌거나 앱 판이 바뀌기 전에는 다시 알리지 않습니다.',
    if (toolFailed.isNotEmpty) '엔진 도구(도구 폴더의 archive-tool)가 DLC 폴더의 ${toolFailed.join(' · ')}을(를) 읽지 못했습니다 — 다음에 앱을 열 때 다시 해 봅니다.',
    if (cleaned.isNotEmpty) '뺀 DLC의 남은 파일 ${cleaned.join(' · ')}을(를) DLC 폴더에서 지웠습니다.',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// 판을 올린 뒤(Windows 설치본 · 포터블이 저장소 파일을 새 판의 것으로 통째로 덮음) 저장소에서 빠진 사용자 DLC를 DLC 폴더에서 찾는다(판정 R32).
/// 들일 것 = 폴더의 DLC 파일 가운데 글자 id가 저장소에도 끈 목록에도 폴더 기억의 묘비(뺀 · 끈 DLC — 판정 R33)에도 없고 기본팩도 아닌 것 — 같은 id는
/// 판이 가장 높은 파일 하나. 뺀 DLC는 폴더에서도 지우고(얹힌 몫 2) COMMIT 직후 묘비를 남기므로, 지우기가 실패해도 되살아나지 않고 다음 열기에서
/// 남은 파일을 마저 지운다(다 지우면 묘비를 뺀다). 끈 묘비의 파일은 지우지 않는다(다시 켤 원본). 읽지 못하는 파일(깨진 파일)은 그것만 건너뛰고
/// [DlcFolderPlan.broken]에 적으며, 지문으로 기억해 같은 파일이면 다음부터 읽거나 알리지 않는다.
/// 끈 목록(`hidden.json`)이나 폴더 기억(`sync.json`)이 있는데 읽지 못하면 앱 틀은 들이지 않는다([blocked]).
class DlcFolderSync {
  DlcFolderSync({required this.readPack, Future<bool> Function(String file)? deleteFile}) : deleteFile = deleteFile ?? _delete;

  /// 묘비의 DLC 파일을 지운다. 참이면 지웠다(기본: 진짜 지우기 — 읽기 전용 · 잠긴 파일이면 거짓).
  final Future<bool> Function(String file) deleteFile;

  static Future<bool> _delete(String file) async {
    try {
      await File(file).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 폴더에서 다시 들이면 안 되는 까닭 — 끈 목록이나 폴더 기억이 **있는데** 읽지 못함(그대로 들이면 꺼 둔 · 뺀 DLC가 되살아난다). 없으면 null.
  static String? blocked(String db) {
    if (DlcHidden.unreadable(db)) {
      return 'DLC 폴더의 끈 목록(hidden.json)을 읽지 못해 DLC 폴더에서 DLC를 다시 넣지 않았습니다 — 꺼 둔 DLC가 켜진 채 들 수 있어서입니다. '
          '그 파일을 지우거나 고치면 다음에 앱을 열 때 다시 살핍니다.';
    }
    if (DlcFolderState.read(db) == null) {
      return 'DLC 폴더의 기억(sync.json)을 읽지 못해 DLC 폴더에서 DLC를 다시 넣지 않았습니다 — 뺀 DLC가 되살아날 수 있어서입니다. '
          '그 파일을 지우거나 고치면 다음에 앱을 열 때 다시 살핍니다.';
    }
    return null;
  }

  /// 엔진 도구(`archive-tool check-pack <파일> <결과.json>` — 머리 · 지문 · 내용을 본다)로 읽는다. 결과 파일은 [scratch](앱 틀의 `--memory-dir` 아래 —
  /// 판정 R50 · 없으면 운영체제의 임시 폴더)에 잠깐 쓰고 지운다. 그 파일을 '깨짐'(null)으로 보는 것은 도구가 형식 문제라고 분명히 말할 때뿐이다
  /// ([dlcCheckPackBroken] — 판정 R63-2). 그 밖의 모든 실패(시작 못 함 · 죽음 · 입출력 · 결과 파일 못 씀 · 임시 자리 · 결과를 못 읽음)는 [DlcToolFailure].
  factory DlcFolderSync.withTool(String tool, {Directory? scratch}) => DlcFolderSync(
    readPack: (file) async {
      final dir = scratch ?? Directory.systemTemp;
      final out = File('${dir.path}${Platform.pathSeparator}ht-check-pack-${DateTime.now().microsecondsSinceEpoch}.json');
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final ProcessResult run;
        try {
          run = await Process.run(tool, ['check-pack', file, out.path], stdoutEncoding: utf8, stderrEncoding: utf8);
        } on ProcessException catch (e) {
          throw DlcToolFailure('엔진 도구를 시작하지 못했습니다: ${e.message}');
        }
        // 종료 코드 1 = Rust main의 Err — 형식 문제(그 파일 탓)인지 입출력 · 결과 쓰기 실패(도구 쪽)인지는 오류 줄로 가른다(판정 R63-2).
        if (run.exitCode == 1 && dlcCheckPackBroken('${run.stderr}')) return null;
        if (run.exitCode != 0 || !out.existsSync()) throw DlcToolFailure('엔진 도구가 그 파일을 읽지 못했습니다(종료 코드 ${run.exitCode})');
        final Object? raw;
        try {
          raw = jsonDecode(await out.readAsString());
        } on FormatException {
          throw const DlcToolFailure('엔진 도구의 결과를 읽지 못했습니다');
        }
        if (raw is! Map) throw const DlcToolFailure('엔진 도구의 결과가 DLC 본문이 아닙니다');
        return DlcFolderPack(file, '${raw['id'] ?? ''}', '${raw['version'] ?? ''}', '${raw['name'] ?? raw['id'] ?? ''}');
      } on DlcToolFailure {
        rethrow;
      } catch (e) {
        // 임시 자리를 만들지 못함 · 결과를 읽다 실패 — 그 파일 탓이 아니다(기억하지 않고 다음 열기에서 다시).
        throw DlcToolFailure('엔진 도구로 그 파일을 읽지 못했습니다: ${dlcErrorText(e)}');
      } finally {
        try {
          if (out.existsSync()) out.deleteSync();
        } catch (_) {}
      }
    },
  );

  /// 파일 하나를 읽는다. 파일을 읽지 못하면(깨짐) null · 도구가 실패하면 [DlcToolFailure]를 던진다.
  final Future<DlcFolderPack?> Function(String file) readPack;

  /// [baseKey]: 동아시아 기본팩의 글자 id — 옛 판에서 기본팩을 뺐으면([DlcHidden.baseRemoved]) 그 파일은 들이지 않는다. 그 밖에는 보통 DLC처럼 들인다
  /// (등불 바탕 저장소에 넣은 동아시아 DLC — 판정 R60 I-1 · 저장소의 바탕이면 이미 저장소에 들어 있어 건너뛴다).
  /// [storeVersions]: 저장소에 든 DLC의 판(글자 id → 판) — 폴더의 판이 더 높으면 저장소에 든 DLC도 다시 들인다(판 올림 — 판정 R60 M-5 · 모르면 건너뜀).
  /// [app]: 지금 앱의 판 — 기억한 거절(`skip`)은 같은 지문 · 같은 앱 판일 때만 건너뛴다(판정 R63-3 · 새로 적는 거절에도 이 판).
  Future<DlcFolderPlan> pending({
    required String db,
    required Iterable<String> storeKeys,
    required DlcHidden hidden,
    required String baseKey,
    Map<String, String> storeVersions = const {},
    DlcFolderState state = DlcFolderState.empty,
    String app = dlcAppVersion,
  }) async {
    final sep = Platform.pathSeparator;
    final folder = Directory('${File(db).absolute.parent.path}${sep}DLC');
    if (!folder.existsSync()) return DlcFolderPlan(state: state);
    final files = [
      for (final f in folder.listSync(followLinks: false))
        if (f is File && f.path.toLowerCase().endsWith('.htpack')) f.path,
    ]..sort();
    final stored = storeKeys.toSet();
    // 다시 넣은 DLC(저장소에 듦)는 묘비에서 뺀다.
    final removed = state.removed.difference(stored);
    final best = <String, DlcFolderPack>{};
    final broken = <String>[], cleaned = <String>[], toolFailed = <String>[];
    final left = <String>{};
    final skip = <String, String>{}, skipApp = <String, String>{};
    for (final file in files) {
      final name = file.split(RegExp(r'[\\/]')).last;
      final known = state.skip[name];
      // 같은 파일(지문) · 같은 앱 판의 거절이면 건너뛴다 — 앱 판이 바뀌었으면 한 번 다시 본다(판정 R63-3).
      if (known != null && dlcFileFingerprint(file) == known && state.skipApp[name] == app) {
        skip[name] = known;
        skipApp[name] = app;
        continue;
      }
      final DlcFolderPack? pack;
      try {
        pack = await readPack(file);
      } on DlcToolFailure {
        // 도구 탓 — 파일을 기억하지 않는다(다음 열기에서 다시 읽음 · 판정 R58).
        toolFailed.add(name);
        continue;
      }
      if (pack == null) {
        broken.add(name);
        skip[name] = dlcFileFingerprint(file);
        skipApp[name] = app;
        continue;
      }
      if (removed.contains(pack.id)) {
        if (await deleteFile(file)) {
          cleaned.add(name);
        } else {
          left.add(pack.id);
        }
        continue;
      }
      // 저장소에 든 DLC는 폴더의 판이 더 높을 때만(판 올림 — 판정 R60 M-5 · 저장소의 판을 모르면 건너뜀).
      final storedVersion = storeVersions[pack.id];
      final newer = storedVersion != null && compareDlcVersion(pack.version, storedVersion) > 0;
      if (pack.id.isEmpty || (pack.id == baseKey && hidden.baseRemoved) || (stored.contains(pack.id) && !newer) || hidden.off.contains(pack.id) || state.off.contains(pack.id)) continue;
      final seen = best[pack.id];
      if (seen == null || compareDlcVersion(pack.version, seen.version) > 0) best[pack.id] = pack;
    }
    final add = best.values.toList()..sort((a, b) => a.path.compareTo(b.path));
    // 묘비는 아직 파일이 남은 id만(다 지웠거나 파일이 없으면 뺀다) · 건너뛸 파일은 지금 폴더에 있는 것만. 도구가 읽지 못한 파일이나 깨진 파일이 있으면
    // 그것이 묘비의 파일일 수 있어 묘비를 줄이지 않는다(되살아나지 않게 — 판정 R58 · R63-2).
    return DlcFolderPlan(
      add: add,
      broken: broken,
      cleaned: cleaned,
      toolFailed: toolFailed,
      state: state.copyWith(removed: toolFailed.isEmpty && broken.isEmpty ? left : {...left, ...removed}, skip: skip, skipApp: skipApp),
    );
  }
}

/// 자료 처리부(FFI · [library])로 저장소 [db]를 잠깐 열어 [ops]를 차례로 묻고 닫는다 — 따로 된 일꾼(isolate)에서. 답 목록(첫째 = `open`의 답 — 그 저장소의
/// info · 열지 못하면 그 실패 답 하나뿐). 앱이 엔진을 열기 전(시드 놓기 — 판정 R34)에만 쓴다: 자료 처리부의 열린 저장소는 하나(전역)라 닫고 나오면
/// 앱이 제 저장소를 다시 연다 — 엔진이 연 뒤에 부르면 앱의 저장소를 닫아 버리므로 이 파일 밖에 내놓지 않는다([SeedCarry.withEngine] · [_carryWithEngine]만). 던지지 않는다.
Future<List<Map<String, dynamic>>> _askStoreBeforeEngineOpens(String library, String db, List<Map<String, dynamic>> ops) async {
  final open = jsonEncode({'op': 'open', 'path': db});
  final rest = [for (final op in ops) jsonEncode(op)];
  try {
    return await Isolate.run(() {
      final answers = [callEngineOnce(library, open)];
      if (answers.first['ok'] == true) {
        for (final op in rest) {
          answers.add(callEngineOnce(library, op));
        }
      }
      callEngineOnce(library, '{"op":"close"}');
      return answers;
    });
  } catch (e) {
    return [
      {'ok': false, 'error': dlcErrorText(e)},
    ];
  }
}

/// 새 시드 파일 [seed]에 옛 저장소 [from]의 DLC를 자료 처리부(FFI · [library])로 넣는다(판정 R34 D — 앱이 엔진을 열기 전 · 따로 된 일꾼에서):
/// `open`(새 시드) → [seedCarrySteps](넣기 · 다시 끄기 — 받지 않는 DLC는 빼고 나머지를 넣음 · 판정 R59) → `close`. 저장소 쪽 거절이면 그 까닭 · `code`를
/// 돌려준다(새 시드 파일은 부르는 쪽이 버린다 — 옛 저장소는 건드리지 않는다). 던지지 않는다.
Future<SeedCarryAnswer> _carryWithEngine(String library, {required String seed, required String from, required List<SeedCarryAdd> adds, required List<String> keep}) async {
  final open = jsonEncode({'op': 'open', 'path': seed});
  try {
    return await Isolate.run<SeedCarryAnswer>(() {
      final opened = callEngineOnce(library, open);
      if (opened['ok'] != true) return SeedCarryAnswer.failed('${opened['error'] ?? '새 판 자료를 열지 못했습니다'}');
      try {
        return seedCarrySteps(seed: seed, from: from, adds: adds, keep: keep, call: (request) => callEngineOnce(library, jsonEncode(request)));
      } finally {
        callEngineOnce(library, '{"op":"close"}');
      }
    });
  } catch (e) {
    return SeedCarryAnswer.failed(dlcErrorText(e));
  }
}

/// 판을 올린 뒤 DLC 폴더에서 다시 들이기의 몸(앱 틀 `_syncDlcFolder` — 판정 R32 · R33 · 8 검토): [job]을 잡아 두고(이미 돌면 아무것도 하지 않고 null)
/// [pending]으로 들일 것을 살핀 뒤 하나씩 [put](앱 틀의 고쳐 쓰기 — 잡음을 이어받는다)한다. 넣지 못한 파일만 지문으로 기억하고([keep] — `DLC/sync.json`),
/// 저장소는 고쳐 썼는데 다시 읽지 못해 끝난 것([restarted])은 넣지 못한 것으로 적지 않는다. 어느 길로 끝나든(던짐 포함) 잡음을 푼다.
/// 돌려주는 것: 끝 알림 한 줄([dlcFolderNotice]) — 알릴 것이 없거나 멈췄으면([stopped] — 화면이 닫힘 · 앱을 다시 켜야 함) null.
class DlcFolderImport {
  static Future<String?> run({
    required DlcJob job,
    required DlcFolderState state,
    required Future<DlcFolderPlan> Function(DlcFolderState state) pending,
    required void Function(DlcFolderState state) keep,
    required Future<bool> Function(DlcFolderPack pack, int index, int count) put,
    required bool Function(DlcFolderPack pack) canPut,
    required bool Function() stopped,
    required bool Function() restarted,
    String app = dlcAppVersion,
  }) async {
    if (!job.hold('DLC 폴더를 살피는 중…')) return null;
    try {
      var current = state;
      final DlcFolderPlan plan;
      try {
        plan = await pending(current);
      } catch (_) {
        return null;
      }
      current = plan.state;
      keep(current);
      final added = <String>[], failed = <String>[], retry = <String>[];
      for (var i = 0; i < plan.add.length; i++) {
        final p = plan.add[i];
        if (stopped()) break;
        // 첫째는 위에서 잡았다 — 둘째부터는 앞의 일이 끝난 바로 뒤(사이에 사용자 일이 끼지 않게 곧바로) 다시 잡는다.
        if (i > 0 && !job.hold('DLC 폴더를 살피는 중…')) break;
        if (!canPut(p)) break;
        if (await put(p, i, plan.add.length)) {
          added.add('«${p.name}»');
        } else if (!restarted()) {
          // 항목 하나 = '«이름»: 까닭'(끝 마침표는 떼고 — 알림이 문장마다 붙인다).
          final why = job.lastLine.trim().replaceFirst(RegExp(r'\.+$'), '');
          final item = why.isEmpty ? '«${p.name}»' : '«${p.name}»: $why';
          // 그 파일 탓(DLC code — 배치 못 함 · 범위 밖 · 낮은 판 · 겹침 · 원본 망가짐)만 '다시 해 보지 않음'으로 적는다. code 없음(환경 탓) · path · 달력 표 없음 ·
          // 원본 없이 든 DLC …는 기억하지 않고 다음 열기에서 다시(판정 R68-3).
          if (dlcFileFault(job.lastCode)) {
            failed.add(item);
            current = current.skipping(p.path, app: app);
            keep(current);
          } else {
            retry.add(item);
          }
        }
      }
      if (stopped()) return null;
      return dlcFolderNotice(added: added, failed: failed, retry: retry, broken: plan.broken, cleaned: plan.cleaned, toolFailed: plan.toolFailed);
    } finally {
      job.release();
    }
  }
}
