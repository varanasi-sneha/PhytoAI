/* ============================================================
   plant_detection.js
   Handles: upload, drag-drop, camera, detect, prevention card
   Two-column layout: result box (left) | prevention (right)
============================================================ */

/* ── Element refs ────────────────────────────────────────── */
const dropZone             = document.getElementById("uploadBox");
const imageInput           = document.getElementById("imageInput");
const previewImage         = document.getElementById("previewImage");
const detectBtn            = document.getElementById("detectBtn");
const resetBtn             = document.getElementById("resetBtn");
const resultBox            = document.getElementById("resultBox");
const loaderContainer      = document.getElementById("loaderContainer");
const resultDisease        = document.getElementById("resultDisease");
const resultConfidenceText = document.getElementById("resultConfidenceText");
const confidenceBar        = document.getElementById("confidenceBar");
const togglePreventionBtn  = document.getElementById("togglePreventionBtn");


/* ── Camera refs ─────────────────────────────────────────── */
const openCameraBtn  = document.getElementById("openCameraBtn");
const cameraVideo    = document.getElementById("cameraVideo");
const captureBtn     = document.getElementById("captureBtn");
const cameraCanvas   = document.getElementById("cameraCanvas");
const cameraBox      = document.getElementById("cameraBox");
const cameraSection  = document.querySelector(".camera-section");

let selectedFile  = null;
let cameraStream  = null;

/* ── Severity → colour map ───────────────────────────────── */
const severityColors = {
  low:      '#22c55e',
  moderate: '#f59e0b',
  high:     '#ef4444',
  critical: '#7f1d1d',
};

/* ─────────────────────────────────────────────────────────
   AUTH HELPERS
───────────────────────────────────────────────────────── */
function showLoginPrompt() {
  alert("Please login to upload and analyze plant images.");
  const loginModal = document.getElementById("authModal");
  const loginForm  = document.getElementById("loginForm");
  const signupForm = document.getElementById("signupForm");
  if (loginModal) {
    loginModal.style.display = "flex";
    if (loginForm)  loginForm.style.display  = "block";
    if (signupForm) signupForm.style.display = "none";
  }
}

async function isLoggedIn() {
  const { data: { session } } = await window.supabaseClient.auth.getSession();
  return !!session;
}

/* ─────────────────────────────────────────────────────────
   FILE SELECT
───────────────────────────────────────────────────────── */
function handleFileSelect(file) {
  if (file && file.type.startsWith("image/")) {
    selectedFile = file;
    previewImage.src = URL.createObjectURL(file);
    previewImage.style.display = "block";
    resetBtn.style.display = "block";
    resultBox.style.display = "none";

    if (cameraSection) cameraSection.style.display = "none";
  } else if (file) {
    alert("Please upload a valid image file (JPG, PNG, etc.)");
  }
}

imageInput.addEventListener("change", (e) => handleFileSelect(e.target.files[0]));
imageInput.addEventListener("click", (e) => e.stopPropagation());

/* ─────────────────────────────────────────────────────────
   DROP ZONE CLICK
───────────────────────────────────────────────────────── */
dropZone.addEventListener("click", async (e) => {
  if (e.target.closest("#resetBtn")) return;
  if (!(await isLoggedIn())) { showLoginPrompt(); return; }
  imageInput.click();
});

/* ─────────────────────────────────────────────────────────
   DRAG & DROP
───────────────────────────────────────────────────────── */
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
  if (!(await isLoggedIn())) { showLoginPrompt(); return; }
  if (e.dataTransfer.files.length > 0) handleFileSelect(e.dataTransfer.files[0]);
});

/* ─────────────────────────────────────────────────────────
   RESET
───────────────────────────────────────────────────────── */
resetBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  selectedFile = null;
  imageInput.value = "";
  previewImage.src = "";
  previewImage.style.display = "none";
  resetBtn.style.display = "none";
  resultBox.style.display = "none";
  togglePreventionBtn.style.display = "none";
  
  document.getElementById("preventionCard").style.display = "none";
  document.getElementById("resultsLayout").style.display = "none";

  if (cameraSection) cameraSection.style.display = "block";
  hidePrevention();
});

/* ─────────────────────────────────────────────────────────
   CAMERA
───────────────────────────────────────────────────────── */
openCameraBtn.addEventListener("click", async () => {
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({ video: true });
    cameraVideo.srcObject = cameraStream;
    cameraBox.style.display = "block";
  } catch (err) {
    alert("Camera permission denied or not available.");
  }
});

captureBtn.addEventListener("click", () => {
  const ctx = cameraCanvas.getContext("2d");
  cameraCanvas.width  = cameraVideo.videoWidth;
  cameraCanvas.height = cameraVideo.videoHeight;
  ctx.drawImage(cameraVideo, 0, 0);

  cameraCanvas.toBlob((blob) => {
    const file = new File([blob], "camera.jpg", { type: "image/jpeg" });
    handleFileSelect(file);
    if (cameraStream) cameraStream.getTracks().forEach(t => t.stop());
    cameraBox.style.display = "none";
  });
});

/* ─────────────────────────────────────────────────────────
   DETECT
───────────────────────────────────────────────────────── */
detectBtn.addEventListener("click", async () => {
  if (!selectedFile) {
    alert("Please upload an image first.");
    return;
  }

  if (!(await isLoggedIn())) { showLoginPrompt(); return; }

  detectBtn.disabled = true;
  loaderContainer.style.display = "block";
  resultBox.style.display = "none";
  hidePrevention();

  const formData = new FormData();
  formData.append("image", selectedFile);

  try {
    const { data: { session } } = await window.supabaseClient.auth.getSession();
    const token = session?.access_token;

    console.log("🚀 Sending prediction request...");
    const response = await fetch("/api/predict/", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: formData,
    });

    let data;
    try {
      data = await response.json();
    } catch {
      data = { error: "Unexpected server response. Please try again." };
    }

    
    console.log("STATUS:", response.status);
    console.log("DATA:", data);
    if (data.valid) {
      // ── Valid prediction ────────────────────────────── 

      resultBox.style.display = "block";
      document.getElementById("resultsLayout").style.display = "block"; // show layout

      togglePreventionBtn.style.display = "inline-block"; // show button 
 
      const label = data.display_name || data.disease || "Unknown"; 
      if (!data.valid) return; 
      resultDisease.innerText = `Detected: ${label}`;
      resultConfidenceText.innerText = `Confidence: ${data.confidence_percentage}`;
      confidenceBar.style.display = "block";
      confidenceBar.style.width = data.confidence ? `${(data.confidence * 100).toFixed(1)}%` : "0%";

      // Fetch prevention using raw disease name
      togglePreventionBtn.onclick = async () => {
        const modal = document.getElementById("preventionModal");
        const modalContent = document.getElementById("modalContent");

        modal.style.display = "flex";

        // MOVE CARD INTO MODAL
        const card = document.getElementById("preventionCard");
        modalContent.appendChild(card);

        document.getElementById("preventionLoader").style.display = "block";
        
        if (data.prevention) {
          renderPrevention(data.prevention);
        } else {
          await fetchPrevention(data.disease);
        }
      };

    } else {
      // ── Handle specific error types from new model ────
      const errorType = data.error;

      if (errorType === "unclear_image") {
        showError("📷 Image Too Unclear",
          data.message || "The image is too blurry. Please upload a clearer photo.");

      } else if (errorType === "not_a_spinach_leaf" || errorType === "not_spinach") {
        showError("🌿 Not a Spinach Leaf",
          `${data.message || "This doesn't appear to be a Malabar Spinach leaf."}\n\nConfidence: ${data.confidence_percentage || "N/A"}`);

      } else if (errorType === "invalid_image" || errorType === "invalid_file_type") {
        showError("❌ Invalid Image",
          data.message || "Could not read the image. Please upload a valid JPG or PNG.");

      } else {
        showError("⚠️ Prediction Failed",
          data.message || data.error || "Something went wrong. Please try again.");
      }
    }

  } catch (err) {
    console.error("Prediction error:", err);
    showResultsLayout();
    showError("⚠️ Network Error", err?.message || "Could not reach the server. Please try again.");
  } finally {
    loaderContainer.style.display = "none";
    detectBtn.disabled = false;
  }
});

/* ── Show a styled error in the result box ────────────────── */
function showError(title, message) {
  resultDisease.innerHTML = `<strong style="color:#ef4444">${title}</strong><br>
    <span style="font-size:14px;color:var(--color-text-muted)">${message}</span>`;
  resultConfidenceText.innerText = "";
  confidenceBar.style.width = "0%";
}

/* ─────────────────────────────────────────────────────────
   PREVENTION
───────────────────────────────────────────────────────── */
function hidePrevention() {
  const card   = document.getElementById("preventionCard");
  const loader = document.getElementById("preventionLoader");
  if (card)   card.style.display   = "none";
  if (loader) loader.style.display = "none";
}

function renderPrevention(data) {
  const color = severityColors[data.severity] || "#4caf50";

  document.getElementById("preventionHeader").style.background = color;
  document.getElementById("preventionTitle").textContent =
    "🌿 " + (data.disease_name || "").replace(/[_-]/g, " ").replace(/\(|\)/g, "");
  document.getElementById("severityBadge").textContent =
    (data.severity || "").toUpperCase();
  document.getElementById("preventionDesc").textContent = data.description || "";

  const fillList = (id, items) => {
    const ul = document.getElementById(id);
    ul.innerHTML = "";
    (items || []).forEach(item => {
      const li = document.createElement("li");
      li.textContent = item;
      ul.appendChild(li);
    });
  };

  fillList("preventionList", data.prevention_measures);
  fillList("treatmentList",  data.treatment_options);
  fillList("organicList",    data.organic_solutions);
  fillList("chemicalList",   data.chemical_solutions);

  document.getElementById("preventionLoader").style.display = "none";
  document.getElementById("preventionCard").style.display   = "block";
}

async function fetchPrevention(diseaseName) {
  if (!diseaseName) return;

  document.getElementById("preventionCard").style.display   = "none";
  document.getElementById("preventionLoader").style.display = "block";
  document.getElementById("preventionLoader").textContent   = "⏳ Loading prevention measures...";

  try {
    const { data: { session } } = await window.supabaseClient.auth.getSession();
    const token = session?.access_token;

    const res = await fetch("/api/prevention", {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${token}`,
      },
      body: JSON.stringify({ disease_name: diseaseName }),
    });

    const result = await res.json();

    if (res.ok && result.success && result.data) {
      renderPrevention(result.data);
    } else {
      document.getElementById("preventionLoader").textContent =
        "⚠️ No prevention data found for this disease.";
    }
  } catch (err) {
    console.error("Prevention fetch error:", err);
    document.getElementById("preventionLoader").textContent =
      "❌ Could not load prevention data.";
    document.getElementById("resultsLayout").style.display = "block";
    showError( "❌ Network Error", "Unable to reach the server. Please check your connection and try again." );
  }
}

document.getElementById("closePreventionModal").onclick = () => {
  document.getElementById("preventionModal").style.display = "none"; 
}; 

document.getElementById("preventionModal").addEventListener("click", (e) => {
  if (e.target.id === "preventionModal") {
    e.target.style.display = "none";
  } 
});