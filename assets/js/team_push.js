// The installed team app on /team (Workflow.Push).
// 1. Register the service worker /team-sw.js with the scope /team.
// 2. Ask for notification permission one time, at the first tap or key press.
//    Browsers show the question only after a user action.
// 3. When the browser gives permission, subscribe to push and send the
//    subscription to the server (event "push:subscribe").
// The page shows no settings. Push is on after the browser gives permission.

const ASKED = "team-push:asked"

const urlKey = (base64) => {
  const pad = "=".repeat((4 - (base64.length % 4)) % 4)
  const raw = atob((base64 + pad).replace(/-/g, "+").replace(/_/g, "/"))
  return Uint8Array.from(raw, (c) => c.charCodeAt(0))
}

const pushReady = () =>
  "serviceWorker" in navigator && "PushManager" in window && "Notification" in window

export const TeamPush = {
  mounted() {
    if (!("serviceWorker" in navigator)) return
    navigator.serviceWorker
      .register("/team-sw.js", {scope: "/team"})
      .then((registration) => this.startPush(registration))
      .catch(() => {})
  },

  startPush(registration) {
    const key = this.el.dataset.key
    if (!key || !pushReady()) return

    if (Notification.permission === "granted") {
      this.subscribe(registration, key)
    } else if (Notification.permission === "default" && !localStorage.getItem(ASKED)) {
      const ask = () => {
        window.removeEventListener("pointerdown", ask, true)
        window.removeEventListener("keydown", ask, true)
        localStorage.setItem(ASKED, new Date().toISOString())
        Notification.requestPermission().then((answer) => {
          if (answer === "granted") this.subscribe(registration, key)
        })
      }
      window.addEventListener("pointerdown", ask, true)
      window.addEventListener("keydown", ask, true)
    }
  },

  subscribe(registration, key) {
    registration.pushManager
      .getSubscription()
      .then((current) =>
        current || registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: urlKey(key)})
      )
      .then((subscription) => {
        this.pushEvent("push:subscribe", {...subscription.toJSON(), user_agent: navigator.userAgent})
      })
      .catch(() => {})
  }
}
