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


/* FILE SELECT */

function handleFileSelect(file){

if(file && file.type.startsWith("image/")){

selectedFile=file;

previewImage.src=URL.createObjectURL(file);
previewImage.style.display="block";

resetBtn.style.display="block";
resultBox.style.display="none";

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