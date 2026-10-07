// Entry point for the build script in your package.json
import { Turbo } from "@hotwired/turbo-rails";
import "./controllers";

Turbo.config.forms.confirm = (message) => {
  const dialog = document.getElementById("turbo-confirm-dialog");
  const messageElement = document.getElementById("turbo-confirm-message");

  if (!dialog || !messageElement) {
    return Promise.resolve(window.confirm(message));
  }

  messageElement.textContent = message;

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
