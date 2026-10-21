import { Controller } from "@hotwired/stimulus"

// Opens the native dialog without changing the current diary until the form is submitted.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
    this.dialogTarget.querySelector('input[type="date"]')?.focus()
  }

  close() {
    this.dialogTarget.close()
  }
}
