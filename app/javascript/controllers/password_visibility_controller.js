import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "showIcon", "hideIcon"]

  toggle() {
    const visible = this.inputTarget.type === "password"
    this.inputTarget.type = visible ? "text" : "password"
    this.buttonTarget.setAttribute("aria-pressed", String(visible))
    this.buttonTarget.setAttribute("aria-label", visible ? "Hide password" : "Show password")
    this.buttonTarget.setAttribute("title", visible ? "Hide password" : "Show password")
    this.showIconTarget.classList.toggle("hidden", visible)
    this.hideIconTarget.classList.toggle("hidden", !visible)
  }
}
