function toggleTheme() {
  document.body.classList.toggle("dark-mode");

  localStorage.setItem(
    "phytoai_theme",
    document.body.classList.contains("dark-mode") ? "dark" : "light"
  );
}

// Apply saved theme on page load
document.addEventListener("DOMContentLoaded", () => {
  const savedTheme = localStorage.getItem("phytoai_theme");
  
  if (savedTheme === "dark") {
    document.body.classList.add("dark-mode");
  } else if (savedTheme === "light") {
    document.body.classList.remove("dark-mode");
  } else {
    // Default to light mode
    document.body.classList.remove("dark-mode");
  }

  // Create theme toggle button if it doesn't exist
  createThemeToggle();
});

function createThemeToggle() {
  const navbar = document.querySelector(".navbar");
  if (!navbar) return;

  // Check if toggle already exists
  if (document.getElementById("themeToggle")) return;

  const navButtons = navbar.querySelector(".nav-buttons");
  if (!navButtons) return;

  // Create toggle button
  const themeBtn = document.createElement("button");
  themeBtn.id = "themeToggle";
  themeBtn.innerHTML = document.body.classList.contains("dark-mode") ? "☀️" : "🌙";
  themeBtn.onclick = () => {
    toggleTheme();
    themeBtn.innerHTML = document.body.classList.contains("dark-mode") ? "☀️" : "🌙";
  };

  // Insert before auth button or at the end
  const authBtn = navButtons.querySelector("#authBtn");
  if (authBtn) {
    navButtons.insertBefore(themeBtn, authBtn);
  } else {
    navButtons.appendChild(themeBtn);
  }
}

// Re-apply saved theme on page load (in case it's already in progress)
if (localStorage.getItem("phytoai_theme") === "dark") {
  document.body.classList.add("dark-mode");
}
