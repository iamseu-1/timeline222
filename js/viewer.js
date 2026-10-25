/* 역사 연표 — 연표 화면 (필터, 검색, 상세 보기, 문서, DLC 관리). 두 화면이 이 파일을 함께 씁니다:
   · index.html(<body data-app="view">) — 연표. 보기 전용이라 편집 길(편집기 · 삭제/숨기기 · 되돌리기 · 문서 저장)은 단추만 없는 것이 아니라 함수에서부터 닫혀 있습니다.
     메이커로 가는 길(메뉴 · 단축키 · 항목 넘겨주기)도 두지 않습니다 — 일방통행: 메이커 → 연표('연표로 ↗')의 한 방향뿐입니다.
   · dlc-maker.html(<body data-app="make">) — DLC 메이커. 같은 화면이 늘 수정 모드로 뜨고, 메이커 부품(js/maker.js의 HT.makerPlugin — 지도 부품처럼 있을 때만 부름)이
     맨 위 메이커 줄과 고치는 DLC(작업본)를 맡습니다. 저장은 덧씌움 없이 작업본을 바로 고칩니다 (순수 계산은 js/core.js의 HT.draft) */
(function () {
  'use strict';
  const HT = window.HT;
  const K = HT.KEYS;
  const esc = HT.escapeHtml;
  const $ = sel => document.querySelector(sel);
  const MAKE = document.body.dataset.app === 'make' && typeof HT.makerPlugin === 'function';

  /* 선 아이콘 한 벌 (건의 8 — 감독 선택 2026-10-13 '1. A · 가', '3. 후'): HistoryArchive와 같은 Lucide 꼴(24칸 격자 · 선 1.5 · 둥근 끝 · 채움 없음 · 글자색).
     맨 위 줄(독)의 기호 단추 · 오른쪽 아래 확대 묶음 · ⋯ 차림표(오른쪽 클릭 차림표도) · 렌즈 차림표 · 상세 창과 필터 시트의 단추가 이 한 벌만 씁니다 — 색 그림 글자(📍 📄 🎯 …)는 쓰지 않음.
     HT.icon(이름, 덧붙일 class)는 <svg class="ic"> 글을 돌려주고, 정적 HTML(index.html · dlc-maker.html)은 data-icon="이름"을 달면 아래에서 맨 앞에 채웁니다. 크기는 CSS(.ic 16 · 독 18) */
  const ICONS = {
    layers: '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>',
    menu: '<path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h16"/>',
    eye: '<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/>',
    more: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
    pin: '<path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>',
    ruler: '<path d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z"/><path d="m14.5 12.5 2-2"/><path d="m11.5 9.5 2-2"/><path d="m8.5 6.5 2-2"/><path d="m17.5 15.5 2-2"/>',
    expand: '<path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="m3 21 7-7"/><path d="M9 21H3v-6"/>',
    bird: '<path d="m7 20 5-5 5 5"/><path d="m7 4 5 5 5-5"/>',
    fold: '<path d="M12 22v-6"/><path d="M12 8V2"/><path d="M4 12H2"/><path d="M10 12H8"/><path d="M16 12h-2"/><path d="M22 12h-2"/><path d="m15 19-3-3-3 3"/><path d="m15 5-3 3-3-3"/>',
    help: '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',
    table: '<path d="M12 3v18"/><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/>',
    image: '<rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>',
    package: '<path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z"/><path d="M12 22V12"/><path d="m3.3 7 7.703 4.734a2 2 0 0 0 1.994 0L20.7 7"/><path d="m7.5 4.27 9 5.15"/>',
    scan: '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/>',
    search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    activity: '<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/>',
    file: '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>',
    'zoom-in': '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/><path d="M11 8v6"/><path d="M8 11h6"/>',
    map: '<path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15"/><path d="M9 3.236v15"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
    minus: '<path d="M5 12h14"/>',
    route: '<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    printer: '<path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 9V3a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v6"/><rect x="6" y="14" width="12" height="8" rx="1"/>',
  };
  HT.icon = (name, cls = '') =>
    ICONS[name] ? `<svg class="ic${cls ? ` ${cls}` : ''}" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${ICONS[name]}</svg>` : '';
  const icon = HT.icon;
  for (const el of document.querySelectorAll('[data-icon]')) if (!el.querySelector(':scope > svg.ic')) el.insertAdjacentHTML('afterbegin', icon(el.dataset.icon));

  /* 옛 "내 수정"(이 브라우저에 덧씌움으로 쌓아 두던 추가 · 고침 · 숨김 · 문서)이 남아 있으면 DLC «내 수정»으로 옮깁니다 — 한 번만. 알림은 화면이 뜬 뒤에 */
  const moved = HT.draft.migrateUser();

  const savedUi = HT.store.get(K.ui, {});
  const state = {
    packs: [],
    packState: HT.store.get(K.packState, {}),
    legacyUser: moved && !moved.ok ? moved.user : null, // 옮기지 못한 옛 내 수정 — 지우지 않았으니 화면에는 계속 얹어 보여 줍니다 (고칠 수는 없음)
    editMode: MAKE, // 메이커는 늘 수정 모드: 연표에서 항목을 누르면 바로 편집
    /* 표시 체크(show)는 한 단계 더 합칩니다 — 저장된 설정에 없는 열쇠는 HT.SHOW_DEFAULTS의 값으로 (뒤에 생긴 표시가 옛 사용자에게 꺼진 채 나오지 않게) */
    ui: Object.assign(
      { tracks: {}, categories: {}, kinds: {}, minImportance: 1, density: 0, birdShape: 'a', birdAuto: false, birdFrom: 0, showAlt: true, lens: '', folded: [], foldedPeoples: [], foldedEras: [], axisOpen: [], openCapSec: [], expandedHosts: [], leaderLabel: 'auto', leaderOrdinal: false, legend: false },
      savedUi,
      { show: Object.assign({}, HT.SHOW_DEFAULTS, savedUi && savedUi.show) }
    ),
    model: null,
    visible: [],
    selected: null,
    editing: null,
    installLog: [],
    yearPanel: null, // { year, t(구간 시작), end, prec('y'|'m'|'d'), window(년), label, cal }
    detailLens: null, // 상세 패널에서 고른 나라 관점
  };
  state.visibleFigures = []; // 필터(보이는 트랙 · 중요도)를 통과한 인물 — 연표에 넘기는 목록이자 검색 · 표 · 같은 해 보기가 도는 셋째 목록 (state.visible은 시대 + 사건)
  if (!state.ui.scopes || typeof state.ui.scopes !== 'object') state.ui.scopes = {}; // 대범위 모아 보기: { uid: true | false } — 기록이 없으면 대범위의 default (docs/구상-체제-확장.md 7-2)

  /* ---------- 날짜 글 ----------
     연표의 시간은 실수 "해 좌표"입니다 (js/calendar.js — 정수 N = N년 1월 1일). 보기 폭에 맞춰 해·달·날·시각까지 적고,
     날짜 글(startAt · endAt …)이 있으면 그 글을 씁니다. 기간은 보기 폭에 따라 해 → 개월 → 일 → 시간으로 셉니다 */
  const WEEK = '일월화수목금토';
  /** 보기 폭(년)에 맞는 자세함: 넓으면 해, 몇 해면 달, 몇 달이면 날, 며칠이면 시각 (눈금이 바뀌는 폭과 맞춤) */
  const precFor = span => (span > 12 ? 'y' : span > 0.75 ? 'm' : span > 4 / 365.25 ? 'd' : 'h');
  /** 두 시점을 한 자세함으로: "1592년 ~ 1598년" · "1592년 5월 ~ 1594년 2월" · "1592년 5월 3일 ~ 20일" (같은 해면 뒤쪽의 겹치는 앞부분은 줄임) */
  const spanRange = (a, b, prec = precFor(b - a)) => {
    const s = HT.cal.formatT(a, prec);
    let e = HT.cal.formatT(b, prec);
    if (e === s) return s;
    const ya = HT.cal.formatT(a, 'y');
    if (prec !== 'y' && HT.cal.formatT(b, 'y') === ya) {
      const ra = s.slice(ya.length + 1).split(' ');
      const rb = e.slice(ya.length + 1).split(' ');
      let i = 0;
      while (i < rb.length - 1 && ra[i] === rb[i]) i++;
      e = rb.slice(i).join(' ');
    }
    return `${s} ~ ${e}`;
  };
  /** 한 시점의 글: 맞는 날짜 글이 있으면 그 글(다른 달력은 양력 곁들임), 없으면 정수는 해, 소수(계산된 값)는 서력 날짜 */
  const whenText = (t, at) => {
    if (t == null || !isFinite(t)) return '';
    if ((at && HT.atFits(at, t)) || Number.isInteger(t)) return HT.formatDate(t, at);
    return HT.cal.formatT(t, 'd');
  };
  /** 항목이 그려지는 끝(endY)의 글: 진행 중이면 "현재", 끝이 없으면 시작 */
  const endWhen = x => (x.ongoing ? '현재' : HT.formatWhen(x, x.end != null ? 'end' : 'start'));
  /** 계산된 끝(진행 중인 정권의 끝 = 오늘)은 "현재"로 */
  const endText = t => (Math.abs(t - HT.NOW_T) < 1e-9 ? '현재' : whenText(t));
  /** 칸(지도자·내각·연호·도읍)의 기간 글 — 날짜 글까지. useEndY: 끝을 비운 칸은 풀어 둔 끝(endY, 도읍은 endYAt)으로. 칸의 미정이면 그쪽은 "미정".
      p(그 칸의 정권)를 주면 진행 중인 정권의 끝까지 가는 칸은 끝을 "현재"로 (HT.cellToNow) */
  const cellWhen = (c, useEndY = c.end == null, p = null) =>
    HT.formatRange({ start: c.start, startAt: c.startAt, end: useEndY ? c.endY : c.end, endAt: useEndY ? c.endYAt : c.endAt, startUnknown: c.startUnknown, endUnknown: c.endUnknown || (useEndY && c.endYAuto), ongoing: HT.cellToNow(c, p) });
  /** 날짜 글의 자세함 'y' · 'm' · 'd' · 'h' (글이 없거나 값과 안 맞으면 해) */
  const precOf = (x, key = 'start') => {
    const at = HT.atOf(x, key);
    const r = at ? HT.cal.parse(at) : null;
    return r && r.ok && r.prec !== 'x' ? (r.prec === 'min' ? 'h' : r.prec) : 'y';
  };
  /** 날짜 글이 음력(한국·중국)인지 — 음력으로 적은 날에는 음력 곁들임을 또 붙이지 않습니다 */
  const lunarAt = (x, key = 'start') => {
    const at = HT.atOf(x, key);
    const r = at ? HT.cal.parse(at) : null;
    return !!(r && r.ok && HT.cal.get(r.cal).lunar);
  };
  /** 그 단위(해·달·날·시)의 끝. t는 그 단위의 시작이고, 달은 그 달력의 달(음력이면 음력 달 — 29·30일)로 셉니다 */
  const unitEnd = (t, prec, calId = 'civil') => {
    if (prec === 'y') return t + 1;
    const a = HT.cal.at(t);
    if (prec === 'm') return HT.cal.tOf(HT.cal.monthStartIn(calId, HT.cal.monthStartIn(calId, a.J) + 31));
    if (prec === 'd') return HT.cal.tOf(a.J + 1);
    if (prec === 'h') return HT.cal.tOf(a.J, Math.min(1, (Math.floor(a.frac * 24 + 1e-6) + 1) / 24));
    return HT.cal.tOf(a.J, Math.min(1, a.frac + 1 / 1440));
  };
  /** t를 그 단위의 시작으로: 해 → 1월 1일, 달 → 1일, 날 → 0시 */
  const snapTo = (t, prec) => {
    if (prec === 'y') return HT.yearOf(t);
    const a = HT.cal.at(t);
    return HT.cal.tOf(prec === 'm' ? HT.cal.monthStartIn('civil', a.J) : a.J);
  };
  /** 항목이 품는 마지막 시점 — 끝(없으면 시작)의 자세함만큼: 연도만 적은 1910은 그해 끝까지, "1910-08"은 8월 끝까지, "1910-08-29"는 그날 끝까지 */
  const endIn = x => {
    if (x.ongoing) return x.endY;
    const key = x.end != null ? 'end' : 'start';
    const at = HT.atOf(x, key);
    if (!at && !Number.isInteger(x.endY)) return x.endY; // 날짜 글 없는 소수(계산된 값)는 그 점까지
    const r = at ? HT.cal.parse(at) : null;
    return r && r.ok ? unitEnd(x.endY, r.prec, r.cal) - 1e-9 : x.endY + 1 - 1e-9;
  };
  /** 그날의 곁들임: "음력 4월 13일 · 경진일 · 토요일" (음력으로 적은 날이면 음력은 빼고) */
  const dayNote = (t, withLunar = true) => {
    const a = HT.cal.at(t);
    const out = [];
    const lunar = withLunar && HT.cal.supports('dangi') ? HT.cal.formatIn('dangi', t, { year: false }) : '';
    if (lunar) out.push(lunar);
    out.push(`${HT.cal.dayGanji(a.J)}일`, `${WEEK[(((a.J + 1) % 7) + 7) % 7]}요일`);
    return out.join(' · ');
  };
  /** a에서 b까지를 달력으로 셉니다: { months, days } — a에서 months개월 뒤의 같은 날(그 달에 없으면 끝날)부터 b까지가 days(소수) */
  const calDiff = (a, b) => {
    const A = HT.cal.at(a);
    const B = HT.cal.at(b);
    const dayAfter = k => {
      const idx = A.ay * 12 + (A.m - 1) + k;
      const ay = Math.floor(idx / 12);
      const m = idx - ay * 12 + 1;
      const y = HT.cal.fromAstro(ay);
      const first = HT.cal.jdnCivil(y, m, 1);
      const next = m === 12 ? HT.cal.jdnCivil(HT.cal.fromAstro(ay + 1), 1, 1) : HT.cal.jdnCivil(y, m + 1, 1);
      return first + Math.min(A.d, next - first) - 1 + A.frac;
    };
    let months = Math.max(0, (B.ay - A.ay) * 12 + (B.m - A.m));
    while (months > 0 && dayAfter(months) > B.J + B.frac + 1e-9) months--;
    return { months, days: Math.max(0, B.J + B.frac - dayAfter(months)), total: B.J + B.frac - (A.J + A.frac) };
  };
  /** 기간 글 — 자세함에 맞춰: "1,200년" · "3년 2개월" · "3개월 12일 (104일)" · "2일 5시간" */
  const durationText = (a, b, prec = 'd') => {
    if (prec === 'y') return `${Math.round(b - a).toLocaleString()}년`;
    const { months, days, total } = calDiff(a, b);
    const parts = (mo, d, h) =>
      [mo >= 12 && `${Math.floor(mo / 12).toLocaleString()}년`, mo % 12 && `${mo % 12}개월`, d && `${d}일`, h && `${h}시간`].filter(Boolean).join(' ');
    if (prec === 'm') return parts(months + (days >= 15 ? 1 : 0), 0, 0) || '한 달 미만';
    if (prec === 'd') {
      const txt = parts(months, Math.round(days), 0) || '하루 미만';
      return months ? `${txt} (${Math.round(total).toLocaleString()}일)` : txt;
    }
    const hrs = Math.round(days * 24);
    return parts(months, Math.floor(hrs / 24), hrs % 24) || '한 시간 미만';
  };

  let saveViewTimer = 0;
  let mapHooks = null; // 지도 부품 (지도/js/viewer-map.js가 있을 때만)
  let maker = null; // 메이커 부품 (dlc-maker.html에서만 — js/maker.js). 없으면 보기 전용입니다
  let viewsUi = null; // 집합 보기 화면 (js/views-ui.js — 독 단추 · 목록 · 시대 구분 카드 · 메이커의 고른 나라 막대). 아래 메이커 부품 다음에 붙입니다
  /** 보기 전용 화면에서 편집 길을 부르면 여기서 거절합니다 (늘 false). 연표에서 메이커로 가는 길은 두지 않습니다 — 메이커 → 연표의 한 방향뿐 */
  const denyEdit = () => {
    HT.toast('연표는 보기 전용입니다.');
    return false;
  };
  let groupTree = null; // 단체 계보 창 (js/group-tree.js — 설계 D5 결정 4 A · 아래쪽 넓은 창). 연표를 만든 바로 뒤에 붙임
  /* 화면의 연표 객체는 아래에서 HT.liveTimeline에도 둡니다 — 검사 스크립트(scripts/maker-shoot.mjs)가 보기 범위 · 접힘을 맞추는 데 씀 */
  const timeline = new HT.Timeline($('#timeline'), {
    rows: 4,
    seogo: MAKE, // 서고 배치 3단(2026-10-23 · 인수인계 5-15): 메이커 미리보기만 — 내보내기(prototype/scripts/export)는 이 갈래를 켜지 않아 배치가 바이트까지 그대로
    foldedSpheres: state.ui.foldedSpheres || null,
    shelvedScopes: state.ui.shelvedScopes || [], // 선반 상태의 그릇(서고 과제 9 — 기억)
    onShelf: list => {
      state.ui.shelvedScopes = list;
      HT.store.set(K.ui, state.ui);
    }, // 접힌 문화권(서고 3단 — 새 앱 ViewState.foldedSpheres처럼 기억 · null이면 처음 접힘 규칙)
    onFoldSphere: list => {
      state.ui.foldedSpheres = list;
      HT.store.set(K.ui, state.ui);
    },
    showAlt: state.ui.showAlt !== false,
    show: Object.assign({}, HT.SHOW_DEFAULTS, state.ui.show),
    folded: state.ui.folded || [],
    foldedPeoples: state.ui.foldedPeoples || [],
    foldedEras: state.ui.foldedEras || [],
    axisOpen: state.ui.axisOpen || [],
    openCapSec: state.ui.openCapSec || [],
    expandedHosts: state.ui.expandedHosts || [],
    leaderMode: state.ui.leaderLabel || 'auto',
    leaderOrdinal: !!state.ui.leaderOrdinal,
    birdShape: state.ui.birdShape || 'a', // 조감 모양 (a 이름 + 점 · b 이름만 · c 8px 띠 · 선만)
    birdAuto: !!state.ui.birdAuto, // 가로로 많이 축소하면 저절로 조감 (기본 끔)
    onBird: on => syncBirdUi(on), // 조감에 들어가거나 나옴 — ↕ 단추의 눌림
    /* 같은 사람의 칸(건의 8의 6-나): 지도자 · 사람을 적은 내각 칸 → 그 사람의 모든 칸 [{ uid, ref }] (사람 자리 HT.personOf — 자리가 하나면 그 칸만) */
    samePerson: (uid, ref) => {
      const x = state.model && state.model.byUid.get(uid);
      const n = x ? HT.personOf(state.model, x, ref) : null;
      return n && !n.unknown ? n.cells.map(q => ({ uid: q.p.uid, ref: q.ref })) : [];
    },
    onExpand: list => {
      state.ui.expandedHosts = list;
      HT.store.set(K.ui, state.ui);
    },
    onLayout: () => state.spotKind && spotHighlight(), // 접기 · 펼치기 · 소속 펼침으로 띠가 바뀌면 조명의 사건 · 같은 시기 타국을 다시 셈 (연표의 echoBands)
    onFold: list => {
      state.ui.folded = list;
      HT.store.set(K.ui, state.ui);
      updateFoldAllBtn();
    },
    onFoldPeople: list => {
      state.ui.foldedPeoples = list;
      HT.store.set(K.ui, state.ui);
    },
    onFoldEra: list => {
      state.ui.foldedEras = list;
      HT.store.set(K.ui, state.ui);
    },
    onAxisGroup: list => {
      state.ui.axisOpen = list;
      HT.store.set(K.ui, state.ui);
    },
    onCapSec: list => {
      state.ui.openCapSec = list;
      HT.store.set(K.ui, state.ui);
    },
    lens: state.ui.lens || '',
    altCal: state.ui.altCal, // 확대했을 때 날짜 칸 아래 보조 달력 (없으면 연표의 기본값)
    onAltCal: id => {
      state.ui.altCal = id;
      HT.store.set(K.ui, state.ui);
    },
    emptyText: '표시할 트랙이 없습니다. 필터나 DLC 설정을 확인하세요.',
    onPeople: key => openWiki(key), // 민족 딱지(8-4 사)를 누르면 그 민족의 문서
    scopesOn: state.ui.scopes, // 대범위 모아 보기 (기록이 없으면 대범위의 default)
    onBoard: board => viewsUi && viewsUi.onBoard(board), // 집합 보기를 켜고 끔 (timeline.setBoard) — 독 단추 · 목록 · 시대 구분 카드를 새 상태로
    onBoardName: () => viewsUi && viewsUi.openList(), // 집합 보기 테두리의 이름표 → 판 목록
    onScope: (list, { uid, on }) => {
      state.ui.scopes[uid] = on;
      HT.store.set(K.ui, state.ui);
      syncScopeUi();
    },
    onMeasure: r => showMeasure(r),
    onSelect: (uid, year, extra) => {
      if (maker && uid && extra && extra.multi) {
        if (viewsUi) viewsUi.noteMulti(); // 연표에서 Ctrl+클릭으로 고르기 시작 — 나라 하나만 골라도 '고른 나라' 막대 (집합 보기 결정 3)
        return maker.toggleSelection(uid);
      }
      if (uid && state.editMode && state.model.byUid.has(uid)) return openEditorFor(uid); // 메이커: 누른 항목의 편집 창 (편집 창이 없는 것은 아래 상세로)
      if (uid) return openDetail(uid, extra && extra.cell ? { cell: extra.cell } : undefined);
      // 기준선은 누른 자리 그대로 (연표가 알려 주는 해는 반올림한 정수라) — 확대 정도에 따라 그 해·달·날
      if (state.yearPanel) return openYearPanel(lastPointerX != null ? timeline.yearAtClientX(lastPointerX) : year, null, { prec: panelPrec() });
      if (maker) return maker.clearSelection(); // 빈 곳을 누르면 선택 해제 — 고치던 글은 닫기 확인을 거쳐 보존
      closeDetail();
    },
    onViewChange: v => {
      const vr = $('#viewRange');
      vr.textContent = spanRange(v.start, v.end);
      vr.title = `지금 보고 있는 시기 · 폭 ${HT.cal.spanText(v.end - v.start)}`;
      if (mapHooks) mapHooks.onView(v);
      if (groupTree) groupTree.sync(); // 단체 계보 창의 연도 눈금은 연표와 같은 x — 연표를 밀거나 당기면 나무도 함께
      clearTimeout(saveViewTimer);
      saveViewTimer = setTimeout(() => HT.store.set(K.view, v), 400);
    },
  });

  HT.liveTimeline = timeline; // 검사 스크립트(scripts/maker-shoot.mjs · seogo-check.mjs)가 보기 범위 · 그릇 상태를 맞추는 데 씀
  /* 단체 계보 창(설계 D5 결정 4 A): 연표 아래쪽에 붙는 넓은 창 — 막대를 누르면 위 연표에 조명, 두 번 누르거나 [단체 창]이면 그 단체 창, 이음선은 그 일의 사건 창.
     상세 창과 함께 열려 있을 수 있고(상세 창 · 확대 단추는 창 위로 비킴 — css .stage.has-gtree), Esc는 상세 창부터 닫습니다 */
  groupTree = HT.groupTree ? HT.groupTree.mount({ timeline, stage: $('#stage'), model: () => state.model, openItem: uid => openDetail(uid), openPolity: uid => openDetail(uid) }) : null;
  /** 단체 계보 창 열기 — 단체 창에서는 그 단체를 고른 채로(그 단체가 있던 나라의 단체들), 나라 상세에서는 그 나라의 단체들 */
  const openGroupTree = x => groupTree && (x.kind === 'group' ? groupTree.open({ groupUid: x.uid, polityUid: x.polityUid || null }) : groupTree.open({ polityUid: x.uid }));

  /* 연표를 누른 자리 (기준선을 그 자리 그대로 옮기려고) */
  let lastPointerX = null;
  $('#timeline').addEventListener('pointerup', e => (lastPointerX = e.clientX), true);

  /* ---------- 날짜로 이동 ---------- */
  /** 한 시점으로 갈 때의 보기 폭: 지금 폭을 그 자세함에 맞는 범위 안으로 — 해 1.6~yearMax년 · 달 1.5개월~2년 · 날 4일~2개월 · 시각 6시간~4일 */
  const JUMP_SPAN = { m: [1.5 / 12, 2], d: [4 / 365.25, 2 / 12], h: [0.25 / 365.25, 4 / 365.25] };
  const jumpSpan = (prec, yearMax = 200) => {
    const [lo, hi] = prec === 'y' ? [1.6, yearMax] : JUMP_SPAN[prec] || JUMP_SPAN.h;
    return HT.clamp(timeline.span(), lo, hi);
  };
  /** t(그 단위의 시작)로 이동: 그 해·달·날이 화면 가운데(상세 창이 열려 있으면 창이 가리지 않은 부분의 가운데) 오게 하고 기준선을 t에 */
  function goToDate(t, prec = 'y', { end = null, yearMax = 200, calId = 'civil' } = {}) {
    const b = end != null ? end : unitEnd(t, prec, calId);
    const span = jumpSpan(prec, yearMax);
    const c = (t + b) / 2;
    timeline.setView(c - span / 2, c + span / 2, { animate: true, inset: 'center' }); // 폭은 지금 그대로, 가운데만
    timeline.setMarker(t);
  }
  /** 확대 정도에 맞는 기준 단위 (같은 해 보기 · 우클릭): 두 달보다 좁으면 날, 2년보다 좁으면 달, 아니면 해 */
  const panelPrec = () => {
    const s = timeline.span();
    return s < 2 / 12 ? 'd' : s < 2 ? 'm' : 'y';
  };
  /** 새 항목의 시작: 2년보다 좁게 확대했으면 그날(날짜 글과 함께), 아니면 그 해 */
  const presetAt = t => {
    if (timeline.span() >= 2) return { start: HT.yearOf(t) };
    const a = HT.cal.at(t);
    const r = HT.cal.build({ y: a.y, m: a.m, d: a.d });
    return r.ok ? { start: r.t, startAt: r.text } : { start: HT.yearOf(t) };
  };

  /* ---------- 팩 & 모델 ---------- */
  const isEnabled = id => !state.packState[id] || state.packState[id].enabled !== false;
  const packById = id => state.packs.find(p => p.id === id);
  const trackOf = id => state.model.trackMap.get(id) || { id, name: id, color: '#8b8f98' };

  function loadPacks() {
    state.packs = HT.loadPacks();
  }

  function refresh() {
    const enabled = state.packs.filter(p => isEnabled(p.id));
    /* 연표: 켜져 있는 DLC 그대로 (반영 전의 작업본은 보이지 않음). 메이커: 켜져 있는 다른 DLC + 고치는 DLC(작업본) — 같은 id의 설치본은 작업본이 대신합니다 */
    state.model = maker ? maker.buildModel(state.packs) : HT.buildModel(enabled, state.legacyUser); // 메이커: 고치는 DLC + 불러온 팩(ht.maker.refs) — 켜고 끔은 보지 않음
    $('#packSummary').textContent = enabled.length ? enabled.map(p => p.name).join(' · ') : '켜진 DLC가 없습니다';
    renderChips();
    fillLeaderModes(); // 지도자 표기 고르기의 선택지 글 — 이 모델이 쓰는 표기 낱말로(6단계 D3)
    syncNamesUi(); // '표기' 무리 · 왼쪽 칸 원어 (10건 3 — 자료에 이름 목록 · 글꼴이 있을 때만 무리가 보임)
    applyFonts(); // 글꼴 팩 (10건 9 — 켜진 글꼴이 없으면 아무것도 건드리지 않음)
    if (!$('#legend').hidden) renderLegend(); // 범례는 지금 자료에 쓰인 종류만 보여 주므로, 열려 있으면 자료가 바뀔 때 다시 그립니다
    if (HT.yearCycleUi(state.ui, state.model) && $('#ganjiToggle')) $('#ganjiToggle').checked = state.ui.show.ganji !== false; // 간지 줄(형식 3 — 설계 6 결정 8 B): DLC가 끈 순환(yearCycle: false)은 처음 볼 때 한 번만 끔 · 다시 켜는 것은 보는 사람(필터 '간지')
    timeline.setYearCycle(state.model.yearCycle, state.ui.show.ganji !== false); // 간지 설정 · 간지 줄 표시 — 날짜 칸은 아래 applyFilters(setData)가 다시 지음
    applyFilters();
    if (mapHooks) mapHooks.onModel();
    if (groupTree) groupTree.refresh(); // 단체 계보 창: 새 모델로 같은 나라 · 같은 단체 (없어졌으면 닫음)
    if (state.selected) {
      if (detailTarget(state.selected)) openDetail(state.selected, state.detailKind === 'succession' ? { cell: 'succession' } : undefined); // 가문 창('house:id')도 새 모델로 다시 · 승계표는 승계표로(접힘은 기억에서)
      else closeDetail();
    }
    refreshFamily();
    if (viewsUi) viewsUi.sync(); // 집합 보기: 켠 판을 새 자료로 맞춤 (처음이면 기억한 판을 되살림)
  }
  /** 지도자 표기 고르기(필터 바 · 메이커)의 선택지 — 이름은 지금 모델이 쓰는 표기 낱말(6단계 D3 · HT.leaderModes — 문화권 · 팩의 leaderLabels, 비우면 묘호 · 시호 · 이름).
      글이 그대로면 손대지 않고, 고른 값은 지킵니다 */
  function fillLeaderModes() {
    const sel = $('#leaderLabelSelect');
    if (!sel) return;
    const html = HT.leaderModes(state.model).map(o => `<option value="${o.id}">${esc(o.name)}</option>`).join('');
    if (sel.dataset.modes === html) return;
    sel.dataset.modes = html;
    sel.innerHTML = html;
    sel.value = state.ui.leaderLabel || 'auto';
  }
  /** 세계표 창이 열려 있으면 새 모델로 다시 (메이커가 모델을 다시 지으면 뼈대도 새로 — 접힘 · 창 자리는 기억에서) */
  function refreshFamily() {
    const fc = HT.kinView && HT.kinView.current();
    if (!fc) return;
    const h = fc.house ? state.model.houseMap && state.model.houseMap.get(fc.house.id) : null;
    const keep = { focusKey: fc.focusedKey(), scroll: fc.scroll(), scale: fc.scale ? fc.scale() : 0, focusTree: false, again: true }; // 고치던 칸의 초점 · 보기 단계는 그대로
    if (h && KV()) openFamily(h, keep);
    else if (!(!fc.house && /^kin:polity:/.test(fc.key || '') && openFamilyKey(fc.key, keep))) HT.kinView.closeFamily(); // 가문 없는 나라의 세계표도 새 모델로
  }

  function applyFilters() {
    const { model: m, ui } = state;
    let tracks = m.tracks.filter(t => ui.tracks[t.id] !== false);
    const ids = new Set(tracks.map(t => t.id));
    const hsOff = historicityOff();
    const hsShown = p => p.kind !== 'period' || !hsOff.has(HT.historicityOf(p) || 'attested');
    const hide = maker ? maker.hiddenPacks() : null; // 메이커: 불러온 팩 가운데 눈을 끈 것 (모델에는 남아 덮어쓰기 · 참조가 풀림)
    const shownPack = x => !hide || !hide.has(x.packId);
    const periods = m.periods.filter(p => ids.has(p.track) && ui.kinds[p.polityKind || 'state'] !== false && hsShown(p) && shownPack(p));
    const hiddenPolities = new Set(m.periods.filter(p => ui.kinds[p.polityKind || 'state'] === false || !hsShown(p)).map(p => p.uid));
    const events = m.events.filter(
      e => ids.has(e.track) && ui.categories[e.category] !== false && (e.importance || 2) >= ui.minImportance && !(e.polityUid && hiddenPolities.has(e.polityUid)) && shownPack(e)
    );
    state.visible = periods.concat(events);
    /* 인물: 보이는 트랙의 사람만, 중요도 필터를 따릅니다 (섬긴 정권이 종류 칩으로 꺼져 있으면 연표가 그 막대를 그리지 않습니다) */
    const figures = (state.visibleFigures = (m.figures || []).filter(f => ids.has(f.track) && (f.importance || 2) >= ui.minImportance && shownPack(f)));
    const epochs = (m.epochs || []).filter(e => (!e.track || ids.has(e.track)) && shownPack(e));
    const scopes = (m.scopes || []).filter(s => ids.has(s.track) && shownPack(s));
    if (hide && hide.size) {
      /* 눈을 끈 팩만 쓰던 트랙은 빈 줄로 남지 않게 — 작업본에 적힌 트랙은 비어도 둠(항목을 넣을 자리) */
      const used = new Set(periods.concat(events, figures, epochs, scopes).map(x => x.track).concat(maker.ownTrackIds()));
      tracks = tracks.filter(t => used.has(t.id));
    }
    /* 서고 3단의 처음 펴 둘 문화권: 고치는 DLC의 첫 트랙이 든 문화권(없으면 첫 트랙의 것) — 새 앱의 '첫 DLC가 처음 말한 트랙의 문화권'과 같은 뜻 */
    const ownIds = maker ? new Set(maker.ownTrackIds()) : null;
    const firstOwn = (ownIds && tracks.find(t => ownIds.has(t.id))) || tracks[0];
    timeline.setData({ tracks, periods, events, epochs, categories: m.categories, figures, scopes, f4: MAKE ? HT.f4Preview(m, maker && maker.draft ? maker.draft : null) : null, spheres: m.spheres || [], defaultSphere: firstOwn ? firstOwn.sphere || null : null, houseMap: m.houseMap || null, unions: HT.unionPairs ? HT.unionPairs(m) : [] }); // spheres — 문화권 머리 단(서고 3단 · 메이커만) · houseMap — 성씨 풍선의 성씨 · 본관 · 본가 길(W3 이음새)
    runSearch();
    updateFoldAllBtn();
    HT.store.set(K.ui, ui);
  }

  const filtersActive = () =>
    Object.values(state.ui.tracks).includes(false) || Object.values(state.ui.categories).includes(false) || Object.values(state.ui.kinds).includes(false) || historicityOff().size > 0 || state.ui.minImportance > 1;
  const kindsUsed = () => {
    const used = new Set(state.model.periods.map(p => p.polityKind || 'state'));
    return HT.ALL_KINDS.filter(k => used.has(k.id)).map(k => ({ id: k.id, name: k.name, color: '#a4b1b7' }));
  };
  /* 실재성 칩 줄 (8-4 마): 자료에 실재성이 쓰였을 때만 보이고, 끄면 그 나라와 딸린 사건을 숨깁니다 — 종류 칩과 같은 방식 (저장된 설정에 없으면 모두 켬) */
  if (!state.ui.historicity || typeof state.ui.historicity !== 'object') state.ui.historicity = {};
  const historicityUsed = () => {
    const used = new Set(state.model.periods.map(p => HT.historicityOf(p) || 'attested'));
    return used.size > 1 || !used.has('attested') ? HT.HISTORICITY.filter(h => used.has(h.id)).map(h => ({ id: h.id, name: h.name, color: '#a4b1b7' })) : [];
  };
  /** 꺼 둔 실재성 — 지금 칩 줄에 보이는 것만 셉니다. 실재성을 쓰던 DLC를 꺼서 칩 줄이 사라졌는데 저장된 "실재 끔"이 남아
      다시 켤 칩도 없이 나라가 모두 숨는 일이 없게 (저장된 값은 지우지 않아 그 DLC를 다시 켜면 꺼 둔 대로) */
  const historicityOff = () => new Set(historicityUsed().filter(h => state.ui.historicity[h.id] === false).map(h => h.id));

  function updateFoldAllBtn() {
    const b = $('#foldAllBtn');
    if (!b) return;
    const all = timeline.allFolded();
    b.innerHTML = `${icon('fold')}${all ? '모두 펴기' : '모두 접기'}`;
    b.disabled = !state.model || !state.model.tracks.length;
  }

  /* ---------- 필터 ---------- */
  const chip = (group, x, on) =>
    `<button type="button" class="chip" data-group="${group}" data-id="${esc(x.id)}" aria-pressed="${on}" style="--c:${x.color}" title="클릭: 켜기/끄기 · Alt+클릭: 이것만 보기">${esc(x.name)}</button>`;

  function renderChips() {
    const m = state.model;
    const lensSel = $('#lensSelect');
    const want = state.ui.lens || '';
    lensSel.innerHTML = '<option value="">기본</option><option value="local">나라마다 제 이름</option>' +
      m.tracks.map(t => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join(''); // 머리 '관점'은 고르기 앞에 한 번 (index.html — 이름만 쓰기)
    lensSel.value = [...lensSel.options].some(o => o.value === want) ? want : '';
    const used = new Set(m.events.map(e => e.category));
    $('#trackChips').innerHTML = m.tracks.map(t => chip('tracks', t, state.ui.tracks[t.id] !== false)).join('');
    $('#categoryChips').innerHTML = m.categories.filter(c => used.has(c.id)).map(c => chip('categories', c, state.ui.categories[c.id] !== false)).join('');
    const kinds = kindsUsed();
    $('#kindGroup').hidden = kinds.length < 2;
    $('#kindChips').innerHTML = kinds.map(k => chip('kinds', k, state.ui.kinds[k.id] !== false)).join('');
    const hss = historicityUsed();
    if ($('#historicityGroup')) {
      $('#historicityGroup').hidden = !hss.length;
      $('#historicityChips').innerHTML = hss.map(h => chip('historicity', h, state.ui.historicity[h.id] !== false)).join('');
    }
    renderScopeChips();
  }
  /* 대범위 칩 줄 (7-4): 트랙별로 · 누르면 모아 보기를 켜고 끕니다(거르기가 아님 — 칩 위임의 맨 앞에서 갈라 timeline.toggleScope만) */
  function renderScopeChips() {
    const box = $('#scopeChips');
    if (!box) return;
    const m = state.model;
    const list = (m.scopes || []).filter(s => state.ui.tracks[s.track] !== false);
    $('#scopeGroup').hidden = !list.length;
    const byTrack = new Map();
    for (const s of list) byTrack.set(s.track, (byTrack.get(s.track) || []).concat([s]));
    box.innerHTML = [...byTrack]
      .map(([tid, ss]) => {
        const t = trackOf(tid);
        return `<span class="scope-chips-track" style="--c:${t.color}">${esc(t.name)}</span>${ss
          .map(s => `<button type="button" class="chip" data-group="scopes" data-id="${esc(s.uid)}" aria-pressed="${timeline.scopeOn(s)}" style="--c:${s.color}" title="${esc(`${s.name}${s.label ? ` · ${s.label}` : ''} — 누르면 모아 보기 ${timeline.scopeOn(s) ? '끄기' : '켜기'} (구성 정권 ${s.members.length}곳)`)}">${esc(s.name)}</button>`)
          .join('')}`;
      })
      .join('');
  }
  /** 대범위를 켜고 끈 뒤: 칩 줄과, 열려 있는 상세의 스위치(대범위 · 시대 구분 · 정권)를 새 상태로 */
  function syncScopeUi() {
    renderScopeChips();
    const x = state.selected && !state.yearPanel ? state.model.byUid.get(state.selected) : null;
    if (x && (x.kind === 'scope' || x.kind === 'epoch' || x.scopes || x.hostedScopes)) openDetail(state.selected, state.cell ? { cell: state.cell } : {});
    syncEditorScope(); // 메이커: 편집 창 맨 위의 스위치도
  }

  $('.filterbar').addEventListener('click', e => {
    const b = e.target.closest('.chip');
    if (!b) return;
    const group = b.dataset.group;
    if (group === 'scopes') {
      /* 대범위: 거르기가 아니라 모아 보기 — 시트를 먼저 접어(--t-out) 모여드는 주연을 가리지 않게 한 뒤에 켜고 끕니다 */
      setFilterBar(false);
      HT.motion.later(HT.motion.T.out, () => timeline.toggleScope(b.dataset.id));
      return;
    }
    const map = state.ui[group];
    const id = b.dataset.id;
    if (e.altKey) {
      const all = group === 'tracks' ? state.model.tracks : group === 'kinds' ? kindsUsed() : group === 'historicity' ? historicityUsed() : state.model.categories;
      all.forEach(x => (map[x.id] = x.id === id));
    } else {
      map[id] = map[id] === false;
    }
    renderChips();
    applyFilters();
  });
  $('#importanceSelect').addEventListener('change', e => {
    state.ui.minImportance = Number(e.target.value);
    applyFilters();
  });
  /* 밀도: 넉넉하게 · 자동 · 빽빽하게 · 조감(건의 1 — 세로를 극단적으로 줄여 한눈에). 조감 ↔ 직전 밀도는 ↕ 단추와 V 키로도 (ui.birdFrom).
     조감 모양(a 이름 + 점 · b 이름만 · c 띠 · 선만)과 '축소하면 조감'(자동 — 기본 끔)은 필터 바에서. 밀도가 바뀌면 줄이 한 시계로 흐릅니다 (timeline _squash) */
  function setDensity(v) {
    v = [-1, 0, 1, 2].includes(Number(v)) ? Number(v) : 0;
    if (v === 2 && state.ui.density !== 2) state.ui.birdFrom = state.ui.density || 0;
    state.ui.density = v;
    $('#densitySelect').value = String(v);
    timeline.setDensity(v);
    applyFilters();
  }
  /** ↕ · V: 조감이 아니면 조감으로, 밀도 조감이면 직전 밀도로, 자동 조감이면 풀기(보기가 문턱 아래로 좁아질 때까지 자동으로 다시 들어가지 않음) */
  function toggleBird() {
    if (!timeline.isBird()) return setDensity(2);
    if (state.ui.density === 2) return setDensity(state.ui.birdFrom ?? 0);
    timeline.leaveAutoBird();
  }
  function syncBirdUi(on = timeline.isBird()) {
    const b = $('#birdBtn');
    if (!b) return;
    b.setAttribute('aria-pressed', String(on));
    b.title = on ? '조감 풀기 (V)' : '조감 (V)';
  }
  $('#densitySelect').addEventListener('change', e => setDensity(e.target.value));
  $('#birdShapeSelect').addEventListener('change', e => {
    state.ui.birdShape = e.target.value;
    timeline.setBird({ shape: state.ui.birdShape });
    if (timeline.isBird()) applyFilters();
    else HT.store.set(K.ui, state.ui);
  });
  $('#birdAutoToggle').addEventListener('change', e => {
    state.ui.birdAuto = e.target.checked;
    timeline.setBird({ auto: state.ui.birdAuto });
    applyFilters();
  });

  /* ---------- 검색 ---------- */
  const searchInput = $('#searchInput');
  const resultsEl = $('#searchResults');
  const YEAR_ONLY = /^\s*(?:기원전|BC|B\.C\.)?\s*-?\d{1,5}\s*년?\s*$/i;
  /* 날짜로 읽어 볼 검색어: 연도만, 또는 세 자리 이상 수·"년"·기원전이 든 것 ("3.1"처럼 짧은 수는 이름으로 찾습니다) */
  const DATE_HINT = /\d{3}|년|기원전|서기전|B\.?\s?C/i;
  /** 검색어가 날짜 하나뿐이면 { t, end, prec, cal, label } — "1592" · "1592년 5월" · "1592-05-23" · "음력 1592-04-13" */
  function dateQuery(q) {
    if (!HT.cal || !(YEAR_ONLY.test(q) || DATE_HINT.test(q))) return null;
    const r = HT.cal.parse(q);
    if (!r || !r.ok || r.prec === 'x') return null;
    const label = r.cal !== 'civil' ? HT.cal.describe(r) : r.prec === 'y' ? HT.formatYear(r.t) : HT.cal.formatT(r.t, r.prec);
    return { t: r.t, end: unitEnd(r.t, r.prec, r.cal), prec: r.prec, cal: r.cal, label };
  }
  const GANJI_ONLY = /^\s*([갑을병정무기경신임계][자축인묘진사오미신유술해])\s*년?\s*$/;
  let results = []; // { type:'item'|'cell'|'ganji', ... }
  let activeIndex = -1;
  /* 연표의 강조는 나중에 건 쪽이 가집니다: 검색어 입력(input)이 'search', 창 열기(openDetail)가 'spot' — spotHighlight 위 글 */
  let hiOwner = 'spot';
  /** 지금 강조를 검색이 가지는가 — 검색어가 있고, 조명 강조를 거는 창이 없거나 그 창이 열린 뒤에 검색어를 고쳤을 때 */
  const searchOwns = () => !!searchInput.value.trim() && (hiOwner === 'search' || !state.spotKind);

  function runSearch() {
    const q = searchInput.value.trim();
    if (!q) {
      results = [];
      resultsEl.hidden = true;
      spotHighlight(); // 검색어가 없으면 열린 창의 조명 강조(없으면 끔) — 필터를 바꿔도 창의 강조가 지워지지 않게
      return;
    }
    const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
    const dq = dateQuery(q); // 날짜 검색: 그 해·달·날에 걸친 항목 (연도만 적은 항목은 그해 전체에 걸친 것으로)
    const ganji = (q.match(GANJI_ONLY) || [])[1] || '';
    const hit = s => terms.every(t => String(s).toLowerCase().includes(t));
    const items = state.visible
      .filter(x => {
        if (!x._hay)
          x._hay = [
            x.title || x.name, x.description, (x.tags || []).join(' '), x.date, trackOf(x.track).name,
            (x.perspectives || []).map(v => `${v.title || ''} ${v.description || ''}`).join(' '),
            x.peopleName || x.people || '', x.polityKind && x.polityKind !== 'state' ? HT.kindName(x.polityKind) : '', x.partOfName || '',
            treatyHay(x), // 조약: 정식 명칭 · 장소 · 당사국 · 서명자 · 조항 제목
            HT.historicityOf(x) ? HT.historicityName(HT.historicityOf(x)) : '', x.historicityNote || '', // 실재성 (8-4 마)
            HT.namesText(x.names), x.place || '', // 이름 목록 · 사건의 장소 (형식 버전 3 — 원어 · 로마자 · 옛 이름으로도)
          ].join(' ').toLowerCase();
        return terms.every(t => x._hay.includes(t)) || (!!dq && !x.startUnknown && x.start < dq.end && endIn(x) >= dq.t);
      })
      .sort((a, b) => a.start - b.start)
      .map(x => ({ type: 'item', x, start: x.start }));
    /* 인물: 이름 · 다른 이름 · 역할 · 직함 · 섬긴 정권 · 가문 · 설명 · 태그로 찾습니다 (날짜 검색이면 그때 살아 있었거나 활동한 사람) */
    for (const f of state.visibleFigures) {
      if (!f._hay) f._hay = [f.name, (f.aka || []).join(' '), f.role, f.house, f.description, (f.tags || []).join(' '), trackOf(f.track).name, (f.services || []).map(s => `${s.polityName || ''} ${s.office || ''} ${s.note || ''}`).join(' '), HT.namesText(f.names)].join(' ').toLowerCase();
      if (terms.every(t => f._hay.includes(t)) || (!!dq && f.spanMin < dq.end && f.spanMax + 1 > dq.t)) items.push({ type: 'item', x: f, start: f.start });
    }
    items.sort((a, b) => a.start - b.start);
    /* 계보 전용 인물(D1 — 띠에 놓이지 않는 사람): 사람 결과로 — 곁글 '계보 전용 · ○○파', 해 칸은 비움. 띠에 그림이 없어 연표 강조에는 넣지 않고 날짜 검색에도 들지 않음 */
    const kinHits = [];
    if (!dq && !ganji)
      for (const f of state.model.lineageFigures || []) {
        if (state.ui.tracks[f.track] === false) continue;
        if (!f._hay) f._hay = [f.name, (f.aka || []).join(' '), f.role, f.description, (f.tags || []).join(' '), trackOf(f.track).name, HT.namesText(f.names), kinFigureHouse(f) ? kinFigureHouse(f).name : ''].join(' ').toLowerCase();
        if (terms.every(t => f._hay.includes(t))) kinHits.push({ type: 'kin', x: f, start: Infinity });
      }
    /* 지도자·내각·연호·도읍 이름으로도 찾습니다 (칸 종류 표 HT.CELL_KINDS의 모든 종류 — 고르면 그 칸의 상세와 기간 조명) */
    const cells = [];
    if (!dq && !ganji) {
      for (const x of state.visible) {
        if (x.kind !== 'period') continue;
        for (const K of HT.CELL_KINDS) {
          HT.cellsOf(x, K).forEach((c, i) => {
            if (hit(`${c.name} ${c.temple || ''} ${c.title || ''} ${c.given || ''} ${c.city || ''} ${c.label || ''} ${c.group || ''} ${c.note || ''} ${HT.namesText(c.names)}${K.id === 'capital' ? ` ${HT.namesText((HT.placeOf(state.model, c.placeId || c.city) || {}).names)}` : ''}`)) cells.push({ type: 'cell', x, c, K, i, start: c.start }); // 칸의 이름 목록 · 도읍 지명의 원어도 (형식 버전 3)
          });
        }
      }
      cells.sort((a, b) => a.start - b.start);
    }
    /* 간지로 찾기: 그 간지에 해당하는 해들 (보고 있는 시기에 가까운 순) */
    const years = [];
    if (ganji) {
      const { min, max } = timeline.extent;
      const center = (timeline.view.start + timeline.view.end) / 2;
      for (let y = Math.floor(min) - 60; y <= max + 60; y++) if (y !== 0 && HT.ganji(y) === ganji) years.push({ type: 'ganji', year: y, start: y, ganji });
      years.sort((a, b) => Math.abs(a.year - center) - Math.abs(b.year - center));
    }
    /* 시대 구분 · 하위 문서 제목으로도 찾습니다 */
    if (!dq && !ganji) {
      for (const ep of state.model.epochs) if (hit(`${ep.name} ${ep.note || ''} ${ep.trackName || ''}`)) items.push({ type: 'item', x: ep, start: ep.start });
      for (const s of state.model.scopes || []) if (state.ui.tracks[s.track] !== false && hit(`${s.name} ${s.label || ''} ${s.note || ''} ${s.description || ''} ${s.trackName || ''} 대범위 ${s.members.map(m => m.name).join(' ')}`)) items.push({ type: 'item', x: s, start: s.start }); // 대범위 (7-4)
      for (const k of allDocKeys()) {
        if (!k.includes('//')) continue;
        const info = docInfo(k);
        if (info && hit(info.title)) cells.push({ type: 'doc', key: k, title: info.title, start: Infinity });
      }
    }
    /* 가문 이름 · 성 · 본관 · 시조로도 찾습니다 (고르면 가문 창 — 가문은 제 줄이 없어 연표를 옮기지 않음) */
    if (!dq && !ganji) for (const h of state.model.houses || []) if (hit(`${h.name} ${h.surname} ${h.seat} ${h.founder} ${h.description} ${HT.namesText(h.names)} ${HT.namesText(((state.model.surnameMap && state.model.surnameMap.get(h.surnameId)) || {}).names)}`)) cells.push({ type: 'house', h, start: Infinity }); // 가문 · 성씨의 이름 목록도 (형식 버전 3)
    /* 단체 · 제도 (형식 버전 3): 이름 · 종류 · 있던 나라 · 구성 나라 · 구성원 · 갈래 · 칸 이름으로 (고르면 그 창 — 제 줄이 없어 연표의 강조에는 넣지 않음) */
    if (!dq && !ganji) {
      for (const g of state.model.groups || []) if (state.ui.tracks[g.track] !== false && hit(`${g.name} ${g.typeName || ''} 단체 ${g.description || ''} ${g.note || ''} ${(g.withinList || []).concat(g.memberList || []).map(r => r.name).join(' ')} ${(g.peopleList || []).map(r => `${r.name} ${r.person ? r.person.name : ''}`).join(' ')} ${HT.namesText(g.names)}`)) cells.push({ type: 'lens', it: g, start: Infinity });
      for (const it of state.model.institutions || []) if (state.ui.tracks[it.track] !== false && hit(`${it.name} 제도 ${it.family || ''} ${it.description || ''} ${(it.spanList || []).map(sp => `${sp.name} ${sp.note || ''}`).join(' ')} ${HT.namesText(it.names)} ${HT.namesText((((state.model.themeMap && state.model.themeMap.get(it.themeId)) || {}).names))}`)) cells.push({ type: 'lens', it, start: Infinity });
    }
    results = years.concat(items, kinHits, cells);
    const hi = new Set(items.map(r => r.x.uid).concat(cells.filter(r => r.x).map(r => r.x.uid)));
    if (searchOwns()) timeline.setHighlight(hi.size ? hi : null); // 창이 열린 뒤에 검색했으면 검색 강조 — 열린 창의 조명 강조는 검색어를 비우거나 창을 닫으면 되살아남
    if (state.spotKind) spotHighlight(); // 창의 '같은 시기 타국' 묶음은 새 필터로 다시 셈 (강조는 나중에 건 쪽 — searchOwns)
    renderResults(dq, ganji);
  }

  function renderResults(dq, ganji) {
    if (document.activeElement !== searchInput) return;
    const top = results.slice(0, 60);
    let html = '';
    if (dq) {
      // 날짜로 이동: 날까지 적었으면 그날의 음력·일진·요일을 곁들입니다
      const day = dq.prec !== 'y' && dq.prec !== 'm' ? dayNote(dq.t, !HT.cal.get(dq.cal).lunar) : '';
      html += `<button type="button" data-year="${dq.t}" data-end="${dq.end}" data-prec="${dq.prec}" data-cal="${esc(dq.cal)}" data-label="${esc(dq.label)}">${icon('pin', 'sr-ic')}<span class="sr-title">${esc(dq.label)}(으)로 이동</span>${day ? `<span class="sr-when">${esc(day)}</span>` : ''}</button>`;
    }
    const n = results.length;
    const meta = n ? `${n}건 찾음${n > top.length ? ` (앞의 ${top.length}건만 표시)` : ''}` : '일치하는 항목이 없습니다';
    html += `<div class="sr-meta">${meta}${ganji ? ` · ${esc(ganji)}년은 60년마다 돌아옵니다. 보고 있는 시기에 가까운 해부터 보여 줍니다` : ''}${filtersActive() ? ' · 필터로 숨긴 항목은 검색되지 않습니다' : ''}</div>`;
    html += top
      .map(r => {
        if (r.type === 'doc') return `<button type="button" data-doc="${esc(r.key)}">${icon('file', 'sr-ic')}<span class="sr-title">${esc(r.title)}</span><span class="sr-when">하위 문서</span></button>`;
        if (r.type === 'house') return `<button type="button" data-uid="${esc(r.h.uid)}"><span class="sr-dot" style="--c:${r.h.color}"></span><span class="sr-title">${esc(r.h.name)} <small>가문${r.h.surname ? ` · 성 ${esc(surnameText(r.h))}` : ''}${r.h.seat ? ` · 본관 ${esc(r.h.seat)}` : ''}</small></span><span class="sr-when">구성원 ${r.h.members.filter(mb => mb.role !== 'period').length}</span></button>`; // 가문 창과 같은 셈 — 국성으로 삼은 나라는 구성원이 아님
        if (r.type === 'lens') {
          const x = r.it;
          const sub = x.kind === 'group' ? `단체${x.typeName ? ` · ${esc(x.typeName)}` : ''}` : `제도${x.family ? ` · ${esc(x.family)}` : ''}`;
          return `<button type="button" data-uid="${esc(x.uid)}"><span class="sr-dot" style="--c:${x.color}"></span><span class="sr-title">${esc(x.name)} <small>${sub}</small></span><span class="sr-when">${esc(x.kind === 'group' ? HT.formatRange(x) : spanText({ start: x.start, end: x.endY }))} · ${esc(trackOf(x.track).name)}</span></button>`;
        }
        if (r.type === 'kin') {
          const h = kinFigureHouse(r.x);
          return `<button type="button" data-uid="${esc(r.x.uid)}" data-kin-only><span class="sr-dot is-figure" style="--c:${h ? h.color : r.x.color || trackOf(r.x.track).color}"></span><span class="sr-title">${esc(r.x.name)} <small>${esc(h ? `계보 전용 · ${h.name}` : '계보 전용')}</small></span><span class="sr-when"></span></button>`;
        }
        if (r.type === 'ganji') return `<button type="button" data-year="${r.year}"><span class="sr-dot" style="--c:var(--warn)"></span><span class="sr-title">${esc(HT.formatYear(r.year))} <small>${esc(r.ganji)}년</small></span><span class="sr-when">그 해로 이동</span></button>`;
        if (r.type === 'cell') {
          const color = r.x.color || trackOf(r.x.track).color;
          const cname = r.K.full ? r.K.full(r.c) : r.K.title(r.c);
          return `<button type="button" data-uid="${esc(r.x.uid)}" data-year="${r.c.start}" data-prec="${precOf(r.c)}" data-cell="${esc(`${r.K.id}:${r.i}`)}"><span class="sr-dot is-cell" style="--c:${color}"></span><span class="sr-title">${esc(cname)} <small>${esc(r.x.name)} ${esc(r.K.name)}${r.c.note ? ` · ${esc(r.c.note)}` : ''}</small></span><span class="sr-when">${esc(cellWhen(r.c, undefined, r.x))} · ${esc(trackOf(r.x.track).name)}</span></button>`;
        }
        const x = r.x;
        const color = x.polityColor || x.color || trackOf(x.track).color;
        if (x.kind === 'figure') return `<button type="button" data-uid="${esc(x.uid)}"><span class="sr-dot is-figure" style="--c:${color}"></span><span class="sr-title">${esc(x.name)} <small>인물${x.role ? ` · ${esc(x.role)}` : ''}${x.polityName ? ` · ${esc(x.polityName)}` : ''}${x.houseName ? ` · 가문 ${esc(x.houseName)}` : ''}</small></span><span class="sr-when">${esc(HT.figureLife(x) || HT.formatRange(x))} · ${esc(trackOf(x.track).name)}</span></button>`;
        return `<button type="button" data-uid="${esc(x.uid)}"><span class="sr-dot${x.kind === 'period' ? ' is-period' : ''}${x.treaty ? ' is-treaty' : ''}" style="--c:${color}"></span><span class="sr-title">${esc(x.title || x.name)}</span><span class="sr-when">${esc(HT.formatRange(x))} · ${esc(trackOf(x.track).name)}</span></button>`;
      })
      .join('');
    resultsEl.innerHTML = html;
    resultsEl.hidden = false;
    activeIndex = -1;
  }

  function activateResult(b) {
    if (b.dataset.doc) openWiki(b.dataset.doc);
    else if (b.dataset.cell) {
      // 지도자·내각·연호·도읍: 그 칸의 상세를 열고(띠 안에 그 기간이 조명됨) 그 시기로 이동
      const item = state.model.byUid.get(b.dataset.uid);
      if (item) openDetail(item.uid, { cell: b.dataset.cell });
      goToDate(Number(b.dataset.year), b.dataset.prec || 'y', { yearMax: 120 });
    } else if (b.dataset.year) {
      // 해·간지·날짜: 그 해(달·날)로 가서 그때 무슨 일이 있었는지 봅니다. 시각까지 적었으면 그날을 기준으로
      const t = Number(b.dataset.year);
      const prec = b.dataset.prec || 'y';
      const cal = b.dataset.cal || 'civil';
      const end = b.dataset.end ? Number(b.dataset.end) : unitEnd(t, prec, cal);
      openYearPanel(t, null, { prec: prec === 'h' || prec === 'min' ? 'd' : prec, end, label: b.dataset.label || null, cal }); // 창을 먼저 — 가는 길이 창이 가리지 않은 부분의 가운데를 향하게
      goToDate(t, prec, { end });
    } else {
      const item = state.model.byUid.get(b.dataset.uid);
      if (item && item.lineageOnly) openDetail(item.uid); // 계보 전용 인물: 창만 (띠에 그림이 없음)
      else if (item) {
        openDetail(item.uid);
        timeline.focusOn(item);
      } else if (houseOf(b.dataset.uid)) openDetail(b.dataset.uid); // 가문: 창만 (그 가문의 칸이 진해짐)
    }
    resultsEl.hidden = true;
  }

  searchInput.addEventListener('input', () => {
    hiOwner = 'search'; // 검색어를 고치면 검색 강조가 창의 조명 강조보다 먼저 (창을 열면 다시 창 — openDetail)
    runSearch();
  });
  searchInput.addEventListener('focus', () => searchInput.value.trim() && runSearch());
  searchInput.addEventListener('blur', () => setTimeout(() => (resultsEl.hidden = true), 150));
  searchInput.addEventListener('keydown', e => {
    const buttons = [...resultsEl.querySelectorAll('button')];
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (!buttons.length) return;
      activeIndex = (activeIndex + (e.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
      buttons.forEach((b, i) => b.classList.toggle('is-active', i === activeIndex));
      buttons[activeIndex].scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const b = buttons[activeIndex] || buttons[0];
      if (b) activateResult(b);
    } else if (e.key === 'Escape') {
      searchInput.value = '';
      runSearch();
      searchInput.blur();
    }
  });
  resultsEl.addEventListener('mousedown', e => e.preventDefault());
  resultsEl.addEventListener('click', e => {
    const b = e.target.closest('button');
    if (b) activateResult(b);
  });

  /* ---------- 상세 패널 ---------- */
  const detailEl = $('#detail');
  /* 창 안 사건 목록(이 시기의 사건 · 같은 시기 타국 · 관련 사건 · 서명한 조약 · 연도 창)의 날짜 칸은 창 전체에서 한 너비 — 가장 넓은 날짜(기간 '1405년 ~ 1433년' · 기원전 …)에 맞춰,
     한 해 사건과 기간 사건의 이름이 한 목록 안에서도 목록끼리도 같은 자리에서 시작합니다(예전에는 날짜 칸이 74px부터 글만큼 늘어 기간 사건의 이름만 13px 뒤로 밀렸음).
     날짜 칸은 여전히 버튼 폭의 45%까지(viewer.css --yw). 창의 글이 바뀔 때마다(열기 · '같은 시기 타국' 묶음 · 더 보기) 다시 잼 — 그리기 전(마이크로태스크)이라 어긋난 한 장면이 없음 */
  /* 승계 · 소속 · 왕조 목록(.succ-list)도 같은 길로(감독 건의 2026-10-14 6번 "이어간 나라의 연도 표기 정렬"): 오른쪽 기간 칸은 창 전체에서 가장 넓은 기간의 폭(--sw)으로
     왼쪽 끝을 맞추고, 앞의 배지(직접 · 간접 · 국가 …)도 가장 넓은 배지의 폭(--bw)으로 맞춰 이름이 같은 자리에서 시작합니다(새 앱 detail_shell.dart DetailSuccRow와 같은 꼴) */
  const alignYearCols = () => {
    for (const v of ['--yw', '--sw', '--bw']) detailEl.style.removeProperty(v);
    if (detailEl.hidden) return;
    const widest = sel => {
      let w = 0;
      for (const el of detailEl.querySelectorAll(sel)) w = Math.max(w, el.getBoundingClientRect().width);
      return w;
    };
    const set = (v, w) => w > 0 && detailEl.style.setProperty(v, `${Math.ceil(w * 2) / 2}px`);
    set('--yw', widest('.year-events .y'));
    set('--sw', widest('.succ-list button > small'));
    set('--bw', widest('.succ-list button > b:first-child'));
  };
  /* 묶음 접기(감독 건의 2026-10-14 3번 "다른 이름 · 실재성 · 소속 등 접기 펴기"): 상세 창의 머리글 있는 묶음(.sub-box > h3)은 머리글을 눌러 접고 폅니다.
     접힘은 머리글의 이름(작은 글 빼고)마다 기억(ui.detailFold) — 다른 나라를 열어도 같은 이름의 묶음은 접힌 채(새 앱 detail_shell.dart DetailFolds와 같은 규칙) */
  const foldTitleOf = h3 => [...h3.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('').trim();
  const applyDetailFolds = () => {
    const folded = new Set(state.ui.detailFold || []);
    for (const h3 of detailEl.querySelectorAll('section.sub-box > h3')) {
      const box = h3.parentElement, title = foldTitleOf(h3);
      const foldable = !!title && box.children.length > 1;
      box.classList.toggle('is-foldable', foldable);
      box.classList.toggle('is-folded', foldable && folded.has(title));
      if (foldable) h3.setAttribute('aria-expanded', String(!folded.has(title)));
    }
  };
  detailEl.addEventListener('click', e => {
    const h3 = e.target.closest('section.sub-box.is-foldable > h3');
    if (!h3 || e.target.closest('button, a, input, label, select')) return;
    const title = foldTitleOf(h3);
    const folded = new Set(state.ui.detailFold || []);
    if (!folded.delete(title)) folded.add(title);
    state.ui.detailFold = [...folded].sort();
    HT.store.set(K.ui, state.ui);
    applyDetailFolds();
  });
  if (typeof MutationObserver === 'function') new MutationObserver(alignYearCols).observe(detailEl, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });
  if (typeof MutationObserver === 'function') new MutationObserver(applyDetailFolds).observe(detailEl, { childList: true, subtree: true });
  /** 'house:가문 id' → 가문 (없으면 null) — 가문은 연표에 제 줄이 없어 byUid에 들지 않습니다 */
  const houseOf = uid => {
    const m = /^house:(.+)$/.exec(String(uid || ''));
    return m && state.model && state.model.houseMap ? state.model.houseMap.get(m[1]) || null : null;
  };
  /** 'surname:성씨 id' → 성씨 (없으면 null) — 성씨 창 (D1 결정 7 A: 그 성의 모든 가문을 함께 조명) */
  const surnameOf = uid => {
    const m = /^surname:(.+)$/.exec(String(uid || ''));
    return m && state.model && state.model.surnameMap ? state.model.surnameMap.get(m[1]) || null : null;
  };
  /** 상세 창을 열 수 있는 것: 모델 항목(byUid) 또는 가문 ('house:id') · 성씨 ('surname:id') */
  const detailTarget = uid => (state.model && state.model.byUid.get(uid)) || houseOf(uid) || surnameOf(uid);
  /** 가문 배지 (누르면 가문 창) — o는 houseId · houseName · houseColor를 단 모델 항목이나 칸. word: '국성' · '가문' (이름이 이미 '…가문'이면 '가문'은 붙이지 않음) */
  const houseBadge = (o, word = '가문') =>
    o && o.houseId
      ? `<button type="button" class="badge is-link" style="--c:${o.houseColor}" data-uid="house:${esc(o.houseId)}" title="${esc(`${o.houseName} — 누르면 가문 창${o.houseAuto ? ' (적지 않아 왕조 · 국성으로 짐작)' : ''}`)}">${esc(word === '가문' && /가문$/.test(o.houseName) ? o.houseName : `${word} ${o.houseName}`)}</button>`
      : '';
  /* ---------- 이름 목록 · 사람 · 자리 이음 · 혈연 (형식 버전 3) — 상세 창의 글 ----------
     상세 창 머리(10건 3 · 감독 결정 D2-1 A): 제목 아래 두 줄 — 첫 원어(크게 · .names-orig) · 첫 로마자(없으면 현지음 → 한자음 — 작게 · .names-roman) (HT.namesHead).
     언어 · 종류 딱지는 두지 않습니다(감독 "한문, 로마자 등의 표기는 X" — 언어 이름 · 종류 · 쓴 기간은 글에 올렸을 때의 풍선에만).
     두 줄에 오르지 않은 이름만 설명 바로 위의 '다른 이름 n개' 칸(.names-rest — 종류 · 글 · 쓴 기간). 머리의 이름은 칸에 다시 적지 않습니다.
     그릴 수 없는 이름(결정 4 B — 창 표 HT.glyphTables(켜진 글꼴).window에 없는 글자가 있음)은 글 대신 '원어 — ○○ · 글꼴 없음' 딱지(.names-nofont).
     글은 <bdi lang>로 방향을 가둡니다(오른쪽에서 왼쪽으로 쓰는 글자도 그 글만). 지명 · 성씨처럼 딸린 이름은 한 줄(namesLineHTML — "지명 ○○ — 원어 · 로마자").
     필터 '표기'(state.ui.names — HT.namesUi): 원어 없음이거나 적용 체크를 끈 종류(나라 · 인물 · 지명)는 이 글을 모두 빼 형식 3 이전 모습 그대로 */
  const nameWhen = n => (n.start != null || n.end != null || n.startUnknown || n.endUnknown ? `${n.startUnknown ? '미정' : n.start != null ? whenText(n.start, n.startAt) : ''} ~ ${n.endUnknown ? '미정' : n.end != null ? whenText(n.end, n.endAt) : ''}`.trim() : '');
  const namesUi = () => HT.namesUi(state.ui.names);
  /** 이 종류(polity 나라 · person 인물 · place 지명 · null = 적용 체크 밖 — 사건 제목의 다른 이름)의 이름 목록을 상세 창에 보이나 */
  const namesShown = kind => {
    const u = namesUi();
    return u.orig !== 'none' && (!kind || u.kinds[kind] !== false);
  };
  /** 판정 표 둘 { band, window } — 켜진 글꼴 팩(모델의 fonts)이 덮는 범위까지 (모델마다 한 번) */
  const glyphT = () => (state.model ? state.model._glyphT || (state.model._glyphT = HT.glyphTables(state.model.fonts)) : HT.glyphTables());
  const nameTip = n => [n.kind ? HT.nameKindName(n.kind) : '', n.lang ? HT.langName(n.lang) : '', nameWhen(n), n.note || ''].filter(Boolean).join(' · ');
  const nameBit = n => `<bdi${n.lang ? ` lang="${esc(n.lang)}"` : ''}${nameTip(n) ? ` title="${esc(nameTip(n))}"` : ''}>${esc(n.text)}</bdi>`;
  /** 그릴 수 없는 이름의 딱지: "원어 — 가상 문자 · 글꼴 없음" (올리면 까닭) */
  const noFontChip = (n, what = '원어') =>
    `<span class="names-nofont" title="${esc(`이 ${what}의 문자가 화면 글꼴에 없습니다 — 글꼴 팩을 넣으면 보입니다`)}">${esc(`${what} — ${HT.missingScriptName(n.text, glyphT().window)} · 글꼴 없음`)}</span>`;
  const nameOrChip = (n, what) => (HT.drawable(n.text, glyphT().window) ? nameBit(n) : noFontChip(n, what));
  /** 머리 두 줄(제목 바로 아래) */
  function namesHeadHTML(list, kind = null) {
    if (!namesShown(kind)) return '';
    const { first, second } = HT.namesHead(list);
    const T = glyphT().window;
    const one = first ? `<p class="names-orig${HT.drawable(first.text, T) ? '' : ' is-nofont'}">${nameOrChip(first, '원어')}</p>` : '';
    const two = second && HT.drawable(second.text, T) ? `<p class="names-roman">${nameBit(second)}</p>` : '';
    return one + two;
  }
  /** '다른 이름 n개' 칸 (설명 바로 위 — 머리 두 줄에 오르지 않은 이름만) */
  function namesRestHTML(list, kind = null) {
    if (!namesShown(kind)) return '';
    const { rest } = HT.namesHead(list);
    if (!rest.length) return '';
    /* [종류][이름 — 그 아래 메모][쓴 기간]: 메모를 기간과 한 글로 오른쪽 칸에 두면 메모가 길 때 그 칸이 폭을 다 가져가 이름이 한 글자씩 세로로 섰습니다
       (감독 건의 2026-10-14 4번). 메모는 이름 아래 작은 글로, 기간 칸은 폭의 40%까지(새 앱 names_display.dart NamesRest와 같은 꼴) */
    return `<section class="sub-box names-rest"><h3>다른 이름 <small>${rest.length}</small></h3><ul class="names-list">${rest
      .map(n => `<li><span class="k">${esc(n.kind ? HT.nameKindName(n.kind) : '')}</span><b>${nameOrChip(n, '이름')}${n.note ? `<i class="note">${esc(n.note)}</i>` : ''}</b><small>${esc(nameWhen(n) || '')}</small></li>`)
      .join('')}</ul></section>`;
  }
  /** 딸린 이름 한 줄(지명 · 성씨): "lead 원어 · 로마자 · 다른 이름 …" */
  function namesLineHTML(list, kind, lead) {
    if (!namesShown(kind)) return '';
    const { first, second, rest } = HT.namesHead(list);
    const head = [first, second].filter(Boolean).map(n => nameOrChip(n, '이름'));
    if (!head.length && !rest.length) return '';
    const restTag = n => [n.kind ? HT.nameKindName(n.kind) : '', nameWhen(n), n.note || ''].filter(Boolean).join(' · ');
    const others = rest.length ? `<small>${head.length ? ' · ' : ''}다른 이름 ${rest.map(n => `${nameOrChip(n, '이름')}${restTag(n) ? ` (${esc(restTag(n))})` : ''}`).join(' · ')}</small>` : '';
    return `<p class="aka names-line">${lead}${head.join(' · ')}${others}</p>`;
  }
  /** 예전 이름(다른 갈래가 부르던 꼴 그대로): lead가 있으면 딸린 한 줄, 없으면 머리 두 줄 + '다른 이름' 칸 */
  const namesHTML = (list, lead = '', kind = null) => (lead ? namesLineHTML(list, kind, lead) : namesHeadHTML(list, kind) + namesRestHTML(list, kind));
  /** 사람 자리 → 누르는 글: 같은 나라의 칸이면 그 칸(data-cell-nav), 인물이면 인물 창, 다른 나라의 칸이면 그 칸, 아니면 글만(미상 · 못 찾은 이름).
      open = 지금 열린 창의 나라 — here(그 사람의 칸을 찾을 나라)와 다르면 같은 나라의 칸도 그 나라의 칸으로(data-cell-of — 한 사람 창의 다른 자리 줄) */
  const personLink = (n, here = null, open = here) => {
    if (!n) return '';
    if (n.unknown) return '미상';
    const same = here ? n.cells.find(q => q.p === here && q.kind === 'leader') : null;
    if (same && same.p !== open) return `<button type="button" class="linky" data-cell-of="${esc(same.p.uid)}" data-cell="${esc(same.ref)}">${esc(n.name)}</button>`;
    if (same) return `<button type="button" class="linky" data-cell-nav="${esc(same.ref)}">${esc(n.name)}</button>`;
    if (n.figure && state.model.byUid.has(n.figure.uid)) return `<button type="button" class="linky" data-uid="${esc(n.figure.uid)}" title="인물 상세">${esc(n.name)}</button>`;
    const c = n.cells[0];
    if (c) return `<button type="button" class="linky" data-cell-of="${esc(c.p.uid)}" data-cell="${esc(c.ref)}">${esc(c.p.name)} ${esc(n.name)}</button>`;
    return `${esc(n.name)}${n.missing ? ' <small>(찾지 못한 이름)</small>' : ''}`;
  };
  const kinRoleText = e => (e.as === 'ancestor' ? `${e.gen ? `${e.gen}대 ` : ''}조상` : e.as ? HT.parentRoleName(e.as) : '부모');
  const spanSmall = s => (s.start != null || s.end != null || s.startUnknown || s.endUnknown ? ` <small>${esc(`${s.startUnknown ? '미정' : s.start != null ? whenText(s.start, s.startAt) : ''} ~ ${s.endUnknown ? '미정' : s.end != null ? whenText(s.end, s.endAt) : ''}`.trim())}</small>` : '');
  /** 사람의 혈연 줄들 — 부모 · 조상 / 배우자 / 자식 (here = 지금 보는 나라 — 같은 나라의 칸은 그 칸으로) */
  function kinLinesHTML(n, here = null) {
    if (!n) return '';
    const cert = e => (e.certainty ? ` <small>${esc(HT.certaintyName(e.certainty))}</small>` : '');
    const parents = n.parents.map(e => `${esc(kinRoleText(e))} ${personLink(e.node, here)}${cert(e)}${e.note ? ` <small>${esc(e.note)}</small>` : ''}`);
    const spouses = n.spouses.map(e => `${personLink(e.node, here)}${spanSmall(e)}`);
    const kids = n.children.map(e => `${personLink(e.node, here)}${e.as === 'ancestor' ? ` <small>${esc(`${e.gen ? `${e.gen}대` : ''} 후손`.trim())}</small>` : /^adoptive-/.test(e.as) ? ' <small>양자</small>' : ''}`);
    return [parents.length ? `<p class="aka kin-line">부모 · 조상: ${parents.join(' · ')}</p>` : '', spouses.length ? `<p class="aka kin-line">배우자: ${spouses.join(' · ')}</p>` : '', kids.length ? `<p class="aka kin-line">자식 · 후손: ${kids.join(' · ')}</p>` : ''].join('');
  }
  /** 지도자 칸의 자리 이음 글 { line, note } ('앞 지도자 ○○의 동생 · 찬탈') — 없으면 null. open = 지금 열린 창의 나라(다른 나라의 자리면 이름 링크가 그 나라의 칸으로),
      short = 한 사람 창의 자리 줄(첫 줄에 이미 '지도자'가 있어 '앞 ○○의 동생 · 찬탈' — 건의 8의 6-가) */
  function accessionOf(x, i, open = x, short = false) {
    const c = (x.leaders || [])[i];
    if (!c || !c.accession) return null;
    const r = ((HT.lineageOf(state.model, x) || {}).rulers || [])[i];
    const a = r ? r.accession : null;
    if (!a) return null;
    /* 앞 지도자를 알고 관계도 알면 '앞 지도자 ○○의 동생', 아니면 조각마다 ' · ' (토씨가 이름의 받침에 따라 갈리지 않게).
       '…의'로 이으면 뜻이 틀어지는 관계(무관 → '○○의 무관'은 다른 낱말로 읽힘 · 본인)는 조각으로 '혈연 없음' · '같은 사람', 앞 지도자가 없으면(첫 지도자) '관계 아들'처럼 앞말을 붙입니다 */
    const lead = short ? '앞' : '앞 지도자';
    const from = a.fromUnknown ? `${lead} 미상` : a.from ? `${lead} ${personLink(a.from, x, open)}` : '';
    const plain = { unrelated: '혈연 없음', self: '같은 사람' }[a.kin] || '';
    const kin = a.kin ? `${!from && !plain ? '관계 ' : ''}<b>${esc(plain || a.kinName)}</b>` : a.kinUnknown ? '관계 미상' : '';
    const how = a.how ? esc(a.howName) : a.howUnknown ? '오른 방식 미상' : '';
    const line = (a.from && !a.fromUnknown && a.kin && !plain ? [`${from}의 ${kin}`, how] : [from, kin, how]).filter(Boolean).join(' · ');
    return line ? { line, note: a.note || '' } : null;
  }
  /** 한 사람의 창인가 (건의 8의 6-가): 지도자 · 사람을 적은 내각 칸이고, 그 사람이 다른 자리(다른 나라 · 같은 나라 복위)를 가졌을 때 — 사람 자리(HT.personOf) */
  const seatPerson = (x, kind, i) => {
    if (kind !== 'leader' && kind !== 'cabinet') return null;
    const n = HT.personOf(state.model, x, `${kind}:${i}`);
    return n && !n.unknown && (n.cells || []).length >= 2 ? n : null;
  };
  /** 자리들 — 시작 순 [{ q(사람 자리 칸 { p, kind, i, ref, c }), sp(칸이 품는 구간 HT.cellSpan) }] */
  const seatsOf = n =>
    n.cells
      .map(q => ({ q, sp: cellSpanOf(q.p, q.c, q.ref) }))
      .sort((a, b) => a.sp.start - b.sp.start || (a.sp.end ?? a.sp.start) - (b.sp.end ?? b.sp.start));
  const seatEnd = sp => (sp.end != null && isFinite(sp.end) ? sp.end : sp.start);
  /** 한 사람의 창의 '자리 N' 묶음 (건의 8의 6-가 — 목업 #s6 '후'): 둥근 8 · 1px 테 상자에 자리마다 한 줄 — 첫 줄 '● 나라 지도자 · 4대' + 오른쪽 끝 연도만 기간,
      둘째 줄은 그 자리의 자리 이음(있을 때만 · 이름은 누르는 링크). 지금 누른 자리는 왼쪽 먹 막대 · 옅은 바탕, 다른 자리를 누르면 그 나라의 그 칸.
      자리 둘 이상이 시간이 겹치면 상자 아래 '겹친 기간'과 자리마다 가는 막대(합친 기간 안의 비례 자리) */
  function seatsHTML(x, ref, n) {
    const seats = seatsOf(n);
    const yy = t => (t == null || !isFinite(t) ? '' : HT.formatAxisYear(t));
    const rows = seats
      .map(({ q, sp }) => {
        const here = q.p === x && q.ref === ref;
        const role = q.kind === 'leader' ? `지도자${q.c.ordinal != null ? ` · ${q.c.ordinal}대` : ''}` : `내각${q.c.name ? ` · ${q.c.name}` : ''}`;
        const go = q.p === x ? `data-cell-nav="${esc(q.ref)}"` : `data-cell-of="${esc(q.p.uid)}" data-cell="${esc(q.ref)}"`;
        const acc = q.kind === 'leader' ? accessionOf(q.p, q.i, x, true) : null;
        const end = q.c.endUnknown ? '미정' : HT.cellToNow(q.c, q.p) ? '현재' : yy(seatEnd(sp));
        return `<li class="seat${here ? ' is-here' : ''}" style="--c:${q.p.color}"><button type="button" class="seat-go" ${go}${here ? ' aria-current="true"' : ''} title="${esc(`${q.p.name} ${role}${here ? ' — 지금 보는 자리' : ' — 그 칸으로'}`)}"><i aria-hidden="true"></i><b>${esc(q.p.name)}</b><small>${esc(role)}</small><span class="seat-when">${esc(`${q.c.startUnknown ? '미정' : yy(sp.start)} ~ ${end}`)}</span></button>${acc ? `<p class="seat-acc"${acc.note ? ` title="${esc(acc.note)}"` : ''}>${acc.line}</p>` : ''}</li>`;
      })
      .join('');
    /* 겹친 기간: 두 자리씩 견줘 겹친 구간을 모두 품는 한 구간 */
    let ov = null;
    for (let a = 0; a < seats.length; a++)
      for (let b = a + 1; b < seats.length; b++) {
        const lo = Math.max(seats[a].sp.start, seats[b].sp.start);
        const hi = Math.min(seatEnd(seats[a].sp), seatEnd(seats[b].sp));
        if (hi > lo) ov = ov ? [Math.min(ov[0], lo), Math.max(ov[1], hi)] : [lo, hi];
      }
    let ovHTML = '';
    if (ov) {
      const A = Math.min(...seats.map(s => s.sp.start));
      const B = Math.max(A + 1e-9, ...seats.map(s => seatEnd(s.sp)));
      const pct = v => (((v - A) / (B - A)) * 100).toFixed(3);
      const bars = seats.map(({ q, sp }, k) => `<i style="--c:${q.p.color};left:${pct(sp.start)}%;width:${(((seatEnd(sp) - sp.start) / (B - A)) * 100).toFixed(3)}%;top:${k * 6}px" title="${esc(q.p.name)}"></i>`).join('');
      const dur = ov[1] - ov[0] >= 1 ? durationText(ov[0], ov[1], 'y') : durationText(ov[0], ov[1], 'm');
      ovHTML = `<p class="seat-ov"><span>겹친 기간</span><b>${esc(`${yy(ov[0])} ~ ${yy(ov[1])}`)}</b><span>· ${esc(dur)}</span><span class="seat-bars" style="height:${seats.length * 6 - 2}px" aria-hidden="true">${bars}</span></p>`;
    }
    return `<section class="sub-box seats"><h3>자리 <small>${seats.length}</small></h3><ul class="seat-list">${rows}</ul>${ovHTML}</section>`;
  }
  /** 지도자 칸 창의 사람 · 자리 이음 · 혈연 글 ('앞 지도자 ○○의 동생 · 찬탈' · 같은 사람의 다른 칸 · 부모 · 배우자).
      그 사람이 다른 자리를 가졌으면(한 사람의 창 — 건의 8의 6-가) 자리 이음과 다른 칸 대신 '자리 N' 묶음, 혈연 줄은 '가족' 묶음 안으로 */
  function cellPersonHTML(x, kind, i, c) {
    const m = state.model;
    const n = HT.personOf(m, x, `${kind}:${i}`);
    if (!n) return '';
    const out = [];
    const multi = seatPerson(x, kind, i);
    const acc = !multi && kind === 'leader' ? accessionOf(x, i) : null;
    if (acc) out.push(`<p class="aka lineage-line">${acc.line}${acc.note ? ` <small>${esc(acc.note)}</small>` : ''}</p>`);
    if (n.figure && n.figure !== figureOfLeader(x, c) && m.byUid.has(n.figure.uid)) out.push(`<p class="aka">사람: <button type="button" class="linky" data-uid="${esc(n.figure.uid)}" title="인물 상세">${esc(n.figure.name)}${n.figure.role ? ` · ${esc(n.figure.role)}` : ''}</button></p>`);
    if (multi) {
      out.push(seatsHTML(x, `${kind}:${i}`, n));
      const kin = kinLinesHTML(n, x);
      if (kin) out.push(`<section class="sub-box seat-kin"><h3>가족</h3>${kin}</section>`);
      out.push(personGroupsHTML(n));
      return out.join('');
    }
    const others = n.cells.filter(q => !(q.p === x && q.ref === `${kind}:${i}`));
    /* 칸 글: 다른 나라면 나라 이름, 내각 칸이면 '내각 이름', 같은 나라의 지도자 칸이면 '지도자' — 같은 나라의 내각 칸과 다시 오른 지도자 칸이 기간만으로 같아 보이지 않게 */
    const otherText = q => [q.p === x ? '' : q.p.name, q.kind === 'cabinet' ? `내각 ${q.c.name}` : q.p === x ? '지도자' : '', cellWhen(q.c, false, q.p)].filter(Boolean).join(' ');
    if (others.length) out.push(`<p class="aka">같은 사람의 다른 칸: ${others.map(q => `<button type="button" class="linky" ${q.p === x ? `data-cell-nav="${esc(q.ref)}"` : `data-cell-of="${esc(q.p.uid)}" data-cell="${esc(q.ref)}"`}>${esc(otherText(q))}</button>`).join(' · ')}</p>`);
    out.push(kinLinesHTML(n, x));
    out.push(personGroupsHTML(n)); // 단체의 구성원으로 적힌 곳 (형식 3 — 단체 · 사람 잇기)
    return out.join('');
  }
  /** 인물 창의 사람 글: 사람(person)으로 이어진 지도자 칸(같은 이름의 지도자에 없는 것) · 부모 · 배우자 · 자식 */
  function figurePersonHTML(f, twins = []) {
    const n = HT.personOf(state.model, f);
    if (!n) return '';
    const ruled = n.cells.filter(q => q.kind === 'leader' && !twins.some(t => t.p === q.p && `leader:${t.i}` === q.ref));
    return `${ruled.length ? `<p class="aka">다스린 칸: ${ruled.map(q => `<button type="button" class="linky" data-cell-of="${esc(q.p.uid)}" data-cell="${esc(q.ref)}">${esc(q.p.name)} ${esc(HT.leaderLabel(q.c, state.ui.leaderLabel || 'auto'))}</button>`).join(' · ')}</p>` : ''}${kinLinesHTML(n)}${personGroupsHTML(n)}`;
  }
  /** 가문의 성 글 — 성을 성씨 사전의 id로 적었어도 이름으로(가문 창 배지와 같은 길 · 형식 버전 3) */
  const surnameText = h => ((h.surnameId && state.model.surnameMap && state.model.surnameMap.get(h.surnameId)) || {}).name || h.surname;
  /** 지명의 원어 한 줄 (도읍 칸 창 · 사건 상세) — 사전에 원어가 있거나 위 구역이 있을 때만 */
  function placeHTML(ref, lead) {
    const pl = HT.placeOf(state.model, ref);
    if (!pl) return '';
    const up = pl.parentId ? state.model.placeMap.get(pl.parentId) : null;
    const tail = up ? ` <small>${esc(`${up.name}에 속함`)}</small>` : '';
    const line = pl.names.length ? namesLineHTML(pl.names, 'place', `${esc(lead)} ${esc(pl.name)}${tail} — `) : ''; // 표기 설정으로 숨긴 지명은 이름이 없는 지명과 같게
    if (line) return line;
    return up || lead !== '지명' ? `<p class="aka">${esc(lead)} ${esc(pl.name)}${tail}</p>` : '';
  }
  /** 상세 창이 연표의 오른쪽을 가린 폭을 연표에 알려 줍니다(창을 열고 닫을 때 · 창 크기가 바뀔 때) — 검색·"이 위치로"처럼 멀리 갈 때 가려지지 않은 부분의 가운데에 도착하게.
      폭은 요소에서 읽습니다(들어오는 움직임의 transform과 무관한 배치 값). 좁은 화면에서 창이 화면을 다 덮으면 연표가 알아서 무시합니다 (timeline.js setInset).
      메이커에서는 오른쪽에 붙은 편집 창도 같은 자리를 가립니다 (떼어 내 떠 있으면 가리지 않는 것으로 — js/maker.js의 pane.cover) */
  const syncInset = () => {
    const host = $('#timeline');
    const detail = detailEl.hidden || detailEl.closest('.mk-right') ? 0 : host.offsetLeft + host.offsetWidth - detailEl.offsetLeft; // 메이커 작업실: 상세는 연표 밖 오른쪽 창 안 — 가리지 않음
    timeline.setInset({ right: Math.max(detail, maker ? maker.pane.cover(host) : 0) });
  };
  window.addEventListener('resize', syncInset);
  const FIELD_NAMES = {
    start: '시작', end: '끝', startAt: '시작 날짜', endAt: '끝 날짜', ongoing: '진행 중', title: '제목', name: '이름', track: '트랙', category: '분류',
    importance: '중요도', date: '날짜', description: '설명', tags: '태그', source: '출처', certainty: '확실성',
    startRange: '시작 연대 폭', endRange: '끝 연대 폭', alternatives: '다른 견해', debate: '쟁점', color: '색',
    parent: '상위 사건', polities: '함께 겪은 정권', tracks: '함께 겪은 나라', perspectives: '나라별 명칭', reigns: '지도자', leaders: '지도자', cabinets: '내각', eras: '연호', capitals: '도읍', polity: '정권', people: '민족', succeeds: '승계',
    kind: '종류', partOf: '소속', startUnknown: '시작 미정', endUnknown: '끝 미정', host: '얹히는 정권', successors: '승계한 국가', note: '메모', scale: '크기', wiki: '문서', house: '가문',
  };
  Object.assign(FIELD_NAMES, { relation: '소속 관계', nest: '상위 띠 아래에 접기' }); // 종류와 소속 관계 (소속 줄 안의 칸)
  Object.assign(FIELD_NAMES, { birth: '출생', death: '사망', birthAt: '출생 날짜', deathAt: '사망 날짜', aka: '다른 이름', role: '역할', service: '활동 기록', figures: '관련 인물' }); // 인물
  Object.assign(FIELD_NAMES, { phases: '시기 구분(학계)' }); // 시기 구분(학계) — 패치 전후 글은 체계 수로
  Object.assign(FIELD_NAMES, { ranks: '지위 변천', rank: '지위' }); // 지위 — 패치 전후 글은 칸 수로
  Object.assign(FIELD_NAMES, { treaty: '조약 규격' }); // 조약: 사건의 treaty 칸 (패치 표시)
  /* 항목 종류에 따라 이름이 다른 칸 (HT.itemKindOf → { 칸: 이름 }) — 시대의 house는 국성, 왕조의 house는 가문(옛 파일에서는 본가 왕조) */
  const FIELD_NAMES_OF = { period: { house: '국성' }, dynasty: { house: '가문·본가' } };
  const fieldName = (k, x) => ((x && FIELD_NAMES_OF[HT.itemKindOf(x)]) || {})[k] || FIELD_NAMES[k] || k;
  Object.assign(FIELD_NAMES, { historicity: '실재성', historicityNote: '실재성의 근거' }); // 실재성 (8-4 마)
  FIELD_NAMES.polityKind = '종류'; // 패치의 kind(정권 종류)는 모델에서 polityKind로 얹힙니다 (전 값도 그 이름으로)
  /** 패치 전후 값의 글. at = 시작·끝(· 연대 폭)과 짝인 날짜 글 */
  const fieldValue = (k, v, at) => {
    if (k === 'startUnknown' || k === 'endUnknown') return v ? '미정' : '아님'; // 켜고 끄는 칸은 비운 것(없음)과 거짓이 같은 값 — 전후 글이 달라 보이지 않게
    if (k === 'ongoing') return v ? '예' : '아니오';
    if (v == null || v === '') return '없음';
    if (HT.DATE_KEYS.includes(k)) return whenText(v, at);
    if (k === 'kind' || k === 'polityKind') return HT.kindName(v);
    if (k === 'track') return trackOf(v).name;
    if (k === 'category') return (state.model.categoryMap.get(v) || { name: v }).name;
    if (typeof v === 'boolean') return v ? '예' : '아니오';
    if (k === 'partOf' && typeof v !== 'string') return HT.readPartOf(v, { relation: true }).map(h => `${h.polity}${h.relation ? `(${HT.relationName(h.relation)})` : ''}`).join(' → ') || '없음'; // 소속 목록은 "상위(소속 관계) → …"로
    if (k === 'certainty') return HT.certaintyName(v);
    if (k === 'historicity') return HT.historicityName(HT.historicity(v));
    if (k === 'startRange' || k === 'endRange') return `${whenText(v[0], at && at[0])}~${whenText(v[1], at && at[1])}`;
    if ((k === 'aka' || k === 'figures' || k === 'successors') && Array.isArray(v)) return v.map(s => (typeof s === 'string' ? s : s && s.to ? s.to.name : '')).filter(Boolean).join(', ') || '없음'; // 이름 목록은 이름 그대로 (문화의 승계한 국가도)
    if (k === 'service' && Array.isArray(v)) return v.map(s => `${s.polity}${s.office ? `(${s.office})` : ''}`).join(' → ') || '없음';
    /* 승계 목록은 "선대(종류)"로 — 부분 승계는 정도 · 이어진 것까지 (HT.successionLabel) */
    if (k === 'succeeds' && Array.isArray(v))
      return (
        v
          .map(s => HT.normalizeSucc(s))
          .filter(Boolean)
          .map(e => `${e.from}(${HT.successionLabel(e)}${e.how ? ` · ${HT.succHowName(e.how)}` : ''})`) // 방식(how — 6단계 결정 15)은 종류 뒤에
          .join(', ') || '없음'
      );
    if (k === 'treaty') return `조약${v.type ? ` (${HT.treatyTypeName(v.type)})` : ''}${v.parties ? ` · 당사국 ${v.parties.length}` : ''}${v.articles ? ` · 조항 ${v.articles.length}` : ''}`; // 조약 규격은 요약만
    if (Array.isArray(v)) return `${v.length}개`;
    return String(v).length > 40 ? `${String(v).slice(0, 40)}…` : String(v);
  };

  /** 다른 견해 상자 (모든 항목 · 칸 공통 — 디테일 건의 4): 첫 줄은 '이 연표가 쓰는 연대'(base), 이설마다 채운 연대(비운 쪽은 통설 값 — HT.altSpan) · 근거 · 출처 · 메모.
      날짜 있는 줄은 누르면 그 해로(이설이 적은 쪽 — 시작을 비웠으면 끝, 인물은 적은 칸), 날짜 없이 근거만 적은 견해는 누르지 않는 줄(연표에도 표시 없음).
      opts.base = 통설 연대(칸은 그 칸의 적힌 구간 · 인물은 생몰과 활동 시기 — figureBase) · opts.figure = 인물(생몰 · 활동을 따로 적음) ·
      opts.sub = 부모 상세의 목록 아래 작은 상자(칸 창이 없는 소속 줄 · 왕조 구간 · 활동 기록 — 제목 opts.title) */
  function altHTML(x, { base = x, figure = false, sub = false, title = '', notes = '' } = {}) {
    const alts = (x && x.alternatives) || [];
    if (!alts.length) return '';
    const keys = figure ? ['start', 'end', 'birth', 'death'] : ['start', 'end'];
    /* 날짜 글 — 이설이 적은 쪽은 진하게, 비워서 통설 값으로 채운 쪽은 옅게(HT.altWhen과 같은 말 · 인물은 적은 칸만: 생몰 · 활동) */
    const sideHTML = (f, k) => {
      const t = f[`${k}Unknown`] ? '미정' : k === 'end' && f.ongoing ? '현재' : f[k] == null ? '' : HT.formatDate(f[k], f[`${k}At`]);
      return !t || f.own[k] ? esc(t) : `<i class="alt-fill" title="이 연표가 쓰는 연대 그대로">${esc(t)}</i>`;
    };
    const rangeHTML = f => (f.ongoing || f.endUnknown || (f.end != null && f.end !== f.start) ? `${sideHTML(f, 'start')} ~ ${sideHTML(f, 'end')}` : sideHTML(f, 'start'));
    const lifeHTML = f => {
      const b = sideHTML(f, 'birth');
      const d = sideHTML(f, 'death');
      return `생몰 ${b ? `${b} ` : ''}~${d ? ` ${d}` : ''}`;
    };
    const whenHTML = a => {
      if (!HT.altDated(a)) return '';
      const f = HT.altSpan(a, base, keys);
      if (!figure) return rangeHTML(f);
      return [f.own.birth || f.own.death ? lifeHTML(f) : '', f.own.start || f.own.end ? `활동 ${rangeHTML(f)}` : ''].filter(Boolean).join(' · ');
    };
    const own = { own: { start: true, end: true, birth: true, death: true } };
    const baseWhen = figure ? [base.birth != null || base.death != null ? lifeHTML(Object.assign({}, base, own)) : '', `활동 ${esc(HT.formatRange(base))}`].filter(Boolean).join(' · ') : esc(HT.formatRange(base));
    /* 첫 줄이 누르면 갈 해: 시작 — 시작이 미정이면 적힌 끝(미정이 아닐 때), 둘 다 없으면 누르지 않는 줄(연대 글은 그대로) */
    const baseAt = !base.startUnknown && base.start != null ? { t: base.start, at: HT.atOf(base, 'start') } : !base.endUnknown && !base.ongoing && base.end != null ? { t: base.end, at: HT.atOf(base, 'end') } : null;
    const btn = (at, when, body, main) =>
      at
        ? `<li${main ? ' class="is-main"' : ''}><button type="button" data-year="${at.t}" data-prec="${precOf({ start: at.t, startAt: at.at })}"><b>${when}</b><span>${body}</span></button></li>`
        : when
          ? `<li class="${main ? 'is-main ' : ''}is-text"><div class="alt-static"><b class="is-when">${when}</b><span>${body}</span></div></li>` // 날짜는 있으나 갈 해가 없는 줄 (시작 · 끝이 모두 미정인 칸의 첫 줄 · 앞뒤가 뒤집힌 이설)
          : `<li class="is-text"><div class="alt-static" title="날짜 없이 근거만 적은 견해 — 연표에는 표시가 없습니다"><b>—</b><span>${body}</span></div></li>`;
    const rows = alts.map(a => {
      const f = HT.altSpan(a, base, keys);
      const k = keys.find(q => f.own[q] && f[q] != null) || (HT.altDated(a) ? 'start' : null); // 이설이 적은 쪽으로 (현재까지만 적었으면 채운 시작)
      const flip = HT.altFlipped(a, base, keys); // 한쪽만 적은 이설의 빈 쪽을 통설 값으로 채우니 앞뒤가 뒤집힘 — 연표에 그리지 않으므로 누르지 않는 줄로, 까닭을 적어 둠
      const at = !flip && k && f[k] != null ? { t: f[k], at: f[`${k}At`] || null } : null;
      const body = `${esc(a.label)}${a.source ? ` · ${esc(a.source)}` : ''}${a.note ? `<small class="alt-note">${esc(a.note)}</small>` : ''}${flip ? '<small class="alt-note">비운 쪽을 이 연표의 연대로 채우면 앞뒤가 뒤집혀 연표에는 그리지 않습니다</small>' : ''}`;
      return btn(at, whenHTML(a), body, false);
    });
    const list = `<ul class="alt-list${sub ? ' is-sub' : ''}">${btn(baseAt, baseWhen, '이 연표가 쓰는 연대', true)}${rows.join('')}</ul>`;
    return sub ? `<div class="alt-sub"><p class="succ-cap">${esc(title)} <small>다른 견해 ${alts.length}</small></p>${notes}${list}</div>` : `<section class="sub-box"><h3>다른 견해</h3>${list}</section>`;
  }
  /** 인물의 통설 연대 (다른 견해의 비운 칸을 채우는 값 — 끝은 풀어 둔 활동 끝 endY) */
  const figureBase = f => ({ kind: 'figure', birth: f.birth, birthAt: f.birthAt, death: f.death, deathAt: f.deathAt, start: f.start, startAt: f.startAt, end: f.endY, endAt: f.endYAt, endY: f.endY, endYAt: f.endYAt, ongoing: f.ongoing, startUnknown: f.startUnknown, endUnknown: f.endUnknown });
  /** 칸의 통설 연대 — 적힌 시작과 연표에 놓인 끝(끝을 비운 칸은 풀어 둔 끝) · 미정 · 진행 중인 정권의 끝까지면 '현재' */
  const cellBase = (x, c, sp = HT.cellSpan(c, x)) => ({ start: sp.start, startAt: c.startAt, end: sp.end, endAt: sp.endAt, startUnknown: c.startUnknown, endUnknown: !!(c.endUnknown || (c.end == null && c.endYAuto)), ongoing: HT.cellToNow(c, x) });
  /** 연대가 모호한 칸(확실성 · 연대 폭)의 안내 줄 — 시대 상세의 '시작 — 이르면 …, 늦으면 …'과 같은 모양. withCert: 확실성도 글로(배지를 달 수 없는 작은 상자) */
  const uncNotesHTML = (u, withCert = false) =>
    [
      withCert && u.certainty && u.certainty !== 'accepted' ? `연대의 확실성 — ${HT.certaintyName(u.certainty)}` : '',
      u.startRange ? `시작 — 이르면 ${rangeWhen(u, 'startRange', 0)}, 늦으면 ${rangeWhen(u, 'startRange', 1)}` : '',
      u.endRange ? `끝 — 이르면 ${rangeWhen(u, 'endRange', 0)}, 늦으면 ${rangeWhen(u, 'endRange', 1)}` : '',
    ]
      .filter(Boolean)
      .map(t => `<p class="range-note">${esc(t)}</p>`)
      .join('');
  /** 칸 창 머리의 확실성 배지 (시대 상세의 '추정 연대' 배지와 같은 모양 — 통설이면 없음) */
  const certBadgeHTML = c => (c && c.certainty && c.certainty !== 'accepted' ? `<span class="badge badge-cert" title="${esc(`연대의 확실성 — ${(HT.CERTAINTY.find(v => v.id === c.certainty) || {}).hint || ''}`)}">${esc(HT.certaintyName(c.certainty))} 연대</span>` : '');
  /** 목록 한 줄의 작은 딱지: '이설 n'(다른 견해 수) · 모호함(확실성 이름, 연대 폭만이면 '연대 폭') — 정권 상세의 칸 목록 · 소속 · 왕조 · 활동 기록 */
  const altTagHTML = c => {
    if (!c) return '';
    const n = (c.alternatives || []).length;
    const fuzzy = HT.isFuzzy(c); // '확실'은 흐림이 아니므로 점선 딱지를 달지 않음 (칸 창 머리의 배지에만)
    const cert = fuzzy && (c.certainty === 'estimated' || c.certainty === 'legend') ? c.certainty : '';
    return `${n ? `<em class="alt-tag" title="다른 견해 ${n}개">이설 ${n}</em>` : ''}${fuzzy ? `<em class="alt-tag is-fuzzy" title="${esc(cert ? `연대의 확실성 — ${HT.certaintyName(cert)}` : '연대 폭이 적혀 있습니다')}">${esc(cert ? HT.certaintyName(cert) : '연대 폭')}</em>` : ''}`;
  };
  /** 칸 창이 없는 줄(소속 줄 · 왕조 구간 · 활동 기록)의 이설 · 모호함을 부모 상세의 목록 아래에: [{ title, base, u }] — 적힌 것이 있는 줄만 */
  const subAltsHTML = rows =>
    rows
      .filter(r => r.u && HT.hasUncertainty(r.u))
      .map(r => {
        const notes = uncNotesHTML(r.u, true);
        return r.u.alternatives && r.u.alternatives.length ? altHTML(r.u, { base: r.base, sub: true, title: r.title, notes }) : `<div class="alt-sub"><p class="succ-cap">${esc(r.title)}</p>${notes}</div>`;
      })
      .join('');

  /** 수정 내역 상자(🩹 «DLC»이(가) 고침 — 칸마다 전 → 후 · 패치의 note)는 메이커의 상세에만 둡니다.
      연표(보기 전용)에서는 DLC가 바꾼 값만 보이고 고친 흔적은 보이지 않습니다(모델의 patchedBy는 그대로 — 메이커의 [↩ 원래대로]는 작업본을 봄).
      줄은 값이 바뀐 칸만(HT.patchChanges — 날짜 글 짝 칸은 값 칸의 줄에 합침). 값은 다른데 글이 같으면(목록의 개수 · 긴 글의 앞부분) 뒤 글에 무엇을 고쳤는지 덧붙입니다 */
  function patchHTML(x) {
    if (!maker) return '';
    if (!x.patchedBy || !x.patchedBy.length) return '';
    return x.patchedBy
      .map((p, i) => {
        const changes = HT.patchChanges(x, i)
          .map(({ k, was, now, wasAt, nowAt, edited, uncEdited }) => {
            const a = fieldValue(k, was, wasAt);
            const b = fieldValue(k, now, nowAt);
            const unc = uncEdited ? (uncEdited === edited ? ' — 이설 · 연대 폭만' : ` — ${uncEdited}개는 이설 · 연대 폭만`) : ''; // 칸의 다른 견해 · 모호함만 고친 줄 (디테일 건의 4)
            const what = edited == null ? '내용 고침' : edited ? `${edited}개 고침${unc}` : '차례만 바꿈';
            return `${esc(fieldName(k, x))}: ${a !== b ? `${esc(a)} → <b>${esc(b)}</b>` : `<b>${esc(b)}</b> (${what})`}`;
          })
          .join('<br>');
        const mine = !!maker && maker.isDraftId(p.id); // 메이커: 지금 고치는 DLC가 건 패치 — 아래의 [원래대로]로 걷습니다
        return `<section class="sub-box is-patch"><h3>🩹 «${esc(p.name)}»이(가) 고침${mine ? ' <small>고치는 중인 DLC</small>' : ''}</h3>
          <div class="desc">${changes || '고치기 전과 같은 값입니다.'}${p.note ? `<br><i>${esc(p.note)}</i>` : ''}</div>
          <small>${mine ? '바뀐 칸만 패치로 담겨 있습니다. [↩ 원래대로]를 누르거나 원래 값으로 고쳐 저장하면 패치가 사라집니다.' : '이 DLC를 끄면 원래 내용으로 돌아갑니다.'}</small></section>`;
      })
      .join('');
  }

  function successionHTML(x) {
    if (x.kind !== 'period') return '';
    const pre = x.predecessors || [];
    const post = x.successors || [];
    if (!pre.length && !post.length && !x.people) return '';
    /* 배지: 직접(실선 테두리) · 간접(점선) · 부흥(점 테두리) · 부분(실선 테두리 — 올리면 '부분 승계 · 정도 중').
       이름 뒤 옅은 글: 부분 승계의 정도(선에는 그리지 않으므로 여기 글로 — '정도 중')와 이어진 것(지배층 · 백성 …), 흡수(후대가 선대보다 먼저 있던 나라 — 연표의 합류 선)면 '· n년 합류' —
       좁으면 이 글만 이름 아래 줄로(연도 칸은 한 줄) */
    const badge = edge =>
      edge.type === 'partial'
        ? `<b class="succ-partial" title="${esc(`부분 승계 · 정도 ${HT.succDegreeName(edge.degree)}`)}">부분</b>`
        : `<b class="succ-${edge.type}" title="${esc(HT.successionName(edge.type))}">${edge.type === 'direct' ? '직접' : edge.type === 'revival' ? '부흥' : '간접'}</b>`;
    const extra = edge => {
      const bits = edge.type === 'partial' ? [`정도 ${HT.succDegreeName(edge.degree)}`].concat((edge.parts || []).map(HT.succPartName)) : [];
      if (HT.succAbsorbs(edge.from, edge.to)) bits.push(`${HT.formatYear(edge.from.endY)} 합류`); // 연표의 합류 선과 같은 조건
      return bits.length ? ` <i class="succ-parts">${esc(bits.join(' · '))}</i>` : '';
    };
    const item = (p, edge) => `<li><button type="button" data-uid="${esc(p.uid)}">${badge(edge)}<span>${esc(p.name)}${extra(edge)}</span><small>${esc(HT.formatRange(p))}</small></button></li>`;
    return `<section class="sub-box"><h3>승계 ${x.people ? `<small>${esc(x.people)}</small>` : ''}</h3>${
      pre.length ? `<p class="succ-cap">이어받은 나라</p><ul class="succ-list">${pre.map(e => item(e.from, e)).join('')}</ul>` : ''
    }${post.length ? `<p class="succ-cap">이어간 나라</p><ul class="succ-list">${post.map(e => item(e.to, e)).join('')}</ul>` : ''}${
      !pre.length && !post.length ? '<p class="succ-cap">등록된 승계 관계가 없습니다.</p>' : ''
    }</section>`;
  }

  /** 소속: 연맹의 구성국, 종속국의 종주국, 조직체가 속한 나라 */
  function partOfHTML(x) {
    if (x.kind !== 'period' || x.polityKind === 'dynasty') return '';
    const hosts = x.hosts || [];
    const members = x.members || [];
    if (!hosts.length && !members.length) return '';
    const isOrgan = x.polityKind === 'overlay';
    /* 소속 관계 배지: 적힌 관계만 (상위 정권 줄에는 이 정권의 관계, 딸린 정권 줄에는 그 정권이 이 정권에 대해 가진 관계 — 여러 번이면 한 번씩) */
    const relBadge = (rels, skip) => {
      const list = [...new Set(rels.filter(Boolean))].map(r => HT.relationInfo(r)).filter(Boolean);
      if (!list.length || (list.length === 1 && list[0].name === skip)) return ''; // 종류 배지와 같은 말 하나뿐이면 되풀이하지 않음
      /* 하나면 이름 그대로, 관계가 차례로 바뀌었으면 배지 하나에 딱지를 차례로(조공 → 보호 → 식민) — 배지가 늘어 이름 자리를 밀어내지 않게 */
      return `<b class="rel-badge" title="${esc(`소속 관계: ${list.map(r => r.name).join(' → ')}`)}">${esc(list.length === 1 ? list[0].name : list.map(r => r.short).join('→'))}</b>`;
    };
    const item = p => `<li><button type="button" data-uid="${esc(p.uid)}"><b>${esc(HT.kindName(p.polityKind))}</b>${relBadge((p.hosts || []).filter(h => h.host === x).map(h => h.relation), HT.kindName(p.polityKind))}<span>${esc(p.name)}</span><small>${esc(HT.formatRange(p))}</small></button></li>`;
    const hostItem = h => `<li><button type="button" data-uid="${esc(h.host.uid)}"><b>${esc(HT.kindName(h.host.polityKind))}</b>${relBadge([h.relation])}<span>${esc(h.host.name)}${altTagHTML(h)}${h.note ? ` <i>${esc(h.note)}</i>` : ''}</span><small>${esc(h.start != null || h.end != null || h.startUnknown || h.endUnknown ? `${h.startUnknown ? '미정' : h.start != null ? whenText(h.start, h.startAt) : HT.formatWhen(x, 'start')} ~ ${h.endUnknown ? '미정' : h.end != null ? whenText(h.end, h.endAt) : endWhen(x)}` : '전 기간')}</small></button></li>`;
    const organs = members.filter(m => m.polityKind === 'overlay');
    const others = members.filter(m => m.polityKind !== 'overlay');
    /* 소속 줄의 이설 · 모호함 (칸 창이 없는 줄 — 목록 아래 작은 상자, 비운 쪽은 그 줄의 기간 · 줄의 기간을 비웠으면 이 정권의 기간) */
    const hostAlts = subAltsHTML(hosts.map(h => ({ title: `${h.host.name} ${isOrgan ? '얹힌 기간' : '소속 기간'}`, u: h, base: { start: h.start ?? x.start, startAt: h.start != null ? h.startAt : x.startAt, end: h.end ?? x.endY, endAt: h.end != null ? h.endAt : x.endYAt, startUnknown: h.startUnknown, endUnknown: h.endUnknown, ongoing: h.end == null && !h.endUnknown && x.ongoing } })));
    return `<section class="sub-box"><h3>${isOrgan ? '얹힌 정권' : '소속'}</h3>${hosts.length ? `<p class="succ-cap">${isOrgan ? '이 기관이 놓인 주권 정권' : hosts.length > 1 ? '차례로 예속된 상위 정권' : '상위 정권'}</p><ul class="succ-list">${hosts.map(hostItem).join('')}</ul>${hostAlts}` : ''}${
      others.length ? `<p class="succ-cap">${x.polityKind === 'federation' ? '구성 정권' : '딸린 정권·조직'} <small>${others.length}개</small></p><ul class="succ-list">${others.map(item).join('')}</ul>` : ''
    }${organs.length ? `<p class="succ-cap">위에 놓인 기관 <small>${organs.length}개</small></p><ul class="succ-list">${organs.map(item).join('')}</ul>` : ''}</section>`;
  }

  /** 실재성 상자 (8-4 마): 전설 · 반전설 · 논쟁 · 부정됨의 뜻과 근거 글 (실재인데 근거만 적었으면 근거만) */
  function historicityHTML(x, hs) {
    if (x.kind !== 'period' || (!hs && !x.historicityNote)) return '';
    const h = HT.HISTORICITY.find(v => v.id === (hs || 'attested'));
    return `<section class="sub-box is-hs${hs ? ` is-${hs}` : ''}"><h3>실재성 <small>${esc(h.name)}</small></h3><p class="succ-cap">${esc(h.hint)}${hs ? ' · 연대의 확실성과는 따로, 나라가 있었는가를 말합니다' : ''}</p>${
      x.historicityNote ? `<div class="desc">${esc(x.historicityNote)}</div>` : ''
    }</section>`;
  }
  /** 상위 띠 아래에 놓인 나라의 민족 (8-4 사): 자리는 소속이 정해 연표의 민족 칸에는 상위의 민족이 보이므로, 제 민족이 다르면 "(상위 〈나라〉는 〈민족〉)" 한마디 */
  function peopleUnderHTML(x) {
    if (x.kind !== 'period' || !x.peopleId || !x.singleHost) return '';
    const host = ((x.hosts || [])[0] || {}).host;
    if (!host || host.track !== x.track || host.peopleId === x.peopleId) return '';
    const c = host.name.charCodeAt(host.name.length - 1) - 0xac00;
    const topic = c >= 0 && c < 11172 ? (c % 28 ? '은' : '는') : '은(는)';
    return `<p class="people-note">민족 <button type="button" class="linky" data-doc="${esc(`people:${x.peopleId}`)}">${esc(x.peopleName)}</button> <small>(상위 <button type="button" class="linky" data-uid="${esc(host.uid)}">${esc(host.name)}</button>${topic} ${esc(host.peopleName || '민족을 적지 않음')})</small></p>`;
  }

  /** 왕조: 나라의 상세에는 다스린 왕조들, 왕조의 상세에는 다스린 나라·가문·지도자 */
  function dynastyHTML(x) {
    if (x.kind !== 'period') return '';
    /* 기간의 두 끝은 { t, text } — 여러 후보 가운데 늦은 시작·이른 끝을 고르고, 글은 그 후보의 날짜 글로 */
    const pt = (t, text) => ({ t, text });
    const later = (p, q) => (q.t > p.t ? q : p);
    const earlier = (p, q) => (q.t < p.t ? q : p);
    const range = (a, b) => `${a.text} ~ ${b.text}`;
    const li = (uid, tag, name, when, note, u) => `<li><button type="button" data-uid="${esc(uid)}"><b>${esc(tag)}</b><span>${esc(name)}${altTagHTML(u)}${note ? ` <i>${esc(note)}</i>` : ''}</span><small>${esc(when)}</small></button></li>`;
    if (x.polityKind !== 'dynasty') {
      const list = x.dynasties || [];
      if (!list.length) return '';
      /* 왕조 구간의 이설 · 모호함은 그 왕조가 적은 다스린 정권 줄의 것 (칸 창이 없어 목록 아래에) */
      const alts = subAltsHTML(list.map(d => ({ title: `${d.dynasty.name} 왕조 구간`, u: d, base: { start: d.start, end: d.end } })));
      return `<section class="sub-box"><h3>왕조 <small>${list.length}</small></h3><ul class="succ-list">${list.map(d => li(d.dynasty.uid, '왕조', d.dynasty.name, range(pt(d.start, whenText(d.start)), pt(d.end, endText(d.end))), d.note, d)).join('')}</ul>${alts}</section>`;
    }
    const ruled = (x.hosts || [])
      .map(h => ({
        host: h.host,
        a: later(h.start != null ? pt(h.start, h.startUnknown ? '미정' : whenText(h.start, h.startAt)) : pt(x.start, h.startUnknown ? '미정' : HT.formatWhen(x, 'start')), pt(h.host.start, HT.formatWhen(h.host, 'start'))),
        b: earlier(h.end != null ? pt(h.end, h.endUnknown ? '미정' : whenText(h.end, h.endAt)) : pt(x.endY, h.endUnknown ? '미정' : endWhen(x)), pt(h.host.endY, endWhen(h.host))),
        note: h.note,
        h,
      }))
      .filter(r => r.b.t >= r.a.t);
    const dyns = state.model.periods.filter(q => q.polityKind === 'dynasty');
    const house = x.house ? dyns.find(q => q !== x && (q.name === x.house || q.id === x.house)) : null;
    const branches = dyns.filter(q => q !== x && q.house && (q.house === x.name || q.house === x.id));
    const rulers = [];
    for (const r of ruled) for (const c of r.host.leaders || []) if ((c.dynasty || c.dynastyAuto) === x.name) rulers.push({ c, host: r.host });
    rulers.sort((a, b) => a.c.start - b.c.start);
    return `<section class="sub-box"><h3>다스린 나라 <small>${ruled.length}</small></h3>${
      ruled.length ? `<ul class="succ-list">${ruled.map(r => li(r.host.uid, HT.kindName(r.host.polityKind), r.host.name, range(r.a, r.b), r.note, r.h)).join('')}</ul>${subAltsHTML(ruled.map(r => ({ title: `${r.host.name} 다스린 기간`, u: r.h, base: { start: r.a.t, end: r.b.t } })))}` : '<p class="succ-cap">다스린 정권을 연표에서 찾지 못했습니다. 정권 이름이나 기간을 확인하세요.</p>'
    }${
      x.house || branches.length
        ? `<p class="succ-cap">가문</p><ul class="succ-list">${x.houseId ? li(`house:${x.houseId}`, '가문', x.houseName, '누르면 가문 창') : ''}${house ? li(house.uid, '본가', house.name, HT.formatRange(house)) : x.house && !x.houseId ? `<li><button type="button" disabled><b>본가</b><span>${esc(x.house)}</span></button></li>` : ''}${branches.map(q => li(q.uid, '갈라진 왕조', q.name, HT.formatRange(q))).join('')}</ul>`
        : ''
    }${
      rulers.length
        ? `<p class="succ-cap">지도자 <small>${rulers.length}명 · 누르면 그 시기로</small></p><ul class="kid-list">${rulers
            .map(({ c, host }) => `<li><button type="button" data-year="${c.start}" data-prec="${precOf(c)}"><b>${esc(cellWhen(c, false, host))}</b><span>${esc(HT.leaderLabel(c, state.ui.leaderLabel || 'auto'))}${ruled.length > 1 ? ` <i>${esc(host.name)}</i>` : ''}</span></button></li>`)
            .join('')}</ul>`
        : ''
    }</section>`;
  }

  /** 칸 목록의 📄 문서 단추 — 연표(보기 전용)에서는 문서가 있는 칸에만, 메이커에서는 없는 칸에도(눌러서 만듦) */
  const cellDocBtn = (key, has) =>
    has || maker ? `<button type="button" class="cell-doc${has ? ' has-doc' : ''}" data-doc="${esc(key)}" title="${has ? '문서 보기' : '문서 만들기'}" aria-label="${has ? '문서 보기' : '문서 만들기'}">${icon('file')}</button>` : '';
  /** 상세 아래의 📄 문서 단추에 적을 글 — 보기 전용에서는 문서도 하위 문서도 없으면 단추를 두지 않습니다('') */
  const wikiBtnText = key => (docText(key) ? `${icon('file')}문서` : maker ? `${icon('file')}문서 만들기` : subdocsOf(key).length ? `${icon('file')}문서` : '');

  /** 지도자·내각·연호 칸 목록. 칸마다 제 문서(📄)를 가질 수 있습니다 */
  function cellsHTML(title, list, unit, x, cellKind) {
    if (!list || !list.length) return '';
    const isLeader = title === '지도자';
    const succ = isLeader && list.length >= 2 && x.kind === 'period' && KVS() ? `<button type="button" class="btn btn-sm sub-act" data-kin-succ="" title="지도자 사이의 관계 · 오른 방식 — 접고 펼쳐 지도자가 아닌 후손까지">승계표</button>` : ''; // D1 결정 1 A: 나라 상세 '지도자' 상자 머리의 승계표 단추
    return `<section class="sub-box"><h3>${title} <small>${list.length}</small>${succ}</h3><ul class="cell-list${isLeader ? ' is-leaders' : ''}">${list
      .map(c => {
        const main = isLeader ? `${c.ordinal != null ? `<em>${c.ordinal}대</em> ` : ''}${esc(HT.leaderLabel(c, state.ui.leaderLabel || 'auto'))}` : esc(c.name);
        const extra = isLeader ? HT.leaderFacts(c, HT.leaderWords(x, state.model)).join(' · ') : ''; // 지도자 표기 낱말(6단계 D3)
        const key = HT.docKey.cell(x.uid, cellKind, c);
        const has = !!docText(key);
        return `<li><button type="button" data-year="${c.start}" data-prec="${precOf(c)}"><b>${esc(cellWhen(c, false, x))}</b><span>${main}${altTagHTML(c)}${c.note ? ` <i>${esc(c.note)}</i>` : ''}</span>${extra ? `<small>${esc(extra)}</small>` : ''}</button>${cellDocBtn(key, has)}</li>`;
      })
      .join('')}</ul></section>`;
  }

  /** 도읍 목록 (정도·배도·임시 …) — 🚇 단추로 노선도 카드. 칸마다 제 문서(📄) */
  function capitalsHTML(x) {
    const list = x.capitals;
    if (!list || !list.length) return '';
    const seats = new Set(list.filter(c => c.role !== 'secondary').map(c => c.city));
    const secs = new Set(list.filter(c => c.role === 'secondary' && !seats.has(c.city)).map(c => c.city)).size;
    return `<section class="sub-box"><h3>도읍 <small>${seats.size}${secs ? ` · 배도 ${secs}` : ''}</small><button type="button" class="btn btn-sm sub-act" data-act="metro" title="이 정권의 도읍 내력을 노선도로">${icon('route')}노선도</button></h3><ul class="cell-list">${list
      .map(c => {
        const key = HT.docKey.cell(x.uid, 'capitals', c);
        const has = !!docText(key);
        const role = c.role && c.role !== 'main' ? HT.capitalRoleName(c.role) : '';
        const extra = [c.as && c.as !== c.city ? `도시 ${c.city}` : '', c.label, c.group ? `묶음 ${c.group}` : ''].filter(Boolean).join(' · ');
        return `<li><button type="button" data-year="${c.start}" data-prec="${precOf(c)}"><b>${esc(cellWhen(c, true, x))}</b><span>${esc(c.name)}${role ? ` <em class="cap-role">${esc(role)}</em>` : ''}${altTagHTML(c)}${c.note ? ` <i>${esc(c.note)}</i>` : ''}</span>${extra ? `<small>${esc(extra)}</small>` : ''}</button>${cellDocBtn(key, has)}</li>`;
      })
      .join('')}</ul></section>`;
  }

  /** 시대 구분(삼국·남북국·고려 시대 …)의 상세 */
  function epochDetailHTML(x) {
    const track = x.track ? trackOf(x.track) : null;
    return `
      <div class="detail-head">
        <div class="badges">${track ? `<button type="button" class="badge is-link" style="--c:${track.color}" data-doc="track:${esc(track.id)}" title="${esc(track.name)} 문서">${esc(track.name)}</button>` : '<span class="badge">공통</span>'}<span class="badge" style="--c:${x.color}">시대 구분</span></div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(x.name)}</h2>
        <p class="when">${esc(HT.formatRange(x))}</p>
        <div class="desc${x.description || x.note ? '' : ' is-empty'}">${x.description ? esc(x.description) : x.note ? esc(x.note) : '설명이 없습니다.'}</div>
        ${altHTML(x)}
        ${scopeListHTML(x.scopes, '이어진 대범위', '같은 뜻의 대범위 — 스위치로 모아 보기')}
        ${viewsUi ? viewsUi.epochCardHTML(x) : ''}
        <dl><dt>제공</dt><dd>${esc(x.packName)}</dd></dl>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${wikiBtnText(x.uid) ? `<button class="btn btn-sm" data-act="wiki" type="button" title="이 시대 구분의 위키 문서">${wikiBtnText(x.uid)}</button>` : ''}
        ${maker && maker.isOwn(x) ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
      </div>`;
  }

  /* ---------- 대범위 (docs/구상-체제-확장.md 7-4 · 8-4 바) ----------
     시대 구분과 같은 부류라 연표(보기 전용)에는 상세 · 문서 · 모아 보기 스위치(보기)만 둡니다 — 메이커에서는 제 대범위(고치는 DLC의 것)만 편집 창에서 고치고(상세의 ✎ 수정 · 편집 창 맨 위에도 스위치),
     남의 DLC의 대범위는 패치가 닿지 않아 상세만(paneEditable). 스위치는 시트처럼 연표를 가리지 않는 자리에:
     대범위 상세의 '모아 보기' · 이어진 시대 구분 상세 · 정권 상세 · 우클릭 메뉴 · 테두리 이름표 · 본국 띠의 단추 */
  /** 모아 보기 스위치 (누르면 timeline.toggleScope — 상세는 새 상태로 다시 그려짐) */
  function scopeSwitchHTML(s) {
    const on = timeline.scopeOn(s);
    return `<button type="button" class="scope-switch${on ? ' is-on' : ''}" data-scope-toggle="${esc(s.uid)}" aria-pressed="${on}" style="--c:${s.color}" title="켜면 구성 정권이 한 가지로 모이고, 끄면 제 민족 묶음으로 돌아갑니다"><i></i><span>모아 보기</span><small>${on ? '켬' : '끔'}</small></button>`;
  }
  /** 대범위 목록 상자: 이름 칩(누르면 대범위 상세) + 스위치 */
  function scopeListHTML(list, title, note) {
    if (!list || !list.length) return '';
    return `<section class="sub-box is-scope"><h3 title="${esc(note)}">${esc(title)}</h3><div class="scope-rows">${list
      .map(s => `<div class="scope-row"><button type="button" class="chip is-scope" data-uid="${esc(s.uid)}" style="--c:${s.color}" title="${esc(`${s.name} 상세`)}">${esc(s.name)}${s.label ? ` <small>${esc(s.label)}</small>` : ''}</button>${scopeSwitchHTML(s)}</div>`)
      .join('')}</div></section>`;
  }
  /** 정권 상세의 대범위: 든 대범위 · 본국으로 받든 대범위. 상징적 본국이 있는 대범위의 구성 정권은 소속(partOf)을 적지 않았어도 "〈본국〉 아래 할거/부흥" (적었으면 그것이 우선) */
  function periodScopesHTML(x) {
    if (x.kind !== 'period' || (!x.scopes && !x.hostedScopes)) return '';
    const under = (x.hosts || []).length ? [] : (x.scopes || []).filter(s => s.host);
    return `${under
      .map(s => `<p class="people-note"><button type="button" class="linky" data-uid="${esc(s.host.uid)}">${esc(s.host.name)}</button> 아래 ${s.afterHost ? '부흥' : '할거'} <small>(대범위 ${esc(s.name)})</small></p>`)
      .join('')}${scopeListHTML(x.scopes, '대범위', '이 나라가 든 집합 — 누르면 상세, 스위치로 모아 보기')}${scopeListHTML(x.hostedScopes, '상징적 본국으로 받든 대범위', '켜면 이 나라 줄 바로 아래에 모입니다')}`;
  }
  /** 대범위 상세: 이름 · 성격 · 기간 · 본국 · 구성 정권 · 모아 보기 스위치 · 이어진 시대 구분 · 확인할 것 · 문서 */
  function scopeDetailHTML(x) {
    const track = trackOf(x.track);
    const own = x.members.filter(m => m.track === x.track);
    const other = x.members.filter(m => m.track !== x.track);
    const li = m => `<li><button type="button" data-uid="${esc(m.uid)}"><b>${esc(m.peopleName || HT.kindName(m.polityKind))}</b><span>${esc(m.name)}</span><small>${esc(HT.formatRange(m))}</small></button></li>`;
    const from = x.rangeFrom === 'epoch' ? ' · 시대 구분의 기간' : x.rangeFrom === 'members' ? ' · 구성 정권의 범위' : '';
    return `
      <div class="detail-head">
        <div class="badges"><button type="button" class="badge is-link" style="--c:${track.color}" data-doc="track:${esc(track.id)}" title="${esc(track.name)} 문서">${esc(track.name)}</button><span class="badge" style="--c:${x.color}">대범위</span>${x.label ? `<span class="badge badge-scope">${esc(x.label)}</span>` : ''}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(x.name)}</h2>
        <p class="when">${esc(HT.formatRange(x))}${from ? `<small class="when-sub">${esc(from.slice(3))}</small>` : ''}</p>
        <div class="scope-rows">${scopeSwitchHTML(x)}</div>
        ${x.host ? `<p class="people-note">상징적 본국 <button type="button" class="linky" data-uid="${esc(x.host.uid)}">${esc(x.host.name)}</button> <small>(${x.afterHost ? '본국이 끝난 뒤의 부흥 — 켜면 본국 줄 아래 · 본국이 끝난 자리의 오른쪽에 모임' : '이름만 남은 본국 — 그 띠에 할거기 칠 · 켜면 본국 줄 바로 아래에 모임'})</small></p>` : ''}
        <div class="desc${x.description || x.note ? '' : ' is-empty'}">${x.description ? esc(x.description) : x.note ? esc(x.note) : '설명이 없습니다.'}</div>
        <section class="sub-box"><h3>구성 정권 <small>${own.length}</small></h3><ul class="succ-list">${own.map(li).join('') || '<li class="muted">이 트랙에서 찾은 구성 정권이 없습니다.</li>'}</ul>${
          other.length ? `<p class="succ-cap">다른 트랙 — 모이지 않음</p><ul class="succ-list">${other.map(li).join('')}</ul>` : ''
        }</section>
        ${x.epoch ? `<p class="people-note">시대 구분 <button type="button" class="linky" data-uid="${esc(x.epoch.uid)}">${esc(x.epoch.name)}</button> <small>(같은 뜻${x.nameAuto || x.startAuto || x.colorAuto ? ' — 비워 둔 이름 · 기간 · 색을 물려받음' : ''})</small></p>` : ''}
        ${x.warnings.length ? `<section class="sub-box is-scope-warn"><h3>확인할 것 <small>${x.warnings.length}</small></h3><ul class="scope-warn">${x.warnings.map(w => `<li>${esc(w)}</li>`).join('')}</ul></section>` : ''}
        ${subdocsHTML(x.uid)}
        <dl><dt>제공</dt><dd>${esc(x.packName)}</dd>${x.note && x.description ? `<dt>메모</dt><dd>${esc(x.note)}</dd>` : ''}</dl>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${wikiBtnText(x.uid) ? `<button class="btn btn-sm" data-act="wiki" type="button" title="이 대범위의 위키 문서">${wikiBtnText(x.uid)}</button>` : ''}
        ${maker && maker.isOwn(x) ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
      </div>`; // 문서 단추는 다른 상세와 같은 규칙 — 연표(보기 전용)에서는 문서가 있을 때만, 메이커에서는 '문서 만들기'도. 수정은 메이커에서 제 대범위만 (시대 구분 상세와 같게)
  }

  /** 연대 폭의 한 끝 (startRange · endRange와 짝 날짜 글 startRangeAt · endRangeAt) */
  const rangeWhen = (x, key, i) => whenText(x[key][i], (x[`${key}At`] || [])[i]);
  /** 사건의 자유 날짜 글(date): 연대와 같은 때를 가리키면 겹치니 숨기고, 다르면(음력 표기·시각 등) "원문 표기"로 남깁니다 */
  const dateNoteOf = x => {
    const s = String(x.date || '').trim();
    if (!s) return '';
    const r = HT.cal.parse(s);
    return r && r.ok && Math.abs(r.t - x.start) < 1e-6 ? '' : s;
  };

  /** 칸 참조 'leader:3' → { kind, K(칸 종류 표의 줄), i, c, list } (없으면 null) — 종류는 HT.CELL_KINDS에 있는 것 모두 */
  const parseCellRef = (x, ref) => {
    if (!ref || x.kind !== 'period') return null;
    const [kind, n] = String(ref).split(':');
    const K = HT.cellKind(kind);
    const list = K ? HT.cellsOf(x, K) : null;
    const c = list && list[Number(n)];
    return c ? { kind, K, i: Number(n), c, list } : null;
  };
  /** 칸이 연표에 놓인 구간(start · end)과 그 칸이 품는 구간 [lo, hi) — 칸 조명 · 그 시기의 사건 · 이 시기의 인물 · "이 시기로"가 씀.
      이웃 칸과 겹치지 않게(경계 해는 뒤 칸의 것 — HT.cellBounds), 이어받는 칸이 없으면 연도만 적은 끝은 그해 끝까지 (HT.cellSpan). ref = 칸 참조('leader:3') */
  const cellSpanOf = (x, c, ref) => HT.cellSpan(c, x, ref);
  /** 칸이 품는 구간이 [a, b)에 걸치는가 — 같은 해 보기의 시기 · 지위 (바뀐 해에는 뒤 칸만 — 칸의 경계. 폭 0인 칸은 그 한 점이 들면) */
  const cellIn = (x, c, ref, a, b) => {
    const { lo, hi } = cellSpanOf(x, c, ref);
    return HT.spanMeets(lo, hi, a, b);
  };
  /** 칸 창(지도자 · 내각 · 연호 · 도읍 — 칸 종류 표의 낱말로): 이름 · 날짜(앞말 없이 — 어느 체제의 칸이든 같은 모양) · 정권 · (지도자는 왕조, 도읍은 역할) · 메모 · 앞뒤 칸 · 이 시기의 사건 · 문서
      (연표에는 그 칸과 기간이 조명되고 사건이 강조됩니다) */
  function cellDetailHTML(x, ref) {
    const { kind, K, i, c, list } = ref;
    const track = trackOf(x.track);
    const { start, end, endAt, lo, hi } = cellSpanOf(x, c, `${kind}:${i}`);
    const eu = !!(c.endUnknown || (c.end == null && c.endYAuto)); // 끝을 비운 도읍의 끝이 시작 미정인 다음 정도에서 짐작한 자리여도 "미정"
    const when = HT.formatRange({ start, startAt: c.startAt, end, endAt, startUnknown: c.startUnknown, endUnknown: eu, ongoing: HT.cellToNow(c, x) }); // 진행 중인 정권의 끝까지 가는 칸은 "~ 현재"
    /* 칸의 미정: 모르는 쪽이 연표의 어디에 놓였는지 (시대의 미정 안내와 같은 말투) */
    const unkWhere = c.startUnknown && eu ? `시작 · 끝 미정 — 연표에는 ${whenText(start)} ~ ${endText(end)} 무렵에 놓았습니다` : c.startUnknown ? `시작 미정 — 연표에는 ${whenText(start)} 무렵부터 놓았습니다` : eu ? `끝 미정 — 연표에는 ${endText(end)} 무렵까지 놓았습니다` : '';
    const nameOf = q => K.title(q, { leaderMode: state.ui.leaderLabel || 'auto' });
    const title = nameOf(c);
    const names = K.facts ? K.facts(c, HT.leaderWords(x, state.model)) : []; // 지도자 표기 낱말(6단계 D3 — 문화권 → 팩 → 묘호 · 시호 · 이름)
    const tag = K.tag ? K.tag(c) : '';
    const dyn = c.dynasty || c.dynastyAuto;
    const key = K.doc === false ? '' : HT.docKey.cell(x.uid, K.list, c);
    const has = !!key && !!docText(key);
    const evs = cellEvents(x, lo, hi);
    const prev = list[i - 1];
    const next = list[i + 1];
    const navName = nameOf;
    const badge = (key2, text, color, tip) => `<button type="button" class="badge is-link" style="--c:${color}" data-doc="${esc(key2)}" title="${esc(tip || `${text} 문서`)}">${esc(text)}</button>`;
    const sp = precOf(c);
    const dayLine = sp === 'd' || sp === 'h' ? dayNote(start, !lunarAt(c)) : '';
    /* 지도자의 지위 배지: 적은 지위, 없으면 지도자 칸이 시작한 해의 정권 지위(짐작) — 누르면 그 지위 창.
       여는 칸은 배지와 이름이 같은 지위 구간만: 칸이 시작한 해의 것 → 칸의 기간과 겹치는 것. 정권의 지위와 다른 지위를 적은 지도자라서
       같은 이름의 구간이 없으면 누를 수 없는 배지로 둡니다(다른 지위의 창을 열어 배지와 창이 어긋나지 않게) */
    const rkName = kind === 'leader' ? c.rank || c.rankAuto : '';
    const rkSame = rkName ? (x.rankSpans || []).map((s, j) => ({ s, j })).filter(({ s }) => s.name === rkName) : [];
    const rkHit = rkSame.find(({ s }) => s.start <= start && start < s.end) || rkSame.find(({ s }) => s.start <= start && start <= s.end) || rkSame.find(({ s }) => s.start < end && start < s.end);
    const rkAt = rkHit ? rkHit.j : -1;
    const rkTip = rkName ? `지위 ${rkName}${c.rank ? '' : ' — 적지 않아 이 지도자 칸이 시작한 해의 정권 지위로 짐작'}` : '';
    /* 한 사람의 창(건의 8의 6-가): 나라 · 트랙 · '지도자 · 제n대' · 지위 배지 대신 '인물'(회색 점 — 인물이 있으면 누르면 인물 창), 제목 아래 기간은 모든 자리를 합친 기간 */
    const seatN = seatPerson(x, kind, i);
    let seatWhen = '';
    let personBadge = '';
    if (seatN) {
      const seats = seatsOf(seatN);
      const a = seats[0];
      const z = seats.reduce((w, s) => (seatEnd(s.sp) > seatEnd(w.sp) ? s : w), seats[0]);
      seatWhen = HT.formatRange({ start: a.sp.start, startAt: a.q.c.startAt, startUnknown: a.q.c.startUnknown, end: seatEnd(z.sp), endAt: z.sp.endAt, endUnknown: z.q.c.endUnknown, ongoing: HT.cellToNow(z.q.c, z.q.p) });
      const fig = seatN.figure && state.model.byUid.has(seatN.figure.uid) ? seatN.figure : kind === 'leader' ? figureOfLeader(x, c) : null;
      personBadge = fig
        ? `<button type="button" class="badge is-link badge-person" data-uid="${esc(fig.uid)}" title="${esc(`${fig.name} — 인물 창`)}">인물</button>`
        : `<span class="badge badge-person" title="${esc(`같은 사람 — 자리 ${seats.length}`)}">인물</span>`;
    }
    const rankBadge = !rkName ? '' : rkAt >= 0 ? `<button type="button" class="badge is-link badge-rank" style="--c:${x.color}" data-cell-nav="rank:${rkAt}" title="${esc(`${rkTip} · 누르면 지위 창`)}">지위 ${esc(rkName)}${c.rank ? '' : ' (짐작)'}</button>` : `<span class="badge badge-rank" style="--c:${x.color}" title="${esc(rkTip)}">지위 ${esc(rkName)}${c.rank ? '' : ' (짐작)'}</span>`;
    return `
      <div class="detail-head">
        <div class="badges">${seatN ? personBadge : `${badge(`track:${track.id}`, track.name, track.color)}<button type="button" class="badge is-link" style="--c:${x.color}" data-uid="${esc(x.uid)}" title="${esc(`${x.name} 상세`)}">${esc(x.name)}</button><span class="badge" style="--c:${x.color}">${esc(K.name)}${tag ? ` · ${esc(tag)}` : ''}</span>${rankBadge}`}${houseBadge(c)}${certBadgeHTML(c)}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(title)}</h2>
        ${namesHeadHTML(c.names, kind === 'leader' ? 'person' : kind === 'capital' ? 'place' : 'polity')}
        ${names.length ? `<p class="aka">${esc(names.join(' · '))}</p>` : ''}
        ${seatWhen ? `<p class="when">${esc(seatWhen)}</p>` : `<p class="when">${esc(when)}${dayLine ? `<small class="when-sub">${esc(dayLine)}</small>` : ''}</p>`}
        ${unkWhere ? `<p class="range-note">${esc(unkWhere)}</p>` : ''}
        ${uncNotesHTML(c)}
        ${boundNoteHTML(x, c, `${kind}:${i}`)}
        ${dyn ? `<p class="aka">왕조 ${esc(dyn)}${c.dynastyAuto && !c.dynasty ? ' <small>(시작한 해로 짐작)</small>' : ''}</p>` : ''}
        ${kind === 'leader' ? leaderFigureHTML(x, c) : ''}
        ${kind === 'leader' || kind === 'cabinet' ? cellPersonHTML(x, kind, i, c) : ''}
        ${kind === 'leader' ? cellKinLinksHTML(x, i) : ''}
        ${kind === 'capital' ? placeHTML(c.placeId || c.city, '지명') : ''}
        ${namesRestHTML(c.names, kind === 'leader' ? 'person' : kind === 'capital' ? 'place' : 'polity')}
        <div class="desc${c.note ? '' : ' is-empty'}">${c.note ? esc(c.note) : '메모가 없습니다.'}</div>
        ${altHTML(c, { base: cellBase(x, c, { start, end, endAt }) })}
        <div class="cell-nav">
          ${prev ? `<button type="button" class="btn btn-sm" data-cell-nav="${kind}:${i - 1}" title="앞 ${esc(K.name)}">◀ ${esc(navName(prev))}</button>` : '<span></span>'}
          ${next ? `<button type="button" class="btn btn-sm" data-cell-nav="${kind}:${i + 1}" title="다음 ${esc(K.name)}">${esc(navName(next))} ▶</button>` : '<span></span>'}
        </div>
        ${echoSwitchHTML()}
        ${ownEventsHTML(evs)}
        ${echoSlotHTML()}
        ${kind === 'leader' || kind === 'cabinet' ? cellFiguresHTML(x, lo, hi) : ''}
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="cell-focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${key && (has || maker) ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-doc="${esc(key)}" type="button">${icon('file')}문서${has ? '' : ' 만들기'}</button>` : ''}
        ${maker ? `<button class="btn btn-sm" data-act="edit" type="button">✏️ ${esc(x.name)} 수정</button>` : ''}
        <button class="btn btn-sm" data-act="close" type="button">닫기</button>
      </div>`;
  }
  /** 지도자 칸 창의 '승계표에서 보기'(그 카드로 데려가 펼친 채 — 3-1) · '세계표에서 보기'(혈연이 적힌 사람만 — 그 사람의 카드로) */
  function cellKinLinksHTML(x, i) {
    const links = [];
    if (KVS() && (x.leaders || []).length >= 2) links.push(`<button type="button" class="linky" data-kin-succ="${i}">승계표에서 보기</button>`);
    const n = KV() ? HT.personOf(state.model, x, `leader:${i}`) : null;
    if (n && (n.parents.length || n.children.length) && kinWhere(n.key)) links.push(`<button type="button" class="linky" data-kin-fam="${esc(n.key)}">세계표에서 보기</button>`);
    return links.length ? `<p class="aka kv-links">${links.join(' · ')}</p>` : '';
  }
  /** 그 정권에 속하며 칸이 품는 구간 [lo, hi)에 걸친 사건들 [{ e, member }] (HT.cellSpan의 lo · hi — 이웃 칸과 겹치지 않음). 연도만 적은 한 해짜리 사건은 그해 한가운데로 봐서
      경계 해의 사건이 앞뒤 두 칸의 목록에 모두 들지 않게 (HT.echoEvents 안의 HT.spanHit) — 연표에서 진하게 남는 사건도 이 목록(같은 계산 — spotHighlight).
      그 정권의 띠 아래 접혀 숨은 소속의 사건(연표에서 이 띠 안에 그려짐)도 여기에 member(소속 이름)와 함께 */
  function cellEvents(x, lo, hi) {
    return spotCalc([{ uid: x.uid, start: lo, end: hi }], false).own;
  }
  /** 창의 '이 시기의 사건' 목록 (칸 · 시기 창) — 숨은 소속의 사건에는 그 이름 */
  function ownEventsHTML(evs) {
    return `<section class="sub-box"><h3>이 시기의 사건 <small>${evs.length}</small></h3>
          <ul class="year-events">${evs.map(({ e, member }) => `<li><button type="button" data-uid="${esc(e.uid)}"><span class="sr-dot${e.treaty ? ' is-treaty' : ''}" style="--c:${e.polityColor || e.color}"></span><span class="y">${esc(HT.formatRange(e))}</span><span class="t">${esc(e.title)}${member ? ` <span class="tr">소속 · ${esc(member)}</span>` : ''}</span></button></li>`).join('') || '<li class="muted">이 시기의 사건이 없습니다.</li>'}</ul>
        </section>`;
  }
  /** 메이커에서만 — 칸의 경계(HT.cellBounds)가 적힌 값과 다르게 잡힌 칸의 창에 그 까닭 한 줄: 경계 해는 뒤 칸의 것 · 날짜가 적힌 쪽이 경계.
      연표(보기 전용)에는 띄우지 않습니다(고칠 수 없는 화면에서 '날짜를 적으면'을 말하지 않게 — 일방통행). 경계가 적힌 값 그대로인 칸에는 없음 */
  function boundNoteHTML(x, c, ref) {
    if (!maker) return '';
    const b = HT.cellBound(x, ref);
    const own = parseCellRef(x, ref);
    if (!b || !own) return '';
    const raw = HT.cellSpan(c, x, null); // 이웃을 보지 않은 구간
    const word = own.K.name;
    /* 경계를 만든 이웃 — 그 이웃의 시작(끝)이 바로 이 경계인 칸. 같은 해에 여럿이 시작했으면 폭이 있는 칸(그해를 실제로 가져간 칸)을 먼저 */
    const near = (refs, t, key) => {
      const hits = refs.map(r => parseCellRef(x, r)).filter(q => q && Math.abs(cellSpanOf(x, q.c, `${q.kind}:${q.i}`)[key] - t) < 1e-9);
      return hits.find(q => (sp => sp.hi > sp.lo)(cellSpanOf(x, q.c, `${q.kind}:${q.i}`))) || hits[0] || null;
    };
    const nameOf = q => q.K.title(q.c, { leaderMode: state.ui.leaderLabel || 'auto' });
    /* 경계에 날짜 글이 적혀 있으면(이 칸이나 이웃의 시작 · 끝) 그 날짜, 없으면 연도만 */
    const dateAt = (t, ...cells) => [].concat(...cells.map(q => (q ? [q.startAt, q.endAt, q.endYAt] : []))).find(at => HT.atFits(at, t)) || null;
    const notes = [];
    if (b.hi < raw.hi - 1e-9 && !near(b.next, b.hi, 'lo') && (b.succ || []).some(q => Math.abs(q.start - b.hi) < 1e-9)) {
      /* 나라 경계: 후대가 이 나라가 끝나는 해에 시작 — 그해는 후대의 것 (HT.cellChains의 뒤 칸) */
      const q = b.succ.find(y => Math.abs(y.start - b.hi) < 1e-9);
      const at = dateAt(b.hi, c) || HT.atOf(q, 'start');
      if (at) notes.push(`${HT.formatDate(b.hi, at)}부터는 뒤를 이은 ${q.name}의 기간으로 셉니다 (날짜가 적힌 쪽이 경계)`);
      else notes.push(`${HT.formatYear(b.hi)}은 뒤를 이은 ${q.name}의 기간으로 셉니다 (경계 해는 뒤 나라의 것) — 날짜를 적으면 그 날짜가 경계가 됩니다`);
    } else if (b.hi < raw.hi - 1e-9) {
      const n = near(b.next, b.hi, 'lo');
      const them = n ? `${word} ${nameOf(n)}` : word; // 이웃이 없으면 임시 도읍 뒤에 다시 이어지는 정도
      const at = dateAt(b.hi, c, n && n.c);
      if (at) notes.push(`${HT.formatDate(b.hi, at)}부터는 ${n ? '다음' : '다시 이어지는'} ${them}의 기간으로 셉니다 (날짜가 적힌 쪽이 경계)`);
      else if (b.hi <= b.lo) notes.push(`${HT.formatYear(b.hi)}은 같은 해에 시작해 이어 가는 ${them}의 기간으로 셉니다 — 이 칸은 폭 없이 놓입니다. 날짜를 적으면 그 날짜에서 나뉩니다`);
      else notes.push(`${HT.formatYear(b.hi)}은 ${n ? '다음' : '다시 이어지는'} ${them}의 기간으로 셉니다 (경계 해는 뒤 칸의 것) — 날짜를 적으면 그 날짜가 경계가 됩니다`);
    }
    if (b.lo > raw.start + 1e-9) {
      const q = near(b.prev, b.lo, 'hi');
      /* 앞 칸의 끝 날짜가 경계(이 칸은 연도만)면 그날은 이 칸의 것 — 끝 날짜는 그날 0시(HT.endBound). 그날까지 앞 칸이면 이 칸의 시작에 그다음 날을 적으면 됨(맞닿은 날짜 — HT.chainBounds ㉠) */
      notes.push(`${HT.formatDate(b.lo, dateAt(b.lo, c, q && q.c))}부터 이 칸의 기간으로 셉니다 — ${q ? `앞 ${word} ${nameOf(q)}` : `앞 ${word}`}에 적힌 끝 날짜가 경계(그날 0시). 그날까지 앞 칸이면 이 칸의 시작에 그다음 날을 적습니다`);
    }
    return notes.length ? `<p class="range-note bound-note">${esc(notes.join(' · '))}</p>` : '';
  }

  /* ---------- 인물 ---------- */
  /** 활동 기록(service) 한 줄의 기간 글 (그 줄에 적은 기간 — 비웠으면 활동 시기). 칸의 미정(그 줄 · 물려받은 활동 시기의 미정)이면 그쪽은 '미정' */
  const serviceWhen = (f, s) => `${s.fromUnknown ? '미정' : whenText(s.from, s.fromAt)} ~ ${f.ongoing && s.to === f.endY ? '현재' : s.toUnknown ? '미정' : whenText(s.to, s.toAt)}`;
  /** 활동 기록 한 줄의 미정 안내 — 모르는 쪽이 연표의 어디에 놓였는지 (칸 창의 '연표에는 … 무렵부터'와 같은 말, 줄의 설명글에) */
  const serviceUnkNote = s =>
    [s.fromUnknown ? `시작 미정 — 연표에는 ${whenText(s.from)} 무렵부터 놓았습니다` : '', s.toUnknown ? `끝 미정 — 연표에는 ${endText(s.to)} 무렵까지 놓았습니다` : ''].filter(Boolean).join(' · ');
  /** 지도자 칸과 같은 사람으로 보이는 인물: 이름(다른 이름 포함)이 같고 시기가 겹치며, 같은 트랙이거나 그 정권을 섬긴 사람 — 새 입력 칸 없이 저절로 이어집니다 */
  const figureOfLeader = (x, c) => {
    const names = [c.name, c.temple, c.title, c.given].filter(Boolean);
    const end = c.end ?? x.endY;
    return (state.model.figures || []).find(f => [f.name].concat(f.aka || []).some(n => names.includes(n)) && f.spanMin <= end && c.start <= f.spanMax + 1 && (f.track === x.track || (f.services || []).some(s => s.polity === x))) || null;
  };
  /** 인물과 같은 사람으로 보이는 지도자 칸들 [{ p(정권), c(칸), i }] (figureOfLeader의 역) */
  const leadersOfFigure = f => {
    const out = [];
    for (const p of state.model.periods) (p.leaders || []).forEach((c, i) => figureOfLeader(p, c) === f && out.push({ p, c, i }));
    return out;
  };
  /** 지도자 칸 상세의 "같은 이름의 인물" 링크 (없으면 '') */
  function leaderFigureHTML(x, c) {
    const f = figureOfLeader(x, c);
    return f ? `<p class="aka">같은 이름의 인물: <button type="button" class="linky" data-uid="${esc(f.uid)}" title="인물 상세">${esc(f.name)}${f.role ? ` · ${esc(f.role)}` : ''}</button></p>` : '';
  }
  /** 같은 해 보기의 "그때 활동한 인물" — 필터를 통과한 인물 가운데 활동 시기가 [a, b)에 걸친 사람, 트랙마다 한 줄 */
  function yearFiguresHTML(a, b) {
    const list = state.visibleFigures.filter(f => f.start < b && HT.endBound(f.endY, f.endYAt) >= a);
    if (!list.length) return '';
    const byTrack = new Map();
    for (const f of list) byTrack.set(f.track, (byTrack.get(f.track) || []).concat([f]));
    return `<p class="when">그때 활동한 인물 <small>${list.length}명</small></p><ul class="year-eras">${[...byTrack]
      .map(([id, fs]) => `<li><span class="badge" style="--c:${trackOf(id).color}">${esc(trackOf(id).name)}</span> ${fs.map(f => `<button type="button" class="linky" data-uid="${esc(f.uid)}" title="${esc(`${f.role || '인물'} · 활동 ${HT.formatRange(f)}`)}">${esc(f.name)}</button>`).join(' · ')}</li>`)
      .join('')}</ul>`;
  }
  /** 범례의 인물 단 한 줄 — 자료에 인물이 있을 때만 */
  function figureLegendHTML() {
    if (!state.model || !(state.model.figures || []).length) return '';
    return `<ul><li><span class="lg-dot"><i class="lg-fig" style="--c:#a0bcc5"></i></span><span>인물 단(띠 안, 기간 막대 아래): 그 나라에서 활동한 사람의 활동 막대 — 이름은 들어갈 때만, 중요도가 높으면 굵게. 올리거나 고르면 생몰을 잇는 가는 수명선이 나타나고, 고르면 활동한 띠마다 그 기간이 밝아짐. 줄마다 두 단(넉넉하게 세 단 · 빽빽하게 한 단 · 조감은 없음)까지, 넘친 사람은 그 나라 상세의 인물 목록에. 막대가 너무 좁으면 “인물 n명” 한 칸</span></li></ul>`;
  }
  /** 정권을 섬긴 인물 한 줄 (역할 · 이름 · 직함 — 역할과 같으면 되풀이하지 않음 · 섬긴 기간). host를 주면 다른 정권(접힌 소속)을 섬긴 줄에 그 정권 이름을 덧붙입니다 */
  const servedRowHTML = ({ figure: f, service: s }, host) =>
    `<li><button type="button" data-uid="${esc(f.uid)}"><b>${esc(f.role || '인물')}</b><span>${esc(f.name)}${s.office && s.office !== f.role ? ` <i>${esc(s.office)}</i>` : ''}${host && s.polity && s.polity !== host ? ` <i>${esc(s.polity.name)}</i>` : ''}</span><small>${esc(serviceWhen(f, s))}</small></button></li>`;
  /** 정권 상세의 "인물" 목록 — 인물 단에서 넘쳐 그려지지 않은 사람까지 모두 (섬긴 기간 순).
      이 띠 아래에 접혀 숨은 소속 정권을 섬긴 사람도 함께 — 연표는 그 사람을 이 띠의 인물 단에 그리고, 빽빽할 때의 `인물 n명` 칸도 이 목록으로 옵니다(펼치면 소속 정권의 제 띠 · 제 상세로) */
  function figuresHTML(x) {
    if (x.kind !== 'period') return '';
    const folded = timeline.shownBandOf ? state.model.periods.filter(p => p !== x && (p.servedBy || []).length && timeline.shownBandOf(p.uid) === x.uid) : [];
    const list = (x.servedBy || []).concat(...folded.map(p => p.servedBy));
    if (!list.length) return '';
    if (folded.length) list.sort((a, b) => a.service.start - b.service.start || (b.figure.importance || 2) - (a.figure.importance || 2));
    return `<section class="sub-box" data-box="figures"><h3>인물 <small>${new Set(list.map(r => r.figure)).size}${folded.length ? ' · 접힌 소속 포함' : ''}</small></h3><ul class="succ-list">${list
      .map(r => servedRowHTML(r, x))
      .join('')}</ul></section>`;
  }
  /** 지도자·내각 칸 상세의 "이 시기의 인물" — 그 정권에서 활동한 사람 가운데 활동 기록의 기간이 그 칸이 품는 구간 [lo, hi)와 겹치는 사람.
      활동 기록의 기간은 인물 창의 조명과 같은 [시작, 끝) — 적힌 끝 해에 시작한 다음 칸에는 들지 않게 (HT.spanMeets) */
  function cellFiguresHTML(x, lo, hi) {
    const list = (x.servedBy || []).filter(r => HT.spanMeets(r.service.start, r.service.endY, lo, hi));
    if (!list.length) return '';
    return `<section class="sub-box"><h3>이 시기의 인물 <small>${list.length}</small></h3><ul class="succ-list">${list
      .map(r => servedRowHTML(r))
      .join('')}</ul></section>`;
  }
  /** 사건 상세의 "관련 인물" 칩 — 인물을 찾았으면 누르면 인물 상세, 못 찾은 이름은 글로만 */
  function eventFiguresHTML(x) {
    const refs = x.kind === 'event' ? x.figureRefs || [] : [];
    if (!refs.length) return '';
    return `<section class="sub-box"><h3>관련 인물 <small>${refs.length}</small></h3><div class="chips">${refs
      .map(r => {
        const f = r.uid ? state.model.byUid.get(r.uid) : null;
        return f ? `<button type="button" class="chip is-figure" data-uid="${esc(f.uid)}" style="--c:${f.color}" title="${esc(`${f.name}${f.role ? ` · ${f.role}` : ''} — 인물 상세`)}">${esc(f.name)}</button>` : `<span class="chip is-figure is-missing" title="이 이름의 인물을 찾지 못했습니다">${esc(r.name)}</span>`;
      })
      .join('')}</div></section>`;
  }
  /** 인물 창: 이름 · 다른 이름 · 역할 · 생몰(향년) · 가문 · 활동 기록 · 관련 사건 · 같은 시기의 지도자 · 설명 · 출처 · 문서.
      연표에는 섬긴 띠마다 그 기간이 조명됩니다(DETAIL_KINDS의 enter) */
  function figureDetailHTML(x) {
    const track = trackOf(x.track);
    const badge = (key, text, color, title) => `<button type="button" class="badge is-link" style="--c:${color}" data-doc="${esc(key)}" title="${esc(title || `${text} 문서`)}">${esc(text)}</button>`;
    const life = HT.figureLife(x);
    const imp = x.importance || 2;
    const source = x.source ? (/^https?:\/\//i.test(x.source) ? `<a href="${esc(x.source)}" target="_blank" rel="noopener noreferrer">${esc(x.source)}</a>` : esc(x.source)) : '';
    const svc = x.services || [];
    /* 짐작한 쪽만 밝힙니다 — 한쪽 끝만 짐작했으면 적은 쪽 연도까지 짐작처럼 읽히지 않게 */
    const guessFrom = svc.some(s => s.given) ? '활동 기록' : '생몰';
    const guessed = x.startAuto && x.endAuto ? ` <small>(${guessFrom}에서 짐작)</small>` : x.startAuto ? ` <small>(시작은 ${guessFrom}에서 짐작)</small>` : x.endAuto ? ` <small>(끝은 ${guessFrom}에서 짐작)</small>` : '';
    /* 활동 시기의 미정: 모르는 쪽이 연표의 어디에 놓였는지 (칸 창 · 시대 창과 같은 말) */
    const actUnk = [x.startUnknown ? `시작 미정 — 연표에는 ${whenText(x.start)} 무렵부터 놓았습니다` : '', x.endUnknown ? `끝 미정 — 연표에는 ${endText(x.endY)} 무렵까지 놓았습니다` : ''].filter(Boolean).join(' · ');
    const twins = leadersOfFigure(x);
    /* 같은 시기의 지도자: 활동한 정권마다, 그 활동 기록의 기간 [시작, 끝)(인물 창의 조명과 같음)과 지도자 칸이 품는 구간 [lo, hi)가 겹치는 지도자
       (칸의 경계 — 경계 해는 뒤 지도자의 것이라, 1988년에 끝난 활동은 1988년에 시작한 지도자와 겹치지 않음) */
    const rulers = [];
    const ruled = new Set(); // 한 나라를 두 번 섬겼으면(승진 · 복귀) 두 기간에 걸친 지도자가 한 번만 나오게
    for (const s of svc)
      if (s.polity)
        (s.polity.leaders || []).forEach((c, i) => {
          const key = `${s.polity.uid}:${i}`;
          const { lo, hi } = cellSpanOf(s.polity, c, `leader:${i}`);
          if (ruled.has(key) || !HT.spanMeets(s.start, s.endY, lo, hi)) return;
          ruled.add(key);
          rulers.push({ p: s.polity, c, i });
        });
    rulers.sort((a, b) => a.c.start - b.c.start);
    /* 서명한 조약(모델의 signedTreaties — 조약의 서명자 이름이 이 인물의 이름 · 다른 이름과 같은 것): 조약 창의 서명자 링크의 거꾸로. 관련 사건 목록에서는 빼서 두 번 나오지 않게 */
    const signed = (x.signedTreaties || []).filter(r => state.model.byUid.has(r.event.uid));
    const evs = (x.events || []).filter(e => !signed.some(r => r.event === e)).sort((a, b) => a.start - b.start);
    const own = !!maker && maker.isOwn(x); // 메이커: 고치는 DLC의 제 인물(지우면 삭제) — 남의 인물은 패치로 고치고, 지우는 대신 숨깁니다 (시대 · 사건 상세와 같은 규칙)
    const patched = !!maker && maker.hasPatch(x.uid);
    return `
      <div class="detail-head">
        <div class="badges">${badge(`track:${track.id}`, track.name, track.color)}${x.polityUid ? badge(x.polityUid, x.polityName, x.polityColor) : ''}<span class="badge is-kind is-figure">인물${x.role ? ` · ${esc(x.role)}` : ''}</span>${x.houseId ? houseBadge(x) : x.house ? `<span class="badge" title="가문">${esc(x.house)}</span>` : ''}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(x.name)}</h2>
        ${namesHeadHTML(x.names, 'person')}
        ${x.aka && x.aka.length ? `<p class="aka">다른 이름: ${esc(x.aka.join(' · '))}</p>` : ''}
        ${life ? `<p class="when">${esc(life)}</p>` : ''}
        <p class="${life ? 'aka' : 'when'}">활동 ${esc(HT.formatRange(x))}${guessed}</p>
        ${actUnk ? `<p class="range-note">${esc(actUnk)}</p>` : ''}
        ${twins.length ? `<p class="aka">같은 이름의 지도자: ${twins.map(t => `<button type="button" class="linky" data-cell-of="${esc(t.p.uid)}" data-cell="leader:${t.i}">${esc(t.p.name)} ${esc(HT.leaderLabel(t.c, state.ui.leaderLabel || 'auto'))}</button>`).join(' · ')}</p>` : ''}
        ${figurePersonHTML(x, twins)}
        ${namesRestHTML(x.names, 'person')}
        <div class="desc${x.description ? '' : ' is-empty'}">${x.description ? esc(x.description) : '설명이 없습니다.'}</div>
        ${altHTML(x, { base: figureBase(x), figure: true })}
        <section class="sub-box"><h3>활동 기록 <small>${svc.length}</small></h3>${
          svc.length
            ? `<ul class="succ-list">${svc
                .map(s => `<li><button type="button"${s.polity ? ` data-uid="${esc(s.polityUid)}"` : ' disabled'}${serviceUnkNote(s) ? ` title="${esc(serviceUnkNote(s))}"` : ''}><b>${esc(s.office || '활동')}</b><span>${esc(s.polityName)}${altTagHTML(s)}${s.polity && s.polity.track !== x.track ? ` <i>${esc(trackOf(s.polity.track).name)}</i>` : ''}${s.note ? ` <i>${esc(s.note)}</i>` : ''}${s.polity ? '' : ' <i>연표에서 찾지 못한 정권</i>'}${s.auto ? ' <i>활동 시기로 짐작한 자리</i>' : ''}</span><small>${esc(serviceWhen(x, s))}</small></button></li>`)
                .join('')}</ul>${subAltsHTML(svc.map(s => ({ title: `${s.polityName}${s.office ? ` ${s.office}` : ''} 활동 기록`, u: s, base: { start: s.from, startAt: s.fromAt, end: s.to, endAt: s.toAt, startUnknown: s.fromUnknown, endUnknown: s.toUnknown, ongoing: !!(x.ongoing && s.to === x.endY) } })))}`
            : '<p class="succ-cap">그 시기의 같은 트랙 정권을 찾지 못했습니다.</p>'
        }</section>
        ${svc.some(s => s.shown && s.polityUid) ? `${echoSwitchHTML()}${echoSlotHTML()}` : ''}
        ${evs.length ? `<section class="sub-box"><h3>관련 사건 <small>${evs.length}</small></h3><ul class="year-events">${evs.map(e => `<li><button type="button" data-uid="${esc(e.uid)}"><span class="sr-dot${e.treaty ? ' is-treaty' : ''}" style="--c:${e.polityColor || e.color}"></span><span class="y">${esc(HT.formatRange(e))}</span><span class="t">${esc(e.title)}</span></button></li>`).join('')}</ul></section>` : ''}
        ${signed.length ? `<section class="sub-box" data-box="signed"><h3>서명한 조약 <small>${signed.length}</small></h3><ul class="year-events">${signed.map(({ event: e, party, signer }) => `<li><button type="button" data-uid="${esc(e.uid)}" title="${esc(`${party.name} 쪽 서명${signer.title ? ` — ${signer.title}` : ''}`)}"><span class="sr-dot is-treaty" style="--c:${e.polityColor || e.color}"></span><span class="y">${esc(HT.formatRange(e))}</span><span class="t">${esc(e.title)} <span class="tr">${esc(party.name)}${signer.title ? ` · ${esc(signer.title)}` : ''}</span></span></button></li>`).join('')}</ul></section>` : ''}
        ${rulers.length ? `<section class="sub-box"><h3>같은 시기의 지도자 <small>${rulers.length}</small></h3><ul class="kid-list">${rulers.map(r => `<li><button type="button" data-cell-of="${esc(r.p.uid)}" data-cell="leader:${r.i}"><b>${esc(cellWhen(r.c, false, r.p))}</b><span>${esc(HT.leaderLabel(r.c, state.ui.leaderLabel || 'auto'))}${svc.filter(s => s.polity).length > 1 ? ` <i>${esc(r.p.name)}</i>` : ''}</span></button></li>`).join('')}</ul></section>` : ''}
        ${subdocsHTML(x.uid)}
        ${patchHTML(x)}
        ${x.tags && x.tags.length ? `<div class="tags">${x.tags.map(t => `<span class="tag">#${esc(t)}</span>`).join('')}</div>` : ''}
        <dl>
          <dt>제공</dt><dd>${esc(x.packName)}${own ? ' <b>(고치는 중인 DLC)</b>' : x.overridden ? ' <b>(옮기지 못한 옛 내 수정)</b>' : ''}</dd>
          <dt>중요도</dt><dd>${'★'.repeat(imp)}${'☆'.repeat(3 - imp)}</dd>
          ${source ? `<dt>출처</dt><dd>${source}</dd>` : ''}
        </dl>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="focus" type="button">${icon('zoom-in')}이 위치로</button>
        ${wikiBtnText(x.uid) ? `<button class="btn btn-sm" data-act="wiki" type="button" title="이 인물의 위키 문서">${wikiBtnText(x.uid)}</button>` : ''}
        ${maker ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
        ${patched ? '<button class="btn btn-sm" data-act="revert" type="button" title="고치는 중인 DLC가 이 인물에 건 패치를 걷습니다">↩ 원래대로</button>' : ''}
        ${maker ? `<button class="btn btn-sm btn-danger" data-act="delete" type="button">${own ? '🗑 삭제' : '🙈 숨기기'}</button>` : ''}
      </div>`;
  }

  /* ---------- 시기 구분(학계) ---------- */
  /** 시기 창: 체계 · 이름 · 기간(비운 경계는 어디서 왔는지) · 메모 · 같은 체계 안의 앞뒤 시기 · 체계 견주기 · 그동안의 사건 · 문서 */
  function phaseDetailHTML(x, ref) {
    const { c } = ref;
    const track = trackOf(x.track);
    const g = (x.phaseSchemes || [])[c.si] || { spans: [c], note: '' };
    const prev = g.spans[c.ii - 1];
    const next = g.spans[c.ii + 1];
    const { start, end, endAt, lo, hi } = cellSpanOf(x, c, `phase:${c.ci}`);
    const key = HT.docKey.cell(x.uid, 'phases', c);
    const has = !!docText(key);
    const evs = cellEvents(x, lo, hi); // 칸 창과 같은 구간(칸의 경계 — 같은 체계의 앞뒤 시기와 겹치지 않음)
    const last = c.ii === g.spans.length - 1;
    const whence = [
      c.startAuto && !c.startUnknown ? (c.ii === 0 ? '시작은 정권 시작' : '시작은 앞 시기의 끝') : '',
      c.endAuto && !c.endUnknown ? (last ? '끝은 정권 끝' : '끝은 다음 시기의 시작') : '',
      c.guess ? '앞뒤 경계를 알 수 없어 그 사이를 고르게 나눠 자리만 잡음' : '',
      /* 칸의 미정과 같은 안내: 모르는 쪽이 연표의 어디에 놓였는지 (배치용 연도를 적었으면 그 자리) */
      c.startUnknown && !c.guess ? `시작 미정 — 연표에는 ${whenText(start)} 무렵부터 놓았습니다` : '',
      c.endUnknown && !c.guess ? `끝 미정 — 연표에는 ${endText(end)} 무렵까지 놓았습니다` : '',
    ].filter(Boolean).join(' · ');
    const nav = (q, word) => (q ? `<button type="button" class="btn btn-sm" data-cell-nav="phase:${q.ci}" title="${word} 시기">${word === '앞' ? `◀ ${esc(q.name)}` : `${esc(q.name)} ▶`}</button>` : '<span></span>');
    return `
      <div class="detail-head">
        <div class="badges"><button type="button" class="badge is-link" style="--c:${track.color}" data-doc="track:${esc(track.id)}" title="${esc(`${track.name} 문서`)}">${esc(track.name)}</button><button type="button" class="badge is-link" style="--c:${x.color}" data-uid="${esc(x.uid)}" title="${esc(`${x.name} 상세`)}">${esc(x.name)}</button><span class="badge badge-phase">시기 구분(학계)${c.scheme ? ` · ${esc(c.scheme)}` : ''}</span>${certBadgeHTML(c)}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(c.name)}</h2>
        ${c.scheme ? `<p class="aka">체계 ${esc(c.scheme)}${g.note ? ` — ${esc(g.note)}` : ''}</p>` : g.note ? `<p class="aka">${esc(g.note)}</p>` : ''}
        <p class="when">${esc(HT.phaseRangeText(c, x))}${whence ? `<small class="when-sub">${esc(whence)}</small>` : ''}</p>
        ${uncNotesHTML(c)}
        ${boundNoteHTML(x, c, `phase:${c.ci}`)}
        <div class="desc${c.note ? '' : ' is-empty'}">${c.note ? esc(c.note) : '메모가 없습니다.'}</div>
        ${altHTML(c, { base: cellBase(x, c, { start, end, endAt }) })}
        <div class="cell-nav">${nav(prev, '앞')}${nav(next, '다음')}</div>
        ${phaseCompareHTML(x, c)}
        ${echoSwitchHTML()}
        ${ownEventsHTML(evs)}
        ${echoSlotHTML()}
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="cell-focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${has || maker ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-doc="${esc(key)}" type="button">${icon('file')}문서${has ? '' : ' 만들기'}</button>` : ''}
        ${maker ? `<button class="btn btn-sm" data-act="edit" type="button">✏️ ${esc(x.name)} 수정</button>` : ''}
        <button class="btn btn-sm" data-act="close" type="button">닫기</button>
      </div>`;
  }
  /** 체계 견주기: 그 정권의 모든 체계를 같은 시간 축에 나란히 — 경계가 어떻게 다른지 한눈에. 지금 시기는 진하게, 그 경계에 가는 세로선.
      막대를 누르면 그 시기로. 막대가 좁아 이름이 들어가지 않으면 이름을 빼고 설명글로만 (fitPhaseBars) */
  function phaseCompareHTML(x, cur) {
    const schemes = x.phaseSchemes || [];
    if (!schemes.length) return '';
    const all = schemes.flatMap(g => g.spans);
    const t0 = Math.min(x.start, ...all.map(c => c.start));
    const t1 = Math.max(x.endY, ...all.map(c => c.end));
    const pct = t => (t1 > t0 ? HT.clamp(((t - t0) / (t1 - t0)) * 100, 0, 100) : 0);
    const bar = c => {
      const l = pct(c.start);
      const w = Math.max(0, pct(c.end) - l);
      const tip = `${c.scheme ? `${c.scheme} · ` : ''}${c.name} · ${HT.phaseRangeText(c, x)}`;
      return `<button type="button" class="ph-bar${c === cur ? ' is-cur' : ''}${c.startUnknown ? ' unk-s' : ''}${c.endUnknown ? ' unk-e' : ''}" data-cell-nav="phase:${c.ci}" style="left:${l.toFixed(3)}%;width:${w.toFixed(3)}%" title="${esc(tip)}" aria-label="${esc(tip)}"><b>${esc(c.name)}</b></button>`;
    };
    const guides = [cur.start, cur.end].map(t => `<i class="ph-guide" style="left:${pct(t).toFixed(3)}%"></i>`).join('');
    return `<section class="sub-box"><h3>${schemes.length > 1 ? `체계 견주기 <small>${schemes.length}</small>` : '시기 한눈에'}</h3>
      <div class="ph-cmp"><div class="ph-rows">${schemes
        .map(g => `<div class="ph-row${g.si === cur.si ? ' is-cur' : ''}">${schemes.length > 1 || g.scheme ? `<span class="ph-sch">${esc(g.scheme || '이름 없는 체계')}</span>` : ''}<div class="ph-track">${g.spans.map(bar).join('')}</div></div>`)
        .join('')}${guides}</div>
        <div class="ph-axis"><span>${esc(whenText(t0))}</span><span>${esc(endText(t1))}</span></div></div></section>`;
  }
  /** 견주기 막대에 이름이 다 들어가지 않으면 이름을 뺍니다(설명글에는 남음) — 창의 폭이 바뀔 때마다 다시 */
  function fitPhaseBars() {
    const box = detailEl.querySelector('.ph-cmp');
    if (!box) return;
    const fit = () => box.querySelectorAll('.ph-bar').forEach(bar => {
      const b = bar.querySelector('b');
      if (b) bar.classList.toggle('is-bare', b.scrollWidth > b.clientWidth + 0.5);
    });
    fit();
    if (typeof ResizeObserver === 'function') new ResizeObserver(fit).observe(box);
  }
  /** 정권 상세의 '시기 구분(학계)' 목록: 체계별로, 누르면 그 시기로 · 📄는 문서 */
  function phasesHTML(x) {
    const schemes = x.phaseSchemes || [];
    if (!schemes.length) return '';
    const n = schemes.reduce((s, g) => s + g.spans.length, 0);
    return `<section class="sub-box"><h3>시기 구분(학계) <small>${schemes.length > 1 ? `체계 ${schemes.length} · ` : ''}시기 ${n}</small></h3>${schemes
      .map(g => `${schemes.length > 1 || g.scheme ? `<p class="succ-cap">${esc(g.scheme || '이름 없는 체계')}${g.note ? ` <small>${esc(g.note)}</small>` : ''}</p>` : g.note ? `<p class="succ-cap">${esc(g.note)}</p>` : ''}<ul class="cell-list">${g.spans
        .map(c => {
          const key = HT.docKey.cell(x.uid, 'phases', c);
          const has = !!docText(key);
          return `<li><button type="button" data-year="${c.start}" data-prec="${precOf(c)}"><b>${esc(HT.phaseRangeText(c, x))}</b><span>${esc(c.name)}${altTagHTML(c)}${c.note ? ` <i>${esc(c.note)}</i>` : ''}</span></button>${cellDocBtn(key, has)}</li>`; // 📄: 연표(보기 전용)에서는 문서가 있는 시기에만
        })
        .join('')}</ul>`)
      .join('')}</section>`;
  }
  /** 같은 해 보기: 그때 각 나라의 시기 구분 — 누르면 그 시기의 창 */
  function yearPhasesHTML(eras, a, b) {
    const rows = [];
    for (const { track, periods } of eras)
      for (const p of periods) {
        const hits = (p.phaseSchemes || []).flatMap(g => g.spans.filter(c => cellIn(p, c, `phase:${c.ci}`, a, b))); // 칸의 경계 — 바뀐 해에는 뒤 시기만
        if (hits.length) rows.push(`<li><span class="badge" style="--c:${track.color}">${esc(track.name)}</span> <span class="yp-name">${esc(p.name)}</span> ${hits.map(c => `<button type="button" class="linky" data-open-cell="phase:${c.ci}" data-cell-uid="${esc(p.uid)}" title="${esc(`${c.scheme ? `${c.scheme} · ` : ''}${c.name} · ${HT.phaseRangeText(c, p)}`)}">${esc(c.name)}</button>${c.scheme ? `<small>${esc(c.scheme)}</small>` : ''}`).join(' · ')}</li>`);
      }
    return rows.length ? `<p class="when">그때의 시기 구분(학계)</p><ul class="year-eras year-phases">${rows.join('')}</ul>` : '';
  }
  /* 같은 해 보기의 시기(누르면 그 정권의 시기 창) — 상세 창의 다른 단추들과 겹치지 않는 제 속성(data-open-cell)으로 */
  detailEl.addEventListener('click', e => {
    const b = e.target.closest('[data-open-cell]');
    if (b && state.model.byUid.has(b.dataset.cellUid)) openDetail(b.dataset.cellUid, { cell: b.dataset.openCell });
  });

  /* ---------- 지위 ---------- */
  /** 지위의 짙기 견본 (연표와 같은 표 HT.RANK_MIX) */
  const rankChip = (c, color) => `<i class="rk-chip" style="--c:${color};--mix:${HT.RANK_MIX[c.level || 0]}%" aria-hidden="true"></i>`;
  /** 앞 지위 → 이 지위: 승격 ▲ · 격하 ▼ (두 서열을 다 알 때만 — 연표에는 두지 않고 이 목록들에서만) */
  const rankMove = (a, b) => (!a || a.tier == null || b.tier == null || a.tier === b.tier ? '' : b.tier > a.tier ? '<em class="rk-move is-up">▲ 승격</em>' : '<em class="rk-move is-down">▼ 격하</em>');
  const rankRange = (c, p) => HT.formatRange({ start: c.start, startAt: c.startAt, end: c.end, endAt: c.endAt, startUnknown: c.startUnknown, endUnknown: c.endUnknown, ongoing: HT.cellToNow(c, p) }); // 칸의 미정이면 그쪽은 '미정', 진행 중인 정권의 끝까지면 '현재'
  /** 지위 목록 한 줄: 기간 · 짙기 견본 · 지위 · 승격/격하 · 메모 (attr = 누르면 할 일) */
  const rankItem = (x, list, j, attr, cur) => {
    const c = list[j];
    return `<li${cur ? ' class="is-cur"' : ''}><button type="button" ${attr}><b>${esc(rankRange(c, x))}</b><span>${rankChip(c, x.color)}${esc(c.name)}${rankMove(list[j - 1], c)}${altTagHTML(c)}${c.note ? ` <i>${esc(c.note)}</i>` : ''}</span></button></li>`;
  };
  /** 지위 창: 지위 · 서열 · 기간(비운 경계가 어디서 왔는지) · 메모 · 앞뒤 지위 · 지위 변천(승격 ▲ · 격하 ▼) · 그 기간의 지도자들 · 정권 문서로 가는 길
      (지위 칸에는 문서를 달지 않습니다 — 칸 창과 같은 길로 그 기간이 조명되고 그 시기의 사건이 강조됩니다) */
  function rankDetailHTML(x, ref) {
    const { c, i, list } = ref;
    const track = trackOf(x.track);
    const { start, end, endAt } = cellSpanOf(x, c, `rank:${i}`);
    const last = i === list.length - 1;
    const whence = [
      c.derived ? '지도자에게 적힌 지위에서 끌어냄' : '',
      c.startAuto && !c.startUnknown ? '시작은 정권 시작' : '',
      c.endAuto && !c.derived && !c.endUnknown ? (last ? '끝은 정권 끝' : '끝은 다음 지위의 시작') : '',
      /* 칸의 미정과 같은 안내: 모르는 쪽이 연표의 어디에 놓였는지 (배치용 연도를 적었으면 그 자리, 아니면 앞 지위의 끝 · 다음 지위의 시작 · 정권의 처음과 끝) */
      c.startUnknown ? `시작 미정 — 연표에는 ${whenText(start)} 무렵부터 놓았습니다` : '',
      c.endUnknown ? `끝 미정 — 연표에는 ${endText(end)} 무렵까지 놓았습니다` : '',
    ].filter(Boolean).join(' · ');
    const tierLine = !c.def
      ? '사전에 없는 지위 — 서열 없이 중립 색으로 그립니다'
      : `${HT.rankTierText(c)}${c.level ? ` · 짙기 ${c.level}단계(넷 중)` : ' · 중립 색'}${c.def.name !== c.name ? ` · 사전의 "${c.def.name}"과(와) 같은 서열로 봄` : ''}`;
    const inSpan = l => (l.start < end || (end === start && l.start === start)) && (l.end ?? x.endY) > start;
    const rulers = (x.leaders || []).map((l, li) => ({ l, li })).filter(({ l }) => l && l.start != null && inSpan(l));
    const has = !!docText(x.uid);
    const nav = (j, word) => (list[j] ? `<button type="button" class="btn btn-sm" data-cell-nav="rank:${j}" title="${word} 지위">${word === '앞' ? `◀ ${esc(list[j].name)}` : `${esc(list[j].name)} ▶`}</button>` : '<span></span>');
    return `
      <div class="detail-head">
        <div class="badges"><button type="button" class="badge is-link" style="--c:${track.color}" data-doc="track:${esc(track.id)}" title="${esc(`${track.name} 문서`)}">${esc(track.name)}</button><button type="button" class="badge is-link" style="--c:${x.color}" data-uid="${esc(x.uid)}" title="${esc(`${x.name} 상세`)}">${esc(x.name)}</button><span class="badge badge-rank" style="--c:${x.color}">지위${c.tier != null ? ` · 서열 ${esc(c.tier)}` : ''}</span>${certBadgeHTML(c)}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${rankChip(c, x.color)}${esc(c.name)}</h2>
        <p class="aka">${esc(tierLine)}${c.def && c.def.description ? ` — ${esc(c.def.description)}` : ''}</p>
        <p class="when">${esc(rankRange(Object.assign({}, c, { start, end, endAt }), x))}${whence ? `<small class="when-sub">${esc(whence)}</small>` : ''}</p>
        ${uncNotesHTML(c)}
        ${boundNoteHTML(x, c, `rank:${i}`)}
        <div class="desc${c.note ? '' : ' is-empty'}">${c.note ? esc(c.note) : '메모가 없습니다.'}</div>
        ${altHTML(c, { base: cellBase(x, c, { start, end, endAt }) })}
        <div class="cell-nav">${nav(i - 1, '앞')}${nav(i + 1, '다음')}</div>
        ${echoSwitchHTML()}
        <section class="sub-box"><h3>지위 변천 <small>${list.length}</small></h3><ul class="cell-list is-ranks">${list.map((q, j) => rankItem(x, list, j, `data-cell-nav="rank:${j}"`, j === i)).join('')}</ul></section>
        <section class="sub-box"><h3>이 지위의 지도자 <small>${rulers.length}</small></h3><ul class="cell-list is-leaders">${
          rulers
            .map(({ l, li }) => `<li><button type="button" data-cell-nav="leader:${li}"><b>${esc(cellWhen(l, false, x))}</b><span>${l.ordinal != null ? `<em>${l.ordinal}대</em> ` : ''}${esc(HT.leaderLabel(l, state.ui.leaderLabel || 'auto'))}${l.rank && l.rank !== c.name ? ` <i>지위 ${esc(l.rank)}</i>` : ''}</span></button></li>`)
            .join('') || '<li class="muted">이 기간의 지도자가 적혀 있지 않습니다.</li>'
        }</ul></section>
        ${echoSlotHTML()}
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="cell-focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${has || maker ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-doc="${esc(x.uid)}" type="button" title="지위 칸에는 문서를 달지 않습니다 — 이 정권의 문서로">${icon('file')}${esc(x.name)} 문서${has ? '' : ' 만들기'}</button>` : ''}
        ${maker ? `<button class="btn btn-sm" data-act="edit" type="button">✏️ ${esc(x.name)} 수정</button>` : ''}
        <button class="btn btn-sm" data-act="close" type="button">닫기</button>
      </div>`;
  }
  /** 정권 창의 '지위' 목록: 기간 · 짙기 · 승격 ▲ · 격하 ▼ — 누르면 그 시기로 */
  function ranksHTML(x) {
    const list = x.rankSpans || [];
    if (!list.length) return '';
    return `<section class="sub-box"><h3>지위 <small>${list.length}${list[0].derived ? ' · 지도자에게 적힌 지위에서 끌어냄' : ''}</small></h3><ul class="cell-list is-ranks">${list
      .map((c, j) => rankItem(x, list, j, `data-year="${c.start}" data-prec="${precOf(c)}"`, false))
      .join('')}</ul></section>`;
  }
  /** 같은 해 보기: 나라 이름 뒤에 그때의 지위(누르면 지위 창) — 그 구간에 바뀌었으면 나중 지위 */
  function yearRankHTML(p, a, b) {
    const hits = (p.rankSpans || []).filter(c => cellIn(p, c, `rank:${c.i}`, a, b)); // 칸의 경계 (바뀐 해는 뒤 지위의 것 — 그래도 여럿이면 나중 지위)
    const c = hits[hits.length - 1];
    return c ? ` <button type="button" class="yr-rank" data-open-cell="rank:${c.i}" data-cell-uid="${esc(p.uid)}" style="--c:${p.color};--mix:${HT.RANK_MIX[c.level || 0]}%" title="${esc(`${p.name}의 그때 지위 — ${HT.rankFull(c)} · ${rankRange(c, p)}`)}">${esc(c.name)}</button>` : '';
  }

  /* ---------- 승계표 · 세계표 · 가문 조명 · 성씨 창 · 계보 전용 인물 (D1 — 10건 1 · 2) ----------
     그리기는 js/kin-view.js(HT.kinView), 자료는 js/core.js의 계약 도우미(HT.kinSkeleton · kinOf · successionRows · polityHead · houseHead · houseUnder · houseSpans · houseEras).
     도우미가 없으면(옛 core.js) 단추 · 줄 · 막대를 두지 않아 지금 화면 그대로입니다. 연표에서 칩은 링크뿐, 메이커 미리 보기에서만 ✏️ · 빈 값의 점선 칩(HT.maker.kin.editHead) */
  const KV = () => (HT.kinView && HT.kinView.ready() ? HT.kinView : null);
  const KVS = () => (HT.kinView && HT.kinView.succReady() ? HT.kinView : null);
  const hasFn = name => typeof HT[name] === 'function';
  /** 접힘 기억 — 보기 설정(ui.kinFold[정권 uid · 뼈대 열쇠]), 파일이 아님. 저장은 모아서 한 번 */
  let kinSaveTimer = 0;
  const kinStore = {
    get: id => (state.ui.kinFold && typeof state.ui.kinFold === 'object' ? state.ui.kinFold[id] || null : null),
    set: (id, v) => {
      const f = state.ui.kinFold && typeof state.ui.kinFold === 'object' ? state.ui.kinFold : (state.ui.kinFold = {});
      delete f[id];
      f[id] = v;
      const ks = Object.keys(f);
      if (ks.length > 80) for (const k of ks.slice(0, ks.length - 80)) delete f[k]; // 오래 열지 않은 표의 기억부터
      clearTimeout(kinSaveTimer);
      kinSaveTimer = setTimeout(() => HT.store.set(K.ui, state.ui), 300);
    },
  };
  /** 계보 전용 인물의 가문 — 사람 자리의 가문(적은 것 → 파조 → 물려받기) */
  const kinFigureHouse = f => {
    const n = HT.personOf(state.model, f);
    const id = (n && n.houseId) || f.houseId;
    return id && state.model.houseMap ? state.model.houseMap.get(id) || null : null;
  };
  /** 사람 자리 열쇠('f:…' · 'c:<정권 uid>|leader:3')의 { key: 뼈대 열쇠, at } (없으면 null) */
  const kinWhere = personKey => {
    if (!KV() || !personKey) return null;
    try {
      if (hasFn('kinOfPerson')) return HT.kinOfPerson(state.model, personKey) || null;
    } catch (err) {
      return null;
    }
    return null;
  };
  /** 가문 창 · 세계표 단추가 여는 뼈대: 뿌리 가문(본가 길의 맨 위)의 'kin:<id>' */
  const kinRootKey = h => `kin:${h.path && h.path.length ? h.path[0] : h.id}`;

  /* 머리 칩 (3-2 · 4-2): [● 구분] › [● 민족] › [● 국가 이름 | 본관 성씨 › 이름] · [꼬리표] … — 칩 꼴은 상세 창 머리 배지, 사이 기호는 가문 창 본가 길의 › */
  const kinEditable = () => !!(maker && HT.maker && HT.maker.kin && typeof HT.maker.kin.editHead === 'function' && (typeof HT.maker.kin.ready !== 'function' || HT.maker.kin.ready()));
  const HEAD_SLOTS = { polity: [['track', '구분'], ['people', '민족'], ['name', '']], house: [['track', '구분'], ['people', '민족'], ['surname', '본관 성씨'], ['name', '']] };
  function headChipsHTML(kind, x) {
    let chips = [];
    try {
      chips = (kind === 'polity' ? HT.polityHead : HT.houseHead)(state.model, x) || [];
    } catch (err) {
      chips = [];
    }
    const m = state.model;
    const edit = kinEditable();
    const target = c => {
      const u = c.uid || '';
      if (!u) return null;
      if (/^(track|people):/.test(u)) return docText(u) ? { doc: u } : null; // 구분 · 민족 → 문서가 있으면 문서 창, 없으면 누를 수 없음
      return detailTarget(u) ? { uid: u } : null; // 국가 → 나라 상세 · 이름 → 가문 창 · 본관 성씨 → 성씨 창
    };
    const colorOf = c => {
      const u = c.uid || '';
      if (/^track:/.test(u)) return trackOf(u.slice(6)).color;
      if (/^people:/.test(u)) return ((m.peopleMap && m.peopleMap.get(u.slice(7))) || {}).color || x.peopleColor || 'var(--text-3)';
      return x.color || 'var(--text-3)';
    };
    const pen = c => (edit ? `<button type="button" class="kv-pen" data-kin-edit="${esc(c.field || c.role)}" data-kin-kind="${kind}" data-kin-uid="${esc(x.uid)}" aria-label="${esc(`${c.text} 고치기`)}" title="고치기">✏️</button>` : '');
    const one = c => {
      const t = target(c);
      const cls = `badge kv-chip${t ? ' is-link' : ''}${c.auto ? ' is-auto' : ''}`;
      const tip = c.title ? ` title="${esc(c.title)}"` : '';
      const attr = t ? (t.doc ? ` data-doc="${esc(t.doc)}"` : ` data-uid="${esc(t.uid)}"`) : '';
      const body = t ? `<button type="button" class="${cls}" style="--c:${colorOf(c)}"${attr}${tip}>${esc(c.text)}</button>` : `<span class="${cls}" style="--c:${colorOf(c)}"${tip}>${esc(c.text)}</span>`;
      return edit ? `<span class="kv-chipw">${body}${pen(c)}</span>` : body;
    };
    const empty = (field, label) => `<button type="button" class="badge kv-chip is-empty" data-kin-edit="${field}" data-kin-kind="${kind}" data-kin-uid="${esc(x.uid)}">＋ ${esc(label)}</button>`;
    const main = [];
    const used = new Set();
    for (const [role, label] of HEAD_SLOTS[kind]) {
      const c = chips.find(q => q.role === role);
      if (c) {
        main.push(one(c));
        used.add(c);
      } else if (edit && label) main.push(empty(role === 'surname' ? 'seat' : role, label));
    }
    for (const c of chips) if (!used.has(c) && c.role !== 'tag') main.push(one(c));
    const tags = chips.filter(c => c.role === 'tag').map(c => `<span class="badge kv-chip is-tag">${esc(c.text)}${edit ? `<button type="button" class="kv-x" data-kin-edit="tags" data-kin-tag-del="${esc(c.text)}" data-kin-kind="${kind}" data-kin-uid="${esc(x.uid)}" aria-label="${esc(`꼬리표 ${c.text} 지우기`)}">✕</button>` : ''}</span>`);
    if (edit) tags.push(empty('tags', '꼬리표'));
    return `${main.join('<i class="hs-arrow" aria-hidden="true">›</i>')}${tags.length ? `<i class="kv-sep" aria-hidden="true">·</i>${tags.join('')}` : ''}`;
  }
  /** 메이커 미리 보기의 칩 고치기 — 메이커 계보 입력(HT.maker.kin.editHead)이 그 원래 칸을 고침(되돌리기 한 걸음) */
  function kinEditChip(btn) {
    if (!kinEditable()) return false;
    const del = btn.dataset.kinTagDel;
    Promise.resolve(HT.maker.kin.editHead({ kind: btn.dataset.kinKind, uid: btn.dataset.kinUid, field: btn.dataset.kinEdit, anchor: btn, remove: del != null ? del : undefined })).catch(err => console.warn('머리 칩을 고치지 못했습니다', err));
    return true;
  }

  /* 가문 조명 (결정 7 A — 5-3): 본가를 누르면 아래 파까지(HT.houseUnder), 그 가문 사람이 지도자 자리에 있던 기간을 다스린 모든 나라의 띠에 칠 · 날짜 칸 괄호 ·
     그 띠의 다른 가문 칸 .55 (timeline.setHouse(ids, { spans, dim })). 도우미가 없으면 옛 꼴(setHouse(id) — 그 가문 칸만 진하게) */
  function lightHouses(ids) {
    const m = state.model;
    const list = ids.filter(Boolean);
    if (!hasFn('houseSpans') || !hasFn('houseUnder')) return timeline.setHouse(list[0] || null);
    const under = [...new Set(list.flatMap(id => HT.houseUnder(m, id) || [id]))];
    let spans = [];
    try {
      spans = HT.houseSpans(m, under, { branches: true }) || [];
    } catch (err) {
      spans = [];
    }
    timeline.setHouse(under.length === 1 ? under[0] : under, { spans, dim: true });
  }

  /* 다스린 기간 막대 (5-3 — 가문 창 맨 위 · 성씨 창): 나라마다 한 줄, 나라 기간 = 나라 색 18% 막대, 가문의 칸 = 가문 색 칠 · 모든 줄이 같은 자 · 아래에 처음 · 가운데 · 끝 해.
     아주 짧은 구간도 4px, 막대 끝에 닿으면 안쪽에 붙임. 줄을 누르면 그 시기로 */
  const eraYear = t => (t == null || !isFinite(t) ? '' : HT.formatAxisYear(t));
  function erasHTML(rows, { title = '다스린 기간', note = '' } = {}) {
    if (!rows.length) return '';
    const A = Math.min(...rows.map(r => r.span[0]));
    const B = Math.max(...rows.map(r => r.span[1]), A + 1);
    const pct = v => ((v - A) / (B - A)) * 100;
    /* 막대 아래 한 줄 = 그 가문이 실제로 자리에 있던 해(감독 건의 2026-10-14 5번): 예전에는 막대 밑의 해가 나라의 처음 · 가운데 · 끝뿐이라
       '다스린 기간'이 나라의 기간으로 읽혔음(해씨 기원전 19 ~ 53이 기원전 37 ~ 668로). 실권(내각) 구간은 옅은 칠과 '실권' 글로 따로 */
    const spanText = (list, open = []) => {
      const shown = list.slice(0, 4).map(([a, b], i) => (open.includes(i) ? `${eraYear(a)} ~ 미정` : eraYear(a) === eraYear(b) ? eraYear(a) : `${eraYear(a)} ~ ${eraYear(b)}`));
      return shown.join(' · ') + (list.length > 4 ? ` 외 ${list.length - 4}` : '');
    };
    const line = r => {
      const l = pct(r.span[0]);
      const w = Math.max(0, pct(r.span[1]) - l);
      const len = Math.max(1e-9, r.span[1] - r.span[0]);
      const piece = real => q => {
        const [a, b] = q.c;
        const lp = ((a - r.span[0]) / len) * 100;
        const wp = Math.max(0, ((b - a) / len) * 100);
        const at = lp + wp > 97 ? `right:${Math.max(0, 100 - lp - wp).toFixed(3)}%` : `left:${lp.toFixed(3)}%`;
        return `<i${real ? ' class="is-real"' : ''} style="${at};width:${wp.toFixed(3)}%;--hc:${q.hc}" title="${esc(`${q.name ? `${q.name} · ` : ''}${real ? '실권 ' : ''}${eraYear(a)} ~ ${eraYear(b)}`)}"></i>`;
      };
      const real = r.real || [];
      const cells = r.cells.map(piece(false)).join('') + real.map(piece(true)).join('');
      const when = [r.cells.length ? spanText(r.cells.map(q => q.c), r.openCells) : '', real.length ? `실권 ${spanText(real.map(q => q.c), r.openReal)}` : ''].filter(Boolean).join(' · ');
      return `<li><button type="button" class="kv-era" data-kin-era="${r.span[0]}|${r.span[1]}" title="${esc(`${r.name} ${eraYear(r.span[0])} ~ ${eraYear(r.span[1])} — 누르면 그 시기로`)}"><span class="kv-era-n">${esc(r.name)}</span><span class="kv-era-bar"><span class="kv-era-trk" style="left:${l.toFixed(3)}%;width:${w.toFixed(3)}%;--c:${r.color}">${cells}</span></span>${when ? `<span class="kv-era-when">${esc(when)}</span>` : ''}</button></li>`;
    };
    return `<section class="sub-box kv-eras"><h3${note ? ` title="${esc(note)}"` : ''}>${esc(title)}</h3><ul>${rows.map(line).join('')}</ul><div class="kv-era-axis" aria-hidden="true"><span>${esc(eraYear(A))}</span><span>${esc(eraYear((A + B) / 2))}</span><span>${esc(eraYear(B))}</span></div></section>`;
  }
  /** 가문(과 아래 파)의 막대 줄 — 칸은 그 가문 색 */
  const houseEraRows = h => {
    if (!hasFn('houseEras')) return [];
    let rows = [];
    try {
      rows = HT.houseEras(state.model, h.id) || [];
    } catch (err) {
      rows = [];
    }
    return rows.map(r => ({ uid: r.uid, name: r.name, color: r.color, span: r.span, cells: (r.cells || []).map(c => ({ c, hc: h.color, name: '' })), real: (r.real || []).map(c => ({ c, hc: h.color, name: '' })), openCells: r.openCells || [], openReal: r.openReal || [] }));
  };

  /** 성씨 창(5-3 — 새 갈래 surname): 성씨 배지 · 가문 수 · 다스린 나라 수 · 막대(가문마다 제 색) · 가문 칩. 연표에는 그 성의 모든 가문이 같은 칠로 조명됩니다 */
  function surnameDetailHTML(sn) {
    const m = state.model;
    const houses = (sn.houses || []).map(id => m.houseMap.get(id)).filter(Boolean);
    const rows = new Map();
    if (hasFn('houseEras'))
      for (const h of houses)
        for (const r of HT.houseEras(m, h.id) || []) {
          const row = rows.get(r.uid) || rows.set(r.uid, { uid: r.uid, name: r.name, color: r.color, span: r.span.slice(), cells: [] }).get(r.uid);
          row.span = [Math.min(row.span[0], r.span[0]), Math.max(row.span[1], r.span[1])];
          for (const c of r.cells || []) row.cells.push({ c, hc: h.color, name: h.name });
        }
    const list = [...rows.values()].sort((a, b) => a.span[0] - b.span[0]);
    const has = !!docText(sn.uid);
    return `
      <div class="detail-head">
        <div class="badges"><span class="badge" style="--c:${houses[0] ? houses[0].color : 'var(--text-3)'}">성씨</span></div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(sn.name)}</h2>
        ${namesHeadHTML(sn.names, 'polity')}
        <p class="when">가문 ${houses.length}${list.length ? ` · 다스린 나라 ${list.length}` : ''}</p>
        ${erasHTML(list, { note: '막대 색 = 가문 · 연표의 모든 띠에 같은 조명' })}
        ${houses.length ? `<section class="sub-box"><h3>가문</h3><div class="chips">${houses.map(h => `<button type="button" class="chip" style="--c:${h.color}" data-uid="${esc(h.uid)}" title="${esc(`${h.name} — 가문 창`)}">${esc(h.name)}</button>`).join('')}</div></section>` : ''}
        ${namesRestHTML(sn.names, 'polity')}
        ${sn.description ? `<div class="desc">${esc(sn.description)}</div>` : ''}
        ${subdocsHTML(sn.uid)}
      </div>
      <div class="detail-foot">
        ${has || maker ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-doc="${esc(sn.uid)}" type="button">${icon('file')}문서${has ? '' : ' 만들기'}</button>` : ''}
        <button class="btn btn-sm" data-act="close" type="button">닫기</button>
      </div>`;
  }

  /** 계보 전용 인물 창(lane:false · pick:false — 띠에 그림이 없음): 이름 · 생몰(적었을 때만 — 비움 ≠ 미상) · 가문 · 파 · 부모 · 자식 줄 · 세계표 · 승계표에서 보기 */
  function kinFigureDetailHTML(x) {
    const m = state.model;
    const track = trackOf(x.track);
    const n = HT.personOf(m, x);
    const h = kinFigureHouse(x);
    const path = h ? (h.path || [h.id]).map(id => m.houseMap.get(id)).filter(Boolean) : [];
    const life = HT.figureLife(x);
    const where = n ? kinWhere(n.key) : null;
    const own = !!maker && maker.isOwn(x);
    const has = !!docText(x.uid);
    const houseChip = q => (q === h ? `<span class="chip is-here" style="--c:${q.color}">${esc(q.name)}</span>` : `<button type="button" class="chip" style="--c:${q.color}" data-uid="${esc(q.uid)}" title="${esc(`${q.name} — 가문 창`)}">${esc(q.name)}</button>`);
    return `
      <div class="detail-head">
        <div class="badges"><button type="button" class="badge is-link" style="--c:${track.color}" data-doc="${esc(`track:${track.id}`)}" title="${esc(`${track.name} 문서`)}">${esc(track.name)}</button><span class="badge is-kind is-figure">계보 전용${x.role ? ` · ${esc(x.role)}` : ''}</span>${h ? houseBadge({ houseId: h.id, houseName: h.name, houseColor: h.color, houseAuto: !(x.houseId && x.houseId === h.id) }) : ''}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(x.name)}</h2>
        ${namesHeadHTML(x.names, 'person')}
        ${x.aka && x.aka.length ? `<p class="aka">다른 이름: ${esc(x.aka.join(' · '))}</p>` : ''}
        ${life ? `<p class="when">${esc(life)}</p>` : ''}
        ${path.length ? `<div class="chips hs-path kv-path">${path.map(houseChip).join('<i class="hs-arrow" aria-hidden="true">›</i>')}</div>` : ''}
        ${kinLinesHTML(n)}
        ${namesRestHTML(x.names, 'person')}
        <div class="desc${x.description ? '' : ' is-empty'}">${x.description ? esc(x.description) : '설명이 없습니다.'}</div>
        ${subdocsHTML(x.uid)}
        ${x.tags && x.tags.length ? `<div class="tags">${x.tags.map(t => `<span class="tag">#${esc(t)}</span>`).join('')}</div>` : ''}
        <dl><dt>제공</dt><dd>${esc(x.packName)}${own ? ' <b>(고치는 중인 DLC)</b>' : ''}</dd></dl>
      </div>
      <div class="detail-foot">
        ${where ? `<button class="btn btn-sm" data-kin-fam="${esc(n.key)}" type="button">세계표에서 보기</button>` : ''}
        ${where && kinLeaderAbove(where) ? `<button class="btn btn-sm" data-kin-succ-person="${esc(n.key)}" type="button">승계표에서 보기</button>` : ''}
        ${has || maker ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-act="wiki" type="button">${icon('file')}문서${has ? '' : ' 만들기'}</button>` : ''}
        ${maker ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
        ${maker ? `<button class="btn btn-sm btn-danger" data-act="delete" type="button">${own ? '🗑 삭제' : '🙈 숨기기'}</button>` : ''}
      </div>`;
  }
  /** 뼈대에서 그 사람 위로 가장 가까운 지도자 — 승계표에서 그 사람이 펼쳐지는 카드 { polity, i } (없으면 null) */
  function kinLeaderAbove(where) {
    const S = KV() ? KV().skeleton(state.model, where.key) : null;
    if (!S) return null;
    for (let q = S.par[where.at]; q >= 0; q = S.par[q]) {
      if (!(S.bits[q] & HT.kinView.bits.LEADER)) continue;
      const node = state.model.personIndex ? state.model.personIndex.get(S.keys[q]) : null;
      const c = node && node.cells.find(z => z.kind === 'leader');
      if (c) return { polity: c.p, i: c.i };
    }
    return null;
  }

  /* 승계표 창(3절 — 상세 창 자리, 갈래 succession): 껍데기(머리 칩 · 범례 · 바닥)만 html로, 목록은 enter에서 HT.kinView.succession이 몸통 안에 붙임 */
  const SUCC_LEVELS = [['L', '지도자만'], ['C', '자녀까지'], ['B', '파 이름까지'], ['A', '모두']];
  function successionShellHTML(x) {
    const n = (x.leaders || []).length;
    return `
      <div class="detail-head">
        <div class="badges kv-head">${headChipsHTML('polity', x)}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body kv-succ-body">
        <h2>${esc(x.name)}</h2>
        <p class="kv-sub" title="지도자 사이의 관계 · 오른 방식">지도자 ${n}</p>
        ${HT.kinView.legendHTML('succession')}
        <div data-kin-list></div>
      </div>
      <div class="detail-foot kv-succ-foot">
        <button class="btn btn-sm" data-uid="${esc(x.uid)}" type="button">◀ 나라 상세</button>
        <button class="btn btn-sm" data-kin-level="A" type="button">모두 펼치기</button>
        <button class="btn btn-sm" data-kin-level="L" type="button">모두 접기</button>
        <select data-kin-levels aria-label="펼칠 수준">${SUCC_LEVELS.map(([v, t]) => `<option value="${v}">${t}</option>`).join('')}</select>
      </div>`;
  }
  let succWait = 0; // 뼈대를 나눠 짓는 동안 창이 바뀌면(닫힘 · 다른 나라) 지은 뒤에 붙이지 않게
  function mountSuccession(x, opts) {
    if (state.kinSucc) state.kinSucc.destroy();
    state.kinSucc = null;
    const host = detailEl.querySelector('[data-kin-list]');
    const body = detailEl.querySelector('.detail-body');
    if (!host || !body) return;
    /* 큰 뼈대(5만 덩어리 등)는 나눠 지으며 '승계표를 짓고 있습니다'(4-6 · 6-1 — 50ms 넘는 장면 0). 이미 지었으면 곧바로 */
    const token = ++succWait;
    const wait = HT.kinView.succPrepare ? HT.kinView.succPrepare(state.model, x) : null;
    if (wait) {
      host.innerHTML = '<p class="kv-building kv-succ-wait">승계표를 짓고 있습니다</p>';
      const model = state.model;
      wait.then(() => {
        if (token !== succWait || state.model !== model || !host.isConnected) return;
        host.textContent = '';
        mountSuccession(x, opts);
      });
      return;
    }
    state.kinSucc = HT.kinView.succession({
      host,
      scroller: body,
      model: state.model,
      polity: x,
      store: kinStore,
      focus: opts.focus != null ? Number(opts.focus) : null,
      expand: !!opts.expand,
      focusPerson: opts.focusPerson || null,
      onOpen: a => kinOpen(a, { back: x.uid }),
      onMenu: (a, cx, cy) => kinMenu(a, cx, cy),
    });
    const sel = detailEl.querySelector('[data-kin-levels]');
    if (sel) sel.value = state.kinSucc.level();
  }
  /** 승계표 · 세계표에서 고른 것을 엽니다 — 칸 창 · 인물 창 · 가문 창 (back = 승계표의 나라 uid → 바닥에 ◀ 승계표) */
  function kinOpen(a, { back = null } = {}) {
    const m = state.model;
    if (a.type === 'house') return openDetail(`house:${a.id}`);
    if (a.type === 'cell') return openDetail(a.polity.uid, { cell: `leader:${a.i}`, kinBack: back });
    if (a.type !== 'person') return;
    const node = m.personIndex ? m.personIndex.get(a.key) : null;
    if (node && node.figure && m.byUid.has(node.figure.uid)) return openDetail(node.figure.uid, { kinBack: back });
    const c = node && node.cells[0];
    if (c) return openDetail(c.p.uid, { cell: c.ref, kinBack: back });
    HT.toast(node && node.unknown ? '이름 미상의 사람은 창이 없습니다.' : '이 사람은 인물이나 지도자 칸으로 적혀 있지 않아 창이 없습니다.');
  }
  /** 승계표 사람 줄 · 세계표 카드의 메뉴 */
  function kinMenu(a, x, y) {
    if (a.type !== 'person') return;
    const items = [{ title: (state.model.personIndex && (state.model.personIndex.get(a.key) || {}).name) || '사람' }, { label: '창 열기', run: () => kinOpen(a) }];
    const where = kinWhere(a.key) || (a.skel != null ? { key: a.skel, at: a.at } : null);
    if (where) items.push({ label: '세계표에서 보기', run: () => openFamilyAt(a.key) });
    const up = where ? kinLeaderAbove(where) : null;
    const node = state.model.personIndex ? state.model.personIndex.get(a.key) : null;
    const lead = node && node.cells.find(z => z.kind === 'leader');
    if (lead && KVS()) items.push({ label: '승계표에서 보기', run: () => openDetail(lead.p.uid, { cell: 'succession', focus: lead.i, expand: true }) });
    else if (up && KVS()) items.push({ label: '승계표에서 보기', run: () => openDetail(up.polity.uid, { cell: 'succession', focusPerson: where }) });
    /* 메이커: 그 사람 곁에 사람 더하기 · 고치기 · 지우기 (js/maker-kin.js — 한 걸음씩 되돌리기) */
    if (kinAddable()) {
      const K2 = HT.maker.kin;
      items.push({ sep: true });
      for (const [rel, word] of [['child', '자식'], ['sibling', '형제'], ['spouse', '배우자'], ['parent', '부모']]) items.push({ label: `＋ ${word}`, run: () => K2.addRelative({ key: a.key, rel, anchor: kinAnchor(a.key) }) });
      items.push({ label: '계층 입력…', run: () => K2.outline({ uid: a.key }) });
      const fig = node && node.figure && state.model.byUid.has(node.figure.uid) ? node.figure : null;
      const editUid = fig ? fig.uid : lead ? lead.p.uid : null;
      if (editUid && paneEditable(editUid)) items.push({ label: '고치기', run: () => openEditorFor(editUid) });
      if (K2.removable && K2.removable(a.key)) items.push({ label: '지우기', run: () => K2.removePerson({ key: a.key }) });
    }
    showMenu(items, x, y);
  }
  /** 메이커에서 세계표 · 승계표 창 안의 사람 더하기를 쓸 수 있는지 (작업본이 있을 때) */
  const kinAddable = () => kinEditable() && typeof HT.maker.kin.addRelative === 'function';
  /** 사람 더하기 창을 붙일 곳 — 세계표의 그 카드(보이면), 없으면 가운데 */
  const kinAnchor = key => {
    const fc = KV() && HT.kinView.current();
    const i = fc ? fc.indexOf(key) : -1;
    return (i >= 0 && fc.el.querySelector(`.kv-p[data-i="${i}"]`)) || null;
  };
  /** 세계표 바닥의 메이커 단추 — 고른 카드(없으면 맨 위 사람) 곁에 사람 더하기 */
  const famFootHTML = () => (kinAddable() ? '<button class="btn btn-sm" data-kin-add type="button" title="고른 사람 곁에 — 자식 · 형제 · 배우자 · 부모 (카드를 오른쪽 눌러도)">＋ 사람</button>' : '');
  function famAdd(btn) {
    const fc = HT.kinView.current();
    if (!fc) return;
    const key = fc.focusedKey() || fc.firstKey();
    if (!key) return HT.toast('사람을 먼저 고릅니다.', 'error');
    HT.maker.kin.addRelative({ key, anchor: kinAnchor(key) || btn });
  }
  /** 그 항목에서 열 수 있는 승계표 · 세계표 — { succ: 승계표의 나라 | null, fam: 세계표를 여는 함수 | null }.
      나라: 지도자 둘 이상이면 승계표, 첫 지도자가 놓인 세계표(가문 · 가문 없는 나라) — 지도자가 없으면 국성. 가문('house:id'): 그 세계표. 인물: 그 사람이 놓인 세계표 */
  function kinPlan(uid) {
    const m = state.model;
    const x = uid && KV() ? detailTarget(uid) : null;
    const out = { succ: null, fam: null };
    if (!x) return out;
    const famOf = n => (n && kinWhere(n.key) ? () => openFamilyAt(n.key) : null);
    if (String(uid).startsWith('house:')) out.fam = () => openFamily(x);
    else if (HT.itemKindOf(x) === 'period') {
      if (KVS() && (x.leaders || []).length >= 2) out.succ = x;
      for (let i = 0; i < (x.leaders || []).length && !out.fam; i++) out.fam = famOf(HT.personOf(m, x, `leader:${i}`));
      const h = !out.fam && x.houseId && m.houseMap ? m.houseMap.get(x.houseId) : null;
      if (h) out.fam = () => openFamily(h);
    } else if (HT.itemKindOf(x) === 'figure') out.fam = famOf(HT.personOf(m, x));
    return out;
  }
  /** 승계표(which 'succession') · 세계표('family') 열기 — 메이커의 편집 창 머리 · 보기 메뉴. 승계표는 상세 자리라 편집 창을 먼저 닫음(고친 것이 있으면 물음) */
  function openKin(uid, which) {
    const k = kinPlan(uid);
    if (which === 'succession') {
      if (!k.succ) return HT.toast('승계표는 지도자가 둘 이상인 나라에서 엽니다.', 'error'), false;
      const go = () => openDetail(k.succ.uid, { cell: 'succession' });
      if (maker && maker.pane.blocks()) return leaveEditor().then(ok => ok && go());
      return go();
    }
    if (!k.fam) return HT.toast('세계표에 놓을 사람이 없습니다 — 지도자 · 인물 · 가문을 먼저 적습니다.', 'error'), false;
    return k.fam();
  }
  /** 편집 창 머리의 「계보」 메뉴 — 그 항목의 승계표 · 세계표 */
  function kinPaneMenu(uid, x, y) {
    const k = kinPlan(uid);
    showMenu([{ label: '승계표', disabled: !k.succ, run: k.succ ? () => openKin(uid, 'succession') : null }, { label: '세계표', disabled: !k.fam, run: k.fam ? () => openKin(uid, 'family') : null }], x, y);
  }
  /** 고른 항목이 없을 때의 고르기 메뉴 — 승계표: 지도자 둘 이상인 나라, 세계표: 뿌리 가문 · 가문 없이 지도자만 있는 나라 (메이커의 고치는 DLC 먼저 · 이름 차례 · 40개까지) */
  function kinPick(which, x, y) {
    const m = state.model;
    const mine = it => (maker && maker.isOwn(it) ? 0 : 1);
    const byName = (a, b) => mine(a) - mine(b) || String(a.name).localeCompare(String(b.name), 'ko');
    const nations = m.periods.filter(p => HT.itemKindOf(p) === 'period' && (p.leaders || []).length >= (which === 'succession' ? 2 : 1));
    let list;
    if (which === 'succession') list = nations.sort(byName).map(p => ({ label: p.name, run: () => openKin(p.uid, 'succession') }));
    else {
      const roots = [...(m.houseMap ? m.houseMap.values() : [])].filter(h => !h.parent && (h.kinCount || (h.members || []).length));
      const lone = nations.filter(p => !p.houseId && !(p.leaders || []).some((c, i) => { const n = HT.personOf(m, p, `leader:${i}`); return n && n.houseId; }));
      list = roots.map(h => ({ name: h.name, h })).concat(lone.map(p => ({ name: p.name, p })));
      list = list.sort((a, b) => mine(a.h || a.p) - mine(b.h || b.p) || String(a.name).localeCompare(String(b.name), 'ko')).map(o => ({ label: o.name, run: () => (o.h ? openFamily(o.h) : openKin(o.p.uid, 'family')) }));
    }
    if (!list.length) return HT.toast(which === 'succession' ? '지도자가 둘 이상인 나라가 없습니다.' : '세계표에 놓을 가문 · 나라가 없습니다.', 'error');
    const more = list.length > 40 ? [{ label: `…외 ${list.length - 40}개 — 항목을 고른 뒤 다시`, disabled: true }] : [];
    showMenu([{ title: which === 'succession' ? '승계표' : '세계표' }, ...list.slice(0, 40), ...more], x, y);
  }
  /** 세계표 창(4절 — 가문 창 왼쪽의 떠 있는 창). house(파면 그 파의 하위 나무) · 또는 사람 열쇠로 그 사람에게 데려감 */
  function openFamily(house, { focusKey = null, scroll = null, scale = 0, focusTree = true, again = false } = {}) {
    const kv = KV();
    if (!kv || !house) return false;
    const ctl = kv.family({
      stage: famStage(),
      model: state.model,
      key: kinRootKey(house),
      house,
      focusKey,
      scroll,
      scale,
      focusTree,
      again,
      headHTML: headChipsHTML('house', house),
      title: `${house.name} 세계표`,
      store: kinStore,
      placeNear: detailEl,
      onOpen: a => kinOpen(a),
      onMenu: (a, cx, cy) => kinMenu(a, cx, cy),
      onLink: t => famLink(t),
      footHTML: famFootHTML(),
    });
    return !!ctl;
  }
  /** 세계표 창을 붙일 무대 — 연표는 상세 창의 부모(무대), 메이커는 상세가 오른쪽 창에 있어 가운데 무대(#stage) */
  const famStage = () => (maker && $('#stage')) || detailEl.parentElement;
  /** 사람 열쇠 → 그 사람이 구성원으로 든 세계표(뿌리 가문 전체)를 열고 그 카드로 */
  function openFamilyAt(personKey, opts = {}) {
    const kv = KV();
    const w = kinWhere(personKey);
    if (!kv || !w) return false;
    const hm = /^kin:(?!polity:)(.+)$/.exec(w.key);
    const house = hm && state.model.houseMap ? state.model.houseMap.get(hm[1]) : null;
    if (house) return openFamily(house, Object.assign({}, opts, { focusKey: personKey }));
    return openFamilyKey(w.key, Object.assign({}, opts, { focusKey: personKey }));
  }
  /** 가문이 없는 지도자의 나라 뼈대('kin:polity:<uid>')의 세계표 */
  function openFamilyKey(key, { focusKey = null, scroll = null, scale = 0, focusTree = true, again = false } = {}) {
    const kv = KV();
    const p = kv ? state.model.byUid.get(String(key).replace(/^kin:polity:/, '')) : null;
    if (!p) return false;
    const ctl = kv.family({ stage: famStage(), model: state.model, key, house: null, focusKey, scroll, scale, focusTree, again, headHTML: headChipsHTML('polity', p), title: `${p.name} 세계표`, store: kinStore, placeNear: detailEl, onOpen: a => kinOpen(a), onMenu: (a, cx, cy) => kinMenu(a, cx, cy), onLink: t => famLink(t), footHTML: famFootHTML() });
    return !!ctl;
  }
  /** 세계표 창 머리 칩 · 바닥 단추의 누름 — 상세 창과 같은 길 */
  function famLink(t) {
    const add = t.closest('[data-kin-add]');
    if (add) return famAdd(add);
    const ed = t.closest('[data-kin-edit]');
    if (ed) return kinEditChip(ed);
    const d = t.closest('[data-doc]');
    if (d) return openWiki(d.dataset.doc);
    const u = t.closest('[data-uid]');
    if (u) return openDetail(u.dataset.uid);
  }
  /** 바닥의 ◀ 승계표 — 승계표 사람 줄에서 연 창에만 */
  function kinBackHTML(uid) {
    const p = state.model.byUid.get(uid);
    return p ? `<button class="btn btn-sm" data-kin-back="${esc(uid)}" type="button" title="${esc(`${p.name} 승계표로 돌아가기`)}">◀ 승계표</button>` : '';
  }

  /** 가문 창: 이름 · 성 · 본관 · 시조 · 본가 → 분가 길과 갈라져 나간 분가 · 국성으로 삼은 나라 · 구성원(나라별로 시작 순, 역할 딱지) · 문서 · 하위 문서.
      단추는 data-doc · data-year · data-uid만 (연표에는 그 가문의 칸이 진해짐 — timeline.setHouse) */
  const HOUSE_ROLES = { period: '국성', dynasty: '왕조', leader: '지도자', cabinet: '내각', figure: '인물' };
  function houseDetailHTML(h) {
    const m = state.model;
    const H = id => m.houseMap.get(id);
    const chip = q => `<button type="button" class="chip" style="--c:${q.color}" data-uid="${esc(q.uid)}" title="${esc(`${q.name} — 가문 창`)}">${esc(q.name)}</button>`;
    const path = (h.path || []).map(H).filter(Boolean);
    const branches = (h.children || []).map(H).filter(Boolean);
    const nations = h.members.filter(mb => mb.role === 'period').map(mb => mb.item);
    /* 구성원은 나라별로: 지도자 · 내각은 그 나라, 왕조는 처음 다스린 나라, 인물은 섬긴 나라(있으면) — 없으면 맨 끝 '그 밖' */
    const groups = new Map();
    for (const mb of h.members) {
      if (mb.role === 'period') continue;
      const it = mb.item;
      const nation = mb.role === 'leader' || mb.role === 'cabinet' ? it : mb.role === 'dynasty' ? ((it.hosts || [])[0] || {}).host : (it.polityUid && m.byUid.get(it.polityUid)) || null;
      const key = nation ? nation.uid : '';
      if (!groups.has(key)) groups.set(key, { nation, list: [] });
      groups.get(key).list.push(mb);
    }
    const order = [...groups.values()].sort((a, b) => (!a.nation) - !b.nation || a.list[0].start - b.list[0].start);
    const row = mb => {
      const role = `<em class="hs-role">${esc(HOUSE_ROLES[mb.role] || '')}</em>`;
      if (mb.cell) {
        const c = mb.cell;
        const name = mb.role === 'leader' ? HT.leaderLabel(c, state.ui.leaderLabel || 'auto') : c.name;
        return `<li><button type="button" data-year="${c.start}" data-prec="${precOf(c)}" title="그 시기로"><b>${esc(cellWhen(c, false, mb.item))}</b><span>${esc(name)} ${role}${mb.auto ? ' <i>짐작</i>' : ''}</span></button></li>`;
      }
      return `<li><button type="button" data-uid="${esc(mb.item.uid)}" title="상세"><b>${esc(HT.formatRange(mb.item))}</b><span>${esc(mb.item.name || mb.item.title)} ${role}</span></button></li>`;
    };
    const count = h.members.filter(mb => mb.role !== 'period').length;
    const has = !!docText(h.uid);
    const sn = h.surnameId && m.surnameMap ? m.surnameMap.get(h.surnameId) : null; // 성씨 사전(형식 버전 3) — 성을 id로 적었어도 이름으로 · 성의 원어
    /* D1: 띠 인물 구성원은 200명까지 그리고 나머지는 세계표로 · 계보 전용 인물은 목록에 넣지 않고 수만(세계표에서 봄) */
    const FIG_CAP = 200;
    const shownFig = new Set();
    for (const g of order) for (const mb of g.list) if (mb.role === 'figure' && shownFig.size < FIG_CAP) shownFig.add(mb);
    const figAll = h.members.filter(mb => mb.role === 'figure').length;
    const famOk = !!KV();
    const under = hasFn('houseUnder') ? new Set(HT.houseUnder(m, h.id)) : new Set([h.id]);
    const kinN = famOk ? (m.lineageFigures || []).filter(f => {
      const q = kinFigureHouse(f);
      return q && under.has(q.id);
    }).length : 0;
    const snBadge = h.surname ? (sn ? `<button type="button" class="badge is-link" data-uid="${esc(sn.uid)}" title="${esc(`성 ${sn.name} — 누르면 성씨 창(그 성의 모든 가문을 조명)`)}">성 ${esc(sn.name)}</button>` : `<span class="badge">성 ${esc(h.surname)}</span>`) : '';
    return `
      <div class="detail-head">
        <div class="badges"><span class="badge" style="--c:${h.color}">가문</span>${snBadge}${h.seat ? `<span class="badge">본관 ${esc(h.seat)}</span>` : ''}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(h.name)}</h2>
        ${namesHeadHTML(h.names, 'polity')}
        ${sn && sn.names.length ? namesLineHTML(sn.names, 'polity', `성 ${esc(sn.name)} — `) : ''}
        ${h.founder ? `<p class="aka">시조 ${esc(h.founder)}</p>` : ''}
        ${h.auto ? '<p class="range-note">가문 목록에 없는 이름이라, 적힌 이름 그대로 가문으로 묶었습니다</p>' : ''}
        ${erasHTML(houseEraRows(h))}
        ${namesRestHTML(h.names, 'polity')}
        <div class="desc${h.description ? '' : ' is-empty'}">${h.description ? esc(h.description) : '설명이 없습니다.'}</div>
        ${
          path.length > 1 || branches.length
            ? `<section class="sub-box"><h3>본가 · 분가</h3>${
                path.length > 1 ? `<p class="succ-cap">본가에서 이 가문까지</p><div class="chips hs-path">${path.map(q => (q === h ? `<span class="chip is-here" style="--c:${q.color}">${esc(q.name)}</span>` : chip(q))).join('<i class="hs-arrow" aria-hidden="true">›</i>')}</div>` : ''
              }${branches.length ? `<p class="succ-cap">갈라져 나간 분가 <small>${branches.length}개</small></p><div class="chips">${branches.map(chip).join('')}</div>` : ''}</section>`
            : ''
        }
        ${nations.length ? `<section class="sub-box"><h3>국성 나라 <small>${nations.length}</small></h3><div class="chips">${nations.map(p => `<button type="button" class="chip" style="--c:${p.color}" data-uid="${esc(p.uid)}">${esc(p.name)}</button>`).join('')}</div></section>` : ''}
        <section class="sub-box"><h3>구성원 <small>${count}</small></h3>${
          order.length
            ? order
                .map(g => {
                  const list = g.list.filter(mb => mb.role !== 'figure' || shownFig.has(mb));
                  return list.length ? `<p class="succ-cap">${g.nation ? `<button type="button" class="linky" data-uid="${esc(g.nation.uid)}">${esc(g.nation.name)}</button>` : '그 밖'} <small>${g.list.length}</small></p><ul class="kid-list hs-members">${list.map(row).join('')}</ul>` : '';
                })
                .join('')
            : '<p class="succ-cap">이 가문을 가리키는 지도자 · 내각 · 왕조 · 인물이 없습니다.</p>'
        }${figAll > FIG_CAP ? `<p class="succ-cap kv-more-line">${famOk ? `<button type="button" class="linky" data-kin-fam-house="${esc(h.id)}">${(figAll - FIG_CAP).toLocaleString()}명 더 — 세계표에서</button>` : `${(figAll - FIG_CAP).toLocaleString()}명 더`}</p>` : ''}${
          kinN ? `<p class="succ-cap kv-more-line">계보 전용 인물 ${kinN.toLocaleString()}명 · <button type="button" class="linky" data-kin-fam-house="${esc(h.id)}">세계표에서 보기</button></p>` : ''
        }</section>
        ${subdocsHTML(h.uid)}
        <dl><dt>제공</dt><dd>${h.packName ? esc(h.packName) : '가문 목록에 없음'}</dd></dl>
      </div>
      <div class="detail-foot">
        ${famOk ? `<button class="btn btn-sm kv-fam-btn" data-kin-fam-house="${esc(h.id)}" type="button">세계표</button>` : ''}
        ${has || maker ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-doc="${esc(h.uid)}" type="button">${icon('file')}문서${has ? '' : ' 만들기'}</button>` : ''}
        <button class="btn btn-sm" data-act="close" type="button">닫기</button>
      </div>`;
  }

  /* ---------- 단체 · 제도 칸 · 사건의 주제 · 법 · 선거 (형식 버전 3 — docs/구상-연표-확장-10건.md 3-7 · 3-8) ----------
     띠 안의 그림(집권 단 · 실권 단 · 연합 끈 · 렌즈 띠)과 렌즈 고르기는 설계(D5)가 정할 때까지 두지 않고 상세 창의 글로만 보입니다.
     단체 창 · 제도 창은 제 줄이 없어 가문 창처럼 고르지 않고(pick: false — 연표가 흐려지지 않음) 세로 닻도 걸지 않습니다.
     여는 길: 검색 · 나라 상세의 '단체' · '제도' 칩 · 사건 상세의 '맺은 단체' · 단체 창 · 제도 창 안의 칩. 단추는 data-uid · data-year · data-doc만 */
  const spanText = r => HT.formatRange({ start: r.start, startAt: r.startAt, end: r.end, endAt: r.endAt, startUnknown: r.startUnknown, endUnknown: r.endUnknown });
  /** 나라 칩 (찾지 못한 나라는 누를 수 없는 칩) */
  const polityChipHTML = r => (r.polityUid ? `<button type="button" class="chip" style="--c:${r.color}" data-uid="${esc(r.polityUid)}" title="${esc(`${r.name} 상세`)}">${esc(r.name)}</button>` : `<span class="chip is-off" title="연표에서 이 나라를 찾지 못했습니다 (트랙 · 이름을 확인하세요)">${esc(r.name)}</span>`);
  /** 단체 칩 — 누르면 단체 창 */
  const groupChipHTML = (g, name, small = '') => (g ? `<button type="button" class="chip" style="--c:${g.color}" data-uid="${esc(g.uid)}" title="${esc(`${g.name}${g.typeName ? ` · ${g.typeName}` : ''} · ${HT.formatRange(g)} — 단체 창`)}">${esc(g.name)}${small ? ` <small>${esc(small)}</small>` : ''}</button>` : `<span class="chip is-off" title="찾지 못한 단체">${esc(name)}${small ? ` <small>${esc(small)}</small>` : ''}</span>`);
  /** 단체의 구성원 칩 — 인물이면 인물 창, 인물이 없는 사람(지도자 칸 — 사람 잇기 HT.personOf와 같은 자리)이면 그 칸, 찾지 못한 이름은 누를 수 없는 칩 */
  const memberChipHTML = p => {
    if (p.uid && p.figure) return `<button type="button" class="chip" style="--c:${p.figure.color}" data-uid="${esc(p.uid)}" title="${esc(`${p.figure.name} — 인물 창`)}">${esc(p.figure.name)}${p.figure.role ? ` <small>${esc(p.figure.role)}</small>` : ''}</button>`;
    const c = p.person && p.person.cells[0];
    if (c) return `<button type="button" class="chip" style="--c:${c.p.color}" data-cell-of="${esc(c.p.uid)}" data-cell="${esc(c.ref)}" title="${esc(`${c.p.name} ${p.person.name} — 지도자 칸`)}">${esc(p.person.name)} <small>${esc(c.p.name)}</small></button>`;
    return `<span class="chip is-off" title="연표에서 인물 · 지도자로 찾지 못한 이름">${esc(p.name)}</span>`;
  };
  /** 사람 자리가 속한 단체 한 줄 (인물 창 · 지도자 칸 창 — 단체의 구성원으로 적힌 곳) */
  const personGroupsHTML = n => (n && n.groups && n.groups.length ? `<p class="aka">속한 단체: ${n.groups.map(g => `<button type="button" class="linky" data-uid="${esc(g.uid)}" title="단체 창">${esc(g.name)}</button>`).join(' · ')}</p>` : '');
  /** 확인할 것 (모델의 warnings — 찾지 못한 나라 · 주제 · 단체 · 사건, 겹치는 칸) */
  const lensWarnHTML = x => (x.warnings && x.warnings.length ? `<section class="sub-box is-scope-warn"><h3>확인할 것 <small>${x.warnings.length}</small></h3><ul class="scope-warn">${x.warnings.map(w => `<li>${esc(w)}</li>`).join('')}</ul></section>` : '');
  /** 단체 창: 이름 · 종류 · 기간 · 있던 나라 · 집권 기간 · 앞선 단체(갈라짐 · 합쳐짐 · 이름 바꿈)와 뒤를 이은 단체 · 구성원 · 연합의 구성 나라 · 맺은 사건 · 문서 */
  function groupDetailHTML(g) {
    const m = state.model;
    const track = trackOf(g.track);
    const has = !!docText(g.uid);
    const within = g.withinList || [];
    const members = g.memberList || [];
    const powers = g.powerSpans || [];
    const from = g.fromList || [];
    const into = g.intoList || [];
    const people = g.peopleList || [];
    const rowWhen = r => (r.given || r.startUnknown || r.endUnknown ? spanText(r) : '');
    const ev = g.eventItem;
    return `
      <div class="detail-head">
        <div class="badges"><button type="button" class="badge is-link" style="--c:${track.color}" data-doc="track:${esc(track.id)}" title="${esc(track.name)} 문서">${esc(track.name)}</button><span class="badge" style="--c:${g.color}">단체</span>${g.typeName ? `<span class="badge">${esc(g.typeName)}</span>` : ''}${
          g.certainty && g.certainty !== 'accepted' ? `<span class="badge badge-cert">${esc(HT.certaintyName(g.certainty))} 연대</span>` : ''}${g.startUnknown || g.endUnknown ? '<span class="badge badge-cert">연도 미정</span>' : ''}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(g.name)}</h2>
        ${namesHeadHTML(g.names, 'polity')}
        <p class="when">${esc(HT.formatRange(g))}</p>
        ${g.startRange ? `<p class="range-note">시작 — 이르면 ${esc(HT.formatDate(g.startRange[0], (g.startRangeAt || [])[0]))}, 늦으면 ${esc(HT.formatDate(g.startRange[1], (g.startRangeAt || [])[1]))}</p>` : ''}
        ${g.endRange ? `<p class="range-note">끝 — 이르면 ${esc(HT.formatDate(g.endRange[0], (g.endRangeAt || [])[0]))}, 늦으면 ${esc(HT.formatDate(g.endRange[1], (g.endRangeAt || [])[1]))}</p>` : ''}
        ${within.length ? `<p class="people-note">있던 나라 ${within.map(r => `${polityChipHTML(r)}${rowWhen(r) ? ` <small>${esc(rowWhen(r))}</small>` : ''}`).join(' ')}</p>` : ''}
        ${namesRestHTML(g.names, 'polity')}
        <div class="desc${g.description || g.note ? '' : ' is-empty'}">${g.description ? esc(g.description) : g.note ? esc(g.note) : '설명이 없습니다.'}</div>
        ${
          powers.length
            ? `<section class="sub-box"><h3>집권 기간 <small>${powers.length}</small></h3><ul class="kid-list">${powers
                .map(c => `<li><button type="button" data-year="${c.start}" data-prec="${precOf(c)}" title="그 시기로"><b>${esc(cellWhen(c, false, g))}</b><span>${esc(c.name)}${c.note ? ` <small>${esc(c.note)}</small>` : ''}${c.endAuto && !c.endUnknown ? ' <i>끝은 다음 칸 · 단체의 끝까지</i>' : ''}</span></button></li>`)
                .join('')}</ul></section>`
            : ''
        }
        ${
          from.length || into.length
            ? `<section class="sub-box"><h3>갈래</h3>${
                from.length ? `<p class="succ-cap">앞선 단체 <small>${from.length}개 — 갈라져 나온 · 합쳐진 · 이름을 바꾸기 전의 단체</small></p><div class="chips">${from.map(f => groupChipHTML(f.group, f.name, [f.how ? HT.groupHowName(f.how) : '', f.note].filter(Boolean).join(' · '))).join('')}</div>` : ''
              }${into.length ? `<p class="succ-cap">뒤를 이은 단체 <small>${into.length}개</small></p><div class="chips">${into.map(f => groupChipHTML(f.group, f.group.name, [f.how ? HT.groupHowName(f.how) : '', f.note].filter(Boolean).join(' · '))).join('')}</div>` : ''}</section>`
            : ''
        }
        ${
          people.length
            ? `<section class="sub-box"><h3>구성원 <small>${people.length}</small></h3><div class="chips">${people.map(memberChipHTML).join('')}</div></section>`
            : ''
        }
        ${
          members.length
            ? `<section class="sub-box"><h3>구성 나라 <small>${members.length}</small></h3><ul class="gp-members">${members
                .map(r => `<li><div class="gp-member">${polityChipHTML(r)}${r.role ? ` <em class="tr-role">${esc(r.role)}</em>` : ''}${r.track !== g.track ? ` <small>${esc(trackOf(r.track).name)}</small>` : ''}${rowWhen(r) ? ` <small>${esc(rowWhen(r))}</small>` : ''}${r.note ? ` <small>· ${esc(r.note)}</small>` : ''}</div></li>`)
                .join('')}</ul></section>`
            : ''
        }
        ${g.event ? `<p class="people-note">맺은 사건 ${ev ? `<button type="button" class="linky" data-uid="${esc(ev.uid)}">${esc(ev.title)}</button> <small>${esc(HT.formatRange(ev))}</small>` : `${esc(g.event)} <small>(연표에서 찾지 못함)</small>`}</p>` : ''}
        ${lensWarnHTML(g)}
        ${subdocsHTML(g.uid)}
        ${altHTML(g)}
        ${g.debate ? `<section class="sub-box"><h3>쟁점</h3><div class="desc">${esc(g.debate)}</div></section>` : ''}
        ${patchHTML(g)}
        <dl><dt>제공</dt><dd>${esc(g.packName)}${maker && maker.isOwn(g) ? ' <b>(고치는 중인 DLC)</b>' : ''}</dd>${g.note && g.description ? `<dt>메모</dt><dd>${esc(g.note)}</dd>` : ''}</dl>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${groupTree && (within.some(r => r.polityUid) || from.length || into.length) ? '<button class="btn btn-sm" data-act="group-tree" type="button" title="갈라짐 · 합쳐짐 · 이름 바꿈과 집권 기간을 연표 아래 넓은 창에 — 연도 눈금은 연표와 같은 자리">단체 계보</button>' : ''}
        ${wikiBtnText(g.uid) ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-act="wiki" type="button" title="이 단체의 위키 문서">${wikiBtnText(g.uid)}</button>` : ''}
        ${maker ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
        ${maker && maker.hasPatch(g.uid) ? '<button class="btn btn-sm" data-act="revert" type="button" title="고치는 DLC가 이 단체에 건 패치를 걷습니다">↩ 원래대로</button>' : ''}
        ${maker ? `<button class="btn btn-sm btn-danger" data-act="delete" type="button">${maker.isOwn(g) ? '🗑 삭제' : '🙈 숨기기'}</button>` : ''}
      </div>`;
  }
  /** 제도 창: 주제 · 나라 · 갈래 · 칸 목록(비운 경계를 채운 자리 · 온 곳) · 같은 갈래의 다른 나라 · 문서 */
  function institutionDetailHTML(x) {
    const P = x.polityItem;
    const track = trackOf(x.track);
    const has = !!docText(x.uid);
    const spans = x.spanList || [];
    const fromRefText = f => (f ? `${f.polity}${f.name ? ` «${f.name}»` : ''}` : '');
    const sources = [];
    for (const sp of spans) if (sp.fromItem && !sources.includes(sp.fromItem)) sources.push(sp.fromItem);
    const same = x.sameFamily || [];
    return `
      <div class="detail-head">
        <div class="badges">${x.track ? `<button type="button" class="badge is-link" style="--c:${track.color}" data-doc="track:${esc(track.id)}" title="${esc(track.name)} 문서">${esc(track.name)}</button>` : ''}<span class="badge" style="--c:${x.color}">제도</span><span class="badge" style="--c:${x.themeColor}">${esc(x.themeName)}</span>${x.family ? `<span class="badge" style="--c:${x.color}" title="제도 갈래 — 같은 갈래는 나라가 달라도 같은 색">${esc(x.family)}</span>` : ''}</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(x.themeName)} <small>${esc(x.polityName)}</small></h2>
        ${namesHeadHTML(x.names, 'polity')}
        <p class="when">${esc(spanText({ start: x.start, end: x.endY }))}</p>
        <p class="people-note">나라 ${polityChipHTML({ polityUid: P ? P.uid : null, color: P ? P.color : null, name: x.polityName })}${x.family ? ` <small>· 갈래 ${esc(x.family)}</small>` : ''}</p>
        ${namesRestHTML(x.names, 'polity')}
        <div class="desc${x.description ? '' : ' is-empty'}">${x.description ? esc(x.description) : '설명이 없습니다.'}</div>
        <section class="sub-box"><h3>칸 <small>${spans.length}</small></h3><ul class="kid-list">${spans
          .map(sp => `<li><button type="button" data-year="${sp.start}" data-prec="${precOf(sp)}" title="그 시기로"><b>${esc(HT.phaseRangeText(sp, P))}</b><span>${esc(sp.name)}${sp.note ? ` <small>${esc(sp.note)}</small>` : ''}${sp.from ? ` <i>← ${esc(fromRefText(sp.from))}에서 옴</i>` : ''}${sp.guess ? ' <i>경계는 짐작</i>' : ''}</span></button></li>`)
          .join('')}</ul>${sources.length ? `<p class="succ-cap">온 곳</p><div class="chips">${sources.map(p => polityChipHTML({ polityUid: p.uid, color: p.color, name: p.name })).join('')}</div>` : ''}</section>
        ${same.length ? `<section class="sub-box"><h3>같은 갈래의 다른 나라 <small>${same.length}</small></h3><div class="chips">${same.map(q => `<button type="button" class="chip" style="--c:${q.color}" data-uid="${esc(q.uid)}" title="${esc(`${q.name} — 제도 창`)}">${esc(q.polityName)} <small>${esc(spanText({ start: q.start, end: q.endY }))}</small></button>`).join('')}</div></section>` : ''}
        ${lensWarnHTML(x)}
        ${subdocsHTML(x.uid)}
        ${patchHTML(x)}
        <dl><dt>제공</dt><dd>${esc(x.packName)}${maker && maker.isOwn(x) ? ' <b>(고치는 중인 DLC)</b>' : ''}</dd></dl>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="focus" type="button">${icon('zoom-in')}이 시기로</button>
        ${wikiBtnText(x.uid) ? `<button class="btn btn-sm${has ? ' has-doc' : ''}" data-act="wiki" type="button" title="이 제도의 위키 문서">${wikiBtnText(x.uid)}</button>` : ''}
        ${maker ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
        ${maker && maker.hasPatch(x.uid) ? '<button class="btn btn-sm" data-act="revert" type="button" title="고치는 DLC가 이 제도에 건 패치를 걷습니다">↩ 원래대로</button>' : ''}
        ${maker ? `<button class="btn btn-sm btn-danger" data-act="delete" type="button">${maker.isOwn(x) ? '🗑 삭제' : '🙈 숨기기'}</button>` : ''}
      </div>`;
  }
  /** 나라 상세의 '단체' · '제도' 칩 (그 나라에 있던 단체 · 구성 나라로 든 연합, 그 나라의 제도 — 주제 차례) */
  function periodLensHTML(x) {
    if (x.kind !== 'period') return '';
    const links = x.groupLinks || [];
    const insts = x.institutionList || [];
    if (!links.length && !insts.length) return '';
    const ichip = i => `<button type="button" class="chip" style="--c:${i.color}" data-uid="${esc(i.uid)}" title="${esc(`${i.themeName} — ${(i.spanList || []).map(s => s.name).join(' → ')}`)}">${esc(i.themeName)}${i.family ? ` <small>${esc(i.family)}</small>` : ''}</button>`;
    const treeBtn = groupTree && links.some(l => l.role === 'within') ? '<button type="button" class="btn btn-sm sub-act" data-act="group-tree" title="이 나라에 있던 단체의 갈라짐 · 합쳐짐 · 이름 바꿈과 집권 기간을 연표 아래 넓은 창에">단체 계보</button>' : '';
    return `${links.length ? `<section class="sub-box"><h3>단체 <small>${links.length}</small>${treeBtn}</h3><div class="chips">${links.map(l => groupChipHTML(l.group, l.group.name, l.role === 'member' ? '구성 나라로' : l.group.typeName)).join('')}</div></section>` : ''}${
      insts.length ? `<section class="sub-box"><h3>제도 <small>${insts.length}</small></h3><div class="chips">${insts.map(ichip).join('')}</div></section>` : ''
    }`;
  }
  /** 사건 상세 머리의 주제 딱지 · 법 · 선거 딱지 (법 · 선거 딱지는 조약 딱지와 같은 마름모 꼴 — 주제 색) */
  function lensBadgesHTML(x) {
    if (x.kind !== 'event') return '';
    const law = x.law ? HT.readLaw(x.law) : null;
    const el = x.election ? HT.readElection(x.election) : null;
    return `${(x.themeRefs || []).map(t => `<span class="badge" style="--c:${t.color}" title="${esc(`주제 — ${t.name}${t.auto ? ' (주제 사전에 없는 이름)' : ''}`)}">${esc(t.name)}</span>`).join('')}${law ? `<span class="badge is-law">법${law.act ? ` · ${esc(HT.lawActName(law.act))}` : ''}</span>` : ''}${
      x.election ? `<span class="badge is-vote">선거${el && el.office ? ` · ${esc(el.office)}` : ''}</span>` : ''
    }`;
  }

  /* ---------- 법 규격 · 선거 규격의 상세 (설계 D5 결정 7 A — 조약문 양식 빌림 · docs/설계-10건/7-8-단체와-렌즈.md) ----------
     법: 머리 딱지 → 법 이름 → 법의 내력(같은 나라 · 같은 법 이름의 사건을 날짜 차례로: 제정 → 개정 → 폐지 · 사이 간격 · 이 사건 표시 ·
         폐지 기록이 없으면 그 뜻을 한 줄) → 설명 → 조항(이 사건에 적은 것) → 관련(그때의 법률 제도 칸 · 앞 고침).
     선거: 머리 딱지 → 뽑은 자리 → 기간 줄 → 결과(의석 막대 하나 · 과반 글 · 표 — 모임 이름이 단체 이름과 같으면 그 단체의 색이고 누르면 단체 창) → 설명 → 관련(그때의 선거 방식 · 앞 · 다음 선거).
     새 자료 칸 없이 모델의 사건에서 셉니다 — 모델마다 한 번 색인(lawVoteIndex). 법 이름이 없는 법 사건은 내력을 셀 수 없어 기본 기간 줄 그대로 */
  const LAW_ACT_ORDER = { enact: 0, amend: 1, repeal: 2 };
  const lawVoteMemo = new WeakMap();
  /** 사건이 속한 나라의 열쇠 — 나라를 찾은 사건은 그 나라, 아니면 트랙(같은 트랙 안에서만 모음) */
  const polityKeyOf = e => e.polityUid || `track:${e.track}`;
  /** 모델의 법 · 선거 색인: laws('나라 열쇠|법 이름' → [{ e, law }]) · votes(나라 열쇠 → [{ e, el }]) — 날짜 차례(같은 때면 제정 → 개정 → 폐지) */
  function lawVoteIndex() {
    const m = state.model;
    let ix = lawVoteMemo.get(m);
    if (ix) return ix;
    ix = { laws: new Map(), votes: new Map() };
    const push = (map, k, v) => (map.has(k) ? map.get(k).push(v) : map.set(k, [v]));
    for (const e of m.events) {
      const law = e.law ? HT.readLaw(e.law) : null;
      if (law && law.name) push(ix.laws, `${polityKeyOf(e)}|${law.name}`, { e, law });
      const el = e.election ? HT.readElection(e.election) : null;
      if (el) push(ix.votes, polityKeyOf(e), { e, el });
    }
    for (const list of ix.laws.values()) list.sort((a, b) => a.e.start - b.e.start || (LAW_ACT_ORDER[a.law.act] ?? 1) - (LAW_ACT_ORDER[b.law.act] ?? 1));
    for (const list of ix.votes.values()) list.sort((a, b) => a.e.start - b.e.start);
    lawVoteMemo.set(m, ix);
    return ix;
  }
  /** 그 나라에서 그해에 쓰던 제도 칸(주제 id) → { inst, sp } (없으면 null) */
  const institutionAt = (e, themeId, t) => {
    if (!e.polityUid || !state.model.institutionIndex) return null;
    for (const inst of state.model.institutionIndex.byPolity.get(e.polityUid) || []) {
      if (inst.themeId !== themeId) continue;
      const sp = (inst.spanList || []).find(s => s.start <= t && (t < s.end || (s.end === inst.endY && t <= s.end)));
      if (sp) return { inst, sp };
    }
    return null;
  };
  /** 관련 목록의 한 줄(조약의 '관련'과 같은 꼴 — 누르면 그 항목) */
  const relRowHTML = (tag, uid, text, when) => `<li><button type="button" data-uid="${esc(uid)}"><b>${esc(tag)}</b><span>${esc(text)}</span>${when ? `<small>${esc(when)}</small>` : ''}</button></li>`;
  /** 이 법 사건의 내력: 같은 나라 · 같은 법 이름의 사건들 (법 이름이 없으면 null) */
  const lawHistoryOf = x => {
    const law = x.kind === 'event' && x.law ? HT.readLaw(x.law) : null;
    if (!law || !law.name) return null;
    const list = lawVoteIndex().laws.get(`${polityKeyOf(x)}|${law.name}`) || [{ e: x, law }];
    return { law, list, i: list.findIndex(r => r.e === x) };
  };
  /** 법 이름 · 선거의 뽑은 자리 — 제목 바로 아래 한 줄 */
  function lensAkaHTML(x) {
    if (x.kind !== 'event') return '';
    const law = x.law ? HT.readLaw(x.law) : null;
    const el = x.election ? HT.readElection(x.election) : null;
    return `${law && law.name ? `<p class="aka">법 이름 ${esc(law.name)}</p>` : ''}${el && el.office ? `<p class="aka">뽑은 자리 ${esc(el.office)}</p>` : ''}`;
  }
  /** 법의 내력 — 조약의 날짜 진행 표(.tr-steps) 꼴. 기본 기간 줄 자리에 놓이므로 이 사건 줄에 날짜의 곁들임(음력 · 원문 표기)을 */
  function lawTopHTML(x) {
    const h = lawHistoryOf(x);
    if (!h) return '';
    const P = x.polityUid ? state.model.byUid.get(x.polityUid) : null;
    const sp = x.startUnknown ? 'y' : precOf(x);
    const orig = dateNoteOf(x);
    const sub = [sp === 'd' || sp === 'h' ? dayNote(x.start, !lunarAt(x)) : '', orig ? `원문 표기 ${orig}` : ''].filter(Boolean).join(' · ');
    const rows = h.list.map(({ e, law }) => ({ e, word: law.act ? HT.lawActName(law.act) : '기록', t: e.startUnknown ? null : e.start, at: e.startAt, text: e.startUnknown ? '미정' : HT.formatWhen(e, 'start'), here: e === x }));
    const last = h.list[h.list.length - 1];
    if (!last || last.law.act !== 'repeal') {
      const ended = P && !P.ongoing && P.endY != null && P.endY < HT.CURRENT_YEAR;
      rows.push({ word: '폐지', t: null, text: '기록 없음', note: ended ? '— 나라가 끝날 때까지 쓴 것으로 봄' : '— 지금도 쓰는 것으로 봄' });
    }
    const li = (r, i) => {
      const prev = rows[i - 1];
      const gap = prev && prev.t != null && r.t != null ? gapText(prev.t, prev.at, r.t, r.at) : '';
      const body = `<b>${esc(r.word)}</b><span>${esc(r.text)}${r.here ? ' <i>이 사건</i>' : r.e ? ` <i>${esc(r.e.title)}</i>` : r.note ? ` <i>${esc(r.note)}</i>` : ''}${r.here && sub ? `<small class="tr-sub">${esc(sub)}</small>` : ''}</span>${gap ? `<small>${esc(gap)}</small>` : ''}`;
      if (r.here) return `<li class="is-now">${r.t != null ? `<button type="button" data-year="${r.t}" data-prec="${precOf({ start: r.t, startAt: r.at })}" title="그때로">${body}</button>` : `<div class="tr-step">${body}</div>`}</li>`;
      return `<li>${r.e ? `<button type="button" data-uid="${esc(r.e.uid)}" title="${esc(`${r.e.title} — 사건 상세`)}">${body}</button>` : `<div class="tr-step">${body}</div>`}</li>`;
    };
    return `<section class="sub-box tr-dates law-history"><h3>법의 내력 <small>${h.list.length}</small></h3><ol class="tr-steps">${rows.map(li).join('')}</ol></section>`;
  }
  /** 선거 결과의 모임마다: 단체 이름과 같으면 그 단체(색 · 누르면 단체 창 — 이 나라에 있던 단체를 먼저), 아니면 팔레트 색(한 선거 안에서 겹치지 않게 다음 색으로) */
  function voteRowsOf(x, el) {
    const groups = state.model.groups || [];
    const used = new Set();
    const pal = HT.PASTEL.map(c => c.id);
    return (el.results || []).map(r => {
      const same = groups.filter(g => g.name === r.who);
      const g = same.find(q => (q.withinList || []).concat(q.memberList || []).some(w => w.polityUid && w.polityUid === x.polityUid)) || same[0] || null;
      let color = g ? g.color : HT.autoColor(`party:${r.who}`);
      if (!g) for (let k = pal.indexOf(color), n = 0; used.has(color) && n < pal.length; n++) color = pal[(k + n + 1) % pal.length];
      used.add(color);
      return Object.assign({}, r, { group: g, color });
    });
  }
  /** 선거 결과 — 의석 막대(의석을 적었으면 의석, 아니면 득표) · 과반 글 · 결과 표 (설명 바로 위) */
  function electionTopHTML(x) {
    const el = x.kind === 'event' && x.election ? HT.readElection(x.election) : null;
    if (!el || !(el.results || []).length) return el && el.note ? `<section class="sub-box el-box"><h3>결과 <small>적지 않음</small></h3><div class="desc">${esc(el.note)}</div></section>` : '';
    const rows = voteRowsOf(x, el);
    const num = n => (n == null ? '—' : Number(n).toLocaleString('ko-KR'));
    const hasVotes = rows.some(r => r.votes != null);
    const hasSeats = rows.some(r => r.seats != null);
    const by = hasSeats ? 'seats' : hasVotes ? 'votes' : '';
    const total = by ? rows.reduce((s, r) => s + (r[by] || 0), 0) : 0;
    let bar = '';
    let cap = '';
    if (total > 0) {
      const part = r => `${r.who} ${by === 'seats' ? `${num(r.seats)}석` : `${num(r.votes)}표 · ${((100 * (r.votes || 0)) / total).toFixed(1)}%`}`;
      bar = `<div class="el-bar" role="img" aria-label="${esc(rows.filter(r => r[by]).map(part).join(' · '))}">${rows
        .filter(r => r[by] > 0)
        .map(r => (r.group ? `<button type="button" class="el-seg" style="flex:${r[by]};--pc:${r.color}" data-uid="${esc(r.group.uid)}" title="${esc(`${part(r)} — 단체 창`)}"></button>` : `<i class="el-seg" style="flex:${r[by]};--pc:${r.color}" title="${esc(part(r))}"></i>`))
        .join('')}</div>`;
      const top = rows.reduce((a, r) => ((r[by] || 0) > (a[by] || 0) ? r : a), rows[0]);
      if (by === 'seats') {
        const half = Math.floor(total / 2) + 1;
        cap = top.seats >= half ? `과반 ${num(half)}석 — ${top.who} ${num(top.seats)}석` : `과반 ${num(half)}석 — 넘은 모임 없음 · 가장 많은 ${top.who} ${num(top.seats)}석`;
      } else cap = `가장 많은 표 — ${top.who} ${((100 * (top.votes || 0)) / total).toFixed(1)}%`;
    }
    const who = r => `<span class="el-who"><i style="--pc:${r.color}"></i>${r.group ? `<button type="button" class="linky" data-uid="${esc(r.group.uid)}" title="단체 창">${esc(r.who)}</button>` : esc(r.who)}${r.won ? '<em>당선</em>' : ''}</span>`;
    return `<section class="sub-box el-box"><h3>결과 <small>${by === 'seats' ? `의석 ${num(total)}` : by === 'votes' ? `득표 ${num(total)}` : `${rows.length}곳`}</small></h3>${bar}${cap ? `<p class="el-half">${esc(cap)}</p>` : ''}<table class="el-table"><thead><tr><th>누구</th>${
      hasVotes ? '<th class="num">득표</th>' : ''
    }${hasSeats ? '<th class="num">의석</th>' : ''}</tr></thead><tbody>${rows
      .map(r => `<tr${r.won ? ' class="is-won"' : ''}><td>${who(r)}</td>${hasVotes ? `<td class="num">${esc(num(r.votes))}</td>` : ''}${hasSeats ? `<td class="num">${r.seats == null ? '—' : `${esc(num(r.seats))}석`}</td>` : ''}</tr>`)
      .join('')}</tbody></table>${el.note ? `<div class="desc">${esc(el.note)}</div>` : ''}</section>`;
  }
  /** 사건 상세의 아래쪽: 법의 조항 · 관련(그때의 법률 · 앞 고침), 선거의 관련(그때의 선거 방식 · 앞 · 다음 선거), 이 사건으로 맺은 단체 */
  function lensBottomHTML(x) {
    if (x.kind !== 'event') return '';
    const law = x.law ? HT.readLaw(x.law) : null;
    const el = x.election ? HT.readElection(x.election) : null;
    const out = [];
    if (law) {
      const h = lawHistoryOf(x);
      const arts = (law.articles || []).map(a => HT.splitArticles(a)[0] || { no: '', title: '', text: a });
      const tag = law.act === 'amend' || law.act === 'repeal' ? HT.lawActName(law.act) : '';
      if (arts.length)
        out.push(`<section class="sub-box tr-articles"><h3>조항 <small>${arts.length}</small></h3><ol class="tr-arts">${arts
          .map(a => `<li><div class="tr-art">${a.no ? `<b class="tr-no">${esc(a.no)}</b> ` : ''}<span class="tr-at">${esc([a.title ? `(${a.title})` : '', a.text].filter(Boolean).join(' '))}</span>${tag ? `<span class="tr-tag">${esc(tag)}</span>` : ''}</div></li>`)
          .join('')}</ol>${law.note ? `<div class="desc">${esc(law.note)}</div>` : ''}</section>`);
      else if (law.note || !h) out.push(`<section class="sub-box tr-articles"><h3>법 <small>${law.act ? esc(HT.lawActName(law.act)) : '제정 · 개정 · 폐지를 적지 않음'}</small></h3>${law.note ? `<div class="desc">${esc(law.note)}</div>` : ''}</section>`);
      const rel = [];
      const cur = institutionAt(x, 'law', x.start);
      if (cur) rel.push(relRowHTML('그때의 법률', cur.inst.uid, cur.sp.name, HT.phaseRangeText(cur.sp, cur.inst.polityItem)));
      const prev = h && h.i > 0 ? h.list[h.i - 1].e : null;
      if (prev) rel.push(relRowHTML('앞 고침', prev.uid, prev.title, HT.formatRange(prev)));
      if (rel.length) out.push(`<section class="sub-box tr-related"><h3>관련</h3><ul class="succ-list">${rel.join('')}</ul></section>`);
    }
    if (el) {
      const rel = [];
      const cur = institutionAt(x, 'election', x.start);
      if (cur) rel.push(relRowHTML('그때의 선거 방식', cur.inst.uid, cur.sp.name, HT.phaseRangeText(cur.sp, cur.inst.polityItem)));
      const list = lawVoteIndex().votes.get(polityKeyOf(x)) || [];
      const i = list.findIndex(r => r.e === x);
      const office = r => (r.el.office && r.el.office !== el.office ? ` · ${r.el.office}` : '');
      if (i > 0) rel.push(relRowHTML('앞 선거', list[i - 1].e.uid, `${list[i - 1].e.title}${office(list[i - 1])}`, HT.formatRange(list[i - 1].e)));
      if (i >= 0 && i < list.length - 1) rel.push(relRowHTML('다음 선거', list[i + 1].e.uid, `${list[i + 1].e.title}${office(list[i + 1])}`, HT.formatRange(list[i + 1].e)));
      if (rel.length) out.push(`<section class="sub-box tr-related"><h3>관련</h3><ul class="succ-list">${rel.join('')}</ul></section>`);
    }
    if (x.groupRefs && x.groupRefs.length) out.push(`<section class="sub-box"><h3>이 일로 맺은 단체</h3><div class="chips">${x.groupRefs.map(g => groupChipHTML(g, g.name, g.typeName)).join('')}</div></section>`);
    return out.join('');
  }

  /* 상세의 갈래 표 — 앞에서부터 맞는 첫 갈래가 창을 그립니다 (새 종류의 창은 '기본' 앞에 한 줄로 더합니다).
     match(x, opts) 이 갈래가 맡으면 그리는 데 쓸 것(참인 값) · html(x, hit) 창의 내용 ·
     lane 연표에 제 줄이 있는가 — 없으면(시대 구분) 세로 닻을 걸지 않아, 화면 가운데 줄을 붙잡는 평소대로 둡니다 ·
     enter(x, hit, opts) 창이 연표에 남기는 것(칸 조명 · 그 시기 사건 강조 — leaveDetail이 치움) · spot 제 조명을 곧바로 다시 켜는 갈래(앞 조명을 끄고 켜는 헛일을 건너뜀) */
  const DETAIL_KINDS = [
    { id: 'epoch', lane: false, match: x => x.kind === 'epoch', html: x => epochDetailHTML(x) },
    { id: 'scope', lane: false, match: x => x.kind === 'scope', html: x => scopeDetailHTML(x) }, // 대범위 (7-4) — 제 줄이 없으므로 세로 닻 없음
    {
      id: 'cell', // 칸 창(지도자 · 내각 · 연호 · 도읍 — 칸 종류 표의 모든 종류): 연표에는 그 칸과 그 기간이 조명되고, 그 시기의 사건이 강조됩니다
      lane: true,
      spot: true,
      match: (x, opts) => parseCellRef(x, opts.cell),
      html: (x, ref) => cellDetailHTML(x, ref),
      enter: (x, { c }, opts) => {
        const { lo, hi } = cellSpanOf(x, c, opts.cell); // 칸이 품는 구간 — 이웃 칸과 겹치지 않음(경계 해는 뒤 칸의 것), 끝을 비운 칸은 풀어 둔 끝까지
        state.cell = opts.cell;
        state.spotKind = { id: 'cell', uid: x.uid, always: true, spots: [{ uid: x.uid, cell: opts.cell, start: lo, end: hi }] };
        timeline.setSpotlight(state.spotKind.spots[0]);
        spotHighlight(); // 그 정권 + 그 시기의 사건을 강조(메아리가 켜져 있으면 같은 시기 타국의 사건과 그 시기의 띠도 흐리지 않음 — HT.echoEvents)
      },
    },
    {
      id: 'dynasty', // 왕조 창: 기본 상세 그대로 + 다스린 나라의 띠마다 그 왕조의 기간이 조명됩니다 (강조는 '같은 시기를 타국에도'가 켜져 있을 때만 — 왕조 + 다스린 띠의 그 시기 사건)
      lane: true,
      match: x => {
        if (x.polityKind !== 'dynasty') return null;
        const spots = [];
        for (const h of x.hosts || []) for (const d of h.host.dynasties || []) if (d.dynasty === x && !spots.some(s => s.uid === h.host.uid && s.start === d.start)) spots.push({ uid: h.host.uid, start: d.start, end: d.end });
        return spots.length ? spots : null;
      },
      html: x => itemDetailHTML(x),
      enter: (x, spots) => {
        state.spotKind = { id: 'dynasty', uid: x.uid, always: false, spots };
        timeline.setSpotlight(spots);
        spotHighlight();
      },
    },
    { id: 'item', lane: true, match: () => true, html: x => itemDetailHTML(x) },
  ];
  /* 인물 창: 연표에는 섬긴 띠마다 그 섬긴 기간이 조명됩니다(두 정권을 섬겼으면 두 띠에 — setSpotlight의 배열). 세로 닻은 섬긴 정권의 줄(연표의 _anchorLane이 인물 → 그 줄).
     인물 단의 `인물 n명` 한 칸을 누르면(칸 참조 'figures') 그 정권의 상세가 열리고 인물 목록으로 내려갑니다 */
  DETAIL_KINDS.splice(DETAIL_KINDS.length - 1, 0, {
    id: 'figure',
    lane: true,
    match: x => x.kind === 'figure',
    html: x => figureDetailHTML(x),
    enter: x => {
      const spots = (x.services || []).filter(s => s.shown).map(s => ({ uid: s.polityUid, start: s.start, end: s.endY }));
      if (!spots.length) return;
      state.spotKind = { id: 'figure', uid: x.uid, always: false, spots }; // 강조는 '같은 시기를 타국에도'가 켜져 있을 때만 — 인물 + 활동한 띠의 그 시기 사건
      timeline.setSpotlight(spots);
      spotHighlight();
    },
  }, {
    id: 'figures-of',
    lane: true,
    match: (x, opts) => opts.cell === 'figures' && x.kind === 'period',
    html: x => itemDetailHTML(x),
    enter: () =>
      queueMicrotask(() => {
        /* 창이 막 열린 참이면 아직 숨어 있어 자리를 잴 수 없으므로, openDetail이 창을 보인 뒤에 */
        const body = detailEl.querySelector('.detail-body');
        const box = detailEl.querySelector('[data-box="figures"]');
        if (body && box && !detailEl.hidden) body.scrollTop += box.getBoundingClientRect().top - body.getBoundingClientRect().top - 8;
      }),
  });
  /* 시기 구분(학계)의 창: 칸 창과 같은 길(누른 시기와 그 기간 조명 · 그 시기의 사건 강조)에, 체계 · 같은 체계 안의 앞뒤 시기 · 체계 견주기 */
  DETAIL_KINDS.splice(DETAIL_KINDS.findIndex(k => k.id === 'cell'), 0, {
    id: 'phase',
    lane: true,
    spot: true,
    match: (x, opts) => (/^phase:/.test(String(opts.cell || '')) ? parseCellRef(x, opts.cell) : null),
    html: (x, ref) => phaseDetailHTML(x, ref),
    enter: (x, ref, opts) => {
      DETAIL_KINDS.find(k => k.id === 'cell').enter(x, ref, opts);
      fitPhaseBars();
    },
  });
  /* 지위 창: 칸 창과 같은 길(누른 지위와 그 기간 조명 · 그 시기의 사건 강조)에, 서열 · 지위 변천(승격 ▲ · 격하 ▼) · 그 기간의 지도자 · 정권 문서로 가는 길 */
  DETAIL_KINDS.splice(DETAIL_KINDS.findIndex(k => k.id === 'cell'), 0, {
    id: 'rank',
    lane: true,
    spot: true,
    match: (x, opts) => (/^rank:/.test(String(opts.cell || '')) ? parseCellRef(x, opts.cell) : null),
    html: (x, ref) => rankDetailHTML(x, ref),
    enter: (x, ref, opts) => DETAIL_KINDS.find(k => k.id === 'cell').enter(x, ref, opts),
  });
  /* 가문 창('house:id'): 제 줄이 없으므로 고르지 않고(pick: false — 연표가 흐려지지 않음) 세로 닻도 걸지 않으며, 그 가문의 칸(과 인물 막대)만 진하게 합니다.
     새 갈래의 자리 규칙대로 '기본'(item) 바로 앞에 — 가문 항목(itemKind 'house')만 맞으므로 다른 갈래와 겹치지 않습니다 */
  DETAIL_KINDS.splice(DETAIL_KINDS.findIndex(k => k.id === 'item'), 0, {
    id: 'house',
    lane: false,
    pick: false,
    match: x => (x.itemKind === 'house' ? x : null),
    html: x => houseDetailHTML(x),
    enter: x => {
      state.houseOn = true;
      lightHouses([x.id]); // D1 결정 7 A — 아래 파까지 조명 · 날짜 칸 괄호 · 그 띠의 다른 가문 칸 .55 (도우미가 없으면 옛 꼴)
    },
  });
  /* 단체 창 · 제도 창 (형식 버전 3): 제 줄이 없어 가문 창처럼 고르지 않고(pick: false) 세로 닻도 없음 — 띠 안 그림은 설계(D5) 뒤에 */
  DETAIL_KINDS.splice(
    DETAIL_KINDS.findIndex(k => k.id === 'item'),
    0,
    { id: 'group', lane: false, pick: false, match: x => (x.kind === 'group' ? x : null), html: x => groupDetailHTML(x) },
    { id: 'institution', lane: false, pick: false, match: x => (x.kind === 'institution' ? x : null), html: x => institutionDetailHTML(x) }
  );
  /* D1(10건 1 · 2): 승계표(나라 상세 자리 — 그 나라 줄에 닻) · 성씨 창(그 성의 모든 가문을 조명 — 고르지 않음) · 계보 전용 인물 창(띠에 그림이 없어 고르지 않고 닻도 없음) */
  DETAIL_KINDS.splice(DETAIL_KINDS.findIndex(k => k.id === 'cell'), 0, {
    id: 'succession',
    lane: true,
    match: (x, opts) => (opts.cell === 'succession' && x.kind === 'period' && (x.leaders || []).length && KVS() ? x : null),
    html: x => successionShellHTML(x),
    enter: (x, hit, opts) => mountSuccession(x, opts),
  });
  DETAIL_KINDS.splice(DETAIL_KINDS.findIndex(k => k.id === 'item'), 0, {
    id: 'surname',
    lane: false,
    pick: false,
    match: x => (x.itemKind === 'surname' ? x : null),
    html: x => surnameDetailHTML(x),
    enter: x => {
      state.houseOn = true;
      lightHouses(x.houses || []);
    },
  });
  DETAIL_KINDS.splice(DETAIL_KINDS.findIndex(k => k.id === 'figure'), 0, {
    id: 'kinfigure',
    lane: false,
    pick: false,
    match: x => (x.kind === 'figure' && x.lineageOnly ? x : null),
    html: x => kinFigureDetailHTML(x),
  });

  /** 앞 상세가 연표에 남긴 것(칸 조명 · 그 시기 사건 강조)을 치웁니다 — 창을 닫을 때 · 같은 해 보기로 바꿀 때 · 다른 상세를 열 때 모두 여기를 거칩니다.
      next = 곧 열릴 갈래 (없으면 모두 치움). 곧 열릴 칸 창(spot)은 제 조명 · 강조를 바로 다시 켜므로 끄고 켜는 헛일을 건너뜁니다.
      강조를 치운 뒤에는 검색어가 있으면 검색 강조를 되살립니다(refreshHighlight — 창의 강조가 검색 강조까지 지우지 않게) */
  function leaveDetail(next) {
    if (state.spotKind) {
      state.spotKind = null;
      if (!(next && next.spot)) {
        state.cell = null;
        timeline.setSpotlight(null);
        refreshHighlight();
        if (groupTree) groupTree.restoreSpot(); // 단체 계보 창에서 고른 단체의 조명을 다시 (곧 열릴 창이 제 조명을 켜면 그것이 덮음)
      }
    }
    if (state.houseOn && !(next && (next.id === 'house' || next.id === 'surname'))) {
      // 가문 강조: 곧 열릴 창이 다른 가문(· 성씨)이면 그 창이 제 가문으로 바꿉니다
      state.houseOn = false;
      timeline.setHouse(null);
    }
    succWait++; // 나눠 짓던 승계표는 지은 뒤에도 붙이지 않음
    if (state.kinSucc) {
      state.kinSucc.destroy();
      state.kinSucc = null;
    }
  }

  /** 메이커: 잠긴 팩의 항목 — 상세의 고치기 · 지우기 단추를 걷고 맨 위에 자물쇠 줄 (설계 3-5) */
  function lockDetail(x) {
    detailEl.querySelectorAll('[data-act="edit"], [data-act="delete"]').forEach(b => b.remove());
    detailEl.insertAdjacentHTML(
      'afterbegin',
      `<div class="mk-lockbar">🔒 «${esc(x.packName)}»의 항목 — 잠겨 있어 보기만 합니다.<span><button type="button" class="btn btn-sm" data-unlock="${esc(x.packId)}">🔓 자물쇠 풀기</button><button type="button" class="btn btn-sm" data-copy-own="${esc(x.uid)}">내 DLC로 복사</button></span></div>`
    );
  }
  function openDetail(uid, opts = {}) {
    const x = detailTarget(uid); // 모델 항목 또는 가문('house:id')
    if (!x) return closeDetail();
    /* 메이커: 상세와 편집 창은 같은 자리 — 편집 창이 붙어 있는 동안 다른 항목을 보러 가면 편집 창이 그 항목으로 바뀌고(고침이 있으면 먼저 물음),
       편집 창에서 고칠 수 없는 것(남의 시대 구분)이면 편집 창을 닫은 뒤 상세로 */
    if (maker && maker.pane.blocks()) {
      if (paneEditable(uid)) return void openEditorFor(uid); // 가문 창('house:id') · 남의 시대 구분 · 남의 대범위처럼 편집 창에서 고칠 수 없는 것은 편집 창을 닫은 뒤 상세로 (판단은 openEditorFor와 같은 paneEditable 하나 — 둘이 어긋나면 서로를 부르며 끝없이 돎)
      return void leaveEditor().then(ok => ok && openDetail(uid, opts));
    }
    let hit = null;
    const kind = DETAIL_KINDS.find(k => (hit = k.match(x, opts)));
    const prevSelected = state.selected;
    if (state.selected !== uid) state.detailLens = null;
    state.selected = uid;
    if (state.yearPanel) {
      state.yearPanel = null;
      $('#yearBtn').setAttribute('aria-pressed', 'false');
    }
    timeline.setSelected(kind.pick === false ? null : uid); // 제 줄이 없는 창(가문)은 고른 것으로 치지 않음 — 연표 전체가 흐려지지 않게
    if (kind.lane) timeline.setAnchor(uid, { reveal: state.selected !== prevSelected }); // 창이 열린 동안 그 줄을 제자리에 고정 — 누른 것은 달아나지 않고, 가려져 있을 때만 최소한으로 데려옵니다 (가운데 맞춤은 focusOn처럼 멀리 갈 때만)
    else timeline.setAnchor(null);
    if (mapHooks) mapHooks.onSelect(kind.pick === false ? null : uid);
    hiOwner = 'spot'; // 창을 열면(검색 결과를 눌러서도) 그 창의 조명 강조가 검색 강조보다 먼저 — 검색어가 입력칸에 남아도 창과 연표가 같은 답
    leaveDetail(kind);
    state.detailKind = kind.id;
    detailEl.innerHTML = kind.html(x, hit);
    if (opts.kinBack && kind.id !== 'succession') {
      const foot = detailEl.querySelector('.detail-foot');
      if (foot) foot.insertAdjacentHTML('afterbegin', kinBackHTML(opts.kinBack)); // 승계표 사람 줄 · 카드에서 연 창 — ◀ 승계표로 돌아감
    }
    if (maker && x.packId && maker.isLocked(x)) lockDetail(x);
    if (kind.enter) kind.enter(x, hit, opts);
    if (detailEl.hidden) HT.platform.trapBack(closeDetail);
    detailEl.hidden = false;
    syncInset();
  }

  /* ---------- 조약 (사건의 treaty 칸) — 상세의 조약문 양식 ----------
     머리(종류 배지 · 불평등 · 정식 명칭) → 당사국(편이 정확히 둘일 때만 좌우로 맞세우고, 그 밖에는 세로 목록) → 날짜 진행 표(체결 → 비준 → 발효 → 실효 · 사이 간격 · 끝난 까닭)
     → 설명 → 조항(본문은 접었다 펴기) → 관련(끝낸 전쟁 · 대체한 옛/새 조약 · 장소 · 언어). 조약이면 큰 틀의 '함께 겪은' 글과 기본 기간 줄은 끕니다.
     풀어낸 당사국 · 관련은 모델 전용 칸(x.treatyRefs · x.treatyBackRefs)에서 읽습니다 */
  const treatyOf = x => (x && x.treaty ? HT.readTreaty(x.treaty) || {} : null);
  const treatyBadgesHTML = x => {
    const t = treatyOf(x);
    return t ? `<span class="badge is-treaty">조약${t.type ? ` · ${esc(HT.treatyTypeName(t.type))}` : ''}</span>${t.unequal ? '<span class="badge badge-cert">불평등 조약</span>' : ''}` : '';
  };
  /** 두 때 사이의 간격 글 — 둘 다 날까지 적었으면 날 · 달로, 달까지면 달로, 그 밖에는 해로 */
  const gapText = (a, aAt, b, bAt) => {
    const d = b - a;
    if (!(d > 1e-6)) return '';
    const pa = precOf({ start: a, startAt: aAt });
    const pb = precOf({ start: b, startAt: bAt });
    const fine = p => p === 'd' || p === 'h';
    if (fine(pa) && fine(pb)) {
      const days = Math.round(d * 365.2425);
      if (days < 62) return `${days}일 뒤`;
      if (days < 730) return `${Math.round(days / 30.44)}개월 뒤`;
    } else if (pa !== 'y' && pb !== 'y') {
      const mo = Math.round(d * 12);
      if (mo < 24) return mo ? `${mo}개월 뒤` : '';
    }
    const y = Math.round(d);
    return y >= 1 ? `${y}년 뒤` : '같은 해';
  };
  function treatyPartiesHTML(x) {
    const refs = (x.treatyRefs && x.treatyRefs.parties) || [];
    if (!refs.length) return '';
    const card = r => {
      const chip = r.uid
        ? `<button type="button" class="chip" style="--c:${r.color}" data-uid="${esc(r.uid)}" title="${esc(`${r.name} 상세`)}">${esc(r.name)}</button>`
        : `<span class="chip is-off" title="연표에서 이 정권을 찾지 못했습니다 (트랙 · 이름을 확인하세요)">${esc(r.name || '이름 없음')}</span>`;
      const guess = r.uid && r.polity && !r.byName ? `<small class="tr-guess" title="적은 이름을 연표에서 찾지 못해 그 해의 그 나라 정권으로 놓았습니다">적은 이름 ${esc(r.polity)}</small>` : '';
      const signers = r.signatories.length
        ? `<ul class="tr-signers">${r.signatories.map(s => `<li>${s.figureUid ? `<button type="button" class="linky" data-uid="${esc(s.figureUid)}">${esc(s.name)}</button>` : esc(s.name)}${s.title ? ` <small>— ${esc(s.title)}</small>` : ''}</li>`).join('')}</ul>`
        : '';
      return `<div class="tr-party"><div class="tr-who">${chip}${r.role ? `<em class="tr-role">${esc(r.role)}</em>` : ''}${guess}</div>${signers}</div>`;
    };
    const sides = [...new Set(refs.map(r => r.side).filter(v => v != null))].sort((a, b) => a - b);
    let body;
    if (sides.length === 2 && refs.every(r => r.side != null)) body = `<div class="tr-sides">${sides.map(s => `<div class="tr-side"><p class="succ-cap">편 ${s}</p>${refs.filter(r => r.side === s).map(card).join('')}</div>`).join('')}</div>`;
    else if (sides.length) body = sides.concat(refs.some(r => r.side == null) ? [null] : []).map(s => `<p class="succ-cap">${s == null ? '편을 적지 않은 당사국' : `편 ${s}`}</p>${refs.filter(r => r.side === s).map(card).join('')}`).join('');
    else body = refs.map(card).join('');
    return `<section class="sub-box tr-parties"><h3>당사국 <small>${refs.length}</small></h3>${body}</section>`;
  }
  function treatyDatesHTML(x, t) {
    /* 체결 줄에는 기본 기간 줄이 하던 곁들임(날까지 적었으면 음력 · 일진 · 요일, 날짜 원문 표기)을 */
    const sp = x.startUnknown ? 'y' : precOf(x);
    const orig = dateNoteOf(x);
    const sub = [sp === 'd' || sp === 'h' ? dayNote(x.start, !lunarAt(x)) : '', orig ? `원문 표기 ${orig}` : ''].filter(Boolean).join(' · ');
    const rows = [{ word: '체결', t: x.startUnknown ? null : x.start, at: x.startAt, text: x.startUnknown ? '미정' : HT.formatWhen(x, 'start'), sub }];
    if (t.ratified != null) rows.push({ word: '비준', t: t.ratified, at: t.ratifiedAt, text: HT.formatDate(t.ratified, t.ratifiedAt) });
    if (t.effective != null) rows.push({ word: '발효', t: t.effective, at: t.effectiveAt, text: HT.formatDate(t.effective, t.effectiveAt) });
    const reason = t.endReason ? HT.treatyEndName(t.endReason) : '';
    if (x.ongoing) rows.push({ word: '실효', t: null, text: '아직 유효 (현재까지)' });
    else if (x.endUnknown) rows.push({ word: '실효', t: null, text: '미정', note: reason });
    else if (x.end != null) rows.push({ word: '실효', t: x.end, at: x.endAt, text: HT.formatWhen(x, 'end'), note: reason });
    else if (reason) rows.push({ word: '실효', t: null, text: '날짜를 적지 않음', note: reason });
    const li = (r, i) => {
      const prev = rows[i - 1];
      const gap = prev && prev.t != null && r.t != null ? gapText(prev.t, prev.at, r.t, r.at) : '';
      const body = `<b>${r.word}</b><span>${esc(r.text)}${r.note ? ` <i>${esc(r.note)}</i>` : ''}${r.sub ? `<small class="tr-sub">${esc(r.sub)}</small>` : ''}</span>${gap ? `<small>${esc(gap)}</small>` : ''}`;
      return `<li>${r.t != null ? `<button type="button" data-year="${r.t}" data-prec="${precOf({ start: r.t, startAt: r.at })}" title="그때로">${body}</button>` : `<div class="tr-step">${body}</div>`}</li>`;
    };
    return `<section class="sub-box tr-dates"><h3>날짜</h3><ol class="tr-steps">${rows.map(li).join('')}</ol></section>`;
  }
  function treatyArticlesHTML(t) {
    const list = t.articles || [];
    if (!list.length) return '';
    const head = (a, whole) => {
      const txt = a.title || (whole || !a.text || a.text.length <= 36 ? a.text || '' : `${a.text.slice(0, 36)}…`);
      return `${a.no ? `<b class="tr-no">${esc(a.no)}</b>` : ''}<span class="tr-at">${esc(txt)}</span>${a.tag ? `<span class="tr-tag">${esc(HT.articleTagName(a.tag))}</span>` : ''}`;
    };
    const li = a => (!a.text || (!a.title && a.text.length <= 60) ? `<li><div class="tr-art">${head(a, true)}</div></li>` : `<li><details class="tr-art"><summary>${head(a)}</summary><div class="desc">${esc(a.text)}</div></details></li>`);
    return `<section class="sub-box tr-articles"><h3>조항 <small>${list.length}</small></h3><ol class="tr-arts">${list.map(li).join('')}</ol></section>`;
  }
  /** 관련: 조약이면 끝낸 전쟁 · 대체한 옛 조약 · 대체한 새 조약 · 장소 · 언어, 조약이 아니면 이 일을 끝낸 조약만 (t = null) */
  function treatyRelatedHTML(x, t) {
    const m = state.model;
    const refs = x.treatyRefs || {};
    const back = x.treatyBackRefs || { concludedBy: [], supersededBy: [] };
    const row = (tag, uid, fallback) => {
      const e = uid ? m.byUid.get(uid) : null;
      if (e) return `<li><button type="button" data-uid="${esc(e.uid)}"><b>${esc(tag)}</b><span>${esc(e.title || e.name)}</span><small>${esc(HT.formatRange(e))}</small></button></li>`;
      return fallback ? `<li><button type="button" disabled title="연표에서 이 사건을 찾지 못했습니다"><b>${esc(tag)}</b><span>${esc(fallback)}</span></button></li>` : '';
    };
    const items = [];
    if (t && t.concludes) items.push(row('끝낸 전쟁', refs.concludes, t.concludes));
    if (t && t.supersedes) items.push(row('대체한 옛 조약', refs.supersedes, t.supersedes));
    for (const uid of back.supersededBy) items.push(row('대체한 새 조약', uid));
    for (const uid of back.concludedBy) items.push(row('끝낸 조약', uid));
    const meta = t ? `${t.place ? `<dt>장소</dt><dd>${esc(t.place)}</dd>` : ''}${t.languages ? `<dt>언어</dt><dd>${esc(t.languages.join(' · '))}</dd>` : ''}` : '';
    if (!items.filter(Boolean).length && !meta) return '';
    return `<section class="sub-box tr-related"><h3>${t ? '관련' : '조약'}</h3>${items.length ? `<ul class="succ-list">${items.join('')}</ul>` : ''}${meta ? `<dl class="tr-meta">${meta}</dl>` : ''}</section>`;
  }
  /** 조약 상세의 위쪽(정식 명칭 · 당사국 · 날짜 진행 표 — 기본 기간 줄 자리)과 아래쪽(조항 · 관련 — 설명 다음). 조약이 아닌 사건은 아래쪽에 "이 일을 끝낸 조약"만 */
  const treatyTopHTML = x => {
    const t = treatyOf(x);
    return `${t.formal ? `<p class="aka tr-formal">정식 명칭 ${esc(t.formal)}</p>` : ''}${treatyPartiesHTML(x)}${treatyDatesHTML(x, t)}`;
  };
  const treatyBottomHTML = x => {
    const t = treatyOf(x);
    return t ? `${treatyArticlesHTML(t)}${treatyRelatedHTML(x, t)}` : x.kind === 'event' ? treatyRelatedHTML(x, null) : '';
  };
  /** 검색 글에 더할 조약의 글: 종류 · 정식 명칭 · 장소 · 언어 · 당사국(적은 이름과 찾은 정권) · 역할 · 서명자 · 조항 번호와 제목 */
  const treatyHay = x => {
    const t = treatyOf(x);
    if (!t) return '';
    const refs = (x.treatyRefs && x.treatyRefs.parties) || [];
    return ['조약', HT.treatyTypeName(t.type), t.formal, t.place, (t.languages || []).join(' ')]
      .concat((t.parties || []).map(p => `${p.polity || ''} ${p.role || ''} ${HT.signersText(p.signatories)}`), refs.map(r => r.name), (t.articles || []).map(a => `${a.no || ''} ${a.title || ''}`))
      .filter(Boolean)
      .join(' ');
  };

  /** 기본 상세: 사건 · 시대 · 기관 · 문화 · 왕조 */
  function itemDetailHTML(x) {
    const track = trackOf(x.track);
    const isEvent = x.kind === 'event';
    const itemKind = HT.itemKindOf(x);
    const own = !!maker && maker.isOwn(x); // 메이커: 고치는 DLC의 제 항목 (지우면 삭제) — 남의 항목은 패치로 고치고, 지우는 대신 숨깁니다
    const patched = !!maker && maker.hasPatch(x.uid);
    const cat = isEvent ? state.model.categoryMap.get(x.category) : null;
    const imp = x.importance || 2;
    const views = x.perspectives || [];
    if (state.detailLens == null || (state.detailLens && !views.some(v => v.track === state.detailLens))) {
      const lens = state.ui.lens && state.ui.lens !== 'local' ? state.ui.lens : '';
      state.detailLens = views.some(v => v.track === lens) ? lens : '';
    }
    const view = views.find(v => v.track === state.detailLens) || null;
    const shownTitle = (view && view.title) || x.title || x.name;
    const shownDesc = view && view.description ? view.description : x.description;
    const lensTabs = views.length
      ? `<div class="lens-tabs" role="tablist"><button type="button" role="tab" data-lens="" aria-selected="${!view}">기본</button>${views
          .map(v => `<button type="button" role="tab" data-lens="${esc(v.track)}" aria-selected="${view === v}">${esc(trackOf(v.track).name)}</button>`)
          .join('')}</div>`
      : '';
    const source = x.source
      ? /^https?:\/\//i.test(x.source)
        ? `<a href="${esc(x.source)}" target="_blank" rel="noopener noreferrer">${esc(x.source)}</a>`
        : esc(x.source)
      : '';
    /* 배지는 모두 그 항목의 문서로 이어집니다 (트랙·정권·민족·분류) */
    const badge = (key, text, color, title) => `<button type="button" class="badge is-link" style="--c:${color}" data-doc="${esc(key)}" title="${esc(title || `${text} 문서`)}">${esc(text)}</button>`;
    const kindBadge = itemKind === 'organ' ? '기관' : itemKind === 'culture' ? '문화' : itemKind === 'dynasty' ? '왕조' : x.polityKind && x.polityKind !== 'state' ? HT.kindName(x.polityKind) : '시대';
    /* 날까지 적은 시작: 그날의 음력·일진·요일을 곁들입니다 */
    const sp = x.startUnknown ? 'y' : precOf(x);
    const dayLine = sp === 'd' || sp === 'h' ? `${x.end != null || x.ongoing ? '시작일 ' : ''}${dayNote(x.start, !lunarAt(x))}` : '';
    const origDate = dateNoteOf(x);
    const hs = isEvent ? '' : HT.historicityOf(x); // 실재성 (8-4 마)
    const lawTop = x.treaty ? '' : lawTopHTML(x);
    return `
      <div class="detail-head">
        <div class="badges">${badge(`track:${track.id}`, track.name, track.color)}${
          x.polityName && x.polityUid ? badge(x.polityUid, x.polityName, x.polityColor) : ''
        }${!isEvent && x.peopleName ? badge(`people:${x.peopleId}`, x.peopleName, x.peopleColor) : ''}${houseBadge(x, itemKind === 'period' ? '국성' : '가문')}${
          isEvent ? badge(`category:${cat.id}`, cat.name, cat.color) : `<span class="badge is-kind is-${itemKind}">${esc(kindBadge)}${x.legendary ? ' · 전승' : ''}</span>`
        }${treatyBadgesHTML(x)}${lensBadgesHTML(x)}${hs ? `<span class="badge badge-hs is-${hs}" title="${esc(`실재성 — ${HT.HISTORICITY.find(h => h.id === hs).hint}`)}">${esc(HT.historicityName(hs))}</span>` : ''}${
          x.certainty && x.certainty !== 'accepted' ? `<span class="badge badge-cert">${esc(HT.certaintyName(x.certainty))} 연대</span>` : ''}${
          x.startUnknown || x.endUnknown ? '<span class="badge badge-cert">연도 미정</span>' : ''
        }</div>
        <button class="icon-btn" data-act="close" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        ${lensTabs}
        <h2>${esc(shownTitle)}</h2>
        ${namesHeadHTML(x.names, isEvent ? null : 'polity')}
        ${view && view.title && view.title !== x.title ? `<p class="aka">기본 이름: ${esc(x.title)}</p>` : ''}
        ${!view && views.some(v => v.title) ? `<p class="aka">다른 이름: ${views.filter(v => v.title).map(v => `${esc(trackOf(v.track).name)} ${esc(v.title)}`).join(' · ')}</p>` : ''}
        ${lensAkaHTML(x)}
        ${isEvent && x.place ? placeHTML(x.place, '장소') : ''}
        ${
          x.treaty
            ? treatyTopHTML(x) /* 조약: 기본 기간 줄 대신 정식 명칭 · 당사국 · 날짜 진행 표 */
            : lawTop /* 법(이름이 있는 것): 기본 기간 줄 대신 법의 내력 (설계 D5 결정 7) */ ||
              `<p class="when">${esc(HT.formatRange(x))}${origDate ? ` <span class="when-orig" title="DLC에 적힌 날짜 표기 그대로">· 원문 표기 ${esc(origDate)}</span>` : ''}${
          dayLine ? `<small class="when-sub">${esc(dayLine)}</small>` : ''
        }</p>`
        }
        ${x.parentUid ? `<p class="crumb"><button type="button" class="linky" data-uid="${esc(x.parentUid)}">${esc(x.parentTitle)}</button> 안의 사건</p>` : ''}
        ${x.startUnknown ? `<p class="range-note">시작 연도 미정 — 연표에는 ${esc(HT.formatWhen(x, 'start'))} 무렵에 자리를 잡았습니다</p>` : ''}
        ${x.endUnknown ? `<p class="range-note">끝 연도 미정 — 연표에는 ${esc(endWhen(x))} 무렵까지로 그렸습니다</p>` : ''}
        ${x.startRange ? `<p class="range-note">시작 — 이르면 ${esc(rangeWhen(x, 'startRange', 0))}, 늦으면 ${esc(rangeWhen(x, 'startRange', 1))}</p>` : ''}
        ${x.endRange ? `<p class="range-note">끝 — 이르면 ${esc(rangeWhen(x, 'endRange', 0))}, 늦으면 ${esc(rangeWhen(x, 'endRange', 1))}</p>` : ''}
        ${!x.treaty && x.sharedWith && x.sharedWith.length ? `<p class="shared-note">${esc([x.polityName].concat(x.sharedWith).filter(Boolean).join(' · '))}가 함께 겪은 일입니다.</p>` : ''}
        ${peopleUnderHTML(x)}
        ${electionTopHTML(x)}
        ${namesRestHTML(x.names, isEvent ? null : 'polity')}
        <div class="desc${shownDesc ? '' : ' is-empty'}">${shownDesc ? esc(shownDesc) : '설명이 없습니다.'}</div>
        ${historicityHTML(x, hs)}
        ${treatyBottomHTML(x)}
        ${lensBottomHTML(x)}
        ${
          x.children && x.children.length
            ? `<section class="sub-box"><h3>포함된 사건 <small>${x.children.length}</small></h3><ul class="kid-list">${x.children
                .map(c => `<li><button type="button" data-uid="${esc(c.uid)}"><b>${esc(HT.formatRange(c))}</b><span>${esc(c.title)}</span></button></li>`)
                .join('')}</ul></section>`
            : ''
        }
        ${eventFiguresHTML(x)}
        ${partOfHTML(x)}
        ${periodScopesHTML(x)}
        ${periodLensHTML(x)}
        ${dynastyHTML(x)}
        ${x.polityKind === 'dynasty' && (x.hosts || []).length ? `${echoSwitchHTML()}${echoSlotHTML()}` : ''}
        ${x.polityKind === 'dynasty' ? '' : successionHTML(x)}
        ${ranksHTML(x)}
        ${phasesHTML(x)}
        ${cellsHTML('지도자', x.leaders, '명', x, 'leaders')}
        ${cellsHTML('내각', x.cabinets, '개', x, 'cabinets')}
        ${cellsHTML('연호', x.eras, '개', x, 'eras')}
        ${capitalsHTML(x)}
        ${figuresHTML(x)}
        ${subdocsHTML(x.uid)}
        ${altHTML(x)}
        ${x.debate ? `<section class="sub-box"><h3>쟁점</h3><div class="desc">${esc(x.debate)}</div></section>` : ''}
        ${patchHTML(x)}
        ${x.tags && x.tags.length ? `<div class="tags">${x.tags.map(t => `<span class="tag">#${esc(t)}</span>`).join('')}</div>` : ''}
        <dl>
          <dt>제공</dt><dd>${esc(x.packName)}${own ? ' <b>(고치는 중인 DLC)</b>' : x.overridden ? ' <b>(옮기지 못한 옛 내 수정)</b>' : ''}</dd>
          ${isEvent ? `<dt>중요도</dt><dd>${'★'.repeat(imp)}${'☆'.repeat(3 - imp)}</dd>` : ''}
          ${x.note ? `<dt>메모</dt><dd>${esc(x.note)}</dd>` : ''}
          ${source ? `<dt>출처</dt><dd>${source}</dd>` : ''}
        </dl>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="focus" type="button">${icon('zoom-in')}이 위치로</button>
        ${wikiBtnText(x.uid) ? `<button class="btn btn-sm" data-act="wiki" type="button" title="이 항목의 위키 문서">${wikiBtnText(x.uid)}</button>` : ''}
        ${maker ? '<button class="btn btn-sm" data-act="edit" type="button">✎ 수정</button>' : ''}
        ${patched ? '<button class="btn btn-sm" data-act="revert" type="button" title="고치는 중인 DLC가 이 항목에 건 패치를 걷습니다">↩ 원래대로</button>' : ''}
        ${maker ? `<button class="btn btn-sm btn-danger" data-act="delete" type="button">${own ? '🗑 삭제' : '🙈 숨기기'}</button>` : ''}
      </div>`;
  }
  /** 항목에 딸린 하위 문서(국가/역사, 국가/개요 …) 목록 */
  function subdocsHTML(baseKey) {
    const subs = subdocsOf(baseKey);
    if (!subs.length) return '';
    return `<section class="sub-box"><h3>하위 문서 <small>${subs.length}</small></h3><div class="chips">${subs.map(s => `<button type="button" class="chip is-doc" data-doc="${esc(s.key)}">${esc(s.sub)}</button>`).join('')}</div></section>`;
  }

  function closeDetail() {
    state.selected = null;
    state.yearPanel = null;
    if (!detailEl.hidden) HT.platform.releaseBack();
    detailEl.hidden = true;
    syncInset();
    const editing = maker && maker.pane.isOpen() && state.model.byUid.has(state.editing) ? state.editing : null; // 메이커: 편집 창이 열려 있으면 고치는 항목은 고른 채로
    const kindOf = editing ? state.model.byUid.get(editing).kind : '';
    timeline.setSelected(kindOf === 'group' || kindOf === 'institution' ? null : editing); // 단체 · 제도는 연표에 그림이 없어 고르지 않음
    if (!editing) {
      timeline.setAnchor(null);
      if (maker && !state.editing) maker.selectItems([]); // 새 편집 창을 채우는 중이면 그 항목의 선택을 지키기
    }
    leaveDetail();
    if (mapHooks) mapHooks.onSelect(null);
  }

  /* ---------- 같은 해 보기 (확대했으면 같은 달 · 같은 날) ---------- */
  /* 기준 단위마다: 앞뒤 범위 목록(년 단위 수) · 처음 범위 · 글자 */
  const PANEL = {
    y: { word: '해', badge: '기준 연도', unit: '년', windows: [0, 5, 10, 25, 50, 100], def: 10 },
    m: { word: '달', badge: '기준 달', unit: '개월', windows: [0, 1 / 12, 3 / 12, 6 / 12, 1, 5], def: 1 / 12 },
    d: { word: '날', badge: '기준 날짜', unit: '일', windows: [0, 3 / 365.25, 7 / 365.25, 1 / 12, 3 / 12, 1], def: 7 / 365.25 },
  };
  const windowText = (w, unit) => (!w ? `±0${unit}` : w >= 1 - 1e-9 ? `±${Math.round(w)}년` : w >= 1 / 12 - 1e-9 ? `±${Math.round(w * 12)}개월` : `±${Math.round(w * 365.25)}일`);
  /**
   * t가 든 해(prec 'm'이면 달, 'd'면 날)를 기준으로 그때 각 나라와 앞뒤 사건을 봅니다.
   * end를 주면 [t, end)를 그대로 씁니다 (검색한 음력 달처럼 서력 달과 어긋나는 구간). label은 제목, cal은 그 날짜를 적은 달력
   */
  function openYearPanel(t, win, { prec = 'y', end = null, label = null, cal = 'civil' } = {}) {
    if (maker && maker.pane.blocks()) return void leaveEditor().then(ok => ok && openYearPanel(t, win, { prec, end, label, cal })); // 메이커: 상세 자리를 쓰는 편집 창을 먼저 닫고
    const P = PANEL[prec] ? prec : 'y';
    const a = end != null ? t : snapTo(t, P);
    const b = end != null ? end : unitEnd(a, P);
    const cur = state.yearPanel;
    const w = win != null ? win : cur && cur.prec === P ? cur.window : PANEL[P].def;
    state.yearPanel = { year: HT.yearOf(a), t: a, end: b, prec: P, window: w, label, cal };
    state.selected = null;
    timeline.setSelected(null);
    timeline.setAnchor(null); // 고른 항목이 없어졌으니 세로 닻도 풉니다 (화면 가운데 줄을 붙잡는 평소대로)
    leaveDetail(); // 앞 상세가 남긴 칸 조명 · 강조도 함께 (상세를 닫지 않고 넘어오므로)
    timeline.setMarker(a);
    $('#yearBtn').setAttribute('aria-pressed', 'true');
    renderYearPanel();
  }

  function closeYearPanel() {
    state.yearPanel = null;
    timeline.setMarker(null);
    $('#yearBtn').setAttribute('aria-pressed', 'false');
    if (!detailEl.hidden) HT.platform.releaseBack();
    detailEl.hidden = true;
    syncInset();
  }

  /** 같은 해 보기에서 전설 · 부정된 나라는 옅은 글씨로 (8-4 마) */
  const yearHs = p => (['legendary', 'refuted'].includes(HT.historicityOf(p)) ? ` is-hs-${HT.historicityOf(p)}` : '');
  function renderYearPanel() {
    const yp = state.yearPanel;
    const { t: a, end: b, prec, window: w } = yp;
    const P = PANEL[prec];
    const m = state.model;
    const shownTracks = m.tracks.filter(t => state.ui.tracks[t.id] !== false);
    /* 걸침: [a, b) 구간과 겹치면 — 연도만 적은 항목은 그해 전체에 걸친 것으로 봅니다 (endIn) */
    const eras = shownTracks
      .map(t => ({ track: t, periods: m.periods.filter(p => p.track === t.id && p.start < b && endIn(p) >= a) }))
      .filter(x => x.periods.length);
    const events = state.visible
      .filter(x => x.kind === 'event' && x.start < b + w && endIn(x) >= a - w)
      .sort((p, q) => p.start - q.start);
    const title = yp.label || (prec === 'y' ? HT.formatYear(a) : HT.cal.formatT(a, prec));
    /* 제목 아래 곁들임: 해·달은 그해의 간지, 날은 음력·일진·요일 */
    const sub = prec === 'd' ? dayNote(a, !HT.cal.get(yp.cal).lunar) : `${HT.ganji(yp.year)}년`;
    const wi = P.windows.findIndex(v => Math.abs(v - w) < 1e-9);
    detailEl.innerHTML = `
      <div class="detail-head">
        <div class="badges"><span class="badge" style="--c:var(--warn)">${P.badge}</span></div>
        <button class="icon-btn" data-act="close-year" type="button" aria-label="닫기">✕</button>
      </div>
      <div class="detail-body">
        <h2>${esc(title)}</h2>
        <p class="when-line">${esc(sub)}</p>
        <p class="when">그때 각 나라는</p>
        <ul class="year-eras">${
          eras
            .map(({ track, periods }) => `<li><span class="badge" style="--c:${track.color}">${esc(track.name)}</span> ${periods.map(p => `<button type="button" class="linky${yearHs(p)}" data-uid="${esc(p.uid)}"${yearHs(p) ? ` title="${esc(HT.historicityName(HT.historicityOf(p)))}"` : ''}>${esc(p.name)}</button>${yearRankHTML(p, a, b)}`).join(' · ')}</li>`)
            .join('') || `<li class="muted">이 ${P.word}에 걸친 시대 정보가 없습니다.</li>`
        }</ul>
        ${yearPhasesHTML(eras, a, b)}
        ${yearFiguresHTML(a, b)}
        <div class="year-window">앞뒤 <select id="yearWindow" aria-label="앞뒤 범위">${P.windows.map((v, i) => `<option value="${i}"${i === wi ? ' selected' : ''}>${windowText(v, P.unit)}</option>`).join('')}</select> 안의 사건 <b>${events.length}</b>건</div>
        <ul class="year-events">${
          events
            .map(e => `<li><button type="button" data-uid="${esc(e.uid)}"><span class="sr-dot${e.treaty ? ' is-treaty' : ''}" style="--c:${e.polityColor || e.color}"></span><span class="y">${esc(HT.formatRange(e))}</span><span class="t">${esc(e.title)}</span><span class="tr">${esc(trackOf(e.track).name)}</span></button></li>`)
            .join('') || '<li class="muted">가까운 사건이 없습니다.</li>'
        }</ul>
      </div>
      <div class="detail-foot">
        <button class="btn btn-sm" data-act="year-here" type="button">${icon('zoom-in')}이 ${P.word}로 이동</button>
        <button class="btn btn-sm" data-act="close-year" type="button">닫기</button>
      </div>`;
    if (detailEl.hidden) HT.platform.trapBack(closeYearPanel);
    detailEl.hidden = false;
    syncInset();
    $('#yearWindow').addEventListener('change', e => openYearPanel(a, P.windows[Number(e.target.value)], { prec, end: b, label: yp.label, cal: yp.cal }));
  }

  /* ---------- 조명의 사건 · 같은 시기 타국 (HT.echoEvents — 창과 연표가 같은 답) ----------
     창이 켠 조명(state.spotKind.spots)으로 한 번 셈해, 연표의 강조(그 창이 고른 것 + 제 조명에 든 사건 — 강조 밖은 흐림)와 창의 목록이 같은 결과를 씁니다.
     칸 · 시기 · 지위 창은 늘, 왕조 · 인물 창은 '같은 시기를 타국에도'가 켜져 있을 때만 강조를 겁니다(always).
     메아리가 켜져 있으면: 그 시기 타국의 사건은 흐리지 않고 제 사건과 같은 밝기(연표 is-echo-hit), 흐린 띠라도 그 시기만큼은 흐리지 않음(lit),
     창에는 '같은 시기 타국' 묶음(나라별 · 건수 — 모두 40건이 넘으면 나라마다 중요한 5건 + 더 보기, 묶음이 8곳을 넘으면 나머지는 접어 둠).
     강조는 나중에 건 쪽이 이깁니다(hiOwner): 창이 열린 뒤에 검색어를 고쳤으면 검색 강조(묶음은 그대로 셈 — 검색어를 비우면 창의 강조가, 창을 닫으면 검색 강조가 되살아남),
     검색 결과를 눌러 창을 열었거나 검색한 뒤에 창을 열었으면 창의 강조(검색어가 입력칸에 남아 있어도 — 창과 연표가 같은 답) */
  const echoOn = () => !!(state.ui.show || {}).spotEcho;
  function spotCalc(spots, echo = echoOn()) {
    const bands = timeline.echoBands();
    return HT.echoEvents({ events: state.visible || [], spots, echo, bandOf: uid => bands.get(uid) || null, trackOrder: id => timeline.trackOrder(id), trackShown: id => state.ui.tracks[id] !== false && state.model.tracks.some(t => t.id === id) });
  }
  function spotHighlight({ animate = false } = {}) {
    const k = state.spotKind;
    const echo = echoOn();
    const res = k ? spotCalc(k.spots, echo) : null;
    fillEchoSlot(k && echo ? res : null, animate);
    if (searchOwns()) return res; // 창이 열린 뒤에 검색했으면 검색 강조가 먼저
    if (!k || (!k.always && !echo)) timeline.setHighlight(null);
    else timeline.setHighlight(new Set([k.uid, ...res.ownUids]), { spot: true, echo: echo ? res.echoKeys : null, lit: echo, layout: k.always }); // 왕조 · 인물 창(스위치를 켤 때만 강조)은 사건 배치에 쓰지 않음 — 켜고 끌 때 이름표 · 부모 펼침이 바뀌지 않게
    return res;
  }
  /** 창이 연표에 건 강조를 지금 상태로: 검색이 강조를 가지면(searchOwns) 검색 강조, 아니면 열린 창의 조명 강조(없으면 끔) */
  function refreshHighlight() {
    if (searchOwns()) runSearch();
    else spotHighlight();
  }
  /** 창 안의 스위치 '같은 시기를 타국에도' (필터의 체크와 같은 설정 — 칸 · 시기 · 지위 · 왕조 · 인물 창) */
  function echoSwitchHTML() {
    return `<label class="check spot-echo" title="켜면 이 창이 연표에 조명한 기간을, 그때 있던 타국의 띠에서도 흐리지 않고 이 조명과 같은 짙기로 칠하고 그 시기 타국의 사건도 제 사건처럼 밝게 남깁니다 — 아래 '같은 시기 타국'에 나라별로 (필터의 '선·견해' 묶음에 같은 체크가 있습니다)"><input type="checkbox" data-spot-echo${echoOn() ? ' checked' : ''}> 같은 시기를 타국에도</label>`;
  }
  /** '같은 시기 타국' 묶음이 들어갈 자리 — 스위치를 켜고 끌 때 창을 다시 그리지 않고 이 자리만 바꿔 끼웁니다(fillEchoSlot) */
  function echoSlotHTML() {
    return '<div class="echo-slot" data-echo-slot></div>';
  }
  const ECHO_MAX = 40; // 모두 이만큼이 넘으면 나라마다 중요한 몇 건만
  const ECHO_EACH = 5;
  const ECHO_GROUPS = 8; // 묶음이 이만큼이 넘으면 나머지는 접어 둠 (펼칠 때 목록을 만듦)
  function echoRowsHTML(rows) {
    return rows
      .map(({ e, kids, with: w }) => `<li><button type="button" data-uid="${esc(e.uid)}"><span class="sr-dot${e.treaty ? ' is-treaty' : ''}" style="--c:${e.polityColor || e.color}"></span><span class="y">${esc(HT.formatRange(e))}</span><span class="t">${esc(e.title)}${kids ? ` <span class="tr">포함 ${kids}</span>` : ''}${w.length ? ` <span class="tr">함께 · ${esc(w.join(' · '))}</span>` : ''}</span></button></li>`)
      .join('');
  }
  /** 묶음 하나(나라 · 정권이 없는 사건은 트랙): 머리에 색 점 · 이름 · 트랙 · 건수(접힌 트랙 · 줄이면 '접힘'), 많으면 중요한 몇 건만(보이는 차례는 연대순) + 더 보기 */
  function echoGroupHTML(g, big, open) {
    const b = g.band;
    const track = trackOf(g.track);
    let rows = g.rows;
    if (big && !open && rows.length > ECHO_EACH) {
      const top = new Set(rows.slice().sort((x, y) => (y.e.importance || 2) - (x.e.importance || 2) || x.e.start - y.e.start).slice(0, ECHO_EACH));
      rows = rows.filter(r => top.has(r));
    }
    const more = g.rows.length - rows.length;
    return `<div class="echo-group" data-echo-group="${esc(g.key)}"><p class="echo-cap"><i style="--c:${b ? b.color : track.color}"></i><b>${esc(b ? b.name : track.name)}</b><small>${esc(b ? track.name : '정권 없는 사건')} · ${g.rows.length}건</small>${g.folded ? '<small class="echo-tag" title="접힌 트랙 · 접힌 줄이라 연표에는 보이지 않습니다">접힘</small>' : ''}</p><ul class="year-events">${echoRowsHTML(rows)}</ul>${
      more ? `<button type="button" class="linky echo-more" data-echo-more="${esc(g.key)}">${more}건 더 보기</button>` : ''
    }</div>`;
  }
  function echoBoxHTML(res) {
    const big = res.count > ECHO_MAX;
    const rest = Math.max(0, res.groups.length - ECHO_GROUPS);
    return `<section class="sub-box echo-box"><h3>같은 시기 타국 <small>${res.count ? `${res.groups.length}곳 · ${res.count}건${big ? ` · 나라마다 중요한 ${ECHO_EACH}건` : ''}` : '없음'}</small></h3>${
      res.count
        ? res.groups.slice(0, ECHO_GROUPS).map(g => echoGroupHTML(g, big, false)).join('') + (rest ? `<button type="button" class="linky echo-rest" data-echo-rest>타국 ${rest}곳 더 펼치기</button>` : '')
        : '<p class="succ-cap">그 시기 타국의 사건이 없습니다.</p>'
    }</section>`;
  }
  /** 묶음 자리 채우기: 창을 열 때 · 목록만 바뀔 때는 그 자리에서, 스위치로 생기고 없어질 때는(animate) 높이가 --t-move로 흐르고 내용은 --t-in에 떠오름 / --t-out에 옅어짐 */
  function fillEchoSlot(res, animate) {
    const slot = detailEl.querySelector('[data-echo-slot]');
    if (!slot) return;
    const html = res ? echoBoxHTML(res) : '';
    slot._res = res;
    if (slot._html === html) return;
    const had = !!slot._html;
    slot._html = html;
    if (slot._anim) {
      for (const a of slot._anim) a.cancel();
      slot._anim = null;
    }
    const M = HT.motion;
    if (!animate || had === !!html) {
      slot.innerHTML = html;
      return;
    }
    const h0 = slot.getBoundingClientRect().height;
    if (html) slot.innerHTML = html;
    const h1 = html ? slot.scrollHeight : 0;
    const box = slot.firstElementChild;
    const grow = slot.animate([{ height: `${h0}px` }, { height: `${h1}px` }], { duration: M.T.move, easing: M.C.spring, fill: html ? 'none' : 'forwards' });
    const fade = box ? box.animate(html ? [{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }] : [{ opacity: 0 }], { duration: html ? M.T.in : M.T.out, easing: html ? M.C.ease : 'ease-in', fill: html ? 'none' : 'forwards' }) : null;
    slot._anim = [grow, fade].filter(Boolean);
    grow.onfinish = () => {
      if (!html) {
        slot.innerHTML = '';
        for (const a of slot._anim || []) a.cancel();
      }
      slot._anim = null;
    };
  }
  detailEl.addEventListener('click', e => {
    const more = e.target.closest('[data-echo-more]');
    const rest = e.target.closest('[data-echo-rest]');
    const slot = (more || rest) && (more || rest).closest('[data-echo-slot]');
    const res = slot && slot._res;
    if (!res) return;
    const big = res.count > ECHO_MAX;
    if (more) {
      const g = res.groups.find(q => q.key === more.dataset.echoMore);
      if (g) more.closest('.echo-group').outerHTML = echoGroupHTML(g, big, true);
    } else rest.outerHTML = res.groups.slice(ECHO_GROUPS).map(g => echoGroupHTML(g, big, false)).join('');
  });

  /* ---------- 조명 메아리 스위치 ----------
     칸 상세 안의 체크와 필터의 체크(#spotEchoToggle)는 같은 설정(ui.show.spotEcho)입니다 — 어느 쪽을 눌러도 둘이 함께 바뀝니다 */
  function setSpotEcho(on) {
    state.ui.show = Object.assign({}, state.ui.show, { spotEcho: !!on });
    HT.store.set(K.ui, state.ui);
    timeline.setShow({ spotEcho: !!on });
    const box = $('#spotEchoToggle');
    if (box) box.checked = !!on;
    const sw = detailEl.querySelector('[data-spot-echo]');
    if (sw) sw.checked = !!on;
    if (state.spotKind) spotHighlight({ animate: true }); // 창을 다시 그리지 않고 강조 · '같은 시기 타국' 묶음만 (스크롤 그대로)
  }
  detailEl.addEventListener('change', e => {
    if (e.target.matches('[data-spot-echo]')) setSpotEcho(e.target.checked);
  });

  /* ---------- 기간 재기 ---------- */
  function showMeasure(r) {
    const el = $('#measureInfo');
    if (!r) {
      el.hidden = true;
      $('#statusPill').hidden = true;
      return;
    }
    // 두 끝과 길이는 지금 확대 정도에 맞춰: 넓게 보면 햇수, 가까이 보면 개월·일·시간까지
    const prec = precFor(Math.min(timeline.span(), r.to - r.from)); // 넓게 보면서 짧게 재도 "0년"이 아니라 개월·일로
    el.innerHTML = `${icon('ruler')}${esc(spanRange(r.from, r.to, prec))} · <b>${esc(durationText(r.from, r.to, prec))}</b> <button class="linky" data-clear-measure type="button">지우기</button>`;
    el.hidden = false;
    $('#statusPill').hidden = false;
  }
  $('#measureInfo').addEventListener('click', e => {
    if (!e.target.closest('[data-clear-measure]')) return;
    timeline.measure = null;
    timeline.render();
    showMeasure(null);
  });

  /* D1 승계표 · 세계표 · 가문 창의 단추 (아래의 공용 단추 처리보다 먼저 — 칩의 ✏️는 칩 링크보다 먼저) */
  detailEl.addEventListener('click', e => {
    const t = e.target;
    const hit = sel => t.closest(sel);
    let b = null;
    const stop = () => e.stopImmediatePropagation();
    if ((b = hit('[data-kin-edit]'))) return stop(), kinEditChip(b);
    if ((b = hit('[data-kin-succ]')) && state.selected) {
      stop();
      const x = state.model.byUid.get(state.selected);
      const i = b.dataset.kinSucc;
      return x && openDetail(x.uid, i === '' ? { cell: 'succession' } : { cell: 'succession', focus: Number(i), expand: true });
    }
    if ((b = hit('[data-kin-back]'))) return stop(), openDetail(b.dataset.kinBack, { cell: 'succession' });
    if ((b = hit('[data-kin-fam]'))) return stop(), openFamilyAt(b.dataset.kinFam);
    if ((b = hit('[data-kin-fam-house]'))) {
      stop();
      const h = state.model.houseMap && state.model.houseMap.get(b.dataset.kinFamHouse);
      return h && openFamily(h);
    }
    if ((b = hit('[data-kin-succ-person]'))) {
      stop();
      const w = kinWhere(b.dataset.kinSuccPerson);
      const up = w ? kinLeaderAbove(w) : null;
      return up && openDetail(up.polity.uid, { cell: 'succession', focusPerson: w });
    }
    if ((b = hit('[data-kin-level]')) && state.kinSucc) {
      stop();
      state.kinSucc.setLevel(b.dataset.kinLevel);
      const sel = detailEl.querySelector('[data-kin-levels]');
      if (sel) sel.value = b.dataset.kinLevel;
      return;
    }
    if ((b = hit('[data-kin-era]'))) {
      stop();
      const [a, z] = b.dataset.kinEra.split('|').map(Number);
      const pad = Math.max(z - a, 8) * 0.12;
      return timeline.setView(a - pad, z + pad, { animate: true, inset: true }); // 그 나라 기간이 가려지지 않은 쪽에 담기게
    }
  });
  detailEl.addEventListener('change', e => {
    const sel = e.target.closest('[data-kin-levels]');
    if (sel && state.kinSucc) state.kinSucc.setLevel(sel.value);
  });
  detailEl.addEventListener('click', e => {
    if (viewsUi && viewsUi.onDetailClick(e)) return; // 시대 구분 상세의 '이 시대의 나라' 카드 (집합 보기 결정 5)
    const copy = e.target.closest('[data-copy-own]');
    if (copy && maker) return maker.duplicateSelection([copy.dataset.copyOwn]);
    const un = e.target.closest('[data-unlock]');
    if (un && maker) {
      const uid = state.selected;
      maker.unlock(un.dataset.unlock);
      if (uid) openEditorFor(uid); // 풀었으면 곧 고치기
      return;
    }
    const scopeSw = e.target.closest('[data-scope-toggle]');
    if (scopeSw) return timeline.toggleScope(scopeSw.dataset.scopeToggle); // 대범위 모아 보기 (상세는 onScope가 새 상태로 다시 그림)
    const lensBtn = e.target.closest('[data-lens]');
    if (lensBtn) {
      state.detailLens = lensBtn.dataset.lens;
      return openDetail(state.selected);
    }
    const docBtn = e.target.closest('[data-doc]');
    if (docBtn) return openWiki(docBtn.dataset.doc);
    const nav = e.target.closest('[data-cell-nav]');
    if (nav && state.selected) return openDetail(state.selected, { cell: nav.dataset.cellNav });
    const cellOf = e.target.closest('[data-cell-of]'); // 다른 항목의 칸 (인물 상세의 같은 이름의 지도자 · 같은 시기의 지도자)
    if (cellOf) return openDetail(cellOf.dataset.cellOf, { cell: cellOf.dataset.cell });
    const yearBtn = e.target.closest('[data-year]');
    if (yearBtn) return goToDate(Number(yearBtn.dataset.year), yearBtn.dataset.prec || 'y', { yearMax: 300 });
    const uidBtn = e.target.closest('[data-uid]');
    if (uidBtn) return openDetail(uidBtn.dataset.uid);
    const btn = e.target.closest('[data-act]');
    if (!btn) return;
    const act = btn.dataset.act;
    if (act === 'close-year') return closeYearPanel();
    if (act === 'year-here' && state.yearPanel) {
      const yp = state.yearPanel;
      return goToDate(yp.t, yp.prec, { end: yp.end, yearMax: 120 });
    }
    const x = state.model.byUid.get(state.selected);
    if (act === 'close' || !x) return closeDetail();
    if (act === 'cell-focus') {
      // 칸의 기간이 화면에 넉넉히 들어오게 (앞뒤 35% 여유, 8년보다 좁게는 가지 않음)
      const ref = parseCellRef(x, state.cell);
      if (!ref) return;
      const { lo: s, hi: e2 } = cellSpanOf(x, ref.c, state.cell);
      const len = Math.max(e2 - s, 8 / 1.7);
      const pad = len * 0.35;
      return timeline.setView(s - pad, e2 + pad, { animate: true, inset: true }); // 상세 창이 가리지 않은 부분에 담기게
    }
    if (act === 'focus') timeline.focusOn(x);
    if (act === 'group-tree') return openGroupTree(x);
    if (act === 'metro') timeline.showMetro(x.uid, $('#timeline').querySelector(`.tl-row[data-uid="${CSS.escape(x.uid)}"]`), true);
    if (act === 'wiki') openWiki(x.uid);
    if (act === 'edit') openEditorFor(x.uid);
    if (act === 'revert') revertItem(x);
    if (act === 'delete') deleteItem(x);
  });

  /* ---------- 고치기 (메이커에서만 — 보기 전용에서는 모두 거절) ----------
     저장은 덧씌움 없이 고치는 DLC(작업본)를 바로 고칩니다: 제 항목은 그 자리에서, 남의 항목(다른 DLC · 기본팩)은 바뀐 칸만 패치로, 지우는 대신 숨김 패치로 (js/maker.js → HT.draft) */
  /** 남의 항목에 건 패치를 걷어 원래대로 */
  function revertItem(x) {
    if (!maker) return denyEdit();
    if (!maker.revertItem(x)) return false;
    refresh();
    syncEditor(null, { only: x.uid }); // 편집 창이 그 항목을 열고 있으면 걷어 낸 패치 값을 들고 있지 않게
    HT.toast('원래 내용으로 되돌렸습니다.');
    return true;
  }
  /** 제 항목은 삭제, 남의 항목은 숨김 */
  function deleteItem(x) {
    if (!maker) return denyEdit();
    if (!maker.ready()) return false;
    if (maker.isLocked(x)) {
      HT.toast(`잠긴 팩 «${x.packName}»의 항목입니다 — 불러온 팩 탭에서 자물쇠를 풀면 숨길 수 있습니다.`);
      return false;
    }
    const word = HT.itemWord(x);
    const name = x.title || x.name;
    if (maker.isOwn(x)) {
      if (!confirm(`"${name}" ${word}을(를) 삭제할까요?`)) return false;
    } else if (!confirm(`"${name}" ${word}을(를) 숨길까요?\n메이커 줄의 [고친 것]에서 다시 되돌릴 수 있습니다.`)) return false;
    if (!maker.removeItem(x)) return false;
    if (state.editing === x.uid) closeEditor(); // 지운 항목을 편집 창이 들고 있지 않게
    closeDetail();
    refresh();
    return true;
  }

  /* ---------- 사건 추가/수정: 메이커의 편집 창 ----------
     편집기는 가운데를 막는 대화상자가 아니라 오른쪽에 붙은 편집 창(dlc-maker.html의 #editPane — 틀 · 폭 · 떼어 내기는 js/maker.js)에 열립니다.
     연표를 보며 고치고, 저장하면 연표에 바로 반영되며 창은 그 항목을 계속 엽니다. 다른 항목을 누르면 그 항목으로 바뀌되, 저장하지 않은 고침이 있으면 먼저 묻습니다 */
  const editorForm = $('#editorForm'); // 편집 창은 dlc-maker.html에만 있습니다
  let editSeq = 0; // 편집 창을 (다른 항목으로) 채운 차례 — 큰 입력 창의 문맥
  let formWiki = null; // 편집 창 문서 칸의 나무위키 편집기

  /** 편집 창의 지금 값 — 저장하지 않은 고침이 있는지 견줄 때 (채운 직후의 값 state.editSnap과) */
  const editorValue = () => {
    try {
      return JSON.stringify(HT.FORMS[state.editingKind].read(editorForm).item);
    } catch (e) {
      return '';
    }
  };
  const editorDirty = () => !!maker && maker.pane.isOpen() && editorValue() !== state.editSnap;
  /** 편집 창을 닫습니다 (묻지 않음) */
  function closeEditor() {
    if (!maker) return;
    const was = state.editing;
    state.editing = state.editingItem = null;
    maker.pane.hide();
    if (!state.selected) maker.selectItems([]);
    if (was && !state.selected) {
      timeline.setSelected(null);
      timeline.setAnchor(null);
    }
  }
  /** 편집 창을 닫아도 되는지 묻고 닫습니다 — 저장하지 않은 고침이 있으면 '저장하고 … / 버리고 … / 취소'. verb = 단추의 뒷말(닫기 · 바꾸기).
      돌려주는 값(Promise): 닫았으면(이미 닫혀 있었으면) true */
  async function leaveEditor(verb = '닫기') {
    if (!maker || !maker.pane.isOpen()) return true;
    if (editorDirty()) {
      const a = await maker.ask('편집 창에 저장하지 않은 고침이 있습니다.', { title: '편집 창', yes: `저장하고 ${verb}`, no: `버리고 ${verb}` });
      if (a === 'cancel' || (a === 'yes' && !saveEditor())) return false;
    }
    closeEditor();
    return true;
  }

  /** 사건·시대·기관·문화·왕조(· 시대 구분 — HT.FORMS의 종류마다) 공용 편집기. item이 없으면 새로 만듭니다.
      이미 다른 항목을 고치던 중이고 저장하지 않은 고침이 있으면 먼저 묻습니다 ('저장하고 이동 / 버리고 이동 / 취소') */
  function openEditor(item, kind = item ? HT.itemKindOf(item) : 'event', preset = {}) {
    if (!maker || !editorForm) return denyEdit();
    if (!maker.ready()) return false; // 고칠 DLC를 아직 고르지 않았으면 고르는 창부터
    if (maker.pane.isOpen() && item && state.editing === item.uid) {
      maker.pane.show(); // 고치던 그 항목 — 채운 값(고치던 글)은 그대로
      return true;
    }
    if (editorDirty()) {
      return maker.ask('편집 창에 저장하지 않은 고침이 있습니다.', { title: '다른 항목으로', yes: '저장하고 이동', no: '버리고 이동' }).then(a => {
        if (a === 'cancel' || (a === 'yes' && !saveEditor())) return false;
        return fillEditor(item && item.uid ? state.model.byUid.get(item.uid) || item : item, kind, preset); // 저장하는 동안 모델이 새로 지어졌으니 새 모습으로
      });
    }
    return fillEditor(item, kind, preset);
  }
  /** 편집 창의 칸을 다시 그릴 때 초점을 잃지 않게: 초점이 있던 칸의 자리(이름 · 같은 이름 가운데 몇 번째 — 줄 입력 · 선택 범위)를 적어 두었다가 새로 그린 같은 칸에 돌려줍니다.
      (돌려주지 않으면 초점이 body로 떨어져, 이어 친 글자가 연표의 단축키로 실행됩니다) */
  const FOCUSABLE = 'input, select, textarea, button, [tabindex]';
  const sameSpot = (box, name, tag) => [...box.querySelectorAll(name ? `${tag}[name="${CSS.escape(name)}"]` : FOCUSABLE)];
  function focusSpot(box) {
    const a = document.activeElement;
    if (!a || a === box || !box.contains(a)) return null;
    let sel = null;
    try {
      if (typeof a.selectionStart === 'number') sel = [a.selectionStart, a.selectionEnd, a.selectionDirection];
    } catch (e) {
      sel = null;
    }
    return { name: a.name || '', tag: a.tagName, i: sameSpot(box, a.name, a.tagName).indexOf(a), sel };
  }
  function restoreFocus(box, spot) {
    const list = sameSpot(box, spot.name, spot.tag);
    const el = spot.i >= 0 ? list[Math.min(spot.i, list.length - 1)] : null;
    if (!el || el.tagName !== spot.tag) return;
    el.focus({ preventScroll: true });
    if (spot.sel)
      try {
        el.setSelectionRange(...spot.sel);
      } catch (e) {
        /* 선택 범위가 없는 칸 (숫자 · 고르기) */
      }
  }
  /** 칸의 이설 상자를 펼쳐 둔 줄의 정체 — 줄 묶음(data-* 이름 · 값과 같은 묶음 가운데 몇 번째) + 그 줄의 이름 · 시작 값(큰 입력 창의 rowSig처럼) + 같은 정체가 또 있으면 몇 번째.
      저장하면 줄이 시작 순으로 다시 놓이므로(HT.sortCells) 순번으로는 엉뚱한 줄의 상자가 열립니다. pick(상자)이 참인 상자의 정체를 Set으로, each(상자, 정체)를 주면 상자마다 부름 */
  const CALT_SIG_KEYS = '.c-name, .c-temple, .c-title, .c-start, .s-from, .v-track, .v-office';
  function caltSigs(pick, each = null) {
    const out = new Set();
    const seen = new Map();
    const boxes = [];
    for (const b of editorForm.querySelectorAll('.cell-alts')) {
      const row = b.parentElement;
      const box = row && row.parentElement;
      if (!box) continue;
      const tag = [...box.attributes].filter(a => a.name.startsWith('data-')).map(a => `${a.name}=${a.value}`).join('&');
      if (!boxes.includes(box)) boxes.push(box);
      const bi = boxes.filter(x => [...x.attributes].filter(a => a.name.startsWith('data-')).map(a => `${a.name}=${a.value}`).join('&') === tag).indexOf(box);
      const vals = [...row.querySelectorAll(CALT_SIG_KEYS)].filter(el => !b.contains(el) && el.closest('.cell-row, .succ-row') === row).map(el => el.value.trim());
      const base = `${tag}#${bi}|${vals.join('\u241f')}`;
      const n = seen.get(base) || 0;
      seen.set(base, n + 1);
      const sig = `${base}|${n}`;
      if (each) each(b, sig);
      else if (pick(b)) out.add(sig);
    }
    return out;
  }
  /** 편집 창에 폼을 채워 엽니다 (묻지 않음). refill = 저장한 뒤 같은 항목을 다시 채움 — 보던 자리(스크롤) · 펼친 묶음 · 초점(치던 칸과 커서 자리)을 그대로 둡니다.
      values = 항목 대신 이 값으로 폼을 채움(syncEditor — 손댄 칸을 살려 둘 때) · quiet = 편집 창의 틀 · 상세 · 연표의 고름은 건드리지 않고 폼만 다시 채움 */
  function fillEditor(item, kind, preset = {}, { refill = false, values = null, quiet = false } = {}) {
    const m = state.model;
    const body = editorForm.querySelector('.ep-body');
    const keep = refill ? { top: body.scrollTop, open: [...editorForm.querySelectorAll('details[data-adv]')].filter(d => d.open).map(d => d.dataset.adv), alts: caltSigs(b => !b.hidden && b.dataset.closing !== '1'), focus: focusSpot($('#editorFields')) } : null; // alts: 펼쳐 두던 칸의 이설 상자(줄의 정체로 — 저장하면 줄이 시작 순으로 다시 놓이므로 순번이 아니라)
    if (!m.tracks.length) return HT.toast('트랙이 없습니다. DLC 관리에서 DLC를 켜 주세요.', 'error');
    const F = HT.FORMS[kind];
    if (!F) throw new Error(`"${kind}" 항목을 고치는 폼이 없습니다.`); // 모르는 종류가 조용히 사건 폼으로 떨어지지 않게
    const word = F.word;
    const polityNames = m.periods.filter(p => p.polityKind !== 'overlay' && p.polityKind !== 'dynasty').map(p => p.name);
    const dynastyNames = m.periods.filter(p => p.polityKind === 'dynasty').map(p => p.name);
    const houseNames = (m.houses || []).map(h => h.name); // 국성 · 가문 칸의 자동 완성 — 가문 목록의 가문과 이름으로만 적혀 저절로 생긴 가문
    /* 사건 폼의 조약 규격: 끝낸 전쟁(사건 모두) · 대체한 조약(조약인 사건)의 자동 완성 — 고치는 사건 자신은 빼고 */
    const otherEvents = m.events.filter(e => !item || e.uid !== item.uid);
    const eventTitles = otherEvents.map(e => e.title);
    const treatyTitles = otherEvents.filter(e => e.treaty).map(e => e.title);
    /* 대범위 폼: '시대 구분에서 가져오기'의 시대 구분 목록(연표의 모든 시대 구분 — 색은 적어 둔 것만: 자동 배정 색이 가져오기로 자료에 굳지 않게, 비워 두면 어차피 물려받음) ·
       구성 정권 · 상징적 본국의 자동 완성(정권 띠만 — 대범위가 찾는 것과 같게, 고른 트랙의 것은 이름 · 다른 트랙은 "트랙:이름") */
    const scopeArgs = kind !== 'scope' ? {} : {
      epochs: (m.epochs || []).map(e => {
        const raw = maker.rawOf(e) || ((packById(e.packId) || {}).epochs || []).find(q => q.id === e.id);
        return Object.assign({}, e, { color: raw && HT.isColor(raw.color) ? raw.color : '' });
      }),
      polities: m.periods.filter(p => p.itemKind === 'period').map(p => ({ name: p.name, track: p.track, trackName: trackOf(p.track).name })),
    };
    /* 사람 · 지명 칸의 자동 완성 (형식 버전 3 — 지도자 줄의 사람 상자 · 인물의 부모 · 배우자 · 사건의 장소): 인물 이름 · 지명 사전과 쓰인 지명 */
    const lineageArgs = { figureNames: (m.figures || []).map(f => f.name), placeNames: (m.places || []).map(p => p.name), figures: (m.figures || []).map(f => ({ name: f.name, birth: f.birth, death: f.death, house: f.houseName || f.house || '' })) }; // 사람 고르기 목록의 생몰 · 가문(5단계 과제 5)
    $('#editorFields').innerHTML = F.html({ tracks: m.tracks, spheres: m.spheres || [], categories: m.categories.filter(c => c.id !== 'etc'), polityNames, dynastyNames, peopleNames: m.peoples.map(p => p.name), houseNames, ...lineageArgs, ...scopeArgs, eventTitles, treatyTitles }); // spheres: 시대 구분 폼의 문화권 고르기(켠 DLC들의 사전 — 5단계 과제 6)
    /* 큰 입력 창(js/fieldpop.js)의 문맥: 다른 항목을 채우면 바뀌고, 저장한 뒤 같은 항목을 다시 채울 때는 그대로 — 그래야 창이 다시 그려진 같은 칸에만 다시 묶이고,
       다른 항목으로 바뀌면 "원래 칸이 닫혔습니다"가 됩니다 (엉뚱한 칸을 덮어쓰지 않게) */
    if (!refill) editorForm.dataset.fpCtx = String(++editSeq);
    state.editing = item ? item.uid : null;
    state.editingItem = item || null; // 검사에서 떨어져 연표에 없는 제 항목도 저장할 수 있게 (저장할 때 모델에서 못 찾으면 이것으로)
    state.editingKind = kind;
    $('#editorTitle').textContent = item ? `${word} 수정` : `${word} 추가`;
    const wholeBtn = editorForm.querySelector('[data-pane="paste-all"]'); // 통째 붙여넣기(js/maker-paste.js) — 시대 폼에만
    if (wholeBtn) wholeBtn.hidden = kind !== 'period';
    const kp = item && item.uid && m.byUid.has(item.uid) ? kinPlan(item.uid) : {}; // 계보 단추 — 승계표 · 세계표(저장된 것으로 — js/kin-view.js)
    const kinBtn = editorForm.querySelector('[data-pane="kin"]');
    if (kinBtn) kinBtn.hidden = !(kp.succ || kp.fam);
    const note = $('#editorNote');
    const missing = !!item && maker.isOwn(item) && !m.byUid.has(item.uid);
    note.hidden = !(item && (!maker.isOwn(item) || missing));
    note.classList.toggle('is-warn', missing);
    if (missing) note.textContent = `검사를 통과하지 못해 연표에 보이지 않는 ${word}입니다 — 고쳐서 저장하면 나타납니다. (무엇이 문제인지는 메이커 줄의 [검사]에)`;
    else if (!note.hidden) note.textContent = `"${item.packName}"에 들어 있는 ${word}입니다. 원본은 그대로 두고, 바뀐 칸만 «${maker.draftName()}»의 패치로 담깁니다 — 원래 값으로 되돌려 저장하면 패치는 사라집니다.`;
    /* 폼에 채울 값: 제 항목은 파일 그대로의 값(+ 지금의 문서 본문)으로, 남의 항목은 지금 보이는 모습(패치가 얹힌 모델의 항목)으로 — 짐작으로 배정된 색은 "따로 지정"을 끈 채로.
       모델의 화면용 값이 저장할 때 자료로 굳지 않게 */
    const rawOwn = item ? maker.rawOf(item) : null;
    if (rawOwn) item = Object.assign({}, rawOwn, { uid: item.uid, packName: item.packName, wiki: docText(item.uid) });
    else if (item && item.colorAuto) item = Object.assign({}, item, { color: undefined });
    const firstTrack = m.tracks.find(t => state.ui.tracks[t.id] !== false) || m.tracks[0];
    // 새 항목의 시작: 우클릭한 자리(preset) 또는 화면 가운데 — 2년보다 좁게 확대했으면 그날, 아니면 그 해
    const p0 = preset.start != null ? preset : presetAt((timeline.view.start + timeline.view.end) / 2);
    editorForm._wikiLink = resolveWikiLink;
    editorForm._wikiImage = name => HT.docImageOf(state.model, maker && maker.draft ? maker.draft.id : '', name); // 폼 문서 칸의 미리 보기 — 저장하면 고치는 DLC에 적히므로 그 그림 사전에서
    const fresh = item ? null : F.fresh({ track: firstTrack.id, start: p0.start, startAt: p0.startAt }); // 종류마다 다른 기본 기간은 HT.FORMS의 표에
    if (item && kind === 'organ' && !item.host) item = Object.assign({}, item, { host: item.partOf });
    if (item && kind === 'dynasty' && !item.polities) item = Object.assign({}, item, { polities: item.partOf });
    const personNode = item && kind === 'figure' && item.uid ? HT.personOf(m, item) : null; // 사람 폼의 칭호 묶음(읽기 전용 — 5단계 과제 5)
    F.fill(editorForm, values || item || fresh, { defaultColor: trackOf(values ? values.track : item ? item.track : firstTrack.id).color, titles: personNode ? HT.personTitles(m, personNode) : [] });
    if (formWiki) formWiki.destroy(); // 앞 폼의 문서 칸 편집기를 뗍니다 — 채울 때마다 자동 완성 상자가 body에 쌓이지 않게
    formWiki = HT.namu.attach(editorForm, { names: wikiNames });
    if (HT.fieldPop) HT.fieldPop.attach(editorForm); // 긴 글 칸의 이름표 줄에 [크게] (큰 입력 창)
    $('#editorProblems').hidden = true;
    /* 상세와 같은 자리 — 편집 중에는 상세 대신 편집 창. 고치는 항목은 연표에서 고른 채로 (제 줄이 있는 것은 그 줄을 제자리에) */
    if (!quiet) {
      closeDetail();
      maker.pane.show();
      const drawn = state.editing && m.byUid.get(state.editing);
      const shown = drawn && drawn.kind !== 'group' && drawn.kind !== 'institution' ? drawn : null; // 단체 · 제도는 연표에 그림이 없어 고르지 않음 (가문 창과 같게 — 연표 전체가 흐려지지 않게)
      timeline.setSelected(shown ? shown.uid : null);
      if (shown && shown.kind !== 'epoch' && shown.kind !== 'scope') timeline.setAnchor(shown.uid, { reveal: true }); // 시대 구분 · 대범위는 제 줄이 없어 세로 닻 없음 (상세와 같게)
      else timeline.setAnchor(null);
    }
    syncEditorScope();
    if (keep) for (const d of editorForm.querySelectorAll('details[data-adv]')) if (keep.open.includes(d.dataset.adv)) d.open = true;
    if (keep) caltSigs(() => true, (b, sig) => keep.alts.has(sig) && HT.toggleCellAlts(b.parentElement, true, { instant: true })); // 저장한 뒤에도 펼쳐 두던 칸의 이설 상자는 그 줄에 그대로 (움직임 없이 — 못 찾은 줄은 닫아 둠)
    body.scrollTop = keep ? keep.top : 0;
    state.editSnap = editorValue();
    const nameEl = editorForm.elements[F.nameKey];
    if (nameEl && !keep) nameEl.focus({ preventScroll: true });
    else if (keep && keep.focus) restoreFocus($('#editorFields'), keep.focus);
    return true;
  }
  /** 편집 창 맨 위의 대범위 모아 보기 스위치 — 고치는 것이 연표에 있는 대범위일 때만(새 대범위는 저장한 뒤에). 편집 창이 붙어 있으면 대범위를 눌러도 상세 대신 편집 창이라
      상세의 스위치에 닿지 않으므로 여기에도 둡니다. 채울 때마다와 켜고 끈 뒤(syncScopeUi) 새 상태로 */
  function syncEditorScope() {
    if (!editorForm) return;
    let bar = $('#editorScopeBar');
    const kind = state.editingKind;
    const x = maker && maker.pane.isOpen() && (kind === 'scope' || kind === 'epoch') && state.editing ? state.model.byUid.get(state.editing) : null; // 시대 구분은 '이 시대의 나라' 카드(집합 보기 결정 5 — 메이커에서는 시대 구분을 누르면 편집 창이라 여기에)
    const html = !x ? '' : kind === 'scope' ? scopeSwitchHTML(x) : viewsUi ? viewsUi.epochCardHTML(x) : '';
    if (!bar) {
      if (!html) return;
      bar = document.createElement('div');
      bar.id = 'editorScopeBar';
      bar.className = 'scope-rows ep-scope-bar';
      $('#editorNote').after(bar);
    }
    bar.hidden = !html;
    bar.innerHTML = html;
  }
  /** 작업본이 편집 창 밖에서 바뀐 뒤 — 바탕 자료에서 id · 이름을 바꿈 · 상세나 [고친 것]의 되돌리기 · 문서 창의 저장 · 다른 메이커 탭의 고침 —
      열린 편집 창을 맞춥니다. 그러지 않으면 폼이 옛 값(옛 트랙 id · 옛 민족 이름 · 걷어 낸 패치 값 · 옛 문서)을 들고 있다가 다음 저장 때 그 값을 다시 씁니다.
      고침이 없으면 같은 항목을 저장된 값으로 다시 채우고, 고침이 있으면 손댄 칸은 그대로 두고(fix로 참조만 따라 고침) 손대지 않은 칸만 새 값으로 채웁니다 (고침은 고침대로 남음).
      fix(값, 목록 이름) = 폼의 값에도 작업본과 같은 참조 바꾸기를 합니다 · only = 그 항목(uid)을 열고 있을 때만 */
  function syncEditor(fix = null, { only = null } = {}) {
    if (!maker || !editorForm || !maker.pane.isOpen() || !state.editingKind) return false;
    if (only && state.editing !== only) return false;
    const kind = state.editingKind;
    const F = HT.FORMS[kind];
    const json = v => JSON.stringify(v);
    let was, cur;
    try {
      was = JSON.parse(state.editSnap); // 채운 직후(= 저장된)의 값
      cur = JSON.parse(editorValue()); // 지금 폼의 값
    } catch (e) {
      return false;
    }
    if (fix) {
      fix(was, F.list);
      fix(cur, F.list);
    }
    const uid = state.editing;
    const x = uid ? state.model.byUid.get(uid) || (maker.hasOwn(uid) ? maker.pseudo(uid) : null) : null;
    if (uid && !x) return false; // 고치던 항목이 사라졌으면 그대로 (저장할 때 알립니다)
    let snap = json(was); // 새 항목(아직 저장 전): 채운 직후의 값(참조만 따라 고친 것)이 그대로 기준
    if (x) {
      fillEditor(x, kind, {}, { refill: true, quiet: true }); // 저장된 새 값으로 (트랙 고르기의 목록도 새 트랙으로)
      snap = state.editSnap;
      if (json(cur) === json(was)) return true; // 고침이 없었으면 여기까지
    }
    const now = JSON.parse(snap);
    const out = {};
    for (const k of new Set([...Object.keys(now), ...Object.keys(cur), ...Object.keys(was)])) {
      const v = json(cur[k]) === json(was[k]) ? now[k] : cur[k]; // 손대지 않은 칸은 새 값, 손댄 칸은 그대로
      if (v !== undefined) out[k] = v;
    }
    fillEditor(x, kind, {}, { refill: true, quiet: true, values: out });
    /* 견본 색 칸은 채울 때마다 색을 파스텔로 한 번 더 맞춥니다(HT.setSwatch) — 손대지 않은 색이 이렇게 다시 채우는 사이 옅어지지 않게 저장된 값 그대로 돌려놓습니다 */
    for (const box of editorForm.querySelectorAll('[data-swatches]')) {
      const k = box.dataset.swatches;
      if (json(cur[k]) !== json(was[k]) || !HT.isColor(now[k])) continue;
      box.querySelector('input').value = now[k];
      box.querySelectorAll('.sw').forEach(b => {
        const on = b.dataset.sw === now[k];
        b.classList.toggle('is-on', on);
        b.setAttribute('aria-checked', String(on));
      });
    }
    state.editSnap = snap; // 기준은 저장된 값 — 손댄 칸이 있으면 여전히 "저장하지 않은 고침"
    return true;
  }
  /** 열린 편집 창을 값(values — 그 종류 폼의 read가 내는 꼴)으로 다시 채웁니다. 기준(state.editSnap)은 그대로 두어, 손으로 고친 것과 같은 '저장하지 않은 고침'이 됩니다
      (통째 붙여넣기 — js/maker-paste.js의 openWhole). 펼쳐 둔 묶음 · 스크롤은 그대로 */
  function refillEditor(values) {
    if (!maker || !editorForm || !maker.pane.isOpen() || !state.editingKind || !values) return false;
    const snap = state.editSnap;
    const uid = state.editing;
    const x = uid ? state.model.byUid.get(uid) || state.editingItem : null;
    fillEditor(x, state.editingKind, {}, { refill: true, quiet: true, values });
    state.editSnap = snap;
    return true;
  }
  /** 메이커의 편집 창에서 고칠 수 있는 항목인지 — openDetail(편집 창이 붙어 있을 때 편집 창으로 보낼지) · openEditorFor(상세로 돌려보낼지) · 우클릭 메뉴의 수정 · 삭제 줄이 모두 이것 하나로 가립니다.
      둘이 따로 판단하면 한쪽은 편집 창으로, 다른 쪽은 상세로 서로를 부르며 끝없이 돕니다. 시대 구분 · 대범위는 패치가 닿지 않아 고치는 DLC의 제 것만, 가문 창('house:id')처럼 모델 항목이 아닌 것은 아님 */
  function paneEditable(uid) {
    const x = maker && state.model ? state.model.byUid.get(uid) : null;
    return !!x && ((x.kind !== 'epoch' && x.kind !== 'scope') || maker.isOwn(x)) && !maker.isLocked(x); // 잠긴 팩의 항목은 읽기 전용 상세로 (설계 3-5)
  }
  function openEditorFor(uid) {
    if (!maker) return denyEdit();
    maker.selectItems([uid]);
    const x = state.model.byUid.get(uid);
    if (!x) return false;
    if (!paneEditable(uid)) return openDetail(uid); // 남의 시대 구분 · 남의 대범위는 고칠 수 없습니다 (패치가 닿지 않음) — 상세로 (openDetail은 같은 판단으로 붙은 편집 창을 먼저 닫고 엶 — 편집 창으로 되돌려 보내지 않음)
    return openEditor(x, HT.itemKindOf(x));
  }
  /** 편집 창의 저장 — 저장하면 연표에 바로 반영되고, 창은 그 항목을 계속 엽니다(파일 그대로의 값으로 다시 채움). 돌려주는 값: 저장한 항목의 uid (못 하면 null) */
  function saveEditor() {
    if (!maker || !editorForm) return denyEdit() && null;
    const kind = state.editingKind || 'event';
    const F = HT.FORMS[kind];
    const read = F.read(editorForm);
    const obj = read.item; // 비운 칸은 undefined — 제 항목에서는 그 칸을 지우고, 남의 항목의 패치에서는 null로 원래 값을 지웁니다 (HT.draft)
    const problems = read.problems;
    const box = $('#editorProblems');
    const editing = state.editing ? state.model.byUid.get(state.editing) || (maker.hasOwn(state.editing) ? state.editingItem : null) : null;
    if (state.editing && !editing) problems.push('고치던 항목이 연표에서 사라졌습니다 (DLC를 끄거나 지웠는지 확인하세요). 창을 닫고 다시 열어 주세요.');
    if (problems.length) {
      box.innerHTML = problems.map(p => `<li>${esc(p)}</li>`).join('');
      box.hidden = false;
      box.scrollIntoView({ block: 'nearest' });
      return null;
    }
    box.hidden = true;
    const isNew = !editing;
    const uid = maker.saveItem(kind, editing, obj); // 새 항목 → 작업본의 목록에 · 제 항목 → 그 자리에서 · 남의 항목 → 바뀐 칸만 패치로. 문서 본문은 documents로
    if (!uid) return null;
    // 방금 저장한 항목이 필터에 가려지지 않도록: 트랙은 늘, 그 밖에 풀 필터(분류 · 종류 칩 · 중요도)는 종류마다 HT.FORMS의 표에
    if (obj.track) delete state.ui.tracks[obj.track];
    for (const [group, v] of Object.entries(F.filterKeys(obj))) {
      if (group === 'importance') {
        if (v < state.ui.minImportance) {
          state.ui.minImportance = 1;
          $('#importanceSelect').value = '1';
        }
      } else if (state.ui[group] && v != null) delete state.ui[group][v];
    }
    refresh();
    const x = state.model.byUid.get(uid);
    fillEditor(x || maker.pseudo(uid) || editing, kind, {}, { refill: true }); // 창은 그 항목 그대로 — 저장된 값으로 다시 채워 고친 것이 없는 상태로
    maker.selectItems([uid]);
    if (x && isNew) timeline.focusOn(x);
    if (!x) HT.toast('저장했지만 검사를 통과하지 못해 연표에 나타나지 않습니다 — 메이커 줄의 [검사]를 보세요.', 'error');
    else HT.toast(isNew ? `${F.word}을(를) 추가했습니다.` : '저장했습니다.', 'ok');
    editorForm.dispatchEvent(new CustomEvent('ht:saved', { detail: { uid, kind, isNew, item: obj } })); // 저장한 뒤 할 일을 남겨 둔 부품에게(통째 붙여넣기의 '다른 나라에 넣을 것' — js/maker-paste.js)
    return uid;
  }

  if (editorForm) {
    HT.bindEventForm(editorForm);
    HT.bindPeriodForm(editorForm);
    HT.bindSwatches(editorForm);

    editorForm.addEventListener('submit', e => {
      e.preventDefault(); // 편집 창은 대화상자가 아니므로 폼이 페이지를 떠나지 않게 늘 막습니다
      if (e.submitter && e.submitter.value === 'save') saveEditor();
    });
    editorForm.addEventListener('click', e => {
      const pn = e.target.closest('[data-person-new]'); // 지도자 · 내각 칸의 ＋ 사람 — 이 칸의 이름으로 사람을 바로 만들어 잇기(5단계 과제 5)
      if (pn) {
        e.preventDefault();
        if (!maker || typeof maker.createPerson !== 'function') return HT.toast('사람 만들기는 메이커에서만 됩니다.');
        const row = pn.closest('.cell-row');
        const g = cls => ((row && row.querySelector(`.${cls}`)) || {}).value || '';
        const name = (g('c-name') || g('c-temple') || g('c-title') || g('c-given')).trim();
        if (!name) return HT.toast('먼저 이 칸의 이름(묘호 · 시호 · 이름 가운데 하나)을 적으세요.');
        const input = pn.closest('.calt-grid') && pn.closest('.calt-grid').querySelector('.x-person');
        const read = cls => { const d = HT.readDate(g(cls)); return d && Number.isFinite(d.t) ? d.t : undefined; };
        const el = editorForm.elements;
        Promise.resolve(maker.createPerson({ name, track: el.track ? el.track.value : undefined, start: read('c-start'), end: read('c-end') })).then(id => {
          if (!id || !input) return;
          delete input.dataset.ref;
          input.value = id;
          input.dispatchEvent(new Event('input', { bubbles: true }));
          HT.toast(`사람 «${name}»을(를) 만들어 이 칸에 이었습니다(id ${id}).`, 'ok');
        });
        return;
      }
      if (viewsUi && viewsUi.onDetailClick(e)) return; // 시대 구분 편집 창 맨 위의 '이 시대의 나라' 카드 (집합 보기)
      const sw = e.target.closest('[data-scope-toggle]');
      if (sw) timeline.toggleScope(sw.dataset.scopeToggle); // 편집 창 맨 위의 대범위 모아 보기 (스위치는 onScope → syncScopeUi가 새 상태로)
    });
    editorForm.addEventListener('keydown', e => {
      const ctrl = e.ctrlKey || e.metaKey;
      if (ctrl && !e.altKey && (e.key === 's' || e.key === 'S' || e.key === 'Enter')) {
        e.preventDefault(); // Ctrl+S · Ctrl+Enter = 저장
        saveEditor();
      } else if (e.key === 'Enter' && !ctrl && e.target.tagName === 'INPUT' && !/^(button|submit|checkbox|radio)$/.test(e.target.type)) e.preventDefault(); // 한 줄 칸의 Enter는 저장하지 않습니다 (실수로 저장되지 않게)
    });
  }

  /* 다른 스크립트·검사에서 쓸 수 있는 작은 공개 API. 편집 길(openEditor · deleteItem · revertItem · saveDoc)은 보기 전용 화면에서 false를 돌려주며 거절합니다 */
  HT.viewer = {
    app: MAKE ? 'make' : 'view',
    timeline,
    state,
    refresh,
    openDetail: (uid, opts) => openDetail(uid, opts), // 항목 uid · 'house:가문 id'
    closeDetail: () => closeDetail(),
    openWiki: key => openWiki(key),
    openEditor: (uid, kind) => (uid ? openEditorFor(uid) : openEditor(null, kind || 'event')),
    saveEditor: () => saveEditor(),
    closeEditor: () => leaveEditor(),
    deleteItem: uid => (state.model.byUid.has(uid) ? deleteItem(state.model.byUid.get(uid)) : false),
    revertItem: uid => (state.model.byUid.has(uid) ? revertItem(state.model.byUid.get(uid)) : false),
    saveDoc: (key, text) => saveDoc(key, text),
    get maker() {
      return maker;
    },
    get groupTree() {
      return groupTree; // 단체 계보 창 (js/group-tree.js — 검사 scripts/group-window-check.mjs가 씀)
    },
  };
  /* 독의 ＋: 추가할 수 있는 종류(HT.FORMS를 돎)의 작은 메뉴 */
  if ($('#addPeriodBtn'))
    $('#addPeriodBtn').addEventListener('click', e => {
      if (!menuEl.hidden) return hideMenu();
      const r = e.currentTarget.getBoundingClientRect();
      showMenu([{ title: '항목 추가' }].concat(addMenuItems(null)), r.left, r.bottom + 6);
    });

  /* ---------- 위키 문서 ----------
   * 문서 키(HT.docKey): 항목 uid · people:id · track:id · category:id · house:id(가문) · cell:uid:cabinets:이름@시작 · 그리고 "//하위 문서".
   * 모든 항목·칸에 문서를 만들 수 있고, 문서 안에 하위 문서(조선/역사, 조선/개요 …)를 얼마든지 둘 수 있습니다. */
  const wikiPane = $('#wikiPane');
  const wiki = { key: null, history: [], editing: false, editor: null };
  const docTitle = x => x.title || x.name;
  /** 문서 본문 — 모델의 문서 색인에서 (메이커에서는 고치는 DLC의 문서가 다른 DLC의 것보다 앞섭니다: 작업본이 맨 뒤의 팩이므로) */
  function docText(key) {
    const d = state.model && state.model.docs.get(key);
    return d ? d.text : '';
  }
  /** 모든 문서 키 (내용이 있는 것) */
  function allDocKeys() {
    const keys = [];
    for (const [k, d] of state.model.docs) if (d.text && d.text.trim()) keys.push(k);
    return keys;
  }
  function subdocsOf(key) {
    const pre = `${key}//`;
    // 중간 단계 문서가 비어 있어도(역사//전기만 있음) "역사"를 하위 문서로 보여 줍니다
    const subs = new Set(allDocKeys().filter(k => k.startsWith(pre)).map(k => k.slice(pre.length).split('//')[0]));
    return [...subs].map(sub => ({ key: pre + sub, sub })).sort((a, b) => a.sub.localeCompare(b.sub, 'ko'));
  }
  /** 바탕 키의 대상: { title, meta, obj, focus } — 없으면 null */
  function baseInfo(base) {
    const m = state.model;
    const p = HT.docKey.parse(base);
    if (p.type === 'people') {
      const pe = m.peopleMap.get(p.id);
      return pe && { title: pe.name, meta: '민족', obj: pe };
    }
    if (p.type === 'track') {
      const t = m.trackMap.get(p.id);
      return t && { title: t.name, meta: '트랙(나라·지역)', obj: t };
    }
    if (p.type === 'category') {
      const c = m.categoryMap.get(p.id);
      return c && { title: c.name, meta: '사건 분류', obj: c };
    }
    if (p.type === 'house') {
      const h = m.houseMap && m.houseMap.get(p.id);
      return h && { title: h.name, meta: `가문${h.surname ? ` · 성 ${surnameText(h)}` : ''}${h.seat ? ` · 본관 ${h.seat}` : ''}`, obj: h, focus: { uid: h.uid } }; // "연표에서" = 가문 창
    }
    if (p.type === 'surname') {
      const s = m.surnameMap && m.surnameMap.get(p.id); // 성씨 (형식 버전 3) — 제 창은 아직 없어 문서만
      return s && { title: s.name, meta: `성씨${s.houses.length ? ` · 가문 ${s.houses.length}` : ''}`, obj: s };
    }
    if (p.type === 'place') {
      const pl = m.placeMap && m.placeMap.get(p.id); // 지명 (형식 버전 3) — 제 창은 아직 없어 문서만
      return pl && { title: pl.name, meta: `지명${pl.uses.length ? ` · 쓰인 곳 ${pl.uses.length}` : ''}`, obj: pl };
    }
    if (p.type === 'cell') {
      const x = m.byUid.get(p.uid);
      // 칸 키는 "이름@시작 해"(날짜를 자세히 고쳐도 문서가 떨어지지 않게) — 키를 만드는 규칙 그대로 맞춰 봅니다
      const CK = HT.cellKind(p.cellKind); // 칸 종류 표의 줄 (이름표 · 제목)
      const c = x && HT.cellsOf(x, CK).find(c => HT.docKey.cell(x.uid, p.cellKind, c) === p.base);
      if (!c) return null;
      const label = CK.title(c, { leaderMode: state.ui.leaderLabel || 'auto' });
      return { title: label, meta: `${x.name} ${CK.name} · ${cellWhen(c, undefined, x)}`, obj: c, focus: { item: x, year: c.start, prec: precOf(c) }, parentKey: x.uid };
    }
    const x = m.byUid.get(p.uid);
    if (!x) return null;
    const where = x.track ? ` · ${trackOf(x.track).name}` : '';
    const word = x.kind === 'epoch' ? '시대 구분' : x.kind === 'event' ? '사건' : HT.itemKindOf(x) === 'period' ? HT.kindName(x.polityKind) : HT.itemWord(x);
    return { title: docTitle(x), meta: `${word} · ${HT.formatRange(x)}${where}`, obj: x, focus: { item: x } };
  }
  function docInfo(key) {
    const { base, sub } = HT.docKey.split(key);
    const b = baseInfo(base);
    if (!b) return null;
    if (!sub) return Object.assign({ key, base, sub: '', path: [] }, b);
    const parts = sub.split('//');
    return Object.assign({}, b, { key, base, sub, path: parts, title: `${b.title}/${parts.join('/')}`, meta: `${b.title}의 하위 문서` });
  }
  /** 이름 → 바탕 키 (시대·사건·기관·문화·시대 구분·민족·트랙·분류·지도자/내각/연호 칸) */
  function nameToBase(name) {
    const m = state.model;
    const n = String(name).trim().toLowerCase();
    if (!n) return null;
    /* 인물: "인물:이름"은 곧바로 인물로. 그냥 "이름"은 항목 → 칸을 먼저 찾고 인물은 맨 나중 — 같은 이름의 인물이 생겨도 이미 있던 링크의 목적지가 바뀌지 않게 */
    const figureNamed = s => (m.figures || []).find(f => f.name.toLowerCase() === s) || (m.figures || []).find(f => (f.aka || []).some(a => a.toLowerCase() === s)) || null;
    const fm = n.match(/^인물\s*:\s*(.+)$/);
    if (fm) {
      const f = figureNamed(fm[1].trim());
      return f ? f.uid : null;
    }
    const gm = n.match(/^단체\s*:\s*(.+)$/); // 단체 (형식 버전 3): "단체:이름"은 곧바로 단체로
    if (gm) {
      const g = (m.groups || []).find(q => q.name.toLowerCase() === gm[1].trim());
      return g ? g.uid : null;
    }
    const x = m.periods.find(p => p.name.toLowerCase() === n) || m.events.find(e => e.title.toLowerCase() === n) || m.epochs.find(e => e.name.toLowerCase() === n);
    if (x) return x.uid;
    const sc = (m.scopes || []).find(s => s.name.toLowerCase() === n); // 대범위
    if (sc) return sc.uid;
    const pe = m.peoples.find(p => p.name.toLowerCase() === n);
    if (pe) return `people:${pe.id}`;
    const t = m.tracks.find(t => t.name.toLowerCase() === n || t.id === n);
    if (t) return `track:${t.id}`;
    const c = m.categories.find(c => c.name.toLowerCase() === n);
    if (c) return `category:${c.id}`;
    for (const p of m.periods)
      for (const CK of HT.CELL_KINDS.filter(k => k.doc !== false)) // 문서를 다는 칸 종류 모두
        for (const cell of HT.cellsOf(p, CK)) if ([cell.name, cell.temple, cell.title, cell.given].some(v => v && v.toLowerCase() === n)) return HT.docKey.cell(p.uid, CK.list, cell);
    const f = figureNamed(n);
    if (f) return f.uid;
    const house = (m.houses || []).find(h => h.name.toLowerCase() === n); // 가문은 맨 끝 — 인물 다음 (같은 이름의 항목 · 칸 · 인물로 가던 옛 링크가 바뀌지 않게)
    if (house) return house.uid;
    const group = (m.groups || []).find(g => g.name.toLowerCase() === n); // 단체는 그 뒤 (새 기능 — 이미 있던 링크의 목적지가 바뀌지 않게)
    if (group) return group.uid;
    return null;
  }
  /** [[이름]] · [[이름/하위]] · [[/하위]] → 문서 키 */
  function linkToKey(name, ctxKey) {
    const raw = String(name).trim();
    if (raw.startsWith('/') && ctxKey) return `${ctxKey}//${raw.slice(1).split('/').filter(Boolean).join('//')}`;
    const whole = nameToBase(raw);
    if (whole) return whole;
    const parts = raw.split('/');
    for (let i = parts.length - 1; i >= 1; i--) {
      const base = nameToBase(parts.slice(0, i).join('/'));
      if (base) return `${base}//${parts.slice(i).filter(Boolean).join('//')}`;
    }
    return null;
  }
  const linkResolver = ctxKey => name => {
    const key = linkToKey(name, ctxKey);
    if (!key) return { missing: true };
    const info = docInfo(key);
    return { uid: key, title: info ? info.title : name, empty: !docText(key) };
  };
  const resolveWikiLink = linkResolver(null);
  /* 문서 그림 (형식 3 — 10건 D3 결정 9 B · js/wiki.js의 namu.figureHTML): [[파일:이름]]은 그 문서 글을 적은 팩의 그림 사전에서 찾습니다(HT.docImageOf).
     메이커에서 고치는 중인 글은 고치는 DLC(작업본)의 사전에서 — 저장하면 그 글이 작업본에 적히므로 미리 보기도 저장한 뒤와 같게 */
  const docPackOf = key => {
    if (maker && wiki.editing && wiki.key === key && maker.draft) return maker.draft.id;
    const d = state.model && state.model.docs.get(key);
    return d ? d.packId : '';
  };
  const imageResolver = key => name => HT.docImageOf(state.model, docPackOf(key), name);
  /* 그림 크게 보기 — 문서 창 · 메이커 미리 보기의 그림을 누르면 화면 전체에 띄웁니다(따스한 어두운 막 · Esc · 막이나 ✕를 누르면 닫힘 · 나타남 --t-in · 사라짐 --t-out) */
  let zoomEl = null;
  let zoomBack = null; // 닫으면 초점을 돌려줄 곳
  function closeZoom() {
    if (!zoomEl || zoomEl.hidden || zoomEl.classList.contains('is-out')) return;
    zoomEl.classList.add('is-out');
    HT.motion.later(HT.motion.T.out, () => {
      zoomEl.hidden = true;
      zoomEl.classList.remove('is-out');
      zoomEl.querySelector('img').removeAttribute('src');
      if (zoomBack && zoomBack.isConnected) zoomBack.focus();
    });
  }
  function openZoom(btn) {
    const fig = btn.closest('.wk-fig');
    const img = fig && fig.querySelector('img');
    if (!img) return;
    if (!zoomEl) {
      zoomEl = document.createElement('div');
      zoomEl.className = 'wk-zoom';
      zoomEl.hidden = true;
      zoomEl.setAttribute('role', 'dialog');
      zoomEl.setAttribute('aria-modal', 'true');
      zoomEl.setAttribute('aria-label', '그림 크게 보기');
      zoomEl.innerHTML = '<figure class="wk-zoom-fig"><img alt=""><figcaption></figcaption></figure><button type="button" class="icon-btn wk-zoom-close" aria-label="닫기">✕</button>';
      zoomEl.addEventListener('click', e => {
        if (!e.target.closest('.wk-zoom-fig img')) closeZoom();
      });
      window.addEventListener('keydown', e => {
        if (e.key !== 'Escape' || !zoomEl || zoomEl.hidden) return;
        e.preventDefault();
        e.stopPropagation(); // 문서 창 · 상세 창이 같은 Esc로 닫히지 않게
        closeZoom();
      }, true);
      document.body.appendChild(zoomEl);
    }
    const big = zoomEl.querySelector('img');
    big.src = img.src;
    big.alt = img.alt;
    const cap = fig.querySelector('figcaption');
    zoomEl.querySelector('figcaption').textContent = cap ? cap.textContent : '';
    zoomEl.querySelector('figcaption').hidden = !cap;
    zoomBack = btn;
    zoomEl.classList.remove('is-out');
    zoomEl.hidden = false;
    zoomEl.querySelector('.wk-zoom-close').focus();
  }
  /** 자동 완성용 이름 목록 */
  function wikiNames() {
    const m = state.model;
    const set = new Set();
    m.periods.forEach(p => set.add(p.name));
    m.events.forEach(e => set.add(e.title));
    m.epochs.forEach(e => set.add(e.name));
    (m.scopes || []).forEach(s => set.add(s.name));
    m.peoples.forEach(p => set.add(p.name));
    m.tracks.forEach(t => set.add(t.name));
    for (const k of allDocKeys()) if (k.includes('//')) {
      const info = docInfo(k);
      if (info) set.add(info.title);
    }
    if (wiki.key) subdocsOf(wiki.key).forEach(s => set.add(`/${s.sub}`));
    const docKinds = HT.CELL_KINDS.filter(k => k.doc !== false); // 칸 종류 표에서 문서를 다는 종류 모두 ([[이름]] 찾기와 같은 목록 — 시기처럼 표에 더한 종류도 저절로)
    m.periods.forEach(p => docKinds.forEach(K => HT.cellsOf(p, K).forEach(c => set.add(c.name))));
    (m.figures || []).forEach(f => set.add(set.has(f.name) ? `인물:${f.name}` : f.name)); // 인물 (항목 · 칸과 이름이 겹치면 "인물:이름"으로)
    (m.houses || []).forEach(h => set.add(h.name)); // 가문
    (m.groups || []).forEach(g => set.add(set.has(g.name) ? `단체:${g.name}` : g.name)); // 단체 (이름이 겹치면 "단체:이름"으로)
    return [...set].filter(Boolean);
  }
  function backlinks(key) {
    const out = [];
    for (const k of allDocKeys()) {
      if (k === key) continue;
      const hits = HT.namu.links(docText(k)).some(l => linkToKey(l, k) === key);
      if (!hits) continue;
      const info = docInfo(k);
      if (info) out.push({ key: k, title: info.title });
    }
    return out;
  }
  function openWiki(key, { push = true, edit = false } = {}) {
    const info = docInfo(key);
    if (!info) return HT.toast('문서를 찾을 수 없습니다.', 'error');
    if (wiki.editing && wiki.key !== key && !confirm('편집 중인 내용을 버릴까요?')) return;
    if (push && wiki.key && wiki.key !== key) wiki.history.push(wiki.key);
    wiki.key = key;
    wiki.editing = !!edit && !!maker && maker.ready(); // 문서 편집은 메이커에서만
    renderWiki();
    if (wikiPane.hidden) HT.platform.trapBack(closeWiki);
    wikiPane.hidden = false;
  }
  function closeWiki() {
    if (wiki.editing && $('#wikiText').value !== docText(wiki.key) && !confirm('편집 중인 내용을 버릴까요?')) return;
    if (!wikiPane.hidden) HT.platform.releaseBack();
    wikiPane.hidden = true;
    wiki.editing = false;
    wiki.history = [];
    wiki.key = null;
  }
  function renderWikiSubs(info) {
    const box = $('#wikiSubs');
    const crumbs = [];
    if (info.parentKey && !info.sub) crumbs.push({ key: info.parentKey, label: docInfo(info.parentKey) ? docInfo(info.parentKey).title : '' });
    if (info.sub) {
      const baseI = docInfo(info.base);
      crumbs.push({ key: info.base, label: baseI ? baseI.title : '' });
      info.path.slice(0, -1).forEach((seg, i) => crumbs.push({ key: `${info.base}//${info.path.slice(0, i + 1).join('//')}`, label: seg }));
    }
    const subs = subdocsOf(wiki.key);
    box.innerHTML = `${crumbs.length ? `<span class="wk-crumbs">${crumbs.map(c => `<button type="button" class="linky" data-wiki-link="${esc(c.key)}">${esc(c.label)}</button>`).join('<i>›</i>')}<i>›</i><b>${esc(info.path.length ? info.path[info.path.length - 1] : info.title)}</b></span>` : ''}
      <span class="wk-subs">${subs.map(s => `<button type="button" class="chip is-doc" data-wiki-link="${esc(s.key)}">${esc(s.sub)}</button>`).join('')}
      ${maker ? '<button type="button" class="chip is-add" data-wiki-act="new-sub" title="이 문서 아래에 하위 문서를 만듭니다 (예: 역사 · 개요 · 정치)">＋ 하위 문서</button>' : ''}</span>`;
    box.hidden = !maker && !crumbs.length && !subs.length; // 보기 전용: 보여 줄 길도 하위 문서도 없으면 줄을 두지 않습니다
  }
  function renderWiki() {
    const info = docInfo(wiki.key);
    if (!info) return closeWiki();
    const text = docText(wiki.key);
    const d = state.model.docs.get(wiki.key);
    $('#wikiTitle').textContent = info.title;
    $('#wikiMeta').textContent = `${info.meta}${d && d.user ? ' · 옮기지 못한 옛 내 문서' : d && d.packName ? ` · ${d.packName}의 문서${maker && maker.isDraftId(d.packId) ? ' (고치는 중인 DLC)' : ''}` : ''}`;
    $('#wikiBack').disabled = !wiki.history.length;
    $('#wikiGoto').hidden = !info.focus;
    renderWikiSubs(info);
    const editBtn = $('#wikiEdit'); // 편집 단추와 편집기는 dlc-maker.html에만 있습니다
    if (editBtn) {
      editBtn.hidden = wiki.editing;
      editBtn.textContent = text ? '✎ 편집' : '✎ 문서 만들기';
    }
    const body = $('#wikiBody');
    const editor = $('#wikiEditor');
    if (wiki.editing && editor) {
      body.hidden = true;
      editor.hidden = false;
      editor.dataset.fpCtx = wiki.key; // 큰 입력 창의 문맥 — 다른 문서를 열면 창이 이 칸에서 떨어집니다 (js/fieldpop.js)
      const ta = $('#wikiText');
      ta.value = text || (info.sub ? `== ${info.path[info.path.length - 1]} ==\n` : '');
      if (!wiki.editor) {
        const withImages = !!HT.makerImages; // 문서 그림 넣기(결정 8 A — 도구 줄 '그림' 단추 + 그림 띠): 메이커에만 있는 부품
        $('#wikiInsertBar').innerHTML = HT.namu.toolbarHTML({ image: withImages });
        wiki.editor = HT.namu.editor(ta, { toolbar: $('#wikiInsertBar'), names: wikiNames, onSave: wikiSave, onImage: () => wiki.images && wiki.images.pick() });
        if (withImages) wiki.images = HT.makerImages.mount({ maker, editor: wiki.editor, host: editor, esc, docKey: () => wiki.key });
      }
      $('#wikiPreview').innerHTML = HT.namu.render(ta.value, { link: linkResolver(wiki.key), image: imageResolver(wiki.key) }).html;
      if (wiki.images) wiki.images.sync(); // 그림 띠(메이커 — js/maker-images.js): 이 문서의 그림 · 팩 그림 합
      ta.focus();
      return;
    }
    if (editor) editor.hidden = true;
    body.hidden = false;
    const obj = info.obj || {};
    if (!text) {
      $('#wikiToc').innerHTML = '';
      $('#wikiArticle').innerHTML = `<div class="wk-empty"><p>아직 문서가 없습니다.</p>${maker ? '<button type="button" class="btn btn-primary" data-wiki-act="edit">✎ 문서 만들기</button>' : ''}</div>${obj.description ? `<div class="wk-desc"><h4>설명</h4><p>${esc(obj.description).replace(/\n/g, '<br>')}</p></div>` : ''}`;
      return;
    }
    const r = HT.namu.render(text, { link: linkResolver(wiki.key), image: imageResolver(wiki.key) });
    $('#wikiToc').innerHTML = r.toc.length
      ? `<b>목차</b><ol>${r.toc.map(h => `<li class="lv${h.lv}"><a href="#${h.id}" data-wiki-anchor="${h.id}"><span>${h.num}.</span> ${esc(h.text)}</a></li>`).join('')}</ol>`
      : '';
    const bl = backlinks(wiki.key);
    $('#wikiArticle').innerHTML = r.html + (bl.length ? `<div class="wk-backlinks"><b>이 문서를 가리키는 문서</b> ${bl.map(b => `<a class="wk-link" data-wiki-link="${esc(b.key)}">${esc(b.title)}</a>`).join(' · ')}</div>` : '');
  }
  /** 문서를 고치는 DLC(작업본)의 documents에 적습니다 — 다른 DLC의 글과 똑같으면(고치지 않았으면) 제 것을 두지 않고, 비우면 제 것을 지웁니다 */
  function saveDoc(key, text) {
    if (!maker) return denyEdit();
    if (!docInfo(key)) {
      HT.toast('문서를 찾을 수 없습니다.', 'error');
      return false;
    }
    if (!maker.setDoc(key, text)) return false;
    refresh();
    syncEditor(null, { only: key }); // 편집 창이 그 항목을 열고 있으면 폼의 문서 칸도 새 글로 (옛 글이 다음 저장 때 문서를 되돌리지 않게)
    return true;
  }
  function wikiSave() {
    const text = $('#wikiText').value;
    if (!saveDoc(wiki.key, text)) return;
    wiki.editing = false;
    renderWiki();
    HT.toast(text.trim() ? '문서를 저장했습니다.' : '이 DLC의 문서를 지웠습니다.', 'ok');
  }
  wikiPane.addEventListener('click', e => {
    const zoom = e.target.closest('[data-wiki-zoom]');
    if (zoom) {
      e.preventDefault();
      return openZoom(zoom);
    }
    const a = e.target.closest('[data-wiki-anchor]');
    if (a) {
      e.preventDefault();
      const el = wikiPane.querySelector(`#${CSS.escape(a.dataset.wikiAnchor)}`);
      if (el) el.scrollIntoView({ block: 'start', behavior: 'smooth' });
      return;
    }
    const fn = e.target.closest('[data-wiki-fn]');
    if (fn) {
      e.preventDefault();
      const el = wikiPane.querySelector(`#wk-fn-${CSS.escape(fn.dataset.wikiFn)}`);
      if (el) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      return;
    }
    const link = e.target.closest('[data-wiki-link]');
    if (link) {
      e.preventDefault();
      const key = link.dataset.wikiLink;
      if (docInfo(key)) return openWiki(key);
      const k2 = linkToKey(link.dataset.wikiName || key, wiki.key);
      if (k2 && docInfo(k2)) return openWiki(k2);
      // 연표(보기 전용)에서는 추가하라고 하지 않습니다 — 고치는 곳은 메이커뿐이고 연표는 메이커로 가지 않습니다(일방통행)
      return HT.toast(`"${link.dataset.wikiName || key}" 항목이 연표에 없습니다. ${maker ? '먼저 시대·사건 등으로 추가하세요.' : '그 항목이 든 DLC가 꺼져 있을 수 있습니다.'}`);
    }
    const b = e.target.closest('[data-wiki-act]');
    if (!b) return;
    const act = b.dataset.wikiAct;
    if (act === 'close') closeWiki();
    else if (act === 'back') {
      const prev = wiki.history.pop();
      if (prev) openWiki(prev, { push: false });
    } else if (act === 'goto') {
      const info = docInfo(wiki.key);
      if (!info || !info.focus) return;
      if (info.focus.uid) return openDetail(info.focus.uid); // 제 줄이 없는 것(가문): 그 창을 엽니다
      const x = info.focus.item;
      if (x.kind !== 'epoch' && x.kind !== 'scope') openDetail(x.uid);
      if (info.focus.year != null) goToDate(info.focus.year, info.focus.prec || 'y', { yearMax: 120 });
      else timeline.focusOn(x);
    } else if (act === 'edit') {
      if (!maker) return denyEdit();
      if (!maker.ready()) return;
      wiki.editing = true;
      renderWiki();
    } else if (act === 'new-sub') {
      if (!maker) return denyEdit();
      if (!maker.ready()) return;
      const name = (prompt('하위 문서 이름 (예: 역사, 개요, 정치, 문화)\n"/"로 이으면 더 깊이 만들 수 있습니다 (예: 역사/전기)') || '').trim().replace(/^\/+|\/+$/g, '');
      if (!name) return;
      openWiki(`${wiki.key}//${name.split('/').filter(Boolean).join('//')}`, { edit: true });
    } else if (act === 'save') wikiSave();
    else if (act === 'cancel') {
      wiki.editing = false;
      renderWiki();
    } else if (act === 'help') HT.namu.showHelp();
    else if (act === 'item-edit') {
      const info = docInfo(wiki.key);
      const x = info && info.focus && info.focus.item;
      if (x) openEditorFor(x.uid);
      else HT.toast('이 문서의 항목(민족 · 트랙 · 분류)은 메이커의 [바탕 자료]에서 고칩니다.');
    }
  });
  let wikiPreviewTimer = 0;
  if ($('#wikiText'))
    $('#wikiText').addEventListener('input', () => {
      clearTimeout(wikiPreviewTimer);
      wikiPreviewTimer = setTimeout(() => {
        $('#wikiPreview').innerHTML = HT.namu.render($('#wikiText').value, { link: linkResolver(wiki.key), image: imageResolver(wiki.key) }).html;
        if (wiki.images) wiki.images.sync();
      }, 200);
    });

  /* ---------- DLC 관리 ---------- */
  const dlcDialog = $('#dlcDialog');
  const dlcBody = $('#dlcBody');

  function openDlc() {
    renderDlc();
    if (!dlcDialog.open) dlcDialog.showModal();
  }

  const logHTML = () =>
    state.installLog
      .map(r => {
        const more = r.details.length > 8 ? `<li>…외 ${r.details.length - 8}건</li>` : '';
        const list = r.details.length ? `<ul>${r.details.slice(0, 8).map(d => `<li>${esc(d)}</li>`).join('')}${more}</ul>` : '';
        return `<div class="log-item ${r.ok ? 'ok' : 'fail'}"><b>${esc(r.file)}</b> — ${esc(r.text)}${list}</div>`;
      })
      .join('');

  /* DLC 관리 (docs/구상-메이커-팩.md 2-5): 표지 카드 모눈 + 고른 팩의 자세히. 거르기 · 찾기 · 고른 팩은 이 화면에서만 기억 */
  const dlcUi = { cat: 'all', q: '', sel: '' };
  const { isBase, catName, coverHTML, contentsText } = HT.packCard; // DLC 카드 부품은 두 화면 공용(js/packfile.js — 메이커의 처음 화면 · 팩 정보도)
  const catOf = p => (isBase(p) ? 'base' : p.category || '');
  /** 카드의 관계 줄: 문제가 있으면 ⚠ 줄(꺼진 필요한 팩은 [켜기]), 필요한 팩이 모두 켜져 있으면 ✓ 한 줄 */
  function relLineHTML(p) {
    const st = HT.packRelationState(p, state.packs, isEnabled);
    const warn = [];
    for (const n of st.needs) {
      if (n.state === 'off') warn.push(`⚠ 필요한 팩 «${esc(n.name)}»이(가) 꺼져 있습니다 <button type="button" class="btn btn-sm" data-enable="${esc(n.id)}">켜기</button>`);
      else if (n.state === 'missing') warn.push(`⚠ 필요한 팩 «${esc(n.name)}»이(가) 없습니다`);
    }
    for (const c of st.conflicts) warn.push(`⚠ «${esc(c.name)}»과(와) 함께 못 씁니다`);
    for (const g of st.ignored) warn.push(`⚠ «${esc(g.name)}»과(와) 불러오는 차례가 맞물려 설치한 차례대로 두었습니다`);
    if (warn.length) return `<div class="pk-rel is-warn">${warn.join('<br>')}</div>`;
    return st.needs.length ? '<div class="pk-rel is-ok">✓ 필요한 팩 켜짐</div>' : '';
  }
  function cardHTML(p) {
    const on = isEnabled(p.id);
    const editing = !!maker && maker.isDraftId(p.id); // 메이커: 지금 고치는 DLC — 연표에는 이 설치본 대신 작업본이 보입니다
    return HT.packCard.html(p, { sel: p.id === dlcUi.sel, toggle: on, off: !on, tag: editing ? '고치는 중' : '', rel: relLineHTML(p) });
  }
  function detailHTML(p) {
    const st = HT.packRelationState(p, state.packs, isEnabled);
    const editing = !!maker && maker.isDraftId(p.id);
    const names = list => list.map(x => `${esc(x.name)}${x.state === 'missing' ? ' <small>(없음)</small>' : x.state === 'off' ? ' <small>(꺼짐)</small>' : ''}`).join(' · ');
    const clash = (p.relations || []).filter(r => r.type === 'conflicts').map(r => esc((packById(r.id) || {}).name || r.name || r.id));
    const rel = [st.needs.length ? `필요한 팩: ${names(st.needs)}` : '필요한 팩 없음', st.recommends.length ? `함께 쓰면 좋은 팩: ${names(st.recommends)}` : '', clash.length ? `함께 못 씀: ${clash.join(' · ')}` : '', st.after.length ? `뒤에 불러오기: ${names(st.after)}` : '']
      .filter(Boolean)
      .join('<br>');
    const log = (p.changelog || []).slice(0, 10);
    return `<aside class="pk-detail" aria-label="${esc(p.name)} 자세히">
      <div class="pk-cover">${coverHTML(p)}</div>
      <div class="in">
        <h3>${esc(p.name)} <small>v${esc(p.version)}${p.author ? ` · 만든 이: ${esc(p.author)}` : ''}</small></h3>
        ${p.description || p.summary ? `<p>${esc(p.description || p.summary)}</p>` : ''}
        ${(p.highlights || []).length ? `<h4>볼거리</h4><ul>${p.highlights.map(h => `<li>${esc(h)}</li>`).join('')}</ul>` : ''}
        <h4>담긴 것</h4><p>${esc(contentsText(p))} · 트랙: ${esc(p.tracks.map(t => t.name).join(', ') || '없음')}</p>
        <h4>관계</h4><p>${rel}</p>
        ${log.length ? `<h4>판 기록</h4><div class="pk-log">${log.map(c => `<span><b>v${esc(c.version)}</b>${c.date ? `${esc(c.date)} · ` : ''}${esc(c.note || '')}</span>`).join('')}${p.changelog.length > 10 ? `<span>…외 ${p.changelog.length - 10}줄</span>` : ''}</div>` : ''}
        <p class="pk-id">id: ${esc(p.id)}${p.updated ? ` · 마지막 반영 ${esc(p.updated)}` : ''}</p>
        <div class="pk-acts">
          <button type="button" class="btn btn-sm" data-export="${esc(p.id)}">파일로 저장 <small>(.htpack)</small></button>
          ${!maker || p.builtin || editing ? '' : `<button type="button" class="btn btn-sm" data-edit="${esc(p.id)}" title="고치는 DLC를 이것으로 바꿉니다">이 DLC 고치기</button>`}
          ${p.builtin ? '' : `<button type="button" class="btn btn-sm btn-danger" data-remove="${esc(p.id)}">${p.overridesBuiltin ? '업데이트 제거' : '지우기'}</button>`}
        </div>
      </div>
    </aside>`;
  }
  /** 찾기 칸 아래 전부: 카드 모눈 · 자세히 · 설치 기록 · 아래 줄 */
  function dlcMainHTML() {
    const q = dlcUi.q.trim().toLowerCase();
    const shown = state.packs.filter(p => (dlcUi.cat === 'all' || catOf(p) === dlcUi.cat) && (!q || [p.name, p.id, p.summary, p.description].concat(p.tags || []).some(s => String(s || '').toLowerCase().includes(q))));
    if (!state.packs.some(p => p.id === dlcUi.sel)) dlcUi.sel = (shown[0] || state.packs[0] || {}).id || '';
    const sel = packById(dlcUi.sel);
    const onList = state.packs.filter(p => isEnabled(p.id));
    return `
      <div class="pk-wrap">
        <div class="pk-grid">${shown.map(cardHTML).join('') || '<p class="hint">맞는 DLC가 없습니다.</p>'}</div>
        ${sel ? detailHTML(sel) : ''}
      </div>
      <div class="install-log">${logHTML()}</div>
      <p class="pk-foot">켜 둔 팩 ${onList.length}개 · 불러오는 차례: ${onList.map(p => esc(p.name)).join(' → ') || '없음'} · 파일을 이 창에 끌어다 놓아도 설치됩니다</p>`;
  }
  /** 찾기 칸에 칠 때: 위 칸(분류 · 찾기 칸)은 그대로 두고 아래만 다시 그림 — 찾기 칸을 새로 만들면 한글 조합(IME)이 글자마다 끊김 */
  function renderDlcMain() {
    const main = dlcBody.querySelector('[data-dlc-main]');
    if (main) main.innerHTML = dlcMainHTML();
    else renderDlc();
  }
  function renderDlc() {
    const cats = [{ id: 'all', name: '전체' }, { id: 'base', name: '기본팩' }].concat(HT.PACK_CATEGORIES);
    const count = id => (id === 'all' ? state.packs.length : state.packs.filter(p => catOf(p) === id).length);
    dlcBody.innerHTML = `
      <div class="pk-top">
        <div class="pk-seg" role="tablist" aria-label="분류로 거르기">${cats.map(c => `<button type="button" role="tab" data-cat="${c.id}" aria-selected="${dlcUi.cat === c.id}"${c.id !== 'all' && !count(c.id) ? ' class="is-empty"' : ''}>${esc(c.name)}${c.id === 'all' ? ` <small>${count('all')}</small>` : ''}</button>`).join('')}</div>
        <input type="search" class="pk-find" data-find value="${esc(dlcUi.q)}" aria-label="이름 · 태그로 찾기" title="이름 · 태그로 찾기" autocomplete="off">
        <span class="spacer"></span>
        <button type="button" class="btn btn-sm" data-backup title="설치한 DLC 모두와 켜고 끔을 한 파일로 — 다른 기기 · 앱으로 옮길 때 (되살릴 때는 백업 파일을 이 창에 놓습니다)">백업 저장</button>
        <button type="button" class="btn btn-sm btn-primary" data-install>＋ DLC 설치 <small>(.htpack)</small></button>
      </div>
      <div data-dlc-main>${dlcMainHTML()}</div>`;
  }

  const pickPack = id => {
    dlcUi.sel = id;
    renderDlc();
  };
  dlcDialog.addEventListener('click', e => {
    if (e.target === dlcDialog || e.target.closest('[data-close]')) return dlcDialog.close();
    const b = e.target.closest('button');
    if (!b) {
      const card = e.target.closest('[data-pick-pack]');
      if (card && !e.target.closest('.switch')) pickPack(card.dataset.pickPack); // 스위치는 켜고 끄기만
      return;
    }
    if (b.dataset.cat) {
      dlcUi.cat = b.dataset.cat;
      renderDlc();
    } else if (b.dataset.enable) {
      state.packState[b.dataset.enable] = { enabled: true };
      HT.store.set(K.packState, state.packState);
      refresh();
      renderDlc();
    } else if ('install' in b.dataset) HT.pickFiles('.htpack', true).then(installFiles);
    else if ('backup' in b.dataset) {
      exportBackup();
    } else if (b.dataset.export) {
      exportPack(packById(b.dataset.export));
    } else if (b.dataset.edit && maker) {
      dlcDialog.close();
      maker.pick(b.dataset.edit); // 메이커: 고치는 DLC 바꾸기 (연표에는 이 단추가 없습니다)
    } else if (b.dataset.remove) removePack(b.dataset.remove);
  });

  dlcDialog.addEventListener('keydown', e => {
    const card = e.target instanceof Element && e.target.matches('[data-pick-pack]') ? e.target : null;
    if (!card || (e.key !== 'Enter' && e.key !== ' ')) return;
    e.preventDefault();
    pickPack(card.dataset.pickPack);
    const again = dlcBody.querySelector(`[data-pick-pack="${CSS.escape(dlcUi.sel)}"]`);
    if (again) again.focus();
  });
  dlcDialog.addEventListener('input', e => {
    if (!(e.target instanceof Element) || !e.target.matches('[data-find]')) return;
    dlcUi.q = e.target.value;
    renderDlcMain(); // 찾기 칸은 다시 그리지 않음 — 한글 조합(IME)이 끊기지 않게 (초점 · 커서도 그대로)
  });
  dlcDialog.addEventListener('change', e => {
    const id = e.target.dataset.toggle;
    if (!id) return;
    state.packState[id] = { enabled: e.target.checked };
    HT.store.set(K.packState, state.packState);
    refresh();
    renderDlc();
  });

  async function exportBackup() {
    try {
      const bytes = await HT.packFile.build({
        format: 'history-timeline-backup', savedAt: new Date().toISOString(),
        packState: state.packState, installed: HT.store.get(K.installed, []),
      });
      await HT.downloadBlob(`history-timeline-backup-${new Date().toISOString().slice(0, 10)}.htpack`, new Blob([bytes], { type: HT.packFile.MIME }));
    } catch (e) { HT.toast(`백업 파일을 만들지 못했습니다 — ${e.message || e}`, 'error'); }
  }

  /* 설치할 때 표지를 줄이는 문턱 — data URL 글자 수 (docs/구상-메이커-팩.md 2-6: 설치본에는 960×540 이하) */
  const COVER_KEEP = 300000;
  /* 설치할 때 문서 그림을 줄이는 문턱 — data URL 글자 수(약 110KB 넘는 그림만 긴 변 960px로) */
  const DOC_IMAGE_KEEP = 150000;
  async function installFiles(files, { quiet = false } = {}) {
    const log = [];
    const ids = []; // 설치한 팩 id (메이커의 '파일에서 불러오기'가 불러온 팩에 더함)
    for (const file of files) {
      let got;
      try {
        got = await HT.packFile.read(file); // 전용 팩만 — JSON · ZIP · 이름만 바꾼 파일은 거절
      } catch (err) {
        log.push({ file: file.name, ok: false, text: err && err.packError ? err.message : 'DLC 파일을 읽을 수 없습니다.', details: err && err.packError ? [] : [String((err && err.message) || err)] });
        continue;
      }
      const raw = got.raw;
      if (raw && raw.format === 'history-timeline-backup') {
        restoreBackup(raw, file.name, log);
        continue;
      }
      /* 큰 표지(휴대폰 사진 같은)는 검사보다 먼저 줄입니다 — 검사는 1.5MB 넘는 표지를 버리므로 */
      if (raw && typeof raw.cover === 'string' && raw.cover.length > COVER_KEEP) {
        try {
          raw.cover = await HT.packFile.fitCover(raw.cover, 960, 540);
        } catch (e) {
          delete raw.cover;
          got.notes.push('표지 그림을 줄이지 못해 표지 없이 설치했습니다.');
        }
      }
      /* 문서 그림(형식 3 — DLC-형식.md '문서 그림'): 설치본은 브라우저 저장소(대략 5MB 안팎)에 두므로 큰 그림은 긴 변 960px로 줄여 둡니다(표지와 같은 까닭) */
      if (raw && Array.isArray(raw.images) && HT.namu && HT.namu.fitImage) {
        let shrunk = 0;
        for (const g of raw.images) {
          if (!g || typeof g.src !== 'string' || g.src.length <= DOC_IMAGE_KEEP) continue;
          try {
            const fit = await HT.namu.fitImage(g.src, 960);
            if (!fit.keep && fit.src.length < g.src.length) {
              Object.assign(g, { src: fit.src, width: fit.width, height: fit.height });
              shrunk++;
            }
          } catch (e) { /* 줄이지 못한 그림은 그대로 — 검사가 한도를 봅니다 */ }
        }
        if (shrunk) got.notes.push(`문서 그림 ${shrunk}장을 브라우저 저장소에 맞게 줄여(긴 변 960px) 설치했습니다.`);
      }
      const { pack, errors, warnings } = HT.normalizePack(raw);
      if (!pack) {
        log.push({ file: file.name, ok: false, text: '설치할 수 없는 파일입니다.', details: errors.map(x => x.msg) });
        continue;
      }
      const existing = packById(pack.id);
      if (existing && !confirm(`"${existing.name}" v${existing.version}이(가) 이미 있습니다.\n"${pack.name}" v${pack.version}(으)로 교체할까요?`)) {
        log.push({ file: file.name, ok: false, text: '설치를 취소했습니다.', details: [] });
        continue;
      }
      const installed = HT.store.get(K.installed, []).filter(p => p.id !== pack.id);
      installed.push(HT.packToJSON(pack));
      let stored = HT.store.set(K.installed, installed);
      if (!stored && pack.images) {
        /* 줄여도 넘치면 문서 그림을 빼고 다시 — 문서의 그림 자리는 '그림 없음'으로 남고, 나머지 자료는 그대로 설치됩니다 */
        const json = installed[installed.length - 1];
        const n = (json.images || []).length;
        delete json.images;
        delete pack.images;
        json.formatVersion = HT.formatVersionOf(json);
        stored = HT.store.set(K.installed, installed);
        if (stored) got.notes.push(`브라우저 저장 공간이 모자라 문서 그림 ${n}장을 빼고 설치했습니다 — 문서의 그 자리는 '그림 없음'으로 보입니다.`);
      }
      if (!stored) {
        log.push({ file: file.name, ok: false, text: '브라우저 저장 공간이 부족해 설치하지 못했습니다.', details: [] });
        continue;
      }
      state.packState[pack.id] = { enabled: true };
      HT.store.set(K.packState, state.packState);
      const skipped = errors.length ? ` · 문제가 있는 항목 ${errors.length}개는 건너뜀` : '';
      ids.push(pack.id);
      log.push({
        file: file.name,
        ok: true,
        text: `${got.kind === 'htpack' ? '팩 파일 ' : ''}"${pack.name}" v${pack.version} ${existing ? '교체' : '설치'} 완료 (사건 ${pack.events.length}개, 시대 ${pack.periods.length}개)${skipped}`,
        details: got.notes.concat(errors.concat(warnings).map(x => x.msg)),
      });
      loadPacks();
    }
    state.installLog = log;
    loadPacks();
    refresh();
    if (!quiet) openDlc();
    else for (const r of log.filter(r => !r.ok)) HT.toast(`${r.file} — ${r.text}${r.details.length ? ` (${r.details[0]})` : ''}`, 'error'); // 조용한 설치(메이커): 창 없이 걸린 것만 알림
    const ok = log.filter(r => r.ok).length;
    if (ok) HT.toast(`${ok}개 파일을 적용했습니다.`, 'ok');
    return ids;
  }

  /** 백업 파일(옛 연표의 [백업 파일 저장]): 설치한 DLC와 켜고 끔을 되살리고, 백업에 든 옛 "내 수정"은 DLC «내 수정»으로 옮깁니다 */
  function restoreBackup(raw, fileName, log) {
    if (!confirm('백업 파일입니다.\n지금 설치한 DLC를 백업 내용으로 바꿀까요?\n(백업에 든 옛 "내 수정"은 DLC «내 수정»으로 옮겨집니다)')) {
      log.push({ file: fileName, ok: false, text: '복원을 취소했습니다.', details: [] });
      return;
    }
    state.packState = raw.packState || {};
    HT.store.set(K.installed, Array.isArray(raw.installed) ? raw.installed : []);
    HT.store.set(K.packState, state.packState);
    let note = '';
    if (raw.user && typeof raw.user === 'object') {
      HT.store.set(K.user, raw.user);
      const r = HT.draft.migrateUser();
      state.legacyUser = r && !r.ok ? r.user : null;
      state.packState = HT.store.get(K.packState, {});
      note = r ? (r.ok ? ` 옛 "내 수정"은 DLC «${r.name}»(으)로 옮겼습니다.` : ` ${r.message}`) : '';
    }
    loadPacks();
    log.push({ file: fileName, ok: true, text: `백업(${raw.savedAt ? raw.savedAt.slice(0, 10) : '날짜 모름'})을 복원했습니다.${note}`, details: [] });
  }

  /** DLC 하나를 팩 파일(.htpack)로 내려받습니다 (기본팩도 같은 모양) */
  async function exportPack(p) {
    if (!p) return;
    try {
      const bytes = await HT.packFile.build(HT.packToJSON(p));
      await HT.downloadBlob(HT.packFile.fileName(p), new Blob([bytes], { type: HT.packFile.MIME }));
    } catch (e) {
      HT.toast(`팩 파일을 만들지 못했습니다 — ${(e && e.message) || e}`, 'error');
    }
  }

  function removePack(id) {
    const p = packById(id);
    const msg = p.overridesBuiltin
      ? `"${p.name}" 업데이트를 제거하고 기본 내장 버전으로 돌아갈까요?`
      : `"${p.name}" DLC를 삭제할까요?\n다시 설치하려면 DLC 파일이 필요합니다.`;
    if (!confirm(msg)) return;
    HT.store.set(K.installed, HT.store.get(K.installed, []).filter(x => x.id !== id));
    state.installLog = [];
    loadPacks();
    refresh();
    renderDlc();
  }

  /* ---------- 표로 보기 · CSV ---------- */
  const tableDialog = $('#tableDialog');

  function tableItems() {
    const rangeOnly = $('#tableRangeOnly').checked;
    const withPeriods = $('#tablePeriods').checked;
    const v = timeline.view;
    return state.visible
      .concat(withPeriods ? state.visibleFigures : []) // 인물은 "시대 · 인물도 포함"일 때 (구분 '인물', 시기는 활동 시기)
      .filter(x => (withPeriods || x.kind === 'event') && (!rangeOnly || (x.start <= v.end && x.endY >= v.start)))
      .sort((a, b) => a.start - b.start || trackOf(a.track).order - trackOf(b.track).order);
  }

  function renderTable() {
    const items = tableItems();
    const rows = items
      .map(x => {
        const cat = x.kind === 'event' ? (state.model.categoryMap.get(x.category) || {}).name || '' : '';
        const alts = (x.alternatives || []).map(a => (HT.altDated(a) ? `${HT.altWhen(a, x.kind === 'figure' ? figureBase(x) : x, { figure: x.kind === 'figure' })}(${a.label})` : a.label)).join(', '); // 비운 쪽은 통설 값 · 인물은 생몰 · 활동 · 날짜 없는 견해는 근거만
        return `<tr data-uid="${esc(x.uid)}">
          <td class="nowrap">${esc(HT.formatRange(x))}</td>
          <td class="nowrap">${esc(HT.itemWord(x))}</td>
          <td class="nowrap">${esc(trackOf(x.track).name)}</td>
          <td><b>${esc(x.title || x.name)}</b>${HT.historicityOf(x) ? ` <small class="hs-tag">${esc(HT.historicityName(HT.historicityOf(x)))}</small>` : ''}${alts ? `<div class="alt-cell">다른 견해: ${esc(alts)}</div>` : ''}</td>
          <td class="nowrap">${esc(cat)}</td>
          <td class="nowrap">${x.certainty === 'accepted' ? '' : esc(HT.certaintyName(x.certainty))}</td>
          <td class="desc-cell">${esc((x.description || '').slice(0, 100))}</td>
        </tr>`;
      })
      .join('');
    $('#tableBody').innerHTML = `
      <p class="hint">${items.length}개 · 줄을 누르면 ${maker ? '그 항목으로 가서 오른쪽 편집 창이 열립니다' : '연표에서 그 위치로 갑니다'}. 지금 켜 둔 필터·검색이 그대로 적용됩니다.</p>
      <div class="table-wrap"><table class="mk-table data-table">
        <thead><tr><th>시기</th><th>구분</th><th>트랙</th><th>제목</th><th>분류</th><th>확실성</th><th>설명</th></tr></thead>
        <tbody>${rows || '<tr><td colspan="7" class="empty-note">표시할 항목이 없습니다.</td></tr>'}</tbody>
      </table></div>`;
  }

  function toCSV(items) {
    const head = ['시작', '끝', '구분', '트랙', '제목', '분류', '중요도', '확실성', '설명', '다른 견해', '쟁점', '태그', '출처', '제공'];
    head.push('실재성'); // 표 보기의 제목 옆 실재성 딱지와 같은 것 (실재면 빈칸 · 8-4 마)
    const q = s => `"${String(s == null ? '' : s).replace(/"/g, '""')}"`;
    const lines = [head.map(q).join(',')];
    for (const x of items) {
      lines.push(
        [
          // 날짜까지 적은 항목은 날짜 글 그대로 ("1592-05-23" · "음력 1592-04-13"), 연도만이면 예전처럼 수
          x.startUnknown ? '미정' : HT.dateInputValue(x, 'start'),
          x.ongoing ? '현재' : x.endUnknown ? '미정' : HT.dateInputValue(x, x.kind === 'figure' ? 'endY' : 'end'), // 인물의 끝은 짐작한 끝(endY)까지 — 활동 시기
          HT.itemWord(x), // 구분: 시대 · 사건 · 기관 · 문화 · 왕조 …
          trackOf(x.track).name,
          x.title || x.name,
          x.kind === 'event' ? (state.model.categoryMap.get(x.category) || {}).name || '' : '',
          x.kind === 'event' || x.kind === 'figure' ? x.importance || 2 : '',
          HT.certaintyName(x.certainty),
          x.description || '',
          (x.alternatives || []).map(a => HT.altText(a, x.kind === 'figure' ? figureBase(x) : x, { figure: x.kind === 'figure' })).join(' / '), // 표 보기와 같은 글 (인물은 생몰 · 활동 — 비운 쪽은 통설 값)
          x.debate || '',
          (x.tags || []).join(' '),
          x.source || '',
          x.packName,
          HT.historicityOf(x) ? HT.historicityName(HT.historicityOf(x)) : '', // 실재성 (맨 끝 열 — 머리의 head.push와 짝)
        ]
          .map(q)
          .join(',')
      );
    }
    return `﻿${lines.join('\r\n')}`;
  }

  $('#tableBtn').addEventListener('click', () => {
    renderTable();
    if (!tableDialog.open) tableDialog.showModal();
  });
  $('#tableRangeOnly').addEventListener('change', renderTable);
  $('#tablePeriods').addEventListener('change', renderTable);
  $('#csvBtn').addEventListener('click', () => {
    HT.downloadBlob('역사연표.csv', new Blob([toCSV(tableItems())], { type: 'text/csv;charset=utf-8' }));
    HT.toast('CSV 파일을 저장했습니다.', 'ok');
  });
  tableDialog.addEventListener('click', e => {
    if (e.target === tableDialog || e.target.closest('[data-close]')) return tableDialog.close();
    const tr = e.target.closest('tr[data-uid]');
    if (!tr) return;
    const item = state.model.byUid.get(tr.dataset.uid);
    if (!item) return;
    tableDialog.close();
    if (maker) openEditorFor(item.uid); // 메이커: 표에서 훑다가 누른 줄은 그 항목의 편집 창 (연표에서 띠를 누른 것과 같게)
    else openDetail(item.uid);
    timeline.focusOn(item); // 창을 먼저 연 뒤 — 창이 가리지 않은 부분으로 갑니다
  });

  /* ---------- 이미지 · 인쇄 ---------- */
  const imageDialog = $('#imageDialog');
  const svgString = () => timeline.toSVG({ width: Number($('#imgWidth').value) || 1800, title: $('#imgTitle').value.trim() });

  $('#imageBtn').addEventListener('click', () => {
    if (!$('#imgTitle').value) {
      const v = timeline.view;
      $('#imgTitle').value = `역사 연표 (${spanRange(v.start, v.end)})`; // 확대했으면 달·날까지
    }
    if (!imageDialog.open) imageDialog.showModal();
  });
  imageDialog.addEventListener('click', e => {
    if (e.target === imageDialog || e.target.closest('[data-close]')) imageDialog.close();
  });
  $('#svgBtn').addEventListener('click', () => {
    HT.downloadBlob('역사연표.svg', new Blob([svgString()], { type: 'image/svg+xml;charset=utf-8' }));
    HT.toast('SVG 파일을 저장했습니다.', 'ok');
  });
  $('#pngBtn').addEventListener('click', async () => {
    const svg = svgString();
    try {
      const img = new Image();
      img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
      await img.decode();
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, 0, 0);
      canvas.toBlob(b => {
        HT.downloadBlob('역사연표.png', b);
        HT.toast('PNG 파일을 저장했습니다.', 'ok');
      }, 'image/png');
    } catch (err) {
      HT.toast('PNG로 바꾸지 못했습니다. SVG로 저장해 보세요.', 'error');
    }
  });
  $('#printBtn').hidden = !HT.platform.canPrint;
  $('#printBtn').addEventListener('click', () => {
    HT.platform.print(
      `<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>${esc($('#imgTitle').value || '역사 연표')}</title>` +
        '<style>@page{size:A4 landscape;margin:8mm}body{margin:0}svg{width:100%;height:auto}</style></head><body>' +
        `${svgString()}</body></html>`
    );
  });

  /* ---------- 파일 끌어다 놓기 ---------- */
  const overlay = $('#dropOverlay');
  let dragDepth = 0;
  const hasFiles = e => !!e.dataTransfer && [...e.dataTransfer.types].includes('Files');
  window.addEventListener('dragenter', e => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth++;
    overlay.hidden = false;
  });
  window.addEventListener('dragover', e => hasFiles(e) && e.preventDefault());
  window.addEventListener('dragleave', e => {
    if (hasFiles(e) && --dragDepth <= 0) {
      dragDepth = 0;
      overlay.hidden = true;
    }
  });
  window.addEventListener('drop', e => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth = 0;
    overlay.hidden = true;
    const files = [...e.dataTransfer.files].filter(f => /\.htpack$/i.test(f.name));
    if (files.length) {
      if (maker) return maker.openDropped(files); // 메이커: 끌어다 놓은 파일은 설치가 아니라 열기
      installFiles(files);
    } else HT.toast('DLC 파일(.htpack)만 열 수 있습니다.', 'error');
  });
  // 앱·PWA에서 "연결 프로그램"으로 .htpack 파일을 열었을 때
  document.addEventListener('ht:files', e => e.detail && e.detail.length && (maker ? maker.openDropped(e.detail) : installFiles(e.detail)));

  /* ---------- 기타 조작 ---------- */
  function setFilterBar(open) {
    $('#filterbar').classList.toggle('is-open', open);
    $('#filterToggle').setAttribute('aria-expanded', String(open));
    state.ui.filterOpen = open;
    HT.store.set(K.ui, state.ui);
  }
  $('#filterToggle').addEventListener('click', () => setFilterBar(!$('#filterbar').classList.contains('is-open')));
  setFilterBar(!!state.ui.filterOpen);

  /* ---------- 메뉴 (⋯ 버튼 · 우클릭) · 단축키 · 집중 모드 ---------- */
  const menuEl = $('#ctxMenu');
  function setZen(on) {
    document.body.classList.toggle('is-zen', on);
    $('#zenExit').hidden = !on;
    if (on) HT.toast('집중 모드 — Z 또는 왼쪽 위 ☰로 돌아옵니다. 오른쪽 클릭으로 메뉴를 열 수 있습니다.');
  }
  $('#zenExit').addEventListener('click', () => setZen(false));
  function setSuccession(mode) {
    state.ui.show = Object.assign({}, state.ui.show, { succession: mode });
    HT.store.set(K.ui, state.ui);
    $('#linkToggle').checked = !!mode;
    timeline.setShow({ succession: mode });
  }
  /* 움직임 계측(감독용): 느리게 보기와 간이 점수표. 창을 처음 열 때에만 js/motion-probe.js를 불러옵니다 — 평소에는 비용 0.
     주소에 ?motion=1 (또는 0.25 · 0.1 — 첫 화면부터 그 빠르기)을 붙여도 열립니다 */
  function toggleMotionPanel() {
    if (HT.motionProbe) return HT.motionProbe.toggle();
    const s = document.createElement('script');
    s.src = 'js/motion-probe.js';
    s.onload = () => HT.motionProbe && HT.motionProbe.open();
    s.onerror = () => HT.toast('움직임 계측 도구를 불러오지 못했습니다.', 'error');
    document.head.appendChild(s);
  }
  if (new URLSearchParams(location.search).has('motion')) toggleMotionPanel();
  const KEYS = { filter: 'F', zen: 'Z', legend: 'L', map: 'M', table: 'T', image: 'P', year: 'Y', measure: 'R', dlc: 'D', event: 'N', period: 'Shift+N', organ: 'Shift+O', culture: 'Shift+C', dynasty: 'Shift+Y', wiki: 'W', foldAll: 'A', bird: 'V', fit: '0', zoomIn: '+', zoomOut: '-', search: '/', export: 'Ctrl+E' };
  /* 추가할 수 있는 항목 종류 — 사건이 먼저, 나머지는 폼 표(HT.FORMS)의 차례(부를 때마다 — 뒤에 더해진 폼도 저절로). 메뉴의 추가 줄 · 독의 ＋ · 단축키가 함께 봅니다 (메이커에서만).
     폼 항목의 선택 속성: add: false 연표의 추가 길에 두지 않음(시대 구분 — 바탕 자료에서) · addLabel 메뉴 글(없으면 "＋ <word> 추가") · key 단축키(없으면 KEYS[종류] — 'N' · 'Shift+N' 꼴) */
  const addKinds = () => ['event'].concat(Object.keys(HT.FORMS).filter(k => k !== 'event')).filter(k => HT.FORMS[k] && HT.FORMS[k].add !== false);
  const addKeyOf = kind => HT.FORMS[kind].key || KEYS[kind] || '';
  /** 메뉴의 추가 줄: preset(우클릭한 자리)이 있으면 그 날짜를 곁들입니다 */
  const addMenuItems = preset =>
    addKinds().map((kind, i) => {
      const F = HT.FORMS[kind];
      const base = F.addLabel || `＋ ${F.word} 추가`;
      const label = preset && !i ? `${base.replace(/^＋ /, '＋ 여기에 ')} (${HT.formatDate(preset.start, preset.startAt)})` : base;
      return { label, key: addKeyOf(kind), run: () => openEditor(null, kind, preset || {}) };
    });
  /** 누른 키의 추가 종류 (없으면 null) — "N" · "Shift+N" 꼴로 견줍니다 */
  const addKindForKey = e => {
    const k = e.key.length === 1 ? e.key.toUpperCase() : e.key;
    const want = `${e.shiftKey ? 'Shift+' : ''}${k}`;
    return addKinds().find(kind => addKeyOf(kind).toUpperCase() === want.toUpperCase()) || null;
  };
  if ($('#addPeriodBtn')) $('#addPeriodBtn').title = `항목 추가 — ${addKinds().map(k => `${HT.FORMS[k].word}${addKeyOf(k) ? ` ${addKeyOf(k)}` : ''}`).join(' · ')}`;
  /** 메뉴 항목. ctx = { uid, trackId, t } (우클릭한 자리 — t는 그 자리의 해 좌표 그대로). 고치는 줄(추가 · 수정 · 숨기기 …)은 메이커에서만 나옵니다 */
  function menuItems(ctx = {}) {
    const items = [];
    const x = ctx.uid ? state.model.byUid.get(ctx.uid) : null;
    const succ = state.ui.show.succession;
    /* 그릇 세 상태(서고 3단 · 설계 4-6 #2 B — 감독 "그릇 옆 버튼 3개 … 그냥 우클릭으로 · 우클릭한 위치가 그 그릇의 안이면 · 뒤의 작고 회색 글자로 무슨 그릇이 바뀌는지"):
       누른 자리를 품은 가장 안쪽 그릇의 세 줄이 맨 위 — 줄 뒤 회색 글(tip)은 그 그릇 이름 */
    if (ctx.scope) {
      const sc = ctx.scope;
      items.push({ title: `그릇 · ${sc.name}` });
      /* 선반(서고 과제 9): 펼친 채 상위 다섯만 제 줄 · 나머지는 폴더 발의 작은 꼬리표 */
      for (const [st, label] of [['open', '펼침'], ['shelf', '선반'], ['closed', '접음'], ['loose', '풂']]) items.push({ label, tip: sc.name, checked: sc.state === st, run: () => timeline.setScopeState(sc.uid, st) });
      items.push({ sep: true });
    }
    if (x) {
      const name = x.title || x.name;
      items.push({ title: `${HT.itemWord(x)} · ${name.length > 20 ? `${name.slice(0, 20)}…` : name}` });
      items.push({ label: '자세히 보기', run: () => openDetail(x.uid) });
      items.push({ icon: 'file', label: '문서', key: KEYS.wiki, run: () => openWiki(x.uid) });
      if (maker) items.push({ icon: 'file', label: '하위 문서 만들기…', run: () => { openWiki(x.uid); const b = $('[data-wiki-act="new-sub"]'); if (b) b.click(); } });
      items.push({ icon: 'zoom-in', label: '여기로 확대', run: () => timeline.focusOn(x) });
    }
    /* 대범위 모아 보기 (보기 쪽 — 7-4): 대범위 자신 · 이어진 시대 구분 · 든 정권 · 본국 */
    if (x) for (const s of x.kind === 'scope' ? [x] : (x.scopes || []).concat(x.hostedScopes || [])) items.push({ label: `대범위 모아 보기: ${s.name}`, checked: timeline.scopeOn(s), run: () => timeline.toggleScope(s.uid) });
    if (x && paneEditable(x.uid)) {
      items.push({ label: '✎ 수정', run: () => openEditorFor(x.uid) });
      if (maker.hasPatch(x.uid)) items.push({ label: '↩ 원래대로', run: () => revertItem(x) });
      items.push({ label: maker.isOwn(x) ? '🗑 삭제' : '🙈 숨기기', danger: true, run: () => deleteItem(x) });
    }
    if (x && maker && maker.isLocked(x)) items.push({ label: `🔓 자물쇠 풀기 (${x.packName})`, run: () => maker.unlock(x.packId) });
    if (x) items.push({ sep: true });
    if (ctx.trackId) {
      const tr = trackOf(ctx.trackId);
      const folded = (state.ui.folded || []).includes(ctx.trackId);
      items.push({ icon: 'fold', label: `${folded ? '펼치기' : '접기'}: ${tr.name} 트랙`, run: () => timeline.toggleFold(ctx.trackId) });
      items.push({ icon: 'file', label: `${tr.name} 문서`, run: () => openWiki(`track:${ctx.trackId}`) });
    }
    if (ctx.t != null) {
      // 확대 정도에 맞춰: 넓게 보면 그 해, 2년보다 좁으면 새 항목은 그날로 · "무슨 일이"는 그 달(두 달보다 좁으면 그날)로
      const preset = presetAt(ctx.t);
      const prec = panelPrec();
      const at = snapTo(ctx.t, prec);
      const panelWhen = prec === 'y' ? HT.formatYear(at) : HT.cal.formatT(at, prec);
      if (maker) items.push(...addMenuItems(preset));
      items.push({ icon: 'pin', label: `${panelWhen}에 무슨 일이`, key: KEYS.year, run: () => openYearPanel(at, null, { prec }) });
      items.push({ sep: true });
    } else {
      if (maker) items.push(...addMenuItems(null));
      items.push({ icon: 'pin', label: '같은 해', key: KEYS.year, run: () => $('#yearBtn').click() });
      items.push({ sep: true });
    }
    items.push({ icon: 'ruler', label: '기간 재기', key: KEYS.measure, checked: $('#measureBtn').getAttribute('aria-pressed') === 'true', run: () => $('#measureBtn').click() });
    items.push({ icon: 'expand', label: '전체 보기', key: KEYS.fit, run: () => timeline.fitAll() });
    items.push({ icon: 'bird', label: '조감', key: KEYS.bird, checked: timeline.isBird(), run: () => toggleBird() });
    items.push({ icon: 'fold', label: timeline.allFolded() ? '모두 펴기' : '모두 접기', key: KEYS.foldAll, run: () => timeline.foldAll(!timeline.allFolded()) });
    items.push({ sep: true });
    items.push({ id: 'filter', icon: 'menu', label: '필터', key: KEYS.filter, checked: $('#filterbar').classList.contains('is-open'), run: () => setFilterBar(!$('#filterbar').classList.contains('is-open')) });
    if (mapHooks) items.push(mapHooks.menuItem(KEYS));
    items.push({ icon: 'help', label: '범례', key: KEYS.legend, checked: !$('#legend').hidden, run: () => $('#legendBtn').click() });
    items.push({ icon: 'table', label: '표', key: KEYS.table, run: () => $('#tableBtn').click() });
    items.push({ icon: 'image', label: '이미지 · 인쇄', key: KEYS.image, run: () => $('#imageBtn').click() });
    items.push({ sep: true });
    items.push({ title: '승계선' });
    items.push({ label: '모두', tip: '직접 실선 · 간접 점선', checked: succ === true, run: () => setSuccession(true) });
    items.push({ label: '직접만', tip: '직접 승계만', checked: succ === 'direct', run: () => setSuccession('direct') });
    items.push({ label: '숨김', checked: !succ, run: () => setSuccession(false) });
    items.push({ sep: true });
    if (maker) items.push(...maker.menuItems(KEYS)); // 반영 · 파일로 · 고치는 DLC 바꾸기 · 연표로
    items.push({ icon: 'package', label: maker ? '불러온 팩' : 'DLC 관리', key: KEYS.dlc, run: () => $('#dlcBtn').click() });
    items.push({ sep: true });
    items.push({ icon: 'scan', label: '집중 모드', tip: '창을 숨기고 연표만', key: KEYS.zen, checked: document.body.classList.contains('is-zen'), run: () => setZen(!document.body.classList.contains('is-zen')) });
    items.push({ icon: 'search', label: '검색', key: KEYS.search, run: () => searchInput.focus() });
    items.push({ sep: true });
    items.push({ icon: 'activity', label: '움직임 계측', tip: '느리게 보기와 간이 점수표', checked: !!(HT.motionProbe && HT.motionProbe.isOpen()), run: toggleMotionPanel });
    return items;
  }
  /* 차림표의 기호 칸 (건의 8): 줄마다 선 아이콘 하나(it.icon) — 체크 줄은 체크. 다른 부품이 보낸 줄(지도 부품의 '🗺 지도' 등)은 맨 앞 그림 글자를 같은 한 벌의 기호로 바꿈.
     이름은 이름만(it.label — '이름만 쓰기'), 풀이가 필요하면 it.tip(올렸을 때의 풍선) */
  const LEAD_GLYPH = /^(🗺|📄|🧩)\uFE0F?\s+/u;
  const LEAD_ICONS = { '🗺': 'map', '📄': 'file', '🧩': 'package' };
  const leadIcon = label => {
    const m = typeof label === 'string' && label.match(LEAD_GLYPH);
    return m ? LEAD_ICONS[m[1]] : '';
  };
  function showMenu(items, x, y, { above = false } = {}) {
    menuEl.innerHTML = items
      .map(it => {
        if (it.sep) return '<div class="ctx-sep"></div>';
        if (it.title) return `<div class="ctx-title">${esc(it.title)}</div>`;
        const lead = it.icon ? '' : leadIcon(it.label);
        const ic = it.checked ? 'check' : it.icon || lead;
        return `<button type="button" class="ctx-item has-ic${it.checked ? ' is-checked' : ''}${it.disabled ? ' is-disabled' : ''}${it.danger ? ' is-danger' : ''}" role="menuitem"${it.id ? ` data-menu-id="${esc(it.id)}"` : ''}${it.tip ? ` title="${esc(it.tip)}"` : ''}>${ic ? icon(ic, 'ctx-ic') : '<span class="ctx-ic" aria-hidden="true"></span>'}<span class="ctx-label">${esc(lead ? it.label.replace(LEAD_GLYPH, '') : it.label)}</span>${it.key ? `<span class="ctx-key">${esc(it.key)}</span>` : ''}</button>`;
      })
      .join('');
    const runs = items.filter(it => !it.sep && !it.title);
    [...menuEl.querySelectorAll('.ctx-item')].forEach((el, i) => el.addEventListener('click', () => {
      hideMenu();
      runs[i].run && runs[i].run();
    }));
    menuEl.hidden = false;
    menuEl.style.left = '0px';
    menuEl.style.top = '0px';
    const r = menuEl.getBoundingClientRect();
    if (above) y -= r.height;
    menuEl.style.left = `${Math.max(4, Math.min(x, innerWidth - r.width - 4))}px`;
    menuEl.style.top = `${Math.max(4, Math.min(y, innerHeight - r.height - 4))}px`;
    const first = menuEl.querySelector('.ctx-item:not(.is-disabled)');
    if (first) first.focus();
  }
  function hideMenu() {
    menuEl.hidden = true;
  }
  $('#menuBtn').addEventListener('click', e => {
    if (!menuEl.hidden) return hideMenu();
    const r = e.currentTarget.getBoundingClientRect();
    showMenu(menuItems({}), r.right - 230, r.bottom + 8); // 맨 위 줄의 단추 아래로 (렌즈 차림표 · 집합 보기 목록과 같은 자리 — 단추를 덮지 않게)
    e.currentTarget.setAttribute('aria-expanded', 'true'); // 연 동안 단추는 반전 채움 (건의 8 — 렌즈 · 필터 단추와 같게)
  });
  /* 차림표가 어느 길로 닫히든(바깥 누름 · Esc · 줄 실행 · 렌즈 차림표로 넘어감) ⋯ 단추의 켜짐을 풂 */
  new MutationObserver(() => menuEl.hidden && $('#menuBtn').setAttribute('aria-expanded', 'false')).observe(menuEl, { attributes: true, attributeFilter: ['hidden'] });
  $('#stage').addEventListener('contextmenu', e => {
    if (e.target.closest('#detail, #wikiPane, #mapPanel, #legend, #editPane, input, textarea, select')) return;
    e.preventDefault();
    const host = e.target.closest('[data-uid]');
    const track = e.target.closest('.tl-track');
    const inLanes = e.target.closest('.tl-lanes, .tl-grid, .tl-inner');
    const ctx = { uid: host ? host.dataset.uid : null, trackId: track ? track.dataset.track : null, t: inLanes ? timeline.yearAtClientX(e.clientX) : null };
    if (MAKE && inLanes) ctx.scope = timeline.scopeAtPoint(e.clientX, e.clientY); // 서고 3단: 누른 자리를 품은 가장 안쪽 그릇 — 세 상태(펼침 · 접음 · 풂)가 차림표 맨 위에
    $('#menuBtn').setAttribute('aria-expanded', 'false'); // 오른쪽 클릭 차림표는 ⋯ 단추의 것이 아님
    showMenu(menuItems(ctx), e.clientX, e.clientY);
  });
  document.addEventListener('pointerdown', e => {
    if (!menuEl.hidden && !e.target.closest('#ctxMenu, #menuBtn, #addPeriodBtn')) hideMenu();
    // 필터 시트는 바깥을 누르면 접힙니다
    if ($('#filterbar').classList.contains('is-open') && !e.target.closest('#filterbar, #filterToggle, dialog, #ctxMenu')) setFilterBar(false);
  });
  window.addEventListener('blur', hideMenu);
  /** 초점이 메이커의 창(편집 창 · 바탕 자료 · 검사 · 큰 입력 창) 안에 있는지 — 저장 단추 · 색 단추처럼 글 칸이 아닌 것에 초점이 있어도
      그 창에서 누른 글자가 연표의 단축키(n 새 사건 · t 표 · a 모두 접기 · / 검색 …)로 새지 않게 (연표에는 이 창들이 없어 늘 거짓) */
  const inMakerWin = () => {
    const a = document.activeElement;
    return !!(a && a.closest && a.closest('#editPane, .mk-win, .fp-win, #mkProps, #mkStart')); // 팩 정보 · 처음 화면 안의 단추에 초점이 있어도 글자가 단축키로 새지 않게
  };
  document.addEventListener('keydown', e => {
    if (!menuEl.hidden && e.key === 'Escape') return hideMenu();
    if (e.defaultPrevented) return; // 연표에 초점이 있어 연표가 이미 처리한 키(화살표 · + − · 0 — timeline.js) — 같은 키가 두 번 실행되지 않게 (확대가 쌓이는 엔진이라 두 번이면 두 배)
    if (document.querySelector('dialog[open]') || /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)) return;
    if (inMakerWin()) return;
    if (maker && maker.isStart()) return; // 처음 화면이 떠 있으면 연표 단축키는 쉽니다 (뒤에서 창이 열리지 않게)
    if (!$('#wikiPane').hidden && $('#wikiEditor') && !$('#wikiEditor').hidden) return;
    if (e.altKey) return;
    const k = e.key;
    const ctrl = e.ctrlKey || e.metaKey;
    const run = fn => {
      e.preventDefault();
      fn();
    };
    if (ctrl && !e.shiftKey && k.toLowerCase() === 'e') return maker && run(() => maker.reflect()); // 메이커: 반영 (Ctrl+Shift+E는 팩 파일로 — 작업실 틀이 받습니다)
    if (ctrl) return;
    if (k === 'Escape') {
      if (document.body.classList.contains('is-zen') && !state.selected) return run(() => setZen(false));
      return;
    }
    const addKind = maker ? addKindForKey(e) : null; // 추가 단축키(N · Shift+N …)는 메이커에서만 — 종류는 폼 표를 돎
    if (addKind) return run(() => openEditor(null, addKind));
    if (e.shiftKey) {
      if (k === '+') return run(() => timeline.zoom(0.6));
      return;
    }
    const map = {
      f: () => setFilterBar(!$('#filterbar').classList.contains('is-open')), z: () => setZen(!document.body.classList.contains('is-zen')),
      l: () => $('#legendBtn').click(), m: () => mapHooks && mapHooks.toggle(), t: () => $('#tableBtn').click(), p: () => $('#imageBtn').click(), y: () => $('#yearBtn').click(),
      r: () => $('#measureBtn').click(), d: () => $('#dlcBtn').click(), a: () => timeline.foldAll(!timeline.allFolded()), v: () => toggleBird(),
      w: () => state.selected && openWiki(state.selected), '0': () => timeline.fitAll(), '+': () => timeline.zoom(0.6), '=': () => timeline.zoom(0.6), '-': () => timeline.zoom(1.6),
      ArrowLeft: () => timeline.panBy(-timeline.span() * 0.15, { smooth: true }), ArrowRight: () => timeline.panBy(timeline.span() * 0.15, { smooth: true }),
    };
    const fn = map[k] || map[k.toLowerCase()];
    if (fn) run(fn);
  });
  $('.zoom-controls').addEventListener('click', e => {
    const b = e.target.closest('[data-zoom]');
    if (!b) return;
    if (b.dataset.zoom === 'in') timeline.zoom(0.6);
    if (b.dataset.zoom === 'out') timeline.zoom(1.6);
    if (b.dataset.zoom === 'fit') timeline.fitAll();
    if (b.dataset.zoom === 'bird') toggleBird();
  });
  /* 표시 체크: 체크 상자 id → show의 열쇠 (기본값은 HT.SHOW_DEFAULTS — 새 체크는 두 표에 한 줄씩) */
  const SHOW_TOGGLES = { dynastyToggle: 'dynasties', leaderToggle: 'leaders', cabinetToggle: 'cabinets', eraToggle: 'eras', capToggle: 'capitals', ganjiToggle: 'ganji', epochToggle: 'epochs', linkToggle: 'succession', partToggle: 'partOf' };
  Object.assign(SHOW_TOGGLES, { spotEchoToggle: 'spotEcho' }); // 조명 메아리 ('같은 시기를 타국에도' — 칸 상세 안에도 같은 스위치: setSpotEcho)
  Object.assign(SHOW_TOGGLES, { phaseToggle: 'phases' }); // 시기 구분(학계) 단 (띠 안 묶음)
  Object.assign(SHOW_TOGGLES, { rankToggle: 'ranks' }); // 지위 단 · 책갈피 탭의 지위 딱지 (띠 안 묶음)
  Object.assign(SHOW_TOGGLES, { groupToggle: 'groups' }); // 단체: 집권 단 · 실권 단 · 명목 지도자 · 연합의 겹 탭 (띠 안 묶음 — 설계 7-8 결정 1 ~ 3 · 지위 다음)
  Object.assign(SHOW_TOGGLES, { figureToggle: 'figures' }); // 인물 단
  Object.assign(SHOW_TOGGLES, { houseToggle: 'houses' }); // 가문 줄 (기본 끔)
  $('#spotEchoToggle').addEventListener('change', e => setSpotEcho(e.target.checked)); // 열려 있는 칸 상세의 스위치도 함께 맞춥니다
  $('#foldAllBtn').addEventListener('click', () => timeline.foldAll(!timeline.allFolded()));
  /* 지도자 표기 방식 · 대수 */
  const leaderSel = $('#leaderLabelSelect');
  fillLeaderModes(); // 머리는 바로 앞의 '지도자' 체크 (이름만 쓰기 — 줄마다 '지도자:'를 되풀이하지 않음)
  $('#ordinalToggle').checked = !!state.ui.leaderOrdinal;
  leaderSel.addEventListener('change', e => {
    state.ui.leaderLabel = e.target.value;
    HT.store.set(K.ui, state.ui);
    timeline.setLeaderLabel(state.ui.leaderLabel, null);
    if (state.selected) openDetail(state.selected);
  });
  $('#ordinalToggle').addEventListener('change', e => {
    state.ui.leaderOrdinal = e.target.checked;
    HT.store.set(K.ui, state.ui);
    timeline.setLeaderLabel(null, state.ui.leaderOrdinal);
  });

  /* ---------- 표기 · 글꼴 (10건 3 · 9 — 감독 결정 D2-2 · 3 A · 4 B · 5 A) ----------
     필터 시트 '표기' 무리: [원어: 상세 창만 ▾](상세 창만 · 없음 · 왼쪽 칸에도) · 적용 ☑나라 ☑인물 ☑지명 · [글꼴: 기본 ▾](켜진 DLC에 글꼴이 있을 때만).
     무리는 자료에 이름 목록(형식 3 names)이나 글꼴이 하나라도 있을 때만 보입니다 — 없으면 시트가 지금 그대로. 연표 · 메이커가 같은 무리를 씁니다(.filter-shows 끝에 이 스크립트가 지음).
     설정은 고를 때만 저장(ht.ui.names = { orig, kinds } · ht.ui.fonts = { screen } — HT.namesUi가 기본값: 원어 상세 창만 · 적용 셋 모두 · 기본 글꼴).
     '왼쪽 칸에도'면 연표 맨 왼쪽 줄 이름 칸(나라 이름 줄)에만 원어를 함께 적습니다(책갈피 탭 · 지도자 칸에는 넣지 않음 — 감독 "맨 왼쪽 구분표에서만"). 띠 표로 그릴 수 없는 원어는 로마자로 물러남(HT.bandOrig) */
  const NAME_KIND_BOXES = [['polity', 'namesPolity'], ['person', 'namesPerson'], ['place', 'namesPlace']];
  const namesGroup = (() => {
    const host = document.querySelector('#filterbar .filter-shows');
    if (!host) return null;
    host.insertAdjacentHTML(
      'beforeend',
      `<div class="filter-group filter-show names-show" id="namesGroup" role="group" aria-label="이름 표기" hidden>
        <span class="filter-title">표기</span>
        <select id="origSelect" aria-label="원어 함께 적기" title="원어(제 말 · 제 글자로 적은 이름)를 어디까지 함께 적을지 — 상세 창의 이름 아래 · 연표 맨 왼쪽 줄 이름 칸">${HT.NAMES_ORIG.map(o => `<option value="${o.id}">원어: ${esc(o.name)}</option>`).join('')}</select>
        <span class="filter-sub" title="원어 고르기를 어느 이름에 쓸지">적용</span>
        <label class="check" title="나라 · 왕조 · 가문 · 성씨 · 연호 · 내각 · 단체 · 제도의 이름에"><input id="namesPolity" type="checkbox" checked> 나라</label>
        <label class="check" title="지도자 · 인물의 이름에"><input id="namesPerson" type="checkbox" checked> 인물</label>
        <label class="check" title="도읍 · 지명에"><input id="namesPlace" type="checkbox" checked> 지명</label>
        <select id="fontSelect" aria-label="화면 글꼴" title="화면 글꼴 — 한글을 덮는 글꼴 팩을 고르면 화면 전체가 그 글꼴로. 화면 글꼴에 없는 글자는 켜진 글꼴 팩이 저절로 채웁니다" hidden></select>
      </div>`
    );
    return host.lastElementChild;
  })();
  /** 자료에 이름 목록이 하나라도 있나 (모델마다 한 번) — 시대 · 사건 · 인물 · 가문 · 성씨 · 지명 · 단체 · 제도와 시대의 칸 */
  const modelHasNames = m => {
    if (m._hasNames != null) return m._hasNames;
    const has = x => !!(x && Array.isArray(x.names) && x.names.length);
    const cellsHave = p => HT.CELL_KINDS.some(C => Array.isArray(p[C.list]) && p[C.list].some(has));
    return (m._hasNames = [m.periods, m.events, m.figures, m.houses, m.surnames, m.places, m.groups, m.institutions].some(l => (l || []).some(x => has(x) || (x.kind === 'period' && cellsHave(x)))));
  };
  /** 왼쪽 줄 이름 칸에 함께 적을 원어를 고르는 함수 (원어: 왼쪽 칸에도 · 적용 '나라'일 때만 — 아니면 null = 지금 그대로) */
  const origFn = () => {
    const u = namesUi();
    if (u.orig !== 'band' || !u.kinds.polity) return null;
    const T = glyphT().band;
    const memo = new WeakMap(); // 줄 이름은 그리기마다 고르므로 정권마다 한 번만 셈 (설정 · 모델이 바뀌면 이 함수째 새로)
    return p => {
      if (!memo.has(p)) memo.set(p, HT.bandOrig(p.names, T));
      return memo.get(p);
    };
  };
  /** 화면 글꼴로 고를 수 있는 글꼴(한글 음절 전부를 덮는 것)인가 */
  const screenOk = f => HT.fontHasHangul(f);
  /** 모델이 바뀐 뒤 · 표기를 고른 뒤: 무리를 보이고 숨김 · 고르기 값 · 연표의 왼쪽 칸 원어 */
  function syncNamesUi() {
    const m = state.model;
    if (namesGroup && m) {
      const fonts = m.fonts || [];
      namesGroup.hidden = !(fonts.length || modelHasNames(m));
      const u = namesUi();
      $('#origSelect').value = u.orig;
      for (const [k, id] of NAME_KIND_BOXES) $('#' + id).checked = u.kinds[k];
      const sel = $('#fontSelect');
      sel.hidden = !fonts.length;
      const want = (state.ui.fonts && state.ui.fonts.screen) || '';
      sel.innerHTML = `<option value="">글꼴: 기본</option>${fonts
        .map(f => `<option value="${esc(f.id)}"${screenOk(f) ? '' : ' disabled'} title="${esc(`${f.packName ? `${f.packName} · ` : ''}라이선스 ${f.license}${screenOk(f) ? '' : ' — 한글이 없는 글꼴이라 화면 글꼴로는 쓰지 않고, 화면 글꼴에 없는 글자에만 씁니다'}`)}">글꼴: ${esc(f.family)}${screenOk(f) ? '' : ' (없는 글자에만)'}</option>`)
        .join('')}`;
      sel.value = fonts.some(f => f.id === want && screenOk(f)) ? want : '';
    }
    timeline.setOrig(origFn(), false);
  }
  function setNamesUi(patch) {
    const u = namesUi();
    state.ui.names = { orig: patch.orig || u.orig, kinds: Object.assign({}, u.kinds, patch.kinds || {}) };
    HT.store.set(K.ui, state.ui);
    timeline.setOrig(origFn());
    if (state.selected && !state.yearPanel && detailTarget(state.selected)) openDetail(state.selected, state.cell ? { cell: state.cell } : {});
  }
  if (namesGroup) {
    $('#origSelect').addEventListener('change', e => setNamesUi({ orig: e.target.value }));
    for (const [k, id] of NAME_KIND_BOXES) $('#' + id).addEventListener('change', e => setNamesUi({ kinds: { [k]: e.target.checked } }));
    $('#fontSelect').addEventListener('change', e => {
      state.ui.fonts = Object.assign({}, state.ui.fonts, { screen: e.target.value || null });
      HT.store.set(K.ui, state.ui);
      applyFonts();
    });
  }
  /* 글꼴 팩 싣기(10건 9 · 감독 결정 D2-4 B · 5 A): 켜진 DLC의 글꼴(형식 3 fonts — HT.fontFaces)을 브라우저 글꼴(FontFace)로 더하고, 화면 글꼴 목록(--font)의
     sans-serif 같은 일반 글꼴 이름 앞에 끼워 화면 글꼴에 없는 글자를 채웁니다(대체 — 저절로). [글꼴 ▾]로 고른 글꼴(한글을 덮는 것만)은 목록 맨 앞(화면 글꼴 — 하나만).
     이름이 같은 글꼴이 여러 DLC에 있어도 섞이지 않게 브라우저에는 'HT 글꼴 팩id 글꼴id'로 넣습니다. 글꼴이 다 실리면 연표가 글 폭을 그 글꼴로 다시 잽니다(timeline.refont).
     켜진 글꼴이 없고 화면 글꼴도 고르지 않았으면 아무것도 건드리지 않습니다(지금 화면 그대로) */
  const fontFaces = new Map(); // '팩id|글꼴id' → { face, source, family(브라우저에 넣은 이름), id }
  let fontBase = null; // 처음의 --font (common.css의 목록)
  let fontStackNow = '';
  function applyFonts() {
    const list = state.model ? HT.fontFaces(state.model) : [];
    const screenId = (state.ui.fonts && state.ui.fonts.screen) || '';
    if (!list.length && !fontFaces.size && !fontStackNow) return;
    if (typeof FontFace !== 'function' || !document.fonts) return;
    const want = new Set();
    const loads = [];
    for (const f of list) {
      const key = `${f.packId}|${f.id}`;
      want.add(key);
      const had = fontFaces.get(key);
      if (had && had.source === f.source) continue;
      if (had) document.fonts.delete(had.face);
      const family = `HT 글꼴 ${f.packId} ${f.id}`.replace(/["\\]/g, '');
      try {
        const face = new FontFace(family, f.source, f.descriptors);
        document.fonts.add(face);
        loads.push(face.load());
        fontFaces.set(key, { face, source: f.source, family, id: f.id });
      } catch (e) {
        /* 브라우저가 읽지 못한 글꼴 — 건너뜀 (파일 검사는 읽을 때 이미 함) */
      }
    }
    for (const [key, x] of [...fontFaces]) {
      if (want.has(key)) continue;
      document.fonts.delete(x.face);
      fontFaces.delete(key);
    }
    if (fontBase == null) fontBase = getComputedStyle(document.documentElement).getPropertyValue('--font').trim();
    const q = s => `"${s}"`;
    const fill = [...fontFaces.values()].map(x => q(x.family));
    const fontOf = id => (state.model && state.model.fontMap && state.model.fontMap.get(id)) || null;
    const screen = screenId && screenOk(fontOf(screenId)) ? [...fontFaces.values()].find(x => x.id === screenId) : null;
    let stack = '';
    if (fill.length || screen) {
      const parts = fontBase.split(',').map(s => s.trim()).filter(Boolean);
      const at = parts.findIndex(s => /^(?:serif|sans-serif|monospace|cursive|fantasy|system-ui|ui-serif|ui-sans-serif|ui-monospace|ui-rounded|math|emoji|fangsong)$/i.test(s));
      parts.splice(at < 0 ? parts.length : at, 0, ...fill.filter(f => !screen || f !== q(screen.family)));
      stack = (screen ? [q(screen.family)] : []).concat(parts).join(', ');
    }
    if (stack !== fontStackNow) {
      fontStackNow = stack;
      if (stack) document.documentElement.style.setProperty('--font', stack);
      else document.documentElement.style.removeProperty('--font');
      Promise.allSettled(loads).then(() => timeline.refont());
    } else if (loads.length) Promise.allSettled(loads).then(() => timeline.refont());
  }

  /* ---------- 범례 ---------- */
  const legendEl = $('#legend');
  function renderLegend() {
    const sw = (cls, text, c) => `<li><i class="lg ${cls}" style="--c:${c || '#bba395'}"></i><span>${text}</span></li>`;
    const dot = (cls, text, c) => `<li><span class="lg-dot ${cls}" style="--c:${c || '#abb3c9'}"><i></i></span><span>${text}</span></li>`;
    const line = (cls, text, c) => `<li><i class="lg-line ${cls}" style="--c:${c || '#bba395'}"></i><span>${text}</span></li>`;
    /* 정권 종류: 지금 자료에 쓰인 종류만. 종속 갈래는 제 띠가 옅은 띠 하나이므로 둘 이상 쓰였으면 한 줄로 묶습니다.
       속국 이름표(상국 띠가 품음 — 2026-09-20 '뒤집기') · 부흥 승계선은 자료에 매달린 탭 · 품은 칸 · 부흥 승계가 있을 때만 */
    const periods = state.model ? state.model.periods : [];
    const usedKinds = new Set(periods.map(p => p.polityKind || 'state'));
    const kinds = HT.ALL_KINDS.filter(k => usedKinds.has(k.id) || k.id === 'state');
    const deps = kinds.filter(k => k.family === 'dependent');
    const kindLine = k => sw(`k-${k.id}${k.family === 'dependent' ? ' fam-dep' : ''}`, `${esc(k.name)} — ${esc(k.hint.split(' — ').pop())}`);
    const kindLines = kinds
      .filter(k => k.family !== 'dependent' || deps.length === 1 || k === deps[0])
      .map(k => (k.family === 'dependent' && deps.length > 1 ? sw('fam-dep', `종속 갈래 — 옅은 띠 (${deps.map(d => esc(d.name)).join(' · ')}). 누구를 어떻게 섬겼는지는 상국 띠의 이름표로`) : kindLine(k)))
      .join('');
    const sides = new Set();
    if (HT.Timeline && HT.Timeline.depProxies) for (const v of HT.Timeline.depProxies(periods).values()) for (const it of v.items) for (const s of it.segs) sides.add(s.side);
    const depLine =
      (sides.has('out')
        ? `<li><span class="lg-hang"><i class="b"></i><i class="t is-loose"></i><i class="t is-firm"></i></span><span>상국 띠 아래에 매달린 이름표 — 스스로 다스린 속국: 빈 탭은 조공·책봉 · 봉국 · 자치령 · 복속 세력 · 기미, 칠한 탭은 종속 · 보호 · 위성 (점선 탭은 명목상 소속, 파선 탭은 예속이 아닌 소속 · 구성국 · 동군연합). 상국 띠의 ▾ 속국 단추로 접고 편다</span></li>`
        : '') +
      (sides.has('in')
        ? `<li><span class="lg-hang is-in"><i class="b"><i class="c is-held"></i><i class="c is-owned"></i></i></span><span>상국 띠 안 맨 아래의 이름표 — 상국이 다스린 속국: 옅은 칸은 괴뢰 · 위임 통치, 짙은 칸은 식민지 · 속령 · 직할령 · 군현, 빗금 칸은 점령지 · 군정. 매달려 있다가 안으로 들어오면 세로 끈으로 이어짐</span></li>`
        : '');
    /* 뒤 장 · 상국 탭(상국 표기 C — 건의 8의 2번 · 2026-10-14): 제 줄에 선 속국(상위 띠 아래에 접히지 않은 소속)이 띠로 그려지는 상국을 섬길 때만 — 견본은 연표와 같은 윤곽(Timeline.hostTabSample) · 글은 새 앱 범례(ui/legend.dart)와 같게 */
    const hasHostTab = periods.some(p => !p.singleHost && (p.hosts || []).some(h => h.host && !['overlay', 'dynasty', 'culture'].includes(h.host.polityKind)));
    const hostLine = hasHostTab && HT.Timeline && HT.Timeline.hostTabSample
      ? `<li><span class="lg-dot">${HT.Timeline.hostTabSample()}</span><span>뒤 장 — 속국 띠 뒤에 깔린 상국 빛깔의 종이(관계가 있던 기간만큼 · 띠 위로 살짝 드러남), 관계가 끝나는 쪽의 탭이 상국 이름. 짙기는 예속의 깊이: 옅게 조공·책봉 · 봉국 · 자치령 · 복속 · 기미, 가운데 종속 · 보호 · 위성, 짙게 괴뢰 · 위임 · 식민 · 군현 · 점령 (칠 없는 점선 테는 명목상 · 예속이 아닌 소속)</span></li>`
      : '';
    /* 연합의 겹 탭(설계 7-8 결정 3 C + 덧판 x2 A): 자료에 연합의 구성 나라가 있을 때만 — 띠 위에는 '연합' 딱지가 없으므로 모양의 뜻을 여기에. 견본은 연표와 같은 윤곽(Timeline.coalTabSample) */
    const hasCoal = HT.coalitionsOf && periods.some(p => HT.coalitionsOf(p).length);
    const coalLine = hasCoal && HT.Timeline && HT.Timeline.coalTabSample
      ? `<li><span class="lg-dot">${HT.Timeline.coalTabSample()}</span><span>겹친 탭 — 띠 위 탭 줄에 두 장이 겹친 탭은 그 나라가 든 연합 · 동맹(연합 빛깔 · 가담이 시작한 해의 자리). 겹은 여럿의 묶음이라는 뜻입니다(연맹 띠의 겹 테두리와 같은 말). 올리면 구성 나라의 띠만 또렷해지고 저마다의 가담 기간이 비치며, 누르면 단체 창. 필터의 <b>단체</b>로 켜고 끕니다</span></li>`
      : '';
    const hasRevival = periods.some(p => (p.predecessors || []).some(e => e.type === 'revival'));
    const revivalLine = hasRevival ? line('dashed ring', '부흥 — 멸망한 나라를 되살리려는 세력 (점선 + 후대 띠 앞의 작은 고리)') : '';
    /* 부분 승계 · 합류(흡수)는 자료에 있을 때만 — 견본은 연표와 같은 코드로 그림 (Timeline.thinSample) */
    const hasPartial = periods.some(p => (p.predecessors || []).some(e => e.type === 'partial'));
    const hasJoin = periods.some(p => (p.predecessors || []).some(e => HT.succAbsorbs(e.from, e.to)));
    const partialLine = hasPartial
      ? `<li><span class="lg-dot">${HT.Timeline.thinSample()}</span><span>부분 승계 — 나라는 끊겼으나 지배층·백성·영역·제도·문화의 일부가 넘어감. <b>가는 실선</b>(직접 승계는 굵은 실선) — 정도(약 · 중 · 강)와 이어진 것은 선에 올리거나 상세 창에서</span></li>`
      : '';
    const joinLine = hasJoin
      ? `<li><span class="lg-dot">${HT.Timeline.joinSample()}</span><span>합류 — 이미 있던 나라로 들어간 승계(흡수): 선이 후대의 건국 네모로 돌아가지 않고 멸망 네모 밑(위)에서 곧게 내려가(올라가) 그해의 띠 테두리에 닿고, 닿는 자리에 선대 색의 짧은 <b>합류 조각</b></span></li>`
      : '';
    /* 곧바로 이어지는 승계(같은 줄에서 맞닿거나 가까운 두 띠)의 다리 견본 — 연표와 같은 도우미로 그림 (Timeline.seamSample) */
    const seam = (type, text) => `<li><span class="lg-dot">${HT.Timeline.seamSample(type)}</span><span>${text}</span></li>`;
    const seamLines =
      seam('direct', '곧바로 이어지는 승계 — 두 네모 사이의 <b>다리</b>(반반 테두리색), 테두리는 <b>문</b>처럼 열림') +
      seam('indirect', '간접 승계의 다리 — 이음매 한가운데가 빈 점선') +
      (hasRevival ? seam('revival', '부흥의 다리 — 이음매 위 작은 고리') : '') +
      (hasPartial ? seam('partial', '부분 승계의 다리 — 가는 실선 (문 · 반반 테두리색은 같음)') : '');
    legendEl.innerHTML = `
      <h3>범례 <button class="icon-btn" type="button" data-legend-close aria-label="닫기">✕</button></h3>
      <h4>정권 띠</h4>
      <ul>${sw('', '통설 연대 (기본)')}${sw('z-estimated', '추정 연대 — 옅은 실선 테두리')}${sw('z-legend', '전승 연대 — 빗금')}${sw('z-range', '연대 폭이 있는 구간만 무늬')}${sw('z-unknown', '연도 미정 — 그쪽 끝이 둥글게 사라짐 · 옅은 실선 테두리')}</ul>
      <h4>정권 종류</h4>
      <ul>${kindLines}</ul>
      <h4>실재성 — 나라가 있었는가 (연대의 확실성과는 따로)</h4>
      <ul>${sw('h-semi', '반전설 — 띠 칠이 한 단 옅은 고른 색 · 탭에 “반전설”')}${sw('h-legendary', '전설 — 띠 칠이 두 단 옅은 고른 색 · 탭 이름이 기울어짐 · 탭에 “전설”')}${sw('h-disputed', '실재 논쟁 — 보통 띠 · 탭에 “논쟁”')}${sw('h-refuted', '부정됨 — 전설과 같은 옅은 칠을 색 없이 회색으로 · 탭 이름에 취소선 · 이어진 승계선 · 소속선이 옅어짐 · 탭에 “부정”')}</ul>
      <h4>대범위 — 흩어진 나라를 한 집합으로</h4>
      <ul>${sw('s-scope', '대범위를 켜면 구성 정권이 한 가지로 모이고 둘레에 옅은 테두리 — 왼쪽 위 이름표를 누르면 상세, 왼쪽 점선 칸을 누르면 접힘 · 짙은 세로 구간은 대범위의 기간', '#d7c18e')}${sw('s-hollow', '할거기 — 상징적 본국 띠의 그 기간이 속 빈 모양(이름만 남음) · 띠의 작은 단추(▸ 할거 4)로 모아 보기', '#d4a39b')}</ul>
      <h4>건국 · 멸망 · 승계 · 소속</h4>
      <ul>${dot('sq', '건국 (채운 둥근 네모, 띠 안쪽)', '#bba395')}${dot('sq hollow', '멸망·종료 (빈 둥근 네모)', '#bba395')}${dot('dashed', '연도 미정 (점선 동그라미)', '#bba395')}${line('', '직접 승계 — 승계를 선언')}${line('dashed', '간접 승계 — 지역·거시적 승계')}${revivalLine}${partialLine}${seamLines}${joinLine}${line('dotted', '소속선 — 상위 띠 아래에 접혀 들어간 정권 ↔ 상위 정권 (펼쳤을 때)')}<li><svg class="lg-union" width="34" height="18" viewBox="0 0 34 18" aria-hidden="true"><rect x="3.5" y="1.5" width="27" height="4" rx="2" fill="#efe6dc" stroke="#bba395"/><rect x="3.5" y="12.5" width="27" height="4" rx="2" fill="#efe6dc" stroke="#bba395"/><path d="M17 6V12.5" stroke="rgba(0,0,0,.6)" stroke-width="1.5"/><circle cx="17" cy="6" r="2" fill="#fff" stroke="#000" stroke-width="1.2"/><circle cx="17" cy="12.5" r="2" fill="#fff" stroke="#000" stroke-width="1.2"/></svg><span>동군연합 — 같은 사람이 같은 때 두 나라의 지도자: 겹친 기간의 가운데에서 두 지도자 칸을 꿰는 옅은 줄과 끝의 고리(한쪽이 화면 밖이면 칸 이름 앞의 겹고리)</span></li>${depLine}${hostLine}${coalLine}</ul>
      <h4>사건</h4>
      <ul>${dot('', '확실·통설 연대의 사건')}${dot('hollow', '추정·전승 연대, 또는 여러 나라가 함께 겪은 사건(속 빈 점)')}${dot('dashed', '연도 미정 (배치용 연도에 놓임)')}${line('rail', '기간이 있는 사건 — 양 끝이 실선 세로바인 가는 선 (실선은 기간에만)')}<li><span class="lg-dot"><i style="width:30px;height:7px;background:radial-gradient(circle at 4px 50%,#8f98b3 0 2.6px,transparent 3px),radial-gradient(circle at 15px 50%,#fff 0 1.7px,#8f98b3 1.8px 2.9px,transparent 3.2px),linear-gradient(90deg,#8f98b3 1px,transparent 1px) 0 50%/3px 1px repeat-x,radial-gradient(circle at 26px 50%,#fff 0 1.7px,#8f98b3 1.8px 2.9px,transparent 3.2px)"></i></span><span>연대가 갈리는 사건(끝 연도 없음) — 점선 실에 꿴 구슬: 채운 구슬 = 통설, 빈 고리 = 다른 견해. 기간이 아니라 "한 사건의 후보 연대"이며, 사건에 올리면 연도가 뜹니다. 날짜를 정확히 모르는 사건(연도만 · 세기로 · 연대 폭만 적은 것)은 범위를 그리지 않고 점 하나로 — 모른다는 것은 날짜 글과 풍선에</span></li>${line('dashed alt', '기간이 있는 사건의 다른 견해 — 이설의 시작 · 끝에 점선 세로바, 본래 시작 · 끝과 점선으로 연결', '#abb3c9')}</ul>
      <h4>칸</h4>
      <ul><li><span class="lg-dot"><i style="border-radius:2px;width:22px;height:9px;background:color-mix(in srgb,#bba395 15%,var(--paper));border:1px solid color-mix(in srgb,#bba395 40%,transparent)"></i></span><span>띠 맨 위: 왕조 칸(왕조를 적은 나라만 — 왕조마다 긴 둥근 칸) · 그 아래 지도자 칸 · 내각 칸. 이어지는 지도자 칸은 같은 왕조끼리 하나의 긴 둥근 칸에 가는 구분선으로 (좁으면 앞글자만, 마우스를 올리면 전체). 띠 안 맨 아래는 기관 칸(옅은 빗금)</span></li>
      <li><span class="lg-dot"><i style="border-radius:2px;width:22px;height:9px;background:color-mix(in srgb,#a0bcc5 12%,var(--paper));border-left:1px solid #a0bcc5"></i></span><span>맨 위 날짜 칸: 간지 줄(갑자년 강조) 아래 <b>연호</b>·<b>도읍</b> 묶음 줄. 접혀 있으면 나라마다 가는 막대만, 묶음 이름을 누르면 나라별 줄이 펼쳐집니다. 한 왕조의 연호, 한 정권의 도읍은 하나의 긴 둥근 칸으로 이어지고(천도 = 가는 구분선, 임시 도읍 = 점선 칸), 겹치는 정권은 갈래로 나뉩니다. 도읍 칸에 올리면 같은 도시를 쓴 다른 나라 칸까지 함께 진해지고, 배도(별도·5경·소경)는 나라 이름 옆 단추로 펼칩니다</span></li>
      <li><span class="lg-dot"><i style="width:22px;height:9px;background:radial-gradient(circle at 5px 50%,#b59a86 0 3px,transparent 3.5px),radial-gradient(circle at 17px 50%,#b59a86 0 3px,transparent 3.5px),linear-gradient(#b59a86,#b59a86) 5px 50%/12px 2px no-repeat"></i></span><span>이름 뒤에 작은 노선 표시가 있는 정권: 왼쪽 줄 이름에 잠깐 올리면(키보드는 Enter) 도읍 노선도 카드 — 본선 = 정도, 위 지선 = 배도, 아래 점선 우회 = 임시 도읍, 겹고리 = 다른 나라와 같은 도시(환승). 역을 누르면 그 시기로, 📌로 고정, Esc로 닫기</span></li></ul>
      <ul><li><span class="lg-dot"><i style="width:7px;height:7px;border-radius:50%;background:#d4a39b;box-shadow:0 0 0 1px #b08077"></i></span><span>띠 안 사건 분류별 글줄: 한 띠에 분류가 둘 이상이면 분류마다 글줄 하나(정치 → 전쟁 → 외교·교류 → 사회·경제 → 문화·사상 순), 글줄 사이는 옅은 점선. 왼쪽 줄 이름 칸 오른쪽의 색 점이 그 글줄의 분류(올리면 이름). ‘빽빽하게’에서는 한 글줄</span></li>
      <li><span class="lg-dot"><i style="width:22px;height:7px;border-radius:2.5px;background:#e8dfe2;box-shadow:inset 0 0 0 1px #a99aa3"></i></span><span>조감(띠 밀도 넷째 · V · ↕): 줄이 띠 하나 높이로 — 나라 이름은 띠 안 왼쪽, 사건은 작은 점 · 개수 알약, 승계선은 네모 대신 띠 끝 가운데에(테두리의 문을 지나 3px). 모양(이름 + 점 · 이름만 · 띠 · 선만)과 ‘축소하면 조감’은 필터 바에서</span></li>
      <li><span class="lg-dot"><i style="border-radius:3px;width:22px;height:11px;background:var(--paper);border:1px solid color-mix(in srgb,#bba395 45%,transparent);font-size:8px;line-height:9px;text-align:center;color:#bba395">▸ 3</i></span><span>띠 첫 글줄 왼쪽의 작은 단추(▸ 3): 딸린 정권(연맹 구성국·종속국·조직체) 개수. 누르면 바로 아래 줄로 펼쳐집니다</span></li>
      <li><span class="lg-dot"><i style="width:9px;height:22px;border-radius:3px;background:color-mix(in srgb,#9dbea8 55%,var(--paper-2));box-shadow:0 0 0 1px var(--paper)"></i></span><span>민족 칸 자리 오른쪽 끝의 작은 세로 딱지: 상위 띠 아래에 펼쳐진 정권의 민족이 그 자리의 민족 칸과 다를 때 제 민족을 알립니다(자리는 소속이, 딱지는 제 민족이). 누르면 그 민족의 문서</span></li></ul>
      ${figureLegendHTML()}
      <p class="lg-note">세로 눈금은 옅은 점선과 한 칸 걸러 깔린 바탕색으로만 표시해, 승계선(실선·점선)·소속선과 섞이지 않습니다. 트랙 이름·민족 칸(대명제부터 세부 민족까지 단계별)·연호·도읍 묶음 이름을 누르면 접거나 펼칩니다. 같은 줄은 승계(직접·간접·부흥·부분)로 이어진 정권만 함께 씁니다(같은 해에 시작하는 나라들이 한 줄을 다투면 직접 승계가 먼저, 그다음 부흥·간접, 부분 승계가 마지막). 다른 줄로 곧바로 이어지면 멸망 네모 밑(위)에서 곧게 나오는 내림줄로 잇고, 띠 안을 지나는 선의 끝은 띠 위에 짙게 그려 네모에 닿는 모습이 보입니다. 띠에 마우스를 올리거나 고르면 그 정권의 승계선이 짙어집니다(굵기는 그대로). 필터 바의 체크로 칸·선을 켜고 끕니다.</p>`;
    /* 칸 기간 조명 · 조명 메아리 (범례 한 줄 — '칸' 묶음의 끝에) */
    legendEl.querySelector('.lg-note').insertAdjacentHTML(
      'beforebegin',
      '<ul><li><span class="lg-dot"><i style="border-radius:3px;width:22px;height:11px;background:linear-gradient(90deg,transparent 0 30%,color-mix(in srgb,#9dbea8 45%,var(--paper)) 30% 70%,transparent 70%);border:1px solid color-mix(in srgb,#9dbea8 60%,transparent)"></i></span><span>칸 기간 조명: 띠 안의 지도자·내각·시기·지위 칸, 맨 위 날짜 칸의 연호·도읍 칸, 왕조 칸을 누르면 그 칸은 진하게, 띠 안의 그 기간은 옅게 칠해지고 그 칸의 창이 열립니다(인물 창을 열면 활동한 띠마다 그 활동 기록의 기간이 칠해짐). 필터의 <b>같은 시기를 타국에도</b>(칸 · 시기 · 지위 · 왕조 · 인물 창 안에도 같은 스위치)를 켜면 이 모든 조명의 기간이 그때 있던 타국의 띠 안에도 제 조명과 같은 짙기로 칠해지고(강조 밖이라 흐려진 띠도 그 시기만큼은 흐리지 않음), 그 시기 타국의 사건도 제 사건처럼 밝게 남으며(창에는 나라별 <b>같은 시기 타국</b> 묶음), 맨 위 연도 줄에 가는 괄호가 섭니다</span></li></ul>'
    );
    /* 칸의 이설 · 모호한 칸 (범례 세 줄 — 자료의 칸에 이설이나 모호한 연대가 있을 때만, '칸' 묶음의 끝에 · 디테일 건의 4) */
    /* 줄마다 따로: 유령 구분선 · 이설 조명은 날짜 있는 이설이 있을 때, 모호한 칸은 모호한 연대(추정 · 전승 · 연대 폭)가 있을 때 — 글만 있는 견해 · '확실'은 연표에 그림이 없으므로 범례도 없음 */
    const figs = state.model ? state.model.figures || [] : [];
    const cellsAll = periods.flatMap(p => [...HT.CELL_KINDS.flatMap(K => HT.cellsOf(p, K)), ...(p.hosts || []), ...(p.dynasties || [])]).concat(figs.flatMap(f => f.services || []));
    const cellAlt = cellsAll.some(c => c && (c.alternatives || []).some(HT.altDated)) || figs.some(f => (f.alternatives || []).some(HT.altDated)) || periods.some(p => (p.itemKind === 'organ' || p.polityKind === 'dynasty') && HT.datedAlts(p).length); // 기관 · 왕조 항목 자신의 이설도 칸의 유령선으로
    const cellFuzzy = cellsAll.some(c => HT.isFuzzy(c));
    if (cellAlt || cellFuzzy)
      legendEl.querySelector('.lg-note').insertAdjacentHTML(
        'beforebegin',
        `<ul>${cellAlt ? `<li><span class="lg-dot"><i class="lg-calt"></i></span><span>칸의 다른 견해(이설): 이설이 말하는 경계 해에 칸 높이만 한 옅은 점선(유령 구분선) — 진짜 구분선(실선)은 그대로 둡니다. 선이 이름에 닿으면 이름이 살짝 비키고, 진짜 구분선에 너무 가까우면 선 대신 그 칸 이름 밑에 옅은 점선(이설 있음). 기관 칸 · 구역 탭 · 왕조 칸에는 그 항목 자신의 이설도. 인물의 생몰 이설은 수명선 위의 작은 빈 고리. 필터의 <b>이설</b>로 켜고 끕니다</span></li>
        <li><span class="lg-dot"><i class="lg-altspot"></i></span><span>이설 조명: 칸을 누르면 그 칸의 이설 기간이 띠 바탕에 좌우 점선과 옅은 칠로 함께 보입니다(칸 기간 조명과 따로 — 같은 시기 타국 · 맨 위 괄호로는 번지지 않음). 칸 창의 <b>다른 견해</b>에 모든 견해가 나오고, 날짜 없이 근거만 적은 견해는 연표에 표시 없이 창에만</span></li>` : ''}${cellFuzzy ? `
        <li><span class="lg-dot"><i class="lg-czone"></i></span><span>연대가 모호한 칸(확실성이 추정 · 전승 · 이르면 ~ 늦으면): 그 구간의 칸 바탕에 띠의 연대 폭과 같은 무늬(추정 = 세로 줄 · 전승 = 빗금 — 이름 글자는 비켜서), 그 구간 안의 경계는 점선. 칸이 옅어지며 사라지는 미정(경계가 대시)과 다릅니다</span></li>` : ''}</ul>`
      );
    /* 시기 구분(학계) (범례 한 줄 — 자료에 시기 구분이 있을 때만, '칸' 묶음의 끝에) */
    if (periods.some(p => p.phaseSchemes))
      legendEl.querySelector('.lg-note').insertAdjacentHTML(
        'beforebegin',
        '<ul><li><span class="lg-dot"><i class="lg-phase"><b></b><b></b></i></span><span>시기 구분(학계): 후대 학계가 나라 안을 나눈 시기 — 띠 안 왕조 칸 아래 · 지도자 칸 위에 체계(출전 · 학설)마다 종이빛 얇은 줄 하나. 체계가 둘 이상이면 줄 왼쪽 끝에 작은 체계 이름. 누르면 그 기간이 조명되고 시기 창(같은 체계의 앞뒤 시기 · 체계 견주기)이 열립니다. 날짜 칸의 ‘시대 구분’과는 다른 것이며, 필터의 <b>시기</b>로 켜고 끕니다(‘빽빽하게’ · ‘조감’에서는 숨음)</span></li></ul>'
      );
    /* 지위 (범례 한 줄 — 자료에 지위가 있을 때만, '칸' 묶음의 끝에): 짙기 견본은 연표와 같은 표(HT.RANK_MIX) — 맨 왼쪽이 서열 밖 */
    if (periods.some(p => p.rankSpans))
      legendEl.querySelector('.lg-note').insertAdjacentHTML(
        'beforebegin',
        `<ul><li><span class="lg-ranks" style="--c:#abb3c9">${HT.RANK_MIX.map(m => `<i style="--mix:${m}%"></i>`).join('')}</span><span>지위: 정권의 지위가 바뀐 나라는 띠 안 지도자 칸 위(시기 구분이 있으면 그 아래)에 얇은 지위 단 — 서열이 높을수록 나라 색이 짙습니다(지위 사전의 서열을 네 묶음으로 나눠, 같은 지위는 어느 나라에서나 같은 짙기 · 맨 왼쪽 견본은 서열 밖). 지위가 하나뿐이면 책갈피 탭의 이름 뒤에 작은 딱지. 누르면 그 기간이 조명되고 지위 창(서열 · 지위 변천의 승격 ▲ · 격하 ▼ · 그 기간의 지도자)이 열립니다. 필터의 <b>지위</b>로 켜고 끕니다(‘빽빽하게’ · ‘조감’에서는 단이 숨음)</span></li></ul>`
      );
    /* 단체 단 (범례 세 줄까지 — 자료에 집권 · 연정 · 실권 칸이 있을 때만, '칸' 묶음의 끝에 · 설계 7-8 결정 1 · 2 + 덧판 x1 A · x3 C):
       띠 위에는 '집권' · '연정' · '실권' 딱지 글이 없으므로(감독 원칙 — 모양 · 색으로 구분) 칠과 점의 뜻을 여기에 적음. 견본은 연표와 같은 값(Timeline.groupCellSample) */
    if (HT.groupStrip && HT.Timeline && HT.Timeline.groupCellSample) {
      let hasPower = false, hasTwo = false, hasReal = false;
      for (const p of periods) {
        if (!p.groupLinks) continue;
        const s = HT.groupStrip(p);
        if (s.power.length) hasPower = true;
        if (s.real.length) hasReal = true;
        if (s.power.concat(s.real).some(c => (c.n || 1) > 1 || c.solo)) hasTwo = true;
      }
      const li = (kind, text) => `<li><span class="lg-dot">${HT.Timeline.groupCellSample(kind)}</span><span>${text}</span></li>`;
      if (hasPower || hasReal)
        legendEl.querySelector('.lg-note').insertAdjacentHTML(
          'beforebegin',
          `<ul>${hasPower ? li('power', '집권한 단체: 띠 안 지도자 칸 위의 얇은 칸은 그때 집권한 단체(단체 빛깔). 누르면 단체 창이 열리고, 필터의 <b>단체</b>로 켜고 끕니다(‘빽빽하게’ · ‘조감’에서는 숨음)') : ''}${
            hasTwo ? li('coal', '함께 집권: 여러 단체가 함께 집권한 칸은 위아래 두 빛깔 — 색 점은 함께한 단체 수만큼(칸이 좁으면 점 없이 두 빛깔만)') : ''}${
            hasReal ? li('real', '실권을 쥔 집단: 짙게 칠한 칸(집권 칸 아래 줄). 그 기간이 제 기간의 절반을 넘는 지도자는 이름이 옅게 적힙니다') : ''}</ul>`
        );
    }
    /* 가문 (범례 한 줄 — '칸' 묶음의 끝에) */
    legendEl.querySelector('.lg-note').insertAdjacentHTML(
      'beforebegin',
      '<ul><li><span class="lg-dot"><i style="border-radius:4px;width:22px;height:11px;background:linear-gradient(color-mix(in srgb,#a0bcc5 72%,var(--paper-ink)),color-mix(in srgb,#a0bcc5 72%,var(--paper-ink))) 3px calc(100% - 2px)/16px 2px no-repeat,var(--paper);border:1px solid color-mix(in srgb,#bba395 45%,transparent)"></i></span><span>가문: 필터의 <b>가문</b>을 켜면 지도자 칸 아래쪽에 그 지도자의 가문 색 줄이 그어집니다(같은 가문이 이어지는 동안 한 줄 · 가문을 적지 않은 지도자는 그 칸이 시작한 해의 왕조의 가문, 그것도 없으면 나라의 국성으로). 상세의 가문 배지나 검색에서 가문을 고르면 가문 창(본가 · 분가 · 국성으로 삼은 나라 · 구성원)이 열리고, 그동안 그 가문의 칸이 진해집니다</span></li></ul>'
    );
    /* 칸의 미정 (범례 한 줄 — '칸' 묶음의 끝에) */
    legendEl.querySelector('.lg-note').insertAdjacentHTML(
      'beforebegin',
      '<ul><li><span class="lg-dot"><i style="border-radius:4px;width:22px;height:11px;background:color-mix(in srgb,#bba395 12%,var(--paper));border:1px solid color-mix(in srgb,#bba395 45%,transparent);border-right-style:dashed;-webkit-mask-image:linear-gradient(90deg,#000 40%,transparent);mask-image:linear-gradient(90deg,#000 40%,transparent)"></i></span><span>칸의 미정: 지도자·내각·연호·도읍·지위·시기 칸과 상국 띠의 속국 이름표, 인물의 활동 막대(활동 기록 · 활동 시기)의 시작이나 끝을 모르면("미정") 그쪽 끝이 칸 안에서 옅어지며 사라지고 칸 사이 구분선이 점선이 됩니다. 배치용 연도가 없으면 앞 칸의 끝이나 다음 칸의 시작에 맞춰 놓이고(활동 기록은 활동 시기에), 도읍 노선도 카드에서는 그 역 사이 본선이 점선입니다</span></li></ul>'
    );
    /* 조약 (범례 두 줄 — '사건' 묶음의 끝에) */
    const cellHead = [...legendEl.querySelectorAll('h4')].find(h => h.textContent === '칸');
    if (cellHead)
      cellHead.insertAdjacentHTML(
        'beforebegin',
        `<ul>${dot('treaty', '조약(조약 규격을 적은 사건) — 마름모 인장: 제 줄은 채운 마름모, 다른 당사국의 줄은 속 빈 마름모. 묶음 알약에 묶이면 모양이 가려지지만, 알약을 눌러 여는 목록에는 마름모로 나옵니다')}${line('rail treaty', '기간이 있는 조약(체결 ~ 실효) — 겹줄 가는 선. 발효가 체결과 다르면 선 위에 작은 마름모 눈금')}</ul>`
      );
  }
  function setLegend(on) {
    state.ui.legend = !!on;
    HT.store.set(K.ui, state.ui);
    $('#legendBtn').setAttribute('aria-pressed', String(!!on));
    legendEl.hidden = !on;
    if (on) renderLegend();
  }
  $('#legendBtn').addEventListener('click', () => setLegend(legendEl.hidden));
  legendEl.addEventListener('click', e => {
    if (e.target.closest('[data-legend-close]')) setLegend(false);
  });
  for (const [id, key] of Object.entries(SHOW_TOGGLES)) {
    $('#' + id).addEventListener('change', e => {
      state.ui.show = Object.assign({}, state.ui.show, { [key]: e.target.checked });
      HT.store.set(K.ui, state.ui);
      timeline.setShow({ [key]: e.target.checked });
    });
  }
  $('#lensSelect').addEventListener('change', e => {
    state.ui.lens = e.target.value;
    HT.store.set(K.ui, state.ui);
    timeline.setLens(state.ui.lens);
    state.detailLens = null;
    if (state.selected) openDetail(state.selected);
  });
  $('#altToggle').addEventListener('change', e => {
    state.ui.showAlt = e.target.checked;
    HT.store.set(K.ui, state.ui);
    timeline.setShowAlt(e.target.checked);
  });
  $('#yearBtn').addEventListener('click', () => {
    if (state.yearPanel) return closeYearPanel();
    // 화면 가운데가 든 해 — 가까이 확대했으면 그 달·그날
    openYearPanel((timeline.view.start + timeline.view.end) / 2, null, { prec: panelPrec() });
    HT.toast('연표의 빈 곳을 클릭하면 그 자리로 기준선이 옮겨집니다.');
  });
  $('#measureBtn').addEventListener('click', e => {
    const on = e.currentTarget.getAttribute('aria-pressed') !== 'true';
    e.currentTarget.setAttribute('aria-pressed', String(on));
    timeline.setMeasureMode(on);
    if (on) HT.toast('연표 위에서 좌우로 드래그하면 기간을 재 줍니다. 가까이 확대하면 개월·일까지 셉니다.');
    else showMeasure(null);
  });
  if ($('#addEventBtn')) $('#addEventBtn').addEventListener('click', () => openEditor(null));
  $('#dlcBtn').addEventListener('click', () => {
    if (maker) return maker.openPacks(); // 메이커: 켜고 끔이 뜻이 없어 불러온 팩 탭으로 (설계 3-8)
    state.installLog = [];
    openDlc();
  });

  document.addEventListener('keydown', e => {
    if (document.querySelector('dialog[open]') || /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) || inMakerWin()) return;
    if (e.key === '/') {
      e.preventDefault();
      searchInput.focus();
    } else if (e.key === 'Escape' && state.selected) closeDetail();
  });

  /** 설치된 DLC · 켜고 끔을 저장소에서 다시 읽어 화면을 새로 짓습니다 (메이커의 반영 뒤 · 다른 탭에서 바뀌었을 때) */
  function reloadPacks() {
    state.packState = HT.store.get(K.packState, {});
    loadPacks();
    refresh();
    if (dlcDialog.open) renderDlc();
  }
  // 다른 탭(메이커의 반영 · 연표의 DLC 관리)에서 DLC가 바뀌면 자동 반영. 메이커는 다른 메이커 탭이 고친 작업본도 다시 읽습니다
  window.addEventListener('storage', e => {
    if (maker && e.key === K.draft) return maker.reloadDraft();
    if (e.key !== K.installed && e.key !== K.packState) return;
    reloadPacks();
    HT.toast('DLC 변경 사항을 불러왔습니다.');
  });

  /* ---------- 지도 (보류 중인 부품) ----------
   * 지도는 유지보수를 위해 지도/ 폴더로 떼어 두었습니다. 지도/js/viewer-map.js가 함께 읽히면 HT.mapPlugin이 생기고, 그때만 단추·창이 붙습니다 */
  mapHooks = HT.mapPlugin ? HT.mapPlugin({ $, state, K, timeline, esc, precFor, isEnabled, openDetail, closeDetail }) : null;

  /* ---------- 메이커 부품 (dlc-maker.html에서만) ----------
   * js/maker.js가 함께 읽히고 <body data-app="make">일 때만 HT.makerPlugin을 부릅니다 — 메이커 줄 · 고치는 DLC(작업본) · 반영 · 파일로를 맡고,
   * 이 파일의 저장 길(편집기 · 삭제/숨기기 · 되돌리기 · 문서)은 부품을 거쳐 작업본을 고칩니다. 부품이 없으면(연표) 그 길은 모두 거절됩니다 */
  maker = MAKE
    ? HT.makerPlugin({
        $, state, K, timeline, esc, isEnabled, packById, refresh, reloadPacks, openDetail, closeDetail, openEditor, openEditorFor, leaveEditor, closeEditor, editorDirty, syncEditor, refillEditor, openWiki, syncInset,
        openKin, kinPlan, kinPick, kinPaneMenu, // 승계표 · 세계표 열기 (편집 창 머리의 계보 · 보기 메뉴)
        /* 작업실 틀(js/maker-shell.js)이 쓰는 명령 — 메뉴 줄 · 도구 줄 · 단축키가 연표의 것을 그대로 부르게 */
        cmd: {
          keys: KEYS, addKinds, addKeyOf, showMenu, hideMenu, setZen,
          openAdd: kind => openEditor(null, kind),
          closeWiki,
          deleteItem: uid => state.model.byUid.has(uid) && deleteItem(state.model.byUid.get(uid)),
          installFiles: (files, opts) => installFiles(files, opts),
        },
        onSelection: uids => viewsUi && viewsUi.onSelection(uids), // 여러 개 고름이 바뀜 → 집합 보기의 '고른 나라' 막대
      })
    : null;
  if (maker) document.body.classList.add('is-editing');
  viewsUi = HT.viewsUi ? HT.viewsUi.mount({ state, K, timeline, maker, openDetail }) : null; // 집합 보기 (js/views-ui.js)

  /* ---------- 시작 ---------- */
  loadPacks();
  $('#importanceSelect').value = String(state.ui.minImportance);
  $('#densitySelect').value = String(state.ui.density || 0);
  timeline.setDensity(state.ui.density || 0);
  $('#birdShapeSelect').value = state.ui.birdShape || 'a';
  $('#birdAutoToggle').checked = !!state.ui.birdAuto;
  $('#altToggle').checked = state.ui.showAlt !== false;
  for (const [id, key] of Object.entries(SHOW_TOGGLES)) $('#' + id).checked = !!((state.ui.show || {})[key] ?? HT.SHOW_DEFAULTS[key]); // 적힌 값이 없으면 표의 기본값 (기본 끔인 표시가 체크만 켜져 보이지 않게)
  /* 글자 폭은 배치할 때 화면 글꼴로 재서 기억하므로(js/timeline.js textWidth), 내장 프리텐다드 세 굵기와 한자 대체 글꼴(조선굵은명조)이 열린 뒤 처음 그립니다.
     글꼴을 못 열거나 늦으면 1.2초 뒤 그대로 그립니다 (그 뒤에 열리면 timeline.js가 잰 폭을 버려 다음 배치부터 맞음) */
  const fontsReady =
    document.fonts && document.fonts.load
      ? Promise.race([Promise.all([document.fonts.load('400 12px Pretendard', '가A1'), document.fonts.load('600 12px Pretendard', '가A1'), document.fonts.load('700 20px Pretendard', '가A1'), document.fonts.load('700 12px ChosunKm', '漢字')]), new Promise(done => setTimeout(done, 1200))]).catch(() => {})
      : Promise.resolve();
  fontsReady.then(() => {
    const saved = HT.store.get(K.view, null);
    const hasSaved = !!(saved && isFinite(saved.start) && isFinite(saved.end));
    if (hasSaved) timeline.setView(saved.start, saved.end); // 자료를 넣기 전에 먼저 — 첫 화면이 처음부터 이 범위에 맞는 줄 높이로 지어집니다 (지은 뒤에 줄이 접히며 흐르지 않게)
    refresh();
    setLegend(!!state.ui.legend);
    if (hasSaved) timeline.setView(saved.start, saved.end); // 자료의 범위에 맞춰 한 번 더
    else timeline.fitAll(false);
    if (mapHooks) mapHooks.start();
    if (maker) maker.start();
    if (moved) HT.toast(moved.ok ? `예전의 "내 수정"(추가 ${moved.counts.items} · 고침 ${moved.counts.overrides} · 숨김 ${moved.counts.hidden} · 문서 ${moved.counts.wiki})을 DLC «${moved.name}»(으)로 옮겼습니다.${moved.counts.waiting ? ` 그 가운데 지금 설치돼 있지 않은 DLC의 것 ${moved.counts.waiting}개는 그 DLC를 다시 설치하면 얹힙니다.` : ''} ${maker ? 'DLC 관리에서 켜고 끄고, [이 DLC 고치기]로 고칠 수 있습니다.' : 'DLC 관리에서 켜고 끌 수 있습니다.'}` : moved.message, moved.ok ? 'ok' : 'error');
  });
})();
