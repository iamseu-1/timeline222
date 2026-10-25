/* 조각 ④ 갈림 ③ (ㄴ) — 손잡이 = 목업 d7의 흰 꼬리표(모따기 3 · 선 아이콘 ⌄ · 수). by Fable
   집권 층이 있으면 집권 층 첫 칸 왼쪽(층 안 · 높이 12 · 위아래 2 띄움), 집권 층이 없으면(명) 머리 줄 이름 뒤 4px — 자리 규칙이 둘.
   띠 안 집권 층(② 가)을 바탕으로. */
window.S4.register({
  id: 's4-3-n', code: '③ ㄴ', name: '흰 꼬리표 ⌄ n', rec: false,
  idea: '손잡이 = 목업 d7-a · d7-c의 흰 꼬리표(모따기 3 · 선 아이콘 ⌄ 10 · 수 8.5) — 집권 층 첫 칸 왼쪽에, 집권 층이 없으면 머리 줄로',
  pro: '사슬 바로 옆이라 "이 층을 펼친다"가 읽힘 · 목업 d7과 같은 꼴 · 글자 없이 선 아이콘 + 수',
  con: '자리 규칙이 둘(층 안 / 머리 줄) · 첫 칸이 띠 시작에 붙으면 자리가 없음 · 층 안 12px에 아이콘 · 수가 빽빽함',
  opt: { chain: 'floor', handle: 'tag', real: true, detail: 'seoin' },
});
window.S4.register({
  id: 's4-3-n-open', code: '③ ㄴ · 펼침', name: '흰 꼬리표 — 펼친 모습', rec: false,
  idea: '⌃ 6 — 누른 뒤의 꼬리표와 펼친 단체 줄',
  pro: '', con: '',
  opt: { chain: 'floor', handle: 'tag', real: true, open: true, detail: 'seoin' },
});
