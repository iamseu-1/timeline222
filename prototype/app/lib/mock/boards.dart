import 'dart:ui' as ui;

import 'render.dart';
import 'themes/s4_common.dart';
import 'themes/t_common.dart';

// 판 목록 — 판마다 그 판에 실린 갈래(JS 갈래 파일이 window.S4.register로 등록한 차례 그대로)와 2배 조각의 자리.
// JS의 갈래 목록 window.THEMES는 themes.js(sha256 6c9f15e06631)가 비워 두고 갈래 파일이 더한다 — 이 파일이 그 목록이다.
// 판 s4(조각 ④ 결정 판 — .claude/research/stage2/mock/board-s4.src.html)는 갈래 파일 아홉의 등록을 옮김(opt는 글자 그대로):
//   themes/s4-2-ga.js(sha256 5e4737bc0a39) · s4-2-na.js(22d91dddd7d1) · s4-3-g.js(9f9408314dfd) · s4-3-n.js(4869bd8a433a) ·
//   s4-4-a.js(f992adb1a702) · s4-4-b.js(a76112730194) · s4-5-a.js(c1ab8b19f33b) · s4-5-b.js(c068c390531e) · s4-6-flag.js(1170faef3bfd)
//   원본의 저장소 사본: test/mock/source/ 아래 같은 이름의 파일(board-s4.src.html · themes/*) — 연구 폴더의 원본이 바뀌어도 옮긴 판의 기준은 이 사본이다.
// 판은 t-common.js가 맞춘 갈래 차례(sortThemes)로 보인다 — s4 갈래는 ORDER에 없어 등록 차례 그대로다.

final Map<String, List<BaseTheme>> boards = {
  's4': sortThemes(<BaseTheme>[
    // s4-2-ga.js — 조각 ④ 갈림 ② (가): 집권 사슬은 띠 안 흰 층(갈래 E 그대로) + 손잡이
    S4Theme(
      id: 's4-2-ga', code: '② 가', name: '띠 안 집권 층 + 손잡이', rec: true, //
      idea: '집권 사슬 = 갈래 E의 집권 흰 층(띠 안 · 지도자 층 위) 그대로 두고 손잡이만 더함 — 누르면 단체가 제 줄의 둥근 끝 꼬리표로 펼쳐짐',
      pro: 'E가 나중 결정 · 줄 높이 그대로(흰 층 16) · 지금 앱이 이미 그리는 칸 · 새 그림은 손잡이와 펼친 줄뿐',
      con: '집권 층이 띠 안에 있어 "단체"라는 느낌이 옅음 · 펼치면 집권 층과 단체 줄에 같은 이름이 두 번',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'detail': 'seoin'},
    ),
    S4Theme(
      id: 's4-2-ga-open', code: '② 가 · 펼침', name: '띠 안 집권 층 + 손잡이 — 펼친 모습', rec: false, //
      idea: '손잡이 `▾ 단체 6`을 누른 뒤 — 조선 밑에 단체 줄 셋(훈구 · 동인 · 북인 / 사림 · 서인 / 남인), 둥근 끝 꼬리표 · 구멍만 · 갈라짐은 승계 실',
      pro: '집권 층은 그대로 · 단체 줄은 펼칠 때만 늚',
      con: '단체 수만큼 줄이 늚 · 같은 이름이 집권 층과 꼬리표에 두 번',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'open': true, 'detail': 'seoin'},
    ),
    // s4-2-na.js — 조각 ④ 갈림 ② (나): 집권 사슬은 띠 밑(목업 d7-c 그대로)
    S4Theme(
      id: 's4-2-na', code: '② 나', name: '띠 밑 사슬', rec: false, //
      idea: '목업 d7-c 그대로 — 집권 사슬을 직위 줄 자리(띠 아래 틈 3 · 높이 14)에, 첫 칸 둥근 끝 + 구멍 + 실 · 왼쪽에 흰 꼬리표 손잡이. E의 집권 층은 없앰',
      pro: '사슬이 띠 밖에 있어 "단체"가 한눈에 갈림 · 목업 d7-c와 같은 그림',
      con: 'E(칸 단은 띠 안)를 되돌림 · 사슬 있는 줄마다 +17 · 실권 단의 자리가 따로 없음 · 손잡이만 든 줄(명)도 +17',
      opt: const {'chain': 'lane', 'handle': null, 'real': true, 'detail': 'seoin'},
    ),
    S4Theme(
      id: 's4-2-na-open', code: '② 나 · 펼침', name: '띠 밑 사슬 — 펼친 모습', rec: false, //
      idea: '손잡이를 누른 뒤 — 사슬은 남고 조선 밑에 단체 줄 셋이 둥근 끝 꼬리표로 펼쳐짐',
      pro: '사슬과 펼친 줄이 같은 꼴(열쇠표)',
      con: '사슬 + 단체 줄 + 지도자 층이 세 겹으로 쌓임',
      opt: const {'chain': 'lane', 'handle': null, 'real': true, 'open': true, 'detail': 'seoin'},
    ),
    // s4-3-g.js — 조각 ④ 갈림 ③ (ㄱ): 손잡이 = 머리 줄의 단추 `▸ 단체 n`
    S4Theme(
      id: 's4-3-g', code: '③ ㄱ', name: '머리 줄 단추 ▸ 단체 n', rec: true, //
      idea: '손잡이 = 머리 줄의 단추 `▸ 단체 6` — 지금 앱의 `▸ 속국 n` · `▸ 할거 n`과 한 가족 · 이름 뒤 4px · 누르면 `▾`',
      pro: '한 자리 · 한 가족 · 명사 + 수 · 집권 층이 없는 나라(명)도 같은 자리',
      con: '머리 줄의 사건 글이 단추만큼 오른쪽으로 밀림 · 집권 층과 떨어져 있어 "저 층을 펼친다"는 느낌은 약함',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'detail': 'seoin'},
    ),
    S4Theme(
      id: 's4-3-g-open', code: '③ ㄱ · 펼침', name: '머리 줄 단추 — 펼친 모습', rec: false, //
      idea: '`▾ 단체 6` — 누른 뒤의 단추와 펼친 단체 줄',
      pro: '', con: '',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'open': true, 'detail': 'seoin'},
    ),
    // s4-3-n.js — 조각 ④ 갈림 ③ (ㄴ): 손잡이 = 목업 d7의 흰 꼬리표(모따기 3 · 선 아이콘 ⌄ · 수)
    S4Theme(
      id: 's4-3-n', code: '③ ㄴ', name: '흰 꼬리표 ⌄ n', rec: false, //
      idea: '손잡이 = 목업 d7-a · d7-c의 흰 꼬리표(모따기 3 · 선 아이콘 ⌄ 10 · 수 8.5) — 집권 층 첫 칸 왼쪽에, 집권 층이 없으면 머리 줄로',
      pro: '사슬 바로 옆이라 "이 층을 펼친다"가 읽힘 · 목업 d7과 같은 꼴 · 글자 없이 선 아이콘 + 수',
      con: '자리 규칙이 둘(층 안 / 머리 줄) · 첫 칸이 띠 시작에 붙으면 자리가 없음 · 층 안 12px에 아이콘 · 수가 빽빽함',
      opt: const {'chain': 'floor', 'handle': 'tag', 'real': true, 'detail': 'seoin'},
    ),
    S4Theme(
      id: 's4-3-n-open', code: '③ ㄴ · 펼침', name: '흰 꼬리표 — 펼친 모습', rec: false, //
      idea: '⌃ 6 — 누른 뒤의 꼬리표와 펼친 단체 줄',
      pro: '', con: '',
      opt: const {'chain': 'floor', 'handle': 'tag', 'real': true, 'open': true, 'detail': 'seoin'},
    ),
    // s4-4-a.js — 조각 ④ 갈림 ④ (A): 실권 정권을 제 띠로 꺼낸 뒤에도 든 나라 띠 안 실권 흰 층을 남김
    S4Theme(
      id: 's4-4-a', code: '④ A', name: '실권 층 남김', rec: true, //
      idea: '최씨 정권은 제 띠(받침 카드 + 고려 탭)로 꺼내되, 고려 띠 안의 실권 흰 층(최씨 정권)과 명목 지도자 옅게도 그대로 남김 — 설계 3-4 · 바꿀 것 없음',
      pro: '명목 지도자 기준이 자료 그대로 남음 · 고려 띠만 봐도 "누가 실권을 쥐었나"가 읽힘 · 코드 변경 없음',
      con: '같은 이름(최씨 정권)이 고려 띠 안과 제 띠에 두 번 · 고려 줄이 +16',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'detail': 'choe'},
    ),
    // s4-4-b.js — 조각 ④ 갈림 ④ (B): 실권 정권을 제 띠로 꺼내면 든 나라 띠 안 실권 층은 지움
    S4Theme(
      id: 's4-4-b', code: '④ B', name: '실권 층 지움', rec: false, //
      idea: '최씨 정권을 제 띠로 꺼내면 고려 띠 안에는 표시 없음 — groupStrip에서 regime을 실권에서 빼고(한 줄), 명목 지도자 옅게도 함께 사라짐',
      pro: '한 단체가 한 자리에만 · 고려 줄이 16 낮음',
      con: '명목 지도자(신종 · 희종 · 강종 · 고종)가 보통 왕처럼 보임 · 고려 띠만 봐서는 실권이 어디 있었는지 모름 · 받침 카드가 없는 줄에서는 관계가 끊김',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': false, 'detail': 'choe'},
    ),
    // s4-5-a.js — 조각 ④ 갈림 ⑤ (A): 옮겨 앉기 · 풀림일 때 토막 둘을 두 줄에 두고 굽은 점선 실 + 매듭으로 이음
    S4Theme(
      id: 's4-5-a', code: '⑤ A', name: '두 줄 + 굽은 점선 실', rec: true, //
      idea: '풀림에서 토막 둘은 각각 제 줄(승계가 없으니 chainRows가 저절로) · 앞 토막 아랫변 매듭에서 곧게 내려가 뒤 토막 구멍으로 꺾이는 점선 실(d3-a · 직위 줄과 같은 규칙)',
      pro: '바꿀 것 없음(줄 배치 그대로) · 실이 "같은 객체"를 말함 · 폴더를 켜도 같은 실',
      con: '한 객체가 두 줄을 차지 · 실이 승계 실(마름모 → 구멍)과 헷갈릴 수 있음',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'move': 'A', 'detail': 'boh'},
    ),
    // s4-5-b.js — 조각 ④ 갈림 ⑤ (B): 옮겨 앉기 · 풀림일 때 토막 둘을 한 줄에 이어 붙이고 이음매에 매듭만
    S4Theme(
      id: 's4-5-b', code: '⑤ B', name: '한 줄 이음매 + 매듭', rec: false, //
      idea: '토막 둘을 한 줄에 이어 붙이고(숨은 직접 승계) 이음매 자리에 매듭만 — 꼬리 마름모 · 승계선은 내보내기에서 걸러냄',
      pro: '세로가 늘지 않음 · 한 객체가 한 줄',
      con: '숨은 승계를 넣어야 해서 승계 규칙(마름모 · 승계선 · 이음매)이 끼어듦 · 매듭만으로는 "그릇이 바뀜"이 약함 · 열쇠표가 이음매 바로 위에 겹쳐 붐빔',
      opt: const {'chain': 'floor', 'handle': 'btn', 'real': true, 'move': 'B', 'detail': 'boh'},
    ),
    // s4-6-flag.js — 조각 ④ 손잡이: 감독 안(포스트잇 플래그 — 닫힘은 빗금 플래그, 누르면 위로 늘어난 창)
    S4Theme(
      id: 's4-6-flag', code: '③ 플래그', name: '포스트잇 플래그(닫힘)', rec: false, //
      idea: '머리 줄 단추 대신 꼬리표 윗변에 빗금 플래그 — 머리 줄은 이름 · 사건만',
      pro: '머리 줄이 비워짐 · 서류철의 색인 플래그 말(서고)', con: '수 · 무엇이 접혔는지 닫힌 채로는 안 보임 · 한 번 더 누름',
      opt: const {'chain': 'floor', 'handle': 'flag', 'real': true, 'detail': 'seoin'},
    ),
    S4Theme(
      id: 's4-6-flag-open', code: '③ 플래그 · 창', name: '포스트잇 플래그 — 누른 뒤의 창', rec: false, //
      idea: '명의 플래그를 누름 — 플래그가 위로 늘어나 창이 됨(단체 2 · 목록 · 펼침 아이콘)',
      pro: '', con: '',
      opt: const {'chain': 'floor', 'handle': 'flag', 'real': true, 'detail': 'seoin', 'flagOpen': '명'},
    ),
  ]),
};

/// 판마다 2배로 잘라 볼 자리(화면 px) — s4는 옆 세션의 shoot-flag.mjs와 같은 자리.
final Map<String, List<ui.Rect>> boardCrops = {
  's4': [ui.Rect.fromLTWH(700, 120, 760, 250)],
};
