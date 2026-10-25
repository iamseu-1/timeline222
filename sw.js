/* 역사 연표 — 서비스 워커 (PWA 오프라인 캐시)
 * VERSION은 scripts/sync-version.mjs가 package.json에 맞춰 바꿉니다.
 * 같은 origin 파일은 캐시 우선으로 주고, 뒤에서 새로 받아 두었다가 다음 실행 때 씁니다.
 * 연표와 DLC 메이커는 웹 폴더가 따로입니다(dist/web · dist/maker). scripts/build-web.mjs가 폴더마다
 * PRECACHE를 그 폴더에 실제로 있는 파일만으로 거르고, 캐시 이름 앞머리 PREFIX를 연표 'ht-' · 메이커 'htm-'로 바꿔 씁니다.
 * 그래서 이 목록은 두 폴더의 파일을 모두 적어 둔 원본이고, 옛 캐시 지우기는 제 앞머리의 것만 지웁니다. */
const VERSION = '0.0.4'; // package.json의 판(scripts/sync-version.mjs) — 1.1.0 릴리즈에서 그동안 손으로 올리던 1.5.4를 대신함(캐시 이름만 바뀜)
const PREFIX = 'ht-';
const CACHE = `${PREFIX}${VERSION}`;
const PRECACHE = [
  'index.html',
  'dlc-maker.html',
  'manifest.webmanifest',
  'css/common.css',
  'css/viewer.css',
  'css/maker.css',
  'fonts/Pretendard-Regular.otf',
  'fonts/Pretendard-SemiBold.otf',
  'fonts/Pretendard-Bold.otf',
  'fonts/Pretendard-OFL.txt',
  'fonts/ChosunKm.ttf',
  'fonts/ChosunKm-LICENSE.txt',
  'js/calendar.js',
  'js/core.js',
  'js/wiki.js',
  'js/platform.js',
  'js/packfile.js',
  'js/fieldpop.js',
  'js/form-keys.js',
  'js/timeline.js',
  'js/kin-view.js',
  'js/group-tree.js',
  'js/viewer.js',
  'js/views-ui.js',
  'js/lens-ui.js',
  'js/maker.js',
  'js/maker-history.js',
  'js/maker-grid.js',
  'js/maker-paste.js',
  'js/maker-drag.js',
  'js/maker-blocks.js',
  'js/maker-find.js',
  'js/maker-shell.js',
  'js/maker-kin.js',
  'js/maker-check.js',
  'js/maker-images.js',
  'js/maker-templates.js',
  'js/motion-probe.js',
  'packs/east-asia/pack.js',
  'packs/east-asia/korea-1.js',
  'packs/east-asia/korea-2.js',
  'packs/east-asia/china-1.js',
  'packs/east-asia/china-2.js',
  'packs/east-asia/japan.js',
  'packs/east-asia/vietnam.js',
  'packs/east-asia/north.js',
  'packs/east-asia/relations.js',
  'icons/icon-192.png',
  'icons/icon-512.png',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then(c => c.addAll(PRECACHE.map(p => new Request(p, { cache: 'reload' }))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches
      .keys()
      .then(keys => Promise.all(keys.filter(k => k.startsWith(PREFIX) && k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(
    caches.open(CACHE).then(async cache => {
      const cached = await cache.match(req, { ignoreSearch: true });
      const fresh = fetch(req)
        .then(res => {
          if (res && res.ok) cache.put(req, res.clone());
          return res;
        })
        .catch(() => null);
      return cached || (await fresh) || new Response('오프라인 상태이고 저장된 파일이 없습니다.', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
    })
  );
});
