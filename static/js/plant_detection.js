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

let selectedFile=null;

// camera code start 
/* CAMERA ELEMENTS */

const openCameraBtn = document.getElementById("openCameraBtn");
const cameraVideo = document.getElementById("cameraVideo");
const captureBtn = document.getElementById("captureBtn");
const cameraCanvas = document.getElementById("cameraCanvas");
const cameraBox = document.getElementById("cameraBox");

let cameraStream = null;

// camera code end

/* FILE SELECT */

function handleFileSelect(file){

if(file && file.type.startsWith("image/")){

selectedFile=file;

previewImage.src=URL.createObjectURL(file);
previewImage.style.display="block";

resetBtn.style.display="block";
resultBox.style.display="none";

/* HIDE CAMERA OPTION after image upload (both file and camera upload) */
document.querySelector(".camera-section").style.display="none";

}

}


/* CLICK UPLOAD */

dropZone.addEventListener("click", ()=>{
imageInput.click();
});

imageInput.addEventListener("change",(e)=>{
handleFileSelect(e.target.files[0]);
});


/* RESET */

resetBtn.addEventListener("click",(e)=>{

e.stopPropagation();

selectedFile=null;
imageInput.value="";

previewImage.src="";
previewImage.style.display="none";

resetBtn.style.display="none";
resultBox.style.display="none";

/* SHOW CAMERA OPTION AGAIN after reset is clicked */
document.querySelector(".camera-section").style.display="block";

});


/* DETECT */

detectBtn.addEventListener("click", async ()=>{

if(!selectedFile){
alert("Upload an image first");
return;
}

detectBtn.disabled=true;
loaderContainer.style.display="block";

const formData=new FormData();
formData.append("image",selectedFile);

try{

const { data: { session } } = await window.supabaseClient.auth.getSession();
const token = session ? session.access_token : null;

if (!token) {
    loaderContainer.style.display="none";
    detectBtn.disabled=false;
    alert("Please login first");
    return;
}

const response = await fetch("/api/predict",{
method:"POST",
headers:{
Authorization:`Bearer ${token}`
},
body:formData
});

const data = await response.json();

loaderContainer.style.display="none";
detectBtn.disabled=false;

if(response.ok){

resultBox.style.display="block";

resultDisease.innerText=`Detected: ${data.disease}`;
resultConfidenceText.innerText=`Confidence: ${data.confidence_percentage}`;

confidenceBar.style.width=`${data.confidence*100}%`;

}else{

alert(data.error);

}

}catch(err){

loaderContainer.style.display="none";
detectBtn.disabled=false;

alert("Prediction error");

}

});


/* =========================
   CAMERA OPEN
========================= */

openCameraBtn.addEventListener("click", async ()=>{

try{

cameraStream = await navigator.mediaDevices.getUserMedia({video:true});

cameraVideo.srcObject = cameraStream;
cameraBox.style.display = "block";

}catch(err){

alert("Camera permission denied");

}

});


/* =========================
   CAPTURE PHOTO
========================= */

captureBtn.addEventListener("click", ()=>{

const context = cameraCanvas.getContext("2d");

cameraCanvas.width = cameraVideo.videoWidth;
cameraCanvas.height = cameraVideo.videoHeight;

context.drawImage(cameraVideo,0,0);

cameraCanvas.toBlob((blob)=>{

const file = new File([blob],"camera.jpg",{type:"image/jpeg"});

/* Use existing upload system */
handleFileSelect(file);

/* Stop camera */
if(cameraStream){
cameraStream.getTracks().forEach(track=>track.stop());
}

cameraBox.style.display="none";

});

});