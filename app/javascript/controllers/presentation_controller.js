import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  connect() { document.body.classList.toggle("hide-proposals", localStorage.getItem("hide-proposals") === "true") }
  async fullscreen() {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen() }
    catch (_) { /* Browser-level fullscreen remains available. */ }
  }
  toggle(event) {
    const hidden = document.body.classList.toggle("hide-proposals")
    localStorage.setItem("hide-proposals", String(hidden))
    event.currentTarget.textContent = hidden ? "Pokaż propozycje" : "Ukryj propozycje"
  }
}
