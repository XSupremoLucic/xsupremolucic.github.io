// By chatgpt becuase I hate frontend and javascript kill me
document.addEventListener("DOMContentLoaded", () => {
  const dropArea = document.getElementById("drop-area");
  const fileInput = document.getElementById("fileElem");
  const uploadStatus = document.getElementById("upload-status");

  // Prevent default drag behaviors
  ["dragenter", "dragover", "dragleave", "drop"].forEach((eventName) => {
    dropArea.addEventListener(eventName, preventDefaults, false);
    document.body.addEventListener(eventName, preventDefaults, false);
  });

  // Highlight drop area when item is dragged over
  ["dragenter", "dragover"].forEach((eventName) => {
    dropArea.addEventListener(eventName, highlight, false);
  });

  ["dragleave", "drop"].forEach((eventName) => {
    dropArea.addEventListener(eventName, unhighlight, false);
  });

  // Handle dropped files
  dropArea.addEventListener("drop", handleDrop, false);
  dropArea.addEventListener("click", () => fileInput.click());

  // Handle file selection
  fileInput.addEventListener(
    "change",
    () => {
      const files = fileInput.files;
      handleFiles(files);
    },
    false
  );

  // Handle pasted files
  document.addEventListener("paste", handlePaste, false);

  function preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
  }

  function highlight() {
    dropArea.classList.add("highlight");
  }

  function unhighlight() {
    dropArea.classList.remove("highlight");
  }

  function handleDrop(e) {
    const dt = e.dataTransfer;
    const files = dt.files;
    handleFiles(files);
  }

  function handlePaste(e) {
    const items = e.clipboardData.items;
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.kind === "file") {
        const file = item.getAsFile();
        handleFiles([file]);
      }
    }
  }

  function handleFiles(files) {
    if (files.length > 0) {
      for (const file of files) {
        uploadFile(file);
      }
    }
  }

  function uploadFile(file) {
    const url = "upload"; // Replace with your upload URL
    const xhr = new XMLHttpRequest();

    // Create a new upload status container and link elements
    const uploadContainer = document.createElement("div");
    const statusLink = document.createElement("div");
    const uploadText = document.createElement("span");
    const buttons = document.createElement("div");
    const copyButton = document.createElement("button");
    const deleteButton = document.createElement("button");

    uploadContainer.className = "upload-status"; // Use the existing CSS class for styling
    uploadContainer.appendChild(uploadText);
    uploadContainer.appendChild(statusLink);
	buttons.appendChild(copyButton)
	buttons.appendChild(deleteButton)
	uploadContainer.appendChild(buttons)
    uploadStatus.appendChild(uploadContainer);

    // Update upload text
    uploadText.innerHTML = "0%";
    uploadText.className = "percent";
    statusLink.className = "status";
    copyButton.className = "copy-button"; // Add class for styling
    copyButton.innerHTML = "Copiar"; // Set button text
    deleteButton.className = "delete-button";
    deleteButton.innerHTML = "Borrar";
    copyButton.style.display = "none";
    deleteButton.style.display = "none";

    // Update progress text
    xhr.upload.addEventListener("progress", (e) => {
      if (e.lengthComputable) {
        const percentComplete = Math.round((e.loaded / e.total) * 100);
        uploadText.innerHTML = `${percentComplete}%`; // Update the text with the percentage
      }
    });

    xhr.onerror = () => {
      console.error("Error:", xhr.status, xhr.statusText, xhr.responseText);
      statusLink.textContent = "Error desconocido";
    };

    xhr.onload = () => {
      //   console.log("Response Status:", xhr.status);
      //   console.log("Response Text:", xhr.responseText);
      if (xhr.status === 200) {
        try {
          const response = JSON.parse(xhr.responseText);
          const fileLink = response.link;
          statusLink.innerHTML = `<a href="${fileLink}" target="_blank">${fileLink}</a>`;
          copyButton.style.display = "inline";
          copyButton.onclick = () => copyToClipboard(fileLink);
          deleteButton.style.display = "inline";
          deleteButton.onclick = () => {
            window.open(response.deleteLink, "_blank");
          };
        } catch (error) {
          statusLink.textContent =
            "Error desconocido, habla con el administrador";
        }
      } else if (xhr.status >= 400 && xhr.status < 500) {
        try {
          const errorResponse = JSON.parse(xhr.responseText);
          statusLink.textContent = errorResponse.error || "Error del cliente.";
        } catch (e) {
          statusLink.textContent = "Error del cliente.";
        }
      } else {
        statusLink.textContent = "Error del servidor.";
      }
    };

    // Send file
    const formData = new FormData();
    formData.append("file", file);
    xhr.open("POST", url, true);
    xhr.send(formData);
  }

  // Function to copy the link to the clipboard
  function copyToClipboard(text) {
    navigator.clipboard
      .writeText(text)
      .then(() => {
        // alert("Link copied to clipboard!"); // Notify the user
      })
      .catch((err) => {
        console.error("Failed to copy: ", err);
      });
  }
});
