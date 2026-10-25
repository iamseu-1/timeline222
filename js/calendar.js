/* 역사 연표 — 날짜와 달력
   ─ 해 좌표: 연표의 시간은 실수 하나입니다. 정수 N = N년 1월 1일 0시, 소수 = 그해 안의 자리(지난 날수 ÷ 그해 날수).
     기원전 N년 = -N이고 0년은 없습니다 — 기원전 1년 다음 해가 1년이라 좌표 [0, 1)은 비어 있는 해입니다.
   ─ 서력: 1582년 10월 15일 전은 율리우스력, 그날부터는 그레고리력으로 읽습니다(역사 서술의 관례).
   ─ 음력(한국·중국)·이슬람력·페르시아력·히브리력·에티오피아력·콥트력·사카력은 브라우저의 국제화 달력(Intl)으로 율리우스 적일(JDN, 날 번호)을 거쳐 바꿉니다.
     불기(타이)는 서력의 해에 543을 더할 뿐이라(달과 날 · 1582년의 열흘 건너뜀까지 서력 그대로) 산수로 바꿉니다.
   ─ 날짜 글: "1592" · "기원전 108" · "1592-05" · "1592-05-23" · "1592.5.23" · "1592년 5월 23일 14시 30분" ·
              "음력 1592-04-13" · "음력 1592년 윤4월 13일" · "이슬람력 1000-08-11" · "율리우스력 1582-10-04" …
     연도만 적은 서력 날짜는 예전처럼 정수이고, 그보다 자세하거나 다른 달력이면 표준 글("…At")로 함께 남겨 저장·표시에 씁니다. */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const cal = (HT.cal = {});

  /* ---------- 달력 목록 ---------- */
  /* words: 날짜 글 앞(또는 뒤 괄호)에 붙여 달력을 고르는 말 — 긴 것부터 맞춥니다.
     maxMonth: 한 해의 달 수가 12보다 많은 달력(히브리력 윤년 · 에티오피아력 · 콥트력의 13째 달). guess: 날짜 → 날 번호를 찾을 때의 어림
     [서력 해와의 차, 새해의 서력 달, 날, 한 달의 날수](음력 · 이슬람력 밖). locale: 숫자 달을 주는 말씨('en'이 달 이름을 주는 히브리력만 'de').
     offset: 서력(천문 연도)의 해에 더하는 수 — 달과 날은 서력 그대로인 달력(불기). ICU의 buddhist도 같은 셈이지만 1582년 10월(1 ~ 4일 · 15 ~ 31일)을
     '달의 시작 표'(엔진 · 앱)로 옮길 수 없어(표는 달 안의 날을 1부터 이어 셈) 산수로 둡니다 */
  cal.CALENDARS = [
    { id: 'civil', name: '양력', long: '양력 (서력 — 1582년 10월 15일 전은 율리우스력)', prefix: '', words: ['양력', '서력'] },
    { id: 'gregorian', name: '그레고리력', long: '그레고리력 (1582년 전에도 그레고리력으로)', prefix: '그레고리력 ', words: ['그레고리력', '그레고리오력', '신력'] },
    { id: 'julian', name: '율리우스력', long: '율리우스력 (1582년 뒤에도 율리우스력으로)', prefix: '율리우스력 ', words: ['율리우스력', '구력'] },
    { id: 'dangi', name: '음력', long: '음력 (한국)', prefix: '음력 ', words: ['한국 음력', '음력', '陰曆', '음'], intl: 'dangi', lunar: true },
    { id: 'chinese', name: '중국 음력', long: '음력 (중국 · 농력)', prefix: '중국 음력 ', words: ['중국 음력', '농력', '農曆', '农历'], intl: 'chinese', lunar: true },
    { id: 'islamic', name: '이슬람력', long: '이슬람력 (히즈라력 · 표 계산)', prefix: '이슬람력 ', words: ['이슬람력', '히즈라력', '히즈라', '회교력', 'AH'], intl: 'islamic-civil', era: 'AH' },
    { id: 'umalqura', name: '이슬람력(움 알쿠라)', long: '이슬람력 (움 알쿠라 — 사우디 공식력)', prefix: '움알쿠라 ', words: ['움 알쿠라', '움알쿠라'], intl: 'islamic-umalqura', era: 'AH' },
    { id: 'persian', name: '페르시아력', long: '페르시아력 (태양 히즈라력)', prefix: '페르시아력 ', words: ['페르시아력', '이란력', '태양 히즈라력'], intl: 'persian', era: 'AP', guess: [621, 3, 21, 30.44] },
    { id: 'hebrew', name: '히브리력', long: '히브리력 (유대력 — 티슈리 달이 1월 · 윤년은 13달)', prefix: '히브리력 ', words: ['히브리력', '유대력'], intl: 'hebrew', era: 'AM', maxMonth: 13, guess: [-3761, 9, 20, 29.53], locale: 'de' },
    { id: 'ethiopic', name: '에티오피아력', long: '에티오피아력 (13째 달은 5 · 6일)', prefix: '에티오피아력 ', words: ['에티오피아력'], intl: 'ethiopic', era: 'EC', maxMonth: 13, guess: [7, 9, 11, 30] },
    { id: 'coptic', name: '콥트력', long: '콥트력 (순교자 기원 — 13째 달은 5 · 6일)', prefix: '콥트력 ', words: ['콥트력'], intl: 'coptic', era: 'AM', maxMonth: 13, guess: [283, 9, 11, 30] },
    { id: 'indian', name: '사카력', long: '사카력 (인도 국정력 — 새해는 서력 3월 21 · 22일)', prefix: '사카력 ', words: ['사카력', '인도 국정력'], intl: 'indian', era: 'SE', guess: [78, 3, 22, 30.44] },
    { id: 'buddhist', name: '불기', long: '불기 (타이 불멸 기원 — 해는 서력 + 543 · 달과 날은 양력)', prefix: '불기 ', words: ['불기', '타이 불기'], era: 'BE', offset: 543 },
  ];
  const CAL = new Map(cal.CALENDARS.map(c => [c.id, c]));
  cal.get = id => CAL.get(id) || CAL.get('civil');
  const WORDS = cal.CALENDARS.flatMap(c => c.words.map(w => ({ w, c }))).sort((a, b) => b.w.length - a.w.length);

  /* ---------- 날 번호(JDN) ↔ 율리우스력·그레고리력 (천문 연도: 0 = 기원전 1년) ---------- */
  const fl = Math.floor;
  const jdnG = (y, m, d) => {
    const a = fl((14 - m) / 12);
    const yy = y + 4800 - a;
    const mm = m + 12 * a - 3;
    return d + fl((153 * mm + 2) / 5) + 365 * yy + fl(yy / 4) - fl(yy / 100) + fl(yy / 400) - 32045;
  };
  const jdnJ = (y, m, d) => {
    const a = fl((14 - m) / 12);
    const yy = y + 4800 - a;
    const mm = m + 12 * a - 3;
    return d + fl((153 * mm + 2) / 5) + 365 * yy + fl(yy / 4) - 32083;
  };
  const fromG = J => {
    const a = J + 32044;
    const b = fl((4 * a + 3) / 146097);
    const c = a - fl((146097 * b) / 4);
    const d = fl((4 * c + 3) / 1461);
    const e = c - fl((1461 * d) / 4);
    const m = fl((5 * e + 2) / 153);
    return { y: 100 * b + d - 4800 + fl(m / 10), m: m + 3 - 12 * fl(m / 10), d: e - fl((153 * m + 2) / 5) + 1 };
  };
  const fromJ = J => {
    const c = J + 32082;
    const d = fl((4 * c + 3) / 1461);
    const e = c - fl((1461 * d) / 4);
    const m = fl((5 * e + 2) / 153);
    return { y: d - 4800 + fl(m / 10), m: m + 3 - 12 * fl(m / 10), d: e - fl((153 * m + 2) / 5) + 1 };
  };
  const GREG = 2299161; // 1582-10-15 (그레고리력 첫날)
  const beforeGreg = (y, m, d) => y < 1582 || (y === 1582 && (m < 10 || (m === 10 && d < 15)));
  const jdnCivil = (y, m, d) => (beforeGreg(y, m, d) ? jdnJ(y, m, d) : jdnG(y, m, d));
  const fromCivil = J => (J < GREG ? fromJ(J) : fromG(J));
  const yearStart = ay => (ay <= 1582 ? jdnJ(ay, 1, 1) : jdnG(ay, 1, 1)); // 서력 ay년 1월 1일
  /* 연표 연도(기원전 = 음수, 0 없음) ↔ 천문 연도 */
  const toAstro = y => (y < 0 ? y + 1 : y);
  const fromAstro = a => (a <= 0 ? a - 1 : a);
  cal.toAstro = toAstro;
  cal.fromAstro = fromAstro;
  cal.jdnCivil = (y, m, d) => jdnCivil(toAstro(y), m, d);
  cal.civilOf = J => {
    const r = fromCivil(J);
    return { y: fromAstro(r.y), m: r.m, d: r.d };
  };
  const monthLen = (id, ay, m) => {
    const f = id === 'gregorian' ? jdnG : id === 'julian' ? jdnJ : jdnCivil;
    const ny = m === 12 ? ay + 1 : ay;
    const nm = m === 12 ? 1 : m + 1;
    return f(ny, nm, 1) - f(ay, m, 1);
  };

  /* ---------- 해 좌표 ↔ 날 번호 ---------- */
  const EPS = 1e-9;
  /** 날 번호(+ 그날 안의 비율) → 해 좌표 */
  cal.tOf = (J, frac = 0) => {
    let ay = fromCivil(J).y;
    while (J < yearStart(ay)) ay--;
    while (J >= yearStart(ay + 1)) ay++;
    const s = yearStart(ay);
    return fromAstro(ay) + (J - s + frac) / (yearStart(ay + 1) - s);
  };
  /** 해 좌표 → { y(연표 연도), ay, J(날 번호), frac(그날 안의 비율), m, d } — 0년 자리는 1년 1월 1일로 봅니다 */
  cal.at = t => {
    let y = fl(t + EPS);
    let pos = t - y;
    if (y === 0) {
      y = 1;
      pos = 0;
    }
    const ay = toAstro(y);
    const s = yearStart(ay);
    const len = yearStart(ay + 1) - s;
    const dayPos = Math.max(0, pos) * len;
    let di = fl(dayPos + 1e-7);
    if (di >= len) di = len - 1;
    const frac = Math.max(0, Math.min(1, dayPos - di));
    const J = s + di;
    const c = fromCivil(J);
    return { y, ay, J, frac, m: c.m, d: c.d, len };
  };
  /** 날 J의 끝 좌표. 기원전 1년 12월 31일 다음은 빈 0년 자리를 건너 1년 1월 1일(=1.0)이므로, 그날만은 하루 폭으로 끊습니다 */
  cal.dayEnd = J => {
    const a = cal.tOf(J);
    const b = cal.tOf(J + 1);
    return b - a > 0.01 ? a + 1 / 366 : b;
  };
  /** 그해의 날수 (서력) */
  cal.yearDays = y => {
    const ay = toAstro(y === 0 ? 1 : y);
    return yearStart(ay + 1) - yearStart(ay);
  };

  /* ---------- 국제화 달력(Intl) ---------- */
  const fmts = new Map();
  const fmtOf = intl => {
    if (!fmts.has(intl)) {
      let f = null;
      try {
        const c = cal.CALENDARS.find(x => x.intl === intl);
        f = new Intl.DateTimeFormat(`${(c && c.locale) || 'en'}-u-ca-${intl}`, { timeZone: 'UTC', year: 'numeric', month: 'numeric', day: 'numeric' });
        if (f.resolvedOptions().calendar !== intl) f = null;
      } catch (e) {
        f = null;
      }
      fmts.set(intl, f);
    }
    return fmts.get(intl);
  };
  cal.supports = id => {
    const c = CAL.get(id);
    return !!c && (!c.intl || !!fmtOf(c.intl));
  };
  const partsMemo = new Map();
  /** 날 번호 → 그 달력의 { y, m, leap, d } (음력의 y는 그 해가 시작한 서력 연도, 연표 연도로) */
  const intlParts = (intl, J) => {
    const key = `${intl}|${J}`;
    let r = partsMemo.get(key);
    if (r) return r;
    const f = fmtOf(intl);
    if (!f) return null;
    const date = new Date((J - 2440588) * 864e5);
    r = { y: NaN, m: NaN, leap: false, d: NaN };
    let rel = null;
    let era = '';
    for (const p of f.formatToParts(date)) {
      if (p.type === 'relatedYear') rel = Number(p.value);
      else if (p.type === 'year') r.y = Number(p.value);
      else if (p.type === 'era') era = p.value;
      else if (p.type === 'month') {
        const mm = /^(\d+)(bis)?$/.exec(p.value);
        if (mm) {
          r.m = Number(mm[1]);
          r.leap = !!mm[2];
        }
      } else if (p.type === 'day') r.d = Number(p.value);
    }
    if (rel != null) r.y = fromAstro(rel); // 음력: 관련 서력 연도(천문 연도)
    else if (intl === 'ethiopic' && era === 'AA') r.y -= 5500; // 기원(서력 8년) 앞은 ICU가 창세 기원(아메테 알렘 — 5500년 앞)으로 셈 → 0 · 음수로 이어지게
    else if (intl === 'coptic' && !era) r.y = 1 - r.y; // 기원(서력 284년) 앞은 ICU가 연대 이름 없이 1부터 거꾸로 셈 → 0 · 음수로 이어지게
    if (partsMemo.size > 20000) partsMemo.clear();
    partsMemo.set(key, r);
    return r;
  };
  const keyOf = (y, m, leap, d) => y * 10000 + (m * 2 + (leap ? 1 : 0)) * 100 + d;
  /** 그 달력의 날짜 → 날 번호. 없는 날(윤달이 없는 해의 윤달, 30일이 없는 달 …)이면 null */
  const intlJdn = (c, y, m, leap, d) => {
    let est;
    if (c.lunar) est = jdnG(toAstro(y), 2, 1) + Math.round((m - 1 + (leap ? 1 : 0)) * 29.53) + d - 1;
    else if (c.era === 'AH') est = 1948440 + fl((y - 1) * 354.36667) + fl((m - 1) * 29.5) + d - 1;
    else est = jdnG(y + c.guess[0], c.guess[1], c.guess[2]) + Math.round((m - 1) * c.guess[3]) + d - 1;
    const target = keyOf(y, m, leap, d);
    let lo = est - 800;
    let hi = est + 800;
    const k = J => {
      const p = intlParts(c.intl, J);
      return keyOf(p.y, p.m, p.leap, p.d);
    };
    if (k(lo) > target || k(hi) < target) return null;
    while (lo < hi) {
      const mid = fl((lo + hi) / 2);
      if (k(mid) < target) lo = mid + 1;
      else hi = mid;
    }
    return k(lo) === target ? lo : null;
  };
  /** 날 번호 → 달력 id의 { y, m, leap, d } */
  cal.partsIn = (id, J) => {
    const c = CAL.get(id);
    if (!c || id === 'civil') return Object.assign({ leap: false }, cal.civilOf(J));
    if (id === 'gregorian') {
      const r = fromG(J);
      return { y: fromAstro(r.y), m: r.m, d: r.d, leap: false };
    }
    if (id === 'julian') {
      const r = fromJ(J);
      return { y: fromAstro(r.y), m: r.m, d: r.d, leap: false };
    }
    if (c.offset) {
      const r = fromCivil(J);
      return { y: r.y + c.offset, m: r.m, d: r.d, leap: false };
    }
    return intlParts(c.intl, J);
  };
  /** 그 달의 첫날 날 번호 (음력 달의 초하루 등) */
  cal.monthStartIn = (id, J) => {
    const p = cal.partsIn(id, J);
    return p ? J - (p.d - 1) : J;
  };
  /** 다음 달의 첫날 날 번호 (J = 그 달의 첫날). 28일 뒤가 벌써 다음 달이면(28일 이하인 짧은 달 — 에티오피아력 · 콥트력의 13째 달 · 2월 …) 그날에서 되짚습니다 */
  cal.nextMonthIn = (id, J) => {
    const p = cal.partsIn(id, J + 28);
    if (p && p.d < 29) return J + 28 - (p.d - 1);
    let n = J + 29;
    while (cal.partsIn(id, n).d !== 1 && n < J + 40) n++;
    return n;
  };

  /* ---------- 날짜 글 읽기 ---------- */
  const pad = n => String(n).padStart(2, '0');
  const numOrNull = v => (v == null || v === '' ? null : Number(v));
  const TIME = String.raw`(?:\s*(?:T|\s)\s*(?:(오전|오후|AM|PM)\s*)?(\d{1,2})(?::(\d{2})|\s*시(?:\s*(\d{1,2})\s*분)?)(?:\s*(AM|PM))?)?`;
  const RE_KO = new RegExp(String.raw`^(\d+)\s*년(?:\s*(윤)?\s*(\d{1,2})\s*월(?:\s*(\d{1,2})\s*일)?)?${TIME}$`, 'i');
  const RE_NUM = new RegExp(String.raw`^(\d+)(?:\s*([-./])\s*(윤)?(\d{1,2})(?:\s*\2\s*(\d{1,2}))?\.?)?${TIME}$`, 'i');
  /* 세기로만 아는 연대(묶음 5 · 6번): "3세기" · "3세기 중반" · "기원전 2세기 말" — 초 · 중 · 말은 세기를 셋으로 나눈 33 · 33 · 34년, 전반 · 후반은 50년, 세기만 적으면 100년 */
  const RE_CENT = /^(\d+)\s*세기(?:\s*(초반|초엽|초|전반|중반|중엽|중|후반|말엽|말))?$/;
  const CENT_PART = { 초: 'a', 초반: 'a', 초엽: 'a', 중: 'b', 중반: 'b', 중엽: 'b', 말: 'c', 말엽: 'c', 전반: 'h1', 후반: 'h2' };
  const CENT_WORD = { a: '초', b: '중반', c: '말', h1: '전반', h2: '후반' };
  const BC_WORD = String.raw`(?:기원전|서기전|B\.?\s?C\.?(?:\s?E\.?)?)`;
  const AD_WORD = String.raw`(?:기원후|서기|A\.?\s?D\.?|C\.?\s?E\.?)`;
  const RE_BC_HEAD = new RegExp(`^${BC_WORD}\\s*`, 'i');
  const RE_BC_TAIL = new RegExp(`\\s*${BC_WORD}$`, 'i');
  const RE_AD_HEAD = new RegExp(`^${AD_WORD}\\s*`, 'i');
  const RE_BC_MID = new RegExp(`^(\\d+)\\s*(?:년\\s*)?${BC_WORD}\\s*(?=[-./\\s]|$)`, 'i');

  const bad = error => ({ ok: false, error });
  const parseMemo = new Map();

  /**
   * 날짜 글(또는 수)을 읽습니다.
   * 성공: { ok:true, t(해 좌표), prec('y'|'m'|'d'|'h'|'min'|'x'), cal, y, m, leap, d, h, mi, J, text(표준 글), fine(연도만 적은 서력이 아님) }
   * 실패: { ok:false, error }. 빈 값은 null.
   */
  cal.parse = input => {
    if (input == null) return null;
    if (typeof input === 'number') {
      if (!isFinite(input)) return bad('숫자가 아닙니다.');
      if (Number.isInteger(input)) return { ok: true, t: input, prec: 'y', cal: 'civil', y: input, text: String(input), fine: false };
      return { ok: true, t: input, prec: 'x', cal: 'civil', y: fl(input + EPS), text: String(input), fine: true }; // 소수 좌표 그대로
    }
    const src = String(input).trim();
    if (!src) return null;
    if (parseMemo.has(src)) return parseMemo.get(src);
    const r = parseText(src);
    if (parseMemo.size > 5000) parseMemo.clear();
    parseMemo.set(src, r);
    return r;
  };

  function parseText(src) {
    let s = src
      .replace(/[０-９]/g, ch => String.fromCharCode(ch.charCodeAt(0) - 0xfee0))
      .replace(/(\d),(?=\d{3}(?!\d))/g, '$1')
      .replace(/\s+/g, ' ')
      .trim();
    /* 기원전 말이 달력 말보다 앞에 오면 ("기원전 음력 100-01-01") 달력 말 뒤로 옮깁니다 */
    const lead = new RegExp(`^(${BC_WORD})\\s*(.+)$`, 'i').exec(s);
    if (lead && WORDS.some(x => lead[2].toLowerCase().startsWith(x.w.toLowerCase()) && !/^\d/.test(x.w))) {
      const hit = WORDS.find(x => lead[2].toLowerCase().startsWith(x.w.toLowerCase()));
      s = `${lead[2].slice(0, hit.w.length)} ${lead[1]} ${lead[2].slice(hit.w.length).trim()}`;
    }
    /* 달력: 앞말("음력 …") 또는 뒤 괄호("… (음력)") */
    let calId = 'civil';
    const tail = /\s*[(（]\s*([^)）]+?)\s*[)）]\s*$/.exec(s);
    if (tail) {
      const hit = WORDS.find(x => x.w.toLowerCase() === tail[1].toLowerCase());
      if (hit) {
        calId = hit.c.id;
        s = s.slice(0, tail.index).trim();
      }
    }
    if (calId === 'civil') {
      const low = s.toLowerCase();
      for (const { w, c } of WORDS) {
        const lw = w.toLowerCase();
        /* 앞말: 뒤에 숫자·기원전 같은 말이 와야 달력으로 봅니다 ("음" 한 글자도 "음 1592.4.13"처럼) */
        if (low.length > lw.length && low.startsWith(lw) && /^\s*[:：]?\s*[-\d기서BbAaCc]/.test(s.slice(w.length))) {
          calId = c.id;
          s = s.slice(w.length).replace(/^\s*[:：]?\s*/, '');
          break;
        }
        /* 뒷말: "1592-04-13 음력" */
        if (low.length > lw.length && low.endsWith(lw) && /\s$/.test(s.slice(0, -w.length))) {
          calId = c.id;
          s = s.slice(0, -w.length).trim();
          break;
        }
      }
    }
    /* 어림("경" · "무렵" · "c.") */
    s = s.replace(/\s*(?:경|무렵|께|쯤)$/, '').replace(/^(?:c\.|ca\.|약)\s*/i, '').trim();
    /* 기원전·기원후 */
    let bc = false;
    if (RE_BC_HEAD.test(s)) {
      bc = true;
      s = s.replace(RE_BC_HEAD, '');
    } else if (RE_BC_TAIL.test(s)) {
      bc = true;
      s = s.replace(RE_BC_TAIL, '');
    } else if (RE_BC_MID.test(s)) {
      bc = true;
      s = s.replace(RE_BC_MID, (m0, y) => `${y}`);
    } else if (RE_AD_HEAD.test(s)) s = s.replace(RE_AD_HEAD, '');
    if (s.startsWith('-')) {
      bc = true;
      s = s.slice(1).trim();
    }
    /* 세기: "3세기 중반" → 구간의 첫해가 자리(연도만 적은 사건이 그해 1월 1일인 것과 같음), span이 정밀도 구간, text는 적은 대로 */
    const cm = RE_CENT.exec(s);
    if (cm) {
      if (calId !== 'civil') return bad('세기로 적은 연대는 서력으로만 읽습니다.');
      const n = Number(cm[1]);
      if (!(n >= 1)) return bad('세기는 1부터입니다.');
      const part = cm[2] ? CENT_PART[cm[2]] : '';
      const span = cal.centurySpan(n, part, bc);
      const last = span[1] === 0 ? -1 : span[1] - 1;
      const text = `${bc ? '기원전 ' : ''}${n}세기${part ? ` ${CENT_WORD[part]}` : ''}`;
      return { ok: true, t: span[0], prec: !part ? 'c' : part === 'h1' || part === 'h2' ? 'c2' : 'c3', cal: 'civil', y: span[0], m: null, leap: false, d: null, h: null, mi: null, text, fine: true, span, last, cent: { n, part, bc } };
    }
    let m = RE_KO.exec(s);
    let y;
    let leap = false;
    let mo = null;
    let d = null;
    let ap;
    let h = null;
    let mi = null;
    let ap2;
    if (m) {
      [, y, leap, mo, d, ap, h] = m;
      mi = m[7] != null ? m[7] : m[8];
      ap2 = m[9];
    } else if ((m = RE_NUM.exec(s))) {
      y = m[1];
      leap = m[3];
      mo = m[4];
      d = m[5];
      ap = m[6];
      h = m[7];
      mi = m[8] != null ? m[8] : m[9];
      ap2 = m[10];
    } else return bad('날짜를 읽을 수 없습니다. 예) 1592 · 1592-05-23 · 1592년 5월 23일 14시 · 음력 1592-04-13');
    y = Number(y);
    mo = numOrNull(mo);
    d = numOrNull(d);
    h = numOrNull(h);
    mi = numOrNull(mi);
    leap = !!leap;
    const half = (ap || ap2 || '').toUpperCase();
    if (h != null && (half === '오후' || half === 'PM') && h < 12) h += 12;
    if (h != null && (half === '오전' || half === 'AM') && h === 12) h = 0;
    if (!isFinite(y)) return bad('연도를 읽을 수 없습니다.');
    if (bc) y = -y;
    if (y === 0 && (mo != null || calId !== 'civil')) return bad('0년은 없습니다. 기원전 1년 다음 해가 1년입니다.');
    const maxM = CAL.get(calId).maxMonth || 12;
    if (mo != null && (mo < 1 || mo > maxM)) return bad(`달은 1~${maxM} 사이여야 합니다.`);
    if (d != null && (d < 1 || d > 31)) return bad('날은 1~31 사이여야 합니다.');
    if (h != null && (h < 0 || h > 23)) return bad('시는 0~23 사이여야 합니다.');
    if (mi != null && (mi < 0 || mi > 59)) return bad('분은 0~59 사이여야 합니다.');
    if (h != null && d == null) return bad('시각을 적으려면 날짜(일)까지 적어 주세요.');
    if (leap && !CAL.get(calId).lunar) return bad('윤달은 음력에만 있습니다.');
    return build({ cal: calId, y, m: mo, leap, d, h, mi });
  }

  /** 부분(달력·연·월·윤달·일·시·분) → 읽은 결과. 폼에서도 씁니다 */
  function build({ cal: calId = 'civil', y, m = null, leap = false, d = null, h = null, mi = null }) {
    const c = CAL.get(calId);
    if (!c) return bad(`알 수 없는 달력입니다: ${calId}`);
    if (!Number.isInteger(y)) return bad('연도는 정수여야 합니다.');
    if (m == null) d = null;
    if (d == null) h = mi = null;
    if (h == null) mi = null;
    const prec = h != null ? (mi ? 'min' : 'h') : d != null ? 'd' : m != null ? 'm' : 'y';
    let J;
    if (calId === 'civil' && prec === 'y') {
      return { ok: true, t: y, prec, cal: calId, y, m: null, leap: false, d: null, h: null, mi: null, text: y < 0 ? `기원전 ${-y}` : String(y), fine: false };
    }
    if (c.intl) {
      if (!fmtOf(c.intl)) return bad(`이 환경에서는 ${c.name}을(를) 바꿀 수 없습니다.`);
      if (c.era && y < 1) return bad(`${c.name}은(는) 1년부터 적을 수 있습니다.`);
      J = intlJdn(c, y, m || 1, leap, d || 1);
      if (J == null) {
        if (leap) return bad(`${c.name} ${y < 0 ? `기원전 ${-y}` : y}년에는 윤${m}월이 없습니다.`);
        if (d != null && d > 29) return bad(`${c.name} ${m}월에는 ${d}일이 없습니다.`);
        return bad(`${c.name}에 그런 날짜가 없습니다.`);
      }
    } else {
      if (c.era && y < 1) return bad(`${c.name}은(는) 1년부터 적을 수 있습니다.`);
      const ay = c.offset ? y - c.offset : toAstro(y);
      const f = calId === 'gregorian' ? jdnG : calId === 'julian' ? jdnJ : jdnCivil;
      J = f(ay, m || 1, d || 1);
      if (d != null) {
        /* 없는 날(2월 30일 등)은 다음 달로 넘어가므로 되돌려 보아 확인합니다 (서력 1582년 10월 5~14일은 율리우스력으로 받아들임) */
        const back = calId === 'gregorian' ? fromG(J) : calId === 'julian' ? fromJ(J) : fromCivil(J);
        if (back.m !== m) {
          const len = monthLen(calId === 'civil' || c.offset ? (beforeGreg(ay, m, 1) ? 'julian' : 'gregorian') : calId, ay, m);
          return bad(`${y < 0 ? `기원전 ${-y}` : y}년 ${m}월은 ${len}일까지입니다.`);
        }
      }
    }
    const frac = h != null ? (h + (mi || 0) / 60) / 24 : 0;
    const t = cal.tOf(J, frac);
    const yt = y < 0 ? `기원전 ${-y}` : String(y);
    const text = `${c.prefix}${yt}${m != null ? `-${leap ? '윤' : ''}${pad(m)}` : ''}${d != null ? `-${pad(d)}` : ''}${h != null ? ` ${pad(h)}:${pad(mi || 0)}` : ''}`;
    return { ok: true, t, prec, cal: calId, y, m, leap: !!leap, d, h, mi, J, text, fine: true };
  }
  cal.build = build;

  /** 표준 날짜 글 → 빈칸 없는 조각 (한 줄 글 "이름 시작~끝"용): "음력 1592-04-13" → "음력:1592-04-13", "기원전 44-03-15" → "-44-03-15" */
  cal.compact = text => {
    let s = String(text || '').trim();
    let head = '';
    const w = WORDS.find(x => s.startsWith(`${x.w} `));
    if (w) {
      head = `${w.w}:`;
      s = s.slice(w.w.length + 1);
    }
    s = s.replace(/^기원전 (\d)/, '-$1').replace(/ (\d{1,2}:\d{2})$/, 'T$1').replace(/\s+/g, '');
    return head + s;
  };
  /** 해 좌표만 필요할 때: 수 · 날짜 글 → 해 좌표 (못 읽으면 NaN) */
  cal.toT = input => {
    const r = cal.parse(input);
    return r && r.ok ? r.t : NaN;
  };

  /* ---------- 날짜 쓰기 ---------- */
  const yearText = y => (y < 0 ? `기원전 ${-y}년` : `${y}년`);
  /** 세기 구간 [첫해, 마지막 해 다음 해) — 연표 연도(0년 없음 · 기원전 1년 다음은 0 자리). n = 세기 번호, part = a(초) · b(중) · c(말) · h1(전반) · h2(후반) · ''(세기 전체), bc = 기원전.
      기원전 2세기 = 기원전 200 ~ 101년, 3세기 = 201 ~ 300년. 초 · 중 · 말 = 33 · 33 · 34년, 전반 · 후반 = 50년 */
  cal.centurySpan = (n, part, bc) => {
    const first = bc ? -n * 100 : (n - 1) * 100 + 1;
    const off = part === 'b' ? 33 : part === 'c' ? 66 : part === 'h2' ? 50 : 0;
    const len = !part ? 100 : part === 'h1' || part === 'h2' ? 50 : part === 'c' ? 34 : 33;
    const lo = first + off;
    const last = lo + len - 1;
    return [lo, last === -1 ? 0 : last + 1];
  };
  const clock = (h, mi) => `${h}시${mi ? ` ${mi}분` : ''}`;
  /** 해 좌표 → 서력 날짜 글. prec: 'y' | 'm' | 'd' | 'h' | 'min' */
  cal.formatT = (t, prec = 'd') => {
    if (t == null || !isFinite(t)) return '';
    const a = cal.at(t);
    if (prec === 'y') return yearText(a.y);
    let s = `${yearText(a.y)} ${a.m}월`;
    if (prec === 'm') return s;
    s += ` ${a.d}일`;
    if (prec === 'd' || prec === 'x') return s;
    const mins = Math.round(a.frac * 1440);
    const h = Math.min(23, fl(mins / 60));
    const mi = prec === 'min' ? mins - h * 60 : 0;
    return `${s} ${clock(h, mi)}`;
  };
  /** 읽은 결과 → 사람이 읽는 글. 다른 달력이면 "음력 1592년 4월 13일 (양력 1592년 5월 23일)"처럼 서력을 곁들입니다 */
  cal.describe = (r, { withCivil = true } = {}) => {
    if (!r || !r.ok) return '';
    if (r.prec === 'x') return cal.formatT(r.t, 'd');
    if (r.span) return r.text; // 세기로 적은 연대는 적은 대로 ("3세기 중반")
    const c = CAL.get(r.cal);
    const own = `${r.cal === 'civil' ? '' : `${c.name} `}${yearText(r.y)}${r.m != null ? ` ${r.leap ? '윤' : ''}${r.m}월` : ''}${r.d != null ? ` ${r.d}일` : ''}${r.h != null ? ` ${clock(r.h, r.mi)}` : ''}`;
    if (r.cal === 'civil' || !withCivil) return own;
    const coarse = r.prec === 'y' || r.prec === 'm';
    let civ = cal.formatT(r.t, coarse ? 'd' : r.prec);
    if (cal.at(r.t).y === r.y) civ = civ.replace(/^(기원전 )?\d+년 /, ''); // 같은 해면 해를 줄여서
    return `${own} (양력 ${civ}${coarse ? '부터' : ''})`;
  };
  /** 해 좌표 → 다른 달력의 날짜 글 ("음력 4월 13일" 등) */
  cal.formatIn = (id, t, { year = true } = {}) => {
    const c = CAL.get(id);
    if (!c || !isFinite(t)) return '';
    const p = cal.partsIn(id, cal.at(t).J);
    if (!p || !isFinite(p.m)) return '';
    return `${c.name} ${year ? `${yearText(p.y)} ` : ''}${p.leap ? '윤' : ''}${p.m}월 ${p.d}일`;
  };

  /* ---------- 일진(날의 간지) ---------- */
  const STEMS = '갑을병정무기경신임계';
  const BRANCHES = '자축인묘진사오미신유술해';
  cal.dayGanjiIndex = J => (((J + 49) % 60) + 60) % 60; // 1949-10-01 = 갑자일
  cal.dayGanji = J => {
    const i = cal.dayGanjiIndex(J);
    return STEMS[i % 10] + BRANCHES[i % 12];
  };

  /* ---------- 눈금 ---------- */
  /* 해보다 작은 눈금: 시(1·3·6·12) → 일(1·2·5·10) → 달(1·3·6). 글자 사이가 너무 좁지 않은 가장 작은 단위를 고릅니다 */
  const SUB = [
    { unit: 'h', n: 1, yrs: 1 / 8766, min: 46 },
    { unit: 'h', n: 3, yrs: 3 / 8766, min: 46 },
    { unit: 'h', n: 6, yrs: 6 / 8766, min: 46 },
    { unit: 'h', n: 12, yrs: 12 / 8766, min: 46 },
    { unit: 'd', n: 1, yrs: 1 / 365.25, min: 40 },
    { unit: 'd', n: 2, yrs: 2 / 365.25, min: 40 },
    { unit: 'd', n: 5, yrs: 5 / 365.25, min: 44 },
    { unit: 'd', n: 10, yrs: 10 / 365.25, min: 48 },
    { unit: 'mo', n: 1, yrs: 1 / 12, min: 58 },
    { unit: 'mo', n: 3, yrs: 1 / 4, min: 62 },
    { unit: 'mo', n: 6, yrs: 1 / 2, min: 66 },
  ];
  /** 이 배율(k = 1년의 픽셀)에서 쓸 해보다 작은 눈금. 해 눈금이면 null */
  cal.subStep = k => SUB.find(s => s.yrs * k >= s.min) || null;
  const DAY_MARKS = { 1: null, 2: null, 5: [1, 6, 11, 16, 21, 26], 10: [1, 11, 21] };
  /**
   * 해보다 작은 눈금 목록: [{ t, J, label, major, key }]. major = 윗단위(해·달·날)가 바뀌는 눈금.
   * 0년 자리는 건너뜁니다
   */
  cal.subTicks = (start, end, step) => {
    const out = [];
    if (!step || !(end > start)) return out;
    const a = cal.at(Math.max(start, -1e6));
    let J = a.J - (step.unit === 'mo' ? 400 : 2);
    const endJ = cal.at(Math.min(end, 1e6)).J + 2;
    if (endJ - J > 40000) return out; // 너무 넓으면 (안전장치)
    for (; J <= endJ; J++) {
      const c = fromCivil(J);
      const y = fromAstro(c.y);
      if (step.unit === 'mo') {
        if (c.d !== 1 || (c.m - 1) % step.n) continue;
        const t = cal.tOf(J);
        if (t < start - 1 || t > end) continue;
        const major = c.m === 1;
        out.push({ t, J, key: `m${J}`, idx: fl((c.y * 12 + c.m - 1) / step.n), major, label: major ? yearText(y) : `${c.m}월` });
        continue;
      }
      if (step.unit === 'd') {
        const marks = DAY_MARKS[step.n] || [];
        const ok = step.n === 1 ? true : step.n === 2 ? c.d % 2 === 1 && c.d < 31 : marks.includes(c.d);
        if (!ok) continue;
        const t = cal.tOf(J);
        if (t < start - 0.2 || t > end) continue;
        const major = c.d === 1;
        const idx = step.n === 1 ? J : step.n === 2 ? fl(J / 2) : (c.y * 12 + c.m) * marks.length + marks.indexOf(c.d);
        out.push({ t, J, key: `d${J}`, idx, major, label: major ? (c.m === 1 ? `${yearText(y)} 1월` : `${c.m}월`) : `${c.d}일` });
        continue;
      }
      for (let hh = 0; hh < 24; hh += step.n) {
        const t = cal.tOf(J, hh / 24);
        if (t < start - 0.01 || t > end) continue;
        const major = hh === 0;
        out.push({ t, J, key: `h${J}.${hh}`, idx: fl((J * 24 + hh) / step.n), major, label: major ? `${c.m}월 ${c.d}일` : `${hh}시` });
      }
    }
    /* 보기 시작 전의 눈금은 하나만 남깁니다 (바탕 띠를 그 눈금부터 칠하려고) */
    const kept = out.filter(x => fl(x.t + EPS) !== 0);
    const first = kept.findIndex(x => x.t >= start);
    return first > 0 ? kept.slice(first - 1) : first < 0 ? kept.slice(-1) : kept;
  };
  /** 화면 왼쪽 끝이 속한 윗단위 ("1592년" · "1592년 5월" · "1592년 5월 23일") */
  cal.context = (t, step) => {
    if (!step) return '';
    const a = cal.at(t);
    if (step.unit === 'mo') return yearText(a.y);
    if (step.unit === 'd') return `${yearText(a.y)} ${a.m}월`;
    return `${yearText(a.y)} ${a.m}월 ${a.d}일`;
  };
  /**
   * 적은 정밀도가 덮는 구간 [t0, t1]: 연도만 적었으면 그해 전체, 달까지면 그달, 날까지면 그날, 시까지면 그 시간.
   * 연표는 확대했을 때 이 구간을 옅은 괄호로 보여 주고 점을 구간 가운데 쪽으로 옮깁니다 (날짜를 모르는 만큼 정직하게)
   */
  cal.precSpan = r => {
    if (!r || !r.ok || r.prec === 'min' || r.prec === 'x') return null;
    if (r.span) return r.span; // 세기 · 반세기 · 세기의 셋째
    if (r.prec === 'h') return [r.t, r.t + 1 / 24 / cal.yearDays(fl(r.t + EPS))];
    if (r.prec === 'd') return [r.t, cal.dayEnd(r.J)];
    if (r.cal === 'civil' && r.prec === 'y') return [r.y, r.y === -1 ? 0 : r.y + 1]; // 기원전 1년은 빈 0년 자리 앞에서 끊음
    const J = r.J != null ? r.J : cal.at(r.t).J;
    if (r.prec === 'm') return [r.t, cal.tOf(cal.nextMonthIn(r.cal, J))];
    const ny = r.y === -1 ? 1 : r.y + 1; // 그 달력의 다음 해 첫날
    const nx = build({ cal: r.cal, y: ny, m: 1, d: 1 });
    return nx.ok ? [r.t, nx.t] : [r.t, r.t + 1];
  };
  /** 두 좌표 사이의 길이: "1,200년" · "3년" · "1년 4개월" · "3개월 12일" · "12일" · "5시간" */
  cal.durText = years => {
    const y = Math.abs(years);
    if (y >= 10) return `${Math.round(y).toLocaleString()}년`;
    const days = y * 365.2425;
    if (days >= 365) {
      const whole = fl(y);
      const mo = Math.round((y - whole) * 12);
      return mo ? (mo === 12 ? `${whole + 1}년` : `${whole}년 ${mo}개월`) : `${whole}년`;
    }
    if (days >= 31) {
      const mo = fl(days / 30.436875 + 0.02);
      const d = Math.max(0, Math.round(days - mo * 30.436875));
      return d ? `${mo}개월 ${d}일` : `${mo}개월`;
    }
    if (days >= 0.96) return `${Math.max(1, Math.round(days))}일`; // 366일짜리 해의 하루(0.998일)도 "1일"
    return `${Math.max(1, Math.round(days * 24))}시간`;
  };
  /** 보기 폭(년)을 사람이 읽는 말로: "약 3개월", "12일", "5시간" */
  cal.spanText = span => {
    if (span >= 10) return `${Math.round(span).toLocaleString()}년`;
    if (span >= 2) return `${span.toFixed(1)}년`;
    const days = span * 365.25;
    if (days >= 60) return `약 ${Math.round(days / 30.44)}개월`;
    if (days >= 2) return `${Math.round(days)}일`;
    return `${Math.max(1, Math.round(days * 24))}시간`;
  };

  /** 다른 달력의 달 경계 (보기 범위 안): [{ J, t, y, m, leap, label, major }] — 보조 달력 줄에 씁니다 */
  const monthCache = new Map();
  cal.monthsIn = (id, startJ, endJ) => {
    const c = CAL.get(id);
    if (!c || !cal.supports(id)) return [];
    const out = [];
    /* 서력 해 단위로 끊어 캐시 */
    const ys = fromCivil(startJ).y;
    const ye = fromCivil(endJ).y;
    if (ye - ys > 12) return out;
    for (let ay = ys - 1; ay <= ye; ay++) {
      // 전해부터: 왼쪽 끝을 덮는 달이 전해 12월에 시작했을 수 있습니다 (앞의 군더더기는 아래 필터가 자름)
      const key = `${id}|${ay}`;
      let list = monthCache.get(key);
      if (!list) {
        list = [];
        const s = yearStart(ay);
        const e = yearStart(ay + 1);
        /* 달의 첫날에서 28일 뒤부터 다음 달 1일을 찾아 건너뜁니다 (하루씩 다 보지 않고 — cal.nextMonthIn) */
        let J = cal.monthStartIn(id, s);
        for (let guard = 0; J < e && guard < 20; guard++) {
          const p = cal.partsIn(id, J);
          if (J >= s) list.push({ J, y: p.y, m: p.m, leap: p.leap, major: p.m === 1 && !p.leap, label: `${p.leap ? '윤' : ''}${p.m}월` });
          J = cal.nextMonthIn(id, J);
        }
        if (monthCache.size > 400) monthCache.clear();
        monthCache.set(key, list);
      }
      for (const x of list) if (x.J >= startJ - 62 && x.J <= endJ) out.push(Object.assign({ t: cal.tOf(x.J) }, x));
    }
    return out;
  };
})();
