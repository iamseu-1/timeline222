/* 조각 ④ 손잡이 — 감독 안(2026-10-15 "접었다 폈다 하는 등의 기능은 포스트잇 플래그처럼 위에 살짝 놓고 누르면 해당 창을 띄우는 느낌" · 그림판).
   닫힘 = 꼬리표 윗변에 얹힌 빗금 플래그(글 없음) · 누르면 그 플래그가 위로 늘어난 창(머리 '단체 n' + 펼침 선 아이콘 · 목록). */
window.S4.register({
  id: 's4-6-flag', code: '③ 플래그', name: '포스트잇 플래그(닫힘)', rec: false,
  idea: '머리 줄 단추 대신 꼬리표 윗변에 빗금 플래그 — 머리 줄은 이름 · 사건만',
  pro: '머리 줄이 비워짐 · 서류철의 색인 플래그 말(서고)', con: '수 · 무엇이 접혔는지 닫힌 채로는 안 보임 · 한 번 더 누름',
  opt: { chain: 'floor', handle: 'flag', real: true, detail: 'seoin' },
});
window.S4.register({
  id: 's4-6-flag-open', code: '③ 플래그 · 창', name: '포스트잇 플래그 — 누른 뒤의 창', rec: false,
  idea: '명의 플래그를 누름 — 플래그가 위로 늘어나 창이 됨(단체 2 · 목록 · 펼침 아이콘)',
  pro: '', con: '',
  opt: { chain: 'floor', handle: 'flag', real: true, detail: 'seoin', flagOpen: '명' },
});
