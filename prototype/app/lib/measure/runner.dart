import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../archive_app.dart';
import '../motion.dart';
import '../scene/paint/links.dart' show LineAudit;
import '../scene/text_paragraph.dart' show SceneText, TextProbe;
import '../ui/filter_state.dart';
import 'frame_stats.dart';
import 'report.dart';
import 'scenarios.dart';
import 'verify_script.dart';

// 측정 실행: 시험 구간을 합성 입력으로 재생하고 장면 기록을 합격선과 견준다.
// 입력은 Flutter의 입력 경로(GestureBinding)로 넣는 합성 입력이다 — 실물 입력 장치의 지연 · 물리 화면의 표시 시각과 구분한다.
//   --measure=<결과 폴더> [--sections=끌기,확대,돋보기,밀집,세로,자료집] [--seconds=30] [--repeats=3] [--cold=yes|no]
//   [--from=<분> --to=<분>] [--hide=층,…] [--capture-only=yes [--capture-scene=밀집] [--capture-mag=1.5]] [--exit=yes]
//   계보 창 구간(D1 — 기본 목록에는 없음): --sections=승계표,세계표 --kin-polity=<정권 uid> --kin-family=<뿌리 뼈대 uid>
// 구간마다: 처음 1회(찬 상태 — 타일 보관을 비우고)는 따로 적고, 이어서 [repeats]회를 재서 판정한다.

class MeasureOptions {
  const MeasureOptions({this.sections = sectionNames, this.seconds = 30, this.repeats = 3, this.cold = true, this.from, this.to, this.hide = const {}, this.captureOnly = false, this.captureScene = '', this.captureMag, this.captureScroll = 0});

  /// 그림을 뜰 때의 세로 자리(배치 px).
  final double captureScroll;
  final List<String> sections;
  final int seconds, repeats;
  final bool cold, captureOnly;
  final double? from, to, captureMag;
  final Set<String> hide;
  final String captureScene;

  factory MeasureOptions.fromArguments(String? Function(String name) option) => MeasureOptions(
    sections: (option('--sections') ?? sectionNames.join(',')).split(',').where((s) => s.isNotEmpty).toList(),
    seconds: int.parse(option('--seconds') ?? '30'),
    repeats: int.parse(option('--repeats') ?? '3'),
    cold: option('--cold') != 'no',
    from: double.tryParse(option('--from') ?? ''),
    to: double.tryParse(option('--to') ?? ''),
    // 병목을 가르는 실험용: 층을 끄고 잰다(정식 측정에는 쓰지 않는다).
    hide: (option('--hide') ?? '').split(',').where((s) => s.isNotEmpty).toSet(),
    captureOnly: option('--capture-only') == 'yes',
    captureScene: option('--capture-scene') ?? '',
    captureMag: double.tryParse(option('--capture-mag') ?? ''),
    captureScroll: double.tryParse(option('--capture-scroll') ?? '') ?? 0,
  );
}

class _Frame {
  _Frame(this.vsyncMicros, this.moving, this.hadInput, this.note);
  final int vsyncMicros;
  final bool moving, hadInput;

  /// 놓친 장면의 까닭을 짚을 단서: 그 장면의 도형 · 글자 · 새 글줄 수, 떠오르던 타일, 단계, 보관 바이트.
  final Map<String, num> note;
}

/// 측정기의 합성 입력에 붙이는 장치 번호. 측정 중의 연표는 이 번호의 입력만 받는다 — 재는 동안 사람 손이 장면을 바꾸지 않게.
const measureDevice = 9071;

/// 돌려주는 값은 보고서(측정.json과 같은 내용). 그림만 뜨는 경우와 실패하면 null.
Future<Map<String, dynamic>?> runMeasure(ArchiveAppState app, String output, {MeasureOptions? options, void Function(String progress)? onProgress}) async {
  // 재는 동안은 늘 1배다 — 계측 창을 4배로 열어 둔 채 '측정'을 눌러도 시간과 입력 응답이 어긋나지 않게(ui/motion_meter.dart 머리말).
  Motion.slow = 1;
  final o = options ?? MeasureOptions.fromArguments(app.option);
  final directory = Directory(output);
  await directory.create(recursive: true);
  final scene = app.scene!, c = app.controller;
  scene.hide.addAll(o.hide);
  final timings = <FrameTiming>[];
  final frames = <_Frame>[];
  final shapes = <num>[], labels = <num>[], paintMs = <num>[], textMs = <num>[], rss = <num>[];
  int blanks = 0, covers = 0, newGlyphs = 0;
  bool measuring = false, inputThisFrame = false;
  // 지금 재는 구간이 계보 창 구간(승계표 · 세계표)이면 그 구간 — 장면 기록에 창의 움직임 · 입력 · 단서를 더한다(D1-N4).
  KinSection? kinCase;
  void collect(List<FrameTiming> values) {
    if (measuring) timings.addAll(values);
  }

  SchedulerBinding.instance.addTimingsCallback(collect);
  // 장면마다(지속 콜백은 뗄 수 없으니 깃발로 끈다).
  bool alive = true;
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    if (!alive || !measuring) return;
    final s = scene.stats;
    final kin = kinCase;
    frames.add(
      _Frame(SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds, c.moving || (kin?.moving ?? false), inputThisFrame || (kin?.acted ?? false), {
        'shapes': s.shapes, 'labels': s.labels, 'new_glyphs': s.newParagraphs, 'fading': scene.fading ? 1 : 0, 'tiles': s.tiles, 'covers': s.covers,
        'level': scene.level, 'paint_ms': s.paintMs, 'rss_mib': ProcessInfo.currentRss ~/ 1048576,
        ...?kin?.frameNote,
      }),
    );
    inputThisFrame = false;
  });
  scene.onPainted = (s) {
    if (!measuring) return;
    shapes.add(s.shapes);
    labels.add(s.labels);
    paintMs.add(s.paintMs);
    textMs.add(s.textMs);
    blanks += s.blanks;
    covers += s.covers;
    newGlyphs += s.newParagraphs;
  };
  var peakRss = ProcessInfo.currentRss;
  final memory = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = ProcessInfo.currentRss;
    peakRss = math.max(peakRss, now);
    if (measuring) rss.add(now / 1048576);
  });
  final cases = <Map<String, dynamic>>[];
  final inputs = c.inputLog = <String>[];
  final allPacks = scene.layout.enabledPacks.toSet();
  try {
    // 같은 날에 사건이 몰린 날(생성 자료의 dense_day). 없는 자료(월흔해)에서는 '밀집'도 보통 장면에서 잰다.
    final denseDay = double.tryParse('${app.meta?['dense_day'] ?? ''}');
    void startScene([String name = '']) {
      scene.setPacks(allPacks);
      if (name == '밀집' && denseDay != null) {
        c.showRange((denseDay - 1.5) * 1440, (denseDay + 2.5) * 1440); // 나흘 보기: 몰린 하루가 화면의 1/4
      } else if (o.from != null && o.to != null) {
        c.showRange(o.from!, o.to!);
      } else {
        c.showAll();
      }
      c.magnifyTo(1, Offset(c.view.width / 2, c.view.height / 2));
      c.scrollTo(0);
    }

    startScene(o.captureScene);
    if (o.captureMag != null) c.magnifyTo(o.captureMag!, Offset(c.view.width / 2, c.view.height / 2));
    // 줄이 접히고 흐른 뒤의 자리에서 세로로 옮긴다(빈 줄 접기의 답과 360ms의 흐름을 기다림).
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // 0이어도 다시 놓는다 — 줄이 접히는 동안 세로 닻이 보던 줄을 붙잡느라 자리가 조금 옮겨질 수 있다.
    c.scrollTo(o.captureScroll);
    // 검증용: --capture-pick=<uid>[@<칸 참조>]이면 그 항목을 고르고(상세 창이 열린다), --capture-echo=yes면 '같은 시기를 타국에도'를 켠 채로 찍는다.
    final pick = app.option('--capture-pick') ?? '';
    if (pick.isNotEmpty && app.bus != null) {
      final at = pick.indexOf('@');
      if (app.option('--capture-echo') == 'yes') {
        // 스위치는 필터 시트의 show.spotEcho와 한 값이다(그쪽이 먼저 읽힌다).
        final filters = app.bus!.slot('filters').value;
        app.bus!.slot('filters').value = FilterState.orSeed(filters, app.bus!.conditions.value).withShowing('spotEcho', true);
      }
      app.bus!.select(at < 0 ? pick : pick.substring(0, at), cell: at < 0 ? null : pick.substring(at + 1));
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    // 검증 대본: 실제 앱을 눌러 보며 걸음마다 찍는다(measure/verify_script.dart).
    final script = app.option('--capture-script') ?? '';
    // --capture-text=yes: 마지막 장면에 그린 글줄의 상자(scene/text_paragraph.dart TextProbe)를 1배 그림과 함께 남긴다 — 글끼리 겹침을 상자로 찾는 검사 전용.
    // 대본 앞에서 켠다 — 대본의 burst가 장면마다 상자를 함께 남긴다(움직이는 동안의 겹침).
    final probe = app.option('--capture-text') == 'yes' ? (SceneText.probe = TextProbe()) : null;
    // --capture-lines=yes: 마지막 장면의 선 감사(scene/paint/links.dart LineAudit — 다른 띠 뒤로 숨은 px · 안 보이는 선 · 빠진 선 · S길)를
    // 1배 그림과 함께 '선-감사.json'으로 남긴다(이어 주는 선 걸음 1 — 찍기 · 검사 전용 · 그림은 그대로).
    final lineAudit = app.option('--capture-lines') == 'yes';
    if (lineAudit) LineAudit.capture = true;
    if (script.isNotEmpty) await runVerifyScript(app, script, directory);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (probe != null || lineAudit) {
      scene.requestFrame();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await app.screenshot('${directory.path}/화면-1배.png');
    if (probe != null) {
      await File('${directory.path}/글-상자.json').writeAsString(textBoxesJson(app, probe));
      SceneText.probe = null;
    }
    if (lineAudit) {
      await File('${directory.path}/선-감사.json').writeAsString(const JsonEncoder.withIndent(' ').convert(LineAudit.last?.toJson() ?? const {'lines': 0}));
      LineAudit.capture = false;
    }
    await File('${directory.path}/시작-장면.json').writeAsString(
      jsonEncode({
        'asked': [o.from, o.to], 'view': [c.view.lo, c.view.hi], 'size': [c.view.width, c.view.height], 'inputs_before_capture': inputs,
        // 실행부터 첫 조작이 가능해질 때까지(ms) — 측정 스크립트가 실행 시각을 넘겼을 때만.
        'launch_to_ready_ms': app.launchToReadyMs, 'first_ready_ms': app.firstReadyMs,
        // 그림을 뜨기까지 실패한 조회(부품이 조용히 삼킨 것) — 비어 있어야 한다.
        'ask_failures': app.askFailures,
      }),
    );
    if (o.captureOnly) return null;

    final box = app.timelineKey.currentContext!.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final hz = SchedulerBinding.instance.platformDispatcher.views.first.display.refreshRate;
    final trackless = [for (final p in scene.layout.packs) if (!scene.layout.tracks.any((t) => t.pack == p.id)) p.id];
    final runs = o.sections.length * (o.repeats + (o.cold ? 1 : 0));
    for (final name in o.sections) {
      for (int repeat = o.cold ? 0 : 1; repeat <= o.repeats; repeat++) {
        final cold = repeat == 0;
        onProgress?.call('${cases.length + 1}/$runs · $name${cold ? ' (처음)' : ' #$repeat'}');
        if (cold) scene.cache.clear(); // 찬 상태: 보관이 비어 있을 때의 첫 조작
        startScene(name);
        await Future<void>.delayed(Duration(milliseconds: cold ? 300 : 2000));
        timings.clear();
        frames.clear();
        for (final list in [shapes, labels, paintMs, textMs, rss]) {
          list.clear();
        }
        blanks = covers = newGlyphs = 0;
        final requests = scene.cache.requests, trips = scene.cache.roundTrips.length;
        inputs.clear();
        measuring = true;
        final clock = Stopwatch()..start();
        final scenario = scenarioFor(
          name, width: c.view.width, height: c.view.height, packs: scene.layout.enabledPacks, trackless: trackless,
          // 계보 창 구간이면 앱 창(D1-N2 KinDriver)을 부리는 측정 손잡이 — 연표 구간이면 null.
          kin: kinProbeFor(name, app.bus, app.option), origin: (x: origin.dx, y: origin.dy), cold: cold,
        );
        kinCase = scenario is KinSection ? scenario : null;
        final sender = _Sender(origin, (pack, on) => scene.setPacks({...scene.layout.enabledPacks.where((id) => id != pack), if (on) pack}),
            () => scene.applyDensity(scene.layout.conditions.density == 2 ? 0 : 2));
        var running = true;
        void eachFrame(Duration _) {
          if (!running) return;
          final now = clock.elapsedMicroseconds / 1000;
          final batch = scenario.step(now, scene.busy.value || c.dragging);
          if (batch.isNotEmpty) inputThisFrame = true;
          sender.send(batch, now);
          SchedulerBinding.instance.scheduleFrameCallback(eachFrame);
        }

        SchedulerBinding.instance.scheduleFrameCallback(eachFrame);
        await Future<void>.delayed(Duration(seconds: o.seconds));
        running = false;
        sender.send(scenario.finish(clock.elapsedMicroseconds / 1000), clock.elapsedMicroseconds / 1000);
        // 마지막 장면 기록 묶음이 도착할 때까지 기다린다(배포 빌드는 1초마다 묶어 보낸다).
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        measuring = false;
        final kin = kinCase;
        kinCase = null;
        c.stop();
        final missedNotes = <Map<String, num>>[];
        final responses = <num>[], totals = <num>[];
        final samples = _join(timings, frames, 1000 / hz, missedNotes, responses, totals);
        // 측정 도중 밖에서 들어온 휠 입력(사람 손 · 다른 프로그램): 우리 합성 입력은 늘 같은 자리에서 ±100으로만 온다.
        final mine = 'wheel -100 @${(c.view.width * .6).toStringAsFixed(0)},${(c.view.height * .45).toStringAsFixed(0)}';
        final outside = [for (final line in inputs) if (name != '확대' || (line != mine && line != mine.replaceFirst('-100', '100'))) line];
        final trip = scene.cache.roundTrips.sublist(trips);
        cases.add(
          caseJson(
            name: name, repeat: math.max(repeat, 1), seconds: o.seconds, cold: cold,
            valid: samples.length >= o.seconds * hz * (name == '자료집' || name == '조감' ? .05 : .5) && outside.isEmpty && (kin?.valid ?? true),
            outsideInputs: outside, verdict: judge(samples, hz), missedFrames: missedNotes,
            series: {
              'build_ms': [for (final s in samples) s.buildMs], 'raster_ms': [for (final s in samples) s.rasterMs], 'total_ms': totals,
              'vsync_gap_ms': [for (final s in samples) if (s.vsyncGapMs > 0) s.vsyncGapMs], 'input_to_first_response_ms': responses,
              'paint_ms': paintMs, 'text_prepare_ms': textMs, 'shapes': shapes, 'labels': labels, 'tile_round_trip_ms': trip, 'rss_mib': rss,
              ...?kin?.series(),
            },
            counts: {
              'blank_tiles': blanks, 'cover_tiles': covers, 'new_glyphs': newGlyphs, 'tile_requests': scene.cache.requests - requests,
              'tile_last_bytes': scene.cache.lastBytes, 'tile_hit_rate': scene.cache.hitRate, 'tile_cache_bytes': scene.cache.bytes, 'level_at_end': scene.level,
              ...?kin?.counts(peakRssMib: rss.isEmpty ? null : rss.reduce(math.max)),
            },
          ),
        );
        await File('${directory.path}/진행.json').writeAsString(const JsonEncoder.withIndent('  ').convert(cases));
      }
    }
    startScene();
    final view = SchedulerBinding.instance.platformDispatcher.views.first;
    final db = File(app.dbPath ?? '');
    final report = buildReport(
      environment: {
        'build': 'release',
        'input': 'Flutter 입력 경로로 재생한 합성 입력(장면마다 한 번). 입력→첫 반응은 입력을 넣은 장면의 시작(vsync)부터 칠하기 끝까지이고, 실물 입력 장치의 지연 · 물리 화면의 표시 시각은 들어 있지 않다.',
        'machine': {'os': Platform.operatingSystemVersion, 'processors': Platform.numberOfProcessors, 'power': powerState()},
        'database': {'path': app.dbPath, 'bytes': db.existsSync() ? db.lengthSync() : null, 'meta': app.meta},
        'display_hz': hz,
        'pixel_ratio': view.devicePixelRatio,
        'viewport': [view.physicalSize.width, view.physicalSize.height],
        'first_ready_ms': app.firstReadyMs,
        'launch_to_ready_ms': app.launchToReadyMs,
        'peak_rss_bytes': peakRss,
        'hidden_layers': scene.hide.toList(),
        'text': app.option('--text') ?? 'atlas',
        'sections': o.sections, 'seconds': o.seconds, 'repeats': o.repeats,
      },
      cases: cases,
    );
    await File('${directory.path}/측정.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    return report;
  } catch (e, stack) {
    await File('${directory.path}/측정-실패.txt').writeAsString('$e\n$stack');
    return null;
  } finally {
    alive = false;
    memory.cancel();
    scene.onPainted = null;
    c.inputLog = null;
    scene.hide.removeAll(o.hide);
    SchedulerBinding.instance.removeTimingsCallback(collect);
    if (app.option('--exit') == 'yes') exit(0);
  }
}

/// 장면 기록에 '움직이던 장면인가'를 붙인다. 멎어 있던 사이의 긴 간격은 놓친 장면이 아니다.
/// [responses]에는 입력을 넣은 장면의, [totals]에는 모든 장면의 '장면 시작(vsync) → 칠하기 끝' 시간을 담는다.
List<FrameSample> _join(List<FrameTiming> timings, List<_Frame> frames, double budgetMs, List<Map<String, num>> missedNotes, List<num> responses, List<num> totals) {
  final out = <FrameSample>[];
  final first = timings.isEmpty ? 0 : timings.first.timestampInMicroseconds(FramePhase.vsyncStart);
  int? before;
  bool beforeMoving = false;
  int at = 0;
  for (final t in timings) {
    final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
    // 엔진이 적은 vsync 시각과 화면 쪽이 적은 장면 시각은 조금 다를 수 있다: 3ms 안의 가장 가까운 기록을 짝짓는다.
    while (at + 1 < frames.length && (frames[at + 1].vsyncMicros - vsync).abs() <= (frames[at].vsyncMicros - vsync).abs()) {
      at++;
    }
    final matched = frames.isNotEmpty && (frames[at].vsyncMicros - vsync).abs() <= 3000;
    final moving = matched && frames[at].moving;
    final gap = before == null || !(moving && beforeMoving) ? 0.0 : (vsync - before) / 1000;
    final sample = FrameSample(buildMs: t.buildDuration.inMicroseconds / 1000, rasterMs: t.rasterDuration.inMicroseconds / 1000, vsyncGapMs: gap);
    out.add(sample);
    final total = t.totalSpan.inMicroseconds / 1000;
    totals.add(total);
    if (matched && frames[at].hadInput) responses.add(total);
    if (sample.buildMs > budgetMs || sample.rasterMs > budgetMs || gap > budgetMs * 1.5) {
      missedNotes.add({
        'at_ms': (vsync - first) / 1000, 'build_ms': sample.buildMs, 'raster_ms': sample.rasterMs, 'gap_ms': gap,
        if (matched) ...frames[at].note,
      });
    }
    before = vsync;
    beforeMoving = moving;
  }
  return out;
}

/// 합성 입력을 Flutter의 입력 경로로 넣는다. 자리는 연표 위젯 안의 px → 화면 px.
class _Sender {
  _Sender(this.origin, this.togglePack, this.toggleBird);
  final Offset origin;
  final void Function(int pack, bool on) togglePack;
  final void Function() toggleBird;
  Offset _at = Offset.zero;

  static Duration _stamp(double ms) => Duration(microseconds: (ms * 1000).round());
  static void _dispatch(PointerEvent event) => GestureBinding.instance.handlePointerEvent(event);

  void send(List<Synthetic> batch, double now) {
    for (final input in batch) {
      switch (input) {
        case PointerDown(:final x, :final y):
          _at = origin + Offset(x, y);
          _dispatch(PointerDownEvent(pointer: 71, position: _at, buttons: kPrimaryMouseButton, kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: _stamp(now)));
        case PointerMove(:final x, :final y):
          final next = origin + Offset(x, y);
          _dispatch(PointerMoveEvent(pointer: 71, position: next, delta: next - _at, buttons: kPrimaryMouseButton, kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: _stamp(now)));
          _at = next;
        case PointerUp(:final x, :final y):
          _dispatch(PointerUpEvent(pointer: 71, position: origin + Offset(x, y), kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: _stamp(now)));
        case Wheel(:final x, :final y, :final dy):
          _dispatch(PointerScrollEvent(position: origin + Offset(x, y), scrollDelta: Offset(0, dy), kind: PointerDeviceKind.mouse, device: measureDevice));
        case PinchStart(:final x, :final y):
          _dispatch(PointerPanZoomStartEvent(pointer: 72, position: origin + Offset(x, y), device: measureDevice, timeStamp: _stamp(now)));
        case PinchUpdate(:final x, :final y, :final scale):
          _dispatch(PointerPanZoomUpdateEvent(pointer: 72, position: origin + Offset(x, y), scale: scale, device: measureDevice, timeStamp: _stamp(now)));
        case PinchEnd(:final x, :final y):
          _dispatch(PointerPanZoomEndEvent(pointer: 72, position: origin + Offset(x, y), device: measureDevice, timeStamp: _stamp(now)));
        case TogglePack(:final pack, :final on):
          togglePack(pack, on);
        case ToggleBird():
          toggleBird();
      }
    }
  }
}

final class _SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;
  @Uint8()
  external int batteryFlag;
  @Uint8()
  external int batteryLifePercent;
  @Uint8()
  external int systemStatusFlag;
  @Uint32()
  external int batteryLifeTime;
  @Uint32()
  external int batteryFullLifeTime;
}

/// 전원 상태(Windows): 전원 연결 · 배터리 · 모름. 배터리로 돌면 기기가 속도를 낮출 수 있어 측정에 적어 둔다.
String powerState() {
  if (!Platform.isWindows) return '모름';
  final status = calloc<_SystemPowerStatus>();
  try {
    final read = DynamicLibrary.open('kernel32.dll').lookupFunction<Int32 Function(Pointer<_SystemPowerStatus>), int Function(Pointer<_SystemPowerStatus>)>('GetSystemPowerStatus');
    if (read(status) == 0) return '모름';
    return switch (status.ref.acLineStatus) { 1 => '전원 연결', 0 => '배터리(${status.ref.batteryLifePercent}%)', _ => '모름' };
  } catch (_) {
    return '모름';
  } finally {
    calloc.free(status);
  }
}
