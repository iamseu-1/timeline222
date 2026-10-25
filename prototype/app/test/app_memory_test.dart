import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/names_display.dart' show readSavedNamesUi;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// 상태 기억 검사 — 명세 06의 8-4와 9 ㈐-23. 임시 폴더에서 돌며 앱 자료 폴더를 건드리지 않는다.

Directory makeFolder() {
  final folder = Directory.systemTemp.createTempSync('ht-memory');
  addTearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });
  return folder;
}

File fileIn(Directory folder) => File('${folder.path}/${AppMemory.fileName}');

/// 짧게 모아 쓰는 기억(검사가 400ms를 기다리지 않아도 되는 곳에서).
Future<AppMemory> quick(Directory folder) => AppMemory.open(folder: folder, delay: const Duration(milliseconds: 20));

void main() {
  group('읽고 쓰기', () {
    test('파일이 없으면 기본값으로 연다', () async {
      final memory = await quick(makeFolder());
      expect(memory.view, isNull);
      expect(memory.ui.density, 0);
      expect(memory.ui.minImportance, 1);
      expect(memory.ui.birdShape, 'a');
      expect(memory.ui.leaderLabel, 'auto');
      expect(memory.ui.folded, isEmpty);
      expect(memory.ui.show['dynasties'], isTrue);
      expect(memory.ui.show['houses'], isFalse, reason: '가문 줄은 기본 끔');
      expect(memory.ui.show['spotEcho'], isFalse);
      expect(memory.ui.show.succession, Succession.all);
      memory.dispose();
    });

    test('담은 것이 다음에 열 때 그대로 나온다', () async {
      final folder = makeFolder();
      final memory = await quick(folder);
      memory
        ..setView(1000, 2000)
        ..ui.density = -1
        ..ui.minImportance = 2
        ..ui.legend = true
        ..ui.filterOpen = true
        ..ui.lens = 'track:3'
        ..ui.folded = [1, 4]
        ..ui.foldedPeoples = ['해민']
        ..ui.expandedHosts = ['moonwake-chronicle/p-coast-6']
        ..ui.tracks = {'1': false, '2': true}
        ..ui.scopes = {'moonwake-chronicle/scope-warlords': true};
      memory.ui.show['houses'] = true;
      memory.ui.show['leaders'] = false;
      memory.ui.show.succession = Succession.direct;
      memory.save();
      await memory.flush();

      final again = await quick(folder);
      expect(again.view, const ViewSpan(1000, 2000));
      expect(again.ui.density, -1);
      expect(again.ui.minImportance, 2);
      expect(again.ui.legend, isTrue);
      expect(again.ui.filterOpen, isTrue);
      expect(again.ui.lens, 'track:3');
      expect(again.ui.folded, [1, 4]);
      expect(again.ui.foldedPeoples, ['해민']);
      expect(again.ui.expandedHosts, ['moonwake-chronicle/p-coast-6']);
      expect(again.ui.tracks, {'1': false, '2': true});
      expect(again.ui.scopes, {'moonwake-chronicle/scope-warlords': true});
      expect(again.ui.show['houses'], isTrue);
      expect(again.ui.show['leaders'], isFalse);
      expect(again.ui.show.succession, Succession.direct);
      again.dispose();
    });

    test('승계선의 세 값이 모두 오간다', () async {
      final folder = makeFolder();
      for (final one in Succession.values) {
        final memory = await quick(folder);
        memory.ui.show.succession = one;
        memory.save();
        await memory.flush();
        expect((await quick(folder)).ui.show.succession, one);
      }
      final raw = jsonDecode(fileIn(folder).readAsStringSync()) as Map;
      expect((raw['ui'] as Map)['show'], containsPair('succession', false), reason: '파일에는 true · direct · false로 적는다');
    });

    test('저장된 show에 없는 열쇠는 기본값으로 채운다', () async {
      final folder = makeFolder();
      fileIn(folder).writeAsStringSync(jsonEncode({
        'version': 1,
        'ui': {
          'show': {'dynasties': false},
        },
      }));
      final memory = await quick(folder);
      expect(memory.ui.show['dynasties'], isFalse, reason: '적힌 것은 그대로');
      expect(memory.ui.show['figures'], isTrue, reason: '없는 열쇠는 기본값 — 뒤에 생긴 표시가 꺼진 채 나오지 않게');
      expect(memory.ui.show['houses'], isFalse);
      expect(memory.ui.show.succession, Succession.all);
      memory.dispose();
    });

    test('깨진 파일은 버리고 기본값으로 열며, 다음 쓰기에 제대로 된 파일이 된다', () async {
      final folder = makeFolder();
      fileIn(folder).writeAsStringSync('{"ui": {"density": 1');
      final memory = await quick(folder);
      expect(memory.ui.density, 0);
      memory.setView(10, 20);
      await memory.flush();
      expect(jsonDecode(fileIn(folder).readAsStringSync()), isA<Map<String, dynamic>>());
      expect((await quick(folder)).view, const ViewSpan(10, 20));
      memory.dispose();
    });

    test('다른 부품의 값은 제 꼴 그대로 담았다 돌려준다', () async {
      final folder = makeFolder();
      final memory = await quick(folder);
      memory.parts['filters'] = {'tracksOff': ['3'], 'density': 1, 'show': {'houses': true}};
      memory.save();
      await memory.flush();
      final again = await quick(folder);
      expect(again.parts['filters'], {'tracksOff': ['3'], 'density': 1, 'show': {'houses': true}});
      expect(again.parts['없는 것'], isNull);
      again.dispose();
      memory.dispose();
    });

    test('엉뚱한 값이 적혀 있어도 기본값으로 읽는다', () async {
      final folder = makeFolder();
      fileIn(folder).writeAsStringSync(jsonEncode({
        'view': {'start': '글자', 'end': 5},
        'ui': {'density': 7, 'birdShape': 'z', 'folded': 'ㄱ', 'minImportance': null, 'show': 3},
      }));
      final memory = await quick(folder);
      expect(memory.view, isNull, reason: '보던 기간이 수가 아니면 없는 것으로');
      expect(memory.ui.density, 0);
      expect(memory.ui.birdShape, 'a');
      expect(memory.ui.folded, isEmpty);
      expect(memory.ui.minImportance, 1);
      expect(memory.ui.show['dynasties'], isTrue);
      memory.dispose();
    });
  });

  group('모아서 쓰기', () {
    test('400ms 동안 여러 번 바꿔도 한 번만 쓴다', () async {
      final folder = makeFolder();
      final memory = await AppMemory.open(folder: folder);
      final file = fileIn(folder);
      memory.setView(0, 100);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(file.existsSync(), isFalse, reason: '아직 400ms가 지나지 않았다');
      memory.setView(0, 200); // 다시 바꾸면 기다림이 다시 시작된다
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(file.existsSync(), isFalse, reason: '마지막으로 바꾼 때부터 400ms');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // 여기까지 왔으면 모아 쓰기의 시계(마지막으로 바꾼 때부터 400ms)는 이미 울렸다 — 이 기다림(250 + 300ms)보다 이른 때로 맞춰져 있다.
      // 그 쓰기가 파일에 놓이는 데 걸리는 시간은 어림하지 않고 기다린다(시계가 울리지 않았다면 기다릴 쓰기가 없어 아래에서 걸린다).
      await memory.written;
      expect(file.existsSync(), isTrue);
      expect(ViewSpan.read((jsonDecode(file.readAsStringSync()) as Map)['view']), const ViewSpan(0, 200), reason: '마지막 값 하나만 남는다');
      memory.dispose();
    });

    test('미뤄 둔 쓰기가 있으면 닫을 때 마저 쓴다', () async {
      final folder = makeFolder();
      final memory = await AppMemory.open(folder: folder);
      memory.setView(5, 15);
      memory.dispose();
      // 닫기는 쓰기를 시작만 한다. 정해 둔 시간(전에는 60ms)이 아니라 그 쓰기가 파일에 놓이기를 기다린다 —
      // 바쁜 기기에서는 60ms 안에 끝나지 않아 다시 열면 비어 있었다(모아 쓰기의 400ms는 닫을 때 멈췄으니 이 쓰기는 닫기가 시작한 것이다).
      await memory.written;
      expect((await quick(folder)).view, const ViewSpan(5, 15));
    });
  });

  group('보던 기간은 자료보다 먼저', () {
    test('readView가 기억 파일 하나만 읽어 보던 기간을 돌려준다', () async {
      final folder = makeFolder();
      final memory = await quick(folder);
      memory.setView(_minute(800), _minute(900));
      await memory.flush();
      memory.dispose();

      // 자료 처리부를 열기 전에 부르는 길 — 파일이 없으면 null이라 첫 화면은 그냥 전체 보기가 된다.
      expect(await AppMemory.readView(folder: folder), ViewSpan(_minute(800), _minute(900)));
      expect(await AppMemory.readView(folder: makeFolder()), isNull);
    });
  });

  group('보기 조건 잇기', () {
    test('기억한 값이 먼저 들어가고, 바뀌면 기억한다', () async {
      final folder = makeFolder();
      final memory = await quick(folder);
      memory.ui.show['leaders'] = false;
      memory.ui.density = 1;

      final conditions = ValueNotifier(const ViewConditions());
      addTearDown(conditions.dispose);
      final stop = memory.bindConditions(conditions);
      expect(conditions.value.leaders, isFalse, reason: '기억한 값이 먼저');
      expect(conditions.value.density, 1);

      conditions.value = conditions.value.copyWith(figures: false, density: 2);
      expect(memory.ui.show['figures'], isFalse);
      expect(memory.ui.density, 2);
      expect(memory.ui.birdFrom, 1, reason: '조감에 들 때 직전 밀도를 적어 둔다');
      await memory.flush();
      expect((await quick(folder)).ui.show['figures'], isFalse);

      stop();
      conditions.value = conditions.value.copyWith(density: 0);
      expect(memory.ui.density, 2, reason: '그만 들으면 더 적지 않는다');
      memory.dispose();
    });

    test('조감은 직전 밀도를 기억했다 돌아간다', () async {
      final memory = await quick(makeFolder());
      memory.ui.density = -1;
      expect(memory.birdTarget(inBird: false), 2);
      expect(memory.ui.birdFrom, -1);
      expect(memory.birdTarget(inBird: true), -1, reason: '조감 밀도에서 나오면 직전 밀도로');
      expect(memory.ui.density, -1);
      memory.ui.density = 0;
      expect(memory.birdTarget(inBird: true), isNull, reason: '자동 조감이면 밀도를 바꾸지 않고 풀기만 한다');
      memory.dispose();
      // 위에서 밀도를 바꿔 미뤄 둔 쓰기가 있다 — 닫기가 시작한 그 쓰기가 끝난 뒤에 폴더를 치우게 한다
      // (기다리지 않으면 뒷정리의 폴더 지우기와 겹쳐, 지운 폴더가 다시 생기거나 '다른 프로세스가 파일을 사용 중'으로 걸린다).
      await memory.written;
    });
  });

  // 판정 R50: 앱을 띄우는 검사(연기 검사 A) 등)가 감독의 기억(%APPDATA%\…\archive-prototype-v2\ui-state.json)을 덮었다 — 검사는 `--memory-dir`로 띄운다.
  // 실제 앱 자료 폴더는 건드리지 않고 경로 셈만 본다: 운영체제의 앱 자료 폴더를 묻는 함수(path_provider — 물으면 그 폴더를 만든다)를 가짜로 넣어
  // 손잡이가 있으면 한 번도 묻지 않음을 센다.
  group('기억 자리(--memory-dir — 판정 R50)', () {
    late int asked;
    late Directory platformFolder;
    Future<Directory> platform() async {
      asked++;
      return platformFolder;
    }

    setUp(() {
      asked = 0;
      platformFolder = makeFolder();
    });

    test('손잡이를 주면 기억 · 저장소 자리가 그 폴더다 — 운영체제의 앱 자료 폴더는 묻지도 않고 거기에 파일이 생기지 않는다', () async {
      final mine = makeFolder();
      final place = MemoryPlace.of(['--db=D:/어디/archive.db', '--memory-dir=${mine.path}']);
      expect(place.folder?.path, mine.path);
      expect(place.remember, isTrue, reason: '보통 모드면 기억을 읽고 쓴다 — 그 폴더에서');
      expect((await place.resolve(platform: platform)).path, mine.path);
      expect(await place.storePath(platform: platform), '${mine.path}/archive.db', reason: '저장소를 주지 않은 휴대폰 꼴의 저장소 자리도 그 폴더');
      // 앱 틀이 하듯 그 폴더로 기억을 열고 쓰면 그 폴더에만 놓인다.
      final memory = await AppMemory.open(folder: place.folder, delay: const Duration(milliseconds: 20));
      memory.setView(1000, 2000);
      await memory.flush();
      expect(fileIn(mine).existsSync(), isTrue);
      expect(await AppMemory.readView(folder: place.folder), isNotNull);
      expect(asked, 0, reason: '운영체제의 앱 자료 폴더(Windows %APPDATA%)를 한 번도 셈하지 않았다');
      expect(platformFolder.listSync(), isEmpty, reason: '운영체제의 앱 자료 폴더에는 아무것도 생기지 않는다');
    });

    test('손잡이가 없으면 예전처럼 운영체제의 앱 자료 폴더 — 저장소도 그 아래 archive.db', () async {
      final place = MemoryPlace.of(const ['--db=D:/어디/archive.db']);
      expect(place.folder, isNull);
      expect(place.remember, isTrue);
      expect((await place.resolve(platform: platform)).path, platformFolder.path);
      expect(await place.storePath(platform: platform), '${platformFolder.path}/archive.db');
      expect(asked, 2);
    });

    test('재는 중 · 메이커 미리보기는 기억을 읽지도 쓰지도 않는다 — 그림만 뜰 때의 --capture-memory만 예외', () {
      final mine = makeFolder().path;
      expect(MemoryPlace.of(['--measure=결과', '--memory-dir=$mine']).remember, isFalse, reason: '측정은 기억이 장면을 바꾸면 무효다');
      expect(MemoryPlace.of(['--measure=결과', '--memory-dir=$mine']).folder?.path, mine, reason: '자리는 그 폴더(운영체제 폴더를 묻지 않게)');
      expect(MemoryPlace.of(['--capture-only=yes', '--memory-dir=$mine']).remember, isFalse);
      expect(MemoryPlace.of(['--preview-dlc=작업본.htpack', '--memory-dir=$mine']).remember, isFalse);
      final capture = MemoryPlace.of(['--measure=결과', '--capture-only=yes', '--capture-memory=$mine']);
      expect((capture.remember, capture.folder?.path), (true, mine), reason: 'D4 다시 열기 검사');
      final both = makeFolder().path;
      expect(MemoryPlace.of(['--capture-only=yes', '--capture-memory=$mine', '--memory-dir=$both']).folder?.path, mine, reason: '그림만 뜰 때는 --capture-memory가 앞선다');
      expect(MemoryPlace.of(['--capture-memory=$mine']).folder, isNull, reason: '--capture-memory는 그림만 뜰 때만');
      expect(MemoryPlace.of(['--memory-dir=']).folder, isNull, reason: '빈 값은 없는 것');
    });

    test('검사 실행의 임시 자리 · 저장소 — --memory-dir면 임시 파일도 그 아래 · 저장소를 주지 않은 재기 · 그림만은 저장소를 고쳐 쓰지 않는다(판정 R50 넘김)', () {
      final mine = makeFolder().path, sep = Platform.pathSeparator;
      expect(MemoryPlace.of(['--memory-dir=$mine']).scratch.path, '$mine${sep}tmp', reason: '미리보기 사본 · check-pack 결과 같은 임시 파일도 %TEMP%가 아니라 그 폴더 아래');
      expect(MemoryPlace.of(const []).scratch.path, Directory.systemTemp.path);
      expect(MemoryPlace.of(['--measure=결과', '--capture-only=yes']).leaveStore, isTrue,
          reason: '저장소를 주지 않은 그림만 · 재기는 기본 저장소(prototype.json)를 R32 · --add-dlc · --off-dlc로 고쳐 쓰지 않는다');
      expect(MemoryPlace.of(['--measure=결과']).leaveStore, isTrue);
      expect(MemoryPlace.of(['--measure=결과', '--capture-only=yes', '--db=D:/사본/archive.db']).leaveStore, isFalse, reason: '검사가 준 저장소(사본)는 그대로 쓴다');
      expect(MemoryPlace.of(['--add-dlc=a.htpack']).leaveStore, isFalse, reason: '연결 프로그램으로 연 .htpack(보통 모드)은 기본 저장소에 더한다');
      expect(MemoryPlace.of(['--memory-dir=$mine']).leaveStore, isFalse, reason: '보통 모드(연기 검사 A — 풀어 둔 꾸러미의 저장소)');
      // 재기 · 그림만은 저장소를 주었어도 저장소 옆 DLC/를 쓰지 않는다(판정 R63-4 — R32 다시 들이기 · 사본 채우기 · 묘비 정리 · 임시 파일 치우기 없음):
      // measure.mjs --capture-only --db <실자료>가 그 저장소의 DLC 폴더를 고쳐 쓰지 않게.
      expect(MemoryPlace.of(['--measure=결과', '--capture-only=yes', '--db=D:/사본/archive.db']).leaveDlcFolder, isTrue);
      expect(MemoryPlace.of(['--capture-only=yes', '--db=D:/사본/archive.db']).leaveDlcFolder, isTrue);
      expect(MemoryPlace.of(['--measure=결과']).leaveDlcFolder, isTrue);
      expect(MemoryPlace.of(['--memory-dir=$mine']).leaveDlcFolder, isFalse, reason: '보통 모드는 DLC 폴더를 맞춘다');
      expect(MemoryPlace.of(['--add-dlc=a.htpack']).leaveDlcFolder, isFalse);
    });

    test('화면 글꼴(names 기억)도 그 폴더에서 읽는다 — 운영체제의 앱 자료 폴더를 읽지 않는다', () async {
      final mine = makeFolder();
      fileIn(mine).writeAsStringSync(jsonEncode({'version': 1, 'parts': {'names': {'screen': 'font:my-hangul'}}}));
      fileIn(platformFolder).writeAsStringSync(jsonEncode({'version': 1, 'parts': {'names': {'screen': 'font:other'}}}));
      final place = MemoryPlace.of(['--memory-dir=${mine.path}']);
      expect((await readSavedNamesUi(folder: place.folder)).screen, 'font:my-hangul');
    });
  });
}

double _minute(int year) => DateTime.utc(year).millisecondsSinceEpoch / 60000;
