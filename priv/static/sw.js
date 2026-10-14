// The service worker of the installable Tales Forge app (/manifest.webmanifest).
// Install only: it caches nothing, so every page, LiveView and asset request
// goes to the network as usual. It exists so browsers offer "Install app".

self.addEventListener("install", () => self.skipWaiting())

self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))
