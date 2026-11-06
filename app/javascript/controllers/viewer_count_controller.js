import { Controller } from "@hotwired/stimulus"

// How many pages have this event open, as pushed over the board's live connection.
export default class extends Controller {
  static targets = ["count"]

  update({ detail: { count } }) {
    this.element.hidden = !count
    if (count) this.countTarget.textContent = count === 1 ? "1 oglądający" : `${count} oglądających`
  }
}
