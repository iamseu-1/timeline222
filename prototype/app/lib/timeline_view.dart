import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'scene/aux_calendar.dart';
import 'scene/axis_model.dart';
import 'scene/cleartype.dart' show ClearTypeBaker;
import 'scene/cleartype_prefs.dart';
import 'scene/glyph_atlas.dart';
import 'scene/hit_test.dart';
import 'scene/layout.dart' show ScopeState;
import 'scene/marks.dart';
import 'scene/paint/gutter.dart';
import 'scene/paint/host_folders.dart';
import 'scene/paint/links.dart';
import 'scene/paint/scopes.dart' show FlagSpot, ScopeIn;
import 'scene/painter.dart';
import 'scene/text_paragraph.dart';
import 'scene/scene.dart';
import 'ui/context_menu.dart' show menuLongPress;

/// 동군연합 이음줄의 맞히기 표시(Hit.ref) — 승계선의 선 맞히기와 가른다.
const unionHitRef = 'union';

/// 짝 꼬리표(트랙을 건너는 승계 — 구역 60 · 이어 주는 선 걸음 4)의 맞히기 표시: 선 맞히기(Hit.ref)에 이 머리글 + '<0 앞 끝 · 1 뒤 끝>:<상대 uid>' —
/// 앱 틀이 누르면 상대 띠로 날아간다(archive_app `_flyToCross`).
const crossTagHitRef = 'cross:';

// 연표 화면: 입력을 조작부에 넘기고, 장면은 전용 그리기 하나로 그린다. 사건마다 화면 부품을 만들지 않는다.
// 시계(Ticker)는 장면이 바쁜 동안(움직임 · 떠오름 · 글줄 준비)만 돈다.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.scene,
    this.onlyDevice,
    this.onHit,
    this.onPill,
    this.onGutterHit,
    this.onAxisCell,
    this.onAxisTip,
    this.onHotCell,
    this.axisState,
    this.onAxisState,
    this.atlasText = true,
  });
  final TimelineScene scene;

  /// 글자 방식: 참이면 (나) 그림판에 찍어 두고 묶어 그리기(기본 — '라' 관문에서 고름), 거짓이면 (가) 글줄 보관.
  final bool atlasText;

  /// 끌지 않고 누른 것을 알린다 — 사건(점 · 이름 · 막대) · 알약 · 띠 · 칸 …. 빈 곳이면 `HitKind.none`에 누른 자리의 때(분)를 lo · hi로 실어 보낸다
  /// (상세 창 닫기 · 같은 해 보기의 기준선 옮기기 — 명세 7-02. 반올림하지 않은 그 자리 그대로).
  final void Function(Hit hit)? onHit;

  /// 개수 알약 위로 손이 올라왔다(그 알약과 손의 자리) · 벗어났다(null) — 묶음 카드가 듣는다. 바뀔 때만 알린다.
  final void Function(Hit? pill, Offset at)? onPill;

  /// 왼쪽 칸에서 누른 것(트랙 이름 · 민족 칸 · 줄 이름 · 노선 표시 · 분류 점) — 그림판을 가로지르는 문화권 머리 단과 그 밑 사람 띠도 이 길로 온다.
  final void Function(GutterHit hit)? onGutterHit;

  /// 날짜 칸에서 누른 칸(시대 구분 · 연호 · 도읍). 묶음 여닫기 같은 날짜 칸 제 일은 이 화면이 바로 한다.
  final void Function(AxisHit hit)? onAxisCell;

  /// 날짜 칸에서 커서가 올라간 칸의 도움말(글 · 그 칸의 왼쪽 끝 · 커서의 y — 모두 배치 px). 걷을 때는 빈 글이 온다.
  /// 띄우는 것은 앱 틀의 몫이다(날짜 칸은 위젯이 아니라 그림이라 `Tooltip`을 붙일 곳이 없다).
  final void Function(String tip, double x, double y)? onAxisTip;

  /// 커서가 올라간 칸의 열쇠(`'<띠 번호>|<칸 참조>'` — StripHit.key)가 바뀌었다(벗어나면 null). 앱 틀이 같은 사람의 칸을 찾아
  /// [SceneMarks.hotTwins]에 싣는다(건의 8의 6-나).
  final void Function(String? cell)? onHotCell;

  /// 기억해 둔 날짜 칸의 상태(열어 둔 묶음 · 접은 연호 · 펼친 배도 · 보조 달력 · 표시 넷) — 열 때 한 번 되돌린다.
  final Map<String, dynamic>? axisState;

  /// 사람이 날짜 칸의 무엇을 바꿨다 — 앱 틀이 `AppMemory.parts['axis']`에 적는다.
  final void Function(Map<String, dynamic> state)? onAxisState;

  /// 측정 모드: 이 장치 번호의 입력(측정기의 합성 입력)만 받는다 — 재는 동안 사람 손의 휠 · 마우스가 장면을 바꾸지 않게.
  final int? onlyDevice;
  @override
  State<TimelineView> createState() => TimelineViewState();
}

class TimelineViewState extends State<TimelineView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final TimelinePainter _painter = TimelinePainter(widget.scene, text: widget.atlasText ? AtlasText(baker: _openBaker()) : ParagraphText());
  Duration _last = Duration.zero;
  double _pinchFrom = 1;
  TimelineScene get scene => widget.scene;
  TimelineController get c => widget.scene.controller;

  /// 글자 굽개를 연다. 있는지 없는지는 `⋯` 차림표가 'ClearType' 줄을 보일지 가르는 데 쓰므로 설정에도 적어 둔다(DLL을 차림표가 다시 열지 않게).
  static ClearTypeBaker? _openBaker() {
    final baker = ClearTypeBaker.open();
    ClearTypePrefs.bakerReady = baker != null;
    return baker;
  }

  @override
  void initState() {
    super.initState();
    scene.busy.addListener(_syncTicker);
    c.active.addListener(_dropCoalWhenMoving);
    _syncTicker();
  }

  @override
  void dispose() {
    scene.busy.removeListener(_syncTicker);
    c.active.removeListener(_dropCoalWhenMoving);
    _ticker.dispose();
    _painter.text.dispose();
    super.dispose();
  }

  void _syncTicker() {
    if (scene.busy.value && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!scene.busy.value && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    scene.tick(dt);
  }

  /// 층마다의 맞히기를 겹침 차례대로 한곳에 모은다(scene/hit_test.dart의 HitSources). 층의 답을 Hit으로 옮겨 적는다:
  /// 칸은 ref에 칸 참조('leader:3' …)를, 가리키는 항목이 따로 있으면(왕조 · 기관 · 예속 안 칸) `@uid`를 싣고, 인물은 ref에 uid(묶음이면 빈 글), 이름표는 `@속국 uid`.
  late final HitSources _sources = HitSources(
    marks: [
      // 집합 보기 판 이름표(판 트랙 머리 — 다른 것과 겹치지 않는다): 누르면 집합 보기 목록(지금 연표의 data-board-name).
      (x, y) => _painter.scopes.hitBoardLabel(x, y) ? const Hit(HitKind.scopeButton, ref: ScopeIn.boardRef) : null,
      // 그릇 폴더의 탭(리메이크 조각 ③): 라벨 — 펼침 ↔ 접힘(누름 번호를 줄 칸에 — 1 펼침 · 2 접힘 · 3 풀림 · 4 선반 · 5 가지 접기 뒤집기
      // (선반 기억에 든 그릇 — `ScopeLayer.pressFold`). 앱 틀은 `ScopeLayer.actionOf`로만 가른다).
      // 소속 폴더의 라벨(리메이크 4단계 과제 8 걸음 3)은 소속 펼치기 단추와 같은 맞히기(memberButton · 상국 띠) — 누르면 소속을 접는다.
      (x, y) {
        final host = _painter.scopes.hitHostFolder(x, y);
        if (host != null) return HostFolders.pressOf(scene.layout, host);
        final h = _painter.scopes.hitFolder(x, y);
        return h == null ? null : Hit(HitKind.scopeButton, ref: h.$1, row: h.$2);
      },
      (x, y) {
        final h = _painter.links.hitCrossTag(x, y) ?? _painter.links.hitLinks(x, y);
        if (h == null) return null;
        return switch (h.kind) {
          LinkHitKind.square => Hit(HitKind.square, bandId: h.band),
          LinkHitKind.link => Hit(HitKind.link, bandId: h.band, itemId: h.to),
          LinkHitKind.memberButton => Hit(HitKind.memberButton, bandId: h.band),
          LinkHitKind.scopeButton => Hit(HitKind.scopeButton, bandId: h.band, ref: h.scope, row: h.to),
          LinkHitKind.hangButton => Hit(HitKind.hangButton, bandId: h.band, row: h.to),
          LinkHitKind.flag => Hit(HitKind.flag, bandId: h.band),
          LinkHitKind.crossTag => Hit(HitKind.link, bandId: h.band, itemId: h.to, ref: '$crossTagHitRef${h.scope}'),
        };
      },
      // 동군연합 이음줄(건의 8의 6-다): 승계선과 같은 '선' 맞히기(두 띠) — 올리면 그 줄이 짙어지고 풍선 글이 뜬다.
      (x, y) {
        final h = _painter.unions.hitUnion(x, y);
        return h == null ? null : Hit(HitKind.link, bandId: h.$1, itemId: h.$2, ref: unionHitRef);
      },
    ],
    rails: [
      (x, y) {
        final h = _painter.rails.hitRails(x, y);
        return h == null ? null : Hit(HitKind.event, eventId: h.eventId, row: h.row, bandId: h.band);
      },
    ],
    figures: [
      (x, y) {
        final h = _painter.figures.hitFigures(x, y);
        return h == null ? null : Hit(HitKind.figure, row: h.row, bandId: h.band, ref: h.group ? '' : h.figure);
      },
    ],
    hangs: [
      (x, y) {
        final h = _painter.hangs.hitHangs(x, y);
        return h == null ? null : Hit(HitKind.hang, row: h.row, bandId: h.band != 0 ? h.band : h.host, ref: h.uid.isEmpty ? '' : '@${h.uid}');
      },
    ],
    cells: [
      (x, y) {
        final h = _painter.strips.hitStrips(x, y);
        return h == null ? null : Hit(HitKind.cell, row: h.row, bandId: h.band, ref: h.uid.isNotEmpty ? '@${h.uid}' : h.ref);
      },
    ],
    bands: [
      (x, y) {
        final h = _painter.bands.hitBands(x, y);
        if (h != null && h.uid.isNotEmpty) return Hit(HitKind.hang, row: h.row, bandId: h.band, ref: '@${h.uid}'); // 뒤 장의 탭 → 그 상국(묶음 3 · 1번)
        return h == null ? null : Hit(HitKind.band, row: h.row, bandId: h.band);
      },
    ],
  );

  /// 화면의 그 자리에 있는 것 — 누름과 같은 맞히기(오른쪽 클릭 메뉴가 쓴다). 날짜 칸 · 왼쪽 칸 · 문화권 머리 단이면 none.
  Hit hitAt(Offset local) {
    final v = c.view, at = v.layoutOf((local.dx, local.dy));
    if (at.$2 < v.head || at.$1 < v.left || _onSphereHead(at.$1, at.$2)) return Hit.none;
    return hitTest(scene, at.$1, at.$2, sources: _sources);
  }

  /// 그 자리(배치 px)가 문화권 머리 단 상자 안인가. 머리 단은 그림판을 가로지르고, 붙은 머리 단(리메이크 4단계 과제 3 걸음 4)은
  /// 그 밑으로 지나가는 줄 · 띠를 덮는다 — 누름([_tapChrome]) · 올림 · 오른쪽 클릭 메뉴가 그 밑의 것보다 머리 단을 먼저 본다.
  /// 그림판 쪽에서 왼쪽 칸 층이 받는 자리는 머리 단과 그 안의 사람 띠(과제 4 걸음 3)뿐이다(다른 누름 자리는 왼쪽 칸 안).
  bool _onSphereHead(double x, double y) => _isSphereHit(_painter.gutter.hitTest(x, y));

  static bool _isSphereHit(GutterHit? hit) => hit != null && (hit.kind == GutterHitKind.sphere || hit.kind == GutterHitKind.person);

  /// 이번 장면에 놓인 띠 [band]의 플래그(리메이크 2부 — 플래그 창이 자리와 칸을 읽는다). 없으면 null.
  FlagSpot? flagOf(int band) => _painter.links.flagOf(band);

  /// 화면의 그 자리를 품은 가장 안쪽 그릇(폴더 · 상자) — (uid, 이름, 지금 상태). 오른쪽 클릭 메뉴가 세 상태를 고른다.
  (String, String, ScopeState)? scopeAt(Offset local) {
    final v = c.view, at = v.layoutOf((local.dx, local.dy));
    if (at.$2 < v.head || at.$1 < v.left || _onSphereHead(at.$1, at.$2)) return null;
    return _painter.scopes.scopeAt(at.$1, at.$2);
  }

  /// 화면의 그 자리가 왼쪽 칸이면 거기 있는 것(트랙 이름 · 민족 칸 · 줄 이름 …).
  GutterHit? gutterAt(Offset local) {
    final v = c.view, at = v.layoutOf((local.dx, local.dy));
    if (at.$2 < v.head || at.$1 >= v.left) return null;
    return _painter.gutter.hitTest(at.$1, at.$2);
  }

  /// 보조 달력 고르기(날짜 칸의 달력 이름 칸 — 지금 연표의 <select>): 달력들과 '끄기'. 끄면 그 줄이 사라진다. 저장소에 표가 없는 달력(옛 저장소의
  /// 나중 달력 넷 — [AuxCalendarStore.offered])은 내놓지 않는다.
  Offset _upAt = Offset.zero;
  Future<void> _pickCalendar() async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final current = _painter.axis.model?.altCal ?? '';
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(_upAt & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        for (final cal in AuxCalendarStore.shared?.offered() ?? AuxCalendar.list) CheckedPopupMenuItem<String>(value: cal.id, checked: cal.id == current, height: 36, child: Text(cal.name, style: const TextStyle(fontSize: 13))),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: '', height: 36, child: Text('보조 달력 끄기', style: TextStyle(fontSize: 13))),
      ],
    );
    if (picked == null || !mounted) return;
    _painter.axis.setAltCal(picked);
    _tellAxisState();
    scene.requestFrame();
  }

  /// 기억해 둔 날짜 칸 상태를 한 번만 되돌린다(기억은 뒤늦게 올 수 있어 올 때까지 기다린다).
  bool _axisRestored = false;
  void _restoreAxisState() {
    if (_axisRestored) return;
    final saved = widget.axisState;
    if (saved == null) return;
    _axisRestored = true;
    _painter.axis.restoreState(saved);
  }

  /// 사람이 정한 날짜 칸 상태가 바뀌었으면 앱 틀에 알린다(그 값만 기억에 적힌다).
  int _axisStateVersion = -1;
  void _tellAxisState() {
    final notify = widget.onAxisState;
    if (notify == null) return;
    final version = _painter.axis.stateVersion;
    if (version == _axisStateVersion) return;
    _axisStateVersion = version;
    notify(_painter.axis.stateJson());
  }

  /// 누른 자리가 날짜 칸 · 왼쪽 칸이면 거기서 처리하고 참을 돌려준다.
  bool _tapChrome(double x, double y) {
    final v = c.view;
    if (y < v.head) {
      final hit = _painter.axis.hitTest(x, y);
      switch (hit.kind) {
        case AxisHitKind.groupToggle:
          _painter.axis.toggleGroup(hit.key);
        case AxisHitKind.eraFold:
          _painter.axis.toggleEraFold(hit.track);
        case AxisHitKind.capSec:
          _painter.axis.toggleCapSec(hit.track);
        case AxisHitKind.epochCell || AxisHitKind.eraCell || AxisHitKind.capCell || AxisHitKind.secCell:
          widget.onAxisCell?.call(hit);
        case AxisHitKind.calPick:
          _pickCalendar();
        case AxisHitKind.none:
          break;
      }
      _tellAxisState();
      scene.requestFrame();
      return true;
    }
    if (x < v.left) {
      final hit = _painter.gutter.hitTest(x, y);
      // 왼쪽 칸의 소속 폴더 줄(리메이크 4단계 과제 8 걸음 3)은 폴더 탭의 라벨과 같이 소속 펼치기 단추의 맞히기로 — 앱 틀의 누름 길(onHit)로 보낸다.
      final host = hit != null && hit.kind == GutterHitKind.folder ? HostFolders.pressOf(scene.layout, hit.uid) : null;
      if (host != null) {
        widget.onHit?.call(host);
      } else if (hit != null) {
        widget.onGutterHit?.call(hit);
      }
      return true;
    }
    // 문화권 머리 단(리메이크 조각 ②)은 그림판을 가로지른다 — 그림판 몫(접힌 꼬리표 · 오른쪽 끝 접기 표)을 눌러도 접고 편다.
    // 그 안의 사람 띠(리메이크 4단계 과제 4 걸음 3)는 그 사람의 창을 연다(GutterHitKind.person — 앱 틀이 고른다).
    // 몸통 맞히기보다 먼저 본다: 붙은 머리 단(리메이크 4단계 과제 3 걸음 4)이 덮은 줄 · 띠가 누름을 가져가지 않게.
    final sphere = _painter.gutter.hitTest(x, y);
    if (_isSphereHit(sphere)) {
      widget.onGutterHit?.call(sphere!);
      return true;
    }
    return false;
  }

  /// 왼쪽 버튼이 아닌 버튼으로 누른 포인터(오른쪽 · 가운데) — 뗄 때까지 끌기 · 누름으로 치지 않는다.
  final _otherButton = <int>{};

  /// 터치 화면: 닿아 있는 손가락의 자리와 닿은 시각, 두 손가락 확대에 든 손가락(뗄 때 '누름'으로 치지 않는다), 쥐기 시작할 때의 두 손가락 거리.
  final _touches = <int, Offset>{};
  final _touchDownMs = <int, double>{};
  final _pinched = <int>{};
  double _pinchGap = 1;

  Offset _touchCenter() {
    final two = _touches.values.take(2).toList();
    return (two[0] + two[1]) / 2;
  }

  double _touchGap() {
    final two = _touches.values.take(2).toList();
    return (two[0] - two[1]).distance;
  }

  /// 커서가 올라간 것을 표시 상태에 적는다(띠 · 칸 · 인물 · 왼쪽 칸의 줄). 바뀌었을 때만 한 장면을 청한다.
  void _hover(double x, double y) {
    final marks = SceneMarks.of(scene), v = c.view;
    // 날짜 칸: 모서리 단추의 hover 칠과 칸 도움말. 누를 것이 없고 도움말만 있는 자리는 `kind == none` · `tip`이 찬 꼴로 오므로
    // 띄울지 말지는 **`tip`이 비었는가**로 가른다(11물결 axis3 고침 1번).
    if (y < v.head) {
      final hit = _painter.axis.hitTest(x, y);
      if (_painter.axis.hover.kind != hit.kind || _painter.axis.hover.row != hit.row || _painter.axis.hover.key != hit.key) {
        _painter.axis.hover = hit;
        scene.requestFrame();
      }
      widget.onAxisTip?.call(hit.tip, hit.x, y);
      _precId = 0;
      _setHot(marks);
      return;
    }
    if (_painter.axis.hover.kind != AxisHitKind.none || _painter.axis.hover.tip.isNotEmpty) {
      _painter.axis.hover = AxisHit.none;
      scene.requestFrame();
    }
    int? band, row, track;
    String? cell, figure, coal, union;
    (int, int)? link;
    ({int eventId, String tip})? prec;
    if (y >= v.head && x < v.left) {
      final g = _painter.gutter.hitTest(x, y);
      if (g != null) {
        row = g.row >= 0 ? g.row : null;
        track = g.kind == GutterHitKind.trackName ? g.track : null;
      }
    } else if (y >= v.head && !_onSphereHead(x, y)) {
      // 문화권 머리 단 위(붙은 머리 단이 덮은 줄 · 띠 포함)는 올림이 없다.
      final hit = hitTest(scene, x, y, sources: _sources);
      if (hit.kind == HitKind.band) band = hit.bandId;
      if (hit.kind == HitKind.figure && hit.ref.isNotEmpty) figure = hit.ref;
      if (hit.kind == HitKind.link) link = (hit.bandId, hit.itemId); // 선 위 — 그 선만 색이 짙어진다(`.tl-link:hover` · `.tl-part:hover`)
      if (hit.kind == HitKind.link && hit.ref == unionHitRef) union = _painter.unions.hitUnion(x, y)?.$3;
      if (hit.kind == HitKind.link && hit.ref.startsWith(crossTagHitRef)) union = _painter.links.crossTipAt(x, y); // 짝 꼬리표의 풍선 글(같은 도움말 상자)
      if (hit.kind == HitKind.cell) {
        final s = _painter.strips.hitStrips(x, y);
        cell = s?.key;
        band = hit.bandId;
      }
      // 연합의 겹 탭(감독 선택 D5 결정 3 C): 올리면 그 연합의 구성 나라 띠만 또렷 · 가담 기간 조명 — 탭은 띠 층이 '이름표'로 답하므로 띠 층에 다시 묻는다.
      if (hit.kind == HitKind.hang) {
        final tab = _painter.bands.hitBands(x, y);
        if (tab != null && tab.coal && hit.ref == '@${tab.uid}') coal = tab.uid;
        // 이름을 다 쓰지 못한 상국 탭(첫 글자 · 점 — 조사 결함 26)과 그 카드 윗단은 풍선 글로 상국 이름을 말한다(같은 도움말 상자).
        if (tab != null && !tab.coal && hit.ref == '@${tab.uid}') {
          final tip = _painter.bands.hostTipAt(x, y);
          if (tip.isNotEmpty) union = tip;
        }
      }
      // 날짜를 정확히 모르는 점(그 구간 가운데로 옮겨 간 것)에 올리면 모른다는 글을 띄운다 — 예전 정밀도 괄호의 설명(건의 8의 9번).
      if (hit.kind == HitKind.event) {
        final tip = _painter.events.vagueTip(hit.eventId);
        if (tip != null) prec = (eventId: hit.eventId, tip: tip);
      }
    }
    if (coal != null) {
      _setCoalTip(coal, x, y);
    } else if (union != null) {
      _coalTip = null;
      _setUnionTip(union, x, y);
    } else {
      _unionTip = null;
      _coalTip = null;
      _setPrec(prec, x, y);
    }
    _setHot(marks, band: band, row: row, track: track, cell: cell, figure: figure, link: link, coal: coal);
  }

  /// 손이 올라간, 날짜를 정확히 모르는 점: 모른다는 글을 띄운다(웹은 점의 title 뒤에 같은 글).
  /// 설명 상자는 날짜 칸의 도움말 상자를 같이 쓴다 — 같은 점 위에서는 처음 올린 커서 자리에 그대로 둔다(움직일 때마다 상자가 따라다니지 않게).
  int _precId = 0;
  double _precTipX = 0, _precTipY = 0;
  void _setPrec(({int eventId, String tip})? prec, double x, double y) {
    final id = prec?.eventId ?? 0;
    if (id != _precId) {
      _precId = id;
      _precTipX = math.max(x - 12, c.view.left);
      _precTipY = y;
    }
    widget.onAxisTip?.call(prec?.tip ?? '', prec == null ? 0 : _precTipX, _precTipY);
  }

  /// 동군연합 이음줄에 올렸을 때의 풍선 글("동군연합 · 넷째 임금 — 가람 나라 · 포구 나라 · 1470년 ~ 1480년") — 같은 줄 위에서는 처음 올린 자리에 그대로.
  String? _unionTip;
  double _unionTipX = 0, _unionTipY = 0;
  void _setUnionTip(String tip, double x, double y) {
    _precId = 0;
    if (tip != _unionTip) {
      _unionTip = tip;
      _unionTipX = math.max(x - 12, c.view.left);
      _unionTipY = y;
    }
    widget.onAxisTip?.call(tip, _unionTipX, _unionTipY);
  }

  /// 연합의 겹 탭에 올렸을 때의 풍선 글(웹의 title — 띠 위에는 딱지 글이 없으므로 '연합'이라는 말은 여기와 단체 창에만).
  /// 날짜 칸의 도움말 상자를 같이 쓰고, 같은 탭 위에서는 처음 올린 자리에 그대로 둔다(정밀도 괄호와 같은 꼴).
  String? _coalTip;
  double _coalTipX = 0, _coalTipY = 0;
  void _setCoalTip(String coal, double x, double y) {
    _precId = 0;
    if (coal != _coalTip) {
      _coalTip = coal;
      _coalTipX = math.max(x - 12, c.view.left);
      _coalTipY = y;
    }
    widget.onAxisTip?.call(_painter.bands.coalTip(coal), _coalTipX, _coalTipY);
  }

  /// 몸통 · 왼쪽 칸의 올림 표시를 적는다(주지 않은 것은 지운다). 바뀌었을 때만 한 장면을 청한다.
  void _setHot(SceneMarks marks, {int? band, int? row, int? track, String? cell, String? figure, (int, int)? link, String? coal}) {
    if (band == marks.hotBand && row == marks.hotRow && track == marks.hotTrack && cell == marks.hotCell && figure == marks.hoverFigure && link == marks.hotLink && coal == marks.hotCoal) return;
    if (cell != marks.hotCell) widget.onHotCell?.call(cell);
    marks
      ..hotBand = band
      ..hotRow = row
      ..hotTrack = track
      ..hotCell = cell
      ..hoverFigure = figure
      ..hotLink = link
      ..hotCoal = coal
      ..version += 1;
    scene.requestFrame();
  }

  /// 연표가 움직이기 시작하면(끌기 · 휠 · 멀리 가기) 연합의 올림을 푼다 — 웹도 움직이는 동안은 올림이 없고(`_hover`의 '움직이는 동안은 고요'),
  /// 풀지 않으면 탭이 손 밑을 떠난 뒤에도 나머지 줄이 옅은 채로 남는다. 멎은 뒤 커서를 움직이면 그 자리의 것으로 다시 켜진다.
  void _dropCoal() {
    final marks = SceneMarks.of(scene);
    if (marks.hotCoal == null) return;
    marks
      ..hotCoal = null
      ..version += 1;
    scene.requestFrame();
    if (_coalTip != null) {
      _coalTip = null;
      widget.onAxisTip?.call('', 0, 0);
    }
  }

  void _dropCoalWhenMoving() {
    if (c.active.value) _dropCoal();
  }

  /// 커서가 연표 밖으로 나갔다 — 올림 표시 · 날짜 칸의 모서리 칠 · 도움말 · 알약을 모두 걷는다.
  void _leave() {
    _leavePill();
    _coalTip = null;
    _setHot(SceneMarks.of(scene));
    _precId = 0;
    scene.hover(0);
    if (_painter.axis.hover.kind != AxisHitKind.none || _painter.axis.hover.tip.isNotEmpty) {
      _painter.axis.hover = AxisHit.none;
      scene.requestFrame();
    }
    widget.onAxisTip?.call('', 0, 0);
  }

  /// 손 밑의 개수 알약이 바뀌면 알린다(같은 알약 위에서 움직이는 동안에는 다시 알리지 않는다 — 카드의 닫힘 시계를 흔들지 않게).
  String? _pillKey;
  void _hoverPill(double x, double y, Offset local) {
    final notify = widget.onPill;
    if (notify == null) return;
    final v = c.view;
    final hit = y >= v.head && x >= v.left && !_onSphereHead(x, y) ? hitEvents(scene, x, y) : Hit.none;
    final key = hit.kind == HitKind.pill ? '${hit.row}@${hit.lo.round()}~${hit.hi.round()}' : null;
    if (key == _pillKey) return;
    _pillKey = key;
    notify(key == null ? null : hit, local);
  }

  void _leavePill() {
    if (_pillKey == null) return;
    _pillKey = null;
    widget.onPill?.call(null, Offset.zero);
  }

  double _ms(PointerEvent e) => e.timeStamp.inMicroseconds / 1000;
  bool _mine(PointerEvent e) => widget.onlyDevice == null || e.device == widget.onlyDevice;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (widget.onlyDevice != null || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final center = Offset(c.view.width / 2, c.view.height / 2);
    final plus = key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd;
    final minus = key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract;
    if (HardwareKeyboard.instance.isControlPressed) {
      // Ctrl + ± · 0 = 돋보기
      if (plus) {
        c.magnifyTo(c.view.mag * TimelineController.magStep, center);
      } else if (minus) {
        c.magnifyTo(c.view.mag / TimelineController.magStep, center);
      } else if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
        c.magnifyTo(1, center);
      } else {
        return KeyEventResult.ignored;
      }
    } else if (plus) {
      c.wheel(center, -280);
    } else if (minus) {
      c.wheel(center, 280);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      c.glide(.15);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      c.glide(-.15);
    } else if (key == LogicalKeyboardKey.escape) {
      c.stop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      c.reduceMotion = MediaQuery.disableAnimationsOf(context);
      c.resize(box.maxWidth, box.maxHeight);
      _painter.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      // 기억은 저장소를 연 뒤에 오므로 처음 몇 장면은 비어 있다 — 올 때 한 번 되돌린다(흐름 없이 곧바로 그 높이로).
      _restoreAxisState();
      return Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: Listener(
          // 왼쪽 버튼(과 손가락 · 펜)만 끌기 · 누름이다. 오른쪽 버튼은 메뉴만 띄운다(`ContextMenuArea`의 몫) — 전에는 버튼을 가리지 않아
          // 오른쪽 클릭이 왼쪽 클릭까지 함께 해서 메뉴와 상세 창이 같이 떴다(감독 검토 2026-09-22). 뗄 때는 버튼 값이 0이라 누를 때 적어 둔다.
          onPointerDown: (e) {
            if (!_mine(e)) return;
            if (e.kind == PointerDeviceKind.mouse && e.buttons & kPrimaryMouseButton == 0) {
              _otherButton.add(e.pointer);
              return;
            }
            if (e.kind == PointerDeviceKind.touch) {
              _touches[e.pointer] = e.localPosition;
              _touchDownMs[e.pointer] = _ms(e);
              if (_touches.length == 2) {
                // 두 번째 손가락: 하던 끌기를 끝내고 두 손가락 확대로 넘어간다. 이 누름들은 뗄 때 '누름'으로 치지 않는다.
                _pinchGap = math.max(1, _touchGap());
                _pinched.addAll(_touches.keys);
                c.pinchStart(_touchCenter());
                return;
              }
              if (_touches.length > 2) {
                _pinched.add(e.pointer);
                return;
              }
            }
            c.pointerDown(e.localPosition, _ms(e));
          },
          onPointerMove: (e) {
            if (!_mine(e) || _otherButton.contains(e.pointer)) return;
            if (_touches.containsKey(e.pointer)) {
              _touches[e.pointer] = e.localPosition;
              if (c.pinching) {
                if (_touches.length >= 2) c.pinchUpdate(_touchCenter(), _touchGap() / _pinchGap);
                return;
              }
              // 두 손가락을 쥐었다 하나만 남은 손가락은 끌지 않는다(남은 손가락으로 장면이 튀지 않게).
              if (_pinched.contains(e.pointer)) return;
            }
            c.pointerMove(e.localPosition, _ms(e));
            if (c.dragging) _dropCoal();
          },
          onPointerUp: (e) {
            if (!_mine(e)) return;
            if (_otherButton.remove(e.pointer)) return;
            final downMs = _touchDownMs.remove(e.pointer);
            if (_touches.remove(e.pointer) != null) {
              if (c.pinching) c.pinchEnd();
              if (_pinched.remove(e.pointer)) return;
            }
            final clicked = !c.dragging;
            c.pointerUp(e.localPosition, _ms(e));
            // 길게 누른 손가락은 메뉴를 띄운 것이다(`ContextMenuArea`) — 떼어도 고르지 않는다(오른쪽 클릭이 왼쪽 클릭까지 하지 않는 것과 같은 뜻).
            if (downMs != null && _ms(e) - downMs >= menuLongPress.inMilliseconds) return;
            if (!clicked || widget.onHit == null) return;
            // 선택 판정은 그린 것과 같은 목록에서, 배치 px로.
            final at = c.view.layoutOf((e.localPosition.dx, e.localPosition.dy));
            _upAt = e.position;
            if (_tapChrome(at.$1, at.$2)) return;
            final hit = hitTest(scene, at.$1, at.$2, sources: _sources);
            final minute = c.view.minuteAt(at.$1);
            widget.onHit!(hit.kind == HitKind.none ? Hit(HitKind.none, lo: minute, hi: minute) : hit);
          },
          onPointerHover: (e) {
            if (!_mine(e) || c.moving) return;
            final at = c.view.layoutOf((e.localPosition.dx, e.localPosition.dy));
            scene.hover(_onSphereHead(at.$1, at.$2) ? 0 : bandAt(scene, at.$1, at.$2));
            _hover(at.$1, at.$2);
            _hoverPill(at.$1, at.$2, e.localPosition);
          },
          onPointerCancel: (e) {
            if (!_mine(e) || _otherButton.remove(e.pointer)) return;
            _touchDownMs.remove(e.pointer);
            if (_touches.remove(e.pointer) != null) {
              if (c.pinching) c.pinchEnd();
              if (_pinched.remove(e.pointer)) return;
            }
            c.pointerCancel();
          },
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent || !_mine(e)) return;
            // 휠 = 기간 확대, Ctrl + 휠 = 돋보기(크기까지 커지는 확대)
            if (HardwareKeyboard.instance.isControlPressed) {
              c.magnify(e.localPosition, e.scrollDelta.dy);
            } else {
              c.wheel(e.localPosition, e.scrollDelta.dy);
            }
          },
          // 노트북 트랙패드의 집기 = 돋보기
          onPointerPanZoomStart: (e) => _mine(e) ? _pinchFrom = c.view.mag : null,
          onPointerPanZoomUpdate: (e) {
            if (_mine(e) && (e.scale - 1).abs() > .01) c.magnifyTo(_pinchFrom * e.scale, e.localPosition);
          },
          // 돋보기 배율 알약은 앱 틀(shell/mag_pill.dart)이 확대 단추 묶음의 왼쪽에 띄운다.
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            onExit: (_) => _leave(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(child: CustomPaint(painter: _painter, isComplex: true, willChange: true)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
