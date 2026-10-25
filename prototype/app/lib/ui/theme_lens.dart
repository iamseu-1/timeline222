import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/color_mix.dart';
import '../scene/marks.dart';
import '../scene/scene.dart';
import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'app_memory.dart';
import 'shell_keys.dart';

// 렌즈(주제 보기 — 10건 8 · 감독 선택 D5 결정 5 A · 6 B, 덧붙임 "렌즈 종류도 dlc 조정 가능하게")의 새 앱 몫: 고르기와 그 상태.
// 웹의 js/lens-ui.js를 옮겼다(규칙은 설계 docs/설계-10건/7-8-단체와-렌즈.md 10-2 '렌즈' · '고르기' · '단축키' · '기억').
//
//   · 자료: 항목 기록 `themes`(주제 사전 — 켠 DLC들이 더하고 · 이름을 바꾸고 · 숨긴 것까지 합친 차례)와 그 `x_lens`
//     (내보내기 `prototype/scripts/export/lens.mjs`가 미리 푼 것: 지도자 자리가 생기는 트랙 · 한마디 · 자료 있음 · 숨김 · 갈래 견본 · 사건 uid).
//   · 켠 렌즈는 bus.slot([slotThemeLens])의 주제 id 하나다 — 단추 · 차림표 · S · Shift+S · Esc · ⋯ 메뉴가 모두 이 값을 바꾸고,
//     [ThemeLensGlue]가 듣고 장면에 잇는다(줄 배치 · 켠 변형 `theme:<id>` · 사건 고리 색 · 그 주제의 사건 번호 · 기억).
//   · 띠 위의 그림은 층이 한다: 칸(paint/strips.dart의 칸 종류 8) · 옅은 지도자 칸 · 사건 옅게(paint/events.dart · rails.dart) · 부제(paint/gutter.dart).
//
// 화면 글에 실제 역사 이름은 없다. 움직임은 토큰만(120ms — `--t-micro`).

/// 내장 주제 여덟의 한마디(js/core.js의 `HT.THEME_HINTS`) — 항목 기록에 `x_lens`가 없을 때(렌즈로 말할 것이 없는 자료) 쓴다.
const themeHints = <String, String>{
  'system': '나라의 짜임', 'faction': '집권한 단체', 'law': '법 · 법전', 'election': '뽑는 방법',
  'ideology': '기준 이념', 'military': '병제', 'tax': '세금 거두는 법', 'selection': '관리 뽑는 법',
};

/// 색을 읽지 못한 주제의 색(자료의 대신 값 — 내보내기의 대신 색과 같다).
const lensNoneColor = 0xffa4b1b7;

/// 차림표의 '없음 — 지도자' 점(웹의 `NONE_C`) — 어느 주제의 색도 아닌 잉크 40%(종이 위에서 #999999 · HistoryArchive 통일).
const lensOffDot = 0xff999999;

/// 주제 하나(렌즈 하나).
@immutable
class LensTheme {
  const LensTheme({
    required this.id,
    required this.name,
    required this.color,
    this.hint = '',
    this.has = false,
    this.hidden = false,
    this.auto = false,
    this.variant = false,
    this.swatchTitle = '',
    this.swatches = const [],
    this.events = const [],
  });

  final String id, name, hint;

  /// 주제 색(0xFFRRGGBB).
  final int color;

  /// 그 렌즈로 그릴 자료가 있는가(칸이든 사건이든) · 렌즈에서 숨겼는가(켠 DLC 가운데 하나라도) · 사전에 없는 이름으로 적힌 주제인가 · 칸 변형이 있는가.
  final bool has, hidden, auto, variant;

  /// 갈래 견본(제목 · [이름, 색]) — 같은 색은 나라 너머 같은 갈래(붕당을 단체로 그리면 단체 색).
  final String swatchTitle;
  final List<(String, int)> swatches;

  /// 그 주제의 사건 uid(공동 사건의 다른 자리 `#n` 포함 — 타일의 사건 번호로 바꿔 쓴다).
  final List<String> events;

  /// 차림표에 나오는가: 숨긴 주제는 빼고, 사전에 없는 이름으로 적힌 주제는 자료가 있을 때만(웹의 `HT.lensThemes`).
  bool get inMenu => !hidden && (!auto || has);
}

/// 렌즈 차림표의 자료 — 항목 기록 `themes` 하나를 읽은 것.
@immutable
class LensBook {
  const LensBook(this.themes, this.slot);

  static const empty = LensBook([], {});

  /// 주제 사전의 차례(내장 여덟 → DLC가 더한 주제) — 숨긴 주제 · 사전 밖 주제도 든다(차림표는 [menu]).
  final List<LensTheme> themes;

  /// 렌즈 켬 배치에서 지도자 자리가 생기는 트랙(트랙의 글자 id).
  final Set<String> slot;

  /// 차림표에 낼 주제(차례 그대로).
  List<LensTheme> get menu => [for (final t in themes) if (t.inMenu) t];

  /// 차림표에 있는 주제 가운데 그 id(없거나 숨었으면 null).
  LensTheme? byId(String id) {
    if (id.isEmpty) return null;
    for (final t in themes) {
      if (t.id == id) return t.inMenu ? t : null;
    }
    return null;
  }

  /// 앞뒤로 넘기기(S · Shift+S): 없음 → 주제들 → 없음 … — 자료 있는 주제가 하나라도 있으면 자료 없는 주제는 건너뛴다(웹의 `step`).
  String step(String now, int dir) {
    final all = menu;
    final withData = [for (final t in all) if (t.has) t];
    final ring = ['', for (final t in (withData.isNotEmpty ? withData : all)) t.id];
    final at = math.max(0, ring.indexOf(now));
    return ring[(at + (dir < 0 ? ring.length - 1 : 1)) % ring.length];
  }

  /// `{"op":"entity","uid":"themes"}`의 답(`{uid, kind, json}`) 또는 그 본문(Map) — 읽지 못하면 [empty].
  static LensBook read(Object? answer) {
    Map? body;
    try {
      if (answer is Map && answer['json'] is String) {
        body = jsonDecode(answer['json'] as String) as Map?;
      } else if (answer is Map && answer['json'] is Map) {
        body = answer['json'] as Map;
      } else if (answer is Map && answer['list'] is List) {
        body = answer;
      }
    } catch (_) {
      body = null;
    }
    final list = body?['list'];
    if (list is! List) return empty;
    final x = body?['x_lens'];
    final extra = <String, Map>{};
    if (x is Map && x['themes'] is List) {
      for (final one in x['themes'] as List) {
        if (one is Map && one['id'] is String) extra[one['id'] as String] = one;
      }
    }
    final themes = <LensTheme>[];
    for (final one in list) {
      if (one is! Map || one['id'] is! String) continue;
      final id = one['id'] as String;
      final more = extra[id] ?? const {};
      final sw = more['sw'];
      themes.add(
        LensTheme(
          id: id,
          name: '${one['name'] ?? id}'.isEmpty ? id : '${one['name'] ?? id}',
          color: _hex(one['color']),
          hint: more['hint'] is String ? more['hint'] as String : (themeHints[id] ?? ''),
          has: more['has'] == 1 || more['has'] == true,
          hidden: more['hidden'] == 1 || more['hidden'] == true,
          auto: one['auto'] == 1 || one['auto'] == true,
          variant: more['v'] == 1 || more['v'] == true,
          swatchTitle: sw is Map && sw['t'] is String ? sw['t'] as String : '',
          swatches: [
            if (sw is Map && sw['l'] is List)
              for (final f in sw['l'] as List)
                if (f is List && f.length >= 2 && f[0] is String && f[1] is num) (f[0] as String, 0xff000000 | (f[1] as num).toInt()),
          ],
          events: [if (more['ev'] is List) for (final u in more['ev'] as List) if (u is String) u],
        ),
      );
    }
    final slot = <String>{if (x is Map && x['slot'] is List) for (final k in x['slot'] as List) if (k is String) k};
    return LensBook(List.unmodifiable(themes), slot);
  }

  static int _hex(Object? text) {
    if (text is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) return 0xff000000 | int.parse(text.substring(1), radix: 16);
    if (text is num) return 0xff000000 | text.toInt();
    return lensNoneColor;
  }
}

/// 렌즈를 장면에 잇는 것. [bus]의 [slotThemeLens]를 듣고(단추 · 차림표 · 단축키 · ⋯ 메뉴가 바꾼다) 배치 · 표시 상태 · 기억을 맞춘다.
class ThemeLensGlue extends ChangeNotifier {
  ThemeLensGlue({required this.bus});

  final AppBus bus;
  TimelineScene get scene => bus.scene;

  /// 차림표의 자료(저장소를 다시 지으면 [load]로 새로).
  LensBook book = LensBook.empty;
  bool _loaded = false;
  AppMemory? _memory;

  /// 렌즈 단추의 자리 — 차림표가 그 아래에 열린다(⋯ 메뉴 · 단축키로 열 때도).
  final buttonKey = GlobalKey(debugLabel: '렌즈 단추');

  /// 차림표가 열려 있는가(단추의 눌린 모습).
  bool menuOpen = false;

  /// 사건 번호를 묻는 차례(늦게 온 옛 답을 버린다).
  int _asked = 0;

  /// 지금 켠 렌즈(꺼져 있으면 null).
  LensTheme? get current => book.byId(scene.layout.themeLens);

  /// 듣기 시작하고 차림표의 자료를 읽는다.
  void start() {
    bus.slot(slotThemeLens).addListener(_onSlot);
    bus.slot(slotCommand).addListener(_onCommand);
    unawaited(load());
  }

  @override
  void dispose() {
    bus.slot(slotThemeLens).removeListener(_onSlot);
    bus.slot(slotCommand).removeListener(_onCommand);
    super.dispose();
  }

  /// 항목 기록 `themes`를 (다시) 읽는다 — 저장소를 다시 지었으면(DLC 더하기 · 빼기) 부른다. 켠 렌즈의 주제가 사라지거나 숨었으면 끈다.
  Future<void> load() async {
    LensBook next = LensBook.empty;
    try {
      next = LensBook.read(await bus.ask({'op': 'entity', 'uid': 'themes'}));
    } catch (_) {
      next = LensBook.empty; // 주제 사전이 없는 저장소(옛 저장소) — 차림표는 내장 여덟만 '자료 없음'으로
    }
    if (next.themes.isEmpty) {
      next = LensBook([for (final e in themeHints.entries) LensTheme(id: e.key, name: _builtinNames[e.key] ?? e.key, color: lensNoneColor, hint: e.value)], const {});
    }
    book = next;
    _loaded = true;
    // 저장소를 다시 지었으면 사건 번호가 바뀌었다 — 켠 렌즈가 그대로여도 그 주제의 사건 번호를 다시 묻는다.
    _apply(_wanted(), fresh: true);
  }

  /// 기억을 잇는다 — 기억해 둔 렌즈가 있고 아직 아무것도 켜지 않았으면 그 렌즈를 켠다(그 주제가 없거나 숨었으면 끄고 기억도 지운다).
  void attachMemory(AppMemory memory) {
    _memory = memory;
    final saved = memory.parts['themeLens']?['id'];
    final now = _wanted();
    if (now.isNotEmpty) {
      // 기억이 오기 전에 켠 렌즈가 이긴다 — 차림표를 아직 못 읽었으면 읽은 뒤의 잇기(_apply)가 적는다.
      if (_loaded) _remember(book.byId(now)?.id ?? '');
    } else if (saved is String && saved.isNotEmpty) {
      bus.slot(slotThemeLens).value = saved;
    }
  }

  /// 렌즈를 켜고 끈다(빈 글이면 끔).
  void set(String id) => bus.slot(slotThemeLens).value = id.isEmpty ? null : id;

  /// 앞뒤로 넘기기(S · Shift+S).
  void step(int dir) => set(book.step(scene.layout.themeLens, dir));

  String _wanted() {
    final v = bus.slot(slotThemeLens).value;
    return v is String ? v : '';
  }

  void _onSlot() {
    if (_loaded) _apply(_wanted());
  }

  void _onCommand() {
    final command = bus.slot(slotCommand).value;
    if (command is! AppCommand) return;
    switch (command.name) {
      case Cmd.lensNext:
        step(1);
      case Cmd.lensPrev:
        step(-1);
      case Cmd.lensMenu:
        openMenu();
    }
  }

  /// 렌즈 차림표를 단추 아래에 연다(단추가 아직 없으면 아무 일도 없다).
  Future<void> openMenu() async {
    final at = buttonKey.currentContext;
    if (at == null || !at.mounted || menuOpen) return;
    menuOpen = true;
    notifyListeners();
    try {
      await showLensMenu(at, this);
    } finally {
      menuOpen = false;
      notifyListeners();
    }
  }

  /// 켠 렌즈를 장면에 잇는다. 차림표에 없는 주제(사라졌거나 숨김)면 끄고 기억도 지운다.
  /// [fresh]면 달라진 것이 없어도 사건 번호를 다시 묻는다(저장소를 다시 지은 뒤 — 번호가 바뀐다).
  void _apply(String want, {bool fresh = false}) {
    final theme = book.byId(want);
    final id = theme?.id ?? '';
    if (want.isNotEmpty && theme == null) {
      bus.slot(slotThemeLens).value = null; // 듣개가 다시 불려 끈 상태로 온다
      _remember('');
      return;
    }
    final s = scene;
    final marks = SceneMarks.of(s);
    // 빈 줄 접기의 물음(rows_near)은 변형을 보지 않으므로 접힘은 그대로다 — 다시 쌓기가 아는 답으로 그 자리에서 다시 셈한다(folder.recheck).
    final changed = s.applyThemeLens(id, slots: book.slot);
    final color = theme == null ? 0 : theme.color & 0xffffff;
    if (changed || fresh || marks.lensColor != color) {
      marks
        ..lensColor = color
        ..lensEvents = null;
      marks.version++;
      unawaited(_askEvents(theme));
    }
    _remember(id);
    s.requestFrame();
    notifyListeners();
  }

  /// 그 주제의 사건 uid → 타일의 사건 번호(`ids_of` — 한 번에 2000개까지). 사건이 없는 주제는 빈 묶음(모든 사건이 옅어진다).
  Future<void> _askEvents(LensTheme? theme) async {
    final ticket = ++_asked;
    if (theme == null) return;
    final ids = <int>{};
    final uids = theme.events;
    for (int at = 0; at < uids.length; at += 2000) {
      try {
        final answer = await bus.ask({'op': 'ids_of', 'uids': uids.sublist(at, math.min(uids.length, at + 2000))});
        final events = answer['events'];
        if (events is List) {
          for (final e in events) {
            if (e is Map && e['id'] is num) ids.add((e['id'] as num).toInt());
          }
        }
      } catch (_) {
        // 묻지 못한 묶음은 건너뛴다(그 사건은 옅게 남는다).
      }
      if (ticket != _asked) return;
    }
    if (ticket != _asked) return;
    final marks = SceneMarks.of(scene);
    marks.lensEvents = ids;
    marks.version++;
    scene.requestFrame();
  }

  void _remember(String id) {
    final m = _memory;
    if (m == null) return;
    final had = m.parts['themeLens']?['id'];
    if ((had is String ? had : '') == id) return;
    if (id.isEmpty) {
      m.parts.remove('themeLens');
    } else {
      m.parts['themeLens'] = {'id': id};
    }
    m.save();
  }

  /// 내장 주제의 이름(주제 사전이 없는 옛 저장소에서만 쓴다 — js/core.js의 `HT.THEMES`).
  static const _builtinNames = <String, String>{
    'system': '체제', 'faction': '붕당', 'law': '법률', 'election': '선거제도',
    'ideology': '이념', 'military': '군사제도', 'tax': '조세제도', 'selection': '선발제도',
  };
}

// ──────────────────────────────── 단추 ────────────────────────────────

/// 위 단추 줄(독)의 '◎ 렌즈' 단추 — 필터 단추 다음(감독 선택 D5 결정 6 B). 켠 동안 주제 색으로 '◎ 렌즈 · 주제 ✕'(✕를 누르면 끔, 나머지는 차림표).
class LensDockButton extends StatefulWidget {
  const LensDockButton({super.key, required this.glue});
  final ThemeLensGlue glue;

  @override
  State<LensDockButton> createState() => _LensDockButtonState();
}

class _LensDockButtonState extends State<LensDockButton> {
  // 기호만(건의 8의 1번 꼴 A · 눈동자): 차림표가 열렸거나 렌즈를 켠 동안은 반전 채움, 켠 동안은 오른쪽 위에 주제 색 점(1-다 '색 점만').
  // 주제 이름 · 끄기(✕)는 단추에서 빠졌다 — 이름은 풍선과 차림표의 체크로, 끄기는 차림표의 '없음' · Esc로. 스크린 리더 이름은 예전 그대로.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.glue,
    builder: (context, _) {
      final glue = widget.glue, theme = glue.current;
      return DockIconButton(
        key: glue.buttonKey,
        glyph: LineGlyph.eye,
        on: glue.menuOpen || theme != null,
        dot: theme == null ? null : Color(0xff000000 | theme.color),
        onPressed: glue.openMenu,
        tooltip: theme == null ? '렌즈 (S)' : '렌즈 · ${theme.name} (S)',
        semantics: theme == null ? '렌즈 — 지도자 칸 자리에 주제(체제 · 법률 · 조세제도 …)의 칸 (S)' : '렌즈 ${theme.name} 켜짐 — 렌즈 차림표',
      );
    },
  );
}

// ──────────────────────────────── 차림표 ────────────────────────────────

/// 렌즈 차림표를 [anchor](단추) 아래 8px에 연다(웹의 `place` — 화면 밖으로 나가지 않게 4px 안으로). 바깥을 누르거나 Esc로 닫힌다.
Future<void> showLensMenu(BuildContext anchor, ThemeLensGlue glue) {
  final box = anchor.findRenderObject() as RenderBox?;
  final at = box == null ? Offset.zero : box.localToGlobal(Offset(0, box.size.height + 8));
  return Navigator.of(anchor, rootNavigator: true).push(_LensMenuRoute(glue: glue, at: at));
}

/// 이 차림표에서 키보드를 썼는가 — 초점이 간 줄을 칠할지 가린다(⋯ 메뉴와 같은 규칙: 마우스로 열면 켠 줄에 초점이 가도 칠하지 않는다).
final _lensKeyboard = ValueNotifier<bool>(false);

class _LensMenuRoute extends PopupRoute<void> {
  _LensMenuRoute({required this.glue, required this.at});
  final ThemeLensGlue glue;
  final Offset at;

  @override
  void install() {
    _lensKeyboard.value = false;
    super.install();
  }

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '렌즈 차림표 닫기';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondary) => CustomSingleChildLayout(
    delegate: _LensMenuLayout(at),
    child: Material(
      type: MaterialType.transparency,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) _lensKeyboard.value = true;
          return KeyEventResult.ignored;
        },
        child: LensMenuCard(glue: glue),
      ),
    ),
  );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) =>
      FadeTransition(opacity: animation.drive(CurveTween(curve: Ui.ease)), child: child);
}

class _LensMenuLayout extends SingleChildLayoutDelegate {
  const _LensMenuLayout(this.at);
  final Offset at;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.loose(Size(constraints.maxWidth - 8, constraints.maxHeight - 8));

  @override
  Offset getPositionForChild(Size size, Size child) =>
      Offset(math.max(4, math.min(at.dx, size.width - child.width - 4)), math.max(4, math.min(at.dy, size.height - child.height - 4)));

  @override
  bool shouldRelayout(_LensMenuLayout old) => old.at != at;
}

/// 차림표의 몸(웹의 `.ctx-menu.lens-menu`): 머리 · 없음 — 지도자(Esc) · 주제(색 점 · 이름 · 한마디 · 자료 없음) · 켠 렌즈의 갈래 견본 · 앞뒤로 넘기기.
/// 렌즈가 바뀌면(앞뒤로 넘기기) 그 자리에서 다시 그린다.
class LensMenuCard extends StatelessWidget {
  const LensMenuCard({super.key, required this.glue});
  final ThemeLensGlue glue;

  /// 갈래 견본을 몇 개까지 보이는가(웹과 같은 12 — 넘으면 '외 n').
  static const maxSwatches = 12;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: glue,
    builder: (context, _) {
      final now = glue.current;
      final rows = <Widget>[
        const _LensTitle('렌즈'),
        _LensItem(
          name: '없음',
          color: lensOffDot,
          checked: now == null,
          keyText: 'Esc',
          autofocus: now == null,
          onTap: () {
            glue.set('');
            Navigator.of(context).pop();
          },
        ),
        const _LensSep(),
        for (final t in glue.book.menu)
          _LensItem(
            name: t.name,
            color: t.color,
            hint: t.hint,
            empty: !t.has,
            checked: now?.id == t.id,
            autofocus: now?.id == t.id,
            onTap: () {
              glue.set(t.id);
              Navigator.of(context).pop();
            },
          ),
      ];
      if (now != null && now.swatches.isNotEmpty) {
        rows
          ..add(const _LensSep())
          ..add(_LensTitle(now.swatchTitle))
          ..add(_LensSwatches(now.swatches, max: maxSwatches));
      }
      rows
        ..add(const _LensSep())
        ..add(_LensItem(name: '렌즈 앞뒤로 넘기기', keyText: 'S · Shift+S', onTap: () => glue.step(1)));
      // 차림표의 틀은 ⋯ 차림표(ui/context_menu.dart)와 같다 — 종이 + 1px 선 · 둥근 12 · 안쪽 여백 4(HistoryArchive 통일).
      return GlassCard(
        radius: Ui.menuRadius,
        color: Ui.detailGlass,
        shadow: Ui.shadow,
        blur: Ui.blurSoft,
        padding: const EdgeInsets.all(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 420),
          child: SingleChildScrollView(
            child: IntrinsicWidth(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
          ),
        ),
      );
    },
  );
}

class _LensTitle extends StatelessWidget {
  const _LensTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Ui.text3, letterSpacing: .44, height: 1.5)),
  );
}

class _LensSep extends StatelessWidget {
  const _LensSep();
  @override
  Widget build(BuildContext context) => Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), color: Ui.line);
}

/// 갈래 견본(웹의 `.lens-fam span` — 12px 글 · 둥근 4(딱지) · 바탕 = 그 색 30% · 안쪽 1px 테 = 그 색 70% — 갈래 색은 자료라 그대로).
class _LensSwatches extends StatelessWidget {
  const _LensSwatches(this.list, {required this.max});
  final List<(String, int)> list;
  final int max;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 4, 10, 8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final (name, color) in list.take(max))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Color(mixSrgb(color, Ui.surface.toARGB32(), .30)),
                borderRadius: BorderRadius.circular(Ui.innerRadius),
                border: Border.all(color: Color(withAlpha(color, .70))),
              ),
              child: Text(name, style: const TextStyle(fontSize: 12, color: Ui.text, height: 1.5)),
            ),
          if (list.length > max)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text('외 ${list.length - max}', style: const TextStyle(fontSize: 12, color: Ui.text3, height: 1.5)),
            ),
        ],
      ),
    ),
  );
}

/// 차림표 한 줄(웹의 `.ctx-item.lens-item` — 왼쪽 26px에 ✓ · 색 점 9px · 이름 · 작은 한마디 · 단축키).
class _LensItem extends StatefulWidget {
  const _LensItem({required this.name, required this.onTap, this.color, this.hint = '', this.empty = false, this.checked = false, this.keyText = '', this.autofocus = false});
  final String name, hint, keyText;
  final int? color;
  final bool empty, checked, autofocus;
  final VoidCallback onTap;

  @override
  State<_LensItem> createState() => _LensItemState();
}

class _LensItemState extends State<_LensItem> {
  bool _hover = false, _focus = false;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k != LogicalKeyboardKey.enter && k != LogicalKeyboardKey.space && k != LogicalKeyboardKey.numpadEnter) return KeyEventResult.ignored;
    widget.onTap();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(valueListenable: _lensKeyboard, builder: (context, keyboard, _) => _build(keyboard));

  Widget _build(bool keyboard) {
    final lit = _hover || (_focus && keyboard);
    // 올림은 잉크 8% 깔개 · 글은 그대로(⋯ 차림표와 같다 — HistoryArchive 통일. 전에는 강조색 채움 + 흰 글이었다).
    const text = Ui.text, small = Ui.text3;
    final dot = widget.color;
    final body = Container(
      padding: const EdgeInsets.fromLTRB(26, 6, 10, 6),
      decoration: BoxDecoration(color: lit ? Ui.ink8 : null, borderRadius: BorderRadius.circular(Ui.innerRadius)),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Color(dot),
                shape: BoxShape.circle,
                border: Border.all(color: Color(mixOklab(dot, Ui.text.toARGB32(), .70))),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: widget.name, style: TextStyle(fontSize: 13, color: text, height: 1.5)),
                  if (widget.hint.isNotEmpty) ...[
                    const WidgetSpan(child: SizedBox(width: 6)),
                    TextSpan(text: widget.hint, style: TextStyle(fontSize: 11.5, color: small, height: 1.5)),
                  ],
                  if (widget.empty) ...[
                    const WidgetSpan(child: SizedBox(width: 6)),
                    TextSpan(text: '자료 없음', style: TextStyle(fontSize: 11, color: small.withValues(alpha: small.a * .8), height: 1.5)),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.keyText.isNotEmpty) ...[
            const SizedBox(width: 14),
            Text(widget.keyText, style: TextStyle(fontSize: 11, color: small, letterSpacing: .26, height: 1.77)),
          ],
        ],
      ),
    );
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      onFocusChange: (on) => setState(() => _focus = on),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          selected: widget.checked,
          label: widget.name,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: widget.checked
                ? Stack(
                    children: [
                      body,
                      Positioned(
                        left: 9,
                        top: 6,
                        child: const Text('✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Ui.accent, height: 1.5)),
                      ),
                    ],
                  )
                : body,
          ),
        ),
      ),
    );
  }
}
