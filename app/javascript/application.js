// Entry point for the build script in your package.json
import { Turbo } from "@hotwired/turbo-rails";
import "./controllers";

Turbo.config.forms.confirm = (message, element) => {
  const dialog = document.getElementById("turbo-confirm-dialog");
  const messageElement = document.getElementById("turbo-confirm-message");

  if (!dialog || !messageElement) {
    return Promise.resolve(window.confirm(message));
  }

  messageElement.textContent = message;

  const cancelButton = dialog.querySelector('button[value="cancel"]');
  const confirmButton = dialog.querySelector('button[value="confirm"]');
  const action = element?.dataset.confirmAction || element?.closest("form")?.dataset.confirmAction || "generic";
  const labels = {
    availability: ["Keep availability", "Cancel availability"],
    reactivate: ["Keep inactive", "Reactivate staff member"],
    deactivate: ["Keep active", "Deactivate staff member"],
    patient_registration: ["Go back", "Approve registration"]
  };
  const [cancelLabel, confirmLabel] = labels[action] || ["Cancel", "Confirm"];
  cancelButton.textContent = cancelLabel;
  confirmButton.textContent = confirmLabel;
  const destructive = ["availability", "deactivate"].includes(action);
  confirmButton.classList.toggle("bg-red-600", destructive);
  confirmButton.classList.toggle("hover:bg-red-700", destructive);
  confirmButton.classList.toggle("focus:ring-red-600", destructive);
  confirmButton.classList.toggle("bg-medical-teal", !destructive);
  confirmButton.classList.toggle("hover:bg-medical-teal-dark", !destructive);
  confirmButton.classList.toggle("focus:ring-medical-teal", !destructive);


  return new Promise((resolve) => {
    const cleanup = () => {
      dialog.removeEventListener("click", handleClick);
      dialog.removeEventListener("cancel", handleCancel);
    };

    const finish = (confirmed) => {
      cleanup();
      dialog.close();
      resolve(confirmed);
    };

    const handleClick = (event) => {
      const button = event.target.closest("button");

      if (button?.value === "confirm") {
        finish(true);
      }

      if (button?.value === "cancel") {
        finish(false);
      }
    };

    const handleCancel = (event) => {
      event.preventDefault();
      finish(false);
    };

    dialog.addEventListener("click", handleClick);
    dialog.addEventListener("cancel", handleCancel);

    dialog.showModal();
  });
};
