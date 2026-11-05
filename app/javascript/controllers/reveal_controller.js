import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["grid", "button"]
  play() {
    this.gridTarget.classList.remove("revealed")
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.gridTarget.querySelectorAll(".bingo-cell").forEach((cell, i) => { cell.style.transitionDelay = reduced ? "0ms" : `${i * 140}ms` })
    this.frame = requestAnimationFrame(() => { this.gridTarget.offsetHeight; this.gridTarget.classList.add("revealed") })
    this.buttonTarget.textContent = "Odtwórz ten sam wynik ponownie ↻"
  }
  disconnect() { cancelAnimationFrame(this.frame) }
}
