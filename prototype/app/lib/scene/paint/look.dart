import 'dart:ui' as ui;

import '../text_paragraph.dart';
import 'ink.dart';

// 그리기의 값. 웹 연표(css/common.css · js/timeline.js)에서 옮겼다. 층마다의 자세한 값은 그 층의 파일에 둔다.
// 바탕 · 글자 · 선은 HistoryArchive의 토큰이다(감독 결정 2026-10-13 · B안 — css/common.css의 그림판 토큰과 같은 값): 흰 바탕 · 검은 잉크,
// paper2 · 3은 바탕 위 잉크 4% · 8%, muted는 60%, line은 20%. 나라 색은 자료라 그대로이고 섞이는 바탕만 흰색이 된다.
abstract final class Look {
  static const paper = 0xffffffff, paper2 = 0xfff5f5f5, paper3 = 0xffebebeb, line = 0xffcccccc, ink = 0xff000000, muted = 0xff666666, accent = 0xff000000;
  static const text2 = 0xff666666;

  /// 그림판의 바탕(감독 건의 2026-10-15 1번 — 흰 사건 칸이 바탕과 갈려 보이게 흰색이 아닌 바탕 · 고르기 판에서 '나' 먹 6%).
  /// 흰 종이([paper])는 띠의 사건 칸 · 꼬리표 · 이름표의 몫이고, 왼쪽 칸 · 날짜 줄도 종이 그대로다.
  static const ground = 0xfff0f0f0;

  /// 세로 눈금의 옅은 점선(css --grid-line — 잉크 20%). 한 칸 걸러 깔리던 바탕(--grid-band)은 없앴다(투명).
  static const gridLine = 0x33000000, gridBand = 0x00000000;
  static const bandRadius = 9.0, fuzzyFade = 44.0, tabInset = 6.0, cellInset = 4.0;

  /// 간지 탭(묶음 3 · 1번 L — 지금 연표 js/timeline.js의 TAB · G.radius): 탭의 발은 띠의 둥근 모서리(줄 안의 띠 10px) 위에 두지 않고
  /// 모서리가 끝나 윗변이 평평해지는 곳부터([tabFoot]), 오른쪽 평지 끝을 넘지 않는다. 어깨는 S자 7px(첫 글자만 적는 짧은 탭 4px),
  /// 온 이름 탭은 예전 필름 탭보다 [tabExt]만큼 넓다(한쪽 6 — 어깨 7 + 안 여백 6 = 13 · 예전 안 여백 7). 뒤 장의 탭 사이 틈 [tabGap].
  static const tabFoot = 10.0, tabShoulder = 7.0, tabShoulderShort = 4.0, tabExt = 12.0, tabGap = 4.0;

  // 그림판 글꼴(지도자 · 내각 · 왕조 · 기관 · 사건 · 막대)의 먹은 그림판 먹 여섯 단계([CanvasInk] — 4단계 G5 #8 먹 가)로 낸다.
  // 옛 값(먹 100 · 60 · 70 · 72)을 [CanvasInk.of]에 주어 스위치 `ink`를 끄면 옛 값 그대로라 const 대신 final이다.
  static final leader = TextLook(11, ui.FontWeight.w600, CanvasInk.of(ink));
  static final cabinet = TextLook(10, ui.FontWeight.w400, CanvasInk.of(muted));
  static final dynasty = TextLook(10, ui.FontWeight.w600, CanvasInk.of(0xb3000000));
  static final organ = TextLook(10, ui.FontWeight.w400, CanvasInk.of(muted));

  // 틀 글꼴(트랙 · 날짜 칸의 해 · 시대 · 간지)은 틀 먹 그대로.
  static const track = TextLook(12.5, ui.FontWeight.w700, ink);
  static const year = TextLook(11, ui.FontWeight.w500, muted);
  static const epoch = TextLook(10.5, ui.FontWeight.w600, muted);
  static const ganji = TextLook(10, ui.FontWeight.w400, muted);
  // 사건 이름: 12px, 중요도 3은 굵게 · 1은 가늘고 옅게 — 먹은 셋 모두 85(고르기 판 '글 85 ← 100 · 85 · 80 · 75 · 72').
  static final event3 = TextLook(12, ui.FontWeight.w700, CanvasInk.of(ink));
  static final event2 = TextLook(12, ui.FontWeight.w500, CanvasInk.of(ink));
  static final event1 = TextLook(12, ui.FontWeight.w400, CanvasInk.of(0xff474747));
  static final bar = TextLook(10, ui.FontWeight.w500, CanvasInk.of(ink));

  static TextLook event(int importance) => importance >= 3 ? event3 : (importance == 2 ? event2 : event1);

  static int mix(int from, int to, double t) {
    int channel(int shift) => (((from >> shift) & 0xff) + ((((to >> shift) & 0xff) - ((from >> shift) & 0xff)) * t)).round() & 0xff;
    return 0xff000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
  }
}
