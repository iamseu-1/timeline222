// 그림판이 장면마다 lcdAllowed를 바르게 정하는가(설계 3-2 · 계획 P2 과제 4 · 과제 6 고침: 타일 기다림 · 멈춘 뒤 150ms).
import 'dart:async';

import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/cleartype_prefs.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/lens_titles.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/reserved.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'glyph_atlas_lcd_test.dart' show FakeBaker;
import 'support/painter_fixture.dart';

AtlasText newAtlas() => AtlasText(baker: FakeBaker(), fontFileOf: (_) => 'fake.otf');

/// 타일이 모두 도착해 떠오름이 끝난 멈춘 장면. 떠오름은 실제 시계로 200ms라 검사가 시계에 기대지 않게 끈다.
/// 멈춘 뒤 [clearTypeSettleMs]가 지나 ClearType을 허락할 때까지(실제 시계로) 기다려 돌려준다.
Future<(AtlasText, TimelineScene, TimelinePainter)> still({bool clearType = true, AtlasText? text}) async {
  final atlas = text ?? newAtlas();
  final (scene, painter, _) = make(text: atlas, clearType: clearType);
  scene.hide.add('fade');
  await loadAll(scene);
  for (var i = 0; i < 30; i++) {
    scene.tick(16);
  }
  for (var i = 0; i < 100 && !scene.stillForClearType; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return (atlas, scene, painter);
}

/// 손으로 돌리는 장면 시계.
class HandClock {
  double now = 0;
}

/// [still]과 같되 장면 시계를 손으로 돌린다 — 150ms 문턱의 안팎을 실제 시간에 기대지 않고 본다(검사가 붐벼 늦어져도 흔들리지 않게).
/// 멈춘 뒤 [clearTypeSettleMs]가 지나 ClearType을 허락한 장면을 돌려준다. [labelHold]는 [make]의 것.
Future<(AtlasText, TimelineScene, TimelinePainter, HandClock)> stillByHand({Future<void> Function()? labelHold}) async {
  final clock = HandClock();
  final atlas = newAtlas();
  final (scene, painter, _) = make(text: atlas, clock: () => clock.now, labelHold: labelHold);
  scene.hide.add('fade');
  await loadAll(scene);
  for (var i = 0; i < 30; i++) {
    scene.tick(16);
  }
  paint(painter); // 그림판의 첫 그림이 이름 판의 서명(비켜 갈 구간 등)을 채워 다음 준비가 판을 한 번 더 청한다 — 그 답까지 받아 둔다
  await labelsDone(scene);
  clock.now += clearTypeSettleMs;
  paint(painter);
  expect(atlas.lcdAllowed, isTrue, reason: '멈춘 지 150ms인 장면');
  expect(scene.labelWorker.busy, isFalse, reason: '더 청한 판이 없다 — 시계를 손으로 돌리는 동안 이름 판의 도착이 끼어들지 않게');
  return (atlas, scene, painter, clock);
}

/// 이름 자리 작업자(실제 isolate)의 답이 올 때까지 기다린 뒤 장면을 한 번 더 준비한다 — 새로 청한 이름 판을 기다리는 동안은 멈춤이 아니다.
/// 그 준비가 판을 또 청하면(앞 그림이 서명을 바꿨다) 그 답까지 기다린다.
Future<void> labelsDone(TimelineScene scene) async {
  for (var round = 0; round < 5; round++) {
    for (var i = 0; i < 200 && scene.labelWorker.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    scene.prepare();
    if (!scene.labelWorker.busy) return;
  }
}

/// 그려 보아 ClearType이 허락되지 않았으면 장면이 알려 올 때마다 다시 그린다(앱의 그림판처럼) — 배율이 바뀌면 이름 판을 새로 청하고 그 답과
/// 150ms를 기다려야 허락된다. 끝내 허락되면 참.
Future<bool> paintUntilAllowed(TimelineScene scene, TimelinePainter painter, AtlasText atlas) async {
  for (var i = 0; i < 10; i++) {
    paint(painter);
    if (atlas.lcdAllowed) return true;
    await toldStill(scene);
  }
  return false;
}

/// 장면이 알려 올 때까지 기다린다(멈춘 뒤 150ms의 타이머 — 시계가 멎어 있어도 깨운다).
/// 다른 알림(이름 판의 도착 등)이 먼저 와도 ClearType을 허락할 때까지 다음 알림을 기다린다. 걸린 시간(ms)을 돌려준다.
Future<double> toldStill(TimelineScene scene) async {
  final watch = Stopwatch()..start();
  while (true) {
    final told = Completer<void>();
    void on() {
      if (!told.isCompleted) told.complete();
    }

    scene.addListener(on);
    await told.future.timeout(const Duration(seconds: 2));
    scene.removeListener(on);
    if (scene.stillForClearType) return watch.elapsedMicroseconds / 1000;
  }
}

/// 앱의 화면처럼 돌린다: 장면이 알리면 다음 장면(16ms 뒤)에 그리고, busy인 동안에만 장면마다 시계(tick)를 돌린다 —
/// 검사가 손으로 그리지 않아 '알림도 시계도 없으면 다시 그려지지 않는' 앱의 사정이 그대로 드러난다.
class AppLoop {
  AppLoop(this.scene, this.painter) {
    scene.addListener(_mark);
    _frames = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (scene.busy.value) scene.tick(16);
      if (_dirty) paintNow();
    });
    addTearDown(stop);
  }
  final TimelineScene scene;
  final TimelinePainter painter;
  late final Timer _frames;
  bool _dirty = false;
  void _mark() => _dirty = true;

  /// 이 장면을 지금 그린다(그때까지 온 알림도 이 그림이 받는다 — 앱이 그 알림으로 그린 장면).
  void paintNow() {
    _dirty = false;
    paint(painter);
  }

  void stop() {
    _frames.cancel();
    scene.removeListener(_mark);
  }
}

void main() {
  setUp(() {
    ClearTypePrefs.on = true;
    ClearTypePrefs.system = const ClearTypeInfo(true, false);
  });
  tearDown(() => Motion.slow = 1);

  test('멈춘 장면 · 1배 · 켬 → ClearType 허락', () async {
    final (atlas, scene, painter) = await still();
    expect(scene.stillForClearType, isTrue);
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('움직임(active)이 참인 동안 → 회색, 멎으면 다시 허락', () async {
    final (atlas, scene, painter) = await still();
    scene.controller.active.value = true;
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    scene.controller.active.value = false;
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '멎은 뒤 150ms 안');
    await toldStill(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('타일이 떠오르는 동안 → 회색', () async {
    Motion.slow = 1000; // 떠오름이 끝나지 않게 시계를 늦춘다
    final atlas = newAtlas();
    final (scene, painter, _) = make(text: atlas);
    await loadAll(scene);
    for (var i = 0; i < 30; i++) {
      scene.tick(16);
    }
    expect(scene.fading, isTrue);
    paint(painter);
    expect(scene.stillForClearType, isFalse);
    expect(atlas.lcdAllowed, isFalse);
  });

  test('이번 장면에 떠오르기 시작한 타일도 이번 장면에서 바로 회색(prepare 뒤에 정한다)', () async {
    var now = 0.0; // 장면 시계를 손으로 — 타일은 0에 도착하고, 160에서 멈춘 지 150ms가 넘었지만 떠오름(200ms)은 아직이다
    final atlas = newAtlas();
    final (scene, painter, _) = make(text: atlas, clock: () => now);
    scene.hide.add('fade');
    await loadAll(scene);
    for (var i = 0; i < 30; i++) {
      scene.tick(16);
    }
    await labelsDone(scene);
    now = 160;
    scene.hide.remove('fade');
    expect(scene.stillForClearType, isTrue, reason: '그리기 앞의 장면은 멈춘 듯 보이지만');
    paint(painter); // 이 장면의 prepare가 타일이 떠오르는 중임을 안다
    expect(scene.fading, isTrue);
    expect(atlas.lcdAllowed, isFalse);
  });

  // 실제 입력(조작부의 손 끌기 · 두 손가락)으로 — controller.active는 쫓아가기 · 돋보기 · 관성만 참이고 손 끌기 · 핀치는 moving에만 있다.
  test('손으로 끄는 동안 → 회색 · 관성 없이 떼면 한 번 알려 다음 그림에서 허락', () async {
    final (atlas, scene, painter) = await still();
    final c = scene.controller;
    c.pointerDown(const Offset(900, 500), 0);
    c.pointerMove(const Offset(920, 500), 16); // 문턱(5px)을 넘겨 끌기가 선다
    c.pointerMove(const Offset(940, 500), 32);
    expect(c.dragging, isTrue);
    expect(c.active.value, isFalse, reason: '끄는 동안 active는 거짓이다 — 그래서 active만 보면 ClearType이 그려진다');
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    var told = 0;
    scene.addListener(() => told++);
    c.pointerUp(const Offset(940, 500), 1000); // 마지막 표본에서 한참 뒤에 뗀다 — 관성 없음
    final released = Stopwatch()..start();
    expect(c.active.value, isFalse);
    expect(told, greaterThan(0), reason: '뗀 쪽이 알려 그 자리의 장면을 다시 그린다');
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '뗀 직후는 150ms 문턱 안 — 회색');
    await toldStill(scene);
    expect(released.elapsedMilliseconds, greaterThanOrEqualTo(clearTypeSettleMs - 5),
        reason: '시계가 돌지 않아도 150ms 뒤 장면이 알려 마지막 장면이 회색으로 남지 않는다');
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('끌다가 취소돼도 알리고 허락', () async {
    final (atlas, scene, painter) = await still();
    final c = scene.controller;
    c.pointerDown(const Offset(900, 500), 0);
    c.pointerMove(const Offset(920, 500), 16);
    c.pointerMove(const Offset(940, 500), 32);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    var told = 0;
    scene.addListener(() => told++);
    c.pointerCancel();
    expect(told, greaterThan(0));
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '150ms 문턱 안');
    await toldStill(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('관성이 있으면 관성이 도는 동안 회색 · 끝난 뒤 허락', () async {
    final (atlas, scene, painter) = await still();
    final c = scene.controller;
    c.pointerDown(const Offset(900, 500), 0);
    for (var i = 1; i <= 5; i++) {
      c.pointerMove(Offset(900 + 20.0 * i, 500), 16.0 * i);
    }
    c.pointerUp(const Offset(1000, 500), 90); // 마지막 표본(80ms)에서 곧바로 — 빠르게 뗀다
    expect(c.active.value, isTrue, reason: '관성이 시작됐다');
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    for (var i = 0; i < 600 && c.active.value; i++) {
      scene.tick(16);
    }
    expect(c.active.value, isFalse);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '관성이 끝난 직후는 150ms 문턱 안');
    await toldStill(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  // 관성 · 쫓아가기 · 돋보기 · 비행을 누름(pointerDown → stop) · Esc(stop)로 멈추면 active만 거짓이 된다 — 알림이 없고, 끌지 않고 떼면
  // pointerUp도 알리지 않는다. 움직임이 한 장면도 돌기 전이면 빈 줄 접기도 가라앉아 있어 시계까지 멎으니, 장면이 스스로 150ms를 세어 깨워야 한다.
  for (final (how, framesFirst) in const [('관성 · 누름', 0), ('쫓아가기 · Esc', 0), ('관성 · 누름', 6)]) {
    test('$how로 멈추면(움직임 $framesFirst장면 뒤) 그리지 않고 기다려도 150ms 뒤 알려 ClearType — 마지막 회색 장면이 남지 않는다', () async {
      final (atlas, scene, painter) = await still();
      final c = scene.controller;
      final app = AppLoop(scene, painter);
      app.paintNow(); // 앱의 첫 그림 — 그 뒤로는 알림과 시계가 그린다(글자 준비 · 굽기가 끝날 때까지)
      for (var i = 0; i < 200 && (scene.busy.value || atlas.lcdSprites == 0); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(atlas.lcdSprites, greaterThan(0), reason: '움직이기 전의 멈춘 장면은 ClearType으로 다 그려져 있다');
      expect(scene.busy.value, isFalse);
      if (how.startsWith('관성')) {
        c.pointerDown(const Offset(900, 500), 0);
        for (var i = 1; i <= 5; i++) {
          c.pointerMove(Offset(900 + 20.0 * i, 500), 16.0 * i);
        }
        c.pointerUp(const Offset(1000, 500), 90); // 빠르게 뗀다 — 관성
      } else {
        c.glide(.15); // → 키
      }
      expect(c.active.value, isTrue);
      app.paintNow(); // 끄는 동안 · 움직이는 동안의 마지막 그림 — 회색
      expect(atlas.lcdAllowed, isFalse);
      if (framesFirst > 0) await Future<void>.delayed(Duration(milliseconds: 16 * framesFirst)); // 앱의 시계가 움직임을 몇 장면 돌린다
      if (how.startsWith('관성')) {
        c.pointerDown(const Offset(1000, 500), 200); // 누름이 관성을 멈춘다
        c.pointerUp(const Offset(1000, 500), 260); // 끌지 않고 뗀다
      } else {
        c.stop(); // Esc
      }
      final stopped = Stopwatch()..start();
      expect(c.active.value, isFalse);
      if (framesFirst == 0) expect(scene.busy.value, isFalse, reason: '시계가 멎었다 — 이 뒤로 그림을 부를 것은 장면의 알림뿐이다');
      for (var i = 0; i < 200 && !atlas.lcdAllowed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(atlas.lcdAllowed, isTrue, reason: '멈춘 자리의 장면이 ClearType으로 다시 그려진다');
      expect(stopped.elapsedMilliseconds, greaterThanOrEqualTo(clearTypeSettleMs - 5), reason: '멈춘 뒤 150ms 문턱은 그대로');
    });
  }

  test('두 손가락 확대 중 → 회색 · 떼면 알리고 허락', () async {
    final (atlas, scene, painter) = await still();
    final c = scene.controller;
    c.pinchStart(const Offset(960, 500));
    c.pinchUpdate(const Offset(960, 500), 1.2);
    expect(c.pinching, isTrue);
    expect(c.active.value, isFalse);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    var told = 0;
    scene.addListener(() => told++);
    c.pinchEnd();
    expect(told, greaterThan(0));
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '150ms 문턱 안');
    // 배율이 1.2로 바뀌었다 — 그 배율의 이름 판 · 타일이 오고 150ms가 지나면 허락
    expect(await paintUntilAllowed(scene, painter, atlas), isTrue);
  });

  test('화면 배율 1.5 → 회색 · 설정 끔 → 회색 · Windows 설정 끔 → 회색', () async {
    final (atlas, scene, painter) = await still();
    paint(painter);
    expect(atlas.lcdAllowed, isTrue); // 같은 장면에서 조건 하나씩만 바꾼다
    painter.devicePixelRatio = 1.5;
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    painter.devicePixelRatio = 1;
    ClearTypePrefs.on = false;
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    ClearTypePrefs.on = true;
    ClearTypePrefs.system = const ClearTypeInfo(false, false);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    ClearTypePrefs.system = const ClearTypeInfo(true, false);
    // 화면 배율을 바꾼 장면은 이름 판을 새로 청한다 — 그 답과 150ms 뒤에 다시 허락
    expect(await paintUntilAllowed(scene, painter, atlas), isTrue);
  });

  test('굽개가 없으면(DLL을 못 엶) 멈춰도 회색 — 글줄마다 글꼴 파일을 찾지 않는다', () async {
    var looked = 0;
    final (atlas, _, painter) = await still(text: AtlasText(fontFileOf: (_) {
      looked++;
      return 'fake.otf';
    }));
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    expect(looked, 0, reason: '굽지 못하는데 새 글줄마다 글꼴 파일을 찾는(existsSync) 헛일');
  });

  test('칸 차례(파초빨)는 Windows 설정을 따른다', () async {
    final (atlas, _, painter) = await still();
    paint(painter);
    expect(atlas.bgr, isFalse);
    ClearTypePrefs.system = const ClearTypeInfo(true, true);
    paint(painter);
    expect(atlas.bgr, isTrue);
  });

  test('그림 저장의 그림판은 늘 회색(검토 초점 5)', () async {
    final (atlas, scene, painter) = await still(clearType: false);
    expect(scene.stillForClearType, isTrue); // 장면은 멈췄어도
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
  });

  test('멈춘 장면은 실제로 ClearType으로 찍고 움직이면 회색으로 찍는다', () async {
    final (atlas, scene, painter) = await still();
    for (var i = 0; i < 12 && atlas.lcdSprites == 0; i++) {
      paint(painter);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // 굽개의 답이 장에 오를 틈
    }
    expect(atlas.lcdSprites, greaterThan(0));
    scene.controller.active.value = true;
    paint(painter);
    expect(atlas.lcdSprites, 0);
  });

  test('멈춘 뒤 150ms가 되는 장면에 한 장 더 그리게 알린다(검토 초점 2) · 그 뒤로는 더 알리지 않는다', () async {
    var now = 0.0; // 장면 시계를 손으로 — 타일은 0에 도착해 떠오르는 중
    final (scene, _, _) = make(clock: () => now);
    await loadAll(scene);
    await labelsDone(scene);
    scene.tick(16); // 타일이 막 도착해 떠오르는 중의 장면 — 마지막으로 그린 장면은 회색이었다
    expect(scene.stillForClearType, isFalse);
    now = 10;
    scene.hide.add('fade');
    scene.prepare(); // 그림판의 장면 준비가 떠오름이 끝났음을 안다 — 가라앉음은 10부터
    await labelsDone(scene); // 그 장면이 새로 청한 이름 판(가라앉음은 그 판이 와서부터 — 시계는 그대로 10)
    var told = 0;
    scene.addListener(() => told++);
    scene.tick(16);
    expect(scene.stillForClearType, isFalse, reason: '멎은 첫 장면은 아직 150ms 안');
    now = 10 + clearTypeSettleMs - 1;
    scene.tick(16);
    expect(scene.stillForClearType, isFalse);
    expect(told, 0, reason: '150ms 안에는 알리지 않는다');
    now = 10 + clearTypeSettleMs;
    scene.tick(16); // 150ms가 된 장면
    expect(scene.stillForClearType, isTrue);
    expect(told, 1, reason: '150ms가 된 장면에서 한 번 알려 ClearType으로 다시 그리게 한다');
    now += 100;
    scene.tick(16);
    scene.tick(16);
    expect(told, 1, reason: '멈춘 채로는 다시 알리지 않는다 — 멈춤 ↔ 바쁨의 고리가 없다');
    expect(scene.busy.value, isFalse);
  });

  // 아래 둘은 장면 시계를 손으로 돌려 문턱의 안팎을 본다 — 타이머만 실제 시간으로 기다린다.
  test('멈춘 뒤 150ms 안에는 회색 · 150ms 뒤 시계가 멎어 있어도 장면이 알리고 ClearType', () async {
    final (atlas, scene, painter, clock) = await stillByHand();
    scene.controller.active.value = true; // 쫓아가기 · 돋보기처럼 움직임
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    clock.now += 500;
    scene.controller.active.value = false;
    final stopped = clock.now, wall = Stopwatch()..start();
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '멎은 그 장면');
    for (final after in const [60.0, clearTypeSettleMs - 1]) {
      clock.now = stopped + after;
      paint(painter);
      expect(atlas.lcdAllowed, isFalse, reason: '멎은 지 ${after}ms');
    }
    clock.now = stopped + clearTypeSettleMs;
    await toldStill(scene); // 시계(tick)를 돌리지 않는다 — 타이머가 깨운다
    expect(wall.elapsedMilliseconds, greaterThanOrEqualTo(clearTypeSettleMs - 5), reason: '타이머는 멎은 장면에서 150ms 뒤에 깨운다');
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('150ms 안에 다시 움직이면 처음부터 다시 기다린다', () async {
    final (atlas, scene, painter, clock) = await stillByHand();
    final c = scene.controller;
    c.active.value = true;
    paint(painter);
    c.active.value = false;
    final first = clock.now;
    paint(painter);
    clock.now = first + 100;
    c.active.value = true; // 100ms 만에 다시 움직인다
    paint(painter);
    expect(atlas.lcdAllowed, isFalse);
    c.active.value = false;
    final again = clock.now;
    paint(painter);
    clock.now = again + 100; // 처음 멎은 때부터는 200ms
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '다시 멎은 지 100ms — 처음 멎은 때부터 세지 않는다');
    clock.now = again + clearTypeSettleMs;
    await toldStill(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('움직임 없이 보기가 한 번에 뛰어도(범위 바꾸기) 그 장면부터 150ms는 회색 — 뛴 한 장만 ClearType이었다 돌아가지 않게', () async {
    final (atlas, scene, painter) = await still();
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
    final v = scene.controller.view;
    scene.controller.showRange(v.lo + v.span * .04, v.hi + v.span * .04); // 쫓아가기 없이 곧바로 옮긴다(검증 대본의 range와 같은 길)
    expect(scene.controller.moving, isFalse);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '뛴 그 장면');
    expect(await paintUntilAllowed(scene, painter, atlas), isTrue);
  });

  test('화면에 걸린 타일을 기다리는 동안은 회색 · 다 와서 150ms 뒤 ClearType', () async {
    final gate = Completer<void>();
    final atlas = newAtlas();
    final (scene, painter, _) = make(text: atlas, gate: gate.future);
    scene.hide.add('fade');
    paint(painter); // 타일을 청한다
    expect(scene.waitingTiles, isTrue);
    expect(atlas.lcdAllowed, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 250)); // 움직임은 없고 150ms가 넘게 지나도
    paint(painter);
    expect(scene.waitingTiles, isTrue);
    expect(scene.stillForClearType, isFalse);
    expect(atlas.lcdAllowed, isFalse, reason: '타일을 기다리는 동안은 회색 — 오면 바뀔 장면을 ClearType으로 먼저 그리지 않는다');
    gate.complete();
    await loadAll(scene);
    paint(painter);
    expect(scene.waitingTiles, isFalse);
    await toldStill(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  test('옮긴 뒤 새로 청한 이름 판을 기다리는 동안도 회색 — 판이 오면 이름이 드나들어 다시 회색이 될 장면을 ClearType으로 먼저 그리지 않는다', () async {
    Completer<void>? hold;
    final (atlas, scene, painter, clock) = await stillByHand(labelHold: () => hold?.future ?? Future<void>.value());
    hold = Completer<void>();
    final v = scene.controller.view;
    scene.controller.showRange(v.lo + v.span * .5, v.hi + v.span * .5); // 폭의 40% 넘게 옮겨 이름 판을 새로 청한다
    await loadAll(scene); // 타일은 모두 온다
    expect(scene.waitingTiles, isFalse);
    expect(scene.labelWorker.busy, isTrue);
    clock.now += clearTypeSettleMs * 3;
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '움직임 · 타일 기다림은 없고 150ms가 넘게 지났어도 이름 판을 기다리는 중');
    hold.complete();
    await labelsDone(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '판이 온 그 장면부터 150ms');
    clock.now += clearTypeSettleMs;
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });

  // 고치기 2바퀴: 보기가 그대로인데 강조(고르기) · 관점 이름 · 비켜 갈 구간만 바뀌어 이름 판을 새로 청할 때는 '멈춤'을 깨지 않는다 —
  // 고를 때마다 화면 전체가 ClearType → 회색 → ClearType으로 번쩍이지 않게. 이름이 실제로 드나들면 이름 옅어짐이 회색으로 둔다.
  for (final (what, change) in <(String, void Function(TimelineScene))>[
    ('강조(고르기)', (s) => em.Emphasis.of(s).set(const em.Look(band: 1))),
    ('관점 이름', (s) => LensTitles.of(s).put(events: {77: '다른 이름'})),
    ('비켜 갈 구간', (s) => ReservedZones.of(s).put('검사', {0: const [ReservedZone(0, 1000)]})),
  ]) {
    test('멈춰 허락된 장면에서 $what만 바뀌면 이름 판을 새로 청해도 ClearType 그대로 — 알림 없이 회색으로 바뀌지 않는다', () async {
      Completer<void>? hold;
      final (atlas, scene, painter, clock) = await stillByHand(labelHold: () => hold?.future ?? Future<void>.value());
      hold = Completer<void>();
      final asked = scene.labelVersion;
      change(scene);
      paint(painter);
      expect(scene.labelVersion, greaterThan(asked), reason: '서명이 바뀌어 이름 판을 새로 청했다');
      expect(scene.labelWorker.busy, isTrue);
      expect(atlas.lcdAllowed, isTrue, reason: '보기는 그대로 — 판을 기다리는 동안에도 ClearType');
      clock.now += clearTypeSettleMs * 3;
      paint(painter);
      expect(atlas.lcdAllowed, isTrue);
      hold.complete();
      await labelsDone(scene);
      paint(painter);
      expect(atlas.lcdAllowed, isTrue, reason: '판이 와도 이름이 그대로면 그대로');
    });
  }

  test('보기가 바뀐 뒤 처음 가라앉기 전에는 강조 · 비켜 갈 구간 때문에 청한 판도 기다린다 — 옮긴 뒤 첫 그림이 서명을 바꿔 다시 청하는 판(실제 앱 range)', () async {
    Completer<void>? hold;
    final (atlas, scene, painter, clock) = await stillByHand(labelHold: () => hold?.future ?? Future<void>.value());
    hold = Completer<void>();
    final v = scene.controller.view;
    scene.controller.showRange(v.lo + v.span * .01, v.hi + v.span * .01); // 타일 · 줄은 그대로인 작은 옮김
    paint(painter);
    final asked = scene.labelVersion;
    expect(scene.labelWorker.busy, isFalse, reason: '보기 · 타일 쪽 서명은 그대로라 이 옮김만으로는 판을 청하지 않는다');
    ReservedZones.of(scene).put('검사', {0: const [ReservedZone(0, 1000)]}); // 옮긴 뒤 첫 그림이 관계선의 비켜 갈 구간을 고친 것과 같다
    paint(painter);
    expect(scene.labelVersion, greaterThan(asked));
    expect(scene.labelWorker.busy, isTrue);
    clock.now += clearTypeSettleMs * 3;
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '옮긴 뒤 아직 한 번도 가라앉지 않았다 — 이 판이 오면 이름이 드나들 수 있다');
    hold.complete();
    await labelsDone(scene);
    paint(painter);
    expect(atlas.lcdAllowed, isFalse, reason: '판이 온 그 장면부터 150ms');
    clock.now += clearTypeSettleMs;
    paint(painter);
    expect(atlas.lcdAllowed, isTrue);
  });
}
