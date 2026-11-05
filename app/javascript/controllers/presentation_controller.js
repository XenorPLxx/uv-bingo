import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["toggle"]
  connect() {
    const hidden = localStorage.getItem("hide-proposals") === "true"
    document.body.classList.toggle("hide-proposals", hidden)
    this.label(hidden)
  }
  async fullscreen() {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen() }
    catch (_) { /* Browser-level fullscreen remains available. */ }
  }
  toggle() {
    const hidden = document.body.classList.toggle("hide-proposals")
    localStorage.setItem("hide-proposals", String(hidden))
    this.label(hidden)
  }
  label(hidden) {
    if (this.hasToggleTarget) this.toggleTarget.textContent = hidden ? "Pokaż propozycje" : "Ukryj propozycje"
  }
}
