/* 역사 연표 — 플랫폼 경계
 *
 * 브라우저 · PWA · Windows 앱(Tauri)에서 서로 달라지는 것만 이 파일에 모읍니다.
 *   saveFile / openFiles   파일 저장·열기
 *   print                  인쇄
 *   openPage / openExternal 다른 화면(메이커 → 연표 — 한 방향)·외부 링크 열기
 *   trapBack / releaseBack 휴대폰 브라우저 뒤로가기(패널·대화상자 닫기)
 * 그리고 Windows 앱에서는 HT.store(localStorage)를 파일로 거울 저장하고,
 * PWA의 "연결 프로그램"(launchQueue)으로 받은 파일을 'ht:files' 이벤트로 넘깁니다.
 *
 * core.js 뒤, timeline.js·viewer.js·maker.js 앞에 읽습니다.
 */
(() => {
  const HT = (window.HT = window.HT || {});

  /* ---------- 환경 판별 ---------- */
  const T = window.__TAURI__ || null;
  const standalone = (window.matchMedia && matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  const mobileUA = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent));
  const name = T ? 'tauri' : standalone ? 'pwa' : 'web';
  const mobile = mobileUA; // 휴대폰 브라우저의 이동 · 뒤로가기 · 화면 배치는 그대로
  /** 창(탭)이 하나뿐인 환경 — 다른 화면은 같은 창에서 이동합니다(기기의 뒤로 단추로 돌아옴).
      PC에 설치한 PWA는 넣지 않습니다: 새 앱 창을 열 수 있고, 연표 미리보기에는 메이커로 돌아가는 길이 없으므로(일방통행) 같은 창으로 옮기면 메이커로 돌아올 수 없습니다 */
  const singleWindow = mobile;

  const baseName = p => String(p).split(/[\\/]/).pop();
  const extOf = f => ((f.match(/\.(\w+)$/) || [])[1] || '').toLowerCase();
  const acceptToExts = accept =>
    String(accept || '')
      .split(',')
      .map(s => s.trim())
      .filter(s => s.startsWith('.'))
      .map(s => s.slice(1).toLowerCase());

  /* ---------- 기본(브라우저) 구현 ---------- */
  const web = {
    async saveFile(filename, blob) {
      const url = URL.createObjectURL(blob);
      const a = Object.assign(document.createElement('a'), { href: url, download: filename });
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1500);
      return true;
    },
    openFiles(accept, multiple = false) {
      return new Promise(resolve => {
        // 휴대폰 파일 고르기는 확장자를 모를 수 있어 전용 형식과 일반 바이트 형식도 허용 — 받은 뒤 확장자 · 내용 검사
        const acc = mobile && /\.htpack/i.test(String(accept || '')) ? `${accept},application/x-htpack,application/octet-stream` : accept;
        const input = Object.assign(document.createElement('input'), { type: 'file', accept: acc, multiple });
        input.addEventListener('change', () => resolve([...input.files]));
        input.addEventListener('cancel', () => resolve([])); // 고르지 않고 닫음 (cancel을 알리는 브라우저)
        // PC에서 취소하면 change가 오지 않으므로 창이 다시 활성화될 때 빈 목록으로 끝냅니다
        if (!mobile) window.addEventListener('focus', () => setTimeout(() => resolve([...input.files]), 800), { once: true });
        input.click();
      });
    },
    /** 완성된 HTML 문서를 숨긴 iframe에 넣어 인쇄합니다 (팝업 차단·앱 제한과 무관) */
    print(html) {
      const f = document.createElement('iframe');
      f.setAttribute('aria-hidden', 'true');
      f.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;opacity:0;pointer-events:none';
      document.body.appendChild(f);
      const d = f.contentDocument;
      d.open();
      d.write(html);
      d.close();
      const w = f.contentWindow;
      const done = () => setTimeout(() => f.remove(), 500);
      w.addEventListener('afterprint', done, { once: true });
      setTimeout(() => {
        w.focus();
        w.print();
        setTimeout(done, 60000);
      }, 350);
    },
    openPage(page, hash = '') {
      if (singleWindow) return leaveTo(page + hash);
      window.open(page + hash, '_blank', 'noopener'); // 설치한 PWA에서는 새 앱 창으로 열립니다 (메이커 창은 그대로)
    },
    openExternal(url) {
      window.open(url, '_blank', 'noopener,noreferrer');
    },
  };

  /* ---------- Tauri (Windows 앱 · 안드로이드의 DLC 메이커 앱) ----------
     안드로이드(휴대폰 — mobile): 창이 하나라 다른 화면은 같은 창에서(웹과 같은 openPage), 열기는 WebView의 파일 고르기(진짜 파일 이름 — .htpack 검사에 씀),
     저장은 기기의 '다른 이름으로 저장'(Tauri 저장 대화상자 — 고른 문서 주소에 씀). 확장자 거르기는 휴대폰이 모르는 형식이라 넘기지 않습니다 */
  const tauri = T && {
    async saveFile(filename, blob) {
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const ext = extOf(filename);
      let path = null;
      try {
        path = await T.dialog.save({ defaultPath: filename, filters: ext && !mobile ? [{ name: ext.toUpperCase(), extensions: [ext] }] : [] });
      } catch (e) {
        if (/cancel/i.test(String(e))) return false; // 취소를 거절(reject)로 알리는 경우에도 아무것도 쓰지 않음
        console.warn('저장 대화상자 실패', e);
        path = undefined;
      }
      if (path) {
        await T.fs.writeFile(path, bytes);
        return true;
      }
      if (path === null) return false; // 사용자가 취소
      // 저장 대화상자를 띄우지 못한 환경: 앱 데이터 폴더에 저장
      const dir = await T.path.appDataDir();
      await T.fs.mkdir(dir, { recursive: true }).catch(() => {});
      const full = `${dir.replace(/[\\/]$/, '')}/${filename}`;
      await T.fs.writeFile(full, bytes);
      HT.toast && HT.toast(`앱 데이터 폴더에 저장했습니다: ${filename}`, 'ok');
      return true;
    },
    async openFiles(accept, multiple = false) {
      if (mobile) return web.openFiles(accept, multiple);
      const exts = acceptToExts(accept);
      let r;
      try {
        r = await T.dialog.open({ multiple, filters: exts.length ? [{ name: exts.join(', ').toUpperCase(), extensions: exts }] : [] });
      } catch (e) {
        console.warn('열기 대화상자 실패', e);
        return web.openFiles(accept, multiple);
      }
      const paths = r == null ? [] : Array.isArray(r) ? r : [r];
      return Promise.all(
        paths.map(async p => {
          const path = typeof p === 'string' ? p : p.path;
          const bytes = await T.fs.readFile(path); // 전용 팩의 바이트를 그대로 읽음
          return new File([bytes], baseName(path), { type: /\.htpack$/i.test(path) ? 'application/x-htpack' : 'application/octet-stream' });
        })
      );
    },
    print(html) {
      web.print(html);
    },
    async openPage(page, hash = '') {
      if (singleWindow) return web.openPage(page, hash); // 휴대폰은 창이 하나 — 같은 창에서 옮기고 기기의 뒤로 단추로 돌아옴
      const label = page.replace(/\.html$/, '').replace(/[^a-z0-9-]/gi, '-');
      const { WebviewWindow } = T.webviewWindow;
      const existing = await WebviewWindow.getByLabel(label).catch(() => null);
      if (existing) {
        await existing.setFocus().catch(() => {}); // 같은 화면이 이미 열려 있으면 앞으로 가져오기만 합니다 (넘겨줄 것은 없음 — 메이커 → 연표의 한 방향)
        return;
      }
      const win = new WebviewWindow(label, {
        url: page + hash,
        // 이 길은 메이커 프로그램 안에서만 불립니다(연표는 메이커를 열지 않음) — 연표 창은 따로 설치한 연표 프로그램과 헷갈리지 않게 '미리보기'로 적습니다
        title: page.startsWith('dlc-maker') ? 'DLC 메이커 — 역사 연표' : '연표 미리보기 — DLC 메이커',
        width: 1280,
        height: 800,
        minWidth: 900,
        minHeight: 600,
        dragDropEnabled: false,
      });
      win.once('tauri://error', e => HT.toast && HT.toast(`창을 열지 못했습니다: ${e.payload}`, 'error'));
    },
    openExternal(url) {
      T.opener.openUrl(url).catch(() => web.openExternal(url));
    },
    /* 메이커 미리보기(2026-10-16 감독 "미리보기 하려면 그냥 앱에서 확인하게 해. 본 프로그램"): 본 프로그램(연표 앱)의 실행 파일 자리를 기억해 두고
       (처음 한 번 · 옮겨져 없으면 다시 고름) 작업본 바이트를 넘겨 띄움 — src-tauri/src/lib.rs preview_in_app. 돌려주는 값(Promise): 띄웠으면 true · 고르지 않았으면 false */
    async previewInApp(bytes, name, view) {
      const KEY = 'ht.previewAppExe';
      const pick = async () => {
        const r = await T.dialog.open({ title: '본 프로그램(역사 연표 앱)의 실행 파일 고르기', multiple: false, filters: [{ name: '프로그램', extensions: ['exe'] }] }).catch(() => null);
        const p = r == null ? '' : typeof r === 'string' ? r : r.path || '';
        if (p) HT.store.set(KEY, p);
        return p;
      };
      let exe = HT.store.get(KEY, '') || (await pick());
      if (!exe) return false;
      const send = () => T.core.invoke('preview_in_app', { exe, bytes: Array.from(bytes), name, view });
      try {
        await send();
      } catch (e) {
        if (!String(e).includes('no-exe')) throw e;
        exe = await pick(); // 기억한 자리에 실행 파일이 없음(옮겼거나 새 판으로 바꿈) — 다시 고름
        if (!exe) return false;
        await send();
      }
      return true;
    },
  };

  const impl = tauri || web;

  /* ---------- 뒤로가기 (모바일: 패널·대화상자를 먼저 닫음) ---------- */
  const traps = [];
  let backing = 0; // releaseBack이 부른 뒤로 가기 가운데 아직 끝나지 않은 수 (leaveTo가 기다림)
  function trapBack(close) {
    if (!mobile) return;
    traps.push(close);
    history.pushState({ htTrap: traps.length }, '');
  }
  function releaseBack() {
    if (!mobile || !traps.length) return;
    if (history.state && history.state.htTrap === traps.length) {
      backing++;
      history.back();
    } else traps.pop();
  }
  window.addEventListener('popstate', () => {
    if (backing) backing--;
    const close = traps.pop();
    if (close) close();
  });
  /** 같은 창에서 다른 화면으로 옮깁니다 (창이 하나뿐인 환경 — 기기의 뒤로 단추로 돌아옴).
      먼저 HT.platform.beforeLeave(화면이 둠 — 메이커: 편집 창에 저장하지 않은 고침이 있으면 '저장하고 이동 / 버리고 이동 / 취소')를 부르고, false면 옮기지 않습니다.
      묻느라 닫은 창 · 패널의 뒤로 한 칸이 아직 끝나지 않았으면 끝난 뒤에 옮깁니다 (그 뒤로 가기가 옮기기를 가로채지 않게) */
  async function leaveTo(url) {
    const check = HT.platform && HT.platform.beforeLeave;
    if (typeof check === 'function' && !(await check())) return false;
    for (let i = 0; backing && i < 20; i++) await new Promise(r => setTimeout(r, 25));
    location.assign(url);
    return true;
  }
  if (mobile && window.HTMLDialogElement) {
    // 대화상자는 모두 <dialog>.showModal()로 열리므로 여기서 한 번에 처리합니다
    const showModal = HTMLDialogElement.prototype.showModal;
    HTMLDialogElement.prototype.showModal = function () {
      showModal.call(this);
      trapBack(() => this.open && this.close());
      this.addEventListener('close', releaseBack, { once: true });
    };
  }

  /* ---------- 공개 API ---------- */
  HT.platform = {
    name,
    mobile,
    singleWindow,
    canPrint: !mobile,
    canDrop: !mobile,
    saveFile: (filename, blob) => impl.saveFile(filename, blob),
    openFiles: (accept, multiple) => impl.openFiles(accept, multiple),
    print: html => impl.print(html),
    openPage: (page, hash) => impl.openPage(page, hash),
    openExternal: url => impl.openExternal(url),
    /** 본 프로그램(연표 앱)에서 미리보기를 띄울 수 있는가 — 컴퓨터의 메이커 앱(Tauri)만 */
    canPreviewApp: !!tauri && !mobile,
    previewInApp: (bytes, name, view) => (tauri && !mobile ? tauri.previewInApp(bytes, name, view) : Promise.resolve(false)),
    /** 같은 창에서 다른 화면으로 옮기기 전에 부르는 확인 — () => Promise<boolean>. 화면(메이커)이 둡니다 */
    beforeLeave: null,
    trapBack,
    releaseBack,
  };
  document.documentElement.dataset.platform = name;
  if (mobile) document.documentElement.dataset.mobile = '';

  /* 링크는 HTML에 그대로 두고 여기서 가로챕니다: data-page(다른 화면) · http 외부 링크 */
  document.addEventListener('click', e => {
    const a = e.target.closest('a[href]');
    if (!a || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey) return;
    if (a.dataset.page != null) {
      e.preventDefault();
      HT.platform.openPage(a.getAttribute('href'), a.dataset.hash || '');
    } else if (/^https?:/i.test(a.href) && name !== 'web') {
      e.preventDefault();
      HT.platform.openExternal(a.href);
    }
  });

  /* ---------- 앱: 저장소 거울 (localStorage → 앱 데이터 폴더/state.json) ---------- */
  if (T && HT.store) {
    const FILE = 'state.json';
    const htKeys = () => Object.keys(localStorage).filter(k => k.startsWith('ht.'));
    let timer = null;
    let dirP = null;
    const dir = () => (dirP = dirP || T.path.appDataDir().then(d => d.replace(/[\\/]$/, '')));
    const mirror = () => {
      clearTimeout(timer);
      timer = setTimeout(async () => {
        try {
          const d = await dir();
          await T.fs.mkdir(d, { recursive: true }).catch(() => {});
          const data = {};
          for (const k of htKeys()) data[k] = localStorage.getItem(k);
          await T.fs.writeTextFile(`${d}/${FILE}`, JSON.stringify({ format: 'history-timeline-state', savedAt: new Date().toISOString(), data }));
        } catch (e) {
          console.warn('거울 저장 실패', e);
        }
      }, 300);
    };
    const set = HT.store.set.bind(HT.store);
    const remove = HT.store.remove.bind(HT.store);
    HT.store.set = (k, v) => {
      const ok = set(k, v);
      mirror();
      return ok;
    };
    HT.store.remove = k => {
      remove(k);
      mirror();
    };
    HT.platform.dataDir = dir;
    // 시작할 때 WebView 저장소가 비어 있고 파일이 있으면 되살립니다 (첫 실행·재설치·OS가 비운 경우)
    if (!htKeys().length) {
      (async () => {
        try {
          const d = await dir();
          const path = `${d}/${FILE}`;
          if (!(await T.fs.exists(path))) return;
          const saved = JSON.parse(await T.fs.readTextFile(path));
          if (!saved || saved.format !== 'history-timeline-state' || !saved.data) return;
          for (const [k, v] of Object.entries(saved.data)) if (typeof v === 'string') localStorage.setItem(k, v);
          if (htKeys().length) location.reload();
        } catch (e) {
          console.warn('거울 복원 실패', e);
        }
      })();
    }
  }

  /* ---------- 파일 "연결 프로그램"으로 열렸을 때 (PWA file_handlers) → 'ht:files' 이벤트 ---------- */
  if ('launchQueue' in window && window.launchQueue.setConsumer) {
    window.launchQueue.setConsumer(async params => {
      if (!params.files || !params.files.length) return;
      const files = await Promise.all(params.files.map(h => h.getFile()));
      document.dispatchEvent(new CustomEvent('ht:files', { detail: files }));
    });
  }

  /* ---------- PWA: 서비스 워커 (http/https에서만 — 파일 직접 열기는 그대로) ---------- */
  if (name !== 'tauri' && /^https?:$/.test(location.protocol) && 'serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker
        .register('sw.js')
        .then(reg => {
          reg.addEventListener('updatefound', () => {
            const w = reg.installing;
            w &&
              w.addEventListener('statechange', () => {
                if (w.state === 'installed' && navigator.serviceWorker.controller && HT.toast) HT.toast('새 버전이 준비되었습니다. 새로고침하면 적용됩니다.');
              });
          });
        })
        .catch(e => console.warn('서비스 워커 등록 실패', e));
    });
  }
})();
