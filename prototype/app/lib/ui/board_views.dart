import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../scene/color_mix.dart';
import '../scene/layout.dart';
import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'app_memory.dart';
import 'date_text.dart' show minutesOfT;
import 'detail_shell.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  집합 보기(10건 6 · 감독 선택 D4 결정 1 A · 2 A · 4 B · 5 A)의 새 앱 화면 부품
//  — 설계 docs/설계-10건/6-모아-보기와-배치.md 9절(웹) · 11절(새 앱). 웹은 js/views-ui.js · js/timeline.js의 setBoard.
//
//  새 앱은 스스로 다시 배치하지 못한다: 판마다 '판을 켠 배치'를 내보내기(`export/boards.mjs`)가 미리 셈해 변형 kind 3(`view:<id>`)으로 싣고,
//  엔진이 나르고, 이 부품은 켜고 끄기만 한다(보기 상태 `ViewState.board` → `scene/layout.dart`가 판 트랙을 맨 위에 쌓고 나머지 트랙을 접는다).
//
//  · 독의 '🗂 집합 보기' 단추(결정 4 B): 판이 하나도 없는 저장소에서는 숨는다(켜 둔 임시 판이 있으면 보임 — 끌 수 있게).
//    켠 판이 있으면 판 이름 · 판 색. 누르면 독 아래 목록.
//  · 목록: 판마다 스위치 · 이름 · DLC 표시 · '나라 n · 트랙 m(· 찾지 못한 나라 k)'. 켜 둔 임시 판은 맨 위 '저장하지 않은 판'.
//    연표(보기 전용)는 켜고 끄기만 한다 — 판을 만들고 고치는 일은 메이커(결정 3).
//  · 시대 구분 창의 '이 시대의 나라' 카드(결정 5 A): 그 시대의 나라 칩 · 스위치 = 저장하지 않은 임시 판(`view:epoch:<시대 구분 uid>`).
//    **칩으로 빼고 넣기 · 다른 트랙 나라 더하기는 앱에 없다** — 조합마다 배치가 달라 미리 실을 수 없어서, 내보내기는 기본 후보 그대로의 판
//    하나만 싣는다(보고의 결정 기록). 칩은 그 나라를 보여 주기만 한다.
//  · 켠 DLC 판은 기억한다(`parts['board']` — 다시 열면 보던 범위 그대로 되살림). 임시 판은 기억하지 않는다.
//  · 켜면 판의 기간으로 날아가고(양쪽 12% · 적어도 2년 — 웹 setBoard의 fly) 판의 머리가 화면 맨 위로, 끄면 켜기 전에 보던 세로 자리로.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 판에 든 나라 하나(판 기록의 `members[]`).
@immutable
class BoardMember {
  const BoardMember(this.uid, this.name, this.color, this.track, this.trackName);
  final String uid, name, track, trackName;
  final int color;
}

/// 판 하나 — 저장소의 변형(kind 3)과 판 기록(`board:<열쇠>` — 내보내기 `export/boards.mjs`)을 합친 것.
@immutable
class BoardInfo {
  const BoardInfo({
    required this.key,
    required this.name,
    required this.color,
    this.temp = false,
    this.label = '',
    this.present = 0,
    this.tracks = 0,
    this.missing = 0,
    this.start,
    this.end,
    this.packName = '',
    this.epoch = '',
    this.epochTrack = '',
    this.scoped = false,
    this.members = const [],
  });

  /// 변형의 열쇠(`view:<id>` · 임시 판은 `view:epoch:<시대 구분 uid>`).
  final String key;
  final String name, label, packName, epoch, epochTrack;
  final int color, present, tracks, missing;

  /// 저장하지 않은 임시 판(시대 구분의 카드)인가.
  final bool temp;

  /// 이어진 대범위가 있는 시대 구분의 카드인가(제목이 '그 밖의 나라').
  final bool scoped;

  /// 판의 기간(해) — 없으면 켜도 보던 시기 그대로 모으기만 한다.
  final double? start, end;
  final List<BoardMember> members;

  /// 판 기록의 JSON(엔진 `entity`의 `json`을 푼 것)과 변형 하나로. 기록이 없으면 변형의 이름 · 버터 색으로.
  factory BoardInfo.of(VariantInfo v, Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    int colorOf(Object? c) {
      if (c is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c)) return int.parse(c.substring(1), radix: 16);
      if (c is num) return c.toInt();
      return butter;
    }

    double? num0(Object? x) => x is num ? x.toDouble() : null;
    final members = <BoardMember>[
      for (final m in (j['members'] as List? ?? const []))
        if (m is Map) BoardMember('${m['uid'] ?? ''}', '${m['name'] ?? ''}', colorOf(m['color']), '${m['track'] ?? ''}', '${m['trackName'] ?? ''}'),
    ];
    return BoardInfo(
      key: v.key,
      name: '${j['name'] ?? v.name}',
      color: colorOf(j['color']),
      temp: j['temp'] == 1 || j['temp'] == true || v.key.startsWith(epochPrefix),
      label: '${j['label'] ?? ''}',
      present: (j['present'] as num?)?.toInt() ?? members.length,
      tracks: (j['tracks'] as num?)?.toInt() ?? 0,
      missing: (j['missing'] as num?)?.toInt() ?? 0,
      start: num0(j['start']),
      end: num0(j['end']) ?? num0(j['start']),
      packName: '${j['packName'] ?? ''}',
      epoch: '${j['epoch'] ?? ''}',
      epochTrack: '${j['epochTrack'] ?? ''}',
      scoped: j['scoped'] == 1 || j['scoped'] == true,
      members: members,
    );
  }

  /// 판의 기본 색 — 파스텔 열두 가지의 버터(js/views-ui.js의 BUTTER).
  static const butter = 0xd7c18e;

  /// 시대 구분 임시 판의 열쇠 머리.
  static const epochPrefix = 'view:epoch:';

  /// 목록의 작은 글 — '나라 n · 트랙 m(· 찾지 못한 나라 k)'(웹 countText · tempHTML).
  String get countText => '나라 ${members.isNotEmpty ? members.length : present} · 트랙 $tracks${missing > 0 ? ' · 찾지 못한 나라 $missing' : ''}';
}

/// 집합 보기의 상태와 길 — 앱 틀(archive_app.dart)이 하나 지어 `bus.slot(BoardViews.slotName)`에 둔다.
/// 판을 실제로 켜고 끄는 일(보기 상태 · 다시 쌓기)은 [apply]가 한다.
class BoardViews extends ChangeNotifier {
  BoardViews({required this.bus, required this.apply, this.memory});

  /// 부품이 이 객체를 찾는 슬롯 이름.
  static const slotName = 'board_views';

  static BoardViews? of(AppBus bus) {
    final v = bus.slot(slotName).value;
    return v is BoardViews ? v : null;
  }

  final AppBus bus;

  /// 판을 켜고(열쇠) 끈다(빈 글) — 다시 쌓았으면 참. [hold]는 다시 쌓는 동안 붙잡을 줄(번호 · 화면 맨 위에서 그 줄 위까지 —
  /// 번호 −1이면 붙잡지 않음 — 장면의 `applyViewState`).
  final bool Function(String key, (int, double) hold) apply;

  /// 켠 DLC 판의 기억(측정 모드에서는 없다).
  AppMemory? Function()? memory;

  /// 독 단추와 목록을 잇는 고리(목록이 단추의 왼쪽 아래에 매달린다).
  final link = LayerLink();
  final dockKey = GlobalKey();

  final _info = <String, BoardInfo>{};
  String _signature = '';
  bool _listOpen = false;

  /// 판을 켜기 전에 화면 맨 위에 있던 줄(번호 · 거리 — 끄면 그 줄로 돌아온다 · 지금 연표의 `_boardBack`). 맨 위에 있었으면 null.
  (int, double)? _back;

  SceneLayout get _layout => bus.scene.layout;

  /// 목록이 열려 있는가.
  bool get listOpen => _listOpen;

  /// 지금 켠 판의 열쇠(없으면 빈 글).
  String get activeKey => _layout.board?.key ?? '';

  /// 지금 켠 판(없으면 null).
  BoardInfo? get active {
    final v = _layout.board;
    return v == null ? null : _info[v.key] ?? BoardInfo.of(v, null);
  }

  /// DLC가 준 판(임시 판 빼고 · 저장소의 차례).
  List<BoardInfo> get saved => [
    for (final v in _layout.boards)
      if (!v.key.startsWith(BoardInfo.epochPrefix)) _info[v.key] ?? BoardInfo.of(v, null),
  ];

  /// 그 시대 구분의 임시 판(없으면 null — 후보 나라가 없거나 옛 저장소).
  BoardInfo? epochBoard(String epochUid) {
    final key = '${BoardInfo.epochPrefix}$epochUid';
    for (final v in _layout.boards) {
      if (v.key == key) return _info[key] ?? BoardInfo.of(v, null);
    }
    return null;
  }

  /// 판 기록을 다시 읽는다 — 처음 한 번과 저장소를 다시 지었을 때(판 목록이 달라졌으면). 실패한 기록은 변형의 이름으로 둔다.
  Future<void> load() async {
    final boards = _layout.boards;
    final signature = boards.map((v) => v.key).join('\n');
    if (signature == _signature && _info.length == boards.length) return;
    _signature = signature;
    _info.removeWhere((key, _) => !boards.any((v) => v.key == key));
    for (final v in boards) {
      Map<String, dynamic>? json;
      try {
        final answer = await bus.ask({'op': 'entity', 'uid': 'board:${v.key}'});
        final text = answer['json'];
        if (text is String && text.isNotEmpty) json = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (_) {}
      _info[v.key] = BoardInfo.of(v, json);
    }
    notifyListeners();
  }

  /// 판 하나를 켠다. [fly]면 판의 기간으로 날아간다(기억에서 되살릴 때는 보던 범위 그대로).
  /// [reveal]이면 판의 머리를 화면 맨 위로 — 기억에서 되살릴 때(저장소를 다시 지은 뒤 포함)는 세로 자리도 그대로 둔다.
  void turnOn(String key, {bool fly = true, bool remember = true, bool reveal = true}) {
    if (key.isEmpty) return turnOff();
    final was = activeKey;
    if (was == key) return;
    final c = bus.controller;
    final back = was.isEmpty ? _held() : _back; // 끄면 켜기 전에 보던 줄로(판을 바꿔 켜면 처음 켜기 전의 줄 그대로)
    // 판의 머리를 화면 맨 위로(지금 연표의 `_boardReveal`) — 아무 줄도 붙잡지 않고 다시 쌓은 뒤 맨 위로 올린다.
    if (!apply(key, (-1, 0))) return;
    _back = back;
    if (reveal) c.scrollTo(0);
    final info = _info[key];
    if (remember) _remember(info != null && info.temp ? '' : key);
    if (fly && info != null && info.start != null) {
      final s = info.start!, e = (info.end ?? s) < s ? s : (info.end ?? s);
      final pad = ((e - s) * .12).clamp(2.0, double.infinity); // 판의 기간이 화면 안쪽에 넉넉히(양쪽 12% · 적어도 2년)
      bus.goTo(minutesOfT(s - pad), minutesOfT(e + pad));
    }
    notifyListeners();
  }

  /// 켠 판을 끈다 — 켜기 전에 보던 세로 자리로.
  void turnOff() {
    if (activeKey.isEmpty) return;
    final back = _back;
    _back = null;
    // 켜기 전에 맨 위에 있던 줄을 붙잡고 다시 쌓는다 — 흐르는 동안에도 그 줄이 같은 자리로 온다(맨 위였으면 맨 위로).
    apply('', back ?? (-1, 0));
    if (back == null) bus.controller.scrollTo(0);
    _remember('');
    notifyListeners();
  }

  /// 지금 화면 맨 위의 줄(번호 · 화면 맨 위에서 그 줄 위까지). 맨 위(세로 0)에 있으면 null.
  (int, double)? _held() {
    final top = bus.controller.view.top;
    if (top <= 0) return null;
    final row = _layout.rowAt(top);
    return row < 0 ? null : (row, _layout.rowTop(row) - top);
  }

  /// 판 하나를 켜고 끈다(목록의 스위치 · 시대 구분 카드의 스위치).
  void toggle(String key) => activeKey == key ? turnOff() : turnOn(key);

  void openList() {
    if (_listOpen) return;
    _listOpen = true;
    notifyListeners();
  }

  void closeList() {
    if (!_listOpen) return;
    _listOpen = false;
    notifyListeners();
  }

  void toggleList() => _listOpen ? closeList() : openList();

  /// 기억에서 켠 DLC 판을 되살린다(날아가지 않음 — 보던 범위 그대로). 판이 사라졌으면 기억을 지운다.
  void restore() {
    final key = memory?.call()?.parts['board']?['key'];
    if (key is! String || key.isEmpty) return;
    if (!_layout.boards.any((v) => v.key == key) || key.startsWith(BoardInfo.epochPrefix)) {
      _remember('');
      return;
    }
    turnOn(key, fly: false, remember: false, reveal: false);
  }

  void _remember(String key) {
    final m = memory?.call();
    if (m == null) return;
    final now = m.parts['board']?['key'];
    if ((now ?? '') == key) return;
    if (key.isEmpty) {
      m.parts.remove('board');
    } else {
      m.parts['board'] = {'key': key};
    }
    m.save();
  }

  /// 판 목록이 바뀌었을 수 있다(저장소를 다시 지음) — 켠 판이 사라졌으면 기억도 함께 정리하고 기록을 다시 읽는다.
  void layoutChanged() {
    if (activeKey.isEmpty) _back = null;
    // 같은 판 열쇠라도 DLC를 다시 가져오면 이름 · 색 · 기간 · 구성 나라가 바뀔 수 있다.
    _signature = '';
    unawaited(load());
    notifyListeners();
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 독의 단추
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 독의 '🗂 집합 보기' 단추(결정 4 B — 필터 앞). 판이 하나도 없으면 자리도 차지하지 않는다.
class BoardDockButton extends StatelessWidget {
  const BoardDockButton({super.key, required this.views});
  final BoardViews views;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: views,
    builder: (context, _) {
      final on = views.active;
      if (views.saved.isEmpty && on == null) return const SizedBox.shrink();
      // 기호만(건의 8의 1번 꼴 A · 겹친 판): 목록이 열렸거나 판을 켠 동안은 반전 채움. 판 이름은 풍선과 목록의 체크로만.
      final body = DockIconButton(
        glyph: LineGlyph.layers,
        on: views.listOpen || on != null,
        onPressed: views.toggleList,
        tooltip: on == null ? '집합 보기' : '집합 보기 · ${on.name}',
        semantics: on == null ? '집합 보기 — 멀리 떨어진 나라들을 한 판에 모아 견주기' : '집합 보기 «${on.name}» 켜짐 — 눌러 목록(끄기 · 다른 판)',
      );
      return Padding(
        padding: const EdgeInsets.only(right: Ui.dockIconGap),
        child: CompositedTransformTarget(key: views.dockKey, link: views.link, child: body),
      );
    },
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 독 아래 목록
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 독 아래 목록 층(앱 틀의 Stack을 덮는다 — 바깥을 누르면 닫힘 · Esc는 목록만 닫음). 닫혀 있으면 아무것도 없다.
class BoardListLayer extends StatelessWidget {
  const BoardListLayer({super.key, required this.views});
  final BoardViews views;

  /// 목록의 폭 · 단추에서의 자리(css `.views-pop` — js placePop: 폭 min(440, 창 − 24) · 단추 왼쪽 −12 · 아래 +10).
  static const width = 440.0, offset = Offset(-12, 10);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: views,
    builder: (context, _) {
      if (!views.listOpen) return const SizedBox.shrink();
      final screen = MediaQuery.sizeOf(context);
      final anchor = views.dockKey.currentContext?.findRenderObject() as RenderBox?;
      final point = anchor?.localToGlobal(Offset.zero) ?? Offset.zero;
      final cardWidth = width.clamp(0.0, screen.width - 24);
      // B의 오른쪽 독 단추에서도 목록은 화면 안 · 맨 위 줄 아래 10px에 둔다(웹 placePop과 같은 경계).
      final dx = offset.dx.clamp(12 - point.dx, screen.width - 12 - cardWidth - point.dx).toDouble();
      final dy = (Ui.top - point.dy - (anchor?.size.height ?? Ui.buttonHeight)).clamp(0.0, double.infinity) + offset.dy;
      return Stack(
        children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: views.closeList)),
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: views.link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: Offset(dx, dy),
              showWhenUnlinked: false,
              child: _BoardList(views: views),
            ),
          ),
        ],
      );
    },
  );
}

class _BoardList extends StatefulWidget {
  const _BoardList({required this.views});
  final BoardViews views;

  @override
  State<_BoardList> createState() => _BoardListState();
}

class _BoardListState extends State<_BoardList> {
  final _focus = FocusNode(debugLabel: '집합 보기 목록');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views = widget.views;
    final saved = views.saved;
    final active = views.active;
    final temp = active != null && active.temp ? active : null;
    final screen = MediaQuery.sizeOf(context);
    final width = BoardListLayer.width.clamp(0.0, screen.width - 24);
    return Focus(
      focusNode: _focus,
      // Esc는 목록만 닫는다(연표의 Esc — 상세 창 닫기 · 고르기 풀기로 번지지 않게 — 웹의 붙잡는 단계 처리와 같은 뜻).
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          views.closeList();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TweenAnimationBuilder<double>(
        // 떠오름(--t-in · 아래로 4px에서) — 움직임 토큰만.
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: Motion.enter.round()),
        curve: Ui.ease,
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, -4 * (1 - t)), child: child)),
        child: SizedBox(
          width: width,
          child: GlassCard(
            radius: Ui.menuRadius,
            blur: Ui.blurWide,
            shadow: Ui.shadow,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: (screen.height - Ui.top - 26).clamp(160.0, double.infinity)),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('집합 보기', style: TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w700, color: Ui.text)),
                          const SizedBox(height: 2),
                          Text(
                            '${saved.isNotEmpty ? '판 ${saved.length}개 · ' : ''}한 번에 하나 — 켜면 그 나라들의 줄이 맨 위로 모이고 나머지 트랙은 접힙니다',
                            style: const TextStyle(fontSize: 11, height: 1.45, color: Ui.text3),
                          ),
                        ],
                      ),
                    ),
                    if (temp != null) BoardRow(views: views, info: temp),
                    for (final b in saved) BoardRow(views: views, info: b),
                    if (saved.isEmpty && temp == null)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 4, 6, 2),
                        child: Text('켠 DLC가 준 집합 보기가 없습니다.', style: TextStyle(fontSize: 12.5, height: 1.55, color: Ui.text3)),
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
}

/// 목록의 한 줄(css `.vw-row` — 높이 44 이상 · 안쪽 4/6 · 둥근 10 · 켜면 판 색 14%): 스위치 · 이름 · DLC 표시 · 수.
class BoardRow extends StatefulWidget {
  const BoardRow({super.key, required this.views, required this.info});
  final BoardViews views;
  final BoardInfo info;

  @override
  State<BoardRow> createState() => _BoardRowState();
}

class _BoardRowState extends State<BoardRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final info = widget.info, views = widget.views;
    final on = views.activeKey == info.key;
    final c = Color(0xff000000 | info.color);
    final bg = on ? c.withValues(alpha: .14) : (_hover ? Ui.ink8 : const Color(0x00000000));
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: Motion.micro.round()),
        curve: Ui.ease,
        margin: const EdgeInsets.only(bottom: 2),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Ui.controlRadius)),
        child: Row(
          children: [
            BoardSwitch(
              on: on,
              color: c,
              label: '집합 보기 ${info.name}',
              tooltip: info.temp ? '${info.name} — 끄기(저장하지 않은 판이라 사라짐)' : '${info.name} — ${on ? '끄기' : '켜기'}',
              onTap: () => views.toggle(info.key),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text)),
                      ),
                      const SizedBox(width: 6),
                      if (info.temp)
                        _Tag('저장하지 않은 판', c.withValues(alpha: .30), Ui.text)
                      else if (info.packName.isNotEmpty)
                        _Tag(info.packName, Ui.text3.withValues(alpha: Ui.text3.a * .14), Ui.text2),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(info.countText, style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// DLC 표시 · '저장하지 않은 판' 딱지(css `.vw-dlc` — 높이 17 · 둥근 5 · 10px/600 · 폭 160까지).
class _Tag extends StatelessWidget {
  const _Tag(this.text, this.bg, this.fg);
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    height: 17,
    constraints: const BoxConstraints(maxWidth: 160),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Ui.innerRadius)),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, height: 1.7, fontWeight: FontWeight.w600, color: fg)),
  );
}

/// 집합 보기 스위치(대범위 스위치 `.scope-switch`와 같은 꼴 — 높이 28 · 28×16 손잡이 · 켜면 제 색 18% 바탕).
/// [text]를 주면 손잡이 뒤에 글과 '켬 · 끔'(시대 구분 카드), 없으면 손잡이만(목록 `.vw-switch` — 좌우 6).
class BoardSwitch extends StatefulWidget {
  const BoardSwitch({super.key, required this.on, required this.color, required this.onTap, required this.label, this.tooltip, this.text});
  final bool on;
  final Color color;
  final VoidCallback onTap;
  final String label;
  final String? tooltip, text;

  @override
  State<BoardSwitch> createState() => _BoardSwitchState();
}

class _BoardSwitchState extends State<BoardSwitch> {
  bool _hover = false;

  static const _duration = Duration(milliseconds: 200); // css의 --t-in

  @override
  Widget build(BuildContext context) {
    final on = widget.on, c = widget.color;
    final bg = on ? Color(mixSrgb(c.toARGB32(), Ui.surface2Solid.toARGB32(), .18)) : Ui.surface2;
    final ring = on ? c.withValues(alpha: .45) : Ui.line;
    final knobTrack = on ? Color(mixSrgb(c.toARGB32(), Ui.text.toARGB32(), .80)) : Ui.text3.withValues(alpha: Ui.text3.a * .30);
    final text = widget.text;
    Widget body = AnimatedOpacity(
      duration: Duration(milliseconds: Motion.micro.round()),
      opacity: _hover ? .92 : 1,
      child: AnimatedContainer(
        duration: _duration,
        curve: Ui.ease,
        height: 28,
        padding: EdgeInsets.only(left: 6, right: text == null ? 6 : 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: ring)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: _duration,
              curve: Ui.ease,
              width: 28,
              height: 16,
              decoration: BoxDecoration(color: knobTrack, borderRadius: BorderRadius.circular(999)),
              child: AnimatedAlign(
                duration: _duration,
                curve: Ui.ease,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                    color: Ui.surface,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            if (text != null) ...[
              const SizedBox(width: 7),
              Text(text, style: TextStyle(fontSize: 12.5, height: 1.5, color: on ? Ui.text : Ui.text2)),
              const SizedBox(width: 7),
              Text(on ? '켬' : '끔', style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3)),
            ],
          ],
        ),
      ),
    );
    if (widget.tooltip != null) body = Tooltip(message: widget.tooltip!, child: body);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        toggled: on,
        label: widget.label,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: body),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 시대 구분 창의 '이 시대의 나라' 카드(결정 5 A)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 시대 구분 창의 카드 — 그 시대 구분의 임시 판이 저장소에 있을 때만(후보 나라가 없으면 내보내기가 싣지 않는다).
/// 이어진 대범위 카드 바로 아래(웹 epochCardHTML과 같은 자리). 칩은 보여 주기만 하고(누르면 그 나라의 상세), 스위치가 임시 판을 켜고 끈다.
class BoardEpochCard extends StatelessWidget {
  const BoardEpochCard({super.key, required this.bus, required this.epochUid});
  final AppBus bus;
  final String epochUid;

  @override
  Widget build(BuildContext context) {
    final views = BoardViews.of(bus);
    if (views == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: views,
      builder: (context, _) {
        final info = views.epochBoard(epochUid);
        if (info == null || info.members.isEmpty) return const SizedBox.shrink();
        final on = views.activeKey == info.key;
        final c = Color(0xff000000 | info.color);
        return DetailBox(
          title: info.scoped ? '그 밖의 나라' : '이 시대의 나라',
          small: '${info.members.length}',
          children: [
            DetailChipRow([
              for (final m in info.members) DetailChip(m.name, color: Color(mixSrgb(0xff000000 | m.color, Ui.surface2Solid.toARGB32(), .22)), onTap: () => bus.select(m.uid)),
            ], top: 0),
            const SizedBox(height: 10),
            Row(
              children: [
                BoardSwitch(
                  on: on,
                  color: c,
                  label: '집합 보기 ${info.name}',
                  text: '집합 보기',
                  tooltip: '켜면 이 시대의 기간으로 가서 이 나라들을 맨 위 한 판에 모읍니다',
                  onTap: () => views.toggle(info.key),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              on ? '저장하지 않은 판입니다 — 끄면 사라지고 켜기 전 모습으로 돌아갑니다.' : '켜면 이 시대의 기간으로 가서 나라들을 맨 위 한 판에 모읍니다. 끄면 제자리로.',
              style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3),
            ),
          ],
        );
      },
    );
  }
}
