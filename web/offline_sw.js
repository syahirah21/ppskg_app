// Offline copy of the PPSKG website (registered in index.html).
//
// Every file the site loads is saved in the browser's cache. Online, the
// newest file always comes from the server first (so updates show up
// straight away) and the cache is refreshed; offline, the saved copy is
// used. The site must be opened once with internet on a device before it
// works offline there.
//
// Lot data from the RISDA ArcGIS server and map tiles are NOT handled here:
// the app keeps its own copy of the lists and drafts.

const CACHE = 'ppskg-offline-v1';

// How long to wait for the server before using the saved copy, for weak
// signal that is connected but not working.
const NETWORK_TIMEOUT_MS = 8000;

// Saved on first visit so the app can start offline even if it was closed
// before everything finished loading. Others are saved as they're used.
const CORE = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(CORE.map((url) => cache.add(url).catch(() => {}))),
    ),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key !== CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

function isFont(url) {
  return (
    url.hostname === 'fonts.gstatic.com' ||
    url.hostname === 'fonts.googleapis.com'
  );
}

async function save(request, response) {
  if (response.ok || response.type === 'opaque') {
    const cache = await caches.open(CACHE);
    await cache.put(request, response.clone());
  }
  return response;
}

async function fromCache(request) {
  const cached = await caches.match(request, { ignoreSearch: true });
  if (cached) return cached;
  // Opening the site at any address inside it falls back to the app.
  if (request.mode === 'navigate') {
    return (await caches.match('./')) || (await caches.match('index.html'));
  }
  return undefined;
}

async function networkFirst(request) {
  const network = fetch(request).then((response) => save(request, response));
  network.catch(() => {}); // Handled below; avoids an "unhandled" warning.
  const timeout = new Promise((resolve) =>
    setTimeout(resolve, NETWORK_TIMEOUT_MS),
  );
  try {
    // Slow network: use the saved copy if there is one, else keep waiting.
    const first = await Promise.race([network, timeout]);
    if (first) return first;
    return (await fromCache(request)) || (await network);
  } catch (e) {
    const cached = await fromCache(request);
    if (cached) return cached;
    throw e;
  }
}

// Font files never change, so the saved copy is used whenever there is one.
async function cacheFirst(request) {
  const cached = await caches.match(request);
  return cached || save(request, await fetch(request));
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (isFont(url)) {
    event.respondWith(cacheFirst(request));
  } else if (url.origin === self.location.origin) {
    event.respondWith(networkFirst(request));
  }
});
