/* 역사 연표 — 메이커 검사 창의 형식 4 검사 (메이커만 · 리메이크 5단계 과제 8)
 *
 * 작업본(옛 꼴 — periods …)에 정규화(HT.normalizePack)가 지켜 둔 형식 4의 칸 — 객체 종류 type · 정통성 status · 중요도 importance · 소속 줄의 으뜸 main ·
 * 직위 줄 더 offices[] · 두 자리의 빌림 leadersFrom · cabinetsFrom · 실권 power[] — 가운데 **파일 검사가 보지 못하는 것**을 검사 창에 올립니다.
 * 정규화가 이미 내는 경고(모르는 종류 · 정통성 · 중요도 범위 · 출처 없는 빌림 · 상대 없는 실권 · from과 cells가 함께)는 그대로 창에 오르므로 여기서 겹쳐 내지 않습니다.
 *
 *   걸음 1 — 참조 · 고리(과제 1 걸음 4의 규칙 — HT.F4.down의 알림과 같은 뜻을 작업본에서):
 *     · 빌림(offices[].from · leadersFrom · cabinetsFrom)의 출처 "객체 id" · "객체 id/직위 이름"과 실권의 상대(power[].over)가 작업본 · 불러온 팩의 객체(id 또는 이름)로
 *       풀리지 않으면 **확인할 것**(notes — 다른 팩의 것일 수 있어 경고가 아님) · 객체는 찾았는데 그 직위 줄이 없으면 확인할 것
 *     · 빌림이 고리를 이루면(가 → 나 → 가 · 자기 자신) **경고** · 지도자 · 내각 자리에 칸을 적어 두고 빌려 보기를 켠 채면(저장 때 그 칸이 빠짐) 경고 · 실권의 상대가 자기 자신이면 경고
 *     · 소속 줄의 으뜸(main)이 둘 이상이면 경고 · 옛 종속 종류(kind)와 객체 종류(type)를 함께 적고 소속이 없으면 저장 때 '미상' 섬김 줄이 소속 줄로 남는다는 확인할 것(계획 문서 과제 3의 알게 된 것)
 *     · 파일을 열 때 다리(HT.F4.down)가 낸 알림(모르는 종류 · 그리는 자리 · 뺀 직위 줄 · 그릇 고리 · 주기 줄 하나만 …)은 메이커가 작업본의 f4notes에 두므로 **알림**으로 올립니다(토스트는 사라지므로)
 *   걸음 0 — 끝이 빈 객체(시작만 있고 끝 · 미정 · 현재까지가 비면 점 띠가 됨)는 경고(5단계 잔여 과제 6)
 *   걸음 2 — 종류에 맞지 않는 칸(설계 3-1 · 3-2 · 3-5 · DLC-형식.md '형식 4' 절의 표):
 *     · 시대(era) 종류에 지도자 · 내각 · 직위 줄 더 · 빌림 · 실권이 남아 있으면 경고 — 저장(HT.F4.toFile)은 이 칸을 빼지 않으므로 '그리지 않음'으로 적습니다
 *     · 사람의 칸(생몰 · 다른 이름 · 역할 · 부모 · 배우자 …) · 시대 그릇의 칸(label · default · host · members) · 기관 · 단체의 칸(scale · subtype · persons)이 객체(periods)에 남아 있으면
 *       정규화가 버리므로 '저장 때 빠짐' 경고
 *
 * 밖으로 내는 것: HT.makerCheck.f4Checks(draft, others) → { warnings, notes } — 한 줄은 검사 창의 다른 줄과 같은 꼴 { msg, kind: 'periods', index }(누르면 그 항목으로) ·
 * 파일 전체의 알림은 kind 'info'(DLC 정보로) · 확인할 것 줄은 confirm: true(창이 낱말을 '확인할 것'으로). draft = 작업본(옛 꼴 · 정규화 전) · others = 불러온 팩(정규화한 것).
 * 순수 함수(화면 · 메이커 부품을 부르지 않음) — scripts/maker-check-check.mjs가 노드에서 검사합니다. js/maker.js의 buildModel이 부릅니다. */
(() => {
  'use strict';
  const HT = window.HT || (window.HT = {});
  const arr = v => (Array.isArray(v) ? v : v == null || v === '' ? [] : [v]);
  const str = v => (v == null ? '' : String(v).trim());
  const isObj = v => v && typeof v === 'object' && !Array.isArray(v);
  const canon = v => JSON.stringify(v, (k, x) => (isObj(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const LEADERS = '지도자';
  const CABINETS = '내각';
  const WORD = '객체'; // 검사 창의 항목 낱말(5단계 과제 3에서 「시대」 → 「객체」)
  /* 객체 목록이 되는 작업본의 표(참조를 찾는 범위) — 사람(figures)은 빌림 · 실권의 상대가 아닙니다 */
  const OBJECT_LISTS = ['periods', 'scopes', 'epochs', 'organs', 'groups'];
  /* 종류에 맞지 않는 칸(걸음 2) — [칸, 이름표] */
  const PERSON_ONLY = [['birth', '생년'], ['death', '몰년'], ['aka', '다른 이름'], ['role', '역할'], ['parents', '부모'], ['spouses', '배우자'], ['lineageOnly', '계보 전용'], ['service', '활동 기록']];
  const CONTAINER_ONLY = [['label', '시대 그릇의 성격(label)'], ['default', '처음부터 켬(default)'], ['host', '상징적 본국(host)'], ['members', '밖의 구성원(members)']];
  const OTHER_ONLY = [['scale', '기관의 크기(scale)'], ['subtype', '세부 종류(subtype)'], ['persons', '구성원 사람(persons)']];
  const ERA_UNFIT = [['leaders', '지도자 칸'], ['cabinets', '내각 칸'], ['leadersFrom', '지도자 줄의 빌림'], ['cabinetsFrom', '내각 줄의 빌림'], ['offices', '직위 줄 더'], ['power', '실권']];
  const has = (o, k) => o[k] != null && o[k] !== '' && !(Array.isArray(o[k]) && !o[k].length);

  const nameOf = x => str(x && (x.name ?? x.title)) || str(x && x.id) || '?';
  /** 작업본 항목의 객체 종류 id — 적어 둔 type이 옛 종류보다 앞섭니다(다리 objectOf와 같음) */
  const typeOf = p => {
    const own = HT.F4.typeId(p.type);
    if (own && own !== 'person') return own;
    return HT.F4.typeOfKind(HT.polityKindId(p.kind) || str(p.kind) || 'state');
  };
  const typeName = id => ((HT.F4.TYPES.find(t => t.id === id) || {}).name || id);
  /** 빌림 적기(leadersFrom · cabinetsFrom · 직위 줄의 from) → { from, name? } 또는 null */
  const borrowOf = v => {
    if (v == null || v === '') return null;
    const from = str(typeof v === 'string' ? v : isObj(v) ? v.from : '');
    return from ? { from, name: isObj(v) ? str(v.name) : '' } : null;
  };
  /** 항목(작업본의 옛 꼴이거나 정규화한 것)의 직위 줄 — 형식 4로 올린 뒤의 이름으로: 빌린 자리는 적은 이름(없으면 '지도자' · '내각'), 셋째 줄부터는 offices의 이름.
      한 줄은 { name, slot?: 'leaders' | 'cabinets', cells, from, index?(offices의 차례) } */
  function linesOf(item) {
    const out = [];
    const slot = (key, cells, word) => {
      const b = borrowOf(item[key]);
      if (!b && !arr(cells).length) return;
      out.push({ name: b && b.name ? b.name : word, slot: key === 'leadersFrom' ? 'leaders' : 'cabinets', word, cells: arr(cells), from: b ? b.from : '' });
    };
    slot('leadersFrom', item.leaders || item.reigns, LEADERS);
    slot('cabinetsFrom', item.cabinets, CABINETS);
    arr(item.offices).forEach((f, index) => {
      if (!isObj(f)) return;
      const b = borrowOf(f.from);
      out.push({ name: str(f.name), cells: arr(f.cells), from: b ? b.from : '', index });
    });
    return out;
  }
  /** 빌릴 직위 줄 고르기 — 다리(HT.F4.down의 officeFrom)와 같은 규칙: 이름을 적지 않으면 '지도자' 줄, 없으면 첫 줄 */
  const pickLine = (lines, want) => (want ? lines.find(l => l.name === want) : lines.find(l => l.name === LEADERS) || lines[0]) || null;

  /** 참조를 찾는 색인 — 작업본(id가 이름보다 앞섬 · 표 차례대로)과 불러온 팩("팩 id/객체 id"로도) */
  function indexOf(draft, others) {
    const byKey = new Map();
    const put = (key, hit) => {
      const k = str(key);
      if (k && !byKey.has(k)) byKey.set(k, hit);
    };
    const own = [];
    for (const list of OBJECT_LISTS) arr(draft[list]).forEach((item, index) => { if (isObj(item)) own.push({ item, list, index, own: true, label: nameOf(item) }); });
    for (const h of own) put(h.item.id, h);
    for (const h of own) put(h.item.name ?? h.item.title, h);
    for (const pack of arr(others)) {
      if (!isObj(pack)) continue;
      const got = [];
      for (const list of OBJECT_LISTS) for (const item of arr(pack[list])) if (isObj(item)) got.push({ item, list, pack: pack.id, own: false, label: `${nameOf(item)}(${pack.name || pack.id})` });
      for (const h of got) put(h.item.id, h);
      for (const h of got) put(h.item.name ?? h.item.title, h);
      for (const h of got) put(`${pack.id}/${str(h.item.id)}`, h);
    }
    return byKey;
  }
  /** 빌림의 출처 "객체 id" · "객체 id/직위 이름" 풀기 → { hit, want } · 못 풀면 { key } */
  function resolveFrom(byKey, ref) {
    const whole = byKey.get(ref);
    if (whole) return { hit: whole, want: '' };
    const cut = ref.indexOf('/');
    if (cut < 0) return { key: ref };
    const key = ref.slice(0, cut).trim();
    const want = ref.slice(cut + 1).trim();
    const hit = byKey.get(key);
    if (hit) return { hit, want };
    /* "팩 id/객체 id/직위 이름" */
    const cut2 = want.indexOf('/');
    if (cut2 >= 0) {
      const deep = byKey.get(`${key}/${want.slice(0, cut2).trim()}`);
      if (deep) return { hit: deep, want: want.slice(cut2 + 1).trim() };
    }
    return { key };
  }

  /**
   * 형식 4 칸의 검사 — 돌려주는 값 { warnings, notes } (위 머리 주석). draft = 작업본(옛 꼴) · others = 불러온 팩(정규화한 것 — 참조를 찾는 범위)
   */
  function f4Checks(draft, others = []) {
    const out = { warnings: [], notes: [] };
    if (!isObj(draft) || !HT.F4) return out;
    const byKey = indexOf(draft, others);
    /* 파일을 열 때의 다리 알림(메이커 openFile이 작업본의 f4notes에 둠) */
    for (const m of arr(draft.f4notes)) if (str(m)) out.notes.push({ msg: `파일을 열 때(형식 4 → 옛 꼴): ${str(m)}`, kind: 'info' });
    arr(draft.periods).forEach((p, index) => {
      if (!isObj(p)) return;
      const label = `${WORD} #${index + 1} "${nameOf(p)}"`;
      const warn = msg => out.warnings.push({ msg: `${label}: ${msg}`, kind: 'periods', index });
      const note = (msg, confirm) => out.notes.push(Object.assign({ msg: `${label}: ${msg}`, kind: 'periods', index }, confirm ? { confirm: true } : null));
      const type = typeOf(p);
      const self = { item: p, list: 'periods', index, own: true };
      const lines = linesOf(p);
      /* ⓪ 끝이 빈 객체(5단계 잔여 과제 6): 정규화가 말없이 받아 한 해짜리 점 띠(시작 = 끝)가 됩니다(5단계 과제 9의 가상 팩 교단) — 시작은 있는데 끝 · 미정 · 현재까지가 모두 비었을 때 */
      if ((has(p, 'start') || p.startUnknown) && !has(p, 'end') && p.ongoing !== true && !p.endUnknown)
        warn('끝이 비어 있어 한 해짜리 점 띠(시작 = 끝)로 그려집니다 — 끝을 적거나 미정 · 현재까지를 고르세요.');
      /* ① 빌림 — 출처 · 직위 줄 · 고리 · 적어 둔 칸 */
      for (const line of lines) {
        if (!line.from) continue;
        const lineWord = line.slot ? `${line.word} 줄의 빌림${line.name !== line.word ? `(«${line.name}»)` : ''}` : `직위 줄 «${line.name || line.from}»`;
        const r = resolveFrom(byKey, line.from);
        if (!r.hit) {
          note(`${lineWord}이(가) 빌려 올 객체 «${r.key}»을(를) 작업본 · 불러온 팩에서 찾지 못했습니다 — 다른 팩의 객체면 그 팩을 불러오고, 아니면 id · 이름을 확인하세요.`, true);
          continue;
        }
        const target = pickLine(linesOf(r.hit.item), r.want);
        if (!target) {
          note(`${lineWord}이(가) 빌려 올 직위 줄 «${r.want || LEADERS}»을(를) 객체 «${r.hit.label}»에서 찾지 못했습니다.`, true);
          continue;
        }
        /* 고리: 출처의 줄이 또 빌리면 따라가며, 이 줄 · 지나온 줄(같은 항목의 같은 이름 줄)로 돌아오면 고리 */
        const path = [`${nameOf(p)}/${line.name || LEADERS}`];
        const seen = new Map([[p, new Set([line.name || LEADERS])]]);
        let cur = { hit: r.hit, line: target };
        let cycle = '';
        while (cur && cur.line.from) {
          const ln = cur.line.name || LEADERS;
          path.push(`${cur.hit.label}/${ln}`);
          const got = seen.get(cur.hit.item) || new Set();
          if (got.has(ln)) {
            cycle = path.join(' → ');
            break;
          }
          got.add(ln);
          seen.set(cur.hit.item, got);
          const n = resolveFrom(byKey, cur.line.from);
          const nl = n.hit ? pickLine(linesOf(n.hit.item), n.want) : null;
          cur = nl ? { hit: n.hit, line: nl } : null;
        }
        if (cycle) {
          warn(`${lineWord}이(가) 고리를 이룹니다(${cycle}) — 서고는 이 줄을 그리지 못하고, 파일을 다시 열 때 다리가 이 줄을 뺍니다.`);
          continue;
        }
        /* 자리에 칸을 적어 두고 빌려 보기를 켠 채 — 출처의 칸을 그대로 복제한 것(파일을 열 때 다리가 둔 것)은 알리지 않고, 다른 칸이면 저장 때 빠진다고 */
        if (line.slot && line.cells.length && r.hit.own && canon(line.cells) !== canon(target.cells)) warn(`${line.word} 칸 ${line.cells.length}개가 적혀 있지만 빌려 보기가 켜져 있어 저장 때 그 칸은 빠지고 «${r.hit.label}»의 «${target.name || LEADERS}» 칸을 봅니다 — 칸을 지키려면 빌려 보기를 끄세요.`);
      }
      /* ② 실권의 상대 */
      arr(p.power).forEach((c, j) => {
        const over = isObj(c) ? str(c.over) : '';
        if (!over) return; // 상대 없음(배열 꼴도)은 정규화가 알림
        const hit = byKey.get(over);
        if (!hit) return note(`실권 ${j + 1}번째 줄의 상대 «${over}»을(를) 작업본 · 불러온 팩에서 찾지 못했습니다 — 실권은 쥔 쪽에만 적고 빼앗긴 객체를 상대로 가리킵니다.`, true);
        if (hit.item === self.item) warn(`실권 ${j + 1}번째 줄의 상대가 자기 자신입니다 — 빼앗긴 상대 객체를 가리키세요.`);
      });
      /* ③ 소속 줄의 으뜸 · 종속 종류와 객체 종류 */
      const entries = arr(p.partOf).map(e => (typeof e === 'string' ? { polity: e } : isObj(e) ? e : null)).filter(Boolean);
      const mains = entries.filter(e => e.main === true).length;
      if (mains > 1) warn(`소속 줄에 으뜸이 ${mains}개입니다 — 구조 나무 · 서고는 첫 것만 기준으로 삼습니다.`);
      const kind = HT.polityKindId(p.kind) || str(p.kind);
      const own = HT.F4.typeId(p.type);
      if (!entries.length && kind && kind !== 'state' && HT.relationOfKind(kind) && own && own !== 'state' && own !== 'person' && HT.F4.typeOfKind(kind) !== own) {
        const kn = (HT.POLITY_KINDS.find(k => k.id === kind) || {}).name || kind;
        note(`옛 종류 «${kn}»와 객체 종류 «${typeName(own)}»을(를) 함께 적고 소속이 없어, 저장하면 상대 '미상'의 섬김 줄이 소속 줄로 남습니다 — 소속에 상대를 적거나 종류를 국가로 두세요.`);
      }
      /* ④ 종류에 맞지 않는 칸(걸음 2) */
      if (type === 'era') {
        const left = ERA_UNFIT.filter(([k]) => has(p, k)).map(([, w]) => w);
        if (left.length) warn(`시대 종류에는 ${left.join(' · ')}이(가) 맞지 않습니다 — 저장한 파일에는 남지만 그리지 않습니다(시대는 그릇 · 이름표). 종류를 바꾸거나 칸을 비우세요.`);
      }
      const person = PERSON_ONLY.filter(([k]) => has(p, k)).map(([, w]) => w);
      if (person.length) warn(`${person.join(' · ')}은(는) 사람의 칸이라 저장 때 빠집니다 — 사람은 인물 표에 적습니다.`);
      const other = CONTAINER_ONLY.concat(OTHER_ONLY).filter(([k]) => has(p, k)).map(([, w]) => w);
      if (other.length) warn(`${other.join(' · ')}은(는) ${typeName(type)} 객체에 없는 칸이라 저장 때 빠집니다.`);
    });
    return out;
  }

  HT.makerCheck = { f4Checks, linesOf, resolveFrom };
})();
