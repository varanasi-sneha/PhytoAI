// ---------- TAB ----------
function showTab(tab) {
    const tabs = ["overviewTab","historyTab","settingsTab"];
    
    tabs.forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.remove("active");
    });
    
    const target = document.getElementById(tab + "Tab");
    if (target) {
        target.classList.add("active");
    }

    document.querySelectorAll(".tabs button").forEach(btn => {
        btn.classList.remove("active");
    });
    if (event && event.target) {
        event.target.classList.add("active");
    }
}

// ---------- UPLOAD CLICK ----------
function uploadClick() {
    const input = document.getElementById("uploadInput");
    if (input) input.click();
    else alert("Upload input not found");
}

// ---------- CLEAR HISTORY ----------
async function clearHistory() {
    if (!confirm("Are you sure you want to clear all your scan history? This cannot be undone.")) return;

    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) return;

    const token = session.access_token;

    try {
        const res = await fetch("/api/history/clear", {
            method: "DELETE",
            headers: { Authorization: `Bearer ${token}` }
        });

        if (res.ok) {
            alert("✓ Scan history cleared.");
            loadProfile();
        } else {
            const err = await res.json().catch(() => ({}));
            alert("Failed to clear history: " + (err.error || "Unknown error"));
        }
    } catch (e) {
        console.error("Clear history error:", e);
        alert("Network error. Please try again.");
    }
}

// ---------- LOAD PROFILE ----------
async function loadProfile() {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) {
        alert("Login first");
        window.location.href = "/";
        return;
    }

    // -------- NAME --------
    let name = session.user.user_metadata?.name || session.user.user_metadata?.full_name;
    if (!name || name.trim() === "") {
        name = session.user.email.split("@")[0];
    }
    document.getElementById("name").innerText = name;
    document.getElementById("email").innerText = session.user.email;

    // initials
    const initials = name.split(" ").map(n => n[0]).join("").toUpperCase();
    const fallback = document.getElementById("avatarFallback");
    const img = document.getElementById("profileImg");
    fallback.innerText = initials;

    // -------- IMAGE LOAD --------
    const path = `${session.user.id}.jpg`;
    const { data } = supabaseClient.storage.from("profile_pics").getPublicUrl(path);

    img.style.display = "none";
    fallback.style.display = "flex";

    if (data?.publicUrl) {
        img.src = data.publicUrl + "?t=" + Date.now();
        img.onload = () => { img.style.display = "block"; fallback.style.display = "none"; };
    }

    // -------- HISTORY + OVERVIEW --------
    const token = session.access_token;
    let historyList = [];
    try {
        const res = await fetch("/api/history", { headers: { Authorization: `Bearer ${token}` } });
        if (res.ok) {
            const rawData = await res.json();
            if (Array.isArray(rawData)) { historyList = rawData; }
            else if (rawData && Array.isArray(rawData.data)) { historyList = rawData.data; }
        }
    } catch (e) {
        console.error("Failed to fetch history", e);
    }

    document.getElementById("stats").innerText = `${historyList.length}`;

    // -------- OVERVIEW TAB --------
    const overviewTab = document.getElementById("overviewTab");
    overviewTab.innerHTML = `
        <h3>Overview</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 32px;">
            <div style="background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-accent) 100%); color: white; padding: 20px; border-radius: 12px; text-align: center;">
                <div style="font-size: 32px; font-weight: 700;">${historyList.length}</div>
                <div style="font-size: 13px; opacity: 0.9;">Total Scans</div>
            </div>
            <div style="background: linear-gradient(135deg, var(--color-accent) 0%, #7cb342 100%); color: white; padding: 20px; border-radius: 12px; text-align: center;">
                <div style="font-size: 32px; font-weight: 700;">${historyList.length > 0 ? (historyList.reduce((sum, h) => sum + (h.confidence || 0), 0) / historyList.length * 100).toFixed(1) : '0'}%</div>
                <div style="font-size: 13px; opacity: 0.9;">Avg Confidence</div>
            </div>
        </div>
        <h4 style="color: var(--color-primary); margin-bottom: 16px; font-weight: 700;">Scan Confidence Trend</h4>
        <canvas id="chart" style="max-height: 300px;"></canvas>
    `;

    setTimeout(() => {
        const ctx = document.getElementById("chart");
        if (!ctx) return;
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: historyList.map((_, i) => `Scan ${i+1}`),
                datasets: [{
                    label: 'Confidence %',
                    data: historyList.map(h => (h.confidence || 0) * 100),
                    borderColor: '#1a5d42',
                    backgroundColor: 'rgba(26, 93, 66, 0.05)',
                    borderWidth: 3, fill: true, tension: 0.4,
                    pointBackgroundColor: '#1a5d42', pointBorderColor: '#fff',
                    pointBorderWidth: 2, pointRadius: 5, pointHoverRadius: 7,
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: { legend: { display: true, labels: { usePointStyle: true, padding: 15 } } },
                scales: { y: { beginAtZero: true, max: 100, ticks: { callback: (v) => v + '%' } } }
            }
        });
    }, 100);

    // -------- HISTORY TAB --------
    const h = document.getElementById("historyTab");

    if (historyList.length === 0) {
        h.innerHTML = `
            <h3>Scan History</h3>
            <p style="color: var(--color-text-muted); text-align: center; padding: 40px 20px;">
                No scans yet. Start by detecting a plant disease!
            </p>`;
    } else {
        h.innerHTML = `
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; flex-wrap: wrap; gap: 12px;">
                <h3 style="margin: 0;">Scan History</h3>
                <button
                    onclick="clearHistory()"
                    style="
                        background: rgba(239,68,68,0.08);
                        color: #ef4444;
                        border: 1px solid rgba(239,68,68,0.2);
                        border-radius: 10px;
                        padding: 8px 16px;
                        font-size: 13px;
                        font-weight: 700;
                        cursor: pointer;
                        transition: all 0.2s ease;
                    "
                    onmouseover="this.style.background='rgba(239,68,68,0.15)'"
                    onmouseout="this.style.background='rgba(239,68,68,0.08)'"
                >
                    🗑️ Clear All History
                </button>
            </div>`;

        historyList.forEach(item => {
            const div = document.createElement("div");
            div.className = "history-card";
            const itemDisease = item.prediction || item.disease || "Unknown";
            const disease = itemDisease.replace(/[_-]/g, " ").replace(/\(|\)/g, "");
            const conf = item.confidence || 0;
            const confidence = (conf * 100).toFixed(1);
            const dateStr = item.created_at ? new Date(item.created_at).toLocaleDateString() : 'Recent';
            div.innerHTML = `
                <div>
                    <div class="date">🕒 ${dateStr}</div>
                    <strong>🌿 ${disease}</strong>
                </div>
                <div class="confidence">${confidence}% Confidence</div>
            `;
            h.appendChild(div);
        });
    }

    // -------- SETTINGS TAB --------
    document.getElementById("settingsTab").innerHTML = `
        <h3>Account Settings</h3>
        <div class="settings-form">
            <div>
                <label style="display: block; font-weight: 600; margin-bottom: 8px; color: var(--color-primary);">Update Name</label>
                <input id="nameInput" placeholder="Enter your name" type="text" value="${name}">
            </div>
            <div>
                <button class="primary" onclick="updateName()">✓ Update Name</button>
            </div>
            <hr style="margin: 32px 0; border: none; border-top: 1px solid var(--color-border);">
            <div>
                <label style="display: block; font-weight: 600; margin-bottom: 16px; color: var(--color-primary);">Theme Preference</label>
                <button class="secondary" onclick="toggleThemeAndLog()">🌓 Toggle Dark Mode</button>
            </div>
            <hr style="margin: 32px 0; border: none; border-top: 1px solid var(--color-border);">
            <div>
                <label style="display: block; font-weight: 600; margin-bottom: 16px; color: #ef4444;">Danger Zone</label>
                <button class="danger-btn" onclick="logout()">🚪 Logout</button>
            </div>
        </div>
    `;
}

window.toggleThemeAndLog = function() {
    if (typeof toggleTheme === 'function') toggleTheme();
};

// ---------- UPDATE NAME ----------
async function updateName() {
    const name = document.getElementById("nameInput").value.trim();
    if (!name) return alert("Please enter a name");
    const { error } = await supabaseClient.auth.updateUser({ data: { name: name } });
    if (error) { alert("Update failed: " + error.message); return; }
    alert("✓ Name updated successfully!");
    loadProfile();
}

// ---------- FILE UPLOAD (JPEG ONLY) ----------
document.addEventListener("DOMContentLoaded", () => {
    const input = document.getElementById("uploadInput");
    if (!input) return;
    input.addEventListener("change", async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        if (!["image/jpeg", "image/jpg"].includes(file.type)) { alert("Only JPG/JPEG allowed"); return; }
        const { data: { session } } = await supabaseClient.auth.getSession();
        const path = `${session.user.id}.jpg`;
        const { error } = await supabaseClient.storage.from("profile_pics").upload(path, file, { upsert: true });
        if (error) { alert("Upload failed: " + error.message); return; }
        alert("✓ Photo uploaded successfully!");
        loadProfile();
    });
});

async function goHome() { window.location.href = "/"; }

async function logout() {
    if (!confirm("Are you sure you want to logout?")) return;
    await supabaseClient.auth.signOut();
    window.location.href = "/";
}

loadProfile();