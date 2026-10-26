import { Controller } from "@hotwired/stimulus";

// Load Stripe.js once for both staff and patient checkout, including Turbo visits.
let stripeScriptPromise;

function loadStripeScript() {
  if (typeof window.Stripe === "function") return Promise.resolve();

  if (!stripeScriptPromise) {
    stripeScriptPromise = new Promise((resolve, reject) => {
      const script = document.querySelector('script[src="https://js.stripe.com/v3/"]') ||
        document.createElement("script");

      if (typeof window.Stripe === "function") {
        resolve();
        return;
      }

      script.addEventListener("load", resolve, { once: true });
      script.addEventListener("error", () => reject(new Error("Stripe.js failed to load")), { once: true });

      if (!script.isConnected) {
        script.src = "https://js.stripe.com/v3/";
        document.head.appendChild(script);
      }
    }).catch((error) => {
      stripeScriptPromise = undefined;
      throw error;
    });
  }

  return stripeScriptPromise;
}

export default class extends Controller {
  static targets = ["form", "element", "error", "submit"];

  static values = {
    publishableKey: String,
    clientSecret: String,
  };

  async connect() {
    this.connected = true;
    this.submitTarget.disabled = true;

    try {
      await loadStripeScript();
      if (!this.connected) return;

      this.stripe = window.Stripe(this.publishableKeyValue);
      this.elements = this.stripe.elements({ clientSecret: this.clientSecretValue });
      this.paymentElement = this.elements.create("payment");
      this.paymentElement.mount(this.elementTarget);
      this.formTarget.addEventListener("submit", this.submitPayment);
      this.submitTarget.disabled = false;
    } catch (error) {
      if (this.connected) {
        console.error("Stripe payment initialization failed:", error);
        this.showError("The payment service could not be loaded. Please refresh and try again.");
      }
    }
  }

  disconnect() {
    this.connected = false;
    this.formTarget.removeEventListener("submit", this.submitPayment);
    if (this.paymentElement) {
      this.paymentElement.destroy();
      this.paymentElement = null;
    }
  }

  submitPayment = async (event) => {
    event.preventDefault();
    if (this.submitting || !this.stripe) return;

    this.submitting = true;
    this.clearError();
    this.setSubmitting(true);

    try {
      const { error } = await this.stripe.confirmPayment({
        elements: this.elements,
        confirmParams: { return_url: this.element.dataset.returnUrl },
      });

      if (error) this.showError(error.message);
    } catch (error) {
      console.error("Stripe payment confirmation failed:", error);
      this.showError("The payment could not be completed. Please try again.");
    } finally {
      this.submitting = false;
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
      : (this.submitTarget.dataset.label || "Pay securely");
  }
}
