import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["grid", "button", "status"]
  play() {
    this.cancelAnimations()
    this.gridTarget.classList.add("revealed")
    this.buttonTarget.textContent = "Odtwórz ten sam wynik ponownie ↻"
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reduced) {
      this.statusTarget.textContent = "Plansza odsłonięta. Animacje są wyłączone w ustawieniach urządzenia."
      return
    }
    this.statusTarget.textContent = "Odsłanianie planszy…"
    const animations = Array.from(this.gridTarget.querySelectorAll(".bingo-cell"), (cell, i) => cell.animate(
      [{ opacity: 0, transform: "rotateY(90deg)" }, { opacity: 1, transform: "rotateY(0deg)" }],
      { duration: 450, delay: i * 140, easing: "ease", fill: "both" }
    ))
    this.animations = animations
    Promise.all(animations.map(animation => animation.finished)).then(() => {
      if (this.animations !== animations) return
      this.statusTarget.textContent = "Plansza odsłonięta."
      this.cancelAnimations()
    }).catch(() => { /* Replaying or leaving cancels the previous animation. */ })
  }
  cancelAnimations() {
    this.animations?.forEach(animation => animation.cancel())
    this.animations = []
  }
  disconnect() { this.cancelAnimations() }
}
