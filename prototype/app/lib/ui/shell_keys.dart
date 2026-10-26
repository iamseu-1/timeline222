import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../motion.dart';
import '../shell/motion_widgets.dart';
import '../shell/parts.dart';
import 'app_bus.dart';

// 단축키 · 집중 모드 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md`의 8-1 · 8-3.
// 이 부품은 AppBus 하나만 받아 혼자 선다: 누른 키는 bus.slot('command')에 명령 하나로 실리고, 집중 모드는 bus.slot('zen')의 참/거짓이다.
// 무엇을 할지는 듣는 쪽(검색 · 필터 시트 · 도구 · 상세 창)이 정한다 — 여기는 "무엇을 하라고 했는가"만 싣는다.

/// [AppBus.slot]에 쓰는 이름: 명령 한 번 · 집중 모드(참/거짓) · 알림 한 줄(글).
const slotCommand = 'command', slotZen = 'zen', slotNotice = 'notice';

/// `⋯` 메뉴의 '글자 › ClearType' 줄이 싣는 새 값(참/거짓). 이어 붙이기(`ui/app_glue.dart`)가 듣고 설정 · 기억 · 장면에 옮긴다.
/// 메뉴 파일이 이어 붙이기 파일을 불러오지 않게(서로 불러오는 고리) 메뉴와 함께 쓰는 이 파일에 둔다.
const slotClearType = 'clearType';

/// 렌즈(주제 보기 — 감독 선택 D5 결정 6 B): 켠 주제 id(글) 또는 null. 렌즈 부품(`ui/theme_lens.dart`)이 듣고 장면에 잇는다.
/// Esc의 차례(메뉴 · 차림표 → 검색 칸 → 창 → **렌즈** → 집중 모드)를 여기서 보려고 이 파일에 둔다.
const slotThemeLens = 'themeLens';

/// 단체 계보 창이 떠 있는지 보는 슬롯(ui/group_tree.dart의 `groupTreeSlot`과 같은 글 — 그 파일을 불러오지 않으려고 글로 둔다).
const _groupTreeSlot = 'groupTree';

/// 집중 모드에 들어갈 때의 안내 한 줄(명세 8-3).
const zenNotice = '집중 모드 — Z 또는 왼쪽 위 삼선 단추로 돌아옵니다. 오른쪽 클릭으로 메뉴를 열 수 있습니다.';

/// 명령 이름. 단축키 · 메뉴 · 듣는 쪽이 모두 이 표만 본다.
abstract final class Cmd {
  static const filter = 'filter'; // ☰ 필터·표시 설정 바를 여닫는다
  static const year = 'year'; // 📍 같은 해 보기 (at이 있으면 그때에 무슨 일이)
  static const legend = 'legend'; // ❔ 범례
  static const table = 'table'; // 📋 표 보기
  static const image = 'image'; // 📷 이미지·인쇄
  static const measure = 'measure'; // 📏 기간 재기 켜고 끄기
  static const bird = 'bird'; // ↕ 조감 ↔ 직전 밀도
  static const foldAll = 'foldAll'; // ▾ 모든 트랙 접기/펴기
  static const dlc = 'dlc'; // 🧩 자료집(DLC) 관리
  static const map = 'map'; // 지도(부품이 있을 때만)
  static const wiki = 'wiki'; // 📄 고른 항목(uid)의 문서
  static const search = 'search'; // 🔍 검색 칸으로 초점
  static const fit = 'fit'; // ⤢ 전체 보기 (메뉴 줄 — 키 0은 연표가 처리한다)
  static const detail = 'detail'; // 자세히 보기(uid)
  static const focusOn = 'focusOn'; // 🎯 여기로 확대(uid)
  static const scope = 'scope'; // 대범위 모아 보기 켜고 끄기(uid)
  static const scopeState = 'scopeState'; // 그릇의 네 상태(uid · arg: 'open' 펼침 · 'shelf' 선반 · 'closed' 접음 · 'loose' 풂 — 그릇 안 오른쪽 클릭)
  static const fold = 'fold'; // 트랙 하나 접기/펴기(trackId)
  static const trackWiki = 'trackWiki'; // 트랙 문서(trackId)
  static const succession = 'succession'; // 승계선 — arg: 'all' · 'direct' · 'off'
  static const motion = 'motion'; // ◔ 움직임 계측 · 느리게 보기
  static const close = 'close'; // Esc — 떠 있는 창을 닫는다
  static const searchClose = 'search.close'; // Esc — 검색 칸을 비우고 초점을 놓는다
  static const lensNext = 'lensNext'; // ◎ 렌즈 다음(S) — 없음 → 주제들 → 없음
  static const lensPrev = 'lensPrev'; // ◎ 렌즈 앞(Shift+S)
  static const lensMenu = 'lensMenu'; // ◎ 렌즈 차림표(⋯ 메뉴의 한 줄 — 단추 아래에 연다)

  /// 집중 모드. 이것만은 명령이 아니라 상태다 — [setZen]이 bus.slot('zen')을 바꾼다(메뉴의 딱지 · 단축키 글에만 쓴다).
  static const zen = 'zen';

  /// 메뉴에 적는 단축키 글(명세 8-1의 표). 없는 명령은 빈 글.
  static const keyLabel = <String, String>{
    filter: 'F', year: 'Y', legend: 'L', table: 'T', image: 'P', measure: 'R', bird: 'V', foldAll: 'A',
    dlc: 'D', map: 'M', wiki: 'W', search: '/', fit: '0', zen: 'Z', lensMenu: 'S',
  };
}

/// 단축키 · 메뉴가 낸 명령 한 번. 같은 명령을 연달아 내도 새 객체라 듣는 쪽이 두 번 다 받는다
/// (ValueNotifier는 같은 값이면 알리지 않으므로 이름만 실으면 두 번째 누름이 사라진다).
@immutable
class AppCommand {
  const AppCommand(this.name, this.seq, {this.uid, this.trackId, this.at, this.arg});

  /// [Cmd]의 이름 가운데 하나.
  final String name;

  /// 이 앱이 낸 몇 번째 명령인가(검사와 기록용).
  final int seq;

  /// 메뉴를 연 자리에서 모아 온 것: 누른 항목 · 트랙 · 그 자리의 때(분).
  final String? uid;
  final int? trackId;
  final double? at;

  /// 명령에 딸린 값 — 승계선은 'all' · 'direct' · 'off'.
  final String? arg;

  @override
  String toString() => name;
}

int _seq = 0;

/// 명령 하나를 [bus]에 싣는다. 단축키와 메뉴가 같은 길을 쓴다.
AppCommand runCommand(AppBus bus, String name, {String? uid, int? trackId, double? at, String? arg}) {
  final command = AppCommand(name, ++_seq, uid: uid, trackId: trackId, at: at, arg: arg);
  bus.slot(slotCommand).value = command;
  return command;
}

/// 지금 집중 모드인가.
bool zenOf(AppBus bus) => bus.slot(slotZen).value == true;

/// 집중 모드를 켜고 끈다. 들어갈 때에만 안내 한 줄을 알린다(명세 8-3).
void setZen(AppBus bus, bool on) {
  if (zenOf(bus) == on) return;
  bus.slot(slotZen).value = on;
  if (on) bus.slot(slotNotice).value = zenNotice;
}

/// 초점이 글 칸(입력 칸)에 있는가 — 글을 치는 동안에는 글자가 단축키가 되지 않는다(명세 8-1).
bool typingNow() {
  final where = FocusManager.instance.primaryFocus?.context;
  if (where == null) return false;
  return where.widget is EditableText || where.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// 단축키를 받는 껍데기. **연표보다 바깥(위)에** 두어야 한다 — 연표가 이미 처리한 키(`0 + − ← → Esc`)는
/// 여기까지 올라오지 않으므로 같은 키가 두 번 실행되지 않는다(명세 9 ㈐-20).
class ShellKeys extends StatefulWidget {
  const ShellKeys({super.key, required this.bus, required this.child, this.hasMap = false, this.escape = true, this.windowOpen});

  final AppBus bus;
  final Widget child;

  /// 지도 부품이 있을 때만 `M`을 받는다(명세 8-1).
  final bool hasMap;

  /// Esc를 초점과 상관없이 창 전체에서 먼저 받을 것인가. 연표가 Esc를 제 것(움직임 멈춤)으로 쓰므로
  /// 초점이 연표에 있으면 다른 길로는 영영 오지 않는다. 앱 틀(`shell/app_shell.dart`)에도 같은 처리가 있으니 **둘 가운데 하나만** 켠다.
  final bool escape;

  /// 떠 있는 창(상세 · 도구)이 있는가 — Esc의 셋째 차례. 주지 않으면 고른 것이 있는지로 본다.
  final bool Function()? windowOpen;

  @override
  State<ShellKeys> createState() => ShellKeysState();
}

class ShellKeysState extends State<ShellKeys> {
  /// 글자 키 → 명령. `0 + − ← →`는 연표의 몫이라 여기에 없다.
  /// (LogicalKeyboardKey가 `==`를 제 것으로 두어 const 표의 열쇠가 되지 못하므로 final이다.)
  static final _table = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.keyF: Cmd.filter,
    LogicalKeyboardKey.keyY: Cmd.year,
    LogicalKeyboardKey.keyL: Cmd.legend,
    LogicalKeyboardKey.keyT: Cmd.table,
    LogicalKeyboardKey.keyP: Cmd.image,
    LogicalKeyboardKey.keyR: Cmd.measure,
    LogicalKeyboardKey.keyV: Cmd.bird,
    LogicalKeyboardKey.keyA: Cmd.foldAll,
    LogicalKeyboardKey.keyD: Cmd.dlc,
    LogicalKeyboardKey.keyZ: Cmd.zen,
    LogicalKeyboardKey.keyW: Cmd.wiki,
    LogicalKeyboardKey.keyM: Cmd.map,
    LogicalKeyboardKey.slash: Cmd.search,
    LogicalKeyboardKey.keyS: Cmd.lensNext, // Shift와 함께면 앞 렌즈(_key)
  };

  @override
  void initState() {
    super.initState();
    if (widget.escape) HardwareKeyboard.instance.addHandler(_escape);
  }

  @override
  void dispose() {
    if (widget.escape) HardwareKeyboard.instance.removeHandler(_escape);
    super.dispose();
  }

  /// 명령 하나를 낸다 — 검사와 메뉴가 함께 쓴다.
  AppCommand run(String name, {String? uid, int? trackId, double? at, String? arg}) =>
      runCommand(widget.bus, name, uid: uid, trackId: trackId, at: at, arg: arg);

  /// 집중 모드를 뒤집는다(`Z` · 메뉴 · ☰).
  void toggleZen() => setZen(widget.bus, !zenOf(widget.bus));

  bool get _windowOpen => widget.windowOpen?.call() ?? (widget.bus.selection.value != null);

  /// Esc의 차례: 메뉴 · 대화 상자 → 검색 칸 → 창 → 집중 모드(명세 9 ㈐-19).
  /// 메뉴와 대화 상자는 제 길(길라잡이 route)이 먼저 닫으므로 여기서는 비켜 준다.
  bool _escape(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape || !mounted) return false;
    if (Navigator.maybeOf(context)?.canPop() ?? false) return false;
    if (typingNow()) {
      run(Cmd.searchClose);
      FocusManager.instance.primaryFocus?.unfocus();
      return true;
    }
    if (_windowOpen) {
      run(Cmd.close);
      return true;
    }
    // 단체 계보 창(ui/group_tree.dart의 groupTreeSlot — 닫기 = 슬롯 비우기)이 떠 있으면 그 창이 먼저(웹 차례: 상세 창 → 계보 창 → 렌즈 → 집중 모드).
    // 계보 창 층의 제 Esc 듣개는 이미 닫힌 창에 아무것도 하지 않으므로 겹쳐 닫지 않는다(설계 7-8 12-4의 이음 ②).
    if (widget.bus.slot(_groupTreeSlot).value != null) {
      widget.bus.slot(_groupTreeSlot).value = null;
      return true;
    }
    // 렌즈를 켰으면 끈다 — 창보다 뒤 · 집중 모드보다 앞(감독 선택 D5 결정 6 · 설계 7-8 10-2 '단축키'). 차림표는 제 길(길라잡이)이 먼저 닫는다.
    final lens = widget.bus.slot(slotThemeLens).value;
    if (lens is String && lens.isNotEmpty) {
      widget.bus.slot(slotThemeLens).value = null;
      return true;
    }
    if (zenOf(widget.bus)) {
      setZen(widget.bus, false);
      return true;
    }
    return false;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    // 누르고 있는 동안의 되풀이는 받지 않는다 — 창이 여닫히며 깜빡이지 않게.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    // Alt가 눌렸으면 아무것도 하지 않고, Ctrl · ⌘은 창(브라우저 자리의 것)에 넘긴다. 글을 치는 동안에도 쉰다.
    if (keyboard.isAltPressed || keyboard.isControlPressed || keyboard.isMetaPressed || typingNow()) return KeyEventResult.ignored;
    var name = _table[event.logicalKey];
    if (name == null || (name == Cmd.map && !widget.hasMap)) return KeyEventResult.ignored;
    if (name == Cmd.lensNext && keyboard.isShiftPressed) name = Cmd.lensPrev;
    if (name == Cmd.zen) {
      // 집중 모드만은 명령이 아니라 상태다(명세 8-3).
      toggleZen();
      return KeyEventResult.handled;
    }
    if (name == Cmd.wiki) {
      // 문서는 고른 항목의 것이다 — 고른 것이 없으면 문서 대문(문서 창이 uid 없는 명령을 대문으로 받는다).
      final picked = widget.bus.selection.value;
      if (picked == null) {
        run(Cmd.wiki);
      } else {
        run(Cmd.wiki, uid: picked.uid);
      }
      return KeyEventResult.handled;
    }
    run(name);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(onKeyEvent: _key, canRequestFocus: false, skipTraversal: true, child: widget.child);
}

/// 집중 모드에서 위로 70px 물러나며 사라지는 껍데기 — 알약 창 · 필터 시트를 이것으로 감싼다
/// (명세 8-3: `transform .4s var(--ease)` · `opacity .3s`).
class ZenHide extends StatelessWidget {
  const ZenHide({super.key, required this.bus, required this.child, this.away = 70});

  final AppBus bus;
  final Widget child;

  /// 물러나는 거리(px).
  final double away;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    valueListenable: bus.slot(slotZen),
    builder: (context, value, inner) {
      final on = value == true;
      return IgnorePointer(
        ignoring: on,
        child: MotionValue(
          target: on ? -away : 0,
          maxOvershoot: 0,
          builder: (context, dy, body) => Transform.translate(offset: Offset(0, dy), child: body),
          child: MotionValue(
            target: on ? 0 : 1,
            enter: MotionToken.enter, exit: MotionToken.exit, maxOvershoot: 0,
            builder: (context, value, child) => Opacity(opacity: value.clamp(0.0, 1.0), child: child),
            child: inner,
          ),
        ),
      );
    },
    child: child,
  );
}

/// 집중 모드에서만 왼쪽 위에 남는 34×34 `☰`(불투명도 .75 · 올리면 1). 누르면 집중 모드를 나간다.
/// 자리는 부르는 쪽이 잡는다(지금 연표는 왼쪽 위 8, 8).
class ZenExitButton extends StatefulWidget {
  const ZenExitButton({super.key, required this.bus});
  final AppBus bus;

  @override
  State<ZenExitButton> createState() => _ZenExitButtonState();
}

class _ZenExitButtonState extends State<ZenExitButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    valueListenable: widget.bus.slot(slotZen),
    builder: (context, value, _) {
      if (value != true) return const SizedBox.shrink();
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          label: '집중 모드 나가기',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setZen(widget.bus, false),
            child: Opacity(
              opacity: _hover ? 1 : .75,
              child: GlassCard(
                radius: Ui.menuRadius,
                blur: Ui.blurLight,
                child: const SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(child: LineIcon(LineGlyph.menu, size: Ui.dockIcon, color: Ui.ink)),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
