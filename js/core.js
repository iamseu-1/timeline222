/* 역사 연표 — 공용 코어: DLC 형식 검사, 데이터 병합, 저장소, 공용 폼 */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});

  HT.FORMAT = 'history-timeline-dlc';
  /* 형식 버전: FORMAT_VERSION은 이 프로그램이 읽는 가장 새 버전입니다 — 파일의 버전이 이보다 높으면 "더 새로운 형식" 경고가 뜹니다 (HT.normalizePack).
     파일에는 버전 2에서 생긴 열쇠·칸(HT.NEW_FORMAT_KEYS)을 하나라도 쓴 것만 2(FORMAT_VERSION_NEW)로, 나머지는 예전처럼 1(FORMAT_VERSION_OLD)로 적습니다
     (HT.packToJSON) — 옛 프로그램이 새 파일을 열면 경고가 뜨고, 옛 파일은 어디서나 그대로 읽힙니다.
     읽는 버전은 2입니다: 버전 2의 열쇠(HT.NEW_FORMAT_KEYS에 적힌 것)를 읽기 시작했습니다 — 목록이 빈 채로 2이거나 찼는데 1이면 scripts/dev-smoke.mjs가 잡습니다.
     새 열쇠를 더하는 단계는 HT.NEW_FORMAT_KEYS에 그 열쇠를 한 줄 더 적습니다.
     형식 버전 3(docs/구상-연표-확장-10건.md 1절 2번): 버전 3에서 생긴 열쇠·칸은 HT.NEW_FORMAT_KEYS_V3에 적고, 그것을 하나라도 쓴 파일만 3(FORMAT_VERSION_V3)으로 나갑니다
     (버전 2의 열쇠만 쓴 파일은 2, 아무것도 쓰지 않은 파일은 1 그대로 — HT.formatVersionOf). 읽는 버전은 3 — 버전 3의 목록이 차 있을 때만 3이어야 합니다(scripts/dev-smoke.mjs가 봄).
     형식 3의 열쇠는 세 갈래가 한 목록에 적습니다: 모아 보기 판 · 지도 · 글꼴(views · maps · fonts) · 단체 · 렌즈 재료(themes · groups · institutions · 사건의 theme · law · election) ·
     이름 목록 · 사람 잇기(names · surnames · places · person · accession · parents · spouses) */
  HT.FORMAT_VERSION = 3;
  HT.FORMAT_VERSION_OLD = 1;
  HT.FORMAT_VERSION_NEW = 2;
  HT.FORMAT_VERSION_V3 = 3;
  HT.CURRENT_YEAR = new Date().getFullYear();
  HT.USER_PACK = { id: 'user', name: '내 사건' };
  /* ICU에 기대지 않는 글 비교 · 수 글 (한 벌 P3 과제 4 — 엔진 Rust가 ICU 없이 똑같이 내도록 `localeCompare` · `toLocaleString('ko-KR')` 대신 쓴다).
     cmp16: UTF-16 코드 단위 차례 — 한글 음절끼리면 가나다 차례와 같고, 영문은 대문자가 소문자보다 앞(ICU는 a < B). 정렬 비교 함수 자리에 그대로 */
  HT.cmp16 = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
  /* groupDigits: `Number(n).toLocaleString('ko-KR')`과 같은 글 — 정수부 세 자리마다 ',' · 소수는 최대 세 자리까지 반올림(0.0005 → 0.001 · 반올림은 JS가 쓰는 짧은 10진 글 위에서 5 이상이면 올림 · 끝 0은 뺌) ·
     음수 '-' · -0은 '-0' · NaN은 'NaN' · 무한대는 '∞'. 1e21 이상도 자릿수를 다 적음 */
  HT.groupDigits = n => {
    const x = Number(n);
    if (x !== x) return 'NaN';
    const neg = x < 0 || Object.is(x, -0);
    if (x === Infinity || x === -Infinity) return neg ? '-∞' : '∞';
    const [m, e] = Math.abs(x).toExponential().split('e'); // 짧게 되돌릴 수 있는 유효숫자(JS 수 글과 같은 자릿수)
    let digits = m.replace('.', '').split('').map(Number);
    let point = Number(e) + 1; // 정수부 자릿수(0 이하면 소수점 바로 뒤에 0이 -point개)
    const keep = point + 3; // 남길 유효숫자 개수(소수 셋째 자리까지)
    if (digits.length > keep) {
      if (keep < 0) {
        digits = [0];
        point = 1;
      } else {
        const up = digits[keep] >= 5;
        digits = digits.slice(0, keep);
        if (up) {
          let i = digits.length - 1;
          while (i >= 0 && digits[i] === 9) digits[i--] = 0;
          if (i >= 0) digits[i]++;
          else {
            digits.unshift(1);
            point++;
          }
        }
      }
    }
    let int;
    let frac;
    if (point <= 0) {
      int = '0';
      frac = '0'.repeat(-point) + digits.join('');
    } else {
      const s = digits.join('') + '0'.repeat(Math.max(0, point - digits.length));
      int = s.slice(0, point);
      frac = s.slice(point);
    }
    frac = frac.replace(/0+$/, '');
    return (neg ? '-' : '') + int.replace(/\B(?=(\d{3})+$)/g, ',') + (frac ? `.${frac}` : '');
  };
  /* DLC 분류 (docs/구상-메이커-팩.md 2-3 — 패러독스의 확장팩 · 몰입팩 · 연대기팩 …을 연표에 맞게). 차례가 곧 DLC 관리 · 팩 정보의 차례 */
  HT.PACK_CATEGORIES = [
    { id: 'expansion', name: '확장팩', hint: '여러 지역 · 시대를 크게 더함' },
    { id: 'region', name: '지역팩', hint: '한 지역을 깊이' },
    { id: 'nation', name: '나라팩', hint: '한두 나라' },
    { id: 'theory', name: '학설팩', hint: '다른 팩의 연대 · 이름을 다른 학설로 덮어씀' },
    { id: 'world', name: '세계관팩', hint: '가상 세계 (소설 · 게임)' },
    { id: 'docs', name: '문서팩', hint: '문서(위키) 위주' },
  ];
  HT.PACK_CATEGORIES.push({ id: 'map', name: '지도팩', hint: '지도(바탕 그림 · 행정 층위 · 구역 · 장면)를 연표 자료와 따로' }); // 형식 3 (10건 10번 — 옛 프로그램은 모르는 분류로 경고하고 분류 없이 읽음)
  /* 팩 사이의 관계 (2-4) — '함께 쓰면 좋은 팩'은 있던 칸 requires 그대로 */
  HT.PACK_RELATIONS = [
    { id: 'needs', name: '필요한 팩' },
    { id: 'conflicts', name: '함께 못 씀' },
    { id: 'after', name: '뒤에 불러오기' },
  ];
  /* 팩 정보 칸의 한도 (2-2) — cover는 data URL 글자 수 */
  HT.PACK_LIMITS = { tags: 5, tagLen: 20, summary: 120, highlights: 10, highlightLen: 120, changelog: 200, noteLen: 500, cover: 2000000 };
  /* 형식 3의 한도 — 지도의 바탕 그림 · 장면 그림은 표지와 같은 한도(mapImage, data URL 글자 수), 글꼴은 하나에 font자 · 한 DLC에 fonts개 · 모두 합쳐 fontTotal자까지
     (웹 연표는 설치한 DLC를 브라우저 저장 공간에 두므로 — 필요한 글자만 담은 woff2를 권함. DLC-형식.md '글꼴') */
  Object.assign(HT.PACK_LIMITS, { mapImage: 2000000, font: 4000000, fonts: 8, fontTotal: 12000000 });

  HT.KEYS = {
    installed: 'ht.packs.installed',
    packState: 'ht.packs.state',
    user: 'ht.user', // 옛 "내 수정"(덧씌움) — 지금은 쓰지 않고, 남아 있으면 시작할 때 DLC로 옮깁니다 (HT.draft.migrateUser)
    userBackup: 'ht.user.backup', // 옮기기 전의 원본
    view: 'ht.view',
    ui: 'ht.ui',
    draft: 'ht.maker.draft', // 메이커가 고치는 DLC(작업본)
  };

  /* 연표의 표시 체크(칸·선 켜고 끄기)의 기본값 — 뷰어의 처음 설정 · 연표에 넘기는 옵션 · 체크 되살리기가 모두 이 표 하나를 봅니다 (show[key] ?? 기본값).
     저장된 설정(ui.show)에 없는 열쇠는 이 값으로 채워지므로, 뒤에 생긴 표시가 옛 사용자에게 꺼진 채로(또는 체크만 켜진 채로) 나오지 않습니다.
     승계선(succession)은 true · 'direct'(직접 승계만) · false 세 값입니다 */
  HT.SHOW_DEFAULTS = { dynasties: true, leaders: true, cabinets: true, eras: true, capitals: true, ganji: true, epochs: true, succession: true, partOf: true };
  Object.assign(HT.SHOW_DEFAULTS, { spotEcho: false }); // 조명 메아리: 칸(지도자 · 연호 …)을 골라 조명된 기간을 타국의 띠에서도 흐리지 않고 조명과 같은 짙기로, 그 시기의 사건도 — 기본 끔 (HT.echoEvents)
  Object.assign(HT.SHOW_DEFAULTS, { figures: true }); // 인물 단(띠 안 기간 막대 아래의 활동 막대)
  Object.assign(HT.SHOW_DEFAULTS, { phases: true }); // 시기 구분(학계): 띠 안 왕조 칸 아래 · 지도자 칸 위의 시기 단 — 기본 켬
  Object.assign(HT.SHOW_DEFAULTS, { ranks: true }); // 지위: 띠 안 시기 단 아래 · 지도자 칸 위의 지위 단과 책갈피 탭의 지위 딱지 — 기본 켬
  Object.assign(HT.SHOW_DEFAULTS, { houses: false }); // 가문 줄: 지도자 칸 아래에 가문 색의 가는 줄 — 기본 끔
  Object.assign(HT.SHOW_DEFAULTS, { groups: true }); // 단체: 띠 안 지위 단 아래 · 지도자 칸 위의 집권 단 · 실권 단(형식 3 groups — 자료가 있는 줄만)과 띠 위 연합의 겹 탭 — 기본 켬 (설계 7-8 결정 1 · 7절 4번)

  /* ---------- 색: 파스텔 팔레트로 고정 ----------
   * 연표·메이커에서 고를 수 있는 색은 아래 열두 가지 파스텔이고, DLC 파일에 다른 색이 적혀 있어도
   * 모델을 만들 때 HT.pastel()로 같은 채도·밝기 범위에 맞춥니다. */
  HT.PASTEL = [
    { id: '#d4a39b', name: '로즈' }, { id: '#dab195', name: '피치' }, { id: '#d7c18e', name: '버터' }, { id: '#b6c398', name: '세이지' },
    { id: '#9dbea8', name: '민트' }, { id: '#a0bcc5', name: '스카이' }, { id: '#abb3c9', name: '페리윙클' }, { id: '#bbacc8', name: '라벤더' },
    { id: '#d1a9b9', name: '핑크' }, { id: '#c8b193', name: '샌드' }, { id: '#a4b1b7', name: '슬레이트' }, { id: '#bba395', name: '모카' },
  ];
  const PALETTE = HT.PASTEL.map(c => c.id);

  HT.DEFAULT_CATEGORIES = [
    { id: 'politics', name: '정치', color: '#abb3c9' },
    { id: 'war', name: '전쟁', color: '#d4a39b' },
    { id: 'diplomacy', name: '외교·교류', color: '#9dbea8' },
    { id: 'society', name: '사회·경제', color: '#d7c18e' },
    { id: 'culture', name: '문화·사상', color: '#bbacc8' },
  ];

  /* 정권(시대) 띠에 쓰는 팔레트 — 한 트랙 안에서 차례로 배정됩니다 */
  HT.POLITY_PALETTE = ['#c8b193', '#9dbea8', '#abb3c9', '#bbacc8', '#dab195', '#b6c398', '#a0bcc5', '#a4b1b7', '#bba395', '#d1a9b9'];

  const hex6 = c => (c.length === 4 ? `#${[...c.slice(1)].map(h => h + h).join('')}` : c);
  const hexToRgb = h => [0, 2, 4].map(i => parseInt(hex6(h).slice(1 + i, 3 + i), 16) / 255);
  const rgbToHsl = (r, g, b) => {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min) return [0, 0, l];
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return [h / 6, s, l];
  };
  const hslToHex = (h, s, l) => {
    const f = t => {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      const p = 2 * l - q;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    };
    const rgb = s === 0 ? [l, l, l] : [f(h + 1 / 3), f(h), f(h - 1 / 3)];
    return `#${rgb.map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('')}`;
  };
  const pastelCache = new Map();
  /** 어떤 색이든 따스한 파스텔 범위(채도 14~46% · 밝기 66~74%)로 맞춥니다. 색조(hue)는 그대로라 서로 구별됩니다 */
  HT.pastel = c => {
    if (typeof c !== 'string' || !/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(c)) return c;
    const key = c.toLowerCase();
    if (PALETTE.includes(key)) return key; // 견본 색은 그대로
    if (pastelCache.has(key)) return pastelCache.get(key);
    const [h, s, l] = rgbToHsl(...hexToRgb(key));
    const out = s < 0.06 ? hslToHex(h, 0.08, Math.min(0.72, Math.max(0.62, l))) : hslToHex(h, Math.min(0.46, Math.max(0.14, s * 0.6)), Math.min(0.74, Math.max(0.66, l)));
    pastelCache.set(key, out);
    return out;
  };
  HT.hexToHsl = c => rgbToHsl(...hexToRgb(c));

  /* 연대의 확실성 등급 */
  HT.CERTAINTY = [
    { id: 'certain', name: '확실', hint: '사료로 연월일까지 분명한 경우' },
    { id: 'accepted', name: '통설', hint: '학계에서 널리 받아들이는 연대 (기본값)' },
    { id: 'estimated', name: '추정', hint: '고고학적 추정 등 대략적인 연대' },
    { id: 'legend', name: '전승', hint: '건국 신화처럼 전해 내려오는 연대' },
  ];
  HT.certaintyOf = x => {
    const c = x && x.certainty;
    if (HT.CERTAINTY.some(v => v.id === c)) return c;
    return x && x.legendary ? 'legend' : 'accepted';
  };
  HT.certaintyName = id => (HT.CERTAINTY.find(v => v.id === id) || { name: '' }).name;

  /* 실재성: 나라가 "있었는가" — 연대가 얼마나 확실한가(certainty)와는 다른 축입니다 (docs/구상-체제-확장.md 8-4 마).
     칸은 시대(periods)의 historicity · historicityNote(근거 글). 비우면 실재(attested). 옛 칸 legendary: true · certainty: "legend"는 지금처럼 연대의 전승입니다.
     tag = 책갈피 탭의 작은 딱지 · 상세 배지 글 */
  HT.HISTORICITY = [
    { id: 'attested', name: '실재', tag: '', hint: '있었음이 기록과 유물로 인정되는 나라 (기본값)' },
    { id: 'semi', name: '반전설', tag: '반전설', hint: '실재는 인정되나 기록이 전설에 기대는 나라' },
    { id: 'legendary', name: '전설', tag: '전설', hint: '전승·신화에만 전하는 나라' },
    { id: 'disputed', name: '실재 논쟁', tag: '논쟁', hint: '있었는지를 두고 학계가 갈리는 나라' },
    { id: 'refuted', name: '부정됨', tag: '부정', hint: '한때 인정되었으나 고고학·사료 비판으로 부정된 나라' },
  ];
  const HISTORICITY_WORDS = { 실재: 'attested', 반전설: 'semi', '반(半)전설': 'semi', 전설: 'legendary', 신화: 'legendary', 논쟁: 'disputed', '실재 논쟁': 'disputed', 부정: 'refuted', 부정됨: 'refuted' };
  /** 실재성 글(id 또는 한국어) → id. 모르는 글이면 '' (HT.capitalRole과 같은 틀) */
  HT.historicity = v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    return HT.HISTORICITY.some(h => h.id === s) ? s : HISTORICITY_WORDS[s] || '';
  };
  /** 항목의 실재성 id — 실재(비움 · attested)면 '' */
  HT.historicityOf = x => {
    const h = HT.historicity(x && x.historicity);
    return h === 'attested' ? '' : h;
  };
  HT.historicityName = id => (HT.HISTORICITY.find(h => h.id === (id || 'attested')) || HT.HISTORICITY[0]).name;
  HT.historicityTag = id => (HT.HISTORICITY.find(h => h.id === id) || { tag: '' }).tag;

  /* 간지(육십갑자). 이 연표는 0년이 없으므로 기원전은 천문 연도로 바꿔 셉니다. */
  const STEMS = '갑을병정무기경신임계';
  const BRANCHES = '자축인묘진사오미신유술해';
  HT.ganji = y => {
    const n = Math.floor(y + 1e-9);
    const astro = n < 0 ? n + 1 : n;
    const i = (((astro - 4) % 60) + 60) % 60;
    return STEMS[i % 10] + BRANCHES[i % 12];
  };
  HT.ganjiIndex = y => {
    const n = Math.floor(y + 1e-9);
    const astro = n < 0 ? n + 1 : n;
    return (((astro - 4) % 60) + 60) % 60;
  };

  /* 승계 관계 */
  HT.SUCCESSION = [
    { id: 'direct', name: '직접 승계', hint: '승계를 직접 선언한 경우 — 실선' },
    { id: 'indirect', name: '간접 승계', hint: '지역·거시적 관점의 승계 — 점선' },
  ];
  /* 부흥: 멸망한 나라를 되살리려는 세력이 옛 나라를 가리킬 때 — 승계선은 간접 승계와 같은 점선에 작은 고리(되돌아옴 — 후대 띠 바로 앞, 맞닿은 다리에서는 이음매 위). 줄 잇기 규칙은 다른 승계와 같습니다 */
  HT.SUCCESSION.push({ id: 'revival', name: '부흥', hint: '멸망한 나라를 되살리려 함 — 점선 + 작은 고리' });
  /* 부분 승계(건의 5 — 선 모양은 2026-10-13 감독 결정 '가는 한 줄 · 짙기 80%', 그 앞은 '늘 세 가닥 · 정도만큼 진하게'): 나라는 끊겼으나 지배층 · 백성 · 영역 · 제도 · 문화의 일부가 실제로 넘어간 경우.
     간접 승계는 '그 땅, 그 역사의 뒤'라는 관점(해석)으로 잇는 선, 부흥은 '옛 나라를 되살리겠다'는 주장, 부분 승계는 무엇이 넘어갔는지를 적는 선입니다.
     degree(정도 1 약 · 2 중 · 3 강 — 없으면 중) · parts(이어진 것 — 여러 개, 선택). 옛 앱은 모르는 종류를 간접 승계로 읽어(정도 · 이어진 것은 무시) 파일이 깨지지 않습니다 */
  HT.SUCCESSION.push({ id: 'partial', name: '부분 승계', hint: '나라는 끊겼으나 지배층·백성·영역·제도·문화의 일부가 넘어감 — 가는 실선, 정도는 설명 글에' });
  /* 한국어 종류 낱말 — 화면 낱말은 '승계'이고, 예전 화면 낱말(아래 한 줄)도 계속 읽습니다(옛 파일 · 옛 붙여넣기가 깨지지 않게) */
  const SUCCESSION_WORDS = { 직접: 'direct', '직접 승계': 'direct', 간접: 'indirect', '간접 승계': 'indirect', 부흥: 'revival', '부흥 승계': 'revival', 부분: 'partial', '부분 승계': 'partial' };
  Object.assign(SUCCESSION_WORDS, { '직접 계승': 'direct', '간접 계승': 'indirect', '부흥 계승': 'revival', '부분 계승': 'partial' }); // 옛 낱말
  /** 승계 종류를 id로 (한국어도 읽음). 모르는 값·빈 값은 간접 승계 — 옛 파일과 같습니다 */
  HT.successionType = v => {
    const s = String(v ?? '').trim();
    return HT.SUCCESSION.some(x => x.id === s) ? s : SUCCESSION_WORDS[s] || 'indirect';
  };
  HT.successionName = id => (HT.SUCCESSION.find(x => x.id === id) || HT.SUCCESSION[1]).name;
  /* 부분 승계의 정도(1 약 · 2 중 · 3 강)와 이어진 것 — 한국어도 읽습니다 */
  HT.SUCC_DEGREES = [
    { id: 1, name: '약' },
    { id: 2, name: '중' },
    { id: 3, name: '강' },
  ];
  HT.SUCC_DEGREE_DEFAULT = 2;
  const DEGREE_WORDS = { 약: 1, 중: 2, 강: 3, weak: 1, medium: 2, strong: 3, 약함: 1, 중간: 2, 강함: 3 };
  /** 정도 글 · 수 → 1 · 2 · 3, 읽지 못하면 null (적지 않은 것은 부르는 쪽이 기본값 중으로) */
  HT.succDegree = v => {
    if (typeof v === 'number') return v === 1 || v === 2 || v === 3 ? v : null;
    const s = String(v ?? '').trim();
    if (/^[123]$/.test(s)) return Number(s);
    return DEGREE_WORDS[s] || DEGREE_WORDS[s.toLowerCase()] || null;
  };
  HT.succDegreeName = d => (HT.SUCC_DEGREES.find(x => x.id === d) || HT.SUCC_DEGREES[1]).name;
  HT.SUCC_PARTS = [
    { id: 'elite', name: '지배층' },
    { id: 'people', name: '백성' },
    { id: 'land', name: '영역' },
    { id: 'institutions', name: '제도' },
    { id: 'culture', name: '문화' },
  ];
  const PART_WORDS = { 지배층: 'elite', 백성: 'people', 유민: 'people', 영역: 'land', 영토: 'land', 제도: 'institutions', 문화: 'culture' };
  /** 이어진 것 한 낱말 → id (모르면 '') */
  HT.succPart = v => {
    const s = String(v ?? '').trim();
    return HT.SUCC_PARTS.some(x => x.id === s) ? s : PART_WORDS[s] || '';
  };
  HT.succPartName = id => (HT.SUCC_PARTS.find(x => x.id === id) || { name: id }).name;
  /* 나라 승계의 방식(how — 설계 3-6 · 리메이크 6단계 결정 15 · 2026-10-24): 종류(직접 · 간접 · 부흥 · 부분)와 따로, 어떻게 넘어갔는지를 적습니다.
     설계의 일곱(혼인 · 상속 · 정복 · 갈라짐 · 합쳐짐 · 개명 · 주장)에 선양을 더함 — 갈라짐 · 합쳐짐 · 개명의 id는 단체의 앞선 단체(HT.GROUP_HOWS)와 같고,
     혼인 · 상속 · 정복 · 선양의 id는 자리 이음(HT.ACCESSION_HOWS)과 같습니다. 단체의 from.how(미상 포함)는 그대로 둡니다 */
  HT.SUCC_HOWS = [
    { id: 'marriage', name: '혼인' },
    { id: 'inheritance', name: '상속' },
    { id: 'conquest', name: '정복' },
    { id: 'split', name: '갈라짐' },
    { id: 'merge', name: '합쳐짐' },
    { id: 'rename', name: '개명' },
    { id: 'claim', name: '주장' },
    { id: 'abdication', name: '선양' },
  ];
  /* 표의 이름 말고도 읽는 낱말 — 띄어쓰기는 무시합니다(단체 · 조약의 낱말 표와 같은 규칙 · 제 낱말만) */
  const SUCC_HOW_WORDS = { 결혼: 'marriage', 분열: 'split', 분리: 'split', 갈라섬: 'split', 갈라져나옴: 'split', 합류: 'merge', 통합: 'merge', 합침: 'merge', 합병: 'merge', 이름바꿈: 'rename', 개칭: 'rename', 국호변경: 'rename', 승계주장: 'claim', 표방: 'claim', 자처: 'claim', 선위: 'abdication', 양위: 'abdication' };
  /** 승계 방식 → id (id · 이름 · 낱말 — 띄어쓰기는 무시). 모르면 '' */
  HT.succHow = v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    const hit = HT.SUCC_HOWS.find(x => x.id === s || x.name === s);
    if (hit) return hit.id;
    const k = s.replace(/\s+/g, '');
    return Object.prototype.hasOwnProperty.call(SUCC_HOW_WORDS, k) ? SUCC_HOW_WORDS[k] : '';
  };
  HT.succHowName = id => (HT.SUCC_HOWS.find(x => x.id === id) || { name: '' }).name;
  /** 승계 한 줄 읽기(DLC 읽기 · 패치 · 메이커가 같은 것을 부름): 이름만 적은 글 · { from, type, degree, parts, how, note } → 정리한 줄(선대가 없으면 null).
      부분 승계는 정도를 늘 적고(적지 않았으면 중), 이어진 것은 있을 때만 · 겹친 것은 한 번 — 다른 종류에 적힌 정도 · 이어진 것은 버립니다(선 모양에 쓰이지 않음).
      방식(how — HT.SUCC_HOWS)은 모든 종류에 둘 수 있고, 모르는 방식은 알리고 뺍니다.
      warn(글) — 읽지 못한 정도 · 이어진 것 · 방식을 알림 */
  HT.normalizeSucc = (x, warn = () => {}) => {
    const s = typeof x === 'string' ? { from: x } : x && typeof x === 'object' ? x : {};
    const t = v => (v == null ? '' : String(v).trim());
    const from = t(s.from);
    if (!from) return null;
    const type = HT.successionType(s.type);
    const o = { from, type };
    if (type === 'partial') {
      let d = s.degree == null || s.degree === '' ? HT.SUCC_DEGREE_DEFAULT : HT.succDegree(s.degree);
      if (d == null) {
        warn(`부분 승계 "${from}"의 정도 "${t(s.degree)}"을(를) 알 수 없어 중으로 봅니다(약 · 중 · 강 또는 1 · 2 · 3).`);
        d = HT.SUCC_DEGREE_DEFAULT;
      }
      o.degree = d;
      const raw = Array.isArray(s.parts) ? s.parts : t(s.parts) ? t(s.parts).split(/[,，、·]/) : [];
      const parts = [];
      for (const w of raw) {
        const id = HT.succPart(w);
        if (id && !parts.includes(id)) parts.push(id);
        else if (!id && t(w)) warn(`부분 승계 "${from}"의 이어진 것 "${t(w)}"을(를) 알 수 없어 뺐습니다(지배층 · 백성 · 영역 · 제도 · 문화).`);
      }
      if (parts.length) o.parts = HT.SUCC_PARTS.map(p => p.id).filter(id => parts.includes(id)); // 늘 같은 차례(지배층 → 문화)
    }
    if (t(s.how)) {
      const h = HT.succHow(s.how);
      if (h) o.how = h;
      else warn(`승계 "${from}"의 방식 "${t(s.how)}"을(를) 알 수 없어 뺐습니다(${HT.SUCC_HOWS.map(x => x.name).join(' · ')}).`);
    }
    if (t(s.note)) o.note = t(s.note);
    return o;
  };
  /** 흡수(합류): 후대 p가 선대 q의 끝보다 먼저 있었고 q가 끝난 뒤에도 이어짐 — 이미 있던 나라로 들어감. 연표는 선을 p의 건국 네모로 거꾸로 보내지 않고
      그해의 p 띠 테두리에 곧게 닿게(합류 조각), 상세 창은 '· n년 합류'. 띠의 시작 · 끝(연대 폭이면 바깥 끝)으로 봅니다 — 모든 승계 종류 */
  HT.succAbsorbs = (q, p) => {
    const bs = x => (x.startRange ? x.startRange[0] : x.start);
    const be = x => (x.endRange ? x.endRange[1] : x.endY);
    return !!q && !!p && bs(p) < be(q) && be(p) > be(q);
  };
  /** 승계 한 건의 글: '부분 승계 · 정도 중 · 지배층 · 백성' (부분이 아니면 종류 이름만) — 풍선 · 상세 · 패치 표시가 같은 말을 씁니다 */
  HT.successionLabel = e => {
    const type = (e && e.type) || 'indirect';
    if (type !== 'partial') return HT.successionName(type);
    const parts = (e.parts || []).map(HT.succPartName);
    return [HT.successionName(type), `정도 ${HT.succDegreeName(e.degree || HT.SUCC_DEGREE_DEFAULT)}`].concat(parts).join(' · ');
  };

  /* 정권(시대)의 종류 — 띠 모양이 달라집니다. (기관·문화는 시대와 별개 항목이라 여기서 고르지 않습니다) */
  HT.POLITY_KINDS = [
    { id: 'state', name: '국가', hint: '독립 국가·왕조 (기본값) — 보통 띠' },
    { id: 'vassal', name: '종속국', hint: '다른 나라에 종속된 정권 — 옅은 띠, 상국 띠 아래에 칠한 이름표로 매달림' },
    { id: 'federation', name: '연맹', hint: '여러 나라의 연합 — 속이 빈 겹줄 띠. 구성국은 "소속"으로 이 연맹을 가리킵니다' },
    { id: 'org', name: '조직체', hint: '국가가 아닌 독립 조직체 — 모서리가 각진 가는 띠' },
    { id: 'era', name: '시대 이름', hint: '왕조가 아닌 시대 이름을 띠로 놓을 때 — 테두리 없는 옅은 띠' },
  ];
  /* 종류의 갈래와 자율성 — short = 짧은 이름(책갈피 탭의 딱지 · 표 붙여넣기 — 종속 갈래는 탭에 딱지를 달지 않음) · family = sovereign(자주) | dependent(종속) | special(특수) ·
     autonomy = 종속 갈래의 자율성 3(높음) ~ 0(없음). 종속 갈래의 제 띠는 옅은 띠 하나이고, 누구를 어떻게 섬겼는지는 상국 띠의 속국 이름표가 말합니다
     (2026-09-20 '뒤집기' — 자율성 3 · 2는 상국 띠 아래에 매달리고 1 · 0은 상국 띠 안으로 들어옴, timeline.js depProxies). hint는 범례·폼이 쓰는 ' — 모양' 꼴을 지킵니다 */
  const KIND_TRAITS = { state: { family: 'sovereign', autonomy: 4 }, vassal: { short: '종속', family: 'dependent', autonomy: 2 }, federation: { short: '연맹', family: 'special' }, org: { short: '조직', family: 'special' }, era: { short: '시대', family: 'special' } };
  HT.POLITY_KINDS.forEach(k => Object.assign(k, KIND_TRAITS[k.id]));
  HT.POLITY_KINDS.push(
    { id: 'tributary', name: '조공·책봉국', short: '조공', family: 'dependent', autonomy: 3, hint: '조공을 바치고 책봉을 받되 안은 스스로 다스린 나라 — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림' },
    { id: 'fief', name: '봉국·제후국', short: '봉국', family: 'dependent', autonomy: 3, hint: '상국이 봉한 제후의 나라 — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림' },
    { id: 'dominion', name: '자치령', short: '자치', family: 'dependent', autonomy: 3, hint: '본국 아래에서 스스로 다스리는 땅 — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림' },
    { id: 'warlord', name: '군벌·할거 세력', short: '군벌', family: 'dependent', autonomy: 3, hint: '상징적 본국을 받들되 실제로는 따로 다스린 세력 — 옅은 띠, 상국 띠 아래에 점선 이름표로 매달림' },
    { id: 'protectorate', name: '보호국', short: '보호', family: 'dependent', autonomy: 2, hint: '외교·군사를 상국에 맡긴 나라 — 옅은 띠, 상국 띠 아래에 칠한 이름표로 매달림' },
    { id: 'satellite', name: '위성국', short: '위성', family: 'dependent', autonomy: 2, hint: '형식은 독립국이나 상국의 뜻을 따르는 나라 — 옅은 띠, 상국 띠 아래에 칠한 이름표로 매달림' },
    { id: 'puppet', name: '괴뢰국', short: '괴뢰', family: 'dependent', autonomy: 1, hint: '다른 나라가 세워 움직이는 정권 — 옅은 띠, 상국 띠 안 맨 아래에 옅은 이름표로 들어감' },
    { id: 'mandate', name: '위임·신탁 통치령', short: '위임', family: 'dependent', autonomy: 1, hint: '다른 나라가 맡아 다스리는 땅 — 옅은 띠, 상국 띠 안 맨 아래에 옅은 이름표로 들어감' },
    { id: 'colony', name: '식민지·속령', short: '식민', family: 'dependent', autonomy: 0, hint: '본국이 직접 다스리는 바깥 땅 — 옅은 띠, 상국 띠 안 맨 아래에 짙은 이름표로 들어감' },
    { id: 'occupied', name: '점령지·군정', short: '점령', family: 'dependent', autonomy: 0, hint: '다른 나라 군대가 차지해 다스리는 땅 — 옅은 띠, 상국 띠 안 맨 아래에 빗금 이름표로 들어감' },
    /* 시대마다의 특별한 형태(묶음 3 · 3번 — 감독 결정 2026-09-22): 고대 · 중세의 변방 복속 세력(나라가 아닌 세력 — 조직체의 점선 테두리를 빌린 옅은 띠),
       직할령 · 군현(상국이 관리를 보내 직접 다스림 — 식민과 같은 그림 · 이름만 시대에 맞게), 변경 간접 통치(기미 · 토사 · 번부 — 자치령과 같은 그림) */
    { id: 'client', name: '복속 세력·부용', short: '복속', family: 'dependent', autonomy: 3, hint: '나라가 아닌 변방의 복속 세력 · 부용(옥저 · 동예 · 부족 …) — 점선 테두리의 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림' },
    { id: 'frontier', name: '기미·번부·토사', short: '기미', family: 'dependent', autonomy: 3, hint: '직함만 주고 현지 수장이 다스린 변경(기미주 · 토사 · 번부) — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림' },
    { id: 'prefecture', name: '직할령·군현', short: '군현', family: 'dependent', autonomy: 0, hint: '상국이 관리를 보내 직접 다스린 땅(군현 · 도호부 · 총관부) — 옅은 띠, 상국 띠 안 맨 아래에 짙은 이름표로 들어감' },
    { id: 'exile', name: '망명 정부', short: '망명', family: 'special', hint: '제 땅을 잃고 나라 밖에서 이어 간 정부 — 옅은 띠 · 딱지 "망명"' },
    { id: 'movement', name: '부흥·저항 세력', short: '세력', family: 'special', hint: '멸망한 나라를 되살리려 하거나 지배에 맞선 세력 — 왼쪽에 깃대가 선 옅은 띠 · 딱지 "세력"' },
  );
  /* 폼·필터·범례에 나오는 순서: 자주 → 종속(자율성이 높은 것부터) → 특수 */
  const KIND_ORDER = ['state', 'tributary', 'fief', 'dominion', 'warlord', 'client', 'frontier', 'vassal', 'protectorate', 'satellite', 'puppet', 'mandate', 'colony', 'prefecture', 'occupied', 'federation', 'org', 'era', 'exile', 'movement'];
  const kindRank = id => (KIND_ORDER.includes(id) ? KIND_ORDER.indexOf(id) : KIND_ORDER.length); // 이 목록에 없는 종류(뒤에 더해지는 것)는 맨 뒤에
  HT.POLITY_KINDS.sort((a, b) => kindRank(a.id) - kindRank(b.id));
  HT.KIND_FAMILIES = [{ id: 'sovereign', name: '자주' }, { id: 'dependent', name: '종속 (자율성이 높은 것부터)' }, { id: 'special', name: '특수' }];
  HT.kindFamily = id => (HT.POLITY_KINDS.find(k => k.id === id) || {}).family || '';
  /* 한국어 → 종류 id (이름 · 딱지 · 흔한 다른 말). 어휘마다 표를 따로 둡니다 (도읍 역할의 HT.capitalRole과 같은 틀) */
  const KIND_WORDS = { 나라: 'state', 조공국: 'tributary', 책봉국: 'tributary', 봉국: 'fief', 제후국: 'fief', 번국: 'fief', 군벌: 'warlord', '할거 세력': 'warlord', 속국: 'vassal', 보호령: 'protectorate', '괴뢰 정권': 'puppet', '위임 통치령': 'mandate', '신탁 통치령': 'mandate', 식민지: 'colony', 속령: 'colony', 점령지: 'occupied', 군정: 'occupied', 조직: 'org', 망명정부: 'exile', '부흥 세력': 'movement', '저항 세력': 'movement', '부흥 운동': 'movement',
    /* 시대마다의 말(묶음 3 · 3번): 복속 세력 · 직할령 · 변경 간접 통치의 새 종류와, 옛 말을 이미 있는 종류로 */
    '복속 세력': 'client', 복속: 'client', 부용: 'client', 부용국: 'client', 기미: 'frontier', 기미주: 'frontier', 토사: 'frontier', 번부: 'frontier',
    군현: 'prefecture', 도호부: 'prefecture', 도독부: 'prefecture', 총관부: 'prefecture', 직할령: 'prefecture',
    부마국: 'vassal', 번: 'fief', 특별행정구: 'dominion', 자치구: 'dominion', 절도사: 'warlord', 번진: 'warlord' };
  HT.KIND_WORDS = KIND_WORDS; // 메이커의 표 붙여넣기도 같은 표로 읽습니다 (파일로 읽을 때와 붙여넣을 때 같은 낱말이 같은 종류가 되게)
  HT.polityKindId = v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    const hit = HT.POLITY_KINDS.find(k => k.id === s || k.name === s || k.short === s);
    return hit ? hit.id : KIND_WORDS[s] || '';
  };

  /* 소속 관계(partOf[].relation) — 종속 갈래의 종류 열 가지와 같은 말 + 명목상 · 구성국 · 동군연합. autonomy는 상국 띠의 속국 이름표 자리를 정합니다
     (3 · 2 = 상국 띠 아래에 매달림, 1 · 0 = 상국 띠 안 맨 아래로 들어옴 — timeline.js depProxies). 구성국 · 동군연합(hollow)은 예속이 아닌 소속(파선 이름표).
     명목상(nominal): 상징적 본국을 받들되 실제로는 따로 다스림 — 매달린 이름표가 점선(가장 옅은 종속) */
  /* 문화권(sphere — 트랙 위의 한 층 · 리메이크 설계 3-7 · 조각 ②): 트랙마다 `sphere`에 문화권 id를 적습니다. 프로그램에 든 문화권은 없고 모두 DLC의 최상위 `spheres`가 만듭니다
     (2026-10-23 — 동아시아 `east-asia`는 기본팩이, 가상 세계 일곱은 등불 견본이 제 것으로 듦 · DLC-형식.md 'spheres'). 적지 않은 트랙은 문화권이 없어 머리 단 없이 모든 문화권 뒤에 섭니다.
     'cultures'(고고 문화) · 형식 4의 'realm'(나라)과는 다른 말입니다 */
  let SPHERE_MAP = new Map(); // 마지막으로 지은 모델(HT.buildModel → HT.mergeSpheres)의 사전 — 켠 DLC들의 spheres
  /** 문화권 id → 문화권(모르는 id · 빈 글이면 null) — 마지막 모델의 사전 */
  HT.sphereOf = id => (id ? SPHERE_MAP.get(id) || null : null);
  /** 아는 문화권 id인가(마지막 모델의 사전) */
  HT.isSphere = id => !!id && SPHERE_MAP.has(id);
  /** 문화권의 차례 값 — 문화권이 없는 트랙(빈 글 · 못 찾음)은 모든 문화권 뒤 */
  HT.sphereOrder = id => {
    const s = HT.sphereOf(id);
    return s ? s.order : Infinity;
  };
  /** DLC의 문화권 사전(최상위 spheres) 읽기 — HT.readRankDefs와 같은 꼴 { list, problems, at }. id가 없거나 틀린 줄 · 겹친 id는 빼고 알립니다. 이름을 비우면 id.
      줄마다 지도자 표기 낱말 leaderLabels(6단계 D3 — HT.readLeaderLabels · 못 읽는 칸은 알리고 뺌)도 받습니다 */
  HT.readSpheres = v => {
    const list = [];
    const problems = [];
    const at = [];
    const s = x => String(x ?? '').trim();
    const bad = (i, m) => {
      problems.push(m);
      at.push(i);
    };
    if (v != null && v !== '' && !Array.isArray(v)) bad(undefined, '문화권 사전(spheres)은 목록이어야 해서 무시했습니다.');
    (Array.isArray(v) ? v : []).forEach((d, i) => {
      if (!d || typeof d !== 'object' || Array.isArray(d)) return bad(i, `문화권 #${i + 1}: 형식이 올바르지 않습니다.`);
      const id = s(d.id);
      if (!ID_RE.test(id)) return bad(i, `문화권 #${i + 1}${s(d.name) ? ` "${s(d.name)}"` : ''}: id가 비었거나 올바르지 않습니다(영문 · 숫자 · - _ .).`);
      if (list.some(x => x.id === id)) return bad(i, `문화권 "${id}"가 중복되어 뒤의 것을 무시했습니다.`);
      const o = { id, name: s(d.name) || id };
      if (d.order !== '' && d.order != null && isFinite(d.order)) o.order = Number(d.order);
      if (s(d.description)) o.description = s(d.description);
      const words = HT.readLeaderLabels(d.leaderLabels, m => bad(i, `문화권 "${id}": ${m}`)); // 지도자 표기 낱말(리메이크 6단계 D3 — 팩의 것보다 이김)
      if (words) o.leaderLabels = words;
      list.push(o);
    });
    return { list, problems, at };
  };
  /** 모델의 문화권 사전: 켠 DLC들의 spheres를 차례대로 — 같은 id는 먼저 놓인 DLC가 이깁니다. 차례는 적은 order, 비우면 1000부터 놓인 차례(적은 것 뒤).
      결과는 차례대로 [{ id, name, order, description?, leaderLabels?, packId }] — leaderLabels는 지도자 표기 낱말(6단계 D3 · HT.leaderWords) */
  HT.mergeSpheres = packs => {
    const byId = new Map();
    let n = 0;
    for (const pack of packs || [])
      for (const d of (pack && pack.spheres) || []) {
        if (!d || !d.id || byId.has(d.id)) continue;
        byId.set(d.id, Object.assign({ id: d.id, name: d.name || d.id, order: d.order != null ? d.order : 1000 + n++, packId: pack.id }, d.description ? { description: d.description } : {}, d.leaderLabels ? { leaderLabels: d.leaderLabels } : {}));
      }
    return [...byId.values()].sort((a, b) => a.order - b.order);
  };
  /** 이 사전을 HT.sphereOf · HT.isSphere가 쓰게 (HT.buildModel이 모델을 지을 때 — 내보내기 · 메이커의 고르기 칸도 마지막 모델의 사전을 봅니다) */
  HT.useSpheres = list => {
    SPHERE_MAP = new Map(list.map(x => [x.id, x]));
    return SPHERE_MAP;
  };

  HT.RELATIONS = HT.POLITY_KINDS.filter(k => k.family === 'dependent' && k.id !== 'warlord').map(k => ({ id: k.id, name: k.name, short: k.short, autonomy: k.autonomy }));
  HT.RELATIONS.splice(HT.RELATIONS.findIndex(r => r.autonomy < 3), 0, { id: 'nominal', name: '명목상 소속', short: '명목', autonomy: 3 });
  HT.RELATIONS.push({ id: 'member', name: '구성국', short: '구성', hollow: true }, { id: 'union', name: '동군연합', short: '동군', hollow: true });
  const RELATION_WORDS = { 조공: 'tributary', 책봉: 'tributary', 조공국: 'tributary', 책봉국: 'tributary', 봉국: 'fief', 제후국: 'fief', 번국: 'fief', 자치: 'dominion', 명목상: 'nominal', 명목: 'nominal', 종속: 'vassal', 속국: 'vassal', 보호: 'protectorate', 보호령: 'protectorate', 위성: 'satellite', 괴뢰: 'puppet', '괴뢰 정권': 'puppet', 위임: 'mandate', 신탁: 'mandate', '위임 통치령': 'mandate', '신탁 통치령': 'mandate', 식민: 'colony', 식민지: 'colony', 속령: 'colony', 점령: 'occupied', 점령지: 'occupied', 군정: 'occupied', 구성: 'member', 가맹국: 'member', 동군: 'union', '동군 연합': 'union',
    /* 시대마다의 말(묶음 3 · 3번) — 종류의 낱말(KIND_WORDS)과 같은 짝 */
    복속: 'client', 부용: 'client', 기미: 'frontier', 토사: 'frontier', 번부: 'frontier', 직할: 'prefecture', 군현: 'prefecture', 도호부: 'prefecture', 총관부: 'prefecture',
    부마: 'vassal', 부마국: 'vassal', 번: 'fief', 특별행정구: 'dominion', 자치구: 'dominion', 절도사: 'nominal', 번진: 'nominal' };
  HT.relationId = v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    const hit = HT.RELATIONS.find(r => r.id === s || r.name === s || r.short === s);
    return hit ? hit.id : RELATION_WORDS[s] || '';
  };
  HT.relationInfo = id => HT.RELATIONS.find(r => r.id === id) || null;
  HT.relationName = id => (HT.relationInfo(id) || { name: '' }).name;
  /** 소속 관계를 적지 않았을 때 종류에서 빌리는 관계 (설명글과 상국 띠의 속국 이름표 모양에 — 종속 갈래 종류만, 그 밖은 빈 값 = 예속이 아닌 소속) */
  HT.relationOfKind = kind => (kind === 'warlord' ? 'nominal' : HT.kindFamily(kind) === 'dependent' ? kind : '');
  /* 시대와 별개인 항목의 종류: 기관은 정권 띠 아래쪽에 큰 띠로, 문화는 승계국 줄 밑 바탕 띠로 그립니다 */
  HT.EXTRA_KINDS = [
    { id: 'culture', name: '문화', hint: '국가 이전의 고고학 문화 — 승계국 줄 밑에 깔리는 바탕 띠' },
    { id: 'overlay', name: '기관', hint: '주권 정권 안에 놓인 외세 기관·특수 구역 — 기관은 시대 띠 안 맨 아래의 기관 칸에, 구역은 시대 띠 아래로 내려오는 작은 탭으로 (둘 다 성긴 빗금 = 외세의 손길 · 속국 이름표는 민무늬)' },
    { id: 'dynasty', name: '왕조', hint: '나라(국체)를 다스린 왕가 — 다스린 시대 띠 맨 위의 왕조 칸에 긴 둥근 칸으로. 나라와 왕조가 같으면 적지 않아도 됩니다' },
  ];
  HT.ALL_KINDS = HT.POLITY_KINDS.concat(HT.EXTRA_KINDS);
  /* DLC 파일에서는 kind, 병합된 모델에서는 polityKind (모델의 kind는 'period'/'event' 구분에 쓰입니다) */
  HT.kindOf = x => {
    const c = x && (x.polityKind || x.kind);
    return HT.ALL_KINDS.some(k => k.id === c) ? c : 'state';
  };
  HT.kindName = id => (HT.ALL_KINDS.find(k => k.id === id) || HT.POLITY_KINDS[0]).name;
  /** 항목의 종류 이름: 시대·사건·기관·문화·시대 구분 */
  HT.ITEM_WORDS = { period: '시대', event: '사건', organ: '기관', culture: '문화', dynasty: '왕조', epoch: '시대 구분', people: '민족', track: '트랙', category: '분류', cell: '칸' };
  Object.assign(HT.ITEM_WORDS, { figure: '인물' });
  Object.assign(HT.ITEM_WORDS, { house: '가문' });
  Object.assign(HT.ITEM_WORDS, { treaty: '조약' }); // 조약: treaty 칸이 있는 사건 (모델의 itemKind — 표 보기 · 내보내기의 구분 칸)
  Object.assign(HT.ITEM_WORDS, { scope: '대범위' }); // 대범위 (docs/구상-체제-확장.md 7) — 모델에서 itemKind 'scope'
  HT.itemKindOf = x => x.itemKind || (x.kind === 'event' ? 'event' : x.kind === 'epoch' ? 'epoch' : x.polityKind === 'overlay' ? 'organ' : x.polityKind === 'culture' ? 'culture' : x.polityKind === 'dynasty' ? 'dynasty' : 'period');
  HT.itemWord = x => HT.ITEM_WORDS[HT.itemKindOf(x)] || '항목';

  /* 도읍(수도)의 역할 — 정도(기본) · 공동 정도 · 배도(별도·5경·소경) · 임시(피난·행재) · 망명 */
  HT.CAPITAL_ROLES = [
    { id: 'main', name: '정도' },
    { id: 'co', name: '공동 정도' },
    { id: 'secondary', name: '배도' },
    { id: 'temporary', name: '임시' },
    { id: 'exile', name: '망명' },
  ];
  const ROLE_WORDS = { 정도: 'main', 공동: 'co', '공동 정도': 'co', 배도: 'secondary', 별도: 'secondary', 소경: 'secondary', '5경': 'secondary', 임시: 'temporary', 피난: 'temporary', 행재: 'temporary', 망명: 'exile' };
  HT.capitalRole = v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    return HT.CAPITAL_ROLES.some(r => r.id === s) ? s : ROLE_WORDS[s] || '';
  };
  HT.capitalRoleName = id => (HT.CAPITAL_ROLES.find(r => r.id === id) || HT.CAPITAL_ROLES[0]).name;
  /** 도읍 항목 하나를 깨끗한 꼴로: [도시, 시작, 끝, 역할|메모] · { city(또는 name), start, end, role(한국어도), as, label, group, event, note }.
      연도는 "기원전 57"도 숫자로, 역할 main은 뺍니다. 도시나 시작이 없으면 null.
      시작 · 끝에 "미정"도 됩니다(칸의 미정 — HT.readCellEdge): startUnknown/endUnknown + 배치용 연도가 있으면 start/end 숫자.
      모델이 짐작해 넣은 자리(startAuto · endAuto가 붙은 값)는 없는 것으로 봅니다 — 모델의 도읍을 다시 넣어도 파일의 꼴이 나옵니다.
      DLC 읽기·수정 폼·패치·모델(HT.resolveCapitals)·내보내기 비교가 모두 이 꼴을 씁니다.
      확실성 · 연대 폭 · 이설도 다른 칸과 같은 읽기(HT.readUncertain — warn(글)을 주면 뺀 것을 알림) */
  HT.normalizeCapital = (raw, warn = null) => {
    const c = Array.isArray(raw) ? { city: raw[0], start: raw[1], end: raw[2], extra: raw[3] } : raw && typeof raw === 'object' ? raw : {};
    const s = v => (v == null ? '' : String(v).trim());
    const city = s(c.city ?? c.name);
    const sd = HT.readCellEdge(c, 'start');
    if (!city || !sd || (!sd.unknown && isNaN(sd.t))) return null;
    const o = { city };
    if (sd.unknown) {
      if (sd.t != null) o.start = sd.t;
      o.startUnknown = true;
    } else {
      o.start = sd.t;
      if (sd.at) o.startAt = sd.at;
    }
    const ed = HT.readCellEdge(c, 'end');
    /* 시작이 미정이고 그 배치용 연도가 적은 끝보다 뒤면 배치용 연도를 버립니다(적은 끝은 사실 — 지위 변천 · 시기 · 섬긴 기록과 같은 규칙) */
    if (o.startUnknown && o.start != null && ed && !ed.unknown && !isNaN(ed.t) && HT.endBound(ed.t, ed.at) < o.start) delete o.start;
    const start = o.start ?? -Infinity;
    if (ed && ed.unknown) {
      if (ed.t != null && ed.t >= start) o.end = ed.t;
      o.endUnknown = true;
    } else if (ed && !isNaN(ed.t) && HT.endBound(ed.t, ed.at) >= start) {
      o.end = ed.t;
      if (ed.at) o.endAt = ed.at;
    }
    const role = HT.capitalRole(c.role) || HT.capitalRole(c.extra);
    if (role && role !== 'main') o.role = role;
    if (s(c.as) && s(c.as) !== city) o.as = s(c.as);
    if (s(c.label)) o.label = s(c.label);
    if (s(c.group)) o.group = s(c.group);
    if (s(c.event)) o.event = s(c.event);
    const note = s(c.note) || (c.extra != null && !HT.capitalRole(c.extra) ? s(c.extra) : '');
    if (note) o.note = note;
    Object.assign(o, HT.readUncertain(c, { mode: 'cell', warn: warn && (m => warn(`도읍 "${city}" — ${m}`)), start: o.start, end: o.end }));
    return o;
  };
  /** 모델의 도읍 목록: 깨끗한 꼴로 바꾸고(패치·내 수정도) 역할을 채웁니다. 끝을 비운 정도·공동·망명·임시는 다음 정도(또는 망명)가
      시작할 때까지(없으면 정권 끝까지) — 공동 정도는 정도를 끊지 않고 나란히 갑니다. 배도는 정권 끝까지.
      name = 그때 이름(as) 또는 도시 — 지도자·연호 칸과 같은 틀(문서·검색)에 씁니다.
      칸의 미정: 배치용 연도 없이 시작이 미정인 정도 · 망명은 앞 정도(정도 · 망명)의 끝에서(끝을 비운 앞 정도면 그 시작과 이 칸의 끝 사이 가운데 — HT.cellStartGuess,
      이 칸의 끝도 없으면 다음 정도의 시작 · 정권의 끝까지의 가운데 — HT.cellStartCap), 임시 · 공동은 그때 있던 정도의 시작과 이 칸의 끝 사이 가운데,
      그것도 모르면(배도도) 정권의 시작에서 — 짐작한 시작은 startAuto로 표시합니다. 끝이 미정이면 끝을 비운 칸과 같은 자리(다음 정도의 시작 · 정권의 끝)에 놓입니다 */
  HT.resolveCapitals = p => {
    /* 모델 사본에만 붙인 것(지명 사전 id로 적은 도읍의 placeId · 문서 이름 docName — buildModel의 지명 사전 덩어리)은 다시 다듬어도 그대로 */
    const keep = (c, n) => (n && c && typeof c === 'object' && !Array.isArray(c) && c.placeId ? Object.assign(n, { placeId: c.placeId }, c.docName ? { docName: c.docName } : null) : n);
    const list = HT.sortCells(
      (p.capitals || [])
        .map(c => keep(c, HT.normalizeCapital(c)))
        .filter(Boolean)
        .map(c => Object.assign(c, { role: c.role || 'main' }))
    );
    if (list.some(c => c.start == null)) {
      const isSeat = c => c.role === 'main' || c.role === 'exile';
      let prevSeat = null;
      list.forEach((c, i) => {
        const seat = isSeat(c);
        if (c.start == null) {
          /* 넘지 않을 자리: 이 칸의 끝 → 다음 정도 · 망명의 자리 → 정권의 끝 (HT.cellStartCap). 배도는 예전처럼 정권의 시작에서.
             정도 · 망명은 앞 정도의 끝에서(끝을 비운 앞 정도면 그 시작과 다음 자리 사이 가운데),
             임시 · 공동은 그때 있던 정도가 이어지는 도중이라 그 정도의 끝은 보지 않고 그 시작과 이 칸의 끝 사이 가운데에 */
          const secondary = c.role === 'secondary';
          const cap = secondary ? c.end ?? Infinity : HT.cellStartCap(c, list.slice(i + 1).filter(isSeat), p);
          const prev = secondary || !prevSeat ? null : seat ? prevSeat : { start: prevSeat.start };
          c.start = HT.cellStartGuess(prev, cap, p.start);
          c.startAuto = true;
        }
        if (seat) prevSeat = c;
      });
      list.sort((a, b) => a.start - b.start);
    }
    const seats = list.filter(c => c.role === 'main' || c.role === 'exile');
    const last = p.endY ?? p.end ?? p.start;
    const lastAt = HT.atOf(p, 'end');
    return list.map(c => {
      let e = c.end;
      let at = HT.atOf(c, 'end'); // endY의 날짜 글 (끝을 비웠으면 다음 정도의 시작 · 정권의 끝)
      let next = null;
      if (e == null) {
        if (c.role === 'secondary') [e, at] = [last, lastAt];
        else {
          next = seats.find(m => m !== c && m.start > c.start);
          [e, at] = next ? [next.start, HT.atOf(next, 'start')] : [last, lastAt];
        }
      }
      /* endYNext: 끝을 다음 정도의 시작에서 끌어냄 — 그 끝은 사람이 적은 "그해까지"가 아니라 다음 칸이 시작하는 순간(HT.cellSpan의 hi).
         endYAuto: 그 다음 정도의 시작이 미정이라 짐작한 자리 — 이 칸의 끝도 모르는 것으로 보입니다(글은 "미정", 끝이 옅어짐 · 파일에는 적지 않음) */
      return Object.assign(c, { name: c.as || c.city, endY: Math.max(c.start, e), endYAt: e >= c.start ? at : HT.atOf(c, 'start') }, next ? { endYNext: true } : null, next && next.startAuto ? { endYAuto: true } : null);
    });
  };

  /* 지도자 칸 표기 방식 */
  HT.LEADER_LABELS = [
    { id: 'auto', name: '기본 이름' },
    { id: 'temple', name: '묘호' },
    { id: 'title', name: '시호' },
    { id: 'given', name: '이름' },
    { id: 'temple-title', name: '묘호·시호' },
    { id: 'all', name: '모두' },
  ];
  /* 지도자 표기 낱말(리메이크 6단계 D3 · 2026-10-24): 칸은 그대로 두고 뜻을 넓혀 읽습니다 — temple = 묘호 · 치세명 · 교황명 · 라캅, title = 시호 · 존호 · 별명,
     given = 이름 · 본명. 화면 낱말만 팩(최상위 leaderLabels)과 문화권(spheres[].leaderLabels — 팩의 것보다 이김)이 정하고, 비운 칸은 아래 기본 낱말입니다(HT.leaderWords) */
  HT.LEADER_WORDS = { temple: '묘호', title: '시호', given: '이름' };
  const LEADER_WORD_KEYS = ['temple', 'title', 'given'];
  /** 지도자 표기 낱말 읽기 — { temple?, title?, given? }(빈 칸은 뺌 · 하나도 없으면 null). 객체가 아니거나 모르는 칸은 warn으로 알리고 뺍니다 */
  HT.readLeaderLabels = (v, warn = () => {}) => {
    if (v == null || v === '') return null;
    if (typeof v !== 'object' || Array.isArray(v)) {
      warn('지도자 표기 낱말(leaderLabels)은 { "temple", "title", "given" } 꼴이어야 해서 무시했습니다.');
      return null;
    }
    const o = {};
    for (const k of LEADER_WORD_KEYS) {
      const s = v[k] == null ? '' : String(v[k]).trim();
      if (s) o[k] = s;
    }
    const extra = Object.keys(v).filter(k => !LEADER_WORD_KEYS.includes(k));
    if (extra.length) warn(`지도자 표기 낱말(leaderLabels)의 ${extra.map(k => `"${k}"`).join(' · ')}은(는) 모르는 칸이라 뺐습니다(temple · title · given).`);
    return Object.keys(o).length ? o : null;
  };
  /** 이름 번호(regnal — 리메이크 6단계 D2) 읽기: 양의 정수(수 · 수 글) → 수, 비었으면 null, 그 밖은 NaN(부르는 곳이 알리고 뺌) */
  HT.readRegnal = v => {
    if (v == null || (typeof v === 'string' && !v.trim())) return null;
    const n = typeof v === 'number' || typeof v === 'string' ? Number(v) : NaN;
    return Number.isInteger(n) && n > 0 ? n : NaN;
  };
  /** 지도자 한 칸의 표시 이름. c = { name, temple(묘호), title(시호), given(이름), ordinal(대수), regnal(이름 번호) }.
      이름 번호는 대표 이름(기본 표기 — 고른 칸이 비어 대표 이름으로 돌아온 때도)에 뒷말 "n세"로 붙습니다("헨리 8세" — 로마 숫자는 보는 사람 몫이라 형식에 두지 않음) */
  HT.leaderLabel = (c, mode = 'auto', withOrdinal = false) => {
    let s;
    if (mode === 'temple') s = c.temple;
    else if (mode === 'title') s = c.title;
    else if (mode === 'given') s = c.given;
    else if (mode === 'temple-title') s = [c.temple, c.title].filter(Boolean).join(' ');
    else if (mode === 'all') s = [c.temple, c.title, c.given].filter(Boolean).join(' ');
    if (!s) {
      s = c.name || c.temple || c.title || c.given || '';
      if (s && c.regnal != null) s = `${s} ${c.regnal}세`;
    }
    if (withOrdinal && c.ordinal != null) s = `${c.ordinal}대 ${s}`;
    return s;
  };
  /** 대수가 빠진 지도자에게 앞 지도자에 이어 번호를 매깁니다. 대수 미상(ordinalUnknown)인 지도자는 번호 없이 두고,
      그 뒤의 빈 대수는 다음 대수를 적은 지도자가 나올 때까지 잇지 않습니다(몇째인지 셀 수 없으므로 — 그 칸들도 미상).
      이름 번호(regnal)를 하나라도 적은 지도자 줄은 빈 대수를 매기지 않습니다(6단계 D2 — 유럽 · 교황처럼 번호가 이름에 붙는 줄 · 적은 대수는 그대로) */
  HT.numberLeaders = list => {
    const named = (list || []).some(c => c && c.regnal != null);
    let n = 0;
    let lost = false;
    for (const c of list || []) {
      if (c.ordinalUnknown) {
        delete c.ordinal; // 파일에 "ordinal": null이 남지 않게
        lost = true;
      } else if (c.ordinal != null) {
        n = c.ordinal;
        lost = false;
      } else if (named) continue;
      else if (lost) c.ordinalUnknown = true;
      else c.ordinal = ++n;
    }
    return list;
  };
  /** 지도자의 다른 이름들 — ["묘호 세종", "시호 …", "이름 이도"] (낱말은 words — HT.leaderWords, 비우면 기본 낱말) */
  HT.leaderFacts = (c, words) => {
    const w = Object.assign({}, HT.LEADER_WORDS, words || null);
    return [c.temple && `${w.temple} ${c.temple}`, c.title && `${w.title} ${c.title}`, c.given && `${w.given} ${c.given}`].filter(Boolean);
  };
  /** 지도자의 모든 이름을 한 줄로 (툴팁·상세용) — 대수(제n대)와 이름 번호(n세)를 함께: "제12대 서리 3세 (별명 얼음손 · 지위 왕)" */
  HT.leaderFull = (c, words) => {
    const names = HT.leaderFacts(c, words);
    if (c.rank || c.rankAuto) names.push(`지위 ${c.rank || c.rankAuto}`); // 지위: 적은 것, 없으면 시작한 해의 정권 지위(모델이 채운 rankAuto)
    return `${c.ordinal != null ? `제${c.ordinal}대 ` : c.ordinalUnknown ? '대수 미상 · ' : ''}${c.name}${c.regnal != null ? ` ${c.regnal}세` : ''}${names.length ? ` (${names.join(' · ')})` : ''}`;
  };
  /* 지도자 표기 낱말의 출처(마지막으로 지은 모델 — HT.buildModel): 팩 id → 팩의 leaderLabels. 문화권의 것은 문화권 사전(HT.sphereOf · model.sphereMap)에 */
  let LEADER_LABEL_MAP = new Map();
  let LEADER_TRACK_SPHERE = new Map();
  /** 지도자 표기 낱말 { temple, title, given } — 트랙의 문화권(spheres[].leaderLabels) → 그 항목을 적은 팩(최상위 leaderLabels) → 기본 낱말 차례로 칸마다.
      x = 모델 항목(track · packId — 정권) 또는 트랙 id. model을 주면 그 모델의 트랙 · 문화권 · 팩 표를, 비우면 마지막으로 지은 모델의 것을 봅니다 */
  HT.leaderWords = (x, model) => {
    const item = x && typeof x === 'object' ? x : null;
    const trackId = item ? item.track : x;
    const t = model && model.trackMap ? model.trackMap.get(trackId) : null;
    const sid = model && model.trackMap ? (t && t.sphere) || '' : LEADER_TRACK_SPHERE.get(trackId) || '';
    const sp = !sid ? null : model && model.sphereMap ? model.sphereMap.get(sid) : HT.sphereOf(sid);
    const map = (model && model.leaderLabelMap) || LEADER_LABEL_MAP;
    const pk = item && item.packId ? map.get(item.packId) : null;
    return Object.assign({}, HT.LEADER_WORDS, pk || null, (sp && sp.leaderLabels) || null);
  };
  /** 모델 전체의 표기 고르기 선택지(필터 바 · 메이커의 '지도자 표기') — HT.LEADER_LABELS의 이름을 모델에서 쓰는 낱말로(지도자가 있는 정권의 낱말 — 서로 다르면 "묘호/치세명") */
  HT.leaderModes = model => {
    const sets = [];
    for (const p of (model && model.periods) || []) {
      if (!p || !p.leaders || !p.leaders.length) continue;
      const w = HT.leaderWords(p, model);
      if (!sets.some(x => x.temple === w.temple && x.title === w.title && x.given === w.given)) sets.push(w);
    }
    if (!sets.length) sets.push(HT.LEADER_WORDS);
    const word = k => [...new Set(sets.map(w => w[k]))].join('/');
    const name = { temple: word('temple'), title: word('title'), given: word('given') };
    return HT.LEADER_LABELS.map(o => (o.id === 'temple-title' ? { id: o.id, name: `${name.temple}·${name.title}` } : name[o.id] ? { id: o.id, name: name[o.id] } : o));
  };
  /** 마지막으로 지은 모델의 표기 낱말 출처를 둡니다(HT.buildModel — HT.useSpheres와 같은 길) */
  HT.useLeaderLabels = (packs, tracks) => {
    LEADER_LABEL_MAP = new Map((packs || []).filter(p => p && p.leaderLabels).map(p => [p.id, p.leaderLabels]));
    LEADER_TRACK_SPHERE = new Map([...(tracks || [])].map(t => [t.id, t.sphere || '']));
    return LEADER_LABEL_MAP;
  };

  /* ---------- 칸 종류 표 ----------
   * 정권에 딸린 '칸'(기간이 있는 작은 항목: 지도자 · 내각 · 연호 · 도읍)의 종류를 한 곳에 적습니다.
   * 문서 키(HT.docKey)의 칸 종류 · 뷰어의 칸 참조('leader:3')와 칸 상세 · 검색의 칸 찾기 · 폼의 줄 채우기가 모두 이 표를 봅니다.
   * 새 종류는 표 아래에 한 줄로 더합니다: HT.CELL_KINDS.push({ id, list, name, … })
   *   id    칸 참조의 종류('leader:3'의 leader — 연표의 data-cell · 뷰어의 상세 · 조명이 씀)
   *   list  정권 항목에 달린 목록 열쇠(p.leaders …) — 문서 키의 종류 글자이기도 합니다("cell:uid:leaders:이름@시작")
   *   name  이름표 · unit 세는 말 — 칸 창은 이름 아래 날짜만(앞말 없이), 사건 목록은 모두 '이 시기의 사건'이라 칸 종류마다 기간 낱말을 두지 않습니다
   *         (어느 체제의 칸이든 같은 모양 — 특정 체제에만 맞는 낱말을 쓰지 않게)
   *   doc   false면 문서를 달지 않는 종류(문서 키 · [[이름]] 찾기에서 빠지고, 상세에 📄 단추가 없음)
   *   title(c, { leaderMode }) 제목 · full(c) 검색 결과의 긴 이름 · tag(c) 이름표 뒤에 붙는 말 · facts(c) 제목 아래 한 줄에 적는 것들
   *   items(p)  목록이 p[list]가 아닌 종류가 제 칸들을 돌려주는 함수 (순번 = 칸 참조의 번호) */
  HT.CELL_KINDS = [
    {
      id: 'leader', list: 'leaders', name: '지도자', unit: '명',
      title: (c, o = {}) => HT.leaderLabel(c, o.leaderMode || 'auto'),
      full: (c, words) => HT.leaderFull(c, words),
      tag: c => (c.ordinal != null ? `제${c.ordinal}대` : c.ordinalUnknown ? '대수 미상' : ''),
      facts: (c, words) => HT.leaderFacts(c, words), // 낱말은 그 정권의 표기 낱말(HT.leaderWords — 6단계 D3)
    },
    { id: 'cabinet', list: 'cabinets', name: '내각', unit: '개', title: c => c.name },
    { id: 'era', list: 'eras', name: '연호', unit: '개', title: c => c.name },
    {
      id: 'capital', list: 'capitals', name: '도읍', unit: '곳', title: c => c.name,
      tag: c => (c.role && c.role !== 'main' ? HT.capitalRoleName(c.role) : ''),
      facts: c => [`역할 ${HT.capitalRoleName(c.role || 'main')}`, c.as && c.as !== c.city ? `도시 ${c.city}` : '', c.label ? `시기 이름 ${c.label}` : '', c.group ? `묶음 ${c.group}` : ''].filter(Boolean),
    },
  ];
  /** 칸 종류 하나 — id('leader')로도 목록 열쇠('leaders')로도 찾습니다 (없으면 null) */
  HT.cellKind = key => HT.CELL_KINDS.find(k => k.id === key || k.list === key) || null;
  /** 그 정권의 그 종류 칸들 (순번이 곧 칸 참조의 번호 — 연표 · 뷰어 · 검색이 같은 배열을 봅니다) */
  HT.cellsOf = (p, kind) => {
    const K = typeof kind === 'string' ? HT.cellKind(kind) : kind;
    const list = !K || !p ? null : K.items ? K.items(p) : p[K.list];
    return Array.isArray(list) ? list : [];
  };
  /** 칸 하나만 보고 정한 구간 { start, startAt, end, endAt, hi, exact } — 이웃 칸은 보지 않습니다(HT.cellSpan이 칸의 경계 HT.cellBounds로 다듬음).
      hi = 그 칸이 품는 마지막 순간: 연도만 적은 끝은 그해 끝까지(HT.endBound), 다만 다음 칸의 시작에서 끌어낸 끝(도읍의 endYNext · 칸의 미정 endAuto ·
      시기 · 지위의 endAuto)은 다음 칸이 시작하는 순간 그대로(exact — 그 끝은 사람이 적은 "그해까지"가 아님). 정권의 끝으로 채웠으면(endPolity) 그해 끝까지 */
  const rawCellSpan = (c, p) => {
    const sp =
      c.end != null
        ? { start: c.start, startAt: c.startAt, end: c.end, endAt: c.endAt }
        : c.endY != null
          ? { start: c.start, startAt: c.startAt, end: c.endY, endAt: c.endYAt }
          : { start: c.start, startAt: c.startAt, end: p.endY, endAt: HT.atOf(p, 'end') };
    sp.exact = !!((c.end == null && c.endYNext) || (c.endAuto && !c.endPolity));
    sp.hi = sp.exact ? sp.end : HT.endBound(sp.end, sp.endAt);
    return sp;
  };
  /** 칸이 연표에 놓이는 구간 { start, startAt, end, endAt, lo, hi } — 끝을 비운 칸은 풀어 둔 끝(도읍의 endY: 다음 정도까지)이나 정권의 끝까지.
      start · end는 적힌(연표에 그려진) 자리 그대로 — 기간 글 · 칸 그림이 씁니다.
      [lo, hi) = 그 칸이 품는 구간(칸 조명 · 그 시기의 사건 · 이 시기의 인물 · "이 시기로"): 칸의 경계(HT.cellBounds — 이웃 칸과 겹치지 않게, 경계 해는 뒤 칸의 것)가 있으면 그것,
      이어받는 칸이 없으면 lo = 시작 · hi = 연도만 적은 끝은 그해 끝까지(HT.endBound — 다음 칸의 시작에서 끌어낸 끝은 그 순간까지).
      ref = 칸 참조('leader:3') — 주지 않으면 그 정권의 칸 목록에서 같은 칸을 찾습니다(HT.cellRefOf). 모델을 만드는 도중(경계를 채우기 전)에는 이웃을 보지 않은 값.
      칸의 미정: 모델이 자리를 잡아 둔 값(HT.placeCells · HT.resolveCapitals)을 그대로 씀. 모델 전용 목록인 칸(시기 · 지위 — items로 돌려주는 경계를 채운 사본)도 같은 길 */
  HT.cellSpan = (c, p, ref) => {
    const sp = rawCellSpan(c, p);
    const b = HT.cellBound(p, ref === undefined ? HT.cellRefOf(p, c) : ref);
    sp.lo = b ? b.lo : sp.start;
    if (b) sp.hi = b.hi;
    delete sp.exact;
    return sp;
  };
  /** 칸의 끝이 진행 중인 정권의 끝(오늘)까지인지 — 끝을 비워 정권의 끝으로 채운 칸(지도자 · 내각 · 연호, 다음 정도가 없는 도읍, 시기 · 지위의 endPolity).
      그런 칸의 기간 글은 끝을 "현재"로 적습니다(계산된 오늘의 해를 끝난 해처럼 적지 않게 — HT.formatRange의 ongoing). 칸의 미정 · 짐작한 끝은 그대로 "미정" */
  HT.cellToNow = (c, p) => !!(p && p.ongoing && c && !c.endUnknown && !c.endYAuto && (c.endPolity || (c.end == null && !c.endYNext)));

  /* ---------- 칸의 경계 (이웃 칸끼리 상호배타 — 경계 해는 뒤 칸의 것) ----------
   * 칸이 품는 구간 [lo, hi)를 이웃 칸과 겹치지 않게 정합니다. 칸 조명 · 그 시기의 사건(연표의 강조도) · 이 시기의 인물 · 같은 시기의 지도자 ·
   * 줄 이름표의 그때 지도자 · 지위 · 같은 해 보기의 시기 · 지위가 모두 이 값을 봅니다(HT.cellSpan의 lo · hi, HT.cellBound).
   * 이설(칸의 다른 견해)과 타국 메아리도 자리를 따로 셈하지 말고 이 함수들을 씁니다 — 칸 무리 하나는 HT.chainBounds(순수 함수), 정권 하나는 HT.cellBounds.
   *
   * 서로 이어받는 칸 무리(HT.cellChains): 지도자 · 내각 · 연호는 목록마다 하나, 도읍은 정도 · 망명 · 임시끼리(공동 정도 · 배도는 나란히 가므로 뺌),
   *   시기는 체계마다, 지위는 하나. 왕조는 넣지 않습니다(왕조 칸의 그림과 조명이 이미 적힌 값 그대로라 서로 맞음).
   * 규칙 — 앞 칸 A의 끝이 덮는 단위(연도만 → 그해, 달까지 → 그달, 날까지 → 그날: HT.cal.precSpan)와 다른 칸 B의 시작이 덮는 단위가 겹치면
   *   둘은 같은 경계를 적은 것으로 봅니다:
   *   ㉠ 경계 = 두 단위가 겹친 곳의 처음 — 연도만 둘이면 그해 1월 1일(경계 해는 뒤 칸의 것 — 연표의 칸 그림과 같은 자리 · 시작한 해로 하는 짐작과 같은 말),
   *      한쪽에만 날짜가 있으면 날짜가 이김(뒤 칸의 시작 날짜면 그 순간, 앞 칸의 끝 날짜면 그날 0시 — HT.endBound와 같은 뜻).
   *      날짜(달 · 날)로 적은 끝과 뒤 칸의 시작이 겹치지 않고 맞닿으면(24일에 끝 · 25일에 시작 — 끝 단위의 끝 = 시작 단위의 처음) 경계는 뒤 칸의 시작:
   *      끝난 날(달)까지 앞 칸의 것(그 날이 어느 칸에도 들지 않는 틈이 없게 — 칸 그림은 적힌 그대로).
   *   ㉡ B가 A의 끝 단위보다 먼저 시작했으면(공동 통치 · 섭정 · 대립처럼 일부러 겹치게 적은 칸) 경계가 아니라 적힌 그대로 겹칩니다.
   *      시작이 같은 두 칸도 A의 끝 단위와 B의 시작 단위가 겹치지 않으면(둘 다 여러 해) 그대로.
   *   ㉢ 같은 해에 여러 칸이 시작하면 늘이지 않음 — 그해에 시작해 그해에 끝난 칸은 적힌 그대로 폭 0(연표에도 그려지지 않음), 그해는 뒤에 이어 가는 칸의 것.
   *      그해에 시작해 그해에 끝난 칸끼리는 서로를 뒤 칸으로 삼지 않고 한쪽으로만 잇습니다(시작이 이른 쪽 → 늦은 쪽, 같으면 목록 차례) —
   *      이어 가는 칸이 없으면(정권 마지막 해에 한 해짜리 칸 둘) 그해에 시작한 칸 가운데 마지막 칸이 그해를 가집니다(그해가 어느 칸에도 들지 않는 일이 없게).
   *   ㉣ 잘라서 칸이 거꾸로 되는 것은 경계로 보지 않음. 이어받는 칸이 없으면 지금처럼(연도만 적은 끝은 그해 끝까지 — 포함식 1450 → 1451도 그대로).
   *   임시 도읍이 끝나면 정도가 적힌 끝(연표의 칸이 다시 시작하는 자리)에서 이어 가므로, 정도가 그 뒤로도 이어지면 임시 도읍의 끝도 그 자리까지.
   * 모델이 buildModel 맨 끝(가문 잇기가 칸을 복사한 뒤)에 정권마다 p.cellBounds(칸 참조 'leader:3' · 'phase:ci' · 'rank:i' → { lo, hi, prev, next })를
   *   모델 안에서만 쓰는 값으로 둡니다(열거되지 않는 속성 — 팩 · 내보내기 · 복사본에 섞이지 않음). 칸 그림은 바꾸지 않습니다(적힌 값 그대로 — 이미 경계에서 맞닿음) */
  /** 적힌 값이 덮는 단위 [처음, 끝) — 날짜 글이 값과 맞으면 그 자세함, 없으면 정수는 그해, 소수(계산된 값)는 그 한 점 [t, t]. exact면 한 점 */
  const unitOf = (t, at, exact) => {
    if (t == null || !isFinite(t)) return null;
    if (exact || !HT.cal) return [t, t];
    const r = HT.cal.parse(at && atFits(at, t) ? at : t);
    const sp = HT.cal.precSpan(r);
    return sp && sp[1] > sp[0] ? sp : [t, t];
  };
  HT.unitOf = unitOf;
  /** 두 단위가 겹치는가 — 한 점 단위는 [t, t]로 닫힌 한 점 */
  const unitsMeet = (U, V) => {
    const pu = U[0] === U[1];
    const pv = V[0] === V[1];
    if (pu && pv) return U[0] === V[0];
    if (pu) return V[0] <= U[0] && U[0] < V[1];
    if (pv) return U[0] <= V[0] && V[0] < U[1];
    return U[0] < V[1] && V[0] < U[1];
  };
  /**
   * 칸 무리 하나의 경계 (순수 함수 — 모델 · 이설 · 메아리가 함께 씀).
   * list = [{ start, startAt, end, endAt, hi, exact }] (hi = 그 칸만 보고 정한 끝 — 연도만 적은 끝은 그해 끝까지, exact = 끝이 다음 칸의 시작에서 끌어낸 한 순간)
   * → 같은 차례로 [{ lo, hi, prev: [앞 칸 번호], next: [뒤 칸 번호] }] (위 규칙 ㉠ ~ ㉣)
   */
  HT.chainBounds = list => {
    const n = list.length;
    const out = list.map(s => ({ lo: s.start, hi: Math.max(s.start, s.hi), prev: [], next: [] }));
    const U = list.map(s => (s.virtual ? null : unitOf(s.end, s.endAt, s.exact))); // 끝 단위
    const V = list.map(s => unitOf(s.start, s.startAt, false)); // 시작 단위
    const found = [];
    for (let i = 0; i < n; i++)
      for (let j = 0; j < n; j++) {
        if (i === j || !U[i] || !V[j]) continue;
        let m;
        if (unitsMeet(U[i], V[j])) m = Math.max(U[i][0], V[j][0]);
        else if (U[i][1] > U[i][0] && U[i][1] - U[i][0] < 0.5 && Math.abs(U[i][1] - V[j][0]) < 1e-7) m = V[j][0]; // ㉠ 날짜로 적은 끝과 맞닿은 시작 — 끝난 날까지 앞 칸
        else continue;
        if (m < list[i].start || m > out[j].hi) continue; // ㉣ 자르면 앞 칸이나 뒤 칸이 거꾸로 됨 — 경계가 아님
        found.push([i, j, m]);
      }
    /* ㉢ 서로를 뒤 칸으로 삼는 짝(같은 해에 시작해 그해에 끝난 칸끼리)은 한쪽으로만 — 시작이 이른 쪽에서 늦은 쪽으로, 같으면 목록 차례 */
    const seen = new Set(found.map(([i, j]) => i * n + j));
    const first = (i, j) => list[i].start < list[j].start || (list[i].start === list[j].start && i < j);
    const pairs = found.filter(([i, j]) => !seen.has(j * n + i) || first(i, j));
    for (const [i, j, m] of pairs) {
      out[j].lo = Math.max(out[j].lo, m);
      out[j].prev.push(i);
      out[i].next.push(j);
    }
    /* 앞 칸의 끝 = 뒤 칸들이 실제로 시작하는 곳 가운데 가장 이른 곳 (뒤 칸의 시작이 앞 칸의 끝 날짜로 밀렸으면 그 자리 — 한쪽만 날짜여도 틈 · 겹침 없이) */
    const cut = new Array(n).fill(Infinity);
    for (const [i, j, m] of pairs) cut[i] = Math.min(cut[i], out[j].lo, Math.max(out[i].hi, m));
    out.forEach((b, i) => {
      if (cut[i] < Infinity) b.hi = cut[i];
      if (b.hi < b.lo) b.hi = b.lo;
    });
    return out;
  };
  /** 정권 p의 서로 이어받는 칸 무리 [[{ ref, c, sp }]] — 무리마다 경계를 따로 셈합니다(HT.cellBounds). 새 칸 종류는 여기에 무리를 더합니다 */
  HT.cellChains = p => {
    const out = [];
    const items = (kind, keep) =>
      HT.cellsOf(p, kind)
        .map((c, i) => ({ ref: `${kind}:${i}`, c }))
        .filter(x => x.c && x.c.start != null && isFinite(x.c.start) && (!keep || keep(x.c)))
        .map(x => Object.assign(x, { sp: rawCellSpan(x.c, p) }));
    /* 나라 경계(승계 이음매): 후대가 이 나라가 끝나는 단위(연도만이면 그해)에 시작하면 그해는 후대의 것 — 칸끼리의 규칙 ㉠을 나라 사이에도(곧바로 이어지는 승계 쌍의
       앞 나라 마지막 칸이 후대의 첫해를 가지지 않게: 칸 조명 · 타국 메아리 · 그 시기의 사건이 이음매에서 1년 겹치지 않음). 무리마다 후대의 시작을 '뒤 칸'(virtual · ref 없음)으로 덧붙임 —
       그 단위에 끝나는 칸만 잘리고(날짜로 적어 겹치지 않으면 그대로 — ㉠ · ㉡), 끝이나 시작이 미정 · 연대 폭이면 잇지 않음(연표의 이음매 조건 chainRows와 같게) */
    const endU = p.endUnknown || p.endRange || p.ongoing ? null : unitOf(p.endY, HT.atOf(p, 'end'), false);
    const seats = !endU
      ? []
      : (p.successors || [])
          .map(e => e && e.to)
          .filter(q => q && q !== p && !q.startUnknown && !q.startRange && q.start != null && isFinite(q.start) && unitsMeet(endU, unitOf(q.start, HT.atOf(q, 'start'), false)))
          .map(q => ({ ref: null, c: null, to: q, sp: { start: q.start, startAt: HT.atOf(q, 'start'), end: q.start, hi: q.start, virtual: true } }));
    const push = g => (g.length > 1 || (g.length && seats.length)) && out.push(seats.length ? g.concat(seats) : g);
    for (const k of ['leader', 'cabinet', 'era']) push(items(k));
    /* 도읍: 정도 · 망명 · 임시끼리. 임시 도읍이 끝나면 정도가 그 끝에서 다시 이어지므로(연표의 칸 그림 — 개경 | 강화 | 개경), 그 뒤로도 이어지는 정도가 있으면
       그 자리에 '다시 시작하는 정도'를 덧붙여 임시 도읍의 끝이 그것과 경계를 이루게 합니다(ref 없음 — 결과에는 남기지 않음) */
    const caps = items('capital', c => ['main', 'exile', 'temporary'].includes(c.role || 'main'));
    for (const t of caps.filter(x => x.c.role === 'temporary' && !x.sp.exact)) {
      const e = t.sp.end;
      const seat = caps.find(x => x !== t && x.c.role !== 'temporary' && x.c.start < e && e < x.sp.end);
      if (seat) caps.push({ ref: null, c: seat.c, sp: Object.assign({}, seat.sp, { start: e, startAt: t.sp.endAt, virtual: true }) });
    }
    push(caps);
    const phases = items('phase');
    for (const si of new Set(phases.map(x => x.c.si))) push(phases.filter(x => x.c.si === si));
    push(items('rank'));
    return out;
  };
  /** 정권 p의 칸 경계 — Map(칸 참조 → { lo, hi, prev: [칸 참조], next: [칸 참조], succ: [끝을 자른 후대 정권] }). 이어받는 칸이 없는 칸은 넣지 않습니다(HT.cellSpan이 칸 하나만 보고 정함) */
  HT.cellBounds = p => {
    const map = new Map();
    for (const g of HT.cellChains(p)) {
      const b = HT.chainBounds(g.map(x => x.sp));
      g.forEach((x, k) => {
        if (!x.ref) return;
        map.set(x.ref, { lo: b[k].lo, hi: b[k].hi, prev: b[k].prev.map(j => g[j].ref).filter(Boolean), next: b[k].next.map(j => g[j].ref).filter(Boolean), succ: b[k].next.map(j => g[j].to).filter(Boolean) }); // succ = 끝을 자른 후대 나라(나라 경계)
      });
    }
    return map;
  };
  /** 모델이 채워 둔 칸 하나의 경계 { lo, hi, prev, next } (없으면 null — 모델을 만드는 도중이거나 이어받는 칸이 없는 무리) */
  HT.cellBound = (p, ref) => (p && ref && p.cellBounds ? p.cellBounds.get(ref) || null : null);
  /** 칸 객체 → 그 정권의 칸 참조('leader:3') — 모델의 칸 목록에 있는 그 칸이어야 합니다(복사본이면 null) */
  HT.cellRefOf = (p, c) => {
    if (!p || !c) return null;
    for (const K of HT.CELL_KINDS) {
      const i = HT.cellsOf(p, K).indexOf(c);
      if (i >= 0) return `${K.id}:${i}`;
    }
    return null;
  };
  /** 구간 [a, b)가 [lo, hi)에 걸치는가 — 폭 0인 쪽은 한 점으로(그 점이 다른 쪽 안에 들면 걸침). 활동 기록 · 칸끼리 · 같은 해 보기가 씀 */
  HT.spanMeets = (a, b, lo, hi) => {
    if (!(b > a)) return hi > lo ? lo <= a && a < hi : a === lo;
    if (!(hi > lo)) return a <= lo && lo < b;
    return a < hi && lo < b;
  };
  /** 항목(사건 …)이 칸의 구간 [lo, hi)에 걸치는가 — 칸의 경계와 짝.
      기간이 있는 항목은 [시작, 끝이 덮는 단위의 끝), 한 단위뿐인 항목(연도만 적은 '1988' · 날짜 하나 · 시작과 끝이 같은 단위)은 그 단위의 한가운데 한 점으로 봅니다 —
      경계 해의 연도만 적은 사건이 앞뒤 두 칸의 목록에 모두 들지 않게(날짜로 나뉜 해면 그해 한가운데 날이 속한 쪽에만). 진행 중이면 오늘까지 */
  HT.spanHit = (x, lo, hi) => {
    const S = unitOf(x.start, x.startAt, false);
    if (!S) return false;
    const E = x.ongoing ? [x.endY, x.endY] : x.end != null ? unitOf(x.end, x.endAt, false) : null;
    if (!E || (E[0] === S[0] && E[1] === S[1])) {
      const t = (S[0] + S[1]) / 2;
      return HT.spanMeets(t, t, lo, hi);
    }
    return HT.spanMeets(S[0], Math.max(S[0], E[1]), lo, hi);
  };

  /* ---------- 같은 시기 타국 (조명 메아리 — 설정 '같은 시기를 타국에도') ----------
   * 칸 · 시기 · 지위 · 왕조 · 인물 창이 연표에 켜는 조명(spots = [{ uid: 정권, start, end }] — 칸이면 칸의 경계 [lo, hi))을 한 번에 셈합니다.
   * 연표의 칠(timeline.js _drawTrack)과 강조, 창의 '이 시기의 사건' · '같은 시기 타국' 묶음이 모두 이 결과 하나를 씁니다 — 창과 연표가 같은 답.
   * 띠마다 칠과 같은 식: 메아리 기간(겹치는 조명은 하나로) − 그 띠의 제 조명 → 그 띠가 있던 구간으로 자름(HT.echoBandSpans). 사건은 그려지는 띠의 그 구간에 걸리면(HT.spanHit — 칸의 경계와 짝) 메아리.
   *   제 것: 사건이 놓인 정권(함께 겪은 자리 placements 가운데 하나)이 조명의 정권이거나, 그 정권의 띠 아래 접혀 숨은 소속이면(연표에서 그 띠 안에 그려짐) — 제 조명 구간에 걸리면.
   *   정권이 없는 사건(트랙의 공통 줄)은 띠도 칠도 없으므로 메아리 기간 전체로 봅니다 · 접힌 트랙 · 접힌 줄의 정권은 묶음에 folded(연표에는 그려지지 않음).
   *   여러 자리에 놓인 사건은 한 번만: 제 것이 하나라도 있으면 제 목록, 아니면 주 자리(없으면 처음 걸린 자리)의 묶음에 '함께' 이름을 달아.
   *   하위 사건은 부모가 같은 묶음 목록에 있으면 부모 줄의 '포함 n'으로 셉니다. 묶음 차례는 연표 위에서 아래로(bandOf의 order).
   * bandOf(정권 uid) → { band: 그려지는 띠의 정권 uid, start, end: 그 띠의 구간, order, drawn, folded, hidden: 다른 띠 아래 숨었나, name, color, track } 또는 null(연표에 띠가 없음 — timeline.echoBands) */
  /** 조명들의 메아리 기간 — 겹치거나 맞닿은 조명은 하나로 [[시작, 끝]] (연표 맨 위의 가는 괄호도 이 구간) */
  HT.echoSpans = spots => {
    const out = [];
    for (const s of (spots || []).filter(s => s && isFinite(s.start) && isFinite(s.end)).sort((a, b) => a.start - b.start)) {
      const last = out[out.length - 1];
      if (last && s.start <= last[1]) last[1] = Math.max(last[1], s.end);
      else out.push([s.start, s.end]);
    }
    return out;
  };
  /** 띠 하나의 메아리 구간 — 메아리 기간에서 그 띠의 제 조명(own = [[시작, 끝]])을 빼고(두 번 칠하지 않게), 띠가 있던 구간 [bs, be]로 자른 것 */
  HT.echoBandSpans = (spans, own, bs = -Infinity, be = Infinity) => {
    let out = spans || [];
    for (const [s, e] of own || []) out = out.flatMap(([a, b]) => (e <= a || s >= b ? [[a, b]] : [[a, Math.min(b, s)], [Math.max(a, e), b]].filter(([u, v]) => v > u)));
    return out.map(([a, b]) => [Math.max(a, bs), Math.min(b, be)]).filter(([a, b]) => b > a);
  };
  /**
   * → { spans: 메아리 기간, own: [{ e, member: 숨은 소속 이름('' = 조명의 정권 제 것) }](시작 차례), ownUids: Set,
   *     echo: Set(사건 uid), echoKeys: Set('uid:자리 번호' — 연표의 점 하나하나), groups: [{ key, band(bandOf의 값 · 없으면 null), track, order, folded, rows: [{ e, pi, with: [함께 겪은 다른 자리 이름], kids }] }], count: 줄 수 }
   * echo가 거짓이면 제 것만 셉니다(메아리 없음). events는 보이는 사건(필터 반영), trackShown(트랙 id) = 연표에 그 트랙이 있나(띠가 없는 자리 — 꺼 둔 트랙으로 함께 겪은 자리는 뺌)
   */
  HT.echoEvents = ({ events = [], spots = [], echo = false, bandOf = () => null, trackOrder = () => 0, trackShown = () => true } = {}) => {
    spots = (spots || []).filter(s => s && s.uid && isFinite(s.start) && isFinite(s.end));
    const spans = echo ? HT.echoSpans(spots) : [];
    const bandKey = uid => {
      const b = uid ? bandOf(uid) : null;
      return b ? b.band : uid;
    };
    const ownOnBand = new Map(); // 띠 → 그 띠의 제 조명 구간
    for (const s of spots) {
      const k = bandKey(s.uid);
      if (!ownOnBand.has(k)) ownOnBand.set(k, []);
      ownOnBand.get(k).push([s.start, s.end]);
    }
    const bandSpans = new Map();
    const echoOf = b => {
      if (!spans.length) return [];
      if (!b) return spans;
      if (!bandSpans.has(b.band)) bandSpans.set(b.band, HT.echoBandSpans(spans, ownOnBand.get(b.band), b.start, b.end));
      return bandSpans.get(b.band);
    };
    /* 걸릴 수 없는 사건은 먼저 거릅니다 — 조명 · 메아리 구간 전체의 [처음, 끝] 밖 */
    const all = spots.map(s => [s.start, s.end]).concat(spans);
    const lo = all.length ? Math.min(...all.map(r => r[0])) : Infinity;
    const hi = all.length ? Math.max(...all.map(r => r[1])) : -Infinity;
    const own = [];
    const ownUids = new Set();
    const rows = new Map(); // 사건 uid → 메아리 줄
    const echoKeys = new Set();
    for (const e of events) {
      if (!e || e.kind !== 'event' || e.start == null || e.start > hi || (e.endY ?? e.start) + 1 < lo) continue;
      const places = e.placements && e.placements.length ? e.placements : [{ track: e.track, polityUid: e.polityUid, polityName: e.polityName }];
      let mine = null;
      const hits = [];
      places.forEach((pl, pi) => {
        const P = pl.polityUid || null;
        const b = P ? bandOf(P) : null;
        for (const s of spots) {
          if (mine) break;
          if ((P === s.uid || (b && b.hidden && b.band === s.uid)) && HT.spanHit(e, s.start, s.end)) mine = { member: P === s.uid ? '' : pl.polityName || '' };
        }
        if (!mine && spans.length && (b || trackShown(pl.track || e.track)) && echoOf(b).some(([a, c]) => HT.spanHit(e, a, c))) hits.push({ pl, pi, b }); // 띠가 없는 자리는 보이는 트랙의 공통 줄일 때만(꺼 둔 트랙의 자리는 연표에 없음)
      });
      if (mine) {
        own.push({ e, member: mine.member });
        ownUids.add(e.uid);
        continue;
      }
      if (!hits.length) continue;
      for (const h of hits) echoKeys.add(`${e.uid}:${h.pi}`);
      const at = hits.find(h => h.pi === 0) || hits[0];
      const name = pl => pl.polityName || pl.track || '';
      rows.set(e.uid, { e, pi: at.pi, at, with: places.filter((pl, pi) => pi !== at.pi).map(name).filter(Boolean), kids: 0 });
    }
    /* 하위 사건: 부모가 목록에 있으면 부모 줄에 셈 */
    for (const [uid, r] of rows) {
      const p = r.e.parentUid ? rows.get(r.e.parentUid) : null;
      if (p && p !== r) {
        p.kids++;
        rows.delete(uid);
      }
    }
    const groups = new Map();
    for (const r of rows.values()) {
      const { b, pl } = r.at;
      const key = b ? `b:${b.band}` : `t:${pl.track || r.e.track}`;
      if (!groups.has(key)) {
        const track = b ? b.track : pl.track || r.e.track;
        groups.set(key, { key, band: b || null, track, order: b ? b.order : trackOrder(track) + 0.999, folded: !!b && !!b.folded, rows: [] });
      }
      delete r.at;
      groups.get(key).rows.push(r);
    }
    const list = [...groups.values()].sort((a, b) => a.order - b.order || HT.cmp16(String(a.key), String(b.key)));
    for (const g of list) g.rows.sort((a, b) => a.e.start - b.e.start || (b.e.importance || 2) - (a.e.importance || 2));
    own.sort((a, b) => a.e.start - b.e.start);
    const echoUids = new Set();
    for (const k of echoKeys) echoUids.add(k.slice(0, k.lastIndexOf(':')));
    return { spans, own, ownUids, echo: echoUids, echoKeys, groups: list, count: list.reduce((n, g) => n + g.rows.length, 0) };
  };

  /* ---------- 칸의 미정 ----------
   * 칸(지도자 · 내각 · 연호 · 도읍, 소속 기간 …)의 시작 · 끝에도 "미정"(HT.isUnknownText — 불명 · 모름 · ?도)을 적을 수 있습니다. 시대의 미정과 같은 말투:
   *   파일에 남는 꼴 = startUnknown: true (+ 배치용 연도가 있으면 start 숫자) · endUnknown: true (+ end 숫자). 읽을 때는 "미정" 글과 startHint · endHint도 받습니다.
   *   비운 끝 = "거기까지가 맞음", 미정 = "모름" — 자리는 같아도 뜻이 다릅니다.
   * 모델이 배치용 연도가 없는 쪽의 자리를 잡습니다(HT.placeCells — 도읍은 HT.resolveCapitals): 시작 = 앞 칸의 끝(그것도 비었으면 앞 칸의 시작과
   *   이 칸의 끝 — 끝도 없으면 다음 칸의 자리 — 사이 가운데) → 정권의 시작, 끝 = 다음 칸의 시작 → 정권의 끝.
   *   앞뒤로 이어 붙이는 것은 이어지는 칸(HT.CELL_CHAIN · 정도)과 차례로 예속된 시대의 소속뿐 — 왕조의 polities · 기관의 host는 나란히 갈 수 있어 미정인 쪽을 비운 쪽처럼 둡니다.
   * 짐작한 값은 start · end에 넣고 startAuto · endAuto로 표시합니다 — 폼 · 내보내기 비교 · HT.normalizeCapital은 표시가 붙은 값을 없는 것으로 봅니다 (짐작이 자료로 굳지 않게) */
  /** 칸 한쪽 끝(key = 'start' | 'end') 읽기 → null(비움) · { unknown: true, t: 배치용 연도 | null } · HT.readDate의 { t, at, error } */
  HT.readCellEdge = (c, key) => {
    if (!c) return null;
    const raw = c[key];
    if (c[`${key}Unknown`] === true || HT.isUnknownText(raw)) {
      const hint = [c[`${key}Hint`], c[`${key}Auto`] || HT.isUnknownText(raw) ? null : raw].map(v => (v == null || v === '' ? NaN : HT.parseYear(v))).find(v => !isNaN(v));
      return { unknown: true, t: hint ?? null };
    }
    return HT.readDate(raw, c[`${key}At`]);
  };
  /** 칸 목록을 시작 순으로 — 시작을 모르면 끝으로(그해에 끝나는 칸이라 같은 해에 시작하는 칸보다 앞에), 둘 다 모르면 적힌 차례에서 앞 칸 바로 뒤에
      (같으면 적힌 차례 그대로 — 시작을 다 아는 목록은 예전 정렬과 같음). 그래서 시작이 미정인 칸을 목록 맨 끝에 적어도 제 끝이 가리키는 자리에 섭니다 */
  HT.sortCells = list => {
    let last = -Infinity;
    return list
      .map((c, i) => {
        const k = c.start ?? c.end;
        const ok = k != null && isFinite(k);
        if (ok) last = k;
        return { c, i, k: ok ? k : last, byEnd: ok && c.start == null ? 0 : 1 };
      })
      .sort((a, b) => a.k - b.k || a.byEnd - b.byEnd || a.i - b.i)
      .map(x => x.c);
  };
  /* 앞 칸의 끝 → 다음 칸의 시작으로 이어지는 칸 목록(정권 항목의 목록 열쇠) — 모델이 이 목록들의 미정 자리를 잡습니다. 새 종류는 한 줄 push (도읍은 HT.resolveCapitals) */
  HT.CELL_CHAIN = ['leaders', 'cabinets', 'eras'];
  /** 시작이 미정인 칸의 자리 (배치용 연도가 없을 때): 앞 칸의 적힌 끝 → (앞 칸의 끝도 비었거나 미정이면) 앞 칸의 시작과 cap 사이 가운데 → 정권의 시작.
      cap(HT.cellStartCap — 이 칸의 끝, 끝도 없으면 다음 칸의 자리)을 넘지 않는 첫 값 — 겹쳐 그려지지 않게 */
  HT.cellStartGuess = (prev, cap, polityStart) => {
    const pe = prev && prev.end != null && !prev.endAuto ? prev.end : null;
    const mid = prev && prev.end == null && prev.start != null && isFinite(cap) && cap > prev.start ? Math.round((prev.start + cap) / 2) : null;
    return [pe, mid, polityStart].find(v => v != null && isFinite(v) && v <= cap) ?? (isFinite(cap) ? cap : polityStart);
  };
  /** 시작이 미정인 칸이 넘지 않을 자리(cap): 이 칸의 끝 → (끝도 없으면) 뒤에 오는 칸(after) 가운데 자리를 아는 첫 칸의 시작(시작도 미정이면 그 끝) → 정권의 끝.
      끝을 비운 앞 칸 뒤에 끝도 없이 오는 칸(가장 흔한 꼴 ["도시", "미정"])이 정권의 시작으로 떨어져 앞 칸과 나란히 놓이지 않고 앞 칸의 시작과 다음 칸 사이 가운데에 놓이게 */
  HT.cellStartCap = (c, after, p) => {
    if (c.end != null) return c.end;
    const n = after.find(m => m && isFinite(m.start ?? m.end ?? NaN));
    return n ? n.start ?? n.end : p.endY ?? p.end ?? Infinity;
  };
  /** 모델의 칸 목록을 파일의 꼴로 — 짐작한 자리(startAuto · endAuto가 붙은 start · end)를 뺍니다. 짐작한 칸이 없으면 목록 그대로 (내보내기 비교가 씀) */
  HT.cellsFileForm = list =>
    Array.isArray(list) && list.some(c => c && (c.startAuto || c.endAuto))
      ? list.map(c => {
          const o = Object.assign({}, c);
          for (const k of ['start', 'end']) {
            if (!o[`${k}Auto`]) continue;
            delete o[k];
            delete o[`${k}Auto`];
          }
          return o;
        })
      : list;
  /** 이어지는 칸 목록에서 미정인 쪽의 자리를 잡습니다 (모델 — buildModel): 배치용 연도가 없으면 시작 = HT.cellStartGuess(앞 칸의 끝 → …),
      끝 = 다음 칸의 시작(없으면 끝을 비운 칸처럼 정권의 끝까지). 미정인 칸이 없으면 목록을 그대로 돌려줍니다(옛 자료는 1px도 같게).
      칸은 복사해서 고치고 시작 순으로 돌려줍니다. 차례로 예속된 시대의 소속 기간(partOf)도 같은 틀 — 그때 정권의 시작은 p.start
      (왕조의 polities · 기관의 host에는 쓰지 않음 — buildModel) */
  HT.placeCells = (list, p) => {
    if (!Array.isArray(list) || !list.some(c => c && (c.startUnknown || c.endUnknown))) return list;
    const out = HT.cellsFileForm(list).map(c => Object.assign({}, c)); // 앞서 짐작한 자리는 버리고 다시 (같은 목록을 두 번 넣어도 같은 자리)
    out.forEach((c, i) => {
      if (!c.startUnknown || c.start != null) return;
      c.start = HT.cellStartGuess(out[i - 1], HT.cellStartCap(c, out.slice(i + 1), p), p.start);
      c.startAuto = true;
    });
    const sorted = HT.sortCells(out);
    sorted.forEach((c, i) => {
      if (!c.endUnknown || (c.end != null && !c.endAuto)) return;
      const next = sorted[i + 1];
      delete c.end;
      delete c.endAuto;
      if (next && next.start != null && next.start > c.start) Object.assign(c, { end: next.start, endAuto: true });
    });
    return sorted;
  };

  /* ---------- 시기 구분(학계) ----------
   * 후대 학계가 한 나라 안을 나눈 시기(앞 시기 · 가운데 시기 · 뒤 시기 …). 출전 · 학설마다 이름도 경계도 다를 수 있어 '체계'를 여럿 둡니다.
   *   periods[].phases = [{ scheme: 체계 이름, note: 메모, spans: [시기 …] }, …] — 시기는 연호와 같은 틀: [이름, 시작, 끝, 메모] 또는 { name, start, end, note }
   *   시작을 비우면 앞 시기의 끝부터(첫 시기는 정권 시작부터), 끝을 비우면 다음 시기가 시작할 때까지(마지막 시기는 정권 끝까지).
   *   "미정"도 적을 수 있습니다(칸의 미정과 같은 규칙 — 배치용 연도가 있으면 그 자리, 없으면 비운 것과 같은 자리이고, 글에 '미정'으로 나옴). 체계가 하나뿐이면 scheme을 비워도 되고,
   *   납작한 꼴 [{ name, start, end, scheme }]도 받아 체계별로(처음 나온 차례대로) 묶습니다.
   * 파일(normalizePack) · 패치 · 폼 · 모델이 모두 HT.readPhases로 같은 꼴을 얻습니다. 모델은 경계를 채운 사본을 p.phaseSchemes에 둡니다
   * (원문 p.phases는 그대로 — 짐작 값은 다른 이름에). 칸 참조는 펼친 순번 하나('phase:3' — 체계 차례대로 이어 센 번호)입니다 */
  HT.CELL_KINDS.push({
    id: 'phase', list: 'phases', name: '시기', unit: '개',
    title: c => c.name,
    full: c => (c.scheme ? `${c.name} (${c.scheme})` : c.name),
    tag: c => c.scheme || '',
    items: p => (p && p.phaseSchemes ? p.phaseSchemes.flatMap(g => g.spans) : []),
  });
  /** 시기 구분 원문 → { list: 정리한 체계 목록, problems: 뺀 것의 글, warnings: 참고할 것의 글(겹침 · 거꾸로 된 끝 …) } */
  HT.readPhases = v => {
    const s = x => (x == null ? '' : String(x).trim());
    const problems = [];
    const warnings = [];
    const groups = [];
    const where = name => (name ? `시기 구분 "${name}"` : '시기 구분');
    const groupOf = (name, note) => {
      let g = groups.find(x => x.scheme === name);
      if (!g) groups.push((g = { scheme: name, note: '', spans: [] }));
      if (note && !g.note) g.note = note;
      return g;
    };
    const readSpan = (c, scheme) => {
      const x = Array.isArray(c) ? { name: c[0], start: c[1], end: c[2], note: c[3] } : c && typeof c === 'object' ? c : null;
      if (!x) {
        problems.push(`${where(scheme)}: 꼴이 올바르지 않은 시기를 뺐습니다.`);
        return null;
      }
      const name = s(x.name ?? x.title);
      if (!name) {
        problems.push(`${where(scheme)}: 이름이 없는 시기를 뺐습니다.`);
        return null;
      }
      const o = { name };
      for (const k of ['start', 'end']) {
        /* 미정: 칸의 미정(HT.readCellEdge)과 같은 규칙 — 배치용 연도(startHint · 숫자와 함께 적은 startUnknown)가 있으면 그 자리에,
           없으면 비운 것과 같은 자리(시작 = 앞 시기의 끝 · 끝 = 다음 시기의 시작 — 앞뒤를 다 모르면 고르게 나눔). 글에는 늘 '미정' */
        const d = HT.readCellEdge(x, k);
        if (d && d.unknown) {
          o[`${k}Unknown`] = true;
          if (d.t != null) o[k] = d.t;
          continue;
        }
        if (d && isNaN(d.t)) {
          problems.push(`${where(scheme)}: 시기 "${name}"의 ${k === 'start' ? '시작' : '끝'}을 읽을 수 없어 그 시기를 뺐습니다.${d.error ? ` (${d.error})` : ''}`);
          return null;
        }
        if (d) {
          o[k] = d.t;
          if (d.at) o[`${k}At`] = d.at;
        }
      }
      if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
        /* 시작만 미정이면(시작은 배치용 연도뿐) 그 배치용 연도를 버리고 적은 끝은 남깁니다 — 지위 변천 · 섬긴 기록 · 인물 활동 시기와 같은 규칙 */
        if (o.startUnknown && !o.endUnknown) {
          warnings.push(`${where(scheme)}: 시기 "${name}"의 끝이 시작보다 앞서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로).`);
          delete o.start;
        } else {
          warnings.push(`${where(scheme)}: 시기 "${name}"의 끝이 시작보다 앞서 끝을 비웠습니다(다음 시기까지로 봄).`);
          delete o.end;
          delete o.endAt;
        }
      }
      if (s(x.note)) o.note = s(x.note);
      Object.assign(o, HT.readUncertain(x, { mode: 'cell', warn: m => warnings.push(`${where(scheme)}: 시기 "${name}" — ${m}`), start: o.start, end: o.end })); // 확실성 · 연대 폭 · 이설 (다른 칸과 같은 읽기)
      return o;
    };
    if (v != null && v !== '' && typeof v !== 'object') problems.push('시기 구분은 목록이어야 해서 무시했습니다.');
    const list = Array.isArray(v) ? v : v && typeof v === 'object' ? [v] : [];
    const seen = new Set();
    for (const x of list) {
      if (x && typeof x === 'object' && !Array.isArray(x) && Array.isArray(x.spans)) {
        const name = s(x.scheme);
        if (seen.has(name)) warnings.push(`${where(name)}: 같은 이름의 체계가 둘이라 하나로 합쳤습니다.`);
        seen.add(name);
        const g = groupOf(name, s(x.note));
        for (const c of x.spans) {
          const sp = readSpan(c, name);
          if (sp) g.spans.push(sp);
        }
      } else {
        const name = x && typeof x === 'object' && !Array.isArray(x) ? s(x.scheme) : '';
        const sp = readSpan(x, name);
        if (sp) groupOf(name, '').spans.push(sp);
      }
    }
    const out = [];
    for (const g of groups) {
      if (!g.spans.length) {
        problems.push(`${where(g.scheme)}: 시기가 하나도 없어 뺐습니다.`);
        continue;
      }
      /* 차례: 적힌 시작 순으로. 시작을 비운 시기는 바로 앞에 적힌 시기 뒤에 그대로 (첫 시기면 맨 앞) */
      let key = -Infinity;
      const spans = g.spans
        .map((sp, i) => ({ sp, i, k: (key = sp.start != null ? sp.start : key) }))
        .sort((a, b) => (a.k === b.k ? 0 : a.k - b.k) || a.i - b.i)
        .map(x => x.sp);
      for (let i = 0; i + 1 < spans.length; i++) {
        const a = spans[i];
        const b = spans[i + 1];
        if ((a.end != null && b.start != null && a.end > b.start) || (a.start != null && a.start === b.start)) warnings.push(`${where(g.scheme)}: 시기 "${a.name}"와(과) "${b.name}"이(가) 겹칩니다.`);
        if (a.end == null && b.start == null) warnings.push(`${where(g.scheme)}: 시기 "${a.name}"의 끝도 "${b.name}"의 시작도 비어 있어, 그 경계는 앞뒤 사이를 고르게 나눠 그립니다.`);
      }
      const o = {};
      if (g.scheme) o.scheme = g.scheme;
      if (g.note) o.note = g.note;
      o.spans = spans;
      out.push(o);
    }
    if (out.length > 1 && out.some(g => !g.scheme)) warnings.push('시기 구분: 체계가 둘 이상이면 체계마다 이름을 적어 주세요 (이름 없는 체계는 이름표 없이 그립니다).');
    return { list: out, problems, warnings };
  };
  /** 모델 전용: 시기의 빈 경계를 채운 사본 [{ scheme, note, si, spans: [{ name, note, scheme, si, ii, ci, start, startAt, end, endAt, startAuto, endAuto, startUnknown, endUnknown, guess, docName }] }] (없으면 null).
      시작을 비우면 앞 시기의 끝 → (첫 시기) 정권 시작, 끝을 비우면 다음 시기의 시작 → (마지막) 정권 끝.
      앞 시기의 끝도 이 시기의 시작도 비어 경계를 알 수 없으면, 알려진 양쪽 사이를 고르게 나눠 자리만 잡습니다(guess — 상세에 짐작이라고 적음) */
  HT.resolvePhases = p => {
    const { list } = HT.readPhases(p && p.phases);
    if (!list.length) return null;
    const P0 = { t: p.start, at: HT.atOf(p, 'start') };
    const P1 = { t: p.endY ?? p.end ?? p.start, at: p.ongoing ? null : HT.atOf(p, 'end') };
    const own = (sp, k) => (sp && sp[k] != null ? { t: sp[k], at: sp[`${k}At`] || null } : null);
    let ci = 0;
    return list.map((g, si) => {
      const n = g.spans.length;
      const st = g.spans.map((sp, i) => own(sp, 'start') || (i === 0 ? P0 : own(g.spans[i - 1], 'end')));
      const en = g.spans.map((sp, i) => own(sp, 'end') || (i === n - 1 ? P1 : own(g.spans[i + 1], 'start')));
      const guess = new Set();
      for (let i = 1; i < n; i++) {
        if (st[i]) continue;
        let j = i;
        while (j + 1 < n && !st[j + 1]) j++;
        const L = st[i - 1].t;
        const R = Math.max(L, en[j].t);
        for (let m = i; m <= j; m++) {
          const t = L + ((R - L) * (m - i + 1)) / (j - i + 2);
          st[m] = en[m - 1] = { t, at: null };
          guess.add(m - 1).add(m);
        }
        i = j;
      }
      const spans = g.spans.map((sp, i) => {
        const a = st[i];
        const b = en[i].t < a.t ? a : en[i];
        return {
          name: sp.name, note: sp.note || '', scheme: g.scheme || '', si, ii: i, ci: ci++,
          start: a.t, startAt: a.at || undefined, end: b.t, endAt: b.at || undefined,
          startAuto: sp.start == null, endAuto: sp.end == null, startUnknown: !!sp.startUnknown, endUnknown: !!sp.endUnknown, guess: guess.has(i),
          endPolity: sp.end == null && b === P1, // 비운 끝을 정권의 끝으로 채움 — HT.cellSpan의 hi가 그해 끝까지 (다음 시기의 시작에서 채운 끝은 그 순간까지)
          docName: g.scheme ? `${g.scheme} · ${sp.name}` : sp.name, // 문서 키의 이름: 체계가 다르면 같은 이름 · 같은 해의 시기도 다른 문서 (HT.docKey.cell)
          ...HT.uncOf(sp), // 확실성 · 연대 폭 · 이설 (디테일 건의 4 — 원문 그대로)
        };
      });
      return { scheme: g.scheme || '', note: g.note || '', si, spans };
    });
  };
  /** 시기 하나의 기간 글: 적힌 것은 그대로, 비워 둔 끝은 어디까지인지, 미정은 '미정'. p(그 정권)를 주면 진행 중인 정권의 끝까지 가는 시기는 끝이 '현재' (HT.cellToNow) */
  HT.phaseRangeText = (c, p) => {
    const side = k => (c[`${k}Unknown`] ? '미정' : k === 'end' && HT.cellToNow(c, p) ? '현재' : HT.formatDate(c[k], c[`${k}At`]));
    return `${side('start')} ~ ${side('end')}`;
  };

  /* ---------- 지위 ----------
   * 정권의 지위(공 → 왕 → 황제 …)와 지도자의 지위. 세 가지를 적습니다.
   *   rankDefs(파일 맨 위, 선택) = 지위 사전 [{ id, name, tier(서열 — 클수록 높음, 비우면 서열 밖), aliases, description }]
   *   periods[].ranks = 지위 변천 — 연호와 같은 칸 목록 [이름, 시작, 끝, 메모] · { name, start, end, note } (읽을 때만 name 대신 rank도 받음).
   *     첫 칸의 시작을 비우면 정권 시작부터, 끝을 비우면 다음 지위가 시작할 때까지(마지막은 정권 끝까지)
   *   leaders[].rank = 그 지도자의 지위(선택)
   * 사전은 켠 DLC들의 것을 id로만 합치고(먼저 정의한 것이 이김) 맨 끝에 내장 사전(HT.RANKS)이 빈 자리만 채웁니다.
   * 지위 이름은 id → 이름 → 별칭 순으로 사전에서 찾고, 사전에 없는 이름도 적을 수 있습니다(서열 없는 지위).
   * 별칭은 서열(짙기)만 빌리고 화면에는 적은 글을 그대로 씁니다. 모델은 끝을 채운 사본을 p.rankSpans에 둡니다(원문 p.ranks는 그대로) */
  /** 내장 지위 사전: 서열 뼈대만 (문화권 고유 칭호와 그 대응은 자료이므로 DLC의 rankDefs에 적습니다) */
  HT.RANKS = [
    { id: 'emperor', name: '황제', tier: 8 },
    { id: 'king', name: '왕', tier: 7, aliases: ['국왕'] },
    { id: 'grand-duke', name: '대공', tier: 6 },
    { id: 'duke', name: '공', tier: 5, aliases: ['공작'] },
    { id: 'marquis', name: '후', tier: 4, aliases: ['후작'] },
    { id: 'count', name: '백', tier: 3, aliases: ['백작'] },
    { id: 'viscount', name: '자', tier: 2, aliases: ['자작'] },
    { id: 'baron', name: '남', tier: 1, aliases: ['남작'] },
    { id: 'president', name: '대통령' },
    { id: 'premier', name: '총리' },
    { id: 'chairman', name: '주석' },
    { id: 'regent', name: '섭정' },
  ];
  /* 지위 칸의 짙기: 사전 전체의 서열을 네 묶음으로 나눈 단계(1 낮음 ~ 4 높음, 0 = 서열 밖) → 나라 색이 섞이는 비율(%).
     같은 지위는 어느 나라에서나 같은 짙기 — 화면(--mix)과 그림 내보내기(toSVG)가 이 표를 함께 씁니다 */
  HT.RANK_MIX = [0, 8, 22, 38, 56];
  /** 지위 사전 원문 → { list, problems, at }. id가 없으면 이름으로 만들고, 같은 id가 또 나오면 뒤의 것을 뺍니다.
      at[k]는 problems[k]가 가리키는 줄의 차례(목록 전체의 것이면 undefined) — 메이커의 검사 창이 그 줄로 갑니다 */
  HT.readRankDefs = v => {
    const s = x => (x == null ? '' : String(x).trim());
    const problems = [];
    const at = [];
    const bad = (i, msg) => {
      problems.push(msg);
      at.push(i);
    };
    const list = [];
    if (v != null && v !== '' && !Array.isArray(v)) bad(undefined, '지위 사전(rankDefs)은 목록이어야 해서 무시했습니다.');
    (Array.isArray(v) ? v : []).forEach((d, i) => {
      if (!d || typeof d !== 'object' || Array.isArray(d)) return bad(i, `지위 사전 #${i + 1}: 형식이 올바르지 않아 뺐습니다.`);
      const name = s(d.name);
      if (!name) return bad(i, `지위 사전 #${i + 1}: 이름이 없어 뺐습니다.`);
      let id = s(d.id);
      if (id && !HT.ID_RE.test(id)) {
        bad(i, `지위 사전 "${name}": id "${id}"가 올바르지 않아 새로 만들었습니다.`);
        id = '';
      }
      if (!id) id = `rank-${HT.hash(name)}`;
      if (list.some(x => x.id === id)) return bad(i, `지위 사전 "${name}": id "${id}"가 중복되어 뺐습니다.`);
      const o = { id, name };
      if (d.tier !== '' && d.tier != null) {
        const t = Number(d.tier);
        if (isFinite(t)) o.tier = t;
        else bad(i, `지위 사전 "${name}": 서열 "${s(d.tier)}"을(를) 읽을 수 없어 서열 밖으로 둡니다.`);
      }
      const aliases = [...new Set((Array.isArray(d.aliases) ? d.aliases : s(d.aliases).split(',')).map(s).filter(a => a && a !== name))];
      if (aliases.length) o.aliases = aliases;
      if (s(d.description)) o.description = s(d.description);
      list.push(o);
    });
    return { list, problems, at };
  };
  /** 모델의 지위 사전: 켠 DLC들의 사전(먼저 정의가 이김 · id로만 합침) → 맨 끝에 내장 사전이 빈 자리만. 항목마다 짙기 단계(level)를 채웁니다 */
  HT.mergeRankDefs = packs => {
    const byId = new Map();
    for (const pack of packs || []) for (const d of (pack && pack.rankDefs) || []) if (d && d.id && !byId.has(d.id)) byId.set(d.id, Object.assign({}, d, { packId: pack.id }));
    for (const d of HT.RANKS) if (!byId.has(d.id)) byId.set(d.id, Object.assign({}, d, { builtin: true }));
    const list = [...byId.values()];
    const tiers = [...new Set(list.map(d => d.tier).filter(t => t != null))].sort((a, b) => a - b);
    for (const d of list) d.level = d.tier == null ? 0 : tiers.length < 2 ? 4 : Math.round((tiers.indexOf(d.tier) * 3) / (tiers.length - 1)) + 1;
    return list;
  };
  /** 사전에서 지위 찾기: id → 이름 → 별칭 (없으면 null) */
  HT.findRank = (defs, ref) => {
    const s = String(ref ?? '').trim();
    if (!s || !Array.isArray(defs)) return null;
    return defs.find(d => d.id === s) || defs.find(d => d.name === s) || defs.find(d => (d.aliases || []).includes(s)) || null;
  };
  /** 지위 변천 원문 → { list: [{ name, start?, startAt?, startUnknown?, end?, endAt?, endUnknown?, note? }], problems: 뺀 것의 글, warnings: 참고할 것의 글 }.
      시작을 비울 수 있는 것은 적은 차례로 첫 칸뿐(정권 시작부터) — 파일(normalizePack) · 패치 · 폼 · 모델이 모두 이 함수로 같은 꼴을 얻습니다.
      시작 · 끝에 "미정"도 됩니다(칸의 미정 — HT.readCellEdge): 파일에 남는 꼴은 다른 칸과 같은 startUnknown/endUnknown + (배치용 연도가 있으면) start/end 숫자.
      시작이 미정인 칸은 첫 칸이 아니어도 됩니다 — 자리는 모델이 잡습니다(HT.resolveRanks → HT.placeCells: 배치용 연도 → 앞 지위의 끝 → …) */
  /* 칸 목록 읽기의 몸(지위 변천 · 종교 — 6단계 D8에서 나눔 · 글의 낱말만 W) */
  const readSpanList = (v, W) => {
    const s = x => (x == null ? '' : String(x).trim());
    const problems = [];
    const warnings = [];
    const out = [];
    if (v != null && v !== '' && !Array.isArray(v)) problems.push(`${W.list}은 목록이어야 해서 무시했습니다.`);
    (Array.isArray(v) ? v : []).forEach((raw, i) => {
      const x = Array.isArray(raw) ? { name: raw[0], start: raw[1], end: raw[2], note: raw[3] } : typeof raw === 'string' ? { name: raw } : raw && typeof raw === 'object' ? raw : null;
      if (!x) return problems.push(`${W.list} ${i + 1}번째 칸: 꼴이 올바르지 않아 뺐습니다.`);
      const name = s(x.name ?? x[W.alias]);
      if (!name) return problems.push(`${W.list} ${i + 1}번째 칸: ${W.one} 이름이 없어 뺐습니다.`);
      const o = { name };
      for (const k of ['start', 'end']) {
        const d = HT.readCellEdge(x, k); // 칸의 미정: "미정" 글 · startUnknown · startHint → 미정 + (있으면) 배치용 연도
        if (d && d.unknown) {
          if (d.t != null) o[k] = d.t;
          o[`${k}Unknown`] = true;
          continue;
        }
        if (d && isNaN(d.t)) return problems.push(`${W.one} "${name}"의 ${k === 'start' ? '시작' : '끝'}을 읽을 수 없어 그 칸을 뺐습니다.${d.error ? ` (${d.error})` : ''}`);
        if (d) {
          o[k] = d.t;
          if (d.at) o[`${k}At`] = d.at;
        }
      }
      if (o.start == null && !o.startUnknown && out.length) return problems.push(`${W.one} "${name}": 시작이 없어 뺐습니다 (시작을 비울 수 있는 것은 첫 칸뿐 — 정권 시작부터, 모르면 "미정").`);
      if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
        /* 거꾸로면 짐작인 쪽을 버립니다(인물 활동 시기와 같은 규칙): 끝이 미정이면 그 배치용 연도, 시작만 미정이면 시작의 배치용 연도
           (적은 끝은 사실이라 남기고 자리는 앞 지위에 맞춰 잡음), 둘 다 적은 날짜면 끝 */
        if (o.startUnknown && !o.endUnknown) {
          warnings.push(`${W.one} "${name}"의 끝이 시작보다 앞서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로, 자리는 앞 ${W.one}에 맞춤).`);
          delete o.start;
        } else {
          warnings.push(`${W.one} "${name}"의 끝이 시작보다 앞서 끝을 비웠습니다(${o.endUnknown ? '미정인 끝의 배치용 연도를 버림' : `다음 ${W.one}까지로 봄`}).`);
          delete o.end;
          delete o.endAt;
        }
      }
      if (o.startUnknown && o.endUnknown && o.start == null && o.end == null) warnings.push(`${W.one} "${name}"은(는) 시작과 끝이 모두 미정이고 배치용 연도가 없어, 앞뒤 ${W.one}나 정권의 기간에 맞춰 놓습니다.`);
      if (s(x.note)) o.note = s(x.note);
      Object.assign(o, HT.readUncertain(x, { mode: 'cell', warn: m => warnings.push(`${W.one} "${name}" — ${m}`), start: o.start, end: o.end })); // 확실성 · 연대 폭 · 이설 (다른 칸과 같은 읽기)
      out.push(o);
    });
    /* 차례: 다른 이어지는 칸과 같은 HT.sortCells — 시작 순, 배치용 연도 없이 시작이 미정인 칸은 적은 끝으로(끝도 없으면 적은 차례에서 바로 앞 칸 뒤에).
       시작을 비운 첫 칸(정권 시작부터)만 맨 앞 그대로. 미정이 없는 목록은 예전 차례와 같습니다 */
    const list = out.length && out[0].start == null && !out[0].startUnknown ? [out[0]].concat(HT.sortCells(out.slice(1))) : HT.sortCells(out);
    for (let i = 0; i + 1 < list.length; i++) {
      const a = list[i];
      const b = list[i + 1];
      if (b.start == null) {
        /* 시작이 미정이고 배치용 연도가 없는 칸은 앞 칸에 이어 놓습니다 — 겹치는 것은 적은 끝이 앞 칸의 끝보다 앞서(앞 칸의 시작보다는 뒤) 앞 칸 안에서 끝날 때뿐 */
        if (b.end != null && a.end != null && a.end > b.end && !(a.start != null && b.end <= a.start)) warnings.push(`${W.one} "${a.name}"와(과) "${b.name}"의 기간이 겹칩니다.`);
        continue;
      }
      if ((a.end != null && a.end > b.start) || a.start === b.start) warnings.push(`${W.one} "${a.name}"와(과) "${b.name}"의 기간이 겹칩니다.`);
    }
    return { list, problems, warnings };
  };
  /* 지위 변천 · 종교(6단계 D8)의 낱말 — 칸 목록 읽기(readSpanList)의 글: list = 목록의 이름 · one = 칸 하나의 이름 · alias = name 대신 읽는 열쇠 */
  const RANK_WORDS = { list: '지위 변천', one: '지위', alias: 'rank' };
  const FAITH_WORDS = { list: '종교 변천', one: '종교', alias: 'faith' };
  HT.readRanks = v => readSpanList(v, RANK_WORDS);
  /** 종교(faiths — 리메이크 6단계 D8 · 2026-10-24) 원문 → { list, problems, warnings } — 지위 변천과 같은 칸 꼴 [이름, 시작, 끝, 메모] · { name, start, end, note }
      (읽을 때만 name 대신 faith도 받음): 첫 칸의 시작을 비우면 정권 시작부터 · 끝을 비우면 다음 종교까지 · "미정" · 확실성 · 겹침 알림까지 같은 규칙(HT.readRanks의 몸을 함께 씀) */
  HT.readFaiths = v => readSpanList(v, FAITH_WORDS);
  /** 모델 전용: 지위 구간(끝을 채운 사본)과, 지위를 적지 않은 지도자에게 시작한 해의 지위를 채운 지도자 목록 → { spans, leaders } (지위가 없으면 null).
      ranks가 없고 지도자에게만 rank가 있으면, 같은 지위가 이어지는 지도자들을 묶어 구간을 끌어냅니다(derived — 지위를 적지 않은 지도자는 앞 지위를 잇는 것으로).
      구간 = { name, note, i, start, startAt, end, endAt, startAuto, endAuto, derived, def(사전 항목), id, tier, level(짙기 단계 0~4) } — 순번 i가 칸 참조('rank:i')입니다 */
  HT.resolveRanks = (p, defs) => {
    if (!p) return null;
    let raw = HT.readRanks(p.ranks).list;
    const derived = !raw.length;
    if (derived) {
      const byStart = (p.leaders || []).filter(c => c && c.start != null && isFinite(c.start)).slice().sort((a, b) => a.start - b.start);
      raw = [];
      for (const c of byStart) {
        const r = String(c.rank ?? '').trim();
        if (r && (!raw.length || raw[raw.length - 1].name !== r)) raw.push({ name: r, start: c.start, startAt: HT.atOf(c, 'start') || undefined });
      }
    }
    if (!raw.length) return null;
    /* 칸의 미정: 배치용 연도가 없는 미정인 쪽은 다른 이어지는 칸과 같은 규칙으로 자리를 잡습니다(HT.placeCells — 시작 = 앞 지위의 끝 → 앞 지위의 시작과
       다음 자리 사이 가운데 → 정권의 시작, 끝 = 다음 지위의 시작 → 정권의 끝). 시작을 비운 첫 칸은 먼저 정권의 시작에 두어(p0) 뒤 칸의 '앞 칸'이 되게 합니다.
       짐작한 자리는 사본에만(startAuto · endAuto) — 원문 p.ranks는 그대로. 미정이 없는 목록은 이 길을 지나지 않아 예전과 1px도 같습니다 */
    if (!derived && raw.some(c => c.startUnknown || c.endUnknown))
      raw = HT.placeCells(raw.map((c, i) => (i === 0 && c.start == null && !c.startUnknown ? Object.assign({}, c, { start: p.start, p0: true }) : c)), p);
    const P0 = { t: p.start, at: HT.atOf(p, 'start') };
    const P1 = { t: p.endY ?? p.end ?? p.start, at: p.ongoing ? null : HT.atOf(p, 'end') };
    const spans = raw.map((c, i) => {
      const next = raw[i + 1];
      const a = c.start != null && !c.p0 ? { t: c.start, at: c.startAt || null } : P0;
      let b = !derived && c.end != null ? { t: c.end, at: c.endAt || null } : next ? { t: next.start, at: next.startAt || null } : P1;
      if (b.t < a.t) b = a;
      const def = HT.findRank(defs, c.name);
      return Object.assign({
        name: c.name, note: c.note || '', i,
        start: a.t, startAt: a.at || undefined, end: b.t, endAt: b.at || undefined,
        startAuto: c.start == null || !!c.p0 || !!c.startAuto, endAuto: derived || c.end == null || !!c.endAuto, derived,
        endPolity: (derived || c.end == null) && b === P1, // 비운 끝을 정권의 끝으로 채움 — HT.cellSpan의 hi가 그해 끝까지 (다음 지위의 시작에서 채운 끝은 그 순간까지)
        def, id: def ? def.id : '', tier: def && def.tier != null ? def.tier : null, level: def ? def.level || 0 : 0,
      }, c.startUnknown ? { startUnknown: true } : null, c.endUnknown ? { endUnknown: true } : null, HT.uncOf(c)); // 칸의 미정 (연표 · 창의 글이 '미정'으로) · 확실성 · 연대 폭 · 이설 (디테일 건의 4)
    });
    const at = t => spans.find(sp => sp.start <= t && t < sp.end) || spans.find(sp => sp.start <= t && t <= sp.end) || null;
    let touched = false;
    const leaders = (p.leaders || []).map(c => {
      if (!c || c.rank || c.start == null) return c;
      const sp = at(c.start);
      if (!sp) return c;
      touched = true;
      return Object.assign({}, c, { rankAuto: sp.name }); // 짐작한 지위는 따로 (폼에는 적힌 것만)
    });
    return { spans, leaders: touched ? leaders : null };
  };
  /** 모델 전용: 종교 구간(끝을 채운 사본 — 6단계 D8) [{ name, note, i, start, startAt, end, endAt, startAuto, endAuto, endPolity, startUnknown?, endUnknown?, 확실성 … }] (종교가 없으면 null).
      지위 변천의 구간(HT.resolveRanks)과 같은 규칙이되 지도자에게서 끌어내지 않고 사전이 없습니다. 원문 p.faiths는 그대로 */
  HT.resolveFaiths = p => {
    if (!p) return null;
    let raw = HT.readFaiths(p.faiths).list;
    if (!raw.length) return null;
    if (raw.some(c => c.startUnknown || c.endUnknown))
      raw = HT.placeCells(raw.map((c, i) => (i === 0 && c.start == null && !c.startUnknown ? Object.assign({}, c, { start: p.start, p0: true }) : c)), p);
    const P0 = { t: p.start, at: HT.atOf(p, 'start') };
    const P1 = { t: p.endY ?? p.end ?? p.start, at: p.ongoing ? null : HT.atOf(p, 'end') };
    return raw.map((c, i) => {
      const next = raw[i + 1];
      const a = c.start != null && !c.p0 ? { t: c.start, at: c.startAt || null } : P0;
      let b = c.end != null ? { t: c.end, at: c.endAt || null } : next ? { t: next.start, at: next.startAt || null } : P1;
      if (b.t < a.t) b = a;
      return Object.assign({
        name: c.name, note: c.note || '', i,
        start: a.t, startAt: a.at || undefined, end: b.t, endAt: b.at || undefined,
        startAuto: c.start == null || !!c.p0 || !!c.startAuto, endAuto: c.end == null || !!c.endAuto,
        endPolity: c.end == null && b === P1,
      }, c.startUnknown ? { startUnknown: true } : null, c.endUnknown ? { endUnknown: true } : null, HT.uncOf(c));
    });
  };
  /** 지위의 서열 글: "서열 7" · "서열 밖" · 사전에 없는 이름이면 "사전에 없는 지위" */
  HT.rankTierText = c => (!c.def ? '사전에 없는 지위' : c.tier == null ? '서열 밖' : `서열 ${c.tier}`);
  /** 지위 칸의 이름 · 짙기 단계 · 사전 이름(별칭으로 찾았으면)을 한 줄로 (설명글 · 검색) */
  HT.rankFull = c => `${c.name}${c.def && c.def.name !== c.name ? ` (${c.def.name})` : ''}`;
  /* 칸 종류 표의 '지위' — 목록은 모델의 p.rankSpans(끝을 채운 사본 · 끌어낸 것 포함). 지위 칸에는 문서를 달지 않습니다(정권 문서로 가는 길만) */
  HT.CELL_KINDS.push({
    id: 'rank', list: 'ranks', name: '지위', unit: '개', doc: false,
    title: c => c.name,
    full: c => HT.rankFull(c),
    tag: c => (c.tier != null ? `서열 ${c.tier}` : ''),
    items: p => (p && p.rankSpans) || [],
  });

  /* 소속(예속) — 문자열 하나, 또는 [{ polity, start, end, note }] 여러 개(옥저: 고조선 → 현도군 → 낙랑 → 고구려).
     opts.relation: 시대의 partOf에서만 켭니다 — 소속 관계(relation: id나 한국어, 모르는 말은 버림)와 놓는 자리(nest: true = 상위 띠 아래에 접기 · false = 제 줄)를 함께 받습니다.
     기관의 host · 왕조의 polities는 같은 꼴을 쓰지만 이 두 칸은 받지 않습니다.
     기간의 시작 · 끝에 "미정"도 됩니다(칸의 미정 — startUnknown/endUnknown + 배치용 연도가 있으면 숫자) */
  HT.readPartOf = (v, opts = {}) => {
    const list = Array.isArray(v) ? v : v == null || v === '' ? [] : [v];
    return list
      .map(x => {
        if (typeof x === 'string') return { polity: x.trim() };
        if (!x || typeof x !== 'object') return null;
        const o = { polity: String(x.polity ?? x.to ?? x.name ?? '').trim() };
        if (opts.relation === true) {
          const rel = HT.relationId(x.relation);
          if (rel) o.relation = rel;
          if (x.nest === true || x.nest === false) o.nest = x.nest;
          if (x.main === true) o.main = true; // 으뜸 그릇(형식 4 within.main — 5단계 과제 3): 여러 그릇에 들 때 나무 · 서고의 기준
        }
        const s = HT.readCellEdge(x, 'start');
        const e = HT.readCellEdge(x, 'end');
        if (s && s.unknown) {
          if (s.t != null) o.start = s.t;
          o.startUnknown = true;
        } else if (s && !isNaN(s.t)) {
          o.start = s.t;
          if (s.at) o.startAt = s.at;
        }
        if (e && e.unknown) {
          if (e.t != null) o.end = e.t;
          o.endUnknown = true;
        } else if (e && !isNaN(e.t)) {
          o.end = e.t;
          if (e.at) o.endAt = e.at;
        }
        if (x.note && String(x.note).trim()) o.note = String(x.note).trim();
        Object.assign(o, HT.readUncertain(x, { mode: 'cell', warn: opts.warn && (m => opts.warn(`"${o.polity}" — ${m}`)), start: o.start, end: o.end })); // 확실성 · 연대 폭 · 이설 (다른 칸과 같은 읽기 — opts.warn을 주면 알림)
        return o;
      })
      .filter(x => x && x.polity);
  };
  /** 항목 하나뿐이고 기간·메모가 없으면 문자열로 줄입니다 (파일이 읽기 쉽고 옛 형식과 같음) */
  HT.compactPartOf = list => (list.length === 1 && Object.keys(list[0]).length === 1 ? list[0].polity : list);

  /* 대범위가 가리키는 정권(구성 정권 · 상징적 본국) 한 개: { track?, polity } — track을 비우면 대범위의 트랙 (docs/구상-체제-확장.md 0절 10).
     읽을 때는 "이름" · "트랙:이름" 글과 { track, polity } 객체를 모두 받고, 트랙을 적지 않았으면 글 하나로 줄여 적습니다 */
  HT.readScopeRef = x => {
    if (typeof x === 'string') {
      const s = x.trim();
      const m = s.match(/^([A-Za-z0-9_.-]+):(.+)$/);
      return !s ? null : m && m[2].trim() ? { track: m[1], polity: m[2].trim() } : { polity: s };
    }
    if (!x || typeof x !== 'object') return null;
    const polity = String(x.polity ?? x.name ?? '').trim();
    const track = String(x.track ?? '').trim();
    return !polity ? null : track ? { track, polity } : { polity };
  };
  HT.readScopeRefs = v => (Array.isArray(v) ? v : v == null || v === '' ? [] : [v]).map(HT.readScopeRef).filter(Boolean);
  HT.compactScopeRef = r => (r.track ? { track: r.track, polity: r.polity } : r.polity);
  /** 글 한 칸(폼)에 쓰는 꼴: "이름" 또는 "트랙:이름" */
  HT.scopeRefText = r => (!r ? '' : r.track ? `${r.track}:${r.polity}` : r.polity);

  /* "미정" — 연도를 모를 때. 배치용 연도(hint)로 자리만 잡습니다 */
  HT.isUnknownText = s => /^(미정|불명|모름|\?|unknown|tbd)$/i.test(String(s ?? '').trim());
  /** 지도자의 대수를 모름(묶음 5 · 4번): "미상"(모름 · 불명 · ? · unknown)을 적거나 ordinalUnknown: true */
  HT.isUnknownOrdinal = v => v === true || /^(미상|미정|불명|모름|\?|unknown)$/i.test(String(v ?? '').trim());
  HT.UNKNOWN_FADE = 44; // 미정 쪽으로 사라지는 꼬리의 길이(px)

  /* ---------- 이설 · 모호한 연대 (디테일 건의 4 — 모든 항목 · 칸 공통) ----------
   * 다른 견해(alternatives)와 연대의 확실성(certainty) · 연대 폭(startRange · endRange와 짝 날짜 글 startRangeAt · endRangeAt)은
   * 사건 · 시대 · 기관 · 문화 · 왕조와 같은 뜻 · 같은 읽기로 칸에도 적습니다 — 지도자 · 내각 · 연호 · 도읍 · 시기 구분의 시기 · 지위 변천 · 소속 줄
   * (시대의 partOf · 기관의 host · 왕조의 polities = 왕조 구간) · 인물의 활동 기록(service). 시대 구분(epochs) · 인물(figures)은 다른 견해만.
   * 읽는 함수는 하나(HT.readUncertain → 이설은 HT.readAlternatives): 파일(normalizePack) · 패치 · 폼 · 모델이 모두 같은 꼴을 얻습니다.
   * 이설 하나 = { start?, startAt?, end?, endAt?, ongoing?, birth?, birthAt?, death?, deathAt?, label, source?, note? }
   *   항목(mode 'item' — 사건 · 시대 · 기관 · 문화 · 왕조 · 시대 구분): 날짜를 적으면 시작부터(끝 · 현재까지는 선택) — 예전 그대로
   *   칸(mode 'cell'): 시작이나 끝 하나만 있어도 됨(끝난 해만 다른 설) — 빈 쪽은 통설 값(그 칸에 적힌 시작 · 끝 — HT.altSpan)
   *   인물(mode 'figure'): 출생 · 사망 · 활동 시작 · 활동 끝 가운데 무엇이든 — 빈 것은 통설 값
   *   날짜가 하나도 없으면 글만 있는 견해(label · source · note) — 연표에는 표시가 없고 상세 창의 '다른 견해'에만 보입니다.
   * 모델: 칸의 사본(도읍 · 시기 · 지위 구간 · 소속 hosts · 왕조 구간 dynasties · 인물의 services)도 이 열쇠들(HT.UNC_KEYS)을 그대로 넘겨받습니다(HT.uncOf).
   * 연표 그림(유령 구분선 · 이설 조명 · 모호한 칸의 무늬 — timeline.js altRowPlan)이 쓰는 값: 모델의 칸 c의 c.alternatives(날짜 있는 것만 — HT.altDated) · c.certainty(적은 것만 — 통설이면 없음) ·
   *   c.startRange · c.endRange([이른, 늦은] 해 좌표). 이설의 채운 구간은 HT.altSpan(a, 칸의 적힌 구간), 칸이 품는 구간은 HT.cellSpan(칸의 경계)으로 —
   *   이설은 이웃 칸과 겹쳐도 되므로 경계를 나누는 계산(HT.cellBounds)에는 넣지 않습니다 */
  HT.UNC_KEYS = ['certainty', 'startRange', 'startRangeAt', 'endRange', 'endRangeAt', 'alternatives'];
  /** x에 적힌 확실성 · 연대 폭 · 이설만 담은 사본 (모델이 칸을 새로 만들 때 넘겨받는 값) */
  HT.uncOf = x => {
    const o = {};
    if (x) for (const k of HT.UNC_KEYS) if (x[k] != null) o[k] = x[k];
    return o;
  };
  /** 확실성(통설이 아닌 것) · 연대 폭 · 이설 가운데 하나라도 적혔는가 */
  HT.hasUncertainty = x => !!x && ((x.certainty && x.certainty !== 'accepted') || !!x.startRange || !!x.endRange || !!(x.alternatives && x.alternatives.length));
  /** 날짜가 적힌 이설인가 (글만 있는 견해가 아닌가) */
  HT.altDated = a => !!a && (a.start != null || a.end != null || a.ongoing === true || a.birth != null || a.death != null);
  /** 연대가 모호한가 — 확실성이 추정 · 전승이거나 연대 폭이 적힘. '확실'(사료로 분명)은 흐림이 아니므로 들지 않습니다 (연표의 무늬 · 목록 딱지 · [이설] 단추의 '모호') */
  HT.isFuzzy = x => !!x && (x.certainty === 'estimated' || x.certainty === 'legend' || !!x.startRange || !!x.endRange);
  /** 연표에 그릴 이설 · 모호함이 있는가 — 날짜 있는 이설(유령 구분선 · 이설 조명)이나 모호한 연대(무늬). 글만 있는 견해 · '확실'은 상세 창에만 */
  HT.drawsUncertainty = x => !!x && (HT.isFuzzy(x) || ((x.alternatives || []).some(HT.altDated)));
  /** 항목의 그림에 쓰는 이설 — 시작이 있는 것만 (사건의 이설 막대 · 시대 띠의 고리: 글만 있는 견해는 그리지 않음) */
  HT.datedAlts = x => ((x && x.alternatives) || []).filter(a => a && a.start != null && isFinite(a.start));
  const ALT_DATE_KEYS = { item: ['start', 'end'], cell: ['start', 'end'], figure: ['start', 'end', 'birth', 'death'] };
  const ALT_WORDS = { start: '시작', end: '끝', birth: '출생', death: '사망' };
  /** 이설 목록 읽기 → [{ … }] (위 꼴). opts.mode = 'item' | 'cell' | 'figure', opts.warn(글) = 뺀 것 · 비운 것을 알림(없으면 조용히).
      opts.base(칸 · 인물) = 이 항목에 적힌 통설 값({ start, end, birth, death … } — 미정인 쪽(…Unknown)은 견주지 않음): 한쪽만 적은 이설의 빈 쪽을 이 값으로 채우면 앞뒤가 뒤집히는 이설은 뺍니다
      (둘 다 적은 이설이 뒤집힌 것과 같게 — 적지 않은 끝(뒤 칸의 시작까지)은 여기서 알 수 없으니 연표 · 상세 창이 HT.altFlipped로 다시 봅니다).
      읽은 결과를 다시 읽어도 같은 꼴(모델 · 폼이 다시 불러도 됨) */
  HT.readAlternatives = (list, { mode = 'item', warn = null, base = null } = {}) => {
    const say = m => warn && warn(m);
    const s = v => (v == null ? '' : String(v).trim());
    const keys = ALT_DATE_KEYS[mode] || ALT_DATE_KEYS.item;
    const out = [];
    (Array.isArray(list) ? list : []).forEach((a, n) => {
      if (!a || typeof a !== 'object' || Array.isArray(a)) return;
      const tag = `이설 #${n + 1}`;
      const ongoing = a.ongoing === true || HT.isOngoingText(a.end);
      const d = {};
      let bad = null;
      for (const k of keys) {
        if (k === 'end' && ongoing) continue;
        const r = HT.readDate(a[k], a[`${k}At`]);
        if (!r) continue;
        if (isNaN(r.t)) bad = bad || k;
        else d[k] = r;
      }
      const text = { label: s(a.label), source: s(a.source), note: s(a.note) };
      const dated = bad || ongoing || keys.some(k => d[k]);
      if (!dated) {
        if (!text.label && !text.source && !text.note) return say(`${tag}에 날짜도 근거도 없어 뺐습니다.`);
      } else if (mode === 'item') {
        /* 항목: 시작이 있어야 합니다(예전 그대로 — 사건의 이설 막대 · 시대 띠의 고리가 시작을 씀). 읽을 수 없는 끝은 비웁니다 */
        if (!d.start) return say(bad === 'start' || !(d.end || ongoing) ? `${tag}의 연도를 읽을 수 없어 뺐습니다.` : `${tag}에 시작이 없어 뺐습니다(항목의 이설은 시작부터 적습니다 — 근거만 적으려면 날짜를 모두 비웁니다).`);
        if (bad === 'end') say(`${tag}의 끝을 읽을 수 없어 비웠습니다.`);
      } else {
        /* 칸 · 인물: 적은 쪽만 — 읽을 수 없는 날짜가 있으면 통째로 뺍니다(빈 쪽이 통설 값으로 채워져 뜻이 바뀌지 않게) */
        if (bad) return say(`${tag}의 ${ALT_WORDS[bad]}을 읽을 수 없어 뺐습니다.`);
        for (const [x, y] of [['start', 'end'], ['birth', 'death']])
          if (d[x] && d[y] && HT.endBound(d[y].t, d[y].at) < d[x].t) return say(`${tag}의 ${ALT_WORDS[y]}이 ${ALT_WORDS[x]}보다 앞서 뺐습니다.`);
        const flip = base && altFlipSide(d, ongoing, base, keys);
        if (flip) return say(`${tag}${altFlipText(flip, mode === 'figure' ? '이 인물' : '이 칸')}`);
      }
      /* 열쇠 차례는 예전 사건 · 시대의 꼴 그대로(start · label · startAt · end · endAt · ongoing · source · note) — 이설이 있던 옛 파일도 1바이트도 달라지지 않게 */
      const o = {};
      if (d.start) o.start = d.start.t;
      o.label = text.label || '다른 견해';
      if (d.start && d.start.at) o.startAt = d.start.at;
      if (d.end && (mode !== 'item' || d.end.t !== o.start)) {
        o.end = d.end.t; // 칸 · 인물은 시작과 같은 끝도 남깁니다(비우면 통설의 끝으로 채워지므로)
        if (d.end.at) o.endAt = d.end.at;
      }
      if (ongoing) o.ongoing = true;
      for (const k of ['birth', 'death']) {
        if (!d[k]) continue;
        o[k] = d[k].t;
        if (d[k].at) o[`${k}At`] = d[k].at;
      }
      if (text.source) o.source = text.source;
      if (text.note) o.note = text.note;
      out.push(o);
    });
    return out;
  };
  /** 확실성 · 연대 폭 · 이설(· 쟁점) 읽기 — 항목과 칸이 같은 함수. x = 원본,
      opts.mode: 'item'(사건 · 시대 … — 옛 legendary · 쟁점도) · 'cell'(칸 — 통설은 적지 않음, 끝도 끝 연대 폭과 견줌) · 'figure' · 'epoch'(이설만),
      opts.warn(글) · opts.start · opts.end(대표 연대 — 연대 폭 밖이면 알림) → 적힌 것만 담은 { certainty?, startRange?, startRangeAt?, endRange?, endRangeAt?, alternatives?, debate? } */
  /** 세기로 적은 시작 · 끝(묶음 5 · 6번) → 연대 폭. 기간이 있는 것(시대 · 기관 · 문화 · 왕조 · 기간 사건 · 칸 · 소속 줄)은 그 세기 구간이 곧 연대 폭이라
      적지 않은 연대 폭을 채우고 끝을 구간의 마지막 해로 옮깁니다(띠는 구간 처음부터 끝까지 · 확정 해가 바깥 끝 — 지금의 연대 폭과 같은 자리).
      점 사건(끝이 없는 것)은 연대 폭이 아니라 그 구간 첫머리의 점 하나로 보입니다(연표의 _pointAt — 2026-10-13부터 괄호 없이 · 2026-10-14부터 확대해도 옮겨 가지 않음).
      x = 시작 · 끝(과 날짜 글 startAt · endAt)이 풀린 것, spanned = 기간이 있는가 → 고칠 칸만 { startRange?, endRange?, end? } */
  HT.centuryRanges = (x, spanned) => {
    const out = {};
    if (!x || !spanned || !HT.cal) return out;
    for (const key of ['start', 'end']) {
      if (x[`${key}Range`]) continue;
      const at = x[`${key}At`];
      const r = typeof at === 'string' && at ? HT.cal.parse(at) : null;
      if (!r || !r.ok || !r.span) continue;
      const v = x[key];
      if (typeof v === 'number' && Math.abs(v - r.t) > 1e-6 && Math.abs(v - r.last) > 1e-6) continue; // 날짜 글이 값과 맞지 않으면 건너뜀
      out[`${key}Range`] = [r.span[0], r.last];
      if (key === 'end') out.end = r.last;
    }
    return out;
  };
  HT.readUncertain = (x, { mode = 'item', warn = null, start = null, end = null, base = null } = {}) => {
    const out = {};
    if (!x || typeof x !== 'object' || Array.isArray(x)) return out;
    const say = m => warn && warn(m);
    const s = v => (v == null ? '' : String(v).trim());
    if (mode === 'item' || mode === 'cell') {
      const c = s(x.certainty);
      if (c && HT.CERTAINTY.some(v => v.id === c)) {
        if (mode !== 'cell' || c !== 'accepted') out.certainty = c; // 칸의 통설은 기본값이라 적지 않습니다 (폼을 열어 저장만 해도 패치가 생기지 않게)
      } else if (c) say(`확실성 "${c}"을(를) 알 수 없어 무시했습니다.`);
      else if (mode === 'item' && x.legendary) out.certainty = 'legend';
      for (const key of ['startRange', 'endRange']) {
        const v = x[key];
        if (v == null || v === '') continue;
        if (!Array.isArray(v) || v.length !== 2) {
          say(`${key}는 [이른 연도, 늦은 연도] 형식이어야 합니다.`);
          continue;
        }
        const atv = Array.isArray(x[`${key}At`]) ? x[`${key}At`] : [];
        const da = HT.readDate(v[0], atv[0]);
        const db = HT.readDate(v[1], atv[1]);
        const a = da ? da.t : null;
        const b = db ? db.t : null;
        if (a == null || b == null || isNaN(a) || isNaN(b)) {
          say(`${key}의 연도를 읽을 수 없습니다.`);
          continue;
        }
        const pair = a <= b ? [[a, da.at], [b, db.at]] : [[b, db.at], [a, da.at]];
        out[key] = pair.map(q => q[0]);
        if (pair.some(q => q[1])) out[`${key}At`] = pair.map(q => q[1] || null);
      }
      if (out.startRange && start != null && (start < out.startRange[0] || start > out.startRange[1])) // 시작이 미정이고 배치용 연도도 없는 칸은 견주지 않음
        say(`대표 연대가 연대 폭(${HT.formatYear(out.startRange[0])}~${HT.formatYear(out.startRange[1])}) 밖에 있습니다.`);
      if (mode === 'cell' && out.endRange && end != null && (end < out.endRange[0] || end > out.endRange[1]))
        say(`끝이 끝 연대 폭(${HT.formatYear(out.endRange[0])}~${HT.formatYear(out.endRange[1])}) 밖에 있습니다.`);
    }
    /* 칸 · 인물: 한쪽만 적은 이설이 통설 값(칸은 적힌 시작 · 끝 — opts.start · end, 인물은 opts.base)과 앞뒤가 뒤집히면 뺌 */
    /* 세기로 적은 시작 · 끝(묶음 5 · 6번 — HT.centuryRanges): 기간이 있는 것은 그 세기 구간이 곧 연대 폭. 패치의 set은 대상이 무엇인지 몰라 끝이 함께 적힌 것만 — 나머지는 모델이 합친 뒤에(buildModel) */
    if ((mode === 'item' || mode === 'cell') && HT.cal) {
      const spanned = mode === 'cell' || (x.end != null && x.end !== '') || x.ongoing === true;
      const ds = HT.readDate(x.start, x.startAt);
      const de = HT.readDate(x.end, x.endAt);
      Object.assign(out, HT.centuryRanges({ start: ds && ds.t, startAt: ds && ds.at, end: de && de.t, endAt: de && de.at, startRange: out.startRange, endRange: out.endRange }, spanned));
    }
    const unk = k => HT.isUnknownText(x[k]) || x[`${k}Unknown`] === true;
    const alts = HT.readAlternatives(x.alternatives, { mode: mode === 'epoch' ? 'item' : mode, warn, base: mode === 'cell' ? base || { start, end, startUnknown: unk('start'), endUnknown: unk('end') } : mode === 'figure' ? base : null });
    if (alts.length) out.alternatives = alts;
    if (mode === 'item' && s(x.debate)) out.debate = s(x.debate);
    return out;
  };
  const FIG_ALT_KEYS = ['birth', 'death', 'start', 'end'];
  /** 이설의 채운 구간 — 이설이 비운 쪽은 통설 값(base의 그 칸: 칸은 적힌 시작 · 끝(끝을 비운 칸은 풀어 둔 끝), 인물은 생몰 · 활동 시기).
      → { start, startAt, end, endAt, ongoing, startUnknown, endUnknown, (birth · birthAt · death · deathAt), own: { 칸: 이설이 적었나 } } */
  HT.altSpan = (a, base = {}, keys = ['start', 'end']) => {
    const o = { own: {} };
    for (const k of keys) {
      const own = a[k] != null || (k === 'end' && a.ongoing === true);
      o.own[k] = own;
      const src = own ? a : base;
      o[k] = src[k] ?? null;
      o[`${k}At`] = src[`${k}At`] || undefined;
      if ((k === 'start' || k === 'end') && !own && base[`${k}Unknown`]) o[`${k}Unknown`] = true;
    }
    o.ongoing = a.ongoing === true || (!o.own.end && !!base.ongoing);
    if (o.ongoing) o.end = o.endAt = undefined;
    return o;
  };
  /** 한쪽만 적은 이설의 빈 쪽을 통설 값으로 채우면 앞뒤가 뒤집히는가 → 뒤집힌 짝 { own: 이설이 적은 쪽, other: 통설로 채운 쪽 } | null.
      d = 이설이 적은 날짜 { 열쇠: { t, at } }, base = 통설 값. 통설이 미정인 쪽(startUnknown …)으로 채우는 짝은 견주지 않습니다 —
      채운 쪽이 '미정'이라 뒤집힌 글이 되지 않고, 배치용 연도는 주장이 아니므로(시작이 미정인 칸의 '미정 ~ 340년'은 두 쪽을 다 적은 이설처럼 이웃 칸 자리에 선이 서도 됨) */
  const altFlipSide = (d, ongoing, base, keys) => {
    for (const [x, y] of [['start', 'end'], ['birth', 'death']]) {
      if (!keys.includes(x)) continue;
      const ownX = !!d[x];
      const ownY = !!d[y] || (y === 'end' && ongoing);
      if (ownX === ownY) continue; // 둘 다 적었으면(위에서 따로 봄) · 둘 다 비웠으면 견줄 것 없음
      if (y === 'end' && (ongoing || (!d[y] && base.ongoing))) continue; // 현재까지 — 끝이 없음
      if (base[`${ownX ? y : x}Unknown`]) continue; // 채우는 쪽이 미정
      const bx = d[x] ? d[x].t : base[x];
      const by = d[y] ? HT.endBound(d[y].t, d[y].at) : base[y] == null ? null : HT.endBound(base[y], base[`${y}At`]);
      if (bx == null || by == null || !isFinite(bx) || !isFinite(by)) continue;
      if (by < bx) return ownX ? { own: x, other: y } : { own: y, other: x };
    }
    return null;
  };
  const FIG_WORDS = Object.assign({}, ALT_WORDS, { start: '활동 시작', end: '활동 끝' });
  const altFlipText = (f, who, W = who === '이 인물' ? FIG_WORDS : ALT_WORDS) =>
    `의 ${W[f.own]}이 ${who}의 ${W[f.other]}보다 ${f.own === 'start' || f.own === 'birth' ? '늦어' : '앞서'} 뺐습니다(비운 ${W[f.other]}은 ${who}의 연대로 채웁니다).`;
  /** 읽은 이설 a를 통설 구간 base(칸의 연표에 놓인 구간 — 풀어 둔 끝 · 인물의 활동 끝까지)로 채우면 앞뒤가 뒤집히는가 —
      적지 않은 끝처럼 파일을 읽을 때는 몰랐던 값과 견줍니다. 뒤집힌 이설은 연표에 그리지 않고, 상세 창의 '다른 견해'에 까닭과 함께 적습니다 */
  HT.altFlipped = (a, base = {}, keys = ['start', 'end']) => {
    if (!HT.altDated(a)) return false;
    const d = {};
    for (const k of keys) if (a[k] != null && isFinite(a[k])) d[k] = { t: a[k], at: a[`${k}At`] || null };
    for (const [x, y] of [['start', 'end'], ['birth', 'death']]) if (d[x] && d[y] && HT.endBound(d[y].t, d[y].at) < d[x].t) return true;
    return !!altFlipSide(d, a.ongoing === true, base || {}, keys);
  };
  /** 이설의 날짜 글 — 칸 · 항목은 채운 구간("350년 ~ 412년"), 인물은 "생몰 … · 활동 …"(이설이 적은 쪽만). 글만 있는 견해는 '' */
  HT.altWhen = (a, base = {}, { figure = false } = {}) => {
    if (!HT.altDated(a)) return '';
    if (!figure) return HT.formatRange(HT.altSpan(a, base));
    const f = HT.altSpan(a, base, FIG_ALT_KEYS);
    const bits = [];
    if (f.own.birth || f.own.death) bits.push(`생몰 ${[f.birth != null ? HT.formatDate(f.birth, f.birthAt) : '', f.death != null ? HT.formatDate(f.death, f.deathAt) : ''].join(' ~ ').trim()}`);
    if (f.own.start || f.own.end) bits.push(`활동 ${HT.formatRange(f)}`);
    return bits.join(' · ');
  };
  /** 이설 한 줄의 글 (표 · CSV · 노선도 설명글): "350년 ~ 412년: 근거" · 글만 있는 견해는 "근거" */
  HT.altText = (a, base = {}, opts = {}) => {
    const when = HT.altWhen(a, base, opts);
    return when ? `${when}: ${a.label}` : a.label;
  };

  /* ---------- 조약 ----------
     조약은 새 목록이 아니라 사건의 treaty 묶음 칸입니다: 체결 = 사건의 start, 실효 = end, 아직 유효 = ongoing.
     파일 · 폼 · 패치가 모두 HT.readTreaty 하나로 깨끗한 꼴이 됩니다(아는 칸만 옮기는 화이트리스트 — 모르는 칸은 버림).
     한국어 낱말 → id 환산은 어휘마다 따로 둡니다(같은 낱말이 어휘마다 다른 뜻일 수 있어서 — 도읍 역할의 HT.capitalRole과 같은 틀) */
  HT.TREATY_TYPES = [
    { id: 'peace', name: '강화' },
    { id: 'armistice', name: '휴전' },
    { id: 'alliance', name: '동맹' },
    { id: 'nonaggression', name: '불가침' },
    { id: 'trade', name: '통상' },
    { id: 'border', name: '국경' },
    { id: 'cession', name: '할양·병합' },
    { id: 'protectorate', name: '보호' },
    { id: 'investiture', name: '책봉·조공' },
    { id: 'marriage', name: '혼인' },
    { id: 'other', name: '기타' },
  ];
  HT.TREATY_END_REASONS = [
    { id: 'expired', name: '기한 만료' },
    { id: 'abrogated', name: '폐기' },
    { id: 'superseded', name: '새 조약으로 대체' },
    { id: 'fulfilled', name: '이행 완료' },
    { id: 'annulled', name: '무효' },
  ];
  HT.ARTICLE_TAGS = [
    { id: 'territory', name: '영토' },
    { id: 'indemnity', name: '배상' },
    { id: 'trade', name: '통상' },
    { id: 'extraterritorial', name: '치외법권' },
    { id: 'military', name: '군사' },
    { id: 'recognition', name: '승인' },
    { id: 'other', name: '기타' },
  ];
  /* 표의 이름(강화 · 폐기 · 영토 …) 말고도 읽는 낱말 — 띄어쓰기는 무시합니다 */
  const TREATY_WORDS = { 평화: 'peace', 강화조약: 'peace', 정전: 'armistice', 휴전협정: 'armistice', 동맹조약: 'alliance', 불가침조약: 'nonaggression', 수호: 'trade', 무역: 'trade', 통상조약: 'trade', 경계: 'border', 국경조약: 'border', 할양: 'cession', 병합: 'cession', 합병: 'cession', 보호조약: 'protectorate', 책봉: 'investiture', 조공: 'investiture', 혼인동맹: 'marriage' };
  const TREATY_END_WORDS = { 만료: 'expired', 기한만료: 'expired', 파기: 'abrogated', 대체: 'superseded', 이행: 'fulfilled', 이행완료: 'fulfilled', 무효화: 'annulled' };
  const ARTICLE_WORDS = { 할양: 'territory', 배상금: 'indemnity', 무역: 'trade', 영사재판권: 'extraterritorial', 군대: 'military', 주둔: 'military', 인정: 'recognition' };
  const vocab = (list, words) => v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    const hit = list.find(x => x.id === s || x.name === s);
    const k = s.replace(/\s+/g, '');
    return hit ? hit.id : (Object.prototype.hasOwnProperty.call(words, k) ? words[k] : '') || ''; // 제 낱말만 — 'constructor' · '__proto__' 같은 자유 글이 객체의 물려받은 것으로 읽히지 않게
  };
  const vocabName = list => id => (list.find(x => x.id === id) || { name: '' }).name;
  /** 조약 종류 · 끝난 까닭 · 조항 분류: id나 한국어 → id (모르면 '') */
  HT.treatyType = vocab(HT.TREATY_TYPES, TREATY_WORDS);
  HT.treatyEndReason = vocab(HT.TREATY_END_REASONS, TREATY_END_WORDS);
  HT.articleTag = vocab(HT.ARTICLE_TAGS, ARTICLE_WORDS);
  HT.treatyTypeName = vocabName(HT.TREATY_TYPES);
  HT.treatyEndName = vocabName(HT.TREATY_END_REASONS);
  HT.articleTagName = vocabName(HT.ARTICLE_TAGS);
  /** 서명자: 목록 [{ name, title }] 또는 한 칸 글 "이름(직함); 이름(직함)" → 늘 목록 꼴 [{ name, title? }].
      파일 · 폼 · 내보내기 비교가 모두 이 꼴이라, 글로 적은 것과 목록으로 적은 것이 같은 값으로 비교됩니다 */
  HT.readSigners = v => {
    const list = Array.isArray(v) ? v : typeof v === 'string' ? v.split(/[;；\n]/) : v && typeof v === 'object' ? [v] : [];
    return list
      .map(x => {
        if (typeof x === 'string') {
          const t = x.trim();
          const m = t.match(/^(.+?)\s*[(（]\s*([^()（）]*?)\s*[)）]$/);
          return m ? { name: m[1].trim(), title: m[2].trim() } : { name: t, title: '' };
        }
        return x && typeof x === 'object' ? { name: String(x.name ?? '').trim(), title: String(x.title ?? '').trim() } : null;
      })
      .filter(x => x && x.name)
      .map(x => (x.title ? x : { name: x.name }));
  };
  /** 서명자 목록 → 한 칸 글 "이름(직함); 이름(직함)" (폼의 칸) */
  HT.signersText = v => HT.readSigners(v).map(x => (x.title ? `${x.name}(${x.title})` : x.name)).join('; ');
  /** 폼의 한 칸 글 ↔ 채울 때의 원래 목록(칸의 data-list에 JSON으로 둔 것): 글이 채울 때의 글(toText(목록))과 같으면 원래 목록을 그대로 돌려주고,
      사람이 고쳤으면 글을 돌려줍니다(읽는 쪽이 다시 나눔). 글로 다시 나누면 바뀌는 값 — 괄호가 든 이름 · 괄호가 든 직함 · ';'이 든 이름 · 쉼표가 든 언어 —
      도 열어서 그대로 저장하면 원래 값 그대로입니다 (설계 0-3: 폼이 풀지 못하는 값은 data-*로 보존) */
  HT.keepListText = (text, kept, toText) => {
    if (!kept) return text;
    let list;
    try {
      list = JSON.parse(kept);
    } catch (e) {
      return text;
    }
    return Array.isArray(list) && toText(list) === text ? list : text;
  };
  /* 조항 번호로 시작하는 줄: "제1조" · "제 2 관" · "제3항" · "Article 4" · "Art. 5" (조항 한꺼번에 붙여넣기와 글로 적은 조항이 함께 씀) */
  const ARTICLE_HEAD = /^\s*(제\s*\d+\s*[조관항]|article\s+\d+|art\.\s*\d+)\s*[.:：]?\s*/i;
  /** 조항 글 하나 → { no, title, text }: 머리의 번호를 떼고, 번호 바로 뒤의 괄호 글("(목적)" · "【목적】")은 제목으로 */
  const splitArticle = s => {
    const t = String(s ?? '').replace(/\r/g, '').trim();
    const m = t.match(ARTICLE_HEAD);
    if (!m) return { no: '', title: '', text: t };
    const no = /^\s*art/i.test(m[1]) ? m[1].replace(/\s+/g, ' ') : m[1].replace(/\s+/g, '');
    let rest = t.slice(m[0].length);
    let title = '';
    const tm = rest.match(/^[(（【[]\s*([^)）】\]\n]{1,60}?)\s*[)）】\]]\s*/);
    if (tm) {
      title = tm[1].trim();
      rest = rest.slice(tm[0].length);
    }
    return { no, title, text: rest.trim() };
  };
  /** 조약문 통째 → 조항 목록: 조항 번호로 시작하는 줄마다 새 조항 (첫 번호 앞의 글은 번호 없는 조항 하나 — 전문) */
  HT.splitArticles = text => {
    const blocks = [];
    for (const line of String(text ?? '').replace(/\r/g, '').split('\n')) {
      if (ARTICLE_HEAD.test(line) || !blocks.length) blocks.push([line]);
      else blocks[blocks.length - 1].push(line);
    }
    return blocks.map(b => splitArticle(b.join('\n'))).filter(a => a.no || a.title || a.text);
  };
  /**
   * 조약 규격을 깨끗한 꼴로 (파일 · 폼 · 패치 · 메이커가 모두 이 함수 하나로) → null(적은 것이 없음) · { formal, type, unequal, ratified(+At), effective(+At),
   * endReason, place, languages, parties: [{ track?, polity, side?, role?, signatories: [{ name, title? }] }], articles: [{ no, title, tag, text }], concludes, supersedes } — 적은 칸만.
   * 당사국은 { track?, polity } 객체 또는 "트랙:이름" 글, 편(side)은 같은 편끼리 같은 수(비우면 모두 한 목록), 조항은 글 목록도 받습니다.
   * 당사국의 트랙은 여기서 검사하지 않습니다(다른 DLC · 기본팩의 트랙일 수 있음 — 모델이 못 찾으면 이름만 남김). warn(글)은 버린 값을 알립니다
   */
  HT.readTreaty = (raw, warn = () => {}) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const s = v => (v == null ? '' : String(v).trim());
    const o = {};
    if (s(raw.formal)) o.formal = s(raw.formal);
    if (s(raw.type)) {
      const t = HT.treatyType(raw.type);
      if (t) o.type = t;
      else warn(`조약 종류 "${s(raw.type)}"을(를) 알 수 없어 뺐습니다.`);
    }
    if (raw.unequal === true || /^(true|예|네|불평등)$/i.test(s(raw.unequal))) o.unequal = true;
    for (const [k, word] of [['ratified', '비준'], ['effective', '발효']]) {
      const d = HT.readDate(raw[k], raw[`${k}At`]);
      if (!d) continue;
      if (isNaN(d.t)) {
        warn(`조약의 ${word} 날짜를 읽을 수 없어 뺐습니다.${d.error ? ` ${d.error}` : ''}`);
        continue;
      }
      o[k] = d.t;
      if (d.at) o[`${k}At`] = d.at;
    }
    if (s(raw.endReason)) {
      const r = HT.treatyEndReason(raw.endReason);
      if (r) o.endReason = r;
      else warn(`조약이 끝난 까닭 "${s(raw.endReason)}"을(를) 알 수 없어 뺐습니다.`);
    }
    if (s(raw.place)) o.place = s(raw.place);
    const langs = (Array.isArray(raw.languages) ? raw.languages : s(raw.languages).split(/[,，、]/)).map(s).filter(Boolean);
    if (langs.length) o.languages = langs;
    const parties = (Array.isArray(raw.parties) ? raw.parties : raw.parties ? [raw.parties] : [])
      .map((p, i) => {
        let track = '';
        let polity = '';
        if (typeof p === 'string') polity = s(p);
        else if (p && typeof p === 'object') {
          track = s(p.track);
          polity = s(p.polity ?? p.name);
        }
        const tp = !track && /^[^:]+:.+$/.test(polity) ? polity.split(/:(.*)/) : null; // "트랙:이름"
        if (tp) [track, polity] = [tp[0].trim(), tp[1].trim()];
        if (!track && !polity) {
          if (p != null && p !== '') warn(`조약의 당사국 #${i + 1}: 정권이 비어 있어 뺐습니다.`);
          return null;
        }
        const q = {};
        if (track) q.track = track;
        if (polity) q.polity = polity;
        if (p && typeof p === 'object') {
          if (p.side !== '' && p.side != null) {
            const n = Number(p.side);
            if (Number.isFinite(n) && n > 0) q.side = Math.round(n);
            else warn(`조약의 당사국 #${i + 1}: 편(side)은 1 · 2처럼 수로 적습니다 — "${s(p.side)}"을(를) 뺐습니다.`);
          }
          if (s(p.role)) q.role = s(p.role);
          const sig = HT.readSigners(p.signatories);
          if (sig.length) q.signatories = sig;
        }
        return q;
      })
      .filter(Boolean);
    if (parties.length) o.parties = parties;
    const articles = (Array.isArray(raw.articles) ? raw.articles : typeof raw.articles === 'string' ? HT.splitArticles(raw.articles) : [])
      .map((a, i) => {
        const x = typeof a === 'string' ? splitArticle(a) : a && typeof a === 'object' ? a : null;
        if (!x) return null;
        const q = {};
        if (s(x.no)) q.no = s(x.no);
        if (s(x.title)) q.title = s(x.title);
        if (s(x.tag)) {
          const t = HT.articleTag(x.tag);
          if (t) q.tag = t;
          else warn(`조약의 조항 #${i + 1}: 분류 "${s(x.tag)}"을(를) 알 수 없어 뺐습니다.`);
        }
        const text = String(x.text ?? '').replace(/\r/g, '').trim();
        if (text) q.text = text;
        return Object.keys(q).length ? q : null;
      })
      .filter(Boolean);
    if (articles.length) o.articles = articles;
    if (s(raw.concludes)) o.concludes = s(raw.concludes);
    if (s(raw.supersedes)) o.supersedes = s(raw.supersedes);
    return Object.keys(o).length ? o : null;
  };

  /* ---------- 단체 · 주제 사전 · 제도 칸 · 사건의 주제 · 법 · 선거 (형식 버전 3 — docs/구상-연표-확장-10건.md 3-7 · 3-8) ----------
     단체(groups)는 나라 안의 붕당 · 정당 · 정권(실권 집단) · 세력과 여러 나라에 걸친 연합 — 자료는 3-7, 그것을 보는 렌즈는 3-8(모양은 설계 D5가 정함).
     주제 사전(themes)은 렌즈의 주제 — 내장 뼈대 여덟(HT.THEMES) + 켠 DLC들의 사전을 id로 합칩니다(지위 사전 rankDefs와 같은 규칙).
     제도 칸(institutions)은 나라마다 주제마다 이어지는 칸 목록(연호와 같은 칸 꼴 · 비운 경계는 시기 구분과 같은 규칙),
     사건의 theme(주제 꼬리표) · law(법 규격) · election(선거 규격)은 조약 규격(treaty)처럼 사건에 얹는 칸입니다.
     파일 · 폼 · 패치가 모두 아래 읽기 함수로 깨끗한 꼴이 됩니다(아는 칸만 옮김 — 모르는 칸은 버림). 한국어 낱말 → id 환산은 어휘마다 따로(조약과 같은 틀) */
  HT.GROUP_TYPES = [
    { id: 'faction', name: '붕당·파벌' },
    { id: 'party', name: '정당' },
    { id: 'regime', name: '정권·실권 집단' },
    { id: 'bloc', name: '세력' },
    { id: 'coalition', name: '연합·동맹' },
  ];
  HT.GROUP_HOWS = [
    { id: 'split', name: '갈라짐' },
    { id: 'merge', name: '합쳐짐' },
    { id: 'rename', name: '이름 바꿈' },
    { id: 'unknown', name: '미상' }, // 어떻게 이어졌는지 모른다고 적음(비움 = 적지 않음과 다름 — 단체 계보 창은 점선 + '방식 미상' · 설계 7-8 제안 5)
  ];
  HT.LAW_ACTS = [
    { id: 'enact', name: '제정' },
    { id: 'amend', name: '개정' },
    { id: 'repeal', name: '폐지' },
  ];
  /* 표의 이름 말고도 읽는 낱말 — 띄어쓰기는 무시합니다 (모르는 단체 종류는 자유 글로 그대로 남고, 모르는 갈라짐 방식 · 법의 고침 종류는 경고와 함께 뺍니다) */
  const GROUP_TYPE_WORDS = { 붕당: 'faction', 파벌: 'faction', 당파: 'faction', 정당: 'party', 정권: 'regime', 실권: 'regime', 실권집단: 'regime', 세력: 'bloc', 연합: 'coalition', 동맹: 'coalition', 연합세력: 'coalition', 연맹: 'coalition' };
  const GROUP_HOW_WORDS = { 분열: 'split', 분당: 'split', 갈라져나옴: 'split', 갈라섬: 'split', 합류: 'merge', 통합: 'merge', 합당: 'merge', 합침: 'merge', 이름바꿈: 'rename', 개칭: 'rename', 개명: 'rename', 바뀐이름: 'rename', 방식미상: 'unknown', 모름: 'unknown', 불명: 'unknown', '?': 'unknown' };
  const LAW_ACT_WORDS = { 공포: 'enact', 반포: 'enact', 신설: 'enact', 수정: 'amend', 개편: 'amend', 폐기: 'repeal', 철폐: 'repeal', 혁파: 'repeal' };
  /** 단체 종류 · 갈라짐 방식 · 법의 고침 종류: id나 한국어 → id (모르면 '') */
  HT.groupType = vocab(HT.GROUP_TYPES, GROUP_TYPE_WORDS);
  HT.groupHow = vocab(HT.GROUP_HOWS, GROUP_HOW_WORDS);
  HT.lawAct = vocab(HT.LAW_ACTS, LAW_ACT_WORDS);
  /** 단체 종류의 이름 — 표에 있는 id면 그 이름, 자유 글이면 그 글 그대로 */
  HT.groupTypeName = t => vocabName(HT.GROUP_TYPES)(t) || String(t ?? '');
  HT.groupHowName = vocabName(HT.GROUP_HOWS);
  HT.lawActName = vocabName(HT.LAW_ACTS);
  /** 내장 주제 사전: 감독이 고른 여덟 주제의 뼈대만 (판타지 · 대체역사의 주제와 이름 바꾸기는 DLC의 themes에 — 같은 id로 적으면 내장 항목을 덮음) */
  HT.THEMES = [
    { id: 'system', name: '체제', color: '#abb3c9' },
    { id: 'faction', name: '붕당', color: '#d4a39b' },
    { id: 'law', name: '법률', color: '#bba395' },
    { id: 'election', name: '선거제도', color: '#a0bcc5' },
    { id: 'ideology', name: '이념', color: '#bbacc8' },
    { id: 'military', name: '군사제도', color: '#b6c398' },
    { id: 'tax', name: '조세제도', color: '#d7c18e' },
    { id: 'selection', name: '선발제도', color: '#9dbea8' },
  ];
  /** 주제 사전 원문 → { list, problems, at } — 지위 사전(HT.readRankDefs)과 같은 꼴: id가 없으면 이름으로 만들고(theme-…), 같은 id가 또 나오면 뒤의 것을 뺍니다 */
  HT.readThemeDefs = v => {
    const s = x => (x == null ? '' : String(x).trim());
    const problems = [];
    const at = [];
    const bad = (i, msg) => {
      problems.push(msg);
      at.push(i);
    };
    const list = [];
    if (v != null && v !== '' && !Array.isArray(v)) bad(undefined, '주제 사전(themes)은 목록이어야 해서 무시했습니다.');
    (Array.isArray(v) ? v : []).forEach((d, i) => {
      if (!d || typeof d !== 'object' || Array.isArray(d)) return bad(i, `주제 사전 #${i + 1}: 형식이 올바르지 않아 뺐습니다.`);
      const name = s(d.name);
      /* 렌즈에서 숨김(hidden: true — 감독 D5 결정 6 덧붙임 "렌즈 종류도 dlc 조정 가능하게"): 이름 없이 { id, hidden: true }만 적은 줄도 받습니다 — 내장 · 다른 DLC의 주제를 숨기기만 하는 줄 */
      const hide = d.hidden === true;
      if (!name && !(hide && s(d.id))) return bad(i, `주제 사전 #${i + 1}: 이름이 없어 뺐습니다.`);
      let id = s(d.id);
      if (id && !HT.ID_RE.test(id)) {
        if (!name) return bad(i, `주제 사전 #${i + 1}: id "${id}"가 올바르지 않아 뺐습니다 (이름 없이 숨김만 적은 줄).`);
        bad(i, `주제 사전 "${name}": id "${id}"가 올바르지 않아 새로 만들었습니다.`);
        id = '';
      }
      if (!id) id = `theme-${HT.hash(name)}`;
      if (list.some(x => x.id === id)) return bad(i, `주제 사전 "${name || id}": id "${id}"가 중복되어 뺐습니다.`);
      const o = name ? { id, name } : { id };
      if (hide) o.hidden = true;
      if (!name) return list.push(o); // 숨김만 적은 줄 — 색 · 설명 · 이름 목록은 이름이 있는 정의(내장 · 다른 DLC)의 것
      if (HT.isColor(d.color)) o.color = d.color;
      if (s(d.kind)) o.kind = s(d.kind);
      if (s(d.description)) o.description = s(d.description);
      const names = HT.readNames(d.names, m => bad(i, `주제 사전 "${name}": ${m}`)); // 이름 목록(주제의 원어 · 다른 이름 — 형식 3 F1과 같은 읽기)
      if (names.length) o.names = names;
      list.push(o);
    });
    return { list, problems, at };
  };
  /** 모델의 주제 사전: 켠 DLC들의 사전(먼저 정의가 이김 · id로만 합침) + 맨 끝에 내장 뼈대가 빈 자리만. 차례는 내장 뼈대의 차례(같은 id로 덮은 것도 그 자리) → DLC만의 주제.
      렌즈에서 숨김(hidden)은 따로 모읍니다: 켠 DLC 가운데 하나라도 그 id를 숨기면 숨김(hiddenBy = 숨긴 DLC 이름) — 이름 없이 숨김만 적은 줄은 이름 · 색을 정하지 않고 숨김만 보탭니다.
      숨긴 주제도 사전에는 남습니다(제도 · 사건 꼬리표가 그대로 찾고 상세 창 · 검색에 나옴) — 렌즈 고르기(HT.lensThemes)에서만 빠짐 */
  HT.mergeThemes = packs => {
    const byId = new Map();
    const hidden = new Map();
    for (const pack of packs || [])
      for (const d of (pack && pack.themes) || []) {
        if (!d || !d.id) continue;
        if (d.hidden && !hidden.has(d.id)) hidden.set(d.id, pack.name || pack.id);
        if (d.name && !byId.has(d.id)) byId.set(d.id, Object.assign({}, d, { packId: pack.id, packName: pack.name }));
      }
    const out = HT.THEMES.map(d => byId.get(d.id) || Object.assign({}, d, { builtin: true }));
    for (const d of byId.values()) if (!HT.THEMES.some(b => b.id === d.id)) out.push(d);
    for (const d of out) {
      delete d.hidden;
      if (hidden.has(d.id)) Object.assign(d, { hidden: true, hiddenBy: hidden.get(d.id) });
    }
    return out;
  };
  /** 사전에서 주제 찾기: id → 이름 → 내장 뼈대의 이름(같은 id로 덮어 이름을 바꾼 주제도 '조세제도'처럼 내장 이름으로 가리킬 수 있게) (없으면 null) */
  HT.findTheme = (defs, ref) => {
    const s = String(ref ?? '').trim();
    if (!s || !Array.isArray(defs)) return null;
    const b = HT.THEMES.find(d => d.name === s);
    return defs.find(d => d.id === s) || defs.find(d => d.name === s) || (b && defs.find(d => d.id === b.id)) || null;
  };
  /** 사건의 주제 꼬리표: 목록 · 글 하나(쉼표로 여럿) → 빈 것 · 겹친 것을 뺀 목록 */
  HT.readThemeList = v => [...new Set((Array.isArray(v) ? v : v == null ? [] : String(v).split(/[,，]/)).map(x => (x == null || typeof x === 'object' ? '' : String(x).trim())).filter(Boolean))];

  /* ---------- 렌즈 (설계 docs/설계-10건/7-8-단체와-렌즈.md 결정 5 · 6 — 감독 선택 5 A · 6 B, 2026-10-12) ----------
     렌즈 = 주제 사전의 주제 하나. 켜면 나라 띠의 지도자 칸 자리(20px — 줄 높이 그대로)에 그 주제의 칸을 바꿔 끼웁니다. 칸의 출처(HT.lensCellsOf):
       · 제도 칸(institutions — 그 나라 · 그 주제의 제도들의 칸을 날짜 차례로) — 색은 갈래 색(같은 갈래면 나라가 달라도 같은 색), 갈래가 없으면 주제 색
       · 붕당(faction)은 단체의 집권 기간(groups[].power — 나라 안 단체 · 연합과 실권 집단은 뺌)이 먼저 — 결정 1의 집권 단이 생기면 그 단과 맞바꿈이 됩니다
       · 체제(system)는 제도 칸이 없으면 지위 변천(p.rankSpans) — 지위 단이 있는 줄은 지위 단과 지도자 칸이 자리를 맞바꿈
     그 주제 자료가 없는 나라는 지도자 칸을 옅게 남깁니다(비우지 않음 — '자료 없음'과 '그런 제도가 없었음'이 같아 보이지 않게).
     연표(js/timeline.js) · 렌즈 차림표(js/lens-ui.js)가 이 도우미로 셈하고, 새 앱 내보내기도 같은 셈을 따르면 됩니다(설계 문서 '구현 기록(웹 — 렌즈)') */
  HT.THEME_HINTS = { system: '나라의 짜임', faction: '집권한 단체', law: '법 · 법전', election: '뽑는 방법', ideology: '기준 이념', military: '병제', tax: '세금 거두는 법', selection: '관리 뽑는 법' };
  /** 렌즈 차림표의 한마디 설명: 주제의 갈래(kind — DLC가 적음) → 내장 주제의 한마디 (없으면 '') */
  HT.themeHint = t => (t && (t.kind || HT.THEME_HINTS[t.id])) || '';
  /** 렌즈의 갈래 색 — 같은 주제 안 겹침 막기(설계 7-8 3절 제안 4 ㉮): 같은 주제의 갈래를 이름 차례(코드 값 차례)로 놓고, 갈래 이름의 해시로 고른 팔레트 자리가
      앞 갈래에 이미 쓰였으면 다음 자리로(열둘이 다 차면 해시 그대로). 켠 DLC의 차례와 상관없이 같은 갈래 모음이면 늘 같은 색이고, 겹침이 없으면 예전 규칙(해시)과 같은 색.
      list = 모델의 제도 목록(familyKey = '주제 id|갈래') — 제도의 color를 고쳐 쓰고 { familyKey → 색 }을 돌려줍니다 */
  HT.familyColors = list => {
    const pal = HT.PASTEL.map(c => c.id);
    const byTheme = new Map();
    for (const o of list || []) {
      if (!o || !o.familyKey) continue;
      const t = o.familyKey.slice(0, o.familyKey.indexOf('|'));
      if (!byTheme.has(t)) byTheme.set(t, new Set());
      byTheme.get(t).add(o.familyKey.slice(t.length + 1));
    }
    const out = new Map();
    for (const [t, fams] of byTheme) {
      const used = new Set();
      for (const f of [...fams].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))) {
        let k = pal.indexOf(HT.autoColor(`family:${t}|${f}`));
        for (let n = 0; n < pal.length && used.has(k); n++) k = (k + 1) % pal.length;
        used.add(k);
        out.set(`${t}|${f}`, HT.pastel(pal[k]));
      }
    }
    for (const o of list || []) if (o && o.familyKey && out.has(o.familyKey)) o.color = out.get(o.familyKey);
    return out;
  };
  /** 집권 기간 칸 이름의 낱말(설계 7-8 3절 제안 2 — 형식은 그대로 · 자유 글): 이 낱말이면 실권 칸(real) · 연정 칸(coal), 모르는 말은 집권(power). 띄어쓰기는 무시.
      단체 종류가 실권 집단(regime)이면 이름과 상관없이 실권 칸 — 집권 단 · 실권 단(js/timeline.js) · 붕당 렌즈가 이 표 하나로 가릅니다 (계보 창 js/group-tree.js의 REAL · COAL과 같은 낱말) */
  HT.POWER_WORDS = { real: ['실권', '섭정', '수렴청정'], coal: ['연정', '공동집권', '공동', '연립', '연립정부'] };
  HT.powerSpanKind = name => {
    const s = String(name == null ? '' : name).replace(/\s+/g, '');
    return HT.POWER_WORDS.real.includes(s) ? 'real' : HT.POWER_WORDS.coal.includes(s) ? 'coal' : 'power';
  };
  /** 붕당 렌즈가 집권 칸으로 쓰지 않는 단체 · 칸: 연합(나라 사이 — 연합 표시는 결정 3), 실권 집단(정권 · 실권 — 실권 단은 결정 2)과 이름이 실권 낱말인 칸 */
  const lensGroupOk = g => !!g && g.type !== 'coalition' && g.type !== 'regime';
  /** 나라 p의 단체 칸 한 줄(want: 'power' 집권 · 'real' 실권): 나라 안 단체(있던 나라 within — 연합은 뺌)의 집권 기간 칸 가운데
      집권 = 실권 집단이 아닌 단체의 실권 낱말이 아닌 칸 · 실권 = 실권 집단(regime)의 칸 + 실권 낱말 칸. 있던 기간(within의 시작 · 끝)으로 자르고, 경계 해마다 잘라
      같은 때 둘 이상이면 연정 칸 하나(단체 수 n · 위아래 두 색 color · color2 · 점은 단체 전부의 색 colors), 맞닿은 같은 단체 모음은 한 칸으로.
      칸 이름이 연정 낱말인데 함께한 단체가 자료에 없으면 '짝을 모르는 연정'(solo — 위 반 제 색 · 아래 반 종이빛 · 점 하나) */
  const groupSpanCells = (p, want) => {
    const segs = [];
    const order = [];
    for (const l of p.groupLinks || []) {
      const g = l.group;
      if (l.role !== 'within' || !g || g.type === 'coalition') continue;
      const rows = (g.withinList || []).filter(w => w.polity === p || (w.polityUid && w.polityUid === p.uid));
      for (const c of g.powerSpans || []) {
        const kind = HT.powerSpanKind(c.name);
        if ((g.type === 'regime' || kind === 'real') !== (want === 'real')) continue;
        for (const w of rows) {
          const a = Math.max(c.start, w.start ?? -Infinity);
          const b = Math.min(c.end, w.end ?? Infinity);
          if (!(b > a)) continue;
          segs.push({ g, c, a, b, coal: kind === 'coal' });
          if (!order.includes(g)) order.push(g);
        }
      }
    }
    if (!segs.length) return [];
    const cuts = [...new Set(segs.flatMap(s => [s.a, s.b]))].sort((x, y) => x - y);
    const out = [];
    for (let i = 0; i + 1 < cuts.length; i++) {
      const t0 = cuts[i];
      const t1 = cuts[i + 1];
      const on = segs.filter(s => s.a <= t0 && s.b >= t1);
      if (!on.length) continue;
      const gs = order.filter(g => on.some(s => s.g === g));
      const solo = gs.length === 1 && on.some(s => s.coal);
      const key = gs.map(g => g.uid).join('|') + (solo ? '|solo' : '');
      const last = out[out.length - 1];
      if (last && last.key === key && last.end === t0) {
        last.end = t1;
        last.endUnknown = on.some(s => s.b === t1 && s.c.endUnknown && s.c.end === t1);
        continue;
      }
      out.push(
        Object.assign(
          {
            key, groups: gs, n: gs.length, name: gs.map(g => g.name).join(' · '), short: gs.map(g => [...g.name][0] || '').join('·'),
            start: t0, end: t1, color: gs[0].color, color2: gs[1] ? gs[1].color : null, colors: gs.map(g => g.color), uids: gs.map(g => g.uid), uid: gs[0].uid,
            startUnknown: on.some(s => s.a === t0 && s.c.startUnknown && s.c.start === t0), endUnknown: on.some(s => s.b === t1 && s.c.endUnknown && s.c.end === t1),
            note: on.map(s => s.c.note).filter(Boolean).join(' · '),
          },
          solo ? { solo: true } : null,
          want === 'real' ? { real: true } : null
        )
      );
    }
    return out;
  };
  /** 붕당 렌즈의 칸 = 집권 단의 칸 (같은 셈 — 렌즈를 켜면 집권 단과 지도자 칸이 자리를 맞바꿈) */
  const lensGroupCells = p => groupSpanCells(p, 'power');
  /** 집권 단 · 실권 단(설계 7-8 결정 1 A · 2 A + 덧판 x1 A · x3 C — 감독 선택 2026-10-12): 나라 p의 { power: 집권 칸, real: 실권 칸, nominal: 명목 지도자 칸의 순번(Set) }.
      명목(지도자 이름 50%)의 고정 기준: 지도자 칸 **제 기간**(끝을 비우면 나라의 끝까지)의 절반 이상이 실권 칸들(합)과 겹침 — 보기 범위 · 화면 폭과 상관없는 자료만의 셈.
      정권마다 기억(모델을 다시 지으면 정권 객체가 새것이라 저절로 비워짐) — 연표의 줄 배치 · 그리기 · 그림 내보내기 · 새 앱 내보내기가 같은 셈 */
  const stripMemo = new WeakMap();
  const STRIP_NONE = Object.freeze({ power: [], real: [], nominal: new Set() });
  HT.groupStrip = p => {
    if (!p || !(p.groupLinks && p.groupLinks.length)) return STRIP_NONE;
    let s = stripMemo.get(p);
    if (s) return s;
    const power = groupSpanCells(p, 'power');
    const real = groupSpanCells(p, 'real');
    const nominal = new Set();
    if (real.length)
      (p.leaders || []).forEach((c, i) => {
        const a = c.start;
        const b = c.end ?? p.endY;
        if (!(b > a)) return;
        const over = real.reduce((n, r) => n + Math.max(0, Math.min(b, r.end) - Math.max(a, r.start)), 0);
        if (over * 2 >= b - a) nominal.add(i);
      });
    s = { power, real, nominal };
    stripMemo.set(p, s);
    return s;
  };
  /** 단체 자동 색의 겹침 막기(설계 7-8 덧판 3절 제안 6 ㉮ · ㉯ — 집권 · 연정 · 실권을 색으로만 가르므로 같은 나라 단체의 색이 같으면 갈리지 않음): 나라마다 그 나라에 있던(within) 단체를
      이름 차례(코드 값 차례 · 같으면 uid)로 놓고, 적은 색(㉯ — 늘 이김)이 먼저 팔레트 자리를 차지한 뒤 자동 색(단체 uid의 해시)이 그 나라의 앞 단체에 이미 쓰인 자리면 다음 자리로
      (열둘이 다 차면 해시 그대로). 여러 나라에 있던 단체는 먼저 만난 나라에서 한 번 정함. 겹침이 없으면 예전 색 그대로(견본 · 옛 파일 모두).
      같은 나라에서 같은 때 함께 집권한 단체의 색이 그래도 같으면(적은 색끼리) 뒤 단체에 경고 — 단체 창의 '확인할 것' · 메이커 검사 창 */
  HT.groupColors = groups => {
    const pal = HT.PASTEL.map(c => c.id);
    const palP = pal.map(c => HT.pastel(c));
    const byPolity = new Map();
    for (const g of groups || [])
      for (const w of g.withinList || []) {
        if (!w.polityUid || g.type === 'coalition') continue;
        if (!byPolity.has(w.polityUid)) byPolity.set(w.polityUid, new Set());
        byPolity.get(w.polityUid).add(g);
      }
    const key = g => String(g.name || '');
    const done = new Set();
    for (const set of byPolity.values()) {
      const list = [...set].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
      const used = new Set();
      for (const g of list) if (!g.colorAuto || done.has(g)) used.add(palP.indexOf(g.color));
      for (const g of list) {
        if (!g.colorAuto || done.has(g)) continue;
        let k = pal.indexOf(HT.autoColor(`group:${g.uid}`));
        for (let n = 0; n < pal.length && used.has(k); n++) k = (k + 1) % pal.length;
        used.add(k);
        g.color = palP[k];
        done.add(g);
      }
      /* 함께 집권한 단체(같은 때 집권 칸 — 실권 칸끼리도)의 색이 같음 */
      const spans = list.flatMap(g => (g.powerSpans || []).filter(c => c.end > c.start).map(c => [g, c.start, c.end]));
      const warned = new Set();
      for (let i = 0; i < spans.length; i++)
        for (let j = 0; j < spans.length; j++) {
          const [a, a0, a1] = spans[i];
          const [b, b0, b1] = spans[j];
          if (a === b || a.color !== b.color || !(a0 < b1 && b0 < a1) || key(a) > key(b) || warned.has(b)) continue;
          warned.add(b);
          (b.warnings || (b.warnings = [])).push(`같은 나라에서 같은 때 함께 집권한 단체 "${a.name}"와(과) 색이 같아 띠에서 갈리지 않습니다 — 둘 중 하나의 색을 바꿔 주세요.`);
        }
    }
  };
  /** 연합 표시(설계 7-8 결정 3 C + 덧판 x2 A): 나라 p가 구성 나라인 연합(type coalition)의 가담 기간 목록 [{ group, start, end, role, note }] — 시작 차례.
      가담 기간 = 구성 나라 줄의 시작 · 끝(비우면 연합의 기간). 띠의 탭 줄에 겹 탭(js/timeline.js _coalTabPlan), 올리면 구성 나라 모두 진하게 */
  const coalMemo = new WeakMap(); // 정권 → 가담 목록 (끄는 동안 탭 자리를 매 장면 다시 셈하므로 — 모델을 다시 지으면 저절로 비워짐)
  HT.coalitionsOf = p => {
    if (!p || !(p.groupLinks && p.groupLinks.length)) return [];
    if (coalMemo.has(p)) return coalMemo.get(p);
    const out = [];
    coalMemo.set(p, out);
    const seen = new Set();
    for (const l of (p && p.groupLinks) || []) {
      const g = l.group;
      if (!g || g.type !== 'coalition' || seen.has(g)) continue;
      seen.add(g);
      for (const m of g.memberList || []) if (m.polity === p || (m.polityUid && m.polityUid === p.uid)) out.push({ group: g, start: m.start, end: m.end, role: m.role || '', note: m.note || '' });
    }
    return out.sort((a, b) => a.start - b.start || a.end - b.end || HT.cmp16(String(a.group.name), String(b.group.name)));
  };
  /** 제도 렌즈의 칸: 그 나라 · 그 주제의 제도들(갈래마다 나눠 적은 제도도)의 칸을 날짜 차례로 — 칸마다 그 제도의 uid · 갈래 · 갈래 색 */
  const lensInstCells = list =>
    list
      .flatMap(o =>
        (o.spanList || []).map(sp => ({
          name: sp.name, start: sp.start, end: sp.end, startUnknown: !!sp.startUnknown, endUnknown: !!sp.endUnknown, guess: !!sp.guess, note: sp.note || '',
          color: o.color, fam: o.family || '', famKey: o.familyKey || '', uid: o.uid, item: o, ii: sp.ii,
        }))
      )
      .sort((a, b) => a.start - b.start || a.end - b.end);
  const lensMemo = new WeakMap(); // 정권 → (주제 id → 칸) — 모델을 다시 지으면 정권 객체가 새것이라 저절로 비워짐
  /** 정권 p의 렌즈 칸 → { src, cells }: src 'inst' 제도 칸 · 'group' 붕당의 집권 칸 · 'rank' 체제를 대신하는 지위 변천(cells = p.rankSpans) · '' 자료 없음 */
  HT.lensCellsOf = (p, id) => {
    if (!p || !id) return { src: '', cells: [] };
    let m = lensMemo.get(p);
    if (!m) lensMemo.set(p, (m = new Map()));
    if (m.has(id)) return m.get(id);
    let r = { src: '', cells: [] };
    const inst = (p.institutionList || []).filter(o => o.themeId === id);
    const gc = id === 'faction' ? lensGroupCells(p) : [];
    if (gc.length) r = { src: 'group', cells: gc };
    else if (inst.length) r = { src: 'inst', cells: lensInstCells(inst) };
    else if (id === 'system' && p.rankSpans && p.rankSpans.length) r = { src: 'rank', cells: p.rankSpans };
    m.set(id, r);
    return r;
  };
  /** 정권 p에 어느 렌즈로든 그릴 칸이 있는지 — 렌즈를 켠 동안의 줄 배치(지도자 칸 자리)를 렌즈 종류와 상관없이 하나로 정합니다(설계 결정 5 'A의 남는 일') */
  HT.lensAny = p => !!p && (!!(p.institutionList && p.institutionList.length) || !!(p.rankSpans && p.rankSpans.length) || (p.groupLinks || []).some(l => l.role === 'within' && lensGroupOk(l.group) && (l.group.powerSpans || []).length > 0));
  /** 사건이 그 렌즈의 주제인지: 주제 꼬리표 + 법률 렌즈는 법 규격이 있는 사건, 선거제도 렌즈는 선거 규격이 있는 사건도 */
  HT.lensEventHit = (e, id) => !!e && !!id && ((e.themeRefs || []).some(r => r.id === id) || (id === 'law' && !!e.law) || (id === 'election' && !!e.election));
  /** 그 렌즈로 그릴 자료가 모델에 하나라도 있는지 (차림표의 '자료 없음' 표시) */
  HT.lensHasData = (m, id) => !!m && !!id && ((m.periods || []).some(p => HT.lensCellsOf(p, id).src !== '') || (m.events || []).some(e => HT.lensEventHit(e, id)));
  /** 렌즈 차림표에 낼 주제: 모델의 주제 사전 차례(내장 여덟 → DLC가 더한 주제) — 렌즈에서 숨긴 주제는 빼고, 사전에 없는 이름으로 적힌 주제(auto)는 자료가 있을 때만 */
  HT.lensThemes = m => ((m && m.themes) || HT.mergeThemes([]).map(t => Object.assign(t, { color: HT.pastel(t.color) }))).filter(t => !t.hidden && (!t.auto || HT.lensHasData(m, t.id)));
  /** 그 해에 걸린 렌즈 칸 (줄 이름 칸의 부제 '— 지금 제도') — 칸의 경계 해는 뒤 칸의 것 */
  HT.lensCellAt = (p, id, t) => {
    const { src, cells } = HT.lensCellsOf(p, id);
    if (!src) return null;
    return cells.find(c => c.start <= t && t < c.end) || cells.find(c => c.start <= t && t <= c.end) || null;
  };
  /** 법 규격: { name?, act?(enact · amend · repeal — 한국어도), articles?: [글], note? } → 적은 칸만 (없으면 null — 보통 사건). 조항은 글 목록(여러 줄 글 하나도 줄마다 나눔) */
  HT.readLaw = (raw, warn = () => {}) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const s = v => (v == null ? '' : String(v).trim());
    const o = {};
    if (s(raw.name)) o.name = s(raw.name);
    if (s(raw.act)) {
      const a = HT.lawAct(raw.act);
      if (a) o.act = a;
      else warn(`법의 고침 종류 "${s(raw.act)}"을(를) 알 수 없어 뺐습니다 (제정 · 개정 · 폐지).`);
    }
    const arts = (Array.isArray(raw.articles) ? raw.articles : typeof raw.articles === 'string' ? raw.articles.split(/\r?\n/) : [])
      .map(a => (typeof a === 'string' || typeof a === 'number' ? String(a) : a && typeof a === 'object' ? [a.no, a.title, a.text].map(s).filter(Boolean).join(' ') : ''))
      .map(t => t.replace(/\r/g, '').trim())
      .filter(Boolean);
    if (arts.length) o.articles = arts;
    if (s(raw.note)) o.note = s(raw.note);
    return Object.keys(o).length ? o : null;
  };
  /** 선거 규격: { office?(뽑은 자리), results?: [{ who, votes?, seats?, won? }], note? } → 적은 칸만 (없으면 null). 득표 · 의석은 수(쉼표 섞인 글도), won은 참이면 당선 */
  HT.readElection = (raw, warn = () => {}) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const s = v => (v == null ? '' : String(v).trim());
    const num = v => {
      if (v == null || v === '') return null;
      const n = Number(String(v).replace(/[,，\s]/g, ''));
      return Number.isFinite(n) && n >= 0 ? n : NaN;
    };
    const o = {};
    if (s(raw.office)) o.office = s(raw.office);
    const rows = Array.isArray(raw.results) ? raw.results : raw.results && typeof raw.results === 'object' ? [raw.results] : [];
    const results = rows
      .map((r, i) => {
        const x = typeof r === 'string' ? { who: r } : Array.isArray(r) ? { who: r[0], votes: r[1], seats: r[2], won: r[3] } : r && typeof r === 'object' ? r : null;
        if (!x) return null;
        const who = s(x.who ?? x.name);
        if (!who) {
          if (['votes', 'seats'].some(k => s(x[k])) || x.won === true) warn(`선거 결과 #${i + 1}: 누구(who)가 없어 뺐습니다.`);
          return null;
        }
        const q = { who };
        for (const [k, word] of [['votes', '득표'], ['seats', '의석']]) {
          const n = num(x[k]);
          if (n == null) continue;
          if (isNaN(n)) warn(`선거 결과 "${who}"의 ${word} "${s(x[k])}"을(를) 읽을 수 없어 뺐습니다.`);
          else q[k] = n;
        }
        if (x.won === true || /^(true|예|네|당선|이김|승리)$/i.test(s(x.won))) q.won = true;
        return q;
      })
      .filter(Boolean);
    if (results.length) o.results = results;
    if (s(raw.note)) o.note = s(raw.note);
    return Object.keys(o).length ? o : null;
  };
  /** 단체가 있던 나라(within) · 연합의 구성 나라(members)의 줄: 이름(또는 id) 글 · "트랙:이름" 글 · { track?, polity, start?, end?, role?, note? } →
      [{ track?, polity, start?(+At · Unknown), end?(+At · Unknown), role?, note? }]. 기간에 "미정"도 됩니다(칸의 미정 — HT.readCellEdge).
      role(연합 안에서의 자리)은 opts.role일 때만. 트랙은 여기서 검사하지 않습니다(다른 DLC · 기본팩의 트랙일 수 있음 — 모델이 못 찾으면 그 항목의 확인할 것에) */
  HT.readPolityRows = (v, { role = false, warn = () => {}, what = '나라' } = {}) => {
    const s = x => (x == null ? '' : String(x).trim());
    const out = [];
    (Array.isArray(v) ? v : v == null || v === '' ? [] : [v]).forEach((x, i) => {
      const r = typeof x === 'string' ? HT.readScopeRef(x) : x && typeof x === 'object' && !Array.isArray(x) ? x : null;
      if (!r) {
        if (x != null && x !== '') warn(`${what} #${i + 1}: 꼴이 올바르지 않아 뺐습니다.`);
        return;
      }
      let track = s(r.track);
      let polity = s(r.polity ?? r.name);
      if (!track && polity) {
        const ref = HT.readScopeRef(polity); // 트랙 칸을 비운 채 "트랙:이름"을 적었으면 둘로 나눔 (대범위 · 조약 당사국과 같은 규칙)
        if (ref && ref.track) [track, polity] = [ref.track, ref.polity];
      }
      if (!polity) {
        warn(`${what} #${i + 1}: 나라가 비어 있어 뺐습니다.`);
        return;
      }
      const o = {};
      if (track) o.track = track;
      o.polity = polity;
      for (const k of ['start', 'end']) {
        const d = HT.readCellEdge(r, k);
        if (!d) continue;
        if (d.unknown) {
          if (d.t != null) o[k] = d.t;
          o[`${k}Unknown`] = true;
          continue;
        }
        if (isNaN(d.t)) {
          warn(`${what} "${polity}"의 ${k === 'start' ? '시작' : '끝'}을 읽을 수 없어 비웠습니다.${d.error ? ` ${d.error}` : ''}`);
          continue;
        }
        o[k] = d.t;
        if (d.at) o[`${k}At`] = d.at;
      }
      if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
        /* 거꾸로면 짐작인 쪽을 버립니다 (활동 기록과 같은 규칙): 시작만 미정이면 시작의 배치용 연도, 아니면 끝 */
        if (o.startUnknown && !o.endUnknown) delete o.start;
        else {
          delete o.end;
          delete o.endAt;
        }
        warn(`${what} "${polity}"의 끝이 시작보다 앞서 ${o.start == null ? '시작의 배치용 연도를' : '끝을'} 버렸습니다.`);
      }
      if (role && s(r.role)) o.role = s(r.role);
      if (s(r.note)) o.note = s(r.note);
      out.push(o);
    });
    return out;
  };
  /** 줄이 하나뿐이고 이름만 있으면 글 하나로 줄여 적습니다 (소속 HT.compactPartOf와 같은 규칙 — 파일이 읽기 쉽게) */
  HT.compactPolityRows = list => (list.length === 1 && Object.keys(list[0]).length === 1 ? list[0].polity : list);
  /** 단체의 앞선 단체(from): 글(단체 이름 · id) · { group, how?(split · merge · rename — 한국어도), note? } → [{ group, how?, note? }] — 같은 단체를 두 번 적으면 첫 줄만 */
  HT.readGroupFrom = (v, warn = () => {}) => {
    const s = x => (x == null ? '' : String(x).trim());
    const out = [];
    (Array.isArray(v) ? v : v == null || v === '' ? [] : [v]).forEach((x, i) => {
      const r = typeof x === 'string' ? { group: x } : x && typeof x === 'object' && !Array.isArray(x) ? x : null;
      const group = r ? s(r.group ?? r.name) : '';
      if (!group) {
        if (x != null && x !== '') warn(`앞선 단체 #${i + 1}: 단체가 비어 있어 뺐습니다.`);
        return;
      }
      if (out.some(y => y.group === group)) return warn(`앞선 단체 "${group}"이(가) 두 번 적혀 있어 첫 줄만 씁니다.`);
      const o = { group };
      if (s(r.how)) {
        const h = HT.groupHow(r.how);
        if (h) o.how = h;
        else warn(`앞선 단체 "${group}": 이어진 방식 "${s(r.how)}"을(를) 알 수 없어 뺐습니다 (갈라짐 · 합쳐짐 · 이름 바꿈).`);
      }
      if (s(r.note)) o.note = s(r.note);
      out.push(o);
    });
    return out;
  };
  /** 제도 칸의 나라: 글(이름 · id · "트랙:이름") · { track, polity } + 제도의 track → { track?, polity } (없으면 null). 객체에 적은 트랙이 제도의 track보다 먼저 */
  HT.readInstPolity = (polity, track) => {
    const s = x => (x == null ? '' : String(x).trim());
    const r = typeof polity === 'string' ? HT.readScopeRef(polity) : polity && typeof polity === 'object' && !Array.isArray(polity) ? { track: s(polity.track), polity: s(polity.polity ?? polity.name) } : null;
    if (!r || !r.polity) return null;
    const t = s(r.track) || s(track);
    return t ? { track: t, polity: r.polity } : { polity: r.polity };
  };
  /** 제도 칸(spans) 원문 → { list, problems: 뺀 것의 글, warnings: 참고할 것의 글 }. 칸은 연호와 같은 꼴 [이름, 시작, 끝, 메모] · { name, start, end, note, from? }.
      비운 시작 · 끝은 시기 구분(HT.readPhases)과 같은 규칙: 첫 칸의 시작을 비우면 나라 시작부터, 끝을 비우면 다음 칸이 시작할 때까지(마지막 칸은 나라 끝까지) — 자리는 모델이 잡습니다.
      시작 · 끝에 "미정"도 됩니다(칸의 미정). from = 다른 나라의 제도에서 옴(전파): { track?, polity, name? } 또는 "나라" · "트랙:나라" 글 */
  HT.readInstSpans = v => {
    const s = x => (x == null ? '' : String(x).trim());
    const problems = [];
    const warnings = [];
    const out = [];
    if (v != null && v !== '' && !Array.isArray(v)) problems.push('제도 칸(spans)은 목록이어야 해서 무시했습니다.');
    (Array.isArray(v) ? v : []).forEach((c, i) => {
      const x = Array.isArray(c) ? { name: c[0], start: c[1], end: c[2], note: c[3] } : typeof c === 'string' ? { name: c } : c && typeof c === 'object' ? c : null;
      if (!x) return problems.push(`제도 칸 ${i + 1}번째: 꼴이 올바르지 않아 뺐습니다.`);
      const name = s(x.name ?? x.title);
      if (!name) return problems.push(`제도 칸 ${i + 1}번째: 이름이 없어 뺐습니다.`);
      const o = { name };
      for (const k of ['start', 'end']) {
        const d = HT.readCellEdge(x, k);
        if (d && d.unknown) {
          if (d.t != null) o[k] = d.t;
          o[`${k}Unknown`] = true;
          continue;
        }
        if (d && isNaN(d.t)) return problems.push(`제도 칸 "${name}"의 ${k === 'start' ? '시작' : '끝'}을 읽을 수 없어 그 칸을 뺐습니다.${d.error ? ` (${d.error})` : ''}`);
        if (d) {
          o[k] = d.t;
          if (d.at) o[`${k}At`] = d.at;
        }
      }
      if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
        if (o.startUnknown && !o.endUnknown) {
          warnings.push(`제도 칸 "${name}"의 끝이 시작보다 앞서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로).`);
          delete o.start;
        } else {
          warnings.push(`제도 칸 "${name}"의 끝이 시작보다 앞서 끝을 비웠습니다(다음 칸까지로 봄).`);
          delete o.end;
          delete o.endAt;
          o.endDropped = true; // 아래 연대 폭 읽기가 세기 글의 끝("3세기 말")을 되살리지 않게 — 알림과 파일이 같게 (정규화 → 내보내기 → 정규화가 한 번에 고정)
        }
      }
      if (s(x.note)) o.note = s(x.note);
      if (x.from != null && x.from !== '') {
        const f = HT.readInstPolity(typeof x.from === 'object' && !Array.isArray(x.from) ? { track: x.from.track, polity: x.from.polity } : x.from, '');
        if (!f) warnings.push(`제도 칸 "${name}": 온 곳(from)에 나라가 없어 뺐습니다.`);
        else {
          if (x.from && typeof x.from === 'object' && s(x.from.name)) f.name = s(x.from.name);
          o.from = f;
        }
      }
      const unc = HT.readUncertain(x, { mode: 'cell', warn: m => warnings.push(`제도 칸 "${name}" — ${m}`), start: o.start, end: o.end }); // 확실성 · 연대 폭 · 이설 (다른 칸과 같은 읽기)
      if (o.endDropped) for (const k of ['end', 'endAt', 'endRange', 'endRangeAt']) delete unc[k];
      delete o.endDropped;
      Object.assign(o, unc);
      out.push(o);
    });
    /* 차례: 적힌 시작 순으로 (시작을 비운 칸은 바로 앞에 적힌 칸 뒤에 그대로 — 시기 구분과 같음) · 겹치면 알림 */
    let key = -Infinity;
    const list = out
      .map((sp, i) => ({ sp, i, k: (key = sp.start != null ? sp.start : key) }))
      .sort((a, b) => (a.k === b.k ? 0 : a.k - b.k) || a.i - b.i)
      .map(x => x.sp);
    for (let i = 0; i + 1 < list.length; i++) {
      const a = list[i];
      const b = list[i + 1];
      if ((a.end != null && b.start != null && a.end > b.start) || (a.start != null && a.start === b.start)) warnings.push(`제도 칸 "${a.name}"와(과) "${b.name}"이(가) 겹칩니다.`);
    }
    return { list, problems, warnings };
  };

  /* ---------- 이름 목록 · 사람 잇기 · 자리 이음 · 혈연 (형식 버전 3 — docs/구상-연표-확장-10건.md 바탕 1 · 2 · 3, 3-1 · 3-2 · 3-3) ----------
   * 이름 목록 names = [{ text, lang?, kind?, start?, end?, note? }] — 시대 · 왕조 · 가문 · 성씨 · 인물 · 지도자 · 내각 · 연호 칸 · 지명 · 사건(제목의 다른 이름)이 같은 꼴 · 같은 읽기(HT.readNames) 하나.
   *   lang = 언어 꼬리표(BCP 47 꼴 — ko · ja · zh-Hant · la · ar, 가상 언어는 x-로 시작: 꼴만 가볍게 봄) · kind = 원어 · 로마자 · 한자음 · 현지음 · 옛 이름 · 약칭(내장 낱말은 id로) 또는 자유 글 ·
   *   start · end = 그 이름을 쓴 기간(날짜 글 · "미정"은 칸과 같은 규칙 — startUnknown · 배치용 연도).
   * 사람 참조 = 인물 id · 이름(글), 또는 지도자 칸 { polity, leader, start?, track? }(글 "나라:지도자@시작 해"도 읽어 객체로).
   * 자리 이음 accession = { kin?, how?, from?, note? } · 혈연 parents = [{ who, as?, gen?, certainty?, note? }] · spouses = [{ who, start?, end?, note? }].
   * 비움(적지 않음)과 "미상"(모른다고 적음 — 모름 · 불명 · ?도)을 구별합니다: 파일에는 kinUnknown · howUnknown · fromUnknown · whoUnknown: true로 남습니다
   *   (대수 미상 ordinalUnknown · 칸의 미정 startUnknown과 같은 꼴 — 글 "미상"을 적어도 읽을 때 이 꼴로). 낱말 표는 내장 뼈대이고 사전에 없는 글도 받습니다(판타지의 의식 · 칭호) */
  HT.NAME_KINDS = [
    { id: 'native', name: '원어' },
    { id: 'roman', name: '로마자' },
    { id: 'sino', name: '한자음' },
    { id: 'local', name: '현지음' },
    { id: 'former', name: '옛 이름' },
    { id: 'short', name: '약칭' },
  ];
  /* 자리 이음의 kin — 앞 지도자과의 관계(이 사람이 앞 지도자의 무엇인가) */
  HT.KIN_TYPES = [
    { id: 'son', name: '아들' },
    { id: 'daughter', name: '딸' },
    { id: 'grandson', name: '손자' },
    { id: 'granddaughter', name: '손녀' },
    { id: 'younger-brother', name: '동생' },
    { id: 'elder-brother', name: '형' },
    { id: 'sister', name: '누이' },
    { id: 'nephew', name: '조카' },
    { id: 'uncle', name: '숙부' },
    { id: 'cousin', name: '사촌' },
    { id: 'son-in-law', name: '사위' },
    { id: 'adopted', name: '양자' },
    { id: 'maternal-grandson', name: '외손' },
    { id: 'spouse', name: '배우자' },
    { id: 'father', name: '아버지' },
    { id: 'mother', name: '어머니' },
    { id: 'collateral', name: '방계' },
    { id: 'unrelated', name: '무관' },
    { id: 'self', name: '본인' },
    /* 세계사 확장(2026-10-23 · docs/점검-세계사-확장-전수조사.md 2-6): 유럽 · 이슬람 · 모계 승계에서 흔한 관계 — 증손(루이 15세 ← 루이 14세) · 의붓자식(네로 ← 클라우디우스) ·
       처남(해럴드 2세 ← 참회왕 에드워드) · 고모 · 이모 · 외삼촌 · 외조카(모계 승계 — 아샨티) · 이복형제(오스만) · 장인 · 며느리. 엔진 names.rs의 표도 함께 */
    { id: 'great-grandson', name: '증손' },
    { id: 'great-granddaughter', name: '증손녀' },
    { id: 'stepson', name: '의붓아들' },
    { id: 'stepdaughter', name: '의붓딸' },
    { id: 'half-brother', name: '이복형제' },
    { id: 'half-sister', name: '이복누이' },
    { id: 'wife-brother', name: '처남' },
    { id: 'sister-husband', name: '매부' },
    { id: 'father-in-law', name: '장인' },
    { id: 'daughter-in-law', name: '며느리' },
    { id: 'paternal-aunt', name: '고모' },
    { id: 'maternal-aunt', name: '이모' },
    { id: 'maternal-uncle', name: '외삼촌' },
    { id: 'sororal-nephew', name: '외조카' },
  ];
  /* 자리 이음의 how — 오른 방식 */
  HT.ACCESSION_HOWS = [
    { id: 'hereditary', name: '세습' },
    { id: 'abdication', name: '선양' },
    { id: 'usurpation', name: '찬탈' },
    { id: 'acclamation', name: '추대' },
    { id: 'election', name: '선출' },
    { id: 'conquest', name: '정복' },
    { id: 'restoration', name: '복위' },
    { id: 'regency', name: '섭정 뒤 오름' },
    { id: 'coup', name: '정변' },
    { id: 'investiture', name: '책봉' },
    /* 세계사 확장(2026-10-23 · 점검 2-6): 혼인으로 얻은 왕위(펠리페 2세의 잉글랜드) · 종주 · 교황 · 칼리파 · 식민 본국의 임명 · 다른 나라 왕위를 혈연으로 받는 상속(합스부르크 — 아버지 → 아들 세습과 가름) ·
       분할 상속(베르됭) · 매입 · 윤번(켈트 타니스트리 · 루스의 측면 승계) · 공동 임명(로마 공동 황제 · 카페의 생전 대관) · 제비(베네치아 도제). 엔진 names.rs의 표도 함께 */
    { id: 'marriage', name: '혼인' },
    { id: 'appointment', name: '임명' },
    { id: 'inheritance', name: '상속' },
    { id: 'partition', name: '분할 상속' },
    { id: 'purchase', name: '매입' },
    { id: 'rotation', name: '윤번' },
    { id: 'co-option', name: '공동 임명' },
    { id: 'lot', name: '제비' },
  ];
  /* 혈연의 as — 이 사람에게 who가 무엇인가 (ancestor = 이 사람이 who의 후손 · gen = 몇 대손) */
  HT.PARENT_ROLES = [
    { id: 'father', name: '부' },
    { id: 'mother', name: '모' },
    { id: 'adoptive-father', name: '양부' },
    { id: 'adoptive-mother', name: '양모' },
    { id: 'birth-father', name: '생부' },
    { id: 'birth-mother', name: '생모' },
    { id: 'ancestor', name: '후손' },
  ];
  const NAME_KIND_WORDS = { 원문: 'native', 원명: 'native', 원어명: 'native', 로마자표기: 'roman', 라틴문자: 'roman', 한자: 'sino', 한자표기: 'sino', 현지: 'local', 현지어: 'local', 옛이름: 'former', 구명: 'former', 옛국호: 'former', 줄임말: 'short', 줄임: 'short', 약자: 'short' };
  const KIN_WORDS = { 왕자: 'son', 장남: 'son', 차남: 'son', 아드님: 'son', 공주: 'daughter', 손: 'grandson', 아우: 'younger-brother', 남동생: 'younger-brother', 형님: 'elder-brother', 오빠: 'elder-brother', 누나: 'sister', 언니: 'sister', 여동생: 'sister', 누이동생: 'sister', 삼촌: 'uncle', 작은아버지: 'uncle', 큰아버지: 'uncle', 종형제: 'cousin', 부마: 'son-in-law', 양아들: 'adopted', 양녀: 'adopted', 외손자: 'maternal-grandson', 외손녀: 'maternal-grandson', 아내: 'spouse', 남편: 'spouse', 왕비: 'spouse', 부인: 'spouse', 부왕: 'father', 아비: 'father', 모후: 'mother', 어미: 'mother', 먼친척: 'collateral', 종친: 'collateral', 남남: 'unrelated', 혈연없음: 'unrelated', 같은사람: 'self',
    /* 세계사 확장(2026-10-23) — 생질은 누이의 아들이라 외조카로(예전엔 조카) */
    증손자: 'great-grandson', 증손녀: 'great-granddaughter', 의붓자식: 'stepson', 계자: 'stepson', 의붓딸: 'stepdaughter', 이복동생: 'half-brother', 이복형: 'half-brother', 배다른형제: 'half-brother', 이복누이: 'half-sister', 이복여동생: 'half-sister', 처남: 'wife-brother', 매제: 'sister-husband', 형부: 'sister-husband', 제부: 'sister-husband', 장인어른: 'father-in-law', 빙부: 'father-in-law', 자부: 'daughter-in-law', 고모님: 'paternal-aunt', 이모님: 'maternal-aunt', 외숙: 'maternal-uncle', 외숙부: 'maternal-uncle', 생질: 'sororal-nephew', 생질녀: 'sororal-nephew', 외조카딸: 'sororal-nephew' };
  const HOW_WORDS = { 물려받음: 'hereditary', 양위: 'abdication', 선위: 'abdication', 왕위찬탈: 'usurpation', 옹립: 'acclamation', 선거: 'election', 침공: 'conquest', 다시오름: 'restoration', 섭정: 'regency', 섭정뒤: 'regency', 반정: 'coup', 쿠데타: 'coup', 봉작: 'investiture',
    /* 세계사 확장(2026-10-23) — '상속'은 이제 제 id(inheritance — 다른 나라 왕위를 혈연으로 받음)이고 세습(hereditary)의 다른 말이 아닙니다 */
    결혼: 'marriage', 혼인상속: 'marriage', 아내의권리: 'marriage', 임명됨: 'appointment', 지명: 'appointment', 파견: 'appointment', 서임: 'appointment', 상속받음: 'inheritance', 유산상속: 'inheritance', 분할: 'partition', 분봉: 'partition', 구입: 'purchase', 사들임: 'purchase', 순번: 'rotation', 돌아가며: 'rotation', 타니스트리: 'rotation', 측면승계: 'rotation', 공동황제: 'co-option', 공동통치자지명: 'co-option', 생전대관: 'co-option', 추첨: 'lot', 제비뽑기: 'lot' };
  const PARENT_WORDS = { 아버지: 'father', 부친: 'father', 어머니: 'mother', 모친: 'mother', 양아버지: 'adoptive-father', 양어머니: 'adoptive-mother', 친부: 'birth-father', 친아버지: 'birth-father', 친모: 'birth-mother', 친어머니: 'birth-mother', 조상: 'ancestor', 선조: 'ancestor', 몇대손: 'ancestor' };
  /** 이름의 종류 · 자리 이음 · 오른 방식 · 혈연: id나 한국어 → id (모르면 '' — 읽는 쪽이 자유 글로 남김) */
  HT.nameKind = vocab(HT.NAME_KINDS, NAME_KIND_WORDS);
  HT.kinId = vocab(HT.KIN_TYPES, KIN_WORDS);
  HT.accessionHow = vocab(HT.ACCESSION_HOWS, HOW_WORDS);
  HT.parentRole = vocab(HT.PARENT_ROLES, PARENT_WORDS);
  /** 보일 이름 — 표의 id면 그 이름, 자유 글이면 그대로 */
  HT.nameKindName = id => vocabName(HT.NAME_KINDS)(id) || String(id ?? '');
  HT.kinName = id => vocabName(HT.KIN_TYPES)(id) || String(id ?? '');
  HT.accessionHowName = id => vocabName(HT.ACCESSION_HOWS)(id) || String(id ?? '');
  HT.parentRoleName = id => vocabName(HT.PARENT_ROLES)(id) || String(id ?? '');
  /** "미상"(모름 · 불명 · ? · 미정)인가 — 비움과 구별해 …Unknown: true로 남깁니다 */
  HT.isUnknownWho = v => typeof v === 'string' && /^(미상|미정|불명|모름|\?|unknown)$/i.test(v.trim());
  /** 언어 꼬리표의 꼴(BCP 47을 가볍게): 앞 조각은 글자 2~8자(가상 언어는 x- 뒤에 조각이 하나 이상), 뒤 조각은 글자 · 숫자 1~8자 */
  HT.isLangTag = s => typeof s === 'string' && /^(?:[a-z]{2,8}(?:-[a-z0-9]{1,8})*|x(?:-[a-z0-9]{1,8})+)$/i.test(s.trim());
  /* 상세 창에 보일 언어 이름 (실제 언어의 이름 — 꼬리표 자체가 표준이라 화면에 그대로 둡니다). 표에 없으면 꼬리표 그대로 */
  const LANG_NAMES = { ko: '한국어', ja: '일본어', zh: '중국어', 'zh-Hant': '중국어 번체', 'zh-Hans': '중국어 간체', lzh: '한문', en: '영어', fr: '프랑스어', de: '독일어', la: '라틴어', el: '그리스어', grc: '고대 그리스어', ar: '아랍어', he: '히브리어', fa: '페르시아어', ru: '러시아어', mn: '몽골어', vi: '베트남어', bo: '티베트어', sa: '산스크리트어', tr: '튀르키예어', 'ko-Latn': '한국어 로마자', 'ja-Latn': '일본어 로마자', 'zh-Latn': '중국어 로마자' };
  HT.langName = tag => {
    const t = String(tag ?? '').trim();
    if (!t) return '';
    if (LANG_NAMES[t]) return LANG_NAMES[t];
    const head = t.split('-')[0];
    return /^x$/i.test(head) ? t : LANG_NAMES[head] ? `${LANG_NAMES[head]} (${t})` : t;
  };
  /**
   * 이름 목록 원문 → 깨끗한 목록 [{ text, lang?, kind?, start?(+At · Unknown), end?(+At · Unknown), note? }] — 적은 칸만.
   * 글 하나(문자열)는 { text }로, text가 빈 줄은 뺍니다. 꼴에 맞지 않는 언어 꼬리표는 알리고 적은 그대로 둡니다(가볍게 — 자료를 버리지 않음).
   * 읽을 수 없는 기간은 그쪽만 비우고, 끝이 시작보다 앞서면 끝을 비웁니다. 같은 글 · 언어 · 종류 · 시작의 줄이 또 나오면 뺍니다. warn(글)은 고친 것을 알립니다
   */
  HT.readNames = (v, warn = () => {}) => {
    const s = x => (x == null ? '' : String(x).trim());
    const list = Array.isArray(v) ? v : v == null || v === '' ? [] : [v];
    const out = [];
    list.forEach((raw, i) => {
      const x = typeof raw === 'string' ? { text: raw } : raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null;
      const text = x ? s(x.text ?? x.name) : '';
      if (!text) {
        if (raw != null && raw !== '') warn(`이름 목록 #${i + 1}: 글(text)이 비어 있어 뺐습니다.`);
        return;
      }
      const o = { text };
      const lang = s(x.lang);
      if (lang) {
        o.lang = lang;
        if (!HT.isLangTag(lang)) warn(`이름 "${text}": 언어 꼬리표 "${lang}"이(가) 꼴에 맞지 않습니다(ko · zh-Hant · x-… 꼴) — 적은 그대로 둡니다.`);
      }
      const kind = s(x.kind);
      if (kind) o.kind = HT.nameKind(kind) || kind;
      for (const k of ['start', 'end']) {
        const d = HT.readCellEdge(x, k);
        if (!d) continue;
        if (d.unknown) {
          if (d.t != null) o[k] = d.t;
          o[`${k}Unknown`] = true;
          continue;
        }
        if (isNaN(d.t)) {
          warn(`이름 "${text}": ${k === 'start' ? '쓰기 시작한' : '그친'} 때를 읽을 수 없어 비웠습니다.${d.error ? ` ${d.error}` : ''}`);
          continue;
        }
        o[k] = d.t;
        if (d.at) o[`${k}At`] = d.at;
      }
      if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
        warn(`이름 "${text}": 그친 때가 쓰기 시작한 때보다 앞서 그친 때를 비웠습니다.`);
        delete o.end;
        delete o.endAt;
      }
      const note = s(x.note);
      if (note) o.note = note;
      if (out.some(y => y.text === o.text && (y.lang || '') === (o.lang || '') && (y.kind || '') === (o.kind || '') && y.start === o.start)) {
        warn(`이름 "${text}"이(가) 두 번 적혀 있어 뒤의 것을 뺐습니다.`);
        return;
      }
      out.push(o);
    });
    return out;
  };
  /** 이름 목록 → 상세 창에 쓸 두 묶음: main = 원어 · 로마자 · 종류 없는 이름(머리 이름 아래 한 줄), other = 나머지(한자음 · 현지음 · 옛 이름 · 약칭 · 자유 글) */
  HT.namesSplit = list => {
    const all = (Array.isArray(list) ? list : []).filter(n => n && n.text);
    const main = all.filter(n => !n.kind || n.kind === 'native' || n.kind === 'roman');
    return { main, other: all.filter(n => !main.includes(n)) };
  };
  /** 이름 목록을 글 하나로(검색 · 설명글): "글 글 …" */
  HT.namesText = list => (Array.isArray(list) ? list : []).map(n => (n && n.text) || '').filter(Boolean).join(' ');

  /* ---------- 원어 표기 · 글자 범위 표 · 글꼴 팩 (10건 3 · 9 — 갈래 D2 구현 · 설계 docs/설계-10건/3-9-원어와-글꼴.md · 감독 선택 docs/설계-10건/감독-선택.md D2) ----------
   * 상세 창 머리(결정 1 A): 이름 아래 두 줄 = 첫 원어(크게) · 첫 로마자(없으면 현지음 → 한자음 — 작게). 언어 · 종류 딱지는 두지 않습니다(감독 "한문, 로마자 등의 표기는 X").
   *   두 줄에 오르지 않은 이름만 '다른 이름 n개' 칸에(HT.namesHead의 rest — 머리의 이름은 칸에 다시 적지 않음).
   * 왼쪽 줄 이름 칸(결정 2 · 감독 "맨 왼쪽 구분표에서만 원어"): 나라 이름 줄에만 원어를 함께 — 띠 표로 그릴 수 없으면 로마자, 그것도 없으면 함께 적지 않음(HT.bandOrig).
   * 그릴 수 있나(결정 4 B): 글자 범위 표 둘 — 띠 표(새 앱의 글자 그림판이 한 글자씩 왼쪽에서 오른쪽으로 놓아 그릴 수 있는 범위 · 왼쪽 칸)와
   *   창 표(문단 그리기가 방향 · 이음을 처리하는 범위 · 상세 창). 이름 글의 모든 글자가 표에 있으면 그리고, 하나라도 없으면 다음 표기로.
   *   화면에 그려 재지 않고 표만 찾으므로 웹 · 내보내기 · 새 앱이 같은 답입니다. 판정 단위는 문자 종류가 아니라 글자 범위(코드 포인트)라
   *   한자 확장 · 옛한글 자모 · 가상 문자(사설 영역)도 가립니다. 켜진 글꼴 팩이 덮는 범위(fonts[].ranges, 없으면 scripts마다 기본 범위)를
   *   두 표에 더합니다 — 띠 표에는 그림판이 그릴 수 있는 범위만(오른쪽에서 왼쪽 · 이어 쓰는 문자 · 결합 부호 · 옛한글 자모는 팩이 있어도 띠 표에 넣지 않음).
   * 보는 사람 설정(ht.ui.names — 파일 아님 · 고르기 전에는 저장하지 않아 지금 사용자는 그대로): { orig: 'none' | 'detail'(기본) | 'band', kinds: { polity, person, place } }.
   *   orig = 원어 없음 · 상세 창만 · 왼쪽 칸에도, kinds = 적용 체크(나라 · 인물 · 지명 — 끈 종류는 '없음'과 같음). 글꼴: ht.ui.fonts = { screen: 글꼴 id | null }(화면 글꼴 — 한글을 덮는 글꼴만) */
  /** 범위 목록 → 겹치거나 이어진 범위를 합친 차례 목록 [[처음, 끝], …] (끝 포함) */
  const mergeRanges = list => {
    const s = list.filter(r => Array.isArray(r) && r[0] <= r[1]).map(r => [r[0], r[1]]).sort((a, b) => a[0] - b[0]);
    const out = [];
    for (const r of s) {
      const last = out[out.length - 1];
      if (last && r[0] <= last[1] + 1) last[1] = Math.max(last[1], r[1]);
      else out.push(r);
    }
    return out;
  };
  /** 범위 목록 a에서 b의 범위를 뺀 목록 */
  const subtractRanges = (a, b) => {
    let cur = mergeRanges(a);
    for (const [lo, hi] of b) {
      const next = [];
      for (const [x, y] of cur) {
        if (y < lo || x > hi) next.push([x, y]);
        else {
          if (x < lo) next.push([x, lo - 1]);
          if (y > hi) next.push([hi + 1, y]);
        }
      }
      cur = next;
    }
    return cur;
  };
  /** 띠 표(내장): 글자 그림판이 한 글자씩 그릴 수 있는 범위 — 웹의 왼쪽 줄 이름 칸도 같은 표(두 앱이 같은 모습) */
  HT.GLYPH_BAND = Object.freeze(
    mergeRanges([
      [0x20, 0x7e], // 라틴 기본(보이는 ASCII)
      [0xa0, 0x24f], // 라틴-1 보충 · 라틴 확장 A · B
      [0x2b0, 0x2ff], // 간격 조정 문자(하와이 ʻ오키나 U+02BB 등 — 2026-10-23 세계사 확장 점검 4-3 · 엔진 glyphs.rs와 함께)
      [0x370, 0x3ff], // 그리스
      [0x400, 0x4ff], // 키릴
      [0x1e00, 0x1eff], // 라틴 확장 추가(베트남어처럼 미리 합친 글자)
      [0x1f00, 0x1fff], // 그리스 확장(고전 그리스어의 숨표 · 악센트 붙은 글자 — 미리 합친 글자라 그림판이 하나씩 놓을 수 있음 · 2026-10-23)
      [0x2010, 0x2027], // 일반 문장 부호 — 줄표 · 따옴표 · 가운뎃점 · 줄임표(보이지 않는 방향 · 이음 표시는 뺌)
      [0x2030, 0x205e],
      [0x3000, 0x303f], // CJK 기호 · 문장 부호
      [0x3040, 0x30ff], // 가나(히라가나 · 가타카나)
      [0x3130, 0x318f], // 한글 호환 자모
      [0x4e00, 0x9fff], // 기본 한자(CJK 통합 한자)
      [0xac00, 0xd7a3], // 한글 음절
      [0xff01, 0xff60], // 전각 꼴(전각 괄호 · 숫자)
      [0xffe0, 0xffe6],
    ])
  );
  /** 창 표(내장): 띠 표 + 문단 그리기가 방향 · 이음 모양을 처리하는 문자(히브리 · 아랍) + 일반 문장 부호 전부(보이지 않는 방향 · 이음 표시 포함).
      한자 확장 · 옛한글 자모는 기기 글꼴마다 달라 넣지 않습니다(좁게 — 설계 확인거리 5의 추천) */
  HT.GLYPH_WINDOW = Object.freeze(mergeRanges(HT.GLYPH_BAND.concat([[0x590, 0x5ff], [0x600, 0x6ff], [0x750, 0x77f], [0x8a0, 0x8ff], [0x2000, 0x206f], [0xfb1d, 0xfb4f], [0xfb50, 0xfdff], [0xfe70, 0xfefe]])));
  /** 글꼴 팩이 있어도 띠 표에는 넣지 않는 범위 — 그림판이 글자를 하나씩 왼쪽에서 오른쪽으로 놓을 뿐이라 그리지 못하는 것
      (결합 부호 · 오른쪽에서 왼쪽 문자 · 이어 쓰는 문자 · 인도계 · 타이 · 티베트 · 몽골 · 옛한글 자모 · 보이지 않는 표시 · 이체자 고르개) */
  const BAND_NEVER = [
    [0x300, 0x36f], [0x483, 0x489], [0x590, 0x8ff], [0x900, 0xdff], [0xe00, 0xeff], [0xf00, 0xfff], [0x1000, 0x109f], [0x1100, 0x11ff], [0x1780, 0x18af],
    [0x1ab0, 0x1aff], [0x1dc0, 0x1dff], [0x200b, 0x200f], [0x202a, 0x202e], [0x2060, 0x206f], [0x20d0, 0x20ff], [0xa960, 0xa97f], [0xd7b0, 0xd7ff],
    [0xfb1d, 0xfdff], [0xfe00, 0xfe0f], [0xfe20, 0xfe2f], [0xfe70, 0xfeff], [0x10800, 0x10fff], [0x1e800, 0x1efff], [0xe0100, 0xe01ef],
  ];
  /** 글꼴 팩이 덮는 범위를 밝히지 않았을 때(fonts[].ranges 없음) 문자 꼬리표(scripts — ISO 15924)마다의 기본 범위.
      가상 문자(Qaaa~Qabx) · 한자 확장 · 옛한글은 기본 범위가 없어 ranges로 적어야 '있음'이 됩니다 */
  HT.SCRIPT_RANGES = Object.freeze({
    Latn: [[0x20, 0x7e], [0xa0, 0x24f], [0x2b0, 0x2ff], [0x1e00, 0x1eff]],
    Grek: [[0x370, 0x3ff], [0x1f00, 0x1fff]],
    Cyrl: [[0x400, 0x4ff]],
    Armn: [[0x530, 0x58f]],
    Hebr: [[0x590, 0x5ff]],
    Arab: [[0x600, 0x6ff], [0x750, 0x77f], [0x8a0, 0x8ff]],
    Syrc: [[0x700, 0x74f]],
    Deva: [[0x900, 0x97f]],
    Beng: [[0x980, 0x9ff]],
    Thai: [[0xe00, 0xe7f]],
    Laoo: [[0xe80, 0xeff]],
    Tibt: [[0xf00, 0xfff]],
    Mymr: [[0x1000, 0x109f]],
    Geor: [[0x10a0, 0x10ff]],
    Ethi: [[0x1200, 0x137f]],
    Khmr: [[0x1780, 0x17ff]],
    Mong: [[0x1800, 0x18af]],
    Hang: [[0x3130, 0x318f], [0xac00, 0xd7a3]],
    Hira: [[0x3040, 0x309f]],
    Kana: [[0x30a0, 0x30ff]],
    Hani: [[0x4e00, 0x9fff]],
    Hans: [[0x4e00, 0x9fff]],
    Hant: [[0x4e00, 0x9fff]],
    Jpan: [[0x3040, 0x30ff], [0x4e00, 0x9fff]],
    Kore: [[0x3130, 0x318f], [0xac00, 0xd7a3], [0x4e00, 0x9fff]],
  });
  /** 글자 범위 글 → [처음, 끝]: "U+F1A00-F1A0B" · "U+4E00" (대소문자 무관 · 끝 포함 · 끝 쪽의 U+는 빼도 됨). 꼴이 틀리면 null */
  HT.parseRange = s => {
    const m = /^\s*U\+([0-9A-F]{1,6})\s*(?:[-–~]\s*(?:U\+)?([0-9A-F]{1,6}))?\s*$/i.exec(String(s ?? ''));
    if (!m) return null;
    const lo = parseInt(m[1], 16);
    const hi = m[2] ? parseInt(m[2], 16) : lo;
    return lo <= hi && hi <= 0x10ffff ? [lo, hi] : null;
  };
  /** [처음, 끝] → "U+F1A00-F1A0B" (하나면 "U+4E00") — 파일에 적는 꼴 */
  HT.rangeText = r => {
    const h = v => v.toString(16).toUpperCase().padStart(4, '0');
    return r[0] === r[1] ? `U+${h(r[0])}` : `U+${h(r[0])}-${h(r[1])}`;
  };
  /** 글꼴(모델의 fonts[] 한 줄)이 덮는 범위 — 적은 ranges, 없으면 scripts마다의 기본 범위 */
  HT.fontRanges = f => {
    if (!f) return [];
    if (Array.isArray(f.ranges) && f.ranges.length) return mergeRanges(f.ranges.map(HT.parseRange).filter(Boolean));
    return mergeRanges([].concat(...(Array.isArray(f.scripts) ? f.scripts : []).map(s => HT.SCRIPT_RANGES[s] || [])));
  };
  const rangesCover = (list, lo, hi) => list.some(r => r[0] <= lo && hi <= r[1]);
  /** 화면 글꼴로 쓸 수 있는 글꼴인가 — 한글 음절 전부(AC00–D7A3)를 덮어야(겹침 금지가 기대는 글 폭 판정이 흔들리지 않게) */
  HT.fontHasHangul = f => rangesCover(HT.fontRanges(f), 0xac00, 0xd7a3);
  /** 켜진 글꼴들(모델의 fonts) → 판정 표 둘 { band, window } — 글꼴이 없으면 내장 표 그대로 */
  HT.glyphTables = (fonts = []) => {
    const add = [].concat(...(Array.isArray(fonts) ? fonts : []).map(HT.fontRanges));
    if (!add.length) return { band: HT.GLYPH_BAND, window: HT.GLYPH_WINDOW };
    return { band: mergeRanges(HT.GLYPH_BAND.concat(subtractRanges(add, BAND_NEVER))), window: mergeRanges(HT.GLYPH_WINDOW.concat(add)) };
  };
  const inRanges = (table, cp) => {
    let lo = 0;
    let hi = table.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const r = table[mid];
      if (cp < r[0]) hi = mid - 1;
      else if (cp > r[1]) lo = mid + 1;
      else return true;
    }
    return false;
  };
  /** 표(띠 표 · 창 표)에 없는 글자들의 코드 포인트(겹치지 않게 · 나온 차례) — 비면 그릴 수 있음. 새 앱은 이 목록만 켜진 팩의 범위로 다시 봅니다 */
  HT.glyphMissing = (text, table = HT.GLYPH_WINDOW) => {
    const out = [];
    for (const ch of String(text ?? '')) {
      const cp = ch.codePointAt(0);
      if (!inRanges(table, cp) && !out.includes(cp)) out.push(cp);
    }
    return out;
  };
  /** 이름 글의 모든 글자가 표에 있는가 (빈 글은 그릴 것이 없어 false) */
  HT.drawable = (text, table = HT.GLYPH_WINDOW) => {
    const s = String(text ?? '');
    if (!s) return false;
    for (const ch of s) if (!inRanges(table, ch.codePointAt(0))) return false;
    return true;
  };
  /** 없는 글자가 어떤 문자인지 — '글꼴 없음' 딱지의 말 (첫째 없는 글자로) */
  const MISSING_SCRIPT_NAMES = [
    ['가상 문자', [[0xe000, 0xf8ff], [0xf0000, 0x10ffff]]],
    ['한자 확장 글자', [[0x3400, 0x4dbf], [0xf900, 0xfaff], [0x20000, 0x3ffff]]],
    ['옛한글', [[0x1100, 0x11ff], [0xa960, 0xa97f], [0xd7b0, 0xd7ff]]],
    ['아랍 문자', [[0x600, 0x6ff], [0x750, 0x77f], [0x8a0, 0x8ff], [0xfb50, 0xfdff], [0xfe70, 0xfeff]]],
    ['히브리 문자', [[0x590, 0x5ff], [0xfb1d, 0xfb4f]]],
    ['결합 부호', [[0x300, 0x36f], [0x1ab0, 0x1aff], [0x1dc0, 0x1dff], [0x20d0, 0x20ff], [0xfe20, 0xfe2f]]],
    ['인도계 문자', [[0x900, 0xdff]]],
    ['타이 문자', [[0xe00, 0xe7f]]],
    ['티베트 문자', [[0xf00, 0xfff]]],
    ['몽골 문자', [[0x1800, 0x18af]]],
  ];
  HT.missingScriptName = (text, table = HT.GLYPH_WINDOW) => {
    const cp = HT.glyphMissing(text, table)[0];
    if (cp == null) return '';
    const hit = MISSING_SCRIPT_NAMES.find(([, rs]) => rs.some(r => r[0] <= cp && cp <= r[1]));
    return hit ? hit[0] : '이 문자';
  };
  /** 상세 창 머리의 이름 셋: first = 첫 원어(kind native), second = 첫 로마자(없으면 현지음 → 한자음), rest = 두 줄에 오르지 않은 나머지(나온 차례) */
  HT.namesHead = list => {
    const all = (Array.isArray(list) ? list : []).filter(n => n && n.text);
    const first = all.find(n => n.kind === 'native') || null;
    const second = all.find(n => n.kind === 'roman') || all.find(n => n.kind === 'local') || all.find(n => n.kind === 'sino') || null;
    return { first, second, rest: all.filter(n => n !== first && n !== second) };
  };
  /** 왼쪽 줄 이름 칸에 함께 적을 이름: 첫 원어 → (띠 표로 그릴 수 없으면) 첫 로마자 → 없음(null — 한국어 이름만) */
  HT.bandOrig = (list, table = HT.GLYPH_BAND) => {
    const all = (Array.isArray(list) ? list : []).filter(n => n && n.text);
    for (const n of [all.find(x => x.kind === 'native'), all.find(x => x.kind === 'roman')]) if (n && HT.drawable(n.text, table)) return n;
    return null;
  };
  /** 보는 사람 설정의 '표기'(ht.ui.names) → 깨끗한 꼴 (없거나 모르는 값은 기본 — 원어: 상세 창만 · 적용 셋 모두) */
  HT.NAMES_ORIG = [
    { id: 'detail', name: '상세 창만' },
    { id: 'none', name: '없음' },
    { id: 'band', name: '왼쪽 칸에도' },
  ];
  HT.namesUi = v => {
    const o = v && typeof v === 'object' ? v : {};
    const k = o.kinds && typeof o.kinds === 'object' ? o.kinds : {};
    return { orig: HT.NAMES_ORIG.some(x => x.id === o.orig) ? o.orig : 'detail', kinds: { polity: k.polity !== false, person: k.person !== false, place: k.place !== false } };
  };
  /**
   * 사람 참조 원문 → 파일의 꼴: 글(인물 id · 이름 — 다듬은 글) · 지도자 칸 { track?, polity, leader, start?(+At) } · null(비움) · undefined(읽지 못함).
   * 글 "나라:지도자@시작 해"는 객체로 바꿉니다("@해"는 없어도 됨 — 같은 이름의 지도자가 여럿이면 첫 칸). "미상"은 부르는 쪽이 먼저 가립니다(…Unknown)
   */
  HT.readPersonRef = v => {
    const s = x => (x == null ? '' : String(x).trim());
    const cellRef = x => {
      const polity = s(x.polity);
      const leader = s(x.leader ?? x.name);
      if (!polity || !leader) return undefined;
      const o = {};
      if (s(x.track)) o.track = s(x.track);
      o.polity = polity;
      o.leader = leader;
      const d = x.start == null || x.start === '' ? null : HT.readDate(x.start, x.startAt);
      if (d && !isNaN(d.t)) {
        o.start = d.t;
        if (d.at) o.startAt = d.at;
      }
      return o;
    };
    if (v == null || v === '') return null;
    if (typeof v === 'number') return String(v);
    if (typeof v === 'string') {
      const t = v.trim();
      if (!t) return null;
      const m = t.match(/^([^:@]+?)\s*:\s*([^@]+?)\s*(?:@\s*(.+))?$/);
      return m ? cellRef({ polity: m[1], leader: m[2], start: m[3] }) : t;
    }
    if (typeof v === 'object' && !Array.isArray(v) && (v.polity != null || v.leader != null)) return cellRef(v);
    return undefined;
  };
  /** 사람 참조 → 한 칸 글(폼의 칸): 글은 그대로, 지도자 칸은 "나라:지도자@시작 해" (트랙은 글에 담지 않음 — 폼은 원래 값을 data-*에 두어 지킴) */
  HT.personRefText = r => (!r ? '' : typeof r === 'string' ? r : `${r.polity}:${r.leader}${r.start != null ? `@${r.startAt || r.start}` : ''}`);
  /** 단체의 구성원(groups[].people — 형식 3, F2 · F1 잇기): 쉼표로 이은 글 하나 · 목록 → 사람 참조 목록(HT.readPersonRef — 인물 id · 이름 글, 지도자 칸 { polity, leader, start? }).
      같은 사람을 두 번 적으면 첫 줄만, 읽지 못한 것은 warn으로 알리고 뺍니다. 사람 자리로 푸는 것은 모델(linkPeople — 인물 · 지도자 칸과 같은 찾기) */
  HT.readGroupPeople = (v, warn = () => {}) => {
    const items = Array.isArray(v) ? v : v == null || v === '' ? [] : typeof v === 'string' ? v.split(/[,，]/) : [v];
    const out = [];
    for (const x of items) {
      if (HT.isUnknownWho(x)) {
        warn(`구성원 "${String(x).trim()}"은(는) 뺐습니다 — 이름 모를 사람은 구성원으로 적지 않습니다(서로 다른 사람이 한 사람으로 묶이지 않게).`);
        continue;
      }
      const r = HT.readPersonRef(x);
      if (r === null) continue;
      if (r === undefined) {
        warn(`구성원 ${typeof x === 'object' ? JSON.stringify(x) : `"${x}"`}을(를) 읽을 수 없어 뺐습니다 (인물의 이름 · id나 지도자 칸 "나라:지도자@시작 해").`);
        continue;
      }
      if (!out.some(q => HT.personRefText(q) === HT.personRefText(r))) out.push(r);
    }
    return out;
  };
  /**
   * 자리 이음 원문 → { kin?, kinUnknown?, how?, howUnknown?, from?, fromUnknown?, note? } (적은 칸만) · null(적은 것이 없음).
   * kin · how는 표의 낱말이면 id로, 아니면 적은 글 그대로(자유 글). 글 "미상" 하나만 적으면 관계 · 방식이 모두 미상입니다.
   * from(앞 지도자)은 비우면 바로 앞 칸 — 다른 사람(형의 아들이 이음 · 복위)이면 사람 참조
   */
  HT.readAccession = (raw, warn = () => {}) => {
    const s = x => (x == null ? '' : String(x).trim());
    if (raw == null || raw === '') return null;
    if (HT.isUnknownWho(raw)) return { kinUnknown: true, howUnknown: true };
    if (typeof raw !== 'object' || Array.isArray(raw)) {
      warn(`자리 이음는 { "kin": …, "how": …, "from": …, "note": … } 꼴로 적습니다 — "${s(raw)}"은(는) 무시했습니다.`);
      return null;
    }
    const o = {};
    for (const [k, read] of [['kin', HT.kinId], ['how', HT.accessionHow]]) {
      if (raw[`${k}Unknown`] === true || HT.isUnknownWho(raw[k])) o[`${k}Unknown`] = true;
      else if (s(raw[k])) o[k] = read(raw[k]) || s(raw[k]);
    }
    if (raw.fromUnknown === true || HT.isUnknownWho(raw.from)) o.fromUnknown = true;
    else if (raw.from != null && raw.from !== '') {
      const r = HT.readPersonRef(raw.from);
      if (r) o.from = r;
      else warn('자리 이음의 앞 지도자(from)을 읽을 수 없어 뺐습니다 — 인물 id · 이름이나 "나라:지도자@시작 해"로 적습니다.');
    }
    if (s(raw.note)) o.note = s(raw.note);
    return Object.keys(o).length ? o : null;
  };
  /** 혈연의 사람 칸(who) 읽기: "미상"이면 { whoUnknown: true }, 아니면 { who } — 읽지 못하면 null */
  const readWho = (x, warn, what) => {
    if (x.whoUnknown === true || HT.isUnknownWho(x.who)) return { whoUnknown: true };
    const r = HT.readPersonRef(x.who ?? x.name);
    if (r) return { who: r };
    warn(`${what} 가운데 사람(who)이 없거나 읽을 수 없는 줄을 뺐습니다 — 모르면 "미상"이라고 적습니다.`);
    return null;
  };
  /**
   * 부모 · 조상 원문 → [{ who | whoUnknown, as?, gen?, certainty?, note? }].
   * as는 표의 낱말이면 id(부 → father …), 아니면 적은 글. gen(몇 대손)은 후손(ancestor)일 때만 — 2 이상의 정수. certainty는 확실성 등급(통설은 적지 않음)
   */
  HT.readParents = (v, warn = () => {}) => {
    const s = x => (x == null ? '' : String(x).trim());
    const out = [];
    for (const raw of Array.isArray(v) ? v : v == null || v === '' ? [] : [v]) {
      const x = typeof raw === 'string' ? { who: raw } : raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null;
      if (!x) continue;
      const w = readWho(x, warn, '부모');
      if (!w) continue;
      const o = Object.assign({}, w);
      if (s(x.as)) o.as = HT.parentRole(x.as) || s(x.as);
      if (x.gen != null && x.gen !== '') {
        const g = Number(x.gen);
        if (o.as !== 'ancestor') warn(`부모 "${HT.personRefText(o.who) || '미상'}": 몇 대손(gen)은 후손(ancestor)일 때만 적습니다 — 뺐습니다.`);
        else if (!Number.isFinite(g) || g < 1) warn(`부모 "${HT.personRefText(o.who) || '미상'}": 몇 대손(gen)은 1 이상의 수로 적습니다 — "${s(x.gen)}"을(를) 뺐습니다.`);
        else o.gen = Math.round(g);
      }
      if (s(x.certainty)) {
        const c = HT.CERTAINTY.find(q => q.id === s(x.certainty) || q.name === s(x.certainty));
        if (!c) warn(`부모 "${HT.personRefText(o.who) || '미상'}": 확실성 "${s(x.certainty)}"을(를) 알 수 없어 뺐습니다.`);
        else if (c.id !== 'accepted') o.certainty = c.id;
      }
      if (s(x.note)) o.note = s(x.note);
      out.push(o);
    }
    return out;
  };
  /** 배우자 원문 → [{ who | whoUnknown, start?(+At · Unknown), end?(+At · Unknown), note? }] — 기간은 칸과 같은 읽기("미정"도) */
  HT.readSpouses = (v, warn = () => {}) => {
    const s = x => (x == null ? '' : String(x).trim());
    const out = [];
    for (const raw of Array.isArray(v) ? v : v == null || v === '' ? [] : [v]) {
      const x = typeof raw === 'string' ? { who: raw } : raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null;
      if (!x) continue;
      const w = readWho(x, warn, '배우자');
      if (!w) continue;
      const o = Object.assign({}, w);
      for (const k of ['start', 'end']) {
        const d = HT.readCellEdge(x, k);
        if (!d) continue;
        if (d.unknown) {
          if (d.t != null) o[k] = d.t;
          o[`${k}Unknown`] = true;
        } else if (isNaN(d.t)) warn(`배우자 "${HT.personRefText(o.who) || '미상'}": ${k === 'start' ? '시작' : '끝'} 날짜를 읽을 수 없어 비웠습니다.${d.error ? ` ${d.error}` : ''}`);
        else {
          o[k] = d.t;
          if (d.at) o[`${k}At`] = d.at;
        }
      }
      if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
        warn(`배우자 "${HT.personRefText(o.who) || '미상'}": 끝이 시작보다 앞서 끝을 비웠습니다.`);
        delete o.end;
        delete o.endAt;
      }
      if (s(x.note)) o.note = s(x.note);
      out.push(o);
    }
    return out;
  };
  /** 좌표 [x, y] — 두 수(글로 적은 수도). 아니면 null (지명의 at) */
  HT.readCoords = v => {
    const a = Array.isArray(v) ? v : typeof v === 'string' ? v.split(/[,，\s]+/).filter(Boolean) : null;
    if (!a || a.length !== 2) return null;
    const n = a.map(x => (x === '' || x == null ? NaN : Number(x)));
    return n.every(Number.isFinite) ? n : null;
  };

  /* ---------- 배열 기준 · 남북 값 · 간지 설정 (형식 버전 3 — docs/설계-10건/6-모아-보기와-배치.md 결정 6 · 8, 감독 선택 D4 6 C · 8 B) ----------
   * 배열 기준(peoples[].rowOrder): 그 민족 묶음 안(제 줄과 하위 민족 — 하위 민족은 제 값을 적지 않으면 물려받음)의 위아래 차례.
   *   'start'(지금 규칙 — 시작 해) · 'northSouth'(북 → 남 — 남북 값이 큰 것이 위, 값이 없는 줄은 값이 있는 줄들 뒤에 시작 해 차례로).
   *   묶음 사이(트랙 맨 위 단)에 거는 값은 두지 않습니다(감독 선택 6 C). 적지 않으면 지금 그대로라 옛 파일은 1px도 다르지 않습니다.
   * 남북 값(periods[].northSouth): 수 · 클수록 북. 적지 않으면 첫 정도(정식 도읍 가운데 시작이 가장 이른 칸)의 지명 좌표에서(모델 — linkOrder).
   * 간지 설정(최상위 yearCycle): false = 날짜 칸의 간지 줄을 기본으로 끔(보는 사람이 필터 '간지'로 다시 켬) ·
   *   { names, start, label } = 육십갑자 대신 이 순환(start 해가 names의 첫 이름). 비우면 육십갑자(내장 뼈대) — 여러 DLC면 먼저 켠 DLC의 것 */
  HT.ROW_ORDERS = [
    { id: 'start', name: '시작 연도', hint: '먼저 시작한 줄이 위 (기본 — 지금 규칙)' },
    { id: 'northSouth', name: '북 → 남', hint: '남북 값이 큰(북쪽) 줄이 위 — 값은 나라의 남북 위치, 없으면 첫 정도의 지명 좌표' },
  ];
  const ROW_ORDER_WORDS = { 시작: 'start', '시작 해': 'start', 시작해: 'start', '시작 연도': 'start', 연도: 'start', 남북: 'northSouth', 북남: 'northSouth', '북 → 남': 'northSouth', '북→남': 'northSouth', '북에서 남': 'northSouth', 'north-south': 'northSouth', northsouth: 'northSouth' };
  /** 배열 기준 글 → 'start' · 'northSouth' (빈 값 '' · 모르는 값 null). 한국어 낱말도 읽습니다(물려받은 이름 — '__proto__' 같은 — 은 낱말로 보지 않음) */
  HT.readRowOrder = v => {
    const s = String(v ?? '').trim();
    if (!s) return '';
    if (HT.ROW_ORDERS.some(o => o.id === s)) return s;
    const k = Object.prototype.hasOwnProperty.call(ROW_ORDER_WORDS, s) ? s : s.toLowerCase();
    return Object.prototype.hasOwnProperty.call(ROW_ORDER_WORDS, k) ? ROW_ORDER_WORDS[k] : null;
  };
  HT.rowOrderName = id => (HT.ROW_ORDERS.find(o => o.id === id) || HT.ROW_ORDERS[0]).name;
  /** 남북 값 → 수 (빈 값 undefined · 읽지 못하면 NaN). 글로 적은 수("38.5")도 읽습니다 */
  HT.readNorthSouth = v => {
    if (v == null || (typeof v === 'string' && !v.trim())) return undefined;
    const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v.trim()) : NaN;
    return Number.isFinite(n) ? n : NaN;
  };
  /** 사건의 자리(spot) → 0~1의 수(소수 셋째 자리까지) · 읽지 못하거나 범위 밖이면 undefined. 글로 적은 수("0.3")도 읽습니다 */
  HT.readSpot = v => {
    const n = typeof v === 'number' ? v : typeof v === 'string' && v.trim() ? Number(v.trim()) : NaN;
    return Number.isFinite(n) && n >= 0 && n <= 1 ? Math.round(n * 1000) / 1000 : undefined;
  };
  HT.YEAR_CYCLE_LIMITS = { names: 240, nameLen: 20, label: 20 };
  const YEAR_CYCLE_KEYS = ['names', 'start', 'startAt', 'label'];
  /** 간지 설정(yearCycle) 읽기 → undefined(적지 않음 · 육십갑자) · false(간지 줄 기본 끔) · { names, start, label? } — 읽지 못한 것은 warn(글)로 알리고 버립니다 */
  HT.readYearCycle = (v, warn = () => {}) => {
    if (v === undefined || v === null) return undefined;
    if (v === false || (typeof v === 'string' && ['끔', 'off', 'false'].includes(v.trim()))) return false;
    if (v === true || (typeof v === 'string' && !v.trim())) {
      if (v === true) warn('간지 설정(yearCycle)의 true는 적지 않은 것과 같아(육십갑자) 뺐습니다 — 끄려면 false, 다른 순환이면 { "names", "start" }.');
      return undefined;
    }
    if (typeof v !== 'object' || Array.isArray(v)) {
      warn('간지 설정(yearCycle)은 false나 { "names", "start", "label" } 꼴이어야 해서 무시했습니다.');
      return undefined;
    }
    const L = HT.YEAR_CYCLE_LIMITS;
    for (const k of Object.keys(v)) if (!YEAR_CYCLE_KEYS.includes(k)) warn(`간지 설정(yearCycle)의 "${k}"은(는) 모르는 칸이라 버렸습니다.`);
    let names = (Array.isArray(v.names) ? v.names : typeof v.names === 'string' ? v.names.split(/[,，]/) : []).map(x => String(x ?? '').trim()).filter(Boolean);
    if (names.some(x => x.length > L.nameLen)) {
      warn(`간지 설정: 명칭은 하나에 ${L.nameLen}자까지라 넘친 것을 잘랐습니다.`);
      names = names.map(x => x.slice(0, L.nameLen));
    }
    if (names.length > L.names) {
      warn(`간지 설정: 명칭은 ${L.names}개까지라 뒤의 것을 버렸습니다.`);
      names = names.slice(0, L.names);
    }
    if (names.length < 2) {
      warn('간지 설정(yearCycle)의 명칭 목록(names)이 둘 이상이어야 해서 무시했습니다(육십갑자 그대로).');
      return undefined;
    }
    const o = { names };
    const d = v.start == null || v.start === '' ? null : HT.readDate(v.start, v.startAt);
    if (!d || isNaN(d.t) || Math.floor(d.t + 1e-9) === 0) {
      warn(`간지 설정: 기준 연도(start — 첫 명칭의 해)${d ? '를 읽을 수 없어' : '가 없어'} 1년으로 봅니다.`);
      o.start = 1;
    } else o.start = Math.floor(d.t + 1e-9);
    const label = String(v.label ?? '').trim();
    if (label) o.label = label.slice(0, L.label);
    if (label.length > L.label) warn(`간지 설정: 줄 제목(label)은 ${L.label}자까지라 잘랐습니다.`);
    return o;
  };
  /* ---------- 문화권별 주기 줄 (형식 4 더하기 yearCycles — DLC-형식.md '형식 4 더하기' · 리메이크 5단계 과제 6) ----------
   * 문화권마다 날짜 칸 아래 주기 줄 하나: [{ sphere?, names, start, label? } | { sphere?, era, from, step, label? }].
   *   이름 돌림(names · start — 최상위 yearCycle과 같은 뜻 · 읽는 규칙도 같음) 또는 연호 눈금(era · from(원년) · step(몇 해마다) — "빙원 410년"처럼 셈).
   *   sphere를 비우면 전체 줄 — 전체 줄의 이름 돌림은 최상위 yearCycle과 같은 것이라 메이커가 둘을 맞춥니다(HT.syncYearCycles). 문화권마다 한 줄(겹치면 뒤의 것을 뺌)
   * 육십갑자 예약 값(리메이크 6단계 결정 16 · 2026-10-24): names에 글 "육십갑자"(또는 "sexagenary" · 그 낱말 하나뿐인 목록 — 메이커 「주기」 표)를 적거나 names 없이 builtin: "sexagenary"만 적으면 내장 육십갑자 —
   *   정규화가 이름 60개(갑자 ~ 계해) + 기준 해 4(서기 4년 = 갑자년 · HT.ganjiIndex)로 펴고 표지 builtin: 'sexagenary'를 둡니다(기준 해 start는 버림 · 줄 제목은 그대로).
   *   내보내기는 펴진 이름 돌림을 그대로 쓰고, 표지는 '날마다의 간지(일진)도 그릴 수 있는 진짜 육십갑자'를 가릅니다. 표지가 있는데 이름 · 기준 해가 육십갑자와 다르면(메이커에서 고침) 표지를 빼고 다른 순환으로 읽습니다 */
  const YEAR_CYCLES_KEYS = ['sphere', 'names', 'start', 'startAt', 'label', 'era', 'from', 'fromAt', 'step', 'builtin'];
  HT.SEXAGENARY = 'sexagenary';
  const SEXAGENARY_WORDS = ['육십갑자', 'sexagenary'];
  const SEXAGENARY_START = 4;
  const sexagenaryNames = () => Array.from({ length: 60 }, (_, k) => STEMS[k % 10] + BRANCHES[k % 12]);
  /** names가 예약 글인가 — 글 하나 또는 그 낱말 하나뿐인 목록 */
  const sexagenaryWord = v => {
    const w = typeof v === 'string' ? v : Array.isArray(v) && v.length === 1 && typeof v[0] === 'string' ? v[0] : null;
    return w != null && SEXAGENARY_WORDS.includes(w.trim());
  };
  /** 주기 줄(읽기 전 원본도)이 내장 육십갑자인가 — names가 예약 글이거나 표지 builtin이 'sexagenary' */
  HT.isSexagenaryRow = c => !!c && typeof c === 'object' && (sexagenaryWord(c.names) || String(c.builtin ?? '').trim() === HT.SEXAGENARY);
  /** 문화권별 주기 줄(yearCycles) 읽기 → 읽힌 줄의 목록. 읽지 못한 줄은 warn(글, 줄 번호)로 알리고 버립니다 */
  HT.readYearCycles = (v, warn = () => {}) => {
    if (v === undefined || v === null) return [];
    if (!Array.isArray(v)) {
      warn('문화권별 주기 줄(yearCycles)은 목록이어야 해서 무시했습니다.');
      return [];
    }
    const L = HT.YEAR_CYCLE_LIMITS;
    const out = [];
    v.forEach((c, i) => {
      const label = `주기 줄 #${i + 1}`;
      if (!c || typeof c !== 'object' || Array.isArray(c)) return warn(`${label}: 형식이 올바르지 않습니다.`, i);
      for (const k of Object.keys(c)) if (!YEAR_CYCLES_KEYS.includes(k)) warn(`${label}: "${k}"은(는) 모르는 칸이라 버렸습니다.`, i);
      const o = {};
      const sp = String(c.sphere ?? '').trim();
      if (sp) {
        if (!HT.ID_RE.test(sp)) return warn(`${label}: 문화권 id "${sp}"이(가) 올바르지 않아 줄을 뺐습니다.`, i);
        o.sphere = sp;
      }
      const bi = String(c.builtin ?? '').trim();
      if (bi && bi !== HT.SEXAGENARY) warn(`${label}: 내장 순환 표지(builtin) "${bi}"을(를) 알 수 없어 버렸습니다(육십갑자는 "${HT.SEXAGENARY}").`, i);
      const reserved = sexagenaryWord(c.names) || (bi === HT.SEXAGENARY && c.names == null);
      const hasNames = reserved || (Array.isArray(c.names) ? c.names.length > 0 : typeof c.names === 'string' && !!c.names.trim());
      const era = String(c.era ?? '').trim();
      if (hasNames) {
        if (era) warn(`${label}: 이름 돌림(names)과 연호 눈금(era)을 함께 적어 이름 돌림으로 읽고 연호 눈금은 버렸습니다.`, i);
        const yc = HT.readYearCycle(reserved ? { names: sexagenaryNames(), start: SEXAGENARY_START, label: c.label } : { names: c.names, start: c.start, startAt: c.startAt, label: c.label }, m => warn(`${label}: ${m}`, i));
        if (!yc || typeof yc !== 'object') return;
        Object.assign(o, yc);
        if (reserved) o.builtin = HT.SEXAGENARY;
        else if (bi === HT.SEXAGENARY) {
          const six = sexagenaryNames();
          if (o.start === SEXAGENARY_START && o.names.length === six.length && o.names.every((n, k) => n === six[k])) o.builtin = HT.SEXAGENARY;
          else warn(`${label}: 내장 육십갑자 표지(builtin)가 있지만 명칭 목록 · 기준 연도가 육십갑자와 달라 표지를 빼고 다른 순환으로 읽습니다.`, i);
        }
      } else if (era) {
        if (era.length > L.label) warn(`${label}: 연호(era)는 ${L.label}자까지라 잘랐습니다.`, i);
        o.era = era.slice(0, L.label);
        const d = c.from === undefined || c.from === null || c.from === '' ? null : HT.readDate(c.from, c.fromAt);
        if (!d || isNaN(d.t)) return warn(`${label}: 연호 눈금의 원년(from)${d ? '을 읽을 수 없어' : '이 없어'} 줄을 뺐습니다.`, i);
        o.from = Math.floor(d.t + 1e-9);
        const st = c.step === undefined || c.step === null || c.step === '' ? 1 : Number(c.step);
        if (!Number.isInteger(st) || st < 1) {
          warn(`${label}: 눈금 간격(step)은 1 이상의 정수여야 해서 1로 봅니다.`, i);
          o.step = 1;
        } else o.step = st;
        const lb = String(c.label ?? '').trim();
        if (lb.length > L.label) warn(`${label}: 줄 제목(label)은 ${L.label}자까지라 잘랐습니다.`, i);
        if (lb) o.label = lb.slice(0, L.label);
      } else return warn(`${label}: 이름 돌림(names)도 연호 눈금(era)도 없어 줄을 뺐습니다.`, i);
      if (out.some(x => (x.sphere || '') === (o.sphere || ''))) return warn(`${label}: ${o.sphere ? `문화권 "${o.sphere}"` : '전체'}의 주기 줄이 앞에 있어 뒤의 것을 뺐습니다(문화권마다 한 줄).`, i);
      out.push(o);
    });
    return out;
  };
  /** 주기 줄 목록의 전체 줄(문화권 없음 · 이름 돌림) → 최상위 yearCycle 꼴 { names, start, label? } — 없으면 null. 내장 육십갑자 줄(표지 builtin)은 최상위 yearCycle을 비운 것과 같아 고르지 않습니다 */
  HT.wholeYearCycle = list => {
    const c = (Array.isArray(list) ? list : []).find(x => x && typeof x === 'object' && !Array.isArray(x) && !String(x.sphere ?? '').trim() && Array.isArray(x.names) && !HT.isSexagenaryRow(x));
    if (!c) return null;
    const o = { names: c.names.slice() };
    if (c.start !== undefined && c.start !== null && c.start !== '') o.start = c.start;
    if (c.label !== undefined && c.label !== null && c.label !== '') o.label = c.label;
    return o;
  };
  /** 메이커의 두 입력 — 정보 창의 간지 설정(최상위 yearCycle)과 「주기」 표(yearCycles)의 전체 줄 — 을 맞춥니다.
      from = 'cycle'(간지 설정을 고침 → 전체 줄을 그에 맞게: 다른 순환이면 전체 줄을 두고, 육십갑자 · 끔이면 전체 줄을 뺌) · 'rows'(표를 고침 → 간지 설정을 전체 줄에서: 전체 줄이 없으면 다른 순환을 지움 · 끔(false)은 그대로).
      작업본(옛 꼴 JSON)을 바로 고치고, 바뀌었는지를 돌려줍니다. 정규화 · 열기(clean)에서는 부르지 않습니다 — 옛 파일을 열어 그대로 저장하면 1바이트도 다르지 않게 */
  HT.syncYearCycles = (draft, from) => {
    if (!draft || typeof draft !== 'object' || Array.isArray(draft)) return false;
    const snap = () => JSON.stringify([draft.yearCycle === undefined ? null : draft.yearCycle, draft.yearCycles === undefined ? null : draft.yearCycles]);
    const before = snap();
    const rows = Array.isArray(draft.yearCycles) ? draft.yearCycles : [];
    const isWhole = c => c && typeof c === 'object' && !Array.isArray(c) && !String(c.sphere ?? '').trim() && Array.isArray(c.names);
    if (from === 'cycle') {
      const yc = draft.yearCycle;
      if (yc && typeof yc === 'object' && !Array.isArray(yc)) {
        const row = Object.assign({ names: Array.isArray(yc.names) ? yc.names.slice() : typeof yc.names === 'string' ? yc.names.split(/[,，]/).map(s => s.trim()).filter(Boolean) : [] }, yc.start !== undefined && yc.start !== null && yc.start !== '' ? { start: yc.start } : {}, yc.label ? { label: yc.label } : {});
        const i = rows.findIndex(isWhole);
        if (i >= 0) rows[i] = row;
        else rows.unshift(row);
        draft.yearCycles = rows;
      } else {
        const kept = rows.filter(c => !isWhole(c) || HT.isSexagenaryRow(c)); // 육십갑자 · 끔이면 다른 순환의 전체 줄만 뺌 — 내장 육십갑자 전체 줄(표지 builtin)은 육십갑자와 같은 뜻이라 둠(6단계 결정 16)
        if (kept.length !== rows.length) draft.yearCycles = kept;
      }
    } else {
      const w = HT.wholeYearCycle(rows);
      if (w) draft.yearCycle = w;
      else if (draft.yearCycle && typeof draft.yearCycle === 'object') delete draft.yearCycle;
    }
    if (Array.isArray(draft.yearCycles) && !draft.yearCycles.length) delete draft.yearCycles;
    return snap() !== before;
  };
  const cycleAstro = y => {
    const n = Math.floor(y + 1e-9);
    return n < 0 ? n + 1 : n; // 0년이 없는 연표의 해 → 천문 연도 (HT.ganji와 같은 셈)
  };
  /** 간지 설정(모델의 yearCycle — 없거나 끔이면 육십갑자)에서 그 해의 순번 · 이름 · 줄 이름 · 한 바퀴의 해 수 */
  HT.cycleIndex = (cycle, y) => {
    if (!cycle || !Array.isArray(cycle.names) || cycle.names.length < 2) return HT.ganjiIndex(y);
    const n = cycle.names.length;
    return (((cycleAstro(y) - cycleAstro(cycle.start)) % n) + n) % n;
  };
  HT.cycleName = (cycle, y) => (cycle && Array.isArray(cycle.names) && cycle.names.length >= 2 ? cycle.names[HT.cycleIndex(cycle, y)] : HT.ganji(y));
  HT.cycleLabel = cycle => (cycle && Array.isArray(cycle.names) && cycle.names.length >= 2 ? cycle.label || '간지' : '간지');
  HT.cycleLength = cycle => (cycle && Array.isArray(cycle.names) && cycle.names.length >= 2 ? cycle.names.length : 60);
  /** 넓게 볼 때의 눈금: start ~ end 안에서 한 바퀴의 첫 해(첫 이름 · 육십갑자는 갑자년)들 — 보이는 해(0년 없음)로. 육십갑자는 예전 날짜 칸과 같은 셈 */
  HT.cycleFirstYears = (cycle, start, end) => {
    const n = HT.cycleLength(cycle);
    const base = cycle && Array.isArray(cycle.names) && cycle.names.length >= 2 ? cycleAstro(cycle.start) : 4;
    const out = [];
    const lo = start < 1 ? start + 1 : start; // 보이는 해 → 천문 연도 (0년 없음 — 기원전 1년 = 0)
    for (let a = Math.ceil((lo - base) / n) * n + base; out.length < 2000; a += n) {
      const y = a <= 0 ? a - 1 : a;
      if (y > end) break;
      out.push(y);
    }
    return out;
  };
  /** 보는 사람의 간지 줄(필터 '간지' — ui.show.ganji)을 모델의 간지 설정에 맞춤: DLC가 끈 순환(yearCycle: false)은 그 DLC를 처음 볼 때 한 번만 끄고
      (ui.cycleSeen — 그 뒤로 보는 사람이 다시 켜면 그대로 · 보는 사람이 바꾼 것이 늘 이김), 그 DLC가 꺼져 순환이 돌아오면 저절로 끈 것만 다시 켭니다(ui.cycleAutoOff).
      ui를 고쳤으면 true — 부르는 쪽(js/viewer.js의 refresh)이 체크 상자를 맞추고 저장합니다 */
  HT.yearCycleUi = (ui, model) => {
    if (!ui || typeof ui !== 'object') return false;
    const c = model && model.yearCycle;
    const show = Object.assign({}, ui.show);
    let changed = false;
    if (c && c.off) {
      const seen = Array.isArray(ui.cycleSeen) ? ui.cycleSeen : [];
      if (!seen.includes(c.packId)) {
        ui.cycleSeen = seen.concat([c.packId]);
        if (show.ganji !== false) {
          ui.show = Object.assign(show, { ganji: false });
          ui.cycleAutoOff = true;
          changed = true;
        }
      }
    } else if (ui.cycleAutoOff) {
      delete ui.cycleAutoOff;
      if (show.ganji === false) {
        ui.show = Object.assign(show, { ganji: true });
        changed = true;
      }
    }
    return changed;
  };

  /* ---------- 유틸 ---------- */
  HT.escapeHtml = s =>
    String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  HT.hash = str => {
    let h = 5381;
    for (let i = 0; i < str.length; i++) h = ((h << 5) + h + str.charCodeAt(i)) | 0;
    return (h >>> 0).toString(36);
  };
  HT.uid = (prefix = 'id') => `${prefix}-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  HT.autoColor = key => PALETTE[parseInt(HT.hash(String(key)), 36) % PALETTE.length];
  HT.clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  HT.isColor = c => typeof c === 'string' && /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(c);

  HT.toast = (message, type = 'info') => {
    let box = document.querySelector('.toast-box');
    if (!box) {
      box = document.createElement('div');
      box.className = 'toast-box';
      document.body.appendChild(box);
    }
    const el = document.createElement('div');
    el.className = `toast toast-${type}`;
    el.textContent = message;
    box.appendChild(el);
    const ms = Math.min(9000, Math.max(3200, String(message).length * 70)); // 긴 알림(옛 내 수정을 옮겼다는 글 같은)은 읽을 만큼 더 머뭅니다
    setTimeout(() => el.classList.add('is-out'), ms);
    setTimeout(() => el.remove(), ms + 400);
  };

  /* ---------- 움직임: 토큰 · 한 시계 · 스프링 ----------
     길이와 곡선의 원본은 css/common.css :root의 변수(--t-micro · --t-out · --t-in · --t-move · --ease · --spring)이고,
     JS는 그 값을 한 번 읽어 같은 숫자를 씁니다 (docs/움직임-개선안.md 4절). "동작 줄이기"가 켜지면 CSS가 토큰을 바꾸므로 여기도 따라갑니다 */
  HT.motion = (() => {
    const FALLBACK = { micro: 120, out: 160, in: 200, move: 360, ease: 'cubic-bezier(.25, .8, .25, 1)', spring: 'cubic-bezier(.32, .72, 0, 1)' };
    const T = {}; // 길이(ms): micro · out · in · move
    const C = {}; // 곡선(CSS 글자 그대로): ease · spring
    const read = () => {
      let cs = null;
      try {
        cs = getComputedStyle(document.documentElement);
      } catch (err) {
        /* 문서가 없는 곳(검사 도구 등)에서는 기본값 */
      }
      for (const k of ['micro', 'out', 'in', 'move']) {
        const v = cs ? cs.getPropertyValue(`--t-${k}`).trim() : '';
        const n = parseFloat(v);
        T[k] = isNaN(n) ? FALLBACK[k] : /ms$/i.test(v) ? n : /s$/i.test(v) ? n * 1000 : n;
      }
      for (const k of ['ease', 'spring']) C[k] = (cs && cs.getPropertyValue(`--${k}`).trim()) || FALLBACK[k];
    };
    read();
    try {
      matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', read);
    } catch (err) {
      /* 옛 브라우저: 처음 읽은 값 그대로 */
    }

    /* ---------- 한 시계 · 느리게 보기 ----------
       rate(1 · 0.25 · 0.1)만큼 천천히 가는 가상 시계 하나로 움직임의 시간을 잽니다: JS 움직임은 now()로 시각을, later()로 "조금 뒤"를 재고,
       CSS 전환·키프레임·WAAPI는 rate가 1이 아닌 동안 매 프레임 playbackRate를 rate에 맞춥니다(1로 돌아오면 되돌림).
       rate가 1이면 now()는 performance.now()와, later()는 setTimeout과 똑같습니다. 사람의 뜻을 기다리는 타이머(카드 호버 등)는 여기로 옮기지 않습니다 */
    let rate = 1;
    let vBase = 0; // 가상 시각 = vBase + (실제 시각 − rBase) × rate — rate가 바뀌어도 끊기지 않고 이어집니다
    let rBase = 0;
    let paceRaf = 0;
    /** 지금의 가상 시각(ms). rAF가 준 시각처럼 실제 시각을 넘기면 그 시각의 가상 시각으로 바꿔 줍니다 */
    const now = (real = performance.now()) => vBase + (real - rBase) * rate;
    /** setTimeout의 느리게 보기판 — 돌려준 id는 clearTimeout으로 취소. 이미 걸린 타이머는 rate가 바뀌어도 다시 맞추지 않습니다 */
    const later = (ms, fn) => setTimeout(fn, rate === 1 ? ms : ms / rate);
    const pace = () => {
      for (const a of document.getAnimations()) if (a.playbackRate !== rate) a.playbackRate = rate;
      paceRaf = rate === 1 ? 0 : requestAnimationFrame(pace);
    };
    const setRate = r => {
      r = Number(r);
      if (!(r > 0) || r === rate) return;
      const real = performance.now();
      vBase = now(real);
      rBase = real;
      rate = r;
      cancelAnimationFrame(paceRaf);
      pace();
    };

    /** 닫힌해 임계감쇠 스프링 — 되튐 0, 빠르기는 response(초) 하나. set()은 지금 값과 "지금 속도"에서 새 목표로 이어 갑니다(속도를 버리지 않음).
        수치 적분이 아니라서 프레임 시간이 흔들려도 같은 시각에 같은 값이 나옵니다. 시간은 now()로 재므로 느리게 보기와 함께 느려집니다.
        쓰는 법: const s = new HT.motion.Spring(0, { response: .36 }); s.set(100); 그리고 매 프레임 s.value() · s.velocity()(초당) · s.done().
        한 프레임의 여러 스프링을 같은 시각으로 재려면 t = HT.motion.now()를 한 번 구해 value(t) · done(t)로 넘깁니다 */
    class Spring {
      constructor(value = 0, { response = 0.36, restDelta = 0.01, restSpeed = 0.1 } = {}) {
        this.response = response;
        this.restDelta = restDelta; // 멈춤 판정: 목표까지 이만큼(값의 단위) 안쪽이고
        this.restSpeed = restSpeed; // 속도가 초당 이만큼 아래면 목표에 붙입니다
        this.target = value;
        this._x0 = 0; // 목표에서 벗어난 거리(출발 때)
        this._v0 = 0;
        this._t0 = 0;
        this._rest = true;
      }
      /** [목표에서 벗어난 거리, 속도(초당)] — x(t) = (x0 + (v0 + ω·x0)·t)·e^(−ω·t), ω = 2π / response */
      _at(t = now()) {
        if (this._rest) return [0, 0];
        const s = Math.max(0, (t - this._t0) / 1000);
        const w = (2 * Math.PI) / this.response;
        const k = this._v0 + w * this._x0;
        const e = Math.exp(-w * s);
        return [(this._x0 + k * s) * e, (this._v0 - k * w * s) * e];
      }
      /** 새 목표로 — 지금 값·지금 속도에서 이어 갑니다. velocity(초당)를 주면 그 속도로 출발(손이 준 속도) */
      set(target, velocity = null, t = now()) {
        const [x, v] = this._at(t);
        this._x0 = this.target + x - target;
        this._v0 = velocity == null ? v : velocity;
        this.target = target;
        this._t0 = t;
        this._rest = false;
        return this;
      }
      /** 움직임 없이 그 값에 놓습니다 (손에 1:1로 붙어 있을 때 · 다시 지을 때) */
      snap(value) {
        this.target = value;
        this._rest = true;
        return this;
      }
      value(t) {
        return this.target + this._at(t)[0];
      }
      velocity(t) {
        return this._at(t)[1];
      }
      done(t) {
        if (this._rest) return true;
        const [x, v] = this._at(t);
        if (Math.abs(x) < this.restDelta && Math.abs(v) < this.restSpeed) this._rest = true;
        return this._rest;
      }
    }

    /* 주소에 ?motion=0.25 · ?motion=0.1 을 붙이면 첫 화면의 등장부터 느리게 봅니다 (?motion=1 은 보통 빠르기 — 계측 창은 뷰어가 엽니다: js/viewer.js) */
    try {
      const q = new URLSearchParams(location.search).get('motion');
      if (q === '0.25' || q === '0.1') setRate(q);
    } catch (err) {
      /* 주소를 읽을 수 없는 곳에서는 보통 빠르기 */
    }

    const api = { T, C, now, later, Spring };
    Object.defineProperty(api, 'rate', { enumerable: true, get: () => rate, set: setRate }); // HT.motion.rate = 0.25 처럼 씁니다
    return api;
  })();

  /* ---------- 연도·날짜 ----------
     연표의 시간은 "해 좌표"(실수 — js/calendar.js): 정수 N = N년 1월 1일. 연도만 적은 서력 값은 예전처럼 정수이고,
     월·일·시각까지 적었거나 다른 달력(음력·이슬람력 …)으로 적은 값은 표준 날짜 글을 짝 칸 "<칸>At"(startAt · endAt …)에 함께 둡니다.
     파일로 내보낼 때는 짝 칸의 글이 제자리(start 등)로 들어갑니다 (HT.packToJSON) */
  /** 항목의 날짜 칸 — 값(해 좌표)과 날짜 글 짝 칸("<칸>At")을 한 쌍으로 다루는 곳이 모두 이 목록을 돕니다
      (패치의 날짜 읽기 · 뷰어의 수정 저장과 DLC로 내보내기 · 패치할 수 있는 칸 목록). 새 날짜 칸은 여기에 더합니다 */
  HT.DATE_KEYS = ['start', 'end'];
  HT.DATE_KEYS.push('birth', 'death'); // 인물의 생몰 (짝 칸 birthAt · deathAt)
  HT.DATE_AT_KEYS = HT.DATE_KEYS.map(k => `${k}At`);
  /** 오늘의 해 좌표 — 진행 중인 항목의 끝과 "현재" 선 */
  HT.NOW_T = (() => {
    const d = new Date();
    return HT.cal ? HT.cal.tOf(HT.cal.jdnCivil(d.getFullYear(), d.getMonth() + 1, d.getDate())) : d.getFullYear();
  })();
  /** 해 좌표가 속한 해 (1592.9 → 1592). 비어 있는 0년 자리는 1년으로 */
  HT.yearOf = y => {
    const n = Math.floor(y + 1e-9);
    return n === 0 && y !== 0 ? 1 : n;
  };
  HT.formatYear = y => {
    if (y == null || !isFinite(y)) return '';
    const n = HT.yearOf(y);
    return n < 0 ? `기원전 ${-n}년` : `${n}년`;
  };
  HT.formatAxisYear = y => {
    const n = HT.yearOf(y);
    return n < 0 ? `기원전 ${-n}` : String(n);
  };
  /** 짝 칸의 날짜 글이 값과 맞을 때만 씁니다 (값만 고치고 글을 못 지운 경우엔 값이 이깁니다) */
  const atFits = (at, t) => {
    if (typeof at !== 'string' || !at.trim() || !HT.cal) return false;
    if (typeof t !== 'number') return true;
    const r = HT.cal.parse(at);
    return !!(r && r.ok && (Math.abs(r.t - t) < 1e-6 || (r.last != null && Math.abs(r.last - t) < 1e-6))); // 세기로 적은 끝은 구간의 마지막 해에 놓임
  };
  HT.atFits = atFits;
  /** 항목 x의 key 칸 날짜 글 (없거나 값과 안 맞으면 null) */
  HT.atOf = (x, key) => (x && atFits(x[`${key}At`], x[key]) ? x[`${key}At`] : null);
  /** 해 좌표 + 날짜 글 → "1592년" · "1592년 5월 23일" · "음력 1592년 4월 13일 (양력 5월 23일)" */
  HT.formatDate = (t, at, opts) => {
    if (at && atFits(at, t)) {
      const r = HT.cal.parse(at);
      if (r && r.ok) return HT.cal.describe(r, opts);
    }
    return HT.formatYear(t);
  };
  /** 연도만 적은 끝(정수 · 날짜 글 없음)이 실제로 뜻하는 마지막 순간: 그해 끝. "1592-05-23 ~ 1592"가 앞뒤가 뒤집힌 게 아니게 */
  HT.endBound = (end, endAt) => {
    if (end == null) return end;
    if (endAt && HT.cal) {
      const r = HT.cal.parse(endAt); // 세기로 적은 끝("3세기 말")은 그 구간의 끝까지
      if (r && r.ok && r.span && (Math.abs(r.t - end) < 1e-6 || Math.abs(r.last - end) < 1e-6)) return r.span[1] - 1e-9;
    }
    return Number.isInteger(end) && !endAt ? end + 1 - 1e-9 : end;
  };
  /** 항목이 품는 마지막 순간 — 진행 중이면 오늘, 연도만 적은 끝은 그해 끝까지 (사건의 소속 정권 판단·지도·검색이 함께 씀) */
  HT.endIn = p => (p.ongoing ? p.endY : HT.endBound(p.endY, HT.atOf(p, 'end')));
  /** 항목 한쪽 끝의 날짜: HT.formatWhen(x, 'start') */
  HT.formatWhen = (x, key = 'start', opts) => HT.formatDate(x[key], x[`${key}At`], opts);
  HT.formatRange = item => {
    if (item.kind === 'figure') return HT.figureRange(item); // 모델의 인물: 활동 시기(짐작한 끝 endY까지)
    const s = item.startUnknown ? '미정' : HT.formatWhen(item, 'start');
    if (item.ongoing) return `${s} ~ 현재`;
    if (item.endUnknown) return `${s} ~ 미정`;
    if (item.end == null || item.end === item.start) return s;
    return `${s} ~ ${HT.formatWhen(item, 'end')}`;
  };
  /** 모델의 인물 — 활동 시기 글. 적지 않아 짐작한 쪽(섬긴 기간 · 생몰에서)은 startAt · endYAt에 그 날짜 글이 함께 실려 있습니다.
      활동 시기를 "미정"으로 적은 쪽은 '미정' (자리는 배치용 연도나 짐작한 자리 — 상세에 따로 적습니다) */
  HT.figureRange = f => {
    const s = f.startUnknown ? '미정' : HT.formatDate(f.start, f.startAt);
    if (f.ongoing) return `${s} ~ 현재`;
    if (f.endUnknown) return `${s} ~ 미정`;
    if (f.endY == null || f.endY === f.start) return s;
    return `${s} ~ ${HT.formatDate(f.endY, f.endYAt)}`;
  };
  /** 인물의 생몰 글: "○○년 ~ ○○년 (향년 n세)" · "○○년 ~" · "~ ○○년" — 둘 다 없으면 '' (향년은 세는나이: 햇수 차 + 1 — 생일을 몰라도 셀 수 있게) */
  HT.figureLife = f => {
    if (f.birth == null && f.death == null) return '';
    const b = f.birth != null ? HT.formatDate(f.birth, f.birthAt) : '';
    const d = f.death != null ? HT.formatDate(f.death, f.deathAt) : '';
    let age = '';
    if (f.birth != null && f.death != null) {
      const yb = HT.yearOf(f.birth);
      const yd = HT.yearOf(f.death);
      const n = yd - yb - (yb < 0 && yd > 0 ? 1 : 0) + 1; // 0년이 없으므로 기원전 → 기원후는 한 해를 뺍니다
      if (n > 0 && n < 150) age = ` (향년 ${n}세)`;
    }
    return `${b} ~ ${d}${age}`.trim();
  };
  /** 연도·날짜 글("기원전 108", "BC 108", "1592년", "1592-05-23", "음력 1592-04-13" …)이나 수를 해 좌표로. 실패하면 NaN */
  HT.parseYear = input => {
    if (typeof input === 'number') return isFinite(input) ? input : NaN;
    const r = HT.cal ? HT.cal.parse(input) : null;
    return r && r.ok ? r.t : NaN;
  };
  /**
   * 날짜 칸 하나를 읽습니다 → null(빈 값) · { t, at, prec, cal } · { t: NaN, error }.
   * at = 연도만 적은 서력이 아니면 표준 날짜 글. 짝 칸 글(atRaw)은 값이 비었거나 값과 맞을 때만 씁니다
   */
  HT.readDate = (v, atRaw) => {
    let src = v;
    if (typeof atRaw === 'string' && atRaw.trim()) {
      if (v == null || v === '') src = atRaw;
      else if (typeof v === 'number' && atFits(atRaw, v)) src = atRaw;
    }
    if (src == null || src === '') return null;
    if (typeof src === 'string' && (HT.isUnknownText(src) || HT.isOngoingText(src))) return { t: NaN, at: null, error: '날짜가 아닙니다.' };
    const r = HT.cal.parse(src);
    if (!r) return null;
    if (!r.ok) return { t: NaN, at: null, error: r.error };
    return { t: r.t, at: r.fine && r.prec !== 'x' ? r.text : null, prec: r.prec, cal: r.cal };
  };
  HT.isOngoingText = s => /^(현재|진행\s*중|present|now|ongoing)$/i.test(String(s ?? '').trim());
  /** 날짜 { t, at }를 n년 옮깁니다 — 월·일은 그대로(그런 날이 없으면 해만), 날짜 글이 없으면 그냥 더하기 (새 항목의 기본 기간) */
  HT.shiftDate = (d, n) => {
    const r = d.at && HT.cal ? HT.cal.parse(d.at) : null;
    if (!r || !r.ok) return { t: d.t + n, at: undefined };
    const s = HT.cal.build({ cal: r.cal, y: HT.cal.fromAstro(HT.cal.toAstro(r.y) + n), m: r.m, leap: r.leap, d: r.d, h: r.h, mi: r.mi });
    return s.ok ? { t: s.t, at: s.text } : { t: HT.yearOf(d.t) + n, at: undefined };
  };

  /* ---------- DLC 검사·정규화 ---------- */
  const ID_RE = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/;
  const str = v => (v == null ? '' : String(v).trim());
  const arr = v => (Array.isArray(v) ? v : []);
  const toYear = v => (v === '' || v == null ? null : HT.parseYear(v));
  /** 날짜 칸 → { t, at } (빈 값 null, 못 읽으면 t: NaN) */
  const dateIn = (x, key) => (x ? HT.readDate(x[key], x[`${key}At`]) : null);
  HT.ID_RE = ID_RE;

  /* 패치로 바꿀 수 있는 칸 — DLC 읽기(HT.normalizePack)와 작업본의 패치 만들기(HT.draft)가 함께 봅니다 */
  const PATCHABLE = ['track', 'title', 'name', 'start', 'startAt', 'end', 'endAt', 'startRangeAt', 'endRangeAt', 'ongoing', 'startUnknown', 'endUnknown', 'category', 'importance', 'date', 'description', 'tags', 'source', 'certainty', 'startRange', 'endRange', 'alternatives', 'debate', 'color', 'polity', 'parent', 'polities', 'tracks', 'perspectives', 'reigns', 'eras', 'leaders', 'cabinets', 'people', 'succeeds', 'kind', 'partOf', 'wiki', 'host', 'successors', 'note', 'scale', 'house', 'capitals'];
  PATCHABLE.push('aka', 'role', 'service', 'figures'); // 인물(다른 이름 · 역할 · 섬긴 기록 — 생몰은 아래 날짜 칸에서) · 사건의 관련 인물
  for (const k of HT.DATE_KEYS) for (const n of [k, `${k}At`]) if (!PATCHABLE.includes(n)) PATCHABLE.push(n); // 날짜 칸은 값과 날짜 글 짝 칸이 늘 함께 (짝이 빠지면 내보낼 때 음력 같은 달력 정보가 떨어짐)
  PATCHABLE.push('phases'); // 시기 구분(학계) — 패치에서도 같은 꼴로 다시 정리합니다(HT.normalizePack의 패치 읽기)
  PATCHABLE.push('ranks'); // 지위 변천 — 패치에서도 같은 꼴로 다시 정리합니다. 지도자의 지위(rank)는 leaders 목록째로
  PATCHABLE.push('treaty'); // 조약 규격 — 통째 교체(지도자 목록처럼), 패치에서도 다시 정규화 · null이면 조약을 떼어 보통 사건으로
  PATCHABLE.push('historicity', 'historicityNote'); // 실재성 (8-4 마) — 비우거나 실재면 null(원래 항목의 실재성을 지움)
  /* 형식 버전 3: 사건의 주제 꼬리표 · 법 규격 · 선거 규격(조약처럼 통째 교체 · null이면 뗌), 단체의 칸(종류 · 있던 나라 · 앞선 단체 · 집권 기간 · 구성 나라 · 맺은 사건 —
     구성원 people은 시대의 민족과 같은 칸 이름이라 이미 있음), 제도 칸의 칸(주제 theme은 사건의 꼬리표와 같은 이름 · 갈래 · 칸 목록 — 나라 polity · track은 이미 있음).
     단체 · 제도는 나라 · 인물처럼 역사 자료라 학설팩이 고치거나 숨길 수 있게 패치 대상입니다(대범위 · 시대 구분은 보는 묶음이라 패치 대상이 아님 — DLC-형식.md '단체' 절) */
  PATCHABLE.push('theme', 'law', 'election', 'type', 'within', 'from', 'power', 'members', 'event', 'family', 'spans');
  /* 형식 버전 3: 이름 목록(names — 시대 · 왕조 · 인물 · 사건) · 사건의 장소(place) · 인물의 혈연(parents · spouses). 패치에서도 같은 읽기로 다시 정리하고, null이면 대상의 것을 비웁니다.
     지도자 · 내각 · 연호 칸의 사람 · 자리 이음 · 혈연 · 이름은 leaders · cabinets · eras 목록째로 */
  PATCHABLE.push('names', 'place', 'parents', 'spouses');
  PATCHABLE.push('spot'); // 날짜를 정확히 모르는 점 사건의 자리(0 처음 ~ 1 끝 · 기본 가운데 — 2026-10-14) — 옛 앱은 이 칸만 든 패치를 버리고 점을 그 구간 첫머리에 둡니다
  PATCHABLE.push('lineageOnly', 'order'); // 형식 3 (D1): 남의 DLC 인물을 계보 전용으로 · 형제 순서 — 값이 null이어도 형식 3
  PATCHABLE.push('northSouth'); // 형식 버전 3: 나라의 남북 위치(배열 기준 '북 → 남' — 기본팩 나라에도 값을 줄 수 있게) · null이면 대상의 것을 비움(첫 정도의 지명 좌표로)
  PATCHABLE.push('faiths'); // 종교(6단계 D8 · 형식 4 더하기) — 지위 변천처럼 패치에서도 같은 꼴로 다시 정리 · 빈 목록 []은 대상의 것을 비움
  HT.PATCHABLE = PATCHABLE;
  const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
  const COVER_RE = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/;
  /** 팩 정보의 새 칸(분류 · 태그 · 짧은 소개 · 볼거리 · 표지 · 관계 · 판 기록 · 만든 날 · 반영한 날 — docs/구상-메이커-팩.md 2-2)을 읽어 **적은 것만** 돌려줍니다.
      적지 않은 칸은 열쇠도 없어, 새 칸을 쓰지 않은 DLC는 읽고 다시 써도 한 글자도 달라지지 않습니다. 고친 것은 warn(글)로 알립니다. selfId = 이 팩의 id(자기를 가리키는 관계는 버림) */
  HT.readPackInfo = (raw, warn = () => {}, selfId = '') => {
    const L = HT.PACK_LIMITS;
    const info = {};
    const cut = (s, n, what) => {
      if (s.length <= n) return s;
      warn(`${what}이(가) ${n}자를 넘어 뒤를 잘랐습니다.`);
      return s.slice(0, n);
    };
    if (raw.category != null && raw.category !== '') {
      const c = str(raw.category);
      if (HT.PACK_CATEGORIES.some(x => x.id === c)) info.category = c;
      else warn(`알 수 없는 분류 «${c}» — 분류 없이 읽습니다.`);
    }
    if (raw.tags != null) {
      const tags = [...new Set(arr(raw.tags).map(t => cut(str(t), L.tagLen, '태그')).filter(Boolean))];
      if (tags.length > L.tags) warn(`태그는 ${L.tags}개까지 — 앞의 ${L.tags}개만 남겼습니다.`);
      if (tags.length) info.tags = tags.slice(0, L.tags);
    }
    if (str(raw.summary)) info.summary = cut(str(raw.summary), L.summary, '짧은 소개');
    if (raw.highlights != null) {
      const hs = arr(raw.highlights).map(h => cut(str(h), L.highlightLen, '볼거리 한 줄')).filter(Boolean);
      if (hs.length > L.highlights) warn(`볼거리는 ${L.highlights}줄까지 — 앞의 ${L.highlights}줄만 남겼습니다.`);
      if (hs.length) info.highlights = hs.slice(0, L.highlights);
    }
    if (raw.cover != null && raw.cover !== '') {
      const c = typeof raw.cover === 'string' ? raw.cover.trim() : '';
      if (c.length > L.cover) warn('표지 그림이 너무 커서(1.5MB 넘음) 뺐습니다.');
      else if (!COVER_RE.test(c)) warn('표지가 그림(png · jpeg · webp)이 아니어서 뺐습니다.');
      else info.cover = c;
    }
    if (raw.relations != null) {
      const seen = new Set();
      const rel = [];
      for (const r of arr(raw.relations)) {
        const type = str(r && r.type);
        const id = str(r && r.id);
        if (!HT.PACK_RELATIONS.some(x => x.id === type)) {
          warn(`관계 종류 «${type}»를 몰라 그 줄을 뺐습니다.`);
          continue;
        }
        if (!ID_RE.test(id) || id === selfId) {
          warn(`관계의 팩 id «${id}»가 올바르지 않아 그 줄을 뺐습니다.`);
          continue;
        }
        if (seen.has(`${type}|${id}`)) continue;
        seen.add(`${type}|${id}`);
        const name = str(r.name).slice(0, 80);
        rel.push(name ? { type, id, name } : { type, id });
      }
      if (rel.length) info.relations = rel;
    }
    if (raw.changelog != null) {
      const log = [];
      for (const e of arr(raw.changelog)) {
        const version = str(e && e.version);
        if (!version) {
          warn('판 기록에서 판 번호가 없는 줄을 뺐습니다.');
          continue;
        }
        const x = { version };
        const date = str(e.date);
        if (DAY_RE.test(date)) x.date = date;
        else if (date) warn(`판 기록 v${version}의 날짜 «${date}»를 읽지 못해 뺐습니다.`);
        const note = str(e.note);
        if (note) x.note = cut(note, L.noteLen, '판 기록 한 줄');
        log.push(x);
      }
      if (log.length > L.changelog) warn(`판 기록은 ${L.changelog}줄까지 — 새것 ${L.changelog}줄만 남겼습니다.`);
      if (log.length) info.changelog = log.slice(0, L.changelog);
    }
    for (const [k, what] of [['created', '처음 만든 날'], ['updated', '마지막 반영한 날']]) {
      const d = str(raw[k]);
      if (DAY_RE.test(d)) info[k] = d;
      else if (d) warn(`${what} «${d}»를 읽지 못해 뺐습니다.`);
    }
    return info;
  };

  /* ---------- 형식 3: 모아 보기 판 · 지도(1단계 — 그림 바탕 + 장면) · 글꼴 (docs/구상-연표-확장-10건.md 3-6 · 3-10 · 3-9) ----------
   * 셋 다 최상위 목록이고, 시대 구분 · 대범위처럼 **패치 대상이 아닙니다** — 모아 보기 판은 보는 방법이라(자료 해석이 아님) 다른 DLC는 제 판을 더하면 되고,
   * 지도는 그림 한 장과 그 위의 구역 · 장면이 한 몸이라 칸 하나를 덮어쓰는 고침이 뜻을 갖지 않으며(다른 해석은 제 지도로), 글꼴은 파일의 권리가 만든 사람에게 있어 남이 고칠 것이 아닙니다.
   * 판 · 지도는 가문처럼 접두어 문서 키("view:id" · "map:id")를 쓰고, 판 · 지도 · 글꼴은 id가 같으면 여러 DLC에 걸쳐 하나입니다(먼저 켠 DLC의 것 — 모델).
   * 읽는 함수는 HT.normalizePack이 부르고(report.err · report.warn — 목록 안의 번호와 함께), 적은 것만 돌려줍니다(목록이 비면 열쇠를 만들지 않아 옛 파일은 1px도 다르지 않음) */
  /** 연표의 밀도 고르기와 같은 값 — 모아 보기 판의 settings.density (글로 적은 이름도 읽음) */
  HT.VIEW_DENSITIES = [{ id: -1, name: '넉넉하게' }, { id: 0, name: '자동' }, { id: 1, name: '빽빽하게' }, { id: 2, name: '조감' }];
  /** 지도의 좌표 방식 — image(그림의 화소 · 왼쪽 위가 0, 0 · 1단계의 주인공) · lonlat(경도, 위도) */
  HT.MAP_CRS = [{ id: 'image', name: '그림 좌표' }, { id: 'lonlat', name: '경위도' }];
  /** 형식 3 목록의 id: 적은 id(영문 id 꼴)나 seed — 같은 목록 안에서 겹치면 "-2"를 붙입니다(적은 id였으면 알림 — 대범위의 takeId와 같은 규칙) */
  const ownId = (raw, seed, used, say) => {
    let id = str(raw);
    if (id && !ID_RE.test(id)) {
      say(`id "${id}"가 올바르지 않아 새로 만들었습니다.`);
      id = '';
    }
    const wrote = !!id;
    if (!id) id = seed;
    if (used.has(id)) {
      let n = 2;
      while (used.has(`${id}-${n}`)) n++;
      if (wrote) say(`id "${id}"가 겹쳐 "${id}-${n}"(으)로 바꿨습니다.`);
      id = `${id}-${n}`;
    }
    used.add(id);
    return id;
  };
  /** 기간 { start, startAt?, end?, endAt?, ongoing? } — 판(시작이 있어야 끝도 씀 · 끝은 그해까지)과 구역(endOnly: 끝만 적어도 됨 · [시작, 끝) — 끝 해에는 이미 없음).
      "미정"은 받지 않습니다. 못 읽은 것은 say로 알리고 기간(또는 끝)을 비웁니다 — 적은 것이 하나도 없으면 null */
  const readSpan = (x, say, endOnly) => {
    const has = k => x[k] != null && x[k] !== '';
    const o = {};
    if (has('start')) {
      const s = HT.readDate(x.start, x.startAt);
      if (!s || isNaN(s.t)) {
        say(`시작 «${str(x.start)}»을(를) 읽지 못해 기간을 무시했습니다.`);
        return null;
      }
      o.start = s.t;
      if (s.at) o.startAt = s.at;
    } else if (!endOnly) {
      if (has('end') || x.ongoing === true) say('시작 없이 끝만 적어 기간을 무시했습니다.');
      return null;
    }
    if (x.ongoing === true || HT.isOngoingText(x.end)) {
      if (!endOnly) o.ongoing = true; // 구역은 끝을 비우면 지금까지
    } else if (has('end')) {
      const e = HT.readDate(x.end, x.endAt);
      if (!e || isNaN(e.t)) say(`끝 «${str(x.end)}»을(를) 읽지 못해 끝을 비웠습니다.`);
      else if (o.start != null && (endOnly ? e.t <= o.start : HT.endBound(e.t, e.at) < o.start)) {
        say('끝이 시작보다 앞서 기간을 무시했습니다.');
        return null;
      } else {
        o.end = e.t;
        if (e.at) o.endAt = e.at;
      }
    }
    return Object.keys(o).length ? o : null;
  };
  /** 모아 보기 판의 보기 설정 { density?, lens?, show?: { 표시 열쇠: 참거짓 } } — 지금 보기 설정의 열쇠 이름만(밀도 HT.VIEW_DENSITIES · 표시 HT.SHOW_DEFAULTS).
      lens = 렌즈(주제 보기 — 10건 8번)의 주제 id 글 — 사전 확인은 렌즈가 하므로 여기서는 글로만. 모르는 열쇠 · 값은 say로 알리고 버립니다. 남은 것이 없으면 null */
  HT.readViewSettings = (raw, say = () => {}) => {
    if (raw == null || raw === '') return null;
    if (typeof raw !== 'object' || Array.isArray(raw)) {
      say('보기 설정(settings)이 { … } 꼴이 아니어서 뺐습니다.');
      return null;
    }
    const o = {};
    for (const [k, v] of Object.entries(raw)) {
      if (k === 'density') {
        const n = typeof v === 'number' ? v : /^-?\d+$/.test(str(v)) ? Number(str(v)) : NaN;
        const d = HT.VIEW_DENSITIES.find(x => x.id === n) || HT.VIEW_DENSITIES.find(x => x.name === str(v));
        if (d) o.density = d.id;
        else say(`보기 설정의 밀도 «${str(v)}»를 몰라 뺐습니다. (${HT.VIEW_DENSITIES.map(x => `${x.id} ${x.name}`).join(' · ')})`);
      } else if (k === 'lens') {
        if (typeof v === 'string' && str(v)) o.lens = str(v);
        else if (v != null && v !== '') say('보기 설정의 렌즈(lens)는 주제 id 글이어야 해서 뺐습니다.');
      } else if (k === 'show') {
        if (!v || typeof v !== 'object' || Array.isArray(v)) {
          say('보기 설정의 표시(show)가 { 열쇠: 참거짓 } 꼴이 아니어서 뺐습니다.');
          continue;
        }
        const show = {};
        for (const [s, b] of Object.entries(v)) {
          if (!Object.prototype.hasOwnProperty.call(HT.SHOW_DEFAULTS, s)) say(`보기 설정의 표시 «${s}»를 몰라 뺐습니다.`);
          else if (typeof b !== 'boolean') say(`보기 설정의 표시 «${s}»는 참(true) · 거짓(false)만 받아 뺐습니다.`);
          else show[s] = b;
        }
        if (Object.keys(show).length) o.show = show;
      } else say(`보기 설정의 열쇠 «${k}»를 몰라 뺐습니다. (밀도 density · 렌즈 lens · 표시 show만 받습니다)`);
    }
    return Object.keys(o).length ? o : null;
  };
  /** 모아 보기 판 (3-6 — 감독 결정: 한 화면에 모으기): [{ id?, name, members, start?, end?, settings?, color?, description?, note?, wiki? }].
      대범위와 달리 트랙이 없고(구성 나라는 여러 트랙에 걸쳐도 됨 — 나라 참조는 대범위와 같은 꼴), 구성 나라는 적은 차례 그대로 둡니다(판 안의 차례로 쓸 수 있게).
      구성 나라를 연표에서 찾는 것은 모델이(다른 DLC의 나라일 수 있어 파일 검사에서는 막지 않음) */
  HT.readViews = (list, report) => {
    const out = [];
    const ids = new Set();
    arr(list).forEach((v, i) => {
      if (!v || typeof v !== 'object' || Array.isArray(v)) return report.err(`모아 보기 판 #${i + 1}: 형식이 올바르지 않습니다.`, i);
      const name = str(v.name);
      const label = `모아 보기 판 #${i + 1}${name ? ` "${name}"` : ''}`;
      const say = msg => report.warn(`${label}: ${msg}`, i);
      if (!name) return report.err(`${label}: 이름이 비어 있습니다.`, i);
      const refs = [];
      for (const r of HT.readScopeRefs(v.members)) if (!refs.some(q => q.polity === r.polity && (q.track || '') === (r.track || ''))) refs.push(r);
      if (!refs.length) return report.err(`${label}: 구성 나라(members)가 없습니다.`, i);
      const o = { id: ownId(v.id, `v-${HT.hash(name)}`, ids, say), name, members: refs.map(HT.compactScopeRef) };
      const span = readSpan(v, say, false);
      if (span) Object.assign(o, span);
      const settings = HT.readViewSettings(v.settings, say);
      if (settings) o.settings = settings;
      const names = HT.readNames(v.names, say); // 이름 목록(판의 원어 · 다른 이름 — 형식 3 F1과 같은 읽기)
      if (names.length) o.names = names;
      if (HT.isColor(v.color)) o.color = v.color;
      for (const k of ['description', 'note']) if (str(v[k])) o[k] = str(v[k]);
      if (str(v.wiki)) o.wiki = String(v.wiki);
      out.push(o);
    });
    return out;
  };
  /** 지도의 그림(바탕 · 장면) — 표지와 같은 꼴 · 같은 한도(HT.PACK_LIMITS.mapImage). 그림이 아니거나 크면 say로 알리고 null */
  const readMapImage = (v, what, say) => {
    const c = typeof v === 'string' ? v.trim() : '';
    if (c.length > HT.PACK_LIMITS.mapImage) say(`${what}이 너무 커서(data URL ${HT.PACK_LIMITS.mapImage}자 넘음) 뺐습니다.`);
    else if (!COVER_RE.test(c)) say(`${what}이 그림(png · jpeg · webp의 data URL)이 아니어서 뺐습니다.`);
    else return c;
    return null;
  };
  /** 구역의 모양: 고리 하나 [[x, y], …] 또는 여러 고리 [[[x, y], …], …] — 적은 꼴 그대로 돌려줍니다. 꼭짓점은 두 수 [x, y](경위도면 경도 ±180 · 위도 ±90 안),
      고리마다 꼭짓점 셋 이상(처음과 끝이 같은 닫힌 고리는 하나로 셈). 잘못된 꼭짓점이 든 고리는 통째로 뺍니다(꼭짓점 하나만 빼면 없는 모양이 되므로).
      그림 밖으로 나간 꼭짓점은 알리기만 합니다(그림 밖은 그리지 않음). 쓸 고리가 없으면 null */
  const readShape = (shape, crs, size, say) => {
    if (!Array.isArray(shape) || !shape.length) {
      say('모양(shape)이 비었거나 목록이 아닙니다.');
      return null;
    }
    const multi = Array.isArray(shape[0]) && Array.isArray(shape[0][0]);
    const good = [];
    let outside = false;
    (multi ? shape : [shape]).forEach((ring, k) => {
      const what = multi ? `고리 #${k + 1}` : '모양';
      if (!Array.isArray(ring)) return say(`${what}이 목록이 아니어서 뺐습니다.`);
      const bad = ring.findIndex(p => !Array.isArray(p) || p.length !== 2 || !p.every(n => typeof n === 'number' && isFinite(n)));
      if (bad >= 0) return say(`${what}의 ${bad + 1}번째 꼭짓점이 [x, y] 두 수가 아니어서 ${multi ? '그 고리를' : '모양을'} 뺐습니다.`);
      if (crs === 'lonlat') {
        const off = ring.findIndex(p => Math.abs(p[0]) > 180 || Math.abs(p[1]) > 90);
        if (off >= 0) return say(`${what}의 ${off + 1}번째 꼭짓점이 경위도 범위(경도 ±180 · 위도 ±90)를 벗어나 ${multi ? '그 고리를' : '모양을'} 뺐습니다.`);
      }
      const closed = ring.length > 1 && ring[0][0] === ring[ring.length - 1][0] && ring[0][1] === ring[ring.length - 1][1];
      const n = ring.length - (closed ? 1 : 0);
      if (n < 3) return say(`${what}의 꼭짓점이 ${n}개뿐이라 뺐습니다 (셋 이상이어야 함).`);
      if (size && ring.some(p => p[0] < 0 || p[1] < 0 || p[0] > size[0] || p[1] > size[1])) outside = true;
      good.push(ring.map(p => [p[0], p[1]]));
    });
    if (outside) say(`그림(${size[0]}×${size[1]}) 밖으로 나간 꼭짓점이 있습니다 — 그림 밖은 그리지 않습니다.`);
    if (!good.length) return null;
    return multi ? good : good[0];
  };
  /** 지도 1단계 (3-10 — 감독 결정: 그림 바탕 + 장면): [{ id?, name, crs?, image?, size?, levels?, regions?, frames?, places?, description?, note?, source?, wiki? }].
      territory(옛 지형 팩 지도)와 따로인 새 열쇠입니다. 지도의 꼴(이름 · 좌표 방식 · 그림 좌표의 크기)이 틀리면 오류로 그 지도만 빼고,
      그 안의 층위 · 구역 · 장면 · 지명이 틀리면 경고하고 그것만 뺍니다.
      · levels — 행정 층위(만든 사람이 정함 · 차례 = 위에서 아래): [{ id, name? }] 또는 글 — id는 글 무엇이든(한글도)
      · regions — 구역: [{ id, name?, level?, parent?(같은 지도의 구역 id), start?, end?, shape, note? }] — 기간은 [시작, 끝)
      · frames — 장면(열쇠 해): [{ year, owners?: { 구역 id: 나라 참조 | null(주인 없음으로) }, image?, note? }] — 해 순으로 정리하고, 같은 해가 둘이면 뒤의 것을 뺍니다.
        장면의 주인은 앞 장면에서 이어받고 적은 구역만 바뀝니다(null이면 그 구역의 주인을 지움). 사이의 해는 앞 열쇠 해를 따릅니다 — HT.mapFrameAt
      · places — 지명 사전(places)의 이름 · id 글 목록(지명 사전은 이름 · 지명 갈래의 몫 — 여기서는 글로만 보관) */
  HT.readMaps = (list, report) => {
    const out = [];
    const ids = new Set();
    arr(list).forEach((m, i) => {
      if (!m || typeof m !== 'object' || Array.isArray(m)) return report.err(`지도 #${i + 1}: 형식이 올바르지 않습니다.`, i);
      const name = str(m.name);
      const label = `지도 #${i + 1}${name ? ` "${name}"` : ''}`;
      const say = msg => report.warn(`${label}: ${msg}`, i);
      if (!name) return report.err(`${label}: 이름이 비어 있습니다.`, i);
      const crs = str(m.crs) || 'image';
      if (!HT.MAP_CRS.some(c => c.id === crs)) return report.err(`${label}: 좌표 방식(crs) «${crs}»를 모릅니다. (image 그림 좌표 · lonlat 경위도)`, i);
      let size = null;
      if (crs === 'image') {
        const s = m.size;
        if (!Array.isArray(s) || s.length !== 2 || !s.every(n => typeof n === 'number' && isFinite(n) && n > 0)) return report.err(`${label}: 그림 좌표(crs: image)의 지도에는 크기(size: [너비, 높이] — 0보다 큰 두 수)가 필요합니다.`, i);
        size = [s[0], s[1]];
      } else if (m.size != null && m.size !== '') say('경위도 지도에는 크기(size)를 쓰지 않아 뺐습니다.');
      const o = { id: ownId(m.id, `m-${HT.hash(name)}`, ids, say), name, crs };
      if (size) o.size = size;
      if (m.image != null && m.image !== '') {
        if (crs === 'lonlat') say('경위도 지도의 바탕 그림은 자리를 맞출 칸이 아직 없어(2단계) 뺐습니다.');
        else {
          const img = readMapImage(m.image, '바탕 그림', say);
          if (img) o.image = img;
        }
      }
      /* 행정 층위 */
      const levels = [];
      if (m.levels != null && !Array.isArray(m.levels)) say('행정 층위(levels)는 목록이어야 해서 뺐습니다.');
      arr(m.levels).forEach((l, k) => {
        const x = typeof l === 'string' ? { id: l } : l && typeof l === 'object' && !Array.isArray(l) ? l : {};
        const id = str(x.id) || str(x.name);
        if (!id) return say(`행정 층위 #${k + 1}: id가 비어 있어 뺐습니다.`);
        if (levels.some(q => q.id === id)) return say(`행정 층위 "${id}"가 겹쳐 뒤의 것을 뺐습니다.`);
        levels.push({ id, name: str(x.name) || id });
      });
      if (levels.length) o.levels = levels;
      const levelAt = id => levels.findIndex(q => q.id === id);
      /* 구역 */
      const regions = [];
      if (m.regions != null && !Array.isArray(m.regions)) say('구역(regions)은 목록이어야 해서 뺐습니다.');
      arr(m.regions).forEach((r, k) => {
        if (!r || typeof r !== 'object' || Array.isArray(r)) return say(`구역 #${k + 1}: 형식이 올바르지 않아 뺐습니다.`);
        const id = str(r.id);
        const rl = `구역 #${k + 1}${id ? ` "${id}"` : ''}`;
        const rsay = msg => say(`${rl}: ${msg}`);
        if (!id) return rsay('id가 비어 있어 뺐습니다.');
        if (regions.some(q => q.id === id)) return rsay('id가 겹쳐 뒤의 것을 뺐습니다.');
        const shape = readShape(r.shape, crs, size, rsay);
        if (!shape) return rsay('쓸 수 있는 모양이 없어 구역을 뺐습니다.');
        const q = { id, name: str(r.name) || id };
        const lv = str(r.level);
        if (lv && levelAt(lv) >= 0) q.level = lv;
        else if (lv) rsay(`행정 층위 «${lv}»가 이 지도의 levels에 없어 뺐습니다.`);
        if (str(r.parent)) q.parent = str(r.parent); // 모두 읽은 뒤에 확인
        const span = readSpan(r, rsay, true);
        if (span) Object.assign(q, span);
        q.shape = shape;
        const names = HT.readNames(r.names, rsay); // 이름 목록(구역의 원어 · 옛 이름 — 형식 3 F1과 같은 읽기)
        if (names.length) q.names = names;
        if (str(r.note)) q.note = str(r.note);
        regions.push(q);
      });
      const regionOf = id => regions.find(q => q.id === id) || null;
      for (const q of regions) {
        if (!q.parent) continue;
        const p = regionOf(q.parent);
        if (!p || p === q) {
          say(`구역 "${q.id}": 위 구역(parent) «${q.parent}»를 이 지도에서 찾지 못해 뺐습니다.`);
          delete q.parent;
          continue;
        }
        const seen = new Set();
        let loop = false;
        for (let cur = p; cur && !seen.has(cur.id); cur = cur.parent ? regionOf(cur.parent) : null) {
          if (cur === q) {
            loop = true;
            break;
          }
          seen.add(cur.id);
        }
        if (loop) {
          say(`구역 "${q.id}": 위 구역을 따라가면 제자리로 돌아와 위 구역(parent)을 뺐습니다.`);
          delete q.parent;
        } else if (q.level && p.level && levelAt(p.level) >= levelAt(q.level)) say(`구역 "${q.id}": 위 구역 "${p.id}"의 층위(${p.level})가 이 구역의 층위(${q.level})보다 위가 아닙니다.`);
      }
      if (regions.length) o.regions = regions;
      /* 장면 (열쇠 해) */
      const frames = [];
      if (m.frames != null && !Array.isArray(m.frames)) say('장면(frames)은 목록이어야 해서 뺐습니다.');
      arr(m.frames).forEach((f, k) => {
        if (!f || typeof f !== 'object' || Array.isArray(f)) return say(`장면 #${k + 1}: 형식이 올바르지 않아 뺐습니다.`);
        const d = f.year == null || f.year === '' ? null : HT.readDate(f.year, f.yearAt);
        if (!d || isNaN(d.t)) return say(`장면 #${k + 1}: 해(year)가 없거나 읽을 수 없어 뺐습니다.`);
        const fl = `장면 #${k + 1}(${str(f.year)})`;
        const q = { year: d.t };
        if (d.at) q.yearAt = d.at;
        if (f.owners != null) {
          if (typeof f.owners !== 'object' || Array.isArray(f.owners)) say(`${fl}: 주인(owners)이 { 구역 id: 나라 } 꼴이 아니어서 뺐습니다.`);
          else {
            const owners = {};
            for (const [rid, ref] of Object.entries(f.owners)) {
              if (!regionOf(rid)) {
                say(`${fl}: 구역 «${rid}»가 이 지도에 없어 그 주인을 뺐습니다.`);
                continue;
              }
              if (ref == null || ref === '' || (typeof ref === 'string' && /^none$/i.test(ref.trim()))) {
                owners[rid] = null; // 주인 없음(앞 장면에서 이어받은 주인을 지움)
                continue;
              }
              const r = HT.readScopeRef(ref);
              if (r) owners[rid] = HT.compactScopeRef(r);
              else say(`${fl}: 구역 «${rid}»의 주인을 읽지 못해 뺐습니다.`);
            }
            if (Object.keys(owners).length) q.owners = owners;
          }
        }
        if (f.image != null && f.image !== '') {
          if (crs === 'lonlat') say(`${fl}: 경위도 지도의 장면 그림은 자리를 맞출 칸이 아직 없어(2단계) 뺐습니다.`);
          else {
            const img = readMapImage(f.image, `${fl}의 그림`, say);
            if (img) q.image = img;
          }
        }
        if (str(f.note)) q.note = str(f.note);
        frames.push(q);
      });
      frames.sort((a, b) => a.year - b.year); // 같은 해는 적은 차례 그대로(안정 정렬) — 뒤의 것을 뺌
      const kept = [];
      for (const f of frames) {
        if (kept.length && Math.abs(kept[kept.length - 1].year - f.year) < 1e-9) say(`장면: 같은 해(${f.yearAt || HT.yearOf(f.year)})의 장면이 둘이라 뒤의 것을 뺐습니다.`);
        else kept.push(f);
      }
      if (kept.length) o.frames = kept;
      /* 지명 (글로만) */
      if (m.places != null) {
        if (!Array.isArray(m.places)) say('지명(places)은 목록이어야 해서 뺐습니다.');
        const places = [];
        for (const p of arr(m.places)) {
          const s = str(p && typeof p === 'object' ? p.id ?? p.name : p);
          if (s && !places.includes(s)) places.push(s);
        }
        if (places.length) o.places = places;
      }
      for (const k of ['description', 'note', 'source']) if (str(m[k])) o[k] = str(m[k]);
      if (str(m.wiki)) o.wiki = String(m.wiki);
      out.push(o);
    });
    return out;
  };
  /* 글꼴 파일: data:font/(woff2|woff|ttf|otf);base64,… — 머리 4바이트로 내용이 그 글꼴인지도 봅니다(woff2 'wOF2' · woff 'wOFF' · ttf/otf 00 01 00 00 · 'true' · 'OTTO') */
  const FONT_RE = /^data:font\/(woff2|woff|ttf|otf);base64,([A-Za-z0-9+/]+={0,2})$/;
  const FONT_FORMATS = { woff2: 'woff2', woff: 'woff', ttf: 'truetype', otf: 'opentype' }; // CSS의 format() 이름
  const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const fontHead = b64 => {
    const n = [...b64.slice(0, 8)].map(c => B64.indexOf(c));
    if (n.length < 8 || n.some(v => v < 0)) return '';
    let s = '';
    for (let k = 0; k < 8; k += 4) {
      const v = (n[k] << 18) | (n[k + 1] << 12) | (n[k + 2] << 6) | n[k + 3];
      s += String.fromCharCode((v >> 16) & 255, (v >> 8) & 255, v & 255);
    }
    return s.slice(0, 4);
  };
  const FONT_HEADS = { woff2: ['wOF2'], woff: ['wOFF'], ttf: ['\0\x01\0\0', 'true', 'OTTO'], otf: ['OTTO', '\0\x01\0\0', 'true'] };
  /** 글꼴 (3-9): [{ id, family, src, license, scripts?, note? }] — id · 이름(family) · 파일(src) · 라이선스(license)가 없거나 틀리면 오류로 그 글꼴만 뺍니다.
      한도(HT.PACK_LIMITS): 하나에 data URL font자 · 한 DLC에 fonts개 · 모두 합쳐 fontTotal자. scripts = 문자 꼬리표(ISO 15924의 네 글자 — Hang · Hani · Latn …) */
  HT.readFonts = (list, report) => {
    const L = HT.PACK_LIMITS;
    const out = [];
    let total = 0;
    arr(list).forEach((f, i) => {
      if (!f || typeof f !== 'object' || Array.isArray(f)) return report.err(`글꼴 #${i + 1}: 형식이 올바르지 않습니다.`, i);
      const id = str(f.id);
      const family = str(f.family);
      const label = `글꼴 #${i + 1}${family || id ? ` "${family || id}"` : ''}`;
      if (!ID_RE.test(id)) return report.err(`${label}: id가 비었거나 올바르지 않습니다.`, i);
      if (out.some(x => x.id === id)) return report.warn(`${label}: id "${id}"가 겹쳐 뒤의 것을 무시했습니다.`, i);
      if (!family) return report.err(`${label}: 글꼴 이름(family)이 비어 있습니다.`, i);
      const license = str(f.license);
      if (!license) return report.err(`${label}: 라이선스(license)가 비어 있어 이 글꼴을 뺐습니다. (글꼴은 쓸 수 있는 조건을 적어야 담을 수 있습니다)`, i);
      const src = typeof f.src === 'string' ? f.src.trim() : '';
      if (!src) return report.err(`${label}: 글꼴 파일(src)이 비어 있습니다.`, i);
      if (src.length > L.font) return report.err(`${label}: 글꼴 파일이 너무 커서(data URL ${L.font}자 넘음) 뺐습니다.`, i);
      const mm = src.match(FONT_RE);
      if (!mm) return report.err(`${label}: 글꼴 파일(src)이 data:font/woff2 · woff · ttf · otf의 base64 꼴이 아닙니다.`, i);
      if (!FONT_HEADS[mm[1]].includes(fontHead(mm[2]))) return report.err(`${label}: 글꼴 파일의 내용이 ${mm[1]} 글꼴이 아닙니다.`, i);
      if (out.length >= L.fonts) return report.warn(`${label}: 글꼴은 한 DLC에 ${L.fonts}개까지라 뺐습니다.`, i);
      if (total + src.length > L.fontTotal) return report.err(`${label}: 글꼴을 모두 합친 크기가 한도(data URL ${L.fontTotal}자)를 넘어 뺐습니다.`, i);
      total += src.length;
      const o = { id, family, src, license };
      if (f.scripts != null && f.scripts !== '') {
        const tags = [];
        for (const t of Array.isArray(f.scripts) ? f.scripts : String(f.scripts).split(',')) {
          const s = str(t);
          if (!s) continue;
          if (!/^[A-Za-z]{4}$/.test(s)) {
            report.warn(`${label}: 문자 꼬리표 «${s}»는 네 글자 꼴(ISO 15924)이 아니어서 뺐습니다.`, i);
            continue;
          }
          const tag = s[0].toUpperCase() + s.slice(1).toLowerCase();
          if (!tags.includes(tag)) tags.push(tag);
        }
        if (tags.length) o.scripts = tags;
      }
      /* 덮는 글자 범위(10건 9 · 결정 4 B의 판정 — 갈래 D2): "U+F1A00-F1A0B" 꼴의 목록(배열이나 쉼표로 이은 글). 없으면 scripts마다의 기본 범위만(HT.fontRanges) —
         가상 문자(사설 영역) · 한자 확장 · 옛한글은 이 칸으로만 '있음'이 됩니다. 꼴이 틀린 범위는 경고하고 뺍니다 */
      if (f.ranges != null && f.ranges !== '') {
        const rs = [];
        for (const t of Array.isArray(f.ranges) ? f.ranges : String(f.ranges).split(',')) {
          const s = str(t);
          if (!s) continue;
          const r = HT.parseRange(s);
          if (!r) {
            report.warn(`${label}: 글자 범위 «${s}»는 U+4E00-9FFF 꼴이 아니어서 뺐습니다.`, i);
            continue;
          }
          const text = HT.rangeText(r);
          if (!rs.includes(text)) rs.push(text);
        }
        if (rs.length) o.ranges = rs;
      }
      if (str(f.note)) o.note = str(f.note);
      out.push(o);
    });
    return out;
  };
  /** 글꼴 파일의 CSS format() 이름 (모르면 '') */
  HT.fontFormat = src => {
    const m = typeof src === 'string' ? src.match(/^data:font\/(woff2|woff|ttf|otf);/) : null;
    return m ? FONT_FORMATS[m[1]] : '';
  };

  /**
   * DLC 원본 객체를 검사하고 깨끗한 형태로 바꿉니다.
   * errors: 고쳐야 하는 문제 (kind==='info'이면 치명적 → pack=null)
   * warnings: 자동으로 보정했거나 참고할 문제
   * 오류가 있는 개별 항목은 결과 pack에서 빠집니다.
   */
  HT.normalizePack = function (raw) {
    const errors = [];
    const warnings = [];
    const err = (msg, kind = 'info', index) => errors.push({ msg, kind, index });
    const warn = (msg, kind = 'info', index) => warnings.push({ msg, kind, index });

    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      err('DLC 파일의 최상위가 객체({ ... })가 아닙니다.');
      return { pack: null, errors, warnings };
    }
    /* 형식 4(리메이크 1단계 1a — docs/설계-리메이크-객체-그릇-서고.md 3-8): 지금 화면이 읽는 옛 꼴로 내려 읽습니다. 저장은 5단계 전까지 옛 형식 */
    if (Number(raw.formatVersion) === HT.F4.VERSION) {
      try {
        raw = HT.F4.down(raw, msg => warn(msg));
      } catch (e) {
        err(`형식 4 파일을 읽지 못했습니다 — ${e && e.message ? e.message : e}`);
        return { pack: null, errors, warnings };
      }
    }
    if (raw.format !== HT.FORMAT) err(`"format" 값이 "${HT.FORMAT}"이어야 합니다. 이 프로그램용 DLC 파일이 맞는지 확인하세요.`);
    if (Number(raw.formatVersion) > HT.FORMAT_VERSION)
      warn(`더 새로운 형식 버전(${raw.formatVersion})으로 만들어진 파일입니다. 일부 정보가 무시될 수 있습니다.`);

    const pack = {
      format: HT.FORMAT,
      formatVersion: HT.FORMAT_VERSION,
      id: str(raw.id),
      name: str(raw.name),
      version: str(raw.version) || '1.0.0',
      author: str(raw.author),
      description: str(raw.description),
      requires: arr(raw.requires).map(str).filter(Boolean),
      ...HT.readPackInfo(raw, msg => warn(msg), str(raw.id)), // 팩 정보의 새 칸 — 적은 것만 (docs/구상-메이커-팩.md 2-2)
      tracks: [],
      categories: [],
      peoples: [],
      epochs: [],
      periods: [],
      organs: [],
      cultures: [],
      dynasties: [],
      events: [],
      patches: [],
      documents: {},
    };
    if (!ID_RE.test(pack.id)) err('DLC "id"는 영문·숫자·- _ . 만 쓸 수 있고 비어 있으면 안 됩니다.');
    else if (pack.id === HT.USER_PACK.id) err(`"${pack.id}"는 프로그램이 쓰는 예약어라서 DLC id로 쓸 수 없습니다.`);
    if (!pack.name) err('DLC 이름("name")이 비어 있습니다.');

    /* 형식 버전 3의 칸 읽기 (HT.readNames · HT.readAccession · HT.readParents · HT.readSpouses — 위 '이름 목록 · 사람 잇기' 덩어리): 적은 것이 있을 때만 o에 둡니다(옛 파일 그대로) */
    const putNames = (o, v, label, kind, i) => {
      const list = HT.readNames(v, m => warn(`${label}: ${m}`, kind, i));
      if (list.length) o.names = list;
    };
    /** 사람 쪽 칸: 사람(person — 지도자 · 내각 칸) · 자리 이음(accession — 지도자 칸) · 부모 · 배우자(지도자 칸 · 인물) */
    const putLineage = (o, x, label, kind, i, { person = false, accession = false, kin = false } = {}) => {
      const w = m => warn(`${label}: ${m}`, kind, i);
      if (person && HT.isUnknownWho(x.person)) w(`사람(person) "${String(x.person).trim()}"은(는) 적지 않은 것과 같아 뺐습니다 — 이 칸 자체가 한 사람입니다(이름 모를 사람끼리 한 사람으로 묶이지 않게).`);
      else if (person && x.person != null && x.person !== '') {
        const r = HT.readPersonRef(x.person);
        if (r) o.person = r;
        else w('사람(person)을 읽을 수 없어 뺐습니다 — 인물 id · 이름이나 "나라:지도자@시작 해"로 적습니다.');
      }
      if (accession) {
        const a = HT.readAccession(x.accession, w);
        if (a) o.accession = a;
      }
      if (kin) {
        const ps = HT.readParents(x.parents, w);
        if (ps.length) o.parents = ps;
        const sp = HT.readSpouses(x.spouses, w);
        if (sp.length) o.spouses = sp;
      }
    };

    /* 문화권 사전(spheres — 2026-10-23) — 있을 때만 열쇠가 생깁니다(옛 파일은 그대로). 트랙의 sphere가 가리킵니다 — 내장 열아홉 · 이 DLC의 것 · 다른 켠 DLC의 것 */
    const spheres = HT.readSpheres(raw.spheres);
    spheres.problems.forEach((msg, k) => warn(msg, 'spheres', spheres.at[k]));
    if (spheres.list.length) pack.spheres = spheres.list;
    /* 지도자 표기 낱말(leaderLabels — 6단계 D3 · 형식 4 더하기): 이 팩의 묘호 · 시호 · 이름 자리 낱말 — 있을 때만 열쇠가 생깁니다(문화권 사전의 것이 이김 — HT.leaderWords) */
    const leaderLabels = HT.readLeaderLabels(raw.leaderLabels, msg => warn(msg, 'info'));
    if (leaderLabels) pack.leaderLabels = leaderLabels;

    const trackIds = new Set();
    arr(raw.tracks).forEach((t, i) => {
      const id = str(t && t.id);
      if (!ID_RE.test(id)) return err(`트랙 #${i + 1}: id가 비었거나 올바르지 않습니다.`, 'tracks', i);
      if (trackIds.has(id)) return warn(`트랙 "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'tracks', i);
      trackIds.add(id);
      const o = { id, name: str(t.name) || id, color: HT.isColor(t.color) ? t.color : HT.autoColor(id) };
      if (t.order !== '' && t.order != null && isFinite(t.order)) o.order = Number(t.order);
      if (str(t.description)) o.description = str(t.description);
      if (str(t.wiki)) o.wiki = String(t.wiki);
      // 문화권(조각 ②): 이 DLC나 다른 켠 DLC(기본팩 등)의 spheres에 만든 id — 올바른 id면 그대로 둡니다. 모델이 켠 DLC 가운데 만든 곳을 못 찾으면 문화권 없이 놓고 알립니다(HT.buildModel의 sphereWarnings)
      if (str(t.sphere)) {
        const sp = str(t.sphere);
        if (ID_RE.test(sp)) o.sphere = sp;
        else warn(`트랙 "${id}"의 문화권 "${sp}"은(는) id가 올바르지 않아 뺐습니다.`, 'tracks', i);
      }
      pack.tracks.push(o);
    });

    const catIds = new Set(HT.DEFAULT_CATEGORIES.map(c => c.id));
    arr(raw.categories).forEach((c, i) => {
      const id = str(c && c.id);
      if (!ID_RE.test(id)) return err(`분류 #${i + 1}: id가 비었거나 올바르지 않습니다.`, 'categories', i);
      if (pack.categories.some(x => x.id === id)) return warn(`분류 "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'categories', i);
      catIds.add(id);
      pack.categories.push({ id, name: str(c.name) || id, color: HT.isColor(c.color) ? c.color : HT.autoColor(id) });
    });

    /* 민족 — 시대를 묶는 단위. 시대의 people에 이름이나 id로 적습니다 */
    arr(raw.peoples).forEach((p, i) => {
      const id = str(p && p.id);
      const name = str(p && p.name);
      if (!ID_RE.test(id)) return err(`민족 #${i + 1}${name ? ` "${name}"` : ''}: id가 비었거나 올바르지 않습니다.`, 'peoples', i);
      if (pack.peoples.some(x => x.id === id)) return warn(`민족 "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'peoples', i);
      const o = { id, name: name || id };
      if (str(p.parent)) o.parent = str(p.parent); // 상위 민족(대명제)의 id나 이름 — 단계는 얼마든지
      if (HT.isColor(p.color)) o.color = p.color;
      if (str(p.description)) o.description = str(p.description);
      if (str(p.wiki)) o.wiki = String(p.wiki);
      if (p.order !== '' && p.order != null && isFinite(p.order)) o.order = Number(p.order);
      /* 배열 기준 (형식 버전 3 — HT.readRowOrder): 'start'(지금 규칙)도 적은 대로 둡니다(상위 민족의 기준을 물려받지 않게 끊는 값) */
      const ro = HT.readRowOrder(p.rowOrder);
      if (ro) o.rowOrder = ro;
      else if (ro === null) warn(`민족 "${name || id}": 배열 기준(rowOrder) "${str(p.rowOrder)}"을(를) 몰라 뺐습니다 — "start"(시작 연도) · "northSouth"(북 → 남).`, 'peoples', i);
      pack.peoples.push(o);
    });

    /* 지위 사전(rankDefs) — 있을 때만 칸이 생깁니다 (옛 파일은 그대로) */
    const rankDefs = HT.readRankDefs(raw.rankDefs);
    rankDefs.problems.forEach((msg, k) => warn(msg, 'rankDefs', rankDefs.at[k]));
    if (rankDefs.list.length) pack.rankDefs = rankDefs.list;

    /* 가문 — 국성 · 왕가 · 집안. 시대(= 국성) · 지도자 · 내각 · 왕조 · 인물의 house에 이 이름이나 id를 적습니다 (등록하지 않은 이름을 적어도 됩니다 — 모델이 그 이름으로 만듭니다).
       id를 비우면 이름으로 만들고, parent(본가)를 적으면 본가 → 분가 나무가 됩니다. 가문이 하나도 없으면 houses 열쇠를 만들지 않습니다 (옛 파일이 예전 그대로 나가게) */
    const houses = [];
    arr(raw.houses).forEach((h, i) => {
      if (!h || typeof h !== 'object') return err(`가문 #${i + 1}: 형식이 올바르지 않습니다.`, 'houses', i);
      const name = str(h.name);
      let id = str(h.id);
      const label = `가문 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!id && !name) return err(`${label}: 이름이 비어 있습니다.`, 'houses', i);
      if (id && !ID_RE.test(id)) return err(`${label}: id가 올바르지 않습니다.`, 'houses', i);
      if (!id) id = `h-${HT.hash(name)}`;
      if (houses.some(x => x.id === id)) return warn(`가문 "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'houses', i);
      const o = { id, name: name || id };
      for (const k of ['surname', 'seat', 'parent', 'founder']) if (str(h[k])) o[k] = str(h[k]); // 성 · 본관 · 본가(가문의 id나 이름) · 시조
      /* 세계표 머리의 구분(트랙 id) · 민족(이름 · id) · 꼬리표 (형식 버전 3 — D1 확정 설계 2-2): 트랙은 다른 DLC의 것일 수 있어 검사하지 않고, 비우면 모델이 짐작합니다(파일에 적지 않음) */
      for (const k of ['track', 'people']) if (str(h[k])) o[k] = str(h[k]);
      const htags = [...new Set((Array.isArray(h.tags) ? h.tags : str(h.tags).split(/[,，]/)).map(str).filter(Boolean))]; // 사건의 tags와 같은 읽기 (배열 · 쉼표 글)
      if (htags.length) o.tags = htags;
      if (HT.isColor(h.color)) o.color = h.color;
      if (str(h.description)) o.description = str(h.description);
      if (str(h.wiki)) o.wiki = String(h.wiki);
      putNames(o, h.names, label, 'houses', i); // 이름 목록 (형식 버전 3)
      houses.push(o);
    });
    if (houses.length) pack.houses = houses;

    /* 주제 사전(themes — 형식 버전 3): 있을 때만 칸이 생깁니다 (지위 사전과 같은 읽기 · 옛 파일은 그대로) */
    const themeDefs = HT.readThemeDefs(raw.themes);
    themeDefs.problems.forEach((msg, k) => warn(msg, 'themes', themeDefs.at[k]));
    if (themeDefs.list.length) pack.themes = themeDefs.list;
    /* 성씨 사전 (형식 버전 3 — 3-2 성씨 층): 가문의 surname(성)이 이 이름이나 id로 이어집니다. 사전에 없는 성도 됩니다(모델이 가문들의 성에서 저절로 모음).
       원어를 달고 싶을 때만 적습니다. id를 비우면 이름으로 만들고(sn-…), 목록이 비면 열쇠를 만들지 않습니다(옛 파일 그대로) */
    const surnames = [];
    arr(raw.surnames).forEach((x, i) => {
      if (!x || typeof x !== 'object') return err(`성씨 #${i + 1}: 형식이 올바르지 않습니다.`, 'surnames', i);
      const name = str(x.name);
      const label = `성씨 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, 'surnames', i);
      let id = str(x.id);
      if (id && !ID_RE.test(id)) return err(`${label}: id가 올바르지 않습니다.`, 'surnames', i);
      if (!id) id = `sn-${HT.hash(name)}`;
      if (surnames.some(q => q.id === id)) return warn(`성씨 "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'surnames', i);
      const o = { id, name };
      putNames(o, x.names, label, 'surnames', i);
      if (str(x.description)) o.description = str(x.description);
      if (str(x.wiki)) o.wiki = String(x.wiki);
      surnames.push(o);
    });
    if (surnames.length) pack.surnames = surnames;
    /* 지명 사전 (형식 버전 3 — 바탕 3): 도읍의 city · 사건의 place가 이 이름이나 id로 가리킵니다. 사전에 없는 이름도 됩니다(그 이름으로 저절로 — 가문 · 민족과 같은 규칙).
       at = 좌표 [x, y](지도가 실제 지리면 경도 · 위도, 그림이면 픽셀 — 두 수) · parent = 위 구역 지명(이름이나 id). id를 비우면 이름으로 만듭니다(pl-…) */
    const places = [];
    arr(raw.places).forEach((x, i) => {
      if (!x || typeof x !== 'object') return err(`지명 #${i + 1}: 형식이 올바르지 않습니다.`, 'places', i);
      const name = str(x.name);
      const label = `지명 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, 'places', i);
      let id = str(x.id);
      if (id && !ID_RE.test(id)) return err(`${label}: id가 올바르지 않습니다.`, 'places', i);
      if (!id) id = `pl-${HT.hash(name)}`;
      if (places.some(q => q.id === id)) return warn(`지명 "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'places', i);
      const o = { id, name };
      putNames(o, x.names, label, 'places', i);
      if (x.at != null && x.at !== '') {
        const at = HT.readCoords(x.at);
        if (at) o.at = at;
        else warn(`${label}: 좌표(at)는 [x, y] 두 수로 적습니다 — 뺐습니다.`, 'places', i);
      }
      if (str(x.parent)) {
        if (str(x.parent) === name || str(x.parent) === id) warn(`${label}: 위 구역(parent)이 자기 자신이라 뺐습니다.`, 'places', i);
        else o.parent = str(x.parent);
      }
      for (const k of ['note', 'description']) if (str(x[k])) o[k] = str(x[k]);
      if (str(x.wiki)) o.wiki = String(x.wiki);
      places.push(o);
    });
    if (places.length) pack.places = places;

    const itemIds = new Set();
    const takeId = (x, prefix, seed, label, kind, i) => {
      let id = str(x.id);
      if (id && !ID_RE.test(id)) {
        warn(`${label}: id "${id}"가 올바르지 않아 새로 만들었습니다.`, kind, i);
        id = '';
      }
      if (!id) id = prefix + HT.hash(seed);
      if (itemIds.has(id)) {
        let n = 2;
        while (itemIds.has(`${id}-${n}`)) n++;
        if (str(x.id)) warn(`${label}: id "${id}"가 중복되어 "${id}-${n}"(으)로 바꿨습니다.`, kind, i);
        id = `${id}-${n}`;
      }
      itemIds.add(id);
      return id;
    };
    /* 시작·끝 연도. "미정"이면 배치용 연도(startHint/endHint, 또는 startUnknown:true와 함께 적은 숫자)로 자리를 잡습니다 */
    const readRange = (x, label, kind, i) => {
      const ongoing = x.ongoing === true || HT.isOngoingText(x.end);
      const startUnknown = x.startUnknown === true || HT.isUnknownText(x.start);
      const endUnknown = !ongoing && (x.endUnknown === true || HT.isUnknownText(x.end));
      const hintOf = (v, raw) => {
        const h = toYear(v);
        if (h != null && !isNaN(h)) return h;
        const r = HT.isUnknownText(raw) ? null : toYear(raw);
        return r != null && !isNaN(r) ? r : null;
      };
      const sd = startUnknown ? null : dateIn(x, 'start');
      let start = sd ? sd.t : null;
      let startAt = sd ? sd.at : null;
      if (!startUnknown && (start == null || isNaN(start))) {
        err(`${label}: 시작 연도가 없거나 올바르지 않습니다.${sd && sd.error ? ` ${sd.error}` : ' (모르면 "미정"이라고 적으세요)'}`, kind, i);
        return null;
      }
      const ed = ongoing || endUnknown ? null : dateIn(x, 'end');
      let end = ed ? ed.t : null;
      let endAt = ed ? ed.at : null;
      if (end != null && isNaN(end)) {
        err(`${label}: 끝 연도가 올바르지 않습니다.${ed.error ? ` ${ed.error}` : ''}`, kind, i);
        return null;
      }
      const startHint = startUnknown ? hintOf(x.startHint, x.start) : null;
      const endHint = endUnknown ? hintOf(x.endHint, x.end) : null;
      if (startUnknown) start = startHint ?? end;
      if (start == null) {
        err(`${label}: 시작 연도가 미정이면 끝 연도나 배치용 연도(startHint)가 필요합니다.`, kind, i);
        return null;
      }
      if (endUnknown) end = endHint ?? start;
      if (end != null && HT.endBound(end, endAt) < start) {
        err(`${label}: 끝 연도가 시작 연도보다 앞섭니다.`, kind, i);
        return null;
      }
      if (end === start && !endUnknown && !startUnknown) end = endAt = null; // 같은 때에 끝나면 한 시점 — 시작이 미정이면 끝은 적은 사실이라 그대로 (배치용 연도가 없어 끝에 놓여도)
      if (startUnknown) startAt = null;
      if (endUnknown) endAt = null;
      return { start, end, ongoing, startUnknown, endUnknown, startAt, endAt };
    };
    const applyRange = (o, r) => {
      o.start = r.start;
      if (r.startAt) o.startAt = r.startAt;
      if (r.end != null) {
        o.end = r.end;
        if (r.endAt) o.endAt = r.endAt;
      }
      if (r.ongoing) o.ongoing = true;
      if (r.startUnknown) o.startUnknown = true;
      if (r.endUnknown) o.endUnknown = true;
    };
    const checkTrack = (track, label, kind, i) => {
      if (trackIds.has(track)) return true;
      err(track ? `${label}: 트랙 "${track}"이(가) 이 DLC의 트랙 목록에 없습니다.` : `${label}: 트랙이 지정되지 않았습니다.`, kind, i);
      return false;
    };
    /* 지도자·내각·연호 같은 칸 목록. 지도자는 묘호(temple)·시호(title)·이름(given)·대수(ordinal)를 따로 적을 수 있고,
       name이 없으면 묘호 → 시호 → 이름 순으로 대표 이름을 삼습니다. 대수가 빠진 지도자는 앞 지도자에 이어 자동으로 매깁니다.
       시작 · 끝에 "미정"도 됩니다(칸의 미정 — HT.readCellEdge): startUnknown/endUnknown + 배치용 연도가 있으면 start/end 숫자 */
    const readCells = (list, label, kind, i, what) => {
      const isLeader = what === '지도자';
      const out = arr(list)
        .map(c => (Array.isArray(c) ? { name: c[0], start: c[1], end: c[2], note: c[3] } : c || {}))
        .map(c => {
          const sd = HT.readCellEdge(c, 'start');
          const ed = HT.readCellEdge(c, 'end');
          return {
            name: str(c.name), temple: str(c.temple), title: str(c.title), given: str(c.given),
            ordinalUnknown: c.ordinalUnknown === true || HT.isUnknownOrdinal(c.ordinal), // 대수 미상 (묶음 5 · 4번)
            ordinal: c.ordinal === '' || c.ordinal == null || !isFinite(c.ordinal) ? null : Math.round(Number(c.ordinal)),
            regnal: HT.readRegnal(c.regnal), // 이름 번호 (6단계 D2 — 양의 정수 · 틀리면 NaN: 아래에서 알리고 뺌)
            start: sd ? sd.t : null, startAt: sd && sd.at, end: ed ? ed.t : null, endAt: ed && ed.at, error: (sd && sd.error) || (ed && ed.error) || '',
            startUnknown: !!(sd && sd.unknown), endUnknown: !!(ed && ed.unknown),
            note: str(c.note), dynasty: str(c.dynasty),
            rank: str(c.rank), // 지위 (지도자만)
            house: str(c.house),
            raw: c, // 확실성 · 연대 폭 · 이설은 아래에서 원본으로 읽습니다 (HT.readUncertain — 이름이 정해진 뒤에 알림 글을 달려고)
          };
        })
        .filter(c => {
          const ok = (c.name || c.temple || c.title || c.given) && (c.startUnknown || (c.start != null && !isNaN(c.start)));
          if (!ok) warn(`${label}: ${what} 항목 중 이름이나 연도가 없는 것을 뺐습니다(연도를 모르면 "미정"이라고 적습니다).${c.error ? ` (${c.name || '이름 없음'}: ${c.error})` : ''}`, kind, i);
          else if (c.startUnknown && c.endUnknown && c.start == null && c.end == null)
            warn(`${label}: ${what} "${c.name || c.temple || c.title || c.given}"은(는) 시작과 끝이 모두 미정이고 배치용 연도가 없어, 앞뒤 칸이나 정권의 기간에 맞춰 놓습니다.`, kind, i);
          return ok;
        })
        .map(c => {
          const o = { name: c.name || c.temple || c.title || c.given };
          if (c.start != null) o.start = c.start;
          if (c.startAt) o.startAt = c.startAt;
          if (c.startUnknown) o.startUnknown = true;
          if (isLeader) {
            if (c.temple) o.temple = c.temple;
            if (c.title) o.title = c.title;
            if (c.given) o.given = c.given;
            if (c.ordinalUnknown) o.ordinalUnknown = true;
            else if (c.ordinal != null) o.ordinal = c.ordinal;
            if (c.regnal > 0) o.regnal = c.regnal; // 이름 번호 — 표시는 대표 이름 뒤 'n세'(HT.leaderLabel) · 하나라도 있으면 그 줄은 대수를 자동으로 매기지 않음(HT.numberLeaders)
            else if (c.regnal != null) warn(`${label}: ${what} "${o.name}"의 이름 번호(regnal) "${String(c.raw.regnal)}"은(는) 양의 정수가 아니라 뺐습니다.`, kind, i);
            if (c.dynasty) o.dynasty = c.dynasty; // 왕조 (비우면 그 정권의 왕조 구간으로 채움)
            if (c.rank) o.rank = c.rank; // 지위 (비우면 시작한 해의 정권 지위로 채움 — 모델의 rankAuto)
          }
          if (c.end != null && !isNaN(c.end)) {
            o.end = c.end;
            if (c.endAt) o.endAt = c.endAt;
          }
          if (c.endUnknown) o.endUnknown = true;
          if (c.note) o.note = c.note;
          if (c.house && (isLeader || what === '내각')) o.house = c.house; // 가문(이름이나 id) — 지도자 · 내각 칸만 (연호에는 없음)
          Object.assign(o, HT.readUncertain(c.raw, { mode: 'cell', warn: m => warn(`${label}: ${what} "${o.name}" — ${m}`, kind, i), start: o.start, end: o.end })); // 칸의 확실성 · 연대 폭 · 이설 (디테일 건의 4)
          /* 형식 버전 3: 이름 목록(지도자 · 내각 · 연호) · 사람(지도자 · 내각) · 자리 이음 · 부모 · 배우자(지도자) — 짧은 꼴 [이름, 시작, 끝, 메모]에는 없음 */
          if (c.raw && typeof c.raw === 'object' && !Array.isArray(c.raw)) {
            const cl = `${label}: ${what} "${o.name}"`;
            if (what !== '집권') putNames(o, c.raw.names, cl, kind, i); // 단체의 집권 칸(power)에는 이름 목록이 없음 — 형식 문서 · 단체 폼과 같게 (읽어 두면 폼에 상자가 없어 그대로 저장해도 사라짐)
            putLineage(o, c.raw, cl, kind, i, { person: isLeader || what === '내각', accession: isLeader, kin: isLeader });
          }
          return o;
        });
      const sorted = HT.sortCells(out); // 시작 순 (시작이 미정인 칸은 끝 · 적힌 차례로)
      if (isLeader) HT.numberLeaders(sorted);
      return sorted;
    };
    /* 도읍: [도시, 시작, 끝, 역할|메모] 또는 { city, start, end, role, as(그때 이름), label(시기 이름), group(배도 묶음), event, note } */
    const readCapitals = (list, label, kind, i) =>
      HT.sortCells(
        arr(list)
          .map(c => {
            const o = HT.normalizeCapital(c, m => warn(`${label}: ${m}`, kind, i));
            if (!o) warn(`${label}: 도읍 항목 중 도시나 시작 연도가 없는 것을 뺐습니다(연도를 모르면 "미정"이라고 적습니다).`, kind, i);
            else if (o.startUnknown && o.endUnknown && o.start == null && o.end == null)
              warn(`${label}: 도읍 "${o.city}"은(는) 시작과 끝이 모두 미정이고 배치용 연도가 없어, 앞 정도의 끝이나 정권의 기간에 맞춰 놓습니다.`, kind, i);
            return o;
          })
          .filter(Boolean)
      );
    /* 승계 목록(시대의 succeeds · 패치의 set.succeeds): 이름만 적은 글도 읽고, 종류 · 정도 · 이어진 것은 한국어도 읽습니다(HT.normalizeSucc).
       한 쌍(선대 · 후대)에는 선 하나 — 같은 선대를 두 번 적으면 첫 줄만 씁니다 */
    const readSuccList = (list, label, kind, i) => {
      const out = [];
      for (const x of arr(list)) {
        const o = HT.normalizeSucc(x, m => warn(`${label}: ${m}`, kind, i));
        if (!o) continue;
        if (out.some(y => y.from === o.from)) {
          warn(`${label}: 승계 "${o.from}"이(가) 두 번 적혀 있어 첫 줄만 씁니다 (한 쌍에는 선 하나 — 둘 중 하나의 종류를 고릅니다).`, kind, i);
          continue;
        }
        out.push(o);
      }
      return out;
    };
    /* 칸의 미정: 소속 기간(시대의 partOf · 기관의 host · 왕조의 polities — HT.readPartOf로 읽은 것)의 시작과 끝이 모두 미정이고 배치용 연도가 없으면
       칸과 같은 말투로 경고합니다. what = 무엇의 기간인지, where = 어디에 놓는지 */
    const warnPartOfUnknown = (refs, label, kind, i, what, where) => {
      for (const x of refs)
        if (x.startUnknown && x.endUnknown && x.start == null && x.end == null)
          warn(`${label}: ${what} "${x.polity}"의 기간은 시작과 끝이 모두 미정이고 배치용 연도가 없어, ${where} 놓습니다.`, kind, i);
    };
    /* 확실성 등급 · 연대 폭 · 이설 · 쟁점 — 칸 · 시대 구분 · 인물과 같은 읽기(HT.readUncertain), 알림 글은 예전 그대로("시대 #1 "…": …") */
    const readUncertainty = (x, label, kind, i, start) => HT.readUncertain(x, { warn: m => warn(`${label}: ${m}`, kind, i), start });

    /* 이름 목록(관련 인물 · 다른 이름 · 태그): 배열이나 쉼표로 이은 글 → 빈 것 · 겹친 것을 뺀 배열 */
    const readNames = v => [...new Set((Array.isArray(v) ? v : str(v).split(/[,，]/)).map(str).filter(Boolean))];
    /* 인물의 섬긴 기록: [{ track?, polity, office(직함), start, end, note }] — 적은 차례 그대로(첫 줄이 대표 정권). 기간의 시작 · 끝에 "미정"도 됩니다(칸의 미정).
       다른 트랙의 정권도 가리킬 수 있습니다(track을 비우면 인물의 트랙). 글로 적은 "트랙:정권" · "정권"도 읽습니다.
       그 track은 여기서 검사하지 않습니다(기본팩 같은 다른 DLC의 트랙일 수 있음) — 모델이 못 찾으면 상세에 글로만 남습니다 */
    const FIGURE_DATE_WORDS = { birth: '출생', death: '사망', start: '활동 시작', end: '활동 끝' };
    const readService = (list, label, kind, i) => {
      const out = [];
      for (const raw0 of Array.isArray(list) ? list : list == null || list === '' ? [] : [list]) {
        let s = raw0;
        if (typeof s === 'string') {
          const j = s.indexOf(':');
          s = j > 0 ? { track: s.slice(0, j), polity: s.slice(j + 1) } : { polity: s };
        }
        if (!s || typeof s !== 'object') continue;
        const polity = str(s.polity ?? s.name);
        if (!polity) {
          warn(`${label}: 활동 기록 가운데 정권이 없는 줄을 뺐습니다.`, kind, i);
          continue;
        }
        const o = {};
        if (str(s.track)) o.track = str(s.track);
        o.polity = polity;
        if (str(s.office ?? s.title)) o.office = str(s.office ?? s.title);
        for (const k of ['start', 'end']) {
          const d = HT.readCellEdge(s, k); // 칸의 미정: "미정" 글 · startUnknown · startHint → 미정 + (있으면) 배치용 연도 — 없으면 비운 것과 같은 자리(활동 시작 · 끝)
          if (!d) continue;
          if (d.unknown) {
            if (d.t != null) o[k] = d.t;
            o[`${k}Unknown`] = true;
            continue;
          }
          if (isNaN(d.t)) {
            warn(`${label}: 활동 기록 "${polity}"의 ${k === 'start' ? '시작' : '끝'} 날짜를 읽을 수 없어 비웠습니다.${d.error ? ` ${d.error}` : ''}`, kind, i);
            continue;
          }
          o[k] = d.t;
          if (d.at) o[`${k}At`] = d.at;
        }
        if (o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) {
          /* 거꾸로면 짐작인 쪽을 버립니다(활동 시기 · 지위 변천과 같은 규칙): 시작만 미정이면 시작의 배치용 연도 — 적은 끝은 사실이라 남김 */
          if (o.startUnknown && !o.endUnknown) {
            warn(`${label}: 활동 기록 "${polity}"의 끝이 시작보다 앞서서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로).`, kind, i);
            delete o.start;
          } else {
            warn(`${label}: 활동 기록 "${polity}"의 끝이 시작보다 앞서서 끝을 비웠습니다${o.endUnknown ? '(미정인 끝의 배치용 연도를 버림)' : ''}.`, kind, i);
            delete o.end;
            delete o.endAt;
          }
        }
        if (str(s.note)) o.note = str(s.note);
        Object.assign(o, HT.readUncertain(s, { mode: 'cell', warn: m => warn(`${label}: 활동 기록 "${polity}" — ${m}`, kind, i), start: o.start, end: o.end })); // 확실성 · 연대 폭 · 이설 (다른 칸과 같은 읽기)
        out.push(o);
      }
      return out;
    };

    /* 시대 구분(선사·고대·중세·근세·근대·현대 …): 맨 위 날짜 칸에 색 띠로. track을 적으면 그 나라 줄에, 비우면 공통 줄에 */
    arr(raw.epochs).forEach((e, i) => {
      if (!e || typeof e !== 'object') return err(`시대 구분 #${i + 1}: 형식이 올바르지 않습니다.`, 'epochs', i);
      const name = str(e.name);
      const label = `시대 구분 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, 'epochs', i);
      const track = str(e.track);
      if (track && !checkTrack(track, label, 'epochs', i)) return;
      const r = readRange(e, label, 'epochs', i);
      if (!r) return;
      const o = { id: takeId(e, 'ep-', track + Math.floor(r.start + 1e-9) + name, label, 'epochs', i), name };
      applyRange(o, r);
      if (track) o.track = track;
      /* 형식 4 더하기 — 시대 구분의 문화권(sphere · 5단계 과제 6): 그 문화권 머리 단 밑 시대 줄에(서고 그림은 과제 9). 트랙과 양자택일 — 둘 다 적으면 트랙이 우선하고 경고합니다(둘 다 지켜 고칠 수 있게) */
      if (str(e.sphere)) {
        const sp = str(e.sphere);
        if (!ID_RE.test(sp)) warn(`${label}: 문화권 id "${sp}"이(가) 올바르지 않아 뺐습니다.`, 'epochs', i);
        else {
          o.sphere = sp;
          if (track) warn(`${label}: 트랙과 문화권을 함께 적어 트랙이 우선합니다 — 문화권 줄에 두려면 트랙을 비우세요.`, 'epochs', i);
        }
      }
      if (HT.isColor(e.color)) o.color = e.color;
      if (str(e.note)) o.note = str(e.note);
      if (str(e.description)) o.description = str(e.description);
      if (str(e.wiki)) o.wiki = String(e.wiki);
      if (str(e.within)) o.within = str(e.within); // 든 그릇(대범위 id · 이름 — 리메이크 2부 포개짐): 그 그릇 윗변의 둘째 탭으로 그리고 날짜 칸에는 싣지 않음
      Object.assign(o, HT.readUncertain(e, { mode: 'epoch', warn: m => warn(`${label}: ${m}`, 'epochs', i) })); // 다른 견해만 (디테일 건의 4 — 확실성 · 연대 폭은 받지 않음)
      pack.epochs.push(o);
    });

    /* 대범위 (docs/구상-체제-확장.md 7 · 8-4 바): 여러 민족 묶음에 흩어진 정권들을 한 집합으로 묶어, 켜면 한 가지로 모여 보이는 단위.
       track · members(구성 정권 — "이름" · "트랙:이름" · { track, polity }) 필수, name은 epoch(같은 뜻의 시대 구분)이 없을 때 필수.
       기간(start · end)은 선택 — 비우면 시대 구분에서, 그것도 없으면 구성 정권의 범위에서(모델). host = 상징적 본국(할거 · 부흥).
       시대 구분과 같은 부류라 패치 · 연표의 수정 대상이 아닙니다. 목록이 비면 파일에 적지 않습니다(옛 파일과 1px도 다르지 않게) */
    const scopes = [];
    arr(raw.scopes).forEach((s, i) => {
      if (!s || typeof s !== 'object') return err(`대범위 #${i + 1}: 형식이 올바르지 않습니다.`, 'scopes', i);
      const name = str(s.name);
      const epoch = str(s.epoch);
      const label = `대범위 #${i + 1}${name || epoch ? ` "${name || epoch}"` : ''}`;
      if (!name && !epoch) return err(`${label}: 이름이 비어 있습니다. (시대 구분(epoch)을 적으면 그 이름을 물려받습니다)`, 'scopes', i);
      const track = str(s.track);
      if (!checkTrack(track, label, 'scopes', i)) return;
      const refs = [];
      for (const r of HT.readScopeRefs(s.members)) if (!refs.some(q => q.polity === r.polity && (q.track || track) === (r.track || track))) refs.push(r);
      if (!refs.length) return err(`${label}: 구성 정권(members)이 없습니다.`, 'scopes', i);
      const hasStart = s.start != null && s.start !== '';
      let r = null;
      if (hasStart) {
        r = readRange(s, label, 'scopes', i);
        if (!r) return;
      } else if ((s.end != null && s.end !== '') || s.ongoing === true) warn(`${label}: 시작 없이 끝만 적어 기간을 무시했습니다. (비우면 시대 구분이나 구성 정권의 기간을 씁니다)`, 'scopes', i);
      const o = { id: takeId(s, 's-', track + (name || epoch) + (r ? Math.floor(r.start + 1e-9) : ''), label, 'scopes', i), track };
      if (name) o.name = name;
      if (str(s.label)) o.label = str(s.label);
      if (r) applyRange(o, r);
      o.members = refs.map(HT.compactScopeRef);
      if (epoch) o.epoch = epoch;
      // 부모 그릇(리메이크 2부 · 설계 3-3 포개짐 — 같은 트랙의 대범위 id · 이름): 이 그릇은 부모 그릇 안의 안쪽 그릇(새 앱은 상자)
      if (str(s.within)) {
        if (str(s.within) === str(s.id) || str(s.within) === name) warn(`${label}: 부모 그릇(within)이 자기 자신이라 뺐습니다.`, 'scopes', i);
        else o.within = str(s.within);
      }
      const host = HT.readScopeRef(s.host);
      if (host) {
        o.host = HT.compactScopeRef(host);
        if (refs.some(q => q.polity === host.polity && (q.track || track) === (host.track || track))) warn(`${label}: 상징적 본국 "${host.polity}"이(가) 구성 정권에도 들어 있습니다. 본국은 모이지 않습니다.`, 'scopes', i);
      }
      const other = refs.filter(q => q.track && q.track !== track);
      if (other.length) warn(`${label}: 다른 트랙의 정권(${other.map(q => `${q.track}:${q.polity}`).join(', ')})은 모이지 않습니다. 구성 정권은 같은 트랙 안에서만 모입니다.`, 'scopes', i);
      if (HT.isColor(s.color)) o.color = s.color;
      if (s.default === true) o.default = true; // 처음부터 켬 (끔이 기본이라 false는 적지 않음)
      if (str(s.description)) o.description = str(s.description);
      if (str(s.note)) o.note = str(s.note);
      if (str(s.wiki)) o.wiki = String(s.wiki);
      scopes.push(o);
    });
    if (scopes.length) pack.scopes = scopes;

    /* 형식 3 — 모아 보기 판 · 지도(1단계) · 글꼴 (위의 HT.readViews · HT.readMaps · HT.readFonts). 목록이 비면 열쇠를 만들지 않습니다 */
    for (const [key, read, what] of [['views', HT.readViews, '모아 보기 판(views)'], ['maps', HT.readMaps, '지도(maps)'], ['fonts', HT.readFonts, '글꼴(fonts)']]) {
      if (raw[key] == null) continue;
      if (!Array.isArray(raw[key])) {
        warn(`${what}은 목록이어야 해서 무시했습니다.`, key);
        continue;
      }
      const list = read(raw[key], { err: (msg, i) => err(msg, key, i), warn: (msg, i) => warn(msg, key, i) });
      if (list.length) pack[key] = list;
    }
    /* 형식 3 — 간지 설정 (HT.readYearCycle): false(간지 줄 기본 끔) · { names, start, label }. 적지 않으면 열쇠를 만들지 않습니다(육십갑자 — 옛 파일 그대로) */
    {
      const yc = HT.readYearCycle(raw.yearCycle, msg => warn(msg, 'yearCycle'));
      if (yc !== undefined) pack.yearCycle = yc;
    }
    /* 형식 4 더하기 — 문화권별 주기 줄(yearCycles · HT.readYearCycles · 5단계 과제 6): 다리(HT.F4.down)가 그대로 실어 오는 것을 정규화가 지킵니다(메이커의 「주기」 표). 목록이 비면 열쇠를 만들지 않습니다 */
    if (raw.yearCycles != null) {
      const ycs = HT.readYearCycles(raw.yearCycles, (msg, i) => warn(msg, 'yearCycles', i));
      if (ycs.length) pack.yearCycles = ycs;
    }
    /* 형식 3 — 문서 그림(images — 아래 HT.readImages · DLC-형식.md '문서 그림'). 목록이 비면 열쇠를 만들지 않습니다 */
    if (raw.images != null) {
      if (!Array.isArray(raw.images)) warn('문서 그림(images)은 목록이어야 해서 무시했습니다.', 'images');
      else {
        const list = HT.readImages(raw.images, { err: (msg, i) => err(msg, 'images', i), warn: (msg, i) => warn(msg, 'images', i) });
        if (list.length) pack.images = list;
      }
    }

    /* 기관: 주권 정권 위에 얹힌 외세 기관·특수 구역(통감부·총독부·조계지·군정청). 얹히는 정권(host)의 띠 아래쪽에 굵은 띠로 그립니다.
       옛 형식(시대의 kind: "overlay")도 여기로 옮겨 읽습니다 */
    const readOrgan = (g, i, legacy) => {
      const kindKey = legacy ? 'periods' : 'organs';
      if (!g || typeof g !== 'object') return err(`기관 #${i + 1}: 형식이 올바르지 않습니다.`, kindKey, i);
      const name = str(g.name ?? g.title);
      const label = `기관 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, kindKey, i);
      const track = str(g.track);
      if (!checkTrack(track, label, kindKey, i)) return;
      const r = readRange(g, label, kindKey, i);
      if (!r) return;
      const o = { id: takeId(g, 'g-', track + Math.floor(r.start + 1e-9) + name, label, kindKey, i), track, name };
      applyRange(o, r);
      const host = HT.readPartOf(g.host ?? g.partOf, { warn: m => warn(`${label}: 얹히는 정권 ${m}`, kindKey, i) });
      if (host.length) o.host = HT.compactPartOf(host);
      else warn(`${label}: 얹히는 정권(host)이 없어 보통 띠로 그립니다.`, kindKey, i);
      warnPartOfUnknown(host, label, kindKey, i, '얹히는 정권', '기관의 기간 전체에');
      Object.assign(o, readUncertainty(g, label, kindKey, i, r.start));
      /* 크기: agency(기관 — 시대 띠 안 맨 아래의 기관 칸) · zone(조계지·조차지 같은 구역 — 띠 아래로 내려오는 탭). 없으면 이름으로 짐작 */
      const scale = str(g.scale);
      if (scale === 'zone' || scale === 'agency') o.scale = scale;
      else if (/조계|조차|租界|租借|거류지|居留地|공사관 ?구역|특구|왜관|倭館/.test(name)) o.scale = 'zone'; // 왜관도 구역(묶음 3 · 3번)
      if (HT.isColor(g.color)) o.color = g.color;
      if (str(g.description)) o.description = str(g.description);
      if (str(g.note)) o.note = str(g.note);
      if (str(g.wiki)) o.wiki = String(g.wiki);
      pack.organs.push(o);
    };
    /* 문화: 국가 이전의 고고학 문화. 승계한 국가(successors, 또는 국가 쪽의 succeeds)가 있으면 그 줄 밑에 바탕 띠로 깔립니다 */
    const readCulture = (c, i, legacy) => {
      const kindKey = legacy ? 'periods' : 'cultures';
      if (!c || typeof c !== 'object') return err(`문화 #${i + 1}: 형식이 올바르지 않습니다.`, kindKey, i);
      const name = str(c.name ?? c.title);
      const label = `문화 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, kindKey, i);
      const track = str(c.track);
      if (!checkTrack(track, label, kindKey, i)) return;
      const r = readRange(c, label, kindKey, i);
      if (!r) return;
      const o = { id: takeId(c, 'c-', track + Math.floor(r.start + 1e-9) + name, label, kindKey, i), track, name };
      applyRange(o, r);
      Object.assign(o, readUncertainty(c, label, kindKey, i, r.start));
      const succ = (Array.isArray(c.successors) ? c.successors : str(c.successors).split(',')).map(str).filter(Boolean);
      if (succ.length) o.successors = succ;
      const pre = arr(c.succeeds)
        .map(x => (typeof x === 'string' ? { from: x } : x || {}))
        .map(x => ({ from: str(x.from), type: str(x.type) === 'direct' ? 'direct' : 'indirect' }))
        .filter(x => x.from);
      if (pre.length) o.succeeds = pre;
      if (str(c.people)) o.people = str(c.people);
      if (HT.isColor(c.color)) o.color = c.color;
      if (str(c.description)) o.description = str(c.description);
      if (str(c.wiki)) o.wiki = String(c.wiki);
      pack.cultures.push(o);
    };
    /* 왕조: 나라(국체)를 다스린 왕가. polities(다스린 정권 — 기간을 적으면 그 구간만)의 시대 띠 맨 위 왕조 칸에 그립니다.
       동아시아처럼 나라와 왕조가 같으면 적지 않아도 되고, 한 나라의 왕조가 바뀌거나(프랑스: 카페 → 발루아 → 부르봉)
       한 왕조가 여러 나라를 다스릴 때(합스부르크: 오스트리아·스페인) 씁니다 */
    const readDynasty = (d, i, legacy) => {
      const kindKey = legacy ? 'periods' : 'dynasties';
      if (!d || typeof d !== 'object') return err(`왕조 #${i + 1}: 형식이 올바르지 않습니다.`, kindKey, i);
      const name = str(d.name ?? d.title);
      const label = `왕조 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, kindKey, i);
      const track = str(d.track);
      if (!checkTrack(track, label, kindKey, i)) return;
      const r = readRange(d, label, kindKey, i);
      if (!r) return;
      const o = { id: takeId(d, 'y-', track + Math.floor(r.start + 1e-9) + name, label, kindKey, i), track, name };
      applyRange(o, r);
      const ruled = HT.readPartOf(d.polities ?? d.rules ?? d.host ?? d.partOf, { warn: m => warn(`${label}: 다스린 정권 ${m}`, kindKey, i) });
      if (ruled.length) o.polities = HT.compactPartOf(ruled);
      else warn(`${label}: 다스린 정권(polities)이 없어 연표의 시대 띠에는 그려지지 않습니다.`, kindKey, i);
      warnPartOfUnknown(ruled, label, kindKey, i, '다스린 정권', '왕조의 기간 전체에');
      Object.assign(o, readUncertainty(d, label, kindKey, i, r.start));
      if (str(d.house)) o.house = str(d.house);
      if (HT.isColor(d.color)) o.color = d.color;
      if (str(d.description)) o.description = str(d.description);
      if (str(d.note)) o.note = str(d.note);
      if (str(d.wiki)) o.wiki = String(d.wiki);
      putNames(o, d.names, label, kindKey, i); // 이름 목록 (형식 버전 3)
      pack.dynasties.push(o);
    };
    /* 소속 관계 · 놓는 자리 검사 (시대의 partOf와 시대를 고치는 패치의 set.partOf): 모르는 관계와 true/false가 아닌 nest는 버리고 알립니다 */
    const checkPartOf = (v, label, where, i) => {
      for (const x of Array.isArray(v) ? v : [v]) {
        if (!x || typeof x !== 'object') continue;
        if (str(x.relation) && !HT.relationId(x.relation)) warn(`${label}: 소속 관계 "${str(x.relation)}"을(를) 알 수 없어 무시했습니다.`, where, i);
        if (x.nest != null && x.nest !== '' && typeof x.nest !== 'boolean') warn(`${label}: 놓는 자리(nest)는 true나 false로 적습니다 — "${str(x.nest)}"은(는) 무시했습니다.`, where, i);
      }
    };

    arr(raw.periods).forEach((p, i) => {
      if (!p || typeof p !== 'object') return err(`시대 #${i + 1}: 형식이 올바르지 않습니다.`, 'periods', i);
      if (str(p.kind) === 'overlay') return readOrgan(Object.assign({}, p, { host: p.host ?? p.partOf }), i, true);
      if (str(p.kind) === 'culture') return readCulture(p, i, true);
      if (str(p.kind) === 'dynasty') return readDynasty(Object.assign({}, p, { polities: p.polities ?? p.partOf }), i, true);
      const name = str(p.name ?? p.title);
      const label = `시대 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, 'periods', i);
      const track = str(p.track);
      if (!checkTrack(track, label, 'periods', i)) return;
      const r = readRange(p, label, 'periods', i);
      if (!r) return;
      const o = { id: takeId(p, 'p-', track + Math.floor(r.start + 1e-9) + name, label, 'periods', i), track, name };
      applyRange(o, r);
      const kind = HT.polityKindId(p.kind) || str(p.kind); // 한국어 이름("괴뢰국")도 읽습니다
      if (kind && kind !== 'state') {
        if (HT.POLITY_KINDS.some(k => k.id === kind)) o.kind = kind;
        else warn(`${label}: 정권 종류 "${kind}"을(를) 알 수 없어 국가로 봅니다.`, 'periods', i);
      }
      /* 형식 4의 칸(5단계 과제 3 — 메이커의 객체 표): 객체 종류 type(열여덟 — 사람은 인물 목록) · 정통성 status · 중요도 importance.
         옛 종류(kind)와 나란히 둡니다 — type은 다리가 옛 종류로 되살릴 수 없는 종류(도시 · 나라 · 동군연합 · 동맹 · 실권 정권 · 교단 · 기사단 · 회사 · 직위)일 때만 적힙니다 */
      const otype = HT.F4 ? HT.F4.typeId(p.type) : '';
      if (otype && otype !== 'state' && otype !== 'person') {
        const k = HT.F4.kindOfType(otype);
        if (!o.kind && k !== 'state') o.kind = k; // 옛 종류를 비우고 객체 종류만 적은 항목(제후국 · 연방 …)은 옛 종류로 풀어 지금 화면이 그 띠로 그림
        if (HT.F4.typeOfKind(o.kind || 'state') !== otype) o.type = otype;
      }
      else if (str(p.type) && !otype) warn(`${label}: 객체 종류 "${str(p.type)}"을(를) 알 수 없어 옛 종류대로 봅니다.`, 'periods', i);
      else if (otype === 'person') warn(`${label}: 사람은 인물 목록에 적습니다 — 옛 종류대로 봅니다.`, 'periods', i);
      const ostatus = HT.F4 ? HT.F4.statusId(p.status) : '';
      if (ostatus) o.status = ostatus;
      else if (str(p.status)) warn(`${label}: 정통성 "${str(p.status)}"을(를) 알 수 없어 뺐습니다(정통 · 대립 · 공동 · 섭정 · 명목 · 주장).`, 'periods', i);
      if (p.importance !== '' && p.importance != null) {
        const n = Number(p.importance);
        if ([0, 1, 2, 3].includes(n)) o.importance = n;
        else warn(`${label}: 중요도는 0~3이어야 해서 뺐습니다(비우면 기간 길이로 짐작).`, 'periods', i);
      }
      const partOf = HT.readPartOf(p.partOf, { relation: true, warn: m => warn(`${label}: 소속 ${m}`, 'periods', i) });
      if (partOf.length) o.partOf = HT.compactPartOf(partOf);
      /* 소속 관계 · 놓는 자리 검사: 모르는 관계 · 잘못 적은 nest는 버리고 알립니다. 접기(nest: true)는 상위 정권이 하나이고 기간이 없을 때만 통합니다
         (기간의 한쪽이라도 "미정"이면 기간이 있는 것 — 모델의 singleHost와 같은 조건) */
      checkPartOf(p.partOf, label, 'periods', i);
      if (partOf.some(x => x.nest === true) && (partOf.length > 1 || partOf[0].start != null || partOf[0].end != null || partOf[0].startUnknown || partOf[0].endUnknown)) warn(`${label}: 상위 띠 아래에 접기(nest)는 상위 정권이 하나이고 기간을 적지 않았을 때만 됩니다 — 제 줄에 놓입니다.`, 'periods', i);
      warnPartOfUnknown(partOf, label, 'periods', i, '소속', '앞뒤 소속의 기간이나 정권의 기간에 맞춰');
      if (str(p.wiki)) o.wiki = String(p.wiki);
      Object.assign(o, readUncertainty(p, label, 'periods', i, r.start));
      /* 실재성 (8-4 마): 한국어도 읽고, 실재(attested)는 기본값이라 적지 않습니다 */
      const hs = HT.historicity(p.historicity);
      if (hs && hs !== 'attested') o.historicity = hs;
      else if (!hs && str(p.historicity)) warn(`${label}: 실재성 "${str(p.historicity)}"을(를) 알 수 없어 실재로 봅니다.`, 'periods', i);
      if (str(p.historicityNote)) o.historicityNote = str(p.historicityNote);
      const leaders = readCells(p.leaders || p.reigns, label, 'periods', i, '지도자');
      if (leaders.length) o.leaders = leaders;
      const cabinets = readCells(p.cabinets, label, 'periods', i, '내각');
      if (cabinets.length) o.cabinets = cabinets;
      /* 형식 4의 직위 줄(5단계 과제 4): 지도자 · 내각 자리 밖의 줄(offices — 이름 + 칸, 또는 빌림 from "객체 id" · "객체 id/직위 이름") · 두 자리의 빌림(leadersFrom · cabinetsFrom — { from, name? }) ·
         실권(power — 쥔 쪽에만 적고 over가 빼앗긴 상대 객체). 모델은 아직 읽지 않습니다(서고 그림은 과제 9) — 다리(HT.F4)가 올리고 내립니다 */
      const offices = [];
      arr(p.offices).forEach((f, j) => {
        if (!f || typeof f !== 'object' || Array.isArray(f)) return warn(`${label}: 직위 줄 더 ${j + 1}번째: 형식이 올바르지 않습니다.`, 'periods', i);
        const name = str(f.name);
        const from = str(f.from);
        if (!name && !from) return warn(`${label}: 직위 줄 더 ${j + 1}번째: 이름이 없습니다.`, 'periods', i);
        if (from) {
          if (arr(f.cells).length) warn(`${label}: 직위 줄 "${name || from}"에 빌림(from)과 칸이 함께 있어 빌림만 씁니다.`, 'periods', i);
          offices.push(Object.assign(name ? { name } : {}, { from }));
          return;
        }
        offices.push({ name, cells: readCells(f.cells, label, 'periods', i, `직위 줄 "${name}"`) });
      });
      if (offices.length) o.offices = offices;
      for (const [k, word] of [['leadersFrom', '지도자'], ['cabinetsFrom', '내각']]) {
        const v = p[k];
        if (v == null || v === '') continue;
        const from = str(typeof v === 'string' ? v : v && v.from);
        if (!from) {
          warn(`${label}: ${word} 줄의 빌림(${k})에 출처가 없어 뺐습니다 — "객체 id" 또는 "객체 id/직위 이름".`, 'periods', i);
          continue;
        }
        const b = {};
        const nm = v && typeof v === 'object' ? str(v.name) : '';
        if (nm && nm !== word) b.name = nm;
        b.from = from;
        o[k] = b;
      }
      const power = [];
      arr(p.power).forEach((c, j) => {
        const x = Array.isArray(c) ? { name: c[0], start: c[1], end: c[2], note: c[3] } : c && typeof c === 'object' ? c : null;
        if (!x) return warn(`${label}: 실권 ${j + 1}번째 줄: 형식이 올바르지 않습니다.`, 'periods', i);
        const over = str(x.over);
        /* 상대(over) 없이 이름만 = 제 안의 실권자(세도 가문 · 권신 · 환관 — 쥔 쪽이 객체가 아닐 때 빼앗긴 쪽에 이름 글로 · 프롬프트 판 2 '실권' 9 · 2026-10-24) */
        if (!over && !str(x.name)) return warn(`${label}: 실권 ${j + 1}번째 줄: 상대(over)도 이름도 없어 뺐습니다 — 남의 실권은 쥔 쪽에 over로, 제 안의 실권자(세도 가문 · 권신)는 이름으로 적습니다.`, 'periods', i);
        const w = {};
        if (str(x.name)) w.name = str(x.name);
        if (over) w.over = over;
        for (const edge of ['start', 'end']) {
          const d = HT.readCellEdge(x, edge);
          if (!d) continue;
          if (d.unknown) {
            if (d.t != null) w[edge] = d.t;
            w[`${edge}Unknown`] = true;
          } else if (!isNaN(d.t)) {
            w[edge] = d.t;
            if (d.at) w[`${edge}At`] = d.at;
          } else warn(`${label}: 실권 ${j + 1}번째 줄: ${edge === 'start' ? '시작' : '끝'} 연도가 올바르지 않습니다.`, 'periods', i);
        }
        if (str(x.note)) w.note = str(x.note);
        power.push(w);
      });
      if (power.length) o.power = power;
      if (str(p.people)) o.people = str(p.people);
      if (str(p.house)) o.house = str(p.house); // 국성: 나라를 다스린 가문(가문의 id나 이름) — 가문을 적지 않은 지도자는 이 가문으로 봅니다
      const succ = readSuccList(p.succeeds, label, 'periods', i);
      if (succ.length) o.succeeds = succ;
      const eras = readCells(p.eras, label, 'periods', i, '연호');
      if (eras.length) o.eras = eras;
      const capitals = readCapitals(p.capitals, label, 'periods', i);
      if (capitals.length) o.capitals = capitals;
      /* 시기 구분(학계): 체계 목록으로 정리 (납작한 꼴도 체계별로 묶음) · 겹침과 정권 기간 밖의 시기는 알림 */
      const phases = HT.readPhases(p.phases);
      phases.problems.concat(phases.warnings).forEach(msg => warn(`${label}: ${msg}`, 'periods', i));
      if (phases.list.length) {
        o.phases = phases.list;
        const lo = r.startUnknown ? -Infinity : r.start - 1e-9;
        const hi = r.endUnknown || r.ongoing ? Infinity : HT.endBound(r.end ?? r.start, r.end != null ? r.endAt : r.startAt) + 1e-9;
        const out = phases.list.flatMap(g => g.spans).find(sp => [sp.start, sp.end].some(t => t != null && (t < lo || t > hi)));
        if (out) warn(`${label}: 시기 구분의 시기 "${out.name}"이(가) 정권 기간 밖으로 나갑니다 — 띠 안에는 정권 기간까지만 그립니다.`, 'periods', i);
      }
      /* 지위 변천: 칸 목록(이름 기준 — rank도 읽음) · 시작을 비울 수 있는 것은 첫 칸뿐 · 겹침과 정권 기간 밖의 지위는 알림 */
      const ranks = HT.readRanks(p.ranks);
      ranks.problems.concat(ranks.warnings).forEach(msg => warn(`${label}: ${msg}`, 'periods', i));
      if (ranks.list.length) {
        o.ranks = ranks.list;
        const lo = r.startUnknown ? -Infinity : r.start - 1e-9;
        const hi = r.endUnknown || r.ongoing ? Infinity : HT.endBound(r.end ?? r.start, r.end != null ? r.endAt : r.startAt) + 1e-9;
        const out = ranks.list.find(c => [c.start, c.end].some(t => t != null && (t < lo || t > hi)));
        if (out) warn(`${label}: 지위 "${out.name}"의 기간이 정권 기간 밖으로 나갑니다 — 띠 안에는 정권 기간까지만 그립니다.`, 'periods', i);
      }
      /* 종교(faiths — 6단계 D8 · 형식 4 더하기): 지위 변천과 같은 칸 목록 · 같은 알림(겹침 · 정권 기간 밖) */
      const faiths = HT.readFaiths(p.faiths);
      faiths.problems.concat(faiths.warnings).forEach(msg => warn(`${label}: ${msg}`, 'periods', i));
      if (faiths.list.length) {
        o.faiths = faiths.list;
        const lo = r.startUnknown ? -Infinity : r.start - 1e-9;
        const hi = r.endUnknown || r.ongoing ? Infinity : HT.endBound(r.end ?? r.start, r.end != null ? r.endAt : r.startAt) + 1e-9;
        const out = faiths.list.find(c => [c.start, c.end].some(t => t != null && (t < lo || t > hi)));
        if (out) warn(`${label}: 종교 "${out.name}"의 기간이 정권 기간 밖으로 나갑니다 — 띠 안에는 정권 기간까지만 그립니다.`, 'periods', i);
      }
      if (HT.isColor(p.color)) o.color = p.color;
      if (str(p.description)) o.description = str(p.description);
      putNames(o, p.names, label, 'periods', i); // 이름 목록 — 원어 · 로마자 · 국호 변천(start · end) (형식 버전 3)
      const ptags = readNames(p.tags); // 승계표 머리 끝의 꼬리표 (형식 버전 3 — D1 확정 설계 2-2 · 사건의 tags와 같은 읽기)
      if (ptags.length) o.tags = ptags;
      const ns = HT.readNorthSouth(p.northSouth); // 남북 위치 (형식 버전 3 — 민족의 배열 기준 '북 → 남'이 씀 · 클수록 북)
      if (Number.isFinite(ns)) o.northSouth = ns;
      else if (ns !== undefined) warn(`${label}: 남북 위치(northSouth)는 수여야 해서 뺐습니다 — 클수록 북 (비우면 첫 정도의 지명 좌표).`, 'periods', i);
      pack.periods.push(o);
    });
    arr(raw.organs).forEach((g, i) => readOrgan(g, i, false));
    arr(raw.cultures).forEach((c, i) => readCulture(c, i, false));
    arr(raw.dynasties).forEach((d, i) => readDynasty(d, i, false));

    arr(raw.events).forEach((e, i) => {
      if (!e || typeof e !== 'object') return err(`사건 #${i + 1}: 형식이 올바르지 않습니다.`, 'events', i);
      const title = str(e.title ?? e.name);
      const label = `사건 #${i + 1}${title ? ` "${title}"` : ''}`;
      if (!title) return err(`${label}: 제목이 비어 있습니다.`, 'events', i);
      const track = str(e.track);
      if (!checkTrack(track, label, 'events', i)) return;
      const r = readRange(e, label, 'events', i);
      if (!r) return;
      const o = { id: takeId(e, 'e-', track + Math.floor(r.start + 1e-9) + title, label, 'events', i), track, title };
      applyRange(o, r);
      const category = str(e.category);
      if (category) {
        if (!catIds.has(category)) warn(`${label}: 분류 "${category}"이(가) 정의되어 있지 않습니다.`, 'events', i);
        o.category = category;
      }
      let importance = Number(e.importance ?? 2);
      if (![1, 2, 3].includes(importance)) {
        if (e.importance !== '' && e.importance != null) warn(`${label}: 중요도는 1~3이어야 해서 2로 바꿨습니다.`, 'events', i);
        importance = 2;
      }
      o.importance = importance;
      /* 자리(spot — 2026-10-14 감독 "중간으로 해 주고 사건에서 위치를 조정할 수 있게"): 날짜를 정확히 모르는 점 사건(연도만 · 달까지 · 날까지 · 세기로 적음)이
         그 구간 안에서 놓일 자리 0(처음) ~ 1(끝) — 비우면 가운데(0.5). 같은 해 사건이 쌓여 점이 겹칠 때 옮깁니다. 연표의 _placeAt이 씁니다 */
      if (e.spot != null && e.spot !== '') {
        const spot = HT.readSpot(e.spot);
        if (spot === undefined) warn(`${label}: 자리(spot)는 0~1이어야 해서 뺐습니다 — 0 처음 · 0.5 가운데 · 1 끝.`, 'events', i);
        else o.spot = spot;
      }
      if (str(e.polity)) o.polity = str(e.polity);
      const views = arr(e.perspectives)
        .filter(v => v && typeof v === 'object')
        .map(v => ({ track: str(v.track), title: str(v.title), description: str(v.description), source: str(v.source) }))
        .filter(v => v.track && (v.title || v.description))
        .map(v => Object.fromEntries(Object.entries(v).filter(([, val]) => val)));
      if (views.length) o.perspectives = views;
      if (str(e.parent)) o.parent = str(e.parent);
      const withPolities = arr(e.polities).map(str).filter(Boolean);
      if (withPolities.length) o.polities = withPolities;
      const withTracks = arr(e.tracks).map(str).filter(Boolean);
      if (withTracks.length) o.tracks = withTracks;
      Object.assign(o, readUncertainty(e, label, 'events', i, r.start));
      if (str(e.date)) o.date = str(e.date);
      if (str(e.description)) o.description = str(e.description);
      if (str(e.wiki)) o.wiki = String(e.wiki);
      const tags = Array.isArray(e.tags) ? e.tags : str(e.tags).split(',');
      const cleanTags = tags.map(str).filter(Boolean);
      if (cleanTags.length) o.tags = cleanTags;
      if (str(e.source)) o.source = str(e.source);
      const related = readNames(e.figures); // 관련 인물 (이름 · id)
      if (related.length) o.figures = related;
      /* 조약 규격: 이 칸이 있으면 조약입니다 (체결 = start, 실효 = end) — 비어 있으면 보통 사건 */
      const treaty = HT.readTreaty(e.treaty, msg => warn(`${label}: ${msg}`, 'events', i));
      if (treaty) o.treaty = treaty;
      /* 형식 버전 3: 주제 꼬리표(주제 사전의 id · 이름 목록 — 렌즈가 그 주제의 사건을 진하게) · 법 규격 · 선거 규격 (조약 규격처럼 — 비어 있으면 칸이 없음) */
      const themes = HT.readThemeList(e.theme);
      if (themes.length) o.theme = themes;
      const law = HT.readLaw(e.law, msg => warn(`${label}: ${msg}`, 'events', i));
      if (law) o.law = law;
      const election = HT.readElection(e.election, msg => warn(`${label}: ${msg}`, 'events', i));
      if (election) o.election = election;
      /* 형식 버전 3: 장소(지명 사전의 이름이나 id — 사전에 없으면 그 이름으로 저절로) · 제목의 다른 이름(이름 목록) */
      if (str(e.place)) o.place = str(e.place);
      putNames(o, e.names, label, 'events', i);
      pack.events.push(o);
    });

    /* 인물: 장군 · 재상 · 학자처럼 나라를 섬긴 사람. 날짜는 생몰(birth · death) · 활동(start · end) · 섬긴 기간(service[].start/end) 가운데 하나 이상이면 됩니다
       — 시작이 선택 사항이라 시대·사건의 기간 읽기(readRange)를 쓰지 않습니다. 활동 시기를 비우면 모델이 섬긴 기간 · 생몰에서 짐작합니다(HT.buildModel).
       목록은 인물이 있는 DLC에만 생깁니다(pack.figures) — 인물을 쓰지 않는 옛 파일은 내보낸 글이 한 글자도 달라지지 않게 */
    const figures = [];
    arr(raw.figures).forEach((f, i) => {
      if (!f || typeof f !== 'object') return err(`인물 #${i + 1}: 형식이 올바르지 않습니다.`, 'figures', i);
      const name = str(f.name ?? f.title);
      const label = `인물 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, 'figures', i);
      const track = str(f.track);
      if (!checkTrack(track, label, 'figures', i)) return;
      const ongoing = f.ongoing === true || HT.isOngoingText(f.end);
      const dates = {};
      /* 활동 시기의 미정(칸의 미정과 같은 말): "미정" 글 · startUnknown(+ 숫자) · startHint → 미정 + (있으면) 배치용 연도.
         배치용 연도가 없으면 비운 것과 같은 자리(섬긴 기간 · 생몰에서 짐작 — HT.buildModel)이고, 글에는 '미정'으로 나옵니다 */
      const unk = {};
      for (const k of ['start', 'end']) {
        const d = k === 'end' && ongoing ? null : HT.readCellEdge(f, k);
        if (d && d.unknown) unk[k] = d;
      }
      for (const k of ['birth', 'death', 'start', 'end']) {
        const d = (k === 'end' && ongoing) || unk[k] ? null : dateIn(f, k);
        if (d && isNaN(d.t)) return err(`${label}: ${FIGURE_DATE_WORDS[k]} 날짜가 올바르지 않습니다.${d.error ? ` ${d.error}` : ''}`, 'figures', i);
        if (d) dates[k] = d;
      }
      const tOf = k => (dates[k] ? dates[k].t : null);
      if (tOf('birth') != null && tOf('death') != null && HT.endBound(tOf('death'), dates.death.at) < tOf('birth')) return err(`${label}: 사망이 출생보다 앞섭니다.`, 'figures', i);
      if (tOf('start') != null && tOf('end') != null && HT.endBound(tOf('end'), dates.end.at) < tOf('start')) return err(`${label}: 활동의 끝이 시작보다 앞섭니다.`, 'figures', i);
      /* 미정인 쪽의 배치용 연도가 다른 쪽과 거꾸로면 그 배치용 연도만 버립니다 (미정은 그대로 — 자리는 모델이 짐작) */
      const sHint = unk.start ? unk.start.t : tOf('start');
      const eHint = unk.end ? unk.end.t : tOf('end');
      if ((unk.start || unk.end) && sHint != null && eHint != null && HT.endBound(eHint, dates.end && dates.end.at) < sHint) {
        warn(`${label}: 활동의 ${unk.end ? '끝' : '시작'}이 미정인데 배치용 연도가 ${unk.end ? '시작보다 앞서' : '끝보다 뒤라'} 그 배치용 연도를 버렸습니다.`, 'figures', i);
        unk[unk.end ? 'end' : 'start'].t = null;
      }
      const service = readService(f.service, label, 'figures', i);
      /* 계보 전용 인물(lineageOnly — 형식 버전 3, D1 확정 설계 2-2 · 2-3): 띠의 인물 단에 놓지 않는 사람(왕위에 오르지 않은 대군 · 공주 · 후손). 날짜가 하나도 없어도 받고, 중요도를 쓰지 않습니다 */
      const lineageOnly = f.lineageOnly === true;
      if (f.lineageOnly != null && f.lineageOnly !== true && f.lineageOnly !== false && f.lineageOnly !== '') warn(`${label}: 계보 전용(lineageOnly)은 true · false로 적습니다 — "${str(f.lineageOnly)}"은(는) 무시했습니다.`, 'figures', i);
      if (!lineageOnly && !Object.keys(dates).length && !['start', 'end'].some(k => unk[k] && unk[k].t != null) && !service.some(s => s.start != null || s.end != null))
        return err(`${label}: 날짜가 하나도 없습니다. 생몰(birth · death) · 활동 시기(start · end) · 활동 기록의 기간 가운데 하나는 적어 주세요.`, 'figures', i);
      /* 자동 id의 씨앗은 트랙 + 이름(+ 생년) — 활동 시기나 섬긴 기록을 고쳐도 id(문서 · 패치가 가리키는 이름)가 바뀌지 않게.
         계보 전용 인물은 첫 부모 글도 씨앗에 넣습니다 — 생년 없는 같은 이름의 형제 · 사촌이 줄 차례에 따라 "-2" 꼬리를 바꿔 부모 참조가 흔들리지 않게 */
      const firstParent = lineageOnly ? HT.readParents(f.parents)[0] : null;
      const seedTail = lineageOnly ? `|${firstParent ? (firstParent.whoUnknown ? '미상' : HT.personRefText(firstParent.who)) : ''}` : '';
      const o = { id: takeId(f, 'f-', `${track}|${name}|${tOf('birth') != null ? Math.floor(tOf('birth') + 1e-9) : ''}${seedTail}`, label, 'figures', i), track, name };
      if (lineageOnly) o.lineageOnly = true;
      if (f.order !== '' && f.order != null) {
        const n = Number(f.order);
        if (Number.isInteger(n)) o.order = n; // 형제 순서 (작을수록 앞 — 민족의 order와 같은 뜻)
        else warn(`${label}: 형제 순서(order)는 정수로 적습니다 — "${str(f.order)}"은(는) 뺐습니다.`, 'figures', i);
      }
      const aka = readNames(f.aka).filter(n => n !== name);
      if (aka.length) o.aka = aka;
      if (str(f.role)) o.role = str(f.role);
      for (const k of ['birth', 'death', 'start', 'end']) {
        if (unk[k]) {
          if (unk[k].t != null) o[k] = unk[k].t; // 배치용 연도 (시대 · 칸의 미정과 같은 꼴: startUnknown + start 숫자)
          o[`${k}Unknown`] = true;
          continue;
        }
        if (!dates[k]) continue;
        o[k] = dates[k].t;
        if (dates[k].at) o[`${k}At`] = dates[k].at;
      }
      if (ongoing) o.ongoing = true;
      if (service.length) o.service = service;
      if (lineageOnly && service.length) warn(`${label}: 계보 전용 인물의 활동 기록은 연표에 그리지 않습니다 — 띠에 그리려면 계보 전용을 끕니다.`, 'figures', i);
      if (str(f.house)) o.house = str(f.house); // 가문의 이름 · id — 적은 그대로 두고, 가문 사전과 잇는 것은 모델(linkHouses — houseId · houseName · 가문 구성원)의 몫
      if (lineageOnly) {
        if (f.importance !== '' && f.importance != null) warn(`${label}: 계보 전용 인물은 중요도를 쓰지 않아 뺐습니다.`, 'figures', i);
      } else {
        let importance = Number(f.importance ?? 2);
        if (![1, 2, 3].includes(importance)) {
          if (f.importance !== '' && f.importance != null) warn(`${label}: 중요도는 1~3이어야 해서 2로 바꿨습니다.`, 'figures', i);
          importance = 2;
        }
        o.importance = importance;
      }
      if (str(f.description)) o.description = str(f.description);
      const tags = readNames(f.tags);
      if (tags.length) o.tags = tags;
      if (str(f.source)) o.source = str(f.source);
      if (str(f.wiki)) o.wiki = String(f.wiki);
      Object.assign(o, HT.readUncertain(f, { mode: 'figure', warn: m => warn(`${label}: ${m}`, 'figures', i), base: o })); // 다른 견해만 — 생몰 · 활동 시기 가운데 적은 쪽만 (디테일 건의 4)
      putNames(o, f.names, label, 'figures', i); // 이름 목록 (형식 버전 3 — aka는 그대로)
      putLineage(o, f, label, 'figures', i, { kin: true }); // 부모 · 배우자 (형식 버전 3)
      figures.push(o);
    });
    if (figures.length) pack.figures = figures;

    /* 단체 (형식 버전 3 — docs/구상-연표-확장-10건.md 3-7): 붕당 · 정당 · 정권(실권 집단) · 세력 · 연합. 제 줄은 없고(띠 안의 집권 단 · 실권 단 · 연합 끈은 설계 D5가 정함)
       상세 창 · 검색 · 나라 상세의 칩으로 봅니다. name · track · start 필수 — 기간은 시대 · 기관과 같은 읽기(미정 · 연대 폭 · 이설 · 세기 글도).
       집권 기간(power)은 연호와 같은 칸 목록, 있던 나라(within) · 구성 나라(members)는 "트랙:이름" · { track?, polity, start?, end? } 줄 — 트랙은 검사하지 않고 모델이 못 찾으면 경고.
       목록이 비면 파일에 적지 않습니다 (옛 파일과 1px도 다르지 않게) */
    const groups = [];
    arr(raw.groups).forEach((g, i) => {
      if (!g || typeof g !== 'object' || Array.isArray(g)) return err(`단체 #${i + 1}: 형식이 올바르지 않습니다.`, 'groups', i);
      const name = str(g.name);
      const label = `단체 #${i + 1}${name ? ` "${name}"` : ''}`;
      if (!name) return err(`${label}: 이름이 비어 있습니다.`, 'groups', i);
      const track = str(g.track);
      if (!checkTrack(track, label, 'groups', i)) return;
      const r = readRange(g, label, 'groups', i);
      if (!r) return;
      const o = { id: takeId(g, 'gr-', track + Math.floor(r.start + 1e-9) + name, label, 'groups', i), track, name };
      const type = HT.groupType(g.type);
      if (type) o.type = type;
      else if (str(g.type)) o.type = str(g.type); // 표에 없는 종류는 자유 글 그대로
      applyRange(o, r);
      const within = HT.readPolityRows(g.within, { warn: m => warn(`${label}: 있던 나라 ${m}`, 'groups', i), what: '있던 나라' });
      if (within.length) o.within = HT.compactPolityRows(within);
      const from = HT.readGroupFrom(g.from, m => warn(`${label}: ${m}`, 'groups', i)).filter(f => {
        if (f.group !== name && f.group !== o.id) return true;
        warn(`${label}: 앞선 단체에 자기 자신을 적어 뺐습니다.`, 'groups', i);
        return false;
      });
      if (from.length) o.from = from;
      const power = readCells(g.power, label, 'groups', i, '집권');
      if (power.length) o.power = power;
      const people = HT.readGroupPeople(g.people, m => warn(`${label}: ${m}`, 'groups', i)); // 구성원 — 사람 참조(인물의 이름 · 다른 이름 · id · 지도자 칸 — 풀이는 모델의 사람 잇기)
      if (people.length) o.people = people;
      const members = HT.readPolityRows(g.members, { role: true, warn: m => warn(`${label}: 구성 나라 ${m}`, 'groups', i), what: '구성 나라' });
      if (members.length) o.members = members;
      if (type === 'coalition' && members.length < 2) warn(`${label}: 연합인데 구성 나라가 ${members.length ? '하나뿐' : '없'}입니다 — 연합의 구성 나라(members)를 둘 이상 적어 주세요.`, 'groups', i);
      if (str(g.event)) o.event = str(g.event); // 맺은 사건(사건의 제목이나 id)
      putNames(o, g.names, label, 'groups', i); // 이름 목록(원어 · 옛 이름 · 약칭 — 형식 3 F1과 같은 읽기)
      Object.assign(o, readUncertainty(g, label, 'groups', i, r.start));
      if (HT.isColor(g.color)) o.color = g.color;
      if (str(g.description)) o.description = str(g.description);
      if (str(g.note)) o.note = str(g.note);
      if (str(g.wiki)) o.wiki = String(g.wiki);
      groups.push(o);
    });
    if (groups.length) pack.groups = groups;

    /* 제도 칸 (형식 버전 3 — 3-8 렌즈의 재료): 나라마다 주제마다 이어지는 칸 목록. theme(주제 사전의 id · 이름) · polity(나라) · spans 필수.
       같은 갈래(family)면 나라가 달라도 같은 색, 칸마다 from(다른 나라의 제도에서 옴 — 전파). 나라 · 주제를 찾는 것은 모델(다른 DLC · 내장 사전일 수 있음) */
    const institutions = [];
    arr(raw.institutions).forEach((x, i) => {
      if (!x || typeof x !== 'object' || Array.isArray(x)) return err(`제도 #${i + 1}: 형식이 올바르지 않습니다.`, 'institutions', i);
      const theme = Array.isArray(x.theme) ? str(x.theme[0]) : str(x.theme);
      const ref = HT.readInstPolity(x.polity, x.track);
      const label = `제도 #${i + 1}${theme || ref ? ` "${[ref && ref.polity, theme].filter(Boolean).join(' · ')}"` : ''}`;
      if (!theme) return err(`${label}: 주제(theme)가 비어 있습니다.`, 'institutions', i);
      if (!ref) return err(`${label}: 나라(polity)가 비어 있습니다.`, 'institutions', i);
      const sp = HT.readInstSpans(x.spans);
      sp.problems.concat(sp.warnings).forEach(msg => warn(`${label}: ${msg}`, 'institutions', i));
      if (!sp.list.length) return err(`${label}: 제도 칸(spans)이 하나도 없습니다.`, 'institutions', i);
      const o = { id: takeId(x, 'in-', `${ref.track || ''}|${ref.polity}|${theme}`, label, 'institutions', i), theme };
      if (ref.track) o.track = ref.track;
      o.polity = ref.polity;
      if (str(x.family)) o.family = str(x.family);
      o.spans = sp.list;
      putNames(o, x.names, label, 'institutions', i); // 이름 목록(제도의 원어 · 다른 이름 — 형식 3 F1과 같은 읽기)
      if (str(x.description)) o.description = str(x.description);
      if (str(x.wiki)) o.wiki = String(x.wiki);
      institutions.push(o);
    });
    if (institutions.length) pack.institutions = institutions;

    /* 다른 DLC의 항목을 고치는 패치 (고칠 수 있는 칸은 위의 PATCHABLE — 작업본의 패치 만들기와 함께 봅니다) */
    arr(raw.patches).forEach((p, i) => {
      if (!p || typeof p !== 'object') return err(`패치 #${i + 1}: 형식이 올바르지 않습니다.`, 'patches', i);
      const target = str(p.target);
      const label = `패치 #${i + 1}${target ? ` (${target})` : ''}`;
      if (!/^[^/]+\/[^/]+$/.test(target)) return err(`${label}: 대상은 "DLC id/항목 id" 형식이어야 합니다.`, 'patches', i);
      if (target.split('/')[0] === pack.id) warn(`${label}: 이 DLC 자신을 고치는 패치입니다. 항목을 직접 고치는 편이 좋습니다.`, 'patches', i);
      const o = { target };
      if (p.hide) o.hide = true;
      const set = {};
      /* 배치용 연도(startHint · endHint — 항목의 미정과 같은 말): 패치에서는 "미정" + 숫자(startUnknown: true + start) 꼴로 옮겨 읽습니다 (내보낼 때도 그 꼴 — 옛 프로그램도 읽음) */
      const src = Object.assign({}, p.set && typeof p.set === 'object' ? p.set : {});
      for (const k of ['start', 'end']) {
        if (!(`${k}Hint` in src)) continue;
        const h = toYear(src[`${k}Hint`]);
        delete src[`${k}Hint`];
        if (h == null) continue;
        if (!HT.isUnknownText(src[k]) && src[`${k}Unknown`] !== true) warn(`${label}: ${k}Hint(배치용 연도)는 ${k === 'start' ? '시작' : '끝'}이 "미정"일 때만 써서 무시했습니다.`, 'patches', i);
        else if (isNaN(h)) warn(`${label}: ${k}Hint(배치용 연도)를 읽을 수 없어 무시했습니다.`, 'patches', i);
        else {
          src[k] = h;
          src[`${k}Unknown`] = true;
          delete src[`${k}At`];
        }
      }
      for (const [k, v] of Object.entries(src)) {
        if (!PATCHABLE.includes(k)) {
          warn(`${label}: "${k}"은(는) 패치할 수 없어 무시했습니다.`, 'patches', i);
          continue;
        }
        set[k] = v;
      }
      for (const k of HT.DATE_KEYS) {
        if (set[k] == null || set[k] === '') {
          delete set[`${k}At`];
          continue;
        }
        if (HT.isUnknownText(set[k])) {
          if (PATCHABLE.includes(`${k}Unknown`)) set[`${k}Unknown`] = true; // "미정"을 받는 날짜 칸(시작·끝)만 — 그 밖의 칸은 값만 비웁니다
          delete set[k];
          delete set[`${k}At`];
          continue;
        }
        const d = HT.readDate(set[k], set[`${k}At`]);
        if (!d || isNaN(d.t)) {
          warn(`${label}: ${k} 연도를 읽을 수 없어 무시했습니다.${d && d.error ? ` ${d.error}` : ''}`, 'patches', i);
          delete set[k];
          delete set[`${k}At`];
        } else {
          set[k] = d.t;
          set[`${k}At`] = d.at || null; // 날짜 글이 없으면 null — 원래 항목의 날짜 글을 지웁니다
        }
      }
      /* 연대 폭 [이른, 늦은]도 날짜 글을 받습니다 (짝 칸 startRangeAt·endRangeAt는 없으면 null — 원래 항목의 글을 지움) */
      for (const k of ['startRange', 'endRange']) {
        if (set[k] == null) {
          delete set[`${k}At`];
          continue;
        }
        const atv = Array.isArray(set[`${k}At`]) ? set[`${k}At`] : [];
        const ds = Array.isArray(set[k]) && set[k].length === 2 ? set[k].map((v, j) => HT.readDate(v, atv[j])) : [];
        if (ds.length !== 2 || ds.some(d => !d || isNaN(d.t))) {
          warn(`${label}: ${k}는 [이른 연도, 늦은 연도] 형식이어야 해서 무시했습니다.`, 'patches', i);
          delete set[k];
          delete set[`${k}At`];
          continue;
        }
        const pair = ds[0].t <= ds[1].t ? ds : [ds[1], ds[0]];
        set[k] = pair.map(d => d.t);
        set[`${k}At`] = pair.some(d => d.at) ? pair.map(d => d.at || null) : null;
      }
      /* 다른 견해: 대상이 사건 · 시대인지 인물인지 파일만으로는 모르므로 가장 넓은 꼴(인물 — 출생 · 사망 · 한쪽만)로 읽고, 모델이 대상에 맞춰 거릅니다(buildModel의 패치).
         날짜 글도 여기서 풉니다 (예전에는 적힌 그대로 넘어가 "기원전 57" 같은 글이 모델에서 읽히지 않았음) */
      if (Array.isArray(set.alternatives)) {
        /* 시작 없이 끝(· 현재까지)만 적은 이설은 인물의 활동 끝으로는 쓰이지만 사건 · 시대에서는 모델이 뺍니다 — 인물을 고치는 패치로 보이지 않으면(생몰 · 역할 · 섬긴 기록이 없음) 여기서 미리 알립니다
           (파일의 사건 · 시대가 '시작이 없어 뺐습니다'라고 알리는 것과 맞춤 — 모델에는 알림 통로가 없으므로) */
        const figLike = ['birth', 'death', 'role', 'service'].some(k => k in set) || set.alternatives.some(a => a && typeof a === 'object' && (a.birth != null || a.death != null));
        if (!figLike)
          set.alternatives.forEach((a, n) => {
            if (!a || typeof a !== 'object' || Array.isArray(a) || HT.readDate(a.start, a.startAt)) return;
            if ((a.end != null && String(a.end).trim() !== '') || a.ongoing === true) warn(`${label}: 이설 #${n + 1}에 시작이 없어, 고치는 대상이 사건 · 시대면 쓰이지 않습니다(인물이면 활동 끝의 이설로 읽습니다 — 근거만 적으려면 날짜를 모두 비웁니다).`, 'patches', i);
          });
        set.alternatives = HT.readAlternatives(set.alternatives, { mode: 'figure', warn: m => warn(`${label}: ${m}`, 'patches', i) });
      }
      for (const [k, what] of [['leaders', '지도자'], ['reigns', '지도자'], ['cabinets', '내각'], ['eras', '연호']]) if (Array.isArray(set[k])) set[k] = readCells(set[k], label, 'patches', i, what);
      if (Array.isArray(set.capitals)) set.capitals = readCapitals(set.capitals, label, 'patches', i);
      if (set.service != null) set.service = readService(set.service, label, 'patches', i); // 인물의 섬긴 기록 (날짜 글 · "트랙:정권" 글도 여기서 풉니다)
      for (const k of ['aka', 'figures']) if (set[k] != null) set[k] = readNames(set[k]);
      if (set.spot != null) {
        const spot = HT.readSpot(set.spot); // 사건의 자리 — null이면 원래 항목의 자리를 지워 가운데로
        if (spot === undefined) {
          warn(`${label}: 자리(spot)는 0~1이어야 해서 무시했습니다.`, 'patches', i);
          delete set.spot;
        } else set.spot = spot;
      }
      /* 형식 버전 3: 이름 목록 · 장소 · 부모 · 배우자도 파일과 같은 읽기로 (null이면 대상의 것을 비움 — 빈 목록 []도) */
      const pw = m => warn(`${label}: ${m}`, 'patches', i);
      if (set.names != null) set.names = HT.readNames(set.names, pw);
      if (set.place != null) set.place = str(set.place) || null;
      if (set.parents != null) set.parents = HT.readParents(set.parents, pw);
      /* 계보 전용 · 형제 순서 (D1): 계보 전용은 참 · 거짓(null은 대상의 것을 지움 — 띠 인물로), 형제 순서는 정수(null은 지움) */
      if ('lineageOnly' in set && set.lineageOnly != null && typeof set.lineageOnly !== 'boolean') {
        pw(`계보 전용(lineageOnly)은 true · false로 적습니다 — "${str(set.lineageOnly)}"은(는) 무시했습니다.`);
        delete set.lineageOnly;
      }
      if ('order' in set && set.order != null && set.order !== '') {
        const n = Number(set.order);
        if (Number.isInteger(n)) set.order = n;
        else {
          pw(`형제 순서(order)는 정수로 적습니다 — "${str(set.order)}"은(는) 무시했습니다.`);
          delete set.order;
        }
      } else if (set.order === '') set.order = null;
      if (set.spouses != null) set.spouses = HT.readSpouses(set.spouses, pw);
      if ('northSouth' in set) {
        /* 남북 위치 (형식 버전 3): 수 · 비우면(null · "") 대상의 값을 지움 — 읽지 못하면 그 칸만 버림 */
        const ns = HT.readNorthSouth(set.northSouth);
        if (ns === undefined) set.northSouth = null;
        else if (Number.isFinite(ns)) set.northSouth = ns;
        else {
          pw('남북 위치(northSouth)는 수여야 해서 그 칸을 버렸습니다.');
          delete set.northSouth;
        }
      }
      /* 정권 종류 · 승계 종류도 시대와 같은 식으로 한국어를 읽어 id로 ("괴뢰국" → puppet · "부흥" → revival) — 모르는 종류는 시대와 같은 경고(모델에서는 국가) */
      if (str(set.kind)) {
        set.kind = HT.polityKindId(set.kind) || str(set.kind);
        if (!HT.ALL_KINDS.some(x => x.id === set.kind)) warn(`${label}: 정권 종류 "${set.kind}"을(를) 알 수 없어 국가로 봅니다.`, 'patches', i);
      }
      if (set.succeeds != null) set.succeeds = readSuccList(set.succeeds, label, 'patches', i);
      if (set.partOf != null) checkPartOf(set.partOf, label, 'patches', i); // 소속 관계 · 놓는 자리는 모델이 시대와 같은 규칙으로 읽습니다(HT.readPartOf)
      /* 시기 구분 · 지위 변천: 빈 목록([])은 "대상의 것을 비움"입니다. 목록이 아니거나, 적은 것이 모두 읽히지 않아 비었으면
         대상의 것을 지우지 않도록 그 칸을 정말 무시합니다 (알림과 결과가 같게) */
      for (const [k, read, what, listy] of [['phases', HT.readPhases, '시기 구분', v => typeof v === 'object'], ['ranks', HT.readRanks, '지위 변천', Array.isArray], ['faiths', HT.readFaiths, '종교 변천', Array.isArray]]) {
        if (!(k in set)) continue;
        if (set[k] == null || set[k] === '') {
          // null · 빈 글도 "목록이 아님" — 대상의 것을 지우지 않고 알립니다 (비우려면 빈 목록 [])
          warn(`${label}: ${what}은 목록이어야 해서 무시했습니다 (대상의 것은 그대로 둡니다 — 비우려면 빈 목록 []).`, 'patches', i);
          delete set[k];
          continue;
        }
        const r = read(set[k]); // 목록이 아니면 읽는 함수가 "목록이어야 해서 무시했습니다"를 알립니다
        r.problems.concat(r.warnings).forEach(msg => warn(`${label}: ${msg}`, 'patches', i));
        if (r.list.length || (Array.isArray(set[k]) && !set[k].length)) set[k] = r.list;
        else {
          if (listy(set[k])) warn(`${label}: ${what}에 읽을 수 있는 것이 없어 무시했습니다 (대상의 ${what}은 그대로 둡니다).`, 'patches', i);
          delete set[k];
        }
      }
      if ('treaty' in set) set.treaty = HT.readTreaty(set.treaty, msg => warn(`${label}: ${msg}`, 'patches', i)); // 조약 규격 (비었으면 null — 조약을 뗌)
      /* 형식 버전 3: 사건의 주제 꼬리표 · 법 · 선거 규격과 단체 · 제도의 칸 — 파일과 같은 읽기로 (규격이 비었으면 null — 그 규격을 뗌).
         주제(theme)는 사건이면 목록 · 제도면 하나라 적힌 꼴(목록 · 글)을 그대로 두고 다듬기만, 구성원(people)은 목록일 때만 — 글 하나는 시대의 민족일 수 있음 */
      if (set.theme != null) set.theme = Array.isArray(set.theme) ? HT.readThemeList(set.theme) : str(set.theme);
      if ('law' in set) set.law = HT.readLaw(set.law, msg => warn(`${label}: ${msg}`, 'patches', i));
      if ('election' in set) set.election = HT.readElection(set.election, msg => warn(`${label}: ${msg}`, 'patches', i));
      if (set.type != null) set.type = HT.groupType(set.type) || str(set.type);
      if (set.within != null) {
        const w = HT.readPolityRows(set.within, { warn: m => warn(`${label}: 있던 나라 ${m}`, 'patches', i), what: '있던 나라' });
        set.within = w.length ? HT.compactPolityRows(w) : null;
      }
      if (set.from != null) set.from = HT.readGroupFrom(set.from, m => warn(`${label}: ${m}`, 'patches', i));
      if (Array.isArray(set.power)) set.power = readCells(set.power, label, 'patches', i, '집권');
      if (set.members != null) set.members = HT.readPolityRows(set.members, { role: true, warn: m => warn(`${label}: 구성 나라 ${m}`, 'patches', i), what: '구성 나라' });
      if (Array.isArray(set.people)) set.people = HT.readGroupPeople(set.people, m => warn(`${label}: ${m}`, 'patches', i)); // 단체의 구성원 — 사람 참조 목록
      for (const k of ['family', 'event']) if (set[k] != null) set[k] = str(set[k]);
      if (set.spans != null) {
        const sp = HT.readInstSpans(set.spans);
        sp.problems.concat(sp.warnings).forEach(msg => warn(`${label}: ${msg}`, 'patches', i));
        if (sp.list.length) set.spans = sp.list;
        else {
          warn(`${label}: 제도 칸(spans)에 읽을 수 있는 칸이 없어 무시했습니다 (대상의 칸은 그대로 둡니다).`, 'patches', i);
          delete set.spans;
        }
      }
      /* 실재성: 한국어도 id로, 비우거나 실재면 null(원래 항목의 실재성을 지움) */
      if ('historicity' in set) {
        const hs = HT.historicity(set.historicity);
        if (!hs && str(set.historicity)) {
          warn(`${label}: 실재성 "${str(set.historicity)}"을(를) 알 수 없어 무시했습니다.`, 'patches', i);
          delete set.historicity;
        } else set.historicity = hs && hs !== 'attested' ? hs : null;
      }
      if (Object.keys(set).length) o.set = set;
      if (!o.hide && !o.set) return err(`${label}: 바꿀 내용이 없습니다.`, 'patches', i);
      if (str(p.note)) o.note = str(p.note);
      pack.patches.push(o);
    });

    /* 문서: { "문서 키": "본문" }. 키는 항목 id(이 DLC), "DLC id/항목 id"(남의 항목), "people:id", "track:id", "category:id", "house:id",
       "cell:항목id:cabinets:이름@시작"(지도자·내각·연호 칸), 그리고 "//"로 잇는 하위 문서("korea-p1//역사"). 자세한 것은 HT.docKey */
    if (raw.documents && typeof raw.documents === 'object' && !Array.isArray(raw.documents)) {
      for (const [k, v] of Object.entries(raw.documents)) {
        const key = str(k);
        if (!key || typeof v !== 'string' || !v.trim()) continue;
        if (!HT.docKey.valid(key)) {
          warn(`문서 "${key}": 키 형식이 올바르지 않아 무시했습니다.`, 'documents');
          continue;
        }
        pack.documents[key] = v;
      }
    }

    /* 영토(지도): { basemap, polities: [지도 전용 정권], ownership: { 조각id: [[시작, 끝, 정권, 상태?, 상대?], …] } }
     * 정권은 "트랙:이름"(연표의 시대)이나 polities 의 id 로 적습니다. 자세한 해석은 js/map.js 의 HT.resolveTerritory */
    if (raw.territory && typeof raw.territory === 'object' && !Array.isArray(raw.territory)) {
      const t = raw.territory;
      const o = { basemap: str(t.basemap) || 'east-asia-v3', polities: [], ownership: {} };
      if (typeof t.generate === 'function') o.generate = t.generate; // 내장 팩 전용 (JSON 으로는 나가지 않음)
      if (str(t.generateOver)) o.generateOver = str(t.generateOver); // 규칙을 돌릴 단위 팩 id
      if (arr(t.unitPacks).length) o.unitPacks = arr(t.unitPacks).map(str).filter(Boolean); // 함께 불러올 단위 팩
      /* DLC 안에 직접 적은 단위(원자 조각 묶음): { id, name, level, parent, start, end, cells: [조각 id], source, confidence } */
      const units = [];
      arr(t.units).forEach((u, i) => {
        const id = str(u && u.id);
        if (!id || /["'\\/]/.test(id)) return err(`단위 #${i + 1}: id가 비었거나 올바르지 않습니다.`, 'territory', i);
        const q = { id, name: str(u.name) || id, cells: arr(u.cells).map(str).filter(Boolean) };
        if (!q.cells.length) return warn(`단위 "${id}": 조각 목록이 비어 있어 무시했습니다.`, 'territory', i);
        for (const k of ['level', 'parent', 'parentName', 'source', 'confidence', 'description']) if (str(u[k])) q[k] = str(u[k]);
        for (const k of ['start', 'end']) {
          if (u[k] == null || u[k] === '') continue;
          if (k === 'end' && HT.isOngoingText(u[k])) continue;
          const y = typeof u[k] === 'number' ? u[k] : HT.parseYear(u[k]);
          if (!isNaN(y)) q[k] = y;
        }
        units.push(q);
      });
      if (units.length) o.units = units;
      /* 조각 지명 기록: { 조각id: [[시작, 끝, 이름, 상위], …] } — 같은 조각의 내장 기록을 통째로 덮어씀 */
      const names = {};
      let nNames = 0;
      Object.keys(t.names && typeof t.names === 'object' ? t.names : {}).forEach(id => {
        const list = arr(t.names[id]).map((r, i) => {
          if (!Array.isArray(r) || r.length < 3) return warn(`지명 기록 "${id}" #${i + 1}: [시작, 끝, 이름, 상위] 꼴이 아닙니다.`, 'territory'), null;
          const s = typeof r[0] === 'number' ? r[0] : HT.parseYear(r[0]), e = r[1] == null || r[1] === '' || HT.isOngoingText(r[1]) ? 9999 : typeof r[1] === 'number' ? r[1] : HT.parseYear(r[1]);
          if (isNaN(s) || isNaN(e) || !str(r[2])) return warn(`지명 기록 "${id}" #${i + 1}: 연도나 이름을 읽을 수 없습니다.`, 'territory'), null;
          return [s, e, str(r[2]), str(r[3])];
        }).filter(Boolean).sort((a, b) => a[0] - b[0]);
        if (list.length) { names[id] = list; nNames += list.length; }
      });
      if (nNames) o.names = names;
      const polIds = new Set();
      arr(t.polities).forEach((p, i) => {
        const id = str(p && p.id);
        const label = `지도 정권 #${i + 1}${p && p.name ? ` "${p.name}"` : ''}`;
        if (!id || /["'\\/]/.test(id)) return err(`${label}: id가 비었거나 올바르지 않습니다 (따옴표·역슬래시·/ 는 쓸 수 없음).`, 'territory', i);
        if (polIds.has(id)) return warn(`${label}: id "${id}"가 중복되어 뒤의 것을 무시했습니다.`, 'territory', i);
        polIds.add(id);
        const q = { id, name: str(p.name) || id };
        if (HT.isColor(p.color)) q.color = p.color;
        if (str(p.track)) q.track = str(p.track);
        if (str(p.period)) q.period = str(p.period);
        if (str(p.kind) && HT.POLITY_KINDS.some(k => k.id === str(p.kind))) q.kind = str(p.kind);
        for (const k of ['start', 'end']) {
          if (p[k] == null || p[k] === '') continue;
          if (k === 'end' && HT.isOngoingText(p[k])) continue;
          const y = typeof p[k] === 'number' ? p[k] : HT.parseYear(p[k]);
          if (isNaN(y)) warn(`${label}: ${k} 연도를 읽을 수 없어 무시했습니다.`, 'territory', i);
          else q[k] = y;
        }
        if (str(p.description)) q.description = str(p.description);
        o.polities.push(q);
      });
      const own = t.ownership && typeof t.ownership === 'object' ? t.ownership : {};
      let bad = 0, overlaps = 0;
      const yr = v => (v == null || v === '' || HT.isOngoingText(v) ? HT.CURRENT_YEAR + 1 : typeof v === 'number' ? v : HT.parseYear(v));
      for (const cellId of Object.keys(own)) {
        const list = arr(own[cellId])
          .map(r => (Array.isArray(r) ? r.slice(0, 5) : r && typeof r === 'object' ? [r.start, r.end, r.polity, r.status, r.by] : null))
          .filter(r => {
            if (!r || !str(r[2]) || isNaN(yr(r[0])) || isNaN(yr(r[1])) || yr(r[0]) >= yr(r[1])) {
              bad++;
              return false;
            }
            return true;
          })
          .map(r => [yr(r[0]), yr(r[1]), str(r[2])].concat(str(r[3]) ? [str(r[3])].concat(str(r[4]) ? [str(r[4])] : []) : []))
          .sort((a, b) => a[0] - b[0]);
        for (let i = 1; i < list.length; i++) if (list[i][0] < list[i - 1][1]) overlaps++;
        if (list.length) o.ownership[cellId] = list;
      }
      if (bad) warn(`영토: 읽을 수 없는 소유 기록 ${bad}개를 무시했습니다.`, 'territory');
      if (overlaps) warn(`영토: 같은 조각에서 기간이 겹치는 소유 기록이 ${overlaps}곳 있습니다. 뒤의 기록이 앞의 것을 덮습니다.`, 'territory');
      if (o.polities.length || Object.keys(o.ownership).length || o.generate || o.units) pack.territory = o;
    }

    if (!pack.periods.length && !pack.events.length && !pack.organs.length && !pack.cultures.length && !pack.dynasties.length && !pack.patches.length && !pack.territory && !Object.keys(pack.documents).length && !pack.epochs.length && !pack.figures && !(pack.houses && pack.houses.length) && !(pack.scopes || []).length && !pack.groups && !pack.institutions && !pack.surnames && !pack.places) // 성씨 · 지명 사전만 담은 DLC도 빈 DLC가 아님 (형식 3)
      warn('시대·사건·기관·문화·왕조·가문·인물·대범위·단체·제도·패치·문서·영토가 하나도 없습니다.');
    if ((pack.rankDefs || pack.spheres) && warnings.length && /하나도 없습니다/.test(warnings[warnings.length - 1].msg)) warnings.pop(); // 지위 사전 · 문화권 사전만 담은 DLC는 빈 DLC가 아닙니다
    if ((pack.views || pack.maps || pack.fonts || pack.themes) && warnings.length && /하나도 없습니다/.test(warnings[warnings.length - 1].msg)) warnings.pop(); // 형식 3: 모아 보기 판 · 지도 · 글꼴만 담은 DLC(지도팩 · 글꼴 팩), 주제 사전만 담은 DLC(여러 DLC가 id로 함께 쓰는 사전)도
    const fatal = errors.some(x => x.kind === 'info');
    return { pack: fatal ? null : pack, errors, warnings };
  };

  /* ---------- 문서 키 ----------
   * 모든 것에 문서를 달 수 있습니다. 키 = 바탕 키 + (하위 문서면 "//이름").
   *   바탕 키: "DLC id/항목 id"(시대·사건·기관·문화·시대 구분) · "people:민족 id" · "track:트랙 id" · "category:분류 id" · "house:가문 id"(접두어는 HT.DOC_PREFIXES)
   *            · "cell:DLC id/항목 id:leaders|cabinets|eras|capitals:이름@시작 연도"(지도자·내각·연호·도읍 칸 — 도읍의 이름은 그때 이름 또는 도시.
   *              칸 종류 글자는 HT.CELL_KINDS의 list 가운데 문서를 다는 종류)
   * DLC 파일 안에서는 자기 항목의 "DLC id/"를 생략할 수 있습니다 ("korea-p1//역사"). */
  /* 접두어가 붙는 바탕 키("people:id" …) — DLC id를 앞에 붙이지 않는 키입니다. 새 접두어는 이 목록에 한 줄 push (정규식은 목록에서 나옴) */
  HT.DOC_PREFIXES = ['people', 'track', 'category'];
  HT.DOC_PREFIXES.push('house'); // 가문: "house:가문 id"
  HT.DOC_PREFIXES.push('view', 'map'); // 형식 3: 모아 보기 판 "view:판 id" · 지도 "map:지도 id" (가문처럼 여러 DLC에 걸쳐 id 하나)
  HT.DOC_PREFIXES.push('surname', 'place'); // 성씨 · 지명 (형식 버전 3): "surname:성씨 id" · "place:지명 id"
  let prefixSrc = null;
  let prefixRe = null;
  const docPrefixRe = () => {
    const src = HT.DOC_PREFIXES.join('|');
    if (src !== prefixSrc) {
      prefixSrc = src;
      prefixRe = new RegExp(`^(${src}):(.+)$`);
    }
    return prefixRe;
  };
  /* 문서 키의 칸 종류 글자(leaders|cabinets|…)는 칸 종류 표(HT.CELL_KINDS)에서 — 문서를 다는 종류만. 표에 종류가 더해지면 정규식도 따라 바뀝니다 */
  let cellKeySrc = null;
  let cellKeyRes = null;
  const cellKeyRe = which => {
    const src = HT.CELL_KINDS.filter(k => k.doc !== false).map(k => k.list).join('|');
    if (src !== cellKeySrc) {
      cellKeySrc = src;
      cellKeyRes = { full: new RegExp(`^cell:(.+?):(${src}):(.+)@(-?\\d+)$`), head: new RegExp(`^cell:(.+?):(${src}):(.+)$`) };
    }
    return cellKeyRes[which];
  };
  HT.docKey = {
    SEP: '//',
    split: key => {
      const i = String(key).indexOf('//');
      return i < 0 ? { base: String(key), sub: '' } : { base: key.slice(0, i), sub: key.slice(i + 2) };
    },
    join: (base, sub) => (sub ? `${base}//${sub}` : base),
    cell: (uid, kind, c) => `cell:${uid}:${kind}:${c.docName || c.name}@${Math.floor(c.start + 1e-9)}`, // docName: 이름만으로는 겹칠 수 있는 칸(시기 구분 — 체계를 붙인 이름)
    /** 바탕 키를 풀어 종류를 알려 줍니다 */
    parse: key => {
      const { base, sub } = HT.docKey.split(key);
      let m;
      if ((m = base.match(docPrefixRe()))) return { type: m[1], id: m[2], base, sub };
      if ((m = base.match(cellKeyRe('full')))) return { type: 'cell', uid: m[1], cellKind: m[2], name: m[3], start: Number(m[4]), base, sub };
      return { type: 'item', uid: base, base, sub };
    },
    valid: key => {
      const { base } = HT.docKey.split(key);
      return !!base && !/\/\//.test(base) && base.length < 300;
    },
    /** DLC 안의 상대 키("korea-p1", "cell:korea-p1:…")를 "DLC id/…" 절대 키로 */
    absolute: (key, packId) => {
      const { base, sub } = HT.docKey.split(key);
      const abs = b => (b.includes('/') ? b : `${packId}/${b}`);
      let out = base;
      let m;
      if (docPrefixRe().test(base)) out = base;
      else if ((m = base.match(cellKeyRe('head')))) out = `cell:${abs(m[1])}:${m[2]}:${m[3]}`;
      else out = abs(base);
      return HT.docKey.join(out, sub);
    },
    /** 절대 키를 그 DLC 기준 상대 키로 (내보낼 때) */
    relative: (key, packId) => {
      const { base, sub } = HT.docKey.split(key);
      const rel = b => (b.startsWith(`${packId}/`) ? b.slice(packId.length + 1) : b);
      let out = base;
      let m;
      if ((m = base.match(cellKeyRe('head')))) out = `cell:${rel(m[1])}:${m[2]}:${m[3]}`;
      else if (!docPrefixRe().test(base)) out = rel(base);
      return HT.docKey.join(out, sub);
    },
  };

  /** 짝 칸 "<칸>At"의 날짜 글을 제자리(<칸>)에 넣고 짝 칸은 뺍니다 — 파일에는 "start": "음력 1592-04-13"처럼 남습니다.
      값과 맞지 않는 글(값만 고친 경우)은 버립니다 */
  HT.unfoldDates = v => {
    if (Array.isArray(v)) return v.map(HT.unfoldDates);
    if (!v || typeof v !== 'object') return v;
    const o = {};
    for (const [k, x] of Object.entries(v)) {
      if (k.length > 2 && k.endsWith('At') && Object.prototype.hasOwnProperty.call(v, k.slice(0, -2))) continue;
      if (k.length > 2 && k.endsWith('At') && (x == null || x === '')) continue;
      const at = v[`${k}At`];
      if (typeof x === 'number' && atFits(at, x)) o[k] = at;
      else if (Array.isArray(x) && Array.isArray(at) && x.every(n => typeof n === 'number')) o[k] = x.map((n, j) => (atFits(at[j], n) ? at[j] : n));
      else o[k] = HT.unfoldDates(x);
    }
    return o;
  };
  const DATED = ['epochs', 'periods', 'organs', 'cultures', 'dynasties', 'events', 'patches'];
  DATED.push('figures'); // 인물: 생몰 · 활동 · 섬긴 기간의 날짜 글도 제자리에 접어 넣습니다
  DATED.push('scopes'); // 대범위의 기간도 날짜 글을 제자리에 (빠지면 "892-05" 같은 글이 start + startAt 두 칸으로 갈라져 나감)
  DATED.push('views'); // 형식 3: 모아 보기 판의 기간 (지도는 장면의 주인 { 구역 id: … }을 건드리지 않게 따로 — 아래 foldMapDates)
  /* 형식 버전 2에서 생긴 열쇠·칸 — 기능을 더하는 단계가 여기에 적습니다 (하나도 쓰지 않은 파일은 1로 나갑니다).
     여기에 처음 적는 단계가 읽는 버전(HT.FORMAT_VERSION)도 2로 올립니다 — 목록이 비었는데 2이거나 찼는데 1이면 scripts/dev-smoke.mjs가 잡습니다.
     길 글: 'houses[]'(최상위 목록에 항목이 있으면) · 'periods[].ranks'(어느 항목이든 그 칸을 쓰면) · 'periods[].partOf[].relation'(안쪽 목록의 칸까지).
     칸이 아니라 값으로 갈리는 것(새 종류 id 같은)은 pack => 참/거짓 함수로 적습니다 */
  HT.NEW_FORMAT_KEYS = [];
  /* 종류와 소속 관계: 소속의 relation · nest 칸, 버전 2에서 생긴 종류 값(조공·책봉국 … 부흥·저항 세력), 승계 종류 '부흥' — 패치의 set과 지도 전용 정권에 적은 것도 셉니다 */
  const KINDS_V1 = ['state', 'vassal', 'federation', 'org', 'era', 'overlay', 'culture', 'dynasty'];
  const isNewKind = k => typeof k === 'string' && !KINDS_V1.includes(k) && HT.POLITY_KINDS.some(x => x.id === k);
  const hasRevival = list => Array.isArray(list) && list.some(s => s && s.type === 'revival');
  HT.NEW_FORMAT_KEYS.push('periods[].partOf[].relation', 'periods[].partOf[].nest', 'patches[].set.partOf[].relation', 'patches[].set.partOf[].nest');
  HT.NEW_FORMAT_KEYS.push(pack => (pack.periods || []).some(p => isNewKind(p.kind) || hasRevival(p.succeeds)) || (pack.patches || []).some(p => p.set && (isNewKind(p.set.kind) || hasRevival(p.set.succeeds))) || ((pack.territory || {}).polities || []).some(p => isNewKind(p.kind)));
  /* 승계 종류 '부분 승계'(정도 · 이어진 것) — 옛 앱은 모르는 종류를 간접 승계로 읽어 점선으로 보입니다(정도 · 이어진 것은 무시 — 파일은 깨지지 않음) */
  const hasPartial = list => Array.isArray(list) && list.some(s => s && s.type === 'partial');
  HT.NEW_FORMAT_KEYS.push(pack => (pack.periods || []).some(p => hasPartial(p.succeeds)) || (pack.patches || []).some(p => p && p.set && hasPartial(p.set.succeeds)));
  /* 인물: 최상위 figures 목록, 사건의 관련 인물(events[].figures), 그리고 패치가 인물의 칸 · 관련 인물을 고칠 때 */
  HT.NEW_FORMAT_KEYS.push('figures[]', 'events[].figures', 'patches[].set.figures', 'patches[].set.service', 'patches[].set.birth', 'patches[].set.death', 'patches[].set.role', 'patches[].set.aka');
  HT.NEW_FORMAT_KEYS.push('periods[].phases', 'patches[].set.phases'); // 시기 구분(학계)
  HT.NEW_FORMAT_KEYS.push('rankDefs[]', 'periods[].ranks', 'periods[].leaders[].rank', 'patches[].set.ranks', 'patches[].set.leaders[].rank', 'patches[].set.reigns[].rank'); // 지위: 사전 · 지위 변천 · 지도자의 지위
  HT.NEW_FORMAT_KEYS.push(pack => (pack.patches || []).some(p => p.set && (Array.isArray(p.set.phases) || Array.isArray(p.set.ranks)))); // 패치로 대상의 시기 구분 · 지위 변천을 비우는 빈 목록([])도 버전 2의 칸을 쓴 것
  HT.NEW_FORMAT_KEYS.push('houses[]', 'periods[].house', 'periods[].leaders[].house', 'periods[].cabinets[].house', 'patches[].set.leaders[].house', 'patches[].set.cabinets[].house'); // 가문: 가문 사전 · 국성 · 지도자/내각의 가문 (왕조의 house는 옛 칸)
  /* 가문: 패치의 옛 이름 reigns(= 지도자)의 가문 · 패치의 house(국성) — 패치에는 대상의 종류가 적히지 않아 시대(국성)인지 왕조(옛 칸)인지 파일만으로는 알 수 없으므로
     house를 고치는 패치는 모두 2로 나갑니다(왕조의 가문을 고치는 패치도 — 옛 프로그램에서는 새 형식 안내가 뜨지만 그대로 읽힘) */
  HT.NEW_FORMAT_KEYS.push('patches[].set.reigns[].house', 'patches[].set.house');
  HT.NEW_FORMAT_KEYS.push(pack => Object.keys(pack.documents || {}).some(k => /^house:/.test(HT.docKey.split(k).base))); // 가문: 가문 문서(house:id) — 옛 프로그램은 "DLC id/house:…"로 읽어 가리키는 것이 없어짐
  HT.NEW_FORMAT_KEYS.push(pack => HT.usesCellUnknown(pack)); // 칸의 미정: 칸 · 소속 기간의 시작 · 끝에 "미정"
  HT.NEW_FORMAT_KEYS.push('events[].treaty', 'patches[].set.treaty'); // 조약: 사건의 조약 규격 · 남의 사건에 조약 규격을 얹는 패치 (떼는 패치 — treaty: null — 는 아래 함수 줄이 셉니다)
  /* 버전 2에서 생긴 패치 칸을 비우는 패치(값이 null · '' · [])도 2 — 옛 앱은 그 칸을 "패치할 수 없는 칸"으로 버리므로, 그것만 든 패치는 "바꿀 내용이 없습니다"로 통째로 버려집니다
     (실재성 줄과 같은 규칙: 값과 상관없이 칸 이름만 있으면). 인물의 칸 · 사건의 관련 인물 · 시기 구분 · 지위 변천 · 조약 규격 */
  const PATCH_KEYS_V2 = ['figures', 'aka', 'role', 'service', 'birth', 'birthAt', 'death', 'deathAt', 'phases', 'ranks', 'treaty'];
  HT.NEW_FORMAT_KEYS.push(pack => (pack.patches || []).some(p => p && p.set && typeof p.set === 'object' && PATCH_KEYS_V2.some(k => k in p.set)));
  /** 칸(지도자 · 내각 · 연호 · 도읍)이나 소속 기간(partOf · 기관의 host · 왕조의 polities)의 시작 · 끝에 "미정"을 적은 DLC인지 — 짧은 꼴 ["이름", "미정", 538]과 패치의 칸도 봅니다 */
  HT.usesCellUnknown = pack => {
    const unk = e => (Array.isArray(e) ? HT.isUnknownText(e[1]) || HT.isUnknownText(e[2]) : !!e && typeof e === 'object' && (e.startUnknown === true || e.endUnknown === true || HT.isUnknownText(e.start) || HT.isUnknownText(e.end)));
    const lists = ['leaders', 'reigns', 'cabinets', 'eras', 'capitals', 'partOf', 'host', 'polities'];
    const inItem = x => !!x && typeof x === 'object' && lists.some(k => (Array.isArray(x[k]) ? x[k].some(unk) : !!x[k] && typeof x[k] === 'object' && unk(x[k])));
    return ['periods', 'organs', 'cultures', 'dynasties'].some(k => (pack[k] || []).some(inItem)) || (pack.patches || []).some(p => inItem(p && p.set));
  };
  const usesPath = (v, segs) => {
    if (!segs.length) return !(v == null || v === '' || (Array.isArray(v) && !v.length)); // false도 "적은 값"입니다
    if (!v || typeof v !== 'object') return false;
    const many = segs[0].endsWith('[]');
    const x = v[many ? segs[0].slice(0, -2) : segs[0]];
    if (!many) return usesPath(x, segs.slice(1));
    const list = Array.isArray(x) ? x : x && typeof x === 'object' ? [x] : [];
    return segs.length > 1 ? list.some(it => usesPath(it, segs.slice(1))) : list.length > 0;
  };
  const keyUsed = (pack, k) => (typeof k === 'function' ? !!k(pack) : usesPath(pack, String(k).split('.')));
  /** 형식 버전 3에서 생긴 열쇠·칸 — NEW_FORMAT_KEYS와 같은 꼴(길 글 · pack => 참/거짓). 하나라도 쓴 파일은 3으로 나갑니다(HT.packToJSON) */
  HT.NEW_FORMAT_KEYS_V3 = [];
  /** 이 DLC가 버전 3의 열쇠·칸을 하나라도 쓰는지 */
  HT.usesFormatV3 = pack => HT.NEW_FORMAT_KEYS_V3.some(k => keyUsed(pack, k));
  /** 이 DLC가 버전 2(또는 3)의 열쇠·칸을 하나라도 쓰는지 — 쓰면 파일의 formatVersion이 2(3)가 됩니다 */
  HT.usesNewFormat = pack => HT.NEW_FORMAT_KEYS.some(k => keyUsed(pack, k)) || HT.usesFormatV3(pack);
  /** 이 DLC가 쓰는 가장 높은 형식 버전 — 1(새 열쇠 없음) · 2(버전 2의 열쇠 · 칸만) · 3(버전 3의 열쇠 · 칸을 하나라도). 파일의 formatVersion이 이 값입니다 (HT.packToJSON) */
  HT.formatVersionOf = pack =>
    HT.usesFormatV3(pack) ? HT.FORMAT_VERSION_V3 : HT.NEW_FORMAT_KEYS.some(k => keyUsed(pack, k)) ? HT.FORMAT_VERSION_NEW : HT.FORMAT_VERSION_OLD;
  /* 실재성 (8-4 마): 시대의 두 칸과 패치의 set에 적은 것 — 패치는 값이 비어도(실재로 되돌리거나 근거 글을 지우는 null · '') 칸 이름만 있으면 2입니다
     (옛 앱은 그 칸을 "패치할 수 없는 칸"으로 버리므로, 그것만 든 패치는 "바꿀 내용이 없습니다"로 통째로 버려짐) */
  HT.NEW_FORMAT_KEYS.push('periods[].historicity', 'periods[].historicityNote');
  HT.NEW_FORMAT_KEYS.push(pack => (pack.patches || []).some(p => p && p.set && typeof p.set === 'object' && ('historicity' in p.set || 'historicityNote' in p.set)));
  /* 대범위 (7절): 최상위 목록에 항목이 있으면 */
  HT.NEW_FORMAT_KEYS.push('scopes[]');
  /* 묶음 5: 세기로 적은 연대("3세기 중반") · 지도자의 대수 미상 — 옛 앱은 세기 글을 연도로 읽지 못해 그 항목 · 칸을 빼고, 미상 대수를 빈 대수로 보아 번호를 매깁니다 */
  const CENT_CELL_LISTS = ['leaders', 'reigns', 'cabinets', 'eras', 'capitals', 'ranks', 'partOf', 'host', 'polities', 'service', 'alternatives'];
  const isCenturyText = v => typeof v === 'string' && /세기/.test(v);
  const usesCentury = x => {
    if (!x || typeof x !== 'object') return false;
    if (Array.isArray(x)) return x.some(v => isCenturyText(v) || usesCentury(v));
    if (['start', 'end', 'startAt', 'endAt', 'birth', 'death', 'startHint', 'endHint'].some(k => isCenturyText(x[k]))) return true;
    if (['startRange', 'endRange'].some(k => Array.isArray(x[k]) && x[k].some(isCenturyText))) return true;
    if (CENT_CELL_LISTS.some(k => usesCentury(x[k]))) return true;
    return Array.isArray(x.phases) ? x.phases.some(g => usesCentury(g && g.spans)) : usesCentury(x.phases && x.phases.spans);
  };
  const usesOrdinalUnknown = x =>
    !!x && typeof x === 'object' && ['leaders', 'reigns'].some(k => Array.isArray(x[k]) && x[k].some(c => c && typeof c === 'object' && !Array.isArray(c) && (c.ordinalUnknown === true || HT.isUnknownOrdinal(c.ordinal))));
  HT.NEW_FORMAT_KEYS.push(pack => ['periods', 'events', 'organs', 'cultures', 'dynasties', 'figures', 'epochs'].some(k => (pack[k] || []).some(usesCentury)) || (pack.patches || []).some(p => usesCentury(p && p.set)));
  HT.NEW_FORMAT_KEYS.push(pack => (pack.periods || []).some(usesOrdinalUnknown) || (pack.patches || []).some(p => usesOrdinalUnknown(p && p.set)));
  /* 이설 · 모호한 연대 (디테일 건의 4 — HT.readUncertain): 옛 앱은 칸을 아는 열쇠만 골라 읽어 이 칸들을 말없이 버리고, 시작이 없는 이설은
     "연도를 읽을 수 없어 뺐습니다"로 버리며(패치의 이설은 읽지 않고 그대로 모델에 넣어 범위가 NaN이 됨), 시대 구분의 이설은 모릅니다.
     · 칸 · 소속 줄 · 활동 기록의 alternatives · certainty · startRange · endRange — 시대 · 기관 · 문화 · 왕조 · 인물의 칸과 패치의 칸 목록
     · 시대 구분의 이설 · 시작이 없는 이설(글만 있는 견해 · 끝만 다른 이설 — 항목과 패치) */
  const UNC_FILE_KEYS = ['alternatives', 'certainty', 'startRange', 'endRange'];
  const CELL_FILE_LISTS = ['leaders', 'reigns', 'cabinets', 'eras', 'capitals', 'ranks', 'partOf', 'host', 'polities', 'service'];
  const hasUncKey = c => !!c && typeof c === 'object' && !Array.isArray(c) && UNC_FILE_KEYS.some(k => !(c[k] == null || c[k] === '' || (Array.isArray(c[k]) && !c[k].length)));
  /** 칸(지도자 · 내각 · 연호 · 도읍 · 시기 · 지위 · 소속 줄 · 활동 기록)에 확실성 · 연대 폭 · 이설을 적은 DLC인지 — 패치의 칸 목록도 봅니다 */
  HT.usesCellUncertainty = pack => {
    const cellsOf = x => {
      if (!x || typeof x !== 'object') return [];
      const out = [];
      for (const k of CELL_FILE_LISTS) {
        const v = x[k];
        if (Array.isArray(v)) out.push(...v);
        else if (v && typeof v === 'object') out.push(v);
      }
      for (const g of Array.isArray(x.phases) ? x.phases : x.phases && typeof x.phases === 'object' ? [x.phases] : []) out.push(...(g && Array.isArray(g.spans) ? g.spans : [g]));
      return out;
    };
    const inItem = x => cellsOf(x).some(hasUncKey);
    return ['periods', 'organs', 'cultures', 'dynasties', 'figures'].some(k => (pack[k] || []).some(inItem)) || (pack.patches || []).some(p => inItem(p && p.set));
  };
  const startlessAlt = list => Array.isArray(list) && list.some(a => a && typeof a === 'object' && (a.start == null || a.start === ''));
  HT.NEW_FORMAT_KEYS.push(pack => HT.usesCellUncertainty(pack), 'epochs[].alternatives');
  HT.NEW_FORMAT_KEYS.push(pack => ['periods', 'organs', 'cultures', 'dynasties', 'events'].some(k => (pack[k] || []).some(x => x && startlessAlt(x.alternatives))) || (pack.patches || []).some(p => p && p.set && startlessAlt(p.set.alternatives)));

  /* 팩 정보의 새 칸 (docs/구상-메이커-팩.md 2-2) — 적은 것이 있으면 */
  HT.NEW_FORMAT_KEYS.push('category', 'tags[]', 'summary', 'highlights[]', 'cover', 'relations[]', 'changelog[]', 'created', 'updated');
  /* 형식 3 (10건 3-6 · 3-10 · 3-9): 모아 보기 판 · 지도 · 글꼴 — 최상위 목록에 항목이 있으면, 분류 '지도팩'(옛 프로그램은 모르는 분류로 버림),
     판 · 지도의 문서("view:id" · "map:id" — 옛 프로그램은 "DLC id/view:…"로 읽어 가리키는 것이 없어짐 · 가문 문서와 같은 까닭) */
  HT.NEW_FORMAT_KEYS_V3.push('views[]', 'maps[]', 'fonts[]');
  HT.NEW_FORMAT_KEYS_V3.push(pack => pack.category === 'map');
  HT.NEW_FORMAT_KEYS_V3.push(pack => Object.keys(pack.documents || {}).some(k => /^(view|map):/.test(HT.docKey.split(k).base)));
  /* 형식 버전 3 — 단체 · 렌즈의 재료 (docs/구상-연표-확장-10건.md 3-7 · 3-8): 주제 사전 · 단체 · 제도 칸 목록, 사건의 주제 꼬리표 · 법 규격 · 선거 규격,
     그리고 그 칸들이나 단체 · 제도의 칸을 고치는(비우는 것도) 패치 — 옛 앱은 이 칸을 "패치할 수 없는 칸"으로 버려 그것만 든 패치를 통째로 버리므로.
     구성원(people)은 시대의 민족과 같은 칸 이름이라 목록으로 적은 것만 (민족은 글 하나) */
  const PATCH_KEYS_V3 = ['theme', 'law', 'election', 'type', 'within', 'from', 'power', 'members', 'event', 'family', 'spans'];
  HT.NEW_FORMAT_KEYS_V3.push('themes[]', 'groups[]', 'institutions[]', 'events[].theme', 'events[].law', 'events[].election');
  HT.NEW_FORMAT_KEYS_V3.push('tracks[].sphere'); // 문화권(리메이크 조각 ②)
  HT.NEW_FORMAT_KEYS_V3.push('spheres[]'); // 문화권 사전 — DLC가 만드는 문화권(2026-10-23 · DLC-형식.md 'spheres')
  HT.NEW_FORMAT_KEYS_V3.push(pack => (pack.patches || []).some(p => p && p.set && typeof p.set === 'object' && (PATCH_KEYS_V3.some(k => k in p.set) || Array.isArray(p.set.people))));
  DATED.push('groups', 'institutions'); // 단체의 기간 · 집권 칸 · 있던 나라의 기간, 제도 칸의 날짜 글도 제자리에
  /** 지도의 날짜 글 접기 — 구역의 기간 · 장면의 해(year + yearAt)는 제자리로, 장면의 주인({ 구역 id: … })은 손대지 않습니다(구역 id가 "…At"이어도 날짜 짝으로 보지 않게) */
  const foldMapDates = m => {
    if (!m || typeof m !== 'object' || Array.isArray(m)) return m;
    const o = Object.assign({}, m);
    if (Array.isArray(o.regions)) o.regions = HT.unfoldDates(o.regions);
    if (Array.isArray(o.frames))
      o.frames = o.frames.map(f => {
        if (!f || typeof f !== 'object' || Array.isArray(f)) return f;
        const { owners, ...rest } = f;
        const g = HT.unfoldDates(rest);
        return owners === undefined ? g : Object.assign(g, { owners });
      });
    return o;
  };
  /* 이름 · 지명 · 사람 · 계보 (F1 — 바탕 1 · 2 · 3, 3-1 · 3-2 · 3-3): 이름 목록(names — 시대 · 왕조 · 가문 · 성씨 · 인물 · 지도자 · 내각 · 연호 칸 · 지명 · 사건) ·
     성씨 사전 · 지명 사전 · 사건의 장소 · 지도자 · 내각 칸의 사람(person) · 자리 이음(accession) · 부모 · 배우자(지도자 칸 · 인물) · 성씨 · 지명 문서(surname:id · place:id).
     패치는 값과 상관없이 그 칸 이름만 있어도(비우는 null · [] 도) 3 — 옛 앱은 모르는 칸을 "패치할 수 없는 칸"으로 버리므로 */
  {
    const CELL_LISTS = ['leaders', 'reigns', 'cabinets', 'eras'];
    const CELL_KEYS = ['names', 'person', 'accession', 'parents', 'spouses'];
    const filled = v => !(v == null || v === '' || (Array.isArray(v) && !v.length));
    const cellUses = x => !!x && typeof x === 'object' && CELL_LISTS.some(k => Array.isArray(x[k]) && x[k].some(c => c && typeof c === 'object' && !Array.isArray(c) && CELL_KEYS.some(q => filled(c[q]))));
    const ITEM_KEYS = { periods: ['names'], dynasties: ['names'], houses: ['names'], figures: ['names', 'parents', 'spouses'], events: ['names', 'place'] };
    HT.NEW_FORMAT_KEYS_V3.push('surnames[]', 'places[]');
    HT.NEW_FORMAT_KEYS_V3.push(pack => Object.entries(ITEM_KEYS).some(([list, keys]) => (pack[list] || []).some(x => x && keys.some(k => filled(x[k])))));
    HT.NEW_FORMAT_KEYS_V3.push(pack => (pack.periods || []).some(cellUses) || (pack.patches || []).some(p => p && cellUses(p.set)));
    HT.NEW_FORMAT_KEYS_V3.push(pack => (pack.patches || []).some(p => p && p.set && typeof p.set === 'object' && ['names', 'place', 'parents', 'spouses'].some(k => k in p.set)));
    HT.NEW_FORMAT_KEYS_V3.push(pack => Object.keys(pack.documents || {}).some(k => /^(surname|place):/.test(HT.docKey.split(k).base)));
  }
  /* 형식 3 — 승계표 · 세계표 · 계보 전용 인물 · 파 (D1 확정 설계 2-2 · 2-5): 인물의 계보 전용 · 형제 순서, 가문의 구분 · 민족 · 꼬리표, 정권의 꼬리표,
     그리고 그 칸을 고치는(비우는 null도) 패치 — 옛 앱은 모르는 칸을 "패치할 수 없는 칸"으로 버리므로. 패치의 tags는 형식 1 칸이라 그대로(대상이 정권인지 모름) */
  HT.NEW_FORMAT_KEYS_V3.push('figures[].lineageOnly', 'figures[].order', 'houses[].track', 'houses[].people', 'houses[].tags', 'periods[].tags');
  HT.NEW_FORMAT_KEYS_V3.push(pack => (pack.patches || []).some(p => p && p.set && typeof p.set === 'object' && ('lineageOnly' in p.set || 'order' in p.set)));
  DATED.push('houses', 'surnames', 'places'); // 이름 목록의 기간(start · end)도 날짜 글을 제자리에 (가문 · 성씨 · 지명 — 옛 가문에는 날짜 칸이 없어 그대로)
  DATED.push('themes'); // 주제 사전의 이름 목록도 (형식 3 — 단체 · 렌즈와 이름 목록 잇기)
  /* 형식 버전 3 — 띠 배치의 기준점 · 간지 설정 (설계 6 결정 6 · 8 — 위 '배열 기준 · 남북 값 · 간지 설정'): 민족의 배열 기준 · 나라의 남북 위치 · 최상위 간지 설정(false도 적은 값),
     그리고 남북 위치를 고치거나 비우는 패치(값과 상관없이 칸 이름만 있어도 — 옛 앱은 모르는 칸을 버려 그것만 든 패치를 통째로 버리므로) */
  HT.NEW_FORMAT_KEYS_V3.push('peoples[].rowOrder', 'periods[].northSouth', 'yearCycle');
  HT.NEW_FORMAT_KEYS_V3.push(pack => (pack.patches || []).some(p => p && p.set && typeof p.set === 'object' && 'northSouth' in p.set));
  /* ---------- 형식 3 — 문서 그림 (10건 D3 · 16건 15번 — docs/설계-10건/4-5-메이커-블록과-묶음.md 결정 8 · 9 · 2절 6 · DLC-형식.md '문서 그림') ----------
     팩 맨 위의 그림 사전 images: [{ id, name, src, caption?, alt?, credit?, width?, height? }]. 문서 본문의 [[파일:이름]](이름 또는 id)이 이 사전에서 그림을 찾습니다 —
     그 문서 글을 적은 팩의 사전에서만(남의 팩 문서를 덮어쓴 글이면 덮어쓴 내 팩의 그림 — HT.docImageOf). 설명(caption)은 사전에 붙어 어느 문서에서나 같습니다.
     src는 표지 · 지도 그림과 같은 꼴(data:image/png · jpeg · webp;base64)이고 한도는 따로 둡니다(지도 그림 mapImage의 선례): 한 장 docImage자 · 팩의 그림 합 docImageTotal자(data URL 글자 수) ·
     설명 · 대체 글 · 출처는 docImageText자까지. 패치 대상이 아닙니다(그림 한 장이 한 몸 — 모아 보기 판 · 지도와 같은 까닭). 옛 프로그램은 열쇠를 버리고 [[파일:…]] 줄은 예전처럼 사라집니다(깨지지 않음) */
  Object.assign(HT.PACK_LIMITS, { docImage: 2000000, docImageTotal: 20000000, docImageText: 500 });
  HT.NEW_FORMAT_KEYS_V3.push('images[]');
  /** 문서 그림 사전 읽기 — id(없으면 이름에서 'img-' + 해시) · 그림(src)이 없거나 틀리거나 한도를 넘으면 오류로 그 그림만 뺍니다(합이 넘으면 뒤의 그림부터).
      width · height는 원본 그림의 픽셀 크기(적으면 화면이 그림을 받기 전에 자리를 잡음) */
  HT.readImages = (list, report) => {
    const L = HT.PACK_LIMITS;
    const out = [];
    let total = 0;
    arr(list).forEach((g, i) => {
      if (!g || typeof g !== 'object' || Array.isArray(g)) return report.err(`문서 그림 #${i + 1}: 형식이 올바르지 않습니다.`, i);
      const name = str(g.name);
      let id = str(g.id);
      const label = `문서 그림 #${i + 1}${name || id ? ` "${name || id}"` : ''}`;
      if (!id && name) id = `img-${HT.hash(name)}`;
      if (!ID_RE.test(id)) return report.err(`${label}: id가 비었거나 올바르지 않습니다.`, i);
      if (out.some(x => x.id === id)) return report.warn(`${label}: id "${id}"가 겹쳐 뒤의 것을 무시했습니다.`, i);
      const src = typeof g.src === 'string' ? g.src.trim() : '';
      if (!src) return report.err(`${label}: 그림(src)이 비어 있습니다.`, i);
      if (src.length > L.docImage) return report.err(`${label}: 그림이 너무 커서(data URL ${L.docImage}자 — 약 1.5MB 넘음) 뺐습니다.`, i);
      if (!COVER_RE.test(src)) return report.err(`${label}: 그림(src)이 png · jpeg · webp의 data URL이 아닙니다.`, i);
      if (total + src.length > L.docImageTotal) return report.err(`${label}: 문서 그림을 모두 합친 크기가 한도(data URL ${L.docImageTotal}자 — 약 15MB)를 넘어 뺐습니다.`, i);
      total += src.length;
      if (name && out.some(x => x.name === name)) report.warn(`${label}: 이름이 앞 그림과 같아 [[파일:${name}]]은 앞 그림을 가리킵니다 — 이 그림은 id(${id})로 적으세요.`, i);
      const o = { id, name: name || id, src };
      for (const [k, word] of [['caption', '설명'], ['alt', '대체 글'], ['credit', '출처']]) {
        const v = str(g[k]);
        if (!v) continue;
        if (v.length > L.docImageText) report.warn(`${label}: ${word}이(가) ${L.docImageText}자를 넘어 뒤를 잘랐습니다.`, i);
        o[k] = v.slice(0, L.docImageText);
      }
      for (const [k, word] of [['width', '폭(width)'], ['height', '높이(height)']]) {
        if (g[k] == null || g[k] === '') continue;
        const n = Number(g[k]);
        if (Number.isInteger(n) && n > 0 && n <= 20000) o[k] = n;
        else report.warn(`${label}: ${word} «${g[k]}»는 1~20000의 정수가 아니어서 뺐습니다.`, i);
      }
      out.push(o);
    });
    return out;
  };
  /** 문서 그림 찾기: 그 문서 글을 적은 팩(packId — 모델 문서 색인의 packId)의 그림 사전에서 [[파일:…]]의 이름(ref — id 또는 이름, 앞의 "파일:"은 있어도 됨)으로.
      id → 이름 → 대소문자를 가리지 않은 이름 차례. 없으면 null — 돌려주는 것: 사전의 그림 + { packId, packName, uid: "img:<팩 id>/<그림 id>" } */
  HT.docImageOf = (model, packId, ref) => {
    const box = model && model.imageMap && model.imageMap.get(packId || '');
    if (!box) return null;
    const r = str(ref).replace(/^(파일|이미지|file)\s*:\s*/i, '');
    return box.byId.get(r) || box.byName.get(r) || box.byName.get(r.toLowerCase()) || null;
  };
  /** 모델의 그림 사전(model.imageMap — 팩 id → { byId, byName, list }). buildModel의 끝에서 */
  const linkDocImages = (model, packs) => {
    model.imageMap = new Map();
    for (const pack of packs) {
      if (!pack || !Array.isArray(pack.images) || !pack.images.length) continue;
      const byId = new Map();
      const byName = new Map();
      for (const g of pack.images) {
        const o = Object.assign({}, g, { packId: pack.id, packName: pack.name, uid: `img:${pack.id}/${g.id}` });
        byId.set(g.id, o);
        for (const k of [g.name, String(g.name).toLowerCase()]) if (!byName.has(k)) byName.set(k, o);
      }
      model.imageMap.set(pack.id, { byId, byName, list: [...byId.values()] });
    }
    return model;
  };
  HT.packToJSON = pack => {
    const { builtin, overridesBuiltin, ...rest } = pack;
    const out = JSON.parse(JSON.stringify(rest));
    for (const k of DATED) if (Array.isArray(out[k])) out[k] = HT.unfoldDates(out[k]);
    if (Array.isArray(out.maps)) out.maps = out.maps.map(foldMapDates); // 형식 3 지도
    out.formatVersion = HT.formatVersionOf(out); // 옛 프로그램이 경고 없이 읽을 수 있는 파일은 계속 1 (버전 2의 열쇠만 쓴 파일은 2)
    return out;
  };

  /* ---------- 형식 4 — 이음 층(올림) · 다리(내림) (docs/설계-리메이크-객체-그릇-서고.md 3절 · 1단계 1a) ----------
     형식 4는 나라 띠(periods) · 시대 구분(epochs) · 대범위(scopes)를 객체 목록 하나(objects)로 모읍니다.
     · 종류는 type(비우면 국가). 옛 kind는 type과 섬김의 관계(partOf[].relation)로 나뉩니다
     · 그릇에 듦(자리를 끎)은 within, 섬김(관계만)은 partOf. 옛 partOf · nest가 이 둘로 갈립니다
     · 1a 밖의 칸(leaders · cabinets · groups · organs · dynasties · events · patches …)은 옛 꼴 그대로 실어 나릅니다(1b · 1c에서 바꿈)
     up(J) = 정규화된 옛 JSON(HT.packToJSON 결과) → { json: 형식 4, problems }. down(J4) = 형식 4 → 옛 JSON(normalizePack이 읽음).
     5단계(메이커) 전까지 저장은 옛 형식이고, 형식 4 파일은 읽을 때 down으로 내려 지금 화면에 그립니다.
     옛 → 4 → 옛을 돌면 project(J)와 같습니다 — project는 형식 4가 옛 뜻을 바꾸는 곳(설계 3-8 '옛 모습이 바뀌는 곳')만 미리 바꾼 옛 JSON입니다.
     검사: scripts/check-format4.mjs */
  HT.F4 = (() => {
    const VERSION = 4;
    const UNKNOWN = '미상'; // 상대를 모르는 섬김 — 옛 '종속 kind만 적고 partOf 없음'을 담는 자리(설계 3-4)
    const LEADERS = '지도자'; // 직위 줄의 이름 — 옛 leaders(첫 줄) · cabinets
    const CABINETS = '내각';
    /* 종류 열여덟(설계 3-2). kind = 내릴 때(down)의 옛 종류 — 옛 형식에 없는 종류는 가장 가까운 옛 종류로 그립니다 */
    const TYPES = [
      { id: 'era', name: '시대', group: 'container', kind: 'era' },
      { id: 'realm', name: '나라', group: 'container', kind: 'state' },
      { id: 'union', name: '동군연합', group: 'container', kind: 'state' },
      { id: 'league', name: '동맹', group: 'container', kind: 'org' },
      { id: 'state', name: '국가', group: 'ruling', kind: 'state' },
      { id: 'federation', name: '연방', group: 'ruling', kind: 'federation' },
      { id: 'principality', name: '제후국', group: 'ruling', kind: 'fief' },
      { id: 'city', name: '도시', group: 'ruling', kind: 'state' },
      { id: 'government', name: '정부', group: 'ruling', kind: 'exile' },
      { id: 'regime', name: '실권 정권', group: 'ruling', kind: 'org' },
      { id: 'dependency', name: '속령', group: 'ruling', kind: 'prefecture' },
      { id: 'warlord', name: '군벌', group: 'ruling', kind: 'warlord' },
      { id: 'organization', name: '단체', group: 'offland', kind: 'movement' },
      { id: 'faith', name: '교단', group: 'offland', kind: 'org' },
      { id: 'order', name: '기사단', group: 'offland', kind: 'org' },
      { id: 'company', name: '회사', group: 'offland', kind: 'org' },
      { id: 'office', name: '직위', group: 'offland', kind: 'org' },
      { id: 'group', name: '집단', group: 'folk', kind: 'client' },
      { id: 'person', name: '사람', group: 'person', kind: 'state' }, // 열아홉째(설계 3-11 ① · 2026-10-23) — 옛 인물(figures)이 이것. 띠로 내리지 않으므로 kind는 쓰이지 않음
    ];
    /* 그리는 자리(display) — 옛 장치의 자리를 지킵니다(2 · 4단계에서 서고의 그림 규칙으로 다시 정함).
       비우면 종류대로(시대 = 이름표 · 그릇, 나머지 = 제 줄의 띠). band = 제 줄의 띠로 그리는 시대(옛 '시대 이름' 띠) ·
       inside = 든 나라 띠 안(옛 기관 · 구역) · mark = 든 나라 띠 위의 표지(옛 단체의 집권 단 · 실권 단 · 연합 탭) */
    const DISPLAYS = ['band', 'inside', 'mark'];
    /* 정통성(status — 설계 3-5 · 3-11): 객체 · within 구간 · 칸의 세 자리에서 같은 값. 한국어 이름도 받습니다(5단계 과제 3에서 id를 정함 — 가상 팩 f4-office의 rival과 같은 꼴) */
    const STATUSES = [
      { id: 'legit', name: '정통' },
      { id: 'rival', name: '대립' },
      { id: 'joint', name: '공동' },
      { id: 'regent', name: '섭정' },
      { id: 'nominal', name: '명목' },
      { id: 'claim', name: '주장' },
    ];
    const statusId = v => {
      const s = String(v ?? '').trim();
      const hit = s ? STATUSES.find(t => t.id === s || t.name === s) : null;
      return hit ? hit.id : '';
    };
    const typeById = new Map(TYPES.map(t => [t.id, t]));
    /** 종류 id → 내릴 때의 옛 종류(모르면 국가) */
    const kindOfType = id => (typeById.get(id) || typeById.get('state')).kind;
    /** 종류 id · 한국어 이름 → 종류 id (모르면 '') */
    const typeId = v => {
      const s = String(v ?? '').trim();
      if (!s) return '';
      const hit = TYPES.find(t => t.id === s || t.name === s);
      return hit ? hit.id : '';
    };
    /* 옛 kind → type (설계 3-8 표). 여기에 없는 종속 kind는 국가 — 그 종속은 partOf의 관계로 옮겨 갑니다 */
    const KIND_TYPE = { federation: 'federation', warlord: 'warlord', exile: 'government', org: 'warlord', movement: 'organization', era: 'era', fief: 'principality', client: 'group', prefecture: 'dependency' };
    const STATE_DEPENDENT = ['tributary', 'dominion', 'vassal', 'protectorate', 'satellite', 'puppet', 'mandate', 'colony', 'occupied', 'frontier'];
    const typeOfKind = k => KIND_TYPE[k] || 'state';
    const clone = v => JSON.parse(JSON.stringify(v ?? null));
    const list = v => (Array.isArray(v) ? v : v == null || v === '' ? [] : [v]);
    const omit = (o, keys) => {
      const r = Object.assign({}, o);
      for (const k of keys) delete r[k];
      return r;
    };
    const entryOf = x => (typeof x === 'string' ? { polity: x } : Object.assign({}, x));
    /** 옛 { polity, … } 줄 → 형식 4의 { of, … } 줄 */
    const toRef = e => Object.assign({ of: e.polity }, omit(e, ['polity']));
    /** 형식 4의 { of, … } 줄 → 옛 { polity, … } 줄 */
    const toPolity = w => Object.assign({ polity: w.of }, omit(w, ['of']));
    /** 형식 4의 그릇 · 섬김 줄 하나 — 글 하나("이름")도 받습니다. of가 비면 null */
    const refOf = x => {
      const o = typeof x === 'string' ? { of: x } : x && typeof x === 'object' && !Array.isArray(x) ? Object.assign({}, x) : null;
      if (!o) return null;
      o.of = String(o.of ?? '').trim();
      return o.of ? o : null;
    };
    const noPeriod = e => e.start == null && e.end == null && !e.startUnknown && !e.endUnknown;
    /** 옛 접기 뜻 — 모델의 singleHost(buildModel)에서 상위 정권의 트랙 조건만 뺀 것(같은 파일만으로는 다른 팩에 있는 상위의 트랙을 모름) */
    const folds = (n, e) => n === 1 && noPeriod(e) && (e.nest === true || (e.nest == null && (!e.relation || e.relation === 'member')));
    /** 옛 nest를 가장 짧게 — 비운 nest의 뜻(관계 없음 · 구성국이고 상위 하나 · 기간 없음이면 접힘)과 같으면 지우고, 다르면 true · false */
    const nestFor = (n, e, folded) => {
      const implied = n === 1 && noPeriod(e) && (!e.relation || e.relation === 'member');
      return folded ? (implied ? undefined : true) : implied ? false : undefined;
    };
    const setNest = (e, v) => {
      if (v === undefined) delete e.nest;
      else e.nest = v;
      return e;
    };

    /** 옛 시대(정권) 하나 → 객체 */
    function objectOf(p) {
      const kind = p.kind || 'state';
      const o = omit(p, ['kind', 'type', 'partOf', 'leaders', 'cabinets', 'leadersFrom', 'cabinetsFrom', 'offices']);
      const own = typeId(p.type); // 적어 둔 객체 종류(5단계 과제 3 — 정규화가 지킨 칸)가 옛 종류보다 앞섭니다(사람은 인물 목록의 것이라 여기 올 수 없음)
      const type = own && own !== 'person' ? own : typeOfKind(kind);
      if (type !== 'state') o.type = type;
      if (kind === 'era') o.display = 'band'; // 옛 '시대 이름' 띠 — 형식 4의 시대는 보통 이름표 · 그릇이라, 띠로 그리던 것을 표시해 둡니다
      const fill = HT.relationOfKind(kind); // 관계를 비운 소속이 종류에서 빌리던 관계(군벌 = 명목상 · 종속 갈래 = 그 종류)
      const entries = list(p.partOf).map(entryOf);
      const within = [];
      const partOf = [];
      for (const e of entries) {
        const relation = e.relation || fill;
        const extra = omit(e, ['polity', 'relation', 'nest', 'main']);
        const main = e.main === true ? { main: true } : null; // 으뜸 그릇 — 접힌 줄이면 within에, 제 줄(기간 있는 섬김)이면 그 줄에 그대로
        if (folds(entries.length, e)) {
          if (relation) {
            within.push(Object.assign({ of: e.polity }, main));
            partOf.push(Object.assign({ of: e.polity, relation }, extra));
          } else within.push(Object.assign({ of: e.polity }, main, extra));
        } else partOf.push(Object.assign({ of: e.polity }, relation ? { relation } : null, main, extra));
      }
      if (!entries.length && STATE_DEPENDENT.includes(kind)) partOf.push({ of: UNKNOWN, relation: kind });
      if (within.length) o.within = within;
      if (partOf.length) o.partOf = partOf;
      /* 직위 줄(설계 3-5): 지도자 칸 = 첫 줄 '지도자' · 내각 칸 = '내각' */
      const offices = [];
      const slotLine = (key, cells, word) => { // 빌린 자리(leadersFrom · cabinetsFrom — 5단계 과제 4)는 복제된 칸 대신 { name, from }으로
        const b = p[key] && typeof p[key] === 'object' ? p[key] : typeof p[key] === 'string' && p[key] ? { from: p[key] } : null;
        if (b && b.from) offices.push({ name: b.name || word, from: b.from });
        else if (list(cells).length) offices.push({ name: word, cells });
      };
      slotLine('leadersFrom', p.leaders, LEADERS);
      slotLine('cabinetsFrom', p.cabinets, CABINETS);
      for (const f of list(p.offices)) if (f && typeof f === 'object' && !Array.isArray(f)) offices.push(f); // 셋째 줄부터(정규화가 지킨 꼴 그대로)
      if (offices.length) o.offices = offices;
      return o;
    }

    /** 옛 기관 하나 → 객체(구역 = 속령 · 기관 = 단체, 얹힌 나라 = within, 그리는 자리 = 나라 띠 안) */
    function organObject(g) {
      const o = Object.assign({ type: g.scale === 'zone' ? 'dependency' : 'organization', display: 'inside' }, omit(g, ['host']));
      const w = list(g.host).map(entryOf).map(toRef);
      if (w.length) o.within = w;
      return o;
    }

    /** 옛 단체 하나 → 객체(연합 = 동맹 · 정권 = 실권 정권 · 그 밖 = 단체, 옛 type은 subtype, 사람 목록은 persons, 앞선 단체는 succeeds의 how) */
    function groupObject(g) {
      const sub = g.type;
      const o = Object.assign({ type: sub === 'coalition' ? 'league' : sub === 'regime' ? 'regime' : 'organization', display: 'mark' }, omit(g, ['type', 'within', 'people', 'from']));
      if (sub) o.subtype = sub;
      const w = list(g.within).map(entryOf).map(toRef);
      if (w.length) o.within = w;
      if (g.people != null) o.persons = g.people; // 객체의 people은 민족 — 단체의 구성원(사람)은 persons로
      const from = list(g.from).map(x => (typeof x === 'string' ? { group: x } : Object.assign({}, x))).map(x => Object.assign({ from: x.group, type: 'direct' }, omit(x, ['group'])));
      if (from.length) o.succeeds = from;
      return o;
    }

    /** 객체 하나 → 옛 시대(정권). eraRef(w) = 이 within이 시대 그릇을 가리키는지(가리키면 소속이 아니라 대범위 구성원) */
    function periodOf(o, eraRef, warn) {
      let kind = o.display === 'band' ? 'era' : (typeById.get(o.type) || typeById.get('state')).kind;
      const p = omit(o, ['type', 'display', 'subtype', 'within', 'partOf', 'offices']);
      const rest = list(o.partOf).map(refOf).filter(Boolean);
      const rows = [];
      for (const w of list(o.within).map(refOf).filter(Boolean)) {
        if (eraRef(w)) continue;
        const i = rest.findIndex(x => x.of === w.of && noPeriod(x));
        const pe = i >= 0 ? rest.splice(i, 1)[0] : null;
        rows.push({ e: Object.assign({ polity: w.of }, omit(w, ['of']), pe ? omit(pe, ['of']) : null), folded: true });
      }
      for (const x of rest) {
        if (x.as != null) { // 어느 자격으로 섬겼나(as) — 두지 않기로 함(설계 3-11 ④ · 감독 2026-10-23): 영지를 객체로 세우고 person으로 꿴다
          warn(`객체 "${o.name || o.id || '?'}"의 섬김 "${x.of}"에 적은 as("${x.as}")는 형식 4에 없는 칸이라 뺍니다 — 그 자격의 영지를 객체로 세우고 지도자 칸의 person으로 이으세요.`);
          delete x.as;
        }
        const rel = HT.relationId(x.relation) || x.relation;
        if (x.of === UNKNOWN && o.type === 'state' && STATE_DEPENDENT.includes(rel)) {
          kind = rel;
          continue;
        }
        rows.push({ e: Object.assign({ polity: x.of }, omit(x, ['of'])), folded: false });
      }
      const n = rows.length;
      /* 지금 화면은 상위 하나 · 기간 없음일 때만 접습니다 — 기간 있는 · 여럿인 within은 알리고 소속(제 줄)으로(그릇의 배치는 2단계) */
      for (const r of rows) if (r.folded && (n > 1 || !noPeriod(r.e))) warn(`객체 "${o.name || o.id || '?'}"의 그릇 "${r.e.polity}"은(는) ${n > 1 ? '그릇 · 섬김이 여럿이라' : '기간이 있어'} 지금 화면에서는 접지 않고 소속(제 줄)으로 그립니다(그릇의 배치는 2단계).`);
      const out = rows.map(({ e, folded }) => {
        const rel = HT.relationId(e.relation) || e.relation;
        if (rel) e.relation = rel;
        else delete e.relation;
        return setNest(e, nestFor(n, e, folded && n === 1 && noPeriod(e)));
      });
      if (out.length) p.partOf = HT.compactPartOf(out);
      if (kind !== 'state') p.kind = kind;
      const type = o.type || 'state';
      if (type !== 'state' && typeOfKind(kind) !== type) p.type = type; // 옛 종류로 되살릴 수 없는 종류는 적어 둡니다(5단계 과제 3 — 정규화 · 메이커가 지킴)
      /* 직위 줄 → 지도자 · 내각 칸(두 자리) + 셋째 줄부터는 offices(5단계 과제 4 — 정규화 · 메이커가 지킴) */
      const offs = list(o.offices).filter(f => f && typeof f === 'object' && !Array.isArray(f));
      const lead = offs.find(f => f.name === LEADERS) || offs.find(f => !f.name) || offs.find(f => f.name !== CABINETS);
      const cab = offs.find(f => f !== lead && f.name === CABINETS) || offs.find(f => f !== lead);
      const borrow = (f, word) => { // 빌린 줄(from) → 옛 자리의 빌림 { name?, from } (5단계 과제 4 — 칸은 위에서 복제됨)
        if (f.from == null || f.from === '') return null;
        const b = {};
        if (f.name && f.name !== word) b.name = f.name;
        b.from = f.from;
        return b;
      };
      if (lead) {
        if (list(lead.cells).length) p.leaders = list(lead.cells);
        const b = borrow(lead, LEADERS);
        if (b) p.leadersFrom = b;
      }
      if (cab) {
        if (list(cab.cells).length) p.cabinets = list(cab.cells);
        const b = borrow(cab, CABINETS);
        if (b) p.cabinetsFrom = b;
      }
      const more = offs.filter(f => f !== lead && f !== cab).map(f => (f.from != null && f.from !== '' ? omit(f, ['cells']) : f)); // 셋째 줄부터 — 정규화가 지키는 offices로(빌린 줄은 복제한 칸을 뺌)
      if (more.length) p.offices = more;
      return p;
    }

    /* 옮겨 앉기(리메이크 2부 · 설계 3-3 · 결정 #3 A — 내보내기만: HT.F4.split): 기간 있는 within이 둘 이상이고 모두 시대 그릇이며
       경계가 정해져(앞의 end · 뒤의 start 가운데 하나 이상 · 둘이면 같은 해) 겹치지 않고 섬김(partOf)이 없으면, 객체를 경계 해마다 **토막**으로 나눕니다 —
       첫 토막은 원 id, 뒤 토막은 '<원 id>.mv<경계 해>'(id 규칙 HT.ID_RE 안 — 원 id가 없거나 규칙 밖이면 정규화가 새 id를 지어 짝이 끊긴다). 토막마다 그 그릇 하나에 기간 없이 듦(지금 대범위 구성원 · 폴더에 그대로 앉음),
       지도자 · 내각 칸은 기간으로 나눠 담고(경계를 걸치면 양쪽으로 잘라), 그 객체를 가리킨 사건은 해가 든 토막으로, 그 객체를 앞선 나라로 적은 승계는 마지막 토막으로 돌립니다.
       토막 사이는 내보내기(export/links.mjs 구역 52)가 실로 잇습니다. 그 밖(미정 경계 · 겹침 · 나라 그릇)은 지금처럼 periodOf가 알리고 소속(제 줄)으로 */
    function splitMoves(objects, eraRef, src) {
      const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);
      const clip = (cells, from, to) => list(cells).map(c => {
        const arr = Array.isArray(c);
        const a = num(arr ? c[1] : c && c.start), b = num(arr ? c[2] : c && c.end);
        if (a == null) return c;
        const e = b == null ? a : b;
        if ((from != null && e <= from) || (to != null && a >= to)) return null;
        const na = from != null && a < from ? from : a, nb = b != null && to != null && b > to ? to : b;
        if (arr) {
          const r = c.slice();
          r[1] = na;
          if (b != null) r[2] = nb;
          return r;
        }
        return Object.assign({}, c, { start: na }, b != null ? { end: nb } : null);
      }).filter(c => c != null);
      const out = [];
      const pieces = new Map(); // 원 객체의 열쇠(id · 이름) → 토막들
      for (const o of objects) {
        const ws = list(o.within).map(refOf).filter(Boolean);
        if (ws.length < 2 || !ws.every(eraRef) || list(o.partOf).length) {
          out.push(o);
          continue;
        }
        const segs = ws.map(w => ({ of: w.of, a: num(w.start), b: num(w.end) })).sort((x, y) => (x.a ?? -Infinity) - (y.a ?? -Infinity));
        const cuts = [];
        for (let i = 1; i < segs.length; i++) {
          const prev = segs[i - 1], cur = segs[i];
          const cut = cur.a ?? prev.b;
          if (cut == null || (prev.b != null && cur.a != null && prev.b !== cur.a) || (cuts.length && cut <= cuts[cuts.length - 1])) {
            cuts.length = 0;
            break;
          }
          cuts.push(cut);
        }
        const os = num(o.start), oe = num(o.end);
        if (cuts.length !== segs.length - 1 || (os != null && cuts[0] <= os) || (oe != null && cuts[cuts.length - 1] >= oe)) {
          out.push(o);
          continue;
        }
        const base = o.id != null && o.id !== '' ? String(o.id) : String(o.name || '');
        const made = segs.map((sg, i) => {
          const q = Object.assign({}, o, { within: [{ of: sg.of }] });
          const from = i === 0 ? null : cuts[i - 1], to = i === segs.length - 1 ? null : cuts[i];
          if (from != null) {
            q.id = `${base}.mv${from}`;
            q.start = from;
            for (const k of ['startUnknown', 'startRange', 'startAt', 'succeeds']) delete q[k];
          }
          if (to != null) {
            q.end = to;
            for (const k of ['endUnknown', 'endRange', 'endAt', 'ongoing']) delete q[k];
          }
          if (o.offices) q.offices = list(o.offices).map(f => (f && typeof f === 'object' && !Array.isArray(f) ? Object.assign({}, f, { cells: clip(f.cells, from, to) }) : f));
          q._from = from;
          q._to = to;
          return q;
        });
        for (const k of [o.id, o.name]) if (k != null && k !== '') pieces.set(String(k), made);
        out.push(...made);
      }
      if (!pieces.size) return;
      objects.splice(0, objects.length, ...out);
      const pieceAt = (made, y) => made.find(q => (q._from == null || y >= q._from) && (q._to == null || y < q._to)) || made[0];
      const idOf = q => (q.id != null && q.id !== '' ? q.id : q.name);
      for (const e of list(src.events)) {
        const made = e && e.polity != null ? pieces.get(String(e.polity)) : null;
        if (made && num(e.start) != null) e.polity = idOf(pieceAt(made, e.start));
      }
      for (const q of objects) {
        for (const r of list(q.succeeds)) {
          const made = r && r.from != null ? pieces.get(String(r.from)) : null;
          if (made && !made.includes(q)) r.from = idOf(made[made.length - 1]);
        }
      }
      for (const q of objects) {
        delete q._from;
        delete q._to;
      }
    }

    /** 객체 → 옛 기관 */
    function organOf(o) {
      const g = omit(o, ['type', 'display', 'subtype', 'within', 'partOf', 'offices']);
      if (!g.scale && o.type === 'dependency') g.scale = 'zone'; // 기관(agency)은 기본값이라 옛 정규화도 적지 않음
      const host = list(o.within).map(refOf).filter(Boolean).map(toPolity);
      if (host.length) g.host = HT.compactPartOf(host);
      return g;
    }

    /** 객체 → 옛 단체 */
    function groupOf(o) {
      const g = omit(o, ['type', 'display', 'subtype', 'within', 'partOf', 'offices', 'persons', 'people', 'succeeds']);
      const sub = o.subtype || (o.type === 'league' ? 'coalition' : o.type === 'regime' ? 'regime' : '');
      if (sub) g.type = sub;
      const w = list(o.within).map(refOf).filter(Boolean).map(toPolity);
      if (w.length) g.within = HT.compactPartOf(w);
      if (o.persons != null) g.people = o.persons;
      const from = list(o.succeeds).filter(s => s && typeof s === 'object' && !Array.isArray(s)).map(s => Object.assign({ group: s.from }, omit(s, ['from', 'type'])));
      if (from.length) g.from = from;
      return g;
    }

    function up(J) {
      const src = clone(J) || {};
      const problems = [];
      const objects = (src.periods || []).map(objectOf);
      const fromPeriods = objects.slice(); // 대범위 구성원은 옛 시대(정권)에서만 — buildModel의 polityIn과 같은 뜻(같은 파일 안)
      for (const e of src.epochs || []) {
        const o = Object.assign({ type: 'era' }, omit(e, ['within']));
        if (e.within) o.within = [{ of: e.within }]; // 그릇 안 이름표 시대
        objects.push(o);
      }
      for (const s of src.scopes || []) {
        const o = Object.assign({ type: 'era' }, omit(s, ['members', 'epoch', 'within']));
        if (s.epoch) o.within = [{ of: s.epoch }]; // 같은 뜻의 시대 구분 — 시대가 시대에 듦(끌지 않음)
        if (s.within) (o.within || (o.within = [])).push({ of: s.within }); // 부모 그릇(포개짐)
        const outside = [];
        for (const r of HT.readScopeRefs(s.members)) {
          const t = r.track || s.track;
          const m = fromPeriods.find(q => q.track === t && (q.name === r.polity || q.id === r.polity));
          if (!m) {
            outside.push(HT.compactScopeRef(r)); // 이 파일 밖의 정권 — 그릇이 목록으로 들고 있음(1c에서 DLC id/객체 id로)
            continue;
          }
          const w = m.within || (m.within = []);
          if (!w.some(x => x.of === s.id)) w.push({ of: s.id });
        }
        if (outside.length) o.members = outside;
        objects.push(o);
      }
      for (const g of src.organs || []) objects.push(organObject(g));
      for (const g of src.groups || []) objects.push(groupObject(g));
      for (const fg of src.figures || []) if (fg && typeof fg === 'object' && !Array.isArray(fg)) objects.push(Object.assign({ type: 'person' }, fg)); // 인물 → 사람 객체(설계 3-11 ①) — 칸은 그대로(생몰 birth · death · 활동 start · end · 활동 기록 service …)
      const seen = new Set();
      for (const o of objects) {
        if (o.id == null || o.id === '') continue;
        if (seen.has(o.id)) problems.push(`id "${o.id}"을(를) 두 항목이 씁니다 — 형식 4는 객체 id를 한 목록에서 셉니다.`);
        seen.add(o.id);
      }
      const json = omit(src, ['periods', 'epochs', 'scopes', 'organs', 'groups', 'figures']);
      json.formatVersion = VERSION;
      json.objects = objects;
      return { json, problems };
    }

    function down(J4, warn = () => {}) {
      const src = clone(J4) || {};
      for (const k of ['periods', 'epochs', 'scopes', 'organs', 'groups', 'figures']) if (src[k] != null) warn(`형식 4 파일의 "${k}"는 읽지 않습니다 — 항목은 objects에 적습니다.`);
      let objects = list(src.objects).filter(o => o && typeof o === 'object' && !Array.isArray(o)).map(o => Object.assign({}, o));
      for (const o of objects) {
        const t = o.type == null || o.type === '' ? 'state' : typeId(o.type);
        if (!t) warn(`객체 "${o.name || o.id || '?'}"의 종류 "${o.type}"을(를) 알 수 없어 국가로 읽습니다.`);
        o.type = t || 'state';
        if (o.display != null && !DISPLAYS.includes(o.display)) {
          warn(`객체 "${o.name || o.id || '?'}"의 그리는 자리 "${o.display}"을(를) 알 수 없어 종류대로 그립니다.`);
          delete o.display;
        }
      }
      /* 사람 객체(설계 3-11 ①) → 옛 인물(figures) — 칸은 그대로. 사람은 그릇에 들지 않고 섬기지 않으며 직위 줄 · 실권을 갖지 않습니다(그 자리는 지도자 칸의 person이 말함) */
      const figures = [];
      objects = objects.filter(o => {
        if (o.type !== 'person') return true;
        for (const k of ['offices', 'power', 'within', 'partOf']) {
          if (o[k] == null) continue;
          warn(`사람 "${o.name || o.id || '?'}"의 ${k === 'offices' ? '직위 줄' : k === 'power' ? '실권' : k === 'within' ? '든 그릇' : '섬김'}은(는) 사람 객체에 적지 않아 뺍니다(칭호는 지도자 칸의 person으로).`);
          delete o[k];
        }
        figures.push(omit(o, ['type']));
        return false;
      });
      /* 트랙을 비운 객체는 within 사슬을 따라 그릇의 트랙을 물려받습니다(설계 3-7) */
      const byKey = new Map();
      for (const o of objects) for (const k of [o.id, o.name]) if (k != null && k !== '' && !byKey.has(String(k))) byKey.set(String(k), o);
      const cycled = new Set(); // 그릇(within)이 고리를 이룬 객체 — 한 번만 알림(5단계 과제 1 검사 규칙)
      const trackOf = (o, path = []) => {
        if (o.track) return String(o.track);
        if (path.includes(o)) {
          if (!cycled.has(o)) {
            cycled.add(o);
            warn(`객체 "${o.name || o.id || '?'}"의 그릇(within)이 고리를 이룹니다 — 트랙을 물려받지 못합니다.`);
          }
          return '';
        }
        const next = path.concat([o]);
        for (const w of list(o.within).map(refOf).filter(Boolean)) {
          const t = byKey.has(w.of) ? trackOf(byKey.get(w.of), next) : '';
          if (t) return t;
        }
        return '';
      };
      for (const o of objects) {
        if (o.track) continue;
        const t = trackOf(o);
        if (t) o.track = t;
      }
      /* 직위 줄 빌려 보기(offices[].from — 설계 3-11 ③ · 형식 문서 '형식 4 더하기'): "객체 id" 또는 "객체 id/직위 이름" → 그 객체의 직위 줄 칸을 복제해 옛 꼴로 내립니다(지금 화면은 두 곳에 보임 · 서고 그림은 5단계 과제 9).
         from과 cells를 함께 적으면 from만 씁니다. 빌려 올 객체 · 직위 줄이 없거나 빌림이 고리를 이루면 알리고 그 줄을 뺍니다. 찾기는 고치기 전의 직위 줄(orig)에서 — 객체 차례에 기대지 않게 */
      const orig = new Map(objects.map(o => [o, list(o.offices)]));
      const officeFrom = (o, f, seen) => {
        const ref = String(f.from ?? '').trim();
        const cut = ref.indexOf('/');
        const key = cut >= 0 ? ref.slice(0, cut).trim() : ref;
        const want = cut >= 0 ? ref.slice(cut + 1).trim() : '';
        const label = `객체 "${o.name || o.id || '?'}"의 직위 줄 "${f.name || want || '?'}"`;
        const from = byKey.get(key);
        if (!from) {
          warn(`${label}이(가) 빌려 올 객체 "${key}"을(를) 찾지 못해 뺍니다.`);
          return null;
        }
        const offs = (orig.get(from) || []).filter(x => x && typeof x === 'object' && !Array.isArray(x));
        const hit = want ? offs.find(x => x.name === want) : offs.find(x => x.name === LEADERS) || offs[0];
        if (!hit) {
          warn(`${label}이(가) 빌려 올 직위 줄 "${want || LEADERS}"을(를) 객체 "${key}"에서 찾지 못해 뺍니다.`);
          return null;
        }
        if (hit.from != null && hit.from !== '') {
          if (seen.has(hit)) {
            warn(`${label}의 빌림이 고리를 이룹니다 — 뺍니다.`);
            return null;
          }
          seen.add(hit);
          return officeFrom(from, hit, seen);
        }
        return list(hit.cells);
      };
      for (const o of objects) {
        if (!Array.isArray(o.offices)) continue;
        o.offices = o.offices.map(f => {
          if (!f || typeof f !== 'object' || Array.isArray(f) || f.from == null || f.from === '') return f;
          if (list(f.cells).length) warn(`객체 "${o.name || o.id || '?'}"의 직위 줄 "${f.name || '?'}"에 from과 cells가 함께 적혀 있어 from만 씁니다.`);
          const cells = officeFrom(o, f, new Set([f]));
          return cells ? Object.assign(omit(f, ['cells']), { cells: clone(cells) }) : null; // from은 둡니다 — periodOf가 자리의 빌림(leadersFrom …)으로 내림(5단계 과제 4)
        }).filter(Boolean);
      }
      const isEra = o => o.type === 'era' && o.display !== 'band';
      const isMark = o => o.display === 'mark';
      const isInside = o => o.display === 'inside';
      /* 시대 그릇을 가리키는 within — id나 이름. 이름은 같은 이름 · id의 다른 객체가 없을 때만(옛 찾기처럼 id가 앞섬) */
      const eraOf = new Map();
      for (const o of objects) if (isEra(o) && o.id != null && o.id !== '') eraOf.set(String(o.id), o);
      for (const o of objects) {
        if (!isEra(o) || o.name == null || o.name === '' || eraOf.has(String(o.name))) continue;
        if (!objects.some(q => q !== o && !isEra(q) && (q.name === o.name || q.id === o.name))) eraOf.set(String(o.name), o);
      }
      const eraRef = w => eraOf.has(w.of);
      if (HT.F4 && HT.F4.split) splitMoves(objects, eraRef, src); // 옮겨 앉기의 토막(내보내기만 — 위 splitMoves)
      /* 시대 그릇의 구성원 — 시대를 within으로 가리킨 객체(객체 차례대로 · 옛 단체 · 기관은 대범위에 들 수 없음) */
      const members = new Map();
      for (const o of objects) {
        if (isEra(o) || isMark(o) || isInside(o)) continue;
        for (const w of list(o.within).map(refOf).filter(Boolean)) {
          if (!eraRef(w)) continue;
          const era = eraOf.get(w.of);
          const got = members.get(era) || [];
          if (!got.includes(o)) got.push(o);
          members.set(era, got);
        }
      }
      /* 포개짐(리메이크 2부 · 설계 3-3): 트랙이 있고 구성원이 있는 시대 = 그릇(대범위). 시대의 within이 그릇을 가리키면 '그릇 안의 그릇'(scopes[].within)
         또는 '그릇 안 이름표 시대'(구성원 없음 — epochs[].within), 그릇이 아닌 시대를 가리키면 지금처럼 같은 뜻의 시대 구분(scopes[].epoch) */
      const isScopeEra = o => isEra(o) && !!o.track && ((members.get(o) || []).length > 0 || list(o.members).length > 0);
      const parentOf = o => {
        const ep = list(o.within).map(refOf).filter(Boolean)[0];
        const parent = ep && eraOf.get(ep.of);
        return parent && parent !== o && isScopeEra(parent) && parent.track === o.track ? ep.of : null;
      };
      const periods = [];
      const epochs = [];
      const scopes = [];
      const organs = [];
      const groups = [];
      for (const o of objects) {
        if (isInside(o)) {
          organs.push(organOf(o));
          continue;
        }
        if (isMark(o)) {
          groups.push(groupOf(o));
          continue;
        }
        if (!isEra(o)) {
          periods.push(periodOf(o, eraRef, warn));
          continue;
        }
        const own = members.get(o) || [];
        const outside = list(o.members);
        const base = omit(o, ['type', 'display', 'subtype', 'within', 'members', 'partOf', 'offices']);
        /* 트랙이 있고 구성원이 있는 시대 = 대범위(그릇). 트랙을 비운 공통 시대는 가리키는 이가 있어도 끌지 않습니다 — 시대 구분(이름표)으로(설계 3-3) */
        if (o.track && (own.length || outside.length)) {
          const s = omit(base, ['alternatives']);
          const ep = list(o.within).map(refOf).filter(Boolean)[0];
          const parent = parentOf(o);
          if (parent) s.within = parent; // 그릇 안의 그릇
          else if (ep) s.epoch = ep.of;
          s.members = own.map(m => HT.compactScopeRef(m.track !== o.track ? { track: m.track, polity: m.id || m.name } : { polity: m.id || m.name })).concat(outside);
          scopes.push(s);
        } else {
          if (own.length) warn(`시대 "${o.name || o.id}"는 트랙이 없어(공통 시대) 구성원을 모으지 않고 시대 구분으로 읽습니다.`);
          const e = omit(base, ['label', 'default', 'host']);
          const parent = parentOf(o);
          if (parent) e.within = parent; // 그릇 안 이름표 시대(그 그릇 윗변의 둘째 탭)
          epochs.push(e);
        }
      }
      const json = omit(src, ['objects', 'periods', 'epochs', 'scopes', 'organs', 'groups', 'figures']);
      json.formatVersion = HT.FORMAT_VERSION; // 지금 읽는 옛 형식으로 — 저장은 5단계 과제 2부터 형식 4
      json.periods = periods;
      json.epochs = epochs;
      if (scopes.length) json.scopes = scopes;
      if (organs.length) json.organs = organs;
      if (groups.length) json.groups = groups;
      if (figures.length) json.figures = figures;
      /* 문화권별 주기 줄(yearCycles — 설계 3-11 ⑤): 지금 날짜 칸의 간지 줄은 하나뿐 — 최상위 yearCycle이 없으면 전체 줄(sphere 없음)을 yearCycle로 내립니다.
         문화권 줄은 고르지 않습니다(6단계 결정 16 — 기본팩의 동아시아 간지 줄이 다른 DLC의 날짜 칸을 덮지 않게) · 전체 줄이 내장 육십갑자(예약 값 · 표지 builtin)면 yearCycle을 비운 것과 같아 두지 않습니다.
         yearCycles · 시대 구분의 sphere · 객체의 importance · 칸의 status는 그대로 실어 둡니다(옛 읽기기는 모르는 칸을 버림 — 서고 그림은 과제 9 · 새 앱은 3 · 4단계 잔여) */
      if (json.yearCycle == null && Array.isArray(json.yearCycles)) {
        const cs = json.yearCycles.filter(c => c && typeof c === 'object' && !Array.isArray(c));
        const pick = cs.find(c => c.sphere == null || c.sphere === '');
        if (pick && !HT.isSexagenaryRow(pick)) {
          json.yearCycle = omit(pick, ['sphere', 'era', 'from', 'step', 'builtin']);
          warn(`문화권별 주기 줄 ${cs.length}개 가운데 "${pick.label || pick.era || '?'}"만 날짜 칸의 간지 줄로 읽습니다(문화권마다의 줄은 아직).`);
        }
      }
      return json;
    }

    /* ---------- 5단계 과제 2 — 형식 4로 저장(docs/계획-리메이크-5단계.md 정한 것 #1 · #2 · #5) ----------
       메이커는 과제 3까지 옛 꼴(periods …)로 작업본을 두므로, 형식 4 파일을 열면 다리(down)와 정규화가 잃는 칸 — 직위 줄 빌림(from) · 객체의 중요도(importance) ·
       정통성(status) … — 을 extrasOf가 객체 id마다 모아 두고(작업본의 f4extras), 저장할 때 toFile이 옛 꼴을 올린(up) 위에
       applyExtras로 되돌립니다. 되돌리는 것은 저장할 객체에 **없는 칸**뿐(메이커에서 고친 칸을 덮지 않게) · 빌린 직위 줄은 내려올 때 복제된 칸 대신 { name, from }으로.
       과제 3 · 4 · 6을 지나며 종류 · 정통성 · 중요도 · 으뜸 · 직위 줄 · 빌림 · 실권 · 시대 구분의 문화권(sphere) · 문화권별 주기(yearCycles)는 정규화가 지키게 되어 더는 잃은 칸이 아닙니다 */
    const keyOfObj = o => (o && typeof o === 'object' ? (o.id != null && o.id !== '' ? String(o.id) : o.name != null ? String(o.name) : '') : '');
    /** 형식 4 원본을 메이커의 저장 길(내림 → 정규화 → JSON → 올림)로 한 바퀴 돌린 것 — extrasOf가 "무엇을 잃나"를 알아내는 기준 */
    function resaved(raw4) {
      const r = HT.normalizePack(down(raw4));
      return r.pack ? up(HT.packToJSON(r.pack)).json : null;
    }
    function extrasOf(raw4) {
      const ex = { top: {}, objects: {}, offices: {} };
      if (!raw4 || typeof raw4 !== 'object' || Array.isArray(raw4)) return ex;
      // 문화권별 주기(yearCycles) · 시대 구분의 문화권(sphere)은 5단계 과제 6부터 정규화가 지키므로(「주기」 표 · 시대 구분 폼) 더 모으지 않습니다 — resaved가 지나므로 아래의 잃은 칸에도 들지 않음
      const again = resaved(raw4);
      const back = new Map();
      for (const o of list(again && again.objects)) if (o && typeof o === 'object') back.set(keyOfObj(o), o);
      for (const o of list(raw4.objects)) {
        if (!o || typeof o !== 'object' || Array.isArray(o)) continue;
        const k = keyOfObj(o);
        if (!k) continue;
        const re = back.get(k) || {};
        const lost = {};
        for (const key of Object.keys(o)) if (key !== 'offices' && !(key in re)) lost[key] = clone(o[key]);
        if (Object.keys(lost).length) ex.objects[k] = lost;
      }
      return ex; // offices는 비워 둡니다 — 빌림(from)은 5단계 과제 4부터 작업본(leadersFrom · cabinetsFrom · offices[].from)이 지킴
    }
    /** 저장할 형식 4(up의 결과)에 extras를 되돌림 — 없는 칸만 · 빌린 직위 줄은 복제된 칸이 든 옛 자리(지도자 · 내각) 줄을 { name, from }으로 */
    function applyExtras(json4, ex) {
      if (!ex || typeof ex !== 'object') return json4;
      for (const [k, v] of Object.entries(ex.top || {})) if (k !== 'yearCycles' && !(k in json4)) json4[k] = clone(v); // yearCycles는 5단계 과제 6부터 작업본이 지킴(옛 저장본의 f4extras에 남은 것은 되돌리지 않음 — 표에서 지운 줄이 되살아나지 않게)
      for (const o of list(json4.objects)) {
        if (!o || typeof o !== 'object') continue;
        const k = keyOfObj(o);
        for (const [key, v] of Object.entries((ex.objects || {})[k] || {})) {
          if (key in o) continue;
          if (key === 'within') restoreWithin(o, v);
          else o[key] = clone(v);
        }
      }
      return json4;
    }
    /** 열 때 모아 둔 within 줄을 되돌리며, 올림(up)이 같은 줄을 소속(partOf)으로도 만든 것을 걷습니다(2026-10-24 — 5단계 잔여 과제 2 걸음 0).
        기간 있는 · 여러 그릇 듦은 내림(down)이 소속 줄로 내려, 저장 한 바퀴에 within이 '잃은 칸'으로 모이는데 올림은 그 소속 줄을 partOf로 올려 둘이 겹쳤습니다
        (열고 저장할 때마다 한 벌씩 늘어남). 관계 없는 소속 줄이 되돌릴 within 줄과 상대 · 기간이 같으면 모두 걷고(이미 겹쳐 저장된 파일도 풀림),
        짝이 없는 within 줄은 되돌리지 않습니다 — 메이커에서 그 줄을 고친 것이라 고친 소속 줄이 남습니다 */
    function restoreWithin(o, rows) {
      const val = v => (v === undefined || v === '' ? null : v);
      const asRow = w => (w && typeof w === 'object' && !Array.isArray(w) ? w : { of: w });
      const twin = (p, w) => !!p && typeof p === 'object' && !p.relation && String(p.of ?? '') === String(w.of ?? '') && val(p.start) === val(w.start) && val(p.end) === val(w.end) && !!p.startUnknown === !!w.startUnknown && !!p.endUnknown === !!w.endUnknown;
      const parts = list(o.partOf);
      const kept = list(rows).filter(w => parts.some(p => twin(p, asRow(w)))).map(clone);
      if (!kept.length) return;
      o.within = kept;
      const left = parts.filter(p => !kept.some(w => twin(p, asRow(w))));
      if (left.length) o.partOf = left;
      else delete o.partOf;
    }
    /** 옛 형식(3)으로 저장하면 빠지는 것의 목록(글) — 메이커가 묻기 전에 보여 줌. J = 작업본의 옛 꼴 JSON(packToJSON — 직위 줄 빌림 · 더한 줄 · 실권은 여기서 셈 · 옛 앱은 모르는 칸을 버림) */
    function lossOf(ex, J) {
      const out = [];
      let borrow = 0, more = 0, power = 0, how = 0, regnal = 0, faiths = 0;
      for (const p of list(J && J.periods)) {
        if (!p || typeof p !== 'object') continue;
        for (const k of ['leadersFrom', 'cabinetsFrom']) if (p[k] && (typeof p[k] === 'string' || p[k].from)) borrow++;
        for (const f of list(p.offices)) {
          more++;
          if (f && f.from) borrow++;
        }
        power += list(p.power).length;
        how += list(p.succeeds).filter(x => x && typeof x === 'object' && x.how).length; // 나라 승계의 방식(6단계 결정 15)
        regnal += list(p.leaders).filter(c => c && typeof c === 'object' && c.regnal != null).length; // 이름 번호(6단계 D2)
        faiths += list(p.faiths).length; // 종교(6단계 D8)
      }
      if (borrow) out.push(`직위 줄 빌림 ${borrow}개 — 빌린 칸을 복제해 두 곳에 적음`);
      if (more) out.push(`직위 줄 셋째부터 ${more}개 — 옛 앱은 지도자 · 내각 두 줄만 그림`);
      if (power) out.push(`실권 ${power}개 — 옛 앱은 그리지 않음`);
      if (how) out.push(`승계 방식 ${how}개 — 옛 앱은 그리지 않음`);
      if (regnal) out.push(`이름 번호 ${regnal}개 — 옛 앱은 'n세'를 붙이지 않고 빈 대수를 매김`);
      const words = (J && J.leaderLabels ? 1 : 0) + list(J && J.spheres).filter(d => d && typeof d === 'object' && d.leaderLabels).length;
      if (words) out.push(`지도자 표기 낱말 ${words}곳 — 옛 앱은 묘호 · 시호 · 이름으로 보임`);
      if (faiths) out.push(`종교 ${faiths}개 — 옛 앱은 그리지 않음`);
      /* 「주기」 표 · 시대 구분의 문화권(5단계 과제 6 — 작업본이 지킴): 전체 이름 돌림 줄은 옛 열쇠 yearCycle로 남으므로 그 밖의 줄만 셈 */
      const cycles = list(J && J.yearCycles).filter(c => c && typeof c === 'object' && !(!c.sphere && Array.isArray(c.names))).length;
      if (cycles) out.push(`문화권별 주기 줄 ${cycles}개 — 전체 줄의 이름 돌림(간지 줄)만 남김`);
      const sphered = list(J && J.epochs).filter(e => e && typeof e === 'object' && e.sphere).length;
      if (sphered) out.push(`시대 구분의 문화권 ${sphered}개 — 옛 앱은 전체 공통 줄로 그림`);
      if (!ex || typeof ex !== 'object') return out;
      const counts = {};
      for (const lost of Object.values(ex.objects || {})) for (const k of Object.keys(lost)) counts[k] = (counts[k] || 0) + 1;
      const WORD = { importance: '중요도', status: '정통성', sphere: '시대 구분의 문화권', power: '실권(남의 실권 over)', display: '그리는 자리', subtype: '세부 종류', persons: '단체의 사람', members: '그릇 밖 구성원', succeeds: '승계 방식' };
      for (const [k, n] of Object.entries(counts)) out.push(`${WORD[k] || `칸 "${k}"`} ${n}개`);
      return out;
    }
    /** 옛 열쇠 yearCycle(간지 설정)이 없고 「주기」 표(yearCycles)에 전체 줄(문화권 없음 · 이름 돌림)이 있으면 그 줄을 yearCycle로도 적습니다 — 옛 앱 호환(5단계 과제 6 · down의 고르기와 같은 뜻) */
    function withLegacyCycle(json) {
      if (json && typeof json === 'object' && json.yearCycle == null) {
        const w = HT.wholeYearCycle(json.yearCycles);
        if (w) json.yearCycle = w;
      }
      return json;
    }
    /** 메이커의 저장 — 옛 꼴 JSON(정규화 뒤 packToJSON)을 형식 4로 올리고 extras를 되돌린 것(formatVersion 4) · 옛 열쇠 yearCycle도 */
    function toFile(J, ex) { return withLegacyCycle(applyExtras(up(J).json, ex)); }
    /** 옛 형식(3)으로 내보낼 JSON — 옛 꼴 그대로(옛 앱은 모르는 칸을 버림)에 옛 열쇠 yearCycle을 전체 줄에서 채움 */
    function legacyFile(J) { return withLegacyCycle(clone(J)); }

    function project(J) {
      const src = clone(J) || {};
      const periods = src.periods || [];
      for (const p of periods) {
        const kind = p.kind || 'state';
        const fill = HT.relationOfKind(kind);
        const entries = list(p.partOf).map(entryOf);
        const n = entries.length;
        const out = entries.map(e => {
          const folded = folds(n, e);
          const r = Object.assign({}, e);
          if (!r.relation && fill) r.relation = fill; // P1 비운 관계를 종류에서 채움
          return setNest(r, nestFor(n, r, folded)); // P1 nest를 가장 짧게(접힘은 그대로)
        });
        if (n) p.partOf = HT.compactPartOf(out);
        if (n && STATE_DEPENDENT.includes(kind)) delete p.kind; // P2 국가 + 관계(설계 3-8 '종속 kind의 옅은 띠 → 국가 띠 + 관계')
        const own = typeId(p.type);
        if (kind === 'org' && !(own && kindOfType(own) === 'org')) p.kind = 'warlord'; // P3 설계 3-8 'org → 군벌' — 적어 둔 객체 종류가 조직체 갈래(동맹 · 실권 정권 · 교단 · 기사단 · 회사 · 직위)면 조직체 그대로(5단계 과제 3)
      }
      /* P4 대범위 구성원: 같은 파일에서 찾은 정권은 객체 id로 · 객체 차례로, 못 찾은 것은 뒤에 적은 차례로(모델은 구성원을 시작 해로 다시 줄 세움) */
      for (const s of src.scopes || []) {
        const found = [];
        const outside = [];
        for (const r of HT.readScopeRefs(s.members)) {
          const t = r.track || s.track;
          const m = periods.find(q => q.track === t && (q.name === r.polity || q.id === r.polity));
          if (!m) outside.push(HT.compactScopeRef(r));
          else if (!found.includes(m)) found.push(m);
        }
        found.sort((a, b) => periods.indexOf(a) - periods.indexOf(b));
        s.members = found.map(m => HT.compactScopeRef(m.track !== s.track ? { track: m.track, polity: m.id } : { polity: m.id })).concat(outside);
      }
      return src;
    }

    return { VERSION, UNKNOWN, TYPES, DISPLAYS, STATUSES, typeId, statusId, typeOfKind, kindOfType, up, down, project, extrasOf, applyExtras, lossOf, toFile, legacyFile };
  })();

  /* ---------- 내장 팩 등록 (packs/*.js에서 사용) ----------
     형식 3 선언(formatVersion을 적지 않음 — 기본값 3)은 지금 그대로: periods · epochs · events 목록에 쌓습니다.
     형식 4 선언(formatVersion: 4 — 리메이크 6단계 · docs/기본팩-손질-목록-초안.md 3-1 결정 1)은 압축 배열로 적는 꼴 · id 만드는 길(`${track}-p${hash(시작+이름)}`) ·
     덧칸 id가 이김(R7)을 그대로 두고, 팩이 내는 JSON만 formatVersion 4 + objects로 냅니다 — 다리(HT.F4.down)가 읽어 옛 꼴로 내립니다.
     형식 3의 대범위 구성원에는 기간 칸이 없어, 기간 있는 within(통일 왕조 R2 · 옮겨 앉기)은 형식 4로만 적을 수 있기 때문입니다.
     HT.packRegistry(store?, opts?)는 같은 등록 함수를 따로 쓰는 등록부를 돌려줍니다(검사가 내장 목록을 더럽히지 않게 — scripts/check-format4.mjs ⑰) */
  HT.packRegistry = (store = new Map(), { warn = msg => console.warn(msg) } = {}) => {
    const v4 = p => Number(p.formatVersion) === HT.F4.VERSION;
    const get = id => {
      const p = store.get(id);
      if (!p) throw new Error(`정의되지 않은 내장 팩: ${id}`);
      return p;
    };
    /** 형식 4는 objects · events만 준비하고(빈 periods · epochs를 넣으면 다리가 '읽지 않음'을 알리고 버림), 형식 3은 지금 그대로 */
    const definePack = raw => {
      const base = Number(raw && raw.formatVersion) === HT.F4.VERSION
        ? { format: HT.FORMAT, tracks: [], categories: [], peoples: [], objects: [], events: [] }
        : { format: HT.FORMAT, formatVersion: HT.FORMAT_VERSION, tracks: [], categories: [], peoples: [], epochs: [], periods: [], events: [] };
      store.set(raw.id, Object.assign(base, raw));
    };
    /** 압축 표기: periods [시작, 끝|'now', 이름, 설명, 옵션], events [시작, 끝|null, 분류, 중요도, 제목, 설명, 옵션].
        형식 4 팩만: eras [시작, 끝|'now', 이름, 설명, 옵션] → 시대 객체(type 'era' · id는 옵션 id가 없으면 `${track}-e${hash(시작+이름)}`),
        persons [태어난 해, 죽은 해, 이름, 설명, 옵션] 또는 { … } → 사람 객체(type 'person' · id는 없으면 `${track}-f${hash(태어난 해+이름)}`). 옵션(덧칸)이 늘 이깁니다 */
    const extendPack = (id, { track, periods = [], events = [], eras = [], persons = [] }) => {
      const p = get(id);
      const four = v4(p);
      const span = (start, end) => ({ start, end: end === 'now' ? undefined : end, ongoing: end === 'now' || undefined });
      for (const [start, end, name, description, opts] of periods) {
        const o = Object.assign({ id: `${track}-p${HT.hash(start + name)}`, track, name, start, end: end === 'now' ? undefined : end, ongoing: end === 'now' || undefined, description }, opts);
        (four ? p.objects : p.periods).push(o);
      }
      if ((eras.length || persons.length) && !four) throw new Error(`내장 팩 ${id}: 시대 객체(eras) · 사람(persons)은 형식 4 선언(formatVersion: 4) 팩에만 적습니다.`);
      for (const [start, end, name, description, opts] of eras) {
        p.objects.push(Object.assign({ id: `${track}-e${HT.hash(start + name)}`, type: 'era', track, name }, span(start, end), { description }, opts));
      }
      for (const x of persons) {
        if (Array.isArray(x)) {
          const [birth, death, name, description, opts] = x;
          p.objects.push(Object.assign({ id: `${track}-f${HT.hash(birth + name)}`, type: 'person', track, name, birth, death: death ?? undefined, description }, opts));
        } else if (x && typeof x === 'object') {
          p.objects.push(Object.assign({ id: `${track}-f${HT.hash((x.birth ?? x.start) + x.name)}`, type: 'person', track }, x));
        }
      }
      for (const [start, end, category, importance, title, description, opts] of events) {
        p.events.push(Object.assign({ id: `${track}-${HT.hash(start + title)}`, track, start, end: end ?? undefined, category, importance, title, description }, opts));
      }
    };
    /** 승계 줄 — 배열 [이름, 종류, 메모, 정도, [이어진 것]] 또는 객체 { from, type, how, note, degree, parts }(방식 how는 객체 꼴로) */
    const succRow = x => {
      if (!Array.isArray(x)) return Object.assign({}, x);
      const [from, type, note, degree, parts] = x;
      return Object.assign({ from, type, note }, degree != null ? { degree } : {}, parts != null ? { parts } : {}); // 부분 승계는 [이름, 'partial', 메모, 정도, [이어진 것]]
    };
    const listOf = v => (v == null ? [] : Array.isArray(v) ? v : [v]);
    /** 직위 줄 하나에 칸을 더함 — 없으면 새 줄(지도자 줄은 맨 앞 · 형식 4 '첫 줄이 지금의 지도자 줄') */
    const officeCells = (o, name, cells) => {
      const offs = o.offices || (o.offices = []);
      let f = offs.find(x => x && x.name === name);
      if (!f) {
        f = { name, cells: [] };
        if (name === '지도자') offs.unshift(f);
        else offs.push(f);
      }
      f.cells = listOf(f.cells).concat(cells);
    };
    const F4_KEYS = ['type', 'within', 'partOf', 'power', 'offices', 'status', 'importance', 'names'];
    /** 이름으로 시대(형식 4는 객체 — id로도)에 민족·승계·지도자·내각·연호를 덧붙입니다.
     *  { '발해': { people: '한민족', succeeds: [['고구려', 'direct', '메모']], cabinets: [['이름', 시작, 끝, '메모']] } }
     *  형식 4 팩은 덧칸 type · within · partOf · power · offices · status · importance · names도 받고(설정 · 목록은 덧붙임), 지도자 · 내각은 직위 줄 '지도자' · '내각'에 담습니다 */
    const describePeriods = (id, track, info) => {
      const p = get(id);
      const four = v4(p);
      const has = k => k != null && k !== '' && Object.prototype.hasOwnProperty.call(info, k);
      const found = new Set();
      for (const period of four ? p.objects : p.periods) {
        let add, key;
        if (four) {
          key = period.track === track ? (has(period.id) ? period.id : has(period.name) ? period.name : null) : null;
          add = key != null && info[key];
        } else {
          add = period.track === track && info[period.name];
          key = period.name;
        }
        if (!add) continue;
        found.add(key);
        if (add.people) period.people = add.people;
        if (add.house) period.house = add.house; // 국성 (가문)
        if (add.succeeds) period.succeeds = add.succeeds.map(succRow);
        for (const k of four ? ['eras', 'capitals'] : ['leaders', 'cabinets', 'eras', 'capitals']) if (add[k]) period[k] = (period[k] || []).concat(add[k]);
        if (four) {
          if (add.leaders) officeCells(period, '지도자', add.leaders);
          if (add.cabinets) officeCells(period, '내각', add.cabinets);
        }
        if (add.phases) period.phases = (period.phases || []).concat(add.phases); // 시기 구분(학계): 체계 목록 [{ scheme, note, spans: [['이름', 시작, 끝, '메모']] }]
        if (add.ranks) period.ranks = (period.ranks || []).concat(add.ranks); // 지위 변천: [['지위', 시작, 끝, '메모']] (첫 칸의 시작은 비워도 됨 — 정권 시작부터)
        if (add.historicity) period.historicity = add.historicity; // 실재성 (8-4 마)
        if (add.historicityNote) period.historicityNote = add.historicityNote;
        for (const k of F4_KEYS) {
          if (add[k] == null) continue;
          if (!four) {
            warn(`describePeriods: ${track} 트랙 "${key}"의 ${k}은(는) 형식 4 선언 팩에만 적습니다 — 뺐습니다.`);
            continue;
          }
          if (['type', 'status', 'importance'].includes(k)) period[k] = add[k];
          else period[k] = listOf(period[k]).concat(add[k]);
        }
      }
      for (const name of Object.keys(info)) if (!found.has(name)) warn(`describePeriods: ${track} 트랙에 "${name}" ${four ? '객체' : '시대'}가 없습니다.`);
    };
    /** 내장 팩에 영토(지도) 규칙을 붙입니다: { basemap, polities, generate(cell) → [[시작, 끝, 정권, 상태?, 상대?], …] } */
    const defineTerritory = (id, territory) => {
      get(id).territory = territory;
    };
    return { definePack, extendPack, describePeriods, defineTerritory, get: id => store.get(id), all: () => [...store.values()] };
  };
  const builtins = new Map();
  const builtinRegistry = HT.packRegistry(builtins);
  HT.definePack = builtinRegistry.definePack;
  HT.extendPack = builtinRegistry.extendPack;
  HT.describePeriods = builtinRegistry.describePeriods;
  HT.defineTerritory = builtinRegistry.defineTerritory;
  HT.getBuiltinPacks = () => [...builtins.values()];

  /* ---------- 가문 ----------
   * 가문 사전(DLC의 houses — id로만 합치고 먼저 켠 DLC의 정의가 이김)과 그것을 가리키는 칸(house)을 잇습니다(buildModel의 끝에서).
   * 참조는 id → 이름 순으로 찾고, 사전에 없는 이름은 그 이름으로 가문을 만듭니다(auto: true — id는 "h-" + 이름의 해시라 늘 같음).
   * 원문(house)은 고쳐 쓰지 않고, 풀어낸 것은 houseId · houseName · houseColor에 둡니다 (뷰어 수정 폼은 모델 항목으로 채워지므로 섞이면 짐작이 자료로 굳음).
   *   시대의 house = 국성 · 왕조의 house = 가문 — 옛 파일에서는 본가 왕조의 이름이므로, 사전에 없고 그 이름의 왕조가 있으면 가문으로 만들지 않습니다
   *     (뷰어가 예전처럼 본가 왕조로 보여 줌)
   *   지도자의 가문: 적은 house → 시작한 해의 왕조의 가문 → 나라의 국성 (적지 않고 짐작한 것은 houseAuto: true) · 내각은 적은 것만
   *   인물(model.figures)의 house도 — 가문 구성원(role 'figure')이 되고 houseId · houseName이 붙음
   * 가문마다 members(구성원 { role: 'period'(국성으로 삼은 나라) | 'dynasty' | 'leader' | 'cabinet' | 'figure', item, cell, ref, start, end, auto } — 시작 순)와
   * 본가 → 분가 나무(parentId · path(뿌리부터의 id) · depth · children). 문서 키는 "house:id" */
  const linkHouses = (model, packs) => {
    const houses = new Map();
    const byName = new Map();
    let seq = 0;
    const add = (h, auto) => {
      if (houses.has(h.id)) return houses.get(h.id);
      const o = {
        id: h.id, uid: `house:${h.id}`, itemKind: 'house', name: h.name || h.id,
        surname: h.surname || '', seat: h.seat || '', parent: h.parent || '', founder: h.founder || '',
        color: HT.pastel(h.color || HT.autoColor(`house:${h.id}`)), description: h.description || '', wiki: h.wiki || '',
        names: Array.isArray(h.names) ? h.names : [], // 이름 목록 (형식 버전 3)
        track: h.track || '', people: h.people || '', tags: Array.isArray(h.tags) ? h.tags : [], // 세계표 머리의 구분 · 민족 · 꼬리표 (형식 버전 3 — 적은 것만, 짐작은 trackAuto · peopleAuto)
        packId: h.packId || '', packName: h.packName || '', auto: !!auto, seq: seq++, members: [],
      };
      houses.set(o.id, o);
      if (!byName.has(o.name)) byName.set(o.name, o);
      return o;
    };
    for (const pack of packs) for (const h of pack.houses || []) add(Object.assign({ packId: pack.id, packName: pack.name }, h));
    const find = ref => {
      const r = String(ref ?? '').trim();
      return r ? houses.get(r) || byName.get(r) || null : null;
    };
    const ensure = ref => {
      const r = String(ref ?? '').trim();
      return r ? find(r) || add({ id: `h-${HT.hash(r)}`, name: r }, true) : null;
    };
    const put = (x, h) => Object.assign(x, { houseId: h.id, houseName: h.name, houseColor: h.color });
    const periods = model.periods;
    /* ① 왕조: 사전에 있으면 그 가문, 없으면 본가 왕조 이름인지 보고(그렇다면 가문으로 만들지 않음) 아니면 새 가문 */
    const dyns = periods.filter(p => p.polityKind === 'dynasty');
    for (const d of dyns) {
      if (!d.house) continue;
      const h = find(d.house) || (dyns.some(q => q !== d && (q.name === d.house || q.id === d.house || q.uid === d.house)) ? null : ensure(d.house));
      if (h) put(d, h);
    }
    /* ② 국성 */
    for (const p of periods) if (HT.itemKindOf(p) === 'period' && p.house) put(p, ensure(p.house));
    /* ③ 지도자 · 내각 — 칸 목록은 복사해서 답니다 (팩의 칸 객체를 그대로 쓰는 목록일 수 있어, 거기에 적으면 내보내는 파일에 섞임) */
    for (const p of periods) {
      if (p.leaders && p.leaders.length)
        p.leaders = p.leaders.map(c => {
          let h = c.house ? ensure(c.house) : null;
          const auto = !h;
          if (!h) {
            const dn = c.dynasty || c.dynastyAuto;
            const d = dn ? (p.dynasties || []).find(x => x.dynasty.name === dn) : null;
            h = (d && d.dynasty.houseId && houses.get(d.dynasty.houseId)) || (p.houseId && houses.get(p.houseId)) || null;
          }
          return h ? put(Object.assign({}, c, auto ? { houseAuto: true } : {}), h) : c;
        });
      if (p.cabinets && p.cabinets.length && p.cabinets.some(c => c.house)) p.cabinets = p.cabinets.map(c => (c.house ? put(Object.assign({}, c), ensure(c.house)) : c));
    }
    /* ④ 구성원 */
    const member = (id, m) => houses.get(id).members.push(m);
    for (const p of periods) {
      const kind = HT.itemKindOf(p);
      if (p.houseId && (kind === 'period' || kind === 'dynasty')) member(p.houseId, { role: kind, item: p, start: p.start, end: p.endY });
      (p.leaders || []).forEach((c, i) => c.houseId && member(c.houseId, { role: 'leader', item: p, cell: c, ref: `leader:${i}`, start: c.start, end: c.end ?? p.endY, auto: !!c.houseAuto }));
      (p.cabinets || []).forEach((c, i) => c.houseId && member(c.houseId, { role: 'cabinet', item: p, cell: c, ref: `cabinet:${i}`, start: c.start, end: c.end ?? p.endY }));
    }
    for (const f of model.figures || []) {
      const h = f.houseId ? houses.get(f.houseId) : f.house ? ensure(f.house) : null;
      if (!h) continue;
      put(f, h);
      member(h.id, { role: 'figure', item: f, start: f.start, end: f.endY ?? f.end ?? f.start });
    }
    /* 계보 전용 인물(D1): 적은 가문은 풀어 두되 구성원 목록(members — 가문 창 · 띠)에는 넣지 않습니다 — 가문 창 목록이 사람 수에 따라 늘지 않게(사람 자리의 가문은 linkPeople) */
    for (const f of model.lineageFigures || []) {
      const h = f.houseId ? houses.get(f.houseId) : f.house ? ensure(f.house) : null;
      if (h) put(f, h);
    }
    const ROLE_ORDER = { period: 0, dynasty: 1, leader: 2, cabinet: 3, figure: 4 }; // 같은 해에 시작하면 나라 · 왕조가 앞
    for (const h of houses.values()) h.members.sort((a, b) => a.start - b.start || ROLE_ORDER[a.role] - ROLE_ORDER[b.role]);
    /* ⑤ 본가 → 분가 (적은 본가가 사전에 없으면 그 이름으로 만듭니다 · 돌고 도는 것은 끊음) */
    for (const h of [...houses.values()]) {
      const parent = h.parent ? ensure(h.parent) : null;
      h.parentId = parent && parent !== h ? parent.id : null;
    }
    for (const h of houses.values()) {
      const path = [];
      const seen = new Set();
      for (let cur = h; cur && !seen.has(cur.id); cur = cur.parentId ? houses.get(cur.parentId) : null) {
        seen.add(cur.id);
        path.unshift(cur.id);
      }
      h.path = path;
      h.depth = path.length - 1;
    }
    /* 분가 목록: 본가 id → 분가들을 한 번에 모읍니다 (가문마다 전체를 훑으면 가문 수의 제곱 — D1 6-3 ⑦) · 차례는 가문 차례(seq) 그대로 */
    const kids = new Map();
    for (const x of houses.values()) if (x.parentId && x.parentId !== x.id) (kids.get(x.parentId) || kids.set(x.parentId, []).get(x.parentId)).push(x.id);
    for (const h of houses.values()) h.children = kids.get(h.id) || [];
    /* ⑥ 문서: houses[].wiki → "house:id" (사용자가 고친 글 · DLC의 documents가 먼저) */
    for (const h of houses.values()) if (h.wiki && !model.docs.has(h.uid)) model.docs.set(h.uid, { text: h.wiki, packId: h.packId, packName: h.packName });
    for (const h of houses.values()) {
      const d = model.docs.get(h.uid);
      if (!d) continue;
      h.wiki = d.text;
      if (d.user) h.wikiUser = true;
    }
    model.houses = [...houses.values()];
    model.houseMap = houses;
    return model;
  };

  /* ---------- 형식 3: 모아 보기 판 · 지도 · 글꼴의 모델 (buildModel의 끝에서 — linkFormat3) ----------
   * 판의 구성 나라 · 장면의 주인(나라 참조)을 모델의 나라(시대 항목)로 풉니다. 원문은 그대로 두고(판 memberRefs · 장면 owners) 풀어낸 것은 다른 이름에(members · ownerItems).
   * 다른 트랙 · 다른 DLC의 나라일 수 있어 파일 검사에서는 막지 않고, 못 찾으면 그 판 · 지도의 warnings에 적습니다(대범위의 '확인할 것'과 같은 길).
   * id가 같으면 여러 DLC에 걸쳐 하나(가문과 같은 규칙 — 먼저 켠 DLC의 것이 쓰이고, 뒤의 것은 쓰지 않았다고 앞의 것의 warnings에).
   * model.views · viewMap / maps · mapMap / fonts · fontMap — 판 · 지도 · 글꼴이 하나도 없으면 빈 목록(그 밖의 모델은 1px도 다르지 않음) */
  /** 나라 참조({ track?, polity }) → 모델의 나라. 트랙을 적으면 그 트랙에서, 아니면 uid · 같은 DLC의 id · 이름 순으로(이름은 같은 DLC의 나라 먼저, year를 주면 그해에 있던 나라 먼저).
      돌려주는 값: { item(없으면 null), tracks(같은 이름이 걸친 트랙들 — 둘 이상이면 모호함) } */
  const polityFinder = model => {
    const list = model.periods.filter(p => HT.itemKindOf(p) === 'period');
    const byName = new Map();
    for (const p of list) {
      if (!byName.has(p.name)) byName.set(p.name, []);
      byName.get(p.name).push(p);
    }
    const pick = (cands, packId, year) => {
      if (!cands.length) return { item: null, tracks: [] };
      const own = cands.filter(q => q.packId === packId);
      let pool = own.length ? own : cands;
      if (year != null) {
        const live = pool.filter(q => year >= q.start - 1e-9 && year < (q.endY ?? q.start) + 1);
        if (live.length) pool = live;
      }
      return { item: pool[0], tracks: [...new Set(pool.map(q => q.track))] };
    };
    return (ref, packId, year) => {
      if (ref.track) return pick(list.filter(q => q.track === ref.track && (q.name === ref.polity || q.id === ref.polity || q.uid === ref.polity)), packId, year);
      const exact = list.find(q => q.uid === ref.polity) || list.find(q => q.packId === packId && q.id === ref.polity);
      if (exact) return { item: exact, tracks: [exact.track] };
      return pick(byName.get(ref.polity) || [], packId, year);
    };
  };
  /** 지도의 장면 목록 — 장면(열쇠 해)마다 그때까지 이어받은 주인(owners: 구역 id → 나라 참조 · items: 구역 id → 모델의 나라(모델의 지도일 때만, 못 찾으면 null))과
      그때의 그림(그 장면이나 앞 장면의 그림, 없으면 바탕 그림). 해 순 */
  const mapScenesOf = map => {
    const scenes = [];
    let owners = {};
    let items = {};
    let image = map.image || null;
    arr(map.frames)
      .filter(f => f && typeof f === 'object' && typeof f.year === 'number' && isFinite(f.year))
      .sort((a, b) => a.year - b.year)
      .forEach((f, index) => {
        owners = Object.assign({}, owners);
        items = Object.assign({}, items);
        for (const [rid, ref] of Object.entries(f.owners || {})) {
          if (ref == null) {
            delete owners[rid];
            delete items[rid];
          } else {
            owners[rid] = ref;
            if (f.ownerItems) items[rid] = f.ownerItems[rid] || null;
          }
        }
        if (f.image) image = f.image;
        scenes.push({ index, year: f.year, yearAt: f.yearAt || null, frame: f, owners, items, image, note: f.note || '' });
      });
    return scenes;
  };
  /** 지도의 장면 목록 (모델의 지도는 미리 셈한 것, 팩의 지도는 그 자리에서) */
  HT.mapScenes = map => (!map || typeof map !== 'object' ? [] : Array.isArray(map.scenes) ? map.scenes : mapScenesOf(map));
  /** 구역이 그 해에 있는지 — [시작, 끝) (끝 해에는 이미 없음 · 영토의 소유 기록과 같은 규칙) */
  HT.mapRegionAlive = (r, y) => !!r && (r.start == null || y >= r.start - 1e-9) && (r.end == null || y < r.end - 1e-9);
  /** 그 해(수 또는 날짜 글)에 쓰는 장면: 그 해나 그 앞의 마지막 열쇠 해의 장면(사이의 해는 앞 열쇠 해를 따름 · 경계를 섞어 움직이지 않음).
      첫 장면보다 앞이거나 장면이 없으면 null(바탕 그림만). 돌려주는 값: { index, year(열쇠 해), yearAt, frame, image, note, at(물은 해),
      regions(그 해에 있는 구역 id), owners · items(그 해에 있는 구역만) } — 팩의 지도(정규화한 것)나 모델의 지도(model.maps) 둘 다 받습니다 */
  HT.mapFrameAt = (map, year) => {
    let y = year;
    if (typeof y !== 'number') {
      const d = HT.readDate(year);
      y = d ? d.t : NaN;
    }
    if (!isFinite(y)) return null;
    const scenes = HT.mapScenes(map);
    let lo = 0;
    let hi = scenes.length - 1;
    let at = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (scenes[mid].year <= y + 1e-9) {
        at = mid;
        lo = mid + 1;
      } else hi = mid - 1;
    }
    if (at < 0) return null;
    const s = scenes[at];
    const regions = arr(map.regions).filter(r => HT.mapRegionAlive(r, y)).map(r => r.id);
    const live = new Set(regions);
    const only = o => Object.fromEntries(Object.entries(o).filter(([k]) => live.has(k)));
    return Object.assign({}, s, { at: y, regions, owners: only(s.owners), items: only(s.items) });
  };
  /** 모델의 글꼴(또는 팩) → 브라우저 FontFace에 넘길 목록 [{ id, family, source(CSS src 글 — url(data:…) format(…)), descriptors, scripts, license, packId }].
      new FontFace(x.family, x.source, x.descriptors)로 만들어 document.fonts에 더하면 됩니다 (붙이는 화면은 따로 — 여기서는 목록만) */
  HT.fontFaces = model =>
    arr(model && model.fonts).map(f => ({ id: f.id, family: f.family, source: `url("${f.src}") format("${f.format || HT.fontFormat(f.src)}")`, descriptors: { display: 'swap' }, scripts: arr(f.scripts).slice(), license: f.license, packId: f.packId || '' }));
  const linkFormat3 = (model, packs) => {
    model.views = [];
    model.viewMap = new Map();
    model.maps = [];
    model.mapMap = new Map();
    model.fonts = [];
    model.fontMap = new Map();
    if (!packs.some(p => p && (p.views || p.maps || p.fonts))) return model;
    const find = polityFinder(model);
    const trackName = id => (model.trackMap.get(id) || {}).name || id;
    const resolve = (ref, packId, year, warnings, what) => {
      const r = find(ref, packId, year);
      if (!r.item) warnings.push(`${what} "${HT.scopeRefText(ref)}"을(를) 연표에서 찾지 못했습니다.`);
      else if (r.tracks.length > 1) warnings.push(`${what} "${ref.polity}" — 이름이 같은 나라가 여러 트랙(${r.tracks.map(trackName).join(' · ')})에 있어 ${trackName(r.item.track)}의 것을 골랐습니다. "트랙:이름"으로 적으면 하나로 정해집니다.`);
      return r.item;
    };
    /* 문서: 판 · 지도의 wiki → "view:id" · "map:id" (사용자가 고친 글 · DLC의 documents가 먼저 — 가문과 같게) */
    const putDoc = o => {
      if (o.wiki && !model.docs.has(o.uid)) model.docs.set(o.uid, { text: o.wiki, packId: o.packId, packName: o.packName });
      const d = model.docs.get(o.uid);
      if (d) {
        o.wiki = d.text;
        if (d.user) o.wikiUser = true;
      }
    };
    const once = (byId, raw, pack, word) => {
      const prev = byId.get(raw.id);
      if (prev) prev.warnings.push(`DLC «${pack.name}»에도 같은 id(${raw.id})의 ${word}이(가) 있어 그쪽은 쓰지 않았습니다.`);
      return !prev;
    };
    for (const pack of packs) {
      for (const raw of pack.views || []) {
        if (!once(model.viewMap, raw, pack, '모아 보기 판')) continue;
        const warnings = [];
        const members = [];
        for (const ref of HT.readScopeRefs(raw.members)) {
          const m = resolve(ref, pack.id, null, warnings, '구성 나라');
          if (m && !members.includes(m)) members.push(m);
        }
        const o = Object.assign({}, raw, { kind: 'view', itemKind: 'view', uid: `view:${raw.id}`, packId: pack.id, packName: pack.name, memberRefs: raw.members, members, warnings });
        o.tracks = [...new Set(members.map(p => p.track))]; // 판이 걸친 트랙 (구성 나라의 차례)
        if (raw.start != null) o.endY = raw.ongoing ? Math.max(HT.NOW_T, raw.start) : raw.end ?? raw.start;
        if (!HT.isColor(raw.color)) o.colorAuto = true;
        o.color = HT.pastel(HT.isColor(raw.color) ? raw.color : HT.autoColor(o.uid));
        putDoc(o);
        model.viewMap.set(raw.id, o);
        model.views.push(o);
      }
      for (const raw of pack.maps || []) {
        if (!once(model.mapMap, raw, pack, '지도')) continue;
        const warnings = [];
        const frames = arr(raw.frames).map(f => {
          if (!f.owners) return Object.assign({}, f);
          const ownerItems = {};
          for (const [rid, ref] of Object.entries(f.owners)) {
            const r = ref == null ? null : HT.readScopeRef(ref);
            const what = `${f.yearAt || HT.yearOf(f.year)}년 장면의 구역 "${rid}" 주인`;
            const item = r ? resolve(r, pack.id, f.year, warnings, what) : null;
            if (item && !(f.year >= item.start - 1e-9 && f.year < (item.endY ?? item.start) + 1)) warnings.push(`${what} "${item.name}"은(는) 그해에 연표에 없던 나라입니다 (${HT.formatRange(item)}).`);
            ownerItems[rid] = item || null;
          }
          return Object.assign({}, f, { ownerItems });
        });
        const o = Object.assign({}, raw, { kind: 'map', itemKind: 'map', uid: `map:${raw.id}`, packId: pack.id, packName: pack.name, frames, warnings });
        o.placeItems = arr(raw.places).map(ref => HT.placeOf(model, ref)); // 지명 글 → 지명 사전의 지명 (사람 잇기의 지명 풀이 — 원문 places는 그대로)
        o.regionMap = new Map(arr(raw.regions).map(r => [r.id, r]));
        o.scenes = mapScenesOf(o);
        putDoc(o);
        model.mapMap.set(raw.id, o);
        model.maps.push(o);
      }
      for (const raw of pack.fonts || []) {
        if (!once(model.fontMap, raw, pack, '글꼴')) continue;
        const o = Object.assign({}, raw, { itemKind: 'font', uid: `font:${raw.id}`, packId: pack.id, packName: pack.name, format: HT.fontFormat(raw.src), warnings: [] });
        model.fontMap.set(raw.id, o);
        model.fonts.push(o);
      }
    }
    return model;
  };

  /* ---------- 여러 팩 + 사용자 데이터 병합 ---------- */
  /* 조약의 서명자 ↔ 인물: 인물(model.figures — 다른 줄의 기능)이 있을 때만, 이름(또는 인물의 다른 이름)이 같은 인물의 uid를 서명자 사본(treatyRefs)에 답니다.
     파일에는 인물을 가리키는 칸을 두지 않습니다 (폼에 칸이 없어 한 번 고치면 사라지는 연결이 되지 않게 — 이름으로만 잇습니다).
     거꾸로 인물 쪽에는 모델 전용 signedTreaties = [{ event(조약 사건), party(당사국 사본), signer(서명자 사본) }] — 인물 창의 '서명한 조약' 목록 (체결 순) */
  const linkTreatySigners = model => {
    if (!Array.isArray(model.figures) || !model.figures.length) return;
    const byName = new Map();
    for (const f of model.figures) {
      const names = [f.name].concat(...['aka', 'aliases', 'names'].map(k => (Array.isArray(f[k]) ? f[k] : [])));
      for (const n of names) if (n && !byName.has(String(n).trim())) byName.set(String(n).trim(), f);
    }
    for (const e of model.events) {
      if (!e.treatyRefs) continue;
      for (const pt of e.treatyRefs.parties)
        for (const s of pt.signatories) {
          const f = byName.get(s.name);
          if (!f || !f.uid) continue;
          s.figureUid = f.uid;
          const list = f.signedTreaties || (f.signedTreaties = []);
          if (!list.some(r => r.event === e)) list.push({ event: e, party: pt, signer: s }); // 한 조약에 두 번 적힌 이름(두 당사국의 서명자)은 한 줄로
        }
    }
    for (const f of model.figures) if (f.signedTreaties) f.signedTreaties.sort((a, b) => a.event.start - b.event.start);
  };

  /* ---------- 지명 · 성씨 · 사람 · 계보 (형식 버전 3 — docs/구상-연표-확장-10건.md 바탕 1 · 3, 3-1 · 3-2) ----------
   * buildModel의 끝(가문 잇기 다음)에서 엽니다. 원문 칸은 고쳐 쓰지 않고, 풀어낸 것은 모델 전용 목록 · 표에만 둡니다(짐작 값은 파일과 다른 이름에).
   * ① 지명(model.places · placeMap): 사전(DLC의 places — id로만 합치고 먼저 켠 DLC의 정의가 이김) + 도읍의 도시 · 사건의 장소 · 조약의 맺은 곳 · 위 구역에서 저절로(auto — id는 "pl-" + 이름의 해시).
   *    지명마다 uses(쓰인 곳 { role: 'capital' | 'event' | 'treaty', item, ref?, start, end? }) · 위 구역 나무(parentId · path · children).
   * ② 성씨(model.surnames · surnameMap): 사전(DLC의 surnames) + 가문들의 성(surname)에서 저절로. 성씨마다 houses(그 성의 가문 id) — 가문에는 surnameId.
   * ③ 사람(model.persons · personIndex): 인물 하나 · 지도자 칸 · 사람을 적은 내각 칸이 한 사람의 자리. 칸의 person(인물 id · 이름 · 다른 칸)이 같으면 한 사람
   *    (두 나라를 다스린 같은 사람 · 다시 오른 사람). person이 없는 지도자 칸은 이름(묘호 · 시호 · 이름)이 같고 시기가 겹치는 같은 트랙(또는 그 나라를 섬긴) 인물과
   *    저절로 한 사람(연표의 '같은 이름의 인물'과 같은 규칙 — auto). 부모 · 배우자의 who와 자리 이음의 from도 같은 찾기:
   *    인물 → 칸의 person에 적힌 이름 → 지도자 칸의 이름(같은 나라 → 같은 트랙 → 모두에서 하나뿐일 때) → 못 찾으면 그 이름의 자리를 만들고(missing) 경고.
   *    "미상"은 줄마다 이름 모를 사람의 자리 하나(unknown — 세대 수를 지키는 빈 고리).
   * ④ 자리 이음: from을 적은 지도자 칸의 앞 지도자(accessionFrom), 관계(kin)가 혈연과 어긋나면 경고. 경고는 model.peopleWarnings [{ msg, packId, list, id }] — 메이커의 검사 창 */
  const linkPeople = (model, packs) => {
    const { periods, events, docs } = model;
    const figures = (model.figures || []).concat(model.lineageFigures || []); // 계보 전용 인물도 사람 자리 · 부모 찾기에 (D1 2-4 가)
    const warnings = [];
    const warnAt = (x, msg) => warnings.push({ msg, packId: x ? x.packId || '' : '', list: x ? (x.kind === 'figure' ? 'figures' : x.kind === 'event' ? 'events' : { organ: 'organs', culture: 'cultures', dynasty: 'dynasties' }[HT.itemKindOf(x)] || 'periods') : '', id: x ? x.id : '' });
    const t = v => String(v ?? '').trim();
    /* ① 지명 */
    const places = new Map();
    const placeByName = new Map();
    let pseq = 0;
    const addPlace = (x, auto) => {
      if (places.has(x.id)) return places.get(x.id);
      const o = { id: x.id, uid: `place:${x.id}`, itemKind: 'place', name: x.name || x.id, names: Array.isArray(x.names) ? x.names : [], at: Array.isArray(x.at) ? x.at : null, parent: x.parent || '', note: x.note || '', description: x.description || '', wiki: x.wiki || '', packId: x.packId || '', packName: x.packName || '', auto: !!auto, seq: pseq++, uses: [] };
      places.set(o.id, o);
      if (!placeByName.has(o.name)) placeByName.set(o.name, o);
      return o;
    };
    for (const pack of packs)
      for (const x of pack.places || []) {
        const twin = !places.has(x.id) && placeByName.get(x.name || x.id);
        if (twin && twin.packId === pack.id) warnings.push({ msg: `지명 사전에 이름 "${x.name || x.id}"이(가) 둘 있습니다(${twin.id} · ${x.id}) — 이름으로 적은 곳은 앞의 지명에 붙습니다. 뒤의 지명은 id로 적습니다.`, packId: pack.id, list: 'places', id: x.id });
        addPlace(Object.assign({ packId: pack.id, packName: pack.name }, x));
      }
    const findPlace = ref => (t(ref) ? places.get(t(ref)) || placeByName.get(t(ref)) || null : null);
    const ensurePlace = ref => (t(ref) ? findPlace(ref) || addPlace({ id: `pl-${HT.hash(t(ref))}`, name: t(ref) }, true) : null);
    for (const p of periods) {
      if (HT.itemKindOf(p) !== 'period') continue;
      (p.capitals || []).forEach((c, i) => {
        const pl = (c.placeId && places.get(c.placeId)) || ensurePlace(c.city); // 사전 id로 적은 도읍(모델 사본의 placeId)은 그 지명 — 이름이 같은 지명이 여럿이어도
        if (pl) pl.uses.push({ role: 'capital', item: p, ref: `capital:${i}`, start: c.start, end: c.endY ?? c.end ?? c.start, as: c.as || '' });
      });
    }
    for (const e of events) {
      const pl = ensurePlace(e.place);
      if (pl) pl.uses.push({ role: 'event', item: e, start: e.start, end: e.endY });
      const tp = e.treaty && ensurePlace(e.treaty.place);
      if (tp) tp.uses.push({ role: 'treaty', item: e, start: e.start, end: e.endY });
    }
    /* 지도의 지명 글 목록(형식 3 — maps[].places, F3와 잇기): 같은 찾기(id → 이름 → 없으면 그 이름으로 저절로)로 지명 사전에 — 지도의 모델(linkFormat3)이 placeItems로 풉니다.
       지도에는 기간이 없어 쓰인 곳(uses)의 맨 앞에(role 'map' · item 없음 — 지도 id만) */
    for (const pack of packs)
      for (const m of pack.maps || [])
        for (const ref of m.places || []) {
          const pl = ensurePlace(ref);
          if (pl && !pl.uses.some(u => u.role === 'map' && u.mapId === m.id)) pl.uses.push({ role: 'map', item: null, mapId: m.id, start: -Number.MAX_SAFE_INTEGER });
        }
    for (const pl of [...places.values()]) {
      const up = pl.parent ? ensurePlace(pl.parent) : null;
      pl.parentId = up && up !== pl ? up.id : null;
    }
    for (const pl of places.values()) {
      const path = [];
      const seen = new Set();
      for (let cur = pl; cur && !seen.has(cur.id); cur = cur.parentId ? places.get(cur.parentId) : null) {
        seen.add(cur.id);
        path.unshift(cur.id);
      }
      pl.path = path;
      pl.children = [];
    }
    for (const pl of places.values()) if (pl.parentId && places.get(pl.parentId) !== pl) places.get(pl.parentId).children.push(pl.id);
    for (const pl of places.values()) pl.uses.sort((a, b) => a.start - b.start);
    /* ② 성씨 */
    const surnames = new Map();
    const surnameByName = new Map();
    const addSurname = (x, auto) => {
      if (surnames.has(x.id)) return surnames.get(x.id);
      const o = { id: x.id, uid: `surname:${x.id}`, itemKind: 'surname', name: x.name || x.id, names: Array.isArray(x.names) ? x.names : [], description: x.description || '', wiki: x.wiki || '', packId: x.packId || '', packName: x.packName || '', auto: !!auto, houses: [] };
      surnames.set(o.id, o);
      if (!surnameByName.has(o.name)) surnameByName.set(o.name, o);
      return o;
    };
    for (const pack of packs) for (const x of pack.surnames || []) addSurname(Object.assign({ packId: pack.id, packName: pack.name }, x));
    for (const h of model.houses || []) {
      const r = t(h.surname);
      if (!r) continue;
      const sn = surnames.get(r) || surnameByName.get(r) || addSurname({ id: `sn-${HT.hash(r)}`, name: r }, true);
      h.surnameId = sn.id;
      sn.houses.push(h.id);
    }
    /* 문서: 사전의 wiki → "place:id" · "surname:id" (DLC의 documents · 내 글이 먼저) */
    for (const x of [...places.values(), ...surnames.values()]) {
      if (x.wiki && !docs.has(x.uid)) docs.set(x.uid, { text: x.wiki, packId: x.packId, packName: x.packName });
      const d = docs.get(x.uid);
      if (d) x.wiki = d.text;
    }
    model.places = [...places.values()];
    model.placeMap = places;
    model.placeByName = placeByName;
    model.surnames = [...surnames.values()];
    model.surnameMap = surnames;

    /* ③ 사람 — 열쇠: 인물 "f:uid" · 칸 "c:정권 uid|leader:3" · 이름 "n:글" · 미상 "u:n". 같은 사람의 열쇠는 하나로 묶습니다(뿌리 — 인물이 있으면 인물) */
    const up = new Map();
    const root = k => {
      let r = k;
      for (let nx = up.get(r); nx !== undefined && nx !== r; nx = up.get(r)) r = nx;
      /* 길 줄이기 (D1 6-3 ④): 지나온 열쇠를 모두 뿌리에 바로 잇습니다 — 같은 사람의 칸이 많아도 찾기가 길어지지 않게 */
      for (let k2 = k, nx = up.get(k2); k2 !== r && nx !== r; k2 = nx, nx = up.get(k2)) up.set(k2, r);
      return r;
    };
    /** a를 b(가리킨 쪽)에 묶습니다 — 뿌리는 b, 다만 인물이 있으면 인물 */
    const join = (a, b) => {
      const ra = root(a);
      const rb = root(b);
      if (ra === rb) return;
      if (ra.startsWith('f:') && !rb.startsWith('f:')) up.set(rb, ra);
      else up.set(ra, rb);
    };
    const figByUid = new Map(figures.map(f => [f.uid, f]));
    const figById = new Map(); // 다른 DLC의 인물 id(같은 팩에 없을 때) — 참조마다 인물 전체를 훑지 않게 (D1 6-3 ①) · 같은 id면 앞의 인물
    for (const f of figures) if (!figById.has(f.id)) figById.set(f.id, f);
    /** 이름이 '미상'인 계보 전용 인물 = 이름 미상의 사람(D1 2-4 다): 빈 고리 하나에 부모 · 자식을 둘 수 있고, 이름으로는 찾지 않습니다(자식은 그 인물의 id로 가리킴) */
    const unknownFigure = f => f.lineageOnly === true && HT.isUnknownWho(f.name);
    const figByName = new Map();
    const byNameAdd = (n, f) => {
      if (!n) return;
      const l = figByName.get(n);
      if (l) l.push(f);
      else figByName.set(n, [f]);
    };
    for (const f of figures) {
      if (unknownFigure(f)) continue;
      byNameAdd(f.name, f);
      if (f.aka) for (const n of f.aka) byNameAdd(n, f);
      if (f.names) for (const x of f.names) byNameAdd(x.text, f);
    }
    /* 날짜가 없는 사람(계보 전용 — spanMin null)은 어느 시기와도 겹치지 않습니다 (null <= b가 참이 되어 기원전 칸과도 겹친다고 나오지 않게 — D1 6-3 ⑤) */
    const overlaps = (f, a, b) => f.spanMin != null && f.spanMax != null && f.spanMin <= b && a <= f.spanMax + 1;
    /** 같은 이름의 인물이 여럿이고 고를 근거(같은 트랙 · 그때 살아 있음)도 같으면 고르지 않습니다 — 부르는 쪽이 알리고 그 이름의 자리로(지도자 이름과 같은 규칙) */
    const AMBIGUOUS = { ambiguous: true };
    const ambiguousMsg = s => `"${s}"은(는) 같은 이름의 인물이 여럿이라 고를 수 없습니다 — 인물 id로 적습니다.`;
    const findFigure = (ref, ctx) => {
      const r = t(ref);
      if (!r) return null;
      const byId = figByUid.get(r.includes('/') ? r : `${ctx.packId}/${r}`) || figById.get(r);
      if (byId) return byId;
      const hit = [...new Set(figByName.get(r) || [])];
      if (hit.length < 2) return hit[0] || null;
      const score = f => (f.track === ctx.track ? 10 : 0) + (ctx.start != null && overlaps(f, ctx.start, ctx.start) ? 5 : 0);
      const best = Math.max(...hit.map(score));
      const top = hit.filter(f => score(f) === best);
      return top.length === 1 ? top[0] : AMBIGUOUS;
    };
    const cellKey = (p, ref) => `c:${p.uid}|${ref}`;
    const leaderNames = c => [c.name, c.temple, c.title, c.given].filter(Boolean);
    const politiesIn = (name, track) => {
      const ok = q => q.itemKind === 'period' && (q.name === name || q.id === name || q.uid === name);
      const same = periods.filter(q => q.track === track && ok(q));
      return same.length ? same : periods.filter(ok);
    };
    /** 지도자 칸 참조 { track?, polity, leader, start? } → { p, i, kind, c } (없으면 null) — 시작 해를 적었으면 그해에 시작한 칸, 아니면 첫 칸 */
    const findCellRef = (ref, ctx) => {
      for (const p of politiesIn(ref.polity, ref.track || ctx.track)) {
        for (const [kind, list] of [['leader', p.leaders || []], ['cabinet', p.cabinets || []]]) {
          const cands = list.map((c, i) => ({ p, i, kind, c })).filter(x => (kind === 'leader' ? leaderNames(x.c) : [x.c.name]).includes(ref.leader));
          if (!cands.length) continue;
          if (ref.start == null) return cands[0];
          const y = Math.floor(ref.start + 1e-9);
          return cands.find(x => Math.floor(x.c.start + 1e-9) === y) || cands.reduce((a, b) => (Math.abs(b.c.start - ref.start) < Math.abs(a.c.start - ref.start) ? b : a));
        }
      }
      return null;
    };
    /* 모든 지도자 칸 · 사람을 적은 내각 칸 */
    const cells = [];
    for (const p of periods) {
      if (HT.itemKindOf(p) !== 'period') continue;
      (p.leaders || []).forEach((c, i) => cells.push({ p, kind: 'leader', i, ref: `leader:${i}`, c }));
      (p.cabinets || []).forEach((c, i) => c.person && cells.push({ p, kind: 'cabinet', i, ref: `cabinet:${i}`, c }));
    }
    /* 인물의 사람 열쇠 'f:uid'는 한 번만 지어 같은 글을 씁니다(만 명 계보에서 같은 글을 거듭 이어 붙여 표를 찾지 않게) */
    const fkOf = new Map();
    for (const f of figures) fkOf.set(f, `f:${f.uid}`);
    const fk = f => fkOf.get(f) || `f:${f.uid}`;
    for (const f of figures) up.set(fk(f), fk(f));
    const named = new Set(); // 칸의 person에 적힌 이름(인물이 없는 사람의 이름표)
    for (const x of cells) {
      const k = cellKey(x.p, x.ref);
      if (!up.has(k)) up.set(k, k);
      const ctx = { packId: x.p.packId, track: x.p.track, start: x.c.start };
      const r = x.c.person;
      if (r && typeof r === 'object') {
        const hit = findCellRef(r, ctx);
        if (hit && !(hit.p === x.p && hit.ref === x.ref)) join(k, cellKey(hit.p, `${hit.kind}:${hit.i}`));
        else if (!hit) warnAt(x.p, `${x.p.name} ${x.kind === 'leader' ? '지도자' : '내각'} "${x.c.name}"의 사람 "${HT.personRefText(r)}"을(를) 찾지 못했습니다.`);
      } else if (r) {
        const f = findFigure(r, ctx);
        if (f === AMBIGUOUS) warnAt(x.p, `${x.p.name} ${x.kind === 'leader' ? '지도자' : '내각'} "${x.c.name}"의 사람 ${ambiguousMsg(t(r))}`);
        if (f && f !== AMBIGUOUS) join(k, fk(f));
        else {
          named.add(t(r));
          join(k, `n:${t(r)}`);
        }
      } else if (x.kind === 'leader') {
        /* 적지 않았으면 같은 이름의 인물과 저절로 (연표의 '같은 이름의 인물' 규칙) */
        const end = x.c.end ?? x.p.endY;
        const f = leaderNames(x.c).flatMap(n => figByName.get(n) || []).find(f => f.lineageOnly !== true && overlaps(f, x.c.start, end) && (f.track === x.p.track || (f.services || []).some(s => s.polity === x.p))); // 계보 전용 인물은 저절로 잇지 않음 — person이나 칸 참조로만 (D1 2-4 나)
        if (f) join(k, fk(f));
      }
    }
    let useq = 0;
    const nodes = new Map();
    const nodeOf = key => {
      const r = root(key);
      let n = nodes.get(r);
      if (!n) {
        n = { key: r, name: '', figure: null, figures: [], cells: [], parents: [], spouses: [], children: [], groups: [], houseId: null, unknown: r.startsWith('u:'), missing: false };
        nodes.set(r, n);
      }
      return n;
    };
    for (const f of figures) {
      const n = nodeOf(fk(f));
      n.figures.push(f);
      if (!n.figure) n.figure = f;
      if (unknownFigure(f)) n.unknown = true;
    }
    for (const x of cells) nodeOf(cellKey(x.p, x.ref)).cells.push(x);
    for (const nm of named) nodeOf(`n:${nm}`);
    /* 이름으로 가리킨 사람(who · from): 인물 → 칸의 person 이름 → 지도자 칸의 이름(같은 나라 → 같은 트랙 → 모두에서 하나뿐일 때) → 못 찾으면 그 이름의 자리(missing) */
    const leaderByName = new Map();
    for (const x of cells) if (x.kind === 'leader') for (const n of leaderNames(x.c)) (leaderByName.get(n) || leaderByName.set(n, []).get(n)).push(x);
    const resolve = (r, ctx, what) => {
      if (r && typeof r === 'object') {
        const hit = findCellRef(r, ctx);
        if (hit) return nodeOf(cellKey(hit.p, `${hit.kind}:${hit.i}`));
        warnAt(ctx.item, `${ctx.label}의 ${what} "${HT.personRefText(r)}"을(를) 찾지 못했습니다.`);
        const n = nodeOf(`n:${HT.personRefText(r)}`);
        n.missing = true;
        return n;
      }
      const s = t(r);
      if (!s) return null;
      const f = findFigure(s, ctx);
      if (f === AMBIGUOUS) {
        warnAt(ctx.item, `${ctx.label}의 ${what} ${ambiguousMsg(s)}`);
        const n = nodeOf(`n:${s}`);
        if (!named.has(s)) n.missing = true;
        return n;
      }
      const ls = leaderByName.get(s) || [];
      const one = l => new Set(l.map(x => root(cellKey(x.p, x.ref)))).size === 1; // 같은 사람의 칸 여럿(다시 오른 지도자 · 두 나라)은 하나
      if (f) {
        /* 같은 나라 지도자가 다른 시대의 같은 이름 인물보다 먼저(고려 충렬왕의 부모 '원종' — 조선 추존 원종 인물이 아니라 고려 원종):
           찾은 인물이 그 지도자와 같은 사람이 아니고, 이 나라를 섬긴 적도 이 나라가 있던 때 살았던 적도 없으면 이 나라의 지도자 */
        const own = ctx.polity ? ls.filter(x => x.p === ctx.polity) : [];
        const fits = (f.services || []).some(v => v.polity === ctx.polity) || overlaps(f, ctx.polity && ctx.polity.start, ctx.polity && ctx.polity.endY);
        if (own.length && one(own) && root(cellKey(own[0].p, own[0].ref)) !== root(fk(f)) && !fits) return nodeOf(cellKey(own[0].p, own[0].ref));
        return nodeOf(fk(f));
      }
      if (named.has(s)) return nodeOf(`n:${s}`);
      /* 같은 이름의 지도자가 여럿이면(고려 현종 · 조선 현종) 이 사람의 생몰(지도자 칸이면 그 칸의 기간)과 가까운 때 다스린 지도자만 — 칸의 기간이 [시작 − 80, 끝]에 걸침 */
      const near = l => (ctx.lo == null ? [] : l.filter(x => x.c.start != null && x.c.start <= ctx.hi && ctx.lo - 80 <= (x.c.end ?? x.p.endY ?? x.c.start)));
      const pick = [ls.filter(x => x.p === ctx.polity), ls.filter(x => x.p.track === ctx.track), ls, near(ls.filter(x => x.p.track === ctx.track)), near(ls)].find(l => l.length && one(l));
      if (pick) return nodeOf(cellKey(pick[0].p, pick[0].ref));
      if (ls.length > 1) warnAt(ctx.item, `${ctx.label}의 ${what} "${s}"은(는) 같은 이름의 지도자가 여럿이라 고를 수 없습니다 — "나라:지도자@시작 해"로 적습니다.`);
      else warnAt(ctx.item, `${ctx.label}의 ${what} "${s}"을(를) 찾지 못했습니다 — 인물이나 지도자 칸의 이름으로 적습니다(그 이름의 자리를 만들어 둡니다).`);
      const n = nodeOf(`n:${s}`);
      n.missing = true;
      return n;
    };
    const unknownNode = () => nodeOf(`u:${useq++}`);
    /* 단체의 구성원(형식 3 — groups[].people, F2와 잇기): 위와 같은 찾기(인물 → 칸의 person 이름 → 지도자 칸 — 같은 나라 → 같은 트랙 → 하나뿐일 때)로 사람 자리에.
       구성원은 인물로 적지 않은 이름도 흔해, 글로 적은 이름을 못 찾으면 자리를 만들지 않고 글로만 둡니다(경고 없음). 지도자 칸 참조를 못 찾으면 단체의 '확인할 것'에.
       사람 자리에는 속한 단체(groups)를 — 인물 창 · 지도자 칸 창이 씀 */
    const memberNode = (r, ctx) => {
      if (r && typeof r === 'object') {
        const hit = findCellRef(r, ctx);
        return hit ? nodeOf(cellKey(hit.p, `${hit.kind}:${hit.i}`)) : null;
      }
      const s = t(r);
      if (!s) return null;
      const f = findFigure(s, ctx);
      if (f === AMBIGUOUS) return null; // 단체 창이 '확인할 것'에 알림(figureByRef)
      if (f) return nodeOf(fk(f));
      if (named.has(s)) return nodeOf(`n:${s}`);
      const ls = leaderByName.get(s) || [];
      const one = l => new Set(l.map(x => root(cellKey(x.p, x.ref)))).size === 1;
      const pick = [ls.filter(x => x.p === ctx.polity), ls.filter(x => x.p.track === ctx.track), ls].find(l => l.length && one(l));
      return pick ? nodeOf(cellKey(pick[0].p, pick[0].ref)) : null;
    };
    for (const g of model.groups || []) {
      const ctx = { packId: g.packId, track: g.track, polity: ((g.withinList || []).find(w => w.polity) || {}).polity || null, start: g.start };
      for (const row of g.peopleList || []) {
        const n = row.figure ? nodeOf(fk(row.figure)) : row.ambiguous ? null : memberNode(row.ref, ctx);
        if (!n) {
          if (row.ref && typeof row.ref === 'object') (g.warnings || (g.warnings = [])).push(`구성원 "${row.name}"을(를) 연표의 지도자 칸에서 찾지 못했습니다 — "나라:지도자@시작 해"로 적습니다.`);
          continue;
        }
        row.person = n;
        if (!row.figure && n.figure) Object.assign(row, { figure: n.figure, uid: n.figure.uid });
        if (!n.groups.includes(g)) n.groups.push(g);
      }
    }
    /* 혈연: 인물의 parents · spouses와 지도자 칸의 parents · spouses — 같은 사람의 것은 한데 모읍니다(같은 부모를 두 번 적었으면 하나로) */
    const sources = figures.filter(f => (f.parents || []).length || (f.spouses || []).length).map(f => ({ node: nodeOf(fk(f)), x: f, ctx: { packId: f.packId, track: f.track, start: f.start, lo: f.spanMin, hi: f.spanMax ?? f.spanMin, item: f, label: `인물 "${f.name}"` } })); // lo · hi: 생몰(활동) — 같은 이름의 지도자가 여럿일 때 고르는 근거(resolve의 near)
    for (const x of cells) if ((x.c.parents || []).length || (x.c.spouses || []).length) sources.push({ node: nodeOf(cellKey(x.p, x.ref)), x: x.c, ctx: { packId: x.p.packId, track: x.p.track, polity: x.p, start: x.c.start, lo: x.c.start, hi: x.c.end ?? x.p.endY ?? x.c.start, item: x.p, label: `${x.p.name} 지도자 "${x.c.name}"` } });
    for (const { node, x, ctx } of sources) {
      for (const q of x.parents || []) {
        const who = q.whoUnknown ? unknownNode() : resolve(q.who, ctx, '부모');
        if (!who) continue;
        if (who === node) {
          warnAt(ctx.item, `${ctx.label}의 부모가 자기 자신입니다 — 뺐습니다.`);
          continue;
        }
        if (!who.unknown && node.parents.some(e => e.node === who && (e.as || '') === (q.as || ''))) continue;
        const e = { node: who, as: q.as || '', gen: q.gen || null, certainty: q.certainty || '', note: q.note || '' };
        node.parents.push(e);
        who.children.push({ node, as: e.as, gen: e.gen, certainty: e.certainty });
      }
      for (const q of x.spouses || []) {
        const who = q.whoUnknown ? unknownNode() : resolve(q.who, ctx, '배우자');
        if (!who || who === node || (!who.unknown && node.spouses.some(e => e.node === who))) continue;
        const span = { start: q.start ?? null, startAt: q.startAt || null, startUnknown: !!q.startUnknown, end: q.end ?? null, endAt: q.endAt || null, endUnknown: !!q.endUnknown, note: q.note || '' };
        node.spouses.push(Object.assign({ node: who }, span));
        who.spouses.push(Object.assign({ node }, span));
      }
    }
    /* 이름: 인물이 있으면 인물, 없으면 첫 칸 */
    for (const n of nodes.values()) {
      const c0 = n.cells[0];
      n.name = n.figure ? n.figure.name : c0 ? HT.leaderLabel(c0.c) : n.unknown ? '미상' : n.key.slice(2);
      n.cells.sort((a, b) => a.c.start - b.c.start);
    }
    /* 가문 (D1 확정 설계 2-4 라 · 마): 사람 자리의 가문(houseId)과 정한 길(houseHow — 'written' · 'founder' · 'inherit' · 'auto').
       ① 적은 가문(인물의 house · 칸에 적은 house) ② 파조 — 이 사람을 founderNode로 가진 가문(적은 가문이 없거나 그 파의 본가 길 위에 있으면 이김 · 가장 깊은 파)
       ③ 물려받기 — 부계 부모의 가문(양부 > 부 > 생부 > 구분 없음(하나뿐일 때) > 후손 — 모 쪽은 받지 않음) ④ 칸 짐작(왕조 · 국성).
       ②③은 혈연이 있을 때만 움직이므로(파조도 그 사람에게 부모나 자식이 있을 때만) 형식 1 · 2 파일의 가문 · 구성원 · 가문 창은 그대로입니다.
       칸의 houseId(띠의 가문 줄 · 풍선)는 바꾸지 않습니다. 짐작은 파일에 적지 않습니다 */
    const houseMap = model.houseMap || new Map();
    const nodeList = [...nodes.values()];
    nodeList.forEach((n, k) => {
      n.seq = k;
      n.houseId = null;
      n.houseHow = null;
    });
    /* 시조 · 파조: 가문의 founder 글을 사람 자리로 — 단체 구성원과 같은 경고 없는 찾기(인물 → 칸의 person 이름 → 지도자 칸: 같은 나라 → 같은 트랙 → 한 사람뿐일 때). 못 찾으면 글로만 */
    const founderOf = new Map(); // 사람 자리 → 그 사람을 파조로 둔 가장 깊은 가문
    for (const h of houseMap.values()) {
      const r = h.founder ? HT.readPersonRef(h.founder) : null;
      const home = (h.members.find(m => m.role === 'period') || {}).item || null;
      const n = r ? memberNode(r, { packId: h.packId, track: h.track || (home ? home.track : ''), polity: home, start: null }) : null;
      Object.defineProperty(h, 'founderNode', { value: n || null, configurable: true, writable: true, enumerable: false }); // 사람 자리(고리가 있는 객체라 열거하지 않음 — 가문 사본 · 내보내기에 섞이지 않게)
      if (!n || !(n.parents.length || n.children.length)) continue;
      const cur = founderOf.get(n);
      if (!cur || h.depth > cur.depth) founderOf.set(n, h);
    }
    const INHERIT = ['adoptive-father', 'father', 'birth-father', '', 'ancestor'];
    /** 물려받을 부모 줄 차례(양부 > 부 > 생부 > 구분 없음 하나뿐 > 후손) — 세계표 · 승계표의 뼈대 열쇠(kinKey)도 같은 차례 */
    const heirParents = n => {
      const plain = n.parents.filter(e => (e.as || '') === '').length;
      const out = [];
      for (const as of INHERIT) for (const e of n.parents) if ((e.as || '') === as && (as !== '' || plain === 1)) out.push(e.node);
      return out;
    };
    /* 부모부터(위상 차례로 한 번 — 고리는 가장 앞 사람에서 끊음) */
    const order = [];
    {
      const N = nodeList.length;
      const indeg = new Int32Array(N);
      for (const n of nodeList) indeg[n.seq] = n.parents.length;
      const done = new Uint8Array(N);
      const queue = [];
      for (const n of nodeList) if (!indeg[n.seq]) queue.push(n);
      let head = 0;
      let scan = 0;
      while (order.length < N) {
        if (head >= queue.length) {
          while (done[nodeList[scan].seq]) scan++; // 남은 것은 모두 고리 안 — 가장 앞 사람부터(그 사람의 남은 부모는 아직 셈하지 않은 채)
          queue.push(nodeList[scan]);
        }
        const n = queue[head++];
        if (done[n.seq]) continue;
        done[n.seq] = 1;
        order.push(n);
        for (const c of n.children) if (!done[c.node.seq] && --indeg[c.node.seq] === 0) queue.push(c.node);
      }
    }
    for (const n of order) {
      const hc = n.cells.find(x => x.c.houseId && !x.c.houseAuto);
      const written = (n.figure && n.figure.houseId) || (hc ? hc.c.houseId : null);
      const fh = founderOf.get(n) || null;
      if (fh && (!written || (fh.path || []).includes(written))) {
        n.houseId = fh.id;
        n.houseHow = 'founder';
      } else if (written) {
        n.houseId = written;
        n.houseHow = 'written';
      } else {
        const heir = heirParents(n).find(q => q.houseId);
        if (heir) {
          n.houseId = heir.houseId;
          n.houseHow = 'inherit';
        } else {
          const ac = n.cells.find(x => x.c.houseId);
          if (ac) {
            n.houseId = ac.c.houseId;
            n.houseHow = 'auto';
          }
        }
      }
      /* 뼈대 열쇠(kinKey — HT.kinSkeleton): 가문이 있으면 그 뿌리 가문 'kin:<id>', 없으면 지도자면 첫 칸의 나라 'kin:polity:<uid>', 아니면 물려받는 부모의 것(없으면 '') */
      const h = n.houseId ? houseMap.get(n.houseId) : null;
      if (h) n.kinKey = `kin:${(h.path && h.path[0]) || h.id}`;
      else {
        const lc = n.cells.find(x => x.kind === 'leader');
        if (lc) n.kinKey = `kin:polity:${lc.p.uid}`;
        else {
          const heir = heirParents(n).find(q => q.kinKey);
          n.kinKey = heir ? heir.kinKey : '';
        }
      }
    }
    /* 가문의 사람 수 · 계보 전용 인물 수 (사람 자리의 가문으로 — 가문 창의 '계보 전용 인물 n명' · 세계표 단추) */
    for (const h of houseMap.values()) h.kinCount = h.lineageCount = 0;
    for (const n of nodeList) {
      const h = n.houseId ? houseMap.get(n.houseId) : null;
      if (!h) continue;
      h.kinCount++;
      if (n.figure && n.figure.lineageOnly === true) h.lineageCount++;
    }
    /* 가문 머리 값의 짐작 (D1 2-4 바 — 파일에 적지 않음): 구분(trackAuto) · 민족(peopleAuto) — 국성으로 삼은 나라 → 지도자 칸이 든 나라 → 사람 자리(구성원)의 트랙 → 본가의 값.
       후보가 여럿이면 가장 많은 것(같으면 이른 것) · 나머지 수는 trackMore · 어디서 짐작했는지는 trackFrom('period' · 'leader' · 'person' · 'parent').
       본관 · 성(seat · surname)은 본가 길에서 처음 만나는 것 — 물려받았으면 그 가문 id를 seatFrom · surnameFrom에 */
    {
      const personsOf = new Map();
      for (const n of nodeList) if (n.houseId) (personsOf.get(n.houseId) || personsOf.set(n.houseId, []).get(n.houseId)).push(n);
      const tally = list => {
        const m = new Map();
        for (const [v, t] of list) {
          if (!v) continue;
          const c = m.get(v);
          if (!c) m.set(v, { v, n: 1, t });
          else {
            c.n++;
            if (t < c.t) c.t = t;
          }
        }
        const all = [...m.values()].sort((a, b) => b.n - a.n || a.t - b.t);
        return all.length ? { value: all[0].v, more: all.length - 1 } : null;
      };
      const byDepth = [...houseMap.values()].sort((a, b) => a.depth - b.depth || a.seq - b.seq);
      for (const h of byDepth) {
        const nations = h.members.filter(m => m.role === 'period').map(m => m.item);
        const ruled = h.members.filter(m => m.role === 'leader').map(m => m.item);
        const parent = h.parentId ? houseMap.get(h.parentId) : null;
        let t = null;
        let from = '';
        let pe = null;
        let peFrom = '';
        if (nations.length) {
          t = tally(nations.map(p => [p.track, p.start]));
          pe = tally(nations.map(p => [p.people, p.start]));
          from = peFrom = 'period';
        } else if (ruled.length) {
          t = tally(ruled.map(p => [p.track, p.start]));
          pe = tally(ruled.map(p => [p.people, p.start]));
          from = peFrom = 'leader';
        } else {
          const ps = personsOf.get(h.id) || [];
          t = tally(ps.map(n => [n.figure ? n.figure.track : n.cells[0] ? n.cells[0].p.track : '', n.seq]));
          from = t ? 'person' : '';
        }
        if (!t && parent) {
          const v = parent.track || parent.trackAuto;
          t = v ? { value: v, more: 0 } : null;
          from = t ? 'parent' : '';
        }
        if (!pe && parent && (parent.people || parent.peopleAuto)) {
          pe = { value: parent.people || parent.peopleAuto, more: 0 };
          peFrom = 'parent';
        }
        h.trackAuto = !h.track && t ? t.value : '';
        h.trackFrom = h.trackAuto ? from : '';
        h.trackMore = h.trackAuto ? t.more : 0;
        h.peopleAuto = !h.people && pe ? pe.value : '';
        h.peopleFrom = h.peopleAuto ? peFrom : '';
        h.seatFrom = '';
        h.surnameFrom = '';
        for (const id of (h.path || [h.id]).slice(0, -1).reverse()) {
          const a = houseMap.get(id);
          if (!a) continue;
          if (!h.seat && !h.seatFrom && a.seat) h.seatFrom = a.id;
          if (!h.surname && !h.surnameFrom && a.surname) h.surnameFrom = a.id;
        }
      }
    }
    /* 부모 고리(누가 자기 조상) — 한 번씩 알림 */
    {
      /* 되부름 대신 손수 쌓는 더미로 (몇천 대의 긴 계보에서 호출 더미가 넘치지 않게) — 차례 · 알림은 되부름과 같음 */
      const state = new Map();
      for (const first of nodes.values()) {
        if (state.has(first)) continue;
        state.set(first, 1);
        const stack = [[first, 0]];
        while (stack.length) {
          const top = stack[stack.length - 1];
          const n = top[0];
          if (top[1] >= n.parents.length) {
            state.set(n, 2);
            stack.pop();
            continue;
          }
          const e = n.parents[top[1]++];
          const s = state.get(e.node);
          if (s === 1) {
            const src = n.figure || (n.cells[0] && n.cells[0].p);
            if (src) warnAt(src, `${n.name}의 부모 · 조상을 따라가면 다시 ${n.name}(으)로 돌아옵니다 — 혈연이 고리를 이룹니다.`);
          } else if (!s) {
            state.set(e.node, 1);
            stack.push([e.node, 0]);
          }
        }
      }
    }
    const index = new Map();
    for (const k of [...up.keys()]) {
      const n = nodes.get(root(k));
      if (n) index.set(k, n);
    }
    for (const n of nodes.values()) index.set(n.key, n);
    /* ④ 자리 이음: 적은 from을 풀고(accessionFrom — 칸 열쇠 → 사람), 관계(kin)를 혈연과 견줍니다. from을 비우면 바로 앞 칸의 사람 */
    const accessionFrom = new Map();
    const BIO = ['', 'father', 'mother', 'birth-father', 'birth-mother', 'adoptive-father', 'adoptive-mother'];
    const knownParents = n => (n ? n.parents.filter(e => !e.node.unknown && !e.node.missing && BIO.includes(e.as || '')) : []); // 찾지 못한 이름(missing)은 견줄 혈연이 아님
    const kinCheck = (kin, cur, pred) => {
      const cp = knownParents(cur);
      const pp = knownParents(pred);
      switch (kin) {
        case 'son':
        case 'daughter':
          return cp.length && !cp.some(e => e.node === pred) ? '부모에 앞 지도자가 없습니다' : '';
        case 'adopted':
          return cp.length && !cp.some(e => e.node === pred && /^adoptive-/.test(e.as)) ? '양부 · 양모에 앞 지도자가 없습니다' : '';
        case 'grandson':
        case 'granddaughter':
        case 'maternal-grandson':
          return cp.length && cp.every(e => knownParents(e.node).length) && !cp.some(e => knownParents(e.node).some(g => g.node === pred)) ? '조부모에 앞 지도자가 없습니다' : '';
        case 'younger-brother':
        case 'elder-brother':
        case 'sister':
          return cp.length && pp.length && !cp.some(e => pp.some(g => g.node === e.node)) ? '앞 지도자와 같은 부모가 없습니다' : '';
        case 'nephew':
          return cp.length && pp.length && cp.every(e => knownParents(e.node).length) && !cp.some(e => knownParents(e.node).some(g => pp.some(h => h.node === g.node))) ? '부모가 앞 지도자의 형제가 아닙니다' : '';
        case 'father':
        case 'mother':
          return pp.length && !pp.some(e => e.node === cur) ? '앞 지도자의 부모에 이 사람이 없습니다' : '';
        case 'spouse':
          return pred.spouses.length && !pred.spouses.some(e => e.node === cur) ? '앞 지도자의 배우자에 이 사람이 없습니다' : '';
        case 'self':
          return cur !== pred ? '앞 지도자와 다른 사람입니다' : '';
        case 'unrelated':
          return cp.some(e => e.node === pred) || pp.some(e => e.node === cur) ? '혈연에는 부모 · 자식으로 적혀 있습니다' : '';
        default:
          return '';
      }
    };
    for (const p of periods) {
      if (HT.itemKindOf(p) !== 'period' || !(p.leaders || []).some(c => c.accession)) continue;
      p.leaders.forEach((c, i) => {
        const a = c.accession;
        if (!a) return;
        const label = `${p.name} 지도자 "${c.name}"`;
        const cur = index.get(cellKey(p, `leader:${i}`)) || null;
        let pred = null;
        if (a.from) {
          pred = resolve(a.from, { packId: p.packId, track: p.track, polity: p, start: c.start, lo: c.start, hi: c.end ?? p.endY ?? c.start, item: p, label }, '앞 지도자');
          if (pred) accessionFrom.set(cellKey(p, `leader:${i}`), pred);
        } else if (!a.fromUnknown && i > 0) pred = index.get(cellKey(p, `leader:${i - 1}`)) || null;
        if (a.kin && pred && cur && !pred.unknown) {
          const why = kinCheck(a.kin, cur, pred);
          if (why) warnAt(p, `${label}: 자리 이음의 관계는 '${HT.kinName(a.kin)}'인데 혈연과 어긋납니다 — ${why}.`);
        }
        if (a.kin && a.kin !== 'self' && cur && pred === cur) warnAt(p, `${label}: 앞 지도자가 같은 사람인데 관계가 '${HT.kinName(a.kin)}'입니다 — 다시 올랐으면 관계를 '본인'으로 적습니다.`);
      });
    }
    model.persons = [...nodes.values()];
    model.personIndex = index;
    model.accessionFrom = accessionFrom;
    model.peopleWarnings = warnings;
    return model;
  };
  /** 칸(정권 · 칸 참조 'leader:3')이나 인물의 사람 자리 (형식 버전 3 — 모델의 personIndex). 없으면 null */
  HT.personOf = (model, x, ref = null) => (model && model.personIndex && x ? model.personIndex.get(ref ? `c:${x.uid}|${ref}` : `f:${x.uid}`) || null : null);
  /** 지명 참조(이름이나 id) → 모델의 지명 (없으면 null) */
  HT.placeOf = (model, ref) => {
    const r = String(ref ?? '').trim();
    return r && model && model.placeMap ? model.placeMap.get(r) || model.placeByName.get(r) || null : null;
  };
  /** 사람 자리가 다스린 칸들의 한 줄 글 ("갑 왕국 3대 · 을 나라") */
  const personRuled = n => (n ? n.cells.filter(x => x.kind === 'leader').map(x => ({ polity: x.p, uid: x.p.uid, name: x.p.name, ref: x.ref, i: x.i, ordinal: x.c.ordinal ?? null, color: x.p.color, start: x.c.start })) : []);
  /** 동군연합(건의 8의 6-다 · 2026-10-14 감독 "이음줄 진행"): 같은 사람이 **같은 때 두 나라의 지도자**인 겹침마다 하나 —
      칸의 person 참조로 묶인 지도자 칸(HT.personOf)끼리, 연표에 그려진 구간(HT.cellSpan)이 겹치는 두 나라의 짝. 같은 나라의 두 칸(복위)과
      맞닿기만 한 칸(앞 나라를 그만둔 해에 다른 나라에 오름)은 뺍니다. a · b는 정권 uid 차례 · key는 그 짝의 열쇠(연표 · 내보내기 공용).
      → [{ key, name, s, e, mid, a: { p, i, ref }, b: { p, i, ref } }] (모델마다 한 번 셈해 둡니다) */
  /* 서고 미리보기의 형식 4 모델(리메이크 5단계 과제 9 · 계획 정한 것 #3): 메이커만 — viewer가 timeline의 setData에 f4로 넘기고 서고 갈래(timeline.js _sphereF4 · _drawSphereRows · _drawF4Threads)가 덧그린다.
     모델(buildModel)과 작업본(옛 꼴 — 과제 3 · 4 · 6이 지키는 칸)에서 셈하는 자료:
     persons: 왕관이 둘 이상인 사람(지도자 칸의 person이 한 사람으로 이어진 객체가 둘 이상) [{ name, start, end, crowns: [{ uid, i }] }] — 때는 그 칸들의 가장 이른 시작 ~ 가장 늦은 끝
     borrows: { [객체 uid]: { leader?: { from(출처 글 — 객체 이름/직위), name }, cabinet?: … } } · powers: { [빼앗긴 객체 uid]: [{ start, end, name, holder: { uid, name, color } }] }
     sphereRows: { [문화권 id]: { epochs: [{ name, start, end }], cycle: { names, start, label } | { era, from, step, label } | null } }.
     내보내기 · 조감은 f4를 받지 않으므로 배치가 바이트까지 같다. 내보내기 모듈에 들지 않는 뷰어용 셈 */
  /** 사람 띠(세계사 장면 1 · 설계 3-11 ①): 왕관(지도자 칸의 person 이음)이 둘 이상의 객체에 있는 사람마다
      { name, start, end(그 칸들의 가장 이른 시작 ~ 가장 늦은 끝), crowns: [{ uid, i }], figure(인물 uid · 없으면 ''), sphere(왕관 트랙들의 문화권 가운데 차례가 가장 앞 · 없으면 '') }.
      서고 미리보기(HT.f4Preview)와 새 앱 내보내기(export/persons.mjs — 리메이크 3단계)가 같은 셈을 쓴다 */
  HT.personBands = model => {
    const out = [];
    if (!model) return out;
    const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);
    const trackSphere = new Map((model.tracks || []).map(t => [t.id, t.sphere || '']));
    for (const n of model.persons || []) {
      const cells = (n && n.cells ? n.cells : []).filter(q => q && q.kind === 'leader' && q.p && q.c);
      if (new Set(cells.map(q => q.p.uid)).size < 2) continue;
      let a = Infinity, b = -Infinity;
      for (const q of cells) {
        const sp = HT.cellSpan(q.c, q.p, q.ref);
        if (num(sp.start) != null) a = Math.min(a, sp.start);
        const e = num(sp.end) != null ? sp.end : num(q.p.endY);
        if (e != null) b = Math.max(b, e);
      }
      if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) continue;
      let sphere = '';
      for (const q of cells) {
        const sp = trackSphere.get(q.p.track) || '';
        if (sp && (!sphere || HT.sphereOrder(sp) < HT.sphereOrder(sphere))) sphere = sp;
      }
      out.push({ name: n.name || '', start: a, end: b, crowns: cells.map(q => ({ uid: q.p.uid, i: q.i })), figure: (n.figure && n.figure.uid) || '', sphere });
    }
    return out;
  };
  HT.f4Preview = (model, draft) => {
    const out = { persons: [], borrows: {}, powers: {}, sphereRows: {} };
    if (!model) return out;
    out.persons = HT.personBands(model);
    if (!draft || typeof draft !== 'object') return out;
    const pid = draft.id;
    const periods = (Array.isArray(draft.periods) ? draft.periods : []).filter(p => p && typeof p === 'object');
    const uidOf = p => `${pid}/${p.id}`;
    const find = ref => {
      const s = String(ref ?? '').trim();
      return s ? periods.find(p => p.id === s) || periods.find(p => p.name === s) || null : null;
    };
    const fromText = ref => {
      const s = String(ref ?? '').trim();
      const cut = s.indexOf('/');
      const key = cut >= 0 ? s.slice(0, cut).trim() : s;
      const office = cut >= 0 ? s.slice(cut + 1).trim() : '';
      const src = find(key);
      return `${src ? src.name : key}${office ? `/${office}` : ''}`;
    };
    const year = (v, at) => {
      const d = v == null || v === '' ? null : HT.readDate(v, at);
      return d && Number.isFinite(d.t) ? d.t : null;
    };
    for (const p of periods) {
      const b = {};
      for (const [k, slot, word] of [['leadersFrom', 'leader', '지도자'], ['cabinetsFrom', 'cabinet', '내각']]) {
        const v = p[k];
        const from = v && typeof v === 'object' ? v.from : typeof v === 'string' ? v : '';
        if (!from) continue;
        b[slot] = { from: fromText(from), name: (v && typeof v === 'object' && v.name) || word };
      }
      if (Object.keys(b).length) out.borrows[uidOf(p)] = b;
      const holder = model.byUid ? model.byUid.get(uidOf(p)) : null;
      for (const w of Array.isArray(p.power) ? p.power : []) {
        if (!w || typeof w !== 'object') continue;
        const target = find(w.over);
        if (!target || target === p) continue;
        (out.powers[uidOf(target)] = out.powers[uidOf(target)] || []).push({ start: year(w.start, w.startAt), end: year(w.end, w.endAt), name: w.name || p.name, holder: { uid: uidOf(p), name: p.name, color: (holder && holder.color) || p.color || '' } });
      }
    }
    const rowOf = id => (out.sphereRows[id] = out.sphereRows[id] || { epochs: [], cycle: null });
    for (const e of Array.isArray(draft.epochs) ? draft.epochs : []) {
      if (!e || typeof e !== 'object' || !e.sphere) continue;
      rowOf(e.sphere).epochs.push({ name: e.name || '', start: year(e.start, e.startAt), end: year(e.end, e.endAt) });
    }
    for (const c of Array.isArray(draft.yearCycles) ? draft.yearCycles : []) {
      if (!c || typeof c !== 'object' || !c.sphere) continue;
      const row = rowOf(c.sphere);
      if (row.cycle) continue;
      if (Array.isArray(c.names) && c.names.length) row.cycle = { names: c.names.map(String), start: Number(c.start) || 0, label: c.label || '' };
      else if (c.era) row.cycle = { era: String(c.era), from: Number(c.from) || 0, step: Math.max(1, Number(c.step) || 1), label: c.label || String(c.era) };
    }
    return out;
  };
  HT.unionPairs = model => {
    if (!model || !model.personIndex) return [];
    if (model._unionPairs) return model._unionPairs;
    const out = [];
    for (const n of new Set(model.personIndex.values())) {
      const cells = ((n && n.cells) || []).filter(q => q.kind === 'leader' && q.p && q.c);
      for (let x = 0; x < cells.length; x++)
        for (let y = x + 1; y < cells.length; y++) {
          let A = cells[x], B = cells[y];
          if (A.p === B.p) continue;
          const sa = HT.cellSpan(A.c, A.p, A.ref), sb = HT.cellSpan(B.c, B.p, B.ref);
          const s = Math.max(sa.start, sb.start), e = Math.min(sa.end ?? A.p.endY, sb.end ?? B.p.endY);
          if (!(e > s)) continue;
          if (A.p.uid > B.p.uid) [A, B] = [B, A];
          out.push({ key: `${A.p.uid}|${A.ref}|${B.p.uid}|${B.ref}`, name: n.name || '', s, e, mid: (s + e) / 2, a: { p: A.p, i: A.i, ref: A.ref }, b: { p: B.p, i: B.i, ref: B.ref } });
        }
    }
    model._unionPairs = out;
    return out;
  };
  /**
   * 한 나라의 자리 이음 표 자료 (구상 문서 3-1의 표 창 — 그림은 아직, 자료만): 지도자를 시작 순으로, 칸마다 사람과 자리 이음.
   * polity = 모델의 정권 항목이나 uid · 이름 · id → { polity, rulers: [{ i, ref, cell, name, start, end, ordinal, person, restored, elsewhere,
   *   accession: { kin, kinName, kinUnknown, how, howName, howUnknown, from(사람), fromRuler(그 나라의 앞 칸 번호 — 바로 앞이면 i - 1), fromAuto(비워서 바로 앞 칸), fromUnknown, note } }] }
   * restored = 이 사람이 이 나라에서 앞서 다스린 적이 있음(다시 오름) · elsewhere = 같은 사람이 다스린 다른 나라의 칸들. 없으면 null
   */
  HT.lineageOf = (model, polity) => {
    if (!model || !model.personIndex) return null;
    const p = polity && typeof polity === 'object' ? polity : model.byUid.get(polity) || model.periods.find(q => q.itemKind === 'period' && (q.name === polity || q.id === polity)) || null;
    if (!p || p.kind !== 'period') return null;
    const people = (p.leaders || []).map((c, i) => HT.personOf(model, p, `leader:${i}`));
    const rulers = (p.leaders || []).map((c, i) => {
      const person = people[i];
      const a = c.accession || {};
      const explicit = model.accessionFrom.get(`c:${p.uid}|leader:${i}`) || null;
      const from = a.fromUnknown ? null : explicit || (i > 0 ? people[i - 1] : null);
      const fromRuler = from ? (explicit ? people.findIndex((n, j) => j < i && n === from) : i - 1) : -1;
      return {
        i, ref: `leader:${i}`, cell: c, name: HT.leaderLabel(c), start: c.start, end: c.end ?? null, ordinal: c.ordinal ?? null, person,
        restored: !!person && people.slice(0, i).includes(person),
        elsewhere: personRuled(person).filter(r => r.polity !== p),
        accession: {
          kin: a.kin || '', kinName: a.kin ? HT.kinName(a.kin) : '', kinUnknown: !!a.kinUnknown,
          how: a.how || '', howName: a.how ? HT.accessionHowName(a.how) : '', howUnknown: !!a.howUnknown,
          from, fromRuler, fromAuto: !a.from && !a.fromUnknown && i > 0, fromUnknown: !!a.fromUnknown, note: a.note || '',
        },
      };
    });
    return { polity: p, rulers };
  };
  /**
   * 한 가문의 세계표 자료 (사람 · 선 목록 — 그리는 창은 계보 뼈대 HT.kinSkeleton을 씁니다): 가문의 사람(사람 자리의 가문 — linkPeople의 houseId)과 그 부모 · 자식 · 배우자(가문 밖 사람은 member: false).
   * → { house, nodes: [{ key, name, member, unknown, missing, generation(위에서부터 0 · 1 …), figureUid, houseId, ruled: [{ uid, name, ref, ordinal, color }] }],
   *     edges: [{ type: 'parent', from(부모 key), to(자식 key), as, gen(건너뛴 세대 — 후손), certainty } · { type: 'spouse', a, b, start, end, startUnknown, endUnknown }], warnings }. 없으면 null.
   * opts.branches = true면 아래 파(분가)의 사람까지 넣고, 노드에 branchId(그 사람의 파 — 본가 자신이면 null) · founderOf(이 사람을 파조로 둔 파 id)를 답니다.
   * 세대는 부모 → 자식 선을 따라 위상 차례로 한 번(가장 긴 길 — 후손은 적은 대수만큼) 셉니다. 고리는 끊고 warnings에 적습니다(고리가 없으면 예전과 같은 값 — D1 2-4 사)
   */
  HT.familyOf = (model, houseId, opts = {}) => {
    if (!model || !model.persons || !model.houseMap) return null;
    const h = model.houseMap.get(houseId) || (model.houses || []).find(x => x.name === houseId) || null;
    if (!h) return null;
    const under = opts.branches ? new Set(HT.houseUnder(model, h.id)) : new Set([h.id]);
    const members = model.persons.filter(n => under.has(n.houseId));
    const memberSet = new Set(members);
    const inSet = new Set(members);
    for (const n of members) for (const e of n.parents.concat(n.children, n.spouses)) inSet.add(e.node);
    const list = [...inSet];
    const edges = [];
    const seenSp = new Set();
    for (const n of list) {
      for (const e of n.parents) if (inSet.has(e.node)) edges.push({ type: 'parent', from: e.node.key, to: n.key, as: e.as, gen: e.gen || 1, certainty: e.certainty || '' });
      for (const e of n.spouses) {
        if (!inSet.has(e.node)) continue;
        const k = [n.key, e.node.key].sort().join('|');
        if (seenSp.has(k)) continue;
        seenSp.add(k);
        edges.push({ type: 'spouse', a: n.key, b: e.node.key, start: e.start, end: e.end, startUnknown: e.startUnknown, endUnknown: e.endUnknown });
      }
    }
    /* 세대: 위상 차례(부모가 먼저)로 한 번 — gen[자식] = 가장 큰 gen[부모] + 대수. 남은 것(고리 안)은 가장 앞 사람에서 끊고(그 사람으로 들어오는 남은 선을 셈하지 않음) 알립니다 */
    const at = new Map(list.map((n, k) => [n.key, k]));
    const byKey = new Map(list.map(n => [n.key, n]));
    const N = list.length;
    const gen = new Array(N).fill(0);
    const indeg = new Int32Array(N);
    const outs = list.map(() => []);
    for (const e of edges) {
      if (e.type !== 'parent') continue;
      indeg[at.get(e.to)]++;
      outs[at.get(e.from)].push(e);
    }
    const done = new Uint8Array(N);
    const warnings = [];
    const queue = [];
    for (let k = 0; k < N; k++) if (!indeg[k]) queue.push(k);
    let head = 0;
    let scan = 0;
    let count = 0;
    while (count < N) {
      if (head >= queue.length) {
        while (done[scan]) scan++;
        const n = list[scan];
        for (const e of n.parents) if (inSet.has(e.node) && !done[at.get(e.node.key)]) warnings.push(`${n.name}의 부모 ${e.node.name}: 혈연이 고리를 이뤄 세대를 셀 때 이 선을 끊었습니다.`);
        queue.push(scan);
      }
      const k = queue[head++];
      if (done[k]) continue;
      done[k] = 1;
      count++;
      for (const e of outs[k]) {
        const c = at.get(e.to);
        if (done[c]) continue;
        if (gen[k] + e.gen > gen[c]) gen[c] = gen[k] + e.gen;
        if (--indeg[c] === 0) queue.push(c);
      }
    }
    /* 배우자는 같은 세대로(부모가 적히지 않은 쪽을 맞춤) */
    const noParentIn = key => !byKey.get(key).parents.some(q => inSet.has(q.node));
    for (const e of edges)
      if (e.type === 'spouse') {
        const ga = gen[at.get(e.a)];
        const gb = gen[at.get(e.b)];
        const noA = noParentIn(e.a);
        const noB = noParentIn(e.b);
        if (noA && !noB) gen[at.get(e.a)] = gb;
        else if (noB && !noA) gen[at.get(e.b)] = ga;
      }
    const founderOf = new Map();
    if (opts.branches) for (const id of under) {
      const b = model.houseMap.get(id);
      if (b && b.founderNode && id !== h.id) founderOf.set(b.founderNode, id);
    }
    const nodes = list.map(n => {
      const o = { key: n.key, name: n.name, member: memberSet.has(n), unknown: n.unknown, missing: n.missing, generation: gen[at.get(n.key)], figureUid: n.figure ? n.figure.uid : null, houseId: n.houseId, ruled: personRuled(n).map(({ polity, ...r }) => r) };
      if (opts.branches) Object.assign(o, { branchId: n.houseId && n.houseId !== h.id && under.has(n.houseId) ? n.houseId : null, founderOf: founderOf.get(n) || null });
      return o;
    });
    nodes.sort((a, b) => a.generation - b.generation || (b.member ? 1 : 0) - (a.member ? 1 : 0));
    return { house: h, nodes, edges, warnings };
  };

  /* ---------- 승계표 · 세계표 · 가문 조명 (D1 — docs/설계-10건/1-2-…-확정.md 2-4 아 · 자, 3-3 · 3-4, 4-2 · 4-4 · 4-5, 5-3) ----------
   * 계보 뼈대(HT.kinSkeleton)는 승계표 · 세계표 · 내보내기(새 앱)가 함께 쓰는 하나입니다 — 가문마다(뿌리 가문) · 가문 없는 지도자의 나라마다 한 벌, 앞 차례(선순) 정수 배열.
   * 웹과 새 앱은 같은 뼈대 위에서 같은 정수 칸 셈(HT.kinLayout = Dart kinLayout)과 같은 줄 규칙(HT.successionRows = Dart kin_rows)을 씁니다.
   * 꼴의 빈 곳을 정한 기록: 같은 문서 끝 '구현 이음새 기록'의 D1-W1 절 */
  /** 나무 부모 차례: 생부 > 부 > 구분 없음 > 양부 > 후손 > 양모 > 생모 · 모 (표에 없는 자유 글은 맨 뒤) */
  const KIN_TREE_ORDER = ['birth-father', 'father', '', 'adoptive-father', 'ancestor', 'adoptive-mother', 'birth-mother', 'mother'];
  const kinTreeRank = as => {
    const k = KIN_TREE_ORDER.indexOf(as || '');
    return k < 0 ? KIN_TREE_ORDER.length : k;
  };
  /** 부계 쪽 부모(이름 미상의 빈 고리를 뼈대에 넣는 갈래 — 세대 수를 지킴) */
  const KIN_PATERNAL = new Set(['birth-father', 'father', '', 'adoptive-father', 'ancestor']);
  /** 선 갈래: 0 실선 · 1 짧은 파선(양부 · 양모) · 2 긴 파선(후손 — 몇 대 건너뜀) · 추정 · 전승이면 + 4(옅게) */
  const kinEdgeCode = e => (/^adoptive-/.test(e.as || '') ? 1 : e.as === 'ancestor' ? 2 : 0) + (e.certainty === 'estimated' || e.certainty === 'legend' ? 4 : 0);
  HT.KIN_BITS = { member: 1, unknown: 2, missing: 4, side: 8, founder: 16, leader: 32, lineage: 64, stub: 128, twoPolities: 256 };
  /* 모델마다 한 번 짓고 둡니다(메이커가 모델을 다시 지으면 함께 버려짐 — 창이 열려 있을 때만 다시 지음) */
  const kinCache = new WeakMap();
  const kinStore = model => {
    let c = kinCache.get(model);
    if (!c) kinCache.set(model, (c = { groups: null, skel: new Map(), succ: new Map() }));
    return c;
  };
  /* 계보 뼈대 짓기는 생성기 하나(kinBuild)로 — 동기(HT.kinSkeleton)는 끝까지 돌리고, 나눠 짓기(HT.kinSkeletonAsync)는 몇 ms마다 양보합니다(4-6 · 6-1 '50ms 넘는 장면 0').
     양보 자리는 무거운 고리 안에서 4096걸음마다(yield) — 동기로 돌릴 때는 거의 공짜 */
  const KIN_STEP = 4096;
  function* kinGroupsGen(model) {
    const c = kinStore(model);
    if (!c.groups) {
      const groups = new Map();
      let tick = 0;
      for (const n of model.persons || []) {
        if (n.kinKey) {
          const l = groups.get(n.kinKey);
          if (l) l.push(n);
          else groups.set(n.kinKey, [n]);
        }
        if (++tick === KIN_STEP) {
          tick = 0;
          yield;
        }
      }
      c.groups = groups;
    }
    return c.groups;
  }
  const runGen = g => {
    let r = g.next();
    while (!r.done) r = g.next();
    return r.value;
  };
  const kinGroups = model => runGen(kinGroupsGen(model));
  const kinYear = y => (y == null || !isFinite(y) ? '' : HT.formatAxisYear(y));
  /** 사람의 짧은 곁글: 지도자면 '3대 · 1418~1450'(첫 칸 — 나라는 카드의 나라 색이 보임: 4-3 '대수 · 기간' · 목업 결정 2 A), 아니면 생몰 '1402~', 둘 다 없으면 직함 */
  const kinSub = n => {
    const lc = n.cells.find(x => x.kind === 'leader');
    if (lc) return `${lc.c.ordinal != null ? `${lc.c.ordinal}대 · ` : ''}${kinYear(lc.c.start)}~${kinYear(lc.c.end)}`;
    const f = n.figure;
    if (f && (f.birth != null || f.death != null)) return `${kinYear(f.birth)}~${kinYear(f.death)}`;
    return f && f.role ? f.role : '';
  };
  /**
   * 계보 뼈대 — key = 'kin:<뿌리 가문 id>' | 'kin:polity:<정권 uid>' → 뼈대(없으면 null). 모델마다 캐시합니다.
   * { v: 1, uid(= key), n, gens, par · size · gen · bits · edge · branch · color: Int32Array(n), color2: Int32Array(n) | [] , name · sub · key(안정 열쇠): 글 목록,
   *   extra: Int32Array([from, to, 갈래, gen] × m — (to, from, 갈래, gen) 오름), colors: 글 목록(0 = '' 종이빛), branches: [{ uid, name, color, at, up }],
   *   cells: { '<정권 uid>|leader:<i>': 번호 }, stubs: {}, warnings: 글 목록 } — 열 꼴 기록(8-1 · 이음새 기록 D1-E ②)과 같은 이름(머리 이름만 uid).
   * 열거되지 않는 덧칸: people(번호 → 사람 자리) · index(안정 열쇠 → 번호).
   * 노드: 사람 자리의 뼈대 열쇠(linkPeople의 kinKey)가 key인 사람(구성원 — 비트 1) + 그 부계 부모 가운데 이름 미상의 빈 고리 + 구성원의 자식 가운데 구성원이 아닌 사람(외손 등 — 잎).
   */
  HT.kinSkeleton = (model, key) => {
    if (!model || !model.persons || typeof key !== 'string') return null;
    const store = kinStore(model);
    if (store.skel.has(key)) return store.skel.get(key);
    const skel = runGen(kinBuild(model, key));
    store.skel.set(key, skel);
    return skel;
  };
  /**
   * 나눠 짓기(덧붙임 — 4-6 '50ms를 넘을 큰 뼈대는 8ms마다 양보하며 짓고'): HT.kinSkeleton과 같은 뼈대를 Promise로. opts.slice(기본 8ms)마다 다음 장면으로 양보합니다.
   * 이미 지었으면 곧바로 그 값, 같은 열쇠를 짓는 중이면 같은 Promise. 지은 값은 HT.kinSkeleton과 같은 캐시에 둡니다
   */
  HT.kinSkeletonAsync = (model, key, opts = {}) => {
    if (!model || !model.persons || typeof key !== 'string') return Promise.resolve(null);
    const store = kinStore(model);
    if (store.skel.has(key)) return Promise.resolve(store.skel.get(key));
    const pending = store.pending || (store.pending = new Map());
    if (pending.has(key)) return pending.get(key);
    const slice = opts.slice > 0 ? opts.slice : 8;
    const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());
    const g = kinBuild(model, key);
    const p = new Promise((resolve, reject) => {
      const step = () => {
        try {
          if (store.skel.has(key)) return resolve(store.skel.get(key)); // 그사이 동기로 지었으면 그 값
          const t0 = now();
          for (;;) {
            const r = g.next();
            if (r.done) {
              store.skel.set(key, r.value);
              return resolve(r.value);
            }
            if (now() - t0 >= slice) break;
          }
          setTimeout(step, 0);
        } catch (e) {
          reject(e);
        }
      };
      step();
    });
    pending.set(key, p);
    const off = () => pending.delete(key);
    p.then(off, off);
    return p;
  };
  function* kinBuild(model, key) {
    let tick = 0;
    const pm = /^kin:polity:(.+)$/.exec(key);
    const hm = pm ? null : /^kin:(.+)$/.exec(key);
    const root = hm && model.houseMap ? model.houseMap.get(hm[1]) || null : null;
    const members = (yield* kinGroupsGen(model)).get(key) || [];
    if (!root && !(pm && members.length)) return null;
    /* ① 노드(번호 = 구성원 → 부계의 빈 고리 → 가문 밖 잎 차례): role 1 · 2 · 3 */
    const list = members.slice();
    const loc = new Int32Array(model.persons.length).fill(-1); // 사람 자리의 모델 차례(seq) → 노드 번호 (−1 = 뼈대 밖)
    for (let k = 0; k < list.length; k++) loc[list[k].seq] = k;
    const M = list.length;
    for (let k = 0; k < M; k++)
      for (const e of list[k].parents)
        if (loc[e.node.seq] < 0 && e.node.unknown && KIN_PATERNAL.has(e.as || '')) {
          loc[e.node.seq] = list.length;
          list.push(e.node);
        }
    const U = list.length;
    for (let k = 0; k < M; k++)
      for (const c of list[k].children)
        if (loc[c.node.seq] < 0) {
          loc[c.node.seq] = list.length;
          list.push(c.node);
        }
    const N = list.length;
    const roleOf = k => (k < M ? 1 : k < U ? 2 : 3);
    yield;
    /* ② 위상 차례 — 받아들인 부모 선 가운데 나무 부모(차례가 가장 앞)와 덧선을 가립니다. 고리를 만드는 선(아직 셈하지 않은 부모에서 오는 선)은 버리고 경고 */
    const warnings = [];
    const indeg = new Int32Array(N);
    for (let k = 0; k < N; k++) for (const e of list[k].parents) if (loc[e.node.seq] >= 0) indeg[k]++;
    const done = new Uint8Array(N);
    const tree = new Int32Array(N).fill(-1);
    const treeEdge = new Array(N).fill(null);
    const exLocal = []; // [부모 번호, 자식 번호, 갈래, gen] 넷씩 (노드 번호 — 앞 차례 번호로는 ⑤ 뒤에 바꿈)
    const queue = new Int32Array(N);
    let qt = 0;
    for (let k = 0; k < N; k++) if (!indeg[k]) queue[qt++] = k;
    let head = 0;
    let scan = 0;
    let count = 0;
    while (count < N) {
      if (head >= qt) {
        while (done[scan]) scan++;
        queue[qt++] = scan;
      }
      const k = queue[head++];
      if (done[k]) continue;
      done[k] = 1;
      count++;
      if (++tick === KIN_STEP) {
        tick = 0;
        yield;
      }
      const n = list[k];
      let best = null;
      let bestP = -1;
      let bestR = 99;
      for (const e of n.parents) {
        const p = loc[e.node.seq];
        if (p < 0) continue;
        if (!done[p] || p === k) {
          warnings.push(`${n.name}의 부모 ${e.node.name}: 혈연이 고리를 이뤄 이 선을 끊었습니다.`);
          continue;
        }
        const r = kinTreeRank(e.as);
        if (r < bestR) {
          bestR = r;
          best = e;
          bestP = p;
        }
      }
      if (best) {
        tree[k] = bestP;
        treeEdge[k] = best;
        for (const e of n.parents) {
          if (e === best) continue;
          const p = loc[e.node.seq];
          if (p < 0 || !done[p] || p === k) continue;
          exLocal.push(p, k, kinEdgeCode(e), e.gen || 1);
        }
      }
      for (const c of n.children) {
        const q = loc[c.node.seq];
        if (q >= 0 && !done[q] && --indeg[q] === 0) queue[qt++] = q;
      }
    }
    /* ③ 차례 열쇠 (order, 생년, 첫 칸 시작, 모델 차례) — 없는 값은 맨 뒤 · 늘 하나로 정해지는 전순서 */
    const kOrder = new Float64Array(N);
    const kBirth = new Float64Array(N);
    const kCell = new Float64Array(N);
    const kSeq = new Float64Array(N);
    for (let k = 0; k < N; k++) {
      const n = list[k];
      const f = n.figure;
      const c0 = n.cells[0];
      kOrder[k] = f && Number.isInteger(f.order) ? f.order : Infinity;
      kBirth[k] = f && f.birth != null && isFinite(f.birth) ? f.birth : Infinity;
      kCell[k] = c0 && c0.c.start != null && isFinite(c0.c.start) ? c0.c.start : Infinity;
      kSeq[k] = n.seq ?? Infinity;
    }
    yield;
    /* 두 값이 모두 Infinity(없음)면 빼기가 NaN — 거짓이라 다음 열쇠로 넘어갑니다(같은 것으로 봄) */
    const cmp = (a, b) => kOrder[a] - kOrder[b] || kBirth[a] - kBirth[b] || kCell[a] - kCell[b] || kSeq[a] - kSeq[b] || a - b;
    /* 자식 목록(CSR): 조각 g = 나무 부모 + 1(뿌리는 0번 조각) — [kid[g], kid[g + 1]) */
    const kid = new Int32Array(N + 2);
    for (let k = 0; k < N; k++) kid[tree[k] + 2]++;
    for (let g = 1; g <= N + 1; g++) kid[g] += kid[g - 1];
    const fill = kid.slice();
    const kidArr = new Int32Array(N);
    for (let k = 0; k < N; k++) kidArr[fill[tree[k] + 1]++] = k;
    for (let g = 0; g <= N; g++) {
      if (kid[g + 1] - kid[g] > 1) {
        kidArr.subarray(kid[g], kid[g + 1]).sort(cmp);
        tick += kid[g + 1] - kid[g];
      }
      if (tick >= KIN_STEP) {
        tick = 0;
        yield;
      }
    }
    /* ④ 앞 차례 */
    const ord = new Int32Array(N);
    const stack = new Int32Array(N);
    let sp = 0;
    for (let j = kid[1] - 1; j >= kid[0]; j--) stack[sp++] = kidArr[j];
    let oi = 0;
    while (sp) {
      const k = stack[--sp];
      ord[oi++] = k;
      for (let j = kid[k + 2] - 1; j >= kid[k + 1]; j--) stack[sp++] = kidArr[j];
    }
    const pre = new Int32Array(N);
    for (let i = 0; i < N; i++) pre[ord[i]] = i;
    const par = new Int32Array(N);
    const size = new Int32Array(N).fill(1);
    const gen = new Int32Array(N);
    const bits = new Int32Array(N);
    const edge = new Int32Array(N);
    const branch = new Int32Array(N);
    const color = new Int32Array(N);
    const color2 = new Int32Array(N);
    const name = new Array(N);
    const sub = new Array(N);
    const skey = new Array(N);
    const people = new Array(N);
    for (let i = 0; i < N; i++) {
      const k = ord[i];
      par[i] = tree[k] < 0 ? -1 : pre[tree[k]];
      const e = treeEdge[k];
      gen[i] = par[i] < 0 ? 0 : gen[par[i]] + (e.as === 'ancestor' ? e.gen || 1 : 1);
      edge[i] = e ? kinEdgeCode(e) : 0;
      people[i] = list[k];
    }
    for (let i = N - 1; i > 0; i--) if (par[i] >= 0) size[par[i]] += size[i];
    yield;
    /* ⑤ 파(가문 나무 — 뿌리 가문이 0번) */
    const branches = [];
    const branchAt = new Map();
    const founders = new Map();
    if (root) {
      HT.houseUnder(model, root.id).forEach((id, b) => {
        const h = model.houseMap.get(id);
        branchAt.set(id, b);
        branches.push({ uid: h.uid, name: h.name, color: h.color, at: -1, up: h.parentId && branchAt.has(h.parentId) ? branchAt.get(h.parentId) : -1 });
        if (b > 0 && h.founderNode) founders.set(h.founderNode, b);
      });
    }
    /* ⑥ 비트 · 파 · 색 · 글 · 안정 열쇠 · 칸 */
    const colors = [''];
    const colorAt = new Map([['', 0]]);
    const colorIdx = c => {
      const s = c || '';
      let v = colorAt.get(s);
      if (v === undefined) {
        v = colors.length;
        colorAt.set(s, v);
        colors.push(s);
      }
      return v;
    };
    const cellList = [];
    let two = false;
    const rootFounder = root ? root.founderNode : null;
    for (let i = 0; i < N; i++) {
      if (++tick === KIN_STEP) {
        tick = 0;
        yield;
      }
      const n = people[i];
      const r = roleOf(ord[i]);
      let b = 0;
      if (r === 1) b |= 1;
      if (n.unknown) b |= 2;
      if (n.missing) b |= 4;
      const fb = founders.get(n);
      if (fb !== undefined) {
        b |= 16;
        if (branches[fb].at < 0) branches[fb].at = i;
      }
      if (rootFounder === n && branches.length && branches[0].at < 0) branches[0].at = i; // 뿌리 가문의 시조 자리(비트 16은 파조에만)
      if (n.figure && n.figure.lineageOnly === true) b |= 64;
      let p0 = null;
      let p1 = null;
      for (const x of n.cells) {
        if (x.kind !== 'leader') continue;
        if (!p0) p0 = x.p;
        else if (!p1 && x.p !== p0) p1 = x.p;
        cellList.push([`${x.p.uid}|${x.ref}`, i]);
      }
      if (p0) {
        b |= 32;
        color[i] = colorIdx(p0.color);
        if (p1) {
          b |= 256;
          two = true;
          color2[i] = colorIdx(p1.color);
        }
      }
      bits[i] = b;
      branch[i] = !root ? -1 : r === 1 && n.houseId && branchAt.has(n.houseId) ? branchAt.get(n.houseId) : par[i] >= 0 ? branch[par[i]] : 0;
      name[i] = n.unknown ? '미상' : n.name;
      sub[i] = n.unknown ? '' : kinSub(n);
      skey[i] = n.key;
    }
    /* 빈 고리(u:…)는 지을 때마다 번호가 바뀌므로 '<자식 열쇠>^<그 자식의 부모 줄 번호>' */
    for (let i = 0; i < N; i++) {
      const n = people[i];
      if (n.key.charCodeAt(0) !== 117 || n.key.charCodeAt(1) !== 58) continue; // 'u:'
      const c = n.children[0] && n.children[0].node;
      skey[i] = c ? `${c.key}^${c.parents.findIndex(e => e.node === n)}` : n.key;
    }
    /* 덧선 — 앞 차례 번호로 · (to, from, 갈래, gen) 오름 · 옆구리 비트 */
    const m = exLocal.length / 4;
    const exIdx = new Int32Array(m);
    for (let j = 0; j < m; j++) {
      exLocal[j * 4] = pre[exLocal[j * 4]];
      exLocal[j * 4 + 1] = pre[exLocal[j * 4 + 1]];
      exIdx[j] = j;
    }
    exIdx.sort((a, b) => exLocal[a * 4 + 1] - exLocal[b * 4 + 1] || exLocal[a * 4] - exLocal[b * 4] || exLocal[a * 4 + 2] - exLocal[b * 4 + 2] || exLocal[a * 4 + 3] - exLocal[b * 4 + 3]);
    const extra = new Int32Array(m * 4);
    for (let j = 0; j < m; j++) {
      const s = exIdx[j] * 4;
      extra[j * 4] = exLocal[s];
      extra[j * 4 + 1] = exLocal[s + 1];
      extra[j * 4 + 2] = exLocal[s + 2];
      extra[j * 4 + 3] = exLocal[s + 3];
      bits[exLocal[s + 1]] |= 8;
    }
    let gens = 0;
    for (let i = 0; i < N; i++) if (gen[i] + 1 > gens) gens = gen[i] + 1;
    cellList.sort((a, b) => a[1] - b[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    const cells = {};
    for (const [k, v] of cellList) cells[k] = v;
    const skel = { v: 1, uid: key, n: N, gens, par, size, gen, bits, edge, branch, color, color2: two ? color2 : [], name, sub, key: skey, extra, colors, branches, cells, stubs: {}, warnings };
    let index = null;
    Object.defineProperty(skel, 'people', { value: people, enumerable: false });
    Object.defineProperty(skel, 'index', { enumerable: false, get: () => index || (index = new Map(skey.map((s, i) => [s, i]))) }); // 안정 열쇠 → 번호 (처음 쓸 때 지음)
    return skel;
  }
  /** 정권의 지도자 칸 i → { key: 뼈대 열쇠, at: 그 사람의 앞 차례 번호 } (없으면 null) */
  HT.kinOf = (model, polity, i) => {
    const p = polity && typeof polity === 'object' ? polity : model && model.byUid ? model.byUid.get(polity) : null;
    const n = p ? HT.personOf(model, p, `leader:${i}`) : null;
    if (!n || !n.kinKey) return null;
    const s = HT.kinSkeleton(model, n.kinKey);
    const at = s ? s.cells[`${p.uid}|leader:${i}`] : undefined;
    return at == null ? null : { key: s.uid, at };
  };
  /** 사람 자리(또는 그 열쇠 'f:…' · 'c:…') → { key, at } — 그 사람이 구성원으로 든 뼈대(없으면 null). 계보 전용 인물 창의 '세계표에서 보기'가 씀 */
  HT.kinOfPerson = (model, person) => {
    const n = typeof person === 'string' ? (model && model.personIndex ? model.personIndex.get(person) : null) : person;
    if (!n || !n.kinKey) return null;
    const s = HT.kinSkeleton(model, n.kinKey);
    const at = s ? s.index.get(n.key) : undefined;
    return at == null ? null : { key: s.uid, at };
  };
  /** 처음 열 때의 펼침(4-5): 200명 이하면 모두 · 넘으면 지도자 · 지도자의 조상을 펴고(지도자의 자녀 1대까지 보임) 나머지와 지도자 길에 없는 파조는 접음 · 지도자가 없으면 위에서 3세대까지(파조는 접음) */
  HT.kinDefaultOpen = skel => {
    const n = skel ? skel.n : 0;
    const open = new Uint8Array(n);
    if (n <= 200) return open.fill(1);
    let leaders = false;
    for (let i = n - 1; i >= 0; i--) {
      if (skel.bits[i] & 32) {
        leaders = true;
        open[i] = 1;
      }
      if (open[i] && skel.par[i] >= 0) open[skel.par[i]] = 1; // 지도자의 조상(뒤에서 앞으로 — 앞 차례라 부모가 늘 앞)
    }
    if (!leaders) for (let i = 0; i < n; i++) open[i] = skel.gen[i] <= 1 && !(skel.bits[i] & 16) ? 1 : 0;
    return open;
  };
  /**
   * 정수 칸 셈(4-4 — Dart kinLayout과 같은 계약): skel + open(Uint8Array · 배열 — 1이면 펼침) → { x: Int32Array(n), w: Int32Array(n), rows: [Int32Array](세대마다 보이는 번호 — 왼 → 오른), width }.
   * 단위 u(1배 35px). 보이지 않는 마디는 x = −1 · w = 0. 꼬투리(비트 128)는 접힌 마디로 셉니다. width = 뿌리들의 w 합.
   * px: 카드 왼쪽 = x·35 − 62 · 카드 위 = gen·82
   */
  HT.kinLayout = (skel, open) => {
    const n = skel ? skel.n : 0;
    const x = new Int32Array(n).fill(-1);
    const w = new Int32Array(n);
    const gens = skel ? skel.gens : 0;
    if (!n) return { x, w, rows: [], width: 0 };
    const { par, size, bits, gen } = skel;
    const o = open || [];
    /* 보이는 마디(앞 차례 — 접힌 · 꼬투리 · 자식 없는 마디의 하위는 건너뜀) */
    const vis = new Int32Array(n);
    const opened = new Uint8Array(n);
    let nv = 0;
    for (let i = 0; i < n; ) {
      vis[nv++] = i;
      if (o[i] && !(bits[i] & 128) && size[i] > 1) {
        opened[i] = 1;
        i++;
      } else i += size[i];
    }
    /* w: 뒤에서 앞으로(자식이 부모보다 먼저) — acc = 보이는 자식들의 w 합 */
    const acc = new Int32Array(n);
    for (let v = nv - 1; v >= 0; v--) {
      const i = vis[v];
      const side = (bits[i] >> 3) & 1;
      const wi = opened[i] ? side + acc[i] : 4 + side;
      w[i] = wi;
      if (par[i] >= 0) acc[par[i]] += wi;
    }
    /* left · 잎의 x · 끝 자식: 앞에서 뒤로 (acc를 '다음 자식의 left'로 다시 씀) */
    const last = acc; // 다 쓴 acc 자리를 끝 자식 번호로
    const cur = new Int32Array(n);
    const rowCount = new Int32Array(gens);
    let rootLeft = 0;
    for (let v = 0; v < nv; v++) {
      const i = vis[v];
      const side = (bits[i] >> 3) & 1;
      let left;
      const p = par[i];
      if (p < 0) {
        left = rootLeft;
        rootLeft += w[i];
      } else {
        left = cur[p];
        cur[p] += w[i];
        last[p] = i;
      }
      cur[i] = left + side;
      if (!opened[i]) x[i] = left + side + 2;
      rowCount[gen[i]]++;
    }
    /* 펼친 마디의 x: 뒤에서 앞으로 — 첫 자식(i + 1)과 끝 자식의 가운데(내림) */
    for (let v = nv - 1; v >= 0; v--) {
      const i = vis[v];
      if (opened[i]) x[i] = Math.floor((x[i + 1] + x[last[i]]) / 2);
    }
    /* 세대 줄: 같은 세대의 보이는 마디는 앞 차례가 곧 왼 → 오른 */
    const rows = new Array(gens);
    const fillAt = new Int32Array(gens);
    for (let g = 0; g < gens; g++) rows[g] = new Int32Array(rowCount[g]);
    for (let v = 0; v < nv; v++) {
      const i = vis[v];
      const g = gen[i];
      rows[g][fillAt[g]++] = i;
    }
    return { x, w, rows, width: rootLeft };
  };
  /** 승계표의 정권 정보(모델마다 캐시): 칸마다 { kin: { key, at } | null, person, first(같은 사람의 처음 칸 번호), count(후손 n — 펼침 구간의 사람 수) } */
  const successionInfo = (model, p) => {
    const store = kinStore(model);
    if (store.succ.has(p.uid)) return store.succ.get(p.uid);
    const L = p.leaders || [];
    const info = L.map((c, m) => ({ kin: HT.kinOf(model, p, m), person: HT.personOf(model, p, `leader:${m}`), first: m, count: 0 }));
    info.forEach((it, m) => {
      const f = it.person ? info.findIndex(q => q.person === it.person) : m;
      it.first = f < 0 ? m : f;
    });
    /* 뼈대 열쇠마다 '이 나라 지도자의 사람 번호 → 그 사람의 처음 칸' */
    const leaderAt = new Map();
    info.forEach((it, m) => {
      if (!it.kin) return;
      const t = leaderAt.get(it.kin.key) || leaderAt.set(it.kin.key, new Map()).get(it.kin.key);
      if (!t.has(it.kin.at)) t.set(it.kin.at, it.first);
    });
    for (const [m, it] of info.entries()) {
      if (!it.kin || it.first !== m) continue;
      const s = HT.kinSkeleton(model, it.kin.key);
      const t = leaderAt.get(it.kin.key);
      const end = it.kin.at + s.size[it.kin.at];
      let k = 0;
      for (let j = it.kin.at + 1; j < end; ) {
        if (t.has(j)) j += s.size[j];
        else {
          k++;
          j++;
        }
      }
      it.count = k;
    }
    const out = { info, leaderAt };
    store.succ.set(p.uid, out);
    return out;
  };
  const polityOf = (model, polity) => (polity && typeof polity === 'object' ? polity : model && model.byUid ? model.byUid.get(polity) || null : null);
  const openOf = (nodes, uid) => (!nodes ? null : nodes instanceof Map ? nodes.get(uid) || null : nodes[uid] || null);
  /**
   * 승계표 줄 목록(3-4 — Dart kinRows와 같은 계약): open = { <뼈대 uid>: 마디마다 1(펼침) · 0 } (객체 · Map — 빠진 뼈대 · 마디는 접힘).
   * 지도자 카드 Lₘ의 펼침은 그 사람의 마디 open[kinOf(m).key][kinOf(m).at] — 카드와 사람 마디가 같은 칸입니다(다시 오른 뒤 칸은 늘 접힘).
   * → Int32Array — 줄마다 세 수 [갈래, 번호, 깊이]:
   *   갈래 0 지도자 줄: 번호 = 칸 번호 m(p.leaders 차례), 깊이 0
   *   갈래 1 사람 줄: 번호 = 뼈대 앞 차례 번호 j(바로 위 지도자 줄의 뼈대 — HT.kinOf), 깊이 = gen[j] − gen[그 카드의 사람](1 이상 · 자르지 않음 — 그릴 때 8에서 자르고 '+n대')
   *   갈래 2 건너뛰기 줄(→ n대 ○○): 번호 = 그 지도자의 처음 칸 번호 m′, 깊이 같음
   * 한 사람은 한 번만 나옵니다 — 다른 지도자의 하위는 그 지도자 카드에서만, 다시 오른 사람은 처음 카드에서만 펼침
   */
  HT.successionRows = (model, polity, open = {}) => {
    const p = polityOf(model, polity);
    if (!p || !(p.leaders || []).length) return new Int32Array(0);
    const { info, leaderAt } = successionInfo(model, p);
    const rows = [];
    info.forEach((it, m) => {
      rows.push(0, m, 0);
      if (it.first !== m || !it.kin) return;
      const s = HT.kinSkeleton(model, it.kin.key);
      const nodeOpen = openOf(open, s.uid);
      const at = it.kin.at;
      if (!nodeOpen || !nodeOpen[at]) return;
      const t = leaderAt.get(it.kin.key);
      const end = at + s.size[at];
      for (let j = at + 1; j < end; ) {
        const d = s.gen[j] - s.gen[at];
        if (t.has(j)) {
          rows.push(2, t.get(j), d);
          j += s.size[j];
          continue;
        }
        rows.push(1, j, d);
        j += nodeOpen[j] && !(s.bits[j] & 128) ? 1 : s.size[j];
      }
    });
    return Int32Array.from(rows);
  };
  /** 지도자 카드 끝 알약 '후손 n ▸'의 n: 그 카드의 펼침 구간에 드는 사람 수(건너뛰기 줄의 하위는 셈하지 않음 — 0이면 알약 없음 · 다시 오른 뒤 칸은 0) */
  HT.successionReach = (model, polity, m) => {
    const p = polityOf(model, polity);
    if (!p || !(p.leaders || [])[m]) return 0;
    return successionInfo(model, p).info[m].count;
  };
  /**
   * 승계표의 수준 → successionRows에 줄 open ({ <뼈대 uid>: [0 · 1 …] } — 평평한 배열이라 JSON으로 옮길 수 있음):
   * 'leaders'(지도자만 — 처음 열 때) · 'children'(자녀까지 — 지도자 카드만 폄) · 'branches'(파 이름까지 — 카드 · 모든 파조의 조상을 펴고 지도자가 아닌 파조는 접음) · 'all'(모두)
   */
  HT.successionOpen = (model, polity, level = 'leaders') => {
    const p = polityOf(model, polity);
    const out = {};
    if (!p) return out;
    const { info } = successionInfo(model, p);
    for (const [m, it] of info.entries()) {
      if (!it.kin) continue;
      const s = HT.kinSkeleton(model, it.kin.key);
      let arr = out[s.uid];
      if (!arr) {
        arr = out[s.uid] = new Array(s.n).fill(level === 'all' ? 1 : 0);
        if (level === 'branches')
          for (let j = 0; j < s.n; j++) {
            if (!(s.bits[j] & 16)) continue;
            if (s.bits[j] & 32) arr[j] = 1;
            for (let q = s.par[j]; q >= 0; q = s.par[q]) arr[q] = 1;
          }
      }
      if (level !== 'leaders' && it.first === m) arr[it.kin.at] = 1;
    }
    return out;
  };
  /** 승계 선 갈래(3-3 · 결정 8 A) — 차례대로 첫째로 맞는 것: 1 찬탈 · 정변 · 정복(끊긴 선 + 빗금) · 2 관계나 방식 미상(점선) · 3 선양(겹선) · 4 복위(실선 + 고리) · 5 그 밖의 적은 값(실선) · 0 모두 비움(옅은 1px — 글 없음) */
  HT.accessionLine = acc => {
    const a = acc || {};
    if (['usurpation', 'coup', 'conquest'].includes(a.how)) return 1;
    if (a.kinUnknown || a.howUnknown) return 2;
    if (a.how === 'abdication') return 3;
    if (a.how === 'restoration') return 4;
    if (a.kin || a.how) return 5;
    return 0;
  };
  /**
   * 이음매 글(3-3): ruler = HT.lineageOf(…).rulers[i] → '전임자 ○○의 동생 · 찬탈' · '전임자 ○○ · 관계 미상 · 찬탈' · '전임자 미상 · 동생 · 방식 미상' ·
   * 바로 앞 칸이면(fromAuto) 이름을 빼고 '동생 · 찬탈'. 관계 · 방식을 모두 비웠으면 ''(비움 ≠ 미상). 새 앱은 이 글을 그대로 싣습니다(x_lineage seam)
   */
  HT.accessionSeam = (model, ruler) => {
    const a = (ruler && ruler.accession) || {};
    const kin = a.kinUnknown ? '관계 미상' : a.kin ? a.kinName || HT.kinName(a.kin) : '';
    const how = a.howUnknown ? '방식 미상' : a.how ? a.howName || HT.accessionHowName(a.how) : '';
    if (!kin && !how) return '';
    let who = '';
    if (a.fromUnknown) who = '전임자 미상';
    else if (a.from && !a.fromAuto) who = `전임자 ${a.from.name || '미상'}`;
    const head = who && kin && !a.kinUnknown && !a.fromUnknown ? `${who}의 ${kin}` : [who, kin].filter(Boolean).join(' · ');
    return [head, how].filter(Boolean).join(' · ');
  };
  /** 민족 참조(이름 · id) → 모델의 민족과 위 단계 사슬(대명제 › … › 민족) */
  const peopleOf = (model, ref) => {
    const r = String(ref ?? '').trim();
    if (!r || !model || !model.peopleMap) return null;
    const pe = model.peopleMap.get(r) || model.peoples.find(x => x.name === r) || null;
    if (!pe) return { people: null, name: r, chain: r };
    const chain = [];
    const seen = new Set();
    for (let cur = pe; cur && !seen.has(cur.id); cur = cur.parent ? model.peopleMap.get(cur.parent) || model.peoples.find(x => x.name === cur.parent) || null : null) {
      seen.add(cur.id);
      chain.unshift(cur.name);
    }
    return { people: pe, name: pe.name, chain: chain.join(' › ') };
  };
  const trackChip = (model, id, extra) => {
    const t = model.trackMap ? model.trackMap.get(id) : null;
    return Object.assign({ role: 'track', text: t ? t.name : id, uid: `track:${id}`, field: 'track' }, extra);
  };
  const peopleChip = (model, ref, extra) => {
    const pe = peopleOf(model, ref);
    if (!pe) return null;
    return Object.assign({ role: 'people', text: pe.name, uid: pe.people ? `people:${pe.people.id}` : undefined, field: 'people' }, pe.chain !== pe.name ? { title: pe.chain } : null, extra);
  };
  const tagChips = tags => (Array.isArray(tags) ? tags : []).filter(Boolean).map(t => ({ role: 'tag', text: String(t), field: 'tags' }));
  const clean = chips => chips.filter(Boolean).map(c => {
    for (const k of Object.keys(c)) if (c[k] === undefined) delete c[k];
    return c;
  });
  /** 승계표 머리 칩(3-2): [● 구분] › [● 민족] › [● 국가 이름] · [꼬리표] … → [{ role: 'track' | 'people' | 'name' | 'tag', text, title?, uid?, field }] (값이 없는 칩은 뺌) */
  HT.polityHead = (model, polity) => {
    const p = polityOf(model, polity);
    if (!p) return [];
    return clean([p.track ? trackChip(model, p.track) : null, p.people ? peopleChip(model, p.people) : null, { role: 'name', text: p.name, uid: p.uid, field: 'name' }, ...tagChips(p.tags)]);
  };
  const houseOf = (model, ref) => {
    if (!model || !model.houseMap) return null;
    if (ref && typeof ref === 'object') return ref;
    const r = String(ref ?? '').trim().replace(/^house:/, '');
    return model.houseMap.get(r) || (model.houses || []).find(h => h.name === r) || null;
  };
  /** 가문의 '본관 성씨' 글과 칩 — 본가 길에서 처음 만나는 seat · surname(성씨 사전 이름). 본관이 있으면 '물빛 온씨', 없으면 성만 */
  const seatSurname = (model, h) => {
    const sh = h.surname ? h : h.surnameFrom ? model.houseMap.get(h.surnameFrom) : null;
    if (!sh) return null;
    const sn = sh.surnameId && model.surnameMap ? model.surnameMap.get(sh.surnameId) : null;
    const surname = sn ? sn.name : sh.surname;
    const seatHouse = h.seat ? h : h.seatFrom ? model.houseMap.get(h.seatFrom) : null;
    const seat = seatHouse ? seatHouse.seat : '';
    return { text: seat ? `${seat} ${surname}씨` : surname, uid: sn ? sn.uid : undefined, field: seat ? 'seat' : 'surname', inherited: sh !== h || (!!seatHouse && seatHouse !== h) };
  };
  const TRACK_FROM = { period: '국성으로 삼은 나라에서', leader: '지도자 칸이 든 나라에서', person: '구성원에서', parent: '본가에서' };
  /** 세계표 머리 칩(4-2): [● 구분] › [● 민족] › [● 본관 성씨] › [● 이름] · [꼬리표] … — 짐작한 칩은 auto: true(풍선 '짐작 — …') · 이름이 본관 성씨와 같으면 뺌 */
  HT.houseHead = (model, house) => {
    const h = houseOf(model, house);
    if (!h) return [];
    const more = h.trackMore ? ` · +${h.trackMore}` : '';
    const tr = h.track ? trackChip(model, h.track) : h.trackAuto ? trackChip(model, h.trackAuto, { auto: true, title: `짐작 — ${TRACK_FROM[h.trackFrom] || '본가에서'}${more}` }) : null;
    const pe = h.people ? peopleChip(model, h.people) : h.peopleAuto ? peopleChip(model, h.peopleAuto, { auto: true }) : null;
    if (pe && pe.auto) pe.title = `짐작 — ${TRACK_FROM[h.peopleFrom] || '본가에서'}${pe.title ? ` (${pe.title})` : ''}`;
    const ss = seatSurname(model, h);
    const seatChip = ss ? Object.assign({ role: 'surname', text: ss.text, uid: ss.uid, field: ss.field }, ss.inherited ? { title: '본가의 본관 성씨' } : null) : null;
    const nameChip = !ss || ss.text !== h.name ? { role: 'name', text: h.name, uid: h.uid, field: 'name' } : null;
    return clean([tr, pe, seatChip, nameChip, ...tagChips(h.tags)]);
  };
  /** 그 가문과 아래 파 모두의 id(자기 먼저 · 가문 나무 앞 차례) — id · 'house:id' · 이름을 받습니다 */
  HT.houseUnder = (model, id) => {
    const h = houseOf(model, id);
    if (!h) return [];
    const out = [];
    const seen = new Set();
    const stack = [h.id];
    while (stack.length) {
      const k = stack.pop();
      if (seen.has(k)) continue;
      seen.add(k);
      out.push(k);
      const x = model.houseMap.get(k);
      const ch = (x && x.children) || [];
      for (let j = ch.length - 1; j >= 0; j--) stack.push(ch[j]);
    }
    return out;
  };
  /**
   * 가문 조명 구간(결정 7 A): ids(가문 id 하나 · 목록 — 'house:id' · 이름도) → [{ uid: 정권 uid, start, end }] (해 단위 · 끝 ≥ 시작 · 시작 순).
   * 칸의 가문(houseId — 적은 것 → 왕조 → 국성: 띠의 가문 줄과 같은 값)이 ids에 든 지도자 칸의 기간. 맞닿은 칸은 한 구간으로 잇고(끝 ≥ 다음 시작),
   * 지도자 칸이 하나도 없는 나라는 국성이 ids에 들면 나라 기간 전체. opts.branches = true면 ids마다 아래 파까지(HT.houseUnder)
   * 내각(실권) 칸의 가문이 ids에 들면 그 기간도 따로 한 구간씩 { …, real: true } (감독 건의 2026-10-14 5번 — 왕이 아니라 재상 · 섭정으로 나라를 쥔 가문도
   * '다스린 기간'에 나오게. 예전에는 지도자 칸만 세어 실권 가문은 막대도 조명도 없었음). 지도자 구간과 잇지 않습니다(따로 칠하므로)
   */
  HT.houseSpans = (model, ids, opts = {}) => {
    if (!model || !model.houseMap) return [];
    const want = new Set();
    for (const r of Array.isArray(ids) ? ids : ids == null ? [] : [ids]) {
      const h = houseOf(model, r);
      if (!h) continue;
      for (const id of opts.branches ? HT.houseUnder(model, h.id) : [h.id]) want.add(id);
    }
    if (!want.size) return [];
    const out = [];
    /* 칸 줄 하나(지도자 · 내각)에서 ids의 가문이 이어 앉은 구간 — 맞닿은 칸은 한 구간으로 */
    const runs = (p, L, real) => {
      let cur = null;
      L.forEach((c, i) => {
        if (!(c.houseId && want.has(c.houseId)) || c.start == null) {
          cur = null;
          return;
        }
        const next = L[i + 1];
        const follows = next && next.start != null && next.start > c.start;
        const end = Math.max(c.start, c.end ?? (follows ? next.start : p.endY ?? c.start));
        /* 끝을 적지 않았고(미정 · 비움) 뒤 칸의 시작으로 메울 수도 없으면 열린 끝 — 막대는 나라 끝까지 가도 글은 '~ 미정'(나라의 끝을 그 가문의 끝처럼 적지 않게) */
        const open = c.end == null && (!!c.endUnknown || (!follows && !p.ongoing));
        if (cur && cur.end >= c.start - 1e-9) {
          if (end >= cur.end) {
            if (open) cur.open = true;
            else delete cur.open;
          }
          cur.end = Math.max(cur.end, end);
        } else out.push((cur = Object.assign({ uid: p.uid, start: c.start, end }, open ? { open: true } : null, real ? { real: true } : null)));
      });
    };
    for (const p of model.periods) {
      if (HT.itemKindOf(p) !== 'period') continue;
      const L = p.leaders || [];
      if (!L.length) {
        if (p.houseId && want.has(p.houseId)) out.push({ uid: p.uid, start: p.start, end: Math.max(p.start, p.endY ?? p.start) });
      } else runs(p, L, false);
      runs(p, (p.cabinets || []).slice().sort((a, b) => (a.start ?? 0) - (b.start ?? 0)), true);
    }
    out.sort((a, b) => a.start - b.start || (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
    return out;
  };
  /** 다스린 기간 막대(5-3 — 가문 창 맨 위): 그 가문(과 아래 파)이 다스린 나라마다 한 줄 [{ uid, name, color, span: [나라 시작, 끝], cells: [[시작, 끝], …], real: [[시작, 끝], …] }] — 나라 시작 순.
   *  cells = 지도자 자리에 있던 구간 · real = 내각(실권) 자리에 있던 구간(감독 건의 2026-10-14 5번 — 실권만 쥔 가문의 나라도 줄이 생김) */
  HT.houseEras = (model, id) => {
    const h = houseOf(model, id);
    if (!h) return [];
    const ids = HT.houseUnder(model, h.id);
    const want = new Set(ids);
    const spans = HT.houseSpans(model, ids);
    const rows = new Map();
    for (const p of model.periods) {
      if (HT.itemKindOf(p) !== 'period') continue;
      const mine = spans.filter(s => s.uid === p.uid);
      if (!mine.length && !(p.houseId && want.has(p.houseId))) continue;
      const lead = mine.filter(s => !s.real), real = mine.filter(s => s.real);
      const row = { uid: p.uid, name: p.name, color: p.color, span: [p.start, Math.max(p.start, p.endY ?? p.start)], cells: lead.map(s => [s.start, s.end]), real: real.map(s => [s.start, s.end]) };
      /* 끝이 열린 구간(적지 않음 · 미정)의 차례 — 글로 적을 때 '~ 미정'(막대는 나라 끝까지) */
      const openOf = list => list.map((s, i) => (s.open ? i : -1)).filter(i => i >= 0);
      if (openOf(lead).length) row.openCells = openOf(lead);
      if (openOf(real).length) row.openReal = openOf(real);
      rows.set(p.uid, row);
    }
    return [...rows.values()].sort((a, b) => a.span[0] - b.span[0] || (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
  };

  /* ---------- 띠 배치의 기준점 · 간지 설정 (형식 버전 3 — 설계 6 결정 6 · 8 · 위 '배열 기준 · 남북 값 · 간지 설정') ----------
   * buildModel의 끝(지명 사전 · 지도를 푼 뒤)에서 엽니다. 원문 칸은 고쳐 쓰지 않습니다.
   * ① 간지 설정(model.yearCycle): 켠 DLC 가운데 yearCycle을 적은 첫 DLC의 것 — { off: true } · { names, start, label } (+ packId · packName), 없으면 null(육십갑자).
   * ② 민족의 배열 기준(pe.rowOrder): id로 합친 민족은 먼저 켠 DLC의 정의가 이기지만, 기준은 그 정의에 없으면 뒤 DLC가 같은 id로 적은 것을 씁니다
   *    (기본팩 민족에 같은 id의 민족 줄로 기준만 더하는 DLC). 하위 민족은 제 값을 적지 않으면 상위의 것을 물려받습니다(HT.rowOrderOf — 연표의 줄 배치와 같은 셈).
   * ③ 나라의 남북 값(p.north — 열거되지 않는 속성이라 사본 · 내보내기에 섞이지 않음): 적은 남북 위치(northSouth) → 없으면 첫 정도(정식 도읍 가운데 시작이 가장 이른 칸 —
   *    천도해도 첫 도읍 하나로)의 지명 좌표 둘째 값. 좌표 방식은 그 지명을 실은 DLC의 지도로 가름: 그 DLC에 지도가 없으면 경위도(위도 — 클수록 북),
   *    그 지명을 실은 지도가 있으면 그 지도의 crs(image면 그림 y가 아래로 커지므로 부호를 뒤집음), 실은 지도가 없으면 그 DLC 지도들의 crs가 모두 같을 때 그것 · 섞였으면 경위도로 보고 알림.
   * ④ 알림(model.orderWarnings [{ msg, packId, list, id }] — 메이커의 검사 창): 기준이 '북 → 남'인 민족의 줄 머리(같은 트랙의 앞 나라가 없는 나라)에 남북 값이 없을 때 · 좌표 방식이 섞여 경위도로 본 때 */
  HT.rowOrderOf = (pe, peopleMap) => {
    for (let cur = pe, k = 0; cur && k < 64; cur = cur.parentId && peopleMap ? peopleMap.get(cur.parentId) : null, k++) if (cur.rowOrder) return cur.rowOrder;
    return 'start';
  };
  /** 나라의 남북 값 (linkOrder가 정함 — 없으면 null) */
  HT.northOf = p => (p && typeof p.north === 'number' && Number.isFinite(p.north) ? p.north : null);
  const linkOrder = (model, packs) => {
    /* ① */
    model.yearCycle = null;
    for (const pack of packs) {
      if (pack.yearCycle === undefined || pack.yearCycle === null) continue;
      model.yearCycle = Object.assign(pack.yearCycle === false ? { off: true } : JSON.parse(JSON.stringify(pack.yearCycle)), { packId: pack.id, packName: pack.name });
      break;
    }
    /* ② */
    const peopleMap = model.peopleMap;
    for (const pack of packs)
      for (const x of pack.peoples || []) {
        const pe = x && x.rowOrder ? peopleMap.get(x.id) : null;
        if (pe && !pe.rowOrder) pe.rowOrder = x.rowOrder;
      }
    /* ③ */
    const warnings = [];
    const packById = new Map(packs.map(p => [p.id, p]));
    const crsMemo = new Map();
    const crsOf = pl => {
      if (crsMemo.has(pl.id)) return crsMemo.get(pl.id);
      const maps = ((packById.get(pl.packId) || {}).maps || []).filter(m => m && typeof m === 'object');
      let r = { crs: 'lonlat', mixed: false };
      if (maps.length) {
        const hit = maps.find(m => (m.places || []).some(ref => ref === pl.id || ref === pl.name));
        if (hit) r = { crs: hit.crs || 'image', mixed: false };
        else {
          const kinds = [...new Set(maps.map(m => m.crs || 'image'))];
          r = kinds.length === 1 ? { crs: kinds[0], mixed: false } : { crs: 'lonlat', mixed: true };
        }
      }
      crsMemo.set(pl.id, r);
      return r;
    };
    const placeOf = ref => (ref && model.placeMap ? model.placeMap.get(ref) || (model.placeByName && model.placeByName.get(ref)) || null : null);
    const firstSeat = p => {
      let best = null;
      for (const c of p.capitals || []) {
        if (!c || (c.role && c.role !== 'main')) continue;
        const s = Number.isFinite(c.start) ? c.start : Infinity;
        if (!best || s < best.s) best = { c, s };
      }
      return best ? best.c : null;
    };
    const ruleOf = new Map(); // 민족 id → 물려받은 기준 (같은 민족을 여러 번 묻지 않게)
    const ruleFor = pe => {
      if (!pe) return 'start';
      if (!ruleOf.has(pe.id)) ruleOf.set(pe.id, HT.rowOrderOf(pe, peopleMap));
      return ruleOf.get(pe.id);
    };
    const words = { period: 'periods', organ: 'organs', culture: 'cultures', dynasty: 'dynasties' };
    for (const p of model.periods) {
      if (p.kind !== 'period') continue;
      let v = null;
      let seat = null;
      let mixed = false;
      if (typeof p.northSouth === 'number' && Number.isFinite(p.northSouth)) v = p.northSouth;
      else {
        seat = firstSeat(p);
        const pl = seat ? (seat.placeId && model.placeMap && model.placeMap.get(seat.placeId)) || placeOf(seat.city) : null;
        if (pl && Array.isArray(pl.at) && pl.at.length === 2 && Number.isFinite(pl.at[1])) {
          const r = crsOf(pl);
          v = r.crs === 'image' ? -pl.at[1] : pl.at[1];
          mixed = r.mixed;
        }
      }
      if (v != null) Object.defineProperty(p, 'north', { value: v, configurable: true, writable: true, enumerable: false });
      /* ④ 기준이 '북 → 남'인 민족에 든 나라만 */
      const pe = p.peopleId ? peopleMap.get(p.peopleId) : null;
      if (!pe || ruleFor(pe) !== 'northSouth') continue;
      const kindWord = words[HT.itemKindOf(p)] || 'periods';
      const at = { packId: p.packId || '', list: kindWord, id: p.id };
      if (mixed) warnings.push(Object.assign({ msg: `${p.name}: 첫 정도 «${seat.city}»의 지명 좌표를 경위도(둘째 값 = 위도)로 보았습니다 — 그 지명을 실은 지도가 없고 이 지명 사전의 DLC 지도들은 좌표 방식이 섞여 있습니다. 지명을 지도의 지명 목록(places)에 넣거나 남북 위치를 직접 적으세요.` }, at));
      const head = !p.singleHost && !['dynasty', 'overlay'].includes(p.polityKind) && !(p.predecessors || []).some(e => e.from && e.from.track === p.track);
      if (v == null && head) warnings.push(Object.assign({ msg: `${p.name}: 남북 위치 없음 — 민족 «${pe.name}»의 배열 기준이 '북 → 남'인데 남북 위치도, 지명 좌표가 있는 첫 정도도 없어 같은 묶음의 값이 있는 줄들 뒤에 놓입니다.` }, at));
    }
    model.orderWarnings = warnings;
  };

  /* opts.groupBands(리메이크 조각 ④ · 내보내기만 켬 — export/base.mjs contextOf): 단체를 띠로도 올린다(아래 '단체의 띠'). 웹 연표 · 메이커 미리보기는 끈 채 예전 그대로 */
  HT.buildModel = function (packs, user, opts = {}) {
    /* 문화권 사전(켠 DLC들의 spheres — 2026-10-23 · 프로그램에 든 문화권은 없음): 트랙의 sphere를 풀기 전에 세워 HT.sphereOf가 이 모델의 사전을 보게 */
    const spheres = HT.mergeSpheres(packs);
    const sphereMap = HT.useSpheres(spheres);
    /* 만든 곳이 없는 문화권 id를 적은 트랙 — 문화권 없이 놓고 알립니다 [{ msg, packId, list: 'tracks', id }] (메이커의 검사 창 — orderWarnings와 같은 길) */
    const sphereWarnings = [];
    for (const pack of packs || [])
      for (const t of (pack && pack.tracks) || [])
        if (t && t.sphere && !sphereMap.has(t.sphere)) sphereWarnings.push({ msg: `트랙 "${t.name || t.id}"의 문화권 "${t.sphere}"을(를) 켠 DLC 가운데 만든 곳이 없어 문화권 없이 놓습니다 — 바탕 자료의 「문화권」에서 만들거나 다른 문화권을 고르세요.`, packId: pack.id, list: 'tracks', id: t.id });
    const tracks = new Map();
    const categories = new Map();
    let seq = 0;
    const addTrack = t => {
      // 문화권: 먼저 놓인 DLC가 적은 것(사전에 있는 것만) → 뒤 DLC가 적은 것 → 없음(빈 글). sphereSet = 사전에 있는 문화권을 DLC가 적었는가(작업본 복사가 본다)
      if (!tracks.has(t.id)) tracks.set(t.id, { id: t.id, name: t.name || t.id, color: HT.pastel(t.color || HT.autoColor(t.id)), order: t.order ?? 1000 + seq, seq: seq++, description: t.description || '', wiki: t.wiki || '', sphere: HT.isSphere(t.sphere) ? t.sphere : '', sphereSet: HT.isSphere(t.sphere) });
      else {
        const cur = tracks.get(t.id);
        if (!cur.wiki && t.wiki) cur.wiki = t.wiki;
        if (!cur.description && t.description) cur.description = t.description;
        if (!cur.sphereSet && HT.isSphere(t.sphere)) Object.assign(cur, { sphere: t.sphere, sphereSet: true });
      }
    };
    const addCat = c => {
      if (!categories.has(c.id)) categories.set(c.id, { id: c.id, name: c.name || c.id, color: HT.pastel(c.color || HT.autoColor(c.id)) });
    };
    HT.DEFAULT_CATEGORIES.forEach(addCat);
    /* 민족: id로 병합하고, 시대에 이름만 적힌 민족은 자동으로 만듭니다 */
    const peoples = new Map();
    let pseq = 0;
    const addPeople = p => {
      if (!peoples.has(p.id)) peoples.set(p.id, { id: p.id, name: p.name || p.id, parent: p.parent || '', color: HT.pastel(p.color || HT.autoColor(`people:${p.id}`)), description: p.description || '', wiki: p.wiki || '', order: p.order ?? 1000 + pseq, seq: pseq++, auto: !!p.auto });
    };

    const periodMap = new Map();
    const eventMap = new Map();
    const patches = [];
    /* 파생 값: 끝 연도, 확실성, 이설·연대 폭까지 포함한 전체 범위 */
    const derive = x => {
      const alts = HT.datedAlts(x); // 글만 있는 견해는 범위에 넣지 않습니다 (날짜가 없음)
      const altEnd = a => (a.ongoing ? HT.NOW_T : a.end ?? a.start);
      /* 끝이 시작보다 앞에 놓이면(날짜로 적은 시작 + 연도만 적은 같은 해의 끝: "1592-05-23 ~ 1592") 그해 끝까지로 */
      const e0 = x.end ?? x.start;
      x.endY = x.ongoing ? Math.max(HT.NOW_T, x.start) : e0 < x.start ? Math.max(x.start, HT.endBound(x.end, HT.atOf(x, 'end'))) : e0;
      x.certainty = HT.certaintyOf(x);
      x.spanMin = Math.min(x.start, x.startRange ? x.startRange[0] : x.start, ...alts.map(a => a.start));
      x.spanMax = Math.max(x.endY, x.endRange ? x.endRange[1] : x.endY, ...alts.map(altEnd));
      return x;
    };
    const deco = (x, pack, kind, extra) =>
      derive(Object.assign({}, x, extra, { kind, uid: `${pack.id}/${x.id}`, packId: pack.id, packName: pack.name }));
    /* 인물은 시작이 없을 수 있어 derive(시작을 전제)를 거치지 않습니다 — 시기(start · endY)와 섬긴 정권은 패치 · 내 수정이 끝난 뒤 아래 "인물" 단계에서 풉니다.
       periods에 넣지 않으므로 트랙 자동 생성 · 띠 색 배정 · 사건의 소속 정권 후보에 섞이지 않습니다 */
    const figureMap = new Map();
    const decoFigure = (f, pack, extra) => Object.assign({}, f, extra, { kind: 'figure', itemKind: 'figure', uid: `${pack.id}/${f.id}`, packId: pack.id, packName: pack.name });
    /* 단체 · 제도 칸 (형식 버전 3): 인물처럼 periods 밖의 목록 — 패치 · 숨김이 닿고(학설팩), 풀기(나라 · 주제 · 앞선 단체 …)는 패치가 모두 끝난 뒤 아래 '단체 · 렌즈의 재료' 단계에서.
       단체는 기간이 있어 derive를 거치고, 제도는 칸에서 기간이 나오므로 거치지 않습니다 */
    const groupMap = new Map();
    const instMap = new Map();
    const decoInst = (x, pack) => Object.assign({}, x, { kind: 'institution', itemKind: 'institution', uid: `${pack.id}/${x.id}`, packId: pack.id, packName: pack.name });

    const epochs = [];
    const EPOCH_PALETTE = ['#c8b193', '#a0bcc5', '#b6c398', '#bbacc8', '#dab195', '#9dbea8', '#abb3c9', '#d1a9b9'];
    /* 기관·문화는 DLC에서는 따로 적지만, 병합 모델에서는 시대와 같은 틀(period + polityKind)로 다뤄 그리기·검색·문서를 함께 씁니다 */
    HT.organAsPeriod = g => Object.assign({}, g, { kind: 'overlay', partOf: g.host });
    HT.cultureAsPeriod = c => Object.assign({}, c, { kind: 'culture' });
    HT.dynastyAsPeriod = d => Object.assign({}, d, { kind: 'dynasty', partOf: d.polities });
    const docs = new Map(); // 문서 키 → { text, packId, packName, user }
    for (const pack of packs) {
      pack.tracks.forEach(addTrack);
      pack.categories.forEach(addCat);
      (pack.peoples || []).forEach(addPeople);
      (pack.epochs || []).forEach((e, i) =>
        epochs.push(Object.assign({}, e, { kind: 'epoch', itemKind: 'epoch', uid: `${pack.id}/${e.id}`, packId: pack.id, packName: pack.name, endY: e.ongoing ? Math.max(HT.NOW_T, e.start) : e.end ?? e.start, color: HT.pastel(e.color || EPOCH_PALETTE[(epochs.length + i) % EPOCH_PALETTE.length]) }))
      );
      pack.periods.forEach(p => periodMap.set(`${pack.id}/${p.id}`, deco(p, pack, 'period', { polityKind: HT.kindOf(p), itemKind: 'period' })));
      (pack.organs || []).forEach(g => periodMap.set(`${pack.id}/${g.id}`, deco(HT.organAsPeriod(g), pack, 'period', { polityKind: 'overlay', itemKind: 'organ' })));
      (pack.cultures || []).forEach(c => periodMap.set(`${pack.id}/${c.id}`, deco(HT.cultureAsPeriod(c), pack, 'period', { polityKind: 'culture', itemKind: 'culture' })));
      (pack.dynasties || []).forEach(d => periodMap.set(`${pack.id}/${d.id}`, deco(HT.dynastyAsPeriod(d), pack, 'period', { polityKind: 'dynasty', itemKind: 'dynasty' })));
      pack.events.forEach(e => eventMap.set(`${pack.id}/${e.id}`, deco(e, pack, 'event', { itemKind: 'event' })));
      (pack.figures || []).forEach(f => figureMap.set(`${pack.id}/${f.id}`, decoFigure(f, pack)));
      (pack.groups || []).forEach(g => groupMap.set(`${pack.id}/${g.id}`, deco(g, pack, 'group', { itemKind: 'group' })));
      (pack.institutions || []).forEach(x => instMap.set(`${pack.id}/${x.id}`, decoInst(x, pack)));
      (pack.patches || []).forEach(patch => patches.push({ patch, pack }));
      for (const [k, text] of Object.entries(pack.documents || {})) docs.set(HT.docKey.absolute(k, pack.id), { text, packId: pack.id, packName: pack.name });
    }

    /* 다른 DLC의 사건·시대를 고치는 패치 */
    for (const { patch, pack } of patches) {
      const map = eventMap.has(patch.target) ? eventMap : periodMap.has(patch.target) ? periodMap : figureMap.has(patch.target) ? figureMap : groupMap.has(patch.target) ? groupMap : instMap.has(patch.target) ? instMap : null;
      if (!map) continue;
      if (patch.hide) {
        map.delete(patch.target);
        continue;
      }
      const item = map.get(patch.target);
      const before = {};
      for (const k of Object.keys(patch.set || {})) before[k] = item[k];
      const set = Object.assign({}, patch.set);
      /* 다른 견해: 패치는 가장 넓은 꼴로 읽었으므로(인물 — HT.readAlternatives의 'figure') 사건 · 시대에는 항목의 꼴만 — 시작이 있는 것과 글만 있는 견해, 생몰 칸은 뺌 */
      if (map !== figureMap && Array.isArray(set.alternatives)) set.alternatives = set.alternatives.filter(a => a.start != null || !HT.altDated(a)).map(({ birth, birthAt, death, deathAt, ...a }) => a);
      if ('kind' in set) {
        // 패치의 kind는 정권 종류입니다 (모델의 kind는 항목 구분이므로 건드리지 않음)
        set.polityKind = HT.kindOf({ kind: set.kind });
        before.polityKind = item.polityKind;
        delete set.kind;
        delete before.kind;
      }
      if (map !== eventMap && 'treaty' in set) {
        // 조약 규격은 사건에만 얹힙니다 (PATCHABLE은 사건과 시대가 함께 써서, 파일을 읽을 때는 대상이 시대인지 모름) — 시대 · 기관 · 문화 · 왕조를 가리킨 treaty는 버림
        delete set.treaty;
        delete before.treaty;
        if (!Object.keys(set).length) continue; // 조약 규격만 담은 패치는 이 대상에 할 일이 없음 (상세에 빈 고침 상자가 생기지 않게)
      }
      /* 형식 버전 3의 규격도 같은 규칙: 법 · 선거 규격은 사건에만, 주제(theme)는 사건(꼬리표 목록)과 제도(주제 하나)에만 — 다른 대상을 가리킨 것은 버림 */
      let dropped = false;
      for (const k of ['law', 'election', 'theme']) {
        if (!(k in set) || map === eventMap || (k === 'theme' && map === instMap)) continue;
        delete set[k];
        delete before[k];
        dropped = true;
      }
      if (dropped && !Object.keys(set).length) continue; // 이 대상에 할 일이 없음 (조약 규격과 같게)
      if (map === instMap && Array.isArray(set.theme)) set.theme = set.theme[0] || item.theme; // 제도의 주제는 하나 — 목록으로 적은 패치는 첫 것
      const merged = Object.assign({}, item, set, {
        id: item.id,
        uid: item.uid,
        kind: item.kind,
        patchedBy: (item.patchedBy || []).concat([{ id: pack.id, name: pack.name, note: patch.note || '', before }]),
      });
      /* 패치가 시작 · 끝을 세기로 적었으면(묶음 5 · 6번) 대상을 알게 된 여기서 연대 폭을 채웁니다 — 시대는 늘 기간이 있고, 사건은 끝이 있을 때만 */
      if (map !== figureMap && ('start' in set || 'end' in set)) Object.assign(merged, HT.centuryRanges(merged, map === periodMap || merged.end != null || merged.ongoing === true));
      map.set(
        patch.target,
        (map === figureMap || map === instMap ? x => x : derive)(merged) // 인물의 시기는 맨 나중에 풉니다 (derive는 시작을 전제) · 제도의 기간은 칸에서 (아래 렌즈의 재료)
      );
    }

    /* 사용자가 숨기거나 고친 것 (패치보다 우선) */
    if (user) {
      for (const uid of Object.keys(user.hidden || {})) {
        eventMap.delete(uid);
        periodMap.delete(uid);
        figureMap.delete(uid);
        groupMap.delete(uid);
        instMap.delete(uid);
      }
      for (const [uid, ov] of Object.entries(user.overrides || {})) {
        const map = eventMap.has(uid) ? eventMap : periodMap.has(uid) ? periodMap : figureMap.has(uid) ? figureMap : groupMap.has(uid) ? groupMap : instMap.has(uid) ? instMap : null;
        if (!map) continue;
        const item = map.get(uid);
        const extra = { id: item.id, uid, kind: item.kind, overridden: true };
        if (item.kind === 'period' && 'kind' in ov) extra.polityKind = HT.kindOf({ kind: ov.kind }); // 수정 폼의 kind는 정권 종류
        map.set(uid, (map === figureMap || map === instMap ? x => x : derive)(Object.assign({}, item, ov, extra)));
      }
    }

    /* 기관의 얹히는 정권(host)은 그리기에서 소속(partOf)으로 씁니다 — 패치·수정으로 host가 바뀌었을 때도 맞춥니다 */
    for (const p of periodMap.values()) {
      if (p.itemKind === 'organ' && p.host != null) p.partOf = p.host;
      if (p.itemKind === 'dynasty' && p.polities != null) p.partOf = p.polities; // 왕조의 다스린 정권도 같은 틀로
    }
    /* 단체의 띠(리메이크 조각 ④ · 설계 4-6 #7 C · opts.groupBands일 때만): 기관(organAsPeriod)과 같은 틀로 단체를 periods에도 올립니다.
       · 모든 단체(실권 정권 · 붕당 · 정당 · 세력 · 자유 글 — 연합은 빼고) = 든 나라에 접혀 든 숨은 띠. 처음에는 든 나라 꼬리표 안(집권 · 실권 층)에만 보이고
         플래그 창에서 펼칠 때만 제 줄에 선다(감독 2026-10-15 "정권 등 숨김 펼침은 플래그에" — 실권 정권도 따로 줄을 두지 않는다). 꼴: 실권 정권은 군벌(모따기 꼬리표),
         그 밖은 부흥 · 저항(둥근 끝 꼬리표). 든 나라의 단체 펼치기
         (`groups:<나라 uid>` 변형 — 웹 줄 배치의 expandedGroups)를 켜야 그 나라 밑 제 줄에 섭니다. 있던 나라가 기간을 두고 여럿이면 줄마다 한 토막.
       단체 쪽(든 나라 띠의 집권 · 실권 칸 · 단체 창 · 계보)은 그대로이고, 띠는 groupUid로 그 단체를 가리킵니다. 저장 파일에는 들지 않습니다(모델만). */
    if (opts.groupBands) {
      for (const g of groupMap.values()) {
        if (!g.track || g.start == null || g.type === 'coalition') continue;
        const rows = HT.readPolityRows(g.within);
        if (!rows.length) continue;
        const regime = g.type === 'regime';
        const base = { name: g.name, track: g.track, color: g.color, description: g.description, wiki: g.wiki };
        for (const k of ['names', 'historicity']) if (g[k] != null) base[k] = g[k];
        const put = (id, extra, partOf) => {
          const uid = `${g.uid}~${id}`;
          periodMap.set(uid, derive(Object.assign({}, base, extra, { id: `${g.id}~${id}`, partOf, kind: 'period', itemKind: 'period', polityKind: regime ? 'warlord' : 'movement', uid, packId: g.packId, packName: g.packName, groupUid: g.uid })));
        };
        const span = {};
        for (const k of ['start', 'end', 'ongoing', 'startUnknown', 'endUnknown', 'startRange', 'endRange', 'startAt', 'endAt']) if (g[k] != null) span[k] = g[k];
        // 숨은 단체 띠: 있던 나라 줄마다 한 토막(그 줄의 기간 — 비우면 단체의 처음 · 끝) · 그 나라에 접혀 듦(nest — 기간 없는 소속 하나라 singleHost)
        const dated = rows.length > 1 || rows.some(r => r.start != null || r.end != null);
        // 꼬리표의 갈래 딱지는 단체의 갈래(붕당 · 정당 · 세력 …) · 앞선 단체(from)는 승계로(갈라짐 · 합쳐짐 — 펼친 단체끼리 이어지고, 이어진 것은 한 줄에 선다).
        // 토막이 하나인 단체끼리만 잇는다(옮겨 앉는 단체의 토막 잇기는 옮겨 앉기 조각에서).
        base.groupKind = (HT.groupTypeName(g.type) || '').split('·')[0];
        if (!dated) {
          const ofGroup = ref => [...groupMap.values()].find(x => x !== g && (x.uid === ref || (x.packId === g.packId && (x.id === ref || x.name === ref)))) || [...groupMap.values()].find(x => x !== g && x.name === ref);
          base.succeeds = (Array.isArray(g.from) ? g.from : []).map(f => ofGroup(f.group)).filter(Boolean).map(src => ({ from: `${src.uid}~band`, type: 'direct' }));
        }
        rows.forEach((r, i) => {
          const seg = dated ? Object.assign({}, span, r.start != null ? { start: r.start, startUnknown: undefined, startRange: undefined, startAt: undefined } : null, r.end != null ? { end: r.end, ongoing: undefined, endUnknown: undefined, endRange: undefined, endAt: undefined } : null) : span;
          if (seg.end != null && seg.end < seg.start) return;
          put(dated ? `seg${i}` : 'band', seg, [{ polity: r.polity, track: r.track, nest: true }]);
        });
      }
    }
    const periods = [...periodMap.values()];
    const events = [...eventMap.values()];
    /* 내가 만든 항목: HT.USER_LISTS의 목록을 차례로 — 종류마다 모델 항목으로 바꾸는 법은 아래 표 (표에 없는 종류는 조용히 빠지지 않고 오류) */
    const USER_ITEM = {
      period: p => {
        const o = deco(p, HT.USER_PACK, 'period', { isUser: true, polityKind: HT.kindOf(p), itemKind: 'period' });
        if (o.leaders) HT.numberLeaders(o.leaders);
        return o;
      },
      organ: g => deco(HT.organAsPeriod(g), HT.USER_PACK, 'period', { isUser: true, polityKind: 'overlay', itemKind: 'organ' }),
      culture: c => deco(HT.cultureAsPeriod(c), HT.USER_PACK, 'period', { isUser: true, polityKind: 'culture', itemKind: 'culture' }),
      dynasty: d => deco(HT.dynastyAsPeriod(d), HT.USER_PACK, 'period', { isUser: true, polityKind: 'dynasty', itemKind: 'dynasty' }),
      event: e => deco(e, HT.USER_PACK, 'event', { isUser: true, itemKind: 'event' }),
    };
    const figures = [...figureMap.values()];
    USER_ITEM.figure = f => decoFigure(f, HT.USER_PACK, { isUser: true });
    for (const { list, kind } of HT.USER_LISTS) {
      const items = (user && user[list]) || [];
      if (items.length && !USER_ITEM[kind]) throw new Error(`내 데이터의 "${list}" 목록을 모델에 넣는 법이 없습니다.`);
      for (const raw of items) {
        const o = USER_ITEM[kind](raw);
        (o.kind === 'figure' ? figures : o.kind === 'event' ? events : periods).push(o);
      }
    }
    /* 조약 = treaty 칸이 있는 사건 — 패치 · 내 수정이 조약 규격을 얹거나 뗄 수 있으므로 모두 끝난 여기서 가립니다 (HT.itemKindOf가 이 값을 먼저 봄) */
    for (const p of periods) if ('treaty' in p) delete p.treaty; // 시대 쪽(내 수정 · 내 항목)에 든 treaty는 버림 — 모델의 사본이라 원래 자료는 그대로
    for (const e of events) e.itemKind = e.treaty ? 'treaty' : 'event';
    events.sort((a, b) => a.start - b.start);

    for (const x of periods.concat(events)) if (!tracks.has(x.track)) addTrack({ id: x.track, name: x.track });
    for (const e of events) {
      const cid = e.category || 'etc';
      if (!categories.has(cid)) addCat({ id: cid, name: cid === 'etc' ? '기타' : cid, color: '#a4b1b7' });
      e.category = cid;
      e.color = categories.get(cid).color;
    }

    /* 정권 띠: 트랙별로 색을 배정하고(파스텔로 맞춤), 사건을 자기 정권에 소속시킵니다 */
    const periodsByTrack = new Map();
    for (const p of periods) {
      if (!periodsByTrack.has(p.track)) periodsByTrack.set(p.track, []);
      periodsByTrack.get(p.track).push(p);
    }
    for (const list of periodsByTrack.values()) {
      list.sort((a, b) => a.start - b.start || a.endY - b.endY);
      list.forEach((p, i) => {
        if (!p.color) p.colorAuto = true; // 짐작으로 배정한 색 — 수정 폼은 "따로 지정"을 끈 채로 열고, 패치 비교는 색이 없던 것으로 봅니다 (트랙에 띠가 늘면 배정 색이 바뀌므로)
        p.color = HT.pastel(p.color || HT.POLITY_PALETTE[i % HT.POLITY_PALETTE.length]);
      });
    }

    /* 민족 연결: people에 적힌 id·이름을 찾고, 없으면 그 이름으로 만듭니다 */
    for (const p of periods) {
      p.polityKind = HT.kindOf(p);
      const ref = p.people ? String(p.people).trim() : '';
      if (!ref) {
        p.peopleId = null;
        continue;
      }
      let pe = peoples.get(ref) || [...peoples.values()].find(x => x.name === ref);
      if (!pe) {
        addPeople({ id: `auto-${HT.hash(ref)}`, name: ref, auto: true });
        pe = peoples.get(`auto-${HT.hash(ref)}`);
      }
      p.peopleId = pe.id;
      p.peopleName = pe.name;
      p.peopleColor = pe.color;
    }
    /* 민족 계층: parent(대명제)를 따라 뿌리까지의 경로를 만듭니다 (순환은 끊음) */
    const findPeople = ref => peoples.get(ref) || [...peoples.values()].find(x => x.name === ref) || null;
    for (const pe of peoples.values()) {
      const parent = pe.parent ? findPeople(pe.parent) : null;
      pe.parentId = parent && parent !== pe ? parent.id : null;
    }
    for (const pe of peoples.values()) {
      const path = [];
      const seen = new Set();
      let cur = pe;
      while (cur && !seen.has(cur.id)) {
        seen.add(cur.id);
        path.unshift(cur);
        cur = cur.parentId ? peoples.get(cur.parentId) : null;
      }
      pe.path = path.map(x => x.id);
      pe.depth = path.length - 1;
    }
    for (const pe of peoples.values()) pe.children = [...peoples.values()].filter(x => x.parentId === pe.id).map(x => x.id);
    for (const p of periods) {
      const pe = p.peopleId ? peoples.get(p.peopleId) : null;
      p.peoplePath = pe ? pe.path.map(id => peoples.get(id)) : [];
    }

    /* 소속(partOf): 연맹의 구성국, 종속국의 종주국, 조직체가 속한 나라 (같은 트랙 우선).
       여러 개면 차례로 예속된 것(옥저: 고조선 → 현도군 → 낙랑 → 고구려)이며 기간을 적을 수 있습니다 */
    for (const p of periods) {
      p.members = [];
      p.hosts = [];
      p.dynasties = [];
    }
    for (const p of periods) {
      /* 칸의 미정: 시작이 미정인 소속은 앞 소속의 끝에서, 끝이 미정이면 다음 소속의 시작까지 (HT.placeCells — 모르면 비운 끝처럼 정권의 처음 · 끝).
         이어 붙이는 것은 차례로 예속된 시대의 소속뿐 — 왕조가 다스린 정권(polities)과 기관이 얹힌 정권(host)은 나란히 갈 수 있어,
         미정인 쪽을 비운 쪽처럼 둡니다(그 항목 기간의 처음 · 끝 — 표시 startUnknown · endUnknown만 남음) */
      const refs = HT.readPartOf(p.partOf, { relation: HT.itemKindOf(p) === 'period' }); // 소속 관계 · 놓는 자리는 시대의 소속에서만 (기관 · 왕조는 받지 않음)
      const parallel = p.polityKind === 'dynasty' || p.polityKind === 'overlay';
      for (const ref of parallel ? refs : HT.placeCells(refs, p)) {
        const same = periodsByTrack.get(p.track) || [];
        const host =
          same.find(q => q !== p && (q.name === ref.polity || q.id === ref.polity || q.uid === ref.polity)) ||
          periods.find(q => q !== p && (q.name === ref.polity || q.uid === ref.polity || (q.packId === p.packId && q.id === ref.polity)));
        if (!host || host.hosts.some(h => h.host === p)) continue; // 서로 소속은 끊음
        p.hosts.push(Object.assign({ host, start: ref.start ?? null, end: ref.end ?? null, note: ref.note || '', relation: ref.relation || '', nest: ref.nest ?? null }, ref.startUnknown ? { startUnknown: true } : null, ref.endUnknown ? { endUnknown: true } : null, HT.uncOf(ref))); // 확실성 · 연대 폭 · 이설 (소속 줄 · 왕조 구간 — 디테일 건의 4)
        if (p.polityKind !== 'dynasty' && !host.members.includes(p)) host.members.push(p); // 왕조는 딸린 정권이 아님 (아래 host.dynasties)
      }
      p.hosts.sort((a, b) => (a.start ?? p.start) - (b.start ?? p.start));
      // 상위 정권이 하나뿐이고 기간이 없으면 그 띠 아래에 접혀 들어갑니다. 여럿이거나 기간이 있으면 제 줄에 서고, 상국 띠에 속국 이름표가 달립니다(timeline.js depProxies).
      // 놓는 자리(nest)를 적었으면 그대로(true = 접기 · false = 제 줄), 비웠으면 소속 관계가 없거나 구성국일 때만 접힙니다 — 그 밖의 관계는 제 줄.
      // 이 규칙은 여기 한 곳에만 둡니다: 연표의 접힘 · 속국 이름표(접히는 소속은 이름표 없음) · 그림 내보내기 · 딸린 정권 단추의 개수 · 찾아가기가 모두 singleHost 하나를 봅니다
      // 연표는 같은 트랙 안에서만 접으므로, 관계를 적은 소속의 상위 정권이 다른 트랙에 있으면 접지 않고 제 줄에 서서 상국 띠에 이름표가 달립니다(관계가 어디에도 안 보이는 일이 없게).
      // 관계를 적지 않은 옛 자료는 예전 그대로(다른 트랙의 상위 정권 하나 · 기간 없음이면 접힌 것으로 쳐 이름표 없음).
      // 칸의 미정: 끝이나 시작을 "미정"이라 적은 소속도 기간이 있는 것으로 — 이름표의 그쪽 끝이 옅어짐
      const h0 = p.hosts[0];
      p.singleHost = p.hosts.length === 1 && h0.start == null && h0.end == null && !h0.startUnknown && !h0.endUnknown && (h0.nest === true || (h0.nest == null && (!h0.relation || h0.relation === 'member'))) && (!h0.relation || h0.host.track === p.track);
      p.partOfUid = p.hosts.length ? p.hosts[0].host.uid : undefined;
      p.partOfName = p.hosts.length ? p.hosts[0].host.name : undefined;
    }
    for (const p of periods) p.members.sort((a, b) => a.start - b.start);
    /* 칸의 미정: 이어지는 칸 목록(HT.CELL_CHAIN — 지도자 · 내각 · 연호 …)에서 미정인 쪽의 자리를 잡습니다 (도읍은 아래 HT.resolveCapitals).
       패치 · 내 수정이 끝난 뒤, 왕조 짐작(시작한 해)보다 먼저 — 짐작한 자리는 startAuto · endAuto */
    for (const p of periods) for (const k of HT.CELL_CHAIN) if (p[k] && p[k].length) p[k] = HT.placeCells(p[k], p);
    /* 왕조: 다스린 정권마다 왕조 구간을 달고(host.dynasties), 왕조를 적지 않은 지도자는 시작한 해의 왕조로 채웁니다.
       지도자 칸은 같은 왕조끼리 하나의 긴 칸으로 이어지고 왕조가 바뀌는 곳에서 끊깁니다 */
    for (const d of periods) {
      if (d.polityKind !== 'dynasty') continue;
      for (const h of d.hosts) {
        const s = Math.max(h.start ?? d.start, h.host.start);
        const e = Math.min(h.end ?? d.endY, h.host.endY);
        if (e < s) continue;
        h.host.dynasties.push(Object.assign({ dynasty: d, start: s, end: e, note: h.note || '' }, HT.uncOf(h))); // 왕조 구간의 확실성 · 연대 폭 · 이설은 그 다스린 정권 줄의 것
      }
    }
    for (const p of periods) {
      if (!p.dynasties.length) continue;
      p.dynasties.sort((a, b) => a.start - b.start || a.end - b.end);
      if (!p.leaders || !p.leaders.length) continue;
      p.leaders = p.leaders.map(c => {
        if (c.dynasty) {
          const ref = p.dynasties.find(x => x.dynasty.name === c.dynasty || x.dynasty.id === c.dynasty || x.dynasty.uid === c.dynasty);
          return ref && ref.dynasty.name !== c.dynasty ? Object.assign({}, c, { dynasty: ref.dynasty.name }) : c;
        }
        const hit = p.dynasties.find(x => x.start <= c.start && c.start < x.end) || p.dynasties.find(x => x.start <= c.start && c.start <= x.end);
        return hit ? Object.assign({}, c, { dynastyAuto: hit.dynasty.name }) : c; // 짐작한 왕조는 따로 (폼에는 적힌 것만)
      });
    }
    /* 지명 사전(형식 버전 3): 도읍의 도시를 지명의 id로 적었으면 모델의 사본에서는 그 지명의 이름으로 — 같은 도시는 같은 이름으로 이어지는 규칙(도읍 줄 · 노선도의 환승역)이
       그대로 통하게. 사전이 없거나 이름으로 적은 도읍은 그대로입니다(옛 파일은 1px도 같게) */
    {
      const ids = new Map();
      for (const pack of packs) for (const pl of pack.places || []) if (!ids.has(pl.id)) ids.set(pl.id, pl);
      const names = new Set([...ids.values()].map(pl => pl.name));
      /* 어느 지명인지(placeId — 같은 이름의 지명이 여럿이어도 원어 · 쓰인 곳이 바른 지명에)와 칸 문서의 이름(docName — 원문 id: 지명 이름을 바꾸거나 사전 DLC를 켜고 꺼도 문서 열쇠가 그대로)을 함께 남깁니다 */
      const byId = c => {
        const n = HT.normalizeCapital(c);
        const pl = n && !names.has(n.city) ? ids.get(n.city) : null;
        return pl ? Object.assign(n, { city: pl.name, placeId: pl.id }, n.as ? null : { docName: n.city }) : c;
      };
      if (ids.size) for (const p of periods) if (p.capitals && p.capitals.length) p.capitals = p.capitals.map(byId);
    }
    /* 도읍: 역할·끝·표시 이름을 채웁니다 (HT.resolveCapitals) */
    for (const p of periods) if (p.capitals && p.capitals.length) p.capitals = HT.resolveCapitals(p);
    /* 시기 구분(학계): 빈 경계를 채운 모델 전용 사본 (원문 p.phases는 그대로 — 폼은 원문으로 채움) */
    for (const p of periods) {
      const ph = p.phases && HT.itemKindOf(p) === 'period' ? HT.resolvePhases(p) : null;
      if (ph) p.phaseSchemes = ph;
    }
    /* 지위: 켠 DLC들의 사전 + 내장 사전(HT.mergeRankDefs), 정권마다 끝을 채운 지위 구간(p.rankSpans — 지도자에게만 적혔으면 끌어냄)과
       지위를 적지 않은 지도자의 시작한 해의 지위(rankAuto). 원문 p.ranks · leaders[].rank는 그대로 (짐작 값은 다른 이름에) */
    const rankDefs = HT.mergeRankDefs(packs);
    HT.lastRankDefs = rankDefs; // 폼의 지위 자동 완성(HT.rankNameOptions)이 씀 — 마지막으로 만든 모델의 사전
    for (const p of periods) {
      const rk = HT.itemKindOf(p) === 'period' && (p.ranks || p.leaders) ? HT.resolveRanks(p, rankDefs) : null;
      if (!rk) continue;
      p.rankSpans = rk.spans;
      if (rk.leaders) p.leaders = rk.leaders;
    }
    /* 종교(6단계 D8): 정권마다 끝을 채운 종교 구간(p.faithSpans — 지위 변천과 같은 꼴 · 사전 없음). 원문 p.faiths는 그대로 */
    for (const p of periods) {
      const spans = HT.itemKindOf(p) === 'period' && p.faiths ? HT.resolveFaiths(p) : null;
      if (spans) p.faithSpans = spans;
    }
    /* 사건의 소속 정권을 해로 짐작할 때 기관·왕조는 고르지 않습니다 (그 해의 나라 띠에 놓이게). 직접 적으면 그대로 */
    const ASIDE = new Set(['overlay', 'dynasty']);
    /* 연도만 적은 끝(정수 · 날짜 글 없음)은 그해 끝까지 품습니다 — 1910년에 끝난 나라의 1910년 8월 사건도 그 나라에 */
    const endIn = HT.endIn;
    for (const e of events) {
      const list = periodsByTrack.get(e.track) || [];
      let target = null;
      if (e.polity) {
        // id · uid · 이름 아무거나로 지정할 수 있습니다
        const want = e.polity.includes('/') ? e.polity : `${e.packId}/${e.polity}`;
        target = list.find(p => p.uid === want || p.id === e.polity || p.name === e.polity) || null;
      }
      if (!target) {
        const hit = list.filter(p => !ASIDE.has(p.polityKind) && !p.groupUid && p.start <= e.start && e.start <= endIn(p)); // 단체의 띠(조각 ④)도 고르지 않음 — 그 해의 나라 띠에
        if (hit.length === 1) target = hit[0];
        else if (hit.length > 1) {
          const title = e.title || '';
          // ① 제목에 정권 이름이 들어 있으면 그 정권 ② 기간 안에 온전히 든 것 ③ 끝나는 해에 든 것
          const score = p => (title.includes(p.name) ? 100 : 0) + (p.start < e.start && e.start < p.endY ? 10 : 0) + (HT.yearOf(e.start) === HT.yearOf(p.endY) ? 5 : 0);
          target = hit.reduce((a, b) => {
            const d = score(b) - score(a);
            if (d !== 0) return d > 0 ? b : a;
            return b.endY - b.start < a.endY - a.start ? b : a;
          });
        }
      }
      e.polityUid = target ? target.uid : null;
      e.polityName = target ? target.name : null;
      e.polityColor = target ? target.color : null;
    }

    /* 승계 관계: 이름·id로 적힌 선대 정권을 찾아 연결합니다 (같은 트랙 우선) */
    for (const p of periods) {
      if (p.polityKind === 'culture' && Array.isArray(p.successors) && p.successors.every(s => typeof s === 'string')) p.successorNames = p.successors;
      p.successors = [];
      p.predecessors = [];
    }
    for (const p of periods) {
      for (const link of p.succeeds || []) {
        const same = periodsByTrack.get(p.track) || [];
        const from =
          same.find(q => q !== p && (q.name === link.from || q.id === link.from || q.uid === link.from)) ||
          periods.find(q => q !== p && (q.name === link.from || q.uid === link.from));
        if (!from || p.predecessors.some(e => e.from === from)) continue; // 한 쌍에는 선 하나 (이름 · id로 같은 선대를 두 번 가리켜도)
        const edge = { from, to: p, type: link.type, note: link.note || '' };
        if (link.type === 'partial') Object.assign(edge, { degree: HT.succDegree(link.degree) || HT.SUCC_DEGREE_DEFAULT, parts: (link.parts || []).slice() }); // 부분 승계: 정도(선의 진한 가닥 수) · 이어진 것
        p.predecessors.push(edge);
        from.successors.push(edge);
      }
    }
    /* 문화 쪽에서 적은 승계국(successors: ["고조선"]) — 그 국가 줄 밑에 바탕 띠로 깔립니다 */
    for (const c of periods) {
      if (c.polityKind !== 'culture' || !c.successorNames) continue;
      for (const ref of c.successorNames) {
        const same = periodsByTrack.get(c.track) || [];
        const to = same.find(q => q !== c && (q.name === ref || q.id === ref || q.uid === ref)) || periods.find(q => q !== c && (q.name === ref || q.uid === ref));
        if (!to || to.predecessors.some(e => e.from === c)) continue;
        const edge = { from: c, to, type: 'indirect', note: '' };
        to.predecessors.push(edge);
        c.successors.push(edge);
      }
    }

    /* 부모·자식 사건 (큰 전쟁 안의 전투 등) */
    const eventByUid = new Map(events.map(e => [e.uid, e]));
    const findEvent = (ref, packId) => {
      const want = ref.includes('/') ? ref : `${packId}/${ref}`;
      return eventByUid.get(want) || events.find(x => x.packId === packId && x.title === ref) || events.find(x => x.title === ref) || null;
    };
    for (const e of events) {
      if (!e.parent) continue;
      const parent = findEvent(e.parent, e.packId);
      if (!parent || parent === e) continue;
      e.parentUid = parent.uid;
      e.parentTitle = parent.title;
      if (!e.polity) {
        e.polityUid = parent.polityUid;
        e.polityName = parent.polityName;
        e.polityColor = parent.polityColor;
      }
      (parent.children = parent.children || []).push(e);
    }
    for (const e of events) if (e.children) e.children.sort((a, b) => a.start - b.start);

    /* 공동 사건 — 같은 사건을 여러 정권·나라 줄에 함께 찍습니다 */
    const findPolity = (trackId, ref, year, preferBig) => {
      const list = periodsByTrack.get(trackId) || [];
      if (ref) {
        const p = list.find(x => x.name === ref || x.id === ref || x.uid === ref);
        if (p) return p;
      }
      const hit = list.filter(p => !ASIDE.has(p.polityKind) && !p.groupUid && p.start <= year && year <= endIn(p)); // 단체의 띠(조각 ④)는 고르지 않음
      if (!hit.length) return null;
      // 같은 트랙 안에서는 가장 구체적인(짧은) 정권, 다른 나라로 넘어갈 때는 대표 정권(가장 긴 것)
      return hit.reduce((a, b) => (preferBig ? (b.endY - b.start > a.endY - a.start ? b : a) : b.endY - b.start < a.endY - a.start ? b : a));
    };
    /* 조약의 당사국 { track?, polity } → 연표의 정권: 트랙을 적었으면 그 트랙에서, 비웠으면 이 사건의 트랙 → 모든 트랙 순으로 이름 · id를 찾고,
       이름으로 못 찾으면 적은 트랙(트랙을 비웠으면 이름이 같은 트랙)의 그 해 정권으로. 찾은 당사국은 함께 겪은 자리에 더합니다(add).
       풀어낸 것은 모델 전용 칸(x.treatyRefs)에만 둡니다 — 원래 treaty는 그대로 (수정 폼 · 내보내기 비교가 원래 칸을 보므로) */
    const treatyParties = e =>
      ((HT.readTreaty({ parties: e.treaty.parties }) || {}).parties || []).map(pt => {
        const ref = pt.polity || '';
        const tid = pt.track || '';
        const is = q => q.polityKind !== 'dynasty' && (q.name === ref || q.id === ref || q.uid === ref);
        let p = ref ? (periodsByTrack.get(tid || e.track) || []).find(is) || (tid ? null : periods.find(is)) || null : null;
        const byName = !!p;
        if (!p) {
          const tr = tid ? tracks.get(tid) : [...tracks.values()].find(t => t.id === ref || t.name === ref);
          if (tr) p = findPolity(tr.id, null, e.start, tr.id !== e.track);
        }
        return { p, track: p ? p.track : tid || e.track, polity: ref, uid: p ? p.uid : null, name: p ? p.name : ref || (tracks.get(tid) || {}).name || tid, color: p ? p.color : null, byName, side: pt.side ?? null, role: pt.role || '', signatories: HT.readSigners(pt.signatories) };
      });
    /* 조약의 제 자리(첫 자리)도 당사국 가운데서: 정권을 적지 않은 조약이 제 트랙에 당사국을 두면 그 정권이 제 자리입니다 (해로 짐작한 더 짧은 정권 대신) */
    for (const e of events) {
      if (!e.treaty || e.polity) continue;
      const own = treatyParties(e).find(x => x.p && x.track === e.track);
      if (own) Object.assign(e, { polityUid: own.uid, polityName: own.name, polityColor: own.color });
    }
    for (const e of events) {
      const places = [{ track: e.track, polityUid: e.polityUid, polityName: e.polityName, polityColor: e.polityColor }];
      const add = (trackId, p) => {
        if (places.some(x => x.track === trackId && x.polityUid === (p ? p.uid : null))) return;
        places.push({ track: trackId, polityUid: p ? p.uid : null, polityName: p ? p.name : null, polityColor: p ? p.color : null });
      };
      for (const ref of e.polities || []) add(e.track, findPolity(e.track, ref, e.start));
      for (const t of e.tracks || []) {
        const [tid, ref] = String(t).split(':');
        if (tid === e.track || !tracks.has(tid)) continue;
        add(tid, findPolity(tid, ref, e.start, true));
      }
      if (e.treaty) e.treatyRefs = { parties: treatyParties(e).map(({ p, ...ref }) => (p && add(p.track, p), ref)) }; // 조약: 찾은 당사국도 함께 겪은 자리에
      e.placements = places;
      e.shared = places.length > 1;
      if (e.shared) e.sharedWith = places.slice(1).map(p => p.polityName || (tracks.get(p.track) || {}).name || p.track);
    }
    /* 조약의 관련: 끝낸 전쟁(concludes) · 대체한 조약(supersedes) — 사건의 제목 · id. 거꾸로 가리키는 것(그 전쟁을 끝낸 조약 · 그 조약을 대체한 조약)은
       가리켜진 사건의 모델 전용 칸 treatyBackRefs에 (조약이 아닌 사건에도 붙으므로 treatyRefs와 따로) */
    for (const e of events) {
      if (!e.treatyRefs) continue;
      for (const [key, back] of [['concludes', 'concludedBy'], ['supersedes', 'supersededBy']]) {
        const ref = e.treaty[key] ? String(e.treaty[key]) : '';
        const hit = ref ? findEvent(ref, e.packId) : null;
        e.treatyRefs[key] = hit && hit !== e ? hit.uid : null;
        if (!e.treatyRefs[key]) continue;
        const b = hit.treatyBackRefs || (hit.treatyBackRefs = { concludedBy: [], supersededBy: [] });
        b[back].push(e.uid);
      }
    }

    /* 인물 — 패치 · 내 수정이 모두 끝난 지금에야 시기와 섬긴 정권을 풉니다.
       · 섬긴 기록(service)의 정권: 그 줄의 track(비우면 인물의 트랙)에서 id · 이름으로. 못 찾으면 그 줄은 상세에 글로만 남습니다(polity: null).
       · 활동 시기: 적은 start · end → 없으면 섬긴 기간의 합 → 그것도 없으면 생몰. 짐작한 쪽은 startAuto · endAuto로 표시합니다
         (수정 폼은 그 칸을 비워 둠 — 한 번 열어 저장해도 짐작이 자료로 굳지 않게). 파일의 end 칸은 건드리지 않고 끝은 endY에 둡니다.
       · 섬긴 기록이 하나도 없으면 활동 가운데 해의 같은 트랙 정권 하나에 자동으로 놓습니다(auto: true).
       · services[] = 연표가 그리는 활동 막대: 구간을 그 정권의 기간 안으로 자른 것(shown: 겹치는 구간이 있는가) */
    for (const p of periods) p.servedBy = []; // 이 정권을 섬긴 인물 [{ figure, service }] — 모델 전용 (파일의 칸 이름과 겹치지 않게: 사건의 figures는 관련 인물 이름 목록)
    /* 계보 전용 인물(D1 확정 설계 2-4 가): 패치 · 내 수정이 끝난 지금 떼어 model.lineageFigures로 — 띠의 인물 단 · 정권의 servedBy · 활동 막대 · 자동 놓기에 들지 않아
       띠 높이 · 띠 그리기 비용이 사람 수와 무관합니다. 들어가는 곳은 byUid(인물 창 · 문서 링크) · 사람 자리(linkPeople) · 사건의 관련 인물 찾기 · 검색.
       생몰 · 활동 날짜가 있을 때만 spanMin · spanMax를 두고(없으면 null — 사람 잇기의 '겹친 시기'에 들지 않게) */
    const lineageFigures = [];
    {
      const keep = [];
      for (const f of figures) (f.lineageOnly === true ? lineageFigures : keep).push(f);
      if (lineageFigures.length) {
        figures.length = 0;
        for (const f of keep) figures.push(f);
      }
      for (const f of lineageFigures) {
        const ts = [f.birth, f.start, f.end, f.death].filter(t => typeof t === 'number' && isFinite(t));
        f.spanMin = ts.length ? Math.min(...ts) : null;
        f.spanMax = ts.length ? Math.max(...ts) : null;
        f.certainty = 'accepted';
        f.events = [];
        f.services = [];
        f.polityUid = f.polityName = f.polityColor = null;
        f.color = (tracks.get(f.track) || {}).color || '#a4b1b7';
      }
    }
    const figurePolity = (trackId, ref, year) => {
      const list = (periodsByTrack.get(trackId) || []).filter(p => p.polityKind !== 'dynasty');
      const byId = list.find(p => p.uid === ref || p.id === ref);
      if (byId) return byId;
      const named = list.filter(p => p.name === ref);
      return (year != null && named.find(p => p.start <= year && year <= endIn(p))) || named[0] || null; // 같은 이름의 정권이 여럿이면 그 시기의 것
    };
    const minOf = list => (list.length ? list.reduce((a, b) => (b.t < a.t ? b : a)) : null);
    const maxOf = list => (list.length ? list.reduce((a, b) => (b.t > a.t ? b : a)) : null);
    for (const f of figures) {
      const raw = Array.isArray(f.service) ? f.service : [];
      const pt = (t, at) => (t == null ? null : { t, at: at || undefined });
      const from = pt(f.start, HT.atOf(f, 'start')) || minOf(raw.map(s => pt(s.start ?? s.end, s.start != null ? s.startAt : s.endAt)).filter(Boolean)) || pt(f.birth, f.birthAt) || pt(f.end, f.endAt) || pt(f.death, f.deathAt);
      if (!from) continue; // 날짜가 하나도 없는 인물(내 수정에서 모두 지운 경우)은 놓을 자리가 없습니다
      f.startAuto = f.start == null;
      f.start = from.t;
      f.startAt = from.at;
      let to = f.ongoing ? pt(Math.max(HT.NOW_T, f.start)) : pt(f.end, HT.atOf(f, 'end'));
      f.endAuto = !to;
      if (!to) to = maxOf(raw.map(s => pt(s.end ?? s.start, s.end != null ? s.endAt : s.startAt)).filter(Boolean)) || pt(f.death, f.deathAt) || from;
      f.endY = to.t < f.start ? Math.max(f.start, HT.endBound(to.t, to.at)) : to.t;
      f.endYAt = to.at;
      f.certainty = 'accepted';
      f.spanMin = Math.min(f.start, f.birth ?? f.start);
      f.spanMax = Math.max(f.endY, f.death ?? f.endY);
      f.events = [];
      f.services = raw.map(s => {
        const a = s.start ?? f.start;
        const b = s.end ?? f.endY;
        const trackId = s.track || f.track;
        const p = figurePolity(trackId, s.polity, (a + b) / 2);
        const o = { polity: p, polityUid: p ? p.uid : null, polityName: p ? p.name : s.polity, track: p ? p.track : trackId, color: p ? p.color : null, office: s.office || '', note: s.note || '', given: s.start != null || s.end != null, from: a, fromAt: s.start != null ? s.startAt : f.startAt, to: b, toAt: s.end != null ? s.endAt : f.endYAt, auto: false };
        /* 칸의 미정: 그 줄의 시작 · 끝이 미정이거나, 비워서 활동 시기를 물려받았는데 활동 시기의 그쪽이 미정이면 — 섬긴 기간 글 · 막대 설명이 '미정', 막대의 그쪽 끝이 옅어짐 */
        if (s.startUnknown || (s.start == null && f.startUnknown)) o.fromUnknown = true;
        if (s.endUnknown || (s.end == null && f.endUnknown)) o.toUnknown = true;
        Object.assign(o, HT.uncOf(s)); // 그 줄의 확실성 · 연대 폭 · 이설 (디테일 건의 4)
        o.start = p ? Math.max(a, p.start) : a;
        o.endY = p ? Math.min(b, p.endY) : b;
        o.shown = !!p && o.endY >= o.start;
        return o;
      });
      if (!raw.length) {
        const p = findPolity(f.track, null, (f.start + f.endY) / 2);
        if (p) f.services.push(Object.assign({ polity: p, polityUid: p.uid, polityName: p.name, track: p.track, color: p.color, office: '', note: '', given: false, from: f.start, fromAt: f.startAt, to: f.endY, toAt: f.endYAt, auto: true, start: Math.max(f.start, p.start), endY: Math.min(f.endY, p.endY), shown: true }, f.startUnknown ? { fromUnknown: true } : null, f.endUnknown ? { toUnknown: true } : null));
      }
      for (const s of f.services) if (s.polity) s.polity.servedBy.push({ figure: f, service: s });
      const first = f.services.find(s => s.polity) || null;
      f.polityUid = first ? first.polityUid : null;
      f.polityName = first ? first.polityName : null;
      f.polityColor = first ? first.color : null;
      f.color = f.polityColor || (tracks.get(f.track) || {}).color || '#a4b1b7';
    }
    for (let i = figures.length - 1; i >= 0; i--) if (figures[i].endY == null) figures.splice(i, 1);
    figures.sort((a, b) => a.start - b.start || a.endY - b.endY);
    for (const p of periods) p.servedBy.sort((a, b) => a.service.start - b.service.start || (b.figure.importance || 2) - (a.figure.importance || 2));
    /* 사건의 관련 인물(events[].figures — 이름 · 다른 이름 · id): 풀어낸 것은 모델 전용 figureRefs에 두고 원래 칸은 그대로. 인물 쪽에는 역으로 events.
       계보 전용 인물도 찾습니다(D1). 이름 · 다른 이름 · uid를 표 하나로 모아 참조마다 인물 전체를 훑지 않습니다(D1 6-3 ⑥ — 후보의 차례는 인물 차례 그대로) */
    const figAll = figures.concat(lineageFigures);
    let figIndex = null; // 사건에 관련 인물이 있을 때만 짓습니다
    const findFigure = (ref, e) => {
      if (!figIndex) {
        figIndex = new Map();
        const add = (n, k) => {
          if (!n) return;
          const l = figIndex.get(n);
          if (!l) figIndex.set(n, [k]);
          else if (l[l.length - 1] !== k) l.push(k);
        };
        figAll.forEach((f, k) => {
          add(f.uid, k);
          add(f.name, k);
          if (f.aka) for (const n of f.aka) add(n, k);
        });
      }
      const want = ref.includes('/') ? ref : `${e.packId}/${ref}`;
      const hit = [...new Set((figIndex.get(want) || []).concat(figIndex.get(ref) || []))].sort((a, b) => a - b).map(k => figAll[k]).filter(f => f.uid === want || f.name === ref || (f.aka || []).includes(ref));
      if (hit.length < 2) return hit[0] || null;
      const score = f => (f.uid === want ? 100 : 0) + (f.track === e.track ? 10 : 0) + (f.spanMin <= e.start && e.start <= f.spanMax + 1 ? 5 : 0);
      return hit.reduce((a, b) => (score(b) > score(a) ? b : a));
    };
    for (const e of events) {
      if (!Array.isArray(e.figures) || !e.figures.length) continue;
      e.figureRefs = e.figures.map(name => {
        const f = findFigure(String(name), e);
        if (f && !f.events.includes(e)) f.events.push(e);
        return { name: String(name), uid: f ? f.uid : null };
      });
    }

    const byUid = new Map();
    periods.concat(events).concat(epochs).forEach(x => byUid.set(x.uid, x));
    figures.forEach(x => byUid.set(x.uid, x));
    lineageFigures.forEach(x => byUid.set(x.uid, x)); // 계보 전용 인물도 (인물 창 · 문서 링크 · 세계표 카드)
    for (const e of epochs) {
      const tr = e.track ? tracks.get(e.track) : null;
      e.trackName = tr ? tr.name : '';
    }
    /* 대범위 (docs/구상-체제-확장.md 7 · 8-4 바): 구성 정권 · 상징적 본국 · 시대 구분을 모델 항목으로 풀고, 정권 쪽에 역참조(p.scopes · p.hostedScopes · epoch.scopes)를 답니다.
       원문은 memberRefs · hostRef · epochRef에 그대로 두고(members · host · epoch는 모델 항목), 비워 둔 이름 · 기간 · 색은 시대 구분에서 물려받거나
       (없으면) 구성 정권의 범위로 채우되 nameAuto · startAuto · endAuto · colorAuto 표시를 달아 폼이 그 칸을 비워 두게 합니다 (0절 4 — 짐작이 자료로 굳지 않게).
       못 찾은 구성 정권 · 다른 트랙의 정권 · 구성 정권에 든 본국은 대범위의 warnings에 (상세의 '확인할 것') */
    const scopes = [];
    {
      const polityIn = (ref, trackId, packId) => {
        const t = ref.track || trackId;
        const ok = q => q.itemKind === 'period';
        return (
          (periodsByTrack.get(t) || []).find(q => ok(q) && (q.name === ref.polity || q.id === ref.polity || q.uid === ref.polity)) ||
          periods.find(q => ok(q) && (q.uid === ref.polity || (!ref.track && q.packId === packId && q.id === ref.polity))) ||
          null
        );
      };
      const epochOf = (ref, trackId, packId) =>
        epochs.find(e => e.packId === packId && (e.id === ref || e.name === ref) && (!e.track || e.track === trackId)) ||
        epochs.find(e => e.uid === ref) ||
        epochs.find(e => e.name === ref && e.track === trackId) ||
        epochs.find(e => e.name === ref) ||
        null;
      for (const pack of packs) {
        for (const raw of pack.scopes || []) {
          const warnings = [];
          const ep = raw.epoch ? epochOf(raw.epoch, raw.track, pack.id) : null;
          if (raw.epoch && !ep) warnings.push(`시대 구분 "${raw.epoch}"을(를) 찾지 못했습니다.`);
          const hostRef = HT.readScopeRef(raw.host);
          const host = hostRef ? polityIn(hostRef, raw.track, pack.id) : null;
          if (hostRef && !host) warnings.push(`상징적 본국 "${hostRef.polity}"을(를) 연표에서 찾지 못했습니다.`);
          else if (host && host.track !== raw.track) warnings.push(`상징적 본국 "${host.name}"이(가) 다른 트랙에 있어 그 줄 아래에 모이지 않습니다.`);
          const members = [];
          for (const ref of HT.readScopeRefs(raw.members)) {
            const m = polityIn(ref, raw.track, pack.id);
            if (!m) warnings.push(`구성 정권 "${ref.polity}"을(를) 연표에서 찾지 못했습니다.`);
            else if (m === host) warnings.push(`상징적 본국 "${m.name}"이(가) 구성 정권에도 들어 있습니다 — 본국은 모이지 않습니다.`);
            else if (!members.includes(m)) {
              if (m.track !== raw.track) warnings.push(`구성 정권 "${m.name}"은(는) 다른 트랙에 있어 모이지 않습니다 — 구성 정권은 같은 트랙 안에서만 모입니다.`);
              members.push(m);
            }
          }
          members.sort((a, b) => a.start - b.start || a.endY - b.endY);
          const o = Object.assign({}, raw, { kind: 'scope', itemKind: 'scope', uid: `${pack.id}/${raw.id}`, packId: pack.id, packName: pack.name, memberRefs: raw.members, members, hostRef: raw.host ?? null, host, epochRef: raw.epoch ?? null, epoch: ep, warnings, default: raw.default === true });
          if (!o.name) Object.assign(o, { name: ep ? ep.name : '대범위', nameAuto: true });
          if (raw.start == null) {
            const own = members.filter(m => m.track === raw.track);
            const list = own.length ? own : members;
            if (ep) Object.assign(o, { start: ep.start, startAt: ep.startAt, end: ep.end, endAt: ep.endAt, ongoing: ep.ongoing, rangeFrom: 'epoch' });
            else if (list.length) Object.assign(o, { start: Math.min(...list.map(m => m.start)), end: Math.max(...list.map(m => m.endY)), rangeFrom: 'members' });
            else continue; // 기간을 정할 것이 하나도 없음 — 그릴 수 없으므로 모델에 넣지 않습니다 (파일 검사는 이미 통과)
            o.startAuto = o.endAuto = true;
          }
          o.endY = o.ongoing ? Math.max(HT.NOW_T, o.start) : o.end ?? o.start;
          if (!HT.isColor(raw.color)) o.colorAuto = true;
          o.color = HT.pastel(HT.isColor(raw.color) ? raw.color : ep ? ep.color : HT.autoColor(`scope:${o.uid}`));
          o.trackName = tracks.has(o.track) ? tracks.get(o.track).name : o.track;
          o.afterHost = !!host && o.start >= host.endY - 1e-9; // 본국이 이미 끝난 뒤의 대범위(부흥 운동) — 본국 띠에 할거기 칠이 없고, 집합은 본국이 끝난 자리의 오른쪽에
          for (const m of members) (m.scopes || (m.scopes = [])).push(o);
          if (host) (host.hostedScopes || (host.hostedScopes = [])).push(o);
          if (ep) (ep.scopes || (ep.scopes = [])).push(o);
          scopes.push(o);
          byUid.set(o.uid, o);
        }
      }
      scopes.sort((a, b) => a.start - b.start || a.endY - b.endY);
      /* 포개짐(리메이크 2부 · 설계 3-3): 부모 그릇(같은 팩 · 같은 트랙의 대범위 id · 이름) → parent · depth(바깥 0) · children. 고리는 끊고 알림.
         그릇 안 이름표 시대(시대 구분의 within) → epoch.scope · scope.labels(그 그릇 윗변의 둘째 탭 — 날짜 칸에는 싣지 않음) */
      const scopeRef = (ref, packId, trackId) =>
        scopes.find(x => x.packId === packId && x.track === trackId && (x.id === ref || x.name === ref)) || scopes.find(x => x.uid === ref) || null;
      for (const s of scopes) {
        if (!s.within) continue;
        const p = scopeRef(s.within, s.packId, s.track);
        if (!p) s.warnings.push(`부모 그릇 "${s.within}"을(를) 같은 트랙에서 찾지 못했습니다.`);
        else s.parent = p;
      }
      for (const s of scopes) {
        const seen = new Set([s]);
        let depth = 0;
        for (let p = s.parent; p; p = p.parent) {
          if (seen.has(p)) {
            s.warnings.push('부모 그릇이 고리를 이뤄 바깥 그릇으로 둡니다.');
            delete s.parent;
            depth = 0;
            break;
          }
          seen.add(p);
          depth++;
        }
        s.depth = depth;
      }
      for (const s of scopes) if (s.parent) (s.parent.children || (s.parent.children = [])).push(s);
      for (const e of epochs) {
        if (!e.within) continue;
        const sc = scopeRef(e.within, e.packId, e.track) || scopes.find(x => x.packId === e.packId && (x.id === e.within || x.name === e.within)) || null;
        if (!sc) continue;
        e.scope = sc;
        (sc.labels || (sc.labels = [])).push(e);
      }
      for (const s of scopes) if (s.wiki && !docs.has(s.uid)) docs.set(s.uid, { text: s.wiki, packId: s.packId, packName: s.packName });
    }
    /* 단체 · 렌즈의 재료 (형식 버전 3 — docs/구상-연표-확장-10건.md 3-7 · 3-8): 패치 · 내 수정이 모두 끝난 지금 풉니다.
       원문 칸(theme · polity · track · spans · within · from · power · people · members · event)은 그대로 두고 풀어낸 것은 다른 이름에 둡니다(0절 4 — 폼은 원문으로 채움):
       · model.themes — 주제 사전(HT.mergeThemes: 켠 DLC들 → 내장 뼈대) + 사전에 없는 이름으로 적힌 주제(auto: true) · themeMap(id → 주제)
       · model.institutions — 제도(kind · itemKind 'institution'): themeId · themeName · polityItem · spanList(빈 경계를 채운 칸 — 시기 구분과 같은 규칙) · start · endY · color(갈래 색) ·
           sameFamily(같은 주제 · 같은 갈래의 다른 나라 제도) + model.institutionIndex { byTheme(주제 id) · byPolity(나라 uid) · byFamily('주제 id|갈래') } · 나라 쪽 institutionList
       · model.groups — 단체(kind · itemKind 'group'): typeName · withinList · powerSpans · fromList · intoList(이 단체에서 갈라지거나 합쳐 나간 단체) · peopleList · memberList · eventItem
           + 나라 쪽 groupLinks [{ group, role: 'within' | 'member' }] · 사건 쪽 groupRefs(이 사건으로 맺은 단체)
       · 사건의 themeRefs [{ ref, id, name, color, auto }] + model.themeEvents(주제 id → 사건 목록 — 시작 순)
       찾지 못한 나라 · 주제 · 앞선 단체 · 사건, 같은 나라 · 같은 주제의 제도끼리 겹치는 칸, 찾은 구성 나라가 하나뿐인 연합은 그 항목의 warnings에 (상세의 '확인할 것' · 메이커 검사).
       사람 참조(지도자 칸 — 바탕 1)의 풀이는 다른 줄(F1)이 만들므로, 구성원은 인물의 이름 · 다른 이름 · id로 찾는 것까지만 */
    const themes = HT.mergeThemes(packs).map((d, i) => Object.assign({}, d, { order: i, color: HT.pastel(d.color || HT.autoColor(`theme:${d.id}`)) }));
    const themeMap = new Map(themes.map(d => [d.id, d]));
    const themeOf = ref => {
      const hit = HT.findTheme(themes, ref);
      if (hit) return hit;
      const s = String(ref ?? '').trim();
      if (!s) return null;
      const id = `theme-${HT.hash(s)}`;
      if (!themeMap.has(id)) {
        const o = { id, name: s, auto: true, order: themes.length, color: HT.pastel(HT.autoColor(`theme:${id}`)) };
        themes.push(o);
        themeMap.set(id, o);
      }
      return themeMap.get(id);
    };
    const pushTo = (m, k, v) => {
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(v);
    };
    /* 나라 찾기 { track?, polity } — 정권 띠만(기관 · 문화 · 왕조는 아님): 적은 트랙(비우면 그 항목의 트랙)에서 이름 · id · uid로, 트랙을 적지 않았으면 모든 트랙에서도.
       같은 이름이 여럿이면 그때(t) 있던 것 */
    const polityByRef = (ref, defTrack, packId, t) => {
      if (!ref || !ref.polity) return null;
      const ok = q => q.itemKind === 'period' && !q.groupUid; // 단체의 띠(조각 ④)는 나라가 아님
      const pickAt = list => (list.length < 2 || t == null || !isFinite(t) ? list[0] : list.find(q => q.start <= t && t <= endIn(q)) || list[0]) || null;
      const here = (periodsByTrack.get(ref.track || defTrack) || []).filter(q => ok(q) && (q.name === ref.polity || q.id === ref.polity || q.uid === ref.polity));
      if (here.length || ref.track) return pickAt(here);
      return pickAt(periods.filter(q => ok(q) && (q.uid === ref.polity || (q.packId === packId && q.id === ref.polity) || q.name === ref.polity)));
    };
    const refText = r => (r.track ? `${r.track}:${r.polity}` : r.polity);
    /* 제도 칸 */
    const institutions = [];
    const institutionIndex = { byTheme: new Map(), byPolity: new Map(), byFamily: new Map() };
    for (const raw of instMap.values()) {
      const warnings = [];
      const th = themeOf(raw.theme);
      if (th && th.auto) warnings.push(`주제 "${th.name}"이(가) 주제 사전에 없습니다 — 그 이름으로 주제를 만들어 묶었습니다.`);
      const known = (raw.spans || []).flatMap(sp => [sp.start, sp.end]).filter(v => v != null && isFinite(v));
      const P = polityByRef({ track: raw.track, polity: raw.polity }, raw.track || '', raw.packId, known.length ? Math.min(...known) : null);
      if (!P) warnings.push(`나라 "${refText(raw)}"을(를) 연표에서 찾지 못했습니다${known.length ? ' — 적힌 칸의 연대로만 자리를 잡았습니다' : ''}.`);
      const host = P || (known.length ? { start: Math.min(...known), endY: Math.max(...known) } : null);
      if (!host) continue; // 자리를 정할 것이 하나도 없음 — 모델에 넣지 않습니다 (메이커 검사가 알림)
      const res = HT.resolvePhases({ start: host.start, startAt: HT.atOf(host, 'start'), end: host.end, endAt: HT.atOf(host, 'end'), endY: host.endY, ongoing: host.ongoing, phases: [{ spans: (raw.spans || []).map(({ from, ...sp }) => sp) }] });
      const spanList = (res ? res[0].spans : []).map(sp => {
        const f = (raw.spans[sp.ii] || {}).from || null;
        const fp = f ? polityByRef(f, P ? P.track : raw.track || '', raw.packId, sp.start) : null;
        if (f && !fp) warnings.push(`칸 "${sp.name}"의 온 곳 "${refText(f)}"을(를) 연표에서 찾지 못했습니다.`);
        return Object.assign({}, sp, { from: f, fromItem: fp });
      });
      if (!spanList.length) continue;
      const famKey = raw.family ? `${th ? th.id : ''}|${raw.family}` : '';
      const o = Object.assign({}, raw, {
        themeId: th ? th.id : '', themeName: th ? th.name : raw.theme, themeColor: th ? th.color : '#a4b1b7',
        polityItem: P, polityUid: P ? P.uid : null, polityName: P ? P.name : raw.polity, polityColor: P ? P.color : null,
        track: P ? P.track : raw.track || '', trackAuto: !raw.track, // 적지 않은 트랙은 찾은 나라의 것 (폼은 비워 둠)
        name: `${P ? P.name : raw.polity} · ${th ? th.name : raw.theme}`, nameAuto: true,
        spanList, start: Math.min(...spanList.map(sp => sp.start)), endY: Math.max(...spanList.map(sp => sp.end)), startAuto: true, endAuto: true, // 기간은 칸에서 (폼 · 패치 비교는 …Auto가 붙은 값을 없는 것으로 봄)
        certainty: 'accepted', familyKey: famKey, warnings,
        color: HT.pastel(famKey ? HT.autoColor(`family:${famKey}`) : th ? th.color : '#a4b1b7'), // 같은 갈래면 나라가 달라도 같은 색
      });
      o.end = o.endY; // 기간 글(HT.formatRange)이 끝까지 보이게 — 짐작 표시(endAuto)가 붙어 파일 · 패치에는 쓰이지 않음
      o.spanMin = o.start;
      o.spanMax = o.endY;
      institutions.push(o);
      byUid.set(o.uid, o);
      if (o.themeId) pushTo(institutionIndex.byTheme, o.themeId, o);
      if (P) {
        pushTo(institutionIndex.byPolity, P.uid, o);
        (P.institutionList || (P.institutionList = [])).push(o);
      }
      if (famKey) pushTo(institutionIndex.byFamily, famKey, o);
    }
    institutions.sort((a, b) => ((themeMap.get(a.themeId) || {}).order ?? 99) - ((themeMap.get(b.themeId) || {}).order ?? 99) || a.start - b.start);
    HT.familyColors(institutions); // 갈래 색: 같은 주제 안의 다른 갈래가 같은 색이 되지 않게 (렌즈 — 설계 7-8 제안 4 ㉮ · 겹침이 없으면 위의 색 그대로)
    for (const p of periods) if (p.institutionList) p.institutionList.sort((a, b) => ((themeMap.get(a.themeId) || {}).order ?? 99) - ((themeMap.get(b.themeId) || {}).order ?? 99) || a.start - b.start);
    for (const o of institutions) {
      o.sameFamily = o.familyKey ? institutionIndex.byFamily.get(o.familyKey).filter(q => q !== o) : [];
      /* 같은 나라 · 같은 주제의 다른 제도와 칸이 겹치면 (한 제도 안의 겹침은 파일 검사가 알림) */
      const peers = o.polityUid ? (institutionIndex.byPolity.get(o.polityUid) || []).filter(q => q !== o && q.themeId === o.themeId) : [];
      for (const q of peers) {
        const hit = o.spanList.find(a => q.spanList.some(b => a.start < b.end && b.start < a.end));
        if (hit) o.warnings.push(`같은 나라 · 같은 주제의 제도 "${q.name}"${q.packId !== o.packId ? `(${q.packName})` : ''}와(과) 칸 "${hit.name}"의 기간이 겹칩니다.`);
      }
    }
    /* 단체 */
    const groups = [...groupMap.values()];
    const groupByRef = (ref, self) => {
      const s = String(ref ?? '').trim();
      if (!s) return null;
      const want = s.includes('/') ? s : `${self.packId}/${s}`;
      return groups.find(g => g !== self && g.uid === want) || groups.find(g => g !== self && g.packId === self.packId && g.name === s) || groups.find(g => g !== self && (g.name === s || g.id === s)) || null;
    };
    const figureByRef = (ref, g) => {
      const s = String(ref ?? '').trim();
      const want = s.includes('/') ? s : `${g.packId}/${s}`;
      const hit = figures.filter(f => f.uid === want || f.name === s || (f.aka || []).includes(s));
      if (hit.length < 2) return hit[0] || null;
      const score = f => (f.uid === want ? 100 : 0) + (f.track === g.track ? 10 : 0) + (f.spanMin <= g.endY && g.start <= f.spanMax + 1 ? 5 : 0);
      const best = Math.max(...hit.map(score));
      const top = hit.filter(f => score(f) === best);
      if (top.length === 1) return top[0];
      g.warnings.push(`구성원 "${s}"은(는) 같은 이름의 인물이 여럿이라 고를 수 없습니다 — 인물 id로 적습니다.`);
      return false; // 고르지 않음 (사람 잇기도 다시 찾지 않음)
    };
    const rowsOf = (g, v, role, word) =>
      HT.readPolityRows(v, { role }).map(r => {
        const p = polityByRef(r, g.track, g.packId, r.start ?? g.start);
        if (!p) g.warnings.push(`${word} "${refText(r)}"을(를) 연표에서 찾지 못했습니다.`);
        return Object.assign(
          { polity: p, polityUid: p ? p.uid : null, name: p ? p.name : r.polity, track: p ? p.track : r.track || g.track, color: p ? p.color : null, start: r.start ?? g.start, end: r.end ?? g.endY, given: r.start != null || r.end != null, role: r.role || '', note: r.note || '' },
          r.startUnknown || (r.start == null && g.startUnknown) ? { startUnknown: true } : null,
          r.endUnknown || (r.end == null && g.endUnknown) ? { endUnknown: true } : null
        );
      });
    for (const g of groups) {
      g.warnings = [];
      g.typeName = g.type ? HT.groupTypeName(g.type) : '';
      g.withinList = rowsOf(g, g.within, false, '있던 나라');
      g.memberList = rowsOf(g, g.members, true, '구성 나라');
      if (g.type === 'coalition' && HT.readPolityRows(g.members).length >= 2 && g.memberList.filter(m => m.polity).length < 2) g.warnings.push('연합인데 연표에서 찾은 구성 나라가 하나뿐입니다.');
      const P = (g.withinList.find(w => w.polity) || g.memberList.find(m => m.polity) || {}).polity || null;
      Object.assign(g, { polityUid: P ? P.uid : null, polityName: P ? P.name : null, polityColor: P ? P.color : null });
      /* 집권 기간: 연호와 같은 칸 — 미정은 이어지는 칸의 규칙(HT.placeCells), 비운 끝은 다음 칸의 시작(없으면 단체의 끝)까지 */
      const cells = HT.sortCells(HT.placeCells(Array.isArray(g.power) ? g.power : [], g).slice());
      g.powerSpans = cells.map((c, i) => {
        const next = cells[i + 1];
        const auto = c.end == null;
        const end = !auto ? c.end : next && next.start != null && next.start > c.start ? next.start : g.endY;
        return Object.assign({}, c, { i, end, endAt: auto ? (next && next.start != null && next.start > c.start ? next.startAt : HT.atOf(g, 'end')) : c.endAt, endAuto: auto || !!c.endAuto, endPolity: auto && !(next && next.start != null && next.start > c.start) });
      });
      g.peopleList = (Array.isArray(g.people) ? g.people : []).map(ref => {
        const f = typeof ref === 'string' ? figureByRef(ref, g) : null;
        return Object.assign({ name: HT.personRefText(ref), ref, uid: f ? f.uid : null, figure: f || null }, f === false ? { ambiguous: true } : null); // person(사람 자리 — 지도자 칸도)은 사람 잇기(linkPeople)가 덧붙임
      });
      g.eventItem = g.event ? findEvent(String(g.event), g.packId) : null;
      if (g.event && !g.eventItem) g.warnings.push(`맺은 사건 "${g.event}"을(를) 연표에서 찾지 못했습니다.`);
      if (g.eventItem) (g.eventItem.groupRefs || (g.eventItem.groupRefs = [])).push(g);
      if (!HT.isColor(g.color)) g.colorAuto = true;
      g.color = HT.pastel(HT.isColor(g.color) ? g.color : HT.autoColor(`group:${g.uid}`));
      g.trackName = tracks.has(g.track) ? tracks.get(g.track).name : g.track;
      for (const w of g.withinList) if (w.polity) (w.polity.groupLinks || (w.polity.groupLinks = [])).push({ group: g, role: 'within' });
      for (const m of g.memberList) if (m.polity && !(m.polity.groupLinks || []).some(l => l.group === g)) (m.polity.groupLinks || (m.polity.groupLinks = [])).push({ group: g, role: 'member' });
    }
    HT.groupColors(groups); // 같은 나라 단체의 자동 색이 겹치지 않게 · 함께 집권한 단체의 색이 같으면 경고 (설계 7-8 덧판 제안 6 — 띠 위를 색으로만 가르므로)
    for (const g of groups) {
      g.fromList = (Array.isArray(g.from) ? g.from : []).map(f => {
        const src = groupByRef(f.group, g);
        if (!src) g.warnings.push(`앞선 단체 "${f.group}"을(를) 찾지 못했습니다.`);
        else (src.intoList || (src.intoList = [])).push({ group: g, how: f.how || '', note: f.note || '' });
        return { group: src, name: src ? src.name : f.group, how: f.how || '', note: f.note || '' };
      });
    }
    groups.sort((a, b) => a.start - b.start || a.endY - b.endY);
    for (const g of groups) byUid.set(g.uid, g);
    for (const p of periods) if (p.groupLinks) p.groupLinks.sort((a, b) => a.group.start - b.group.start);
    /* 사건의 주제 꼬리표 → 주제 (사전에 없는 이름은 auto 주제 — 메이커 검사가 알림) */
    const themeEvents = new Map();
    for (const e of events) {
      const list = HT.readThemeList(e.theme);
      if (!list.length) continue;
      e.themeRefs = list.map(ref => {
        const t = themeOf(ref);
        pushTo(themeEvents, t.id, e);
        return { ref, id: t.id, name: t.name, color: t.color, auto: !!t.auto };
      });
    }
    for (const x of groups.concat(institutions)) if (x.wiki && !docs.has(x.uid)) docs.set(x.uid, { text: x.wiki, packId: x.packId, packName: x.packName });
    HT.lastThemes = themes; // 폼의 주제 자동 완성(HT.themeNameOptions)이 씀 — 마지막으로 만든 모델의 사전 (지위의 HT.lastRankDefs와 같은 길)
    HT.lastGroupNames = groups.map(g => g.name); // 단체 폼의 앞선 단체 자동 완성
    /* 문서 색인: 항목의 wiki 칸 → 바탕 문서. documents 칸은 위에서 이미 넣었습니다. 사용자가 고친 글이 DLC의 글보다 우선합니다 */
    for (const x of periods.concat(events, epochs)) if (x.wiki && !docs.has(x.uid)) docs.set(x.uid, { text: x.wiki, packId: x.packId, packName: x.packName });
    for (const x of figures.concat(lineageFigures)) if (x.wiki && !docs.has(x.uid)) docs.set(x.uid, { text: x.wiki, packId: x.packId, packName: x.packName }); // 인물의 문서 키도 항목과 같은 "DLC id/항목 id"
    for (const pe of peoples.values()) if (pe.wiki && !docs.has(`people:${pe.id}`)) docs.set(`people:${pe.id}`, { text: pe.wiki, packId: '', packName: '' });
    for (const t of tracks.values()) if (t.wiki && !docs.has(`track:${t.id}`)) docs.set(`track:${t.id}`, { text: t.wiki, packId: '', packName: '' });
    for (const [key, d] of docs) {
      if (key.includes('//')) continue;
      const x = byUid.get(key) || (key.startsWith('people:') ? peoples.get(key.slice(7)) : key.startsWith('track:') ? tracks.get(key.slice(6)) : null);
      if (x) x.wiki = d.text;
    }
    if (user && user.wiki) {
      for (const [key, text] of Object.entries(user.wiki)) {
        if (typeof text !== 'string' || !text.trim()) continue;
        docs.set(key, { text, packId: HT.USER_PACK.id, packName: HT.USER_PACK.name, user: true });
        if (key.includes('//')) continue;
        const x = byUid.get(key) || (key.startsWith('people:') ? peoples.get(key.slice(7)) : key.startsWith('track:') ? tracks.get(key.slice(6)) : null);
        if (!x) continue;
        x.wiki = text;
        x.wikiUser = true;
      }
    }
    const model = {
      // 트랙 차례: 문화권의 차례(켠 DLC의 spheres · 없는 트랙은 맨 뒤) → order → 넣은 차례 — 한 문화권의 트랙이 이어 서게
      tracks: [...tracks.values()].sort((a, b) => {
        const x = HT.sphereOrder(a.sphere);
        const y = HT.sphereOrder(b.sphere);
        return (x === y ? 0 : x < y ? -1 : 1) || a.order - b.order || a.seq - b.seq;
      }),
      categories: [...categories.values()],
      peoples: [...peoples.values()].sort((a, b) => a.order - b.order || a.seq - b.seq),
      epochs: epochs.sort((a, b) => a.start - b.start || a.endY - b.endY),
      scopes, // 대범위 (7절)
      periods,
      events,
      figures, // 인물 (시작 순) — byUid에도 들어 있습니다 (kind · itemKind 'figure')
      lineageFigures, // 계보 전용 인물 (D1 — 파일 차례) — byUid에도 들어 있지만 figures(띠 인물 단)에는 없습니다
      byUid,
      docs,
      trackMap: tracks,
      spheres, // 문화권 사전 (켠 DLC들의 spheres — 차례대로 · 트랙 차례의 바탕 · 메이커의 트랙 고르기 칸)
      sphereMap,
      sphereWarnings, // 만든 곳이 없는 문화권을 적은 트랙 (메이커의 검사 창)
      categoryMap: categories,
      peopleMap: peoples,
      rankDefs, // 지위 사전 (켠 DLC들 + 내장, 항목마다 짙기 단계 level)
      themes, // 주제 사전 (형식 버전 3 — 내장 뼈대 여덟 + 켠 DLC들 + 사전에 없는 이름으로 적힌 주제)
      themeMap,
      themeEvents, // 주제 id → 그 꼬리표를 단 사건 (시작 순)
      groups, // 단체 (시작 순) — byUid에도 들어 있습니다 (kind · itemKind 'group')
      institutions, // 제도 칸 (주제 차례 → 시작 순) — byUid에도 (kind · itemKind 'institution')
      institutionIndex, // { byTheme, byPolity, byFamily }
    };
    linkHouses(model, packs); // 가문 사전 · 국성 · 지도자/내각(/인물)의 가문 → model.houses · houseMap
    linkTreatySigners(model); // 조약의 서명자 ↔ 같은 이름의 인물 (인물 기능이 모델에 있을 때만)
    linkPeople(model, packs); // 지명 · 성씨 · 사람 · 계보 (형식 버전 3) → model.places · surnames · persons · personIndex · peopleWarnings
    linkFormat3(model, packs); // 형식 3: 모아 보기 판 · 지도 · 글꼴 → model.views · maps · fonts (구성 나라 · 장면의 주인을 나라로)
    linkOrder(model, packs); // 형식 3: 간지 설정 · 민족의 배열 기준 · 나라의 남북 값 → model.yearCycle · orderWarnings (설계 6 결정 6 · 8)
    linkDocImages(model, packs); // 형식 3: 문서 그림 사전 → model.imageMap (HT.docImageOf가 찾음)
    /* 지도자 표기 낱말(6단계 D3 — HT.leaderWords): 팩 id → 팩의 leaderLabels. 열거되지 않는 속성이라 내보내기 · 모델 사본에 섞이지 않습니다(저장소 자리는 아직 — 그림은 4단계) */
    Object.defineProperty(model, 'leaderLabelMap', { value: HT.useLeaderLabels(packs, model.tracks), configurable: true, writable: true, enumerable: false });
    /* 칸의 경계(HT.cellBounds — 이웃 칸끼리 겹치지 않게, 경계 해는 뒤 칸의 것): 칸 목록이 더 바뀌지 않는 맨 끝에서(가문 잇기가 지도자 · 내각을 복사한 뒤).
       열거되지 않는 속성이라 팩 · 내보내기 · 정권을 복사한 사본에 섞이지 않습니다 */
    for (const p of periods) if (p.kind === 'period') Object.defineProperty(p, 'cellBounds', { value: HT.cellBounds(p), configurable: true, writable: true, enumerable: false });
    return model;
  };

  /* ---------- 저장소 ---------- */
  HT.store = {
    get(key, fallback) {
      try {
        const v = localStorage.getItem(key);
        return v == null ? fallback : JSON.parse(v);
      } catch (e) {
        return fallback;
      }
    },
    set(key, value) {
      try {
        localStorage.setItem(key, JSON.stringify(value));
        return true;
      } catch (e) {
        console.warn('저장 실패', e);
        return false;
      }
    },
    remove(key) {
      try {
        localStorage.removeItem(key);
      } catch (e) {
        /* 무시 */
      }
    },
  };

  /** 불러오는 차례 (docs/구상-메이커-팩.md 2-4): 기본 내장 팩(과 그것을 대신한 설치본)은 앞 그대로, 나머지는 설치한 차례를 기본으로 하되
      needs · after가 가리키는 팩보다 뒤로(목록에 있는 팩만). 고리가 생기면 남은 것 가운데 가장 먼저 설치한 팩을 놓고, 그 팩의 아직 놓이지 않은 줄은
      무시합니다(그 팩의 orderIgnored에 id — DLC 관리 카드가 알림). 돌려주는 값: 새 배열 (팩 객체는 그대로 — orderIgnored만 새로 적음) */
  HT.orderPacks = list => {
    const head = list.filter(p => p.builtin || p.overridesBuiltin);
    const rest = list.filter(p => !(p.builtin || p.overridesBuiltin));
    const have = new Set(rest.map(p => p.id));
    const deps = new Map(rest.map(p => [p.id, [...new Set(arr(p.relations).filter(r => r && (r.type === 'needs' || r.type === 'after') && r.id !== p.id && have.has(r.id)).map(r => r.id))]]));
    const placed = new Set();
    const out = [];
    for (const p of rest) delete p.orderIgnored;
    while (out.length < rest.length) {
      let next = rest.find(p => !placed.has(p.id) && deps.get(p.id).every(d => placed.has(d)));
      if (!next) {
        next = rest.find(p => !placed.has(p.id));
        next.orderIgnored = deps.get(next.id).filter(d => !placed.has(d));
      }
      placed.add(next.id);
      out.push(next);
    }
    return head.concat(out);
  };
  /** 한 팩의 관계를 지금 팩 목록에 비춰 봅니다 — DLC 관리 카드의 관계 줄 · 자세히. packs = 쓸 수 있는 팩(HT.loadPacks), on(id) = 켜져 있는지.
      conflicts는 둘 다 켜져 있는 것만(어느 쪽이 적었든) · recommends는 있던 칸 requires */
  HT.packRelationState = (pack, packs, on) => {
    const find = id => packs.find(p => p.id === id);
    const nameOf = (id, fallback) => (find(id) || {}).name || fallback || id;
    const stateOf = id => (!find(id) ? 'missing' : on(id) ? 'on' : 'off');
    const rel = type => arr(pack.relations).filter(r => r && r.type === type);
    const clash = q => arr(pack.relations).some(r => r && r.type === 'conflicts' && r.id === q.id) || arr(q.relations).some(r => r && r.type === 'conflicts' && r.id === pack.id);
    return {
      needs: rel('needs').map(r => ({ id: r.id, name: nameOf(r.id, r.name), state: stateOf(r.id) })),
      conflicts: on(pack.id) ? packs.filter(q => q.id !== pack.id && on(q.id) && clash(q)).map(q => ({ id: q.id, name: q.name })) : [],
      recommends: arr(pack.requires).map(id => ({ id, name: nameOf(id), state: stateOf(id) })),
      after: rel('after').map(r => ({ id: r.id, name: nameOf(r.id, r.name), state: stateOf(r.id) })),
      ignored: arr(pack.orderIgnored).map(id => ({ id, name: nameOf(id) })),
    };
  };

  /** 쓸 수 있는 DLC 목록(정규화한 것): 기본 내장 팩 + 설치한 DLC — 설치한 것이 내장 팩과 id가 같으면 그 자리를 대신합니다(overridesBuiltin).
      켜고 끄기(HT.KEYS.packState)는 보지 않습니다 — 부르는 쪽이 거릅니다 */
  HT.loadPacks = () => {
    const list = [];
    for (const raw of HT.getBuiltinPacks()) {
      const { pack, errors } = HT.normalizePack(raw);
      if (errors.length) console.warn(`내장 팩 "${raw.id}" 검사 결과`, errors);
      if (pack) list.push(Object.assign(pack, { builtin: true }));
    }
    for (const raw of HT.store.get(HT.KEYS.installed, [])) {
      const { pack } = HT.normalizePack(raw);
      if (!pack) continue;
      const i = list.findIndex(p => p.id === pack.id);
      if (i >= 0) list[i] = Object.assign(pack, { overridesBuiltin: !!(list[i].builtin || list[i].overridesBuiltin) });
      else list.push(pack);
    }
    return HT.orderPacks(list);
  };

  /* ---------- 파일 ----------
   * 실제 동작은 js/platform.js(HT.platform)가 환경(브라우저·PWA·Tauri·Capacitor)에 맞게 맡습니다.
   * platform.js가 없으면 브라우저 방식으로 동작합니다. */
  const fallbackSave = (filename, blob) => {
    const url = URL.createObjectURL(blob);
    const a = Object.assign(document.createElement('a'), { href: url, download: filename });
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
    return Promise.resolve(true);
  };
  const fallbackPick = (accept, multiple = false) =>
    new Promise(resolve => {
      const input = Object.assign(document.createElement('input'), { type: 'file', accept, multiple });
      input.addEventListener('change', () => resolve([...input.files]));
      input.click();
    });
  HT.downloadBlob = (filename, blob) => (HT.platform ? HT.platform.saveFile(filename, blob) : fallbackSave(filename, blob));
  HT.downloadJSON = (filename, data) => HT.downloadBlob(filename, new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
  HT.pickFiles = (accept, multiple = false) => (HT.platform ? HT.platform.openFiles(accept, multiple) : fallbackPick(accept, multiple));
  HT.readFile = file =>
    new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result));
      r.onerror = () => reject(r.error);
      r.readAsText(file, 'utf-8');
    });

  /* ---------- 공용 폼: 날짜 입력 & 사건 입력 ---------- */
  const pad2 = n => String(n).padStart(2, '0');
  const WEEK = '일월화수목금토';
  /** 입력 칸에 보일 날짜 글: 날짜 글(값과 맞을 때) · 연도 수 · 소수 좌표면 서력 날짜 */
  HT.dateInputValue = (x, key) => {
    const at = HT.atOf(x, key);
    if (at) return at;
    const v = x ? x[key] : null;
    if (v == null || v === '') return '';
    if (typeof v !== 'number') return String(v);
    if (Number.isInteger(v)) return String(v);
    const a = HT.cal.at(v);
    return `${a.y < 0 ? `기원전 ${-a.y}` : a.y}-${pad2(a.m)}-${pad2(a.d)}`;
  };
  /** 기원전·기원후 고르기가 따로 있는 칸의 글: 글에 기원 표시가 없고 기원전을 골랐으면 붙여서 읽습니다 */
  const withEra = (raw, bc) => (bc && !/(^|\s)(-|기원전|서기전|b\.?\s?c)/i.test(raw) && /\d/.test(raw) ? `기원전 ${raw.replace(/^\s+/, '')}` : raw);
  /** 날짜 글에서 기원전 표시를 떼어 { bc, text } (기원전·기원후 고르기와 함께 보여 줄 때) */
  const splitEra = text => {
    const bc = /(^|\s)기원전\s/.test(text);
    return { bc, text: bc ? text.replace(/(^|\s)기원전\s/, '$1') : text };
  };
  /**
   * 날짜 입력 한 벌: [기원전/후] [연도]년 [월·일] (+ 미정). "월·일"을 누르면 달력(양력·음력·이슬람력 …)·월·윤달·일·시각이 열립니다.
   * 연도 칸에 날짜 글을 통째로 적어도 됩니다 (1592-05-23 · 음력 1592.4.13 — 칸에서 나오면 나눠 채움).
   * label은 화면 읽기 프로그램용 이름입니다 (칸 안에 회색 예시 글은 두지 않습니다)
   */
  HT.yearFieldHTML = (name, label = '연도', { unknown = false } = {}) => {
    const cals = HT.cal ? HT.cal.CALENDARS.filter(c => HT.cal.supports(c.id)) : [];
    return `<span class="year-field" data-year="${name}"><select name="${name}Era" aria-label="기원전/기원후"><option value="ad">기원후</option><option value="bc">기원전</option></select><input type="text" name="${name}" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${label}"><span class="unit">년</span><button type="button" class="date-more" data-date-more="${name}" aria-expanded="false" title="월·일·시각, 음력·이슬람력 같은 다른 달력">월·일</button>${
      unknown ? `<label class="check unk-check" title="연도를 모를 때. 숫자 칸에는 연표에서 자리를 잡을 대략의 연도를 적습니다"><input type="checkbox" name="${name}Unknown"> 미정</label>` : ''
    }<span class="date-parts" hidden><select name="${name}Cal" aria-label="달력" title="이 날짜를 적은 달력">${cals
      .map(c => `<option value="${c.id}" title="${HT.escapeHtml(c.long || c.name)}">${HT.escapeHtml(c.name)}</option>`)
      .join('')}</select><select name="${name}Month" aria-label="월"><option value="">—</option>${Array.from({ length: 13 }, (_, i) => `<option value="${i + 1}"${i === 12 ? ' hidden disabled' : ''}>${i + 1}월</option>`).join('')}</select><label class="check leap-check" hidden title="윤달"><input type="checkbox" name="${name}Leap"> 윤달</label><input type="number" name="${name}Day" min="1" max="31" step="1" inputmode="numeric" aria-label="일"><span class="unit">일</span><input type="time" name="${name}Time" step="60" aria-label="시각"></span><span class="date-note" aria-live="polite"></span></span>`;
  };
  const fieldEls = (form, name) => {
    const el = form.elements;
    const g = k => el[`${name}${k}`] || null;
    return { year: el[name] || null, era: g('Era'), cal: g('Cal'), month: g('Month'), leap: g('Leap'), day: g('Day'), time: g('Time'), unknown: g('Unknown'), wrap: form.querySelector(`.year-field[data-year="${name}"]`) };
  };
  /** 날짜 입력 한 벌 → null(빈 칸) · { t, at } · { t: NaN, error } */
  HT.readDateField = (form, name) => {
    const f = fieldEls(form, name);
    if (!f.year) return null;
    const raw = f.year.value.trim();
    if (!raw) return null;
    const bc = !!f.era && f.era.value === 'bc';
    if (!/^\d+$/.test(raw)) {
      const r = HT.cal.parse(withEra(raw, bc));
      if (!r) return null;
      return r.ok ? { t: r.t, at: r.fine && r.prec !== 'x' ? r.text : null } : { t: NaN, at: null, error: r.error };
    }
    const y = Number(raw) * (bc ? -1 : 1);
    const calId = (f.cal && f.cal.value) || 'civil';
    const m = f.month && f.month.value ? Number(f.month.value) : null;
    const d = m != null && f.day && f.day.value !== '' ? Number(f.day.value) : null;
    const [h, mi] = d != null && f.time && f.time.value ? f.time.value.split(':').map(Number) : [null, null];
    if (calId === 'civil' && m == null) return { t: y, at: null };
    const r = HT.cal.build({ cal: calId, y, m, leap: m != null && !!(f.leap && f.leap.checked && HT.cal.get(calId).lunar), d, h, mi });
    return r.ok ? { t: r.t, at: r.fine ? r.text : null } : { t: NaN, at: null, error: r.error };
  };
  /** 날짜 입력 한 벌에 값 채우기: t(해 좌표) + at(날짜 글) */
  HT.writeDateField = (form, name, t, at) => {
    const f = fieldEls(form, name);
    if (!f.year) return;
    let r = null;
    if (t != null && at && HT.atFits(at, t)) r = HT.cal.parse(at);
    else if (typeof t === 'number' && isFinite(t) && !Number.isInteger(t)) {
      const a = HT.cal.at(t);
      r = HT.cal.build({ y: a.y, m: a.m, d: a.d });
    }
    const fine = !!(r && r.ok && r.fine && r.prec !== 'x');
    const y = fine ? r.y : t;
    f.year.value = y == null || !isFinite(y) ? '' : String(Math.abs(Math.floor(y + 1e-9)));
    if (f.era) f.era.value = y != null && y < 0 ? 'bc' : 'ad';
    if (f.cal) f.cal.value = fine ? r.cal : 'civil';
    if (f.month) f.month.value = fine && r.m != null ? String(r.m) : '';
    if (f.leap) f.leap.checked = !!(fine && r.leap);
    if (f.day) f.day.value = fine && r.d != null ? String(r.d) : '';
    if (f.time) f.time.value = fine && r.h != null ? `${pad2(r.h)}:${pad2(r.mi || 0)}` : '';
    HT.syncDateField(form, name, { open: fine });
  };
  /** 날짜 입력의 모양(윤달 칸 · 월·일 단추 · 아래 설명 줄)을 값에 맞춥니다. open: 월·일 칸을 열지/닫을지(생략하면 그대로) */
  HT.syncDateField = (form, name, { open } = {}) => {
    const f = fieldEls(form, name);
    if (!f.wrap) return;
    const parts = f.wrap.querySelector('.date-parts');
    const btn = f.wrap.querySelector('[data-date-more]');
    const note = f.wrap.querySelector('.date-note');
    const c = f.cal ? HT.cal.get(f.cal.value) : null;
    const leapBox = f.wrap.querySelector('.leap-check');
    if (leapBox) leapBox.hidden = !(c && c.lunar);
    /* 13월은 달이 13인 달력(히브리력 · 에티오피아력 · 콥트력 — HT.cal.CALENDARS의 maxMonth)에서만 — 다른 달력으로 바꾸면 고른 13월을 비움 */
    const m13 = f.month ? f.month.querySelector('option[value="13"]') : null;
    if (m13) {
      m13.hidden = m13.disabled = !(c && c.maxMonth === 13);
      if (m13.disabled && f.month.value === '13') f.month.value = '';
    }
    if (parts && open != null) parts.hidden = !open;
    const unknown = !!(f.unknown && f.unknown.checked);
    f.wrap.classList.toggle('is-unknown', unknown);
    const hasDetail = !!((f.cal && f.cal.value !== 'civil') || (f.month && f.month.value));
    if (btn) {
      btn.setAttribute('aria-expanded', String(!!parts && !parts.hidden));
      btn.classList.toggle('has-date', hasDetail);
    }
    if (f.day) f.day.disabled = !(f.month && f.month.value);
    if (f.time) f.time.disabled = !(f.day && f.day.value !== '' && !f.day.disabled);
    if (!note) return;
    note.classList.remove('is-bad');
    if (f.year) f.year.setCustomValidity('');
    if (unknown) {
      note.textContent = '미정 — 숫자는 연표에서 자리를 잡을 대략의 연도입니다';
      return;
    }
    const d = HT.readDateField(form, name);
    if (d && d.error) {
      note.textContent = d.error;
      note.classList.add('is-bad');
      if (f.year) f.year.setCustomValidity(d.error);
      return;
    }
    if (!d || !d.at) {
      note.textContent = '';
      return;
    }
    const r = HT.cal.parse(d.at);
    const bits = [HT.cal.describe(r)];
    if (r.prec !== 'y' && r.prec !== 'm') {
      const J = HT.cal.at(r.t).J;
      bits.push(`${WEEK[(((J + 1) % 7) + 7) % 7]}요일`, `${HT.cal.dayGanji(J)}일`);
    }
    note.textContent = bits.join(' · ');
  };
  /* 날짜 입력은 문서 전체에서 한 번만 연결합니다 (연표·메이커의 모든 폼) */
  if (typeof document !== 'undefined' && !HT._dateFieldsBound) {
    HT._dateFieldsBound = true;
    const nameOf = el => (el && el.closest ? (el.closest('.year-field') || {}).dataset || {} : {}).year;
    document.addEventListener('click', ev => {
      const b = ev.target.closest && ev.target.closest('[data-date-more]');
      if (!b || !b.form) return;
      ev.preventDefault();
      const parts = b.parentElement.querySelector('.date-parts');
      const open = parts.hidden;
      HT.syncDateField(b.form, b.dataset.dateMore, { open });
      if (open) {
        const m = b.form.elements[`${b.dataset.dateMore}Month`];
        if (m) m.focus();
      }
    });
    const onEdit = ev => {
      const t = ev.target;
      const name = nameOf(t);
      if (!name || !t.form) return;
      /* 연도 칸에 날짜 글을 통째로 적었으면 칸에서 나올 때 나눠 채웁니다 */
      if (ev.type === 'change' && t.name === name && t.value.trim() && !/^\d+$/.test(t.value.trim())) {
        const bc = t.form.elements[`${name}Era`] && t.form.elements[`${name}Era`].value === 'bc';
        const r = HT.cal.parse(withEra(t.value.trim(), bc));
        if (r && r.ok) {
          const sp = splitEra(r.text);
          HT.writeDateField(t.form, name, r.t, r.fine && r.prec !== 'x' ? r.text : null);
          if (!r.fine) t.value = String(Math.abs(r.y));
          if (sp.bc || r.y < 0) t.form.elements[`${name}Era`].value = 'bc';
          t.form.dispatchEvent(new Event('input', { bubbles: true }));
          return;
        }
      }
      HT.syncDateField(t.form, name);
    };
    document.addEventListener('change', onEdit);
    document.addEventListener('input', onEdit);
  }
  /** 옛 이름들 (연도만 다루던 때) — 값은 해 좌표 */
  HT.syncUnknownField = (form, name) => HT.syncDateField(form, name);
  HT.readYearField = (form, name) => {
    const d = HT.readDateField(form, name);
    return d ? d.t : null;
  };
  HT.writeYearField = (form, name, y, at) => HT.writeDateField(form, name, y, at);
  /** 끝 칸 잠그기 (현재까지 이어짐) */
  HT.lockDateField = (form, name, on) => {
    const f = fieldEls(form, name);
    for (const el of [f.year, f.era, f.cal, f.month, f.leap, f.day, f.time]) if (el) el.disabled = on;
    const btn = f.wrap && f.wrap.querySelector('[data-date-more]');
    if (btn) btn.disabled = on;
    if (!on) HT.syncDateField(form, name);
  };

  const options = (list, selected) =>
    list.map(x => `<option value="${HT.escapeHtml(x.id)}"${x.id === selected ? ' selected' : ''}>${HT.escapeHtml(x.name)}</option>`).join('');
  const eraSelect = (cls, y) =>
    `<select class="${cls}" aria-label="기원전/기원후"><option value="ad"${y != null && y < 0 ? '' : ' selected'}>기원후</option><option value="bc"${y != null && y < 0 ? ' selected' : ''}>기원전</option></select>`;
  /** 기원전·기원후 고르기 옆 칸에 보일 글 (날짜 글이면 기원전 표시를 떼고) */
  const yearVal = (x, key) => {
    const v = HT.dateInputValue(x, key);
    if (/^-?\d+$/.test(v)) return String(Math.abs(Number(v)));
    return splitEra(v).text.replace(/^-/, '');
  };
  /** 이설 한 줄의 날짜 → null · { t, at } · { t: NaN, error } */
  const readPair = (row, eraCls, yearCls) => {
    const raw = row.querySelector(`.${yearCls}`).value.trim();
    if (raw === '') return null;
    const bc = row.querySelector(`.${eraCls}`).value === 'bc';
    if (/^\d+$/.test(raw)) return { t: Number(raw) * (bc ? -1 : 1), at: null };
    const r = HT.cal.parse(withEra(raw, bc));
    if (!r) return null;
    return r.ok ? { t: r.t, at: r.fine && r.prec !== 'x' ? r.text : null } : { t: NaN, at: null, error: r.error };
  };

  /* ---------- 공용 폼: 다른 견해(이설) 줄 · 칸의 이설 상자 (디테일 건의 4) ----------
     이설 한 줄 = 시작 ~ 끝(인물은 활동 시작 ~ 끝 · 출생 ~ 사망) · 근거 · 출처 · 메모 · ✕. 칸마다 이름표를 위에 적고, 입력 칸에 회색 예시 글은 두지 않습니다.
     끝 칸에 '현재'라고 적으면 지금까지 이어짐(ongoing). 읽은 줄은 파일과 같은 꼴로 다시 읽어(HT.readAlternatives) 출처 · 메모 · 현재까지가 폼을 거쳐도 남고,
     열어서 저장만 한 항목 · 칸은 패치가 생기지 않습니다(파일을 읽은 값과 한 글자도 같은 꼴).
     줄은 늘 제 상자 안에서만 찾습니다 — 항목의 이설은 [data-alts](값 = 모드: '' 항목 · 'figure' 인물, 폼에 하나뿐), 칸의 이설은 그 줄 안의 .cell-alts [data-calt-rows].
     칸의 상자를 칸 줄(.cell-row · .succ-row — flex-wrap이라 한 줄 전체 폭으로 내려감) 안에 두어, 줄을 지우면 상자도 함께 사라집니다 */
  /** 기원전 · 기원후 고르기의 값 — 수면 그 부호, 글(파일에 적힌 "기원전 57" · "-44-03-15" · 날짜 글)이면 그 글의 기원 표시 (고르기와 옆 칸의 글이 어긋나지 않게) */
  const eraOf = (x, key) => {
    const v = x ? x[key] : null;
    if (v == null || v === '' || typeof v === 'number') return v;
    return /^\s*(-|기원전|서기전|b\.?\s?c)/i.test(String(HT.dateInputValue(x, key))) ? -1 : 1;
  };
  const altPairHTML = (lab, c1, c2, a, k1, k2, tip2) =>
    `<span class="alt-f alt-when"><span class="alt-lab">${lab}</span><span class="alt-pair"><span class="alt-side">${eraSelect(`alt-era${c1}`, eraOf(a, k1))}<input class="alt-year${c1}" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${lab} — 앞 (연도나 날짜)" value="${HT.escapeHtml(yearVal(a, k1))}"></span><span class="tilde">~</span><span class="alt-side">${eraSelect(`alt-era${c2}`, eraOf(a, k2))}<input class="alt-year${c2}" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${lab} — 뒤 (연도나 날짜)" title="${tip2}" value="${HT.escapeHtml(k2 === 'end' && a.ongoing ? '현재' : yearVal(a, k2))}"></span></span></span>`; // 좁으면 한 쪽(기원 · 연도)씩 통째로 다음 줄로
  /** 이설 한 줄. opt.mode: 'item'(사건 · 시대 … — 기본) · 'cell'(칸의 상자) · 'figure'(인물 — 출생 · 사망 칸도). (.map(HT.altRowHTML)처럼 불러 둘째 인자가 순번이어도 항목의 줄) */
  HT.altRowHTML = (alt = {}, opt) => {
    const mode = (opt && typeof opt === 'object' && opt.mode) || 'item';
    const a = alt && typeof alt === 'object' ? alt : {};
    const endTip = mode === 'item' ? '비우면 한 해 · 지금까지 이어지면 현재' : '비우면 통설의 끝 · 지금까지 이어지면 현재';
    return `<div class="alt-row${mode === 'figure' ? ' is-figure' : ''}">
      ${altPairHTML(mode === 'figure' ? '활동 시작 ~ 끝' : '시작 ~ 끝', '', '2', a, 'start', 'end', endTip)}
      ${mode === 'figure' ? altPairHTML('출생 ~ 사망', '3', '4', a, 'birth', 'death', '비우면 통설의 사망') : ''}
      <label class="alt-f alt-lbl"><span class="alt-lab">근거 · 주장</span><input class="alt-label" value="${HT.escapeHtml(a.label || '')}"></label>
      <label class="alt-f alt-src"><span class="alt-lab">출처</span><input class="alt-source" value="${HT.escapeHtml(a.source || '')}"></label>
      <label class="alt-f alt-nt"><span class="alt-lab">메모</span><input class="alt-note" value="${HT.escapeHtml(a.note || '')}"></label>
      <button type="button" class="icon-btn" ${mode === 'cell' ? 'data-calt-del' : 'data-alt-del'} aria-label="이설 삭제" title="이설 삭제">✕</button>
    </div>`;
  };
  /** 이설 줄들 → 파일과 같은 꼴의 목록 (HT.readAlternatives). host = 줄들을 담은 상자(그 바로 아래 줄만 — 안쪽 상자의 줄은 보지 않음), where = 문제 글 앞말,
      base(칸 · 인물) = 그 칸 · 인물의 폼에 적힌 통설 값 — 한쪽만 적은 줄의 빈 쪽을 이 값으로 채우면 앞뒤가 뒤집히면 문제로(파일을 읽을 때와 같은 규칙) */
  const readAltRows = (host, problems, where, mode = 'item', base = null) => {
    const raw = [];
    [...(host ? host.children : [])]
      .filter(r => r.classList.contains('alt-row'))
      .forEach((row, n) => {
        const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const tag = `${where}이설 ${n + 1}번째 줄`;
        const ongoing = HT.isOngoingText(g('alt-year2'));
        const d = { start: readPair(row, 'alt-era', 'alt-year'), end: ongoing ? null : readPair(row, 'alt-era2', 'alt-year2') };
        if (mode === 'figure') Object.assign(d, { birth: readPair(row, 'alt-era3', 'alt-year3'), death: readPair(row, 'alt-era4', 'alt-year4') });
        const text = { label: g('alt-label'), source: g('alt-source'), note: g('alt-note') };
        const dated = ongoing || Object.values(d).some(Boolean);
        if (!dated && !text.label && !text.source && !text.note) return; // 빈 줄
        const badK = Object.keys(d).find(k => d[k] && isNaN(d[k].t));
        if (badK) return problems.push(`${tag}: ${ALT_WORDS[badK]}이 올바르지 않습니다.${d[badK].error ? ` (${d[badK].error})` : ''}`);
        if (mode === 'item' && dated && !d.start) return problems.push(`${tag}: 시작을 적어 주세요 (날짜 없이 근거만 적으려면 끝도 비웁니다).`);
        for (const [x, y] of [['start', 'end'], ['birth', 'death']]) if (d[x] && d[y] && HT.endBound(d[y].t, d[y].at) < d[x].t) return problems.push(`${tag}: ${ALT_WORDS[y]}이 ${ALT_WORDS[x]}보다 앞섭니다.`);
        const flip = mode !== 'item' && base && altFlipSide(d, ongoing, base, Object.keys(d));
        const FW = mode === 'figure' ? FIG_WORDS : ALT_WORDS;
        if (flip) return problems.push(`${tag}: ${FW[flip.own]}이 ${mode === 'figure' ? '이 인물' : '이 칸'}의 ${FW[flip.other]}보다 ${flip.own === 'start' || flip.own === 'birth' ? '늦습니다' : '앞섭니다'} (비운 ${FW[flip.other]}은 ${mode === 'figure' ? '이 인물' : '이 칸'}의 연대로 채웁니다).`);
        const o = Object.assign({}, text);
        for (const k of Object.keys(d)) {
          if (!d[k]) continue;
          o[k] = d[k].t;
          if (d[k].at) o[`${k}At`] = d[k].at;
        }
        if (ongoing) o.ongoing = true;
        raw.push(o);
      });
    return HT.readAlternatives(raw, { mode });
  };
  /** 항목의 다른 견해 칸 한 벌 (사건 · 시대 · 기관 · 문화 · 왕조 · 시대 구분 · 인물). mode: ''(항목) · 'figure'(인물 — 출생 · 사망도) */
  HT.altFieldHTML = (mode = '', hint = '시작·끝 연대를 학설마다 따로 적을 수 있습니다 — 날짜 없이 근거만 적으면 연표에는 표시 없이 상세 창의 다른 견해에만') => `<div class="field field-wide"><span>다른 견해(이설) <small>${hint}</small></span>
      <div class="alt-rows" data-alts="${mode}"></div>
      <button type="button" class="btn btn-sm" data-alt-add>＋ 이설 추가</button></div>`;
  /** 폼에서 항목 자신의 이설 줄 상자 — [data-alts]는 폼에 하나뿐입니다(칸의 이설 상자는 [data-calt-rows]) */
  const ownAlts = form => form.querySelector('[data-alts]');
  /** 항목의 이설 줄 채우기 · 읽기 (상자의 모드대로) */
  HT.fillAlternatives = (form, x) => {
    const host = ownAlts(form);
    if (host) host.innerHTML = ((x && x.alternatives) || []).map(a => HT.altRowHTML(a, { mode: host.dataset.alts || 'item' })).join('');
  };
  HT.readAlternativesField = (form, problems, base = null) => {
    const host = ownAlts(form);
    return host ? readAltRows(host, problems, '', host.dataset.alts || 'item', base) : [];
  };

  /** 칸 줄 끝의 [이설] 단추 글 — 적힌 이설 수와 모호함 ("이설" · "이설 2" · "이설 · 모호") */
  const caltLabel = u => {
    const n = ((u && u.alternatives) || []).length;
    return `이설${n ? ` ${n}` : ''}${HT.isFuzzy(u) ? ' · 모호' : u && u.certainty === 'certain' ? ' · 확실' : ''}`; // '확실'은 흐림이 아니므로 '모호'라고 하지 않음
  };
  const caltBtnHTML = c => `<button type="button" class="btn btn-sm calt-btn${HT.hasUncertainty(c) ? ' has-calt' : ''}" data-calt-toggle aria-expanded="false" title="이 칸의 다른 견해(이설) · 연대가 모호할 때 — 누르면 줄 아래에 펼쳐집니다">${caltLabel(c)}</button>`;
  /** 연대 폭 한 쌍(이르면 ~ 늦으면) — 칸의 상자 안: 이름(name)이 없는 칸이라 편집 창 폼의 이름 칸(certainty · rangeFrom …)과 부딪치지 않습니다 */
  const caltRangeHTML = (lab, key, u) => {
    const r = Array.isArray(u[key]) ? u[key] : [];
    const at = Array.isArray(u[`${key}At`]) ? u[`${key}At`] : [];
    const x = { a: r[0], aAt: at[0] || undefined, b: r[1], bAt: at[1] || undefined };
    return `<span class="alt-f calt-range"><span class="alt-lab">${lab}</span><span class="alt-pair"><span class="alt-side">${eraSelect(`u-${key}-era1`, eraOf(x, 'a'))}<input class="u-${key}-1" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${lab} — 이르면" value="${HT.escapeHtml(yearVal(x, 'a'))}"></span><span class="tilde">~</span><span class="alt-side">${eraSelect(`u-${key}-era2`, eraOf(x, 'b'))}<input class="u-${key}-2" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${lab} — 늦으면" value="${HT.escapeHtml(yearVal(x, 'b'))}"></span></span></span>`;
  };
  /** 칸의 이설 상자 (처음엔 접힘 — [이설] 단추로 펼침): 이설 줄들 · ＋ 이설 추가 · 연대가 모호함(확실성 · 시작 폭 · 끝 폭) */
  const caltBoxHTML = c => {
    const u = c && typeof c === 'object' ? c : {};
    const cert = HT.certaintyOf(u);
    return `<div class="cell-alts" hidden>
        <div class="calt-sec"><span class="calt-cap">다른 견해(이설) <small>시작이나 끝 하나만 적어도 됩니다 — 비운 쪽은 이 칸의 연대 · 날짜 없이 근거만 적으면 상세 창에만</small></span>
          <div class="alt-rows" data-calt-rows>${(Array.isArray(u.alternatives) ? u.alternatives : []).map(a => HT.altRowHTML(a, { mode: 'cell' })).join('')}</div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-calt-add>＋ 이설 추가</button></div></div>
        <div class="calt-sec"><span class="calt-cap">연대가 모호함 <small>이설이 아니라 연대 자체가 흐릴 때 — 확실성과 이르면 ~ 늦으면</small></span>
          <div class="calt-grid">
            <label class="alt-f calt-cert"><span class="alt-lab">확실성</span><select class="u-cert">${HT.CERTAINTY.map(v => `<option value="${v.id}"${v.id === cert ? ' selected' : ''} title="${HT.escapeHtml(v.hint)}">${HT.escapeHtml(v.name)}</option>`).join('')}</select></label>
            ${caltRangeHTML('시작 — 이르면 ~ 늦으면', 'startRange', u)}
            ${caltRangeHTML('끝 — 이르면 ~ 늦으면', 'endRange', u)}
          </div></div>
      </div>`;
  };
  HT.caltBtnHTML = caltBtnHTML; // 칸 줄 HTML(HT.cellRowHTML · partOfRowHTML · phaseRowHTML · rankRowHTML · serviceRowHTML)이 줄 끝 묶음 .row-end([이설] · ✕)과 그 뒤(상자)에 둡니다
  HT.caltBoxHTML = caltBoxHTML;
  /* 그 줄 바로 아래의 상자 · 단추 (줄 안의 이설 줄이 또 줄로 잡히지 않게 자식만 — 자식 목록이 없는 흉내 줄(검사 도구)이면 없음) */
  const caltBoxOf = row => Array.from((row && row.children) || []).find(el => el.classList && el.classList.contains('cell-alts')) || null;
  const caltBtnOf = row => (row && row.querySelector ? row.querySelector(':scope > .row-end > [data-calt-toggle]') : null); // 줄 끝 묶음([이설] · ✕ — 좁아도 둘이 함께 줄 끝에)
  /** 칸 줄의 이설 상자 → 파일과 같은 꼴 { certainty?, startRange?, startRangeAt?, endRange?, endRangeAt?, alternatives? } (적은 것만 — HT.readUncertain으로 다시 읽음).
      상자가 없는 줄은 {} · where = 문제 글 앞말("지도자 3번째 줄") */
  HT.readCellAlts = (row, problems, where, base = null) => {
    const box = caltBoxOf(row);
    if (!box) return {};
    const raw = {};
    const cert = (box.querySelector('.u-cert') || {}).value;
    if (cert && cert !== 'accepted') raw.certainty = cert;
    for (const [key, word] of [['startRange', '시작'], ['endRange', '끝']]) {
      const a = readPair(box, `u-${key}-era1`, `u-${key}-1`);
      const b = readPair(box, `u-${key}-era2`, `u-${key}-2`);
      if (!a && !b) continue;
      if (!a || !b || isNaN(a.t) || isNaN(b.t)) {
        problems.push(`${where}: ${word} 연대 폭은 이른 날짜와 늦은 날짜를 모두 바르게 적어 주세요.${(a && a.error) || (b && b.error) ? ` (${(a && a.error) || b.error})` : ''}`);
        continue;
      }
      raw[key] = [a.t, b.t];
      if (a.at || b.at) raw[`${key}At`] = [a.at || null, b.at || null];
    }
    const alts = readAltRows(box.querySelector('[data-calt-rows]'), problems, `${where} `, 'cell', base); // base = 그 줄의 시작 · 끝 (한쪽만 적은 이설이 뒤집히지 않았는지)
    if (alts.length) raw.alternatives = alts;
    return HT.readUncertain(raw, { mode: 'cell' });
  };
  /** 칸 줄의 [이설] 단추 글 · 표시를 상자의 지금 값에 맞춥니다 (상자를 고칠 때마다) */
  HT.syncCellAlts = row => {
    const btn = caltBtnOf(row);
    if (!btn || !caltBoxOf(row)) return;
    const u = HT.readCellAlts(row, [], '');
    btn.textContent = caltLabel(u);
    btn.classList.toggle('has-calt', HT.hasUncertainty(u));
  };
  /** 칸 줄의 이설 상자 펼치기 · 접기 (open을 주지 않으면 뒤집음). 나타날 때는 --t-in 동안 떠오르고, 접을 때는 --t-out 동안 옅어진 뒤 숨깁니다 —
      도중에 다시 누르면 지금 보이는 밝기에서 이어 갑니다(움직임 원칙 ②). instant: 움직임 없이 (저장한 뒤 다시 채울 때 펼쳐 두던 상자) */
  HT.toggleCellAlts = (row, open, opts = {}) => HT.toggleCellBox(caltBoxOf(row), caltBtnOf(row), open, opts);
  /** 칸 줄 아래 상자(이설 상자 · 사람 상자 — 형식 버전 3)를 펼치고 접는 공용 움직임: box = 상자, btn = 그 상자를 여는 단추 (위 HT.toggleCellAlts의 규칙 그대로) */
  HT.toggleCellBox = (box, btn, open, { instant = false } = {}) => {
    if (!box || !btn) return;
    const shown = !box.hidden && box.dataset.closing !== '1';
    const want = open == null ? !shown : !!open;
    btn.setAttribute('aria-expanded', String(want));
    btn.classList.toggle('is-open', want);
    if (want === shown) return;
    let from = box.hidden ? 0 : 1;
    try {
      if (!box.hidden) from = Number(getComputedStyle(box).opacity);
    } catch (e) {
      /* 문서가 없는 곳 */
    }
    for (const a of box.getAnimations ? box.getAnimations() : []) a.cancel();
    delete box.dataset.closing;
    box.hidden = false;
    if (instant || !box.animate) {
      box.hidden = !want;
      return;
    }
    const M = HT.motion;
    let still = false; // 동작 줄이기: 옮겨 가는 움직임은 없이 나타남 · 사라짐만 (토큰이 짧아진 --t-in · --t-out — 움직임 원칙의 줄이기 규칙, 날짜 칸 펼침과 같게)
    try {
      still = matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (e) {
      /* 문서가 없는 곳 */
    }
    const lift = want && from < 0.01 && !still ? -3 : 0;
    const anim = box.animate([{ opacity: from, transform: `translateY(${lift}px)` }, { opacity: want ? 1 : 0, transform: 'translateY(0)' }], { duration: want ? M.T.in : M.T.out, easing: want ? M.C.ease : 'ease-in', fill: 'forwards' });
    if (!want) box.dataset.closing = '1';
    anim.onfinish = () => {
      if (!want) {
        box.hidden = true;
        delete box.dataset.closing;
      }
      anim.cancel();
    };
  };
  /* 칸의 이설 상자는 문서 전체에서 한 번만 연결합니다 (메이커의 편집 창 · 어느 폼이든 — 날짜 입력과 같은 방식) */
  if (typeof document !== 'undefined' && !HT._cellAltsBound) {
    HT._cellAltsBound = true;
    document.addEventListener('click', ev => {
      const b = ev.target && ev.target.closest && ev.target.closest('[data-calt-toggle],[data-calt-add],[data-calt-del]');
      if (!b) return;
      const row = b.closest('.cell-row, .succ-row');
      if (!row) return;
      ev.preventDefault();
      const form = row.closest('form');
      if ('caltToggle' in b.dataset) return HT.toggleCellAlts(row);
      if ('caltAdd' in b.dataset) {
        const host = caltBoxOf(row).querySelector('[data-calt-rows]');
        host.insertAdjacentHTML('beforeend', HT.altRowHTML({}, { mode: 'cell' }));
        host.lastElementChild.querySelector('.alt-year').focus();
      } else b.closest('.alt-row').remove();
      HT.syncCellAlts(row);
      if (form) form.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const onAltEdit = ev => {
      const box = ev.target && ev.target.closest && ev.target.closest('.cell-alts');
      if (box) HT.syncCellAlts(box.parentElement);
    };
    document.addEventListener('input', onAltEdit);
    document.addEventListener('change', onAltEdit);
  }

  /** 연대 폭(이르면~늦으면) 두 칸: 시작용 rangeFrom/rangeTo, 끝용 endFrom/endTo */
  HT.uncertaintyFieldsHTML = ({ withAlternatives = true } = {}) => `
    <label class="field"><span>연대의 확실성</span><select name="certainty">${HT.CERTAINTY.map(c => `<option value="${c.id}"${c.id === 'accepted' ? ' selected' : ''}>${c.name} — ${c.hint}</option>`).join('')}</select></label>
    <div class="field"><span>시작 연대 폭 <small>(정확한 해를 모를 때)</small></span>
      <div class="range-row">${HT.yearFieldHTML('rangeFrom', '시작 — 이르면')}<span class="tilde">~</span>${HT.yearFieldHTML('rangeTo', '시작 — 늦으면')}</div></div>
    <div class="field field-wide"><span>끝(멸망·종료) 연대 폭 <small>(끝나는 해가 불확실할 때)</small></span>
      <div class="range-row">${HT.yearFieldHTML('endFrom', '끝 — 이르면')}<span class="tilde">~</span>${HT.yearFieldHTML('endTo', '끝 — 늦으면')}</div></div>
    ${withAlternatives ? HT.altFieldHTML() : ''}
    <label class="field field-wide"><span>쟁점 <small>(왜 견해가 갈리는지)</small></span><textarea name="debate" rows="3"></textarea></label>`;

  HT.eventFieldsHTML = ({ tracks, categories, polityNames = [], eventTitles = [], treatyTitles = [], figureNames = [], placeNames = [] }) => `
    <label class="field field-wide"><span>제목 <b class="req">*</b></span>${nameInHTML('<input name="title" maxlength="120" required>')}</label>
    <details class="field-wide adv names-adv" data-adv="names">
      <summary>이름(원어 등) — 제목의 원어 · 로마자 · 옛 이름 · 약칭</summary>
      <div class="adv-body">${HT.namesFieldHTML('제목의 다른 이름 — 원어 · 로마자 · 약칭 (나라마다 다른 이름은 아래 \'나라마다 다른 이름·인식\')')}</div>
    </details>
    <label class="field"><span>장소 <small>(지명 사전의 이름이나 id — 사전에 없으면 그 이름으로 저절로 생깁니다)</small></span><input name="place" maxlength="80" list="mkPlaceList"></label>
    ${HT.lineageListsHTML({ figureNames, placeNames })}
    <div class="field"><span><span data-when-lab="start">시작 연도</span> <b class="req">*</b></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span><span data-when-lab="end">끝 연도</span> <small data-when-hint>(한 해에 끝난 일이면 비워 두세요)</small></span>${HT.yearFieldHTML('end', '연도', { unknown: true })}
      <label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <label class="field"><span>자리 <small>(날짜를 정확히 모르는 점 — 그 해 · 달 · 날 안의 처음 ~ 끝 · 기본 가운데 · 같은 때 사건이 겹치면 옮기세요)</small></span><input type="range" name="spot" min="0" max="100" step="5" value="50" list="mkSpotTicks"><datalist id="mkSpotTicks"><option value="0"></option><option value="50"></option><option value="100"></option></datalist></label>
    <label class="field"><span>트랙</span><select name="track">${options(tracks)}</select></label>
    <label class="field"><span>정권 <small>(이 사건을 겪은 그 트랙의 나라 — 비우면 그 해의 정권)</small></span><input name="polity" maxlength="120" list="mkTreatyPolityList"></label>
    <label class="field"><span>분류</span><select name="category">${options(categories)}<option value="">기타 (분류 없음)</option></select></label>
    <label class="field"><span>중요도 <small>(높을수록 축소해도 이름이 보여요)</small></span><select name="importance"><option value="3">높음 ★★★</option><option value="2" selected>보통 ★★</option><option value="1">낮음 ★</option></select></label>
    <label class="field"><span>날짜 원문 표기 <small>(선택 — 날짜 계산은 시작·끝의 "월·일"에서)</small></span><input name="date" maxlength="40"></label>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="5"></textarea></label>
    <details class="field-wide adv" data-adv="links">
      <summary>묶기 — 상위 사건 · 함께 겪은 쪽 · 관련 인물</summary>
      <div class="adv-body">
        <label class="field field-wide"><span>상위 사건 <small>(큰 전쟁 안의 전투처럼 묶을 때 — 상위 사건의 제목을 그대로 적으세요)</small></span><input name="parent" maxlength="120"></label>
        <label class="field field-wide"><span>함께 겪은 쪽 <small>(쉼표로 구분 · 나라 이름, 나라:정권, 같은 나라의 다른 정권)</small></span><input name="sharedWith" maxlength="200"></label>
        <label class="field field-wide"><span>관련 인물 <small>(쉼표로 구분 · 인물의 이름이나 다른 이름 — 사건 상세에 인물 칩이 생기고, 인물 상세에는 이 사건이 나옵니다)</small></span><input name="figures" maxlength="300"></label>
      </div>
    </details>
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리는 경우 — 확실성 · 연대 폭 · 이설</summary>
      <div class="adv-body">${HT.uncertaintyFieldsHTML()}</div>
    </details>
    <details class="field-wide adv" data-adv="views">
      <summary>나라마다 다른 이름·인식</summary>
      <div class="adv-body">
        <div class="field field-wide"><span>나라별 명칭·서술 <small>같은 사건을 나라마다 어떻게 부르고 보는지</small></span>
          <div class="view-rows" data-views></div>
          <button type="button" class="btn btn-sm" data-view-add>＋ 나라 추가</button></div>
      </div>
    </details>
    ${HT.treatyFieldsHTML({ tracks, polityNames, eventTitles, treatyTitles })}
    ${HT.lensFieldsHTML() /* 주제 꼬리표 · 법 규격 · 선거 규격 (형식 버전 3) */}
    <label class="field"><span>태그 <small>(쉼표로 구분)</small></span><input name="tags"></label>
    <label class="field"><span>출처 <small>(선택)</small></span><input name="source"></label>
    ${HT.wikiFieldHTML()}`;

  /** 문서(위키) 본문 칸 — 사건·시대·민족 공용. 나무위키 문법으로 적고 미리보기로 확인합니다 */
  HT.wikiFieldHTML = () => `
    <details class="field-wide adv" data-adv="wiki">
      <summary>문서 (위키) — 나무위키 문법</summary>
      <div class="adv-body">
        <label class="field field-wide"><span>본문 <small>== 제목 == · '''굵게''' · [[다른 문서]] · [* 각주] · || 표 || · {{{#!folding 접기}}} 등</small></span><textarea name="wiki" rows="12" class="wiki-src" spellcheck="false"></textarea></label>
        <div class="field field-wide"><div class="toolbar"><button type="button" class="btn btn-sm" data-wiki-preview>👁 미리보기</button><button type="button" class="btn btn-sm" data-wiki-help>문법 도움말</button></div><div class="wiki-preview wk" data-wiki-preview-box hidden></div></div>
      </div>
    </details>`;

  HT.viewRowHTML = (tracks, v = {}) => `<div class="view-row">
      <select class="view-track" aria-label="나라">${options(tracks, v.track)}</select>
      <input class="view-title" placeholder="그 나라에서 부르는 이름" value="${HT.escapeHtml(v.title || '')}">
      <input class="view-desc" placeholder="그 나라의 서술·인식" value="${HT.escapeHtml(v.description || '')}">
      <button type="button" class="icon-btn" data-view-del aria-label="삭제">✕</button>
    </div>`;

  /* ---------- 사건 폼의 조약 규격 ----------
     접는 구역 하나(details.adv[data-adv="treaty"]): 무엇이든 적으면 이 사건이 조약이 되고, 비우면 treaty 칸이 사라져 보통 사건으로 돌아갑니다.
     형식의 칸 = 폼의 칸입니다(서명자는 한 칸 글 "이름(직함); …" — HT.readSigners가 목록 꼴과 같은 값으로 맞춤). 조약일 때 시작 · 끝 칸의 이름표는 체결 · 실효 */
  const esc = s => HT.escapeHtml(s == null ? '' : s);
  HT.treatyFieldsHTML = ({ polityNames = [], eventTitles = [], treatyTitles = [] } = {}) => `
    <details class="field-wide adv" data-adv="treaty">
      <summary>조약 규격 — 정식 명칭 · 당사국 · 조항</summary>
      <div class="adv-body">
        <p class="field-wide tr-form-note">이 구역에 무엇이든 적으면 이 사건이 조약이 됩니다(연표에 마름모). 시작은 체결, 끝은 실효(아직 유효하면 "현재까지 이어짐")이고, 구역을 모두 비우면 보통 사건으로 돌아갑니다.</p>
        <label class="field field-wide"><span>정식 명칭 <small>(제목은 흔히 부르는 이름)</small></span><input name="trFormal" maxlength="200"></label>
        <label class="field"><span>종류</span><select name="trType"><option value="">—</option>${options(HT.TREATY_TYPES)}</select></label>
        <div class="field"><span>불평등 조약</span><label class="check"><input type="checkbox" name="trUnequal"> 한쪽에 불리하게 맺은 조약</label></div>
        <div class="field"><span>비준 <small>(선택)</small></span>${HT.yearFieldHTML('ratified', '비준')}</div>
        <div class="field"><span>발효 <small>(체결과 다를 때)</small></span>${HT.yearFieldHTML('effective', '발효')}</div>
        <label class="field"><span>끝난 까닭 <small>(실효했으면)</small></span><select name="trEndReason"><option value="">—</option>${options(HT.TREATY_END_REASONS)}</select></label>
        <label class="field"><span>장소 <small>(맺은 곳)</small></span><input name="trPlace" maxlength="80"></label>
        <label class="field field-wide"><span>언어 <small>(조약문을 적은 말 · 쉼표로 구분)</small></span><input name="trLanguages" maxlength="120"></label>
        <div class="field field-wide"><span>당사국 <small>한 줄에 한 나라 · 트랙을 비우면 이 사건의 트랙 · 같은 편은 같은 수(비우면 모두 한 목록) · 서명자는 "이름(직함); 이름(직함)"</small></span>
          <div class="succ-rows" data-tr-parties></div>
          <button type="button" class="btn btn-sm" data-tr-party-add>＋ 당사국</button></div>
        <div class="field field-wide"><span>조항 <small>번호 · 제목 · 분류 · 본문 (모두 선택)</small></span>
          <div class="succ-rows" data-tr-articles></div>
          <button type="button" class="btn btn-sm" data-tr-article-add>＋ 조항</button>
          <details class="cell-paste"><summary>조항 한꺼번에 붙여넣기</summary>
            <textarea rows="5" aria-label="조약문" data-tr-paste-text></textarea>
            <button type="button" class="btn btn-sm" data-tr-paste>조항으로 나누어 추가</button>
            <p class="cells-hint">"제1조" · "제1관" · "Article 1"처럼 조항 번호로 시작하는 줄마다 새 조항이 됩니다. 번호 바로 뒤 괄호 안의 글은 제목, 다음 번호까지의 줄은 본문이 되고, 첫 번호 앞의 글은 번호 없는 조항 하나가 됩니다.</p></details></div>
        <label class="field"><span>끝낸 전쟁 <small>(사건의 제목이나 id)</small></span><input name="trConcludes" maxlength="120" list="mkTreatyEventList"></label>
        <label class="field"><span>대체한 조약 <small>(사건의 제목이나 id)</small></span><input name="trSupersedes" maxlength="120" list="mkTreatyTreatyList"></label>
        <datalist id="mkTreatyPolityList">${[...new Set(polityNames)].map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>
        <datalist id="mkTreatyEventList">${[...new Set(eventTitles)].filter(Boolean).map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>
        <datalist id="mkTreatyTreatyList">${[...new Set(treatyTitles)].filter(Boolean).map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>
      </div>
    </details>`;
  /** 당사국 한 줄: 트랙 · 정권 · 편 · 역할 · 서명자 (tracks = [{ id, name }] — 목록에 없는 트랙(다른 DLC의 것)도 고른 그대로 남김) */
  HT.treatyPartyRowHTML = (tracks = [], p = {}) => `<div class="succ-row tr-party">
      <select class="p-track" aria-label="트랙" title="당사국의 트랙(나라) — 비우면 이 사건의 트랙"><option value="">이 사건의 트랙</option>${options(tracks, p.track)}${
        p.track && !tracks.some(t => t.id === p.track) ? `<option value="${esc(p.track)}" selected>${esc(p.track)}</option>` : ''
      }</select>
      <input class="p-polity" list="mkTreatyPolityList" placeholder="정권" title="당사국 정권의 이름 — 비우면 그 해 그 트랙의 정권" value="${esc(p.polity)}">
      <input class="p-side" type="number" min="1" step="1" inputmode="numeric" placeholder="편" title="같은 편끼리 같은 수 — 비우면 편 없이 한 목록" value="${esc(p.side)}">
      <input class="p-role" placeholder="역할" title="이 조약에서의 역할 (선택)" value="${esc(p.role)}">
      <input class="p-sign" placeholder="서명자" title="서명한 사람 — 이름(직함); 이름(직함)" value="${esc(HT.signersText(p.signatories))}"${p.signatories && p.signatories.length ? ` data-list="${esc(JSON.stringify(HT.readSigners(p.signatories)))}"` : ''}>
      <button type="button" class="icon-btn" data-tr-party-del aria-label="당사국 삭제">✕</button></div>`;
  /** 조항 한 줄: 번호 · 제목 · 분류 · 본문 */
  HT.treatyArticleRowHTML = (a = {}) => `<div class="succ-row tr-article">
      <input class="a-no" placeholder="번호" title="조항 번호 (선택)" value="${esc(a.no)}">
      <input class="a-title" placeholder="제목" title="조항 제목 (선택)" value="${esc(a.title)}">
      <select class="a-tag" aria-label="분류" title="조항의 분류 (선택)"><option value="">분류 없음</option>${options(HT.ARTICLE_TAGS, a.tag)}</select>
      <button type="button" class="icon-btn" data-tr-article-del aria-label="조항 삭제">✕</button>
      <textarea class="a-text" rows="2" aria-label="본문" placeholder="본문">${esc(a.text)}</textarea></div>`;
  /** 조약 규격을 폼에 채웁니다 — 파일의 꼴(서명자 글 · 글로 적은 조항 · 한국어 종류)도 받습니다. raw가 객체이면(새 조약의 빈 규격도) 구역을 열어 둡니다 */
  HT.fillTreatyFields = (form, raw) => {
    const el = form.elements;
    if (!el.trFormal) return;
    const t = HT.readTreaty(raw) || {};
    el.trFormal.value = t.formal || '';
    el.trType.value = t.type || '';
    el.trUnequal.checked = !!t.unequal;
    HT.writeDateField(form, 'ratified', t.ratified ?? null, t.ratifiedAt);
    HT.writeDateField(form, 'effective', t.effective ?? null, t.effectiveAt);
    el.trEndReason.value = t.endReason || '';
    el.trPlace.value = t.place || '';
    el.trLanguages.value = (t.languages || []).join(', ');
    el.trLanguages.dataset.list = JSON.stringify(t.languages || []); // 쉼표가 든 언어도 그대로 두면 원래 목록 (HT.keepListText)
    el.trConcludes.value = t.concludes || '';
    el.trSupersedes.value = t.supersedes || '';
    const tracks = JSON.parse(form.dataset.tracks || '[]');
    form.querySelector('[data-tr-parties]').innerHTML = (t.parties || []).map(p => HT.treatyPartyRowHTML(tracks, p)).join('');
    form.querySelector('[data-tr-articles]').innerHTML = (t.articles || []).map(HT.treatyArticleRowHTML).join('');
    const paste = form.querySelector('[data-tr-paste-text]');
    if (paste) paste.value = '';
    const box = form.querySelector('details[data-adv="treaty"]');
    if (box) box.open = !!raw && typeof raw === 'object';
    HT.syncTreatyForm(form);
  };
  /** 폼의 조약 규격 → 깨끗한 꼴(HT.readTreaty) · 적은 것이 없으면 null (보통 사건). 빈 줄은 조용히 건너뜁니다 */
  HT.readTreatyFields = (form, problems = []) => {
    const el = form.elements;
    if (!el.trFormal) return null;
    const raw = { formal: el.trFormal.value, type: el.trType.value, unequal: el.trUnequal.checked, endReason: el.trEndReason.value, place: el.trPlace.value, languages: HT.keepListText(el.trLanguages.value, el.trLanguages.dataset.list, l => l.join(', ')), concludes: el.trConcludes.value, supersedes: el.trSupersedes.value };
    for (const [k, word] of [['ratified', '비준'], ['effective', '발효']]) {
      const d = HT.readDateField(form, k);
      if (!d) continue;
      if (isNaN(d.t)) problems.push(`조약의 ${word}: ${d.error || '날짜가 올바르지 않습니다.'}`);
      else {
        raw[k] = d.t;
        if (d.at) raw[`${k}At`] = d.at;
      }
    }
    const g = (row, cls) => (row.querySelector(`.${cls}`) || {}).value || '';
    raw.parties = [...form.querySelectorAll('[data-tr-parties] .tr-party')]
      .map(row => ({ track: g(row, 'p-track'), polity: g(row, 'p-polity'), side: g(row, 'p-side').trim(), role: g(row, 'p-role'), signatories: HT.keepListText(g(row, 'p-sign'), (row.querySelector('.p-sign') || { dataset: {} }).dataset.list, HT.signersText) }))
      .filter(p => Object.values(p).some(v => String(v).trim()));
    raw.articles = [...form.querySelectorAll('[data-tr-articles] .tr-article')].map(row => ({ no: g(row, 'a-no'), title: g(row, 'a-title'), tag: g(row, 'a-tag'), text: g(row, 'a-text') }));
    return HT.readTreaty(raw, msg => problems.push(msg));
  };
  /** 폼이 조약인지(구역이 열렸거나 무엇이든 적혔으면)에 맞춰 시작 · 끝 칸의 이름표를 체결 · 실효로 */
  HT.syncTreatyForm = form => {
    const box = form.querySelector('details[data-adv="treaty"]');
    if (!box) return;
    const on = box.open || !!HT.readTreatyFields(form);
    const put = (sel, text) => {
      const n = form.querySelector(sel);
      if (n && n.textContent !== text) n.textContent = text;
    };
    put('[data-when-lab="start"]', on ? '체결' : '시작 연도');
    put('[data-when-lab="end"]', on ? '실효' : '끝 연도');
    put('[data-when-hint]', on ? '(효력이 끝난 때 — 아직 유효하면 "현재까지 이어짐")' : '(한 해에 끝난 일이면 비워 두세요)');
  };

  /** 폼 안의 추가/삭제 버튼과 진행 중 체크박스를 연결합니다. */
  HT.bindEventForm = form => {
    form.addEventListener('click', e => {
      const btn = e.target.closest('[data-alt-add],[data-alt-del],[data-view-add],[data-view-del],[data-wiki-preview],[data-wiki-help]');
      if (!btn) return;
      e.preventDefault();
      if ('wikiPreview' in btn.dataset) {
        const box = form.querySelector('[data-wiki-preview-box]');
        const src = form.elements.wiki ? form.elements.wiki.value : '';
        box.hidden = !box.hidden;
        if (!box.hidden) box.innerHTML = HT.namu ? HT.namu.render(src, { link: form._wikiLink, image: form._wikiImage }).html : HT.escapeHtml(src); // 문서 그림(형식 3)은 이 문서가 저장될 팩의 그림 사전에서
        return;
      }
      if ('wikiHelp' in btn.dataset) {
        if (HT.namu) HT.namu.showHelp();
        return;
      }
      if ('altAdd' in btn.dataset) {
        const host = ownAlts(form); // 항목 자신의 이설 줄 상자 (칸의 이설 상자는 [data-calt-rows] — 문서 전체에 건 칸 상자 처리가 맡음)
        host.insertAdjacentHTML('beforeend', HT.altRowHTML({}, { mode: host.dataset.alts || 'item' }));
        host.lastElementChild.querySelector('.alt-year').focus();
      } else if ('altDel' in btn.dataset) btn.closest('.alt-row').remove();
      else if ('viewAdd' in btn.dataset) {
        const tracks = JSON.parse(form.dataset.tracks || '[]');
        form.querySelector('[data-views]').insertAdjacentHTML('beforeend', HT.viewRowHTML(tracks));
        form.querySelector('.view-row:last-child .view-title').focus();
      } else btn.closest('.view-row').remove();
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
    form.addEventListener('change', e => {
      if (e.target.name === 'ongoing' && form.elements.end) HT.lockDateField(form, 'end', e.target.checked);
      if (/Unknown$/.test(e.target.name || '')) HT.syncUnknownField(form, e.target.name.replace(/Unknown$/, ''));
    });
    /* 조약 규격: 당사국 · 조항 줄 추가/삭제 · 조항 한꺼번에 붙여넣기, 그리고 구역을 열고 닫거나 적을 때 체결 · 실효 이름표 */
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-tr-party-add],[data-tr-party-del],[data-tr-article-add],[data-tr-article-del],[data-tr-paste]');
      if (!b) return;
      e.preventDefault();
      if ('trPartyAdd' in b.dataset) {
        const host = form.querySelector('[data-tr-parties]');
        host.insertAdjacentHTML('beforeend', HT.treatyPartyRowHTML(JSON.parse(form.dataset.tracks || '[]')));
        host.lastElementChild.querySelector('.p-polity').focus();
      } else if ('trPartyDel' in b.dataset) b.closest('.tr-party').remove();
      else if ('trArticleAdd' in b.dataset) {
        const host = form.querySelector('[data-tr-articles]');
        host.insertAdjacentHTML('beforeend', HT.treatyArticleRowHTML());
        host.lastElementChild.querySelector('.a-no').focus();
      } else if ('trArticleDel' in b.dataset) b.closest('.tr-article').remove();
      else {
        const ta = form.querySelector('[data-tr-paste-text]');
        const list = HT.splitArticles(ta.value);
        form.querySelector('[data-tr-articles]').insertAdjacentHTML('beforeend', list.map(HT.treatyArticleRowHTML).join(''));
        if (list.length) {
          ta.value = '';
          HT.toast(`조항 ${list.length}개를 줄로 옮겼습니다.`, 'ok');
        } else HT.toast('옮길 조항이 없습니다. 조약문을 붙여 넣어 주세요.', 'error');
      }
      HT.syncTreatyForm(form);
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const inTreaty = e => e.target && e.target.closest && e.target.closest('details[data-adv="treaty"]');
    form.addEventListener('input', e => inTreaty(e) && HT.syncTreatyForm(form));
    form.addEventListener('change', e => inTreaty(e) && HT.syncTreatyForm(form));
    form.addEventListener('toggle', e => e.target.matches && e.target.matches('details[data-adv="treaty"]') && HT.syncTreatyForm(form), true); // toggle은 올라오지 않아 잡는 단계에서
  };

  /** 시작·끝 연도 + 미정 체크를 폼에 채웁니다 (사건·시대 공용) */
  HT.fillRangeFields = (form, x) => {
    const el = form.elements;
    if (el.startUnknown) el.startUnknown.checked = !!x.startUnknown;
    if (el.endUnknown) el.endUnknown.checked = !!x.endUnknown;
    HT.writeDateField(form, 'start', x.start ?? null, x.startAt);
    HT.writeDateField(form, 'end', x.end ?? null, x.endAt);
    el.ongoing.checked = !!x.ongoing;
    HT.lockDateField(form, 'end', !!x.ongoing);
  };
  /** 폼 → { start, end, ongoing, startUnknown, endUnknown, startAt, endAt }. 미정이면 숫자 칸은 배치용 연도입니다.
      날짜 글(startAt · endAt)은 없으면 null — 고친 내용이 원래 항목의 날짜 글을 지우도록 */
  HT.readRangeFields = (form, problems) => {
    const el = form.elements;
    const ongoing = el.ongoing.checked;
    const startUnknown = !!(el.startUnknown && el.startUnknown.checked);
    const endUnknown = !ongoing && !!(el.endUnknown && el.endUnknown.checked);
    const sd = HT.readDateField(form, 'start');
    const ed = ongoing ? null : HT.readDateField(form, 'end');
    let start = sd ? sd.t : null;
    let end = ed ? ed.t : null;
    let startAt = sd && !startUnknown ? sd.at : null;
    let endAt = ed && !endUnknown ? ed.at : null;
    if (start != null && isNaN(start)) problems.push(`시작: ${sd.error || '연도가 올바르지 않습니다.'}`);
    if (end != null && isNaN(end)) problems.push(`끝: ${ed.error || '연도가 올바르지 않습니다.'}`);
    if (startUnknown && start == null) start = end;
    if (start == null) problems.push(startUnknown ? '시작이 미정이면 끝 연도나 배치용 연도를 적어 주세요.' : '시작 연도를 입력하세요.');
    if (endUnknown && end == null) end = start;
    if (end != null && start != null && !isNaN(end) && !isNaN(start) && HT.endBound(end, endAt) < start) problems.push('끝이 시작보다 앞섭니다.');
    if (end === start && !endUnknown && !startUnknown) end = endAt = null; // 시작이 미정이면 끝은 그대로 (파일 읽기 · 표 붙여넣기와 같은 규칙)
    return { start, end, ongoing, startUnknown, endUnknown, startAt: startAt || null, endAt: end != null ? endAt || null : null };
  };

  /** 확실성·연대 폭·이설·쟁점 칸 채우기 (사건·시대 공용) */
  HT.fillUncertainty = (form, x) => {
    form.elements.certainty.value = HT.certaintyOf(x);
    const sr = x.startRange || [];
    const er = x.endRange || [];
    const sa = x.startRangeAt || [];
    const ea = x.endRangeAt || [];
    HT.writeDateField(form, 'rangeFrom', sr[0] ?? null, sa[0]);
    HT.writeDateField(form, 'rangeTo', sr[1] ?? null, sa[1]);
    HT.writeDateField(form, 'endFrom', er[0] ?? null, ea[0]);
    HT.writeDateField(form, 'endTo', er[1] ?? null, ea[1]);
    form.elements.debate.value = x.debate || '';
    HT.fillAlternatives(form, x);
    const box = form.querySelector('details[data-adv="dates"]');
    if (box) box.open = !!(x.alternatives && x.alternatives.length) || !!x.startRange || !!x.endRange || !!x.debate || HT.certaintyOf(x) !== 'accepted';
  };

  HT.readUncertainty = (form, problems) => {
    const out = { certainty: form.elements.certainty.value, debate: form.elements.debate.value.trim(), startRange: null, endRange: null, startRangeAt: null, endRangeAt: null, alternatives: [] };
    for (const [key, a, b, label] of [
      ['startRange', 'rangeFrom', 'rangeTo', '시작 연대 폭'],
      ['endRange', 'endFrom', 'endTo', '끝 연대 폭'],
    ]) {
      const from = HT.readDateField(form, a);
      const to = HT.readDateField(form, b);
      if (from == null && to == null) continue;
      if (from == null || to == null || isNaN(from.t) || isNaN(to.t)) {
        problems.push(`${label}은 이른 날짜와 늦은 날짜를 모두 바르게 입력하세요.${(from && from.error) || (to && to.error) ? ` (${(from && from.error) || to.error})` : ''}`);
        continue;
      }
      const pair = from.t <= to.t ? [from, to] : [to, from];
      out[key] = pair.map(d => d.t);
      if (pair.some(d => d.at)) out[`${key}At`] = pair.map(d => d.at || null);
    }
    out.alternatives = HT.readAlternativesField(form, problems); // 항목 자신의 이설 줄만 (칸 줄 안의 이설 상자는 그 칸이 읽음) — 출처 · 메모 · 현재까지도 남습니다
    return out;
  };

  /* 실재성 칸 (시대 폼의 '연대가 갈리거나 실재가 의심될 때' 구역 맨 앞 — 8-4 마): 고르기 + 근거 글. 실재는 빈 값 */
  HT.historicityFieldsHTML = () => `
    <label class="field"><span>실재성 <small>(나라가 있었는가 — 연대의 확실성과는 따로)</small></span><select name="historicity">${HT.HISTORICITY.map(h => `<option value="${h.id === 'attested' ? '' : h.id}">${h.name} — ${h.hint}</option>`).join('')}</select></label>
    <label class="field field-wide"><span>실재성의 근거 <small>(출전 · 누가 언제 인정하거나 부정했는가)</small></span><textarea name="historicityNote" rows="2"></textarea></label>`;
  HT.fillHistoricity = (form, x) => {
    const el = form.elements;
    if (!el.historicity) return;
    el.historicity.value = HT.historicityOf(x);
    el.historicityNote.value = (x && x.historicityNote) || '';
    const box = form.querySelector('details[data-adv="dates"]');
    if (box && (el.historicity.value || el.historicityNote.value)) box.open = true;
  };
  HT.readHistoricity = form => {
    const el = form.elements;
    if (!el.historicity) return {};
    return { historicity: HT.historicity(el.historicity.value) || undefined, historicityNote: el.historicityNote.value.trim() || undefined };
  };

  HT.fillEventForm = (form, e) => {
    const el = form.elements;
    el.title.value = e.title || '';
    HT.fillRangeFields(form, e);
    if (e.track) el.track.value = e.track;
    el.category.value = e.category && e.category !== 'etc' ? e.category : '';
    el.importance.value = String(e.importance || 2);
    if (el.spot) el.spot.value = String(Math.round((Number.isFinite(e.spot) ? e.spot : 0.5) * 100));
    el.date.value = e.date || '';
    el.description.value = e.description || '';
    el.tags.value = (e.tags || []).join(', ');
    el.source.value = e.source || '';
    el.parent.value = e.parent || '';
    if (el.polity) el.polity.value = typeof e.polity === 'string' ? e.polity : (e.polity && (e.polity.name || e.polity.id)) || ''; // 정권(polity — 2026-10-23 전역 확대 ⑨: 남의 사건의 정권도 패치로 덮어씀)
    if (el.wiki) {
      el.wiki.value = e.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!e.wiki;
    }
    const tracks = [...el.track.options].map(o => ({ id: o.value, name: o.textContent }));
    form.dataset.tracks = JSON.stringify(tracks);
    const trackName = id => (tracks.find(t => t.id === id) || {}).name || id;
    el.sharedWith.value = []
      .concat(e.polities || [])
      .concat((e.tracks || []).map(t => {
        const [id, pol] = String(t).split(':');
        return pol ? `${trackName(id)}:${pol}` : trackName(id);
      }))
      .join(', ');
    HT.fillUncertainty(form, e);
    form.querySelector('[data-views]').innerHTML = (e.perspectives || []).map(v => HT.viewRowHTML(tracks, v)).join('');
    const links = form.querySelector('details[data-adv="links"]');
    if (links) links.open = !!(e.parent || el.sharedWith.value);
    if (el.figures) el.figures.value = (Array.isArray(e.figures) ? e.figures : []).join(', '); // 관련 인물
    if (links && el.figures && el.figures.value) links.open = true;
    const views = form.querySelector('details[data-adv="views"]');
    if (views) views.open = !!(e.perspectives && e.perspectives.length);
    HT.fillTreatyFields(form, e.treaty); // 조약 규격 (트랙 목록 form.dataset.tracks를 채운 뒤에)
    HT.fillLensFields(form, e); // 주제 꼬리표 · 법 규격 · 선거 규격 (형식 버전 3)
    if (el.place) el.place.value = e.place || ''; // 장소 · 이름 목록 (형식 버전 3)
    HT.fillNamesField(form, e);
  };

  /** 폼 → 사건 객체. problems 배열에 사람이 읽을 문제를 담아 돌려줍니다. */
  HT.readEventForm = form => {
    const el = form.elements;
    const problems = [];
    const range = HT.readRangeFields(form, problems);
    const e = {
      title: el.title.value.trim(),
      start: range.start,
      startAt: range.startAt,
      end: range.end,
      endAt: range.endAt,
      ongoing: range.ongoing,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      track: el.track.value,
      category: el.category.value,
      importance: Number(el.importance.value) || 2,
      spot: el.spot && Number(el.spot.value) !== 50 ? HT.readSpot(Number(el.spot.value) / 100) : undefined, // 가운데(기본)는 적지 않음
      date: el.date.value.trim(),
      description: el.description.value.trim(),
      tags: el.tags.value.split(',').map(s => s.trim()).filter(Boolean),
      source: el.source.value.trim(),
      parent: el.parent.value.trim(),
      polities: [],
      tracks: [],
      perspectives: [],
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    Object.assign(e, HT.readUncertainty(form, problems));
    if (el.figures) {
      /* 관련 인물 (폼에 칸이 있을 때만 — 없으면 원래 값을 건드리지 않게 칸 자체를 안 만듭니다). 비우면 undefined: 내 항목에서는 칸이 빠지고, DLC 항목의 수정에서는 원래 목록을 지움 */
      const rel = [...new Set(el.figures.value.split(/[,，]/).map(s => s.trim()).filter(Boolean))];
      e.figures = rel.length ? rel : undefined;
    }

    // 함께 겪은 쪽: "일본", "중국:명", "거란(요)"
    const tracks = JSON.parse(form.dataset.tracks || '[]');
    const findTrack = v => tracks.find(t => t.id === v || t.name === v);
    for (const token of el.sharedWith.value.split(/[,，]/).map(s => s.trim()).filter(Boolean)) {
      const [head, pol] = token.split(':').map(s => s.trim());
      const t = findTrack(head);
      if (t && t.id !== e.track) e.tracks.push(pol ? `${t.id}:${pol}` : t.id);
      else if (t && t.id === e.track && pol) e.polities.push(pol);
      else if (!t) e.polities.push(token);
    }

    e.perspectives = [...form.querySelectorAll('.view-row')]
      .map(row => ({ track: row.querySelector('.view-track').value, title: row.querySelector('.view-title').value.trim(), description: row.querySelector('.view-desc').value.trim() }))
      .filter(v => v.title || v.description)
      .map(v => Object.fromEntries(Object.entries(v).filter(([, val]) => val)));
    e.treaty = HT.readTreatyFields(form, problems) || undefined; // 조약 규격 — 비었으면 칸이 사라져 보통 사건 (DLC 항목의 수정에서는 null로 원래 조약을 뗌)
    Object.assign(e, HT.readLensFields(form, problems)); // 주제 꼬리표 · 법 규격 · 선거 규격 (형식 버전 3 — 같은 규칙)
    if (el.place) e.place = el.place.value.trim() || undefined; // 장소 · 이름 목록 (형식 버전 3 — 폼에 그 칸이 있을 때만)
    if (el.polity) e.polity = el.polity.value.trim() || undefined; // 정권 — 비우면 칸이 빠지고(그 해의 정권), 남의 사건에서는 null로 원래 값을 비움
    if (form.querySelector('[data-names-field]')) e.names = HT.readNamesField(form, problems);

    if (!e.title) problems.push('제목을 입력하세요.');
    if (e.startRange && e.start != null && !isNaN(e.start) && (e.start < e.startRange[0] || e.start > e.startRange[1]))
      problems.push('시작 연도가 시작 연대 폭 밖에 있습니다.');
    if (e.parent && e.parent === e.title) problems.push('자기 자신을 상위 사건으로 지정할 수 없습니다.');
    return { event: e, problems };
  };

  /* ---------- 색 고르기: 파스텔 견본 ----------
   * 폼 안: HT.swatchesHTML('color') → 숨은 input[name=color] + 견본 단추들. HT.bindSwatches(form)로 한 번 연결.
   * 표 안: HT.pickColor(anchor, current) → 작은 팝오버에서 고른 색(Promise). */
  HT.hex6 = c => (!HT.isColor(c) ? '#888888' : c.length === 4 ? `#${[...c.slice(1)].map(h => h + h).join('')}` : c);
  const val = x => HT.escapeHtml(x == null ? '' : x);
  HT.swatchesHTML = (name = 'color', current = '') =>
    `<span class="swatches" data-swatches="${name}" role="radiogroup" aria-label="색"><input type="hidden" name="${name}" value="${val(current)}">${HT.PASTEL.map(
      c => `<button type="button" class="sw${c.id === current ? ' is-on' : ''}" data-sw="${c.id}" style="--c:${c.id}" title="${c.name}" role="radio" aria-checked="${c.id === current}"></button>`
    ).join('')}</span>`;
  HT.setSwatch = (form, name, value) => {
    const box = form.querySelector(`[data-swatches="${name}"]`);
    if (!box) return;
    const v = HT.pastel(value || '');
    box.querySelector('input').value = v;
    box.querySelectorAll('.sw').forEach(b => {
      const on = b.dataset.sw === v;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-checked', String(on));
    });
  };
  HT.bindSwatches = form => {
    if (form.dataset.swatchBound) return;
    form.dataset.swatchBound = '1';
    form.addEventListener('click', e => {
      const b = e.target.closest('.sw[data-sw]');
      if (!b || !form.contains(b)) return;
      e.preventDefault();
      const box = b.closest('[data-swatches]');
      const input = box.querySelector('input');
      HT.setSwatch(form, box.dataset.swatches, b.dataset.sw);
      if (form.elements.useColor) form.elements.useColor.checked = true;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    });
  };
  HT.pickColor = (anchor, current) =>
    new Promise(resolve => {
      document.querySelectorAll('.sw-pop').forEach(p => p.remove());
      const pop = document.createElement('div');
      pop.className = 'sw-pop';
      pop.innerHTML = HT.PASTEL.map(c => `<button type="button" class="sw${c.id === current ? ' is-on' : ''}" data-sw="${c.id}" style="--c:${c.id}" title="${c.name}"></button>`).join('') + '<button type="button" class="sw sw-auto" data-sw="" title="자동">자동</button>';
      document.body.appendChild(pop);
      const r = anchor.getBoundingClientRect();
      pop.style.left = `${Math.min(r.left, innerWidth - pop.offsetWidth - 8)}px`;
      pop.style.top = `${r.bottom + 6 + pop.offsetHeight > innerHeight ? r.top - pop.offsetHeight - 6 : r.bottom + 6}px`;
      const done = v => {
        pop.remove();
        document.removeEventListener('pointerdown', outside, true);
        resolve(v);
      };
      const outside = e => {
        if (!pop.contains(e.target)) done(null);
      };
      setTimeout(() => document.addEventListener('pointerdown', outside, true), 0);
      pop.addEventListener('click', e => {
        const b = e.target.closest('[data-sw]');
        if (b) done(b.dataset.sw);
      });
    });
  /* 승계 한 줄: 칸 이름은 바로 위 소속 줄처럼 칸 안의 흐린 글자(칸 이름뿐 — 실제 이름 예시는 없음) + aria-label · 풍선(title).
     흐린 글자를 메이커에서 모두 걷을지는 한꺼번에 정할 일이라(이 줄만 걷으면 같은 폼에서 어긋나고, 풍선이 없는 터치 기기에서는 둘째 칸이 무엇인지 알 길이 없음) 여기서는 그대로 */
  /* 부분 승계를 고르면 줄 아래에 정도 단추 셋(약 · 중 · 강 — 하나만 눌림)과 이어진 것 단추 다섯(켜고 끔)이 나옵니다(.s-partial — 한 줄 전체 폭, 좁으면 묶음째 꺾임).
     단추 글은 칸 이름 · 값 이름뿐(예시 값 없음) */
  const succPartialHTML = s => {
    const type = HT.successionType(s.type);
    const deg = HT.succDegree(s.degree) || HT.SUCC_DEGREE_DEFAULT;
    const parts = (Array.isArray(s.parts) ? s.parts : []).map(HT.succPart);
    return `<div class="s-partial"${type === 'partial' ? '' : ' hidden'}>
        <span class="sp-grp" role="group" aria-label="정도"><span class="sp-lab">정도</span>${HT.SUCC_DEGREES.map(d => `<button type="button" class="sp-btn" data-sp-deg="${d.id}" aria-pressed="${d.id === deg}" title="정도 ${d.name} — 연표의 세 줄 가닥 가운데 진한 줄 ${d.id}개">${d.name}</button>`).join('')}</span>
        <span class="sp-grp" role="group" aria-label="이어진 것"><span class="sp-lab">이어진 것</span>${HT.SUCC_PARTS.map(p => `<button type="button" class="sp-btn" data-sp-part="${p.id}" aria-pressed="${parts.includes(p.id)}" title="이어진 것 — ${p.name} (켜고 끔 · 여러 개)">${p.name}</button>`).join('')}</span>
        <span class="sp-hint">${val(HT.SUCCESSION.find(t => t.id === 'partial').hint.split(' — ')[0].replace(/·/g, ' · '))}</span></div>`;
  };
  HT.succRowHTML = (s = {}) => `<div class="succ-row">
      <input class="s-from" list="mkPolityList" placeholder="이어받은 정권" aria-label="이어받은 정권" title="이어받은 정권 — 이 정권이 이어받은 앞 정권의 이름" value="${val(s.from)}">
      <select class="s-type" aria-label="승계 종류" title="승계 종류 — 직접 승계(실선) · 간접 승계(점선) · 부흥(점선 + 작은 고리) · 부분 승계(가는 실선)">${HT.SUCCESSION.map(t => `<option value="${t.id}" title="${val(t.hint)}"${HT.successionType(s.type) === t.id ? ' selected' : ''}>${val(t.name)}</option>`).join('')}</select>
      <select class="s-how" aria-label="승계 방식" title="승계 방식 — 어떻게 넘어갔는지(혼인 · 상속 · 정복 · 갈라짐 · 합쳐짐 · 개명 · 주장 · 선양) · 고르지 않아도 됩니다"><option value="">방식 —</option>${HT.SUCC_HOWS.map(h => `<option value="${h.id}"${HT.succHow(s.how) === h.id ? ' selected' : ''}>${val(h.name)}</option>`).join('')}</select>
      <input class="s-note" placeholder="메모 (선택)" aria-label="메모" title="메모 (선택) — 왜 승계로 보는지 등" value="${val(s.note)}">
      <button type="button" class="icon-btn" data-succ-del aria-label="삭제">✕</button>${succPartialHTML(s)}</div>`;
  /* 칸의 미정 — 줄 입력의 시작 · 끝 칸: 미정이면 칸에 "미정"이라고 쓰고, 파일에 있던 배치용 연도는 줄(div)의 data-start-hint · data-end-hint에 남겨
     폼을 고쳐 저장해도 줄지 않게 합니다 (모델이 짐작해 넣은 자리 — startAuto · endAuto — 는 남기지 않음) */
  const edgeVal = (c, key) => (c && c[`${key}Unknown`] ? '미정' : HT.dateInputValue(c, key));
  const hintAttrs = c => ['start', 'end'].map(k => (c && c[`${k}Unknown`] && typeof c[k] === 'number' && isFinite(c[k]) && !c[`${k}Auto`] ? ` data-${k}-hint="${c[k]}"` : '')).join('');
  const UNK_TIP = ' · 모르면 미정';
  /* 소속 관계 고르기(시대 폼의 소속 줄에서만): 종속 갈래는 자율성이 높은 것부터, 그 밖(구성국 · 동군연합)은 따로 묶습니다 */
  const relationSelectHTML = cur =>
    `<select class="s-rel" aria-label="소속 관계" title="소속 관계 — 상국 띠에 달리는 이름표의 자리 · 칠이 달라집니다 (고르지 않아도 됩니다)"><option value="">소속 관계 없음</option>${[['종속 (자율성이 높은 것부터)', r => r.autonomy != null], ['그 밖', r => r.autonomy == null]]
      .map(([label, pick]) => `<optgroup label="${val(label)}">${HT.RELATIONS.filter(pick).map(r => `<option value="${r.id}"${cur === r.id ? ' selected' : ''}>${val(r.name)}</option>`).join('')}</optgroup>`)
      .join('')}</select>`;
  /** 놓는 자리를 적지 않았을 때의 기본: 소속 관계가 없거나 구성국이면 상위 띠 아래에 접고, 그 밖의 관계면 제 줄 (모델의 singleHost 규칙과 같음) */
  HT.nestDefault = relation => !relation || relation === 'member';
  /** 소속(예속) 한 줄: 상위 정권 · 기간 · 메모. 여러 줄이면 차례로 예속된 것.
      opt.relation === true(시대 폼)일 때만 소속 관계 고르기와 `상위 띠 아래에 접기` 체크가 붙습니다 — 같은 줄을 쓰는 기관 · 왕조 폼에는 없습니다.
      (.map(HT.partOfRowHTML)처럼 부르면 둘째 인자로 순번이 오므로, 옵션은 꼭 객체의 relation === true로만 켭니다) */
  HT.partOfRowHTML = (s = {}, opt) => {
    const rel = opt && opt.relation === true;
    const relation = rel ? HT.relationId(s.relation) : '';
    const explicit = s.nest === true || s.nest === false;
    return `<div class="succ-row part-row"${hintAttrs(s)}>
      <input class="s-from" list="mkPolityList" placeholder="상위 정권" title="연맹·종주국·속한 나라" value="${val(s.polity)}">
      ${rel ? relationSelectHTML(relation) : ''}
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="예속 시작 — 연도나 날짜 (비우면 처음부터${UNK_TIP})" value="${val(edgeVal(s, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="예속 끝 — 연도나 날짜 (비우면 끝까지${UNK_TIP})" value="${val(edgeVal(s, 'end'))}">
      <input class="s-note" placeholder="메모 (선택)" value="${val(s.note)}">
      ${rel ? `<label class="check s-nest-wrap" title="켜면 상위 정권 띠 아래에 접혀 있다가 단추(▸)로 펼쳐지고, 끄면 제 줄에 섭니다 (어느 쪽이든 예속 관계는 상국 띠의 이름표로 보입니다) — 상위 정권이 하나이고 기간을 비웠으며 같은 트랙에 있을 때만 접을 수 있습니다"><input type="checkbox" class="s-nest"${explicit ? ' data-touched="1"' : ''}${(explicit ? s.nest : HT.nestDefault(relation)) ? ' checked' : ''}> 상위 띠 아래에 접기</label>` : ''}
      ${rel ? `<label class="check s-main-wrap" title="으뜸 그릇(형식 4 within.main) — 여러 그릇에 들 때 구조 나무 · 서고가 기준으로 삼는 그릇"><input type="checkbox" class="s-main"${s.main === true ? ' checked' : ''}> 으뜸</label>` : ''}
      <span class="row-end">${HT.caltBtnHTML(s)}<button type="button" class="icon-btn" data-part-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(s)}</div>`;
  };
  /** 시대 폼의 소속 줄 상태 맞추기: 접을 수 없는 줄(여러 줄이거나 기간을 적은 줄)의 `상위 띠 아래에 접기`는 흐리게 잠급니다 */
  HT.syncPartRows = form => {
    const rows = [...form.querySelectorAll('[data-parts][data-relation] .part-row')];
    for (const row of rows) {
      const nest = row.querySelector('.s-nest');
      if (!nest) continue;
      const moot = rows.length > 1 || !!row.querySelector('.c-start').value.trim() || !!row.querySelector('.c-end').value.trim();
      nest.disabled = moot;
      nest.closest('.s-nest-wrap').classList.toggle('is-off', moot);
    }
  };
  /* 지도자 줄의 표기 낱말(리메이크 6단계 D3 · 걸음 3): 칸(묘호 · 시호 · 이름)은 그대로, 줄의 회색 글 · 풍선만 그 정권의 낱말(HT.leaderWords — 문화권 → 팩 → 기본)로.
     폼을 채울 때(HT.fillCellRows) 그 항목의 낱말로 정하고, 그 폼에서 더하는 줄도 같은 낱말 */
  let formWords = null;
  const formWord = k => (formWords && formWords[k]) || HT.LEADER_WORDS[k];
  const FORM_WORD_ROLE = { temple: '묘호 자리 — 묘호 · 치세명 · 교황명 · 라캅', title: '시호 자리 — 시호 · 존호 · 별명', given: '이름 자리 — 이름 · 본명 · 휘 · 세례명' };
  const formWordTip = k => `${formWord(k)} (${FORM_WORD_ROLE[k]} · 있는 것만 · 낱말은 팩 정보 · 「문화권」 표가 정함)`;
  HT.cellRowHTML = (kind, c = {}) =>
    kind === 'ranks' ? HT.rankRowHTML(c) : kind === 'faiths' ? HT.faithRowHTML(c) : kind === 'capitals'
      ? `<div class="cell-row is-capital"${c.event ? ` data-event="${val(c.event)}"` : ''}${hintAttrs(c)}>
      <input class="c-name" placeholder="도시" title="도시 — 다른 나라가 같은 도시를 썼으면 같은 이름으로 적으면 이어집니다" value="${val(c.city)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜 (1232 · 1232-07-06 · 음력 1232-06-16${UNK_TIP})" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="비우면 다음 정도가 시작할 때까지 (배도는 정권 끝까지${UNK_TIP})" value="${val(edgeVal(c, 'end'))}">
      <select class="c-role" title="역할">${HT.CAPITAL_ROLES.map(r => `<option value="${r.id}"${(c.role || 'main') === r.id ? ' selected' : ''}>${r.name}</option>`).join('')}</select>
      <input class="c-as" placeholder="그때 이름" title="그 나라가 부른 이름 — 비우면 도시 이름" value="${val(c.as)}">
      <input class="c-label" placeholder="시기 이름" title="맨 위 도읍 줄에 적을 시기 이름 — 비우면 그때 이름" value="${val(c.label)}">
      <input class="c-group" placeholder="묶음" title="배도 묶음 — 같은 묶음의 배도는 도읍 줄·노선도에서 한 칸으로" value="${val(c.group)}">
      <input class="c-event" list="mkEventList" placeholder="천도 사건" title="천도 사건 — 이 DLC 사건의 id나 제목 (선택)" value="${val(c.event)}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-cell-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}</div>`
      : kind === 'leaders'
      ? `<div class="cell-row is-leader"${hintAttrs(c)}>
      <input class="c-ordinal" type="text" inputmode="numeric" placeholder="대수" title="대수 — 그 나라 역사 서술의 순번 &quot;제n대&quot; (비우면 앞 지도자에 이어 자동 · 모르면 미상)" value="${val(c.ordinalUnknown ? '미상' : c.ordinal)}">
      <input class="c-regnal" type="text" inputmode="numeric" autocomplete="off" placeholder="n세" title="이름 번호 — 대표 이름 뒤에 붙는 &quot;n세&quot;(헨리 8세의 8 · 순번인 대수와 다름 · 양의 정수) · 이 줄에 하나라도 적으면 빈 대수를 자동으로 매기지 않습니다" value="${val(c.regnal)}">
      <input class="c-name" placeholder="대표 이름" title="연표에 기본으로 보이는 이름" value="${val(c.name)}">
      ${['temple', 'title', 'given'].map(k => `<input class="c-${k}" placeholder="${val(formWord(k))}" title="${val(formWordTip(k))}" value="${val(c[k])}">`).join('\n      ')}
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="시작 — 연도나 날짜 (1418 · 1418-09-09 · 음력 1418-08-10${UNK_TIP})" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="끝 — 연도나 날짜${UNK_TIP}" value="${val(edgeVal(c, 'end'))}">
      <input class="c-dynasty" list="mkDynastyList" placeholder="왕조 (선택)" title="이 지도자의 왕조 — 비우면 이 지도자가 시작한 해의 왕조로 채웁니다" value="${val(c.dynasty)}">
      <input class="c-rank" list="mkRankList" placeholder="지위" title="이 지도자의 지위 — 비우면 이 지도자가 시작한 해의 정권 지위(지위 변천)로 채웁니다" value="${val(c.rank)}">
      <input class="c-house" list="mkHouseList" placeholder="가문" title="이 지도자의 가문 — 비우면 이 지도자가 시작한 해의 왕조의 가문, 그것도 없으면 나라의 국성으로 봅니다" value="${val(c.house)}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${HT.cxBtnHTML('leaders', c)}${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-cell-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}${HT.cxBoxHTML('leaders', c)}</div>`
      : kind === 'cabinets'
      ? `<div class="cell-row is-cabinet"${hintAttrs(c)}>
      <input class="c-name" placeholder="내각 이름" value="${val(c.name)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜${UNK_TIP}" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜${UNK_TIP}" value="${val(edgeVal(c, 'end'))}">
      <input class="c-house" list="mkHouseList" placeholder="가문" title="이 내각을 이끈 가문 (선택)" value="${val(c.house)}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${HT.cxBtnHTML('cabinets', c)}${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-cell-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}${HT.cxBoxHTML('cabinets', c)}</div>`
      : `<div class="cell-row"${hintAttrs(c)}>
      <input class="c-name" placeholder="${kind === 'cabinets' ? '내각 이름' : '연호'}" value="${val(c.name)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜${UNK_TIP}" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜${UNK_TIP}" value="${val(edgeVal(c, 'end'))}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${kind === 'eras' ? HT.cxBtnHTML('eras', c) : ''}${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-cell-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}${kind === 'eras' ? HT.cxBoxHTML('eras', c) : ''}</div>`;
  HT.cellPasteHTML = kind => `<details class="cell-paste"><summary>여러 줄 한꺼번에 붙여넣기</summary>
      <textarea class="cells" rows="4" aria-label="한 줄에 한 칸씩" data-paste-text="${kind}"></textarea>
      <button type="button" class="btn btn-sm" data-cell-paste="${kind}">줄을 칸으로 추가</button>
      <p class="cells-hint">한 줄에 하나씩 "이름 시작~끝 메모". 날짜도 됩니다(1418-09-09 · 음력:1418-08-10). 연도만이면 "이름 시작-끝"도 되고, 기원전은 음수(-220~-194). 끝을 비우면 정권이 끝날 때까지. 시작이나 끝을 모르면 "미정"("이름 미정~끝"), 세기로만 알면 "3세기중반"("이름 3세기초~490" · 기원전은 "-2세기말").</p></details>`;
  const numOrNull = s => {
    const t = String(s ?? '').trim();
    if (t === '') return null;
    const n = Number(t);
    return isFinite(n) ? Math.round(n) : NaN;
  };
  /** 칸의 연도·날짜 글 → null · { t, at } · { t: NaN, error } */
  const dateOrNull = s => HT.readDate(String(s ?? '').trim());
  const putDate = (o, key, d) => {
    if (!d || isNaN(d.t)) return;
    o[key] = d.t;
    if (d.at) o[`${key}At`] = d.at;
  };
  /** 줄의 시작 · 끝 칸 → null(비움) · { unknown: true, t: 배치용 연도 | null } · { t, at, error } — "미정"이면 줄에 남겨 둔 배치용 연도(data-start-hint)를 잇습니다 */
  const rowEdge = (row, key) => {
    const v = ((row.querySelector(`.c-${key}`) || {}).value ?? '').trim();
    if (!HT.isUnknownText(v)) return dateOrNull(v);
    const h = row.dataset[`${key}Hint`];
    return { unknown: true, t: h != null && h !== '' && isFinite(Number(h)) ? Number(h) : null };
  };
  /** 칸 한쪽 끝을 파일의 꼴로: 미정이면 (배치용 연도 +) startUnknown: true, 아니면 값과 날짜 글 */
  const putEdge = (o, key, d) => {
    if (!d || !d.unknown) return putDate(o, key, d);
    if (d.t != null) o[key] = d.t;
    o[`${key}Unknown`] = true;
  };
  const known = d => !!d && !d.unknown;
  HT.readCellRows = (form, kind, label, problems) => {
    if (kind === 'ranks') return HT.readRankRows(form, problems); // 지위 변천: 첫 줄의 시작은 비워도 됩니다
    if (kind === 'faiths') return HT.readFaithRows(form, problems); // 종교(6단계 D8): 지위 변천과 같은 꼴
    const out = [];
    if (kind === 'capitals') {
      form.querySelectorAll('[data-cells="capitals"] .cell-row').forEach((row, i) => {
        const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const sd = rowEdge(row, 'start');
        const ed = rowEdge(row, 'end');
        const o = { city: g('c-name') };
        if (sd && sd.unknown) putEdge(o, 'start', sd);
        else {
          o.start = sd ? sd.t : null;
          if (sd && sd.at) o.startAt = sd.at;
        }
        if (!o.city && sd == null && ed == null) return;
        if (!o.city) problems.push(`${label} ${i + 1}번째 줄: 도시가 없습니다.`);
        if (!(sd && sd.unknown) && (o.start == null || isNaN(o.start))) problems.push(`${label} ${i + 1}번째 줄: 시작 연도가 없거나 올바르지 않습니다(모르면 "미정").${sd && sd.error ? ` (${sd.error})` : ''}`);
        if (known(ed) && isNaN(ed.t)) problems.push(`${label} ${i + 1}번째 줄: 끝 연도가 올바르지 않습니다.${ed.error ? ` (${ed.error})` : ''}`);
        if (known(ed) && known(sd) && o.start != null && !isNaN(ed.t) && HT.endBound(ed.t, ed.at) < o.start) problems.push(`${label} ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
        putEdge(o, 'end', ed);
        const role = g('c-role');
        if (role && role !== 'main') o.role = role;
        for (const [k, cls] of [['as', 'c-as'], ['label', 'c-label'], ['group', 'c-group'], ['event', 'c-event'], ['note', 'c-note']]) if (g(cls)) o[k] = g(cls); // 천도 사건(event)은 줄의 칸에서 (2026-10-23 — 옛 폼은 data-event로 보존)
        if (!o.event && !row.querySelector('.c-event') && row.dataset.event) o.event = row.dataset.event;
        Object.assign(o, HT.readCellAlts(row, problems, `${label} ${i + 1}번째 줄`, o)); // 확실성 · 연대 폭 · 이설 (줄 안의 상자)
        out.push(o);
      });
      return out;
    }
    form.querySelectorAll(`[data-cells="${kind}"] .cell-row`).forEach((row, i) => {
      const g = cls => (row.querySelector(`.${cls}`) || {}).value ?? '';
      const sd = rowEdge(row, 'start');
      const ed = rowEdge(row, 'end');
      const c = { name: g('c-name').trim(), start: known(sd) ? sd.t : null, end: known(ed) ? ed.t : null, note: g('c-note').trim() };
      if (kind === 'leaders' || kind === 'office') { // office = 직위 줄 더의 칸(지도자 칸과 같은 칸 — 5단계 과제 4)
        c.temple = g('c-temple').trim();
        c.title = g('c-title').trim();
        c.given = g('c-given').trim();
        c.ordinalUnknown = HT.isUnknownOrdinal(g('c-ordinal')); // "미상"
        c.ordinal = c.ordinalUnknown ? null : numOrNull(g('c-ordinal'));
        c.regnal = HT.readRegnal(g('c-regnal').trim().replace(/\s*세$/, '')); // 이름 번호(6단계 D2 — "8" · "8세" · 칸이 없는 옛 폼이면 빈 값)
        c.dynasty = g('c-dynasty').trim();
        c.rank = g('c-rank').trim(); // 지위 (칸이 없는 옛 폼이면 빈 값)
        if (!c.name) c.name = c.temple || c.title || c.given;
      }
      if (!c.name && !sd && !ed && !c.note) return;
      if (!c.name) problems.push(`${label} ${i + 1}번째 줄: 이름이 없습니다.`);
      if ((kind === 'leaders' || kind === 'office') && Number.isNaN(c.regnal)) problems.push(`${label} ${i + 1}번째 줄: 이름 번호 "${g('c-regnal').trim()}"은(는) 양의 정수로 적습니다(헨리 8세의 8 — 순번 "제n대"는 대수 칸에).`);
      if ((kind === 'leaders' || kind === 'office') && /세$/.test(g('c-ordinal').trim())) problems.push(`${label} ${i + 1}번째 줄: 대수 칸에 "${g('c-ordinal').trim()}"을(를) 적었습니다 — "n세"는 이름 번호 칸에, 대수 칸은 순번(제n대)입니다.`);
      if (!(sd && sd.unknown) && (c.start == null || isNaN(c.start))) problems.push(`${label} ${i + 1}번째 줄: 시작 연도가 없거나 올바르지 않습니다(모르면 "미정").${sd && sd.error ? ` (${sd.error})` : ''}`);
      if (c.end != null && isNaN(c.end)) problems.push(`${label} ${i + 1}번째 줄: 끝 연도가 올바르지 않습니다.${ed && ed.error ? ` (${ed.error})` : ''}`);
      if (c.end != null && c.start != null && !isNaN(c.end) && !isNaN(c.start) && HT.endBound(c.end, ed && ed.at) < c.start) problems.push(`${label} ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
      const o = { name: c.name };
      if (sd && sd.unknown) putEdge(o, 'start', sd);
      else {
        o.start = c.start;
        if (sd && sd.at) o.startAt = sd.at;
      }
      if (ed && ed.unknown) putEdge(o, 'end', ed);
      else if (c.end != null) putDate(o, 'end', ed);
      if (c.note) o.note = c.note;
      if (kind === 'leaders' || kind === 'office') { // office = 직위 줄 더의 칸(지도자 칸과 같은 칸 — 5단계 과제 4)
        if (c.temple) o.temple = c.temple;
        if (c.title) o.title = c.title;
        if (c.given) o.given = c.given;
        if (c.ordinalUnknown) o.ordinalUnknown = true;
        else if (c.ordinal != null && !isNaN(c.ordinal)) o.ordinal = c.ordinal;
        if (c.regnal > 0) o.regnal = c.regnal; // 이름 번호(6단계 D2)
        if (c.dynasty) o.dynasty = c.dynasty;
        if (c.rank) o.rank = c.rank;
      }
      if (kind === 'leaders' || kind === 'cabinets' || kind === 'office') {
        const house = g('c-house').trim(); // 가문 — 지도자 · 내각 줄만 (줄에 칸이 없으면 빈 값)
        if (house) o.house = house;
      }
      Object.assign(o, HT.readCellAlts(row, problems, `${label} ${i + 1}번째 줄`, o)); // 확실성 · 연대 폭 · 이설 (줄 안의 상자)
      Object.assign(o, HT.readCellX(row, problems, `${label} ${i + 1}번째 줄`)); // 사람 · 자리 이음 · 부모 · 배우자 · 이름 (줄 안의 사람 상자 — 형식 버전 3)
      out.push(o);
    });
    return out;
  };
  /* 승계 줄 읽기 — 파일 읽기와 같은 정리(HT.normalizeSucc)를 거쳐, 폼을 열었다 그대로 저장해도 파일의 줄과 같게(부분 승계의 정도는 늘 적힘) */
  HT.readSuccRows = form =>
    [...form.querySelectorAll('[data-succ] .succ-row')]
      .map(row => {
        const type = row.querySelector('.s-type').value;
        const on = sel => [...row.querySelectorAll(`.s-partial [${sel}][aria-pressed="true"]`)];
        const raw = { from: row.querySelector('.s-from').value.trim(), type, note: row.querySelector('.s-note').value.trim() };
        const how = row.querySelector('.s-how'); // 승계 방식(6단계 결정 15) — 고르지 않으면 적지 않음
        if (how && how.value) raw.how = how.value;
        if (type === 'partial') {
          const d = on('data-sp-deg')[0];
          raw.degree = d ? Number(d.dataset.spDeg) : HT.SUCC_DEGREE_DEFAULT;
          raw.parts = on('data-sp-part').map(b => b.dataset.spPart);
        }
        return HT.normalizeSucc(raw);
      })
      .filter(Boolean);
  HT.readPartOfRows = (form, problems) =>
    [...form.querySelectorAll('[data-parts] .part-row')]
      .map((row, i) => {
        const o = { polity: row.querySelector('.s-from').value.trim() };
        /* 소속 관계 · 놓는 자리(시대 폼의 줄에만 있음): 놓는 자리는 기본(관계가 없거나 구성국 = 접기 · 그 밖 = 제 줄)과 다를 때만 적습니다 */
        const relEl = row.querySelector('.s-rel');
        const nestEl = row.querySelector('.s-nest');
        if (relEl && relEl.value) o.relation = relEl.value;
        if (nestEl && nestEl.checked !== HT.nestDefault(o.relation)) o.nest = nestEl.checked;
        const mainEl = row.querySelector('.s-main');
        if (mainEl && mainEl.checked) o.main = true; // 으뜸 그릇(형식 4 within.main)
        const s = rowEdge(row, 'start');
        const e = rowEdge(row, 'end');
        if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) problems.push(`소속 ${i + 1}번째 줄: 연도가 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
        putEdge(o, 'start', s);
        putEdge(o, 'end', e);
        if (known(s) && known(e) && o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) problems.push(`소속 ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
        const note = row.querySelector('.s-note').value.trim();
        if (note) o.note = note;
        Object.assign(o, HT.readCellAlts(row, problems, `소속 ${i + 1}번째 줄`, o)); // 확실성 · 연대 폭 · 이설 (줄 안의 상자)
        return o;
      })
      .filter(s => s.polity);
  /* ---------- 객체 폼의 직위 줄(5단계 과제 4): 빌려 보기 · 직위 줄 더 · 실권 ----------
     빌려 보기(지도자 · 내각 자리): 켜면 그 자리의 칸 줄이 숨고 출처("객체 id" 또는 "객체 id/직위 이름")와 줄 이름을 적습니다 — 저장은 leadersFrom · cabinetsFrom { from, name? }.
     직위 줄 더(세 번째 줄부터): 이름 + 칸 줄(지도자 칸과 같은 칸 — 읽기는 readCellRows의 'office' 갈래) 또는 빌려 오기(from을 적으면 칸 줄이 숨음) — 저장은 offices[].
     실권: 이 객체가 남의 실권을 쥔 기간 — 쥔 쪽에만 적고 상대(over)는 빼앗긴 객체 — 저장은 power[] (서고는 빼앗긴 쪽 띠 머리에 쥔 쪽 색 밑줄 · 과제 9) */
  HT.borrowRowHTML = slot => {
    const word = slot === 'cabinets' ? '내각' : '지도자';
    return `<div class="borrow-row" data-borrow="${slot}" title="다른 객체의 직위 줄을 이 자리에서 함께 봅니다(같은 자리 · 같은 사람 — 교황이 기사단장을 겸하듯) · 형식 4의 offices[].from">
      <label class="check"><input type="checkbox" class="b-on"> 빌려 보기</label>
      <span class="b-lab">출처</span><input class="b-from" list="mkPolityList" aria-label="${word} 줄의 출처" title="빌려 올 객체의 id(그 객체의 지도자 줄) 또는 &quot;객체 id/직위 이름&quot;" disabled>
      <span class="b-lab">줄 이름</span><input class="b-name" aria-label="${word} 자리의 줄 이름" title="비우면 ${word}" disabled></div>`;
  };
  HT.officeLineHTML = (f = {}) => `<div class="office-line${f.from ? ' is-borrowed' : ''}" data-office>
      <div class="o-head">
        <input class="o-name" placeholder="직위 이름" title="세 번째 줄부터의 직위 이름 (지도자 · 내각은 위의 자리)" value="${val(f.name)}">
        <input class="o-from" list="mkPolityList" placeholder="빌려 오기 — 객체 id 또는 id/직위 (비우면 아래 칸을 씀)" value="${val(f.from)}">
        <span class="row-end"><button type="button" class="icon-btn" data-office-del aria-label="삭제">✕</button></span></div>
      <div class="cell-rows" data-cells="office">${(Array.isArray(f.cells) ? f.cells : []).map(c => HT.cellRowHTML('leaders', HT.formCell('leaders', c))).join('')}</div>
      <div class="toolbar"><button type="button" class="btn btn-sm" data-office-cell-add>＋ 칸 추가</button></div></div>`;
  HT.objectPowerRowHTML = (w = {}) => `<div class="succ-row op-row" data-object-power-row${hintAttrs(w)}>
      <input class="pw-over" list="mkPolityList" placeholder="상대 — 빼앗긴 객체의 id나 이름" title="실권을 빼앗긴 객체 (쥔 쪽인 이 객체에만 적습니다) — 비우고 이름만 적으면 이 객체 안의 실권자(세도 가문 · 권신)" value="${val(w.over)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜 (비우면 처음부터${UNK_TIP})" value="${val(edgeVal(w, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜 (비우면 끝까지${UNK_TIP})" value="${val(edgeVal(w, 'end'))}">
      <input class="pw-name" placeholder="이름 (선택 · 섭정 · 막부)" value="${val(w.name)}">
      <input class="s-note" placeholder="메모 (선택)" value="${val(w.note)}">
      <span class="row-end"><button type="button" class="icon-btn" data-power-del aria-label="삭제">✕</button></span></div>`;
  /** 빌려 보기 줄의 켜고 끔을 자리에 맞춤: 켜면 그 자리의 칸 줄 · 단추 · 붙여넣기를 숨기고 출처 칸을 엽니다 */
  HT.syncBorrowRows = form => {
    for (const row of form.querySelectorAll('[data-borrow]')) {
      const on = row.querySelector('.b-on').checked;
      const field = row.closest('.field');
      if (field) field.classList.toggle('is-borrowed', on);
      row.querySelector('.b-from').disabled = !on;
      row.querySelector('.b-name').disabled = !on;
    }
  };
  HT.fillOfficeExtras = (form, p) => {
    for (const [slot, key] of [['leaders', 'leadersFrom'], ['cabinets', 'cabinetsFrom']]) {
      const row = form.querySelector(`[data-borrow="${slot}"]`);
      if (!row) continue;
      const b = p[key] && typeof p[key] === 'object' ? p[key] : typeof p[key] === 'string' && p[key] ? { from: p[key] } : null;
      row.querySelector('.b-on').checked = !!(b && b.from);
      row.querySelector('.b-from').value = b && b.from ? b.from : '';
      row.querySelector('.b-name').value = (b && b.name) || '';
    }
    HT.syncBorrowRows(form);
    const offs = form.querySelector('[data-offices]');
    if (offs) offs.innerHTML = (Array.isArray(p.offices) ? p.offices : []).filter(f => f && typeof f === 'object').map(f => HT.officeLineHTML(f)).join('');
    const pw = form.querySelector('[data-object-power]'); // 객체의 실권(단체 폼의 집권 줄 data-gp-power · HT.powerRowHTML과 다른 것)
    if (pw) pw.innerHTML = (Array.isArray(p.power) ? p.power : []).filter(w => w && typeof w === 'object').map(w => HT.objectPowerRowHTML(w)).join('');
    const box = form.querySelector('details[data-adv="cells"]');
    if (box && ((p.offices || []).length || (p.power || []).length || (p.leadersFrom && p.leadersFrom.from) || (p.cabinetsFrom && p.cabinetsFrom.from))) box.open = true;
  };
  /** 빌려 보기 줄 → { name?, from } (끈 줄은 undefined · 켰는데 출처가 비면 문제) */
  HT.readBorrowRow = (form, slot, problems) => {
    const row = form.querySelector(`[data-borrow="${slot}"]`);
    if (!row || !row.querySelector('.b-on').checked) return undefined;
    const word = slot === 'cabinets' ? '내각' : '지도자';
    const from = row.querySelector('.b-from').value.trim();
    if (!from) {
      problems.push(`${word} 줄 빌려 보기: 출처(객체 id 또는 id/직위 이름)를 적으세요.`);
      return undefined;
    }
    const name = row.querySelector('.b-name').value.trim();
    const b = {};
    if (name && name !== word) b.name = name;
    b.from = from;
    return b;
  };
  /** 직위 줄 더 → offices[] ({ name, cells } 또는 { name?, from }) — 빈 목록이면 undefined */
  HT.readOfficeLines = (form, problems) => {
    const out = [];
    [...form.querySelectorAll('[data-office]')].forEach((line, i) => {
      const name = line.querySelector('.o-name').value.trim();
      const from = line.querySelector('.o-from').value.trim();
      if (from) {
        out.push(Object.assign(name ? { name } : {}, { from }));
        return;
      }
      const cells = HT.readCellRows(line, 'office', `직위 줄 ${i + 1}`, problems);
      if (!name && !cells.length) return;
      if (!name) problems.push(`직위 줄 ${i + 1}: 이름이 없습니다.`);
      out.push({ name, cells });
    });
    return out.length ? out : undefined;
  };
  /** 실권 줄 → power[] — 빈 목록이면 undefined */
  HT.readPowerRows = (form, problems) => {
    const out = [];
    [...form.querySelectorAll('[data-object-power-row]')].forEach((row, i) => {
      const over = row.querySelector('.pw-over').value.trim();
      const name = row.querySelector('.pw-name').value.trim();
      const note = row.querySelector('.s-note').value.trim();
      const s = rowEdge(row, 'start');
      const e = rowEdge(row, 'end');
      if (!over && !name && !note && s == null && e == null) return;
      if (!over && !name) problems.push(`실권 ${i + 1}번째 줄: 상대(빼앗긴 객체)나 이름(제 안의 실권자)을 적으세요.`);
      if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) problems.push(`실권 ${i + 1}번째 줄: 연도가 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
      const w = {};
      if (name) w.name = name;
      if (over) w.over = over;
      putEdge(w, 'start', s);
      putEdge(w, 'end', e);
      if (known(s) && known(e) && w.start != null && w.end != null && HT.endBound(w.end, w.endAt) < w.start) problems.push(`실권 ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
      if (note) w.note = note;
      out.push(w);
    });
    return out.length ? out : undefined;
  };
  /* ---------- 공용 폼: 이름 목록 · 사람 · 자리 이음 · 혈연 (형식 버전 3) ----------
     줄은 이설 줄과 같은 꼴(.alt-row — 칸마다 이름표를 위에, 회색 예시 글 없음): 이름 줄 = 글 · 언어 · 종류 · 쓴 기간 · 메모,
     부모 줄 = 사람 · 관계 · 몇 대손 · 확실성 · 메모, 배우자 줄 = 사람 · 혼인 기간 · 메모.
     지도자 · 내각 · 연호 줄에는 줄 끝 [이설] 앞에 [사람](연호는 [이름]) 단추 — 줄 아래 숨은 상자(.cell-xbox)를 펼칩니다: 사람 · 자리 이음(관계 · 방식 · 앞 지도자 · 메모) · 부모 · 배우자 · 이름(원어 등).
     사람 참조를 적은 칸은 원래 값(지도자 칸 객체 — 트랙까지)을 data-ref에 두어, 글을 고치지 않으면 그대로 돌려줍니다(설계 0-3 — 폼이 풀지 못하는 값은 data-*로).
     읽은 값은 파일과 같은 읽기(HT.readNames · readAccession · readParents · readSpouses)를 거쳐, 열어서 그대로 저장한 항목 · 칸은 한 글자도 달라지지 않습니다 */
  /** 줄의 기간 칸(.x-start · .x-end) → null(비움) · { unknown: true, t } · { t, at, error } — "미정"이면 줄에 남긴 배치용 연도(data-start-hint)를 잇습니다 */
  const xRowEdge = (row, key) => {
    const v = ((row.querySelector(`.x-${key}`) || {}).value ?? '').trim();
    if (!HT.isUnknownText(v)) return dateOrNull(v);
    const h = row.dataset[`${key}Hint`];
    return { unknown: true, t: h != null && h !== '' && isFinite(Number(h)) ? Number(h) : null };
  };
  const xPairHTML = (lab, c, tipS, tipE) =>
    `<span class="alt-f nm-when"><span class="alt-lab">${lab}</span><span class="alt-pair"><span class="alt-side"><input class="x-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${lab} — 시작" title="${tipS}" value="${val(edgeVal(c, 'start'))}"></span><span class="tilde">~</span><span class="alt-side"><input class="x-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" aria-label="${lab} — 끝" title="${tipE}" value="${val(edgeVal(c, 'end'))}"></span></span></span>`;
  /** 사람 참조 칸 (사람 · 부모 · 배우자 · 앞 지도자): 원래 값이 지도자 칸 객체면 data-ref에 */
  const refInputHTML = (cls, r, label, tip, list = 'mkWhoList') =>
    `<label class="alt-f x-ref-f"><span class="alt-lab">${label}</span><input class="${cls}" list="${list}" autocomplete="off" title="${tip}"${r && typeof r === 'object' ? ` data-ref="${val(JSON.stringify(r))}"` : ''} value="${val(HT.personRefText(r))}"></label>`;
  const readRefInput = el => {
    const text = el ? el.value.trim() : '';
    if (!text) return null;
    if (el.dataset.ref) {
      try {
        const o = JSON.parse(el.dataset.ref);
        if (HT.personRefText(o) === text) return o;
      } catch (e) {
        /* 깨진 보관 값 — 글로 읽음 */
      }
    }
    return HT.readPersonRef(text);
  };
  const WHO_TIP = '인물 id · 이름 · 지도자 칸의 이름, 또는 나라:지도자@시작 해 — 모르면 미상';
  /** 이름 한 줄 (이름 목록) */
  HT.nameRowHTML = (n = {}) => `<div class="alt-row name-row"${hintAttrs(n)}>
      <label class="alt-f nm-text"><span class="alt-lab">글</span><input class="x-text" dir="auto"${n.lang ? ` lang="${val(n.lang)}"` : ''} value="${val(n.text)}"></label>
      <label class="alt-f nm-lang"><span class="alt-lab">언어</span><input class="x-lang" list="mkLangList" spellcheck="false" autocomplete="off" title="언어 꼬리표 — ko · ja · zh-Hant · la · ar, 가상 언어는 x-로 시작 (비워도 됨)" value="${val(n.lang)}"></label>
      <label class="alt-f nm-kind"><span class="alt-lab">종류</span><input class="x-kind" list="mkNameKindList" title="원어 · 로마자 · 한자음 · 현지음 · 옛 이름 · 약칭, 또는 자유 글 (비워도 됨)" value="${val(n.kind ? HT.nameKindName(n.kind) : '')}"></label>
      ${xPairHTML('쓴 기간', n, '쓰기 시작한 때 — 연도나 날짜 (비우면 처음부터 · 모르면 미정)', '그친 때 — 연도나 날짜 (비우면 지금까지 · 모르면 미정)')}
      <label class="alt-f nm-note"><span class="alt-lab">메모</span><input class="x-note" value="${val(n.note)}"></label>
      <button type="button" class="icon-btn" data-name-del aria-label="이름 삭제" title="이름 삭제">✕</button>
    </div>`;
  /** 부모 · 조상 한 줄 */
  HT.parentRowHTML = (q = {}) => `<div class="alt-row kin-row parent-row">
      ${refInputHTML('x-who', q.whoUnknown ? '미상' : q.who, '사람', WHO_TIP)}
      <label class="alt-f kin-as"><span class="alt-lab">관계</span><input class="x-as" list="mkParentAsList" title="부 · 모 · 양부 · 양모 · 생부 · 생모 · 후손(몇 대 건너뛴 조상), 또는 자유 글" value="${val(q.as ? HT.parentRoleName(q.as) : '')}"></label>
      <label class="alt-f kin-gen"><span class="alt-lab">몇 대손</span><input class="x-gen" type="text" inputmode="numeric" autocomplete="off" title="관계가 후손일 때만 — 1 이상의 수" value="${val(q.gen ?? '')}"></label>
      <label class="alt-f kin-cert"><span class="alt-lab">확실성</span><select class="x-cert">${HT.CERTAINTY.map(v => `<option value="${v.id}"${v.id === (q.certainty || 'accepted') ? ' selected' : ''} title="${val(v.hint)}">${val(v.name)}</option>`).join('')}</select></label>
      <label class="alt-f nm-note"><span class="alt-lab">메모</span><input class="x-note" value="${val(q.note)}"></label>
      <button type="button" class="icon-btn" data-kin-del aria-label="줄 삭제" title="줄 삭제">✕</button>
    </div>`;
  /** 배우자 한 줄 */
  HT.spouseRowHTML = (q = {}) => `<div class="alt-row kin-row spouse-row"${hintAttrs(q)}>
      ${refInputHTML('x-who', q.whoUnknown ? '미상' : q.who, '사람', WHO_TIP)}
      ${xPairHTML('혼인 기간', q, '시작 — 연도나 날짜 (비워도 됨 · 모르면 미정)', '끝 — 연도나 날짜 (비워도 됨 · 모르면 미정)')}
      <label class="alt-f nm-note"><span class="alt-lab">메모</span><input class="x-note" value="${val(q.note)}"></label>
      <button type="button" class="icon-btn" data-kin-del aria-label="줄 삭제" title="줄 삭제">✕</button>
    </div>`;
  const NAMES_HINT = '원어 · 로마자 · 한자음 · 옛 이름 · 약칭 — 쓴 기간을 적으면 그때의 이름(국호 변천)';
  const namesRowsHTML = list => (Array.isArray(list) ? list : []).map(n => HT.nameRowHTML(n)).join('');
  const kinSecHTML = (type, list) =>
    `<div class="calt-sec" data-kin-sec="${type}"><span class="calt-cap">${type === 'parent' ? '부모 · 조상 <small>모르는 사람은 미상 — 세대 수를 지키는 빈 고리 · 몇 대 건너뛴 조상이면 관계를 후손으로 하고 몇 대손</small>' : '배우자'}</span>
        <div class="alt-rows" data-kin-rows="${type}">${(Array.isArray(list) ? list : []).map(q => (type === 'parent' ? HT.parentRowHTML(q) : HT.spouseRowHTML(q))).join('')}</div>
        <div class="toolbar"><button type="button" class="btn btn-sm" data-kin-add="${type}">＋ ${type === 'parent' ? '부모' : '배우자'} 추가</button></div></div>`;
  /** 폼에 한 번 두는 자동 완성 목록: 이름의 종류 · 언어 · 관계 · 오른 방식 · 부모 관계 · 사람(인물 이름) · 지명 */
  /** 사람 선택지 한 줄의 꼬리말: 생몰 · 가문 (5단계 과제 5 — 지도자 · 내각 칸의 사람 고르기에서 이름 옆에 보임) */
  HT.personOptionLabel = f => {
    const y = v => (v == null || v === '' ? '' : HT.isUnknownText(v) ? '?' : HT.formatYear(Number(v)));
    const life = [y(f.birth), y(f.death)].some(Boolean) ? `${y(f.birth)}–${y(f.death)}` : '';
    return [f.name, life, f.house].filter(Boolean).join(' · ');
  };
  HT.lineageListsHTML = ({ figureNames = [], placeNames = [], figures = [] } = {}) =>
    `<datalist id="mkNameKindList">${HT.NAME_KINDS.map(k => `<option value="${val(k.name)}"></option>`).join('')}</datalist>
    <datalist id="mkLangList">${['ko', 'ko-Latn', 'ja', 'zh', 'zh-Hant', 'zh-Hans', 'lzh', 'la', 'ar', 'he', 'mn', 'vi', 'x-'].map(v => `<option value="${v}">${val(v === 'x-' ? '가상 언어 (x- 뒤에 이름)' : HT.langName(v))}</option>`).join('')}</datalist>
    <datalist id="mkKinList">${HT.KIN_TYPES.map(k => `<option value="${val(k.name)}"></option>`).join('')}<option value="미상"></option></datalist>
    <datalist id="mkHowList">${HT.ACCESSION_HOWS.map(k => `<option value="${val(k.name)}"></option>`).join('')}<option value="미상"></option></datalist>
    <datalist id="mkParentAsList">${HT.PARENT_ROLES.map(k => `<option value="${val(k.name)}"></option>`).join('')}</datalist>
    <datalist id="mkPersonList">${[...new Set(figureNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkWhoList">${figures.length ? figures.filter(f => f && f.name).map(f => `<option value="${val(f.name)}" label="${val(HT.personOptionLabel(f))}"></option>`).join('') : [...new Set(figureNames)].map(n => `<option value="${val(n)}"></option>`).join('')}<option value="미상"></option></datalist>
    <datalist id="mkPlaceList">${[...new Set(placeNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>`;
  /* 이름 칸 안의 文 단추 (10건 3 · 감독 결정 D2-6 A): 시대 · 왕조 · 인물 · 사건(제목) · 단체 폼의 이름 칸 오른쪽 안. 누르면 이름 칸 바로 아래의
     명칭 목록(details.names-adv[data-adv="names"] — 접는 막대 없이 닫혀 있으면 0px)을 펼치고 접습니다. 이름이 있어도 처음에는 닫혀 있고 단추에 표기 수 딱지.
     단추 꼴은 바탕 자료 표의 文 단추(.mk-names-btn)와 같습니다 — 메이커 안에서 "명칭 목록 = 文" 하나. 줄 꼴 · 읽기는 F1 그대로(HT.namesFieldHTML · readNamesField) */
  HT.namesBtnHTML = () => '<button type="button" class="icon-btn mk-names-btn" data-names-toggle aria-expanded="false" aria-label="명칭 목록(원어 등)" title="명칭 목록(원어 등) — 누르면 이름 칸 아래에 펼칩니다">文</button>';
  const nameInHTML = input => `<span class="name-in">${input}${HT.namesBtnHTML()}</span>`;
  /** 文 단추를 명칭 목록의 지금 상태(펼침 · 표기 수)에 맞춥니다 (scope = 폼 · 문서) */
  HT.syncNamesBtn = scope => {
    for (const btn of (scope || document).querySelectorAll('[data-names-toggle]')) {
      const form = btn.closest('form') || scope || document;
      const box = form.querySelector('details.names-adv[data-adv="names"]');
      if (!box) continue;
      const n = [...box.querySelectorAll('[data-names-rows] > .name-row .x-text')].filter(i => i.value.trim()).length;
      const html = `文${n ? `<small>${n}</small>` : ''}`;
      if (btn.innerHTML !== html) btn.innerHTML = html;
      btn.classList.toggle('has-names', n > 0);
      btn.classList.toggle('is-open', box.open);
      btn.setAttribute('aria-expanded', String(box.open));
      btn.title = `명칭 목록(원어 등)${n ? ` ${n}개` : ''} — 누르면 이름 칸 아래에 ${box.open ? '접습니다' : '펼칩니다'}`;
    }
  };
  /** 항목의 이름 목록 칸 (시대 · 왕조 · 인물 · 사건 폼) — 줄은 [data-names-field] 바로 아래 [data-names-rows] */
  HT.namesFieldHTML = (hint = NAMES_HINT) => `<div class="field field-wide names-box" data-names-field><span>이름(원어 등) <small>${hint}</small></span>
      <div class="alt-rows" data-names-rows></div>
      <div class="toolbar"><button type="button" class="btn btn-sm" data-name-add>＋ 이름 추가</button></div></div>`;
  /** 항목의 혈연 칸 (인물 폼) */
  HT.kinFieldHTML = () => `<div class="field field-wide kin-field" data-kin-field>${kinSecHTML('parent', [])}${kinSecHTML('spouse', [])}</div>`;
  /** 이름 줄들 → 파일과 같은 꼴의 목록 (host = 줄들을 담은 상자 · where = 문제 글 앞말) */
  const readNameRows = (host, problems, where = '') => {
    const raw = [];
    [...(host ? host.children : [])]
      .filter(r => r.classList.contains('name-row'))
      .forEach((row, i) => {
        const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const s = xRowEdge(row, 'start');
        const e = xRowEdge(row, 'end');
        if (!g('x-text') && !g('x-lang') && !g('x-kind') && !s && !e && !g('x-note')) return; // 빈 줄
        const tag = `${where}이름 ${i + 1}번째 줄`;
        if (!g('x-text')) return problems.push(`${tag}: 글이 없습니다.`);
        if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) return problems.push(`${tag}: 쓴 기간이 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
        if (known(s) && known(e) && HT.endBound(e.t, e.at) < s.t) return problems.push(`${tag}: 그친 때가 쓰기 시작한 때보다 앞섭니다.`);
        const o = { text: g('x-text') };
        if (g('x-lang')) o.lang = g('x-lang');
        if (g('x-kind')) o.kind = g('x-kind');
        putEdge(o, 'start', s);
        putEdge(o, 'end', e);
        if (g('x-note')) o.note = g('x-note');
        raw.push(o);
      });
    return HT.readNames(raw);
  };
  HT.readNameRows = readNameRows; // 메이커 바탕 자료 창(가문 · 성씨 · 지명 줄의 이름 상자)도 같은 읽기로
  HT.namesRowsHTML = namesRowsHTML;
  /** 부모 · 배우자 줄들 → 파일과 같은 꼴의 목록 (type = 'parent' | 'spouse') */
  const readKinRows = (host, problems, where, type) => {
    const raw = [];
    [...(host ? host.children : [])]
      .filter(r => r.classList.contains(`${type}-row`))
      .forEach((row, i) => {
        const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const whoEl = row.querySelector('.x-who');
        const text = whoEl ? whoEl.value.trim() : '';
        const tag = `${where}${type === 'parent' ? '부모' : '배우자'} ${i + 1}번째 줄`;
        const o = {};
        if (type === 'parent') {
          if (!text && !g('x-as') && !g('x-gen') && !g('x-note') && (g('x-cert') || 'accepted') === 'accepted') return; // 빈 줄
          if (g('x-as')) o.as = g('x-as');
          if (g('x-gen')) {
            const n = Number(g('x-gen'));
            if (!Number.isFinite(n) || n < 1) return problems.push(`${tag}: 몇 대손은 1 이상의 수로 적습니다.`);
            if ((HT.parentRole(o.as) || o.as) !== 'ancestor') return problems.push(`${tag}: 몇 대손은 관계가 후손일 때만 적습니다.`);
            o.gen = n;
          }
          if (g('x-cert') && g('x-cert') !== 'accepted') o.certainty = g('x-cert');
        } else {
          const s = xRowEdge(row, 'start');
          const e = xRowEdge(row, 'end');
          if (!text && !s && !e && !g('x-note')) return; // 빈 줄
          if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) return problems.push(`${tag}: 혼인 기간이 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
          if (known(s) && known(e) && HT.endBound(e.t, e.at) < s.t) return problems.push(`${tag}: 끝이 시작보다 앞섭니다.`);
          putEdge(o, 'start', s);
          putEdge(o, 'end', e);
        }
        if (g('x-note')) o.note = g('x-note');
        if (!text) return problems.push(`${tag}: 사람이 없습니다 — 모르면 미상이라고 적습니다.`);
        if (HT.isUnknownWho(text)) o.whoUnknown = true;
        else {
          const r = readRefInput(whoEl);
          if (!r) return problems.push(`${tag}: 사람을 읽을 수 없습니다 — 인물 id · 이름이나 나라:지도자@시작 해로 적습니다.`);
          o.who = r;
        }
        raw.push(o);
      });
    return type === 'parent' ? HT.readParents(raw) : HT.readSpouses(raw);
  };
  /** 항목의 이름 목록 칸 채우기 · 읽기 (시대 · 왕조 · 인물 · 사건) — 칸이 없는 폼이면 읽은 값 undefined(원래 값을 건드리지 않음) */
  const ownNames = form => form.querySelector('[data-names-field] > [data-names-rows]');
  HT.fillNamesField = (form, x) => {
    const host = ownNames(form);
    if (!host) return;
    host.innerHTML = namesRowsHTML(x && x.names);
    const box = host.closest('details[data-adv]');
    if (box && box.classList.contains('names-adv')) box.open = false; // 文 단추로 여는 명칭 목록: 이름이 있어도 닫혀 시작(단추의 표기 수 딱지 — 결정 D2-6 A)
    else if (box && x && Array.isArray(x.names) && x.names.length) box.open = true;
    HT.syncNamesBtn(form);
  };
  HT.readNamesField = (form, problems) => {
    const host = ownNames(form);
    if (!host) return undefined;
    const list = readNameRows(host, problems);
    return list.length ? list : undefined;
  };
  /** 인물의 부모 · 배우자 칸 채우기 · 읽기 */
  const ownKin = (form, type) => form.querySelector(`[data-kin-field] [data-kin-rows="${type}"]`);
  HT.fillKinField = (form, x) => {
    for (const type of ['parent', 'spouse']) {
      const host = ownKin(form, type);
      if (host) host.innerHTML = ((x && x[type === 'parent' ? 'parents' : 'spouses']) || []).map(q => (type === 'parent' ? HT.parentRowHTML(q) : HT.spouseRowHTML(q))).join('');
    }
    const box = form.querySelector('details[data-adv="kin"]');
    if (box && x && ((x.parents || []).length || (x.spouses || []).length)) box.open = true;
  };
  HT.readKinField = (form, problems) => {
    const out = {};
    for (const [type, key] of [['parent', 'parents'], ['spouse', 'spouses']]) {
      const host = ownKin(form, type);
      if (!host) continue;
      const list = readKinRows(host, problems, '', type);
      out[key] = list.length ? list : undefined;
    }
    return out;
  };

  /** 칸 줄 끝의 [사람] · [이름] 단추 글 — 적힌 것의 수 ("사람" · "사람 3" · "이름 2") */
  const cxCount = (kind, c) => {
    if (!c) return 0;
    const n = (Array.isArray(c.names) ? c.names.length : 0) + (kind === 'eras' ? 0 : c.person ? 1 : 0);
    return kind === 'leaders' ? n + (c.accession ? 1 : 0) + (c.parents || []).length + (c.spouses || []).length : n;
  };
  const cxWord = kind => (kind === 'eras' ? '이름' : '사람');
  HT.cxBtnHTML = (kind, c) => {
    const n = cxCount(kind, c);
    const tip = kind === 'eras' ? '이 연호의 이름(원어 등) — 누르면 줄 아래에 펼쳐집니다' : kind === 'cabinets' ? '이 내각을 이끈 사람 · 이름(원어 등) — 누르면 줄 아래에 펼쳐집니다' : '이 지도자의 사람(인물 잇기) · 자리 이음 · 부모 · 배우자 · 이름(원어 등) — 누르면 줄 아래에 펼쳐집니다';
    return `<button type="button" class="btn btn-sm calt-btn cx-btn${n ? ' has-cx' : ''}" data-cx-toggle aria-expanded="false" title="${tip}">${cxWord(kind)}${n ? ` ${n}` : ''}</button>`;
  };
  /** 칸 줄의 사람 상자 (처음엔 접힘 — [사람] · [이름] 단추로 펼침) */
  HT.cxBoxHTML = (kind, c = {}) => {
    const a = c.accession || {};
    const word = (unk, v, name) => (unk ? '미상' : v ? name(v) : '');
    const person =
      kind === 'eras'
        ? ''
        : `<div class="calt-sec"><span class="calt-cap">사람 <small>${kind === 'cabinets' ? '이 내각을 이끈 사람 — 인물 id · 이름' : '인물 id · 이름 — 같은 사람이 다른 나라도 다스렸거나 다시 올랐으면 그 칸들에 같은 값을 적습니다(다른 칸이면 나라:지도자@시작 해)'}</small></span>
          <div class="calt-grid">${refInputHTML('x-person', c.person, '사람', '인물 id · 이름, 또는 나라:지도자@시작 해 — 비우면 이 칸 자체가 한 사람(같은 이름의 인물이 있으면 저절로 이어짐 · 이름을 모르면 비워 둠)', 'mkPersonList')}${kind === 'leaders' || kind === 'cabinets' ? '<button type="button" class="btn btn-sm" data-person-new title="이 칸의 이름으로 사람을 바로 만들어 잇습니다(트랙은 이 객체의 트랙 · 활동 기간은 이 칸의 기간)">＋ 사람</button>' : ''}</div></div>`;
    const acc =
      kind !== 'leaders'
        ? ''
        : `<div class="calt-sec"><span class="calt-cap">자리 이음 <small>앞 지도자와의 관계 · 오른 방식 — 모르면 미상, 비우면 적지 않은 것 · 앞 지도자를 비우면 바로 앞 칸</small></span>
          <div class="calt-grid">
            <label class="alt-f kin-as"><span class="alt-lab">관계</span><input class="x-kin" list="mkKinList" title="앞 지도자와의 관계 — 아들 · 동생 · 조카 · 사위 · 양자 · 방계 · 무관 …, 또는 자유 글 · 모르면 미상" value="${val(word(a.kinUnknown, a.kin, HT.kinName))}"></label>
            <label class="alt-f kin-as"><span class="alt-lab">방식</span><input class="x-how" list="mkHowList" title="오른 방식 — 세습 · 선양 · 찬탈 · 추대 · 선출 · 정복 · 복위 · 섭정 뒤 오름 …, 또는 자유 글 · 모르면 미상" value="${val(word(a.howUnknown, a.how, HT.accessionHowName))}"></label>
            ${refInputHTML('x-from', a.fromUnknown ? '미상' : a.from, '앞 지도자', '비우면 바로 앞 칸 — 다른 사람이면 인물 id · 이름 · 나라:지도자@시작 해 · 모르면 미상')}
            <label class="alt-f nm-note"><span class="alt-lab">메모</span><input class="x-acc-note" value="${val(a.note)}"></label>
          </div></div>${kinSecHTML('parent', c.parents)}${kinSecHTML('spouse', c.spouses)}`;
    return `<div class="cell-xbox" data-cx="${kind}" hidden>${person}${acc}<div class="calt-sec names-box"><span class="calt-cap">이름(원어 등) <small>${NAMES_HINT}</small></span>
        <div class="alt-rows" data-names-rows>${namesRowsHTML(c.names)}</div>
        <div class="toolbar"><button type="button" class="btn btn-sm" data-name-add>＋ 이름 추가</button></div></div></div>`;
  };
  const cxBoxOf = row => Array.from((row && row.children) || []).find(el => el.classList && el.classList.contains('cell-xbox')) || null;
  const cxBtnOf = row => (row && row.querySelector ? row.querySelector(':scope > .row-end > [data-cx-toggle]') : null);
  /** 칸 줄의 사람 상자 → 파일과 같은 꼴 { person?, accession?, parents?, spouses?, names? } (적은 것만). 상자가 없는 줄은 {} */
  HT.readCellX = (row, problems, where) => {
    const box = cxBoxOf(row);
    if (!box) return {};
    const kind = box.dataset.cx;
    const out = {};
    const g = cls => ((box.querySelector(`.${cls}`) || {}).value ?? '').trim();
    if (kind !== 'eras') {
      const el = box.querySelector('.x-person');
      if (el && el.value.trim() && !HT.isUnknownWho(el.value)) { // "미상"은 비운 것과 같음 — 이 칸 자체가 한 사람 (이름 모를 사람끼리 한 사람으로 묶이지 않게)
        const r = readRefInput(el);
        if (r) out.person = r;
        else problems.push(`${where}: 사람을 읽을 수 없습니다 — 인물 id · 이름이나 나라:지도자@시작 해로 적습니다.`);
      }
    }
    if (kind === 'leaders') {
      const raw = {};
      if (g('x-kin')) raw.kin = g('x-kin');
      if (g('x-how')) raw.how = g('x-how');
      const fromEl = box.querySelector('.x-from');
      if (fromEl && fromEl.value.trim()) {
        if (HT.isUnknownWho(fromEl.value)) raw.fromUnknown = true;
        else {
          const r = readRefInput(fromEl);
          if (r) raw.from = r;
          else problems.push(`${where}: 앞 지도자를 읽을 수 없습니다 — 인물 id · 이름이나 나라:지도자@시작 해로 적습니다.`);
        }
      }
      if (g('x-acc-note')) raw.note = g('x-acc-note');
      const acc = HT.readAccession(Object.keys(raw).length ? raw : null);
      if (acc) out.accession = acc;
      const ps = readKinRows(box.querySelector('[data-kin-rows="parent"]'), problems, `${where} `, 'parent');
      if (ps.length) out.parents = ps;
      const sp = readKinRows(box.querySelector('[data-kin-rows="spouse"]'), problems, `${where} `, 'spouse');
      if (sp.length) out.spouses = sp;
    }
    const names = readNameRows(box.querySelector(':scope > .names-box > [data-names-rows]'), problems, `${where} `);
    if (names.length) out.names = names;
    return out;
  };
  /** 칸 줄의 [사람] · [이름] 단추 글을 상자의 지금 값에 맞춥니다 */
  HT.syncCellX = row => {
    const btn = cxBtnOf(row);
    const box = cxBoxOf(row);
    if (!btn || !box) return;
    const kind = box.dataset.cx;
    const n = cxCount(kind, HT.readCellX(row, [], ''));
    btn.textContent = `${cxWord(kind)}${n ? ` ${n}` : ''}`;
    btn.classList.toggle('has-cx', n > 0);
  };
  /* 줄 추가 · 삭제 · 상자 펼치기는 문서 전체에서 한 번만 연결합니다 (편집 창 폼 · 메이커 바탕 자료 창의 이름 줄 — 칸의 이설 상자와 같은 방식) */
  if (typeof document !== 'undefined' && !HT._lineageRowsBound) {
    HT._lineageRowsBound = true;
    document.addEventListener('click', ev => {
      const b = ev.target && ev.target.closest && ev.target.closest('[data-cx-toggle],[data-name-add],[data-name-del],[data-kin-add],[data-kin-del],[data-names-toggle]');
      if (!b) return;
      ev.preventDefault();
      if ('cxToggle' in b.dataset) {
        const row = b.closest('.cell-row');
        return HT.toggleCellBox(cxBoxOf(row), b);
      }
      if ('namesToggle' in b.dataset) {
        /* 文 단추: 이름 칸 바로 아래의 명칭 목록을 펼치고 접음 (자리를 미는 것은 폼 칸 하나라 움직임 없이 — 접는 구역(details)과 같게) */
        const scope = b.closest('form') || document;
        const box = scope.querySelector('details.names-adv[data-adv="names"]');
        if (box) box.open = !box.open;
        return HT.syncNamesBtn(scope);
      }
      let host = null;
      if ('nameAdd' in b.dataset) {
        host = b.closest('.names-box').querySelector('[data-names-rows]');
        host.insertAdjacentHTML('beforeend', HT.nameRowHTML());
        host.lastElementChild.querySelector('.x-text').focus();
      } else if ('kinAdd' in b.dataset) {
        const type = b.dataset.kinAdd;
        host = b.closest('[data-kin-sec]').querySelector('[data-kin-rows]');
        host.insertAdjacentHTML('beforeend', type === 'parent' ? HT.parentRowHTML() : HT.spouseRowHTML());
        host.lastElementChild.querySelector('.x-who').focus();
      } else {
        host = b.closest('.alt-rows');
        b.closest('.alt-row').remove();
      }
      const row = host && host.closest('.cell-row');
      if (row) HT.syncCellX(row);
      const target = (host && host.closest('form')) || host;
      if (target) target.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const onEdit = ev => {
      const box = ev.target && ev.target.closest && ev.target.closest('.cell-xbox');
      if (box) HT.syncCellX(box.parentElement);
      const nf = ev.target && ev.target.closest && ev.target.closest('form');
      if (nf && nf.querySelector('[data-names-toggle]')) HT.syncNamesBtn(nf); // 文 단추의 표기 수 딱지
      if (ev.target && ev.target.classList && ev.target.classList.contains('x-lang')) {
        const t = ev.target.closest('.name-row') && ev.target.closest('.name-row').querySelector('.x-text');
        if (t) t.lang = ev.target.value.trim(); // 글 칸의 글꼴 · 방향이 그 언어를 따르게
      }
    };
    document.addEventListener('input', onEdit);
    document.addEventListener('change', onEdit);
    /* 명칭 목록이 코드로 열리고 닫혀도(편집 창을 다시 채울 때 펼쳐 두던 구역을 되살림 등) 文 단추가 따라오게 — toggle은 거품이 없어 잡는 단계에서 */
    document.addEventListener(
      'toggle',
      ev => {
        const d = ev.target;
        if (d && d.classList && d.classList.contains('names-adv')) HT.syncNamesBtn(d.closest('form') || document);
      },
      true
    );
  }

  /** 한 줄 글("이름 시작~끝 메모")에 쓸 날짜 조각 — 빈칸 없이 (음력:1418-08-10 · -44-03-15 · 1592-05-23T14:30) */
  const dateToken = (x, key) => {
    const at = HT.atOf(x, key);
    if (at) return HT.cal.compact(at);
    const v = x[key];
    return v == null ? '' : Number.isInteger(v) ? String(v) : HT.cal.compact(HT.dateInputValue(x, key));
  };
  HT.cellsToText = list =>
    (list || [])
      .map(c => {
        const plain = !c.startUnknown && !c.endUnknown && !HT.atOf(c, 'start') && !HT.atOf(c, 'end') && Number.isInteger(c.start) && (c.end == null || Number.isInteger(c.end));
        const sep = plain ? '-' : '~';
        const tok = key => (c[`${key}Unknown`] ? '미정' : dateToken(c, key)); // 칸의 미정 (배치용 연도는 한 줄 글에 담지 않음)
        return `${c.name} ${tok('start')}${c.end != null || c.endUnknown ? `${sep}${tok('end')}` : sep}${c.note ? ` ${c.note}` : ''}`;
      })
      .join('\n');
  HT.textToCells = (text, label, problems) => {
    const out = [];
    text.split(/\r?\n/).forEach((line, i) => {
      /* 세기로 적은 연대("3세기 중반")는 낱말 사이의 빈칸을 붙여 한 조각으로("3세기중반" — HT.cal.compact와 같은 꼴 · 묶음 5 · 6번) */
      const s = line.trim().replace(/(\d+)\s*세기\s+(초반|초엽|초|전반|중반|중엽|중|후반|말엽|말)(?=\s*[~-]|\s*$)/g, '$1세기$2');
      if (!s) return;
      /* 새 꼴 "이름 시작~끝 메모"(날짜도) · 옛 꼴 "이름 시작-끝 메모"(연도만, 기원전은 음수).
         메모에 "~"가 들어 있으면("갑오~을미") 새 꼴이 잘못 맞을 수 있으니, 날짜가 실제로 읽히는 꼴을 고릅니다 */
      /* 시작 · 끝 자리에 "미정"도 됩니다 ("이름 미정~끝") */
      const edge = t => (HT.isUnknownText(t) ? { unknown: true, t: null } : HT.readDate(t));
      const tryMatch = m => {
        if (!m) return null;
        const sd = edge(m[2]);
        const ed = m[3] ? edge(m[3]) : null;
        return { m, sd, ed, ok: !!sd && (sd.unknown || !isNaN(sd.t)) && !(known(ed) && isNaN(ed.t)) };
      };
      const cands = [tryMatch(s.match(/^(.+?)\s+(\S+?)\s*~\s*(\S*)(?:\s+(.*))?$/)), tryMatch(s.match(/^(.+?)\s+(-?\d+)\s*-\s*(-?\d+)?(?:\s+(.*))?$/))].filter(Boolean);
      const hit = cands.find(c => c.ok) || cands[0];
      if (!hit) return problems.push(`${label} ${i + 1}번째 줄 "${s}"을(를) 읽을 수 없습니다. "이름 시작~끝" 형식으로 적어 주세요.`);
      const { m, sd, ed } = hit;
      if (!hit.ok) return problems.push(`${label} ${i + 1}번째 줄: 날짜를 읽을 수 없습니다.${(sd && sd.error) || (ed && ed.error) ? ` (${(sd && sd.error) || ed.error})` : ''}`);
      const cell = { name: m[1].trim() };
      putEdge(cell, 'start', sd);
      putEdge(cell, 'end', ed);
      if (known(sd) && known(ed) && cell.end != null && HT.endBound(cell.end, cell.endAt) < cell.start) return problems.push(`${label} ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
      if (m[4]) cell.note = m[4].trim();
      out.push(cell);
    });
    return out;
  };
  /** 폼에 채울 칸 하나: DLC 원본 꼴(짧은 꼴 [이름, 시작, 끝, 메모] · "기원전 57" · 도읍의 한국어 역할)도 폼이 아는 꼴로.
      알아보지 못한 칸도 적힌 만큼은 보여 줘서, 폼을 고칠 때 말없이 지워지지 않게 합니다 */
  HT.formCell = (kind, raw) => {
    if (kind === 'capitals') {
      const n = HT.normalizeCapital(raw);
      if (n) return n;
      const c = Array.isArray(raw) ? { city: raw[0], start: raw[1], end: raw[2], note: raw[3] } : Object.assign({}, raw, { city: raw && (raw.city ?? raw.name), role: raw && HT.capitalRole(raw.role) });
      return c;
    }
    const c = Array.isArray(raw) ? { name: raw[0], start: raw[1], end: raw[2], note: raw[3] } : Object.assign({}, raw);
    for (const k of ['start', 'end']) {
      /* 칸의 미정: "미정" 글 · startUnknown · startHint → 미정 + (있으면) 배치용 연도. 모델이 짐작해 넣은 자리(startAuto)는 버립니다 */
      if (c[`${k}Unknown`] === true || HT.isUnknownText(c[k])) {
        const d = HT.readCellEdge(c, k);
        for (const x of [k, `${k}At`, `${k}Hint`, `${k}Auto`]) delete c[x];
        c[`${k}Unknown`] = true;
        if (d && d.t != null) c[k] = d.t;
        continue;
      }
      if (typeof c[k] !== 'string' || !c[k].trim()) continue;
      const d = HT.readDate(c[k]);
      if (d && isFinite(d.t)) {
        c[k] = d.t;
        if (d.at) c[`${k}At`] = d.at;
      }
    }
    return c;
  };
  HT.fillCellRows = (form, p) => {
    /* 지도자 줄의 표기 낱말(6단계 D3) — 이 항목의 문화권 · 팩의 것. 메이커의 제 항목은 파일 그대로의 값(packId 없음 — uid의 앞)이고, 새 항목은 고치는 DLC의 것 */
    const mk = HT.viewer && HT.viewer.maker && HT.viewer.maker.draft;
    const packId = (p && p.packId) || (p && typeof p.uid === 'string' && p.uid.includes('/') ? p.uid.slice(0, p.uid.indexOf('/')) : '') || (mk ? mk.id : '');
    formWords = p ? HT.leaderWords(Object.assign({}, p, { packId })) : null;
    for (const kind of HT.CELL_KINDS.map(k => k.list)) { // 칸 종류 표의 목록들 — 폼에 그 줄 자리([data-cells])가 없는 종류는 건너뜁니다
      const host = form.querySelector(`[data-cells="${kind}"]`);
      const list = kind === 'leaders' ? p.leaders || p.reigns : p[kind];
      if (host) host.innerHTML = (Array.isArray(list) ? list : []).map(c => HT.cellRowHTML(kind, HT.formCell(kind, c))).join('');
    }
    /* 종교(6단계 D8): 칸 종류 표에는 아직 없어(계획 정한 것 7) 따로 — 파일의 짧은 꼴 · faith 열쇠도 폼의 줄 꼴로 */
    const faithHost = form.querySelector('[data-cells="faiths"]');
    const faithRaw = c => (typeof c === 'string' ? { name: c } : c && typeof c === 'object' && !Array.isArray(c) && c.name == null ? Object.assign({}, c, { name: c.faith }) : c);
    if (faithHost) faithHost.innerHTML = (Array.isArray(p.faiths) ? p.faiths : []).map(c => HT.faithRowHTML(HT.formCell('faiths', faithRaw(c)))).join('');
    const succ = form.querySelector('[data-succ]');
    if (succ) succ.innerHTML = (p.succeeds || []).map(s => HT.succRowHTML(typeof s === 'string' ? { from: s } : s)).join('');
    const parts = form.querySelector('[data-parts]');
    const partOpt = { relation: !!parts && 'relation' in parts.dataset }; // 시대 폼의 소속 줄만 소속 관계 · 놓는 자리를 받습니다 (periodFieldsHTML의 data-relation)
    if (parts) parts.innerHTML = HT.readPartOf(p.partOf, partOpt).map(s => HT.partOfRowHTML(s, partOpt)).join('');
    HT.syncPartRows(form);
  };
  /** 줄 추가·삭제·붙여넣기 버튼 (폼 하나에 한 번만) */
  HT.bindPeriodForm = form => {
    if (form.dataset.cellsBound) return;
    form.dataset.cellsBound = '1';
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-cell-add],[data-cell-del],[data-cell-paste],[data-succ-add],[data-succ-del],[data-part-add],[data-part-del],[data-sp-deg],[data-sp-part],[data-office-add],[data-office-del],[data-office-cell-add],[data-power-add],[data-power-del]');
      if (!b) return;
      e.preventDefault();
      /* 부분 승계의 정도(하나만 눌림) · 이어진 것(켜고 끔) */
      if (b.dataset.spDeg) {
        for (const x of b.parentElement.querySelectorAll('[data-sp-deg]')) x.setAttribute('aria-pressed', String(x === b));
        form.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }
      if (b.dataset.spPart) {
        b.setAttribute('aria-pressed', String(b.getAttribute('aria-pressed') !== 'true'));
        form.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }
      if (b.dataset.cellAdd) {
        const host = form.querySelector(`[data-cells="${b.dataset.cellAdd}"]`);
        host.insertAdjacentHTML('beforeend', HT.cellRowHTML(b.dataset.cellAdd));
        const first = host.lastElementChild.querySelector('input:not(.c-ordinal):not(.c-regnal)');
        if (first) first.focus();
      } else if ('cellDel' in b.dataset) b.closest('.cell-row').remove();
      else if (b.dataset.cellPaste) {
        const kind = b.dataset.cellPaste;
        const ta = form.querySelector(`[data-paste-text="${kind}"]`);
        if (HT.makerPaste && HT.makerPaste.open(form, kind, ta)) return; // 줄 묶음 붙여넣기(메이커 전용 js/maker-paste.js): 표(탭으로 나뉜 열)면 열 맞추기 미리 보기 창이 넣기까지 맡음 — 한 줄 글 꼴은 아래 예전 길 그대로
        const problems = [];
        const raw = kind === 'ranks' ? HT.textToRanks(ta.value, problems) : kind === 'faiths' ? HT.textToFaiths(ta.value, problems) : HT.textToCells(ta.value, (HT.cellKind(kind) || {}).name || '칸', problems); // 지위 · 종교는 시작 · 끝을 비울 수 있음
        // 도읍은 "도시 시작-끝 역할|메모" (예: 강화 1232-1270 임시)
        const cells = kind === 'capitals' ? raw.map(c => Object.assign({ city: c.name, start: c.start, startAt: c.startAt, end: c.end, endAt: c.endAt, startUnknown: c.startUnknown, endUnknown: c.endUnknown }, HT.capitalRole(c.note) ? { role: HT.capitalRole(c.note) } : c.note ? { note: c.note } : {})) : raw;
        if (problems.length) HT.toast(problems[0], 'error');
        form.querySelector(`[data-cells="${kind}"]`).insertAdjacentHTML('beforeend', cells.map(c => HT.cellRowHTML(kind, c)).join(''));
        if (cells.length) {
          ta.value = '';
          HT.toast(`${cells.length}개를 칸으로 옮겼습니다.`, 'ok');
        }
      } else if ('succAdd' in b.dataset) {
        form.querySelector('[data-succ]').insertAdjacentHTML('beforeend', HT.succRowHTML());
        form.querySelector('[data-succ] .succ-row:last-child .s-from').focus();
      } else if ('succDel' in b.dataset) b.closest('.succ-row').remove();
      else if ('partAdd' in b.dataset) {
        const parts = form.querySelector('[data-parts]');
        parts.insertAdjacentHTML('beforeend', HT.partOfRowHTML({}, { relation: 'relation' in parts.dataset })); // 어느 폼의 소속 줄인지는 [data-parts]의 data-relation이 알려 줍니다
        form.querySelector('[data-parts] .part-row:last-child .s-from').focus();
      } else if ('partDel' in b.dataset) b.closest('.part-row').remove();
      else if ('officeAdd' in b.dataset) { // 직위 줄 더 · 실권 (5단계 과제 4)
        form.querySelector('[data-offices]').insertAdjacentHTML('beforeend', HT.officeLineHTML());
        form.querySelector('[data-offices] .office-line:last-child .o-name').focus();
      } else if ('officeDel' in b.dataset) b.closest('.office-line').remove();
      else if ('officeCellAdd' in b.dataset) {
        const host = b.closest('.office-line').querySelector('[data-cells="office"]');
        host.insertAdjacentHTML('beforeend', HT.cellRowHTML('leaders'));
        const first = host.lastElementChild.querySelector('input:not(.c-ordinal):not(.c-regnal)');
        if (first) first.focus();
      } else if ('powerAdd' in b.dataset) {
        form.querySelector('[data-object-power]').insertAdjacentHTML('beforeend', HT.objectPowerRowHTML());
        form.querySelector('[data-object-power] .op-row:last-child .pw-over').focus();
      } else if ('powerDel' in b.dataset) b.closest('.op-row').remove();
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
    form.addEventListener('input', e => { // 직위 줄 더의 빌려 오기 칸: 출처를 적으면 그 줄의 칸 줄을 숨김
      const t = e.target;
      if (t && t.classList && t.classList.contains('o-from')) t.closest('.office-line').classList.toggle('is-borrowed', !!t.value.trim());
    });
    /* 소속 줄: 소속 관계를 고르면 놓는 자리의 기본도 따라갑니다(관계 없음 · 구성국 = 접기, 그 밖 = 제 줄) — 체크를 직접 만진 줄은 그대로 둡니다.
       줄 수 · 기간이 바뀌면 접을 수 없는 줄의 체크를 잠급니다 */
    form.addEventListener('change', e => {
      const t = e.target;
      /* 승계 종류: 부분 승계일 때만 정도 · 이어진 것 단추 */
      if (t && t.classList && t.classList.contains('b-on')) return HT.syncBorrowRows(form); // 빌려 보기 켜고 끔 (5단계 과제 4)
      if (t && t.classList && t.classList.contains('s-type')) {
        const box = t.closest('.succ-row') && t.closest('.succ-row').querySelector('.s-partial');
        if (box) box.hidden = t.value !== 'partial';
        return;
      }
      if (!t || !t.closest || !t.closest('.part-row')) return;
      const nest = t.closest('.part-row').querySelector('.s-nest');
      if (t.classList.contains('s-nest')) t.dataset.touched = '1';
      else if (t.classList.contains('s-rel') && nest && !nest.dataset.touched) nest.checked = HT.nestDefault(t.value);
    });
    form.addEventListener('input', () => HT.syncPartRows(form));
  };

  /* ---------- 공용 폼: 시기 구분(학계) — 체계 묶음(체계 이름 · 메모 + 시기 줄)을 더하고 뺍니다 ---------- */
  /** 시기 한 줄: 이름 · 시작 · 끝 · 메모. 시작 · 끝은 비워도 되고 "미정"이라고 적어도 됩니다 */
  HT.phaseRowHTML = (c = {}) => {
    const side = k => (c[`${k}Unknown`] === true ? '미정' : c[k] == null || c[k] === '' ? '' : HT.dateInputValue(c, k));
    return `<div class="cell-row phase-row"${hintAttrs(c)}>
      <input class="c-name" placeholder="이름" value="${val(c.name)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜 — 비우면 앞 시기의 끝부터(첫 시기는 정권 시작부터) · 모르면 미정" value="${val(side('start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜 — 비우면 다음 시기가 시작할 때까지(마지막 시기는 정권 끝까지) · 모르면 미정" value="${val(side('end'))}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-phase-del aria-label="시기 삭제">✕</button></span>${HT.caltBoxHTML(c)}</div>`;
  };
  /** 체계 묶음 하나: 체계 이름 · 메모 + 시기 줄들 + 여러 줄 붙여넣기 */
  HT.phaseSchemeHTML = (g = {}) => `<div class="phase-scheme">
      <div class="phase-head">
        <input class="ps-name" placeholder="체계 이름" title="구분 체계(출전 · 학설)의 이름 — 체계가 하나뿐이면 비워도 됩니다" value="${val(g.scheme)}">
        <input class="ps-note" placeholder="메모" title="출전 · 학설에 대한 짧은 메모" value="${val(g.note)}">
        <button type="button" class="icon-btn" data-phase-scheme-del aria-label="체계 삭제">✕</button>
      </div>
      <div class="cell-rows" data-phase-rows>${(g.spans || []).map(HT.phaseRowHTML).join('')}</div>
      <div class="toolbar"><button type="button" class="btn btn-sm" data-phase-add>＋ 시기 추가</button></div>
      <details class="cell-paste"><summary>여러 줄 한꺼번에 붙여넣기</summary>
        <textarea class="cells" rows="3" aria-label="한 줄에 시기 하나씩" data-phase-paste-text></textarea>
        <button type="button" class="btn btn-sm" data-phase-paste>줄을 시기로 추가</button>
        <p class="cells-hint">한 줄에 하나씩 "이름 시작~끝 메모". 시작이나 끝은 비워도 됩니다("이름 ~끝" · "이름 시작~") — 비운 시작은 앞 시기의 끝부터, 비운 끝은 다음 시기까지. 모르면 미정.</p></details>
    </div>`;
  /** 폼에 채울 체계 묶음: 원문을 거르지 않고 묶기만 합니다 (읽을 수 없는 날짜도 적힌 그대로 보여 줘서, 폼을 고칠 때 말없이 지워지지 않게) */
  const phaseGroupsForForm = v => {
    const groups = [];
    const groupOf = name => {
      let g = groups.find(x => x.scheme === name && !x.explicit);
      if (!g) groups.push((g = { scheme: name, note: '', spans: [] }));
      return g;
    };
    const raw = c => (Array.isArray(c) ? { name: c[0], start: c[1], end: c[2], note: c[3] } : Object.assign({}, c));
    for (const x of Array.isArray(v) ? v : v && typeof v === 'object' ? [v] : []) {
      if (x && typeof x === 'object' && !Array.isArray(x) && Array.isArray(x.spans)) groups.push({ scheme: x.scheme ?? '', note: x.note ?? '', spans: x.spans.filter(c => c && typeof c === 'object').map(raw), explicit: true });
      else if (x && typeof x === 'object') groupOf(Array.isArray(x) ? '' : String(x.scheme ?? '').trim()).spans.push(raw(x));
    }
    return groups;
  };
  HT.fillPhaseRows = (form, p) => {
    const host = form.querySelector('[data-phases]');
    if (!host) return;
    const groups = phaseGroupsForForm(p.phases);
    host.innerHTML = groups.map(HT.phaseSchemeHTML).join('');
    const box = form.querySelector('details[data-adv="phases"]');
    if (box) box.open = groups.length > 0;
    HT.bindPhaseForm(form);
  };
  /** 한 줄 글 "이름 시작~끝 메모" → 시기 (시작 · 끝은 비워도 되고 "미정"도 됨). 옛 꼴 "이름 시작-끝"(연도만)도 받습니다.
      줄을 첫 "~"에서 둘로 나눠, 왼쪽은 끝에서부터 날짜(또는 미정)로 읽히는 가장 긴 낱말들이 시작이고 나머지가 이름(띄어 쓴 이름도 됨),
      오른쪽은 앞에서부터 날짜로 읽히는 가장 긴 낱말들이 끝이고 나머지가 메모입니다 — 날짜가 없으면 시작 · 끝은 비움("이름 ~끝" · "이름 시작~ 메모") */
  HT.textToPhases = (text, problems, what = '시기') => { // what: 문제 글의 이름표 (지위 붙여넣기도 같은 읽기를 씀 — HT.textToRanks)
    const out = [];
    const isDate = t => {
      if (HT.isUnknownText(t)) return true;
      const d = HT.readDate(t);
      return !!d && !isNaN(d.t);
    };
    const byTilde = s => {
      const at = s.search(/[~～]/);
      if (at < 0) return null;
      const L = s.slice(0, at).trim().split(/\s+/).filter(Boolean);
      const R = s.slice(at + 1).trim().split(/\s+/).filter(Boolean);
      const c = { name: L.join(' '), start: '', end: '', note: R.join(' ') };
      for (let k = 1; k < L.length; k++) { // 이름은 적어도 한 낱말
        if (!isDate(L.slice(k).join(' '))) continue;
        c.name = L.slice(0, k).join(' ');
        c.start = L.slice(k).join(' ');
        break;
      }
      for (let k = R.length; k > 0; k--) {
        if (!isDate(R.slice(0, k).join(' '))) continue;
        c.end = R.slice(0, k).join(' ');
        c.note = R.slice(k).join(' ');
        break;
      }
      return c;
    };
    text.split(/\r?\n/).forEach((line, i) => {
      const s = line.trim();
      if (!s) return;
      let c = byTilde(s);
      /* 옛 꼴: "~"가 없는 줄, 또는 "~"로는 날짜가 하나도 안 읽히고 그 "~"가 옛 꼴의 메모 안에 있는 줄("이름 100-200 갑~을") */
      const old = s.match(/^(.+?)\s+(-?\d+)\s*-\s*(-?\d+)?(?:\s+(.*))?$/);
      if (old && (!c || (!c.start && !c.end && /[~～]/.test(old[4] || '')))) c = { name: old[1].trim(), start: old[2], end: old[3] || '', note: (old[4] || '').trim() };
      if (!c) c = { name: s, start: '', end: '', note: '' };
      if (!c.name) return problems.push(`${what} ${i + 1}번째 줄: 이름이 없습니다.`);
      for (const k of ['start', 'end']) {
        const d = HT.isUnknownText(c[k]) ? null : HT.readDate(c[k]);
        if (d && isNaN(d.t)) return problems.push(`${what} ${i + 1}번째 줄: 날짜를 읽을 수 없습니다.${d.error ? ` (${d.error})` : ''}`);
      }
      out.push(c);
    });
    return out;
  };
  /** 폼의 시기 구분 → 파일과 같은 꼴(HT.readPhases로 정리한 체계 목록). 막을 문제(이름 없음 · 읽을 수 없는 날짜 · 끝이 시작보다 앞섬)만 problems에 */
  HT.readPhaseRows = (form, problems) => {
    const raw = [];
    form.querySelectorAll('[data-phases] .phase-scheme').forEach((box, si) => {
      const scheme = box.querySelector('.ps-name').value.trim();
      const note = box.querySelector('.ps-note').value.trim();
      const where = `시기 구분${scheme ? ` "${scheme}"` : ` ${si + 1}번째 체계`}`;
      const spans = [];
      box.querySelectorAll('.phase-row').forEach((row, i) => {
        const g = cls => row.querySelector(`.${cls}`).value.trim();
        const c = { name: g('c-name'), start: g('c-start'), end: g('c-end'), note: g('c-note') };
        if (!c.name && !c.start && !c.end && !c.note) return;
        for (const k of ['start', 'end']) if (HT.isUnknownText(c[k]) && row.dataset[`${k}Hint`]) c[`${k}Hint`] = row.dataset[`${k}Hint`]; // 미정 칸의 배치용 연도는 줄에 남겨 둔 것을 잇습니다 (칸의 미정과 같게)
        if (!c.name) problems.push(`${where} ${i + 1}번째 줄: 이름이 없습니다.`);
        const d = {};
        for (const k of ['start', 'end']) {
          d[k] = HT.isUnknownText(c[k]) ? null : dateOrNull(c[k]);
          if (d[k] && isNaN(d[k].t)) problems.push(`${where} ${i + 1}번째 줄: ${k === 'start' ? '시작' : '끝'}이 올바르지 않습니다.${d[k].error ? ` (${d[k].error})` : ''}`);
        }
        if (d.start && d.end && !isNaN(d.start.t) && !isNaN(d.end.t) && HT.endBound(d.end.t, d.end.at) < d.start.t) problems.push(`${where} ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
        Object.assign(c, HT.readCellAlts(row, problems, `${where} ${i + 1}번째 줄`, { start: d.start && !isNaN(d.start.t) ? d.start.t : null, end: d.end && !isNaN(d.end.t) ? d.end.t : null, endAt: d.end && d.end.at })); // 확실성 · 연대 폭 · 이설 (줄 안의 상자 — HT.readPhases가 다시 읽음)
        spans.push(c);
      });
      if (spans.length) raw.push({ scheme, note, spans });
      else if (scheme || note) problems.push(`${where}: 시기를 하나 이상 적어 주세요 (체계를 지우려면 ✕).`);
    });
    /* 이름이 같은 체계(둘 다 비운 것도)는 읽을 때 하나로 합쳐져 시기가 한 줄에 섞이고 둘째 메모가 사라지니, 저장을 막고 알립니다 */
    const names = raw.map(g => g.scheme);
    const dup = names.find((n, i) => names.indexOf(n) !== i);
    if (dup != null) problems.push(dup ? `시기 구분: 체계 이름 "${dup}"이(가) 둘 이상입니다 — 체계마다 다른 이름을 적어 주세요.` : '시기 구분: 이름을 비운 체계가 둘 이상입니다 — 체계가 둘 이상이면 체계마다 다른 이름을 적어 주세요.');
    return HT.readPhases(raw).list;
  };
  /** 체계 · 시기 줄 더하기/빼기 · 붙여넣기 단추 (폼 하나에 한 번만) */
  HT.bindPhaseForm = form => {
    if (form.dataset.phasesBound) return;
    form.dataset.phasesBound = '1';
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-phase-scheme-add],[data-phase-scheme-del],[data-phase-add],[data-phase-del],[data-phase-paste]');
      if (!b) return;
      e.preventDefault();
      const box = b.closest('.phase-scheme');
      if ('phaseSchemeAdd' in b.dataset) {
        const host = form.querySelector('[data-phases]');
        host.insertAdjacentHTML('beforeend', HT.phaseSchemeHTML({ spans: [{}] }));
        host.lastElementChild.querySelector(host.children.length > 1 ? '.ps-name' : '.phase-row .c-name').focus();
      } else if ('phaseSchemeDel' in b.dataset) box.remove();
      else if ('phaseAdd' in b.dataset) {
        const rows = box.querySelector('[data-phase-rows]');
        rows.insertAdjacentHTML('beforeend', HT.phaseRowHTML());
        rows.lastElementChild.querySelector('.c-name').focus();
      } else if ('phaseDel' in b.dataset) b.closest('.phase-row').remove();
      else if ('phasePaste' in b.dataset) {
        const ta = box.querySelector('[data-phase-paste-text]');
        const problems = [];
        const list = HT.textToPhases(ta.value, problems);
        if (problems.length) HT.toast(problems[0], 'error');
        box.querySelector('[data-phase-rows]').insertAdjacentHTML('beforeend', list.map(HT.phaseRowHTML).join(''));
        if (list.length) {
          ta.value = '';
          HT.toast(`${list.length}개를 시기로 옮겼습니다.`, 'ok');
        }
      }
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
  };

  /* ---------- 공용 폼: 지위 변천 — 줄(지위 · 시작 · 끝 · 메모)과 여러 줄 붙여넣기 · 지도자 줄의 지위 칸 ---------- */
  /** 지위 이름 자동 완성의 목록: 마지막으로 만든 모델의 지위 사전(켠 DLC들 + 내장) — 모델이 아직 없으면 내장 사전만. 이름 다음에 별칭 */
  HT.rankNameOptions = () => {
    const defs = HT.lastRankDefs || HT.RANKS;
    return [...new Set(defs.flatMap(d => [d.name].concat(d.aliases || [])))].map(n => `<option value="${val(n)}"></option>`).join('');
  };
  /** 지위 변천 한 줄: 지위(자동 완성) · 시작 · 끝 · 메모. 첫 줄의 시작은 비워도 됩니다(정권 시작부터).
      칸의 미정: 미정이면 칸에 "미정"이라고 쓰고 배치용 연도는 줄의 data-start-hint · data-end-hint에 남깁니다(다른 칸 줄과 같게 — 고쳐 저장해도 줄지 않게) */
  HT.rankRowHTML = (c = {}) => `<div class="cell-row is-rank"${hintAttrs(c)}>
      <input class="c-name" list="mkRankList" placeholder="지위" title="지위 이름 — 사전에 없는 이름도 됩니다(서열 없는 지위로)" value="${val(c.name ?? c.rank)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜 — 첫 줄은 비우면 정권 시작부터${UNK_TIP}" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜 — 비우면 다음 지위가 시작할 때까지(마지막 지위는 정권 끝까지)${UNK_TIP}" value="${val(edgeVal(c, 'end'))}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-cell-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}</div>`;
  /** 한 줄 글 "지위 시작~끝 메모" → 지위 줄 (시작 · 끝은 비워도 됨 — 시작을 비울 수 있는 것은 첫 줄뿐) */
  HT.textToRanks = (text, problems) => HT.textToPhases(text, problems, '지위');
  /** 폼의 지위 변천 → 파일과 같은 꼴(HT.readRanks로 정리한 목록). 막을 문제(이름 없음 · 읽을 수 없는 날짜 · 둘째 줄부터 빈 시작 · 끝이 시작보다 앞섬)만 problems에 */
  /* 지위 변천 · 종교 줄 읽기의 몸(6단계 걸음 3에서 나눔 — 글만 다름): kind = 줄 자리(data-cells) · list = 문제 글의 줄 이름 · lack = 이름이 빈 줄의 글 · read = 정리 함수(HT.readRanks · HT.readFaiths) */
  const readSpanRows = (form, problems, kind, list, lack, read) => {
    const raw = [];
    form.querySelectorAll(`[data-cells="${kind}"] .cell-row`).forEach((row, i) => {
      const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
      const c = { name: g('c-name'), start: g('c-start'), end: g('c-end'), note: g('c-note') };
      if (!c.name && !c.start && !c.end && !c.note) return;
      const where = `${list} ${i + 1}번째 줄`;
      if (!c.name) problems.push(`${where}: ${lack}`);
      for (const k of ['start', 'end']) if (HT.isUnknownText(c[k]) && row.dataset[`${k}Hint`]) c[`${k}Hint`] = row.dataset[`${k}Hint`]; // 칸의 미정: 줄에 남겨 둔 배치용 연도를 잇습니다
      const d = {};
      for (const k of ['start', 'end']) {
        d[k] = HT.isUnknownText(c[k]) ? null : dateOrNull(c[k]);
        if (d[k] && isNaN(d[k].t)) problems.push(`${where}: ${k === 'start' ? '시작' : '끝'}이 올바르지 않습니다.${d[k].error ? ` (${d[k].error})` : ''}`);
      }
      if (!d.start && !HT.isUnknownText(c.start) && raw.length) problems.push(`${where}: 시작이 없습니다 (시작을 비울 수 있는 것은 첫 줄뿐 — 정권 시작부터, 모르면 "미정").`);
      if (d.start && d.end && !isNaN(d.start.t) && !isNaN(d.end.t) && HT.endBound(d.end.t, d.end.at) < d.start.t) problems.push(`${where}: 끝이 시작보다 앞섭니다.`);
      Object.assign(c, HT.readCellAlts(row, problems, where, { start: d.start && !isNaN(d.start.t) ? d.start.t : null, end: d.end && !isNaN(d.end.t) ? d.end.t : null, endAt: d.end && d.end.at })); // 확실성 · 연대 폭 · 이설 (줄 안의 상자 — read가 다시 읽음)
      raw.push(c);
    });
    return read(raw).list;
  };
  HT.readRankRows = (form, problems) => readSpanRows(form, problems, 'ranks', '지위 변천', '지위가 없습니다.', HT.readRanks);
  /* ---------- 공용 폼: 종교(faiths — 리메이크 6단계 D8 · 걸음 3) — 지위 변천과 같은 꼴의 줄(종교 · 시작 · 끝 · 메모)과 여러 줄 붙여넣기 ----------
     첫 줄의 시작을 비우면 정권 시작부터, 끝을 비우면 다음 종교까지(마지막은 정권 끝까지) · 모르면 "미정" · 겹치면 검사 창에 경고(정규화 HT.readFaiths) */
  HT.faithRowHTML = (c = {}) => `<div class="cell-row is-faith"${hintAttrs(c)}>
      <input class="c-name" placeholder="종교" title="종교 이름 — 국교 · 지배층의 공식 신앙(같은 종교는 같은 표기로)" value="${val(c.name ?? c.faith)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜 — 첫 줄은 비우면 정권 시작부터${UNK_TIP}" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜 — 비우면 다음 종교가 시작할 때까지(마지막 종교는 정권 끝까지)${UNK_TIP}" value="${val(edgeVal(c, 'end'))}">
      <input class="c-note" placeholder="메모" value="${val(c.note)}">
      <span class="row-end">${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-cell-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}</div>`;
  /** 한 줄 글 "종교 시작~끝 메모" → 종교 줄 (지위 변천과 같은 읽기 — 시작을 비울 수 있는 것은 첫 줄뿐) */
  HT.textToFaiths = (text, problems) => HT.textToPhases(text, problems, '종교');
  /** 폼의 종교 줄 → 파일과 같은 꼴(HT.readFaiths로 정리한 목록). 막을 문제(이름 없음 · 읽을 수 없는 날짜 · 둘째 줄부터 빈 시작 · 끝이 시작보다 앞섬)만 problems에 — 겹침은 검사 창의 경고 */
  HT.readFaithRows = (form, problems) => readSpanRows(form, problems, 'faiths', '종교', '종교가 없습니다.', HT.readFaiths);

  HT.periodFieldsHTML = ({ tracks, polityNames = [], peopleNames = [], dynastyNames = [], houseNames = [], figureNames = [], placeNames = [], figures = [], eventTitles = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b></span>${nameInHTML('<input name="name" maxlength="80">')}</label>
    <datalist id="mkEventList">${[...new Set(eventTitles)].filter(Boolean).map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <details class="field-wide adv names-adv" data-adv="names">
      <summary>이름(원어 등) — 원어 · 로마자 · 옛 이름(국호 변천) · 약칭</summary>
      <div class="adv-body">${HT.namesFieldHTML()}</div>
    </details>
    ${HT.lineageListsHTML({ figureNames, placeNames, figures })}
    <div class="field"><span>시작 연도 <b class="req">*</b> <small>(모르면 "미정"에 체크하고 대략의 연도를)</small></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <label class="field"><span>트랙</span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <label class="field"><span>종류 <small>(형식 4의 객체 종류 — 띠 모양이 달라집니다 · 옛 종속 종류는 섬김 관계로 저장됩니다 · 사람 · 문화는 따로 추가합니다)</small></span><select name="kind">${HT.objectKindOptionsHTML()}</select></label>
    <label class="field"><span>정통성 <small>(대립 · 명목 등은 서고에서 점선 테 · 비우면 정통)</small></span><select name="status"><option value="">정통 (기본)</option>${HT.F4.STATUSES.filter(s => s.id !== 'legit').map(s => `<option value="${s.id}">${val(s.name)}</option>`).join('')}</select></label>
    <label class="field"><span>중요도 <small>(서고 선반에서 추릴 때의 기준 · 비우면 기간 길이로 짐작)</small></span><select name="importance"><option value="">짐작 (기본)</option><option value="3">높음 ★★★</option><option value="2">보통 ★★</option><option value="1">낮음 ★</option><option value="0">없음</option></select></label>
    <div class="field"><span>띠 색 <small>(고르지 않으면 자동)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <label class="field"><span>민족 <small>(같은 민족끼리 한 묶음 · 대명제에 바로 붙여도 됩니다)</small></span><input name="people" maxlength="40" list="mkPeopleList"></label>
    <datalist id="mkPeopleList">${[...new Set(peopleNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkPolityList">${[...new Set(polityNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkDynastyList">${[...new Set(dynastyNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkRankList">${HT.rankNameOptions()}</datalist>
    <label class="field"><span>국성 <small>(나라를 다스린 가문 · 지도자에게 가문을 따로 적지 않으면 이 가문으로 봅니다)</small></span><input name="house" maxlength="60" list="mkHouseList"></label>
    <datalist id="mkHouseList">${[...new Set(houseNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <div class="field field-wide"><span>소속·예속 <small>(연맹의 구성국·종속국·조직체라면 상위 정권. 여러 줄이면 차례로 예속된 것 — 기간을 적으면 그 구간만, 모르면 "미정" · 소속 관계를 고르면 상국 띠에 이 나라의 이름표가 달립니다 — 스스로 다스린 관계는 상국 띠 아래에 매달리고, 상국이 다스린 관계는 상국 띠 안으로 들어갑니다)</small></span>
      <div class="succ-rows" data-parts data-relation></div>
      <button type="button" class="btn btn-sm" data-part-add>＋ 소속 추가</button></div>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <label class="field"><span>꼬리표 <small>(쉼표로 구분 · 승계표 머리의 국가 이름 뒤에 붙습니다)</small></span><input name="tags" maxlength="200"></label>
    <details class="field-wide adv" data-adv="cells">
      <summary>승계 · 지위 · 종교 · 지도자 · 내각 · 연호 · 도읍</summary>
      <div class="adv-body">
        <div class="field field-wide"><span>승계 <small>(이어받은 정권과 직접/간접/부흥 — 승계로 이어진 정권만 연표에서 같은 줄을 씁니다 · 부흥은 멸망한 나라를 되살리려는 세력이 옛 나라를 가리킬 때)</small></span>
          <div class="succ-rows" data-succ></div>
          <button type="button" class="btn btn-sm" data-succ-add>＋ 승계 추가</button></div>
        <div class="field field-wide"><span>지위 변천 <small>(이 정권의 지위가 바뀐 차례 · 첫 줄의 시작을 비우면 정권 시작부터, 끝을 비우면 다음 지위까지, 모르면 "미정" · 지위가 둘 이상이면 띠 안 지도자 칸 위에 지위 단이, 하나뿐이면 책갈피 탭에 작은 딱지가 붙습니다 · 비워 두고 지도자 줄의 지위만 적어도 됩니다)</small></span>
          <div class="cell-rows" data-cells="ranks"></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-cell-add="ranks">＋ 지위 추가</button></div>
          <details class="cell-paste"><summary>여러 줄 한꺼번에 붙여넣기</summary>
            <textarea class="cells" rows="3" aria-label="한 줄에 지위 하나씩" data-paste-text="ranks"></textarea>
            <button type="button" class="btn btn-sm" data-cell-paste="ranks">줄을 지위로 추가</button>
            <p class="cells-hint">한 줄에 하나씩 "지위 시작~끝 메모". 시작이나 끝은 비워도 됩니다("지위 ~끝" · "지위 시작~") — 시작을 비울 수 있는 것은 첫 줄뿐(정권 시작부터), 비운 끝은 다음 지위까지. 모르면 미정("지위 미정~끝").</p></details></div>
        <div class="field field-wide"><span>종교 <small>(국교 · 지배층의 공식 신앙이 바뀐 차례 — 지위 변천과 같은 꼴 · 첫 줄의 시작을 비우면 정권 시작부터, 끝을 비우면 다음 종교까지, 모르면 "미정" · 겹치면 검사 창에 경고)</small></span>
          <div class="cell-rows" data-cells="faiths"></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-cell-add="faiths">＋ 종교 추가</button></div>
          <details class="cell-paste"><summary>여러 줄 한꺼번에 붙여넣기</summary>
            <textarea class="cells" rows="3" aria-label="한 줄에 종교 하나씩" data-paste-text="faiths"></textarea>
            <button type="button" class="btn btn-sm" data-cell-paste="faiths">줄을 종교로 추가</button>
            <p class="cells-hint">한 줄에 하나씩 "종교 시작~끝 메모". 시작이나 끝은 비워도 됩니다 — 시작을 비울 수 있는 것은 첫 줄뿐(정권 시작부터), 비운 끝은 다음 종교까지. 모르면 미정("종교 미정~끝").</p></details></div>
        <div class="field field-wide"><span>지도자 <small>(묘호·시호·이름은 있는 것만 — 문화권 · 팩이 정한 표기 낱말(치세명 · 존호 · 본명 …)로 읽어도 같은 칸 · 대수는 순번 "제n대"로 비우면 앞 지도자에 이어 자동 · 이름 번호는 "헨리 8세"의 8(적은 줄은 대수를 자동으로 매기지 않음) · 기원전은 음수 · 시작·끝을 모르면 "미정")</small></span>
          <div class="cell-rows" data-cells="leaders"></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-cell-add="leaders">＋ 지도자 추가</button></div>
          ${HT.cellPasteHTML('leaders', '세종 1418-1450 제4대&#10;문종 1450-1452')}${HT.borrowRowHTML('leaders')}</div>
        <div class="field field-wide"><span>내각 <small>(내각 이름과 기간)</small></span>
          <div class="cell-rows" data-cells="cabinets"></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-cell-add="cabinets">＋ 내각 추가</button></div>
          ${HT.cellPasteHTML('cabinets', '김홍집 내각 1894-1896')}${HT.borrowRowHTML('cabinets')}</div>
        <div class="field field-wide"><span>직위 줄 더 <small>(지도자 · 내각 밖의 직위 — 줄마다 이름과 칸, 또는 빌려 오기 "객체 id/직위 이름" · 형식 4의 offices · 지금 연표는 두 줄만 그립니다)</small></span>
          <div class="office-lines" data-offices></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-office-add>＋ 직위 줄 추가</button></div></div>
        <div class="field field-wide"><span>실권 <small>(이 객체가 남의 실권을 쥔 기간 — 쥔 쪽에만 적고 상대는 빼앗긴 객체 · 서고는 빼앗긴 쪽 띠 머리에 쥔 쪽 색 밑줄 · 형식 4의 power[].over)</small></span>
          <div class="succ-rows" data-object-power></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-power-add>＋ 실권 추가</button></div></div>
        <div class="field field-wide"><span>연호 <small>(그 나라가 선포한 연호만 · 맨 위 날짜 칸에 놓입니다)</small></span>
          <div class="cell-rows" data-cells="eras"></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-cell-add="eras">＋ 연호 추가</button></div>
          ${HT.cellPasteHTML('eras', '광무 1897-1907&#10;융희 1907-1910')}</div>
        <div class="field field-wide"><span>도읍 <small>(수도 · 역할: 정도·공동 정도·배도·임시·망명 · 끝을 비우면 다음 정도까지, 모르면 "미정" · 같은 도시는 같은 이름으로 — 맨 위 '도읍' 줄과 노선도 카드에 쓰입니다)</small></span>
          <div class="cell-rows" data-cells="capitals"></div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-cell-add="capitals">＋ 도읍 추가</button></div>
          ${HT.cellPasteHTML('capitals', '개경 919-1232&#10;강화 1232-1270 임시&#10;평양 918- 배도')}</div>
      </div>
    </details>
    <details class="field-wide adv" data-adv="northSouth">
      <summary>남북 위치 — 민족 묶음 안의 배열 기준</summary>
      <div class="adv-body"><label class="field"><span>남북 위치 <small>(민족의 배열 기준이 '북 → 남'일 때 그 묶음 안의 위아래 · 클수록 북 · 비우면 첫 정도의 지명 좌표)</small></span><input name="northSouth" type="number" step="any" inputmode="decimal"></label></div>
    </details>
    <details class="field-wide adv" data-adv="phases">
      <summary>시기 구분(학계) — 후대 학계가 이 나라 안을 나눈 시기</summary>
      <div class="adv-body"><div class="field field-wide"><span>구분 체계 <small>(출전 · 학설마다 체계 하나 — 체계마다 시기의 이름도 경계도 달라도 됩니다 · 띠 안 지도자 칸 위에 체계마다 얇은 줄로 · 시작을 비우면 앞 시기의 끝부터, 끝을 비우면 다음 시기까지)</small></span>
        <div class="phase-schemes" data-phases></div>
        <button type="button" class="btn btn-sm" data-phase-scheme-add>＋ 구분 체계 추가</button></div></div>
    </details>
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리거나 실재가 의심될 때 — 실재성 · 확실성 · 시작·끝 연대 폭 · 이설</summary>
      <div class="adv-body">${HT.historicityFieldsHTML()}${HT.uncertaintyFieldsHTML()}</div>
    </details>
    ${HT.wikiFieldHTML()}`;

  /* 객체 폼의 종류 고르기(5단계 과제 3): 형식 4의 종류 열여덟을 갈래(그릇 · 다스림 · 땅 밖 · 무리)로 묶고(값 "type:<id>"), 형식 4가 섬김 관계로 옮긴 옛 종속 종류 열은 그 뒤에(값 = 옛 종류 id).
     옛 종류 가운데 형식 4의 종류와 하나로 맞는 것(연맹 · 군벌 · 망명 정부 · 부흥 세력 · 시대 이름 · 봉국 · 복속 · 군현 · 조직체)은 그 종류로 보입니다 */
  const OBJECT_GROUPS = [['container', '그릇'], ['ruling', '다스림'], ['offland', '땅 밖'], ['folk', '무리']];
  HT.objectKindOptionsHTML = () => {
    const mapped = new Set(HT.POLITY_KINDS.map(k => k.id).filter(id => HT.F4.typeOfKind(id) !== 'state' || id === 'state'));
    const legacy = HT.POLITY_KINDS.filter(k => !mapped.has(k.id));
    const groups = OBJECT_GROUPS.map(([g, name]) => `<optgroup label="${val(name)}">${HT.F4.TYPES.filter(t => t.group === g).map(t => `<option value="type:${t.id}">${val(t.name)}</option>`).join('')}</optgroup>`);
    groups.push(`<optgroup label="옛 종속 종류 — 섬김 관계로 저장">${legacy.map(k => `<option value="${k.id}" title="${val(k.hint)}">${val(k.name)} — ${val(k.hint.split(' — ')[0])}</option>`).join('')}</optgroup>`);
    return groups.join('');
  };
  /** 항목 → 종류 고르기의 값: 적어 둔 객체 종류가 있으면 그것, 옛 종류가 형식 4의 종류와 맞으면 그 종류, 나머지(종속 종류)는 옛 종류 그대로 */
  HT.objectKindValue = p => {
    const own = HT.F4.typeId(p.type);
    if (own && own !== 'person') return `type:${own}`;
    const kind = HT.kindOf(p);
    return HT.F4.typeOfKind(kind) !== 'state' || kind === 'state' ? `type:${HT.F4.typeOfKind(kind)}` : kind;
  };
  /** 종류 고르기의 값 → { kind, type }(국가 · 되살릴 수 있는 종류는 비움) */
  HT.readObjectKind = v => {
    const s = String(v || '');
    if (!s.startsWith('type:')) return { kind: s && s !== 'state' ? s : undefined, type: undefined };
    const type = HT.F4.typeId(s.slice(5)) || 'state';
    const kind = HT.F4.kindOfType(type);
    return { kind: kind === 'state' ? undefined : kind, type: type !== 'state' && HT.F4.typeOfKind(kind) !== type ? type : undefined };
  };
  HT.fillPeriodForm = (form, p, { defaultColor = '#8b8f98' } = {}) => {
    const el = form.elements;
    el.name.value = p.name || '';
    HT.fillRangeFields(form, p);
    if (p.track) el.track.value = p.track;
    el.kind.value = HT.objectKindValue(p);
    if (!el.kind.value) el.kind.value = 'type:state';
    if (el.status) el.status.value = HT.F4.statusId(p.status) || '';
    if (el.importance) el.importance.value = p.importance != null && [0, 1, 2, 3].includes(Number(p.importance)) ? String(Number(p.importance)) : '';
    el.useColor.checked = HT.isColor(p.color);
    HT.setSwatch(form, 'color', HT.isColor(p.color) ? p.color : '');
    el.description.value = p.description || '';
    if (el.tags) el.tags.value = (Array.isArray(p.tags) ? p.tags : []).join(', '); // 꼬리표 (형식 버전 3 — 승계표 머리)
    el.people.value = p.people || '';
    if (el.house) el.house.value = p.house || ''; // 국성 (적은 것만 — 모델이 풀어낸 houseId는 채우지 않음)
    if (el.wiki) {
      el.wiki.value = p.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!p.wiki;
    }
    HT.fillCellRows(form, p);
    HT.fillOfficeExtras(form, p); // 빌려 보기 · 직위 줄 더 · 실권 (5단계 과제 4)
    HT.fillPhaseRows(form, p);
    HT.fillNamesField(form, p); // 이름 목록 (형식 버전 3)
    HT.bindPeriodForm(form);
    HT.bindSwatches(form);
    const cells = form.querySelector('details[data-adv="cells"]');
    if (cells) cells.open = !!((p.leaders || p.reigns || []).length || (p.cabinets || []).length || (p.eras || []).length || (p.capitals || []).length || (p.succeeds || []).length);
    if (cells && ((Array.isArray(p.ranks) && p.ranks.length) || (Array.isArray(p.faiths) && p.faiths.length))) cells.open = true; // 지위 변천 · 종교만 적은 정권도 그 구역을 열어 둠
    if (el.northSouth) {
      el.northSouth.value = typeof p.northSouth === 'number' && Number.isFinite(p.northSouth) ? String(p.northSouth) : ''; // 남북 위치 (형식 버전 3 — 적은 것만 · 모델이 지명 좌표에서 푼 값은 채우지 않음)
      if (el.northSouth.value) el.northSouth.closest('details').open = true;
    }
    HT.fillUncertainty(form, p);
    HT.fillHistoricity(form, p);
  };

  HT.readPeriodForm = form => {
    const el = form.elements;
    const problems = [];
    const range = HT.readRangeFields(form, problems);
    const partOf = HT.readPartOfRows(form, problems);
    const period = {
      name: el.name.value.trim(),
      start: range.start,
      startAt: range.startAt,
      end: range.end,
      endAt: range.endAt,
      ongoing: range.ongoing,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      track: el.track.value,
      kind: HT.readObjectKind(el.kind.value).kind,
      type: HT.readObjectKind(el.kind.value).type,
      status: el.status && el.status.value ? el.status.value : undefined,
      importance: el.importance && el.importance.value !== '' ? Number(el.importance.value) : undefined,
      partOf: partOf.length ? HT.compactPartOf(partOf) : undefined,
      color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
      description: el.description.value.trim(),
      legendary: undefined,
      reigns: undefined,
      leaders: HT.readCellRows(form, 'leaders', '지도자', problems),
      cabinets: HT.readCellRows(form, 'cabinets', '내각', problems),
      leadersFrom: HT.readBorrowRow(form, 'leaders', problems),
      cabinetsFrom: HT.readBorrowRow(form, 'cabinets', problems),
      offices: HT.readOfficeLines(form, problems),
      power: HT.readPowerRows(form, problems),
      people: el.people.value.trim(),
      house: el.house && el.house.value.trim() ? el.house.value.trim() : undefined,
      succeeds: HT.readSuccRows(form),
      eras: HT.readCellRows(form, 'eras', '연호', problems),
      capitals: HT.readCellRows(form, 'capitals', '도읍', problems),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    if (el.tags) {
      const tags = [...new Set(el.tags.value.split(/[,，]/).map(x => x.trim()).filter(Boolean))];
      period.tags = tags.length ? tags : undefined; // 꼬리표 (형식 버전 3 — 비우면 적지 않음)
    }
    Object.assign(period, HT.readUncertainty(form, problems));
    Object.assign(period, HT.readHistoricity(form));
    if (form.querySelector('[data-phases]')) period.phases = HT.readPhaseRows(form, problems); // 시기 구분(학계) — 폼에 그 구역이 있을 때만
    if (form.querySelector('[data-cells="ranks"]')) period.ranks = HT.readCellRows(form, 'ranks', '지위', problems); // 지위 변천 — 폼에 그 줄 자리가 있을 때만
    if (form.querySelector('[data-cells="faiths"]')) period.faiths = HT.readCellRows(form, 'faiths', '종교', problems); // 종교(6단계 D8) — 폼에 그 줄 자리가 있을 때만
    if (form.querySelector('[data-names-field]')) period.names = HT.readNamesField(form, problems); // 이름 목록 (형식 버전 3 — 폼에 그 칸이 있을 때만)
    if (el.northSouth) {
      /* 남북 위치 (형식 버전 3): 비우면 적지 않음(첫 정도의 지명 좌표로) · 수가 아니면 알림 */
      const ns = HT.readNorthSouth(el.northSouth.value);
      period.northSouth = Number.isFinite(ns) ? ns : undefined; // 비운 칸은 undefined — 제 항목에서는 지우고 남의 항목의 패치에서는 null (HT.draft)
      if (ns !== undefined && !Number.isFinite(ns)) problems.push('남북 위치는 수로 적어 주세요 (클수록 북 · 비우면 첫 정도의 지명 좌표).');
      else if (el.northSouth.validity && el.northSouth.validity.badInput) problems.push('남북 위치는 수로 적어 주세요 (클수록 북 · 비우면 첫 정도의 지명 좌표).');
    }
    if (!period.name) problems.push('이름을 입력하세요.');
    if (partOf.some(s => s.polity === period.name)) problems.push('자기 자신을 소속으로 지정할 수 없습니다.');
    return { period, problems };
  };

  /* ---------- 공용 폼: 기관 — 주권 정권 위에 얹힌 외세 기관·특수 구역 ---------- */
  HT.organFieldsHTML = ({ tracks, polityNames = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b></span><input name="name" maxlength="80"></label>
    <div class="field"><span>시작 연도 <b class="req">*</b></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <label class="field"><span>트랙</span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <label class="field"><span>크기 <small>(시대 띠 안에서의 모양)</small></span><select name="scale"><option value="agency">기관 — 시대 띠 안 맨 아래의 기관 칸</option><option value="zone">구역 — 시대 띠 아래로 내려오는 탭</option></select></label>
    <div class="field"><span>띠 색 <small>(외세의 색으로 주면 알아보기 쉽습니다)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <datalist id="mkPolityList">${[...new Set(polityNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <div class="field field-wide"><span>얹히는 정권 <b class="req">*</b> <small>(이 기관이 올라앉은 주권 정권. 여러 줄이면 차례로 — 기간을 적으면 그 구간만)</small></span>
      <div class="succ-rows" data-parts></div>
      <button type="button" class="btn btn-sm" data-part-add>＋ 정권 추가</button></div>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <label class="field field-wide"><span>메모 <small>(짧게 · 마우스를 올리면 보입니다)</small></span><input name="note" maxlength="120"></label>
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리는 경우 — 확실성 · 연대 폭 · 이설</summary>
      <div class="adv-body">${HT.uncertaintyFieldsHTML()}</div>
    </details>
    ${HT.wikiFieldHTML()}`;
  HT.fillOrganForm = (form, g) => {
    const el = form.elements;
    el.name.value = g.name || '';
    HT.fillRangeFields(form, g);
    if (g.track) el.track.value = g.track;
    el.useColor.checked = HT.isColor(g.color);
    HT.setSwatch(form, 'color', HT.isColor(g.color) ? g.color : '');
    el.description.value = g.description || '';
    el.note.value = g.note || '';
    el.scale.value = g.scale === 'zone' || (!g.scale && /조계|조차|租界|租借|거류지|居留地|공사관 ?구역|특구|왜관|倭館/.test(g.name || '')) ? 'zone' : 'agency';
    if (el.wiki) {
      el.wiki.value = g.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!g.wiki;
    }
    const parts = form.querySelector('[data-parts]');
    if (parts) parts.innerHTML = HT.readPartOf(g.host ?? g.partOf).map(HT.partOfRowHTML).join('') || HT.partOfRowHTML();
    HT.bindPeriodForm(form);
    HT.bindSwatches(form);
    HT.fillUncertainty(form, g);
  };
  HT.readOrganForm = form => {
    const el = form.elements;
    const problems = [];
    const range = HT.readRangeFields(form, problems);
    const host = HT.readPartOfRows(form, problems);
    const organ = {
      name: el.name.value.trim(),
      start: range.start,
      startAt: range.startAt,
      end: range.end,
      endAt: range.endAt,
      ongoing: range.ongoing,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      track: el.track.value,
      host: host.length ? HT.compactPartOf(host) : undefined,
      scale: el.scale.value === 'zone' ? 'zone' : undefined,
      color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
      description: el.description.value.trim(),
      note: el.note.value.trim(),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    Object.assign(organ, HT.readUncertainty(form, problems));
    if (!organ.name) problems.push('이름을 입력하세요.');
    if (!host.length) problems.push('얹히는 정권을 적어 주세요. (없으면 시대로 넣는 편이 맞습니다)');
    if (host.some(s => s.polity === organ.name)) problems.push('자기 자신 위에 얹힐 수 없습니다.');
    return { organ, problems };
  };

  /* ---------- 공용 폼: 문화 — 국가 이전의 고고학 문화 ---------- */
  HT.cultureFieldsHTML = ({ tracks, polityNames = [], peopleNames = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b></span><input name="name" maxlength="80"></label>
    <div class="field"><span>시작 연도 <b class="req">*</b> <small>(대략이면 아래 "연대 폭"에)</small></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <label class="field"><span>트랙</span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <div class="field"><span>띠 색 <small>(고르지 않으면 자동)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <datalist id="mkPolityList">${[...new Set(polityNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkPeopleList">${[...new Set(peopleNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <label class="field"><span>승계한 국가 <small>(쉼표로 여럿 · 적으면 그 국가 줄 밑에 바탕 띠로 깔립니다)</small></span><input name="successors" list="mkPolityList"></label>
    <label class="field"><span>민족 <small>(선택)</small></span><input name="people" maxlength="40" list="mkPeopleList"></label>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <details class="field-wide adv" data-adv="dates" open>
      <summary>연대 — 확실성 · 시작·끝 연대 폭 · 이설</summary>
      <div class="adv-body">${HT.uncertaintyFieldsHTML()}</div>
    </details>
    ${HT.wikiFieldHTML()}`;
  HT.fillCultureForm = (form, c) => {
    const el = form.elements;
    el.name.value = c.name || '';
    HT.fillRangeFields(form, c);
    if (c.track) el.track.value = c.track;
    el.useColor.checked = HT.isColor(c.color);
    HT.setSwatch(form, 'color', HT.isColor(c.color) ? c.color : '');
    el.successors.value = (Array.isArray(c.successorNames) ? c.successorNames : Array.isArray(c.successors) ? c.successors.map(s => (typeof s === 'string' ? s : s.to ? s.to.name : '')) : []).filter(Boolean).join(', ');
    el.people.value = c.people || '';
    el.description.value = c.description || '';
    if (el.wiki) {
      el.wiki.value = c.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!c.wiki;
    }
    HT.bindSwatches(form);
    HT.fillUncertainty(form, c);
    const dates = form.querySelector('details[data-adv="dates"]');
    if (dates) dates.open = true;
  };
  HT.readCultureForm = form => {
    const el = form.elements;
    const problems = [];
    const range = HT.readRangeFields(form, problems);
    const successors = el.successors.value.split(/[,，]/).map(s => s.trim()).filter(Boolean);
    const culture = {
      name: el.name.value.trim(),
      start: range.start,
      startAt: range.startAt,
      end: range.end,
      endAt: range.endAt,
      ongoing: range.ongoing,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      track: el.track.value,
      color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
      successors: successors.length ? successors : undefined,
      people: el.people.value.trim() || undefined,
      description: el.description.value.trim(),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    Object.assign(culture, HT.readUncertainty(form, problems));
    if (!culture.name) problems.push('이름을 입력하세요.');
    if (successors.includes(culture.name)) problems.push('자기 자신을 승계국으로 적을 수 없습니다.');
    return { culture, problems };
  };

  /* ---------- 공용 폼: 왕조 — 나라(국체)를 다스린 왕가 ---------- */
  HT.dynastyFieldsHTML = ({ tracks, polityNames = [], dynastyNames = [], houseNames = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b> <small>(나라를 다스린 왕가의 이름)</small></span>${nameInHTML('<input name="name" maxlength="80">')}</label>
    <details class="field-wide adv names-adv" data-adv="names">
      <summary>이름(원어 등) — 원어 · 로마자 · 옛 이름 · 약칭</summary>
      <div class="adv-body">${HT.namesFieldHTML()}</div>
    </details>
    <div class="field"><span>시작 연도 <b class="req">*</b></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <label class="field"><span>트랙 <small>(주로 다스린 나라의 트랙)</small></span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <label class="field"><span>가문 <small>(선택 · 가문 목록의 이름 — 옛 파일의 본가 왕조 이름도 읽습니다. 본가 → 분가는 가문의 본가로 적습니다)</small></span><input name="house" maxlength="60" list="mkHouseList"></label>
    <div class="field"><span>칸 색 <small>(고르지 않으면 자동)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <datalist id="mkPolityList">${[...new Set(polityNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkDynastyList">${[...new Set(dynastyNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkHouseList">${[...new Set(houseNames.concat(dynastyNames))].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <div class="field field-wide"><span>다스린 정권 <b class="req">*</b> <small>(이 왕조가 다스린 나라. 여러 줄이면 함께 · 기간을 적으면 그 구간만 — 비우면 왕조 전체 기간)</small></span>
      <div class="succ-rows" data-parts></div>
      <button type="button" class="btn btn-sm" data-part-add>＋ 정권 추가</button></div>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <label class="field field-wide"><span>메모 <small>(짧게 · 마우스를 올리면 보입니다)</small></span><input name="note" maxlength="120"></label>
    ${HT.lineageListsHTML()}
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리는 경우 — 확실성 · 연대 폭 · 이설</summary>
      <div class="adv-body">${HT.uncertaintyFieldsHTML()}</div>
    </details>
    ${HT.wikiFieldHTML()}`;
  HT.fillDynastyForm = (form, d) => {
    const el = form.elements;
    el.name.value = d.name || '';
    HT.fillRangeFields(form, d);
    if (d.track) el.track.value = d.track;
    el.house.value = d.house || '';
    el.useColor.checked = HT.isColor(d.color);
    HT.setSwatch(form, 'color', HT.isColor(d.color) ? d.color : '');
    el.description.value = d.description || '';
    el.note.value = d.note || '';
    if (el.wiki) {
      el.wiki.value = d.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!d.wiki;
    }
    const parts = form.querySelector('[data-parts]');
    if (parts) parts.innerHTML = HT.readPartOf(d.polities ?? d.partOf).map(HT.partOfRowHTML).join('') || HT.partOfRowHTML();
    HT.fillNamesField(form, d); // 이름 목록 (형식 버전 3)
    HT.bindPeriodForm(form);
    HT.bindSwatches(form);
    HT.fillUncertainty(form, d);
  };
  HT.readDynastyForm = form => {
    const el = form.elements;
    const problems = [];
    const range = HT.readRangeFields(form, problems);
    const ruled = HT.readPartOfRows(form, problems);
    const dynasty = {
      name: el.name.value.trim(),
      start: range.start,
      startAt: range.startAt,
      end: range.end,
      endAt: range.endAt,
      ongoing: range.ongoing,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      track: el.track.value,
      polities: ruled.length ? HT.compactPartOf(ruled) : undefined,
      house: el.house.value.trim() || undefined,
      color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
      description: el.description.value.trim(),
      note: el.note.value.trim(),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    Object.assign(dynasty, HT.readUncertainty(form, problems));
    if (form.querySelector('[data-names-field]')) dynasty.names = HT.readNamesField(form, problems); // 이름 목록 (형식 버전 3)
    if (!dynasty.name) problems.push('이름을 입력하세요.');
    if (!ruled.length) problems.push('다스린 정권을 적어 주세요. (나라와 왕조가 같으면 왕조를 따로 적지 않아도 됩니다)');
    if (ruled.some(s => s.polity === dynasty.name)) problems.push('왕조 이름과 다스린 정권 이름이 같습니다. 나라와 왕조가 같으면 왕조를 따로 적지 않아도 됩니다.');
    return { dynasty, problems };
  };

  /* ---------- 공용 폼: 인물 — 장군 · 재상 · 학자처럼 나라를 섬긴 사람 ----------
     날짜 칸은 넷 다 선택 사항입니다(생몰 · 활동) — 하나 이상이면 되고, 활동 시기를 비우면 섬긴 기간 · 생몰에서 짐작합니다.
     모델이 짐작해 채운 시작(startAuto)은 폼에 적지 않습니다 — 한 번 열어 저장해도 짐작이 자료로 굳지 않게 */
  HT.FIGURE_ROLES = ['장군', '재상', '관료', '학자', '승려', '예술가', '상인', '탐험가', '왕족', '봉기 지도자'];
  /** 섬긴 기록 한 줄: 트랙(비우면 인물의 트랙) · 정권 · 직함 · 기간 · 메모.
      적힌 트랙이 지금 목록에 없으면(꺼 둔 DLC의 트랙 등) 그 값을 담은 선택지를 하나 더 두어 골라 둡니다 — 설명만 고쳐 저장해도 그 줄이 인물의 트랙으로 조용히 바뀌지 않게 */
  HT.serviceRowHTML = (tracks, s = {}) => `<div class="succ-row svc-row"${hintAttrs(s)}>
      <select class="v-track" aria-label="활동한 정권의 트랙" title="활동한 정권이 있는 트랙 — 고르지 않으면 인물의 트랙"><option value="">인물의 트랙</option>${options(tracks || [], s.track)}${s.track && !(tracks || []).some(t => t.id === s.track) ? `<option value="${val(s.track)}" selected>${val(s.track)} (지금 없는 트랙)</option>` : ''}</select>
      <input class="s-from" list="mkPolityList" placeholder="활동한 정권" value="${val(s.polity)}">
      <input class="v-office" placeholder="직함" value="${val(s.office)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="이 정권에서 활동을 시작한 때 — 연도나 날짜 (비우면 활동 시작부터${UNK_TIP})" value="${val(edgeVal(s, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="이 정권에서 활동이 끝난 때 — 연도나 날짜 (비우면 활동 끝까지${UNK_TIP})" value="${val(edgeVal(s, 'end'))}">
      <input class="s-note" placeholder="메모" value="${val(s.note)}">
      <span class="row-end">${HT.caltBtnHTML(s)}<button type="button" class="icon-btn" data-svc-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(s)}</div>`;
  HT.figureFieldsHTML = ({ tracks, polityNames = [], houseNames = [], figureNames = [], placeNames = [], figures = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b></span>${nameInHTML('<input name="name" maxlength="80">')}</label>
    <details class="field-wide adv names-adv" data-adv="names">
      <summary>이름(원어 등) — 원어 · 로마자 · 한자음 · 옛 이름</summary>
      <div class="adv-body">${HT.namesFieldHTML('원어 · 로마자 · 한자음 · 옛 이름 · 약칭 — 다른 이름(aka)은 아래 칸 그대로')}</div>
    </details>
    <label class="field"><span>다른 이름 <small>(쉼표로 구분 · 자 · 호 · 시호처럼 달리 불린 이름 — 검색과 문서 링크가 함께 찾습니다)</small></span><input name="aka" maxlength="200"></label>
    <details class="field-wide adv" data-adv="kin">
      <summary>가족 — 부모 · 조상 · 배우자</summary>
      <div class="adv-body">${HT.kinFieldHTML()}</div>
    </details>
    ${HT.lineageListsHTML({ figureNames, placeNames, figures })}
    <label class="field"><span>역할 <small>(자유롭게 적습니다 · 연표의 설명글과 상세에 보입니다)</small></span><input name="role" maxlength="40" list="mkRoleList"></label>
    <datalist id="mkRoleList">${HT.FIGURE_ROLES.map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <label class="field"><span>트랙</span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <div class="field"><span>계보 전용 <small>(왕위에 오르지 않은 대군 · 공주 · 후손처럼 띠에 그리지 않고 승계표 · 세계표에만 두는 사람 — 날짜가 없어도 됩니다)</small></span><label class="check"><input type="checkbox" name="lineageOnly"> 계보 전용</label></div>
    <label class="field"><span>형제 순서 <small>(선택 · 정수 — 작을수록 앞. 생년이 없거나 형제가 여러 DLC에 흩어졌을 때 승계표 · 세계표의 차례)</small></span><input name="order" type="text" inputmode="numeric" autocomplete="off" maxlength="6"></label>
    <label class="field" data-life><span>중요도 <small>(높은 사람부터 인물 단의 윗자리를 차지합니다 · 중요도 필터를 따릅니다)</small></span><select name="importance"><option value="3">높음 ★★★</option><option value="2" selected>보통 ★★</option><option value="1">낮음 ★</option></select></label>
    <div class="field"><span>출생 <small>(선택)</small></span>${HT.yearFieldHTML('birth', '출생 연도')}</div>
    <div class="field"><span>사망 <small>(선택)</small></span>${HT.yearFieldHTML('death', '사망 연도')}</div>
    <button type="button" class="btn btn-sm field-wide" data-life-more style="display:none">더 보기 — 활동 시기 · 활동 기록 · 중요도 (계보 전용 인물은 띠에 그리지 않습니다)</button>
    <div class="field" data-life><span>활동 시작 <small>(비우면 활동 기록의 기간, 그것도 없으면 생몰에서 짐작합니다 · 모르면 "미정"에 체크 — 숫자 칸은 비우거나 대략의 연도를)</small></span>${HT.yearFieldHTML('start', '활동 시작 연도', { unknown: true })}</div>
    <div class="field" data-life><span>활동 끝</span>${HT.yearFieldHTML('end', '활동 끝 연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 지금도 활동 중</label></div>
    <datalist id="mkPolityList">${[...new Set(polityNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkHouseList">${[...new Set(houseNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <div class="field field-wide" data-life><span>활동 기록 <small>(활동한 정권마다 한 줄 — 그 정권의 띠 안, 기간 막대 아래에 활동 막대로 그려집니다 · 다른 트랙의 정권이면 트랙을 고르세요 · 기간을 비우면 활동 시기 전체, 모르면 "미정" · 줄이 없으면 활동 가운데 해의 같은 트랙 정권에 놓입니다)</small></span>
      <div class="succ-rows" data-services></div>
      <button type="button" class="btn btn-sm" data-svc-add>＋ 활동 기록 추가</button></div>
    <label class="field"><span>가문 <small>(선택)</small></span><input name="house" maxlength="60" list="mkHouseList"></label>
    <details class="field-wide adv" data-adv="titles">
      <summary>칭호 묶음 — 이 사람이 앉은 자리(읽기 전용 · 지도자 · 내각 칸에서 모음)</summary>
      <div class="adv-body"><div class="titles-list" data-titles></div></div>
    </details>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <label class="field"><span>태그 <small>(쉼표로 구분)</small></span><input name="tags"></label>
    <label class="field"><span>출처 <small>(선택)</small></span><input name="source"></label>
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리는 경우 — 생몰 · 활동 시기의 이설</summary>
      <div class="adv-body">${HT.altFieldHTML('figure', '출생 · 사망 · 활동 시기를 학설마다 따로 — 적은 칸만 다른 견해이고 비운 칸은 위의 값 그대로 · 날짜 없이 근거만 적으면 상세 창에만')}</div>
    </details>
    ${HT.wikiFieldHTML()}`;
  /** 계보 전용이면 활동 시기 · 활동 기록 · 중요도 줄을 '더 보기'로 접습니다(값은 지우지 않음 — D1 7-2 ①). 생몰은 늘 보입니다(세계표 카드의 곁글) */
  HT.applyFigureLife = form => {
    const lo = !!(form.elements.lineageOnly && form.elements.lineageOnly.checked);
    const open = !lo || form.dataset.lifeOpen === '1';
    form.querySelectorAll('[data-life]').forEach(x => (x.style.display = open ? '' : 'none'));
    const more = form.querySelector('[data-life-more]');
    if (more) more.style.display = open ? 'none' : '';
  };
  /** 섬긴 기록 줄의 추가 · 삭제 (폼 하나에 한 번만) */
  HT.bindFigureForm = form => {
    if (form.dataset.servicesBound) return;
    form.dataset.servicesBound = '1';
    form.addEventListener('change', e => {
      if (e.target && e.target.name === 'lineageOnly') {
        delete form.dataset.lifeOpen;
        HT.applyFigureLife(form);
      }
    });
    form.addEventListener('click', e => {
      if (!e.target.closest('[data-life-more]')) return;
      e.preventDefault();
      form.dataset.lifeOpen = '1';
      HT.applyFigureLife(form);
    });
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-svc-add],[data-svc-del]');
      if (!b) return;
      e.preventDefault();
      const host = form.querySelector('[data-services]');
      if ('svcAdd' in b.dataset && host) {
        host.insertAdjacentHTML('beforeend', HT.serviceRowHTML(JSON.parse(form.dataset.tracks || '[]')));
        host.lastElementChild.querySelector('.s-from').focus();
      } else if ('svcDel' in b.dataset) b.closest('.svc-row').remove();
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
  };
  /** 모델의 사람 자리(personIndex의 사람 노드)에서 칭호 묶음 — [{ polity, office, years, rank? }] 시작 해 차례(5단계 과제 5 · 읽기 전용) */
  HT.personTitles = (model, node) => {
    const cells = ((node && node.cells) || []).filter(q => q && q.p && q.c && (q.kind === 'leader' || q.kind === 'cabinet'));
    const y = v => (Number.isFinite(v) ? HT.formatYear(v) : '');
    return cells
      .map(q => {
        const sp = HT.cellSpan(q.c, q.p, q.ref);
        return { polity: q.p.name || q.p.id || '', office: q.kind === 'leader' ? '지도자' : '내각', years: [y(sp.start), y(sp.end)].filter(Boolean).join('–'), rank: q.c.rank || '', start: Number.isFinite(sp.start) ? sp.start : Infinity };
      })
      .sort((a, b) => a.start - b.start)
      .map(({ start, ...t }) => t);
  };
  HT.fillFigureForm = (form, f, { titles = null } = {}) => {
    const el = form.elements;
    const tbox = form.querySelector('[data-titles]');
    if (tbox) { // 칭호 묶음(읽기 전용) — 메이커가 모델의 사람 자리에서 모아 넘김 · 없으면 안내
      const list = Array.isArray(titles) ? titles : [];
      tbox.innerHTML = list.length
        ? `<ul class="titles">${list.map(t => `<li>${val(t.polity)} · ${val(t.office)}${t.years ? ` · ${val(t.years)}` : ''}${t.rank ? ` · ${val(t.rank)}` : ''}</li>`).join('')}</ul>`
        : '<p class="hint">아직 어느 칸에도 이어지지 않았습니다 — 객체의 지도자 · 내각 칸에서 [사람]에 이 사람의 id나 이름을 적으면 여기에 모입니다.</p>';
      const box = tbox.closest('details');
      if (box) box.open = list.length > 0;
    }
    el.name.value = f.name || '';
    el.aka.value = (Array.isArray(f.aka) ? f.aka : []).join(', ');
    el.role.value = f.role || '';
    if (f.track) el.track.value = f.track;
    el.importance.value = String(f.importance || 2);
    if (el.lineageOnly) el.lineageOnly.checked = f.lineageOnly === true; // 계보 전용 · 형제 순서 (형식 버전 3 — D1)
    if (el.order) el.order.value = Number.isInteger(f.order) ? String(f.order) : '';
    HT.writeDateField(form, 'birth', f.birth ?? null, f.birthAt);
    HT.writeDateField(form, 'death', f.death ?? null, f.deathAt);
    /* 활동 시기의 미정: 체크 + (있으면) 숫자 칸의 배치용 연도. 체크를 먼저 채워야 날짜 칸이 처음부터 미정 모양(점선 · 안내 줄)으로 나옵니다
       (HT.fillRangeFields와 같은 차례 — writeDateField가 그때의 체크로 모양을 정함). 짐작한 자리(startAuto)는 적지 않습니다 */
    if (el.startUnknown) el.startUnknown.checked = !!f.startUnknown;
    if (el.endUnknown) el.endUnknown.checked = !f.ongoing && !!f.endUnknown;
    HT.writeDateField(form, 'start', f.startAuto ? null : f.start ?? null, f.startAuto ? null : f.startAt);
    HT.writeDateField(form, 'end', f.end ?? null, f.endAt);
    el.ongoing.checked = !!f.ongoing;
    HT.lockDateField(form, 'end', !!f.ongoing);
    el.house.value = f.house || '';
    el.description.value = f.description || '';
    el.tags.value = (f.tags || []).join(', ');
    el.source.value = f.source || '';
    if (el.wiki) {
      el.wiki.value = f.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!f.wiki;
    }
    const tracks = [...el.track.options].map(o => ({ id: o.value, name: o.textContent }));
    form.dataset.tracks = JSON.stringify(tracks);
    const host = form.querySelector('[data-services]');
    if (host) host.innerHTML = (Array.isArray(f.service) ? f.service : []).map(s => HT.serviceRowHTML(tracks, s)).join('');
    HT.fillAlternatives(form, f); // 다른 견해 (생몰 · 활동 시기 — 디테일 건의 4)
    const dates = form.querySelector('details[data-adv="dates"]');
    if (dates) dates.open = !!(f.alternatives && f.alternatives.length);
    HT.fillNamesField(form, f); // 이름 목록 · 부모 · 배우자 (형식 버전 3)
    HT.fillKinField(form, f);
    HT.bindFigureForm(form);
    delete form.dataset.lifeOpen;
    HT.applyFigureLife(form);
  };
  HT.readServiceRows = (form, problems) =>
    [...form.querySelectorAll('[data-services] .svc-row')]
      .map((row, i) => {
        const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const o = {};
        if (g('v-track')) o.track = g('v-track');
        o.polity = g('s-from');
        if (g('v-office')) o.office = g('v-office');
        const s = rowEdge(row, 'start'); // 칸의 미정: "미정"이면 줄에 남겨 둔 배치용 연도(data-start-hint)를 잇습니다
        const e = rowEdge(row, 'end');
        if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) problems.push(`활동 기록 ${i + 1}번째 줄: 연도가 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
        putEdge(o, 'start', s);
        putEdge(o, 'end', e);
        if (known(s) && known(e) && o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) problems.push(`활동 기록 ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
        if (g('s-note')) o.note = g('s-note');
        Object.assign(o, HT.readCellAlts(row, problems, `활동 기록 ${i + 1}번째 줄`, o)); // 확실성 · 연대 폭 · 이설 (줄 안의 상자)
        if (!o.polity && (o.office || o.start != null || o.end != null || o.startUnknown || o.endUnknown || o.note)) problems.push(`활동 기록 ${i + 1}번째 줄: 활동한 정권이 없습니다.`);
        return o;
      })
      .filter(s => s.polity);
  HT.readFigureForm = form => {
    const el = form.elements;
    const problems = [];
    const names = v => [...new Set(String(v || '').split(/[,，]/).map(s => s.trim()).filter(Boolean))];
    const lineageOnly = !!(el.lineageOnly && el.lineageOnly.checked); // 계보 전용(형식 버전 3 — D1): 중요도를 쓰지 않고 날짜가 없어도 됨
    const figure = { name: el.name.value.trim(), aka: names(el.aka.value), role: el.role.value.trim(), track: el.track.value, importance: lineageOnly ? undefined : Number(el.importance.value) || 2 };
    figure.lineageOnly = lineageOnly || undefined;
    if (el.order && el.order.value.trim()) {
      const n = Number(el.order.value.trim());
      if (Number.isInteger(n)) figure.order = n;
      else problems.push('형제 순서는 정수로 적습니다.');
    }
    const ongoing = el.ongoing.checked;
    const words = { birth: '출생', death: '사망', start: '활동 시작', end: '활동 끝' };
    /* 활동 시기의 미정: 체크하면 숫자 칸은 배치용 연도(비워도 됨 — 그러면 섬긴 기간 · 생몰에서 짐작), 날짜 글은 두지 않습니다 (시대의 미정과 같게) */
    const unknown = { start: !!(el.startUnknown && el.startUnknown.checked), end: !ongoing && !!(el.endUnknown && el.endUnknown.checked) };
    for (const k of ['birth', 'death', 'start', 'end']) {
      const d = k === 'end' && ongoing ? null : HT.readDateField(form, k);
      if (d && isNaN(d.t)) problems.push(`${words[k]}: ${d.error || '연도가 올바르지 않습니다.'}`);
      figure[k] = d && !isNaN(d.t) ? d.t : undefined;
      figure[`${k}At`] = d && !isNaN(d.t) && d.at && !unknown[k] ? d.at : undefined;
      if (k in unknown) figure[`${k}Unknown`] = unknown[k];
    }
    figure.ongoing = ongoing;
    figure.service = HT.readServiceRows(form, problems);
    figure.alternatives = HT.readAlternativesField(form, problems, figure); // 다른 견해 (적은 쪽만 — 빈 쪽은 통설 값: 생몰 · 활동 시기와 앞뒤가 뒤집히면 문제로)
    figure.house = el.house.value.trim() || undefined;
    figure.description = el.description.value.trim();
    figure.tags = names(el.tags.value);
    figure.source = el.source.value.trim();
    figure.wiki = el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined;
    if (form.querySelector('[data-names-field]')) figure.names = HT.readNamesField(form, problems); // 이름 목록 · 부모 · 배우자 (형식 버전 3 — 폼에 그 칸이 있을 때만)
    if (form.querySelector('[data-kin-field]')) Object.assign(figure, HT.readKinField(form, problems));
    if (!figure.name) problems.push('이름을 입력하세요.');
    if (figure.birth != null && figure.death != null && HT.endBound(figure.death, figure.deathAt) < figure.birth) problems.push('사망이 출생보다 앞섭니다.');
    if (figure.start != null && figure.end != null && HT.endBound(figure.end, figure.endAt) < figure.start) problems.push('활동의 끝이 시작보다 앞섭니다.');
    if (!problems.length && !lineageOnly && !['birth', 'death', 'start', 'end'].some(k => figure[k] != null) && !figure.service.some(s => s.start != null || s.end != null))
      problems.push('날짜를 하나는 적어 주세요 — 출생 · 사망 · 활동 시기 · 활동 기록의 기간 가운데.');
    return { figure, problems };
  };

  /* 새 항목의 기본 기간: 누른 자리 o = { track, start, startAt }에서 from년 ~ to년 떨어진 구간 (0 = 누른 자리 그대로) */
  const freshRange = (o, from, to) => {
    const at = { t: o.start, at: o.startAt || undefined };
    const s = from ? HT.shiftDate(at, from) : at;
    const e = to ? HT.shiftDate(at, to) : at;
    return { track: o.track, start: s.t, startAt: s.at, end: e.t, endAt: e.at };
  };
  /** 항목 종류별 폼 묶음 — 메이커의 편집기(js/viewer.js의 openEditor)가 이 표를 씁니다.
      word 부르는 말 · list DLC의 목록 이름 · nameKey 제목 칸의 이름(폼을 열면 여기에 초점) ·
      fresh(o) 새 항목의 기본값(o = { track, start, startAt } 누른 자리) · filterKeys(x) 저장한 항목이 가려지지 않게 풀 필터 { 칩 묶음: id, importance } (트랙은 늘 풉니다) */
  HT.FORMS = {
    period: { word: '객체', list: 'periods', nameKey: 'name', fresh: o => freshRange(o, 0, 100), filterKeys: x => ({ kinds: x.kind || 'state' }), html: o => HT.periodFieldsHTML(o), fill: (f, x, o) => HT.fillPeriodForm(f, x, o), read: f => { const r = HT.readPeriodForm(f); return { item: r.period, problems: r.problems }; } },
    event: { word: '사건', list: 'events', nameKey: 'title', fresh: o => ({ track: o.track, category: 'politics', importance: 2, start: o.start, startAt: o.startAt || undefined }), filterKeys: x => ({ categories: x.category, importance: x.importance }), html: o => HT.eventFieldsHTML(o), fill: (f, x) => HT.fillEventForm(f, x), read: f => { const r = HT.readEventForm(f); return { item: r.event, problems: r.problems }; } },
    organ: { word: '기관', list: 'organs', nameKey: 'name', fresh: o => freshRange(o, 0, 10), filterKeys: () => ({ kinds: 'overlay' }), html: o => HT.organFieldsHTML(o), fill: (f, x) => HT.fillOrganForm(f, x), read: f => { const r = HT.readOrganForm(f); return { item: r.organ, problems: r.problems }; } },
    culture: { word: '문화', list: 'cultures', nameKey: 'name', fresh: o => freshRange(o, -500, 0), filterKeys: () => ({ kinds: 'culture' }), html: o => HT.cultureFieldsHTML(o), fill: (f, x) => HT.fillCultureForm(f, x), read: f => { const r = HT.readCultureForm(f); return { item: r.culture, problems: r.problems }; } },
    dynasty: { word: '왕조', list: 'dynasties', nameKey: 'name', fresh: o => freshRange(o, 0, 100), filterKeys: () => ({ kinds: 'dynasty' }), html: o => HT.dynastyFieldsHTML(o), fill: (f, x) => HT.fillDynastyForm(f, x), read: f => { const r = HT.readDynastyForm(f); return { item: r.dynasty, problems: r.problems }; } },
  };
  /* 조약(모델의 itemKind 'treaty' = treaty 칸이 있는 사건)은 사건 폼 그대로 — 목록도 사건과 같은 events. 새 조약은 분류 외교 · 조약 규격 구역이 열린 채로 */
  HT.FORMS.treaty = Object.assign({}, HT.FORMS.event, { word: '조약', fresh: o => Object.assign(HT.FORMS.event.fresh(o), { category: 'diplomacy', treaty: {} }) });
  /* 실재성 칩 (8-4 마): 저장한 시대가 꺼 둔 실재성 칩에 가려지지 않게 그 칩도 풉니다 */
  {
    const kindKeys = HT.FORMS.period.filterKeys;
    HT.FORMS.period.filterKeys = x => Object.assign(kindKeys(x), { historicity: HT.historicityOf(x) || 'attested' });
  }

  /* ---------- 공용 폼: 대범위 — 흩어진 정권들을 한 집합으로 (docs/구상-체제-확장.md 7 · 8-4 바) ----------
     시대 구분과 같은 부류라 연표(보기 전용)에서는 고치지 않고 메이커에서만 씁니다 — 그래서 내 데이터 목록(HT.USER_LISTS)에는 없고, 작업본의 항목 목록(아래 DRAFT_ITEMS)에 있습니다.
     메이커에서는 추가 메뉴(독의 ＋ · 오른쪽 클릭 — 단축키 없음) · 바탕 자료의 대범위 칸 · 제 대범위를 누르면 편집 창에 열립니다 (남의 DLC의 대범위는 패치가 닿지 않아 상세만).
     형식에 있는 칸 = 폼에 있는 칸: 이름 · 트랙 · 성격 · 기간 · 상징적 본국 · 구성 정권 줄 · 시대 구분(+ 가져오기) · 색 · 처음부터 켬 · 설명 · 메모 · 문서.
     모델 항목으로 채울 때는 물려받거나 짐작한 칸(nameAuto · startAuto · colorAuto)을 비워 둡니다 — 한 번 열어 저장해도 짐작이 자료로 굳지 않게.
     html(o)의 o.epochs(시대 구분 목록 — 이름 · 기간 · 색)가 있으면 '시대 구분에서 가져오기'가 그 값을 채웁니다.
     o.polities(정권 목록 — { name, track, trackName })가 있으면 구성 정권 · 상징적 본국 칸의 자동 완성이 고른 트랙의 정권 이름을 먼저, 다른 트랙의 정권은 "트랙:이름"으로 내놓습니다
     (트랙을 바꾸면 목록도 그 트랙 기준으로 — 없으면 o.polityNames 그대로) */
  HT.scopeMemberRowHTML = (r = {}) => `<div class="succ-row scope-member-row">
      <input class="s-from" list="mkPolityList" placeholder="정권" value="${val(r.polity)}">
      <input class="s-track" placeholder="트랙" title="다른 트랙의 정권이면 그 트랙 id — 비우면 이 대범위의 트랙 (다른 트랙의 정권은 모이지 않고 상세에만 나옵니다)" value="${val(r.track)}">
      <button type="button" class="icon-btn" data-scope-member-del aria-label="삭제">✕</button></div>`;
  HT.scopeFieldsHTML = ({ tracks, polityNames = [], epochs = [], polities = null }) => `
    <label class="field field-wide"><span>이름 <small>(비우면 시대 구분의 이름)</small></span><input name="name" maxlength="80"></label>
    <label class="field"><span>트랙</span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <label class="field"><span>성격 <small>(자유 글 — 연표의 단추와 이름표에 붙습니다)</small></span><input name="label" maxlength="30"></label>
    <div class="field"><span>시작 연도 <small>(비우면 시대 구분 · 구성 정권의 기간)</small></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <div class="field field-wide"><span>구성 정권 <b class="req">*</b> <small>(켜면 이 정권들이 한 가지로 모입니다 — 같은 트랙의 정권만)</small></span>
      <div class="succ-rows" data-scope-members></div>
      <button type="button" class="btn btn-sm" data-scope-member-add>＋ 정권 추가</button></div>
    <label class="field"><span>상징적 본국 <small>(선택 · 켜면 이 나라 줄 바로 아래에 모이고, 그 띠에 할거기 칠)</small></span><input name="host" maxlength="80" list="mkPolityList"></label>
    <div class="field"><span>시대 구분 <small>(선택 · 같은 뜻의 시대 구분 — 비운 이름 · 기간 · 색을 물려받음)</small></span><span class="color-row"><input name="epoch" maxlength="80" list="mkScopeEpochList"><button type="button" class="btn btn-sm" data-scope-epoch-import title="고른 시대 구분의 이름 · 기간 · 색을 칸에 채웁니다">시대 구분에서 가져오기</button></span></div>
    <div class="field"><span>테두리 색 <small>(고르지 않으면 시대 구분의 색이나 자동)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <div class="field"><span>처음 보일 때</span><label class="check"><input type="checkbox" name="default"> 처음부터 모아 보기</label></div>
    <datalist id="mkPolityList"${polities ? ` data-polities="${val(JSON.stringify(polities.map(p => ({ name: p.name, track: p.track || '', trackName: p.trackName || '' }))))}"` : ''}>${[...new Set(polityNames)].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <datalist id="mkScopeEpochList" data-epochs="${val(JSON.stringify(epochs.map(e => ({ name: e.name, id: e.id, track: e.track || '', start: e.start, startAt: e.startAt || null, end: e.end ?? null, endAt: e.endAt || null, ongoing: !!e.ongoing, color: HT.isColor(e.color) ? e.color : '' }))))}">${[...new Set(epochs.map(e => e.name))].map(n => `<option value="${val(n)}"></option>`).join('')}</datalist>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <label class="field field-wide"><span>메모 <small>(짧게 · 마우스를 올리면 보입니다)</small></span><input name="note" maxlength="120"></label>
    ${HT.wikiFieldHTML()}`;
  /** 구성 정권 · 상징적 본국 칸의 자동 완성을 고른 트랙 기준으로: 그 트랙의 정권은 이름 그대로, 다른 트랙의 정권은 "트랙:이름"(뒤에 · 옆 글은 트랙 이름).
      정권 목록(data-polities)이 없으면 html이 넣은 이름 목록 그대로 둡니다 */
  HT.scopePolityOptions = form => {
    const box = form.querySelector('#mkPolityList');
    if (!box || !box.dataset.polities) return;
    let list = [];
    try {
      list = JSON.parse(box.dataset.polities);
    } catch (err) {
      return;
    }
    const track = form.elements.track ? form.elements.track.value : '';
    const seen = new Set();
    const opts = [];
    const put = (v, label) => {
      if (!v || seen.has(v)) return;
      seen.add(v);
      opts.push(`<option value="${val(v)}"${label ? ` label="${val(label)}"` : ''}></option>`);
    };
    for (const p of list) if (p.track === track) put(p.name, '');
    for (const p of list) if (p.track !== track && p.track) put(`${p.track}:${p.name}`, p.trackName || p.track);
    box.innerHTML = opts.join('');
  };
  /** 줄 추가 · 삭제와 '시대 구분에서 가져오기' · 트랙을 바꾸면 정권 자동 완성도 그 트랙 기준으로 (폼 하나에 한 번만) */
  HT.bindScopeForm = form => {
    if (form.dataset.scopeBound) return;
    form.dataset.scopeBound = '1';
    form.addEventListener('change', e => {
      if (e.target === form.elements.track && form.querySelector('[data-scope-members]')) HT.scopePolityOptions(form);
    });
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-scope-member-add],[data-scope-member-del],[data-scope-epoch-import]');
      if (!b) return;
      e.preventDefault();
      if ('scopeMemberAdd' in b.dataset) {
        const host = form.querySelector('[data-scope-members]');
        host.insertAdjacentHTML('beforeend', HT.scopeMemberRowHTML());
        host.lastElementChild.querySelector('.s-from').focus();
      } else if ('scopeMemberDel' in b.dataset) b.closest('.scope-member-row').remove();
      else {
        const ref = form.elements.epoch.value.trim();
        const box = form.querySelector('#mkScopeEpochList');
        let list = [];
        try {
          list = JSON.parse((box && box.dataset.epochs) || '[]');
        } catch (err) {
          list = [];
        }
        const track = form.elements.track.value;
        const ep = list.find(x => (x.name === ref || x.id === ref) && x.track === track) || list.find(x => x.name === ref || x.id === ref);
        if (!ep) return HT.toast(ref ? `시대 구분 "${ref}"을(를) 찾지 못했습니다.` : '시대 구분 칸에 이름을 먼저 적어 주세요.', 'error');
        if (!form.elements.name.value.trim()) form.elements.name.value = ep.name;
        HT.fillRangeFields(form, ep);
        if (ep.color) {
          form.elements.useColor.checked = true;
          HT.setSwatch(form, 'color', ep.color);
        }
      }
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
  };
  HT.fillScopeForm = (form, x) => {
    const el = form.elements;
    el.name.value = x.nameAuto ? '' : x.name || '';
    HT.fillRangeFields(form, x.startAuto ? {} : x);
    if (x.track) el.track.value = x.track;
    el.label.value = x.label || '';
    el.host.value = HT.scopeRefText(HT.readScopeRef(x.hostRef !== undefined ? x.hostRef : x.host));
    el.epoch.value = String((x.epochRef !== undefined ? x.epochRef : typeof x.epoch === 'string' ? x.epoch : '') || '');
    el.useColor.checked = !x.colorAuto && HT.isColor(x.color);
    HT.setSwatch(form, 'color', el.useColor.checked ? x.color : '');
    el.default.checked = !!x.default;
    el.description.value = x.description || '';
    el.note.value = x.note || '';
    if (el.wiki) {
      el.wiki.value = x.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!x.wiki;
    }
    const rows = form.querySelector('[data-scope-members]');
    if (rows) rows.innerHTML = HT.readScopeRefs(x.memberRefs !== undefined ? x.memberRefs : x.members).map(HT.scopeMemberRowHTML).join('') || HT.scopeMemberRowHTML();
    HT.scopePolityOptions(form);
    HT.bindScopeForm(form);
    HT.bindSwatches(form);
  };
  HT.readScopeForm = form => {
    const el = form.elements;
    const problems = [];
    const blank = !['start', 'end'].some(k => el[k] && el[k].value.trim()) && !el.ongoing.checked;
    const range = blank ? {} : HT.readRangeFields(form, problems);
    const refs = [];
    for (const row of form.querySelectorAll('[data-scope-members] .scope-member-row')) {
      const from = row.querySelector('.s-from').value;
      const tr = row.querySelector('.s-track').value.trim();
      const r = HT.readScopeRef(tr ? { polity: from, track: tr } : from); // 트랙 칸을 비운 채 "트랙:이름"을 적었으면(자동 완성) 둘로 나눔 — 파일을 읽을 때와 같은 규칙
      if (r && !refs.some(q => q.polity === r.polity && (q.track || '') === (r.track || ''))) refs.push(r);
    }
    const host = HT.readScopeRef(el.host.value);
    const scope = {
      name: el.name.value.trim() || undefined,
      track: el.track.value,
      label: el.label.value.trim() || undefined,
      start: range.start ?? undefined,
      startAt: range.startAt || undefined,
      end: range.end ?? undefined,
      endAt: range.endAt || undefined,
      ongoing: range.ongoing || undefined,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      members: refs.map(HT.compactScopeRef),
      host: host ? HT.compactScopeRef(host) : undefined,
      epoch: el.epoch.value.trim() || undefined,
      color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
      default: el.default.checked || undefined,
      description: el.description.value.trim(),
      note: el.note.value.trim(),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    if (!scope.name && !scope.epoch) problems.push('이름을 입력하세요. (시대 구분을 적으면 그 이름을 물려받습니다)');
    if (!refs.length) problems.push('구성 정권을 한 줄 이상 적어 주세요.');
    if (host && refs.some(q => q.polity === host.polity && (q.track || scope.track) === (host.track || scope.track))) problems.push('상징적 본국은 구성 정권에 넣지 않습니다. (본국은 제 줄에 그대로 있고, 구성 정권이 그 아래에 모입니다)');
    return { scope, problems };
  };
  HT.FORMS.scope = { word: '대범위', list: 'scopes', nameKey: 'name', fresh: o => ({ track: o.track, members: [] }), filterKeys: () => ({}), html: o => HT.scopeFieldsHTML(o), fill: (f, x) => HT.fillScopeForm(f, x), read: f => { const r = HT.readScopeForm(f); return { item: r.scope, problems: r.problems }; } };
  /* 메이커의 추가 메뉴(폼 표를 돌며 만듦 — 독의 ＋ · 오른쪽 클릭)에 "＋ 대범위 추가"로 나옵니다. 단축키는 두지 않습니다(key 없음).
     새 대범위는 작업본의 scopes 목록에 들어갑니다 (아래 DRAFT_ITEMS — 자동 id의 씨앗은 HT.normalizePack의 대범위 읽기와 같게) */

  /* 연표에서 추가 · 수정하는 항목의 목록 — 목록 이름 ↔ HT.FORMS의 종류. DLC 통계 · 옛 "내 수정"(아래 blankUser)의 기본 꼴과 이사 ·
     모델의 내 항목 넣기가 모두 이 표를 돕니다 (한 곳이라도 빠지면 옛 내 수정을 DLC로 옮길 때 그 목록이 사라지므로). 차례는 모델에 들어가는 차례이기도 합니다 */
  HT.USER_LISTS = [
    { list: 'periods', kind: 'period' },
    { list: 'events', kind: 'event' },
    { list: 'organs', kind: 'organ' },
    { list: 'cultures', kind: 'culture' },
    { list: 'dynasties', kind: 'dynasty' },
  ];
  /* 인물: 새 인물은 누른 자리에서 20년의 활동 시기로 시작합니다. 중요도 필터를 따르므로 저장 뒤 가려지지 않게 중요도를 풉니다 */
  HT.FORMS.figure = { word: '사람', list: 'figures', nameKey: 'name', fresh: o => Object.assign(freshRange(o, 0, 20), { importance: 2 }), filterKeys: x => (x.lineageOnly ? {} : { importance: x.importance }), html: o => HT.figureFieldsHTML(o), fill: (f, x, o) => HT.fillFigureForm(f, x, o), read: f => { const r = HT.readFigureForm(f); return { item: r.figure, problems: r.problems }; } };
  HT.USER_LISTS.push({ list: 'figures', kind: 'figure' });
  HT.FORMS.figure.key = 'Shift+F'; // 메이커의 추가 단축키 (메뉴 · 독의 ＋ 추가 줄은 폼 표를 돌며 저절로)
  /** 비어 있는 옛 "내 수정"(덧씌움: 추가한 항목 목록 + 고침 · 숨김 · 문서) — 지금은 이사(HT.draft.migrateUser)와 검사에만 씁니다 */
  HT.blankUser = () => Object.assign(Object.fromEntries(HT.USER_LISTS.map(l => [l.list, []])), { overrides: {}, hidden: {}, wiki: {} });

  /* ---------- 공용 폼: 단체 · 제도 칸 · 사건의 주제 · 법 · 선거 (형식 버전 3 — docs/구상-연표-확장-10건.md 3-7 · 3-8) ----------
     대범위 폼(HT.FORMS.scope)과 같은 길: 연표(보기 전용)에서는 고치지 않고 메이커의 편집 창에서만 — 내 데이터 목록(HT.USER_LISTS)에는 없고 작업본의 항목 목록(DRAFT_ITEMS)에 있습니다.
     메이커의 추가 메뉴(폼 표를 돌며 만듦)에 '＋ 단체 추가' · '＋ 제도 추가'. 형식에 있는 칸 = 폼에 있는 칸 — 줄 입력은 기존 줄처럼 짧은 칸 이름만(예시 글 없음).
     남의 단체 · 제도는 패치로 고칩니다(인물과 같게). 모델 항목으로 채울 때 모델이 짐작한 값(단체의 짐작 색 colorAuto)은 비워 둡니다 */
  Object.assign(HT.ITEM_WORDS, { group: '단체', institution: '제도' }); // 모델의 itemKind 'group' · 'institution'
  /** 주제 이름 자동 완성의 목록: 마지막으로 만든 모델의 주제 사전(내장 + 켠 DLC들) — 모델이 아직 없으면 내장 뼈대만 */
  HT.themeNameOptions = () => [...new Set((HT.lastThemes || HT.THEMES).filter(t => !t.auto).map(t => t.name))].map(n => `<option value="${val(n)}"></option>`).join('');
  const rowsAsObjects = v => (Array.isArray(v) ? v : []).map(c => (Array.isArray(c) ? { name: c[0], start: c[1], end: c[2], note: c[3] } : c && typeof c === 'object' ? c : { name: String(c ?? '') }));
  /** 있던 나라 · 구성 나라 한 줄: 트랙(비우면 이 단체의 트랙) · 나라 · (구성 나라면 자리) · 시작 · 끝 · 메모 */
  HT.polityRowHTML = (tracks, r = {}, { role = false } = {}) => `<div class="succ-row gp-polity-row"${hintAttrs(r)}>
      <select class="v-track" aria-label="나라의 트랙" title="그 나라가 있는 트랙 — 고르지 않으면 이 단체의 트랙(거기 없으면 모든 트랙에서 이름으로 찾음)"><option value="">이 단체의 트랙</option>${options(tracks || [], r.track)}${r.track && !(tracks || []).some(t => t.id === r.track) ? `<option value="${val(r.track)}" selected>${val(r.track)} (지금 없는 트랙)</option>` : ''}</select>
      <input class="s-from" list="mkPolityList" placeholder="나라" aria-label="나라" value="${val(r.polity)}">
      ${role ? `<input class="g-role" placeholder="자리" aria-label="연합 안에서의 자리" title="연합 안에서의 자리 (선택)" value="${val(r.role)}">` : ''}
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="${role ? '연합에 든 때' : '그 나라에 있던 때'} — 비우면 단체의 시작부터${UNK_TIP}" value="${val(edgeVal(r, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="비우면 단체의 끝까지${UNK_TIP}" value="${val(edgeVal(r, 'end'))}">
      <input class="s-note" placeholder="메모" aria-label="메모" value="${val(r.note)}">
      <button type="button" class="icon-btn" data-gp-row-del aria-label="삭제">✕</button></div>`;
  /** 앞선 단체 한 줄: 단체 · 이어진 방식(갈라짐 · 합쳐짐 · 이름 바꿈) · 메모 */
  HT.groupFromRowHTML = (f = {}) => `<div class="succ-row gp-from-row">
      <input class="s-from" list="mkGroupList" placeholder="단체" aria-label="앞선 단체" title="앞선 단체의 이름이나 id" value="${val(f.group)}">
      <select class="g-how" aria-label="이어진 방식" title="갈라짐 · 합쳐짐 · 이름 바꿈 — 고르지 않아도 됩니다"><option value="">—</option>${options(HT.GROUP_HOWS, HT.groupHow(f.how))}</select>
      <input class="s-note" placeholder="메모" aria-label="메모" value="${val(f.note)}">
      <button type="button" class="icon-btn" data-gp-row-del aria-label="삭제">✕</button></div>`;
  /** 집권 기간 한 줄: 이름(집권 · 실권 · 연정) · 시작 · 끝 · 메모 + [이설] — 연호와 같은 칸 */
  HT.powerRowHTML = (c = {}) => `<div class="cell-row gp-power-row"${hintAttrs(c)}>
      <input class="c-name" list="mkPowerList" placeholder="이름" aria-label="기간의 이름" title="집권 · 실권 · 연정처럼 그 기간의 이름" value="${val(c.name)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜${UNK_TIP}" value="${val(edgeVal(c, 'start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="비우면 다음 칸이 시작할 때까지(마지막 칸은 단체의 끝까지)${UNK_TIP}" value="${val(edgeVal(c, 'end'))}">
      <input class="c-note" placeholder="메모" aria-label="메모" value="${val(c.note)}">
      <span class="row-end">${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-gp-row-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}</div>`;
  /** 제도 칸 한 줄: 이름 · 시작 · 끝 · 메모 · 온 곳(다른 나라 — "트랙:이름"도) · 온 칸 + [이설]. 시작 · 끝은 비워도 되고 "미정"도 됩니다(시기 구분과 같은 규칙) */
  HT.instSpanRowHTML = (c = {}) => {
    const side = k => (c[`${k}Unknown`] === true ? '미정' : c[k] == null || c[k] === '' ? '' : HT.dateInputValue(c, k));
    const from = c.from && typeof c.from === 'object' ? HT.scopeRefText({ track: c.from.track, polity: c.from.polity }) : c.from ? String(c.from) : '';
    return `<div class="cell-row inst-span-row"${hintAttrs(c)}>
      <input class="c-name" placeholder="이름" aria-label="칸 이름" value="${val(c.name)}">
      <input class="c-start" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="시작" title="연도나 날짜 — 비우면 앞 칸의 끝부터(첫 칸은 나라 시작부터) · 모르면 미정" value="${val(side('start'))}">
      <input class="c-end" type="text" inputmode="numeric" autocomplete="off" spellcheck="false" placeholder="끝" title="연도나 날짜 — 비우면 다음 칸이 시작할 때까지(마지막 칸은 나라 끝까지) · 모르면 미정" value="${val(side('end'))}">
      <input class="c-note" placeholder="메모" aria-label="메모" value="${val(c.note)}">
      <input class="i-from" list="mkPolityList" placeholder="온 곳" aria-label="온 곳" title="다른 나라의 제도에서 왔으면 그 나라 — 이름 · id, 다른 트랙이면 트랙:이름 (선택)" value="${val(from)}">
      <input class="i-from-name" placeholder="온 칸" aria-label="온 칸" title="온 곳의 칸 이름 (선택)" value="${val(c.from && typeof c.from === 'object' ? c.from.name : '')}">
      <span class="row-end">${HT.caltBtnHTML(c)}<button type="button" class="icon-btn" data-gp-row-del aria-label="삭제">✕</button></span>${HT.caltBoxHTML(c)}</div>`;
  };
  const listOptions = names => [...new Set(names)].filter(Boolean).map(n => `<option value="${val(n)}"></option>`).join('');
  HT.groupFieldsHTML = ({ tracks, polityNames = [], eventTitles = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b></span>${nameInHTML('<input name="name" maxlength="80">')}</label>
    <details class="field-wide adv names-adv" data-adv="names">
      <summary>이름(원어 등) — 원어 · 로마자 · 옛 이름 · 약칭</summary>
      <div class="adv-body">${HT.namesFieldHTML()}</div>
    </details>
    <label class="field"><span>종류 <small>(붕당·파벌 · 정당 · 정권·실권 집단 · 세력 · 연합·동맹 — 표에 없는 말은 적은 그대로 남습니다)</small></span><input name="type" maxlength="30" list="mkGroupTypeList"></label>
    <datalist id="mkGroupTypeList">${listOptions(HT.GROUP_TYPES.map(t => t.name))}</datalist>
    <label class="field"><span>트랙</span><select name="track">${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <div class="field"><span>시작 연도 <b class="req">*</b> <small>(모르면 "미정"에 체크하고 대략의 연도를)</small></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <div class="field field-wide"><span>있던 나라 <small>(그 단체가 있던 나라 — 여러 나라에 차례로 있었으면 줄마다 기간을 · 기간을 비우면 단체의 기간 전체)</small></span>
      <div class="succ-rows" data-gp-within></div>
      <button type="button" class="btn btn-sm" data-gp-add="within">＋ 나라 추가</button></div>
    <div class="field field-wide"><span>앞선 단체 <small>(갈라져 나온 단체 · 합쳐진 단체 · 이름을 바꾸기 전의 단체)</small></span>
      <div class="succ-rows" data-gp-from></div>
      <button type="button" class="btn btn-sm" data-gp-add="from">＋ 앞선 단체 추가</button></div>
    <div class="field field-wide"><span>집권 기간 <small>(집권 · 실권 · 연정 — 연호와 같은 칸 · 끝을 비우면 다음 칸이 시작할 때까지, 모르면 "미정". 연표의 띠에서는 이름이 실권 · 섭정 · 수렴청정이거나 종류가 실권 집단이면 실권 단(짙은 칠), 같은 때 함께 집권한 단체가 있으면 연정 칸(두 색 + 색 점)으로 보입니다)</small></span>
      <div class="cell-rows" data-gp-power></div>
      <button type="button" class="btn btn-sm" data-gp-add="power">＋ 기간 추가</button></div>
    <datalist id="mkPowerList">${listOptions(['집권', '실권', '연정', '섭정'])}</datalist>
    <label class="field field-wide"><span>구성원 <small>(쉼표로 구분 · 인물의 이름 · 다른 이름 · id, 또는 지도자 칸 "나라:지도자@시작 해" — 연표에서 찾은 사람은 단체 창에서 그 인물 · 지도자 칸으로 이어집니다)</small></span><input name="people" maxlength="600"></label>
    <div class="field field-wide"><span>구성 나라 <small>(연합 · 동맹이면 함께한 나라마다 한 줄 — 다른 트랙의 나라는 트랙을 고르세요)</small></span>
      <div class="succ-rows" data-gp-members></div>
      <button type="button" class="btn btn-sm" data-gp-add="members">＋ 구성 나라 추가</button></div>
    <label class="field"><span>맺은 사건 <small>(사건의 제목이나 id — 선택)</small></span><input name="event" maxlength="120" list="mkGroupEventList"></label>
    <datalist id="mkGroupEventList">${listOptions(eventTitles)}</datalist>
    <datalist id="mkGroupList">${listOptions(HT.lastGroupNames || [])}</datalist>
    <datalist id="mkPolityList">${listOptions(polityNames)}</datalist>
    <div class="field"><span>색 <small>(고르지 않으면 자동)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    <label class="field field-wide"><span>메모 <small>(짧게 · 마우스를 올리면 보입니다)</small></span><input name="note" maxlength="120"></label>
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리는 경우 — 확실성 · 연대 폭 · 이설</summary>
      <div class="adv-body">${HT.uncertaintyFieldsHTML()}</div>
    </details>
    ${HT.wikiFieldHTML()}`;
  HT.institutionFieldsHTML = ({ tracks, polityNames = [] }) => `
    <label class="field"><span>주제 <b class="req">*</b> <small>(주제 사전의 이름이나 id — 체제 · 붕당 · 법률 · 선거제도 · 이념 · 군사제도 · 조세제도 · 선발제도 · DLC가 더한 주제)</small></span><input name="theme" maxlength="60" list="mkThemeList"></label>
    <datalist id="mkThemeList">${HT.themeNameOptions()}</datalist>
    <label class="field"><span>나라 <b class="req">*</b> <small>(나라 이름이나 id)</small></span><input name="polity" maxlength="80" list="mkPolityList"></label>
    <label class="field"><span>트랙 <small>(나라가 있는 트랙 — 비우면 이 이름의 나라를 모든 트랙에서 찾습니다)</small></span><select name="track"><option value="">—</option>${tracks.map(t => `<option value="${val(t.id)}">${val(t.name || t.id)}</option>`).join('')}</select></label>
    <label class="field"><span>갈래 <small>(같은 갈래의 제도는 나라가 달라도 같은 색 — 선택)</small></span><input name="family" maxlength="60"></label>
    <details class="field-wide adv" data-adv="names">
      <summary>이름(원어 등) — 원어 · 로마자 · 옛 이름 · 약칭</summary>
      <div class="adv-body">${HT.namesFieldHTML()}</div>
    </details>
    <div class="field field-wide"><span>칸 <b class="req">*</b> <small>(이어지는 제도 — 첫 칸의 시작을 비우면 나라 시작부터, 끝을 비우면 다음 칸이 시작할 때까지 · 모르면 "미정" · 다른 나라에서 왔으면 온 곳)</small></span>
      <div class="cell-rows" data-inst-spans></div>
      <button type="button" class="btn btn-sm" data-gp-add="spans">＋ 칸 추가</button></div>
    <datalist id="mkPolityList">${listOptions(polityNames)}</datalist>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="4"></textarea></label>
    ${HT.wikiFieldHTML()}`;
  /** 단체 · 제도 폼의 줄 더하기 · 빼기 (폼 하나에 한 번만) */
  HT.bindGroupForm = form => {
    if (form.dataset.groupBound) return;
    form.dataset.groupBound = '1';
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-gp-add],[data-gp-row-del]');
      if (!b) return;
      e.preventDefault();
      if ('gpRowDel' in b.dataset) b.closest('.succ-row, .cell-row').remove();
      else {
        const tracks = JSON.parse(form.dataset.tracks || '[]');
        const kind = b.dataset.gpAdd;
        const host = form.querySelector(kind === 'spans' ? '[data-inst-spans]' : `[data-gp-${kind}]`);
        if (!host) return;
        host.insertAdjacentHTML('beforeend', kind === 'from' ? HT.groupFromRowHTML() : kind === 'power' ? HT.powerRowHTML() : kind === 'spans' ? HT.instSpanRowHTML() : HT.polityRowHTML(tracks, {}, { role: kind === 'members' }));
        const first = host.lastElementChild.querySelector('.s-from, .c-name');
        if (first) first.focus();
      }
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
  };
  const formTracks = form => {
    const el = form.elements;
    const tracks = [...el.track.options].filter(o => o.value).map(o => ({ id: o.value, name: o.textContent }));
    form.dataset.tracks = JSON.stringify(tracks);
    return tracks;
  };
  HT.fillGroupForm = (form, x) => {
    const el = form.elements;
    el.name.value = x.name || '';
    HT.fillNamesField(form, x); // 이름 목록 (형식 3 — 시대 · 인물 폼과 같은 이름 줄)
    el.type.value = x.type ? HT.groupTypeName(x.type) : '';
    if (x.track) el.track.value = x.track;
    HT.fillRangeFields(form, x);
    const tracks = formTracks(form);
    form.querySelector('[data-gp-within]').innerHTML = HT.readPolityRows(x.within).map(r => HT.polityRowHTML(tracks, r)).join('');
    form.querySelector('[data-gp-from]').innerHTML = HT.readGroupFrom(x.from).map(HT.groupFromRowHTML).join('');
    form.querySelector('[data-gp-power]').innerHTML = rowsAsObjects(x.power).map(HT.powerRowHTML).join('');
    /* 구성원: 사람 참조를 글로(지도자 칸은 "나라:지도자@시작 해") — 객체로 적은 참조는 원래 값을 data-refs에 두어 글을 고치지 않으면 트랙까지 그대로 돌려줌(지도자 칸의 [사람] 칸과 같은 길) */
    const people = HT.readGroupPeople(x.people);
    el.people.value = people.map(HT.personRefText).join(', ');
    el.people.dataset.refs = JSON.stringify(people.filter(r => r && typeof r === 'object'));
    form.querySelector('[data-gp-members]').innerHTML = HT.readPolityRows(x.members, { role: true }).map(r => HT.polityRowHTML(tracks, r, { role: true })).join('');
    el.event.value = x.event || '';
    el.useColor.checked = !x.colorAuto && HT.isColor(x.color);
    HT.setSwatch(form, 'color', el.useColor.checked ? x.color : '');
    el.description.value = x.description || '';
    el.note.value = x.note || '';
    if (el.wiki) {
      el.wiki.value = x.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!x.wiki;
    }
    HT.fillUncertainty(form, x);
    HT.bindGroupForm(form);
    HT.bindSwatches(form);
  };
  /** 있던 나라 · 구성 나라 줄 → 파일의 꼴 (막을 문제만 problems에 — 나라 없는 줄 · 읽을 수 없는 날짜 · 끝이 시작보다 앞섬) */
  const readPolityRowsForm = (host, problems, word, role) =>
    [...(host ? host.querySelectorAll('.gp-polity-row') : [])]
      .map((row, i) => {
        const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const o = {};
        if (g('v-track')) o.track = g('v-track');
        o.polity = g('s-from');
        if (role && g('g-role')) o.role = g('g-role');
        const s = rowEdge(row, 'start');
        const e = rowEdge(row, 'end');
        if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) problems.push(`${word} ${i + 1}번째 줄: 연도가 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
        putEdge(o, 'start', s);
        putEdge(o, 'end', e);
        if (known(s) && known(e) && o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) problems.push(`${word} ${i + 1}번째 줄: 끝이 시작보다 앞섭니다.`);
        if (g('s-note')) o.note = g('s-note');
        if (!o.polity && (o.role || o.start != null || o.end != null || o.startUnknown || o.endUnknown || o.note)) problems.push(`${word} ${i + 1}번째 줄: 나라가 없습니다.`);
        return o;
      })
      .filter(o => o.polity);
  HT.readGroupForm = form => {
    const el = form.elements;
    const problems = [];
    const range = HT.readRangeFields(form, problems);
    const typeText = el.type.value.trim();
    const within = readPolityRowsForm(form.querySelector('[data-gp-within]'), problems, '있던 나라', false);
    const from = [...form.querySelectorAll('[data-gp-from] .gp-from-row')]
      .map(row => ({ group: row.querySelector('.s-from').value.trim(), how: row.querySelector('.g-how').value, note: row.querySelector('.s-note').value.trim() }))
      .filter(f => f.group || f.note)
      .map((f, i) => {
        if (!f.group) problems.push(`앞선 단체 ${i + 1}번째 줄: 단체가 없습니다.`);
        return Object.fromEntries(Object.entries(f).filter(([, v]) => v));
      })
      .filter(f => f.group);
    const power = [];
    form.querySelectorAll('[data-gp-power] .gp-power-row').forEach((row, i) => {
      const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
      const s = rowEdge(row, 'start');
      const e = rowEdge(row, 'end');
      const o = { name: g('c-name') };
      if (!o.name && s == null && e == null && !g('c-note')) return;
      const where = `집권 기간 ${i + 1}번째 줄`;
      if (!o.name) problems.push(`${where}: 이름이 없습니다.`);
      if (!s) problems.push(`${where}: 시작이 없습니다 (모르면 "미정").`);
      if ((known(s) && isNaN(s.t)) || (known(e) && isNaN(e.t))) problems.push(`${where}: 연도가 올바르지 않습니다.${(s && s.error) || (e && e.error) ? ` (${(s && s.error) || e.error})` : ''}`);
      putEdge(o, 'start', s);
      putEdge(o, 'end', e);
      if (known(s) && known(e) && o.start != null && o.end != null && HT.endBound(o.end, o.endAt) < o.start) problems.push(`${where}: 끝이 시작보다 앞섭니다.`);
      if (g('c-note')) o.note = g('c-note');
      Object.assign(o, HT.readCellAlts(row, problems, where, o)); // 확실성 · 연대 폭 · 이설 (줄 안의 상자 — 그 줄의 시작 · 끝과 견줌)
      power.push(o);
    });
    const members = readPolityRowsForm(form.querySelector('[data-gp-members]'), problems, '구성 나라', true);
    const kept = (() => {
      try {
        return JSON.parse(el.people.dataset.refs || '[]');
      } catch (e) {
        return [];
      }
    })();
    const people = HT.readGroupPeople(el.people.value.split(/[,，]/).map(s => kept.find(r => HT.personRefText(r) === s.trim()) || s), m => problems.push(m));
    const group = {
      name: el.name.value.trim(),
      type: typeText ? HT.groupType(typeText) || typeText : undefined,
      track: el.track.value,
      start: range.start,
      startAt: range.startAt,
      end: range.end,
      endAt: range.endAt,
      ongoing: range.ongoing,
      startUnknown: range.startUnknown || undefined,
      endUnknown: range.endUnknown || undefined,
      within: within.length ? HT.compactPolityRows(within) : undefined,
      from: from.length ? from : undefined,
      power: power.length ? power : undefined,
      people: people.length ? people : undefined,
      members: members.length ? members : undefined,
      event: el.event.value.trim() || undefined,
      color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
      description: el.description.value.trim(),
      note: el.note.value.trim(),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
      names: HT.readNamesField(form, problems), // 이름 목록 (형식 3)
    };
    Object.assign(group, HT.readUncertainty(form, problems));
    if (!group.name) problems.push('이름을 입력하세요.');
    if (from.some(f => f.group === group.name)) problems.push('앞선 단체에 자기 자신을 적을 수 없습니다.');
    return { group, problems };
  };
  HT.fillInstitutionForm = (form, x) => {
    const el = form.elements;
    el.theme.value = Array.isArray(x.theme) ? x.theme[0] || '' : x.theme || '';
    const ref = HT.readInstPolity(x.polity, x.track);
    el.polity.value = ref ? ref.polity : '';
    const t = ref && ref.track ? ref.track : '';
    if (t && ![...el.track.options].some(o => o.value === t)) el.track.insertAdjacentHTML('beforeend', `<option value="${val(t)}">${val(t)} (지금 없는 트랙)</option>`);
    el.track.value = t;
    formTracks(form);
    el.family.value = x.family || '';
    HT.fillNamesField(form, x); // 이름 목록 (형식 3 — 시대 · 인물 폼과 같은 이름 줄)
    form.querySelector('[data-inst-spans]').innerHTML = (rowsAsObjects(x.spans).length ? rowsAsObjects(x.spans) : [{}]).map(HT.instSpanRowHTML).join('');
    el.description.value = x.description || '';
    if (el.wiki) {
      el.wiki.value = x.wiki || '';
      const box = form.querySelector('details[data-adv="wiki"]');
      if (box) box.open = !!x.wiki;
    }
    HT.bindGroupForm(form);
  };
  HT.readInstitutionForm = form => {
    const el = form.elements;
    const problems = [];
    const raw = [];
    form.querySelectorAll('[data-inst-spans] .inst-span-row').forEach((row, i) => {
      const g = cls => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
      const c = { name: g('c-name'), start: g('c-start'), end: g('c-end'), note: g('c-note') };
      const fromText = g('i-from');
      if (!c.name && !c.start && !c.end && !c.note && !fromText) return;
      const where = `칸 ${i + 1}번째 줄`;
      for (const k of ['start', 'end']) if (HT.isUnknownText(c[k]) && row.dataset[`${k}Hint`]) c[`${k}Hint`] = row.dataset[`${k}Hint`]; // 미정 칸의 배치용 연도는 줄에 남겨 둔 것을 잇습니다
      if (!c.name) problems.push(`${where}: 이름이 없습니다.`);
      const d = {};
      for (const k of ['start', 'end']) {
        d[k] = HT.isUnknownText(c[k]) ? null : dateOrNull(c[k]);
        if (d[k] && isNaN(d[k].t)) problems.push(`${where}: ${k === 'start' ? '시작' : '끝'}이 올바르지 않습니다.${d[k].error ? ` (${d[k].error})` : ''}`);
      }
      if (d.start && d.end && !isNaN(d.start.t) && !isNaN(d.end.t) && HT.endBound(d.end.t, d.end.at) < d.start.t) problems.push(`${where}: 끝이 시작보다 앞섭니다.`);
      if (fromText) {
        const f = HT.readScopeRef(fromText);
        c.from = Object.assign({}, f, g('i-from-name') ? { name: g('i-from-name') } : {});
      }
      Object.assign(c, HT.readCellAlts(row, problems, where, { start: d.start && !isNaN(d.start.t) ? d.start.t : null, end: d.end && !isNaN(d.end.t) ? d.end.t : null, endAt: d.end && d.end.at }));
      raw.push(c);
    });
    const spans = HT.readInstSpans(raw).list;
    const item = {
      theme: el.theme.value.trim(),
      track: el.track.value || undefined,
      polity: el.polity.value.trim(),
      family: el.family.value.trim() || undefined,
      spans,
      names: HT.readNamesField(form, problems), // 이름 목록 (형식 3)
      description: el.description.value.trim(),
      wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
    };
    if (!item.theme) problems.push('주제를 입력하세요.');
    if (!item.polity) problems.push('나라를 입력하세요.');
    if (!spans.length && !problems.length) problems.push('칸을 한 줄 이상 적어 주세요.');
    return { institution: item, problems };
  };
  HT.FORMS.group = { word: '단체', list: 'groups', nameKey: 'name', fresh: o => freshRange(o, 0, 30), filterKeys: () => ({}), html: o => HT.groupFieldsHTML(o), fill: (f, x) => HT.fillGroupForm(f, x), read: f => { const r = HT.readGroupForm(f); return { item: r.group, problems: r.problems }; } };
  HT.FORMS.institution = { word: '제도', list: 'institutions', nameKey: 'theme', fresh: o => ({ spans: [{ name: '', start: o.start, startAt: o.startAt }] }), filterKeys: () => ({}), html: o => HT.institutionFieldsHTML(o), fill: (f, x) => HT.fillInstitutionForm(f, x), read: f => { const r = HT.readInstitutionForm(f); return { item: r.institution, problems: r.problems }; } };

  /* 사건 폼의 주제 · 법 · 선거 (조약 규격 구역과 같은 접는 구역): 무엇이든 적으면 그 규격이 생기고, 비우면 칸이 사라집니다 (DLC 항목의 수정에서는 null로 원래 규격을 뗌) */
  HT.electionRowHTML = (r = {}) => `<div class="succ-row el-row">
      <input class="e-who" placeholder="누구" aria-label="누구" title="후보 · 모임의 이름" value="${val(r.who)}">
      <input class="e-votes" type="text" inputmode="numeric" placeholder="득표" aria-label="득표" title="득표 수 (선택)" value="${val(r.votes)}">
      <input class="e-seats" type="text" inputmode="numeric" placeholder="의석" aria-label="의석" title="얻은 의석 (선택)" value="${val(r.seats)}">
      <label class="check"><input type="checkbox" class="e-won"${r.won ? ' checked' : ''}> 당선</label>
      <button type="button" class="icon-btn" data-el-del aria-label="결과 줄 삭제">✕</button></div>`;
  HT.lensFieldsHTML = () => `
    <details class="field-wide adv" data-adv="lens">
      <summary>주제 · 법 · 선거 — 렌즈의 재료</summary>
      <div class="adv-body">
        <label class="field field-wide"><span>주제 꼬리표 <small>(쉼표로 구분 · 주제 사전의 이름이나 id — 그 주제로 볼 때 이 사건이 진해집니다)</small></span><input name="themes" maxlength="200" list="mkThemeList"></label>
        <datalist id="mkThemeList">${HT.themeNameOptions()}</datalist>
        <p class="field-wide tr-form-note">법 규격 — 적으면 이 사건이 법의 제정 · 개정 · 폐지가 됩니다(상세에 법 양식).</p>
        <label class="field"><span>법 이름</span><input name="lawName" maxlength="120"></label>
        <label class="field"><span>제정 · 개정 · 폐지</span><select name="lawAct"><option value="">—</option>${options(HT.LAW_ACTS)}</select></label>
        <label class="field field-wide"><span>조항 <small>(한 줄에 한 조항)</small></span><textarea name="lawArticles" rows="3"></textarea></label>
        <label class="field field-wide"><span>법 메모</span><input name="lawNote" maxlength="200"></label>
        <p class="field-wide tr-form-note">선거 규격 — 적으면 이 사건이 선거가 됩니다(상세에 결과 표).</p>
        <label class="field"><span>뽑은 자리</span><input name="elOffice" maxlength="80"></label>
        <div class="field field-wide"><span>결과 <small>누구 · 득표 · 의석 · 당선 (득표 · 의석은 선택)</small></span>
          <div class="succ-rows" data-el-results></div>
          <button type="button" class="btn btn-sm" data-el-add>＋ 결과 줄</button></div>
        <label class="field field-wide"><span>선거 메모</span><input name="elNote" maxlength="200"></label>
      </div>
    </details>`;
  /** 결과 줄 더하기 · 빼기 (폼 하나에 한 번만) */
  HT.bindLensForm = form => {
    if (form.dataset.lensBound) return;
    form.dataset.lensBound = '1';
    form.addEventListener('click', e => {
      const b = e.target.closest('[data-el-add],[data-el-del]');
      if (!b) return;
      e.preventDefault();
      if ('elDel' in b.dataset) b.closest('.el-row').remove();
      else {
        const host = form.querySelector('[data-el-results]');
        host.insertAdjacentHTML('beforeend', HT.electionRowHTML());
        host.lastElementChild.querySelector('.e-who').focus();
      }
      form.dispatchEvent(new Event('input', { bubbles: true }));
    });
  };
  HT.fillLensFields = (form, e) => {
    const el = form.elements;
    if (!el.themes) return;
    el.themes.value = HT.readThemeList(e.theme).join(', ');
    const law = HT.readLaw(e.law) || {};
    el.lawName.value = law.name || '';
    el.lawAct.value = law.act || '';
    el.lawArticles.value = (law.articles || []).join('\n');
    el.lawArticles.dataset.list = JSON.stringify(law.articles || []); // 줄바꿈이 든 조항도 손대지 않으면 원래 목록 그대로 (HT.keepListText)
    el.lawNote.value = law.note || '';
    const ele = HT.readElection(e.election) || {};
    el.elOffice.value = ele.office || '';
    el.elNote.value = ele.note || '';
    form.querySelector('[data-el-results]').innerHTML = (ele.results || []).map(HT.electionRowHTML).join('');
    const box = form.querySelector('details[data-adv="lens"]');
    if (box) box.open = !!(el.themes.value || e.law || e.election);
    HT.bindLensForm(form);
  };
  /** 폼의 주제 · 법 · 선거 → { theme, law, election } (비었으면 undefined — 내 항목에서는 칸이 빠지고 DLC 항목의 수정에서는 원래 값을 지움) */
  HT.readLensFields = (form, problems = []) => {
    const el = form.elements;
    if (!el.themes) return {};
    const themes = HT.readThemeList(el.themes.value);
    const law = HT.readLaw({ name: el.lawName.value, act: el.lawAct.value, articles: HT.keepListText(el.lawArticles.value, el.lawArticles.dataset.list, l => l.join('\n')), note: el.lawNote.value }, m => problems.push(m));
    const g = (row, cls) => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
    const results = [...form.querySelectorAll('[data-el-results] .el-row')]
      .map(row => ({ who: g(row, 'e-who'), votes: g(row, 'e-votes'), seats: g(row, 'e-seats'), won: !!(row.querySelector('.e-won') || {}).checked }))
      .filter(r => r.who || r.votes || r.seats || r.won);
    const election = HT.readElection({ office: el.elOffice.value, results, note: el.elNote.value }, m => problems.push(m));
    return { theme: themes.length ? themes : undefined, law: law || undefined, election: election || undefined };
  };

  /* ---------- 작업본: DLC 메이커가 고치는 DLC (순수 계산 — 화면 없이 scripts/dev-smoke.mjs에서도 돕니다) ----------
   * 작업본(draft)은 DLC 파일과 같은 꼴의 JSON 하나입니다. 메이커(js/maker.js · js/viewer.js의 저장 길)는 덧씌움 없이 이것을 바로 고칩니다:
   *   제 항목(이 DLC의 항목) → 목록에서 바로 고치고 지움 · 남의 항목(다른 DLC · 기본팩) → 원본과 견줘 바뀐 칸만 patches에 · 숨김 → hide 패치 · 문서 → documents.
   * 화면의 모델 = 켜져 있는 다른 팩들 + HT.normalizePack(작업본).pack. 파일 · 설치로 나갈 때는 늘 정규화를 거칩니다 (HT.packToJSON) */
  const DRAFT_LISTS = ['tracks', 'categories', 'peoples', 'epochs', 'periods', 'organs', 'cultures', 'dynasties', 'events', 'patches'];
  DRAFT_LISTS.push('figures', 'houses', 'rankDefs'); // 인물 · 가문 · 지위 사전 (파일 맨 위의 목록 — 반영하지 않은 고침에 잡히고, 빈 작업본에도 자리가 있게)
  /* id 이름공간을 함께 쓰는 항목 목록: [목록, 자동 id의 머리글, 제목 칸] — 차례와 머리글은 HT.normalizePack이 id를 매기는 것과 같게 */
  const DRAFT_ITEMS = [['epochs', 'ep-', 'name'], ['periods', 'p-', 'name'], ['organs', 'g-', 'name'], ['cultures', 'c-', 'name'], ['dynasties', 'y-', 'name'], ['events', 'e-', 'title']];
  DRAFT_ITEMS.push(['figures', 'f-', 'name']); // 인물 — 자동 id의 씨앗은 트랙 + 이름 + 생년 (HT.normalizePack과 같게 — 아래 clean)
  /* 대범위 — HT.normalizePack이 시대 구분 바로 다음에 읽으므로 목록도 그 자리에(겹친 id에 "-2"를 붙이는 차례가 같게). 자동 id의 씨앗은 트랙 + 이름(없으면 시대 구분) + 시작 해 (아래 scopeSeed) */
  DRAFT_LISTS.push('scopes');
  DRAFT_ITEMS.splice(1, 0, ['scopes', 's-', 'name']);
  const LIST_WORDS = { tracks: '트랙', categories: '분류', peoples: '민족', epochs: '시대 구분', periods: '시대', organs: '기관', cultures: '문화', dynasties: '왕조', events: '사건', patches: '패치' };
  Object.assign(LIST_WORDS, { figures: '사람', houses: '가문', rankDefs: '지위' });
  Object.assign(LIST_WORDS, { scopes: '대범위' });
  /* 형식 3의 최상위 목록 — 메이커의 입력 칸은 아직 없어 작업본 목록(DRAFT_LISTS)에는 넣지 않지만(작업본은 모르는 열쇠도 그대로 들고 있음),
     파일로 고친 것이 '반영하지 않은 고침'(HT.draft.changes)에 잡히고 판 기록 요약에 이름이 나오게 */
  const DRAFT_LISTS_V3 = ['views', 'maps', 'fonts'];
  Object.assign(LIST_WORDS, { views: '모아 보기 판', maps: '지도', fonts: '글꼴' });
  DRAFT_LISTS_V3.push('images'); // 문서 그림 사전 (형식 3 — 메이커는 문서 편집기의 '그림' 단추 · 그림 띠로 고침, js/maker-images.js)
  LIST_WORDS.images = '문서 그림';
  /* 형식 버전 3: 주제 사전(파일 맨 위의 사전 — 바탕 자료) · 단체 · 제도 칸(항목 — 편집 창의 폼). HT.normalizePack이 인물 다음에 단체 → 제도 차례로 id를 매기므로
     항목 목록도 그 차례로 뒤에 (자동 id의 씨앗: 단체는 다른 항목과 같은 트랙 + 시작 해 + 이름, 제도는 트랙 | 나라 | 주제 — 아래 clean) */
  DRAFT_LISTS.push('themes', 'groups', 'institutions');
  DRAFT_ITEMS.push(['groups', 'gr-', 'name'], ['institutions', 'in-', 'theme']);
  Object.assign(LIST_WORDS, { themes: '주제', groups: '단체', institutions: '제도' });
  DRAFT_LISTS.push('surnames', 'places'); // 성씨 · 지명 사전 (형식 버전 3 — 파일 맨 위의 사전 목록, 가문 · 지위 사전과 같은 자리)
  Object.assign(LIST_WORDS, { surnames: '성씨', places: '지명' });
  DRAFT_LISTS.push('spheres'); // 문화권 사전 (2026-10-23 — 바탕 자료의 「문화권」 표 · DLC-형식.md 'spheres')
  LIST_WORDS.spheres = '문화권';
  /** 대범위의 자동 id 씨앗 — HT.normalizePack의 대범위 읽기와 같게: 트랙 + (이름 || 시대 구분) + 시작 해(시작을 비웠으면 해 없이).
      시작이 "미정"이면 배치용 해(startHint) → 적은 수 → 끝 해 차례로 (readRange와 같은 규칙). 정규화가 받지 않을 대범위(이름도 시대 구분도 없음 · 읽을 수 없는 시작)면 null */
  const scopeSeed = x => {
    const name = str(x.name) || str(x.epoch);
    if (!name) return null;
    if (x.start == null || x.start === '') return str(x.track) + name;
    const yr = v => {
      const t = v === '' || v == null ? null : HT.parseYear(v);
      return t != null && !isNaN(t) ? t : null;
    };
    let t = null;
    if (x.startUnknown === true || HT.isUnknownText(x.start)) {
      const ongoing = x.ongoing === true || HT.isOngoingText(x.end);
      const endUnknown = !ongoing && (x.endUnknown === true || HT.isUnknownText(x.end));
      const e = ongoing || endUnknown ? null : HT.readDate(x.end, x.endAt);
      t = yr(x.startHint) ?? (HT.isUnknownText(x.start) ? null : yr(x.start)) ?? (e && !isNaN(e.t) ? e.t : null);
    } else {
      const d = HT.readDate(x.start, x.startAt);
      t = d && !isNaN(d.t) ? d.t : null;
    }
    return t == null ? null : str(x.track) + name + Math.floor(t + 1e-9);
  };
  const blankValue = v => v == null || v === '' || v === false || (Array.isArray(v) && !v.length);
  /** 견줄 때의 꼴: 열쇠 차례 · 빈 값 · 모델이 짐작해 붙인 값(…Auto · 풀어 둔 끝 endY · 가문을 이은 houseId/houseName/houseColor)을 지우고, 해 좌표는 백만분의 1로 맞춥니다 (폼을 거쳐 다시 계산되면 끝자리가 달라질 수 있어서) */
  const MODEL_ONLY = /Auto$|^endY(At)?$|^house(Id|Name|Color)$/; // 파일에는 없는 모델 전용 열쇠 — 지도자 · 내각 칸에 모델이 가문을 이어 붙인 것도 (열어서 그대로 저장한 나라에 지도자 패치가 생기지 않게)
  const canonValue = v => {
    if (Array.isArray(v)) return v.map(canonValue);
    if (v && typeof v === 'object') {
      const o = {};
      for (const k of Object.keys(v).sort()) if (!blankValue(v[k]) && !MODEL_ONLY.test(k)) o[k] = canonValue(v[k]);
      return o;
    }
    return typeof v === 'number' ? Math.round(v * 1e6) / 1e6 : v;
  };
  const canonText = v => JSON.stringify(blankValue(v) ? null : canonValue(v));
  const capsOf = list => (Array.isArray(list) ? list.map(c => HT.normalizeCapital(c)).filter(Boolean).sort((a, b) => a.start - b.start || HT.cmp16(a.city, b.city)) : list);
  /* 폼에 칸이 없는 안쪽 열쇠가 있는 목록 — 폼이 아는 열쇠만 견줍니다 (다른 견해의 출처 · 메모처럼 폼을 거치며 떨어지는 값 때문에, 손대지 않은 목록이 바뀐 것으로 보이지 않게) */
  /* 다른 견해는 폼이 출처 · 메모 · 현재까지까지 모두 담으므로(디테일 건의 4 — HT.altRowHTML) 통째로 견줍니다 */
  const FORM_ROW_KEYS = { perspectives: ['track', 'title', 'description'] };
  const sameField = (k, a, b) => {
    if (k === 'capitals') return canonText(capsOf(a)) === canonText(capsOf(b));
    /* 색: 폼의 색 견본은 어떤 색이든 파스텔로 맞춰 담습니다(HT.setSwatch) — 파스텔로 맞춘 값과 같으면 고치지 않은 것 (열어서 저장할 때마다 색이 조금씩 옅어지지 않게) */
    if (k === 'color' && HT.isColor(a) && HT.isColor(b)) return a.toLowerCase() === b.toLowerCase() || HT.pastel(b) === a.toLowerCase() || HT.pastel(a) === b.toLowerCase();
    const keys = FORM_ROW_KEYS[k];
    const pick = list => (keys && Array.isArray(list) ? list.map(r => (r && typeof r === 'object' ? Object.fromEntries(keys.map(n => [n, r[n]])) : r)) : list);
    return canonText(pick(a)) === canonText(pick(b));
  };
  /** 원본 항목(다른 팩들만으로 만든 모델의 항목)의 그 칸 값 — 폼이 내놓는 값과 같은 뜻으로: 종류는 정권 종류(국가는 빈 값) · 날짜 글은 값과 맞을 때만 ·
      짐작으로 배정된 색과 분류 없음("etc")은 빈 값 · 문화의 승계한 국가는 폼에 보이는 이름들(모델은 그 칸을 승계선 목록으로 바꿔 둡니다 — HT.fillCultureForm과 같은 규칙) */
  const baseValue = (base, k) =>
    k === 'kind' ? (base.polityKind === 'state' ? undefined : base.polityKind)
      : (HT.DATE_KEYS.includes(k) || HT.DATE_AT_KEYS.includes(k)) && base[`${k.replace(/At$/, '')}Auto`] ? undefined // 모델이 짐작해 채운 날짜(인물의 활동 시작 — startAuto)는 없는 것으로
      : HT.DATE_AT_KEYS.includes(k) ? HT.atOf(base, k.slice(0, -2))
        : HT.CELL_CHAIN.includes(k) ? HT.cellsFileForm(base[k]) // 칸의 미정: 모델이 짐작해 잡은 자리(startAuto · endAuto가 붙은 start · end)는 없는 것으로
        : k === 'color' && base.colorAuto ? undefined
          : k === 'category' && base.category === 'etc' ? ''
            : k === 'successors' ? (Array.isArray(base.successorNames) ? base.successorNames : arr(base.successors).map(x => (typeof x === 'string' ? x : x && x.to ? x.to.name : '')).filter(Boolean))
              : base[k];
  /** 폼에서 읽은 값(obj — 비운 칸은 undefined나 null)과 원본을 견줘 바뀐 칸만 담은 패치의 set. 문서 본문(wiki)은 documents로 가므로 뺍니다 */
  const patchSet = (base, obj) => {
    const set = {};
    for (const k of HT.PATCHABLE) {
      if (!(k in obj) || k === 'wiki') continue;
      if (sameField(k, obj[k], baseValue(base, k))) continue;
      if (k === 'color' && base.colorAuto && obj.color === base.color) continue; // 옛 수정 폼은 짐작으로 배정된 색을 그대로 담아 두었습니다 — 그것도 고치지 않은 것
      set[k] = obj[k] === undefined ? null : obj[k];
    }
    /* 날짜 칸(시작·끝 …)은 날짜 글과 한 쌍으로 담습니다 — 패치를 읽을 때 값 없이 온 날짜 글은 버려지고, 글 없이 온 값은 원래 글을 지우므로 */
    for (const k of HT.DATE_KEYS) {
      if (!(k in set || `${k}At` in set) || !(k in obj)) continue;
      set[k] = obj[k] ?? null;
      set[`${k}At`] = obj[`${k}At`] ?? null;
    }
    /* 이름을 바꾼 문화: 원본의 승계한 국가가 제 칸이 아니라 상대 국가의 succeeds(옛 이름)에서 온 선이면, 이름이 바뀐 뒤에는 그 선이 이어지지 않습니다 —
       폼에 보이던 승계한 국가를 함께 담아 선을 지킵니다 (옛 수정 폼으로 이름을 바꾼 문화의 이사 · 메이커에서 남의 문화의 이름을 바꿀 때. 이름을 그대로 두면 패치 0 그대로) */
    if ('name' in set && !('successors' in set) && base.polityKind === 'culture' && !Array.isArray(base.successorNames) && 'successors' in obj && !blankValue(obj.successors)) set.successors = obj.successors;
    return set;
  };
  /** 날짜 글 짝 칸 → 그 값 칸 (startAt → start · startRangeAt → startRange …) — 패치가 고친 칸을 보이거나 셀 때 짝 칸은 제 칸 없이 값 칸에 합칩니다 */
  HT.PATCH_AT_OF = Object.fromEntries([...HT.DATE_KEYS, 'startRange', 'endRange'].map(k => [`${k}At`, k]));
  /* 패치 전후 값을 견주는 꼴: 메이커가 패치를 만들 때(canonText)와 같게 — 빈 값 · 거짓 · 빈 목록은 같고, 모델이 짐작해 붙인 값(…Auto · 가문 이음 · 풀어 둔 끝)은 빼고,
     이어지는 칸은 짐작한 자리 없이 · 도읍은 파일의 꼴로 · 분류 없음("etc")은 빈 값 · 문화의 승계한 국가는 이름으로(모델은 그 칸을 승계선 목록으로 바꿔 둡니다) */
  const patchForm = (k, v) =>
    k === 'capitals' ? capsOf(v) : HT.CELL_CHAIN.includes(k) ? HT.cellsFileForm(v) : k === 'category' && v === 'etc' ? '' : k === 'successors' && Array.isArray(v) ? v.map(s => (typeof s === 'string' ? s : s && s.to ? s.to.name : '')).filter(Boolean) : v;
  const patchCanon = v => {
    try {
      return canonText(v);
    } catch (e) {
      return `?${String(v)}`; // 견줄 수 없는 값 (같은지 모르면 다른 것으로 — 고친 칸이 조용히 사라지지 않게)
    }
  };
  /** 모델 항목 x에 걸린 패치 하나(x.patchedBy[i])가 실제로 바꾼 칸들 → [{ k, was, now, wasAt, nowAt, edited }] — k는 값 칸 이름(짝 칸은 합침),
      was · now는 그 패치 직전 · 직후의 값(직후 = 같은 칸을 뒤 패치가 또 고쳤으면 그 패치의 전 값, 아니면 지금 값), wasAt · nowAt은 짝 칸의 날짜 글.
      전후가 같은 값인 칸은 뺍니다(글이 아니라 값으로 — 목록의 개수나 긴 글의 앞부분이 같아도 고친 칸은 남게). edited: 전후가 모두 같은 길이의 목록이면
      뒤 목록에서 앞 목록에 없던 줄의 수(0이면 차례만 바뀜). 메이커 상세의 수정 내역 상자와 '고친 것' 목록의 칸 수가 함께 씁니다 */
  HT.patchChanges = (x, i) => {
    const list = (x && x.patchedBy) || [];
    const p = list[i];
    if (!p) return [];
    const before = p.before || {};
    const after = k => {
      for (let j = i + 1; j < list.length; j++) if (list[j].before && k in list[j].before) return list[j].before[k];
      return baseValue(x, k); // 지금 값 — 모델이 짐작해 채운 값(색 · 날짜의 …Auto)은 없는 것으로, 문화의 승계한 국가는 이름으로 (패치를 만들 때와 같은 뜻)
    };
    const was = k => (k in before ? before[k] : after(k)); // 이 패치가 건드리지 않은 짝 칸은 직후 값 그대로
    return [...new Set(Object.keys(before).map(k => HT.PATCH_AT_OF[k] || k))]
      .map(k => {
        const at = `${k}At` in HT.PATCH_AT_OF ? `${k}At` : '';
        const c = { k, was: was(k), now: after(k), wasAt: at ? was(at) : undefined, nowAt: at ? after(at) : undefined };
        c.same = (patchCanon(patchForm(k, c.was)) === patchCanon(patchForm(k, c.now)) && (!at || patchCanon(c.wasAt) === patchCanon(c.nowAt))) || (k === 'color' && sameField('color', c.was, c.now));
        const rowsA = patchForm(k, c.was);
        const rowsB = patchForm(k, c.now);
        if (Array.isArray(rowsA) && Array.isArray(rowsB) && rowsA.length === rowsB.length) {
          const left = rowsA.map(patchCanon);
          const changed = rowsB.filter(r => {
            const j = left.indexOf(patchCanon(r));
            if (j < 0) return true;
            left.splice(j, 1);
            return false;
          });
          c.edited = changed.length;
          /* 그 가운데 이설 · 연대 폭 · 확실성만 고친 줄(디테일 건의 4 — 칸의 HT.UNC_KEYS를 빼면 앞 목록에 있는 줄): 수정 내역이 '지도자 12개 (1개 고침 — 이설 · 연대 폭만)'으로 */
          const bare = r => patchCanon(r && typeof r === 'object' && !Array.isArray(r) ? Object.fromEntries(Object.entries(r).filter(([q]) => !HT.UNC_KEYS.includes(q))) : r);
          const leftBare = rowsA.map(bare);
          c.uncEdited = changed.filter(r => leftBare.includes(bare(r))).length;
        }
        return c;
      })
      .filter(c => !c.same)
      .map(({ same, ...c }) => c);
  };
  /** 원본을 모르는 옛 고침(지금 설치돼 있지 않은 DLC의 항목)의 패치 set: 견줄 원본이 없으니 적힌 값 가운데 빈 값이 아닌 칸을 그대로 — 날짜 칸은 날짜 글과 한 쌍으로 */
  const looseSet = obj => {
    const set = {};
    for (const k of HT.PATCHABLE) if (k in obj && k !== 'wiki' && !blankValue(obj[k])) set[k] = obj[k];
    for (const k of HT.DATE_KEYS) if (k in set) set[`${k}At`] = obj[`${k}At`] ?? null;
    return set;
  };
  /** 작업본의 제 항목 찾기: { list, i, item } (없으면 null) — 옛 꼴로 다른 목록에 든 것까지 모든 항목 목록을 봅니다 */
  const findOwn = (draft, id) => {
    for (const [list] of DRAFT_ITEMS) {
      const i = (draft[list] || []).findIndex(x => x && x.id === id);
      if (i >= 0) return { list, i, item: draft[list][i] };
    }
    return null;
  };
  /** 폼에서 읽은 값을 제 항목에 옮깁니다: 비운 칸은 지우고, 폼에 없는 칸은 그대로 둡니다. cur = 지금의 정규화된 항목 — 폼이 모르는 안쪽 값(FORM_ROW_KEYS)이 든 목록은 손대지 않았으면 그대로.
      문서 본문(wiki)은 여기서 다루지 않습니다 — 본문의 자리는 documents (HT.draft.setDoc). 확실성은 기본값(통설)이면 적지 않습니다 (폼은 늘 값을 내놓으므로, 열어서 그대로 저장해도 자료가 달라지지 않게) */
  const putFields = (item, obj, cur) => {
    for (const [k, v] of Object.entries(obj)) {
      if (k === 'id' || k === 'wiki') continue;
      if (cur && FORM_ROW_KEYS[k] && sameField(k, v, cur[k])) continue;
      if (k === 'color' && HT.isColor(item.color) && sameField(k, v, item.color)) continue; // 파스텔로 맞춰졌을 뿐인 색은 적힌 그대로
      if (k === 'certainty') delete item.legendary; // 옛 표기(legendary)는 확실성 칸으로 갈음
      if (blankValue(v) || (k === 'certainty' && v === 'accepted')) delete item[k];
      else item[k] = v;
    }
    /* 폼이 시작 · 끝 칸을 적었으면 파일에서 온 배치용 연도(startHint · endHint)는 걷어 냅니다 — 폼의 숫자 칸이 곧 배치용 연도인데, 남아 있으면 읽을 때
       그것이 먼저라(HT.readCellEdge · readRange) 폼에서 고친 배치용 연도가 소리 없이 버려집니다 (시대 · 사건 · 인물 · 대범위의 미정. 내보내는 파일은 그대로) */
    for (const k of ['start', 'end']) if (k in obj && `${k}Hint` in item) delete item[`${k}Hint`];
    return item;
  };
  const verParts = v => (/^\d+(\.\d+)*$/.test(str(v)) ? str(v).split('.').map(Number) : null);

  HT.draft = {
    LISTS: DRAFT_LISTS,
    WORDS: LIST_WORDS, // 목록 이름 → 낱말 (메이커의 판 기록 요약)
    /** 빈 작업본 */
    blank: (meta = {}) =>
      Object.assign(
        { format: HT.FORMAT, formatVersion: HT.FORMAT_VERSION, id: str(meta.id) || 'my-dlc', name: str(meta.name) || '새 DLC', version: str(meta.version) || '1.0.0', author: str(meta.author), description: str(meta.description), requires: [] },
        Object.fromEntries(DRAFT_LISTS.map(k => [k, []])),
        { documents: {} }
      ),
    /** 파일 · 설치본 · 옛 임시 저장본을 작업본으로: 목록을 갖추고, 옛 꼴의 시대(kind: overlay · culture · dynasty)를 제 목록으로 옮기고,
        모든 항목에 겹치지 않는 올바른 id를 줍니다 — 그래야 정규화 뒤에도 id가 그대로여서 연표의 항목(<DLC id>/<항목 id>)과 작업본의 항목이 늘 짝이 맞습니다.
        없는 id는 HT.normalizePack이 매길 것과 같은 값으로 (그 id를 가리키던 다른 DLC의 패치 · 문서가 떨어지지 않게) */
    clean(raw) {
      const src = raw && typeof raw === 'object' && !Array.isArray(raw) ? JSON.parse(JSON.stringify(raw)) : {};
      const d = Object.assign(HT.draft.blank(), src, { format: HT.FORMAT, formatVersion: HT.FORMAT_VERSION });
      for (const k of DRAFT_LISTS) d[k] = arr(d[k]).filter(x => x && typeof x === 'object' && !Array.isArray(x));
      d.requires = arr(d.requires).map(str).filter(Boolean);
      if (!d.documents || typeof d.documents !== 'object' || Array.isArray(d.documents)) d.documents = {};
      d.periods = d.periods.filter(x => {
        const { kind, partOf, ...rest } = x;
        if (kind === 'overlay') d.organs.push(Object.assign(rest, { host: x.host ?? partOf }));
        else if (kind === 'culture') d.cultures.push(Object.assign(rest, partOf ? { partOf } : {}));
        else if (kind === 'dynasty') d.dynasties.push(Object.assign(rest, { polities: x.polities ?? partOf }));
        else return true;
        return false;
      });
      const used = new Set();
      for (const [list, prefix, nameKey] of DRAFT_ITEMS) {
        for (const x of d[list]) {
          let id = str(x.id);
          if (!ID_RE.test(id) && list === 'figures') {
            const b = HT.readDate(x.birth, x.birthAt); // 인물: 트랙 | 이름 | 생년 (활동 시기를 고쳐도 id가 바뀌지 않게 — HT.normalizePack의 인물 읽기와 같은 씨앗)
            id = prefix + HT.hash(`${str(x.track)}|${str(x.name ?? x.title)}|${b && !isNaN(b.t) ? Math.floor(b.t + 1e-9) : ''}`);
          } else if (!ID_RE.test(id) && list === 'scopes') {
            const seed = scopeSeed(x); // 대범위: 트랙 + 이름 + 시작 해 — 차례가 다른 항목(트랙 + 시작 해 + 이름)과 다름
            id = seed != null ? prefix + HT.hash(seed) : HT.uid(prefix.slice(0, -1));
          } else if (!ID_RE.test(id) && list === 'institutions') {
            const ref = HT.readInstPolity(x.polity, x.track); // 제도: 트랙 | 나라 | 주제 (HT.normalizePack의 제도 읽기와 같은 씨앗 — 칸을 고쳐도 id가 바뀌지 않게)
            const theme = Array.isArray(x.theme) ? str(x.theme[0]) : str(x.theme);
            id = ref && theme ? prefix + HT.hash(`${ref.track || ''}|${ref.polity}|${theme}`) : HT.uid(prefix.slice(0, -1));
          } else if (!ID_RE.test(id)) {
            const at = HT.readDate(HT.isUnknownText(x.start) ? x.startHint ?? x.end : x.start, x.startAt);
            const name = str(x[nameKey] ?? (nameKey === 'title' ? x.name : x.title));
            id = at && !isNaN(at.t) ? prefix + HT.hash(str(x.track) + Math.floor(at.t + 1e-9) + name) : HT.uid(prefix.slice(0, -1));
          }
          if (used.has(id)) {
            let n = 2;
            while (used.has(`${id}-${n}`)) n++;
            id = `${id}-${n}`;
          }
          used.add(id);
          x.id = id;
        }
      }
      /* 가문 · 지위 사전의 비운 id도 HT.normalizePack이 매길 값으로 채워 둡니다 — 바탕 자료 창의 id 칸 · 문서("house:id") · 쓰는 곳이 모델의 것과 같게 (내보내는 파일은 그대로) */
      for (const [list, prefix] of [['houses', 'h-'], ['rankDefs', 'rank-'], ['themes', 'theme-'], ['surnames', 'sn-'], ['places', 'pl-'], ['spheres', 'sphere-']]) for (const x of d[list]) if (!str(x.id) && str(x.name)) x.id = prefix + HT.hash(str(x.name)); // 주제 · 성씨 · 지명(형식 버전 3) · 문화권도
      return d;
    },
    /** 브라우저에 임시 저장된 작업본 (없으면 null) — 옛 메이커의 임시 저장본도 그대로 이어받습니다 */
    load() {
      const raw = HT.store.get(HT.KEYS.draft, null);
      return raw && typeof raw === 'object' && !Array.isArray(raw) ? HT.draft.clean(raw) : null;
    },
    save: draft => HT.store.set(HT.KEYS.draft, draft),
    /** 작업본에 든 것이 있는지 (목록 · 문서) */
    hasWork: draft => !!draft && (DRAFT_LISTS.some(k => arr(draft[k]).length > 0) || Object.keys(draft.documents || {}).length > 0),
    /** 제 항목인지: uid가 "<작업본 id>/…" */
    isOwnUid: (draft, uid) => !!draft && String(uid).startsWith(`${draft.id}/`),
    findOwn,

    /** 새 항목을 제 목록에 — 새 id를 돌려줍니다 (연표의 uid는 "<작업본 id>/<이 id>") */
    addItem(draft, kind, obj) {
      const F = HT.FORMS[kind];
      if (!F) throw new Error(`"${kind}" 항목을 작업본에 넣는 법이 없습니다.`);
      const prefix = DRAFT_ITEMS.find(r => r[0] === F.list)[1].slice(0, -1);
      let id = HT.uid(prefix);
      while (findOwn(draft, id)) id = HT.uid(prefix);
      if (!Array.isArray(draft[F.list])) draft[F.list] = [];
      draft[F.list].push(putFields({ id }, obj));
      return id;
    },
    /** 제 항목을 고칩니다 (없으면 false). cur = 지금 모델에 있는 그 항목 (putFields) */
    updateOwn(draft, id, obj, cur) {
      const hit = findOwn(draft, id);
      if (!hit) return false;
      putFields(hit.item, obj, cur);
      return true;
    },
    /** 제 항목을 지웁니다 — 그 항목과 하위 문서 · 칸 문서도 함께 */
    removeOwn(draft, id) {
      const hit = findOwn(draft, id);
      if (!hit) return false;
      draft[hit.list].splice(hit.i, 1);
      const uid = `${draft.id}/${id}`;
      for (const k of Object.keys(draft.documents || {})) {
        const abs = HT.docKey.absolute(k, draft.id);
        if (abs === uid || abs.startsWith(`${uid}//`) || abs.startsWith(`cell:${uid}:`)) delete draft.documents[k];
      }
      return true;
    },
    /** 남의 항목을 고칩니다: base(다른 팩들만으로 만든 모델의 그 항목)와 견줘 바뀐 칸만 담은 패치로 그 대상의 패치를 통째로 갈아 끼웁니다.
        바뀐 것이 없으면(원래 값으로 되돌렸으면) 패치가 사라집니다. 폼에 칸이 없는 열쇠(손으로 적은 패치의 polity 같은)와 메모, 패치로 단 문서 본문(set.wiki)은 이어받습니다
        (본문을 고치면 documents로 옮겨 갑니다 — HT.draft.setDoc). 돌려주는 값: 새 패치나 null */
    patchForeign(draft, base, obj) {
      const set = patchSet(base, obj);
      const olds = draft.patches.filter(p => p && p.target === base.uid);
      const was = olds.map(p => (!p.hide && p.set) || {});
      /* 색: 편집 창은 보이는 색(패치의 색을 파스텔로 맞춘 값)을 한 번 더 파스텔로 맞춰 담습니다 — 패치에 적힌 색이나 그것이 파스텔을 거친 값이면 고치지 않은 것
         (원본과만 견주면 견본 밖의 색을 건 패치가 열어서 저장할 때마다 바랩니다) */
      const oldColor = (was.find(s => HT.isColor(s.color)) || {}).color;
      if (oldColor && HT.isColor(obj.color) && [oldColor, HT.pastel(oldColor), HT.pastel(HT.pastel(oldColor))].some(c => c.toLowerCase() === obj.color.toLowerCase())) {
        if (sameField('color', oldColor, baseValue(base, 'color'))) delete set.color;
        else set.color = oldColor;
      }
      for (const s of was) for (const [k, v] of Object.entries(s)) if ((!(k in obj) || k === 'wiki') && !(k in set)) set[k] = v;
      /* 칸의 차례는 옛 패치의 것을 따르고 새 칸은 뒤에 — 고치지 않고 저장하면 내보낸 파일도 그대로 */
      const order = [...new Set(was.flatMap(s => Object.keys(s)))].filter(k => k in set);
      const ordered = Object.fromEntries(order.concat(Object.keys(set).filter(k => !order.includes(k))).map(k => [k, set[k]]));
      const at = olds.length ? draft.patches.indexOf(olds[0]) : draft.patches.length;
      const note = (olds.find(p => str(p.note)) || {}).note;
      const next = Object.keys(ordered).length ? [Object.assign({ target: base.uid, set: ordered }, note ? { note } : {})] : [];
      draft.patches = draft.patches.slice(0, at).concat(next, draft.patches.slice(at).filter(p => !olds.includes(p)));
      return next[0] || null;
    },
    /** 남의 항목을 숨깁니다 (그 대상의 패치는 숨김 하나로 바뀝니다) */
    hideForeign(draft, uid) {
      draft.patches = draft.patches.filter(p => !p || p.target !== uid).concat([{ target: uid, hide: true }]);
    },
    /** 숨김을 풉니다 */
    unhide(draft, uid) {
      draft.patches = draft.patches.filter(p => !(p && p.target === uid && p.hide));
    },
    /** 그 대상에 건 패치(고침 · 숨김)를 모두 걷어 원래대로 */
    unpatch(draft, uid) {
      draft.patches = draft.patches.filter(p => !p || p.target !== uid);
    },
    /** 문서를 적습니다 (빈 글이면 지움). key는 연표의 문서 키(절대 키) — 제 항목의 것은 상대 키로 담깁니다.
        항목 · 트랙 · 민족 · 가문에 직접 적혀 있던 본문(wiki 칸)과 그 항목에 건 패치의 본문(set.wiki)은 지웁니다 — 본문의 자리는 documents 하나뿐
        (패치의 본문이 남아 있으면 문서를 지웠을 때 옛 본문이 되살아납니다) */
    setDoc(draft, key, text) {
      if (!draft.documents || typeof draft.documents !== 'object' || Array.isArray(draft.documents)) draft.documents = {};
      const abs = HT.docKey.absolute(key, draft.id);
      for (const k of Object.keys(draft.documents)) if (HT.docKey.absolute(k, draft.id) === abs) delete draft.documents[k];
      if (typeof text === 'string' && text.trim()) draft.documents[HT.docKey.relative(abs, draft.id)] = text;
      const p = HT.docKey.parse(abs);
      if (p.sub) return;
      if (p.type === 'item') {
        const keep = [];
        for (const q of arr(draft.patches)) {
          if (q && q.target === p.uid && q.set && typeof q.set === 'object' && 'wiki' in q.set) {
            delete q.set.wiki;
            if (!Object.keys(q.set).length) delete q.set;
            if (!q.hide && !q.set) continue; // 본문만 담던 패치는 사라집니다
          }
          keep.push(q);
        }
        draft.patches = keep;
      }
      if (p.type === 'item' && HT.draft.isOwnUid(draft, p.uid)) {
        const hit = findOwn(draft, p.uid.slice(draft.id.length + 1));
        if (hit) delete hit.item.wiki;
      } else if (p.type === 'track' || p.type === 'people' || p.type === 'house' || p.type === 'view' || p.type === 'map' || p.type === 'surname' || p.type === 'place') {
        /* 가문의 본문(houses[].wiki)도 모델이 documents에 없을 때만 문서로 쓰므로 함께 지웁니다 (남겨 두면 문서를 지웠을 때 옛 본문이 되살아남) — 형식 3의 판 · 지도 · 성씨 · 지명 사전도 같게 */
        const def = arr(draft[{ track: 'tracks', people: 'peoples', house: 'houses', view: 'views', map: 'maps', surname: 'surnames', place: 'places' }[p.type]]).find(x => x && x.id === p.id);
        if (def) delete def.wiki;
      }
    },
    /** 제 항목이 쓰는 트랙 · 분류 · 민족 가운데 작업본의 목록에 없는 것을 모델에서 찾아 싣습니다 — 제 목록에 없는 트랙의 항목은 검사에서 떨어지므로, 항목을 넣거나 고친 뒤 늘 부릅니다.
        모델도 모르는 것은 싣지 않습니다 (검사가 알려 줍니다) */
    ensureRefs(draft, model) {
      if (!model) return;
      const has = (list, id) => arr(draft[list]).some(x => x && x.id === id);
      for (const [list] of DRAFT_ITEMS) {
        for (const x of arr(draft[list])) {
          const t = str(x.track) && !has('tracks', str(x.track)) ? model.trackMap.get(str(x.track)) : null;
          if (t) draft.tracks.push(Object.assign({ id: t.id, name: t.name, color: t.color }, t.order < 1000 ? { order: t.order } : {}, t.sphereSet ? { sphere: t.sphere } : {}));
        }
      }
      for (const e of arr(draft.events)) {
        const id = str(e.category);
        const c = id && !has('categories', id) && !HT.DEFAULT_CATEGORIES.some(d => d.id === id) && id !== 'etc' ? model.categoryMap.get(id) : null;
        if (c) draft.categories.push({ id: c.id, name: c.name, color: c.color });
      }
      for (const x of arr(draft.periods).concat(arr(draft.cultures))) {
        const ref = str(x.people);
        if (!ref || arr(draft.peoples).some(p => p && (p.id === ref || p.name === ref))) continue;
        const pe = model.peoples.find(p => !p.auto && (p.id === ref || p.name === ref));
        if (pe) draft.peoples.push(Object.assign({ id: pe.id, name: pe.name }, pe.parent ? { parent: pe.parent } : {}, pe.color ? { color: pe.color } : {}));
      }
    },
    /** 판 올림: "1.0.3" → "1.0.4" (숫자 셋이 아니면 뒤에 ".1") */
    bumpVersion(v) {
      const s = str(v) || '1.0.0';
      const m = s.match(/^(\d+)\.(\d+)\.(\d+)$/);
      return m ? `${m[1]}.${m[2]}.${Number(m[3]) + 1}` : `${s}.1`;
    },
    /** 둘 가운데 더 높은 판 (숫자와 점으로만 된 판끼리만 견줍니다 — 아니면 앞의 것) */
    newerVersion(a, b) {
      const pa = verParts(a);
      const pb = verParts(b);
      if (!pa || !pb) return str(a) || str(b);
      for (let i = 0; i < Math.max(pa.length, pb.length); i++) if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0) ? str(a) : str(b);
      return str(a);
    },
    /** 반영하지 않은 고침의 목록: 정규화한 작업본(a)과 설치된 같은 id의 DLC(b — 없으면 null)를 견줍니다. 판 번호는 보지 않습니다.
        [{ type: 'add'|'edit'|'remove'|'error', list, key, label }] — a가 null이면(검사를 통과하지 못한 작업본) 'error' 하나 */
    changes(a, b) {
      if (!a) return [{ type: 'error', list: '', key: '', label: '검사를 통과하지 못한 작업본' }];
      const A = HT.packToJSON(a);
      const B = b ? HT.packToJSON(b) : {};
      const out = [];
      const word = { add: '추가', edit: '고침', remove: '삭제' };
      const put = (type, list, key, what, name) => out.push({ type, list, key, label: `${what} ${word[type]}${name ? ` · ${name}` : ''}` });
      const INFO = [['name', '이름'], ['author', '만든 사람'], ['description', '설명'], ['requires', '함께 쓰면 좋은 DLC'], ['category', '분류'], ['tags', '태그'], ['summary', '짧은 소개'], ['highlights', '볼거리'], ['cover', '표지'], ['relations', '관계'], ['changelog', '판 기록'], ['created', '만든 날'], ['updated', '반영한 날']];
      if (b) for (const [k, what] of INFO) if (canonText(A[k]) !== canonText(B[k])) put('edit', 'info', k, `DLC 정보(${what})`, '');
      if (b && JSON.stringify(A.yearCycle ?? null) !== JSON.stringify(B.yearCycle ?? null)) put('edit', 'info', 'yearCycle', 'DLC 정보(간지 설정)', ''); // 형식 3 — false(간지 줄 끔)도 적은 값이라 빈 값 견주기(canonText)를 거치지 않음
      if (b && canonText(A.yearCycles) !== canonText(B.yearCycles)) put('edit', 'info', 'yearCycles', 'DLC 정보(문화권별 주기 줄)', ''); // 형식 4 더하기 — 「주기」 표(5단계 과제 6 · 줄에 id가 없어 통째로 견줌)
      for (const list of DRAFT_LISTS) {
        const keyOf = x => (list === 'patches' ? x.target : x.id);
        const nameOf = x => x.title || x.name || (list === 'scopes' ? x.epoch : '') || keyOf(x); // 이름을 비운 대범위는 시대 구분의 이름으로 (바탕 자료의 대범위 목록과 같은 규칙)
        const old = new Map(arr(B[list]).map(x => [keyOf(x), x]));
        for (const x of arr(A[list])) {
          const o = old.get(keyOf(x));
          old.delete(keyOf(x));
          if (!o) put('add', list, keyOf(x), LIST_WORDS[list], nameOf(x));
          else if (canonText(x) !== canonText(o)) put('edit', list, keyOf(x), LIST_WORDS[list], nameOf(x));
        }
        for (const o of old.values()) put('remove', list, keyOf(o), LIST_WORDS[list], nameOf(o));
      }
      const docsA = A.documents || {};
      const docsB = B.documents || {};
      for (const k of Object.keys(docsA)) if (!(k in docsB)) put('add', 'documents', k, '문서', k); else if (docsA[k] !== docsB[k]) put('edit', 'documents', k, '문서', k);
      for (const k of Object.keys(docsB)) if (!(k in docsA)) put('remove', 'documents', k, '문서', k);
      if (canonText(A.territory) !== canonText(B.territory)) put(B.territory ? (A.territory ? 'edit' : 'remove') : 'add', 'territory', '', '영토', '');
      for (const list of DRAFT_LISTS_V3) {
        const old = new Map(arr(B[list]).map(x => [x.id, x]));
        for (const x of arr(A[list])) {
          const o = old.get(x.id);
          old.delete(x.id);
          if (!o) put('add', list, x.id, LIST_WORDS[list], x.name || x.family || x.id);
          else if (canonText(x) !== canonText(o)) put('edit', list, x.id, LIST_WORDS[list], x.name || x.family || x.id);
        }
        for (const o of old.values()) put('remove', list, o.id, LIST_WORDS[list], o.name || o.family || o.id);
      }
      return out;
    },
    /** 반영하지 않은 고침이 있는지. draft · installed는 DLC JSON (installed가 없으면 작업본에 든 것이 모두 고침) */
    isDirty(draft, installed) {
      const b = installed ? HT.normalizePack(installed).pack : null;
      return HT.draft.changes(HT.normalizePack(draft).pack, b).length > 0;
    },

    /** 옛 "내 수정"(덧씌움)을 하나의 DLC(JSON)로: 추가한 항목은 목록에, 고친 항목은 바뀐 칸만 패치로, 숨긴 항목은 hide 패치로, 문서는 documents로.
        packs = 그 수정이 얹혀 있던 DLC들(정규화한 것). 옛 뷰어의 "수정 내용을 DLC로"와 같은 규칙입니다 */
    fromUser(user, packs, meta = {}) {
      const u = Object.assign(HT.blankUser(), user);
      const base = HT.buildModel(packs, null); // 내 수정을 뺀 원본
      const m = HT.buildModel(packs, u);
      /* 추가한 항목: 목록(HT.USER_LISTS)마다 얕게 복사 — 목록 하나라도 빠지면 옮긴 뒤 그 항목이 사라집니다 */
      const lists = {};
      for (const { list } of HT.USER_LISTS) lists[list] = arr(u[list]).filter(x => x && typeof x === 'object').map(x => Object.assign({}, x));
      const patchMap = new Map();
      const own = uid => uid.startsWith(`${HT.USER_PACK.id}/`) || (!!meta.id && uid.startsWith(`${meta.id}/`)); // 내 항목 · 이 DLC 자신의 항목(패치가 아니라 항목에 바로)
      for (const [uid, ov] of Object.entries(u.overrides || {})) {
        if (!ov || typeof ov !== 'object' || own(uid)) continue;
        const item = base.byUid.get(uid);
        /* 지금 설치돼 있지 않은 DLC의 항목: 버리지 않고 적힌 값을 패치로 — 대상이 없는 패치는 조용히 쉬다가, 그 DLC를 다시 설치하면 옛 연표처럼 다시 얹힙니다 */
        const set = item ? patchSet(item, ov) : looseSet(ov);
        if (Object.keys(set).length) patchMap.set(uid, { target: uid, set });
      }
      for (const uid of Object.keys(u.hidden || {})) if (!own(uid)) patchMap.set(uid, { target: uid, hide: true }); // 숨김도 같은 규칙 (대상이 없으면 쉬다가 설치하면 숨김)
      /* 문서: 내 항목(user/…)은 새 DLC의 항목이 되므로 상대 키로, 남의 항목·민족·트랙·칸은 그대로 */
      const documents = {};
      for (const [key, text] of Object.entries(u.wiki || {})) {
        if (typeof text !== 'string' || !text.trim()) continue;
        const d = base.docs.get(key);
        if (d && d.text === text) continue;
        documents[HT.docKey.relative(key, HT.USER_PACK.id)] = text;
      }
      const all = [].concat(...Object.values(lists));
      for (const x of all) {
        if (str(x.wiki) && x.id && !(x.id in documents)) documents[x.id] = String(x.wiki); // 문서 저장소에 없는 본문은 옮겨 담고
        delete x.wiki; // 본문은 documents에 한 번만
      }
      const usedTracks = new Set(all.map(x => x.track));
      const usedCats = new Set(lists.events.map(e => e.category));
      const peopleNames = new Set(lists.periods.concat(lists.cultures).map(p => p.people).filter(Boolean));
      const out = Object.assign(
        {
          format: HT.FORMAT,
          formatVersion: HT.FORMAT_VERSION,
          id: meta.id,
          name: meta.name,
          version: meta.version || '1.0.0',
          description: meta.description || '',
          tracks: m.tracks.filter(t => usedTracks.has(t.id)).map(t => ({ id: t.id, name: t.name, color: t.color, order: t.order < 1000 ? t.order : undefined, sphere: t.sphereSet ? t.sphere : undefined })),
          categories: m.categories.filter(c => usedCats.has(c.id) && !HT.DEFAULT_CATEGORIES.some(d => d.id === c.id)).map(c => ({ id: c.id, name: c.name, color: c.color })),
          peoples: m.peoples.filter(p => peopleNames.has(p.name) && !p.auto).map(p => Object.assign({ id: p.id, name: p.name }, p.parent ? { parent: p.parent } : {}, p.color ? { color: p.color } : {})),
        },
        lists,
        { patches: [...patchMap.values()], documents }
      );
      /* 색: 옛 수정 폼은 남의 항목을 열어 저장할 때 그때 짐작으로 배정된 색을 color로 굳혀 두었습니다. 짐작 색은 자료로 굳히지 않는 것이 규칙이지만(patchSet),
         숨김 · 추가로 트랙 안의 차례가 바뀌었으면 옮긴 뒤 그 띠의 색이 옛 화면과 달라집니다 — 새 DLC로 지은 모델에서 색이 달라진 고친 항목에만 옛 색을 담습니다 (이사에서만) */
      const made = HT.normalizePack(out).pack;
      if (made) {
        const now = HT.buildModel(packs.concat([made]), null);
        let recolored = false;
        for (const uid of Object.keys(u.overrides || {})) {
          const was = m.byUid.get(uid);
          const got = now.byUid.get(uid);
          const p = patchMap.get(uid);
          if (!was || !got || was.kind !== 'period' || !HT.isColor(was.color) || got.color === was.color || (p && p.hide)) continue;
          patchMap.set(uid, { target: uid, set: Object.assign({}, p && p.set, { color: was.color }) });
          recolored = true;
        }
        if (recolored) out.patches = [...patchMap.values()];
      }
      return out;
    },
    /** 이미 있는 DLC(existing)에 add의 내용을 합칩니다: 항목은 더하고, 같은 id의 항목 · 같은 대상의 패치 · 같은 문서는 새것이 이깁니다 (트랙 · 분류 · 민족의 정의는 있던 것 그대로) */
    merge(existing, add) {
      const out = HT.draft.clean(existing);
      for (const list of DRAFT_LISTS) {
        const keyOf = x => (list === 'patches' ? x.target : x.id);
        const isDef = list === 'tracks' || list === 'categories' || list === 'peoples' || list === 'spheres';
        for (const x of arr(add[list])) {
          const i = out[list].findIndex(o => keyOf(o) === keyOf(x));
          if (i < 0) out[list].push(x);
          else if (!isDef) out[list][i] = x;
        }
      }
      for (const [k, text] of Object.entries(add.documents || {})) HT.draft.setDoc(out, HT.docKey.absolute(k, out.id), text);
      return out;
    },
    /** 옛 "내 수정"의 이사: HT.KEYS.user에 내용이 있으면 DLC «내 수정»(id my-edits — 이미 설치돼 있으면 거기에 합침)을 만들어 설치 · 켜고,
        원본은 HT.KEYS.userBackup에 남긴 뒤 비웁니다. 만들기나 저장에 실패하면 아무것도 지우지 않습니다.
        돌려주는 값: 옮길 것이 없으면 null · { ok: true, name, counts } · { ok: false, message, user(그대로 남은 내 수정 — 화면에는 계속 보이게) } */
    migrateUser() {
      const K = HT.KEYS;
      const raw = HT.store.get(K.user, null);
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
      const user = Object.assign(HT.blankUser(), raw);
      for (const k of ['overrides', 'hidden', 'wiki']) if (!user[k] || typeof user[k] !== 'object') user[k] = {};
      const nItems = HT.USER_LISTS.reduce((n, { list }) => n + arr(user[list]).length, 0);
      const counts = { items: nItems, overrides: Object.keys(user.overrides).length, hidden: Object.keys(user.hidden).length, wiki: Object.keys(user.wiki).length };
      if (!counts.items && !counts.overrides && !counts.hidden && !counts.wiki) return null;
      const ID = 'my-edits';
      const fail = message => ({ ok: false, message, user });
      try {
        const packState = HT.store.get(K.packState, {});
        const isOn = id => !packState[id] || packState[id].enabled !== false;
        const all = HT.loadPacks().filter(p => p.id !== ID); // 이미 있는 «내 수정»의 패치는 원본에서 빼고 견줍니다 (새 패치가 그 대상의 패치를 통째로 갈음하므로)
        /* 꺼 둔 DLC의 항목을 고치거나 숨긴 것이 있으면 모든 DLC를 놓고 견줍니다 (그 고침이 빠지지 않게) */
        const on = all.filter(p => isOn(p.id));
        const need = Object.keys(user.overrides).concat(Object.keys(user.hidden)).filter(uid => !uid.startsWith(`${ID}/`));
        const baseOn = HT.buildModel(on, null);
        const useOn = need.every(uid => baseOn.byUid.has(uid));
        const add = HT.draft.fromUser(user, useOn ? on : all, { id: ID, name: '내 수정', description: '예전 연표의 수정 모드에서 추가 · 고침 · 숨김 · 문서로 쌓아 둔 "내 수정"을 옮겨 온 DLC' });
        /* 지금 설치돼 있지 않은 DLC의 항목에 대한 고침 · 숨김 — 패치로 옮겨 두었다가 그 DLC를 다시 설치하면 얹힙니다 (알림에 따로 적음) */
        const baseFor = useOn ? baseOn : HT.buildModel(all, null);
        counts.waiting = new Set(need.filter(uid => !uid.startsWith(`${HT.USER_PACK.id}/`) && !baseFor.byUid.has(uid))).size;
        const added = HT.normalizePack(add);
        if (!added.pack) return fail(`옛 "내 수정"을 DLC로 만들지 못했습니다: ${added.errors[0] && added.errors[0].msg}`);
        const got = HT.USER_LISTS.reduce((n, { list }) => n + arr(added.pack[list]).length, 0); // 인물처럼 쓸 때만 생기는 목록은 없을 수 있음
        if (got < nItems) return fail(`옛 "내 수정"의 항목 ${nItems - got}개가 DLC에 담기지 못해 옮기지 않았습니다.${added.errors[0] ? ` ${added.errors[0].msg}` : ''}`);
        const installed = arr(HT.store.get(K.installed, []));
        const existing = installed.find(p => p && p.id === ID);
        let next = add;
        if (existing) {
          next = HT.draft.merge(existing, add);
          /* «내 수정» 자신의 항목을 고치거나 숨긴 것은 그 항목에 바로 */
          for (const [uid, ov] of Object.entries(user.overrides)) if (uid.startsWith(`${ID}/`) && ov && typeof ov === 'object') HT.draft.updateOwn(next, uid.slice(ID.length + 1), ov);
          for (const uid of Object.keys(user.hidden)) if (uid.startsWith(`${ID}/`)) HT.draft.removeOwn(next, uid.slice(ID.length + 1));
          next.version = HT.draft.bumpVersion(next.version);
        }
        const { pack, errors } = HT.normalizePack(next);
        if (!pack) return fail(`옛 "내 수정"을 DLC로 만들지 못했습니다: ${errors[0] && errors[0].msg}`);
        if (!HT.store.set(K.userBackup, raw)) return fail('저장 공간이 부족해 옛 "내 수정"을 옮기지 못했습니다.');
        const json = HT.packToJSON(pack);
        if (!HT.store.set(K.installed, installed.filter(p => !p || p.id !== ID).concat([json]))) {
          HT.store.remove(K.userBackup);
          return fail('저장 공간이 부족해 옛 "내 수정"을 옮기지 못했습니다.');
        }
        HT.store.set(K.packState, Object.assign({}, packState, { [ID]: { enabled: true } }));
        HT.store.remove(K.user);
        return { ok: true, id: ID, name: pack.name, version: pack.version, counts };
      } catch (e) {
        console.warn('옛 "내 수정" 옮기기 실패', e);
        return fail(`옛 "내 수정"을 옮기지 못했습니다: ${e && e.message ? e.message : e}`);
      }
    },
  };
})();
