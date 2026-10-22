// The application used to live at the root of this site, and browsers that
// opened it then still run its service worker for "/". Browsers check this
// file again on their next visit: this version removes that old worker and
// its stored copy of the application, then reloads the open tabs so they show
// the landing page. The application at /app/ registers its own worker there.
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter((key) => key.startsWith("flutter-")).map((key) => caches.delete(key)),
    );
    await self.registration.unregister();
    const tabs = await self.clients.matchAll({ type: "window" });
    tabs.forEach((tab) => tab.navigate(tab.url));
  })());
});
