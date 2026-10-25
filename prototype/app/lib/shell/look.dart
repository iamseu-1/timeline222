import 'package:flutter/material.dart';
import '../motion.dart';

import '../scene/fonts.dart';

// 앱 틀(맨 위 줄 · 확대 단추 · 상세 칸 …)의 색 · 치수. 모양은 HistoryArchive(위키 아카이브 앱)의 디자인을 따른다 — 감독 결정 2026-10-13 · B안:
// 틀과 그림판의 바탕 · 선 · 글자는 그 앱의 토큰으로, 나라 색과 띠의 둥근 네모는 자료라 그대로. 값은 웹 연표의 css/common.css 맨 위 토큰과
// css/common.css · css/viewer.css 끝의 'HistoryArchive 통일' 절과 같고, 자리와 크기는 그 화면을 1배로 찍은 것에 맞췄다.
abstract final class Ui {
  /// HistoryArchive의 토큰(그 저장소 packages/design_system/lib/src/tokens.dart): 바탕 하나 · 잉크의 불투명도 다섯 단계 · 링크 파랑.
  /// 읽는 글자는 [ink]와 [ink60]만 · [ink40]은 꺼진 글자와 아이콘 · [ink20]은 선 · 눌림 · 창 뒤 깔개 · [ink8]은 올림.
  static const paper = Color(0xffffffff), ink = Color(0xff000000), ink60 = Color(0x99000000), ink40 = Color(0x66000000), ink20 = Color(0x33000000), ink8 = Color(0x14000000);

  /// 반전 채움([ink] 바탕) 위의 보조 글자 · 링크.
  static const paper60 = Color(0x99ffffff), link = Color(0xff0275d8);

  /// 감독 선택: 제목·본문·연표는 프리텐다드, 제목의 굵기는 각 부품에서 유지한다.
  static const title = sceneTitleFontFamily, titleFallback = sceneFontFallback;
  static const serif = sceneFontFamily, serifFallback = sceneFontFallback;

  /// 예전부터 쓰던 이름 — 값만 위 토큰으로. 강조([accent])는 색이 아니라 반전 채움이다.
  static const bg = paper, surface = paper, surface2 = ink8, glass = paper;

  /// [surface2]를 paper 위에 얹은 불투명한 값 — 다른 색과 섞는 셈(`mixSrgb`)처럼 투명도를 못 쓰는 자리에 쓴다.
  static const surface2Solid = Color(0xffebebeb);
  static const line = ink20, lineStrong = ink20;
  static const text = ink, text2 = ink60, text3 = ink60;
  static const accent = ink, accentSoft = ink8;

  /// 미정 · 연대 폭 안내 · 간지 줄 · ★(중요도 3) — 상태는 색 없이 잉크로 알린다(css의 `--warn`).
  /// [warnRgb]는 같은 색의 0xRRGGBB 정수(결과 줄의 `color` 칸처럼 수로 받는 자리).
  static const warn = ink, warnRgb = 0x000000;

  /// 그림자는 쓰지 않는다 — 떠 있는 면은 1px 선 하나(css의 0 0 0 1px var(--line)). 이름 둘은 예전 그대로 둔다.
  static const shadowSmall = [BoxShadow(color: line, spreadRadius: 1)];
  static const shadow = [BoxShadow(color: line, spreadRadius: 1)];

  /// 단추 · 칸의 둥근 정도 6 · 그 안쪽 4 · 시트 · 메뉴 · 창 12.
  static const controlRadius = 6.0, innerRadius = 4.0, menuRadius = 12.0;

  /// 맨 위 줄의 높이. 그 아래가 연표다(연표의 맨 위에는 1px 선).
  static const top = 60.0;

  /// 상세 칸: 연표 영역 오른쪽에 붙은 폭 380의 칸(왼쪽 1px 선 · 가장자리 틈 없음). 열려 있으면 그만큼([detailCover]) 연표를 가리고,
  /// 확대 단추는 380 + 16으로 비킨다. [detailSlide]는 열릴 때 미끄러져 들어오는 거리.
  static const detailWidth = 380.0, detailInset = 0.0, detailCover = 380.0, detailSlide = 12.0, zoomRightOpen = 396.0, zoomRight = 16.0, zoomBottom = 16.0;

  /// 상세 칸 · 메뉴의 바탕(불투명한 [paper]) · 상세 칸은 모서리와 아래 틈이 없다.
  static const detailGlass = paper, detailRadius = 0.0, detailBottom = 0.0;

  /// 맨 위 줄(.dock): 화면 폭 · 높이 60 · 왼쪽은 보는 시기 글(줄 이름 칸과 같은 폭 `SceneView.gutterNow` — 240 · 휴대폰 160 · 안쪽 여백 왼 16 오 12) · 부품 사이 8 · 오른쪽 여백 16.
  static const dockLeft = 0.0, dockTop = 0.0, dockHeight = top, dockRadius = 0.0, dockGap = 8.0;
  static const dockPadding = EdgeInsets.only(right: 16), dockRangePadding = EdgeInsets.only(left: 16, right: 12);

  /// 검색 칸: 높이 44 · 폭은 남는 만큼(읽는 폭 720까지) · ink20 테두리(초점은 ink) · 둥근 6 · 돋보기 그림은 왼쪽 13에 15×15(글은 왼쪽 40부터).
  static const searchWidth = 720.0, searchHeight = 44.0, searchRadius = controlRadius, searchIcon = Color(0xff86868b);

  /// 검색 결과 목록: 검색 칸의 왼쪽 아래에 붙어 아래 +8 · 폭 460 · 둥근 12.
  static const resultsOffset = Offset(0, 8), resultsWidth = 460.0, resultsRadius = menuRadius, resultsMaxHeight = 460.0;

  /// 맨 위 줄의 단추: 높이 36 · 둥근 6 · 좌우 여백 12. 확대 묶음 안의 단추는 32 · 둥근 4.
  static const buttonHeight = 36.0, buttonRadius = controlRadius, buttonPadding = EdgeInsets.symmetric(horizontal: 12);

  /// 맨 위 줄의 기호 단추(건의 8의 1번 꼴 A): 36×36 · 선 아이콘 18 · 단추 사이 4 · 렌즈를 켠 동안의 주제 색 점 지름 7.
  /// 메뉴 줄의 아이콘은 16(먹 60%) · 글과 사이 9.
  static const dockIcon = 18.0, dockIconGap = 4.0, dockDot = 7.0, menuIcon = 16.0, menuIconGap = 9.0;

  /// 확대 단추 묶음 40×142: 안쪽 여백 4 · 단추 32 · 사이 2 · 둥근 6. 배율 알약은 그 왼쪽 8에 선다.
  static const zoomButton = 32.0, zoomGap = 2.0, zoomPad = 4.0, zoomRadius = controlRadius, magGap = 8.0;

  /// 필터 시트: 맨 위 줄 아래(위 60+8 · 왼 16) · 폭 1080까지 · 둥근 12 · 안쪽 여백 16/18.
  static const sheetTop = top + 8, sheetLeft = 16.0, sheetWidth = 1080.0, sheetRadius = menuRadius, sheetPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 16);

  /// 맨 위 줄 아래 작은 알약(측정 중 안내): 위 60+8 · 왼 12.
  static const noticeTop = top + 8, noticeLeft = 12.0;

  /// 유리 바탕 뒤의 흐림 — 유리 창이 없어졌으므로 어디서도 흐리지 않는다(0이면 건너뛴다).
  static const blur = 0.0, blurWide = 0.0, blurSoft = 0.0, blurLight = 0.0;

  /// 확대 · 축소 단추의 휠 값: 지금 연표의 timeline.zoom(0.6) · zoom(1.6)과 같은 배율(exp(dy × .0018)).
  static const zoomInWheel = -284.0, zoomOutWheel = 261.0;

  /// 상세 창이 미끄러져 뜨는 시간과 확대 단추가 비키는 시간(ms).
  static const detailEnter = Duration(milliseconds: Motion.moveMs), zoomShift = detailEnter;

  static const spring = Cubic(.32, .72, 0, 1), ease = Cubic(.25, .8, .25, 1);
}

/// 보기 폭(분)에 맞는 자세함으로 두 시점을 적는다 — 지금 연표의 spanRange(js/viewer.js)와 같은 규칙:
/// 12년 넘으면 해, 아홉 달 넘으면 달, 나흘 넘으면 날, 그보다 좁으면 시각. 같은 해면 뒤쪽의 겹치는 앞부분은 줄인다.
String rangeLabel(double lo, double hi) {
  const year = 525960.0;
  final span = (hi - lo) / year;
  final precision = span > 12 ? 0 : (span > .75 ? 1 : (span > 4 / 365.25 ? 2 : 3));
  List<String> parts(double minute) {
    final d = DateTime.fromMillisecondsSinceEpoch((minute * 60000).floor(), isUtc: true);
    return [d.year > 0 ? '${d.year}년' : '기원전 ${1 - d.year}년', if (precision >= 1) '${d.month}월', if (precision >= 2) '${d.day}일', if (precision >= 3) '${d.hour}시'];
  }

  final a = parts(lo), b = parts(hi);
  if (a.join(' ') == b.join(' ')) return a.join(' ');
  int same = 0;
  if (precision > 0 && a[0] == b[0]) {
    same = 1;
    while (same < b.length - 1 && a[same] == b[same]) {
      same++;
    }
  }
  return '${a.join(' ')} ~ ${b.sublist(same).join(' ')}';
}

/// 보기 폭(분)을 사람이 읽는 말로 — 지금 연표의 HT.cal.spanText와 같은 규칙: "3,000년" · "4.5년" · "약 3개월" · "12일" · "5시간".
String spanText(double minutes) {
  final span = minutes / 525960;
  if (span >= 10) return '${_thousands(span.round())}년';
  if (span >= 2) return '${span.toStringAsFixed(1)}년';
  final days = span * 365.25;
  if (days >= 60) return '약 ${(days / 30.44).round()}개월';
  if (days >= 2) return '${days.round()}일';
  final hours = (days * 24).round();
  return '${hours < 1 ? 1 : hours}시간';
}

String _thousands(int n) {
  final digits = '$n', out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
