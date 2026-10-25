import '../scene/aux_calendar.dart';
import '../scene/marks.dart';
import 'app_bus.dart';
import 'app_memory.dart';
import 'filter_state.dart';

/// DLC 순환 선택과 보는 사람의 간지 켬끔을 잇는다. 웹 HT.yearCycleUi와 같은 기억이다.
class YearCycleGlue {
  YearCycleGlue(this.bus, Map<String, dynamic> meta) : _cycles = YearCycle.fromMeta(meta);
  final AppBus bus;
  List<YearCycle> _cycles;
  final cycleSeen = <String>{};
  bool cycleAutoOff = false, _ready = false, _syncing = false;
  AppMemory? _memory;
  static const slotName = 'yearCycle';

  void start({bool ready = false}) {
    _ready = ready;
    bus.scene.addListener(sync);
    bus.slot('filters').addListener(sync);
    sync();
  }

  void attachMemory(AppMemory memory) {
    _memory = memory;
    final saved = memory.parts[slotName];
    cycleSeen
      ..clear()
      ..addAll([if (saved?['cycleSeen'] is List) for (final key in saved!['cycleSeen'] as List) if (key is String) key]);
    cycleAutoOff = saved?['cycleAutoOff'] == true;
    _ready = true;
    sync();
  }

  /// 저장소 교체 알림도 새 후보와 함께 처리한다. 옛 후보의 기본 끔이 순간 선택되어
  /// 아직 본 적 없는 DLC를 cycleSeen에 잘못 적지 않게 한다.
  void replaceMeta(Map<String, dynamic> meta, {void Function()? applyLayout}) {
    final wasSyncing = _syncing;
    _syncing = true;
    try {
      _cycles = YearCycle.fromMeta(meta);
      applyLayout?.call();
    } finally { _syncing = wasSyncing; }
    sync();
  }

  void sync() {
    if (_syncing) return;
    _syncing = true;
    try {
      final layout = bus.scene.layout;
      final keys = {for (final p in layout.packs) if (layout.isPackEnabled(p.id)) p.key};
      YearCycle? cycle;
      for (final c in _cycles) {
        if (c.packId.isEmpty || keys.contains(c.packId)) { cycle = c; break; }
      }
      final marks = SceneMarks.of(bus.scene);
      if (!identical(marks.yearCycle, cycle)) {
        marks.yearCycle = cycle;
        marks.version++;
        bus.slot(slotName).value = cycle;
        bus.scene.requestFrame();
      }
      if (!_ready) return;
      final state = bus.slot('filters').value;
      if (state is! FilterState) return;
      var on = state.showing('ganji'), changed = false;
      if (cycle?.off == true) {
        if (cycleSeen.add(cycle!.packId)) {
          changed = true;
          if (on) { on = false; cycleAutoOff = true; }
        }
      } else if (cycleAutoOff) {
        cycleAutoOff = false;
        on = true;
        changed = true;
      }
      if (on != state.showing('ganji')) bus.slot('filters').value = state.copyWith(show: {...state.show, 'ganji': on});
      if (changed && _memory != null) {
        _memory!.parts[slotName] = {'cycleSeen': cycleSeen.toList(), if (cycleAutoOff) 'cycleAutoOff': true};
        _memory!.save();
      }
    } finally { _syncing = false; }
  }

  void dispose() {
    bus.scene.removeListener(sync);
    bus.slot('filters').removeListener(sync);
  }
}
