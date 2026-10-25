import 'dart:async' show Completer, Timer, scheduleMicrotask;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../controller.dart';
import '../motion.dart';
import 'emphasis.dart' show Emphasis;
import 'fold.dart';
import 'label_batch.dart';
import 'label_worker.dart';
import 'labels.dart';
import 'layout.dart';
import 'lens_titles.dart';
import 'levels.dart';
import 'name_fade.dart';
import 'reserved.dart';
import 'row_flow.dart';
import 'sphere_crowns.dart';
import 'tile.dart';
import 'tile_cache.dart';
import 'viewport.dart';

export 'label_batch.dart';

/// 이번 장면에 그릴 타일 하나. 제 단계의 타일이 아직 없으면 윗단계 타일을 그 자리(clip)만큼만 잘라 메운다.
class DrawTile {
  DrawTile(this.tile, this.key, this.clip, this.alpha, this.isCover, {this.fadeRect, this.ghost = false, this.hasUnder = false});
  final Tile tile;
  final TileKey key;

  /// 켜고 끄기의 흐름 동안 **사라지는 줄**에 잘라 그리는 직전 조합의 타일 — 이름 자리는 여기서 모으지 않는다(새 조합의 타일이 맡는다).
  final bool ghost;

  /// 떠오르는 동안 쓰는 층의 자리 — 화면 전체가 아니라 이 타일의 자리만큼만 잡는다.
  final Rect? fadeRect;

  /// 메움 타일을 그릴 자리(배치 px). 제 타일이면 null.
  final Rect? clip;

  /// 막 도착한 타일은 200ms 동안 떠오른다.
  final double alpha;
  final bool isCover;

  /// 떠오르는 타일 밑에 메움 타일(더 성긴 단계)을 깔았는가. 깔았으면 그리개가 예전처럼 층째 투명도로 엇갈려 바꾸고(메움의 불투명 띠가
  /// 아래 눈금을 가린다), 없으면 바탕색에서 짙어지게 그린다(투명도로 그리면 맨 아래 연도 세로줄이 띠 안에 비친다 — 세로줄 얹기 걸음 4).
  final bool hasUnder;
}

/// 한 장면의 집계(측정 모드가 읽는다).
class SceneStats {
  int shapes = 0, labels = 0, newParagraphs = 0, tiles = 0, covers = 0, blanks = 0;
  double paintMs = 0, textMs = 0;

  /// 이번 장면에 그린 사건 이름의 판 번호(없으면 −1) · 그린 이름 수 · 옅어지며 남은 그림자 수 — 잔상을 재는 쪽(검증 대본의 burst)이 읽는다.
  int nameBatch = -1, namesDrawn = 0, ghostNames = 0;
}

/// 멈춘 뒤 ClearType을 허락하기까지 기다리는 시간(ms · 장면 시계). 옮긴 직후 한두 장면만 ClearType이었다가 타일이 와서 떠오르는 동안
/// 회색으로 돌아가는 깜빡임(과제 6 보고 걱정 2)을 막는다 — 그 사이 다시 움직이면 처음부터 센다. 움직임 원칙(`docs/움직임-원칙.md`)의 토큰에 150ms가 없어 따로 이름을 둔다.
const clearTypeSettleMs = 150.0;

// 장면 준비: 보기에서 '지금 보이는 타일'을 셈해 보관에 알리고, 그릴 목록을 만든다.
// 장면마다 하는 일은 보이는 타일 몇 장을 고르는 것뿐이고, 자료 조회는 기다리지 않는다.
class TimelineScene extends ChangeNotifier {
  TimelineScene({
    required this.controller,
    required this.layout,
    required Future<Uint8List> Function(int level, int x, int chunk, List<int> packs) fetchTile,
    double Function()? clock,
    Future<LabelOutput> Function(LabelInput input)? labelCompute,
    this.ask,
  }) : _clock = clock ?? _stopwatchClock() {
    cache = TileCache(
      fetch: (key) => fetchTile(key.level, key.x, key.chunk, _packsOf(key.packsVersion)),
      onArrive: (_) => notifyListeners(),
      clock: _clock,
    );
    labelWorker = LabelWorker(compute: labelCompute, onResult: _onLabels);
    folder = RowFolder(layout: layout, ask: ask, onFolded: _applyFolded);
    controller.addListener(notifyListeners);
    controller.active.addListener(_syncBusy);
  }

  /// 빈 줄 접기: 보이는 기간에 그릴 것이 없는 줄을 접는다(fold.dart).
  late final RowFolder folder;

  /// 세로 닻: 줄이 접히고 펴져도 보던 줄은 화면에서 제자리(row_flow.dart).
  final _anchor = RowAnchor();

  /// 고른 사건이 놓인 줄(모르면 -1). 닻은 이 줄을 먼저 붙잡는다 — 선택을 다루는 쪽이 [Hit.row]로 채워 준다.
  int selectedEventRow = -1;

  // ---- 사건의 이름 자리와 묶음: 뒤의 작업자가 계산하고, 화면은 도착한 마지막 판으로 그린다 ----
  late final LabelWorker labelWorker;

  /// 지금 그리는 판: 후보(입력)와 그 자리(출력)는 늘 같은 판끼리 짝지어 둔다.
  LabelBatch? labelBatch;
  LabelOutput? labelOutput;

  /// 그리는 쪽이 넣어 준다: 사건 이름의 폭(px). 아직 모르면 null.
  double? Function(String title, int importance)? measureName;
  int? selectedEventId;

  /// 자료 처리부에 묻는 길({"op": …} → 답의 data). 줄 이름 · 빈 줄 접기처럼 타일 말고 곁들이는 자료를 층과 장면이 받아 올 때 쓴다. 검사에서는 없을 수 있다.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query)? ask;

  /// 왼쪽 칸의 폭(민족 단계에 따라)과 날짜 칸의 높이(열린 줄에 따라)를 보기에 옮긴다. 날짜 칸의 높이는 날짜 칸의 구성이 정해 [axisHeight]에 넣어 둔다.
  double? axisHeight;

  /// 줄이 접히면 날짜 칸의 줄도 줄어 이 값이 그리는 도중에 바뀐다 — 값은 바로 옮기고 '다시 그려라'는 알림만 다음 마이크로태스크로 미룬다
  /// (그리는 도중에 다시 그리라고 하면 화면 틀이 막는다).
  void applyLayoutToView() {
    if (!controller.setFrame(layout.gutterWidth, axisHeight ?? SceneView.rulerHeight, notify: false)) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  /// 뒤에서 도는 일(빈 줄 접기의 물음 · 미뤄 둔 접힘 · 줄 높이의 흐름 · 왕관 표의 물음)이 모두 끝나 장면이 가라앉았는가 — 그림을 뜨는 도구가 기다릴 때 본다.
  bool get settled => folder.settled && !layout.flowing && !crowns.pending;

  /// 사람 띠의 왕관이 가리키는 띠 · 지도자 칸의 자리(리메이크 4단계 과제 4 걸음 2 — sphere_crowns.dart). 저장소를 바꿔 넣을 때마다 한 번 묻고
  /// ([prepare]가 맞춤 · 사람 띠가 없으면 묻지 않음), 풀리면 다시 그린다. 실 층(paint/sphere_threads.dart)과 동군연합 이음줄 층(paint/unions.dart)이 읽는다.
  late final crowns = CrownTable(
    ask: ask,
    onReady: () {
      if (!_disposed) requestFrame();
    },
  );

  /// 이미 붙잡을 것을 잡아 둔 다시 쌓기가 도는 중인가 — 그 안에서 또 잡으면 옛 자리를 잃는다.
  bool _held = false;

  /// 접힘이 달라졌다: 붙잡을 줄을 잡아 두고 다시 쌓은 뒤, 그 줄이 화면에서 제자리에 있게 한다.
  void _applyFolded(Set<int> folded) {
    final v = controller.view;
    // 맨 위에 서 있을 때는 닻을 잡지 않는다 — 처음 열었을 때(세로 0)의 첫 접힘에 화면 가운데 줄을 붙잡으면 맨 위가 몇 px 밀려 올라간다(지금 연표도 맨 위에서는 그대로 선다).
    if (!_held) {
      if (v.top <= 0) {
        _anchor.clear();
      } else {
        _anchor.capture(layout, v.top, v.bodyHeight, preferred: selectedEventRow);
      }
    }
    layout.reduceMotion = controller.reduceMotion;
    if (!layout.setFolded(folded)) return;
    _keepAnchor();
    notifyListeners();
  }

  // ---- 보기 상태(트랙 접기 · 민족 접기 · 트랙 끔)와 자동 조감 ----

  /// 보기 상태를 바꾼다. 붙잡을 줄(트랙을 접고 펼 때는 그 트랙의 위 — 지금 연표의 `_pressHold`)을 잡아 두고
  /// 다시 쌓은 뒤, 빈 줄 접힘을 그 자리에서 다시 셈해 한 번의 흐름에 함께 싣는다. 달라졌으면 참.
  /// [hold]를 주면 스스로 고르지 않고 그 줄(번호 · 화면 맨 위에서 그 줄 위까지의 거리)을 붙잡는다 — 번호가 −1이면
  /// 아무것도 붙잡지 않는다(집합 보기를 켤 때는 판의 머리를 맨 위로, 끌 때는 켜기 전에 보던 줄로 — `ui/board_views.dart`).
  bool applyViewState(ViewState next, {(int, double)? hold}) {
    final v = controller.view;
    final pressed = ViewState.foldToggled(layout.viewState, next, boardTrack: layout.boardTrackId);
    if (hold != null) {
      _anchor.clear();
      if (hold.$1 >= 0 && hold.$1 < layout.rowCount) {
        _anchor
          ..row = hold.$1
          ..offset = hold.$2;
      }
    } else if (pressed >= 0) {
      _anchor.captureTrack(layout, v.top, layout.tracks.indexWhere((t) => t.id == pressed));
    } else {
      _anchor.capture(layout, v.top, v.bodyHeight, preferred: selectedEventRow);
    }
    final boardChanged = layout.viewState.board != next.board;
    // 모두 접기 · 펴기(트랙 둘 넘게 한꺼번에)는 크게 바뀌는 장면이다.
    final many = layout.viewState.foldedTracks.difference(next.foldedTracks).length + next.foldedTracks.difference(layout.viewState.foldedTracks).length > 1;
    return _restack(big: many, () {
      if (boardChanged) {
        // 판은 줄 번호도 바꾼다. 옛 rows_near로 새 판을 접지 않도록 답과 실제 접힘을 함께 비운다.
        // 내부 기억만 비우면 새 답이 빈 접힘 집합일 때 알림이 없어, 배치에 옛 접힘이 남는다.
        folder.forget();
        layout.setFolded(const <int>{});
      }
      return layout.setViewState(next);
    });
  }

  /// 밀도를 사람이 골랐다(지금 연표의 `setDensity`): 자동 조감이 걸린 채 다른 밀도를 고르면 문턱 아래로 내려올 때까지 쉰다.
  bool applyDensity(int density) {
    _autoBird.chose(density);
    return applyConditions(layout.conditions.copyWith(density: density, autoBird: _autoBird.wanted));
  }

  /// 보기 조건(켠 단 · 밀도 · 조감 모양)을 바꾼다. 줄이 흐르는 동안 보던 줄은 제자리다.
  bool applyConditions(ViewConditions next) {
    final v = controller.view;
    _anchor.capture(layout, v.top, v.bodyHeight, preferred: selectedEventRow);
    // 밀도가 바뀌면(조감 켜고 끔 · 자동 조감 포함) 글자 크기와 줄 높이가 한꺼번에 바뀐다 — 크게 바뀌는 장면.
    final c = layout.conditions;
    return _restack(big: next.density != c.density || next.bird != c.bird, () => layout.setConditions(next));
  }

  /// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A)를 켜고 끈다([id]가 빈 글이면 끔). 지도자 자리가 새로 생기는 트랙이 있으면 줄이 흐르고,
  /// 켠 변형(`theme:<id>`)이 바뀌어 타일을 다시 받는다. 보던 줄은 제자리(보기 조건과 같은 닻). 달라졌으면 참.
  bool applyThemeLens(String id, {Set<String>? slots}) {
    final v = controller.view;
    _anchor.capture(layout, v.top, v.bodyHeight, preferred: selectedEventRow);
    return _restack(() => layout.setThemeLens(id, slots: slots));
  }

  /// 붙잡을 것을 잡아 둔 채 다시 쌓는다: 빈 줄 접힘도 그 자리에서 다시 셈해 한 번의 흐름에 함께 싣는다.
  bool _restack(bool Function() apply, {bool big = false}) {
    layout.reduceMotion = controller.reduceMotion;
    _held = true;
    try {
      if (!apply()) return false;
      if (big) cutNames();
      folder.recheck();
      _keepAnchor();
    } finally {
      _held = false;
      _anchor.track = -1; // 트랙 닻은 이 한 번의 다시 쌓기 동안만
    }
    notifyListeners();
    return true;
  }

  final _autoBird = AutoBird();

  /// 자동 조감의 켬/끔과 되돌아갈 밀도(명세 05 7.6). 켜는 순간에는 지금 보기로 한 번 판정한다.
  AutoBird get autoBirdState => _autoBird;
  (bool, int) get autoBird => (_autoBird.on, _autoBird.from);
  set autoBird((bool, int) value) {
    _autoBird.from = value.$2;
    _autoBird.enable(value.$1, _spanYears);
    _settleAutoBird();
  }

  /// 자동 조감을 손으로 푼다(↕ · V) — 문턱 아래로 좁아질 때까지 쉬고 고른 밀도로 흘러 돌아간다.
  void leaveAutoBird() {
    _autoBird.leave();
    _settleAutoBird();
  }

  /// 밀도가 달라졌다는 알림. `auto: true`면 **자동 조감이 스스로 바꾼 것**이니 표시만 고치고 되돌려 부르지 않는다
  /// (되돌려 [applyDensity]를 부르면 사람이 고른 것으로 여겨 자동 조감이 쉰다).
  void Function(int density, {required bool auto})? onDensity;

  double get _spanYears => controller.view.span / 525960;

  /// 지금 곧바로 정착한다(멀리 가기의 도착 · 다시 배치 — 기다림 0): 미뤄 둔 빈 줄 접힘과 자동 조감의 문턱을 함께 셈한다.
  void settleNow() {
    folder.settleNow();
    _settleAutoBird();
  }

  /// 정착 때 한 번: 문턱을 다시 재고, 자동 조감이 달라지면 그 시계에 함께 흐르게 한다(움직임 원칙 ③ · ④).
  void _settleAutoBird() {
    final c = layout.conditions;
    final wanted = _autoBird.settle(_spanYears, density: c.density, active: c.autoBird);
    if (wanted == null) return;
    applyConditions(c.copyWith(autoBird: wanted));
    onDensity?.call(wanted ? 2 : _autoBird.from, auto: true);
  }

  /// 전체 높이를 알리고 붙잡은 줄을 제자리에 둔다. 손이 쥐고 있는 동안(끌기 · 관성)에는 닻이 쉰다 — 멎은 자리가 새 기준이다.
  void _keepAnchor() {
    controller.setContentHeight(layout.totalHeight);
    if (controller.dragging || controller.velocity != Offset.zero) {
      _anchor.clear();
      return;
    }
    final to = _anchor.keep(layout);
    if (to != null) controller.scrollTo(to);
  }

  /// 커서 아래의 띠(없으면 0). 띠가 바뀔 때만 다시 그린다 — 마우스가 움직일 때마다 그리지 않는다.
  int hoverBand = 0;
  void hover(int band) {
    if (band == hoverBand) return;
    hoverBand = band;
    notifyListeners();
  }

  /// 사건을 고른다. [row]를 주면 세로 닻이 그 줄을 먼저 붙잡는다(모르면 -1 — 화면 가운데 줄을 붙잡는다).
  void select(int? eventId, {int row = -1}) {
    if (eventId == selectedEventId && row == selectedEventRow) return;
    selectedEventId = eventId;
    selectedEventRow = row;
    notifyListeners();
  }
  final _batches = <int, LabelBatch>{};
  int _labelVersion = 0, _labelSignature = 0, _labelViewSignature = 0;

  /// 마지막으로 맡긴 이름 판이 모은 줄 번호 범위(처음 · 끝 — 비었으면 0 · −1). [_askLabels]가 이 밖의 줄이 화면에 들면 다시 셈한다.
  int _labelFirstRow = 0, _labelLastRow = -1;

  /// 마지막으로 셈을 맡긴 이름 판의 번호.
  int get labelVersion => _labelVersion;
  double _labelPpm = 0, _labelLo = 0, _labelAskedAt = -1e9;

  /// 이름의 드나듦(옅어짐). 그리는 쪽의 글자 방식이 옅어짐을 못 하면 꺼 둔다.
  final nameFade = NameFade();

  // ---- 크게 바뀌는 장면(건의 8의 8번 — 조감 등으로 갑자기 줄일 때의 잔상) ----
  // 정의는 여기 한 곳이다: 밀도 바뀜(조감 켜고 끔) · 모두 접기/펴기([applyConditions] · [applyViewState]가 부름) ·
  // 한 장면에 배율이 1.5배 넘게 바뀌거나 한 화면 폭 넘게 건너뜀(전체 보기 · 범위 바로 가기) · 비행 도착([_watchJumps]).
  // 그 장면에서는 ① 빠지는 이름의 그림자를 만들지 않고 옅어지던 것도 바로 지운다 ② 바뀌기 전에 셈한 이름 판(옛 크기 · 옛 자리)은
  // 새 판이 올 때까지 그리지 않는다 ③ 새 판의 이름은 자리가 정해진 뒤 지금의 등장 값(in)으로 한 번에 나타난다.
  // 끌기 · 휠 한 칸씩의 드나듦은 그대로다. (타일은 자료를 장면마다 지금 배치로 그리므로 옛 밀도의 그림이 늘여 깔리지 않는다.)
  double _jumpPpm = 0, _jumpLo = 0;
  bool _wasFlying = false, _cutFlow = false;

  /// 크게 바뀐 장면: 옛 이름 · 그림자를 거둔다. 그 뒤 줄이 흐르는 동안에도 그림자를 만들지 않는다.
  /// 새 판은 평소처럼 다음 장면의 [_askLabels]가 맡긴다(보기 조건 · 배치 · 배율이 바뀌어 서명이 달라진다) — 이 자리에서 억지로 다시 셈하게 하면
  /// 같은 장면의 글자 예산을 사건 이름이 먼저 써 버려 띠의 탭이 두 장면 늦게 나온다(2026-10-13 연속 장면에서 봄).
  void cutNames() {
    if (hide.contains('cut')) return; // 측정용(--hide cut): 고치기 전처럼 — 같은 실행본으로 성능을 견준다
    nameFade.cut(_clock());
    _batches.clear(); // 바뀌기 전에 맡긴 셈의 답은 버린다(도착해도 짝이 없어 그리지 않는다)
    _cutFlow = true;
    _syncBusy();
  }

  /// 장면마다: 배율 · 자리가 한 번에 크게 건너뛰었는지, 비행이 막 끝났는지 본다.
  void _watchJumps(SceneView v) {
    final flying = controller.flying;
    if (_jumpPpm > 0 && !flying && !_wasFlying) {
      final ratio = v.ppm / _jumpPpm;
      if (ratio > 1.5 || ratio < 1 / 1.5 || (v.lo - _jumpLo).abs() > v.span) cutNames();
    }
    if (_wasFlying && !flying) nameFade.dropGhosts();
    _jumpPpm = v.ppm;
    _jumpLo = v.lo;
    _wasFlying = flying;
  }

  void _onLabels(LabelOutput output) {
    _labelsPending = false;
    final batch = _batches[output.version];
    if (batch == null) return;
    if (_cutFlow && !layout.flowing) _cutFlow = false;
    _batches.removeWhere((version, _) => version <= output.version);
    labelBatch = batch;
    labelOutput = output;
    final input = batch.input;
    nameFade.accept(
      [
        for (int i = 0; i < output.shownCount; i++)
          if (output.shownSide[i] != LabelSide.none)
            NameShown(
              eventId: input.eventId[output.shownCandidate[i]],
              title: batch.title(output.shownCandidate[i]),
              importance: input.importance[output.shownCandidate[i]],
              at: input.at[output.shownCandidate[i]],
              row: input.row[output.shownCandidate[i]],
              line: output.shownLine[i],
              size: batch.sizeOf(output.shownCandidate[i]),
              look: input.look[output.shownCandidate[i]],
              band: input.band[output.shownCandidate[i]],
              // 옅어지는 이름의 자리는 어림이 아니라 그릴 때와 같은 셈으로(점의 폭 · 연도 · 알약까지) 잡는다.
              dx: batch.runOf(output.shownCandidate[i], 0, output.shownSide[i], output.shownFlags[i]).nameLeft,
            ),
      ],
      now: _clock(),
      moving: controller.moving,
      instant: controller.reduceMotion || hide.contains('fade'),
      ghosts: !_cutFlow && !controller.flying,
      minutesPerPx: 1 / controller.view.ppm,
    );
    _syncBusy();
    _trackStill(); // 이름 판을 기다리던 가라앉음이 여기서 시작될 수 있다(그리지 않아도 150ms 뒤 깨우게)
    notifyListeners();
  }

  /// 이름 자리를 다시 계산해야 하면 입력을 모아 작업자에 맡긴다. 옆으로 조금 움직인 것만으로는 다시 계산하지 않는다(자리는 분에 매여 있다).
  void _askLabels(SceneView v, int firstRow, int lastRow) {
    // 비켜 갈 구간(관계선 층)과 밝기 상태(강조가 이름 차례를 바꾼다)가 달라지면 이름 자리를 다시 셈한다.
    // 관점(lens)이 바뀌면 이름이 바뀌고 그 폭으로 자리를 다시 잡아야 한다 — 그 판 번호도 함께 본다(11물결 labels4 1번).
    // 서명은 보기 · 타일 쪽(줄 · 단계 · 그릴 타일)과 꾸밈 쪽(비켜 갈 구간 · 강조 · 관점 이름)으로 나눠 센다 — ClearType의 '멈춤'은
    // 보기 · 타일이 바뀐 뒤 처음 가라앉을 때까지만 판을 기다린다([_viewSettling]).
    // 보기 조건(밀도 · 조감 · 조감 모양 · 켠 단)도 보기 쪽에 넣는다 — 글자 크기 · 글줄 수 · 이름을 붙일지(조감은 없음)가 바뀌는데
    // [SceneLayout.version](자료 조합의 판 번호)은 그대로라, 예전에는 V만 누르면 보통 밀도의 옛 판을 조감에서 그대로 그렸다(2026-10-25).
    int view = Object.hash(layout.version, layout.conditions, firstRow ~/ chunkRows, lastRow ~/ chunkRows, level);
    for (final d in draw) {
      view = Object.hash(view, d.tile, d.isCover);
    }
    final signature = Object.hash(view, ReservedZones.of(this).version, Emphasis.of(this).version, LensTitles.of(this).version);
    final now = _clock();
    final scaled = _labelPpm == 0 || (v.ppm / _labelPpm - 1).abs() > .04;
    final moved = (v.lo - _labelLo).abs() > v.span * .4;
    // 판이 모으지 않은 줄이 화면에 들었다 — 서명의 줄 범위는 줄 묶음(8줄) 단위인데 판은 그때 화면의 줄만 모으므로, 줄 묶음 안에서 위 · 아래 줄이
    // 새로 들면 서명이 그대로라 그 줄의 사건 점 · 이름 · 알약이 빠진 채 남았다(밀도 넉넉하게 → 자동: 흐르는 동안 화면 위에 있던 맨 위 줄 —
    // 2026-10-25 조감 글자 겹침 검증에서 봄). 모은 범위 안에서 움직이는 동안은 다시 셈하지 않는다.
    final uncovered = firstRow < _labelFirstRow || lastRow > _labelLastRow;
    if (scaled || moved || uncovered || view != _labelViewSignature) _viewSettling = true;
    // 폭을 아직 몰라 미룬 이름이 있으면 0.12초마다 다시 본다(그동안 그리는 쪽이 폭을 준비한다).
    final retry = (labelOutput?.deferred ?? 0) > 0 && now - _labelAskedAt > 120 && !labelWorker.busy;
    if (!scaled && !moved && !retry && !uncovered && signature == _labelSignature) return;
    // 보기가 바뀐 뒤 아직 가라앉지 않았으면 무슨 까닭이든 이 판을 기다린다(옮긴 뒤 첫 그림이 비켜 갈 구간을 고쳐 다시 청하는 판도 —
    // 그 답에 이름이 드나든다). 가라앉은 뒤 강조(고르기) · 관점 이름 · 비켜 갈 구간만 바뀐 판은 기다리지 않는다 — 고를 때마다 화면 전체가
    // 회색으로 번쩍이지 않게(이름이 실제로 드나들면 [_namesMoving]이 회색으로 둔다).
    if (_viewSettling) _labelsPending = true;
    // 한 번에 하나만 묻는다(빈 줄 접기의 `RowFolder.maybeAsk`와 같은 길). 확대 · 돋보기 도중에는 배율이 장면마다 바뀌어
    // 후보 모으기(`LabelBatch.collect`)가 장면마다 도는데, 뒤의 작업자가 앞 판을 셈하는 동안 모은 판은 그대로 버려진다
    // (100만 건 · 돋보기 50%에서 한 번이 여러 ms다). 답이 온 뒤 그때의 보기로 한 번만 모은다 — 다음 장면에 다시 들른다.
    if (labelWorker.busy) {
      requestFrame();
      return;
    }
    _labelSignature = signature;
    _labelViewSignature = view;
    _labelFirstRow = firstRow;
    _labelLastRow = lastRow;
    _labelPpm = v.ppm;
    _labelLo = v.lo;
    _labelAskedAt = now;
    final batch = LabelBatch.collect(this, v, firstRow, lastRow, ++_labelVersion);
    _batches[batch.input.version] = batch;
    labelWorker.request(batch.input);
  }

  /// 자료집(DLC)을 켜고 끈다. 조회를 기다리지 않는다 — 줄은 옛 자리에서 새 자리로 360ms 흐르고(켠 트랙은 0에서 자라나고 끈 트랙은 0으로 접힌다 —
  /// 4단계 1걸음), 타일은 방금까지 보던 조합의 것으로 메우다가 새 조합의 타일이 오면 바꾼다(새로 나타난 내용만 200ms로 떠오른다).
  /// 흐르는 동안 사라지는 줄에는 직전 조합의 타일을 그 줄 자리만큼만 잘라 그린다(내용이 팍 사라지지 않고 줄이 접히는 대로 잘려 나간다 — [prepare]).
  /// 보던 줄 — 화면 맨 위에서부터 처음으로, 바꾼 뒤에도 남는 줄 — 은 화면에서 제자리에 머문다(세로 닻).
  void setPacks(Set<int> packs) {
    final v = controller.view, before = layout.version;
    _anchor.clear();
    final first = layout.rowAt(v.top);
    if (first >= 0 && v.top > 0) {
      for (final r in layout.visibleRowsFrom(first)) {
        if (!packs.contains(layout.trackOf(r).pack)) continue;
        _anchor.row = r;
        _anchor.offset = layout.rowTop(r) - v.top;
        break;
      }
    }
    layout.reduceMotion = controller.reduceMotion;
    layout.enable(packs);
    if (layout.version == before) {
      _anchor.clear();
      return;
    }
    // 줄 구성이 달라졌으니 접힘의 기억을 버리고 새 조합으로 다시 묻는다(명세 05 6.3).
    folder.forget();
    _goneVersion = layout.flowing ? before : null;
    cache.olderVersions = [before, ...cache.olderVersions.where((version) => version != before && version != layout.version)].take(4).toList();
    _keepAnchor();
    notifyListeners();
  }

  /// 켜고 끄기의 흐름 동안 사라지는 줄을 그릴 직전 조합의 판 번호(흐름이 끝나면 null).
  int? _goneVersion;

  /// 저장소를 고쳐 쓰는 동안(엔진 apply — 계약 2-7) 새 타일 · 빈 줄 접기를 묻지 않는다([TileCache.paused] · [RowFolder.paused]). 있는 타일로 그리고
  /// 끌기 · 확대는 그대로 된다. 엔진은 COMMIT 순간만 잠금을 쥐므로, 그 뒤 [replaceLayout]까지 새 저장소의 답(새 줄 번호)이 옛 뼈대에 섞이지 않게
  /// 쓰기 직전에 걸고 [replaceLayout]이 푼다(실패면 앱 틀이 푼다 — 화면 그대로).
  bool get storeWriting => cache.paused;
  set storeWriting(bool value) {
    if (value == cache.paused) return;
    if (value) {
      folder.paused = true;
      cache.paused = true;
    } else {
      _releaseWriting();
      notifyListeners();
    }
  }

  /// 고쳐 쓰기가 끝나 [storeWriting]이 풀릴 때(새 뼈대로 바꾸거나 실패로 풀 때) 끝나는 기다림 — 쓰지 않는 동안은 곧바로 끝난다.
  /// 줄 번호로 답하는 조회(사건 목록 · 같은 시기 · 검색 결과의 줄 · 줄 이름 …)를 앱 틀이 이것으로 미룬다: 엔진은 COMMIT 순간만 잠그므로 COMMIT 뒤
  /// 새 뼈대를 받기 전의 답은 새 줄 번호라 옛 뼈대에 엉뚱하게 비친다(과제 8 고침 1회차 걱정 2).
  Future<void> get storeSettled => storeWriting ? (_settling ??= Completer<void>()).future : Future<void>.value();
  Completer<void>? _settling;

  void _releaseWriting() {
    folder.paused = false;
    cache.paused = false;
    final waiting = _settling;
    _settling = null;
    waiting?.complete();
  }

  /// 저장소를 다시 지어 뼈대가 통째로 바뀌었다(DLC 더하기 · 빼기 · 판 올리기). 뼈대를 제자리에서 바꾸고([SceneLayout.replaceWith])
  /// 옛 자리에서 새 자리로 흐른다. 보던 줄은 제자리 — 닻은 줄 번호가 아니라 (트랙 열쇠 · 트랙 안 차례)로 잡아 새 번호로 옮긴다.
  /// 접힘 · 이름 자리 · 고른 사건은 모두 비운다(번호가 바뀌었다). [enabled] · [view]는 새 번호로 옮겨 적은 켠 DLC와 보기 상태.
  /// 타일 보관([keepBefore] — 엔진 apply의 `first_pos` · 계약 2-7): 0이면 모두 버린다(바꿔 넣은 저장소 · 앞에서부터 바뀜). 양수면 줄 묶음 c 가운데
  /// `(c + 1) × 8 ≤ keepBefore`인 것(끝 줄까지 그 자리 앞 — 고쳐 쓰지 않았다)의 타일은 새 판 번호로 옮겨 남기고 나머지는 다시 받는다. −1이면(바뀐 트랙 없음)
  /// 모두 남긴다. 켠 변형이 있으면(소속 펼치기 · 대범위 · 판 — 다른 트랙의 띠 · 칸을 옮기거나 가린다) 고쳐 쓴 트랙이 앞 묶음의 타일에도 닿을 수 있어
  /// −1이 아니면 모두 버리고, 바꾸기 전후의 켠 변형이 다르면 늘 모두 버린다.
  void replaceLayout(SceneLayout fresh, {Set<int>? enabled, ViewState view = ViewState.none, int keepBefore = 0}) {
    final v = controller.view;
    final snap = layout.snapshot();
    final oldVersion = layout.version, oldVariants = layout.variantKeys.join(',');
    String? heldTrack;
    int heldOrd = -1;
    double offset = 0;
    if (v.top > 0) {
      _anchor.capture(layout, v.top, v.bodyHeight, preferred: selectedEventRow);
      final held = _anchor.row;
      if (held >= 0) {
        final i = layout.trackIndexOf(held);
        heldTrack = snap.identity[i];
        heldOrd = held - layout.tracks[i].firstRow;
        offset = _anchor.offset;
      }
    }
    _anchor.clear();
    layout.reduceMotion = controller.reduceMotion;
    layout.replaceWith(fresh, enabled: enabled, view: view, from: snap);
    if (heldTrack != null) {
      for (int i = 0; i < layout.tracks.length; i++) {
        if (layout.trackIdentity(i) != heldTrack) continue;
        final row = layout.tracks[i].firstRow + heldOrd;
        if (heldOrd < layout.tracks[i].rowCount && layout.isVisible(row)) {
          _anchor.row = row;
          _anchor.offset = offset;
        }
        break;
      }
    }
    folder.forget();
    final sameVariants = layout.variantKeys.join(',') == oldVariants;
    if (keepBefore < 0 && sameVariants) {
      cache.keepChunks(chunks: null, from: oldVersion, to: layout.version);
    } else if (keepBefore > 0 && sameVariants && oldVariants.isEmpty) {
      cache.keepChunks(chunks: keepBefore ~/ chunkRows, from: oldVersion, to: layout.version);
    } else {
      cache.clear();
    }
    cache.olderVersions = const [];
    _packsByVersion.clear();
    _releaseWriting();
    _batches.clear();
    labelBatch = null;
    labelOutput = null;
    _labelSignature = 0;
    _labelViewSignature = 0;
    _labelFirstRow = 0;
    _labelLastRow = -1;
    _labelPpm = 0;
    _labelLo = 0;
    nameFade.clear();
    selectedEventId = null;
    selectedEventRow = -1;
    hoverBand = 0;
    _goneVersion = null;
    storeVersion++;
    _keepAnchor();
    notifyListeners();
  }

  /// 저장소를 바꿔 넣을 때마다 오른다([replaceLayout]). 줄 번호로 적어 둔 기억(왼쪽 칸의 줄 이름 — [RowLabels])이 이것을 보고 비운다 —
  /// 다시 지은 저장소에서는 같은 번호의 줄이 다른 나라다(DLC를 끄고 켜면 늘 다시 짓는다 — 2026-10-16).
  int storeVersion = 0;

  /// 화면의 시계가 돌아야 하는 동안 참: 움직이는 중이거나, 타일이 떠오르는 중이거나, 글줄 준비가 밀려 있을 때.
  final busy = ValueNotifier<bool>(false);
  bool _starved = false;

  /// 그리는 쪽이 부른다: 이번 장면에 못 그린 이름이 있으니 다음 장면을 달라.
  void requestFrame() {
    _starved = true;
    _syncBusy();
  }

  /// 화면의 시계가 장면마다 부른다(지난 시간 ms).
  void tick(double dtMs) {
    final flowing = layout.flowing;
    final again = _fading || _starved || _namesMoving || flowing || !folder.settled;
    _starved = false;
    controller.tick(dtMs);
    // 정착(미뤄 둔 접힘)은 움직임이 멎은 뒤 한 번에 — 그리는 중이 아니라 시계에서 셈한다.
    folder.tick(moving: controller.moving || controller.pressed, coasting: controller.velocity != Offset.zero, nowMs: _clock());
    // 자동 조감의 문턱도 그 정착에 함께(원칙 ④ — 옮기는 도중에는 바뀌지 않는다).
    if (folder.settledNow) _settleAutoBird();
    if (flowing) {
      layout.tickFlow(dtMs);
      _keepAnchor();
    }
    if (again && !controller.active.value) notifyListeners();
    _syncBusy();
    // 멎은 뒤 [clearTypeSettleMs]가 되는 장면에 한 장 더 — 마지막 장면이 회색으로 그려졌으면 ClearType으로 다시 그린다(검토 초점 2).
    // requestFrame이 아니라 notifyListeners: requestFrame은 _starved를 세워 busy를 다시 켜므로, 멈춤과 바쁨이 오가는 고리가 된다.
    // 시계가 멎어 있으면(손을 떼 관성 없이 멈춤 등) [_trackStill]의 타이머가 깨운다.
    _trackStill();
    final still = stillForClearType;
    if (still && !_wasStill) {
      _settleTimer?.cancel(); // 시계가 먼저 닿았다 — 타이머로 한 번 더 그리지 않는다
      _settleTimer = null;
      notifyListeners();
    }
    _wasStill = still;
  }

  /// ClearType을 그려도 되는 '멈춤'(설계 3-2): 손 끌기 · 두 손가락 · 관성 · 흐름 · 접힘 · 이름 옅어짐 · 도착 타일 떠오름 · 타일 기다림이 모두 없고,
  /// 그렇게 된 지 [clearTypeSettleMs]가 지났다.
  /// 손(끌기 · 두 손가락)은 `active`가 아니라 `moving`에만 있다 — `active`만 보면 끄는 동안 ClearType이 그려진다.
  /// busy와 달리 '글줄 준비 부족(_starved)'은 넣지 않는다 — 굽는 동안 회색 ↔ ClearType을 오가지 않게.
  bool get stillForClearType => _calm && _calmSince >= 0 && _clock() - _calmSince >= clearTypeSettleMs;
  bool _wasStill = true;

  /// 움직임 · 흐름 · 떠오름 · 타일 기다림 · 이름 자리 기다림이 모두 없다(기다림 시간은 빼고). [_fading] · [_waitingTiles]는 마지막 [prepare]의 값.
  /// 이름 자리(뒤의 작업자)를 기다리는 동안도 넣는다 — 옮긴 직후 타일은 이미 받아 두었어도 이름 판이 오면 이름이 드나들며 회색으로 돌아가므로
  /// (실제 앱 range 옮기기에서 장면 0 · 1만 ClearType이던 것 — 과제 6 보고 걱정 2), 그 판이 와서 가라앉을 때까지 회색으로 둔다.
  /// 보기 · 타일이 바뀐 뒤 처음 가라앉기 전에 청한 판만 기다린다([_viewSettling] — 가라앉은 뒤 강조 · 관점 이름 · 비켜 갈 구간만 바뀐 판은 빼고)
  /// · 작업자가 실패해 쉬면 기다리지 않는다.
  bool get _calm => !controller.moving && !_fading && !_namesMoving && !_waitingTiles && !(_labelsPending && labelWorker.busy) && settled;

  /// 보기 · 타일이 바뀐 뒤 처음 가라앉기 전에 이름 자리를 새로 청했고 그 답이 아직 오지 않았다.
  bool _labelsPending = false;

  /// 보기(자리 · 배율 · 크기) · 타일 · 줄이 바뀐 뒤 아직 ClearType으로 가라앉지 않았다 — 이 동안 청한 이름 판은 무슨 까닭이든 기다린다.
  /// ClearType을 허락하는 장면의 준비([prepare] 끝)에서만 내린다: 시계에서 내리면 그 뒤 첫 그림이 청한 판(옮긴 뒤 첫 그림이 비켜 갈 구간을
  /// 고쳐 다시 청하는 판)을 기다리지 않아 ClearType → 회색 → ClearType이 된다.
  bool _viewSettling = true;

  /// 진단용(검증 대본의 burst 기록): 가라앉은 지 몇 ms인가(아니면 −1) · 지금 가라앉았는가 · 이름이 드나드는가.
  double get debugCalmMs => _calm && _calmSince >= 0 ? _clock() - _calmSince : -1;
  bool get debugNamesMoving => _namesMoving;

  /// 화면에 걸린 타일 가운데 청했는데 아직 오지 않은 것이 있다(받기에 실패해 쉬는 타일은 빼고 — 영영 회색에 머물지 않게). 마지막 [prepare]의 값.
  bool _waitingTiles = false;
  bool get waitingTiles => _waitingTiles;

  /// [_calm]이 된 장면 시계의 때(아니면 −1).
  double _calmSince = -1;

  /// 지난 준비의 보기(자리 · 배율 · 크기) — 바뀌면 [_calmSince]를 처음부터.
  int _viewKey = 0;
  Timer? _settleTimer;

  /// 그림판이 장면마다 알려 준다: 이 장면을 ClearType으로 그릴 수 있는가(설정 · 굽개 · 화면 배율). 거짓이면 기다림의 타이머를 걸지 않는다.
  bool clearTypeWanted = false;

  /// 가라앉음이 시작되면 때를 적고 [clearTypeSettleMs] 뒤에 깨울 타이머를 건다 · 다시 움직이면 지운다. 준비(prepare) · 시계(tick)가 부른다.
  void _trackStill() {
    if (!_calm) {
      _calmSince = -1;
      _settleTimer?.cancel();
      _settleTimer = null;
      return;
    }
    final now = _clock();
    if (_calmSince < 0) _calmSince = now;
    final left = clearTypeSettleMs - (now - _calmSince);
    if (clearTypeWanted && _settleTimer == null && left > 0) _armSettle(left);
  }

  void _armSettle(double sceneMs) {
    _settleTimer?.cancel();
    // 장면 시계는 느리게 보기만큼 느리다 — 벽시계로는 그만큼 길게 기다린다.
    _settleTimer = Timer(Duration(microseconds: (sceneMs * Motion.slow * 1000).ceil()), () {
      _settleTimer = null;
      if (_disposed || _calmSince < 0) return;
      _syncBusy();
      if (!_calm) {
        _calmSince = -1; // 그사이 무엇이 움직였다 — 다시 가라앉을 때(준비 · 시계 · 이름 판의 도착) 처음부터 센다
        return;
      }
      final left = clearTypeSettleMs - (_clock() - _calmSince);
      if (left > 0) {
        _armSettle(left);
        return;
      }
      _wasStill = true;
      notifyListeners(); // 멈춘 뒤 150ms — ClearType으로 한 장 더
    });
  }

  bool _namesMoving = false;
  void _syncBusy() {
    _namesMoving = nameFade.animating(_clock());
    busy.value = controller.active.value || _fading || _starved || _namesMoving || layout.flowing || !folder.settled;
    // controller.active의 듣개이기도 하다: 관성 · 쫓아가기 · 돋보기 · 비행을 누름 · Esc(stop)로 멈추면 알림이 없고, 시계가 한 장면도 돌기 전이면
    // 접기도 가라앉아 있어 시계까지 멎는다 — 여기서 가라앉음을 세어 150ms 뒤 깨워야 마지막 회색 장면이 남지 않는다.
    _trackStill();
  }

  /// 장면의 시계 — 느리게 보기(`Motion.slow`)와 함께 느려진다. 타일 떠오름 · 이름 드나듦 · 접힘 정착 · 도착 고리 ·
  /// 밝기의 흐름이 이 시계를 탄다(11물결 motion ④). 장면 dt를 받는 것(조작부 · 줄 흐름 · 위젯)은 `timeDilation`이 이미 나눠 준다.
  static double Function() _stopwatchClock() => Motion.now;

  final TimelineController controller;
  final SceneLayout layout;
  late final TileCache cache;
  final double Function() _clock;
  final stats = SceneStats();

  /// 측정 모드가 장면마다의 집계를 받아 간다.
  void Function(SceneStats stats)? onPainted;

  /// 병목을 가르는 실험용 층 끄기: bands(bandFill · bandEdge) · cells · cellNames · tabs · events · fade · cut(크게 바뀌는 장면의 이름 거두기).
  final hide = <String>{};
  final draw = <DrawTile>[];
  final _packsByVersion = <int, List<int>>{};
  int level = levelMax;
  bool _fading = false;

  double get now => _clock();

  /// 떠오르는 타일이 있는 동안에는 시계가 돌아야 한다.
  bool get fading => _fading;

  List<int> _packsOf(int version) => _packsByVersion[version] ?? layout.enabledPacks;

  /// 그리기 직전에 부른다: 단계를 고르고, 보이는 타일과 미리 받을 타일을 보관에 알리고, 그릴 목록을 채운다.
  void prepare() {
    final v = controller.view;
    crowns.sync(layout, storeVersion);
    // 빈 줄 접기의 물음. 보기가 폭의 10% 넘게 옮겨졌거나 배율이 바뀌었을 때만 묻는다 — 답은 시계에서 받아 넣는다(그리는 중에는 자리를 바꾸지 않는다).
    folder.maybeAsk(v, layout.enabledPacks);
    _watchJumps(v);
    // 보기가 바뀌었다(옮기기 · 범위 바꾸기처럼 움직임 없이 한 번에 뛰는 것도) — 멈춤의 150ms를 처음부터 센다.
    // 뛴 그 장면은 이름 판 · 줄 접기를 아직 청하기 전이라, 세지 않으면 그 한 장만 ClearType이었다가 회색으로 돌아간다(과제 6 보고 걱정 2).
    final viewKey = Object.hash(v.lo, v.ppm, v.top, v.mag, v.width, v.height);
    if (viewKey != _viewKey) {
      _viewKey = viewKey;
      _calmSince = -1;
      _viewSettling = true;
    }
    level = levelFor(v.ppm, current: level);
    final version = layout.version;
    _packsByVersion[version] = layout.enabledPacks;
    draw.clear();
    _fading = false;
    _waitingTiles = false;
    stats
      ..tiles = 0
      ..covers = 0
      ..blanks = 0;
    // 화면에 걸친 줄의 번호 범위 — 판이 없으면 (위 끝 줄, 아래 끝 줄) 그대로, 집합 보기를 켜면 맨 위 판 줄(번호가 가장 큼)까지 품는다.
    final (firstRow, lastRow) = layout.rowRange(v.top, v.top + v.bodyHeight);
    // 접힌 트랙의 줄은 보이지 않지만 가는 막대를 그리려면 그 트랙의 띠가 있어야 한다 — 화면에 걸친 접힌 트랙의 줄 묶음도 받는다.
    _foldedChunks.clear();
    for (int i = 0; i < layout.tracks.length; i++) {
      if (!layout.isTrackFolded(layout.tracks[i].id)) continue;
      final top = layout.trackTop(i), bottom = top + layout.trackHeight(i);
      if (bottom < v.top || top > v.top + v.bodyHeight) continue;
      for (int r = 0; r < layout.rowCount; r++) {
        if (layout.trackIndexOf(r) == i) _foldedChunks.add(r ~/ chunkRows);
      }
    }
    // 접힌 문화권(리메이크 조각 ②)도 같다: 머리 단 안의 작은 꼬리표가 그 문화권 트랙의 띠(구역 45)에서 나온다 — 머리 단이 화면에 걸치면 받는다.
    for (int i = 0; i < layout.tracks.length; i++) {
      if (!layout.isTrackHidden(i)) continue;
      final sphere = layout.sphereIndexOfTrack(i), head = layout.sphereHeadTop(sphere);
      if (head < 0 || head + layout.sphereHeadHeight(sphere) < v.top || head > v.top + v.bodyHeight) continue;
      for (int r = 0; r < layout.rowCount; r++) {
        if (layout.trackIndexOf(r) == i) _foldedChunks.add(r ~/ chunkRows);
      }
    }
    // 접힌 민족 줄도 같다: 합쳐 놓은 한 줄에 그 묶음 줄들의 가는 막대를 그리는데, 묶음이 줄 묶음의 경계를 넘으면 보이는 줄이 하나도 없는
    // 줄 묶음의 타일은 받지 않게 된다(유리해안의 '월흔해의 백성' 줄 1~16 → 줄 묶음 1) — 화면에 걸친 합쳐진 줄의 묶음 전체를 받는다.
    for (final merged in layout.mergedGroups.entries) {
      final head = merged.key;
      if (head >= layout.rowCount || !layout.isVisible(head)) continue;
      final top = layout.rowTop(head);
      if (top + layout.geo(head).height < v.top || top > v.top + v.bodyHeight) continue;
      for (int r = head; r < merged.value && r < layout.rowCount; r++) {
        _foldedChunks.add(r ~/ chunkRows);
      }
      // 대범위 가지는 드는 줄이 번호 차례가 아니라 합쳐 놓은 줄보다 **번호가 작은 줄**도 들 수 있다 —
      // 위의 범위로는 빠지므로 정확한 목록(`mergedRows`)도 함께 받는다(11물결 stack3 ㈒).
      for (final r in layout.mergedRows[head] ?? const <int>[]) {
        if (r >= 0 && r < layout.rowCount) _foldedChunks.add(r ~/ chunkRows);
      }
    }
    if (firstRow < 0 && _foldedChunks.isEmpty) {
      cache.want(const [], const []);
      _trackStill();
      if (stillForClearType) _viewSettling = false;
      return;
    }
    final c0 = firstRow < 0 ? 0 : firstRow ~/ chunkRows, c1 = firstRow < 0 ? -1 : lastRow ~/ chunkRows;
    final x0 = tileOf(v.lo, level), x1 = tileOf(v.hi, level);
    final visible = <TileKey>[], ahead = <TileKey>[];
    for (int chunk = c0; chunk <= c1; chunk++) {
      if (!_chunkVisible(chunk)) continue;
      for (int x = x0; x <= x1; x++) {
        visible.add(TileKey(level, x, chunk, version));
      }
    }
    for (final chunk in _foldedChunks) {
      if (chunk >= c0 && chunk <= c1 && _chunkVisible(chunk)) continue; // 이미 넣었다
      for (int x = x0; x <= x1; x++) {
        visible.add(TileKey(level, x, chunk, version));
      }
    }
    // 미리 받기: 좌우 한 장 · 위아래 줄 묶음 하나 · 단계 위아래 하나, 그리고 어느 때든 메울 수 있게 맨 윗단계.
    for (int chunk = c0 - 1; chunk <= c1 + 1; chunk++) {
      if (chunk < 0 || !_chunkVisible(chunk)) continue;
      final edge = chunk < c0 || chunk > c1;
      for (int x = x0 - 1; x <= x1 + 1; x++) {
        if (edge || x < x0 || x > x1) ahead.add(TileKey(level, x, chunk, version));
      }
      if (edge) continue;
      for (int x = tileOf(v.lo, levelMax); x <= tileOf(v.hi, levelMax); x++) {
        ahead.add(TileKey(levelMax, x, chunk, version));
      }
      if (level < levelMax) {
        for (int x = x0 >> 2; x <= x1 >> 2; x++) {
          ahead.add(TileKey(level + 1, x, chunk, version));
        }
      }
      if (level > 0) {
        for (int x = tileOf(v.lo, level - 1); x <= tileOf(v.hi, level - 1); x++) {
          ahead.add(TileKey(level - 1, x, chunk, version));
        }
      }
    }
    cache.want(visible, ahead);

    final now = _clock();
    for (final key in visible) {
      final own = cache.get(key);
      if (own != null) {
        final age = now - (cache.arrivedAt(key) ?? now - Motion.enter);
        final alpha = controller.reduceMotion || hide.contains('fade') ? 1.0 : (age / (controller.moving ? Motion.micro : Motion.enter)).clamp(0.0, 1.0);
        Rect? rect;
        Tile? under;
        if (alpha < 1) {
          _fading = true;
          rect = _rectOf(key, v);
          under = cache.cover(key);
          if (under != null) draw.add(DrawTile(under, key, rect, 1, true));
        }
        draw.add(DrawTile(own, key, null, alpha, false, fadeRect: rect, hasUnder: under != null));
        stats.tiles++;
      } else {
        if (!cache.failedRecently(key)) _waitingTiles = true;
        final cover = cache.cover(key);
        if (cover != null) {
          draw.add(DrawTile(cover, key, _rectOf(key, v), 1, true));
          stats.covers++;
        } else {
          stats.blanks++;
        }
      }
    }
    // 켜고 끄기의 흐름 동안 사라지는 줄(옛 조합에만 있던 줄)은 직전 조합의 타일을 그 줄 자리만큼만 잘라 그린다 —
    // 내용이 팍 사라지지 않고 줄이 접히는 대로 잘려 나간다(움직임 원칙 ②). 받아 둔 것만 쓰고(새로 받지 않는다) 이름 자리는 여기서 모으지 않는다.
    final gone = _goneVersion;
    if (gone != null && !layout.flowing) {
      _goneVersion = null;
    } else if (gone != null && firstRow >= 0) {
      for (int chunk = c0; chunk <= c1; chunk++) {
        for (int r = chunk * chunkRows; r < (chunk + 1) * chunkRows && r < layout.rowCount; r++) {
          if (!layout.isGoneRow(r)) continue;
          final top = v.yOf(layout.rowTop(r)), bottom = top + layout.geo(r).height;
          if (bottom - top <= 0) continue;
          for (int x = x0; x <= x1; x++) {
            final key = TileKey(level, x, chunk, gone);
            final tile = cache.get(key);
            if (tile == null) continue;
            final left = v.xOf(tileOrigin(level, x)), right = v.xOf(tileOrigin(level, x + 1));
            draw.add(DrawTile(tile, key, Rect.fromLTRB(left.roundToDouble(), top, right.roundToDouble(), bottom), 1, true, ghost: true));
          }
        }
      }
    }
    if (firstRow >= 0) _askLabels(v, firstRow, lastRow);
    _syncBusy();
    _trackStill();
    if (stillForClearType) _viewSettling = false; // 이 장면이 ClearType이다 — 이제부터 강조 · 관점 이름 · 비켜 갈 구간만 바뀐 판은 기다리지 않는다
  }

  final _foldedChunks = <int>{};

  bool _chunkVisible(int chunk) {
    final first = chunk * chunkRows;
    if (first >= layout.rowCount) return false;
    for (int r = first; r < first + chunkRows && r < layout.rowCount; r++) {
      if (layout.isVisible(r)) return true;
    }
    return false;
  }

  /// 타일이 덮는 자리(배치 px): 가로는 타일의 시간 범위, 세로는 줄 묶음.
  Rect _rectOf(TileKey key, SceneView v) {
    final left = v.xOf(tileOrigin(key.level, key.x)), right = v.xOf(tileOrigin(key.level, key.x + 1));
    double top = double.infinity, bottom = double.negativeInfinity;
    for (int r = key.chunk * chunkRows; r < (key.chunk + 1) * chunkRows && r < layout.rowCount; r++) {
      if (!layout.isVisible(r)) continue;
      final y = v.yOf(layout.rowTop(r));
      if (y < top) top = y;
      if (y + layout.geo(r).height > bottom) bottom = y + layout.geo(r).height;
    }
    // 접힌 트랙의 줄 묶음: 보이는 줄이 없으니 그 트랙들의 접힌 상자가 자리다.
    if (top == double.infinity) {
      for (int r = key.chunk * chunkRows; r < (key.chunk + 1) * chunkRows && r < layout.rowCount; r++) {
        final i = layout.trackIndexOf(r);
        final y = v.yOf(layout.trackTop(i));
        if (y < top) top = y;
        if (y + layout.trackHeight(i) > bottom) bottom = y + layout.trackHeight(i);
      }
    }
    return Rect.fromLTRB(left.roundToDouble(), top, right.roundToDouble(), bottom);
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(notifyListeners);
    controller.active.removeListener(_syncBusy);
    labelWorker.dispose();
    _settleTimer?.cancel();
    busy.dispose();
    super.dispose();
  }
}
