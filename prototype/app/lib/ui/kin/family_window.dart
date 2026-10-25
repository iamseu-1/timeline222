import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../motion.dart';
import '../../motion_spring.dart';
import '../../shell/look.dart';
import '../../shell/motion_controls.dart' show MotionChoice, MotionSegmented;
import '../../shell/parts.dart';
import '../app_bus.dart';
import '../app_memory.dart' show KinFoldMemory;
import '../context_menu.dart' show MenuRow, showTimelineMenu;
import '../detail_shell.dart';
import 'kin_head.dart';
import 'kin_layout.dart';
import 'kin_record.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  세계표 떠 있는 창 — D1 결정 2 A(위 → 아래) · 4 B + 감독 덧붙임(접고 펴기 · 파 · 머리 태그)
//  설계: `docs/설계-10건/1-2-계승과-가문-확정.md` 4절 · 8-3 · 8-4. 목업 그림 `.claude/research/10건/D1/d1-2-a.png`.
//
//  ◆ 여는 길: `bus.slot('family').value = FamilyRequest(kin: …)` — 가문 창 바닥의 `세계표` · 승계표 줄 메뉴의 `세계표에서 보기` ·
//    계보 전용 인물 창의 `세계표에서 보기`. 창은 [DetailHost.registerWindow]가 연표 위(Overlay)에 띄운다 — 가문 창 왼쪽.
//  ◆ 뼈대(갈래 `kin`)는 창을 열 때 `entity` 한 번만 받고 작업자 isolate에서 푼다([kinDecode]). 이 파일은 JSON을 풀지 않는다.
//    머리 칩 · 제목은 가문 기록(작은 기록 — [detailEntity])에서.
//  ◆ 자리는 N1의 정수 칸 셈([kinLayout] — 웹 `HT.kinLayout`과 같은 정수)이 낸다: 카드 왼쪽 = x·35 − 62, 카드 위 = 세대·82.
//    그리는 것은 보이는 카드 · 선만이다(`CustomPainter` 하나 · `RepaintBoundary`로 연표 캔버스와 나눔 · 글은 문단 캐시 LRU 600).
//  ◆ 접고 펼 때 누른 카드는 화면에서 0px. 공통 move 스프링으로 옮기며, 드나드는 짙기는 in/out을 쓴다.
//    사라지는 자리에는 snap을 쓰고, 다시 누르면 화면의 자리와 속도를 이어 받는다. 동작 줄이기면 바로 바뀐다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 세계표를 여는 부탁 — `bus.slot('family')`(app_glue의 `slotFamily`)에 넣으면 창이 뜨고, null이면 닫힌다.
@immutable
class FamilyRequest {
  const FamilyRequest({required this.kin, this.house = '', this.at = -1, this.focus = ''});

  /// 뿌리 뼈대 uid(`kin:<뿌리 가문 id>` · `kin:polity:<정권 uid>`) — 가문 기록 `x_kin.key` · 인물 기록 `x_kin.key` · 정권 `x_lineage[ref].kinAt[0]`.
  final String kin;

  /// 머리 칩 · 제목을 가져올 가문 uid(`house:<id>`). 비면 뼈대의 뿌리 파(branches[0])의 가문.
  final String house;

  /// 파에서 열면 그 파의 뿌리 마디(한 벌 앞 차례 번호 — 가문 `x_kin.at`). −1이면 뼈대 전체.
  final int at;

  /// 열자마자 데려갈 사람의 안정 열쇠(조상을 펴고 그 카드로 날아간다). 비면 맨 위.
  final String focus;

  @override
  bool operator ==(Object other) => other is FamilyRequest && other.kin == kin && other.house == house && other.at == at && other.focus == focus;

  @override
  int get hashCode => Object.hash(kin, house, at, focus);

  @override
  String toString() => 'FamilyRequest($kin, house: $house, at: $at, focus: $focus)';
}

/// 세계표 창을 여는 슬롯 이름(app_glue의 `slotFamily`와 같은 글).
const familySlot = 'family';

/// 세계표 창의 치수(1배 — 목업 d1-2-a 판에서 잰 값 · 4-4 계약의 정수).
abstract final class FamilyUi {
  /// 창: 폭 779 · 오른쪽에서 501(가문 창 380 + 확대 단추 자리) · 위 84 · 아래 19.
  static const width = 779.0, right = 501.0, top = 84.0, bottom = 19.0, radius = Ui.menuRadius;

  /// 세대 번호 칸 · 판 위 '세대' 머리 · 전체도 높이.
  static const genCol = 30.0, headPad = 18.0, overview = 56.0;

  /// 카드 · 선.
  static const cardW = 124.0, cardH = 42.0, cardR = 11.0, gap = 40.0;

  /// 덧선(양자 · 둘째 부모)을 그리는 두 끝의 거리 한도(칸 12 = 단위 48).
  static const extraReach = 48;
}

/// 세계표 카드의 화면 자리(검사 · 측정 — 누른 카드가 0px 움직이는지 · 카드끼리 겹치지 않는지).
abstract class KinGeometry {
  /// 그 안정 열쇠 카드의 전역 사각형(보이지 않으면 null).
  Rect? cardRect(String key);

  /// 지금 보이는 카드들의 전역 사각형(겹침 검사).
  List<Rect> get cardRects;
}

/// 세계표의 보기 단계 손잡이(건의 8의 4-가 — 측정 · 그림 대본이 쓴다). 단계 번호는 [KinScale.levels]의 차례(0 보통 · 1 점).
abstract class KinLevels {
  int get level;

  /// 아래 줄 세그먼트를 누른 것과 같다 — 점으로 들면 한눈 보기(맨 위부터), 보통으로 돌아오면 가운데에 가장 가까운 사람이 제자리.
  void setLevel(int index);
}

/// 세계표 떠 있는 창.
class FamilyWindow extends StatefulWidget {
  const FamilyWindow({super.key, required this.bus, required this.request, this.onClose});
  final AppBus bus;
  final FamilyRequest request;
  final VoidCallback? onClose;

  @override
  State<FamilyWindow> createState() => _FamilyWindowState();
}

class _FamilyWindowState extends State<FamilyWindow> with TickerProviderStateMixin implements KinDriver, KinGeometry, KinLevels {
  AppBus get bus => widget.bus;
  FamilyRequest get req => widget.request;

  KinSkeleton? _full; // 받은 뼈대(덩어리를 합친 것)
  KinSkeleton? _view; // 보이는 뼈대 — 파에서 열면 그 파조의 하위
  String _ancestor = ''; // 파에서 열었을 때 맨 위 옅은 한 줄(파조의 부모)
  int _genOffset = 0; // 파에서 열었을 때 그 파조의 한 벌 세대
  Uint8List _open = Uint8List(0);
  KinLayout? _lay;
  Int32List _lastChild = Int32List(0);

  List<KinChip> _head = const [];
  String _title = '';
  String _failed = '';

  Offset _pan = Offset.zero; // 판 좌표에서 보는 자리의 왼쪽 위
  Offset _move = Offset.zero; // 창을 끌어 옮긴 만큼
  Size _viewport = Size.zero;
  int _cursor = -1;
  String _findText = '';
  int _findFrom = 0;

  final _loadedDone = Completer<void>();
  bool _ready = false;
  final _focus = FocusNode(debugLabel: '세계표');
  final _findFocus = FocusNode(debugLabel: '세계표 찾기');
  final _findCtrl = TextEditingController();
  final _areaKey = GlobalKey();
  final _stats = _PaintStats();
  final _text = _TextCache();

  // 옮김(접고 펴기 · 데려가기).
  _CardShift? _shift;
  final _flyX = MotionSpring(0, epsilon: .02, maxOvershoot: 4);
  final _flyY = MotionSpring(0, epsilon: .02, maxOvershoot: 4);
  bool _flying = false;

  // 끌기 · 관성.
  Offset? _down;
  bool _dragging = false;
  final _trail = <(Duration, Offset)>[];
  late final Ticker _coast = createTicker(_onCoast);
  Offset _velocity = Offset.zero;
  Duration _coastLast = Duration.zero;

  ui.Picture? _overviewPicture;
  Size _overviewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    MotionStage.instance.attach(_flyX, _motionTick);
    MotionStage.instance.attach(_flyY, _motionTick);
    bus.slot('kinDriver').value = this;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FamilyWindow old) {
    super.didUpdateWidget(old);
    if (old.request.kin != req.kin || old.request.at != req.at || old.request.house != req.house) {
      _ready = false;
      unawaited(_load());
    } else if (old.request.focus != req.focus && req.focus.isNotEmpty) {
      unawaited(reveal(req.focus));
    }
  }

  @override
  void dispose() {
    final driver = bus.slot('kinDriver');
    if (identical(driver.value, this)) driver.value = null;
    _shift?.dispose();
    MotionStage.instance.detach(_flyX);
    MotionStage.instance.detach(_flyY);
    _coast.dispose();
    _focus.dispose();
    _findFocus.dispose();
    _findCtrl.dispose();
    _overviewPicture?.dispose();
    super.dispose();
  }

  // ── 자료 ──────────────────────────────────────────────────────────────────────────────────

  Future<String?> _fetch(String uid) async {
    try {
      final answer = await bus.ask({'op': 'entity', 'uid': uid});
      final json = answer['json'];
      return json is String && json.isNotEmpty ? json : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final text = await _fetch(req.kin);
      if (text == null) {
        _failed = '이 가문의 세계표 기록을 찾지 못했습니다.';
        if (mounted) setState(() {});
        return;
      }
      var full = await kinDecode(text, uid: req.kin);
      // 파의 뿌리 · 데려갈 사람이 나눈 덩어리 안이면 그 덩어리를 받아 합친다.
      if (req.at >= 0 && full.locate(req.at).at < 0) full = (await kinRevealIn(full, req.at, _fetch)).skel;
      if (!mounted) return;
      _setFull(full);
      // 머리 칩 · 제목 — 가문 기록에서(없으면 뼈대의 파 이름).
      final houseUid = req.house.isNotEmpty ? req.house : (full.branches.isNotEmpty ? full.branches.first.uid : '');
      final house = houseUid.isEmpty ? null : await detailEntity(bus, houseUid);
      if (!mounted) return;
      _head = KinChip.read(house?['x_head']);
      _title = '${house?['name'] ?? (full.branches.isNotEmpty ? full.branches.first.name : '')}'.trim();
      _ready = true;
      _failed = '';
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _centerStart();
        if (req.focus.isNotEmpty) unawaited(reveal(req.focus));
        _focus.requestFocus();
      });
    } catch (_) {
      _failed = '세계표 기록을 읽지 못했습니다.';
      if (mounted) setState(() {});
    } finally {
      if (!_loadedDone.isCompleted) _loadedDone.complete();
    }
  }

  /// 받은 뼈대로 보이는 뼈대 · 펼침 · 자리를 다시 짓는다(접힘은 안정 열쇠로 옮긴다).
  void _setFull(KinSkeleton full, {Uint8List? keepOpen, KinSkeleton? keepFrom}) {
    _full = full;
    var view = full;
    _ancestor = '';
    if (req.at >= 0) {
      final at = full.locate(req.at).at;
      if (at >= 0) {
        view = _slice(full, at);
        final p = full.par[at];
        if (p >= 0) _ancestor = full.name[p];
      }
    }
    _view = view;
    _genOffset = identical(view, full) || view.n == 0 ? 0 : full.gen[full.indexOfKey(view.keys[0])];
    final last = Int32List(view.n)..fillRange(0, view.n, -1);
    for (var j = 0; j < view.n; j++) {
      final p = view.par[j];
      if (p >= 0) last[p] = j;
    }
    _lastChild = last;
    if (keepOpen != null && keepFrom != null) {
      final open = kinDefaultOpen(view);
      for (var i = 0; i < keepFrom.n; i++) {
        final j = view.indexOfKey(keepFrom.keys[i]);
        if (j >= 0) open[j] = keepOpen[i];
      }
      _open = open;
    } else {
      final base = kinDefaultOpen(view);
      final memory = _memory;
      final flipped = memory?.read(_memoryKey) ?? const <String>{};
      _open = flipped.isEmpty ? base : kinFoldApply(view, base, flipped);
    }
    _relayout();
  }

  /// 파조의 하위를 뿌리로 본 뼈대(새로 짓지 않고 열을 잘라 옮김 — 4-1 '파에서 열면').
  static KinSkeleton _slice(KinSkeleton s, int at) {
    final end = at + s.size[at], n = end - at, g0 = s.gen[at];
    Int32List cut(Int32List a) => Int32List.fromList(a.sublist(at, end));
    final par = Int32List(n), gen = Int32List(n);
    var gens = 0;
    for (var i = 0; i < n; i++) {
      par[i] = i == 0 ? -1 : s.par[at + i] - at;
      gen[i] = s.gen[at + i] - g0;
      gens = math.max(gens, gen[i] + 1);
    }
    final extra = <int>[];
    for (var e = 0; e + 3 < s.extra.length; e += 4) {
      final f = s.extra[e], t = s.extra[e + 1];
      if (f >= at && f < end && t >= at && t < end) extra.addAll([f - at, t - at, s.extra[e + 2], s.extra[e + 3]]);
    }
    return KinSkeleton(
      key: s.key,
      n: n,
      gens: gens,
      par: par,
      size: cut(s.size),
      gen: gen,
      bits: cut(s.bits),
      edge: cut(s.edge),
      branch: cut(s.branch),
      color: cut(s.color),
      color2: cut(s.color2),
      name: s.name.sublist(at, end),
      sub: s.sub.sublist(at, end),
      keys: s.keys.sublist(at, end),
      extra: Int32List.fromList(extra),
      colors: s.colors,
      branches: s.branches,
      cells: {
        for (final e in s.cells.entries)
          if (e.value >= at && e.value < end) e.key: e.value - at,
      },
      stubs: {
        for (final e in s.stubs.entries)
          if (e.key >= at && e.key < end) e.key - at: e.value,
      },
      warnings: const [],
      root: KinRoot(uid: s.root?.uid ?? s.key, at: s.fullIndexOf(at), up: '', upAt: -1),
    );
  }

  KinFoldMemory? get _memory {
    final v = bus.slot('kinFold').value;
    return v is KinFoldMemory ? v : null;
  }

  /// 접힘 기억의 창 열쇠 — 뿌리 뼈대 uid(파에서 열면 `<uid>@<파조 안정 열쇠>`).
  String get _memoryKey {
    final v = _view;
    if (req.at < 0 || v == null || v.n == 0) return req.kin;
    return '${req.kin}@${v.keys[0]}';
  }

  void _save() {
    final v = _view;
    final memory = _memory;
    if (v == null || memory == null) return;
    memory.write(_memoryKey, kinFoldDiff(v, _open, kinDefaultOpen(v)));
  }

  /// 보기 단계(건의 8의 4-가): 보통 ↔ 점. 자리 셈은 그대로이고 칸의 px만 바뀐다(`KinScale`).
  KinScale _s = KinScale.normal;

  @override
  int get level => KinScale.levels.indexOf(_s);

  @override
  void setLevel(int index) {
    final next = KinScale.levels[index.clamp(0, KinScale.levels.length - 1)];
    _setScale(next, overview: next.dots);
  }

  /// 단계를 바꾼다. [overview]면 한눈 보기(아래 줄 세그먼트 · V로 점 단계에 들 때 — 목업의 '점' 그림: 가문 전체의 생김새를 한눈에):
  /// 판이 창보다 좁으면 가운데, 넓으면 왼쪽 끝부터 · 늘 맨 위부터. 아니면 [keep](없으면 [at] — 판 위 화면 좌표, 그것도 없으면 가운데)에
  /// 가장 가까운 사람이 화면에서 제자리에 남는다(Ctrl+휠 · 점 누르기 · 보통으로 돌아올 때).
  void _setScale(KinScale next, {Offset? at, int keep = -1, bool overview = false}) {
    if (next == _s || _lay == null) return;
    _stopFly();
    _coast.stop();
    _shift?.dispose();
    _shift = null;
    final point = at ?? Offset(_viewport.width / 2, _viewport.height / 2);
    final i = keep >= 0 ? keep : _nearest(point);
    Offset? before;
    if (i >= 0) before = Offset(_cardLeft(i) + _s.cardW / 2 - _pan.dx, _cardTop(i) + _s.cardH / 2 - _pan.dy);
    _s = next;
    _overviewPicture?.dispose();
    _overviewPicture = null;
    _tip = null;
    setState(() {
      if (overview) {
        final plane = _plane, vw = _viewport.width;
        _pan = _clampPan(Offset(plane.width <= vw ? -(vw - plane.width) / 2 : -_overviewPad, 0));
      } else if (i >= 0 && before != null) {
        _pan = _clampPan(Offset(_cardLeft(i) + _s.cardW / 2 - before.dx, _cardTop(i) + _s.cardH / 2 - before.dy));
      }
    });
  }

  /// 화면 좌표 [p]에 가장 가까운 보이는 사람(없으면 −1).
  int _nearest(Offset p) {
    final lay = _lay;
    if (lay == null) return -1;
    final px = p.dx + _pan.dx, py = p.dy + _pan.dy;
    var best = -1;
    var bd = double.infinity;
    for (final i in _visibleSet(lay, _pan)) {
      final d = (_cardLeft(i) + _s.cardW / 2 - px).abs() + (_cardTop(i) + _s.cardH / 2 - py).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  /// 점 단계 · 이름 미상에 올렸을 때의 풍선(글 · 화면 자리).
  ({String text, Offset at})? _tip;

  void _hover(Offset local) {
    final hit = _hit(local);
    final v = _view;
    String? text;
    if (hit != null && hit.$2 == _Hit.card && v != null) {
      final i = hit.$1;
      final unknown = v.bits[i] & kKinUnknown != 0;
      if (unknown) {
        text = '이름 미상';
      } else if (_s.dots) {
        text = v.sub[i].isEmpty ? v.name[i] : '${v.name[i]} · ${v.sub[i]}';
      }
    }
    final next = text == null ? null : (text: text, at: local);
    if (next?.text == _tip?.text && (next == null || _tip != null)) return;
    setState(() => _tip = next);
  }

  /// 판 위 여백(맨 위 '세대' 머리 + 파에서 열었으면 옅은 조상 한 줄).
  double get _topPad => FamilyUi.headPad + (_ancestor.isNotEmpty ? _s.row : 0);

  void _relayout() {
    final v = _view;
    if (v == null) return;
    _lay = kinLayout(v, _open);
    _overviewPicture?.dispose();
    _overviewPicture = null;
  }

  // ── 자리 ──────────────────────────────────────────────────────────────────────────────────

  double _cardLeft(int i) => _s.left(_lay!.x[i]);
  double _cardDisplayLeft(int i) => _shift?.positions[i]?.value ?? _cardLeft(i);
  double _cardTop(int i) => _topPad + _view!.gen[i] * _s.row;
  Size get _plane => Size(math.max(1, (_lay?.width ?? 0) * _s.unit).toDouble(), _topPad + (_view?.gens ?? 1) * _s.row);

  Offset _clampPan(Offset p) {
    final vw = _viewport.width, vh = _viewport.height, plane = _plane;
    final minX = -vw / 2, maxX = math.max(minX, plane.width - vw / 2);
    // 판이 창의 반보다 낮아도(점 단계의 작은 세계표) 맨 위에 둘 수 있게 — 0까지는 늘 허락한다(건의 8의 4-가 한눈 보기).
    final minY = -vh / 3, maxY = math.max(0.0, plane.height - vh / 2);
    return Offset(p.dx.clamp(minX, maxX), p.dy.clamp(minY, maxY));
  }

  /// 처음 자리 — 판이 좁으면 가운데, 넓으면 첫 뿌리를 가운데로.
  void _centerStart() {
    final lay = _lay;
    if (lay == null || _viewport.isEmpty) return;
    final plane = _plane;
    final dx = plane.width <= _viewport.width ? -(_viewport.width - plane.width) / 2 : _cardLeft(0) + _s.cardW / 2 - _viewport.width / 2;
    setState(() => _pan = _clampPan(Offset(dx, 0)));
  }

  void _motionTick() {
    if (!mounted) return;
    if (_flying) {
      _pan = _clampPan(Offset(_flyX.value, _flyY.value));
      if (!_flyX.active && !_flyY.active) _flying = false;
    }
    if (_shift != null && !_shift!.active) {
      _shift!.dispose();
      _shift = null;
    }
    setState(() {});
  }

  /// 직접 입력이 들어오면 같은 pan의 주인을 넘긴다.
  void _stopFly() {
    _flying = false;
    _flyX.stop();
    _flyY.stop();
  }

  /// 그 카드로 날아간다(move · 동작 줄이기면 바로).
  void _flyToCard(int i) {
    if (_lay == null || _viewport.isEmpty || _lay!.x[i] == 0) return;
    final want = _clampPan(Offset(_cardLeft(i) + _s.cardW / 2 - _viewport.width / 2, _cardTop(i) + _s.cardH / 2 - _viewport.height / 3));
    _coast.stop();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _stopFly();
      setState(() => _pan = want);
      return;
    }
    if (!_flying) {
      _flyX.jump(_pan.dx);
      _flyY.jump(_pan.dy);
    }
    _flying = true;
    _flyX.retarget(want.dx);
    _flyY.retarget(want.dy);
  }

  Offset get _panNow => _pan;

  // ── 접고 펴기 ──────────────────────────────────────────────────────────────────────────────

  /// 펼침을 바꾸고 자리를 다시 셈한다 — [anchor] 카드는 화면에서 0px, 나머지는 옛 x → 새 x.
  void _change(VoidCallback change, {int anchor = -1}) {
    final v = _view, lay = _lay;
    if (v == null || lay == null) return;
    _stopFly();
    final prior = _shift;
    final before = {..._visibleSet(lay, _pan), ...?prior?.positions.keys};
    final oldLeft = <int, double>{for (final i in before) i: prior?.positions[i]?.value ?? _cardLeft(i)};
    final oldPan = _pan;
    final anchorX = anchor >= 0 && lay.x[anchor] > 0 ? (oldLeft[anchor] ?? _cardLeft(anchor)) - _pan.dx : null;
    change();
    _relayout();
    _save();
    final nl = _lay!;
    var pan = _pan;
    if (anchorX != null && nl.x[anchor] > 0) pan = Offset(_cardLeft(anchor) - anchorX, pan.dy);
    pan = _clampPan(pan);
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!calm && before.isNotEmpty) {
      final after = _visibleSet(nl, pan);
      final from = <int, double>{}, to = <int, double>{}, fade = <int, int>{};
      for (final i in {...before, ...after}) {
        final was = oldLeft[i];
        final now = nl.x[i] > 0 ? _cardLeft(i) : null;
        if (was != null && now != null) {
          from[i] = was;
          to[i] = now;
        } else if (now != null) {
          // 새로 나타남 — 부모 자리에서 흘러나온다.
          final a = _shownAncestor(i, (j) => oldLeft.containsKey(j));
          from[i] = a >= 0 ? oldLeft[a]! : now;
          to[i] = now;
          fade[i] = 1;
        } else if (was != null) {
          // 접혀 사라짐 — 부모 쪽으로 모인다.
          final a = _shownAncestor(i, (j) => nl.x[j] > 0);
          from[i] = was;
          to[i] = a >= 0 ? _cardLeft(a) : was;
          fade[i] = -1;
        }
      }
      // 판의 닻이 옮겨도 화면에 보이던 시작점은 그대로이며, 이전 속도도 같은 좌표계다.
      for (final i in from.keys) {
        from[i] = from[i]! + pan.dx - oldPan.dx;
      }
      _shift = _CardShift(from, to, fade, prior, _motionTick, anchor: anchor);
    } else {
      _shift = null;
    }
    prior?.dispose();
    setState(() => _pan = pan);
  }

  int _shownAncestor(int i, bool Function(int j) shown) {
    for (var p = _view!.par[i]; p >= 0; p = _view!.par[p]) {
      if (shown(p)) return p;
    }
    return -1;
  }

  bool _toggleIndex(int i, {bool all = false}) {
    final v = _view;
    if (v == null || i < 0 || i >= v.n) return false;
    if (v.isStub(i)) {
      unawaited(_openStub(i));
      return true;
    }
    if (v.size[i] <= 1) return false;
    _change(() => kinToggle(v, _open, i, all: all), anchor: i);
    return true;
  }

  /// 꼬투리(나눈 덩어리)를 펼치면 그 덩어리를 받아 합친 뒤 편다.
  Future<void> _openStub(int i) async {
    final full = _full, view = _view;
    if (full == null || view == null) return;
    final key = view.keys[i];
    final t = full.indexOfKey(key);
    if (t < 0) return;
    final merged = await kinOpenStub(full, t, _fetch);
    if (!mounted || identical(merged, full)) return;
    final keepOpen = Uint8List.fromList(_open), keepFrom = view;
    _setFull(merged, keepOpen: keepOpen, keepFrom: keepFrom);
    final j = _view!.indexOfKey(key);
    if (j >= 0) _change(() => _open[j] = 1, anchor: j);
  }

  void _setOpen(Uint8List open) => _change(() => _open = open, anchor: _cursor >= 0 && _lay!.x[_cursor] > 0 ? _cursor : _anchorGuess());

  /// 보는 자리 가운데에 가장 가까운 카드(모두 펴기 · 접기에서 제자리에 둘 카드).
  int _anchorGuess() {
    final lay = _lay;
    if (lay == null) return -1;
    final vis = _visibleSet(lay, _pan);
    if (vis.isEmpty) return 0;
    final cx = _pan.dx + _viewport.width / 2;
    var best = vis.first;
    var bd = double.infinity;
    for (final i in vis) {
      final d = (_cardLeft(i) + _s.cardW / 2 - cx).abs() + _cardTop(i) * .01;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  /// 보이는 카드(판 좌표 [pan] 기준 · 위아래 · 좌우 한 화면 여유).
  List<int> _visibleSet(KinLayout lay, Offset pan) {
    final v = _view!;
    final out = <int>[];
    final lo = (pan.dx - _viewport.width / 2).round(), hi = (pan.dx + _viewport.width * 1.5).round();
    for (var g = 0; g < v.gens; g++) {
      final top = _topPad + g * _s.row;
      if (top + _s.cardH < pan.dy - _viewport.height / 2 || top > pan.dy + _viewport.height * 1.5) continue;
      final r = lay.visibleIn(g, lo, hi, scale: _s);
      for (var k = r.start; k < r.end; k++) {
        out.add(lay.rows[g][k]);
      }
    }
    return out;
  }

  // ── 찾기 ──────────────────────────────────────────────────────────────────────────────────

  void _find(String text) {
    final v = _view;
    final q = text.trim();
    if (v == null || q.isEmpty) return;
    if (q != _findText) {
      _findText = q;
      _findFrom = 0;
    }
    for (var n = 0; n < v.n; n++) {
      final i = (_findFrom + n) % v.n;
      if (v.name[i].contains(q)) {
        _findFrom = i + 1;
        unawaited(reveal(v.keys[i]));
        return;
      }
    }
  }

  // ── 창 열기 ───────────────────────────────────────────────────────────────────────────────

  void _openPerson(int i) {
    final t = kinPersonTarget(_view!.keys[i]);
    if (t == null) return;
    bus.select(t.uid, cell: t.cell);
  }

  Future<void> _menu(Offset at, int i) async {
    final v = _view!;
    final key = v.keys[i];
    final t = kinPersonTarget(key);
    final founder = v.bits[i] & kKinFounder != 0 ? _branchOf(i) : null;
    await showTimelineMenu(context, [
      if (t != null) MenuRow('창 열기', onSelected: () => _openPerson(i)),
      if (t != null && t.cell != null) MenuRow('승계표에서 보기', onSelected: () => bus.select(t.uid, cell: successionCell)),
      if (founder != null) MenuRow('${founder.name} 가문 창', onSelected: () => bus.select(founder.uid, kind: 'house')),
      if (v.size[i] > 1) MenuRow('그 아래 모두 펼치기', onSelected: () => _change(() => _open.fillRange(i, i + v.size[i], 1), anchor: i)),
    ], at: at);
  }

  KinBranch? _branchOf(int i) {
    final v = _view!;
    final full = v.fullIndexOf(i);
    for (final b in v.branches) {
      if (b.at == full) return b;
    }
    return null;
  }

  // ── 손잡이(KinDriver) ─────────────────────────────────────────────────────────────────────

  @override
  String get kind => 'family';

  @override
  Future<void> get loaded => _loadedDone.future;

  @override
  bool get ready => _ready;

  @override
  void expandAll() {
    final v = _view;
    if (v != null) _setOpen(kinOpenAll(v));
  }

  @override
  void collapseAll() {
    final v = _view;
    if (v != null) _setOpen(kinOpenNone(v));
  }

  @override
  List<String> get visible {
    final lay = _lay, v = _view;
    if (lay == null || v == null) return const [];
    final out = <String>[];
    for (var g = 0; g < v.gens; g++) {
      final top = _topPad + g * _s.row;
      if (top + _s.cardH < _pan.dy || top > _pan.dy + _viewport.height) continue;
      final r = lay.visibleIn(g, _pan.dx.floor(), (_pan.dx + _viewport.width).ceil(), scale: _s);
      for (var k = r.start; k < r.end; k++) {
        out.add(v.keys[lay.rows[g][k]]);
      }
    }
    return out;
  }

  @override
  bool toggle(String key) => _toggleIndex(_view?.indexOfKey(key) ?? -1);

  @override
  void panBy(double dx, double dy) {
    if (_lay == null) return;
    _coast.stop();
    _stopFly();
    setState(() => _pan = _clampPan(_pan + Offset(dx, dy)));
  }

  @override
  Future<bool> reveal(String key) async {
    await loaded;
    final v = _view;
    if (!mounted || v == null) return false;
    var i = v.indexOfKey(key);
    if (i < 0) {
      // 아직 받지 않은 덩어리 안일 수 있다 — 그 사람의 한 벌 번호를 모르므로 열쇠로는 찾지 못한다(N1 kinReveal은 번호로 찾음).
      return false;
    }
    final open = Uint8List.fromList(_open);
    kinOpenTo(v, open, i);
    _change(() => _open = open);
    setState(() => _cursor = i);
    _flyToCard(i);
    return true;
  }

  @override
  int get built => _stats.cards;

  @override
  int get lines => _stats.lines;

  @override
  Rect? get area {
    final box = _areaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Rect? cardRect(String key) {
    final v = _view, lay = _lay, a = area;
    if (v == null || lay == null || a == null) return null;
    final i = v.indexOfKey(key);
    if (i < 0 || lay.x[i] == 0) return null;
    return Rect.fromLTWH(a.left + FamilyUi.genCol + _cardDisplayLeft(i) - _pan.dx, a.top + _cardTop(i) - _pan.dy, _s.cardW, _s.cardH);
  }

  @override
  List<Rect> get cardRects => [for (final k in visible) ?cardRect(k)];

  // ── 키보드(4-6) ───────────────────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final v = _view, lay = _lay;
    if (v == null || lay == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }
    // 처음 누른 키는 맨 위 뿌리 카드에서 시작한다.
    final cur = _cursor >= 0 && lay.x[_cursor] > 0 ? _cursor : (v.n > 0 ? 0 : -1);
    if (cur < 0) return KeyEventResult.ignored;
    void go(int i) {
      if (i < 0 || i >= v.n || lay.x[i] == 0) return;
      setState(() => _cursor = i);
      _ensureVisible(i);
    }

    if (k == LogicalKeyboardKey.arrowUp) {
      go(v.par[cur]);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      if (v.size[cur] > 1) {
        if (!kinShowsChildren(v, _open, cur)) _toggleIndex(cur);
        go(cur + 1);
      }
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      final right = k == LogicalKeyboardKey.arrowRight;
      final row = lay.rows[v.gen[cur]];
      var at = -1;
      for (var q = 0; q < row.length; q++) {
        if (row[q] == cur) at = q;
      }
      final nb = at + (right ? 1 : -1);
      if (at >= 0 && nb >= 0 && nb < row.length) go(row[nb]);
    } else if (k == LogicalKeyboardKey.space || e.character == '*') {
      if (e.character == '*') {
        final p = v.par[cur];
        if (p >= 0) {
          _change(() {
            for (final c in v.children(p)) {
              _open[c] = 1;
            }
          }, anchor: cur);
        }
      } else {
        _toggleIndex(cur, all: HardwareKeyboard.instance.isAltPressed);
      }
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _openPerson(cur);
    } else if (k == LogicalKeyboardKey.keyF) {
      _findFocus.requestFocus();
    } else if (k == LogicalKeyboardKey.keyV) {
      // 연표의 조감과 같은 키 — 보통 ↔ 점(단계 표의 차례로 돈다). 점으로 들 때는 한눈 보기, 돌아올 때는 커서의 사람이 제자리.
      final at = KinScale.levels.indexOf(_s);
      final next = KinScale.levels[(at + 1) % KinScale.levels.length];
      _setScale(next, keep: _cursor >= 0 && lay.x[_cursor] > 0 ? _cursor : -1, overview: next.dots);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _ensureVisible(int i) {
    final l = _cardLeft(i), t = _cardTop(i);
    var p = _pan;
    if (l < p.dx + 8) p = Offset(l - 8, p.dy);
    if (l + _s.cardW > p.dx + _viewport.width - 8) p = Offset(l + _s.cardW - _viewport.width + 8, p.dy);
    if (t < p.dy + 8) p = Offset(p.dx, t - 8);
    if (t + _s.cardH + 24 > p.dy + _viewport.height) p = Offset(p.dx, t + _s.cardH + 24 - _viewport.height);
    if (p != _pan) setState(() => _pan = _clampPan(p));
  }

  // ── 손짓(끌기 문턱 5px · 관성 250ms · 휠 · Shift+휠) ─────────────────────────────────────

  void _onDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    _coast.stop();
    _stopFly();
    _down = e.localPosition;
    _dragging = false;
    _trail
      ..clear()
      ..add((e.timeStamp, e.localPosition));
  }

  void _onMoveP(PointerMoveEvent e) {
    final down = _down;
    if (down == null) return;
    if (!_dragging && (e.localPosition - down).distance < Motion.dragThreshold) return;
    if (!_dragging) {
      _dragging = true;
      _down = e.localPosition; // 넘는 순간 기준점을 다시 잡는다
      return;
    }
    _trail.add((e.timeStamp, e.localPosition));
    while (_trail.length > 2 && e.timeStamp - _trail.first.$1 > Duration(milliseconds: Motion.coastGrab.round())) {
      _trail.removeAt(0);
    }
    setState(() => _pan = _clampPan(_pan - e.delta));
  }

  void _onUp(PointerUpEvent e) {
    final down = _down;
    _down = null;
    if (down == null) return;
    if (!_dragging) {
      _tap(e.localPosition);
      return;
    }
    _dragging = false;
    if (_trail.length < 2) return;
    final a = _trail.first, b = _trail.last;
    final dt = (b.$1 - a.$1).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final v = (b.$2 - a.$2) / dt;
    if (v.distance < Motion.coastMin || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
    _velocity = -v;
    _coastLast = Duration.zero;
    _coast.start();
  }

  void _onCoast(Duration t) {
    final dt = (t - _coastLast).inMicroseconds / 1e6;
    _coastLast = t;
    if (dt <= 0) return;
    final decay = math.exp(-dt * 1000 / Motion.coastTau);
    setState(() => _pan = _clampPan(_pan + _velocity * dt));
    _velocity *= decay;
    if (_velocity.distance < Motion.coastRest) _coast.stop();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    _coast.stop();
    _stopFly();
    if (HardwareKeyboard.instance.isControlPressed && e.scrollDelta.dy != 0) {
      // Ctrl+휠: 아래로 굴리면 좁게(점) · 위로 굴리면 보통 — 커서 밑의 사람이 제자리.
      final at = KinScale.levels.indexOf(_s);
      final to = (at + (e.scrollDelta.dy > 0 ? 1 : -1)).clamp(0, KinScale.levels.length - 1);
      _setScale(KinScale.levels[to], at: e.localPosition - const Offset(FamilyUi.genCol, 0));
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final d = shift ? Offset(e.scrollDelta.dy + e.scrollDelta.dx, 0) : e.scrollDelta;
    setState(() => _pan = _clampPan(_pan + d));
  }

  /// 누른 자리 → 카드 · 손잡이 · 알약 · 파 이름표.
  void _tap(Offset local) {
    final hit = _hit(local);
    if (hit == null) return;
    setState(() => _cursor = hit.$1);
    if (_s.dots) {
      // 점을 누르면 그 사람을 가운데 두고 보통으로 돌아온다.
      _setScale(KinScale.normal, keep: hit.$1);
      _flyToCard(hit.$1);
      return;
    }
    switch (hit.$2) {
      case _Hit.card:
        _openPerson(hit.$1);
      case _Hit.handle:
      case _Hit.pill:
        _toggleIndex(hit.$1);
      case _Hit.branch:
        _toggleIndex(hit.$1, all: true);
    }
  }

  (int, _Hit)? _hit(Offset local) {
    final lay = _lay, v = _view;
    if (lay == null || v == null || local.dx < FamilyUi.genCol) return null;
    final px = local.dx - FamilyUi.genCol + _pan.dx, py = local.dy + _pan.dy;
    final dots = _s.dots;
    final g = ((py - _topPad) / _s.row).floor();
    for (final gg in [g, g + 1]) {
      if (gg < 0 || gg >= v.gens) continue;
      final top = _topPad + gg * _s.row;
      final r = lay.visibleIn(gg, (px - _s.cardW).floor(), (px + 1).ceil(), scale: _s);
      final candidates = _shift == null
          ? [for (var k = r.start; k < r.end; k++) lay.rows[gg][k]]
          : [
              for (final i in _shift!.positions.keys)
                if (v.gen[i] == gg && lay.x[i] > 0) i,
            ];
      for (final i in candidates) {
        final left = _cardDisplayLeft(i);
        if (px < left || px > left + _s.cardW) continue;
        if (py >= top && py <= top + _s.cardH) {
          final kids = v.size[i] > 1 || v.isStub(i);
          if (!dots && kids && v.bits[i] & kKinUnknown == 0 && px > left + _s.cardW - 22 && py < top + 20) return (i, _Hit.handle);
          return (i, _Hit.card);
        }
        if (dots) continue; // 점 단계에는 알약 · 파 이름표가 없다
        final kids = v.size[i] > 1 || v.isStub(i);
        if (kids && !kinShowsChildren(v, _open, i) && py > top + _s.cardH && py < top + _s.cardH + 26) return (i, _Hit.pill);
        if (v.bits[i] & kKinFounder != 0 && py >= top - 20 && py < top && px < left + _s.cardW / 2) return (i, _Hit.branch);
      }
    }
    return null;
  }

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final room = screen.width - FamilyUi.right - 12;
    final narrow = room < 420;
    final width = narrow ? screen.width - 16 : math.min(FamilyUi.width, room);
    final height = math.max(320.0, screen.height - FamilyUi.top - FamilyUi.bottom);
    final right = narrow ? 8.0 : FamilyUi.right;
    return Positioned(
      right: right - _move.dx,
      top: FamilyUi.top + _move.dy,
      width: width,
      height: height,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Semantics(
          container: true,
          label: '세계표',
          child: DecoratedBox(
            // 창 둘레 1px 선(먹 20% · 둥근 12 — 건의 8의 4-나 '둘 다'): 불투명한 바탕 카드 위에 그려야 보인다(뒤에 깔면 카드가 덮는다).
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FamilyUi.radius),
              border: Border.all(color: Ui.line),
            ),
            child: GlassCard(
              radius: FamilyUi.radius,
              blur: Ui.blurSoft,
              color: Ui.detailGlass,
              shadow: const [],
              child: DefaultTextStyle(
                style: DetailUi.body,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headRow(),
                    Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 0), child: _titleBlock()),
                    Expanded(child: _treeArea()),
                    Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 6), child: _overview()),
                    _foot(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 머리 — 칩 줄(끌어서 창을 옮기는 손잡이) · ✕.
  Widget _headRow() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanUpdate: (d) => setState(() => _move += d.delta),
    child: Padding(
      padding: DetailUi.headPad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: _head.isEmpty
                  ? Wrap(spacing: 6, children: [const DetailBadge('세계표', dot: false), if (_title.isNotEmpty) DetailBadge(_title)])
                  : KinHead(_head, onOpen: (c) => kinChipOpen(bus, c)),
            ),
          ),
          const SizedBox(width: 8),
          ShellButton(
            width: 32,
            padding: EdgeInsets.zero,
            tooltip: '닫기',
            onPressed: widget.onClose,
            child: const Text('✕', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    ),
  );

  Widget _titleBlock() {
    final v = _view;
    var leaders = 0;
    if (v != null) {
      for (var i = 0; i < v.n; i++) {
        if (v.bits[i] & kKinLeader != 0) leaders++;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Text.rich(
            TextSpan(
              text: '${_title.isEmpty ? '' : '$_title '}세계표',
              children: [
                if (v != null)
                  TextSpan(
                    text: '   사람 ${v.n} · 지도자 $leaders',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Ui.text3),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 19, fontWeight: FontWeight.w700, color: Ui.text),
          ),
        ),
        KinLegend(const [
          ('ruler:#c8b193', '지도자(나라 색 · 대수)'),
          ('paper', '지도자 아님'),
          ('seam:5', '부모 → 자식'),
          ('adopt', '양자(양부)'),
          ('skip', '여러 대 건너뜀(n대손)'),
          ('ring', '이름 미상'),
        ], ink: KinUi.treeInk),
        if (_failed.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: DetailNote(_failed)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _treeArea() => LayoutBuilder(
    builder: (context, box) {
      final size = Size(box.maxWidth - FamilyUi.genCol - 2 * _framePad, box.maxHeight - 2);
      if (size != _viewport) {
        final first = _viewport.isEmpty;
        _viewport = size;
        if (first && _ready) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _centerStart() : null);
      }
      if (!_ready || _lay == null) {
        return Center(
          child: Text(_failed.isEmpty ? '세계표를 짓고 있습니다' : _failed, style: const TextStyle(fontSize: 13, color: Ui.text3)),
        );
      }
      final pan = _panNow;
      final tip = _tip;
      // 그림판 둘레의 1px 틀(먹 20% · 둥근 6 · 좌우 여백 18)과 세대 번호 칸의 가는 세로선(먹 8%) — 건의 8의 4-나 '둘 다'.
      final area = Listener(
        key: _areaKey,
        onPointerDown: _onDown,
        onPointerMove: _onMoveP,
        onPointerUp: _onUp,
        onPointerSignal: _onSignal,
        onPointerHover: (e) => _hover(e.localPosition),
        child: GestureDetector(
          onSecondaryTapUp: (d) {
            final hit = _hit(d.localPosition);
            if (hit != null) unawaited(_menu(d.globalPosition, hit.$1));
          },
          onLongPressStart: (d) {
            final hit = _hit(d.localPosition);
            if (hit != null) unawaited(_menu(d.globalPosition, hit.$1));
          },
          child: RepaintBoundary(
            child: ClipRect(
              child: CustomPaint(
                size: Size.infinite,
                painter: _TreePainter(
                  view: _view!,
                  lay: _lay!,
                  open: _open,
                  lastChild: _lastChild,
                  pan: pan,
                  topPad: _topPad,
                  ancestor: _ancestor,
                  genOffset: _genOffset,
                  shift: _shift,
                  cursor: _cursor,
                  text: _text,
                  stats: _stats,
                  scale: _s,
                ),
              ),
            ),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _framePad),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Ui.ink20), borderRadius: BorderRadius.circular(Ui.controlRadius)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Ui.controlRadius - 1),
            child: Stack(
              children: [
                MouseRegion(onExit: (_) => _tip == null ? null : setState(() => _tip = null), child: area),
                const Positioned(left: FamilyUi.genCol - 1, top: 0, bottom: 0, child: SizedBox(width: 1, child: ColoredBox(color: Ui.ink8))),
                if (tip != null)
                  Positioned(
                    left: tip.at.dx + 12,
                    top: tip.at.dy + 14,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Ui.ink, borderRadius: BorderRadius.circular(Ui.innerRadius)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(tip.text, style: const TextStyle(fontSize: 11.5, height: 16 / 11.5, fontWeight: FontWeight.w600, color: Ui.paper)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// 그림판 틀의 좌우 여백.
  static const _framePad = 18.0;

  /// 한눈 보기에서 판이 창보다 넓을 때 왼쪽 끝 사람 앞에 두는 틈.
  static const _overviewPad = 12.0;

  /// 전체도(56px) — 보이는 사람을 세대 × 칸 1px 막대로. 지금 보는 자리를 테두리로 · 누르거나 끌면 그리로.
  Widget _overview() => SizedBox(
    height: FamilyUi.overview,
    child: LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, FamilyUi.overview);
        void jump(Offset p) {
          _coast.stop();
          _stopFly();
          final plane = _plane;
          final s = _overviewScale(size, plane);
          setState(() => _pan = _clampPan(Offset(p.dx / s.width - _viewport.width / 2, p.dy / s.height - _viewport.height / 2)));
        }

        return GestureDetector(
          onTapDown: (d) => jump(d.localPosition),
          onPanUpdate: (d) => jump(d.localPosition),
          child: CustomPaint(size: size, painter: _OverviewPainter(this, size)),
        );
      },
    ),
  );

  Size _overviewScale(Size box, Size plane) => Size(box.width / math.max(1.0, plane.width), box.height / math.max(1.0, plane.height));

  ui.Picture _overviewOf(Size box) {
    final had = _overviewPicture;
    if (had != null && _overviewSize == box) return had;
    had?.dispose();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final lay = _lay!, v = _view!;
    final s = _overviewScale(box, _plane);
    final bar = Paint()..color = KinUi.fade(Ui.text2, .55);
    final lead = Paint()..color = KinUi.fade(Ui.accent, .8);
    for (var g = 0; g < v.gens; g++) {
      final y = (_topPad + g * _s.row + _s.cardH / 2) * s.height;
      final row = lay.rows[g];
      for (var k = 0; k < row.length; k++) {
        final i = row[k];
        final x = _cardLeft(i) * s.width;
        c.drawRect(Rect.fromLTWH(x, y, math.max(1.0, _s.cardW * s.width), math.max(1.0, s.height * 20)), v.bits[i] & kKinLeader != 0 ? lead : bar);
      }
    }
    _overviewSize = box;
    return _overviewPicture = rec.endRecording();
  }

  Widget _foot() => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Ui.line)),
    ),
    child: Padding(
      padding: DetailUi.footPad,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 보기 단계(건의 8의 4-가) — 보통 ↔ 점(V · Ctrl+휠로도).
          MotionSegmented<int>(
            value: KinScale.levels.indexOf(_s),
            options: [for (var k = 0; k < KinScale.levels.length; k++) MotionChoice(k, KinScale.levels[k].name)],
            onChanged: _ready ? (k) => _setScale(KinScale.levels[k], overview: KinScale.levels[k].dots) : null,
            label: '보기 단계',
            hint: '보기 단계 (V)',
          ),
          DetailSmallButton('모두 펼치기', onTap: _ready ? expandAll : null),
          DetailSmallButton('모두 접기', onTap: _ready ? collapseAll : null),
          // 웹 바닥의 `세대 수준` 고르기와 같은 이름(4-5 '세대 수준(n세대까지)').
          Builder(builder: (context) => DetailSmallButton('세대 수준 ▾', onTap: _ready ? () => _genMenu(context) : null)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('찾기', style: TextStyle(fontSize: 12.5, color: Ui.text2)),
              const SizedBox(width: 6),
              SizedBox(
                width: 150,
                height: 28,
                child: TextField(
                  controller: _findCtrl,
                  focusNode: _findFocus,
                  // 입력 칸에 회색 예시 글을 두지 않는다(인수인계 10절 3번) — 이름표 '찾기'가 칸 앞에 있다.
                  style: const TextStyle(fontSize: 12.5, color: Ui.text),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    filled: true,
                    fillColor: Ui.surface2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (t) {
                    _find(t);
                    _findFocus.requestFocus();
                  },
                ),
              ),
            ],
          ),
          DetailSmallButton('닫기', onTap: widget.onClose),
        ],
      ),
    ),
  );

  void _genMenu(BuildContext button) {
    final v = _view;
    if (v == null) return;
    final box = button.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height));
    unawaited(
      showTimelineMenu(context, [
        for (var g = 1; g <= math.min(v.gens, 12); g++) MenuRow('$g세대까지', onSelected: () => _setOpen(kinOpenGenerations(v, g))),
        MenuRow('모두', onSelected: expandAll),
      ], at: at),
    );
  }
}

enum _Hit { card, handle, pill, branch }

/// 지난 장면에서 그린 수(손잡이의 `built` · `lines`).
class _PaintStats {
  int cards = 0, lines = 0;
}

/// 접고 펼 때의 카드 옮김 — 앞 차례 번호 → 옛 · 새 왼쪽(판 px) · 나타남(1) · 사라짐(−1).
class _CardShift {
  _CardShift(Map<int, double> from, Map<int, double> to, Map<int, int> fade, _CardShift? prior, VoidCallback changed, {required int anchor}) {
    for (final entry in from.entries) {
      final i = entry.key, leaving = fade[i] == -1;
      final position = MotionSpring(entry.value, token: leaving ? MotionToken.snap : MotionToken.move, epsilon: .02, maxOvershoot: 4);
      positions[i] = position;
      MotionStage.instance.attach(position, changed);
      position.retarget(to[i]!);
      if (i != anchor) {
        final old = prior?.positions[i];
        if (old != null) position.kick(old.velocity);
      }
      final opacity = MotionSpring(prior?.opacity[i]?.value ?? (fade[i] == 1 ? 0 : 1), token: leaving ? MotionToken.exit : MotionToken.enter, maxOvershoot: 0);
      this.opacity[i] = opacity;
      MotionStage.instance.attach(opacity, changed);
      opacity.retarget(leaving ? 0 : 1);
      if (prior?.opacity[i] case final old?) opacity.kick(old.velocity);
    }
  }
  final positions = <int, MotionSpring>{}, opacity = <int, MotionSpring>{};
  bool get active => positions.values.any((s) => s.active) || opacity.values.any((s) => s.active);
  void dispose() {
    for (final spring in [...positions.values, ...opacity.values]) {
      MotionStage.instance.detach(spring);
    }
  }
}

/// 글 조각 캐시(LRU 600 — 4-6 '글은 문단 캐시').
class _TextCache {
  final _map = <String, TextPainter>{};

  TextPainter get(String text, TextStyle style, {double max = double.infinity}) {
    final key = '${style.fontSize}|${style.fontWeight?.value}|${style.color?.toARGB32()}|$max|$text';
    final had = _map.remove(key);
    if (had != null) {
      _map[key] = had;
      return had;
    }
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: max);
    _map[key] = p;
    if (_map.length > 600) _map.remove(_map.keys.first)!.dispose();
    return p;
  }
}

/// 보이는 카드 · 선만 그린다.
class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.view,
    required this.lay,
    required this.open,
    required this.lastChild,
    required this.pan,
    required this.topPad,
    required this.ancestor,
    required this.genOffset,
    required this.shift,
    required this.cursor,
    required this.text,
    required this.stats,
    this.scale = KinScale.normal,
  });

  final KinSkeleton view;
  final KinLayout lay;
  final Uint8List open;
  final Int32List lastChild;
  final Offset pan;
  final double topPad;
  final String ancestor;

  /// 파에서 열었을 때 세대 번호를 한 벌 세대로 적으려고 더하는 수.
  final int genOffset;
  final _CardShift? shift;
  final int cursor;
  final _TextCache text;
  final _PaintStats stats;

  /// 보기 단계(보통 · 점).
  final KinScale scale;

  static final _ink = Color.lerp(KinUi.paper, Ui.text2, .70)!;
  static const _nameStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.text);
  static const _paperName = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.text2);
  static const _subStyle = TextStyle(fontSize: 10.5, color: Ui.text2);
  static const _tagStyle = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Ui.text2);
  static const _genStyle = TextStyle(fontSize: 11, color: Ui.text3);

  double _left(int i) {
    final now = lay.x[i] > 0 ? scale.left(lay.x[i]) : null;
    final s = shift;
    if (s == null) return now ?? 0;
    return s.positions[i]?.value ?? now ?? 0;
  }

  double _top(int i) => topPad + view.gen[i] * scale.row;

  double _alpha(int i) {
    return (shift?.opacity[i]?.value ?? 1).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    stats
      ..cards = 0
      ..lines = 0;
    final vw = size.width - FamilyUi.genCol, vh = size.height;
    // 세대 번호(왼쪽 30px 칸) — 판과 함께 세로로만 움직인다.
    final g0 = math.max(0, ((pan.dy - topPad) / scale.row).floor() - 1);
    final g1 = math.min(view.gens - 1, ((pan.dy + vh - topPad) / scale.row).ceil());
    final head = text.get('세대', _genStyle);
    head.paint(canvas, Offset(0, -pan.dy));
    for (var g = g0; g <= g1; g++) {
      final p = text.get('${g + 1 + genOffset}', _genStyle);
      p.paint(canvas, Offset(22 - p.width, topPad + g * scale.row + scale.cardH / 2 - 8 - pan.dy));
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(FamilyUi.genCol, 0, vw, vh));
    canvas.translate(FamilyUi.genCol - pan.dx, -pan.dy);

    // 보이는 카드(앞 화면 ∪ 옮김 중이면 옮기는 카드).
    final lo = (pan.dx - scale.cardW).floor(), hi = (pan.dx + vw + scale.cardW).ceil();
    final cards = <int>[];
    final s = shift;
    if (s != null) {
      cards.addAll(s.positions.keys);
    } else {
      for (var g = g0; g <= g1; g++) {
        final r = lay.visibleIn(g, lo, hi, scale: scale);
        for (var k = r.start; k < r.end; k++) {
          cards.add(lay.rows[g][k]);
        }
      }
    }

    // ① 선 — 나무 부모 → 자식(빗), 부모가 화면 밖이어도 보이는 자식의 선은 긋는다.
    final linePaint = Paint()
      ..color = _ink
      ..strokeWidth = scale.dots ? 1.2 : KinUi.stroke
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final parents = <int>{};
    for (final i in cards) {
      if (s == null && kinShowsChildren(view, open, i)) parents.add(i);
      final p = view.par[i];
      if (p >= 0) parents.add(p);
    }
    for (final p in parents) {
      _comb(canvas, p, linePaint, s != null, lo, hi);
    }
    // 덧선(양자 · 둘째 부모) — 두 끝이 12칸 안이면 선, 멀면 꼬리표.
    if (s == null) _extras(canvas, linePaint, lo, hi);

    // ② 카드.
    for (final i in cards) {
      final a = _alpha(i);
      if (a <= 0) continue;
      _card(canvas, i, a);
      stats.cards++;
    }
    // 파에서 열면 맨 위 옅은 조상 한 줄.
    if (ancestor.isNotEmpty && view.n > 0) {
      final x = _left(0);
      final top = topPad - scale.row;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, top, scale.cardW, scale.cardH), Radius.circular(scale.radius));
      canvas.drawRRect(r, Paint()..color = KinUi.fade(KinUi.paper, .5));
      canvas.drawRRect(
        r.deflate(.5),
        Paint()
          ..color = KinUi.fade(Ui.lineStrong, .5)
          ..style = PaintingStyle.stroke,
      );
      final tp = text.get(ancestor, _paperName.copyWith(color: KinUi.fade(Ui.text2, .5)), max: scale.cardW - 12);
      tp.paint(canvas, Offset(x + (scale.cardW - tp.width) / 2, top + (scale.cardH - tp.height) / 2));
      canvas.drawLine(
        Offset(x + scale.cardW / 2, top + scale.cardH),
        Offset(x + scale.cardW / 2, topPad),
        Paint()
          ..color = KinUi.fade(_ink, .5)
          ..strokeWidth = KinUi.stroke,
      );
    }
    canvas.restore();
  }

  /// 부모 [p]의 빗 — 실선 자식은 세대 사이 가운데의 가로 토막 하나를 함께 쓰고, 양부 · 건너뜀 자식은 제 파선.
  void _comb(Canvas canvas, int p, Paint paint, bool moving, int lo, int hi) {
    if (!moving && !kinShowsChildren(view, open, p)) return;
    // 이름 미상은 원 하나(지름 14)라 부모 선은 원의 아래에서 나간다(건의 8의 4-다) — 점 단계는 점의 아래.
    final px = _left(p) + scale.cardW / 2, mid = _top(p) + scale.elbow;
    final pBottom = !scale.dots && view.bits[p] & kKinUnknown != 0 ? _top(p) + scale.cardH / 2 + _ring / 2 : _top(p) + scale.cardH;
    var minX = px, maxX = px;
    final last = lastChild.length > p ? lastChild[p] : -1;
    if (last < 0) return;
    var solidKids = false;
    for (var c = p + 1; c <= last; c += view.size[c]) {
      if (moving && shift!.positions[c] == null) continue;
      // 이름 미상 자식의 선은 원의 위에 바로 닿는다.
      final cx = _left(c) + scale.cardW / 2, cTop = !scale.dots && view.bits[c] & kKinUnknown != 0 ? _top(c) + scale.cardH / 2 - _ring / 2 : _top(c);
      final kind = kinEdgeKind(view.edge[c]);
      final faint = kinEdgeIsFaint(view.edge[c]);
      final q = faint ? (Paint.from(paint)..color = KinUi.fade(paint.color, .70)) : paint;
      final a = math.min(_alpha(c), 1.0);
      final pp = a < 1 ? (Paint.from(q)..color = KinUi.fade(q.color, a)) : q;
      if (cx + 1 < lo || cx - 1 > hi + scale.cardW) {
        // 화면 밖 자식 — 가로 토막만 늘인다.
        if (kind == kKinEdgeSolid) {
          minX = math.min(minX, cx);
          maxX = math.max(maxX, cx);
          solidKids = true;
        }
        continue;
      }
      if (kind == kKinEdgeSolid) {
        minX = math.min(minX, cx);
        maxX = math.max(maxX, cx);
        solidKids = true;
        canvas.drawLine(Offset(cx, mid), Offset(cx, cTop), pp);
        stats.lines++;
      } else {
        final path = Path()
          ..moveTo(px, pBottom)
          ..lineTo(px, mid)
          ..lineTo(cx, mid)
          ..lineTo(cx, cTop);
        paintDashed(canvas, path, pp, kind == kKinEdgeSkip ? KinUi.skipDash : KinUi.adoptDash);
        stats.lines++;
        if (kind == kKinEdgeSkip && !scale.dots) _tag(canvas, Offset(cx, (mid + cTop) / 2), '${view.gen[c] - view.gen[p]}대손');
      }
    }
    if (solidKids) {
      canvas.drawLine(Offset(px, pBottom), Offset(px, mid), paint);
      if (maxX > minX) canvas.drawLine(Offset(minX, mid), Offset(maxX, mid), paint);
      stats.lines += 2;
    }
  }

  void _extras(Canvas canvas, Paint paint, int lo, int hi) {
    final e = view.extra;
    for (var k = 0; k + 3 < e.length; k += 4) {
      final f = e[k], to = e[k + 1], kind = e[k + 2];
      if (lay.x[to] == 0) continue;
      final tx = _left(to), tTop = _top(to);
      if (tx + scale.cardW < lo - scale.cardW || tx > hi + scale.cardW) continue;
      if (lay.x[f] == 0) continue;
      final far = (lay.x[f] - lay.x[to]).abs() > FamilyUi.extraReach;
      if (far && scale.dots) continue; // 점 단계에는 꼬리표가 없다
      if (far) {
        // 멀면 선 대신 꼬리표 — 자식 카드에 '양가 ○○'(양부 쪽 '양자 ○○ →'는 그 카드가 보일 때).
        _tag(canvas, Offset(tx + scale.cardW / 2, tTop - 9), '양가 ${view.name[f]}');
        final fx = _left(f);
        if (fx + scale.cardW >= lo && fx <= hi) _tag(canvas, Offset(fx + scale.cardW / 2, _top(f) + scale.cardH + 9), '양자 ${view.name[to]} →');
        continue;
      }
      final ax = _left(f) + scale.cardW / 2, aBottom = _top(f) + scale.cardH;
      final mid = tTop - (scale.row - scale.cardH) / 2;
      final fromLeft = ax < tx + scale.cardW / 2;
      final ex = fromLeft ? tx - 8 : tx + scale.cardW + 8;
      final side = fromLeft ? tx : tx + scale.cardW;
      final path = Path()
        ..moveTo(ax, aBottom)
        ..lineTo(ax, mid)
        ..lineTo(ex, mid)
        ..lineTo(ex, tTop + scale.cardH / 2)
        ..lineTo(side, tTop + scale.cardH / 2);
      paintDashed(canvas, path, paint, kind == kKinEdgeSkip ? KinUi.skipDash : KinUi.adoptDash);
      stats.lines++;
      if (!scale.dots) _tag(canvas, Offset((ax + ex) / 2, mid), kind == kKinEdgeSkip ? '${e[k + 3]}대손' : '양자');
    }
  }

  void _tag(Canvas canvas, Offset c, String label) {
    final tp = text.get(label, _tagStyle);
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: tp.width + 12, height: 16), const Radius.circular(999));
    canvas.drawRRect(r, Paint()..color = Ui.surface);
    canvas.drawRRect(
      r.deflate(.5),
      Paint()
        ..color = Ui.lineStrong
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }

  void _card(Canvas canvas, int i, double alpha) {
    final x = _left(i), top = _top(i);
    final bits = view.bits[i];
    if (alpha < 1) canvas.saveLayer(Rect.fromLTWH(x - 2, top - 22, scale.cardW + 4, scale.cardH + 50), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    final rect = Rect.fromLTWH(x, top, scale.cardW, scale.cardH);
    if (scale.dots) {
      _dot(canvas, i, x, top, bits);
      if (alpha < 1) canvas.restore();
      return;
    }
    if (bits & kKinUnknown != 0) {
      // 이름 미상 — 글자 없이 원 하나(지름 14 · 종이빛 채움 · 테 2px = 선과 같은 빛 — 건의 8의 4-다 · 2026-10-13). 이름은 풍선으로.
      final c = Offset(x + scale.cardW / 2, top + scale.cardH / 2);
      canvas.drawCircle(c, _ring / 2, Paint()..color = KinUi.paper);
      canvas.drawCircle(
        c,
        _ring / 2 - 1,
        Paint()
          ..color = _ink
          ..strokeWidth = KinUi.stroke
          ..style = PaintingStyle.stroke,
      );
    } else {
      final r = RRect.fromRectAndRadius(rect, Radius.circular(scale.radius));
      final leader = bits & kKinLeader != 0;
      final c1 = _color(view.color[i]);
      if (leader && c1 != null) {
        final c2 = bits & kKinTwoPolities != 0 ? _color(view.color2[i]) : null;
        canvas.drawRRect(r, Paint()..color = KinUi.tint(c1, .36));
        if (c2 != null) {
          canvas.save();
          canvas.clipRect(Rect.fromLTWH(x + scale.cardW / 2, top, scale.cardW / 2, scale.cardH));
          canvas.drawRRect(r, Paint()..color = KinUi.tint(c2, .36));
          canvas.restore();
        }
        canvas.drawRRect(
          r.deflate(.5),
          Paint()
            ..color = Color.lerp(Ui.text3, c1, .62)!
            ..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawRRect(r, Paint()..color = KinUi.paper);
        canvas.drawRRect(
          r.deflate(.5),
          Paint()
            ..color = bits & kKinMember != 0 ? Ui.lineStrong : Ui.line
            ..style = PaintingStyle.stroke,
        );
      }
      final missing = bits & kKinMissing != 0;
      final nameStyle = leader ? _nameStyle : (missing ? _paperName.copyWith(color: Ui.text3) : _paperName);
      final sub = view.sub[i];
      final name = text.get(view.name[i], nameStyle);
      final subP = sub.isEmpty ? null : text.get(sub, _subStyle);
      final h = name.height + (subP?.height ?? 0);
      var y = top + (scale.cardH - h) / 2;
      _fitted(canvas, name, x, y, scale.cardW);
      y += name.height;
      if (subP != null) _fitted(canvas, subP, x, y, scale.cardW);
    }
    // 접는 손잡이 · 접힌 카드 아래 알약. 이름 미상의 원에는 손잡이가 없다(목업 그림 — 접기는 키보드 · 모두 접기로).
    final kids = view.size[i] > 1 || view.isStub(i);
    final ring = bits & kKinUnknown != 0;
    if (kids) {
      final shown = kinShowsChildren(view, open, i);
      if (!ring) {
        final h = text.get(shown ? '▾' : '▸', const TextStyle(fontSize: 10, color: Ui.text3));
        h.paint(canvas, Offset(x + scale.cardW - 6 - h.width, top + 3));
      }
      if (!shown) {
        final founder = bits & kKinFounder != 0 ? _branchName(i) : null;
        final n = view.isStub(i) ? (view.stubs[i]?.n ?? 1) : view.size[i];
        _tag(canvas, Offset(x + scale.cardW / 2, top + scale.cardH + 12), founder != null ? '$founder · $n명' : '후손 ${n - 1}명');
      }
    }
    // 파 이름표 — 파조 카드 윗변 바로 위 왼쪽(가운데 8px 앞까지).
    if (bits & kKinFounder != 0) {
      final name = _branchName(i);
      if (name != null) {
        final b = _branch(i);
        final dot = b == null ? Ui.text3 : (detailColor(b.color, Ui.text3));
        canvas.drawCircle(Offset(x + 4, top - 9), 3.5, Paint()..color = dot);
        final tp = text.get(name, const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Ui.text2));
        _fitted(canvas, tp, x + 11, top - 9 - tp.height / 2, scale.cardW / 2 - 8 - 11, left: true);
      }
    }
    if (i == cursor && ring) {
      // 이름 미상의 커서는 원 둘레에(카드 자리만 한 네모가 아니라).
      canvas.drawCircle(
        Offset(x + scale.cardW / 2, top + scale.cardH / 2),
        _ring / 2 + 4,
        Paint()
          ..color = Ui.accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    } else if (i == cursor) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), Radius.circular(scale.radius + 2)),
        Paint()
          ..color = Ui.accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    if (alpha < 1) canvas.restore();
  }

  /// 이름 미상 원의 지름.
  static const _ring = 14.0;

  /// 점 단계의 사람 하나(지름 12): 지도자 = 나라 색 칠(나라 색 70% + 종이 · 테 나라 색 62% + 먹) · 그 밖 = 종이빛 + 먹 40% 테 1.5px ·
  /// 이름 미상 = 먹 20% 테. 딱지 · 알약 · 파 이름표 · 손잡이는 없다(이름은 올리면 풍선).
  void _dot(Canvas canvas, int i, double x, double top, int bits) {
    final c = Offset(x + scale.cardW / 2, top + scale.cardH / 2);
    final r = scale.cardW / 2;
    final leader = bits & kKinLeader != 0;
    final c1 = leader ? _color(view.color[i]) : null;
    if (c1 != null) {
      canvas.drawCircle(c, r, Paint()..color = Color.lerp(Ui.paper, c1, .70)!);
      canvas.drawCircle(c, r - .75, Paint()
        ..color = Color.lerp(Ui.ink, c1, .62)!
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
    } else {
      canvas.drawCircle(c, r, Paint()..color = Ui.paper);
      canvas.drawCircle(c, r - .75, Paint()
        ..color = bits & kKinUnknown != 0 ? Ui.ink20 : Ui.ink40
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
    }
    if (i == cursor) {
      canvas.drawCircle(c, r + 2.5, Paint()
        ..color = Ui.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
    }
  }

  /// 가운데 맞춰(또는 [left]면 왼쪽부터) 그리되, 폭을 넘으면 끝을 옅게 한다(글이 카드 밖으로 나가지 않는다).
  void _fitted(Canvas canvas, TextPainter tp, double x, double y, double width, {bool left = false}) {
    const pad = 6.0;
    final room = left ? width : width - 2 * pad;
    if (tp.width <= room) {
      tp.paint(canvas, Offset(left ? x : x + (width - tp.width) / 2, y));
      return;
    }
    final start = left ? x : x + pad;
    final clip = Rect.fromLTWH(start, y, room, tp.height);
    canvas.saveLayer(clip, Paint());
    canvas.clipRect(clip);
    tp.paint(canvas, Offset(start, y));
    final fade = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.linear(Offset(start + room - 18, 0), Offset(start + room, 0), [Colors.black, Colors.transparent]);
    canvas.drawRect(clip, fade);
    canvas.restore();
  }

  Color? _color(int c) {
    if (c <= 0 || c >= view.colors.length) return null;
    final s = view.colors[c];
    return s.isEmpty ? null : detailColor(s);
  }

  KinBranch? _branch(int i) {
    final full = view.fullIndexOf(i);
    for (final b in view.branches) {
      if (b.at == full) return b;
    }
    final b = view.branch[i];
    return b >= 0 && b < view.branches.length ? view.branches[b] : null;
  }

  String? _branchName(int i) => _branch(i)?.name;

  @override
  bool shouldRepaint(_TreePainter old) => true;
}

/// 전체도 — 녹화해 둔 막대 그림(자리 셈이 바뀔 때만 다시 녹화) 위에 지금 보는 자리 테두리.
class _OverviewPainter extends CustomPainter {
  _OverviewPainter(this.state, this.box);
  final _FamilyWindowState state;
  final Size box;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(r, Paint()..color = KinUi.fade(Ui.surface2, .7));
    if (state._lay == null) return;
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawPicture(state._overviewOf(size));
    final s = state._overviewScale(size, state._plane);
    final view = Rect.fromLTWH(state._pan.dx * s.width, state._pan.dy * s.height, state._viewport.width * s.width, state._viewport.height * s.height);
    canvas.drawRect(
      view,
      Paint()
        ..color = Ui.accent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OverviewPainter old) => true;
}
