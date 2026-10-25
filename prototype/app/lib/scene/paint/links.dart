import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' show Emphasis, Spot;
import '../layout.dart';
import '../reserved.dart';
import '../sprites.dart';
import '../tile.dart';
import 'bands.dart';
import 'context.dart';
import 'figures.dart' show FigureLook;
import 'hangs.dart' show HangLayer, HangLook;
import 'look.dart';
import 'scopes.dart';
import 'strips.dart' show CellKind;

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

  /// 띠 번호 → 네모(장면마다 다시).
  final _squares = <int, _Square>{};

  /// 이번 장면에 승계선이 **떠나는** 띠(꼬리표 갈래 E의 꼬리 마름모 — 설계 4-1 '구멍과 꼬리 마름모'). 선을 숨기면(메뉴 '숨기기') 비운다.
  final _outs = <int>{};
  final _rowSquares = <int, List<_Square>>{};

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
    _back.clear();
    _top.clear();
    _reserved.clear();
    _zones.clear();
    _hits.clear();
    _markDone.clear();
    _tabRightOf.clear();
    _lowerSpans.clear();
    _host = null;
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
    final hole = TagLook.holeAt(_bands?.endOf(it.band) ?? TagEnd.cham, G.head); // 두 장 꼬리표: 구멍은 이름 색줄(14)의 귀에 맞춤
    var fc = it.unknownStart ? xStart : math.max(xStart, x1 + hole);
    var ec = it.unknownEnd ? xEnd : math.min(xEnd, x2 - TagLook.diamondX);
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
    showF = showF && xStart >= l - 1 && fc - half >= l - .5 && fc + half <= r + .5;
    showE = showE && xEnd <= r + 1 && ec - half >= l - .5 && ec + half <= r + .5;
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
    final parts = <_PartIn>[];
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      _readLinks(t, linkById);
      _readItems(t, secPart, seen, (i, s, origin) => parts.add(_PartIn.read(s, i, origin)));
    }
    final links = linkById.values.toList();
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
        _planPart(c, p);
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
    final bundledHosts = <int>{};
    for (final l in links) {
      if (successionMode == 1 && l.kind != 0) continue; // '직접 승계만'은 대범위 부흥선도 숨긴다(명세 4-5)
      if (l.bundled && byHost.containsKey(l.from)) {
        bundledHosts.add(l.from);
        continue;
      }
      _planLink(c, l);
    }
    if (successionMode != 1) {
      for (final host in bundledHosts) {
        _planBundle(c, byHost[host]!, host);
      }
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

  /// 옮겨 앉기의 실(리메이크 2부 · 결정 #3 A · 목업 d3-a `mv`): 앞 토막의 아랫변(뒤 토막이 위 줄이면 윗변)에 매듭(지름 4 · 먹 50)을 두고,
  /// 뒤 토막 왼쪽 6 앞에서 곧게 내려(올라)가 뒤 토막 구멍 높이에서 반지름 6으로 꺾어 구멍으로 든다 — 띠 뒤는 점선 3 2 · 1.5px · 먹 50,
  /// 뒤 토막 왼쪽 끝에서 구멍 테까지는 띠 위 실선. 두 토막이 다 그려질 때만 긋는다(한쪽만 보이면 없음 · 조감 없음).
  void _planMoves(PaintContext c) {
    if (_bird) return;
    final ends = <String, List<(int, int)>>{};
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      _readItems(t, secMove, seen, (i, s, origin) {
        final key = t.text(s.u(Tile.itemText2)[i]);
        if (key.isNotEmpty) (ends[key] ??= []).add((s.u(Tile.itemRef)[i], s.u(Tile.itemA)[i]));
      });
    }
    if (ends.isEmpty) return;
    final layout = c.layout, v = c.v;
    for (final e in ends.values) {
      int front = 0, back = 0;
      for (final (band, a) in e) {
        if (a == 0) {
          front = band;
        } else {
          back = band;
        }
      }
      final f = _squares[front], b = _squares[back];
      if (f == null || b == null || !b.showF || f.row >= layout.rowCount || !layout.hasBody(f.row)) continue;
      final geo = layout.geo(f.row);
      final fTop = v.yOf(layout.rowTop(f.row) + geo.bandTop).roundToDouble(), fBottom = v.yOf(layout.rowTop(f.row) + geo.bandTop + geo.bandHeight).roundToDouble();
      final below = b.y > f.y;
      final knotY = below ? fBottom - .5 : fTop + .5;
      final left = b.x1;
      final x = (left - MoveLook.lead).floorToDouble() + .5;
      if (x < c.left || (below ? b.y - knotY : knotY - b.y) < MoveLook.radius) continue;
      final pts = [ui.Offset(x, knotY), ui.Offset(x, b.y), ui.Offset(left, b.y)];
      _back.add(_Back.link(pts, MoveLook.radius, MoveLook.ink, 1, const [MoveLook.dash, MoveLook.gap], MoveLook.width));
      final hole = b.fc - TagLook.holeR - .5;
      if (hole > left) _top.add(_Top.seg(left, b.y, hole, b.y, MoveLook.ink & 0xffffff, MoveLook.width, 1 / LinkLook.topAlpha));
      _top.add(_Top.knot(x, knotY, MoveLook.ink));
      _hits.add(_HitArea.line(LinkHitKind.link, front, back, pts));
      c.debug?.note('옮겨앉기', '${_n(x)},${_n(knotY)} → ${_n(left)},${_n(b.y)}');
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

  /// 소속선(명세 5-1절): 상국 띠 아래(위)로 내려오는 세로 점선 + 끝의 작은 점.
  void _planPart(PaintContext c, _PartIn it) {
    final layout = c.layout, v = c.v;
    final hostRow = it.down ? it.row : it.row2, row = it.down ? it.row2 : it.row;
    if (row >= layout.rowCount || hostRow >= layout.rowCount || !layout.hasBody(row) || !layout.hasBody(hostRow)) return;
    final self = _squares[it.member];
    var x = v.xOf(it.start) + 12; // 둥근 모서리를 피해 띠 안쪽 12px에서 내려온다
    final tabEnd = self == null ? null : _tabRight(c, self);
    if (tabEnd != null && self != null && x < tabEnd + 6 && tabEnd + 8 < self.bandEnd - 6) x = tabEnd + 8;
    if (x < c.left - 4 || x > c.w + 4) return;
    final hostGeo = layout.geo(hostRow), geo = layout.geo(row);
    final hostBottom = v.yOf(layout.rowTop(hostRow) + hostGeo.bandTop + hostGeo.bandHeight);
    final hostTop = v.yOf(layout.rowTop(hostRow) + hostGeo.bandTop);
    final myTop = v.yOf(layout.rowTop(row) + geo.bandTop);
    final myBottom = v.yOf(layout.rowTop(row) + geo.bandTop + geo.bandHeight);
    // 상국 띠 아래에 매달린 이름표 줄 아래에서 내려온다 — 줄의 몫은 줄 생김새가 안다(한 줄 13 · 접었으면 0). 옛 저장소는 실린 줄 수 × 23.
    final hang = hostGeo.hangLanes > 0 ? hostGeo.hangDepth : it.hangLanes * (G.zoneTab + G.zoneGap);
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

  /// 승계선 한 건(명세 3절). 길은 `hv` → 당김 → 내림줄 → 오름줄 → 되돌아감 차례로 고른다.
  void _planLink(PaintContext c, _LinkIn it) {
    final layout = c.layout;
    final qRow = it.down ? it.row : it.row2, pRow = it.down ? it.row2 : it.row;
    if (qRow >= layout.rowCount || pRow >= layout.rowCount || !layout.hasBody(qRow) || !layout.hasBody(pRow)) return;
    final v = c.v, left = c.left, right = c.w;
    final q = _squares[it.from], p = _squares[it.to];
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
    var rad = 6.0;
    if (qRow == pRow) {
      if (it.seam && gq && gp) {
        // 곧바로 이음 — 선 전체가 띠 위 층이라 맞닿아도 틈이 벌어져도 같은 모양이 이어진다(띠 뒤 선은 없다).
        _bridge(c, qe, pf, x1, x2, y1, it, qEdge, pEdge, dim);
        _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, [ui.Offset(x1, y1), ui.Offset(x2, y1)]));
        return;
      }
      if (x2 - x1 < 2) return;
      pts = [ui.Offset(x1, y1), ui.Offset(x2, y1)];
      if (ring) ring = rx - LinkLook.ringR >= qEnd + 3;
      // 네모 하나가 생략된 먼 보기에서는 관문도 두지 않는다(반쪽 다리가 되지 않게).
      if (!it.seam && (gq == gp || pl - qEnd >= 1)) {
        gateOut();
        gateIn();
      }
    } else {
      final k = it.channel / 10;
      var xm = qEnd + 9 + k * 5; // 세로 통로는 선대 띠(꼬리 포함) 바깥에
      final dir = it.down ? 1 : -1;
      final qGeo = layout.geo(qRow), pGeo = layout.geo(pRow);
      final qBottom = v.yOf(layout.rowTop(qRow) + qGeo.bandTop + qGeo.bandHeight);
      final qTop = v.yOf(layout.rowTop(qRow) + qGeo.bandTop);
      final pBottom = v.yOf(layout.rowTop(pRow) + pGeo.bandTop + pGeo.bandHeight);
      final pTop = v.yOf(layout.rowTop(pRow) + pGeo.bandTop);
      final tabQ = q == null ? null : _tabRight(c, q);
      final tabP = p == null ? null : _tabRight(c, p);
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
        var drop = false;
        final xd = _bird ? qe - BirdLook.stationX : (q?.ec ?? (qe - LinkLook.inset));
        if (gq && landOK(xd) && _dropOK(c, qRow, dir, xd, tabQ, it.from, q?.bandStart ?? double.negativeInfinity, q?.bandEnd ?? qe) && _birdClear(qRow, xd)) {
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
            final yS = _bird ? (dir > 0 ? qBottom - 1 - BirdLook.stub : qTop + 1 + BirdLook.stub) : y1 + dir * LinkLook.tipGap;
            final edgeY = dir > 0 ? qBottom : qTop;
            pts = [ui.Offset(xj, yS), ui.Offset(xj, yJ)];
            _gate(c, yS, edgeY + dir * .5, xj, true, edgeY - dir, edgeY, it, qEdge, dim);
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
      // 조감의 내림줄 · 오름줄은 띠 안 이름 · 단추를 비켜야 한다(명세 7-2의 `birdClear` — 지금 연표의 `tr._bnmZ` · js:7654 · 7657).
      var mode = x2 >= xm + 6 ? _Mode.hv : _Mode.back;
      if (mode == _Mode.back) {
        final slid = math.min(xm, pf - 6); // ① 통로를 후대 앞까지 당긴다
        final drop = _bird ? qe - BirdLook.stationX : (q?.ec ?? (qe - LinkLook.inset)); // ② 멸망 네모 밑(위)에서 곧게 나오는 내림줄
        final rise = _bird ? pf + BirdLook.stationX : (p?.fc ?? (pf + LinkLook.inset)); // ③ 거꾸로 건국 네모로 드는 오름줄
        if (slid >= qEnd + 4 && _clearAt(qRow, slid, it.from) && _clearAt(pRow, slid, it.to)) {
          xm = slid;
          mode = _Mode.hv;
        } else if (okQ && okP && pf - 6 >= drop && _dropOK(c, qRow, dir, drop, tabQ, it.from, q?.bandStart ?? double.negativeInfinity, q?.bandEnd ?? qe) && _birdClear(qRow, drop) && _clearAt(pRow, drop, it.to)) {
          xm = drop;
          mode = _Mode.drop;
        } else if (okQ && (_bird ? (okP && _birdClear(pRow, rise)) : (p?.showF ?? true)) && !it.unknownP && rise >= qe + 6 && rise >= x1 + 8 && _dropOK(c, pRow, -dir, rise, tabP, it.to, p?.bandStart ?? pf, p?.bandEnd ?? double.infinity) && _clearAt(qRow, (qe + rise) / 2, it.from, (rise - qe) / 2)) {
          xm = rise;
          mode = _Mode.rise;
        }
      }
      switch (mode) {
        case _Mode.hv:
          pts = [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, y2), ui.Offset(x2, y2)];
          if (ring) ring = rx - LinkLook.ringR >= xm + 3;
          gateOut();
        case _Mode.rise:
          final yE = _bird ? (dir > 0 ? pTop + 1 + BirdLook.stub : pBottom - 1 - BirdLook.stub) : y2 - dir * LinkLook.tipGap;
          final edgeY = dir > 0 ? pTop : pBottom;
          pts = [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, yE)];
          gateOut();
          _gate(c, yE, edgeY - dir * .5, xm, true, edgeY + dir, edgeY, it, pEdge, dim);
          _dropZone(c, pRow, dir > 0, xm);
          if (ring) {
            ring = false;
            final gy = edgeY - dir * (0.5 + 3.6);
            if (dir > 0 ? gy - 3.6 >= qBottom + 1 : gy + 3.6 <= qTop - 1) _back.add(_Back.ring(xm, gy, qColor, lineAlpha));
          }
        case _Mode.drop:
          final yS = _bird ? (dir > 0 ? qBottom - 1 - BirdLook.stub : qTop + 1 + BirdLook.stub) : y1 + dir * LinkLook.tipGap;
          final edgeY = dir > 0 ? qBottom : qTop;
          pts = [ui.Offset(xm, yS), ui.Offset(xm, y2), ui.Offset(x2, y2)];
          if (ring) ring = rx - LinkLook.ringR >= xm + 3;
          _gate(c, yS, edgeY + dir * .5, xm, true, edgeY - dir, edgeY, it, qEdge, dim);
          _dropZone(c, qRow, dir < 0, xm);
        case _Mode.back:
          // 되돌아가는 길: 줄 사이의 빈 곳(책갈피 탭 위의 틈)으로 돌아 후대의 건국 네모로 든다.
          final upGap = pGeo.bandTop - _tabOf(c, pRow);
          final nextGap = _gapBelow(c, pRow);
          final up = v.yOf(layout.rowTop(pRow) + pGeo.bandTop - _tabOf(c, pRow)) - math.max(2, upGap / 2);
          final down = v.yOf(layout.rowTop(pRow) + pGeo.height) + math.max(2, nextGap / 2);
          final xl = pl - 9 - k * 5 - (ring ? 5 : 0); // 고리가 있으면 도착 통로를 고리만큼 더 왼쪽에
          List<ui.Offset> via(double gy) =>
              [ui.Offset(x1, y1), ui.Offset(xm, y1), ui.Offset(xm, gy), ui.Offset(xl, gy), ui.Offset(xl, y2), ui.Offset(x2, y2)];
          pts = via(dir > 0 ? up : down);
          if ((dir > 0 ? upGap : nextGap) < 3 && (dir > 0 ? nextGap : upGap) >= 3) pts = via(dir > 0 ? down : up);
          rad = 5;
          gateOut();
      }
      if (mode != _Mode.rise) gateIn();
    }
    _back.add(_Back.link(pts, rad, qColor, lineAlpha, it.beat, it.thin ? _thinW : LinkLook.width));
    _hits.add(_HitArea.line(LinkHitKind.link, it.from, it.to, pts));
    if (ring) _back.add(_Back.ring(rx, y2, qColor, lineAlpha));
  }

  /// 내림줄 · 오름줄이 띠 안을 지나는 자리(반너비 5px)는 사건 글자가 비켜 간다(명세 3-6 다 · 3-5 ①).
  /// [first]면 첫 글줄만, 아니면 둘째 글줄부터 — 네모가 첫 글줄 위쪽에 있어 위로 나가면 첫 글줄, 아래로 나가면 둘째 글줄부터다.
  void _dropZone(PaintContext c, int row, bool first, double xm) {
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
  /// 인물 막대(구역 37), 매달린 속국 이름표(구역 16 — 세로 끈은 빼고), 구역 탭(구역 17)을 제 가로 구간으로 본다. 바탕 문화의 이름 단은 선이 지나가는 바탕이라 보지 않는다.
  bool _lowerBusy(PaintContext c, int row, double xc) {
    for (final (a, b) in _lowerSpans.putIfAbsent(row, () => _collectLower(c, row))) {
      if (a < xc + 10 && b > xc - 10) return true;
    }
    return false;
  }

  List<(double, double)> _collectLower(PaintContext c, int row) {
    final v = c.v, out = <(double, double)>[];
    for (final d in c.scene.draw) {
      if (d.isCover) continue;
      final t = d.tile;
      final origin = t.origin.toDouble();
      for (int i = 0; i < t.cellCount; i++) {
        if (t.cellRow[i] != row) continue;
        final k = t.cellKindOf(i);
        if (k != CellKind.organ && k != CellKind.figure && k != CellKind.dep) continue;
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

  // ───────────────────────── 맞히기 ─────────────────────────

  /// 단추 · 네모 · 선을 눌렀는가(배치 px). 위에 있는 것부터 본다 — 단추 → 네모 → 선.
  LinkHit? hitLinks(double x, double y) {
    for (final kind in [LinkHitKind.flag, LinkHitKind.scopeButton, LinkHitKind.memberButton, LinkHitKind.hangButton, LinkHitKind.square, LinkHitKind.link]) {
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
    for (final b in _back) {
      switch (b.kind) {
        case _Back.kPart:
          _vLine(c, b.pts[0].dx, b.pts[0].dy, b.pts[1].dy, withAlpha(b.color, b.alpha), 1.3, LinkLook.partDash, LinkLook.partGap, b.pts[0].dy);
          c.sprites.add(Sprites.fill, b.pts[0].dx - 2, b.tip - 2, withAlpha(b.color, b.dotAlpha), 4 / 7);
          c.debug?.note('소속선', '${_n(b.pts[0].dx)},${_n(b.pts[0].dy)},${_n(b.pts[1].dy)}');
        case _Back.kRing:
          _sprites.add(LinkSprites.ring275, b.pts[0].dx - LinkSprites.ringBox / 2, b.pts[0].dy - LinkSprites.ringBox / 2, withAlpha(b.color, b.alpha));
          c.debug?.note('고리', '${_n(b.pts[0].dx)},${_n(b.pts[0].dy)}');
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

  /// 검사 기록에 쓰는 0.1px 수(지금 연표의 cx와 같은 해상도).
  static String _n(double v) => v.toStringAsFixed(1);

  /// 검사 기록에 쓰는 색(rrggbb).
  static String _hex(int argb) => (argb & 0xffffff).toRadixString(16).padLeft(6, '0');

  /// 띠 위에 얹히는 것(문 → 관문 · 다리 · 고리 · 합류 조각 → 네모 → 단추).
  void paintFront(PaintContext c, Tile t) {
    if (t != _host || c.hide.contains('links')) return;
    for (final p in _top) {
      if (p.kind != _Top.kDoor) continue;
      c.quads.add(p.x1, p.y1, p.x2, p.y2, withAlpha(Look.paper, p.alpha));
      c.debug?.note('문', '${_n(p.x1)},${_n(p.y1)},${_n(p.x2 - p.x1)},${_n(p.y2 - p.y1)} 짙기 ${p.alpha.toStringAsFixed(2)}');
    }
    for (final p in _top) {
      switch (p.kind) {
        case _Top.kSeg:
          final argb = withAlpha(0xff000000 | p.color, LinkLook.topAlpha * p.alpha);
          if (p.y1 == p.y2) {
            _hLine(c, p.x1, p.x2, p.y1, argb, p.width, 0, 0, 0);
          } else {
            _vLine(c, p.x1, p.y1, p.y2, argb, p.width, 0, 0, 0);
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
    _marks.paint(c, dimPicked);
  }

  /// 이 판의 펼친 폴더(매다는 실 — 처음 물을 때 한 번 센다).
  List<FolderSpot>? _folders;

  /// 매다는 실(리메이크 조각 ③ · 설계 4-1 '실의 규칙 하나'): 펼친 폴더 안 꼬리표의 구멍에서 곧게 올라가 매듭(지름 3)에 걸린다 —
  /// 그릇 첫 줄은 몸통 윗변에(그릇에 매달림), 둘째 줄부터는 띠 윗변 위 (위 틈 − 3)에(줄 사이 매듭 — 위 꼬리표를 가로지르지 않는다).
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
    final knot = sq.row == f.firstRow ? f.body + 1 : (bandTop - c.layout.tabOf(sq.row) + FolderLook.knotDrop).roundToDouble();
    final x = (sq.fc - .5).roundToDouble(), end = (sq.y - TagLook.holeR - 1).roundToDouble();
    if (end - knot < 3) return;
    c.quads.add(x, knot + 2, x + 1, end, color);
    // 매듭 = 지름 3의 점: 1배 픽셀에서 가운데 십자는 짙게, 네 귀는 옅게(둥글게 보인다).
    c.quads.add(x - 1, knot - 1, x + 2, knot + 2, withAlpha(color, .35 * ((color >>> 24) / 255)));
    c.quads.add(x - 1, knot, x + 2, knot + 1, color);
    c.quads.add(x, knot - 1, x + 1, knot, color);
    c.quads.add(x, knot + 1, x + 1, knot + 2, color);
    c.stats.shapes++;
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
    if (sq.showF) {
      if (sq.unknownStart) {
        _sprites.add(LinkSprites.dashRing, sq.fc - LinkSprites.dashBox / 2, sq.y - LinkSprites.dashBox / 2, edge);
      } else {
        final ring = sq.band == emphasis?.look.band ? Look.ink : mixSrgb(Look.ink, Look.paper, .45);
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

/// 옮겨 앉기의 실 · 매듭(리메이크 2부 · 결정 #3 A · 목업 d3-a): 먹 50 · 굵기 1.5 · 점선 3 2 · 굽이 반지름 6 · 뒤 토막 왼쪽 6 앞에서 곧게 · 매듭 지름 4.
abstract final class MoveLook {
  static const ink = 0xff808080, width = 1.5, dash = 3.0, gap = 2.0, radius = 6.0, lead = 6.0, knot = 4.0;
}

/// 맞힌 것의 종류.
enum LinkHitKind { square, link, memberButton, scopeButton, hangButton, flag }

/// 맞히기의 결과 — 총괄이 입력에 잇는다.
class LinkHit {
  const LinkHit(this.kind, {this.band = 0, this.to = 0, this.scope = ''});

  final LinkHitKind kind;

  /// 눌린 것이 딸린 띠 번호(선이면 선대 · 소속선이면 상국).
  final int band;

  /// 승계선이면 후대 띠 · 소속선이면 속국의 띠 번호.
  final int to;

  /// 대범위 단추면 그 대범위의 uid.
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

/// 관계선의 값(명세 1절 · css). 모두 px.
abstract final class LinkLook {
  static const sq = 7.0, half = 3.5, bw = 1.0, door = 4.4, radius = 10.0;

  /// 네모 가운데의 띠 안쪽 여백 = G.bw + 2 + G.sq/2.
  static const inset = 6.5;
  /// 관문의 가장 긴 길이: 네모 + 1px ↔ 테두리 밖 0.5px = bw 1 + 1 + 비키기 최대(직접이 아닌 이음매 6px) + 0.5 — js의 GATE_MAX와 같은 식.
  /// 5.5(3px 비키기 기준)로 두면 6px 비켜 앉은 이음매의 다리(상 → 서주 같은 간접)가 아예 그려지지 않는다.
  /// 꼬리표 갈래 E의 키에 맞춘 귀(2026-10-15)부터 구멍은 띠 시작에서 7 ~ 14(귀 + 2)라 구멍 왼쪽 테까지 최대 11.5 — 그보다 조금 넉넉히 12.
  static const gateMax = 12.0, sqClear = 1.5, tipGap = 4.5, fade = 44.0;
  /// 부분 승계는 가는 실선 하나(1px — 픽셀 칸에 맞춰 긋는다 `_crisp`). 예전의 늘 세 가닥(정도만큼 진하게)은 선이 셋이라 난잡해 버렸다(2026-10-13 감독 'A 한 줄 · 짙기 80%').
  static const thinW = 1.0;
  static const width = 1.6, ringR = 2.75, joinH = 1.6;
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
  _PartIn(this.row, this.row2, this.start, this.member, this.host, this.a, this.hangLanes, this.color);

  factory _PartIn.read(TileSection s, int i, double origin) => _PartIn(
    s.u(Tile.itemRow)[i], s.u(Tile.itemRow2)[i], origin + s.f(Tile.itemX0)[i],
    s.u(Tile.itemRef)[i], s.u(Tile.itemB)[i], s.u(Tile.itemA)[i], s.u(Tile.itemC)[i], s.u(Tile.itemColor)[i],
  );

  final int row, row2, member, host, a, hangLanes, color;
  final double start;

  bool get down => a & 1 != 0;
  bool get refuted => a & 2 != 0;
}

/// 띠 뒤 층의 한 조각.
class _Back {
  _Back(this.kind, this.pts, this.rad, this.color, this.alpha, this.beat, this.width, this.tip, this.dotAlpha);
  static const kLink = 0, kPart = 1, kRing = 2, kBundleRing = 3;

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
