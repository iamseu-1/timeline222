/* 공용 목업 도구 — 쓰는 예. 고정 사본(BASE)의 연표에 동아시아 기본팩 + 가상 이름의 확인용 DLC(나라 하나를 한국 트랙에)를 얹어
 * 500~700년을 찍고, 그 띠 바로 위에 끼워 넣은 작은 후보 도형(안 A) · 띠 안에 넣은 후보(안 B)를 더한 그림과 고르기 판을 만듭니다.
 * 휴대폰 가로(891×411 · 배율 3.5)와 메이커 작업본도 한 장씩 찍어 도구가 도는지 함께 봅니다.
 *
 * ── 쓰는 법 ──
 *   node scripts/mock/example.mjs                       → .claude/research/10건/kit/ 에 kit-*.png · board.html
 *   node scripts/mock/example.mjs --out <폴더> --root <띄울 폴더>
 *   마지막 줄 '목업 도구 확인 — 문제 없음'이 나와야 합니다. 그 뒤에 그림을 직접 열어 띠 · 글자 · 예시 나라가 제대로 보이는지 눈으로 봅니다.
 * ── 뒤 갈래 작업자가 따라 할 차례 ──
 *   1) makeDlc로 예시 자료(가상 이름 · 파스텔 색) → 2) openMock({ dlcs, view }) → 3) uidOf · reveal로 그 자리를 화면에
 *   4) shot('…-now.png', { clip }) — 지금 모습 → 5) css · overlay · overlayAt · insertInto(+ freeze)로 후보 → 같은 clip으로 shot
 *   6) clearInjected 뒤 다음 후보 → 7) writeBoard({ decisions }) → 8) 그림을 열어 눈으로 확인 */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { openMock, makeDlc, PASTEL, VIEW_PHONE, BASE, REPO } from './lib.mjs';
import { writeBoard } from './board.mjs';

const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
};
const OUT = path.resolve(arg('--out', path.join(REPO, '.claude/research/10건/kit')));
const ROOT = path.resolve(arg('--root', BASE));
fs.mkdirSync(OUT, { recursive: true });
const at = name => path.join(OUT, name);

/* 1) 예시 DLC — 이름은 모두 가상(확인용 · 고증 아님). 한국 트랙(기본팩과 같은 id · 이름이면 한 줄로 합쳐짐)에 나라 하나 */
const dlc = makeDlc({
  id: 'mock-kit-check',
  name: '확인용 가상 나라',
  description: '목업 도구 확인용 예시 — 고증 아님',
  tracks: [{ id: 'korea', name: '한국' }],
  periods: [
    {
      id: 'haeon', track: 'korea', name: '해온국', start: 520, end: 680, color: PASTEL.민트,
      leaders: [{ name: '솔빛', start: 520, end: 575 }, { name: '가람', start: 575, end: 630 }, { name: '누리', start: 630 }],
    },
  ],
  events: [
    { id: 'sea', track: 'korea', polity: '해온국', title: '바닷길 열림', start: 560, category: 'diplomacy' },
    { id: 'wall', track: 'korea', polity: '해온국', title: '새 성 쌓음', start: 612, category: 'politics' },
  ],
});

/* 후보 도형의 모양 — 파스텔 열두 가지 안의 색 · 둥근 네모 · 연표의 글꼴 */
const CAND_CSS = `
.mk-cand{display:inline-flex;align-items:center;gap:4px;height:18px;padding:0 8px;border-radius:7px;background:${PASTEL.버터};color:#4a3b22;
  font:600 11px/18px Pretendard,sans-serif;white-space:nowrap;box-shadow:0 0 0 1px rgba(90,70,40,.18)}
.mk-cand i{width:6px;height:6px;border-radius:50%;background:#8a6d3b;opacity:.55}
.mk-in{position:absolute;right:10px;bottom:7px;z-index:3;display:inline-flex;align-items:center;height:16px;padding:0 7px;border-radius:6px;
  background:${PASTEL.피치};color:#4a3226;font:600 10.5px/16px Pretendard,sans-serif;white-space:nowrap}
`;

const overlaps = (a, b) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
const t0 = Date.now();
console.log(`목업 도구 확인 — 띄울 폴더 ${ROOT}`);

/* 2) 연표 + 기본팩 + 예시 DLC, 500~700년 */
const m = await openMock({ root: ROOT, dlcs: [dlc], view: [500, 700] });
let ok = false;
try {
  /* 3) 예시 나라를 화면 위쪽 1/3쯤에 */
  const uid = await m.uidOf('해온국', { kind: 'period' });
  await m.reveal(uid, { at: 330 });

  /* 띠 · 글자가 정말 생겼는지 (그림을 보기 전에 숫자로 한 번) */
  const band = await m.rect(uid);
  assert.ok(band && band.width > 600 && band.height > 40, '예시 나라의 띠가 화면에 있음');
  const tab = await m.rect({ uid, part: 'tab' });
  assert.ok(tab && tab.text.includes('해온국'), '띠의 간지 탭에 나라 이름');
  const cells = await m.rects({ sel: `.tl-band[data-uid="${uid}"] .tl-cell` });
  assert.deepEqual(cells.map(c => c.text), ['솔빛', '가람', '누리'], '지도자 칸 셋');
  const others = (await m.bands({ track: 'korea' })).map(b => b.name);
  assert.ok(others.includes('신라'), '기본팩의 띠도 함께 (신라)');
  const body = await m.bodyRect();

  /* 4) 지금 모습 — 화면 전체 한 장 + 띠 둘레를 가로 전체로 자른 한 장 */
  const clip = await m.clipAround(uid, { above: 150, below: 70 }); // 탭 윗변 150px 위 ~ 띠 아랫변 70px 아래, 가로는 화면 전체
  assert.ok(clip.y >= body.top - 150 && clip.height > band.height, '자를 사각형');
  const full = await m.shot(at('kit-now-full.png'));
  const now = await m.shot(at('kit-now.png'), { clip });

  /* 5-A) 안 A — 띠 바로 위(윗변에서 3px 떨어져) 600년 자리에 얹은 작은 딱지 (맨 위 층 · 연표 몸통 밖은 잘림) */
  await m.css(CAND_CSS);
  const x600 = await m.xOf(600);
  const a = await m.overlayAt(uid, '<span class="mk-cand"><i></i>후보 딱지</span>', { place: 'above', dx: x600 - band.x, gap: 3, clip: 'timeline' });
  assert.ok(!overlaps(a, band) && !overlaps(a, tab), '안 A의 딱지가 띠 · 탭과 겹치지 않음');
  const shotA = await m.shot(at('kit-a.png'), { clip });
  await m.clearInjected();

  /* 5-B) 안 B — 띠 안 오른쪽 아래에 넣은 딱지 (띠 요소 안 — 다시 그리면 지워지므로 멈추고 찍음) */
  await m.css(CAND_CSS);
  await m.freeze();
  await m.insertInto(uid, '<span class="mk-in">후보 딱지</span>');
  const inB = await m.rect({ sel: '.mk-in' });
  assert.ok(inB && inB.x >= band.x && inB.right <= band.right && inB.y >= band.y && inB.bottom <= band.bottom, '안 B의 딱지가 띠 안에 (띠 밖 돌출 없음)');
  const shotB = await m.shot(at('kit-b.png'), { clip });
  await m.unfreeze();
  await m.clearInjected();
  assert.deepEqual(m.errors, [], '연표 오류 없음');
  await m.close();

  /* 휴대폰 가로 (갤럭시 S25 울트라 — CSS 891×411 · 배율 3.5, 그림은 CSS 1px = 1px) */
  const p = await openMock({ root: ROOT, dlcs: [dlc], view: [500, 700], viewport: VIEW_PHONE });
  await p.reveal(uid, { at: 90 });
  assert.ok(await p.rect(uid), '휴대폰 화면에도 띠');
  const phone = await p.shot(at('kit-phone.png'));
  assert.deepEqual(p.errors, [], '휴대폰 화면 오류 없음');
  await p.close();

  /* 메이커 — 같은 자료를 작업본(고치는 DLC)으로, 기본팩은 불러온 팩(잠김)으로 함께 */
  const mk = await openMock({ root: ROOT, app: 'maker', draft: dlc, refs: ['east-asia-base'], view: [500, 700] });
  await mk.reveal(uid, { at: 300 });
  assert.ok(await mk.rect(uid), '메이커 연표에도 띠');
  const maker = await mk.shot(at('kit-maker.png'));
  assert.deepEqual(mk.errors, [], '메이커 오류 없음');
  await mk.close();

  /* 7) 고르기 판 */
  const board = writeBoard({
    out: at('board.html'),
    branch: 'kit · 공용 목업 도구',
    title: '목업 도구 확인 판',
    date: '2026-10-12',
    lead: '뒤 갈래(D1~D6) 작업자가 쓰는 공용 목업 도구(scripts/mock/)가 제대로 도는지 보는 견본 판입니다. 고정 사본의 연표에 동아시아 기본팩과 가상 나라 하나(확인용 DLC)를 얹고, 띠 둘레에 후보 도형을 두 가지 방법으로 끼워 찍었습니다. 판의 꼴(결정 · 지금 모습 · 안 A/B · 추천 · 따짐 표)도 이것을 본보기로 씁니다.',
    decisions: [
      {
        id: 'kit-1',
        title: '후보 도형을 얹는 자리 (도구 확인용 예시)',
        desc: '가상 나라 «해온국»(520~680 · 한국 트랙) 띠에 작은 딱지 하나를 더한다면 어디에 둘지 — 실제 결정이 아니라 도구의 두 끼워 넣기(맨 위 층 · 띠 안)를 보여 주는 예시입니다.',
        now: { src: path.basename(now.file), caption: '지금 모습 — 띠 둘레를 가로 전체로 자름' },
        nowDesc: '간지 탭 · 지도자 칸 셋 · 사건 둘이 그려진 예시 나라의 띠. 위로는 기본팩의 가야 · 신라 띠.',
        options: [
          {
            key: 'A', name: '띠 바로 위 (맨 위 층)',
            img: { src: path.basename(shotA.file), caption: 'm.overlayAt(uid, …, { place: "above" }) — 600년 자리' },
            desc: '띠 윗변에서 3px 떨어진 빈 자리에 딱지를 띄움. 화면 좌표로 얹으므로 연표가 다시 그려도 그대로 남습니다.',
            pros: ['띠 높이를 바꾸지 않음', '탭 · 칸과 겹치지 않음(도구가 검사)'],
            cons: ['줄 사이 여백이 좁은 곳에서는 위 띠와 닿을 수 있음'],
            checks: { '새 앱': '(예시) 장면의 띠 위 여백에 그리는 꼴 — 같은 모습 가능', '띠 높이': '+0px', '성능': '(예시) 띠마다 요소 하나', '휴대폰': '(예시) 여백이 같아 그대로' },
          },
          {
            key: 'B', name: '띠 안 오른쪽 아래',
            img: { src: path.basename(shotB.file), caption: 'm.freeze() + m.insertInto(uid, …) — 띠 요소 안' },
            desc: '띠 요소 안에 직접 넣어 띠의 좌표계를 그대로 씀. 다시 그리면 지워지므로 그리기를 멈추고 찍습니다.',
            pros: ['띠 밖 돌출 없음(도구가 검사)', '띠와 함께 움직임'],
            cons: ['짧은 띠에서는 사건 이름과 다툼'],
            checks: { '새 앱': '(예시) 띠 안 구역에 그리는 꼴 — 같은 모습 가능', '띠 높이': '+0px', '성능': '(예시) 띠마다 요소 하나', '휴대폰': '(예시) 짧은 띠에서 숨김 규칙 필요' },
          },
        ],
        recommend: 'A',
        why: '(예시) 띠 높이 · 띠 안의 칸을 건드리지 않고, 짧은 띠에서도 사건 이름과 다투지 않음. — 실제 갈래 판에서는 여기에 새 앱 · 띠 높이 · 성능 · 휴대폰의 까닭을 적습니다.',
      },
    ],
    sections: [
      {
        title: '도구 확인 — 화면 전체 · 휴대폰 가로 · 메이커 작업본',
        desc: '같은 예시 DLC로 찍은 세 장: ① 연표 화면 전체(1920×1080) ② 휴대폰 가로(CSS 891×411 · 배율 3.5 — 그림은 CSS 1px = 1px) ③ 메이커 — 예시 DLC를 작업본으로, 기본팩을 불러온 팩(잠김)으로.',
        images: [
          { src: path.basename(full.file), caption: '연표 화면 전체' },
          { src: path.basename(phone.file), caption: '휴대폰 가로' },
          { src: path.basename(maker.file), caption: '메이커 작업본' },
        ],
      },
    ],
  });
  console.log(`  그림: ${[full, now, shotA, shotB, phone, maker].map(s => `${path.basename(s.file)} ${s.width}×${s.height}`).join(' · ')}`);
  console.log(`  판: ${board}`);
  console.log(`  걸린 시간 ${((Date.now() - t0) / 1000).toFixed(1)}초`);
  ok = true;
} catch (e) {
  console.error('목업 도구 확인 — 실패:', e && e.message ? e.message : e);
  if (m.errors.length) console.error('  연표 오류:', m.errors.join(' / '));
  process.exit(1); // 열린 브라우저가 남아 있어도 끝냄
}
if (ok) console.log('목업 도구 확인 — 문제 없음');
