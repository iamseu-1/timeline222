import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';

import '../archive_app.dart';
import '../scene/marks.dart';
import '../ui/dlc_add.dart' show DlcJobPhase;
import '../ui/dlc_manager.dart' show DlcCardInfo;
import '../ui/filter_state.dart';
import '../ui/group_tree.dart';
import '../scene/paint/bands.dart' show BandLayer;
import '../scene/text_paragraph.dart' show SceneText, TextProbe;
import '../ui/kin/family_window.dart' show FamilyRequest, KinLevels;
import '../ui/kin/kin_head.dart' show KinDriver;
import '../ui/shell_keys.dart';
import 'runner.dart' show measureDevice;

// 실제 앱을 눌러 보며 찍는 검증 대본(--capture-script=<json 파일>). 그림만 뜨는 실행(--capture-only)에서 첫 장면이 가라앉은 뒤 차례대로 돈다.
// 부품은 조회가 실패하면 그 묶음만 조용히 비우므로(창은 그대로 선다) 단위 검사 · 계약 검사가 통과해도 실제 앱에서는 빌 수 있다 —
// 그래서 "고른 채 찍은 그림"과 "실패한 조회의 기록"을 함께 남긴다(2026-09-22의 교훈).
//
// 대본은 걸음의 목록이다:
//   {"do":"select","uid":"…","cell":"leader:2","kind":"period"} · {"do":"clear"}
//   {"do":"command","name":"year","at":분,"uid":"…","arg":"direct","trackId":1}      — 단축키 · 메뉴가 내는 명령 그대로
//   {"do":"key","key":"W"}                                                          — 그 글자의 단축키가 내는 명령(`ui/shell_keys.dart`의 표와 같다)
//   {"do":"slot","name":"doc","value":"…"}                                          — 부품끼리 주고받는 자리에 값을 싣는다
//   {"do":"filters","json":{"density":2,"show":{"spotEcho":true}}}                  — 지금 필터 값(toJson)에 덮어쓴다
//   {"do":"search","text":"은결"} · {"do":"activate"}                                — 검색 칸에 치고 · 맨 위 결과를 고른다
//   {"do":"range","from":분,"to":분} · {"do":"scroll","top":px} · {"do":"mag","value":0.5} · {"do":"wheel","dy":261,"n":1,"x":960,"y":540} — 휠 n칸(261 축소 · −284 확대)
//   {"do":"tap","x":698,"y":581} · {"do":"rightTap",…} · {"do":"hover",…}            — 화면 좌표(창의 왼쪽 위가 0,0)
//   {"do":"groupTree","uid":"…","group":"…"} · {"do":"groupTree"}              — 단체 계보 창을 연다(그 단체를 고른 채) · uid 없이 부르면 닫는다(D5)
//   {"do":"lens","id":"faction"}                                                 — 렌즈(주제 보기)를 켠다 · 빈 글이면 끈다(D5)
//   {"do":"family","kin":"kin:h-…","house":"house:h-…","focus":""} · {"do":"family"} — 세계표 떠 있는 창을 연다 · 닫는다
//   {"do":"kinLevel","level":1}                                                  — 떠 있는 세계표의 보기 단계(0 보통 · 1 점 — 건의 8의 4-가)
//   {"do":"kin","all":true} · {"do":"kin","all":false} · {"do":"kin","toggle":"<안정 열쇠>"} — 떠 있는 계보 창(승계표 · 세계표)의 모두 펼치기 · 모두 접기 ·
//                                                                                   그 마디 접고 펴기(바닥 단추 · 누름과 같은 일 — 뼈대를 받아 풀 때까지 기다림)
//   {"do":"sheet","rise":5,"shift":5,"tab":5,"gap":1.5}                          — 상국 뒤 장의 어긋남 · 탭 올림 · 틈(건의 8의 2번 C — 감독 확인 그림)
//   {"do":"tapBoardDock"}                                                       — 집합 보기 독의 실제 자리 중심을 포인터로 누름
//   {"do":"board","key":"view:v-three-lands"}                                    — UI 스위치와 같은 공개 제어부(빈 key면 끔)
//   {"do":"dlc","add":["<.htpack>"]} · {"do":"dlc","remove":"<글자 id>"} · {"do":"dlc","off":"…"} · {"do":"dlc","on":"…"} — DLC 일을 기다리지 않고 건다
//   {"do":"until","what":"writing|flowing|idle","ms":120000}                       — 저장소를 고쳐 쓰는 중 · 줄이 흐르는 중 · DLC 일이 끝남을 장면마다 보며 기다린다
//   {"do":"pan","ms":5000,"px":3}                                                 — 그동안 장면마다 보기를 옆으로 옮기며 장면 사이 간격(최대 · p95)을 적는다(멈춤 재기)
//   {"do":"wait","ms":800}
//   {"do":"shot","name":"지도자-칸"}                                                 — <폴더>/<이름>.png + 그때의 상태
//   {"do":"burst","name":"조감","step":{"do":"key","key":"V"},"frames":[0,1,2,4,8,16]} — 안의 걸음을 내고 그 뒤 n번째 장면들을 연달아 찍는다
//        (<폴더>/<이름>-<n>.png · 0 = 걸음 뒤 첫 장면). 장면마다 그린 이름의 판 번호 · 옅어지는 그림자 수도 적는다(잔상 재현 — 건의 8의 8번).
// 끝나면 <폴더>/검증-기록.json에 걸음마다의 상태와 실패한 조회를 적는다.

/// 글자 키 → 명령. `ui/shell_keys.dart`의 `_table`과 같아야 한다(그쪽은 사사로워 여기서 다시 적는다).
/// 실제 키 입력을 만들어 넣을 길이 앱 안에는 없어, 그 키가 내는 **명령**을 대신 낸다.
const _keyCommands = <String, String>{
  'F': Cmd.filter, 'Y': Cmd.year, 'L': Cmd.legend, 'T': Cmd.table, 'P': Cmd.image,
  'R': Cmd.measure, 'V': Cmd.bird, 'A': Cmd.foldAll, 'D': Cmd.dlc, 'Z': Cmd.zen,
  'W': Cmd.wiki, 'M': Cmd.map, '/': Cmd.search,
};

Future<void> runVerifyScript(ArchiveAppState app, String scriptPath, Directory folder) async {
  final bus = app.bus;
  if (bus == null) return;
  final steps = (jsonDecode(await File(scriptPath).readAsString()) as List).cast<Map>();
  final log = <Map<String, dynamic>>[];
  var pointer = 80;

  Map<String, dynamic> state() {
    final picked = bus.selection.value;
    final view = app.controller.view, layout = app.scene!.layout.viewState;
    Object? plain(Object? v) => v == null || v is num || v is bool || v is String ? v : (v is Map || v is List ? jsonDecode(jsonEncode(v, toEncodable: (o) => '$o')) : '$v');
    return {
      'selection': picked == null ? null : {'uid': picked.uid, 'cell': picked.cell, 'kind': picked.kind},
      'detailOpen': app.glue?.detail.open ?? false,
      // 열린 플래그 창의 띠(리메이크 2부 — 꼬리표 윗변의 플래그를 누른 걸음이 창을 열었는지).
      'flag': app.openFlagBand,
      'yearOpen': app.glue?.yearOpen ?? false,
      'slots': {for (final name in const ['doc', 'yearPanel', 'scopes', 'echo', 'marker', 'metro', 'motion', 'legend', 'foldAll']) name: plain(bus.slot(name).value)},
      // 날짜 칸의 표시 넷 · 관점 · 지도자 표기 — 필터를 바꾼 걸음이 실제로 장면에 닿았는지 본다.
      'marks': () {
        final m = SceneMarks.of(app.scene!);
        return {
          'axis': [m.showGanji, m.showEras, m.showCapitals, m.showEpochs],
          'lens': m.lens,
          'houses': m.showHouses,
          'leaderLabel': m.leaderLabel,
          'leaderOrdinal': m.leaderOrdinal,
          'alt': m.showAlt,
          // 단체 · 렌즈(D5): 올린 연합 · 계보 창에서 고른 단체 · 켠 렌즈의 색
          'hotCoal': m.hotCoal,
          'groupFocus': m.groupFocus,
          'lensColor': m.lensColor,
        };
      }(),
      'themeLens': app.scene!.layout.themeLens,
      'board': {'activeKey': app.boardViews?.activeKey ?? '', 'listOpen': app.boardViews?.listOpen ?? false},
      'groupTree': bus.slot(groupTreeSlot).value != null,
      'view': [view.lo, view.hi, view.top, view.mag],
      'foldedTracks': layout.foldedTracks.toList()..sort(),
      'expandedHosts': layout.expandedHosts.toList()..sort(),
      'openScopes': layout.openScopes.toList()..sort(),
      // 선반(과제 7 걸음 4): 선반에 둔 그릇(보기 기억)과 지금 켠 변형의 열쇠(선반이면 `shelf:<그릇 uid>`가 `scope:<uid>` 대신) — 찍기 틀이 선반을 정말 켰는지 본다.
      'shelvedScopes': layout.shelvedScopes.toList()..sort(),
      'variantKeys': app.scene!.layout.variantKeys,
      'askFailures': app.askFailures.length,
    };
  }

  void send(PointerEvent event) => GestureBinding.instance.handlePointerEvent(event);
  Offset at(Map step) => Offset((step['x'] as num).toDouble(), (step['y'] as num).toDouble());
  Duration now() => Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
  Future<void> tapAt(Offset position, {bool secondary = false}) async {
    final id = pointer++, buttons = secondary ? kSecondaryMouseButton : kPrimaryMouseButton;
    send(PointerHoverEvent(position: position, kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: now()));
    send(PointerDownEvent(pointer: id, position: position, buttons: buttons, kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: now()));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    send(PointerUpEvent(pointer: id, position: position, kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: now()));
  }


  Future<void> perform(String what, Map step) async {
    switch (what) {
      case 'select':
        bus.select('${step['uid']}', kind: '${step['kind'] ?? ''}', cell: step['cell'] as String?);
      case 'clear':
        bus.clearSelection();
      case 'command':
        runCommand(bus, '${step['name']}', uid: step['uid'] as String?, trackId: (step['trackId'] as num?)?.toInt(), at: (step['at'] as num?)?.toDouble(), arg: step['arg'] as String?);
      case 'key':
        final letter = '${step['key']}'.toUpperCase();
        final name = _keyCommands[letter];
        if (letter == 'Z') {
          // 집중 모드는 명령이 아니라 상태다(진짜 키 처리도 `setZen`을 부른다 — ui/shell_keys.dart).
          setZen(bus, !zenOf(bus));
        } else if (name == null) {
          log.add({'step': what, 'error': '단축키가 없는 글자: ${step['key']}'});
        } else {
          runCommand(bus, name);
        }
      case 'slot':
        bus.slot('${step['name']}').value = step['value'];
      case 'filters':
        final current = bus.slot('filters').value;
        // 값이 아직 없으면 앱의 필터 시트처럼 지금 보기 조건에서 시작한다([FilterState.orSeed] — 0.1.1 · 앞 걸음의 V · ↕ 조감을 풀지 않게).
        final base = FilterState.orSeed(current, bus.conditions.value).toJson();
        final over = Map<String, dynamic>.from(step['json'] as Map);
        final merged = {...base, ...over, if (over['show'] is Map) 'show': {...(base['show'] as Map? ?? const {}), ...(over['show'] as Map)}};
        final next = FilterState.fromJson(merged);
        bus.slot('filters').value = next;
        bus.conditions.value = next.toConditions();
      case 'search':
        app.query.text = '${step['text']}';
        await app.search?.setQuery('${step['text']}');
      case 'activate':
        app.search?.activate();
      case 'range':
        app.controller.showRange((step['from'] as num).toDouble(), (step['to'] as num).toDouble());
      case 'scroll':
        app.controller.scrollTo((step['top'] as num).toDouble());
      case 'mag':
        app.controller.magnifyTo((step['value'] as num).toDouble(), Offset(app.controller.view.width / 2, app.controller.view.height / 2));
      case 'wheel':
        // 휠 한 칸(축소 단추와 같은 길 — dy 261 = 축소 · −284 = 확대) · n이면 그만큼 잇달아(빠르게 여러 칸 굴림). 자리를 주지 않으면 화면 가운데.
        final at = Offset((step['x'] as num? ?? app.controller.view.width / 2).toDouble(), (step['y'] as num? ?? app.controller.view.height / 2).toDouble());
        for (var i = 0; i < ((step['n'] as num?) ?? 1).toInt(); i++) {
          app.controller.wheel(at, (step['dy'] as num? ?? 261).toDouble());
        }
      case 'tap' || 'rightTap':
        await tapAt(at(step), secondary: what == 'rightTap');
      case 'tapBoardDock':
        final box = app.boardViews?.dockKey.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) throw StateError('집합 보기 독이 화면에 없습니다');
        await tapAt(box.localToGlobal(box.size.center(Offset.zero)));
      case 'board':
        final views = app.boardViews;
        if (views == null) throw StateError('집합 보기 제어부가 없습니다');
        final key = step['key']?.toString() ?? '';
        if (key.isEmpty) {
          views.turnOff();
        } else {
          views.turnOn(key);
        }
      case 'hover':
        send(PointerHoverEvent(position: at(step), kind: PointerDeviceKind.mouse, device: measureDevice, timeStamp: now()));
      case 'groupTree':
        if (step['uid'] == null) {
          closeGroupTree(bus);
        } else {
          openGroupTree(bus, '${step['uid']}', group: step['group'] as String?);
        }
      case 'lens':
        app.lens?.set('${step['id'] ?? ''}');
      case 'family':
        final kin = step['kin'] as String?;
        bus.slot('family').value = kin == null
            ? null
            : FamilyRequest(kin: kin, house: '${step['house'] ?? ''}', focus: '${step['focus'] ?? ''}');
      case 'sheet':
        BandLayer.sheetRise = ((step['rise'] ?? BandLayer.sheetRise) as num).toDouble();
        BandLayer.sheetShift = ((step['shift'] ?? BandLayer.sheetShift) as num).toDouble();
        BandLayer.tabRise = ((step['tab'] ?? BandLayer.tabRise) as num).toDouble();
        BandLayer.sheetGap = ((step['gap'] ?? BandLayer.sheetGap) as num).toDouble();
        app.scene?.requestFrame();
      case 'kinLevel':
        final driver = bus.slot('kinDriver').value;
        if (driver is! KinLevels) throw StateError('보기 단계를 바꿀 계보 창이 없습니다');
        driver.setLevel((step['level'] as num).toInt());
      case 'kin':
        final driver = bus.slot('kinDriver').value;
        if (driver is! KinDriver) throw StateError('떠 있는 계보 창이 없습니다');
        await driver.loaded;
        if (step['all'] == true) driver.expandAll();
        if (step['all'] == false) driver.collapseAll();
        if (step['toggle'] is String && !driver.toggle(step['toggle'] as String)) throw StateError('접고 펼 마디가 없습니다: ${step['toggle']}');
      case 'dlc':
        // DLC 넣기 · 빼기 · 끄기 · 켜기를 **기다리지 않고** 건다(창의 단추와 같은 길) — 다음 걸음이 그동안의 화면을 찍고 끈다(계획 P4 과제 8).
        final scene = app.scene!;
        DlcCardInfo? card(String key) => DlcCardInfo.of(scene.layout, hidden: app.dlcJob.hidden).where((c) => c.key == key).firstOrNull;
        if (step['add'] is List) {
          unawaited(app.addDlcFiles([for (final f in step['add'] as List) '$f']));
        } else if (step['remove'] != null) {
          final c = card('${step['remove']}') ?? (throw StateError('뺄 DLC가 없습니다: ${step['remove']}'));
          unawaited(app.removeDlc(c));
        } else if (step['off'] != null || step['on'] != null) {
          final c = card('${step['on'] ?? step['off']}') ?? (throw StateError('켜고 끌 DLC가 없습니다'));
          unawaited(app.toggleDlcs([c], step['on'] != null));
        }
      case 'until':
        // 장면마다 보며 기다린다: writing(저장소를 고쳐 쓰는 중) · flowing(뼈대를 바꿔 줄이 흐르는 중) · idle(DLC 일이 끝나고 흐름도 멎음).
        final scene = app.scene!;
        bool met() => switch ('${step['what']}') {
          'writing' => scene.storeWriting,
          'flowing' => scene.layout.flowing,
          _ => app.dlcJob.phase != DlcJobPhase.running && !scene.layout.flowing,
        };
        final limit = Stopwatch()..start();
        final ms = ((step['ms'] ?? 120000) as num).toInt();
        while (!met()) {
          if (limit.elapsedMilliseconds > ms) throw StateError('${step['what']}를 ${ms}ms 안에 보지 못했습니다');
          SchedulerBinding.instance.scheduleFrame();
          await SchedulerBinding.instance.endOfFrame;
        }
        log.add({'until': step['what'], 'ms': limit.elapsedMilliseconds});
      case 'pan':
        // 끌기 흉내: 정한 시간 동안 장면마다 보기를 옆으로 조금씩 옮기고(2초마다 방향을 바꿈) 장면 사이 간격을 적는다 — DLC를 넣는 동안
        // 화면이 멈추지 않는가(계획 P4 과제 8). 그동안 저장소를 고쳐 쓰는 중이었던 장면 수도 적는다.
        final ms = (step['ms'] as num).toInt(), px = ((step['px'] ?? 3) as num).toDouble();
        final gaps = <double>[];
        final clock = Stopwatch()..start();
        var last = 0.0, writing = 0;
        while (clock.elapsedMilliseconds < ms) {
          final v = app.controller.view;
          final shift = px / v.ppm * ((clock.elapsedMilliseconds ~/ 2000).isEven ? 1 : -1);
          app.controller.showRange(v.lo + shift, v.hi + shift);
          await SchedulerBinding.instance.endOfFrame;
          final t = clock.elapsedMicroseconds / 1000;
          gaps.add(t - last);
          last = t;
          if (app.scene!.storeWriting) writing++;
        }
        final sorted = [...gaps]..sort();
        log.add({
          'pan': ms, 'frames': gaps.length, 'writing_frames': writing,
          'max_gap_ms': sorted.isEmpty ? null : sorted.last,
          'p95_gap_ms': sorted.isEmpty ? null : sorted[(sorted.length * .95).floor().clamp(0, sorted.length - 1)],
        });
      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: (step['ms'] as num).toInt()));
      case 'shot':
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await app.screenshot('${folder.path}/${step['name']}.png');
        log.add({'shot': step['name'], ...state()});
      case 'burst':
        final inner = step['step'] as Map;
        final frames = [for (final f in (step['frames'] as List? ?? const [0, 1, 2, 4, 8, 16])) (f as num).toInt()]..sort();
        log.add({'burst': step['name'], 'frames': await _burst(app, folder, '${step['name']}', frames, () => perform('${inner['do']}', inner))});
      default:
        log.add({'step': what, 'error': '모르는 걸음'});
    }
  }

  for (final step in steps) {
    final what = '${step['do']}';
    try {
      await perform(what, step);
    } catch (e) {
      log.add({'step': what, 'error': '$e'});
    }
    // 걸음마다 조금 쉰다 — 조회의 답과 200~360ms의 흐름이 가라앉게. DLC 일을 거는 걸음은 쉬지 않는다(다음 걸음이 그동안을 재고 찍는다).
    if (what != 'wait' && what != 'shot' && what != 'dlc') await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  await File('${folder.path}/검증-기록.json').writeAsString(const JsonEncoder.withIndent(' ').convert({'steps': log, 'ask_failures': app.askFailures}));
}

/// 안의 걸음을 내고, 그 뒤 [frames]번째 장면마다 화면을 곧바로 떠 둔다(뜨는 동안 다음 장면이 밀리지 않게 그림만 쥐고, 파일은 끝나고 쓴다).
/// 멎은 화면이면 장면이 오지 않으므로 장면을 청해 센다 — n번째 = 걸음 뒤 n번째로 그려진 화면.
Future<List<Map<String, dynamic>>> _burst(ArchiveAppState app, Directory folder, String name, List<int> frames, Future<void> Function() act) async {
  final scene = app.scene!;
  final boundary = app.captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await SchedulerBinding.instance.endOfFrame;
  final asked = scene.labelVersion;
  final shots = <int, ui.Image>{}, notes = <Map<String, dynamic>>[];
  final boxes = <int, String>{};
  final done = Completer<void>();
  var index = -1;
  void onFrame(Duration _) {
    index++;
    if (frames.contains(index)) {
      shots[index] = boundary.toImageSync(pixelRatio: 1);
      final probe = SceneText.probe; // --capture-text면 그 장면의 글 상자도(움직이는 동안의 겹침)
      if (probe != null) boxes[index] = textBoxesJson(app, probe);
      final s = scene.stats;
      // 이름의 판이 걸음 앞에 셈한 것(번호 ≤ asked)인데 이름을 그렸다면 옛 판의 글자가 남은 것이다.
      notes.add({
        'frame': index, 'nameBatch': s.nameBatch, 'namesDrawn': s.namesDrawn, 'ghostNames': s.ghostNames,
        'staleNames': s.nameBatch >= 0 && s.nameBatch <= asked ? s.namesDrawn : 0, 'flowing': scene.layout.flowing,
        // ClearType의 멈춤과 그 까닭(과제 6 고침 — 옮긴 직후 장면마다 회색인지 · 왜 회색인지)
        'clearTypeStill': scene.stillForClearType, 'fading': scene.fading, 'waitingTiles': scene.waitingTiles, 'labelBusy': scene.labelWorker.busy,
        'settled': scene.settled, 'busy': scene.busy.value, 'calmMs': scene.debugCalmMs, 'namesMoving': scene.debugNamesMoving,
      });
    }
    if (index >= frames.last) {
      done.complete();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(onFrame);
    SchedulerBinding.instance.scheduleFrame();
  }

  await act();
  SchedulerBinding.instance.addPostFrameCallback(onFrame);
  SchedulerBinding.instance.scheduleFrame();
  await done.future;
  for (final entry in shots.entries) {
    final bytes = await entry.value.toByteData(format: ui.ImageByteFormat.png);
    await File('${folder.path}/$name-${entry.key}.png').writeAsBytes(bytes!.buffer.asUint8List());
    entry.value.dispose();
  }
  for (final entry in boxes.entries) {
    await File('${folder.path}/$name-${entry.key}.text.json').writeAsString(entry.value);
  }
  return notes;
}

/// 글 상자 기록([TextProbe])의 마지막 장면을 JSON으로 — 가장 많이 그린 뒷단(연표 화면)의 상자와, 찍는 경계 안에서 연표의 원점.
String textBoxesJson(ArchiveAppState app, TextProbe probe) {
  final owner = probe.frames.entries.fold<MapEntry<SceneText, List<List<Object>>>?>(null, (a, b) => a == null || b.value.length > a.value.length ? b : a);
  final boxes = owner?.value ?? const <List<Object>>[];
  final marks = owner == null ? const <List<Object>>[] : probe.marks[owner.key] ?? const <List<Object>>[];
  final timeline = (app.timelineKey.currentContext!.findRenderObject() as RenderBox).localToGlobal(Offset.zero);
  final frame = (app.captureKey.currentContext!.findRenderObject() as RenderBox).localToGlobal(Offset.zero);
  return jsonEncode({'timeline': [timeline.dx - frame.dx, timeline.dy - frame.dy], 'boxes': boxes, 'marks': marks});
}
