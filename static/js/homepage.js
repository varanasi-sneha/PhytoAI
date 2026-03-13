document.addEventListener("DOMContentLoaded", () => {

const plantDetection = document.getElementById("plantDetection");
const drugClassification = document.getElementById("drugClassification");

if(plantDetection){
plantDetection.onclick = () => {
window.location.href="/plant_detection.html";
};
}

if(drugClassification){
drugClassification.onclick = () => {
window.location.href="/drug_classification.html";
};
}

});