const CACHE = "heha-swipe-shell-v3-review-20260830";
const LEGACY_HEHA_CACHES = new Set(["heha-v1"]);
const SHELL = [
  "/index.html",
  "/manifest.json",
  "/icons/icon-180.png",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/icon-maskable-192.png",
  "/icons/icon-maskable-512.png",
  "/install-guides/ios-add-to-home.svg",
  "/install-guides/android-add-to-home.svg",
];
const EXPLICIT_STATIC_PATHS = new Set(SHELL.filter((path) => path !== "/index.html"));

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys
        .filter((key) => (key.startsWith("heha-swipe-shell-") || LEGACY_HEHA_CACHES.has(key)) && key !== CACHE)
        .map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match("/index.html")));
    return;
  }

  const immutableBuildAsset = url.pathname.startsWith("/assets/")
    && ["script", "style", "font"].includes(request.destination);
  if (!immutableBuildAsset && !EXPLICIT_STATIC_PATHS.has(url.pathname)) return;

  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request).then((response) => {
      if (!response.ok || response.type !== "basic") return response;
      const copy = response.clone();
      caches.open(CACHE).then((cache) => cache.put(request, copy));
      return response;
    }))
  );
});
