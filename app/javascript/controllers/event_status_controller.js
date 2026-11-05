import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
export default class extends Controller {
  static values = { url: String, phase: String }
  connect() { this.timer = setInterval(() => this.refresh(), 15000) }
  disconnect() { clearInterval(this.timer); this.request?.abort() }
  async refresh() {
    if (document.hidden || this.loading) return
    this.loading = true
    this.request = new AbortController()
    const timeout = setTimeout(() => this.request.abort(), 8000)
    try {
      const response = await fetch(this.urlValue, { cache: "no-store", signal: this.request.signal })
      if (!response.ok) return
      const state = await response.json()
      if (state.phase !== this.phaseValue && !["TEXTAREA", "INPUT"].includes(document.activeElement?.tagName)) Turbo.visit(window.location.href, { action: "replace" })
    } catch (_) { /* The next refresh retries. Server-side dates always gate submissions. */ }
    finally { clearTimeout(timeout); this.loading = false }
  }
}
