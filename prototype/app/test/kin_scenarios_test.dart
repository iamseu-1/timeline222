import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/measure/frame_stats.dart';
import 'package:archive_prototype/measure/report.dart';
import 'package:archive_prototype/measure/scenarios.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart' show slotFamily, slotKinDriver;
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/detail_cell.dart';
import 'package:archive_prototype/ui/detail_item.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/kin/family_window.dart';
import 'package:archive_prototype/ui/kin/kin_head.dart';
import 'package:archive_prototype/ui/kin/kin_layout.dart';
import 'package:archive_prototype/ui/kin/kin_rows.dart';
import 'package:archive_prototype/ui/kin/succession_view.dart' show registerKinDetail;
import 'package:archive_prototype/ui/kin/kin_record.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 계보 창 측정 구간(승계표 · 세계표 — 확정 설계 6-5 ③ · D1-N4)의 검사.
// 창(D1-N2)과 뼈대(D1-N1)는 같은 때에 따로 지어지므로 측정 손잡이 KinProbe의 대역(_FakeProbe)과 N2 손잡이 꼴의 대역 창으로 구간을 돌리고,
// 들어온 진짜 승계표 창(SuccessionView)과 세계표 창(FamilyWindow — 결합 때 더함)에도 붙여 돌린다.
// 시간 판정은 PC 몫 — 여기서는 구간이 오류 없이 돌고, 차례가 결정적이고, judge가 판정을 내고, 보고서 꼴이 맞는지 본다.

/// 계획만 돌린 기록. 창은 열기 뒤 [openMs]에 열리고, 일을 시킬 때마다 [busyMs] 동안 움직인다고 친다(끌기는 놓은 뒤부터).
List<String> playPlan(KinPlan plan, double seconds, {double hz = 144, double openMs = 50, double busyMs = 300}) {
  final log = <String>[];
  double readyAt = double.infinity, busyUntil = -1;
  bool down = false;
  for (double now = 0; now < seconds * 1000; now += 1000 / hz) {
    final actions = plan.step(now, (ready: now >= readyAt, busy: down || now < busyUntil));
    for (final a in actions) {
      if (a is KinActOpen) readyAt = now + openMs;
      if (a is KinActPointer && a.press == KinActPress.down) down = true;
      if (a is KinActPointer && a.press == KinActPress.up) down = false;
      if (a is! KinActPointer || a.press == KinActPress.up) busyUntil = now + busyMs;
    }
    log.addAll(actions.map((a) => '${now.toStringAsFixed(1)} $a'));
  }
  log.addAll(plan.finish(seconds * 1000).map((a) => 'end $a'));
  return log;
}

double timeOf(String line) => double.parse(line.split(' ').first);
String whatOf(String line) => line.substring(line.indexOf(' ') + 1);

/// 측정 손잡이의 대역: 부른 일을 적고, 열기는 [Completer]로 붙잡아 두었다가 [land]로 끝낸다.
class _FakeProbe implements KinProbe {
  final cost = const KinProbeCost(target: 'kin:h-on', bytes: 2400000, fetchMs: 4, decodeMs: 31, layoutMs: .8, people: 50000);
  final calls = <String>[];
  Completer<KinProbeCost>? opening;
  bool moving = false;
  int notes = 0;

  void land() => opening?.complete(cost);
  void fail(Object error) => opening?.completeError(error);

  @override
  void forget() => calls.add('forget');
  @override
  Future<KinProbeCost> open() {
    calls.add('open');
    return (opening = Completer<KinProbeCost>()).future;
  }

  @override
  KinProbeArea get area => (left: 1500, top: 120, width: 380, height: 800);
  @override
  bool get busy => moving;
  @override
  void toggle(int slot) => calls.add('toggle $slot');
  @override
  void expandAll() => calls.add('expand all');
  @override
  void collapseAll() => calls.add('collapse all');
  @override
  void scrollTo(double fraction) => calls.add('scroll ${fraction.toStringAsFixed(3)}');
  @override
  void bring(int slot) => calls.add('bring $slot');
  @override
  void overview(double fx, double fy) => calls.add('overview $fx,$fy');
  @override
  KinProbeNote takeNote() {
    notes++;
    // 장면마다 지은 수 40 · 선 120, 접을 때마다 자리 셈 하나 · 고르기 하나(대역 값).
    final folded = calls.isNotEmpty && (calls.last.startsWith('toggle') || calls.last.endsWith(' all'));
    return KinProbeNote(built: 40, lines: 120, layoutMs: folded ? const [1.2] : const [], pickMs: const [.03]);
  }

  @override
  void close() => calls.add('close');
}

void main() {
  test('계보 구간은 둘이고, 기본 측정의 여섯 구간은 그대로다', () {
    expect(kinSectionNames, ['승계표', '세계표']);
    expect(kinViews, {'승계표': 'succession', '세계표': 'family'});
    expect(sectionNames, ['끌기', '확대', '돋보기', '밀집', '세로', '자료집'], reason: '앱 안 빠른 측정 · 옛 저장소 측정은 바뀌지 않는다');
    for (final name in kinSectionNames) {
      final s = scenarioFor(name, width: 1538, height: 846);
      expect(s, isA<KinSection>());
      expect(s.name, name);
    }
    expect(scenarioFor('끌기', width: 1538, height: 846), isNot(isA<KinSection>()));
  });

  test('손잡이가 없으면 입력 없이 오류 없이 끝나고, 보고서에 그렇게 적는다', () {
    final s = scenarioFor('승계표', width: 1538, height: 846) as KinSection;
    for (double now = 0; now < 3000; now += 1000 / 60) {
      expect(s.step(now, false), isEmpty);
      expect(s.acted, isFalse);
    }
    expect(s.finish(3000), isEmpty);
    expect(s.valid, isFalse);
    final counts = s.counts();
    expect(counts['kin_probe'], isFalse);
    expect(counts['kin_ready'], isFalse);
    expect(jsonDecode(jsonEncode(counts)), isA<Map<String, dynamic>>());
  });

  test('같은 시각 · 같은 창 상태를 넣으면 늘 같은 일이 나온다(결정적)', () {
    for (final name in kinSectionNames) {
      final a = playPlan(kinPlanFor(name), 30), b = playPlan(kinPlanFor(name), 30);
      expect(a, b, reason: name);
      expect(a.length, greaterThan(100), reason: name);
      expect(playPlan(kinPlanFor(name), 30, hz: 60), playPlan(kinPlanFor(name), 30, hz: 60), reason: '$name 60Hz');
    }
  });

  test('승계표: 열기 → (열린 뒤) 모두 펼치기 → 휠 12칸씩 셋 → 목록 끌기 둘 → 막대 끌기로 끝까지 → 휠 거슬러 셋 → 처음까지 → 접기 · 펼치기 20회 → 모두 접기', () {
    final log = playPlan(kinPlanFor('승계표'), 30);
    final what = log.map(whatOf).toList();
    expect(what.first, 'open');
    expect(timeOf(log.first), 0);
    final expand = log.firstWhere((l) => whatOf(l) == 'expand all');
    expect(timeOf(expand), greaterThanOrEqualTo(50 + 300), reason: '열린 뒤(50ms) 0.3초 쉬고서');
    final firstRound = what.sublist(1, what.indexOf('collapse all') + 1);
    final wheels = firstRound.where((w) => w.startsWith('wheel')).toList();
    expect(wheels.length, 72);
    expect(wheels.take(36).every((w) => w == 'wheel 100'), isTrue);
    expect(wheels.skip(36).every((w) => w == 'wheel -100'), isTrue);
    expect(firstRound.where((w) => w.startsWith('down')).length, 2, reason: '목록 끌기 위 · 아래');
    expect(firstRound.where((w) => w.startsWith('up')).length, 2);
    final scrolls = [for (final w in firstRound) if (w.startsWith('scroll')) double.parse(w.split(' ')[1])];
    final turn = scrolls.indexOf(1);
    expect(turn, greaterThan(0));
    expect(scrolls.first, 0);
    expect(scrolls.last, 0);
    for (int i = 1; i < scrolls.length; i++) {
      expect(i <= turn ? scrolls[i] >= scrolls[i - 1] : scrolls[i] <= scrolls[i - 1], isTrue, reason: '막대 끌기는 한쪽으로만 — $i');
    }
    // 휠 묶음 안은 80ms 간격.
    final wheelTimes = [for (final l in log) if (whatOf(l).startsWith('wheel')) timeOf(l)];
    for (int i = 1; i < 12; i++) {
      expect(wheelTimes[i] - wheelTimes[i - 1], closeTo(80, 1000 / 144 + .01));
    }
    final toggles = [for (final l in log) if (whatOf(l).startsWith('toggle')) l];
    expect(toggles.take(20).map(whatOf), [for (int i = 0; i < 20; i++) 'toggle ${i ~/ 2}'], reason: '같은 줄을 접고 다시 편다');
    for (int i = 1; i < 20; i++) {
      expect(timeOf(toggles[i]) - timeOf(toggles[i - 1]), closeTo(400, 1000 / 144 + .01));
    }
    final collapse = log.firstWhere((l) => whatOf(l) == 'collapse all');
    expect(timeOf(collapse), lessThan(28000), reason: '한 바퀴가 30초 안에 끝난다');
    expect(what.where((w) => w == 'open').length, 1, reason: '열기는 처음 한 번');
    expect(what.where((w) => w == 'expand all').length, 2, reason: '30초 안에 둘째 바퀴가 시작된다');
  });

  test('세계표: 네 방향 끌기 → 모두 펼치기 → 대각선 넷 → 접기 · 펼치기 20회 → 찾아 데려오기 셋 → 전체도 넷 → 모두 접기', () {
    final log = playPlan(kinPlanFor('세계표'), 30);
    final what = log.map(whatOf).toList();
    expect(what.first, 'open');
    final firstRound = what.sublist(1, what.indexOf('collapse all') + 1);
    final downs = [for (int i = 0; i < firstRound.length; i++) if (firstRound[i].startsWith('down')) i];
    expect(downs.length, 8);
    expect(firstRound.indexOf('expand all'), allOf(greaterThan(downs[3]), lessThan(downs[4])), reason: '넷째 끌기 뒤 · 다섯째 앞');
    // 끌기마다 첫 옮김은 누른 장면에서 5px 문턱을 넘고, 끝 옮김은 6 + 2×200px 너머(놓을 때 달리던 속도).
    final ends = <List<double>>[];
    for (final at in downs) {
      final firstMove = firstRound[at + 1].split(' ')[1].split(',').map(double.parse).toList();
      expect(firstMove[0] * firstMove[0] + firstMove[1] * firstMove[1], greaterThan(25));
      final up = firstRound.indexWhere((w) => w.startsWith('up'), at);
      ends.add(firstRound[up].split(' ')[1].split(',').map(double.parse).toList());
    }
    String way(List<double> v) => '${v[0].sign.toInt()},${v[1].abs() < 1 ? 0 : v[1].sign.toInt()}';
    expect(ends.map((v) => way([v[0].abs() < 1 ? 0 : v[0], v[1]])), ['1,0', '-1,0', '0,1', '0,-1', '1,1', '-1,-1', '-1,1', '1,-1']);
    for (final v in ends) {
      final d = v[0] * v[0] + v[1] * v[1];
      expect(d, greaterThan(406 * 406));
    }
    expect([for (final w in firstRound) if (w.startsWith('toggle')) w], [for (int i = 0; i < 20; i++) 'toggle ${i ~/ 2}']);
    expect([for (final w in firstRound) if (w.startsWith('bring')) w], ['bring 0', 'bring 1', 'bring 2']);
    expect([for (final w in firstRound) if (w.startsWith('overview')) w], ['overview 0.10,0.50', 'overview 0.90,0.50', 'overview 0.50,0.20', 'overview 0.50,0.80']);
    final collapse = log.firstWhere((l) => whatOf(l) == 'collapse all');
    expect(timeOf(collapse), lessThan(29000), reason: '한 바퀴가 30초 안에 끝난다');
    // 둘째 바퀴의 찾기는 다른 사람(3 · 4 · 5)을 고른다.
    final second = playPlan(kinPlanFor('세계표'), 70).map(whatOf).where((w) => w.startsWith('bring')).toList();
    expect(second.take(6), ['bring 0', 'bring 1', 'bring 2', 'bring 3', 'bring 4', 'bring 5']);
  });

  test('쉼은 창이 열리고 움직임이 멎을 때까지 기다린다', () {
    final plan = kinPlanFor('세계표');
    // 열리지 않으면 열기 뒤로 아무 일도 없다.
    final out = <String>[];
    for (double now = 0; now < 5000; now += 1000 / 60) {
      out.addAll(plan.step(now, (ready: false, busy: false)).map((a) => '$a'));
    }
    expect(out, ['open']);
    // 열렸어도 계속 움직이면 쉼이 끝나지 않는다.
    final busy = kinPlanFor('승계표');
    final seen = <String>[];
    for (double now = 0; now < 5000; now += 1000 / 60) {
      seen.addAll(busy.step(now, (ready: true, busy: now > 100)).map((a) => '$a'));
    }
    expect(seen, ['open'], reason: '0.3초 쉼이 끝나기 전에 움직임이 시작되어 기다린다');
  });

  test('끄는 중에 구간이 끝나면 마지막 자리에서 뗀다', () {
    final plan = kinPlanFor('세계표');
    final log = <KinAct>[];
    double now = 0;
    for (; now < 2000; now += 1000 / 60) {
      log.addAll(plan.step(now, (ready: now > 10, busy: false)));
      if (log.whereType<KinActPointer>().any((p) => p.press == KinActPress.down) && now > 900) break;
    }
    final last = log.whereType<KinActPointer>().last;
    expect(last.press, KinActPress.move);
    final end = plan.finish(now);
    expect(end.single, isA<KinActPointer>());
    expect((end.single as KinActPointer).press, KinActPress.up);
    expect((end.single as KinActPointer).dx, last.dx);
    expect(plan.finish(now), isEmpty, reason: '한 번만 뗀다');
  });

  test('찾아 데려오기의 사람 번호: 범위 안 · 결정적 · 고루 흩어짐', () {
    expect(kinBringIndex(0, 0), 0);
    expect(kinBringIndex(5, 1), 0);
    final picked = {for (int slot = 0; slot < 100; slot++) kinBringIndex(slot, 50000)};
    expect(picked.length, 100);
    expect(picked.every((i) => i >= 0 && i < 50000), isTrue);
    expect(kinBringIndex(7, 1000), kinBringIndex(7, 1000));
    final buckets = {for (final i in picked) i * 10 ~/ 50000};
    expect(buckets.length, 10, reason: '앞 차례 전체(뼈대의 앞 · 뒤 · 깊은 곳)에 고루');
  });

  test('예산 대조: 한도와 값 · 모르는 값은 판정하지 않음 · 세계표만 선 수', () {
    final none = kinBudget(view: 'succession');
    expect(none['pass'], isTrue);
    expect((none['fetch_ms'] as Map)['pass'], isNull);
    expect(none.containsKey('lines_max'), isFalse);
    expect((none['built_max'] as Map)['limit'], 50);
    final family = kinBudget(
      view: 'family',
      cost: const KinProbeCost(fetchMs: 12, decodeMs: 40),
      layoutMs: [for (int i = 0; i < 40; i++) 1.0],
      pickMs: const [.02, .03],
      builtMax: 180,
      linesMax: 290,
      peakRssMib: 380,
    );
    expect((family['built_max'] as Map)['limit'], 200);
    expect((family['lines_max'] as Map)['pass'], isTrue);
    expect((family['fetch_ms'] as Map)['pass'], isFalse, reason: '받기 10ms 넘음');
    expect((family['decode_ms'] as Map)['pass'], isTrue);
    expect((family['layout_p99_ms'] as Map)['value'], 1.0);
    expect(family['pass'], isFalse);
    expect((kinBudget(view: 'family', blank: 1)['blank'] as Map)['pass'], isFalse, reason: '빈 자리는 0이어야 한다');
    expect((kinBudget(view: 'succession', peakRssMib: 401)['rss_peak_mib'] as Map)['pass'], isFalse);
  });

  test('구간이 손잡이에 일을 시키고 · 창 안 입력을 연표 위젯 안의 자리로 바꾸고 · 찬 상태면 먼저 비운다', () async {
    final probe = _FakeProbe();
    final s = scenarioFor('승계표', width: 1538, height: 846, kin: probe, origin: (x: 20, y: 60), cold: true) as KinSection;
    expect(s.step(0, false), isEmpty);
    expect(probe.calls, ['forget', 'open']);
    expect(s.acted, isTrue, reason: '열기를 누른 장면');
    expect(s.ready, isFalse);
    probe.land();
    await Future<void>.delayed(Duration.zero);
    expect(s.ready, isTrue);
    final inputs = <Synthetic>[];
    for (double now = 1000 / 60; now < 4000; now += 1000 / 60) {
      inputs.addAll(s.step(now, true));
    }
    expect(probe.calls.sublist(2, 3), ['expand all'], reason: '연표가 바빠도(sceneBusy) 창의 차례는 그대로');
    final wheel = inputs.whereType<Wheel>().first;
    // 창 몸통 (1500, 120, 380 × 800)의 가운데 − 연표 위젯 자리 (20, 60).
    expect(wheel.x, 1500 + 190 - 20);
    expect(wheel.y, 120 + 400 - 60);
    expect(wheel.dy, 100);
    expect(probe.calls.where((c) => c == 'forget').length, 1);
  });

  test('구간 하나를 끝까지 돌리면 judge가 판정을 내고, 보고서 꼴에 계보 칸이 들어간다', () async {
    for (final name in kinSectionNames) {
      final probe = _FakeProbe();
      final s = scenarioFor(name, width: 1538, height: 846, kin: probe) as KinSection;
      final samples = <FrameSample>[];
      bool landed = false;
      for (double now = 0; now < 30000; now += 1000 / 60) {
        s.step(now, false);
        if (!landed && probe.opening != null) {
          landed = true;
          probe.land();
          await Future<void>.delayed(Duration.zero);
        }
        // 대역 장면: 움직이던 장면만 간격을 센다(runner의 _join과 같은 규칙).
        samples.add(FrameSample(buildMs: 3, rasterMs: 4, vsyncGapMs: s.moving ? 1000 / 60 : 0));
      }
      s.finish(30000);
      expect(probe.calls.last, 'close', reason: name);
      expect(s.valid, isTrue, reason: name);
      final verdict = judge(samples, 60);
      expect(verdict.frames, samples.length);
      expect(verdict.pass, isTrue, reason: '대역 장면은 예산 안 — $name');
      final c = caseJson(name: name, repeat: 1, seconds: 30, cold: false, valid: s.valid, outsideInputs: const [], verdict: verdict, series: s.series(), counts: s.counts(peakRssMib: 300));
      final back = jsonDecode(jsonEncode(c)) as Map<String, dynamic>;
      expect(back['kin_view'], kinViews[name]);
      expect(back['kin_probe'], isTrue);
      expect(back['kin_ready'], isTrue);
      expect(back['kin_record_bytes'], 2400000);
      expect(back['kin_decode_ms'], 31);
      expect(back['kin_open_ms'], isA<num>());
      expect(back['kin_built_max'], 40);
      expect((back['kin_layout_ms'] as Map)['n'], greaterThan(10), reason: '접을 때마다 자리 셈을 적는다 — $name');
      expect((back['kin_pick_ms'] as Map)['p99'], closeTo(.03, 1e-9));
      final actions = back['kin_actions'] as Map;
      expect(actions['open'], 1);
      expect(actions['toggle'], greaterThanOrEqualTo(20));
      if (name == '세계표') {
        expect(actions['bring'], 3);
        expect(actions['overview'], 4);
        expect(actions['down'], greaterThanOrEqualTo(8));
      } else {
        expect(actions['wheel'], greaterThanOrEqualTo(72));
        expect(actions['scroll'], greaterThan(100));
      }
      expect((back['kin_budget'] as Map)['pass'], isTrue, reason: name);
      final report = buildReport(environment: const {'display_hz': 60}, cases: [c]);
      expect(report['result'], '합격');
      expect(summaryLine(c), contains(name));
    }
  });

  test('창을 열지 못하면 그 회차는 무효이고 까닭을 적는다', () async {
    final probe = _FakeProbe();
    final s = scenarioFor('세계표', width: 1538, height: 846, kin: probe) as KinSection;
    s.step(0, false);
    probe.fail(StateError('뼈대 기록 없음'));
    await Future<void>.delayed(Duration.zero);
    for (double now = 16; now < 3000; now += 16) {
      expect(s.step(now, false), isEmpty);
    }
    expect(s.valid, isFalse);
    expect(s.counts()['kin_error'], contains('뼈대 기록 없음'));
    final c = caseJson(name: '세계표', repeat: 1, seconds: 3, cold: false, valid: s.valid, outsideInputs: const [], verdict: judge(const [], 60), counts: s.counts());
    expect(buildReport(environment: const {}, cases: [c])['result'], '무효');
  });

  group('측정 손잡이를 앱 창에 잇기(KinDriverProbe — D1-N2 조종 손잡이 · D1-N1 바탕)', () {
    test('구간 이름 → 창 갈래 · 측정 선택지(--kin-polity · --kin-family)', () {
      final (:bus, :store, :scene) = measureBus();
      addTearDown(() => _dispose(bus, scene));
      String? option(String name) => {'--kin-polity': 'kin-measure/garam', '--kin-family': 'kin:h-on'}[name];
      final polity = kinProbeFor('승계표', bus, option) as KinDriverProbe;
      expect((polity.view, polity.target), ('succession', 'kin-measure/garam'));
      final family = kinProbeFor('세계표', bus, option) as KinDriverProbe;
      expect((family.view, family.target), ('family', 'kin:h-on'));
      expect(kinProbeFor('끌기', bus, option), isNull);
      expect(kinProbeFor('승계표', null, option), isNull);
      expect((kinProbeFor('세계표', bus, (_) => null) as KinDriverProbe).target, '');
      expect(slotKinDriver, 'kinDriver', reason: 'N2 손잡이 슬롯');
      expect(store, isEmpty);
    });

    test('승계표: 정권을 고르면 뜬 창의 손잡이를 잡고, 같은 기록을 한 번 더 받아 받기 · 풀기 · 첫 자리 셈을 잰다', () async {
      final (:bus, :store, :scene) = measureBus();
      addTearDown(() => _dispose(bus, scene));
      store['kin-measure/garam'] = jsonEncode({
        'name': '가람',
        'x_lineage': {
          'leader:0': {'kinAt': ['kin:h-on', 0]},
          'leader:1': {'kinAt': ['kin:h-on', 1]},
          'leader:2': {'kinAt': ['kin:h-other', 0]},
          'leader:3': {'fromUnknown': 1},
        },
      });
      final record = store['kin:h-on'] = kinRecordJson('kin:h-on', 400);
      final window = _FakeWindow('succession');
      bus.selection.addListener(() => bus.slot(slotKinDriver).value = bus.selection.value?.cell == successionCell ? window : null);
      final probe = KinDriverProbe(bus, view: 'succession', target: 'kin-measure/garam', firstFrame: () async {});
      final opening = probe.open();
      await Future<void>.delayed(Duration.zero);
      expect(bus.selection.value?.uid, 'kin-measure/garam');
      expect(bus.selection.value?.cell, successionCell);
      expect(probe.driver, same(window));
      window.land();
      final cost = await opening;
      expect(cost.target, 'kin:h-on', reason: '지도자 칸이 가장 많이 가리킨 뼈대');
      expect(cost.people, 400);
      expect(cost.bytes, utf8.encode(record).length);
      expect(cost.decodeMs, greaterThan(0));
      expect(cost.fetchMs, greaterThanOrEqualTo(0));
      expect(cost.layoutMs, greaterThanOrEqualTo(0));
      expect(probe.area, (left: 1520.0, top: 140.0, width: 380.0, height: 760.0));

      // 접기: 보이는 것 가운데 slot번째부터 — 펼 것이 없는 마디(손잡이가 거짓)는 건너뛰고, 짝의 둘째 번은 앞서 누른 것.
      probe.toggle(1);
      expect(window.calls, ['toggle a', 'toggle b']);
      expect(probe.busy, isTrue, reason: '접기 움직임');
      probe.toggle(1);
      expect(window.calls.last, 'toggle b');
      window.calls.clear();
      probe.toggle(2);
      expect(window.calls, ['toggle b']);
      final note = probe.takeNote();
      expect(note.layoutMs.length, 3, reason: '누른 셋의 자리 셈');
      expect((note.built, note.lines), (37, 0));
      expect(probe.takeNote().layoutMs, isEmpty, reason: '읽으면 비운다');

      // 막대 끌기: 모두 펼친 높이 × 비율의 차이만큼 보는 자리를 옮긴다.
      final skel = kinFromMap(jsonDecode(record) as Map<String, dynamic>);
      final leaders = [for (final at in skel.cells.values) KinLeaderSpot(skel, at)];
      final height = kinRowTops(kinRows(leaders, kinLevelOpen(leaders, KinLevel.all)), leaders.length).last;
      window.calls.clear();
      probe.scrollTo(1);
      probe.scrollTo(.5);
      expect(window.calls, ['pan 0,$height', 'pan 0,${(-height / 2).round()}'], reason: '양수 = 보는 자리가 아래로(N2 승계표 부호)');

      // 찾아 데려오기: 따로 푼 뼈대의 안정 열쇠로, 끝날 때까지 움직임 중.
      probe.bring(3);
      expect(window.calls.last, 'reveal ${skel.keys[kinBringIndex(3, 400)]}');
      window.revealing!.complete(true);
      await Future<void>.delayed(Duration.zero);

      probe.close();
      expect(bus.selection.value, isNull);
      expect(probe.driver, isNull);
    });

    test('세계표: 슬롯에 부탁을 넣어 열고, 전체도 누르기 · 막대 끌기는 모두 펼친 크기로 갈음하고, 닫으면 부탁을 비운다', () async {
      final (:bus, :store, :scene) = measureBus();
      addTearDown(() => _dispose(bus, scene));
      final record = store['kin:h-on'] = kinRecordJson('kin:h-on', 300, fan: 4);
      final window = _FakeWindow('family');
      bus.slot(slotFamily).addListener(() => bus.slot(slotKinDriver).value = bus.slot(slotFamily).value is FamilyRequest ? window : null);
      final probe = KinDriverProbe(bus, view: 'family', target: 'kin:h-on', firstFrame: () async {});
      final opening = probe.open();
      await Future<void>.delayed(Duration.zero);
      expect(bus.slot(slotFamily).value, const FamilyRequest(kin: 'kin:h-on'));
      window.land();
      final cost = await opening;
      expect((cost.target, cost.people), ('kin:h-on', 300));
      final skel = kinFromMap(jsonDecode(record) as Map<String, dynamic>);
      final width = kinLayout(skel, kinOpenAll(skel)).widthPx, height = skel.gens * kKinRowHeight;
      window.calls.clear();
      probe.overview(.5, .25);
      probe.scrollTo(1);
      expect(window.calls, ['pan ${(width / 2).round()},${(height / 4).round()}', 'pan ${(width / 2).round()},0']);
      probe.expandAll();
      probe.collapseAll();
      expect(window.calls.sublist(2), ['expand all', 'collapse all']);
      expect(probe.takeNote().layoutMs.length, 2);
      probe.close();
      expect(bus.slot(slotFamily).value, isNull);
    });

    test('계보를 정하지 않았거나 창이 뼈대를 받지 못하면 열기가 까닭과 함께 실패한다', () async {
      final (:bus, :store, :scene) = measureBus();
      addTearDown(() => _dispose(bus, scene));
      final empty = KinDriverProbe(bus, view: 'succession', target: '', firstFrame: () async {});
      await expectLater(empty.open(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('--kin-polity'))));
      final s = KinSection(kinPlanFor('승계표'), empty);
      s.step(0, false);
      await Future<void>.delayed(Duration.zero);
      expect(s.valid, isFalse);
      expect(s.counts()['kin_error'], contains('--kin-polity'));

      store['kin:h-on'] = kinRecordJson('kin:h-on', 10);
      final window = _FakeWindow('family')..readyNow = false;
      bus.slot(slotFamily).addListener(() => bus.slot(slotKinDriver).value = bus.slot(slotFamily).value == null ? null : window);
      final broken = KinDriverProbe(bus, view: 'family', target: 'kin:h-on', firstFrame: () async {});
      final opening = broken.open();
      await Future<void>.delayed(Duration.zero);
      window.land();
      await expectLater(opening, throwsA(isA<StateError>().having((e) => e.message, 'message', contains('뼈대를 받지 못했습니다'))));
    });

    test('구간 둘을 앱 창 손잡이(대역)로 끝까지 돌리면 오류 없이 judge가 판정을 내고, 창 안 입력은 창 몸통 안에 떨어진다', () async {
      for (final name in kinSectionNames) {
        final (:bus, :store, :scene) = measureBus();
        store['kin-measure/garam'] = jsonEncode({
          'x_lineage': {
            'leader:0': {'kinAt': ['kin:h-on', 0]},
          },
        });
        store['kin:h-on'] = kinRecordJson('kin:h-on', 2000);
        final window = _FakeWindow(kinViews[name]!, autoReveal: true);
        void show() => bus.slot(slotKinDriver).value = bus.selection.value?.cell == successionCell || bus.slot(slotFamily).value != null ? window : null;
        bus.selection.addListener(show);
        bus.slot(slotFamily).addListener(show);
        double now = 0;
        final probe = KinDriverProbe(bus, view: kinViews[name]!, target: name == '세계표' ? 'kin:h-on' : 'kin-measure/garam', firstFrame: () async {}, clock: () => now);
        const origin = (x: 40.0, y: 70.0);
        final s = scenarioFor(name, width: 1538, height: 846, kin: probe, origin: origin, cold: true) as KinSection;
        final samples = <FrameSample>[];
        final inputs = <Synthetic>[];
        for (; now < 30000; now += 1000 / 60) {
          inputs.addAll(s.step(now, false));
          if (now < 100) {
            if (window.calls.isEmpty && !window.landed) window.land();
            // 열기는 진짜 isolate(풀기 · 바이트 셈)를 거치므로 열릴 때까지 실제로 기다린다.
            for (var wait = 0; wait < 400 && !s.ready && s.error == null; wait++) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
          } else if (window.revealing != null) {
            await Future<void>.delayed(Duration.zero);
          }
          samples.add(FrameSample(buildMs: 2, rasterMs: 3, vsyncGapMs: s.moving ? 1000 / 60 : 0));
        }
        s.finish(now);
        expect(s.error, isNull, reason: name);
        expect(s.valid, isTrue, reason: name);
        expect(bus.slot(slotKinDriver).value, isNull, reason: '구간 끝에 창을 닫았다 — $name');
        // 창 안 입력(끌기 · 휠)은 창 몸통(1520, 140, 380 × 760) 안에서 시작한다 — 연표 위젯 자리(origin)를 더해 전역으로.
        for (final i in inputs) {
          final (x, y) = switch (i) {
            PointerDown(:final x, :final y) => (x, y),
            Wheel(:final x, :final y) => (x, y),
            _ => (double.nan, double.nan),
          };
          if (x.isNaN) continue;
          expect(x + origin.x, inInclusiveRange(1520, 1900), reason: '$name $i');
          expect(y + origin.y, inInclusiveRange(140, 900), reason: '$name $i');
        }
        final verdict = judge(samples, 60);
        expect(verdict.frames, samples.length);
        final c = caseJson(name: name, repeat: 0, seconds: 30, cold: true, valid: s.valid, outsideInputs: const [], verdict: verdict, series: s.series(), counts: s.counts(peakRssMib: 250));
        final back = jsonDecode(jsonEncode(c)) as Map<String, dynamic>;
        expect(back['kin_target'], 'kin:h-on');
        expect(back['kin_people'], 2000);
        expect(back['kin_record_bytes'], greaterThan(50000));
        expect(back['kin_built_max'], 37);
        expect((back['kin_layout_ms'] as Map)['n'], greaterThanOrEqualTo(20), reason: '접기 20회 + 모두 펼치기 · 접기 — $name');
        final actions = back['kin_actions'] as Map;
        expect(actions['toggle'], greaterThanOrEqualTo(20));
        if (name == '세계표') {
          expect(window.calls.where((c) => c.startsWith('reveal')).length, 3);
          expect(window.calls.where((c) => c.startsWith('pan')).length, 4, reason: '전체도 넷');
        } else {
          expect(window.calls.where((c) => c.startsWith('pan')).length, greaterThan(100), reason: '막대 끌기');
        }
        expect(buildReport(environment: const {'display_hz': 60}, cases: [c])['result'], '미달', reason: '처음 1회만이면 판정할 회차가 없다 — $name');
        _dispose(bus, scene);
      }
    });

    test('가상 대가족 5만: 머리 없는 창(N1의 진짜 셈)으로 구간 둘을 돌려 기록 크기 · 풀기 · 자리 셈을 적는다(시간 판정은 PC)', () async {
      const people = 50000;
      final record = kinRecordJson('kin:h-on', people);
      final skel = kinFromMap(jsonDecode(record) as Map<String, dynamic>);
      final lines = <String>[];
      for (final name in kinSectionNames) {
        final (:bus, :store, :scene) = measureBus();
        store['kin-measure/garam'] = jsonEncode({
          'x_lineage': {
            'leader:0': {'kinAt': ['kin:h-on', 0]},
          },
        });
        store['kin:h-on'] = record;
        final window = _HeadlessWindow(kinViews[name]!, skel);
        void show() => bus.slot(slotKinDriver).value = bus.selection.value?.cell == successionCell || bus.slot(slotFamily).value != null ? window : null;
        bus.selection.addListener(show);
        bus.slot(slotFamily).addListener(show);
        double now = 0;
        final probe = KinDriverProbe(bus, view: kinViews[name]!, target: name == '세계표' ? 'kin:h-on' : 'kin-measure/garam', firstFrame: () async {}, clock: () => now);
        final s = scenarioFor(name, width: 1538, height: 846, kin: probe) as KinSection;
        for (; now < 30000; now += 1000 / 60) {
          s.step(now, false);
          if (now < 100) {
            for (var wait = 0; wait < 2000 && !s.ready && s.error == null; wait++) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
          }
        }
        s.finish(now);
        expect(s.error, isNull, reason: name);
        final counts = s.counts(peakRssMib: null);
        expect(counts['kin_people'], people);
        expect(counts['kin_record_bytes'], utf8.encode(record).length);
        final layout = distribution(s.series()['kin_layout_ms']!);
        expect(layout['n'], greaterThanOrEqualTo(20), reason: name);
        expect(counts['kin_built_max'] as int, lessThanOrEqualTo(name == '세계표' ? 200 : 50), reason: '보이는 것만 — $name');
        lines.add(
          '$name 5만: 기록 ${((counts['kin_record_bytes'] as int) / 1048576).toStringAsFixed(2)}MiB · 풀기 ${(counts['kin_decode_ms'] as num).toStringAsFixed(1)}ms · '
          '첫 자리 셈 ${(counts['kin_first_layout_ms'] as num).toStringAsFixed(2)}ms · 접기 자리 셈 p50 ${(layout['p50'] as num).toStringAsFixed(2)} · '
          'p99 ${(layout['p99'] as num).toStringAsFixed(2)} · 최대 ${(layout['max'] as num).toStringAsFixed(2)}ms(${layout['n']}회) · 지은 수 최대 ${counts['kin_built_max']}',
        );
        _dispose(bus, scene);
      }
      // 클라우드(디버그 · JIT)에서 잰 참고값 — 판정은 PC의 배포 빌드에서.
      for (final line in lines) {
        // ignore: avoid_print
        print(line);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('진짜 승계표 창(D1-N2 SuccessionView)에 붙이기', () {
    testWidgets('정권을 고르면 뜨는 승계표 창을 측정 손잡이로 부려 구간을 25초 돌린다 — 휠 · 막대 끌기가 목록을 옮기고 · 지은 줄 ≤ 50 · 닫힘', (tester) async {
      for (final k in detailKinds) {
        DetailHost.unregister(k.id);
      }
      addTearDown(() {
        for (final k in detailKinds) {
          DetailHost.unregister(k.id);
        }
      });
      final kin = jsonDecode(kinRecordJson('kin:polity:k/garam', 2000)) as Map<String, Object?>;
      kin['cells'] = {for (var m = 0; m < 4; m++) 'k/garam|leader:$m': m};
      final polity = <String, Object?>{
        'uid': 'k/garam',
        'name': '가람 나라',
        'color': '#a0bcc5',
        'track': 'garam',
        'leaders': [
          for (var m = 0; m < 4; m++) {'name': '온 가람 $m', 'start': 1400 + 10 * m, 'end': 1410 + 10 * m, 'ordinal': m + 1, if (m > 0) 'accession': {}},
        ],
        'x_lineage': {
          for (var m = 0; m < 4; m++) 'leader:$m': {'line': m == 0 ? 0 : 5, if (m > 0) 'seam': '아들 · 세습', 'kinAt': ['kin:polity:k/garam', m]},
        },
      };
      final (:bus, :store, :scene) = measureBus();
      addTearDown(() => _dispose(bus, scene));
      store['k/garam'] = jsonEncode(polity);
      store['kin:polity:k/garam'] = jsonEncode(kin);
      registerItemDetail();
      registerCellDetail();
      registerKinDetail();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: Ui.detailWidth, height: 900, child: DetailHost(bus: bus, framed: false)),
            ),
          ),
        ),
      );
      double now = 0;
      final probe = KinDriverProbe(bus, view: 'succession', target: 'k/garam', firstFrame: () async {}, clock: () => now);
      final s = scenarioFor('승계표', width: 1538, height: 846, kin: probe) as KinSection;
      final samples = <FrameSample>[];
      final firsts = <String>{};
      for (; now < 25000; now += 1000 / 60) {
        for (final input in s.step(now, false)) {
          final event = switch (input) {
            Wheel(:final x, :final y, :final dy) => PointerScrollEvent(position: Offset(x, y), scrollDelta: Offset(0, dy), kind: PointerDeviceKind.mouse),
            PointerDown(:final x, :final y) => PointerDownEvent(pointer: 71, position: Offset(x, y), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton),
            PointerMove(:final x, :final y) => PointerMoveEvent(pointer: 71, position: Offset(x, y), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton),
            PointerUp(:final x, :final y) => PointerUpEvent(pointer: 71, position: Offset(x, y), kind: PointerDeviceKind.mouse),
            _ => null,
          };
          if (event != null) await tester.sendEventToBinding(event);
        }
        if (now > 0 && !s.ready && s.error == null) {
          // 열기는 진짜 isolate(창의 풀기 · 측정 손잡이의 비용 재기)를 거친다.
          await tester.runAsync(() async {
            for (var i = 0; i < 1000 && !s.ready && s.error == null; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
          });
        }
        final d = probe.driver;
        if (d != null && d.ready && d.visible.isNotEmpty) firsts.add(d.visible.first);
        final watch = Stopwatch()..start();
        await tester.pump(const Duration(microseconds: 16667));
        samples.add(FrameSample(buildMs: watch.elapsedMicroseconds / 1000, rasterMs: 0, vsyncGapMs: s.moving ? 1000 / 60 : 0));
      }
      s.finish(now);
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.valid, isTrue);
      expect(bus.slot(slotKinDriver).value, isNull, reason: '구간 끝에 창을 닫았다');
      expect(firsts.length, greaterThan(20), reason: '휠 · 막대 끌기가 목록을 옮겼다');
      final verdict = judge(samples, 60);
      expect(verdict.frames, samples.length);
      final c = caseJson(name: '승계표', repeat: 1, seconds: 25, cold: false, valid: s.valid, outsideInputs: const [], verdict: verdict, series: s.series(), counts: s.counts());
      expect(c['kin_target'], 'kin:polity:k/garam');
      expect(c['kin_people'], 2000);
      expect(c['kin_built_max'] as int, lessThanOrEqualTo(50), reason: '보이지 않는 줄은 짓지 않는다');
      expect((c['kin_actions'] as Map)['toggle'], 20);
      expect((c['kin_layout_ms'] as Map)['n'], greaterThanOrEqualTo(20));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // 결합(D1n)에서 더함: 세계표 창(D1-N2 FamilyWindow · 87a8d1b)이 들어와 대역 창 대신 진짜 창으로 세계표 구간을 돌린다.
  group('진짜 세계표 창(D1-N2 FamilyWindow)에 붙이기', () {
    testWidgets('슬롯 family에 부탁을 넣어 뜬 세계표를 측정 손잡이로 부려 구간을 한 바퀴 돌린다 — 끌기 · 전체도 갈음이 판을 옮기고 · 카드 ≤ 200 · 선 ≤ 300 · 닫힘', (tester) async {
      for (final k in detailKinds) {
        DetailHost.unregister(k.id);
      }
      DetailHost.unregisterWindow(familySlot);
      addTearDown(() {
        for (final k in detailKinds) {
          DetailHost.unregister(k.id);
        }
        DetailHost.unregisterWindow(familySlot);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      final (:bus, :store, :scene) = measureBus();
      addTearDown(() => _dispose(bus, scene));
      // 2천 명 · 세 갈래 나무 — 200명을 넘어 기본 펼침은 지도자 · 조상만(설계 4-5), 모두 펼치면 폭이 넓어 끌기 · 전체도가 판을 옮긴다.
      store['kin:h-measure'] = kinRecordJson('kin:h-measure', 2000);
      store['house:h-on'] = jsonEncode({'uid': 'house:h-on', 'name': '물빛 온씨', 'color': '#a0bcc5', 'x_kin': {'key': 'kin:h-measure', 'n': 2000, 'gens': 7, 'branches': []}});
      registerKinDetail();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(top: Ui.top + Ui.detailInset, right: Ui.detailInset, bottom: Ui.detailBottom, width: Ui.detailWidth, child: DetailHost(bus: bus, framed: false)),
              ],
            ),
          ),
        ),
      );
      double now = 0;
      final probe = KinDriverProbe(bus, view: 'family', target: 'kin:h-measure', firstFrame: () async {}, clock: () => now);
      final s = scenarioFor('세계표', width: 1538, height: 846, kin: probe) as KinSection;
      final samples = <FrameSample>[];
      final seen = <String>{};
      var inside = 0, pointers = 0;
      for (; now < 32000; now += 1000 / 60) {
        for (final input in s.step(now, false)) {
          final event = switch (input) {
            Wheel(:final x, :final y, :final dy) => PointerScrollEvent(position: Offset(x, y), scrollDelta: Offset(0, dy), kind: PointerDeviceKind.mouse),
            PointerDown(:final x, :final y) => PointerDownEvent(pointer: 72, position: Offset(x, y), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton),
            PointerMove(:final x, :final y) => PointerMoveEvent(pointer: 72, position: Offset(x, y), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton),
            PointerUp(:final x, :final y) => PointerUpEvent(pointer: 72, position: Offset(x, y), kind: PointerDeviceKind.mouse),
            _ => null,
          };
          if (event == null) continue;
          // 누름 · 휠은 창 몸통 안에서 시작해야 한다(끄는 중의 옮김은 창 밖으로 나가도 된다 — 손을 떼지 않은 끌기).
          if (event is PointerDownEvent || event is PointerScrollEvent) {
            pointers++;
            final a = probe.driver?.area;
            if (a != null && a.inflate(1).contains(event.position)) inside++;
          }
          await tester.sendEventToBinding(event);
        }
        if (now > 0 && !s.ready && s.error == null) {
          // 열기는 진짜 isolate(창의 풀기 · 측정 손잡이의 비용 재기)를 거친다.
          await tester.runAsync(() async {
            for (var i = 0; i < 1000 && !s.ready && s.error == null; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
          });
        }
        final d = probe.driver;
        if (d != null && d.ready && d.visible.isNotEmpty) seen.add(d.visible.first);
        final watch = Stopwatch()..start();
        await tester.pump(const Duration(microseconds: 16667));
        samples.add(FrameSample(buildMs: watch.elapsedMicroseconds / 1000, rasterMs: 0, vsyncGapMs: s.moving ? 1000 / 60 : 0));
      }
      s.finish(now);
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.valid, isTrue);
      expect(bus.slot(slotFamily).value, isNull, reason: '구간 끝에 세계표 부탁을 비웠다');
      expect(bus.slot(slotKinDriver).value, isNull, reason: '창이 닫히며 손잡이를 내렸다');
      expect(pointers, greaterThan(0));
      expect(inside, pointers, reason: '창 안 누름 · 휠은 모두 세계표 몸통 안에 떨어진다');
      expect(seen.length, greaterThan(3), reason: '끌기 · 전체도 갈음 · 찾아 데려오기가 판을 옮겼다');
      final verdict = judge(samples, 60);
      expect(verdict.frames, samples.length);
      final c = caseJson(name: '세계표', repeat: 1, seconds: 32, cold: false, valid: s.valid, outsideInputs: const [], verdict: verdict, series: s.series(), counts: s.counts());
      expect(c['kin_view'], 'family');
      expect(c['kin_target'], 'kin:h-measure');
      expect(c['kin_people'], 2000);
      expect(c['kin_built_max'] as int, lessThanOrEqualTo(200), reason: '보이지 않는 카드는 짓지 않는다');
      expect(c['kin_lines_max'] as int, lessThanOrEqualTo(300));
      final acts = c['kin_actions'] as Map;
      expect(acts['toggle'], 20);
      expect(acts['bring'], 3);
      expect(acts['overview'], 4);
      expect((c['kin_layout_ms'] as Map)['n'], greaterThanOrEqualTo(20));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// 머리 없는 창: N2 창 대신 N1의 진짜 셈(세계표 kinToggle · kinLayout · visibleIn, 승계표 kinRows · kinRowTops)으로 접고 펴고
/// 보이는 것을 고른다 — 그리기만 없다. 창 몸통 380 × 760(승계표) · 830 × 760(세계표).
class _HeadlessWindow implements KinDriver {
  _HeadlessWindow(this.kind, this.skel) {
    if (kind == 'family') {
      open = kinDefaultOpen(skel);
    } else {
      leaders = [for (final at in skel.cells.values) KinLeaderSpot(skel, at)];
      levels = kinLevelOpen(leaders, KinLevel.leaders);
    }
    _relayout();
  }

  @override
  final String kind;
  final KinSkeleton skel;
  late Uint8List open;
  late List<KinLeaderSpot> leaders;
  late Map<String, Uint8List> levels;
  KinLayout? layout;
  Int32List rows = Int32List(0), tops = Int32List(1);
  double scrollX = 0, scrollY = 0;
  double get viewW => kind == 'family' ? 830 : 380;
  static const viewH = 760.0;

  void _relayout() {
    if (kind == 'family') {
      layout = kinLayout(skel, open);
    } else {
      rows = kinRows(leaders, levels);
      tops = kinRowTops(rows, leaders.length);
    }
    _clamp();
  }

  void _clamp() {
    final wide = kind == 'family' ? layout!.widthPx.toDouble() : viewW, tall = kind == 'family' ? (skel.gens * kKinRowHeight).toDouble() : tops.last.toDouble();
    scrollX = scrollX.clamp(0, math.max(0, wide - viewW)).toDouble();
    scrollY = scrollY.clamp(0, math.max(0, tall - viewH)).toDouble();
  }

  @override
  Future<void> get loaded => Future<void>.value();
  @override
  bool get ready => true;

  @override
  void expandAll() {
    if (kind == 'family') {
      open = kinOpenAll(skel);
    } else {
      levels = kinLevelOpen(leaders, KinLevel.all);
    }
    _relayout();
  }

  @override
  void collapseAll() {
    if (kind == 'family') {
      open = kinOpenNone(skel);
    } else {
      levels = kinLevelOpen(leaders, KinLevel.leaders);
    }
    _relayout();
  }

  @override
  List<String> get visible {
    final out = <String>[];
    if (kind == 'family') {
      final l = layout!;
      for (var g = math.max(0, scrollY ~/ kKinRowHeight); g < l.rows.length && g * kKinRowHeight < scrollY + viewH; g++) {
        final (:start, :end) = l.visibleIn(g, scrollX.floor(), (scrollX + viewW).ceil());
        for (var k = start; k < end; k++) {
          out.add(skel.keys[l.rows[g][k]]);
        }
      }
      return out;
    }
    // 승계표: 누적 높이에서 화면 위 끝의 줄을 이분 탐색하고, 보이는 줄 + 위아래 8줄.
    final count = kinRowCount(rows);
    var a = 0, b = count;
    while (a < b) {
      final mid = (a + b) >> 1;
      if (tops[mid + 1] <= scrollY) {
        a = mid + 1;
      } else {
        b = mid;
      }
    }
    for (var r = math.max(0, a - 8); r < count && tops[r] < scrollY + viewH + 8 * kKinRowLine; r++) {
      final kindOf = rows[r * 3], at = rows[r * 3 + 1];
      out.add(switch (kindOf) { kKinRowLeader => skel.keys[leaders[at].at], kKinRowPerson => skel.keys[at], _ => 'skip:$at' });
    }
    return out;
  }

  @override
  bool toggle(String key) {
    final i = skel.indexOfKey(key);
    if (i < 0 || !skel.hasChildren(i)) return false;
    if (kind == 'family') {
      final before = layout!.cardLeft(i);
      kinToggle(skel, open, i);
      _relayout();
      // 누른 카드는 화면에서 0px — 스크롤을 그 카드의 Δx만큼 옮긴다.
      scrollX += layout!.cardLeft(i) - before;
      _clamp();
    } else {
      kinToggle(skel, levels[skel.key]!, i);
      _relayout();
    }
    return true;
  }

  @override
  void panBy(double dx, double dy) {
    // N2 승계표와 같은 부호 — 양수면 보는 자리가 아래 · 오른쪽으로.
    scrollX += dx;
    scrollY += dy;
    _clamp();
  }

  @override
  Future<bool> reveal(String key) {
    final i = skel.indexOfKey(key);
    if (i < 0) return Future.value(false);
    if (kind == 'family') {
      kinOpenTo(skel, open, i);
      _relayout();
      scrollX = layout!.cardLeft(i) - viewW / 2;
      scrollY = skel.gen[i] * kKinRowHeight - viewH / 2;
      _clamp();
    }
    return Future.value(true);
  }

  @override
  int get built => visible.length;
  @override
  int get lines => kind == 'family' ? visible.length : 0;
  @override
  Rect? get area => Rect.fromLTWH(1520 - (viewW - 380), 140, viewW, viewH);
}

/// 측정 손잡이 검사용 AppBus — 항목 기록은 [store]의 글에서(없으면 '없는 항목'), 그 밖의 조회는 거절한다.
({AppBus bus, Map<String, String> store, TimelineScene scene}) measureBus() {
  final controller = TimelineController()..resize(1920, 500);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 0},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('측정 손잡이 검사는 타일을 읽지 않는다'),
  );
  final store = <String, String>{};
  final bus = AppBus(
    ask: (query) async {
      final uid = '${query['uid']}';
      if (query['op'] == 'entity' && store.containsKey(uid)) return {'uid': uid, 'kind': 'x', 'json': store[uid]};
      throw StateError('없는 항목: $uid');
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, store: store, scene: scene);
}

void _dispose(AppBus bus, TimelineScene scene) {
  bus.dispose();
  scene.dispose();
}

/// 결정적 합성 뼈대 기록(열 꼴 — D1-E ②): 사람 [n]명, 너비 우선 번호로 [fan]갈래 나무를 짓고 앞 차례(선순)로 바꾼다.
/// 앞 차례 0 … [leaders]−1(뿌리에서 맏이로 내려가는 사슬)이 지도자다. 이름은 가상(온 가람 n).
String kinRecordJson(String uid, int n, {int fan = 3, int leaders = 4}) {
  final kids = List.generate(n, (_) => <int>[]);
  for (var k = 1; k < n; k++) {
    kids[(k - 1) ~/ fan].add(k);
  }
  final order = <int>[], depth = List.filled(n, 0), stack = [0];
  while (stack.isNotEmpty) {
    final v = stack.removeLast();
    order.add(v);
    for (final c in kids[v].reversed) {
      depth[c] = depth[v] + 1;
      stack.add(c);
    }
  }
  final at = List.filled(n, 0);
  for (var i = 0; i < n; i++) {
    at[order[i]] = i;
  }
  final par = [for (final v in order) v == 0 ? -1 : at[(v - 1) ~/ fan]];
  final gen = [for (final v in order) depth[v]];
  final size = List.filled(n, 1);
  for (var i = n - 1; i > 0; i--) {
    size[par[i]] += size[i];
  }
  var gens = 0;
  for (final g in gen) {
    if (g + 1 > gens) gens = g + 1;
  }
  final zeros = List.filled(n, 0);
  return jsonEncode({
    'v': 1,
    'uid': uid,
    'n': n,
    'gens': gens,
    'par': par,
    'size': size,
    'gen': gen,
    'bits': [for (var i = 0; i < n; i++) i < leaders ? 33 : 1],
    'edge': zeros,
    'branch': zeros,
    'color': zeros,
    'color2': <int>[],
    'name': [for (var i = 0; i < n; i++) '온 가람 $i'],
    'sub': List.filled(n, ''),
    'key': [for (var i = 0; i < n; i++) 'f:kin-measure/p$i'],
    'extra': <int>[],
    'colors': [''],
    'branches': [
      {'uid': 'house:h-on', 'name': '물빛 온씨', 'color': '#a0bcc5', 'at': 0, 'up': -1},
    ],
    'cells': {for (var m = 0; m < leaders; m++) 'kin-measure/garam|leader:$m': m},
    'stubs': <String, Object>{},
    'warnings': <String>[],
  });
}

/// 앱 창 조종 손잡이(D1-N2 KinDriver)의 대역: 부른 일을 적는다. 보이는 마디 넷 가운데 'a'는 펼 것이 없는 잎.
class _FakeWindow implements KinDriver {
  _FakeWindow(this.kind, {this.autoReveal = false});
  @override
  final String kind;
  final bool autoReveal;
  final calls = <String>[];
  final _loaded = Completer<void>();
  bool readyNow = true;
  bool get landed => _loaded.isCompleted;
  Completer<bool>? revealing;

  void land() => _loaded.complete();

  @override
  Future<void> get loaded => _loaded.future;
  @override
  bool get ready => readyNow;
  @override
  void expandAll() => calls.add('expand all');
  @override
  void collapseAll() => calls.add('collapse all');
  @override
  List<String> get visible => const ['c:kin-measure/garam|leader:0', 'a', 'b', 'c'];
  @override
  bool toggle(String key) {
    calls.add('toggle $key');
    return key != 'a';
  }

  @override
  void panBy(double dx, double dy) => calls.add('pan ${dx.round()},${dy.round()}');
  @override
  Future<bool> reveal(String key) {
    calls.add('reveal $key');
    final c = revealing = Completer<bool>();
    if (autoReveal) scheduleMicrotask(() => c.complete(true));
    return c.future;
  }

  @override
  int get built => 37;
  @override
  int get lines => kind == 'family' ? 120 : 0;
  @override
  Rect? get area => const Rect.fromLTWH(1520, 140, 380, 760);
}
