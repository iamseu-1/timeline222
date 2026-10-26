import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../layout.dart';
import '../row_labels.dart';
import '../scene.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import 'chains.dart';
import 'context.dart';
import 'ink.dart';
import 'links.dart' show TunnelLook;
import 'look.dart';
import 'paint_pick.dart';
import 'scopes.dart';
import 'small_tags.dart';
import 'sphere_lines.dart';
import 'sphere_threads.dart';
import 'strips.dart' show StripLayer;

// 왼쪽 칸(리메이크 2부 — 목업 서고 `mock/themes/blend.js`의 gutter대로): 트랙은 가는 세로 선 + 세로 이름, 그릇(폴더)은 폴더 그림 + 이름,
// 줄은 작은 꼬리표 그림 + 그 줄의 띠 이름(' · '로 이음), 문화권은 왼쪽 칸과 그림판을 가로지르는 머리 단(설계 4-6 #5 B).
// 옛 민족 칸 · 민족 딱지 · 줄 이름의 연도 · 부제 · 노선 표시 · 분류 색 점 · 트랙 사이 선은 목업에 없어 뺐다(감독 2026-10-15 "최대한 목업 반영").
//
// 그리기는 모두 묶음으로 한다: 칸 · 선 · 그림은 c.quads(1px 계단), 동그란 점은 제 그림판(GutterDots), 글자는 c.later. 항목마다 drawPath를 부르지 않는다.

/// 왼쪽 칸에서 누른 것의 종류.
enum GutterHitKind {
  /// 트랙 세로 이름 — 트랙 접기.
  trackName,

  /// 민족 칸 — 민족 접기.
  people,

  /// 줄 이름 — 그 띠의 상세.
  row,

  /// 줄 이름의 노선 표시 — 도읍 노선도 카드.
  cap,

  /// 분류 색 점 — 그 분류의 사건 줄.
  lane,

  /// 민족 딱지 — 그 민족의 문서(접기 단추가 아니다).
  chip,

  /// 문화권 머리 단 — 그 문화권 접기 · 펴기(리메이크 조각 ② · [GutterHit.uid] = 문화권 id).
  sphere,

  /// 폴더 그림 · 이름 — 그 그릇 펼침 ↔ 접힘(리메이크 2부 · [GutterHit.uid] = 대범위 uid · [GutterHit.row] = 누름 번호 1 펼침 · 2 접힘 ·
  /// 5 가지 접기 뒤집기 — 선반 기억에 든 그릇은 1 · 2 대신 5(`ScopeLayer.pressOf` · [ScopeLayer.pressFold] — 과제 7 걸음 5)).
  /// 앱 틀은 이 번호를 `ScopeLayer.actionOf`로만 가른다 — 1 ~ 3으로 거르면 선반 그릇의 누름이 사라진다.
  /// 소속 폴더(uid `host:…` — 리메이크 4단계 과제 8)의 줄이면 화면(timeline_view.dart)이 앱 틀에 이 맞히기 대신 소속 펼치기 단추의 맞히기
  /// (`HostFolders.pressOf` — memberButton · 상국 띠)를 보낸다 — 누르면 소속을 접는다.
  folder,

  /// 문화권 머리 단 밑의 사람 띠 — 그 사람의 창(리메이크 4단계 과제 4 걸음 3 · [GutterHit.uid] = 인물 uid · [GutterHit.cell]은 빈 글).
  /// 인물 기록이 없는 사람이면 첫 왕관의 띠 칸 창([GutterHit.uid] = 띠 uid · [GutterHit.cell] = `leader:i`). 머리 단 상자 안이라 그림판 몫에 있다.
  person,
}

/// 집합 보기의 왼쪽 칸 칩(원래 트랙 칩 `__from:…` · 제 민족 칩 `__bp:…` — 내보내기 `export/boards.mjs`의 묶음 열쇠)인가.
/// 칩은 접기 단추가 아니다(지금 연표의 `data-board-chip`) — 누름은 아무것도 하지 않는다.
bool isBoardChipKey(String key) => key.startsWith('__from:') || key.startsWith('__bp:');

/// 누른 자리가 무엇인가. [row]는 전체 줄 번호, [group]은 그 트랙의 묶음 번호, [lane]은 분류 번호.
class GutterHit {
  const GutterHit(this.kind, {this.track = -1, this.row = -1, this.group = -1, this.lane = -1, this.uid = '', this.cell = ''});
  final GutterHitKind kind;
  final int track, row, group, lane;
  final String uid;

  /// 칸 참조(사람 띠가 인물 기록 없이 첫 왕관의 칸 창을 열 때 `leader:i` — 그 밖은 빈 글).
  final String cell;

  @override
  String toString() => '$kind(track $track · row $row · group $group · lane $lane · $uid${cell.isEmpty ? '' : ' · $cell'})';
}

/// 왼쪽 칸의 값 — 지금 연표의 COL · G와 css의 마지막에 이기는 값(명세 05의 1.3절).
abstract final class Gut {
  static const trackColumn = 24.0, peopleColumn = 22.0;

  /// 트랙 이름 칸 왼쪽의 트랙 색 줄(`box-shadow: inset 3px 0 0`).
  static const trackBar = 3.0;

  /// 세로 글 한 자의 높이 = 글자 크기 + 자간. 트랙 이름 12.5 + .24em · 민족 칸 10.5 + .12em · 민족 딱지 9.5 + .06em.
  /// 집합 보기의 판 트랙 이름은 자간 .18em(css `.tl-track.is-board .tl-tname span`).
  static const trackPitch = 12.5 * 1.24, peoplePitch = 10.5 * 1.12, boardPitch = 12.5 * 1.18;

  /// 집합 보기: 판 트랙의 왼쪽 칸 바탕은 판 색 7% · 트랙 이름 칸은 18%(css `.tl-track.is-board .tl-tbox` · `.tl-tname`),
  /// 원래 트랙 칩(`.tl-people.is-from`)은 점선 테두리 판 · 트랙 색 60% · 바탕 14% · 글 굵기 600 · 색 45%.
  /// 칩 글이 드는지는 세로 글 한 자 12.5 · 위아래 여유 8로 잰다(설계 결정 2의 규칙 — 반쯤 잘린 글자가 없게).
  static const boardBoxMix = .07, boardNameMix = .18, fromFillMix = .14, fromTextMix = .45, boardFits = 12.5, boardFitPad = 8.0;

  /// 이름이 드는지 재는 값은 지금 연표의 어림수 그대로다(같은 후보를 고르게).
  static const trackFits = 15.5, peopleFits = 11.8;

  /// 줄 이름 칸: 좌우 여백 8(소속 줄은 왼쪽 18) · 점과 글 사이 7(조감 5) · 모서리 7(조감 4).
  static const rowPad = 8.0, memberPad = 18.0, rowGap = 7.0, birdRowGap = 5.0, rowRadius = 7.0, birdRowRadius = 4.0;
  static const dot = 6.0, memberDot = 4.0, birdDot = 5.0;
  static const peopleRadius = 8.0, birdPeopleRadius = 5.0;

  /// 부제(11px)와 그 앞의 8×1 가로선, 글줄 사이 1px. 가로선은 부제 글줄의 위에서 9.9px 아래(기준 덤프의 픽셀로 잰 자리 — `vertical-align: middle`).
  static const subSize = 11.0, subLine = 16.5, lblGap = 1.0, subMark = 8.0, subMarkGap = 4.0, subMarkY = 9.9;

  /// 분류 색 점: 줄 이름 칸 오른쪽 끝에서 5px 안쪽 · 7×7 · 글줄 높이 21마다.
  static const laneRight = 5.0, laneDot = 7.0;

  /// 노선 표시: 14×7(점 둘 + 가로선) · 이름과 5px 띄고 · 밑줄에서 1px 올라감 · 옅기 .45.
  static const capWidth = 14.0, capHeight = 7.0, capGap = 5.0, capLift = 1.0, capAlpha = .45;

  /// 노선 표시의 점은 `radial-gradient(… 0 2.1px, transparent 2.7px)` — 4.2px까지 제 색이고 5.4px까지 고르게 옅어진다.
  /// 옅어지는 고리는 그 몫의 평균(.5)으로 한 겹 더 찍어 흉내 낸다(기준 그림에서 점이 4.2px보다 한 둘레 커 보였다).
  static const capDot = 4.2, capHalo = 5.4, capHaloAlpha = .5;

  /// 접힌 트랙의 머리글(`.tl-fold`): 좌우 여백 12 · 왼쪽에 온 이름 13px/700 · 오른쪽에 `펼치기 ▸` 11px.
  static const foldPad = 12.0, foldName = 13.0, foldHint = 11.0;
  static const foldHintText = '펼치기 ▸';

  /// 문화권 머리 단(리메이크 조각 ② · 목업 d5-b): 왼쪽 칸 왼쪽 3에서 그림판 오른쪽 끝까지 · 높이 [G.sphereHead] − 1 · 왼쪽 두 귀 모따기 5 ·
  /// 칠 먹 3% · 테 먹 25 · 구멍(왼쪽 7) · 이름 11 굵게 먹 85 (왼쪽 19) · 띠 수 10 먹 45 · 오른쪽 끝에 접기 표(▾ 펼침 · ▸ 접힘 — 11 · muted).
  static const sphereLeft = 3.0, sphereCham = 5.0, sphereName = 11.0, sphereCount = 10.0, sphereNameX = 19.0, sphereHoleX = 7.0, sphereMarkRight = 16.0;
  static const sphereFill = .03, sphereEdge = .25;

  /// 접힌 민족 칸(`.tl-people.is-folded span`): 가로 글 11px · 자간 0 · 좌우 여백 4 · 색은 민족 색 70% + 먹.
  static const foldedPeopleSize = 11.0, foldedPeoplePad = 4.0;

  /// 민족 딱지(`.tl-pchip`): 오른쪽 끝 단 안에 left = (depth−1)×22 + 4 · 폭 22 − 8 · 모서리 5 · 세로 글 9.5px/600 자간 .06em.
  /// 한 단뿐인 대범위 가지 안에서는 가는 띠(왼쪽 22 − 2 − 6 · 폭 5 · 글 없음 · 오른쪽만 둥글게 3).
  static const chipPad = 4.0, chipRadius = 5.0, chipSize = 9.5, chipFits = 10.1, chipPitch = 9.5 * 1.06;
  static const chipThinLeft = peopleColumn - 2 - 6, chipThinWidth = 5.0, chipThinRadius = 3.0;

  /// 올린 줄 · 칸의 바탕(css `.tl-row.is-hot` 12% · `.tl-row.is-folded:hover` 16% · `.tl-people:hover` 22% · `.tl-pchip:hover` 72% · `.tl-tname:hover` 16%).
  static const hotRowMix = .12, hotFoldedMix = .16, hotPeopleMix = .22, hotChipMix = .72, hotTrackMix = .16;

  /// 대범위 칸의 점선 테두리(css `border-style: dashed` — 1px 테는 3px 긋고 3px 띄움).
  static const dash = 3.0, dashGap = 3.0;

  /// body의 자간 −0.01em이 줄 이름에도 물려 온다(기준 화면에서 −0.14px).
  static const letterSpacing = -0.14;

  /// 글줄 높이는 글자 크기의 1.5배(css의 line-height: 1.5), 글자 그림은 1.2배 상자.
  static const lineRatio = 1.5, boxRatio = 1.2;

  /// 이 PC의 Noto Sans KR의 글줄 값(hhea): ascent 1.16em · descent 0.288em · 합 1.448em.
  /// 브라우저도 새 엔진도 같은 값을 쓴다(`Paragraph.alphabeticBaseline`과 브라우저의 밑줄 자리를 크기 9.5~13.5로 재어 확인).
  static const ascent = 1.16, inlineBox = 1.448, baseline = ascent / inlineBox;

  /// css의 글줄 상자(line-height [lineHeight]) 안에서 밑줄이 앉는 자리 — 브라우저는 **반내림해 정수 px**에 놓는다
  /// (12.5/18.75 → 14 · 11/16.5 → 13 · 10.5/15.75 → 12 · 13.5/20.25 → 16 · 9.5/9.5 → 8 — 모두 재어 맞췄다).
  static double baselineIn(double lineHeight, double size) => ((lineHeight - inlineBox * size) / 2 + ascent * size).floorToDouble();

  /// 글줄 상자의 위가 [lineTop]일 때 글자 그림 상자(1.2배)의 위 자리.
  /// 브라우저는 밑줄을 화면 px에 맞춰 찍으므로 밑줄을 반올림한 뒤 글자 상자 안의 밑줄 비율(1.2 × 1.16/1.448 = 0.9613)만큼 올린다.
  static double textTopAt(double lineTop, double lineHeight, double size) => (lineTop + baselineIn(lineHeight, size)).roundToDouble() - boxRatio * baseline * size;

  /// 글줄 상자 안에서의 글자 그림 위 자리(자리를 재기만 할 때 — 화면 px 맞춤은 [textTopAt]).
  static double textTopIn(double lineHeight, double size) => baselineIn(lineHeight, size) - boxRatio * baseline * size;

  /// 이름이 들 폭을 잴 때 늘 빼는 값: 8(왼쪽 여백) + 6(점) + 7(틈) + 8(오른쪽 여백).
  static const nameRoom = 29.0;

  /// 분류를 못 찾았을 때의 색(지금 연표 `_laneKey`).
  static const unknownCategory = 0xa4b1b7;
}

/// 왼쪽 칸의 동그란 조각(줄의 색 점 6 · 소속 줄 4 · 조감 5 · 분류 색 점 7과 그 둘레 9 · 노선 표시의 점 4.2)을
/// 크기마다 한 번 그려 두고 한 번에 찍는다. `scene/sprites.dart`의 조각은 7px · 13px 원뿐이라 그것을 줄여 찍으면
/// 작은 점의 테두리가 흐려진다(기준 그림과 대조할 때 점이 한 둘레 작아 보였다) — 그래서 제 층의 그림판을 둔다.
class GutterDots {
  GutterDots._(this._image, this._scale);
  ui.Image _image;
  double _scale;

  static const sizes = [4.0, 4.2, 5.0, 5.4, 6.0, 7.0, 9.0];
  static const _cell = 16.0;

  static GutterDots? _shared;
  static GutterDots get shared => _shared ??= GutterDots._(_render(1), 1);

  /// 멎은 돋보기 배율(× 화면의 px 비율)이 바뀌면 그 배율로 다시 뜬다(작아서 싸다).
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image.dispose();
    _image = _render(next);
    _scale = next;
  }

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..isAntiAlias = true;
    for (int i = 0; i < sizes.length; i++) {
      final r = sizes[i] / 2;
      canvas.drawCircle(ui.Offset(i * _cell + r, r), r, white);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync((sizes.length * _cell * scale).ceil(), (_cell * scale).ceil());
    picture.dispose();
    return image;
  }

  Float32List _transforms = Float32List(4 * 128), _rects = Float32List(4 * 128);
  Int32List _colors = Int32List(128);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 지름 [size]의 점 하나를 왼쪽 위 자리에 찍는다. 없는 크기는 가장 가까운 것을 늘려 찍는다.
  void add(double size, double left, double top, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    int at = 0;
    for (int i = 1; i < sizes.length; i++) {
      if ((sizes[i] - size).abs() < (sizes[at] - size).abs()) at = i;
    }
    final p = _n * 4, s = _scale, source = sizes[at];
    _transforms[p] = size / source / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = at * _cell * s;
    _rects[p + 1] = 0;
    _rects[p + 2] = (at * _cell + source) * s;
    _rects[p + 3] = source * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }
}


/// 맞히기용 자리 한 칸. 장면마다 새로 만들지 않고 밭에 두고 값만 갈아 쓴다 —
/// [GutterHit]은 정말로 맞혔을 때만 만든다(장면마다 줄 수만큼 만들던 것을 없앴다).
class _HitBox {
  double left = 0, top = 0, right = 0, bottom = 0;
  GutterHitKind kind = GutterHitKind.row;
  int track = -1, row = -1, group = -1, lane = -1;
  String uid = '', cell = '';

  bool has(double x, double y) => x >= left && x < right && y >= top && y < bottom;
  GutterHit get hit => GutterHit(kind, track: track, row: row, group: group, lane: lane, uid: uid, cell: cell);
}

/// 세로 글 한 줄을 미리 재 둔 것 — 글자와 그 자리 폭. 이름과 글꼴이 그대로면 장면마다 폭을 다시 묻지 않는다
/// (자리 셈은 그릴 때 그대로 하므로 소수점까지 옛 자리와 같다).
class _Upright {
  _Upright(this.text, this.shape, this.size, this.letters, this.widths);
  final String text;
  final int shape;
  final double size;
  final List<String> letters;
  final List<double> widths;

  bool fits(String text, TextLook look) => this.text == text && shape == look.shapeKey && size == look.size;
}

/// 이름을 고르고(줄임) 그 세로 자리까지 함께 보관하는 칸 하나.
class _Vertical {
  String? text;
  int tick = -1;
  String source = '';
  _Upright? upright;
}

/// 왼쪽 칸의 목업 값(리메이크 2부 — 목업 서고 `mock/themes/blend.js`의 gutter · 감독 2026-10-15 "최대한 목업 반영 · 완전 리메이크").
abstract final class GutLook {
  /// 칸 폭(목업 GUT)과 오른쪽 테(먹 8 — 목업 frame의 GUT − .5 세로 선).
  static const width = 240.0, edgeInk = .08;

  /// 트랙(그 문화권과 이름이 다를 때만): 세로 글 10 굵게 · 먹 60 · 가운데 x 31 · 한 자 12, 그 왼쪽의 가는 세로 선(x 23 · 먹 20 · 위아래 2 안).
  static const trackX = 31.0, trackSize = 10.0, trackPitch = 12.0, trackInk = .6, lineX = 23.0, lineInk = .2, lineInset = 2.0;

  /// 트랙 이름을 누를 자리(세로 선에서 이름까지).
  static const trackHitLeft = 18.0, trackHitRight = 40.0;

  /// 그릇(펼친 · 접힌 폴더): 그림 왼쪽 44 + 깊이 × 10 · 세로 가운데 = 그릇 위 + 11 · 그림 12(먹 60 — 1px 선이라 한 단 짙게 70) ·
  /// 이름은 그림 + 17 · 11 굵게 · 먹 85 · 접힌 폴더는 이름 뒤 5에 띠 수(10 · 먹 45).
  static const boxX = 44.0, step = 10.0, boxMid = 11.0, boxText = 17.0, boxInk = .85, iconInk = .7, countSize = 10.0, countInk = .45, countGap = 5.0;

  /// 접힌 상자(과제 7 걸음 2)의 세로 가운데 = 상자 위 + 14 — 그림판의 상자 한 줄(합쳐진 줄의 띠 자리 24 · 이름 · 꼬리표의 가운데 위 + 14.5 — [ScopeLook.closedMid])에 맞춘다.
  /// 펼친 상자는 [boxMid] 11이 뚜껑 22 안 라벨 16의 가운데와 같다.
  static const closedBoxMid = 14.0;

  /// 줄: 작은 꼬리표 그림(12 × 8 · 왼쪽 모따기 2 · 그 띠의 칠 24% · 테 84%)은 왼쪽 47 + 깊이 × 10 · 이름은 그림 + 16 · 11 굵게 · 먹 80(올리면 먹) ·
  /// 세로 가운데 = 띠 위 + min(높이, 이름 색줄 14)/2 − .5 · 이름 = 보는 범위에 든 그 줄의 띠 이름을 시작 차례로 ' · '(넘치면 끝을 '…' — 칸 오른쪽 10 앞까지).
  static const rowX = 47.0, rowText = 16.0, rowSize = 11.0, rowInk = .8, rightPad = 10.0;
  static const tagW = 12.0, tagH = 8.0, tagCham = 2, tagFill = .24, tagEdge = .84;
  static const joiner = ' · ', more = '…';
}

/// 왼쪽 칸 민족 머리 줄의 값(0.1.1 감독 "민족이 안보여" → 감독 고름 '나' — [PaintPick.people] · 끄면 쓰지 않는다 · 설계 4-4 재료: 흰 종이 + 먹 선 · 이름 9).
abstract final class PeopleLook {
  /// 이름 9 굵게 · 이름 글 = 민족 색 + 먹 55 · 선 = 민족 색 + 먹 16(설계 4-4 '나라 색 섞임 — 먹 쪽').
  static const nameSize = 9.0, nameInk = .55, lineInk = .16;

  /// 머리 줄 — ▾(7 × 4 · 먹 45)의 왼쪽 44 + 단 × 10 · 이름은 + 10 · 이름 뒤 5부터 칸 오른쪽 10 앞까지 1px 선.
  /// 민족 선은 '민족 색 + 먹 16'을 종이 쪽으로 반([headLine]) — 트랙 선(먹 20)보다 짙지 않게.
  static const nameX = 10.0, lineGap = 5.0, markInk = .45, headLine = .5;

  /// 붙은 머리 줄(긴 묶음을 내려 볼 때 — 문화권 머리 단처럼 그림판 위에 붙음): 종이 바탕의 왼쪽 41(트랙 칸 18 ~ 40 밖 — 트랙 선 · 이름은 그대로) ·
  /// 붙은 줄들 밑 1px 테(먹 8 — 왼쪽 칸 오른쪽 테와 같은 먹).
  static const stickLeft = 41.0;

  /// 한 줄짜리 묶음의 이름(머리 줄 대신 그 줄 이름 뒤): 줄 이름 뒤 6 띄움 · 들지 않으면 줄인 이름 · 그도 안 들면 적지 않는다(줄 이름이 이김).
  static const inlineGap = 6.0;

  /// 딱지: 줄 이름 앞 점 4(딱지 색 + 먹 16) · 점 뒤 3 띄우고 이름.
  static const chipDot = 4.0, chipGap = 3.0;
}

/// 이번 장면의 폴더 하나(왼쪽 칸이 그 그림 · 이름을 적고, 안의 줄을 한 단 들인다).
class _Folder {
  const _Folder(this.name, this.uid, this.box, this.closed, this.count, this.rows);
  final String name, uid;
  final ScopeBox box;
  final bool closed;
  final int count;

  /// 그 그릇의 묶음 줄 집합(리메이크 2부 포개짐 — 번호 범위가 아니라). 옛 저장소는 null(범위로).
  final Set<int>? rows;
  bool holds(int row) => rows != null ? rows!.contains(row) : row >= box.firstRow && row <= box.lastRow;
}

/// 줄 이름을 폭에 맞춘 것(이은 글 · 들 폭이 그대로면 다시 재지 않는다).
class _Fitted {
  String text = '', out = '';
  double room = -1;
  int shape = 0;
}

class GutterLayer extends SceneLayer {
  /// 줄 이름의 자료. 장면이 만들어질 때 자료 처리부에 길을 건다.
  final rowLabels = RowLabels();

  final _hits = <_HitBox>[];
  int _hitN = 0;

  /// 맞히기 자리 하나를 적는다(밭에 둔 칸을 다시 쓴다).
  void _hit(double left, double top, double right, double bottom, GutterHitKind kind, {int track = -1, int row = -1, int group = -1, int lane = -1, String uid = '', String cell = ''}) {
    if (_hitN == _hits.length) _hits.add(_HitBox());
    _hits[_hitN++]
      ..left = left
      ..top = top
      ..right = right
      ..bottom = bottom
      ..kind = kind
      ..track = track
      ..row = row
      ..group = group
      ..lane = lane
      ..uid = uid
      ..cell = cell;
  }

  /// 트랙 세로 이름은 고른 글과 글자마다의 자리를 함께 보관한다 — 칸 높이가 달라질 때만 다시 한다.
  final _trackNames = <int, _Vertical>{};

  /// 줄 이름 · 폴더 이름을 폭에 맞춘 것(줄 번호 · 폴더 uid마다).
  final _rowFits = <int, _Fitted>{}, _folderFits = <String, _Fitted>{};

  /// 민족 머리 줄 이름 · 한 줄짜리 묶음 이름을 폭에 맞춘 것. 열쇠 = '트랙 순번:묶음 순번' · 한 줄짜리는 '줄 번호'.
  final _peopleFits = <String, _Fitted>{}, _inlineFits = <int, _Fitted>{};

  /// 이번 장면에 위에 붙일 머리 줄(긴 묶음을 내려 볼 때 — [_peopleHeads]가 모으고 뒤 걸음이 그린다) · 트랙마다 붙은 줄들의 아래(그 위의 줄 이름은 적지 않는다).
  final _sticky = <({int track, int row, int group, double y})>[];
  final _stickBottom = <int, double>{};

  /// 이번 장면에 그릴 줄 · 폴더 — 장면마다 새 목록을 만들지 않고 비워 다시 쓴다.
  final _rowsBuf = <int>[];
  final _folders = <_Folder>[];
  final _names = <String>[];
  final _spans = <RowLabel>[];

  /// 밝기 상태(총괄이 장면에 넣기 전에는 중립). 왼쪽 칸은 고르기 · 강조에 흐리지 않는다([dims]).
  em.Emphasis? emphasis;
  static final em.Emphasis _neutral = em.Emphasis();
  em.Emphasis get _em => emphasis ?? _neutral;

  /// 손이 올라간 줄 · 트랙(이름이 먹으로 짙어진다).
  int? hotRow, hotTrack;

  /// 제 층의 그림판(동그란 점 — 문화권 머리 단 · 사람 띠의 구멍) — 층의 끝에서 내보낸다.
  final dots = GutterDots.shared;

  /// 이번 장면에 그린 사람 띠(문화권 자리 · 그린 자리 — 줄 · x 범위 · 장면 y · 인물 uid · 왕관). 장면마다 새로 채운다.
  /// 리메이크 4단계 과제 4 걸음 2(실 · 뿔 매듭)가 읽고, 걸음 3이 띠마다 누름 자리([GutterHitKind.person] — 사람 창)를 머리 단 누름 자리 뒤에 적는다
  /// (사람 띠 밖의 상자 자리는 그대로 문화권 접기 · 펴기).
  final personBands = <({int sphere, SpherePersonBand band})>[];

  /// 사람 띠의 실 층(0.1.1 · 조사 결함 38 · 39 — 그리개가 잇는다). 실은 몸통 뒤 판에 긋고 머리 단 상자는 이 층이 몸통 뒤에 칠하므로,
  /// 상자에 덮이는 몫을 [_threadsOver]가 상자 위에 다시 찍는다(스위치 mend — 다른 문화권 실의 굴 문 39만 새 길이라 route 뒤). 없으면 예전 그대로.
  SphereThreadLayer? threads;

  /// 이번 장면에 머리 단 상자 위에 다시 찍은 실 조각(점선 · 점) 수와 굴 문 수 — 검사가 읽는다.
  int threadPieces = 0, threadDoors = 0;

  /// 접힘과 조감은 줄 쌓기(`layout`)가 정한다 — 층은 읽기만 한다.
  bool isTrackFolded(SceneLayout layout, TrackInfo track) => layout.isTrackFolded(track.id);
  bool isGroupFolded(SceneLayout layout, GroupInfo group) => layout.isGroupFolded(group);

  @override
  void attach(TimelineScene scene) => rowLabels.attach(scene);

  @override
  void setScale(double scale) => dots.setScale(scale);

  /// 누른 자리가 무엇인가(배치 px). 없으면 null. 입력을 잇는 일은 총괄의 몫이다.
  GutterHit? hitTest(double x, double y) {
    for (int i = _hitN - 1; i >= 0; i--) {
      if (_hits[i].has(x, y)) return _hits[i].hit;
    }
    return null;
  }

  /// 왼쪽 칸도 흐리게 할 것인가 — 기본은 거짓(지금 연표처럼 고르기 · 강조에 왼쪽 칸을 흐리지 않는다). 참이면 밝기가 몸통과 같은 길로 알파에 곱해진다.
  bool dims = false;

  double _alphaOf(int row) => dims ? _em.bandAlpha(0, row) : 1;

  /// 묶음을 다시 만들어야 하는가를 가리는 번호 — 밝기가 흐르는 중(`active`)이면 장면마다 값이 달라진다.
  int get emphasisVersion => _em.active ? -1 : _em.version;

  static int _ink(double a) => mixSrgb(Look.ink, Look.paper, a);

  @override
  void paint(PaintContext c) {
    _hitN = 0;
    personBands.clear();
    threadPieces = threadDoors = 0;
    final v = c.v, layout = c.layout;
    final left = c.left, head = c.head, w = c.w, h = c.h;

    c.canvas.drawRect(ui.Rect.fromLTWH(0, head, left, h - head), c.fill..color = const ui.Color(Look.paper));
    // 오른쪽 테(목업 — 먹 8)는 문화권 머리 단(왼쪽 칸과 그림판을 가로지르는 가로 꼬리표) 자리에서 끊는다 — 머리 단 밑 줄(리메이크 4단계 과제 3)까지 든 높이로.
    // 머리 단 자리는 그린 자리([SceneLayout.sphereHeadBox] — 붙은 머리 단은 그림판 위)다.
    final edge = _ink(GutLook.edgeInk);
    var lineFrom = head;
    stuckBottom = head;
    for (int k = 0; k < layout.spheres.length; k++) {
      final box = layout.sphereHeadBox(k, v);
      if (box == null) continue;
      final y0 = box.top, boxH = box.height;
      if (y0 + boxH < head || y0 > h) continue;
      if (box.stuck) stuckBottom = math.max(stuckBottom, y0 + boxH - 1);
      if (y0 > lineFrom) c.quads.vLine(left - 1, lineFrom, y0, edge);
      lineFrom = math.max(lineFrom, y0 + boxH - 1);
    }
    if (lineFrom < h) c.quads.vLine(left - 1, lineFrom, h, edge);
    rowLabels.variants = layout.variantKeys;

    _readFolders(c);
    final rows = _rowsBuf..clear();
    _sticky.clear();
    _stickBottom.clear();
    // 머리 줄이 붙는 자리: 붙은 문화권 머리 단의 밑(테 다음 줄) · 없으면 그림판 위.
    final stickTop = stuckBottom > head ? stuckBottom + 1 : head;
    for (int i = 0; i < layout.tracks.length; i++) {
      final top = layout.trackTop(i);
      if (top < 0 || layout.isTrackHidden(i)) continue; // 접힌 문화권의 트랙은 없다(머리 단 하나)
      final track = layout.tracks[i];
      final y0 = v.yOf(top), y1 = y0 + layout.trackHeight(i);
      if (y1 < head || y0 > h) continue;
      if (layout.isTrackFolded(track.id)) {
        _foldedTrack(c, i, track, y0, y1, head, h);
        continue;
      }
      _track(c, i, track, y0, y1, head, h);
      if (PaintPick.people) _peopleHeads(c, i, track, head, h, stickTop);
      for (final row in layout.visibleRowsOfTrack(i)) {
        final geo = layout.geo(row);
        final top = v.yOf(layout.rowTop(row) + geo.bandTop);
        if (top > h || top + (geo.height - geo.bandTop) < head) continue;
        rows.add(row);
      }
    }
    final at = ((v.lo + v.hi) / 2).round();
    rowLabels.want(rows, at: at);
    for (final f in _folders) {
      _folder(c, f, head, h);
    }
    for (final row in rows) {
      _rowLabel(c, row, at, head, h);
    }
    final strips = StripLayer.of(c.scene);
    final yielded = strips == null ? const <ChainMark>{} : yieldedNames(strips.chainMarks.values, strips.officeMarks.values, head, h);
    _chainLabels(c, head, h, yielded);
    _officeLabels(c, head, h, yielded);
    _stuck.clear();
    for (int k = 0; k < layout.spheres.length; k++) {
      if (layout.sphereHeadBox(k, v)?.stuck ?? false) {
        _stuck.add(k);
        continue;
      }
      _sphereHead(c, k, head, h, w);
    }
    c.flushShapes();
    dots.flush(c.canvas);
    ThreadSprites.shared.flush(c.canvas); // 상자 위에 다시 찍은 실 조각(0.1.1 · [_threadsOver]) — 상자 · 사람 띠 · 굴 문 위 · 글자 아래
    c.flushText();
    // 위에 붙은 민족 머리 줄(0.1.1 · 긴 묶음을 내려 볼 때)도 붙은 머리 단처럼 그 밑으로 지나가는 폴더 · 사슬 이름을 종이로 덮도록 한 번 더 내보낸다
    // (그 자리의 줄 이름은 [_rowLabel]이 적지 않는다). 붙는 자리 위로 밀려 나가는 몫은 잘라 낸다 — 붙은 머리 단 · 날짜 칸을 덮지 않게.
    if (_sticky.isNotEmpty) {
      _stickyHeads(c, head, h);
      c.canvas.save();
      c.canvas.clipRect(ui.Rect.fromLTRB(0, stickTop, left, h));
      c.flushShapes();
      c.flushText();
      c.canvas.restore();
    }
    // 붙은 머리 단(리메이크 4단계 과제 3 걸음 4)은 그 밑으로 지나가는 줄 이름 · 폴더 · 트랙 이름(글자는 층 끝에 몰아 그린다)까지 덮도록
    // 한 번 더 내보낸다 — 누름 자리도 맨 뒤에 적혀 가려진 줄 이름보다 먼저 잡힌다. 붙은 머리 단이 없으면 이 걸음이 없다(그림이 4단계 전과 같다).
    if (_stuck.isEmpty) return;
    for (final k in _stuck) {
      _sphereHead(c, k, head, h, w);
    }
    c.flushShapes();
    dots.flush(c.canvas);
    ThreadSprites.shared.flush(c.canvas);
    c.flushText();
  }

  /// 이번 장면에 붙은 머리 단의 문화권(뒤 걸음으로 그림) · 보이는 붙은 머리 단 상자의 아랫변(테 y — 없으면 그림판 위 [SceneView.head]).
  /// 그리개가 연합 흐림(왼쪽 칸 덮개)을 이 밑으로만 칠한다(painter.dart).
  final _stuck = <int>[];
  double stuckBottom = 0;

  // ---- 그릇(폴더) ----

  /// 이번 장면의 폴더(켠 대범위 가운데 펼친 · 접힌 것 — 풀린 그릇 · 조감 · 집합 보기 판 둘레는 빼고).
  void _readFolders(PaintContext c) {
    _folders.clear();
    final layout = c.layout;
    if (layout.bird || c.hide.contains('scopes')) return;
    for (final it in ScopeLayer.readScopes(c).values) {
      if (!it.folderIn(c)) continue;
      final uid = scopeUidOf(c, it);
      final state = uid.isEmpty ? ScopeState.open : layout.scopeStateOf(uid);
      if (state == ScopeState.loose) continue;
      final box = scopeBoxOf(c, it);
      if (box == null) continue;
      // 이름 수는 폴더 탭과 같은 셈(과제 7 걸음 4 · [scopeCountOf] — 선반 변형을 켠 그릇은 남은 수 + 숨은 수). 왼쪽 칸은 접힌 폴더에만 수를 적고
      // 접힘은 선반 변형을 끄므로(접힘이 선반 기억을 이김) 지금 적히는 수는 늘 구역 23의 b 그대로다 — 셈을 탭과 하나로 둘 뿐.
      _folders.add(_Folder(it.name, uid, box, state == ScopeState.closed, scopeCountOf(c, it, uid), layout.scopeOnOf(uid)?.rows));
    }
  }

  /// 그 줄 · 폴더를 감싼 폴더 수(한 단마다 10 들인다).
  int _depthOf(int row, {_Folder? self}) {
    int depth = 0;
    for (final f in _folders) {
      if (identical(f, self) || !f.holds(row)) continue;
      if (self != null && f.box.lastRow - f.box.firstRow < self.box.lastRow - self.box.firstRow) continue;
      depth++;
    }
    return depth;
  }

  void _folder(PaintContext c, _Folder f, double head, double h) {
    final depth = f.rows != null ? f.box.depth : _depthOf(f.box.firstRow, self: f);
    final x = GutLook.boxX + depth * GutLook.step;
    final closedBox = f.closed && depth > 0 && f.uid.isNotEmpty && c.layout.closedBoxRowOf(f.uid) >= 0;
    final cy = (c.v.yOf(f.box.top) + (closedBox ? GutLook.closedBoxMid : GutLook.boxMid)).roundToDouble();
    if (cy - 6 < head || cy + 6 > h) return;
    final ink = _ink(GutLook.iconInk);
    if (depth == 0) {
      _folderIcon(c, x, cy - 6, ink);
    } else {
      _boxIcon(c, x, cy, ink);
    }
    final look = TextLook(GutLook.rowSize, ui.FontWeight.w700, _ink(GutLook.boxInk));
    final nameX = x + GutLook.boxText;
    final room = c.left - GutLook.rightPad - nameX;
    final fit = _fitted(c, _folderFits[f.uid] ??= _Fitted(), f.name, look, room);
    if (fit == null) return;
    c.later.add('gutFolder', fit, look, nameX, _textTop(cy, GutLook.rowSize));
    if (f.closed && f.count > 0 && fit == f.name) {
      final count = TextLook(GutLook.countSize, ui.FontWeight.w700, _ink(GutLook.countInk));
      final nameW = c.text.widthOf(fit, look);
      if (nameW != null && nameX + nameW + GutLook.countGap + 16 <= c.left - GutLook.rightPad) {
        c.later.add('gutFolderCount', '${f.count}', count, nameX + nameW + GutLook.countGap, _textTop(cy, GutLook.countSize));
      }
    }
    // 누르면 펼침 ↔ 접힘(폴더 탭의 라벨과 같다 — 바꿀 상태: 1 펼침 · 2 접힘 · 선반 기억에 든 그릇은 5 가지 접기 뒤집기 — 과제 7 걸음 5).
    // 소속 폴더(늘 펼침)는 화면이 소속 접기로 바꾼다([GutterHitKind.folder]).
    if (f.uid.isNotEmpty) _hit(x - 3, cy - 9, c.left - 1, cy + 9, GutterHitKind.folder, row: ScopeLayer.pressOf(c.layout, f.uid, f.closed ? 1 : 2), uid: f.uid);
  }

  /// 폴더 그림(목업 kit.js의 folder 그림 — 12 · 선 하나): 왼쪽 위 어깨 탭 · 둥근 네 귀는 귀 한 점을 비워서.
  void _folderIcon(PaintContext c, double x, double y, int ink) {
    final q = c.quads;
    q.hLine(x + 2, x + 5, y + 1, ink); // 탭 윗변
    q.add(x + 5, y + 2, x + 6, y + 3, ink); // 어깨
    q.hLine(x + 6, x + 11, y + 3, ink); // 몸 윗변
    q.vLine(x + 1, y + 2, y + 10, ink);
    q.vLine(x + 11, y + 4, y + 10, ink);
    q.hLine(x + 2, x + 11, y + 10, ink);
    c.stats.shapes++;
  }

  /// 상자 그림(목업 — 안쪽 그릇): 뚜껑(13 × 3 칠) 아래 모따기 2의 몸(12 × 8 · 선).
  void _boxIcon(PaintContext c, double x, double cy, int ink) {
    final q = c.quads, y = cy - 4;
    q.add(x - 1, y - 2, x + 12, y + 1, ink);
    q.vLine(x, y + 1, y + 7, ink);
    q.vLine(x + 11, y + 1, y + 7, ink);
    q.add(x + 1, y + 7, x + 2, y + 8, ink);
    q.add(x + 10, y + 7, x + 11, y + 8, ink);
    q.hLine(x + 2, x + 10, y + 8, ink);
    c.stats.shapes++;
  }

  // ---- 트랙 ----

  /// 트랙: 가는 세로 선 + 세로 이름(문화권과 같은 이름이면 적지 않는다 — 목업 `Tr.n !== C.n`). 이름을 누르면 트랙 접기.
  void _track(PaintContext c, int index, TrackInfo track, double y0, double y1, double head, double h) {
    final layout = c.layout;
    _hit(GutLook.trackHitLeft, math.max(y0, head), GutLook.trackHitRight, math.min(y1, h), GutterHitKind.trackName, track: index);
    final sphere = layout.sphereIndexOfTrack(index);
    if (sphere >= 0 && sphere < layout.spheres.length && layout.spheres[sphere].name == track.name) return;
    final hot = hotTrack == index;
    final lineTop = math.max(y0 + GutLook.lineInset, head), lineBottom = math.min(y1 - GutLook.lineInset, h);
    if (lineBottom > lineTop) {
      c.quads.vLine(GutLook.lineX, lineTop, lineBottom, _ink(hot ? GutLook.trackInk : GutLook.lineInk));
      c.stats.shapes++;
    }
    final height = y1 - y0;
    final slot = _trackNames[index] ??= _Vertical();
    final tick = (height * 10).round();
    if (slot.tick != tick || !identical(slot.source, track.name)) {
      slot.tick = tick;
      slot.source = track.name;
      slot.text = shortName(track.name, (t) => t.runes.length * GutLook.trackPitch + 4 <= height);
      slot.upright = null;
    }
    final text = slot.text ?? '';
    if (text.isEmpty) return;
    final look = TextLook(GutLook.trackSize, ui.FontWeight.w700, _ink(hot ? 1 : GutLook.trackInk));
    _vertical(c, 'track', slot, text, look, GutLook.trackX, (y0 + y1) / 2 - text.runes.length * GutLook.trackPitch / 2, GutLook.trackPitch, head, h);
  }

  // ---- 민족 머리 줄(0.1.1 감독 "민족이 안보여" → 감독 고름 '나' — PaintPick.people) ----

  /// 민족 머리 줄: 쌓기가 묶음 첫 줄 위에 비워 둔 자리([SceneLayout.peopleHeadOf])에 묶음마다 한 줄 — ▾ + 이름 9 + 가는 선(단마다 10 들임).
  /// 누르면 그 묶음 접기(접히면 머리 줄 대신 접힌 줄 '이름 ▸' — 그것을 누르면 편다).
  /// 머리 줄이 붙는 자리([stickTop]) 위로 지나간 긴 묶음은 그 머리 줄을 붙는 자리에 붙인다(얕은 단부터 아래로 쌓음 · 묶음 끝이 다가오면 밀려 올라감 —
  /// 문화권 머리 단처럼). 붙일 것은 [_sticky]에 모으고 뒤 걸음([_stickyHeads])이 그린다.
  /// 붙은 줄들 밑(쌓인 자리)으로 올라온 다음 묶음의 머리 줄도 그 자리에 붙는다(0.1.1 1배 '새로 생긴 것' 2 — 감독 자료 내려 봄 500에서 붙은 '한민족 · 예맥'
  /// 밑에 '옥저인' 머리 줄이 가려졌다). 붙은 줄들이 차지한 자리 안의 제자리 머리 줄은 그리지 않는다(종이 밑에 글이 겹쳐 남지 않게 — 붙었으면 붙은 자리에 한 번).
  void _peopleHeads(PaintContext c, int index, TrackInfo track, double head, double h, double stickTop) {
    final layout = c.layout, v = c.v;
    final mark = _ink(PeopleLook.markInk);
    final above = <({int row, int group, double top, double bottom, GroupInfo info})>[];
    final natural = <({int row, int group, double top, GroupInfo info})>[];
    for (final row in layout.visibleRowsOfTrack(index)) {
      final heads = layout.peopleHeadOf(row);
      if (heads == null) continue;
      var y = v.yOf(layout.rowTop(row) + heads.top);
      for (final group in heads.groups) {
        final top = y;
        y += G.peopleHead;
        final gi = track.groups.indexOf(group);
        natural.add((row: row, group: gi, top: top, info: group));
        if (top >= h) continue;
        // 붙을 수 있는 머리 줄 — 묶음의 보이는 끝(마지막 보이는 줄의 끝)을 잰다. 붙는 자리 밑이어도 쌓인 줄들 밑으로 올라오면 붙으므로 함께 모은다.
        double bottom = double.negativeInfinity;
        for (int r = group.firstRow; r < group.firstRow + group.rowCount; r++) {
          if (layout.isVisible(r)) bottom = math.max(bottom, v.yOf(layout.rowTop(r) + layout.geo(r).height));
        }
        if (bottom > stickTop) above.add((row: row, group: gi, top: top, bottom: bottom, info: group));
      }
    }
    // 붙는 자리를 품은 묶음을 얕은 단부터 — 단마다 하나(형제는 겹치지 않는다). 둘째 단부터는 밀려 올라가 윗단과 겹치게 되면 붙이지 않고 다음 것을 본다
    // (끝나 가는 묶음 뒤의 형제 머리 줄이 그 단에 붙는다).
    above.sort((a, b) => a.info.depth != b.info.depth ? a.info.depth.compareTo(b.info.depth) : a.top.compareTo(b.top));
    var slot = stickTop;
    final stuck = <(int, int)>{};
    for (final e in above) {
      if (e.top >= slot || e.bottom <= slot) continue;
      final y = math.min(slot, e.bottom - G.peopleHead);
      if (y < slot && slot > stickTop) continue;
      if (y <= e.top) continue; // 제자리가 더 아래 — 붙일 것이 없다
      _sticky.add((track: index, row: e.row, group: e.group, y: y));
      stuck.add((e.row, e.group));
      slot = y + G.peopleHead;
    }
    for (final e in natural) {
      if (stuck.contains((e.row, e.group))) continue;
      if (slot > stickTop && e.top + G.peopleHead > stickTop && e.top < slot) continue; // 붙은 줄들 밑 — 종이가 덮는 자리
      final cy = (e.top + G.peopleHead / 2).roundToDouble();
      if (cy - 6 < head || cy + 6 > h) continue;
      _head(c, index, e.row, e.group, e.info, e.top, mark, head, h);
    }
    if (slot > stickTop) _stickBottom[index] = slot + 1;
  }

  /// 머리 줄 하나(제자리 · 붙은 자리 같은 꼴): ▾ + 이름 9(들지 않으면 줄인 이름) + 이름 뒤 가는 선 · 누르면 그 묶음 접기.
  void _head(PaintContext c, int index, int row, int gi, GroupInfo group, double top, int mark, double head, double h) {
    final right = c.left - GutLook.rightPad;
    final cy = (top + G.peopleHead / 2).roundToDouble();
    final argb = 0xff000000 | group.color;
    final x = GutLook.boxX + group.depth * GutLook.step;
    _sphereMark(c, x, cy, false, mark);
    final look = TextLook(PeopleLook.nameSize, ui.FontWeight.w700, mixOklab(argb, Look.ink, PeopleLook.nameInk));
    final nameX = x + PeopleLook.nameX;
    final fit = _fitted(c, _peopleFits['$index:$gi'] ??= _Fitted(), group.name, look, right - nameX);
    if (fit != null && fit.isNotEmpty) {
      c.later.add('peopleHead', fit, look, nameX, _textTop(cy, PeopleLook.nameSize));
      final w = c.text.widthOf(fit, look);
      if (w != null && nameX + w + PeopleLook.lineGap < right) {
        c.quads.hLine(nameX + w + PeopleLook.lineGap, right, cy, mixSrgb(mixOklab(argb, Look.ink, PeopleLook.lineInk), Look.paper, PeopleLook.headLine));
      }
    }
    c.stats.shapes++;
    _hit(x - 3, math.max(top, head), c.left - 1, math.min(top + G.peopleHead, h), GutterHitKind.people, track: index, row: row, group: gi);
  }

  /// 뒤 걸음: 위에 붙은 머리 줄 — 종이 바탕(트랙 칸 밖 [PeopleLook.stickLeft]부터 오른쪽 테 앞까지)으로 밑에 지나는 것을 덮고, 트랙마다 붙은 줄들 밑에 1px 테.
  void _stickyHeads(PaintContext c, double head, double h) {
    final layout = c.layout, mark = _ink(PeopleLook.markInk), edge = _ink(GutLook.edgeInk);
    final right = c.left - 1;
    for (final s in _sticky) {
      c.under.add(PeopleLook.stickLeft, s.y, right, s.y + G.peopleHead + 1, Look.paper);
      final track = layout.tracks[s.track];
      _head(c, s.track, s.row, s.group, track.groups[s.group], s.y, mark, head, h);
    }
    for (final e in _stickBottom.entries) {
      c.quads.hLine(PeopleLook.stickLeft, right, e.value - 1, edge);
    }
  }

  /// 접힌 트랙: 세로 선 대신 가로 이름(11 굵게 · 먹 60)과 ▸ — 왼쪽 칸 전체가 펴는 단추다.
  void _foldedTrack(PaintContext c, int index, TrackInfo track, double y0, double y1, double head, double h) {
    final top = math.max(y0, head), bottom = math.min(y1, h);
    if (bottom <= top) return;
    _hit(0, top, c.left - 1, bottom, GutterHitKind.trackName, track: index);
    final mid = (y0 + y1) / 2;
    if (mid - 6 < head || mid + 6 > h) return;
    final look = TextLook(GutLook.rowSize, ui.FontWeight.w700, _ink(hotTrack == index ? 1 : GutLook.trackInk));
    c.later.add('foldName', '${track.name} ▸', look, GutLook.boxX, _textTop(mid, GutLook.rowSize));
  }

  // ---- 줄 이름 ----

  /// 이 줄이 접힌 민족 줄이면 그 묶음의 단계, 아니면 −1(접힌 것 가운데 가장 얕은 것).
  int _foldedDepthOf(SceneLayout layout, int row) {
    if (!layout.isFoldedGroupRow(row)) return -1;
    final track = layout.trackOf(row);
    int best = -1;
    for (final group in track.groups) {
      if (group.firstRow != row || !layout.isGroupFolded(group)) continue;
      if (best < 0 || group.depth < best) best = group.depth;
    }
    return best < 0 ? 0 : best;
  }

  /// 줄 하나: 작은 꼬리표 그림 + 이름(목업 — 보는 범위에 든 그 줄의 띠 이름을 ' · '로). 접힌 폴더 안의 줄은 폴더 줄 하나로 갈음해 적지 않는다.
  void _rowLabel(PaintContext c, int row, int at, double head, double h) {
    final v = c.v, layout = c.layout;
    int depth = 0;
    for (final f in _folders) {
      if (!f.holds(row)) continue;
      if (f.closed) return;
      depth++;
    }
    final geo = layout.geo(row);
    final top = v.yOf(layout.rowTop(row) + geo.bandTop);
    final height = geo.height - geo.bandTop;
    final cy = top + math.min(height, G.head) / 2 - .5;
    // 줄이 접히며 흐르는 동안 보이는 높이가 글줄보다 낮으면 적지 않는다(트랙 사이에 글이 겹치지 않게).
    if (layout.rowClip(row) != null && height < GutLook.rowSize * Gut.lineRatio) return;
    if (cy - 6 < head || cy + 6 > h) return;
    // 위에 붙은 민족 머리 줄 밑으로 지나는 줄은 이름을 적지 않는다(붙은 줄이 종이로 덮는다 — 글자가 반쯤 비치지 않게).
    final stuck = _stickBottom[layout.trackIndexOf(row)];
    if (stuck != null && cy - 6 < stuck) return;
    final foldedDepth = _foldedDepthOf(layout, row), foldedVariant = layout.foldedVariantOf(row);
    final picked = rowLabels.pick(row, at: at, xOf: v.xOf, left: c.left, right: c.w, foldedDepth: foldedDepth, foldedVariant: foldedVariant);
    if (picked == null) return; // 답이 아직 오지 않았다(오면 다음 장면에 그린다)
    var color = picked.color;
    String text;
    if (picked.kind == RowLabel.band) {
      // 보는 범위에 든 띠를 시작 차례로 — 이름이 같은 띠(한 나라의 여러 토막)는 한 번만.
      _spans.clear();
      for (final l in rowLabels.of(row)) {
        if (l.kind != RowLabel.band || v.xOf(l.end) <= c.left || v.xOf(l.start) >= c.w) continue;
        _spans.add(l);
      }
      _spans.sort((a, b) => a.start.compareTo(b.start));
      _names.clear();
      for (final l in _spans) {
        if (!_names.contains(l.name)) _names.add(l.name);
      }
      if (_spans.isNotEmpty) color = _spans.first.color;
      text = _names.isEmpty ? picked.name : _names.join(GutLook.joiner);
    } else {
      text = picked.kind == RowLabel.foldedGroup ? '${picked.name} ▸' : picked.name;
    }
    final x = GutLook.rowX + depth * GutLook.step;
    final alpha = _alphaOf(row);
    final argb = 0xff000000 | color;
    _tagIcon(c, x, (cy - 4).roundToDouble(), withAlpha(mixSrgb(argb, Look.paper, GutLook.tagFill), alpha), withAlpha(mixOklab(argb, Look.ink, GutLook.tagEdge), alpha));
    final look = TextLook(GutLook.rowSize, ui.FontWeight.w700, _ink(hotRow == row ? 1 : GutLook.rowInk));
    var textX = x + GutLook.rowText;
    // 민족 딱지(그 줄의 정권 민족이 덮은 민족과 다를 때): 줄 이름 앞 작은 점 · 이름은 그만큼 뒤로.
    final chip = PaintPick.people ? rowLabels.chipOf(row) : null;
    final chipX = textX;
    if (chip != null) {
      dots.add(PeopleLook.chipDot, chipX, (cy - PeopleLook.chipDot / 2).roundToDouble(), withAlpha(mixOklab(0xff000000 | chip.color, Look.ink, PeopleLook.lineInk), alpha));
      textX += PeopleLook.chipDot + PeopleLook.chipGap;
    }
    // 조감 모양 c(띠 8px — 11px 글이 들지 않는다)는 이름 없이 작은 꼬리표 그림만(옛 왼쪽 칸 · 웹 css 1812 · 설계 4-1 좁은 꼬리표 '구멍만').
    final named = !(layout.bird && layout.birdShape == BirdShape.c);
    final fit = named ? _fitted(c, _rowFits[row] ??= _Fitted(), text, look, c.left - GutLook.rightPad - textX) : null;
    if (fit != null && fit.isNotEmpty) c.later.add('rowName', fit, look, textX, _textTop(cy, GutLook.rowSize), alpha);
    final hitTop = math.max(top, head), hitBottom = math.min(top + height, h);
    if (picked.kind == RowLabel.foldedGroup) {
      _foldedHit(c, row, foldedVariant, x - 3, hitTop, hitBottom);
    } else {
      _hit(x - 3, hitTop, c.left - 1, hitBottom, GutterHitKind.row, row: row, uid: picked.period);
    }
    if (chip != null) _hit(chipX - 2, cy - 5, chipX + PeopleLook.chipDot + 2, cy + 5, GutterHitKind.chip, row: row, uid: 'people:${chip.id}');
    // 한 줄짜리 민족 묶음(머리 줄 없이 — [SceneLayout.peopleHeadOf]의 inline): 줄 이름 뒤 6에 이름 9(민족 색 + 먹 55). 줄 이름이 먼저 들고, 남은 폭에 들지 않으면
    // 줄인 이름 · 그도 안 들면 적지 않는다(겹치지 않게). 누르면 그 묶음 접기(머리 줄과 같다).
    final inline = PaintPick.people && fit != null && fit.isNotEmpty ? layout.peopleHeadOf(row)?.inline : null;
    if (inline == null || inline.isEmpty) return;
    final nameW = c.text.widthOf(fit!, look);
    if (nameW == null) return;
    final first = inline.first;
    final peopleLook = TextLook(PeopleLook.nameSize, ui.FontWeight.w700, mixOklab(0xff000000 | first.color, Look.ink, PeopleLook.nameInk));
    final px = textX + nameW + PeopleLook.inlineGap;
    final names = inline.length == 1 ? first.name : [for (final g in inline) g.name].join(GutLook.joiner);
    if (text.contains(names)) return; // 줄 이름에 이미 든 민족 이름(유연 · 유연 / 흑요 화로 문화 · 문화)은 되풀이하지 않는다
    final pfit = _fitted(c, _inlineFits[row] ??= _Fitted(), names, peopleLook, c.left - GutLook.rightPad - px);
    if (pfit == null || pfit.isEmpty) return;
    c.later.add('peopleInline', pfit, peopleLook, px, _textTop(cy, PeopleLook.nameSize), alpha);
    final pw = c.text.widthOf(pfit, peopleLook) ?? 0;
    final track = layout.trackIndexOf(row);
    _hit(px - 2, cy - 6, px + pw + 2, cy + 6, GutterHitKind.people, track: track, row: row, group: layout.tracks[track].groups.indexOf(first));
  }

  // ---- 꼬리표 밑 흰 사슬의 이름(감독 고름 G5 #9 나 · 차례 걸음 15) ----

  /// 사슬 이름의 글꼴 — 10 · 보통 굵기 · 틀 먹 50(목업 subLabels `k(.5)` — 왼쪽 칸은 틀 먹 그대로).
  static final _chainLabelLook = TextLook(ChainLook.labelSize, ui.FontWeight.w400, _ink(ChainLook.labelInk));

  /// 사슬마다(칸 층이 이 장면에 그린 사슬 — 줄 · 사슬 차례마다 화면 왼쪽에 가장 가까운 것, [StripLayer.chainMarks]) 칸 오른쪽 끝 − 12에 '왕조' · '지위'를
  /// 오른쪽 맞춤 · 사슬 가운데 높이로, 그 뒤 칸 오른쪽 끝 − 8 ~ − 2에 6px 금(틀 먹 20). 누름은 그 줄 이름의 자리 그대로(줄의 몫 전체).
  /// 칸 층은 몸통에서 이 층보다 먼저 그린다(painter.dart) — 같은 장면의 자리다. 사슬이 없거나 스위치 `chain`을 끄면(쌓기가 예전 칸 층) 없다.
  /// 직위 줄 더 이름([_officeLabels])과 맞닿으면 화면 왼쪽에 가까운 띠의 이름 하나만([yieldedNames] — 비키는 이름이 [yielded]).
  void _chainLabels(PaintContext c, double head, double h, Set<ChainMark> yielded) {
    final strips = StripLayer.of(c.scene), marks = strips?.chainMarks;
    if (marks == null || marks.isEmpty) return;
    final right = c.left;
    for (final m in marks.values) {
      final y = m.y;
      if (y - 6 < head || y + 6 > h) continue;
      if (yielded.contains(m)) {
        c.debug?.note('왼쪽칸이름비킴', '사슬 ${m.row}:${m.slot} ${m.label}');
        continue;
      }
      final w = c.text.widthOf(m.label, _chainLabelLook);
      if (w == null) continue; // 글자 폭이 아직 — 다음 장면에(글줄 준비가 모자라면 그리개가 다시 청한다)
      c.later.add('chainLabel', m.label, _chainLabelLook, right - ChainLook.labelRight - w, _textTop(y, ChainLook.labelSize));
      c.quads.hLine(right - ChainLook.lineFrom, right - ChainLook.lineTo, y, _ink(ChainLook.lineInk));
      c.stats.shapes++;
      c.debug?.note('사슬이름', '${m.row}:${m.slot} ${m.label} ${(y * 10).round()}');
    }
  }

  // ---- 직위 줄 더 층의 줄 이름(G7 가 · 칸 그림 갈래 걸음 4 — 구역 55) ----

  /// 직위 줄 더 층마다(칸 층이 이 장면에 그린 층 — 줄 · 직위 줄 더의 줄마다 화면 왼쪽에 가장 가까운 띠의 것, [StripLayer.officeMarks]) 그 띠 구역 55의
  /// 줄 이름(예: '재상')을 사슬 이름([_chainLabels])과 같은 꼴로 — 칸 오른쪽 끝 − 12에 오른쪽 맞춤 · 층 가운데 높이 · 10 · 틀 먹 50, 그 뒤 칸 오른쪽 끝
  /// − 8 ~ − 2에 6px 금(틀 먹 20). 고르기 판 G7 가(`stage4-choose/themes/g-g7.js` gutName — 8.5 · 먹 55 · 끝 − 10 · 금 − 7 ~ − 2 먹 25)가 아니라
  /// 사슬 이름 꼴로 맞춘 까닭: 같은 왼쪽 칸에서 띠 아래 단(왕조 · 지위 사슬 — 감독 고름 G5 #9 나)과 이 층의 이름이 같은 일(줄 안 단의 이름표)을 하고
  /// 높이도 같은 14라 한 칸에 한 꼴이 읽기 쉽다(G7 판은 사슬 이름이 정해지기 전의 그림). 누름은 그 줄 이름의 자리 그대로(줄의 몫 전체).
  /// 층이 없거나(직위 줄 더 띠가 없음 · 표시 '지도자' 끔) 스위치 `office`를 끄면(쌓기에 층이 없음) 없다.
  /// 사슬 이름과 맞닿으면 화면 왼쪽에 가까운 띠의 이름 하나만 — 같은 자리면 이 이름이 비킴([yieldedNames]).
  void _officeLabels(PaintContext c, double head, double h, Set<ChainMark> yielded) {
    final strips = StripLayer.of(c.scene), marks = strips?.officeMarks;
    if (marks == null || marks.isEmpty) return;
    final right = c.left;
    for (final m in marks.values) {
      final y = m.y;
      if (y - 6 < head || y + 6 > h) continue;
      if (yielded.contains(m)) {
        c.debug?.note('왼쪽칸이름비킴', '직위 ${m.row}:${m.slot} ${m.label}');
        continue;
      }
      final w = c.text.widthOf(m.label, _chainLabelLook);
      if (w == null) continue; // 글자 폭이 아직 — 다음 장면에(글줄 준비가 모자라면 그리개가 다시 청한다)
      c.later.add('officeLabel', m.label, _chainLabelLook, right - ChainLook.labelRight - w, _textTop(y, ChainLook.labelSize));
      c.quads.hLine(right - ChainLook.lineFrom, right - ChainLook.lineTo, y, _ink(ChainLook.lineInk));
      c.stats.shapes++;
      c.debug?.note('직위줄이름', '${m.row}:${m.slot} ${m.label} ${(y * 10).round()}');
    }
  }

  /// 사슬 이름([chains])과 직위 줄 더 이름([offices]) 가운데 왼쪽 칸에서 비키는 것. 둘 다 칸 오른쪽 끝 − 12에 오른쪽 맞춤 · 10이라, 가운데 높이 차가
  /// 글 크기 + 2 안이면 글이 겹친다(한 띠 안 이웃 단은 14 떨어져 겹치지 않음). 겹치는 것은 한 줄의 서로 다른 띠가 제 몸통으로 맞붙어(TagLook.compactOf —
  /// 직위 줄 더 층이 없는 띠의 사슬은 그 층만큼 올라섬) 이름 둘이 몇 px 차로 설 때다(f4-legit 몸통 줄 20: 솔 왕국 '지위' 사슬 ↔ 솔 후왕국 '재상' 층 — 7px).
  /// 그때는 사슬 · 직위 이름을 고르는 같은 규칙('화면 왼쪽에 가장 가까운 띠')대로 화면 왼쪽에 가까운 이름부터 차례로 받고, 이미 받은(그릴) 다른 갈래 이름과
  /// 맞닿으면 비킨다 — 같은 자리면 사슬 이름이 먼저(직위 줄 더 이름이 비켜 4단계 전부터 있던 사슬 이름이 남음). 비킨 이름은 상대가 되지 않는다
  /// (칸 그림 갈래 검토 고침: 사슬 A · 직위 B · 사슬 C가 12px 안에 엇갈려 서면 B가 A에게 비키고, C는 그리지 않는 B에게 비키지 않는다).
  /// 그리지 않는 이름(왼쪽 칸 위 · 아래 밖)은 빠진다. 직위 줄 더 층이 없거나 스위치 `office`를 끄면 [offices]가 비어 사슬 이름은 예전 그대로다.
  static Set<ChainMark> yieldedNames(Iterable<ChainMark> chains, Iterable<ChainMark> offices, double head, double h) {
    if (chains.isEmpty || offices.isEmpty) return const <ChainMark>{};
    bool shown(ChainMark m) => m.y - 6 >= head && m.y + 6 <= h;
    final all = [
      for (final m in chains) if (shown(m)) (m, false),
      for (final m in offices) if (shown(m)) (m, true),
    ]..sort((a, b) {
        final d = a.$1.x.compareTo(b.$1.x);
        return d != 0 ? d : (a.$2 == b.$2 ? 0 : (a.$2 ? 1 : -1));
      });
    final kept = <(ChainMark, bool)>[];
    final out = Set<ChainMark>.identity();
    for (final (m, office) in all) {
      if (kept.any((k) => k.$2 != office && (k.$1.y - m.y).abs() < ChainLook.labelSize + 2)) {
        out.add(m);
      } else {
        kept.add((m, office));
      }
    }
    return out;
  }

  /// 접힌 묶음 줄을 누르면 그 묶음을 편다 — 민족 묶음은 그 번호로, 대범위 가지는 그 열쇠로(GutterHitKind.people).
  void _foldedHit(PaintContext c, int row, String variant, double x, double top, double bottom) {
    final layout = c.layout, index = layout.trackIndexOf(row), track = layout.tracks[index];
    if (variant.isNotEmpty) {
      for (final vg in layout.variantGroups(index)) {
        if (!vg.rows.contains(row) || !layout.isVariantGroupFolded(index, vg)) continue;
        _hit(x, top, c.left - 1, bottom, GutterHitKind.people, track: index, row: row, uid: vg.key);
        return;
      }
    }
    int best = -1;
    for (int g = 0; g < track.groups.length; g++) {
      final group = track.groups[g];
      if (group.firstRow != row || !layout.isGroupFolded(group)) continue;
      if (best < 0 || group.depth < track.groups[best].depth) best = g;
    }
    if (best >= 0) _hit(x, top, c.left - 1, bottom, GutterHitKind.people, track: index, row: row, group: best);
  }

  /// 작은 꼬리표 그림(12 × 8 · 왼쪽 두 귀 모따기 2 — 1px 계단): 칠 · 테.
  void _tagIcon(PaintContext c, double x, double y0, int fill, int edge) {
    const w = GutLook.tagW, h = GutLook.tagH, k = GutLook.tagCham;
    final q = c.quads, y1 = y0 + h;
    for (int i = 0; i < k; i++) {
      q.add(x + k - i, y0 + i, x + w, y0 + i + 1, fill);
      q.add(x + k - i, y1 - i - 1, x + w, y1 - i, fill);
      q.add(x + k - i - 1, y0 + i, x + k - i, y0 + i + 1, edge);
      q.add(x + k - i - 1, y1 - i - 1, x + k - i, y1 - i, edge);
    }
    q.add(x, y0 + k, x + w, y1 - k, fill);
    q.hLine(x + k, x + w, y0, edge);
    q.hLine(x + k, x + w, y1 - 1, edge);
    q.vLine(x, y0 + k, y1 - k, edge);
    q.vLine(x + w - 1, y0, y1, edge);
    c.stats.shapes++;
  }

  // ---- 셈하기 ----

  /// 세로 가운데 [mid]에 놓을 글(크기 [size])의 글자 상자 위.
  static double _textTop(double mid, double size) => Gut.textTopAt(mid - size * Gut.lineRatio / 2, size * Gut.lineRatio, size);

  /// [text]를 [room]에 맞춘다 — 넘치면 끝을 '…'로(목업: 들 때까지 한 자씩 덜고 '…'). 글자 폭이 아직 준비되지 않았으면 null(다음 장면에).
  /// 같은 글 · 같은 폭이면 지난 결과를 쓴다(옆으로 끌기만 할 때 다시 재지 않는다).
  String? _fitted(PaintContext c, _Fitted slot, String text, TextLook look, double room) {
    if (slot.text == text && slot.room == room && slot.shape == look.shapeKey) return slot.out;
    final full = c.text.widthOf(text, look);
    if (full == null) {
      c.scene.requestFrame();
      return null;
    }
    var out = text;
    if (full > room) {
      // 들어가는 가장 긴 앞부분(+ '…')을 반으로 갈라 찾는다.
      final chars = text.runes.toList();
      int lo = 0, hi = chars.length - 1;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        final width = c.text.widthOf('${String.fromCharCodes(chars.take(mid)).trimRight()}${GutLook.more}', look);
        if (width == null) {
          c.scene.requestFrame();
          return null;
        }
        if (width <= room) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      out = lo <= 0 ? '' : '${String.fromCharCodes(chars.take(lo)).trimRight()}${GutLook.more}';
    }
    slot
      ..text = text
      ..room = room
      ..shape = look.shapeKey
      ..out = out;
    return out;
  }

  // ---- 문화권 머리 단(리메이크 조각 ② · 설계 4-6 #5 B) ----

  /// 문화권 하나의 머리 단 — 왼쪽 칸과 그림판을 가로지르는 옅은 가로 꼬리표. 누르면 그 문화권을 접고 편다(누름 자리는 상자 전체 — 밑 줄까지 ·
  /// 사람 띠 자리만은 그 사람의 창 — 리메이크 4단계 과제 4 걸음 3).
  /// 접혔으면 그 문화권 객체들의 작은 꼬리표가 단 안(그림판 몫)에 들어앉는다(paint/minibars.dart의 `paintSphereTags`).
  /// 펼친 문화권에 시대 · 주기 줄 · 사람 띠가 있으면(리메이크 4단계 과제 3 · 4) 상자가 그만큼 아래로 늘고(칠 · 테 · 아래 모따기), 이름 · 띠 수 · ▾는 위 20 안 그대로다 —
  /// 줄은 [SphereLinesPaint]가 상자 안 위 20 밑에 그린다(메이커 서고 미리보기 `_drawSphereRows`).
  void _sphereHead(PaintContext c, int sphere, double head, double h, double w) {
    final layout = c.layout, v = c.v;
    // 그린 자리(머리 단 고정 — 리메이크 4단계 과제 3 걸음 4): 줄 있는 펼친 문화권을 내려 보는 동안은 그림판 위에 붙고 문화권 끝에 밀려 올라간다.
    final box = layout.sphereHeadBox(sphere, v);
    if (box == null) return;
    final y0 = box.top, y1 = y0 + box.height - 1;
    if (y1 < head || y0 > h) return;
    final info = layout.spheres[sphere];
    final folded = layout.isSphereFolded(info.id);
    // 머리 단의 먹은 그림판 먹 단계([CanvasInk] — 칠 3 → 4 · 테 25 · 구멍 테 40 → 45 · 이름 85 · 수 45 · 접기 표 60). 머리 단 밖(줄 이름 · 트랙 · 폴더 그림)은 틀 먹 그대로.
    final fill = CanvasInk.gray(Gut.sphereFill), edge = CanvasInk.gray(Gut.sphereEdge);
    final x0 = Gut.sphereLeft, x1 = w;
    const k = Gut.sphereCham;
    // 칠: 모따기 귀는 1px 계단(45° — 1배에서 빗금 그대로), 몸통은 네모 하나.
    for (int i = 0; i < k; i++) {
      final inset = k - i;
      c.quads.add(x0 + inset, y0 + i, x1, y0 + i + 1, fill);
      c.quads.add(x0 + inset, y1 - i - 1, x1, y1 - i, fill);
    }
    c.quads.add(x0, y0 + k, x1, y1 - k, fill);
    // 테: 윗변 · 아랫변 · 왼쪽 세로 변 + 귀의 빗변(1px 점 계단). 오른쪽은 그림판 끝이라 열림.
    c.quads.hLine(x0 + k, x1, y0, edge);
    c.quads.hLine(x0 + k, x1, y1 - 1, edge);
    c.quads.vLine(x0, y0 + k, y1 - k, edge);
    for (int i = 0; i < k; i++) {
      c.quads.add(x0 + k - i - 1, y0 + i, x0 + k - i, y0 + i + 1, edge);
      c.quads.add(x0 + k - i - 1, y1 - i - 1, x0 + k - i, y1 - i, edge);
    }
    c.stats.shapes += 2;
    // 이름 · 구멍 · 접기 표의 세로 가운데는 위 20 안(밑 줄이 없을 때의 (y0 + y1) / 2와 같은 값).
    final mid = y0 + (G.sphereHead - 1) / 2;
    // 구멍(서고의 꼬리표 말 — 왼쪽 7): 테 먹 40 · 속 종이.
    dots.add(6, x0 + Gut.sphereHoleX - 3, mid - 3, CanvasInk.gray(.4));
    dots.add(4, x0 + Gut.sphereHoleX - 2, mid - 2, Look.paper);
    final name = _sphereNameLook, count = _sphereCountLook, mark = _sphereMarkLook; // mark는 색만 씀
    c.later.add('sphereName', info.name, name, Gut.sphereNameX, Gut.textTopAt(mid - Gut.sphereName * Gut.lineRatio / 2, Gut.sphereName * Gut.lineRatio, Gut.sphereName));
    final nameW = c.text.widthOf(info.name, name);
    if (nameW == null) {
      c.scene.requestFrame();
    } else if (info.count > 0) {
      c.later.add('sphereCount', '${info.count}', count, Gut.sphereNameX + nameW + 5, Gut.textTopAt(mid - Gut.sphereCount * Gut.lineRatio / 2, Gut.sphereCount * Gut.lineRatio, Gut.sphereCount));
    }
    _sphereMark(c, x1 - Gut.sphereMarkRight, mid, folded, mark.color);
    _hit(x0, y0, x1, y1, GutterHitKind.sphere, uid: info.id);
    var persons = const <SpherePersonBand>[];
    if (folded) {
      _sphereTags(c, sphere, mid, c.left + 4, x1 - Gut.sphereMarkRight - 16);
    } else {
      final plan = SphereLinesPaint.paint(c, layout.sphereRowsOf(sphere), y0 + G.sphereHead, y1 - 1, dot: dots.add);
      if (plan != null) {
        persons = plan.persons;
        for (final band in plan.persons) {
          personBands.add((sphere: sphere, band: band));
          // 사람 띠를 누르면 그 사람의 창(과제 4 걸음 3) — 머리 단 누름 자리 뒤에 적어 먼저 잡힌다(붙은 머리 단이면 그 걸음째 맨 뒤).
          final open = band.opens;
          _hit(band.x0, band.top, band.x1, band.bottom, GutterHitKind.person, uid: open.uid, cell: open.cell);
        }
      }
    }
    if (PaintPick.mend) _threadsOver(c, sphere, y0, y1, persons);
  }

  /// 머리 단 상자에 덮이는 실(0.1.1 · 스위치 mend — 실은 몸통 뒤 판, 상자는 이 층이 몸통 뒤에 칠한다):
  ///  · 제 문화권의 실(조사 결함 38): 사람 띠 아랫변의 점과 점선을 상자 아랫변까지 상자 위에 다시 찍는다 — 다른 사람 띠(둘째 단부터)를 지나는 몫은 빼고.
  ///    예전에는 첫 단 사람 띠의 실 첫머리 · 점이 상자에 덮여 실이 상자 아랫변에서 갑자기 시작했다.
  ///  · 다른 문화권의 실(조사 결함 39 · 굴 문이라 새 길 — 스위치 route일 때만): 상자를 가로지르면 위 · 아래 테에 굴 문(관계선의 굴 문과 같은 꼴 — 테 1px과 안팎 1px씩을 상자 밖 바탕색으로 ·
  ///    문에서 상자 안쪽 2px까지 실 조각) — 끊긴 것이 아니라 상자 밑을 지나는 것으로 읽히게. 테가 화면 밖인 쪽은 두지 않는다.
  void _threadsOver(PaintContext c, int sphere, double y0, double y1, List<SpherePersonBand> persons) {
    final list = threads?.threads;
    if (list == null || list.isEmpty) return;
    final top = math.max(y0, c.head), bottom = math.min(y1, c.h);
    if (bottom <= top) return;
    final sprites = ThreadSprites.shared, ink = CanvasInk.gray(SphereThreadLook.ink);
    const cap = SphereThreadLook.width / 2, r = SphereThreadLook.dot;
    for (final t in list) {
      if (t.x < c.left || t.x > c.w || t.to <= top || t.dot >= bottom) continue;
      final piece = t.thin ? ThreadSprites.thinDash : ThreadSprites.dash;
      void dash(double y) {
        sprites.add(piece, t.x - ThreadSprites.dashAt.dx, y - ThreadSprites.dashAt.dy, ink);
        threadPieces++;
        c.debug?.note('실 다시 찍기', (t.x, y));
      }

      if (t.sphere == sphere) {
        // 사람 띠(테 포함 상자)를 지나는가 — 제 띠의 아랫변에 앉는 점은 제 띠와 겹쳐도 된다.
        bool inBand(double a, double b, {SpherePersonBand? own}) =>
            persons.any((p) => !identical(p, own) && t.x + cap > p.x0 && t.x - cap < p.x1 && b > p.top && a < p.bottom);
        SpherePersonBand? own;
        for (final p in persons) {
          if ((p.bottom.roundToDouble() + .5 - t.dot).abs() < .01 && t.x >= p.x0 - 1 && t.x <= p.x1 + 1) own = p;
        }
        if (t.dot >= top && t.dot <= bottom && !inBand(t.dot - r, t.dot + r, own: own)) {
          sprites.add(ThreadSprites.dot, t.x - ThreadSprites.dotAt.dx, t.dot - ThreadSprites.dotAt.dy, ink);
          threadPieces++;
          c.debug?.note('실 다시 찍기 점', (t.x, t.dot));
        }
        for (final (a, z) in t.dashes(lo: top, hi: bottom)) {
          if (a - cap >= y1 || inBand(a - cap, z + cap)) continue;
          dash(a);
        }
        continue;
      }
      // 굴 문: [edge]는 테 px의 바깥쪽 경계(위 테 y0 · 아래 테 y1), [inward]는 상자 안쪽 방향.
      void door(double edge, int inward) {
        final a = inward > 0 ? edge - 1 : edge - 2, z = a + TunnelLook.depth;
        final col = t.x - .5;
        c.quads.add(col - 2, a, col + 3, z, c.grounds.at(t.x, inward > 0 ? edge - 2 : edge + 1));
        final s0 = inward > 0 ? a : a - TunnelLook.stub, s1 = inward > 0 ? z + TunnelLook.stub : z;
        for (final (y, e) in t.dashes(lo: s0, hi: s1)) {
          if (y < s0 - cap || e > s1 + cap) continue;
          dash(y);
        }
        threadDoors++;
        c.debug?.note('실 굴문', '${t.x} · 문화권 $sphere · ${inward > 0 ? '위' : '아래'} $edge');
      }

      if (!PaintPick.route) continue; // 굴 문(39)은 이어 주는 선의 새 길과 같은 꼴 — route 뒤에 남김(감독 고름 2026-10-26 떼어서 살림)
      if (t.from < y0 - 1 && t.to > y0 + 3 && y0 > c.head + .5 && y0 < c.h - .5) door(y0, 1);
      if (t.from < y1 - 4 && t.to > y1 + 1 && y1 > c.head + .5 && y1 < c.h - .5) door(y1, -1);
    }
  }

  /// 머리 단의 이름(먹 85 알파) · 띠 수(먹 45 알파) · 접기 표(먹 60) — 그림판 먹 단계([CanvasInk]).
  static final _sphereNameLook = TextLook(Gut.sphereName, ui.FontWeight.w700, CanvasInk.of(0xd9000000));
  static final _sphereCountLook = TextLook(Gut.sphereCount, ui.FontWeight.w400, CanvasInk.of(0x73000000));
  static final _sphereMarkLook = TextLook(Gut.foldHint, ui.FontWeight.w400, CanvasInk.of(Look.muted));

  /// 접기 표(접힘 ▸ · 펼침 ▾) — 글꼴에 기대지 않게 1px 계단의 작은 삼각형(밑변 7 · 높이 4)으로. [x]는 왼쪽, [mid]는 세로 가운데.
  void _sphereMark(PaintContext c, double x, double mid, bool folded, int color) {
    final y = mid.roundToDouble();
    for (int i = 0; i < 4; i++) {
      if (folded) {
        // ▸: 세로 7 · 가로 4 — 왼쪽 세로 변에서 오른쪽 꼭짓점으로
        c.quads.add(x + i, y - 3 + i, x + i + 1, y + 4 - i, color);
      } else {
        // ▾: 가로 7 · 세로 4 — 윗변에서 아래 꼭짓점으로
        c.quads.add(x - 1 + i, y - 2 + i, x + 6 - i, y - 1 + i, color);
      }
    }
  }

  /// 접힌 문화권의 작은 꼬리표(목업 d5-b의 packTags · smallTag): 그 문화권 트랙의 띠(타일 구역 45 — 이름 · 색 · 구간)를
  /// 시작 해 차례로 머리 단 안에 늘어놓는다(늘어놓기 · 그리기는 접힌 폴더와 함께 쓰는 [SmallTags]).
  void _sphereTags(PaintContext c, int sphere, double mid, double startX, double xmax) {
    final layout = c.layout, v = c.v;
    final items = <(double, int, String, int)>[]; // (시작 x, 띠 참조, 이름, 색)
    final seen = <int>{};
    for (final d in c.scene.draw) {
      final t = d.tile, sec = t.section(45);
      if (sec.count == 0) continue;
      final x0 = sec.f(Tile.itemX0), x1 = sec.f(Tile.itemX1), rows = sec.u(Tile.itemRow), refs = sec.u(Tile.itemRef), colors = sec.u(Tile.itemColor), names = sec.u(Tile.itemName);
      final origin = t.origin.toDouble();
      for (int i = 0; i < sec.count; i++) {
        final row = rows[i];
        if (row >= layout.rowCount) continue;
        final track = layout.trackIndexOf(row);
        if (layout.sphereIndexOfTrack(track) != sphere || !layout.isTrackHidden(track)) continue;
        // 보는 범위 밖(화면 왼쪽 앞에서 끝남 · 오른쪽 뒤에서 시작)의 띠는 늘어놓지 않는다(목업 tabsOf — 보는 때 안의 것만).
        if (v.xOf(origin + x1[i]) < c.left || v.xOf(origin + x0[i]) > c.w) continue;
        if (refs[i] != 0 && !seen.add(refs[i])) continue;
        items.add((v.xOf(origin + x0[i]), refs[i], t.text(names[i]), 0xff000000 | colors[i]));
      }
    }
    if (items.isEmpty) return;
    items.sort((a, b) => a.$1.compareTo(b.$1));
    final spots = SmallTags.pack(c, [for (final it in items) (it.$1, it.$3, it.$4)], startX, xmax);
    if (spots == null) {
      c.scene.requestFrame();
      return;
    }
    for (final spot in spots) {
      SmallTags.paint(c, spot, mid, dots.add, tag: 'sphereTag');
    }
  }

  /// 세로 글: 글자를 눕히지 않고 한 글자씩 아래로(css `writing-mode: vertical-rl` + `text-orientation: upright`).
  /// 한 글자의 몫은 [pitch](글자 크기 + 자간)이고, 글자 상자는 그 안에서 가운데.
  ///
  /// 가로 자리: 글자의 **자리 폭(advance) 상자를 em 상자(글자 크기)의 오른쪽 끝**에 붙인다 —
  /// 세로 쓰기 `vertical-rl`은 블록 방향이 오른쪽→왼쪽이라 글자가 제 em 상자의 '시작' 쪽에 붙는다.
  /// 이 글꼴(Noto Sans KR)의 한글 자리 폭은 0.92em이라 먹이 칸 가운데보다 (1em − 자리 폭)/2 = 0.04em 오른쪽에 온다
  /// (브라우저를 같은 css로 따로 재서 확인했다 — 자리 폭의 반으로 가운데를 맞추면 트랙 이름이 1px 왼쪽으로 밀렸다).
  ///
  /// 글자마다의 폭 재기는 글과 글꼴이 그대로면 되풀이하지 않는다 — [slot]에 가운데에서 잰 왼쪽 자리로 적어 두고 옆으로 밀기만 한다.
  void _vertical(PaintContext c, String kind, _Vertical slot, String text, TextLook look, double centerX, double top, double pitch, double clipTop, double clipBottom) {
    var up = slot.upright;
    if (up == null || !up.fits(text, look)) {
      final letters = <String>[], widths = <double>[];
      var ready = true;
      for (final rune in text.runes) {
        final letter = String.fromCharCode(rune);
        final width = c.text.widthOf(letter, look);
        if (width == null) ready = false;
        letters.add(letter);
        widths.add(width ?? look.size);
      }
      up = _Upright(text, look.shapeKey, look.size, letters, widths);
      // 폭이 아직 준비되지 않았으면 보관하지 않는다(다음 장면에 제 폭으로 다시 잰다).
      slot.upright = ready ? up : null;
    }
    double y = top;
    final right = centerX + look.size / 2;
    for (int i = 0; i < up.letters.length; i++) {
      // 세로 글의 한 글자는 제 em 상자(글자 크기)만큼 내려간다 — 글자 그림 상자(1.2배)의 위가 그 em 상자의 위와 거의 같다.
      if (y + pitch >= clipTop && y <= clipBottom) c.later.add(kind, up.letters[i], look, right - up.widths[i], y);
      y += pitch;
    }
  }
}

/// 이름 줄임의 차례(js/timeline.js의 `shortNames` 358~379): 온 이름 → 괄호를 뗀 이름 → (한 낱말이면) 끝의 '민족 · 족'을 뗀 이름 → 그 첫 글자,
/// (여러 낱말이면) 첫 낱말 → 그 낱말의 '민족 · 족'을 뗀 것. 여러 낱말 이름은 한 글자로 자르지 않는다.
List<String> shortNames(String name) {
  final out = <String>[];
  void add(String? text) {
    final t = (text ?? '').trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }

  add(name);
  final bare = name.replaceAll(RegExp(r'\s*[(（][^)）]*[)）]\s*'), ' ').trim();
  add(bare);
  final words = bare.split(RegExp(r'[\s\-‐–·・/]+')).where((w) => w.isNotEmpty).toList();
  String stem(String w) => w.replaceAll(RegExp(r'(민족|족)$'), '');
  if (words.length == 1) {
    final st = stem(words[0]);
    add(st);
    if (st.runes.length > 1) add(String.fromCharCode(st.runes.first));
  } else if (words.length > 1) {
    add(words[0]);
    add(stem(words[0]));
  }
  return out;
}

/// [fits]가 참인 첫 후보. 모두 안 들면 빈 글(칸의 색과 풍선만).
String shortName(String name, bool Function(String) fits) {
  for (final candidate in shortNames(name)) {
    if (fits(candidate)) return candidate;
  }
  return '';
}
