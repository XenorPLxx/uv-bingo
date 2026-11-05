import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]

  dismissOutside(event) {
    if (this.element.open && !this.element.contains(event.target)) this.element.open = false
  }

  dismissWithEscape(event) {
    if (!this.element.open) return

    const restoreFocus = this.element.contains(document.activeElement)
    this.element.open = false
    if (restoreFocus) {
      event.preventDefault()
      this.triggerTarget.focus({ preventScroll: true })
    }
  }
}
