// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ex_tales_forge"
import topbar from "../vendor/topbar"
import {Mermaid} from "./mermaid_hook"
import {StoryScroll} from "./story_scroll"
import {TeamPush} from "./team_push"
import {MentionSuggest, TeamAnchorRedirect, ImageInput, TeamChat, TeamFlow, TeamInbox, TeamLanes, TeamPage} from "./team_hooks"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Mermaid, TeamPage, TeamFlow, TeamLanes, TeamAnchorRedirect, MentionSuggest, TeamChat, TeamInbox, ImageInput, StoryScroll, TeamPush},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Server-pushed "scroll-into-view" (e.g. admin docs: jump to the article after
// picking a file). `mobile_only` skips it when the list and article sit side by side.
window.addEventListener("phx:scroll-into-view", ({detail}) => {
  if (detail.mobile_only && window.matchMedia("(min-width: 1024px)").matches) return
  const el = document.getElementById(detail.id)
  if (el) requestAnimationFrame(() => el.scrollIntoView({behavior: "smooth", block: "start"}))
})

// "We can't find the internet" flash (Layouts.flash_group). Phoenix shows it
// at once when the socket drops. A deploy or a phone that comes back from the
// background reconnects in about 1 second, so wait 3 seconds and show it only
// if the socket is still down.
const CLIENT_ERROR_DELAY_MS = 3000
window.addEventListener("tf:client-error-later", e => {
  const el = e.target
  clearTimeout(el._showTimer)
  el._showTimer = setTimeout(() => {
    if (!liveSocket.isConnected() && el.closest(".phx-client-error")) {
      liveSocket.execJS(el, el.getAttribute("data-show-js"))
    }
  }, CLIENT_ERROR_DELAY_MS)
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

