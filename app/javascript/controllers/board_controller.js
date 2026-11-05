import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["content", "connection"]
  static values = { eventId: Number, url: String, revision: Number, phase: String }
  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create({ channel: "EventChannel", event_id: this.eventIdValue }, {
      connected: () => { this.online = true; this.refresh() },
      disconnected: () => { this.online = false; this.connectionTarget.textContent = "Ponowne łączenie…" },
      received: () => this.refresh()
    })
    this.timer = setInterval(() => this.refresh(), 15000)
    this.visibility = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.visibility)
  }
  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.visibility)
    this.request?.abort()
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }
  async refresh() {
    if (document.hidden || this.element.querySelector("dialog[open]") || this.loading) return
    this.loading = true
    this.request = new AbortController()
    const timeout = setTimeout(() => this.request.abort(), 8000)
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: this.request.signal })
      if (!response.ok) throw new Error("state request failed")
      const data = await response.json()
      if (data.phase !== this.phaseValue || data.revision !== this.revisionValue) {
        if (data.html) this.contentTarget.innerHTML = data.html
        this.revisionValue = data.revision
        this.phaseValue = data.phase
      }
      this.connectionTarget.textContent = this.online ? "● POŁĄCZONO NA ŻYWO" : "● ODŚWIEŻANIE CO 15 S"
    } catch (error) {
      if (this.element.isConnected) this.connectionTarget.textContent = "Brak aktualizacji — ponawiamy połączenie…"
    } finally { clearTimeout(timeout); this.loading = false }
  }
  openCell(event) { this.element.querySelector(`[data-cell-dialog="${event.currentTarget.dataset.position}"]`)?.showModal() }
  closeCell(event) { event.currentTarget.closest("dialog").close(); this.refresh() }
}
