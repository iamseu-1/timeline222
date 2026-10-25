/* 역사 연표 — 움직임 계측 (감독용 도구)
 * 느리게 보기(1× · 0.25× · 0.1×)와 간이 점수표. 메뉴(⋯)의 "움직임 계측"이나 주소의 ?motion=1 로 창을 열 때에만 불러옵니다 — 평소에는 비용 0.
 * 점수표는 "마지막 손짓 하나"(누르기 · 휠 굴리기 · 키)를 손을 뗀 뒤 1.5초 동안 지켜본 결과입니다 (합격 숫자: docs/움직임-개선안.md 7절).
 *   움직임 수        그 손짓으로 시작된 CSS 전환 + 키프레임 + 스크립트(WAAPI) 애니메이션
 *   끝나는 시각      손을 뗀 때부터 잰 끝(시작 + 지연 + 길이)을 20ms 단위로 묶어 서로 다른 것의 수 — "따로 도착"의 정도
 *   길이 · 곡선 종류  서로 다른 길이와 곡선의 수
 *   다 끝난 때       마지막 움직임이 끝난 시각 — 손을 뗀 뒤 앱이 혼자 움직인 시간
 *   누른 것이 밀린 거리  누른 요소가 다 끝난 뒤 위아래로 옮겨진 거리
 *   다른 트랙 출렁임   높이가 결국 그대로인 트랙이 도중에 가장 크게 벗어난 높이
 * 시험용: await HT.motionProbe.measure(() => timeline.toggleFold(id), { target: el, label: '트랙 접기' }) → 같은 결과 객체 (창을 열지 않아도 됨) */
(function () {
  'use strict';
  const HT = window.HT;
  if (!HT || !HT.motion || HT.motionProbe) return;
  const M = HT.motion;
  const WINDOW = 1500; // 손을 뗀 뒤 지켜보는 길이(ms, 1배 기준 — 느리게 보기에서는 그만큼 길어짐)
  const WHEEL_IDLE = 180; // 휠이 이만큼 조용하면 "굴리기 끝"
  const RATES = [1, 0.25, 0.1];
  const esc = HT.escapeHtml;

  /* ---------- 지켜보기 ---------- */
  let act = null; // 지켜보는 중인 손짓
  let panel = null;
  let listening = false;
  const waiters = [];

  const hostOf = t => (t && t.closest ? t.closest('[data-uid], [data-fold], [data-fold-people], [data-fold-members], [data-fold-hangs], [data-cluster], [data-hint-go], button, .chip, label, a') || t : null);
  /** 다시 지어져 요소가 바뀌어도 같은 것을 찾을 수 있게: 고유 키가 있으면 그 키로 */
  const finderOf = el => {
    if (!el || !el.getAttribute) return null;
    if (el.id) return () => document.getElementById(el.id);
    const cls = el.classList && el.classList[0] ? `.${CSS.escape(el.classList[0])}` : '';
    const q = sel => () => (cls && document.querySelector(cls + sel)) || document.querySelector(sel);
    for (const name of ['data-uid', 'data-fold', 'data-fold-people', 'data-fold-members', 'data-fold-hangs', 'data-cluster']) {
      if (el.hasAttribute(name)) return q(`[${name}="${CSS.escape(el.getAttribute(name))}"]`);
    }
    const data = [...el.attributes].filter(a => a.name.startsWith('data-')); // 필터 칩(data-group · data-id)처럼 키가 따로 없는 것
    return data.length ? q(data.map(a => `[${a.name}="${CSS.escape(a.value)}"]`).join('')) : null;
  };
  const trackHeights = () => {
    const m = new Map();
    document.querySelectorAll('.tl-track[data-track]').forEach(el => m.set(el.dataset.track, el.getBoundingClientRect().height));
    return m;
  };

  function begin(kind, target, label) {
    drop();
    for (const w of waiters.splice(0)) w(null); // 새 손짓이 끼어들면 앞의 시험은 결과 없이 끝납니다
    const host = hostOf(target);
    const seen = new WeakSet();
    for (const a of document.getAnimations()) seen.add(a); // 앞선 손짓이 남긴 것은 세지 않습니다
    const tracks = new Map();
    for (const [id, h] of trackHeights()) tracks.set(id, { h0: h, last: h, peak: 0 });
    act = { kind, label: label || '', host, find: finderOf(host), top0: host && host.isConnected ? host.getBoundingClientRect().top : null, seen, tracks, recs: [], t0: performance.now(), released: null, rate: M.rate, mixed: false, hidden: document.visibilityState === 'hidden', raf: 0, iv: 0, timer: 0 };
    const tick = () => {
      if (!act) return;
      sample();
      act.raf = requestAnimationFrame(tick);
    };
    act.raf = requestAnimationFrame(tick);
    act.iv = setInterval(sample, 100); // 그리기가 멈춘 창(숨은 탭)에서도 띄엄띄엄 봅니다
    act.timer = setTimeout(release, 15000); // 손을 뗀 알림이 끝내 오지 않아도 지켜보기가 남지 않게
    render();
  }

  /** 손을 뗀 순간 — 여기서부터 끝나는 시각을 잽니다. 휠은 굴릴 때마다 다시 불러 "마지막으로 굴린 때"가 됩니다 */
  function release() {
    if (!act) return;
    act.released = performance.now();
    setTimeout(sample, 0); // 손짓을 처리한 직후의 모습(새로 지어 부푼 높이 등)을 놓치지 않게
    clearTimeout(act.timer);
    act.timer = setTimeout(finish, WINDOW / M.rate + 40);
  }

  function drop() {
    if (!act) return;
    cancelAnimationFrame(act.raf);
    clearInterval(act.iv);
    clearTimeout(act.timer);
    act = null;
  }

  function sample() {
    if (!act) return;
    const now = performance.now();
    if (M.rate !== act.rate) act.mixed = true;
    if (document.visibilityState === 'hidden') act.hidden = true;
    for (const a of document.getAnimations()) {
      if (act.seen.has(a)) continue;
      act.seen.add(a);
      const eff = a.effect;
      if (!eff || !eff.getComputedTiming || (panel && eff.target && panel.contains(eff.target))) continue;
      const tm = eff.getComputedTiming();
      let curve = tm.easing || 'linear';
      if (curve === 'linear' && eff.getKeyframes) {
        const kf = eff.getKeyframes()[0];
        if (kf && kf.easing) curve = kf.easing; // 키프레임 애니메이션의 곡선은 키프레임 쪽에 있습니다
      }
      const type = typeof CSSTransition !== 'undefined' && a instanceof CSSTransition ? 'transition' : typeof CSSAnimation !== 'undefined' && a instanceof CSSAnimation ? 'keyframes' : 'script';
      const left = tm.endTime - (a.currentTime || 0); // 끝까지 남은 길이(1배 기준)
      act.recs.push({ type, prop: a.transitionProperty || a.animationName || '', dur: Math.round(typeof tm.duration === 'number' ? tm.duration : 0), curve: curve.replace(/\s+/g, ''), seenAt: now, endAt: isFinite(left) ? now + left / M.rate : Infinity });
    }
    for (const [id, h] of trackHeights()) {
      const t = act.tracks.get(id);
      if (!t) continue;
      t.last = h;
      t.peak = Math.max(t.peak, Math.abs(h - t.h0));
    }
  }

  function finish() {
    if (!act) return;
    sample();
    const a = act;
    const rel = a.released == null ? a.t0 : a.released;
    const finite = a.recs.filter(r => isFinite(r.endAt));
    const ends = [...new Set(finite.map(r => Math.round(((r.endAt - rel) * a.rate) / 20) * 20).filter(ms => ms > 0))].sort((x, y) => x - y);
    const durs = [...new Set(a.recs.map(r => r.dur))].sort((x, y) => x - y);
    const curves = [...new Set(a.recs.map(r => r.curve))];
    let wobble = 0;
    let wobbleTracks = 0;
    for (const t of a.tracks.values()) {
      if (Math.abs(t.last - t.h0) >= 0.5 || t.peak < 0.5) continue; // 높이가 결국 달라진 트랙은 "움직여야 했던" 트랙
      wobbleTracks++;
      wobble = Math.max(wobble, t.peak);
    }
    const el = a.host && a.host.isConnected ? a.host : a.find ? a.find() : null;
    const result = {
      kind: a.kind,
      label: a.label,
      rate: a.rate,
      rough: a.hidden || a.mixed, // 창이 숨어 있었거나 도중에 빠르기를 바꿈 — 값이 거칠 수 있음
      count: a.recs.length,
      transitions: a.recs.filter(r => r.type === 'transition').length,
      keyframes: a.recs.filter(r => r.type === 'keyframes').length,
      scripted: a.recs.filter(r => r.type === 'script').length,
      during: a.recs.filter(r => r.seenAt < rel).length, // 손에 잡힌 동안(끌기 · 굴리기) 시작된 것
      held: Math.round(rel - a.t0),
      endless: a.recs.length - finite.length,
      ends,
      durations: durs,
      curves,
      tail: ends.length ? ends[ends.length - 1] : 0,
      moved: el && a.top0 != null ? Math.round((el.getBoundingClientRect().top - a.top0) * 10) / 10 : null,
      wobble: Math.round(wobble * 10) / 10,
      wobbleTracks,
    };
    drop();
    probe.last = result;
    render();
    for (const w of waiters.splice(0)) w(result);
  }

  /* ---------- 손짓 듣기 (창이 열려 있는 동안만) ---------- */
  const inPanel = e => panel && e.target && e.target.closest && e.target.closest('.motion-panel');
  const onDown = e => {
    if (inPanel(e) || (e.pointerType === 'mouse' && e.button !== 0)) return;
    begin('press', e.target);
  };
  const onUp = e => {
    if (!act || act.kind !== 'press' || act.released != null || inPanel(e)) return;
    if (performance.now() - act.t0 > 250) act.kind = 'drag';
    release();
  };
  const onWheel = e => {
    if (inPanel(e)) return;
    if (!act || act.kind !== 'wheel' || (act.released != null && performance.now() - act.released > WHEEL_IDLE)) begin('wheel', e.target);
    release();
  };
  const onKey = e => {
    if (inPanel(e) || e.repeat || ['Shift', 'Control', 'Alt', 'Meta'].includes(e.key)) return;
    begin('key', null, e.key === ' ' ? 'Space' : e.key);
    release();
  };
  const onStart = () => sample(); // 짧은 움직임도 놓치지 않게: 시작 알림이 오면 바로 훑습니다
  function listen(on) {
    if (on === listening) return;
    listening = on;
    const fn = on ? 'addEventListener' : 'removeEventListener';
    window[fn]('pointerdown', onDown, true);
    window[fn]('pointerup', onUp, true);
    window[fn]('pointercancel', onUp, true);
    window[fn]('wheel', onWheel, { capture: true, passive: true });
    window[fn]('keydown', onKey, true);
    document[fn]('transitionrun', onStart, true);
    document[fn]('animationstart', onStart, true);
    if (!on) drop();
  }

  /* ---------- 창 ---------- */
  const KIND = { press: '누르기', drag: '끌기', wheel: '휠 굴리기', key: '키', call: '시험' };
  const CSS_TEXT = `
.motion-panel { position: absolute; left: calc(12px + var(--safe-left)); bottom: 16px; z-index: 28; width: 224px; padding: 8px 12px 12px; border-radius: 16px; background: var(--glass); backdrop-filter: blur(20px) saturate(1.6); -webkit-backdrop-filter: blur(20px) saturate(1.6); box-shadow: var(--shadow-sm), 0 0 0 1px var(--line); color: var(--text); font-size: 12px; line-height: 1.45; user-select: none; -webkit-user-select: none; animation: mp-in var(--t-in) var(--ease); }
.stage:has(.legend:not([hidden])) .motion-panel:not(.is-moved) { left: 324px; }
.motion-panel.is-leaving { opacity: 0; transition: opacity var(--t-out) var(--ease); pointer-events: none; }
@keyframes mp-in { from { opacity: 0; transform: translateY(6px); } }
.mp-head { display: flex; align-items: center; gap: 6px; height: 28px; margin-bottom: 4px; cursor: grab; touch-action: none; }
.mp-head:active { cursor: grabbing; }
.mp-head b { flex: 1; font-size: 12.5px; font-weight: 650; letter-spacing: -.01em; }
.mp-x { width: 24px; height: 24px; padding: 0; border: 0; border-radius: 8px; background: none; color: var(--text-3); font-size: 12px; cursor: pointer; transition: background-color var(--t-micro) var(--ease), color var(--t-micro) var(--ease); }
.mp-x:hover { background: var(--surface-2); color: var(--text); }
.mp-speed { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2px; padding: 2px; border-radius: 10px; background: color-mix(in srgb, var(--surface-2) 80%, transparent); }
.mp-speed button { height: 26px; padding: 0; border: 0; border-radius: 8px; background: none; color: var(--text-2); font: inherit; font-weight: 600; font-variant-numeric: tabular-nums; cursor: pointer; transition: background-color var(--t-micro) var(--ease), color var(--t-micro) var(--ease), box-shadow var(--t-micro) var(--ease); }
.mp-speed button:hover { color: var(--text); }
.mp-speed button[aria-pressed="true"] { background: var(--surface); color: var(--accent); box-shadow: var(--shadow-sm); }
.mp-speed button:focus-visible, .mp-x:focus-visible { outline: none; box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 35%, transparent); }
.mp-act { display: flex; align-items: baseline; gap: 6px; margin: 10px 0 4px; color: var(--text-3); font-size: 11.5px; }
.mp-act b { color: var(--text); font-weight: 600; }
.mp-list { margin: 0; }
.mp-list div { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; padding: 2px 0; }
.mp-list dt { color: var(--text-2); white-space: nowrap; }
.mp-list dd { margin: 0; font-weight: 650; font-variant-numeric: tabular-nums; white-space: nowrap; }
.mp-list dd small { margin-left: 5px; font-weight: 500; font-size: 10.5px; color: var(--text-3); }
.mp-list dd.is-over { color: var(--danger); }
.mp-list dd.is-ok { color: var(--ok); }
.mp-note { margin: 6px 0 0; font-size: 10.5px; line-height: 1.4; color: var(--text-3); word-break: keep-all; font-variant-numeric: tabular-nums; }
@media (max-width: 720px) {
  .motion-panel { left: 8px; bottom: calc(8px + var(--safe-bottom)); }
  .stage:has(.legend:not([hidden])) .motion-panel:not(.is-moved) { left: 8px; top: 8px; bottom: auto; }
}
@media (prefers-reduced-motion: reduce) { .motion-panel { animation: none; } }
`;

  function build() {
    if (!document.getElementById('motionProbeCss')) {
      const st = document.createElement('style');
      st.id = 'motionProbeCss';
      st.textContent = CSS_TEXT;
      document.head.appendChild(st);
    }
    const el = document.createElement('section');
    el.className = 'motion-panel';
    el.setAttribute('aria-label', '움직임 계측');
    el.innerHTML =
      `<div class="mp-head" title="끌어서 옮기기"><b>움직임 계측</b><button type="button" class="mp-x" data-mp-close aria-label="닫기" title="닫기">✕</button></div>` +
      `<div class="mp-speed" role="group" aria-label="빠르기 — 느리게 보기">${RATES.map(r => `<button type="button" data-mp-rate="${r}" title="${r === 1 ? '보통 빠르기' : `${r}배로 느리게 보기`}">${r}×</button>`).join('')}</div>` +
      `<p class="mp-act"></p><dl class="mp-list"></dl><p class="mp-note"></p>`;
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-mp-rate]');
      if (b) {
        M.rate = Number(b.dataset.mpRate);
        return render();
      }
      if (e.target.closest('[data-mp-close]')) probe.close();
    });
    /* 머리를 끌어 옮기기 — 가리고 싶지 않은 것이 있으면 비켜 둘 수 있게 */
    const head = el.querySelector('.mp-head');
    let grab = null;
    head.addEventListener('pointerdown', e => {
      if (e.target.closest('button')) return;
      const r = el.getBoundingClientRect();
      grab = { dx: e.clientX - r.left, dy: e.clientY - r.top };
      try {
        head.setPointerCapture(e.pointerId);
      } catch (err) {
        /* 합성 이벤트 */
      }
    });
    head.addEventListener('pointermove', e => {
      if (!grab) return;
      const box = (el.offsetParent || document.body).getBoundingClientRect();
      el.classList.add('is-moved');
      el.style.left = `${Math.round(HT.clamp(e.clientX - grab.dx - box.left, 4, box.width - el.offsetWidth - 4))}px`;
      el.style.top = `${Math.round(HT.clamp(e.clientY - grab.dy - box.top, 4, box.height - el.offsetHeight - 4))}px`;
      el.style.bottom = 'auto';
    });
    const end = () => (grab = null);
    head.addEventListener('pointerup', end);
    head.addEventListener('pointercancel', end);
    return el;
  }

  function render() {
    if (!panel) return;
    panel.querySelectorAll('[data-mp-rate]').forEach(b => b.setAttribute('aria-pressed', String(Number(b.dataset.mpRate) === M.rate)));
    const actEl = panel.querySelector('.mp-act');
    const list = panel.querySelector('.mp-list');
    const note = panel.querySelector('.mp-note');
    const r = probe.last;
    if (act) actEl.innerHTML = `마지막 손짓 <b>${esc(KIND[act.kind] || act.kind)}${act.label ? ` · ${esc(act.label)}` : ''}</b> 재는 중…`;
    else if (r) actEl.innerHTML = `마지막 손짓 <b>${esc(KIND[r.kind] || r.kind)}${r.label ? ` · ${esc(r.label)}` : ''}</b>${r.rate !== 1 ? ` ${r.rate}×` : ''}`;
    else actEl.innerHTML = '연표에서 누르거나 굴려 보세요';
    if (!r) {
      list.innerHTML = '';
      note.textContent = '';
      return;
    }
    const row = (name, value, { goal = '', over = null, title = '' } = {}) =>
      `<div title="${esc(title)}"><dt>${esc(name)}</dt><dd class="${over == null ? '' : over ? 'is-over' : 'is-ok'}">${esc(value)}${goal ? `<small>${esc(goal)}</small>` : ''}</dd></div>`;
    const sec = ms => `${(ms / 1000).toFixed(2)}초`;
    list.innerHTML =
      row('움직임 수', `${r.count}`, { title: `CSS 전환 ${r.transitions} · 키프레임 ${r.keyframes} · 스크립트 ${r.scripted}${r.during ? ` · 손에 잡힌 동안 시작 ${r.during}` : ''}${r.endless ? ` · 끝없이 도는 것 ${r.endless}` : ''}` }) +
      row('끝나는 시각', `${r.ends.length}`, { goal: '목표 2 이하', over: r.ends.length > 2, title: r.ends.map(ms => `${ms}ms`).join(' · ') }) +
      row('길이 종류', `${r.durations.length}`, { title: r.durations.map(ms => `${ms}ms`).join(' · ') }) +
      row('곡선 종류', `${r.curves.length}`, { title: r.curves.join('\n') }) +
      row('다 끝난 때', r.count ? sec(r.tail) : '—', { goal: '목표 1초 안', over: r.count ? r.tail >= 1000 : null }) +
      row('누른 것이 밀린 거리', r.moved == null ? '—' : `${r.moved}px`, { goal: '목표 0', over: r.moved == null ? null : Math.abs(r.moved) >= 0.5 }) +
      row('다른 트랙 출렁임', `${r.wobble}px`, { goal: '목표 0', over: r.wobble >= 0.5, title: r.wobbleTracks ? `높이가 결국 그대로인데 도중에 출렁인 트랙 ${r.wobbleTracks}개` : '' });
    const bits = [];
    if (r.ends.length) bits.push(`끝 ${r.ends.slice(0, 6).join(' · ')}ms${r.ends.length > 6 ? ` 외 ${r.ends.length - 6}` : ''}`);
    if (r.during) bits.push(`손에 잡힌 동안 시작 ${r.during}`);
    if (r.endless) bits.push(`끝없이 도는 것 ${r.endless}`);
    if (r.rough) bits.push('창이 숨어 있었거나 도중에 빠르기를 바꿔 값이 거칠 수 있음');
    note.textContent = bits.join(' — ');
  }

  const probe = (HT.motionProbe = {
    last: null,
    isOpen: () => !!panel,
    open() {
      if (panel) return;
      panel = build();
      (document.getElementById('stage') || document.body).appendChild(panel);
      listen(true);
      render();
    },
    close() {
      if (!panel) return;
      const el = panel;
      panel = null;
      listen(false);
      if (M.rate !== 1) M.rate = 1; // 창을 닫으면 보통 빠르기로 — 느린 채로 남지 않게
      el.classList.add('is-leaving');
      M.later(M.T.out, () => el.remove());
    },
    toggle(on = !panel) {
      if (on) probe.open();
      else probe.close();
    },
    /** 공개 API로 일으킨 동작을 잽니다 (창을 열지 않아도 됨). target은 "누른 것" 구실을 할 요소 */
    measure(fn, { target = null, label = '' } = {}) {
      return new Promise(resolve => {
        begin('call', target, label);
        waiters.push(resolve);
        try {
          fn();
        } finally {
          release();
        }
      });
    },
  });
})();
