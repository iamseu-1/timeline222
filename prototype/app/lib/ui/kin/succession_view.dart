import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../motion.dart';
import '../../motion_spring.dart';
import '../../shell/look.dart';
import '../../shell/sheet_look.dart';
import '../../shell/sheet_parts.dart';
import '../app_memory.dart' show KinFoldMemory;
import '../context_menu.dart' show MenuRow, showTimelineMenu;
import '../date_text.dart' show civilAt;
import '../detail_shell.dart';
import 'family_window.dart';
import 'kin_head.dart';
import 'kin_layout.dart';
import 'kin_record.dart';
import 'kin_rows.dart';
import 'succession_look.dart';
import 'succession_wide.dart' show SuccWideLook, SuccessionDrawer, openSuccessionWide;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  승계표 창 — D1 결정 1 A(세로 한 줄 · 상세 창 자리) · 4 B · 8 A + 감독 덧붙임(접고 펴기 · 파 · 머리 태그)
//  설계: `docs/설계-10건/1-2-계승과-가문-확정.md` 3절 · 8-3 · 8-4. 목업 그림 `.claude/research/10건/D1/d1-1-a.png` · `d1-8-a.png`.
//  그리는 꼴(리메이크 4단계 틀의 시트와 창 걸음 6 · 감독 고름 G5 #9 '서고로 다시 그림' — 좁은 창은 예전처럼 위에서 아래로):
//  지도자 카드 = 그림판 꼬리표를 줄인 이름띠(머리 24 + 흰 층 16 = 40) · 승계 = 앞 꼬리표의 꼬리 마름모 → 다음 꼬리표의 구멍으로 곧게 내려가는 실 ·
//  이음매 글 = 실 옆 열쇠표 · 펼친 사람 줄 = 들여쓴 흰 사람 띠 · 머리 = 제목 꼬리표 + 승계표 전용 범례 · 바닥 단추 = 흰 이름 종이.
//  그리개는 `succession_look.dart`(넓은 창 — 화면 아래 서랍 — 도 함께 씀). 기능 · 줄 규칙 · 기억 · 움직임 · 키보드는 그대로.
//  넓은 창(`succession_wide.dart` — 걸음 7): 서랍 층이 붙어 있고 휴대폰이 아니며 창 폭이 860 이상이면 바닥에 '넓게'(닫기 앞 · 여섯이면
//  글 앞뒤 7로 한 줄) — 누르면 그 정권의 서랍이 열리고 상세 칸은 나라 상세로. 서랍의 '수준 ▾'에서 다른 수준을 고르면 [kinLevelSlot]으로 이 창을 연다.
//
//  ◆ 여는 길: 나라 상세 '지도자' 상자의 `승계표` 단추 · 칸 창의 `승계표에서 보기` → `bus.select(정권 uid, cell: 'succession')`.
//  ◆ 읽는 것(정권 기록): leaders(칸 목록 — 시작 순) · color · x_head(머리 칩) · x_lineage['leader:i'] =
//      { kin · how(글) · kinUnknown · howUnknown · line(0~5) · seam(이음매 글 — 웹이 지은 그대로) · kinAt: [뿌리 뼈대 uid, 한 벌 번호] · elsewhere }.
//    뼈대(갈래 `kin` 기록)는 창을 열 때 뼈대마다 `entity` 한 번만 받고 **작업자 isolate에서 푼다**([decodeKin]) —
//    이 파일은 JSON을 풀지 않는다. 지도자가 나눈 덩어리 안이면 그 덩어리를 받아 합친다([kinReveal]).
//  ◆ 줄 규칙은 [kinRows](웹 `HT.successionRows`와 같은 규칙 — D1-N1). 이 파일은 그 줄 사이에 이음매(22px)를 끼워
//    `꼬리표 40 · (펼친 줄 28 …) · 이음매 22 · 다음 꼬리표` 차례로 세운다(펼친 줄은 카드와 이음매 사이 — 3-4 '이음매와의 자리').
//    줄 높이는 `kin_rows.dart`의 값(측정 대본 · 검사가 같은 값으로 전체 높이를 셈).
//  ◆ 보이는 줄만 짓는다(`SliverVariedExtentList` — 줄 높이 누적합). 접고 펼 때 누른 줄은 0px 움직이고, 아래 줄은 옛 y → 새 y로
//    공통 move 스프링의 옮김 판을 띄운 뒤 목록으로 갈아 끼운다. 새 줄과 사라지는 줄은 in/out으로 옅어지며 재입력은 현재 자리와 속도를 잇는다.
//  ◆ 접힘은 보기 설정 — `bus.slot('kinFold')`의 [KinFoldMemory]에 정권 uid 열쇠로 기본과 다른 마디의 안정 열쇠만 남긴다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 칸 창의 `승계표에서 보기`가 실어 보내는 '그 카드로 데려가 펼친 채'(`{'uid': 정권 uid, 'cell': 'leader:3'}`).
const kinFocusSlot = 'kinFocus';

/// 계보 창에서 다른 창(인물 · 칸)을 열었을 때 그 창 바닥에 `◀ 승계표`를 붙이는 표(그 창이 [target]일 때만).
const kinBackSlot = 'kinBack';

/// 넓은 창(화면 아래 서랍)의 '수준 ▾'에서 지도자만 말고 다른 수준을 고르면 그 수준으로 이 창을 연다 — `{'uid': 정권 uid, 'level': KinLevel}`
/// (가로 꼴에는 자녀 · 파 그림이 없어 수준은 좁은 창이 맡는다).
const kinLevelSlot = 'kinLevel';

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
//  치수(1배 — 줄 높이는 `kin_rows.dart`, 그 밖은 `succession_look.dart`의 [SuccLook])
// ────────────────────────────────────────────────────────────────────────────────────────────

abstract final class _G {
  /// 지도자 꼬리표 40 · 이음매 22 · 사람 줄(건너뛰기 줄도) 28.
  static const card = kKinRowCard * 1.0, seam = kKinRowSeam * 1.0, row = kKinRowLine * 1.0;

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
      _takeLevel();
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

  /// 넓은 창의 '수준 ▾'에서 지도자만 말고 다른 수준을 골라 왔으면 그 수준으로 편다.
  void _takeLevel() {
    final slot = ctx.slot(kinLevelSlot);
    final want = slot.value;
    if (want is! Map || want['uid'] != ctx.uid) return;
    slot.value = null;
    final level = want['level'];
    if (level is KinLevel) _setLevel(level);
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
  Widget build(BuildContext context) {
    // 넓은 창(화면 아래 서랍 — succession_wide.dart)을 열 수 있으면 바닥에 '넓게'(서랍 층이 붙어 있고 휴대폰이 아니며 창 폭이 860 이상일 때만).
    // 단추가 여섯이면 글 앞뒤를 7로 좁혀(다듬기 판 `paper`의 7) 상세 칸 안 폭 344에 한 줄로 선다.
    final wide = SuccessionDrawer.canOpen(context, ctx.bus);
    final pad = wide ? SuccWideLook.buttonPad : SheetLook.buttonPad;
    return DetailShell(
      onClose: ctx.close,
      badges: _head(),
      // 흰 이름 종이 다섯(글 12 굵게 · 앞뒤 11)이 상세 칸 안 폭 344에 한 줄로 서도록 사이 4.
      footGap: 4,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 0), child: _top()),
          Expanded(child: _list()),
        ],
      ),
      // 바닥 단추 = 흰 이름 종이(일 · 차례 · 글은 그대로 · '넓게'는 닫기 앞).
      foot: [
        SheetPaperButton(label: '◀ 나라 상세', onTap: () => ctx.open(ctx.uid), pad: pad),
        SheetPaperButton(label: '모두 펼치기', onTap: _ready ? expandAll : null, pad: pad),
        SheetPaperButton(label: '모두 접기', onTap: _ready ? collapseAll : null, pad: pad),
        Builder(builder: (context) => SheetPaperButton(label: '수준 ▾', onTap: _ready ? () => _levelMenu(context) : null, pad: pad)),
        if (wide) SheetPaperButton(label: '넓게', onTap: _openWide, pad: pad, hint: '화면 아래 서랍에 가로로 이어지는 승계표'),
        SheetPaperButton(label: '닫기', onTap: ctx.close, pad: pad),
      ],
    );
  }

  /// '넓게' — 이 정권의 넓은 창(화면 아래 서랍)을 열고 상세 칸은 나라 상세로.
  void _openWide() {
    openSuccessionWide(ctx.bus, ctx.uid);
    ctx.open(ctx.uid);
  }

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

  /// 승계표 전용 범례 — 실 갈래(이음매 여섯 가운데 글이 있는 다섯 · 비움은 글 없는 옅은 실) · 복위 고리 · 열쇠표 견본.
  static final _legend = <(String, String)>[
    (SuccLegendKind.seam(SeamLine.solid), '세습 · 추대'),
    (SuccLegendKind.seam(SeamLine.abdicate), '선양'),
    (SuccLegendKind.seam(SeamLine.usurp), '찬탈 · 정변'),
    (SuccLegendKind.seam(SeamLine.unknown), '관계 · 방식 미상'),
    (SuccLegendKind.restore, '복위(같은 사람)'),
    (SuccLegendKind.key, '관계 · 방식'),
  ];

  /// 제목 꼬리표(이름 · '지도자 n') · 범례 · 가름 금(목록 위에 붙어 있다 — 목록만 민다).
  Widget _top() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // 위 14: 제목 꼬리표 구멍에서 위로 매단 실(10) · 매듭 자리.
      const SizedBox(height: SuccLook.titleThread + 4),
      SuccTitleTag(color: _color, title: detailString(x, 'name'), sub: '지도자 ${_leaders.length}'),
      const SizedBox(height: 12),
      SuccLegend(_legend, color: _color),
      const SizedBox(height: 10),
      const SizedBox(height: 1, child: ColoredBox(color: SheetLook.ink12)),
      const SizedBox(height: 10),
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
  /// 실은 줄마다 제 토막만 그린다 — 꼬리표 안의 토막(윗변 → 구멍 · 마름모 → 아랫변)은 [SuccTagPainter], 이음매 · 사람 · 건너뛰기 줄을
  /// 지나는 실과 열쇠표의 45° 실은 [SuccRowPainter](줄 뒤), 오른쪽 통로의 복위 고리는 줄 앞(꼬리표 테의 매듭이 꼬리표 위에 앉게).
  Widget _row(_Item it, int i) {
    final focused = i >= 0 && i == _cursor;
    final key = it.k == _K.seam ? _seamSpan(it) : null;
    final Widget body = switch (it.k) {
      _K.card => _card(it, focused),
      _K.seam => _seam(key),
      _K.person => _person(it, focused),
      _K.skip => _skip(it, focused),
    };
    final loops = i < 0 ? const <SuccLoop>[] : _loopsAt(i);
    return CustomPaint(
      painter: SuccRowPainter(
        line: switch (it.k) {
          _K.seam => SeamLine.of(_lin(it.m)),
          _K.person || _K.skip => _through(it) ? _nextLine(it.owner) : null,
          _K.card => null,
        },
        keyThread: key != null,
      ),
      foregroundPainter: loops.isEmpty ? null : SuccRowPainter(loops: loops),
      child: body,
    );
  }

  /// 펼친 줄을 지나는 실의 꼴 — 다음 이음매가 비움이면 옅은 실(먹 25), 아니면 이은 실.
  int _nextLine(int owner) => SeamLine.of(_lin(owner + 1)) == SeamLine.blank ? SeamLine.blank : SeamLine.solid;

  /// 복위 고리 — 같은 사람의 처음 카드와 다시 오른 카드를 오른쪽 통로에서 잇는다. 그 사이 줄마다 제 토막만 그린다.
  List<SuccLoop> _loopsAt(int i) {
    final out = <SuccLoop>[];
    for (var m = 0; m < _leaders.length; m++) {
      final f = _first[m];
      if (f == m) continue;
      final a = _cardIndex(f), b = _cardIndex(m);
      if (a < 0 || b < 0 || i < a || i > b) continue;
      out.add(i == a ? SuccLoop.start : (i == b ? SuccLoop.end : SuccLoop.mid));
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

  static const _tabular = [FontFeature.tabularFigures()];

  /// 지도자 꼬리표(40 — 그림판 꼬리표를 줄인 꼴): 머리 24 = 구멍 · 대수 8.5 · 이름 9 굵게 · `다시` · 다른 나라 · `후손 n ▸`(작은 흰 종이 —
  /// 오른쪽 끝) / 흰 층 16 = 해 8.5. 실 토막은 위(구멍으로 드는 실 — 이 카드 이음매의 갈래)와 아래(마름모에서 나가는 실 — 다음 이음매의 갈래).
  /// 좁으면 이름이 먼저 줄고(…), 작은 종이는 통째로 들어갈 자리가 없으면 숨는다 — 꼬리표 밖으로 나가지 않는다(겹침 · 돌출 금지).
  Widget _card(_Item it, bool focused) {
    final m = it.m;
    final c = _leaders[m];
    final again = _first[m] != m;
    final reach = _reach[m] ?? 0;
    final spot = _spots[m];
    final open = !again && spot.skel != null && spot.at >= 0 && _open[spot.skel!.key]![spot.at] != 0;
    final elsewhere = detailList(_lin(m) ?? const {}, 'elsewhere');
    final chips = <Widget>[
      if (again) const SuccPaper('다시'),
      for (final q in elsewhere.take(2)) SuccPaper(detailString(q, 'polity'), onTap: () => ctx.open(detailString(q, 'uid'), cell: detailString(q, 'ref'))),
      if (elsewhere.length > 2) SuccPaper('+${elsewhere.length - 2}'),
    ];
    final Widget? pill = again
        ? SuccPaper('${_ordinalOrName(_first[m])}에서', onTap: () => _jumpToLeader(_first[m]))
        : (reach > 0 ? SuccPaper('후손 $reach ${open ? '▾' : '▸'}', onTap: () => _toggle(_items.indexOf(it))) : null);
    final name = detailString(c, 'name');
    final soft = SheetLook.nameInk(_color);
    return Padding(
      padding: const EdgeInsets.only(right: SuccLook.lane),
      child: SuccPress(
        onTap: () => _openLeader(m),
        semantics: '${_ordinal(m)} $name',
        onMenu: (at) => _menu(at, it),
        builder: (hover) => SheetPickRing(
          on: focused,
          child: CustomPaint(
            painter: SuccTagPainter(
              color: _color,
              hover: hover,
              threadIn: m > 0 ? SeamLine.of(_lin(m)) : null,
              threadOut: m < _leaders.length - 1 ? SeamLine.of(_lin(m + 1)) : null,
            ),
            child: SizedBox(
              height: _G.card,
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: SuccLook.head,
                      child: CustomMultiChildLayout(
                        delegate: _HeadLayout(chips: chips.length),
                        children: [
                          LayoutId(id: 'ord', child: succLine(_ordinal(m), sheetText(SuccLook.ordText, color: soft).copyWith(fontFeatures: _tabular))),
                          LayoutId(id: 'name', child: succLine(name, sheetText(SuccLook.nameText, bold: true, color: SheetLook.tagInk(_color)), overflow: TextOverflow.ellipsis)),
                          for (var k = 0; k < chips.length; k++) LayoutId(id: 'chip$k', child: chips[k]),
                          if (pill != null) LayoutId(id: 'pill', child: pill),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: SuccLook.floor,
                      child: Padding(
                        // 흰 층의 보이는 칸은 머리 밑선 아래 ~ 아랫테 위(24 ~ 39) — 그 가운데에.
                        padding: const EdgeInsets.only(left: SuccLook.lead, right: SuccLook.headRight, bottom: 1),
                        child: Align(alignment: Alignment.centerLeft, child: succLine(_years(c), sheetText(SuccLook.yearText, color: soft).copyWith(fontFeatures: _tabular))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 이음매 글(열쇠표 한 덩이 — [succSeamSpan]: 관계 굵게 먹 85 · 방식 먹 60 · 미상과 복위의 '— n대와 같은 사람'은 먹 45).
  /// 비움이거나 글이 없으면 null(열쇠표 없음).
  InlineSpan? _seamSpan(_Item it) {
    final f = _first[it.m];
    return succSeamSpan(_lin(it.m), sameAs: f != it.m ? _ordinalOrName(f) : null);
  }

  /// 이음매(22) — 실은 왼쪽 통로([SuccRowPainter] — 이음매 갈래의 꼴), 글은 실 옆 열쇠표(왼쪽 19 · 다음 꼬리표 윗변 1 위 · 45° 실).
  Widget _seam(InlineSpan? text) {
    if (text == null) return const SizedBox.expand();
    return Padding(
      padding: const EdgeInsets.only(left: SuccLook.keyLeft, right: SuccLook.lane, top: _G.seam - SuccLook.keyBelow - SuccLook.keyBox, bottom: SuccLook.keyBelow),
      child: Align(alignment: Alignment.topLeft, child: SuccKeyLabel(text)),
    );
  }

  /// 사람 줄(28) — 들여쓴 `▸/▾` · (`+n대`) · 흰 사람 띠(둥근 끝 · 구멍 · 이름 10 굵게 + 곁글) · 파조면 파 꼬리표(`○○파 · n명 ▸`).
  Widget _person(_Item it, bool focused) {
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
    final nameInk = bits & kKinMissing != 0 || !member ? SheetLook.ink45 : SheetLook.ink85;
    final i = _items.indexOf(it);
    return SuccPress(
      onTap: kinPersonTarget(s.keys[j]) == null ? null : () => _openPerson(s.keys[j]),
      semantics: unknown ? '이름 미상' : s.name[j],
      onMenu: (at) => _menu(at, it),
      builder: (hover) => SizedBox(
        height: _G.row,
        child: Padding(
          padding: EdgeInsets.only(left: SuccLook.indentBase + kinRowIndent(it.depth), right: SuccLook.lane),
          child: Row(
            children: [
              SizedBox(
                width: SuccLook.toggle,
                child: kids
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggle(i),
                          child: Center(child: Text(open ? '▾' : '▸', style: sheetText(SuccLook.personText, color: SheetLook.ink45))),
                        ),
                      )
                    : null,
              ),
              if (deeper > 0) succLine('+$deeper대 ', sheetText(SuccLook.paperText, color: SheetLook.ink45)),
              Flexible(
                child: SheetPickRing(
                  on: focused,
                  kind: SheetTagKind.key,
                  child: SheetTag(
                    shape: SheetShape(
                      kind: SheetTagKind.key,
                      round: SuccLook.bandRound,
                      fill: hover ? SheetLook.ink4 : SheetLook.paper,
                      stroke: SheetLook.ink45,
                      hole: true,
                      holeAt: const Offset(SuccLook.bandHole, SuccLook.band / 2),
                    ),
                    height: SuccLook.band,
                    child: Padding(
                      padding: const EdgeInsets.only(left: SuccLook.bandLead, right: SuccLook.bandTail),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        child: unknown
                            ? succLine('이름 미상', sheetText(SuccLook.personText, color: SheetLook.ink45))
                            : Text.rich(
                                TextSpan(
                                  text: s.name[j],
                                  children: [
                                    if (s.sub[j].isNotEmpty)
                                      TextSpan(
                                        text: '  ${s.sub[j]}',
                                        style: const TextStyle(fontWeight: FontWeight.w400, color: SheetLook.ink60),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: sheetText(SuccLook.personText, bold: true, color: nameInk),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              if (founder != null) ...[
                const SizedBox(width: SuccLook.branchGap),
                SuccBranchTag(
                  label: '${founder.name} · $count명${kids ? (open ? ' ▾' : ' ▸') : ''}',
                  color: detailColor(founder.color, SheetLook.ink45),
                  onTap: () => _toggle(i, all: true),
                ),
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

  /// 건너뛰기 줄 — 흰 이름 종이 `→ n대 ○○`(사람 띠와 같은 들여쓰기 · 누르면 그 카드로).
  Widget _skip(_Item it, bool focused) {
    final m = it.m;
    return SuccPress(
      onTap: () => _jumpToLeader(m),
      semantics: '${_ordinal(m)} ${detailString(_leaders[m], 'name')}',
      builder: (hover) => SizedBox(
        height: _G.row,
        child: Padding(
          padding: EdgeInsets.only(left: SuccLook.indentBase + kinRowIndent(it.depth) + SuccLook.toggle, right: SuccLook.lane),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SheetPickRing(
              on: focused,
              child: SheetTag(
                shape: SheetPaperButton.shapeOf(hover: hover),
                height: SuccLook.band,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SuccLook.bandTail),
                  child: Center(
                    widthFactor: 1,
                    child: succLine('→ ${_ordinal(m)} ${detailString(_leaders[m], 'name')}'.replaceAll('  ', ' '), sheetText(SuccLook.personText, color: SheetLook.ink60), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
          ),
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

/// 지도자 꼬리표 머리(24)의 자리 — 오른쪽 끝의 작은 종이(`후손 n ▸` · `n대에서`)를 먼저 놓고, 구멍 뒤 14부터 대수(최소 16 — 이름이
/// 줄마다 한 줄에 선다) · 이름(꼬리표 폭의 45%까지) · 작은 종이(다시 · 다른 나라)를 놓는다. 작은 종이는 통째로 들어가는 것까지만
/// 보이고 나머지는 꼬리표 밖(잘림)으로 보낸다. 세로는 머리 가운데(온 화소).
class _HeadLayout extends MultiChildLayoutDelegate {
  _HeadLayout({required this.chips});
  final int chips;

  @override
  void performLayout(Size size) {
    final h = size.height;
    double mid(Size s) => ((h - s.height) / 2).roundToDouble();
    final loose = BoxConstraints.loose(size);
    var right = size.width - SuccLook.headRight;
    if (hasChild('pill')) {
      final p = layoutChild('pill', loose);
      right -= p.width;
      positionChild('pill', Offset(right, mid(p)));
      right -= SuccLook.chipGap;
    }
    final ord = layoutChild('ord', loose);
    positionChild('ord', Offset(SuccLook.lead, mid(ord)));
    final left = SuccLook.lead + math.max(SuccLook.ordMin, ord.width) + SuccLook.ordGap;
    final n = layoutChild('name', BoxConstraints(maxWidth: math.max(0, math.min(right - left, size.width * SuccLook.nameShare)), maxHeight: h));
    positionChild('name', Offset(left, mid(n)));
    var x = left + n.width;
    var shown = true;
    for (var i = 0; i < chips; i++) {
      final c = layoutChild('chip$i', loose);
      shown = shown && x + SuccLook.chipGap + c.width <= right;
      if (shown) {
        positionChild('chip$i', Offset((x + SuccLook.chipGap).roundToDouble(), mid(c)));
        x += SuccLook.chipGap + c.width;
      } else {
        positionChild('chip$i', Offset(size.width + 100, 0));
      }
    }
  }

  @override
  bool shouldRelayout(_HeadLayout old) => old.chips != chips;
}
