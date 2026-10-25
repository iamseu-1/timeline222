import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' show Dim, Emphasis;
import '../layout.dart' show G, ScopeState;
import '../text_paragraph.dart';
import '../tile.dart';
import 'bands.dart';
import 'context.dart';
import 'links.dart';
import 'look.dart';
import 'small_tags.dart';

// 대범위: 테두리(구역 23) · 기간의 짙은 구간(24) · 이름표와, **꺼 두어도 보이는 둘** — 본국 띠의 할거기 칠(25 · z-hollow)과
// 소속 펼치기 단추(26) · '▸ 〈성격〉 n' 단추(27). 값의 뜻은 docs/계약-아카이브-3단계.md 6-10절, 그리기 규칙은 docs/명세-3단계/04-관계선.md 6절.
//
// 켠 대범위에만 줄이 옮겨 가므로(명세 6-1) 구역 23 · 24는 **켠 상태에만 실려 온다** — 층은 실려 온 것을 그리기만 하고 켜고 끄기를 스스로 판단하지 않는다.
// 층 차례(명세 0절): 1층 테두리는 [paintTile](띠보다 뒤), 할거기 칠은 띠 채움 바로 뒤 · 칸 앞의 [paintOverBands], 단추는 띠 위라 관계선 층의 앞 판이 [ScopeMarks]로 부른다.

/// 대범위 테두리의 값(명세 1절 · 6-2 · 6-3 · css 1617~1658). 모두 px.
abstract final class ScopeLook {
  /// 안쪽 그릇 = 상자(리메이크 2부 포개짐 · 목업 서고 box): 모따기 6 · 테 먹 25 · 뚜껑 먹 4% · 라벨은 왼쪽 8.
  static const boxCham = 6, boxEdge = .25, boxLid = .04, boxLabelX = 8.0;

  /// 그릇 안 이름표 시대의 둘째 탭(목업 서고 ftab plain): 높이 16 · 글 9.5 · 좌우 6 · 앞 탭과 4.
  static const labelTabH = 16.0, labelTabText = 9.5, labelTabPad = 6.0, labelTabGap = 4.0;

  /// 가로 여백. 머리(16 · 조감 12)와 발(6 · 조감 4)은 줄 쌓기가 주는 `layout.metrics.scopeHead` · `scopeFoot`을 쓴다.
  static const padX = 8.0;

  /// 테두리: 1px · 모서리 12(조감 8) · 바탕은 대범위 색 9% · 테두리색은 --edge의 55%.
  static const radius = 12.0, birdRadius = 8.0, fillPct = .09, edgePct = .55;

  /// 기간 칸: 바탕 11% · 좌우 1px 파선(--edge 40%).
  static const spanFillPct = .11, spanEdgePct = .40, spanDash = 3.0, spanGap = 3.0;

  /// 이름표: 위 1(매달리면 2) · 왼쪽 8 · 높이 14 · 좌우 여백 6 · 모서리 4 · 바탕은 대범위 색 24%를 섞은 종이색.
  static const labelTop = 1.0, labelHungTop = 2.0, labelLeft = 8.0, labelHeight = 14.0, labelPad = 6.0, labelRadius = 4.0;
  static const labelTextSize = 10.0, kindTextSize = 9.0, kindAlpha = .75, labelTintPct = .24;
  static const birdLabelTextSize = 9.0, birdKindTextSize = 8.0, birdLabelTop = 0.5, birdLabelHeight = 11.0;

  /// 할거기 칠: 세로 그라디언트(위아래 2px 투명 → 7px부터 종이색 92%)와 좌우 1px 파선(대범위 색 70% + 글자색, 짙기 .6).
  static const hollowFade = 7.0, hollowClear = 2.0, hollowPaper = .92, hollowEdgeAlpha = .6;
}

/// 그릇 폴더의 값(리메이크 조각 ③ · 설계 4-1 '가장 바깥 그릇' · 목업 blend.js folder · d2-b의 ftabH · handle · packTags). 모두 px.
/// 조감이 아닐 때 켠 대범위(그릇)는 옛 둥근 테두리 대신 폴더로 그린다 — 집합 보기의 판 둘레와 조감은 예전 그대로다.
abstract final class FolderLook {
  /// 몸통: 둥근 10(어깨 탭이 선 왼쪽 위 · 화면에 잘린 쪽은 0) · 칠 = 그릇 색 9% · 테 = 그릇 색 55%와 종이 · 안쪽 겹선(2 안 · 둥근 8 · 먹 12).
  static const radius = 10.0, fillPct = .09, edgePct = .55, inset = 2.0, innerAlpha = .12;

  /// 어깨 탭: 높이 [G.folderTab] · 어깨 7 · 라벨 종이는 어깨 + 2 · 손잡이 뒤로 2 + 어깨. 화면에 왼쪽이 잘리면 그림판 왼쪽 + 8에 선다.
  static const shoulder = ScopeSprites.shoulderW, clipInset = 8.0;

  /// 라벨 종이(재료 하나 — 흰 종이 + 1px 먹 40): 높이 15(몸통 윗변 위 2) · 좌우 6 · 이름 11 굵게 먹 85 · 수 10.5 먹 50(이름 뒤 5).
  static const labelH = 15.0, labelPad = 6.0, nameSize = 11.0, countSize = 10.5, countGap = 5.0;


  /// 접힌 폴더의 작은 꼬리표: 높이 13의 가운데가 몸통 윗변 위 8.5(목업 ty = Y − 15) · 탭 오른쪽 4부터 · 몸통 오른쪽 끝 6 앞까지.
  static const tagRise = 8.5, tagFrom = 4.0, tagEnd = 6.0;

  /// 풀린 그릇의 열쇠표(목업 blend.js tags): 높이 12 · 띠 윗변 위 2 · 왼쪽 둥근 끝 6 · 구멍 6 · 글 8.5 굵게 먹 65(왼쪽 11) · 띠 시작 + 16에서 실이 45°로 오른다.
  static const keyH = 12.0, keyRise = 2.0, keyR = 6.0, keyFrom = 16.0, keyTextX = 11.0, keySize = 8.5, keyGap = 4.0;

  /// 매다는 실 · 매듭(설계 4-1 '실의 규칙 하나'): 먹 45(고른 띠는 먹) · 그릇 첫 줄은 몸통 윗변에, 둘째 줄부터는 띠 윗변 위 (위 틈 − 3)에 매듭.
  static const threadPct = .45, knotDrop = 3.0;
}

/// 대범위 테두리 하나의 세로 자리(명세 6-2절의 `_scopeBox`).
class ScopeBox {
  const ScopeBox(this.top, this.height, this.firstRow, this.lastRow, {double? body, this.depth = 0}) : body = body ?? top;
  final double top, height;
  final int firstRow, lastRow;

  /// 포개짐의 깊이(0 폴더 · 1 이상 상자 — 리메이크 2부).
  final int depth;

  /// 몸통 윗변(배치 px) — 폴더면 어깨 탭 아래([top] + [G.folderTab]), 옛 테두리면 [top]과 같다.
  final double body;
}

/// 켠 대범위 하나 — 타일에서 읽은 구역 23과 그 세로 자리.
class ScopeIn {
  ScopeIn(this.id, this.row, this.row2, this.start, this.end, this.host, this.color, this.a, this.name, this.label, {this.count = 0, this.uid = ''});
  final int id, row, row2, host, color, a;

  /// 그릇의 uid(구역 23 text2의 앞 — 리메이크 2부 포개짐). 옛 저장소는 빈 글(그리는 쪽이 첫 줄로 찾는다).
  final String uid;

  /// 구성 띠 수(항목의 b — 리메이크 조각 ③ · 폴더 라벨의 '이름 수'). 0이면 옛 저장소라 수를 쓰지 않는다.
  final int count;
  final double start, end;
  final String name, label;

  /// 본국 띠 아래에 매달렸는가(`hung`) · 본국이 끝난 뒤 생겼는가(`afterHost`) · 기간이 '짐작'인가.
  bool get hung => a & 1 != 0;
  bool get afterHost => a & 2 != 0;
  bool get guessed => a & 4 != 0;

  /// **집합 보기 판의 둘레**인가(a 비트 8 — 내보내기 `export/scopes.mjs` · 10건 6 결정 2 A): 가로는 화면 전체(기간이 아니라 보는 방법)라
  /// 양쪽 테두리 없이 모서리를 펴고, 이름표는 물러나지 않는다(지금 연표의 `_scopeX` — 판이면 `mode: 'full'`). 이름표 글은 '판 이름'과
  /// '집합 보기 · 트랙 n · 나라 m', 짙은 세로 구간은 판의 기간이다(기간 없는 판은 짐작 비트 4가 서 구간이 없다).
  bool get board => a & 8 != 0;

  /// 폴더로 그리는가(리메이크 조각 ③) — 조감과 집합 보기의 판 둘레는 옛 테두리다.
  bool folderIn(PaintContext c) => !c.layout.bird && !board;

  /// 판 이름표를 누른 맞히기(`Hit(HitKind.scopeButton)`)의 참조 — 대범위 uid가 아니라 '집합 보기 목록을 연다'는 표시(지금 연표의 data-board-name).
  static const boardRef = '__board';
}

/// 대범위 테두리의 자리 셈(명세 6-2절). 두 층(테두리 · 부흥선 묶음)이 함께 쓴다.
ScopeBox? scopeBoxOf(PaintContext c, ScopeIn it) {
  final layout = c.layout;
  // 리메이크 2부 포개짐: 켠 그릇은 묶음 줄 집합에서 셈한 자리(머리 · 발 · 깊이 — layout.scopeSpanOf). 폴더(깊이 0)의 몸통은 어깨 탭 아래, 상자(깊이 1 이상)는 뚜껑 아래.
  final uid = scopeUidOf(c, it);
  if (it.folderIn(c) && uid.isNotEmpty && layout.scopeOnOf(uid) != null) {
    final span = layout.scopeSpanOf(uid);
    if (span == null) return null;
    final depth = layout.scopeDepthOf(uid);
    return ScopeBox(span.top, span.bottom - span.top, span.first, span.last, body: span.top + (depth == 0 ? G.folderTab : G.boxLid), depth: depth);
  }
  int fv = -1, lv = -1;
  for (int r = it.row; r <= it.row2 && r < layout.rowCount; r++) {
    if (!layout.isVisible(r)) continue;
    if (fv < 0) fv = r;
    lv = r;
  }
  if (fv < 0) return null;
  int prev = -1;
  for (int r = fv - 1; r >= 0; r--) {
    if (layout.isVisible(r)) {
      prev = r;
      break;
    }
  }
  // 폴더(리메이크 조각 ③)는 늘 제 어깨 탭이 있어 본국 줄에 매달리지 않는다 — 머리 · 발도 폴더 값(줄 배치의 _scopePadOf와 같은 값).
  final folder = it.folderIn(c);
  final hostRow = it.host == 0 ? -1 : _rowOfBand(c, it.host);
  final hung = !folder && it.hung && prev >= 0 && prev == hostRow;
  final metrics = layout.metrics;
  // 띠 위 틈의 띠 몫(꼬리표 갈래 E — 5, 그릇의 줄 + 10 · 솟는 줄 + 15 · 접힌 묶음 · 그 밖 줄 · 조감은 0)을 줄 배치에서 그대로.
  final tab = layout.tabOf(fv);
  final head = layout.bird ? metrics.scopeHead : G.folderHead, foot = layout.bird ? metrics.scopeFoot : G.folderFoot;
  final top = hung ? layout.rowTop(fv) : layout.rowTop(fv) + layout.geo(fv).bandTop - tab - head;
  final height = layout.rowTop(lv) + layout.geo(lv).height + foot - top;
  return ScopeBox(top, height, fv, lv, body: folder ? top + G.folderTab : top);
}

/// 그 그릇의 uid — 구역 23 text2의 앞(리메이크 2부), 없으면(옛 저장소) 첫 줄이 든 켠 변형.
String scopeUidOf(PaintContext c, ScopeIn it) => it.uid.isNotEmpty ? it.uid : c.layout.scopeUidOfRow(it.row);

/// 펼친 폴더 하나의 화면 자리(px) — 매다는 실이 쓴다(관계선 층의 구멍 옆).
class FolderSpot {
  const FolderSpot(this.left, this.right, this.body, this.bottom, this.firstRow, {this.depth = 0});
  final double left, right, body, bottom;
  final int firstRow;

  /// 포개짐의 깊이(상자는 1 이상 — 실은 구멍을 품은 것 가운데 가장 안쪽에 매달린다).
  final int depth;
}

/// 이 장면의 **펼친** 폴더(켠 대범위 가운데 가지가 펼쳐진 것 — 조감 · 집합 보기 판 둘레는 빼고). 접힌 폴더에는 띠가 없어 실도 없다.
List<FolderSpot> openFolders(PaintContext c) {
  final out = <FolderSpot>[];
  if (c.layout.bird) return out;
  final v = c.v;
  for (final it in ScopeLayer.readScopes(c).values) {
    if (!it.folderIn(c)) continue;
    final uid = scopeUidOf(c, it);
    if (uid.isNotEmpty && c.layout.scopeStateOf(uid) != ScopeState.open) continue;
    final box = scopeBoxOf(c, it);
    if (box == null) continue;
    out.add(FolderSpot(v.xOf(it.start) - ScopeLook.padX, v.xOf(it.end) + ScopeLook.padX, v.yOf(box.body).roundToDouble(), v.yOf(box.top + box.height), box.firstRow, depth: box.depth));
  }
  return out;
}

/// 본국 띠가 놓인 줄 — 테두리 항목은 본국 띠의 번호만 싣는다(계약 6-10절). 줄을 못 찾으면 −1.
int _rowOfBand(PaintContext c, int band) {
  for (final d in c.scene.draw) {
    final t = d.tile;
    for (int i = 0; i < t.bandCount; i++) {
      if (t.bandId[i] == band) return t.bandRow[i];
    }
  }
  return -1;
}

class ScopeLayer extends TileLayer {
  /// 구역 번호(계약 6-10절).
  static const secScope = 23, secSpan = 24, secHollow = 25;

  /// 그릇 안 이름표 시대의 둘째 탭(리메이크 2부 — 내보내기 `export/scopes.mjs` · row · row2 = 그 그릇의 구역 23과 같음 · text2 = 시대 구분 uid).
  static const secLabel = 53;

  /// 밝기 상태(총괄이 이어 준다 — 없으면 중립).
  Emphasis? emphasis;

  final sprites = ScopeSprites();
  final _done = <int>{};
  final _edge = <int, int>{};
  final _labelLook = <int, TextLook>{}, _kindLook = <int, TextLook>{};
  Tile? _host;
  bool _bird = false;

  /// 이번 판에 그린 집합 보기 판 이름표의 자리(없으면 null) — 누르면 집합 보기 목록(지금 연표의 `onBoardName`).
  ui.Rect? _boardLabel;

  /// 그 자리가 집합 보기 판 이름표 위인가(관계선 층과 같은 화면 좌표).
  bool hitBoardLabel(double x, double y) => _boardLabel?.contains(ui.Offset(x, y)) ?? false;

  /// 이번 판에 그린 폴더 탭의 누를 자리 — (자리, 대범위 uid, 바꿀 상태: 1 펼침 · 2 접힘 · 3 풀림). 라벨은 펼침 ↔ 접힘(세 상태는 오른쪽 클릭 메뉴).
  final _folderHits = <(ui.Rect, String, int)>[];

  /// 그 자리의 폴더 탭(대범위 uid, 바꿀 상태 1 펼침 · 2 접힘 · 3 풀림 — [ScopeState]의 차례 + 1). 없으면 null.
  (String, int)? hitFolder(double x, double y) {
    final at = ui.Offset(x, y);
    for (final h in _folderHits.reversed) {
      if (h.$1.contains(at)) return (h.$2, h.$3);
    }
    return null;
  }

  /// 이번 판에 그린 그릇(폴더 · 상자)의 자리 — 오른쪽 클릭 메뉴가 그 안에서 세 상태를 고른다
  /// (리메이크 2부 · 감독 2026-10-15 "그릇 옆 버튼 3개 … 그냥 우클릭으로 · 우클릭한 위치가 그 그릇의 안이면"). (자리, uid, 이름, 지금 상태, 깊이).
  final _scopeAreas = <(ui.Rect, String, String, ScopeState, int)>[];

  /// 그 자리를 품은 그릇 가운데 가장 안쪽(깊이가 큰 것 — 같으면 나중에 그린 것) — (uid, 이름, 지금 상태). 없으면 null.
  (String, String, ScopeState)? scopeAt(double x, double y) {
    final at = ui.Offset(x, y);
    (ui.Rect, String, String, ScopeState, int)? best;
    for (final a in _scopeAreas) {
      if (!a.$1.contains(at)) continue;
      if (best == null || a.$5 >= best.$5) best = a;
    }
    return best == null ? null : (best.$2, best.$3, best.$4);
  }

  TextLook? _folderName, _folderCount;

  /// 폴더 탭 위의 이름 종이(라벨 · 손잡이 · 접힌 폴더의 작은 꼬리표)는 날짜 눈금(띠 위의 세로 점선)보다 위라 표식 판에서 그린다 —
  /// 뒤 판의 [paintTile]이 자리를 셈해 여기에 모아 두면 [paintLabels]가 그린다(폴더마다 하나라 닫힘꼴로 둔다).
  final _labels = <void Function(PaintContext)>[];

  /// 모아 둔 폴더 탭의 이름 종이를 그린다(그리개의 표식 판 — 날짜 눈금 위 · 관계선 앞 판 앞).
  void paintLabels(PaintContext c) {
    for (final job in _labels) {
      job(c);
    }
    _labels.clear();
  }

  int _edgeOf(int color) => _edge[color] ??= mixOklab(0xff000000 | color, Look.ink, .84);

  @override
  void setScale(double scale) => sprites.setScale(scale);

  @override
  void flush(PaintContext c) => sprites.flush(c.canvas);

  @override
  void beginFrame(PaintContext c) {
    _done.clear();
    _boardLabel = null;
    _folderHits.clear();
    _scopeAreas.clear();
    _labels.clear();
    _host = null;
    _bird = c.layout.bird;
    for (final d in c.scene.draw) {
      if (!d.isCover && d.alpha >= 1) {
        _host = d.tile;
        break;
      }
    }
    if (_host == null && c.scene.draw.isNotEmpty) _host = c.scene.draw.first.tile;
  }

  /// 띠보다 뒤: 대범위 테두리(23) · 기간 칠(24) · 이름표. 선 하나가 여러 타일에 실려 오므로 이 장면의 첫 온전한 타일에서 한 번만.
  @override
  void paintTile(PaintContext c, Tile t) {
    if (t != _host || c.hide.contains('scopes')) return;
    final items = readScopes(c);
    if (items.isEmpty) return;
    // 기간 칠(24)은 시각을 a~d에 담을 수 없어 따로 온다 — 줄 범위가 테두리와 같아 그 줄로 짝을 찾는다(계약 6-10절의 덧붙임).
    final spans = <int, (double, double)>{};
    for (final d in c.scene.draw) {
      final s = d.tile.section(secSpan);
      if (s.count == 0) continue;
      final row = s.u(Tile.itemRow), row2 = s.u(Tile.itemRow2), x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
      final origin = d.tile.origin.toDouble();
      for (int i = 0; i < s.count; i++) {
        final key = row[i] * 1000003 + row2[i];
        final old = spans[key];
        final lo = origin + x0[i], hi = origin + x1[i];
        spans[key] = old == null ? (lo, hi) : (math.min(old.$1, lo), math.max(old.$2, hi));
      }
    }
    for (final it in items.values) {
      _paintScope(c, it, spans[it.row * 1000003 + it.row2]);
    }
  }

  /// 이 장면에 실려 온 대범위 테두리(구역 23) — 본국 띠 번호로 찾을 수 있게 항목 번호를 열쇠로 돌려준다.
  static Map<int, ScopeIn> readScopes(PaintContext c) {
    final out = <int, ScopeIn>{};
    for (final d in c.scene.draw) {
      final t = d.tile;
      final s = t.section(secScope);
      if (s.count == 0) continue;
      final id = s.u(Tile.itemId), row = s.u(Tile.itemRow), row2 = s.u(Tile.itemRow2), ref = s.u(Tile.itemRef);
      final color = s.u(Tile.itemColor), a = s.u(Tile.itemA), name = s.u(Tile.itemName), text2 = s.u(Tile.itemText2);
      final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1), flags = s.u(Tile.itemFlags), b = s.u(Tile.itemB);
      final origin = t.origin.toDouble();
      for (int i = 0; i < s.count; i++) {
        final old = out[id[i]];
        final lo = origin + x0[i], hi = origin + x1[i];
        if (old == null) {
          // text2 = 'uid␟성격'(리메이크 2부) · ␟이 없으면 옛 저장소(성격만).
          final raw = t.text(text2[i]), cut = raw.indexOf('\u001f');
          out[id[i]] = ScopeIn(id[i], row[i], row2[i], lo, hi, ref[i], color[i], a[i], t.text(name[i]), cut >= 0 ? raw.substring(cut + 1) : raw, count: b[i], uid: cut >= 0 ? raw.substring(0, cut) : '');
        } else {
          // 타일에 잘려 온 조각은 잘리지 않은 쪽이 제 끝이다(계약 6-10절 끝).
          final start = flags[i] & Tile.clipLeft == 0 ? lo : math.min(old.start, lo);
          final end = flags[i] & Tile.clipRight == 0 ? hi : math.max(old.end, hi);
          out[id[i]] = ScopeIn(old.id, old.row, old.row2, start, end, old.host, old.color, old.a, old.name, old.label, count: old.count, uid: old.uid);
        }
      }
    }
    return out;
  }

  void _paintScope(PaintContext c, ScopeIn it, (double, double)? span) {
    if (!_done.add(it.id)) return;
    if (it.folderIn(c)) {
      _paintFolder(c, it, span);
      return;
    }
    final box = scopeBoxOf(c, it);
    if (box == null) return;
    final v = c.v;
    // 집합 보기의 판 둘레는 가로 전체(지금 연표의 `_scopeX` — 판이면 { xl: −2, xr: W + 2 }).
    final xl = it.board ? c.left - 2 : v.xOf(it.start) - ScopeLook.padX, xr = it.board ? c.w + 2 : v.xOf(it.end) + ScopeLook.padX;
    if (xr < c.left - 2 || xl > c.w + 2) return;
    final left = math.max(xl, c.left - 1);
    final width = math.max(4.0, math.min(xr, c.w + 1) - left);
    final top = v.yOf(box.top), height = box.height;
    if (top > c.h || top + height < c.head) return;
    final clipL = xl < c.left - 1, clipR = xr > c.w + 1;
    final color = 0xff000000 | it.color;
    // css 1627 — 강조 밖의 테두리는 .45(`.tl-scope.is-dim`). 고르기에는 흐림 규칙이 없다.
    // 강조에 든 대범위(`is-match`)는 1이어야 하지만 `ScopeIn`에 uid가 없어 아직 가리지 못한다 — 보고의 '총괄이 이어 줄 것'.
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    final fill = withAlpha(color, ScopeLook.fillPct * dim);
    final edge = withAlpha(_edgeOf(it.color), ScopeLook.edgePct * dim);
    final radius = _bird ? ScopeLook.birdRadius : ScopeLook.radius;
    final rl = clipL ? 0.0 : radius, rr = clipR ? 0.0 : radius;
    final rt = it.hung ? 0.0 : 1.0; // 본국 띠에 매달리면 위 테두리와 위 모서리가 없다
    _roundRect(c, left, top, left + width, top + height, rl * rt, rr * rt, rr, rl, fill);
    // 테두리: 곧은 네 변(네모 묶음) + 모서리의 1px 호.
    if (!it.hung) _edgeLine(c, true, left + rl * rt, left + width - rr * rt, top, edge);
    _edgeLine(c, true, left + rl, left + width - rr, top + height - 1, edge);
    if (!clipL) _edgeLine(c, false, top + rl * rt, top + height - rl, left, edge);
    if (!clipR) _edgeLine(c, false, top + rr * rt, top + height - rr, left + width - 1, edge);
    _arcs(c, left, top, left + width, top + height, rl * rt, rr * rt, rr, rl, edge);
    c.stats.shapes++;
    c.debug?.note(
      '대범위',
      '${it.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${width.toStringAsFixed(1)},${height.toStringAsFixed(1)}'
          '${it.hung ? ' 매달림' : ''}${clipL ? ' 왼쪽잘림' : ''}${clipR ? ' 오른쪽잘림' : ''}',
    );
    // 기간의 짙은 구간(명세 6-3): 짐작한 기간이거나 테두리 전체와 같으면 칠하지 않는다.
    if (span != null && !it.guessed) {
      final bw = clipL ? 0.0 : 1.0;
      final inner = width - bw - (clipR ? 0.0 : 1.0);
      final a = (v.xOf(span.$1) - left - bw).clamp(0.0, inner);
      final b = (v.xOf(span.$2) - left - bw).clamp(0.0, inner);
      if (b - a >= 1 && (a > .5 || b < inner - .5)) {
        c.quads.add(left + bw + a, top + 1, left + bw + b, top + height - 1, withAlpha(color, ScopeLook.spanFillPct * dim));
        final se = withAlpha(_edgeOf(it.color), ScopeLook.spanEdgePct * dim);
        c.quads.vLine(left + bw + a, top + 1, top + height - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: top);
        c.quads.vLine(left + bw + b - 1, top + 1, top + height - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: top);
        c.stats.shapes++;
      }
    }
    // 판의 이름표는 물러나지 않는다(테두리 왼쪽 끝이 화면 밖이어도 — 가로 전체라 늘 그렇다).
    _paintLabel(c, it, left, top, width, dim, clipL && !it.board, borderLeft: !clipL);
  }

  /// 그릇 폴더 하나(리메이크 조각 ③ · 목업 d2-b): 몸통(둥근 10 · 안쪽 겹선) · 어깨 탭 안의 라벨 종이(이름 · 수) · 세 칸 손잡이,
  /// 접혔으면(가지가 한 줄로 합쳐짐) 탭 오른쪽에 그 가지 띠의 작은 꼬리표. 몸통은 띠보다 뒤라 펼친 폴더의 띠는 그 안에 앉는다.
  void _paintFolder(PaintContext c, ScopeIn it, (double, double)? span) {
    final box = scopeBoxOf(c, it);
    if (box == null) return;
    final v = c.v;
    final xl = v.xOf(it.start) - ScopeLook.padX, xr = v.xOf(it.end) + ScopeLook.padX;
    if (xr < c.left - 2 || xl > c.w + 2) return;
    final clipL = xl < c.left - 1, clipR = xr > c.w + 1;
    final left = (clipL ? c.left - 1 : xl).roundToDouble(), right = (clipR ? c.w + 1 : xr).roundToDouble();
    final top = v.yOf(box.top).roundToDouble(), body = v.yOf(box.body).roundToDouble(), bottom = v.yOf(box.top + box.height).roundToDouble();
    if (top > c.h || bottom < c.head || right - left < 8 || bottom - body < 4) return;
    final uid = scopeUidOf(c, it);
    final state = uid.isEmpty ? ScopeState.open : c.layout.scopeStateOf(uid);
    if (uid.isNotEmpty) _scopeAreas.add((ui.Rect.fromLTRB(left, top, right, bottom), uid, it.name, state, box.depth));
    if (box.depth > 0) {
      _paintBox(c, it, box, uid, state, left, right, top, body, bottom, clipL, clipR);
      return;
    }
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    final color = 0xff000000 | it.color;
    final fill = withAlpha(color, FolderLook.fillPct * dim);
    final edge = withAlpha(mixOklab(color, Look.paper, FolderLook.edgePct), dim);
    const radius = FolderLook.radius;
    final rr = clipR ? 0.0 : radius, rl = clipL ? 0.0 : radius;
    // 몸통 칠 — 왼쪽 위는 어깨 탭이 서는 자리라 직각.
    _roundRect(c, left, body, right, bottom, 0, rr, rr, rl, fill);
    // 어깨 탭(칠 · 테) + 라벨 + 손잡이. 탭 아래에서는 몸통 윗변이 끊겨 탭이 몸통으로 열린다.
    final tabL = (clipL ? c.left + FolderLook.clipInset : left).roundToDouble();
    final tabR0 = _folderTab(c, it, uid, state, tabL, top, body, fill, edge, dim);
    final tabR = _labelTabs(c, it, tabR0, body, math.min(right, c.w), fill, edge, dim);
    if (tabL > left) _edgeLine(c, true, left, tabL, body, edge);
    _edgeLine(c, true, tabR, right - rr, body, edge);
    _edgeLine(c, true, left + rl, right - rr, bottom - 1, edge);
    if (!clipL) _edgeLine(c, false, body, bottom - rl, left, edge);
    if (!clipR) _edgeLine(c, false, body + rr, bottom - rr, right - 1, edge);
    _arcs(c, left, body, right, bottom, 0, rr, rr, rl, edge);
    // 안쪽 겹선(2 안 · 둥근 8 · 먹 12 — 폴더 윤곽의 일부). 윗변은 탭 아래도 지난다.
    final inner = withAlpha(Look.ink, FolderLook.innerAlpha * dim);
    const ir = radius - FolderLook.inset;
    final irr = clipR ? 0.0 : ir, irl = clipL ? 0.0 : ir;
    final il = clipL ? left : left + FolderLook.inset, iR = clipR ? right : right - FolderLook.inset;
    final iT = body + FolderLook.inset, iB = bottom - FolderLook.inset;
    if (iB - iT > 2 * ir) {
      _edgeLine(c, true, il, iR - irr, iT, inner);
      _edgeLine(c, true, il + irl, iR - irr, iB - 1, inner);
      if (!clipL) _edgeLine(c, false, iT, iB - irl, il, inner);
      if (!clipR) _edgeLine(c, false, iT + irr, iB - irr, iR - 1, inner);
      _arcs(c, il, iT, iR, iB, 0, irr, irr, irl, inner);
    }
    c.stats.shapes++;
    c.debug?.note('폴더', '${it.name} ${state.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${(right - left).toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}'
        '${clipL ? ' 왼쪽잘림' : ''}${clipR ? ' 오른쪽잘림' : ''}');
    // 기간의 짙은 구간(명세 6-3 — 몸통 안에서): 짐작한 기간이거나 몸통 전체와 같으면 칠하지 않는다.
    if (span != null && !it.guessed) {
      final bw = clipL ? 0.0 : 1.0;
      final inside = right - left - bw - (clipR ? 0.0 : 1.0);
      final a = (v.xOf(span.$1) - left - bw).clamp(0.0, inside);
      final b = (v.xOf(span.$2) - left - bw).clamp(0.0, inside);
      if (b - a >= 1 && (a > .5 || b < inside - .5)) {
        c.quads.add(left + bw + a, body + 1, left + bw + b, bottom - 1, withAlpha(color, ScopeLook.spanFillPct * dim));
        final se = withAlpha(_edgeOf(it.color), ScopeLook.spanEdgePct * dim);
        c.quads.vLine(left + bw + a, body + 1, bottom - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: body);
        c.quads.vLine(left + bw + b - 1, body + 1, bottom - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: body);
        c.stats.shapes++;
      }
    }
    if (state == ScopeState.closed) _closedTags(c, box, tabR + FolderLook.tagFrom, math.min(right, c.w) - FolderLook.tagEnd, body);
  }

  /// 안쪽 그릇 = 상자(리메이크 2부 포개짐 · 목업 서고 box): 모따기 6 몸통(칠 없음 · 테 먹 25 · 화면에 잘린 쪽은 직각) ·
  /// 뚜껑(상자 위 ~ 18 · 먹 4%) 안 왼쪽 8의 흰 라벨 종이(이름 · 수). 세 상태는 그릇 안 오른쪽 클릭 메뉴(예전 세 칸 손잡이). 접히면 뚜껑 뒤로 작은 꼬리표.
  void _paintBox(PaintContext c, ScopeIn it, ScopeBox box, String uid, ScopeState state, double left, double right, double top, double body, double bottom, bool clipL, bool clipR) {
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    final edge = withAlpha(mixSrgb(Look.ink, Look.paper, ScopeLook.boxEdge), dim), lid = withAlpha(mixSrgb(Look.ink, Look.paper, ScopeLook.boxLid), dim);
    const k = ScopeLook.boxCham;
    final kl = clipL ? 0 : k, kr = clipR ? 0 : k;
    // 뚜껑 칠(위 1 ~ 몸통 윗변) — 모따기 귀는 1px 계단.
    for (int i = 0; i < k; i++) {
      c.quads.add(left + (kl > 0 ? kl - i : 0), top + i, right - (kr > 0 ? kr - i : 0), top + i + 1, lid);
    }
    c.quads.add(left, top + k, right, body, lid);
    // 테: 윗변 · 뚜껑 밑선 · 아랫변 · 양옆 + 네 귀의 빗변.
    c.quads.hLine(left + kl, right - kr, top, edge);
    c.quads.hLine(left, right, body, edge);
    c.quads.hLine(left + kl, right - kr, bottom - 1, edge);
    if (!clipL) c.quads.vLine(left, top + k, bottom - k, edge);
    if (!clipR) c.quads.vLine(right - 1, top + k, bottom - k, edge);
    for (int i = 0; i < k; i++) {
      if (!clipL) {
        c.quads.add(left + k - i - 1, top + i, left + k - i, top + i + 1, edge);
        c.quads.add(left + k - i - 1, bottom - i - 1, left + k - i, bottom - i, edge);
      }
      if (!clipR) {
        c.quads.add(right - k + i, top + i, right - k + i + 1, top + i + 1, edge);
        c.quads.add(right - k + i, bottom - i - 1, right - k + i + 1, bottom - i, edge);
      }
    }
    c.stats.shapes++;
    // 라벨 종이 + 손잡이(뚜껑 안 — 위 2 · 높이 15).
    final nameLook = _folderName ??= TextLook(FolderLook.nameSize, ui.FontWeight.w700, mixSrgb(Look.ink, Look.paper, .85));
    final countLook = _folderCount ??= TextLook(FolderLook.countSize, ui.FontWeight.w400, mixSrgb(Look.ink, Look.paper, .5));
    final count = it.count > 0 ? '${it.count}' : '';
    final nw = c.text.widthOf(it.name, nameLook), cw = count.isEmpty ? 0.0 : c.text.widthOf(count, countLook);
    if (nw == null || cw == null) {
      c.scene.requestFrame();
      return;
    }
    const pad = FolderLook.labelPad, lh = FolderLook.labelH;
    final lw = (nw + (count.isEmpty ? 0 : FolderLook.countGap + cw) + 2 * pad).roundToDouble();
    final lx = (clipL ? c.left + FolderLook.clipInset : left + ScopeLook.boxLabelX).roundToDouble(), ly = top + ((body - top - lh) / 2).roundToDouble();
    final name = it.name;
    if (uid.isNotEmpty) _folderHits.add((ui.Rect.fromLTWH(lx, ly, lw, lh), uid, state == ScopeState.open ? 2 : 1));
    _labels.add((c) {
      _paper(c, lx, ly, lw, lh, dim);
      c.later.add('folder', name, nameLook, lx + pad, ly + (lh - FolderLook.nameSize * 1.2) / 2, dim);
      if (count.isNotEmpty) c.later.add('folder', count, countLook, lx + pad + nw + FolderLook.countGap, ly + (lh - FolderLook.countSize * 1.2) / 2, dim);
    });
    if (state == ScopeState.closed) _closedTags(c, box, lx + lw + FolderLook.tagFrom, math.min(right, c.w) - FolderLook.tagEnd, body);
    c.debug?.note('상자', '${it.name} ${state.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${(right - left).toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}');
  }

  /// 그릇 안 이름표 시대(리메이크 2부 · 설계 3-3 · 목업 서고 folder의 둘째 탭 — 구역 53): 폴더 윗변의 둘째 탭(높이 16 · 글 9.5 먹 75를 탭에 바로) —
  /// x = max(그 해의 자리, 앞 탭 오른쪽 + 4) · 오른쪽 = max(글 폭 + 12, 그 해의 끝). 칠 · 테는 폴더와 같고 위 두 귀는 모따기 3. 돌려줌 = 마지막 탭의 오른쪽(몸통 윗변이 거기서 이어진다).
  double _labelTabs(PaintContext c, ScopeIn it, double from, double body, double maxRight, int fill, int edge, double dim) {
    var right = from;
    final look = _labelTabLook ??= TextLook(ScopeLook.labelTabText, ui.FontWeight.w700, mixSrgb(Look.ink, Look.paper, .75));
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile, sec = t.section(secLabel);
      if (sec.count == 0) continue;
      final ids = sec.u(Tile.itemId), rows = sec.u(Tile.itemRow), rows2 = sec.u(Tile.itemRow2), names = sec.u(Tile.itemName), x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1);
      final origin = t.origin.toDouble();
      for (int i = 0; i < sec.count; i++) {
        if (rows[i] != it.row || rows2[i] != it.row2 || !seen.add(ids[i])) continue;
        final label = t.text(names[i]);
        final w = c.text.widthOf(label, look);
        if (w == null) {
          c.scene.requestFrame();
          continue;
        }
        final xa = math.max(c.v.xOf(origin + x0[i]), right + ScopeLook.labelTabGap).roundToDouble();
        final xb = math.max(xa + w + 2 * ScopeLook.labelTabPad, c.v.xOf(origin + x1[i])).roundToDouble();
        if (xa > maxRight - 8) continue;
        final xr = math.min(xb, maxRight);
        const h = ScopeLook.labelTabH, k = 3;
        final y0 = body - h;
        for (int j = 0; j < k; j++) {
          c.quads.add(xa + k - j, y0 + j, xr - k + j, y0 + j + 1, fill);
          c.quads.add(xa + k - j - 1, y0 + j, xa + k - j, y0 + j + 1, edge);
          c.quads.add(xr - k + j, y0 + j, xr - k + j + 1, y0 + j + 1, edge);
        }
        c.quads.add(xa, y0 + k, xr, body, fill);
        c.quads.hLine(xa + k, xr - k, y0, edge);
        c.quads.vLine(xa, y0 + k, body, edge);
        c.quads.vLine(xr - 1, y0 + k, body, edge);
        c.stats.shapes++;
        _labels.add((c) => c.later.add('folderLabel', label, look, xa + ScopeLook.labelTabPad, y0 + (h - ScopeLook.labelTabText * 1.2) / 2, dim));
        right = xr;
      }
    }
    return right;
  }

  TextLook? _labelTabLook;

  /// 어깨 탭(목업 ftabH): 칠 · 테 · 흰 라벨 종이(이름 11 굵게 + 수). 세 상태는 그릇 안 오른쪽 클릭 메뉴(예전 세 칸 손잡이). 돌려줌 = 탭 오른쪽 끝(글자 폭을 아직 모르면 [x] — 탭 없이 다음 판에).
  double _folderTab(PaintContext c, ScopeIn it, String uid, ScopeState state, double x, double top, double body, int fill, int edge, double dim) {
    const s = FolderLook.shoulder, pad = FolderLook.labelPad, lh = FolderLook.labelH;
    final nameLook = _folderName ??= TextLook(FolderLook.nameSize, ui.FontWeight.w700, mixSrgb(Look.ink, Look.paper, .85));
    final countLook = _folderCount ??= TextLook(FolderLook.countSize, ui.FontWeight.w400, mixSrgb(Look.ink, Look.paper, .5));
    final count = it.count > 0 ? '${it.count}' : '';
    final nw = c.text.widthOf(it.name, nameLook), cw = count.isEmpty ? 0.0 : c.text.widthOf(count, countLook);
    if (nw == null || cw == null) {
      c.scene.requestFrame();
      return x;
    }
    final lw = (nw + (count.isEmpty ? 0 : FolderLook.countGap + cw) + 2 * pad).roundToDouble();
    final xR = x + s + 2 + lw + 2 + s;
    // 칠(가운데 네모 + 두 어깨) · 테(윗변 + 두 어깨의 곡선).
    c.quads.add(x + s, top, xR - s, body, fill);
    sprites.shoulder(right: false, stroke: false, left: x, top: top, argb: fill);
    sprites.shoulder(right: true, stroke: false, left: xR - s, top: top, argb: fill);
    sprites.shoulder(right: false, stroke: true, left: x, top: top, argb: edge);
    sprites.shoulder(right: true, stroke: true, left: xR - s, top: top, argb: edge);
    c.quads.add(x + s, top, xR - s, top + 1, edge);
    // 라벨 종이: 몸통 윗변 위 2에 아랫변. 라벨을 누르면 펼침 ↔ 접힘(폴더를 여닫는 손짓), 손잡이의 칸은 제 상태로.
    final lx = x + s + 2, ly = body - 2 - lh, name = it.name;
    if (uid.isNotEmpty) _folderHits.add((ui.Rect.fromLTWH(lx, ly, lw, lh), uid, state == ScopeState.open ? 2 : 1));
    _labels.add((c) {
      _paper(c, lx, ly, lw, lh, dim);
      c.later.add('folder', name, nameLook, lx + pad, ly + (lh - FolderLook.nameSize * 1.2) / 2, dim);
      if (count.isNotEmpty) c.later.add('folder', count, countLook, lx + pad + nw + FolderLook.countGap, ly + (lh - FolderLook.countSize * 1.2) / 2, dim);
    });
    c.debug?.note('폴더탭', '${it.name} ${x.toStringAsFixed(1)}~${xR.toStringAsFixed(1)} 라벨 ${lx.toStringAsFixed(1)},${ly.toStringAsFixed(1)},${lw.toStringAsFixed(1)}');
    return xR;
  }

  /// 흰 이름 종이 + 1px 먹 40(설계 4-1 '재료 하나').
  void _paper(PaintContext c, double x, double y, double w, double h, double dim) {
    final e = withAlpha(mixSrgb(Look.ink, Look.paper, .4), dim);
    c.quads.add(x, y, x + w, y + h, withAlpha(Look.paper, dim));
    c.quads.hLine(x, x + w, y, e);
    c.quads.hLine(x, x + w, y + h - 1, e);
    c.quads.vLine(x, y, y + h, e);
    c.quads.vLine(x + w - 1, y, y + h, e);
  }

  /// 접힌 폴더의 작은 꼬리표(목업 d2-b closedFolder · packTags): 합쳐진 가지 줄의 띠(구역 45 — 보는 때 안의 것)를 탭 오른쪽에 늘어놓고,
  /// 꼬리표마다 몸통 윗변으로 짧은 실을 내린다.
  void _closedTags(PaintContext c, ScopeBox box, double from, double to, double body) {
    final layout = c.layout, v = c.v;
    final rows = layout.mergedRows[box.firstRow] ?? [box.firstRow];
    final items = <(double, String, int)>[];
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile, sec = t.section(45);
      if (sec.count == 0) continue;
      final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1), row = sec.u(Tile.itemRow), refs = sec.u(Tile.itemRef);
      final colors = sec.u(Tile.itemColor), names = sec.u(Tile.itemName);
      final origin = t.origin.toDouble();
      for (int i = 0; i < sec.count; i++) {
        if (!rows.contains(row[i])) continue;
        if (v.xOf(origin + x1[i]) < c.left || v.xOf(origin + x0[i]) > c.w) continue;
        if (refs[i] != 0 && !seen.add(refs[i])) continue;
        items.add((v.xOf(origin + x0[i]), t.text(names[i]), 0xff000000 | colors[i]));
      }
    }
    if (items.isEmpty) return;
    items.sort((a, b) => a.$1.compareTo(b.$1));
    final spots = SmallTags.pack(c, items, from, to);
    if (spots == null) {
      c.scene.requestFrame();
      return;
    }
    final mid = body - FolderLook.tagRise, thread = mixSrgb(Look.ink, Look.paper, FolderLook.threadPct);
    _labels.add((c) {
      for (final spot in spots) {
        c.quads.vLine(spot.$1 + 5, mid + SmallTags.height / 2, body, thread);
        SmallTags.paint(c, spot, mid, sprites.dot, tag: 'folderTag');
      }
    });
  }

  /// 이름표(명세 6-3의 `_scopeLabelRect`): 자리가 모자라면 성격을 떼고(`short`), 더 모자라면 아예 없다(`off`).
  void _paintLabel(PaintContext c, ScopeIn it, double left, double top, double width, double dim, bool clipL, {bool borderLeft = true}) {
    if (it.name.isEmpty) return;
    final big = _bird ? ScopeLook.birdLabelTextSize : ScopeLook.labelTextSize;
    final small = _bird ? ScopeLook.birdKindTextSize : ScopeLook.kindTextSize;
    final color = 0xff000000 | it.color;
    final look = _labelLook[it.color] ??= TextLook(big, ui.FontWeight.w700, mixSrgb(color, Look.ink, .35));
    final kindLook = _kindLook[it.color] ??= TextLook(small, ui.FontWeight.w400, withAlpha(mixSrgb(color, Look.ink, .35), ScopeLook.kindAlpha));
    final nameWidth = c.text.widthOf(it.name, look);
    if (nameWidth == null) return;
    final nameW = nameWidth + (_bird ? 10 : 12);
    final room = width - 16;
    if (clipL || room < nameW) return; // 'off'
    var kindW = 0.0;
    if (it.label.isNotEmpty) {
      final w = c.text.widthOf(it.label, kindLook);
      if (w != null && room >= nameW + w + 4) kindW = w + 4;
    }
    final height = _bird ? ScopeLook.birdLabelHeight : ScopeLook.labelHeight;
    // 이름표는 테두리 안쪽에서 왼쪽 8 — 왼쪽 테두리를 편 판 둘레(clip-l)는 테두리 1px이 없다.
    final l = left + (borderLeft ? 1 : 0) + ScopeLook.labelLeft;
    final t = top + (it.hung ? ScopeLook.labelHungTop : (_bird ? ScopeLook.birdLabelTop : ScopeLook.labelTop));
    final w = math.min(nameW + kindW, width - 18);
    final tint = mixSrgb(Look.paper, color, ScopeLook.labelTintPct);
    _roundRect(c, l, t, l + w, t + height, ScopeLook.labelRadius, ScopeLook.labelRadius, ScopeLook.labelRadius, ScopeLook.labelRadius, withAlpha(tint, dim));
    if (it.board) _boardLabel = ui.Rect.fromLTWH(l, t, w, height);
    c.later.add('scope', it.name, look, l + ScopeLook.labelPad, t + (height - big * 1.2) / 2, dim);
    if (kindW > 0) c.later.add('scope', it.label, kindLook, l + ScopeLook.labelPad + nameWidth + 4, t + (height - small * 1.2) / 2, dim);
    c.debug?.note('대범위이름표', '${it.name} ${it.label} ${l.toStringAsFixed(1)},${t.toStringAsFixed(1)},${w.toStringAsFixed(1)}');
  }

  /// 띠의 채움 바로 뒤 · 칸보다 앞에 그릴 것(할거기 칠 — 지금 연표에서는 띠 바탕 위 · 칸 아래). 그리개가 띠 채움을 내보낸 뒤 타일마다 부른다.
  /// 띠에 잘려 온 조각은 제 타일에서 그린다(다른 타일에서 그리면 그 타일의 띠 채움이 덮는다).
  void paintOverBands(PaintContext c, Tile t) {
    final s = t.section(secHollow);
    if (s.count == 0 || c.hide.contains('scopes')) return;
    final v = c.v, layout = c.layout;
    final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
    final row = s.u(Tile.itemRow), color = s.u(Tile.itemColor), ref = s.u(Tile.itemRef), flags = s.u(Tile.itemFlags);
    final origin = t.origin.toDouble();
    for (int i = 0; i < s.count; i++) {
      final r = row[i];
      if (r >= layout.rowCount || !layout.isVisible(r)) continue;
      final geo = layout.geo(r);
      final bandTop = v.yOf(layout.rowTop(r) + geo.bandTop);
      if (!c.rowOnScreen(r, bandTop, geo.bandHeight)) continue;
      final band = _bandBox(c, t, ref[i]);
      if (band == null) continue;
      // 띠의 자식은 테두리 안쪽(padding box)에서 잰다: ox = 안쪽 왼쪽 x, iw = 안쪽 너비(지금 연표의 _hollowHTML).
      final ox = band.$1 + 1, iw = math.max(0.0, band.$2 - band.$1 - 2);
      if (iw <= 0) continue;
      final za = v.xOf(origin + x0[i]) - ox, zb = v.xOf(origin + x1[i]) - ox;
      if (zb - za < .5 || zb < 0 || za > iw) continue;
      final zl = math.max(za, 0.0), zw = math.min(zb, iw) - zl;
      if (zw < .5) continue;
      final l = ox + zl, rr = l + zw;
      final top = bandTop + 1, bottom = bandTop + geo.bandHeight - 1;
      if (bottom - top < 1) continue;
      final dim = emphasis?.bandAlpha(ref[i], r) ?? 1;
      // 가운데가 종이빛으로 비고 위아래 가장자리만 띠 색이 남는다 — 위아래 2px 투명 → 7px에서 종이색 92%(css 1652).
      final paper = withAlpha(Look.paper, ScopeLook.hollowPaper * dim);
      final clear = Look.paper & 0x00ffffff;
      final fade = math.min(ScopeLook.hollowFade, (bottom - top) / 2);
      final clearAt = math.min(ScopeLook.hollowClear, fade);
      c.quads.addFadeDown(l, top + clearAt, rr, top + fade, clear, paper);
      if (bottom - fade > top + fade) c.quads.add(l, top + fade, rr, bottom - fade, paper);
      c.quads.addFadeDown(l, bottom - fade, rr, bottom - clearAt, paper, clear);
      // 좌우의 대범위 색 파선(구간의 끝이 띠 · 화면에 잘리지 않았을 때만 — 지금 연표의 at-s · at-e)
      final edge = withAlpha(mixSrgb(0xff000000 | color[i], Look.ink, .70), ScopeLook.hollowEdgeAlpha * dim);
      if (zl > .5 && flags[i] & Tile.clipLeft == 0) c.quads.vLine(l, top, bottom, edge, dash: 3, gap: 3, phase: top);
      if (zl + zw < iw - .5 && flags[i] & Tile.clipRight == 0) c.quads.vLine(rr - 1, top, bottom, edge, dash: 3, gap: 3, phase: top);
      c.stats.shapes++;
      c.debug?.note('할거기', '${ref[i]} ${l.toStringAsFixed(1)},${top.toStringAsFixed(1)},${zw.toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}');
    }
  }

  /// 이 타일에서 띠 [band]가 차지한 가로 자리(화면에 잘린 뒤 — bands.dart와 같은 셈). 없으면 null.
  (double, double)? _bandBox(PaintContext c, Tile t, int band) {
    final v = c.v, origin = t.origin.toDouble();
    for (int i = 0; i < t.bandCount; i++) {
      if (t.bandId[i] != band) continue;
      final flags = t.bandFlags[i];
      var x1 = v.xOf(origin + t.bandX0[i]), x2 = v.xOf(origin + t.bandX1[i]);
      if (flags & Tile.fuzzyStart != 0) x1 -= Look.fuzzyFade;
      if (flags & Tile.fuzzyEnd != 0) x2 += Look.fuzzyFade;
      var l = math.max(x1, c.left - 1), r = math.min(x2, c.w + 1);
      if (r - l < 3) r = l + 3;
      if (flags & Tile.clipLeft != 0) l = l.roundToDouble();
      if (flags & Tile.clipRight != 0) r = r.roundToDouble();
      return (l, r);
    }
    return null;
  }

  /// 둥근 네모의 채움(모서리는 제 그림판의 사분원).
  void _roundRect(PaintContext c, double l, double t, double r, double b, double tl, double tr, double br, double bl, int fill) {
    if (r - l < .5 || b - t < .5) return;
    final top = math.max(tl, tr), bottom = math.max(bl, br);
    sprites.disc(ScopeCorner.topLeft, l, t, fill, tl);
    sprites.disc(ScopeCorner.topRight, r - tr, t, fill, tr);
    sprites.disc(ScopeCorner.bottomLeft, l, b - bl, fill, bl);
    sprites.disc(ScopeCorner.bottomRight, r - br, b - br, fill, br);
    if (top > 0) c.quads.add(l + tl, t, r - tr, t + top, fill);
    if (bottom > 0) c.quads.add(l + bl, b - bottom, r - br, b, fill);
    c.quads.add(l, t + top, r, b - bottom, fill);
  }

  /// 둥근 네모의 1px 테두리 모서리 넷.
  void _arcs(PaintContext c, double l, double t, double r, double b, double tl, double tr, double br, double bl, int edge) {
    sprites.arc(ScopeCorner.topLeft, l, t, edge, tl);
    sprites.arc(ScopeCorner.topRight, r - tr, t, edge, tr);
    sprites.arc(ScopeCorner.bottomLeft, l, b - bl, edge, bl);
    sprites.arc(ScopeCorner.bottomRight, r - br, b - br, edge, br);
  }

  void _edgeLine(PaintContext c, bool horizontal, double from, double to, double at, int edge) {
    if (to - from <= .05) return;
    if (horizontal) {
      c.quads.add(from, at, to, at + 1, edge);
    } else {
      c.quads.add(at, from, at + 1, to, edge);
    }
  }
}

/// 소속 펼치기 단추(구역 26 · `▸ n`) · 매달린 속국 접기 단추(48 · `▾ 속국 n`) · 할거 모아 보기 단추(27 · `▸ 〈성격〉 n`)를 모아 그린다. 띠 채움보다 위, 글자보다 아래.
/// 자리 잡기는 관계선 층의 [LinkLayer.beginFrame]에서(네모를 비켜 앉아야 하므로), 그리기는 그 층의 앞 판에서.
class ScopeMarks {
  /// 구역 번호(계약 6-10절).
  static const secMemBtn = 26, secScopeBtn = 27;

  /// 상국 띠의 매달린 속국 접기 단추(건의 8 · 2026-10-14 — 내보내기 `export/hangs.mjs` · a = 매달린 속국 수).
  static const secHangBtn = 48;

  /// 풀린 그릇의 열쇠표(리메이크 조각 ③ — 내보내기 `export/scopes.mjs` · ref = 구성 띠 · 이름 · 색 = 그릇 · text2 = 그릇 uid · start = 매다는 해).
  static const secKey = 50;

  /// 단체 펼치기(리메이크 조각 ④ — 내보내기 `export/links.mjs` · ref = 든 나라 띠 · a = 단체 수 · text2 = 단체마다 'uid␟이름␟#색'을 ␞로).
  static const secGroupsBtn = 51;

  /// 단추의 모양(css .tl-mem · 실측 dom/전체.json #545): 높이 16 · 좌우 여백 6 · 테두리 1 · 모서리 5 · 글자 10px. 글줄 높이는 G.line 21.
  static const btnHeight = 16.0, btnPad = 6.0, btnRadius = 5.0, btnTextSize = 10.0, lineHeight = 21.0;

  final sprites = ScopeSprites();
  final _btnLook = <int, TextLook>{};
  final _edge = <int, int>{};
  final _jobs = <_Button>[];
  final _keys = <_Key>[];

  /// 이번 장면의 플래그(띠 번호 → 그 띠의 접고 펴는 것) · 그 가운데 화면에 놓인 것(리메이크 2부 — 조감이 아닐 때 단추 대신).
  final _flags = <int, FlagSpot>{};
  final _placed = <FlagSpot>[];

  /// 놓인 플래그 하나(없으면 null) — 플래그 창이 자리와 칸을 읽는다.
  FlagSpot? flagOf(int band) {
    for (final f in _placed) {
      if (f.band == band) return f;
    }
    return null;
  }
  TextLook? _keyLook;

  /// 띠 층 — 조감에서 띠 안 이름의 오른쪽 끝(`bnR`)과 이름이 차지한 구간을 여기서 읽는다(js:3329 · 3335).
  /// 그리개가 이어 준다(`painter.dart`의 층 배선). 띠 층의 `beginFrame`이 이 층보다 **먼저** 돌아야 한다.
  BandLayer? bands;

  int _edgeOf(int color) => _edge[color] ??= mixOklab(0xff000000 | color, Look.ink, .84);

  void setScale(double scale) => sprites.setScale(scale);
  void flush(PaintContext c) => sprites.flush(c.canvas);

  /// 한 장면의 단추 자리를 잡는다. [reserved]는 줄 번호 → [왼쪽, 오른쪽]의 목록이고, 부르는 쪽(관계선 층)이 네모를 먼저 넣어 준다.
  void collect(PaintContext c, LinkLayer layer, Map<int, List<(double, double)>> reserved, Set<int> done) {
    _jobs.clear();
    _keys.clear();
    _flags.clear();
    _placed.clear();
    if (c.hide.contains('links')) return;
    final bird = c.layout.bird;
    for (final d in c.scene.draw) {
      final t = d.tile;
      // 차례: 소속 단추(띠 시작 + 14에 그대로) → 속국 접기 단추 → 대범위 단추(둘 다 앞의 것을 비켜 앉는다).
      // 리메이크 2부(감독 2026-10-15 "접고 펴는 것은 플래그 하나에"): 조감이 아니면 단추 대신 띠마다 플래그 하나에 모은다(단체 펼치기 51도).
      for (final section in [secMemBtn, secHangBtn, secScopeBtn, secGroupsBtn]) {
        // 조감에서는 매달린 이름표가 없다(명세 05의 7.2) — 접을 것도 없다. 단체 펼치기는 플래그 창에만 있다.
        if ((section == secHangBtn || section == secGroupsBtn) && bird) continue;
        final s = t.section(section);
        if (s.count == 0) continue;
        final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
        final id = s.u(Tile.itemId), row = s.u(Tile.itemRow), color = s.u(Tile.itemColor), a = s.u(Tile.itemA);
        final ref = s.u(Tile.itemRef), name = s.u(Tile.itemName), text2 = s.u(Tile.itemText2);
        final origin = t.origin.toDouble();
        for (int i = 0; i < s.count; i++) {
          if (!done.add(id[i])) continue;
          if (!bird) {
            _flagEntry(c, layer, section, row[i], ref[i], origin + x0[i], origin + x1[i], color[i], a[i], t.text(name[i]), t.text(text2[i]));
            continue;
          }
          if (section == secHangBtn) {
            final r = row[i];
            // 소속을 펼친 상위 띠는 매달린 이름표를 그리지 않는다(이름표 층의 `expanded`) — 접을 것이 없으니 단추도 없다.
            if (r >= c.layout.rowCount || layer.expanded.contains(ref[i])) continue;
            final open = !c.layout.isHangFolded(r);
            _place(c, layer, r, ref[i], '', origin + x0[i], origin + x1[i], '${open ? '▾' : '▸'} 속국 ${a[i]}', color[i], reserved, false, false, hang: true);
            continue;
          }
          final scope = section == secScopeBtn ? t.text(text2[i]) : '';
          final on = section == secScopeBtn ? layer.scopesOn.contains(scope) : layer.expanded.contains(ref[i]);
          final head = on ? '▾' : '▸';
          final kind = t.text(name[i]);
          // 조감의 소속 단추는 글이 `▸2`로 붙는다(`_birdBtns` js:3319~3336) — 할거 단추는 조감에서도 사이를 띄운다.
          final text = section == secMemBtn ? (bird ? '$head${a[i]}' : '$head ${a[i]}') : '$head ${kind.isEmpty ? '대범위' : kind} ${a[i]}';
          _place(c, layer, row[i], ref[i], scope, origin + x0[i], origin + x1[i], text, color[i], reserved, section == secScopeBtn, bird);
        }
      }
    }
    if (bird) return;
    _placeFlags(c, layer);
    _collectKeys(c, layer);
  }

  /// 플래그 창의 칸 하나를 그 띠의 플래그에 더한다(조감이 아닐 때 — 단추 대신).
  void _flagEntry(PaintContext c, LinkLayer layer, int section, int r, int band, double from, double to, int color, int count, String kind, String text2) {
    if (band == 0 || r >= c.layout.rowCount) return;
    final f = _flags[band] ??= FlagSpot(band, r, from, to, color);
    switch (section) {
      case secMemBtn:
        f.entries.add(FlagEntry(FlagKind.members, '소속', count, layer.expanded.contains(band)));
      case secHangBtn:
        // 소속을 펼친 상위 띠는 매달린 이름표를 그리지 않는다(이름표 층의 `expanded`) — 접을 것이 없다.
        if (layer.expanded.contains(band)) return;
        f.entries.add(FlagEntry(FlagKind.hangs, '속국', count, !c.layout.isHangFolded(r), row: r));
      case secScopeBtn:
        f.entries.add(FlagEntry(FlagKind.scope, kind.isEmpty ? '대범위' : kind, count, layer.scopesOn.contains(text2), scope: text2));
      case secGroupsBtn:
        final names = <(String, int)>[];
        for (final one in text2.split('\u001e')) {
          final parts = one.split('\u001f');
          if (parts.length < 2 || parts[1].isEmpty) continue;
          final hex = parts.length > 2 ? parts[2].replaceFirst('#', '') : '';
          names.add((parts[1], int.tryParse(hex, radix: 16) ?? 0xa4b1b7));
        }
        f.entries.add(FlagEntry(FlagKind.groups, '단체', count, c.layout.isGroupsExpanded(band), names: names));
    }
  }

  /// 플래그를 놓는다: 꼬리표 윗변 위, 구멍 오른쪽 6(띠 시작 + 16 — 화면 왼쪽 밖이면 그림판 왼쪽 + 16) · 14 × 7. 띠가 그보다 좁으면 놓지 않는다.
  void _placeFlags(PaintContext c, LinkLayer layer) {
    final v = c.v, layout = c.layout;
    for (final f in _flags.values) {
      if (f.entries.isEmpty) continue;
      final r = f.row;
      if (!layout.isVisible(r)) continue;
      final geo = layout.geo(r);
      final top = v.yOf(layout.rowTop(r) + geo.bandTop).roundToDouble();
      if (!c.rowOnScreen(r, top - FlagLook.h, geo.bandHeight + FlagLook.h)) continue;
      final left = _bandLeft(c, f.band) ?? v.xOf(f.from);
      final x = (math.max(left, c.left) + FlagLook.from).roundToDouble();
      if (x + FlagLook.w > math.min(v.xOf(f.to), c.w) - 4) continue;
      f.rect = ui.Rect.fromLTWH(x, top - FlagLook.h, FlagLook.w, FlagLook.h);
      f.entries.sort((a, b) => a.kind.index.compareTo(b.kind.index));
      _placed.add(f);
      // 누를 자리는 위아래 · 옆으로 조금 넓게(작은 꼬리라 — 플래그 목업 보고의 약점 3).
      layer.addHit(LinkHitKind.flag, f.band, '', ui.Rect.fromLTRB(x - 3, top - FlagLook.h - 4, x + FlagLook.w + 3, top + 2));
    }
  }

  /// 플래그 하나: 칠(띠 색 50% — 목업의 빗금 짙기) · 위와 양옆 1px 테(띠의 테 색). 아래는 꼬리표 윗변에 얹힌다.
  void _paintFlag(PaintContext c, FlagSpot f, double dim) {
    final r = f.rect, color = 0xff000000 | f.color;
    final fill = withAlpha(mixSrgb(color, Look.paper, FlagLook.fillPct), dim), edge = withAlpha(_edgeOf(f.color), dim);
    c.quads.add(r.left, r.top, r.right, r.bottom, fill);
    c.quads.hLine(r.left, r.right, r.top, edge);
    c.quads.vLine(r.left, r.top, r.bottom, edge);
    c.quads.vLine(r.right - 1, r.top, r.bottom, edge);
    c.stats.shapes++;
  }

  /// 단추 하나의 자리(명세 5-2절 · 6-4절). [dashed]면 테두리가 파선(.tl-scopebtn)이고 앞의 것(네모 · 소속 단추)을 비켜 앉는다.
  /// [hang]이면 속국 접기 단추 — 테두리는 소속 단추처럼 곧고, 자리는 소속 단추와 같은 띠 시작 + 14에서 앞의 것을 비켜 앉는다(웹의 `.tl-hangbtn`).
  void _place(
    PaintContext c, LinkLayer layer, int r, int band, String scope, double from, double to, String text, int color,
    Map<int, List<(double, double)>> reserved, bool dashed, bool bird, {bool hang = false}
  ) {
    final v = c.v, layout = c.layout;
    if (r >= layout.rowCount || !layout.isVisible(r)) return;
    final geo = layout.geo(r);
    final top = v.yOf(layout.rowTop(r) + geo.bandTop);
    if (!c.rowOnScreen(r, top, geo.bandHeight)) return;
    final size = bird ? BirdLook.btnTextSize : btnTextSize;
    final weight = bird ? ui.FontWeight.w600 : ui.FontWeight.w400;
    final look = _btnLook[color * 2 + (bird ? 1 : 0)] ??= TextLook(size, weight, mixSrgb(0xff000000 | color, Look.ink, .30));
    final width = c.text.widthOf(text, look);
    if (width == null) {
      c.debug?.note('단추', '$text 글자 폭 아직');
      return;
    }
    final height = bird ? BirdLook.btnHeight : btnHeight;
    final pad = bird ? BirdLook.btnPad : btnPad;
    final w = width + 2 * pad + 2;
    // 조감에서 대범위(파선) 단추가 비켜 갈 것은 **띠 안 이름과 앞서 놓인 띠 안 단추**뿐이다(js:3335의 `zones` = `bnm`) —
    // 건국 · 멸망 네모까지 든 관계선 층의 `reserved`를 쓰면 지금 연표가 비키지 않는 것까지 비켜 오른쪽으로 밀린다.
    final zones = bird ? bands?.birdNameZones : null;
    final lane = zones != null ? (zones[r] ??= []) : (reserved[r] ??= []);
    // 소속 단추는 띠 시작 + 14에서 그대로, 대범위 단추는 구간 시작 + 6에서 앞의 것(소속 단추 · 건국 네모 · 앞 단추)과 겹치면 그 오른쪽 + 3으로 비킨다(최대 여섯 번).
    // 조감의 소속 단추(파선 아님)는 띠 안 이름의 오른쪽 끝 + 4에 붙는다(js:3329). 이름이 들어가지 않는 모양 c에서도
    // 띠 층이 `bnR`을 남겨 두므로(`nm.l − 4`) 단추는 선다. 띠가 아닌 줄에는 `bnR` 자체가 없고 그때는 단추도 없다(js:3320).
    double bx;
    if (bird && !dashed) {
      final end = bands?.birdNameEnd[band];
      if (end == null) {
        c.debug?.note('단추', '$text 조감의 띠 안 이름 자리 없음');
        return;
      }
      bx = end + BandLayer.birdBtnGap;
    } else {
      bx = (bird ? v.xOf(from) : math.max(v.xOf(from), c.left)) + (dashed ? 6 : 14);
      // 꼬리표 갈래 E: 이름이 띠 안 머리(첫 글줄 높이)에 들어 — 소속 단추는 이름(과 딱지) 뒤 4px에 앉는다(조감의 띠 안 이름과 같은 꼴).
      final end = bird || dashed || hang ? null : bands?.headNameEnd[band];
      if (end != null && end + BandLayer.birdBtnGap > bx) bx = end + BandLayer.birdBtnGap;
    }
    // 대범위 · 속국 접기 단추는 머리 이름의 자리도 비킨다(조감이 아닐 때 — 조감은 위 birdNameZones가 이미 든다).
    final heads = bird ? null : bands?.headNameZones[r];
    if (dashed || hang) {
      for (int k = 0; k < 6; k++) {
        (double, double)? hit;
        for (final z in [...lane, ...?heads]) {
          if (bx < z.$2 && bx + w > z.$1) {
            hit = z;
            break;
          }
        }
        if (hit == null) break;
        bx = hit.$2 + 3;
      }
    }
    final room = (bird ? v.xOf(to) : math.min(v.xOf(to), c.w)) - 6;
    if (bx + w > room) {
      c.debug?.note('단추', '$text 자리 모자람 ${bx.toStringAsFixed(1)}+${w.toStringAsFixed(1)} > ${room.toStringAsFixed(1)}');
      return;
    }
    final by = bird
        ? v.yOf(layout.rowTop(r) + geo.bandTop + (geo.bandHeight - height) / 2)
        : v.yOf(layout.rowTop(r) + geo.textTop) + ((lineHeight - height) / 2).roundToDouble();
    _jobs.add(_Button(bx, by, w, height, bird ? BirdLook.btnRadius : btnRadius, pad, text, look, color, dashed, size));
    final clear = bird ? BirdLook.nameClear : 3.0;
    lane.add((bx - clear, bx + w + clear));
    // 사건 이름 · 점이 비켜 갈 자리. 글줄이 하나면 점도 단추 오른쪽으로 밀고(js:6958), 분류별 글줄이 있는 줄이면
    // **첫 글줄의 점만** 민다(js:6959 — 첫 글줄의 분류 점은 다른 글줄로 갈 수 없어 단추 밑에 가려진다).
    final cats = layout.spec(r)?.cats.length ?? 0;
    layer.addZone(r, bx - 3, bx + w + 3, 0, geo.textLines <= 1 || cats >= 2);
    layer.addHit(hang ? LinkHitKind.hangButton : (dashed ? LinkHitKind.scopeButton : LinkHitKind.memberButton), band, scope, ui.Rect.fromLTWH(bx, by, w, height), to: hang ? r : 0);
  }

  /// 풀린 그릇의 열쇠표(구역 50 — 리메이크 조각 ③ · 설계 4-6 #2 B · 목업 blend.js tags): 구성 띠의 윗변 위(그릇의 줄이라 위 틈 15)에
  /// 흰 열쇠표 '○ 그릇 이름'을 띠 시작 + 16에서 45° 실로 매단다. 켠 대범위(펼침 · 접힘)의 것은 폴더가 이름을 보이므로 건너뛴다.
  /// 한 띠에 여럿이면 앞 열쇠표 뒤 4에 잇는다. 누르면 그 그릇을 펼친다(손잡이의 펼침과 같다).
  void _collectKeys(PaintContext c, LinkLayer layer) {
    final v = c.v, layout = c.layout;
    final last = <int, double>{};
    final seen = <String>{};
    final look = _keyLook ??= TextLook(FolderLook.keySize, ui.FontWeight.w700, mixSrgb(Look.ink, Look.paper, .65));
    for (final d in c.scene.draw) {
      final t = d.tile, s = t.section(secKey);
      if (s.count == 0) continue;
      final x0 = s.f(Tile.itemX0), row = s.u(Tile.itemRow), ref = s.u(Tile.itemRef), name = s.u(Tile.itemName), text2 = s.u(Tile.itemText2);
      final origin = t.origin.toDouble();
      for (int i = 0; i < s.count; i++) {
        final uid = t.text(text2[i]), band = ref[i], r = row[i];
        if (uid.isEmpty || band == 0 || layer.scopesOn.contains(uid) || !seen.add('$band|$uid')) continue;
        if (r >= layout.rowCount || !layout.hasBody(r)) continue;
        final geo = layout.geo(r);
        final bandTop = v.yOf(layout.rowTop(r) + geo.bandTop).roundToDouble();
        if (!c.rowOnScreen(r, bandTop - FolderLook.keyH - FolderLook.keyRise, geo.bandHeight + FolderLook.keyH + FolderLook.keyRise)) continue;
        final bandLeft = _bandLeft(c, band);
        if (bandLeft == null) continue;
        final label = t.text(name[i]);
        final tw = c.text.widthOf(label, look);
        if (tw == null) {
          c.scene.requestFrame();
          continue;
        }
        // 실이 띠에 닿는 곳: 매다는 해 · 띠 시작 + 16 가운데 늦은 쪽(화면 왼쪽 밖이면 그림판 왼쪽 안으로).
        var xa = math.max(math.max(v.xOf(origin + x0[i]), bandLeft + FolderLook.keyFrom), c.left + 2).roundToDouble();
        // 플래그가 있는 띠는 열쇠표를 플래그 뒤로 민다(플래그 목업 보고의 약점 4 — 리메이크 2부).
        final flag = flagOf(band);
        if (flag != null && xa < flag.rect.right + FolderLook.keyGap) xa = flag.rect.right + FolderLook.keyGap;
        final w = (tw + 17).roundToDouble();
        final kx = math.max(xa + 3, (last[band] ?? double.negativeInfinity) + FolderLook.keyGap).roundToDouble();
        if (kx > c.w) continue;
        final ky = bandTop - FolderLook.keyRise - FolderLook.keyH;
        last[band] = kx + w;
        _keys.add(_Key(xa, bandTop, kx, ky, w, label, look));
        layer.addHit(LinkHitKind.scopeButton, band, uid, ui.Rect.fromLTWH(kx, ky, w, FolderLook.keyH), to: 1);
      }
    }
  }

  /// 띠 [band]의 화면 왼쪽 끝(실린 타일 가운데 가장 왼쪽 — 시작이 실리지 않았으면 화면 왼쪽 밖이다). 없으면 null.
  double? _bandLeft(PaintContext c, int band) {
    double? out;
    for (final d in c.scene.draw) {
      final t = d.tile, origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        if (t.bandId[i] != band) continue;
        final x = c.v.xOf(origin + t.bandX0[i]);
        if (out == null || x < out) out = x;
      }
    }
    return out;
  }

  /// 열쇠표 하나: 45° 실(띠 윗변 → 구멍) · 왼쪽 둥근 끝 6의 흰 종이 · 1px 먹 40 · 구멍(지름 4 · 먹 45) · 그릇 이름.
  void _paintKey(PaintContext c, _Key k, double dim) {
    const h = FolderLook.keyH, r = FolderLook.keyR;
    final thread = withAlpha(mixSrgb(Look.ink, Look.paper, FolderLook.threadPct), dim);
    // 실: 띠 윗변의 xa에서 구멍 가운데(kx + 6, ky + 6)로 — 1px 계단(줄마다 가로로 나눠 긋는다).
    final hx = k.kx + r, hy = k.ky + h / 2;
    final steps = (k.bandTop - hy).round();
    if (steps > 0) {
      final run = (hx - k.xa) / steps;
      for (int i = 0; i < steps; i++) {
        final a = (k.xa + i * run).floorToDouble(), b = math.max(a + 1, (k.xa + (i + 1) * run).floorToDouble());
        c.quads.add(a, k.bandTop - i - 1, b, k.bandTop - i, thread);
      }
    }
    final paper = withAlpha(Look.paper, dim), edge = withAlpha(mixSrgb(Look.ink, Look.paper, .4), dim);
    sprites.disc(ScopeCorner.topLeft, k.kx, k.ky, paper, r);
    sprites.disc(ScopeCorner.bottomLeft, k.kx, k.ky + r, paper, r);
    c.quads.add(k.kx + r, k.ky, k.kx + k.w, k.ky + h, paper);
    c.quads.hLine(k.kx + r, k.kx + k.w, k.ky, edge);
    c.quads.hLine(k.kx + r, k.kx + k.w, k.ky + h - 1, edge);
    c.quads.vLine(k.kx + k.w - 1, k.ky, k.ky + h, edge);
    sprites.arc(ScopeCorner.topLeft, k.kx, k.ky, edge, r);
    sprites.arc(ScopeCorner.bottomLeft, k.kx, k.ky + r, edge, r);
    sprites.dot(4, hx - 2, hy - 2, thread);
    sprites.dot(2, hx - 1, hy - 1, paper);
    c.later.add('key', k.label, k.look, k.kx + FolderLook.keyTextX, k.ky + (h - FolderLook.keySize * 1.2) / 2, dim);
    c.stats.shapes++;
    c.debug?.note('열쇠표', '${k.label} ${k.kx.toStringAsFixed(1)},${k.ky.toStringAsFixed(1)},${k.w.toStringAsFixed(1)}');
  }

  /// 모아 둔 단추를 그린다(관계선 층의 앞 판에서). [dim]은 고른 것이 있을 때의 .5(css 481).
  void paint(PaintContext c, double dim) {
    for (final k in _keys) {
      _paintKey(c, k, dim);
    }
    for (final f in _placed) {
      _paintFlag(c, f, dim);
    }
    for (final b in _jobs) {
      _roundBox(c, b, dim);
      c.debug?.note('단추', b.text);
      c.stats.shapes++;
    }
  }

  /// 종이색 둥근 네모 + 1px 테두리(모서리는 제 그림판의 조각).
  void _roundBox(PaintContext c, _Button b, double dim) {
    final l = b.x, t = b.y, r = b.x + b.w, bottom = b.y + b.h, radius = b.radius;
    final fill = withAlpha(Look.paper, dim), edge = withAlpha(_edgeOf(b.color), dim);
    sprites.disc(ScopeCorner.topLeft, l, t, fill, radius);
    sprites.disc(ScopeCorner.topRight, r - radius, t, fill, radius);
    sprites.disc(ScopeCorner.bottomLeft, l, bottom - radius, fill, radius);
    sprites.disc(ScopeCorner.bottomRight, r - radius, bottom - radius, fill, radius);
    c.quads.add(l, t + radius, l + radius, bottom - radius, fill);
    c.quads.add(r - radius, t + radius, r, bottom - radius, fill);
    c.quads.add(l + radius, t, r - radius, bottom, fill);
    // 테두리: 곧은 네 변 + 모서리의 1px 호(호는 파선으로 끊지 않는다 — 1px 조각이라 눈에 띄지 않는다).
    final dash = b.dashed ? 3.0 : 0.0, gap = b.dashed ? 2.0 : 0.0;
    c.quads.hLine(l + radius, r - radius, t, edge, dash: dash, gap: gap, phase: l);
    c.quads.hLine(l + radius, r - radius, bottom - 1, edge, dash: dash, gap: gap, phase: l);
    c.quads.vLine(l, t + radius, bottom - radius, edge, dash: dash, gap: gap, phase: t);
    c.quads.vLine(r - 1, t + radius, bottom - radius, edge, dash: dash, gap: gap, phase: t);
    sprites.arc(ScopeCorner.topLeft, l, t, edge, radius);
    sprites.arc(ScopeCorner.topRight, r - radius, t, edge, radius);
    sprites.arc(ScopeCorner.bottomLeft, l, bottom - radius, edge, radius);
    sprites.arc(ScopeCorner.bottomRight, r - radius, bottom - radius, edge, radius);
    c.later.add('mem', b.text, b.look, l + b.pad + 1, t + (b.h - b.size * 1.2) / 2, dim);
  }
}

/// 플래그의 꼴(리메이크 2부 · 목업 slice4 s4-플래그 · 감독 "플래그 하나로 모으고, 빗금 말고 그냥 칠하자. 지금 빗금 색 정도로"):
/// 14 × 7 · 띠 시작(구멍) + 16 · 칠은 띠 색 50%.
abstract final class FlagLook {
  static const w = 14.0, h = 7.0, from = 16.0, fillPct = .5;
}

/// 플래그 창의 칸 갈래 — 창에 적는 차례이기도 하다.
enum FlagKind { members, hangs, groups, scope }

/// 플래그 창의 칸 하나 — 접고 펴는 것 하나(소속 · 매단 속국 · 단체 · 할거와 대범위).
class FlagEntry {
  const FlagEntry(this.kind, this.label, this.count, this.on, {this.scope = '', this.row = -1, this.names = const []});
  final FlagKind kind;
  final String label;

  /// 대범위 uid(할거 · 대범위 칸) — 그 밖에는 빈 글.
  final String scope;
  final int count;

  /// 매단 속국 칸의 줄(접고 펴는 단위) — 그 밖에는 −1.
  final int row;

  /// 지금 펼쳐져 있는가.
  final bool on;

  /// 단체 칸의 단체 목록(이름 · 색) — 창이 색 점과 함께 적는다.
  final List<(String, int)> names;
}

/// 꼬리표 하나의 플래그 — 윗변에 얹힌 칠한 꼬리. 누르면 위로 늘어난 창(그 띠의 [entries]).
class FlagSpot {
  FlagSpot(this.band, this.row, this.from, this.to, this.color);
  final int band, row, color;
  final double from, to;
  final entries = <FlagEntry>[];

  /// 화면 자리(배치 px) — 아래 변이 꼬리표 윗변이다.
  ui.Rect rect = ui.Rect.zero;
}

/// 자리를 잡아 둔 열쇠표 하나 — 실이 띠에 닿는 x · 띠 윗변 · 열쇠표의 왼쪽 위 · 너비 · 글.
class _Key {
  _Key(this.xa, this.bandTop, this.kx, this.ky, this.w, this.label, this.look);
  final double xa, bandTop, kx, ky, w;
  final String label;
  final TextLook look;
}

/// 자리를 잡아 둔 단추 하나.
class _Button {
  _Button(this.x, this.y, this.w, this.h, this.radius, this.pad, this.text, this.look, this.color, this.dashed, this.size);
  final double x, y, w, h, radius, pad, size;
  final String text;
  final TextLook look;
  final int color;
  final bool dashed;
}

enum ScopeCorner { topLeft, topRight, bottomRight, bottomLeft }

/// 대범위 · 단추만의 작은 그림판: 사분원 채움(반지름 하나를 키우고 줄여 쓴다)과 1px 테두리 호.
/// 1px 호는 키우면 굵어지므로 쓰는 반지름마다 따로 그려 둔다(3 · 4 · 5 · 6 · 8 · 10 · 12 — 단추 5 · 조감 단추 3 · 대범위 12 · 조감 대범위 8 · 띠 안쪽 9는 8로 갈음 ·
/// 폴더 몸통 10 · 안쪽 겹선 8 · 열쇠표의 둥근 끝 6). 맨 아래 줄은 폴더 어깨 탭의 어깨(7 × 21 — 칠 · 테 × 왼쪽 · 오른쪽).
/// (`scene/sprites.dart`와 같은 방식이지만 공용 파일을 고치지 않으려고 제 층 안에 둔다 — 계약 7절.)
class ScopeSprites {
  static const unit = 12.0, _cell = 16.0;

  /// 1px 호를 그려 둔 반지름들.
  static const arcRadii = [3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0];

  /// 폴더 어깨(목업 kit.js tabPath — 어깨 7 · 탭 높이 20): 21 높이에 그려 아래 끝이 몸통 윗변의 1px 줄에 닿는다.
  static const shoulderW = 7.0, shoulderH = 21.0;
  static const _shoulderTop = 8 * _cell;

  /// 작은 동그라미(지름 2 · 3 · 4 — 작은 꼬리표 · 열쇠표의 구멍과 매다는 실의 매듭): 1배에서 둥글게 보이게 제 크기로 그려 둔다.
  static const dotSizes = [2.0, 3.0, 4.0];
  static const _dotTop = _shoulderTop + 24;
  static const _sheetWidth = 4 * _cell, _sheetHeight = _dotTop + 8;

  ui.Image? _image;
  double _scale = 1;

  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  /// 채움 사분원의 자리(맨 윗줄).
  static ui.Rect discCell(ScopeCorner corner) => ui.Rect.fromLTWH(corner.index * _cell, 0, unit, unit);

  /// 반지름 [i]번째의 1px 호.
  static ui.Rect arcCell(int i, ScopeCorner corner) => ui.Rect.fromLTWH(corner.index * _cell, (i + 1) * _cell, arcRadii[i], arcRadii[i]);

  /// 폴더 어깨 하나(0 왼쪽 칠 · 1 오른쪽 칠 · 2 왼쪽 테 · 3 오른쪽 테).
  static ui.Rect shoulderCell(int i) => ui.Rect.fromLTWH(i * _cell, _shoulderTop, shoulderW, shoulderH);

  /// [dotSizes]의 [i]번째 지름의 동그라미.
  static ui.Rect dotCell(int i) => ui.Rect.fromLTWH(i * 8, _dotTop, dotSizes[i], dotSizes[i]);

  /// 그 반지름에 가장 가까운 호 조각의 번호.
  static int arcIndex(double radius) {
    var best = 0;
    for (int i = 1; i < arcRadii.length; i++) {
      if ((arcRadii[i] - radius).abs() < (arcRadii[best] - radius).abs()) best = i;
    }
    return best;
  }

  Float32List _transforms = Float32List(4 * 128), _rects = Float32List(4 * 128);
  Int32List _colors = Int32List(128);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  /// 채운 사분원(반지름은 마음대로).
  void disc(ScopeCorner corner, double left, double top, int argb, double radius) {
    if (radius <= 0) return;
    _put(discCell(corner), left, top, argb, radius / unit);
  }

  /// 폴더 어깨 탭의 어깨 하나 — [left] · [top]은 탭의 위 왼쪽 자리(어깨 칸 7 × 21).
  void shoulder({required bool right, required bool stroke, required double left, required double top, required int argb}) =>
      _put(shoulderCell((right ? 1 : 0) + (stroke ? 2 : 0)), left, top, argb, 1);

  /// 동그란 점(지름 [size]) — 지름 2 · 3 · 4는 그려 둔 동그라미, 그 밖은 사분원 넷. 작은 꼬리표 · 열쇠표의 구멍과 매듭이 쓴다.
  void dot(double size, double left, double top, int argb) {
    final i = dotSizes.indexOf(size);
    if (i >= 0) {
      _put(dotCell(i), left, top, argb, 1);
      return;
    }
    final r = size / 2;
    disc(ScopeCorner.topLeft, left, top, argb, r);
    disc(ScopeCorner.topRight, left + r, top, argb, r);
    disc(ScopeCorner.bottomLeft, left, top + r, argb, r);
    disc(ScopeCorner.bottomRight, left + r, top + r, argb, r);
  }

  /// 1px 테두리의 사분원 호.
  void arc(ScopeCorner corner, double left, double top, int argb, double radius) {
    if (radius <= 0) return;
    final i = arcIndex(radius);
    _put(arcCell(i, corner), left, top, argb, radius / arcRadii[i]);
  }

  void _put(ui.Rect source, double left, double top, int argb, double size) {
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

  /// 조각 상자의 한 모서리가 원의 한가운데가 되게 — 보이는 사분면이 그 모서리의 반대쪽이다.
  static ui.Offset _center(ui.Rect box, ScopeCorner corner) => ui.Offset(
    corner == ScopeCorner.topRight || corner == ScopeCorner.bottomRight ? box.left : box.right,
    corner == ScopeCorner.bottomLeft || corner == ScopeCorner.bottomRight ? box.top : box.bottom,
  );

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    const white = ui.Color(0xffffffff);
    final fill = ui.Paint()
      ..color = white
      ..isAntiAlias = true;
    final line = ui.Paint()
      ..color = white
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (final corner in ScopeCorner.values) {
      final box = discCell(corner);
      canvas.save();
      canvas.clipRect(box);
      canvas.drawCircle(_center(box, corner), unit, fill);
      canvas.restore();
    }
    for (int i = 0; i < arcRadii.length; i++) {
      for (final corner in ScopeCorner.values) {
        final box = arcCell(i, corner);
        canvas.save();
        canvas.clipRect(box);
        canvas.drawCircle(_center(box, corner), arcRadii[i] - .5, line);
        canvas.restore();
      }
    }
    // 폴더 어깨(kit.js tabPath): 왼쪽은 (0, 20.5)에서 (7, 0.5)로 오르는 곡선 — 칠은 곡선 오른쪽 아래(탭 안), 테는 곡선. 오른쪽은 거울.
    // 테의 두 끝은 1px 줄의 가운데(탭 윗변 0.5 · 몸통 윗변 20.5)에 닿는다. 칠은 탭 안(0 ~ 20)만 — 그 아래는 몸통 칠이다.
    for (int i = 0; i < 4; i++) {
      final box = shoulderCell(i), right = i.isOdd;
      ui.Offset at(double x, double y) => ui.Offset(box.left + (right ? shoulderW - x : x), box.top + y);
      final curve = ui.Path()
        ..moveTo(at(0, 20.5).dx, at(0, 20.5).dy)
        ..cubicTo(at(3.85, 20.5).dx, at(3.85, 20.5).dy, at(3.15, .5).dx, at(3.15, .5).dy, at(7, .5).dx, at(7, .5).dy);
      canvas.save();
      canvas.clipRect(box);
      if (i < 2) {
        final area = ui.Path.from(curve)
          ..lineTo(at(7, 20).dx, at(7, 20).dy)
          ..lineTo(at(0, 20).dx, at(0, 20).dy)
          ..close();
        canvas.clipRect(ui.Rect.fromLTWH(box.left, box.top, shoulderW, 20));
        canvas.drawPath(area, fill);
      } else {
        canvas.drawPath(curve, line);
      }
      canvas.restore();
    }
    for (int i = 0; i < dotSizes.length; i++) {
      final box = dotCell(i);
      canvas.drawCircle(box.center, dotSizes[i] / 2, fill);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheetWidth * scale).ceil(), (_sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }
}
