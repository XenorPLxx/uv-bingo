import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["options", "ballot", "addOption", "sidebar", "feedback", "schedule"]
  static values = { url: String, phase: String, revision: Number }

  connect() {
    this.timer = setInterval(() => this.refresh(), 15000)
    this.visibility = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.visibility)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.visibility)
    this.request?.abort()
    this.mutation?.abort()
  }

  async refresh() {
    if (document.hidden || this.saving || this.refreshPromise || !this.element.isConnected) return
    if (this.element.contains(document.activeElement) && document.activeElement.matches("textarea, input:not([type=submit])")) return
    this.refreshPromise = this.readState().catch(() => {
      // Retry on the next poll. The server always checks voting dates and limits.
    }).finally(() => { this.refreshPromise = null })
    await this.refreshPromise
  }

  async submit(event) {
    event.preventDefault()
    if (this.saving) return
    const form = event.currentTarget
    this.saving = true
    this.element.setAttribute("aria-busy", "true")
    this.request?.abort()
    await this.refreshPromise
    this.mutation = new AbortController()
    const timeout = setTimeout(() => this.mutation.abort(), 10000)
    let feedback
    let clearDraft = false
    try {
      const response = await fetch(form.action, {
        method: "POST", body: new FormData(form), headers: { Accept: "application/json" }, signal: this.mutation.signal
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || (response.status === 429 ? "Zbyt wiele kliknięć. Spróbuj za chwilę." : "Nie zapisano zmiany. Odśwież stronę i spróbuj ponownie."))
      feedback = { message: data.message, failed: false }
      clearDraft = form.dataset.votingKind === "proposal"
    } catch (error) {
      feedback = {
        message: error.name === "AbortError" ? "Nie udało się potwierdzić zapisu. Sprawdź liczbę głosów przed ponownym kliknięciem." : error.message,
        failed: true
      }
    } finally {
      clearTimeout(timeout)
    }

    const update = { force: true, feedback, clearDraft, excludedOptionId: form.dataset.optionId }
    try {
      await this.readState(update)
    } catch (_) {
      this.updateVoting(null, { ...update, feedback: { message: `${feedback.message} Nie udało się odświeżyć listy.`, failed: true } })
    } finally {
      this.saving = false
      this.element.removeAttribute("aria-busy")
    }
  }

  async readState(update = {}) {
    this.request = new AbortController()
    const timeout = setTimeout(() => this.request.abort(), 8000)
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("revision", this.revisionValue)
    url.searchParams.set("phase", this.phaseValue)
    if (update.force) url.searchParams.set("refresh", "1")
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal: this.request.signal })
      if (response.status === 404) { Turbo.visit("/?removed=1", { action: "replace" }); return }
      if (!response.ok) throw new Error("state request failed")
      const state = await response.json()
      if (!this.element.isConnected || (this.saving && !update.force)) return
      if (state.html) { Turbo.visit(window.location.href, { action: "replace" }); return }
      this.updateVoting(state.voting, update)
      this.revisionValue = state.revision
      this.phaseValue = state.phase
    } finally {
      clearTimeout(timeout)
    }
  }

  updateVoting(voting, { feedback, clearDraft = false, excludedOptionId } = {}) {
    if (!this.element.isConnected || (!voting && !feedback)) return
    const viewport = this.captureViewport(excludedOptionId)
    const focused = document.activeElement
    const input = this.addOptionTarget.querySelector("textarea")
    if (input) this.draft = input.value
    if (clearDraft) this.draft = ""

    if (voting) {
      this.optionsTarget.innerHTML = voting.options
      this.ballotTarget.innerHTML = voting.ballot
      this.scheduleTarget.innerHTML = voting.schedule
      // Keep the existing form and its draft/preview while it remains available.
      if (!voting.can_add || !input) {
        this.addOptionTarget.innerHTML = voting.add_option
        const restored = this.addOptionTarget.querySelector("textarea")
        if (restored) {
          restored.value = this.draft || ""
          queueMicrotask(() => restored.dispatchEvent(new Event("input", { bubbles: true })))
        }
      } else {
        const counter = document.createRange().createContextualFragment(voting.add_option).querySelector(".authored-option-count")
        if (counter) this.addOptionTarget.querySelector(".authored-option-count")?.replaceWith(counter)
      }
    }
    if (clearDraft && input?.isConnected) {
      input.value = ""
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (feedback) {
      const message = document.createElement("div")
      message.className = `flash ${feedback.failed ? "alert" : "notice"}`
      message.textContent = feedback.message
      this.feedbackTarget.replaceChildren(message)
    }

    if (focused?.id && !focused.isConnected) document.getElementById(focused.id)?.focus({ preventScroll: true })
    this.sidebarTarget.scrollTop = viewport.sidebarScroll
    const anchor = viewport.anchors.find(({ id }) => document.getElementById(id))
    if (anchor) {
      const delta = document.getElementById(anchor.id).getBoundingClientRect().top - anchor.top
      window.scrollBy({ top: delta, behavior: "instant" })
    } else {
      window.scrollTo({ left: viewport.x, top: viewport.y, behavior: "instant" })
    }
  }

  captureViewport(excludedOptionId) {
    const changedRow = document.getElementById(`option-${excludedOptionId}`)
    const neighbour = changedRow?.nextElementSibling || changedRow?.previousElementSibling
    const anchors = Array.from(this.optionsTarget.querySelectorAll(".option-card")).filter(row => row !== changedRow).map(row => ({ id: row.id, top: row.getBoundingClientRect().top, bottom: row.getBoundingClientRect().bottom })).filter(row => row.bottom > 0 && row.top < window.innerHeight)
    // Keep the neighbouring row steady when the clicked proposal changes rank.
    anchors.sort((a, b) => Number(b.id === neighbour?.id) - Number(a.id === neighbour?.id))
    return { anchors, x: window.scrollX, y: window.scrollY, sidebarScroll: this.sidebarTarget.scrollTop }
  }
}
