import { Controller } from "@hotwired/stimulus"

// Keep the complete prediction readable inside its allocated row, including at 1080p.
export default class extends Controller {
  static targets = ["text"]
  connect() {
    this.observer = new ResizeObserver(() => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.fit())
    })
    this.observer.observe(this.element)
    this.fit()
  }
  disconnect() { this.observer.disconnect(); cancelAnimationFrame(this.frame) }
  fit() {
    this.textTargets.forEach(text => {
      text.style.fontSize = ""
      let size = parseFloat(getComputedStyle(text).fontSize)
      const available = text.parentElement.clientHeight - 8
      while (text.offsetHeight > available && size > 12) {
        size -= 0.5
        text.style.fontSize = `${size}px`
      }
    })
  }
}
