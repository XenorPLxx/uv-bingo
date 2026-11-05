import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["options", "ballot", "addOption", "sidebar", "feedback", "schedule", "search", "searchForm", "searchStatus", "voters", "votersTitle", "votersCount", "votersList"]
  static values = { url: String, phase: String, revision: Number }

  connect() {
    this.queryVersion = 0
    this.requestId = 0
    this.appliedQuery = this.query
    this.searchPending = false
    this.searchError = false
    this.timer = setInterval(() => this.refresh(), 15000)
    this.visibility = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.visibility)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.searchTimer)
    this.activeSearch = null
    document.removeEventListener("visibilitychange", this.visibility)
    this.request?.abort()
    this.mutation?.abort()
  }

  async refresh() {
    if (document.hidden || this.saving || this.activeSearch || this.searchPending || this.refreshPromise || !this.element.isConnected) return
    if (document.activeElement !== this.searchTarget && this.element.contains(document.activeElement) && document.activeElement.matches("textarea, input:not([type=submit])")) return
    this.refreshPromise = this.readState({ force: this.searchError || this.query !== this.appliedQuery }).catch(() => {
      // Retry on the next poll. The server always checks voting dates and limits.
    }).finally(() => { this.refreshPromise = null })
    await this.refreshPromise
  }

  get query() { return this.searchTarget.value.slice(0, 100) }

  queueSearch(event) {
    clearTimeout(this.searchTimer)
    this.queryVersion += 1
    this.searchPending = true
    if (!this.saving) this.request?.abort()
    if (event?.isComposing) return
    this.searchTimer = setTimeout(() => this.performSearch(), 300)
  }

  searchNow(event) {
    event.preventDefault()
    this.queueSearch()
    clearTimeout(this.searchTimer)
    this.performSearch()
  }

  async performSearch() {
    if (!this.element.isConnected || this.saving) return
    this.searchPending = false
    const task = Symbol()
    const version = this.queryVersion
    this.activeSearch = task
    this.request?.abort()
    this.optionsTarget.setAttribute("aria-busy", "true")
    this.searchStatusTarget.textContent = "Wyszukiwanie…"
    try {
      await this.readState({ force: true, search: true })
    } catch (_) {
      if (this.activeSearch === task && version === this.queryVersion && this.element.isConnected) {
        this.searchError = true
        this.updateVoting(null, { search: true, feedback: { message: "Nie udało się odświeżyć wyników. Spróbuj ponownie.", failed: true } })
        this.searchStatusTarget.textContent = "Nie udało się odświeżyć wyników."
      }
    } finally {
      if (this.activeSearch === task) {
        this.activeSearch = null
        this.optionsTarget.removeAttribute("aria-busy")
      }
    }
  }

  synchronizeSearch(query) {
    this.appliedQuery = query
    this.searchPending = false
    clearTimeout(this.searchTimer)
    this.element.querySelectorAll('input[type="hidden"][name="q"]').forEach(input => { input.value = query })
    const url = new URL(window.location.href)
    if (query) url.searchParams.set("q", query)
    else url.searchParams.delete("q")
    if (url.href !== window.location.href) window.history.replaceState(window.history.state, "", url)
    this.searchStatusTarget.textContent = `Wyniki: ${this.optionsTarget.querySelectorAll(".option-card").length}.`
  }

  async submit(event) {
    event.preventDefault()
    if (this.saving) return
    const form = event.currentTarget
    this.saving = true
    this.activeSearch = null
    this.optionsTarget.removeAttribute("aria-busy")
    this.element.setAttribute("aria-busy", "true")
    this.request?.abort()
    await this.refreshPromise
    this.mutation = new AbortController()
    const timeout = setTimeout(() => this.mutation.abort(), 10000)
    let feedback
    let clearDraft = false
    try {
      const body = new FormData(form)
      body.set("q", this.query)
      const response = await fetch(form.action, {
        method: "POST", body, headers: { Accept: "application/json" }, signal: this.mutation.signal
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

    this.searchError = false
    const update = { force: true, mutation: true, feedback, clearDraft, excludedOptionId: form.dataset.optionId }
    try {
      await this.readState(update)
    } catch (_) {
      this.updateVoting(null, { ...update, feedback: { message: `${feedback.message} Nie udało się odświeżyć listy.`, failed: true } })
    } finally {
      this.saving = false
      this.element.removeAttribute("aria-busy")
      if (this.searchPending && this.element.isConnected) this.queueSearch()
    }
  }

  async readState(update = {}) {
    const request = new AbortController()
    this.request = request
    const requestId = ++this.requestId
    const queryVersion = this.queryVersion
    const query = this.query
    const timeout = setTimeout(() => request.abort(), 8000)
    const url = new URL(this.urlValue, window.location.origin)
    if (query) url.searchParams.set("q", query)
    else url.searchParams.delete("q")
    url.searchParams.set("revision", this.revisionValue)
    url.searchParams.set("phase", this.phaseValue)
    if (update.force) url.searchParams.set("refresh", "1")
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (response.status === 404) { Turbo.visit("/?removed=1", { action: "replace" }); return }
      if (!response.ok) throw new Error("state request failed")
      const state = await response.json()
      if (request.signal.aborted || !this.element.isConnected || (this.saving && !update.mutation)) return
      if (requestId !== this.requestId || queryVersion !== this.queryVersion) {
        if (update.feedback) this.updateVoting(null, { ...update, search: true })
        return
      }
      if (state.html) { Turbo.visit(window.location.href, { action: "replace" }); return }
      this.updateVoting(state.voting, { ...update, clearSearchError: Boolean(state.voting) && this.searchError, search: update.search || query !== this.appliedQuery })
      if (state.voting) {
        this.searchError = false
        this.synchronizeSearch(query)
      }
      this.revisionValue = state.revision
      this.phaseValue = state.phase
    } finally {
      clearTimeout(timeout)
    }
  }

  updateVoting(voting, { feedback, clearDraft = false, excludedOptionId, search = false, clearSearchError = false } = {}) {
    if (!this.element.isConnected || (!voting && !feedback && !clearSearchError)) return
    const viewport = this.captureViewport(excludedOptionId, search)
    const focused = document.activeElement
    const input = this.addOptionTarget.querySelector("textarea")
    if (input) this.draft = input.value
    if (clearDraft) this.draft = ""

    if (voting) {
      this.optionsTarget.innerHTML = voting.options
      // An open voter list follows the refreshed votes, or closes when the option has none left.
      if (this.hasVotersTarget && this.votersTarget.open && !this.renderVoters()) this.votersTarget.close()
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
      }
    }
    if (clearDraft && input?.isConnected) {
      input.value = ""
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (clearSearchError) this.feedbackTarget.replaceChildren()
    if (feedback) {
      const message = document.createElement("div")
      message.className = `flash ${feedback.failed ? "alert" : "notice"}`
      message.textContent = feedback.message
      this.feedbackTarget.replaceChildren(message)
    }

    if (focused?.id && !focused.isConnected) document.getElementById(focused.id)?.focus({ preventScroll: true })
    this.sidebarTarget.scrollTop = viewport.sidebarScroll
    const anchor = viewport.anchors.find(({ id }) => document.getElementById(id))
    if (viewport.searchTop !== null) {
      window.scrollBy({ top: this.searchFormTarget.getBoundingClientRect().top - viewport.searchTop, behavior: "instant" })
    } else if (anchor) {
      const delta = document.getElementById(anchor.id).getBoundingClientRect().top - anchor.top
      window.scrollBy({ top: delta, behavior: "instant" })
    } else {
      window.scrollTo({ left: viewport.x, top: viewport.y, behavior: "instant" })
    }
  }

  openVoters(event) {
    if (!this.hasVotersTarget) return
    this.votersOptionId = event.currentTarget.dataset.optionId
    if (this.renderVoters()) this.votersTarget.showModal()
  }

  closeVoters() { this.votersTarget.close() }

  closeVotersOnBackdrop(event) {
    if (event.target === this.votersTarget) this.votersTarget.close()
  }

  votersClosed() {
    // The opening button may have been replaced by a refresh while the dialog was open.
    document.getElementById(`option-${this.votersOptionId}-count`)?.focus({ preventScroll: true })
    this.votersOptionId = null
  }

  renderVoters() {
    const names = document.getElementById(`option-${this.votersOptionId}-voters`)
    if (!names) return false
    this.votersTitleTarget.textContent = names.dataset.title
    this.votersListTarget.replaceChildren(names.content.cloneNode(true))
    this.votersCountTarget.textContent = `KTO GŁOSOWAŁ · ${this.votersListTarget.children.length}`
    return true
  }

  captureViewport(excludedOptionId, search) {
    const changedRow = document.getElementById(`option-${excludedOptionId}`)
    const neighbour = changedRow?.nextElementSibling || changedRow?.previousElementSibling
    const anchors = Array.from(this.optionsTarget.querySelectorAll(".option-card")).filter(row => row !== changedRow).map(row => ({ id: row.id, top: row.getBoundingClientRect().top, bottom: row.getBoundingClientRect().bottom })).filter(row => row.bottom > 0 && row.top < window.innerHeight)
    // Keep the neighbouring row steady when the clicked proposal changes rank.
    anchors.sort((a, b) => Number(b.id === neighbour?.id) - Number(a.id === neighbour?.id))
    return { anchors, searchTop: search ? this.searchFormTarget.getBoundingClientRect().top : null, x: window.scrollX, y: window.scrollY, sidebarScroll: this.sidebarTarget.scrollTop }
  }
}
