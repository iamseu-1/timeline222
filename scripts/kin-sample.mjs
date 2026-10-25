/* 가상 대가족 견본 생성기 (D1-T) — 승계표 · 세계표 · 가문(D1)을 재고 확인할 큰 계보 DLC 원문(JSON)을 만듭니다.
   기준: D1 확정 설계(docs/설계-10건/ 의 '1-2 … 가문-확정.md') 6-5 ①. 측정은 scripts/kin-bench.mjs가 이 모듈의 kinSample()을 그대로 부릅니다.

   node scripts/kin-sample.mjs [--size 1000,10000,50000,200000] [--kind lineage-id,lineage-name,band-id,band-name]
                               [--house written|inherit] [--no-cycle] [--out <폴더>] [--twice]

   * 난수를 쓰지 않습니다. 고정 산술 순열(씨앗 20260921 — 엔진의 가상 자료 생성기 prototype/engine/src/generate.rs와 같은 수)만 써서,
     같은 수(크기 · 판 · 선택)면 언제 · 어느 기계에서 만들어도 같은 바이트가 나옵니다. --twice는 같은 수로 두 번 만들어 sha256을 견줍니다.
   * 이름은 가상 음절 스물넷의 조합(네 음절 — 사람마다 하나뿐)과 손으로 지은 가상 낱말만 씁니다. 실제 역사 이름이 들어갈 길이 없습니다.
   * 크기 = 인물(figures) 수입니다(가문 사람 · 배우자 · 이름 미상 · 외손 모두). 지도자 칸 30(+ 두 나라 칸 2)은 따로입니다.
   * 판 넷(--kind): 계보 전용 / 띠 인물 × id 참조 / 이름 참조
       lineage-id    계보 전용(lineageOnly) · 생몰은 반만 · 부모 · 배우자 · 파조를 인물 id(지도자는 "나라:지도자@해")로
       lineage-name  같은 사람들 · 가리키는 글을 이름으로(지도자도 이름 — 같은 사람의 두 칸만 "나라:지도자@해")
       band-id       띠 인물(lineageOnly 없음) · 모두 생몰을 적음 · id 참조 — 형식 3의 새 칸 없이도 지금 코드가 읽는 판
       band-name     띠 인물 · 이름 참조
     이름 미상의 공유 자리('미상'인 인물)를 가리키는 자식 줄은 이름 판에서도 id로 적습니다(설계 2-4 다 — '미상' 글은 줄마다 새 빈 고리).
   * 가문(--house): written(기본) = 가문 사람마다 제 가문(파)을 적음 — 물려받기가 없는 지금 코드에서도 파 · 본가가 갈림(설계 6-4의 측정과 같은 꼴)
                    inherit = 배우자(가문 밖)만 적고 나머지는 파조 · 부계 물려받기(설계 2-4 마)에 맡김
   * 넣는 것(설계 6-5 ①)
       지도자 줄 30(가람 나라) — 세습 · 선양 · 동생 선양 · 숙부 찬탈 · 복위(같은 사람의 두 칸) · 관계 미상('미상' 한 글 · 선출 + 전임자 미상) · 방식 미상 · 비움 · 두 나라 지도자(물마루 나라에도 같은 사람의 칸)
       파 14(대군파 10 + 파 안의 군파 4) · 가문 밖 집안 6(배우자)
       비율(아들 줄 기준): 양자 3% · 건너뜀(후손 2대) 1% · 이름 미상 2%(공유 미상 1.5% + 줄마다 빈 고리 0.5%) · 부모 둘 다 가문 안 0.5%
       배우자 40%(가문 밖 집안의 인물) · 외손(딸의 자식 — 가문 밖 잎) 딸의 1% · 직함 약 2할 · 명칭 목록 약 3할 · 형제 순서(order — 생년이 없는 형제)
       고리 1건(어떤 사람의 양부로 그 사람의 증손을 적음 — --no-cycle이면 뺌)
   * 출력: <폴더>/kin-<크기>-<판>[-inherit][-nocycle].json 과 목록.json(파일마다 바이트 · sha256 · 셈). 기본 폴더 배포/측정/가상-대가족/(git 밖).
     packs/ · samples/는 읽지도 쓰지도 않고, 그 지문(sha256)을 처음과 끝에 견줍니다. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const SEED = 20260921;
export const SIZES = [1000, 10000, 50000, 200000];
export const KINDS = {
  'lineage-id': { lineage: true, byName: false, label: '계보 전용 · id 참조' },
  'lineage-name': { lineage: true, byName: true, label: '계보 전용 · 이름 참조' },
  'band-id': { lineage: false, byName: false, label: '띠 인물 · id 참조' },
  'band-name': { lineage: false, byName: true, label: '띠 인물 · 이름 참조' },
};
const SIZE_WORDS = { '1천': 1000, '1만': 10000, '2만': 20000, '5만': 50000, '20만': 200000 };

/** 고정 산술 섞기 — (번호, 갈래) → 32비트 정수. 난수가 아니라 같은 입력이면 늘 같은 값 */
const mix = (i, salt) => {
  let h = Math.imul(i + 1, 0x9e3779b1) ^ Math.imul(salt + SEED, 0x85ebca6b);
  h ^= h >>> 15;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 13;
  h = Math.imul(h, 0x27d4eb2f);
  h ^= h >>> 16;
  return h >>> 0;
};

/* 이름 — 가상 음절 24개의 네 음절 조합(24⁴ = 331,776가지). n → (n × 7919 + 씨앗) mod 24⁴는 서로 다른 n에 서로 다른 값(7919는 24⁴와 서로소)이라
   번호가 다르면 이름도 다릅니다. 지도자 0~63 · 인물 100~ 으로 나눠 씀(가장 큰 견본 20만도 넉넉히 안) */
const SYL = ['가', '람', '나', '래', '다', '온', '라', '마', '루', '바', '새', '론', '아', '하', '늬', '보', '미', '르', '도', '담', '슬', '기', '한', '울'];
const SPACE = 24 ** 4;
const given = n => {
  const k = (n * 7919 + SEED) % SPACE;
  return SYL[k % 24] + SYL[Math.floor(k / 24) % 24] + SYL[Math.floor(k / 576) % 24] + SYL[Math.floor(k / 13824)];
};

/* 손으로 지은 가상 낱말 */
const POLITY_A = { id: 'kin-garam', track: 'kin-garam', name: '가람 나라', people: '누리족' };
const POLITY_B = { id: 'kin-mulmaru', track: 'kin-mulmaru', name: '물마루 나라', people: '물마루족' };
const ROOT = { id: 'kin-on', name: '물빛 온씨', surname: '온', seat: '물빛' };
const PA = ['바람', '솔빛', '물결', '달빛', '구름', '안개', '이슬', '노을', '여울', '윤슬', '가온', '나래', '미르', '한울']; // 0~9 대군파(본가 아래) · 10~13 군파(파 안의 파)
const OUTSIDE = [['바위골', '결'], ['안개내', '늘'], ['별마루', '솔'], ['갈대섬', '담'], ['흰여울', '별'], ['구름재', '새']];
const ROLES = ['관료', '학자', '무관', '문인', '상인', '승려'];
/* 지도자 줄의 갈래(i = 1~29 → PLAN[(i − 1) % 10]) */
const PLAN = ['세습', '선양', '세습', '동생 선양', '숙부 찬탈', '복위', '관계 미상', '방식 미상', '비움', '두 나라'];
/* 파조를 내는 지도자 칸 번호(그 사람의 첫 아들이 대군파의 파조) */
const FOUNDER_CELLS = [1, 2, 3, 7, 8, 11, 13, 17, 20, 23]; // 복위 칸(6 · 16 · 26)은 앞 칸과 같은 사람이라 뺌
/* 가람 나라 사람이 아들 · 딸을 몇 두나(인물) — 아들 평균 1.5 · 딸 0.3 */
const SONS = [0, 1, 1, 1, 2, 2, 2, 2, 3, 1];
const DAUGHTERS = [0, 0, 1, 0, 1, 0, 0, 1, 0, 0];

const sizeOf = s => {
  const v = SIZE_WORDS[String(s).trim()] ?? Number(String(s).replace(/[_,]/g, ''));
  if (!Number.isInteger(v) || v < 100 || v > 300000) throw new Error(`크기는 100~300,000의 정수입니다: ${s}`);
  return v;
};
const sizeWord = n => (n % 10000 === 0 ? `${n / 10000}만` : n % 1000 === 0 ? `${n / 1000}천` : n.toLocaleString('ko-KR'));

/**
 * 가상 대가족 하나를 짓습니다.
 * @param {{ size: number, kind?: string, house?: 'written'|'inherit', cycle?: boolean }} o
 * @returns {{ pack: object, json: string, file: string, stats: object, tree: object }}
 *   pack — DLC 원문(객체) · json — 바이트가 늘 같은 글(한 줄에 항목 하나) · stats — 셈 · tree — 생성기가 아는 나무(측정 도구의 대역 뼈대용)
 */
export function kinSample({ size, kind = 'lineage-id', house = 'written', cycle = true } = {}) {
  const N = sizeOf(size);
  const K = KINDS[kind];
  if (!K) throw new Error(`판은 ${Object.keys(KINDS).join(' · ')} 가운데 하나입니다: ${kind}`);
  if (house !== 'written' && house !== 'inherit') throw new Error(`가문은 written · inherit 가운데 하나입니다: ${house}`);

  /* ① 지도자 칸 30 — 사람(P)과 칸(cells)을 따로 둡니다. 복위는 같은 사람의 둘째 칸 */
  const P = []; // { i, kind: 'leader'|'member'|'spouse'|'outer', name, id, father, parents: [{ p | unknown, as, gen? }], spouses: [], birth, death?, ... }
  const person = o => {
    o.i = P.length;
    o.parents = o.parents || [];
    o.spouses = [];
    o.kids = [];
    P.push(o);
    return o;
  };
  const cells = [];
  let cursor = 1000;
  for (let i = 0; i < 30; i++) {
    const plan = i ? PLAN[(i - 1) % 10] : '시조';
    const len = plan === '숙부 찬탈' ? 4 + (mix(i, 1) % 5) : plan === '복위' ? 8 + (mix(i, 1) % 8) : 22 + (mix(i, 1) % 17);
    const start = cursor;
    const end = cursor + len;
    cursor = end;
    const prev = i ? cells[i - 1].p : null;
    let p;
    if (plan === '복위') p = cells[i - 2].p;
    else {
      let father = prev;
      if (plan === '동생 선양') father = prev.father || prev;
      if (plan === '숙부 찬탈') father = (prev.father && prev.father.father) || prev.father || prev;
      const name = given(i);
      p = person({ kind: 'leader', name, father, cell: i });
      p.birth = Math.max(start - 22 - (mix(i, 2) % 10), father ? father.birth + 18 : -Infinity);
      if (father) p.parents.push({ p: father, as: '부' });
      if (father) father.kids.push(p);
    }
    const acc = {
      시조: null,
      세습: { kin: '아들', how: '세습' },
      선양: { kin: '아들', how: '선양' },
      '동생 선양': { kin: '동생', how: '선양' },
      '숙부 찬탈': { kin: '숙부', how: '찬탈' },
      복위: { kin: '조카', how: '복위' },
      '관계 미상': [{ kin: '미상', how: '세습' }, '미상', { kin: '미상', how: '선출', from: '미상' }][Math.floor((i - 1) / 10)],
      '방식 미상': { kin: '아들', how: '미상' },
      비움: null,
      '두 나라': { kin: '아들', how: '세습' },
    }[plan];
    cells.push({ i, plan, p, start, end, acc, again: plan === '복위' });
  }
  const endA = cursor;
  const LAST_BIRTH = endA - 30;
  const firstCell = p => cells.find(c => c.p === p);

  /* ② 집안 — 본가 · 파 14 · 가문 밖 6 */
  const houses = [{ ...ROOT, founderOf: cells[0].p, track: POLITY_A.track, people: POLITY_A.people, tags: ['왕실'] }];
  const outside = OUTSIDE.map(([seat, surname], k) => ({ id: `kin-out-${k + 1}`, name: `${seat} ${surname}씨`, surname, seat }));
  const paHouse = []; // 파 번호 → 가문

  /* ③ 사람 — 지도자의 아들 · 딸부터 너비 우선으로, 크기(N)에 닿을 때까지. 딸은 대를 잇지 않고(외손만 가끔), 배우자는 가문 밖 집안 */
  let figures = 0;
  let seq = 100;
  const stats = { 크기: N, 판: K.label, 가문: house === 'written' ? '가문 사람마다 적음' : '물려받기에 맡김', 고리: cycle ? 1 : 0, 지도자칸: 0, 사람: 0, 가문사람: 0, 아들: 0, 딸: 0, 배우자: 0, 외손: 0, 양자: 0, 건너뜀: 0, 공유미상: 0, 빈고리: 0, 부모둘다가문안: 0, 파조: 0, 생몰없음: 0, 직함: 0, 명칭목록: 0, 형제순서: 0, 깊이: 0 };
  const figure = o => {
    figures++;
    return person(o);
  };
  const spouseOf = m => {
    const [seat, surname] = OUTSIDE[mix(m.i, 42) % OUTSIDE.length];
    const out = outside.find(h => h.surname === surname && h.seat === seat);
    const s = figure({ kind: 'spouse', name: `${surname} ${given(seq++)}`, house: out, birth: m.birth + (mix(m.i, 43) % 7) - 3 });
    m.spouses.push(s);
    stats.배우자++;
    return s;
  };
  const queue = cells.filter(c => !c.again).map(c => c.p);
  /* 지도자의 배우자(가문 밖) — 40%. 크기 안에 셈하려고 아들 · 딸보다 먼저 */
  for (const p of queue) if (mix(p.i, 44) % 100 < 40) spouseOf(p);
  let head = 0;
  let prevFather = null;
  const recentDaughters = [];
  while (figures < N && head < queue.length) {
    const f = queue[head++];
    if (f.birth + 20 > LAST_BIRTH) continue;
    const isLeader = f.kind === 'leader';
    let sons = isLeader ? 2 + (mix(f.i, 11) % 3) : SONS[mix(f.i, 11) % 10];
    const daughters = isLeader ? 1 + (mix(f.i, 12) % 2) : DAUGHTERS[mix(f.i, 12) % 10];
    const paOf = isLeader ? FOUNDER_CELLS.indexOf(f.cell) : f.foundsPa != null && f.foundsPa < 4 ? 10 + f.foundsPa : -1;
    if (paOf >= 0 || f.foundsPa != null) sons = Math.max(sons, 2);
    for (let c = 0; c < sons + daughters && figures < N; c++) {
      const female = c >= sons;
      const birth = f.birth + 21 + (mix(f.i, 13 + c) % 9) + c * 2;
      const kid = figure({ kind: 'member', female, father: f, birth, depth: (f.depth || 0) + 1, sib: c });
      f.kids.push(kid);
      stats[female ? '딸' : '아들']++;
      stats.깊이 = Math.max(stats.깊이, kid.depth);
      const r = mix(kid.i, 31) % 1000;
      const founder = !female && c === 0 && paOf >= 0;
      if (founder) {
        kid.foundsPa = paOf;
        const parentHouse = paOf < 10 ? houses[0] : paHouse[paOf - 10];
        const h = { id: `kin-pa-${paOf + 1}`, name: `${PA[paOf]}${paOf < 10 ? '대군' : '군'}파`, parent: parentHouse.id, founderOf: kid, under: parentHouse };
        paHouse[paOf] = h;
        houses.push(h);
        kid.pa = h;
        kid.title = `${PA[paOf]}${paOf < 10 ? '대군' : '군'}`;
        stats.파조++;
        kid.parents.push({ p: f, as: '부' });
      } else if (!female && r < 30 && prevFather && prevFather !== f && !prevFather.unknown) {
        kid.parents.push({ p: f, as: '생부' }, { p: prevFather, as: '양부' });
        kid.adoptive = prevFather;
        stats.양자++;
      } else if (!female && r < 40 && f.parents[0] && f.parents[0].p && (f.parents[0].as === '부' || f.parents[0].as === '생부')) {
        kid.parents.push({ p: f.parents[0].p, as: '후손', gen: 2 }); // 아버지 대를 건너뛰고 할아버지의 2대손으로만 적음
        stats.건너뜀++;
      } else if (!female && r < 55 && !isLeader) {
        kid.unknown = true;
        kid.parents.push({ p: f, as: '부' });
        stats.공유미상++;
      } else if (!female && r < 60) {
        kid.birth += 25;
        kid.parents.push({ unknown: true, as: '부' }, { p: f, as: '후손', gen: 2 });
        stats.빈고리++;
      } else if (!female && r < 65 && recentDaughters.length) {
        const d = recentDaughters.find(d => d.father !== f && d.father !== f.father && Math.abs(d.birth - f.birth) <= 30);
        kid.parents.push({ p: f, as: '부' });
        if (d) {
          kid.parents.push({ p: d, as: '모' });
          stats.부모둘다가문안++;
        }
      } else kid.parents.push({ p: f, as: '부' });
      kid.name = kid.unknown ? '미상' : `${ROOT.surname} ${given(seq++)}`;
      if (isLeader) kid.role = female ? '공주' : founder || c === 0 ? '대군' : '군';
      else if (!kid.unknown && mix(kid.i, 71) % 10 < 2) kid.role = ROLES[mix(kid.i, 72) % ROLES.length];
      if (!kid.unknown && (founder || mix(kid.i, 81) % 10 < 3)) kid.alias = founder ? kid.title : `${kid.name.slice(ROOT.surname.length + 1)}재`;
      if (!female) queue.push(kid);
      else {
        recentDaughters.unshift(kid);
        if (recentDaughters.length > 8) recentDaughters.pop();
      }
      if (figures < N && !kid.unknown && mix(kid.i, 41) % 100 < 40) spouseOf(kid);
      /* 외손 — 딸의 1%: 가문 밖 남편과의 자식(가문 밖 잎) */
      if (female && figures < N && mix(kid.i, 51) % 100 < 1 && kid.birth + 20 <= LAST_BIRTH) {
        const s = kid.spouses[0] || (figures < N - 1 ? spouseOf(kid) : null);
        if (s) {
          const [surname] = s.name.split(' ');
          const o = figure({ kind: 'outer', name: `${surname} ${given(seq++)}`, birth: kid.birth + 24, depth: kid.depth + 1, house: s.house });
          o.parents.push({ p: s, as: '부' }, { p: kid, as: '모' });
          kid.kids.push(o);
          stats.외손++;
        }
      }
    }
    prevFather = f; // 줄에는 아들만 들므로 다음 사람의 양부 후보(사촌 · 형제)
  }
  if (figures < N) throw new Error(`사람이 ${N}명까지 자라지 않았습니다(${figures}명에서 멈춤) — 생성 규칙을 확인합니다`);

  /* 가문(파) — 생성기가 아는 답: 파조는 제 파, 양자는 양부의 가문, 그 밖에는 부계(나무 아버지) — 이름 미상도 아버지의 가문 */
  const houseOf = p => {
    if (p.houseMemo !== undefined) return p.houseMemo;
    let h = null;
    if (p.kind === 'leader') h = houses[0];
    else if (p.kind === 'spouse' || p.kind === 'outer') h = p.house || null;
    else if (p.pa) h = p.pa;
    else if (p.adoptive) h = houseOf(p.adoptive);
    else if (p.father) h = houseOf(p.father);
    p.houseMemo = h;
    return h;
  };

  /* 고리 1건 — 본가 사람 A의 부모 줄에 A의 증손 Z를 양부로 */
  let cycleNote = null;
  if (cycle) {
    const chainUp = p => (p.parents.find(x => x.p && x.as !== '양부' && x.as !== '모') || {}).p || null;
    for (const z of P) {
      if (z.kind !== 'member' || z.unknown) continue;
      const a1 = chainUp(z);
      const a2 = a1 && chainUp(a1);
      const a3 = a2 && chainUp(a2);
      if (!a3 || a3.kind !== 'member' || a3.unknown || a1.kind !== 'member' || a2.kind !== 'member') continue;
      if (houseOf(a3) !== houses[0] || houseOf(z) !== houses[0]) continue; // 본가 안의 고리 — 본가 세계표(familyOf · 뼈대)가 고리를 만나게
      a3.parents.push({ p: z, as: '양부', note: '고리 시험 — 증손을 양부로 적음' });
      cycleNote = { 사람: a3.name, 양부: z.name };
      break;
    }
    if (!cycleNote) throw new Error('고리를 놓을 4대 사슬을 찾지 못했습니다');
  }

  /* ④ id · 가리키는 글 */
  let fseq = 0;
  for (const p of P) if (p.kind !== 'leader') p.id = `k${(fseq++).toString(36).padStart(4, '0')}`;
  const cellRef = c => `${POLITY_A.name}:${c.p.name}@${c.start}`;
  const refOf = p => {
    if (p.kind === 'leader') return K.byName ? p.name : cellRef(firstCell(p));
    if (p.unknown) return p.id; // 이름 미상의 공유 자리는 이름 판에서도 id로(설계 2-4 다)
    return K.byName ? p.name : p.id;
  };
  const rowsOf = p =>
    p.parents.map(x => {
      const o = { who: x.unknown ? '미상' : refOf(x.p), as: x.as };
      if (x.gen) o.gen = x.gen;
      if (x.note) o.note = x.note;
      return o;
    });

  /* ⑤ 원문 */
  const periodA = {
    id: POLITY_A.id, track: POLITY_A.track, name: POLITY_A.name, people: POLITY_A.people, house: ROOT.id, start: 1000, end: endA, tags: ['가상 왕조'],
    leaders: cells.map(c => {
      const o = { name: c.p.name, start: c.start, end: c.end };
      if (c.again) o.person = cellRef(firstCell(c.p));
      if (c.acc) o.accession = c.acc;
      if (!c.again) {
        if (c.p.parents.length) o.parents = rowsOf(c.p);
        if (c.p.spouses.length) o.spouses = c.p.spouses.map(s => ({ who: refOf(s) }));
      }
      return o;
    }),
  };
  const twin = cells.filter(c => c.plan === '두 나라');
  const periodB = {
    id: POLITY_B.id, track: POLITY_B.track, name: POLITY_B.name, people: POLITY_B.people, start: twin[0].start - 40, end: twin[twin.length - 1].end + 40,
    leaders: twin.map(c => ({ name: c.p.name, start: c.start + 1, end: c.end, person: cellRef(c), accession: { kin: '무관', how: '추대' } })),
  };
  const figs = [];
  for (const p of P) {
    if (p.kind === 'leader') continue;
    const o = { id: p.id, track: POLITY_A.track, name: p.name };
    if (K.lineage) o.lineageOnly = true;
    if (p.role) {
      o.role = p.role;
      stats.직함++;
    }
    const dated = !K.lineage || p.pa || (!p.unknown && (mix(p.i, 61) & 1) === 0);
    if (dated) {
      o.birth = p.birth;
      if (!p.unknown) o.death = p.birth + 30 + (mix(p.i, 62) % 50);
    } else {
      stats.생몰없음++;
      if (p.kind === 'member' && p.sib != null) {
        o.order = p.sib + 1;
        stats.형제순서++;
      }
    }
    const h = houseOf(p);
    if (h && (house === 'written' || p.kind === 'spouse')) o.house = h.id;
    if (p.alias) {
      o.names = [{ text: p.alias, kind: p.pa ? '군호' : '호' }];
      stats.명칭목록++;
    }
    if (p.parents.length) o.parents = rowsOf(p);
    if (p.spouses.length) o.spouses = p.spouses.map(s => ({ who: refOf(s) }));
    figs.push(o);
  }
  stats.지도자칸 = cells.length + periodB.leaders.length;
  stats.사람 = figs.length;
  stats.가문사람 = P.filter(p => p.kind === 'member').length;
  if (cycleNote) stats.고리자리 = cycleNote;

  const tag = `${house === 'inherit' ? '-inherit' : ''}${cycle ? '' : '-nocycle'}`;
  const pack = {
    format: 'history-timeline-dlc',
    formatVersion: 3,
    id: `kin-sample-${N}-${kind}${tag}`,
    name: `가상 대가족 · ${sizeWord(N)} 명 (${K.label}${house === 'inherit' ? ' · 가문 물려받기' : ''}${cycle ? '' : ' · 고리 없음'})`,
    version: '1.0.0',
    author: '가상 견본 — scripts/kin-sample.mjs',
    description: '승계표 · 세계표 · 가문의 성능과 모양을 재는 가상 대가족입니다. 이름과 나라는 모두 지어낸 것이고, 같은 수로 만들면 늘 같은 바이트가 나옵니다.',
    tags: ['가상 견본', '계보', '측정'],
    tracks: [
      { id: POLITY_A.track, name: '가람', color: '#c8b193' },
      { id: POLITY_B.track, name: '물마루', color: '#9dbea8' },
    ],
    peoples: [
      { id: 'kin-nuri', name: POLITY_A.people },
      { id: 'kin-mulmaru-people', name: POLITY_B.people },
    ],
    houses: [
      ...houses.map(h => {
        const o = { id: h.id, name: h.name };
        if (h.surname) Object.assign(o, { surname: h.surname, seat: h.seat });
        if (h.parent) o.parent = h.parent;
        o.founder = refOf(h.founderOf);
        if (h.track) Object.assign(o, { track: h.track, people: h.people, tags: h.tags });
        return o;
      }),
      ...outside.map(h => ({ id: h.id, name: h.name, surname: h.surname, seat: h.seat })),
    ],
    periods: [periodA, periodB],
    figures: figs,
  };
  const json = serialize(pack);
  return {
    pack,
    json,
    file: `kin-${N}-${kind}${tag}.json`,
    stats,
    tree: { persons: P, cells, houses: [...houses, ...outside], polity: POLITY_A, root: ROOT.id },
  };
}

/** 바이트가 늘 같은 글 — 최상위 열쇠 한 줄씩, 객체 목록은 항목 하나에 한 줄(줄 끝 LF) */
function serialize(pack) {
  const keys = Object.keys(pack);
  const lines = ['{'];
  keys.forEach((k, ki) => {
    const v = pack[k];
    const comma = ki < keys.length - 1 ? ',' : '';
    if (Array.isArray(v) && v.length && v[0] && typeof v[0] === 'object') {
      lines.push(`  ${JSON.stringify(k)}: [`);
      v.forEach((x, i) => lines.push(`    ${JSON.stringify(x)}${i < v.length - 1 ? ',' : ''}`));
      lines.push(`  ]${comma}`);
    } else lines.push(`  ${JSON.stringify(k)}: ${JSON.stringify(v)}${comma}`);
  });
  lines.push('}');
  return lines.join('\n') + '\n';
}

/** packs/ · samples/ 아래 모든 파일의 sha256 지문(상대 경로 → 값) */
export function fingerprint(root) {
  const out = {};
  const walk = dir => {
    for (const ent of fs.readdirSync(path.join(root, dir), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
      const rel = `${dir}/${ent.name}`;
      if (ent.isDirectory()) walk(rel);
      else out[rel] = createHash('sha256').update(fs.readFileSync(path.join(root, rel))).digest('hex');
    }
  };
  for (const d of ['packs', 'samples']) if (fs.existsSync(path.join(root, d))) walk(d);
  return out;
}
export const sha256 = s => createHash('sha256').update(s).digest('hex');

/* ---------- 명령 ---------- */
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const args = process.argv.slice(2);
  const opt = (name, def) => {
    const i = args.indexOf(name);
    return i >= 0 && args[i + 1] != null ? args[i + 1] : def;
  };
  const sizes = String(opt('--size', SIZES.join(','))).split(',').map(sizeOf);
  const kinds = String(opt('--kind', Object.keys(KINDS).join(','))).split(',').map(s => s.trim());
  const house = opt('--house', 'written');
  const cycle = !args.includes('--no-cycle');
  const twice = args.includes('--twice');
  const out = path.resolve(opt('--out', path.join(root, '배포/측정/가상-대가족')));
  const before = fingerprint(root);
  fs.mkdirSync(out, { recursive: true });
  const list = [];
  let bad = 0;
  for (const size of sizes)
    for (const kind of kinds) {
      const t0 = performance.now();
      const a = kinSample({ size, kind, house, cycle });
      const ms = performance.now() - t0;
      const hash = sha256(a.json);
      let again = null;
      if (twice) {
        again = sha256(kinSample({ size, kind, house, cycle }).json);
        if (again !== hash) bad++;
      }
      fs.writeFileSync(path.join(out, a.file), a.json);
      const back = sha256(fs.readFileSync(path.join(out, a.file)));
      if (back !== hash) bad++;
      list.push({ 파일: a.file, 바이트: Buffer.byteLength(a.json), sha256: hash, ...(twice ? { 두번째: again === hash ? '같음' : `다름 ${again}` } : {}), 짓기ms: Math.round(ms), 셈: a.stats });
      console.log(`${a.file}  ${(Buffer.byteLength(a.json) / 1048576).toFixed(2)}MB  사람 ${a.stats.사람.toLocaleString('ko-KR')} · 깊이 ${a.stats.깊이}대 · ${Math.round(ms)}ms  sha256 ${hash.slice(0, 16)}${twice ? (again === hash ? '  두 번 같음' : '  두 번 다름!') : ''}`);
    }
  fs.writeFileSync(path.join(out, '목록.json'), JSON.stringify({ 씨앗: SEED, 파일: list }, null, 2) + '\n');
  const after = fingerprint(root);
  const same = JSON.stringify(before) === JSON.stringify(after);
  console.log(`packs/ · samples/ 지문 ${Object.keys(before).length}개 — 처음 = 끝: ${same ? '같음' : '다름!'}`);
  if (!same || bad) {
    console.error(bad ? `같은 수인데 바이트가 다른 파일 ${bad}개` : 'packs/ · samples/가 바뀌었습니다');
    process.exit(1);
  }
  console.log(`문제 없음 — ${out}`);
}
