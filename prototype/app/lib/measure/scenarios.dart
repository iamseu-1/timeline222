import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import '../motion.dart';
import '../ui/app_bus.dart';
import '../ui/app_glue.dart' show slotFamily, slotKinDriver;
import '../ui/detail_shell.dart' show successionCell;
import '../ui/kin/family_window.dart';
import '../ui/kin/kin_head.dart' show KinDriver;
import '../ui/kin/kin_layout.dart';
import '../ui/kin/kin_record.dart';
import '../ui/kin/kin_rows.dart';
import 'frame_stats.dart' show percentile;

// 측정 구간의 합성 입력. 시각과 '장면이 아직 바쁜가'만 받아 그 장면에 넣을 입력을 돌려주는 순수한 계산이라,
// 같은 기록을 넣으면 늘 같은 입력이 나온다(검사로 못 박아 둔다). 실제로 넣는 일은 runner가 한다.
// 입력은 장면마다 한 번, 그 장면의 시각으로 넣는다 — 8ms 시계로 넣으면 144Hz 화면과 어긋나
// '입력이 없어 그릴 것이 없던 장면'이 놓친 장면으로 세어진다(입력 장치의 한계이지 그리기의 한계가 아니다).

const sectionNames = ['끌기', '확대', '돋보기', '밀집', '세로', '자료집'];

/// 합성 입력 하나. 자리는 연표 위젯 안의 px.
sealed class Synthetic {
  const Synthetic();
}

class PointerDown extends Synthetic {
  const PointerDown(this.x, this.y);
  final double x, y;
  @override
  String toString() => 'down ${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
}

class PointerMove extends Synthetic {
  const PointerMove(this.x, this.y);
  final double x, y;
  @override
  String toString() => 'move ${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
}

class PointerUp extends Synthetic {
  const PointerUp(this.x, this.y);
  final double x, y;
  @override
  String toString() => 'up ${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
}

class Wheel extends Synthetic {
  const Wheel(this.x, this.y, this.dy);
  final double x, y, dy;
  @override
  String toString() => 'wheel ${dy.toStringAsFixed(0)}';
}

class PinchStart extends Synthetic {
  const PinchStart(this.x, this.y);
  final double x, y;
  @override
  String toString() => 'pinch start';
}

class PinchUpdate extends Synthetic {
  const PinchUpdate(this.x, this.y, this.scale);
  final double x, y, scale;
  @override
  String toString() => 'pinch ${scale.toStringAsFixed(3)}';
}

class PinchEnd extends Synthetic {
  const PinchEnd(this.x, this.y);
  final double x, y;
  @override
  String toString() => 'pinch end';
}

/// 조감 켬/끔(V)도 장면에 바로 시킨다 — 밀도를 조감 ↔ 자동으로(건의 8의 8번 '크게 바뀌는 장면'을 잰다).
class ToggleBird extends Synthetic {
  const ToggleBird();
  @override
  String toString() => 'bird';
}

/// 자료집 켬/끔은 화면 입력이 아니라 장면에 바로 시킨다(스위치를 누른 뒤의 일과 같다).
class TogglePack extends Synthetic {
  const TogglePack(this.pack, this.on);
  final int pack;
  final bool on;
  @override
  String toString() => 'pack $pack ${on ? 'on' : 'off'}';
}

abstract class Scenario {
  String get name;

  /// 장면마다 한 번 부른다. [sceneBusy]는 앞선 움직임(관성 · 쫓아가기 · 떠오름)이 아직 끝나지 않았는가.
  List<Synthetic> step(double nowMs, bool sceneBusy);

  /// 구간이 끝날 때: 누른 채면 떼고, 끈 자료집은 다시 켠다.
  List<Synthetic> finish(double nowMs);
}

/// [packs]는 켤 수 있는 자료집 번호(위에서부터), [trackless]는 그 가운데 트랙 없이 사건만 덧붙인 것.
/// 계보 창 구간(kinSectionNames)이면 [kin]으로 창을 부리고, [origin]은 연표 위젯의 전역 자리 · [cold]는 처음 1회(찬 상태)인가.
/// [kin]이 없으면(창을 부릴 길이 아직 없는 앱) 아무 입력도 내지 않는 구간이 된다 — 오류 없이 끝나고 counts에 kin_probe: false.
Scenario scenarioFor(
  String name, {
  required double width,
  required double height,
  List<int> packs = const [],
  List<int> trackless = const [],
  KinProbe? kin,
  ({double x, double y}) origin = (x: 0.0, y: 0.0),
  bool cold = false,
}) {
  if (kinSectionNames.contains(name)) return KinSection(kinPlanFor(name), kin, origin: origin, cold: cold);
  final x = width * .6, y = height * .45;
  return switch (name) {
    '확대' => _WheelScenario(x, y),
    '돋보기' => _PinchScenario(x, y),
    '세로' => _DragScenario('세로', x, y, vertical: true),
    '자료집' => _PackScenario(packs, trackless),
    '조감' => _BirdScenario(),
    '밀집' => _DragScenario('밀집', x, y), // 끌기와 같은 입력, 시작 장면(같은 날 몰린 나흘 보기)만 다르다
    _ => _DragScenario('끌기', x, y),
  };
}

/// 끌기와 관성: 1.2초 동안 한쪽으로 끌다(최고 약 1,100px/s) 달리던 속도로 놓고, 관성이 멎고 0.2초 쉰 뒤 반대쪽으로 되풀이한다.
class _DragScenario implements Scenario {
  _DragScenario(this.name, this.homeX, this.homeY, {this.vertical = false});
  @override
  final String name;
  final double homeX, homeY;
  final bool vertical;
  double at = 0; // 끄는 축의 자리(집에서부터)
  bool down = false;
  int direction = -1;
  double phaseStart = -1, restSince = -1;

  // 세로는 몸통이 짧으니 덜 끈다.
  double get reach => vertical ? 150 : 420;

  PointerMove _move(double offset) {
    at = offset;
    return vertical ? PointerMove(homeX, homeY + offset) : PointerMove(homeX + offset, homeY);
  }

  @override
  List<Synthetic> step(double now, bool sceneBusy) {
    if (!down) {
      if (sceneBusy) {
        restSince = -1;
        return const [];
      }
      if (restSince < 0) restSince = now;
      if (now - restSince < 200) return const [];
      down = true;
      phaseStart = now;
      // 5px 문턱은 누른 장면에서 바로 넘는다.
      return [PointerDown(homeX, homeY), _move(direction * 6.0)];
    }
    final t = now - phaseStart;
    if (t < 1200) return [_move(direction * (6 + reach * (1 - math.cos(t / 1200 * math.pi))))];
    final out = <Synthetic>[_move(at + direction * 7.6)];
    if (t >= 1260) {
      out.add(vertical ? PointerUp(homeX, homeY + at) : PointerUp(homeX + at, homeY));
      down = false;
      direction = -direction;
      restSince = -1;
    }
    return out;
  }

  @override
  List<Synthetic> finish(double now) => down ? [vertical ? PointerUp(homeX, homeY + at) : PointerUp(homeX + at, homeY)] : const [];
}

/// 빠른 휠 확대와 축소: 80ms마다 한 칸씩 12칸 확대, 12칸 축소를 되풀이한다.
class _WheelScenario implements Scenario {
  _WheelScenario(this.x, this.y);
  final double x, y;
  @override
  String get name => '확대';
  int sent = 0;
  double start = -1;

  @override
  List<Synthetic> step(double now, bool sceneBusy) {
    if (start < 0) start = now;
    final out = <Synthetic>[];
    while (sent <= (now - start) / 80) {
      out.add(Wheel(x, y, sent % 24 < 12 ? -100 : 100));
      sent++;
    }
    return out;
  }

  @override
  List<Synthetic> finish(double now) => const [];
}

/// 돋보기(크기까지 커지는 확대): 트랙패드 집기 입력으로 6초마다 100% → 300% → 100% → 50% → 100%를 되풀이한다.
class _PinchScenario implements Scenario {
  _PinchScenario(this.x, this.y);
  final double x, y;
  @override
  String get name => '돋보기';
  double start = -1;

  @override
  List<Synthetic> step(double now, bool sceneBusy) {
    final out = <Synthetic>[];
    if (start < 0) {
      start = now;
      out.add(PinchStart(x, y));
    }
    final wave = math.sin((now - start) / 6000 * 2 * math.pi);
    out.add(PinchUpdate(x, y, wave >= 0 ? 1 + 2 * wave : 1 + .5 * wave));
    return out;
  }

  @override
  List<Synthetic> finish(double now) => [PinchEnd(x, y)];
}

/// 조감 켬/끔: 0.9초마다 한 번(줄의 흐름 0.4초가 끝나고 이름이 들어온 뒤). 기본 목록에는 없다 — `--sections=조감`으로 부른다.
class _BirdScenario implements Scenario {
  @override
  String get name => '조감';
  int done = 0;
  double start = -1;

  @override
  List<Synthetic> step(double now, bool sceneBusy) {
    if (start < 0) start = now;
    if (now - start < (done + 1) * 900) return const [];
    done++;
    return const [ToggleBird()];
  }

  /// 조감으로 끝났으면 되돌린다.
  @override
  List<Synthetic> finish(double now) => done.isOdd ? const [ToggleBird()] : const [];
}

/// 자료집 켬/끔: 0.7초마다 하나씩 끄고 켠다. 맨 위 자료집은 그대로 두고(보던 줄이 남게), 트랙 있는 것과 없는 것을 번갈아.
class _PackScenario implements Scenario {
  _PackScenario(List<int> packs, List<int> trackless) {
    final withTracks = [for (final p in packs) if (!trackless.contains(p)) p];
    targets = [if (withTracks.length > 1) withTracks[1], if (trackless.isNotEmpty) trackless.first];
  }
  @override
  String get name => '자료집';
  late final List<int> targets;
  int done = 0;
  double start = -1;

  @override
  List<Synthetic> step(double now, bool sceneBusy) {
    if (start < 0) start = now;
    if (targets.isEmpty || now - start < (done + 1) * 700) return const [];
    final toggle = TogglePack(targets[(done ~/ 2) % targets.length], done.isOdd);
    done++;
    return [toggle];
  }

  @override
  List<Synthetic> finish(double now) => done.isOdd ? [TogglePack(targets[(done ~/ 2) % targets.length], true)] : const [];
}

// ---- 계보 창 구간: 승계표 · 세계표 (docs/설계-10건/1-2-계승과-가문-확정.md 6-5 ③ · 묶음 D1-N4) ----
// 연표 구간과 같은 틀에서 돈다: 장면마다 한 번 · 30초 × 3회 · 처음 1회(찬 상태)는 따로 · runner의 _join과 frame_stats의 judge로 판정.
// 할 일의 차례(KinPlan)는 시각과 창의 상태(열렸나 · 아직 움직이나)만 받아 할 일을 내는 순수한 계산이라, 같은 기록이면 늘 같은 일이 나온다.
// 그 일을 창에 시키는 것은 KinSection이 측정 손잡이 KinProbe로 한다 — 앱 창(D1-N2)의 조종 손잡이 KinDriver(bus 슬롯 'kinDriver')에
// 기대어 채우는 측정 쪽 꼴이다. 창 안의 끌기 · 휠은 연표 구간과 같은 합성 입력으로 runner가 넣고, 열기 · 접기 · 모두 펼치기 ·
// 찾아 데려오기 · 전체도 누르기는 손잡이에 바로 시킨다 — 자료집 켬/끔을 장면에 바로 시키는 것과 같은 까닭이다(단추를 누른 뒤의 일을 잰다).
// 함께 적는 것(6-5 ③): 기록 크기 · 받는 시간 · 풀기 시간 · 자리 셈 ms · 빈 자리 · 상주 메모리(runner가 잰 것과 함께 kinBudget으로 견준다).

/// 계보 창 구간. 기본 측정(sectionNames — 앱 안 빠른 측정도)에는 넣지 않는다: 계보 기록이 없는 저장소의 측정이 그대로이게.
/// 계보가 있는 저장소에서 `--sections=승계표,세계표`로 부른다.
const kinSectionNames = ['승계표', '세계표'];

/// 구간 → 창 갈래(상세 갈래 id `succession` · 세계표 창 id `family` — 설계 1절).
const kinViews = {'승계표': 'succession', '세계표': 'family'};

/// 계보 창에 시킬 일 하나. 화면 입력(KinActPointer)만 runner의 합성 입력 길로 가고, 나머지는 KinProbe에 바로 시킨다.
sealed class KinAct {
  const KinAct();
}

/// 창을 연다(누름 → 첫 장면). 기록 받기(엔진 한 번) · 풀기(작업자 isolate) · 첫 자리 셈이 여기에 든다.
class KinActOpen extends KinAct {
  const KinActOpen();
  @override
  String toString() => 'open';
}

/// 바닥의 `모두 펼치기`.
class KinActExpandAll extends KinAct {
  const KinActExpandAll();
  @override
  String toString() => 'expand all';
}

/// 바닥의 `모두 접기`.
class KinActCollapseAll extends KinAct {
  const KinActCollapseAll();
  @override
  String toString() => 'collapse all';
}

/// 접기 · 펼치기 한 번: 지금 보이는 것 가운데 접고 펼 수 있는 [slot]번째(KinProbe.toggle).
class KinActToggle extends KinAct {
  const KinActToggle(this.slot);
  final int slot;
  @override
  String toString() => 'toggle $slot';
}

/// 목록을 전체의 [fraction] 자리로 옮긴다 — 스크롤 막대를 끄는 것과 같다(승계표의 '끝까지 밀기').
class KinActScroll extends KinAct {
  const KinActScroll(this.fraction);
  final double fraction;
  @override
  String toString() => 'scroll ${fraction.toStringAsFixed(3)}';
}

/// 찾아 데려오기: [slot]번째로 고른 사람(kinBringIndex)을 찾기 칸으로 찾아 그 카드로 간다(세계표).
class KinActBring extends KinAct {
  const KinActBring(this.slot);
  final int slot;
  @override
  String toString() => 'bring $slot';
}

/// 전체도의 (fx, fy) 자리를 누른다 — 너비 · 높이에 대한 비율(세계표).
class KinActOverview extends KinAct {
  const KinActOverview(this.fx, this.fy);
  final double fx, fy;
  @override
  String toString() => 'overview ${fx.toStringAsFixed(2)},${fy.toStringAsFixed(2)}';
}

enum KinActPress { down, move, up, wheel }

/// 창 안의 화면 입력(끌기 · 휠). 자리는 창 크기에 대한 비율(fx, fy)에 px(dx, dy)를 더한 것이라 창이 열리기 전에도 정해 둘 수 있다.
class KinActPointer extends KinAct {
  const KinActPointer(this.press, this.fx, this.fy, {this.dx = 0, this.dy = 0, this.wheel = 0});
  final KinActPress press;
  final double fx, fy, dx, dy, wheel;
  @override
  String toString() => press == KinActPress.wheel ? 'wheel ${wheel.toStringAsFixed(0)}' : '${press.name} ${dx.toStringAsFixed(1)},${dy.toStringAsFixed(1)}';
}

/// 계획이 보는 창의 상태: 열려 첫 장면이 그려졌나 · 창 안의 움직임(옮김 판 · 관성 · 날아가기 · 끌기)이 아직 도나.
typedef KinPlanState = ({bool ready, bool busy});

/// 계보 창 구간의 차례. 장면마다 한 번 부른다(순수한 계산 — 같은 시각 · 같은 상태면 같은 일).
abstract class KinPlan {
  String get name;
  List<KinAct> step(double nowMs, KinPlanState state);

  /// 구간이 끝날 때: 누른 채면 뗀다.
  List<KinAct> finish(double nowMs);
}

/// 처음에 한 번 열고(첫 장면 뒤 0.3초 쉼), 한 바퀴를 시간이 다할 때까지 되풀이한다.
KinPlan kinPlanFor(String name) => name == '세계표' ? _KinPlan('세계표', _familyRound) : _KinPlan('승계표', _successionRound);

/// 승계표 한 바퀴(웹 측정 kin-bench 구간 1의 차례 — 열기 → 모두 펼치기 → 끝까지 밀기 → 접기 · 펼치기 20회):
/// 모두 펼치기 → 휠 12칸씩 세 번 → 목록 끌기 위 · 아래 → 막대 끌기로 끝까지 → 끝에서 휠 12칸씩 세 번 거슬러 → 막대 끌기로 처음까지 →
/// 접기 · 펼치기 20회(400ms 간격 — 같은 줄을 접고 다시 펴는 짝 열) → 모두 접기. 약 22초(접기 움직임 360ms를 기다려서).
List<_Beat> _successionRound(int round) => [
  _Once(const [KinActExpandAll()]), _Rest(200),
  for (var i = 0; i < 3; i++) ...[_Every(80, 12, (_) => const [KinActPointer(KinActPress.wheel, .5, .5, wheel: 100)]), _Rest(200)],
  _Drag(.5, .6, -math.pi / 2, reach: 120), _Rest(200),
  _Drag(.5, .4, math.pi / 2, reach: 120), _Rest(200),
  _Sweep(0, 1, 1200), _Rest(200),
  for (var i = 0; i < 3; i++) ...[_Every(80, 12, (_) => const [KinActPointer(KinActPress.wheel, .5, .5, wheel: -100)]), _Rest(200)],
  _Sweep(1, 0, 1200), _Rest(200),
  _Every(400, 20, (i) => [KinActToggle(i ~/ 2)]), _Rest(200),
  _Once(const [KinActCollapseAll()]), _Rest(200),
];

/// 세계표 한 바퀴(웹 측정 kin-bench 구간 2의 차례 — 열기 → 8방향 끌기 + 관성 → 접기 20회 → 찾아 데려오기 → 전체도 누르기):
/// 기본 접힘에서 네 방향(→ ← ↓ ↑) 끌기 → 모두 펼치기 → 펼친 채 네 대각선 끌기 → 접기 · 펼치기 20회 → 찾아 데려오기 셋 →
/// 전체도 누르기 넷(왼 · 오른 · 위 · 아래) → 모두 접기. 약 28초(관성 · 날아가기를 기다려서). 방향은 짝으로 되돌아와 끌기마다 같은 동네를 지난다.
List<_Beat> _familyRound(int round) => [
  for (final degrees in const [0.0, 180.0, 90.0, 270.0]) ...[_Drag(.5, .45, degrees * math.pi / 180), _Rest(200)],
  _Once(const [KinActExpandAll()]), _Rest(200),
  for (final degrees in const [45.0, 225.0, 135.0, 315.0]) ...[_Drag(.5, .45, degrees * math.pi / 180), _Rest(200)],
  _Every(400, 20, (i) => [KinActToggle(i ~/ 2)]), _Rest(200),
  for (var k = 0; k < 3; k++) ...[_Once([KinActBring(round * 3 + k)]), _Rest(400)],
  for (final (fx, fy) in const [(.1, .5), (.9, .5), (.5, .2), (.5, .8)]) ...[_Once([KinActOverview(fx, fy)]), _Rest(300)],
  _Once(const [KinActCollapseAll()]), _Rest(200),
];

class _KinPlan implements KinPlan {
  _KinPlan(this.name, this.round);
  @override
  final String name;
  final List<_Beat> Function(int round) round;
  final _queue = <_Beat>[_Once(const [KinActOpen()]), _Rest(300)];
  int _rounds = 0;
  _Beat? _beat;
  double _beatStart = 0;
  KinActPointer? _held;

  @override
  List<KinAct> step(double now, KinPlanState state) {
    final out = <KinAct>[];
    // 끝난 박자의 다음 박자는 같은 장면에서 바로 시작한다(한 번 내는 일 뒤의 입력이 한 장면 늦지 않게). 시간이 드는 박자에서 멈춘다.
    for (var guard = 0; guard < 64; guard++) {
      if (_beat == null) {
        if (_queue.isEmpty) _queue.addAll(round(_rounds++));
        _beat = _queue.removeAt(0);
        _beatStart = now;
      }
      final (:actions, :done) = _beat!.step(now - _beatStart, state);
      out.addAll(actions);
      if (!done) break;
      _beat = null;
    }
    for (final a in out) {
      if (a is KinActPointer && a.press != KinActPress.wheel) _held = a.press == KinActPress.up ? null : a;
    }
    return out;
  }

  @override
  List<KinAct> finish(double now) {
    final held = _held;
    _held = null;
    return held == null ? const [] : [KinActPointer(KinActPress.up, held.fx, held.fy, dx: held.dx, dy: held.dy)];
  }
}

typedef _Out = ({List<KinAct> actions, bool done});

/// 계획의 박자 하나. [t]는 이 박자를 시작한 뒤의 ms.
abstract class _Beat {
  _Out step(double t, KinPlanState state);
}

/// 한 번 내고 끝.
class _Once implements _Beat {
  _Once(this.actions);
  final List<KinAct> actions;
  @override
  _Out step(double t, KinPlanState state) => (actions: actions, done: true);
}

/// 쉼: 창이 열려 있고 움직임이 멎은 채로 [ms]가 지나면 끝. 움직임이 다시 돌면 처음부터 센다(연표 끌기 구간의 0.2초 쉼과 같은 규칙).
class _Rest implements _Beat {
  _Rest(this.ms);
  final double ms;
  double _since = -1;
  @override
  _Out step(double t, KinPlanState state) {
    if (!state.ready || state.busy) {
      _since = -1;
      return (actions: const [], done: false);
    }
    if (_since < 0) _since = t;
    return (actions: const [], done: t - _since >= ms);
  }
}

/// [interval]ms마다 하나씩 [count]번 — 움직임과 무관하게(빠른 휠 · 400ms 간격의 접기처럼). 마지막 뒤 한 간격을 더 기다린다.
class _Every implements _Beat {
  _Every(this.interval, this.count, this.make);
  final double interval;
  final int count;
  final List<KinAct> Function(int i) make;
  int _sent = 0;
  @override
  _Out step(double t, KinPlanState state) {
    final out = <KinAct>[];
    while (_sent < count && _sent * interval <= t) {
      out.addAll(make(_sent++));
    }
    return (actions: out, done: _sent >= count && t >= count * interval);
  }
}

/// 스크롤 막대 끌기: [from] → [to]를 [ms] 동안 천천히 출발해 천천히 닿게(코사인) 장면마다 옮긴다.
class _Sweep implements _Beat {
  _Sweep(this.from, this.to, this.ms);
  final double from, to, ms;
  @override
  _Out step(double t, KinPlanState state) {
    final p = math.min(t / ms, 1.0);
    return (actions: [KinActScroll(from + (to - from) * (1 - math.cos(p * math.pi)) / 2)], done: p >= 1);
  }
}

/// 끌기와 관성: ([fx], [fy])에서 [angle](라디안 · 화면 좌표 — 0은 오른쪽, π/2는 아래) 쪽으로 [ms] 동안 6 + 2×[reach]px를 끌다가
/// 약 1,100px/s로 달리며 60ms 뒤에 놓는다. 누른 장면에서 5px 문턱을 넘는다(연표 끌기 구간과 같은 꼴).
class _Drag implements _Beat {
  _Drag(this.fx, this.fy, this.angle, {this.reach = 200});
  final double fx, fy, angle, reach;
  static const ms = 900.0, speed = 1.1;
  bool _pressed = false;

  KinActPointer _at(KinActPress press, double offset) => KinActPointer(press, fx, fy, dx: offset * math.cos(angle), dy: offset * math.sin(angle));

  @override
  _Out step(double t, KinPlanState state) {
    if (!_pressed) {
      _pressed = true;
      return (actions: [KinActPointer(KinActPress.down, fx, fy), _at(KinActPress.move, 6)], done: false);
    }
    if (t < ms) return (actions: [_at(KinActPress.move, 6 + reach * (1 - math.cos(t / ms * math.pi)))], done: false);
    final offset = 6 + 2 * reach + speed * (t - ms);
    if (t < ms + 60) return (actions: [_at(KinActPress.move, offset)], done: false);
    return (actions: [_at(KinActPress.move, offset), _at(KinActPress.up, offset)], done: true);
  }
}

/// 창의 자리(전역 논리 px).
typedef KinProbeArea = ({double left, double top, double width, double height});

/// 측정 손잡이 — 측정 구간이 계보 창을 부리는 측정 쪽 꼴(주인 D1-N4 · 설계 문서 끝 '구현 이음새 기록').
/// 앱 창(D1-N2)의 조종 손잡이 KinDriver(`lib/ui/kin/kin_head.dart` · bus 슬롯 'kinDriver')에 기대어 채운다:
/// 열기는 bus(승계표 `select(정권 uid, cell: 'succession')` · 세계표 슬롯 'family'), 접기 · 모두 펼치기 · 찾아 데려오기는 그 손잡이,
/// 비용(받기 · 풀기 · 첫 자리 셈)은 같은 기록을 한 번 더 받아 D1-N1의 풀기 · 자리 셈으로 잰다. 이 꼴 자체는 창을 모른다.
abstract class KinProbe {
  /// 찬 상태로: 받아 둔 계보 기록 · 풀어 둔 뼈대 · 글 문단 캐시를 비운다. 처음 1회(cold) 앞에서만 부른다.
  void forget();

  /// 창을 연다 — 대상은 손잡이를 지을 때 정한다(측정 선택지 · 없으면 저장소에서 사람이 가장 많은 계보).
  /// 접힘은 기본(3-4 · 4-5의 '처음 열 때')으로 하고 접힘 기억(app_memory)은 읽지도 쓰지도 않는다 — 회차마다 같은 데서 출발하게.
  /// 첫 장면이 그려진 뒤에 끝나고 그 비용을 돌려준다. 열 수 없으면 오류로 끝낸다(까닭은 보고서의 kin_error).
  Future<KinProbeCost> open();

  /// 창 몸통(목록 · 나무가 그려지는 곳)의 자리. 화면 입력은 열린 뒤에만 내므로 열리기 전에는 아무 값이나 괜찮다.
  KinProbeArea get area;

  /// 창 안의 움직임(접기 · 펼치기의 옮김 판 · 관성 · 날아가기 · 끌기)이 아직 도는가.
  bool get busy;

  /// 지금 보이는 것 가운데 접고 펼 수 있는 것(자식이 있는 사람 줄 · 후손이 있는 지도자 카드 · 세계표 카드)을 읽는 차례
  /// (승계표는 위 → 아래, 세계표는 위 세대부터 왼 → 오른)로 셀 때 [slot]번째(보이는 수로 나눈 나머지)를 누른다.
  /// 같은 slot이 잇따라 오면 앞서 누른 것을 다시 누른다 — 둘째 번에 제자리로 돌아온다.
  void toggle(int slot);

  void expandAll();
  void collapseAll();

  /// 목록(승계표)을 (전체 높이 − 보이는 높이) × [fraction] 자리로 바로 옮긴다. 세계표는 가로 자리로.
  void scrollTo(double fraction);

  /// 찾아 데려오기: 앞 차례 번호 kinBringIndex([slot], 사람 수)의 사람을 찾기 칸으로 찾아 조상을 펴고 그 카드로 간다.
  void bring(int slot);

  /// 전체도의 너비 · 높이에 대한 비율 자리(fx, fy)를 누른다.
  void overview(double fx, double fy);

  /// 앞서 읽은 뒤의 기록. 장면마다 한 번 읽는다.
  KinProbeNote takeNote();

  /// 구간이 끝날 때 창을 닫는다.
  void close();
}

/// 창을 여는 데 든 것(KinProbe.open의 답).
class KinProbeCost {
  const KinProbeCost({this.target = '', this.bytes = 0, this.fetchMs = 0, this.decodeMs = 0, this.layoutMs = 0, this.people = 0, this.chunks = 1});

  /// 연 계보의 열쇠(뼈대 uid `kin:…` — 승계표면 정권 uid).
  final String target;

  /// 받은 기록 글(`json`)의 바이트. 나눈 덩어리면 열 때 받은 것들의 합.
  final int bytes;

  /// 엔진 조회(`entity` 한 번)의 ms · 작업자 isolate 풀기의 ms · 첫 자리 셈의 ms.
  final double fetchMs, decodeMs, layoutMs;

  /// 뼈대의 사람 수 · 열 때 받은 덩어리 수.
  final int people, chunks;
}

/// 장면 사이의 기록(KinProbe.takeNote의 답).
class KinProbeNote {
  const KinProbeNote({this.built = 0, this.blank = 0, this.lines = 0, this.layoutMs = const [], this.pickMs = const []});

  /// 지금 지어 둔 줄 위젯(승계표) · 그린 카드(세계표)의 수.
  final int built;

  /// 보이는 카드 · 줄인데 글이 아직 없는 수(빈 자리 — 0이어야 한다).
  final int blank;

  /// 그린 선의 수(세계표).
  final int lines;

  /// 앞서 읽은 뒤에 한 자리 셈(접기 · 펼치기 · 모두 펼치기 · 찾아 펴기 한 번마다 — 열 때의 첫 셈은 KinProbeCost에만)과 보이는 것 고르기의 ms.
  final List<double> layoutMs, pickMs;
}

/// 찾아 데려오기에 고를 사람의 앞 차례 번호: 큰 소수 걸음으로 뼈대 전체에 고루 흩는다(깊은 곳 · 접힌 곳이 고루 든다). 결정적이다.
int kinBringIndex(int slot, int people) => people <= 0 ? 0 : (slot * 7919 + people ~/ 2) % people;

/// 계보 창 구간 하나: 계획을 장면마다 돌려 창에 시키고, 창 안의 화면 입력은 연표 위젯 안의 자리로 바꿔 runner에 돌려준다.
/// runner는 이것을 다른 구간과 똑같이 재생한다. 결합 때 runner에서 잇는 것(이 파일 밖):
///  · 장면 기록의 '움직이던 장면'에 [moving]을, 놓친 장면 단서에 [frameNote]를, 입력 → 첫 반응을 잴 장면에 [acted]를 더한다.
///  · caseJson의 series에 [series]를, counts에 [counts](그 회차 상주 메모리의 최댓값과 함께)를 더하고 valid에 [valid]를 건다.
class KinSection implements Scenario {
  KinSection(this.plan, this.probe, {this.origin = (x: 0.0, y: 0.0), this.cold = false});
  final KinPlan plan;
  final KinProbe? probe;

  /// 연표 위젯의 전역 자리 — runner는 합성 입력의 자리를 연표 위젯 안의 px로 받는다.
  final ({double x, double y}) origin;
  final bool cold;

  @override
  String get name => plan.name;
  String get view => kinViews[plan.name] ?? '';

  bool _started = false, _ready = false, _acted = false, _down = false;
  String? _error;
  KinProbeCost? _cost;
  double? _openMs;
  final _clock = Stopwatch();
  KinProbeNote _last = const KinProbeNote();
  int _blank = 0, _builtMax = 0, _linesMax = 0;
  final _layoutMs = <num>[], _pickMs = <num>[], _built = <num>[], _lines = <num>[];
  final _actions = <String, int>{};

  /// 창이 열려 첫 장면이 그려졌나.
  bool get ready => _ready;
  String? get error => _error;
  KinProbeCost? get cost => _cost;

  /// 이번 장면에 창에 일을 시켰나(화면 입력 포함) — 입력 → 첫 반응을 잴 장면.
  bool get acted => _acted;

  /// 창 안이 움직이던 장면인가(끄는 중 · 옮김 판 · 관성 · 날아가기). 멎어 있던 사이의 긴 간격은 놓친 장면이 아니다.
  bool get moving => _down || (probe?.busy ?? false);

  /// 판정에 넣어도 되는 회차인가: 창을 부릴 길이 있고, 창이 열렸고, 오류가 없었다.
  bool get valid => probe != null && _ready && _error == null;

  /// 놓친 장면의 단서(runner의 장면 기록에 더한다).
  Map<String, num> get frameNote => {'kin_built': _last.built, 'kin_blank': _last.blank, 'kin_lines': _last.lines, 'kin_busy': moving ? 1 : 0};

  @override
  List<Synthetic> step(double now, bool sceneBusy) {
    _acted = false;
    final d = probe;
    if (d == null) return const [];
    if (!_started) {
      _started = true;
      if (cold) d.forget();
    }
    _take(d);
    // 계보 창의 계획은 창의 움직임만 본다 — 뒤의 연표(sceneBusy)가 바빠도 창의 차례는 그대로.
    final actions = plan.step(now, (ready: _ready, busy: d.busy));
    if (actions.isEmpty) return const [];
    _acted = true;
    final out = <Synthetic>[];
    for (final a in actions) {
      final kind = _kindOf(a);
      _actions[kind] = (_actions[kind] ?? 0) + 1;
      switch (a) {
        case KinActOpen():
          _open(d);
        case KinActExpandAll():
          d.expandAll();
        case KinActCollapseAll():
          d.collapseAll();
        case KinActToggle(:final slot):
          d.toggle(slot);
        case KinActScroll(:final fraction):
          d.scrollTo(fraction);
        case KinActBring(:final slot):
          d.bring(slot);
        case KinActOverview(:final fx, :final fy):
          d.overview(fx, fy);
        case KinActPointer():
          out.add(_input(a, d.area));
      }
    }
    return out;
  }

  @override
  List<Synthetic> finish(double now) {
    final d = probe;
    if (d == null) return const [];
    _take(d);
    final out = [for (final a in plan.finish(now)) if (a is KinActPointer) _input(a, d.area)];
    d.close();
    return out;
  }

  static String _kindOf(KinAct a) => switch (a) {
    KinActOpen() => 'open',
    KinActExpandAll() => 'expand_all',
    KinActCollapseAll() => 'collapse_all',
    KinActToggle() => 'toggle',
    KinActScroll() => 'scroll',
    KinActBring() => 'bring',
    KinActOverview() => 'overview',
    KinActPointer(:final press) => press.name,
  };

  void _open(KinProbe d) {
    _clock
      ..reset()
      ..start();
    d.open().then(
      (cost) {
        _clock.stop();
        _openMs = _clock.elapsedMicroseconds / 1000;
        _cost = cost;
        _ready = true;
      },
      onError: (Object e) {
        _clock.stop();
        _error = '$e';
      },
    );
  }

  void _take(KinProbe d) {
    final note = d.takeNote();
    _last = note;
    _blank += note.blank;
    _builtMax = math.max(_builtMax, note.built);
    _linesMax = math.max(_linesMax, note.lines);
    if (_ready) {
      _built.add(note.built);
      _lines.add(note.lines);
    }
    _layoutMs.addAll(note.layoutMs);
    _pickMs.addAll(note.pickMs);
  }

  Synthetic _input(KinActPointer p, KinProbeArea f) {
    final x = f.left - origin.x + f.width * p.fx + p.dx, y = f.top - origin.y + f.height * p.fy + p.dy;
    switch (p.press) {
      case KinActPress.down:
        _down = true;
        return PointerDown(x, y);
      case KinActPress.move:
        return PointerMove(x, y);
      case KinActPress.up:
        _down = false;
        return PointerUp(x, y);
      case KinActPress.wheel:
        return Wheel(x, y, p.wheel);
    }
  }

  /// 장면마다의 값(caseJson이 분포로 줄여 담는다).
  Map<String, List<num>> series() => {'kin_layout_ms': _layoutMs, 'kin_pick_ms': _pickMs, 'kin_built': _built, 'kin_lines': _lines};

  /// 그대로 담는 수와 예산 대조. [peakRssMib]는 runner가 잰 이 회차 상주 메모리의 최댓값(MiB).
  Map<String, Object?> counts({num? peakRssMib}) => {
    'kin_view': view,
    'kin_probe': probe != null,
    'kin_ready': _ready,
    if (_error != null) 'kin_error': _error,
    'kin_target': _cost?.target,
    'kin_record_bytes': _cost?.bytes,
    'kin_fetch_ms': _cost?.fetchMs,
    'kin_decode_ms': _cost?.decodeMs,
    'kin_first_layout_ms': _cost?.layoutMs,
    'kin_people': _cost?.people,
    'kin_chunks': _cost?.chunks,
    'kin_open_ms': _openMs,
    'kin_blank': _blank,
    'kin_built_max': _builtMax,
    'kin_lines_max': _linesMax,
    'kin_actions': Map<String, int>.of(_actions),
    'kin_budget': kinBudget(view: view, cost: _cost, layoutMs: _layoutMs, pickMs: _pickMs, blank: _blank, builtMax: _builtMax, linesMax: _linesMax, peakRssMib: peakRssMib),
  };
}

/// 계보 창의 예산(설계 6-1 · 6-2 — 5만 명 덩어리 기준)과 견준 표: 항목마다 {value, limit, pass}이고 값이 없으면 pass는 null.
/// 시간 항목(받기 · 풀기 · 자리 셈 · 고르기)은 PC에서 잰 값으로만 판정하고 클라우드 값은 참고다.
/// 장면 판정(judge)과 따로 적고 보고서의 전체 판정에는 넣지 않는다. 'pass'는 값을 아는 항목이 모두 한도 안인가.
Map<String, Object?> kinBudget({
  required String view,
  KinProbeCost? cost,
  List<num> layoutMs = const [],
  List<num> pickMs = const [],
  int blank = 0,
  int builtMax = 0,
  int linesMax = 0,
  num? peakRssMib,
}) {
  Map<String, Object?> item(num? value, num limit) => {'value': value, 'limit': limit, 'pass': value == null ? null : value <= limit};
  double? p99(List<num> values) => values.isEmpty ? null : percentile([for (final v in values) v.toDouble()], .99);
  final family = view == 'family';
  final items = <String, Map<String, Object?>>{
    'blank': item(blank, 0),
    'built_max': item(builtMax, family ? 200 : 50),
    if (family) 'lines_max': item(linesMax, 300),
    'fetch_ms': item(cost?.fetchMs, 10),
    'decode_ms': item(cost?.decodeMs, 60),
    'layout_p99_ms': item(p99(layoutMs), 2),
    'pick_p99_ms': item(p99(pickMs), .1),
    'rss_peak_mib': item(peakRssMib, 400),
  };
  return {...items, 'pass': items.values.every((i) => i['pass'] != false)};
}

// ---- 측정 손잡이를 앱 창에 잇기: D1-N2의 조종 손잡이 KinDriver + D1-N1의 계보 바탕 ----

/// 계보 구간의 측정 손잡이를 측정 선택지로 짓는다 — 승계표 `--kin-polity=<정권 uid>` · 세계표 `--kin-family=<뿌리 뼈대 uid>`.
/// 연표 구간이거나 bus가 없으면 null(그러면 KinSection은 입력 없이 끝난다). 선택지를 비우면 창을 열 때 까닭을 적고 그 회차는 무효.
KinProbe? kinProbeFor(String name, AppBus? bus, String? Function(String name) option) {
  final view = kinViews[name];
  if (view == null || bus == null) return null;
  return KinDriverProbe(bus, view: view, target: option(view == 'family' ? '--kin-family' : '--kin-polity') ?? '');
}

/// 측정 손잡이를 앱 창으로 채운 것.
///  · 열기: 승계표는 `bus.select(정권 uid, cell: successionCell)`, 세계표는 슬롯 [slotFamily]에 FamilyRequest — 창이 슬롯
///    [slotKinDriver]에 제 손잡이(KinDriver)를 실으면 `loaded`를 기다리고 첫 장면이 그려질 때까지.
///  · 비용: 창이 열린 뒤 같은 기록을 한 번 더 받아(엔진은 제 isolate라 화면을 막지 않음) 받는 ms · 바이트, D1-N1 `decodeKin`(작업자 isolate)의
///    풀기 ms, 첫 자리 셈 ms(세계표 `kinLayout(기본 펼침)` · 승계표 `kinRows(지도자만)`)를 잰다. 그 뼈대의 안정 열쇠로 찾아 데려오기를 고른다.
///  · 접기 · 모두 펼치기 · 모두 접기는 손잡이에 시키고 부른 시간을 자리 셈 ms로 적는다(누른 뒤 그 장면의 셈 — 그리기는 장면 판정이 잰다).
///  · 손잡이에 아직 없는 길(움직임 중 · 빈 자리 · 고르기 ms · 막대 끌기 · 전체도 누르기 · 캐시 비우기)은 비슷하게 갈음한다:
///    움직임 중 = 접기 뒤 Motion.move · 찾아 데려오기가 끝날 때까지, 막대 끌기 · 전체도 누르기 = 모두 펼친 크기에 비율을 곱한 `panBy`(양수 = 보는 자리가 아래 · 오른쪽으로).
///    손잡이에 그 길이 생기면 여기 한 곳만 바꾼다.
class KinDriverProbe implements KinProbe {
  KinDriverProbe(this.bus, {required this.view, required this.target, this.firstFrame, this.clock});
  final AppBus bus;

  /// 첫 장면을 기다리는 길(검사가 장면 없이 돌릴 때 바꾼다). 없으면 SchedulerBinding.endOfFrame.
  final Future<void> Function()? firstFrame;

  /// 움직임 중을 셀 시계(ms — 검사가 장면 시각으로 바꾼다). 없으면 실제 시계.
  final double Function()? clock;

  /// `succession`(승계표) · `family`(세계표).
  final String view;

  /// 승계표: 정권 uid · 세계표: 뿌리 뼈대 uid(`kin:…`).
  final String target;

  KinSkeleton? _skel;
  double _width = 0, _height = 0, _atX = 0, _atY = 0, _busyUntil = 0;
  int _revealing = 0;
  int? _lastSlot;
  String? _lastKey;
  final _clock = Stopwatch()..start();
  final _layoutMs = <double>[];

  /// 측정이 연 이 갈래의 창 손잡이(다른 갈래의 창이면 null).
  KinDriver? get driver {
    final value = bus.slot(slotKinDriver).value;
    return value is KinDriver && value.kind == view ? value : null;
  }

  double get _now => clock?.call() ?? _clock.elapsedMicroseconds / 1000;
  void _moved([double ms = Motion.move]) => _busyUntil = math.max(_busyUntil, _now + ms);

  @override
  void forget() {
    // 창의 기록 캐시를 비우는 길은 손잡이에 아직 없다 — 측정 쪽에 받아 둔 것만 비운다.
    _skel = null;
  }

  @override
  Future<KinProbeCost> open() async {
    if (target.isEmpty) throw StateError('측정할 계보를 정하지 않았습니다 — 승계표는 --kin-polity=<정권 uid>, 세계표는 --kin-family=<뼈대 uid>');
    _lastSlot = _lastKey = null;
    _atX = _atY = 0;
    final shown = Completer<KinDriver>();
    void look() {
      final d = driver;
      if (d != null && !shown.isCompleted) shown.complete(d);
    }

    final slot = bus.slot(slotKinDriver)..addListener(look);
    try {
      if (view == 'family') {
        bus.slot(slotFamily).value = FamilyRequest(kin: target);
      } else {
        bus.select(target, cell: successionCell);
      }
      look();
      final d = await shown.future.timeout(const Duration(seconds: 30));
      await d.loaded;
      if (!d.ready) throw StateError('계보 창이 뼈대를 받지 못했습니다: $target');
      await (firstFrame?.call() ?? SchedulerBinding.instance.endOfFrame);
    } finally {
      slot.removeListener(look);
    }
    return _cost();
  }

  Future<KinProbeCost> _cost() async {
    final kin = view == 'family' ? target : await _polityKin(target);
    if (kin.isEmpty) throw StateError('정권 기록에 뼈대 자리(x_lineage의 kinAt)가 없습니다: $target');
    final watch = Stopwatch()..start();
    final answer = await bus.ask({'op': 'entity', 'uid': kin});
    final fetchMs = watch.elapsedMicroseconds / 1000;
    final json = '${answer['json'] ?? ''}';
    if (json.isEmpty) throw StateError('계보 기록이 없습니다: $kin');
    watch
      ..reset()
      ..start();
    final skel = _skel = await decodeKin(json, uid: kin);
    final decodeMs = watch.elapsedMicroseconds / 1000;
    watch
      ..reset()
      ..start();
    if (view == 'family') {
      kinLayout(skel, kinDefaultOpen(skel));
    } else {
      final leaders = [for (final at in skel.cells.values) KinLeaderSpot(skel, at)];
      kinRows(leaders, kinLevelOpen(leaders, KinLevel.leaders));
    }
    final layoutMs = watch.elapsedMicroseconds / 1000;
    // 막대 끌기 · 전체도 누르기를 갈음할 크기 — 모두 펼친 모습(구간이 펼친 채 끄므로).
    if (view == 'family') {
      _width = kinLayout(skel, kinOpenAll(skel)).widthPx.toDouble();
      _height = (skel.gens * kKinRowHeight).toDouble();
    } else {
      final leaders = [for (final at in skel.cells.values) KinLeaderSpot(skel, at)];
      final rows = kinRows(leaders, kinLevelOpen(leaders, KinLevel.all));
      _height = kinRowTops(rows, leaders.length).last.toDouble();
    }
    return KinProbeCost(target: kin, bytes: await _utf8Bytes(json), fetchMs: fetchMs, decodeMs: decodeMs, layoutMs: layoutMs, people: skel.n, chunks: 1);
  }

  @override
  KinProbeArea get area {
    final r = driver?.area;
    return r == null ? (left: 0.0, top: 0.0, width: 0.0, height: 0.0) : (left: r.left, top: r.top, width: r.width, height: r.height);
  }

  @override
  bool get busy => _revealing > 0 || _now < _busyUntil;

  void _timed(void Function() work) {
    final watch = Stopwatch()..start();
    work();
    _layoutMs.add(watch.elapsedMicroseconds / 1000);
    _moved();
  }

  @override
  void toggle(int slot) {
    final d = driver;
    if (d == null) return;
    // 짝의 둘째 번: 앞서 누른 것을 다시 눌러 제자리로.
    final again = _lastKey;
    if (slot == _lastSlot && again != null) {
      _lastSlot = _lastKey = null;
      _timed(() => d.toggle(again));
      return;
    }
    final keys = d.visible;
    if (keys.isEmpty) return;
    // 보이는 것 가운데 slot번째부터 차례로 — 접고 펼 것이 있는 첫 마디(없는 마디는 손잡이가 거짓을 돌려준다).
    for (var k = 0; k < keys.length && k < 64; k++) {
      final key = keys[(slot + k) % keys.length];
      final watch = Stopwatch()..start();
      if (d.toggle(key)) {
        _layoutMs.add(watch.elapsedMicroseconds / 1000);
        _moved();
        _lastSlot = slot;
        _lastKey = key;
        return;
      }
    }
  }

  @override
  void expandAll() {
    final d = driver;
    if (d != null) _timed(d.expandAll);
  }

  @override
  void collapseAll() {
    final d = driver;
    if (d != null) _timed(d.collapseAll);
  }

  @override
  void scrollTo(double fraction) {
    final d = driver;
    if (d == null) return;
    // 막대 끌기를 갈음: 모두 펼친 크기 × 비율의 차이만큼 보는 자리를 옮긴다(panBy 양수 = 보는 자리가 아래 · 오른쪽으로 —
    // N2 승계표가 offset + dy로 짓고 제 검사가 panBy(0, 3000)으로 끝까지 가는 부호. 끝을 넘으면 창이 끝에 멈춘다).
    if (view == 'family') {
      d.panBy((fraction - _atX) * _width, 0);
      _atX = fraction;
    } else {
      d.panBy(0, (fraction - _atY) * _height);
      _atY = fraction;
    }
  }

  @override
  void bring(int slot) {
    final d = driver, skel = _skel;
    if (d == null || skel == null || skel.n == 0) return;
    _revealing++;
    void done() {
      _revealing--;
      _moved();
    }

    d.reveal(skel.keys[kinBringIndex(slot, skel.n)]).then((_) => done(), onError: (Object _) => done());
  }

  @override
  void overview(double fx, double fy) {
    final d = driver;
    if (d == null) return;
    // 전체도 누르기를 갈음: 그 비율 자리로 한 번에 옮긴다(손잡이에 전체도 길이 생기면 그것으로).
    d.panBy((fx - _atX) * _width, (fy - _atY) * _height);
    _atX = fx;
    _atY = fy;
    _moved();
  }

  @override
  KinProbeNote takeNote() {
    final d = driver;
    final note = KinProbeNote(built: d?.built ?? 0, lines: d?.lines ?? 0, layoutMs: List.of(_layoutMs));
    _layoutMs.clear();
    return note;
  }

  @override
  void close() {
    if (view == 'family') {
      bus.slot(slotFamily).value = null;
    } else if (bus.selection.value?.cell == successionCell) {
      bus.clearSelection();
    }
  }

  /// 정권 기록의 지도자 칸이 가리키는 뼈대 가운데 가장 많이 든 것(x_lineage[ref].kinAt — D1-E ①). 기록은 작업자 isolate에서 푼다.
  Future<String> _polityKin(String polity) async {
    final answer = await bus.ask({'op': 'entity', 'uid': polity});
    final json = '${answer['json'] ?? ''}';
    return json.isEmpty ? '' : _mainKinOf(json);
  }
}

// 작업자 isolate로 넘기는 일은 바깥 함수로 둔다 — 닫힌 함수가 손잡이(알림 · 완료자)를 붙잡아 isolate로 보내지 못하는 일이 없게.
Future<int> _utf8Bytes(String text) => Isolate.run(() => utf8.encode(text).length, debugName: 'kin-measure-bytes');

Future<String> _mainKinOf(String polityJson) => Isolate.run(() => kinMainOf(polityJson), debugName: 'kin-measure-polity');

/// 정권 기록 글에서 지도자 칸들의 `kinAt` 뼈대 uid를 세어 가장 많이 든 것(같으면 먼저 나온 것). 없으면 빈 글.
String kinMainOf(String polityJson) {
  final raw = jsonDecode(polityJson);
  final lineage = raw is Map ? raw['x_lineage'] : null;
  final counts = <String, int>{};
  for (final row in lineage is Map ? lineage.values : (lineage is List ? lineage : const [])) {
    final ref = row is Map ? kinRefOf(row['kinAt']) : null;
    if (ref != null) counts[ref.key] = (counts[ref.key] ?? 0) + 1;
  }
  var best = '';
  counts.forEach((key, n) {
    if (best.isEmpty || n > counts[best]!) best = key;
  });
  return best;
}
