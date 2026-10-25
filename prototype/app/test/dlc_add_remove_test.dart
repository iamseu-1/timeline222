import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/dlc_add.dart';
import 'package:archive_prototype/ui/dlc_layout_import.dart';
import 'package:archive_prototype/ui/dlc_manager.dart';
import 'package:archive_prototype/ui/seed_carry.dart' show DlcFolderSync;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

/// 카드 안 스위치(MotionToggle)의 값을 읽는다 — 스위치는 의미 노드의 'toggled'로 값을 알린다.
class MotionToggleLike {
  MotionToggleLike(this.tester, this.card);
  final WidgetTester tester;
  final Finder card;
  bool get value => tester.widget<DlcSwitch>(find.descendant(of: card, matching: find.byType(DlcSwitch))).value;
}

// DLC 관리 창의 더하기 · 삭제(4단계 1걸음 — `docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md` 2절 · 3-3절)와 뒷일([DlcJob])의 상태.
// 엔진 흉내(쓰기 일꾼 [DlcJob.applier] · 읽기 일꾼 [DlcJob.reader])로 엔진의 답 · 거절이 창에 쉬운 말로 비치는지, 삭제가 확인을 거쳐 앱 틀에 닿는지를 굳힌다.
// 끝의 무리는 진짜 자료 처리부(FFI · 빠른 빌드)로 같은 길을 잰다.

Future<void> pumpManager(WidgetTester tester, scene, {Future<void> Function()? onAddFiles, Future<void> Function(DlcCardInfo card)? onRemove, Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle, DlcJob? job}) async {
  tester.view.physicalSize = const Size(1300, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: DlcManager(scene: scene, onAddFiles: onAddFiles, onRemove: onRemove, onToggle: onToggle, job: job))));
}

/// 열쇠가 있는 뼈대(다시 지은 저장소의 꼴) — 기본팩 · 해솔 · 은빛 나루.
SceneLayout keyedLayout() => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': 1250, 'key': 'east-asia-base'},
    {'id': 2, 'name': '해솔 기록집', 'events': 2, 'key': 'haesol'},
    {'id': 3, 'name': '은빛 나루 기록집', 'events': 2, 'key': 'silverbay'},
  ],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0), packRow(1)]},
    {'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'rows': [packRow(2), packRow(3)]},
    {'id': 3, 'pack': 3, 'ord': 2, 'name': '은빛 나루 갈래', 'rows': [packRow(4), packRow(5)]},
  ],
  'epochs': [],
});

/// 꺼 두어 저장소에서 뺀 DLC 둘(기본팩이 아닌 것 하나 · 기본팩) — 도구가 `DLC/hidden.json`에 적는 꼴.
const hiddenJson = {
  'version': 1,
  'off': ['moonbay', 'east-asia-base'],
  'baseRemoved': false,
  'cards': {
    'moonbay': {
      'name': '달물결 기록집', 'version': '2.0.0', 'category': 'world', 'events': 101, 'periods': 54,
      'tracks': [{'key': 'tide', 'name': '물결 갈래', 'color': 0xabb3c9, 'rows': 2}, {'key': 'reef', 'name': '산호 갈래', 'color': 0xd8c4a0, 'rows': 13}],
      'shared': [{'key': 'starbrook', 'name': '별여울 갈래', 'color': 0x9ab0c0, 'owner': '별여울 기록집'}],
    },
    'east-asia-base': {'name': '별여울 기본팩', 'version': '1.0.0', 'events': 214, 'periods': 84, 'tracks': [{'key': 'starbrook', 'name': '별여울 갈래', 'color': 0x9ab0c0, 'rows': 8}]},
  },
};

/// 팩 파일(종류 [kind])의 흉내 — 머리는 진짜와 같다(지문 0 — 지문은 엔진이 본다).
List<int> sealedPack(int kind, String text) {
  final plain = utf8.encode(text), body = ZLibCodec().encode(plain);
  final head = Uint8List(packFileHeader)
    ..setAll(0, packFileMagic)
    ..[8] = packFileVersion
    ..[9] = kind
    ..[10] = 1;
  ByteData.sublistView(head)
    ..setUint32(12, plain.length, Endian.little)
    ..setUint32(16, body.length, Endian.little);
  return [...head, ...body];
}

/// DLC 파일(형식 3 — 팩 파일 종류 1)을 [path]에 쓴다 — 본문은 맨 바깥 칸(format · id · name · version)과 트랙 하나.
String writeDlc(String path, String id, String version, {String? name}) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(sealedPack(packKindDlc, jsonEncode({'format': 'history-timeline-dlc', 'id': id, 'name': name ?? id, 'version': version, 'tracks': [{'id': '$id-t', 'name': '갈래'}]})));
  return path;
}

/// 고쳐 쓰기 검사의 자리: 임시 폴더의 저장소(archive.db) · DLC/ 폴더(같은 id 낮은 판 · 뺄 DLC의 파일) · 내려받기 폴더의 새 DLC 파일(진짜 팩 머리).
class _Store {
  _Store() {
    dir = Directory.systemTemp.createTempSync('ht-dlc-apply-');
    db = _put('archive.db', '지금 저장소');
    older = writeDlc(inDlc('korean-timeline-v1.0.4.htpack'), 'korean-timeline', '1.0.4', name: 'Tigers of the East');
    haesol = writeDlc(inDlc('haesol-v1.0.0.htpack'), 'haesol', '1.0.0', name: '해솔 기록집');
    picked = writeDlc(_at('내려받기${Platform.pathSeparator}korean-timeline-v1.0.5.htpack'), 'korean-timeline', '1.0.5', name: 'Tigers of the East');
  }
  late final Directory dir;
  late final String db, older, haesol, picked;
  String _at(String name) => '${dir.path}${Platform.pathSeparator}$name';
  String _put(String name, String text) => (File(_at(name))..writeAsStringSync(text)).path;
  String inDlc(String name) => _at('DLC${Platform.pathSeparator}$name');
  String downloaded(String name) => _at('내려받기${Platform.pathSeparator}$name');
  File get hiddenFile => File(inDlc('hidden.json'));
  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// 엔진 흉내 — 받은 명령(읽기 일꾼의 op · 쓰기 일꾼의 'write')을 차례로 적는다. 보관함(`kept_packs`)은 [kept]로 답한다(null이면 빈 답 — 모름).
class _Engine {
  final commands = <String>[];
  final requests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? kept;
  Map<String, dynamic> Function(Map<String, dynamic> request) answer = (_) => {
    'ok': true,
    'data': {'rewrote': <String>[], 'added': ['ktl-t1'], 'removed': <String>[], 'globals': false, 'first_pos': 16, 'rows_before': 40, 'rows_after': 44, 'names': true, 'ms': 812.0, 'steps': []},
  };
  bool? writingDuringApply;
  Future<Map<String, dynamic>> call(Map<String, dynamic> query) async {
    commands.add('${query['op']}');
    if (query['op'] == 'kept_packs' && kept != null) return {'ok': true, 'data': kept};
    return {'ok': true, 'data': {}};
  }

  Future<Map<String, dynamic>> apply(TimelineScene scene, Map<String, dynamic> request) async {
    commands.add('write');
    requests.add(request);
    writingDuringApply = scene.storeWriting;
    return answer(request);
  }
}

void main() {
  group('넣고 빼기 — 엔진 하나로(add_pack · remove_pack — 계약 2-7-1 · 계획 P4 과제 10b)', () {
    late _Store store;
    setUp(() => store = _Store());
    tearDown(() => store.dispose());

    (DlcApplyFlow, _Engine, List<int>) flowFor(DlcJob job, TimelineScene scene) {
      final engine = _Engine(), reloads = <int>[];
      final flow = DlcApplyFlow(
        job: job, scene: scene, engineCall: engine.call,
        engineApply: (request) => engine.apply(scene, request),
        reload: (keepBefore) async => reloads.add(keepBefore),
      );
      return (flow, engine, reloads);
    }

    const stored = {'east-asia-base', 'haesol', 'silverbay'};

    test('더하기: 경로 둘이면 엔진 add_pack 하나로 그 둘(Node 없음) — close · open 없음 · 끝난 뒤에만 DLC 폴더를 맞춘다', () async {
      final (scene, _, _) = makePackScene();
      final moon = writeDlc(store.downloaded('moonbay-v2.0.0.htpack'), 'moonbay', '2.0.0', name: '달물결 기록집');
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      final version = scene.layout.version;
      final done = await flow.run(db: store.db, files: [store.picked, moon], stored: stored);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      // 엔진: 쓰기 일꾼의 add_pack 하나뿐 — 닫았다 다시 열지 않는다 · 경로는 고른 그대로(온전한 경로).
      expect(engine.commands, ['write']);
      expect(engine.requests.single, {'op': 'add_pack', 'files': [File(store.picked).absolute.path, File(moon).absolute.path], 'path': store.db},
          reason: '요청마다 쓸 저장소(path)를 싣는다 — 엔진이 열린 저장소와 다르면 거절(판정 R59 M-4 앱 몫)');
      expect(engine.writingDuringApply, isTrue, reason: '쓰는 동안 새 타일 · 빈 줄 접기 물음을 멈춘다(COMMIT 뒤 새 번호가 옛 뼈대에 섞이지 않게)');
      // 뼈대 다시 읽기는 first_pos부터만 타일을 버린다.
      expect(reloads, [16]);
      expect(done.firstPos, 16);
      expect(done.storeChanged, isTrue);
      expect(scene.storeWriting, isFalse, reason: '끝나면 푼다');
      expect(scene.layout.version, version, reason: '이 흐름은 뼈대를 직접 바꾸지 않는다(앱 틀의 다시 읽기가 바꾼다)');
      // 끝난 뒤의 DLC 폴더: 넣은 파일을 들이고 같은 id의 다른 파일(낮은 판)은 지운다 — 폴더는 id마다 하나(판을 올린 뒤 다시 들이는 원본).
      expect(File(store.inDlc('korean-timeline-v1.0.5.htpack')).readAsBytesSync(), File(store.picked).readAsBytesSync());
      expect(File(store.inDlc('moonbay-v2.0.0.htpack')).existsSync(), isTrue);
      expect(File(store.older).existsSync(), isFalse);
      expect(File(store.haesol).existsSync(), isTrue, reason: '다른 DLC의 파일은 그대로');
      expect(store.hiddenFile.existsSync(), isFalse, reason: '끈 목록이 바뀌지 않았으면 적지 않는다');
      expect(job.phase, DlcJobPhase.done);
      expect(job.lines.first, 'DLC «Tigers of the East» · «달물결 기록집»을(를) 저장소에 넣는 중…');
      expect(job.lines.last, '마쳤습니다 — 새 트랙 1개 · 0.8초', reason: '사용자 말로(엔진 속 사정 "다시 쓴 트랙" 대신)');
    });

    test('넣은 파일을 DLC 폴더에 두지 못하면 같은 id의 옛 사본은 지우지 않는다 — 판 올림 뒤 다시 들일 원본이 하나도 없게 되지 않게(① m-1)', () async {
      final (scene, _, _) = makePackScene();
      // 사본 자리에 폴더가 있어 복사(임시 파일 → 이름 바꾸기)가 실패한다.
      Directory(store.inDlc('korean-timeline-v1.0.5.htpack')).createSync(recursive: true);
      final job = DlcJob();
      final (flow, _, _) = flowFor(job, scene);
      final done = await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(done.ok, isTrue, reason: '저장소는 고쳐 썼다');
      expect(File(store.older).existsSync(), isTrue, reason: '새 사본이 없으니 옛 사본(v1.0.4)은 남긴다');
      expect(job.notes.join('\n'), contains('DLC 폴더에 두지 못했습니다'));
      // 판 글자도 파일 이름에 쓸 수 있게(경로 구분자 · 콜론 → _).
      expect(dlcOriginalFileName('reed', '1.0/2:b'), 'reed-v1.0_2_b.htpack');
    });

    test('휴대폰이 지킴으로 정한 저장소(.seed-kept)에 넣기가 성공하면 그 표식을 지운다 — 다음에 켤 때 새 판 자료로 옮기기를 다시 해 본다(① m-3)', () async {
      final (scene, _, _) = makePackScene();
      final mark = File(seedKeptPath(store.db))..writeAsStringSync('0.0.4');
      final job = DlcJob()..phone = true;
      final (flow, _, _) = flowFor(job, scene);
      expect((await flow.run(db: store.db, files: [store.picked], stored: stored)).ok, isTrue);
      expect(mark.existsSync(), isFalse);
    });

    test('DLC 폴더 사본은 고른 파일 이름이 아니라 <id>-v<판>.htpack으로 · 임시 파일에 쓴 뒤 바꿔 놓는다 — 이름 같은 다른 DLC의 파일을 덮지 않는다(판정 R60 I-2)', () async {
      final (scene, _, _) = makePackScene();
      // 폴더에 이미 다른 DLC(달물결)가 내려받은 이름 그대로 들어 있다 — 사용자가 고른 해솔 새 판도 같은 이름으로 내려받았다.
      final other = writeDlc(store.inDlc('download (1).htpack'), 'moonbay', '2.0.0', name: '달물결 기록집');
      final otherBytes = File(other).readAsBytesSync();
      final picked = writeDlc(store.downloaded('download (1).htpack'), 'haesol', '1.1.0', name: '해솔 기록집');
      final job = DlcJob();
      final (flow, _, _) = flowFor(job, scene);
      expect((await flow.run(db: store.db, files: [picked], stored: stored)).ok, isTrue, reason: job.lines.join('\n'));
      expect(File(store.inDlc(dlcOriginalFileName('haesol', '1.1.0'))).readAsBytesSync(), File(picked).readAsBytesSync());
      expect(File(other).readAsBytesSync(), otherBytes, reason: '이름이 같은 다른 DLC의 사본은 그대로');
      expect(File(store.haesol).existsSync(), isFalse, reason: '같은 id의 옛 판 사본은 지운다(폴더는 id마다 하나)');
      expect(Directory(store.inDlc('')).listSync().map((f) => f.path).where((p) => p.endsWith('.tmp') || p.contains('.htpack.')), isEmpty, reason: '임시 파일이 남지 않는다');
    });

    test('빼기 · 끄기의 묘비는 엔진에 맡기기 **전에** 적고 거절되면 되돌린다 — COMMIT과 묘비 사이에 꺼져도 판 올림 뒤 되살아나지 않게(판정 R60 M-1)', () async {
      final (scene, _, _) = makePackScene();
      final job = DlcJob();
      final (flow, engine, _) = flowFor(job, scene);
      final during = <String, DlcFolderState?>{};
      engine.answer = (request) {
        during['${request['id']}'] = DlcFolderState.read(store.db);
        return request['id'] == 'silverbay'
            ? {'ok': false, 'error': '거절', 'code': 'dup_uid'}
            : {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['h'], 'first_pos': 2, 'ms': 1}};
      };
      expect((await flow.run(db: store.db, removeKey: 'haesol', stored: stored)).ok, isTrue);
      expect(during['haesol']!.removed, {'haesol'}, reason: '엔진이 쓰는 동안 이미 묘비');
      expect((await flow.run(db: store.db, offKeys: ['silverbay'], stored: stored, offCards: {'silverbay': {'name': '은빛 나루'}})).ok, isFalse);
      expect(during['silverbay']!.off, {'silverbay'}, reason: '끄기도 먼저');
      expect(DlcFolderState.read(store.db)!.off, isEmpty, reason: '거절되면 묘비를 되돌린다(저장소 그대로 — 끈 것이 아니다)');
      expect(DlcFolderState.read(store.db)!.removed, {'haesol'}, reason: '앞의 지우기 묘비는 그대로');
    });

    test('넣을 때 DLC 폴더의 같은 id 사본 가운데 넣은 판보다 높은 판은 남긴다(판정 R60 M-2)', () async {
      final (scene, _, _) = makePackScene();
      final higher = writeDlc(store.inDlc('haesol-v1.2.0.htpack'), 'haesol', '1.2.0', name: '해솔 기록집');
      final picked = writeDlc(store.downloaded('haesol-v1.1.0.htpack'), 'haesol', '1.1.0', name: '해솔 기록집');
      final job = DlcJob();
      final (flow, _, _) = flowFor(job, scene);
      expect((await flow.run(db: store.db, files: [picked], stored: stored)).ok, isTrue, reason: job.lines.join('\n'));
      expect(File(higher).existsSync(), isTrue, reason: '더 높은 판의 원본은 지우지 않는다');
      expect(File(store.haesol).existsSync(), isFalse, reason: '낮은 판(1.0.0)은 지운다');
      expect(File(store.inDlc('haesol-v1.1.0.htpack')).existsSync(), isTrue);
    });

    test('지우기: remove_pack delete:true · 끝난 뒤 그 DLC의 파일을 지운다 · COMMIT 직후 묘비', () async {
      final (scene, _, _) = makePackScene();
      String? during;
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      engine.answer = (request) {
        during = job.removingKey;
        return {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['haesol-t'], 'first_pos': 2, 'ms': 300, 'deleted': ['haesol']}};
      };
      final done = await flow.run(db: store.db, removeKey: 'haesol', stored: stored);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(engine.requests.single, {'op': 'remove_pack', 'id': 'haesol', 'delete': true, 'path': store.db});
      expect(reloads, [2]);
      expect(File(store.haesol).existsSync(), isFalse);
      expect(during, 'haesol', reason: '도는 동안 창이 그 카드를 `삭제하는 중…`으로');
      expect(job.removingKey, '');
      expect(DlcFolderState.read(store.db)!.removed, {'haesol'}, reason: 'COMMIT 직후 묘비 — 폴더 지우기가 실패해도 판을 올린 뒤 다시 들이지 않게(판정 R33)');
    });

    test('지우기의 파일 지우기가 실패해도(읽기 전용 파일) 묘비가 남고 나머지 지우기는 이어 가며, 알림은 사실대로다(판정 R33)', () async {
      final (scene, _, _) = makePackScene();
      final locked = store.haesol, other = writeDlc(store.inDlc('haesol-v0.9.0.htpack'), 'haesol', '0.9.0');
      if (Platform.isWindows) {
        Process.runSync('attrib', ['+R', locked]);
        addTearDown(() => Process.runSync('attrib', ['-R', locked]));
      } else {
        Process.runSync('chmod', ['a-w', File(locked).parent.path]);
        addTearDown(() => Process.runSync('chmod', ['u+w', File(locked).parent.path]));
      }
      final job = DlcJob();
      final (flow, engine, _) = flowFor(job, scene);
      engine.answer = (_) => {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['haesol-t'], 'first_pos': 2, 'ms': 300}};
      final done = await flow.run(db: store.db, removeKey: 'haesol', stored: stored);
      expect(done.ok, isTrue, reason: '저장소는 고쳐 썼다');
      expect(File(locked).existsSync(), isTrue, reason: '장면: 지우기 실패');
      if (Platform.isWindows) expect(File(other).existsSync(), isFalse, reason: '첫 실패에서 멈추지 않고 나머지를 지운다');
      expect(job.notes.single, contains('다음에 앱을 열 때 다시 지웁니다'));
      expect(DlcFolderState.read(store.db)!.removed, {'haesol'});
    });

    test('같은 DLC의 낮은 판 파일(묘비 DLC의 것이 아님)을 못 지우면 "다음에 앱을 열 때 다시 지웁니다"를 약속하지 않는다(8 검토)', () async {
      final (scene, _, _) = makePackScene();
      final locked = store.older;
      if (Platform.isWindows) {
        Process.runSync('attrib', ['+R', locked]);
        addTearDown(() => Process.runSync('attrib', ['-R', locked]));
      } else {
        Process.runSync('chmod', ['a-w', File(locked).parent.path]);
        addTearDown(() => Process.runSync('chmod', ['u+w', File(locked).parent.path]));
      }
      final job = DlcJob();
      final (flow, _, _) = flowFor(job, scene);
      final done = await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(File(locked).existsSync(), isTrue, reason: '장면: 지우기 실패');
      expect(job.notes.single, contains('korean-timeline-v1.0.4.htpack'));
      expect(job.notes.single, isNot(contains('다음에 앱을 열 때 다시 지웁니다')), reason: '열 때 지우는 것은 묘비(뺀 DLC)의 파일뿐이다');
      expect(job.notes.single, contains('다시 들이지 않습니다'));
      expect(job.notes.single, contains('손으로 지워도 됩니다'));
    });

    test('엔진도 앱도 저장소를 다시 열지 못하거나 뼈대를 읽다 던지면 예외가 새지 않고 "앱을 다시 켜 주세요"로 끝난다', () async {
      final (scene, _, _) = makePackScene();
      // 1. committed + 앱의 open도 실패 → 다시 읽지 않는다(닫힌 저장소에 묻지 않게).
      final job = DlcJob(), reloads = <int>[];
      final flow = DlcApplyFlow(
        job: job, scene: scene,
        engineCall: (q) async => throw StateError('저장소를 열 수 없습니다'),
        engineApply: (_) async => {'ok': false, 'error': '쓰기는 끝나 … 다시 열어 주세요', 'committed': true},
        reload: (k) async => reloads.add(k),
      );
      final done = await flow.run(db: store.db, files: [store.picked]);
      expect(done.restart, isTrue);
      expect(reloads, isEmpty);
      expect(scene.storeWriting, isFalse);
      expect(job.notes.last, contains('앱을 다시 켜 주세요'));
      // 2. 다시 읽다 던짐 → 잡아서 같은 끝.
      final job2 = DlcJob();
      final flow2 = DlcApplyFlow(
        job: job2, scene: scene, engineCall: (q) async => {'ok': true},
        engineApply: (_) async => {'ok': true, 'data': {'rewrote': [], 'added': ['t'], 'removed': [], 'first_pos': 0, 'ms': 1}},
        reload: (k) async => throw StateError('저장소가 열리지 않았습니다'),
      );
      final done2 = await flow2.run(db: store.db, files: [store.picked]);
      expect(done2.restart, isTrue);
      expect(scene.storeWriting, isFalse);
      expect(job2.notes.last, contains('앱을 다시 켜 주세요'));
    });

    test('쓰기 직전에 한 번(beforeWrite) — 앱이 옛 저장소에서 옮겨 적을 것(옛 띠 번호 → uid)을 셈한다(고침 2회차 Minor 2)', () async {
      final (scene, _, _) = makePackScene();
      final seen = <bool>[];
      final engine = _Engine();
      final flow = DlcApplyFlow(
        job: DlcJob(), scene: scene, engineCall: engine.call, engineApply: (r) => engine.apply(scene, r), reload: (_) async {},
        beforeWrite: () async => seen.add(scene.storeWriting),
      );
      expect((await flow.run(db: store.db, files: [store.picked])).ok, isTrue);
      expect(seen, [false], reason: '엔진이 쓰기 전(옛 저장소) · 한 번');
    });

    test('잡아 둔 동안(hold) 다른 일은 끼지 못하고, 잡은 쪽만 이어서 넣는다(고침 2회차 Minor 4)', () async {
      final job = DlcJob()..applier = (r) async => {'ok': true, 'data': {'rewrote': [], 'added': ['t'], 'removed': [], 'first_pos': 0, 'ms': 1}};
      expect(job.hold('DLC 폴더를 살피는 중…'), isTrue);
      expect(job.running, isTrue);
      expect(job.status, 'DLC 폴더를 살피는 중…');
      expect(job.hold('또'), isFalse, reason: '다른 일은 끼지 못한다');
      final done = await job.apply(db: store.db, files: [store.picked]);
      expect(done.ok, isTrue, reason: '잡은 쪽은 이어서 넣는다');
      expect(job.running, isFalse);
      expect(job.hold('다시'), isTrue);
      job.release();
      expect(job.running, isFalse);
      expect(job.phase, DlcJobPhase.idle);
    });

    test('거절이면 저장소 · 화면 · DLC 폴더 · 끈 목록 그대로이고 창에 쉬운 까닭이 남는다(다시 읽기 · 다시 열기 없음)', () async {
      final (scene, painter, _) = makePackScene();
      for (int i = 0; i < 20; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(1920, 500));
        recorder.endRecording().dispose();
        await pumpEventQueue();
      }
      final tiles = scene.cache.count, version = scene.layout.version;
      expect(tiles, greaterThan(0));
      store.hiddenFile.writeAsStringSync(jsonEncode({'version': 1, 'off': ['korean-timeline'], 'baseRemoved': false, 'cards': {'korean-timeline': {'name': 'Tigers of the East'}}}));
      final hiddenBefore = store.hiddenFile.readAsStringSync();
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      const why = '달력 표 없음 — 새 판 시드로 다시';
      engine.answer = (_) => {'ok': false, 'error': why, 'code': 'calendar'};
      final before = File(store.db).readAsStringSync();
      final done = await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(done.ok, isFalse);
      expect(done.storeChanged, isFalse);
      expect(engine.commands, ['write'], reason: '다시 열지 않는다');
      expect(reloads, isEmpty, reason: '뼈대를 다시 읽지 않는다 — 화면 그대로');
      expect(scene.layout.version, version);
      expect(scene.cache.count, tiles, reason: '타일 보관도 그대로');
      expect(scene.storeWriting, isFalse, reason: '멈췄던 물음을 푼다');
      expect(job.failed, isTrue);
      expect(job.status, dlcRefusalText('calendar', why), reason: '창의 위 칸에 쉬운 말(code로 가름)');
      expect(job.status, contains('앱을 새 판으로 올리면'), reason: "표 없는 옛 저장소 → '새 판 시드로 옮긴 뒤 다시'(시드 잇기)로 이어진다(판정 R36)");
      expect(File(store.db).readAsStringSync(), before);
      expect(File(store.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isFalse, reason: '실패면 DLC 폴더도 그대로');
      expect(File(store.older).existsSync(), isTrue);
      expect(store.hiddenFile.readAsStringSync(), hiddenBefore, reason: '실패면 끈 목록도 그대로(끈 DLC를 다시 더해도 켜지 않음)');
    });

    test('엔진 code마다 쉬운 알림 — version · original · calendar · dup_uid · 깨진 파일 · code 없음', () async {
      final (scene, _, _) = makePackScene();
      const said = {
        'version': '지금 든(꺼 둔 것 포함) 것보다 낮은 판이라 넣지 않았습니다',
        'original': "그 DLC의 .htpack을 '파일에서 더하기'로 함께 골라",
        'calendar': '저장소의 달력 표에 문제가 있어',
        'dup_uid': 'DLC를 만든 쪽(메이커)에서 고쳐야 합니다',
        'base': '기본 DLC(바탕)가 지금 저장소와 달라',
        'layout': '그 DLC를 연표에 배치하지 못해 넣지 않았습니다',
      };
      for (final MapEntry(key: code, value: words) in said.entries) {
        final job = DlcJob();
        final (flow, engine, _) = flowFor(job, scene);
        engine.answer = (_) => {'ok': false, 'error': '엔진의 글($code)', 'code': code, 'detail': '개발자 말($code)'};
        expect((await flow.run(db: store.db, files: [store.picked])).ok, isFalse);
        expect(job.status, dlcRefusalText(code, '엔진의 글($code)'));
        expect(job.status, contains(words), reason: code);
        // 어느 DLC의 무엇인지는 엔진의 글(error)이 말한다 — 달력 표 없음(calendar)도(② Minor 1). 개발자 말(detail)은 알림에 싣지 않고 일에 보관한다(② Minor 4).
        expect(job.status, contains('자세히: 엔진의 글($code)'), reason: code);
        expect(job.status, isNot(contains('개발자 말')), reason: code);
        expect(job.lastDetail, '개발자 말($code)', reason: code);
      }
      // 판정 R72-6: calendar는 저장소의 달력 표 문제 모두(표 없음 · 깨짐 · 그 달력 없음 · 아주 옛 저장소)를 덮는 글 — '앱을 새 판으로 올리면'은 표가 없을 때만.
      const absent = '달력 표가 없는 옛 저장소입니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요(이 저장소에서는 DLC를 넣거나 뺄 수 없습니다)';
      expect(dlcRefusalText('calendar', absent), allOf(startsWith('저장소의 달력 표에 문제가 있어'), contains('앱을 새 판으로 올리면'), contains('자세히: 달력 표가 없는 옛 저장소')));
      for (final other in [
        '저장소의 달력 표가 깨졌습니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요(이 저장소에서는 DLC를 넣거나 뺄 수 없습니다)',
        '저장소의 달력 표에 «음력»이 없어 «갈대»의 날짜를 읽을 수 없습니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요',
        '',
      ]) {
        expect(dlcRefusalText('calendar', other), allOf(startsWith('저장소의 달력 표에 문제가 있어'), isNot(contains('앱을 새 판으로 올리면')), isNot(contains('예전 판에서 지어'))), reason: other);
      }
      // broken은 그 파일이 망가짐 — 같은 파일을 다시 고르라 하지 않고 메이커에서 다시 저장한 .htpack을(판정 R72-6).
      expect(dlcRefusalText('broken', '«갈대»의 원본을 읽을 수 없습니다 — 본문이 JSON이 아닙니다'),
          allOf(contains('그 DLC 파일이 망가져'), contains('메이커에서 다시 저장한 .htpack을 골라'), isNot(contains('다시 골라 넣어'))));
      // 엔진 글의 '보관함'(속말)은 자세히 칸에서도 쓰지 않는다(② Minor 2).
      expect(dlcRefusalText('version', '«X»의 판이 보관함(꺼 둔 DLC)의 것보다 낮습니다(보관함 v1.2 · 받은 v1.0) — 낮은 판으로는 바꾸지 않습니다'), isNot(contains('보관함')));
      // 열린 저장소가 아닌 곳에 쓰라는 거절(갈래 1의 path — code 'path'이든 글이든)은 쉬운 말로(② Minor 4).
      // 갈래 1(p34-b dc0488a)의 실제 글(code path)과 그 전의 글(code 없음) 모두.
      const pathErrors = [
        '지금 열린 저장소가 이 요청의 저장소와 달라 쓰지 않았습니다(저장소는 그대로) — 다시 해 주세요',
        '열린 저장소가 아닌 곳에 쓰라는 요청입니다 — 쓰지 않습니다(요청 D:\\a\\archive.db · 열린 저장소 D:\\b\\archive.db)',
      ];
      for (final pathError in pathErrors) {
        for (final code in [null, 'path']) {
          expect(dlcRefusalText(code, pathError), allOf(contains('앱이 연 저장소가 그새 바뀌어'), isNot(contains('D:'))), reason: '$code $pathError');
        }
      }
      // code가 없는 거절(넣을 DLC가 둘 · 저장소가 열리지 않음 …)은 엔진의 글 그대로 앞에 '넣지 못했습니다' · 빼기는 '빼지 못했습니다'.
      final job = DlcJob();
      final (flow, engine, _) = flowFor(job, scene);
      engine.answer = (_) => {'ok': false, 'error': '«korean-timeline»를 둘 받았습니다'};
      await flow.run(db: store.db, files: [store.picked]);
      expect(job.status, 'DLC를 넣지 못했습니다 — «korean-timeline»를 둘 받았습니다');
      await flow.run(db: store.db, removeKey: 'haesol', stored: stored);
      expect(job.status, startsWith('DLC를 빼지 못했습니다 — '));
      // 엔진의 옛 말('컴퓨터에서 다시 지어 주세요' — 다시 짓기 길은 걷었다)은 앱의 길로 바꿔 말한다 · '보관함' 같은 속말은 쓰지 않는다(판정 R60 M-11).
      expect(dlcRefusalText(null, '기본 DLC «별여울 기본팩»는 뺄 수 없습니다 — 컴퓨터에서 다시 지어 주세요', removing: true),
          'DLC를 빼지 못했습니다 — 기본 DLC «별여울 기본팩»는 뺄 수 없습니다 — 끄면 화면에서 가려집니다');
      expect(dlcRefusalText(null, '«moonbay»는 이미 꺼 둔(보관함의) DLC입니다 — 지우려면 delete를 주세요', removing: true), isNot(contains('보관함')));
      expect(dlcErrorText(const FileSystemException('Cannot delete file', r'D:\사본\DLC\reed-v1.0.0.htpack', OSError('액세스가 거부되었습니다.', 5))),
          '액세스가 거부되었습니다. (reed-v1.0.0.htpack)');
      expect(dlcErrorText(StateError('저장소가 열리지 않았습니다')), '저장소가 열리지 않았습니다');
      // 빼기 · 끄기(remove_pack)의 dup_uid는 '빼지 않았습니다'(남는 조합에서 겹침 — 판정 R37) — '넣지 않았습니다'가 아니다.
      engine.answer = (_) => {'ok': false, 'error': '«은빛 나루»의 사건 x가 두 트랙에', 'code': 'dup_uid'};
      await flow.run(db: store.db, removeKey: 'haesol', stored: stored);
      expect(job.status, allOf(contains('같은 항목이 두 트랙에 들어 있어 빼지 않았습니다'), isNot(contains('넣지'))));
      await flow.run(db: store.db, offKeys: ['haesol'], stored: stored, offCards: {'haesol': {'name': '해솔 기록집'}});
      expect(job.status, allOf(contains('빼지 않았습니다'), isNot(contains('넣지'))), reason: '끄기도 저장소에서 빼는 일');
      await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(job.status, contains('같은 항목이 두 트랙에 들어 있어 넣지 않았습니다'));
      // 빼기의 dup_uid는 남는 DLC끼리의 사정 — 겹친 DLC를 먼저 빼라고(② Minor 7). range · layout은 빼기에서 오지 않는다(받은 DLC 탓일 때만 — 판정 R72-3 ·
      // R72-7: 따로 된 빼기 갈래를 걷었다) — 와도 '빼지 않았습니다'.
      expect(dlcRefusalText('dup_uid', '', removing: true), '같은 항목이 두 트랙에 들어 있어 빼지 않았습니다 — 이 DLC를 빼면 남는 DLC끼리 겹칩니다: 겹친 DLC를 먼저 빼 주세요.');
      expect(dlcRefusalText('layout', '', removing: true), allOf(contains('빼지 않았습니다'), isNot(contains('남는 DLC를 연표에'))));
      // 켜기(add_pack ids)의 거절은 '켜지 않았습니다'(② Minor 7).
      engine
        ..kept = [{'id': 'moonbay', 'name': '달물결 기록집', 'version': '2.0.0', 'bytes': 9}]
        ..answer = (_) => {'ok': false, 'error': '«달물결»의 사건 y가 두 트랙에', 'code': 'dup_uid'};
      await flow.run(db: store.db, onKeys: ['moonbay'], stored: stored);
      expect(job.status, allOf(contains('켜지 않았습니다'), isNot(contains('넣지'))));
      engine.answer = (_) => {'ok': false, 'error': '알 수 없는 까닭'};
      await flow.run(db: store.db, onKeys: ['moonbay'], stored: stored);
      expect(job.status, startsWith('DLC를 켜지 못했습니다 — '));
    });

    test('range(그 DLC의 날짜가 앱이 아는 달력 범위 밖 — DLC 쪽 잘못 · 판정 R62): 그 DLC 하나의 거절 — 메이커에서 날짜를 고쳐 다시 · 저장소를 옮기라는 말 없음', () async {
      final (scene, _, _) = makePackScene();
      // 원본 없이 든 KoreanTimeLine(같은 판)의 .htpack을 고른 꼴 — calendar · original이면 DLC 폴더에 둘 자리다(② Minor 8: 아래 '두지 않는다'가 정말 가르게).
      final job = DlcJob()..packFacts.addAll(const {'korean-timeline': DlcPackFacts(version: '1.0.5', original: false)});
      final (flow, engine, reloads) = flowFor(job, scene);
      const why = '«Tigers of the East»의 날짜가 앱이 아는 달력 범위 밖입니다 — 보조 달력(음력) 날짜는 -3500 ~ 2500년 안이어야 합니다';
      engine.answer = (_) => {'ok': false, 'error': why, 'code': 'range', 'detail': '음력 표 범위 밖: 2500'};
      final before = File(store.db).readAsStringSync();
      final done = await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(done.ok, isFalse);
      expect(job.lastCode, 'range');
      expect(job.status, dlcRefusalText('range', why));
      expect(job.status, allOf(startsWith('그 DLC의 날짜가 앱이 아는 달력 범위 밖이라 넣지 않았습니다'), contains('메이커에서 그 DLC의 날짜를 고쳐'), contains('자세히: $why')));
      expect(job.status, isNot(anyOf(contains('새 판으로 올리'), contains('옮기'), contains('달력 표가 없'))), reason: '저장소 쪽 사정(calendar)과 섞지 않는다');
      expect(dlcFileFault('range'), isTrue, reason: '판 올림 뒤 다시 들이기(R32)는 그 파일의 문제로 기억한다(파일이 바뀌기 전에는 다시 해 보지 않음)');
      expect(reloads, isEmpty);
      expect(File(store.db).readAsStringSync(), before);
      expect(File(store.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isFalse, reason: '원본 없는 DLC의 .htpack 두기(calendar · original)와 달리 DLC 폴더에 두지 않는다');
      // 같은 꼴에 calendar면 둔다 — 위 단언이 빈 단언이 아님을 보인다.
      engine.answer = (_) => {'ok': false, 'error': '달력 표가 없는 옛 저장소입니다', 'code': 'calendar'};
      await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(File(store.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isTrue);
      expect(dlcRefusalText('range', '', removing: true), contains('빼지 않았습니다'));
    });

    test('DLC가 아닌 파일 · 깨진 파일 · 백업 팩은 엔진에 닿기 전에 알린다(저장소 그대로) · 쓰기 일꾼이 던지면 까닭을 남긴다', () async {
      final (scene, _, _) = makePackScene();
      final notes = (File(store.downloaded('메모.txt'))..writeAsStringSync('그냥 글')).path;
      final cut = (File(store.downloaded('잘린-팩.htpack'))..writeAsBytesSync(sealedPack(packKindDlc, '{"format":"history-timeline-dlc","id":"x"}').sublist(0, 60))).path;
      final backup = (File(store.downloaded('백업.htpack'))..writeAsBytesSync(sealedPack(packKindBackup, '{"format":"history-timeline-backup"}'))).path;
      final other = (File(store.downloaded('다른-본문.htpack'))..writeAsBytesSync(sealedPack(packKindDlc, '{"format":"maker-workspace","id":"x"}'))).path;
      final noId = (File(store.downloaded('id-없음.json'))..writeAsStringSync('{"format":"history-timeline-dlc","name":"이름만"}')).path;
      final cases = {
        notes: 'DLC 파일(.htpack)이 아닙니다',
        cut: '잘렸거나',
        backup: '전체 백업 팩이라 DLC로 넣을 수 없습니다',
        other: 'DLC 본문이 아닙니다',
        noId: 'DLC에 id가 없습니다',
      };
      for (final MapEntry(key: file, value: why) in cases.entries) {
        final job = DlcJob();
        final (flow, engine, reloads) = flowFor(job, scene);
        final done = await flow.run(db: store.db, files: [store.picked, file]);
        expect(done.ok, isFalse);
        expect(engine.commands, isEmpty, reason: '엔진에 닿지 않는다');
        expect(reloads, isEmpty);
        expect(job.status, contains(why), reason: file);
        expect(job.status, startsWith(file.split(Platform.pathSeparator).last), reason: '어느 파일인지');
      }
      expect(File(store.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isFalse);
      // .json 본문(형식 1 · 4)은 받는다 — 엔진이 싸서 넣는다.
      final json = (File(store.downloaded('reed.json'))..writeAsStringSync('{"name":"갈대","format":"history-timeline-dlc","version":1.2,"id":"reed"}')).path;
      expect(readDlcFileHead(json).head?.id, 'reed');
      expect(readDlcFileHead(json).head?.version, '1.2');
      final job2 = DlcJob();
      final flow2 = DlcApplyFlow(job: job2, scene: scene, engineCall: (q) async => {'ok': true}, engineApply: (_) async => throw StateError('자료 처리 종료'), reload: (_) async {});
      expect((await flow2.run(db: store.db, files: [store.picked])).ok, isFalse);
      expect(job2.status, 'DLC를 넣지 못했습니다 — 저장소를 고쳐 쓰지 못했습니다: 자료 처리 종료', reason: "날 예외 꼴('Bad state: …') 대신 사람의 말(판정 R60 M-11)");
      expect(scene.storeWriting, isFalse);
    });

    test('replaced(판정 R43 — 엔진은 원본이 바뀌면 늘 싣는다)는 같은 판 · 옛 원본이 있던 것만 "같은 판의 다른 파일로 바꿨습니다" — 판 올림 · 원본 채우기는 알리지 않는다', () async {
      final (scene, _, _) = makePackScene();
      Map<String, dynamic> replaced(String oldVersion, String newVersion, String? oldSha) =>
          {'id': 'korean-timeline', 'old_version': oldVersion, 'new_version': newVersion, 'old_sha256': oldSha, 'new_sha256': 'b' * 64};
      Future<List<String>> notesFor(Map<String, dynamic> entry) async {
        final job = DlcJob();
        final (flow, engine, _) = flowFor(job, scene);
        engine.answer = (_) => {'ok': true, 'data': {'rewrote': ['korea'], 'added': [], 'removed': [], 'first_pos': 4, 'ms': 500, 'replaced': [entry]}};
        expect((await flow.run(db: store.db, files: [store.picked], stored: stored)).ok, isTrue);
        return [...job.notes];
      }
      expect(await notesFor(replaced('1.0.5', '1.0.5', 'a' * 64)), ['«Tigers of the East»은(는) 같은 판의 다른 파일로 바꿨습니다.']);
      expect(await notesFor(replaced('1.0.4', '1.0.5', 'a' * 64)), isEmpty, reason: '판 올림은 보통의 바꿔 넣기 — 알리지 않는다');
      expect(await notesFor(replaced('1.0.5', '1.0.5', null)), isEmpty, reason: '원본 없이 든 DLC에 원본을 채운 것 — 알리지 않는다');
    });

    test('형식 4 파일을 넣으면(엔진 답의 notes에 형식 4 내림 알림 — 리메이크 5단계 과제 10) "아직 그리지 않습니다" 한 줄 — 미리보기(prefer_given)도 · 알림이 없거나 다른 알림이면 조용', () async {
      final (scene, _, _) = makePackScene();
      Future<List<String>> notesFor(List<dynamic>? notes, {bool preview = false}) async {
        final job = DlcJob();
        final (flow, engine, _) = flowFor(job, scene);
        engine.answer = (_) => {'ok': true, 'data': {'rewrote': <String>[], 'added': ['f4-t'], 'removed': <String>[], 'first_pos': 4, 'ms': 50, 'notes': ?notes}};
        expect((await flow.run(db: store.db, files: [store.picked], stored: stored, preferGiven: preview)).ok, isTrue, reason: job.lines.join(' / '));
        return [...job.notes];
      }
      // 엔진 `add_pack`이 형식 4 파일을 옛 꼴로 내리며 남기는 알림(`lay/pack.rs` · `f4.rs` — DLC 이름 머리) — 이름은 가상.
      const f4 = [
        '«형식 4 가상 팩»: 형식 4 파일을 지금 형식으로 바꿔 읽었습니다(저장은 지금 형식으로 됩니다).',
        '«형식 4 가상 팩»: 사람 "은 하림"의 직위 줄은(는) 사람 객체에 적지 않아 뺍니다(칭호는 지도자 칸의 person으로).',
      ];
      expect(await notesFor(f4), [dlcFormat4Line]);
      expect(await notesFor(f4, preview: true), [dlcFormat4Line], reason: '메이커 미리보기(연표로 ↗)도 — 앱 틀이 미리보기의 늘 남는 글에 붙인다');
      expect(await notesFor(null), isEmpty, reason: '옛 엔진 · 형식 3 파일 — notes 없음');
      expect(await notesFor(const <dynamic>[]), isEmpty);
      expect(await notesFor(['«해솔 기록집»: 다른 알림']), isEmpty, reason: '형식 4 내림 알림이 아니면 조용');
      expect(dlcFormat4Note(f4), dlcFormat4Line);
      expect(dlcFormat4Note('글'), isNull, reason: '목록이 아니면 null');
    });

    test('예전 배치로만 든 DLC(원본 없음)의 .htpack을 저장소가 받지 못하면(표 없음 · 원본 채우기 전 엔진) DLC 폴더에 두고 지킴 표식을 지운다 — 시드 잇기가 옮긴다(과제 11c)', () async {
      final (scene, _, _) = makePackScene();
      final reed = writeDlc(store.downloaded('reed-v1.0.0.htpack'), 'reed', '1.0.0', name: '갈대 기록집');
      final kept = File('${store.db}.seed-kept')..writeAsStringSync('0.0.4');
      final job = DlcJob()..packFacts.addAll(const {'reed': DlcPackFacts(version: '1.0.0', original: false)});
      final (flow, engine, reloads) = flowFor(job, scene);
      engine.answer = (_) => {'ok': false, 'error': '달력 표가 없는 옛 저장소입니다', 'code': 'calendar'};
      final done = await flow.run(db: store.db, files: [reed], stored: const {'east-asia-base', 'reed'});
      expect(done.ok, isFalse);
      expect(done.storeChanged, isFalse);
      expect(reloads, isEmpty);
      expect(File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).readAsBytesSync(), File(reed).readAsBytesSync(), reason: '시드 잇기가 찾는 이름으로 DLC 폴더에');
      expect(kept.existsSync(), isFalse, reason: '지킴 표식을 지워 다음에 켤 때 시드 잇기가 다시 해 본다');
      expect(job.status, '«갈대 기록집»의 원본(.htpack)을 DLC 폴더에 두었습니다 — 이 저장소에는 지금 넣을 수 없어 앱을 다시 켜면 새 판 자료로 옮기며 함께 넣습니다.');
      expect(job.notes, contains(job.status), reason: '창을 닫았다 열어도 남는다');
      expect(job.stashedNote, job.status, reason: "앱 틀은 '더하기에 실패했습니다 — …두었습니다' 대신 이 알림만 보인다(11c 검토 — 모순처럼 읽힘)");

      // 표식이 없으면(컴퓨터 — 시드를 쓰지 않거나 아직 지키지 않음) '새 판으로 올리면' — 엔진이 원본 채우기를 아직 못 받아(code original) 거절해도 같은 길.
      File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).deleteSync();
      engine.answer = (_) => {'ok': false, 'error': '원본이 저장소에 없는 DLC가 있어', 'code': 'original'};
      expect((await flow.run(db: store.db, files: [reed], stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).existsSync(), isTrue);
      expect(job.status, endsWith('앱을 새 판으로 올리면 새 판 자료로 옮기며 함께 넣습니다.'));
      // 휴대폰은 늘 '다시 켜면'(시드 잇기가 켤 때마다 다시 해 본다 — 표식은 첫 원본에서 이미 지웠다: 둘째 원본 없는 DLC부터도 — 11c 검토).
      job.phone = true;
      expect((await flow.run(db: store.db, files: [reed], stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(job.status, endsWith('앱을 다시 켜면 새 판 자료로 옮기며 함께 넣습니다.'));
      job.phone = null;

      // 판이 다른 .htpack이면 두지 않고 '저장소와 같은 판(vX)의 .htpack'을 말한다(11c 검토). 파일 탓 거절이면 두지 않는다.
      File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).deleteSync();
      kept.writeAsStringSync('0.0.4');
      final other = writeDlc(store.downloaded('reed-v2.0.0.htpack'), 'reed', '2.0.0', name: '갈대 기록집');
      engine.answer = (_) => {'ok': false, 'error': '달력 표가 없는 옛 저장소입니다', 'code': 'calendar'};
      expect((await flow.run(db: store.db, files: [other], stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(Directory(store.inDlc('')).listSync().map((f) => f.path).where((p) => p.contains('reed-v')), isEmpty);
      expect(kept.existsSync(), isTrue);
      expect(job.status, '«갈대 기록집»은(는) 저장소에 든 판(v1.0.0)과 달라 원본으로 둘 수 없습니다 — 저장소와 같은 판(v1.0.0)의 .htpack을 골라 주세요.');
      expect(job.stashedNote, isNull);
      // 맞는 판과 다른 판을 함께 고르면 둔 알림이 다른 판 알림을 가리지 않는다(② Minor 7 — 앱 틀은 stashedNote만 보인다).
      expect((await flow.run(db: store.db, files: [reed, other], stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(job.stashedNote, allOf(contains('원본(.htpack)을 DLC 폴더에 두었습니다'), contains('저장소와 같은 판(v1.0.0)의 .htpack을 골라 주세요')));
      File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).deleteSync();
      kept.writeAsStringSync('0.0.4');
      // 표식이 있는데 원본 없는 DLC가 아닌 새 DLC를 넣으려 하면 먼저 할 일을 알린다.
      final fresh = writeDlc(store.downloaded('moon-v1.0.0.htpack'), 'moonbay', '1.0.0', name: '달물결 기록집');
      expect((await flow.run(db: store.db, files: [fresh], stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(job.status, contains("먼저 '원본 없음' DLC의 .htpack을 '파일에서 더하기'로 넣어 주세요"));
      // 빼기 · 끄기도 같은 사정이면 '앱을 새 판으로 올리면'(이미 새 판이다) 대신 할 일을 말한다(② Minor 1 — 휴대폰이 지킨 저장소 · R34 A).
      expect((await flow.run(db: store.db, removeKey: 'reed', stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(job.status, allOf(contains("먼저 '원본 없음' DLC의 .htpack을 '파일에서 더하기'로 넣어 주세요"), isNot(contains('앱을 새 판으로 올리면'))));
      engine.answer = (_) => {'ok': false, 'error': '낮은 판', 'code': 'version'};
      expect((await flow.run(db: store.db, files: [reed], stored: const {'east-asia-base', 'reed'})).ok, isFalse);
      expect(File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).existsSync(), isFalse, reason: '파일 탓 거절은 그 파일을 두지 않는다');
      expect(job.stashedNote, isNull);
      // 엔진이 받은 파일로 원본을 채우면(갈래 1 고침 — 표 있는 저장소) 보통의 넣기 그대로(폴더에 들임 · 알림 없음).
      engine.answer = (_) => {'ok': true, 'data': {'rewrote': ['reed-t'], 'added': [], 'removed': [], 'first_pos': 2, 'ms': 30, 'replaced': [{'id': 'reed', 'old_version': '1.0.0', 'new_version': '1.0.0', 'old_sha256': null, 'new_sha256': 'c' * 64}]}};
      final filled = await flow.run(db: store.db, files: [reed], stored: const {'east-asia-base', 'reed'});
      expect(filled.ok, isTrue, reason: job.lines.join('\n'));
      expect(job.notes, isEmpty, reason: '원본 채우기(old_sha256 null)는 알리지 않는다(판정 R43)');
      expect(File(store.inDlc('reed-v1.0.0.htpack')).existsSync(), isTrue);
    });

    test('원본 없는 DLC 둘 가운데 하나의 .htpack만 고르면 그것만 DLC 폴더에 두고 나머지도 넣으라고 알린다 — 둘째를 넣으면 그 말이 빠진다(휴대폰 · 11c 검토)', () async {
      final (scene, _, _) = makePackScene();
      final reed = writeDlc(store.downloaded('reed-v1.0.0.htpack'), 'reed', '1.0.0', name: '갈대 기록집');
      final moss = writeDlc(store.downloaded('moss-v2.1.0.htpack'), 'moss', '2.1.0', name: '이끼 기록집');
      final kept = File('${store.db}.seed-kept')..writeAsStringSync('0.0.4');
      final job = DlcJob()
        ..phone = true
        ..packFacts.addAll(const {'reed': DlcPackFacts(version: '1.0.0', original: false), 'moss': DlcPackFacts(version: '2.1.0', original: false)});
      final (flow, engine, _) = flowFor(job, scene);
      engine.answer = (_) => {'ok': false, 'error': '달력 표가 없는 옛 저장소입니다', 'code': 'calendar'};
      const inStore = {'east-asia-base', 'reed', 'moss'};
      expect((await flow.run(db: store.db, files: [reed], stored: inStore)).ok, isFalse);
      expect(File(store.inDlc(dlcOriginalFileName('reed', '1.0.0'))).existsSync(), isTrue);
      expect(File(store.inDlc(dlcOriginalFileName('moss', '2.1.0'))).existsSync(), isFalse);
      expect(kept.existsSync(), isFalse);
      expect(job.status, allOf(startsWith('«갈대 기록집»의 원본(.htpack)을 DLC 폴더에 두었습니다'), contains('«moss»'), contains('함께 골라')),
          reason: '시드 잇기는 원본 없는 DLC가 하나라도 원본이 없으면 다시 지킨다 — 나머지도 넣어야 옮겨진다');
      expect(job.status, isNot(contains('앱을 다시 켜면')), reason: "남은 것이 있으면 '다시 켜면 옮깁니다'는 맞지 않는다(① 넘김)");
      // 둘째(표식은 이미 지워짐) — 휴대폰은 여전히 '다시 켜면', 남은 것이 없으니 '도 넣어 주세요'가 없다.
      expect((await flow.run(db: store.db, files: [moss], stored: inStore)).ok, isFalse);
      expect(File(store.inDlc(dlcOriginalFileName('moss', '2.1.0'))).existsSync(), isTrue);
      expect(job.status, '«이끼 기록집»의 원본(.htpack)을 DLC 폴더에 두었습니다 — 이 저장소에는 지금 넣을 수 없어 앱을 다시 켜면 새 판 자료로 옮기며 함께 넣습니다.');
    });

    test('COMMIT 뒤 다시 열기만 실패했으면(committed) 저장소를 다시 열고 뼈대를 처음부터 읽는다', () async {
      final (scene, _, _) = makePackScene();
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      engine.answer = (_) => {'ok': false, 'error': '쓰기는 끝나 저장소 파일이 바뀌었지만 저장소를 다시 열지 못해 닫아 두었습니다 — 다시 열어 주세요: 디스크', 'committed': true};
      final done = await flow.run(db: store.db, files: [store.picked]);
      expect(done.ok, isTrue);
      expect(done.reopen, isTrue);
      expect(engine.commands, ['write', 'open'], reason: '이때만 다시 연다');
      expect(reloads, [0], reason: '타일은 모두 버린다');
      expect(File(store.inDlc('korean-timeline-v1.0.5.htpack')).existsSync(), isTrue, reason: '저장소가 바뀌었으니 폴더도 맞춘다');
      // 엔진의 '…다시 열어 주세요'(앱이 스스로 다시 연다)는 알리지 않고 일에 보관한다(② Minor 5).
      expect(job.notes.join('\n'), isNot(contains('다시 열어 주세요')));
      expect(job.lastDetail, contains('다시 열지 못해'));
    });

    test('모두 끄기의 한 걸음이 COMMIT 뒤 다시 열기에 실패하면(committed) 다음 걸음 없이 멈추고 다시 연다 — 남은 것은 끄지 않았다고 알린다(② Minor 5)', () async {
      final (scene, _, _) = makePackScene();
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      engine.answer = (_) => {'ok': false, 'error': '쓰기는 끝나 저장소 파일이 바뀌었지만 저장소를 다시 열지 못해 닫아 두었습니다 — 다시 열어 주세요: 디스크', 'committed': true};
      final done = await flow.run(db: store.db, offKeys: ['haesol', 'silverbay'], stored: stored, offCards: {'haesol': {'name': '해솔 기록집'}, 'silverbay': {'name': '은빛 나루'}});
      expect([for (final r in engine.requests) r['id']], ['haesol'], reason: '닫힌 저장소에 다음 걸음을 보내지 않는다');
      expect(engine.commands, ['write', 'open']);
      expect(reloads, [0]);
      expect(done.ok, isFalse);
      expect(DlcHidden.read(store.db).off, {'haesol'}, reason: '고쳐 쓴 걸음(해솔)은 끈 목록에');
      expect(job.status, allOf(contains('«은빛 나루»'), contains('끄지 않았습니다')));
    });

    test('끄기 = remove_pack delete:false(원본은 보관함) · 켜기 = add_pack ids(보관함) — 끝난 뒤에만 끈 목록(카드)을 적는다', () async {
      final (scene, _, _) = makePackScene();
      const card = {'name': '해솔 기록집', 'version': '1.0.0', 'events': 2, 'periods': 1, 'tracks': [{'key': 'haesol-t', 'name': '해솔 갈래', 'color': 0x7a95c2, 'rows': 2}], 'shared': []};
      Map<String, bool>? during;
      final job = DlcJob();
      // 뼈대 다시 읽기는 새 끈 목록을 보고 켠 DLC를 정한다(앱 틀의 `_reloadStore`) — 다시 읽기 **전에** 끈 목록을 읽어 두어야 한다.
      final offAtReload = <Set<String>>[];
      final engine = _Engine();
      final flow = DlcApplyFlow(
        job: job, scene: scene, engineCall: engine.call,
        engineApply: (request) {
          during = job.toggling;
          return engine.apply(scene, request);
        },
        reload: (keepBefore) async => offAtReload.add({...job.hidden.off}),
      );
      expect((await flow.run(db: store.db, offKeys: ['haesol'], stored: stored, offCards: {'haesol': card})).ok, isTrue, reason: job.lines.join('\n'));
      expect(engine.requests.single, {'op': 'remove_pack', 'id': 'haesol', 'delete': false, 'path': store.db});
      expect(during, {'haesol': false});
      expect(File(store.haesol).existsSync(), isTrue, reason: '끈 DLC의 파일은 남긴다(판을 올려 보관함이 사라져도 다시 켤 원본)');
      expect(offAtReload.single, {'haesol'}, reason: '다시 읽을 때 이미 새 끈 목록');
      expect(job.hidden.cards['haesol'], card, reason: '카드는 끄기 전 뼈대에서 뜬 값');
      expect(DlcFolderState.read(store.db)!.off, {'haesol'}, reason: 'COMMIT 직후 묘비(끈 것) — 끈 목록 쓰기가 실패해도 판을 올린 뒤 다시 들이지 않게');
      expect(job.toggling, {'haesol': false}, reason: '성공하면 앱 틀이 다시 읽을 때(reset)까지 스위치는 부탁한 쪽');
      job.reset();

      // 켜기: 보관함에 있으면 그것으로(ids) · 끈 목록에서 내린다.
      engine.kept = [{'id': 'haesol', 'name': '해솔 기록집', 'version': '1.0.0', 'bytes': 99}];
      expect((await flow.run(db: store.db, onKeys: ['haesol'], stored: {'east-asia-base', 'silverbay'})).ok, isTrue, reason: job.lines.join('\n'));
      expect(engine.commands, ['write', 'kept_packs', 'write']);
      expect(engine.requests.last, {'op': 'add_pack', 'ids': ['haesol'], 'path': store.db});
      expect(offAtReload.last, isEmpty, reason: '켠 DLC가 끈 목록에 남은 채 다시 읽으면 화면에서 꺼진 채로 들어온다');
      expect(DlcHidden.read(store.db).off, isEmpty);
      expect(job.turnedOn, {'haesol'});
      expect(DlcFolderState.read(store.db)!.off, isEmpty, reason: '켜면 묘비에서 뺀다');

      // 보관함에 없으면(판을 올려 저장소가 바뀜) DLC 폴더의 그 파일로(files) — 판이 가장 높은 것.
      writeDlc(store.inDlc('haesol-v1.1.0.htpack'), 'haesol', '1.1.0');
      engine.kept = [];
      expect((await flow.run(db: store.db, onKeys: ['haesol'], stored: {'east-asia-base'})).ok, isTrue);
      expect(engine.requests.last, {'op': 'add_pack', 'files': [File(store.inDlc('haesol-v1.1.0.htpack')).absolute.path], 'path': store.db});
      // 둘 다 없으면 엔진에 닿지 않고 되찾는 길을 알린다.
      final writes = engine.requests.length;
      expect((await flow.run(db: store.db, onKeys: ['moonbay'], stored: {'east-asia-base'})).ok, isFalse);
      expect(engine.requests, hasLength(writes));
      expect(job.status, contains("'파일에서 더하기'로 다시 넣어 주세요"));
    });

    test('끄기 답에 그 DLC가 deleted로 오면(남길 원본이 없어 지워짐 — 뜻밖의 경우) 쉬운 말로 알린다(고침 1회차 I-1)', () async {
      final (scene, _, _) = makePackScene();
      final job = DlcJob();
      final (flow, engine, _) = flowFor(job, scene);
      engine.answer = (_) => {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['moon-t'], 'first_pos': 2, 'ms': 30, 'kept': [], 'deleted': ['moonbay']}};
      final done = await flow.run(db: store.db, offKeys: ['moonbay'], stored: {...stored, 'moonbay'}, offCards: {'moonbay': {'name': '달물결 기록집'}});
      expect(done.ok, isTrue);
      expect(job.notes.single, contains('«달물결 기록집»'));
      expect(job.notes.single, contains('원본'));
      expect(job.notes.single, contains("'파일에서 더하기'"), reason: '되찾는 길');
    });

    test('모두 끄기 — DLC마다 remove_pack 하나씩, 하나가 실패하면 거기서 멈추고 앞의 것만 끈 목록에(저장소는 앞의 것만 고쳐 씀)', () async {
      final (scene, _, _) = makePackScene();
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      engine.answer = (request) => request['id'] == 'silverbay'
          ? {'ok': false, 'error': '빼라는 DLC «silverbay»가 지금 저장소에 없습니다'}
          : {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['haesol-t'], 'first_pos': 2, 'ms': 30}};
      final done = await flow.run(db: store.db, offKeys: ['haesol', 'silverbay'], stored: stored, offCards: {'haesol': {'name': '해솔 기록집'}, 'silverbay': {'name': '은빛 나루'}});
      expect(done.ok, isFalse);
      expect(done.storeChanged, isTrue, reason: '앞의 것(해솔)은 고쳐 썼다 — 앱 틀이 뼈대를 다시 읽는다');
      expect(reloads, [2]);
      expect([for (final r in engine.requests) r['id']], ['haesol', 'silverbay']);
      expect(DlcHidden.read(store.db).off, {'haesol'});
      expect(DlcFolderState.read(store.db)!.off, {'haesol'});
      // 끈 것과 멈춘 자리를 함께 알린다(② Minor 6).
      expect(job.status, '«해솔 기록집»은(는) 껐고 «은빛 나루»에서 멈췄습니다: DLC를 빼지 못했습니다 — 빼라는 DLC «silverbay»가 지금 저장소에 없습니다');
    });

    test('모두 켜기 — 원본이 보관함에도 DLC 폴더에도 없는 DLC만 건너뛰고 나머지는 켠다(② Minor 6)', () async {
      final (scene, _, _) = makePackScene();
      store.hiddenFile.writeAsStringSync(jsonEncode({'version': 1, 'off': ['moonbay', 'reed'], 'baseRemoved': false, 'cards': {'moonbay': {'name': '달물결 기록집'}, 'reed': {'name': '갈대 기록집'}}}));
      final job = DlcJob()..loadHidden(store.db);
      final (flow, engine, _) = flowFor(job, scene);
      engine.kept = [{'id': 'moonbay', 'name': '달물결 기록집', 'version': '2.0.0', 'bytes': 9}];
      final done = await flow.run(db: store.db, onKeys: ['moonbay', 'reed'], stored: stored);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(engine.requests.single, {'op': 'add_pack', 'ids': ['moonbay'], 'path': store.db});
      expect(DlcHidden.read(store.db).off, {'reed'}, reason: '건너뛴 것은 꺼진 채');
      expect(job.notes.join('\n'), allOf(contains('«갈대 기록집»'), contains("'파일에서 더하기'")));
    });

    test('모두 끄기가 도중에 멈춘 뒤 다시 읽은 뼈대 — 끈 것은 끈 채(끈 목록) · 아직 저장소에 남은 것은 화면에서도 켠다(끈 목록에 없어 다음 실행에 켜지므로 — 11c 검토)', () {
      // 앱 틀은 쓰기 전에 화면에서 둘 다 먼저 접는다(그래서 옮겨 적을 것의 wasOn에 둘 다 빠짐) → 엔진은 해솔만 빼고 은빛 나루에서 멈춤 → 뼈대를 다시 읽는다.
      final turnOn = dlcTurnOnAfterReload(onKeys: const [], offKeys: const ['haesol', 'silverbay'], turnedOn: const {});
      final on = dlcEnabledAfterReload(
        packOf: const {'east-asia-base': 1, 'silverbay': 3},
        off: const {'haesol'},
        wasOn: const {'east-asia-base'},
        known: const {'east-asia-base', 'haesol', 'silverbay'},
        turnOn: turnOn,
      );
      expect(on, {1, 3}, reason: '은빛 나루는 저장소에 켜진 채 남았다 — 화면에서 꺼진 채 두면 끈 목록에 없어 다음 실행과 어긋난다');
      // 끝까지 끈 것은 저장소에 없어(뼈대에 없음) 켜지 않는다 · 켜기 부탁과 더하기로 끈 목록에서 뺀 것은 켠다.
      expect(dlcEnabledAfterReload(packOf: const {'east-asia-base': 1}, off: const {'haesol', 'silverbay'}, wasOn: const {'east-asia-base'}, known: const {'east-asia-base', 'haesol', 'silverbay'}, turnOn: turnOn), {1});
      expect(dlcTurnOnAfterReload(onKeys: const ['moonbay'], offKeys: const [], turnedOn: const {'reed'}), {'moonbay', 'reed'});
    });

    test('깨진 끈 목록(hidden.json)은 덮어쓰지 않는다 — 끄기 · 켜기 · 화면에서만 끄기 모두 · 판 올림 뒤 다시 들이기(R32)는 계속 막힌다(판정 R60 I-3)', () async {
      final (scene, _, _) = makePackScene();
      store.hiddenFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"off":["moonbay"], 깨짐');
      final broken = store.hiddenFile.readAsStringSync();
      expect(() => DlcHidden.save(store.db, {'version': 1, 'off': ['haesol'], 'baseRemoved': false, 'cards': {}}), throwsA(isA<StateError>()));
      expect(() => rememberScreenOff(store.db, keyedLayout()..enable({1})), throwsA(isA<StateError>()));
      final job = DlcJob();
      final (flow, engine, _) = flowFor(job, scene);
      final done = await flow.run(db: store.db, offKeys: ['haesol'], stored: stored, offCards: {'haesol': {'name': '해솔 기록집'}});
      expect(done.ok, isTrue, reason: '저장소는 고쳐 썼다');
      expect(job.notes.single, contains('끈 DLC 목록(hidden.json)'));
      expect(store.hiddenFile.readAsStringSync(), broken, reason: '깨진 목록을 새 목록으로 덮으면 거기 적힌 끈 DLC가 판 올림 뒤 켜진 채 되들어온다');
      expect(DlcFolderSync.blocked(store.db), isNotNull, reason: 'R32는 계속 막힌다');
      // 켜기(끈 목록에서 빼기)도 덮지 않는다.
      job.reset();
      await flow.run(db: store.db, files: [store.picked], stored: stored);
      expect(store.hiddenFile.readAsStringSync(), broken);
      expect(engine.requests, isNotEmpty);
    });

    test('켠 DLC를 끈 목록(hidden.json)에서 빼지 못하면(쓰기 실패) 화면에서는 꺼진 채라는 것과 할 일을 말한다(② Minor 7 — 알림과 화면이 맞게)', () async {
      if (!Platform.isWindows) return markTestSkipped('읽기 전용 파일 흉내는 Windows의 attrib');
      final (scene, _, _) = makePackScene();
      store.hiddenFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'version': 1, 'off': ['moonbay'], 'baseRemoved': false, 'cards': {'moonbay': {'name': '달물결 기록집'}}}));
      await Process.run('attrib', ['+R', store.hiddenFile.path]);
      addTearDown(() => Process.runSync('attrib', ['-R', store.hiddenFile.path]));
      final job = DlcJob()..loadHidden(store.db);
      final (flow, engine, _) = flowFor(job, scene);
      engine.kept = [{'id': 'moonbay', 'name': '달물결 기록집', 'version': '2.0.0', 'bytes': 9}];
      expect((await flow.run(db: store.db, onKeys: ['moonbay'], stored: stored)).ok, isTrue);
      expect(job.turnedOn, isEmpty, reason: '끈 목록에 남아 다시 읽은 화면에서도 꺼진 채');
      expect(job.notes.join('\n'), allOf(contains('«달물결 기록집»'), contains('화면에서는 꺼진 채'), contains('hidden.json')));
    });

    test('알림 정리 — 도는 동안 온 알림은 버리지 않고 끝난 뒤에 남긴다 · 같은 알림은 한 번 · 화면에서만 끈 기억은 엔진이 켜고 끄는 DLC를 건드리지 않는다(② Minor 3 · 7)', () async {
      final job = DlcJob();
      expect(job.hold('DLC 폴더를 살피는 중…'), isTrue);
      job.notice('고른 파일 하나는 DLC 파일이 아닙니다.');
      job.release();
      expect(job.notes, ['고른 파일 하나는 DLC 파일이 아닙니다.'], reason: '도는 동안 온 알림(고르기 창의 까닭 등)을 버리지 않는다');
      // 잡아 둔 일이 이어서 넣기(apply — 시작하며 알림을 비움)로 가도 도는 동안 온 알림은 끝난 뒤에 남는다(R32 put · 고침 2회차 ② Minor 3).
      expect(job.hold('DLC 폴더를 살피는 중…'), isTrue);
      job.notice('도는 동안 온 알림');
      job.applier = (request) async => {'ok': true, 'data': {'rewrote': [], 'added': ['x'], 'removed': [], 'first_pos': 0, 'ms': 1}};
      expect((await job.apply(db: store.db, files: [store.picked])).ok, isTrue);
      expect(job.notes, contains('도는 동안 온 알림'));
      job.applier = null;
      // sync.json이 깨진 채 빼기: 엔진 앞 · COMMIT 뒤 두 번 적으려다 실패해도 알림은 한 번.
      final (scene, _, _) = makePackScene();
      Directory(store.inDlc('')).createSync(recursive: true);
      File(store.inDlc('sync.json')).writeAsStringSync('{깨짐');
      final (flow, _, _) = flowFor(job, scene);
      expect((await flow.run(db: store.db, removeKey: 'haesol', stored: stored)).ok, isTrue);
      expect(job.notes.where((n) => n.contains('sync.json')), hasLength(1));
      // 엔진이 끄는 중인 해솔(화면에서 먼저 접힘)은 화면에서만 끈 기억에 넣지 않는다 — 엔진 끄기가 실패하면 다음 실행에 화면에서만 꺼진 채 열리지 않게.
      final layout = keyedLayout()..enable({1, 3});
      rememberScreenOff(store.db, layout, busy: const {'haesol'});
      expect(DlcHidden.read(store.db).off, isNot(contains('haesol')));
      rememberScreenOff(store.db, layout);
      expect(DlcHidden.read(store.db).off, contains('haesol'));
      // 보관함 카드는 지운 묘비의 id를 거른다(예전 판 앱이 꺼 둔 채 지워 보관함에 원본이 남은 것 — ① m-4).
      job.keptFrom({'ok': true, 'data': [{'id': 'old', 'name': '옛 DLC', 'version': '1'}, {'id': 'reed', 'name': '갈대', 'version': '1'}]}, gone: const {'old'});
      expect(job.kept.map((k) => k.id), ['reed']);
    });

    test('끈 목록(hidden.json)을 적지 못하면 저장소는 고쳐 쓴 채 되찾는 길(DLC 폴더의 그 파일을 파일에서 더하기로)을 알린다(8 검토)', () async {
      final (scene, _, _) = makePackScene();
      // 장면: hidden.json 자리를 폴더가 차지해 이름 바꾸기가 늘 실패한다(재시도도 실패).
      Directory(store.inDlc('hidden.json')).createSync();
      final job = DlcJob();
      final (flow, _, _) = flowFor(job, scene);
      final done = await flow.run(db: store.db, offKeys: ['haesol'], stored: stored, offCards: {'haesol': {'name': '해솔 기록집'}});
      expect(done.ok, isTrue, reason: '저장소는 고쳐 썼다');
      expect(job.notes.single, contains('끈 DLC 목록(hidden.json)을 적지 못했습니다'));
      expect(job.notes.single, contains('파일에서 더하기'));
      expect(job.notes.single, contains('${store.dir.path}${Platform.pathSeparator}DLC'), reason: '그 파일이 있는 폴더');
      expect(DlcFolderState.read(store.db)!.off, {'haesol'}, reason: '묘비는 남았다(판을 올려도 되살아나지 않음)');
    });

    test('꺼 둔(저장소에 없는) DLC 지우기 = remove_pack delete:true로 보관함의 원본까지(판정 R42) · 조합 그대로라 다시 읽지 않음 · 보관함에 없거나 모르면 폴더와 끈 목록만 · 화면에서만 끈 DLC를 켜도 엔진 없음', () async {
      final (scene, _, _) = makePackScene();
      store.hiddenFile.writeAsStringSync(jsonEncode({'version': 1, 'off': ['haesol', 'silverbay'], 'baseRemoved': false, 'cards': {'haesol': {'name': '해솔 기록집'}}}));
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      // 엔진의 답(보관함에만 있는 id의 delete:true — 배치 · apply 없이): 바뀐 트랙 없음 · layouts 0 · first_pos −1 · deleted.
      engine.kept = [{'id': 'haesol', 'name': '해솔 기록집', 'version': '1.0.0', 'bytes': 99}];
      job.keptFrom({'ok': true, 'data': engine.kept}); // 앱 틀이 열 때 읽어 둔 보관함(카드)
      engine.answer = (_) => {'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': [], 'globals': false, 'first_pos': -1, 'layouts': 0, 'ms': 3.0, 'kept': [], 'deleted': ['haesol']}};
      final done = await flow.run(db: store.db, removeKey: 'haesol', stored: {'east-asia-base', 'silverbay'});
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(engine.commands, ['kept_packs', 'write'], reason: '보관함을 보고 그 id면 엔진에');
      expect(engine.requests.single, {'op': 'remove_pack', 'id': 'haesol', 'delete': true, 'path': store.db});
      expect(done.storeChanged, isFalse, reason: '조합 · 배치는 그대로(보관함만 바뀜) — 뼈대를 다시 읽지 않는다(검색 · 카드가 닫히지 않게)');
      expect(reloads, isEmpty);
      expect(scene.storeWriting, isFalse);
      expect(File(store.haesol).existsSync(), isFalse);
      expect(DlcHidden.read(store.db).off, {'silverbay'});
      expect(DlcFolderState.read(store.db)!.removed, {'haesol'}, reason: '끈 DLC를 지워도 묘비(파일 지우기가 실패해도 다시 들이지 않게)');
      expect(job.lines.last, isNot(startsWith('마쳤습니다')), reason: "바뀐 트랙이 없는 일에 '마쳤습니다 — 바뀐 트랙 없음'을 적지 않는다");
      // 뼈대를 다시 읽지 않으니 보관함 카드도 그 자리에서 뺀다(② I-1 — 지운 뒤 카드가 남아 켜면 '원본 없음'이 되지 않게).
      expect(job.kept.map((k) => k.id), isNot(contains('haesol')));
      expect(DlcCardInfo.of(scene.layout, hidden: job.hidden, kept: job.kept).map((c) => c.key), isNot(contains('haesol')), reason: '지운 뒤 카드 없음');
      // 보관함에 없는 꺼 둔 DLC(예전 길로 끈 것 — 원본은 폴더에만) · 보관함을 읽지 못함(모름): 엔진에 보내지 않는다(없는 id면 엔진이 거절해 지우기가 막힌다).
      for (final kept in [<Map<String, dynamic>>[], null]) {
        store.hiddenFile.writeAsStringSync(jsonEncode({'version': 1, 'off': ['moonbay', 'silverbay'], 'baseRemoved': false, 'cards': {'moonbay': {'name': '달물결 기록집'}}}));
        engine
          ..kept = kept
          ..commands.clear()
          ..requests.clear();
        final old = await flow.run(db: store.db, removeKey: 'moonbay', stored: {'east-asia-base', 'silverbay'});
        expect(old.ok, isTrue, reason: job.lines.join('\n'));
        expect(engine.commands, ['kept_packs'], reason: '$kept');
        expect(DlcHidden.read(store.db).off, {'silverbay'});
        expect(DlcFolderState.read(store.db)!.removed, containsAll(['haesol', 'moonbay']));
      }
      expect(reloads, isEmpty);
      // 저장소에 든 채 화면에서만 끈 것(휴대폰 10a · 옛 길에서 다 끈 것)을 켜면 끈 목록에서만 뺀다.
      engine.commands.clear();
      expect((await flow.run(db: store.db, onKeys: ['silverbay'], stored: {'east-asia-base', 'silverbay'})).ok, isTrue);
      expect(engine.commands, isEmpty);
      expect(DlcHidden.read(store.db).off, isEmpty);
      expect(job.turnedOn, {'silverbay'}, reason: '앱 틀이 화면에서 켠다');
    });

    test('메이커 미리보기: 작업본이 서재의 같은 id 높은 판을 이긴다 — add_pack prefer_given(판정 R39) · replaced 알림 없음 · Node 없음', () async {
      final (scene, _, _) = makePackScene();
      // 서재(의 임시 사본)에는 KoreanTimeLine 1.0.5가 들어 있고, 메이커의 작업본은 판이 낮은 1.0.3이다(고치는 중인 작업본).
      final work = writeDlc(store.downloaded('작업본.htpack'), 'korean-timeline', '1.0.3', name: 'Tigers of the East');
      final job = DlcJob();
      final (flow, engine, reloads) = flowFor(job, scene);
      // 엔진 흉내: prefer_given이 없으면 낮은 판은 code version으로 거절(판 대조) · 있으면 판과 상관없이 바꿔 넣고 replaced.
      engine.answer = (request) => request['prefer_given'] == true
          ? {'ok': true, 'data': {'rewrote': ['korea'], 'added': [], 'removed': [], 'first_pos': 4, 'ms': 90, 'replaced': [{'id': 'korean-timeline', 'old_version': '1.0.5', 'new_version': '1.0.3', 'old_sha256': 'a' * 64, 'new_sha256': 'b' * 64}]}}
          : {'ok': false, 'error': '«Tigers of the East»의 판이 저장소보다 낮습니다(저장소 v1.0.5 · 받은 v1.0.3)', 'code': 'version'};
      final plain = await flow.run(db: store.db, files: [work], stored: stored);
      expect(plain.ok, isFalse, reason: '보통의 더하기는 낮은 판을 거절한다');
      expect(job.status, startsWith('지금 든(꺼 둔 것 포함) 것보다 낮은 판이라 넣지 않았습니다'));
      final done = await flow.run(db: store.db, files: [work], stored: stored, preferGiven: true);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(engine.requests.last, {'op': 'add_pack', 'files': [File(work).absolute.path], 'prefer_given': true, 'path': store.db});
      expect(reloads, [4]);
      expect(job.notes, isEmpty, reason: "미리보기는 판과 상관없이 작업본으로 바꾼다 — '같은 판의 다른 파일' 알림은 하지 않는다");
      expect(engine.commands, ['write', 'write'], reason: '닫았다 다시 열지 않는다(바꿔 넣기 없음)');
    });

    test('메이커 미리보기의 서재 사본은 저장소 일지(-wal · -journal)와 DLC 폴더를 함께 옮긴다 — 쓰다 멈춘 거래가 사본에서 되감기게(판정 R60 M-10)', () async {
      final library = Directory.systemTemp.createTempSync('ht-preview-src-');
      final copyDir = Directory.systemTemp.createTempSync('ht-preview-dst-');
      addTearDown(() {
        for (final d in [library, copyDir]) {
          if (d.existsSync()) d.deleteSync(recursive: true);
        }
      });
      final sep = Platform.pathSeparator;
      final db = '${library.path}${sep}archive.db';
      for (final (tail, text) in const [('', '저장소'), ('-wal', '일지 wal'), ('-journal', '되감기 일지')]) {
        File('$db$tail').writeAsStringSync(text);
      }
      writeDlc('${library.path}${sep}DLC${sep}reed-v1.0.0.htpack', 'reed', '1.0.0');
      File('${library.path}${sep}DLC${sep}reed-v1.0.0.htpack.1700000000000000.tmp').writeAsStringSync('반쯤 쓴 사본');
      final copied = await copyLibraryForPreview(db, copyDir);
      expect(copied, '${copyDir.path}${sep}archive.db');
      expect(File(copied).readAsStringSync(), '저장소');
      expect(File('$copied-wal').readAsStringSync(), '일지 wal');
      expect(File('$copied-journal').readAsStringSync(), '되감기 일지', reason: '없으면 사본이 반쯤 쓴 거래를 그대로 연다');
      expect(File('${copyDir.path}${sep}DLC${sep}reed-v1.0.0.htpack').existsSync(), isTrue);
      expect(File('${copyDir.path}${sep}DLC${sep}reed-v1.0.0.htpack.1700000000000000.tmp').existsSync(), isFalse, reason: '반쯤 쓴 임시 파일은 옮기지 않는다(① m-5)');
    });

    test('어느 길로 가나 — 바탕(첫 DLC)이 아니면 엔진 · 바탕은 화면에서만(판정 R43) · 미리보기도 엔진 · 원본 없이 든 DLC의 끄기는 화면에서만', () {
      const base = 'east-asia-base';
      final keys = [base, 'haesol', 'silverbay'];
      DlcRoute route({List<String> packKeys = const [], DlcHidden hidden = DlcHidden.none, String? remove, List<String> off = const [], List<String> on = const [], bool preview = false}) =>
          dlcRoute(packKeys: packKeys.isEmpty ? keys : packKeys, hidden: hidden, baseKey: base, removeKey: remove, offKeys: off, onKeys: on, preview: preview);
      expect(route(), DlcRoute.engine, reason: 'DLC 파일 더하기는 엔진(add_pack) — 휴대폰 · 도구 없는 실행본도');
      expect(route(remove: 'haesol'), DlcRoute.engine);
      expect(route(off: ['haesol']), DlcRoute.engine);
      expect(route(on: ['moonbay'], hidden: const DlcHidden(off: {'moonbay'})), DlcRoute.engine, reason: '끈 DLC(보관함)를 켜기');
      expect(route(off: ['silverbay'], hidden: const DlcHidden(off: {'haesol'})), DlcRoute.engine, reason: '화면에서만 끈 DLC가 저장소에 남아도 엔진');
      expect(route(packKeys: ['lantern', 'haesol']), DlcRoute.engine, reason: '바탕이 기본팩이 아닌 저장소(견본 단독 · 판타지 APK)도 엔진');
      expect(route(packKeys: ['haesol'], hidden: const DlcHidden(baseRemoved: true)), DlcRoute.engine, reason: '기본팩을 뺀 옛 서재에도 엔진으로 더한다');
      // 판정 R43: 엔진은 바탕을 빼지 못한다 — 바탕 켜고 끄기는 화면에서만, 바탕 빼기는 없음(Node 다시 짓기 길은 과제 11c에서 걷었다).
      expect(route(off: [base]), DlcRoute.screen);
      expect(route(on: [base]), DlcRoute.screen, reason: '화면에서만 끈 바탕 켜기');
      expect(route(remove: base), DlcRoute.none, reason: '바탕은 뺄 수 없다');
      expect(route(off: ['lantern'], packKeys: ['lantern', 'haesol']), DlcRoute.screen, reason: '다른 바탕도 화면에서만');
      expect(route(remove: 'lantern', packKeys: ['lantern', 'haesol']), DlcRoute.none);
      expect(route(on: [base], packKeys: ['haesol'], hidden: const DlcHidden(baseRemoved: true)), DlcRoute.none, reason: '옛 다시 짓기 길에서 뺀 기본팩은 켤 길이 없다(파일에서 더하기로 넣음)');
      // 판정 R60 I-1: 동아시아 id를 늘 바탕으로 다루지 않는다 — 등불 바탕 저장소(판타지 APK)에 넣은 동아시아 DLC는 보통 DLC(끄고 켜고 지움 — 엔진).
      final lantern = ['lantern-chronicle', base, 'korean-timeline'];
      expect(route(packKeys: lantern, off: [base]), DlcRoute.engine);
      expect(route(packKeys: lantern, remove: base), DlcRoute.engine);
      expect(route(packKeys: const ['lantern-chronicle', 'korean-timeline'], hidden: const DlcHidden(off: {base}), on: [base]), DlcRoute.engine, reason: '꺼 둔(보관함) 동아시아를 다시 켠다');
      expect(route(packKeys: const ['lantern-chronicle', 'korean-timeline'], hidden: const DlcHidden(off: {base}), remove: base), DlcRoute.engine);
      expect(route(packKeys: lantern, off: ['lantern-chronicle']), DlcRoute.screen, reason: '바탕은 저장소의 첫 DLC');
      expect(route(off: [base, 'haesol']), DlcRoute.screen, reason: '바탕이 섞이면 바탕은 화면에서 · 나머지는 앱 틀이 따로(toggleDlcs) — 길 하나로는 화면');
      expect(route(packKeys: const ['x'], preview: true), DlcRoute.engine, reason: '메이커 미리보기도 엔진(add_pack prefer_given — 판정 R39)');
      expect(DlcRoute.values, [DlcRoute.engine, DlcRoute.screen, DlcRoute.none], reason: '다시 짓기 길은 없다(과제 11c)');
      expect(dlcRouteRefusal(removeKey: base), contains('바탕 DLC(저장소의 첫 DLC)는 뺄 수 없습니다'));
      // 원본 없이 든 DLC(예전 메이커 배치로만 넣은 것 — 카드의 original 거짓)의 끄기는 화면에서만(고침 1회차 I-1): 엔진이 빼면 남길 원본이 없어 지워진다.
      final layoutCards = keyedLayout();
      final noOriginal = DlcCardInfo.of(layoutCards, facts: const {'haesol': DlcPackFacts(version: '1.0.0', original: false)}).firstWhere((c) => c.key == 'haesol');
      expect(noOriginal.original, isFalse);
      expect(dlcCardRoute(noOriginal, layoutCards, hidden: DlcHidden.none), DlcRoute.screen);
      expect(dlcCardRoute(noOriginal, layoutCards, hidden: DlcHidden.none, on: true), DlcRoute.engine, reason: '켜기(화면에서만 끈 것 — 저장소에 든 채)는 엔진 길(쓸 것 없이 끈 목록만)');
      expect(dlcCardRoute(noOriginal, layoutCards, hidden: DlcHidden.none, remove: true), DlcRoute.engine, reason: '지우기는 원본이 없어도 된다');
      expect(dlcScreenNote(noOriginal, layoutCards, hidden: DlcHidden.none), dlcNoOriginalOffText(noOriginal.name));
      expect(dlcNoOriginalOffText('해솔 기록집'), startsWith('«해솔 기록집»은(는) 원본(.htpack)이 없어 화면에서만 끕니다'), reason: '어느 DLC인지(② Minor 7)');
      // 실패한 켜고 끄기가 화면을 되돌리는 때 — 그사이 뼈대를 다시 읽지 않았을 때만(옛 번호를 새 뼈대에 씌우지 않게 · ② Minor 8).
      expect(dlcToggleShouldRestore(ok: false, reloaded: false), isTrue);
      expect(dlcToggleShouldRestore(ok: false, reloaded: true), isFalse);
      expect(dlcToggleShouldRestore(ok: true, reloaded: false), isFalse);
      // 원본 없는 바탕은 바탕의 알림이 먼저(10b 고침 재검토).
      final noOriginalBase = DlcCardInfo.of(layoutCards, facts: {layoutCards.packs.first.key: const DlcPackFacts(original: false)}).firstWhere((c) => c.key == layoutCards.packs.first.key);
      expect(dlcCardRoute(noOriginalBase, layoutCards, hidden: DlcHidden.none), DlcRoute.screen);
      expect(dlcScreenNote(noOriginalBase, layoutCards, hidden: DlcHidden.none), dlcScreenOnlyNote);
    });
  });

  group('DlcJob(뒷일)', () {
    test('끈 목록(DLC/hidden.json)을 읽는다 — 없거나 깨졌으면 비어 있다', () {
      final dir = Directory.systemTemp.createTempSync('ht-hidden-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = '${dir.path}${Platform.pathSeparator}archive.db';
      expect(DlcHidden.read(db).off, isEmpty);
      Directory('${dir.path}${Platform.pathSeparator}DLC').createSync();
      final file = File('${dir.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}hidden.json');
      file.writeAsStringSync('{깨진');
      expect(DlcHidden.read(db).off, isEmpty);
      file.writeAsStringSync(jsonEncode(hiddenJson));
      final hidden = DlcHidden.read(db);
      expect(hidden.off, {'moonbay', 'east-asia-base'});
      expect(hidden.baseRemoved, isFalse);
      expect(hidden.cards['moonbay']!['name'], '달물결 기록집');
    });

    test('도는 중에는 다시 부탁해도 거절한다 · 도는 동안 removingKey · toggling을 들고 끝나면 내린다(실패하면 스위치는 저장소의 값으로)', () async {
      final dir = Directory.systemTemp.createTempSync('ht-busy-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = '${dir.path}${Platform.pathSeparator}archive.db';
      final job = DlcJob();
      String? removing;
      final toggling = <Map<String, bool>>[];
      job.applier = (request) => Future.delayed(const Duration(milliseconds: 50), () {
        removing ??= job.removingKey;
        toggling.add(job.toggling);
        return {'ok': false, 'error': '흉내 거절'};
      });
      final first = job.apply(db: db, removeKey: 'test-starbrook', stored: const {'test-starbrook'});
      expect((await job.apply(db: db, offKeys: ['a'], stored: const {'a'})).ok, isFalse, reason: '도는 중');
      expect((await first).ok, isFalse);
      expect(removing, 'test-starbrook');
      expect(job.removingKey, '', reason: '끝나면 빼는 중 표시는 내린다');
      expect(job.status, 'DLC를 빼지 못했습니다 — 흉내 거절');
      final again = job.apply(db: db, offKeys: ['a', 'b'], onKeys: ['c'], stored: const {'a', 'b'});
      expect((await again).ok, isFalse);
      expect(toggling.last, {'a': false, 'b': false, 'c': true}, reason: '도는 동안 스위치는 부탁한 쪽에');
      expect(job.toggling, isEmpty, reason: '실패하면 스위치는 저장소의 값으로 돌아간다');
    });
  });

  group('휴대폰(안드로이드 갈래 — 과제 10a · 10b): 고르기 창 · 넣기 · 빼기 · 끄기 · 켜기는 컴퓨터와 같은 엔진 길 · 바탕만 화면에서만', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory dir;
    late String db;
    String at(String name) => '${dir.path}${Platform.pathSeparator}$name';
    setUp(() {
      dir = Directory.systemTemp.createTempSync('ht-phone-dlc-');
      db = at('archive.db');
      File(db).writeAsStringSync('휴대폰 저장소');
      Directory(at('dlc-in')).createSync();
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(dlcFilesChannel, null);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// `MainActivity.kt`의 흉내 — `pick`을 받아 [answer]를 돌려준다(앱 캐시 폴더 `dlc-in/`에 복사한 경로 목록 · 취소면 빈 목록).
    List<MethodCall> fakeChannel(Future<Object?> Function() answer) {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(dlcFilesChannel, (call) async {
        calls.add(call);
        return answer();
      });
      return calls;
    }

    /// 예전 배치 파일(.htlayout — 메이커 '아카이브용으로 내보내기')의 흉내 — 앱은 더 받지 않고 알림만(과제 11c).
    String oldLayoutIn(String name) => (File(at('dlc-in${Platform.pathSeparator}$name'))
          ..writeAsBytesSync(sealedPack(packKindLayout, jsonEncode({'name': '배치', 'packs': [{'id': 'east-asia-base', 'name': '별여울 기본팩'}, {'id': 'reed', 'name': '갈대 기록집', 'version': '1.0.0'}], 'tracks': []}))))
        .path;
    String packIn(String name, String id) =>
        (File(at('dlc-in${Platform.pathSeparator}$name'))..writeAsBytesSync(sealedPack(packKindDlc, jsonEncode({'format': 'history-timeline-dlc', 'id': id, 'version': '1.0.0'})))).path;

    test("예전 배치 파일(.htlayout): 채널이 건너뛴 이름으로 주면 '예전 배치 파일' 알림 · 경로로 와도 엔진에 닿지 않고 같은 알림(계획 P4 과제 11c)", () async {
      final layout = oldLayoutIn('reed-v1.0.0.htlayout'), pack = packIn('reed-v1.0.0.htpack', 'reed');
      final requests = <Map<String, dynamic>>[];
      final job = DlcJob()
        ..applier = (request) async {
          requests.add(request);
          return {'ok': true, 'data': {'rewrote': [], 'added': ['reed-t'], 'removed': [], 'first_pos': 3, 'ms': 120}};
        };
      // 지금의 MainActivity.kt: .htlayout은 옮기지 않고 이름만 skipped로 — 나머지(.htpack)만 넣는다.
      fakeChannel(() async => {'paths': [pack], 'skipped': ['reed-v1.0.0.htlayout']});
      await pickAndAddDlc((files) async {
        await job.apply(db: db, files: files);
      }, job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(requests.single, {'op': 'add_pack', 'files': [File(pack).absolute.path], 'path': db});
      expect(job.notes, contains(dlcOldLayoutText('reed-v1.0.0.htlayout')));
      // 경로로 와도(옛 실행본 · 컴퓨터의 --add-dlc) 엔진에 닿기 전에 같은 알림 — 저장소 그대로.
      requests.clear();
      final done = await job.apply(db: db, files: [layout, pack]);
      expect(done.ok, isFalse);
      expect(requests, isEmpty);
      expect(job.status, dlcOldLayoutText('reed-v1.0.0.htlayout'));
      expect(File(db).readAsStringSync(), '휴대폰 저장소');
    });

    test('고르기 취소(빈 목록) · 채널 없음 · 창을 못 엶 — 아무 일도 없다(못 엶은 까닭만 창 위 칸에)', () async {
      var added = 0;
      Future<void> add(List<String> files) async => added++;
      final job = DlcJob();
      Future<List<String>> android(void Function(String) e) => pickDlcFilesAndroid(onError: e);
      fakeChannel(() async => <String>[]);
      await pickAndAddDlc(add, job: job, pick: android);
      fakeChannel(() async => null);
      await pickAndAddDlc(add, job: job, pick: android);
      fakeChannel(() async => throw PlatformException(code: 'no-picker', message: '파일 고르기 창을 열 수 없습니다'));
      await pickAndAddDlc(add, job: job, pick: android);
      expect(job.notes, ['파일 고르기 창을 열 수 없습니다'], reason: '잡음을 푼 뒤에 알린다(잡은 동안의 알림이 버려지지 않게)');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(dlcFilesChannel, null);
      await pickAndAddDlc(add, job: job, pick: android);
      expect(added, 0);
      expect(job.notes, isEmpty, reason: '다음 고르기를 시작하면 지난 알림은 비운다(다른 일과 같은 규칙)');
      expect(job.running, isFalse);
      expect(File(db).readAsStringSync(), '휴대폰 저장소');
    });

    test('고르고 옮기는 동안 일을 잡아 두어 두 번째 고르기는 막힌다 — 옮기기가 앞 결과를 지우지 않게(8 검토 2회차 Important 2)', () async {
      final picked = packIn('reed-v1.0.0.htpack', 'reed');
      final answer = Completer<Object?>();
      final calls = fakeChannel(() => answer.future);
      final job = DlcJob(), got = <List<String>>[];
      final first = pickAndAddDlc((files) async => got.add(files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e), holding: '고른 파일을 앱 안으로 옮기는 중…');
      await Future<void>.delayed(Duration.zero);
      expect(job.running, isTrue);
      expect(job.status, '고른 파일을 앱 안으로 옮기는 중…');
      await pickAndAddDlc((files) async => got.add(files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(calls, hasLength(1), reason: '고르는 중의 두 번째 요청은 창을 다시 열지 않는다');
      answer.complete([picked]);
      await first;
      expect(got, [
        [picked],
      ]);
      expect(job.running, isFalse, reason: '끝나면 푼다');
      expect(job.status, isEmpty);
    });

    test('채널이 건너뛴 파일(DLC가 아닌 큰 파일 · 한도 넘음)을 함께 주면 그 까닭을 알리고 나머지만 넣는다(8 검토 2회차 Minor 2)', () async {
      final picked = packIn('reed-v1.0.0.htpack', 'reed');
      fakeChannel(() async => {
            'paths': [picked],
            'skipped': ['휴가-영상.mp4'],
          });
      final job = DlcJob(), got = <List<String>>[];
      await pickAndAddDlc((files) async => got.add(files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(got, [
        [picked],
      ]);
      expect(job.notes.single, contains('휴가-영상.mp4'));
      expect(job.notes.single, contains('64MB'));
    });

    test('거른 파일 알림은 더하기(새 일 — 알림을 비움)가 끝난 뒤에 남긴다 — 성공해도 거절돼도 보인다(덧붙임 N1)', () async {
      final picked = packIn('reed-v1.0.0.htpack', 'reed');
      Future<Object?> answer() async => {
            'paths': [picked],
            'skipped': ['휴가-영상.mp4'],
          };
      // 진짜 더하기(job.apply)가 일을 시작하며 알림을 비운다.
      fakeChannel(answer);
      final job = DlcJob()..applier = (request) async => {'ok': true, 'data': {'rewrote': [], 'added': ['reed-t'], 'removed': [], 'first_pos': 3, 'ms': 120}};
      await pickAndAddDlc((files) async => job.apply(db: db, files: files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(job.notes.any((n) => n.contains('휴가-영상.mp4')), isTrue, reason: '더하기가 끝난 뒤의 알림');
      // 거절(앱 틀의 이른 거절)도 같다 — 거절 까닭과 거른 파일이 함께 남는다.
      fakeChannel(answer);
      final refused = DlcJob();
      await pickAndAddDlc((files) async => refused.refuse('이 판의 휴대폰에서는 …'), job: refused, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(refused.notes, ['이 판의 휴대폰에서는 …', contains('휴가-영상.mp4')]);
    });

    test('끈 DLC를 파일로 다시 더하면 끈 목록에서 빼 켜진 채로 — 다시 켜도 꺼진 채이지 않게(덧붙임 N2) · 다른 끈 DLC는 그대로', () async {
      final pack = packIn('reed-v1.0.0.htpack', 'reed');
      File(at('DLC${Platform.pathSeparator}hidden.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'version': 1, 'off': ['east-asia-base', 'haesol', 'reed'], 'baseRemoved': false, 'cards': {'reed': {'name': '갈대 기록집'}}}));
      final job = DlcJob()..applier = (request) async => {'ok': true, 'data': {'rewrote': [], 'added': ['reed-t'], 'removed': [], 'first_pos': 3, 'ms': 120}};
      final done = await job.apply(db: db, files: [pack]);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      final hidden = DlcHidden.read(db);
      expect(hidden.off, {'east-asia-base', 'haesol'}, reason: '바탕 · 다른 끈 DLC는 그대로(사용자가 끈 것)');
      expect(hidden.cards.containsKey('reed'), isFalse);
      expect(job.turnedOn, {'reed'}, reason: '앱 틀이 뼈대를 다시 읽을 때 켤 DLC');
      // 실패하면 끈 목록 그대로.
      File(at('DLC${Platform.pathSeparator}hidden.json')).writeAsStringSync(jsonEncode({'version': 1, 'off': ['reed'], 'baseRemoved': false, 'cards': {}}));
      job.applier = (request) async => {'ok': false, 'error': '기본팩이 다릅니다', 'code': 'base'};
      expect((await job.apply(db: db, files: [pack])).ok, isFalse);
      expect(DlcHidden.read(db).off, {'reed'});
      expect(job.turnedOn, isEmpty);
    });

    test('알림은 앞의 알림을 지우지 않는다 · 실패 까닭도 알림으로 남긴다(8 검토 2회차 Minor 1)', () {
      final job = DlcJob();
      expect(job.refuse('엔진이 거절했습니다'), isTrue);
      job.notice(dlcScreenOnlyNote);
      expect(job.failed, isFalse);
      expect(job.notes, ['엔진이 거절했습니다', dlcScreenOnlyNote]);
      job.notice(dlcScreenOnlyNote);
      expect(job.notes, hasLength(2), reason: '같은 알림은 한 번');
    });

    test('화면에서만 끌 때도 카드를 끈 목록에 적는다(판 올림으로 저장소에서 빠져도 창에 남게 — 판정 R60 M-6) · 켜면 카드도 뺀다', () {
      final layout = keyedLayout()..enable({1, 3});
      const card = {'name': '해솔 기록집', 'version': '1.0.0', 'events': 2, 'periods': 0, 'tracks': [], 'shared': []};
      rememberScreenOff(db, layout, cards: const {'haesol': card, 'silverbay': {'name': '은빛 나루'}});
      expect(DlcHidden.read(db).off, {'haesol'});
      expect(DlcHidden.read(db).cards, {'haesol': card}, reason: '꺼진 것의 카드만');
      layout.enable({1, 2, 3});
      rememberScreenOff(db, layout, cards: const {'haesol': card});
      expect(DlcHidden.read(db).cards, isEmpty, reason: '켜면 카드도 뺀다');
    });

    test('옛 판에서 기본팩을 뺀 기억(baseRemoved)은 그 기본팩이 든 저장소를 처음 열 때 화면에서 끈 목록으로 한 번 옮긴다(판정 R60 M-3)', () {
      File(at('DLC${Platform.pathSeparator}hidden.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'version': 1, 'off': ['moonbay'], 'baseRemoved': true, 'cards': {'moonbay': {'name': '달물결 기록집'}}}));
      final layout = keyedLayout();
      expect(migrateBaseRemoved(db, layout, baseKey: 'east-asia-base'), isTrue);
      final hidden = DlcHidden.read(db);
      expect(hidden.off, {'moonbay', 'east-asia-base'});
      expect(hidden.baseRemoved, isFalse);
      expect(dlcOffAtOpen(layout, hidden), {1}, reason: '바탕은 화면에서만 끈 채로 연다');
      expect(migrateBaseRemoved(db, layout, baseKey: 'east-asia-base'), isFalse, reason: '한 번만');
      // 그 기본팩이 저장소에 없으면 그대로(켤 길은 파일에서 더하기 — dlcRouteRefusal).
      File(at('DLC${Platform.pathSeparator}hidden.json')).writeAsStringSync(jsonEncode({'version': 1, 'off': [], 'baseRemoved': true, 'cards': {}}));
      final noBase = SceneLayout.fromJson({'packs': [{'id': 1, 'name': '해솔', 'events': 1, 'key': 'haesol'}], 'tracks': [], 'epochs': []});
      expect(migrateBaseRemoved(db, noBase, baseKey: 'east-asia-base'), isFalse);
      expect(DlcHidden.read(db).baseRemoved, isTrue);
    });

    test('화면에서만 끈 DLC를 끈 목록(hidden.json)에 기억해 다음 실행에도 끈 채로 연다 — 켜면 뺀다(8 검토 2회차 Minor 1)', () {
      final layout = keyedLayout()..enable({1, 3});
      File(at('DLC${Platform.pathSeparator}hidden.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'version': 1, 'off': ['moonbay', 'gone'], 'baseRemoved': false, 'cards': {'moonbay': {'name': '달물결 기록집'}}}));
      rememberScreenOff(db, layout);
      final hidden = DlcHidden.read(db);
      expect(hidden.off, {'haesol', 'moonbay'}, reason: '저장소에 없는 끈 DLC는 카드가 있는 것(저장소에 있었던 것)만 둔다 — 카드 없는 낡은 id(gone)는 뺀다(덧붙임 N2)');
      expect(hidden.cards.keys, ['moonbay']);
      expect(dlcOffAtOpen(layout, hidden), {2}, reason: '다음 실행에서 끈 채로 열 자료집 번호');
      layout.enable({1, 2, 3});
      rememberScreenOff(db, layout);
      expect(DlcHidden.read(db).off, {'moonbay'});
      expect(Directory(at('DLC')).listSync().map((f) => f.path).where((n) => n.endsWith('.tmp')), isEmpty);
    });

    test('채널이 .htpack 경로 둘을 주면 엔진 add_pack 하나로 그 둘 — 형식 3 파일을 고른 그대로(바꾸는 차례 없음 · Node 없음)', () async {
      final ktl = writeDlc(at('dlc-in${Platform.pathSeparator}KoreanTimeLine-v1.0.5.htpack'), 'KoreanTimeLine', '1.0.5', name: 'Tigers of the East');
      final reed = packIn('reed-v1.0.0.htpack', 'reed');
      final calls = fakeChannel(() async => {'paths': [ktl, reed], 'skipped': []});
      final requests = <Map<String, dynamic>>[];
      final job = DlcJob()
        ..applier = (request) async {
          requests.add(request);
          return {'ok': true, 'data': {'rewrote': [], 'added': ['koreaA'], 'removed': [], 'first_pos': 3, 'ms': 120}};
        };
      DlcApplied? done;
      await pickAndAddDlc((files) async => done = await job.apply(db: db, files: files, stored: {'lantern'}), job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(calls.single.method, 'pick');
      expect(done?.ok, isTrue, reason: job.lines.join('\n'));
      expect(requests.single, {'op': 'add_pack', 'files': [File(ktl).absolute.path, File(reed).absolute.path], 'path': db}, reason: '경로 둘이면 add_pack 하나');
      expect(File(at('DLC${Platform.pathSeparator}KoreanTimeLine-v1.0.5.htpack')).existsSync(), isTrue, reason: '끝난 뒤 원본은 저장소 옆 DLC 폴더로(캐시 폴더는 다음 고르기에 비워진다)');
      expect(job.notes, isEmpty);
    });

    test('채널이 DLC가 아닌 파일을 주면 엔진에 닿지 않고 그 까닭을 알린다(저장소 그대로)', () async {
      final photo = (File(at('dlc-in${Platform.pathSeparator}사진.jpg'))..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3])).path;
      fakeChannel(() async => [photo]);
      final job = DlcJob()..applier = (request) async => fail('엔진에 닿으면 안 된다');
      final before = File(db).readAsBytesSync();
      DlcApplied? done;
      await pickAndAddDlc((files) async => done = await job.apply(db: db, files: files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(done?.ok, isFalse);
      expect(done?.storeChanged, isFalse);
      expect(job.status, '사진.jpg — DLC 파일(.htpack)이 아닙니다.');
      expect(File(db).readAsBytesSync(), before);
      expect(Directory(at('DLC')).existsSync(), isFalse);
      expect(DlcTools.phoneOnly.archiveTool, isEmpty);
      expect(DlcTools.phoneOnly.phone, isTrue);
      expect(DlcTools.engineOnly.phone, isFalse);
    });

    test('고르기 창이 한도 안에 돌아오지 않으면 기다리기를 멈추고 잡음을 푼다 · 늦게 온 답은 버린다(10a 검토 N3)', () async {
      final never = Completer<Object?>();
      fakeChannel(() => never.future);
      final job = DlcJob(), got = <List<String>>[];
      await pickAndAddDlc((files) async => got.add(files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e, timeout: const Duration(milliseconds: 50)));
      expect(job.running, isFalse, reason: '잡음이 풀려 다른 DLC 일을 할 수 있다');
      expect(got, isEmpty, reason: '아무것도 넣지 않는다');
      expect(job.notes, [dlcPickTimeoutText]);
      expect(dlcPickTimeout, const Duration(minutes: 10));
      never.complete([at('dlc-in${Platform.pathSeparator}늦은.htpack')]);
      await pumpEventQueue();
      expect(got, isEmpty, reason: '늦게 온 답은 버린다');
      // 다시 고르면 창이 다시 열린다(안드로이드 쪽도 오래된 고르기는 버린다 — MainActivity.kt STALE_MS).
      final again = fakeChannel(() async => <String>[]);
      await pickAndAddDlc((files) async => got.add(files), job: job, pick: (e) => pickDlcFilesAndroid(onError: e));
      expect(again, hasLength(1));
    });

    testWidgets('바탕(첫 DLC)만 화면에서만 켜고 끄고(알림) 그 밖은 앱 틀로(엔진) — 삭제 단추는 바탕 말고 선다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(keyedLayout());
      final job = DlcJob()
        ..phone = true;
      final toggled = <String>[], removed = <String>[];
      await pumpManager(tester, scene, job: job, onAddFiles: () async {}, onRemove: (card) async => removed.add(card.key),
          onToggle: (cards, on) async => toggled.add('${[for (final c in cards) c.key].join(',')}:${on ? '켬' : '끔'}'));
      expect(find.text('파일에서 더하기'), findsOneWidget);
      // 첫 카드(바탕)는 삭제 단추가 서지 않는다 — 엔진이 빼지 못하고 다시 지을 도구도 없다.
      expect(find.byKey(const ValueKey('dlc-remove')), findsNothing);
      final before = scene.layout.enabledPacks.toSet();
      // 해솔(바탕이 아님)은 앱 틀로 — 엔진이 저장소에서 뺀다.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-2')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(toggled, ['haesol:끔']);
      expect(scene.layout.enabledPacks.toSet(), before, reason: '창은 조합을 바꾸지 않는다(앱 틀의 몫)');
      expect(job.notes, isEmpty);
      // 바탕은 화면에서만 끄고 그 사정을 위 칸에 알린다.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-1')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(toggled, hasLength(1), reason: '바탕은 앱 틀에 넘기지 않는다');
      expect(scene.layout.enabledPacks.toSet(), before.difference({1}), reason: '화면에서만 끈다(저장소 그대로)');
      expect(find.byKey(const ValueKey('dlc-job-notes')), findsOneWidget);
      expect(job.notes.single, dlcScreenOnlyNote);
      // 모두 끄기 — 바탕 아닌 것만 앱 틀로 · 바탕은 이미 꺼져 있다.
      await tester.tap(find.text('모두 끄기'));
      await tester.pump();
      expect(toggled.last, 'haesol,silverbay:끔');
      // 해솔을 고르면 삭제 단추가 선다(엔진 remove_pack).
      await tester.tap(find.text('해솔 기록집').first);
      await tester.pump();
      expect(find.byKey(const ValueKey('dlc-remove')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dlc-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(removed, ['haesol']);
      // 도구가 있어도(컴퓨터) 바탕에는 삭제 단추가 서지 않는다(판정 R43 — 다시 짓기는 달력 표 없는 저장소를 지어 부르지 않는다).
      await tester.tap(find.text('별여울 기록집').first);
      await tester.pump();
      expect(find.byKey(const ValueKey('dlc-remove')), findsNothing);
    });

    testWidgets('바탕 켜고 끄기는 화면에서만(판정 R43) · 원본 없이 든 DLC 끄기도 화면에서만 — 앱 틀에 넘기지 않고 알린다 · 원본 없는 바탕은 바탕의 알림(고침 1회차 I-1 · I-3 · 재검토)', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(keyedLayout());
      final job = DlcJob();
      final toggled = <String>[];
      tester.view.physicalSize = const Size(1300, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DlcManager(
            scene: scene, job: job, onRemove: (card) async {},
            packFacts: const {'haesol': DlcPackFacts(version: '1.0.0', original: false), 'east-asia-base': DlcPackFacts(original: false)},
            onToggle: (cards, on) async => toggled.add('${[for (final c in cards) c.key].join(',')}:${on ? '켬' : '끔'}'),
          ),
        ),
      ));
      final before = scene.layout.enabledPacks.toSet();
      // 바탕(동아시아 기본팩 — 첫 DLC · 여기서는 원본도 없음) 끄기 → 화면에서만 · 바탕의 알림이 먼저(원본 없음 알림이 아니라 — 10b 고침 재검토).
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-1')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(toggled, isEmpty, reason: '다시 짓기(Node)도 엔진도 부르지 않는다');
      expect(scene.layout.enabledPacks.toSet(), before.difference({1}));
      expect(job.notes, [dlcScreenOnlyNote]);
      // 원본 없이 든 해솔 끄기 → 화면에서만 · 그 사정을 알린다(엔진이 빼면 남길 원본이 없어 지워진다).
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-2')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(toggled, isEmpty);
      expect(scene.layout.enabledPacks.toSet(), before.difference({1, 2}));
      expect(job.notes.last, allOf(contains('원본(.htpack)이 없어 화면에서만 끕니다'), startsWith('«')));
      // 원본이 있는 은빛 나루는 앱 틀로(엔진 remove_pack).
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-3')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(toggled, ['silverbay:끔']);
      // 바탕에는 삭제 단추가 없다(처음 고른 카드).
      expect(find.byKey(const ValueKey('dlc-remove')), findsNothing);
    });

    testWidgets('모두 끄기에 원본 없이 든 DLC가 섞이면 그것은 화면에서만 끄고(알림) 나머지만 앱 틀로 — 바탕의 알림도 함께(10b 고침 재검토)', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(keyedLayout());
      final job = DlcJob();
      final toggled = <String>[];
      tester.view.physicalSize = const Size(1300, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DlcManager(
            scene: scene, job: job, onRemove: (card) async {},
            packFacts: const {'haesol': DlcPackFacts(version: '1.0.0', original: false)},
            onToggle: (cards, on) async => toggled.add('${[for (final c in cards) c.key].join(',')}:${on ? '켬' : '끔'}'),
          ),
        ),
      ));
      await tester.tap(find.text('모두 끄기'));
      await tester.pump();
      expect(toggled, ['silverbay:끔'], reason: '원본이 있는 것만 앱 틀(엔진)로');
      expect(scene.layout.isPackEnabled(1), isFalse, reason: '바탕은 화면에서');
      expect(scene.layout.isPackEnabled(2), isFalse, reason: '원본 없이 든 해솔도 화면에서');
      expect(job.notes, hasLength(2), reason: '카드마다의 까닭을 한 번씩(바탕 먼저)');
      expect(job.notes.first, dlcScreenOnlyNote);
      expect(job.notes.last, contains('원본(.htpack)이 없어 화면에서만 끕니다'));
    });
  });

  group('DLC 관리 창', () {
    testWidgets('고른 카드의 자세히에 DLC 삭제가 서고(바탕 말고), 확인하면 앱 틀에 닿는다', (tester) async {
      final (scene, _, _) = makePackScene();
      // 열쇠가 있는 뼈대(다시 지은 저장소의 꼴)로 바꾼다 — 삭제는 글자 id가 있어야 한다.
      scene.layout.replaceWith(keyedLayout());
      final removed = <String>[];
      await pumpManager(tester, scene, onRemove: (card) async => removed.add(card.key));
      // 처음 고른 카드는 첫 카드(바탕 — 기본팩): 판정 R43부터 바탕은 뺄 수 없다(엔진이 못 빼고, 다시 짓기는 달력 표 없는 저장소를 지음).
      expect(find.textContaining('east-asia-base'), findsOneWidget, reason: '자세히의 번호 줄에 글자 id도 적는다');
      expect(find.byKey(const ValueKey('dlc-remove')), findsNothing);

      // 둘째 카드를 고르면 삭제 단추가 선다.
      await tester.tap(find.text('해솔 기록집').first);
      await tester.pump();
      expect(find.byKey(const ValueKey('dlc-remove')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dlc-remove')));
      await tester.pumpAndSettle();
      expect(find.text('"해솔 기록집" DLC를 삭제할까요?'), findsOneWidget, reason: '지금 연표의 확인 글');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);

      await tester.tap(find.byKey(const ValueKey('dlc-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(removed, ['haesol']);
    });

    testWidgets('등불 바탕 저장소의 동아시아 DLC — 삭제 단추가 서고(바탕이 아님) · 휴대폰의 삭제 글은 도구 폴더가 아니라 그 .htpack을 말한다(판정 R60 I-1)', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '등불 연대기', 'events': 120, 'key': 'lantern-chronicle'},
          {'id': 2, 'name': '동아시아사 기본팩', 'events': 214, 'key': 'east-asia-base'},
        ],
        'tracks': [
          {'id': 1, 'pack': 1, 'ord': 0, 'name': '불씨 갈래', 'rows': [packRow(0), packRow(1)]},
          {'id': 2, 'pack': 2, 'ord': 1, 'name': '별여울 갈래', 'rows': [packRow(2), packRow(3)]},
        ],
        'epochs': [],
      }));
      for (final phone in [true, false]) {
        final job = DlcJob()..phone = phone;
        final removed = <String>[];
        await pumpManager(tester, scene, onRemove: (card) async => removed.add(card.key), job: job);
        await tester.tap(find.text('동아시아사 기본팩').first);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('dlc-remove')));
        await tester.pumpAndSettle();
        expect(find.text(phone ? dlcBaseRemovePhoneText : dlcBaseRemoveText), findsOneWidget, reason: '휴대폰에는 도구 폴더가 없다');
        await tester.tap(find.text('삭제'));
        await tester.pumpAndSettle();
        expect(removed, ['east-asia-base']);
      }
    });

    testWidgets('켜고 끄기는 앱 틀로 간다(저장소에서 빼고 넣음) — 스위치 · 모두 끄기 · 끈 카드 켜기', (tester) async {
      final (scene, _, asked) = makePackScene();
      scene.layout.replaceWith(keyedLayout());
      final job = DlcJob()
        ..hidden = DlcHidden.fromJson(const {'off': ['moonbay'], 'cards': {'moonbay': {'name': '달물결 기록집', 'tracks': [{'key': 'tide', 'name': '물결 갈래', 'color': 0xabb3c9, 'rows': 2}]}}});
      final calls = <String>[];
      await pumpManager(tester, scene, job: job, onToggle: (cards, on) async => calls.add('${[for (final c in cards) c.key].join(',')}:${on ? '켬' : '끔'}'));
      final before = scene.layout.enabledPacks;
      // 해솔의 스위치를 끈다 → 화면에서만 끄지 않고 앱 틀에 맡긴다(앱 틀이 화면에서 접고 다시 짓는다).
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-2')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(calls.last, 'haesol:끔');
      expect(scene.layout.enabledPacks, before, reason: '창은 조합을 바꾸지 않는다(앱 틀의 몫)');
      // 끈 카드(저장소에 없음)의 스위치를 켠다.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card--1')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(calls.last, 'moonbay:켬');
      // 모두 끄기 — 켜져 있는 것만 · 바탕은 화면에서만 끄고(판정 R43) 나머지만 앱 틀로.
      await tester.tap(find.text('모두 끄기'));
      await tester.pump();
      expect(calls.last, 'haesol,silverbay:끔');
      expect(scene.layout.isPackEnabled(1), isFalse, reason: '바탕은 화면에서 껐다');
      expect(asked.isEmpty || asked.last.length <= 3, isTrue);
    });

    testWidgets('켜고 끄는 동안 스위치는 부탁한 쪽에 서 있고, 다른 스위치는 받지 않는다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(keyedLayout());
      final dir = Directory.systemTemp.createTempSync('ht-toggling-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final release = Completer<Map<String, dynamic>>();
      final job = DlcJob()..applier = (request) => release.future;
      final calls = <String>[];
      await pumpManager(tester, scene, job: job, onToggle: (cards, on) async => calls.add(cards.first.key));
      final running = job.apply(db: '${dir.path}${Platform.pathSeparator}archive.db', offKeys: ['haesol'], stored: const {'haesol'});
      await tester.pump();
      MotionToggleLike toggleOf(int id) => MotionToggleLike(tester, find.byKey(ValueKey('dlc-card-$id')));
      expect(toggleOf(2).value, isFalse, reason: '끄는 중이면 꺼진 쪽');
      expect(toggleOf(3).value, isTrue);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dlc-card-3')), matching: find.byType(DlcSwitch)));
      await tester.pump();
      expect(calls, isEmpty, reason: '도는 동안에는 받지 않는다');
      release.complete({'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['h'], 'first_pos': 0, 'ms': 1}});
      await running;
      await tester.pump();
      expect(toggleOf(2).value, isFalse, reason: '성공하면 뼈대를 다시 읽을 때까지 그대로(reset 전)');
      job.reset();
      await tester.pump();
      expect(toggleOf(2).value, isTrue, reason: '다시 읽기 전 저장소의 값으로 돌아온다(여기서는 뼈대를 바꾸지 않았다)');
    });

    testWidgets('글자 id가 없는 옛 저장소의 카드에는 삭제 단추가 서지 않는다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene, onRemove: (card) async {});
      await tester.tap(find.text('해솔 기록집').first);
      await tester.pump();
      expect(find.byKey(const ValueKey('dlc-remove')), findsNothing);
    });

    testWidgets('뒷일이 도는 동안 위 칸에 진행 말이 비치고 더하기 단추가 잠기며, 실패하면 까닭이 남는다', (tester) async {
      final (scene, _, _) = makePackScene();
      final dir = Directory.systemTemp.createTempSync('ht-job-status-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = '${dir.path}${Platform.pathSeparator}archive.db';
      final job = DlcJob();
      var release = Completer<Map<String, dynamic>>();
      job.applier = (request) => release.future;
      await pumpManager(tester, scene, onAddFiles: () async {}, job: job);
      expect(find.byKey(const ValueKey('dlc-job-status')), findsNothing);

      final running = job.apply(db: db, removeKey: 'haesol', stored: const {'haesol'});
      await tester.pump();
      expect(find.text('DLC «haesol»을(를) 지우는 중…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final add = tester.widget<Semantics>(find.ancestor(of: find.text('파일에서 더하기'), matching: find.byType(Semantics)).first);
      expect(add.properties.enabled, isFalse, reason: '도는 동안 잠근다');

      release.complete({'ok': true, 'data': {'rewrote': [], 'added': [], 'removed': ['h'], 'first_pos': 0, 'ms': 1}});
      expect((await running).ok, isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('dlc-job-status')), findsNothing, reason: '끝나면(성공) 상태 줄은 사라진다');

      release = Completer<Map<String, dynamic>>();
      final failing = job.apply(db: db, removeKey: 'silverbay', stored: const {'silverbay'});
      release.complete({'ok': false, 'error': '타일 검사가 어긋났습니다'});
      expect((await failing).ok, isFalse);
      await tester.pump();
      expect(find.text('DLC를 빼지 못했습니다 — 타일 검사가 어긋났습니다'), findsOneWidget, reason: '실패의 까닭이 그대로 남는다');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('꺼 두어 저장소에서 뺀 DLC의 카드', () {
    test('끈 목록의 카드를 붙인다 — 꺼 둔 기본팩은 맨 앞 · 나머지는 뒤 · 번호는 음수 · 저장소에 없음', () {
      final layout = SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '해솔 기록집', 'events': 2, 'key': 'haesol'}],
        'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [packRow(0)]}],
        'epochs': [],
      });
      final cards = DlcCardInfo.of(layout, hidden: DlcHidden.fromJson(hiddenJson));
      expect([for (final c in cards) c.key], ['east-asia-base', 'haesol', 'moonbay']);
      expect([for (final c in cards) c.stored], [false, true, false]);
      expect(cards.first.isBase, isTrue, reason: '기본팩은 글자 id로 알아본다(첫 DLC가 아니어도)');
      expect(cards[1].isBase, isFalse, reason: '기본팩을 뺀 저장소의 첫 DLC는 기본팩이 아니다');
      final moon = cards.last;
      expect(moon.id, lessThan(0));
      expect(moon.version, '2.0.0');
      expect(moon.contents, '사건 101건 · 시대 54개 · 트랙 2개 · 줄 15개 · 얹은 트랙 1개');
      expect(moon.trackNames, '물결 갈래 · 산호 갈래 · 별여울 갈래');
      expect(moon.owners.values, ['별여울 기록집']);
    });

    test('보관함(kept_packs)에 있는데 끈 목록에 카드가 없는 DLC도 카드로 선다(끈 목록 쓰기가 실패한 뒤 — 판정 R60 I-3 덤) · 이름 · 판은 보관함의 값', () {
      final layout = SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '해솔 기록집', 'events': 2, 'key': 'haesol'}],
        'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [packRow(0)]}],
        'epochs': [],
      });
      final cards = DlcCardInfo.of(layout, hidden: DlcHidden.fromJson(hiddenJson), kept: const [
        (id: 'moonbay', name: '달물결 기록집(보관함)', version: '2.0.0'),
        (id: 'reed', name: '갈대 기록집', version: '1.0.0'),
        (id: 'haesol', name: '해솔 기록집', version: '1.0.0'),
      ]);
      expect([for (final c in cards) c.key], ['east-asia-base', 'haesol', 'moonbay', 'reed'], reason: '끈 목록의 카드가 먼저 · 저장소에 든 것은 하나만');
      final reed = cards.last;
      expect((reed.name, reed.version, reed.stored), ('갈대 기록집', '1.0.0', false));
      expect(cards[2].name, '달물결 기록집', reason: '끈 목록의 카드가 있으면 그것');
    });

    test('저장소에 남은 끈 DLC(다 꺼서 짓지 않은 것)는 저장소의 카드 하나만 선다', () {
      final layout = SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기본팩', 'events': 214, 'key': 'east-asia-base'}],
        'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0)]}],
        'epochs': [],
      });
      final cards = DlcCardInfo.of(layout, hidden: DlcHidden.fromJson(hiddenJson));
      expect([for (final c in cards) (c.key, c.stored)], [('east-asia-base', true), ('moonbay', false)]);
    });

    testWidgets('끈 카드의 자세히 — 저장소에서 뺌 · 꺼 둠 · 삭제 단추', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(keyedLayout());
      final job = DlcJob()
        ..hidden = DlcHidden.fromJson(hiddenJson);
      final removed = <String>[];
      await pumpManager(tester, scene, job: job, onRemove: (card) async => removed.add(card.key));
      await tester.tap(find.text('달물결 기록집').first);
      await tester.pump();
      expect(find.text('저장소에서 뺌 · 꺼 둠 · moonbay'), findsOneWidget);
      expect(find.text('v2.0.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dlc-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(removed, ['moonbay']);
    });
  });

  group('담긴 것 — 남의 트랙에 얹은 DLC', () {
    /// 나라 52개를 기본팩의 첫 트랙에 얹은 DLC(제 트랙 없음 · 사건 없음)와, 사건 하나만 얹은 DLC.
    SceneLayout layoutWithShared() => SceneLayout.fromJson({
      'packs': [
        {'id': 1, 'name': '별여울 기록집', 'events': 214, 'key': 'east-asia-base', 'periods': 84, 'touches': [1, 2]},
        {'id': 2, 'name': '동방의 기록집', 'events': 0, 'key': 'tigers', 'periods': 52, 'touches': [1]},
        {'id': 3, 'name': '덧붙인 기록집', 'events': 1, 'key': 'extend', 'periods': 0, 'touches': [2]},
        {'id': 4, 'name': '빈 기록집', 'events': 0, 'key': 'empty'},
      ],
      'tracks': [
        {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'key': 'starbrook', 'rows': [packRow(0), packRow(1)]},
        {'id': 2, 'pack': 1, 'ord': 1, 'name': '해솔 갈래', 'key': 'haesol', 'rows': [packRow(2), packRow(3)]},
      ],
      'epochs': [],
    });

    test('카드 글: 시대 수와 얹은 트랙을 적고, 둘 다 없을 때만 트랙 없음', () {
      final cards = DlcCardInfo.of(layoutWithShared());
      expect(cards[0].contents, '사건 214건 · 시대 84개 · 트랙 2개 · 줄 4개');
      expect(cards[1].contents, '사건 0건 · 시대 52개 · 얹은 트랙 1개', reason: '나라 52개를 얹은 DLC가 "트랙 없음"으로 읽히지 않는다');
      expect(cards[1].shared.map((t) => t.name), ['별여울 갈래']);
      expect(cards[1].owners, {1: '별여울 기록집'});
      expect(cards[1].trackNames, '별여울 갈래');
      expect(cards[1].matches('별여울'), isTrue, reason: '얹은 트랙 이름으로도 찾는다');
      expect(cards[2].contents, '사건 1건 · 얹은 트랙 1개');
      expect(cards[3].contents, '사건 0건 · 트랙 없음');
    });

    testWidgets('자세히에 얹은 트랙과 그 트랙의 DLC 이름이 선다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(layoutWithShared());
      await pumpManager(tester, scene);
      await tester.tap(find.text('동방의 기록집').first);
      await tester.pump();
      expect(find.text('사건 0건 · 시대 52개 · 얹은 트랙 1개'), findsWidgets);
      expect(find.byKey(const ValueKey('dlc-shared-1')), findsOneWidget);
      expect(find.text('별여울 갈래에 얹음'), findsOneWidget);
      expect(find.text('별여울 기록집'), findsWidgets, reason: '얹은 트랙의 주인 DLC 이름');
      expect(find.text('트랙 없음 — 다른 DLC의 줄에 사건만 덧붙입니다.'), findsNothing);
    });
  });

  group('진짜 자료 처리부(FFI · 빠른 빌드)로 — 넣기 · 끄기 · 켜기 · 지우기 · 낮은 판(계획 P4 과제 10b 걸음 1 ~ 4)', () {
    final dll = File('../engine/target/release/archive_engine.dll'), tool = File('../engine/target/release/archive-tool.exe');
    final ready = Platform.isWindows && dll.existsSync() && tool.existsSync();
    // 감독의 실자료 KoreanTimeLine v1.0.5(형식 3 그대로 — 읽기만 · 사본을 쓴다). 없는 PC는 정답지의 작은 장면으로.
    final ktl = File('D:/Timeline/KoreanTimeLine-v1.0.5.htpack');

    test('동아시아 정답지 저장소에 형식 3 파일 둘을 한 번에 넣고, 하나를 끄고(보관함) 켜고, 다른 하나를 지운다 — 낮은 판은 code version', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      final dir = Directory.systemTemp.createTempSync('ht-dlc-real-');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      String at(String name) => '${dir.path}${Platform.pathSeparator}$name';
      final db = at('archive.db');
      final built = await Process.run(tool.absolute.path, [
        'build', db, File('../fixtures/oracle/east-asia.json').absolute.path, '--now=2026-10-22T09:00:00+09:00',
        '--calendar=${File('../engine/tests/fixtures/lay/calendar-slice.json').absolute.path}', '--calendar-narrow',
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      Directory(at('내려받기')).createSync();
      final first = ktl.existsSync()
          ? ktl.copySync(at('내려받기${Platform.pathSeparator}KoreanTimeLine-v1.0.5.htpack')).path
          : File('../fixtures/oracle/move-scene.htpack').copySync(at('내려받기${Platform.pathSeparator}move-scene.htpack')).path;
      final nest = File('../fixtures/oracle/nest-scene.htpack').copySync(at('내려받기${Platform.pathSeparator}nest-scene.htpack')).path;
      final firstHead = readDlcFileHead(first).head!, firstId = firstHead.id, nestId = readDlcFileHead(nest).head!.id;
      // 폴더 사본의 이름은 고른 파일 이름이 아니라 `<id>-v<판>.htpack`(판정 R60 I-2) — KTL은 우연히 둘이 같아 KTL 없는 PC의 move-scene에서만 드러났다.
      final firstCopy = at('DLC${Platform.pathSeparator}${dlcOriginalFileName(firstId, firstHead.version)}');

      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine.start(db);
      addTearDown(() async {
        // 자료 처리부의 열린 저장소(프로세스 전역)를 닫아야 임시 폴더를 지울 수 있다(Windows는 열린 파일을 못 지움).
        try {
          await engine.call({'op': 'close'});
        } catch (_) {}
        engine.close();
      });
      final (scene, _, _) = makePackScene();
      final job = DlcJob(), reloads = <int>[];
      final flow = DlcApplyFlow(job: job, scene: scene, engineCall: engine.call, engineApply: engine.write, reload: (k) async => reloads.add(k));
      Future<List<String>> keys() async => [for (final p in (await engine.call({'op': 'layout'}))['data']['packs'] as List) '${(p as Map)['key']}'];
      Future<List<String>> kept() async => [for (final p in (await engine.call({'op': 'kept_packs'}))['data'] as List) '${(p as Map)['id']}'];

      // 1) 넣기 — 경로 둘을 add_pack 하나로(휴대폰 길 · Node 없음).
      var done = await flow.run(db: db, files: [first, nest], stored: (await keys()).toSet());
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(await keys(), ['east-asia-base', firstId, nestId]);
      expect(File(firstCopy).existsSync(), isTrue);
      expect(job.lines.last, startsWith('마쳤습니다 — 새 트랙'));
      // 2) 끄기 — 저장소에서 빼고 원본은 보관함에 · 카드는 끈 목록에.
      done = await flow.run(db: db, offKeys: [nestId], stored: (await keys()).toSet(), offCards: {nestId: {'name': '포개짐 시험'}});
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(await keys(), ['east-asia-base', firstId]);
      expect(await kept(), [nestId]);
      expect(DlcHidden.read(db).off, {nestId});
      // 3) 켜기 — 보관함에서 다시(add_pack ids).
      job.reset();
      done = await flow.run(db: db, onKeys: [nestId], stored: (await keys()).toSet());
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(await keys(), contains(nestId));
      expect(await kept(), isEmpty);
      expect(DlcHidden.read(db).off, isEmpty);
      expect(job.turnedOn, {nestId});
      // 4) 낮은 판 — 엔진이 code version으로 거절하고 저장소 그대로 · 쉬운 말.
      final lower = File('../fixtures/oracle/nest-scene.f4.json').readAsStringSync().replaceFirst('"version": "0.0.1"', '"version": "0.0.0"');
      final lowerFile = (File(at('내려받기${Platform.pathSeparator}nest-scene-낮은판.json'))..writeAsStringSync(lower)).path;
      final before = await keys();
      done = await flow.run(db: db, files: [lowerFile], stored: before.toSet());
      expect(done.ok, isFalse);
      expect(done.storeChanged, isFalse);
      expect(job.status, startsWith('지금 든(꺼 둔 것 포함) 것보다 낮은 판이라 넣지 않았습니다'));
      expect(await keys(), before);
      // 5) 지우기 — 원본까지 버리고 DLC 폴더의 파일도.
      done = await flow.run(db: db, removeKey: firstId, stored: (await keys()).toSet());
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(await keys(), isNot(contains(firstId)));
      expect(await kept(), isEmpty);
      expect(File(firstCopy).existsSync(), isFalse);
      expect(reloads, hasLength(4), reason: '고쳐 쓴 걸음마다 뼈대를 다시 읽는다(낮은 판은 그대로라 다시 읽지 않음)');
      // 6) 꺼 둔 채 지우기(판정 R42) — 다시 끄면 원본은 보관함에, 꺼 둔 채 지우면 엔진이 보관함의 원본까지 버린다(조합 그대로 — 다시 읽지 않음).
      done = await flow.run(db: db, offKeys: [nestId], stored: (await keys()).toSet(), offCards: {nestId: {'name': '포개짐 시험'}});
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(await kept(), [nestId]);
      final keysOff = await keys();
      done = await flow.run(db: db, removeKey: nestId, stored: keysOff.toSet());
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      expect(await kept(), isEmpty, reason: '꺼 둔 DLC의 원본이 보관함에 남지 않는다(예전에는 남아 시드 잇기가 묘비로 걸렀다)');
      expect(await keys(), keysOff);
      expect(DlcHidden.read(db).off, isEmpty);
      expect(DlcFolderState.read(db)!.removed, contains(nestId));
      expect(reloads, hasLength(5), reason: '끄기는 다시 읽고 · 꺼 둔 채 지우기는 뼈대가 그대로라 다시 읽지 않는다');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('메이커 미리보기 — 작업본(낮은 판)이 prefer_given으로 서재 사본의 같은 id를 이긴다(판정 R39)', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      final dir = Directory.systemTemp.createTempSync('ht-dlc-preview-');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      String at(String name) => '${dir.path}${Platform.pathSeparator}$name';
      final db = at('archive.db');
      final built = await Process.run(tool.absolute.path, [
        'build', db, File('../fixtures/oracle/east-asia.json').absolute.path, '--now=2026-10-22T09:00:00+09:00',
        '--calendar=${File('../engine/tests/fixtures/lay/calendar-slice.json').absolute.path}', '--calendar-narrow',
        File('../fixtures/oracle/nest-scene.htpack').absolute.path,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine.start(db);
      addTearDown(() async {
        // 자료 처리부의 열린 저장소(프로세스 전역)를 닫아야 임시 폴더를 지울 수 있다(Windows는 열린 파일을 못 지움).
        try {
          await engine.call({'op': 'close'});
        } catch (_) {}
        engine.close();
      });
      final (scene, _, _) = makePackScene();
      final job = DlcJob();
      final flow = DlcApplyFlow(job: job, scene: scene, engineCall: engine.call, engineApply: engine.write, reload: (_) async {});
      final work = (File(at('작업본.json'))..writeAsStringSync(File('../fixtures/oracle/nest-scene.f4.json').readAsStringSync().replaceFirst('"version": "0.0.1"', '"version": "0.0.0"'))).path;
      final done = await flow.run(db: db, files: [work], preferGiven: true);
      expect(done.ok, isTrue, reason: job.lines.join('\n'));
      final meta = Map<String, dynamic>.from((await engine.call({'op': 'info'}))['data']['meta'] as Map);
      expect(DlcPackFacts.fromMeta(meta)['nest-scene']?.version, '0.0.0', reason: '작업본(낮은 판)이 이겼다');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
