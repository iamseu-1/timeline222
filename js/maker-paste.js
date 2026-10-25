/* DLC 메이커 — 줄 묶음 붙여넣기 (docs/구상-연표-확장-10건.md 3-5 (나) 2).
   시대 편집 창의 줄 목록(지도자 · 내각 · 연호 · 도읍 · 지위 변천)마다 있는 '여러 줄 한꺼번에 붙여넣기' 글 칸에
   엑셀 · 표 계산 프로그램에서 복사한 여러 열(탭으로 나뉜 열 — TSV)을 넣고 [줄을 칸으로 추가]를 누르면,
   열 맞추기 미리 보기 창이 열립니다: 첫 줄이 머리글(칸 이름)인지 짐작하고, 열마다 받을 칸을 고른 뒤 [넣기].
   - 머리글은 칸 이름(대표 이름 · 대수 · 묘호 · 시호 · 이름 · 시작 · 끝 · 왕조 · 지위 · 가문 · 메모 …)과 같으면 알아봅니다.
     머리글이 없으면 열의 내용(날짜 · 기간 · 대수 · 역할)으로 짐작합니다 — 미리 보기에서 언제든 바꿀 수 있습니다.
   - 날짜는 기존 날짜 읽기(HT.readDate — 기원전 · 음력 · 날짜 · 세기)와 "미정"을 그대로 씁니다.
   - 읽지 못한 줄은 미리 보기에서 빨갛게 표시하고 까닭을 적으며, 넣지 않고 글 칸에 남겨 둡니다(고쳐서 다시 넣도록).
   - 탭이 없는 지금의 한 줄 글 꼴("이름 시작~끝 메모")은 예전 길(HT.textToCells)이 그대로 받습니다 — 이 파일은 손대지 않음(뒤 호환).
     첫 줄이 쉼표로 나뉜 머리글(이름,시작,끝 …)이면 쉼표 표(CSV)로도 받습니다.
   넣은 줄은 폼의 줄(HT.cellRowHTML)이 되고, 저장은 예전과 같이 편집 창의 [저장]이 합니다(되돌리기 한 걸음).
   메이커 전용 — 연표 배포물에서는 읽지 않습니다(core.js의 붙여넣기 단추는 HT.makerPaste가 있을 때만 이리로 넘깁니다). */
(function () {
  'use strict';
  const HT = window.HT;
  const F = (key, label, aliases = []) => ({ key, label, aliases: [label, key, ...aliases] });
  /* 머리글 별칭은 체제를 가리지 않는 낱말만 — 앱 글에 특정 체제 낱말을 두지 않는 규칙(dev-smoke ㉝ ③) */
  const START = F('start', '시작', ['시작 연도', '시작일', '시작 날짜', '부터', '연도', 'from']);
  const END = F('end', '끝', ['끝 연도', '끝 날짜', '종료', '종료 연도', '까지', 'to']);
  const RANGE = F('range', '기간 (시작~끝)', ['기간', '연대', '시기', 'period']);
  const NOTE = F('note', '메모', ['비고', '설명', '참고']);
  const HOUSE = F('house', '가문', ['집안']);
  /* 승계 · 사람 · 혈연 (D1 확정 설계 7-2 ⑥): 읽은 값은 칸의 accession · person · parents로 (HT.readAccession · readPersonRef · readParents 그대로) */
  const KIN = [F('kin', '관계', ['전임자와의 관계', '승계 관계']), F('how', '방식', ['승계 방식', '오른 방식']), F('from', '전임자', ['전임']), F('person', '인물', ['사람', '인물 id']), F('father', '부', ['아버지', '부친']), F('mother', '모', ['어머니', '모친'])];
  /* 확실성(확실 · 통설 · 추정 · 전승) — 그 줄의 [이설] 상자의 확실성으로 (통설은 기본값이라 적지 않음) */
  const CERT = F('certainty', '확실성', ['확실도']);
  /** 줄 목록마다 받을 칸 — 차례는 미리 보기의 고르기 차례. 별칭이 여러 칸에 겹치면(지도자의 '이름') 머리글을 읽을 때 앞 칸부터 채웁니다 */
  const FIELDS = {
    leaders: [F('name', '대표 이름', ['대표이름', '이름', '지도자', '임금', '군주', '통치자', '왕']), F('ordinal', '대수', ['대', '순번', '차례']), F('temple', '묘호'), F('title', '시호'), F('given', '이름', ['본명', '휘', '실명']), START, END, RANGE, F('dynasty', '왕조'), F('rank', '지위', ['칭호']), HOUSE, ...KIN, NOTE, CERT],
    cabinets: [F('name', '내각 이름', ['내각', '이름']), START, END, RANGE, HOUSE, NOTE, CERT],
    eras: [F('name', '연호', ['이름']), START, END, RANGE, NOTE, CERT],
    capitals: [F('city', '도시', ['도읍', '수도', '이름']), START, END, RANGE, F('role', '역할', ['구분']), F('as', '그때 이름', ['당시 이름']), F('label', '시기 이름'), F('group', '묶음'), F('event', '천도 사건', ['사건', '천도']), NOTE, CERT],
    ranks: [F('name', '지위', ['이름', '칭호']), START, END, RANGE, NOTE, CERT],
    /* 족보 (D1 확정 설계 7-2 ④ · ⑤): 메이커 인물 표에 족보를 머리글째 붙여넣을 때의 낱말(js/maker-grid.js가 인물 표의 열 별칭으로 씀 — 부 = 아버지 · 부친, 생 = 출생 · 생년 …).
       들여쓰기 족보 글(한 줄 = 한 사람 · 들여쓰기 = 세대)은 계층 입력 창(js/maker-kin.js의 readLine)이 같은 읽기로 받습니다 */
    genealogy: [F('name', '이름', ['성명']), F('father', '부', ['아버지', '부친']), F('mother', '모', ['어머니', '모친']), F('adoptive-father', '양부', ['양아버지']), F('birth-father', '생부', ['친부', '친아버지']), F('house', '파', ['가문', '집안', '분파']), F('birth', '생', ['출생', '생년', '태어남', '출생년']), F('death', '몰', ['사망', '몰년', '졸년', '죽음']), F('order', '형제 순서', ['순서', '형제순']), F('lineageOnly', '계보 전용', ['계보전용']), NOTE],
  };
  const WORD = { leaders: '지도자', cabinets: '내각', eras: '연호', capitals: '도읍', ranks: '지위', genealogy: '족보' };
  const norm = s => String(s ?? '').trim().toLowerCase().replace(/[\s_·.()~]/g, '');
  const fieldsOf = kind => FIELDS[kind] || null;
  const RANGE_RE = /^(-?\d+)\s*-\s*(-?\d+)?$/;
  const ORD_RE = /^제?\s*(\d+)\s*대?$/;

  /** 붙여넣은 글 → 줄마다 칸 목록. delim으로 나누고, 큰따옴표로 감싼 칸 안의 줄바꿈 · 나눔표 · "" 도 읽습니다(엑셀이 복사하는 꼴). 빈 줄은 뺍니다 */
  function splitTable(text, delim) {
    const src = String(text || ''), rows = [];
    let row = [], cell = '', quoted = false;
    for (let i = 0; i < src.length; i++) {
      const c = src[i];
      if (quoted) {
        if (c === '"' && src[i + 1] === '"') { cell += '"'; i++; }
        else if (c === '"') quoted = false;
        else cell += c;
      } else if (c === '"' && cell === '') quoted = true;
      else if (c === delim) { row.push(cell); cell = ''; }
      else if (c === '\n' || c === '\r') {
        if (c === '\r' && src[i + 1] === '\n') i++;
        row.push(cell); rows.push(row); row = []; cell = '';
      } else cell += c;
    }
    if (cell !== '' || row.length) { row.push(cell); rows.push(row); }
    return rows.filter(r => r.some(c => String(c).trim() !== ''));
  }
  /** 머리글 줄 짐작: 칸 이름과 같은 칸이 절반 이상(하나 이상)이면 머리글 — 열마다 받을 칸(없으면 '')을 돌려주고, 아니면 null.
      한 칸만 맞는 머리를 먼저 채우고, 여러 칸에 맞는 머리(지도자의 '이름')는 남은 칸 가운데 앞의 것으로 */
  function guessHead(first, kind) {
    const fields = fieldsOf(kind); if (!fields || !first) return null;
    const cand = first.map(h => (norm(h) ? fields.filter(f => f.aliases.some(a => norm(a) === norm(h))).map(f => f.key) : []));
    const map = first.map(() => ''), used = new Set();
    for (const pass of [1, 2]) cand.forEach((keys, j) => {
      if (map[j] || !keys.length || (pass === 1 && keys.length !== 1)) return;
      const k = keys.find(x => !used.has(x)); if (k) { map[j] = k; used.add(k); }
    });
    const filled = first.filter(h => String(h).trim()).length, hit = map.filter(Boolean).length;
    return hit && hit >= Math.max(1, Math.ceil(filled / 2)) ? map : null;
  }
  const isDateText = v => HT.isUnknownText(v) || (() => { const d = HT.readDate(v); return !!d && Number.isFinite(d.t); })();
  const isRangeText = v => /~/.test(v) || RANGE_RE.test(v);
  /** 머리글이 없을 때 열의 내용으로 짐작: 기간(시작~끝) · 날짜 둘(시작 · 끝) · 대수(제4대 · 1,2,3 …) · 도읍의 역할 · 나머지 글 열은 첫째가 이름, 마지막이 메모 */
  function guessColumns(rows, kind) {
    const fields = fieldsOf(kind); if (!fields) return [];
    const width = Math.max(0, ...rows.map(r => r.length)), map = Array(width).fill('');
    const col = j => rows.map(r => String(r[j] ?? '').trim()).filter(Boolean);
    const has = k => fields.some(f => f.key === k), take = (j, k) => { if (!map.includes(k) && has(k)) map[j] = k; };
    const dates = [], texts = [];
    const datesElsewhere = j => Array.from({ length: width }, (_, i) => i).some(i => i !== j && col(i).length && col(i).every(isDateText));
    for (let j = 0; j < width; j++) {
      const v = col(j); if (!v.length) continue;
      const ints = v.every(x => /^\d+$/.test(x)) ? v.map(Number) : null;
      const ordinalLike = (v.every(x => ORD_RE.test(x)) && v.some(x => /대/.test(x))) || // 제4대 · 4대
        (!!ints && ints.length > 1 && ints[0] < 300 && ints.every((n, i) => !i || n === ints[i - 1] + 1) && datesElsewhere(j)); // 1 · 2 · 3 … — 날짜 열이 따로 있을 때만(연도 열과 헷갈리지 않게)
      if (has('ordinal') && ordinalLike) { take(j, 'ordinal'); if (map[j]) continue; }
      if (v.every(isDateText)) { dates.push(j); continue; }
      if (v.every(isRangeText)) { take(j, 'range'); if (map[j]) continue; }
      if (kind === 'capitals' && v.every(x => HT.capitalRole(x))) { take(j, 'role'); if (map[j]) continue; }
      texts.push(j);
    }
    if (!map.includes('range')) { if (dates[0] != null) map[dates[0]] = 'start'; if (dates[1] != null) map[dates[1]] = 'end'; }
    else if (dates[0] != null) map[dates[0]] = 'start';
    if (texts.length) map[texts[0]] = kind === 'capitals' ? 'city' : 'name';
    if (texts.length > 1) map[texts.at(-1)] = 'note';
    return map;
  }
  /** 붙여넣은 글이 표인지 — 탭이 있거나, 첫 줄이 쉼표로 나뉜 머리글(칸 둘 이상이 모두 칸 이름)이면 표. 아니면 null(예전 한 줄 글 꼴) */
  function parseText(text, kind, loose = false) {
    const s = String(text || '');
    if (!fieldsOf(kind) || !s.trim()) return null;
    if (s.includes('\t')) return { delim: '\t', rows: splitTable(s, '\t') };
    const rows = splitTable(s, ','), first = rows[0] || [], head = guessHead(first, kind);
    /* loose(통째 붙여넣기): 머리글의 절반 이상만 칸 이름이면 표 — 모르는 열은 받지 않음(알림에 적음) */
    return first.length > 1 && head && (loose || head.every((k, j) => k || !String(first[j]).trim())) ? { delim: ',', rows } : null;
  }
  const splitRange = s => { const t = String(s).trim(); let m = t.match(/^(.*?)\s*~\s*(.*)$/); if (m) return [m[1], m[2]]; m = t.match(RANGE_RE); return m ? [m[1], m[2] || ''] : [t, '']; };
  /** 시작 · 끝 글 하나 → null(비움) · { unknown: true } · { t, at } · { error } (세기 글 "3세기 중반"은 예전 한 줄 글처럼 붙여 읽음) */
  function readEdge(text) {
    const s = String(text ?? '').trim().replace(/(\d+)\s*세기\s+(초반|초엽|초|전반|중반|중엽|중|후반|말엽|말)$/, '$1세기$2');
    if (!s) return null;
    if (HT.isUnknownText(s)) return { unknown: true };
    const d = HT.readDate(s);
    return d && Number.isFinite(d.t) ? d : { error: d && d.error ? d.error : '', text: s };
  }
  /**
   * 한 줄 읽기 — cells(열 글) · map(열마다 받을 칸) → { cell(폼의 줄 꼴 — HT.cellRowHTML이 받는 것), error(넣지 않는 까닭 — 없으면 '') }.
   * opt.startOptional = 지위 변천의 첫 줄처럼 시작을 비워도 되는지
   */
  function readRow(cells, map, kind, opt = {}) {
    const v = {};
    map.forEach((k, j) => { const t = String(cells[j] ?? '').trim(); if (k && t) v[k] = t; });
    if (v.range) { const [a, b] = splitRange(v.range); if (v.start == null && a) v.start = a; if (v.end == null && b) v.end = b; }
    const bad = [], cell = {};
    const nameKey = kind === 'capitals' ? 'city' : 'name';
    if (v[nameKey]) cell[nameKey] = v[nameKey];
    for (const k of ['temple', 'title', 'given', 'dynasty', 'rank', 'house', 'as', 'label', 'group', 'note']) if (v[k] && fieldsOf(kind).some(f => f.key === k)) cell[k] = v[k];
    if (kind === 'leaders') {
      /* 관계 · 방식 · 전임자 → 승계(accession) · 인물 → 사람(person) · 부 → 혈연(parents) — 읽지 못한 값은 그 줄을 넣지 않음 */
      const acc = {};
      for (const k of ['kin', 'how', 'from']) if (v[k]) acc[k] = v[k];
      if (Object.keys(acc).length) {
        const a = HT.readAccession(acc, m => bad.push(m));
        if (a) cell.accession = a;
      }
      if (v.person) {
        const r = HT.isUnknownWho(v.person) ? null : HT.readPersonRef(v.person);
        if (r) cell.person = r;
        else bad.push(`인물 "${v.person}"을(를) 읽을 수 없음 (인물 id · 이름이나 "나라:지도자@시작 해" — 모르면 비워 둠)`);
      }
      const kin = [['father', v.father], ['mother', v.mother]].filter(([, who]) => who).map(([as, who]) => ({ who, as }));
      if (kin.length) {
        const ps = HT.readParents(kin, m => bad.push(m));
        if (ps.length) cell.parents = ps;
      }
    }
    if (!cell[nameKey] && !(kind === 'leaders' && (cell.temple || cell.title || cell.given))) bad.push(kind === 'capitals' ? '도시가 없음' : `${kind === 'ranks' ? '지위' : '이름'}이 없음`);
    const sd = readEdge(v.start), ed = readEdge(v.end);
    if (!sd) { if (!opt.startOptional) bad.push(kind === 'ranks' ? '시작이 없음 (시작을 비울 수 있는 것은 지위 변천의 첫 줄뿐 — 모르면 "미정")' : '시작이 없음 (모르면 "미정")'); }
    else if (sd.unknown) cell.startUnknown = true;
    else if (sd.error != null) bad.push(`시작 "${sd.text}"을(를) 읽을 수 없음${sd.error ? ` (${sd.error})` : ''}`);
    else { cell.start = sd.t; if (sd.at) cell.startAt = sd.at; }
    if (ed && ed.unknown) cell.endUnknown = true;
    else if (ed && ed.error != null) bad.push(`끝 "${ed.text}"을(를) 읽을 수 없음${ed.error ? ` (${ed.error})` : ''}`);
    else if (ed) { cell.end = ed.t; if (ed.at) cell.endAt = ed.at; }
    if (cell.start != null && cell.end != null && HT.endBound(cell.end, cell.endAt) < cell.start) bad.push('끝이 시작보다 앞섬');
    if (v.ordinal) {
      const m = v.ordinal.match(ORD_RE);
      if (HT.isUnknownOrdinal(v.ordinal)) cell.ordinalUnknown = true;
      else if (m) cell.ordinal = Number(m[1]);
      else bad.push(`대수 "${v.ordinal}"을(를) 읽을 수 없음 (숫자나 "미상")`);
    }
    if (v.role) {
      const role = HT.capitalRole(v.role);
      if (role) { if (role !== 'main') cell.role = role; }
      else bad.push(`역할 "${v.role}"을(를) 알 수 없음 (${HT.CAPITAL_ROLES.map(r => r.name).join(' · ')})`);
    }
    if (v.certainty) {
      const c = certaintyId(v.certainty);
      if (c) { if (c !== 'accepted') cell.certainty = c; }
      else bad.push(`확실성 "${v.certainty}"을(를) 알 수 없음 (${HT.CERTAINTY.map(x => x.name).join(' · ')})`);
    }
    return { cell, error: bad.join(', ') };
  }
  /** 확실성 글(이름 · id) → id, 모르면 '' */
  function certaintyId(v) {
    const s = String(v ?? '').trim().replace(/^`|`$/g, '');
    const hit = (HT.CERTAINTY || []).find(c => c.id === s || c.name === s);
    return hit ? hit.id : '';
  }
  /**
   * 붙여넣은 글 읽기 → null(표가 아님 — 예전 한 줄 글 꼴) 또는
   * { kind, delim, head(첫 줄을 머리글로 보았는지), guessed(짐작한 값), map(열마다 받을 칸), width, header(머리글 줄 · 없으면 null), rows: [{ line(붙여넣은 글의 몇째 줄), cells, cell, error }] }.
   * opt = { head: true|false(머리글 짐작을 덮어씀), map(열 맞추기를 덮어씀), existing(폼에 이미 있는 줄 수 — 지위 변천의 빈 시작은 첫 줄만), loose(머리글에 모르는 열이 섞여도 표로) }
   */
  function analyze(text, kind, opt = {}) {
    const t = parseText(text, kind, !!opt.loose); if (!t) return null;
    const headMap = guessHead(t.rows[0], kind), guessed = !!headMap;
    const head = opt.head == null ? guessed : !!opt.head;
    const body = head ? t.rows.slice(1) : t.rows;
    const width = Math.max(0, ...t.rows.map(r => r.length));
    let map = Array.isArray(opt.map) ? opt.map.slice(0, width) : head ? headMap || guessColumns(body, kind) : guessColumns(body, kind);
    while (map.length < width) map.push('');
    const keys = new Set(fieldsOf(kind).map(f => f.key)), seen = new Set();
    map = map.map(k => (k && keys.has(k) && !seen.has(k) ? (seen.add(k), k) : '')); // 모르는 칸 · 겹친 칸은 받지 않음
    let free = kind === 'ranks' && !opt.existing;
    const rows = body.map((cells, i) => {
      const r = readRow(cells, map, kind, { startOptional: free });
      if (!r.error) free = false;
      return { line: i + 1 + (head ? 1 : 0), cells, ...r };
    });
    return { kind, delim: t.delim, head, guessed, map, width, header: head ? t.rows[0] : null, rows };
  }
  /** 읽지 못한 줄을 글 칸에 남길 꼴 — 머리글이 있었으면 머리글과 함께, 나눔표는 붙여넣은 것 그대로 */
  function leftoverText(a) {
    const bad = a.rows.filter(r => r.error);
    if (!bad.length) return '';
    const q = v => (/["\n\r]/.test(String(v)) || String(v).includes(a.delim) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v));
    return (a.header ? [a.header] : []).concat(bad.map(r => r.cells)).map(r => r.map(q).join(a.delim)).join('\n');
  }

  /* ---------- 미리 보기 창 (기존 메이커 대화상자의 꼴 — .dlc-dialog .mk-box · .dlg · 표 붙여넣기의 .mk-paste-preview · .mk-base-table) ---------- */
  const esc = s => (HT.esc ? HT.esc(s) : String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]));
  const when = c => {
    const side = k => (c[`${k}Unknown`] ? '미정' : c[k] == null ? '' : HT.dateInputValue(c, k));
    return `${side('start') || '(처음부터)'} ~ ${side('end') || '(끝까지)'}`;
  };
  /**
   * core.js의 [줄을 칸으로 추가](data-cell-paste)가 부릅니다 — 글 칸의 글이 표면 미리 보기 창을 열고 true(넣기까지 이 창이 맡음),
   * 표가 아니면 false(예전 한 줄 글 읽기가 그대로 이어서 함)
   */
  function open(form, kind, ta) {
    if (!form || !ta || !fieldsOf(kind) || typeof document === 'undefined' || !document.body) return false;
    const existing = () => form.querySelectorAll(`[data-cells="${kind}"] .cell-row`).length;
    let a = analyze(ta.value, kind, { existing: existing() });
    if (!a) return false;
    const box = document.createElement('dialog');
    box.className = 'dlc-dialog mk-box'; box.dataset.rowPaste = kind;
    box.style.width = 'min(860px, calc(100vw - 24px))'; // 표 붙여넣기 창(#mkPasteDialog)과 같은 폭 — 열이 많은 표를 보므로 기본 대화상자보다 넓게
    const fields = fieldsOf(kind);
    function paint() {
      const good = a.rows.filter(r => !r.error).length, bad = a.rows.length - good;
      const pick = (k, j) => `<select data-paste-col="${j}" aria-label="${j + 1}번째 열이 받을 칸"><option value="">받지 않음</option>${fields.map(f => `<option value="${f.key}"${k === f.key ? ' selected' : ''}>${esc(f.label)}</option>`).join('')}</select>`;
      const heads = a.map.map((k, j) => `<th>${pick(k, j)}${a.header && String(a.header[j] ?? '').trim() ? `<br><small>머리글: ${esc(a.header[j])}</small>` : ''}</th>`).join('');
      /* 줄 번호 바로 옆에 읽은 기간(넣을 줄) · 넣지 않음(빨강) — 열이 많아 표가 옆으로 넘쳐도 결과가 늘 보이게. 까닭은 표 위의 빨간 목록(표 붙여넣기와 같은 꼴) */
      const body = a.rows.slice(0, 500).map(r => `<tr${r.error ? ' class="is-bad"' : ''}><td>${r.error ? `<b>✕ ${r.line}</b>` : r.line}</td><td>${r.error ? '<b>넣지 않음</b>' : esc(when(r.cell))}</td>${Array.from({ length: a.width }, (_, j) => `<td>${esc(r.cells[j] ?? '')}</td>`).join('')}</tr>`).join('');
      const errs = a.rows.filter(r => r.error);
      box.querySelector('[data-paste-preview]').innerHTML = `
        <p><b>${good}줄</b>을 넣을 수 있습니다.${bad ? ` 읽지 못한 줄 <b>${bad}개</b>는 빨갛게 표시했고 넣지 않습니다(글 칸에 남겨 둠).` : ''}</p>
        ${errs.length ? `<ul class="mk-paste-problems">${errs.slice(0, 10).map(r => `<li>${r.line}번째 줄: ${esc(r.error)}</li>`).join('')}${errs.length > 10 ? `<li>…외 ${errs.length - 10}개</li>` : ''}</ul>` : ''}
        <div class="mk-table-wrap"><table class="mk-base-table is-list"><thead><tr><th>줄</th><th>읽은 기간</th>${heads}</tr></thead><tbody>${body}</tbody></table>${a.rows.length > 500 ? `<p>…외 ${a.rows.length - 500}줄</p>` : ''}</div>`;
      box.querySelector('[data-paste-head]').checked = a.head;
      const accept = box.querySelector('[data-paste-accept]');
      accept.disabled = !good; accept.textContent = good ? `${good}줄 넣기` : '넣을 줄 없음';
    }
    box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>${esc(WORD[kind])} 줄 묶음 붙여넣기</h2><button type="button" class="icon-btn" data-paste-cancel aria-label="닫기">✕</button></div>
      <div class="dlg-body">
        <p>표에서 복사한 열을 ${esc(WORD[kind])} 줄의 칸에 맞춥니다. 열 머리의 고르기에서 받을 칸을 바꿀 수 있습니다. 날짜는 연도 · 날짜(음력 · 기원전) · "미정"을 읽고, 읽지 못한 줄은 넣지 않습니다.</p>
        <label class="check"><input type="checkbox" data-paste-head> 첫 줄은 머리글(칸 이름)</label>
        <div class="mk-paste-preview" data-paste-preview></div>
      </div>
      <div class="dlg-foot"><button type="button" class="btn" data-paste-cancel>취소</button><button type="button" class="btn btn-primary" data-paste-accept>넣기</button></div></div>`;
    box.addEventListener('change', e => {
      const t = e.target;
      if (t.matches('[data-paste-head]')) a = analyze(ta.value, kind, { head: t.checked, existing: existing() });
      else if (t.matches('[data-paste-col]')) {
        const j = Number(t.dataset.pasteCol), map = a.map.map((k, i) => (i !== j && k === t.value ? '' : k)); // 한 칸은 한 열만 받음 — 같은 칸을 고른 다른 열은 '받지 않음'으로
        map[j] = t.value;
        a = analyze(ta.value, kind, { head: a.head, map, existing: existing() });
      } else return;
      paint();
    });
    box.addEventListener('click', e => {
      if (e.target.closest('[data-paste-cancel]')) box.close();
      if (e.target.closest('[data-paste-accept]')) {
        const cells = a.rows.filter(r => !r.error).map(r => r.cell);
        if (!cells.length) return;
        const host = form.querySelector(`[data-cells="${kind}"]`);
        if (!host) { box.close(); return; }
        host.insertAdjacentHTML('beforeend', cells.map(c => HT.cellRowHTML(kind, c)).join(''));
        const left = a.rows.length - cells.length;
        ta.value = leftoverText(a);
        form.dispatchEvent(new Event('input', { bubbles: true }));
        HT.toast(`${cells.length}개를 칸으로 옮겼습니다.${left ? ` 읽지 못한 줄 ${left}개는 글 칸에 남겨 두었습니다.` : ''}`, 'ok');
        box.close();
      }
    });
    box.addEventListener('close', () => { box.remove(); ta.focus(); });
    document.body.append(box);
    paint();
    box.showModal();
    box.querySelector('[data-paste-accept]').focus();
    return true;
  }

  /* ================= 통째 붙여넣기 — 칸 블록(#HT칸 1) 하나로 시대 편집 창의 모든 칸 =================
     칸 채우기 답(docs/프롬프트-DLC-메이커-칸-채우기.md)은 사람이 읽는 글과 따로, 메이커가 읽는 '칸 블록'을 냅니다:
       #HT칸 1
       나라,고리국,미정,미정,한국,국가,예맥,,45.8
       지도자,미상,시비왕,미정,미정,전승,탁근국주로 전함
       #끝
     - 한 줄 = 한 층. 첫 자리는 층 이름(아래 LAYERS의 열쇠), 그 뒤는 그 층의 정해진 자리(cols)에 차례로 — 빈 자리는 쉼표 사이를 비우고, 뒤쪽의 빈 자리는 줄여도 됨.
     - tail인 층은 마지막 자리가 그 줄의 나머지(메모 · 까닭 — 쉼표가 들어도 됨), text인 층은 첫 쉼표 뒤가 통째 글(같은 층의 줄이 여럿이면 줄을 바꿔 이어 붙임 — 문서 본문).
       그 밖의 칸 안에 쉼표가 꼭 필요하면 큰따옴표로 감쌈(쉼표 표와 같은 규칙). '//'로 시작하는 줄과 빈 줄은 건너뜀.
     - 블록 밖의 글(근거 · 함께 만들 것 · 확인 필요)은 사람이 읽는 것이라 보지 않습니다 — 답 전체를 붙여넣어도, 블록만 붙여넣어도 됩니다.
       답이 끊겨 "계속"으로 이어 받으면 이어진 답의 블록(#HT칸 1부터 — 끊긴 줄부터 다시)도 함께 붙여넣습니다 — 끊긴 블록의 마지막 줄은 버리고, 글이 아닌 층의 같은 줄이 또 나오면 한 번만.
     - 지도자 · 도읍의 덧층(지도자칭호 · 지도자자리 · 지도자계보 · 도읍이름)과 폭 · 이설 · 원어는 열쇠(대표 이름 · 도시 · 연호 …, 같은 이름이 여럿이면 "이름@시작 해")로 그 줄을 찾아 붙습니다.
     - 인물 층(지도자가 아닌 사람 — 자리에 오르지 않은 왕족 · 왕비 · 장수 …)과 그 덧층(인물계보 · 인물활동 · 인물별칭)은 편집 창의 칸이 아니라 내 DLC의 인물 항목:
       이 나라를 저장할 때 넣습니다(같은 트랙 · 같은 이름의 제 인물은 고침 — js/maker-kin.js planPeople). 지도자계보의 부 · 모 자리는 인물 층의 이름을 가리켜도 됩니다.
     - 시대구분 · 대범위 층도 편집 창의 칸이 아니라 내 DLC의 대범위(scopes)의 구성 정권: 이 나라를 저장할 때 넣습니다(joinScope — 형식 3의 시대 구분은 구성원이 없어,
       '시대 구분에 든다'는 그 시대 구분을 가리키는 대범위에 드는 것 · 형식 4의 within과 같은 뜻). 없으면 대범위를 새로 만들고, 시대 구분도 기간을 적었으면 새로 만듦.
     - 층을 더하거나 자리를 바꿀 때는 LAYERS 한 곳과 프롬프트 문서의 '칸 블록' 표만 고칩니다(바뀐 판이면 #HT칸의 수를 올림).
     - 판 2(#HT칸 2 — 2026-10-24 · 프롬프트를 형식 4 낱말로 · 계획 docs/계획-리메이크-5단계-잔여.md 과제 1)는 LAYERS2: 객체 한 건의 머리 `객체`(종류는 형식 4의 열여덟) ·
       `그릇`(시대 그릇 = 대범위 · 그 밖 = 상위 띠에 접기) · `시대`(그 시대 그릇의 제 칸) · `섬김`(옛 소속) · `구성원`(그 객체의 그릇 칸에 이 객체 — 저장할 때) ·
       `주기`(바탕 자료 「주기」 표 — 저장할 때) · 이름만 바뀐 층(사람 · 이어받은객체 · 섬긴객체 …). 판 1 답은 LAYERS 그대로 읽습니다(섞지 않음).
       작업본이 아직 옛 꼴이라(5단계 정한 것 #1) 담지 못하는 것 — 그릇 · 구성원의 기간 · 그릇 구간의 정통성 · 칸의 정통성 · 승계 방식 — 은 알리고 뺍니다.
     읽기(parseWhole) · 합치기(mergeWhole) · 요약(wholeSummary)은 화면 없는 계산(scripts/maker-paste-check.mjs가 노드에서 봄) */
  const LIST_LABEL = { names: '이름(원어 등)', partOf: '소속·예속', succeeds: '승계', ranks: '지위 변천', leaders: '지도자', cabinets: '내각', eras: '연호', capitals: '도읍', phases: '시기 구분', alternatives: '이설', offices: '직위 줄 더', power: '실권' };
  const CELL_LISTS = ['ranks', 'leaders', 'cabinets', 'eras', 'capitals'];
  const BLOCK_START = /^\s*#\s*HT칸\s*(\d+)?\s*$/;
  const BLOCK_END = /^\s*#\s*끝\s*$/;
  /** 층 표 — cols: 자리마다의 열쇠(차례가 곧 블록의 자리) · tail: 마지막 자리가 줄의 나머지 · text: 첫 쉼표 뒤 통째 글의 칸 · rest: 나머지 자리가 모두 한 목록 ·
      list: 줄 목록(그 줄이 폼의 지도자 줄 같은 한 줄) · of: 덧층 — 첫 자리(key)로 그 목록의 줄을 찾아 칸을 더함 */
  const LAYERS = {
    나라: { cols: ['name', 'start', 'end', 'track', 'kind', 'people', 'house', 'northSouth'] },
    꼬리표: { rest: 'tags' },
    연대: { cols: ['historicity', 'certainty', 'placeStart', 'placeEnd'] },
    설명: { text: 'description' },
    실재근거: { text: 'historicityNote' },
    쟁점: { text: 'debate' },
    문서: { text: 'wiki' },
    이름: { cols: ['text', 'lang', 'kind', 'start', 'end', 'note'], tail: true },
    소속: { cols: ['polity', 'relation', 'start', 'end', 'nest', 'note'], tail: true },
    승계: { cols: ['from', 'type', 'degree', 'parts', 'note'], tail: true },
    지위: { list: 'ranks', cols: ['name', 'start', 'end', 'certainty', 'note'], tail: true },
    지도자: { list: 'leaders', cols: ['ordinal', 'name', 'start', 'end', 'certainty', 'note'], tail: true },
    지도자칭호: { of: 'leaders', cols: ['key', 'temple', 'title', 'given'] },
    지도자자리: { of: 'leaders', cols: ['key', 'dynasty', 'rank', 'house'] },
    지도자계보: { of: 'leaders', cols: ['key', 'kin', 'how', 'from', 'father', 'person', 'mother'] },
    내각: { list: 'cabinets', cols: ['name', 'start', 'end', 'house', 'certainty', 'note'], tail: true },
    연호: { list: 'eras', cols: ['name', 'start', 'end', 'certainty', 'note'], tail: true },
    도읍: { list: 'capitals', cols: ['city', 'start', 'end', 'role', 'certainty', 'note'], tail: true },
    도읍이름: { of: 'capitals', cols: ['key', 'as', 'label', 'group'] },
    체계: { cols: ['scheme', 'note'], tail: true },
    시기: { cols: ['scheme', 'name', 'start', 'end', 'note'], tail: true },
    폭: { cols: ['target', 'key', 'sa', 'sb', 'ea', 'eb'] },
    이설: { cols: ['target', 'key', 'start', 'end', 'label', 'source', 'note'], tail: true },
    원어: { cols: ['target', 'key', 'text', 'lang', 'kind', 'note'], tail: true },
    이어받은나라: { cols: ['name', 'type', 'note'], tail: true },
    속했던나라: { cols: ['name', 'relation', 'start', 'end'] },
    /* 시대구분 · 대범위: 이 나라가 드는 대범위(내 DLC의 scopes — 저장할 때 joinScope). 시대구분의 시작 · 끝은 그 시대 구분이 연표에 없을 때 새로 만드는 데만 씀 */
    시대구분: { cols: ['name', 'start', 'end'] },
    대범위: { cols: ['name', 'label', 'host'] },
    /* 인물(지도자가 아닌 사람 — 자리에 오르지 않은 왕족 · 왕비 · 재상 · 장군 …): 시대 편집 창의 칸이 아니라 내 DLC의 인물 항목 — 이 나라를 저장할 때 넣음(나라의 트랙).
       구분 '계보'(비우면 이것)는 계보 전용 인물(승계표 · 세계표에만), '활동'은 띠의 인물 단에 놓이는 인물(인물활동 층의 활동 기록 — 이 나라) */
    인물: { list: 'people', cols: ['name', 'role', 'birth', 'death', 'father', 'mother', 'spouse', 'kind', 'note'], tail: true },
    인물계보: { of: 'people', cols: ['key', 'house', 'order', 'certainty', 'adoptive'] },
    인물활동: { of: 'people', cols: ['key', 'start', 'end', 'office', 'importance'] },
    인물별칭: { of: 'people', cols: ['key', 'aka'] },
    /* 형식 4의 칸(5단계 과제 7 — 과제 3 · 4가 작업본에 지키는 칸): 객체 = 종류(열여덟 가운데 하나 · 사람 제외) · 정통성 · 중요도(0~3) · 으뜸(으뜸 그릇인 상위 정권 — 그 소속 줄에 표시),
       빌림 = 지도자 · 내각 자리를 다른 객체의 직위 줄로 보임(자리 · 출처 "객체 id" 또는 "객체 id/직위 이름" · 줄 이름), 직위줄 = 셋째 줄부터(이름 · 빌려 오기 출처 — 적으면 칸을 두지 않음),
       직위칸 = 그 직위 줄의 칸(열쇠 = 직위 줄 이름 · 지도자 칸과 같은 자리), 실권 = 이 객체가 쥔 남의 실권(상대 = 빼앗긴 객체 · 쥔 쪽에만) */
    객체: { cols: ['type', 'status', 'importance', 'main'] },
    빌림: { cols: ['slot', 'from', 'name'] },
    직위줄: { cols: ['name', 'from'] },
    직위칸: { cols: ['key', 'ordinal', 'name', 'start', 'end', 'certainty', 'note'], tail: true },
    실권: { cols: ['over', 'start', 'end', 'name', 'note'], tail: true },
  };
  /** 판 2 층 표(#HT칸 2 — 프롬프트 판 2의 '층 표' 그대로). as = 같은 일을 하는 판 1 층(읽는 함수를 함께 씀 — 자리는 판 2의 것) */
  const LAYERS2 = {
    객체: { cols: ['name', 'start', 'end', 'track', 'kind', 'people', 'house', 'northSouth', 'status', 'importance'] },
    꼬리표: LAYERS.꼬리표, 연대: LAYERS.연대, 설명: LAYERS.설명, 실재근거: LAYERS.실재근거, 쟁점: LAYERS.쟁점, 문서: LAYERS.문서, 이름: LAYERS.이름,
    그릇: { cols: ['name', 'type', 'start', 'end', 'main', 'status', 'note'], tail: true },
    시대: { cols: ['name', 'start', 'end', 'where', 'label', 'host', 'description'], tail: true },
    섬김: { as: '소속', cols: ['polity', 'relation', 'start', 'end', 'note'], tail: true },
    승계: { cols: ['from', 'type', 'how', 'degree', 'parts', 'note'], tail: true },
    지위: LAYERS.지위, 지도자: LAYERS.지도자, 지도자칭호: LAYERS.지도자칭호,
    지도자자리: { of: 'leaders', cols: ['key', 'dynasty', 'rank', 'house', 'status'] },
    지도자계보: LAYERS.지도자계보, 내각: LAYERS.내각, 빌림: LAYERS.빌림, 직위줄: LAYERS.직위줄, 직위칸: LAYERS.직위칸, 실권: LAYERS.실권,
    연호: LAYERS.연호, 도읍: LAYERS.도읍, 도읍이름: LAYERS.도읍이름, 체계: LAYERS.체계, 시기: LAYERS.시기, 폭: LAYERS.폭, 이설: LAYERS.이설, 원어: LAYERS.원어,
    이어받은객체: { as: '이어받은나라', cols: ['name', 'type', 'how', 'note'], tail: true },
    섬긴객체: { as: '속했던나라', cols: ['name', 'relation', 'start', 'end'] },
    구성원: { cols: ['name', 'start', 'end', 'main', 'note'], tail: true },
    주기: { cols: ['sphere', 'names', 'start', 'label', 'era', 'from', 'step'] },
    사람: { as: '인물', list: 'people', cols: LAYERS.인물.cols, tail: true },
    사람계보: { as: '인물계보', of: 'people', cols: LAYERS.인물계보.cols },
    사람활동: { as: '인물활동', of: 'people', cols: LAYERS.인물활동.cols },
    사람별칭: { as: '인물별칭', of: 'people', cols: LAYERS.인물별칭.cols },
  };
  /** 폭 · 이설 · 원어의 대상 → 목록 ('나라'는 나라 자신) */
  const TARGETS = { 나라: '', 지위: 'ranks', 지도자: 'leaders', 내각: 'cabinets', 연호: 'eras', 도읍: 'capitals', 소속: 'partOf', 인물: 'people' };
  /** 판 2의 대상(직위칸 = 직위 줄 더의 칸) */
  const TARGETS2 = { 객체: '', 지위: 'ranks', 지도자: 'leaders', 내각: 'cabinets', 직위칸: 'officeCells', 연호: 'eras', 도읍: 'capitals', 섬김: 'partOf', 사람: 'people' };
  /** 판 2에서 알림 글의 층 이름(판 1의 읽는 함수가 판 1 이름으로 알릴 때) */
  const NAMES2 = { 나라: '객체', 소속: '섬김', 인물: '사람', 인물계보: '사람계보', 인물활동: '사람활동', 인물별칭: '사람별칭', 이어받은나라: '이어받은객체', 속했던나라: '섬긴객체' };
  const ON_RE = /^(켬|예|o|on|true)$/i;
  /** 칸 글 손질: 둘레의 `코드` · **굵게** · 따옴표를 걷고, 틀의 자리표(〈…〉)와 빈 값 표시(— · (비움) · (해당 없음) · 없음)는 빈 글로 */
  const EMPTY_RE = /^(?:[—–\-·]|\(?\s*(?:비움|없음|해당\s*없음)\s*\)?|n\/?a)$/i;
  /** 마크다운 링크 [글](주소) 풀기 — 'label': 글만(출처 괄호 "([글](주소))"는 "(글)") · 'source': "글 주소"(출처 칸 — 주소를 남김) ·
      'namu': 나무위키의 바깥 링크 [[주소|글]](문서). 주소 안의 괄호도 짝을 맞춰 읽고, http · mailto 주소만 링크로 봄 */
  function unlink(s, how = 'label') {
    const src = String(s ?? '');
    if (!src.includes('](')) return src;
    let out = '', i = 0;
    while (i < src.length) {
      const open = src.indexOf('[', i);
      const close = open < 0 ? -1 : src.indexOf('](', open);
      if (open < 0 || close < 0) { out += src.slice(i); break; }
      const label = src.slice(open + 1, close);
      if (/[[\]\n]/.test(label)) { out += src.slice(i, open + 1); i = open + 1; continue; }
      let j = close + 2, depth = 1;
      for (; j < src.length; j++) {
        const c = src[j];
        if (c === '(') depth++;
        else if (c === ')' && --depth === 0) break;
        else if (/\s/.test(c)) break;
      }
      const url = src.slice(close + 2, j);
      if (src[j] !== ')' || !/^(https?:|mailto:)/i.test(url)) { out += src.slice(i, open + 1); i = open + 1; continue; }
      out += src.slice(i, open) + (how === 'namu' ? `[[${url}|${label}]]` : how === 'source' ? `${label} ${url}` : label);
      i = j + 1;
    }
    return out;
  }
  function bare(s) {
    let t = unlink(s).replace(/ /g, ' ').trim();
    for (let k = 0; k < 3; k++) {
      const m = t.match(/^(\*\*|__|`|"|“)([\s\S]*)(\*\*|__|`|"|”)$/);
      if (!m || !m[2].trim()) break;
      t = m[2].trim();
    }
    return /^〈[^〉]*〉$/.test(t) || EMPTY_RE.test(t) ? '' : t;
  }
  /** 날짜 칸 글 → null(비움) · { unknown, t? }(미정 — t는 함께 적은 배치용 연도) · { ongoing } · { t, at } · { error, text } */
  function readWhen(text, { ongoingOK = false } = {}) {
    const s = bare(text);
    if (!s) return null;
    if (ongoingOK && /^(현재|진행\s*중)$/.test(s)) return { ongoing: true };
    if (/^(미정|미상|불명|모름)/.test(s)) {
      const rest = s.replace(/^(미정|미상|불명|모름)/, '').replace(/[()（）,，:：·]|배치용|연도|대략|무렵|쯤/g, ' ').trim();
      const d = rest ? readEdge(rest) : null;
      return { unknown: true, t: d && d.error == null && Number.isFinite(d.t) ? d.t : null };
    }
    return readEdge(s);
  }
  /** 연대 폭 한 쌍(이르면 · 늦으면 — 두 자리) → { range, at } · null(둘 다 비움) · { error } */
  function readPair(a, b) {
    if (!bare(a) && !bare(b)) return null;
    const x = readEdge(bare(a)), y = readEdge(bare(b));
    if (!x || !y || x.error != null || y.error != null || x.unknown || y.unknown) return { error: true };
    const [p, q] = x.t <= y.t ? [x, y] : [y, x];
    return { range: [p.t, q.t], at: p.at || q.at ? [p.at || null, q.at || null] : null };
  }
  /** 날짜 한쪽을 칸 객체에 (미정이면 …Unknown + 배치용 연도) */
  const putWhen = (o, key, d) => {
    if (!d || d.error != null) return;
    if (d.unknown) {
      o[`${key}Unknown`] = true;
      if (d.t != null) o[key] = d.t;
      return;
    }
    if (d.ongoing) { o.ongoing = true; return; }
    o[key] = d.t;
    if (d.at) o[`${key}At`] = d.at;
  };
  const trackIdOf = (name, tracks) => {
    const s = bare(name);
    if (!s) return '';
    const k = s.replace(/\s/g, '');
    const t = (tracks || []).find(x => x.id === s || x.name === s) || (tracks || []).find(x => String(x.name || '').replace(/\s/g, '') === k || String(x.id).replace(/\s/g, '') === k);
    return t ? t.id : null;
  };
  const yearOf = t => (HT.yearOf ? HT.yearOf(t) : Math.floor(t));
  /** 승계 종류 글 → id ('' = 모름 — 직접 · 간접 · 부흥 · 부분은 '승계'를 빼고 적어도 됨) */
  const succTypeOf = v => {
    const t = bare(v);
    if (!t) return '';
    if (HT.SUCCESSION.some(x => x.id === t || x.name === t)) return HT.successionType(t);
    const m = t.match(/^(직접|간접|부흥|부분)\s*(승계)?$/);
    return m ? HT.successionType(m[1] === '부흥' ? '부흥' : `${m[1]} 승계`) : '';
  };
  /** 칸 블록의 줄들 — 블록(#HT칸 … #끝) 안의 줄만, 붙여넣은 글의 몇째 줄인지와 함께. 블록이 여럿이면(이어 받은 답) 모두.
      닫히지 않은 블록 뒤에 새 블록이 열리면(답이 끊겨 "계속"으로 이어 받음) 앞 블록의 마지막 줄은 끊긴 줄일 수 있어 버림 — 이어진 블록이 그 줄부터 다시 적음 */
  function blockLines(text) {
    const all = String(text || '').replace(/\r\n?/g, '\n').split('\n');
    const out = [];
    let inside = false, found = 0, open = false, version = 0, from = 0;
    all.forEach((raw, i) => {
      if (/^\s*```\w*\s*$/.test(raw)) {
        inside = false; // 코드 블록이 닫힘 — #끝 없이 끊긴 블록 뒤의 글(이어 받은 답의 머리말)은 읽지 않음
        return;
      }
      const s = BLOCK_START.exec(raw);
      if (s) {
        if (open && out.length > from) out.pop();
        from = out.length;
        inside = open = true;
        found++;
        version = Math.max(version, Number(s[1] || 1));
        return;
      }
      if (BLOCK_END.test(raw)) {
        inside = open = false;
        return;
      }
      if (inside && raw.trim()) out.push({ no: i + 1, raw });
    });
    return { lines: out, found, closed: !open, version };
  }
  /** 한 줄 → 자리 값들 (text 층은 첫 쉼표 뒤 통째 · tail은 남는 자리를 마지막 자리에 이어 붙임) · 자리가 넘치면 { error } */
  function splitLine(raw, def) {
    if (def.text) {
      const at = raw.indexOf(',');
      return at < 0 ? '' : raw.slice(at + 1).replace(/\s+$/, '');
    }
    const vals = (splitTable(raw, ',')[0] || []).slice(1);
    if (def.rest) return vals;
    if (vals.length <= def.cols.length) return vals;
    if (def.tail) return vals.slice(0, def.cols.length - 1).concat(vals.slice(def.cols.length - 1).join(','));
    return { error: `자리가 ${def.cols.length}개인데 ${vals.length}개입니다 — 칸 안의 쉼표는 · 로 쓰거나 칸을 큰따옴표로 감쌉니다` };
  }
  const valsOf = (def, vals) => Object.fromEntries(def.cols.map((k, j) => [k, vals[j] == null ? '' : String(vals[j])]));

  /**
   * 칸 블록 읽기 → { fields, lists, nameAdds, others, problems, skipped, found, title, version }
   *   fields = 적힌 낱칸만(파일과 같은 꼴: name · start/startAt/startUnknown · end/endAt/endUnknown/ongoing · track · kind · people · house · tags · description ·
   *            northSouth · historicity · historicityNote · certainty · startRange(At) · endRange(At) · debate · wiki),
   *   lists = 줄 목록(names · partOf · succeeds · ranks · leaders · cabinets · eras · capitals · phases · alternatives — 폼의 줄 꼴),
   *   nameAdds = 원어 층(합칠 때 그 줄을 찾아 붙임 — 편집 창에 이미 있는 줄에도), others = 다른 나라 · 대범위에 넣을 것(이어받은나라 · 속했던나라 · 시대구분 · 대범위),
   *   problems = 넣지 않거나 바꾸지 않은 것의 까닭("n번째 줄(층): …"), found = 블록 수.
   * opt.tracks = [{ id, name }] (트랙 이름 → id)
   */
  function parseWhole(text, opt = {}) {
    const { lines, found, closed, version } = blockLines(text);
    const fields = {}, lists = {}, problems = [], nameAdds = [], others = [];
    const v2 = version >= 2;
    const LL = v2 ? LAYERS2 : LAYERS, TT = v2 ? TARGETS2 : TARGETS;
    const say = (no, tag, m) => problems.push(`${no}번째 줄${tag ? `(${(v2 && NAMES2[tag]) || tag})` : ''}: ${m}`);
    const containers = [], eraLines = new Map(), memberRows = [];
    /** 문화권 글(id · 이름) → id — opt.spheres([{ id, name }])가 있으면 그 안에서, 없으면 HT의 사전 · 글 그대로 */
    const sphereIdOf = s => {
      const list = opt.spheres || [];
      const hit = list.find(x => x && (x.id === s || x.name === s));
      if (hit) return hit.id;
      if (HT.isSphere && HT.isSphere(s)) return s;
      return list.length ? '' : s;
    };
    if (found && !closed) problems.push('끝 표시(#끝)가 없습니다 — 답이 끊겼으면 이어진 답의 블록도 함께 붙여넣으세요');
    const texts = {}, rows = {}, subs = [], later = [], phases = [], schemeNotes = {};
    const seen = new Set();
    for (const { no, raw } of lines) {
      const t = raw.trim();
      if (t.startsWith('//')) continue;
      const tag = t.split(',')[0].trim().replace(/\s+/g, '');
      const def = LL[tag];
      if (!def) { say(no, '', `모르는 층 "${tag}" (${Object.keys(LL).join(' · ')})${!v2 && LAYERS2[tag] ? ' — 판 2의 층이면 블록 머리를 #HT칸 2로' : ''})`); continue; }
      if (!def.text) {
        if (seen.has(t)) continue; // 이어 받은 답이 되풀이한 줄
        seen.add(t);
      }
      const vals = splitLine(def.text ? raw.replace(/^\s+/, '') : t, def);
      if (vals && vals.error) { say(no, tag, vals.error); continue; }
      if (def.text) { (texts[def.text] = texts[def.text] || []).push(vals); continue; }
      if (def.rest) {
        const tags = vals.flatMap(x => String(x).split(/[·、]/)).map(bare).filter(Boolean); // 한 자리에 가운뎃점으로 여럿을 적어도 됨
        if (tags.length) fields[def.rest] = [...new Set((fields[def.rest] || []).concat(tags))];
        continue;
      }
      const v = valsOf(def, vals);
      const as = def.as || tag; // 판 2에서 이름만 바뀐 층은 판 1의 읽는 함수로
      if (def.list) (rows[def.list] = rows[def.list] || []).push({ no, v });
      else if (def.of) subs.push({ no, tag: as, def, v });
      else if (v2 && tag === '객체') head2(no, v);
      else if (v2 && tag === '그릇') containerRow(no, v);
      else if (v2 && tag === '시대') eraRow(no, v);
      else if (v2 && tag === '구성원') memberRow(no, v);
      else if (v2 && tag === '주기') cycleRow(no, v);
      else if (as === '소속') partRow(no, v);
      else if (as === '이어받은나라' || as === '속했던나라') otherRow(no, as, v);
      else if (tag === '나라') nation(no, v);
      else if (tag === '연대') dating(no, v);
      else if (tag === '이름') nameRow(no, v);
      else if (tag === '소속') partRow(no, v);
      else if (tag === '승계') succRow(no, v);
      else if (tag === '체계') schemeNotes[bare(v.scheme)] = bare(v.note);
      else if (tag === '시기') phaseRow(no, v);
      else if (tag === '이어받은나라' || tag === '속했던나라') otherRow(no, tag, v);
      else if (tag === '시대구분' || tag === '대범위') scopeRow(no, tag, v);
      else if (tag === '객체') objectRow(no, v);
      else if (tag === '빌림') borrowRow(no, v);
      else if (tag === '직위줄') officeRow(no, v);
      else if (tag === '직위칸') officeCellRow(no, v);
      else if (tag === '실권') powerRow(no, v);
      else later.push({ no, tag, v }); // 폭 · 이설 · 원어 — 줄 목록을 다 읽은 뒤에
    }
    /* 글 층: 설명 · 실재근거 · 쟁점은 이름만 남긴 링크로, 문서는 줄을 그대로 이어 나무위키 링크로 */
    for (const [k, list] of Object.entries(texts)) {
      if (k === 'wiki') {
        const w = unlink(list.join('\n'), 'namu').replace(/\s+$/, '');
        if (w.trim()) fields.wiki = w;
      } else if (bare(list.join('\n'))) fields[k] = bare(list.join('\n'));
    }
    if (fields.startUnknown && fields.start == null && fields._placeStart != null) fields.start = fields._placeStart;
    if (fields.endUnknown && fields.end == null && fields._placeEnd != null) fields.end = fields._placeEnd;
    delete fields._placeStart;
    delete fields._placeEnd;
    /* 줄 목록: 덧층을 열쇠로 붙인 뒤 한 줄씩 읽음(줄 묶음 붙여넣기의 readRow 그대로 — 날짜 · 대수 · 역할 · 확실성 · 자리 이음) */
    for (const s of subs) {
      if (s.v.status !== undefined) {
        if (bare(s.v.status)) say(s.no, s.tag, `"${bare(s.v.key)}" 칸의 정통성은 작업본이 형식 4가 된 뒤에 담깁니다 — 뺐습니다`);
        delete s.v.status;
      }
      const host = findRaw(rows[s.def.of], bare(s.v.key), s.def.of);
      if (!host) { say(s.no, s.tag, `"${bare(s.v.key)}" 줄이 없습니다 — 열쇠는 그 줄의 ${s.def.of === 'capitals' ? '도시' : s.def.of === 'people' ? '이름' : '대표 이름(같은 이름이 여럿이면 "이름@시작 해")'}`); continue; }
      for (const [k, x] of Object.entries(s.v)) if (k !== 'key' && bare(x)) host.v[k] = x;
    }
    for (const list of CELL_LISTS) {
      if (!rows[list]) continue;
      const out = [];
      rows[list].forEach(({ no, v }, i) => {
        const keys = Object.keys(v).filter(k => bare(v[k]) !== '' || k === 'start');
        const r = readRow(keys.map(k => bare(v[k])), keys, list, { startOptional: list === 'ranks' && i === 0 });
        if (r.error) return say(no, LIST_LABEL[list], `넣지 않았습니다 — ${r.error}`);
        for (const k of Object.keys(r.cell)) if (r.cell[k] === undefined) delete r.cell[k];
        out.push(r.cell);
      });
      if (out.length) lists[list] = out;
    }
    if (phases.length) lists.phases = phases.map(g => Object.assign(g, { note: schemeNotes[g.scheme] || g.note || '' }));
    if (v2) settleContainers();
    /* 객체 층의 으뜸 — 그 상위 정권의 소속 줄에 표시(소속 줄을 다 읽은 뒤) */
    if (fields._main) {
      const row = (lists.partOf || []).find(p => p.polity === fields._main);
      if (row) row.main = true;
      else problems.push(`객체 층의 으뜸 "${fields._main}" — 그 이름의 소속 줄이 없어 표시하지 않았습니다`);
      delete fields._main;
    }
    /* 인물 — 덧층(인물계보 · 인물활동 · 인물별칭)은 위에서 그 줄에 붙였음 */
    const people = [];
    for (const { no, v } of rows.people || []) personRow(no, v);
    /* 폭 · 이설 · 원어 — 대상의 줄(나라면 나라 자신)에 */
    for (const { no, tag, v } of later) {
      const target = bare(v.target), key = bare(v.key);
      if (!(target in TT)) { say(no, tag, `대상 "${target}"을(를) 알 수 없습니다 (${Object.keys(TT).join(' · ')})`); continue; }
      const list = TT[target];
      if (list === 'people' && tag !== '원어') { say(no, tag, '인물에는 원어만 붙습니다 — 생몰이 갈리면 메모에 적습니다'); continue; }
      if (tag === '원어') {
        if (!['leaders', 'cabinets', 'eras', 'people', 'officeCells'].includes(list)) { say(no, tag, `원어는 지도자 · 내각 · ${v2 ? '직위칸 · ' : ''}연호 · ${v2 ? '사람' : '인물'} 줄에만 붙습니다`); continue; }
        const name = { text: bare(v.text) };
        if (!name.text) continue;
        if (bare(v.lang)) name.lang = bare(v.lang);
        if (bare(v.kind)) name.kind = HT.nameKind(bare(v.kind)) || bare(v.kind);
        if (bare(v.note)) name.note = bare(v.note);
        if (list === 'officeCells') { // 직위 줄 더의 칸 — 편집 창에 붙일 줄 목록이 아니라 이 답의 칸에 바로
          const c = findRow((lists.offices || []).flatMap(o => o.cells || []), key, 'leaders');
          if (!c) say(no, tag, `직위칸 "${key}" 줄이 없습니다`);
          else if (!(c.names = c.names || []).some(n => n.text === name.text && (n.lang || '') === (name.lang || ''))) c.names.push(name);
          continue;
        }
        if (list === 'people') {
          const p = people.find(q => q.name === key);
          if (!p) say(no, tag, `인물 "${key}" 줄이 없습니다`);
          else if (!(p.names = p.names || []).some(n => n.text === name.text && (n.lang || '') === (name.lang || ''))) p.names.push(name);
          continue;
        }
        nameAdds.push({ list, key, name });
        continue;
      }
      const host = !list ? null : list === 'partOf' ? (lists.partOf || []).find(p => p.polity === key) : list === 'officeCells' ? findRow((lists.offices || []).flatMap(o => o.cells || []), key, 'leaders') : findRow(lists[list], key, list);
      if (list && !host) { say(no, tag, `${target} "${key}" 줄이 없습니다`); continue; }
      if (tag === '폭') {
        for (const [k, a, b, w] of [['startRange', v.sa, v.sb, '시작'], ['endRange', v.ea, v.eb, '끝']]) {
          const r = readPair(a, b);
          if (r && r.error) say(no, tag, `${w} 연대 폭 "${bare(a)} ~ ${bare(b)}"을(를) 읽을 수 없습니다`);
          else if (r) {
            const o = host || fields;
            o[k] = r.range;
            if (r.at) o[`${k}At`] = r.at;
          }
        }
      } else {
        const alt = alternativeOf(v.start, v.end, v.label, v.source, v.note);
        if (!alt) continue;
        if (!host && alt.start == null && (alt.end != null || alt.ongoing)) { say(no, tag, '나라의 이설은 시작부터 적습니다(근거만 적으려면 날짜를 모두 비움)'); continue; }
        if (host) (host.alternatives = host.alternatives || []).push(alt);
        else (lists.alternatives = lists.alternatives || []).push(alt);
      }
    }
    return { fields, lists, nameAdds, others, people, problems, skipped: [], found, title: fields.name || '', version };

    /** 인물 줄 → { no, name, lineageOnly, role?, birth(At)?, death(At)?, description?, house?, order?, aka?, names?, service?(이 나라의 활동 기록 한 줄 — 나라 이름은 넣을 때),
        importance?, certainty?(부모 줄의 확실성), refs: { father?, mother?, adoptive?, spouses? }(사람 글 — 넣을 때 사람을 찾아 잇습니다) } */
    function personRow(no, v) {
      const name = bare(v.name);
      if (!name) return say(no, '인물', '이름이 없습니다');
      if (HT.isUnknownWho(name)) return say(no, '인물', '이름 미상의 사람은 줄로 넣지 않습니다 — 그 자식의 부 · 모 자리에 "미상"을 적습니다');
      if (people.some(p => p.name === name)) return say(no, '인물', `«${name}» 줄이 이미 있습니다 — 같은 이름의 두 사람은 이름을 구별해 적습니다`);
      const kind = bare(v.kind).replace(/\s/g, '');
      const p = { no, name, lineageOnly: true, kindSet: !!kind, refs: {} }; // kindSet: 구분을 적었는지(있는 사람을 고칠 때 적지 않았으면 계보 · 활동을 그대로)
      if (/^(활동|띠인물)$/.test(kind)) p.lineageOnly = false;
      else if (kind && !/^(계보|계보전용)$/.test(kind)) say(no, '인물', `«${name}»의 구분 "${kind}"을(를) 알 수 없어 계보로 넣습니다 (계보 · 활동)`);
      if (bare(v.role)) p.role = bare(v.role);
      for (const [k, w] of [['birth', '생'], ['death', '몰']]) {
        const d = readWhen(v[k]);
        if (d && d.error != null) say(no, '인물', `«${name}»의 ${w} "${bare(v[k])}"을(를) 읽을 수 없어 비웠습니다`);
        else if (d && d.t != null && !d.unknown) {
          p[k] = d.t;
          if (d.at) p[`${k}At`] = d.at;
        }
      }
      for (const k of ['father', 'mother', 'adoptive']) if (bare(v[k])) p.refs[k] = bare(v[k]);
      const sp = bare(v.spouse).split(/[·、]/).map(x => x.trim()).filter(x => x && !HT.isUnknownWho(x));
      if (sp.length) p.refs.spouses = sp;
      if (bare(v.note)) p.description = bare(v.note);
      if (bare(v.house)) p.house = bare(v.house);
      if (bare(v.order)) {
        const n = Number(bare(v.order));
        if (Number.isInteger(n)) p.order = n;
        else say(no, '인물계보', `«${name}»의 형제 순서 "${bare(v.order)}"은(는) 정수로 적습니다`);
      }
      if (bare(v.certainty)) {
        const c = certaintyId(bare(v.certainty));
        if (!c) say(no, '인물계보', `«${name}»의 확실성 "${bare(v.certainty)}"을(를) 알 수 없습니다 (${HT.CERTAINTY.map(x => x.name).join(' · ')})`);
        else if (c !== 'accepted') p.certainty = c;
      }
      if (bare(v.aka)) p.aka = [...new Set(bare(v.aka).split(/[·、]/).map(x => x.trim()).filter(Boolean))];
      if (['start', 'end', 'office', 'importance'].some(k => bare(v[k]))) {
        p.lineageOnly = false; // 활동 기록이 있으면 띠 인물
        p.kindSet = true;
        const s = {};
        for (const [k, w] of [['start', '시작'], ['end', '끝']]) {
          const d = readWhen(v[k]);
          if (d && d.error != null) say(no, '인물활동', `«${name}»의 활동 ${w} "${bare(v[k])}"을(를) 읽을 수 없어 비웠습니다`);
          else putWhen(s, k, d);
        }
        if (bare(v.office)) s.office = bare(v.office);
        p.service = s;
        if (bare(v.importance)) {
          const n = Number(bare(v.importance));
          if ([1, 2, 3].includes(n)) p.importance = n;
          else say(no, '인물활동', `«${name}»의 중요도 "${bare(v.importance)}"은(는) 1 · 2 · 3으로 적습니다`);
        }
      }
      const dated = p.birth != null || p.death != null || (p.service && (p.service.start != null || p.service.end != null));
      if (!p.lineageOnly && !dated) {
        say(no, '인물', `«${name}»은(는) 날짜(생 · 몰 · 활동 시작 · 끝)가 없어 계보로 넣습니다`);
        p.lineageOnly = true;
        delete p.service;
        delete p.importance;
      }
      people.push(p);
    }
    /* ---- 판 2의 층 ---- */
    /** 객체 층 — 머리(이름 · 기간 · 트랙 · 민족 · 국성 · 남북 위치)는 판 1의 나라와 같고, 종류는 형식 4의 열여덟(옛 종류 이름도 받음) · 정통성 · 중요도 */
    function head2(no, v) {
      nation(no, Object.assign({}, v, { kind: '' }));
      const t = bare(v.kind);
      if (t) {
        const id = HT.F4 ? HT.F4.typeId(t) : '';
        if (id && id !== 'person') fields.type = id;
        else if (HT.polityKindId(t)) fields.kind = HT.polityKindId(t);
        else say(no, '객체', `종류 "${t}"을(를) 알 수 없어 비웠습니다 (${HT.F4.TYPES.filter(x => x.id !== 'person').map(x => x.name).join(' · ')})`);
      }
      objectRow(no, { type: '', status: v.status, importance: v.importance, main: '' });
    }
    /** 그릇 층 — 시대 그릇이면 그 대범위에 들고(저장할 때 joinScope), 그 밖(나라 · 연방 · 동군연합 · 동맹 · 국가)이면 상위 띠에 접기(소속 줄 nest) */
    function containerRow(no, v) {
      const name = bare(v.name);
      if (!name) return say(no, '그릇', '그릇 이름이 없습니다');
      const t = bare(v.type);
      const tid = t && HT.F4 ? HT.F4.typeId(t) : '';
      if (t && !tid) say(no, '그릇', `«${name}»의 종류 "${t}"을(를) 알 수 없어 연표의 그릇대로 봅니다`);
      if (bare(v.start) || bare(v.end)) say(no, '그릇', `«${name}»에 든 기간은 작업본이 형식 4가 된 뒤에 담깁니다 — 기간 없이 넣었습니다`);
      if (bare(v.status)) say(no, '그릇', `«${name}» 구간의 정통성은 작업본이 형식 4가 된 뒤에 담깁니다 — 뺐습니다`);
      containers.push({ no, name, tid, main: ON_RE.test(bare(v.main)) });
    }
    /** 시대 층 — 그 시대 그릇의 제 칸(그릇 줄이 가리킬 때 대범위 · 시대 구분을 만들거나 채우는 데 씀) */
    function eraRow(no, v) {
      const name = bare(v.name);
      if (!name) return say(no, '시대', '이름이 없습니다');
      const it = { name };
      for (const [k, w] of [['start', '시작'], ['end', '끝']]) {
        const d = readWhen(v[k], { ongoingOK: k === 'end' });
        if (d && (d.error != null || d.unknown)) say(no, '시대', `«${name}»의 ${w} "${bare(v[k])}"은(는) 연도로 적습니다 — 비웠습니다`);
        else putWhen(it, k, d);
      }
      const w = bare(v.where);
      if (w) {
        const tid = trackIdOf(w, opt.tracks);
        const sid = tid ? '' : sphereIdOf(w);
        if (tid) it.track = tid;
        else if (sid) it.sphere = sid;
        else say(no, '시대', `트랙 또는 문화권 "${w}"이(가) 없어 비웠습니다`);
      }
      if (bare(v.label)) it.label = bare(v.label);
      if (bare(v.host)) it.host = bare(v.host);
      if (bare(v.description)) it.description = bare(v.description);
      if (eraLines.has(name)) return say(no, '시대', `«${name}» 줄이 이미 있습니다`);
      eraLines.set(name, Object.assign(it, { no }));
    }
    /** 구성원 층 — 이 객체가 그릇 노릇일 때 그 객체의 그릇 칸(상위 띠에 접기)에 이 객체 — 저장할 때(linkOther 'contain') */
    function memberRow(no, v) {
      const name = bare(v.name);
      if (!name) return;
      if (bare(v.start) || bare(v.end)) say(no, '구성원', `«${name}»이(가) 든 기간은 작업본이 형식 4가 된 뒤에 담깁니다 — 기간 없이 넣습니다`);
      const it = { kind: 'contain', name };
      if (ON_RE.test(bare(v.main))) it.main = true;
      if (bare(v.note)) it.note = bare(v.note);
      memberRows.push({ no, it });
    }
    /** 주기 층 — 바탕 자료 「주기」 표(yearCycles)의 그 문화권 줄 — 저장할 때(joinCycle — 그 문화권에 이미 있으면 그대로) */
    function cycleRow(no, v) {
      const sp = bare(v.sphere);
      if (!sp) return say(no, '주기', '문화권이 없습니다');
      const sid = sphereIdOf(sp);
      if (!sid) return say(no, '주기', `문화권 "${sp}"이(가) 없습니다 — 바탕 자료의 「문화권」 탭이나 켠 DLC의 문화권`);
      if (others.some(o => o.kind === 'cycle' && o.sphere === sid)) return say(no, '주기', `문화권 «${sp}»의 줄이 이미 있습니다`);
      const it = { kind: 'cycle', name: sp, sphere: sid };
      const names = bare(v.names).split(/[·、]/).map(x => x.trim()).filter(Boolean);
      const int = (k, w) => {
        if (!bare(v[k])) return undefined;
        const n = Number(bare(v[k]));
        if (Number.isInteger(n)) return n;
        say(no, '주기', `${w} "${bare(v[k])}"은(는) 정수로 적습니다 — 비웠습니다`);
        return undefined;
      };
      if (names.length) {
        it.names = names;
        const s = int('start', '시작');
        if (s !== undefined) it.start = s;
      } else if (bare(v.era)) {
        it.era = bare(v.era);
        const f = int('from', '기준 해'), st = int('step', '간격');
        if (f !== undefined) it.from = f;
        if (st !== undefined) it.step = st;
      } else return say(no, '주기', '이름들이나 연호를 적습니다');
      if (bare(v.label)) it.label = bare(v.label);
      others.push(it);
    }
    /** 그릇 · 구성원 · 시대 줄을 다 읽은 뒤: 시대 그릇(종류 시대 · 이 블록의 시대 줄 · 연표에 있는 시대 이름)은 대범위에 넣을 것으로, 나머지는 상위 띠에 접기(소속 줄 nest)로 */
    function settleContainers() {
      const eras = new Set(opt.eras || []);
      const used = new Set();
      for (const c of containers) {
        const isEra = c.tid === 'era' || (!c.tid && (eraLines.has(c.name) || eras.has(c.name)));
        if (isEra) {
          const e = eraLines.get(c.name);
          if (e) used.add(c.name);
          const it = { kind: 'epoch', name: c.name };
          if (e) for (const k of ['start', 'startAt', 'end', 'endAt', 'ongoing', 'sphere', 'label', 'host', 'description']) if (e[k] != null) it[k] = e[k];
          if (others.some(o => o.kind === 'epoch' && o.name === c.name)) { say(c.no, '그릇', `«${c.name}» 줄이 이미 있습니다`); continue; }
          others.push(it);
          continue;
        }
        const list = (lists.partOf = lists.partOf || []);
        const row = list.find(p => p.polity === c.name && p.start == null && p.end == null); // 같은 상대의 섬김 줄(기간 없음)이 있으면 그 줄에 접기를 켬
        if (row) {
          row.nest = true;
          if (c.main) row.main = true;
        } else list.push(Object.assign({ polity: c.name, nest: true }, c.main ? { main: true } : {}));
      }
      /* 옛 꼴의 접기는 소속 줄이 하나뿐이고 기간이 없을 때만 그릇이 된다(HT.F4 folds) — 섬김 · 그릇 줄이 여럿이면 소속 줄로만 남음을 알림 */
      const nests = (lists.partOf || []).filter(p => p.nest === true);
      if (nests.length && lists.partOf.length > 1)
        for (const p of nests) say((containers.find(c => c.name === p.polity) || {}).no || 0, '그릇', `«${p.polity}»에 접기는 섬김 · 그릇 줄이 하나뿐일 때만 됩니다 — 작업본이 형식 4가 된 뒤에는 여럿도 됨 · 지금은 소속 줄로만 들어갑니다`);
      const headEra = fields.type === 'era';
      for (const [name, e] of eraLines) {
        if (used.has(name)) continue;
        say(e.no, '시대', headEra
          ? `머리 객체가 시대일 때의 제 칸(성격 · 상징적 본국 · 자리)은 작업본이 형식 4가 된 뒤에 담깁니다 — 넣지 않았습니다`
          : `«${name}»을(를) 가리키는 그릇 줄이 없어 넣지 않았습니다`);
      }
      for (const { no, it } of memberRows) {
        if (headEra) say(no, '구성원', `시대 객체의 구성원은 그 객체의 그릇 줄로 적습니다(작업본이 형식 4가 된 뒤에는 이 줄로도) — «${it.name}»은(는) 넣지 않았습니다`);
        else others.push(it);
      }
    }
    function nation(no, v) {
      if (bare(v.name)) fields.name = bare(v.name);
      const s = readWhen(v.start);
      if (s && s.error != null) say(no, '나라', `시작 "${bare(v.start)}"을(를) 읽을 수 없어 바꾸지 않았습니다${s.error ? ` (${s.error})` : ''}`);
      else if (s && s.unknown) {
        fields.startUnknown = true;
        if (s.t != null) fields.start = s.t;
      } else if (s) {
        fields.start = s.t;
        if (s.at) fields.startAt = s.at;
      }
      const e = readWhen(v.end, { ongoingOK: true });
      if (e && e.error != null) say(no, '나라', `끝 "${bare(v.end)}"을(를) 읽을 수 없어 바꾸지 않았습니다${e.error ? ` (${e.error})` : ''}`);
      else if (e && e.ongoing) fields.ongoing = true;
      else if (e && e.unknown) {
        fields.endUnknown = true;
        if (e.t != null) fields.end = e.t;
      } else if (e) {
        fields.end = e.t;
        if (e.at) fields.endAt = e.at;
      }
      if (bare(v.track)) {
        const id = trackIdOf(v.track, opt.tracks);
        if (id) fields.track = id;
        else say(no, '나라', `트랙 "${bare(v.track)}"이(가) 없어 바꾸지 않았습니다 (있는 트랙: ${(opt.tracks || []).map(x => x.name || x.id).join(' · ') || '없음'})`);
      }
      if (bare(v.kind)) {
        const id = HT.polityKindId(bare(v.kind));
        if (id) fields.kind = id;
        else say(no, '나라', `종류 "${bare(v.kind)}"을(를) 알 수 없어 바꾸지 않았습니다`);
      }
      if (bare(v.people)) fields.people = bare(v.people);
      if (bare(v.house)) fields.house = bare(v.house);
      if (bare(v.northSouth)) {
        const n = Number(bare(v.northSouth));
        if (Number.isFinite(n) && n >= -90 && n <= 90) fields.northSouth = n;
        else say(no, '나라', `남북 위치 "${bare(v.northSouth)}"은(는) -90 ~ 90의 수로 적습니다`);
      }
    }
    function dating(no, v) {
      if (bare(v.historicity)) {
        const h = HT.historicity(bare(v.historicity));
        if (h) fields.historicity = h === 'attested' ? '' : h;
        else say(no, '연대', `실재성 "${bare(v.historicity)}"을(를) 알 수 없어 바꾸지 않았습니다`);
      }
      if (bare(v.certainty)) {
        const c = certaintyId(bare(v.certainty));
        if (c) fields.certainty = c;
        else say(no, '연대', `확실성 "${bare(v.certainty)}"을(를) 알 수 없어 바꾸지 않았습니다`);
      }
      for (const [k, w] of [['placeStart', '_placeStart'], ['placeEnd', '_placeEnd']]) {
        if (!bare(v[k])) continue;
        const d = readEdge(bare(v[k]));
        if (d && d.error == null && !d.unknown) fields[w] = d.t;
        else say(no, '연대', `배치용 연도 "${bare(v[k])}"을(를) 읽을 수 없습니다`);
      }
    }
    function nameRow(no, v) {
      const o = { text: bare(v.text) };
      if (!o.text) return;
      if (bare(v.lang)) o.lang = bare(v.lang);
      if (bare(v.kind)) o.kind = HT.nameKind(bare(v.kind)) || bare(v.kind);
      const x = readWhen(v.start), y = readWhen(v.end);
      if ((x && x.error != null) || (y && y.error != null)) say(no, '이름', `"${o.text}"의 쓴 기간을 읽을 수 없어 비웠습니다`);
      else {
        putWhen(o, 'start', x);
        putWhen(o, 'end', y);
      }
      if (bare(v.note)) o.note = bare(v.note);
      (lists.names = lists.names || []).push(o);
    }
    function partRow(no, v) {
      const o = { polity: bare(v.polity) };
      if (!o.polity) return;
      const rel = bare(v.relation);
      if (rel && !/^소속\s*관계\s*없음$|^없음$/.test(rel)) {
        const id = HT.relationId(rel);
        if (id) o.relation = id;
        else say(no, '소속', `"${o.polity}"의 소속 관계 "${rel}"을(를) 알 수 없어 비웠습니다`);
      }
      for (const k of ['start', 'end']) {
        const d = readWhen(v[k]);
        if (d && d.error != null) say(no, '소속', `"${o.polity}"의 ${k === 'start' ? '시작' : '끝'} "${bare(v[k])}"을(를) 읽을 수 없어 비웠습니다`);
        else putWhen(o, k, d);
      }
      const nest = bare(v.nest);
      if (/^(켬|예|o|on|true)$/i.test(nest)) o.nest = true;
      else if (/^(끔|아니오|x|off|false)$/i.test(nest)) o.nest = false;
      if (bare(v.note)) o.note = bare(v.note);
      (lists.partOf = lists.partOf || []).push(o);
    }
    /* 형식 4의 칸(5단계 과제 7) */
    function objectRow(no, v) {
      const t = bare(v.type);
      if (t) {
        const id = HT.F4 ? HT.F4.typeId(t) : '';
        if (id && id !== 'person') fields.type = id;
        else say(no, '객체', `종류 "${t}"을(를) 알 수 없어 비웠습니다 (${HT.F4.TYPES.filter(x => x.id !== 'person').map(x => x.name).join(' · ')})`);
      }
      const s = bare(v.status);
      if (s) {
        const id = HT.F4 ? HT.F4.statusId(s) : '';
        if (id) fields.status = id;
        else say(no, '객체', `정통성 "${s}"을(를) 알 수 없어 비웠습니다 (${HT.F4.STATUSES.map(x => x.name).join(' · ')})`);
      }
      const im = bare(v.importance);
      if (im) {
        const n = Number(im);
        if ([0, 1, 2, 3].includes(n)) fields.importance = n;
        else say(no, '객체', `중요도 "${im}"은(는) 0~3 가운데 하나여야 해서 비웠습니다`);
      }
      if (bare(v.main)) fields._main = bare(v.main);
    }
    function borrowRow(no, v) {
      const slot = bare(v.slot);
      const key = /내각/.test(slot) ? 'cabinetsFrom' : /지도자/.test(slot) ? 'leadersFrom' : '';
      if (!key) return say(no, '빌림', `자리 "${slot}"은(는) 지도자 · 내각 가운데 하나여야 합니다`);
      const from = bare(v.from);
      if (!from) return say(no, '빌림', '출처("객체 id" 또는 "객체 id/직위 이름")가 없습니다');
      const b = {};
      const nm = bare(v.name);
      if (nm && nm !== (key === 'cabinetsFrom' ? '내각' : '지도자')) b.name = nm;
      b.from = from;
      fields[key] = b;
    }
    function officeRow(no, v) {
      const name = bare(v.name), from = bare(v.from);
      if (!name && !from) return say(no, '직위줄', '직위 이름이 없습니다');
      (lists.offices = lists.offices || []).push(from ? Object.assign(name ? { name } : {}, { from }) : { name, cells: [] });
    }
    function officeCellRow(no, v) {
      const key = bare(v.key);
      const host = (lists.offices || []).find(o => o.name === key);
      if (!host) return say(no, '직위칸', `"${key}" 직위 줄이 없습니다 — 먼저 직위줄 층으로 적습니다`);
      if (host.from) return say(no, '직위칸', `"${key}"은(는) 빌린 줄이라 칸을 넣지 않습니다`);
      const keys = ['ordinal', 'name', 'start', 'end', 'certainty', 'note'].filter(k => bare(v[k]) !== '' || k === 'start');
      const r = readRow(keys.map(k => bare(v[k])), keys, 'leaders', {});
      if (r.error) return say(no, '직위칸', `넣지 않았습니다 — ${r.error}`);
      for (const k of Object.keys(r.cell)) if (r.cell[k] === undefined) delete r.cell[k];
      host.cells.push(r.cell);
    }
    function powerRow(no, v) {
      const over = bare(v.over);
      if (!over && !bare(v.name)) return say(no, '실권', '상대(빼앗긴 객체의 id나 이름)도, 이름(제 안의 실권자 — 세도 가문 · 권신)도 없습니다 — 남의 실권은 쥔 쪽에 상대로, 제 안의 실권자는 이름으로 적습니다');
      const w = {};
      if (bare(v.name)) w.name = bare(v.name);
      if (over) w.over = over;
      for (const k of ['start', 'end']) {
        const d = readWhen(v[k]);
        if (d && d.error != null) say(no, '실권', `"${over || bare(v.name)}"의 ${k === 'start' ? '시작' : '끝'} "${bare(v[k])}"을(를) 읽을 수 없어 비웠습니다`);
        else putWhen(w, k, d);
      }
      if (bare(v.note)) w.note = bare(v.note);
      (lists.power = lists.power || []).push(w);
    }
    function succRow(no, v) {
      const from = bare(v.from);
      if (!from) return;
      const type = succTypeOf(v.type);
      if (!type) return say(no, '승계', `"${from}"의 승계 종류 "${bare(v.type)}"을(를) 알 수 없어 넣지 않았습니다 (${HT.SUCCESSION.map(x => x.name).join(' · ')})`);
      if (bare(v.how)) say(no, '승계', `"${from}"의 승계 방식 "${bare(v.how)}"은(는) 작업본이 형식 4가 된 뒤에 담깁니다 — 뺐습니다`);
      const raw = { from, type };
      if (bare(v.degree)) raw.degree = bare(v.degree);
      if (bare(v.parts)) raw.parts = bare(v.parts);
      if (bare(v.note)) raw.note = bare(v.note);
      const n = HT.normalizeSucc(raw, m => say(no, '승계', m));
      if (n) (lists.succeeds = lists.succeeds || []).push(n);
    }
    function phaseRow(no, v) {
      const scheme = bare(v.scheme), name = bare(v.name);
      if (!name) return say(no, '시기', '시기 이름이 없습니다');
      let g = phases.find(x => x.scheme === scheme);
      if (!g) phases.push((g = { scheme, note: '', spans: [] }));
      const o = { name };
      for (const k of ['start', 'end']) {
        const d = readWhen(v[k]);
        if (d && d.error != null) say(no, '시기', `"${name}"의 ${k === 'start' ? '시작' : '끝'} "${bare(v[k])}"을(를) 읽을 수 없어 비웠습니다`);
        else putWhen(o, k, d);
      }
      if (bare(v.note)) o.note = bare(v.note);
      g.spans.push(o);
    }
    function otherRow(no, tag, v) {
      const name = bare(v.name);
      if (!name) return;
      if (tag === '이어받은나라') {
        if (bare(v.how)) say(no, tag, `"${name}"의 승계 방식 "${bare(v.how)}"은(는) 작업본이 형식 4가 된 뒤에 담깁니다 — 뺐습니다`);
        const type = succTypeOf(v.type);
        if (!type) return say(no, tag, `"${name}"의 승계 종류 "${bare(v.type)}"을(를) 알 수 없어 넣지 않았습니다`);
        const it = { kind: 'succ', name, type };
        if (bare(v.note)) it.note = bare(v.note);
        others.push(it);
        return;
      }
      const it = { kind: 'member', name };
      const rel = bare(v.relation);
      if (rel && !/^소속\s*관계\s*없음$|^없음$/.test(rel)) {
        const id = HT.relationId(rel);
        if (id) it.relation = id;
        else return say(no, tag, `"${name}"의 소속 관계 "${rel}"을(를) 알 수 없어 넣지 않았습니다`);
      }
      for (const k of ['start', 'end']) {
        const d = readWhen(v[k]);
        if (d && d.error != null) say(no, tag, `"${name}"의 ${k === 'start' ? '시작' : '끝'} "${bare(v[k])}"을(를) 읽을 수 없어 비웠습니다`);
        else putWhen(it, k, d);
      }
      others.push(it);
    }
    /** 시대구분 · 대범위 줄 → others의 { kind: 'epoch', name, start(At)?, end(At)? · ongoing? } · { kind: 'scope', name, label?, host? } */
    function scopeRow(no, tag, v) {
      const name = bare(v.name);
      if (!name) return say(no, tag, '이름이 없습니다');
      const kind = tag === '시대구분' ? 'epoch' : 'scope';
      if (others.some(o => o.kind === kind && o.name === name)) return say(no, tag, `«${name}» 줄이 이미 있습니다`);
      const it = { kind, name };
      if (kind === 'scope') {
        if (bare(v.label)) it.label = bare(v.label);
        if (bare(v.host)) it.host = bare(v.host);
      } else {
        for (const [k, w] of [['start', '시작'], ['end', '끝']]) {
          const d = readWhen(v[k], { ongoingOK: k === 'end' });
          if (d && (d.error != null || d.unknown)) say(no, tag, `«${name}»의 ${w} "${bare(v[k])}"은(는) 연도로 적습니다 — 비웠습니다`);
          else putWhen(it, k, d);
        }
      }
      others.push(it);
    }
  }
  /** 덧층의 열쇠로 읽기 전의 줄(rows의 { v }) 찾기 — 대표 이름(도읍은 도시), "이름@시작 해"면 시작 해까지 */
  function findRaw(rows, key, list) {
    const [nm, at] = String(key).split('@').map(x => x.trim());
    const y = at && /^-?\d+$/.test(at) ? Number(at) : null;
    return (rows || []).find(r => bare(list === 'capitals' ? r.v.city : r.v.name) === nm && (y == null || (() => { const d = readWhen(r.v.start); return d && d.t != null && !d.error && yearOf(d.t) === y; })())) || null;
  }
  /** 다른 나라에 넣을 것 하나(it — parseWhole의 others)를 그 나라의 원본(raw — 고침)에: 이 나라(name)를 승계 칸(이어받은 정권) · 소속 칸(속했던 정권)에.
      이미 이 나라를 가리키는 줄이 있으면 종류 · 관계 · 기간만 맞춤(메모는 비었을 때만) → 'added' · 'updated' · 'same' */
  function linkOther(raw, it, name) {
    if (!raw || !it || !name || it.name === name) return 'same';
    if (it.kind === 'succ') {
      const list = (Array.isArray(raw.succeeds) ? raw.succeeds : raw.succeeds ? [raw.succeeds] : []).map(s => HT.normalizeSucc(s)).filter(Boolean);
      const at = list.findIndex(s => s.from === name);
      if (at >= 0) {
        const s = list[at];
        if (s.type === it.type) return 'same';
        list[at] = HT.normalizeSucc(Object.assign({}, s, { type: it.type, note: s.note || it.note }));
        raw.succeeds = list;
        return 'updated';
      }
      list.push(HT.normalizeSucc({ from: name, type: it.type, note: it.note }));
      raw.succeeds = list;
      return 'added';
    }
    if (it.kind === 'contain') { // 판 2 구성원 층 — 그 객체가 이 객체(그릇)에 접혀 듦(기간 없는 소속 줄의 nest · 으뜸)
      const list = HT.readPartOf(raw.partOf, { relation: true });
      const at = list.findIndex(s => s.polity === name && s.start == null && s.end == null && !s.startUnknown && !s.endUnknown);
      if (at >= 0) {
        const next = Object.assign({}, list[at], { nest: true }, it.main ? { main: true } : {});
        if (JSON.stringify(next) === JSON.stringify(list[at])) return 'same';
        list[at] = next;
        raw.partOf = HT.compactPartOf(list);
        return 'updated';
      }
      list.push(Object.assign({ polity: name, nest: true }, it.main ? { main: true } : {}));
      raw.partOf = HT.compactPartOf(list);
      return 'added';
    }
    const list = HT.readPartOf(raw.partOf, { relation: true });
    const want = { polity: name };
    for (const k of ['relation', 'start', 'startAt', 'startUnknown', 'end', 'endAt', 'endUnknown']) if (it[k] != null) want[k] = it[k];
    const at = list.findIndex(s => s.polity === name);
    if (at >= 0) {
      const next = Object.assign({}, list[at], want);
      if (JSON.stringify(next) === JSON.stringify(list[at])) return 'same';
      list[at] = next;
      raw.partOf = HT.compactPartOf(list);
      return 'updated';
    }
    list.push(want);
    raw.partOf = HT.compactPartOf(list);
    return 'added';
  }
  /** others의 한 줄이 대범위에 넣을 것(시대구분 · 대범위 층)인지 — 나머지(이어받은나라 · 속했던나라)는 다른 나라에 넣을 것 */
  const isScopeLink = l => !!l && (l.kind === 'epoch' || l.kind === 'scope' || l.kind === 'cycle');
  /** 주기 층(판 2) 하나를 작업본(d — 고침: d.yearCycles)에: 그 문화권의 줄이 없을 때만 새로(있으면 'same' — 프롬프트 "이미 있으면 새로 만들지 않음").
      others = 다른 DLC가 이미 가진 문화권 id 목록(있으면 'same'). → { result: 'new' · 'same' · 'none', why? } */
  function joinCycle(d, it, others = []) {
    if (!d || !it || !it.sphere) return { result: 'none', why: '문화권이 없습니다' };
    const list = Array.isArray(d.yearCycles) ? d.yearCycles : [];
    if (list.some(c => c && String(c.sphere || '') === it.sphere) || others.includes(it.sphere)) return { result: 'same' };
    const o = { sphere: it.sphere };
    for (const k of ['names', 'start', 'label', 'era', 'from', 'step']) if (it[k] != null && it[k] !== '') o[k] = Array.isArray(it[k]) ? it[k].slice() : it[k];
    d.yearCycles = list.concat(o);
    return { result: 'new' };
  }
  /** 대범위에 넣을 것 하나(it — parseWhole의 others 가운데 kind 'epoch'(시대구분 층) · 'scope'(대범위 층))를 작업본(d — 고침: d.scopes · d.epochs)에:
      이 나라(nation = { name, track, id? })를 같은 트랙의 내 대범위 구성 정권에 넣습니다. 형식 3의 시대 구분은 구성원이 없어, 시대구분은 그 시대 구분을 가리키는
      대범위(scopes[].epoch — 형식 4의 within과 같은 뜻)에 넣습니다.
      - 시대 구분: 내 것(d.epochs) · 남의 것(ctx.epochs = [{ name, id?, track? }]) 가운데 같은 이름 — 같은 트랙 먼저, 다음 공통(트랙 없음).
      - 대범위: 같은 트랙의 내 대범위 — 시대구분은 그 시대 구분을 가리키는 것(없으면 시대 구분을 적지 않은 같은 이름), 대범위는 같은 이름(이름을 비웠으면 시대 구분 이름).
        남의 DLC의 대범위(ctx.scopes = [{ name, epoch, track, packName? }])만 있으면 고치지 못함(대범위는 패치 대상이 아님 — DLC-형식.md 'scopes').
      - 대범위가 없으면 새로 만들고, 시대 구분도 없으면 줄의 시작 · 끝으로 이 나라의 트랙에 새로(기간이 없으면 못 넣음). 성격 · 본국은 비어 있을 때만 채움(본국이 이 나라면 적지 않음).
      ctx.add(list, obj) → 새 항목(메이커는 HT.draft.addItem으로 id를 매김 — 없으면 목록 끝에 그대로).
      → { result: 'new' · 'added' · 'updated' · 'same' · 'none' · 'foreign', epochNew(시대 구분도 새로 만듦), scope?(넣은 대범위), why?(none · foreign의 까닭) } */
  function joinScope(d, it, nation, ctx = {}) {
    const txt = v => (v == null ? '' : String(v).trim());
    const name = txt(nation && nation.name), track = txt(nation && nation.track);
    if (!d || !it || !name) return { result: 'none', epochNew: false, why: '나라 이름이 없습니다' };
    if (!track) return { result: 'none', epochNew: false, why: '나라의 트랙이 없습니다 — 대범위는 같은 트랙의 나라만 모읍니다' };
    const add = ctx.add || ((list, obj) => ((d[list] = Array.isArray(d[list]) ? d[list] : []).push(obj), obj));
    const pick = list => list.find(e => e && txt(e.name) === it.name && txt(e.track) === track) || list.find(e => e && txt(e.name) === it.name && !txt(e.track)) || null;
    let ep = it.kind === 'epoch' ? pick(Array.isArray(d.epochs) ? d.epochs : []) || pick(ctx.epochs || []) : null;
    const refs = ep ? [txt(ep.name), txt(ep.id)].filter(Boolean) : [it.name];
    const matches = s =>
      !!s && txt(s.track) === track &&
      (it.kind === 'epoch' ? refs.includes(txt(s.epoch)) || (!txt(s.epoch) && txt(s.name) === it.name) : txt(s.name) === it.name || (!txt(s.name) && txt(s.epoch) === it.name));
    let scope = (Array.isArray(d.scopes) ? d.scopes : []).find(matches) || null;
    if (!scope) {
      const other = (ctx.scopes || []).find(matches);
      if (other) return { result: 'foreign', epochNew: false, why: `«${other.packName || '다른 DLC'}»의 대범위라 고칠 수 없습니다 — 대범위는 그 DLC에서만 고칩니다` };
    }
    const me = [name, txt(nation.id)].filter(Boolean);
    let epochNew = false;
    if (!scope) {
      if (it.kind === 'epoch' && !ep) {
        if (it.start == null || (it.end == null && !it.ongoing)) return { result: 'none', epochNew, why: `시대 구분 «${it.name}»이(가) 연표에 없고 기간(시작 · 끝)이 없어 만들지 못합니다` };
        const o = it.sphere ? { name: it.name, sphere: it.sphere } : { name: it.name, track }; // 판 2 시대 줄의 문화권 — 문화권 머리 단 밑의 시대(트랙 없음)
        for (const k of ['start', 'startAt', 'end', 'endAt', 'ongoing', 'description']) if (it[k] != null) o[k] = it[k];
        ep = add('epochs', o);
        epochNew = true;
      }
      const o = { track };
      if (it.kind === 'epoch') {
        o.epoch = txt(ep.name);
        if (it.label) o.label = it.label; // 판 2의 시대 줄(성격 · 상징적 본국) — 판 1의 시대구분 줄에는 없음
        if (it.host && !me.includes(it.host)) o.host = it.host;
      } else {
        o.name = it.name;
        if (it.label) o.label = it.label;
        if (it.host && !me.includes(it.host)) o.host = it.host;
      }
      o.members = [name];
      return { result: 'new', epochNew, scope: add('scopes', o) };
    }
    const members = Array.isArray(scope.members) ? scope.members : scope.members ? [scope.members] : [];
    const isMe = m => (typeof m === 'string' ? me.some(x => txt(m) === x || txt(m) === `${track}:${x}`) : !!m && me.includes(txt(m.polity)) && (!txt(m.track) || txt(m.track) === track));
    let result = 'same';
    if (!members.some(isMe)) {
      scope.members = members.concat(name);
      result = 'added';
    }
    if (it.kind === 'scope' || it.label || it.host) {
      const put = (k, v) => {
        if (!v || txt(typeof scope[k] === 'object' && scope[k] ? scope[k].polity : scope[k])) return;
        scope[k] = v;
        if (result === 'same') result = 'updated';
      };
      put('label', it.label);
      if (!me.includes(it.host)) put('host', it.host);
    }
    return { result, epochNew, scope };
  }
  /** 칸 줄 찾기 — 열쇠는 대표 이름(도읍은 도시 · 그 밖은 이름), 같은 이름이 여럿이면 "이름@시작 해" */
  function findRow(rows, key, kind) {
    const keyOf = c => (kind === 'capitals' ? c.city : c.name || c.temple || c.title || c.given);
    const [nm, at] = String(key).split('@').map(x => x.trim());
    const y = at && /^-?\d+$/.test(at) ? Number(at) : null;
    return (rows || []).find(c => keyOf(c) === nm && (y == null || (c.start != null && yearOf(c.start) === y))) || null;
  }
  /** 이설 한 줄(시작 · 끝 · 근거 · 출처 · 메모 글) → 파일 꼴의 이설 · 아무것도 없으면 null (출처는 링크의 주소까지) */
  function alternativeOf(s, e, label, source, note) {
    const o = {};
    const x = readWhen(s), y = readWhen(e, { ongoingOK: true });
    if (x && x.error == null && !x.unknown) {
      o.start = x.t;
      if (x.at) o.startAt = x.at;
    }
    if (y && y.ongoing) o.ongoing = true;
    else if (y && y.error == null && !y.unknown) {
      o.end = y.t;
      if (y.at) o.endAt = y.at;
    }
    for (const [k, v] of [['label', label], ['source', unlink(source, 'source')], ['note', note]]) if (bare(v)) o[k] = bare(v);
    return Object.keys(o).length ? o : null;
  }
  /** 붙여넣은 글에 칸 블록이 있는지 (메이커의 Ctrl+V가 표 붙여넣기 대신 통째 붙여넣기로 보낼지) */
  const isWhole = text => blockLines(text).found > 0;

  const LIST_KEYS = ['names', 'partOf', 'succeeds', 'ranks', 'leaders', 'cabinets', 'eras', 'capitals', 'phases', 'alternatives', 'offices', 'power']; // offices · power = 형식 4의 직위 줄 더 · 실권(5단계 과제 7)
  const EDGE_KEYS = new Set(['start', 'startAt', 'startUnknown', 'end', 'endAt', 'endUnknown', 'ongoing']);
  /** 줄 목록의 지금 줄 (소속은 줄인 꼴 — 이름 하나 — 도 목록으로) */
  const listNow = (cur, k) => (k === 'partOf' ? HT.readPartOf(cur && cur.partOf, { relation: true }) : k === 'leaders' ? (cur && (cur.leaders || cur.reigns)) || [] : Array.isArray(cur && cur[k]) ? cur[k] : []);
  /**
   * 편집 창의 지금 값(cur — HT.FORMS.period.read의 item)에 읽은 답(r)을 얹은 값 → 편집 창을 다시 채울 값.
   * 낱칸은 적힌 것만 바꾸고, 줄 목록은 mode 'replace'(바꾸기 — 답에 있는 목록만 통째로) · 'append'(보태기 — 있는 줄 뒤에)
   */
  function mergeWhole(cur, r, mode = 'replace') {
    const out = JSON.parse(JSON.stringify(cur || {}));
    const f = r.fields || {};
    for (const [k, v] of Object.entries(f)) if (!EDGE_KEYS.has(k)) out[k] = v;
    if ('start' in f || f.startUnknown) {
      out.startUnknown = !!f.startUnknown;
      out.startAt = f.startUnknown ? null : f.startAt || null;
      if (f.start != null) out.start = f.start; // 미정이고 배치용 연도가 없으면 지금 자리를 배치용으로
    }
    if (f.ongoing) Object.assign(out, { ongoing: true, end: null, endAt: null, endUnknown: false });
    else if ('end' in f || f.endUnknown) {
      out.ongoing = false;
      out.endUnknown = !!f.endUnknown;
      out.endAt = f.endUnknown ? null : f.endAt || null;
      if (f.end != null) out.end = f.end;
    }
    for (const k of LIST_KEYS) {
      const add = (r.lists || {})[k];
      if (!add || !add.length) continue;
      out[k] = mode === 'append' ? listNow(cur, k).concat(JSON.parse(JSON.stringify(add))) : JSON.parse(JSON.stringify(add));
    }
    if (out.leaders) delete out.reigns;
    attachNames(out, r.nameAdds);
    return out;
  }
  /** 원어 이름(+원어)을 합친 값의 지도자 · 내각 · 연호 줄에 붙임 (같은 글 · 언어는 한 번) → 줄을 찾지 못한 것의 목록 */
  function attachNames(out, adds) {
    const missed = [];
    for (const a of adds || []) {
      if (a.list === 'leaders' && !out.leaders && out.reigns) out.leaders = out.reigns;
      const cell = findRow(out[a.list], a.key, a.list);
      if (!cell) {
        missed.push(a);
        continue;
      }
      const names = (cell.names = Array.isArray(cell.names) ? cell.names : []);
      if (!names.some(n => n.text === a.name.text && (n.lang || '') === (a.name.lang || ''))) names.push(Object.assign({}, a.name));
    }
    return missed;
  }
  /** 미리 보기의 줄 [{ label, text, now(지금 줄 수 — 줄 목록만), clash(바꾸기/보태기를 고를 것인지) }] */
  function wholeSummary(r, cur = {}, opt = {}) {
    const f = r.fields || {}, L = r.lists || {};
    const out = [];
    const when = k => (f[`${k}Unknown`] ? '미정' : f[k] == null ? '' : HT.formatDate ? HT.formatDate(f[k], f[`${k}At`]) : String(f[k]));
    const bits = [];
    if (f.name) bits.push(f.name);
    if ('start' in f || f.startUnknown || 'end' in f || f.endUnknown || f.ongoing) bits.push(`${when('start') || '…'} ~ ${f.ongoing ? '현재' : when('end') || '…'}`);
    if (f.track) bits.push(`트랙 ${((opt.tracks || []).find(t => t.id === f.track) || { name: f.track }).name}`);
    if (f.kind) bits.push(HT.kindName(f.kind));
    if (f.people) bits.push(`민족 ${f.people}`);
    if (f.house) bits.push(`국성 ${f.house}`);
    if (f.tags) bits.push(`꼬리표 ${f.tags.join(' · ')}`);
    if (bits.length) out.push({ label: '기본 칸', text: bits.join(' · ') });
    const f4 = [];
    if (f.type) f4.push(`종류 ${((HT.F4 && HT.F4.TYPES.find(t => t.id === f.type)) || { name: f.type }).name}`);
    if (f.status) f4.push(`정통성 ${((HT.F4 && HT.F4.STATUSES.find(t => t.id === f.status)) || { name: f.status }).name}`);
    if (f.importance != null) f4.push(`중요도 ${f.importance}`);
    if (f.leadersFrom) f4.push(`지도자 자리 빌림 ${f.leadersFrom.from}`);
    if (f.cabinetsFrom) f4.push(`내각 자리 빌림 ${f.cabinetsFrom.from}`);
    if ((L.partOf || []).some(p => p.main)) f4.push(`으뜸 ${L.partOf.find(p => p.main).polity}`);
    if (f4.length) out.push({ label: '객체(형식 4)', text: f4.join(' · ') });
    if (f.description) out.push({ label: '설명', text: `${f.description.length}자` });
    for (const k of LIST_KEYS) {
      if (!L[k] || !L[k].length) continue;
      const rows = L[k], now = listNow(cur, k).length;
      const extra = [];
      if (k === 'phases') extra.push(`체계 ${rows.length} · 시기 ${rows.reduce((n, g) => n + g.spans.length, 0)}`);
      else extra.push(`${rows.length}줄`);
      if (CELL_LISTS.includes(k)) {
        const cert = rows.filter(c => c.certainty).length, rng = rows.filter(c => c.startRange || c.endRange).length, alt = rows.reduce((n, c) => n + (c.alternatives || []).length, 0);
        if (cert) extra.push(`확실성 ${cert}`);
        if (rng) extra.push(`연대 폭 ${rng}`);
        if (alt) extra.push(`이설 ${alt}`);
      }
      out.push({ label: k === 'alternatives' ? '나라의 이설' : LIST_LABEL[k], text: extra.join(' · '), now, clash: now > 0 });
    }
    if ((r.nameAdds || []).length) {
      const missed = attachNames(mergeWhole(cur, Object.assign({}, r, { nameAdds: [] }), opt.mode || 'replace'), r.nameAdds);
      const hit = r.nameAdds.length - missed.length;
      out.push({ label: '원어 이름', text: `${hit}개${missed.length ? ` · 줄을 찾지 못한 ${missed.length}개(${[...new Set(missed.map(a => a.key))].slice(0, 4).join(' · ')})는 넣지 않음` : ''}`, none: !hit });
    }
    if ((r.people || []).length) {
      const lin = r.people.filter(p => p.lineageOnly).length;
      out.push({ label: '사람', text: [`${r.people.length}명`, lin && `계보 ${lin}`, r.people.length - lin && `활동 ${r.people.length - lin}`].filter(Boolean).join(' · ') });
    }
    if (f.northSouth != null) out.push({ label: '남북 위치', text: String(f.northSouth) });
    const dt = [];
    if ('historicity' in f) dt.push(`실재성 ${HT.historicityName(f.historicity)}`);
    if (f.historicityNote) dt.push('실재성의 근거');
    if (f.certainty) dt.push(`확실성 ${HT.certaintyName(f.certainty)}`);
    if (f.startRange) dt.push('시작 연대 폭');
    if (f.endRange) dt.push('끝 연대 폭');
    if (f.debate) dt.push('쟁점');
    if (dt.length) out.push({ label: '연대 · 실재성', text: dt.join(' · ') });
    if (f.wiki) out.push({ label: '문서', text: `${f.wiki.length}자` });
    return out;
  }

  /**
   * 통째 붙여넣기 창 — env = { form(편집 창 폼), tracks() → [{ id, name }], read() → 지금 값, refill(값) → 편집 창을 그 값으로(저장하지 않은 고침), title?() → 고치는 항목 이름 }.
   * text를 주면(메이커의 Ctrl+V) 그 글로 미리 보기까지. 넣으면 편집 창의 칸이 바뀌고, 저장은 편집 창의 [저장]
   */
  function openWhole(env, text = '') {
    if (!env || !env.form || typeof document === 'undefined' || !document.body) return false;
    const box = document.createElement('dialog');
    box.className = 'dlc-dialog mk-box mk-whole';
    box.style.width = 'min(860px, calc(100vw - 24px))';
    box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>통째 붙여넣기</h2><button type="button" class="icon-btn" data-whole-cancel aria-label="닫기">✕</button></div>
      <div class="dlg-body">
        <p>칸 채우기 답의 칸 블록(#HT칸 2 … #끝 · 옛 답 #HT칸 1도)을 붙여넣으면 이 객체의 칸을 한 번에 채웁니다. 답 전체를 붙여넣어도 되고, 답이 둘로 나뉘었으면 이어서 붙여넣습니다. 넣은 뒤 편집 창에서 살펴보고 저장합니다.</p>
        <textarea class="cells" rows="9" spellcheck="false" aria-label="칸 채우기 답" data-whole-text></textarea>
        <div class="mk-paste-preview" data-whole-preview aria-live="polite"></div>
      </div>
      <div class="dlg-foot"><span class="mk-whole-mode" data-whole-mode hidden>있는 줄 <label class="check"><input type="radio" name="wholeMode" value="replace" checked> 바꾸기</label><label class="check"><input type="radio" name="wholeMode" value="append"> 보태기</label></span><span class="spacer"></span><button type="button" class="btn" data-whole-cancel>취소</button><button type="button" class="btn btn-primary" data-whole-accept disabled>넣기</button></div></div>`;
    const ta = box.querySelector('[data-whole-text]');
    const accept = box.querySelector('[data-whole-accept]');
    const modeBox = box.querySelector('[data-whole-mode]');
    let r = null, cur = {}, done = false;
    const tracks = () => (env.tracks ? env.tracks() : []) || [];
    const mode = () => ((box.querySelector('input[name="wholeMode"]:checked') || {}).value === 'append' ? 'append' : 'replace');
    function paint() {
      const out = box.querySelector('[data-whole-preview]');
      try {
        cur = env.read() || {};
      } catch (e) {
        cur = {};
      }
      r = ta.value.trim() ? parseWhole(ta.value, { tracks: tracks(), spheres: env.spheres ? env.spheres() : undefined, eras: env.eras ? env.eras() : undefined }) : null;
      const rows = r ? wholeSummary(r, cur, { tracks: tracks(), mode: mode() }) : [];
      const n = rows.filter(x => !x.none).length;
      accept.disabled = !n && !(r && r.others.length);
      accept.textContent = n ? `${n}곳 넣기` : '넣기';
      modeBox.hidden = !rows.some(x => x.clash);
      if (!r) {
        out.innerHTML = '';
        return;
      }
      if (!r.found) {
        out.innerHTML = `<p class="problems">칸 블록(#HT칸 2 … #끝)을 찾지 못했습니다 — 답의 칸 블록을 복사 단추로 복사해 붙여넣으세요.</p>`;
        return;
      }
      const other = cur.name && r.fields.name && cur.name !== r.fields.name;
      out.innerHTML = `
        ${other ? `<p class="problems">답의 이름 «${esc(r.fields.name)}»이(가) 지금 편집 창의 «${esc(cur.name)}»와(과) 다릅니다 — 넣으면 이름도 바뀝니다.</p>` : ''}
        <div class="mk-table-wrap"><table class="mk-base-table is-list"><thead><tr><th>칸</th><th>붙여넣은 것</th><th>지금</th></tr></thead><tbody>${rows.map(x => `<tr><td>${esc(x.label)}</td><td>${esc(x.text)}</td><td>${x.now ? `${x.now}줄` : ''}</td></tr>`).join('')}</tbody></table></div>
        ${r.skipped.length ? `<p>넣지 않는 절: ${esc(r.skipped.join(' · '))} — 표 붙여넣기 · 계층 입력에서 넣습니다.</p>` : ''}
        ${othersHTML()}
        ${r.problems.length ? `<ul class="mk-paste-problems">${r.problems.slice(0, 12).map(p => `<li>${esc(p)}</li>`).join('')}${r.problems.length > 12 ? `<li>…외 ${r.problems.length - 12}개</li>` : ''}</ul>` : ''}`;
      const keep = box.querySelector('[data-whole-others]');
      if (keep) keep.checked = othersOn;
    }
    /* 다른 나라에 넣을 것(이어받은나라 · 속했던나라 층) — 메이커가 찾은 그 나라와 넣는 길(내 DLC · 덮어쓰기 · 잠김 · 없음). 넣는 것은 이 나라를 저장할 때 */
    let othersOn = true, links = [];
    const thisName = () => (r && r.fields.name) || cur.name || '';
    const thisTrack = () => (r && r.fields.track) || cur.track || '';
    const doable = () => links.filter(l => (l.status === 'own' || l.status === 'patch') && l.result !== 'same');
    /* 인물 층 — 이 나라를 저장할 때 내 DLC의 인물로(같은 트랙 · 같은 이름의 제 인물이 있으면 그 사람을 고침) */
    let peopleOn = true;
    function peopleHTML() {
      const list = (r && r.people) || [];
      if (!list.length) return '';
      const seen = env.previewPeople ? env.previewPeople(list, thisTrack()) || [] : [];
      const how = p => {
        const s = (seen.find(x => x.name === p.name) || {}).status;
        return [p.lineageOnly ? '계보' : '활동', p.role, s === 'update' ? '있는 사람 고침' : s === 'many' ? '같은 이름이 여럿 — 넣지 않음' : '새 사람'].filter(Boolean).join(' · ');
      };
      const shown = list.slice(0, 12);
      return `<div class="mk-whole-others"><label class="check"><input type="checkbox" data-whole-people${peopleOn ? ' checked' : ''}> 저장할 때 인물 ${list.length}명 넣기</label>
        <ul>${shown.map(p => `<li><b>${esc(p.name)}</b> — ${esc(how(p))}</li>`).join('')}${list.length > shown.length ? `<li>…외 ${list.length - shown.length}명</li>` : ''}</ul></div>`;
    }
    function othersHTML() {
      links = r && r.others.length && env.previewLinks ? env.previewLinks(r.others, thisName(), thisTrack()) || [] : [];
      if (!links.length) return peopleHTML();
      const what = l =>
        l.kind === 'epoch' ? `시대 구분의 대범위${l.label ? `(${l.label})` : ''}에 «${thisName()}»`
        : l.kind === 'scope' ? `대범위${l.label ? `(${l.label})` : ''}에 «${thisName()}»`
        : l.kind === 'cycle' ? `「주기」 표에 이 문화권의 ${l.names ? '이름 돌림' : '연호 눈금'} 줄${l.label ? `(${l.label})` : ''}`
        : l.kind === 'contain' ? `그릇 «${thisName()}»에 접혀 듦${l.main ? ' · 으뜸' : ''}`
        : l.kind === 'succ' ? `승계 «${thisName()}» ${HT.successionName(l.type)}`
        : `소속 «${thisName()}»${l.relation ? ` ${HT.relationName(l.relation)}` : ''}`;
      const how = l => {
        if (l.kind === 'cycle') return l.why || (l.result === 'same' ? '그 문화권의 주기 줄이 이미 있음' : '내 DLC의 「주기」 표에 새로 만듦');
        if (isScopeLink(l)) {
          if (l.why) return l.why;
          return { same: '이미 들어 있음', added: '내 DLC의 대범위에 더함', updated: '내 DLC의 대범위 성격 · 본국을 채움' }[l.result] || (l.epochNew ? '내 DLC에 시대 구분과 대범위를 새로 만듦' : '내 DLC에 대범위를 새로 만듦');
        }
        if (l.status === 'locked') return `잠긴 팩 «${l.packName}» <button type="button" class="btn btn-sm" data-whole-unlock="${esc(l.packId)}">자물쇠 풀기</button>`;
        if (l.status === 'none') return '연표에 없음 — 그 나라를 먼저 등록';
        if (l.status === 'many') return '같은 이름이 여럿 — 손으로';
        if (l.result === 'same') return '이미 있음';
        const verb = l.result === 'updated' ? '바꿈' : '더함';
        return l.status === 'own' ? `내 DLC에서 ${verb}` : `«${l.packName}» 덮어쓰기로 ${verb}`;
      };
      const where = [links.some(l => !isScopeLink(l)) && '다른 객체', links.some(l => isScopeLink(l) && l.kind !== 'cycle') && '대범위', links.some(l => l.kind === 'cycle') && '주기 표'].filter(Boolean).join(' · ');
      return `<div class="mk-whole-others"><label class="check"><input type="checkbox" data-whole-others${othersOn ? ' checked' : ''}> 저장할 때 ${where}에도 넣기</label>
        <ul>${links.map(l => `<li><b>${esc(l.name)}</b> — ${esc(what(l))} · ${how(l).replace(/^([^<]*)/, m => esc(m))}</li>`).join('')}</ul></div>${peopleHTML()}`;
    }
    let timer = 0;
    box.addEventListener('change', e => {
      if (e.target.matches('[data-whole-others]')) othersOn = e.target.checked;
      else if (e.target.matches('[data-whole-people]')) peopleOn = e.target.checked;
      else if (e.target.name === 'wholeMode') paint();
    });
    ta.addEventListener('input', () => {
      clearTimeout(timer);
      timer = setTimeout(paint, 120);
    });
    box.addEventListener('click', e => {
      if (e.target.closest('[data-whole-cancel]')) return box.close();
      const lock = e.target.closest('[data-whole-unlock]');
      if (lock) {
        if (env.unlock) env.unlock(lock.dataset.wholeUnlock);
        return paint();
      }
      if (!e.target.closest('[data-whole-accept]') || !r) return;
      clearTimeout(timer);
      paint();
      const rows = wholeSummary(r, cur, { tracks: tracks(), mode: mode() }).filter(x => !x.none);
      const later = othersOn ? doable() : [];
      const people = peopleOn && env.applyPeople ? r.people || [] : [];
      if (!rows.length && !later.length) return;
      if (!env.refill(mergeWhole(cur, r, mode()))) return HT.toast('편집 창이 닫혀 있어 넣지 못했습니다.', 'error');
      done = true;
      /* 다른 나라 · 인물은 이 나라를 저장할 때(편집 창의 '저장' — viewer.js가 폼에 'ht:saved'를 알림). 그 사이 다른 항목을 열면(fpCtx가 바뀜) 버림.
         인물을 저장 뒤에 넣는 까닭: 부 · 모 자리가 이번에 넣은 지도자 줄을 가리킬 수 있어서(저장해야 연표에 그 칸이 생김) */
      env.form._wholeLinks = later.length || people.length ? { ctx: env.form.dataset.fpCtx, items: later.length ? r.others : [], people, env } : null;
      bindLinkSave(env.form);
      const lands = later.filter(l => !isScopeLink(l)), groups = later.filter(isScopeLink);
      const after = [lands.length && `다른 나라 ${lands.length}곳(${lands.map(l => l.name).join(' · ')})`, groups.length && `대범위 ${groups.length}곳(${groups.map(l => l.name).join(' · ')})`, people.length && `인물 ${people.length}명`].filter(Boolean);
      HT.toast(`${rows.length ? `${rows.length}곳을 채웠습니다. ` : ''}편집 창에서 살펴보고 저장하세요.${after.length ? ` 저장하면 ${after.join('과 ')}도 넣습니다.` : ''}${r.problems.length ? ` 읽지 못한 것 ${r.problems.length}개는 빼고 넣었습니다.` : ''}`, 'ok');
      box.close();
    });
    box.addEventListener('close', () => {
      clearTimeout(timer);
      box.remove();
      /* 넣었으면 초점을 편집 창의 이름 칸으로 — Ctrl+S(편집 창 안에서만 듣는 저장)가 바로 되게. 취소면 연 자리로(브라우저가 돌려줌) */
      const name = done && env.form.querySelector('[name="name"]');
      if (name) name.focus({ preventScroll: true });
    });
    document.body.append(box);
    ta.value = text || '';
    paint();
    box.showModal();
    (text ? accept.disabled ? ta : accept : ta).focus();
    return true;
  }
  /** 편집 창의 저장 알림(ht:saved)을 한 번만 받아, 통째 붙여넣기가 남겨 둔 '다른 나라에 넣을 것'을 그 나라들에 넣습니다(env.applyLinks — 되돌리기 한 걸음) */
  function bindLinkSave(form) {
    if (form._wholeLinkBound) return;
    form._wholeLinkBound = true;
    form.addEventListener('ht:saved', async e => {
      const p = form._wholeLinks;
      form._wholeLinks = null;
      const d = (e && e.detail) || {};
      if (!p || p.ctx !== form.dataset.fpCtx || d.kind !== 'period' || !d.item || !d.item.name) return;
      if (p.items.length && p.env.applyLinks) {
        const res = (await p.env.applyLinks(d.item.name, d.item.track, p.items, d.item.id)) || {};
        const into = [(res.names || []).length && `다른 나라 ${res.names.length}곳(${res.names.join(' · ')})`, (res.scopes || []).length && `대범위 ${res.scopes.length}곳(${res.scopes.join(' · ')})`].filter(Boolean);
        if (into.length) HT.toast(`${into.join('과 ')}에 «${d.item.name}»을(를) 넣었습니다.${res.epochs && res.epochs.length ? ` 새 시대 구분: ${res.epochs.join(' · ')}.` : ''}`, 'ok');
        if ((res.skipped || []).length) HT.toast(`다른 나라 · 대범위 가운데 넣지 못한 곳: ${res.skipped.join(' · ')}`, 'error');
      }
      if (p.people.length && p.env.applyPeople) {
        const res = (await p.env.applyPeople(d.uid, d.item, p.people)) || {};
        const n = (res.added || 0) + (res.updated || 0);
        if (n) HT.toast(`«${d.item.name}»의 인물 ${n}명을 넣었습니다(새 사람 ${res.added || 0} · 고침 ${res.updated || 0}).${(res.loose || []).length ? ` 찾지 못한 이름 ${res.loose.length}개(${res.loose.slice(0, 4).join(' · ')})는 글 그대로 적었습니다 — 검사 창에서 확인하세요.` : ''}`, 'ok');
        if ((res.skipped || []).length) HT.toast(`넣지 못한 인물: ${res.skipped.join(' · ')}`, 'error');
      }
    });
  }
  HT.makerPaste = { FIELDS, splitTable, guessHead, guessColumns, parseText, readRow, analyze, leftoverText, open, LAYERS, LAYERS2, joinCycle, parseWhole, mergeWhole, wholeSummary, isWhole, openWhole, unlink, linkOther, joinScope };
})();
