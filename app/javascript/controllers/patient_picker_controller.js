import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "value", "results"];
  static values = { url: String };

  connect() {
    this.options = [];
    this.activeIndex = -1;
    this.requestNumber = 0;
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abortController?.abort();
  }

  search() {
    if (this.inputTarget.value !== this.selectedLabel) this.valueTarget.value = "";
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetchResults(), 180);
  }

  async fetchResults() {
    this.abortController?.abort();
    const controller = new AbortController();
    this.abortController = controller;
    const requestNumber = ++this.requestNumber;
    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("q", this.inputTarget.value);

    try {
      const response = await fetch(url, {
        signal: controller.signal,
        headers: { Accept: "application/json" },
      });
      if (!response.ok) throw new Error("Patient search failed");
      const options = await response.json();
      if (requestNumber !== this.requestNumber) return;
      this.options = options;
      this.activeIndex = -1;
      this.renderResults();
    } catch (error) {
      if (error.name !== "AbortError") this.close();
    }
  }

  renderResults() {
    this.resultsTarget.replaceChildren();
    this.options.forEach((patient, index) => {
      const item = document.createElement("li");
      item.id = `patient-option-${index}`;
      item.role = "option";
      item.dataset.index = index;
      item.setAttribute("aria-selected", String(index === this.activeIndex));
      item.className = "cursor-pointer px-4 py-3 text-sm text-medical-ink hover:bg-medical-cream";
      if (index === this.activeIndex) item.classList.add("bg-medical-cream");
      item.textContent = patient.label;
      item.addEventListener("mousedown", (event) => event.preventDefault());
      item.addEventListener("click", () => this.select(index));
      this.resultsTarget.append(item);
    });
    this.resultsTarget.classList.toggle("hidden", this.options.length === 0);
    this.inputTarget.setAttribute("aria-expanded", String(this.options.length > 0));
    if (this.activeIndex >= 0) {
      this.inputTarget.setAttribute("aria-activedescendant", `patient-option-${this.activeIndex}`);
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant");
    }
  }

  keyDown(event) {
    if (event.key === "Escape") {
      this.close();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (!this.options.length) return;
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      this.activeIndex = (this.activeIndex + step + this.options.length) % this.options.length;
      this.renderResults();
    } else if (event.key === "Enter" && this.activeIndex >= 0 && this.options.length) {
      event.preventDefault();
      this.select(this.activeIndex);
    }
  }

  select(index) {
    const patient = this.options[index];
    if (!patient) return;
    this.valueTarget.value = patient.id;
    this.inputTarget.value = patient.label;
    this.selectedLabel = patient.label;
    this.close();
  }

  blur() {
    setTimeout(() => this.close(), 120);
  }

  close() {
    this.abortController?.abort();
    ++this.requestNumber;
    this.options = [];
    this.activeIndex = -1;
    this.resultsTarget.replaceChildren();
    this.resultsTarget.classList.add("hidden");
    this.inputTarget.setAttribute("aria-expanded", "false");
    this.inputTarget.removeAttribute("aria-activedescendant");
  }
}
