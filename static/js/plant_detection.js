const dropZone = document.getElementById("uploadBox");
const imageInput = document.getElementById("imageInput");
const previewImage = document.getElementById("previewImage");

const detectBtn = document.getElementById("detectBtn");
const resetBtn = document.getElementById("resetBtn");

const resultBox = document.getElementById("resultBox");
const loaderContainer = document.getElementById("loaderContainer");

const resultDisease = document.getElementById("resultDisease");
const resultConfidenceText = document.getElementById("resultConfidenceText");
const confidenceBar = document.getElementById("confidenceBar");

let selectedFile = null;

/* ── Helpers ──────────────────────────────────────────────────────────── */

function showLoginPrompt() {
  alert("Please login to upload and analyze plant images.");
  const loginModal = document.getElementById("authModal");
  const loginForm = document.getElementById("loginForm");
  const signupForm = document.getElementById("signupForm");
  if (loginModal) {
    loginModal.style.display = "flex";
    if (loginForm) loginForm.style.display = "block";
    if (signupForm) signupForm.style.display = "none";
  }
}

async function isLoggedIn() {
  const { data: { session } } = await window.supabaseClient.auth.getSession();
  return !!session;
}

function handleFileSelect(file) {
  if (file && file.type.startsWith("image/")) {
    selectedFile = file;
    previewImage.src = URL.createObjectURL(file);
    previewImage.style.display = "block";
    resetBtn.style.display = "block";
    resultBox.style.display = "none";
  } else if (file) {
    alert("Please upload a valid image file (JPG, PNG, etc.)");
  }
}

/* ── File input change (triggered programmatically) ───────────────────── */
imageInput.addEventListener("change", (e) => {
  handleFileSelect(e.target.files[0]);
});

/* ── Drop zone CLICK ──────────────────────────────────────────────────────
   The <input type="file"> is INSIDE the drop zone div, so clicking the
   input would bubble up and re-trigger the dropZone click → infinite loop.
   Fix: only open the dialog when the click target is NOT the input itself,
   and stop propagation on the input so it never bubbles to dropZone.
*/
imageInput.addEventListener("click", (e) => {
  e.stopPropagation(); // prevent bubbling up to dropZone
});

dropZone.addEventListener("click", async (e) => {
  // If user clicked the reset button (inside the upload area) ignore
  if (e.target.closest("#resetBtn")) return;

  if (!(await isLoggedIn())) {
    showLoginPrompt();
    return;
  }

  imageInput.click();
});

/* ── Drag & Drop ──────────────────────────────────────────────────────── */
dropZone.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropZone.classList.add("drag-over");
});

dropZone.addEventListener("dragleave", (e) => {
  e.preventDefault();
  dropZone.classList.remove("drag-over");
});

dropZone.addEventListener("drop", async (e) => {
  e.preventDefault();
  dropZone.classList.remove("drag-over");

  if (!(await isLoggedIn())) {
    showLoginPrompt();
    return;
  }

  const files = e.dataTransfer.files;
  if (files.length > 0) {
    handleFileSelect(files[0]);
  }
});

/* ── Reset ────────────────────────────────────────────────────────────── */
resetBtn.addEventListener("click", (e) => {
  e.stopPropagation(); // don't bubble to dropZone → no dialog

  selectedFile = null;
  imageInput.value = "";

  previewImage.src = "";
  previewImage.style.display = "none";

  resetBtn.style.display = "none";
  resultBox.style.display = "none";
});

/* ── Detect ───────────────────────────────────────────────────────────── */
detectBtn.addEventListener("click", async () => {
  if (!selectedFile) {
    alert("Please upload an image first.");
    return;
  }

  if (!(await isLoggedIn())) {
    showLoginPrompt();
    return;
  }

  detectBtn.disabled = true;
  loaderContainer.style.display = "block";
  resultBox.style.display = "none";

  const formData = new FormData();
  formData.append("image", selectedFile);

  try {
    const { data: { session } } = await window.supabaseClient.auth.getSession();
    const token = session?.access_token;

    const response = await fetch("/api/predict/", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`
      },
      body: formData
    });

    const responseText = await response.text();
    let data;
    try {
      data = JSON.parse(responseText);
    } catch {
      data = { error: responseText || response.statusText };
    }

    if (response.ok) {
      resultBox.style.display = "block";
      resultDisease.innerText = `Detected: ${data.disease}`;
      resultConfidenceText.innerText = `Confidence: ${data.confidence_percentage}`;
      confidenceBar.style.width = `${data.confidence * 100}%`;
    } else {
      alert(data.error || "Prediction failed. Please try again.");
    }

  } catch (err) {
    console.error("Prediction error:", err);
    alert(`Network error. ${err?.message || err}`);
  } finally {
    loaderContainer.style.display = "none";
    detectBtn.disabled = false;
  }
});