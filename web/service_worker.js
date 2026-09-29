// The first successful install caches everything needed to reopen the tracker offline.
const CACHE = 'athlete-os-shell-v5';
const PRECACHE = [
  './', './index.html', './flutter_bootstrap.js', './flutter.js',
  './main.dart.js', './manifest.json', './sqlite3.wasm',
  './assets/AssetManifest.bin', './assets/FontManifest.json',
  './assets/catalog/exercises.json',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  './assets/shaders/ink_sparkle.frag', './assets/shaders/stretch_effect.frag',
  './canvaskit/canvaskit.js', './canvaskit/canvaskit.wasm',
  './canvaskit/chromium/canvaskit.js', './canvaskit/chromium/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => Promise.allSettled(PRECACHE.map((url) => cache.add(url))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith('athlete-os-shell-') && key !== CACHE)
          .map((key) => caches.delete(key)),
      ))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.includes('/auth/') || url.pathname.includes('/rest/') ||
      url.pathname.includes('/v1/') || url.pathname.includes('/functions/')) return;
  event.respondWith((async () => {
    try {
      const response = await fetch(event.request);
      if (response.ok) {
        const copy = response.clone();
        event.waitUntil(caches.open(CACHE).then((cache) => cache.put(event.request, copy)));
      }
      return response;
    } catch (_) {
      const cached = await caches.match(event.request, {ignoreSearch: true});
      if (cached) return cached;
      if (event.request.mode === 'navigate') {
        return (await caches.match('./index.html')) || Response.error();
      }
      return Response.error();
    }
  })());
});
