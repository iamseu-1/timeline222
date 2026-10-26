import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/labels.dart' show placeLabels;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show BandLayer, TagEnd, TagLook;
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellKind, CellStyle, StripLayer;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 그림판이 스키마 4의 새 값을 어디까지 그리는지 못 박는 검사(3단계 과제 8 걸음 4에서 시작 — 4단계 과제 5 걸음 2 · 과제 6에서 뜻을 나눔).
// 새 값은 계약 1-1의 다섯 가운데 타일에 실리는 넷이다: 띠의 form(열 10 → 띠 구역 11열) · 빌린 칸의 style 27비트 ·
// 칸 종류 9(직위 줄 더) · 일반 구역 54(빌린 줄의 머리 글) · 55(직위 줄 더의 이름) · 56(실권 밑줄).
//
// 같은 장면을 타일 네 벌로 그려 견준다(strips_paint_test · painter_fixture와 같은 꼴 — 단계 9 · 통 32px · 1920×1080 · 1배).
//   A(옛 값): 띠 · 칸 · 사건 · 구역 43 · 49와, 다리가 복제한 '빌린' 지도자 · 내각 칸(27비트 없이 — 다리는 지금도 칸을 복제해 싣는다).
//   C(form + 아직 그리지 않는 새 값): A + 띠의 form≠0 · 종류 9 칸(단 0 · 1 — 단 1은 27비트) · 구역 54의 a = 9(직위 줄 더의 빌림) · 구역 55.
//     form 셋 가운데 해솔국만 종류 갈래가 옛 짐작과 갈린다(기사단 = 영토 밖 → 둥근 끝 · 옛 종류 국가 → 모따기). 다른 둘은 같은 갈래이고
//     가람 왕국의 정통성 섭정은 그리지 않는 값이다(대립만 그림 — bands_paint_test).
//   B(빌림): C + 빌린 지도자 · 내각 칸의 27비트 · 구역 54의 a = 1 · 2(같은 줄 · 같은 띠 ref).
//   D(실권): A + 구역 56(가람 왕국 띠에 남의 실권 600 ~ 1000 — 같은 기간에 단체의 실권 단 칸 · 제 안의 실권자 1100 ~ 1400).
// (가) A ↔ C: 밀도 넷(보통 · 빽빽하게 · 넉넉하게 · 조감) × 표시 체크 '단체' 켬 · 끔에서(렌즈 끔) — 4단계 차례 걸음 12(G6 가 · 과제 2)부터 form을 그린다:
//   **form이 look과 갈리는 띠(해솔국)만 꼬리표 왼쪽 끝이 다르다** — 왼쪽 두 귀(모따기 → 둥근 끝 — 띠 왼쪽 13px 안)와 구멍 자리(7 → 9)만큼 머리 이름 ·
//   머리 글 구간이 2px 오른쪽. 그 밖의 검사 기록(painter.debugSink.notes — 모든 열쇠를 글로) · 이름(labels) · 띠 조각 · 점 · 막대 · 동군연합 줄 · 장면 통계 ·
//   `toImage` 뒤 rawRgba 바이트(bands_paint_test의 render와 같은 길) · `StripLayer.hitStrips`로 종류 9 칸 자리 · 빌린 칸 자리를 누른 답은 1배 같다.
//   조감은 꼬리표 꼴이 아니라(설계 4-6 #4) 통째로 같다. 종류 9와 구역 54의 a = 9 · 55는 G7(직위 줄 더를 줄 높이에 — 과제 5 걸음 1 · 3) 몫이다.
//   뜻을 다시 나눔(칸 그림 갈래 걸음 4 — G7 가 · `Schema4.officeLinesDrawn` 참): 앱은 이제 종류 9를 **직위 줄 더 층이 선 줄**(줄 fig_wide 21 ~ 25 —
//   배치 판 9 이후 내보내기가 실음)에 그린다. 이 견본의 줄은 그 값이 없는 옛 꼴 줄(fig_wide 비트 3 ~ 5가 0 — 줄 값 없음)이라 층이 없고, 그래서
//   C의 종류 9 칸 · 구역 54의 a = 9 · 55는 여전히 아무것도 그리지 않고 누름에도 안 잡혀 A와 1배 같다 — (가)는 '층 자리가 없는 줄의 종류 9는 그리지 않는다'를 굳힌다.
//   층이 선 줄의 종류 9(층 · 빌림 꼴 · 출처 글 '재상' · 왼쪽 칸 줄 이름)는 office_lines_test · strips_paint_test '종류 9가 빌림 꼴로 그려진다'가 본다.
//   엔진의 범례 · 연도 검색 거르기(되돌릴 자리의 엔진 몫)는 remake-3 몫으로 남았다(schema4_real_engine_test).
// (나) C ↔ B: 4단계 과제 5 걸음 2가 그리는 것만 달라진다(바탕은 C — form의 꼬리표 끝은 둘이 같다) — 빌린 지도자 · 내각 칸(종류 1 · 2의 27비트)은 칸 전체 .72 · 윗변 1px 파선
//   (서고 미리보기 `.tl-cell.is-borrowed` — common.css 2495), 구역 54의 a = 1 · 2는 머리 이름 뒤 `· 지도자 ← 출처 · 내각 ← 출처`(`.tl-borrow` — 2497).
//   기록은 '빌린칸' · '빌린머리'가 더해지고 '칸밝기'는 빌린 칸만 .72배, 이름은 출처 글 둘이 더해지고 빌린 칸 이름만 짙기 .72배,
//   다른 픽셀은 모두 빌린 칸 상자와 출처 글 자리 안이다. 띠 · 점 · 막대 · 동군연합 · 누른 답은 그대로. 조감은 칸도 머리도 없어 통째로 같다.
// (다) A ↔ D: 4단계 과제 6이 그리는 것만 달라진다 — 빼앗긴 띠 머리의 2px 밑줄(띠 윗변 + 11 · 쥔 쪽 색 80% + 먹, 제 안의 실권자는 먹)과
//   끝 이름(쥔 쪽 이름 — 서고 미리보기 `.tl-power-ul` · `.tl-power-name` — common.css 2498 ~ 2499), 그 기간과 겹친 지도자 칸은 칸 전체 .55(`.is-ousted` — 2496).
//   같은 기간에 단체의 실권 단 칸이 그려지면('단체' 켬) 남의 실권의 끝 이름은 빠지고 밑줄은 남는다(과제 6 걸음 2).
//   기록은 '실권밑줄' · '실권이름' · '실권칸'이 더해지고 '칸밝기'는 겹친 지도자 칸만 .55배, 이름은 끝 이름이 더해지고 그 칸 이름만 짙기 .55배,
//   다른 픽셀은 모두 밑줄 · 끝 이름 · 옅어진 칸 자리 안이다. 띠 · 점 · 막대 · 동군연합 · 누른 답은 그대로. 조감은 통째로 같다.
//
// 견줄 때 고쳐 쓰는 것은 '칸이음' 기록의 두 값뿐이다 — 이 기록은 그림의 결정이 아니라 칸의 입력을 그대로 적어 두는 검사용 글이라
// `st=`(칸의 style 그대로)에는 27비트가 보이고, `i=`(타일 칸 배열 안의 자리)는 C · B의 줄 0에 낀 종류 9 칸만큼 뒤 줄 칸에서 밀린다.
// 그래서 `st=`는 27비트를 지운 값으로, `i=`는 그 자리의 칸 번호(id)로 바꿔 견준다. 다른 기록은 글 그대로 견준다.

/// 단계 9에서 통 하나가 32px일 때의 1분 폭. 자리는 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(strips_paint_test와 같은 셈).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// style에 함께 실리는 순번(계약 6-2: 비트 15 ~ 26 = 순번 + 1).
int st(int style, {int seq = -1}) => style | ((seq < 0 ? 0 : seq + 1) << 15);

/// 사건 점의 단을 비워 둔 look(events_paint_test의 freeLane).
const freeLane = 255 << 8;

/// 띠의 form(계약 1-1 비트 — band_form.dart의 BandForm으로 풀린다). 종류 + 1 · 관계 << 5 · (정통성 + 1) << 10 · (중요도 + 1) << 13.
/// 첫불 성채국 = 국가(0) · 중요도 2 / 해솔국 = 기사단(10 — 영토 밖 → 둥근 끝 · 옛 종류는 국가라 옛 짐작은 모따기) · 봉신(4) · 정통(0) /
/// 가람 왕국 = 국가(0) · 섭정(3 — 그리지 않음) · 중요도 3.
const formCheotbul = 1 | 3 << 13, formHaesol = 11 | 4 << 5 | 1 << 10, formGaram = 1 | 4 << 10 | 4 << 13;

/// 3판의 줄 하나(strips_paint_test의 row와 같은 값 + 줄 깃발 [figWide]).
Map<String, dynamic> row(int id, {int phase = 0, int rank = 0, int figWide = 0}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': 4, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': phase, 'rank': rank, 'cats': <int>[],
  'fig': 0, 'fig_wide': figWide, 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 트랙 하나 · 줄 셋. 줄 0 · 1은 왕조 · 시기(단 1) · 지위 · 지도자 · 내각 단, 줄 2는 단체 단 줄(집권 · 실권 — `fig_wide` 비트 7 · 8,
/// 비트 3 ~ 5가 0이 아니어야 읽힌다 — layout.dart RowFlags.legacy)에 지도자 · 내각 단.
SceneLayout shape({required int density, required bool groups}) {
  final layout = SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 4}],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5,
        'dynasty': 1, 'leader': 1, 'cabinet': 1, 'organ': 0, 'rail_levels': 2,
        'rows': [row(0, phase: 1, rank: 1), row(1, phase: 1, rank: 1), row(2, figWide: 8 | 128 | 256)],
      },
    ],
    'epochs': <dynamic>[],
    'categories': [{'id': 1, 'key': 'politics', 'name': '정치', 'color': 0xd4a39b}],
  });
  layout
    ..setConditions(layout.conditions.copyWith(density: density, groups: groups))
    ..finishFlow();
  return layout;
}

/// 칸 하나(타일에 싣기 전). 타일의 칸은 (줄, 종류, 단, 시작) 순이어야 하므로(엔진 부호화의 약속) 모아서 정렬한 뒤 싣는다.
typedef CellSpec = ({int id, int row, double x0, double x1, String name, int kind, int lane, int style, int color});

CellSpec c(int id, int row, double x0, double x1, String name, int kind, {int lane = 0, int style = 0, int color = 0}) =>
    (id: id, row: row, x0: at(x0), x1: at(x1), name: name, kind: kind, lane: lane, style: style, color: color);

/// 동군연합(구역 49)의 풍선 글.
const tip = '동군연합 · 셋째 지도자 = 어린 임금';

/// 타일 네 벌(머리 주석): A 옛 값 · C 아직 그리지 않는 새 값만 · B 빌림(C + 빌린 칸 · 출처 글) · D 실권(A + 구역 56).
enum Vals { old, undrawn, borrow, power }

/// 구역 56의 쥔 쪽(남의 실권 — 가람 왕국 띠 600 ~ 1000)과 제 안의 실권자(1100 ~ 1400).
const powerHolder = '큰 뭍 제국', powerOwn = '세도 가문', powerColor = 0xc8b193;

/// 출처 글(구역 54의 a = 1 · 2 — bands.dart `_borrowsOf`가 지도자 → 내각 차례로 잇는다). 띠 1의 a = 9는 그리지 않는다(이 견본의 줄에는 직위 줄 더 층이 없음 —
/// 층이 선 줄에서만 `· 재상 ← 출처`로 잇는다 · bands.dart `_borrowTextOf`).
const borrowHaesol = '· 지도자 ← 첫불 성채국/지도자 · 내각 ← 첫불 성채국/내각', borrowGaram = '· 지도자 ← 큰 뭍 제국/황제';

/// 타일 하나(단계 9 · x 0).
Uint8List tileOf(Vals vals) {
  final undrawn = vals == Vals.undrawn || vals == Vals.borrow, drawn = vals == Vals.borrow, power = vals == Vals.power;
  final borrow = drawn ? Schema4.borrowed : 0;
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1600), '첫불 성채국', color: 0xa0bcc5, form: undrawn ? formCheotbul : 0)
    ..band(2, 1, at(200), at(1500), '해솔국', color: 0xc8b193, form: undrawn ? formHaesol : 0)
    ..band(3, 2, at(150), at(1550), '가람 왕국', color: 0xb1a0c9, form: undrawn ? formGaram : 0);
  final cells = <CellSpec>[
    // ── 줄 0: 첫불 성채국 — 제 칸만
    c(1, 0, 150, 700, '유리항 깊은 왕조', CellKind.dynasty, style: st(0, seq: 0), color: 0xa0bcc5),
    c(2, 0, 700, 1500, '은결 왕가', CellKind.dynasty, style: st(0, seq: 1), color: 0xc8b193),
    c(10, 0, 150, 500, '은결 나나나', CellKind.leader, style: st(0, seq: 0)),
    c(11, 0, 500, 900, '둘째 지도자', CellKind.leader, style: st(CellStyle.joinLeft | 1 << 14, seq: 1)),
    c(12, 0, 900, 1300, '셋째 지도자', CellKind.leader, style: st(CellStyle.joinLeft, seq: 2)),
    c(13, 0, 150, 800, '첫 내각', CellKind.cabinet, style: st(0, seq: 0)),
    c(14, 0, 800, 1400, '둘째 내각', CellKind.cabinet, style: st(0, seq: 1)),
    c(20, 0, 150, 800, '장부 학파\t복구기', CellKind.phase, style: st(CellStyle.tagged, seq: 0)),
    c(21, 0, 800, 1400, '장부 학파\t안정기', CellKind.phase, style: st(CellStyle.tagged | CellStyle.joinLeft, seq: 1)),
    c(30, 0, 150, 1400, '문지기', CellKind.rank, style: st(4 << 8, seq: 0)),
    // ── 줄 1: 해솔국 — 지도자 · 내각 줄을 첫불 성채국에서 빌림(`leadersFrom` · `cabinetsFrom`: 다리가 출처의 칸을 제 구간으로 잘라 복제)
    c(50, 1, 250, 1400, '해솔 왕가', CellKind.dynasty, style: st(0, seq: 0), color: 0xc8b193),
    c(60, 1, 200, 500, '은결 나나나', CellKind.leader, style: st(0, seq: 0) | borrow),
    c(61, 1, 500, 900, '둘째 지도자', CellKind.leader, style: st(CellStyle.joinLeft | 1 << 14, seq: 1) | borrow),
    c(62, 1, 900, 1300, '셋째 지도자', CellKind.leader, style: st(CellStyle.joinLeft, seq: 2) | borrow),
    c(63, 1, 200, 800, '첫 내각', CellKind.cabinet, style: st(0, seq: 0) | borrow),
    c(64, 1, 800, 1400, '둘째 내각', CellKind.cabinet, style: st(0, seq: 1) | borrow),
    c(70, 1, 250, 1400, '물길 학파\t한 시기', CellKind.phase, style: st(CellStyle.tagged, seq: 0)),
    c(71, 1, 250, 1400, '파수꾼', CellKind.rank, style: st(3 << 8, seq: 0)),
    // ── 줄 2: 가람 왕국(단체 단 줄) — 지도자 줄을 빌림(가운데는 명목 지도자 — 29비트와 27비트가 함께 선다) · 제 내각 · 집권 단(단 2) · 실권 단(단 3)
    c(80, 2, 150, 600, '첫 가람왕', CellKind.leader, style: st(0, seq: 0) | borrow),
    c(81, 2, 600, 1000, '어린 임금', CellKind.leader, style: st(CellStyle.joinLeft | CellStyle.nominalLeader, seq: 1) | borrow),
    c(82, 2, 1000, 1500, '늦은 임금', CellKind.leader, style: st(CellStyle.joinLeft, seq: 2) | borrow),
    c(83, 2, 150, 1500, '가람 내각', CellKind.cabinet, style: st(0, seq: 0)),
    c(90, 2, 200, 700, '들\t들 무리', CellKind.common, lane: 2, style: st(CellStyle.groupOne << 27 | CellStyle.tagged, seq: 0), color: 0xc8b193),
    c(91, 2, 700, 1200, '물·새\t물 무리 · 새벽 무리', CellKind.common, lane: 2, style: st(CellStyle.groupTwo << 27 | CellStyle.tagged | CellStyle.joinLeft, seq: 1), color: 0xd7c18e),
    c(92, 2, 600, 1000, '푸\t푸른 집안', CellKind.common, lane: 3, style: st(CellStyle.groupReal << 27 | CellStyle.tagged, seq: 0), color: 0xa0bcc5),
    // ── C · B: 종류 9(직위 줄 더) — 줄 0의 단 0(제 줄) · 단 1(빌린 줄 — 27비트). (줄, 종류, 단, 시작) 순이라 줄 0의 맨 뒤에 낀다.
    if (undrawn) ...[
      c(40, 0, 200, 900, '첫 재상', Schema4.cellOfficeMore, style: st(0, seq: 0)),
      c(41, 0, 900, 1500, '둘째 재상', Schema4.cellOfficeMore, style: st(CellStyle.joinLeft, seq: 1)),
      c(42, 0, 300, 1200, '나루 재상', Schema4.cellOfficeMore, lane: 1, style: st(0, seq: 0) | Schema4.borrowed),
    ],
  ]..sort((p, q) {
      for (final d in [p.row - q.row, p.kind - q.kind, p.lane - q.lane]) {
        if (d != 0) return d;
      }
      return p.x0.compareTo(q.x0);
    });
  for (final s in cells) {
    t.cell(s.id, s.row, s.x0, s.x1, s.name, kind: s.kind, lane: s.lane, style: s.style, color: s.color);
  }
  t
    // 사건(띠 안 · 점과 이름)
    ..event(100, 0, at(300), '첫불 성채 세움', look: freeLane, band: 1)
    ..event(101, 0, at(1000), '둘째 성 쌓음', look: freeLane, band: 1)
    ..event(102, 1, at(700), '해솔 나루 엶', look: freeLane, band: 2)
    ..event(103, 2, at(1100), '가람 큰물', look: freeLane, band: 3)
    // 구역 43 — 단체 칸이 가리키는 단체(연정 칸은 둘째 색 · 색 점)
    ..item(43, 200, 2, at(200), at(700), ref: 3, a: CellKind.common, b: 2, c: 1, text2: 'sample/pw-deul')
    ..item(43, 201, 2, at(700), at(1200), ref: 3, a: CellKind.common, b: 2, c: 2, color: 0xbbacc8, text2: 'sample/pw-mul\td7c18e,bbacc8')
    ..item(43, 202, 2, at(600), at(1000), ref: 3, a: CellKind.common, b: 3, c: 1, text2: 'sample/pw-pureun')
    // 구역 49 — 동군연합: 해솔국의 빌린 셋째 지도자(순번 2) = 가람 왕국의 빌린 명목 지도자(순번 1). 겹친 기간 900 ~ 1000의 가운데 950.
    ..item(49, 300, 1, at(950), at(1000), ref: 2, name: tip, a: 2, b: 3, c: 1, text2: 'k1')
    ..item(49, 301, 2, at(950), at(1000), ref: 3, name: tip, a: 1, b: 2, c: 2, text2: 'k1');
  // 구역 54 — 빌린 직위 줄의 머리 글(ref = 빌린 쪽 띠 · a = 칸 종류 · b = 직위 줄 더의 단 · text2 = 출처 uid). 지도자 · 내각 줄(a = 1 · 2)은 B에만,
  // 직위 줄 더의 빌림(a = 9)은 C · B에(그리지 않는다).
  if (drawn) {
    t
      ..item(Schema4.secBorrowHead, 400, 1, at(200), at(1500), ref: 2, name: '첫불 성채국/지도자', a: CellKind.leader, text2: 'sample/cheotbul')
      ..item(Schema4.secBorrowHead, 401, 1, at(200), at(1500), ref: 2, name: '첫불 성채국/내각', a: CellKind.cabinet, text2: 'sample/cheotbul');
  }
  if (undrawn) t.item(Schema4.secBorrowHead, 402, 0, at(100), at(1600), ref: 1, name: '나루국/재상', a: Schema4.cellOfficeMore, b: 1, text2: 'sample/naru');
  if (drawn) t.item(Schema4.secBorrowHead, 403, 2, at(150), at(1550), ref: 3, name: '큰 뭍 제국/황제', a: CellKind.leader, text2: 'sample/keunmut');
  if (undrawn) {
    t
      // 구역 55 — 직위 줄 더의 이름(b = 그 줄의 단)
      ..item(Schema4.secOfficeName, 410, 0, at(100), at(1600), ref: 1, name: '재상', b: 0)
      ..item(Schema4.secOfficeName, 411, 0, at(100), at(1600), ref: 1, name: '나루 재상', b: 1);
  }
  if (power) {
    t
      // 구역 56 — 실권 밑줄(빼앗긴 띠에 · 쥔 쪽 이름 · 색 · uid) · 제 안의 실권자(a = 1). 남의 실권 기간은 단체의 실권 단 칸(92 — 600 ~ 1000)과 같다.
      ..item(Schema4.secPowerLine, 420, 2, at(600), at(1000), ref: 3, name: powerHolder, color: powerColor, text2: 'sample/keunmut')
      ..item(Schema4.secPowerLine, 421, 2, at(1100), at(1400), ref: 3, name: powerOwn, a: 1);
  }
  return t.build();
}

/// 그린 이름 하나(검사 기록의 labels).
typedef Label = ({String kind, String text, double x, double y, double alpha});

/// 장면 하나를 그린 결과 — 견줄 것을 모두 글과 바이트로.
class Shot {
  Shot(this.pixels, this.notes, this.labels, this.marks, this.stats, this.hits, this.borrowedCells, this.headZones, this.ends);
  final Uint8List pixels;
  final Map<String, List<String>> notes;
  final List<Label> labels;
  final List<String> marks, stats, hits;

  /// '칸' 기록 차례로, 그 칸이 빌린 칸(고쳐 쓰기 전 '칸이음'의 `st=`에 종류 1 · 2의 27비트)인가 — 그림판이 그 값을 받았다는 표시.
  final List<bool> borrowedCells;

  /// 머리 줄의 글이 차지한 구간(띠 층 `headNameZones` — 이름 · 출처 글, 앞뒤 4).
  final Map<int, List<(double, double)>> headZones;

  /// 띠 1 · 2 · 3의 꼬리표 왼쪽 끝(띠 층이 이 장면에 정한 것 — 관계선 구멍 · 받침 카드가 따른다).
  final Map<int, TagEnd> ends;

  int get borrowedStyles => borrowedCells.where((b) => b).length;

  /// 이름을 한 줄 글로(견줄 때 · 실패 글).
  static String text(Label l) => '${l.kind} ${l.text} ${r1(l.x)},${r1(l.y)} ${l.alpha}';
}

/// '칸이음' 기록('종류:줄:단 … st=… … i=…')의 칸 종류와 style.
(int, int) joinKindStyle(String note) =>
    (int.parse(note.substring(0, note.indexOf(':'))), int.parse(RegExp(r'\bst=(\d+)').firstMatch(note)![1]!));

/// 그 '칸이음' 기록의 칸이 빌린 칸(27비트 — 종류 1 · 2 · 9에서만. 종류 8의 27비트는 단 갈래의 아래 비트다)인가.
bool joinBorrowed(String note) {
  final (kind, style) = joinKindStyle(note);
  return Schema4.isBorrowed(kind, style);
}

/// '칸이음' 기록의 두 값을 견줄 꼴로 — 머리 주석의 까닭. [t]는 그 장면의 타일(배열 자리 → 칸 번호).
/// 27비트는 빌린 칸(종류 1 · 2 · 9)에서만 지운다 — 종류 8(단체 단)의 갈래 5 · 7은 27비트가 선 그대로 견준다.
String normalJoin(String note, Tile t) => note
    .replaceAllMapped(RegExp(r'\bst=(\d+)'), (m) => 'st=${joinBorrowed(note) ? int.parse(m[1]!) & ~Schema4.borrowed : int.parse(m[1]!)}')
    .replaceAllMapped(RegExp(r' i=(\d+)$'), (m) => ' id=${t.cellId[int.parse(m[1]!)]}');

String r1(double v) => v.toStringAsFixed(2);
String rect(ui.Rect r) => '${r1(r.left)},${r1(r.top)},${r1(r.width)},${r1(r.height)}';

/// 누를 자리: 종류 9 칸 · 빌린 칸(B 기준 — A에는 같은 자리에 같은 빌린 칸이 27비트 없이 있다)의 가운데 · 두 끝 안쪽 2px을
/// 그 줄의 몫 위아래 전부(1px 걸음)로, 그리고 화면 몸통 전체를 성기게(25px · 3px 걸음).
List<ui.Offset> pokesOf(TimelineScene scene) {
  final v = scene.controller.view, layout = scene.layout;
  final b = Tile.decode(tileOf(Vals.borrow));
  final xsOf = <int, List<double>>{};
  for (int i = 0; i < b.cellCount; i++) {
    if (!Schema4.isBorrowed(b.cellKind[i], b.cellStyle[i]) && b.cellKindOf(i) != Schema4.cellOfficeMore) continue;
    final l = v.xOf(b.cellX0[i].toDouble()), r = v.xOf(b.cellX1[i].toDouble());
    (xsOf[b.cellRow[i]] ??= []).addAll([(l + r) / 2, l + 2, r - 2]);
  }
  final out = <ui.Offset>[];
  for (final MapEntry(key: r, value: xs) in xsOf.entries) {
    if (r >= layout.rowCount || !layout.isVisible(r)) continue;
    final top = v.yOf(layout.rowTop(r)), height = layout.geo(r).height;
    for (double y = top; y <= top + height; y += 1) {
      for (final x in xs) {
        out.add(ui.Offset(x, y + .5));
      }
    }
  }
  for (double y = v.head; y < 1080; y += 3) {
    for (double x = v.left; x < 1920; x += 25) {
      out.add(ui.Offset(x + .5, y + .5));
    }
  }
  return out;
}

/// 장면을 지어 이름 판까지 가라앉힌 뒤 한 번 그려(그림을 떠서) 견줄 것을 모은다.
Future<Shot> shoot(Vals vals, {required int density, required bool groups}) async {
  var now = 0.0;
  final layout = shape(density: density, groups: groups);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(layout.totalHeight);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final bytes = tileOf(vals);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    clock: () => now,
    labelCompute: (input) async => placeLabels(input),
    fetchTile: (level, x, chunk, packs) async =>
        level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  addTearDown(scene.dispose);
  final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
  void paintOnce() {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }

  // 타일 받기 → 이름 판(작업자) → 글자 폭이 처음 그릴 때 재지는 것까지 가라앉힌다(events_paint_test의 settle).
  int calm = 0;
  for (int i = 0; i < 80 && calm < 3; i++) {
    now += 1000;
    scene.prepare();
    paintOnce();
    await pumpEventQueue();
    final out = scene.labelOutput;
    calm = out != null && out.deferred == 0 && !scene.labelWorker.busy && scene.stats.blanks == 0 && scene.stats.tiles > 0 ? calm + 1 : 0;
  }
  expect(calm, 3, reason: '장면이 가라앉지 않았다');

  // 견주는 장면 — 그림을 뜨는 이 한 번의 그리기에서 기록도 함께 읽는다.
  now += 1000;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  expect(painter.text.starved, isFalse, reason: '글줄 준비가 모자란 장면이다');
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();

  final tile = Tile.decode(bytes);
  final sink = painter.debugSink;
  final notes = <String, List<String>>{
    for (final key in sink.notes.keys.toList()..sort())
      key: [for (final v in sink.notes[key]!) key == '칸이음' ? normalJoin('$v', tile) : '$v'],
  };
  final s = scene.stats;
  final hit = painter.strips;
  return Shot(
    data!.buffer.asUint8List(),
    notes,
    [for (final l in sink.labels) (kind: l.kind, text: l.text, x: l.at.dx, y: l.at.dy, alpha: l.alpha)],
    [
      for (final b in sink.bands) '띠 ${b.id} ${rect(b.rect)} ${b.roundLeft} ${b.roundRight} ${b.fadeLeft} ${b.fadeRight}',
      for (final d in sink.dots) '점 ${d.eventId} ${r1(d.at.dx)},${r1(d.at.dy)} ${d.extra}',
      for (final b in sink.bars) '막대 ${b.eventId} ${rect(b.rect)}',
      for (final (x, y0, y3, a) in painter.unions.debugLines) '연합줄 ${r1(x)} ${r1(y0)}~${r1(y3)} $a',
      for (final (band, ref, x) in painter.unions.debugMarks) '연합표지 $band|$ref ${r1(x)}',
      '고름 ${sink.selectionAt} · 눈금 ${sink.gridLines}',
    ],
    [
      'shapes ${s.shapes}', 'labels ${s.labels}', 'tiles ${s.tiles}', 'covers ${s.covers}', 'blanks ${s.blanks}',
      'nameBatch ${s.nameBatch}', 'namesDrawn ${s.namesDrawn}', 'ghostNames ${s.ghostNames}',
    ],
    [
      for (final p in pokesOf(scene))
        switch (hit.hitStrips(p.dx, p.dy)) {
          null => '',
          final h => '${h.band} ${h.row} ${h.kind} ${h.ref} ${h.uid} ${h.name} ${rect(h.rect)} ${h.houseId} ${h.houseName} ${h.houseColor}',
        },
    ],
    [
      for (final v in sink.notes['칸이음'] ?? const <Object>[])
        () {
          final (kind, _) = joinKindStyle('$v');
          return (kind == CellKind.leader || kind == CellKind.cabinet) && joinBorrowed('$v');
        }(),
    ],
    {for (final MapEntry(:key, :value) in painter.bands.headNameZones.entries) key: List.of(value)},
    {for (final id in const [1, 2, 3]) id: painter.bands.endOf(id)},
  );
}

/// 두 그림의 첫 다른 픽셀(없으면 null).
String? firstPixelDiff(Uint8List a, Uint8List b) {
  if (a.length != b.length) return '길이 ${a.length} · ${b.length}';
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      final p = i ~/ 4;
      return '(${p % 1920}, ${p ~/ 1920}) 채널 ${i % 4}: ${a[i]} → ${b[i]}';
    }
  }
  return null;
}

/// (가) · 조감의 (나): 두 장면이 기록 · 이름 · 띠 · 통계 · 누른 답 · 그림 바이트까지 같다.
void expectSameShot(Shot a, Shot b, String label) {
  expect(b.notes.keys.toList(), a.notes.keys.toList(), reason: '$label 기록 열쇠');
  for (final key in a.notes.keys) {
    expect(b.notes[key], a.notes[key], reason: '$label 기록 \'$key\'');
  }
  expect(b.labels.map(Shot.text).toList(), a.labels.map(Shot.text).toList(), reason: '$label 이름');
  expect(b.marks, a.marks, reason: '$label 띠 · 점 · 막대 · 동군연합');
  expect(b.stats, a.stats, reason: '$label 통계');
  expect(b.hits.length, a.hits.length);
  for (int i = 0; i < a.hits.length; i++) {
    if (a.hits[i] != b.hits[i]) fail('$label 누른 답 $i번: A「${a.hits[i]}」 · B「${b.hits[i]}」');
  }
  expect(firstPixelDiff(a.pixels, b.pixels), isNull, reason: '$label 그림 바이트');
}

/// (가)의 밀도 보통 · 빽빽하게 · 넉넉하게: form이 look과 갈리는 띠(해솔국 — 띠 2 · 줄 1)만 꼬리표 왼쪽 끝이 다르다.
/// 기록 · 띠 · 통계 · 누른 답은 같고, 이름은 그 띠의 머리 이름만 x가 구멍 차이(9 − 7)만큼 · 머리 글 구간도 그만큼 오른쪽,
/// 다른 픽셀은 모두 그 띠의 왼쪽 끝(띠 왼쪽 − 1 ~ + 13 · 위아래 ±1)과 머리 이름 자리(옛 · 새 구간을 합친 것) 안 — 왼쪽 끝 안에는 다른 픽셀이 있다(귀의 꼴).
void expectTagEndOnly(Shot a, Shot c, String label) {
  final shift = TagLook.holeAt(TagEnd.key, G.head) - TagLook.holeAt(TagEnd.cham, G.head);
  expect(shift, 2);
  expect(a.ends, {1: TagEnd.cham, 2: TagEnd.cham, 3: TagEnd.cham}, reason: '$label A — form 없음: 옛 짐작(옛 종류 국가 → 모따기)');
  expect(c.ends, {1: TagEnd.cham, 2: TagEnd.key, 3: TagEnd.cham}, reason: '$label C — 해솔국(기사단)만 둥근 끝');
  expect(c.notes.keys.toList(), a.notes.keys.toList(), reason: '$label 기록 열쇠');
  for (final key in a.notes.keys) {
    expect(c.notes[key], a.notes[key], reason: '$label 기록 \'$key\'');
  }
  expect(c.marks, a.marks, reason: '$label 띠 · 점 · 막대 · 동군연합');
  expect(c.stats, a.stats, reason: '$label 통계');
  expect(c.hits.length, a.hits.length);
  for (int i = 0; i < a.hits.length; i++) {
    if (a.hits[i] != c.hits[i]) fail('$label 누른 답 $i번: A「${a.hits[i]}」 · C「${c.hits[i]}」');
  }
  // 이름: 해솔국 머리 이름만 2px 오른쪽.
  expect(c.labels.length, a.labels.length, reason: '$label 이름 수');
  var moved = 0;
  for (int i = 0; i < a.labels.length; i++) {
    final x = a.labels[i], y = c.labels[i];
    final head = y.kind == 'tab' && y.text == '해솔국';
    expect((y.kind, y.text, r1(y.x - (head ? shift : 0)), r1(y.y), y.alpha), (x.kind, x.text, r1(x.x), r1(x.y), x.alpha), reason: '$label 이름 ${Shot.text(y)}');
    if (head) moved++;
  }
  expect(moved, 1, reason: '$label 해솔국 머리 이름');
  // 머리 글 구간: 줄 1(해솔국)만 그만큼.
  expect(c.headZones.keys.toSet(), a.headZones.keys.toSet());
  for (final MapEntry(key: row, value: zones) in a.headZones.entries) {
    final want = row == 1 ? [for (final z in zones) (z.$1 + shift, z.$2 + shift)] : zones;
    expect([for (final z in c.headZones[row]!) '${r1(z.$1)},${r1(z.$2)}'], [for (final z in want) '${r1(z.$1)},${r1(z.$2)}'], reason: '$label 줄 $row 머리 글 구간');
  }
  // 픽셀: 해솔국의 왼쪽 끝 · 머리 이름 자리 밖은 같다.
  final band = a.marks.firstWhere((m) => m.startsWith('띠 2 ')).split(' ')[2].split(',').map(double.parse).toList();
  final end = ui.Rect.fromLTRB(band[0] - 1, band[1] - 1, band[0] + 13, band[1] + band[3] + 1);
  final tab = a.labels.firstWhere((l) => l.kind == 'tab' && l.text == '해솔국');
  final zoneA = a.headZones[1]!.firstWhere((z) => (z.$1 - (tab.x - 4)).abs() < 1e-6);
  final name = ui.Rect.fromLTRB(zoneA.$1, tab.y - 3, zoneA.$2 + shift, tab.y + 12);
  var outside = '', inEnd = 0;
  for (int i = 0; i < a.pixels.length; i += 4) {
    if (a.pixels[i] == c.pixels[i] && a.pixels[i + 1] == c.pixels[i + 1] && a.pixels[i + 2] == c.pixels[i + 2] && a.pixels[i + 3] == c.pixels[i + 3]) continue;
    final p = i ~/ 4, at = ui.Offset(p % 1920 + .5, p ~/ 1920 + .5);
    if (end.contains(at)) {
      inEnd++;
    } else if (!name.contains(at)) {
      outside = outside.isEmpty ? '(${at.dx}, ${at.dy})' : outside;
    }
  }
  expect(outside, '', reason: '$label 해솔국의 왼쪽 끝 · 머리 이름 밖에서 바뀐 픽셀');
  expect(inEnd, greaterThan(0), reason: '$label 해솔국의 왼쪽 귀가 둥근 끝으로');
}

/// 검사용 기록 '종류:줄:단 l,t,w[,h] …'(0.1px 단위)의 머리와 수.
(String, List<int>) noteParts(String note) {
  final parts = note.split(' ');
  return (parts[0], [for (final v in parts[1].split(',')) int.parse(v)]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('견본 타일', () {
    test('C는 A에 아직 그리지 않는 새 값만 · B는 C에 빌림(빌린 칸 27비트 · 구역 54의 a = 1 · 2)만 · D는 A에 구역 56만 더했다 — 검사가 헛돌지 않게', () {
      final a = Tile.decode(tileOf(Vals.old)), cc = Tile.decode(tileOf(Vals.undrawn)), b = Tile.decode(tileOf(Vals.borrow)), d = Tile.decode(tileOf(Vals.power));
      // 띠: C · B만 form 열이 있어 11열, 나머지 열은 같다.
      expect((a.section(Tile.secBand).columns, cc.section(Tile.secBand).columns, b.section(Tile.secBand).columns), (10, 11, 11));
      expect(a.bandForm, [0, 0, 0]);
      expect(cc.bandForm, [formCheotbul, formHaesol, formGaram]);
      expect(b.bandForm, cc.bandForm);
      for (final t in [cc, b]) {
        for (final (x, y) in [(a.bandId, t.bandId), (a.bandRow, t.bandRow), (a.bandColor, t.bandColor), (a.bandLook, t.bandLook), (a.bandFlags, t.bandFlags)]) {
          expect(y, x);
        }
      }
      // 칸: C · B에서 종류 9를 빼고 27비트를 지우면 A와 칸마다 같다(차례도 — 종류 9는 줄 0의 맨 뒤에 낀다).
      String cellOf(Tile t, int i) =>
          '${t.cellId[i]} ${t.cellRow[i]} ${t.cellKind[i]} ${t.cellLane[i]} ${t.cellX0[i]} ${t.cellX1[i]} ${t.text(t.cellName[i])} '
          '${Schema4.isBorrowed(t.cellKind[i], t.cellStyle[i]) ? t.cellStyle[i] & ~Schema4.borrowed : t.cellStyle[i]} ${t.cellColor[i]}';
      for (final t in [cc, b]) {
        final officeMore = Schema4.officeMoreCells(t);
        expect([for (final i in officeMore) t.cellId[i]], [40, 41, 42]);
        expect(officeMore, [10, 11, 12], reason: '줄 0의 칸 열 개 뒤 — 줄 1의 칸부터 배열 자리가 셋씩 밀린다');
        expect([for (int i = 0; i < t.cellCount; i++) if (!officeMore.contains(i)) cellOf(t, i)], [for (int i = 0; i < a.cellCount; i++) cellOf(a, i)]);
      }
      List<int> borrowedIds(Tile t) => [for (int i = 0; i < t.cellCount; i++) if (Schema4.isBorrowed(t.cellKind[i], t.cellStyle[i])) t.cellId[i]];
      expect(borrowedIds(a), isEmpty);
      expect(borrowedIds(cc), [42], reason: 'C의 27비트는 종류 9 칸에만(그리지 않는 줄)');
      expect(borrowedIds(b), [42, 60, 61, 62, 63, 64, 80, 81, 82]);
      // 빌린 명목 지도자: 27비트와 29비트가 함께 서고 순번은 그대로다.
      final nominal = [for (int i = 0; i < b.cellCount; i++) b.cellId[i]].indexOf(81);
      expect(b.cellStyle[nominal] & CellStyle.nominalLeader, isNonZero);
      expect(CellStyle.seqOf(b.cellStyle[nominal]), 1);
      // 일반 구역: C · B만 54 · 55(같은 띠 ref · 같은 줄), D만 56. 구역 54는 C에 a = 9 하나, B에 a = 1 · 2가 더. 사건 · 구역 43 · 49는 같다.
      expect(Schema4.borrowHeads(a), isEmpty);
      expect(Schema4.officeNames(a), isEmpty);
      expect(Schema4.powerLines(a), isEmpty);
      expect([for (final h in Schema4.borrowHeads(cc)) (h.band, h.row, h.kind, h.lane)], [(1, 0, 9, 1)]);
      expect([for (final h in Schema4.borrowHeads(b)) (h.band, h.row, h.kind, h.lane)], [(2, 1, 1, 0), (2, 1, 2, 0), (1, 0, 9, 1), (3, 2, 1, 0)]);
      for (final t in [cc, b]) {
        expect([for (final n in Schema4.officeNames(t)) (n.band, n.row, n.lane, n.name)], [(1, 0, 0, '재상'), (1, 0, 1, '나루 재상')]);
        expect(Schema4.powerLines(t), isEmpty);
        expect(t.sectionKinds, [...a.sectionKinds, 54, 55]);
      }
      // D: 띠 · 칸은 A 그대로(form 0 · 10열 · 27비트 없음)에 구역 56 둘 — 남의 실권은 단체의 실권 단 칸(92)과 같은 기간이다.
      expect(d.section(Tile.secBand).columns, 10);
      expect([for (int i = 0; i < d.cellCount; i++) cellOf(d, i)], [for (int i = 0; i < a.cellCount; i++) cellOf(a, i)]);
      expect(borrowedIds(d), isEmpty);
      expect([for (final p in Schema4.powerLines(d)) (p.band, p.row, p.holder, p.color, p.own, p.holderUid)],
          [(3, 2, powerHolder, powerColor, false, 'sample/keunmut'), (3, 2, powerOwn, 0, true, '')]);
      final real = [for (int i = 0; i < d.cellCount; i++) d.cellId[i]].indexOf(92);
      expect((d.cellKindOf(real), d.cellLane[real], CellStyle.bandOf(d.cellStyle[real])), (CellKind.common, 3, CellStyle.groupReal));
      expect((d.cellX0[real], d.cellX1[real]), (Schema4.powerLines(d).first.x0, Schema4.powerLines(d).first.x1));
      expect(d.sectionKinds, [...a.sectionKinds, 56]);
      expect((a.eventCount, cc.eventCount, b.eventCount, d.eventCount), (4, 4, 4, 4));
    });
  });

  // 밀도(−1 넉넉하게 · 0 보통 · 1 빽빽하게 · 2 조감) × 표시 체크 '단체'. 렌즈는 끈 채(기본).
  for (final (density, name) in const [(0, '보통'), (1, '빽빽하게'), (-1, '넉넉하게'), (2, '조감')]) {
    for (final groups in const [true, false]) {
      final label = '밀도 $name · 단체 ${groups ? '켬' : '끔'}';
      test('(가) $label: 옛 값 타일(A)과 form · 층 자리가 없는 줄의 종류 9 등 그리지 않는 새 값을 더한 타일(C)의 장면은 form이 look과 갈리는 띠의 꼬리표 왼쪽 끝만 다르다(조감은 1배 같다)', () async {
        final a = await shoot(Vals.old, density: density, groups: groups);
        final cc = await shoot(Vals.undrawn, density: density, groups: groups);
        // 검사가 헛돌지 않게: 장면이 실제로 그려졌다(띠 · 이름 · 칸).
        expect(a.marks.where((m) => m.startsWith('띠 ')), isNotEmpty, reason: '띠가 그려지지 않았다');
        expect(a.labels, isNotEmpty, reason: '이름이 그려지지 않았다');
        final drawnCells = a.notes['칸'] ?? const <String>[];
        if (density == 2) {
          expect(drawnCells, isEmpty, reason: '조감에는 띠 안의 단이 없다');
        } else {
          // 빌린 지도자 칸(줄 1 · 줄 2의 종류 1)이 그려졌고, 그 자리를 누르면 칸이 잡힌다.
          expect(drawnCells.where((n) => n.startsWith('1:1:')), isNotEmpty, reason: '줄 1의 빌린 지도자 칸');
          expect(drawnCells.where((n) => n.startsWith('2:1:')), isNotEmpty, reason: '줄 1의 빌린 내각 칸');
          expect(a.hits.where((h) => h.isNotEmpty), isNotEmpty, reason: '누른 자리에서 잡힌 칸이 하나도 없다');
          // C의 27비트는 종류 9 칸에만 있어 그려지는 칸에 닿지 않는다(이 견본의 줄은 직위 줄 더 층이 없는 옛 꼴 줄 — 머리 주석 '뜻을 다시 나눔').
          expect((a.borrowedStyles, cc.borrowedStyles), (0, 0));
          for (int r = 0; r < 3; r++) {
            expect(shape(density: density, groups: groups).geo(r).officeTop, -1, reason: '줄 $r: 직위 줄 더 층 없음(줄 값 없음)');
          }
        }
        // 아래 C ↔ A '꼬리표 끝만 다름'에는 층 자리가 없는 줄의 종류 9 칸이 아무것도 그리지 않고 누름에도 안 잡힌다는 기대가 든다.
        if (density == 2) {
          expectSameShot(a, cc, label);
        } else {
          expectTagEndOnly(a, cc, label);
        }
      });

      test('(나) $label: 빌린 지도자 · 내각 칸(.72 · 윗변 파선)과 구역 54의 출처 글만 새로 그린다 — 나머지는 C와 1배 같다', () async {
        final a = await shoot(Vals.undrawn, density: density, groups: groups); // 바탕은 C(B = C + 빌림 — form의 꼬리표 끝은 둘이 같다)
        final b = await shoot(Vals.borrow, density: density, groups: groups);
        if (density == 2) {
          // 조감: 띠 안의 단도 머리 이름도 없다(이름은 띠 안 이름 — 출처 글 없음) — 통째로 같다.
          expect(b.notes['빌린칸'], isNull);
          expect(b.notes['빌린머리'], isNull);
          expectSameShot(a, b, label);
          return;
        }
        // (1) 기록: '빌린칸' · '빌린머리'가 더해지고, '칸밝기'는 빌린 칸만 .72배, '층선'(칸 층 가로선 — 아래 (1-2))은 빌린 칸의 층 윗줄만 빔, 나머지 열쇠는 글 그대로.
        expect(b.notes.keys.toSet(), {...a.notes.keys, '빌린칸', '빌린머리'}, reason: '$label 기록 열쇠');
        for (final key in a.notes.keys) {
          if (key != '칸밝기' && key != '층선') expect(b.notes[key], a.notes[key], reason: '$label 기록 \'$key\'');
        }
        final cellsA = a.notes['칸']!, lightA = a.notes['칸밝기']!, lightB = b.notes['칸밝기']!;
        expect(b.borrowedCells.length, cellsA.length);
        expect(lightB.length, lightA.length);
        final wantTop = <String>[];
        final borrowedRects = <ui.Rect>[];
        for (int i = 0; i < cellsA.length; i++) {
          if (!b.borrowedCells[i]) {
            expect(lightB[i], lightA[i], reason: '$label 빌리지 않은 칸의 밝기 $i');
            continue;
          }
          final (head, va) = noteParts(lightA[i]);
          final (headB, vb) = noteParts(lightB[i]);
          expect(headB, head);
          expect(vb[0], closeTo(va[0] * StripLayer.borrowedAlpha, 1), reason: '$label 빌린 칸 $head의 왼쪽 밝기');
          expect(vb[1], closeTo(va[1] * StripLayer.borrowedAlpha, 1), reason: '$label 빌린 칸 $head의 오른쪽 밝기');
          final (_, box) = noteParts(cellsA[i]);
          wantTop.add('$head ${box[0]},${box[1] - 10},${box[2]}'); // 파선은 칸 한 줄 위(층 맨 윗줄 — 미리보기 칸 상자의 윗 테두리)
          borrowedRects.add(ui.Rect.fromLTWH(box[0] / 10, box[1] / 10, box[2] / 10, box[3] / 10));
        }
        // (1-2) 칸 층 가로선(감독 지적 2026-10-25 — paint/floor_rules.dart '층선' — 띠 · y×10 · x0×10,x1×10 · 밝기×1000): 가로선은 띠의 밝기라 빌린 칸의 .72를
        // 타지 않고, 빌린 칸의 층 윗줄(윗변 파선 줄 — 칸 한 줄 위)만 긋지 않는다. B의 선 픽셀은 모두 C에 같은 밝기로 있고, C에만 있는 픽셀은 빌린 칸의 파선 줄 위다.
        Map<(int, int, int), int> rulePixels(List<String>? notes) => {
          for (final n in notes ?? const <String>[])
            for (int x = int.parse(n.split(' ')[2].split(',')[0]) ~/ 10; x < int.parse(n.split(' ')[2].split(',')[1]) ~/ 10; x++)
              (int.parse(n.split(' ')[0]), int.parse(n.split(' ')[1]) ~/ 10, x): int.parse(n.split(' ')[3]),
        };
        final rulesC = rulePixels(a.notes['층선']), rulesB = rulePixels(b.notes['층선']);
        if (density != 2) expect(rulesC, isNotEmpty, reason: '$label 가로선이 있는 장면이다');
        for (final e in rulesB.entries) {
          expect(rulesC[e.key], e.value, reason: '$label B의 가로선 픽셀 ${e.key}는 C에 같은 밝기로');
        }
        for (final k in rulesC.keys) {
          if (rulesB.containsKey(k)) continue;
          expect(borrowedRects.any((r) => k.$2 == (r.top - 1).floor() && k.$3 >= r.left - 1 && k.$3 < r.right + 1), isTrue,
              reason: '$label C에만 있는 가로선 픽셀 $k는 빌린 칸의 파선 줄 위여야 한다');
        }
        final tops = b.notes['빌린칸']!;
        expect([for (final n in tops) n.substring(0, n.lastIndexOf(' '))], wantTop, reason: '$label 빌린 칸마다 윗변 파선 하나 — 칸과 같은 가로 자리 · 칸 한 줄 위');
        expect(tops.every((n) => n.startsWith('1:') || n.startsWith('2:')), isTrue, reason: '빌린 칸은 지도자 · 내각만(종류 8 단체 칸의 27비트 · 종류 9는 아님)');
        expect([for (final n in tops) int.parse(n.split(' ').last)], everyElement(720), reason: '고른 것이 없으면 칸 밝기 1 × .72');
        if (density <= 0) {
          // 보통 · 넉넉하게: 빌린 지도자 칸 줄 1 · 2와 빌린 내각 칸 줄 1이 모두 낱칸으로 그려진다(빽빽하게는 빽빽한 칸이 되면 빌림 꼴 없이 — 미리보기와 같음).
          for (final head in ['1:1:', '2:1:', '1:2:']) {
            expect(tops.where((n) => n.startsWith(head)), isNotEmpty, reason: '$label $head 빌린 칸');
          }
        }
        // (2) 출처 글: 띠 2(해솔국 — 지도자 · 내각) · 띠 3(가람 왕국 — 지도자). 띠 1의 a = 9(직위 줄 더)는 그리지 않는다.
        final heads = b.notes['빌린머리']!;
        expect([for (final n in heads) n.split(' ').first], ['2', '3'], reason: '$label 출처 글의 띠');
        expect([for (final n in heads) n.substring(n.indexOf(' ', n.indexOf(' ') + 1) + 1)], [borrowHaesol, borrowGaram]);
        // (3) 이름: 출처 글 둘이 더해지고(머리 이름 탭 뒤), 빌린 칸 안의 칸 이름만 짙기 .72배 — 자리 · 글은 그대로.
        final borrowLabels = [for (final l in b.labels) if (l.kind == 'borrow') l];
        expect([for (final l in borrowLabels) l.text], [borrowHaesol, borrowGaram]);
        final rest = [for (final l in b.labels) if (l.kind != 'borrow') l];
        expect(rest.length, a.labels.length, reason: '$label 이름 수');
        var dimmed = 0;
        for (int i = 0; i < rest.length; i++) {
          final x = a.labels[i], y = rest[i];
          expect((y.kind, y.text, r1(y.x), r1(y.y)), (x.kind, x.text, r1(x.x), r1(x.y)), reason: '$label 이름 $i');
          if (y.alpha == x.alpha) continue;
          expect(y.kind, 'cell', reason: '$label 짙기가 바뀐 이름은 칸 이름뿐: ${Shot.text(y)}');
          expect(y.alpha, closeTo(x.alpha * StripLayer.borrowedAlpha, 1e-9));
          expect(borrowedRects.any((r) => y.x >= r.left - .5 && y.x <= r.right && y.y >= r.top - 2 && y.y <= r.bottom), isTrue, reason: '$label 빌린 칸 안의 이름: ${Shot.text(y)}');
          dimmed++;
        }
        if (density <= 0) expect(dimmed, greaterThan(0), reason: '$label 빌린 칸 이름이 하나는 그려졌다');
        // 출처 글 자리(머리 줄의 글 구간 — 앞뒤 4): 이름 탭 뒤 · 그 줄 머리 이름 구간 다음.
        final borrowRects = <ui.Rect>[];
        for (final l in borrowLabels) {
          final zone = b.headZones.values.expand((z) => z).firstWhere((z) => (z.$1 - (l.x - 4)).abs() < 1e-6);
          borrowRects.add(ui.Rect.fromLTRB(zone.$1, l.y - 3, zone.$2, l.y + 12));
        }
        // (4) 띠 · 점 · 막대 · 동군연합 · 누른 답은 그대로. 통계는 그린 글줄 수만 출처 글만큼.
        expect(b.marks, a.marks, reason: '$label 띠 · 점 · 막대 · 동군연합');
        expect(b.hits.length, a.hits.length);
        for (int i = 0; i < a.hits.length; i++) {
          if (a.hits[i] != b.hits[i]) fail('$label 누른 답 $i번: A「${a.hits[i]}」 · B「${b.hits[i]}」');
        }
        int labelsOf(Shot s) => int.parse(s.stats.firstWhere((v) => v.startsWith('labels ')).split(' ').last);
        expect(labelsOf(b), labelsOf(a) + borrowLabels.length, reason: '$label 그린 글줄 수');
        expect([for (final v in b.stats) if (!v.startsWith('labels ')) v], [for (final v in a.stats) if (!v.startsWith('labels ')) v], reason: '$label 통계');
        // (5) 픽셀: 다른 픽셀은 모두 빌린 칸 상자(±1)와 출처 글 자리 안 — 빌린 칸마다 윗변 줄에 다른 픽셀이 있다(파선).
        final allowed = [for (final r in borrowedRects) r.inflate(1), ...borrowRects];
        final topHit = List<int>.filled(borrowedRects.length, 0);
        var outside = '';
        for (int i = 0; i < a.pixels.length; i += 4) {
          if (a.pixels[i] == b.pixels[i] && a.pixels[i + 1] == b.pixels[i + 1] && a.pixels[i + 2] == b.pixels[i + 2] && a.pixels[i + 3] == b.pixels[i + 3]) continue;
          final p = i ~/ 4, x = p % 1920 + .5, y = p ~/ 1920 + .5;
          if (!allowed.any((r) => r.contains(ui.Offset(x, y)))) outside = outside.isEmpty ? '($x, $y)' : outside;
          for (int k = 0; k < borrowedRects.length; k++) {
            final r = borrowedRects[k];
            if (y.floor() == (r.top - 1).floor() && x >= r.left && x <= r.right) topHit[k]++;
          }
        }
        expect(outside, '', reason: '$label 빌린 칸 · 출처 글 밖에서 바뀐 픽셀');
        expect(topHit, everyElement(greaterThan(0)), reason: '$label 빌린 칸마다 윗변 파선');
      });

      test('(다) $label: 구역 56의 실권 밑줄 · 끝 이름과 그 기간의 지도자 칸(.55)만 새로 그린다 — 실권 단이 같은 기간이면 끝 이름만 빠지고 나머지는 1배 같다', () async {
        final a = await shoot(Vals.old, density: density, groups: groups);
        final d = await shoot(Vals.power, density: density, groups: groups);
        if (density == 2) {
          // 조감: 머리도 띠 안의 단도 없다 — 통째로 같다.
          expect(d.notes['실권밑줄'], isNull);
          expect(d.notes['실권칸'], isNull);
          expectSameShot(a, d, label);
          return;
        }
        final g = SceneView.gutter;
        final bandTop = double.parse(a.marks.firstWhere((m) => m.startsWith('띠 3 ')).split(' ')[2].split(',')[1]);
        // (1) 밑줄: 가람 왕국(띠 3) 머리에 둘 — 실권 기간 그대로(띠 안 3px 안쪽보다 안) · 띠 윗변 + 11 · 2px · 남의 실권은 쥔 쪽 색 80% + 먹, 제 안의 실권자는 먹(그림판 먹 단계 85).
        final y = (bandTop + BandLayer.powerTop).floor();
        String hex6(int argb) => (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
        final lineOther = mixSrgb(0xff000000 | powerColor, Look.ink, BandLayer.powerMix);
        final spans = [(g + 600.0, g + 1000.0, lineOther), (g + 1100.0, g + 1400.0, CanvasInk.k85)];
        expect(d.notes['실권밑줄'], [for (final (l, r, ink) in spans) '3 ${(l * 10).round()},${y * 10},${((r - l) * 10).round()} ${hex6(ink)}'], reason: '$label 밑줄');
        // (2) 끝 이름: 밑줄 오른쪽 끝 − 3에 오른쪽 맞춤 · 글줄 가운데 = 띠 윗변 + 6.5. 단체를 켜면 남의 실권 기간에 실권 단 칸(92)이 그려져 그 이름이 빠진다(밑줄은 남음).
        final nameLabels = [for (final l in d.labels) if (l.kind == 'powerName') l];
        expect([for (final l in nameLabels) l.text], groups ? [powerOwn] : [powerHolder, powerOwn], reason: '$label 끝 이름');
        final nameRects = <ui.Rect>[];
        for (final l in nameLabels) {
          final zone = d.headZones[2]!.firstWhere((z) => (z.$1 - (l.x - 4)).abs() < 1e-6);
          expect(zone.$2 - 4, closeTo((l.text == powerHolder ? g + 1000 : g + 1400) - 3, .01), reason: '$label ${l.text}의 오른쪽 끝');
          expect(l.y, closeTo(bandTop + BandLayer.powerNameMid - BandLayer.powerNameLook.size * .6, .01));
          nameRects.add(ui.Rect.fromLTRB(zone.$1, l.y - 3, zone.$2, l.y + 12));
        }
        final nameInk = {powerHolder: mixSrgb(0xff000000 | powerColor, Look.ink, BandLayer.powerNameMix), powerOwn: CanvasInk.k85};
        expect(d.notes['실권이름'] ?? const <String>[], [for (final l in nameLabels) '3 ${(l.x * 10).round()} ${hex6(nameInk[l.text]!)} ${l.text}'], reason: '$label 끝 이름의 자리 · 빛깔');
        // (3) 지도자 칸: 띠 3(줄 2)의 지도자 칸 가운데 두 기간과 1px 넘게 겹치는 것만 .55(맞닿은 칸 — 80의 끝 = 600 · 82의 시작 = 1000 — 은 아님).
        final cellsA = a.notes['칸'] ?? const <String>[], lightA = a.notes['칸밝기'] ?? const <String>[], lightD = d.notes['칸밝기'] ?? const <String>[];
        expect(lightD.length, lightA.length);
        final ousted = <String>[];
        final oustedRects = <ui.Rect>[];
        for (int i = 0; i < cellsA.length; i++) {
          final (head, box) = noteParts(cellsA[i]);
          final l = box[0] / 10, r = (box[0] + box[2]) / 10;
          if (!head.startsWith('1:2:') || !spans.any((s) => math.min(r, s.$2) - math.max(l, s.$1) > 1)) {
            expect(lightD[i], lightA[i], reason: '$label 실권 밖 칸의 밝기 $i');
            continue;
          }
          final (_, va) = noteParts(lightA[i]);
          final (_, vd) = noteParts(lightD[i]);
          expect(vd[0], closeTo(va[0] * StripLayer.oustedAlpha, 1), reason: '$label 실권 기간의 칸 $head 왼쪽 밝기');
          expect(vd[1], closeTo(va[1] * StripLayer.oustedAlpha, 1), reason: '$label 실권 기간의 칸 $head 오른쪽 밝기');
          ousted.add(cellsA[i]);
          oustedRects.add(ui.Rect.fromLTWH(box[0] / 10, box[1] / 10, box[2] / 10, box[3] / 10));
        }
        expect(d.notes['실권칸'] ?? const <String>[], ousted, reason: '$label 옅어진 칸');
        if (density <= 0) expect(ousted.length, 2, reason: '$label 어린 임금(600 ~ 1000) · 늦은 임금(1000 ~ 1500 — 제 안의 실권자와 겹침)');
        // (4) 기록 열쇠: '실권밑줄' · '실권이름' · '실권칸'이 더해지고, '칸밝기' 말고는 글 그대로.
        expect(d.notes.keys.toSet(), {...a.notes.keys, '실권밑줄', if (nameLabels.isNotEmpty) '실권이름', if (ousted.isNotEmpty) '실권칸'}, reason: '$label 기록 열쇠');
        for (final key in a.notes.keys) {
          if (key != '칸밝기') expect(d.notes[key], a.notes[key], reason: '$label 기록 \'$key\'');
        }
        // (5) 이름: 끝 이름이 더해지고, 옅어진 칸 안의 칸 이름만 짙기 .55배 — 자리 · 글은 그대로.
        final rest = [for (final l in d.labels) if (l.kind != 'powerName') l];
        expect(rest.length, a.labels.length, reason: '$label 이름 수');
        for (int i = 0; i < rest.length; i++) {
          final x = a.labels[i], z = rest[i];
          expect((z.kind, z.text, r1(z.x), r1(z.y)), (x.kind, x.text, r1(x.x), r1(x.y)), reason: '$label 이름 $i');
          if (z.alpha == x.alpha) continue;
          expect(z.kind, 'cell', reason: '$label 짙기가 바뀐 이름은 칸 이름뿐: ${Shot.text(z)}');
          expect(z.alpha, closeTo(x.alpha * StripLayer.oustedAlpha, 1e-9));
          expect(oustedRects.any((r) => z.x >= r.left - .5 && z.x <= r.right && z.y >= r.top - 2 && z.y <= r.bottom), isTrue, reason: '$label 옅어진 칸 안의 이름: ${Shot.text(z)}');
        }
        // (6) 띠 · 점 · 막대 · 동군연합 · 누른 답은 그대로. 통계는 그린 글줄 수만 끝 이름만큼 · 도형 수만 밑줄만큼.
        expect(d.marks, a.marks, reason: '$label 띠 · 점 · 막대 · 동군연합');
        expect(d.hits.length, a.hits.length);
        for (int i = 0; i < a.hits.length; i++) {
          if (a.hits[i] != d.hits[i]) fail('$label 누른 답 $i번: A「${a.hits[i]}」 · D「${d.hits[i]}」');
        }
        int statOf(Shot s, String key) => int.parse(s.stats.firstWhere((v) => v.startsWith('$key ')).split(' ').last);
        expect(statOf(d, 'labels'), statOf(a, 'labels') + nameLabels.length, reason: '$label 그린 글줄 수');
        expect(statOf(d, 'shapes'), statOf(a, 'shapes') + spans.length, reason: '$label 도형 수');
        bool counted(String v) => v.startsWith('labels ') || v.startsWith('shapes ');
        expect([for (final v in d.stats) if (!counted(v)) v], [for (final v in a.stats) if (!counted(v)) v], reason: '$label 통계');
        // (7) 픽셀: 다른 픽셀은 모두 밑줄 · 끝 이름 자리 · 옅어진 칸 상자(±1) 안 — 밑줄 두 줄은 그 빛깔 그대로(흐림 없음).
        final lineRects = [for (final (l, r, _) in spans) ui.Rect.fromLTRB(l, y.toDouble(), r, y + BandLayer.powerHeight)];
        final allowed = [...lineRects, ...nameRects, for (final r in oustedRects) r.inflate(1)];
        var outside = '';
        for (int i = 0; i < a.pixels.length; i += 4) {
          if (a.pixels[i] == d.pixels[i] && a.pixels[i + 1] == d.pixels[i + 1] && a.pixels[i + 2] == d.pixels[i + 2] && a.pixels[i + 3] == d.pixels[i + 3]) continue;
          final p = i ~/ 4, x = p % 1920 + .5, py = p ~/ 1920 + .5;
          if (!allowed.any((r) => r.contains(ui.Offset(x, py)))) outside = outside.isEmpty ? '($x, $py)' : outside;
        }
        expect(outside, '', reason: '$label 밑줄 · 끝 이름 · 옅어진 칸 밖에서 바뀐 픽셀');
        for (final (l, r, ink) in spans) {
          for (final dy in const [0, 1]) {
            for (final x in [l + 2, (l + r) / 2, r - 2]) {
              final at = ((y + dy) * 1920 + x.floor()) * 4;
              expect(hex6(d.pixels[at] << 16 | d.pixels[at + 1] << 8 | d.pixels[at + 2]), hex6(ink), reason: '$label 밑줄 ($x, ${y + dy})');
            }
          }
        }
      });
    }
  }

  test("'칸이음' 고쳐 쓰기는 27비트와 배열 자리만 건드린다", () {
    final b = Tile.decode(tileOf(Vals.borrow));
    final i = [for (int k = 0; k < b.cellCount; k++) b.cellId[k]].indexOf(81);
    final style = b.cellStyle[i];
    expect(normalJoin('1:2:0 jl=true jr=true zl=false zr=false st=$style seq=1 a=1.0 b=2.0 i=$i', b),
        '1:2:0 jl=true jr=true zl=false zr=false st=${style & ~Schema4.borrowed} seq=1 a=1.0 b=2.0 id=81');
    expect(style & ~Schema4.borrowed & CellStyle.nominalLeader, isNonZero, reason: '명목 비트(29)는 남는다');
    // 종류 8(단체 단)의 갈래 5 · 7은 27비트가 서 있어도 빌림이 아니라 그대로 둔다.
    final group = CellStyle.groupOne << 27 | 1 << 15;
    expect(group & Schema4.borrowed, isNonZero);
    expect(normalJoin('8:2:2 jl=false jr=false zl=false zr=false st=$group seq=0 a=1.0 b=2.0 i=0', b),
        '8:2:2 jl=false jr=false zl=false zr=false st=$group seq=0 a=1.0 b=2.0 id=${b.cellId[0]}');
  });
}
