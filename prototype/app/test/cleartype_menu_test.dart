// ClearType 켜고 끄기(계획 P2 과제 5): 기억(parts['text']) · `⋯` 차림표의 '글자 › ClearType' 줄 · 이어 붙이기(슬롯 → 기억 · 장면) · 명령줄 끄기.
import 'dart:io';
import 'dart:ui' show Size;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/cleartype_prefs.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/shell_keys.dart' show slotClearType;
import 'package:flutter_test/flutter_test.dart';

import 'app_glue_test.dart' show FakeBridge;
import 'timeline_view_test.dart' show pumpView;

/// 자료 처리부 없이 서는 빈 장면과 길.
AppBus makeBus() {
  final controller = TimelineController()
    ..resize(1920, 500)
    ..setExtent(-1000000, 1000000);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {'packs': [], 'tracks': [], 'epochs': []}),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('이 검사는 타일을 읽지 않는다'),
  );
  addTearDown(scene.dispose);
  addTearDown(controller.dispose);
  final bus = AppBus(ask: (query) async => const {}, controller: controller, scene: scene);
  addTearDown(bus.dispose);
  return bus;
}

Future<AppMemory> openMemory(Directory folder) async {
  final memory = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
  addTearDown(() async {
    await memory.flush(); // 폴더를 지우기 전에 미뤄 둔 쓰기를 끝낸다
    memory.dispose();
  });
  return memory;
}

Future<Directory> tempFolder() async {
  final folder = await Directory.systemTemp.createTemp('ht-cleartype-');
  addTearDown(() => folder.delete(recursive: true));
  return folder;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 전역 설정이라 검사마다 처음 값으로 되돌린다.
  void reset() {
    ClearTypePrefs.on = true;
    ClearTypePrefs.system = const ClearTypeInfo(true, false);
    ClearTypePrefs.bakerReady = false;
  }

  setUp(reset);
  tearDown(reset);

  group('기억', () {
    test('없으면 켬 · 쓰면 parts["text"]에 실려 다시 열어도 그대로', () async {
      final folder = await tempFolder();
      final m = await openMemory(folder);
      ClearTypePrefs.load(m);
      expect(ClearTypePrefs.on, isTrue);

      ClearTypePrefs.save(m, false);
      expect(ClearTypePrefs.on, isFalse);
      expect(m.parts['text'], {'clearType': false});

      await m.flush();
      final again = await openMemory(folder);
      ClearTypePrefs.on = true;
      ClearTypePrefs.load(again);
      expect(ClearTypePrefs.on, isFalse, reason: '파일을 거쳐도 끔이 남는다');
    });

    test('같은 칸의 다른 열쇠는 지우지 않고, false가 아닌 값은 켬으로 읽는다', () async {
      final m = await openMemory(await tempFolder());
      m.parts['text'] = {'other': 1};
      ClearTypePrefs.save(m, false);
      expect(m.parts['text'], {'other': 1, 'clearType': false});

      for (final odd in <Object?>[true, null, 'off', 0]) {
        m.parts['text'] = {'clearType': odd};
        ClearTypePrefs.on = false;
        ClearTypePrefs.load(m);
        expect(ClearTypePrefs.on, isTrue, reason: '$odd');
      }
    });

    test('명령줄 --cleartype=off는 끄기만 하고 기억에는 쓰지 않는다', () async {
      final m = await openMemory(await tempFolder());
      ClearTypePrefs.applyOption(null);
      ClearTypePrefs.applyOption('on');
      ClearTypePrefs.applyOption('');
      expect(ClearTypePrefs.on, isTrue, reason: 'off가 아니면 아무것도 하지 않는다');
      ClearTypePrefs.applyOption('off');
      expect(ClearTypePrefs.on, isFalse);
      expect(m.parts['text'], isNull);
    });

    test('끔은 기억을 열기 전에(화면이 서기 전에) 파일에서 먼저 읽는다 — 첫 장면부터 회색', () async {
      final folder = await tempFolder();
      final m = await openMemory(folder);
      ClearTypePrefs.save(m, false);
      await m.flush();
      ClearTypePrefs.on = true;
      ClearTypePrefs.loadPart(await AppMemory.readPart('text', folder: folder));
      expect(ClearTypePrefs.on, isFalse);
      ClearTypePrefs.loadPart(await AppMemory.readPart('text', folder: await tempFolder()));
      expect(ClearTypePrefs.on, isTrue, reason: '기억이 없으면 켬');
    });
  });

  group('차림표', () {
    test('보일 때만 "글자" 무리에 "ClearType" 줄 · 켬은 체크', () {
      final bus = makeBus();
      final on = buildMenuRows(bus: bus, flags: const MenuFlags(clearTypeShown: true, clearType: true));
      final i = on.indexWhere((r) => r.header && r.label == '글자');
      expect(i, greaterThanOrEqualTo(0));
      expect(on[i + 1].label, 'ClearType');
      expect(on[i + 1].checked, isTrue);
      expect(on[i + 1].icon, isNull, reason: '아이콘 없는 줄');

      final off = buildMenuRows(bus: bus, flags: const MenuFlags(clearTypeShown: true, clearType: false));
      expect(off.firstWhere((r) => r.label == 'ClearType').checked, isFalse);

      final hidden = buildMenuRows(bus: bus, flags: const MenuFlags(clearTypeShown: false, clearType: true));
      expect(hidden.any((r) => r.label == 'ClearType' || r.label == '글자'), isFalse);
      expect(buildMenuRows(bus: bus).any((r) => r.label == 'ClearType'), isFalse, reason: '기본은 보이지 않음');
    });

    test('자리: 승계선 무리 뒤 · DLC 관리 앞, 구분선으로 가른다', () {
      final bus = makeBus();
      final plain = buildMenuRows(bus: bus);
      final shown = buildMenuRows(bus: bus, flags: const MenuFlags(clearTypeShown: true));
      expect(shown.length, plain.length + 3, reason: '구분선 · 글자 · ClearType');
      final i = shown.indexWhere((r) => r.header && r.label == '글자');
      expect(shown[i - 1].sep, isTrue);
      expect(shown[i - 2].label, '숨김');
      expect(shown[i + 2].sep, isTrue);
      expect(shown[i + 3].label, 'DLC 관리');
    });

    test('줄을 고르면 슬롯이 지금 값의 반대로 바뀐다', () {
      final bus = makeBus();
      MenuRow rowOf(bool now) => buildMenuRows(bus: bus, flags: MenuFlags(clearTypeShown: true, clearType: now)).firstWhere((r) => r.label == 'ClearType');
      rowOf(true).onSelected!();
      expect(bus.slot(slotClearType).value, isFalse);
      rowOf(false).onSelected!();
      expect(bus.slot(slotClearType).value, isTrue);
    });

    test('보임은 Windows · Windows 설정 켬 · 굽개 있음이 모두 맞을 때만', () {
      expect(ClearTypePrefs.shown, isFalse, reason: '굽개가 아직 없음');
      ClearTypePrefs.bakerReady = true;
      expect(ClearTypePrefs.shown, Platform.isWindows);
      ClearTypePrefs.system = const ClearTypeInfo(false, false);
      expect(ClearTypePrefs.shown, isFalse, reason: 'Windows 설정이 꺼져 있음');
    });
  });

  group('이어 붙이기', () {
    test('깃발: 기억이 없어도 · 있어도 지금 켬 여부와 보임을 싣는다', () async {
      final bus = makeBus();
      final glue = AppGlue(bus: bus, bridge: FakeBridge())..start();
      addTearDown(glue.dispose);
      expect(glue.menuFlags().clearType, isTrue);
      expect(glue.menuFlags().clearTypeShown, isFalse);

      ClearTypePrefs.on = false;
      ClearTypePrefs.bakerReady = true;
      expect(glue.menuFlags().clearType, isFalse);
      expect(glue.menuFlags().clearTypeShown, Platform.isWindows);

      glue.attachMemory(await openMemory(await tempFolder()));
      expect(glue.menuFlags().clearType, isFalse);
      expect(glue.menuFlags().clearTypeShown, Platform.isWindows);
    });

    test('슬롯이 바뀌면 설정 · 기억을 바꾸고 장면을 다시 그리게 한다', () async {
      final bus = makeBus();
      final glue = AppGlue(bus: bus, bridge: FakeBridge())..start();
      addTearDown(glue.dispose);
      final memory = await openMemory(await tempFolder());
      glue.attachMemory(memory);
      expect(bus.scene.busy.value, isFalse);

      bus.slot(slotClearType).value = false;
      expect(ClearTypePrefs.on, isFalse);
      expect(memory.parts['text'], {'clearType': false});
      expect(bus.scene.busy.value, isTrue, reason: 'requestFrame으로 장면 시계가 한 장 더 돈다');

      bus.scene.tick(16);
      bus.scene.tick(16);
      expect(bus.scene.busy.value, isFalse);
      bus.slot(slotClearType).value = true;
      expect(ClearTypePrefs.on, isTrue);
      expect(memory.parts['text'], {'clearType': true});
      expect(bus.scene.busy.value, isTrue);
    });

    test('같은 값을 다시 넣어도 기억을 다시 쓰지 않는다 · 닫은 뒤에는 듣지 않는다', () async {
      final bus = makeBus();
      final glue = AppGlue(bus: bus, bridge: FakeBridge())..start();
      final memory = await openMemory(await tempFolder());
      glue.attachMemory(memory);

      bus.slot(slotClearType).value = true; // 이미 켜진 값
      expect(memory.parts['text'], isNull);

      glue.dispose();
      bus.slot(slotClearType).value = false;
      expect(ClearTypePrefs.on, isTrue);
    });

    testWidgets('연표 화면이 그림판을 지으면 굽개 유무를 설정에 적는다', (tester) async {
      ClearTypePrefs.bakerReady = true; // 이 검사 환경에는 archive_glyphs가 든 자료 처리부가 없다 — 화면이 거짓으로 고쳐 쓰는지 본다
      await pumpView(tester, const Size(820, 410));
      expect(ClearTypePrefs.bakerReady, ClearTypeBaker.open() != null);
    });

    test('측정 모드(기억 없음)에서도 설정은 바뀌되 파일은 만들지 않는다', () async {
      final bus = makeBus();
      final glue = AppGlue(bus: bus, bridge: FakeBridge())..start();
      addTearDown(glue.dispose);
      bus.slot(slotClearType).value = false;
      expect(ClearTypePrefs.on, isFalse);
      expect(glue.memory, isNull);
    });
  });
}
