import 'dart:ui' show Color;

import '../scene/color_mix.dart';

// 틀의 시트와 창 여덟(필터 시트 · 검색 결과 · 범례 · 차림표 · DLC 관리 · 승계표 · 단체 계보 · 문서 창)을 서고 꼴로 다시 그릴 때만 쓰는 토큰.
// 감독 고름(2026-10-25 — 계획 4단계 '감독 고름 더' · G5 #9 다듬기 판 `.claude/research/stage4-choose/out/4단계-다듬기-판.html` · git 밖):
//   폴더 탭은 맨 글 12 · 흰 라벨은 상자 뚜껑에만 · 뚜껑 22 · 고른 테 1.5 · 꺼 둔 줄과 칩은 흰 종이 + 먹 25 실선(점선은 대립과 얹은 트랙만) ·
//   먹 여섯(85 · 60 · 45 · 25 · 12 · 4) · 범례에 정통성 상자.
// 수치의 원본은 다듬기 판의 갈래 파일 `.claude/research/stage4-choose/themes/g-sheet-*.js`(git 밖) — 두 작업자 값이 갈린 뚜껑(20 · 22)과
// 고른 테(2 · 1.5)는 감독 고름대로 22 · 1.5로 맞췄다.
// 값은 remake-4 갈래의 그림판 먹 토큰과 같음 — 합칠 때 하나로.
// 앱 틀의 토큰(`look.dart`의 [Ui])과 그림판의 값(`scene/paint/look.dart`)은 고치지 않는다 — 시트를 다시 그린 창만 이 파일을 읽는다.
//
// 먹: 목업 `kit.js`의 `ink(a)` = 흰 종이 위에 검정을 a만큼 섞은 **불투명** 색(sRGB · 반올림)과 같은 값. 겹쳐 그려도 짙어지지 않는다.
// 나라 색 섞임: 그림판(`scene/paint/bands.dart`)과 같은 셈 — 칠은 종이와 `in srgb`, 테는 먹과 `in oklab`, 글은 먹과 `in srgb`.
//   목업의 먹은 #1b1a19이지만 앱 그림판의 먹은 검정([ink100])이라 앱 그림판을 따른다(꼬리표가 연표의 띠와 같은 빛깔로 읽히게).
abstract final class SheetLook {
  // ---- 먹 여섯 · 종이 ----

  /// 종이(흰)와 먹(검정) — [ink100]은 고른 테에만 쓴다.
  static const paper = Color(0xffffffff), ink100 = Color(0xff000000);

  /// 먹 85 · 60 · 45 · 25 · 12 · 4 — 흰 종이 위의 불투명 색. 읽는 글 85 · 곁글 60 · 옅은 글 · 구멍 · 실 · 켠 테 45 ·
  /// 상자 테 · 끈 테 25 · 뚜껑 밑선 · 안쪽 겹선 · 가로대 12 · 뚜껑 · 폴더 칠 4.
  static const ink85 = Color(0xff262626), ink60 = Color(0xff666666), ink45 = Color(0xff8c8c8c), ink25 = Color(0xffbfbfbf), ink12 = Color(0xffe0e0e0), ink4 = Color(0xfff5f5f5);

  /// 먹 여섯의 짙기(차례대로 [ink85] ~ [ink4]).
  static const inkSteps = <double>[.85, .60, .45, .25, .12, .04];

  /// 짙기 a의 먹 — 흰 종이 위에 검정을 a만큼(`color-mix(in srgb, 검정 a, 흰)`). [ink85] ~ [ink4]는 이 값을 미리 적은 것이다.
  static Color inkOf(double a) => Color(mixSrgb(0xff000000, 0xffffffff, a));

  // ---- 고른 테 ----

  /// 고른 것의 테: 먹 100 · 굵기 1.5(감독 고름 — 다듬기 판의 2와 1.5 가운데). 바깥 테는 그림판 고른 띠처럼 2 밖 · 모따기 6 · 둥근 끝 14.
  static const pickInk = ink100, pickWidth = 1.5, pickOutset = 2.0, pickChamfer = 6.0, pickRound = 14.0;

  /// 안쪽 고른 테(흰 층 안의 칸 줄 — 검색의 칸 묶음): 안으로 3 · 둥근 3.
  static const pickInset = 3.0, pickInnerRadius = 3.0;

  // ---- 폴더(시트 · 창) ----

  /// 둥근 10 · 칠 먹 4 · 테 먹 25 · 안쪽 겹선(안으로 3 · 둥근 7 · 먹 12).
  static const folderRadius = 10.0, folderInnerInset = 3.0, folderInnerRadius = 7.0;

  /// 어깨 탭 20: 어깨 굽음 8 · 탭 왼쪽(또는 오른쪽) 들임 12 · 글 앞뒤 14 · 맨 글 12 굵게 먹 85 + 수 12 보통 먹 45(사이 5).
  static const folderTab = 20.0, folderTabShoulder = 8.0, folderTabInset = 12.0, folderTabPad = 14.0, folderTabText = 12.0, folderTabCountGap = 5.0;

  /// 오른쪽 닫기 탭: 폭 44 · ✕ 14 먹 60.
  static const folderCloseTab = 44.0, folderCloseIcon = 14.0;

  /// 흰 둘레 6(둥근 16) — 띄운 시트가 그림판의 글 · 선과 맞닿지 않게(그림자 대신 종이).
  static const folderRim = 6.0, folderRimRadius = 16.0;

  /// 몸통 윗변 3 위의 뒷장 금(양 끝 18 들임 · 먹 12 — 나라 폴더는 제 색 35% + 종이).
  static const folderBackRise = 3.0, folderBackInset = 18.0;

  // ---- 상자(묶음) ----

  /// 모따기 6 · 테 먹 25 · 몸 흰 종이 · 뚜껑 22(먹 4 + 밑선 먹 12) · 안쪽 들임 10(뚜껑 라벨 · 칩 · 목록 줄의 왼쪽 끝이 한 줄).
  static const boxChamfer = 6.0, boxLid = 22.0, boxInset = 10.0;

  /// 뚜껑 안 흰 라벨 16(위 3 · 둥근 2 · 테 먹 45): 글 11 굵게 먹 85 · 앞뒤 6 · 수 11 보통 먹 45(라벨 뒤 6) · 오른쪽 안내 글 11 보통 먹 45.
  static const boxLabel = 16.0, boxLabelTop = 3.0, boxLabelRadius = 2.0, boxLabelText = 11.0, boxLabelPad = 6.0, boxCountGap = 6.0;

  // ---- 꼬리표 ----

  /// 다스림 = 왼쪽 두 귀 모따기 5 · 영토 밖 = 왼쪽 둥근 끝(반지름 12까지) · 무리 = 직각(테 없음). 오른쪽은 늘 직각.
  static const tagChamfer = 5.0, tagRound = 12.0;

  /// 구멍: 반지름 2.5 · 왼쪽 테에서 7(둥근 끝은 9 — 7이면 구멍 테가 둥근 끝에 닿음) · 윗테에서 6 · 종이 칠 · 테 먹 45.
  static const holeRadius = 2.5, holeLeft = 7.0, holeLeftRound = 9.0, holeTop = 6.0;

  /// 꼬리 마름모: 반 대각선 3 · 오른쪽 테에서 7 · 구멍과 같은 높이 · 제 색 60% + 먹(oklab).
  static const diamondHalf = 3.0, diamondRight = 7.0;

  // ---- 이름 종이 · 칩 · 열쇠표 · 실 ----

  /// 흰 이름 종이(단추 · 고르는 칸 · 사슬 고리): 왼쪽 모따기 3 · 테 먹 45.
  static const paperChamfer = 3.0;

  /// 칩 키 24 · 글 12 굵게 · 글 앞 15(둥근 끝 17) · 글 뒤 10 · 칩 사이 6.
  static const chip = 24.0, chipText = 12.0, chipLead = 15.0, chipLeadRound = 17.0, chipTail = 10.0, chipGap = 6.0;

  /// 사건 점 칩: 점 반지름 3(끔 = 빈 점 2.5) · 점 가운데 12 · 글 앞 21.
  static const dotRadius = 3.0, dotOffRadius = 2.5, dotCenter = 12.0, dotLead = 21.0;

  /// 폴더 칩: 둥근 6 · 안쪽 겹선(안으로 2 · 둥근 4) · 폴더 그림 13(왼쪽 10) · 글 앞 29.
  static const scopeRadius = 6.0, scopeInnerRadius = 4.0, scopeIcon = 13.0, scopeIconLeft = 10.0, scopeLead = 29.0;

  /// 흰 이름 종이 단추: 글 앞뒤 11 · 고르는 칸: 제목 뒤 8 · 값 앞 10 · 값 뒤 34(▾ 14가 오른쪽 21에) · 사슬: 고리 사이 실 10.
  static const buttonPad = 11.0, selectTitleGap = 8.0, selectLead = 10.0, selectTail = 34.0, selectIcon = 14.0, selectIconRight = 21.0, chainLink = 10.0;

  /// 열쇠표 12: 둥근 끝 6 · 구멍 1.5(왼쪽 6) · 글 8.5(앞 11 · 뒤 6) · 꼬리표 윗변에서 45° 실(먹 45).
  static const keyTag = 12.0, keyRound = 6.0, keyHole = 1.5, keyHoleLeft = 6.0, keyText = 8.5, keyLead = 11.0, keyTail = 6.0;

  /// 실: 먹 45 · 1px · 매듭(뚜껑 밑선 · 가로대 위) 반지름 1.5 · 실은 구멍 위 3에서 멎는다(구멍 테 안으로 들지 않게).
  static const threadInk = ink45, threadWidth = 1.0, knotRadius = 1.5, threadStop = 3.0;

  // ---- 실에 꿴 목록(검색 결과 · 차림표 — 목업 g-sheet-search `drawSearch` · g-sheet-menu `drawMenu`) ----

  /// 목록 시트의 폴더 안쪽 12 · 상자 사이 8 · 폴더 맨 위 안내 글(12) 줄 18 + 아래 틈 12.
  static const listPad = 12.0, listBoxGap = 8.0, noteLine = 18.0, noteGap = 12.0, noteText = 12.0;

  /// 검색 결과: 폭 480 · 줄 꼬리표 24 · 줄 사이 틈 6 + 가로대 1 + 6(가로대는 틈 가운데) · 뚜껑 밑선에서 첫 줄까지 6 · 끝 줄 아래 9.
  static const searchWidth = 480.0, searchRow = 24.0, searchRowGap = 13.0, searchTop = 6.0, searchBottom = 9.0;

  /// 검색 줄의 글: 이름 13 굵게 · 곁글 12(이름 뒤 8) · 때 12(오른쪽 끝 10 안) — 한 바탕선. 이름은 구멍 뒤 18(다스림 · 영토 밖 모두),
  /// 점 · 마름모 · 문서 그림은 왼쪽 24 가운데이고 그 뒤 이름 34. 맨 위 이동 줄(흰 종이)의 글은 앞 10.
  static const searchName = 13.0, searchSub = 12.0, searchSubGap = 8.0, searchWhenRight = 10.0, searchLead = 18.0, searchMark = 24.0, searchMarkLead = 34.0, searchPaperLead = 10.0;

  /// 검색 줄 앞의 사건 점(반지름 3) · 조약 마름모(반 대각선 4) · 문서 그림 14.
  static const searchDot = 3.0, searchDiamond = 4.0, searchDocIcon = 14.0;

  /// 칸 묶음: 주인 꼬리표 머리 24 아래 흰 층을 칸마다 한 줄 26(사이 금 먹 25) · 머리 글 12(주인 굵게 + '· 칸 갈래' 사이 5).
  static const cellHead = 24.0, cellFloor = 26.0, cellHeadText = 12.0, cellHeadGap = 5.0;

  /// 차림표: 폴더 폭 356(… 단추 — 탭이 오른쪽 · 단추 밑 12) · 줄 꼬리표 24 · 사이 4 · 작은 묶음 틈 6 ·
  /// 뚜껑 밑선에서 첫 줄까지 8 · 끝 줄 아래 10 · 아이콘 15 먹 60(왼쪽 17) · 이름 13(왼쪽 40) · 단축키 11 먹 45(오른쪽 11).
  static const menuWidth = 356.0, menuBelow = 12.0, menuRow = 24.0, menuRowGap = 4.0, menuSubGap = 6.0, menuTop = 8.0, menuBottom = 10.0;
  static const menuIcon = 15.0, menuIconLeft = 17.0, menuLabelLeft = 40.0, menuLabel = 13.0, menuKey = 11.0, menuKeyRight = 11.0;

  // ---- DLC 관리 창(목업 g-sheet-menu `drawDlc` — 다듬기 판 sm-dlc) ----

  /// 폴더 폭 1180(가운데 · 화면 − 24 안) · 폴더 안쪽 18(위 14 · 아래 10) · 위 칸 키 28(찾기 240 · 돋보기 14가 왼쪽 10 · 단추 사이 6 ·
  /// 닫기 앞 가름 금 먹 25 — 앞뒤 14 · 위아래 4 들임) · 위 칸 아래 · 아래 줄 위 틈 14 · 자세히 폭 352 · 목록과 자세히 사이 16 · 상자 사이 10 ·
  /// 폭이 [dlcWide]보다 좁으면 자세히가 목록 밑으로(휴대폰 · 좁은 창) · [dlcTwoLines]보다 좁으면 위 칸이 두 줄.
  static const dlcWidth = 1180.0, dlcPad = 18.0, dlcPadTop = 14.0, dlcPadBottom = 10.0, dlcTop = 28.0, dlcFind = 240.0, dlcFindIcon = 14.0, dlcFindLead = 10.0;
  static const dlcGap = 14.0, dlcDetail = 352.0, dlcColumnGap = 16.0, dlcBoxGap = 10.0, dlcWide = 720.0, dlcTwoLines = 640.0;

  /// 줄 꼬리표 50 · 줄 사이 6 · 첫 줄 가운데 17(차례 번호 11 굵게 먹 45 — 가운데 21 · 이름 14 굵게 — 30부터 · 판 11 먹 45 — 이름 뒤 7 ·
  /// '원본 없음' 흰 종이 18 — 판 뒤 9 · 글 11 굵게 먹 60 · 앞뒤 9) · 둘째 줄 가운데 36(트랙 작은 꼬리표 14 · 사이 4 · 글 8.5 굵게 앞 10 · 뒤 5 ·
  /// 담긴 것 12는 꼬리표 뒤 6) · 끄기 · 삭제 단추는 오른쪽 12 안 · 사이 6. 켠 줄 = 흰 종이 · 테 먹 45 / 꺼 둔 줄 = 흰 종이 · 테 먹 25 · 글 옅게.
  static const dlcRow = 50.0, dlcRowGap = 6.0, dlcLine1 = 17.0, dlcLine2 = 36.0, dlcOrder = 21.0, dlcLead = 30.0, dlcName = 14.0, dlcVersion = 11.0, dlcVersionGap = 7.0;
  static const dlcBadge = 18.0, dlcBadgeGap = 9.0, dlcBadgeText = 11.0, dlcBadgePad = 9.0;
  static const dlcMini = 14.0, dlcMiniChamfer = 3.0, dlcMiniHole = 1.5, dlcMiniText = 8.5, dlcMiniLead = 10.0, dlcMiniTail = 5.0, dlcMiniGap = 4.0;
  static const dlcContents = 12.0, dlcContentsGap = 6.0, dlcButtonGap = 6.0, dlcButtonRight = 12.0;

  /// 얹은 트랙의 점선 — 작은 꼬리표 '2 2' · 표지와 자세히의 트랙 줄 '3 2'.
  static const dlcSharedDash = <double>[2, 2], dlcSharedDashWide = <double>[3, 2];

  /// 자세히: 안쪽 12(위 10 · 아래 12) · 표지(둥근 4 · 칠 먹 4 · 테 먹 12 · 꼬리표 24 · 사이 8 · 왼쪽 18 · 위아래 18 · 넷까지 ·
  /// 길이 = (폭 − 36) × (.42 + .58 × 줄 수 / 가장 많은 줄 수) · 글 9 굵게 — 꼬리표 왼쪽 15) · 표지 아래 16 · 이름 17 굵게 + 판 12 먹 45 ·
  /// 마디 = 금 먹 12 → 제목 12 굵게 먹 60(금에서 가운데 16) → 글 13 먹 85(줄 20 — 첫 줄 가운데가 금에서 35) · 마디 사이 17 ·
  /// 트랙 줄 꼬리표 22(금에서 30 · 사이 6 · 이름 12 굵게 앞 15 · 줄 수 · 주인 11 오른쪽 9) · 맨 아래 번호 11 먹 45.
  static const dlcDetailPad = 12.0, dlcDetailTop = 10.0, dlcCoverRadius = 4.0, dlcCoverTag = 24.0, dlcCoverGap = 8.0, dlcCoverLead = 18.0, dlcCoverText = 9.0, dlcCoverTextLeft = 15.0;
  static const dlcCoverMax = 4, dlcCoverEmpty = 72.0, dlcCoverBelow = 16.0;
  static const dlcTitle = 17.0, dlcTitleVersion = 12.0, dlcTitleBelow = 12.0, dlcSection = 12.0, dlcBody = 13.0, dlcBodyLine = 20.0, dlcSectionGap = 17.0;
  static const dlcTrack = 22.0, dlcTrackGap = 6.0, dlcTrackText = 12.0, dlcTrackNote = 11.0, dlcTrackLead = 15.0, dlcTrackTail = 9.0, dlcIdText = 11.0;

  // ---- 나라 색 섞임 ----

  /// 꼬리표 칠: 제 색 24% + 종이(in srgb — 그림판 띠 바탕과 같은 셈).
  static Color tagFill(Color c) => Color(mixSrgb(c.toARGB32(), 0xffffffff, .24));

  /// 꼬리표 테: 제 색 84% + 먹(in oklab).
  static Color tagEdge(Color c) => Color(mixOklab(c.toARGB32(), 0xff000000, .84));

  /// 꼬리표 머리의 이름 글(탭 글): 제 색 22% + 먹(in srgb — 그림판 탭 글과 같은 셈).
  static Color tagInk(Color c) => Color(mixSrgb(c.toARGB32(), 0xff000000, .22));

  /// 꼬리표의 곁글(해 · 직위 · 줄 수): 제 색 45% + 먹(in srgb).
  static Color nameInk(Color c) => Color(mixSrgb(c.toARGB32(), 0xff000000, .45));

  /// 꼬리 마름모 · 조약 마름모: 제 색 60% + 먹(in oklab).
  static Color diamondInk(Color c) => Color(mixOklab(c.toARGB32(), 0xff000000, .60));

  /// 나라 시트(승계표 · 단체 계보 · 문서 창의 폴더 · 폴더 칩) 칠: 제 색 9% + 종이(in srgb).
  static Color folderFill(Color c) => Color(mixSrgb(c.toARGB32(), 0xffffffff, .09));

  /// 나라 시트 테: 제 색 55% + 종이(in oklab).
  static Color folderEdge(Color c) => Color(mixOklab(c.toARGB32(), 0xffffffff, .55));

  /// 나라 시트의 탭 글: 제 색 25% + 먹(in srgb).
  static Color folderInk(Color c) => Color(mixSrgb(c.toARGB32(), 0xff000000, .25));

  /// 나라 시트의 뒷장 금: 제 색 35% + 종이(in oklab).
  static Color folderBack(Color c) => Color(mixOklab(c.toARGB32(), 0xffffffff, .35));
}
