import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["clinician", "date", "fee", "feeOption"];

  connect() {
    this.updateFee();
    this.refreshFeeOnPageShow = () => this.updateFee();
    window.addEventListener("pageshow", this.refreshFeeOnPageShow);
  }

  disconnect() {
    window.removeEventListener("pageshow", this.refreshFeeOnPageShow);
  }

  updateFee() {
    const selectedId = this.clinicianTarget.value;
    const option = this.feeOptionTargets.find(
      (element) => element.dataset.clinicianId === selectedId,
    );
    this.feeTarget.textContent = option
      ? option.dataset.feeLabel
      : "Select a clinician to see the consultation fee.";
  }

  async loadSlots() {
    this.updateFee();
    const clinicianId = this.clinicianTarget.value;
    const date = this.dateTarget.value;
    this.slotRequest?.abort();

    if (!clinicianId || !date) {
      document.getElementById("available_appointment_slots").innerHTML =
        '<p class="text-sm text-medical-muted">Select a clinician and date to view available appointments.</p>';
      return;
    }

    const controller = new AbortController();
    this.slotRequest = controller;
    const url = new URL(this.element.dataset.slotsUrl, window.location.origin);
    url.searchParams.set("clinician_id", clinicianId);
    url.searchParams.set("date", date);

    try {
      const response = await fetch(url, {
        signal: controller.signal,
        headers: { Accept: "text/vnd.turbo-stream.html" },
      });

      if (response.ok && this.slotRequest === controller) {
        Turbo.renderStreamMessage(await response.text());
      }
    } catch (error) {
      if (error.name !== "AbortError") throw error;
    }
  }
}
