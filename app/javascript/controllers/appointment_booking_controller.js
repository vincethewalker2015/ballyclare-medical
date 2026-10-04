import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["clinician"];

  async loadSlots() {
    const clinicianId = this.clinicianTarget.value;

    if (!clinicianId) {
      return;
    }

    const url = new URL(this.element.dataset.slotsUrl, window.location.origin);
    url.searchParams.set("clinician_id", clinicianId);

    const response = await fetch(url, {
      headers: {
        Accept: "text/vnd.turbo-stream.html",
      },
    });

    if (response.ok) {
      Turbo.renderStreamMessage(await response.text());
    }
  }
}
