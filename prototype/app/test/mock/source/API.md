# 방향(theme) 만드는 법 — 개편 목업 그리기 틀

같은 장면(`scene.js`)을 모든 방향이 그린다. 방향 하나 = `themes/<id>.js` 한 파일(또는 `themes.js` 안의 객체 하나)이고, `render.js`의 `BASE`(기준 방향 '간지')가 가진 **고리(함수)** 가운데 바꿀 것만 덮어쓴다. 덮어쓰지 않은 고리는 BASE 것을 쓴다. 고리 안의 `this`는 합쳐진 방향 객체(`this.k(a)` · `this.M` · `this.tok` · 다른 고리 호출 가능).

## 방향 객체

```js
THEMES.push({
  id: 'ledger', code: '방향 5', name: '장부', keepB: false, by: '메인' | 'Fable',
  idea: '한 줄 은유', pro: '장점 한 줄', con: '약점 한 줄', rec: false,
  tok: { paper: '#ffffff', ink: '#000000', fam: 'sans' | 'serif' },   // this.k(a) = 종이 위 먹 a의 불투명 색
  M: { ... },            // 줄 치수(아래) — 바꿀 것만
  frame(S, p, L) {}, dateHeader(S, p, L) {}, labelEra(S, p, g, name, layer) {}, gutter(S, p, L) {},
  container(S, p, c, g) {}, closedCulture(S, p, C) {},
  object(S, p, o, g) {}, shape(g) {}, cells(S, p, o, g, b) {}, power(S, p, o, g, b) {}, events(S, p, o, g, b) {},
  tags(S, p, o, g, b) {}, serve(S, p, o, g) {}, select(S, p, o, g, b) {},
  link(S, p, a, b, how) {}, lanes(S, p, L) {}, detail(S, p) {}, zoom(S, p) {},
});
```

## 치수 `M` (BASE 값)

`top 128`(첫 줄 y) · `clipTop 112`(그림판 위 끝) · `tabH 13`(탭 높이 — 줄마다 띠 위에 비워 둠) · `bandH 20`(띠) · `cellsH 32`(칸이 든 띠) · `gap 5` · `headH 24`(그릇 머리 자리 — 바깥) · `headH2 22`(안쪽 그릇) · `padB 7`(그릇 아래 여백) · `afterC 4` · `laneH 12` · `laneGap 2`(직위 줄) · `closedRoom 14`(접힌 줄 위 탭 자리) · `closedH 24` · `trackGap 6` · `cultureGap 9` · `inset 5`(그릇 안 객체를 그릇 가장자리에서 띄움). **세로 합이 1080을 넘지 않게**(지금 BASE로 약 1040).

## 그리기 층 `p`

`p.bg` `p.grid` `p.cont`(그릇) `p.under`(띠 뒤 — 뒤 장 · 뒤 탭) `p.links` `p.band`(띠) `p.over`(고름 · 위 표지) `p.dateh` `p.gut` `p.frame` `p.detail` `p.top`. 그림판 층(grid ~ over)은 `x 240 ~ 1540 · y clipTop ~ 1080`으로 잘린다. `p.X(해)` → x. `p.CL = 240` · `p.CR = 1540`(그림판 좌우 끝). `p.defs`(무늬 · 그라데이션 · 잘라내기).

## 넘겨받는 것

* `g`(객체 자리): `{ o, row, x0, x1, y(띠 윗변), h, cl, cr }` — `cl/cr` = 화면 밖으로 이어짐(그 쪽 모서리는 직각 · x는 화면 밖 30px).
* `o`(객체): `{ n 이름, a, b, c 나라 색, t 종류, g 갈래('다스림' · '영토 밖' · '무리'), cells?[[이름, 시작, 끝]], offices?[{n, a, b, status}], power?[{n, a, b}], ev?[{n, y}], serve?{to, c, rel, a}, tags?[{n, a, kind}], selected?, from?('direct'|'indirect'), outL?, outR? }`.
* `b`(그려진 띠): `{ X0, X1, Y, Hh }`(1px 선 맞춤 끝난 값).
* `c`(그릇): `{ n, t('시대' · '나라' · '연방'), c?(색), depth, yTop, yBottom, rows[], labels?[{n, a, b}] }` · `g`(그릇 자리): `{ x0, x1, yTop, yBottom, cl, cr }`.
* `C`(접힌 문화권): `{ n, count, tabs[{n, y, c}], rowY, rowH }`.
* `L.lanes[]`: `{ laneY, lane{ n, a, b, status } }` — 칼리파위가 아바스 → 맘루크 → 오스만으로 옮겨 앉음(이어짐 선을 그릴 것).

## 도구 `K`(kit.js) · `MOCK`(render.js)

`K.P`(파스텔 열둘) · `K.mix(c, p, base)` · `K.mixOk` · `K.fillC(c, p=.24, paper)` · `K.edge(c)` · `K.edgeSoft` · `K.tabInk(c)` · `K.nameInk(c)` · `K.ink(a, paper, ink)` · `K.E(tag, attrs, parent)` · `K.T(g, x, y, s, {size, wt, fill, anchor, fam:'serif', op})` · `K.TW(s, size, wt, fam)` · `K.base(가운데y, size)` → 바탕선 · `K.px(v)` → .5 맞춤 · `K.rr(x, y, w, h, r | [tl, tr, br, bl])` · `K.tabPath(xL, xR, yBase, th, s)` · `K.roundPoly(pts, r)` · `K.icon(g, 'search'|'filter'|'eye'|'layers'|'more'|'x'|'plus'|'minus'|'expand'|'down'|'right'|'folder'|'book'|'doc', x, y, size, color)` · `K.fit(s, room, size)` · `K.id()` · `MOCK.tab(g, xL, yBase, label, {fill, stroke, ink, th, size, pad, s, behind, count})` · `MOCK.tabSquare` · `MOCK.wrap(s, width, size, wt, fam)`.

## 지킬 것

* 나라 색(`o.c`)은 파스텔 열둘 그대로 — 칠의 짙기 · 쓰는 자리는 방향이 정함. 그릇(시대)은 나라 색을 쓰지 않음(나라 · 연방 그릇은 제 색을 옅게 써도 됨).
* 글자 위아래 2px 이상 틈 · 명사만 · 이모지 금지 · 겹침 금지(이름이 안 들어가면 첫 글자 → 없음).
* 층 위계: 그릇 > 객체 > 칸 > 표지가 한눈에 갈려야 함. 그릇(끄는 그릇)과 섬김(상국 · 명목 군주 — `serve`), 끌지 않는 그릇(`tags` — 가문 영역 · 동맹)이 서로 다른 꼴.
* 갈래 넷: 다스림 · 영토 밖 · 무리 + 그릇 — 띠 모양으로 가름(종류 열여덟은 상세 · 범례에서).
* 확인: `node build.mjs && node shoot.mjs <id>` → `shots/<id>.png`(1920×1080 1배)를 직접 열어 볼 것.
