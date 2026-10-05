import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static values = {
    url: String,
  };

  connect() {
    this.attempts = 0;
    this.maxAttempts = 20;
    this.schedule();
  }

  disconnect() {
    clearTimeout(this.timer);
  }

  schedule() {
    this.timer = setTimeout(() => this.poll(), 1000);
  }

  async poll() {
    if (this.attempts >= this.maxAttempts) return;

    this.attempts += 1;

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "text/vnd.turbo-stream.html",
        },
      });

      if (response.status === 204) {
        this.schedule();
        return;
      }

      if (response.ok) {
        Turbo.renderStreamMessage(await response.text());
        return;
      }
    } catch (_) {
      // Treat network errors as temporary and try again.
    }

    this.schedule();
  }
}
