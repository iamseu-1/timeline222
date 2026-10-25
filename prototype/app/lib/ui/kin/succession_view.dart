import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../motion.dart';
import '../../motion_spring.dart';
import '../../shell/look.dart';
import '../app_memory.dart' show KinFoldMemory;
import '../context_menu.dart' show MenuRow, showTimelineMenu;
import '../date_text.dart' show civilAt;
import '../detail_shell.dart';
import 'family_window.dart';
import 'kin_head.dart';
import 'kin_layout.dart';
import 'kin_record.dart';
import 'kin_rows.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  승계표 창 — D1 결정 1 A(세로 한 줄 · 상세 창 자리) · 4 B · 8 A + 감독 덧붙임(접고 펴기 · 파 · 머리 태그)
//  설계: `docs/설계-10건/1-2-계승과-가문-확정.md` 3절 · 8-3 · 8-4. 목업 그림 `.claude/research/10건/D1/d1-1-a.png` · `d1-8-a.png`.
//
//  ◆ 여는 길: 나라 상세 '지도자' 상자의 `승계표` 단추 · 칸 창의 `승계표에서 보기` → `bus.select(정권 uid, cell: 'succession')`.
//  ◆ 읽는 것(정권 기록): leaders(칸 목록 — 시작 순) · color · x_head(머리 칩) · x_lineage['leader:i'] =
//      { kin · how(글) · kinUnknown · howUnknown · line(0~5) · seam(이음매 글 — 웹이 지은 그대로) · kinAt: [뿌리 뼈대 uid, 한 벌 번호] · elsewhere }.
//    뼈대(갈래 `kin` 기록)는 창을 열 때 뼈대마다 `entity` 한 번만 받고 **작업자 isolate에서 푼다**([decodeKin]) —
//    이 파일은 JSON을 풀지 않는다. 지도자가 나눈 덩어리 안이면 그 덩어리를 받아 합친다([kinReveal]).
//  ◆ 줄 규칙은 [kinRows](웹 `HT.successionRows`와 같은 규칙 — D1-N1). 이 파일은 그 줄 사이에 이음매(22px)를 끼워
//    `카드 34 · (펼친 줄 28 …) · 이음매 22 · 다음 카드` 차례로 세운다(펼친 줄은 카드와 이음매 사이 — 3-4 '이음매와의 자리').
//  ◆ 보이는 줄만 짓는다(`SliverVariedExtentList` — 줄 높이 누적합). 접고 펼 때 누른 줄은 0px 움직이고, 아래 줄은 옛 y → 새 y로
//    공통 move 스프링의 옮김 판을 띄운 뒤 목록으로 갈아 끼운다. 새 줄과 사라지는 줄은 in/out으로 옅어지며 재입력은 현재 자리와 속도를 잇는다.
//  ◆ 접힘은 보기 설정 — `bus.slot('kinFold')`의 [KinFoldMemory]에 정권 uid 열쇠로 기본과 다른 마디의 안정 열쇠만 남긴다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 칸 창의 `승계표에서 보기`가 실어 보내는 '그 카드로 데려가 펼친 채'(`{'uid': 정권 uid, 'cell': 'leader:3'}`).
const kinFocusSlot = 'kinFocus';

/// 계보 창에서 다른 창(인물 · 칸)을 열었을 때 그 창 바닥에 `◀ 승계표`를 붙이는 표(그 창이 [target]일 때만).
const kinBackSlot = 'kinBack';

/// 승계표에서 연 창 — 그 창의 uid · 칸이 [target] · [cell]이면 바닥에 `◀ 승계표`가 붙어 정권 [polity]의 승계표로 돌아간다.
@immutable
class KinBack {
  const KinBack({required this.polity, required this.target, this.cell});
  final String polity, target;
  final String? cell;
}

/// 승계표 갈래 · 세계표 떠 있는 창 · 칸 창의 `승계표에서 보기` · 승계표에서 연 창의 `◀ 승계표`를 등록한다
/// (app_glue의 `registerDetailKinds`가 부른다).
void registerKinDetail() {
  DetailHost.register('succession', SuccessionView.new);
  DetailHost.registerWindow(familySlot, (bus, value, close) => value is FamilyRequest ? FamilyWindow(bus: bus, request: value, onClose: close) : const SizedBox.shrink());
  DetailHost.registerFoot('cell', 'succession', _cellFoot);
  for (final id in const ['cell', 'figure', 'lineage']) {
    DetailHost.registerFoot(id, 'kinBack', _backFoot);
  }
}

/// 지도자 칸 창 — 지도자가 둘 이상인 나라면 `승계표에서 보기`(그 카드로 데려가 펼친 채).
List<Widget> _cellFoot(DetailContext ctx) {
  final cell = ctx.cell ?? '';
  if (!cell.startsWith('leader:') || detailList(ctx.json, 'leaders').length < 2) return const [];
  return [
    DetailSmallButton(
      '승계표에서 보기',
      onTap: () {
        ctx.slot(kinFocusSlot).value = {'uid': ctx.uid, 'cell': cell};
        ctx.open(ctx.uid, cell: successionCell);
      },
    ),
  ];
}

/// 승계표 · 세계표에서 연 창이면 `◀ 승계표`.
List<Widget> _backFoot(DetailContext ctx) {
  final back = ctx.slot(kinBackSlot).value;
  if (back is! KinBack || back.target != ctx.uid || (back.cell != null && back.cell != ctx.cell)) return const [];
  return [DetailSmallButton('◀ 승계표', onTap: () => ctx.open(back.polity, cell: successionCell))];
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  치수(1배 · 목업 D1_CSS 그대로)
// ────────────────────────────────────────────────────────────────────────────────────────────

abstract final class _G {
  /// 카드 오른쪽 여백(복위 고리 자리) · 카드 왼쪽에서 선 가운데까지 · 이음매 글 시작 · 펼친 줄 글 시작.
  static const loop = 30.0, line = 30.0, seamText = 46.0, rowText = 32.0;
  static const card = 34.0, seam = 22.0, row = 28.0;

  /// 목록 아래 끝이 옅어지는 높이.
  static const fade = 28.0;
}

enum _K { card, seam, person, skip }

/// 목록 한 줄 — 카드(지도자 m) · 이음매(m 앞) · 사람(지도자 [owner] 펼침 안의 마디 [j]) · 건너뛰기(지도자 m으로).
@immutable
class _Item {
  const _Item(this.k, {this.m = -1, this.j = -1, this.depth = 0, this.owner = -1, required this.key});
  final _K k;
  final int m, j, depth, owner;

  /// 안정 열쇠(옮김 판의 같은 줄 찾기 · 접힘 · 손잡이의 `visible`).
  final String key;

  double get extent => switch (k) {
    _K.card => _G.card,
    _K.seam => _G.seam,
    _ => _G.row,
  };
}

/// 승계표 창.
class SuccessionView extends StatefulWidget {
  const SuccessionView(this.ctx, {super.key});
  final DetailContext ctx;

  @override
  State<SuccessionView> createState() => _SuccessionViewState();
}

class _SuccessionViewState extends State<SuccessionView> implements KinDriver {
  DetailContext get ctx => widget.ctx;
  Map<String, dynamic> get x => ctx.json;

  late final List<Map<String, dynamic>> _leaders = detailList(x, 'leaders');
  late final Color _color = detailColor(x['color'], Ui.text3);
  late final Color _ink = KinUi.ink(_color);

  final _skels = <String, KinSkeleton>{};
  late List<KinLeaderSpot> _spots = List.filled(_leaders.length, const KinLeaderSpot.none());
  late Int32List _first = Int32List.fromList(List.generate(_leaders.length, (i) => i));
  final _open = <String, Uint8List>{};
  final _reach = <int, int>{};

  List<_Item> _items = const [];
  Float64List _tops = Float64List(1);
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: '승계표');
  final _listKey = GlobalKey();
  int _cursor = -1;

  final _loadedDone = Completer<void>();
  bool _ready = false;
  KinLevel _level = KinLevel.leaders;

  // 목록과 옮김 판이 같은 자리를 동시에 움직이지 않는다. 보이는 줄만 공통 장에서 옮긴다.
  _Shift? _shift;
  final _shiftFrames = ValueNotifier<int>(0);
  final _scrollFlight = MotionSpring(0, epsilon: .02, maxOvershoot: 4);
  bool _scrollFlying = false;

  /// 지금 지어 둔 줄 위젯(그리는 수 — 손잡이의 [built]).
  final _builtRows = <Object>{};

  @override
  void initState() {
    super.initState();
    MotionStage.instance.attach(_scrollFlight, _scrollTick);
    _scroll.addListener(_scrollShift);
    _rebuild();
    ctx.slot(kinBackSlot).value = null; // 돌아왔으면 `◀ 승계표`는 끝났다
    ctx.slot('kinDriver').value = this;
    unawaited(_load());
  }

  @override
  void dispose() {
    final driver = ctx.slot('kinDriver');
    if (identical(driver.value, this)) driver.value = null;
    _shift?.dispose();
    _shiftFrames.dispose();
    MotionStage.instance.detach(_scrollFlight);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── 자료 ──────────────────────────────────────────────────────────────────────────────────

  Map<String, dynamic>? _lin(int m) {
    final all = x['x_lineage'];
    if (all is! Map) return null;
    final one = all['leader:$m'];
    return one is Map ? one.cast<String, dynamic>() : null;
  }

  Future<String?> _fetch(String uid) async {
    try {
      final answer = await ctx.bus.ask({'op': 'entity', 'uid': uid});
      final json = answer['json'];
      return json is String && json.isNotEmpty ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// 지도자마다의 뼈대 자리를 모으고 뼈대를 받아 푼다(뼈대마다 `entity` 한 번 · 풀기는 작업자 isolate).
  Future<void> _load() async {
    try {
      final refs = <int, ({String key, int at})>{};
      for (var m = 0; m < _leaders.length; m++) {
        final r = kinRefOf(_lin(m)?['kinAt']);
        if (r != null && r.at >= 0) refs[m] = r;
      }
      for (final uid in {for (final r in refs.values) r.key}) {
        final text = await _fetch(uid);
        if (text == null) continue;
        try {
          _skels[uid] = await kinDecode(text, uid: uid);
        } catch (_) {
          // 깨진 기록은 그 뼈대만 빼고 연다 — 카드는 그대로 선다.
        }
      }
      // 나눈 덩어리 안의 지도자는 그 덩어리를 받아 합친다(합치면 번호가 밀리므로 자리는 마지막에 다시 찾는다).
      for (final r in refs.values) {
        final s = _skels[r.key];
        if (s == null || s.locate(r.at).at >= 0) continue;
        _skels[r.key] = (await kinRevealIn(s, r.at, _fetch)).skel;
      }
      if (!mounted) return;
      final spots = [
        for (var m = 0; m < _leaders.length; m++)
          if (refs[m] case final r? when _skels[r.key] != null && _skels[r.key]!.locate(r.at).at >= 0)
            KinLeaderSpot(_skels[r.key], _skels[r.key]!.locate(r.at).at)
          else
            const KinLeaderSpot.none(),
      ];
      _spots = spots;
      _first = kinFirstCards(spots);
      _open
        ..clear()
        ..addAll(kinLevelOpen(spots, KinLevel.leaders));
      // 기억한 접힘(기본 = 모두 접힘과 다른 마디)을 되살린다.
      final memory = _memory;
      if (memory != null) {
        final flipped = memory.read(ctx.uid);
        if (flipped.isNotEmpty) {
          for (final s in _skels.values) {
            final base = _open[s.key];
            if (base != null) _open[s.key] = kinFoldApply(s, base, flipped);
          }
        }
      }
      _reach.clear();
      for (var m = 0; m < _leaders.length; m++) {
        _reach[m] = kinLeaderReach(spots, m);
      }
      _ready = true;
      setState(_rebuild);
      _takeFocus();
    } finally {
      if (!_loadedDone.isCompleted) _loadedDone.complete();
    }
  }

  KinFoldMemory? get _memory {
    final v = ctx.slot('kinFold').value;
    return v is KinFoldMemory ? v : null;
  }

  /// 칸 창의 `승계표에서 보기`로 왔으면 그 카드를 펼쳐 데려간다.
  void _takeFocus() {
    final slot = ctx.slot(kinFocusSlot);
    final want = slot.value;
    if (want is! Map || want['uid'] != ctx.uid) return;
    slot.value = null;
    final cell = '${want['cell'] ?? ''}';
    final m = cell.startsWith('leader:') ? int.tryParse(cell.substring(7)) ?? -1 : -1;
    if (m < 0 || m >= _leaders.length) return;
    final spot = _spots[_first[m]];
    final s = spot.skel;
    if (s != null && spot.at >= 0) {
      _open[s.key]![spot.at] = 1;
      _rebuild();
      _save();
    }
    final i = _items.indexWhere((it) => it.k == _K.card && it.m == m);
    if (i >= 0) {
      _cursor = i;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(i, animate: false));
    }
  }

  /// 줄 규칙([kinRows]) → 이음매를 끼운 목록 · 줄 위치의 누적합.
  void _rebuild() {
    final rows = _ready ? kinRows(_spots, _open) : _leaderOnlyRows();
    final items = <_Item>[];
    var owner = -1;
    for (var r = 0; r < rows.length; r += 3) {
      final kind = rows[r], a = rows[r + 1], d = rows[r + 2];
      if (kind == kKinRowLeader) {
        if (a > 0) items.add(_Item(_K.seam, m: a, key: 'S$a'));
        items.add(_Item(_K.card, m: a, key: _leaderKey(a)));
        owner = a;
      } else if (kind == kKinRowPerson) {
        final s = _spots[owner].skel!;
        items.add(_Item(_K.person, j: a, depth: d, owner: owner, key: s.keys[a]));
      } else {
        items.add(_Item(_K.skip, m: a, depth: d, owner: owner, key: 'K$owner>$a'));
      }
    }
    final tops = Float64List(items.length + 1);
    for (var i = 0; i < items.length; i++) {
      tops[i + 1] = tops[i] + items[i].extent;
    }
    _items = items;
    _tops = tops;
    if (_cursor >= items.length) _cursor = items.length - 1;
  }

  Int32List _leaderOnlyRows() => Int32List.fromList([
    for (var m = 0; m < _leaders.length; m++) ...[kKinRowLeader, m, 0],
  ]);

  String _leaderKey(int m) => 'c:${ctx.uid}|leader:$m';

  /// 그 줄의 뼈대(사람 줄은 그 줄이 든 카드의 뼈대).
  KinSkeleton? _skelOf(_Item it) => it.k == _K.card ? _spots[it.m].skel : (it.owner >= 0 ? _spots[it.owner].skel : null);

  /// 다음 카드가 있는 줄인가(왼쪽 선이 그 줄을 지나 다음 이음매로 이어지는가).
  bool _through(_Item it) => it.owner >= 0 && it.owner < _leaders.length - 1;

  // ── 접고 펴기 ──────────────────────────────────────────────────────────────────────────────

  /// 그 줄을 접거나 편다 — 누른 줄은 화면에서 0px 움직인다.
  bool _toggle(int i, {bool all = false}) {
    if (i < 0 || i >= _items.length) return false;
    final it = _items[i];
    final s = _skelOf(it);
    if (s == null) return false;
    final at = it.k == _K.card ? _spots[it.m].at : it.j;
    if (it.k == _K.card && _first[it.m] != it.m) return false; // 복위 — 처음 카드에서만 편다
    if (it.k != _K.card && it.k != _K.person) return false;
    if (at < 0 || s.size[at] <= 1 || s.isStub(at)) {
      if (at >= 0 && s.isStub(at)) unawaited(_openStub(s, at, it.key));
      return false;
    }
    final open = _open[s.key]!;
    _relayout(() => kinToggle(s, open, at, all: all), anchor: it.key);
    return true;
  }

  /// 꼬투리(나눈 덩어리)를 펼치면 그 덩어리를 받아 합친 뒤 편다.
  Future<void> _openStub(KinSkeleton s, int at, String key) async {
    final next = await kinOpenStub(s, at, _fetch);
    if (!mounted || identical(next, s)) return;
    _replaceSkel(s, next);
    final i = _items.indexWhere((it) => it.key == key);
    final ns = next, j = ns.indexOfKey(key);
    if (j >= 0) {
      _relayout(() => _open[ns.key]![j] = 1, anchor: i >= 0 ? key : null);
    }
  }

  /// 합친 뼈대로 갈아 끼운다 — 접힘은 안정 열쇠로 옮긴다.
  void _replaceSkel(KinSkeleton old, KinSkeleton next) {
    final was = _open[old.key]!;
    final open = Uint8List(next.n);
    for (var i = 0; i < old.n; i++) {
      if (was[i] == 0) continue;
      final j = next.indexOfKey(old.keys[i]);
      if (j >= 0) open[j] = 1;
    }
    _skels[next.key] = next;
    _open[next.key] = open;
    _spots = [
      for (final sp in _spots)
        if (identical(sp.skel, old)) KinLeaderSpot(next, next.indexOfKey(old.keys[sp.at])) else sp,
    ];
    _reach.clear();
    for (var m = 0; m < _leaders.length; m++) {
      _reach[m] = kinLeaderReach(_spots, m);
    }
  }

  /// 수준(지도자만 · 자녀까지 · 파 이름까지 · 모두) — 맨 위에 보이던 줄을 제자리에 둔다.
  void _setLevel(KinLevel level) {
    if (!_ready) return;
    _level = level;
    final next = kinLevelOpen(_spots, level);
    _relayout(() {
      _open
        ..clear()
        ..addAll(next);
    }, anchor: _topKey());
  }

  String? _topKey() {
    if (!_scroll.hasClients || _items.isEmpty) return null;
    return _items[_indexAt(_scroll.offset)].key;
  }

  /// 줄 위치(px) → 그 자리의 줄 번호(이분 탐색).
  int _indexAt(double y) {
    var lo = 0, hi = _items.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return math.max(0, lo);
  }

  /// 접힘을 바꾸고 목록을 다시 세운다. [anchor] 줄은 화면에서 제자리(0px), 그 밖은 옮김 판으로 흐른다.
  void _relayout(VoidCallback change, {String? anchor}) {
    _stopScrollFlight();
    final prior = _shift;
    final hasView = _scroll.hasClients;
    final offset = hasView ? _scroll.offset : 0.0;
    final viewport = hasView ? _scroll.position.viewportDimension : 0.0;
    final before = <String, (double, _Item)>{};
    if (hasView) {
      for (var i = _indexAt(offset); i < _items.length && _tops[i] < offset + viewport; i++) {
        before[_items[i].key] = (_tops[i] - offset, _items[i]);
      }
    }
    if (prior != null) {
      for (final entry in prior.items.entries) {
        before[entry.key] = (prior.positions[entry.key]!.value - offset + prior.scrollOrigin, entry.value);
      }
    }
    final anchorY = anchor == null
        ? null
        : (() {
            final i = _items.indexWhere((it) => it.key == anchor);
            return i < 0 ? null : before[anchor]?.$1 ?? _tops[i] - offset;
          })();
    final oldCursorKey = _cursor >= 0 && _cursor < _items.length ? _items[_cursor].key : null;

    change();
    _rebuild();
    _save();

    var nextOffset = offset;
    if (anchor != null && anchorY != null) {
      final i = _items.indexWhere((it) => it.key == anchor);
      if (i >= 0) nextOffset = _tops[i] - anchorY;
    }
    final maxOffset = math.max(0.0, _tops[_items.length] - viewport);
    nextOffset = nextOffset.clamp(0.0, maxOffset);
    if (oldCursorKey != null) {
      final c = _items.indexWhere((it) => it.key == oldCursorKey);
      if (c >= 0) _cursor = c;
    }

    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (hasView && !calm && before.isNotEmpty) {
      final after = <String, (double, _Item)>{};
      for (var i = _indexAt(nextOffset); i < _items.length && _tops[i] < nextOffset + viewport; i++) {
        after[_items[i].key] = (_tops[i] - nextOffset, _items[i]);
      }
      _shift = _Shift(before, after, prior, _shiftTick, scrollOrigin: nextOffset, anchor: anchor);
    } else {
      _shift = null;
    }
    prior?.dispose();
    setState(() {});
    if (hasView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(nextOffset.clamp(0.0, _scroll.position.maxScrollExtent));
      });
    }
  }

  /// 접힘 기억 — 기본(모두 접힘)과 다른 마디의 안정 열쇠만.
  void _save() {
    final memory = _memory;
    if (memory == null || !_ready) return;
    final keys = <String>[];
    for (final s in _skels.values) {
      final open = _open[s.key];
      if (open != null) keys.addAll(kinFoldDiff(s, open, Uint8List(s.n)));
    }
    memory.write(ctx.uid, keys);
  }

  void _scrollTo(int i, {bool animate = true}) {
    if (!_scroll.hasClients || i < 0 || i >= _items.length) return;
    final view = _scroll.position.viewportDimension;
    final want = (_tops[i] - view / 3).clamp(0.0, _scroll.position.maxScrollExtent);
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!animate || calm) {
      _stopScrollFlight();
      _scroll.jumpTo(want);
    } else {
      if (!_scrollFlying) _scrollFlight.jump(_scroll.offset);
      _scrollFlying = true;
      _scrollFlight.retarget(want);
    }
  }

  void _stopScrollFlight() {
    _scrollFlying = false;
    _scrollFlight.stop();
  }

  void _scrollTick() {
    if (!mounted || !_scrollFlying || !_scroll.hasClients) return;
    _scroll.jumpTo(_scrollFlight.value.clamp(0.0, _scroll.position.maxScrollExtent));
    if (!_scrollFlight.active) _scrollFlying = false;
  }

  void _scrollShift() {
    if (mounted && _shift != null) _shiftFrames.value++;
  }

  void _shiftTick() {
    if (!mounted) return;
    if (_shift != null && !_shift!.active) {
      _shift!.dispose();
      setState(() => _shift = null);
    } else {
      _shiftFrames.value++;
    }
  }

  // ── 창 열기 ───────────────────────────────────────────────────────────────────────────────

  void _openLeader(int m) {
    ctx.slot(kinBackSlot).value = KinBack(polity: ctx.uid, target: ctx.uid, cell: 'leader:$m');
    ctx.open(ctx.uid, cell: 'leader:$m');
  }

  void _openPerson(String key) {
    final t = kinPersonTarget(key);
    if (t == null) return;
    ctx.slot(kinBackSlot).value = KinBack(polity: ctx.uid, target: t.uid, cell: t.cell);
    ctx.open(t.uid, cell: t.cell);
  }

  void _openFamily(KinSkeleton s, String focus) {
    ctx.slot(familySlot).value = FamilyRequest(kin: s.root?.uid ?? s.key, focus: focus);
  }

  Future<void> _menu(Offset at, _Item it) async {
    final s = _skelOf(it);
    final key = it.k == _K.card ? (_spots[it.m].person ?? '') : it.key;
    await showTimelineMenu(context, [
      if (it.k == _K.card) MenuRow('칸 창 열기', onSelected: () => _openLeader(it.m)),
      if (it.k == _K.person && kinPersonTarget(key) != null) MenuRow('창 열기', onSelected: () => _openPerson(key)),
      if (s != null && key.isNotEmpty) MenuRow('세계표에서 보기', onSelected: () => _openFamily(s, key)),
    ], at: at);
  }

  // ── 손잡이(KinDriver) ─────────────────────────────────────────────────────────────────────

  @override
  String get kind => 'succession';

  @override
  Future<void> get loaded => _loadedDone.future;

  @override
  bool get ready => _ready;

  @override
  void expandAll() => _setLevel(KinLevel.all);

  @override
  void collapseAll() => _setLevel(KinLevel.leaders);

  @override
  List<String> get visible {
    if (!_scroll.hasClients) {
      return [
        for (final it in _items.take(50))
          if (it.k != _K.seam) it.key,
      ];
    }
    final offset = _scroll.offset, view = _scroll.position.viewportDimension;
    return [
      for (var i = _indexAt(offset); i < _items.length && _tops[i] < offset + view; i++)
        if (_items[i].k != _K.seam) _items[i].key,
    ];
  }

  @override
  bool toggle(String key) => _toggle(_items.indexWhere((it) => it.key == key));

  @override
  void panBy(double dx, double dy) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo((_scroll.offset + dy).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Future<bool> reveal(String key) async {
    await loaded;
    if (!mounted) return false;
    var i = _items.indexWhere((it) => it.key == key);
    if (i < 0) {
      // 그 사람을 품은 카드를 찾아 조상을 편다.
      for (var m = 0; m < _leaders.length; m++) {
        final spot = _spots[m];
        final s = spot.skel;
        if (s == null || _first[m] != m) continue;
        final j = s.indexOfKey(key);
        if (j < 0 || j < spot.at || j >= spot.at + s.size[spot.at]) continue;
        final open = _open[s.key]!;
        _relayout(() {
          open[spot.at] = 1;
          for (var p = s.par[j]; p > spot.at; p = s.par[p]) {
            open[p] = 1;
          }
        });
        i = _items.indexWhere((it) => it.key == key);
        break;
      }
    }
    if (i < 0) return false;
    setState(() => _cursor = i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(i));
    return true;
  }

  @override
  int get built => _builtRows.length;

  @override
  int get lines => 0;

  @override
  Rect? get area {
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // ── 키보드(ARIA tree — 3-6) ───────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_items.isEmpty) return KeyEventResult.ignored;
    final k = e.logicalKey;
    int step(int from, int dir) {
      var i = from;
      do {
        i += dir;
      } while (i >= 0 && i < _items.length && _items[i].k == _K.seam);
      return i.clamp(0, _items.length - 1);
    }

    void go(int i) {
      if (_items[i].k == _K.seam) return;
      setState(() => _cursor = i);
      _ensureVisible(i);
    }

    final cur = _cursor < 0 ? 0 : _cursor;
    if (k == LogicalKeyboardKey.arrowDown) {
      go(_cursor < 0 ? 0 : step(cur, 1));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      go(step(cur, -1));
    } else if (k == LogicalKeyboardKey.home) {
      go(0);
    } else if (k == LogicalKeyboardKey.end) {
      go(_items.lastIndexWhere((it) => it.k != _K.seam));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      if (!_isOpen(cur)) {
        _toggle(cur);
      } else if (cur + 1 < _items.length && _items[cur + 1].k != _K.seam && _items[cur + 1].k != _K.card) {
        go(cur + 1);
      }
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      if (_isOpen(cur)) {
        _toggle(cur);
      } else {
        final p = _parentRow(cur);
        if (p >= 0) go(p);
      }
    } else if (k == LogicalKeyboardKey.space) {
      _toggle(cur);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      final it = _items[cur];
      if (it.k == _K.card) _openLeader(it.m);
      if (it.k == _K.person) _openPerson(it.key);
      if (it.k == _K.skip) _jumpToLeader(it.m);
    } else if (e.character == '*') {
      _expandSiblings(cur);
    } else if (k == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored; // 창 닫기는 지금처럼(밖틀의 Esc)
    } else if (e.character != null && e.character!.trim().isNotEmpty && e.character!.length == 1) {
      final ch = e.character!;
      for (var n = 1; n <= _items.length; n++) {
        final i = (cur + n) % _items.length;
        if (_items[i].k != _K.seam && _rowName(_items[i]).startsWith(ch)) {
          go(i);
          break;
        }
      }
    } else {
      return KeyEventResult.ignored;
    }
    // 창에 초점이 있는 동안은 창의 키가 연표 전역 키보다 먼저다(넘기지 않는다).
    return KeyEventResult.handled;
  }

  void _ensureVisible(int i) {
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension, off = _scroll.offset;
    if (_tops[i] < off) {
      _scroll.jumpTo(_tops[i]);
    } else if (_tops[i + 1] > off + view - _G.fade) {
      _scroll.jumpTo(math.min(_scroll.position.maxScrollExtent, _tops[i + 1] - view + _G.fade));
    }
  }

  bool _isOpen(int i) {
    final it = _items[i];
    final s = _skelOf(it);
    if (s == null) return false;
    final at = it.k == _K.card ? _spots[it.m].at : it.j;
    if (at < 0 || (it.k != _K.card && it.k != _K.person)) return false;
    return _open[s.key]![at] != 0 && s.size[at] > 1;
  }

  int _parentRow(int i) {
    final it = _items[i];
    if (it.k == _K.card || it.k == _K.seam) return -1;
    for (var k = i - 1; k >= 0; k--) {
      final o = _items[k];
      if (o.k == _K.card && o.m == it.owner) return k;
      if (o.k == _K.person && o.owner == it.owner && o.depth == it.depth - 1) return k;
    }
    return -1;
  }

  void _expandSiblings(int i) {
    final it = _items[i];
    final s = _skelOf(it);
    if (s == null) return;
    if (it.k == _K.card) {
      _relayout(() {
        for (var m = 0; m < _leaders.length; m++) {
          final sp = _spots[m];
          if (sp.skel != null && sp.at >= 0 && _first[m] == m) _open[sp.skel!.key]![sp.at] = 1;
        }
      }, anchor: it.key);
      return;
    }
    final p = s.par[it.j];
    if (p < 0) return;
    final open = _open[s.key]!;
    _relayout(() {
      for (final c in s.children(p)) {
        open[c] = 1;
      }
    }, anchor: it.key);
  }

  void _jumpToLeader(int m) {
    final i = _items.indexWhere((it) => it.k == _K.card && it.m == m);
    if (i < 0) return;
    setState(() => _cursor = i);
    _scrollTo(i);
  }

  String _rowName(_Item it) => switch (it.k) {
    _K.card => detailString(_leaders[it.m], 'name'),
    _K.person => _skelOf(it)?.name[it.j] ?? '',
    _K.skip => detailString(_leaders[it.m], 'name'),
    _K.seam => '',
  };

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => DetailShell(
    onClose: ctx.close,
    badges: _head(),
    footGap: 6,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 0), child: _top()),
        Expanded(child: _list()),
      ],
    ),
    foot: [
      DetailSmallButton('◀ 나라 상세', pad: 9, onTap: () => ctx.open(ctx.uid)),
      DetailSmallButton('모두 펼치기', pad: 9, onTap: _ready ? expandAll : null),
      DetailSmallButton('모두 접기', pad: 9, onTap: _ready ? collapseAll : null),
      Builder(builder: (context) => DetailSmallButton('수준 ▾', pad: 9, onTap: _ready ? () => _levelMenu(context) : null)),
      DetailSmallButton('닫기', pad: 9, onTap: ctx.close),
    ],
  );

  static const _levelNames = {KinLevel.leaders: '지도자만', KinLevel.children: '자녀까지', KinLevel.branches: '파 이름까지', KinLevel.all: '모두'};

  void _levelMenu(BuildContext button) {
    final box = button.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height));
    unawaited(showTimelineMenu(context, [for (final e in _levelNames.entries) MenuRow(e.value, checked: e.key == _level, onSelected: () => _setLevel(e.key))], at: at));
  }

  /// 머리 칩(`구분 › 민족 › 국가 이름 · 꼬리표`) — 기록에 `x_head`가 없으면(옛 기록) 나라 이름 배지 하나.
  List<Widget> _head() {
    final chips = KinChip.read(x['x_head']);
    if (chips.isEmpty) return [DetailBadge(detailString(x, 'name'), color: _color)];
    return [KinHead(chips, onOpen: (c) => kinChipOpen(ctx.bus, c), colorOf: (c) => c.uid == ctx.uid ? _color : null)];
  }

  /// 제목 · 한 줄 안내 · 범례(목록 위에 붙어 있다 — 목록만 민다).
  Widget _top() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DetailTitle(detailString(x, 'name')),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('지도자 ${_leaders.length}', style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text2)),
      ),
      KinLegend(const [('seam:5', '세습 · 추대'), ('seam:3', '선양'), ('seam:1', '찬탈 · 정변'), ('seam:2', '관계 · 방식 미상'), ('res', '복위(같은 사람)')], ink: _ink),
      const SizedBox(height: 14),
    ],
  );

  Widget _list() {
    final list = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CustomScrollView(
        key: _listKey,
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, _G.fade),
            sliver: SliverVariedExtentList.builder(
              itemCount: _items.length,
              itemExtentBuilder: (i, _) => i < _items.length ? _items[i].extent : null,
              itemBuilder: (context, i) => i < _items.length ? _RowHost(key: ValueKey(_items[i].key), built: _builtRows, child: _row(_items[i], i)) : null,
            ),
          ),
        ],
      ),
    );
    final shift = _shift;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        label: '승계표',
        child: Listener(
          onPointerDown: (_) => _stopScrollFlight(),
          onPointerSignal: (_) => _stopScrollFlight(),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.black, Colors.black, Colors.transparent],
              stops: [0, rect.height <= _G.fade ? 0 : (rect.height - _G.fade) / rect.height, 1],
            ).createShader(rect),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(opacity: shift == null ? 1 : 0, child: list),
                ),
                if (shift != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRect(
                        child: AnimatedBuilder(animation: _shiftFrames, builder: (context, _) => _shiftStack(shift)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 옮김 판 — 보이는 줄(앞 ∪ 뒤)만 공통 자리·짙기 스프링으로 옮긴다.
  Widget _shiftStack(_Shift shift) {
    final kids = <Widget>[];
    final scrollDelta = (_scroll.hasClients ? _scroll.offset : shift.scrollOrigin) - shift.scrollOrigin;
    for (final e in shift.items.entries) {
      kids.add(_placed(shift.positions[e.key]!.value - scrollDelta, e.value, shift.opacity[e.key]!.value.clamp(0.0, 1.0)));
    }
    return Stack(clipBehavior: Clip.hardEdge, children: kids);
  }

  Widget _placed(double y, _Item it, double opacity) {
    final i = _items.indexWhere((o) => o.key == it.key);
    return Positioned(
      top: y,
      left: 18,
      right: 18,
      height: it.extent,
      child: Opacity(opacity: opacity, child: _row(it, i)),
    );
  }

  /// 줄 하나. [i]는 지금 목록의 번호(사라지는 줄이면 -1).
  Widget _row(_Item it, int i) {
    final focused = i >= 0 && i == _cursor;
    final Widget body = switch (it.k) {
      _K.card => _card(it),
      _K.seam => _seam(it),
      _K.person => _person(it),
      _K.skip => _skip(it),
    };
    final loops = i < 0 ? const <_Loop>[] : _loopsAt(i);
    return CustomPaint(
      painter: _RowPainter(
        through: it.k == _K.person || it.k == _K.skip ? (_through(it) ? _nextLine(it.owner) : null) : null,
        seam: it.k == _K.seam ? SeamLine.of(_lin(it.m)) : null,
        loops: loops,
        ink: _ink,
        focused: focused,
      ),
      child: body,
    );
  }

  /// 펼친 줄을 지나는 선의 무늬 — 다음 이음매가 비움이면 옅은 1px, 아니면 실선.
  int _nextLine(int owner) => SeamLine.of(_lin(owner + 1)) == SeamLine.blank ? SeamLine.blank : SeamLine.solid;

  /// 복위 고리 — 같은 사람의 처음 카드와 다시 오른 카드를 오른쪽 여백에서 잇는다. 그 사이 줄마다 제 토막만 그린다.
  List<_Loop> _loopsAt(int i) {
    final out = <_Loop>[];
    for (var m = 0; m < _leaders.length; m++) {
      final f = _first[m];
      if (f == m) continue;
      final a = _cardIndex(f), b = _cardIndex(m);
      if (a < 0 || b < 0 || i < a || i > b) continue;
      out.add(i == a ? _Loop.start : (i == b ? _Loop.end : _Loop.mid));
    }
    return out;
  }

  int _cardIndex(int m) {
    // 카드 줄은 지도자 차례대로 놓이므로 이분 탐색할 수도 있지만, 보이는 줄(≤ 50)마다 지도자 수만큼이라 그대로 둔다.
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].k == _K.card && _items[i].m == m) return i;
    }
    return -1;
  }

  String _ordinal(int m) {
    final o = detailNum(_leaders[m], 'ordinal');
    return o == null ? '' : '${o.toInt()}대';
  }

  /// 글 안에서 지도자를 가리키는 말 — 대수가 없으면 이름(웹 ordText와 같다).
  String _ordinalOrName(int m) {
    final o = _ordinal(m);
    return o.isNotEmpty ? o : detailString(_leaders[m], 'name');
  }

  String _years(Map<String, dynamic> c) {
    final s = detailNum(c, 'start')?.toDouble();
    final e = (detailNum(c, 'end') ?? detailNum(c, 'endY'))?.toDouble();
    String y(double? t) => t == null ? '' : kinYear(civilAt(t).year);
    if (s == null && e == null) return '';
    return '${y(s)} ~ ${y(e)}';
  }

  /// 지도자 카드(34px) — 대수 · 이름 · `다시` · 다른 나라 칩 · `후손 n ▸` · 기간.
  Widget _card(_Item it) {
    final m = it.m;
    final c = _leaders[m];
    final again = _first[m] != m;
    final reach = _reach[m] ?? 0;
    final spot = _spots[m];
    final open = !again && spot.skel != null && spot.at >= 0 && _open[spot.skel!.key]![spot.at] != 0;
    final elsewhere = detailList(_lin(m) ?? const {}, 'elsewhere');
    return Padding(
      padding: const EdgeInsets.only(right: _G.loop),
      child: DetailPressable(
        onTap: () => _openLeader(m),
        radius: 10,
        padding: EdgeInsets.zero,
        semantics: '${_ordinal(m)} ${detailString(c, 'name')}',
        child: GestureDetector(
          onSecondaryTapDown: (d) => _menu(d.globalPosition, it),
          onLongPressStart: (d) => _menu(d.globalPosition, it),
          child: Container(
            height: _G.card,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: KinUi.tint(_color, .20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KinUi.fade(_color, .52)),
            ),
            // 웹 `.kv-row.is-L`과 같은 차례: 대수 · 이름(폭의 45%까지) · 다시 · 다른 곳 칩 … 기간(오른쪽 끝 쪽) · 알약(맨 끝).
            // 좁으면 이름이 먼저 줄고(…), 칩은 통째로 들어갈 자리가 없으면 숨는다 — 카드 밖으로 나가지 않는다(겹침 · 돌출 금지).
            child: ClipRect(
              child: CustomMultiChildLayout(
                delegate: _CardLayout(chips: (again ? 1 : 0) + math.min<int>(elsewhere.length, 2) + (elsewhere.length > 2 ? 1 : 0)),
                children: [
                  LayoutId(
                    id: 'ord',
                    child: Text(
                      _ordinal(m),
                      style: const TextStyle(fontSize: 11, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  LayoutId(
                    id: 'name',
                    child: Text(
                      detailString(c, 'name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Ui.text),
                    ),
                  ),
                  ...[
                    if (again) _tag('다시', KinUi.tint(_color, .30)),
                    for (final q in elsewhere.take(2)) _tag(detailString(q, 'polity'), Ui.surface2, onTap: () => ctx.open(detailString(q, 'uid'), cell: detailString(q, 'ref'))),
                    if (elsewhere.length > 2) _tag('+${elsewhere.length - 2}', Ui.surface2),
                  ].indexed.map((e) => LayoutId(id: 'chip${e.$1}', child: e.$2)),
                  LayoutId(
                    id: 'years',
                    child: Text(
                      _years(c),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 12, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  if (again)
                    LayoutId(
                      id: 'pill',
                      child: _pill('${_ordinalOrName(_first[m])}에서', onTap: () => _jumpToLeader(_first[m])),
                    )
                  else if (reach > 0)
                    LayoutId(
                      id: 'pill',
                      child: _pill('후손 $reach ${open ? '▾' : '▸'}', onTap: () => _toggle(_items.indexOf(it))),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color bg, {VoidCallback? onTap}) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        maxLines: 1,
        style: const TextStyle(fontSize: 10.5, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text2),
      ),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: body),
    );
  }

  Widget _pill(String text, {required VoidCallback onTap, Color? dot}) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Semantics(
      button: true,
      label: text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: KinUi.fade(Ui.surface, .85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Ui.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: const TextStyle(fontSize: 10.5, height: 1.6, fontWeight: FontWeight.w600, color: Ui.text2),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  static final _unknownWords = RegExp('관계 미상|방식 미상|전임자 미상');

  /// 이음매(22px) — 선은 왼쪽([_RowPainter]), 글은 46px에서(관계는 굵게 · 미상은 옅게).
  Widget _seam(_Item it) {
    final a = _lin(it.m);
    final line = SeamLine.of(a);
    final spans = <InlineSpan>[];
    if (line != SeamLine.blank && a != null) {
      var text = detailString(a, 'seam');
      if (text.isEmpty) {
        // 옛 기록(이음매 글이 없음) — 실린 관계 · 방식 글만 잇는다(글은 웹이 지은 낱말 그대로).
        bool on(String k) => a[k] == 1 || a[k] == true;
        final kin = detailString(a, 'kin').isNotEmpty ? detailString(a, 'kin') : (on('kinUnknown') ? '관계 미상' : '');
        final how = detailString(a, 'how').isNotEmpty ? detailString(a, 'how') : (on('howUnknown') ? '방식 미상' : '');
        text = [kin, how].where((s) => s.isNotEmpty).join(' · ');
      }
      // '관계 미상' · '방식 미상' · '전임자 미상'은 옅게(웹 `.kv-row.is-S i`와 같은 text-3).
      void plain(String s) {
        var i = 0;
        for (final w in _unknownWords.allMatches(s)) {
          if (w.start > i) spans.add(TextSpan(text: s.substring(i, w.start)));
          spans.add(
            TextSpan(
              text: w[0],
              style: const TextStyle(color: Ui.text3),
            ),
          );
          i = w.end;
        }
        if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
      }

      final kin = detailString(a, 'kin');
      final at = kin.isEmpty ? -1 : text.indexOf(kin);
      if (at >= 0) {
        plain(text.substring(0, at));
        spans.add(
          TextSpan(
            text: kin,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Ui.text),
          ),
        );
        plain(text.substring(at + kin.length));
      } else {
        plain(text);
      }
      // 다시 오른 지도자 — 이음매 글이 이미 '같은 사람'을 말하면 겹쳐 쓰지 않는다(웹 seamHTML과 같다).
      final f = _first[it.m];
      if (f != it.m && !text.contains('같은 사람')) {
        spans.add(
          TextSpan(
            text: ' — ${_ordinalOrName(f)}와 같은 사람',
            style: const TextStyle(color: Ui.text3),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(left: _G.seamText, right: _G.loop),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(children: spans),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text2),
        ),
      ),
    );
  }

  /// 사람 줄(28px) — `▸/▾` · 이름 · 곁글 · 파조면 `● ○○파 · n명 ▸`.
  Widget _person(_Item it) {
    final s = _skelOf(it)!;
    final j = it.j;
    final bits = s.bits[j];
    final unknown = bits & kKinUnknown != 0;
    final member = bits & kKinMember != 0;
    final kids = s.size[j] > 1 || s.isStub(j);
    final open = kids && _open[s.key]![j] != 0 && !s.isStub(j);
    final deeper = kinRowDeeper(it.depth);
    final founder = bits & kKinFounder != 0 ? _branchOf(s, j) : null;
    final count = s.isStub(j) ? (s.stubs[j]?.n ?? 1) : s.size[j];
    final nameColor = bits & kKinMissing != 0 || !member ? Ui.text3 : Ui.text;
    final i = _items.indexOf(it);
    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(d.globalPosition, it),
      onLongPressStart: (d) => _menu(d.globalPosition, it),
      child: DetailPressable(
        onTap: kinPersonTarget(s.keys[j]) == null ? null : () => _openPerson(s.keys[j]),
        radius: 6,
        padding: EdgeInsets.only(left: _G.rowText + kinRowIndent(it.depth) - 14, right: _G.loop),
        semantics: unknown ? '이름 미상' : s.name[j],
        child: SizedBox(
          height: _G.row,
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: kids
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggle(i),
                          child: Text(open ? '▾' : '▸', style: const TextStyle(fontSize: 10, color: Ui.text3)),
                        ),
                      )
                    : null,
              ),
              if (deeper > 0) Text('+$deeper대 ', style: const TextStyle(fontSize: 11, color: Ui.text3)),
              if (unknown) ...[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: KinUi.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: KinUi.fade(Ui.text3, .9), width: 1.5),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('이름 미상', style: TextStyle(fontSize: 12, color: Ui.text3)),
              ] else
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: s.name[j],
                      children: [
                        if (s.sub[j].isNotEmpty)
                          TextSpan(
                            text: '  ${s.sub[j]}',
                            style: const TextStyle(fontSize: 11.5, color: Ui.text3),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(fontSize: 13, color: nameColor),
                  ),
                ),
              if (founder != null) ...[
                const SizedBox(width: 6),
                _pill('${founder.name} · $count명${kids ? (open ? ' ▾' : ' ▸') : ''}', dot: detailColor(founder.color), onTap: () => _toggle(i, all: true)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  KinBranch? _branchOf(KinSkeleton s, int j) {
    final full = s.fullIndexOf(j);
    for (final b in s.branches) {
      if (b.at == full) return b;
    }
    final b = s.branch[j];
    return b >= 0 && b < s.branches.length ? s.branches[b] : null;
  }

  /// 건너뛰기 줄 — `→ n대 ○○`(누르면 그 카드로).
  Widget _skip(_Item it) {
    final m = it.m;
    return DetailPressable(
      onTap: () => _jumpToLeader(m),
      radius: 6,
      padding: EdgeInsets.only(left: _G.rowText + kinRowIndent(it.depth), right: _G.loop),
      semantics: '${_ordinal(m)} ${detailString(_leaders[m], 'name')}',
      child: SizedBox(
        height: _G.row,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('→ ${_ordinal(m)} ${detailString(_leaders[m], 'name')}'.replaceAll('  ', ' '), style: const TextStyle(fontSize: 12.5, color: Ui.text2)),
        ),
      ),
    );
  }
}

/// 지어 둔 줄 위젯을 세는 껍데기(그리는 수 — 손잡이의 `built` · 검사의 '보이지 않는 줄은 짓지 않음').
class _RowHost extends StatefulWidget {
  const _RowHost({super.key, required this.built, required this.child});
  final Set<Object> built;
  final Widget child;

  @override
  State<_RowHost> createState() => _RowHostState();
}

class _RowHostState extends State<_RowHost> {
  @override
  void initState() {
    super.initState();
    widget.built.add(this);
  }

  @override
  void dispose() {
    widget.built.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 옮김 판의 앞 · 뒤 — 줄 열쇠 → (화면 y, 줄).
class _Shift {
  _Shift(Map<String, (double, _Item)> before, Map<String, (double, _Item)> after, _Shift? prior, VoidCallback changed, {required this.scrollOrigin, String? anchor}) {
    for (final key in {...before.keys, ...after.keys}) {
      final from = before[key], to = after[key], leaving = to == null;
      items[key] = (to ?? from)!.$2;
      final position = MotionSpring((from ?? to)!.$1, token: leaving ? MotionToken.snap : MotionToken.move, epsilon: .02, maxOvershoot: 4);
      positions[key] = position;
      MotionStage.instance.attach(position, changed);
      position.retarget((to ?? from)!.$1);
      if (key != anchor) {
        final old = prior?.positions[key];
        if (old != null) position.kick(old.velocity);
      }
      final alpha = MotionSpring(prior?.opacity[key]?.value ?? (from == null ? 0 : 1), token: leaving ? MotionToken.exit : MotionToken.enter, maxOvershoot: 0);
      opacity[key] = alpha;
      MotionStage.instance.attach(alpha, changed);
      alpha.retarget(leaving ? 0 : 1);
      if (prior?.opacity[key] case final old?) alpha.kick(old.velocity);
    }
  }
  final items = <String, _Item>{};
  final double scrollOrigin;
  final positions = <String, MotionSpring>{}, opacity = <String, MotionSpring>{};
  bool get active => positions.values.any((s) => s.active) || opacity.values.any((s) => s.active);
  void dispose() {
    for (final spring in [...positions.values, ...opacity.values]) {
      MotionStage.instance.detach(spring);
    }
  }
}

enum _Loop { start, mid, end }

/// 줄 하나의 선 — 왼쪽(30px) 이음매 무늬 · 펼친 줄을 지나는 선, 오른쪽 여백의 복위 고리 토막, 키보드 초점 테.
/// 지도자 카드 한 줄의 자리 — 오른쪽(알약 · 기간)을 먼저 놓고, 남은 폭에 대수 · 이름(카드 폭의 45%까지) · 칩을 놓는다.
/// 칩은 통째로 들어가는 것까지만 보이고 나머지는 카드 밖(잘림)으로 보낸다.
class _CardLayout extends MultiChildLayoutDelegate {
  _CardLayout({required this.chips});
  final int chips;
  static const _gap = 8.0, _chipGap = 6.0, _ordMin = 30.0;

  @override
  void performLayout(Size size) {
    final h = size.height;
    double mid(Size s) => (h - s.height) / 2;
    final loose = BoxConstraints.loose(size);
    final ord = layoutChild('ord', loose);
    positionChild('ord', Offset(0, mid(ord)));
    final left = math.max(_ordMin, ord.width) + _gap;
    var right = size.width;
    if (hasChild('pill')) {
      final p = layoutChild('pill', loose);
      right -= p.width;
      positionChild('pill', Offset(right, mid(p)));
      right -= _gap;
    }
    final y = layoutChild('years', BoxConstraints(maxWidth: math.max(0, right - left), maxHeight: h));
    right -= y.width;
    positionChild('years', Offset(right, mid(y)));
    right -= _gap;
    final n = layoutChild('name', BoxConstraints(maxWidth: math.max(0, math.min(right - left, size.width * .45)), maxHeight: h));
    positionChild('name', Offset(left, mid(n)));
    var x = left + n.width;
    var shown = true;
    for (var i = 0; i < chips; i++) {
      final c = layoutChild('chip$i', loose);
      shown = shown && x + _chipGap + c.width <= right;
      if (shown) {
        positionChild('chip$i', Offset(x + _chipGap, mid(c)));
        x += _chipGap + c.width;
      } else {
        positionChild('chip$i', Offset(size.width + 100, 0));
      }
    }
  }

  @override
  bool shouldRelayout(_CardLayout old) => old.chips != chips;
}

class _RowPainter extends CustomPainter {
  _RowPainter({this.through, this.seam, this.loops = const [], required this.ink, this.focused = false});

  /// 펼친 줄을 지나는 선의 무늬(실선 · 비움) — null이면 없음.
  final int? through;

  /// 이음매의 선 갈래 — null이면 이음매 줄이 아님.
  final int? seam;
  final List<_Loop> loops;
  final Color ink;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    if (seam != null) paintSeamLine(canvas, seam!, ink, c: _G.line, a: 0, b: size.height);
    if (through != null) paintSeamLine(canvas, through!, ink, c: _G.line, a: 0, b: size.height);
    if (loops.isNotEmpty) {
      final p = Paint()
        ..color = ink
        ..strokeWidth = KinUi.stroke
        ..style = PaintingStyle.stroke;
      final x0 = size.width - _G.loop + 2, x1 = size.width - _G.loop + 20, mid = _G.card / 2;
      for (final loop in loops) {
        switch (loop) {
          case _Loop.start:
            canvas.drawPath(
              Path()
                ..moveTo(x0, mid)
                ..lineTo(x1 - 8, mid)
                ..quadraticBezierTo(x1, mid, x1, mid + 8)
                ..lineTo(x1, size.height),
              p,
            );
          case _Loop.mid:
            canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), p);
          case _Loop.end:
            canvas.drawPath(
              Path()
                ..moveTo(x1, 0)
                ..lineTo(x1, mid - 8)
                ..quadraticBezierTo(x1, mid, x1 - 8, mid)
                ..lineTo(x0, mid),
              p,
            );
            // 화살 끝 — 시간이 흐르는 쪽으로, 다시 오른 카드를 가리킨다(건의 8의 5번 A · 2026-10-13: 예전에는 처음 오른 카드 쪽).
            canvas.drawPath(
              Path()
                ..moveTo(x0 + 5, mid - 4)
                ..lineTo(x0, mid)
                ..lineTo(x0 + 5, mid + 4),
              p,
            );
        }
      }
    }
    if (focused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(1, 1, size.width - _G.loop - 2, size.height - 2), const Radius.circular(8)),
        Paint()
          ..color = Ui.accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RowPainter old) =>
      old.through != through || old.seam != seam || old.ink != ink || old.focused != focused || old.loops.length != loops.length || !_same(old.loops, loops);

  static bool _same(List<_Loop> a, List<_Loop> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
