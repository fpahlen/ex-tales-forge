// The founders' pages: the landing page (/team, TalesForgeWeb.TeamLive) and
// the full presentation (/team/presentation, TalesForgeWeb.TeamPresentationLive).
// TeamAnchorRedirect forwards old /team#section links to the presentation;
// the rest are the animations.
//
// Everything here is decoration: the server renders the full, static page
// (every flow step lit, every bar at its size), and nothing is hidden until
// this code has decided motion is allowed. With prefers-reduced-motion the
// page root gets data-motion="reduce" and nothing moves; otherwise
// data-motion="full", sections fade in as they scroll into view, their bars
// grow (CSS, app.css "Founders' page"), and the d20 rolls through the change
// flow once, with a Replay button.

const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)")

// Root hook: sets data-motion, reveals [data-reveal] sections in view, and
// runs the peeks (hover cards, see setupPeeks below).
export const TeamPage = {
  mounted() {
    this.mq = reducedMotion()
    this.onChange = () => this.apply()
    this.mq.addEventListener("change", this.onChange)
    this.apply()
    this.peeksCleanup = setupPeeks(this.el)
    this.boardDragCleanup = setupBoardDrag(this)
    this.draftsCleanup = BoardDrafts.setup(this)
    this.cardUrlCleanup = setupCardUrl(this)
    this.presentCleanup = setupPresent(this)
    this.timesCleanup = startRelativeTimes()
  },

  // After a reconnect (a deploy restarts production) the board component
  // mounts again with no card open: open the card in the URL again, and put
  // the drafts back.
  reconnected() {
    this.cardUrlRestore?.()
    BoardDrafts.restoreAll(this.el)
  },

  apply() {
    const reduce = this.mq.matches || !("IntersectionObserver" in window)
    this.motion = reduce ? "reduce" : "full"
    this.el.dataset.motion = this.motion
    this.revealed ||= new Set()
    this.observer?.disconnect()
    const sections = this.el.querySelectorAll("[data-reveal]")

    if (reduce) {
      sections.forEach(s => { s.classList.add("is-visible"); this.revealed.add(s.id) })
      return
    }

    this.observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        entry.target.classList.add("is-visible")
        this.revealed.add(entry.target.id)
        this.observer.unobserve(entry.target)
      }
    }, {rootMargin: "0px 0px -8% 0px", threshold: 0.02})

    sections.forEach(s => s.classList.contains("is-visible") || this.observer.observe(s))
  },

  // A LiveView patch (the live feed's numbers change about once a minute)
  // resets the attributes this hook set to what the server rendered:
  // data-motion back to "auto" and the revealed sections' class. Without
  // this, CSS stops every animation (the Replay buttons seemed dead) and
  // revealed sections fade out again. Put them back.
  updated() {
    if (this.motion) this.el.dataset.motion = this.motion
    this.presentRefresh?.()
    this.revealed?.forEach(id => document.getElementById(id)?.classList.add("is-visible"))
  },

  destroyed() {
    this.timesCleanup?.()
    this.observer?.disconnect()
    this.mq?.removeEventListener("change", this.onChange)
    this.peeksCleanup?.()
    this.boardDragCleanup?.()
    this.draftsCleanup?.()
    this.cardUrlCleanup?.()
    this.presentCleanup?.()
  },
}

// Present mode on /team/presentation (TeamPresentationLive.present_controls).
// The "Present" button ([data-present-start], its data-slides lists the
// section ids of the nav) shows one section for each slide, in full screen.
//   - Forward: Right or Down arrow, Page Down, Space, a click, a swipe left.
//   - Back: Left or Up arrow, Page Up, Shift+Space, a click on the left third,
//     a swipe right.
//   - Esc (or leaving full screen) stops it and goes to that section.
// The URL hash is #slide-N (1-based), so a link opens that slide. The
// browser allows full screen only after a click, so a link opens the slide
// in the window.
export const slideFromHash = (hash, total) => {
  const m = /^#slide-(\d+)$/.exec(hash || "")
  if (!m) return null
  const n = parseInt(m[1], 10)
  return n >= 1 && n <= total ? n : null
}

export const clampSlide = (n, total) => Math.min(Math.max(n, 1), total)

const PRESENT_SKIP = "a, button, input, textarea, select, summary, label, [data-peek], [data-present-bar]"

export const setupPresent = hook => {
  const root = hook.el
  const start = root.querySelector("[data-present-start]")
  const bar = root.querySelector("[data-present-bar]")
  if (!start || !bar) return () => {}
  const ids = JSON.parse(start.dataset.slides || "[]")
  const total = ids.length
  let current = null
  let touch = null

  const others = () => root.querySelectorAll("#team-header, #present-start-wrap, #team-main > *, footer")

  const render = () => {
    if (current === null) return
    const id = ids[current - 1]
    others().forEach(el => el.classList.toggle("hidden", el.id !== id))
    document.getElementById(id)?.classList.add("is-visible")
    bar.hidden = false
    root.dataset.presenting = "true"
    const counter = bar.querySelector("#present-counter")
    if (counter) counter.textContent = `${current} / ${total}`
    window.scrollTo(0, 0)
  }

  // A slide with a [data-present-steps] figure (TeamFlow) steps through it
  // first: forward shows its next part until all is shown.
  const stepper = () => current && document.getElementById(ids[current - 1])?.querySelector("[data-present-steps]")
  // Back steps back one part at a time; from the next slide it lands on the
  // stepper's last part, everything shown (presentStart(true)).
  const forward = () => { if (!stepper()?.presentNext?.()) go(current + 1) }
  const back = () => { if (!stepper()?.presentPrev?.()) go(current - 1, true) }

  const go = (n, fromEnd = false) => {
    const next = clampSlide(n, total)
    if (next !== current) stepper()?.presentEnd?.()
    const entered = next !== current
    current = next
    history.replaceState(null, "", `#slide-${current}`)
    render()
    // After render, so the slide is visible and the d20 can be placed.
    if (entered) stepper()?.presentStart?.(fromEnd)
  }

  const begin = (n, fullscreen) => {
    if (total === 0) return
    if (fullscreen && document.documentElement.requestFullscreen && !document.fullscreenElement) {
      document.documentElement.requestFullscreen().catch(() => {})
    }
    go(n)
  }

  const stop = () => {
    if (current === null) return
    const id = ids[current - 1]
    stepper()?.presentEnd?.()
    current = null
    others().forEach(el => el.classList.remove("hidden"))
    bar.hidden = true
    delete root.dataset.presenting
    if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {})
    history.replaceState(null, "", `#${id}`)
    document.getElementById(id)?.scrollIntoView()
  }

  const onStart = () => begin(1, true)
  const onExit = e => { e.stopPropagation(); stop() }

  const onKey = e => {
    if (current === null || e.target.closest?.("input, textarea, select, [contenteditable]")) return
    const fwd = ["ArrowRight", "ArrowDown", "PageDown"].includes(e.key) || (e.key === " " && !e.shiftKey)
    const bwd = ["ArrowLeft", "ArrowUp", "PageUp"].includes(e.key) || (e.key === " " && e.shiftKey)
    if (e.key === "Escape") stop()
    else if (fwd) forward()
    else if (bwd) back()
    else return
    e.preventDefault()
  }

  const onClick = e => {
    if (current === null || e.target.closest(PRESENT_SKIP)) return
    if (e.clientX < window.innerWidth / 3) back()
    else forward()
  }

  const onTouchStart = e => {
    const t = e.changedTouches[0]
    touch = {x: t.clientX, y: t.clientY}
  }

  const onTouchEnd = e => {
    if (current === null || !touch) return
    const t = e.changedTouches[0]
    const dx = t.clientX - touch.x
    const dy = t.clientY - touch.y
    touch = null
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) dx < 0 ? forward() : back()
  }

  const onFullscreen = () => { if (!document.fullscreenElement && current !== null) stop() }

  const onHash = () => {
    const n = slideFromHash(window.location.hash, total)
    if (n && n !== current) begin(n, false)
  }

  start.addEventListener("click", onStart)
  bar.querySelector("[data-present-exit]")?.addEventListener("click", onExit)
  document.addEventListener("keydown", onKey)
  root.addEventListener("click", onClick)
  root.addEventListener("touchstart", onTouchStart, {passive: true})
  root.addEventListener("touchend", onTouchEnd, {passive: true})
  document.addEventListener("fullscreenchange", onFullscreen)
  window.addEventListener("hashchange", onHash)
  hook.presentRefresh = render
  onHash()

  return () => {
    start.removeEventListener("click", onStart)
    document.removeEventListener("keydown", onKey)
    root.removeEventListener("click", onClick)
    root.removeEventListener("touchstart", onTouchStart)
    root.removeEventListener("touchend", onTouchEnd)
    document.removeEventListener("fullscreenchange", onFullscreen)
    window.removeEventListener("hashchange", onHash)
  }
}

// Peeks: the hover cards on the call-type pills (TalesForgeWeb.TeamPeek).
// A [data-peek] wrapper holds a [data-peek-trigger] button and its card; the
// card shows while the wrapper has data-open (Tailwind classes in the
// component), and the button's aria-expanded follows it.
//   - Mouse: opens on hover, closes on leaving (unless pinned).
//   - Keyboard: opens when the button gets focus, closes when focus leaves
//     the peek (unless pinned). Enter/Space pins it like a click.
//   - Tap or click on the button: pins it open, or closes it if pinned.
//   - Esc closes every peek and puts focus back on its button; a tap or click
//     outside closes pinned ones. One peek is open at a time.
// Motion (the fade) is CSS with motion-safe:, so reduced motion just snaps.
// The idea board (TalesForgeWeb.TeamIdeaBoard): drag a card
// ([data-board-card]) onto a column ([data-board-column]) to move it. Delegated
// on the page root, so it survives LiveView patches. The keyboard and phone
// alternative is each card's "Move to" form. The server renders the columns a
// card may go to in data-moves (TalesForge.Board.Transitions); the JS only
// reads that list, it has no rules of its own. The server checks every move.
export const setupBoardDrag = hook => {
  const root = hook.el
  let dragged = null
  let moves = []
  const column = e => e.target.closest?.("[data-board-column]")
  const columns = () => root.querySelectorAll("[data-board-column]")
  const accepts = col => col && moves.includes(col.dataset.boardColumn)
  const onStart = e => {
    const card = e.target.closest?.("[data-board-card]")
    if (!card) return
    dragged = card.dataset.boardCard
    moves = (card.dataset.moves || "").split(" ").filter(Boolean)
    columns().forEach(c => { c.dataset.accepts = String(accepts(c)) })
    e.dataTransfer.effectAllowed = "move"
    e.dataTransfer.setData("text/plain", dragged)
  }
  const onOver = e => {
    const col = column(e)
    if (!dragged || !accepts(col)) return
    e.preventDefault()
    col.classList.add("is-drop-target")
  }
  const onLeave = e => column(e)?.classList.remove("is-drop-target")
  const onDrop = e => {
    const col = column(e)
    if (!dragged || !accepts(col)) return
    e.preventDefault()
    col.classList.remove("is-drop-target")
    const target = root.querySelector("[data-board-target]")
    if (target) hook.pushEventTo(target, "move", {card_id: dragged, to: col.dataset.boardColumn})
    dragged = null
  }
  const onEnd = () => {
    dragged = null
    moves = []
    columns().forEach(c => { delete c.dataset.accepts })
  }
  const events = [["dragstart", onStart], ["dragover", onOver], ["dragleave", onLeave], ["drop", onDrop], ["dragend", onEnd]]
  events.forEach(([n, f]) => root.addEventListener(n, f))
  return () => events.forEach(([n, f]) => root.removeEventListener(n, f))
}

export const setupPeeks = root => {
  const all = () => root.querySelectorAll("[data-peek]")
  const peekOf = node => node instanceof Element ? node.closest("[data-peek]") : null
  const triggerOf = peek => peek.querySelector("[data-peek-trigger]")

  const open = (peek, pinned = false) => {
    all().forEach(other => other !== peek && close(other))
    peek.dataset.open = ""
    if (pinned) peek.dataset.pinned = ""
    triggerOf(peek)?.setAttribute("aria-expanded", "true")
  }

  const close = peek => {
    delete peek.dataset.open
    delete peek.dataset.pinned
    triggerOf(peek)?.setAttribute("aria-expanded", "false")
  }

  const isOpen = peek => "open" in peek.dataset
  const isPinned = peek => "pinned" in peek.dataset

  const onPointerOver = e => {
    const peek = peekOf(e.target)
    if (e.pointerType !== "mouse" || !peek || isOpen(peek) || "dismissed" in peek.dataset) return
    open(peek)
  }

  const onPointerOut = e => {
    const peek = peekOf(e.target)
    if (e.pointerType !== "mouse" || !peek || peek.contains(e.relatedTarget)) return
    delete peek.dataset.dismissed
    if (!isPinned(peek)) close(peek)
  }

  const onFocusIn = e => {
    const peek = peekOf(e.target)
    if (!peek || isOpen(peek) || !e.target.matches("[data-peek-trigger]:focus-visible")) return
    open(peek)
  }

  const onFocusOut = e => {
    const peek = peekOf(e.target)
    if (!peek || peek.contains(e.relatedTarget) || isPinned(peek)) return
    close(peek)
  }

  const onClick = e => {
    const trigger = e.target instanceof Element ? e.target.closest("[data-peek-trigger]") : null

    if (trigger) {
      const peek = peekOf(trigger)
      if (!peek) return

      if (isPinned(peek)) {
        close(peek)
        if (peek.matches(":hover")) peek.dataset.dismissed = ""
      } else {
        open(peek, true)
      }

      return
    }

    const inside = peekOf(e.target)
    all().forEach(peek => peek !== inside && isPinned(peek) && close(peek))
  }

  const onKeyDown = e => {
    if (e.key !== "Escape") return
    const focused = peekOf(document.activeElement)

    all().forEach(peek => {
      if (!isOpen(peek)) return
      close(peek)
      if (peek.matches(":hover")) peek.dataset.dismissed = ""
    })

    if (focused) triggerOf(focused)?.focus()
  }

  root.addEventListener("pointerover", onPointerOver)
  root.addEventListener("pointerout", onPointerOut)
  root.addEventListener("focusin", onFocusIn)
  root.addEventListener("focusout", onFocusOut)
  document.addEventListener("click", onClick)
  document.addEventListener("keydown", onKeyDown)

  return () => {
    root.removeEventListener("pointerover", onPointerOver)
    root.removeEventListener("pointerout", onPointerOut)
    root.removeEventListener("focusin", onFocusIn)
    root.removeEventListener("focusout", onFocusOut)
    document.removeEventListener("click", onClick)
    document.removeEventListener("keydown", onKeyDown)
  }
}

// The change flow (section 2) and the path from the idea board to production
// (section 4, #wired-flow): the d20 visits each step; approval steps hold
// longer and stamp the founders' seal. A [data-flow-note] step (the fast
// lane under the path) lights up without the token. After the steps, the
// [data-flow-fact] items appear one at a time. Plays once when scrolled into
// view. In Present mode, a figure with data-present-steps shows one more step
// or fact for each click or arrow key (el.presentStart / el.presentNext,
// called by setupPresent).
export const TeamFlow = {
  mounted() {
    this.steps = [...this.el.querySelectorAll("[data-flow-step]")]
    this.facts = [...this.el.querySelectorAll("[data-flow-fact]")]
    this.presentAt = null
    if ("presentSteps" in this.el.dataset) {
      this.el.presentStart = fromEnd => this.presentStart(fromEnd)
      this.el.presentNext = () => this.presentNext()
      this.el.presentPrev = () => this.presentPrev()
      this.el.presentEnd = () => this.presentEnd()
    }
    this.track = this.el.querySelector("[data-flow-track]")
    this.token = this.el.querySelector("[data-flow-token]")
    this.timers = []
    this.current = null
    this.mq = reducedMotion()

    this.onReplay = () => { this.presentAt = null; this.play() }
    this.replayButton = this.el.querySelector("[data-flow-replay]")
    this.replayButton?.addEventListener("click", this.onReplay)

    this.onResize = () => this.place(this.current)
    window.addEventListener("resize", this.onResize)

    this.onChange = () => this.mq.matches && this.settle()
    this.mq.addEventListener("change", this.onChange)

    if (this.mq.matches || !("IntersectionObserver" in window)) return this.settle()

    // Plays once when first scrolled into view. Scrolled away before it is
    // done, it settles to the full static picture and stays so: coming back
    // shows everything at once. Only the Replay button plays it again.
    this.observer = new IntersectionObserver(entries => {
      if (this.presentAt != null) return
      if (entries.some(e => e.isIntersecting)) {
        if (!this.played) { this.played = true; this.play() }
      } else if (this.el.dataset.flow === "playing") {
        this.settle()
      }
    }, {threshold: 0.3})
    this.observer.observe(this.el)
  },

  // Static diagram: every step lit, no token.
  settle() {
    this.clear()
    this.el.dataset.flow = "static"
    this.steps.forEach(s => { delete s.dataset.state; delete s.dataset.stamped })
    this.facts.forEach(f => { delete f.dataset.shown })
  },

  reset() {
    this.clear()
    this.el.dataset.flow = "playing"
    this.steps.forEach(s => { s.dataset.state = "idle"; delete s.dataset.stamped })
    this.facts.forEach(f => { delete f.dataset.shown })
  },

  light(i) {
    const step = this.steps[i]
    if (!("flowNote" in step.dataset)) { this.current = i; this.place(i) }
    step.dataset.state = "lit"
    if (step.dataset.approval) step.dataset.stamped = "true"
  },

  // Present mode: the slide opens with nothing lit; each call of presentNext
  // shows the next step, then the next fact. It returns false when all is
  // shown, so the next click goes to the next slide.
  presentStart(fromEnd = false) {
    if (this.mq.matches) { this.presentAt = null; return this.settle() }
    this.presentShow(fromEnd ? this.parts() : 0)
  },

  parts() { return this.steps.length + this.facts.length },

  // Present mode, static: the first k parts shown, no token travel (Back).
  presentShow(k) {
    this.reset()
    const n = this.steps.length
    this.presentAt = k
    this.current = null
    this.steps.forEach((step, i) => {
      if (i >= k) return
      step.dataset.state = "lit"
      if (step.dataset.approval) step.dataset.stamped = "true"
      if (!("flowNote" in step.dataset)) this.current = i
    })
    this.facts.forEach((f, j) => { if (n + j < k) f.dataset.shown = "true" })
    if (k >= this.parts()) this.el.dataset.flow = "done"
    if (this.token) {
      this.token.style.transition = "none"
      if (this.current == null) this.token.style.transform = ""
      else this.place(this.current)
      void this.token.offsetWidth
      this.token.style.transition = ""
    }
  },

  // Back one part; false at the first part, so Back goes to the slide before.
  presentPrev() {
    if (this.presentAt == null || this.mq.matches || this.presentAt <= 0) return false
    this.presentShow(this.presentAt - 1)
    return true
  },

  presentNext() {
    if (this.presentAt == null || this.mq.matches) return false
    const n = this.steps.length
    if (this.presentAt >= n + this.facts.length) return false
    if (this.presentAt < n) this.light(this.presentAt)
    else this.facts[this.presentAt - n].dataset.shown = "true"
    this.presentAt += 1
    if (this.presentAt === n + this.facts.length) this.el.dataset.flow = "done"
    return true
  },

  presentEnd() {
    if (this.presentAt == null) return
    this.presentAt = null
    this.played = true
    this.settle()
  },

  play() {
    if (this.mq.matches) return this.settle()
    this.reset()

    let at = 250
    this.steps.forEach((step, i) => {
      this.later(at, () => this.light(i))
      at += step.dataset.approval ? 1600 : (this.facts.length ? 900 : 600)
    })
    this.facts.forEach(fact => {
      this.later(at, () => { fact.dataset.shown = "true" })
      at += 450
    })
    this.later(at, () => { this.el.dataset.flow = "done" })
  },

  place(i) {
    if (i == null || !this.token || !this.track) return
    const marker = this.steps[i]?.querySelector("[data-flow-marker]")
    if (!marker) return
    const box = this.track.getBoundingClientRect()
    const m = marker.getBoundingClientRect()
    const x = m.left - box.left + m.width / 2
    const y = m.top - box.top + m.height / 2
    this.token.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) rotate(${i * 72}deg)`
  },

  later(ms, fun) { this.timers.push(setTimeout(fun, ms)) },

  clear() {
    this.timers.forEach(clearTimeout)
    this.timers = []
  },

  destroyed() {
    this.clear()
    this.observer?.disconnect()
    window.removeEventListener("resize", this.onResize)
    this.mq?.removeEventListener("change", this.onChange)
    this.replayButton?.removeEventListener("click", this.onReplay)
  },
}

// One turn, three lanes (TalesForgeWeb.TeamCallTypes): the player's line, the
// Jev card, the Elixir roll, the GM's prose and the parchment out to the
// player appear one after another (about 6 s). Plays once when scrolled into
// view, with a Replay button. Every [data-at] element is visible in the
// server's static diagram; only while playing are the ones not yet reached
// hidden (app.css, under data-motion="full").
const LANE_STEPS = [200, 1100, 2200, 3600, 5300]
const LANES_DONE = 6200

export const TeamLanes = {
  mounted() {
    this.timers = []
    this.mq = reducedMotion()
    this.parts = [...this.el.querySelectorAll("[data-at]")]

    this.onReplay = () => this.play()
    this.replayButton = this.el.querySelector("[data-lanes-replay]")
    this.replayButton?.addEventListener("click", this.onReplay)

    this.onChange = () => this.mq.matches && this.settle()
    this.mq.addEventListener("change", this.onChange)

    if (this.mq.matches || !("IntersectionObserver" in window)) return this.settle()

    this.observer = new IntersectionObserver(entries => {
      if (!entries.some(e => e.isIntersecting)) return
      this.observer.disconnect()
      this.play()
    }, {threshold: 0.3})
    this.observer.observe(this.el)
  },

  // Static, numbered diagram: everything shown.
  settle() {
    this.clear()
    this.el.dataset.lanes = "static"
    this.parts.forEach(p => { delete p.dataset.shown })
  },

  play() {
    if (this.mq.matches) return this.settle()
    this.clear()
    this.parts.forEach(p => { delete p.dataset.shown })
    this.el.dataset.lanes = "playing"

    LANE_STEPS.forEach((at, i) => {
      this.later(at, () => {
        this.parts.forEach(p => { if (p.dataset.at === String(i + 1)) p.dataset.shown = "true" })
      })
    })
    this.later(LANES_DONE, () => { this.el.dataset.lanes = "done" })
  },

  later(ms, fun) { this.timers.push(setTimeout(fun, ms)) },

  clear() {
    this.timers.forEach(clearTimeout)
    this.timers = []
  },

  destroyed() {
    this.clear()
    this.observer?.disconnect()
    this.mq?.removeEventListener("change", this.onChange)
    this.replayButton?.removeEventListener("click", this.onReplay)
  },
}

// Old links to the presentation's sections pointed at /team#section. The
// server never sees the fragment, so on /team this hook checks it: when it
// is one of the presentation's anchors (data-anchors, from
// TeamPresentationLive.anchors/0), the URL is replaced with
// /team/presentation#section, so Back skips the landing page. Anything else
// (the landing page's own anchors, no fragment) stays put.
export const presentationTarget = (hash, anchors, target, aliases = {}) => {
  const anchor = decodeURIComponent((hash || "").replace(/^#/, ""))
  if (anchor && Object.prototype.hasOwnProperty.call(aliases, anchor)) return aliases[anchor]
  return anchor && anchors.includes(anchor) ? `${target}#${anchor}` : null
}

export const TeamAnchorRedirect = {
  mounted() {
    this.anchors = JSON.parse(this.el.dataset.anchors || "[]")
    this.aliases = JSON.parse(this.el.dataset.aliases || "{}")
    this.onHash = () => this.check()
    window.addEventListener("hashchange", this.onHash)
    this.check()
  },

  check() {
    const to = presentationTarget(
      window.location.hash,
      this.anchors,
      this.el.dataset.target,
      this.aliases,
    )
    if (to) window.location.replace(to)
  },

  destroyed() {
    window.removeEventListener("hashchange", this.onHash)
  },
}

// @mention suggestions in a board comment box (TalesForge.Board.Mentions).
// Type @ and letters: a list of matching names opens under the box. Arrow
// keys choose, Enter or Tab inserts, Escape closes. A click also inserts.
export const mentionQuery = (text, caret) => {
  const m = /(^|[^\w@.])@([\p{L}]*)$/u.exec(text.slice(0, caret))
  return m ? {start: caret - m[2].length - 1, query: m[2].toLowerCase().normalize("NFD").replace(/[^a-z]/g, "")} : null
}

export const MentionSuggest = {
  mounted() {
    const box = this.el
    const list = document.getElementById(box.getAttribute("aria-controls"))
    const handles = JSON.parse(box.dataset.handles || "[]")
    let items = [], active = 0, at = null
    const close = () => { list.hidden = true; items = []; box.removeAttribute("aria-activedescendant") }
    const insert = name => {
      const end = box.selectionStart
      box.value = box.value.slice(0, at.start) + "@" + name + " " + box.value.slice(end)
      const pos = at.start + name.length + 2
      box.setSelectionRange(pos, pos)
      close()
      box.focus()
    }
    const draw = () => {
      list.innerHTML = ""
      items.forEach((name, i) => {
        const li = document.createElement("li")
        li.id = `${list.id}-${i}`
        li.setAttribute("role", "option")
        li.setAttribute("aria-selected", String(i === active))
        li.className = "cursor-pointer px-3 py-2" + (i === active ? " bg-[var(--paper-margin)] font-semibold" : "")
        li.textContent = "@" + name
        li.addEventListener("mousedown", e => { e.preventDefault(); insert(name) })
        list.appendChild(li)
      })
      list.hidden = items.length === 0
      if (items.length) box.setAttribute("aria-activedescendant", `${list.id}-${active}`)
    }
    box.addEventListener("input", () => {
      at = mentionQuery(box.value, box.selectionStart)
      items = at ? handles.filter(h => h.startsWith(at.query)) : []
      active = 0
      draw()
    })
    box.addEventListener("keydown", e => {
      if (list.hidden || !items.length) return
      if (e.key === "ArrowDown") { active = (active + 1) % items.length; draw(); e.preventDefault() }
      else if (e.key === "ArrowUp") { active = (active - 1 + items.length) % items.length; draw(); e.preventDefault() }
      else if (e.key === "Enter" || e.key === "Tab") { insert(items[active]); e.preventDefault() }
      else if (e.key === "Escape") { close(); e.preventDefault(); e.stopPropagation() }
    })
    box.addEventListener("blur", () => setTimeout(close, 100))
  }
}

// The team chat drawer (TalesForgeWeb.TeamChatLive): keeps the newest
// message in view, grows the one-line message box with its text (up to its
// max height), and sends on Enter (Shift+Enter adds a new line). Enter while
// the @mention list is open picks a name instead (MentionSuggest handles it
// first and marks the event as handled).
export const growBox = box => {
  box.style.height = "auto"
  box.style.height = `${box.scrollHeight}px`
}

export const TeamChat = {
  mounted() {
    this.list = () => this.el.querySelector("[data-chat-scroll]")
    this.box = () => this.el.querySelector("[data-chat-input]")
    this.toBottom()
    this.onInput = e => { if (e.target.matches("[data-chat-input]")) growBox(e.target) }
    this.onKey = e => {
      if (!e.target.matches("[data-chat-input]")) return
      if (e.key !== "Enter" || e.shiftKey || e.isComposing || e.defaultPrevented) return
      e.preventDefault()
      const hasImage = e.target.form.querySelector("[data-phx-entry-ref]")
      if (e.target.value.trim() !== "" || hasImage) e.target.form.requestSubmit()
    }
    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("keydown", this.onKey)
    this.handleEvent("team_chat:sent", () => {
      const box = this.box()
      if (box) { box.value = ""; growBox(box); box.focus() }
    })
    const box = this.box()
    if (box) growBox(box)
    this.draftsCleanup = BoardDrafts.setup(this)
    this.timesCleanup = startRelativeTimes()
  },
  reconnected() { BoardDrafts.restoreAll(this.el) },
  updated() { this.toBottom() },
  toBottom() {
    const list = this.list()
    if (list) list.scrollTop = list.scrollHeight
  },
  destroyed() {
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("keydown", this.onKey)
    this.draftsCleanup?.()
    this.timesCleanup?.()
  },
}

// Relative times on card comments and in the team chat
// (TalesForgeWeb.TeamTime: the same rules, keep them in step). The server
// renders the text; every minute this writes it again for each
// time[data-team-ago] on the page. One timer for the page, however many hooks
// start it.
const STOCKHOLM = "Europe/Stockholm"
const stockholmYear = d =>
  new Intl.DateTimeFormat("en-GB", {timeZone: STOCKHOLM, year: "numeric"}).format(d)

export const relativeTime = (then, now = new Date()) => {
  const s = Math.max(Math.floor((now - then) / 1000), 0)
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)} min ago`
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`
  if (s < 2 * 86400) return "yesterday"
  if (s < 7 * 86400) return `${Math.floor(s / 86400)} days ago`
  const opts = {timeZone: STOCKHOLM, day: "numeric", month: "short"}
  if (stockholmYear(then) !== stockholmYear(now)) opts.year = "numeric"
  return new Intl.DateTimeFormat("en-GB", opts).format(then)
}

export const refreshRelativeTimes = (root = document, now = new Date()) => {
  root.querySelectorAll("time[data-team-ago][datetime]").forEach(el => {
    const then = new Date(el.getAttribute("datetime"))
    if (isNaN(then)) return
    const text = relativeTime(then, now)
    if (el.textContent !== text) el.textContent = text
  })
}

let timesUsers = 0
let timesTimer = null
export const startRelativeTimes = () => {
  if (timesUsers++ === 0) {
    refreshRelativeTimes()
    timesTimer = setInterval(() => refreshRelativeTimes(), 60_000)
  }
  let stopped = false
  return () => {
    if (stopped) return
    stopped = true
    if (--timesUsers === 0) { clearInterval(timesTimer); timesTimer = null }
  }
}

// Images on cards and in the team chat (TalesForgeWeb.TeamImages). The hook
// sits on a form with a LiveView upload. It adds pasted images and one still
// from "Capture screen" to the upload's file input. LiveView then shows the
// previews and uploads the files. The capture button shows only where the
// browser can capture the screen and the device is not a phone.
const MAX_IMAGE_BYTES = 5_000_000

export function canCaptureScreen(nav = navigator, win = window) {
  const media = nav.mediaDevices
  if (!media || typeof media.getDisplayMedia !== "function") return false
  if (/Android|iPhone|iPad|iPod|Mobi/i.test(nav.userAgent || "")) return false
  return !win.matchMedia || win.matchMedia("(pointer: fine)").matches
}

export const ImageInput = {
  mounted() {
    this.onPaste = e => {
      const files = [...(e.clipboardData?.files || [])].filter(f => f.type.startsWith("image/"))
      if (files.length === 0) return
      e.preventDefault()
      this.addFiles(files)
    }
    this.el.addEventListener("paste", this.onPaste)
    this.onCapture = () => this.capture()
    this.bindCapture()
  },
  updated() { this.bindCapture() },
  destroyed() {
    this.el.removeEventListener("paste", this.onPaste)
    this.stopStream()
  },
  bindCapture() {
    const button = this.el.querySelector("[data-capture]")
    if (!button || button.dataset.bound) return
    button.dataset.bound = "1"
    if (!canCaptureScreen()) return
    button.hidden = false
    button.addEventListener("click", this.onCapture)
  },
  fileInput() { return this.el.querySelector("input[type=file][data-phx-upload-ref]") },
  addFiles(files) {
    const input = this.fileInput()
    if (!input) return
    const transfer = new DataTransfer()
    files.forEach(f => transfer.items.add(f))
    input.files = transfer.files
    input.dispatchEvent(new Event("input", {bubbles: true}))
  },
  stopStream() {
    if (this.stream) this.stream.getTracks().forEach(t => t.stop())
    this.stream = null
  },
  // Takes one still frame of the tab, window or screen the user picks, then
  // stops the screen sharing at once. No recording is kept.
  async capture() {
    try {
      this.stream = await navigator.mediaDevices.getDisplayMedia({video: true, audio: false})
    } catch (_cancelled) {
      return
    }
    try {
      const video = document.createElement("video")
      video.muted = true
      video.playsInline = true
      video.srcObject = this.stream
      await video.play()
      await new Promise(resolve => requestAnimationFrame(() => resolve()))
      const canvas = document.createElement("canvas")
      canvas.width = video.videoWidth
      canvas.height = video.videoHeight
      canvas.getContext("2d").drawImage(video, 0, 0)
      let blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      let ext = "png"
      if (blob && blob.size > MAX_IMAGE_BYTES) {
        blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", 0.85))
        ext = "jpg"
      }
      if (!blob) return
      const stamp = new Date().toISOString().replace(/[:.]/g, "-")
      this.addFiles([new File([blob], `screen-capture-${stamp}.${ext}`, {type: blob.type})])
      const note = this.el.querySelector("textarea, input[type=text]")
      if (note) note.focus()
    } finally {
      this.stopStream()
    }
  },
}

// BoardDrafts: unsaved text on the idea board and in the team chat stays in
// localStorage, so a reconnect, a deploy or a reload does not lose it.
//   - A form with data-draft="<scope>" (for example "card:<id>", "new-idea",
//     "chat") is a draft scope. Each text box and select in it is saved on
//     every input as {value, at} under "tf:draft:<scope>:<field name>".
//     A button with data-draft-toggle="<field>" and aria-pressed (the Defer
//     toggles) is saved as "true" or "false".
//   - When a draft form shows up (page mount, a card opens, a reconnect),
//     the saved values go back into empty boxes. A form with data-draft-sync
//     (the answer boxes, whose drafts the server keeps) also gets an input
//     event, so the server state follows.
//     A [data-draft-hint] element (aria-live polite) then says "Draft restored".
//   - The server confirms a save with push_event("board_draft:saved",
//     %{scope: scope, fields: [names] | nil}): those drafts go (nil: all of
//     the scope). The chat clears its scope on "team_chat:sent".
//   - Drafts older than 7 days go when the page loads.
// The hook runs from TeamPage (the board) and TeamChat (the composer), so
// app.js needs no change. The pure functions take the storage and the time
// as arguments, so they run without a browser.
const DRAFT_PREFIX = "tf:draft:"
export const DRAFT_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000
const HINT_MS = 6000

const safeStorage = () => {
  try { return window.localStorage } catch (_e) { return null }
}

export const BoardDrafts = {
  key: (scope, field) => `${DRAFT_PREFIX}${scope}:${field}`,

  save(storage, scope, field, value, now = Date.now()) {
    if (!storage || !scope || !field) return
    const key = this.key(scope, field)
    try {
      if (value === "" || value == null) storage.removeItem(key)
      else storage.setItem(key, JSON.stringify({value: String(value), at: now}))
    } catch (_e) { /* storage full or blocked: the draft stays only on screen */ }
  },

  // The fresh drafts of a scope as {field: value}. Old or broken ones go.
  load(storage, scope, now = Date.now()) {
    const out = {}
    if (!storage) return out
    const prefix = `${DRAFT_PREFIX}${scope}:`
    for (const key of this.keys(storage)) {
      if (!key.startsWith(prefix)) continue
      const d = this.read(storage, key, now)
      if (d) out[key.slice(prefix.length)] = d.value
    }
    return out
  },

  // Removes the drafts of a scope: the fields named (a name or a prefix
  // ending in "[" such as "answers["), or every field when fields is null.
  clear(storage, scope, fields = null) {
    if (!storage) return
    const prefix = `${DRAFT_PREFIX}${scope}:`
    for (const key of this.keys(storage)) {
      if (!key.startsWith(prefix)) continue
      const field = key.slice(prefix.length)
      const hit = !fields || fields.some(f => f.endsWith("[") ? field.startsWith(f) : field === f)
      if (hit) storage.removeItem(key)
    }
  },

  // Removes every draft older than 7 days.
  prune(storage, now = Date.now()) {
    if (!storage) return
    for (const key of this.keys(storage)) if (key.startsWith(DRAFT_PREFIX)) this.read(storage, key, now)
  },

  read(storage, key, now) {
    try {
      const d = JSON.parse(storage.getItem(key))
      if (d && typeof d.value === "string" && now - d.at <= DRAFT_MAX_AGE_MS) return d
    } catch (_e) { /* broken entry: remove it below */ }
    storage.removeItem(key)
    return null
  },

  keys(storage) {
    const keys = []
    for (let i = 0; i < storage.length; i++) keys.push(storage.key(i))
    return keys
  },

  // Puts the saved drafts back into one form. Returns true when something
  // came back. A box the founder already typed in keeps its text.
  restoreForm(form, storage = safeStorage(), now = Date.now()) {
    const scope = form.dataset.draft
    if (!scope || this.restored.has(form)) return false
    this.restored.add(form)
    const drafts = this.load(storage, scope, now)
    let restored = false
    // Toggles first: a click on a button in a form that waits for a change
    // reply does nothing.
    const entries = Object.entries(drafts)
      .sort(([a], [b]) => Number(b.startsWith("deferred[")) - Number(a.startsWith("deferred[")))
    for (const [field, value] of entries) {
      const toggle = form.querySelector(`[data-draft-toggle="${CSS.escape(field)}"]`)
      if (toggle) {
        if (toggle.getAttribute("aria-pressed") !== value) { toggle.click(); restored = true }
        continue
      }
      const box = form.elements.namedItem(field)
      if (!box || box.disabled || box.readOnly || box.type === "hidden") continue
      if (box.value !== "" && box.value !== box.defaultValue) continue
      if (box.value === value) continue
      box.value = value
      // Only a form whose server keeps the value (data-draft-sync, the answer
      // boxes) gets the input event: LiveView puts the server's value back
      // into an unfocused box when it acknowledges a change.
      if (form.hasAttribute("data-draft-sync")) box.dispatchEvent(new Event("input", {bubbles: true}))
      restored = true
    }
    if (restored) this.hint(form)
    return restored
  },

  // The forms already restored (kept in JS: a LiveView patch would remove a
  // marker attribute).
  restored: new WeakSet(),

  restoreAll(root) {
    this.restored = new WeakSet()
    root.querySelectorAll("form[data-draft]").forEach(f => this.restoreForm(f))
  },

  // The boxes with phx-update="ignore" keep their text through LiveView
  // patches (a patch puts the server's empty value into an unfocused box).
  // After a confirmed save, empty the saved ones here.
  emptyBoxes(root, scope, fields) {
    root.querySelectorAll("form[data-draft]").forEach(form => {
      if (form.dataset.draft !== scope) return
      form.querySelectorAll("[phx-update=ignore][name]").forEach(box => {
        const hit = !fields || fields.some(f => f.endsWith("[") ? box.name.startsWith(f) : box.name === f)
        if (!hit) return
        if (box.tagName === "SELECT") box.selectedIndex = 0
        else box.value = ""
      })
    })
  },

  hint(form) {
    const hint = form.querySelector("[data-draft-hint]") ||
      form.closest("[data-draft-hint-root]")?.querySelector("[data-draft-hint]")
    if (!hint) return
    hint.textContent = "Draft restored"
    clearTimeout(hint._draftTimer)
    hint._draftTimer = setTimeout(() => { hint.textContent = "" }, HINT_MS)
  },

  // Wires a hook: save on input and toggle clicks, restore when a draft form
  // shows up, clear on the server's confirmation.
  setup(hook) {
    const storage = safeStorage()
    if (!storage) return () => {}
    this.prune(storage)
    const root = hook.el

    const onInput = e => {
      const form = e.target.form
      if (!form?.dataset.draft || !e.target.name || !e.isTrusted) return
      this.save(storage, form.dataset.draft, e.target.name, e.target.value)
    }
    const onClick = e => {
      const toggle = e.target.closest?.("[data-draft-toggle]")
      const form = toggle?.closest("form[data-draft]")
      if (!form || !e.isTrusted) return
      // The click flips the state: save the new one.
      const next = toggle.getAttribute("aria-pressed") === "true" ? "false" : "true"
      this.save(storage, form.dataset.draft, toggle.dataset.draftToggle, next)
    }
    root.addEventListener("input", onInput)
    root.addEventListener("change", onInput)
    root.addEventListener("click", onClick)

    root.querySelectorAll("form[data-draft]").forEach(f => this.restoreForm(f, storage))
    const observer = new MutationObserver(() => {
      root.querySelectorAll("form[data-draft]").forEach(f => this.restoreForm(f, storage))
    })
    observer.observe(root, {childList: true, subtree: true})

    hook.handleEvent("board_draft:saved", ({scope, fields}) => {
      this.clear(storage, scope, fields || null)
      this.emptyBoxes(root, scope, fields || null)
    })
    hook.handleEvent("team_chat:sent", () => this.clear(storage, "chat"))

    return () => {
      observer.disconnect()
      root.removeEventListener("input", onInput)
      root.removeEventListener("change", onInput)
      root.removeEventListener("click", onClick)
    }
  },
}

// The open card in the URL (#idea-<id>) and the scroll position. The board
// component pushes "board:card" with the id when a card opens and with nil
// when it closes; a reconnect (the component mounts again with no card open)
// sends nothing, so the hash stays. On mount and after a reconnect, the card
// in the hash opens again and the page and the card scroll back to where
// they were (sessionStorage, this tab only).
const SCROLL_KEY = "tf:board-scroll"
export const cardIdFromHash = hash => {
  const m = /^#idea-([0-9a-f-]{8,})$/i.exec(hash || "")
  return m ? m[1] : null
}

const setupCardUrl = hook => {
  const board = () => hook.el.querySelector("[data-board-target]")
  if (!board()) return () => {}
  let pendingPanelScroll = null

  const panel = () => document.getElementById("board-modal-panel")
  const saveScroll = () => {
    try {
      sessionStorage.setItem(SCROLL_KEY, JSON.stringify({
        y: window.scrollY, card: cardIdFromHash(location.hash), panel: panel()?.scrollTop || 0,
      }))
    } catch (_e) { /* sessionStorage blocked */ }
  }
  let timer = null
  const onScroll = () => { clearTimeout(timer); timer = setTimeout(saveScroll, 200) }
  window.addEventListener("scroll", onScroll, {passive: true})
  hook.el.addEventListener("scroll", onScroll, {passive: true, capture: true})

  hook.handleEvent("board:card", ({id}) => {
    const url = new URL(location.href)
    url.hash = id ? `idea-${id}` : ""
    history.replaceState(history.state, "", url.toString().replace(/#$/, ""))
    if (!id) saveScroll()
  })

  const reopen = () => {
    const id = cardIdFromHash(location.hash)
    let saved = {}
    try { saved = JSON.parse(sessionStorage.getItem(SCROLL_KEY)) || {} } catch (_e) { saved = {} }
    if (typeof saved.y === "number") window.scrollTo(0, saved.y)
    if (!id || document.getElementById("board-modal")) return
    pendingPanelScroll = saved.card === id ? saved.panel : null
    hook.pushEventTo(board().dataset.boardTarget, "open", {card_id: id, restore: "true"})
  }
  hook.cardUrlRestore = reopen

  const observer = new MutationObserver(() => {
    const p = panel()
    if (p && pendingPanelScroll != null) { p.scrollTop = pendingPanelScroll; pendingPanelScroll = null }
  })
  observer.observe(hook.el, {childList: true, subtree: true})
  reopen()

  return () => {
    observer.disconnect()
    window.removeEventListener("scroll", onScroll)
    hook.el.removeEventListener("scroll", onScroll, {capture: true})
  }
}
