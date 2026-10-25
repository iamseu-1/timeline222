import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/legend.dart' show LegendSpot, legendSlot, legendSpotSlot;
import 'package:archive_prototype/ui/motion_meter.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 움직임 계측 · 느리게 보기(대조표 움직임-14) 검사.
//
// 가장 중요한 것은 **배율이 한 번만 먹는가**이다. Flutter는 장면 시각을 timeDilation으로 나눠 시계(Ticker)에 주므로
// 조작부의 `tick(dt)`와 줄 흐름은 저절로 함께 느려진다 — 거기서 또 나누면 4배가 16배가 된다.
// 그 사실을 여기서 진짜 Ticker로 재어 못 박는다(첫째 검사). 견본의 이름은 모두 가상이다.
//
// 창의 모습을 그림으로 뜨려면(app 폴더에서):
//   flutter test --no-pub test/motion_meter_test.dart --dart-define=OUT=../results/render-motion

const _year = 525960.0;
const _out = String.fromEnvironment('OUT');

/// 장면마다 흘러온 시간을 적는 작은 부품 — 진짜 시계(Ticker)로 재기 위한 것.
class _Beat extends StatefulWidget {
  const _Beat(this.onTick);
  final void Function(Duration elapsed) onTick;

  @override
  State<_Beat> createState() => _BeatState();
}

class _BeatState extends State<_Beat> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(widget.onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 100ms를 두 번 흘려보내고 **장면 사이에 시계가 읽은 시간**(ms)을 돌려준다.
Future<double> tickSpan(WidgetTester tester, {required double slow}) async {
  Motion.slow = slow;
  final beats = <Duration>[];
  await tester.pumpWidget(MaterialApp(home: _Beat(beats.add)));
  await tester.pump(const Duration(milliseconds: 100));
  beats.clear();
  await tester.pump(const Duration(milliseconds: 100));
  final first = beats.last;
  await tester.pump(const Duration(milliseconds: 100));
  final second = beats.last;
  await tester.pumpWidget(const SizedBox.shrink());
  return (second - first).inMicroseconds / 1000;
}

/// 실제로 [realMs]만큼 돌고 돈 시간(ms)을 돌려준다 — 느리게 보기의 시계가 정말 느려지는지 보려고.
double spin(double realMs) {
  final watch = Stopwatch()..start();
  while (watch.elapsedMicroseconds < realMs * 1000) {
    // 돌기만 한다.
  }
  return watch.elapsedMicroseconds / 1000;
}

/// 엔진이 알려 주는 장면 기록 하나(µs).
FrameTiming timing({required int vsync, required double buildMs, required double rasterMs}) => FrameTiming(
  vsyncStart: vsync,
  buildStart: vsync,
  buildFinish: vsync + (buildMs * 1000).round(),
  rasterStart: vsync + (buildMs * 1000).round(),
  rasterFinish: vsync + ((buildMs + rasterMs) * 1000).round(),
  rasterFinishWallTime: vsync + ((buildMs + rasterMs) * 1000).round(),
);

void main() {
  tearDown(() => Motion.slow = 1);

  group('느리게 보기 배율', () {
    testWidgets('배율은 장면 시각 하나로만 먹는다 — 시계가 읽는 dt가 이미 그만큼 줄어 있다', (tester) async {
      expect(await tickSpan(tester, slow: 1), closeTo(100, 1), reason: '보통 빠르기에서는 흘려보낸 만큼');
      expect(await tickSpan(tester, slow: 4), closeTo(25, 1), reason: '4배 느리게면 시계가 읽는 시간도 4분의 1 — 조작부는 여기서 또 나누지 않는다');
      expect(await tickSpan(tester, slow: 8), closeTo(12.5, 1));
      expect(await tickSpan(tester, slow: 1), closeTo(100, 1), reason: '1배로 되돌리면 그대로');
    });

    test('배율을 켜면 위젯의 움직임도 함께 느려진다(timeDilation)', () {
      Motion.slow = 2;
      expect(timeDilation, 2);
      Motion.slow = 8;
      expect(timeDilation, 8);
      Motion.slow = 1;
      expect(timeDilation, 1);
    });

    test('0이나 음수는 받지 않는다 — 1배로 둔다', () {
      Motion.slow = 4;
      Motion.slow = 0;
      expect(Motion.slow, 1);
      Motion.slow = 4;
      Motion.slow = double.nan;
      expect(Motion.slow, 1);
    });

    test('한 시계(Motion.now)는 배율을 바꿔도 이어 가고, 그만큼 느리게 흐른다', () {
      Motion.slow = 1;
      final before = Motion.now();
      Motion.slow = 4;
      final after = Motion.now();
      expect(after, greaterThanOrEqualTo(before), reason: '바꾸는 순간 뒤로 가지 않는다');
      expect(after - before, lessThan(5), reason: '바꾸는 순간 건너뛰지 않는다');

      final start = Motion.now();
      final real = spin(40);
      final ran = Motion.now() - start;
      expect(ran, closeTo(real / 4, real / 4 * .4 + 1), reason: '4배 느리게면 같은 실제 시간에 4분의 1만 흐른다');
      Motion.slow = 1;
    });
  });

  group('최근 2초의 장면', () {
    MotionWindow fill({required int count, double buildMs = 2, double rasterMs = 2, double from = 0}) {
      final window = MotionWindow();
      for (int i = 0; i < count; i++) {
        final at = from + i * 1000 / 60;
        window.add(vsyncMs: at, seenMs: at, buildMs: buildMs, rasterMs: rasterMs, moving: true);
      }
      return window;
    }

    test('2초보다 오래된 장면은 버린다', () {
      final window = fill(count: 240); // 60Hz로 4초
      expect(window.length, lessThanOrEqualTo(121));
      expect(window.frames.first.seenMs, greaterThanOrEqualTo(window.frames.last.seenMs - 2000));
      // 그리기가 멎어 기록이 더 오지 않아도 스스로 비운다.
      window.trim(window.frames.last.seenMs + 3000);
      expect(window.isEmpty, isTrue);
    });

    test('멎어 있던 참에 온 장면도, 다시 움직이기 시작한 첫 장면도 간격을 세지 않는다', () {
      final window = MotionWindow();
      window.add(vsyncMs: 0, seenMs: 0, buildMs: 2, rasterMs: 2, moving: true);
      // 300ms 쉬었다 온 장면 — 놓친 것이 아니다.
      window.add(vsyncMs: 300, seenMs: 300, buildMs: 2, rasterMs: 2, moving: false);
      expect(window.frames.last.gapMs, 0);
      expect(window.judgeNow(60).missedRatio, 0);
      // 멎어 있다 **다시 움직이기 시작한 첫 장면**도 앞의 쉬던 틈을 뒤집어쓰지 않는다
      // (2단계 측정의 `_join`과 같은 규칙 — 앞 장면도 그리는 중이어야 센다). 연표에 손을 대는 순간마다
      // '50ms 멈춤 1 · 놓친 장면 1%'가 빨갛게 뜨던 거짓 경보를 막는 자리다.
      window.add(vsyncMs: 600, seenMs: 600, buildMs: 2, rasterMs: 2, moving: true);
      expect(window.frames.last.gapMs, 0);
      final started = window.judgeNow(60);
      expect(started.missedRatio, 0);
      expect(started.over50, 0);
      // 그리는 도중의 틈만 놓친 장면이다.
      window.add(vsyncMs: 900, seenMs: 900, buildMs: 2, rasterMs: 2, moving: true);
      expect(window.frames.last.gapMs, 300);
      final during = window.judgeNow(60);
      expect(during.missedRatio, greaterThan(0));
      expect(during.over50, 1);
    });

    test('다시 비운 창은 앞 장면의 기억도 지운다 — 창을 여닫아도 첫 장면이 틈을 뒤집어쓰지 않는다', () {
      final window = MotionWindow();
      window.add(vsyncMs: 0, seenMs: 0, buildMs: 2, rasterMs: 2, moving: true);
      window.clear();
      window.add(vsyncMs: 500, seenMs: 500, buildMs: 2, rasterMs: 2, moving: true);
      expect(window.frames.single.gapMs, 0);
    });

    test('2단계 측정과 같은 판정으로 읽는다 — 예산을 넘은 장면 · 연달아 둘', () {
      final window = fill(count: 60);
      expect(window.judgeNow(60).pass, isTrue);
      expect(window.judgeNow(60).missedRatio, 0);
      // 60Hz의 예산은 16.7ms. 만들기가 넘은 장면 둘을 잇따라 넣는다.
      window
        ..add(vsyncMs: 1000, seenMs: 1000, buildMs: 30, rasterMs: 2, moving: true)
        ..add(vsyncMs: 1030, seenMs: 1030, buildMs: 30, rasterMs: 2, moving: true);
      final verdict = window.judgeNow(60);
      expect(verdict.maxConsecutiveMissed, 2);
      expect(verdict.missedByBuild, 2);
      expect(verdict.pass, isFalse);
    });
  });

  group('계측 창', () {
    Future<(AppBus, TimelineScene)> pumpMeter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final bus = AppBus(ask: (q) async => <String, dynamic>{}, controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Stack(children: [Positioned.fill(child: MotionMeter(bus: bus))])),
        ),
      );
      return (bus, scene);
    }

    /// 창을 열고 나타남이 끝날 때까지.
    Future<void> open(WidgetTester tester, AppBus bus) async {
      runCommand(bus, Cmd.motion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('메뉴의 `◔ 움직임 계측`이 오면 열리고, 다시 오면 닫힌다', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      expect(find.text('움직임 계측'), findsNothing);
      await open(tester, bus);
      expect(find.text('움직임 계측'), findsOneWidget);
      expect(MotionMeter.isOpen(bus), isTrue, reason: '메뉴의 ✓가 읽을 값');
      expect(find.text('1×'), findsOneWidget);
      expect(find.text('8×'), findsOneWidget);
      expect(find.text('놓친 장면'), findsOneWidget);

      runCommand(bus, Cmd.motion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('움직임 계측'), findsNothing);
      expect(MotionMeter.isOpen(bus), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('빠르기 단추를 누르면 그 배율로 느려지고, 창을 닫으면 1배로 돌아온다', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      await open(tester, bus);
      await tester.tap(find.text('4×'));
      await tester.pump();
      expect(Motion.slow, 4);
      expect(timeDilation, 4);

      runCommand(bus, Cmd.motion);
      await tester.pump();
      expect(Motion.slow, 1, reason: '창을 닫으면 느린 채로 남지 않는다');
      expect(timeDilation, 1);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('엔진이 알려 주는 장면 기록을 ms로 담고, 멎어 있던 틈은 세지 않는다', (tester) async {
      final (bus, scene) = await pumpMeter(tester);
      await open(tester, bus);
      final state = tester.state<MotionMeterState>(find.byType(MotionMeter));

      // 멎어 있는 동안 — 간격은 0.
      state.collect([timing(vsync: 0, buildMs: 4, rasterMs: 3), timing(vsync: 16700, buildMs: 2, rasterMs: 1)]);
      expect(state.window.length, 2);
      expect(state.window.frames.first.buildMs, closeTo(4, .001));
      expect(state.window.frames.first.rasterMs, closeTo(3, .001));
      expect(state.window.frames.last.gapMs, 0);

      // 움직이기 시작한 첫 장면 — 앞의 쉬던 틈은 이 장면의 몫이 아니다.
      bus.controller.flyTo(-3000 * _year, -2900 * _year);
      expect(scene.busy.value, isTrue);
      state.collect([timing(vsync: 33400, buildMs: 2, rasterMs: 1)]);
      expect(state.window.frames.last.gapMs, 0);
      // 그리는 도중의 간격만 센다.
      state.collect([timing(vsync: 50100, buildMs: 2, rasterMs: 1)]);
      expect(state.window.frames.last.gapMs, closeTo(16.7, .01));
      expect(state.window.judgeNow(60).frames, 4);
      expect(state.window.judgeNow(60).missedRatio, 0);

      bus.controller.stop();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('이 창이 스스로 부른 되그리기는 틈으로 세지 않는다 — 손을 댄 채 멈춰 있을 때', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      await open(tester, bus);
      final state = tester.state<MotionMeterState>(find.byType(MotionMeter));

      // 손은 닿아 있는데(끌기) 연표는 멎어 있다 — 앱이 그릴 것은 없고 0.15초마다 이 창만 다시 그린다.
      bus.controller.dragging = true;
      final mine = <int>[];
      for (int i = 0; i < 2; i++) {
        spin(20); // 창의 글('끌기 x.xx초')이 달라지도록 실제 시간을 흘린다 — 달라져야 다시 그린다.
        await tester.pump(const Duration(milliseconds: 150));
        mine.add(SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds);
      }
      expect(mine.last - mine.first, greaterThanOrEqualTo(100000), reason: '되그리기 사이는 0.15초 — 그대로 세면 없는 멈춤이 된다');

      // 그 두 장면의 기록이 엔진에서 온다.
      state.collect([for (final at in mine) timing(vsync: at, buildMs: 1, rasterMs: 1)]);
      expect(state.window.length, 2);
      expect(state.window.frames.last.gapMs, 0);
      final verdict = state.window.judgeNow(60);
      expect(verdict.over50, 0, reason: '재는 도구가 제가 낸 장면으로 멈춤을 만들어 내지 않는다');
      expect(verdict.missedRatio, 0);

      bus.controller.dragging = false;
      runCommand(bus, Cmd.motion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('멎어 있고 값도 그대로면 다시 그리지 않는다 — 창이 스스로 장면을 만들어 내지 않게', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      await open(tester, bus);
      // 2초가 지나 창이 비고 도는 움직임도 없으면 0.15초 되그리기는 더 할 일이 없다.
      await tester.pump(const Duration(milliseconds: 2200));
      final quiet = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(SchedulerBinding.instance.currentSystemFrameTimeStamp, quiet, reason: '새 장면이 없었다');
      expect(find.textContaining('멎어 있음'), findsOneWidget);

      runCommand(bus, Cmd.motion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('진행 중인 움직임의 이름과 길이를 적는다', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      await open(tester, bus);
      expect(find.textContaining('멎어 있음'), findsOneWidget);

      bus.controller.flyTo(-3000 * _year, -2900 * _year);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.textContaining('비행'), findsOneWidget);
      expect(tester.state<MotionMeterState>(find.byType(MotionMeter)).running().single.name, '비행');

      bus.controller.stop();
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.textContaining('멎어 있음'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('자리는 왼쪽 12 · 바닥에서 16이고, 범례가 열리면 324로 비킨다', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      await open(tester, bus);
      final card = find.byType(GlassCard).first;
      expect(tester.getTopLeft(card).dx, closeTo(12, .01));
      expect(1080 - tester.getBottomLeft(card).dy, closeTo(16, .01));

      bus.slot(legendSlot).value = true;
      await tester.pump();
      expect(tester.getTopLeft(find.byType(GlassCard).first).dx, closeTo(324, .01));

      // 서고 폴더 범례(리메이크 4단계)는 제 자리를 슬롯에 적는다 — 그 오른쪽 끝 + 12로 비킨다.
      bus.slot(legendSpotSlot).value = const LegendSpot(Rect.fromLTWH(16, 300, 752, 760), Rect.fromLTWH(16, 300, 752, 760));
      await tester.pump();
      expect(tester.getTopLeft(find.byType(GlassCard).first).dx, closeTo(780, .01));
      bus.slot(legendSpotSlot).value = null;
      await tester.pump();
      expect(tester.getTopLeft(find.byType(GlassCard).first).dx, closeTo(324, .01));

      runCommand(bus, Cmd.motion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('머리를 끌면 창이 그 자리로 옮겨진다 — 붙잡은 자리가 어긋나지 않는다', (tester) async {
      final (bus, _) = await pumpMeter(tester);
      await open(tester, bus);
      final before = tester.getTopLeft(find.byType(GlassCard).first);
      await tester.drag(find.text('움직임 계측'), const Offset(200, -300));
      await tester.pump();
      final after = tester.getTopLeft(find.byType(GlassCard).first);
      expect(after.dx - before.dx, closeTo(200, .01));
      expect(after.dy - before.dy, closeTo(-300, .01));

      // 옮긴 뒤에는 범례가 열려도 비키지 않는다.
      bus.slot(legendSlot).value = true;
      await tester.pump();
      expect(tester.getTopLeft(find.byType(GlassCard).first).dx, closeTo(after.dx, .01));

      runCommand(bus, Cmd.motion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('창의 모습을 그림으로 뜬다', (tester) async {
      await loadFonts();
      tester.view.physicalSize = const Size(248, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final bus = AppBus(ask: (q) async => <String, dynamic>{}, controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      const key = ValueKey('뜨기');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: Ui.bg,
              body: Stack(children: [Positioned.fill(child: MotionMeter(bus: bus))]),
            ),
          ),
        ),
      );
      await open(tester, bus);
      // 값이 든 모습으로 뜬다: 60Hz의 보통 장면 100개와 예산을 넘은 장면 하나, 그리고 비행 중.
      final state = tester.state<MotionMeterState>(find.byType(MotionMeter));
      for (int i = 0; i < 100; i++) {
        state.window.add(vsyncMs: i * 16.7, seenMs: i * 16.7, buildMs: 2 + (i % 7) * .4, rasterMs: 1.6 + (i % 5) * .3, moving: true);
      }
      state.window.add(vsyncMs: 1670, seenMs: 1670, buildMs: 19.4, rasterMs: 3.1, moving: true);
      bus.controller.flyTo(-3000 * _year, -2900 * _year);
      await tester.pump(const Duration(milliseconds: 160));

      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final folder = Directory(_out)..createSync(recursive: true);
      File('${folder.path}/계측창.png').writeAsBytesSync(bytes!);

      bus.controller.stop();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
          // 그림은 --dart-define=OUT=<폴더>를 줄 때만 뜬다.
    }, skip: _out.isEmpty);
  });
}

/// 검사 환경에는 시스템 글꼴이 없다 — 이 PC의 글꼴을 같은 이름으로 올린다(render_scene_test와 같은 길).
Future<void> loadFonts() async {
  await loadAppFonts();
  for (final (family, path) in [('Noto Sans KR', 'C:/Windows/Fonts/NotoSansKR-VF.ttf'), ('Malgun Gothic', 'C:/Windows/Fonts/malgun.ttf')]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)))).load();
  }
}
