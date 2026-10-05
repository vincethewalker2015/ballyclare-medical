import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form", "element", "error", "submit"];

  static values = {
    publishableKey: String,
    clientSecret: String,
  };

  connect() {
    if (typeof Stripe === "undefined") {
      this.showError(
        "The payment service could not be loaded. Please refresh and try again.",
      );
      return;
    }

    this.stripe = Stripe(this.publishableKeyValue);

    this.elements = this.stripe.elements({
      clientSecret: this.clientSecretValue,
    });

    this.paymentElement = this.elements.create("payment");
    this.paymentElement.mount(this.elementTarget);

    this.formTarget.addEventListener("submit", this.submitPayment);
  }

  disconnect() {
    this.formTarget.removeEventListener("submit", this.submitPayment);

    if (this.paymentElement) {
      this.paymentElement.destroy();
    }
  }

  submitPayment = async (event) => {
    event.preventDefault();

    // Prevent duplicate submissions.
    if (this.submitting) return;

    this.submitting = true;
    this.clearError();
    this.setSubmitting(true);

    const { error } = await this.stripe.confirmPayment({
      elements: this.elements,
      confirmParams: {
        return_url: this.element.dataset.returnUrl,
      },
    });

    if (error) {
      this.submitting = false;
      this.showError(error.message);
      this.setSubmitting(false);
    }
  };

  showError(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.classList.remove("hidden");
  }

  clearError() {
    this.errorTarget.textContent = "";
    this.errorTarget.classList.add("hidden");
  }

  setSubmitting(submitting) {
    this.submitTarget.disabled = submitting;
    this.submitTarget.textContent = submitting
      ? "Processing…"
      : this.submitTarget.dataset.label;
  }
}
