// document.addEventListener("DOMContentLoaded", () => {
//     const dropArea = document.getElementById("drop-area");
//     const fileInput = document.getElementById("fileElem");
//     const progressContainer = document.getElementById("progress-container");
//     const progressBar = document.getElementById("progress-bar");
//     const status = document.getElementById("status");

//     // Prevent default drag behaviors
//     ["dragenter", "dragover", "dragleave", "drop"].forEach(eventName => {
//         dropArea.addEventListener(eventName, preventDefaults, false);
//         document.body.addEventListener(eventName, preventDefaults, false);
//     });

//     // Highlight drop area when item is dragged over
//     ["dragenter", "dragover"].forEach(eventName => {
//         dropArea.addEventListener(eventName, highlight, false);
//     });

//     ["dragleave", "drop"].forEach(eventName => {
//         dropArea.addEventListener(eventName, unhighlight, false);
//     });

//     // Handle dropped files
//     dropArea.addEventListener("drop", handleDrop, false);
//     dropArea.addEventListener("click", () => fileInput.click());

//     // Handle file selection
//     fileInput.addEventListener("change", () => {
//         const files = fileInput.files;
//         handleFiles(files);
//     }, false);

//     // Handle pasted files
//     document.addEventListener("paste", handlePaste, false);

//     function preventDefaults(e) {
//         e.preventDefault();
//         e.stopPropagation();
//     }

//     function highlight() {
//         dropArea.classList.add("highlight");
//     }

//     function unhighlight() {
//         dropArea.classList.remove("highlight");
//     }

//     function handleDrop(e) {
//         const dt = e.dataTransfer;
//         const files = dt.files;
//         handleFiles(files);
//     }

//     function handlePaste(e) {
//         const items = e.clipboardData.items;
//         for (let i = 0; i < items.length; i++) {
//             const item = items[i];
//             if (item.kind === "file") {
//                 const file = item.getAsFile();
//                 handleFiles([file]);
//             }
//         }
//     }

//     function handleFiles(files) {
//         if (files.length > 0) {
//             uploadFile(files[0]);
//         }
//     }

//     function uploadFile(file) {
//         const url = "upload"; // Replace with your upload URL
//         const xhr = new XMLHttpRequest();

//         // Update progress bar
//         xhr.upload.addEventListener("progress", (e) => {
//             if (e.lengthComputable) {
//                 const percentComplete = (e.loaded / e.total) * 100;
//                 progressBar.style.width = percentComplete + "%"; // Set the width of the progress bar
//                 progressContainer.style.display = "block"; // Show progress container
//             }
//         });

//         // Handle response
//         xhr.onload = () => {
//             if (xhr.status === 200) {
//                 try {
//                     const response = JSON.parse(xhr.responseText);
//                     const fileLink = response.link; // Assuming the response contains a key 'link'
//                     status.innerHTML = `<a href="${fileLink}" target="_blank">File uploaded successfully! Click here to view the file</a>`;
//                 } catch (error) {
//                     status.textContent = "File uploaded but failed to parse response.";
//                 }
//             } else {
//                 status.textContent = "File upload failed.";
//             }
//             progressBar.style.width = "0"; // Reset progress bar
//             progressContainer.style.display = "none"; // Hide progress container
//         };

//         // Handle errors
//         xhr.onerror = () => {
//             status.textContent = "An error occurred during the file upload.";
//             progressBar.style.width = "0"; // Reset progress bar
//             progressContainer.style.display = "none"; // Hide progress container
//         };

//         // Send file
//         const formData = new FormData();
//         formData.append("file", file);
//         xhr.open("POST", url, true);
//         xhr.send(formData);
//     }
// });

function handleFiles(input) {
    const files = input.files;
    Array.from(files).forEach(file => {
        // Display download link initially
        document.querySelector(`#link-${file.name}`).textContent = "Uploading...";

        // Create a new FormData instance
        let formData = new FormData();
        formData.append('file', file);

        // Simulate a request to the server
        fetch('/upload', { method: 'POST', body: formData })
            .then(response => response.json())
            .then(data => {
                // Update the progress bar
                document.querySelector(`#progress-${file.name}`).style.width = `${data.progress}%`;

                // Display the download link
                document.querySelector(`#link-${file.name}`).textContent = data.link;
            })
            .catch(error => console.error('Error:', error));
    });
}

// Handle drag & drop
document.addEventListener('dragover', function(event) {
    event.preventDefault();
    event.stopPropagation();
});

document.addEventListener('drop', function(event) {
    event.preventDefault();
    event.stopPropagation();

    const files = event.dataTransfer.files;
    handleFiles(files);
}, false);

// Handle clipboard paste
document.addEventListener('paste', function(event) {
    event.preventDefault();
    event.stopPropagation();

    const items = event.clipboardData.items;
    if (items.length > 0 && items[0].type.indexOf("text") !== -1) {
        const file = items[0].getAsFile();
        handleFiles([file]);
    }
}, false);
