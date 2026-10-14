// The service worker of the installed team app (/team).
// It handles install and push only. It caches no pages and no page data.
// The team page registers it with the scope /team (assets/js/team_push.js).

self.addEventListener("install", () => self.skipWaiting())

self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

// The server sends JSON: {title, body, url, tag} (Workflow.Push).
self.addEventListener("push", (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch (_e) {
    data = {body: event.data ? event.data.text() : ""}
  }

  const title = data.title || "Tales Forge team"
  const options = {
    body: data.body || "",
    tag: data.tag,
    icon: "/team-app/icon-maskable-192.png",
    badge: "/team-app/icon-maskable-192.png",
    data: {url: data.url || "/team"}
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

// A click on the notification opens the team app at the item.
self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = new URL(event.notification.data.url || "/team", self.location.origin).href

  event.waitUntil(
    self.clients.matchAll({type: "window", includeUncontrolled: true}).then((windows) => {
      const open = windows.find((w) => w.url.startsWith(self.location.origin + "/team"))
      if (open) return open.navigate(url).then((w) => (w || open).focus())
      return self.clients.openWindow(url)
    })
  )
})
