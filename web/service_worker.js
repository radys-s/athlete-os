const CACHE = 'athlete-os-shell-v1';
const SHELL = [
  './', './index.html', './flutter_bootstrap.js', './flutter.js',
  './main.dart.js', './manifest.json', './sqlite3.wasm',
  './drift_worker.dart.js', './assets/AssetManifest.bin',
  './assets/FontManifest.json', './assets/catalog/exercises.json',
  './canvaskit/canvaskit.js', './canvaskit/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(
    keys.filter((key) => key.startsWith('athlete-os-shell-') && key !== CACHE)
      .map((key) => caches.delete(key)),
  )));
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.includes('/auth/') || url.pathname.includes('/rest/') ||
      url.pathname.includes('/v1/') || url.pathname.includes('/functions/')) return;
  const isShell = url.pathname === new URL('./', self.location.href).pathname ||
    /\.(js|wasm|json|bin|png|svg|woff2?)$/.test(url.pathname);
  if (!isShell) return;
  event.respondWith(caches.match(event.request).then((cached) => cached ||
    fetch(event.request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, copy));
      }
      return response;
    })));
});
