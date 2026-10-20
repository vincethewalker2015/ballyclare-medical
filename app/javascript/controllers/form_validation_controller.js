import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "feedback"]

  submit(event) {
    let firstInvalid = null

    this.fieldTargets.forEach((field) => {
      if (!this.check(field) && !firstInvalid) firstInvalid = field
    })

    if (firstInvalid) {
      event.preventDefault()
      firstInvalid.focus()
    }
  }

  validate(event) {
    this.check(event.target)
  }

  validateOnInput(event) {
    if (event.target.getAttribute("aria-invalid") === "true") {
      this.check(event.target)
    }
  }

  check(field) {
    const valid = field.checkValidity()
    const feedback = this.feedbackTargets.find((element) =>
      element.id === `${field.id}_error`
    )

    field.classList.toggle("border-red-500", !valid)
    field.classList.toggle("ring-1", !valid)
    field.classList.toggle("ring-red-500", !valid)
    field.setAttribute("aria-invalid", String(!valid))

    if (feedback) {
      if (valid) {
        feedback.textContent = ""
        feedback.classList.add("hidden")
        field.removeAttribute("aria-describedby")
      } else {
        const label = this.element.querySelector(`label[for="${field.id}"]`)
        const name = label ? label.textContent.trim() : "This field"
        feedback.textContent = field.validity.valueMissing
          ? `${name} is required`
          : field.validity.typeMismatch
            ? "Please enter a valid email address"
            : field.validationMessage
        feedback.classList.remove("hidden")
        field.setAttribute("aria-describedby", feedback.id)
      }
    }

    return valid
  }
}
