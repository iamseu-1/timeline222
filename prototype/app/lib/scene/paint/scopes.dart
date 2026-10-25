import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' show Dim, Emphasis;
import '../layout.dart' show G, SceneLayout, ScopeState, ShelfMember;
import '../text_paragraph.dart';
import '../tile.dart';
import 'bands.dart';
import 'context.dart';
import 'host_folders.dart';
import 'links.dart';
import 'ink.dart';
import 'look.dart';
import 'paint_pick.dart';
import 'small_tags.dart';

// 대범위: 테두리(구역 23) · 기간의 짙은 구간(24) · 이름표와, **꺼 두어도 보이는 둘** — 본국 띠의 할거기 칠(25 · z-hollow)과
// 소속 펼치기 단추(26) · '▸ 〈성격〉 n' 단추(27). 값의 뜻은 docs/계약-아카이브-3단계.md 6-10절, 그리기 규칙은 docs/명세-3단계/04-관계선.md 6절.
//
// 켠 대범위에만 줄이 옮겨 가므로(명세 6-1) 구역 23 · 24는 **켠 상태에만 실려 온다** — 층은 실려 온 것을 그리기만 하고 켜고 끄기를 스스로 판단하지 않는다.
// 층 차례(명세 0절): 1층 테두리는 [paintTile](띠보다 뒤), 할거기 칠은 띠 채움 바로 뒤 · 칸 앞의 [paintOverBands], 단추는 띠 위라 관계선 층의 앞 판이 [ScopeMarks]로 부른다.

/// 대범위 테두리의 값(명세 1절 · 6-2 · 6-3 · css 1617~1658). 모두 px. 먹 값(먹 25 · 4% 따위)은 옛 값 — 그릴 때 그림판 먹 단계([CanvasInk])로 낸다.
abstract final class ScopeLook {
  /// 안쪽 그릇 = 상자(리메이크 2부 포개짐 · 목업 서고 box · 과제 7 걸음 2): 모따기 6 · 테 먹 25 · 뚜껑 칠 먹 4% · 뚜껑 밑선 먹 12(목업 · G5 #8 먹 표 '뚜껑 밑선 12' —
  /// 예전에는 테 먹 25) · 흰 라벨은 왼쪽 8 · 높이 16(뚜껑 [G.boxLid] 22 안 세로 가운데 — 다듬기 판 '뚜껑 22(흰 라벨 16)' · 예전 18 · 15).
  static const boxCham = 6, boxEdge = .25, boxLid = .04, boxRule = .12, boxLabelX = 8.0, boxLabelH = 16.0;

  /// 접힌 상자(과제 7 걸음 2 · 목업 container closed · 1배 w2-ga): 모따기 6 상자 한 줄(높이 [G.boxClosed] 24 — 합쳐진 줄의 띠 자리) · 칠 먹 6 · 테 먹 30
  /// (그림판 먹 단계 [CanvasInk]에는 6 · 30이 없어 자르기 표대로 4 · 25 — 가까운 단계 · 스위치 `ink`를 끄면 목업 값) · 위 + [closedRule] 6에 밑선 먹 12.
  /// 뚜껑 · 흰 라벨은 없다. 이름 10 굵게 먹 85(상자 왼쪽 + 8 · 화면에 잘리면 그림판 왼쪽 + 8) · 수 10 먹 45(이름 뒤 5) · 작은 꼬리표 [closedTags] 셋까지
  /// (수 뒤 + 14부터 오른쪽 − 26까지 · 넘치면 끝에 '+n' = 구성원 수 − 놓은 수) · ▸ 오른쪽 − 22(14 칸 가운데의 1px 계단 삼각형 · 먹 50 → 단계 45).
  /// 글 · 꼬리표 · ▸의 세로 가운데는 위 + [closedMid] 14.5(밑선 아래 칸 — 목업 꼬리표 위 + 8 · 높이 13).
  static const closedFill = .06, closedEdge = .30, closedRule = 6.0, closedTextX = 8.0, closedText = 10.0, closedCountGap = 5.0;
  static const closedTagGap = 14.0, closedTagEnd = 26.0, closedTags = 3, closedArrowX = 22.0, closedArrowW = 14.0, closedArrowInk = .5, closedMid = 14.5;

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
  /// 조감 이름표: 위 1 · 높이 10(머리 12 안에서 아래 1px이 빈다 — 보통 밀도 옛 테두리의 '머리 − 1'과 같은 틈).
  /// css 2004는 위 .5 · 높이 11이라 칩이 바로 아래 띠의 윗테와 0.5px만 띄고 맞닿아 아래가 잘린 듯 보였다(2026-10-25 조감 글자 겹침 — 웹은 띠 밑에 깔려 더 잘림).
  /// 글의 자리는 그대로다(9px 글줄 10.8을 칩 가운데에: 위 + .6 · 성격 8px은 위 + 1.2 — 예전 .5 + (11 − 10.8)/2와 같다).
  static const birdLabelTextSize = 9.0, birdKindTextSize = 8.0, birdLabelTop = 1.0, birdLabelHeight = 10.0;

  /// 할거기 칠: 세로 그라디언트(위아래 2px 투명 → 7px부터 종이색 92%)와 좌우 1px 파선(대범위 색 70% + 글자색, 짙기 .6).
  static const hollowFade = 7.0, hollowClear = 2.0, hollowPaper = .92, hollowEdgeAlpha = .6;
}

/// 그릇 폴더의 값(리메이크 조각 ③ · 설계 4-1 '가장 바깥 그릇' · 목업 blend.js folder · d2-b의 ftabH · handle · packTags). 모두 px.
/// 조감이 아닐 때 켠 대범위(그릇)는 옛 둥근 테두리 대신 폴더로 그린다 — 집합 보기의 판 둘레와 조감은 예전 그대로다.
/// 먹 값(겹선 12 · 라벨 종이 테 40 · 이름 85 · 수 50 · 열쇠표 글 65 · 실 45)은 옛 값 — 그릴 때 그림판 먹 단계([CanvasInk] — 12 · 45 · 85 · 45 · 60 · 45)로 낸다.
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

  /// 상국 탭에 막혀 이름이 들지 못하는 열쇠표의 작은 꼴(0.1.0 1배 지적 — `ScopeMarks._collectKeys`): 왼쪽 둥근 끝 6 + 구멍 뒤 6 — 이름 없이 구멍만.
  static const keyStub = 12.0;

  /// 매다는 실 · 매듭(설계 4-1 '실의 규칙 하나'): 먹 45(고른 띠는 먹) · 그릇 첫 줄은 몸통 윗변에, 둘째 줄부터는 띠 윗변 위 (위 틈 − 3)에 매듭.
  static const threadPct = .45, knotDrop = 3.0;

  /// 둘째 줄부터의 매듭 자리(화면 y — 1px 줄의 위): 띠 윗변 [bandTop] − 그 줄의 위 틈 + [knotDrop]. 관계선 층의 매다는 실(`links.dart _thread`)과
  /// 흠 ①의 가로대([ScopeLayer] 뒤 판)가 함께 쓴다 — 매듭이 가로대에 걸리게 같은 셈.
  static double knotY(PaintContext c, int row, double bandTop) => (bandTop - c.layout.tabOf(row) + knotDrop).roundToDouble();

  /// 흠 ① 고침(4단계 감독 고름 G5 #8 흠 라 — 고르기 판 `g-g5-8.js` hangThreads fix): 둘째 줄부터의 매듭이 걸리는 그릇 너비의 가로대 — 1px · 먹 12
  /// (안쪽 겹선과 같은 먹 — 그림판 먹 단계 12) · 몸통 안 왼 + 3 ~ 오른 − 3(안쪽 겹선 사이에 닿음 — 목업의 '오른 − 3.5'는 SVG 선 가운데라 앱 픽셀로 같은 자리).
  static const railAlpha = .12, railInset = 3.0;

  /// 흠 ③ 고침(G5 #8 흠 라 — 고르기 판 closedFolder fix): 접힌 폴더의 작은 꼬리표는 몸통 안 세로 가운데, 몸통 왼쪽(화면에 잘렸으면 그림판 왼쪽) + 10부터
  /// 몸통 오른쪽 끝 − 28까지(목업의 몸통 오른쪽 ▸ 자리 22 + 그 앞 틈 6을 비킴 — 앱은 ▸를 그리지 않고 세 상태는 오른쪽 클릭 메뉴) · 끝에 `+n`.
  static const closedTagX = 10.0, closedArrow = 28.0;

  /// 선반 줄(과제 7 걸음 4 · 메이커 서고 미리보기 css `.tl-shelf` — 폴더 발의 작은 꼬리표 줄 · 발에 더한 [G.shelfH] 19 자리): 그릇 아래 − [shelfRise] 20에
  /// 1px 금(먹 [shelfInk] 12 — 먹 알파 · 왼쪽 + [shelfInset] 6 ~ 오른쪽 − 6 · 화면에 잘린 쪽은 그림판 끝까지), 그 금 밑 [shelfPad] 3에 작은 꼬리표 13(아래 − 3).
  static const shelfRise = 20.0, shelfInset = 6.0, shelfPad = 3.0, shelfInk = .12;
}

/// 폴더 탭 · 상자 라벨 · 왼쪽 칸 폴더가 적는 그릇의 이름 수(과제 7 걸음 4). 선반 변형을 켠 그릇은 구역 23의 `b`가 **제 줄에 남은 수**라
/// 숨은 수([SceneLayout.shelfOf] — 구역 59의 `b`와 같음)를 더한다(계약 6-10절 덧붙임 '폴더 라벨에 그릇 전체의 이름 수를 쓰려면 둘을 더한다').
/// 옛 저장소(수 0) · 선반 변형을 켜지 않은 그릇(✓만 선반인 것 포함)은 그대로.
int scopeCountOf(PaintContext c, ScopeIn it, String uid) =>
    it.count > 0 && uid.isNotEmpty && c.layout.isShelfOn(uid) ? it.count + c.layout.shelfOf(uid).length : it.count;

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
    // 접힌 상자(과제 7 걸음 2): 틀 = 합쳐진 줄의 띠 자리(높이 [G.boxClosed] 24 — 위 틈 6은 그 위의 빈자리) · 몸통 윗변 = 밑선(위 + 6).
    final closed = layout.closedBoxRowOf(uid);
    if (closed >= 0 && depth > 0) {
      if (!layout.isVisible(closed)) return null;
      final geo = layout.geo(closed), top = layout.rowTop(closed) + geo.bandTop;
      return ScopeBox(top, geo.bandHeight, closed, closed, body: top + ScopeLook.closedRule, depth: depth);
    }
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

/// 이 장면의 **펼친** 폴더(켠 대범위 가운데 가지가 펼쳐진 것 — 선반 포함 · 조감 · 집합 보기 판 둘레는 빼고). 접힌 폴더에는 띠가 없어 실도 없다.
List<FolderSpot> openFolders(PaintContext c) {
  final out = <FolderSpot>[];
  if (c.layout.bird) return out;
  final v = c.v;
  for (final it in ScopeLayer.readScopes(c).values) {
    if (!it.folderIn(c)) continue;
    final uid = scopeUidOf(c, it);
    if (uid.isNotEmpty && !c.layout.scopeStateOf(uid).spread) continue;
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

/// 그릇 누름이 앱 틀에서 하는 일([ScopeLayer.actionOf] — 과제 7 검토 고침).
enum ScopePress {
  /// 켜고 끄기(0 — 본국 띠의 모아 보기 단추 · 모르는 번호). 왼쪽 칸 폴더는 이것을 받지 않는다(아무 일도 없음).
  toggle,

  /// 그 상태로(1 ~ 4 — 선반 기억을 맞춘다 · [SceneLayout.viewForScopeState]).
  state,

  /// 가지만 접고 펴기(5 [ScopeLayer.pressFold] — 선반 기억을 남긴다 · [SceneLayout.viewForScopeFold]).
  fold,
}

class ScopeLayer extends TileLayer {
  /// 구역 번호(계약 6-10절).
  static const secScope = 23, secSpan = 24, secHollow = 25;

  /// 그릇 안 이름표 시대의 둘째 탭(리메이크 2부 — 내보내기 `export/scopes.mjs` · row · row2 = 그 그릇의 구역 23과 같음 · text2 = 시대 구분 uid).
  static const secLabel = 53;

  /// 숨긴 구성원 꼬리표(선반 — 계약 6-10절 · 선반 변형 `shelf:<그릇 uid>`에만 실림): 가지 끝 줄 · 그 띠의 바깥 끝 · ref = 숨은 띠 · 이름 · 색 = 띠 ·
  /// a = 그릇 안 차례 · b = 숨은 수 · text2 = 그 띠의 uid. 폴더 · 상자 발의 선반 줄([_shelfRow])이 그린다(과제 7 걸음 4).
  static const secShelf = 59;

  /// 누름 5 — 그릇의 가지 접기 뒤집기(선반 기억은 남김 · 과제 7 걸음 5): 선반 기억에 든 그릇의 폴더 탭 · 상자 라벨 · 접힌 상자의 이름 · ▸ ·
  /// 풀린 그릇의 열쇠표 · 왼쪽 칸 폴더가 1 · 2 대신 이것을 싣는다 — 앱 틀이 [SceneLayout.viewForScopeFold]로 넣는다(메이커 서고 미리보기의 라벨 누름
  /// `toggleFoldPeople`(js/timeline.js 5649) · 열쇠표 `toggleScope`처럼 선반 기억이 남아, 다시 펴면 선반으로 돌아온다). 차림표의 네 줄과 선반 줄 누름(펼침)은
  /// 그대로 [SceneLayout.viewForScopeState]다(선반 기억을 뺀다). 1 ~ 4는 [ScopeState]의 차례 + 1(1 펼침 · 2 접힘 · 3 풀림 · 4 선반)이라 그 뒤에 둔다.
  static const pressFold = 5;

  /// 그릇 [uid]를 누를 때 실을 번호 — 선반 기억에 들었으면 [pressFold], 아니면 [state]([ScopeState] 차례 + 1) 그대로.
  static int pressOf(SceneLayout layout, String uid, int state) => layout.viewState.shelvedScopes.contains(uid) ? pressFold : state;

  /// 누름 번호 [press](폴더 탭 · 상자 라벨 · 열쇠표 · 왼쪽 칸 폴더가 싣는 줄 칸)가 앱 틀에서 할 일 — 앱 틀(그림판의 그릇 단추 · 왼쪽 칸 폴더)은
  /// 이것만 보고 가른다(과제 7 검토 고침 — 가르는 차례를 시험이 지킨다). [pressFold]가 먼저다: 1 ~ 4의 범위 검사보다 앞에 둬야 선반 기억에 든 그릇의
  /// 누름이 상태 바꾸기(선반 기억을 뺌)로 새지 않는다. 1 ~ 4 = 그 상태([ScopeState] 차례 + 1 — 둘째 값). 그 밖(0 — 본국 띠의 모아 보기 단추)은 켜고 끄기.
  static (ScopePress, ScopeState?) actionOf(int press) {
    if (press == pressFold) return (ScopePress.fold, null);
    if (press >= 1 && press <= ScopeState.values.length) return (ScopePress.state, ScopeState.values[press - 1]);
    return (ScopePress.toggle, null);
  }

  /// 밝기 상태(총괄이 이어 준다 — 없으면 중립).
  Emphasis? emphasis;

  /// 띠 층(그리개가 이어 준다 — 없으면 할거기 경계 파선이 가로 금 줄을 건너뛰지 않음 · [BandLayer.innerRows]).
  BandLayer? bands;

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

  /// 이번 판에 그린 폴더 탭의 누를 자리 — (자리, 대범위 uid, 바꿀 상태: 1 펼침 · 2 접힘 · 3 풀림 · 4 선반 · 5 가지 접기 뒤집기([pressFold])).
  /// 라벨은 펼침(선반) ↔ 접힘 — 선반 기억에 든 그릇은 5(선반 기억을 남김). 네 상태는 오른쪽 클릭 메뉴.
  final _folderHits = <(ui.Rect, String, int)>[];

  /// 그 자리의 폴더 탭(대범위 uid, 바꿀 상태 1 펼침 · 2 접힘 · 3 풀림 · 4 선반 — [ScopeState]의 차례 + 1 · 5 [pressFold]). 없으면 null.
  /// 맨 위(나중에 그린) 탭이 소속 폴더의 것이면 null — 그 누름은 [hitHostFolder]의 몫이다(그릇 네 상태가 없다 · 과제 8 걸음 3).
  (String, int)? hitFolder(double x, double y) {
    final h = _topFolderHit(x, y);
    return h == null || SceneLayout.isHostFolder(h.$2) ? null : (h.$2, h.$3);
  }

  /// 그 자리의 맨 위 탭이 소속 폴더의 라벨(깊이 0은 어깨 탭 · 1 이상은 상자 뚜껑)이면 그 폴더 uid(`host:<상국 uid>`), 아니면 null
  /// (리메이크 4단계 과제 8 걸음 3) — 화면이 [HostFolders.pressOf]로 소속 펼치기 단추와 같은 맞히기로 바꾼다.
  String? hitHostFolder(double x, double y) {
    final h = _topFolderHit(x, y);
    return h != null && SceneLayout.isHostFolder(h.$2) ? h.$2 : null;
  }

  (ui.Rect, String, int)? _topFolderHit(double x, double y) {
    final at = ui.Offset(x, y);
    for (final h in _folderHits.reversed) {
      if (h.$1.contains(at)) return h;
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
      if (!a.$1.contains(at) || SceneLayout.isHostFolder(a.$2)) continue; // 소속 폴더는 네 상태가 없다(과제 8 걸음 3)
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
    // 그릇 · 테두리의 칠은 아래(연도 세로줄)를 가리는 불투명 종이다(리메이크 4단계 세로줄 얹기 — paint/grounds.dart) — 그리는 차례가 곧 겹침이라
    // 판 → 깊이 얕은 것 → 같은 깊이는 줄 범위가 큰 것(바깥) 먼저 그린다(늦게 그린 바깥 그릇이 안쪽 상자를 덮지 않게).
    final order = _drawOrder(c, items.values);
    // 옛 테두리(집합 보기의 판 · 조감)는 칠(과 기간 칸)을 먼저 다 깔고, 테 · 이름표는 그릇까지 그린 뒤에 — 안쪽 테두리 · 그릇의 불투명 칠이
    // 바깥 테두리의 테를 덮지 않게(조감에서 겹쳐 켠 대범위 · 판의 첫 줄에 선 그릇).
    for (final it in order) {
      if (!it.folderIn(c)) _fillScope(c, it, spans[it.row * 1000003 + it.row2]);
    }
    for (final it in order) {
      if (it.folderIn(c)) _paintScope(c, it, spans[it.row * 1000003 + it.row2]);
    }
    for (final it in order) {
      if (!it.folderIn(c)) _paintScope(c, it, spans[it.row * 1000003 + it.row2]);
    }
    if (PaintPick.flaw) _paintRails(c, items.values);
  }

  /// 그리는 차례(불투명 종이라 차례가 곧 겹침): 집합 보기의 판 → 포개짐의 깊이가 얕은 것 → 같은 깊이는 줄 범위가 큰 것(바깥) → 실려 온 차례.
  List<ScopeIn> _drawOrder(PaintContext c, Iterable<ScopeIn> items) {
    final layout = c.layout;
    final keyed = <(ScopeIn, int, int, int)>[];
    var i = 0;
    for (final it in items) {
      final uid = it.folderIn(c) ? scopeUidOf(c, it) : '';
      final depth = it.board ? -1 : (uid.isNotEmpty && layout.scopeOnOf(uid) != null ? layout.scopeDepthOf(uid) : 0);
      keyed.add((it, depth, it.row2 - it.row, i++));
    }
    keyed.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : (a.$3 != b.$3 ? b.$3.compareTo(a.$3) : a.$4.compareTo(b.$4)));
    return [for (final k in keyed) k.$1];
  }

  /// 흠 ① 고침 — 둘째 줄 매듭의 가로대(4단계 감독 고름 G5 #8 흠 라 · 설계 4-6 #8 · 고르기 판 `g-g5-8.js` hangThreads fix). 펼친 그릇(폴더 · 상자)의
  /// 둘째 줄부터 매다는 실의 매듭은 줄 사이 틈에 떠 위 꼬리표에 매달린 듯 읽혔다 — 그 매듭 자리([FolderLook.knotY] — 관계선 층 `_thread`와 같은 셈)에
  /// 그릇 너비의 가로대(1px · 먹 12)를 그어 매듭이 그릇에 걸리게 한다(첫 줄 = 몸통 윗변 · 뚜껑 밑선과 같은 뜻 — 첫 줄은 그대로).
  /// 가로는 몸통 안 왼 + 3 ~ 오른 − 3, 화면에 잘린 쪽은 그림판 끝까지. 줄마다 한 번 — 그 줄을 품은 그릇 가운데 가장 안쪽(깊이가 큰) 것만이고
  /// (관계선 층이 실을 매다는 그릇과 같은 셈), 그 그릇이 접혔으면 없다. 이 층의 뒤 판(띠보다 뒤 · 이 걸음의 맨 앞)이라 받침 카드 · 상국 탭 · 열쇠표 ·
  /// 글자가 모두 그 위에 온다(설계 4-6 #11 공통 규칙 — 글자를 덮지 않음). 스위치 `flaw`가 꺼지면 없다.
  void _paintRails(PaintContext c, Iterable<ScopeIn> items) {
    final layout = c.layout, v = c.v;
    if (layout.bird) return;
    final boxes = <({ScopeBox box, bool open, double body, double bottom, double left, double right, bool clipL, bool clipR})>[];
    for (final it in items) {
      if (!it.folderIn(c)) continue;
      final box = scopeBoxOf(c, it);
      if (box == null) continue;
      final uid = scopeUidOf(c, it);
      final xl = v.xOf(it.start) - ScopeLook.padX, xr = v.xOf(it.end) + ScopeLook.padX;
      final clipL = xl < c.left - 1, clipR = xr > c.w + 1;
      boxes.add((
        box: box,
        open: uid.isEmpty || layout.scopeStateOf(uid).spread,
        body: v.yOf(box.body).roundToDouble(),
        bottom: v.yOf(box.top + box.height).roundToDouble(),
        left: (clipL ? c.left - 1 : xl).roundToDouble(),
        right: (clipR ? c.w + 1 : xr).roundToDouble(),
        clipL: clipL,
        clipR: clipR,
      ));
    }
    if (boxes.isEmpty) return;
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    final ink = CanvasInk.alpha(FolderLook.railAlpha, dim);
    for (final f in boxes) {
      if (!f.open || f.right < c.left - 2 || f.left > c.w + 2 || f.bottom < c.head || f.body > c.h) continue;
      final inset = _railInset(f.box.depth);
      final xa = f.clipL ? f.left : f.left + inset, xb = f.clipR ? f.right : f.right - inset;
      if (xb - xa < 1) continue;
      for (final r in layout.visibleRowsFrom(f.box.firstRow)) {
        if (r != f.box.firstRow && r < layout.rowCount && layout.tabOf(r) > FolderLook.knotDrop) {
          // 매다는 실과 같은 띠 윗변(구멍 높이에서 되돌린 값 — links.dart `_thread`의 sq.y − holeY).
          final bandTop = v.yOf(layout.rowTop(r) + layout.geo(r).bandTop + TagLook.holeY) - TagLook.holeY;
          final y = FolderLook.knotY(c, r, bandTop);
          var inner = bandTop > f.body && bandTop < f.bottom;
          for (final o in boxes) {
            if (!inner) break;
            if (o.box.depth > f.box.depth && bandTop > o.body && bandTop < o.bottom && o.left < f.right && o.right > f.left) inner = false;
          }
          if (inner && y >= c.head - 1 && y <= c.h) {
            c.quads.add(xa, y, xb, y + 1, ink);
            c.stats.shapes++;
            c.debug?.note('가로대', '$r ${xa.toStringAsFixed(1)},${y.toStringAsFixed(1)},${(xb - xa).toStringAsFixed(1)}');
          }
        }
        if (r == f.box.lastRow) break;
      }
    }
  }

  /// 가로대가 그릇 테에서 들어오는 몫. 폴더(깊이 0)는 [FolderLook.railInset](3 — 2 안의 안쪽 겹선 바로 옆에 닿음). 상자(깊이 > 0)는 겹선이 없어
  /// 3이면 테(left · right − 1)와 2px 떠 있었다 — 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off가 아니면)에서는 1(테 바로 옆).
  static double _railInset(int depth) => depth > 0 && PaintPick.rows != FloorRule.off ? 1 : FolderLook.railInset;

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
    HostFolders.addTo(c, out); // 소속 폴더(과제 8 걸음 2 — 몸은 host_folders.dart)
    return out;
  }

  /// 옛 테두리(집합 보기의 판 둘레 · 조감)의 화면 자리 — 화면 밖이면 null. 칠([_fillScope])과 테 · 이름표([_paintScope])가 함께 쓴다.
  ({double left, double width, double top, double height, bool clipL, bool clipR})? _oldBox(PaintContext c, ScopeIn it) {
    final box = scopeBoxOf(c, it);
    if (box == null) return null;
    final v = c.v;
    // 집합 보기의 판 둘레는 가로 전체(지금 연표의 `_scopeX` — 판이면 { xl: −2, xr: W + 2 }).
    final xl = it.board ? c.left - 2 : v.xOf(it.start) - ScopeLook.padX, xr = it.board ? c.w + 2 : v.xOf(it.end) + ScopeLook.padX;
    if (xr < c.left - 2 || xl > c.w + 2) return null;
    final left = math.max(xl, c.left - 1);
    final width = math.max(4.0, math.min(xr, c.w + 1) - left);
    final top = v.yOf(box.top), height = box.height;
    if (top > c.h || top + height < c.head) return null;
    return (left: left, width: width, top: top, height: height, clipL: xl < c.left - 1, clipR: xr > c.w + 1);
  }

  /// 옛 테두리의 모서리 반지름(왼쪽 위 · 오른쪽 위 · 오른쪽 아래 · 왼쪽 아래) — 화면에 잘린 쪽은 0, 본국 띠에 매달리면 위 모서리가 없다.
  (double, double, double, double) _oldCorners(ScopeIn it, bool clipL, bool clipR) {
    final radius = _bird ? ScopeLook.birdRadius : ScopeLook.radius;
    final rl = clipL ? 0.0 : radius, rr = clipR ? 0.0 : radius;
    final rt = it.hung ? 0.0 : 1.0;
    return (rl * rt, rr * rt, rr, rl);
  }

  /// 기간의 짙은 구간(명세 6-3)의 가로 자리 — 짐작한 기간이거나 테두리(몸통) 안 전체와 같으면 null. [left] ~ [right]는 테두리(몸통)의 바깥 자리.
  (double, double)? _spanRange(PaintContext c, ScopeIn it, (double, double)? span, double left, double right, bool clipL, bool clipR) {
    if (span == null || it.guessed) return null;
    final bw = clipL ? 0.0 : 1.0;
    final inner = right - left - bw - (clipR ? 0.0 : 1.0);
    final a = (c.v.xOf(span.$1) - left - bw).clamp(0.0, inner);
    final b = (c.v.xOf(span.$2) - left - bw).clamp(0.0, inner);
    if (b - a < 1 || !(a > .5 || b < inner - .5)) return null;
    return (left + bw + a, left + bw + b);
  }

  /// 옛 테두리의 칠(css 1627 — 대범위 색 9%)과 기간의 짙은 구간 칠(11%). 조감의 테두리는 그 자리 바탕색과 섞은 **불투명 종이**로 칠하고 바탕 칸으로 등록한다
  /// (안의 띠 · 매단 것이 그 빛과 섞인다 — 리메이크 4단계 세로줄 얹기). 집합 보기의 판은 칠을 반투명 그대로 두어 판 안 빈 바탕의 연도 세로줄이 보이고,
  /// 그 빛만 등록한다(판 안의 그릇 · 띠가 판 빛과 섞인 불투명 색을 얻게). 기간 칸은 칠 위라 반투명 그대로 · 등록만.
  void _fillScope(PaintContext c, ScopeIn it, (double, double)? span) {
    if (_done.contains(it.id)) return; // 이 장면에 이미 그린 테두리(테 · 이름표까지 — [_paintScope])
    final g = _oldBox(c, it);
    if (g == null) return;
    // css 1627 — 강조 밖의 테두리는 .45(`.tl-scope.is-dim`). 고르기에는 흐림 규칙이 없다.
    // 강조에 든 대범위(`is-match`)는 1이어야 하지만 `ScopeIn`에 uid가 없어 아직 가리지 못한다 — 보고의 '총괄이 이어 줄 것'.
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    final color = 0xff000000 | it.color;
    final fill = withAlpha(color, ScopeLook.fillPct * dim);
    final (tl, tr, br, bl) = _oldCorners(it, g.clipL, g.clipR);
    final right = g.left + g.width, bottom = g.top + g.height;
    if (it.board) {
      _roundRect(c, g.left, g.top, right, bottom, tl, tr, br, bl, fill);
      c.grounds.tint(g.left, g.top, right, bottom, fill);
    } else {
      _paperRoundRect(c, g.left, g.top, right, bottom, tl, tr, br, bl, fill);
    }
    final s = _spanRange(c, it, span, g.left, right, g.clipL, g.clipR);
    if (s != null) {
      final spanFill = withAlpha(color, ScopeLook.spanFillPct * dim);
      c.quads.add(s.$1, g.top + 1, s.$2, bottom - 1, spanFill);
      c.grounds.tint(s.$1, g.top + 1, s.$2, bottom - 1, spanFill);
    }
  }

  void _paintScope(PaintContext c, ScopeIn it, (double, double)? span) {
    if (!_done.add(it.id)) return;
    if (it.folderIn(c)) {
      _paintFolder(c, it, span);
      return;
    }
    final g = _oldBox(c, it);
    if (g == null) return;
    final left = g.left, width = g.width, top = g.top, height = g.height, clipL = g.clipL, clipR = g.clipR;
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    final edge = withAlpha(_edgeOf(it.color), ScopeLook.edgePct * dim);
    // 칠(과 기간 칸 칠)은 [_fillScope]가 이미 깔았다. 테두리: 곧은 네 변(네모 묶음) + 모서리의 1px 호. 본국 띠에 매달리면 위 테두리와 위 모서리가 없다.
    final (tl, tr, br, bl) = _oldCorners(it, clipL, clipR);
    if (!it.hung) _edgeLine(c, true, left + tl, left + width - tr, top, edge);
    _edgeLine(c, true, left + bl, left + width - br, top + height - 1, edge);
    if (!clipL) _edgeLine(c, false, top + tl, top + height - bl, left, edge);
    if (!clipR) _edgeLine(c, false, top + tr, top + height - br, left + width - 1, edge);
    _arcs(c, left, top, left + width, top + height, tl, tr, br, bl, edge);
    c.stats.shapes++;
    c.debug?.note(
      '대범위',
      '${it.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${width.toStringAsFixed(1)},${height.toStringAsFixed(1)}'
          '${it.hung ? ' 매달림' : ''}${clipL ? ' 왼쪽잘림' : ''}${clipR ? ' 오른쪽잘림' : ''}',
    );
    // 기간의 짙은 구간(명세 6-3)의 좌우 파선: 짐작한 기간이거나 테두리 전체와 같으면 없다.
    final s = _spanRange(c, it, span, left, left + width, clipL, clipR);
    if (s != null) {
      final se = withAlpha(_edgeOf(it.color), ScopeLook.spanEdgePct * dim);
      c.quads.vLine(s.$1, top + 1, top + height - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: top);
      c.quads.vLine(s.$2 - 1, top + 1, top + height - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: top);
      c.stats.shapes++;
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
    // 동군연합 폴더는 먹(과제 8 걸음 1) — 상국이 동군연합인 소속 폴더 · 성격이 동군연합인 그릇.
    final inked = HostFolders.inked(c, uid, it.label);
    final fill = inked ? CanvasInk.alpha(LidLook.folderFill, dim) : withAlpha(color, FolderLook.fillPct * dim);
    final edge = inked ? withAlpha(CanvasInk.gray(LidLook.folderEdge), dim) : withAlpha(mixOklab(color, Look.paper, FolderLook.edgePct), dim);
    const radius = FolderLook.radius;
    final rr = clipR ? 0.0 : radius, rl = clipL ? 0.0 : radius;
    // 몸통 칠 — 왼쪽 위는 어깨 탭이 서는 자리라 직각. 아래(연도 세로줄)를 가리는 불투명 종이(그 자리 바탕색과 섞은 9%)이고 바탕 칸으로 등록한다 —
    // 띠 사이 빈자리 · 뚜껑 · 탭 · 발까지 폴더 부분에는 세로줄이 없다(감독 2026-10-25 '할거 등 폴더 부분에도 세로선 없게').
    _paperRoundRect(c, left, body, right, bottom, 0, rr, rr, rl, fill);
    // 어깨 탭(칠 · 테) + 라벨 + 손잡이. 탭 아래에서는 몸통 윗변이 끊겨 탭이 몸통으로 열린다.
    final tabL = (clipL ? c.left + FolderLook.clipInset : left).roundToDouble();
    final tabR0 = _folderTab(c, it, uid, state, tabL, top, body, fill, edge, dim);
    final tabs = _tabSpans..clear();
    final tabR = _labelTabs(c, it, tabR0, body, math.min(right, c.w), fill, edge, dim, spans: tabs);
    if (tabL > left) _edgeLine(c, true, left, tabL, body, edge);
    _bodyTop(c, tabR0, tabR, right - rr, body, edge, tabs);
    _edgeLine(c, true, left + rl, right - rr, bottom - 1, edge);
    if (!clipL) _edgeLine(c, false, body, bottom - rl, left, edge);
    if (!clipR) _edgeLine(c, false, body + rr, bottom - rr, right - 1, edge);
    _arcs(c, left, body, right, bottom, 0, rr, rr, rl, edge);
    // 안쪽 겹선(2 안 · 둥근 8 · 먹 12 — 폴더 윤곽의 일부). 윗변은 탭 아래도 지난다.
    final inner = CanvasInk.alpha(FolderLook.innerAlpha, dim);
    const ir = radius - FolderLook.inset;
    final irr = clipR ? 0.0 : ir, irl = clipL ? 0.0 : ir;
    final il = clipL ? left : left + FolderLook.inset, iR = clipR ? right : right - FolderLook.inset;
    final iT = body + FolderLook.inset, iB = bottom - FolderLook.inset;
    if (iB - iT > 2 * ir) {
      _edgeLine(c, true, il, iR - irr, iT, inner);
      _edgeLine(c, true, il + irl, iR - irr, iB - 1, inner);
      // 왼쪽 위 귀는 직각(어깨 탭 자리)이라 윗변과 왼쪽 세로 겹선이 귀 한 점을 함께 칠했다(먹 12가 두 번 — 짙은 점). 맞닿음(감독 결정 2026-10-25
      // '모든 가로세로 구분선은 맞닿게' · 꼴 off가 아니면)에서는 세로 겹선을 윗변 다음 줄부터 — 귀는 윗변 하나가 칠한다.
      if (!clipL) _edgeLine(c, false, PaintPick.rows == FloorRule.off ? iT : iT + 1, iB - irl, il, inner);
      if (!clipR) _edgeLine(c, false, iT + irr, iB - irr, iR - 1, inner);
      _arcs(c, il, iT, iR, iB, 0, irr, irr, irl, inner);
    }
    c.stats.shapes++;
    c.debug?.note('폴더', '${it.name} ${state.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${(right - left).toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}'
        '${clipL ? ' 왼쪽잘림' : ''}${clipR ? ' 오른쪽잘림' : ''}');
    // 기간의 짙은 구간(명세 6-3 — 몸통 안에서): 짐작한 기간이거나 몸통 전체와 같으면 칠하지 않는다. 칠은 불투명 몸통 위라 반투명 그대로 · 빛만 등록.
    final s = _spanRange(c, it, span, left, right, clipL, clipR);
    if (s != null) {
      final spanFill = withAlpha(color, ScopeLook.spanFillPct * dim);
      c.quads.add(s.$1, body + 1, s.$2, bottom - 1, spanFill);
      c.grounds.tint(s.$1, body + 1, s.$2, bottom - 1, spanFill);
      final se = withAlpha(_edgeOf(it.color), ScopeLook.spanEdgePct * dim);
      c.quads.vLine(s.$1, body + 1, bottom - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: body);
      c.quads.vLine(s.$2 - 1, body + 1, bottom - 1, se, dash: ScopeLook.spanDash, gap: ScopeLook.spanGap, phase: body);
      c.stats.shapes++;
    }
    if (state == ScopeState.closed) {
      // 흠 ③ 고침(스위치 flaw): 작은 꼬리표가 몸통 안 세로 가운데 · 제 해 자리 · 끝에 +n(실 없음). 끄면 예전 — 탭 오른쪽 몸통 위 + 짧은 실.
      // 수는 구역 23의 b 그대로([scopeCountOf]를 쓰지 않음 — 과제 7 걸음 4): 접힘이 선반 기억을 이겨 선반 변형이 꺼져 있어 b가 곧 그릇 전체의 수다.
      if (PaintPick.flaw) {
        _closedTagsIn(c, box, it.count, (clipL ? c.left : left) + FolderLook.closedTagX, math.min(right, c.w) - FolderLook.closedArrow, (body + bottom) / 2);
      } else {
        _closedTags(c, box, tabR + FolderLook.tagFrom, math.min(right, c.w) - FolderLook.tagEnd, body);
      }
    }
    if (state == ScopeState.shelf) _shelfRow(c, it, uid, left, right, bottom, clipL, clipR, dim);
  }

  /// 안쪽 그릇 = 상자(리메이크 2부 포개짐 · 목업 서고 box · 과제 7 걸음 2): 모따기 6 몸통(칠 없음 · 테 먹 25 · 화면에 잘린 쪽은 직각) ·
  /// 뚜껑(상자 위 ~ [G.boxLid] 22 · 칠 먹 4% · 밑선 먹 12) 안 왼쪽 8의 흰 라벨 종이(높이 16 · 이름 · 수). 세 상태는 그릇 안 오른쪽 클릭 메뉴(예전 세 칸 손잡이).
  /// 가지가 접혔으면(접힌 상자 — [scopeBoxOf]가 합쳐진 줄의 띠 자리를 준다) 뚜껑 없는 모따기 상자 한 줄([_closedBox]).
  void _paintBox(PaintContext c, ScopeIn it, ScopeBox box, String uid, ScopeState state, double left, double right, double top, double body, double bottom, bool clipL, bool clipR) {
    final dim = emphasis?.markAlpha(mine: false, matched: false, pick: Dim.scopePick, dim: Dim.scopeDim) ?? 1.0;
    if (state == ScopeState.closed && c.layout.closedBoxRowOf(uid) >= 0) {
      _closedBox(c, it, box, uid, left, right, top, bottom, clipL, clipR, dim);
      return;
    }
    final edge = withAlpha(CanvasInk.gray(ScopeLook.boxEdge), dim), lid = withAlpha(CanvasInk.gray(ScopeLook.boxLid), dim);
    const k = ScopeLook.boxCham;
    final kl = clipL ? 0 : k, kr = clipR ? 0 : k;
    // 뚜껑 칠(위 1 ~ 몸통 윗변) — 모따기 귀는 1px 계단. 아래의 연도 세로줄을 가리는 종이다(리메이크 4단계 세로줄 얹기 · 4단계 마지막 합치기):
    // 흐릴 때(dim < 1)의 반투명 칠은 그 자리 바탕(바깥 그릇 몸통)과 미리 섞은 불투명 색으로 칠하고 바탕 칸으로 등록한다(그 위의 밑선 · 테 · 라벨 종이가
    // 이 빛과 섞이게). 흐림 없음이면 예전 불투명 회색 그대로(바이트 같음).
    for (int i = 0; i < k; i++) {
      c.grounds.fill(c.quads, left + (kl > 0 ? kl - i : 0), top + i, right - (kr > 0 ? kr - i : 0), top + i + 1, lid, register: true);
    }
    c.grounds.fill(c.quads, left, top + k, right, body, lid, register: true);
    // 뚜껑 밑선(먹 12 — 양 끝은 뒤에 긋는 세로 테가 덮는다) · 테(윗변 · 아랫변 · 양옆 + 네 귀의 빗변).
    // 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off가 아니면 — 구분선 갈래와 합칠 때 옮김): 밑선은 양옆 테 사이에서만 —
    // 전폭으로 그으면 테 열의 그 줄에 먹이 두 번 얹혀 흐린 상자(강조 밖)에서 귀가 짙은 점이 됐다. 화면에 잘린 쪽(테 없음)은 끝까지. 꼴 off면 예전 전폭.
    final joint = PaintPick.rows != FloorRule.off;
    _rule(c, joint && !clipL ? left + 1 : left, joint && !clipR ? right - 1 : right, body, withAlpha(CanvasInk.gray(ScopeLook.boxRule), dim));
    _chamferEdge(c, left, right, top, bottom, clipL, clipR, edge);
    c.stats.shapes++;
    // 라벨 종이(뚜껑 안 세로 가운데 — 높이 16).
    final nameLook = _folderName ??= TextLook(FolderLook.nameSize, ui.FontWeight.w700, CanvasInk.gray(.85));
    final countLook = _folderCount ??= TextLook(FolderLook.countSize, ui.FontWeight.w400, CanvasInk.gray(.5));
    final n = scopeCountOf(c, it, uid), count = n > 0 ? '$n' : '';
    final nw = c.text.widthOf(it.name, nameLook), cw = count.isEmpty ? 0.0 : c.text.widthOf(count, countLook);
    if (nw == null || cw == null) {
      c.scene.requestFrame();
      return;
    }
    const pad = FolderLook.labelPad, lh = ScopeLook.boxLabelH;
    final lw = (nw + (count.isEmpty ? 0 : FolderLook.countGap + cw) + 2 * pad).roundToDouble();
    final lx = (clipL ? c.left + FolderLook.clipInset : left + ScopeLook.boxLabelX).roundToDouble(), ly = top + ((body - top - lh) / 2).roundToDouble();
    final name = it.name;
    if (uid.isNotEmpty) _folderHits.add((ui.Rect.fromLTWH(lx, ly, lw, lh), uid, pressOf(c.layout, uid, state.spread ? 2 : 1)));
    _labels.add((c) {
      _paper(c, lx, ly, lw, lh, dim);
      c.later.add('folder', name, nameLook, lx + pad, ly + (lh - FolderLook.nameSize * 1.2) / 2, dim);
      if (count.isNotEmpty) c.later.add('folder', count, countLook, lx + pad + nw + FolderLook.countGap, ly + (lh - FolderLook.countSize * 1.2) / 2, dim);
    });
    // 접힌 상자 꼴이 서지 못한 접힘(합쳐진 줄이 다른 묶음에 먹힘 따위 — 드묾)은 예전처럼 뚜껑 뒤로 작은 꼬리표.
    if (state == ScopeState.closed) _closedTags(c, box, lx + lw + FolderLook.tagFrom, math.min(right, c.w) - FolderLook.tagEnd, body);
    // 상자의 선반 줄은 지금 서지 않는다(과제 7 걸음 3의 포개짐 규칙 ④ — [SceneLayout] `_scopePick` ② · ③): 켠 바깥 그릇 안의 그릇은 선반이어도 선반 변형을
    // 켜지 않고(✓만 선반), 바깥이 선반이면 안쪽 그릇은 꺼진다 — 상자(깊이 1 이상)가 선반 변형을 켤 일이 없다. 안쪽 그릇의 선반 변형이 생기면 쓰도록 길만 둔다.
    if (state == ScopeState.shelf) _shelfRow(c, it, uid, left, right, bottom, clipL, clipR, dim);
    c.debug?.note('상자', '${it.name} ${state.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${(right - left).toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}');
    c.debug?.note('상자라벨', '${it.name} ${lx.toStringAsFixed(1)},${ly.toStringAsFixed(1)},${lw.toStringAsFixed(1)},${lh.toStringAsFixed(1)}');
  }

  /// 모따기 [ScopeLook.boxCham] 상자의 1px 테 — 윗변 · 아랫변 · 양옆 + 네 귀의 빗변(1px 계단). 화면에 잘린 쪽은 직각이고 세로 변이 없다.
  /// 흐릴 때(dim < 1)의 반투명 테는 점마다 그 자리 바탕(뚜껑 · 접힌 상자 칠 · 바깥 그릇 몸통)과 미리 섞은 불투명 색으로(세로줄 얹기 — 테 위로 연도 세로줄이
  /// 비치지 않게 · [Grounds.fill]은 불투명 색이면 예전 네모 그대로).
  void _chamferEdge(PaintContext c, double left, double right, double top, double bottom, bool clipL, bool clipR, int edge) {
    const k = ScopeLook.boxCham;
    final kl = clipL ? 0 : k, kr = clipR ? 0 : k;
    void px(double l, double t, double r, double b) => c.grounds.fill(c.quads, l, t, r, b, edge);
    _rule(c, left + kl, right - kr, top, edge);
    _rule(c, left + kl, right - kr, bottom - 1, edge);
    if (!clipL) px(left.floorToDouble(), top + k, left.floorToDouble() + 1, bottom - k);
    if (!clipR) px((right - 1).floorToDouble(), top + k, (right - 1).floorToDouble() + 1, bottom - k);
    for (int i = 0; i < k; i++) {
      if (!clipL) {
        px(left + k - i - 1, top + i, left + k - i, top + i + 1);
        px(left + k - i - 1, bottom - i - 1, left + k - i, bottom - i);
      }
      if (!clipR) {
        px(right - k + i, top + i, right - k + i + 1, top + i + 1);
        px(right - k + i, bottom - i - 1, right - k + i + 1, bottom - i);
      }
    }
  }

  /// 1px 가로 금([Quads.hLine]과 같은 자리 — y는 내림) — 반투명 먹(흐림)이면 그 자리 바탕과 미리 섞은 불투명 색으로(세로줄 얹기 · [Grounds.fill]).
  static void _rule(PaintContext c, double x0, double x1, double y, int argb) {
    final row = y.floorToDouble();
    c.grounds.fill(c.quads, x0, row, x1, row + 1, argb);
  }

  TextLook? _closedName, _closedCount;

  /// 접힌 상자(과제 7 걸음 2 · 목업 container closed — 메이커 서고 미리보기가 5단계에 남긴 '접힌 상자의 모따기 꼴'): 합쳐진 줄의 띠 자리([top] ~ [bottom] — 24)에
  /// 모따기 6 상자 한 줄(칠 먹 6 · 테 먹 30 → 단계 4 · 25 · 위 + 6에 밑선 먹 12 · 뚜껑 · 흰 라벨 없음) — 이름 · 수 · 작은 꼬리표 셋까지 + '+n' · ▸.
  /// 이름 · ▸를 누르면 펼침([_folderHits] 상태 1 — 선반 기억에 든 그릇은 [pressFold] 5로 선반에 돌아감), 그 밖 자리는 오른쪽 클릭 차림표(부르는 쪽이 [_scopeAreas]에 상자 자리를 넣었다).
  /// 글 · 꼬리표 · ▸는 날짜 눈금보다 위라 표식 판([paintLabels])에서 그린다(접힌 폴더의 작은 꼬리표와 같은 판).
  void _closedBox(PaintContext c, ScopeIn it, ScopeBox box, String uid, double left, double right, double top, double bottom, bool clipL, bool clipR, double dim) {
    final fill = withAlpha(CanvasInk.gray(ScopeLook.closedFill), dim), edge = withAlpha(CanvasInk.gray(ScopeLook.closedEdge), dim);
    const k = ScopeLook.boxCham;
    final kl = clipL ? 0 : k, kr = clipR ? 0 : k;
    // 칠 — 위아래 모따기 귀는 1px 계단(빗변 픽셀 안쪽부터). 띠 자리를 대신하는 종이라 아래의 연도 세로줄을 가린다(리메이크 4단계 세로줄 얹기 ·
    // 4단계 마지막 합치기): 흐릴 때의 반투명 칠은 그 자리 바탕(바깥 그릇 몸통)과 미리 섞은 불투명 색으로 칠하고 바탕 칸으로 등록한다(밑선 · 테 · ▸ · 글이
    // 이 빛과 섞이게). 흐림 없음이면 예전 불투명 회색 그대로(바이트 같음).
    for (int i = 0; i < k; i++) {
      final a = left + (kl > 0 ? kl - i : 0), b = right - (kr > 0 ? kr - i : 0);
      c.grounds.fill(c.quads, a, top + i, b, top + i + 1, fill, register: true);
      c.grounds.fill(c.quads, a, bottom - i - 1, b, bottom - i, fill, register: true);
    }
    c.grounds.fill(c.quads, left, top + k, right, bottom - k, fill, register: true);
    // 밑선(위 + 6 · 먹 12 — 테 안쪽 왼 + 1 ~ 오른 − 1) · 테.
    final ruleY = top + ScopeLook.closedRule;
    _rule(c, left + (clipL ? 0 : 1), right - (clipR ? 0 : 1), ruleY, withAlpha(CanvasInk.gray(ScopeLook.boxRule), dim));
    _chamferEdge(c, left, right, top, bottom, clipL, clipR, edge);
    c.stats.shapes++;
    final edgeR = math.min(right, c.w);
    final arrowL = (edgeR - ScopeLook.closedArrowX).roundToDouble(), mid = top + ScopeLook.closedMid;
    c.debug?.note('상자', '${it.name} ${ScopeState.closed.name} ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${(right - left).toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}');
    // ▸(14 칸 가운데 — 1px 계단의 작은 삼각형 세로 7 · 가로 4 — 왼쪽 칸 머리 단의 접기 표와 같은 꼴) · 누르면 펼침.
    final lx = ((clipL ? c.left : left) + ScopeLook.closedTextX).roundToDouble();
    final arrowRoom = arrowL > lx + 4;
    if (arrowRoom && uid.isNotEmpty) _folderHits.add((ui.Rect.fromLTRB(arrowL, top, arrowL + ScopeLook.closedArrowW, bottom), uid, pressOf(c.layout, uid, 1)));
    // ▸ 먹도 흐릴 때는 그 자리(접힌 상자 칠 — 바로 위에서 등록) 바탕과 미리 섞은 불투명 색으로.
    final arrowInk = c.grounds.over(withAlpha(CanvasInk.gray(ScopeLook.closedArrowInk), dim), arrowL + ScopeLook.closedArrowW / 2, mid);
    // 이름 · 수(이름 뒤 5) — ▸ 앞 4까지 들 때만(못 들면 이름은 왼쪽 칸이 적는다 · 수만 빼 볼 수도 있다).
    final nameLook = _closedName ??= TextLook(ScopeLook.closedText, ui.FontWeight.w700, CanvasInk.gray(.85));
    final countLook = _closedCount ??= TextLook(ScopeLook.closedText, ui.FontWeight.w400, CanvasInk.gray(.45));
    // 수 · 아래 '+n'의 전체는 구역 23의 b 그대로(과제 7 걸음 4): 접힌 상자는 선반 변형이 꺼져 있어(접힘이 선반 기억을 이김) b가 그릇 전체의 수다.
    final count = it.count > 0 ? '${it.count}' : '';
    final nw = c.text.widthOf(it.name, nameLook), cw = count.isEmpty ? 0.0 : c.text.widthOf(count, countLook);
    if (nw == null || cw == null) {
      c.scene.requestFrame();
      if (arrowRoom) _labels.add((c) => _arrow(c, arrowL, mid, arrowInk));
      return;
    }
    final limit = arrowRoom ? arrowL - 4 : edgeR - 4;
    final showName = lx + nw <= limit, cx = lx + nw + ScopeLook.closedCountGap;
    final showCount = showName && count.isNotEmpty && cx + cw <= limit;
    final textTop = mid - ScopeLook.closedText * 1.2 / 2, name = it.name;
    if (showName && uid.isNotEmpty) _folderHits.add((ui.Rect.fromLTRB(lx - 2, top, (showCount ? cx + cw : lx + nw) + 2, bottom), uid, pressOf(c.layout, uid, 1)));
    // 작은 꼬리표: 수 뒤 + 14(수가 없으면 이름 뒤) ~ 오른쪽 − 26 · 셋까지 · 넘치면 끝에 +n(구성원 수 − 놓은 수).
    final from = showName ? (showCount ? cx + cw : lx + nw) + ScopeLook.closedTagGap : lx;
    final items = _mergedBands(c, box);
    final total = it.count > 0 ? it.count : items.length;
    final spots = total > 0 ? SmallTags.packCounted(c, items, from.roundToDouble(), edgeR - ScopeLook.closedTagEnd, total, max: ScopeLook.closedTags) : const <(double, double, String, int?)>[];
    if (spots == null) c.scene.requestFrame();
    c.debug?.note('접힌상자', '${it.name} 이름 ${showName ? lx.toStringAsFixed(1) : '-'} 수 ${showCount ? cx.toStringAsFixed(1) : '-'} ▸ ${arrowRoom ? arrowL.toStringAsFixed(1) : '-'} '
        '꼬리표 ${[for (final s in spots ?? const <(double, double, String, int?)>[]) '${s.$3}@${s.$1.toStringAsFixed(0)}+${s.$2.toStringAsFixed(0)}'].join(' ')}');
    _labels.add((c) {
      if (showName) c.later.add('boxName', name, nameLook, lx, textTop, dim);
      if (showCount) c.later.add('boxCount', count, countLook, cx, textTop, dim);
      for (final spot in spots ?? const <(double, double, String, int?)>[]) {
        SmallTags.paint(c, spot, mid, sprites.dot, tag: 'boxTag');
      }
      if (arrowRoom) _arrow(c, arrowL, mid, arrowInk);
    });
  }

  /// 접힌 상자의 ▸ — [x]부터 [ScopeLook.closedArrowW] 칸 가운데의 1px 계단 삼각형(세로 7 · 가로 4 — 왼쪽 세로 변에서 오른쪽 꼭짓점으로) · 세로 가운데 [mid].
  void _arrow(PaintContext c, double x, double mid, int ink) {
    final y = mid.floorToDouble(), x0 = x + ((ScopeLook.closedArrowW - 4) / 2).roundToDouble();
    for (int i = 0; i < 4; i++) {
      c.quads.add(x0 + i, y - 3 + i, x0 + i + 1, y + 4 - i, ink);
    }
    c.stats.shapes++;
  }

  /// 그릇 안 이름표 시대(리메이크 2부 · 설계 3-3 · 목업 서고 folder의 둘째 탭 — 구역 53): 폴더 윗변의 둘째 탭(높이 16 · 글 9.5 먹 75를 탭에 바로) —
  /// x = max(그 해의 자리, 앞 탭 오른쪽 + 4) · 오른쪽 = max(글 폭 + 12, 그 해의 끝). 칠 · 테는 폴더와 같고 위 두 귀는 모따기 3. 돌려줌 = 마지막 탭의 오른쪽(몸통 윗변이 거기서 이어진다).
  /// [spans]를 주면 그린 탭마다 (왼쪽, 오른쪽)을 적는다 — 몸통 윗변이 탭 사이에서도 이어지게([_bodyTop]). 맞닿음(감독 결정 2026-10-25 '모든 가로세로
  /// 구분선은 맞닿게' · 꼴 off가 아니면)에서는 탭의 두 세로 변이 몸통 윗변 줄([body])까지 내려와 윗변 끝과 ㄱ자로 맞닿는다(예전에는 body − 1에서 멈춰
  /// 귀 한 점이 비었다 — 탭 아래는 여전히 몸통으로 열림).
  double _labelTabs(PaintContext c, ScopeIn it, double from, double body, double maxRight, int fill, int edge, double dim, {List<(double, double)>? spans}) {
    var right = from;
    final sideEnd = PaintPick.rows == FloorRule.off ? body : body + 1;
    final look = _labelTabLook ??= TextLook(ScopeLook.labelTabText, ui.FontWeight.w700, CanvasInk.gray(.75));
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
        // 칠은 몸통과 같은 9% — 그 자리 바탕색과 섞은 불투명 종이(세로줄 얹기).
        for (int j = 0; j < k; j++) {
          c.grounds.fill(c.quads, xa + k - j, y0 + j, xr - k + j, y0 + j + 1, fill);
          c.quads.add(xa + k - j - 1, y0 + j, xa + k - j, y0 + j + 1, edge);
          c.quads.add(xr - k + j, y0 + j, xr - k + j + 1, y0 + j + 1, edge);
        }
        c.grounds.fill(c.quads, xa, y0 + k, xr, body, fill, register: true);
        c.quads.hLine(xa + k, xr - k, y0, edge);
        c.quads.vLine(xa, y0 + k, sideEnd, edge);
        c.quads.vLine(xr - 1, y0 + k, sideEnd, edge);
        c.stats.shapes++;
        _labels.add((c) => c.later.add('folderLabel', label, look, xa + ScopeLook.labelTabPad, y0 + (h - ScopeLook.labelTabText * 1.2) / 2, dim));
        spans?.add((xa, xr));
        c.debug?.note('둘째탭', '$label ${xa.toStringAsFixed(1)},${xr.toStringAsFixed(1)},${body.toStringAsFixed(1)}');
        right = xr;
      }
    }
    return right;
  }

  TextLook? _labelTabLook;

  /// [_paintFolder]가 폴더마다 다시 쓰는 둘째 탭의 자리(왼쪽, 오른쪽).
  final _tabSpans = <(double, double)>[];

  /// 폴더 몸통의 윗변(탭 아래는 끊겨 탭이 몸통으로 열림): 어깨 탭 오른쪽 [tabR0]부터 [end](오른쪽 귀 앞)까지. 예전에는 마지막 둘째 탭의 오른쪽 [tabR]부터만
  /// 그어 어깨 탭과 첫 둘째 탭 사이 · 둘째 탭 사이가 비었다(윗변이 끊겨 보임). 맞닿음(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' · 꼴 off가
  /// 아니면)에서는 탭 사이마다 긋는다 — 탭의 세로 변이 그 줄까지 내려오므로([_labelTabs]) 윗변은 탭 왼쪽 변 앞에서 멈추고 오른쪽 변 다음에서 다시 선다.
  void _bodyTop(PaintContext c, double tabR0, double tabR, double end, double body, int edge, List<(double, double)> tabs) {
    if (PaintPick.rows == FloorRule.off || tabs.isEmpty) {
      _edgeLine(c, true, tabR, end, body, edge);
      return;
    }
    var from = tabR0;
    for (final (xa, xr) in tabs) {
      _edgeLine(c, true, from, math.min(xa, end), body, edge);
      from = math.max(from, xr);
    }
    _edgeLine(c, true, from, end, body, edge);
  }

  /// 어깨 탭(목업 ftabH): 칠 · 테 · 흰 라벨 종이(이름 11 굵게 + 수). 세 상태는 그릇 안 오른쪽 클릭 메뉴(예전 세 칸 손잡이). 돌려줌 = 탭 오른쪽 끝(글자 폭을 아직 모르면 [x] — 탭 없이 다음 판에).
  double _folderTab(PaintContext c, ScopeIn it, String uid, ScopeState state, double x, double top, double body, int fill, int edge, double dim) {
    const s = FolderLook.shoulder, pad = FolderLook.labelPad, lh = FolderLook.labelH;
    final nameLook = _folderName ??= TextLook(FolderLook.nameSize, ui.FontWeight.w700, CanvasInk.gray(.85));
    final countLook = _folderCount ??= TextLook(FolderLook.countSize, ui.FontWeight.w400, CanvasInk.gray(.5));
    final n = scopeCountOf(c, it, uid), count = n > 0 ? '$n' : '';
    final nw = c.text.widthOf(it.name, nameLook), cw = count.isEmpty ? 0.0 : c.text.widthOf(count, countLook);
    if (nw == null || cw == null) {
      c.scene.requestFrame();
      return x;
    }
    final lw = (nw + (count.isEmpty ? 0 : FolderLook.countGap + cw) + 2 * pad).roundToDouble();
    final xR = x + s + 2 + lw + 2 + s;
    // 칠(가운데 네모 + 두 어깨) · 테(윗변 + 두 어깨의 곡선). 칠은 몸통과 같은 9% — 그 자리 바탕색과 섞은 불투명 종이(세로줄 얹기 · 어깨 조각은 그 어깨 자리의 바탕색과).
    final g = c.grounds;
    final shoulderL = g.over(fill, x + s - 1, body - 1), shoulderR = g.over(fill, xR - s + 1, body - 1);
    g.fill(c.quads, x + s, top, xR - s, body, fill, register: true);
    sprites.shoulder(right: false, stroke: false, left: x, top: top, argb: shoulderL);
    sprites.shoulder(right: true, stroke: false, left: xR - s, top: top, argb: shoulderR);
    sprites.shoulder(right: false, stroke: true, left: x, top: top, argb: edge);
    sprites.shoulder(right: true, stroke: true, left: xR - s, top: top, argb: edge);
    c.quads.add(x + s, top, xR - s, top + 1, edge);
    // 라벨 종이: 몸통 윗변 위 2에 아랫변. 라벨을 누르면 펼침 ↔ 접힘(폴더를 여닫는 손짓), 손잡이의 칸은 제 상태로.
    final lx = x + s + 2, ly = body - 2 - lh, name = it.name;
    if (uid.isNotEmpty) _folderHits.add((ui.Rect.fromLTWH(lx, ly, lw, lh), uid, pressOf(c.layout, uid, state.spread ? 2 : 1)));
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
    final e = withAlpha(CanvasInk.gray(.4), dim);
    c.quads.add(x, y, x + w, y + h, withAlpha(Look.paper, dim));
    c.quads.hLine(x, x + w, y, e);
    c.quads.hLine(x, x + w, y + h - 1, e);
    c.quads.vLine(x, y, y + h, e);
    c.quads.vLine(x + w - 1, y, y + h, e);
  }

  /// 접힌 폴더의 작은 꼬리표(목업 d2-b closedFolder · packTags): 합쳐진 가지 줄의 띠(구역 45 — 보는 때 안의 것)를 탭 오른쪽에 늘어놓고,
  /// 꼬리표마다 몸통 윗변으로 짧은 실을 내린다.
  void _closedTags(PaintContext c, ScopeBox box, double from, double to, double body) {
    final items = _mergedBands(c, box);
    if (items.isEmpty) return;
    final spots = SmallTags.pack(c, items, from, to);
    if (spots == null) {
      c.scene.requestFrame();
      return;
    }
    final mid = body - FolderLook.tagRise, thread = CanvasInk.gray(FolderLook.threadPct);
    _labels.add((c) {
      for (final spot in spots) {
        c.quads.vLine(spot.$1 + 5, mid + SmallTags.height / 2, body, thread);
        SmallTags.paint(c, spot, mid, sprites.dot, tag: 'folderTag');
      }
    });
  }

  /// 흠 ③ 고침(4단계 감독 고름 G5 #8 흠 라 · 설계 4-6 #8 · 고르기 판 `g-g5-8.js` closedFolder fix — 스위치 `flaw`): 접힌 폴더(깊이 0)의 몸통이 비어
  /// 무엇이 접혔는지 몸통이 말하지 않았다 — 합쳐진 가지 줄의 띠를 몸통 **안** 세로 가운데 [mid]에 제 해 자리로 늘어놓고([SmallTags.packCounted] ·
  /// [from] ~ [to]), 끝에 `+n`(n = 그릇 구성원 수 [count] − 놓은 꼬리표 수 · 옛 저장소처럼 수가 없으면 보는 때 안의 띠 수로) 하나. 몸통 위 짧은 실은 없다.
  /// 접힌 상자(깊이 1 이상)는 제 꼴([_closedBox] — 과제 7 걸음 2 · 같은 늘어놓기에 셋까지).
  void _closedTagsIn(PaintContext c, ScopeBox box, int count, double from, double to, double mid) {
    final items = _mergedBands(c, box);
    final total = count > 0 ? count : items.length;
    if (total <= 0) return;
    final spots = SmallTags.packCounted(c, items, from, to, total);
    if (spots == null) {
      c.scene.requestFrame();
      return;
    }
    if (spots.isEmpty) return;
    c.debug?.note('접힌꼬리표', '${box.firstRow} 가운데 ${mid.toStringAsFixed(1)} ${[for (final s in spots) '${s.$3}@${s.$1.toStringAsFixed(0)}'].join(' ')}');
    _labels.add((c) {
      for (final spot in spots) {
        SmallTags.paint(c, spot, mid, sprites.dot, tag: 'folderTag');
      }
    });
  }

  /// 접힌 그릇이 대신 보이는 띠 — 합쳐진 가지 줄의 띠(구역 45 · 보는 때 안의 것 · 같은 띠는 하나) — (시작 x · 이름 · 색)을 시작 x 차례로.
  List<(double, String, int)> _mergedBands(PaintContext c, ScopeBox box) {
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
    items.sort((a, b) => a.$1.compareTo(b.$1));
    return items;
  }

  /// 선반 줄(과제 7 걸음 4 · 메이커 서고 미리보기 css `.tl-shelf` · `_stagsHTML`): 선반 변형을 켠 그릇(폴더 · 상자 — [SceneLayout.isShelfOn])에 숨은 구성원이
  /// 있으면 발에 더한 [G.shelfH] 19 자리에 — 그릇 아래 − 20의 1px 금(먹 12 · 왼쪽 + 6 ~ 오른쪽 − 6 · 화면에 잘린 쪽은 그림판 끝까지)과 그 밑 3의 작은 꼬리표 13.
  /// 꼬리표는 구역 59 가운데 이 그릇의 숨은 띠([_shelfBands])를 띠 시작 자리에 해 차례로([SmallTags.packCounted]) 놓고, 끝의 '+n' = 숨은 수 전체
  /// ([SceneLayout.shelfOf] 길이 = 59의 `b`) − 놓은 수 — 보는 때 밖의 숨은 띠도 센다(흠 ③ 접힌 폴더와 같은 규칙. 미리보기의 '+n'은 자리가 막힌 것만 세어 뜻이 다르다 —
  /// 5단계 잔여). 그래서 보는 때 안에 숨은 띠가 하나도 없어도 금과 '+n'은 선다(빈 19 자리로 남지 않게).
  /// 금 · 꼬리표는 날짜 눈금보다 위라 표식 판([paintLabels])에서 그린다. 줄 전체(꼬리표 · '+n' 포함)를 누르면 펼침([_folderHits] 상태 1).
  /// 선반이 아닌 그릇 · 선반 변형이 없거나 켜지 않은 그릇(✓만 선반 — 발 19도 없음) · 조감에는 없다.
  void _shelfRow(PaintContext c, ScopeIn it, String uid, double left, double right, double bottom, bool clipL, bool clipR, double dim) {
    final layout = c.layout;
    if (uid.isEmpty || layout.bird || !layout.isShelfOn(uid)) return;
    final hidden = layout.scopeOnOf(uid)?.shelf ?? const <ShelfMember>[];
    if (hidden.isEmpty) return;
    final y = bottom - FolderLook.shelfRise;
    if (y > c.h || bottom < c.head) return;
    final xa = clipL ? left : left + FolderLook.shelfInset, xb = clipR ? right : right - FolderLook.shelfInset;
    if (xb - xa < 1) return;
    final from = ((clipL ? c.left : left) + FolderLook.shelfInset).roundToDouble(), to = math.min(right, c.w) - FolderLook.shelfInset;
    final mid = y + 1 + FolderLook.shelfPad + SmallTags.height / 2;
    final items = _shelfBands(c, hidden, from, to);
    final spots = SmallTags.packCounted(c, items, from, to, hidden.length);
    if (spots == null) c.scene.requestFrame();
    _folderHits.add((ui.Rect.fromLTRB(xa, y, xb, bottom - FolderLook.shelfPad), uid, 1));
    final ink = CanvasInk.alpha(FolderLook.shelfInk, dim);
    c.debug?.note('선반줄', '${it.name} ${xa.toStringAsFixed(1)},${y.toStringAsFixed(1)},${(xb - xa).toStringAsFixed(1)} 숨음 ${hidden.length} '
        '꼬리표 ${[for (final s in spots ?? const <(double, double, String, int?)>[]) '${s.$3}@${s.$1.toStringAsFixed(0)}+${s.$2.toStringAsFixed(0)}'].join(' ')}');
    _labels.add((c) {
      // 먹 12 알파의 금은 그 자리 바탕(그릇 발 — 몸통 종이)과 미리 섞은 불투명 색으로 긋는다(리메이크 4단계 세로줄 얹기 · 4단계 마지막 합치기 —
      // 금이 연도 세로줄과 만나는 점에 먹이 비쳐 짙은 점이 되지 않게). 바탕이 몸통 하나면 보이는 빛은 예전과 같다(±1).
      c.grounds.fill(c.quads, xa, y, xb, y + 1, ink);
      c.stats.shapes++;
      for (final spot in spots ?? const <(double, double, String, int?)>[]) {
        SmallTags.paint(c, spot, mid, sprites.dot, tag: 'shelfTag');
      }
    });
  }

  /// 선반 줄의 꼬리표 감 — 구역 59 항목 가운데 [hidden](이 그릇의 숨은 구성원)에 든 띠(항목의 text2 = 띠 uid · 같은 띠는 하나 — 타일에 잘려 온 조각은
  /// 바깥 끝을 모은다)로 [from] ~ [to]에 걸치는 것 — (시작 x · 이름 · 색)을 시작 차례(같으면 끝이 먼 것 먼저 — 미리보기 `_stagsHTML`과 같은 차례)로.
  List<(double, String, int)> _shelfBands(PaintContext c, List<ShelfMember> hidden, double from, double to) {
    final want = {for (final m in hidden) m.uid};
    final found = <String, (double, double, String, int)>{};
    for (final d in c.scene.draw) {
      final t = d.tile, sec = t.section(secShelf);
      if (sec.count == 0) continue;
      final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1), names = sec.u(Tile.itemName), colors = sec.u(Tile.itemColor), text2 = sec.u(Tile.itemText2);
      final origin = t.origin.toDouble();
      for (int i = 0; i < sec.count; i++) {
        final band = t.text(text2[i]);
        if (!want.contains(band)) continue;
        final lo = origin + x0[i], hi = origin + x1[i], old = found[band];
        found[band] = old == null ? (lo, hi, t.text(names[i]), colors[i]) : (math.min(old.$1, lo), math.max(old.$2, hi), old.$3, old.$4);
      }
    }
    final v = c.v;
    final list = [for (final b in found.values) if (v.xOf(b.$2) >= from && v.xOf(b.$1) <= to) b]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
    return [for (final b in list) (v.xOf(b.$1), b.$3, 0xff000000 | b.$4)];
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
    // 흐릴 때(고른 동안)의 반투명 이름표 칠도 그 자리 바탕색과 섞은 불투명 종이(세로줄 얹기 — 판의 이름표는 반투명 판 위에 선다).
    final fill = c.grounds.over(withAlpha(tint, dim), l + w / 2, t + height / 2);
    _roundRect(c, l, t, l + w, t + height, ScopeLook.labelRadius, ScopeLook.labelRadius, ScopeLook.labelRadius, ScopeLook.labelRadius, fill);
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
      final paperA = ScopeLook.hollowPaper * dim;
      final fade = math.min(ScopeLook.hollowFade, (bottom - top) / 2);
      final clearAt = math.min(ScopeLook.hollowClear, fade);
      // 좌우의 대범위 색 파선(구간의 끝이 띠 · 화면에 잘리지 않았을 때만 — 지금 연표의 at-s · at-e)
      final dashL = zl > .5 && flags[i] & Tile.clipLeft == 0, dashR = zl + zw < iw - .5 && flags[i] & Tile.clipRight == 0;
      // 가로 금 줄이 없는 띠(빈 목록 — 띠 층은 목록을 장면마다 비워 다시 쓴다)는 없음과 같다.
      final rows = PaintPick.rows == FloorRule.off ? null : bands?.innerRows[ref[i]], skip = rows == null || rows.isEmpty ? null : rows;
      // 맞닿음(꼴 off가 아니면): 종이 칠은 파선 열을 비켜(그 열 다음부터 · 앞까지 — 정수 열) 파선 열에서는 띠의 가로 금이 그대로 남는다 — 파선이 건너뛴
      // 가로 금 줄([_hollowEdge])의 그 점이 종이에 덮여 옅은 점(틈처럼 보임)이 되지 않게.
      final pl = skip != null && dashL ? l.floorToDouble() + 1 : l, pr = skip != null && dashR ? (rr - 1).floorToDouble() : rr;
      // 칠은 줄 몫의 띠 높이로 깔리는데, 꼬리표가 그보다 짧으면(사건 칸을 올린 꼬리표 · 꼬리표 밑 사슬) 그 밑 몫은 띠 칠이 아니라 띠 아래 바탕 위다 —
      // 그 몫은 그 자리 바탕색과 섞은 불투명 종이로 깐다(리메이크 4단계 세로줄 얹기 — 맨 아래 연도 세로줄이 8% 비치지 않게 · [_hollowBand]).
      // 꼬리표 위 몫(띠 칠 위)의 92% 종이는 일부러 비치는 칠이다 — 아래 띠 빛이 비쳐 '비어 있는 할거기'로 읽히는 것이 이 칠의 뜻(css 1652).
      final tagB = _tagBottomOf(c, r, ref[i], bandTop);
      _hollowBand(c, pl, pr, top + clearAt, top + fade, 0, paperA, tagB);
      if (bottom - fade > top + fade) _hollowBand(c, pl, pr, top + fade, bottom - fade, paperA, paperA, tagB);
      _hollowBand(c, pl, pr, bottom - fade, bottom - clearAt, paperA, 0, tagB);
      final edge = withAlpha(mixSrgb(0xff000000 | color[i], Look.ink, .70), ScopeLook.hollowEdgeAlpha * dim);
      if (dashL) _hollowEdge(c, l, top, bottom, edge, skip);
      if (dashR) _hollowEdge(c, rr - 1, top, bottom, edge, skip);
      c.stats.shapes++;
      c.debug?.note('할거기', '${ref[i]} ${l.toStringAsFixed(1)},${top.toStringAsFixed(1)},${zw.toStringAsFixed(1)},${(bottom - top).toStringAsFixed(1)}');
    }
  }

  /// 할거기 경계의 세로 파선(3 · 3 — 무늬는 [top]에서). [skip]이 있으면 그 줄(띠 몸통의 가로 금 · 칸 층 가로선 — [BandLayer.innerRows] · 오름차순)은 칠하지 않는다:
  /// 파선이 가로 금을 가로지르는 점에 먹이 두 번 얹혀 짙은 점이 되던 것을 가로 금 하나로(감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게' ·
  /// 꼴 off면 [skip]이 없어 예전 그대로). 나머지 줄의 무늬는 예전과 같다.
  static void _hollowEdge(PaintContext c, double x, double top, double bottom, int edge, List<double>? skip) {
    if (skip == null || skip.isEmpty) {
      c.quads.vLine(x, top, bottom, edge, dash: 3, gap: 3, phase: top);
      return;
    }
    var y = top;
    for (final row in skip) {
      if (row + 1 <= y || row >= bottom) continue;
      if (row > y) c.quads.vLine(x, y, row, edge, dash: 3, gap: 3, phase: top);
      y = row + 1;
    }
    if (bottom > y) c.quads.vLine(x, y, bottom, edge, dash: 3, gap: 3, phase: top);
  }

  /// 할거기 칠 한 켜([y0] ~ [y1] — 종이색의 짙기가 위 [a0]에서 아래 [a1]로 세로로 번짐). [tagB](꼬리표의 보이는 아랫변) 위는 띠 칠 위라 예전처럼
  /// 반투명 그대로(아래 띠 빛이 비치는 것이 이 칠의 뜻), 밑은 띠 아래 바탕 위라 1px 줄마다 그 줄 가운데의 짙기로 그 자리 바탕색과 섞은 불투명 색으로
  /// 칠하고 바탕 칸으로 등록한다(그림판의 꼭짓점 색 보간과 같은 값 — ±1 · 그 위에 얹는 꼬리표 밑 사슬 칸이 이 빛과 섞이게).
  void _hollowBand(PaintContext c, double l, double r, double y0, double y1, double a0, double a1, double tagB) {
    if (y1 <= y0 || r <= l) return;
    double alphaAt(double y) => a0 + (a1 - a0) * ((y - y0) / (y1 - y0)).clamp(0.0, 1.0);
    final cut = tagB.clamp(y0, y1);
    if (cut > y0) {
      final from = withAlpha(Look.paper, a0), to = withAlpha(Look.paper, cut < y1 ? alphaAt(cut) : a1);
      if (from == to) {
        c.quads.add(l, y0, r, cut, from);
      } else {
        c.quads.addFadeDown(l, y0, r, cut, from, to);
      }
    }
    if (cut >= y1) return;
    if (a0 == a1) {
      c.grounds.fill(c.quads, l, cut, r, y1, withAlpha(Look.paper, a0), register: true);
      return;
    }
    for (var y = cut; y < y1;) {
      final z = math.min(y1, y.floorToDouble() + 1);
      c.grounds.fill(c.quads, l, y, r, z, withAlpha(Look.paper, alphaAt((y + z) / 2)), register: true);
      y = z;
    }
  }

  /// 줄 [row]에 놓인 띠 [band]의 꼬리표가 보이는 아랫변(화면 y — 띠 층 [BandLayer.tagBottom] 그 셈 하나를 묻는다: 사건 칸을 남의 칸 층만큼 올린
  /// 꼬리표는 줄 몫의 띠 아랫변보다 짧고, 몸통이 없으면 이름 색줄 아랫변). [bandTop]은 띠 윗변(화면 y). 그 밑은 띠 아래 바탕이다.
  /// 띠 층이 없는 장면(시험)은 줄 몫의 띠 아랫변.
  static double _tagBottomOf(PaintContext c, int row, int band, double bandTop) =>
      BandLayer.of(c.scene)?.tagBottom(c, row, band, bandTop) ?? bandTop + c.layout.geo(row).bandHeight;

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

  /// [_roundRect]의 불투명 종이 꼴(리메이크 4단계 세로줄 얹기): 반투명 [fill]을 그 자리 바탕색과 섞은 불투명 색으로 칠하고(곧은 몫은 바탕 칸 경계에서 나눠 ·
  /// 모서리 조각은 그 모서리 자리의 바탕색과), 곧은 몫을 바탕 칸으로 등록한다 — 그 위에 얹는 띠 · 매단 것이 이 빛과 섞인다.
  void _paperRoundRect(PaintContext c, double l, double t, double r, double b, double tl, double tr, double br, double bl, int fill) {
    if (r - l < .5 || b - t < .5) return;
    final g = c.grounds;
    final top = math.max(tl, tr), bottom = math.max(bl, br);
    // 모서리 조각의 색은 등록 전에(이 칠의 곧은 몫이 모서리의 바탕으로 읽히지 않게).
    sprites.disc(ScopeCorner.topLeft, l, t, g.over(fill, l + tl / 2, t + tl / 2), tl);
    sprites.disc(ScopeCorner.topRight, r - tr, t, g.over(fill, r - tr / 2, t + tr / 2), tr);
    sprites.disc(ScopeCorner.bottomLeft, l, b - bl, g.over(fill, l + bl / 2, b - bl / 2), bl);
    sprites.disc(ScopeCorner.bottomRight, r - br, b - br, g.over(fill, r - br / 2, b - br / 2), br);
    if (top > 0) g.fill(c.quads, l + tl, t, r - tr, t + top, fill, register: true);
    if (bottom > 0) g.fill(c.quads, l + bl, b - bottom, r - br, b, fill, register: true);
    g.fill(c.quads, l, t + top, r, b - bottom, fill, register: true);
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
    // 꼬리표 윗변 위 바탕에 선 칠 — 고른 동안의 흐림(.5)은 그 자리 바탕색과 섞은 불투명 색(세로줄 얹기 걸음 4 — 아래 눈금이 비치지 않게).
    c.grounds.fill(c.quads, r.left, r.top, r.right, r.bottom, fill);
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
    final look = _keyLook ??= TextLook(FolderLook.keySize, ui.FontWeight.w700, CanvasInk.gray(.65));
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
        var kx = math.max(xa + 3, (last[band] ?? double.negativeInfinity) + FolderLook.keyGap).roundToDouble();
        if (kx > c.w) continue;
        var kw = w, text = label;
        // 상국 탭과 같은 윗변 위 틈을 다투면 열쇠표가 비킨다(0.1.0 1배 지적 — 4단계 상국 탭이 생기며 갈대 공국 위 '아홉 불씨 할거'가 '아랫물국'의 '아'를 덮었다).
        // 탭은 관계가 끝나는 해에 매여 움직이지 않는다(연합 겹 탭이 상국 탭을 비키는 것과 같은 차례). ① 탭 뒤로 밀어(실도 함께 옮겨 45° 그대로) 띠 끝 ·
        // 화면 끝 안에 다 들면 거기에, ② 아니면 제자리에 구멍만 남긴 작은 열쇠표(이름 없이 — 같은 그릇의 이름은 이웃 띠의 열쇠표가 보인다 · 누르면 그대로 펼침)로,
        // ③ 그것도 탭에 닿으면 없다. 띠 밖으로 내밀지 않고, 탭과 닿지 않는 열쇠표는 1px도 움직이지 않는다.
        final tabs = bands?.hostTabSpans(c, band) ?? const <(double, double)>[];
        if (_tabHit(tabs, kx, w) != null) {
          final limit = math.min(bands?.bandRightOf(band) ?? c.w, c.w) - Look.tabInset;
          double? moved;
          var at = kx;
          for (int k = 0; k <= tabs.length; k++) {
            final hit = _tabHit(tabs, at, w);
            if (hit == null) {
              moved = at;
              break;
            }
            at = (hit.$2 + FolderLook.keyGap).roundToDouble();
          }
          if (moved != null && moved + w <= limit) {
            kx = moved;
            xa = kx - 3;
          } else if (_tabHit(tabs, kx, FolderLook.keyStub) == null) {
            kw = FolderLook.keyStub;
            text = '';
          } else {
            c.debug?.note('열쇠표비킴', '$label 자리 없음 ${kx.toStringAsFixed(1)}');
            continue;
          }
          c.debug?.note('열쇠표비킴', '$label ${text.isEmpty ? '구멍만' : '탭 뒤'} ${kx.toStringAsFixed(1)}');
        }
        final ky = bandTop - FolderLook.keyRise - FolderLook.keyH;
        last[band] = kx + kw;
        _keys.add(_Key(xa, bandTop, kx, ky, kw, text, look));
        layer.addHit(LinkHitKind.scopeButton, band, uid, ui.Rect.fromLTWH(kx, ky, kw, FolderLook.keyH), to: ScopeLayer.pressOf(layout, uid, 1));
      }
    }
  }

  /// 열쇠표([x] ~ + [w])가 상국 탭([tabs] — 왼쪽에서 오른쪽 차례)과 [FolderLook.keyGap] 안으로 닿으면 그 탭(가장 왼쪽 것), 아니면 null.
  static (double, double)? _tabHit(List<(double, double)> tabs, double x, double w) {
    for (final t in tabs) {
      if (x < t.$2 + FolderLook.keyGap && x + w + FolderLook.keyGap > t.$1) return t;
    }
    return null;
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
    final thread = withAlpha(CanvasInk.gray(FolderLook.threadPct), dim);
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
    final paper = withAlpha(Look.paper, dim), edge = withAlpha(CanvasInk.gray(.4), dim);
    // 흰 종이: 띠 윗변 위 바탕에 선 것이라 고른 동안의 흐림(.5)은 그 자리 바탕색과 섞은 불투명 색(세로줄 얹기 걸음 4 — 아래 눈금이 비치지 않게).
    // 구멍의 종이 점은 그 종이 위라 그대로 반투명(예전 쌓임과 같은 빛).
    sprites.disc(ScopeCorner.topLeft, k.kx, k.ky, c.grounds.over(paper, k.kx + r / 2, k.ky + r / 2), r);
    sprites.disc(ScopeCorner.bottomLeft, k.kx, k.ky + r, c.grounds.over(paper, k.kx + r / 2, k.ky + r * 1.5), r);
    c.grounds.fill(c.quads, k.kx + r, k.ky, k.kx + k.w, k.ky + h, paper);
    c.quads.hLine(k.kx + r, k.kx + k.w, k.ky, edge);
    c.quads.hLine(k.kx + r, k.kx + k.w, k.ky + h - 1, edge);
    c.quads.vLine(k.kx + k.w - 1, k.ky, k.ky + h, edge);
    sprites.arc(ScopeCorner.topLeft, k.kx, k.ky, edge, r);
    sprites.arc(ScopeCorner.bottomLeft, k.kx, k.ky + r, edge, r);
    sprites.dot(4, hx - 2, hy - 2, thread);
    sprites.dot(2, hx - 1, hy - 1, paper);
    if (k.label.isNotEmpty) c.later.add('key', k.label, k.look, k.kx + FolderLook.keyTextX, k.ky + (h - FolderLook.keySize * 1.2) / 2, dim);
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
  /// 단추는 조감에만 서고(그 밖에는 플래그) 늘 띠 안(띠 높이 가운데 · 소속 단추는 띠 안 이름 뒤 · 대범위 단추는 본국 띠와 겹친 구간)이라,
  /// 흐린 칠도 불투명한 띠 칠 위다 — 바탕색과 섞지 않는다(세로줄 얹기 걸음 4에서 자리를 확인함).
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
