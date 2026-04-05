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

/* ─────────────────────────────────────────
   CAMERA CODE
───────────────────────────────────────── */

// camera code start 
/* CAMERA ELEMENTS */

const openCameraBtn = document.getElementById("openCameraBtn");
const cameraVideo = document.getElementById("cameraVideo");
const captureBtn = document.getElementById("captureBtn");
const cameraCanvas = document.getElementById("cameraCanvas");
const cameraBox = document.getElementById("cameraBox");

let cameraStream = null;

// camera code end


/* ─────────────────────────────────────────
   LOGIN HELPERS
───────────────────────────────────────── */

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


/* ─────────────────────────────────────────
   FILE SELECT
───────────────────────────────────────── */

function handleFileSelect(file){

if(file && file.type.startsWith("image/")){

selectedFile=file;

previewImage.src=URL.createObjectURL(file);
previewImage.style.display="block";

resetBtn.style.display="block";
resultBox.style.display="none";

/* HIDE CAMERA OPTION after image upload */
document.querySelector(".camera-section").style.display="none";

}else if(file){

alert("Please upload a valid image file (JPG, PNG, etc.)");

}

}


/* ─────────────────────────────────────────
   FILE INPUT
───────────────────────────────────────── */

imageInput.addEventListener("change",(e)=>{
handleFileSelect(e.target.files[0]);
});

imageInput.addEventListener("click",(e)=>{
e.stopPropagation();
});


/* ─────────────────────────────────────────
   DROP ZONE CLICK
───────────────────────────────────────── */

dropZone.addEventListener("click",async (e)=>{

if(e.target.closest("#resetBtn")) return;

if(!(await isLoggedIn())){
showLoginPrompt();
return;
}

imageInput.click();

});


/* ─────────────────────────────────────────
   DRAG & DROP
───────────────────────────────────────── */

dropZone.addEventListener("dragover",(e)=>{
e.preventDefault();
dropZone.classList.add("drag-over");
});

dropZone.addEventListener("dragleave",(e)=>{
e.preventDefault();
dropZone.classList.remove("drag-over");
});

dropZone.addEventListener("drop",async (e)=>{

e.preventDefault();
dropZone.classList.remove("drag-over");

if(!(await isLoggedIn())){
showLoginPrompt();
return;
}

const files = e.dataTransfer.files;

if(files.length>0){
handleFileSelect(files[0]);
}

});


/* ─────────────────────────────────────────
   RESET
───────────────────────────────────────── */

resetBtn.addEventListener("click",(e)=>{

e.stopPropagation();

selectedFile=null;
imageInput.value="";

previewImage.src="";
previewImage.style.display="none";

resetBtn.style.display="none";
resultBox.style.display="none";

/* SHOW CAMERA OPTION AGAIN after reset */
document.querySelector(".camera-section").style.display="block";

});


/* ─────────────────────────────────────────
   DETECT
───────────────────────────────────────── */

detectBtn.addEventListener("click", async () => {

if (!selectedFile) {
  alert("Upload an image first");
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

    // ✅ KEEP THIS (prevention feature)
    fetchPrevention(data.disease);

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

// CAMERA OPEN
openCameraBtn.addEventListener("click", async () => {
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({ video: true });
    cameraVideo.srcObject = cameraStream;
    cameraBox.style.display = "block";
  } catch (err) {
    alert("Camera permission denied");
  }
});

// CAPTURE
captureBtn.addEventListener("click", () => {

  const context = cameraCanvas.getContext("2d");

  cameraCanvas.width = cameraVideo.videoWidth;
  cameraCanvas.height = cameraVideo.videoHeight;

  context.drawImage(cameraVideo, 0, 0);

  cameraCanvas.toBlob((blob) => {

    const file = new File([blob], "camera.jpg", { type: "image/jpeg" });

    handleFileSelect(file);

    if (cameraStream) {
      cameraStream.getTracks().forEach(track => track.stop());
    }

    cameraBox.style.display = "none";

  });

});