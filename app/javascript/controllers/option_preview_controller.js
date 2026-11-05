import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["input", "count", "preview"]
  update() { this.countTarget.textContent = `${Array.from(this.inputTarget.value).length}/100`; this.previewTarget.textContent = this.inputTarget.value || "Twój pomysł" }
}
