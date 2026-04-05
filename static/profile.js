// ---------- TAB ----------
function showTab(tab) {
    ["overviewTab","historyTab","settingsTab"].forEach(id=>{
        const el = document.getElementById(id);
        if (el) el.style.display = "none";
    });
    const target = document.getElementById(tab + "Tab");
    if (target) target.style.display = "block";
}

// ---------- UPLOAD CLICK ----------
function uploadClick() {
    const input = document.getElementById("uploadInput");
    if (input) input.click();
    else alert("Upload input not found");
}

// ---------- LOAD PROFILE ----------
async function loadProfile() {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) {
        alert("Login first");
        return;
    }

    // -------- NAME (use `name` from metadata) --------
    let name = session.user.user_metadata?.name;

    // fallback → use email prefix if no name
    if (!name || name.trim() === "") {
        name = session.user.email.split("@")[0];
    }

    document.getElementById("name").innerText = name;
    document.getElementById("email").innerText = session.user.email;

    // initials
    const initials = name
        .split(" ")
        .map(n => n[0])
        .join("")
        .toUpperCase();

    const fallback = document.getElementById("avatarFallback");
    const img = document.getElementById("profileImg");

    fallback.innerText = initials;

    // -------- IMAGE LOAD --------
    const path = `${session.user.id}.jpg`; // we will use JPG

    const { data } = supabaseClient.storage
        .from("profile_pics")
        .getPublicUrl(path);

    // default: show initials
    img.style.display = "none";
    fallback.style.display = "flex";

    if (data?.publicUrl) {
        img.src = data.publicUrl + "?t=" + Date.now();

        img.onload = () => {
            img.style.display = "block";
            fallback.style.display = "none";
        };
    }

    // -------- HISTORY + OVERVIEW --------
    const token = session.access_token;

    const res = await fetch("/api/history", {
        headers: { Authorization: `Bearer ${token}` }
    });

    const history = await res.json();

    document.getElementById("stats").innerText =
        `Total scans: ${history.length}`;

    // overview
    document.getElementById("overviewTab").innerHTML = `
        <h3>Overview</h3>
        <p>Total scans: ${history.length}</p>
        <p>Last scan: ${history[0]?.prediction || "None"}</p>
        <canvas id="chart"></canvas>
    `;

    setTimeout(() => {
        const ctx = document.getElementById("chart");
        if (!ctx) return;
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: history.map((_, i) => `Scan ${i+1}`),
                datasets: [{
                    label: 'Confidence',
                    data: history.map(h => h.confidence * 100)
                }]
            }
        });
    }, 100);

    // history
    const h = document.getElementById("historyTab");
    h.innerHTML = "<h3>History</h3>";

    history.forEach(item => {
        const div = document.createElement("div");
        div.className = "history-card";

        const disease = item.prediction.replace(/_/g, " ");

        div.innerHTML = `
            <strong>${disease}</strong><br>
            ${(item.confidence * 100).toFixed(2)}%
        `;

        h.appendChild(div);
    });

    // settings
    document.getElementById("settingsTab").innerHTML = `
        <h3>Settings</h3>
        <input id="nameInput" placeholder="New name">
        <button onclick="updateName()">Update</button>
        <br><br>
        <button onclick="logout()">Logout</button>
    `;
}

// ---------- UPDATE NAME (use `name`) ----------
async function updateName() {
    const name = document.getElementById("nameInput").value;
    if (!name) return alert("Enter name");

    const { error } = await supabaseClient.auth.updateUser({
        data: { name: name }
    });

    if (error) {
        console.log(error);
        alert("Update failed");
        return;
    }

    alert("Updated!");
    loadProfile();
}

// ---------- FILE UPLOAD (JPEG ONLY) ----------
document.addEventListener("DOMContentLoaded", () => {
    const input = document.getElementById("uploadInput");

    if (!input) {
        console.log("uploadInput not found");
        return;
    }

    input.addEventListener("change", async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        // allow only jpeg/jpg
        if (!["image/jpeg", "image/jpg"].includes(file.type)) {
            alert("Only JPG/JPEG allowed");
            return;
        }

        const { data: { session } } = await supabaseClient.auth.getSession();

        const path = `${session.user.id}.jpg`;

        const { error } = await supabaseClient.storage
            .from("profile_pics")
            .upload(path, file, { upsert: true });

        if (error) {
            console.log(error);
            alert("Upload failed");
            return;
        }

        alert("Uploaded!");
        loadProfile();
    });
});

async function goHome() {
    window.location.href = "/";
}

// ---------- LOGOUT ----------
async function logout() {
    await supabaseClient.auth.signOut();
    window.location.href = "/";
}

async function goHome() {
    
    window.location.href = "/";
}

// ---------- INIT ----------
loadProfile();