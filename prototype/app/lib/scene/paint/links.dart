import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../color_mix.dart';
import '../emphasis.dart' show Emphasis, Spot;
import '../layout.dart';
import '../reserved.dart';
import '../sprites.dart';
import '../text_paragraph.dart' show SceneText, TextLook;
import '../tile.dart';
import 'bands.dart';
import 'context.dart';
import 'figures.dart' show FigureLook;
import 'grid.dart';
import 'hangs.dart' show HangLayer, HangLook;
import 'host_folders.dart';
import 'ink.dart';
import 'look.dart';
import 'paint_pick.dart';
import 'scopes.dart';
import 'strips.dart' show CellKind, CellStyle, StripLayer;

// 관계선: 건국 · 멸망 네모(구역 20) · 승계선(21) · 소속선(22). 값의 뜻은 docs/계약-아카이브-3단계.md 6-10절,
// 자리와 모양은 docs/명세-3단계/04-관계선.md(1절 상수 · 2절 네모 · 3절 길 고르기 · 4절 선의 모양 · 6-5 부흥선 묶기 · 7-2 조감).
//
// 층 차례(명세 0절): 2층 '띠 뒤 선'은 [paintTile]에서, 4층 '띠 위 표식'(문 → 관문 · 다리 · 합류 조각 · 고리 → 네모 → 단추)은 [paintFront]에서.
// 한 장면의 셈은 [beginFrame]에서 한 번만 한다 — 같은 항목이 여러 타일에 실려 오므로 항목 번호로 한 번만 읽고, 타일 경계에서 잘린 조각(flags 1 · 2)은 이어 붙여 제 끝을 되찾는다.
// 그리기도 '이 장면의 첫 온전한 타일' 한 번뿐이다 — 선 하나가 여러 타일에 걸리므로 타일마다 그리면 두 번 그려진다(명세 8-5절 2).
class LinkLayer extends TileLayer {
  /// 구역 번호(계약 6-10절).
  static const secSquare = 20, secLink = 21, secPart = 22;

  /// 옮겨 앉기의 끝 둘(리메이크 2부 · 결정 #3 A — 내보내기 `export/links.mjs` · ref = 그 토막 · a = 0 앞 / 1 뒤 · text2 = 짝 열쇠).
  static const secMove = 52;

  /// 트랙을 건너는 승계의 짝 꼬리표(감독 결정 (2) 2026-10-25 · 이어 주는 선 걸음 3 · 4 — 내보내기 `export/links.mjs` · ref = 이 끝의 띠 ·
  /// name · color = 상대 이름 · 색 · a = 0 앞 끝 / 1 뒤 끝 · b = 상대 띠 · c = 승계 종류 · text2 = 상대 uid). 그리기는 [_planCross].
  static const secCross = 60;

  final _sprites = LinkSprites();
  final _marks = ScopeMarks();

  /// 밝기 상태(명세 06의 3절). 총괄이 통합할 때 장면에 이어 준다 — 아직 없으면 중립(모두 1)으로 그린다.
  Emphasis? emphasis;

  /// 필터의 '승계선' 세 값(명세 04의 4-5절): 0 모두 · 1 직접만 · 2 끔. 총괄이 채운다.
  int successionMode = 0;

  /// 필터의 '소속선' 체크.
  bool showPartOf = true;

  /// 커서가 올라간 띠(띠 층과 같은 값 — 없으면 `scene.hoverBand`) · 커서가 올라간 선의 두 끝. 총괄이 채운다.
  int? hotBand;
  (int, int)? hotLink;

  /// 켠 대범위의 uid · 소속을 펼친 띠의 번호. 줄이 옮겨 가는 것은 줄 쌓기의 몫이고, 여기는 단추의 모양(`▸`/`▾`)과
  /// 대범위 테두리 · 부흥선 묶음을 켤지만 본다. 총괄이 채운다(아직 `c.layout`에 그 밭이 없다).
  final scopesOn = <String>{};
  final expanded = <int>{};

  /// 띠 층 — 조감의 내림줄 · 오름줄이 띠 안 이름 · 단추를 비키는지 여기서 묻는다(`BandLayer.birdClear` · js:7602 · 7654 · 7657).
  /// 그리개가 이어 주고(층 배선), 단추 층에도 같은 것을 건넨다. 띠 층의 `beginFrame`이 이 층보다 **먼저** 돌아야 한다.
  BandLayer? get bands => _bands;
  BandLayer? _bands;
  set bands(BandLayer? layer) {
    _bands = layer;
    _marks.bands = layer;
  }

  /// 조감이 아니거나 띠 층이 없으면 늘 참(지금까지와 같다).
  bool _birdClear(int row, double x) => !_bird || (_bands?.birdClear(row, x) ?? true);

  /// 칸 층 — 꼬리표 밑 흰 사슬의 종이 자리([StripLayer.chainAt])를 맞히기에서 묻는다. 그리개가 이어 준다(없으면 묻지 않음 — 지금까지와 같다).
  StripLayer? strips;

  /// 바탕 눈금 층 — 이번 장면에 그은 연도 세로줄의 열([GridLayer.columns]). 띠 뒤 선의 세로 획과 같은 자리의 줄을 그 밑에서 걷는다
  /// (0.1.1 · 이어 주는 선 미룸 1 — [_maskGrid]). 그리개가 이어 준다(없으면 걷지 않음).
  GridLayer? grid;

  /// 띠 번호 → 네모(장면마다 다시).
  final _squares = <int, _Square>{};

  /// 이번 장면에 승계선이 **떠나는** 띠(꼬리표 갈래 E의 꼬리 마름모 — 설계 4-1 '구멍과 꼬리 마름모'). 선을 숨기면(메뉴 '숨기기') 비운다.
  final _outs = <int>{};

  /// 줄 → 그 줄의 네모(왼쪽 끝 차례 — [_readSquares]가 정렬한다. (가-0)의 이웃 띠 찾기가 이분 탐색한다).
  final _rowSquares = <int, List<_Square>>{};

  /// (가-0) 앞 나라 끝 지키기(명세 04 3-6 · 스위치 route): 이 장면에 선대마다 세운 줄기 — (선대 띠 × 4 + 종류) → (통로 x, 꼬리 내림인가) ·
  /// 선대 띠 → 세운 줄기 수 · 관문을 이미 둔 꼬리 내림 줄기(같은 줄기의 선이 띠 위 획을 겹쳐 긋지 않게).
  final _stems = <int, (double, bool)>{};
  final _stemCount = <int, int>{};
  final _stemGated = <int>{};

  /// 꼬리 마름모 밑 줄기의 x — (선대 띠 × 4 + 종류) → x. (가-0) 꼬리 내림([_exitAt])과 꼬리 내림 갈래(fell)가 함께 쓴다:
  /// 같은 열쇠는 같은 x(관문 [_tailGate]가 한 번만 서므로)이고, 새 x를 잡을 때마다 [_stemCount]를 올린다(다른 종류의 줄기와 겹치지 않게 · 검증 지적).
  final _tails = <int, double>{};

  /// 선 감사: 꼬리 관문(열쇠 → 띠 위 조각의 차례 범위)과, 지금 세우는 선이 남이 이미 그은 꼬리 관문을 함께 쓰는 몫
  /// (그 선의 보이는 px에 더한다 — 같은 줄기의 둘째 선이 '안 보임'으로 잘못 세어지지 않게 · 검증 지적).
  final _gateSpan = <int, (int, int)>{};
  final _shareSpans = <(int, int)>[];

  /// 0.1.1 승계선 나머지(스위치 route · 명세 04 3-6 · 조사 결함 5 · 6 · 13 · 43): 이번 장면에 이미 세운 승계선의 세로 획(x · 위 · 아래 · 선대 띠 — 세로 기둥 표) ·
  /// 줄 위 틈마다 놓인 가로 토막(틈의 줄 → (y · 왼 · 오른) — 골목 층 표) · 구멍마다 먼저 든 선(옆으로: 가로의 시작 x · y / 위에서: 세로 x · 틈 y — 합류 점).
  final _cols = <(double, double, double, int)>[];
  final _lanes = <int, List<(double, double, double)>>{};
  final _holeSide = <int, (double, double, bool)>{};
  final _holeTop = <int, (double, double)>{};

  /// 틈으로 들 몫의 어림(선 → (틈 열쇠, 왼, 오른, 무게) — [_claimGaps] · [_lane]). 선을 세우면 지운다.
  final _claims = <_LinkIn, (int, double, double, double)>{};

  /// 띠 → 이 장면에 그 띠에서 나가는 다른 줄 선의 통로 수(위 · 아래 가운데 큰 쪽 — [_recount]). 띠 밖 통로가 설 자리를 어림한다([_columnFree]).
  final _chanCount = <int, int>{};

  /// 이번 장면의 계획: 띠 뒤 선 · 띠 위 조각.
  final _back = <_Back>[];
  final _top = <_Top>[];

  /// 줄 → 이미 자리를 잡은 구간(네모) — 단추가 비켜 앉을 때 본다(지금 연표의 reserved).
  final _reserved = <int, List<(double, double)>>{};

  /// 사건 이름 · 점이 비켜 갈 구간(지금 연표의 `_sqZones` · `plan.zones` · 단추가 차지한 자리). px으로 모아 두고 장면 끝에 분으로 적는다.
  /// 값은 (왼쪽, 오른쪽, 글줄, 점도 미는가, 세기, 미는 쪽)이다 — 세기 · 미는 쪽의 뜻은 `ReservedZone`에 적었다.
  final _zones = <int, List<(double, double, int, bool, int, int)>>{};

  /// 맞히기의 자리 기록(단추 → 네모 → 선 차례로 본다).
  final _hits = <_HitArea>[];

  /// 선 감사(이어 주는 선 걸음 1 — 끊김 0의 잣대 · [LineAudit]): 이번 장면에 세운 선마다 (종류, 두 끝 띠, 띠 뒤 · 띠 위 조각의 차례 범위).
  /// 검사 기록(c.debug)이나 찍기([LineAudit.capture])를 켰을 때만 모으고 센다 — 그림 · 셈은 그대로다.
  final _audit = <_AuditEntry>[];
  final _auditMissed = <String>[];
  bool _auditing = false;

  /// 이번 장면에 놓은 짝 꼬리표(구역 60 · [_planCross]) — 그리기 · 맞히기 · 풍선 글이 함께 읽는다.
  final _crossTags = <_CrossTag>[];

  /// 선대 끝이 화면 오른쪽 밖인 승계선의 후대 쪽 끝(감독 고름 2026-10-26 ① '후대 쪽만이라도 그림' · [_planLink]) — 후대 띠 → 그 띠 시작의 짝 꼬리표 `← ●앞 나라`.
  /// 들어오는 짧은 선은 후대마다 한 번만 긋는다(같은 구멍으로 드는 선대가 여럿이어도 한 획 — 꼬리표가 ' · '로 잇는다).
  final _lateIns = <int, _CrossEnd>{};

  /// 그 꼬리표들의 자리(그림판 px — [LinkTagBoxes]로 실 층에 넘김).
  final _tagBoxes = <ui.Rect>[];

  /// 굴 문 훑기([_tunnels] · 명세 04 3-9 · 이어 주는 선 걸음 5): 띠 뒤 꺾은선([_back]의 차례)마다 두 끝 띠(앞, 뒤) · 굴 문을 둔 띠 · 굴 문 토막의 길이.
  /// 두 끝 띠는 선을 세운 자리([_own])에서 적고, 굴 문은 모든 선을 정한 뒤 따로 한 번 훑어 둔다 — 선 감사가 '표시 있음'으로 센다.
  final _ends = <int, (int, int)>{};
  final _tunnelBands = <int, Set<int>>{};
  final _tunnelPx = <int, double>{};

  /// 이번 장면의 띠 몸통([_bodiesOf] — 굴 문 훑기 · 선 감사가 함께 쓴다).
  List<AuditBody>? _bodyCache;

  /// 이번 장면에 이 층을 그릴 타일(메움 타일이 아니고 다 떠오른 첫 타일).
  Tile? _host;
  final _markDone = <int>{};
  final _edge = <int, int>{};
  final _tabRightOf = <int, double?>{};

  /// 조감(밀도 2)인가 · 조감의 모양 c(8px 띠)인가. 줄 높이 · 자리는 layout이 주고, 여기는 모양만 바꾼다.
  bool _bird = false, _birdC = false;

  /// 이 장면의 문 높이 · 가는 선(부분 승계)의 굵기(보통 · 조감 a·b · 조감 c).
  double _doorH = LinkLook.door, _thinW = LinkLook.thinW;

  /// 가는 선을 픽셀 칸 가운데(.5)에 맞춰 긋는가 — 보통 밀도의 1px 선만(조감의 더 가는 선은 그대로). js의 `G.thin.crisp`.
  bool _thinCrisp = true;

  /// 가는 선의 자리를 픽셀 칸 가운데로(js `crispAt` — `Math.round(v − .5) + .5`와 같은 값).
  double _crisp(double v) => _thinCrisp ? v.floorToDouble() + .5 : v;

  /// 줄마다 아래쪽 단(인물 막대 · 품은 속국 칸 · 기관 칸)과 띠 밑에 덧붙은 것(매달린 속국 이름표 · 구역 탭)의 가로 구간(장면마다 처음 물을 때 한 번 모음).
  final _lowerSpans = <int, List<(double, double)>>{};

  /// 밝기 캐시(같은 [Emphasis.version]이면 다시 셈하지 않는다).
  final _linkAlphaOf = <int, double>{};
  final _bandAlphaOf = <int, double>{};
  int _emphVersion = -1;

  int _edgeOf(int color) => _edge[color] ??= mixOklab(0xff000000 | color, Look.ink, .84);

  @override
  void setScale(double scale) {
    _sprites.setScale(scale);
    _marks.setScale(scale);
  }

  // ───────────────────────── 밝기(명세 06의 3절) ─────────────────────────

  /// 승계선 · 소속선 · 그 문과 조각: 고른 것이 있으면 .14, 고른 띠에 닿는 것만 1(css 408 · 911).
  double linkAlpha(int from, int to) {
    final e = emphasis;
    if (e == null) return 1;
    return _linkAlphaOf[(from << 20) ^ to] ??= e.linkAlpha(from, to);
  }

  /// 승계선이 '짙게'인 정도(0~1) — 고른 띠에 닿으면(`.is-selected` · 흐름을 탐), 고른 것이 없을 때 올린 띠에 닿거나 선 위에 커서가 있으면(`.is-hot` · `:hover`) 1.
  /// 짙어지는 것은 색뿐이다: 선의 색이 띠 테 빛깔에서 꼬리 마름모 빛깔로(LinkLook.liftedInk — 2026-10-16 관계선 색 '가'부터. 예전에는 평소 짙기 .5 · .9 …가 1이 되었다).
  /// 부정된 나라에 닿는 선의 옅음(.2)은 투명도라 그대로 1로 올린다. 굵기는 그대로(css 405 · 409 · 903~904 · 910 · 1639).
  /// 고른 것이 있는 동안의 올림은 짙게 하지 않는다 — `.tl.is-picked .tl-link:not(.is-selected) { opacity: .14 }`가 `.is-hot` · `:hover`보다 세다.
  double _lift(int from, int to, PaintContext c) {
    final e = emphasis;
    if (!(e?.look.picked ?? false)) {
      final hot = hotBand ?? c.scene.hoverBand;
      if (hot != 0 && (from == hot || to == hot)) return 1;
      final l = hotLink;
      if (l != null && l.$1 == from && l.$2 == to) return 1;
    }
    return e?.linkLift(from, to) ?? 0;
  }

  /// 평소 짙기 [base]를 [lift]만큼 1로 올린 값.
  static double _lifted(double base, double lift) => base + (1 - base) * lift;

  /// 네모 · 할거기 칠처럼 한 띠에 딸린 것: 그 띠의 밝기(css 330~331 · 336).
  double bandAlpha(int band, int row) {
    final e = emphasis;
    if (e == null) return 1;
    return _bandAlphaOf[(band << 12) ^ row] ??= e.bandAlpha(band, row);
  }

  /// 고른 동안 옅어지는 단추 · 칸의 밝기(css 481 — `.tl.is-picked .tl-mem { opacity: .5 }`).
  double get dimPicked => emphasis?.cellDim ?? 1;

  /// 같은 줄의 이음매(다리 · 그 문)가 두 띠의 흐리지 않는 조명 구간에 들면 고른 동안에도 .9 그대로(css 911~912 · T:7394).
  /// 조명이 흐르는 동안에는 켜지는 구간과 꺼지는 구간이 함께 오므로 **반을 넘긴 구간만**(`glow > .5`) '밝다'로 본다 —
  /// 이음매의 밝기는 0/1로만 갈리는 값이라, 켜짐과 꺼짐이 스치는 한복판에서 한 번만 바뀐다.
  bool _lit(_LinkIn it, double centerX, PaintContext c) {
    final e = emphasis;
    if (e == null || !it.seam || !e.look.lit) return false;
    bool inside(int band) {
      for (final Spot s in e.spotsOf(band)) {
        if (s.glow <= .5) continue;
        final a = c.v.xOf(s.start), b = c.v.xOf(s.end);
        if (centerX >= a - 3 && centerX <= b + 3) return true;
      }
      return false;
    }

    return inside(it.from) && inside(it.to);
  }

  @override
  void beginFrame(PaintContext c) {
    _folders = null;
    _squares.clear();
    _outs.clear();
    _rowSquares.clear();
    _stems.clear();
    _stemCount.clear();
    _stemGated.clear();
    _tails.clear();
    _gateSpan.clear();
    _shareSpans.clear();
    _cols.clear();
    _lanes.clear();
    _holeSide.clear();
    _holeTop.clear();
    _claims.clear();
    _chanCount.clear();
    _back.clear();
    _top.clear();
    _reserved.clear();
    _zones.clear();
    _hits.clear();
    _crossTags.clear();
    _tagBoxes.clear();
    _lateIns.clear();
    _markDone.clear();
    _tabRightOf.clear();
    _lowerSpans.clear();
    _host = null;
    _audit.clear();
    _auditMissed.clear();
    _ends.clear();
    _tunnelBands.clear();
    _tunnelPx.clear();
    _bodyCache = null;
    _auditing = c.debug != null || LineAudit.capture;
    final e = emphasis;
    if (e == null || e.version != _emphVersion || e.active) {
      _linkAlphaOf.clear();
      _bandAlphaOf.clear();
      _emphVersion = e?.version ?? -1;
    }
    final shape = c.layout.birdShape;
    _bird = shape != null;
    _birdC = shape == BirdShape.c;
    _doorH = shape?.door ?? LinkLook.door;
    _thinW = !_bird ? LinkLook.thinW : (_birdC ? BirdLook.thinWC : BirdLook.thinW);
    _thinCrisp = !_bird;
    if (c.hide.contains('links')) {
      _publishZones(c);
      LinkColumns._of[c.scene] = const [];
      return;
    }
    for (final d in c.scene.draw) {
      if (!d.isCover && d.alpha >= 1) {
        _host = d.tile;
        break;
      }
    }
    if (_host == null && c.scene.draw.isNotEmpty) _host = c.scene.draw.first.tile;
    _readSquares(c);
    _plan(c);
    _planMoves(c);
    _publishColumns(c);
    if (PaintPick.route) _tunnels(c); // 모든 선을 정한 뒤 따로 한 번 — 짝 꼬리표가 굴 문도 비키게 그 앞에
    // 짝 꼬리표(구역 60)는 제 스위치 pair(감독 고름 2026-10-26 다-1 — 선 길 route에서 뗌 · 기본 켬). 선 길을 꺼도 [_lineSpans]가 옛 길의 선 · 관문을 비킨다.
    // 끄면 놓지 않아 그리기 · 누름 · 풍선 글이 함께 빈다.
    if (PaintPick.pair) _planCross(c);
    LinkTagBoxes._of[c.scene] = [..._tagBoxes];
    if (_auditing) _runAudit(c);
    _marks.collect(c, this, _reserved, _markDone);
    _publishZones(c);
  }

  /// 대범위 표식(단추)이 자리를 적을 때 쓴다 — 단추는 늘 세기 0(이름 줄 전체를 막고) · 오른쪽으로 민다(js:6957~6959).
  void addZone(int row, double l, double r, int line, bool noDot) => _zone(row, l, r, line, noDot, 0, 1);

  /// 이번 장면의 비켜 갈 구간을 분으로 바꿔 통째로 적는다(총괄의 `ReservedZones` — 같은 값이면 번호가 오르지 않는다).
  void _publishZones(PaintContext c) {
    final v = c.v;
    final out = <int, List<ReservedZone>>{};
    for (final e in _zones.entries) {
      final list = <ReservedZone>[];
      for (final z in e.value) {
        list.add(ReservedZone(v.minuteAt(z.$1), v.minuteAt(z.$2), line: z.$3, noDot: z.$4, strength: z.$5, dir: z.$6));
      }
      if (list.isNotEmpty) out[e.key] = list;
    }
    ReservedZones.of(c.scene).put('links', out);
  }

  void _zone(int row, double l, double r, int line, bool noDot, int strength, int dir) => (_zones[row] ??= []).add((l, r, line, noDot, strength, dir));

  /// 이번 장면의 세로 기둥(승계 · 부흥선 묶음 · 옮겨 앉기의 띠 뒤 꺾은선의 세로 획)을 장면 곁에 적는다 — 사람 띠의 실 층이 읽고 비킨다([LinkColumns]).
  void _publishColumns(PaintContext c) {
    final out = <LinkColumn>[];
    for (final b in _back) {
      if (b.kind != _Back.kLink) continue;
      final pts = b.pts;
      for (int i = 1; i < pts.length; i++) {
        final a = pts[i - 1], z = pts[i];
        if ((a.dx - z.dx).abs() > 1e-6 || (a.dy - z.dy).abs() < 1) continue;
        out.add(LinkColumn(a.dx, math.min(a.dy, z.dy), math.max(a.dy, z.dy)));
      }
    }
    LinkColumns._of[c.scene] = out;
  }

  // ───────────────────────── 네모 (구역 20) ─────────────────────────

  /// 구역 20을 모아 띠마다 네모 하나를 셈한다. 타일에 잘려 온 조각은 이어 붙인다(잘리지 않은 쪽이 제 끝).
  void _readSquares(PaintContext c) {
    final raw = <int, _SquareIn>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      final s = t.section(secSquare);
      if (s.count == 0) continue;
      final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
      final ref = s.u(Tile.itemRef), row = s.u(Tile.itemRow), flags = s.u(Tile.itemFlags), color = s.u(Tile.itemColor);
      final a = s.u(Tile.itemA), b = s.u(Tile.itemB), cc = s.u(Tile.itemC), name = s.u(Tile.itemName);
      final origin = t.origin.toDouble();
      for (int i = 0; i < s.count; i++) {
        final it = raw[ref[i]] ??= _SquareIn(ref[i], row[i], color[i], a[i], b[i].toDouble(), cc[i].toDouble());
        final lo = origin + x0[i], hi = origin + x1[i];
        if (flags[i] & Tile.clipLeft == 0) {
          it.start = lo;
          it.clipLeft = false;
        } else if (it.clipLeft && lo < it.start) {
          it.start = lo;
        }
        if (flags[i] & Tile.clipRight == 0) {
          it.end = hi;
          it.clipRight = false;
        } else if (it.clipRight && hi > it.end) {
          it.end = hi;
        }
        it.name ??= t.text(name[i]);
      }
    }
    for (final it in raw.values) {
      final sq = _square(c, it);
      if (sq == null) continue;
      _squares[it.band] = sq;
      (_rowSquares[it.row] ??= []).add(sq);
    }
    for (final list in _rowSquares.values) {
      list.sort((a, b) => a.x1.compareTo(b.x1));
    }
  }

  /// 지금 연표의 `_squares`(명세 2절) 그대로. 좌표는 배치 px이라 트랙 좌표의 0 · W가 여기서는 [PaintContext.left] · [PaintContext.w]다.
  _Square? _square(PaintContext c, _SquareIn it) {
    final layout = c.layout;
    if (it.row >= layout.rowCount || !layout.hasBody(it.row)) return null;
    final v = c.v;
    final y = _anchorY(c, it.row);
    final ppm = v.ppm;
    final xs = v.xOf(it.start), xe = v.xOf(it.end);
    final x1 = xs - (it.unknownStart ? LinkLook.fade : 0);
    final x2 = xe + (it.unknownEnd ? LinkLook.fade : 0);
    // 확정 해: 연대 폭이 있으면 바깥 끝에서 b · c(분)만큼 안쪽에 선다.
    final xStart = it.rangeStart ? xs + it.b * ppm : xs;
    final xEnd = it.rangeEnd ? xe - it.c * ppm : xe;
    // 조감에는 네모가 없다(명세 7-2) — 선이 띠 끝 가운데에 닿게 두 끝만 돌려준다.
    if (_bird) {
      return _Square(
        band: it.band, row: it.row, color: it.color, y: y, x1: x1, x2: x2, fc: x1, ec: x2, showF: false, showE: false,
        bandStart: xs, bandEnd: xe, xStart: xStart, xEnd: xEnd, unknownStart: it.unknownStart, unknownEnd: it.unknownEnd, name: it.name ?? '',
      );
    }
    // 꼬리표 갈래 E(설계 4-1 '구멍과 꼬리 마름모'): 구멍은 왼쪽 끝에서 7(영토 밖 9), 꼬리 마름모는 오른쪽 끝에서 7 — 이음매에서도 비켜 앉지 않는다
    // (네모와 달리 둘이 다른 꼴이라 맞닿아도 헷갈리지 않는다). 미정인 끝은 예전처럼 확정 해의 점선 동그라미.
    // 감독 2026-10-26 수정 4: 구멍은 언제나 띠의 맨 앞, 마름모는 맨 뒤 — 연대 폭(startRange · endRange)이 있어도 확정 해로 안쪽에 들지 않는다
    // (예전 네모의 max(확정 해, 끝 + 여백)이 남아 확대할수록 구멍이 이름 쪽으로 들어왔다 — 서고 미리보기 timeline.js `_squares`는 처음부터 끝 고정).
    final hole = TagLook.holeAt(_bands?.endOf(it.band) ?? TagEnd.cham, G.head); // 두 장 꼬리표: 구멍은 이름 색줄(14)의 귀에 맞춤
    var fc = it.unknownStart ? xStart : x1 + hole;
    var ec = it.unknownEnd ? xEnd : x2 - TagLook.diamondX;
    var showF = true, showE = !it.ongoing;
    // 타일에 잘려 반대쪽 끝을 모르면 띠가 화면보다 넓다는 뜻이다 — 생략 문턱(폭)을 걸지 않는다.
    // 구멍은 띠가 16px 이상일 때, 마름모는 구멍과 떨어져 설 수 있는 30px 이상일 때만.
    final w = it.clipLeft || it.clipRight ? double.infinity : x2 - x1;
    if (w < 30) showE = false;
    if (w < 16) {
      showF = showE = false;
      fc = ec = (x1 + x2) / 2;
    }
    final l = c.left, r = c.w, half = LinkLook.half;
    // 띠의 맨 앞(미정이면 확정 해)이 화면 왼쪽 밖이면 구멍은 없다 — 보이는 자리로 따라오지 않는다(맨 뒤 · 마름모도 같음).
    showF = showF && (it.unknownStart ? xStart : xs) >= l - 1 && fc - half >= l - .5 && fc + half <= r + .5;
    showE = showE && (it.unknownEnd ? xEnd : xe) <= r + 1 && ec - half >= l - .5 && ec + half <= r + .5;
    return _Square(
      band: it.band, row: it.row, color: it.color, y: y, x1: x1, x2: x2, fc: fc, ec: ec, showF: showF, showE: showE,
      bandStart: xs, bandEnd: xe, xStart: xStart, xEnd: xEnd, unknownStart: it.unknownStart, unknownEnd: it.unknownEnd, name: it.name ?? '',
    );
  }


  /// 책갈피 탭의 오른쪽 끝(지금 연표의 `p._tabR`). 탭을 그리는 층(bands.dart)이 잰 값을 나눠 쓸 길이 아직 없어 같은 식으로 다시 잰다.
  /// 조감에는 탭이 없다(`G_BIRD.tab = 0`).
  ///
  /// 꼬리표 갈래 E: 탭 대신 띠 안 머리의 이름 끝(띠 층이 잰 [BandLayer.headNameEnd]) — 위에서 띠로 드는 줄 · 합류가 이름을 가로지르지 않게.
  double? _tabRight(PaintContext c, _Square sq) => _bird ? null : _tabRightOf.putIfAbsent(sq.band, () => _bands?.headNameEnd[sq.band]);

  // ───────────────────────── 계획 세우기 ─────────────────────────

  void _plan(PaintContext c) {
    final linkById = <int, _LinkIn>{};
    final partById = <int, _PartIn>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      _readLinks(t, linkById);
      _readParts(t, partById);
    }
    final links = linkById.values.toList();
    final parts = partById.values;
    // 꼬리 마름모는 승계선이 떠나는 띠에만(선을 숨긴 보기에는 없다).
    if (successionMode != 2) {
      for (final l in links) {
        _outs.add(l.from);
      }
    }
    // 구멍 · 마름모의 자리를 먼저 적어 둔다 — 단추가 비켜 앉을 구간(지금 연표의 reserved).
    // 두 장 꼬리표(감독 결정 '두 장 ㄴ'): 구멍 · 마름모는 이름 색줄(띠 윗변 + 7)에, 사건은 몸통의 흰 사건 칸에 있어 서로 다른 줄이다 —
    // 예전(갈래 E · 첫 글줄)처럼 사건 글자 · 점이 비켜 갈 구간은 적지 않는다(머리 이름의 구간을 없앤 것과 같은 까닭 — bands.dart _placeHead).
    for (final sq in _squares.values) {
      final lane = _reserved[sq.row] ??= [];
      const half = TagLook.holeR + 1 + LinkLook.sqClear; // 2.5 + 1 + 1.5 = 5
      for (final (at, on) in [(sq.fc, sq.showF), (sq.ec, sq.showE && _outs.contains(sq.band))]) {
        if (!on) continue;
        lane.add((at - half, at + half));
      }
      _hits.add(_HitArea.rect(LinkHitKind.square, sq.band, 0, '', ui.Rect.fromLTRB(sq.fc - half, sq.y - half, sq.ec + half, sq.y + half)));
    }
    if (showPartOf) {
      for (final p in parts) {
        final b0 = _back.length, t0 = _top.length;
        _planPart(c, p);
        _own(p.host, p.member, b0);
        if (_auditing) _audited(LineAuditKind.part, p.host, p.member, b0, t0);
      }
    }
    if (successionMode == 2) return; // 메뉴 '숨기기' — 네모는 그대로 두고 선만 없앤다(명세 3-1)
    // 켠 대범위(구역 23이 실려 온 것)의 본국: 그 본국에서 나가는 '묶임' 승계는 낱낱의 부흥선 대신 한 줄로 묶는다(명세 6-5).
    final scopes = ScopeLayer.readScopes(c);
    final byHost = <int, ScopeIn>{};
    for (final s in scopes.values) {
      if (s.host != 0 && s.afterHost) byHost[s.host] = s;
    }
    // 세로 통로가 안쪽인 것부터 — 지금 연표의 edges 정렬(선대 uid → |Δ줄|)을 내보내기가 통로 번호로 실어 보냈다.
    links.sort((a, b) => a.channel.compareTo(b.channel));
    if (PaintPick.route) {
      _recount(c, links, byHost);
      _claimGaps(c, links);
    }
    final bundledHosts = <int>{};
    for (final l in links) {
      if (successionMode == 1 && l.kind != 0) continue; // '직접 승계만'은 대범위 부흥선도 숨긴다(명세 4-5)
      if (l.bundled && byHost.containsKey(l.from)) {
        bundledHosts.add(l.from);
        continue;
      }
      final b0 = _back.length, t0 = _top.length;
      _shareSpans.clear();
      _planLink(c, l);
      _claims.remove(l);
      _own(l.from, l.to, b0);
      if (_auditing) _auditLink(c, l, b0, t0);
    }
    if (successionMode != 1) {
      for (final host in bundledHosts) {
        final b0 = _back.length, t0 = _top.length;
        _planBundle(c, byHost[host]!, host);
        _own(host, 0, b0);
        if (_auditing) _audited(LineAuditKind.succession, host, 0, b0, t0);
      }
    }
  }

  /// 세로 통로 번호 다시 세기(명세 04 8-1 · 3-6 · 스위치 route · 조사 결함 6): 구역 21의 통로 번호(`c` = k × 10)는 '모두 켠 상태'의 기준값이라,
  /// 이 장면에 걸러진 쌍(메뉴 '직접 승계만' · 대범위 부흥선 묶음 · 접힌 줄 · 이 단계에 실리지 않은 선)도 번호를 차지해 통로가 쓸데없이 바깥으로 밀렸다
  /// (고구려 여섯 가닥). 살아남은 다른 줄 쌍만 선대마다 통로 번호 차례로 0부터 다시 세고, 아래로 가는 선과 위로 가는 선은 따로 센다 —
  /// 두 쪽의 세로 획은 선대 줄에서 반대로 나가므로 한 번호를 함께 쓸 까닭이 없다. 같은 줄 쌍은 번호가 없다(−1).
  void _recount(PaintContext c, List<_LinkIn> links, Map<int, ScopeIn> byHost) {
    final layout = c.layout;
    final next = <int, int>{}; // 선대 띠 × 2 + 쪽 → 다음 번호
    for (final l in links) {
      l.lane = -1;
      if (l.row == l.row2) continue;
      if (successionMode == 1 && l.kind != 0) continue;
      if (l.bundled && byHost.containsKey(l.from)) continue;
      final (qRow, pRow, down) = _endsOf(c, l);
      if (qRow >= layout.rowCount || pRow >= layout.rowCount || !layout.hasBody(qRow) || !layout.hasBody(pRow)) continue;
      final key = l.from * 2 + (down ? 1 : 0);
      final k = next[key] ?? 0;
      l.lane = k;
      next[key] = k + 1;
      if (k + 1 > (_chanCount[l.from] ?? 0)) _chanCount[l.from] = k + 1;
    }
  }

  /// 대범위 부흥선 — 한 줄로 묶기(명세 6-5절). 본국의 멸망 네모에서 테두리의 왼쪽 변(또는 위 변)으로 간다.
  void _planBundle(PaintContext c, ScopeIn s, int host) {
    final box = scopeBoxOf(c, s);
    if (box == null) return;
    final sq = _squares[host];
    if (sq == null) return;
    final v = c.v, left = c.left, right = c.w;
    final xl = v.xOf(s.start) - ScopeLook.padX;
    final x1 = _bird ? (sq.unknownEnd ? sq.xEnd : sq.bandEnd - BirdLook.stub) : sq.ec + LinkLook.tipGap;
    final y1 = sq.y;
    final y2 = v.yOf(box.top) + c.layout.metrics.scopeHead / 2;
    final x2 = math.max(xl, left - 20);
    final xm = sq.bandEnd + (sq.unknownEnd ? LinkLook.fade : 0) + 9;
    if (math.max(x1, x2) < left - 20 || math.min(x1, xm) > right + 20) return;
    final color = LinkLook.inkOf(sq.color);
    final alpha = LinkLook.backAlpha * linkAlpha(host, 0);
    final side = x2 >= xm + 6;
    final pts = side
        ? [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, y2), ui.Offset(x2, y2)]
        : [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, v.yOf(box.top))];
    _back.add(_Back.link(pts, 6, color, alpha, LinkLook.beat, LinkLook.width));
    _back.add(_Back.bundleRing(pts.last.dx, pts.last.dy, color));
    _hits.add(_HitArea.line(LinkHitKind.link, host, 0, pts));
    // 본국의 멸망 네모에서 오른쪽 테두리까지는 보통 승계선처럼 관문을 둔다(명세 6-5 끝).
    final he = sq.bandEnd;
    if ((_bird ? _birdEnd(c, sq, he) : sq.showE) && !sq.unknownEnd && x1 < he && x1 >= he - LinkLook.gateMax) {
      final edge = LinkLook.inkOf(sq.color);
      final lo = he - 1 - .5, hi = he + .5;
      _top.add(_Top.door(lo, y1 - _doorH / 2, hi, y1 + _doorH / 2, 1));
      for (final run in beatRuns(x1, he + .5, LinkLook.beat)) {
        _top.add(_Top.seg(run.$1, y1, run.$2, y1, edge, LinkLook.width, 1));
      }
    }
    c.debug?.note('부흥선', '${s.name} ${_n(x1)},${_n(y1)} → ${_n(pts.last.dx)},${_n(pts.last.dy)}');
  }

  /// 승계선(구역 21)은 여러 타일에 잘려 오므로 조각을 이어 붙여 제 두 끝을 되찾는다(네모의 `_readSquares`처럼).
  /// 첫 조각만 읽던 때는 선대 줄이 화면 밖이라 네모가 실리지 않으면 선의 끝을 타일 경계에서 읽어, 합류 선이 엉뚱한 해에서 내려왔다(월흔해 은륜 제국 → 새빛 공동국이 960년이 아니라 949년에서).
  void _readLinks(Tile t, Map<int, _LinkIn> byId) {
    final s = t.section(secLink);
    if (s.count == 0) return;
    final id = s.u(Tile.itemId);
    final origin = t.origin.toDouble();
    for (int i = 0; i < s.count; i++) {
      final l = _LinkIn.read(s, i, origin);
      final had = byId[id[i]];
      if (had == null) {
        byId[id[i]] = l;
      } else {
        if (l.start < had.start) had.start = l.start;
        if (l.end > had.end) had.end = l.end;
      }
    }
  }

  /// 소속선(구역 22)도 여러 타일에 잘려 오므로 조각을 이어 붙인다(조사 결함 29 — 첫 조각만 읽던 때는 왼쪽 타일 경계에서 잘린 자리를 소속 시작으로 알아
  /// 화면 왼끝 가까이에 가짜 선이 생겼다 사라졌다). 잘리지 않은 왼쪽 조각이 있으면 그 시작이 제 시작이고, 없으면 시작을 모른다([_PartIn.clipped]).
  void _readParts(Tile t, Map<int, _PartIn> byId) {
    final s = t.section(secPart);
    if (s.count == 0) return;
    final id = s.u(Tile.itemId), flags = s.u(Tile.itemFlags), x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
    final origin = t.origin.toDouble();
    for (int i = 0; i < s.count; i++) {
      final had = byId[id[i]];
      if (had == null) {
        byId[id[i]] = _PartIn.read(s, i, origin);
        continue;
      }
      final lo = origin + x0[i], hi = origin + x1[i];
      if (flags[i] & Tile.clipLeft == 0) {
        had.start = lo;
        had.clipped = false;
      } else if (had.clipped && lo < had.start) {
        had.start = lo;
      }
      if (hi > had.end) had.end = hi;
    }
  }

  /// 옮겨 앉기의 실(리메이크 2부 · 결정 #3 A · 목업 d3-a `mv`): 앞 토막의 아랫변(뒤 토막이 위 줄이면 윗변)에 매듭(지름 4 · 먹 50)을 두고,
  /// 뒤 토막 왼쪽 6 앞에서 곧게 내려(올라)가 뒤 토막 구멍 높이에서 반지름 6으로 꺾어 구멍으로 든다 — 띠 뒤는 점선 3 2 · 1.5px · 먹 50,
  /// 뒤 토막 왼쪽 끝에서 구멍 테까지는 띠 위 실선. 두 토막이 다 그려질 때만 긋는다(한쪽만 보이면 없음 · 조감 없음).
  /// 스위치 route(조사 결함 28 · 34): 매듭은 앞 토막의 바닥([_floorOf] — 짧은 꼬리표의 몸통 아랫변 · 꼬리표 밑 흰 사슬 단 밑)에 선다.
  /// 앞 토막 네모가 실리지 않았어도 구역 52 앞 끝 항목의 줄로 매듭 높이를 센다(뒤 토막 네모만 있으면 된다). 옮긴 해가 화면 왼쪽 밖이면(뒤 토막의
  /// 왼쪽 끝 · 구멍이 화면 밖) 화면 왼끝 + 6에 붙여 곧게 뒤 토막으로 든다 — 꺾어 구멍으로 드는 몫 · 띠 위 실선 없이. 사이 줄 띠는 굴 문(3-9)의 몫.
  void _planMoves(PaintContext c) {
    if (_bird) return;
    final ends = <String, List<(int, int, int)>>{};
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      _readItems(t, secMove, seen, (i, s, origin) {
        final key = t.text(s.u(Tile.itemText2)[i]);
        if (key.isNotEmpty) (ends[key] ??= []).add((s.u(Tile.itemRef)[i], s.u(Tile.itemA)[i], s.u(Tile.itemRow)[i]));
      });
    }
    if (ends.isEmpty) return;
    final layout = c.layout, v = c.v;
    final route = PaintPick.route;
    for (final e in ends.values) {
      final b0 = _back.length, t0 = _top.length;
      int front = 0, back = 0, frontRow = -1;
      for (final (band, a, row) in e) {
        if (a == 0) {
          front = band;
          frontRow = row;
        } else {
          back = band;
        }
      }
      final f = _squares[front], b = _squares[back];
      if (b == null || (f == null && !route)) continue;
      final fRow = f?.row ?? frontRow;
      if (fRow < 0 || fRow >= layout.rowCount || fRow == b.row || !layout.hasBody(fRow)) continue;
      final geo = layout.geo(fRow);
      final fTop = v.yOf(layout.rowTop(fRow) + geo.bandTop).roundToDouble();
      final fBottom = (route ? _floorOf(c, fRow, front) : v.yOf(layout.rowTop(fRow) + geo.bandTop + geo.bandHeight)).roundToDouble();
      final below = b.y > (f?.y ?? _anchorY(c, fRow));
      final knotY = below ? fBottom - .5 : fTop + .5;
      final left = b.x1;
      final x = (left - MoveLook.lead).floorToDouble() + .5;
      if (route && x < c.left) {
        final xp = (c.left + MoveLook.lead).floorToDouble() + .5;
        if (b.bandEnd < xp + MoveLook.lead || (below ? b.y - knotY : knotY - b.y) < MoveLook.radius) continue;
        final pts = [ui.Offset(xp, knotY), ui.Offset(xp, b.y)];
        _back.add(_Back.link(pts, MoveLook.radius, MoveLook.ink, 1, const [MoveLook.dash, MoveLook.gap], MoveLook.width));
        _top.add(_Top.knot(xp, knotY, MoveLook.ink));
        _hits.add(_HitArea.line(LinkHitKind.link, front, back, pts));
        c.debug?.note('옮겨앉기', '${_n(xp)},${_n(knotY)} → ${_n(xp)},${_n(b.y)} 붙임');
        _own(front, back, b0);
        if (_auditing) _audited(LineAuditKind.move, front, back, b0, t0);
        continue;
      }
      if (!b.showF || x < c.left || (below ? b.y - knotY : knotY - b.y) < MoveLook.radius) continue;
      final pts = [ui.Offset(x, knotY), ui.Offset(x, b.y), ui.Offset(left, b.y)];
      _back.add(_Back.link(pts, MoveLook.radius, MoveLook.ink, 1, const [MoveLook.dash, MoveLook.gap], MoveLook.width));
      final hole = b.fc - TagLook.holeR - .5;
      if (hole > left) _top.add(_Top.seg(left, b.y, hole, b.y, MoveLook.ink & 0xffffff, MoveLook.width, 1 / LinkLook.topAlpha));
      _top.add(_Top.knot(x, knotY, MoveLook.ink));
      _hits.add(_HitArea.line(LinkHitKind.link, front, back, pts));
      c.debug?.note('옮겨앉기', '${_n(x)},${_n(knotY)} → ${_n(left)},${_n(b.y)}');
      _own(front, back, b0);
      if (_auditing) _audited(LineAuditKind.move, front, back, b0, t0);
    }
  }

  void _readItems(Tile t, int section, Set<int> seen, void Function(int i, TileSection s, double origin) read) {
    final s = t.section(section);
    if (s.count == 0) return;
    final id = s.u(Tile.itemId);
    final origin = t.origin.toDouble();
    for (int i = 0; i < s.count; i++) {
      if (!seen.add(id[i])) continue;
      read(i, s, origin);
    }
  }

  /// 줄 [row]에 놓인 띠 [band]의 '바닥'(화면 y): 몸통 아랫변([BandLayer.bodyBottomOf] — 사건 칸을 올린 꼬리표는 줄의 띠 아랫변보다 위)과
  /// 그 줄에 꼬리표 밑 흰 사슬(왕조 · 지위 — [RowGeo.chainTop])이 있으면 사슬 단 아랫변(꼬리 내림 관문 `_tailGate`와 같은 셈) 가운데 아래 것.
  /// 띠 뒤 선의 끝 · 매듭이 이 밑에 서야 사슬 종이 뒤로 숨거나 꼬리표 아래 허공에 뜨지 않는다(조사 결함 28). 조감 · 띠 층이 없으면 줄의 띠 아랫변 + 사슬.
  double _floorOf(PaintContext c, int row, int band) {
    final layout = c.layout, geo = layout.geo(row), top = layout.rowTop(row);
    final bands = _bands;
    final chained = geo.chainTop >= 0;
    if (_bird || bands == null) return c.v.yOf(top + geo.bandTop + geo.bandHeight + (chained ? geo.chainDepth : 0));
    final body = bands.bodyBottomOf(layout, row, band);
    final chain = chained ? geo.bandTop + geo.bandHeight + geo.chainDepth - bands.eventLiftOf(layout, row, band) : body;
    return c.v.yOf(top + math.max(body, chain));
  }

  /// 소속선(명세 5-1절): 상국 띠 아래(위)로 내려오는 세로 점선 + 끝의 작은 점.
  /// 같은 소속 폴더 안의 상국 → 소속(리메이크 4단계 과제 8 걸음 3)은 긋지 않는다 — 소속은 폴더(상자) 안에 매달려 매다는 실이 대신한다
  /// (설계 4-2 '그릇에 듦 = 폴더 · 상자 안에 매달림'). 소속 폴더가 없으면(조감 · 스위치 folder 끔 · 접힌 그릇 안) 예전 그대로.
  void _planPart(PaintContext c, _PartIn it) {
    final layout = c.layout, v = c.v;
    final hostRow = it.down ? it.row : it.row2, row = it.down ? it.row2 : it.row;
    if (row >= layout.rowCount || hostRow >= layout.rowCount || !layout.hasBody(row) || !layout.hasBody(hostRow)) return;
    if (HostFolders.holdsPart(layout, it.host, hostRow, row)) return;
    final route = PaintPick.route;
    final self = _squares[it.member];
    var x = v.xOf(route ? it.start : it.first) + 12; // 둥근 모서리를 피해 띠 안쪽 12px에서 내려온다
    // 시작이 화면 왼쪽 밖이면(조사 결함 29 · 스위치 route): 구성국 띠가 보이고 소속이 화면 안까지 이어질 때 화면 왼끝 + 12에 붙여 긋는다 —
    // 띠 시작이 화면 밖이면 머리 이름이 화면 끝 + 6에 붙어 따라오는 것과 같은 말씨(그 이름 끝은 아래 탭 비킴이 비킨다). 시작을 모르면(잘린 조각뿐) 늘 붙인다.
    // 끈 길은 예전: 첫 조각의 시작(잘렸어도) · 화면 왼끝 − 4보다 왼쪽이면 없음.
    final pinned = route && (it.clipped || x < c.left - 4);
    if (pinned) {
      final pin = c.left + 12;
      if (self == null || math.min(self.bandEnd, v.xOf(it.end)) < pin + 6) return;
      x = pin;
    }
    final tabEnd = self == null ? null : _tabRight(c, self);
    if (tabEnd != null && self != null && x < tabEnd + 6 && tabEnd + 8 < self.bandEnd - 6) x = tabEnd + 8;
    if (pinned && x > math.min(self!.bandEnd, v.xOf(it.end)) - 6) return;
    if (x < c.left - 4 || x > c.w + 4) return;
    final hostGeo = layout.geo(hostRow), geo = layout.geo(row);
    final hostTop = v.yOf(layout.rowTop(hostRow) + hostGeo.bandTop);
    final myTop = v.yOf(layout.rowTop(row) + geo.bandTop);
    final double hostBottom, myBottom, hang;
    if (route) {
      // 상국 띠 아래에 매달린 이름표 줄 아래에서 내려온다 — 줄의 몫은 줄 생김새가 안다(한 줄 13 · 접었으면 0). 옛 저장소(줄 생김새에 매단 줄 수가 없음)는
      // 실린 줄 수 × 23이되 그 줄의 덧단 줄 수까지만. 덧단이 없는 줄(조감 · 접힌 단체 줄)은 0 — 조감 줄 생김새에는 매단 줄이 없는데 옛 저장소 몫(c × 23)을
      // 써서 선이 상국 밑 138px에서 떠 시작하거나 통째로 빠졌다(조사 결함 19).
      hang = _bird || hostGeo.zoneTop < 0
          ? 0
          : (hostGeo.hangLanes > 0 ? hostGeo.hangDepth : math.min(it.hangLanes, hostGeo.zoneLanes) * (G.zoneTab + G.zoneGap));
      // 끝은 그 띠의 몸통 아랫변 · 꼬리표 밑 흰 사슬 단 밑([_floorOf] — 사건 칸을 올린 짧은 꼬리표의 소속선이 꼬리표 아래 허공에서 시작하지 않게 · 조사 결함 28).
      // 매단 줄이 있으면 그 줄들(줄의 덧단 — [RowGeo.zoneTop]부터) 밑.
      hostBottom = hang > 0 ? v.yOf(layout.rowTop(hostRow) + hostGeo.zoneTop) : _floorOf(c, hostRow, it.host);
      myBottom = _floorOf(c, row, it.member);
    } else {
      // 띠 아랫변은 꼬리표 밑 흰 사슬 단까지 센다(감독 고름 G5 #9 나 — 사슬이 없거나 스위치 chain을 끄면 0). 매단 속국 줄 · 구역 탭도 그 밑이라
      // ([RowGeo.zoneTop] = 띠 아랫변 + [RowGeo.chainDepth]) 선이 사슬 종이 뒤로 지나 끊기거나 이름표 줄 사이로 드러나지 않는다(검토 2026-10-25).
      hostBottom = v.yOf(layout.rowTop(hostRow) + hostGeo.bandTop + hostGeo.bandHeight + hostGeo.chainDepth);
      myBottom = v.yOf(layout.rowTop(row) + geo.bandTop + geo.bandHeight + geo.chainDepth);
      hang = hostGeo.hangLanes > 0 ? hostGeo.hangDepth : it.hangLanes * (G.zoneTab + G.zoneGap);
    }
    final y1 = it.down ? hostBottom + 1 + hang : hostTop - 1;
    final y2 = it.down ? myTop - 2.5 : myBottom + 2.5;
    if ((it.down ? y2 - y1 : y1 - y2) < 2) return;
    // 소속선은 선 위에 올렸을 때만 색이 짙어진다(`.tl-part:hover { opacity: 1 }` — 띠 올림 · 고르기의 is-hot · is-selected는 승계선에만 붙는다). 끝의 점은 그대로.
    final l = hotLink;
    final hot = l != null && l.$1 == it.host && l.$2 == it.member ? 1.0 : 0.0;
    final alpha = _lifted(it.refuted ? LinkLook.refutedPart : LinkLook.partAlpha, hot) * linkAlpha(it.host, it.member);
    final dot = (it.refuted ? LinkLook.refutedPart : LinkLook.dotAlpha) * linkAlpha(it.host, it.member);
    _back.add(_Back.part(x, math.min(y1, y2), math.max(y1, y2), y2, LinkLook.liftedInk(it.color, hot), alpha, dot));
    _hits.add(_HitArea.line(LinkHitKind.link, it.host, it.member, [ui.Offset(x, math.min(y1, y2)), ui.Offset(x, math.max(y1, y2))]));
  }

  /// 승계선 [it]의 선대 줄 · 후대 줄 · 아래로 가는가. 그릇을 펼친 장면(스위치 route 또는 mend — 0.1.1: 선 길이 아니라 줄 고르기라 mend로도 켬 · 4단계 마지막 합치기 검토 지적): 변형은 두 끝 줄을 옮긴 뒤 row ≤ row2로
  /// 다시 고르면서 down 비트(기본 줄 차례로 셈)는 그대로 둔다 — 차례가 뒤집힌 쌍은 선대 · 후대 줄이 뒤바뀐다. 그 줄의 네모가 선대 · 후대의 진짜 줄이니 그것으로
  /// 바로잡고, 위 · 아래는 줄 번호가 아니라 화면 높이로 가른다(펼친 그릇의 줄은 번호 차례와 화면 차례가 다르다 — 그릇 밖 줄이 그릇 줄보다 번호가 커도 위에 선다).
  /// 길([_planLink]) · 통로 다시 셈([_recount] — 위 · 아래를 따로 셈) · 틈 어림([_claimGaps])이 같은 셈을 쓴다.
  (int, int, bool) _endsOf(PaintContext c, _LinkIn it) {
    final layout = c.layout;
    var qRow = it.down ? it.row : it.row2, pRow = it.down ? it.row2 : it.row;
    var goesDown = it.down;
    if ((PaintPick.route || PaintPick.mend) && qRow != pRow) {
      final q = _squares[it.from], p = _squares[it.to];
      if ((q != null && q.row == pRow) || (p != null && p.row == qRow)) (qRow, pRow) = (pRow, qRow);
      if (layout.rowTop(qRow) >= 0 && layout.rowTop(pRow) >= 0) goesDown = layout.rowTop(qRow) < layout.rowTop(pRow);
    }
    return (qRow, pRow, goesDown);
  }

  /// 승계선 한 건(명세 3절). 길은 `hv` → 당김 → 내림줄 → 오름줄 → 되돌아감 차례로 고른다.
  void _planLink(PaintContext c, _LinkIn it) {
    final layout = c.layout;
    final q = _squares[it.from], p = _squares[it.to];
    final (qRow, pRow, goesDown) = _endsOf(c, it);
    if (qRow >= layout.rowCount || pRow >= layout.rowCount || !layout.hasBody(qRow) || !layout.hasBody(pRow)) return;
    final v = c.v, left = c.left, right = c.w;
    // 띠의 몸통 아랫변(명세 04 3-5 · 3-6 · 스위치 route · 조사 결함 10): 사건 칸을 올린 꼬리표 · 판 3 저장소의 키 작은 띠는 줄의 띠 아랫변보다 위다 —
    // 합류 조각 · 관문의 문이 허공에 뜨지 않게 그 띠의 몸통 아랫변([BandLayer.bodyBottomOf])에 둔다. 조감 · 끔 · 모르는 띠는 줄의 띠 아랫변.
    double bottomOf(int row, _Square? sq) {
      final geo = layout.geo(row);
      final bands = _bands;
      return v.yOf(layout.rowTop(row) + (sq == null || bands == null || _bird || !PaintPick.route ? geo.bandTop + geo.bandHeight : bands.bodyBottomOf(layout, row, sq.band)));
    }
    // 띠의 네모가 이 장면에 실리지 않았으면(줄이 화면 밖으로 멀리 나감) 선 항목의 두 끝에서 어림한다.
    final qe = q?.bandEnd ?? v.xOf(it.qFirst ? it.start : it.end);
    final pf = p?.bandStart ?? v.xOf(it.qFirst ? it.end : it.start);
    final y1 = q?.y ?? _anchorY(c, qRow), y2 = p?.y ?? _anchorY(c, pRow);
    // 조감: 네모가 없어 선이 띠 끝 안쪽 STUB(3px)에 닿는다. 미정인 끝은 사라지는 꼬리라 제 끝 해에서.
    final double x1, x2;
    if (_bird) {
      x1 = it.unknownQ ? (q?.xEnd ?? qe) : qe - BirdLook.stub;
      x2 = it.unknownP ? (p?.xStart ?? pf) : pf + BirdLook.stub;
    } else {
      // 꼬리표 갈래 E: 선은 꼬리 마름모의 가운데에서 나와(마름모가 위에 덮여 흰 틈이 없다) 구멍의 왼쪽 테에서 멎는다.
      x1 = q?.ec ?? qe - TagLook.diamondX;
      x2 = (p?.fc ?? pf + TagLook.holeX) - TagLook.holeR;
    }
    if (math.max(x1, x2) < left - 20 || math.min(x1, x2) > right + 20) return;
    final qEnd = qe + (it.unknownQ ? LinkLook.fade : 0);
    final pl = pf - (it.unknownP ? LinkLook.fade : 0);
    final bool okQ, okP;
    if (_bird) {
      okQ = !it.unknownQ && _birdEnd(c, q, qe);
      okP = !it.unknownP && _birdEnd(c, p, pf);
    } else {
      okQ = (q?.showE ?? true) && !it.unknownQ && x1 <= qe - 1.5;
      okP = (p?.showF ?? true) && !it.unknownP && x2 >= pf + 1.5;
    }
    final gq = okQ && (_bird || x1 >= qe - LinkLook.gateMax);
    final gp = okP && (_bird || x2 <= pf + LinkLook.gateMax);
    final dim = linkAlpha(it.from, it.to), lift = _lift(it.from, it.to, c);
    // 선 · 띠 위 조각 · 고리가 한 색(띠 테 빛깔) — 짙게일 때는 꼬리 마름모 빛깔로 흐른다(LinkLook.liftedInk).
    final qColor = LinkLook.liftedInk(it.color, lift), qEdge = qColor, pEdge = p == null ? qEdge : LinkLook.liftedInk(p.color, lift);
    final lineAlpha = _lifted(it.refuted ? LinkLook.refutedLine : (it.thin ? LinkLook.partialAlpha : LinkLook.backAlpha), lift) * dim;
    void gateOut() {
      if (gq) _gate(c, x1, qe + .5, y1, false, qe - 1, qe, it, qEdge, dim);
    }

    void gateIn() {
      if (gp) _gate(c, x2, pf - .5, y2, false, pf, pf + 1, it, pEdge, dim);
    }

    final rx = pl - (gp ? 4.75 : 3.75);
    var ring = it.kind == _LinkIn.revival && pl > left - 10 && pl < right + 10;
    List<ui.Offset> pts;
    ui.Offset? dot; // 합류 점(조사 결함 43) — 선을 그은 뒤 그 위에
    var rad = 6.0;
    // 선대 끝이 화면 오른쪽 밖(감독 고름 2026-10-26 ① '후대 쪽만이라도 그림'): 이미 있던 나라로 드는 선(합류 — 뒤로 가는 승계선)은 '앞 나라 끝에서'
    // 그해의 후대 테두리로 내려가므로, 선대 끝이 화면 오른쪽 밖이면 길 전체가 화면 밖이라 아무것도 긋지 않았다(아래 합류 갈래의 `x1 > right + 20` —
    // 감독 자료 기원전 208 ~ 327: 북부여 둘째 줄 → 고구려 · 백제, 동예 → 고구려, 부여 → 고구려). 그때는 후대 구멍 앞에 짧은 들어오는 선(띠 시작 앞 9에서)과
    // 관문을 두고, 후대 띠 시작에 짝 꼬리표 `← ●앞 나라`(자리 사다리 · 글 · 누르면 앞 나라 끝으로 — [_planCross])를 놓는다(기본 · route 같음).
    // 선대 끝이 화면 안으로 들어오면 지금 길 그대로. 화면 밖에서 되돌아와 후대 구멍으로 드는 다른 승계선은 이미 후대 쪽이 보이므로 그대로다.
    // 조감(구멍 없음) · 짝 꼬리표를 끈 보기(스위치 pair)는 지금 길.
    if (!_bird && it.absorb && PaintPick.pair && q != null && p != null && okP && x1 > right + 20 && pf >= left && pf < qe) {
      final stub = [ui.Offset(pl - LinkLook.lateIn, y2), ui.Offset(x2, y2)];
      final had = _lateIns[p.band];
      final end = had ?? (_lateIns[p.band] = _CrossEnd(p.band, p.row, true, late: true));
      if (had == null) {
        _back.add(_Back.link(stub, rad, qColor, lineAlpha, it.beat, it.thin ? _thinW : LinkLook.width));
        gateIn();
      }
      end.partners.add(_CrossPartner(it.from, it.from, '', q.name, it.color, it.kind));
      _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, stub));
      c.debug?.note('후대쪽', '${it.from}→${it.to} ${_n(stub.first.dx)},${_n(y2)} ${_n(stub.last.dx)},${_n(y2)}${had == null ? '' : ' 함께'}');
      return;
    }
    if (qRow == pRow) {
      if (it.seam && gq && gp) {
        // 곧바로 이음 — 선 전체가 띠 위 층이라 맞닿아도 틈이 벌어져도 같은 모양이 이어진다(띠 뒤 선은 없다).
        _bridge(c, qe, pf, x1, x2, y1, it, qEdge, pEdge, dim);
        _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, [ui.Offset(x1, y1), ui.Offset(x2, y1)]));
        return;
      }
      // 이음매 눈금(명세 04 3-4 · 스위치 route): 좁은 띠라 마름모 · 구멍이 꺼져 다리를 못 세우면 이음매 문 하나와 양쪽 띠 위 토막으로 — 끊긴 것처럼 보이지 않게.
      if (it.seam && PaintPick.route && (!okQ || !okP) && _seamTick(c, q, p, qe, pf, y1, it, qEdge, pEdge, dim)) return;
      if (x2 - x1 < 2) return;
      // 같은 줄 ⊓(명세 04 3-4 · 스위치 route · 조사 결함 2 · 3): 이음매가 아닌 쌍 사이에 다른 띠가 있으면 곧은 선은 그 띠 뒤로 숨어
      // '사이 띠 → 후대'로 읽힌다 — 꼬리 마름모에서 이름 색줄 위로 나가 줄 위 틈을 건너 후대의 구멍으로 위에서 든다(두 끝은 오름줄 관문 꼴).
      final cap = !it.seam && PaintPick.route && q != null && p != null && okQ && okP ? _capAt(c, qRow, q, p, x1, x2) : null;
      if (cap != null) {
        final (xa, xb, gy0) = cap;
        final top = v.yOf(layout.rowTop(qRow) + layout.geo(qRow).bandTop);
        final yS = _bird ? top + 1 + BirdLook.stub : y1 - LinkLook.tipGap, yE = _bird ? top + 1 + BirdLook.stub : y2 - LinkLook.tipGap;
        // 골목 층 표(조사 결함 5): 같은 틈에 앞서 놓인 가로와 겹치면 2.5px 위 · 아래 층으로(다 차면 그대로).
        final gy = _laneAt(c, qRow, gy0, xa, xb) ?? gy0;
        pts = [ui.Offset(xa, yS), ui.Offset(xa, gy), ui.Offset(xb, gy), ui.Offset(xb, yE)];
        _upGate(c, q!, yS, top, xa, it, qEdge, dim);
        _dropZone(c, qRow, true, xa);
        // 합류 점(조사 결함 43): 같은 구멍에 위에서 먼저 든 선이 있으면 그 세로에 닿는 곳에서 멎는다(관문은 첫 선의 것).
        final merged = _mergeTop(p!.band, pts);
        if (merged != null) {
          pts = merged;
          dot = pts.last;
          ring = false;
        } else {
          _upGate(c, p, yE, top, xb, it, pEdge, dim);
          _dropZone(c, pRow, true, xb);
        }
        // 부흥 고리는 위 틈의 가로 획 위 — 후대 쪽 굽이 앞(틈이 고리를 담을 만할 때만).
        final gx = xb - 6 - LinkLook.ringR - 1.5;
        ring = ring && gx - LinkLook.ringR >= xa + 6 + 1.5 && layout.geo(qRow).bandTop - _tabOf(c, qRow) >= 2 * LinkLook.ringR + 1;
        if (ring) {
          ring = false;
          _back.add(_Back.ring(gx, gy, qColor, lineAlpha));
        }
        c.debug?.note('같은줄위', '${it.from}→${it.to} ${_n(xa)},${_n(gy)},${_n(xb)}');
      } else {
        pts = [ui.Offset(x1, y1), ui.Offset(x2, y1)];
        if (ring) ring = rx - LinkLook.ringR >= qEnd + 3;
        // 합류 점(조사 결함 43): 같은 구멍에 옆으로 먼저 든 선이 있으면 그 가로와 겹치기 시작하는 곳에서 멎는다.
        final merged = PaintPick.route && p != null ? _mergeSide(p.band, pts) : null;
        if (merged != null) {
          pts = merged;
          dot = pts.last;
          ring = false;
        }
        // 네모 하나가 생략된 먼 보기에서는 관문도 두지 않는다(반쪽 다리가 되지 않게).
        if (!it.seam && (gq == gp || pl - qEnd >= 1)) {
          gateOut();
          if (merged == null) gateIn();
        }
      }
    } else {
      final route = PaintPick.route;
      // 통로 번호: 스위치 route면 이 장면에서 걸러진 뒤 쪽(위 · 아래)마다 다시 센 번호([_recount] · 조사 결함 6), 아니면 구역 21의 기준값.
      final k = route && it.lane >= 0 ? it.lane.toDouble() : it.channel / 10;
      var xm = qEnd + 9 + k * 5; // 세로 통로는 선대 띠(꼬리 포함) 바깥에
      // 세로 기둥 표(조사 결함 6): 다른 선대가 이미 세운 세로 획과 2.5px 안이면 3px씩 비킨다(길의 꼴이 바뀌거나 선대 줄의 다음 띠 밑이 되면 그대로).
      if (route) xm = _dodgeColumn(qRow, it.from, xm, x2, math.min(y1, y2), math.max(y1, y2));
      final dir = goesDown ? 1 : -1;
      final qGeo = layout.geo(qRow), pGeo = layout.geo(pRow);
      final qBottom = bottomOf(qRow, q);
      final qTop = v.yOf(layout.rowTop(qRow) + qGeo.bandTop);
      final pBottom = bottomOf(pRow, p);
      final pTop = v.yOf(layout.rowTop(pRow) + pGeo.bandTop);
      final tabQ = q == null ? null : _tabRight(c, q);
      final tabP = p == null ? null : _tabRight(c, p);
      // 사이 줄 비킴(명세 04 3-6 · 3-7 · 스위치 route · 검증 지적): 띠 안에서 곧게 나가는 세로 획(내림줄 · 오름줄 · 합류 내림줄 · 꼬리 내림)이
      // 사이 줄의 띠를 지나는데 띠 밖 통로(되돌아가는 길의 첫 세로 획 [chan])는 비었으면 그 획을 고르지 않는다 — 띠 뒤로 숨어 굴 문으로만
      // 보이는 곧은 획보다 다 보이는 S자가 낫다. 통로도 막혔으면 그대로(더 나빠지지 않는다).
      final chan = xm;
      bool? chanClear;
      bool midOK(double x) => !PaintPick.route || _midClear(c, qRow, pRow, dir, x) || !(chanClear ??= _midClear(c, qRow, pRow, dir, chan));
      // (가-0) 앞 나라 끝 지키기(명세 04 3-6 · 스위치 route): 통로 자리에 같은 줄의 다음 띠가 맞붙어 있으면 앞 나라 끝의 틈 · 꼬리 마름모 밑으로.
      final tailX = _bird ? qe - BirdLook.stationX : (q?.ec ?? (qe - LinkLook.inset));
      // 꼬리 내림의 자격은 줄기가 실제로 설 x에서 본다(이어 주는 선 미룸 4): 줄기는 첫 선이 세우므로 같은 줄기를 함께 쓰는 위로 가는 선의 탭 검사를
      // 꼬리 x(tailX)로 어림하면, 둘째 줄기(tailX − 3)나 아래로 가는 선이 먼저 세운 줄기가 탭 밑을 지나도 몰랐다.
      final exit = route && q != null
          ? _exitAt(q, it.kind, qEnd, xm, tailX, (x) => okQ && _birdClear(qRow, x) && (dir > 0 || _overTop(c, q, x) < 2))
          : null;
      var tail = exit?.$2 ?? false;
      final yS = _bird ? (dir > 0 ? qBottom - 1 - BirdLook.stub : qTop + 1 + BirdLook.stub) : y1 + dir * LinkLook.tipGap;
      // 합류(흡수): 이미 있던 나라로 들어가는 선은 후대의 건국 네모가 아니라 그해의 테두리에 곧게 닿는다.
      if (it.absorb) {
        if (qEnd < left - 50 || x1 > right + 20) return;
        const jw = LinkLook.width + 3; // 합류 조각은 승계 종류와 상관없이 같은 크기(js joinPiece)
        final yJ = dir > 0 ? pTop : pBottom;
        final pe = p?.bandEnd ?? (pf + 1);
        final tabEnd = dir > 0 ? tabP : null;
        bool landOK(double x) =>
            x - jw / 2 >= pf + LinkLook.radius && x + jw / 2 <= pe - LinkLook.radius && (tabEnd == null || x - jw / 2 >= tabEnd + 3) && x > left - 10 && x < right + 10;
        double? xj;
        var drop = false, stem = false;
        final xd = _bird ? qe - BirdLook.stationX : (q?.ec ?? (qe - LinkLook.inset));
        if (exit != null && (!tail || gq) && landOK(exit.$1)) {
          xj = exit.$1; // (가-0) — 합류 내림줄 · 통로도 앞 나라 끝에서
          drop = tail;
          stem = true;
        } else if (gq && landOK(xd) && _dropOK(c, qRow, dir, xd, tabQ, it.from, q?.bandStart ?? double.negativeInfinity, q?.bandEnd ?? qe) && _birdClear(qRow, xd) && midOK(xd)) {
          xj = xd;
          drop = true;
        } else {
          // 합류 통로: 띠 밖 세로 통로에서 곧게 — 후대의 책갈피 탭 위면 탭 너머로(js의 `[xm, tabEnd + 3 + jw / 2]`).
          for (final xv in [xm, if (tabEnd != null) math.max(xm, tabEnd + 3 + jw / 2)]) {
            if (landOK(xv) && _clearAt(qRow, (qe + xv) / 2, it.from, (xv - qe) / 2)) {
              xj = xv;
              break;
            }
          }
        }
        if (xj != null) {
          if (drop) {
            final edgeY = dir > 0 ? qBottom : qTop;
            pts = [ui.Offset(xj, yS), ui.Offset(xj, yJ)];
            if (stem) {
              _tailGate(c, qRow, q!, it.kind, dir, xj, yS, it, qEdge, dim);
            } else if (dir < 0 && q != null) {
              _upGate(c, q, yS, edgeY, xj, it, qEdge, dim);
            } else {
              _gate(c, yS, edgeY + dir * .5, xj, true, edgeY - dir, edgeY, it, qEdge, dim);
            }
            _dropZone(c, qRow, dir < 0, xj);
          } else {
            pts = [ui.Offset(x1, y1), ui.Offset(xj, y1), ui.Offset(xj, yJ)];
            gateOut();
          }
          _top.add(_Top.join(xj - jw / 2, dir > 0 ? yJ : yJ - LinkLook.joinH, jw, LinkLook.joinH, qEdge, dim * _topK(1, lift)));
          _back.add(_Back.link(pts, 6, qColor, lineAlpha, it.beat, it.thin ? _thinW : LinkLook.width));
          _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, pts));
          final gy = yJ - dir * (0.5 + 3.6);
          if (it.kind == _LinkIn.revival && (dir > 0 ? gy - 3.6 >= qBottom + 1 : gy + 3.6 <= qTop - 1)) {
            _back.add(_Back.ring(xj, gy, qColor, lineAlpha));
          }
          return;
        }
      }
      if (exit != null) xm = exit.$1; // (가-0)이 고친 통로가 그 뒤 길 고르기의 기준 — 꼬리 내림이면 길은 drop 꼴(넉넉지 않으면 되돌아감)
      // 조감의 내림줄 · 오름줄은 띠 안 이름 · 단추를 비켜야 한다(명세 7-2의 `birdClear` — 지금 연표의 `tr._bnmZ` · js:7654 · 7657).
      var mode = x2 >= xm + 6 ? (tail ? _Mode.drop : _Mode.hv) : _Mode.back;
      if (mode == _Mode.back && !tail) {
        final slid = math.min(xm, pf - 6); // ① 통로를 후대 앞까지 당긴다
        final drop = _bird ? qe - BirdLook.stationX : (q?.ec ?? (qe - LinkLook.inset)); // ② 멸망 네모 밑(위)에서 곧게 나오는 내림줄
        final rise = _bird ? pf + BirdLook.stationX : (p?.fc ?? (pf + LinkLook.inset)); // ③ 거꾸로 건국 네모로 드는 오름줄
        if (slid >= qEnd + 4 && _clearAt(qRow, slid, it.from) && _clearAt(pRow, slid, it.to)) {
          xm = slid;
          mode = _Mode.hv;
        } else if (okQ && okP && pf - 6 >= drop && _dropOK(c, qRow, dir, drop, tabQ, it.from, q?.bandStart ?? double.negativeInfinity, q?.bandEnd ?? qe) && _birdClear(qRow, drop) && _clearAt(pRow, drop, it.to) && midOK(drop)) {
          xm = drop;
          mode = _Mode.drop;
          // 조감 내림줄 비킴(조사 결함 13): 같은 선대의 둘째 내림줄은 세로 기둥 표로 3px 안쪽에(청림 신관국 → 청림 대공국 · 은가지 자치령이 한 x에 포개짐).
          if (route && _bird && q != null) xm = _innerDrop(qRow, pRow, q, it.to, xm, math.min(yS, y2), math.max(yS, y2));
        } else if (okQ && (_bird ? (okP && _birdClear(pRow, rise)) : (p?.showF ?? true)) && !it.unknownP && rise >= qe + 6 && rise >= x1 + 8 && _dropOK(c, pRow, -dir, rise, tabP, it.to, p?.bandStart ?? pf, p?.bandEnd ?? double.infinity) && _clearAt(qRow, (qe + rise) / 2, it.from, (rise - qe) / 2) && midOK(rise)) {
          xm = rise;
          mode = _Mode.rise;
        }
      }
      // (가-0) 꼬리 내림으로(명세 04 3-6 (나) 끝 · 스위치 route · 조사 결함 12 · 44): 당김 · 내림줄 · 오름줄이 다 막혀 되돌아가는 길(S자 6점)만 남으면
      // 띠 밖 통로로 나갔다 되돌아오지 않고 꼬리 마름모 밑(위)에서 곧게 — 후대 줄의 그 구간이 비었으면 drop 꼴, 아니면 되돌아감(첫 두 점 없이).
      // (가-0)의 줄기 표([_stems])에는 적지 않는다(같은 선대의 흠 없는 선은 길이 그대로). 줄기의 x는 꼬리 줄기 표([_tails])에서 — 같은 선대 · 같은 종류는
      // 같은 x(관문 한 번)이고, 처음 잡으면 줄기 수를 올려 다른 종류의 줄기가 3px씩 왼쪽에 선다(검증 지적 — 예전에는 수를 올리지 않아 겹치거나 관문 없이 어긋났다).
      // 사이 줄의 띠가 그 x를 막고 띠 밖 통로는 비었으면 꼬리 내림 대신 되돌아감(drop 꼴이 빈 기둥으로 옮겨 갈 수 있으면 꼬리 내림 — midOK · [_jogAt]).
      // 위로 가는 선은 그 자리에 탭이 설 수 있으면 하지 않는다([_overTop] 2).
      var fell = false;
      if (mode == _Mode.back && !tail && exit == null && PaintPick.route && q != null && okQ && _birdClear(qRow, tailX)) {
        final xf = _tailAt(q, it.kind, tailX);
        final down = x2 >= xf + 6 && _clearAt(pRow, (xf + pf) / 2, it.to, (pf - xf) / 2);
        if ((dir > 0 || _overTop(c, q, xf) < 2) && (midOK(xf) || (down && _jogAt(c, qRow, pRow, dir, xf, x2, take: false) != null))) {
          _takeTail(q, it.kind, xf);
          xm = xf;
          tail = fell = true;
          if (down) mode = _Mode.drop;
        }
      }
      // (가-0) 사이 줄의 띠가 통로를 막으면 선대 줄 밑(위) 틈에서 40px 안의 빈 기둥으로 옮긴다(없으면 그대로 — 굴 문의 몫).
      final jog = (exit != null || fell) && (mode == _Mode.hv || mode == _Mode.drop) ? _jogAt(c, qRow, pRow, dir, xm, x2) : null;
      var xv = jog?.$1 ?? xm; // 후대 줄로 내려(올라)가는 세로 획의 자리
      // hv 빈 기둥(명세 04 3-6 (나) · 스위치 route · 조사 결함 4 · 42 (가)): 띠 밖 통로를 사이 줄의 띠가 막으면 막은 띠 오른끝 + 4 차례로 빈 기둥을 찾아
      // 통로째 옮긴다(8번까지 — 선대 줄의 [선대 끝, 기둥]이 비고 후대가 기둥 오른쪽 6px 밖일 때만). 없으면 그대로(지나는 띠는 굴 문 3-9).
      if (route && mode == _Mode.hv && exit == null && !fell && jog == null && !_midClear(c, qRow, pRow, dir, xm)) {
        final col = _openColumn(c, qRow, pRow, xm, x2, qEnd, it.from, math.min(y1, y2), math.max(y1, y2));
        if (col != null) xm = xv = col;
      }
      var entered = false; // 후대 구멍에 위에서 들었는가(관문을 이미 둠 — 가로 관문 gateIn 없음)
      // 후대 줄의 틈으로 들기(명세 04 3-6 (나) · 스위치 route · 조사 결함 4 · 8 · 42 (나) · 43): hv · drop 꼴의 마지막 가로는 후대의 구멍 높이로 후대 줄을 지나므로,
      // 그 줄에서 세로 획과 후대 사이에 다른 띠가 있으면 그 띠 뒤로 숨어 '그 띠 → 후대'로 읽혔다(고조선 → 조선이 후고구려 · 고려 뒤로 1,100px ·
      // 응우옌 → 남베트남이 프랑스 식민 지배 안에서 끝남). 아래로 가는 선은 후대 줄 위 틈을 따라 구멍 위까지 와서 위에서 들고(오름줄 관문 꼴),
      // 위로 가는 선은 후대 줄 아래 틈을 따라 구멍 앞 9px(되돌아가는 길의 도착 통로)까지 와서 구멍 높이로 든다. 같은 구멍에 옆으로 먼저 든 선이 있으면
      // 아래로 가는 선은 이 길을 먼저 해 본다(합류 점보다 다른 길이 낫다). 틈이 3px 미만 · 구멍이 꺼짐 · 탭 자리 · 골목이 다 차면 그대로.
      List<ui.Offset>? into; // 세로 획([xv]) 뒤의 꺾은점들
      var intoX = 0.0, intoY = 0.0, intoGy = 0.0;
      if (route && (mode == _Mode.hv || mode == _Mode.drop) && p != null && !it.unknownP &&
          (_rowBlocked(pRow, xv, pf, it.from, it.to) || (dir > 0 && _holeSide.containsKey(p.band)))) {
        if (dir > 0) {
          final upGap = pGeo.bandTop - _tabOf(c, pRow);
          final xb = _bird ? pf + BirdLook.stationX : p.fc;
          final xin = (xb - xv).abs() < 2 ? xv : xb;
          final shown = okP || (!_bird && p.fc > right && p.x2 - p.x1 >= 16); // 구멍이 화면 오른쪽 밖이면 틈을 따라 화면 밖으로
          if (upGap >= 3 && shown && _birdClear(pRow, xb) && _overTop(c, p, xin) < 2) {
            final hi = v.yOf(layout.rowTop(pRow) + pGeo.bandTop - _tabOf(c, pRow)), lo = v.yOf(layout.rowTop(pRow));
            final gy = xin == xv ? hi - math.max(2, upGap / 2) : _lane(lo, hi, hi - math.max(2, upGap / 2), xv, xb, who: it);
            if (gy != null) {
              final yE = _bird ? pTop + 1 + BirdLook.stub : y2 - LinkLook.tipGap;
              into = xin == xv ? [ui.Offset(xv, yE)] : [ui.Offset(xv, gy), ui.Offset(xb, gy), ui.Offset(xb, yE)];
              (intoX, intoY, intoGy) = (xin, yE, gy);
            }
          }
        } else if (_rowBlocked(pRow, xv, pf, it.from, it.to)) {
          final nextGap = _gapBelow(c, pRow);
          final xl = pl - 9 - k * 5 - (ring ? 5 : 0);
          final lo = v.yOf(layout.rowTop(pRow) + pGeo.height), hi = v.yOf(layout.rowTop(pRow) + pGeo.height + nextGap);
          // 구멍 앞 9px의 세로 획은 후대 줄에서 후대 앞 띠의 띠 밖 통로(끝 + 9 + 5k — 그 띠에서 나가는 선의 세로 획) 자리와 겹치기 쉽다
          // (판 3.1 동아시아 부여 → 발해가 고구려의 여섯 가닥 사이로) — 그 자리이거나 이미 선 세로 획과 2.5px 안이면 이 길을 하지 않는다.
          if (nextGap >= 3 && okP && xl >= xv + 12 && _columnFree(pRow, it.to, xl, y2, lo)) {
            final gy = _lane(lo, hi, lo + math.max(2, nextGap / 2), xv, xl, who: it);
            if (gy != null) {
              into = [ui.Offset(xv, gy), ui.Offset(xl, gy), ui.Offset(xl, y2), ui.Offset(x2, y2)];
              (intoX, intoY, intoGy) = (xl, y2, gy);
            }
          }
        }
      }
      // 위에서 드는 몫의 관문 · 글줄 비킴 · 합류 점(같은 구멍에 위에서 먼저 든 선이 있으면 그 세로에 닿는 곳에서 멎는다).
      List<ui.Offset> enterTop(List<ui.Offset> path) {
        entered = true;
        final merged = _mergeTop(p!.band, path);
        if (merged != null) {
          dot = merged.last;
          ring = false;
          return merged;
        }
        _upGate(c, p, intoY, pTop, intoX, it, pEdge, dim);
        _dropZone(c, pRow, true, intoX);
        if (ring) {
          // 부흥 고리는 위 틈의 가로 획 위 — 후대 쪽 굽이 앞(틈이 고리를 담을 만할 때만).
          ring = false;
          if (path.length > 3) {
            final xs = path[path.length - 3].dx, side = intoX >= xs ? 1.0 : -1.0, gx = intoX - side * (6 + LinkLook.ringR + 1.5);
            final upGap = pGeo.bandTop - _tabOf(c, pRow);
            if ((gx - xs) * side >= 6 + LinkLook.ringR + 1.5 && upGap >= 2 * LinkLook.ringR + 1) _back.add(_Back.ring(gx, intoGy, qColor, lineAlpha));
          }
        }
        return path;
      }

      switch (mode) {
        case _Mode.hv:
          pts = jog == null
              ? [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, y2), ui.Offset(x2, y2)]
              : [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, jog.$2), ui.Offset(xv, jog.$2), ui.Offset(xv, y2), ui.Offset(x2, y2)];
          if (into != null) pts = [...pts.sublist(0, pts.length - 2), ...into];
          if (ring && !(into != null && dir > 0)) ring = rx - LinkLook.ringR >= (into != null ? intoX : xv) + 3;
          gateOut();
          if (into != null && dir > 0) pts = enterTop(pts);
        case _Mode.rise:
          final yE = _bird ? (dir > 0 ? pTop + 1 + BirdLook.stub : pBottom - 1 - BirdLook.stub) : y2 - dir * LinkLook.tipGap;
          final edgeY = dir > 0 ? pTop : pBottom;
          pts = [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, yE)];
          gateOut();
          if (dir > 0 && p != null) {
            _upGate(c, p, yE, edgeY, xm, it, pEdge, dim);
          } else {
            _gate(c, yE, edgeY - dir * .5, xm, true, edgeY + dir, edgeY, it, pEdge, dim);
          }
          _dropZone(c, pRow, dir > 0, xm);
          if (ring) {
            ring = false;
            final gy = edgeY - dir * (0.5 + 3.6);
            if (dir > 0 ? gy - 3.6 >= qBottom + 1 : gy + 3.6 <= qTop - 1) _back.add(_Back.ring(xm, gy, qColor, lineAlpha));
          }
        case _Mode.drop:
          final edgeY = dir > 0 ? qBottom : qTop;
          pts = jog == null
              ? [ui.Offset(xm, yS), ui.Offset(xm, y2), ui.Offset(x2, y2)]
              : [ui.Offset(xm, yS), ui.Offset(xm, jog.$2), ui.Offset(xv, jog.$2), ui.Offset(xv, y2), ui.Offset(x2, y2)];
          if (into != null) pts = [...pts.sublist(0, pts.length - 2), ...into];
          if (ring && !(into != null && dir > 0)) ring = rx - LinkLook.ringR >= (into != null ? intoX : xv) + 3;
          if (tail) {
            _tailGate(c, qRow, q!, it.kind, dir, xm, yS, it, qEdge, dim);
          } else if (dir < 0 && q != null) {
            _upGate(c, q, yS, edgeY, xm, it, qEdge, dim);
          } else {
            _gate(c, yS, edgeY + dir * .5, xm, true, edgeY - dir, edgeY, it, qEdge, dim);
          }
          _dropZone(c, qRow, dir < 0, xm);
          if (into != null && dir > 0) pts = enterTop(pts);
        case _Mode.back:
          // 되돌아가는 길: 줄 사이의 빈 곳(책갈피 탭 위의 틈)으로 돌아 후대의 건국 네모로 든다.
          final upGap = pGeo.bandTop - _tabOf(c, pRow);
          final nextGap = _gapBelow(c, pRow);
          final up = v.yOf(layout.rowTop(pRow) + pGeo.bandTop - _tabOf(c, pRow)) - math.max(2, upGap / 2);
          final down = v.yOf(layout.rowTop(pRow) + pGeo.height) + math.max(2, nextGap / 2);
          final xl = pl - 9 - k * 5 - (ring ? 5 : 0); // 고리가 있으면 도착 통로를 고리만큼 더 왼쪽에
          List<ui.Offset> via(double gy) =>
              [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, gy), ui.Offset(xl, gy), ui.Offset(xl, y2), ui.Offset(x2, y2)];
          var useUp = dir > 0;
          if ((dir > 0 ? upGap : nextGap) < 3 && (dir > 0 ? nextGap : upGap) >= 3) useUp = !useUp;
          pts = via(useUp ? up : down);
          rad = 5;
          final upLo = v.yOf(layout.rowTop(pRow)), upHi = v.yOf(layout.rowTop(pRow) + pGeo.bandTop - _tabOf(c, pRow));
          final xb = _bird ? pf + BirdLook.stationX : (p?.fc ?? pf + LinkLook.inset);
          final xin = (xb - xm).abs() < 2 ? xm : xb; // 마름모와 구멍이 2px 안이면 곧은 세로 한 획(구멍 반지름 2.5 안에 든다)
          // (가-0) 꼬리 내림 뒤의 되돌아감 가운데 아래로 가는 선은 후대 줄 위 틈에서 후대의 구멍 위로 건너가 위에서 든다(오름줄 관문 꼴 · 명세 04 3-6 · 스위치 route) —
          // 후대 왼쪽으로 돌아 나갔다 구멍 높이로 되돌아오는 갈고리 없이. 구멍이 꺼졌거나 위 틈이 3px 미만이면 예전 꼴.
          // 그 자리에 탭이 설 수 있으면([_overTop] 2) 위에서 들지 않는다(예전 꼴).
          final fromTop = tail && route && dir > 0 && upGap >= 3 && okP && p != null && _birdClear(pRow, xb) && _overTop(c, p, xin) < 2;
          if (route && !fromTop) {
            // 골목 층 표(조사 결함 5): 같은 틈에 앞서 놓인 가로와 겹치면 2.5px 위 · 아래 층으로(다 차면 그대로).
            final center = useUp ? up : down;
            final gy = useUp ? _lane(upLo, upHi, up, xm, xl, force: true) : _lane(v.yOf(layout.rowTop(pRow) + pGeo.height), v.yOf(layout.rowTop(pRow) + pGeo.height + nextGap), down, xm, xl, force: true);
            if (gy != null && gy != center) pts = via(gy);
          }
          if (tail) {
            // (가-0) 꼬리 내림 뒤의 되돌아감: 첫 두 점(마름모 → 띠 밖 통로) 없이 마름모 밑에서 곧게.
            if (fromTop) {
              final yE = _bird ? pTop + 1 + BirdLook.stub : y2 - LinkLook.tipGap;
              final gy = xin == xm ? up : (_lane(upLo, upHi, up, xm, xb, force: true) ?? up);
              pts = xin == xm
                  ? [ui.Offset(xm, yS), ui.Offset(xm, yE)]
                  : [ui.Offset(xm, yS), ui.Offset(xm, gy), ui.Offset(xb, gy), ui.Offset(xb, yE)];
              rad = 6;
              (intoX, intoY, intoGy) = (xin, yE, gy);
              pts = enterTop(pts);
            } else {
              pts = [ui.Offset(xm, yS), ...pts.skip(2)];
            }
            _tailGate(c, qRow, q!, it.kind, dir, xm, yS, it, qEdge, dim);
            _dropZone(c, qRow, dir < 0, xm);
          } else {
            gateOut();
          }
      }
      // 합류 점(명세 04 3-6 · 스위치 route · 조사 결함 43): 같은 구멍에 옆으로 먼저 든 선이 있으면 그 가로와 겹치기 시작하는 곳에서 멎고
      // 그 자리에 제 색 점(지름 3)을 찍는다 — 같은 문 · 같은 가로를 겹쳐 써 어느 선이 드는지 모르던 것(남송 · 원 → 명). 관문은 첫 선의 것.
      if (route && p != null && mode != _Mode.rise && !entered) {
        final merged = _mergeSide(p.band, pts);
        if (merged != null) {
          pts = merged;
          dot = pts.last;
          ring = false;
        }
      }
      if (mode != _Mode.rise && !entered && dot == null) gateIn();
    }
    final width = it.thin ? _thinW : LinkLook.width;
    if (qRow == pRow && pts.length == 2) {
      // 같은 줄의 곧은 선: 사이에 낀 흐린 띠 뒤로는 긋지 않는다([_cutBehindDim]). 맞히기 자리는 선 전체 그대로.
      // 스위치 route면 끊지 않는다 — 흐린 띠도 불투명 종이라 가려지는 것은 같고, 끊지 않아야 그 띠의 테에 굴 문([_tunnels])이 서 고른 선이 이어 보인다.
      for (final (l, r) in PaintPick.route ? [(pts[0].dx, pts[1].dx)] : _cutBehindDim(qRow, pts[0].dx, pts[1].dx, it.from, it.to)) {
        _back.add(_Back.link([ui.Offset(l, y1), ui.Offset(r, y1)], rad, qColor, lineAlpha, it.beat, width));
      }
    } else {
      _back.add(_Back.link(pts, rad, qColor, lineAlpha, it.beat, width));
    }
    final d = dot;
    if (d != null) _back.add(_Back.dot(d.dx, d.dy, qColor, lineAlpha));
    c.debug?.note('승계길', '${it.from}→${it.to} ${pts.map((o) => '${_n(o.dx)},${_n(o.dy)}').join(' ')}${d != null ? ' 합류' : ''}');
    _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, pts));
    if (ring) _back.add(_Back.ring(rx, y2, qColor, lineAlpha));
    // 세로 기둥 표(조사 결함 6 · 13): 이 선의 세로 획을 적어 둔다 — 뒤에 세우는 다른 선대의 통로 · 같은 선대의 조감 내림줄이 비킨다.
    if (PaintPick.route) {
      for (int i = 1; i < pts.length; i++) {
        final a = pts[i - 1], z = pts[i];
        if ((a.dx - z.dx).abs() < 1e-6 && (a.dy - z.dy).abs() >= 1) _cols.add((a.dx, math.min(a.dy, z.dy), math.max(a.dy, z.dy), it.from));
      }
    }
  }

  /// 같은 줄의 띠 뒤 선 [a] ~ [b] 가운데, 사이에 낀 다른 띠(두 끝 [from] · [to]가 아닌 띠)가 **흐린**(밝기 < 1 — 고르기 · 흐림) 구간을 뺀 조각들.
  /// 4단계 마지막 합치기 뒤: 흐린 띠 칠도 바탕과 섞은 불투명 종이라(감독 결정 '맨 아래 한 번 긋고 위에 얹기') 아래 까닭의 '비침'은 더 없고 끊음은 보이는 것을
  /// 바꾸지 않는다 — 끊은 조각은 그 띠를 지나지 않아 굴 문([_tunnels])이 서지 않으므로 스위치 route면 쓰지 않는다(끈 길만 · 흐린 띠를 비추게 되돌리면 다시 — 감독 확인 몫).
  /// 띠가 온전히 칠해지면 어차피 가려지는 몫이다. 흐린 띠는 뒤가 비치므로, 고른 띠에 닿아 짙어진 선이 그 띠의 이름 · 점을 줄 긋듯 가로질러 보였다
  /// (등불 V 조감에서 등불 왕국을 누르면 등불 왕국 → 하연 부흥국 선이 흐린 하연 총관부 이름 위로 — 2026-10-25 조감 글자 겹침 검증).
  /// 지금 연표는 흐린 띠(opacity)가 뒤 선을 그대로 비춘다 — 앱의 덧 규칙이다. 흐리지 않은 장면은 예전과 같은 선 하나다.
  List<(double, double)> _cutBehindDim(int row, double a, double b, int from, int to) {
    var pieces = [(a, b)];
    final list = _rowSquares[row];
    if (list == null || emphasis == null) return pieces;
    for (final o in list) {
      if (o.band == from || o.band == to || o.x2 <= a || o.x1 >= b) continue;
      if (bandAlpha(o.band, o.row) >= 1) continue;
      pieces = [
        for (final (l, r) in pieces)
          if (o.x2 <= l || o.x1 >= r)
            (l, r)
          else ...[
            if (o.x1 - l >= 1) (l, o.x1),
            if (r - o.x2 >= 1) (o.x2, r),
          ],
      ];
    }
    return pieces;
  }

  /// 내림줄 · 오름줄이 띠 안을 지나는 자리(반너비 5px)는 사건 글자가 비켜 간다(명세 3-6 다 · 3-5 ①).
  /// [first]면 첫 글줄만, 아니면 둘째 글줄부터 — 네모가 첫 글줄 위쪽에 있어 위로 나가면 첫 글줄, 아래로 나가면 둘째 글줄부터다.
  /// 스위치 route면 첫 글줄 쪽(위로 나가는 획 · 위에서 드는 획)은 구간을 적지 않는다(명세 04 3-6 다 · 3-7 · 검증 지적): 두 장 꼬리표의 마름모 · 구멍은
  /// 이름 색줄(윗변 + 7)에 있고 사건 칸은 색줄 밑이라, 그 획은 사건 글자 · 점과 만나지 않는다 — 예전 규칙대로 적으면 글줄 하나인 띠에서 점까지 밀려 합쳐졌다.
  /// 조감은 띠 하나가 글줄이라 그대로 적는다.
  void _dropZone(PaintContext c, int row, bool first, double xm) {
    if (first && PaintPick.route && !_bird) return;
    final lines = c.layout.geo(row).textLines;
    const half = LinkLook.half + LinkLook.sqClear;
    // 내림줄은 이름 줄 전체를 막는다(js:7001의 `reserved[z.row][k].push([z.l, z.r])` — 셋째 값이 없다) · 점은 오른쪽으로 민다.
    if (lines <= 1 || first) {
      _zone(row, xm - half, xm + half, 0, lines <= 1, 0, 1);
      return;
    }
    for (int k = 1; k < lines; k++) {
      _zone(row, xm - half, xm + half, k, false, 0, 1);
    }
  }

  /// (가-0) 앞 나라 끝 지키기(명세 04 3-6 · 2026-10-25 감독 결정 (1) · 스위치 route). 선대 [q]의 세로 통로 [xm](= qEnd + 9 + k×5) 자리를
  /// 같은 줄의 다음 띠 N(사라지는 꼬리 포함)이 덮으면 선이 N 밑에서 나오는 것처럼 보인다 — 통로를 앞 나라 끝으로 옮긴다:
  /// N과의 틈이 8px 이상이면 틈 안(qEnd + 3 + 3j · N 앞 3px까지), 아니면 꼬리 마름모 밑 내림([tailX] − 3j · 그 x에서 [tailOK]일 때만 —
  /// 마름모가 보이고 조감이면 띠 안 이름을 비키고 위로 가는 선이면 탭 밑이 아님).
  /// 돌려주는 값은 (통로 x, 꼬리 내림인가). N이 없거나 옮길 곳이 없으면 null — 길은 지금 그대로다.
  /// 같은 선대 · 같은 종류의 선은 한 줄기(같은 x · j는 그 선대에서 세운 줄기의 차례)로 묶는다. 이미 선 꼬리 줄기도 이 선의 쪽에서 [tailOK]가 아니면
  /// 함께 쓰지 않는다(이어 주는 선 미룸 4 — 아래로 가는 선이 세운 줄기를 위로 가는 선이 탭 밑으로 함께 쓰던 것).
  (double, bool)? _exitAt(_Square q, int kind, double qEnd, double xm, double tailX, bool Function(double x) tailOK) {
    final key = q.band * 4 + kind;
    final had = _stems[key];
    if (had != null) return !had.$2 || tailOK(had.$1) ? had : null;
    final list = _rowSquares[q.row];
    if (list == null) return null;
    // 줄의 띠는 왼쪽 끝 차례 — 선대 끝 − 꼬리 폭보다 앞에서 시작하는 띠는 선대와 겹치지 않으므로(chainRows) 이분 탐색으로 건너뛴다.
    final from = q.bandEnd - LinkLook.fade - 1;
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].x1 < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _Square? n;
    for (int i = lo; i < list.length && list[i].x1 < xm + 4; i++) {
      final o = list[i];
      if (o.band != q.band && o.x2 > qEnd) {
        n = o;
        break;
      }
    }
    if (n == null) return null;
    final j = _stemCount[q.band] ?? 0;
    final gap = n.x1 - qEnd;
    final (double, bool) out;
    if (gap >= 8 && qEnd + 3 + 3 * j <= n.x1 - 3) {
      out = (qEnd + 3 + 3 * j, false);
      _stemCount[q.band] = j + 1;
    } else if (tailOK(_tailAt(q, kind, tailX))) {
      out = (_tailAt(q, kind, tailX), true); // 꼬리 내림 갈래가 같은 열쇠의 줄기를 먼저 세웠으면 그 x(관문 한 번)
      _takeTail(q, kind, out.$1);
    } else {
      return null;
    }
    return _stems[key] = out;
  }

  /// 같은 줄 ⊓(명세 04 3-4 · 스위치 route · 조사 결함 2 · 3)의 자리: 같은 줄 [row]에서 선대 [q]와 후대 [p] 사이(선의 두 끝 [x1] ~ [x2])에
  /// 다른 띠(사라지는 꼬리 포함)가 있고, 줄 위 틈(책갈피 탭 자리를 뺀 빈 곳 — 되돌아가는 길의 `up`과 같은 셈)이 3px 이상이면
  /// (오르는 x = 꼬리 마름모 · 드는 x = 구멍 · 틈 y). 조감은 마름모 · 구멍 대신 띠 끝 안쪽 7(내림줄 · 오름줄 자리)이고 띠 안 이름을 비킬 때만.
  /// 사이 띠가 없거나 틈 · 굽이 둘이 들 가로 자리가 없으면 null — 곧은 선 그대로(띠 뒤로 지나는 몫은 굴 문 3-9).
  /// 셈: 줄의 띠는 왼쪽 끝 차례라 '선대 끝 − 꼬리 폭'부터 이분 탐색해 [x2] 앞까지만 본다.
  (double, double, double)? _capAt(PaintContext c, int row, _Square q, _Square p, double x1, double x2) {
    final list = _rowSquares[row];
    if (list == null) return null;
    final from = q.bandEnd - LinkLook.fade - 1;
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].x1 < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    var between = false;
    for (int i = lo; i < list.length && list[i].x1 < x2; i++) {
      final o = list[i];
      if (o.band != q.band && o.band != p.band && o.x2 > x1) {
        between = true;
        break;
      }
    }
    if (!between) return null;
    final layout = c.layout, geo = layout.geo(row);
    final gap = geo.bandTop - _tabOf(c, row);
    if (gap < 3) return null;
    final xa = _bird ? q.bandEnd - BirdLook.stationX : q.ec;
    final xb = _bird ? p.bandStart + BirdLook.stationX : p.fc;
    if (xb - xa < 2 * 6 + 2) return null;
    if (_bird && !(_birdClear(row, xa) && _birdClear(row, xb))) return null;
    // 두 끝의 세로 획이 받침 카드 위 탭 자리를 지나면 세우지 않는다([_overTop] 2 · 카드 윗단만이면 관문이 카드 윗변까지 — [_upGate] · 검증 지적).
    if (_overTop(c, q, xa) == 2 || _overTop(c, p, xb) == 2) return null;
    return (xa, xb, c.v.yOf(layout.rowTop(row) + gap) - math.max(2, gap / 2));
  }

  /// (가-0) 선대 줄과 후대 줄 사이의 펴진 줄(사이 줄)이 통로 [xm]을 막으면(그 줄의 [_clearAt] 거짓) 선대 줄 밑(위로 가면 위) 틈의 한가운데에서
  /// [xm] ± 40px 안의 빈 기둥(사이 줄 모두 비어 있는 x — 가까운 것부터 · 같으면 오른쪽 먼저 · 1px 걸음)으로 옮긴다. 돌려주는 값은 (기둥 x, 틈 y).
  /// 사이 줄이 비었거나 막히지 않았거나 틈(3px 미만) · 기둥이 없으면 null(그대로 — 띠 뒤로 지나는 몫은 굴 문 3-9의 몫).
  /// [take]면 그 틈의 골목 층 표(조사 결함 5 — [_lane])에 가로 토막을 적고 층을 고른다(길을 고를 수 있는지만 묻는 자리는 적지 않는다).
  (double, double)? _jogAt(PaintContext c, int qRow, int pRow, int dir, double xm, double x2, {bool take = true}) {
    final layout = c.layout, v = c.v;
    final mid = _midRows(c, qRow, pRow);
    bool clear(double x) {
      for (final r in mid) {
        if (!_clearAt(r, x, 0)) return false;
      }
      return true;
    }

    if (mid.isEmpty || clear(xm)) return null;
    final geo = layout.geo(qRow);
    final double gy, lo, hi;
    if (dir > 0) {
      final gap = _gapBelow(c, qRow);
      if (gap < 3) return null;
      lo = v.yOf(layout.rowTop(qRow) + geo.height);
      hi = v.yOf(layout.rowTop(qRow) + geo.height + gap);
      gy = lo + math.max(2, gap / 2);
    } else {
      final gap = geo.bandTop - _tabOf(c, qRow);
      if (gap < 3) return null;
      lo = v.yOf(layout.rowTop(qRow));
      hi = v.yOf(layout.rowTop(qRow) + geo.bandTop - _tabOf(c, qRow));
      gy = hi - math.max(2, gap / 2);
    }
    for (int d = 1; d <= 40; d++) {
      for (final x in [xm + d, xm - d]) {
        if (x2 >= x + 6 && clear(x)) return (x, take && PaintPick.route ? (_lane(lo, hi, gy, xm, x, force: true) ?? gy) : gy);
      }
    }
    return null;
  }

  /// 골목 층 표(명세 04 3-6 · 스위치 route · 조사 결함 5 — 같은 후대 줄로 드는 가로 셋이 한 줄로 포개짐): 줄 사이 틈 하나(위 끝 [lo] ~ 아래 끝 [hi] — 화면 y)에
  /// 가로 토막 [a] ~ [b]를 놓을 높이. 가운데 [center] → 2.5px 위 → 2.5px 아래 차례로, 틈 안(위아래 끝에서 1px 안쪽)이고 같은 높이에 앞서 놓인 토막과
  /// 3px 안으로 겹치지 않는 첫 높이를 적고 돌려준다(한 틈에 많아야 세 층 — 위 틈 8px인 줄은 세 층 · 6px인 구성원 줄은 한 층). 다 차면 null(부르는 쪽이 지금 길로 둔다).
  /// 틈은 아래 끝(다음 줄의 탭 자리 위)으로 가린다 — 위 줄의 '아래 틈'과 아래 줄의 '위 틈'은 같은 틈이다.
  /// 틈으로 드는 선([who] — 후대 줄의 틈으로 들기)은 아직 세우지 않은 더 무거운 몫([_claims] — 띠 뒤로 숨을 px이 더 긴 선)이 겹치는 만큼 층을 남겨 두고
  /// 고른다(틈이 3px인 보통 밀도는 한 층뿐이라, 먼저 세운 짧은 몫이 고조선 → 조선처럼 1,100px 숨을 선의 자리를 가져가지 않게). 예전부터 틈을 쓰던 길
  /// (되돌아감 · ⊓ · 빈 기둥 · 꼬리 내림 뒤 위에서 듦)은 [force] — 틈 말고 갈 데가 없으므로 몫을 보지 않고, 다 차도 가운데에 적고 돌려준다(예전과 같은 자리).
  double? _lane(double lo, double hi, double center, double a, double b, {_LinkIn? who, bool force = false}) {
    final l = math.min(a, b), r = math.max(a, b);
    final key = (hi * 4).round();
    final list = _lanes[key] ??= [];
    final free = <double>[];
    for (final y in [center, center - 2.5, center + 2.5]) {
      if (y < lo + 1 - 1e-6 || y > hi - 1 + 1e-6) continue;
      var open = true;
      for (final (ly, la, lb) in list) {
        if ((ly - y).abs() < .1 && la < r + 3 && lb > l - 3) {
          open = false;
          break;
        }
      }
      if (open) free.add(y);
    }
    var hold = 0; // 남겨 둘 층 — 이 틈에 겹치는, 더 무거운 아직 세우지 않은 몫의 수
    if (who != null) {
      final mine = _claims[who]?.$4 ?? 0;
      for (final MapEntry(key: other, value: (k, ca, cb, w)) in _claims.entries) {
        if (!identical(other, who) && k == key && w > mine && ca < r + 3 && cb > l - 3) hold++;
      }
    }
    if (free.length > hold) {
      final y = free[hold];
      list.add((y, l, r));
      return y;
    }
    if (!force) return null;
    list.add((center, l, r));
    return center;
  }

  /// 틈으로 들 몫의 어림(조사 결함 5 · [_lane]의 [who]): 길을 세우기 전에 한 번 — 살아남은 다른 줄 쌍마다 지금 길의 hv 꼴(통로 = 선대 끝 + 9 + 5k)로 어림해,
  /// 후대 줄의 [통로, 후대 시작]을 다른 띠 몸통이 덮으면 그 덮는 px을 무게로 그 틈(아래로 가면 후대 줄 위 틈 · 위로 가면 아래 틈)과 가로 자리를 적는다.
  /// 어림이 실제 길과 달라도(앞 나라 끝 지키기 · 빈 기둥) 층을 남겨 두는 데만 쓴다 — 선을 세우면 지운다.
  void _claimGaps(PaintContext c, List<_LinkIn> links) {
    final layout = c.layout, v = c.v;
    for (final l in links) {
      if (l.lane < 0 || l.absorb || l.unknownP) continue;
      final q = _squares[l.from], p = _squares[l.to];
      if (q == null || p == null) continue;
      final pRow = p.row, geo = layout.geo(pRow);
      final xm = q.bandEnd + (l.unknownQ ? LinkLook.fade : 0) + 9 + 5 * l.lane;
      final pf = p.bandStart;
      final xb = _bird ? pf + BirdLook.stationX : p.fc;
      if (xb - (_bird ? 0 : TagLook.holeR) < xm + 6) continue;
      var weight = 0.0;
      for (final o in _rowSquares[pRow] ?? const <_Square>[]) {
        if (o.band == l.from || o.band == l.to) continue;
        final w = math.min(pf, o.bandEnd) - math.max(xm, o.bandStart);
        if (w > 2) weight += w;
      }
      if (weight <= 0) continue;
      if (_endsOf(c, l).$3) {
        _claims[l] = ((v.yOf(layout.rowTop(pRow) + geo.bandTop - _tabOf(c, pRow)) * 4).round(), xm, xb, weight);
      } else {
        final xl = pf - 9 - 5 * l.lane;
        _claims[l] = ((v.yOf(layout.rowTop(pRow) + geo.height + _gapBelow(c, pRow)) * 4).round(), xm, xl, weight);
      }
    }
  }

  /// 줄 [row] 위 틈(줄 위 끝 ~ 탭 자리 위)의 골목 층([_lane]).
  double? _laneAt(PaintContext c, int row, double center, double a, double b) {
    final layout = c.layout, v = c.v, geo = layout.geo(row);
    return _lane(v.yOf(layout.rowTop(row)), v.yOf(layout.rowTop(row) + geo.bandTop - _tabOf(c, row)), center, a, b, force: true);
  }

  /// 줄 [row]에서 두 끝 띠([from] · [to]) 말고 다른 띠의 몸통(제 두 끝 — 사라지는 꼬리 뺌)이 가로 [a] ~ [b]를 2px 넘게 덮는가 —
  /// 그 줄의 구멍 높이로 지나는 가로가 그 띠 뒤로 숨는가(굴 문 3-9가 문을 두는 문턱과 같은 2px).
  bool _rowBlocked(int row, double a, double b, int from, int to) {
    final list = _rowSquares[row];
    if (list == null || b - a < 2) return false;
    for (final o in list) {
      if (o.band == from || o.band == to) continue;
      if (math.min(b, o.bandEnd) - math.max(a, o.bandStart) > 2) return true;
    }
    return false;
  }

  /// 줄 [row]에서 세로 획 [x](세로 범위 [ya] ~ [yb])가 비었는가: 이미 선 세로 획(세로 기둥 표)과 2.5px 넘게 떨어지고, 그 줄의 다른 띠(띠 [self] 말고)에서
  /// 나가는 선의 띠 밖 통로 자리(끝 + 9 ~ 끝 + 9 + 5 × (통로 수 − 1) — 아직 세우지 않은 선도)와 3px 넘게 떨어진다.
  bool _columnFree(int row, int self, double x, double ya, double yb) {
    final lo = math.min(ya, yb), hi = math.max(ya, yb);
    for (final (cx, top, bottom, _) in _cols) {
      if ((cx - x).abs() < 2.5 && top < hi && bottom > lo) return false;
    }
    for (final o in _rowSquares[row] ?? const <_Square>[]) {
      final n = o.band == self ? 0 : (_chanCount[o.band] ?? 0);
      if (n == 0) continue;
      final e = o.bandEnd + (o.unknownEnd ? LinkLook.fade : 0) + 9;
      if (x > e - 3 && x < e + 5 * (n - 1) + 3) return false;
    }
    return true;
  }

  /// 세로 기둥 표로 띠 밖 통로 비키기(명세 04 3-6 · 스위치 route · 조사 결함 6): 다른 선대가 이미 세운 세로 획(같은 세로 범위 [ya] ~ [yb]와 겹치는 것)이
  /// 통로 [xm]과 2.5px 안이면 3px씩 오른쪽으로(세 번까지). 옮긴 통로가 길의 꼴을 바꾸거나(후대가 오른쪽 6px 밖인지가 달라짐) 선대 줄의 다른 띠 밑이 되면 그대로.
  double _dodgeColumn(int qRow, int from, double xm, double x2, double ya, double yb) {
    var x = xm;
    for (int t = 0; t < 3; t++) {
      var hit = false;
      for (final (cx, top, bottom, f) in _cols) {
        if (f != from && (cx - x).abs() < 2.5 && top < yb && bottom > ya) {
          hit = true;
          break;
        }
      }
      if (!hit) break;
      x += 3;
    }
    if (x == xm || (x2 >= x + 6) != (x2 >= xm + 6) || !_clearAt(qRow, x, from)) return xm;
    return x;
  }

  /// 조감 내림줄 비킴(명세 04 7-2 · 스위치 route · 조사 결함 13): 같은 선대 [q]가 이미 세운 세로 획이 내림줄 [x]와 2.5px 안이고 세로 범위([ya] ~ [yb])가 겹치면
  /// 3px씩 띠 안쪽(왼쪽)으로 — 띠가 2 × (STUB + 3) + 3 이상이고 옮긴 자리가 띠 끝 STUB + 3 안 · 띠 안 이름 밖 · 후대 줄의 다른 띠 밖일 때만(세 번까지).
  double _innerDrop(int qRow, int pRow, _Square q, int to, double x, double ya, double yb) {
    if (q.bandEnd - q.bandStart < 2 * (BirdLook.stub + 3) + 3) return x;
    var at = x;
    for (int t = 0; t < 3; t++) {
      var hit = false;
      for (final (cx, top, bottom, f) in _cols) {
        if (f == q.band && (cx - at).abs() < 2.5 && top < yb && bottom > ya) {
          hit = true;
          break;
        }
      }
      if (!hit) return at;
      final nx = at - 3;
      if (nx < q.bandStart + BirdLook.stub + 3 || !_birdClear(qRow, nx) || !_clearAt(pRow, nx, to)) return at;
      at = nx;
    }
    return at;
  }

  /// hv 빈 기둥(명세 04 3-6 (나) · 스위치 route · 조사 결함 4 · 42 (가)): 띠 밖 통로 [xm]을 사이 줄의 띠가 막으면 그 자리를 막은 띠들의 오른끝 + 4로
  /// 옮겨 다시 본다(8번까지 — 사이 줄은 [_midRows]처럼 화면 높이로). 사이 줄이 모두 비는 기둥 x에서, 선대 줄의 [선대 끝 [qEnd], x]가 비었고(그 가로가 다른 띠 뒤로 숨지 않게) 후대가 x 오른쪽 6px 밖이면 x.
  /// 다른 선대가 이미 세운 세로 획(세로 범위 [ya] ~ [yb]와 겹치는 것)과 2.5px 안이면 그 오른쪽 3으로 더 옮긴다(삼한 셋이 한 기둥에 포개지지 않게).
  /// 옮기는 거리는 [_jogAt]의 빈 기둥과 같은 40px까지 — 더 멀면 선대 줄의 구멍 높이로 수백 px 가로가 생겨 '그 줄에서 이어지는 선'으로 읽힌다(판 3.1 삼한 → 신라).
  /// 없으면 null(그대로 — 지나는 띠는 굴 문 3-9).
  double? _openColumn(PaintContext c, int qRow, int pRow, double xm, double x2, double qEnd, int from, double ya, double yb) {
    final mid = _midRows(c, qRow, pRow);
    var x = xm;
    for (int t = 0; t < 8; t++) {
      var far = double.negativeInfinity;
      for (final r in mid) {
        for (final o in _rowSquares[r] ?? const <_Square>[]) {
          if (o.x1 < x + 4 && o.x2 > x - 4 && o.x2 > far) far = o.x2;
        }
      }
      if (far == double.negativeInfinity) {
        for (final (cx, top, bottom, f) in _cols) {
          if (f != from && (cx - x).abs() < 2.5 && top < yb && bottom > ya) far = math.max(far, cx - 1);
        }
      }
      if (far == double.negativeInfinity) {
        if (x == xm || x2 < x + 6 || !_clearAt(qRow, (qEnd + x) / 2, from, (x - qEnd) / 2)) return null;
        return x;
      }
      x = far + 4;
      if (x2 < x + 6 || x - xm > 40) return null;
    }
    return null;
  }

  /// 합류 점(조사 결함 43) — 옆으로: 꺾은선 [pts]의 끝 토막이 구멍으로 드는 가로(오른쪽으로)이면, 같은 구멍(띠 [band])에 옆으로 먼저 든 선의 가로와 견준다.
  /// 먼저 든 선이 없으면 이 선을 적고 null. 같은 높이로 먼저 든 선이 있으면 그 가로와 겹치기 시작하는 곳에서 멎은 꺾은선 — 이 선의 가로가 먼저 든 선의 가로
  /// 안에서 시작하면 가로 없이 그 꺾는 자리(세로가 닿는 곳)에서, 더 왼쪽에서 오면 먼저 든 선의 가로 시작에서 — 단 그 시작이 꺾는 자리일 때만
  /// (같은 줄의 곧은 선은 가로가 제 꼬리 마름모에서 시작하므로 거기서 멎으면 '그 띠로 드는 선'으로 읽힌다). 멎고 남는 것이 없으면 null(그대로 겹친다).
  List<ui.Offset>? _mergeSide(int band, List<ui.Offset> pts) {
    final n = pts.length;
    if (n < 2) return null;
    final last = pts[n - 1], prev = pts[n - 2];
    if ((prev.dy - last.dy).abs() > 1e-6 || prev.dx >= last.dx) return null;
    final had = _holeSide[band];
    if (had == null) {
      _holeSide[band] = (prev.dx, last.dy, n > 2);
      return null;
    }
    if ((had.$2 - last.dy).abs() > .5) return null;
    if (prev.dx >= had.$1 - .5) return n > 2 ? pts.sublist(0, n - 1) : null;
    if (!had.$3) return null;
    return [...pts.sublist(0, n - 1), ui.Offset(had.$1, last.dy)];
  }

  /// 합류 점(조사 결함 43) — 위에서: 꺾은선 [pts]의 끝 토막이 구멍으로 위에서 드는 세로이면, 같은 구멍(띠 [band])에 위에서 먼저 든 선(같은 x)의 세로와 견준다.
  /// 먼저 든 선이 없으면 이 선을 적고 null. 있으면 그 세로와 겹치기 시작하는 곳에서 멎은 꺾은선 — 이 선의 틈 가로가 먼저 든 선의 틈 가로보다 아래(구멍 쪽)면
  /// 그 가로가 세로에 닿는 곳에서, 위면 먼저 든 선의 꺾는 자리에서.
  List<ui.Offset>? _mergeTop(int band, List<ui.Offset> pts) {
    final n = pts.length;
    if (n < 2) return null;
    final last = pts[n - 1], prev = pts[n - 2];
    if ((prev.dx - last.dx).abs() > 1e-6 || prev.dy >= last.dy) return null;
    final had = _holeTop[band];
    if (had == null) {
      _holeTop[band] = (last.dx, prev.dy);
      return null;
    }
    if ((had.$1 - last.dx).abs() > .5) return null;
    if (prev.dy >= had.$2 - .5) return n > 2 ? pts.sublist(0, n - 1) : null;
    return [...pts.sublist(0, n - 1), ui.Offset(last.dx, had.$2)];
  }

  /// (가-0) ② 꼬리 마름모 밑 내림의 관문: 마름모 밑(위)에서 선대 꼬리표의 몸통 변까지 띠 위 층의 세로 획 + 그 변의 문(3-3의 drop 꼴).
  /// 아래로 가면 변은 제 꼬리표 몸통의 아랫변([BandLayer.bodyBottomOf] — 사건 칸을 올린 꼬리표는 줄의 띠 아랫변보다 위)이고, 그 줄에 꼬리표 밑 흰 사슬
  /// (왕조 · 지위 — [RowGeo.chainTop])이 있으면 사슬 단 밑까지 획을 잇고 사슬 아랫변에도 문을 둔다 — 선이 사슬 종이 뒤로 숨지 않게.
  /// 같은 줄기 · 같은 쪽(위 · 아래)의 둘째 선부터는 같은 자리라 다시 긋지 않고, 그 관문을 함께 쓰는 몫으로 감사에 적는다([_shareSpans]).
  /// 쪽을 열쇠에 넣는 까닭: 한 줄기에서 위로 가는 선과 아래로 가는 선이 함께 나가면 관문이 서로 다른 변에 서야 한다(검증 지적).
  void _tailGate(PaintContext c, int row, _Square q, int kind, int dir, double x, double yS, _LinkIn it, int edge, double dim) {
    final key = (q.band * 4 + kind) * 2 + (dir > 0 ? 1 : 0);
    if (!_stemGated.add(key)) {
      final had = _gateSpan[key];
      if (had != null) _shareSpans.add(had);
      return;
    }
    final t0 = _top.length;
    final layout = c.layout, v = c.v, geo = layout.geo(row), top = layout.rowTop(row);
    if (_bird) {
      final edgeY = dir > 0 ? v.yOf(top + geo.bandTop + geo.bandHeight) : v.yOf(top + geo.bandTop);
      _gate(c, yS, edgeY + dir * .5, x, true, edgeY - dir, edgeY, it, edge, dim);
    } else if (dir < 0) {
      _upGate(c, q, yS, v.yOf(top + geo.bandTop), x, it, edge, dim);
    } else {
      final body = v.yOf(top + (_bands?.bodyBottomOf(layout, row, q.band) ?? geo.bandTop + geo.bandHeight));
      final lift = _bands?.eventLiftOf(layout, row, q.band) ?? 0;
      final chain = geo.chainTop >= 0 ? v.yOf(top + geo.bandTop + geo.bandHeight + geo.chainDepth - lift) : body;
      _gate(c, yS, math.max(body, chain) + .5, x, true, body - 1, body, it, edge, dim);
      if (chain > body + .5) _top.add(_Top.door(x - _doorH / 2, chain - 1.5, x + _doorH / 2, chain + .5, dim));
    }
    _gateSpan[key] = (t0, _top.length);
  }

  /// 위로 드는 획의 띠 윗변 관문(명세 04 3-3 · 3-7): 띠 [sq]의 윗변 [edgeY]를 [x]에서 지나는 문과 [yS] ~ 윗변의 띠 위 획.
  /// 스위치 route면, 그 자리에 받침 카드의 윗단이 드러나 있을 때([BandLayer.overTop] 1 — 카드는 띠 뒤 선보다 위 판이라 선을 덮는다)
  /// 획을 카드 윗변까지 잇고 카드 윗변에도 문을 둔다(꼬리 관문의 사슬 문과 같은 까닭 · 검증 지적).
  void _upGate(PaintContext c, _Square sq, double yS, double edgeY, double x, _LinkIn it, int edge, double dim) {
    if (_overTop(c, sq, x) == 1) {
      final sheetTop = edgeY - BandLayer.sheetRise;
      _gate(c, yS, sheetTop - .5, x, true, edgeY + 1, edgeY, it, edge, dim);
      _top.add(_Top.door(x - _doorH / 2, sheetTop - .5, x + _doorH / 2, sheetTop + 1.5, _lit(it, x, c) ? 1.0 : dim));
      return;
    }
    _gate(c, yS, edgeY - .5, x, true, edgeY + 1, edgeY, it, edge, dim);
  }

  /// 띠 [sq]의 윗변 위가 [x]의 문 폭에서 무엇에 덮이는가(스위치 route · 조감 아님만 — [BandLayer.overTop]): 0 비었음 · 1 받침 카드 윗단 · 2 탭.
  int _overTop(PaintContext c, _Square sq, double x) =>
      !PaintPick.route || _bird ? 0 : (_bands?.overTop(c, sq.band, sq.row, x, _doorH / 2 + 1) ?? 0);

  /// 선대 줄 [qRow]와 후대 줄 [pRow] 사이의 펴진 줄(사이 줄)이 모두 세로 획 [x]를 비우는가([_jogAt]의 `clear`와 같은 셈 · 사이 줄이 없으면 참).
  bool _midClear(PaintContext c, int qRow, int pRow, int dir, double x) {
    for (final r in _midRows(c, qRow, pRow)) {
      if (!_clearAt(r, x, 0)) return false;
    }
    return true;
  }

  /// 선대 줄 [qRow]와 후대 줄 [pRow] 사이에 선 펴진 줄(이 장면에 네모가 실린 줄 — 사이 줄 비킴 · (가-0)이 보는 줄). 사이는 줄 번호가 아니라 화면 높이로 —
  /// 그릇을 펼친 장면은 줄 번호 차례와 화면 차례가 다르다(4단계 마지막 합치기 검토 지적 · 번호 차례가 화면 차례인 장면은 예전과 같은 줄들).
  List<int> _midRows(PaintContext c, int qRow, int pRow) {
    final layout = c.layout;
    final a = layout.rowTop(qRow), b = layout.rowTop(pRow);
    final lo = math.min(a, b), hi = math.max(a, b);
    return [
      for (final r in _rowSquares.keys)
        if (r != qRow && r != pRow && r >= 0 && r < layout.rowCount && layout.hasBody(r) && layout.rowTop(r) > lo && layout.rowTop(r) < hi) r,
    ];
  }

  /// 꼬리 마름모 밑 줄기의 x([_tails]): 그 열쇠의 줄기가 이미 섰으면 그 x, 아니면 [tailX] − 3 × (선대에서 세운 줄기 수).
  double _tailAt(_Square q, int kind, double tailX) => _tails[q.band * 4 + kind] ?? tailX - 3 * (_stemCount[q.band] ?? 0);

  /// 꼬리 줄기를 잡는다 — 처음 잡는 열쇠면 [_stemCount]를 올린다.
  void _takeTail(_Square q, int kind, double x) {
    final key = q.band * 4 + kind;
    if (_tails.containsKey(key)) return;
    _tails[key] = x;
    _stemCount[q.band] = (_stemCount[q.band] ?? 0) + 1;
  }

  /// 네모의 가운데와 모든 가로 획이 오는 높이(명세 2-1절): `rowTop + (글줄이 둘 이상이면 textTop + 글줄높이, 하나면 textTop + 글줄높이/2)`.
  /// 조감은 `textTop = 0 · 글줄높이 = 띠 높이`라 띠 한가운데가 된다(명세 05의 7-2절).
  /// 꼬리표 갈래 E(설계 4-1): 조감이 아니면 **구멍 높이** — 띠 윗변 + [TagLook.holeY]. 승계선은 꼬리 마름모에서 나와 뒤 꼬리표의 구멍으로 든다.
  double _anchorY(PaintContext c, int row) {
    final geo = c.layout.geo(row);
    if (!_bird) return c.v.yOf(c.layout.rowTop(row) + geo.bandTop + TagLook.holeY);
    final lineH = _bird ? geo.bandHeight : G.line;
    final base = _bird ? geo.bandTop : geo.textTop;
    return c.v.yOf(c.layout.rowTop(row) + (!_bird && geo.textLines > 1 ? base + lineH : base + lineH / 2));
  }

  /// 조감에서 관문을 둘 수 있는 끝인가(명세 3-2 · 7452): 끝이 화면 안이고 띠 폭이 2 × (STUB + 3) = 12px 이상.
  bool _birdEnd(PaintContext c, _Square? sq, double x) {
    if (x < c.left - 1 || x > c.w + 1) return false;
    if (sq == null) return true;
    return sq.bandEnd - sq.bandStart >= 2 * (BirdLook.stub + 3);
  }

  /// 그 줄의 책갈피 탭 자리(접힌 줄 · 그 밖 줄 · 조감은 0).
  /// 꼬리표 갈래 E: 띠 위 틈(5 — 상국 · 연합 탭이 솟는 줄은 + 15)을 줄 배치에서 그대로 읽는다(`SceneLayout.tabOf`).
  double _tabOf(PaintContext c, int row) => c.layout.tabOf(row);

  /// 후대 줄 아래의 첫 펴진 줄 위의 빈 곳(책갈피 탭 자리는 뺀다).
  double _gapBelow(PaintContext c, int row) {
    for (int j = row + 1; j < c.layout.rowCount; j++) {
      if (!c.layout.isVisible(j)) continue;
      return c.layout.geo(j).bandTop - _tabOf(c, j);
    }
    return c.layout.metrics.gap;
  }

  /// 줄 [row]에서 [self] 말고 다른 띠(사라지는 꼬리 포함)가 x ± (4 + half)를 덮지 않는가.
  bool _clearAt(int row, double x, int self, [double half = 0]) {
    final list = _rowSquares[row];
    if (list == null) return true;
    for (final o in list) {
      if (o.band == self) continue;
      if (o.x1 < x + 4 + half && o.x2 > x - 4 - half) return false;
    }
    return true;
  }

  /// 내림줄을 띠 안에 그어도 되는가(명세 3-7절).
  /// 지시대로 이번 옮김에서는 **띠 · 칸의 자료로만** 본다 — 지금 연표가 함께 보는 '± 10px 안의 사건'은 다른 층(사건 배치)의 값이라 아직 닿지 않는다.
  /// 줄 [row]의 아래쪽 단과 띠 밑에 덧붙은 것이 [xc] ± 10px 안에 실제로 있는가(js `_lowerBusy`) — 칸(구역 2)의 기관 · 인물 · 예속,
  /// 인물 막대(구역 37), 매달린 속국 이름표(구역 16 — 세로 끈은 빼고), 구역 탭(구역 17), 꼬리표 밑 흰 사슬의 칸(왕조 · 지위 — 감독 고름 G5 #9 나)을
  /// 제 가로 구간으로 본다. 바탕 문화의 이름 단은 선이 지나가는 바탕이라 보지 않는다.
  bool _lowerBusy(PaintContext c, int row, double xc) {
    for (final (a, b) in _lowerSpans.putIfAbsent(row, () => _collectLower(c, row))) {
      if (a < xc + 10 && b > xc - 10) return true;
    }
    return false;
  }

  List<(double, double)> _collectLower(PaintContext c, int row) {
    final v = c.v, out = <(double, double)>[];
    // 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나): 왕조 · 지위(와 지위 단 자리의 렌즈 칸)가 띠 아랫변 밑 단에 서면 그 칸도 띠 밑에 덧붙은 것이다 —
    // 내림줄 · 오름줄이 그 자리로 지나면 띠 뒤 선이 흰 종이에 가려 끊기고 보이지 않는 선이 사슬 누름을 가로챈다(검토 2026-10-25).
    // 칸 층의 사슬 차례 셈([StripLayer.chainSlotOf])을 그대로 쓴다 — 사슬이 없거나 스위치 chain을 끄면 아무것도 더하지 않는다.
    final chained = row < c.layout.rowCount && c.layout.geo(row).chainTop >= 0 ? c.layout.geo(row) : null;
    final lensRank = c.layout.themeLens.isNotEmpty && c.layout.conditions.leaders;
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.cellCount; i++) {
        if (t.cellRow[i] != row) continue;
        final k = t.cellKindOf(i);
        if (k != CellKind.organ && k != CellKind.figure && k != CellKind.dep) {
          if (chained == null || StripLayer.chainSlotOf(chained, k, t.cellLane[i] & 0xff, lensRank: lensRank) < 0) continue;
          if (k == CellKind.common && CellStyle.bandOf(t.cellStyle[i]) != CellStyle.lensLeader) continue;
        }
        out.add((v.xOf(origin + t.cellX0[i]), v.xOf(origin + t.cellX1[i])));
      }
      for (final sec in const [FigureLook.secBar, HangLayer.sectionHang, HangLayer.sectionZone]) {
        final s = t.section(sec);
        if (s.count == 0) continue;
        final rows = s.u(Tile.itemRow), x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
        final look = sec == HangLayer.sectionHang ? s.u(Tile.itemB) : null;
        for (int i = 0; i < s.count; i++) {
          if (rows[i] != row || (look != null && look[i] == HangLook.link)) continue;
          out.add((v.xOf(origin + x0[i]), v.xOf(origin + x1[i])));
        }
      }
    }
    return out;
  }

  /// 줄 [row]에서 [xc] ± 10px 안에 사건(점 · 기간 막대 · 알약)이 있는가(js `_dropOK`의 사건 검사 — 띠 안으로 당겨진 점 · 기간 막대 자리).
  /// 다른 띠의 사건은 보지 않고, 제 띠([band] — 가로 [bandL] ~ [bandR])의 사건은 띠 끝 9px 안으로 당겨 본다(js `_placeRow`).
  bool _eventNear(PaintContext c, int row, double xc, int band, double bandL, double bandR) {
    final v = c.v;
    final lo = bandL + 9, hi = math.max(bandL + 9, bandR - 9);
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      final (e0, e1) = t.eventsIn(row, double.negativeInfinity, double.infinity);
      for (int i = e0; i < e1; i++) {
        final owner = t.eventBand[i];
        if (owner != 0 && owner != band) continue;
        var a = v.xOf(origin + t.eventX0[i]), b = v.xOf(origin + t.eventX1[i]);
        if (owner == band) {
          a = math.min(math.max(a, lo), hi);
          b = math.min(math.max(b, lo), hi);
        }
        if (a < xc + 10 && b > xc - 10) return true;
      }
      final (p0, p1) = t.pillsIn(row, double.negativeInfinity, double.infinity);
      for (int i = p0; i < p1; i++) {
        if (v.xOf(origin + t.pillX0[i]) < xc + 10 && v.xOf(origin + t.pillX1[i]) > xc - 10) return true;
      }
    }
    return false;
  }

  bool _dropOK(PaintContext c, int row, int dir, double xc, double? tabRight, int band, double bandL, double bandR) {
    // 두 장 꼬리표(명세 04 3-7 · 스위치 route · 조사 결함 12): 마름모 · 구멍은 맨 위 이름 색줄(윗변 + 7)에 있어 위로 나가는 획은 색줄 7px만 지난다 —
    // 칸 층(왕조 · 지위 · 지도자 · 내각 …)도 흰 사건 칸도 머리 이름(구멍 뒤에서 시작)도 가로지르지 않는다(웹 서고 갈래와 같은 뜻 · js:9668).
    // 예전에는 칸 층이 있는 줄과 '머리 이름 끝 > 구멍 − 6'(늘 참)에 막혀 오름줄 ┐이 서지 못하고 S자 되돌아감이 되었다. 조감은 띠 하나가 글줄이라 그대로 본다.
    // 받침 카드 위 상국 탭 · 연합 겹 탭이 설 수 있는 자리면 막는다([BandLayer.overTop] 2 — 카드 윗단만이면 관문이 카드 윗변까지 잇는다 · [_upGate] · 검증 지적).
    if (dir < 0 && PaintPick.route && !_bird) return (_bands?.overTop(c, band, row, xc, _doorH / 2 + 1) ?? 0) < 2;
    final g = c.layout.geo(row);
    if (dir > 0) {
      // 아래쪽 단(인물 · 예속 · 기관)과 띠 밑에 덧붙은 것은 그 줄에 있기만 하면 막던 것을 그 자리(xc ± 10px)에 실제로 있을 때만 막는다(js `_lowerBusy`) —
      // 예속 띠가 일찍 끝난 선대에서도 이미 있던 나라로 합류하게(2026-09-22 감독 '부분 승계도 간접 승계처럼 중간 합류').
      if ((g.figLevels > 0 || g.depHeight > 0 || g.organTop >= 0 || g.height - g.bandTop - g.bandHeight > 0) && _lowerBusy(c, row, xc)) return false;
    } else {
      if (g.dynastyTop >= 0 || g.phaseLanes > 0 || g.rankTop >= 0 || g.leaderTop >= 0 || g.cabinetTop >= 0) return false;
    }
    if (dir < 0 && tabRight != null && tabRight > xc - 6) return false;
    // 근처(± 10px)에 사건이 있으면 긋지 않는다 — 띠 위 층의 획이 사건 점 · 기간 막대를 가로지르지 않게(js와 같게 · 2026-09-22에 옮김).
    return !_eventNear(c, row, xc, band, bandL, bandR);
  }

  // ───────────────────────── 띠 위 조각 ─────────────────────────

  /// 관문: 선이 네모에서 제 띠의 테두리를 지나는 짧은 한 획 + 테두리의 문(명세 3-3절).
  void _gate(PaintContext c, double a, double b, double at, bool vertical, double border0, double border1, _LinkIn it, int edge, double dim) {
    final h = _doorH;
    final lo = math.min(border0, border1) - .5, hi = math.max(border0, border1) + .5;
    final lit = _lit(it, vertical ? at : (lo + hi) / 2, c);
    final alpha = lit ? 1.0 : dim;
    _top.add(vertical ? _Top.door(at - h / 2, lo, at + h / 2, hi, alpha) : _Top.door(lo, at - h / 2, hi, at + h / 2, alpha));
    final segAlpha = alpha * _segTop(it, _lift(it.from, it.to, c));
    final o = it.thin ? _crisp(at) : at, width = it.thin ? _thinW : LinkLook.width;
    for (final run in _beatRuns(a, b, it.beat)) {
      _top.add(vertical ? _Top.seg(o, run.$1, o, run.$2, edge, width, segAlpha) : _Top.seg(run.$1, o, run.$2, o, edge, width, segAlpha));
    }
  }

  /// 띠 위 조각(다리 · 관문)의 짙기 배율: 부분 승계는 .9 대신 [LinkLook.partialAlpha](.8)(css `.tl-link.is-partial .tl-seg:not(.is-join)` — 합류 조각 · 문은 그대로).
  /// 짙게([lift] 1)면 둘 다 1이다(`.tl-marks .tl-link:not(.is-hot, .is-selected, :hover)`가 풀림).
  static double _segTop(_LinkIn it, double lift) => _topK(it.thin ? LinkLook.partialAlpha / LinkLook.topAlpha : 1, lift);

  /// 띠 위 조각의 짙기 배율 — 그릴 때 [LinkLook.topAlpha](.9)를 곱하므로 평소 배율 [base]를 [lift]만큼 `1 / .9`(곱하면 1)로 올린다.
  static double _topK(double base, double lift) => base + (1 / LinkLook.topAlpha - base) * lift;

  /// 다리: 같은 줄에서 곧바로 이어지는 두 네모 사이(명세 3-4절). 이음매 한가운데를 기준으로 왼쪽은 선대 · 오른쪽은 후대의 테두리색.
  void _bridge(PaintContext c, double qe, double pf, double xa, double xb, double y, _LinkIn it, int qEdge, int pEdge, double dim) {
    final h = _doorH;
    final mid = (qe + pf) / 2;
    final lit = _lit(it, mid, c);
    final alpha = lit ? 1.0 : dim;
    if (pf - qe < .5) {
      _top.add(_Top.door(qe - 1.5, y - h / 2, pf + 1.5, y + h / 2, alpha)); // 맞닿으면 두 테두리를 한 문으로
    } else {
      _top.add(_Top.door(qe - 1.5, y - h / 2, qe + .5, y + h / 2, alpha));
      _top.add(_Top.door(pf - .5, y - h / 2, pf + 1.5, y + h / 2, alpha));
    }
    final beat = it.beat;
    final runs = beat == null
        ? [(xa, mid), (mid, xb)]
        : [..._beatRuns(mid - beat[1] / 2, xa, beat), ..._beatRuns(mid + beat[1] / 2, xb, beat)];
    final lift = _lift(it.from, it.to, c);
    final segAlpha = alpha * _segTop(it, lift);
    final sy = it.thin ? _crisp(y) : y, width = it.thin ? _thinW : LinkLook.width;
    for (final run in runs) {
      final lo = math.min(run.$1, run.$2), hi = math.max(run.$1, run.$2);
      if (hi - lo <= .05) continue;
      _top.add(_Top.seg(lo, sy, hi, sy, hi <= mid + 1e-6 ? qEdge : pEdge, width, segAlpha));
    }
    if (it.kind == _LinkIn.revival) _top.add(_Top.ring(mid, y, qEdge, alpha * _topK(1, lift)));
  }

  /// 이음매 눈금(명세 04 3-4 · 조사 결함 9 — 동아시아 진 · 신 · 호 → 명 지배기): 다리([_bridge])를 못 세우는 이음매 쌍(좁은 띠라 마름모 · 구멍이 꺼짐)에
  /// 다리와 같은 문(맞닿으면 한 문 · 벌어졌으면 두 테에 하나씩)과 띠 위 토막 `qe − 3 … pf + 3`(가운데 왼쪽은 선대 · 오른쪽은 후대의 테 빛깔 · 점선 종류도 한 획 ·
  /// 조감은 [BirdLook.stub])을 둔다. 고리 · 관문은 없다. 두 띠가 다 토막 둘 몫(6px) 이상이고 이음매 가운데가 화면 안일 때만 — 세웠으면 참.
  bool _seamTick(PaintContext c, _Square? q, _Square? p, double qe, double pf, double y, _LinkIn it, int qEdge, int pEdge, double dim) {
    if (q == null || p == null || it.unknownQ || it.unknownP) return false;
    final stub = _bird ? BirdLook.stub : TunnelLook.tick;
    if (qe - q.bandStart < 2 * stub || p.bandEnd - pf < 2 * stub) return false;
    final mid = (qe + pf) / 2;
    if (mid < c.left || mid > c.w) return false;
    final h = _doorH;
    final alpha = _lit(it, mid, c) ? 1.0 : dim;
    final xa = qe - stub;
    // 합류 점(0.1.1 · 조사 결함 43 — 동아시아 남송 → 명의 이음매 눈금과 원 → 명의 끝 가로가 명 구멍 앞 토막을 함께 썼다): 같은 구멍에 옆으로 먼저 든 선이
    // 이 토막 안(선대 끝 − 3 ~ 후대 시작)에서 꺾어 들었으면 그 꺾는 자리에서 멎고 그 자리에 제 색 점(지름 3)을 찍는다 — 후대 쪽 문 · 토막은 두지 않는다(구멍 문은 먼저 든 선의 것).
    // 먼저 든 선이 없으면 이 토막을 적어 두어 뒤에 드는 선이 토막에 닿는 곳에서 멎는다([_mergeSide]). 맞닿은 이음매(한 문)는 자를 자리가 없어 그대로.
    var cut = double.infinity;
    if (pf - qe >= .5) {
      final had = _holeSide[p.band];
      if (had == null) {
        _holeSide[p.band] = (xa, y, false);
      } else if (had.$3 && (had.$2 - y).abs() <= .5 && had.$1 > xa + .5 && had.$1 < pf - .5) {
        cut = had.$1;
      }
    }
    if (pf - qe < .5) {
      _top.add(_Top.door(qe - 1.5, y - h / 2, pf + 1.5, y + h / 2, alpha));
    } else {
      _top.add(_Top.door(qe - 1.5, y - h / 2, qe + .5, y + h / 2, alpha));
      if (cut.isInfinite) _top.add(_Top.door(pf - .5, y - h / 2, pf + 1.5, y + h / 2, alpha));
    }
    final segAlpha = alpha * _segTop(it, _lift(it.from, it.to, c));
    final sy = it.thin ? _crisp(y) : y, width = it.thin ? _thinW : LinkLook.width;
    final xb = math.min(pf + stub, cut);
    _top.add(_Top.seg(xa, sy, math.min(mid, xb), sy, qEdge, width, segAlpha));
    if (xb > mid) _top.add(_Top.seg(mid, sy, xb, sy, pEdge, width, segAlpha));
    if (cut.isFinite) _back.add(_Back.dot(cut, y, cut <= mid ? qEdge : pEdge, segAlpha));
    _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, [ui.Offset(xa, y), ui.Offset(xb, y)]));
    c.debug?.note('이음매눈금', '${it.from}→${it.to} ${_n(xa)},${_n(sy)},${_n(xb)}${cut.isFinite ? ' 합류' : ''}');
    return true;
  }

  /// 점선 박자 [beat]로 from → to를 채운 칠 구간 — 칠을 늘이거나 줄여 양 끝이 늘 칠로 끝난다(명세 4-2절).
  static List<(double, double)> beatRuns(double from, double to, List<double>? beat) {
    final len = (to - from).abs();
    if (len < .5) return const [];
    if (beat == null) return [(math.min(from, to), math.max(from, to))];
    final on = beat[0], off = beat[1];
    final n = math.max(1, ((len + off) / (on + off)).round());
    final d = (len - off * (n - 1)) / n;
    final dir = to >= from ? 1.0 : -1.0;
    final out = <(double, double)>[];
    for (int i = 0; i < n; i++) {
      final a = from + dir * i * (d + off), b = a + dir * d;
      out.add((math.min(a, b), math.max(a, b)));
    }
    return out;
  }

  static List<(double, double)> _beatRuns(double from, double to, List<double>? beat) => beatRuns(from, to, beat);

  // ───────────────────────── 굴 문 (이어 주는 선 걸음 5 — 명세 04 3-9) ─────────────────────────

  /// 방금 세운 띠 뒤 꺾은선([b0]부터 — 승계 · 소속 · 옮겨 앉기)의 두 끝 띠를 적는다(굴 문 훑기가 그 둘은 건너뛴다).
  void _own(int from, int to, int b0) {
    for (int i = b0; i < _back.length; i++) {
      final k = _back[i].kind;
      if (k == _Back.kLink || k == _Back.kPart) _ends[i] = (from, to);
    }
  }

  /// 이번 장면의 띠 몸통(선 감사 8-6 · 굴 문 3-9가 함께 쓴다): 네모(구역 20)가 실린 띠마다 가로 = 띠의 제 두 끝(사라지는 꼬리 뺌) ·
  /// 세로 = 띠 윗변 ~ 몸통 아랫변([BandLayer.bodyBottomOf] · 조감은 띠 아랫변). 줄마다 왼쪽 끝 차례.
  List<AuditBody> _bodiesOf(PaintContext c) {
    final cached = _bodyCache;
    if (cached != null) return cached;
    final layout = c.layout, v = c.v;
    final bodies = <AuditBody>[];
    for (final e in _rowSquares.entries) {
      final row = e.key, geo = layout.geo(row), rowTop = layout.rowTop(row);
      final top = v.yOf(rowTop + geo.bandTop);
      for (final sq in e.value) {
        final bottom = layout.bird || _bands == null ? geo.bandTop + geo.bandHeight : _bands!.bodyBottomOf(layout, row, sq.band);
        bodies.add(AuditBody(sq.band, row, ui.Rect.fromLTRB(sq.bandStart, top, sq.bandEnd, v.yOf(rowTop + bottom))));
      }
    }
    return _bodyCache = bodies;
  }

  /// 굴 문 훑기(명세 04 3-9): 모든 선을 정한 뒤 따로 한 번 — 띠 뒤 꺾은선(승계 · 소속 · 옮겨 앉기)의 곧은 토막마다, 두 끝 띠가 아닌 다른 띠의 몸통
  /// ([_bodiesOf])을 지나면 그 띠의 테를 지나는 곳마다 굴 문을 둔다: 종이색 문(선을 가로질러 문 높이 · 테를 따라 3 — 테 1px과 안팎 1px씩)과
  /// 문에서 띠 안쪽 2px까지의 띠 위 토막(선의 색 · 굵기 그대로). 세로 획은 위 · 아래 테, 가로 획은 왼 · 오른 테다.
  /// 몸통 아랫변을 지나는 세로 획은 그 줄에 꼬리표 밑 흰 사슬이 있으면 사슬 단 밑에도 문을 하나 더 둔다(꼬리 내림 관문 `_tailGate`와 같은 까닭).
  /// 두지 않는 때: 몸통 안에서 2px 안에 끝나는 획 · 테가 화면 밖인 쪽 · 두 끝 띠. 흐린 띠(밝기 < 1)에도 둔다 — 감독 결정 '맨 아래 한 번 긋고 위에 얹기'로
  /// 흐린 띠 칠도 그 자리 바탕과 섞은 불투명 종이라 뒤가 비치지 않는다(예전에는 비친다고 건너뛰어, 고르기 장면의 짙은 선이 흐린 띠 뒤에서 표시 없이 끊겼다 —
  /// 4단계 마지막 합치기 검토 지적). 같은 줄 곧은 선도 route면 흐린 띠에서 끊지 않아([_cutBehindDim]은 끈 길만) 문이 선다.
  /// 스위치 cross(1배 후보 · 기본 끔)면 문 대신 가려진 몫 전체를 띠 위에 옅은 토막(짙기 [TunnelLook.crossAlpha] + 1px 종이 테 — '건넘 토막')으로 긋는다.
  /// 셈: 줄마다 세로 범위를 한 번 모아 획이 지나지 않는 줄은 건너뛴다(선 수 × 토막 수 × 지나는 줄의 띠 수).
  void _tunnels(PaintContext c) {
    if (_ends.isEmpty) return;
    final layout = c.layout, v = c.v;
    final rows = <(int, double, double, List<AuditBody>)>[]; // 줄 · 위 · 아래(사슬 단까지) · 몸통들
    {
      List<AuditBody>? list;
      var row = -1;
      for (final b in _bodiesOf(c)) {
        if (b.row != row) {
          row = b.row;
          final geo = layout.geo(row), top = layout.rowTop(row);
          final low = v.yOf(top + geo.bandTop + geo.bandHeight + (geo.chainTop >= 0 ? geo.chainDepth : 0));
          rows.add((row, b.rect.top, low, list = []));
        }
        list!.add(b);
      }
    }
    final cross = PaintPick.cross;
    for (final MapEntry(key: i, value: (from, to)) in _ends.entries) {
      final b = _back[i];
      final part = b.kind == _Back.kPart;
      final width = part ? TunnelLook.partW : b.width;
      final crisp = !part && b.width < LinkLook.width && _thinCrisp;
      final rgb = b.color & 0xffffff, alpha = b.alpha * (((b.color >> 24) & 0xff) / 255);
      final beat = part ? const [LinkLook.partDash, LinkLook.partGap] : b.beat;
      var px = 0.0;
      Set<int>? doored;
      void stub(bool vertical, double at, double a, double z) {
        _top.add(vertical ? _Top.seg(at, a, at, z, rgb, width, alpha) : _Top.seg(a, at, z, at, rgb, width, alpha));
        px += z - a;
      }

      // 테 [edge]에 굴 문 하나: [inward]는 띠 안쪽 방향(+1 아래 · 오른쪽, −1 위 · 왼쪽) — 테 px는 inward > 0이면 [edge, edge + 1], 아니면 [edge − 1, edge].
      void door(bool vertical, double at, double edge, int inward) {
        final a = inward > 0 ? edge - 1 : edge - 2, z = a + TunnelLook.depth; // 테 1px과 안팎 1px씩
        final h = _doorH / 2;
        _top.add(vertical ? _Top.door(at - h, a, at + h, z, b.alpha) : _Top.door(a, at - h, z, at + h, b.alpha));
        if (inward > 0) {
          stub(vertical, at, a, z + TunnelLook.stub);
        } else {
          stub(vertical, at, a - TunnelLook.stub, z);
        }
      }

      final pts = b.pts;
      for (int k = 1; k < pts.length; k++) {
        var p0 = pts[k - 1], p1 = pts[k];
        if (crisp) {
          p0 = ui.Offset(_crisp(p0.dx), _crisp(p0.dy));
          p1 = ui.Offset(_crisp(p1.dx), _crisp(p1.dy));
        }
        final horizontal = (p0.dy - p1.dy).abs() < 1e-6;
        if (!horizontal && (p0.dx - p1.dx).abs() >= 1e-6) continue;
        final at = horizontal ? p0.dy : p0.dx;
        final lo = horizontal ? math.min(p0.dx, p1.dx) : math.min(p0.dy, p1.dy);
        final hi = horizontal ? math.max(p0.dx, p1.dx) : math.max(p0.dy, p1.dy);
        if (hi - lo < TunnelLook.minRun) continue;
        if (horizontal ? (at < c.head - 4 || at > c.h + 4) : (at < c.left - 4 || at > c.w + 4)) continue;
        for (final (row, rowTop, rowLow, bodies) in rows) {
          if (horizontal ? (at <= rowTop || at >= rowLow) : (hi <= rowTop || lo >= rowLow)) continue;
          for (final o in bodies) {
            if (o.band == from || o.band == to) continue;
            final r = o.rect;
            if (horizontal ? (at <= r.top || at >= r.bottom) : (at <= r.left || at >= r.right)) continue;
            final s = math.max(lo, horizontal ? r.left : r.top), e = math.min(hi, horizontal ? r.right : r.bottom);
            if (e - s < TunnelLook.minRun) continue; // 몸통 안에서 2px 안에 끝나는 획
            // 세로 획이 몸통 아랫변을 지나 사슬 단 밑까지 가면 사슬 아랫변도 테로 본다.
            double? chain;
            if (!horizontal && !_bird && hi > r.bottom + .5) {
              final geo = layout.geo(row);
              if (geo.chainTop >= 0) {
                final y = v.yOf(layout.rowTop(row) + geo.bandTop + geo.bandHeight + geo.chainDepth - (_bands?.eventLiftOf(layout, row, o.band) ?? 0));
                if (y > r.bottom + .5 && hi > y + .5) chain = y;
              }
            }
            final (a0, a1, l0, l1) = horizontal ? (r.left, r.right, c.left, c.w) : (r.top, r.bottom, c.head, c.h);
            var any = false;
            if (cross) {
              // 건넘 토막: 가려진 몫 전체를 종이 테(양쪽 1px) 위에 옅게. 종이 테가 불투명하면(짙기 1) 옅은 획은 그 종이와 미리 섞은 불투명 색으로
              // (감독 결정 '맨 아래 한 번 긋고 위에 얹기' — 획은 종이 테 안에만 서므로 보이는 색은 같다). 흐린 선(짙기 < 1)은 종이 테도 비쳐 그대로 옅게.
              final z = chain ?? e, half = width / 2 + 1;
              if (z - s >= TunnelLook.minRun) {
                _top.add(horizontal ? _Top.door(s, at - half, z, at + half, b.alpha) : _Top.door(at - half, s, at + half, z, b.alpha));
                final paperUnder = b.alpha >= 1;
                final segRgb = paperUnder ? over(withAlpha(0xff000000 | rgb, LinkLook.topAlpha * alpha * TunnelLook.crossAlpha), Look.paper) & 0xffffff : rgb;
                final segAlpha = paperUnder ? 1 / LinkLook.topAlpha : alpha * TunnelLook.crossAlpha;
                for (final run in _beatRuns(s, z, beat)) {
                  _top.add(horizontal
                      ? _Top.seg(run.$1, at, run.$2, at, segRgb, width, segAlpha)
                      : _Top.seg(at, run.$1, at, run.$2, segRgb, width, segAlpha));
                  px += run.$2 - run.$1;
                }
                any = true;
              }
            } else {
              if (lo < a0 - .5 && a0 >= l0 - .5 && a0 <= l1 + .5) {
                door(!horizontal, at, a0, 1);
                any = true;
              }
              if (hi > a1 + .5 && a1 >= l0 - .5 && a1 <= l1 + .5) {
                door(!horizontal, at, a1, -1);
                any = true;
              }
              if (chain != null && chain >= l0 - .5 && chain <= l1 + .5) {
                door(true, at, chain, -1);
                any = true;
              }
            }
            if (!any) continue;
            (doored ??= <int>{}).add(o.band);
            c.debug?.note('굴문', '${o.band} ${horizontal ? '가로' : '세로'} ${_n(at)} ${_n(s)}~${_n(chain ?? e)}${cross ? ' 건넘' : ''}');
          }
        }
      }
      if (doored != null) {
        _tunnelBands[i] = doored;
        _tunnelPx[i] = px;
      }
    }
  }

  // ───────────────────────── 선 감사 (이어 주는 선 걸음 1) ─────────────────────────

  /// 방금 세운 선 하나를 감사 목록에 적는다 — 띠 뒤 꺾은선이 [b0]부터, 띠 위 조각이 [t0]부터 이번에 더해진 것.
  /// [extra]는 이 선이 남과 함께 쓰는 띠 위 조각의 차례 범위(같은 줄기의 꼬리 관문 — [_shareSpans]).
  void _audited(LineAuditKind kind, int from, int to, int b0, int t0, [List<(int, int)> extra = const []]) {
    for (int i = b0; i < _back.length; i++) {
      final b = _back[i];
      if (b.kind != _Back.kLink && b.kind != _Back.kPart) continue;
      _audit.add(_AuditEntry(kind, from, to, i, t0, _top.length, extra));
      return;
    }
    if (_top.length > t0) _audit.add(_AuditEntry(kind, from, to, -1, t0, _top.length, extra)); // 띠 뒤 선 없이 띠 위 조각만(다리)
  }

  /// 승계선 한 건을 적는다. 아무것도 세우지 못했는데 두 끝 줄이 펴져 있고 선의 자리가 화면에 걸치면 '빠진 선'으로 센다
  /// (접힌 줄에 닿는 선은 긋지 않는 것이 규칙이라 빼고 — 명세 04 3-1).
  void _auditLink(PaintContext c, _LinkIn l, int b0, int t0) {
    if (_back.length > b0 || _top.length > t0) {
      _audited(LineAuditKind.succession, l.from, l.to, b0, t0, _shareSpans.isEmpty ? const [] : List.of(_shareSpans));
      return;
    }
    // 선대 끝이 화면 밖이라 후대 쪽 꼬리표로 든 선(같은 구멍의 짧은 선은 첫 선대가 긋는다)은 빠진 선이 아니다.
    if (_lateIns[l.to]?.partners.any((p) => p.band == l.from) ?? false) return;
    final layout = c.layout, v = c.v;
    final qRow = l.down ? l.row : l.row2, pRow = l.down ? l.row2 : l.row;
    if (qRow >= layout.rowCount || pRow >= layout.rowCount || !layout.hasBody(qRow) || !layout.hasBody(pRow)) return;
    final xa = v.xOf(l.start), xb = v.xOf(l.end);
    if (xb < c.left || xa > c.w) return;
    final ya = _anchorY(c, qRow), yb = _anchorY(c, pRow);
    if (math.max(ya, yb) < c.head || math.min(ya, yb) > c.h) return;
    _auditMissed.add('${l.from}→${l.to} 줄 $qRow→$pRow ${_n(xa)}~${_n(xb)}${qRow == pRow ? ' 같은 줄' : ''}');
  }

  /// 이번 장면의 감사: 띠 몸통(윗변 ~ [BandLayer.bodyBottomOf])을 모아 [auditLines]에 넘기고 결과를 기록 · 찍기에 남긴다.
  void _runAudit(PaintContext c) {
    final bodies = _bodiesOf(c);
    final screen = ui.Rect.fromLTRB(c.left, c.head, c.w, c.h);
    final lines = <AuditLine>[];
    for (final a in _audit) {
      var topPx = 0.0;
      for (final (t0, t1) in [(a.t0, a.t1), ...a.extra]) {
        for (int i = t0; i < t1; i++) {
          final p = _top[i];
          if (p.kind == _Top.kDoor) continue;
          final r = ui.Rect.fromLTRB(math.min(p.x1, p.x2), math.min(p.y1, p.y2), math.max(p.x1, p.x2), math.max(p.y1, p.y2));
          if (!r.inflate(1).overlaps(screen)) continue;
          topPx += p.kind == _Top.kSeg ? math.max(r.width, r.height) : math.max(1.0, math.max(r.width, r.height));
        }
      }
      // 굴 문(3-9)은 모든 선을 정한 뒤 따로 놓으므로 띠 위 조각의 차례 범위 밖이다 — 그 토막 길이와 문을 둔 띠를 따로 더한다.
      lines.add(AuditLine(a.kind, a.from, a.to, a.back < 0 ? const [] : _back[a.back].pts,
          topPx: topPx + (_tunnelPx[a.back] ?? 0), doors: _tunnelBands[a.back] ?? const {}));
    }
    final r = auditLines(lines, bodies, screen, missed: _auditMissed, nameOf: (band) => _squares[band]?.name ?? '');
    LineAudit.last = r;
    final debug = c.debug;
    if (debug == null) return;
    debug.note('선감사', r.summary);
    for (final s in r.detail) {
      debug.note('선감사-선', s);
    }
    for (final s in r.missed) {
      debug.note('선감사-빠짐', s);
    }
  }

  /// 선 감사의 셈(순수 — 검사에서 가짜 장면으로 부른다). 띠 뒤 꺾은선의 곧은 토막마다 화면 안 길이를 재고, 두 끝 띠가 아닌 다른 띠의
  /// 몸통 상자 **안쪽**을 지나는 길이를 띠마다 모은다(겹친 구간은 한 번만). 굴 문([AuditLine.doors] — 걸음 5)이 있는 띠의 몫은 '표시 있음'으로 따로.
  /// 보이는 px = 화면 안 길이 − 어느 띠 몸통이든(두 끝 띠 포함) 뒤에 든 길이 + 띠 위 조각(관문 · 다리 · 합류 조각)의 길이 — 0이면 '안 보이는 선'.
  /// 굽이는 꺾인 점으로 본다(반지름 5 ~ 6의 굽이가 띠 안에서 꺾이는 일은 셈에서 1px 안팎). [nameOf]가 있으면 내역에 띠 이름을 붙인다.
  @visibleForTesting
  static LineAudit auditLines(List<AuditLine> lines, List<AuditBody> bodies, ui.Rect screen, {List<String> missed = const [], String Function(int band)? nameOf}) {
    String named(int band) {
      final name = band == 0 || nameOf == null ? '' : nameOf(band);
      return name.isEmpty ? '$band' : '$name($band)';
    }

    var hidden = 0.0, marked = 0.0;
    var invisible = 0, back6 = 0;
    final kinds = <LineAuditKind, List<double>>{}; // 종류 → [선 수, 숨은 px, 안 보임]
    final detail = <(double, String)>[];
    for (final line in lines) {
      final k = kinds[line.kind] ??= [0, 0, 0];
      k[0]++;
      if (line.kind == LineAuditKind.succession && line.pts.length == 6) back6++;
      var onScreen = 0.0, covered = 0.0;
      final byBand = <int, double>{};
      for (int i = 1; i < line.pts.length; i++) {
        final a = line.pts[i - 1], b = line.pts[i];
        final horizontal = (a.dy - b.dy).abs() < 1e-6;
        final at = horizontal ? a.dy : a.dx;
        if (horizontal ? (at < screen.top || at > screen.bottom) : (at < screen.left || at > screen.right)) continue;
        final lo = math.max(math.min(horizontal ? a.dx : a.dy, horizontal ? b.dx : b.dy), horizontal ? screen.left : screen.top);
        final hi = math.min(math.max(horizontal ? a.dx : a.dy, horizontal ? b.dx : b.dy), horizontal ? screen.right : screen.bottom);
        if (hi - lo <= 1e-6) continue;
        onScreen += hi - lo;
        final all = <(double, double)>[], others = <int, List<(double, double)>>{};
        for (final body in bodies) {
          final r = body.rect;
          final inside = horizontal ? (at > r.top && at < r.bottom) : (at > r.left && at < r.right);
          if (!inside) continue;
          final s = math.max(lo, horizontal ? r.left : r.top), e = math.min(hi, horizontal ? r.right : r.bottom);
          if (e - s <= 1e-6) continue;
          all.add((s, e));
          if (body.band != line.from && body.band != line.to) (others[body.band] ??= []).add((s, e));
        }
        covered += _unionLength(all);
        final mixed = <(double, double)>[], doored = <(double, double)>[];
        for (final o in others.entries) {
          byBand[o.key] = (byBand[o.key] ?? 0) + _unionLength(o.value);
          (line.doors.contains(o.key) ? doored : mixed).addAll(o.value);
        }
        final h = _unionLength(mixed);
        hidden += h;
        k[1] += h;
        marked += _unionLength(doored);
      }
      final visible = onScreen - covered + line.topPx;
      if (onScreen + line.topPx > 0 && visible < .5) {
        invisible++;
        k[2]++;
      }
      final behind = byBand.entries.where((e) => !line.doors.contains(e.key) && e.value >= .5).toList()..sort((x, y) => y.value.compareTo(x.value));
      final sum = behind.fold(0.0, (s, e) => s + e.value);
      if (behind.isNotEmpty || (onScreen + line.topPx > 0 && visible < .5)) {
        detail.add((
          sum,
          '${line.kind.label} ${named(line.from)}→${named(line.to)} 숨은 ${sum.round()}px${visible < .5 ? ' 안 보임' : ''}${line.pts.length == 6 ? ' S길' : ''}'
              '${behind.map((e) => ' · 띠 ${named(e.key)} ${e.value.round()}').join()}',
        ));
      }
    }
    detail.sort((x, y) => y.$1.compareTo(x.$1));
    return LineAudit(
      lines: lines.length, hiddenPx: hidden, markedPx: marked, invisible: invisible, missing: missed.length, backPaths: back6,
      kinds: {for (final e in kinds.entries) e.key: (e.value[0].round(), e.value[1], e.value[2].round())},
      detail: [for (final d in detail) d.$2], missed: List.of(missed),
    );
  }

  /// 구간 목록의 합집합 길이.
  static double _unionLength(List<(double, double)> spans) {
    if (spans.isEmpty) return 0;
    if (spans.length == 1) return spans.first.$2 - spans.first.$1;
    final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0.0, s = sorted.first.$1, e = sorted.first.$2;
    for (final x in sorted.skip(1)) {
      if (x.$1 > e) {
        total += e - s;
        s = x.$1;
        e = x.$2;
      } else if (x.$2 > e) {
        e = x.$2;
      }
    }
    return total + e - s;
  }

  // ───────────────────────── 짝 꼬리표 (구역 60 · 이어 주는 선 걸음 4) ─────────────────────────

  /// 트랙을 건너는 승계의 짝 꼬리표(감독 결정 (2) 2026-10-25 · 명세 04 3-1 · 3-10 · 8-3): 긴 선 대신 두 끝 띠에 작은 글 —
  /// 앞 나라 띠 끝에 `→ ●뒤 나라`, 뒤 나라 띠 시작에 `●앞 나라 →`(한 끝에 여럿이면 ' · '로 잇고, ●은 상대 띠 테 빛깔의 점).
  /// 자리 사다리(먼저 맞는 것 — [CrossTagLook]): ① 띠 밖 틈(앞 끝은 오른쪽 · 뒤 끝은 왼쪽 — 이웃 띠 · 선 · 앞서 놓인 꼬리표를 비킴) →
  /// ② 이름 색줄 안(앞 끝은 꼬리 마름모 앞 · 뒤 끝은 머리 이름 뒤 — 머리 글 구간과 띠 위 조각을 비킴 · 조감은 없음) →
  /// ③ '→' 한 글자(①의 자리, 없으면 ②의 자리 — 올리면 풍선 글로 다 보인다). 다 막히면 두지 않는다.
  /// 메뉴 '숨기기'면 없고 '직접 승계만'이면 c(종류)가 직접인 것만. 그 끝(앞 끝은 띠 끝 · 뒤 끝은 띠 시작)이 화면 밖이면 두지 않는다.
  /// 띠 · 선 · 이름 · 사건은 하나도 옮기지 않는다 — 옛 저장소(구역 60 없음)는 지금 그림 그대로다.
  void _planCross(PaintContext c) {
    if (successionMode == 2) return;
    final ends = <int, _CrossEnd>{};
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      _readItems(t, secCross, seen, (i, s, origin) {
        final kind = s.u(Tile.itemC)[i];
        if (successionMode == 1 && kind != 0) return;
        final band = s.u(Tile.itemRef)[i], back = s.u(Tile.itemA)[i] & 1 == 1, to = s.u(Tile.itemB)[i];
        final uid = t.text(s.u(Tile.itemText2)[i]);
        final e = ends[band * 2 + (back ? 1 : 0)] ??= _CrossEnd(band, s.u(Tile.itemRow)[i], back);
        if (e.partners.any((p) => p.band == to && p.uid == uid)) return;
        e.partners.add(_CrossPartner(s.u(Tile.itemId)[i], to, uid, t.text(s.u(Tile.itemName)[i]), s.u(Tile.itemColor)[i], kind));
      });
    }
    // 선대 끝이 화면 밖인 승계선의 후대 쪽 끝([_lateIns]) — 같은 띠 시작의 구역 60 꼬리표와는 따로 한 꼬리표(화살이 앞에 선다).
    for (final e in _lateIns.values) {
      ends[-1 - e.band] = e;
    }
    if (ends.isEmpty) return;
    // 줄 → x 차례로 놓는다 — 같은 틈을 나눠 쓰는 두 꼬리표(앞 띠의 앞 끝 · 뒤 띠의 뒤 끝)는 뒤에 놓는 것이 비킨다.
    final order = [
      for (final e in ends.values)
        if (_squares[e.band] case final sq?) (e, sq),
    ]..sort((a, b) => a.$1.row != b.$1.row ? a.$1.row.compareTo(b.$1.row) : (a.$1.back ? a.$2.bandStart : a.$2.bandEnd).compareTo(b.$1.back ? b.$2.bandStart : b.$2.bandEnd));
    final placed = <int, List<(double, double)>>{};
    final arrowLook = TextLook(CrossTagLook.size, ui.FontWeight.w600, CrossTagLook.arrowInk);
    for (final (e, sq) in order) {
      if (sq.y < c.head - 8 || sq.y > c.h + 8) continue;
      final edge = e.back ? sq.bandStart : sq.bandEnd;
      if (edge < c.left - .5 || edge > c.w + .5) continue;
      e.partners.sort((a, b) => a.id.compareTo(b.id));
      final arrowText = e.late ? CrossTagLook.from : CrossTagLook.arrow;
      final aw = c.text.widthOf(arrowText, arrowLook), sw = c.text.widthOf(CrossTagLook.sep, arrowLook);
      final names = [for (final p in e.partners) c.text.widthOf(p.name, CrossTagLook.nameLook(p.color))];
      if (aw == null || sw == null || names.contains(null)) {
        c.scene.requestFrame(); // 글자 폭을 아직 잴 수 없다 — 다음 장면에
        continue;
      }
      var full = aw + CrossTagLook.arrowGap + (e.partners.length - 1) * sw;
      for (final w in names) {
        full += CrossTagLook.dot + CrossTagLook.dotGap + w!;
      }
      final half = CrossTagLook.size * .6;
      final top = sq.y - half, bottom = sq.y + half;
      final mine = placed[e.row] ??= [];
      final outside = [..._lineSpans(top, bottom, back: true), ...mine];
      final inside = [..._lineSpans(top, bottom, back: false), ...mine, ...?_bands?.headNameZones[e.row]];
      // ① 띠 밖 틈 · ② 이름 색줄 안 — 둘 다 막히면 ③ '→' 한 글자를 같은 차례로.
      var mode = 1;
      var x = _crossOutside(c, e, sq, full, outside);
      if (x == null && !_bird) {
        mode = 2;
        x = _crossInside(c, e, sq, full, inside);
      }
      if (x == null) {
        mode = 3;
        x = _crossOutside(c, e, sq, aw, outside) ?? (_bird ? null : _crossInside(c, e, sq, aw, inside));
      }
      if (x == null) {
        c.debug?.note('짝꼬리표-없음', '${e.band} ${e.back ? '뒤' : '앞'} ${e.partners.map((p) => p.name).join(' · ')}');
        continue;
      }
      final tag = _CrossTag(e, mode, x, sq.y, sq.name);
      if (mode == 3) {
        tag.pieces.add(_CrossPiece(arrowText, x, aw, 0));
      } else {
        var at = x;
        void arrow(int partner) {
          tag.pieces.add(_CrossPiece(arrowText, at, aw, partner));
          at += aw;
        }

        // 화살은 흐름 쪽에: 앞 끝 `→ ●뒤 나라` · 뒤 끝 `●앞 나라 →` · 선대 끝이 화면 밖인 후대 쪽 끝 `← ●앞 나라`(앞 나라는 화면 오른쪽 밖).
        if (!e.back || e.late) {
          arrow(0);
          at += CrossTagLook.arrowGap;
        }
        for (int i = 0; i < e.partners.length; i++) {
          if (i > 0) {
            tag.pieces.add(_CrossPiece(CrossTagLook.sep, at, sw, -1));
            at += sw;
          }
          tag.pieces.add(_CrossPiece(null, at, CrossTagLook.dot, i));
          at += CrossTagLook.dot + CrossTagLook.dotGap;
          tag.pieces.add(_CrossPiece(e.partners[i].name, at, names[i]!, i));
          at += names[i]!;
        }
        if (e.back && !e.late) {
          at += CrossTagLook.arrowGap;
          arrow(e.partners.length - 1);
        }
      }
      final right = x + (mode == 3 ? aw : full);
      tag.right = right;
      _crossTags.add(tag);
      _tagBoxes.add(ui.Rect.fromLTRB(x, top, right, bottom));
      mine.add((x, right));
      _crossZone(c, e.row, x, right, top, bottom);
      c.debug?.note('짝꼬리표', '${e.band} ${e.back ? '뒤' : '앞'} 갈래$mode ${_n(x)},${_n(sq.y)},${_n(right - x)} ${_crossText(e)}');
    }
  }

  /// ① 띠 밖 틈: 앞 끝은 띠 바깥 끝(사라지는 꼬리까지) + 4에서 오른쪽으로, 뒤 끝은 띠 바깥 시작 − 4에서 왼쪽으로 —
  /// 같은 줄의 이웃 띠(3px 앞) · 화면 끝 안에 다 들어야 하고, 선 · 앞서 놓인 꼬리표를 비켜 [CrossTagLook.drift]까지만 밀린다.
  double? _crossOutside(PaintContext c, _CrossEnd e, _Square sq, double w, List<(double, double)> busy) {
    final list = _rowSquares[e.row] ?? const <_Square>[];
    if (!e.back) {
      var limit = c.w - 2;
      for (final o in list) {
        if (o.band != sq.band && o.x1 >= sq.x2 - .5) {
          limit = math.min(limit, o.x1 - CrossTagLook.clear);
          break;
        }
      }
      final x = _slide(sq.x2 + CrossTagLook.outGap, w, 1, busy, CrossTagLook.drift);
      return x != null && x + w <= limit && x >= c.left + 2 ? x : null;
    }
    var floor = c.left + 2;
    for (final o in list) {
      if (o.band != sq.band && o.x2 <= sq.x1 + .5) floor = math.max(floor, o.x2 + CrossTagLook.clear);
    }
    final x = _slide(sq.x1 - CrossTagLook.outGap - w, w, -1, busy, CrossTagLook.drift);
    return x != null && x >= floor && x + w <= c.w - 2 ? x : null;
  }

  /// ② 이름 색줄 안: 앞 끝은 꼬리 마름모 앞 3(마름모가 없으면 띠 끝 − 4)에 오른쪽을 맞추고, 뒤 끝은 구멍 뒤에서 머리 글(이름 · 출처 글 · 실권 이름)을
  /// 비켜 그 뒤에 선다. 구멍 · 마름모 사이에 다 들어야 한다. 미정인 끝(사라지는 꼬리)에는 색줄이 옅어 두지 않는다.
  double? _crossInside(PaintContext c, _CrossEnd e, _Square sq, double w, List<(double, double)> busy) {
    final lo = math.max(sq.fc + TagLook.holeR + CrossTagLook.inGap, c.left + 2);
    final diamond = sq.showE && _outs.contains(sq.band);
    final hi = math.min(diamond ? sq.ec - TagLook.diamondHalf - CrossTagLook.inGap : sq.bandEnd - TagLook.diamondX + TagLook.diamondHalf, c.w - 2);
    if (!e.back) {
      if (sq.unknownEnd) return null;
      final x = _slide(hi - w, w, -1, busy, double.infinity);
      return x != null && x >= lo ? x : null;
    }
    if (sq.unknownStart) return null;
    final x = _slide(lo, w, 1, busy, double.infinity);
    return x != null && x + w <= math.min(hi, sq.bandEnd - TagLook.nameRight) ? x : null;
  }

  /// [x0] ~ [x0] + [w]가 [busy] 구간과 겹치면(틈 [CrossTagLook.clear]) [dir] 쪽(+1 오른쪽 · −1 왼쪽)으로 비켜 선 왼쪽 끝 —
  /// 처음 자리에서 [drift]보다 멀어지면 null. 띠 밖은 [CrossTagLook.drift](띠 끝에서 떨어진 꼬리표는 어느 띠의 것인지 흐려진다),
  /// 이름 색줄 안은 끝없음(머리 이름이 길어도 그 뒤에 선다 — 띠 안이라 어느 띠의 것인지 늘 분명하고, 한계는 부르는 쪽이 띠 안쪽으로 건다).
  static double? _slide(double x0, double w, int dir, List<(double, double)> busy, double drift) {
    var x = x0;
    for (int k = 0; k < 12; k++) {
      (double, double)? hit;
      for (final z in busy) {
        if (z.$1 < x + w + CrossTagLook.clear && z.$2 > x - CrossTagLook.clear) {
          hit = z;
          break;
        }
      }
      if (hit == null) return (x - x0).abs() <= drift ? x : null;
      x = dir > 0 ? hit.$2 + CrossTagLook.clear : hit.$1 - CrossTagLook.clear - w;
    }
    return null;
  }

  /// 이번 장면의 선이 세로 [y0, y1]를 지나는 가로 구간들 — 짝 꼬리표가 선 · 문 · 관문을 덮지 않게(끊김 · 가림 0).
  /// [back]이면 띠 뒤 선(종이 위에서 보이는 몫)까지, 아니면 띠 위 조각(문 · 관문 · 합류 · 고리)만 — 이름 색줄 안에서는 띠 뒤 선이 보이지 않는다.
  List<(double, double)> _lineSpans(double y0, double y1, {required bool back}) {
    final out = <(double, double)>[];
    void seg(double ax, double ay, double bx, double by, double w) {
      final h = w / 2;
      if (math.max(ay, by) + h < y0 || math.min(ay, by) - h > y1) return;
      out.add((math.min(ax, bx) - h, math.max(ax, bx) + h));
    }

    if (back) {
      for (final b in _back) {
        if (b.kind == _Back.kLink || b.kind == _Back.kPart) {
          for (int i = 1; i < b.pts.length; i++) {
            seg(b.pts[i - 1].dx, b.pts[i - 1].dy, b.pts[i].dx, b.pts[i].dy, b.kind == _Back.kPart ? 4 : b.width);
          }
        } else {
          seg(b.pts[0].dx, b.pts[0].dy, b.pts[0].dx, b.pts[0].dy, LinkSprites.ringBox);
        }
      }
    }
    for (final p in _top) {
      switch (p.kind) {
        case _Top.kSeg:
          seg(p.x1, p.y1, p.x2, p.y2, p.width);
        case _Top.kDoor || _Top.kJoin:
          if (p.y2 >= y0 && p.y1 <= y1) out.add((p.x1, p.x2));
        default:
          seg(p.x1, p.y1, p.x2, p.y2, LinkSprites.ringBox);
      }
    }
    return out;
  }

  /// 꼬리표 상자가 사건 글줄에 걸치면 그 글줄의 사건 이름이 비킨다(세기 1 — 글자 상자만). 보통 밀도는 꼬리표가 이름 색줄(띠 윗변 ~ + 14)에 있어
  /// 흰 사건 칸의 글줄과 겹치지 않으므로 적을 것이 없고, 조감(글줄 하나가 띠 전체)은 띠 밖 꼬리표가 그 글줄에 든다.
  void _crossZone(PaintContext c, int row, double l, double r, double top, double bottom) {
    final layout = c.layout, geo = layout.geo(row), base = layout.rowTop(row) + geo.textTop;
    for (int k = 0; k < geo.textLines; k++) {
      final a = c.v.yOf(base + k * geo.lineH), b = c.v.yOf(base + (k + 1) * geo.lineH);
      if (b <= top || a >= bottom) continue;
      _zone(row, l - 2, r + 2, k, false, 1, 1);
    }
  }

  /// 꼬리표 글 전체(검사 기록 · 풍선 글): `→ 뒤 나라` · `앞 나라 · 앞 나라 →`.
  static String _crossText(_CrossEnd e) {
    final names = e.partners.map((p) => p.name).join(CrossTagLook.sep);
    if (e.late) return '${CrossTagLook.from} $names';
    return e.back ? '$names ${CrossTagLook.arrow}' : '${CrossTagLook.arrow} $names';
  }

  /// 짝 꼬리표를 눌렀는가(배치 px) — 앱 틀이 [hitLinks]보다 **먼저** 묻는다(이름 색줄 안의 꼬리표는 띠 머리의 네모 맞히기 구간 안이다).
  /// [LinkHit.band]는 이 끝의 띠, [LinkHit.to]는 상대 띠, [LinkHit.scope]는 '<0 앞 끝 · 1 뒤 끝>:<상대 uid>'(앱 틀이 날아갈 곳).
  LinkHit? hitCrossTag(double x, double y) {
    final piece = _crossPieceAt(x, y);
    if (piece == null) return null;
    final (tag, p) = piece;
    final partner = tag.end.partners[p.partner];
    return LinkHit(LinkHitKind.crossTag, band: tag.end.band, to: partner.band, scope: '${tag.end.back ? 1 : 0}:${partner.uid}');
  }

  /// 짝 꼬리표에 올렸을 때의 풍선 글 — 두 나라와 종류 · 누르면 갈 띠(한 글자 꼬리표면 상대 모두를 줄마다):
  /// `산호 해상 동맹 → 하연 연합 왕국 · 부분 승계 · 다른 트랙 — 누르면 하연 연합 왕국 띠로`.
  String? crossTipAt(double x, double y) {
    final piece = _crossPieceAt(x, y);
    if (piece == null) return null;
    final (tag, p) = piece;
    final e = tag.end;
    String one(_CrossPartner q) {
      final kind = q.kind >= 0 && q.kind < CrossTagLook.kinds.length ? CrossTagLook.kinds[q.kind] : '승계';
      final (a, b) = e.back ? (q.name, tag.name) : (tag.name, q.name);
      return '$a ${CrossTagLook.arrow} $b · $kind · ${e.late ? '앞 나라 끝은 화면 오른쪽 밖' : '다른 트랙'}';
    }

    final lines = tag.mode == 3 ? e.partners.map(one).join('\n') : one(e.partners[p.partner]);
    return '$lines — 누르면 ${e.partners[p.partner].name} 띠로';
  }

  (_CrossTag, _CrossPiece)? _crossPieceAt(double x, double y) {
    const pad = CrossTagLook.hitPad;
    for (final tag in _crossTags) {
      if (y < tag.y - CrossTagLook.hitHalf || y > tag.y + CrossTagLook.hitHalf || x < tag.left - pad || x > tag.right + pad) continue;
      for (final p in tag.pieces) {
        if (p.partner >= 0 && x >= p.x - pad && x <= p.x + p.w + pad) return (tag, p);
      }
    }
    return null;
  }

  /// 짝 꼬리표를 그린다(띠 위 판 — 네모 뒤): 글은 글 줄에, 점은 공용 그림판의 동그라미로. 밝기는 승계선과 같다 —
  /// 고른 것이 있으면 고른 띠에 닿는 것만 1, 띠 · 꼬리표에 올리면(또는 고른 띠에 닿으면) 글이 먹 · 점이 꼬리 마름모 빛깔.
  void _paintCrossTags(PaintContext c) {
    for (final tag in _crossTags) {
      final e = tag.end;
      if (tag.y < c.head - 8 || tag.y > c.h + 8) continue;
      for (final p in tag.pieces) {
        final partners = p.partner >= 0 ? [e.partners[p.partner]] : e.partners;
        var alpha = 0.0, lift = 0.0;
        for (final q in partners) {
          alpha = math.max(alpha, linkAlpha(e.band, q.band));
          lift = math.max(lift, _lift(e.band, q.band, c));
        }
        final text = p.text;
        if (text == null) {
          final q = partners.first;
          const d = CrossTagLook.dot;
          c.sprites.add(Sprites.fill, p.x, tag.y - d / 2, withAlpha(LinkLook.liftedInk(q.color, lift), alpha), d / 7);
          continue;
        }
        final look = p.partner < 0 || text == CrossTagLook.arrow || text == CrossTagLook.from
            ? TextLook(CrossTagLook.size, ui.FontWeight.w600, lift > 0 ? Look.ink : CrossTagLook.arrowInk)
            : CrossTagLook.nameLook(partners.first.color, hot: lift > 0);
        c.later.add('crossTag', text, look, p.x, tag.y - CrossTagLook.size * .6, alpha);
      }
      c.stats.shapes++;
    }
  }

  // ───────────────────────── 맞히기 ─────────────────────────

  /// 단추 · 네모 · 선을 눌렀는가(배치 px). 위에 있는 것부터 본다 — 단추 → 네모 → 선.
  LinkHit? hitLinks(double x, double y) {
    // 선(승계선 · 소속선 · 옮겨앉기)은 띠 뒤 판이라 꼬리표 밑 흰 사슬의 종이 뒤에서는 보이지 않는다 — 그 자리의 누름은 사슬 칸이 받는다(검토 2026-10-25).
    final onChain = strips?.chainAt(x, y) ?? false;
    for (final kind in [LinkHitKind.flag, LinkHitKind.scopeButton, LinkHitKind.memberButton, LinkHitKind.hangButton, LinkHitKind.square, LinkHitKind.link]) {
      if (onChain && kind == LinkHitKind.link) continue;
      for (final a in _hits) {
        if (a.kind != kind) continue;
        if (a.hit(x, y)) return LinkHit(a.kind, band: a.band, to: a.to, scope: a.scope);
      }
    }
    return null;
  }

  /// 이번 장면에 놓인 띠 [band]의 플래그(리메이크 2부 — 접고 펴는 것을 모은 꼬리표 윗변의 꼬리). 없으면 null.
  FlagSpot? flagOf(int band) => _marks.flagOf(band);

  /// 단추를 그린 쪽(대범위 표식)이 자리를 적어 둔다. 속국 접기 단추는 [to]에 그 줄을 싣는다.
  void addHit(LinkHitKind kind, int band, String scope, ui.Rect rect, {int to = 0}) => _hits.add(_HitArea.rect(kind, band, to, scope, rect));

  // ───────────────────────── 그리기 ─────────────────────────

  @override
  void paintTile(PaintContext c, Tile t) {
    if (t != _host || c.hide.contains('links')) return;
    if (PaintPick.mend) _maskGrid(c); // 옛 길 · 새 길 모두(0.1.1 미룸 1 — route에서 뗌)
    for (final b in _back) {
      switch (b.kind) {
        case _Back.kPart:
          _vLine(c, b.pts[0].dx, b.pts[0].dy, b.pts[1].dy, withAlpha(b.color, b.alpha), 1.3, LinkLook.partDash, LinkLook.partGap, b.pts[0].dy);
          c.sprites.add(Sprites.fill, b.pts[0].dx - 2, b.tip - 2, withAlpha(b.color, b.dotAlpha), 4 / 7);
          c.debug?.note('소속선', '${_n(b.pts[0].dx)},${_n(b.pts[0].dy)},${_n(b.pts[1].dy)}');
        case _Back.kRing:
          _sprites.add(LinkSprites.ring275, b.pts[0].dx - LinkSprites.ringBox / 2, b.pts[0].dy - LinkSprites.ringBox / 2, withAlpha(b.color, b.alpha));
          c.debug?.note('고리', '${_n(b.pts[0].dx)},${_n(b.pts[0].dy)}');
        case _Back.kDot:
          const d = LinkLook.mergeDot;
          c.sprites.add(Sprites.fill, b.pts[0].dx - d / 2, b.pts[0].dy - d / 2, withAlpha(b.color, b.alpha), d / 7);
          c.debug?.note('합류점', '${_n(b.pts[0].dx)},${_n(b.pts[0].dy)}');
        case _Back.kBundleRing:
          const box = LinkSprites.ring25Box;
          _sprites.add(LinkSprites.ring25Fill, b.pts[0].dx - box / 2, b.pts[0].dy - box / 2, withAlpha(Look.paper, b.alpha));
          _sprites.add(LinkSprites.ring25, b.pts[0].dx - box / 2, b.pts[0].dy - box / 2, withAlpha(b.color, b.alpha));
          c.debug?.note('고리', '부흥선 ${_n(b.pts[0].dx)},${_n(b.pts[0].dy)}');
        default:
          _polyline(c, b);
          c.debug?.note('선', '${b.pts.map((o) => '${_n(o.dx)},${_n(o.dy)}').join(' ')}${b.width < LinkLook.width ? ' 가는${_n(b.width)}' : ''} 짙기 ${b.alpha.toStringAsFixed(2)}');
          c.debug?.note('선색', _hex(b.color));
      }
      c.stats.shapes++;
    }
  }

  /// 연도 세로줄과 같은 자리의 세로 획(0.1.1 · 이어 주는 선 미룸 1 — 스위치 mend · route에서 뗌): 구멍 · 마름모 x는 띠가 정하므로 어느 확대에서든 관문 · 통로의
  /// 세로 획이 우연히 세로줄과 같은 x가 될 수 있다 — 점선 세로줄이 획에 섞여 선이 끊기거나 세로줄로 읽힌다. 구멍 · 마름모를 옮기는 대신
  /// 띠 뒤 선(승계 · 소속 · 옮겨 앉기)의 세로 획이 덮거나 1px 안에 맞닿는 세로줄 열([GridLayer.touching])을 그 획의 세로 범위만큼 그 자리 바탕색
  /// 종이(1px 폭)로 걷는다. 이 걸음의 네모라 같은 걸음의 획보다 먼저 나가 획 밑에 깔린다(띠 위로 얹는 것은 띠가 덮으니 그대로).
  void _maskGrid(PaintContext c) {
    final columns = grid?.columns ?? const <double>[];
    if (columns.isEmpty) return;
    for (final b in _back) {
      if (b.kind == _Back.kRing || b.kind == _Back.kBundleRing) continue;
      final pts = b.pts, half = (b.kind == _Back.kPart ? TunnelLook.partW : b.width) / 2;
      for (int k = 1; k < pts.length; k++) {
        final p0 = pts[k - 1], p1 = pts[k];
        if ((p0.dx - p1.dx).abs() >= 1e-6) continue;
        final top = math.max(math.min(p0.dy, p1.dy), c.head), bottom = math.min(math.max(p0.dy, p1.dy), c.h);
        if (bottom - top < 1) continue;
        for (final l in GridLayer.touching(columns, p0.dx, half)) {
          c.grounds.paper(c.quads, l, top, l + 1, bottom);
          c.debug?.note('세로줄 걷기', '선 ${_n(p0.dx)} · 열 $l · ${_n(top)} ~ ${_n(bottom)}');
        }
      }
    }
  }

  /// 검사 기록에 쓰는 0.1px 수(지금 연표의 cx와 같은 해상도).
  static String _n(double v) => v.toStringAsFixed(1);

  /// 검사 기록에 쓰는 색(rrggbb).
  static String _hex(int argb) => (argb & 0xffffff).toRadixString(16).padLeft(6, '0');

  /// 띠 위에 얹히는 것(문 → 관문 · 다리 · 고리 · 합류 조각 → 네모 → 단추).
  void paintFront(PaintContext c, Tile t) {
    if (t != _host || c.hide.contains('links')) return;
    for (final p in _top) {
      if (p.kind != _Top.kDoor) continue;
      _paperDoor(c, p.x1, p.y1, p.x2, p.y2, withAlpha(Look.paper, p.alpha));
      c.debug?.note('문', '${_n(p.x1)},${_n(p.y1)},${_n(p.x2 - p.x1)},${_n(p.y2 - p.y1)} 짙기 ${p.alpha.toStringAsFixed(2)}');
    }
    for (final p in _top) {
      switch (p.kind) {
        case _Top.kSeg:
          final argb = withAlpha(0xff000000 | p.color, LinkLook.topAlpha * p.alpha);
          if (p.y1 == p.y2) {
            _paperRun(c, true, p.x1, p.x2, p.y1, argb, (a, z, color) => _hLine(c, a, z, p.y1, color, p.width, 0, 0, 0));
          } else {
            _paperRun(c, false, p.y1, p.y2, p.x1, argb, (a, z, color) => _vLine(c, p.x1, a, z, color, p.width, 0, 0, 0));
          }
          c.debug?.note('조각', '${_n(p.x1)},${_n(p.y1)},${_n(p.x2)},${_n(p.y2)}${p.width < LinkLook.width ? ' 가는${_n(p.width)}' : ''} 짙기 ${(LinkLook.topAlpha * p.alpha).toStringAsFixed(3)}');
          c.debug?.note('조각색', _hex(p.color));
        case _Top.kRing:
          _sprites.add(LinkSprites.ringFill, p.x1 - LinkSprites.ringBox / 2, p.y1 - LinkSprites.ringBox / 2, withAlpha(Look.paper, p.alpha));
          _sprites.add(LinkSprites.ring275, p.x1 - LinkSprites.ringBox / 2, p.y1 - LinkSprites.ringBox / 2, withAlpha(0xff000000 | p.color, LinkLook.topAlpha * p.alpha));
        case _Top.kKnot:
          c.sprites.add(Sprites.fill, p.x1 - MoveLook.knot / 2, p.y1 - MoveLook.knot / 2, withAlpha(p.color, p.alpha), MoveLook.knot / 7);
        case _Top.kJoin:
          c.quads.add(p.x1, p.y1, p.x2, p.y2, withAlpha(0xff000000 | p.color, LinkLook.topAlpha * p.alpha));
          c.debug?.note('합류', '${_n(p.x1)},${_n(p.y1)},${_n(p.x2 - p.x1)},${_n(p.y2 - p.y1)}');
        default:
          break;
      }
      c.stats.shapes++;
    }
    for (final sq in _squares.values) {
      _paintSquare(c, sq);
    }
    _paintCrossTags(c);
    _marks.paint(c, dimPicked);
  }

  // 띠 위 조각의 반투명 칠(리메이크 4단계 감독 결정 '맨 아래 한 번 긋고 위에 얹기' — paint/grounds.dart · 마지막 합치기):
  // 연도 세로줄은 그림판 바탕 바로 위에 한 번 긋고 띠 칠은 불투명 종이라, 띠 몸통([_bodiesOf]) · 꼬리표 밑 흰 사슬 종이 위의 반투명 문 · 획은
  // 그 밑이 비치지 않아 예전 그대로 둔다(흐림 · 부정된 선의 짙기 — 일부러 비치는 칠의 뜻을 지킴). 몸통 밖 바탕 위에 나온 몫(관문 · 굴 문이 테 밖 .5 ~ 1px로
  // 나온 문 · 벌어진 이음매의 다리 · 이음매 눈금 토막)만 그 자리 바탕색과 미리 섞은 불투명 색으로 칠한다 — 보이는 색은 세로줄이 없는 자리에서 예전과 같고
  // 세로줄은 비치지 않는다. 짙기 1(평소 — 흐림 · 고르기가 없을 때)이면 예전과 바이트 같다. 0.1.0에는 스위치 route 뒤였으나 0.1.1에서 route가 기본 끔이 되어
  // 옛 길의 같은 줄 이음매 다리 · 관문도 이 규칙을 지키게 mend로도 켠다(둘 다 끄면 예전 반투명 그대로 — 다-1 34aab6a의 그림).

  /// 문 하나(종이 [argb]): 반투명이면 띠 몸통과 겹친 몫은 그대로, 몸통 밖 몫은 그 자리 바탕(사슬 종이 위면 그대로)과 미리 섞은 불투명 색으로 나눠 칠한다.
  void _paperDoor(PaintContext c, double l, double t, double r, double b, int argb) {
    final a = argb >>> 24;
    if (a == 0xff || a == 0 || !(PaintPick.route || PaintPick.mend)) {
      c.quads.add(l, t, r, b, argb);
      return;
    }
    var outside = <(double, double, double, double)>[(l, t, r, b)];
    for (final o in _bodiesOf(c)) {
      final k = o.rect;
      if (k.left >= r || k.right <= l || k.top >= b || k.bottom <= t) continue;
      final next = <(double, double, double, double)>[];
      for (final (pl, pt, pr, pb) in outside) {
        final il = math.max(pl, k.left), it = math.max(pt, k.top), ir = math.min(pr, k.right), ib = math.min(pb, k.bottom);
        if (ir <= il || ib <= it) {
          next.add((pl, pt, pr, pb));
          continue;
        }
        c.quads.add(il, it, ir, ib, argb); // 띠 몸통 위 — 불투명한 띠 종이 위라 예전 그대로
        if (it > pt) next.add((pl, pt, pr, it));
        if (ib < pb) next.add((pl, ib, pr, pb));
        if (il > pl) next.add((pl, it, il, ib));
        if (ir < pr) next.add((ir, it, pr, ib));
      }
      outside = next;
      if (outside.isEmpty) return;
    }
    for (final (pl, pt, pr, pb) in outside) {
      final cx = (pl + pr) / 2, cy = (pt + pb) / 2;
      final color = (strips?.chainAt(cx, cy) ?? false) ? argb : c.grounds.over(argb, cx, cy);
      c.quads.add(pl, pt, pr, pb, color);
      c.debug?.note('문종이', '${_n(pl)},${_n(pt)},${_n(pr - pl)},${_n(pb - pt)} ${_hex(color)}${(color >>> 24) == 0xff ? '' : ' 반투명'}');
    }
  }

  /// 띠 위 획 하나(가로면 [horizontal] · 줄기 [at]에서 [from] ~ [to] · 색 [argb]): 반투명이면 줄기 방향으로만 나눠(한 획을 두 번 긋지 않게) 띠 몸통 · 문
  /// (이 장면의 문은 이미 칠한 불투명 · 몸통 위 종이) · 사슬 종이 위 몫은 그대로, 그 밖(벌어진 이음매 사이의 바탕)은 그 자리 바탕색과 미리 섞은 불투명 색으로 [draw]한다.
  void _paperRun(PaintContext c, bool horizontal, double from, double to, double at, int argb, void Function(double a, double z, int argb) draw) {
    final a = argb >>> 24;
    final lo = math.min(from, to), hi = math.max(from, to);
    if (a == 0xff || a == 0 || to <= from || !(PaintPick.route || PaintPick.mend)) {
      draw(from, to, argb);
      return;
    }
    final cover = <(double, double)>[];
    void hit(double l, double t, double r, double b) {
      if (horizontal ? (at < t || at > b) : (at < l || at > r)) return;
      final s = math.max(lo, horizontal ? l : t), e = math.min(hi, horizontal ? r : b);
      if (e > s) cover.add((s, e));
    }

    for (final o in _bodiesOf(c)) {
      hit(o.rect.left, o.rect.top, o.rect.right, o.rect.bottom);
    }
    for (final p in _top) {
      if (p.kind == _Top.kDoor) hit(p.x1, p.y1, p.x2, p.y2);
    }
    cover.sort((x, y) => x.$1.compareTo(y.$1));
    var x = lo;
    void bare(double s, double e) {
      if (e - s <= 1e-6) return;
      final m = (s + e) / 2;
      final px = horizontal ? m : at, py = horizontal ? at : m;
      draw(s, e, (strips?.chainAt(px, py) ?? false) ? argb : c.grounds.over(argb, px, py));
    }

    for (final (s, e) in cover) {
      if (e <= x) continue;
      if (s > x) bare(x, s);
      draw(math.max(s, x), e, argb);
      x = e;
    }
    bare(x, hi);
  }

  /// 이 판의 펼친 폴더(매다는 실 — 처음 물을 때 한 번 센다).
  List<FolderSpot>? _folders;

  /// 매다는 실(리메이크 조각 ③ · 설계 4-1 '실의 규칙 하나'): 펼친 폴더 안 꼬리표의 구멍에서 곧게 올라가 매듭(지름 3)에 걸린다 —
  /// 그릇 첫 줄은 몸통 윗변에(그릇에 매달림), 둘째 줄부터는 띠 윗변 위 (위 틈 − 3)에(줄 사이 매듭 — 위 꼬리표를 가로지르지 않는다).
  /// 둘째 줄부터의 매듭은 그 자리의 그릇 너비 가로대에 걸린다(4단계 흠 ① 고침 — 가로대는 대범위 층이 띠보다 뒤에 긋는다 · `ScopeLayer._paintRails`).
  /// 폴더 밖 꼬리표는 구멍만이다. 색은 구멍 테와 같다(먹 45 · 고른 띠는 먹).
  void _thread(PaintContext c, _Square sq, int color) {
    final folders = _folders ??= openFolders(c);
    if (folders.isEmpty) return;
    final bandTop = sq.y - TagLook.holeY;
    // 구멍을 품은 그릇 가운데 가장 안쪽(리메이크 2부 포개짐 — 상자 안 꼬리표는 상자 뚜껑 밑선에 매달린다).
    FolderSpot? f;
    for (final x in folders) {
      if (sq.fc >= x.left && sq.fc <= x.right && bandTop > x.body && bandTop < x.bottom && (f == null || x.depth > f.depth)) f = x;
    }
    if (f == null) return;
    // 둘째 줄부터의 매듭은 대범위 층 뒤 판의 가로대(흠 ① 고침 — 스위치 flaw)와 같은 자리에 걸린다([FolderLook.knotY]).
    final knot = sq.row == f.firstRow ? f.body + 1 : FolderLook.knotY(c, sq.row, bandTop);
    final x = (sq.fc - .5).roundToDouble(), end = (sq.y - TagLook.holeR - 1).roundToDouble();
    if (end - knot < 3) return;
    c.quads.add(x, knot + 2, x + 1, end, color);
    // 매듭 = 지름 3의 점: 1배 픽셀에서 가운데 십자는 짙게, 네 귀는 옅게(둥글게 보인다).
    c.quads.add(x - 1, knot - 1, x + 2, knot + 2, withAlpha(color, .35 * ((color >>> 24) / 255)));
    c.quads.add(x - 1, knot, x + 2, knot + 1, color);
    c.quads.add(x, knot - 1, x + 1, knot, color);
    c.quads.add(x, knot + 1, x + 1, knot + 2, color);
    c.stats.shapes++;
    c.debug?.note('매다는실', '${sq.band} ${_n(x)},${_n(knot)},${_n(end)} 깊이 ${f.depth}');
  }

  void _paintSquare(PaintContext c, _Square sq) {
    if (sq.y < c.head - 12 || sq.y > c.h + 12) return;
    final dim = bandAlpha(sq.band, sq.row);
    final edge = withAlpha(_edgeOf(sq.color), dim);
    if (sq.showF) c.debug?.note('네모', '건국 ${sq.band} ${_n(sq.fc)},${_n(sq.y)} 짙기 ${dim.toStringAsFixed(2)}${sq.unknownStart ? ' 미정' : ''}');
    if (sq.showE && _outs.contains(sq.band)) c.debug?.note('네모', '멸망 ${sq.band} ${_n(sq.ec)},${_n(sq.y)} 짙기 ${dim.toStringAsFixed(2)}${sq.unknownEnd ? ' 미정' : ''}');
    // 꼬리표 갈래 E(설계 4-1 '구멍과 꼬리 마름모'): 구멍 = 흰 동그라미(반지름 2.5) + 1px 테(먹 45 · 고른 띠는 먹) — 모든 꼬리표의 왼쪽 위.
    // 꼬리 마름모 = 반 대각선 3 · 테 없음 · 나라 색 60% + 먹 — 승계선이 떠나는 꼬리표의 오른쪽 위에만. 미정인 끝은 예전처럼 점선 동그라미.
    const hb = LinkSprites.holeBox;
    final probe = SceneText.probe; // 글 상자 기록(검사 전용 — 측정기 --capture-text): 구멍 · 마름모가 글을 가리지 않는지 견줄 상자
    if (probe != null) {
      if (sq.showF) probe.mark(c.text, c.canvas, sq.unknownStart ? 'ring' : 'hole', ui.Rect.fromCenter(center: ui.Offset(sq.fc, sq.y), width: hb, height: hb), sq.band);
      if (sq.showE && _outs.contains(sq.band)) probe.mark(c.text, c.canvas, sq.unknownEnd ? 'ring' : 'diamond', ui.Rect.fromCenter(center: ui.Offset(sq.ec, sq.y), width: hb, height: hb), sq.band);
    }
    if (sq.showF) {
      if (sq.unknownStart) {
        _sprites.add(LinkSprites.dashRing, sq.fc - LinkSprites.dashBox / 2, sq.y - LinkSprites.dashBox / 2, edge);
      } else {
        final ring = sq.band == emphasis?.look.band ? Look.ink : CanvasInk.gray(.45);
        _thread(c, sq, withAlpha(ring, dim));
        _sprites.add(LinkSprites.holeFill, sq.fc - hb / 2, sq.y - hb / 2, withAlpha(Look.paper, dim));
        _sprites.add(LinkSprites.holeRing, sq.fc - hb / 2, sq.y - hb / 2, withAlpha(ring, dim));
      }
      c.stats.shapes++;
    }
    if (sq.showE && _outs.contains(sq.band)) {
      _sprites.add(LinkSprites.diamond, sq.ec - hb / 2, sq.y - hb / 2, withAlpha(mixOklab(0xff000000 | sq.color, Look.ink, .6), dim));
      c.stats.shapes++;
    }
  }

  @override
  void flush(PaintContext c) {
    _sprites.flush(c.canvas);
    _marks.flush(c);
  }

  /// 가로 · 세로 꺾은선 하나. 곧은 변은 네모 묶음으로, 꺾이는 곳은 제 그림판의 굽이 조각으로. 가는 선(부분 승계)은 제 굵기로, 1px 선은 픽셀 칸 가운데에.
  void _polyline(PaintContext c, _Back b) {
    final crisp = b.width < LinkLook.width && _thinCrisp;
    _stroke(c, crisp ? [for (final p in b.pts) ui.Offset(_crisp(p.dx), _crisp(p.dy))] : b.pts, b.rad, withAlpha(b.color, b.alpha), b.width, b.beat);
  }

  static double _sign(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

  void _stroke(PaintContext c, List<ui.Offset> pts, double rad, int argb, double width, List<double>? beat) {
    final dash = beat == null ? 0.0 : beat[0], gap = beat == null ? 0.0 : beat[1];
    var from = pts.first;
    var run = 0.0; // 지나온 길이 — 점선의 박자가 굽이를 건너서도 이어지게(SVG의 stroke-dasharray와 같게)
    for (int i = 1; i < pts.length; i++) {
      final pt = pts[i];
      if (i + 1 == pts.length) {
        _segment(c, from, pt, argb, width, dash, gap, run);
        break;
      }
      final pv = pts[i - 1], nx = pts[i + 1];
      final inLen = (pt.dx - pv.dx).abs() != 0 ? (pt.dx - pv.dx).abs() : (pt.dy - pv.dy).abs();
      final outLen = (nx.dx - pt.dx).abs() != 0 ? (nx.dx - pt.dx).abs() : (nx.dy - pt.dy).abs();
      final r = math.min(math.min(rad, inLen / 2), outLen / 2);
      final ix = pt.dx - _sign(pt.dx - pv.dx) * r, iy = pt.dy - _sign(pt.dy - pv.dy) * r;
      final ox = pt.dx + _sign(nx.dx - pt.dx) * r, oy = pt.dy + _sign(nx.dy - pt.dy) * r;
      run = _segment(c, from, ui.Offset(ix, iy), argb, width, dash, gap, run);
      // 굽이의 한가운데: 들어온 변이 가로면 (ix, oy), 세로면 (ox, iy).
      final center = (pt.dy - pv.dy).abs() < 1e-9 ? ui.Offset(ix, oy) : ui.Offset(ox, iy);
      _sprites.corner(center, pt, r, argb, width < LinkLook.width);
      run += r * math.pi / 2; // 굽이는 이어 그리고 길이만 센다
      from = ui.Offset(ox, oy);
    }
  }

  /// 곧은 한 변. 점선이면 [run](지나온 길이)에서 박자를 이어 간다. 돌려주는 값은 이 변까지의 길이.
  double _segment(PaintContext c, ui.Offset a, ui.Offset b, int argb, double width, double dash, double gap, double run) {
    final horizontal = (a.dy - b.dy).abs() < 1e-9;
    final len = horizontal ? (b.dx - a.dx).abs() : (b.dy - a.dy).abs();
    if (len < .05) return run;
    void put(double from, double to) {
      if (horizontal) {
        final dir = b.dx >= a.dx ? 1.0 : -1.0;
        final x0 = a.dx + dir * from, x1 = a.dx + dir * to;
        _span(c, true, math.min(x0, x1), math.max(x0, x1), a.dy, width, argb);
      } else {
        final dir = b.dy >= a.dy ? 1.0 : -1.0;
        final y0 = a.dy + dir * from, y1 = a.dy + dir * to;
        _span(c, false, math.min(y0, y1), math.max(y0, y1), a.dx, width, argb);
      }
    }

    // 화면에 걸친 부분만(감독 건의 2026-10-14 9번 — 날 단위로 확대하면 버벅임): 수백 년을 잇는 승계 · 소속선은 날 단위에서 수백만 px이라
    // 점선 박자를 처음부터 끝까지 세면 장면마다 획이 수십만 개(묶음 내보내기까지 3초)였다. 보이는 구간 [v0, v1](이 변의 시작에서 잰 길이)만 돌고,
    // 박자는 지나온 길이([run])에서 그대로 이어 간다 — 화면 안의 모양은 예전과 같다.
    final (v0, v1) = _visible(c, a, b, horizontal, len);
    if (v1 <= v0) return run + len;
    if (dash <= 0) {
      put(v0, v1);
      return run + len;
    }
    final period = dash + gap;
    final base = -(run % period);
    for (double pos = base + ((v0 - base) / period).floorToDouble() * period; pos < v1; pos += period) {
      final s = math.max(pos, v0), e = math.min(pos + dash, v1);
      if (e > s) put(s, e);
    }
    return run + len;
  }

  /// 곧은 변 [a] → [b](길이 [len]) 가운데 화면(여유 4px)에 드는 구간 — 변의 시작에서 잰 길이로.
  (double, double) _visible(PaintContext c, ui.Offset a, ui.Offset b, bool horizontal, double len) {
    final (lo, hi, from, to) = horizontal ? (c.left - 4, c.w + 4, a.dx, b.dx) : (c.head - 4, c.h + 4, a.dy, b.dy);
    final (d0, d1) = to >= from ? (lo - from, hi - from) : (from - hi, from - lo);
    return (math.max(0.0, d0), math.min(len, d1));
  }

  /// 가로 한 획을 네모 묶음에 모은다. `c.quads`의 hLine은 1px 격자에 붙이므로(가는 구분선용) 여기서는 0.1px 그대로 쓴다.
  void _hLine(PaintContext c, double x0, double x1, double y, int argb, double width, double dash, double gap, double phase) {
    // 화면 밖은 세지 않는다(박자는 [phase]에서 재므로 잘라도 같은 자리) — 위 [_segment]와 같은 까닭.
    x0 = math.max(x0, c.left - 4);
    x1 = math.min(x1, c.w + 4);
    if (x1 <= x0) return;
    if (dash <= 0) {
      if (x1 - x0 > .05) _span(c, true, x0, x1, y, width, argb);
      return;
    }
    final period = dash + gap;
    var x = x0 - ((x0 - phase) % period + period) % period;
    for (; x < x1; x += period) {
      final a = math.max(x, x0), e = math.min(x + dash, x1);
      if (e > a) _span(c, true, a, e, y, width, argb);
    }
  }

  void _vLine(PaintContext c, double x, double y0, double y1, int argb, double width, double dash, double gap, double phase) {
    y0 = math.max(y0, c.head - 4);
    y1 = math.min(y1, c.h + 4);
    if (y1 <= y0) return;
    if (dash <= 0) {
      if (y1 - y0 > .05) _span(c, false, y0, y1, x, width, argb);
      return;
    }
    final period = dash + gap;
    var y = y0 - ((y0 - phase) % period + period) % period;
    for (; y < y1; y += period) {
      final a = math.max(y, y0), e = math.min(y + dash, y1);
      if (e > a) _span(c, false, a, e, x, width, argb);
    }
  }

  /// 굵기 [width]의 곧은 한 획을 px 격자에 나눠 싣는다 — 공용 `Quads`는 `drawVertices`라 가장자리가 또렷해서,
  /// 0.1px 자리의 가는 선이 2px로 번지거나 한쪽으로 튄다. 걸치는 px마다 덮은 만큼을 알파에 곱해 안티에일리어싱을 흉내 낸다(첫 작업자의 남은 차이 4).
  void _span(PaintContext c, bool horizontal, double from, double to, double center, double width, int argb) {
    if (to - from <= .02) return;
    final lo = center - width / 2, hi = center + width / 2;
    final first = lo.floorToDouble(), last = hi.ceilToDouble();
    final alpha = ((argb >> 24) & 0xff) / 255;
    if (last - first <= 1.001) {
      // 한 px 안에 다 든다 — 덮은 만큼만 옅게.
      final cover = (hi - lo).clamp(0.0, 1.0);
      _quad(c, horizontal, from, to, first, first + 1, withAlpha(argb, alpha * cover));
      return;
    }
    for (double p = first; p < last; p += 1) {
      final cover = math.min(hi, p + 1) - math.max(lo, p);
      if (cover <= .002) continue;
      _quad(c, horizontal, from, to, p, p + 1, cover >= .999 ? argb : withAlpha(argb, alpha * cover));
    }
  }

  void _quad(PaintContext c, bool horizontal, double from, double to, double a, double b, int argb) =>
      horizontal ? c.quads.add(from, a, to, b, argb) : c.quads.add(a, from, b, to, argb);
}

enum _Mode { hv, drop, rise, back }

/// 승계선의 세로 기둥 하나(배치 px — 띠 뒤 꺾은선의 세로 획: x · 위 · 아래).
class LinkColumn {
  const LinkColumn(this.x, this.top, this.bottom);
  final double x, top, bottom;

  @override
  String toString() => 'LinkColumn(${x.toStringAsFixed(1)} · ${top.toStringAsFixed(1)} ~ ${bottom.toStringAsFixed(1)})';
}

/// 장면마다의 세로 기둥 표(명세 04 3-6 '실 비킴' · 조사 결함 14 · 40 · 이어 주는 선 걸음 6): 관계선 층이 [LinkLayer.beginFrame]에서 적고,
/// 사람 띠의 실 층(paint/sphere_threads.dart)이 같은 장면에 읽어 실이 승계선 세로 통로와 같은 자리를 함께 지나지 않게 비킨다.
/// 관계선 층의 준비가 실 층보다 먼저다(painter.dart `_tileLayers` · ui/export_svg.dart의 같은 차례). 적은 적이 없는 장면은 빈 표.
/// 이번 장면의 짝 꼬리표 자리(그림판 px · [LinkLayer]가 놓음). 실 층이 그 몫의 점선 · 세로줄 걷기를 비운다(스위치 mend —
/// 0.1.1 검토: 조감의 띠 단위 가는 실(조사 결함 47)이 띠 밖에 선 '→ 하연 부흥국'의 화살 글자 위를 지났다).
abstract final class LinkTagBoxes {
  static final _of = Expando<List<ui.Rect>>('짝 꼬리표 자리');

  /// [scene](장면 — `PaintContext.scene`)의 이번 자리들.
  static List<ui.Rect> of(Object scene) => _of[scene] ?? const [];
}

abstract final class LinkColumns {
  static final _of = Expando<List<LinkColumn>>('승계선 세로 기둥');

  /// [scene](장면 — `PaintContext.scene`)의 이번 기둥들.
  static List<LinkColumn> of(Object scene) => _of[scene] ?? const [];
}

/// 옮겨 앉기의 실 · 매듭(리메이크 2부 · 결정 #3 A · 목업 d3-a): 먹 50 · 굵기 1.5 · 점선 3 2 · 굽이 반지름 6 · 뒤 토막 왼쪽 6 앞에서 곧게 · 매듭 지름 4.
abstract final class MoveLook {
  /// 먹 50(그림판 먹 단계 45 — [CanvasInk]).
  static final ink = CanvasInk.of(0xff808080);
  static const width = 1.5, dash = 3.0, gap = 2.0, radius = 6.0, lead = 6.0, knot = 4.0;
}

/// 굴 문 · 이음매 눈금 · 건넘 토막의 값(명세 04 3-4 · 3-9 · 이어 주는 선 걸음 5). 모두 px.
abstract final class TunnelLook {
  /// 굴 문의 테를 따른 깊이(테 1px과 안팎 1px씩 — 선을 가로지른 폭은 그 밀도의 문 높이) · 문에서 띠 안쪽으로 더 긋는 토막 ·
  /// 이보다 짧게 몸통을 지나는 획에는 두지 않는다.
  static const depth = 3.0, stub = 2.0, minRun = 2.0;

  /// 소속선의 굵기(띠 뒤 소속선을 긋는 `_vLine`의 1.3과 같다).
  static const partW = 1.3;

  /// 이음매 눈금의 한쪽 토막(조감은 [BirdLook.stub]).
  static const tick = 3.0;

  /// 1배 후보 '건넘 토막'(스위치 cross)의 짙기 — 종이 테는 선 양쪽 1px.
  static const crossAlpha = .75;
}

/// 맞힌 것의 종류. [crossTag]는 트랙을 건너는 승계의 짝 꼬리표(구역 60 — [LinkLayer.hitCrossTag]로만 나온다).
enum LinkHitKind { square, link, memberButton, scopeButton, hangButton, flag, crossTag }

/// 맞히기의 결과 — 총괄이 입력에 잇는다.
class LinkHit {
  const LinkHit(this.kind, {this.band = 0, this.to = 0, this.scope = ''});

  final LinkHitKind kind;

  /// 눌린 것이 딸린 띠 번호(선이면 선대 · 소속선이면 상국).
  final int band;

  /// 승계선이면 후대 띠 · 소속선이면 속국의 띠 번호.
  final int to;

  /// 대범위 단추면 그 대범위의 uid. 짝 꼬리표면 '<0 앞 끝 · 1 뒤 끝>:<상대 uid>'.
  final String scope;

  @override
  String toString() => '$kind band=$band to=$to scope=$scope';
}

/// 맞히기의 자리 하나.
class _HitArea {
  _HitArea(this.kind, this.band, this.to, this.scope, this.rect, this.pts);

  factory _HitArea.rect(LinkHitKind kind, int band, int to, String scope, ui.Rect rect) => _HitArea(kind, band, to, scope, rect, null);
  factory _HitArea.line(LinkHitKind kind, int band, int to, List<ui.Offset> pts) => _HitArea(kind, band, to, '', null, pts);

  final LinkHitKind kind;
  final int band, to;
  final String scope;
  final ui.Rect? rect;
  final List<ui.Offset>? pts;

  bool hit(double x, double y) {
    final r = rect;
    if (r != null) return x >= r.left - 1 && x <= r.right + 1 && y >= r.top - 1 && y <= r.bottom + 1;
    final list = pts!;
    for (int i = 1; i < list.length; i++) {
      final a = list[i - 1], b = list[i];
      final lo = math.min(a.dx, b.dx) - 4, hi = math.max(a.dx, b.dx) + 4;
      final top = math.min(a.dy, b.dy) - 4, bottom = math.max(a.dy, b.dy) + 4;
      if (x >= lo && x <= hi && y >= top && y <= bottom) return true;
    }
    return false;
  }
}

/// 짝 꼬리표의 꼴(구역 60 · 이어 주는 선 걸음 4 — 글 꼴 · 자리는 감독 1배 확인 몫): 글 8.5 · 굵기 600 · 상대 이름은 상대 색 30% + 먹(올리면 먹) ·
/// 화살 · 사이 점은 먹 60 · 점 지름 5(상대 띠 테 빛깔 — 승계선과 같은 색) · 띠 바깥 끝과의 틈 4 · 구멍 · 마름모와의 틈 3 · 점 ↔ 이름 2 ·
/// 화살 ↔ 점 3 · 이웃 띠 · 선 · 머리 글과의 틈 3 · 처음 자리에서 비켜 갈 수 있는 거리 40 · 누를 자리는 가운데에서 위아래 6 · 옆 2 넓게.
abstract final class CrossTagLook {
  static const size = 8.5, dot = 5.0, dotGap = 2.0, arrowGap = 3.0, outGap = 4.0, inGap = 3.0, clear = 3.0, drift = 40.0;
  static const hitPad = 2.0, hitHalf = 6.0;
  static const arrow = '→', sep = ' · ';

  /// 선대 끝이 화면 오른쪽 밖인 승계선의 후대 쪽 꼬리표 화살(`← ●앞 나라` — 감독 고름 2026-10-26 ①).
  static const from = '←';

  /// 풍선 글의 승계 종류(구역 60의 c — 0 직접 · 1 간접 · 2 부흥 · 3 부분).
  static const kinds = ['직접 승계', '간접 승계', '부흥', '부분 승계'];
  static final arrowInk = CanvasInk.gray(.6);
  static TextLook nameLook(int color, {bool hot = false}) => TextLook(size, ui.FontWeight.w600, hot ? Look.ink : mixSrgb(0xff000000 | color, Look.ink, .30));
}

/// 짝 꼬리표 한 끝의 상대 하나(구역 60 항목 하나 — [id]는 항목 번호로, 한 끝에 여럿일 때의 차례).
class _CrossPartner {
  _CrossPartner(this.id, this.band, this.uid, this.name, this.color, this.kind);
  final int id, band, color, kind;
  final String uid, name;
}

/// 짝 꼬리표 한 끝(한 띠의 앞 끝 · 뒤 끝)에 모인 상대들.
class _CrossEnd {
  _CrossEnd(this.band, this.row, this.back, {this.late = false});
  final int band, row;
  final bool back;

  /// 선대 끝이 화면 오른쪽 밖인 승계선의 후대 쪽 끝([LinkLayer._lateIns]) — 구역 60이 아니라 이번 장면의 길이 놓는다(상대 uid 없음 · 누르면 띠 번호로).
  final bool late;
  final partners = <_CrossPartner>[];
}

/// 놓인 짝 꼬리표 하나 — [mode]는 자리 사다리의 갈래(1 띠 밖 · 2 이름 색줄 안 · 3 '→' 한 글자), [y]는 글줄 가운데, [name]은 이 끝 띠의 이름(풍선 글).
class _CrossTag {
  _CrossTag(this.end, this.mode, this.left, this.y, this.name);
  final _CrossEnd end;
  final int mode;
  final double left, y;
  final String name;
  double right = 0;
  final pieces = <_CrossPiece>[];
}

/// 짝 꼬리표의 조각: 글([text]) 또는 점(null) · 왼쪽 끝 · 폭 · 누르면 갈 상대의 차례(사이 점 ' · '는 −1 — 누름 없음).
class _CrossPiece {
  const _CrossPiece(this.text, this.x, this.w, this.partner);
  final String? text;
  final double x, w;
  final int partner;
}

/// 관계선의 값(명세 1절 · css). 모두 px.
abstract final class LinkLook {
  static const sq = 7.0, half = 3.5, bw = 1.0, door = 4.4, radius = 10.0;

  /// 네모 가운데의 띠 안쪽 여백 = G.bw + 2 + G.sq/2.
  static const inset = 6.5;
  /// 관문의 가장 긴 길이: 네모 + 1px ↔ 테두리 밖 0.5px = bw 1 + 1 + 비키기 최대(직접이 아닌 이음매 6px) + 0.5 — js의 GATE_MAX와 같은 식.
  /// 5.5(3px 비키기 기준)로 두면 6px 비켜 앉은 이음매의 다리(상 → 서주 같은 간접)가 아예 그려지지 않는다.
  /// 꼬리표 갈래 E의 키에 맞춘 귀(2026-10-15)부터 구멍은 띠 시작에서 7 ~ 14(귀 + 2)라 구멍 왼쪽 테까지 최대 11.5 — 그보다 조금 넉넉히 12.
  static const gateMax = 12.0, sqClear = 1.5, tipGap = 4.5, fade = 44.0;

  /// 선대 끝이 화면 오른쪽 밖일 때 후대 구멍으로 드는 짧은 선이 시작하는 자리(띠 시작 앞 — 되돌아가는 길의 도착 통로와 같은 9).
  static const lateIn = 9.0;
  /// 부분 승계는 가는 실선 하나(1px — 픽셀 칸에 맞춰 긋는다 `_crisp`). 예전의 늘 세 가닥(정도만큼 진하게)은 선이 셋이라 난잡해 버렸다(2026-10-13 감독 'A 한 줄 · 짙기 80%').
  static const thinW = 1.0;
  static const width = 1.6, ringR = 2.75, joinH = 1.6;

  /// 합류 점의 지름(0.1.1 · 조사 결함 43 — 같은 구멍에 둘째로 드는 선이 첫 선에 닿아 멎는 자리 · 그 선의 색).
  static const mergeDot = 3.0;
  static const dash = 5.0, gap = 4.0, partDash = 2.0, partGap = 3.0;

  /// 간접 · 부흥 계승선의 박자(파선). 감독 건의 2026-10-15 4번(A)부터 띠의 테에는 파선이 없다 — 끊긴 선은 관계선만.
  static const beat = [dash, gap];
  /// 부분 승계의 짙기: 띠 뒤 선도 띠 위 조각도 .8(css `.tl-link.is-partial` — js의 PARTIAL). 가는 선이라 다른 승계선의 띠 뒤 .5로는 잘 보이지 않는다
  /// (감독: 처음 35%는 "너무 안보이네" → 80%). 정도는 선에 그리지 않는다.
  /// 관계선의 짙기 — 모두 1(감독 2026-10-16 "계승선 등도 색을 바꿔보자 · 너무 눈에 안 띔 · 통일감 유지" → 판 `.claude/research/band-one/관계선-색-고르기.html`의 가).
  /// 예전에는 나라 색 그대로를 띠 뒤 .5 · 띠 위 조각 .9 · 부분 승계 .8 · 소속선 .8 · 소속선 끝점 .9의 투명도로 옅게 했다 — 이제 색 자체([inkOf])가 옅고 또렷하다.
  /// 고른 띠 · 흐림의 밝기(linkAlpha) · 올림(_lifted)과 부정된 나라의 옅은 선([refutedLine] · [refutedPart])은 그대로 투명도다.
  static const backAlpha = 1.0, partialAlpha = 1.0, topAlpha = 1.0, partAlpha = 1.0, dotAlpha = 1.0;

  /// 관계선 한 가닥의 색 = 그 나라 띠의 테 빛깔(나라 색 84% + 먹 · oklab — 띠 테 `BandLayer.toneOf`의 edge와 같다).
  /// 띠 뒤 선 · 띠 위 조각(관문 · 다리) · 소속선과 끝점 · 고리 · 대범위 부흥선이 모두 이 색 하나 — 선이 띠의 테에서 이어져 나온 것처럼 보인다.
  static int inkOf(int rgb) => mixOklab(0xff000000 | rgb, Look.ink, .84);

  /// 짙게(올린 띠 · 고른 띠에 닿음 · 선 위 커서)의 색 = 꼬리 마름모 빛깔(나라 색 60% + 먹). 예전의 '짙기 .5 → 1'을 색으로 옮겼다 — 기본 짙기가 1이라 투명도로는 더 짙어질 데가 없다.
  static int hotInkOf(int rgb) => mixOklab(0xff000000 | rgb, Look.ink, .6);

  /// 짙게의 정도 [lift](0 ~ 1 · 흐름을 탄다)만큼 [inkOf] → [hotInkOf]. 흐르는 값마다 섞기를 보관하지 않게 sRGB로 바로 섞는다.
  static int liftedInk(int rgb, double lift) => lift <= 0 ? inkOf(rgb) : (lift >= 1 ? hotInkOf(rgb) : Look.mix(inkOf(rgb), hotInkOf(rgb), lift));
  static const refutedLine = .2, refutedPart = .3;
}

/// 조감(밀도 2)의 값(명세 04의 7-2절 · 05의 7절). 모양 a · b는 14px 띠, c는 8px 띠다.
abstract final class BirdLook {
  /// 띠 끝 안쪽의 관문 길이 · 네모가 있었을 자리(G.bw + 2 + G.sq/2 + 0.5).
  static const stub = 3.0, stationX = 7.0;
  static const door = 4.4, doorC = 3.0;
  /// 조감의 가는 선(부분 승계): 띠가 낮아 더 가늘게 — a·b .8 · c .6(js BIRD의 thin).
  static const thinW = .8, thinWC = .6;

  /// 띠 안 이름 둘레의 여유 · 단추의 꼴(css 1801).
  static const nameClear = 3.0, btnHeight = 10.0, btnPad = 4.0, btnRadius = 3.0, btnTextSize = 8.5;
}

/// 타일에서 읽은 구역 20(네모)의 날것 — 조각들을 이어 붙이는 동안의 값.
class _SquareIn {
  _SquareIn(this.band, this.row, this.color, this.a, this.b, this.c);
  final int band, row, color, a;

  /// 왼쪽 · 오른쪽 칸(분): 이음매면 이웃과의 틈, 연대 폭이면 바깥 끝 ↔ 확정 해의 거리.
  final double b, c;
  double start = 0, end = 0;
  bool clipLeft = true, clipRight = true;
  String? name;

  bool get unknownStart => a & 1 != 0;
  bool get unknownEnd => a & 2 != 0;
  bool get ongoing => a & 4 != 0;
  bool get seamLeft => a & 8 != 0;
  bool get seamRight => a & 16 != 0;
  bool get rangeStart => a & 32 != 0;
  bool get rangeEnd => a & 64 != 0;
  /// 직접이 아닌 승계(간접 · 부흥 · 부분)의 이음매 — 네모가 6px 비켜 앉는다(내보내기 links.mjs의 wideL · wideR).
  bool get wideLeft => a & 256 != 0;
  bool get wideRight => a & 512 != 0;
}

/// 한 띠의 네모 셈(배치 px).
class _Square {
  _Square({
    required this.band, required this.row, required this.color, required this.y, required this.x1, required this.x2,
    required this.fc, required this.ec, required this.showF, required this.showE, required this.bandStart, required this.bandEnd,
    required this.xStart, required this.xEnd, required this.unknownStart, required this.unknownEnd, required this.name,
  });
  final int band, row, color;

  /// 네모의 가운데 높이 · 띠의 바깥 두 끝 · 두 네모의 가운데 · 띠의 제 두 끝(사라지는 꼬리를 뺀) · 확정 해의 자리.
  final double y, x1, x2, fc, ec, bandStart, bandEnd, xStart, xEnd;
  final bool showF, showE, unknownStart, unknownEnd;
  final String name;
}

/// 타일에서 읽은 승계선 한 건.
class _LinkIn {
  _LinkIn(this.row, this.row2, this.start, this.end, this.from, this.to, this.a, this.channel, this.color);

  /// 승계 종류(계약 6-10절): 0 직접 · 1 간접 · 2 부흥 · 3 부분.
  static const indirect = 1, revival = 2, partial = 3;

  factory _LinkIn.read(TileSection s, int i, double origin) => _LinkIn(
    s.u(Tile.itemRow)[i], s.u(Tile.itemRow2)[i], origin + s.f(Tile.itemX0)[i], origin + s.f(Tile.itemX1)[i],
    s.u(Tile.itemRef)[i], s.u(Tile.itemB)[i], s.u(Tile.itemA)[i], s.u(Tile.itemC)[i], s.u(Tile.itemColor)[i],
  );

  final int row, row2, from, to, a, channel, color;

  /// 타일에 잘려 온 조각을 이어 붙이며 넓힌다(`_readLinks`).
  double start, end;

  /// 이 장면에서 다시 센 세로 통로 번호(스위치 route · 명세 04 8-1 · 조사 결함 6 — [LinkLayer._recount]). 다시 세지 않았으면 −1(구역 21의 기준값 [channel]을 쓴다).
  int lane = -1;

  int get kind => a & 3;
  int get degree => (a >> 2) & 3;
  bool get down => a & (1 << 4) != 0;
  bool get qFirst => a & (1 << 5) != 0;
  bool get seam => a & (1 << 6) != 0;
  bool get absorb => a & (1 << 7) != 0;
  bool get bundled => a & (1 << 8) != 0;
  bool get unknownQ => a & (1 << 9) != 0;
  bool get unknownP => a & (1 << 10) != 0;
  bool get refuted => a & (1 << 13) != 0;

  /// 가는 선으로 긋는 종류인가(부분 승계 — js SUCC_KINDS의 thin).
  bool get thin => kind == partial;
  List<double>? get beat => kind == indirect || kind == revival ? LinkLook.beat : null;
}

/// 타일에서 읽은 소속선 한 건.
class _PartIn {
  _PartIn(this.row, this.row2, this.start, this.end, this.member, this.host, this.a, this.hangLanes, this.color, {this.clipped = false}) : first = start;

  factory _PartIn.read(TileSection s, int i, double origin) => _PartIn(
    s.u(Tile.itemRow)[i], s.u(Tile.itemRow2)[i], origin + s.f(Tile.itemX0)[i], origin + s.f(Tile.itemX1)[i],
    s.u(Tile.itemRef)[i], s.u(Tile.itemB)[i], s.u(Tile.itemA)[i], s.u(Tile.itemC)[i], s.u(Tile.itemColor)[i],
    clipped: s.u(Tile.itemFlags)[i] & Tile.clipLeft != 0,
  );

  final int row, row2, member, host, a, hangLanes, color;

  /// 소속 시작 · 끝(분). 타일에 잘려 온 조각을 이어 붙이며 넓힌다([LinkLayer._readParts]) — [clipped]이면 시작이 실린 타일들보다 왼쪽(모름)이고
  /// [start]는 실린 조각 가운데 가장 왼쪽의 잘린 자리다.
  double start, end;
  bool clipped;

  /// 처음 읽은 조각의 시작(잘렸어도 그대로) — 스위치 route를 끈 길(예전: 첫 조각만 읽음).
  final double first;

  bool get down => a & 1 != 0;
  bool get refuted => a & 2 != 0;
}

/// 띠 뒤 층의 한 조각.
class _Back {
  _Back(this.kind, this.pts, this.rad, this.color, this.alpha, this.beat, this.width, this.tip, this.dotAlpha);
  static const kLink = 0, kPart = 1, kRing = 2, kBundleRing = 3, kDot = 4;

  /// 합류 점(0.1.1 · 조사 결함 43 — 같은 구멍에 둘째로 드는 선이 첫 선에 닿아 멎는 자리): 지름 [LinkLook.mergeDot] · 그 선의 색 · 짙기.
  factory _Back.dot(double x, double y, int color, double alpha) => _Back(kDot, [ui.Offset(x, y)], 0, color, alpha, null, 0, 0, 0);

  factory _Back.link(List<ui.Offset> pts, double rad, int color, double alpha, List<double>? beat, double width) => _Back(kLink, pts, rad, color, alpha, beat, width, 0, 0);
  factory _Back.part(double x, double top, double bottom, double tip, int color, double alpha, double dotAlpha) =>
      _Back(kPart, [ui.Offset(x, top), ui.Offset(x, bottom)], 0, color, alpha, null, 0, tip, dotAlpha);
  factory _Back.ring(double x, double y, int color, double alpha) => _Back(kRing, [ui.Offset(x, y)], 0, color, alpha, null, 0, 0, 0);

  /// 대범위 부흥선 끝의 고리(`.tl-link-ring` — r 2.5 · 굵기 1.3 · 채움 종이색 · 짙기 .6).
  factory _Back.bundleRing(double x, double y, int color) => _Back(kBundleRing, [ui.Offset(x, y)], 0, color, .6, null, 0, 0, 0);

  final int kind, color;
  final List<ui.Offset> pts;

  /// 승계선의 굵기(1.6 · 가는 선이면 그 밀도의 값) — 소속선 · 고리는 쓰지 않는다(0).
  final double rad, alpha, width, tip, dotAlpha;
  final List<double>? beat;
}

/// 띠 위 층의 한 조각.
class _Top {
  _Top(this.kind, this.x1, this.y1, this.x2, this.y2, this.color, this.width, this.alpha);
  static const kDoor = 0, kSeg = 1, kRing = 2, kJoin = 3, kKnot = 4;

  /// 옮겨 앉기의 매듭(리메이크 2부) — [color]는 알파까지 든 색.
  factory _Top.knot(double x, double y, int color) => _Top(kKnot, x, y, x, y, color, 0, 1);

  factory _Top.door(double l, double t, double r, double b, double alpha) => _Top(kDoor, l, t, r, b, 0, 0, alpha);
  factory _Top.seg(double x1, double y1, double x2, double y2, int color, double width, double alpha) => _Top(kSeg, x1, y1, x2, y2, color, width, alpha);
  factory _Top.ring(double x, double y, int color, double alpha) => _Top(kRing, x, y, x, y, color, 0, alpha);
  factory _Top.join(double l, double t, double w, double h, int color, double alpha) => _Top(kJoin, l, t, l + w, t + h, color, 0, alpha);

  final int kind, color;
  final double x1, y1, x2, y2, width, alpha;
}

/// 관계선만의 작은 그림판: 굽이(둥근 모서리) · 고리 · 네모. 조각을 흰색으로 한 번 그려 두고 장면마다 drawRawAtlas 한 번으로 찍는다.
/// (`scene/sprites.dart`와 같은 방식이지만 공용 파일을 고치지 않으려고 제 층 안에 둔다 — 계약 7절.)
class LinkSprites {
  static const _cell = 24.0;

  /// 굽이의 반지름들(굵기 1.6) — 그릴 반지름에 가장 가까운 것을 골라 조금 줄이거나 늘여 찍는다.
  static const radii = [3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
  static const stroke = 1.6;

  /// 가는 선(부분 승계)의 굽이는 굵기 1로 따로 그려 둔다 — 1.6짜리 조각을 쓰면 굽이만 굵어 보인다. 자리는 같은 칸의 네 줄 아래.
  static const thinStroke = 1.0;

  /// 네모(7×7 · rx 2)는 9×9 상자, 미정 동그라미(r 4 · 굵기 1.4)는 9.4×9.4, 고리(r 2.75 · 굵기 1.6)는 7.1×7.1.
  static const squareBox = 9.0, dashBox = 9.4, ringBox = 7.1;
  static const squareFill = ui.Rect.fromLTWH(0 * _cell, 3 * _cell, squareBox, squareBox);
  static const squareEdge1 = ui.Rect.fromLTWH(1 * _cell, 3 * _cell, squareBox, squareBox);
  static const squareEdge16 = ui.Rect.fromLTWH(2 * _cell, 3 * _cell, squareBox, squareBox);
  static const dashRing = ui.Rect.fromLTWH(3 * _cell, 3 * _cell, dashBox, dashBox);
  static const ring275 = ui.Rect.fromLTWH(4 * _cell, 3 * _cell, ringBox, ringBox);
  static const ringFill = ui.Rect.fromLTWH(5 * _cell, 3 * _cell, ringBox, ringBox);

  /// 대범위 부흥선 끝의 고리(r 2.5 · 굵기 1.3)는 6.3×6.3 상자.
  static const ring25Box = 6.3;
  static const ring25 = ui.Rect.fromLTWH(6 * _cell, 3 * _cell, ring25Box, ring25Box);
  static const ring25Fill = ui.Rect.fromLTWH(7 * _cell, 3 * _cell, ring25Box, ring25Box);

  /// 꼬리표 갈래 E의 구멍(흰 원 반지름 2.5 · 1px 테 — 바깥 반지름 3)과 꼬리 마름모(반 대각선 3)는 7×7 상자의 한가운데에.
  static const holeBox = 7.0;
  static const holeFill = ui.Rect.fromLTWH(0 * _cell, 7 * _cell, holeBox, holeBox);
  static const holeRing = ui.Rect.fromLTWH(1 * _cell, 7 * _cell, holeBox, holeBox);
  static const diamond = ui.Rect.fromLTWH(2 * _cell, 7 * _cell, holeBox, holeBox);

  static const _sheetWidth = 8 * _cell, _sheetHeight = 8 * _cell;

  ui.Image? _image;
  double _scale = 1;

  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  /// 굽이 조각의 자리: 반지름 [i]번째의 [q]사분면. [thin]이면 가는 선의 것.
  static ui.Rect arc(int i, int q, [bool thin = false]) {
    final box = radii[i] + (thin ? thinStroke : stroke) / 2;
    return ui.Rect.fromLTWH((i.isEven ? 0.0 : 4 * _cell) + q * _cell, (i < 2 ? 0 : (i < 4 ? _cell : 2 * _cell)) + (thin ? 4 * _cell : 0), box, box);
  }

  /// 굽이 하나: 원의 한가운데가 [center], 꺾이는 점이 [pt], 반지름 [r].
  void corner(ui.Offset center, ui.Offset pt, double r, int argb, [bool thin = false]) {
    if (r < .5) return;
    var best = 0;
    for (int i = 1; i < radii.length; i++) {
      if ((radii[i] - r).abs() < (radii[best] - r).abs()) best = i;
    }
    final size = r / radii[best];
    final right = pt.dx > center.dx, below = pt.dy > center.dy;
    final source = arc(best, below ? (right ? 2 : 3) : (right ? 1 : 0), thin);
    final box = source.width * size;
    add(source, right ? center.dx : center.dx - box, below ? center.dy : center.dy - box, argb, size);
  }

  // 장면마다 다시 쓰는 목록.
  Float32List _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  Int32List _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  void add(ui.Rect source, double left, double top, int argb, [double size = 1]) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = size / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = source.left * s;
    _rects[p + 1] = source.top * s;
    _rects[p + 2] = source.right * s;
    _rects[p + 3] = source.bottom * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(
      _image ??= _render(_scale), Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4),
      Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint,
    );
    _n = 0;
  }

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    const white = ui.Color(0xffffffff);
    final line = ui.Paint()
      ..color = white
      ..style = ui.PaintingStyle.stroke
      ..isAntiAlias = true;
    final fill = ui.Paint()..color = white;
    // 굽이: 반지름마다 네 사분면. 조각 상자가 그 사분면이 되도록 원의 한가운데를 놓는다.
    for (final thin in [false, true]) {
      line.strokeWidth = thin ? thinStroke : stroke;
      for (int i = 0; i < radii.length; i++) {
        for (int q = 0; q < 4; q++) {
          final cell = arc(i, q, thin);
          final cx = cell.left + (q == 1 || q == 2 ? 0.0 : cell.width), cy = cell.top + (q >= 2 ? 0.0 : cell.height);
          canvas.save();
          canvas.clipRect(cell);
          canvas.drawCircle(ui.Offset(cx, cy), radii[i], line);
          canvas.restore();
        }
      }
    }
    // 네모 7×7 · rx 2: 채움 · 테두리 1(건국) · 테두리 1.6(멸망). 9×9 상자의 한가운데에.
    const rrect = ui.RRect.fromLTRBXY(1, 1, 8, 8, 2, 2);
    canvas.save();
    canvas.translate(squareFill.left, squareFill.top);
    canvas.drawRRect(rrect, fill);
    canvas.restore();
    for (final (at, w) in [(squareEdge1, 1.0), (squareEdge16, 1.6)]) {
      canvas.save();
      canvas.translate(at.left, at.top);
      line.strokeWidth = w;
      canvas.drawRRect(rrect.deflate(w / 2), line);
      canvas.restore();
    }
    // 미정 동그라미(r 4 · 굵기 1.4 · 점선 2 2): 짧은 호 여섯으로.
    canvas.save();
    canvas.translate(dashRing.left, dashRing.top);
    line.strokeWidth = 1.4;
    for (int i = 0; i < 6; i++) {
      canvas.drawArc(ui.Rect.fromCircle(center: const ui.Offset(dashBox / 2, dashBox / 2), radius: 4), i * math.pi / 3, math.pi / 3 * .55, false, line);
    }
    canvas.restore();
    // 고리 r 2.75(굵기 1.6)와 그 속을 메우는 원.
    canvas.save();
    canvas.translate(ring275.left, ring275.top);
    line.strokeWidth = stroke;
    canvas.drawCircle(const ui.Offset(ringBox / 2, ringBox / 2), 2.75, line);
    canvas.restore();
    canvas.save();
    canvas.translate(ringFill.left, ringFill.top);
    canvas.drawCircle(const ui.Offset(ringBox / 2, ringBox / 2), 2.75, fill);
    canvas.restore();
    // 대범위 부흥선 끝의 고리 r 2.5(굵기 1.3)와 그 속을 메우는 원.
    canvas.save();
    canvas.translate(ring25.left, ring25.top);
    line.strokeWidth = 1.3;
    canvas.drawCircle(const ui.Offset(ring25Box / 2, ring25Box / 2), 2.5, line);
    canvas.restore();
    canvas.save();
    canvas.translate(ring25Fill.left, ring25Fill.top);
    canvas.drawCircle(const ui.Offset(ring25Box / 2, ring25Box / 2), 2.5, fill);
    canvas.restore();
    // 꼬리표의 구멍(흰 원 + 1px 테)과 꼬리 마름모.
    const hc = ui.Offset(holeBox / 2, holeBox / 2);
    canvas.save();
    canvas.translate(holeFill.left, holeFill.top);
    canvas.drawCircle(hc, 2.5, fill);
    canvas.restore();
    canvas.save();
    canvas.translate(holeRing.left, holeRing.top);
    line.strokeWidth = 1;
    canvas.drawCircle(hc, 2.5, line);
    canvas.restore();
    canvas.save();
    canvas.translate(diamond.left, diamond.top);
    canvas.drawPath(
      ui.Path()
        ..moveTo(hc.dx, hc.dy - 3)
        ..lineTo(hc.dx + 3, hc.dy)
        ..lineTo(hc.dx, hc.dy + 3)
        ..lineTo(hc.dx - 3, hc.dy)
        ..close(),
      ui.Paint()
        ..color = white
        ..isAntiAlias = true,
    );
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheetWidth * scale).ceil(), (_sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }
}

// ───────────────────────── 선 감사 (이어 주는 선 걸음 1 — 명세 04의 8-6) ─────────────────────────

/// 감사하는 선의 종류: 승계(구역 21 · 대범위 부흥선 묶음 포함) · 소속(22) · 옮겨 앉기(52).
enum LineAuditKind {
  succession('승계'),
  part('소속'),
  move('옮겨앉기');

  const LineAuditKind(this.label);
  final String label;
}

/// 감사할 선 하나: 띠 뒤 꺾은선 [pts](배치 px) · 두 끝 띠 [from] · [to](이 둘의 몸통 뒤는 숨은 몫이 아님) ·
/// 띠 위 조각의 길이 [topPx] · 굴 문을 둔 띠 [doors](걸음 5 — 그 띠 뒤의 몫은 '표시 있음').
class AuditLine {
  const AuditLine(this.kind, this.from, this.to, this.pts, {this.topPx = 0, this.doors = const {}});
  final LineAuditKind kind;
  final int from, to;
  final List<ui.Offset> pts;
  final double topPx;
  final Set<int> doors;
}

/// 띠 몸통 하나: 띠 [band] · 줄 [row] · 상자(가로 = 띠의 제 두 끝 · 세로 = 띠 윗변 ~ 몸통 아랫변, 배치 px).
class AuditBody {
  const AuditBody(this.band, this.row, this.rect);
  final int band, row;
  final ui.Rect rect;
}

/// 한 장면의 선 감사 — 끊김 0의 잣대(명세 04의 8-6). 그림은 바꾸지 않고 세기만 한다.
///  · [hiddenPx]: 두 끝 띠가 아닌 다른 띠 몸통 뒤로 숨은 px 가운데 굴 문 표시가 없는 것(0이어야 함)
///  · [markedPx]: 굴 문이 있는 숨은 px · [invisible]: 보이는 px이 0인 선 · [missing]: 화면 안인데 그려지지 않은 구역 21 쌍 ·
///    [backPaths]: 6점 되돌아감(S길) 수 · [kinds]: 종류 → (선 수, 숨은 px, 안 보임)
class LineAudit {
  const LineAudit({
    required this.lines, required this.hiddenPx, required this.markedPx, required this.invisible, required this.missing, required this.backPaths,
    this.kinds = const {}, this.detail = const [], this.missed = const [],
  });
  final int lines, invisible, missing, backPaths;
  final double hiddenPx, markedPx;
  final Map<LineAuditKind, (int, double, int)> kinds;

  /// 숨은 px이 큰 선부터 '종류 앞→뒤 숨은 n px · 띠 id n …'(안 보이는 선 포함).
  final List<String> detail;

  /// 빠진 구역 21 쌍 '앞→뒤 줄 a→b x~x'.
  final List<String> missed;

  String get summary =>
      '선 $lines · 숨은 ${hiddenPx.round()}px · 표시 ${markedPx.round()}px · 안 보임 $invisible · 빠짐 $missing · S길 $backPaths'
      '${kinds.entries.map((e) => ' · ${e.key.label} ${e.value.$1}선 ${e.value.$2.round()}px').join()}';

  Map<String, Object> toJson() => {
    'lines': lines, 'hiddenPx': double.parse(hiddenPx.toStringAsFixed(1)), 'markedPx': double.parse(markedPx.toStringAsFixed(1)),
    'invisible': invisible, 'missing': missing, 'backPaths': backPaths,
    'kinds': {for (final e in kinds.entries) e.key.label: {'lines': e.value.$1, 'hiddenPx': double.parse(e.value.$2.toStringAsFixed(1)), 'invisible': e.value.$3}},
    'detail': detail, 'missed': missed,
  };

  /// 찍기(측정기 `--capture-lines=yes`)가 켜면 그림판이 장면마다 감사해 [last]에 둔다 — 검사 기록(debug)을 켜지 않은 실제 앱에서도.
  static bool capture = false;
  static LineAudit? last;
}

/// 감사 목록의 한 건: 띠 뒤 꺾은선의 차례 [back](없으면 −1 — 다리만) · 띠 위 조각의 차례 범위 [t0] ~ [t1].
class _AuditEntry {
  _AuditEntry(this.kind, this.from, this.to, this.back, this.t0, this.t1, [this.extra = const []]);
  final LineAuditKind kind;
  final int from, to, back, t0, t1;

  /// 남과 함께 쓰는 띠 위 조각의 차례 범위(같은 줄기의 꼬리 관문).
  final List<(int, int)> extra;
}
