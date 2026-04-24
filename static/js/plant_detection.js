/* ============================================================
   plant_detection.js  (UPDATED)
   - Shows confidence bar + result on screen (not just console)
   - Renders 5-class distribution bars inside result card
   - Prevention modal cycles through all diseases by confidence
     with Prev / Next buttons
============================================================ */

/* ── Element refs ────────────────────────────────────────── */
const dropZone             = document.getElementById("uploadBox");
const imageInput           = document.getElementById("imageInput");
const previewImage         = document.getElementById("previewImage");
const detectBtn            = document.getElementById("detectBtn");
const resetBtn             = document.getElementById("resetBtn");
const resultsLayout        = document.getElementById("resultsLayout");
const loaderContainer      = document.getElementById("loaderContainer");
const resultDisease        = document.getElementById("resultDisease");
const resultConfidenceText = document.getElementById("resultConfidenceText");
const confidenceBar        = document.getElementById("confidenceBar");
const distributionSection  = document.getElementById("distributionSection");

/* ── Camera refs ─────────────────────────────────────────── */
const openCameraBtn  = document.getElementById("openCameraBtn");
const cameraVideo    = document.getElementById("cameraVideo");
const captureBtn     = document.getElementById("captureBtn");
const cameraCanvas   = document.getElementById("cameraCanvas");
const cameraBox      = document.getElementById("cameraBox");
const cameraSection  = document.querySelector(".camera-section");

/* ── Disease accent colours ──────────────────────────────── */
const CLASS_COLOURS = {
  "Anthracnose":    "#ef5350",
  "Bacterial-Spot": "#ff7043",
  "Downy-Mildew":   "#7e57c2",
  "Healthy-Leaf":   "#66bb6a",
  "Pest-Damage":    "#ffa726",
};

const severityColors = {
  low:      '#22c55e',
  moderate: '#f59e0b',
  high:     '#ef4444',
  critical: '#7f1d1d',
};

/* ── State ───────────────────────────────────────────────── */
let selectedFile       = null;
let cameraStream       = null;
let preventionQueue    = [];   // sorted disease names by confidence desc
let preventionIndex    = 0;   // which disease we're currently showing
let preventionCache    = {};  // { diseaseName: data } to avoid re-fetching

/* ─────────────────────────────────────────────────────────
   LAYOUT HELPERS
───────────────────────────────────────────────────────── */
function showResultsLayout() {
  resultsLayout.style.display = "flex";
  // Make sure the inner result-box is visible
  const box = document.getElementById("resultBox");
  if (box) box.style.display = "block";
}

function hideResultsLayout() {
  resultsLayout.style.display = "none";
  const box = document.getElementById("resultBox");
  if (box) box.style.display = "none";
  hidePrevention();
}

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
    selectedFile               = file;
    previewImage.src           = URL.createObjectURL(file);
    previewImage.style.display = "block";
    resetBtn.style.display     = "block";
    hideResultsLayout();
    clearDistributionChart();
    if (cameraSection) cameraSection.style.display = "none";
  } else if (file) {
    alert("Please upload a valid image file (JPG, PNG, etc.)");
  }
}

imageInput.addEventListener("change", (e) => handleFileSelect(e.target.files[0]));
imageInput.addEventListener("click",  (e) => e.stopPropagation());

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
  selectedFile               = null;
  imageInput.value           = "";
  previewImage.src           = "";
  previewImage.style.display = "none";
  resetBtn.style.display     = "none";
  hideResultsLayout();
  clearDistributionChart();
  preventionQueue  = [];
  preventionIndex  = 0;
  preventionCache  = {};
  if (cameraSection) cameraSection.style.display = "block";
});

/* ─────────────────────────────────────────────────────────
   CAMERA
───────────────────────────────────────────────────────── */
if (openCameraBtn) {
  openCameraBtn.addEventListener("click", async () => {
    try {
      cameraStream = await navigator.mediaDevices.getUserMedia({ video: true });
      cameraVideo.srcObject = cameraStream;
      cameraBox.style.display = "block";
    } catch {
      alert("Camera permission denied or not available.");
    }
  });
}

if (captureBtn) {
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
}

/* ─────────────────────────────────────────────────────────
   DETECT
───────────────────────────────────────────────────────── */
detectBtn.addEventListener("click", async () => {
  if (!selectedFile) {
    alert("Please upload an image first.");
    return;
  }

  if (!(await isLoggedIn())) { showLoginPrompt(); return; }

  detectBtn.disabled            = true;
  loaderContainer.style.display = "block";
  hideResultsLayout();
  clearDistributionChart();
  preventionQueue = [];
  preventionIndex = 0;
  preventionCache = {};

  const formData = new FormData();
  formData.append("image", selectedFile);

  try {
    const { data: { session } } = await window.supabaseClient.auth.getSession();
    const token = session?.access_token;

    if (!token) throw new Error("No authentication token found. Please login again.");

    const response = await fetch("/api/predict/", {
      method:  "POST",
      headers: { "Authorization": `Bearer ${token}` },
      body:    formData,
    });

    let data;
    try {
      const responseText = await response.text();
      data = JSON.parse(responseText);
    } catch {
      data = { error: "server_error", message: "Server returned invalid response." };
    }

    showResultsLayout();

    if (response.ok) {
      renderSuccess(data);
    } else {
      const errorType = data.error;
      if (errorType === "unclear_image") {
        showError("📷 Image Too Unclear", data.message || "The image is too blurry. Please upload a clearer photo.", data);
      } else if (errorType === "not_a_spinach_leaf") {
        showError("🌿 Not a Spinach Leaf", data.message || "This doesn't appear to be a Malabar Spinach leaf.", data);
      } else if (errorType === "invalid_image" || errorType === "invalid_file_type") {
        showError("❌ Invalid Image", data.message || "Could not read the image. Please upload a valid JPG or PNG.", data);
      } else {
        showError("⚠️ Prediction Failed", data.message || data.error || "Something went wrong. Please try again.", data);
      }
    }

  } catch (err) {
    showResultsLayout();
    showError("⚠️ Network Error", err?.message || "Could not reach the server. Please check your connection.");
  } finally {
    loaderContainer.style.display = "none";
    detectBtn.disabled            = false;
  }
});

/* ─────────────────────────────────────────────────────────
   RENDER SUCCESS
───────────────────────────────────────────────────────── */
function renderSuccess(data) {
  const label = data.display_name || data.disease || "Unknown";

  let warningHtml = "";
  if (data.is_blurry) {
    warningHtml += `<div class="result-warning result-warning--blur">
      📷 Blurry image (sharpness: ${data.blur_score}). Results may be less accurate.
    </div>`;
  }
  if (data.is_low_confidence) {
    warningHtml += `<div class="result-warning result-warning--confidence">
      ⚠️ Low confidence — consider a clearer photo or consult an agronomist.
    </div>`;
  }

  resultDisease.innerHTML = `${warningHtml}<strong>${escHtml(label)}</strong>`;
  resultConfidenceText.innerText = `Confidence: ${data.confidence_percentage}`;

  // Animate confidence bar
  confidenceBar.style.width = "0%";
  requestAnimationFrame(() => {
    setTimeout(() => {
      confidenceBar.style.width = `${(data.confidence * 100).toFixed(1)}%`;
    }, 50);
  });

  // Show "Prevention / Cure" button
  const toggleBtn = document.getElementById("togglePreventionBtn");
  if (toggleBtn) toggleBtn.style.display = "inline-flex";

  // Build sorted prevention queue from distribution
  if (data.distribution) {
    renderDistributionChart(data.distribution);
    preventionQueue = Object.entries(data.distribution)
      .sort((a, b) => b[1] - a[1])
      .slice(0,1)
      .map(([name]) => name);
  } else {
    preventionQueue = data.disease ? [data.disease] : [];
  }

  preventionIndex = 0;
  preventionCache = {};
}

/* ─────────────────────────────────────────────────────────
   SHOW ERROR
───────────────────────────────────────────────────────── */
function showError(title, message, data = {}) {
  resultDisease.innerHTML = `
    <strong style="color:#ef4444">${escHtml(title)}</strong><br>
    <span style="font-size:14px;color:var(--color-text-muted,#666)">${escHtml(message)}</span>
    ${data.confidence_percentage && data.confidence_percentage !== "N/A"
      ? `<br><small style="color:#999">Model confidence: ${escHtml(data.confidence_percentage)}</small>`
      : ""}
  `;
  resultConfidenceText.innerText = "";
  confidenceBar.style.width = "0%";

  const toggleBtn = document.getElementById("togglePreventionBtn");
  if (toggleBtn) toggleBtn.style.display = "none";

  if (data.distribution) renderDistributionChart(data.distribution);
}

/* ─────────────────────────────────────────────────────────
   DISTRIBUTION BAR CHART  (5-class, inside result card)
───────────────────────────────────────────────────────── */
function renderDistributionChart(distribution) {
  if (!distributionSection) return;
  distributionSection.style.display = "block";

  const sorted = Object.entries(distribution).sort((a, b) => b[1] - a[1]);
  const topPct = sorted[0]?.[1] ?? 0;

  distributionSection.innerHTML = `
    <div class="dist-title">Confidence across all classes</div>
    <div class="dist-bars">
      ${sorted.map(([cls, pct], i) => {
        const colour  = CLASS_COLOURS[cls] || "#78909c";
        const isTop   = pct === topPct;
        const label   = cls.replace(/-/g, " ");
        return `
          <div class="dist-row ${isTop ? "dist-row--top" : ""}">
            <div class="dist-label">${escHtml(label)}</div>
            <div class="dist-track">
              <div class="dist-fill"
                   style="background:${colour};width:0%"
                   data-target="${pct.toFixed(2)}">
              </div>
            </div>
            <div class="dist-pct">${pct.toFixed(1)}%</div>
          </div>
        `;
      }).join("")}
    </div>
  `;

  // Animate after paint
  requestAnimationFrame(() => {
    distributionSection.querySelectorAll(".dist-fill").forEach(bar => {
      bar.style.width = `${bar.dataset.target}%`;
    });
  });
}

function clearDistributionChart() {
  if (!distributionSection) return;
  distributionSection.innerHTML = "";
  distributionSection.style.display = "none";
}

/* ─────────────────────────────────────────────────────────
   PREVENTION MODAL  (toggle button + open/close)
───────────────────────────────────────────────────────── */
const toggleBtn          = document.getElementById("togglePreventionBtn");
const preventionModal    = document.getElementById("preventionModal");
const closeModalBtn      = document.getElementById("closePreventionModal");

if (toggleBtn) {
  toggleBtn.addEventListener("click", () => {
    if (!preventionModal) return;
    preventionModal.style.display = "flex";
    preventionIndex = 0;
    openPreventionForIndex(0);
  });
}

if (closeModalBtn) {
  closeModalBtn.addEventListener("click", () => {
    if (preventionModal) preventionModal.style.display = "none";
  });
}

// Close on backdrop click
if (preventionModal) {
  preventionModal.addEventListener("click", (e) => {
    if (e.target === preventionModal) preventionModal.style.display = "none";
  });
}

/* ─────────────────────────────────────────────────────────
   OPEN PREVENTION FOR A SPECIFIC INDEX
───────────────────────────────────────────────────────── */
async function openPreventionForIndex(idx) {
  const diseaseName = preventionQueue[idx];
  if (!diseaseName) return;

  // If cached, render immediately
  if (preventionCache[diseaseName]) {
    renderPrevention(preventionCache[diseaseName]);
    return;
  }

  // Show loader
  const card   = document.getElementById("preventionCard");
  const loader = document.getElementById("preventionLoader");
  if (card)   card.style.display   = "none";
  if (loader) {
    loader.style.display = "block";
    loader.textContent   = `⏳ Loading info for ${diseaseName.replace(/-/g, " ")}…`;
  }

  try {
    const { data: { session } } = await window.supabaseClient.auth.getSession();
    const token = session?.access_token;

    const res = await fetch("/api/prevention", {
      method:  "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ disease_name: diseaseName }),
    });

    const result = await res.json();

    if (res.ok && result.success && result.data) {
      preventionCache[diseaseName] = result.data;
      renderPrevention(result.data);
    } else {
      if (loader) loader.textContent = "⚠️ No prevention data found for this disease.";
    }
  } catch (err) {
    console.error("Prevention fetch error:", err);
    if (loader) loader.textContent = "❌ Could not load prevention data.";
  }
}

/* ─────────────────────────────────────────────────────────
   RENDER PREVENTION CARD
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
    "🌿 " + (data.disease_name || "").replace(/[_-]/g, " ").replace(/[()]/g, "");
  document.getElementById("severityBadge").textContent =
    (data.severity || "").toUpperCase();
  document.getElementById("preventionDesc").textContent = data.description || "";

  const fillList = (id, items) => {
    const ul = document.getElementById(id);
    if (!ul) return;
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

/* ─────────────────────────────────────────────────────────
   UTILITIES
───────────────────────────────────────────────────────── */
function escHtml(str = "") {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}