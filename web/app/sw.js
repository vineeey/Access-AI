/* AccessAI PWA service worker.
 *
 * Registered ONLY in a secure context (see app.js). Two jobs:
 *   1. Cache the APP SHELL so the app launches offline (index/js/css/icons/manifest).
 *   2. Stay OUT OF THE WAY of live data: /video, /events, snapshots, history,
 *      status and every other API call are NETWORK-ONLY — a doorbell app must
 *      never show a stale frame or a cached "who's at the door".
 *
 * Bump CACHE_VERSION to ship an update (old caches are purged on activate).
 */

const CACHE_VERSION = "accessai-shell-v1";
const SHELL = [
  "/app",
  "/app/",
  "/app/index.html",
  "/app/app.css",
  "/app/app.js",
  "/app/manifest.webmanifest",
  "/app/icons/icon-192.png",
  "/app/icons/icon-512.png",
  "/app/icons/maskable-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then((cache) => cache.addAll(SHELL).catch(() => {}))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Only the app shell is a candidate for the cache. Everything else is dynamic.
function isShellRequest(url) {
  if (url.origin !== self.location.origin) return false;   // never cache other origins (a remote server URL)
  const p = url.pathname;
  return SHELL.includes(p) || p === "/app" || p === "/app/" || p.startsWith("/app/icons/");
}

// Live/dynamic endpoints that must NEVER be cached, even under /app-less origins.
function isDynamic(url) {
  const p = url.pathname;
  return (
    p.startsWith("/video") || p.startsWith("/events") || p.startsWith("/snapshot") ||
    p.startsWith("/history") || p.startsWith("/event") || p.startsWith("/status") ||
    p.startsWith("/trigger") || p.startsWith("/hear_visitor") || p.startsWith("/reply") ||
    p.startsWith("/command") || p.startsWith("/speak_audio") || p.startsWith("/known") ||
    p.startsWith("/enroll") || p.startsWith("/mode") || p.startsWith("/voices") ||
    p.startsWith("/voice") || p.startsWith("/listen")
  );
}

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;                 // POSTs go straight to the network
  const url = new URL(req.url);

  if (isDynamic(url)) return;                        // network-only (default browser handling)

  if (isShellRequest(url)) {
    // Cache-first for the shell, with a background refresh so updates land.
    event.respondWith(
      caches.match(req).then((cached) => {
        const network = fetch(req).then((res) => {
          if (res && res.ok) {
            const copy = res.clone();
            caches.open(CACHE_VERSION).then((c) => c.put(req, copy));
          }
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
  }
  // Anything else: let the browser handle it (network).
});
