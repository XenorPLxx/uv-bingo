import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["content", "connection", "feedback", "dialog", "dialogMeta", "dialogTitle", "dialogActions", "dialogVoters"]
  static values = { eventId: Number, url: String, revision: Number, phase: String }
  connect() {
    this.compact = window.matchMedia("(max-width: 760px)")
    this.lastSync = Date.now()
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create({ channel: "EventChannel", event_id: this.eventIdValue }, {
      connected: () => { this.online = true; this.refresh() },
      disconnected: () => { this.online = false; this.showStatus("Ponowne łączenie…") },
      received: () => this.queueRefresh()
    })
    // Pushes carry changes. Polling covers a dropped connection and otherwise acts as a slow safety resync.
    this.timer = setInterval(() => { if (!this.online || Date.now() - this.lastSync >= 60000) this.refresh() }, 15000)
    this.visibility = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.visibility)
  }
  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.pushTimer)
    this.pushTimer = null
    clearTimeout(this.feedbackTimer)
    document.removeEventListener("visibilitychange", this.visibility)
    this.request?.abort()
    this.mutation?.abort()
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }
  // Folds pushes arriving while a refresh is scheduled into it. The random delay spreads viewers' requests.
  queueRefresh(delay = 150 + Math.random() * 450) {
    if (!this.element.isConnected || this.pushTimer) return
    this.pushTimer = setTimeout(() => {
      this.pushTimer = null
      this.refresh()
    }, delay)
  }

  showStatus(text) {
    // An archived board no longer changes, so connection details would only distract.
    this.connectionTarget.textContent = this.phaseValue === "archived" ? "ZAKOŃCZONE" : text
  }

  async refresh() {
    if (document.hidden || !this.element.isConnected) return
    if (this.loading) { this.refreshPending = true; return }
    this.loading = true
    this.request = new AbortController()
    const timeout = setTimeout(() => this.request.abort(), 8000)
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("revision", this.revisionValue)
    url.searchParams.set("phase", this.phaseValue)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal: this.request.signal })
      if (response.status === 404) { window.location.replace("/?removed=1"); return }
      if (!response.ok) throw new Error("state request failed")
      const data = await response.json()
      this.lastSync = Date.now()
      if (data.phase !== this.phaseValue) { window.location.reload(); return }
      if (data.revision !== this.revisionValue) {
        const focusedControl = document.activeElement?.dataset.boardControl
        const focusInDialog = this.dialogTarget.contains(document.activeElement)
        if (data.html) {
          const before = this.snapshot()
          this.contentTarget.innerHTML = data.html
          this.animateChanges(before)
          if (this.dialogTarget.open && !this.renderDialog()) this.dialogTarget.close()
        }
        const scope = focusInDialog ? this.dialogTarget : this.contentTarget
        if (focusedControl) scope.querySelector(`[data-board-control="${focusedControl}"]`)?.focus({ preventScroll: true })
        this.revisionValue = data.revision
        this.phaseValue = data.phase
      }
      this.showStatus(this.online ? "● POŁĄCZONO NA ŻYWO" : "● ODŚWIEŻANIE CO 15 S")
    } catch (error) {
      if (this.element.isConnected) this.showStatus("Brak aktualizacji — ponawiamy połączenie…")
    } finally {
      clearTimeout(timeout)
      this.loading = false
      if (this.refreshPending) { this.refreshPending = false; this.refresh() }
    }
  }
  async submit(event) {
    event.preventDefault()
    if (this.saving) return
    const form = event.currentTarget
    this.saving = true
    form.setAttribute("aria-busy", "true")
    this.mutation = new AbortController()
    const timeout = setTimeout(() => this.mutation.abort(), 10000)
    try {
      const response = await fetch(form.action, {
        method: "POST", body: new FormData(form), headers: { Accept: "application/json" }, signal: this.mutation.signal
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || (response.status === 429 ? "Zbyt wiele kliknięć. Spróbuj za chwilę." : "Nie zapisano zmiany. Odśwież stronę i spróbuj ponownie."))
      this.feedback(data.message)
    } catch (error) {
      this.feedback(error.name === "AbortError" ? "Nie udało się potwierdzić zapisu. Sprawdź aktualną planszę przed ponownym kliknięciem." : error.message, true)
    } finally {
      clearTimeout(timeout)
      form.removeAttribute("aria-busy")
      this.saving = false
      this.refresh()
    }
  }
  snapshot() {
    const cells = new Map(Array.from(this.contentTarget.querySelectorAll(".bingo-cell"), cell => [cell.dataset.position, {
      mark: cell.dataset.mark,
      winning: cell.classList.contains("winning-cell"),
      counts: this.counts(cell)
    }]))
    return { cells, lines: Number(this.contentTarget.querySelector(".bingo-celebration")?.dataset.lines || 0) }
  }

  counts(cell) {
    return Object.fromEntries(["question", "cross"].map(mark => [mark, Number(cell.querySelector(`.${mark}-count .proposal-total`)?.textContent || 0)]))
  }

  // Admin decisions stamp the cell, community suggestions pulse their counter and newly completed lines sweep.
  // The reduced-motion stylesheet turns all of these off.
  animateChanges(before) {
    let newlyWinning = 0
    for (const cell of this.contentTarget.querySelectorAll(".bingo-cell")) {
      const previous = before.cells.get(cell.dataset.position)
      if (!previous) continue
      if (cell.dataset.mark !== previous.mark) {
        // A decision starts a new cell revision, so the reset suggestion counters are not pulsed.
        cell.classList.add(cell.dataset.mark === "blank" ? "mark-cleared" : "mark-set")
      } else {
        const counts = this.counts(cell)
        for (const mark of ["question", "cross"]) {
          if (counts[mark] === previous.counts[mark]) continue
          cell.querySelector(`.${mark}-count`)?.classList.add(counts[mark] > previous.counts[mark] ? "count-up" : "count-down")
        }
      }
      if (cell.classList.contains("winning-cell") && !previous.winning) {
        cell.style.setProperty("--win-delay", `${newlyWinning++ * 120}ms`)
        cell.classList.add("win-new")
      }
    }
    const celebration = this.contentTarget.querySelector(".bingo-celebration")
    if (celebration && Number(celebration.dataset.lines) > before.lines) celebration.classList.add("celebrate")
  }

  openCell(event) {
    this.clearFeedback()
    this.dialogPosition = event.currentTarget.closest(".bingo-cell").dataset.position
    if (this.renderDialog()) this.dialogTarget.showModal()
  }

  // On phones the cells are too small for their controls, so tapping anywhere opens the details instead.
  openFromCell(event) {
    if (!this.compact.matches || event.target.closest("button, a, form")) return
    this.openCell(event)
  }

  closeDialog() { this.dialogTarget.close() }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  dialogClosed() {
    this.clearFeedback()
    this.contentTarget.querySelector(`.bingo-cell[data-position="${this.dialogPosition}"] .cell-number`)?.focus({ preventScroll: true })
    this.dialogPosition = null
  }

  // The dialog mirrors the cell: its full text, its suggestion and decision controls, and who voted for it.
  renderDialog() {
    const cell = this.contentTarget.querySelector(`.bingo-cell[data-position="${this.dialogPosition}"]`)
    if (!cell) return false
    this.dialogTarget.dataset.mark = cell.dataset.mark
    this.dialogMetaTarget.textContent = cell.dataset.meta
    this.dialogTitleTarget.textContent = cell.querySelector(".cell-text [data-fit-text-target]").textContent
    this.dialogActionsTarget.replaceChildren(cell.querySelector(".cell-bottom").cloneNode(true))
    const voters = cell.querySelector("template.cell-voters")
    if (voters) {
      const heading = document.createElement("h3")
      heading.textContent = "Kto głosował"
      const list = document.createElement("ul")
      list.className = "voter-chips"
      list.append(voters.content.cloneNode(true))
      this.dialogVotersTarget.replaceChildren(heading, list)
    } else {
      this.dialogVotersTarget.replaceChildren()
    }
    return true
  }

  feedback(message, failed = false) {
    if (!this.element.isConnected) return
    this.clearFeedback()
    // Modal dialogs put the rest of the page behind their backdrop and make it inert.
    const target = this.feedbackTargets.find(target => this.dialogTarget.contains(target) === this.dialogTarget.open)
    target.textContent = message
    target.classList.toggle("failed", failed)
    this.feedbackTimer = setTimeout(() => this.clearFeedback(), failed ? 10000 : 3000)
  }

  clearFeedback() {
    clearTimeout(this.feedbackTimer)
    this.feedbackTargets.forEach(target => { target.textContent = "" })
  }
}
