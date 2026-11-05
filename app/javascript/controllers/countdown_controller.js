import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["label"]
  static values = { opens: String, closes: String }
  connect() { this.original = this.labelTarget.textContent; this.update(); this.timer = setInterval(() => this.update(), 1000) }
  disconnect() { clearInterval(this.timer) }
  update() {
    const now = Date.now(), opening = Date.parse(this.opensValue), closing = Date.parse(this.closesValue)
    const remaining = Math.floor(((now < opening ? opening : closing) - now) / 1000)
    if (remaining <= 0) { this.labelTarget.textContent = this.original; return }
    const days = Math.floor(remaining / 86400), hours = Math.floor(remaining % 86400 / 3600), minutes = Math.floor(remaining % 3600 / 60)
    this.labelTarget.textContent = `${now < opening ? "Start za" : "Do końca"}: ${days ? `${days} dni · ` : ""}${hours} godz. ${minutes} min.`
  }
}
