/* 조각 ④ 갈림 ③ (ㄱ) — 손잡이 = 머리 줄의 단추 `▸ 단체 n`. by Fable
   지금 앱의 `▸ 속국 n` · `▸ 할거 n`(scopes.dart ScopeMarks — 높이 16 · 좌우 6 · 모서리 5 · 글 10 · 종이색 칠 + 띠 테 빛깔)과 한 가족.
   자리는 띠 안 이름 뒤 4px(갈래 E의 소속 단추 자리) — 집권 층이 있든 없든(조선 · 명) 한 자리. 띠 안 집권 층(② 가)을 바탕으로. */
window.S4.register({
  id: 's4-3-g', code: '③ ㄱ', name: '머리 줄 단추 ▸ 단체 n', rec: true,
  idea: '손잡이 = 머리 줄의 단추 `▸ 단체 6` — 지금 앱의 `▸ 속국 n` · `▸ 할거 n`과 한 가족 · 이름 뒤 4px · 누르면 `▾`',
  pro: '한 자리 · 한 가족 · 명사 + 수 · 집권 층이 없는 나라(명)도 같은 자리',
  con: '머리 줄의 사건 글이 단추만큼 오른쪽으로 밀림 · 집권 층과 떨어져 있어 "저 층을 펼친다"는 느낌은 약함',
  opt: { chain: 'floor', handle: 'btn', real: true, detail: 'seoin' },
});
window.S4.register({
  id: 's4-3-g-open', code: '③ ㄱ · 펼침', name: '머리 줄 단추 — 펼친 모습', rec: false,
  idea: '`▾ 단체 6` — 누른 뒤의 단추와 펼친 단체 줄',
  pro: '', con: '',
  opt: { chain: 'floor', handle: 'btn', real: true, open: true, detail: 'seoin' },
});
